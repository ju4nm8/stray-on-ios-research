# Community Technical Review — Current Device State

**Status date:** 2026-11-23  
**Project:** Stray macOS ARM64 compatibility experiment on iPhone  
**Target:** iPhone 17 Pro Max, iOS 27.3  
**Host:** MacBook Air M4, 16 GB unified memory  
**Bundle ID:** `com.ju4nm8.strayios`

## What is verified on the device

- The adapted application installs and launches on the physical iPhone.
- The application displays parts of its UI and menus.
- A DualShock 4 can be connected and is recognized by the application.
- Metal-related activity has been observed in logs, including library loading, render-encoder creation, drawable presentation, and completed command buffers.
- The latest reported `exit code 9` was caused by the user manually closing the application. It was **not** a crash.

These observations prove that the application gets substantially further than the earlier early-termination baseline. They do **not** prove that Stray's 3D scenes render correctly.

## Current visible problems

1. **Orientation / aspect ratio:** the application initially appears in portrait. Rotating to landscape produces a severely stretched image.
2. **3D scene rendering:** the Stray title/menu scene does not visibly render its cat-with-white-eyes, Stray logo, or expected background. The screen is black apart from UI/menu elements.
3. **Gameplay rendering:** after selecting Start, the 3D world is not visibly rendered. Do not assume this is only a texture or lighting issue; the root cause has not yet been isolated.
4. **Touch controls:** a minimal touch-control layout is planned but is not yet considered complete. Desired behavior: virtual movement stick, camera gesture area, jump, contextual interaction, and a small settings entry. Hide gameplay touch controls while a physical controller is connected; restore them when it disconnects.

## Important diagnostic distinction

A visible UI, Metal drawable presentation, or completed command buffer does not by itself prove that Unreal's 3D scene geometry, materials, post-processing, or final composited frame are correct.

Please help identify which stage is failing:

- Unreal world / level loading
- active camera and viewport setup
- scene render submission / draw calls
- shader or pipeline-state creation
- vertex/index buffers and mesh rendering
- texture/material binding
- lighting, exposure, tonemapping, and post-processing
- Metal drawable sizing, orientation, and presentation

Please distinguish measured evidence from hypotheses. Include exact log excerpts, symbol names, source references, and reproducible test conditions.

## What would be most useful from reviewers

- Review of the AppKit-to-UIKit window/view bridge and orientation handling.
- Review of `CAMetalLayer.drawableSize`, view bounds, content scale, viewport, and render-target dimensions.
- Unreal Engine 4 Metal RHI debugging expertise, especially macOS-built UE4 binaries running against iOS Metal.
- Techniques to establish whether scene draw calls are submitted and whether the expected render targets contain non-black pixels.
- Review of GPU/IOKit compatibility shims and any assumptions about macOS GPU properties on iOS.
- GameController / DualShock 4 input mapping advice that does not interfere with Unreal's existing input path.

## Scope and reproducibility

This is an independent compatibility research project, not an official iOS port. The project does not distribute Stray or any game content. Reviewers must own a legitimate copy of the game and reproduce experiments with their own files.

We can share original research code, sanitized logs, configuration snippets, disassembly notes, and minimal test harnesses after checking provenance and removing private paths, identifiers, signing material, and third-party content.

## Do not upload or request

- `.app` bundles, the Stray executable, PAK/UCAS/UTOC archives, cooked assets, textures, models, audio, or extracted game resources.
- Apple certificates, provisioning profiles, private keys, device identifiers, personal paths, tokens, or credentials.
- Third-party source code without checking its license and preserving required notices.

## Current engineering priority

1. Fix landscape orientation and correct drawable/viewport dimensions.
2. Diagnose and restore visible 3D rendering in the title/menu scene and gameplay.
3. Implement and test minimal touch controls and automatic controller-aware visibility.
4. Only then evaluate sustained performance and thermal behavior.

**Nothing here claims that the port is complete or that the game is currently playable.**
