#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourceRoot = '',

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BiosFile,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory,

    [switch]$InitializeIfMissing,
    [switch]$AllowUntestedPython
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Toolkit.Common.psm1') -Force -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Split-Path -Parent $PSScriptRoot
}
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot -ErrorAction Stop).Path
$biosFileResolved = (Resolve-Path -LiteralPath $BiosFile -ErrorAction Stop).Path
$biosUtilities = Get-ToolkitBiosUtilitiesRoot -SourceRoot $SourceRoot
$venvPython = Join-Path (Join-Path (Join-Path $biosUtilities '.venv') 'Scripts') 'python.exe'

if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
    if (-not $InitializeIfMissing) {
        throw "BIOSUtilities virtual environment is missing at '$venvPython'. Run Initialize-BiosUtilities.ps1 or use -InitializeIfMissing."
    }

    $initializeScript = Join-Path $PSScriptRoot 'Initialize-BiosUtilities.ps1'
    $initializeParameters = @{ SourceRoot = $SourceRoot }
    if ($AllowUntestedPython) {
        $initializeParameters['AllowUntestedPython'] = $true
    }
    & $initializeScript @initializeParameters
}

if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
    throw "Virtual-environment Python was not found after initialisation: '$venvPython'."
}

$sevenZip = Get-Command 7z.exe -ErrorAction SilentlyContinue
if ($null -eq $sevenZip -and -not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
    $candidate = Join-Path (Join-Path $env:ProgramFiles '7-Zip') '7z.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $sevenZip = Get-Item -LiteralPath $candidate
        $env:Path = (Split-Path -Parent $candidate) + [System.IO.Path]::PathSeparator + $env:Path
    }
}
if ($null -eq $sevenZip) {
    throw '7z.exe was not found. Install 7-Zip, open a new PowerShell window, and verify that `7z` runs before extracting the Dell executable.'
}

$outputFull = [System.IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $outputFull -PathType Container)) {
    New-Item -ItemType Directory -Path $outputFull -Force | Out-Null
}
$outputFull = (Resolve-Path -LiteralPath $outputFull).Path

$main = Join-Path $biosUtilities 'main.py'
$inputHash = Get-ToolkitSha256 -Path $biosFileResolved
$started = [DateTime]::UtcNow

Write-Host "Input BIOS package: $biosFileResolved"
Write-Host "Input SHA-256: $inputHash"
Write-Host "Output root: $outputFull"
Write-Host 'Running BIOSUtilities DellPfsExtract. No firmware will be flashed.'

Push-Location $biosUtilities
try {
    & $venvPython $main -e -u DellPfsExtract -o $outputFull $biosFileResolved
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($exitCode -ne 0) {
    throw "BIOSUtilities did not complete successfully; exit code $exitCode. Review the console output and confirm that the exact Dell package and external dependencies are supported."
}

$files = @(Get-ChildItem -LiteralPath $outputFull -File -Recurse -ErrorAction Stop)
$candidates = @($files | Where-Object {
    $_.Name -match '(?i)(system.*bios|bios.*guard|firmware|payload|image)' -or
    $_.Extension -match '(?i)^\.(bin|rom|fd|cap)$'
} | Sort-Object -Property Length -Descending)

$candidateRecords = @()
foreach ($candidate in $candidates) {
    $candidateRecords += [ordered]@{
        path = Get-ToolkitRelativePath -BasePath $outputFull -Path $candidate.FullName
        size = [int64]$candidate.Length
        sha256 = Get-ToolkitSha256 -Path $candidate.FullName
    }
}

$report = [ordered]@{
    schemaVersion = 1
    startedAtUtc = $started.ToString('o')
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
    sourceBios = [ordered]@{
        path = $biosFileResolved
        size = [int64](Get-Item -LiteralPath $biosFileResolved).Length
        sha256 = $inputHash
    }
    biosUtilitiesRoot = $biosUtilities
    outputDirectory = $outputFull
    extractedFileCount = $files.Count
    candidates = $candidateRecords
    warning = 'Candidate detection is heuristic. Open the extracted files in UEFITool and verify the correct system BIOS image before continuing.'
}
$reportPath = Join-Path $outputFull 'toolkit-extraction-report.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Host "Extraction completed; $($files.Count) files are present under the output directory." -ForegroundColor Green
Write-Host "Report: $reportPath"
if ($candidates.Count -gt 0) {
    Write-Host 'Likely firmware-image candidates:'
    $candidates | Select-Object -First 20 @{Name='SizeMiB';Expression={[math]::Round($_.Length / 1MB, 2)}}, FullName | Format-Table -AutoSize
}
else {
    Write-Warning 'No candidate was identified by filename or extension. Inspect the complete extraction tree manually.'
}
Write-Host 'Next: read docs/FIRMWARE-ANALYSIS.md and use UEFITool plus IFRExtractor on the exact extracted firmware.'
