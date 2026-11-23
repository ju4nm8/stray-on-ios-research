# Project Status — Stray iOS Port Research

> **Current Baseline:** 2026-11-23  
> **Target Device:** iPhone 17 Pro Max (Apple Silicon A19 Pro GPU, iOS 27.x, 8 GB RAM)  
> **Development Host:** MacBook Air M4, 16 GB Unified Memory  
> **Original App:** Stray for macOS (ARM64, Unreal Engine 4 `Hk_project`, v1.5 / build 99)  
> **App Identifier:** `com.ju4nm8.strayios`  

---

## Executive Summary

> [!CAUTION]
> **HONEST STATUS:** **Stray has NOT been successfully ported to iOS yet. It is NOT fully playable.**
> 
> The project has successfully executed the original un-recompiled ARM64 macOS executable of **Stray** on physical iPhone 17 Pro Max hardware using dynamic library shims and platform header adaptation. The game initializes a Desktop Metal SM5 Dynamic RHI, streams 2.65 GB of cooked level assets, accepts virtual touch and DualShock 4 input, and renders 3D world geometry at **25–33 FPS**.
> 
> However, visual presentation remains severely broken: the cat protagonist renders only as a dark silhouette, procedural fur is absent, textures appear flat or low-resolution, dynamic shadows are missing, and the 3D menu background is black.

---

## 9-Stage Engineering Status Matrix

| Stage | Milestone | Status | Verified Hardware Evidence |
|---|---|---|---|
| **Stage 1** | **Process Stability & Launch** | **PASS** | Bundle installs via `devicectl` (Exit Code 0); runs under watchdog without early crash. |
| **Stage 2** | **Unreal Engine Initialization** | **PASS** | `FEngineLoop::AppInit` completes; 3,463 ICU files loaded via VFS redirect; PhysX 3.4 initialized. |
| **Stage 3** | **Metal & RHI Initialization** | **PASS** | `GDynamicRHI = 0x12298af00`, `GIsRHIInitialized = 1`, `GIsMetalInitialized = 1`, `SF_METAL_SM5` active. |
| **Stage 4** | **First Screen Rendering** | **PASS** | 16:9 aspect fit (`1536x864` drawable) presented to `CAMetalLayer` at 60 FPS in Slate UI. |
| **Stage 5** | **Scene Geometry & Character** | **IN PROGRESS** | 3D level geometry renders cleanly at 25–33 FPS. Cat mesh is rasterized (silhouette); shading incomplete. |
| **Stage 6** | **Materials, Textures & Lighting** | **IN PROGRESS** | **ACTIVE BLOCKER:** `MSM_SubsurfaceProfile` lacks screen-space SSS blur; VLM ambient lighting returns 0. |
| **Stage 7** | **Audio Pipeline Recovery** | **IN PROGRESS** | Audio thread active; Wwise soundbank streaming pending deep verification. |
| **Stage 8** | **Input Controls & Gameplay** | **IN PROGRESS** | Virtual on-screen gamepad and connected DualShock 4 controller fully operational. |
| **Stage 9** | **Performance & Thermals** | **IN PROGRESS** | 25–33 FPS sustained, 2.65 GB RAM, nominal thermals within 60s execution windows. |

---

## Verified Technical Milestones (Tests 31 to 41)

The following milestones have been validated through reproducible physical device test runs on iPhone 17 Pro Max:

### 1. GPU Discovery & Null Pointer Crash Resolution (Test 31)
- **Problem:** UE4 dereferenced null `IOAccelerator` properties in `0x10121a060` during `FMetalDynamicRHI` startup, causing immediate SIGSEGV `0x28`.
- **Resolution:** `libShim_IOKit.dylib` implements synthetic registry matching returning:
  `vendorId = 0x106b` (Apple Inc.), `model = "Apple A19 Pro GPU"`, `plugin = "AGXMetalG18P"`.
- **Verification:** Log confirmed 0 crashes; `FMetalDynamicRHI` detected the GPU and proceeded into feature set initialization.

### 2. PhysX & Metal SM5 Dynamic RHI Unification (Test 32)
- **Problem:** Dynamic loading of PhysX libraries failed due to path and case mismatches.
- **Resolution:** `libShim_libSystem.dylib` intercepted `dlopen` and redirected relative paths (`../../../Engine/Binaries/ThirdParty/PhysX3/Mac/`).
- **Verification:** Console log confirmed:
  ```text
  [UE4] LogInit: GDynamicRHI: 0x12298af00
  [UE4] LogInit: GIsRHIInitialized: 1
  [UE4] LogInit: GIsMetalInitialized: 1
  [UE4] LogInit: GMaxRHIFeatureLevel: 3 (SM5)
  ```

### 3. Metal Storage Mode Sanitization (Test 33)
- **Problem:** macOS Metal utilizes `MTLStorageModeManaged` (`1`), which is illegal on iOS unified memory devices.
- **Resolution:** `libShim_AppKit.dylib` interposes `MTLTextureDescriptor` to convert `MTLStorageModeManaged` to `MTLStorageModeShared` (`0`).
- **Verification:** 60 FPS presentation loop achieved in Slate UI menus without Metal validation panics.

### 4. 16:9 Viewport & Landscape Orientation (Test 34)
- **Implementation:** `libShim_AppKit` binds `FCocoaWindow` to a centered 16:9 `UIWindow` container:
  - Screen dimensions: $956 \times 440\text{ pt}$ (Safe insets: Top 0, Left 62, Bottom 20, Right 62).
  - Container frame: $768 \times 432\text{ pt}$.
  - Drawable resolution: $1536 \times 864\text{ px}$.
