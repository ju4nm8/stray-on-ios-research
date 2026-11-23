# Sanitized Milestone Runtime Logs

This directory contains sanitized device console logs captured during key milestones of the compatibility research on physical hardware.

## Privacy & Safety Boundary

All logs in this directory have been audited and sanitized according to strict security standards:
- All device UDIDs and serial numbers replaced with `<TARGET_DEVICE_UDID>`.
- All developer email addresses and account IDs replaced with `<DEVELOPER_EMAIL>`.
- All Apple Team IDs and certificate identifiers replaced with `<APPLE_TEAM_ID>`.
- All local user file paths (`/Users/...`, `/Volumes/...`) replaced with standardized placeholders (`<WORKSPACE_ROOT>`, `<PROJECT_ROOT>`).
- No game assets, proprietary keys, or sensitive application data are included.

## Log Files Description

### 1. `test33_metal_rhi_60fps_sanitized.log`
- **Milestone**: Full Metal Dynamic RHI initialization and stable present loop.
- **Key Evidence**:
  - `SHIM Metal storage hooks installed`: Interception of `MTLTextureDescriptorInternal` and `MTLHeapDescriptorInternal`.
  - `SHIM Metal tex managed->shared (setStorageMode #1)`: Translation of `MTLStorageModeManaged (1)` to `MTLStorageModeShared (0)`.
  - `SHIM Metal newLibraryWithSource -> ok`: Runtime Metal shader compilation.
  - `SHIM STATS fps=60 cpu=88 mem=1298 avail=2078 threads=50`: Continuous presentation loop maintaining 59-61 FPS cadence over 60 seconds with 50 threads and 1.3 GB memory footprint.
  - **Important Technical Note**: A 60 FPS stats output indicates that the runloop and presentation encoder are executing smoothly; it does **not** prove visible 3D world rendering (see `CURRENT_BLOCKERS.md`).

### 2. `test31_iokit_gpu_descriptor_sanitized.log`
- **Milestone**: Synthetic IOKit GPU adapter verification.
- **Key Evidence**:
  - `SHIM IOKit: GPU descriptor initialized (model=Apple A19 Pro GPU, plugin=AGXMetalG18P, registryID=0x1000003a3, vendor=0x106b)`.
  - Eliminates the `FMetalDynamicRHI` SIGSEGV at offset `0x28` (`ldr w8, [x19, #0x28]`).

### 3. `test30_physx_case_hook_sanitized.log`
- **Milestone**: PhysX case-sensitivity bypass.
- **Key Evidence**:
  - `SHIM dlopen case-insensitive hook`: Intercepts `libAPEXFramework.dylib` and maps it to `libApexFramework.dylib`.
  - Enables all PhysX 3.4 physics modules to load without missing library aborts.

### 4. `test1_nsurl_case_fix_sanitized.log`
- **Milestone**: Filesystem case-sensitivity check bypass.
- **Key Evidence**:
  - Intercepts `NSURLVolumeSupportsCaseSensitiveNamesKey` returning `@NO`.
  - Bypasses the fatal abort: "Unreal Engine does not support running from case-sensitive file systems".
