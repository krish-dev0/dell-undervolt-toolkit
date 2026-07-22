#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Repository = '',
    [string]$Version = 'latest',
    [string]$AssetPattern = 'dell-undervolt-toolkit-*-full.zip',
    [string]$ArchivePath = '',
    [string]$SourceDirectory = '',
    [string]$InstallDirectory = '',
    [string]$RuEfiPath = '',
    [string]$UsbDestination = '',
    [switch]$Force,
    [switch]$InitializeBiosUtilities,
    [switch]$SkipManifestVerification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-ToolkitStep {
    param([string]$Message)
    Write-Host "[Dell Undervolt Toolkit] $Message"
}

function Get-ToolkitSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath (Resolve-Path -LiteralPath $Path).Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-SafeRemovalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $root = [System.IO.Path]::GetPathRoot($full).TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($full) -or $full -eq $root) {
        throw "Refusing to remove unsafe path '$Path'."
    }

    $protected = @(
        [Environment]::GetFolderPath('Windows'),
        [Environment]::GetFolderPath('ProgramFiles'),
        [Environment]::GetFolderPath('ProgramFilesX86'),
        [Environment]::GetFolderPath('UserProfile'),
        $env:SystemDrive
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($item in $protected) {
        $candidate = [System.IO.Path]::GetFullPath($item).TrimEnd('\', '/')
        if ($full -eq $candidate) {
            throw "Refusing to remove protected path '$full'."
        }
    }
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Resolve-ConfiguredRepository {
    param([string]$RequestedRepository)

    if (-not [string]::IsNullOrWhiteSpace($RequestedRepository)) {
        return $RequestedRepository
    }

    $environmentRepository = $env:DELL_UNDERVOLT_TOOLKIT_REPOSITORY
    if (-not [string]::IsNullOrWhiteSpace($environmentRepository)) {
        return $environmentRepository
    }

    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $configPath = Join-Path (Join-Path $PSScriptRoot 'config') 'repository.json'
        if (Test-Path -LiteralPath $configPath -PathType Leaf) {
            try {
                $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
                $configured = [string]$config.repository
                if (-not [string]::IsNullOrWhiteSpace($configured) -and -not $configured.StartsWith('OWNER/')) {
                    return $configured
                }
            }
            catch {
                Write-Warning "Could not read '$configPath': $($_.Exception.Message)"
            }
        }
    }

    return ''
}

function Invoke-ToolkitDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [hashtable]$Headers = @{}
    )

    $parameters = @{
        Uri = $Uri
        OutFile = $OutFile
        Headers = $Headers
        ErrorAction = 'Stop'
    }
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $parameters['UseBasicParsing'] = $true
    }
    Invoke-WebRequest @parameters | Out-Null
}

function Get-GitHubHeaders {
    $headers = @{
        'Accept' = 'application/vnd.github+json'
        'User-Agent' = 'dell-undervolt-toolkit-installer'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)"
    }
    return $headers
}

function Get-ExpectedChecksumFromText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$TargetFileName = ''
    )

    $lines = $Text -split "`r?`n"
    if (-not [string]::IsNullOrWhiteSpace($TargetFileName)) {
        foreach ($line in $lines) {
            if ($line -match '^(?<hash>[A-Fa-f0-9]{64})\s+\*?(?<name>.+?)\s*$') {
                $name = [System.IO.Path]::GetFileName($matches.name.Trim())
                if ($name -ieq $TargetFileName) {
                    return $matches.hash.ToLowerInvariant()
                }
            }
        }
    }

    foreach ($line in $lines) {
        if ($line -match '(?<hash>[A-Fa-f0-9]{64})') {
            return $matches.hash.ToLowerInvariant()
        }
    }
    return $null
}

