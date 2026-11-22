<#
.SYNOPSIS
    Starts a staged client (Tango.exe) that connects to a server, optionally under network emulation,
    and returns its process.

.DESCRIPTION
    -NetEmulation picks a [PacketSimulationProfile.<Name>] section from Config/DefaultEngine.ini and is
    applied on this client only (both directions). Switch at runtime from the client console (~):
        NetEmulation.PktEmulationProfile Bad
        NetEmulation.Off
    Keep the ValidateSet below in sync with the profile sections in DefaultEngine.ini.

.EXAMPLE
    ./Scripts/StartClient.ps1
    ./Scripts/StartClient.ps1 -Name A -NetEmulation Good
    ./Scripts/StartClient.ps1 -Name B -NetEmulation Bad
#>
param(
    [string]$Address = '127.0.0.1:7777',
    [ValidateSet('Off', 'Good', 'Average', 'Bad')]
    [string]$NetEmulation = 'Off',
    # Instance name; keeps logs of several clients apart.
    [string]$Name = 'Client',
    # Absolute log path. Default: Saved\Logs\Local\Client-<Name>.log
    [string]$LogPath,
    [int]$ResX = 1280,
    [int]$ResY = 720
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'TangoTestCommon.psm1') -Force

if (-not $LogPath) { $LogPath = Get-TangoLogPath -Folder 'Local' -FileName "Client-$Name.log" }
Remove-Item $LogPath -ErrorAction SilentlyContinue

$exe = Get-TangoExe -Role Client
Write-Host "Starting client '$Name' -> $Address, NetEmulation=$NetEmulation (log: $LogPath)"
Start-Process $exe -PassThru -ArgumentList @(
    $Address, '-windowed', "-ResX=$ResX", "-ResY=$ResY",
    "-PktEmulationProfile=$NetEmulation",
    "-abslog=`"$LogPath`""
)
