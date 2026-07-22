# Payload directory

The source repository intentionally contains no third-party binaries.

A maintainer-created Release can add:

```text
USB/EFI/BOOT/BOOTX64.EFI
USB/EFI/BOOT/RU.EFI        # optional
Toolkit/BIOSMod/...
```

Do not commit RU.EFI or other third-party executable files to the source tree. Use `scripts/Build-Release.ps1` to create an explicit, checksummed Release asset from a locally supplied archive.