function Get-ReleaseArchive {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryName,
        [Parameter(Mandatory = $true)][string]$RequestedVersion,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    if ($RepositoryName -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        throw "Repository must use the OWNER/REPOSITORY form, not '$RepositoryName'."
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = Get-GitHubHeaders
    if ($RequestedVersion -eq 'latest') {
        $apiUri = "https://api.github.com/repos/$RepositoryName/releases/latest"
    }
    else {
        $tag = [System.Uri]::EscapeDataString($RequestedVersion)
        $apiUri = "https://api.github.com/repos/$RepositoryName/releases/tags/$tag"
    }

    Write-ToolkitStep "Reading GitHub Release metadata for $RepositoryName ($RequestedVersion)."
    $release = Invoke-RestMethod -Uri $apiUri -Headers $headers -Method Get -ErrorAction Stop
    $assets = @($release.assets)
    $assetMatches = @($assets | Where-Object { [string]$_.name -like $Pattern })
    if ($assetMatches.Count -eq 0) {
        $available = ($assets | ForEach-Object { [string]$_.name }) -join ', '
        throw "No Release asset matches '$Pattern'. Available assets: $available"
    }
    if ($assetMatches.Count -gt 1) {
        $names = ($assetMatches | ForEach-Object { [string]$_.name }) -join ', '
        throw "More than one Release asset matches '$Pattern': $names. Use a narrower -AssetPattern."
    }

    $asset = $assetMatches[0]
    $archive = Join-Path $WorkingDirectory ([string]$asset.name)
    Write-ToolkitStep "Downloading $($asset.name)."
    Invoke-ToolkitDownload -Uri ([string]$asset.browser_download_url) -OutFile $archive -Headers $headers

    $checksumAssets = @($assets | Where-Object {
        ([string]$_.name -ieq (([string]$asset.name) + '.sha256')) -or
        ([string]$_.name -ieq 'SHA256SUMS.txt')
    })

    $checksumVerified = $false
    $expected = $null
    if ($checksumAssets.Count -gt 0) {
        $checksumAsset = $checksumAssets[0]
        $checksumFile = Join-Path $WorkingDirectory ([string]$checksumAsset.name)
        Invoke-ToolkitDownload -Uri ([string]$checksumAsset.browser_download_url) -OutFile $checksumFile -Headers $headers
        $checksumText = Get-Content -LiteralPath $checksumFile -Raw
        $expected = Get-ExpectedChecksumFromText -Text $checksumText -TargetFileName ([string]$asset.name)
        if ([string]::IsNullOrWhiteSpace($expected)) {
            throw "Could not parse a SHA-256 value from '$($checksumAsset.name)'."
        }
        $actual = Get-ToolkitSha256 -Path $archive
        if ($actual -ne $expected) {
            throw "Release archive SHA-256 mismatch. Expected $expected, got $actual."
        }
        $checksumVerified = $true
        Write-ToolkitStep "Release archive SHA-256 verified: $actual"
    }
    else {
        Write-Warning 'The Release has no matching .sha256 or SHA256SUMS.txt asset. The internal manifest will still be checked when present.'
    }

    return [pscustomobject]@{
        ArchivePath = $archive
        ReleaseTag = [string]$release.tag_name
        ReleaseUrl = [string]$release.html_url
        AssetName = [string]$asset.name
        Sha256 = Get-ToolkitSha256 -Path $archive
        ExternalChecksumVerified = $checksumVerified
    }
}

function Expand-ArchiveSafely {
    param(
        [Parameter(Mandatory = $true)][string]$Archive,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        Assert-SafeRemovalPath -Path $Destination
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
}

function Resolve-PackageRoot {
    param([Parameter(Mandatory = $true)][string]$ExpandedDirectory)

    $root = (Resolve-Path -LiteralPath $ExpandedDirectory).Path
    if ((Test-Path -LiteralPath (Join-Path $root 'README.md') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $root 'scripts') -PathType Container)) {
        return $root
    }

    $candidateDirectories = @(Get-ChildItem -LiteralPath $root -Directory -Force)
    foreach ($candidate in $candidateDirectories) {
        if ((Test-Path -LiteralPath (Join-Path $candidate.FullName 'README.md') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $candidate.FullName 'scripts') -PathType Container)) {
            return $candidate.FullName
        }
    }

    $installers = @(Get-ChildItem -LiteralPath $root -Filter 'install.ps1' -File -Recurse -ErrorAction SilentlyContinue)
    foreach ($installer in $installers) {
        $candidate = $installer.Directory.FullName
        if ((Test-Path -LiteralPath (Join-Path $candidate 'README.md') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'scripts') -PathType Container)) {
            return $candidate
        }
    }

    throw "Could not locate a toolkit package root under '$root'."
}

