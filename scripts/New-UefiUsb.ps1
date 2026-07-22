#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$SourceRoot = '',

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Destination,

    [string]$ShellEfiPath = '',
    [string]$RuEfiPath = '',
    [switch]$AllowMissingRuEfi,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'Toolkit.Common.psm1'
Import-Module -Name $modulePath -Force -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Split-Path -Parent $PSScriptRoot
}
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot -ErrorAction Stop).Path

function Get-DriveRootInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    $isRoot = $full.TrimEnd('\', '/') -eq $root.TrimEnd('\', '/')
    $driveLetter = $null
    if ($root -match '^(?<letter>[A-Za-z]):\\') {
        $driveLetter = $matches.letter.ToUpperInvariant()
    }

    [pscustomobject]@{
        FullPath = $full
        Root = $root
        IsDriveRoot = $isRoot
        DriveLetter = $driveLetter
    }
}

function Get-FileSystemForDriveLetter {
    param([Parameter(Mandatory = $true)][string]$DriveLetter)

    try {
        $volume = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop
        if ($null -ne $volume) {
            return [string]$volume.FileSystem
        }
    }
    catch {
        try {
            $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$DriveLetter`:'" -ErrorAction Stop
            if ($null -ne $disk) {
                return [string]$disk.FileSystem
            }
        }
        catch {
            Write-Warning "Windows could not determine the filesystem for drive $DriveLetter`: $($_.Exception.Message)"
        }
    }

    return ''
}

