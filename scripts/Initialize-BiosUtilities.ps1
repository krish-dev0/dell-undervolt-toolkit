#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourceRoot = '',
    [string]$PythonPath = '',
    [switch]$AllowUntestedPython,
    [switch]$Recreate,
    [switch]$SkipDependencyInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Toolkit.Common.psm1') -Force -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Split-Path -Parent $PSScriptRoot
}
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot -ErrorAction Stop).Path
$biosUtilities = Get-ToolkitBiosUtilitiesRoot -SourceRoot $SourceRoot
$requirements = Join-Path $biosUtilities 'requirements.txt'
$venv = Join-Path $biosUtilities '.venv'

function Resolve-PythonCommand {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $resolved = (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path
        return [pscustomobject]@{ Command = $resolved; PrefixArguments = @() }
    }

    $python = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($null -ne $python) {
        return [pscustomobject]@{ Command = $python.Source; PrefixArguments = @() }
    }

    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($null -ne $py) {
        foreach ($selector in @('-3.13', '-3.12', '-3.11', '-3.10', '-3')) {
            & $py.Source $selector -c 'import sys; print(sys.executable)' *> $null
            if ($LASTEXITCODE -eq 0) {
                return [pscustomobject]@{ Command = $py.Source; PrefixArguments = @($selector) }
            }
        }
    }

    throw 'Compatible Python was not found. Install official Python 3.10 through 3.13 or pass -PythonPath. The Python 3.14 installer in the tutorial archive is newer than the bundled BIOSUtilities tested range.'
}

function Invoke-Python {
    param(
        [Parameter(Mandatory = $true)]$PythonCommand,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $allArguments = @($PythonCommand.PrefixArguments) + $Arguments
    & $PythonCommand.Command @allArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed with exit code $LASTEXITCODE: $($PythonCommand.Command) $($allArguments -join ' ')"
    }
}

$pythonCommand = Resolve-PythonCommand -RequestedPath $PythonPath
$versionArguments = @($pythonCommand.PrefixArguments) + @('-c', 'import sys; print("%d.%d.%d" % sys.version_info[:3])')
$versionText = & $pythonCommand.Command @versionArguments
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$versionText)) {
    throw 'Could not determine the selected Python version.'
}

$version = [Version]([string]$versionText).Trim()
if ($version -lt [Version]'3.10.0') {
    throw "BIOSUtilities requires Python 3.10 or newer; selected version is $version."
}
if ($version -ge [Version]'3.14.0' -and -not $AllowUntestedPython) {
    throw "Selected Python $version is outside the bundled BIOSUtilities documented 3.10-3.13 range. Install a supported version or rerun with -AllowUntestedPython after reviewing compatibility."
}
if ($version -ge [Version]'3.14.0') {
    Write-Warning "Proceeding with untested Python version $version."
}

if ($Recreate -and (Test-Path -LiteralPath $venv)) {
    Assert-ToolkitSafeRemovalPath -Path $venv
    Remove-Item -LiteralPath $venv -Recurse -Force
}

if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $venv 'Scripts') 'python.exe') -PathType Leaf)) {
    Write-Host "Creating virtual environment at '$venv'."
    Invoke-Python -PythonCommand $pythonCommand -Arguments @('-m', 'venv', $venv)
}

$venvPython = Join-Path (Join-Path $venv 'Scripts') 'python.exe'
if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
    throw "Virtual-environment Python was not created at '$venvPython'."
}

if (-not $SkipDependencyInstall) {
    if (-not (Test-Path -LiteralPath $requirements -PathType Leaf)) {
        throw "requirements.txt not found at '$requirements'."
    }
    Write-Host 'Installing pinned BIOSUtilities dependencies into the local virtual environment.'
    & $venvPython -m pip install --disable-pip-version-check --requirement $requirements
    if ($LASTEXITCODE -ne 0) {
        throw "Dependency installation failed with exit code $LASTEXITCODE."
    }
}

$sevenZipCandidates = @()
$sevenZipCommand = Get-Command 7z.exe -ErrorAction SilentlyContinue
if ($null -ne $sevenZipCommand) {
    $sevenZipCandidates += $sevenZipCommand.Source
}
if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
    $sevenZipCandidates += Join-Path (Join-Path $env:ProgramFiles '7-Zip') '7z.exe'
}
if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
    $sevenZipCandidates += Join-Path (Join-Path ${env:ProgramFiles(x86)} '7-Zip') '7z.exe'
}
$sevenZip = Get-ToolkitFirstExistingFile -CandidatePaths $sevenZipCandidates
if ($null -eq $sevenZip) {
    Write-Warning '7z.exe was not found. Dell executable extraction may require an installed 7-Zip. The toolkit does not silently run the bundled installer.'
}
else {
    Write-Host "7-Zip detected: $sevenZip"
}

$environmentRecord = [ordered]@{
    schemaVersion = 1
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    biosUtilitiesRoot = $biosUtilities
    virtualEnvironment = $venv
    pythonVersion = $version.ToString()
    pythonExecutable = $venvPython
    requirementsSha256 = if (Test-Path -LiteralPath $requirements -PathType Leaf) { Get-ToolkitSha256 -Path $requirements } else { $null }
    sevenZipExecutable = $sevenZip
    untestedPythonAllowed = [bool]$AllowUntestedPython
}
$environmentRecord | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $biosUtilities 'toolkit-environment.json') -Encoding UTF8

Write-Host 'BIOSUtilities environment is ready.' -ForegroundColor Green
Write-Host "Python: $venvPython"
Write-Host 'No firmware image or UEFI variable was modified.'
