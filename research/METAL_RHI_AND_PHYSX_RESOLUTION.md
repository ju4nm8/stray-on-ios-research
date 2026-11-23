# Technical Report: Resolution of Metal RHI and PhysX Initialization on iOS

**Status:** Verified on physical hardware (iPhone 17 Pro Max, Apple Silicon A19 Pro GPU, iOS 27.3).  
**Authors:** Compatibility Research Team.  
**Classification:** Engineering Resolution Summary.

---

## 1. Executive Summary

This report documents the resolution of three fatal blockers preventing Unreal Engine 4 (`Stray-Mac-Shipping`) from completing graphics engine initialization on iOS:

1. **The IOKit GPU Enumeration Crash (SIGSEGV `0x28` / `0x10121a060`):** Completely eliminated by a synthetic IOKit GPU adapter in `libShim_IOKit.dylib`.
2. **The PhysX Case-Sensitivity Blocker:** Resolved by a case-normalizing `dlopen` interposer in `libShim_libSystem.dylib`.
3. **The Metal Storage Mode Assertion Crash (`invalid storageMode (1)`):** Resolved by dynamic descriptor swizzling in `libShim_AppKit.dylib`.

With these three fixes in place, the application successfully initializes `FMetalDynamicRHI`, compiles Metal shaders at runtime, and enters a stable present loop maintaining a 60 FPS swap cadence with 50 concurrent threads and a 1.3 GB memory footprint.

---

## 2. Problem Analysis & Resolutions

### Phase 1: PhysX Case Normalization (`libShim_libSystem.dylib`)

- **Symptom:** The engine terminated during early physics setup because `libAPEXFramework.dylib` could not be located.
- **Root Cause:** In macOS, the filesystem is case-insensitive. In iOS, APFS is case-sensitive. The engine's compiled code calls `dlopen(".../libAPEXFramework.dylib")`, but the physical file on disk is named `libApexFramework.dylib`.
- **Implementation:** In `libSystem.m`, a `dlopen` interposer checks if the requested path matches known third-party library casing discrepancies and transparently corrects the path before delegating to the real system `dlopen`.
- **Result:** All 5 PhysX 3.4 modules (`libPxFoundation`, `libPhysX3Common`, `libPxPvdSDK`, `libPhysX3`, `libPhysX3Cooking`) and APEX load without error.

---

### Phase 2: Synthetic IOKit GPU Adapter (`libShim_IOKit.dylib`)

- **Symptom:** Immediate SIGSEGV crash during `FMetalDynamicRHI::FMetalDynamicRHI` at instruction `0x10121a060` (`ldr w8, [x19, #0x28]`).
- **Root Cause:** Unreal Engine's `FMacPlatformGPUManager` invokes `IOServiceGetMatchingServices(..., IOServiceMatching("IOAccelerator"), ...)` to populate an internal `GPUDescriptors` array. In the iOS application sandbox, access to kernel IOKit services is blocked, returning an empty iterator. Consequently, `GPUDescriptors` remains empty, and the engine attempts to read `VendorId` at offset `0x28` from a null pointer.
- **Implementation:** `libShim_IOKit.dylib` implements a synthetic accelerator service:
  - Intercepts `IOServiceMatching("IOAccelerator")` and `IOServiceGetMatchingServices`.
  - Queries `MTLCreateSystemDefaultDevice()` to retrieve the real device name (e.g., `Apple A19 Pro GPU`).
  - Synthesizes all 7 properties required by `FMacPlatformGPUManager`: `device_type`, `IOMatchCategory`, `IOClass`, `CFBundleIdentifier`, `vendor-id`, `MetalPluginName`, `IOGLBundleName`, `model`, plus 64-bit `registryID`.
  - Respects CoreFoundation memory management rules (CFRelease on input matching dictionary, +1 on created dictionaries).
- **Result:** `GPUDescriptors` is populated cleanly with hardware device properties. The null pointer dereference at `0x10121a060` is completely eliminated.

---

### Phase 3: Metal Storage Mode & Unified Memory Coherency (`libShim_AppKit.dylib`)

- **Symptom:** Fatal assertion failure in iOS Metal validation layer:
  ```text
  -[MTLTextureDescriptorInternal validateWithDevice:]: failed assertion
  'Texture Descriptor Validation: invalid storageMode (1).
  Must be one of MTLStorageModeShared(0) MTLStorageModeMemoryless(3) MTLStorageModePrivate(2)'
  ```
- **Root Cause:** In macOS Metal, `MTLStorageModeManaged (1)` is used for discrete GPUs. Apple Silicon iOS devices utilize Unified Memory Architecture (UMA), where `MTLStorageModeManaged` does not exist.
- **Implementation:**
  - `MTLTextureDescriptor` and `MTLHeapDescriptor` are class clusters whose concrete implementations are private (`MTLTextureDescriptorInternal`, `MTLHeapDescriptorInternal`).
  - The shim swizzles `setStorageMode:`, `setResourceOptions:`, and `validateWithDevice:` on both abstract and concrete classes.
  - When `storageMode == MTLStorageModeManaged (1)` is requested, the shim transparently rewrites it to `MTLStorageModeShared (0)` and updates `resourceOptions` accordingly.
  - In addition, macOS cache synchronization methods (`-[MTLBuffer didModifyRange:]`, `-[MTLBlitCommandEncoder synchronizeResource:]`, `-[MTLBlitCommandEncoder synchronizeTexture:slice:level:]`) are safely stubbed as no-ops.
- **Result:** All texture and heap descriptor validation checks pass. Shaders compile successfully via `newLibraryWithSource` and `newLibraryWithData`.

---

## 3. Verified Execution Metrics

The combined shims enabled continuous, uninterrupted execution on physical hardware:

```text
SHIM Metal storage hooks installed: texDesc=MTLTextureDescriptorInternal heapDesc=MTLHeapDescriptorInternal
SHIM Metal tex managed->shared (setStorageMode #1): origMode=1 finalMode=0 type=7 fmt=80 16x16x16 mips=1 usage=0x11
SHIM Metal newLibraryWithSource -> ok 
SHIM STATS fps=60 cpu=88 mem=1298 avail=2078 threads=50 controllers=0 thermal=nominal
SHIM STATS fps=61 cpu=88 mem=1298 avail=2078 threads=50 controllers=0 thermal=nominal
SHIM STATS fps=60 cpu=116 mem=1299 avail=2077 threads=50 controllers=0 thermal=fair
```

- **Runtime:** Maintained stable 60 FPS presentation loop cadence.
- **Threads:** 50 concurrent engine threads.
- **Memory Footprint:** 1,298 MB active (2,078 MB available).
- **Thermal Status:** Nominal to Fair.

---

## 4. Current Limitations & What Remains Open

While Metal RHI initialization is solved, **3D scene rendering is still not visible**:
- UI overlays and menu text render correctly.
- The 3D cat character model and game world geometry do not visibly appear on screen.
- See `documentation/CURRENT_BLOCKERS.md` and `documentation/CONTRIBUTION_CALL_FOR_HELP.md` for specific technical details and open questions for Unreal Engine and Metal specialists.