- **Verification:** Eliminates aspect-ratio distortion and letterboxes cleanly within device safe areas.

### 5. DualShock 4 Controller & Virtual Touch Overlay (Test 34–35)
- **Implementation:** Custom `ShimTouchOverlayView` provides on-screen analog sticks and action buttons. Intercepts Apple `GameController` notifications to detect physical gamepads.
- **Verification:** Connecting a DualShock 4 controller automatically sets `_controlsContainer.hidden = YES`, handing full control to the physical gamepad.

### 6. Texture View Format Compatibility (Test 35–36)
- **Problem:** UE4 requested incompatible depth/stencil texture views on compressed texture formats, triggering Metal validation assertions.
- **Resolution:** Interposed `-[MTLTexture newTextureViewWithPixelFormat:]` to remap depth (`260 -> 252`) and stencil (`260 -> 261`).
- **Verification:** 100% texture view instantiation success across all test frames.

### 7. In-Game 3D World Rendering (Test 37)
- **Evidence:** Stray executed the intro tunnel level (`Zone01_Intro`) under Metal SM5 at **25–33 FPS** on the Apple A19 Pro GPU.
- **Level Streaming:** Concurrent streaming from `pakchunk0_s1`, `pakchunk0_s2`, and `pakchunk0_s3` drove resident memory smoothly: $697\text{ MB} \rightarrow 1,322\text{ MB} \rightarrow 2,273\text{ MB} \rightarrow 2,650\text{ MB}$.
- **Exposure:** Fixed severe overexposure by resetting exposure bias to 0.0 EV and re-enabling HZB occlusion.

### 8. Binary Code Cave Probe & Bone Limit Refutation (Test 40)
- **Probe Hook:** Assembled an ARM64 probe in zero-filled binary cave `0x1005d03ec`, instrumenting `USkinnedMeshComponent::CreateSceneProxy` (`0x102fd67a0`).
- **Findings:**
  - Section bone count: **14 bones**.
  - Vertex factory bone limit: **256 bones**.
  - Proxy creation result: **Valid non-null `FSkeletalMeshSceneProxy` instantiated (`0x13a762c80`)**.
- **Conclusion:** Conclusively disproved that bone limit checks caused the missing cat protagonist.

### 9. Framebuffer Pixel Forensics & Silhouette Discovery (Test 41)
- **Evidence:** Analysis of native 2868x1320 capture (`test41_ingame.png`) at coordinates $[X: 1850..2200, Y: 700..1050]$ confirmed that **the cat mesh IS physically rasterized**:
  - The silhouette cleanly occludes background pipes and valve wheels.
  - Feline ears, arched spine, paws, and shoulder blades are distinctly outlined.
- **Root Cause Isolation:**
  1. Material `MI_CAT_Body_2sidedshading` uses `MSM_SubsurfaceProfile` (`/Game/Character/Cat/Material/SSS_profil_cat`). In UE4's deferred renderer, this relies on screen-space bilateral blur post-processing (`FPostProcessSubsurface`), which fails or outputs black on iOS Metal.
  2. Dynamic movable skeletal meshes in static-baked levels depend on Volumetric Lightmap (VLM) indirect diffuse sampling, which evaluates to 0.0 lumens in dark interior tunnels.

---

## Current Active Blockers (Technical Priorities)

### Blocker 1: Cat Protagonist Shading & Subsurface Profile
- **Status:** Cat renders as pitch-black silhouette.
- **Remediation Under Test:**
  - Inject `r.SubsurfaceScattering=0` in `Engine.ini` under `[SystemSettings]` to force UE4 to fall back from `MSM_SubsurfaceProfile` to standard Lambertian `MSM_DefaultLit`.
  - Add ambient fill light via `DefaultFeatureAutoExposureBias=1.6` or skylight intensity override.

### Blocker 2: GFur PRO Procedural Fur Compute Shaders
- **Status:** The GFur PRO plugin sets `bHideSkin = true` (`bit 8` of `USkinnedMeshComponent + 0x5fe`) and `bVisible = false` in `ABP_CatPawn_C__pf1235962618`.
- **Surgical Binary Patches Applied:**
  - `0x102fd67f0`: NOP `tbnz w9, #0x8, 0x102fd6840` (`bHideSkin` check).
  - `0x102fd6e44`: NOP `cbz w0, 0x102fd6f34` (`MeshObject` allocation bypass).
  - `0x1008f9134`: In nativized blueprint, change `mov w1, #0` to `mov w1, #1` in `SetVisibility`.

### Blocker 3: Main Menu 3D Background
- **Status:** Main menu title screen renders Slate/UMG widgets over a black void.
- **Investigation:** World rendering pass in menu level is suppressed or occluded before Slate viewport compositing.

### Blocker 4: Desktop Texture Compression & Mip Streaming
- **Status:** Textures appear muddy or unstreamed.
- **Remediation:** Enforce `r.TextureStreaming=1`, `r.Streaming.PoolSize=2048`, and `r.Streaming.FullyLoadUsedTextures=1` to resident-load desktop BC mips on unified memory.

---

## Artifact & Log References

- Sanitized Logs & Diagnostics: [community/diagnostics/](community/diagnostics/)
- Technical Reverse Engineering Breakdown: [community/REDDIT_TECHNICAL_HELP.md](community/REDDIT_TECHNICAL_HELP.md)
- Community Reddit Post: [community/REDDIT_POST.md](community/REDDIT_POST.md)
