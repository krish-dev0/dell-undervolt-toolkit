# Publishing Releases

The Git repository is source-only. Third-party executables are added only to an explicit Release package built from a maintainer-supplied `BIOSMod.zip`.

## 1. Review the input archive

Before every Release:

- obtain the archive from a trusted local source;
- inspect every executable and nested archive;
- record hashes and provenance;
- review each project's licence and redistribution terms;
- scan the package with the organisation's normal malware-analysis process;
- remove personal firmware dumps, service tags, BitLocker material, logs, and configuration files;
- decide whether RU.EFI may be distributed in that Release.

A checksum detects later byte changes; it is not a licence grant or malware verdict.

## 2. Set repository metadata

Replace the placeholder throughout the source tree, then review the diff:

```powershell
.\scripts\Set-RepositoryMetadata.ps1 -Repository 'YOUR-ACCOUNT/dell-undervolt-toolkit'
```

Alternatively, edit [`../config/repository.json`](../config/repository.json) and pass `-Repository` to the build script:

```json
{
  "repository": "YOUR-ACCOUNT/dell-undervolt-toolkit"
}
```

## 3. Build the full asset locally

From a Windows PowerShell 5.1 window at the repository root:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Build-Release.ps1 `
  -SourceArchive 'C:\ReleaseInput\BIOSMod.zip' `
  -Version '1.0.0' `
  -Repository 'YOUR-ACCOUNT/dell-undervolt-toolkit'
```

The script creates:

- `dell-undervolt-toolkit-<version>-full.zip`;
- a matching `.sha256` file;
- `dell-undervolt-toolkit-<version>-usb.zip`;
- a matching USB checksum;
- generated release notes.

The full ZIP contains the repository, `Toolkit/BIOSMod`, a canonical `USB/EFI/BOOT` directory, `build-info.json`, and `manifest.json`. The nested USB ZIP from the input archive is removed after extraction so RU.EFI is not hidden in a duplicate archive.

## 4. Build the no-RU fallback

```powershell
.\scripts\Build-Release.ps1 `
  -SourceArchive 'C:\ReleaseInput\BIOSMod.zip' `
  -Version '1.0.0' `
  -Repository 'YOUR-ACCOUNT/dell-undervolt-toolkit' `
  -ExcludeRuEfi
```

The no-RU package remains useful because users can pass a local file to `install.ps1 -RuEfiPath` or `New-UefiUsb.ps1 -RuEfiPath`.

## 5. Validate the output

Extract the generated full ZIP into a clean directory and run:

```powershell
.\scripts\Test-Toolkit.ps1 -SourceRoot . -RequireFullPayload
```

Also verify that:

- the external `.sha256` file matches the ZIP;
- every `manifest.json` entry matches the extracted file;
- the USB ZIP expands directly to `EFI/BOOT`;
- source control contains no third-party executable;
- release notes explicitly state whether RU.EFI is included.

## 6. Publish

Create the GitHub Release for the matching tag and upload the ZIPs and checksum files. Keep the source archive itself outside Git. Do not publish a third-party binary merely because it was present in an older package.

Suggested title:

```text
Dell Undervolt Toolkit v1.0.0
```

The Release description should include the generated notes, binary provenance, licence caveats, and a link to the tutorial.

## Takedown or redistribution concern

Remove the affected Release asset, publish a corrected no-RU or source-only asset, and document the change. The repository installer and local-file workflow are designed to keep working without RU.EFI in the repository or Release.
