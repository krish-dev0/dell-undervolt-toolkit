#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourceRoot = '',
    [switch]$RequireFullPayload,
    [switch]$RequireSourceOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Toolkit.Common.psm1') -Force -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Split-Path -Parent $PSScriptRoot
}
$root = (Resolve-Path -LiteralPath $SourceRoot -ErrorAction Stop).Path
$results = New-Object System.Collections.Generic.List[object]

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('Pass', 'Warning', 'Fail')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail
    )
    $results.Add([pscustomobject]@{ Test = $Name; Status = $Status; Detail = $Detail })
}

$requiredFiles = @(
    'README.md',
    'LICENSE',
    'DISCLAIMER.md',
    'THIRD_PARTY_NOTICES.md',
    'install.ps1',
    'scripts/Toolkit.Common.psm1',
    'scripts/New-UefiUsb.ps1',
    'scripts/Initialize-BiosUtilities.ps1',
    'scripts/Extract-DellBios.ps1',
    'scripts/Get-PreflightSnapshot.ps1',
    'scripts/Build-Release.ps1',
    'scripts/Set-RepositoryMetadata.ps1',
    'docs/FIRMWARE-ANALYSIS.md',
    'docs/RECOVERY.md',
    'examples/precision-3551-video-example.json',
    'config/repository.json'
)

foreach ($relative in $requiredFiles) {
    $path = Join-Path $root ($relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Add-TestResult -Name "Required file: $relative" -Status Pass -Detail 'Present'
    }
    else {
        Add-TestResult -Name "Required file: $relative" -Status Fail -Detail 'Missing'
    }
}

$jsonFiles = @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -Recurse -ErrorAction SilentlyContinue)
foreach ($jsonFile in $jsonFiles) {
    try {
        $parsed = Get-Content -LiteralPath $jsonFile.FullName -Raw | ConvertFrom-Json
        Add-TestResult -Name "JSON: $(Get-ToolkitRelativePath -BasePath $root -Path $jsonFile.FullName)" -Status Pass -Detail 'Valid JSON'
    }
    catch {
        Add-TestResult -Name "JSON: $(Get-ToolkitRelativePath -BasePath $root -Path $jsonFile.FullName)" -Status Fail -Detail $_.Exception.Message
    }
}

$examplePath = Join-Path (Join-Path $root 'examples') 'precision-3551-video-example.json'
if (Test-Path -LiteralPath $examplePath -PathType Leaf) {
    try {
        $example = Get-Content -LiteralPath $examplePath -Raw | ConvertFrom-Json
        if ([bool]$example.exampleOnly -and -not [bool]$example.portablePreset) {
            Add-TestResult -Name 'Tutorial example portability guard' -Status Pass -Detail 'exampleOnly=true and portablePreset=false'
        }
        else {
            Add-TestResult -Name 'Tutorial example portability guard' -Status Fail -Detail 'The model-specific example is not clearly marked as non-portable.'
        }
    }
    catch {
        Add-TestResult -Name 'Tutorial example portability guard' -Status Fail -Detail $_.Exception.Message
    }
}

$scriptFiles = @(
    Get-ChildItem -LiteralPath $root -Include '*.ps1', '*.psm1' -File -Recurse -ErrorAction SilentlyContinue
)
foreach ($scriptFile in $scriptFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$parseErrors)
    $relative = Get-ToolkitRelativePath -BasePath $root -Path $scriptFile.FullName
    if (@($parseErrors).Count -eq 0) {
        Add-TestResult -Name "PowerShell parse: $relative" -Status Pass -Detail 'No parser errors'
    }
    else {
        $detail = (@($parseErrors) | ForEach-Object { "Line $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; '
        Add-TestResult -Name "PowerShell parse: $relative" -Status Fail -Detail $detail
    }
}

$manifestPath = Join-Path $root 'manifest.json'
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
        $manifestResult = Test-ToolkitManifest -PackageRoot $root
        Add-TestResult -Name 'Release manifest' -Status Pass -Detail "$($manifestResult.FilesChecked) files verified"
    }
    catch {
        Add-TestResult -Name 'Release manifest' -Status Fail -Detail $_.Exception.Message
    }
}
else {
    Add-TestResult -Name 'Release manifest' -Status Warning -Detail 'Absent; expected for a source checkout, recommended for a Release package.'
}

$fullPayloadRoot = Join-Path (Join-Path $root 'Toolkit') 'BIOSMod'
$hasFullPayload = Test-Path -LiteralPath $fullPayloadRoot -PathType Container
if ($RequireFullPayload -and -not $hasFullPayload) {
    Add-TestResult -Name 'Full third-party payload' -Status Fail -Detail 'Toolkit/BIOSMod is missing.'
}
elseif ($hasFullPayload) {
    Add-TestResult -Name 'Full third-party payload' -Status Pass -Detail 'Toolkit/BIOSMod is present.'
}
else {
    Add-TestResult -Name 'Full third-party payload' -Status Warning -Detail 'Not present; this appears to be a source-only checkout.'
}

