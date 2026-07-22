Set-StrictMode -Version Latest

function Get-ToolkitSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    return (Get-FileHash -LiteralPath $resolved -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Get-ToolkitRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    if (-not $baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString())) {
        $baseFull += [System.IO.Path]::DirectorySeparatorChar
    }

    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $baseUri = New-Object System.Uri($baseFull)
    $pathUri = New-Object System.Uri($pathFull)
    $relative = [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString())
    return $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Test-ToolkitChildPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParentPath,

        [Parameter(Mandatory = $true)]
        [string]$CandidatePath
    )

    $parentFull = [System.IO.Path]::GetFullPath($ParentPath).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $candidateFull = [System.IO.Path]::GetFullPath($CandidatePath)
    return $candidateFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-ToolkitSafeRemovalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $root = [System.IO.Path]::GetPathRoot($full).TrimEnd('\', '/')

    if ([string]::IsNullOrWhiteSpace($full) -or $full -eq $root) {
        throw "Refusing to remove an unsafe path: '$Path'."
    }

    $protected = @(
        [Environment]::GetFolderPath('Windows'),
        [Environment]::GetFolderPath('ProgramFiles'),
        [Environment]::GetFolderPath('ProgramFilesX86'),
        [Environment]::GetFolderPath('UserProfile'),
        $env:SystemDrive
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($item in $protected) {
        $protectedFull = [System.IO.Path]::GetFullPath($item).TrimEnd('\', '/')
        if ($full -eq $protectedFull) {
            throw "Refusing to remove protected path '$full'."
        }
    }
}

function Copy-ToolkitDirectoryContents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    $sourceFull = (Resolve-Path -LiteralPath $Source -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    Get-ChildItem -LiteralPath $sourceFull -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Get-ToolkitBiosModRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot
    )

    $root = (Resolve-Path -LiteralPath $SourceRoot -ErrorAction Stop).Path
    $candidates = @(
        (Join-Path (Join-Path $root 'Toolkit') 'BIOSMod'),
        (Join-Path $root 'BIOSMod'),
        $root
    )

    foreach ($candidate in $candidates) {
        $apps = Join-Path $candidate 'Apps'
        if (Test-Path -LiteralPath $apps -PathType Container) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Could not locate BIOSMod under '$root'. Install a full Release or provide the correct -SourceRoot."
}

function Get-ToolkitBiosUtilitiesRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot
    )

    $biosMod = Get-ToolkitBiosModRoot -SourceRoot $SourceRoot
    $candidate = Join-Path (Join-Path $biosMod 'Apps') 'BIOSUtilities'
    if (-not (Test-Path -LiteralPath (Join-Path $candidate 'main.py') -PathType Leaf)) {
        throw "BIOSUtilities was not found at '$candidate'."
    }

    return (Resolve-Path -LiteralPath $candidate).Path
}

function Get-ToolkitFirstExistingFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CandidatePaths
    )

    foreach ($candidate in $CandidatePaths) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Import-ToolkitZipSupport {
    [CmdletBinding()]
    param()

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    }
    catch {
        if (-not ('System.IO.Compression.ZipFile' -as [type])) {
            throw "ZIP support could not be loaded: $($_.Exception.Message)"
        }
    }
}

function Expand-ToolkitZip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [switch]$Force
    )

    $archive = (Resolve-Path -LiteralPath $ArchivePath -ErrorAction Stop).Path
    if (Test-Path -LiteralPath $DestinationPath) {
        if (-not $Force) {
            throw "Destination already exists: '$DestinationPath'."
        }
        Assert-ToolkitSafeRemovalPath -Path $DestinationPath
        Remove-Item -LiteralPath $DestinationPath -Recurse -Force
    }

    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    Import-ToolkitZipSupport
    [System.IO.Compression.ZipFile]::ExtractToDirectory($archive, $DestinationPath)
}

function Test-ToolkitManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageRoot,

        [string]$ManifestPath = ''
    )

    $root = (Resolve-Path -LiteralPath $PackageRoot -ErrorAction Stop).Path
    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        $ManifestPath = Join-Path $root 'manifest.json'
    }

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest not found: '$ManifestPath'."
    }

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json
    $entries = $manifest.files
    if ($null -eq $entries) {
        throw "Manifest '$ManifestPath' does not contain a 'files' array."
    }

    $rootPrefix = $root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $checked = 0

    foreach ($entry in $entries) {
        $relative = [string]$entry.path
        if ([string]::IsNullOrWhiteSpace($relative)) {
            throw 'Manifest contains an empty path.'
        }

        $nativeRelative = $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $root $nativeRelative))
        if (-not $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Manifest path escapes package root: '$relative'."
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Manifest file is missing: '$relative'."
        }

        $file = Get-Item -LiteralPath $candidate
        if ($null -ne $entry.size -and [int64]$entry.size -ne $file.Length) {
            throw "Manifest size mismatch for '$relative'. Expected $($entry.size), got $($file.Length)."
        }

        $actual = Get-ToolkitSha256 -Path $candidate
        $expected = ([string]$entry.sha256).ToLowerInvariant()
        if ($actual -ne $expected) {
            throw "Manifest SHA-256 mismatch for '$relative'. Expected $expected, got $actual."
        }
        $checked++
    }

    [pscustomobject]@{
        Manifest = (Resolve-Path -LiteralPath $ManifestPath).Path
        FilesChecked = $checked
        Valid = $true
    }
}

Export-ModuleMember -Function @(
    'Get-ToolkitSha256',
    'Get-ToolkitRelativePath',
    'Test-ToolkitChildPath',
    'Assert-ToolkitSafeRemovalPath',
    'Copy-ToolkitDirectoryContents',
    'Get-ToolkitBiosModRoot',
    'Get-ToolkitBiosUtilitiesRoot',
    'Get-ToolkitFirstExistingFile',
    'Import-ToolkitZipSupport',
    'Expand-ToolkitZip',
    'Test-ToolkitManifest'
)
