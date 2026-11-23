# Project Status — Stray iOS Port Research

> **Current Baseline:** 2026-11-23  
> **Target Device:** iPhone 17 Pro Max (Apple Silicon, iOS 27.3)  
> **Development Host:** MacBook Air M4, 16 GB Unified Memory  
> **Original App:** Stray for macOS (ARM64, Unreal Engine 4 `Hk_project`, v1.5 / build 99)  
> **App Identifier:** `com.ju4nm8.strayios`  

---

## Executive Summary

> *Stray iOS is entering a new development cycle. The project is establishing a clean technical baseline and rebuilding its public roadmap around the current implementation goals.*

The goal of this project is to run the original ARM64 macOS release of **Stray** on a physical iPhone 17 Pro Max using the compatibility layer derived from [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public). 

All reported milestones are backed by reproducible physical device logs captured under an automated host watchdog. Previous exploratory claims regarding in-game 3D rendering or character movement have been retired to `archive/previous-development/` in order to maintain absolute engineering rigor.

---

## Stage Status Matrix

| Stage | Milestone | Status | Verified Evidence |
|---|---|---|---|
| **Stage 1** | **Process Stability & Launch** | **BLOCKED** | Bundle installs and starts; terminates after ~3s (`_Exit(1)`). |
| **Stage 2** | **Unreal Engine Initialization** | **IN PROGRESS** | Blocked inside `FEngineLoop::AppInit` / `PreInitPreStartupScreen`. |
| **Stage 3** | **Metal & RHI Initialization** | **BLOCKED** | `GDynamicRHI == 0x0`, `GIsMetalInitialized == 0` at termination. |
| **Stage 4** | **First Screen Rendering** | **NOT STARTED** | No frame presentation on display yet. |
| **Stage 5** | **Scene Geometry & Character** | **NOT STARTED** | Requires working RHI and viewport presentation. |
| **Stage 6** | **Materials, Textures & Lighting** | **NOT STARTED** | — |
| **Stage 7** | **Audio Pipeline Recovery** | **NOT STARTED** | — |
| **Stage 8** | **Input Controls & Gameplay** | **NOT STARTED** | — |
| **Stage 9** | **Performance & Thermals** | **NOT STARTED** | — |

---

## Verified Technical Milestones (Passes)

The following components have been implemented, tested, and verified on the physical iPhone 17 Pro Max:

1. **Bundle Conversion & Codesigning:**
   - Mach-O platform headers converted to iOS platform load commands (`minos 17.0`, `sdk 27.1`) via `vtool`.
   - Dynamic library load paths (RPATHs) rewritten to reference internal framework shims.
   - Code signed with Apple Developer Personal Team profile and deployed via `devicectl` (Exit Code 0).

2. **ICU Internationalization Discovery:**
   - **Previous Blocker:** Unreal Engine crashed with fatal error `ICU data directory was not discovered` due to missing directory structure on disk.
   - **Resolution:** Extracted 3,463 ICU resource files (22 MB) from `pakchunk0-MacNoEditor.pak` to the app container path `Documents/stray/StrayICU/icudt64l`.
   - **Verification:** Configured shim redirect `Internationalization=Documents/stray/StrayICU`. Log verification confirmed **0** occurrences of the fatal error.

3. **Filesystem Case-Sensitivity Bypass:**
   - **Previous Blocker:** Unreal Engine displayed a modal alert `Unreal Engine does not support running from case-sensitive file systems` and terminated via SIGABRT.
   - **Resolution:** Implemented runtime hook on `NSURL getResourceValue:forKey:error:` and `resourceValuesForKeys:error:` intercepting `NSURLVolumeSupportsCaseSensitiveNamesKey` to return `NO` (simulating case-insensitive volume).
   - **Verification:** Modal dialog eliminated completely across all subsequent runs.

4. **Hardware & Platform Spoofing:**
   - **Implementation:** Intercepted `sysctlbyname` for `hw.model` (returning `Mac16,12`) and `hw.machine` (returning `arm64`).
   - **Verification:** Unreal Engine console logs confirm:
     ```text
     [UE4] Device Type: Mac16,12
     [UE4] Matched Mac as MacGame
     ```

5. **Exit Forensics & Reentrancy-Safe Interception:**
   - **Implementation:** Added interceptor for `_Exit` in `libShim_libSystem.dylib` with recursive guard (`gInHook`) and backtrace logging.
   - **Verification:** Test runs cleanly report backtrace and global state rather than crashing silently.

---

## Current Active Blocker (Investigation Priority)

During controlled test runs (latest verified: `test20_clean_uproject_plugins`), the process executes for approximately 3 seconds before terminating cleanly with **exit code 1**.

### Diagnostic Evidence at Exit

```text
SHIM INTERCEPTED _Exit(1)! Backtrace (6 frames):
  frame #0: libShim_libSystem.dylib     _Exit + 60
  frame #1: Stray-Mac-Shipping          -[UE4AppDelegate runGameThread:] (0x100675f24)
  frame #2: Stray-Mac-Shipping          -[FCocoaGameThread main] + 196
  frame #3: Foundation                  _NSThread__start
  frame #4: libsystem_pthread.dylib     _pthread_start + 136
  frame #5: libsystem_pthread.dylib     thread_start + 8

SHIM UE STATE AT _Exit:
  GIsRequestingExit = 1
  GDynamicRHI = 0x0
  GIsRHIInitialized = 0
  GIsMetalInitialized = 0
  GIsCriticalError = 0
  GMaxRHIFeatureLevel = 3
  GShaderPlatformForFeatureLevel = 49 (SP_NumPlatforms)
  GErrorHist = "Fatal error!\n\n"
```

### Forensic Analysis

1. **Origin of `_Exit(1)`:** In `-[UE4AppDelegate runGameThread:]`, `GuardedMain` returns exit code `1`. The code checks `cbnz w0, 0x100675f20` and invokes `_Exit(1)`.
2. **Failure inside `PlatformCreateDynamicRHI` / `FMetalDynamicRHI`:**
   - When command-line arguments do not specify `-metalsm5` or configuration lacks `TargetedRHIs` during early parsing, feature level defaults to `4`.
   - `FMetalDynamicRHI` selects shader platform 18 (`SP_METAL_MAC_ES3_1` / `"SF_METAL"`).
   - Validation against project `TargetedRHIs` (`SF_METAL_SM5` = 16) fails with low-level fatal error:
     `"Shader platform: SF_METAL was not cooked! Please enable this shader platform in the project's target settings."`
   - This sets `GIsRequestingExit = 1` and leaves `GDynamicRHI = 0x0`.
3. **Milestone 11 Shader Cache Lookup:**
   - With `GShaderPlatformForFeatureLevel` unset (remaining at `49`), the engine attempts to resolve `GlobalShaderCache-None.bin` and exits.

Active engineering work is focused on resolving this initialization chain so that `GDynamicRHI` is properly instantiated and `FEngineLoop` proceeds into its main tick loop.

---

## What Is Explicitly Not Working Yet

- **No visual rendering:** No frames or user interface have been displayed on the device screen.
- **Engine initialization incomplete:** `FEngineLoop` has not reached tick execution.
- **Audio pipeline unlinked:** CoreAudio/AudioMixer shims have not been tested.
- **Input unmapped:** Gameplay controls and touch inputs are not currently active.
- **Long-session stability:** Tests are restricted to 40-second watchdog windows.
