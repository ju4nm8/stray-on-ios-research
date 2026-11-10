# Stray on iOS — research log

> Can the original Apple-silicon macOS build of **Stray** run on an iPhone?
>
> I'm documenting a personal compatibility experiment based on [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). This is an engineering log, not a native iOS port, installer or claim that the game is complete or fully playable.

**Latest update — 9 November 2026:** I can launch Stray directly from its iOS Home Screen icon and reach an in-game 3D level on my iPhone 17 Pro Max. I also manually confirmed that gameplay actions respond: I can run, jump, meow and keep progressing even though the cat is not visible. Recent short test runs (Runs 16–17) produced median frame rates around 52–53 FPS over roughly 94 seconds, with nominal thermal state reported in the logs. These are encouraging short samples, not a sustained performance benchmark. The visual result is still far from complete: the cat, parts of the environment and some materials are missing or incorrectly rendered, and lighting/exposure remain problematic.

[En español](README.es.md) · [Technical timeline](docs/MILESTONES.md) · [Architecture](docs/ARCHITECTURE.md) · [Known issues](docs/KNOWN-ISSUES.md)

---

## What I'm trying to do

I'm testing whether the original ARM64 macOS build of Stray can run inside an iOS app container using the compatibility infrastructure and shims from the upstream project. The game executable remains the original macOS binary. My work has involved bundle conversion, macOS API compatibility, resource paths, Unreal platform detection, IOKit GPU discovery, Metal behavior, rendering and input.

This is **not** a native iOS port, a redistribution of Stray, a DRM bypass or proof that arbitrary Mac games can run on iOS. It is an unfinished compatibility experiment.

## Current state

### What I have verified

- Stray launches directly from its iOS Home Screen icon on my physical iPhone 17 Pro Max.
- The game reaches its menus and loads into a 3D level.
- I manually tested gameplay actions: running, jumping, meowing and continuing through the sequence all respond even though the cat's visual mesh is missing.
- Static parts of the environment render. Earlier captures show sections of a tunnel/courtyard with pipes, concrete structures, cables, vegetation, sky and atmospheric effects.
- Recent Runs 16 and 17 recorded median frame rates of approximately 52 and 53 FPS respectively over about 94 seconds. The logs report nominal thermal state during those samples. This does not establish sustained performance, frame pacing or stability over longer sessions.
- The original project PAK archives opened in the recent test logs. That confirms the archives were accessible to the process; it does not prove every asset was successfully loaded or rendered.
- The revised AppKit GPU-family shim was compiled, signed and installed before Run 4. Later runs progressed without the same UE4 texture-view fatal error in the supplied log excerpts. This is encouraging, but I have not established causality with a controlled A/B test.

### What is still broken or unknown

- **The cat is invisible.** Gameplay actions respond, but the character's visual mesh does not appear in the captures.
- A substantial amount of level geometry and other visual content is missing or incorrectly rendered.
- Materials and textures are incomplete, absent or displayed incorrectly in parts of the scene.
- Lighting and exposure are inconsistent; some areas are much too dark or otherwise look wrong.
- Skeletal/dynamic-mesh rendering is a major suspect, but I have not isolated a root cause.
- The landscape viewport and the relationship between UIKit bounds, `CAMetalLayer.drawableSize` and Unreal's viewport still need deliberate verification.
- Long-session stability, audio and background/foreground behavior have not been properly tested.
- The latest FPS results are short-run observations only. They should not be read as proof of a stable 50–60 FPS experience.

## Possible causes I'm investigating

These are hypotheses, not confirmed diagnoses:

- Unreal's skeletal-mesh scene-proxy creation or rendering path on this Metal implementation.
- GPU skinning and skin-cache behavior.
- Masked, subsurface or other material permutations that may behave differently on the iPhone GPU.
- Stencil and LOD dithering, Early Z/depth handling, and visibility/culling decisions.
- GFur or other dynamic geometry/plugin paths.
- Metal feature-family reporting or format/view compatibility.
- Resource streaming, texture formats, mip selection or asset-loading paths.
- Lighting, exposure, shadow and post-processing features that may not map cleanly to this runtime.
- Viewport/drawable sizing or orientation mismatches.

The cat mesh and related assets were found in the original game data during inspection, so a missing source asset is not currently the leading explanation. That still does not prove the game is loading and binding those assets correctly at runtime.

## Test setup

- MacBook Air M4, 16 GB unified memory.
- iPhone 17 Pro Max.
- Original Apple-silicon macOS build of Stray, based on Unreal Engine 4.
- Metal on the iPhone's Apple GPU.
- Compatibility layer: [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public).

I try to distinguish source changes, builds, installations, runtime configuration experiments and things I actually observed on the phone. Short logs, FPS overlays and successful PAK opens are not treated as proof of complete rendering or playability.

## What I could use help with

I'd appreciate technical input from people who know Unreal Engine's Metal RHI, skeletal mesh rendering, GPU skinning, material/shader permutations, Metal feature sets, resource streaming, or UIKit/CAMetalLayer/viewport sizing.

In particular, I'm looking for ways to narrow down why static environment geometry can render while the cat's skeletal mesh and parts of the scene do not. Suggestions for small, controlled tests or useful instrumentation would be especially helpful.

## Project notes

- [Technical timeline](docs/MILESTONES.md)
- [Rendering follow-up and test runs](docs/RENDERING-FOLLOW-UP.md)
- [Known issues and verification matrix](docs/KNOWN-ISSUES.md)
- [Metal compatibility notes](docs/METAL-COMPATIBILITY.md)
- [Architecture notes](docs/ARCHITECTURE.md)

## Upstream, attribution and distribution

This work builds on [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). See [UPSTREAM.md](UPSTREAM.md) and the upstream [MIT license](https://github.com/zorrobyte/macos-on-ios-public/blob/main/LICENSE). I do not claim authorship of the upstream compatibility framework.

I do not publish Stray's executable, PAK files, extracted assets, converted app bundles, signing material, provisioning profiles, device identifiers or private logs. This is an unofficial independent experiment, not affiliated with or endorsed by Annapurna Interactive, BlueTwelve Studio, Apple or the upstream maintainer.