if ($RequireSourceOnly) {
    $disallowedExtensions = @('.exe', '.efi', '.dll', '.sys', '.msi', '.zip', '.7z', '.rar')
    $binaryFiles = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object {
        $disallowedExtensions -contains $_.Extension.ToLowerInvariant()
    })
    if ($binaryFiles.Count -eq 0) {
        Add-TestResult -Name 'Source-only binary exclusion' -Status Pass -Detail 'No executable or archive payloads found.'
    }
    else {
        $detail = ($binaryFiles | ForEach-Object { Get-ToolkitRelativePath -BasePath $root -Path $_.FullName }) -join ', '
        Add-TestResult -Name 'Source-only binary exclusion' -Status Fail -Detail $detail
    }
}

$configPath = Join-Path (Join-Path $root 'config') 'repository.json'
$config = $null
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    try { $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json } catch { $config = $null }
}

$bootPath = Join-Path (Join-Path (Join-Path (Join-Path $root 'USB') 'EFI') 'BOOT') 'BOOTX64.EFI'
$ruPath = Join-Path (Join-Path (Join-Path (Join-Path $root 'USB') 'EFI') 'BOOT') 'RU.EFI'

if (Test-Path -LiteralPath $bootPath -PathType Leaf) {
    $bootHash = Get-ToolkitSha256 -Path $bootPath
    $expectedBootHash = $null
    if ($null -ne $config) { $expectedBootHash = [string]$config.knownPayloadHashes.bootx64EfiSha256 }
    if (-not [string]::IsNullOrWhiteSpace($expectedBootHash) -and $bootHash -ne $expectedBootHash.ToLowerInvariant()) {
        Add-TestResult -Name 'BOOTX64.EFI hash' -Status Fail -Detail "Expected $expectedBootHash; got $bootHash"
    }
    else {
        Add-TestResult -Name 'BOOTX64.EFI hash' -Status Pass -Detail $bootHash
    }
}
elseif ($RequireFullPayload) {
    Add-TestResult -Name 'BOOTX64.EFI' -Status Fail -Detail 'USB/EFI/BOOT/BOOTX64.EFI is missing.'
}
else {
    Add-TestResult -Name 'BOOTX64.EFI' -Status Warning -Detail 'Not present in source-only package.'
}

if (Test-Path -LiteralPath $ruPath -PathType Leaf) {
    $ruHash = Get-ToolkitSha256 -Path $ruPath
    $expectedRuHash = $null
    if ($null -ne $config) { $expectedRuHash = [string]$config.knownPayloadHashes.ruEfiSha256FromTutorialPackage }
    if (-not [string]::IsNullOrWhiteSpace($expectedRuHash) -and $ruHash -ne $expectedRuHash.ToLowerInvariant()) {
        Add-TestResult -Name 'RU.EFI hash' -Status Warning -Detail "The file differs from the tutorial-package hash. Expected $expectedRuHash; got $ruHash. Confirm provenance before release."
    }
    else {
        Add-TestResult -Name 'RU.EFI hash' -Status Pass -Detail $ruHash
    }
}
elseif ($RequireFullPayload) {
    Add-TestResult -Name 'RU.EFI' -Status Warning -Detail 'Not present. This may be an intentional no-RU Release.'
}
else {
    Add-TestResult -Name 'RU.EFI' -Status Warning -Detail 'Not present in source-only package.'
}

$nestedUsbZip = Join-Path (Join-Path $fullPayloadRoot 'Extract_to_USB') 'dell_efiboot_usb_w_RU.zip'
if ($hasFullPayload -and (Test-Path -LiteralPath $nestedUsbZip -PathType Leaf)) {
    Add-TestResult -Name 'Nested USB archive removed' -Status Fail -Detail 'The nested USB ZIP remains and can hide a duplicate RU.EFI payload.'
}
elseif ($hasFullPayload) {
    Add-TestResult -Name 'Nested USB archive removed' -Status Pass -Detail 'No duplicate nested USB ZIP is present.'
}

$results | Format-Table -AutoSize
$failures = @($results | Where-Object { $_.Status -eq 'Fail' })
$warnings = @($results | Where-Object { $_.Status -eq 'Warning' })
Write-Host "`nPass: $(@($results | Where-Object { $_.Status -eq 'Pass' }).Count)  Warning: $($warnings.Count)  Fail: $($failures.Count)"
if ($failures.Count -gt 0) {
    throw "Toolkit validation failed with $($failures.Count) failing check(s)."
}
Write-Host 'Toolkit validation passed.' -ForegroundColor Green
