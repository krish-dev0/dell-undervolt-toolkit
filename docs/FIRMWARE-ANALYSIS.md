# Firmware analysis with UEFITool and IFRExtractor

This workflow is deliberately model- and BIOS-version-specific. There is no safe universal list of offsets for Dell laptops.

> [!CAUTION]
> Analyse the exact firmware installed on the target computer. A firmware update can move a setting, change its VarStore, rename it, remove it, or change the option values while leaving the human-readable label unchanged.

## Evidence to record first

Create a copy of [`../examples/offset-worksheet.csv`](../examples/offset-worksheet.csv) and record:

- laptop model and motherboard revision, when available;
- exact BIOS version and release date;
- Dell BIOS installer filename and SHA-256;
- extracted system BIOS image filename and SHA-256;
- extracted Setup PE32 module filename and SHA-256;
- UEFITool and IFRExtractor versions;
- variable name, variable GUID or VarStore identity, VarStore ID, offset, current value, and option mapping.

A display name such as `CPU Setup` is not a unique identifier. Firmware can contain multiple variables or forms with the same visible name.

## 1. Extract the Dell update package

Use the helper after initialising BIOSUtilities:

```powershell
.\scripts\Initialize-BiosUtilities.ps1 -SourceRoot .
.\scripts\Extract-DellBios.ps1 `
  -SourceRoot . `
  -BiosFile 'C:\Firmware\Exact-Dell-BIOS.exe' `
  -OutputDirectory 'C:\Firmware\Extracted'
```

The helper records the input hash and lists likely large firmware images. Do not assume that the first or largest output is automatically the correct system BIOS region; compare filenames, extraction logs, sizes, and UEFITool contents.

## 2. Locate the Setup module in UEFITool

1. Open the extracted system BIOS image in UEFITool.
2. Use **Action > Search > Text** and search for one setting at a time, for example `Overclocking Lock` or `CFG Lock`.
3. Follow the search result to the containing firmware file and PE32 image section.
4. Record the file GUID and surrounding module identity.
5. Extract the body or PE32 image in the form expected by the selected IFR extractor.
6. Hash the extracted module before processing it.

Different UEFITool generations expose slightly different menu names. Use the tool version consistently and record it in the worksheet.

## 3. Convert the Setup module to IFR text

The supplied archive names the legacy executable `IRFExtractor.exe`; the established term is **IFR**, or Internal Forms Representation. New repositories may use IFRExtractor-RS instead of the legacy Universal IFR Extractor.

Example command patterns vary by build:

```powershell
# Legacy GUI build: select the extracted Setup module and an output .txt file.

# IFRExtractor-RS example; confirm the exact syntax shown by your downloaded build:
IFRExtractor-RS.exe 'Setup.bin' 'Setup.ifr.txt'
```

Do not treat a successful extraction as proof that the selected module is correct. Open the text and verify that it contains the expected form, questions, variable references, and option labels.

## 4. Resolve the complete variable identity

For every proposed setting, find and record all available fields:

- `Prompt` or display name;
- `VarOffset`;
- `VarStore` or VarStore ID;
- variable name, such as `CpuSetup` or `PchSetup`;
- variable GUID, when shown or resolved through the VarStore declaration;
- option labels and their numeric values;
- current value read from the target machine.

Do not select a variable only because its display name matches a tutorial. In the tutorial machine, the operator moved past one `CPU Setup` entry and used another. That is exactly why the complete identity matters.

## 5. Interpret the option mapping

A typical IFR fragment may conceptually describe a one-byte question with two options:

```text
Prompt: Example Lock
VarOffset: 0x123
VarStore: 0x7
Option: Disabled, Value: 0x0
Option: Enabled, Value: 0x1
```

This illustration is not an offset or instruction for a real computer. The numeric meaning must come from the exact extracted IFR. Some questions use bit fields, wider integers, enums, defaults, or conditional forms rather than a simple one-byte switch.

## 6. Cross-check before opening RU.EFI

Before any manual firmware-variable change, confirm all of the following:

- target machine model and BIOS version match the recorded evidence;
- BIOS installer and extracted file hashes still match;
- the variable name/GUID or VarStore identity matches, not just the label;
- the intended offset is inside the expected variable size;
- the current byte matches the value predicted by the IFR option mapping;
- the original value has been written down separately;
- the recovery plan in [`RECOVERY.md`](RECOVERY.md) has been read and prepared.

If the current byte does not match the expected option, stop. A mismatch is useful evidence that the wrong variable, wrong firmware image, wrong offset, or wrong interpretation is being used.

## Tutorial example, not a lookup table

The recording used a Dell Precision 3551 with an Intel Core i5-10300H and demonstrated these addresses for that analysed firmware:

| Setting | Variable shown | Offset shown | Demonstrated change |
|---|---|---:|---:|
| Overclocking Lock | `CpuSetup` | `0xDA` | `0x01 -> 0x00` |
| CFG Lock | `CpuSetup` | `0x3E` | `0x01 -> 0x00` |
| BIOS Lock | `PchSetup` | `0x17` | `0x01 -> 0x00` |

The recording does not establish a portable preset, and the exact BIOS version/GUID evidence is not part of that example. `BIOS Lock` affects firmware write protection and is not universally necessary for undervolting. Re-derive every value from the target firmware and change only what the target workflow actually requires.

## Repeat after every firmware change

Repeat the complete extraction and analysis after:

- a BIOS update or downgrade;
- a motherboard replacement;
- loading a materially different firmware configuration;
- switching to another laptop, even the same marketed model;
- discovering that the current variable value no longer matches the worksheet.

Never assume that a previously valid offset survived an update.
