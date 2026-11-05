# Stray on iOS — research log

> Can the original Apple-silicon macOS build of **Stray** run on an iPhone?
>
> This repository documents a personal compatibility experiment based on [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). It is a research log, not a game port, installer, or claim of full playability.

**Current verified milestone: the original macOS build reaches Stray's initial brightness-calibration screen on an iPhone 17 Pro Max.** The app has not yet been demonstrated to reach the main menu or sustained gameplay.

[En español](README.es.md) · [Technical timeline](docs/MILESTONES.md) · [Architecture](docs/ARCHITECTURE.md) · [Known issues](docs/KNOWN-ISSUES.md)

---

## What this is

This project records the work required to run a native ARM64 macOS game binary in an iOS app container using the compatibility framework and shims from the upstream project. The Stray executable itself remains the original macOS build; the work so far has concentrated on bundle conversion, macOS API compatibility, platform detection, resource paths, IOKit GPU discovery and Metal behavior.

This is **not** a native iOS port, a game redistribution, a DRM bypass, or proof that arbitrary Mac games can run on iOS.

## Current result

Test environment:
- MacBook Air M4, 16 GB unified memory.
- iPhone 17 Pro Max.
- iOS 27.3 beta was shown in the performance overlay during the recorded test.
- Unreal Engine 4.27-era Mac build.
- Metal on the iPhone Apple GPU.

Observed in phase G:
- Launch succeeds through `devicectl` when supplied with the project path and `-basedir`.
- The IOKit adapter exposes the GPU descriptor structure Unreal expects, based on the actual iPhone GPU.
- Unreal passes the previously empty GPU-descriptor path.
- Targeted Metal hooks translate observed macOS `MTLStorageModeManaged` requests to iOS `Shared`.
- Metal library loading succeeds in the observed log.
- Stray displays its autosave warning and brightness-calibration UI.
- The overlay/log reports roughly 59–62 FPS during parts of this short run. This is not a benchmark.
- The process exits with status 0 after the app transitions to the background; this was not the earlier Metal validation crash.

Reaching calibration does **not** prove full playability. See [milestones](docs/MILESTONES.md).

## What remains

1. Diagnose direct SpringBoard icon launch (user reports immediate close); the missing-arguments explanation is plausible, not confirmed.
2. Fix distorted landscape presentation by tracing UIKit, `CAMetalLayer.drawableSize`, Unreal viewport dimensions and rotation.
3. Prove end-to-end input. UIKit touch-began events are logged, but movement, camera and action events have not been validated in Unreal.
4. Navigate the original UI, reach the main menu and attempt gameplay.
5. Test longer-run stability, thermal behavior, memory, audio and background/foreground lifecycle.

See [known issues](docs/KNOWN-ISSUES.md) and [display/input investigation](docs/DISPLAY-AND-INPUT.md).

## Layout

- `README.md` — English overview
- `README.es.md` — resumen en español
- `UPSTREAM.md` — attribution and license boundary
- `PUBLISHING-SCOPE.md` — what must never be published
- `CONTRIBUTING.md` — contribution guidelines
- `docs/ARCHITECTURE.md` — system layers
- `docs/MILESTONES.md` — observed progress
- `docs/METAL-COMPATIBILITY.md` — Managed/Shared investigation
- `docs/DISPLAY-AND-INPUT.md` — orientation and input plan
- `docs/KNOWN-ISSUES.md` — verification matrix
- `docs/REDDIT-DRAFT-EN.md` — English post draft
- `docs/REDDIT-DRAFT-ES.md` — Spanish post draft

## Upstream and attribution

This work builds on [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). See [UPSTREAM.md](UPSTREAM.md) and the upstream [MIT license](https://github.com/zorrobyte/macos-on-ios-public/blob/main/LICENSE). This repository does not relicense upstream code or claim ownership of it.

## Safety and distribution

Use only game copies you legitimately own and devices/accounts you control. No Stray executable, PAKs, extracted assets, certificates, provisioning profiles, device identifiers or signed app packages belong here. Do not distribute converted copies of the game.

See [PUBLISHING-SCOPE.md](PUBLISHING-SCOPE.md). This is an unofficial independent experiment, not affiliated with or endorsed by Annapurna Interactive, BlueTwelve Studio, Apple or the upstream maintainer.
