# Compatibility Shims Architecture & Guide

This directory contains the core compatibility shims that enable the native macOS ARM64 Unreal Engine 4 binary (`Stray-Mac-Shipping`) to execute on physical iOS devices.

## Architectural Overview

macOS and iOS share the XNU kernel and Darwin foundation, but diverge significantly in userland frameworks (AppKit vs UIKit), graphics APIs (discrete vs unified memory Metal expectations), and system security restrictions (sandbox isolation of IOKit).

The shims intercept and bridge these differences:

```
+-----------------------------------------------------------+
|                   Stray-Mac-Shipping                      |
|                  (Unreal Engine 4.27)                     |
+-----------------------------------------------------------+
         |                       |                     |
         v                       v                     v
+------------------+   +-------------------+   +------------------+
|   libShim_AppKit |   |   libShim_IOKit   |   | libShim_libSystem|
|------------------|   |-------------------|   |------------------|
| • UIKit Main Loop|   | • Synthetic GPU   |   | • dlopen Case-   |
| • GSavedCmdLine  |   |   IORegistry      |   |   Insensitive    |
| • StorageMode    |   | • Device Matching |   |   Interposer     |
|   Managed->Shared|   | • Property Query  |   | • Path Redirect  |
| • GPU Family     |   |   Emulation       |   | • Case-sensitive |
|   Spoofing       |   |                   |   |   Bypass         |
+------------------+   +-------------------+   +------------------+
         |                       |                     |
         +-----------------------+---------------------+
                                 |
                                 v
                 iOS 17+ Native Runtime & Metal
```

## Source Files Description

### 1. `IOKit.m` (Synthetic GPU IORegistry Adapter)
- **Problem**: In the iOS application sandbox, kernel IOKit service matching (`IOServiceGetMatchingServices(AppleARMIODevice)`) is restricted. Unreal Engine's `FMacPlatformGPUManager` expects macOS IORegistry entries to enumerate GPUs. When the registry array is empty, `FMetalDynamicRHI::FMetalDynamicRHI` performs an unchecked dereference of a null pointer at offset `0x28` (`ldr w8, [x19, #0x28]`), resulting in SIGSEGV crash `0x10121a060`.
- **Solution**: Implements a synthetic IOKit accelerator service. Queries `MTLCreateSystemDefaultDevice()` at runtime and dynamically synthesizes the 7 required properties (`device_type`, `IOMatchCategory`, `IOClass`, `CFBundleIdentifier`, `vendor-id`, `MetalPluginName`, `IOGLBundleName`, `model`, plus 64-bit `registryID`).
- **Result**: Eliminates the `0x28` SIGSEGV crash and allows RHI initialization to complete cleanly.

### 2. `AppKit_RuntimeHooks.m` (Metal Compatibility & Memory Coherence)
- **Problem 1 (Storage Mode)**: macOS Metal supports `MTLStorageModeManaged (1)` for discrete GPUs with separate VRAM. iOS devices have Unified Memory Architecture (UMA) and reject `storageMode = 1` with a validation assertion crash: `invalid storageMode (1). Must be one of MTLStorageModeShared(0) MTLStorageModeMemoryless(3) MTLStorageModePrivate(2)`.
- **Solution 1**: Swizzles `setStorageMode:`, `setResourceOptions:`, and `validateWithDevice:` on both abstract classes and concrete private classes (`MTLTextureDescriptorInternal`, `MTLHeapDescriptorInternal`). Transparently translates `Managed (1)` into `Shared (0)`.
- **Problem 2 (Cache Synchronization)**: Code written for discrete GPUs invokes `-didModifyRange:` and `-synchronizeResource:`. On UMA these methods are invalid or unnecessary.
- **Solution 2**: Implements no-ops for `-[MTLBuffer didModifyRange:]`, `-[MTLBlitCommandEncoder synchronizeResource:]`, and `-[MTLBlitCommandEncoder synchronizeTexture:slice:level:]`.
- **Problem 3 (Shader & Texture Decoding)**: On mobile Apple GPUs, Unreal Engine attempts to decode ASTC textures and mobile shaders.
- **Solution 3**: Intercepts `supportsFamily:` to return `YES` for `MTLGPUFamilyMac1` and `MTLGPUFamilyMac2`, and `NO` for `MTLGPUFamilyApple1..3`, ensuring UE4 uses standard desktop BC texture pipelines.

### 3. `AppKit.m` (Windowing, Event Loop & Engine Boot Injection)
- **`ShimUIKitFiberMain`**: Wraps the engine execution thread inside a UIKit application fiber, feeding `UIApplicationMain` and managing the display link.
- **`ShimSyncUnrealGSavedCommandLine`**: Unreal Engine initializes `GSavedCommandLine` very early. The shim uses `ShimUnrealMalloc` (`FMemory::Realloc` at address `0x1012b9928`) to safely inject project paths, rendering flags (`-metalsm5 -SaveToUserDir`), and resolution parameters before the engine initializes RHI.
- **`ShimOutputDevice`**: Injects an in-memory `FOutputDevice` hook directly into Unreal's logging system, allowing internal engine logs (`LogInit`, `LogShaders`, `LogRHI`) to be captured to the iOS system console even when filesystem log writing fails.

### 4. `libSystem.m` (Path Normalization & Filesystem Emulation)
- **Case-Insensitive `dlopen` Interposer**: macOS filesystems are traditionally case-insensitive (HFS+ / APFS case-insensitive), whereas iOS APFS is strictly case-sensitive. Unreal Engine's PhysX loader requests `libAPEXFramework.dylib`, while the dylib on disk is named `libApexFramework.dylib`. The shim intercepts `dlopen` and resolves case mismatches.
- **Path Redirection (`AppParentRedirect` & `WorkingDirOverride`)**: Redirects relative directory queries (`../../../Engine/...`) and sandbox-escaping paths to the application container's `Documents` folder.
- **`NSURLVolumeSupportsCaseSensitiveNamesKey` Interception**: Hooks `getResourceValue:forKey:error:` to return `@NO` for case-sensitivity checks, preventing UE4 from exiting with "Unreal Engine does not support running from case-sensitive file systems".

### 5. `Metal.m` & `CoreGraphics.m`
- Provide stubs and shims for macOS-specific CoreGraphics and Metal symbols absent from the iOS SDK.

## Provenance and License

All shims in this directory are licensed under the MIT License.
Based on the upstream architecture from [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public) (Copyright (c) 2026 Ross Fisher), extended with custom Unreal Engine 4 and Metal fixes by Stray on iOS Research Contributors.
