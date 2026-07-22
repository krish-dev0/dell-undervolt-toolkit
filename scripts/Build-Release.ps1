#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceArchive,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$')]
    [string]$Version,

    [string]$Repository = 'krish-dev0/dell-undervolt-toolkit
',
    [string]$OutputDirectory = '',
    [switch]$ExcludeRuEfi,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Toolkit.Common.psm1') -Force -ErrorAction Stop
Import-ToolkitZipSupport

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot) -ErrorAction Stop).Path
$sourceArchiveFull = (Resolve-Path -LiteralPath $SourceArchive -ErrorAction Stop).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot 'dist'
}
$outputFull = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputFull -Force | Out-Null

$normalizedVersion = $Version.TrimStart('v')
$packageName = "dell-undervolt-toolkit-$normalizedVersion"
$fullAssetName = "$packageName-full.zip"
$usbAssetName = "$packageName-usb.zip"
$fullAssetPath = Join-Path $outputFull $fullAssetName
$usbAssetPath = Join-Path $outputFull $usbAssetName
$releaseNotesPath = Join-Path $outputFull "$packageName-release-notes.md"

foreach ($output in @($fullAssetPath, $usbAssetPath, $fullAssetPath + '.sha256', $usbAssetPath + '.sha256', $releaseNotesPath)) {
    if (Test-Path -LiteralPath $output) {
        if (-not $Force) {
            throw "Output already exists: '$output'. Use -Force to replace it."
        }
        Remove-Item -LiteralPath $output -Force
    }
}

$workRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('dell-undervolt-toolkit-build-' + [Guid]::NewGuid().ToString('N'))
$sourceExtract = Join-Path $workRoot 'source-archive'
$archiveContainer = Join-Path $workRoot 'archive-container'
$packageRoot = Join-Path $archiveContainer $packageName
New-Item -ItemType Directory -Path $sourceExtract -Force | Out-Null
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

function Test-ExcludedRepositoryPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normal = $RelativePath.Replace('/', '\')
    $segments = $normal.Split('\')
    foreach ($segment in $segments) {
        if ($segment -in @('.git', '.venv', 'venv', '__pycache__', 'dist', 'build', 'Toolkit', 'USB')) {
            return $true
        }
    }

    $name = [System.IO.Path]::GetFileName($normal)
    if ($name -in @('manifest.json', 'installation-record.json', 'toolkit-environment.json')) {
        return $true
    }
    if ($name -match '(?i)\.(exe|efi|dll|sys|msi|zip|7z|rar|pyc|pyo)$') {
        return $true
    }
    return $false
}

function Copy-RepositorySource {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $files = @(Get-ChildItem -LiteralPath $Source -File -Recurse -Force)
    foreach ($file in $files) {
        $relative = Get-ToolkitRelativePath -BasePath $Source -Path $file.FullName
        if (Test-ExcludedRepositoryPath -RelativePath $relative) {
            continue
        }
        $target = Join-Path $Destination $relative
        $targetParent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }

    $placeholder = Join-Path (Join-Path (Join-Path (Join-Path $Destination 'payload') 'EFI') 'BOOT') '.gitkeep'
    if (-not (Test-Path -LiteralPath $placeholder -PathType Leaf)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $placeholder) -Force | Out-Null
        New-Item -ItemType File -Path $placeholder -Force | Out-Null
    }
}

function Find-ExtractedBiosModRoot {
    param([Parameter(Mandatory = $true)][string]$ExtractedRoot)

    $direct = @(
        (Join-Path $ExtractedRoot 'BIOSMod'),
        $ExtractedRoot
    )
    foreach ($candidate in $direct) {
        if ((Test-Path -LiteralPath (Join-Path $candidate 'Apps') -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'Extract_to_USB') -PathType Container)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $directories = @(Get-ChildItem -LiteralPath $ExtractedRoot -Directory -Recurse -ErrorAction SilentlyContinue)
    foreach ($candidate in $directories) {
        if ((Test-Path -LiteralPath (Join-Path $candidate.FullName 'Apps') -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $candidate.FullName 'Extract_to_USB') -PathType Container)) {
            return $candidate.FullName
        }
    }

    throw 'The source archive does not contain a recognisable BIOSMod directory.'
}

