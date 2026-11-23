# Stray on iOS — Technical Compatibility Research

> Can the original Apple Silicon macOS build of Stray run inside an iOS app on a physical iPhone?

**This is an unfinished, independent compatibility experiment. It is not an official iOS port and the game is not yet visually playable.**

[Current device state & community review](COMMUNITY-REVIEW.md) · [Project status](PROJECT_STATUS.md) · [Development roadmap](ROADMAP.md) · [Architecture](docs/ARCHITECTURE.md) · [Current blockers](docs/CURRENT_BLOCKERS.md)

## Current result — 2026-11-23

The adapted application now installs and launches on a physical iPhone 17 Pro Max running iOS 27.3. It displays UI and menus, and a DualShock 4 is recognized.

The 3D presentation is still broken:
- The Stray title/menu scene does not visibly show the cat with white eyes, the Stray logo, or its expected background. The screen is black apart from UI/menu elements.
- Starting the game does not produce a visibly rendered 3D world.
- The application initially appears in portrait; rotating to landscape produces a severely stretched image.
- Minimal, controller-aware touch controls remain to be implemented and tested.

Metal library loading, render-encoder creation, drawable presentation, and completed command buffers have been observed. Those events do not prove that Unreal's scene geometry and final image are rendering correctly.

The latest reported exit code 9 occurred because the user manually closed the application. It was **not a crash**.

See [COMMUNITY-REVIEW.md](COMMUNITY-REVIEW.md) for exact observations, help wanted, and safe contribution boundaries.

## What help is needed

1. UIKit orientation, window/view geometry, CAMetalLayer drawable sizing, and Unreal viewport sizing.
2. UE4 Metal RHI, render passes, shader/pipeline state, scene draw calls, and render-target inspection.
3. Camera, level loading, mesh rendering, materials, textures, lighting, and post-processing.
4. GameController / DualShock 4 integration and minimal touch controls.

Technical review and reproducible findings are welcome. Use the [technical review issue template](.github/ISSUE_TEMPLATE/technical-review.yml).

## Research-only publishing boundary

This repository may contain original research code, sanitized logs, configuration snippets, technical notes, and minimal test harnesses after provenance and privacy review.

It must not contain Stray executables, app bundles, PAK/UCAS/UTOC archives, extracted game resources, textures, models, audio, Apple signing certificates, provisioning profiles, private keys, credentials, tokens, or private device identifiers. Third-party code may only be redistributed when its license permits it and required notices are preserved.

Reviewers must own a legitimate copy of the game and use their own local files. See [UPSTREAM.md](UPSTREAM.md), [PUBLISHING-SCOPE.md](PUBLISHING-SCOPE.md), and [CONTRIBUTING.md](CONTRIBUTING.md).

## Development status

| Area | Status |
|---|---|
| App installation and launch | Verified on physical iPhone |
| UI and menus | Visible |
| DualShock 4 recognition | Observed |
| Landscape orientation / aspect ratio | Broken |
| Stray title/menu 3D scene | Not visibly rendered |
| Gameplay 3D world | Not visibly rendered |
| Touch controls | Incomplete / planned |
| Audio | Not verified |
| Sustained performance and thermals | Not verified |

No stage is considered complete merely because the app launches or Metal command buffers complete. Claims of working 3D rendering require visual confirmation on the physical device.

## Upstream

Compatibility infrastructure is derived from [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). This repository distinguishes upstream infrastructure from Stray-specific research and does not claim ownership of the game or its assets.
