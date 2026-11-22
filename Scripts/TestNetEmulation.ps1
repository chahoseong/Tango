<#
.SYNOPSIS
    Verifies that client-side network emulation profiles are applied, by measuring RTT and loss.

.DESCRIPTION
    For each profile: start server + client (StartServer/StartClient), wait for the connection,
    check the profile was applied, skip a warm-up, then average the once-per-second
    `LogTangoNet: NetStats ...` lines written by UTangoNetStatsSubsystem and compare them to the
    expectations below.

    RTT on one PC is not 0 even without emulation (tick/ack timing), so expectations are
    "baseline + added RTT". The baseline is the mean RTT of the Off run, which always runs first.

    Connection problems are not diagnosed here: if the connection fails, run TestConnection.ps1.

.EXAMPLE
    ./Scripts/TestNetEmulation.ps1
    ./Scripts/TestNetEmulation.ps1 -NetEmulation Bad -MeasureSec 120
#>
param(
    [ValidateSet('Off', 'Good', 'Average', 'Bad')]
    [string[]]$NetEmulation = @('Off', 'Good', 'Average', 'Bad'),
    [int]$Port = 7777,
    [int]$WarmupSec = 5,
    # ~20 packets/s under Bad -> 60 s gives ~1200 samples, so 5% loss measures within about +-0.6 %p (1 sigma).
    [int]$MeasureSec = 60,
    [int]$ConnectTimeoutSec = 120
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'TangoTestCommon.psm1') -Force

# Expected values per profile. Keep in sync with [PacketSimulationProfile.*] in Config/DefaultEngine.ini.
#   Emu       : configured values as printed by the overlay (proves the profile really is in effect)
#   AddedRtt  : RTT the profile adds on top of the Off baseline (ms), with tolerance RttTol
#   Loss*     : allowed range for the mean loss in EACH direction (percent).
#               Precision depends on packets/s (drops from ~29 to ~20 as the profile gets worse);
#               see the pkt/s column before tightening these ranges or shortening MeasureSec.
$Expected = @{
    Off     = @{ Emu = 'Out=0-0 In=0-0 Loss=0/0';         AddedRtt = 0;   RttTol = $null; LossMin = 0; LossMax = 0.5 }
    Good    = @{ Emu = 'Out=15-15 In=15-15 Loss=0/0';     AddedRtt = 30;  RttTol = 10;    LossMin = 0; LossMax = 0.5 }
    Average = @{ Emu = 'Out=45-55 In=45-55 Loss=1/1';     AddedRtt = 100; RttTol = 10;    LossMin = 0; LossMax = 3 }
    Bad     = @{ Emu = 'Out=88-112 In=88-112 Loss=5/5';   AddedRtt = 200; RttTol = 15;    LossMin = 3; LossMax = 7 }
}

$StatsPattern = 'NetStats Emu=\[(?<emu>[^\]]*)\] RttMs=(?<rtt>[\d.]+) JitterMs=(?<jit>[\d.]+) InLoss=(?<in>[\d.]+) OutLoss=(?<out>[\d.]+) InPps=(?<inpps>\d+) OutPps=(?<outpps>\d+)'
$Inv = [System.Globalization.CultureInfo]::InvariantCulture

function Get-NetStatsSamples {
    param([string]$ClientLog)
    foreach ($m in [regex]::Matches($ClientLog, $StatsPattern)) {
        [pscustomobject]@{
            Emu     = $m.Groups['emu'].Value
            Rtt     = [double]::Parse($m.Groups['rtt'].Value, $Inv)
            Jitter  = [double]::Parse($m.Groups['jit'].Value, $Inv)
            InLoss  = [double]::Parse($m.Groups['in'].Value, $Inv)
            OutLoss = [double]::Parse($m.Groups['out'].Value, $Inv)
            InPps   = [int]$m.Groups['inpps'].Value
            OutPps  = [int]$m.Groups['outpps'].Value
        }
    }
}