function Rename-PayloadCase {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string[]]$PossibleNames,
        [Parameter(Mandatory = $true)][string]$CanonicalName
    )

    foreach ($name in $PossibleNames) {
        $candidate = Join-Path $Directory $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $canonical = Join-Path $Directory $CanonicalName
            if ($candidate -ceq $canonical) {
                return $canonical
            }
            $temporary = Join-Path $Directory ([Guid]::NewGuid().ToString('N') + '.tmp')
            Move-Item -LiteralPath $candidate -Destination $temporary -Force
            Move-Item -LiteralPath $temporary -Destination $canonical -Force
            return $canonical
        }
    }
    return $null
}

function Write-Sha256Sidecar {
    param([Parameter(Mandatory = $true)][string]$Path)
    $hash = Get-ToolkitSha256 -Path $Path
    $line = "$hash  $([System.IO.Path]::GetFileName($Path))"
    $line | Set-Content -LiteralPath ($Path + '.sha256') -Encoding ASCII
    return $hash
}

try {
    Write-Host 'Copying source repository files.'
    Copy-RepositorySource -Source $repoRoot -Destination $packageRoot

    Write-Host "Extracting maintainer archive '$sourceArchiveFull'."
    [System.IO.Compression.ZipFile]::ExtractToDirectory($sourceArchiveFull, $sourceExtract)
    $inputBiosMod = Find-ExtractedBiosModRoot -ExtractedRoot $sourceExtract
    $releaseBiosMod = Join-Path (Join-Path $packageRoot 'Toolkit') 'BIOSMod'
    New-Item -ItemType Directory -Path $releaseBiosMod -Force | Out-Null
    Copy-ToolkitDirectoryContents -Source $inputBiosMod -Destination $releaseBiosMod

    Get-ChildItem -LiteralPath $releaseBiosMod -Directory -Filter '__pycache__' -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
    Get-ChildItem -LiteralPath $releaseBiosMod -File -Include '*.pyc', '*.pyo' -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -LiteralPath $releaseBiosMod -File -Include 'ThrottleStop.ini', 'HWiNFO64.INI' -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force

    foreach ($workingFolder in @(
        (Join-Path (Join-Path $releaseBiosMod 'BIOS') 'downloaded_bios'),
        (Join-Path (Join-Path $releaseBiosMod 'BIOS') 'extracted_bios')
    )) {
        if (Test-Path -LiteralPath $workingFolder -PathType Container) {
            Get-ChildItem -LiteralPath $workingFolder -Force | Remove-Item -Recurse -Force
        }
    }

    $nestedUsbZip = Join-Path (Join-Path $releaseBiosMod 'Extract_to_USB') 'dell_efiboot_usb_w_RU.zip'
    if (-not (Test-Path -LiteralPath $nestedUsbZip -PathType Leaf)) {
        throw "Expected nested USB archive was not found: '$nestedUsbZip'."
    }

    $usbRoot = Join-Path $packageRoot 'USB'
    New-Item -ItemType Directory -Path $usbRoot -Force | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($nestedUsbZip, $usbRoot)
    Remove-Item -LiteralPath $nestedUsbZip -Force

    $bootDirectory = Join-Path (Join-Path $usbRoot 'EFI') 'BOOT'
    if (-not (Test-Path -LiteralPath $bootDirectory -PathType Container)) {
        throw 'The nested USB archive did not produce USB/EFI/BOOT.'
    }

    $bootPath = Rename-PayloadCase -Directory $bootDirectory -PossibleNames @('BOOTX64.EFI', 'bootx64.efi', 'ShellX64.efi', 'shellx64.efi') -CanonicalName 'BOOTX64.EFI'
    if ($null -eq $bootPath) {
        throw 'The USB archive does not contain an x64 UEFI Shell binary.'
    }

    $ruPath = Rename-PayloadCase -Directory $bootDirectory -PossibleNames @('RU.EFI', 'RU.efi', 'ru.efi') -CanonicalName 'RU.EFI'
    if ($ExcludeRuEfi) {
        if ($null -ne $ruPath -and (Test-Path -LiteralPath $ruPath -PathType Leaf)) {
            Remove-Item -LiteralPath $ruPath -Force
        }
        $ruPath = $null
    }
    elseif ($null -eq $ruPath) {
        throw 'RU.EFI was not found. Use -ExcludeRuEfi to build an explicit no-RU Release.'
    }

    $configPath = Join-Path (Join-Path $packageRoot 'config') 'repository.json'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $config.repository = $Repository
        $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8
    }

    $buildInfo = [ordered]@{
        schemaVersion = 1
        toolkitVersion = $normalizedVersion
        repository = $Repository
        builtAtUtc = [DateTime]::UtcNow.ToString('o')
        sourceArchive = [ordered]@{
            fileName = [System.IO.Path]::GetFileName($sourceArchiveFull)
            size = [int64](Get-Item -LiteralPath $sourceArchiveFull).Length
            sha256 = Get-ToolkitSha256 -Path $sourceArchiveFull
        }
        payload = [ordered]@{
            ruEfiIncluded = $null -ne $ruPath
            bootx64EfiSha256 = Get-ToolkitSha256 -Path $bootPath
            ruEfiSha256 = if ($null -ne $ruPath) { Get-ToolkitSha256 -Path $ruPath } else { $null }
        }
        safety = [ordered]@{
            automaticFirmwareVariableWrites = $false
            automaticDiskFormatting = $false
            modelSpecificOffsetsIncludedAsPreset = $false
        }
    }
    $buildInfo | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $packageRoot 'build-info.json') -Encoding UTF8

    $manifestEntries = @()
    $packageFiles = @(Get-ChildItem -LiteralPath $packageRoot -File -Recurse -Force | Where-Object { $_.Name -ne 'manifest.json' } | Sort-Object -Property FullName)
    foreach ($file in $packageFiles) {
        $relative = (Get-ToolkitRelativePath -BasePath $packageRoot -Path $file.FullName).Replace('\', '/')
        $manifestEntries += [ordered]@{
            path = $relative
            size = [int64]$file.Length
            sha256 = Get-ToolkitSha256 -Path $file.FullName
        }
    }
    $manifest = [ordered]@{
        schemaVersion = 1
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        hashAlgorithm = 'SHA-256'
        files = $manifestEntries
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $packageRoot 'manifest.json') -Encoding UTF8

    Write-Host "Creating $fullAssetName."
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $archiveContainer,
        $fullAssetPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    Write-Host "Creating $usbAssetName."
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $usbRoot,
        $usbAssetPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    $fullHash = Write-Sha256Sidecar -Path $fullAssetPath
    $usbHash = Write-Sha256Sidecar -Path $usbAssetPath

    $ruStatement = if ($null -ne $ruPath) { 'RU.EFI is included in this Release asset.' } else { 'RU.EFI is not included; users must supply it locally with -RuEfiPath.' }
    $releaseNotes = @(
        "# Dell Undervolt Toolkit v$normalizedVersion",
        '',
        $ruStatement,
        '',
        '## Assets',
        '',
        "- $fullAssetName - complete toolkit package",
        "- $usbAssetName - EFI directory for a FAT32 USB drive",
        '- matching `.sha256` files - external integrity checks',
        '',
        '## SHA-256',
        '',
        '```text',
        "$fullHash  $fullAssetName",
        "$usbHash  $usbAssetName",
        '```',
        '',
        '## Critical warning',
        '',
        'Firmware offsets are specific to the exact laptop and BIOS image. The Dell Precision 3551 values in the documentation are examples only. Analyse the target firmware with UEFITool and IFRExtractor and record VarStore/GUID, offset, original byte, and option mapping before any manual change.',
        '',
        'The installer and helper scripts do not write UEFI variables and do not format USB drives.',
        '',
        'Tutorial: https://www.youtube.com/watch?v=gJBEIfyV7DY'
    )
    $releaseNotes | Set-Content -LiteralPath $releaseNotesPath -Encoding UTF8

    Write-Host ''
    Write-Host 'Release assets created successfully.' -ForegroundColor Green
    Write-Host "$fullAssetPath`n$($fullAssetPath + '.sha256')`n$usbAssetPath`n$($usbAssetPath + '.sha256')`n$releaseNotesPath"
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        try {
            Assert-ToolkitSafeRemovalPath -Path $workRoot
            Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "Temporary build directory could not be removed: '$workRoot'."
        }
    }
}
