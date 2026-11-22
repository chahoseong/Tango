<#
.SYNOPSIS
    Launches the staged dedicated server and client locally and judges the connection from log markers.

.DESCRIPTION
    Completion criterion: TangoServer.exe listens on 7777, Tango.exe connects to 127.0.0.1:7777,
    the server logs "Join succeeded", and no pawn spawn failure is logged.
    Client-side possession is confirmed manually with `DisplayAll PlayerController Pawn`
    (use -KeepRunning to leave both processes open for that).

.EXAMPLE
    ./Scripts/TestConnection.ps1
    ./Scripts/TestConnection.ps1 -KeepRunning
#>
param(
    [string]$StagedRoot = (Join-Path $PSScriptRoot '..\Saved\StagedBuilds'),
    [int]$Port = 7777,
    [int]$TimeoutSec = 120,
    [switch]$KeepRunning
)

$ErrorActionPreference = 'Stop'

# Markers in the order the connection progresses. "Forbidden" markers fail the run if they ever appear.
$Markers = @{
    ServerListening = "IpNetDriver listening on port $Port"
    ClientWelcomed  = 'Welcomed by server (Level: /Game/Maps/L_Entry'
    ServerJoined    = 'Join succeeded:'
    Forbidden       = @('Failed to spawn Pawn', 'Couldn''t spawn player')
}

function Test-ConnectionMarkers {
    <#
    Judge the current state of the run from the two log texts.
    Return [pscustomobject]@{ Status = 'Pass' | 'Fail' | 'Pending'; Stage = <string>; Reason = <string> }
      - Pass    : every required marker is present and no forbidden marker appeared -> stop polling
      - Fail    : something definitively went wrong (e.g. forbidden marker)        -> stop polling
      - Pending : not there yet, keep polling; Stage tells which step we are waiting on (used on timeout)
    #>
    param(
        [string]$ServerLog,
        [string]$ClientLog
    )

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

function Wait-Judgment {
    param([string]$ServerLogPath, [string]$ClientLogPath, [datetime]$Deadline)

    $last = $null
    while ((Get-Date) -lt $Deadline) {
        $server = if (Test-Path $ServerLogPath) { Get-Content $ServerLogPath -Raw } else { '' }
        $client = if (Test-Path $ClientLogPath) { Get-Content $ClientLogPath -Raw } else { '' }
        $last = Test-ConnectionMarkers -ServerLog $server -ClientLog $client
        if ($last.Status -ne 'Pending') { return $last }
        Start-Sleep -Milliseconds 500
    }
    [pscustomobject]@{ Status = 'Fail'; Stage = $last.Stage; Reason = "Timed out after $TimeoutSec s while waiting: $($last.Stage)" }
}

# --- Launch -------------------------------------------------------------------------------------

# Launch the real binaries, not the bootstrap launchers at the staging root: a launcher only spawns
# the real exe as a child, so stopping the launcher would leave the server/client running.
$serverExe = Join-Path $StagedRoot 'WindowsServer\Tango\Binaries\Win64\TangoServer.exe'
$clientExe = Join-Path $StagedRoot 'Windows\Tango\Binaries\Win64\Tango.exe'
foreach ($exe in $serverExe, $clientExe) {
    if (-not (Test-Path $exe)) { throw "Missing staged executable: $exe (run BuildCookRun first)" }
}

$logDir = Join-Path $PSScriptRoot '..\Saved\Logs\ConnectTest'
New-Item -ItemType Directory -Force $logDir | Out-Null
$logDir = (Resolve-Path $logDir).Path
$serverLog = Join-Path $logDir 'Server.log'
$clientLog = Join-Path $logDir 'Client.log'
Remove-Item $serverLog, $clientLog -ErrorAction SilentlyContinue

Write-Host "Starting server on port $Port ..."
$server = Start-Process $serverExe -PassThru -ArgumentList @('-log', "-port=$Port", "-abslog=`"$serverLog`"")

Write-Host "Starting client -> 127.0.0.1:$Port ..."
$client = Start-Process $clientExe -PassThru -ArgumentList @("127.0.0.1:$Port", '-windowed', '-ResX=1280', '-ResY=720', "-abslog=`"$clientLog`"")

try {
    $result = Wait-Judgment -ServerLogPath $serverLog -ClientLogPath $clientLog -Deadline (Get-Date).AddSeconds($TimeoutSec)
}
finally {
    if (-not $KeepRunning) {
        foreach ($p in $client, $server) { if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
    }
}

# --- Report -------------------------------------------------------------------------------------

$color = if ($result.Status -eq 'Pass') { 'Green' } else { 'Red' }
Write-Host ("[{0}] stage={1} {2}" -f $result.Status.ToUpper(), $result.Stage, $result.Reason) -ForegroundColor $color
Write-Host "Logs: $serverLog"
Write-Host "      $clientLog"
if ($KeepRunning -and $result.Status -eq 'Pass') {
    Write-Host 'Processes left running. In the client console (~) run: DisplayAll PlayerController Pawn'
}
exit ([int]($result.Status -ne 'Pass'))
