# Changelog — Stray iOS Port Research

All notable changes and technical milestones for the Stray iOS compatibility project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [New Cycle Baseline] — 2026-11-23

### Established
- **Clean Technical Baseline:** Reorganized public documentation to establish an evidence-based technical baseline, separating verified device results from exploratory hypotheses.
- **Documentation Archival:** Archived preliminary reports and unverified claims from previous cycles into `archive/previous-development/` to preserve historical transparency without distorting current progress.
- **Nine-Stage Roadmap:** Adopted a structured 9-stage engineering roadmap focusing sequentially on process stability, Unreal Engine initialization, Metal RHI, rendering, and gameplay.
- **Safety Watchdog Infrastructure:** Implemented automated watchdog supervision (`tools/watchdog_stray.sh`) enforcing 40–90 second execution limits to protect the physical test device against thermal buildup and memory pressure.

### Verified Milestones (Current Baseline)
- **Physical Installation:** Successful conversion, signing with Personal Team certificate, and deployment of `com.ju4nm8.strayios` to physical iPhone 17 Pro Max (iOS 27.3) via `devicectl` (exit code 0).
- **ICU Data Discovery:** Resolved the early blocking fatal error `ICU data directory was not discovered` by extracting 3,463 ICU resource files (22 MB) from `pakchunk0-MacNoEditor.pak` to `Documents/stray/StrayICU/icudt64l` and providing a shim path redirect.
- **Case-Sensitivity Bypass:** Eliminated the modal alert abort `Unreal Engine does not support running from case-sensitive file systems` via a runtime hook intercepting `NSURLVolumeSupportsCaseSensitiveNamesKey` returning `NO`.
- **Platform Hardware Spoofing:** Implemented `sysctl` intercepts for `hw.model` (`Mac16,12`) and `hw.machine` (`arm64`), causing Unreal Engine to cleanly identify the host as `Device Type: Mac16,12` and `Matched Mac as MacGame`.
- **Exit Forensics & Interception:** Implemented reentrancy-guarded hook on `_Exit` in `libShim_libSystem.dylib`, capturing call backtraces and engine global state (`GIsRequestingExit=1`, `GDynamicRHI=0x0`, `GIsRHIInitialized=0`, `GErrorHist="Fatal error!\n\n"`).

### Active Blocker
- **Early Process Termination (~3s):** Engine initiates execution on the main/game threads but terminates cleanly with exit code 1 during early initialization (`-[UE4AppDelegate runGameThread:]` -> `_Exit(1)`). Active investigation focuses on `PlatformCreateDynamicRHI` / `FMetalDynamicRHI` and plugin configuration.

---

## [Archived Exploratory Cycle] — 2026-11-05 to 2026-11-22

### Summary
- Initial feasibility exploration using the [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public) compatibility framework.
- Analysis of original Mach-O headers, dynamic library dependencies, and PAK archive structure.
- Implementation of initial shims for AppKit, IOKit, CoreGraphics, and POSIX filesystem redirections.
- Exploratory runs (archived in `archive/previous-development/`) that documented preliminary hypotheses regarding rendering pipelines, texture views, and gamepad telemetry.
