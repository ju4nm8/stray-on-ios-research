# Project Status — Stray iOS Port Research

**Status date:** 2026-11-23  
**Target:** iPhone 17 Pro Max, iOS 27.3  
**Host:** MacBook Air M4, 16 GB unified memory  
**Original application:** Stray macOS ARM64, Unreal Engine 4  
**Bundle ID:** com.ju4nm8.strayios

## Executive summary

The adapted application now installs and launches on the physical iPhone. It displays UI and menus, and a DualShock 4 is recognized. This supersedes the older baseline that described an early process exit before any UI was displayed.

The project is **not a completed port and is not yet visually playable**. The Stray title/menu 3D scene (cat with white eyes, Stray logo, expected background) is not visibly rendered. Starting the game does not produce a visibly rendered 3D world. The app initially appears in portrait and the image is severely stretched when rotated to landscape.

The latest reported exit code 9 was caused by the user manually closing the app, not by a crash.

## Evidence status

| Observation | Status | What it proves |
|---|---|---|
| App installs and launches on iPhone 17 Pro Max | Verified by device test report | Adapted bundle can be installed and started |
| UI and menus appear | Observed on device | Some UI/presentation path is active |
| DualShock 4 recognized | Observed on device | Controller discovery is reached |
| Metal library loading | Observed in logs | Metal-related library loading occurs |
| Render encoder creation | Observed in logs | A render encoder is created |
| Drawable presentation and completed command buffers | Observed in logs | Commands are submitted/completed and drawables presented |
| Stray title/menu 3D assets | Not visibly rendered | No proof of successful scene rendering |
| Gameplay world | Not visibly rendered | No proof of successful gameplay rendering |
| Landscape layout | Broken | Orientation/aspect ratio requires correction |
| Audio | Not verified | No conclusion |
| Sustained 40–60 FPS | Not verified | Short HUD/log samples are not a benchmark |

Metal activity is not equivalent to correct 3D rendering. A completed command buffer can still present a black or incomplete frame.

## Current blockers

### 1. Orientation and aspect ratio

The app initially appears in portrait. Rotating to landscape results in a severely stretched image. Investigate supported interface orientations, scene/window/view geometry, Unreal viewport dimensions, CAMetalLayer drawable size, content scale, Metal viewport/scissor, and render-target sizing. Do not assume a single missing rotation callback is the cause without measurement.

### 2. 3D scene rendering

Neither the expected Stray title/menu scene nor the gameplay world is visibly rendered. Determine whether the failure is in level loading, active camera, viewport binding, scene draw submission, shader/pipeline creation, geometry buffers, material/texture binding, lighting/post-processing, or final presentation. Collect evidence that distinguishes these cases.

### 3. Controller and touch input

DualShock 4 recognition has been observed. Full gameplay input mapping is not yet verified. The desired touch layout is minimal and configurable: movement stick, camera drag area, jump, contextual interaction, and a small settings entry. Hide gameplay touch controls while a physical controller is connected and restore them when it disconnects.

### 4. Audio and stability

Audio has not been verified. Long-session performance, sustained frame rate, memory pressure, and thermal behavior have not been characterized.

## Verified earlier compatibility work

Earlier bring-up included Mach-O platform adaptation and iOS bundle deployment, ICU resource discovery redirection, filesystem case-sensitivity compatibility, hardware identification hooks, IOKit GPU discovery emulation, Metal-related shims, and runtime exit forensics. These do not prove that 3D rendering works. Verify implementation details against current source and latest device logs before changing code.

## Current priorities

1. Correct landscape orientation and establish accurate view/drawable/viewport dimensions.
2. Restore visible rendering of the Stray title/menu scene and gameplay world.
3. Implement minimal touch controls and controller-aware visibility.
4. Verify audio, performance, memory, and thermal stability.

See [COMMUNITY-REVIEW.md](COMMUNITY-REVIEW.md) for the current observed state, concrete areas where outside reviewers can help, and safe publishing boundaries.

## Evidence policy

Separate observed facts, log-derived facts, static analysis, and hypotheses. Do not mark a milestone complete without reproducible evidence from the physical device. Do not describe the game as playable until the 3D world and required input paths work in a real session.
