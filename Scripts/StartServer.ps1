<#
.SYNOPSIS
    Starts the staged dedicated server (TangoServer.exe) and returns its process.

.EXAMPLE
    ./Scripts/StartServer.ps1
    ./Scripts/StartServer.ps1 -Port 7778
#>
param(
    [int]$Port = 7777,
    # Absolute log path. Default: Saved\Logs\Local\Server.log
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'TangoTestCommon.psm1') -Force

if (-not $LogPath) { $LogPath = Get-TangoLogPath -Folder 'Local' -FileName 'Server.log' }
Remove-Item $LogPath -ErrorAction SilentlyContinue

$exe = Get-TangoExe -Role Server
Write-Host "Starting server on port $Port (log: $LogPath)"
Start-Process $exe -PassThru -ArgumentList @('-log', "-port=$Port", "-abslog=`"$LogPath`"")
