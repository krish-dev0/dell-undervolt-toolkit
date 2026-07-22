# Dell Undervolt Toolkit

Research-oriented scripts and documentation for analysing Dell firmware, preparing a UEFI Shell USB drive, and testing a conservative Intel CPU undervolt on supported laptops.

> \[!CAUTION]
> This is an advanced firmware workflow. A wrong variable, offset, value, or VarStore can make a computer unbootable, weaken platform security, trigger BitLocker recovery, or cause data loss. Firmware layout can change between two BIOS versions of the same laptop. Never copy offsets from another machine or another BIOS build.

The toolkit deliberately **does not write UEFI variables automatically**. It prepares the working environment and USB layout, then leaves firmware analysis and any manual change to the operator.

## Tutorial videos

* Hungarian tutorial: https://www.youtube.com/watch?v=gJBEIfyV7DY
* English tutorial: (coming soon)

## The rule that matters most

`VarOffset`, `VarStore`, variable GUID, and option values are **not universal**. They may differ by:

* laptop model and motherboard revision;
* BIOS version and firmware region;
* CPU generation and OEM configuration;
* a BIOS update, downgrade, reset, or security mitigation.

Use **UEFITool plus IFRExtractor** on the exact firmware installed on the target computer. Record the variable name, GUID/VarStore, offset, original byte, and intended byte before opening RU.EFI. If two variables have the same display name, the name alone is not enough to identify the correct one.

## What is included

* `install.ps1` - local or GitHub Release installer with SHA-256 verification.
* `scripts/New-UefiUsb.ps1` - creates the standard `EFI/BOOT` layout without formatting a drive.
* `scripts/Initialize-BiosUtilities.ps1` - creates an isolated Python virtual environment.
* `scripts/Extract-DellBios.ps1` - runs the Dell PFS extractor non-interactively.
* `scripts/Get-PreflightSnapshot.ps1` - records model, BIOS, CPU, Secure Boot, and BitLocker status.
* `scripts/Test-Toolkit.ps1` - validates the repository or an installed/release package.
* `scripts/Build-Release.ps1` - converts the maintainer's `BIOSMod.zip` into release-ready assets.
* `scripts/Uninstall-Toolkit.ps1` - safely removes installed toolkit files without touching firmware settings.
* `scripts/Set-RepositoryMetadata.ps1` - replaces the `OWNER` placeholder after the GitHub owner is known.
* Detailed analysis, USB, validation, recovery, and release documentation.
* A model-specific example from the tutorial, clearly marked as non-portable.

## What is not in the source repository

The source repository intentionally excludes third-party executable files, including `RU.EFI`, ThrottleStop, HWiNFO, UEFITool, IFRExtractor, prerequisite installers, and the UEFI Shell binary. A maintainer may place approved copies in a GitHub Release after reviewing the applicable licences and redistribution terms.

The supplied `BOOTX64.EFI` has SHA-256:

```text
4ea080ddd576117cd04f5c02d16712ea5d9249c0752214d8e4055e460d7b11e0
```

That hash matches the x64 EDK II UEFI Shell build distributed by the `pbatard/UEFI-Shell` project. The supplied `RU.EFI` has SHA-256:

```text
a05eef8b029c637112a4451ca96c875bf4ee23e04738b522b9360d9b744877f2
```

A hash identifies exact bytes; it does not by itself grant redistribution rights or prove that a binary is safe.

## Before doing anything

1. Back up important data.
2. Save the BitLocker recovery key and verify that it is readable.
3. Download the exact Dell BIOS installer currently used by the machine and record its SHA-256 hash.
4. Read the model-specific Dell BIOS recovery instructions and confirm that recovery is supported.
5. Use AC power and a charged battery.
6. Record the current BIOS version, Secure Boot state, and original values of every byte you may change.
7. Do not experiment on a computer that cannot be taken out of service.

Run the preflight snapshot from an elevated PowerShell window:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\\scripts\\Get-PreflightSnapshot.ps1
```

See [Recovery and rollback](docs/RECOVERY.md) before proceeding.



## Installation

### Install from an extracted Release package

Extract the Release ZIP, open PowerShell in that directory, and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\\install.ps1 -SourceDirectory . -InstallDirectory "$env:LOCALAPPDATA\\DellUndervoltToolkit"
```

To supply a locally obtained RU.EFI at install time:

```powershell
.\\install.ps1 `
  -SourceDirectory . `
  -RuEfiPath "C:\\Users\\You\\Downloads\\RU.EFI" `
  -InstallDirectory "$env:LOCALAPPDATA\\DellUndervoltToolkit"
