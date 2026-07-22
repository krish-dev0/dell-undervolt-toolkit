#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputPath = '',
    [switch]$IncludeServiceTag
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'This preflight helper is intended for Windows.'
}

function Get-SafeCimInstance {
    param([Parameter(Mandatory = $true)][string]$ClassName)
    try {
        return Get-CimInstance -ClassName $ClassName -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not query $ClassName: $($_.Exception.Message)"
        return $null
    }
}

function Convert-CimDate {
    param($Value)
    if ($null -eq $Value) { return $null }
    try {
        return ([DateTime]$Value).ToUniversalTime().ToString('o')
    }
    catch {
        return [string]$Value
    }
}

$warnings = New-Object System.Collections.Generic.List[string]
$computer = Get-SafeCimInstance -ClassName Win32_ComputerSystem
$baseBoard = Get-SafeCimInstance -ClassName Win32_BaseBoard
$bios = Get-SafeCimInstance -ClassName Win32_BIOS
$processors = @(Get-SafeCimInstance -ClassName Win32_Processor)
$operatingSystem = Get-SafeCimInstance -ClassName Win32_OperatingSystem
$batteries = @(Get-SafeCimInstance -ClassName Win32_Battery)

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$secureBootSupported = $null
$secureBootEnabled = $null
try {
    $secureBootEnabled = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
    $secureBootSupported = $true
}
catch {
    $secureBootSupported = $false
    $warnings.Add("Secure Boot state could not be read: $($_.Exception.Message)")
}

$bitLocker = $null
try {
    $bitLockerCommand = Get-Command Get-BitLockerVolume -ErrorAction Stop
    $systemVolume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    $protectorTypes = @()
    foreach ($protector in @($systemVolume.KeyProtector)) {
        if ($null -ne $protector.KeyProtectorType) {
            $protectorTypes += [string]$protector.KeyProtectorType
        }
    }
    $bitLocker = [ordered]@{
        mountPoint = [string]$systemVolume.MountPoint
        volumeStatus = [string]$systemVolume.VolumeStatus
        protectionStatus = [string]$systemVolume.ProtectionStatus
        encryptionMethod = [string]$systemVolume.EncryptionMethod
        encryptionPercentage = [int]$systemVolume.EncryptionPercentage
        keyProtectorTypes = @($protectorTypes | Sort-Object -Unique)
        recoveryKeyCaptured = $false
        note = 'This snapshot intentionally does not collect recovery passwords or key identifiers.'
    }
}
catch {
    $warnings.Add("BitLocker status could not be read: $($_.Exception.Message)")
}

$tpm = $null
try {
    $tpmCommand = Get-Command Get-Tpm -ErrorAction Stop
    $tpmStatus = Get-Tpm -ErrorAction Stop
    $tpm = [ordered]@{
        present = [bool]$tpmStatus.TpmPresent
        ready = [bool]$tpmStatus.TpmReady
        enabled = [bool]$tpmStatus.TpmEnabled
        activated = [bool]$tpmStatus.TpmActivated
        owned = [bool]$tpmStatus.TpmOwned
        restartPending = [bool]$tpmStatus.RestartPending
    }
}
catch {
    $warnings.Add("TPM status could not be read: $($_.Exception.Message)")
}

$storageVolume = $null
try {
    $driveLetter = $env:SystemDrive.TrimEnd(':')
    $volume = Get-Volume -DriveLetter $driveLetter -ErrorAction Stop
    $storageVolume = [ordered]@{
        driveLetter = $driveLetter
        fileSystem = [string]$volume.FileSystem
        healthStatus = [string]$volume.HealthStatus
        operationalStatus = @($volume.OperationalStatus | ForEach-Object { [string]$_ })
        sizeBytes = [int64]$volume.Size
        sizeRemainingBytes = [int64]$volume.SizeRemaining
    }
}
catch {
    $warnings.Add("System volume information could not be read: $($_.Exception.Message)")
}

$processorRecords = @()
foreach ($processor in $processors) {
    if ($null -eq $processor) { continue }
    $processorRecords += [ordered]@{
        name = [string]$processor.Name
        manufacturer = [string]$processor.Manufacturer
        processorId = [string]$processor.ProcessorId
        cores = [int]$processor.NumberOfCores
        logicalProcessors = [int]$processor.NumberOfLogicalProcessors
        maxClockMHz = [int]$processor.MaxClockSpeed
        currentClockMHz = [int]$processor.CurrentClockSpeed
    }
}

