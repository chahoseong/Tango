<#
    Shared helpers for the Tango launch/test scripts.
    Imported by StartServer.ps1, StartClient.ps1, TestConnection.ps1 and TestNetEmulation.ps1.
#>

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$StagedRoot  = Join-Path $ProjectRoot 'Saved\StagedBuilds'

# Real binaries, not the bootstrap launchers at the staging root: a launcher only spawns the real exe
# as a child, so stopping the launcher would leave the server/client running.
$ServerExe = Join-Path $StagedRoot 'WindowsServer\Tango\Binaries\Win64\TangoServer.exe'
$ClientExe = Join-Path $StagedRoot 'Windows\Tango\Binaries\Win64\Tango.exe'

function Get-TangoExe {
    param([ValidateSet('Server', 'Client')][string]$Role)
    $exe = if ($Role -eq 'Server') { $ServerExe } else { $ClientExe }
    if (-not (Test-Path $exe)) { throw "Missing staged $Role executable: $exe (run BuildCookRun first)" }
    $exe
}

function Get-TangoLogPath {
    <# Absolute log path under Saved\Logs\<Folder>; creates the folder. #>
    param([string]$Folder, [string]$FileName)
    $dir = Join-Path $ProjectRoot "Saved\Logs\$Folder"
    New-Item -ItemType Directory -Force $dir | Out-Null
    Join-Path $dir $FileName
}

function Get-TangoConnectionMarkers {
    <# Log markers in the order the connection progresses. Forbidden markers fail a run if they appear. #>
    param([int]$Port = 7777)
    @{
        ServerListening = "IpNetDriver listening on port $Port"
        ClientWelcomed  = 'Welcomed by server (Level: /Game/Maps/L_Entry'
        ServerJoined    = 'Join succeeded:'
        Forbidden       = @('Failed to spawn Pawn', 'Couldn''t spawn player')
    }
}

function Test-TangoConnection {
    <#
    Judge the connection from the two log texts.
    Returns [pscustomobject]@{ Status = 'Pass' | 'Fail' | 'Pending'; Stage; Reason }.
    #>
    param([string]$ServerLog, [string]$ClientLog, [hashtable]$Markers)

    # A forbidden marker fails the run right away: nothing later can fix a failed pawn spawn.
    foreach ($bad in $Markers.Forbidden) {
        if ($ServerLog.Contains($bad)) {
            return [pscustomobject]@{ Status = 'Fail'; Stage = 'Spawn'; Reason = "Server logged '$bad'" }
        }
    }

    # Walk the stages in connection order; the first missing marker is where we are waiting.
    # .Contains() is a literal match (-match would treat '(' in the markers as regex).
    $stages = @(
        @{ Name = 'ServerListening'; Log = $ServerLog; Marker = $Markers.ServerListening }
        @{ Name = 'ClientWelcomed';  Log = $ClientLog; Marker = $Markers.ClientWelcomed }
        @{ Name = 'ServerJoined';    Log = $ServerLog; Marker = $Markers.ServerJoined }
    )
    foreach ($s in $stages) {
        if (-not $s.Log.Contains($s.Marker)) {
            return [pscustomobject]@{ Status = 'Pending'; Stage = $s.Name; Reason = "missing '$($s.Marker)'" }
        }
    }
    [pscustomobject]@{ Status = 'Pass'; Stage = 'Done'; Reason = 'listening, welcomed and joined markers all present' }
}

function Read-TangoLog {
    param([string]$Path)
    if (Test-Path $Path) { Get-Content $Path -Raw } else { '' }
}

function Wait-TangoJudgment {
    <#
    Polls $Judge (a scriptblock returning a Status/Stage/Reason object) every 500 ms until it is not
    'Pending' or $TimeoutSec elapses. On timeout returns Fail with the stage it was still waiting on.
    #>
    param([scriptblock]$Judge, [int]$TimeoutSec)

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $last = $null
    while ((Get-Date) -lt $deadline) {
        $last = & $Judge
        if ($last.Status -ne 'Pending') { return $last }
        Start-Sleep -Milliseconds 500
    }
    [pscustomobject]@{ Status = 'Fail'; Stage = $last.Stage; Reason = "Timed out after $TimeoutSec s while waiting: $($last.Stage)" }
}

function Stop-TangoProcess {
    param([System.Diagnostics.Process[]]$Process)
    foreach ($p in $Process) { if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
}

function Write-TangoResult {
    param($Result)
    $color = if ($Result.Status -eq 'Pass') { 'Green' } else { 'Red' }
    Write-Host ("[{0}] stage={1} {2}" -f $Result.Status.ToUpper(), $Result.Stage, $Result.Reason) -ForegroundColor $color
}

Export-ModuleMember -Function Get-TangoExe, Get-TangoLogPath, Get-TangoConnectionMarkers, Test-TangoConnection,
    Read-TangoLog, Wait-TangoJudgment, Stop-TangoProcess, Write-TangoResult
