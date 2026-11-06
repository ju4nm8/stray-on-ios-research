# Stray on iOS — research log

> Can the original Apple-silicon macOS build of **Stray** run on an iPhone?
>
> I am documenting a personal compatibility experiment based on [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). This is an engineering log, not a native iOS port, installer or claim that the game is fully playable.

**Latest update — 6 November 2026:** I can open Stray directly from its iOS Home Screen icon and progress through the game. I have manually confirmed that the gameplay controls respond correctly: I can run, jump, meow and continue through the sequence even though the cat is not visible. Run 9 used a new renderer configuration and produced a short telemetry sample around 62 FPS, but the scene still has missing assets and substantial lighting/rendering defects. The main blocker is visual completeness, especially the invisible cat and other missing geometry—not input.

[En español](README.es.md) · [Technical timeline](docs/MILESTONES.md) · [Architecture](docs/ARCHITECTURE.md) · [Known issues](docs/KNOWN-ISSUES.md)

---

## What I am building

I am testing whether the original native ARM64 macOS build of Stray can run inside an iOS app container using the compatibility infrastructure and shims from the upstream project. The game executable remains the original macOS binary. My work has focused on bundle conversion, macOS API compatibility, resource paths, Unreal platform detection, IOKit GPU discovery, Metal behavior, rendering and input.

This is **not** a native iOS port, a redistribution of Stray, a DRM bypass or proof that arbitrary Mac games can run on iOS.

## Current state

### Confirmed

- I can launch Stray from its iOS Home Screen icon. I no longer consider direct icon launch a current blocker.
- The app has reached the Stray menus and loaded into a 3D level on the physical iPhone 17 Pro Max.
- In Run 9, I deployed `Engine_run9.ini` to the app data container and relaunched the existing app. Metal rendering remained active; a short log sample showed about 62 FPS, 1.43 GB app memory, 6.77 GB available memory and nominal thermal state. This is one brief sample, not a benchmark or evidence of sustained 60 FPS.
- I manually confirmed in-game control response: running, jumping, meowing and other actions work, and I can continue progressing through the game while the cat's visual mesh is missing.
- The Run 9 screenshot was captured with `devicectl`. The attempted macOS `screencapture` fallback failed because it could not create an image from the display.
- Run 6 captures show a recognizable tunnel environment with textured pipes, concrete structures, cables/conduits, vegetation, sky and atmospheric effects.
- The revised AppKit GPU-family shim was compiled, signed and installed before Run 4. Later runs progressed without the same UE4 texture-view fatal error in the supplied log excerpts. This is encouraging, although I have not established causality with a controlled A/B test.
- In Run 6, VGC polling logs recorded non-zero analog stick axes. This confirms axis values reached the shim's polling path, not that Unreal applied them to movement or camera control.

### Still unresolved

- The scene still has substantial lighting/exposure errors, dark or uneven areas and incomplete rendering of environmental objects.
- The cat remains invisible in the captured image even though its gameplay actions respond. Skeletal-mesh rendering remains unresolved.
- The latest investigation points toward the skeletal/dynamic-mesh path, with masked materials, stencil/LOD dithering, Early Z, skinning and GFur as candidates. None is a proven root cause.
- A significant portion of the level's visual content is still absent or rendered incorrectly; visual quality is improving between runs but is not yet acceptable.
- The controls are working in my manual gameplay test, but the cat's mesh and several other scene elements are still missing. The visual absence of the cat must not be confused with a failure of input or game logic.
- Run 6 telemetry samples ranged around 38–56 FPS, with about 2.8 GB app memory, 5.3–5.4 GB available memory and a `fair` thermal state. These are short-run samples, not a benchmark.
- Landscape captures exist, but I have not completed a deliberate verification of UIKit bounds, `CAMetalLayer.drawableSize`, Unreal viewport dimensions and rotation.
- Long-session stability, audio and background/foreground behavior still need testing.

## Test environment and method

- MacBook Air M4, 16 GB unified memory.
- iPhone 17 Pro Max.
- The overlay in earlier recordings showed iOS 27.3 beta; I treat that as the OS shown during those captures, not as a verified statement about every later run.
- Original Unreal Engine 4-era macOS build of Stray.
- Metal on the iPhone's Apple GPU.
- PS4 DualShock 4 paired during controller tests.

I distinguish between code changes, builds, installations, runtime configuration experiments and results actually observed on the phone. FPS overlays and short captures are not treated as benchmarks or proof of full playability.

## Technical history

- `docs/MILESTONES.md` records the conversion, Metal storage-mode adaptation, initial UI and scene-rendering experiments through Run 9.
- `docs/METAL-COMPATIBILITY.md` documents the Managed/Shared storage adaptation and the later GPU-family investigation.
- `docs/RENDERING-FOLLOW-UP.md` records Runs 4–9 and the renderer configuration experiments.
- `docs/DISPLAY-AND-INPUT.md` tracks viewport and controller work.
- `docs/KNOWN-ISSUES.md` is the current verification matrix.

## What I will test next

1. Fix the missing cat mesh and restore the remaining missing environmental geometry/materials.
2. Correct lighting, exposure, shadows and other rendering defects without regressing the geometry that already appears.
3. Preserve the working controls; only investigate input again if a reproducible regression appears.
4. Recheck landscape layout and compare UIKit, Metal drawable and Unreal viewport dimensions.
5. Test longer-session stability, frame pacing, audio and app lifecycle after visual completeness improves.

## Upstream, attribution and distribution

This work builds on [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). See [UPSTREAM.md](UPSTREAM.md) and the upstream [MIT license](https://github.com/zorrobyte/macos-on-ios-public/blob/main/LICENSE). I do not claim authorship of the upstream compatibility framework.

I do not publish Stray's executable, PAK files, extracted assets, converted app bundles, signing material, provisioning profiles, device identifiers or private logs. This is an unofficial independent experiment, not affiliated with or endorsed by Annapurna Interactive, BlueTwelve Studio, Apple or the upstream maintainer.