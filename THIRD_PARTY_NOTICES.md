# Third-party notices

This repository's original scripts and documentation are MIT-licensed. A maintainer-created full Release may also contain the components below. Each remains under its own licence or terms; inclusion does not relicense it under MIT.

The source Git repository intentionally excludes executable binaries. Maintainers must review current terms before publishing a Release.

| Component | Upstream / author | Licence or status | Packaging note |
|---|---|---|---|
| BIOSUtilities | Plato Mavropoulos, `platomav/BIOSUtilities` | BSD-2-Clause-Patent | Source from the supplied archive may be included with its licence. |
| UEFITool | Nikolaj Schlej / LongSoft, `LongSoft/UEFITool` | BSD 2-Clause | Include the licence with redistributed binaries. |
| Legacy Universal IFR Extractor | Donovan6000; later rewrite and fixes by community contributors, `LongSoft/Universal-IFR-Extractor` | GPL-3.0 | The bundled file is named `IRFExtractor.exe`; retain GPL notices and source-offer obligations applicable to the distributed build. |
| IFRExtractor-RS | `LongSoft/IFRExtractor-RS` contributors | BSD 2-Clause for the reviewed upstream licence | Recommended modern alternative; verify the exact revision and retain its notice. |
| EDK II UEFI Shell build | TianoCore contributors; prebuilt distribution by Pete Batard, `pbatard/UEFI-Shell` | BSD-2-Clause-Patent and upstream notices | The supplied `BOOTX64.EFI` hash is recorded in the README. |
| RU.EFI | James Wang | Closed-source binary; upstream terms must be reviewed | Optional Release payload only. It is excluded from Git and can be supplied locally. |
| ThrottleStop | Kevin Glynn (unclewebb), distributed by TechPowerUp | Proprietary/freeware terms | Do not imply MIT coverage. Review redistribution permission for the exact package. |
| HWiNFO64 | Martin Malik / REALiX | Proprietary/freeware terms | Review the current licence for redistribution and commercial use. |
| 7-Zip | Igor Pavlov | Primarily GNU LGPL with unRAR restrictions and additional notices | Include upstream licence material for the exact installer. |
| Python | Python Software Foundation and contributors | PSF Licence Agreement and bundled third-party notices | The official installer contains its own licence material. |
| Microsoft Visual C++ Redistributables | Microsoft | Microsoft redistributable terms | Review the applicable Visual Studio licence before redistribution. |

## Known tutorial-package hashes

These values identify the exact files inspected while preparing the repository package:

```text
BOOTX64.EFI  4ea080ddd576117cd04f5c02d16712ea5d9249c0752214d8e4055e460d7b11e0
RU.EFI       a05eef8b029c637112a4451ca96c875bf4ee23e04738b522b9360d9b744877f2
```

A hash proves only byte identity. It does not prove authorship, safety, suitability, or redistribution permission.

## Included licence texts

The `third_party/licenses` directory contains licence copies for open-source components present in the tutorial archive when an authoritative text was available. Proprietary software retains the notices bundled by its publisher.

## No endorsement

All trademarks and product names belong to their respective owners. This project is independent and is not endorsed by the third-party authors or vendors.