function Test-PackageManifest {
    param([Parameter(Mandatory = $true)][string]$PackageRoot)

    $manifestPath = Join-Path $PackageRoot 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Write-Warning 'No manifest.json is present. This is normal for a source checkout but not recommended for a binary Release.'
        return [pscustomobject]@{ Present = $false; Valid = $false; FilesChecked = 0 }
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($null -eq $manifest.files) {
        throw "'$manifestPath' has no files array."
    }

    $root = (Resolve-Path -LiteralPath $PackageRoot).Path
    $prefix = $root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $count = 0
    foreach ($entry in $manifest.files) {
        $relative = [string]$entry.path
        if ([string]::IsNullOrWhiteSpace($relative)) {
            throw 'Manifest contains an empty path.'
        }
        $native = $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $root $native))
        if (-not $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Manifest path escapes package root: '$relative'."
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Manifest file is missing: '$relative'."
        }
        $file = Get-Item -LiteralPath $candidate
        if ($null -ne $entry.size -and [int64]$entry.size -ne $file.Length) {
            throw "Manifest size mismatch for '$relative'."
        }
        $expected = ([string]$entry.sha256).ToLowerInvariant()
        $actual = Get-ToolkitSha256 -Path $candidate
        if ($actual -ne $expected) {
            throw "Manifest SHA-256 mismatch for '$relative'. Expected $expected, got $actual."
        }
        $count++
    }

    Write-ToolkitStep "Internal manifest verified ($count files)."
    return [pscustomobject]@{ Present = $true; Valid = $true; FilesChecked = $count }
}

if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is not set. Supply -InstallDirectory explicitly.'
    }
    $InstallDirectory = Join-Path $env:LOCALAPPDATA 'DellUndervoltToolkit'
}

$workingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('dell-undervolt-toolkit-install-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workingRoot -Force | Out-Null
$downloadRecord = $null
$packageRoot = $null

try {
    $sourceCount = 0
    if (-not [string]::IsNullOrWhiteSpace($SourceDirectory)) { $sourceCount++ }
    if (-not [string]::IsNullOrWhiteSpace($ArchivePath)) { $sourceCount++ }
    if ($sourceCount -gt 1) {
        throw 'Use only one of -SourceDirectory or -ArchivePath.'
    }

    if (-not [string]::IsNullOrWhiteSpace($SourceDirectory)) {
        $packageRoot = (Resolve-Path -LiteralPath $SourceDirectory -ErrorAction Stop).Path
        Write-ToolkitStep "Using local source directory '$packageRoot'."
    }
    else {
        if (-not [string]::IsNullOrWhiteSpace($ArchivePath)) {
            $archive = (Resolve-Path -LiteralPath $ArchivePath -ErrorAction Stop).Path
            $sidecar = $archive + '.sha256'
            $verified = $false
            if (Test-Path -LiteralPath $sidecar -PathType Leaf) {
                $expected = Get-ExpectedChecksumFromText -Text (Get-Content -LiteralPath $sidecar -Raw) -TargetFileName ([System.IO.Path]::GetFileName($archive))
                if ([string]::IsNullOrWhiteSpace($expected)) {
                    throw "Could not parse '$sidecar'."
                }
                $actual = Get-ToolkitSha256 -Path $archive
                if ($actual -ne $expected) {
                    throw "Archive SHA-256 mismatch. Expected $expected, got $actual."
                }
                $verified = $true
                Write-ToolkitStep "Local archive SHA-256 verified: $actual"
            }
            else {
                Write-Warning "No sidecar checksum was found at '$sidecar'."
            }
            $downloadRecord = [pscustomobject]@{
                ArchivePath = $archive
                ReleaseTag = $null
                ReleaseUrl = $null
                AssetName = [System.IO.Path]::GetFileName($archive)
                Sha256 = Get-ToolkitSha256 -Path $archive
                ExternalChecksumVerified = $verified
            }
        }
        else {
            $Repository = Resolve-ConfiguredRepository -RequestedRepository $Repository
            if ([string]::IsNullOrWhiteSpace($Repository)) {
                throw 'No local source was supplied and the GitHub repository is not configured. Pass -Repository krish-dev0/dell-undervolt-toolkit
.'
            }
            $downloadRecord = Get-ReleaseArchive -RepositoryName $Repository -RequestedVersion $Version -Pattern $AssetPattern -WorkingDirectory $workingRoot
        }

        $expanded = Join-Path $workingRoot 'expanded'
        Write-ToolkitStep 'Extracting package.'
        Expand-ArchiveSafely -Archive $downloadRecord.ArchivePath -Destination $expanded
        $packageRoot = Resolve-PackageRoot -ExpandedDirectory $expanded
    }

    if (-not $SkipManifestVerification) {
        $manifestResult = Test-PackageManifest -PackageRoot $packageRoot
    }
    else {
        Write-Warning 'Internal manifest verification was explicitly skipped.'
        $manifestResult = [pscustomobject]@{ Present = $false; Valid = $false; FilesChecked = 0 }
    }

    $sourceFull = [System.IO.Path]::GetFullPath($packageRoot).TrimEnd('\', '/')
    $installFull = [System.IO.Path]::GetFullPath($InstallDirectory).TrimEnd('\', '/')
    $sourcePrefix = $sourceFull.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if ($sourceFull -eq $installFull -or $installFull.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'InstallDirectory must not be the source directory or a child of it.'
    }

    if (Test-Path -LiteralPath $installFull) {
        if (-not $Force) {
            throw "Install directory already exists: '$installFull'. Use -Force to replace it."
        }
        Assert-SafeRemovalPath -Path $installFull
        Write-ToolkitStep "Removing previous installation '$installFull'."
        Remove-Item -LiteralPath $installFull -Recurse -Force
    }

    New-Item -ItemType Directory -Path $installFull -Force | Out-Null
    Write-ToolkitStep "Installing to '$installFull'."
    Copy-DirectoryContents -Source $packageRoot -Destination $installFull

    if (-not [string]::IsNullOrWhiteSpace($RuEfiPath)) {
        $ruSource = (Resolve-Path -LiteralPath $RuEfiPath -ErrorAction Stop).Path
        if ([System.IO.Path]::GetExtension($ruSource) -ine '.efi') {
            Write-Warning "The supplied RU file does not use the .EFI extension: '$ruSource'."
        }
        $ruDestinationDirectory = Join-Path (Join-Path (Join-Path $installFull 'USB') 'EFI') 'BOOT'
        New-Item -ItemType Directory -Path $ruDestinationDirectory -Force | Out-Null
        $ruDestination = Join-Path $ruDestinationDirectory 'RU.EFI'
        Copy-Item -LiteralPath $ruSource -Destination $ruDestination -Force
        if ((Get-ToolkitSha256 -Path $ruSource) -ne (Get-ToolkitSha256 -Path $ruDestination)) {
            throw 'RU.EFI copy verification failed.'
        }
        Write-ToolkitStep "Local RU.EFI added with SHA-256 $(Get-ToolkitSha256 -Path $ruDestination)."
    }

    $record = [ordered]@{
        schemaVersion = 1
        installedAtUtc = [DateTime]::UtcNow.ToString('o')
        installDirectory = $installFull
        sourceDirectory = $sourceFull
        repository = $Repository
        requestedVersion = $Version
        assetName = if ($null -ne $downloadRecord) { $downloadRecord.AssetName } else { $null }
        archiveSha256 = if ($null -ne $downloadRecord) { $downloadRecord.Sha256 } else { $null }
        externalChecksumVerified = if ($null -ne $downloadRecord) { $downloadRecord.ExternalChecksumVerified } else { $false }
        manifestPresent = $manifestResult.Present
        manifestVerified = $manifestResult.Valid
        manifestFilesChecked = $manifestResult.FilesChecked
        ruEfiSuppliedLocally = -not [string]::IsNullOrWhiteSpace($RuEfiPath)
    }
    $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $installFull 'installation-record.json') -Encoding UTF8

    if ($InitializeBiosUtilities) {
        $initializeScript = Join-Path (Join-Path $installFull 'scripts') 'Initialize-BiosUtilities.ps1'
        if (-not (Test-Path -LiteralPath $initializeScript -PathType Leaf)) {
            throw "Initialisation script not found: '$initializeScript'."
        }
        Write-ToolkitStep 'Initialising the BIOSUtilities virtual environment.'
        & $initializeScript -SourceRoot $installFull
    }

    if (-not [string]::IsNullOrWhiteSpace($UsbDestination)) {
        $usbScript = Join-Path (Join-Path $installFull 'scripts') 'New-UefiUsb.ps1'
        if (-not (Test-Path -LiteralPath $usbScript -PathType Leaf)) {
            throw "USB preparation script not found: '$usbScript'."
        }
        Write-ToolkitStep "Preparing UEFI USB layout at '$UsbDestination'."
        $usbParameters = @{
            SourceRoot = $installFull
            Destination = $UsbDestination
        }
        if ($Force) { $usbParameters.Force = $true }
        & $usbScript @usbParameters
    }

    Write-Host ''
    Write-Host 'Installation complete.' -ForegroundColor Green
    Write-Host "Location: $installFull"
    Write-Host 'No UEFI variable or undervolt value was written by this installer.'
    Write-Host "Next: read '$([System.IO.Path]::Combine($installFull, 'docs', 'FIRMWARE-ANALYSIS.md'))'."
}
finally {
    if (Test-Path -LiteralPath $workingRoot) {
        try {
            Assert-SafeRemovalPath -Path $workingRoot
            Remove-Item -LiteralPath $workingRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "Temporary directory could not be removed: '$workingRoot'."
        }
    }
}
