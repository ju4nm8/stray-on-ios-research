# Stray on iOS — research log

> Can the original Apple-silicon macOS build of **Stray** run on an iPhone?
>
> I am documenting a personal compatibility experiment based on [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). This is an engineering log, not a native iOS port, installer or claim that the game is fully playable.

**Latest update — 6 November 2026:** I can open Stray directly from its iOS Home Screen icon. In the latest Antigravity session, the app was re-signed, installed and launched on the physical iPhone; Metal command buffers completed and screenshots showed a live 3D level. Runs 7–8 still did not clearly show the cat. The current blocker is skeletal-character rendering, not app launch or basic static-scene rendering.

[En español](README.es.md) · [Technical timeline](docs/MILESTONES.md) · [Architecture](docs/ARCHITECTURE.md) · [Known issues](docs/KNOWN-ISSUES.md)

---

## What I am building

I am testing whether the original native ARM64 macOS build of Stray can run inside an iOS app container using the compatibility infrastructure and shims from the upstream project. The game executable remains the original macOS binary. My work has focused on bundle conversion, macOS API compatibility, resource paths, Unreal platform detection, IOKit GPU discovery, Metal behavior, rendering and input.

This is **not** a native iOS port, a redistribution of Stray, a DRM bypass or proof that arbitrary Mac games can run on iOS.

## Current state

### Confirmed

- I can launch Stray from its iOS Home Screen icon. I no longer consider direct icon launch a current blocker.
- The app has reached the Stray menus and loaded into a 3D level on the physical iPhone 17 Pro Max.
- In the latest session, Metal render encoders and command buffers were active on-device; the Run 8 log sampled about 40 FPS, 3.0 GB app memory, 5.2 GB available memory and nominal thermal state. This is a short sample, not a benchmark.
- Run 7 showed a detailed courtyard/tunnel environment and a brief controller button-mask transition (`0x0001`); this does not prove a working in-game action.
- Run 6 captures show a recognizable tunnel environment with textured pipes, concrete structures, cables/conduits, vegetation, sky and atmospheric effects.
- The revised AppKit GPU-family shim was compiled, signed and installed before Run 4. Later runs progressed without the same UE4 texture-view fatal error in the supplied log excerpts. This is encouraging, although I have not established causality with a controlled A/B test.
- In Run 6, VGC polling logs recorded non-zero analog stick axes. This confirms axis values reached the shim's polling path, not that Unreal applied them to movement or camera control.

### Still unresolved

- The tunnel interior is much darker than the exterior.
- I have not confirmed the cat's skeletal mesh in the latest captures. The first Phase J1 screenshot was initially interpreted as showing the cat/backpack, but later captures and deeper review did not corroborate that interpretation; I therefore keep cat visibility unverified.
- The latest investigation points toward a failure specific to skeletal meshes (and possibly the attached GFur component) while static level geometry renders. GPU skinning, material/shading and dynamic scene-proxy behavior are still hypotheses, not a proven root cause.
- I have not yet demonstrated complete character movement, camera control and action inputs in a sustained gameplay session.
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

- `docs/MILESTONES.md` records the conversion, Metal storage-mode adaptation, initial UI, scene-rendering experiments and Run 6.
- `docs/METAL-COMPATIBILITY.md` documents the Managed/Shared storage adaptation and the later GPU-family investigation.
- `docs/RENDERING-FOLLOW-UP.md` records Runs 4–6 and the configuration changes.
- `docs/DISPLAY-AND-INPUT.md` tracks viewport and controller work.
- `docs/KNOWN-ISSUES.md` is the current verification matrix.

## What I will test next

1. Resolve skeletal-mesh rendering and make the cat clearly visible; validate any GFur fallback separately.
2. Improve tunnel lighting/exposure without regressing static geometry.
3. Verify DualShock 4 movement, camera and action bindings end-to-end in Unreal, not only from button-mask or axis logs.
4. Recheck landscape layout and compare UIKit, Metal drawable and Unreal viewport dimensions.
5. Run a longer session and record frame time, memory, thermal state, audio and app lifecycle behavior.

## Upstream, attribution and distribution

This work builds on [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). See [UPSTREAM.md](UPSTREAM.md) and the upstream [MIT license](https://github.com/zorrobyte/macos-on-ios-public/blob/main/LICENSE). I do not claim authorship of the upstream compatibility framework.

I do not publish Stray's executable, PAK files, extracted assets, converted app bundles, signing material, provisioning profiles, device identifiers or private logs. This is an unofficial independent experiment, not affiliated with or endorsed by Annapurna Interactive, BlueTwelve Studio, Apple or the upstream maintainer.