```

### Install the latest GitHub Release

Replace `OWNER` with the GitHub account or organisation that owns the repository:

```powershell
$repo = 'krish-dev0/dell-undervolt-toolkit
'
$installer = Join-Path $env:TEMP 'dell-undervolt-toolkit-install.ps1'
Invoke-WebRequest "https://raw.githubusercontent.com/$repo/main/install.ps1" -OutFile $installer
notepad $installer
\& $installer -Repository $repo
```

The two-step form lets the user inspect the script before execution. The installer selects a Release asset matching `dell-undervolt-toolkit-\*-full.zip`, downloads the matching `.sha256` sidecar when present, verifies it, extracts the package, and verifies `manifest.json` when included.

A source-only repository has no third-party payload. In that case installation succeeds, but the analysis tools and USB binaries must be supplied separately.

## RU.EFI distribution options

The installer supports all of these layouts:

1. **Local file, recommended fallback**

```powershell
   .\\install.ps1 -Repository 'krish-dev0/dell-undervolt-toolkit
' -RuEfiPath 'D:\\Downloads\\RU.EFI'

' -RuEfiPath 'D:\\Downloads\\RU.EFI'

```

2. \*\*Included inside a maintainer-created full Release ZIP\*\*

   `scripts/Build-Release.ps1` can extract the user-supplied `BIOSMod.zip`, place RU.EFI under `USB/EFI/BOOT`, generate a file manifest, and create a checksummed Release asset.

3. \*\*No-RU Release\*\*

   Build with `-ExcludeRuEfi`. Users then provide RU.EFI locally. If an RU-containing asset is removed after a takedown request, the source repository and local-file workflow continue to work.

The installer never downloads RU.EFI from an unknown mirror.

## Prepare BIOSUtilities

After installing the full toolkit:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
\& "$env:LOCALAPPDATA\\DellUndervoltToolkit\\scripts\\Initialize-BiosUtilities.ps1" `
  -SourceRoot "$env:LOCALAPPDATA\\DellUndervoltToolkit"
```

The script creates a local `.venv` next to BIOSUtilities and installs `requirements.txt`. It does not modify the system Python package set. BIOSUtilities in the supplied archive documents Python 3.10 through 3.13 as its tested range; Python 3.14 can be allowed explicitly, but should be treated as untested for that bundled revision.

## Extract a Dell BIOS package

Download the BIOS executable for the exact target model and firmware build, then run:

```powershell
\& "$env:LOCALAPPDATA\\DellUndervoltToolkit\\scripts\\Extract-DellBios.ps1" `
  -BiosFile 'C:\\Path\\To\\DellBIOS.exe' `
  -OutputDirectory 'C:\\DellUndervoltWork\\Extracted' `
  -SourceRoot "$env:LOCALAPPDATA\\DellUndervoltToolkit"
```

Continue with [Firmware analysis](docs/FIRMWARE-ANALYSIS.md). The essential sequence is:

1. Extract the Dell PFS package.
2. Open the extracted system BIOS image in UEFITool.
3. Search for each setting, such as `Overclocking Lock` or `CFG Lock`.
4. Extract the PE32 Setup module that contains the result.
5. Convert that module to human-readable IFR text with IFRExtractor.
6. Record the exact VarStore/GUID, offset, original value, and desired option value.
7. Repeat the analysis after every BIOS change.

## Prepare the UEFI USB directory or drive

The script never formats media. Format the intended USB drive as FAT32 yourself, verify the drive letter, then run:

```powershell
\& "$env:LOCALAPPDATA\\DellUndervoltToolkit\\scripts\\New-UefiUsb.ps1" `
  -SourceRoot "$env:LOCALAPPDATA\\DellUndervoltToolkit" `
  -Destination 'E:\\' `
  -Force
```

For a local RU.EFI:

```powershell
\& "$env:LOCALAPPDATA\\DellUndervoltToolkit\\scripts\\New-UefiUsb.ps1" `
  -SourceRoot "$env:LOCALAPPDATA\\DellUndervoltToolkit" `
  -Destination 'C:\\DellUndervoltWork\\USB-Payload' `
  -RuEfiPath 'C:\\Users\\You\\Downloads\\RU.EFI'
```

Expected layout:

```text
USB root/
â””â”€â”€ EFI/
    â””â”€â”€ BOOT/
        â”œâ”€â”€ BOOTX64.EFI
        â””â”€â”€ RU.EFI
```

See [UEFI USB preparation](docs/UEFI-USB.md).

## Tutorial machine example - not a preset

The following values are transcribed from the tutorial. They apply only to the exact firmware analysed in that recording and are included to explain the workflow, **not** to provide reusable addresses or tuning defaults.