function Measure-Profile {
    <# Runs one profile and returns the averaged measurement, or a failure reason. #>
    param([string]$ProfileName)

    $serverLog = Get-TangoLogPath -Folder 'EmulationTest' -FileName "Server-$ProfileName.log"
    $clientLog = Get-TangoLogPath -Folder 'EmulationTest' -FileName "Client-$ProfileName.log"
    $markers = Get-TangoConnectionMarkers -Port $Port

    $server = & (Join-Path $PSScriptRoot 'StartServer.ps1') -Port $Port -LogPath $serverLog
    $client = & (Join-Path $PSScriptRoot 'StartClient.ps1') -Address "127.0.0.1:$Port" -NetEmulation $ProfileName -LogPath $clientLog
    try {
        $conn = Wait-TangoJudgment -TimeoutSec $ConnectTimeoutSec -Judge {
            Test-TangoConnection -ServerLog (Read-TangoLog $serverLog) -ClientLog (Read-TangoLog $clientLog) -Markers $markers
        }
        if ($conn.Status -ne 'Pass') {
            return [pscustomobject]@{ Error = "connection failed at $($conn.Stage) - run TestConnection.ps1 for details" }
        }

        $clientText = Read-TangoLog $clientLog
        if (-not $clientText.Contains("Applying EmulationProfile $ProfileName")) {
            return [pscustomobject]@{ Error = "client log has no 'Applying EmulationProfile $ProfileName'" }
        }
        if ($clientText.Contains("EmulationProfile [PacketSimulationProfile.$ProfileName] was not found")) {
            return [pscustomobject]@{ Error = "profile section [PacketSimulationProfile.$ProfileName] not found in the staged config" }
        }

        $needed = $WarmupSec + $MeasureSec
        $wait = Wait-TangoJudgment -TimeoutSec ($needed + 30) -Judge {
            $n = @(Get-NetStatsSamples (Read-TangoLog $clientLog)).Count
            if ($n -ge $needed) { [pscustomobject]@{ Status = 'Pass'; Stage = 'Sampled'; Reason = '' } }
            else { [pscustomobject]@{ Status = 'Pending'; Stage = "Sampling ($n/$needed)"; Reason = '' } }
        }
        if ($wait.Status -ne 'Pass') {
            return [pscustomobject]@{ Error = "$($wait.Reason) - is UTangoNetStatsSubsystem in this build?" }
        }

        $samples = @(Get-NetStatsSamples (Read-TangoLog $clientLog)) | Select-Object -Skip $WarmupSec -First $MeasureSec
        $avg = { param($prop) ($samples | Measure-Object -Property $prop -Average).Average }
        [pscustomobject]@{
            Error   = $null
            Emu     = ($samples | Select-Object -Last 1).Emu
            Rtt     = & $avg 'Rtt'
            Jitter  = & $avg 'Jitter'
            InLoss  = & $avg 'InLoss'
            OutLoss = & $avg 'OutLoss'
            InPps   = & $avg 'InPps'
            OutPps  = & $avg 'OutPps'
        }
    }
    finally {
        Stop-TangoProcess $client, $server
        Start-Sleep -Seconds 2   # let the port close before the next run
    }
}

function Test-Measurement {
    <# Compares one measurement to its expectation. Returns a list of failure reasons (empty = pass). #>
    param([string]$ProfileName, $M, [double]$Baseline)

    $e = $Expected[$ProfileName]
    $fails = @()
    if ($M.Emu -ne $e.Emu) { $fails += "configured '$($M.Emu)' != expected '$($e.Emu)'" }
    if ($null -ne $e.RttTol) {
        $target = $Baseline + $e.AddedRtt
        if ([math]::Abs($M.Rtt - $target) -gt $e.RttTol) {
            $fails += ('RTT {0:N1} not within {1:N1} +- {2}' -f $M.Rtt, $target, $e.RttTol)
        }
    }
    foreach ($dir in 'InLoss', 'OutLoss') {
        $v = $M.$dir
        if ($v -lt $e.LossMin -or $v -gt $e.LossMax) {
            $fails += ('{0} {1:N2}% not within {2}-{3}%' -f $dir, $v, $e.LossMin, $e.LossMax)
        }
    }
    $fails
}

# --- Run -------------------------------------------------------------------------------------

# The baseline comes from the Off run, so Off always runs first.
$profiles = @('Off') + @($NetEmulation | Where-Object { $_ -ne 'Off' })

$baseline = $null
$rows = @()
$allPassed = $true

foreach ($p in $profiles) {
    Write-Host "`n=== $p ===" -ForegroundColor Cyan
    $m = Measure-Profile -ProfileName $p
    if ($m.Error) {
        Write-TangoResult ([pscustomobject]@{ Status = 'Fail'; Stage = $p; Reason = $m.Error })
        $allPassed = $false
        if ($p -eq 'Off') { break }   # no baseline -> nothing else can be judged
        continue
    }
    if ($p -eq 'Off') { $baseline = $m.Rtt }

    $fails = @(Test-Measurement -ProfileName $p -M $m -Baseline $baseline)
    $status = if ($fails.Count -eq 0) { 'Pass' } else { 'Fail' }
    if ($status -eq 'Fail') { $allPassed = $false }
    Write-TangoResult ([pscustomobject]@{ Status = $status; Stage = $p; Reason = ($fails -join '; ') })

    $rows += [pscustomobject]@{
        Profile   = $p
        Result    = $status.ToUpper()
        'RTT ms'  = '{0:N1}' -f $m.Rtt
        'Target'  = if ($p -eq 'Off') { 'baseline' } else { '{0:N1}' -f ($baseline + $Expected[$p].AddedRtt) }
        'Jitter'  = '{0:N1}' -f $m.Jitter
        'In loss' = '{0:N2}%' -f $m.InLoss
        'Out loss'= '{0:N2}%' -f $m.OutLoss
        'pkt/s in/out' = '{0:N0}/{1:N0}' -f $m.InPps, $m.OutPps
        Configured = $m.Emu
    }
}

Write-Host ''
$rows | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
Write-Host "Logs: $(Split-Path (Get-TangoLogPath -Folder 'EmulationTest' -FileName 'x'))"
exit ([int](-not $allPassed))
