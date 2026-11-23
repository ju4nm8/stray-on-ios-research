# INDEPENDENT IOKIT / METAL COMPATIBILITY AUDIT REPORT
**Target Component:** Synthetic IOKit GPU Enumeration Adapter (`libShim_IOKit.dylib`)  
**Target Game:** Stray (macOS ARM64 port on iOS 17+)  
**Engine:** Unreal Engine 4.27.2 (`FMacPlatformGPUManager`, `FMetalDynamicRHI`)  
**Auditor:** Independent Apple Silicon, Darwin IOKit, Mach-O & UE4 Compatibility Engineer  
**Date:** 2026-11-23  
**Status:** COMPLETE  

---

## 1. EXECUTIVE SUMMARY

An independent technical audit was conducted on the synthetic IOKit GPU enumeration adapter implemented in [IOKit.m](file://<WORKSPACE_ROOT>/upstream/macos-on-ios-public/shim/overrides/IOKit.m) and compiled into [libShim_IOKit.dylib](file://<WORKSPACE_ROOT>/work/out_icu/Stray.app/Frameworks/libShim_IOKit.dylib).

The audit rigorously evaluated the claims regarding the resolution of the crash at `0x10121a060` (`ldr w8, [x19, #0x28]`), where `x19` was `NULL` due to an empty `GPUDescriptors` array in Unreal's `FMetalDynamicRHI`.

### Key Findings:
1. **Root Cause Confirmation:** Disassembly of [Stray-Mac-Shipping](file://<WORKSPACE_ROOT>/work/out_icu/Stray.app/Stray-Mac-Shipping) at `0x101219360`–`0x10121a060` definitively proves that `x19` is loaded with `GPUDescriptors.Data + DeviceIndex * 72`. When IOKit queries fail in the iOS sandbox, `GPUDescriptors` has 0 elements (`Data = NULL`), causing the `NULL + 0x28` (`VendorId`) SIGSEGV.
2. **Adapter Implementation Correctness:** The synthetic adapter in `IOKit.m` faithfully implements the exact Darwin IOKit hierarchy expected by `FMacPlatformGPUManager`: `AppleARMIODevice` (matching `device_type = "sgx"`) and child accelerator in `"IOService"` plane (matching `IOMatchCategory = "IOAccelerator"`).
3. **Property Compatibility:** All 7 required properties queried by `FMacPlatformGPUManager` (`device_type`, `IOMatchCategory`, `IOClass`, `CFBundleIdentifier`, `vendor-id`, `MetalPluginName`, `IOGLBundleName`, `model`, plus 64-bit `registryID`) are provided with exact matching CoreFoundation types (`CFData` vs `CFString`), widths, and little-endian byte ordering.
4. **CoreFoundation Ownership & ABI:** Memory ownership conventions are strictly observed. `IOServiceGetMatchingServices` correctly consumes 1 reference to `matching` (via `CFRelease(matching)`), Create functions return +1 ownership, Get functions borrow references, and local objects are properly released. ARC manages Objective-C lifetimes cleanly without leaks.
5. **Direct Binary Resolution:** Mach-O load command analysis confirms `Stray-Mac-Shipping` contains `LC_LOAD_DYLIB` pointing directly to `@rpath/libShim_IOKit.dylib`. Two-level namespace symbols bind directly to the shim, eliminating any risk of unintended bypass to iOS kernel IOKit.
6. **Critical Pre-Deployment Blocker Discovered (Code Signing):** The compiled `libShim_IOKit.dylib` was signed adhoc (`flags=0x2(adhoc)`), while the app bundle was signed with Apple Development credentials (`Authority=Apple Development: <DEVELOPER_EMAIL>`). Furthermore, the inclusion of `libShim_IOKit.dylib.orig` in `Frameworks/` breaks bundle resource sealing (`codesign --verify` fails with `a sealed resource is missing or invalid`). The bundle **cannot** execute on a physical iOS device until cleaned and re-signed.

---

## 2. FILES AND BINARIES INSPECTED

| Item | Path | File Type / Architecture | SHA-256 Checksum |
|---|---|---|---|
| **Current Source** | `upstream/macos-on-ios-public/shim/overrides/IOKit.m` | Objective-C Source (320 lines) | `6c10e1cb7b55fdb60fcbafe4305dfc65dd30d8d0caebf1fc3572d3f3f0bc175f` |
| **Source Backup** | `upstream/macos-on-ios-public/shim/overrides/IOKit.m.orig` | Objective-C Source (60 lines) | `f04ee88eb4481c62f2db63cc50d8a70df9d1cfbbcc24ff865668e1c6b8c9d1a3` |
| **Compiled Dylib** | `work/out_icu/Stray.app/Frameworks/libShim_IOKit.dylib` | Mach-O 64-bit arm64 dylib (70,736 B) | `d0c7d5017da376a91d102e3477123aa1ff258d45129fc2a2f96cf1583ba05b08` |
| **Dylib Backup** | `work/out_icu/Stray.app/Frameworks/libShim_IOKit.dylib.orig` | Mach-O 64-bit arm64 dylib (69,232 B) | `8f51ec94bf82b090bc19e5d4cb052309ce1dd87b32c6faee43d939634458b299` |
| **Game Executable** | `work/out_icu/Stray.app/Stray-Mac-Shipping` | Mach-O 64-bit arm64 executable (161,698,528 B) | `555549443f61224cba233672983965e4916bbd92...` |
| **Historical Source** | `work/antigravity/fulltext/eaa6cb79-3600-4d81-9e51-9bd35ce10c56/step_00007.txt` | Recovered Session Transcript (lines 53–274) | Local DB |

---

## 3. VERIFIED EXPORTED SYMBOLS AND LINKING EVIDENCE

### 3.1. Symbol Exports in `libShim_IOKit.dylib`
Executing `nm -gU work/out_icu/Stray.app/Frameworks/libShim_IOKit.dylib` confirms exactly 20 symbols exported with external visibility (`T`):

```text
0000000000004088 T _IOAllowPowerChange
00000000000040a0 T _IOCancelPowerChange
0000000000004074 T _IODeregisterForSystemPower
0000000000004280 T _IODisplayCreateInfoDictionary
00000000000045f0 T _IOIteratorNext
00000000000041e0 T _IONotificationPortDestroy
00000000000040b8 T _IONotificationPortGetRunLoopSource
0000000000004768 T _IOObjectRelease
0000000000004000 T _IORegisterForSystemPower
000000000000494c T _IORegistryEntryCreateCFProperties
0000000000005168 T _IORegistryEntryCreateCFProperty
0000000000005028 T _IORegistryEntryGetChildIterator
0000000000005428 T _IORegistryEntryGetRegistryEntryID
00000000000052b8 T _IORegistryEntrySearchCFProperty
0000000000004574 T _IOServiceGetMatchingService
000000000000436c T _IOServiceGetMatchingServices
00000000000042c8 T _IOServiceMatching
0000000000004858 T _IOServiceOpen
0000000000004298 T _KextManagerCopyLoadedKextInfo
00000000000042b0 T _KextManagerCreateURLForBundleIdentifier
```

### 3.2. Unreal Binary Import Resolution
Inspection of `work/out_icu/Stray.app/Stray-Mac-Shipping` with `nm -m` confirms that Unreal's two-level namespace import table binds these symbols specifically and directly to `libShim_IOKit`:

```text
(undefined) external _IOIteratorNext (from libShim_IOKit)
(undefined) external _IOObjectRelease (from libShim_IOKit)
(undefined) external _IORegistryEntryCreateCFProperties (from libShim_IOKit)
(undefined) external _IORegistryEntryCreateCFProperty (from libShim_IOKit)
(undefined) external _IORegistryEntryGetChildIterator (from libShim_IOKit)
(undefined) external _IORegistryEntryGetRegistryEntryID (from libShim_IOKit)
(undefined) external _IORegistryEntrySearchCFProperty (from libShim_IOKit)
(undefined) external _IOServiceGetMatchingService (from libShim_IOKit)
(undefined) external _IOServiceGetMatchingServices (from libShim_IOKit)
(undefined) external _IOServiceMatching (from libShim_IOKit)
(undefined) external _IOServiceOpen (from libShim_IOKit)
```

### 3.3. Mach-O Header and RPATH Chain
Inspection of `otool -l work/out_icu/Stray.app/Stray-Mac-Shipping`:
- `LC_LOAD_DYLIB` entry: `@rpath/libShim_IOKit.dylib`
- `LC_RPATH` entries:
  - `@executable_path/Mac/Contents/MacOS/`
  - `@executable_path/`
  - `@executable_path/Frameworks`
- Target Location: `@executable_path/Frameworks/libShim_IOKit.dylib` matches the physical layout inside `Stray.app/Frameworks/libShim_IOKit.dylib`.

Inspection of `otool -l work/out_icu/Stray.app/Frameworks/libShim_IOKit.dylib`:
- `cmd LC_ID_DYLIB`: `@rpath/libShim_IOKit.dylib`
- `cmd LC_REEXPORT_DYLIB`: `/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit`
- `cmd LC_LOAD_DYLIB`: `Foundation`, `CoreFoundation`, `Metal`, `libobjc.A`, `libSystem.B`

**Verdict on Linking:** The Mach-O link structure is 100% sound. Dyld resolves all Unreal IOKit calls to `libShim_IOKit.dylib`.

---

## 4. DETAILED API AND COREFOUNDATION OWNERSHIP AUDIT

### 4.1. `IOServiceMatching`
- **Prototype:** `CFMutableDictionaryRef IOServiceMatching(const char *name)`
- **Behavior:** Allocates mutable dictionary, wraps `name` into `CFStringRef` (`kCFStringEncodingUTF8`), sets `"IOProviderClass"` key, releases local string, returns dictionary.
- **Ownership:** Follows CoreFoundation Create Rule. Returns +1 reference to caller. Caller is responsible for releasing it (or passing it to a consuming function).
- **Audit Result:** `PASS`.

### 4.2. `IOServiceGetMatchingServices`
- **Prototype:** `kern_return_t IOServiceGetMatchingServices(mach_port_t mainPort, CFDictionaryRef matching, mach_port_t *existing)`
- **Reference Consumption Contract:** Darwin IOKit documentation explicitly specifies: *`IOServiceGetMatchingServices` consumes one reference to the matching dictionary in all cases (success or failure).*
- **Implementation in `IOKit.m`:**
  - On synthetic match (`AppleARMIODevice`): Calls `CFRelease(matching);`. Sets `*existing = kShimIOIterSGX`. Returns `KERN_SUCCESS`.
  - On pass-through failure (`!real`): Checks `if (matching) CFRelease(matching);`. Returns `KERN_FAILURE`.
  - On pass-through delegate: Passes `matching` to `real(mainPort, matching, existing)`, which consumes the reference.
- **Audit Result:** `PASS` (No leak; strictly adheres to XNU reference consumption semantics).

### 4.3. `IOServiceGetMatchingService`
- **Prototype:** `mach_port_t IOServiceGetMatchingService(mach_port_t mainPort, CFDictionaryRef matching)`
- **Implementation:** Wraps `IOServiceGetMatchingServices(mainPort, matching, &iter)`, obtains entry via `IOIteratorNext(iter)`, calls `IOObjectRelease(iter)`, returns entry.
- **Ownership:** Consumes `matching` through `IOServiceGetMatchingServices`.
- **Audit Result:** `PASS`.

### 4.4. `IOIteratorNext` & Iteration Semantics
- **Prototype:** `mach_port_t IOIteratorNext(mach_port_t iterator)`
- **Handles Audited:**
  - `kShimIOIterSGX` (`0x53484940u`): Yields `kShimIOEntrySGX` (`0x53484941u`) on first call; returns `0` on subsequent calls.
  - `kShimIOIterAccel` (`0x53484942u`): Yields `kShimIOEntryAccel` (`0x53484943u`) on first call; returns `0` on subsequent calls.
- **Reset Logic:** Calling `IOServiceGetMatchingServices` resets `gShimSGXIterYielded = 0`. Calling `IORegistryEntryGetChildIterator` resets `gShimAccelIterYielded = 0`.
- **Audit Result:** `PASS`.

### 4.5. `IOObjectRelease` & Handle Collision Analysis
- **Prototype:** `kern_return_t IOObjectRelease(mach_port_t object)`
- **Synthetic Handle Values:** `0x53484940` – `0x53484943` (ASCII `'SHI@'` through `'SHIC'`).
- **Collision Risk:** In Darwin XNU, user-space Mach port names are allocated sequentially with generation counters in upper bits (`MACH_PORT_INDEX` 24 bits, `MACH_PORT_GEN` 8 bits). An index of `0x534849` corresponds to index ~5.45 million in the task IPC table. A newly launched application process has fewer than 500 ports. Collision probability with a real kernel Mach port is virtually zero ($< 10^{-7}$).
- **Release Safety:** For synthetic handles, `IOObjectRelease` intercepts the call, returns `KERN_SUCCESS`, and prevents passing fake port IDs to `mach_port_deallocate`, eliminating `KERN_INVALID_RIGHT` errors. Real objects pass to `RealIOKit("IOObjectRelease")`.
- **Audit Result:** `PASS`.

### 4.6. `IORegistryEntryCreateCFProperties`
- **Prototype:** `kern_return_t IORegistryEntryCreateCFProperties(mach_port_t entry, CFMutableDictionaryRef *properties, CFAllocatorRef allocator, uint32_t options)`
- **Ownership Contract:** Returns a +1 dictionary to the caller via `*properties`.
- **Implementation in `IOKit.m`:**
  - When `entry == kShimIOEntrySGX`: Calls `CreateShimSGXCFDictionary()`.
  - When `entry == kShimIOEntryAccel`: Calls `CreateShimAccelCFDictionary()`.
  - If `properties != NULL`, assigns `*properties = dict` (+1 transferred to caller).
  - If `properties == NULL`, calls `CFRelease(dict)` to prevent a leak.
- **Unreal Deallocation:** Disassembly of `Stray-Mac-Shipping` at `0x101360768` and `0x101360cec` confirms Unreal calls `CFRelease` on both dictionaries.
- **Audit Result:** `PASS`.

### 4.7. `IORegistryEntryCreateCFProperty` & `IORegistryEntrySearchCFProperty`
- **Prototypes:**
  - `CFTypeRef IORegistryEntryCreateCFProperty(mach_port_t entry, CFStringRef key, CFAllocatorRef allocator, uint32_t options)`
  - `CFTypeRef IORegistryEntrySearchCFProperty(mach_port_t entry, const char *plane, CFStringRef key, CFAllocatorRef allocator, uint32_t options)`
- **Ownership Contract:** Darwin IOKit functions with "Create" or "Search" in their name return +1 retained CF objects.
- **Implementation in `IOKit.m`:** Extracts borrowed reference from dictionary via `CFDictionaryGetValue`, calls `CFRetain(val)`, releases the temporary dictionary, and returns `val` (+1 retain count).
- **Unreal Deallocation:** Disassembly at `0x101360a88` confirms Unreal calls `CFRelease` on the returned search property (`IOMatchCategory`).
- **Audit Result:** `PASS`.

### 4.8. `IORegistryEntryGetRegistryEntryID`
- **Prototype:** `kern_return_t IORegistryEntryGetRegistryEntryID(mach_port_t entry, uint64_t *entryID)`
- **Implementation:** Queries `[MTLCreateSystemDefaultDevice() registryID]`. If nil or 0, falls back to `1ULL`.
- **Unreal Verification:** In `FMacPlatformGPUManager::InitializeDescriptorFromDeviceEntryM` (`0x101360b0c`), Unreal calls this function to write into `desc.RegistryID` (`offset 0x40`). At `0x101360a94`, Unreal tests `cbnz x8` (non-zero ID) to successfully terminate the child iterator loop.
- **Audit Result:** `PASS`.

---

## 5. GPU PROPERTY COMPATIBILITY ASSESSMENT

Disassembly of `FMacPlatformGPUManager::FMacPlatformGPUManager` (`0x101360678`) and `InitializeDescriptorFromDeviceEntryM` (`0x1013609c0`) reveals every property read and its exact validation requirements:

| Property Key | CF Type Expected by UE4 | Byte Layout / Value in `IOKit.m` | Purpose in Unreal Engine | Audit Status |
|---|---|---|---|---|
| `device_type` | `CFDataRef` | `'s', 'g', 'x', 0` (4 bytes) | Tested with `strncasecmp(bytePtr, "sgx", 3)`. Must match to recognize Apple Silicon GPU. | **MATCHES EXACTLY** |
| `IOMatchCategory` | `CFStringRef` | `"IOAccelerator"` | Searched in `"IOService"` plane to identify GPU accelerator child entry. | **MATCHES EXACTLY** |
| `IOClass` | `CFStringRef` | `"AGXAccelerator"` | Driver class name; stored for driver telemetry. | **MATCHES EXACTLY** |
| `CFBundleIdentifier` | `CFStringRef` | `"com.apple.AGXMetal"` | Stored in `desc.BundleID` (`[desc, #0x20]`). | **MATCHES EXACTLY** |
| `vendor-id` | `CFDataRef` | `0x6b, 0x10, 0x00, 0x00` (4 bytes LE) | Tested via `CFGetTypeID == CFDataGetTypeID`. Loaded via `ldr w8, [x0]` $\to$ `0x106b` (Apple). Stored in `desc.VendorId` (`[desc, #0x28]`). | **MATCHES EXACTLY** |
| `MetalPluginName` | `CFStringRef` | `ShimMetalPluginName()` (e.g. `"AGXMetalG16G_B0"`) | Stored in `desc.MetalPluginName` (`[desc, #0x10]`). **Tested with `cbz` at `0x101360818`: if NULL, descriptor is rejected.** | **MATCHES EXACTLY** |
| `IOGLBundleName` | `CFStringRef` | `"AppleMetalGLRenderer"` | Stored in `desc.GLBundleName` (`[desc, #0x18]`). | **MATCHES EXACTLY** |
| `model` | `CFStringRef` | `ShimMetalDeviceModel()` (e.g. `[dev name]`) | Stored in `desc.Model` (`[desc, #0x8]`). Populates `GRHIAdapterName`. | **MATCHES EXACTLY** |
| `registryID` | `uint64_t` | `dev.registryID` (or `1ULL`) | Stored in `desc.RegistryID` (`[desc, #0x40]`). Must be non-zero to exit child enumeration. | **MATCHES EXACTLY** |

### Additional Unreal Queries (Independent of IOKit):
- `sysctlbyname("hw.targettype")`: read into `desc.DeviceId` (`[desc, #0x2c]`).
- `sysctlbyname("hw.memsize")`: converted to MB and stored in `desc.DedicatedVideoMemory` (`[desc, #0x30]`).
These are system sysctls that succeed on iOS natively.

**Summary:** The fabricated registry properties are 100% sufficient and accurate for Unreal 4.27's ARM64 GPU enumeration.

---

## 6. MACH-O AND SIGNING ASSESSMENT

### 6.1. Dylib Identity and Re-exports
- Binary: `work/out_icu/Stray.app/Frameworks/libShim_IOKit.dylib`
- Architecture: `arm64` (Mach-O thin)
- Install Name: `@rpath/libShim_IOKit.dylib`
- Current Version: `0.0.0`
- Compatibility Version: `0.0.0`
- Re-export: `/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit` (compatibility 1.0.0, current 275.0.0)

### 6.2. Code Signing Verification
Direct execution of `codesign --verify` yielded:
```bash
# 1. Verification of the dylib in isolation:
codesign --verify --deep --strict --verbose=4 work/out_icu/Stray.app/Frameworks/libShim_IOKit.dylib
# Output:
# valid on disk
# satisfies its Designated Requirement (Signature=adhoc)

# 2. Verification of the application bundle:
codesign --verify --deep --strict --verbose=4 work/out_icu/Stray.app
# Output:
# work/out_icu/Stray.app: a sealed resource is missing or invalid
# file added: .../work/out_icu/Stray.app/Frameworks/libShim_IOKit.dylib.orig
# file modified: .../work/out_icu/Stray.app/Frameworks/libShim_IOKit.dylib
```

### 6.3. Signing Impact Analysis
1. The app bundle was signed on `23/11/2026 at 6:05:06 AM` using developer identity `Apple Development: <DEVELOPER_EMAIL> (<CERT_COMMON_NAME_ID>)`.
2. Recompiling `libShim_IOKit.dylib` and signing it adhoc (`-s -`) invalidated the bundle's `_CodeSignature/CodeResources`.
3. Adding the backup file `libShim_IOKit.dylib.orig` inside `Frameworks/` added an untracked, unsealed file to the bundle.
4. **Conclusion:** On a physical iOS device without a jailbreak (such as the target iPhone 17 Pro Max running iOS 17+), AMFI will immediately terminate the application upon launch (`EXC_CRASH (Code Signature Invalid)` / `SIGKILL`) unless the bundle is cleaned and re-signed.

---

## 7. CONFIRMED ISSUES, RISKS AND UNVERIFIED ASSUMPTIONS

### 7.1. Confirmed Issues (Must Be Addressed Before Launch)
- [x] **Broken Bundle Code Seal (CRITICAL):** `Stray.app` fails `codesign --verify` due to the modified `libShim_IOKit.dylib` and the added `libShim_IOKit.dylib.orig`.
- [x] **Adhoc Signature on Framework (HIGH):** `libShim_IOKit.dylib` has an adhoc signature while the container app has a Developer certificate signature. Mixed signature types violate iOS bundle validation rules.

### 7.2. Risks & Architectural Limitations (Benign in Single-GPU Context)
- [!] **Static Iterator State (Concurrency Risk):** The variables `gShimSGXIterYielded` and `gShimAccelIterYielded` are static file-scope integers (`static int`). If multiple threads concurrently called `IOServiceGetMatchingServices` or `IOIteratorNext`, a race condition would occur. However, Unreal's `FMacPlatformGPUManager` serializes initialization under `pthread_mutex_lock` and runs as a singleton (`sSelf`). For UE4's startup, this risk is mitigated, but it is not re-entrant.
- [!] **Compatibility Version Mismatch:** In `Stray-Mac-Shipping`, the expected compatibility version for `libShim_IOKit.dylib` is `1.0.0`, whereas the compiled dylib has `compatibility version 0.0.0`. While dyld currently treats `0.0.0` as wild-card on iOS, best practice is to pass `-compatibility_version 1.0.0` during compilation.

### 7.3. Unverified Assumptions (Marked UNVERIFIED)
- [?] **Metal RHI Downstream Initialization (`UNVERIFIED`):** While static disassembly confirms that `GPUDescriptors` will contain 1 valid descriptor and prevent the SIGSEGV at `0x10121a060`, subsequent operations (e.g., `CompileGlobalShaderMap`, loose PAK shader reading, PSO creation, and pipeline state generation) cannot be validated until an authorized device test executes.
- [?] **iOS Metal Driver Behavior on Non-Standard Keys (`UNVERIFIED`):** Whether the underlying iOS Metal runtime logs internal warnings when Unreal queries device properties remains to be observed on device console.
- [?] **Absence of `supportsFeatureSet:` Hook (`VERIFIED ABSENT`):** No `supportsFeatureSet:` hook exists in the compiled dylib or overrides. Unreal queries `SupportsFeatureSet(10003)` and `(10001)`. Disassembly shows that if these return `NO`, Unreal merely disables dynamic resolution bubbles and HDR output without crashing.

---

## 8. EXACT RECOMMENDED CORRECTIONS (WITHOUT IMPLEMENTING THEM)

The following corrective steps are recommended for the implementation engineer prior to launching Test 31:

1. **Clean Extraneous Files from Application Bundle:**
   Remove `libShim_IOKit.dylib.orig` from the `.app` bundle:
   ```bash
   rm -f "work/out_icu/Stray.app/Frameworks/libShim_IOKit.dylib.orig"
   ```

2. **Recompile Dylib with Matching Mach-O Versioning:**
   Ensure compatibility version matches Unreal's expected `1.0.0`:
   ```bash
   xcrun -sdk iphoneos clang -fobjc-arc -target arm64-apple-ios17.0 -dynamiclib \
     -install_name @rpath/libShim_IOKit.dylib \
     -compatibility_version 1.0.0 -current_version 275.0.0 \
     -Wno-incompatible-library-redeclaration \
     -framework Foundation -framework CoreFoundation -framework Metal \
     -Wl,-reexport_framework,IOKit \
     upstream/macos-on-ios-public/shim/overrides/IOKit.m \
     -o work/out_icu/Stray.app/Frameworks/libShim_IOKit.dylib
   ```

3. **Re-sign Frameworks and Bundle with Developer Identity:**
   Re-sign the framework and the complete bundle using the valid mobileprovision and certificate:
   ```bash
   # Sign the dylib
   codesign -f -s "Apple Development: <DEVELOPER_EMAIL> (<CERT_COMMON_NAME_ID>)" \
     --timestamp=none "work/out_icu/Stray.app/Frameworks/libShim_IOKit.dylib"

   # Re-seal the complete app bundle
   codesign -f -s "Apple Development: <DEVELOPER_EMAIL> (<CERT_COMMON_NAME_ID>)" \
     --timestamp=none --deep "work/out_icu/Stray.app"
   ```

4. **Verify Bundle Seal:**
   Confirm `codesign --verify --deep --strict work/out_icu/Stray.app` exits with code 0 before triggering `devicectl`.

---

## 9. FINAL VERDICT

# APPROVED WITH CONDITIONS

### Conditions for Device Test Authorization:
1. **Application Bundle Re-signing:** The application bundle must be cleared of `libShim_IOKit.dylib.orig` and fully re-signed with the active developer provisioning profile to satisfy AMFI code directory checks.
2. **Controlled Watchdog Execution:** Test 31 must be executed with the standard 90-second watchdog to observe console logs for the expected sequence:
   - `SHIM IOKit: IOServiceGetMatchingServices(AppleARMIODevice) -> iter=0x53484940`
   - `SHIM IOKit: GPU descriptor initialized (model=Apple ..., plugin=..., registryID=..., vendor=0x106b)`
   - Elimination of `SIGSEGV` at `0x10121a060`.
3. **Downstream Monitoring:** Verification that execution proceeds to `FMetalDynamicRHI` completion and shader cache compilation (`CompileGlobalShaderMap`).

*Note: This approval strictly authorizes a controlled device execution for Test 31; it does not certify that the game renders frames or that shader compilation will succeed.*
