# Stray on iOS — research log

> Can the original Apple-silicon macOS build of **Stray** run on an iPhone?
>
> This repository documents a personal compatibility experiment based on [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). It is a research log, not a game port, installer, or claim of full playability.

**Latest experiment: Stray reaches its menus and enters a 3D level on the iPhone. Runs 4/5 render selected textured pipework and structural geometry, but most of the scene remains black and the cat/ground/walls are not clearly visible in the latest captures. Gameplay is not yet verified.**

[En español](README.es.md) · [Technical timeline](docs/MILESTONES.md) · [Architecture](docs/ARCHITECTURE.md) · [Known issues](docs/KNOWN-ISSUES.md)

---

## What this is

This project records the work required to run a native ARM64 macOS game binary in an iOS app container using the compatibility framework and shims from the upstream project. The Stray executable itself remains the original macOS build; the work so far has concentrated on bundle conversion, macOS API compatibility, platform detection, resource paths, IOKit GPU discovery and Metal behavior.

This is **not** a native iOS port, a game redistribution, a DRM bypass, or proof that arbitrary Mac games can run on iOS.

## Current result

Test environment:
- MacBook Air M4, 16 GB unified memory.
- iPhone 17 Pro Max.
- iOS 27.3 beta was shown in the performance overlay during the recordings.
- Unreal Engine 4.27-era Mac build.
- Metal on the iPhone Apple GPU.
- A PS4 DualShock 4 controller was paired to the iPhone for the latest navigation attempt.

### Phase G — initial UI

Observed in the phase-G run:
- Launch succeeds through `devicectl` when supplied with the project path and `-basedir`.
- The IOKit adapter exposes the GPU descriptor structure Unreal expects, based on the actual iPhone GPU.
- Unreal passes the previously empty GPU-descriptor path.
- Targeted Metal hooks translate observed macOS `MTLStorageModeManaged` requests to iOS `Shared`.
- Metal library loading succeeds in the observed log.
- Stray displays its autosave warning and brightness-calibration UI.
- The overlay/log reports roughly 59–62 FPS during parts of this short run. This is not a benchmark.
- The process exits with status 0 after the app transitions to the background; this was not the earlier Metal validation crash.

### Follow-up — controller navigation and first scene-load attempt

In a later on-device recording:
- The user reports that a paired PS4 DualShock 4 controller successfully navigated beyond the brightness-calibration screen and through the UI.
- The recording shows a Stray menu with Resume, Settings and Quit, followed by a transition into a 3D rendered view.
- The 3D view is not correct: it is dominated by blue/washed-out surfaces and obvious rendering artifacts. The cat and a recognizable playable scene are not clearly visible, so this is **not yet proof of working gameplay**.
- The recording's performance overlay shows roughly 19–31 FPS during the captured attempt, around 3.37–3.42 GB of app memory, and approximately 123–184 MB of available memory. These are readings from a short overlay capture, not a controlled benchmark or memory-pressure diagnosis.
- The recording is portrait (1320 × 2868); it does not demonstrate that landscape/aspect-ratio issues have been fixed.

More detail: [gamepad and first scene-load notes](docs/GAMEPAD-AND-FIRST-LOAD.md) and the [latest rendering follow-up](docs/RENDERING-FOLLOW-UP.md).

## What remains

1. Diagnose direct SpringBoard icon launch (user reports immediate close); missing launch arguments are plausible, not confirmed.
2. Fix distorted presentation and validate both portrait/landscape sizing by tracing UIKit, `CAMetalLayer.drawableSize`, Unreal viewport dimensions and rotation.
3. Diagnose the corrupted 3D view: materials, shaders, texture streaming, render targets, lighting, camera/frustum and resource synchronization all remain candidates, not confirmed causes.
4. Prove actual gameplay: visible character/world, movement, camera and action input using the controller.
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
- `docs/GAMEPAD-AND-FIRST-LOAD.md` — DualShock 4 and first scene-load attempt
- `docs/RENDERING-FOLLOW-UP.md` — Runs 4/5 selective-rendering investigation
- `docs/KNOWN-ISSUES.md` — verification matrix
- `docs/REDDIT-DRAFT-EN.md` — English post draft
- `docs/REDDIT-DRAFT-ES.md` — Spanish post draft

## Upstream and attribution

This work builds on [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). See [UPSTREAM.md](UPSTREAM.md) and the upstream [MIT license](https://github.com/zorrobyte/macos-on-ios-public/blob/main/LICENSE). This repository does not relicense upstream code or claim ownership of it.

## Safety and distribution

Use only game copies you legitimately own and devices/accounts you control. No Stray executable, PAKs, extracted assets, certificates, provisioning profiles, device identifiers or signed app packages belong here. Do not distribute converted copies of the game.

See [PUBLISHING-SCOPE.md](PUBLISHING-SCOPE.md). This is an unofficial independent experiment, not affiliated with or endorsed by Annapurna Interactive, BlueTwelve Studio, Apple or the upstream maintainer.
