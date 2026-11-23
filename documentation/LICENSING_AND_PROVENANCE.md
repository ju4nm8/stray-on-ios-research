# Licensing, Copyright & Provenance Register

This document provides a formal inventory of copyright ownership, open-source licenses, and material provenance for all components published in this repository.

## 1. Upstream Foundation

Our compatibility research builds upon the pioneering translation framework published in [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public).

- **Upstream Author:** Ross Fisher
- **License:** MIT License
- **Upstream Copyright Notice:** `Copyright (c) 2026 Ross Fisher`
- **Permitted Redistribution:** MIT permits redistribution, modification, and sublicense provided the copyright and permission notice are preserved in all copies.
- **Attribution Status:** All compatibility shims, conversion tools, and derived works in this repository retain the full upstream copyright and MIT license notice.

## 2. Stray-Specific Compatibility Code

All original shims, extensions, and modifications developed specifically for this compatibility project are licensed under the MIT License:

- **Copyright:** `Copyright (c) 2026 Stray on iOS Research Contributors`
- **Components:**
  - `source/shims/IOKit.m`: Synthetic IOKit GPU accelerator service adapter.
  - `source/shims/AppKit_RuntimeHooks.m`: Metal texture storage mode translator and UMA cache coherency hooks.
  - `source/shims/AppKit.m`: `FMemory::Realloc` command line injector and logging bridge.
  - `source/shims/libSystem.m`: Case-insensitive `dlopen` interposer and filesystem redirection.
  - `scripts/extract_icu.py`: Standalone ICU extraction utility.
  - `scripts/run_test.sh` / `scripts/watchdog_stray.sh`: Safety test automation harnesses.

## 3. Third-Party Code & Tools (Excluded from Repository)

To maintain absolute legal and copyright integrity, the following third-party repositories and tools were analyzed during static research but are **explicitly excluded** from redistribution in this repository:

| Repository / Project | Upstream License | Exclusion Rationale |
|---|---|---|
| `UEAssetToolkit` | GPL-3.0 | License incompatibility with MIT; requires Windows Unreal Editor. Excluded. |
| `UEAssetToolkitGenerator` | GPL-3.0 | Excluded to prevent license contamination. |
| `RE-UE4SS` | MIT | Windows-only memory scanner/injector. Not needed on iOS. Excluded. |
| `UAssetAPI` | MIT | Third-party .NET library. Referenced for static header format knowledge only. Excluded. |
| `Stray-Local-Co-op-Mod` | Unlicensed / Custom | Third-party mod script (`main.lua`). Referenced for bug analysis only. Excluded. |
| `HK_Project` | Community Reverse-Engineering | Community UHT header stubs. Consulted for class hierarchy mapping only. Excluded. |

## 4. Proprietary Commercial Assets (Strictly Excluded)

This repository contains **NO proprietary game software or assets**:
- **NO `Stray.app` bundle.**
- **NO `Stray-Mac-Shipping` game binary.**
- **NO `.pak`, `.ucas`, or `.utoc` game archives.**
- **NO 3D models, textures, animations, audio files, or cinematics.**
- **NO Apple proprietary framework binaries or SDK code.**

All research and tooling published here require the end-user to possess a legitimately acquired copy of the original macOS game.
