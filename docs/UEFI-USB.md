# UEFI USB preparation

The toolkit stages a standard removable-media path:

```text
EFI/BOOT/BOOTX64.EFI
EFI/BOOT/RU.EFI
```

`BOOTX64.EFI` is an x64 UEFI Shell binary. From the shell, the operator can start `RU.EFI` manually.

## Safety design

`scripts/New-UefiUsb.ps1`:

- never formats a disk;
- never repartitions a disk;
- refuses the Windows system drive;
- requires `-Force` before writing directly to a drive root;
- checks that a drive-root destination uses FAT32 when Windows exposes the filesystem information;
- copies only the expected UEFI files and small toolkit metadata files;
- verifies copied SHA-256 hashes.

The safest first run targets a normal directory:

```powershell
.\scripts\New-UefiUsb.ps1 `
  -SourceRoot . `
  -Destination 'C:\DellUndervoltWork\USB-Payload' `
  -RuEfiPath 'C:\Downloads\RU.EFI'
```

Inspect the output, then copy the `EFI` directory to a known, empty FAT32 USB drive.

## Direct drive-root staging

After formatting and checking the intended USB drive yourself:

```powershell
Get-Volume -DriveLetter E
.\scripts\New-UefiUsb.ps1 `
  -SourceRoot . `
  -Destination 'E:\' `
  -RuEfiPath 'C:\Downloads\RU.EFI' `
  -Force
```

The script does not delete unrelated files from the drive. Use a dedicated USB drive to avoid ambiguity.

## How the script finds the files

The script accepts explicit `-ShellEfiPath` and `-RuEfiPath` values. Without explicit paths it checks, in order:

1. a Release package's `USB/EFI/BOOT` directory;
2. the source repository's `payload/EFI/BOOT` directory;
3. the maintainer package's nested USB ZIP under `Toolkit/BIOSMod` or `BIOSMod`;
4. a narrowly scoped recursive search under the selected source root.

The source repository intentionally contains neither binary. A full Release may contain both. A no-RU Release requires a local `-RuEfiPath`.

## Secure Boot and BitLocker

An unsigned UEFI Shell may not launch while Secure Boot is enabled. Changing Secure Boot or firmware variables can trigger BitLocker recovery on the next boot. Save and verify the recovery key before changing firmware configuration, and restore the original Secure Boot policy after the manual task when the platform permits it.

## Shell use

UEFI Shell filesystem mappings are commonly displayed as `FS0:`, `FS1:`, and similar names. Select the mapping that contains the `EFI` directory, then run the tool by its path or, when the current directory contains it:

```text
RU.EFI
```

Do not write any variable until the complete identity, original value, desired option, and recovery plan have been verified for the exact firmware.
