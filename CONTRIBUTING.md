# Contributing

Contributions should keep the project model-agnostic and recovery-first.

- Never present a firmware offset as universal.
- Include the exact model, motherboard revision when known, BIOS version, BIOS executable SHA-256, extracted module SHA-256, VarStore/GUID, original value, and option mapping with any example.
- Do not add automated UEFI-variable writes.
- Do not commit proprietary or closed-source binaries without documented redistribution permission.
- Keep PowerShell compatible with Windows PowerShell 5.1 unless a change is explicitly documented.
- Add or update tests and documentation for script changes.
- Do not submit personal service tags, BitLocker keys, serial numbers, or full firmware dumps containing private information.
