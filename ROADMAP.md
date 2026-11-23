# Stray iOS — Development Roadmap

This roadmap tracks the independent effort to run the original macOS ARM64 version of Stray (Unreal Engine 4) inside an iOS app on a physical iPhone using compatibility shims.

**Current state (2026-11-23):** the app launches, displays UI/menus, and recognizes a DualShock 4. The Stray title/menu 3D scene and gameplay world are not visibly rendered. Landscape orientation currently produces a stretched image. This is not a completed or playable port.

No stage is complete without reproducible evidence from the physical device.

## Stages

| Stage | Goal | Current status |
|---|---|---|
| 1 | App installation and process launch | Verified |
| 2 | Reach usable UI and controller discovery | Partially verified |
| 3 | Correct orientation, viewport, and drawable sizing | Blocked |
| 4 | Render a complete 3D title/menu scene | Blocked — cat, Stray logo, and background not visible |
| 5 | Render gameplay world, geometry, camera, and character | Blocked — world not visibly rendered |
| 6 | Materials, textures, lighting, and post-processing | Unresolved; root cause not isolated |
| 7 | Audio pipeline | Not verified |
| 8 | Gameplay input, minimal touch controls, and controller mapping | Partially observed; implementation/testing incomplete |
| 9 | Sustained performance, memory, and thermal stability | Not verified |

## Stage 1 — Installation and launch

The adapted app installs and launches on the physical iPhone 17 Pro Max. The latest reported exit code 9 was a manual user close, not a crash. Do not reuse old early-exit reports as the current state without checking their test date and build.

## Stage 2 — UI and controller discovery

UI/menu elements are visible and a DualShock 4 is recognized. Full button/axis input delivery to Unreal, controller reconnect/disconnect behavior, menu navigation, and gameplay actions still require verification.

## Stage 3 — Orientation and display geometry

Goal: start in landscape and maintain correct aspect ratio without stretching.

Investigate supported interface orientations, scene/window/view bounds, transition handling, Unreal viewport dimensions, CAMetalLayer drawable size, content scale, Metal viewport/scissor, and render-target sizes.

Passing criteria: app launches in landscape; image is not stretched, squashed, or incorrectly cropped; layout and render dimensions agree; both landscape orientations work reliably.

## Stage 4 — First complete 3D title/menu scene

Goal: visibly render the expected Stray title/menu scene, including the cat, Stray logo, and background.

Determine whether scene assets load, the world/camera are valid, draw calls are submitted, shaders/pipelines are valid, and the final render target contains the expected image. Passing requires visual confirmation on the physical device, not merely successful command-buffer completion.

## Stage 5 — Gameplay world and character

Goal: render the gameplay level, geometry, camera, and player character. Determine whether level loading completes, a valid camera is active, scene proxies and skeletal meshes submit draw calls, and geometry reaches the presented drawable.

## Stage 6 — Materials, textures, lighting, and post-processing

Goal: restore correct materials, texture streaming, lighting, exposure, tonemapping, and post-processing. Do not assume a black screen is a texture-only issue. First distinguish absent geometry/draw calls from shader, material, lighting, and final-composition failures.

## Stage 7 — Audio

Goal: verify audio session initialization, mixer output, and in-game audio. No current success claim.

## Stage 8 — Input and touch controls

Goal: complete DualShock 4 input mapping and a minimal configurable touch interface:
- Virtual movement stick.
- Camera drag area.
- Jump.
- Contextual interaction.
- Small settings entry.

Hide gameplay touch controls while a physical controller is connected. Restore them automatically after disconnect. Verify actual input delivery, not merely controller detection.

## Stage 9 — Performance and thermals

Measure sustained gameplay performance, memory use, thermal behavior, and stability only after visual rendering and controls work. Short FPS samples are not proof of sustained performance.

## Community participation

See [COMMUNITY-REVIEW.md](COMMUNITY-REVIEW.md) for specific review requests and publishing boundaries.
