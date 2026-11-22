<#
.SYNOPSIS
    Launches the staged dedicated server and client locally and judges the connection from log markers.

.DESCRIPTION
    Verifies the connection only: TangoServer.exe listens on the port, Tango.exe connects,
    the server logs "Join succeeded", and no pawn spawn failure is logged.
    Client-side possession is confirmed manually with `DisplayAll PlayerController Pawn`
    (use -KeepRunning to leave both processes open for that).
    Network emulation is verified separately by TestNetEmulation.ps1.

.EXAMPLE
    ./Scripts/TestConnection.ps1
    ./Scripts/TestConnection.ps1 -KeepRunning
#>
param(
    [int]$Port = 7777,
    [int]$TimeoutSec = 120,
    [switch]$KeepRunning
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'TangoTestCommon.psm1') -Force

$serverLog = Get-TangoLogPath -Folder 'ConnectTest' -FileName 'Server.log'
$clientLog = Get-TangoLogPath -Folder 'ConnectTest' -FileName 'Client.log'
$markers = Get-TangoConnectionMarkers -Port $Port

$server = & (Join-Path $PSScriptRoot 'StartServer.ps1') -Port $Port -LogPath $serverLog
$client = & (Join-Path $PSScriptRoot 'StartClient.ps1') -Address "127.0.0.1:$Port" -LogPath $clientLog

try {
    $result = Wait-TangoJudgment -TimeoutSec $TimeoutSec -Judge {
        Test-TangoConnection -ServerLog (Read-TangoLog $serverLog) -ClientLog (Read-TangoLog $clientLog) -Markers $markers
    }
}
finally {
    if (-not $KeepRunning) { Stop-TangoProcess $client, $server }
}

Write-TangoResult $result
Write-Host "Logs: $serverLog"
Write-Host "      $clientLog"
if ($KeepRunning -and $result.Status -eq 'Pass') {
    Write-Host 'Processes left running. In the client console (~) run: DisplayAll PlayerController Pawn'
}
exit ([int]($result.Status -ne 'Pass'))