|Item|Tutorial example|
|-|-|
|Laptop|Dell Precision 3551|
|CPU|Intel Core i5-10300H|
|`Overclocking Lock`|`CpuSetup`, offset `0xDA`, demonstrated change `0x01 -> 0x00`|
|`CFG Lock`|`CpuSetup`, offset `0x3E`, demonstrated change `0x01 -> 0x00`|
|`BIOS Lock`|`PchSetup`, offset `0x17`, demonstrated change `0x01 -> 0x00`|
|CPU Core voltage offset|`-120 mV` shown in the video|
|CPU Cache voltage offset|`-80 mV` shown in the video|
|Intel GPU / Unslice|approximately `-25 mV` shown in the video|
|Turbo ratios|`40 / 38 / 36` shown in the video|
|Long / short package power|approximately `35 W / 37 W` shown in the video|

Do not import these values into another laptop. Even another Precision 3551 can use different offsets after a BIOS update. `BIOS Lock` is also a write-protection control and is not a universal undervolting requirement; changing it can reduce firmware protection. Modify only settings that your exact analysis and recovery plan justify.

A machine-readable copy is in [`examples/precision-3551-video-example.json`](examples/precision-3551-video-example.json). Use [`examples/offset-worksheet.csv`](examples/offset-worksheet.csv) for the target system.

## ThrottleStop validation

Unlocking a firmware control does not make a particular undervolt stable. Begin near stock, change one category at a time, and validate:

* idle, sleep, resume, shutdown, and cold boot;
* AC and battery operation;
* TS Bench and a sustained CPU stress test;
* the real rendering, compilation, or gaming workload;
* WHEA errors, application crashes, freezes, and silent calculation errors;
* temperatures, clock consistency, power-limit flags, and thermal throttling.

Voltage offsets, turbo ratios, and package power limits are separate controls. A stable voltage offset does not prove that an aggressive power or turbo profile is safe. See [Undervolt validation](docs/UNDERVOLT-VALIDATION.md).

## Security notes

Modern firmware may intentionally disable voltage control as a mitigation for undervolting-related security issues. Bypassing an OEM lock can restore tuning capability while also reversing part of the vendor's security posture. Do not use this workflow on managed, security-sensitive, or untrusted multi-user systems.

Disabling Secure Boot to launch an unsigned shell reduces boot-chain protection. Restore the original Secure Boot state after the manual operation when the platform permits it. Firmware and Secure Boot changes can trigger BitLocker recovery, so keep the recovery key available.

The tutorial also demonstrates disabling UEFI capsule updates to prevent an operating system update from replacing the modified firmware settings. That can delay security fixes. A safer operational policy is to keep automatic firmware updates enabled unless there is a specific, documented reason to pause them, and to reanalyse every new BIOS before applying any manual setting again.

## Repository structure

```text
.
â”œâ”€â”€ install.ps1
â”œâ”€â”€ config/
â”œâ”€â”€ docs/
â”œâ”€â”€ examples/
â”œâ”€â”€ payload/                 # intentionally empty in source control
â”œâ”€â”€ scripts/
â”œâ”€â”€ tests/
â”œâ”€â”€ third\_party/
â””â”€â”€ .github/
```

Release packages add:

```text
Toolkit/BIOSMod/             # maintainer-supplied third-party tools
USB/EFI/BOOT/                # UEFI Shell and optionally RU.EFI
manifest.json                # SHA-256 for every packaged file
```

## Maintainer release workflow

See [Publishing Releases](docs/RELEASING.md). Typical commands:

```powershell
.\\scripts\\Build-Release.ps1 `
  -SourceArchive 'C:\\Path\\To\\BIOSMod.zip' `
  -Version '1.0.0' `
  -Repository 'krish-dev0/dell-undervolt-toolkit
'
```

No-RU fallback:

```powershell
.\\scripts\\Build-Release.ps1 `
  -SourceArchive 'C:\\Path\\To\\BIOSMod.zip' `
  -Version '1.0.0' `
  -Repository 'krish-dev0/dell-undervolt-toolkit
' `
  -ExcludeRuEfi
```

## Credits

* **Krisztian Homoki** - original tutorial, test system, and toolkit concept.
* **James Wang** - RU.EXE / RU.EFI.
* **LongSoft contributors** - UEFITool and IFRExtractor projects.
* **Plato Mavropoulos** - BIOSUtilities.
* **Kevin Glynn (unclewebb)** - ThrottleStop.
* **Martin Malik / REALiX** - HWiNFO.
* **TianoCore contributors and Pete Batard** - EDK II UEFI Shell build and distribution.
* **Igor Pavlov** - 7-Zip.
* **Python Software Foundation** - Python.
* The firmware research community whose documentation made these workflows understandable.

See [Credits](CREDITS.md) and [Third-party notices](THIRD_PARTY_NOTICES.md) for project links and licensing notes.

## Licence

The original scripts and documentation in this repository are licensed under the MIT Licence. Third-party tools and binaries remain under their own licences and are not relicensed by this project. See [`LICENSE`](LICENSE), [`DISCLAIMER.md`](DISCLAIMER.md), and [`THIRD\_PARTY\_NOTICES.md`](THIRD_PARTY_NOTICES.md).

