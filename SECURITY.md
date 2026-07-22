# Security policy

## Scope

Security reports are welcome for the original PowerShell scripts, packaging workflow, checksum verification, and documentation in this repository.

Third-party binaries are outside this project's source-security scope. Report vulnerabilities in those components to their respective authors or distributors.

## Reporting

Open a private GitHub security advisory when the repository is published. Do not publish an exploit, malicious Release asset, token, BitLocker key, service tag, firmware dump containing private data, or other sensitive information in a public issue.

## Release integrity

Official project Release assets should include:

- an asset-specific `.sha256` sidecar;
- an internal `manifest.json` covering packaged files;
- release notes stating whether RU.EFI is included;
- provenance and licensing notes for every bundled binary.

The installer verifies available checksums but cannot establish trust if the GitHub account, repository, release, and checksum are all compromised together. Users should review scripts and compare hashes through an independent trusted channel for high-assurance use.
