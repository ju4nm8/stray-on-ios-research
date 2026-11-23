# System Architecture & Technical Design

This document details the architecture of the Stray on iOS compatibility research layer.

## 1. System Overview

The objective of this research is running native macOS Apple Silicon binaries (`arm64`) on physical iOS devices without source code access. Because macOS and iOS share the XNU Darwin kernel, the Mach-O binary format, and ARM64 instruction execution, application logic runs natively on the device CPU without CPU emulation or JIT compilation.

However, desktop games rely on macOS-specific subsystem frameworks (AppKit, IOKit, Carbon, OpenGL, discrete Metal conventions) and desktop filesystem conventions. The compatibility layer bridges these differences using binary rewriting, Mach-O load command redirection, dynamic Objective-C swizzling, and POSIX libc interposition.

```
+---------------------------------------------------------------+
|                      iOS Physical Device                      |
|                  (A19 Pro / iOS 17+ Sandbox)                  |
+---------------------------------------------------------------+
                               |
                               v
+---------------------------------------------------------------+
|                       Host Environment                        |
|   • Container Filesystem: /var/mobile/Containers/Data/...     |
|   • Sandbox Entitlements: get-task-allow, memory limits       |
|   • iOS Native Frameworks: UIKit, Metal (UMA), QuartzCore     |
+---------------------------------------------------------------+
                               ^
                               |
+---------------------------------------------------------------+
|                   Compatibility Shim Layer                    |
|  • libShim_AppKit.dylib: UIKit event loop, display link, UE4  |
|    command-line injection, Metal storage mode swizzling       |
|  • libShim_IOKit.dylib: Synthetic GPU IORegistry adapter      |
|  • libShim_libSystem.dylib: Case-normalization dlopen         |
|    interposer, path redirection, working directory override   |
+---------------------------------------------------------------+
                               ^
                               | (LC_LOAD_DYLIB)
+---------------------------------------------------------------+
|                    Target Mach-O Executable                   |
|                      `Stray-Mac-Shipping`                     |
|           • Original arm64 machine instructions               |
|           • Unreal Engine 4.27 RHI & Game Framework           |
|           • PhysX 3.4 physics engine                          |
+---------------------------------------------------------------+
```

## 2. Core Architectural Components

### 2.1 Mach-O Binary Conversion & Dependency Rebinding

During the conversion process (`scripts/convert_app.py`):
1. The target executable is inspected with `otool -l` and `vtool`.
2. `LC_BUILD_VERSION` is adapted to specify the iOS platform target.
3. Every `LC_LOAD_DYLIB` command pointing to missing desktop frameworks is rewritten to load a corresponding compatibility shim:
   - `/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit` -> `@rpath/libShim_AppKit.dylib`
   - `/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit` -> `@rpath/libShim_IOKit.dylib`
   - `/System/Library/Frameworks/Carbon.framework/...` -> `@rpath/libShim_Carbon.dylib`
4. The executable and all nested dylibs are resigned using a valid iOS provisioning profile and development identity.

### 2.2 Synthetic IOKit GPU Subsystem

Unreal Engine's macOS platform manager (`FMacPlatformGPUManager`) queries IOKit to detect the primary graphics accelerator:
- On macOS, `IOServiceGetMatchingServices` with `IOMatchCategory = "IOAccelerator"` returns kernel descriptors for Apple Silicon GPUs (e.g., `AGXAccelerator`).
- On iOS, sandbox boundaries deny application processes access to `IOAccelerator` services.
- `libShim_IOKit.dylib` intercepts `IOServiceMatching` and `IOServiceGetMatchingServices`. It instantiates `MTLCreateSystemDefaultDevice()` and constructs a synthetic CFDictionary with exact keys:
  - `device_type`: `CFData` containing `"display"`.
  - `model`: `CFData` containing the GPU name (e.g., `"Apple A19 Pro GPU"`).
  - `vendor-id`: `CFData` containing Apple's vendor ID (`0x106b`).
  - `IOMatchCategory`: `CFString` (`"IOAccelerator"`).
  - `IOClass`: `CFString` (`"AGXAccelerator"`).
  - `MetalPluginName`: `CFString` (`"AGXMetalG18P"`).
  - `IOGLBundleName`: `CFString` (`"AppleMetalGL"`).
  - `registryID`: 64-bit integer identifier.
- This prevents `FMetalDynamicRHI` from encountering an empty GPU list and crashing at offset `0x28`.

### 2.3 Metal Architecture Adaptation (Discrete vs Unified Memory)

Desktop Unreal Engine assumes a discrete GPU with dedicated VRAM, requesting:
1. `MTLStorageModeManaged (1)`: Invalid on iOS. The shim swizzles `setStorageMode:` and `setResourceOptions:` on `MTLTextureDescriptorInternal` and `MTLHeapDescriptorInternal`, forcing `MTLStorageModeShared (0)`.
2. Explicit cache flushing: `-didModifyRange:` and `-synchronizeResource:` are no-opped because CPU and GPU share the same physical memory space on Apple Silicon iOS devices.
3. Desktop Texture Formats: In `AppKit_RuntimeHooks.m`, `supportsFamily:` is hooked to return `YES` for `MTLGPUFamilyMac1/Mac2` and `NO` for `MTLGPUFamilyApple1..3`, signaling UE4 to use BC desktop compression rather than failing mobile texture queries.

### 2.4 Filesystem Virtualization & Path Translation

1. **Working Directory (`SHIMWorkingDirectory`)**:
   Unreal Engine on desktop resolves asset paths relative to `Contents/UE4/Hk_project/Binaries/Mac`. iOS applications launch with `cwd` set to the bundle root. The shim's `chdir()` hook transparently redirects bundle root cwd requests to the nested binary directory.
2. **Case Normalization (`dlopen` Interposer)**:
   PhysX dylibs are named with specific casing (`libApexFramework.dylib`). Because iOS APFS is case-sensitive, case-divergent `dlopen` requests fail. `libSystem.m` normalizes library names before dynamic linking.
3. **ICU Data Redirection (`SHIMPathRedirects`)**:
   Unreal 4.27 requires internationalization data at `../../../Engine/Content/Internationalization/icudt64l`. This tree is extracted from `pakchunk0-MacNoEditor.pak` and placed in the app container's `Documents/stray/StrayICU`. The shim redirects `open()` and `access()` calls to this folder.

### 2.5 Unreal Engine Runtime Injection

Before engine initialization, the shim executes `ShimSyncUnrealGSavedCommandLine`:
- Locates `GSavedCommandLine` in the engine image.
- Uses `FMemory::Realloc` at known binary offsets to safely allocate and inject command-line flags:
  `-SaveToUserDir -ResX=1536 -ResY=864 -sm5 -metalsm5 -metal`.
- Injects a custom `FOutputDevice` to capture internal engine logs to `stderr` and the iOS unified console.
