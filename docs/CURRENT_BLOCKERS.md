# Current Technical Blockers & Active Investigation

This document provides a technical deep-dive into the current active blocker preventing **Stray** from completing initialization on iOS.

---

## The Active Blocker: Early Termination During `FEngineLoop::AppInit`

During controlled device launches (Test 20, `test20_clean_uproject_plugins`), the application process starts, spawns its threads, progresses through early platform checks, and terminates approximately 3 seconds after launch with **exit code 1**.

### Physical Device Telemetry at Exit

```text
2026-11-23 06:05:42.245 Stray-Mac-Shipping[7533:707305] [UE4] Device Type: Mac16,12
2026-11-23 06:05:42.247 Stray-Mac-Shipping[7533:707305] [UE4] Matched Mac as MacGame
2026-11-23 06:05:42.948 Stray-Mac-Shipping[7533:707300] SHIM STATS fps=0 cpu=22 mem=91 avail=3285 threads=39 controllers=0 loops=180 thermal=nominal
2026-11-23 06:05:43.979 Stray-Mac-Shipping[7533:707290] SHIM STATS fps=0 cpu=1 mem=91 avail=3285 threads=39 controllers=0 loops=8 thermal=nominal
2026-11-23 06:05:44.857 Stray-Mac-Shipping[7533:707305] SHIM INTERCEPTED _Exit(1)! Backtrace (6 frames):
2026-11-23 06:05:44.857 Stray-Mac-Shipping[7533:707305]   frame #0: 0   libShim_libSystem.dylib             0x000000010c51a184 _Exit + 60
2026-11-23 06:05:44.857 Stray-Mac-Shipping[7533:707305]   frame #1: 1   Stray-Mac-Shipping                  0x0000000102975f24 -[UE4AppDelegate applicationDidFinishLaunching:] + 0
2026-11-23 06:05:44.857 Stray-Mac-Shipping[7533:707305]   frame #2: 2   Stray-Mac-Shipping                  0x000000010364ff4c -[FCocoaGameThread main] + 196
2026-11-23 06:05:44.857 Stray-Mac-Shipping[7533:707305]   frame #3: 3   Foundation                          0x0000000199cfcfb8 _NSThread__start + 2113464
2026-11-23 06:05:44.857 Stray-Mac-Shipping[7533:707305]   frame #4: 4   libsystem_pthread.dylib             0x000000019955701c _pthread_start + 136
2026-11-23 06:05:44.857 Stray-Mac-Shipping[7533:707305]   frame #5: 5   libsystem_pthread.dylib             0x000000019955391c thread_start + 8
2026-11-23 06:05:44.857 Stray-Mac-Shipping[7533:707305] SHIM UE STATE AT _Exit: slide=0x2300000 GIsRequestingExit=1 GMaxRHIFeatureLevel=3 GShaderPlatformForFeatureLevel=49 GMaxRHIShaderPlatform=0 GAppleMetalEnabled=1 GDynamicRHI=0x0 GIsRHIInitialized=0 GIsMetalInitialized=0 GIsCriticalError=0
2026-11-23 06:05:44.857 Stray-Mac-Shipping[7533:707305] SHIM UE GErrorHist: "Fatal error!\n\n"
2026-11-23 06:05:44.857 Stray-Mac-Shipping[7533:707305] SHIM UE GLog: pGLog=0x10751a490 numLines=0
The app terminated with the exit code 1.
```

---

## Forensic Disassembly & Causal Sequence

### 1. ASLR Slide Resolution
- Observed address of `-[FCocoaGameThread main]`: `0x10364ff4c` (`- 196 = 0x10364fe88`).
- Static symbol in Mach-O binary: `0x10134fe88`.
- Calculated ASLR Slide: `0x10364fe88 - 0x10134fe88 = 0x2300000`.
- Calling instruction before frame 1: `0x102975f24 - 0x2300000 = 0x100675f24`.
  - Instruction at `0x100675f20`: `bl 0x103c8cba8 ; _Exit`.
  - Condition: Evaluates return value of `GuardedMain` in `w0`. If non-zero (`cbnz w0, 0x100675f20`), invokes `_Exit(1)`.

### 2. Failure Root Cause: `FMetalDynamicRHI` & Shader Platform Validation
Detailed disassembly of `PlatformCreateDynamicRHI` (`0x101a28268`) and `FMetalDynamicRHI::FMetalDynamicRHI` (`0x101219188`):

1. **Feature Level Fallback:**
   - When `TargetedRHIs` has not yet been populated from the project configuration or command line, register `w20` (Feature Level) falls back to `4`.
   - Without `-metalsm5` present in the initial parsed command line, `FMetalDynamicRHIModule::CreateRHI(4)` is called.

2. **Shader Platform Selection (`0x101219a88`):**
   - At feature level `4` without `-metalsm5`, execution jumps to `0x101219ae4`, setting `GMaxRHIShaderPlatform = 18` (`SP_METAL_MAC_ES3_1`, formatted as `"SF_METAL"`).

3. **TargetedRHIs Mismatch & Fatal Error:**
   - At `0x101219b50`, `FMetalDynamicRHI` queries `TargetedRHIs` from `/Script/MacTargetPlatform.MacTargetSettings` in `GEngineIni`.
   - In Stray's original `Engine/Config/BaseEngine.ini` (inside the authentic PAK):
     ```ini
     +TargetedRHIs=SF_METAL_SM5
     ```
   - At `0x101219be4`, the RHI checks whether the active platform (`SF_METAL` = 18) exists in `TargetedRHIs` (`SF_METAL_SM5` = 16).
   - Because `18 != 16`, execution branches to `0x101219bf8`:
     - Calls `LowLevelFatalErrorHandler` (`0x101219ee0`):
       `"Shader platform: SF_METAL was not cooked! Please enable this shader platform in the project's target settings."`
     - Invokes `FDebug::ProcessFatalError()` (`0x101219ef0`) and `FMacPlatformMisc::RequestExit(true)` (`0x101219e94`).
     - Sets `GIsRequestingExit = 1` and aborts RHI instantiation, leaving `GDynamicRHI = 0x0`.

4. **Cascading Failure at Milestone 11:**
   - Because `GDynamicRHI == 0x0`, `RHIInit` skips RHI setup.
   - `GShaderPlatformForFeatureLevel[3]` remains uninitialized at `49` (`SP_NumPlatforms`).
   - At Milestone 11 (`CompileGlobalShaderMap`), the engine asks for `LegacyShaderPlatformToShaderFormat(49)` -> `"None"`, attempting to open `../../../Engine/GlobalShaderCache-None.bin`, fails, and calls `_Exit(1)`.

---

## Investigation Plan & Next Steps

1. **Force SM5 via CLI & Ini Injection:**
   - Ensure `-sm5 -metalsm5 -metal` is consistently present in `GSavedCommandLine` prior to `PlatformCreateDynamicRHI`.
   - Ensure `BaseEngine.ini` / `DefaultEngine.ini` properly export `SF_METAL_SM5` into `GEngineIni` during early pre-init.
2. **Verify Global Shader Cache Path:**
   - Ensure that when `GMaxRHIShaderPlatform` is set to `16` (`SF_METAL_SM5`), `CompileGlobalShaderMap` successfully opens `GlobalShaderCache-SF_METAL_SM5.bin`.
3. **Capture UE Disk Logs:**
   - Redirect engine logging output so diagnostic messages from `GLog` are persisted to the app container before process termination.
