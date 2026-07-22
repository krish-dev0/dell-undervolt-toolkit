#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$InstallDirectory = '',
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Toolkit.Common.psm1') -Force -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is not set. Supply -InstallDirectory explicitly.'
    }
    $InstallDirectory = Join-Path $env:LOCALAPPDATA 'DellUndervoltToolkit'
}

$installFull = [System.IO.Path]::GetFullPath($InstallDirectory)
if (-not (Test-Path -LiteralPath $installFull -PathType Container)) {
    Write-Host "Toolkit installation was not found at '$installFull'."
    return
}

Assert-ToolkitSafeRemovalPath -Path $installFull
if (-not $Force) {
    $confirmation = Read-Host "Type REMOVE to delete '$installFull'. This does not revert firmware or ThrottleStop settings"
    if ($confirmation -cne 'REMOVE') {
        Write-Host 'Uninstall cancelled.'
        return
    }
}

if ($PSCmdlet.ShouldProcess($installFull, 'Remove Dell Undervolt Toolkit installation directory')) {
    Remove-Item -LiteralPath $installFull -Recurse -Force
    Write-Host 'Toolkit files removed.' -ForegroundColor Green
    Write-Host 'Firmware variables, BIOS settings, USB media, and ThrottleStop profiles were not changed by this uninstaller.'
}