function Find-PayloadFile {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][ValidateSet('Shell', 'RU')][string]$Kind,
        [string]$ExplicitPath = '',
        [ref]$TemporaryDirectory
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop).Path
    }

    if ($Kind -eq 'Shell') {
        $names = @('BOOTX64.EFI', 'bootx64.efi', 'ShellX64.efi', 'shellx64.efi')
    }
    else {
        $names = @('RU.EFI', 'RU.efi', 'ru.efi')
    }

    $directCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($name in $names) {
        $directCandidates.Add((Join-Path (Join-Path (Join-Path (Join-Path $Root 'USB') 'EFI') 'BOOT') $name))
        $directCandidates.Add((Join-Path (Join-Path (Join-Path (Join-Path $Root 'payload') 'EFI') 'BOOT') $name))
    }

    $direct = Get-ToolkitFirstExistingFile -CandidatePaths $directCandidates.ToArray()
    if ($null -ne $direct) {
        return $direct
    }

    if ($null -ne $TemporaryDirectory.Value -and (Test-Path -LiteralPath $TemporaryDirectory.Value -PathType Container)) {
        foreach ($name in $names) {
            $candidate = Join-Path (Join-Path (Join-Path $TemporaryDirectory.Value 'EFI') 'BOOT') $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }

    $nestedArchives = @(
        (Join-Path (Join-Path (Join-Path (Join-Path $Root 'Toolkit') 'BIOSMod') 'Extract_to_USB') 'dell_efiboot_usb_w_RU.zip'),
        (Join-Path (Join-Path (Join-Path $Root 'BIOSMod') 'Extract_to_USB') 'dell_efiboot_usb_w_RU.zip')
    )

    $nestedArchive = Get-ToolkitFirstExistingFile -CandidatePaths $nestedArchives
    if ($null -ne $nestedArchive) {
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ('dell-undervolt-usb-' + [Guid]::NewGuid().ToString('N'))
        Expand-ToolkitZip -ArchivePath $nestedArchive -DestinationPath $temp
        $TemporaryDirectory.Value = $temp
        foreach ($name in $names) {
            $candidate = Join-Path (Join-Path (Join-Path $temp 'EFI') 'BOOT') $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }

    $matchesFound = @()
    foreach ($name in $names) {
        $matchesFound += @(Get-ChildItem -LiteralPath $Root -Filter $name -File -Recurse -ErrorAction SilentlyContinue)
    }
    $uniqueMatches = @($matchesFound | Sort-Object -Property FullName -Unique)
    if ($uniqueMatches.Count -eq 1) {
        return $uniqueMatches[0].FullName
    }
    if ($uniqueMatches.Count -gt 1) {
        $locations = ($uniqueMatches | ForEach-Object { $_.FullName }) -join "`n  "
        throw "More than one possible $Kind payload was found. Supply an explicit path.`n  $locations"
    }

    return $null
}

$destinationInfo = Get-DriveRootInfo -Path $Destination
if ($destinationInfo.IsDriveRoot) {
    if (-not $Force) {
        throw "Writing directly to drive root '$($destinationInfo.FullPath)' requires -Force. The script never formats the drive."
    }
    if ($null -eq $destinationInfo.DriveLetter) {
        throw "Could not determine the drive letter for '$Destination'."
    }

    $systemRoot = [System.IO.Path]::GetPathRoot($env:SystemRoot)
    if ($destinationInfo.Root.TrimEnd('\', '/') -ieq $systemRoot.TrimEnd('\', '/')) {
        throw 'Refusing to write the UEFI payload to the Windows system drive.'
    }

    $fileSystem = Get-FileSystemForDriveLetter -DriveLetter $destinationInfo.DriveLetter
    if ([string]::IsNullOrWhiteSpace($fileSystem)) {
        throw "The filesystem for drive $($destinationInfo.DriveLetter): could not be verified. Use a normal directory destination or verify the drive from Windows and retry."
    }
    if ($fileSystem -ine 'FAT32') {
        throw "Drive $($destinationInfo.DriveLetter): uses '$fileSystem', not FAT32. Format the intended USB manually and verify the drive letter before retrying."
    }
}

$tempPayload = $null
try {
    $shell = Find-PayloadFile -Root $SourceRoot -Kind Shell -ExplicitPath $ShellEfiPath -TemporaryDirectory ([ref]$tempPayload)
    if ($null -eq $shell) {
        throw 'BOOTX64.EFI / ShellX64.efi was not found. Supply -ShellEfiPath or install a full Release.'
    }

    $ru = Find-PayloadFile -Root $SourceRoot -Kind RU -ExplicitPath $RuEfiPath -TemporaryDirectory ([ref]$tempPayload)
    if ($null -eq $ru -and -not $AllowMissingRuEfi) {
        throw 'RU.EFI was not found. Supply -RuEfiPath, install a full Release, or use -AllowMissingRuEfi to stage only the shell.'
    }

    $destinationRoot = $destinationInfo.FullPath
    $bootDirectory = Join-Path (Join-Path $destinationRoot 'EFI') 'BOOT'
    $operation = "Copy UEFI payload to '$bootDirectory'"
    if ($PSCmdlet.ShouldProcess($destinationRoot, $operation)) {
        New-Item -ItemType Directory -Path $bootDirectory -Force | Out-Null

        $shellDestination = Join-Path $bootDirectory 'BOOTX64.EFI'
        Copy-Item -LiteralPath $shell -Destination $shellDestination -Force
        $shellSourceHash = Get-ToolkitSha256 -Path $shell
        $shellDestinationHash = Get-ToolkitSha256 -Path $shellDestination
        if ($shellSourceHash -ne $shellDestinationHash) {
            throw 'BOOTX64.EFI copy verification failed.'
        }

        $checksumLines = @("$shellDestinationHash  EFI/BOOT/BOOTX64.EFI")
        if ($null -ne $ru) {
            $ruDestination = Join-Path $bootDirectory 'RU.EFI'
            Copy-Item -LiteralPath $ru -Destination $ruDestination -Force
            $ruSourceHash = Get-ToolkitSha256 -Path $ru
            $ruDestinationHash = Get-ToolkitSha256 -Path $ruDestination
            if ($ruSourceHash -ne $ruDestinationHash) {
                throw 'RU.EFI copy verification failed.'
            }
            $checksumLines += "$ruDestinationHash  EFI/BOOT/RU.EFI"
        }

        $checksumLines | Set-Content -LiteralPath (Join-Path $destinationRoot 'SHA256SUMS.txt') -Encoding ASCII

        $readmeLines = @(
            'Dell Undervolt Toolkit - UEFI payload',
            '',
            'This directory was staged without formatting or repartitioning the destination.',
            'BOOTX64.EFI launches an x64 UEFI Shell. RU.EFI, when present, must be started manually.',
            '',
            'Firmware offsets are model- and BIOS-version-specific.',
            'Analyse the exact firmware with UEFITool and IFRExtractor before changing any variable.',
            'Keep the BitLocker recovery key and the original variable bytes available.',
            '',
            ('Generated UTC: ' + [DateTime]::UtcNow.ToString('o'))
        )
        $readmeLines | Set-Content -LiteralPath (Join-Path $destinationRoot 'TOOLKIT-USB-README.txt') -Encoding UTF8

        Write-Host 'UEFI payload prepared successfully.' -ForegroundColor Green
        Write-Host "Destination: $destinationRoot"
        Write-Host "BOOTX64.EFI SHA-256: $shellDestinationHash"
        if ($null -ne $ru) {
            Write-Host "RU.EFI SHA-256: $ruDestinationHash"
        }
        else {
            Write-Warning 'RU.EFI is not present; the staged payload contains only the UEFI Shell.'
        }
        Write-Host 'No firmware variable was written.'
    }
}
finally {
    if ($null -ne $tempPayload -and (Test-Path -LiteralPath $tempPayload)) {
        try {
            Assert-ToolkitSafeRemovalPath -Path $tempPayload
            Remove-Item -LiteralPath $tempPayload -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "Temporary payload directory could not be removed: '$tempPayload'."
        }
    }
}