$batteryRecords = @()
foreach ($battery in $batteries) {
    if ($null -eq $battery) { continue }
    $batteryRecords += [ordered]@{
        name = [string]$battery.Name
        status = [string]$battery.Status
        estimatedChargeRemainingPercent = if ($null -ne $battery.EstimatedChargeRemaining) { [int]$battery.EstimatedChargeRemaining } else { $null }
        batteryStatusCode = if ($null -ne $battery.BatteryStatus) { [int]$battery.BatteryStatus } else { $null }
        estimatedRunTimeMinutes = if ($null -ne $battery.EstimatedRunTime) { [int]$battery.EstimatedRunTime } else { $null }
    }
}

$serviceTag = $null
if ($IncludeServiceTag -and $null -ne $bios) {
    $serviceTag = [string]$bios.SerialNumber
}

$snapshot = [ordered]@{
    schemaVersion = 1
    capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    privacy = [ordered]@{
        serviceTagIncluded = [bool]$IncludeServiceTag
        bitLockerRecoveryMaterialIncluded = $false
        computerNameIncluded = $false
        userNameIncluded = $false
    }
    execution = [ordered]@{
        powerShellVersion = $PSVersionTable.PSVersion.ToString()
        isAdministrator = $isAdministrator
        systemDrive = $env:SystemDrive
    }
    computer = [ordered]@{
        manufacturer = if ($null -ne $computer) { [string]$computer.Manufacturer } else { $null }
        model = if ($null -ne $computer) { [string]$computer.Model } else { $null }
        totalPhysicalMemoryBytes = if ($null -ne $computer) { [int64]$computer.TotalPhysicalMemory } else { $null }
        baseBoardManufacturer = if ($null -ne $baseBoard) { [string]$baseBoard.Manufacturer } else { $null }
        baseBoardProduct = if ($null -ne $baseBoard) { [string]$baseBoard.Product } else { $null }
        baseBoardVersion = if ($null -ne $baseBoard) { [string]$baseBoard.Version } else { $null }
        serviceTag = $serviceTag
    }
    firmware = [ordered]@{
        manufacturer = if ($null -ne $bios) { [string]$bios.Manufacturer } else { $null }
        smbiosVersion = if ($null -ne $bios) { [string]$bios.SMBIOSBIOSVersion } else { $null }
        version = if ($null -ne $bios) { [string]$bios.Version } else { $null }
        releaseDateUtc = if ($null -ne $bios) { Convert-CimDate -Value $bios.ReleaseDate } else { $null }
        secureBootSupported = $secureBootSupported
        secureBootEnabled = $secureBootEnabled
    }
    processors = $processorRecords
    operatingSystem = [ordered]@{
        caption = if ($null -ne $operatingSystem) { [string]$operatingSystem.Caption } else { $null }
        version = if ($null -ne $operatingSystem) { [string]$operatingSystem.Version } else { $null }
        buildNumber = if ($null -ne $operatingSystem) { [string]$operatingSystem.BuildNumber } else { $null }
        architecture = if ($null -ne $operatingSystem) { [string]$operatingSystem.OSArchitecture } else { $null }
        lastBootUpTimeUtc = if ($null -ne $operatingSystem) { Convert-CimDate -Value $operatingSystem.LastBootUpTime } else { $null }
    }
    batteries = $batteryRecords
    systemVolume = $storageVolume
    bitLocker = $bitLocker
    tpm = $tpm
    warnings = $warnings.ToArray()
    operatorChecklist = @(
        'Back up important data.',
        'Save and verify the BitLocker recovery key outside this laptop.',
        'Download the exact Dell BIOS installer and record its SHA-256.',
        'Read the exact model recovery procedure.',
        'Record every original firmware-variable byte before changing it.',
        'Use UEFITool and IFRExtractor on the exact target firmware; never reuse another laptop offset.'
    )
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Get-Location).Path ('dell-undervolt-preflight-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
}
$outputFull = [System.IO.Path]::GetFullPath($OutputPath)
$outputParent = Split-Path -Parent $outputFull
if (-not [string]::IsNullOrWhiteSpace($outputParent) -and -not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
}
$snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputFull -Encoding UTF8

Write-Host "Preflight snapshot saved to '$outputFull'." -ForegroundColor Green
Write-Host 'No BitLocker recovery password, username, computer name, or firmware dump was collected.'
if (-not $IncludeServiceTag) {
    Write-Host 'Service tag collection was disabled.'
}
if ($warnings.Count -gt 0) {
    Write-Warning ($warnings -join "`n")
}
