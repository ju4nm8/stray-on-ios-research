# Stray on iOS — Technical Compatibility Research

> Can the original Apple Silicon macOS build of **Stray** run on a physical iPhone?
> 
> *Stray iOS is entering a new development cycle. The project is establishing a clean technical baseline and rebuilding its public roadmap around the current implementation goals.*

[En español](README.es.md) · [Project Status](PROJECT_STATUS.md) · [Development Roadmap](ROADMAP.md) · [Architecture](docs/ARCHITECTURE.md) · [Current Blockers](docs/CURRENT_BLOCKERS.md)

---

## 1. Project Overview & Scope

This repository documents an independent technical experiment exploring whether the compiled ARM64 macOS release of **Stray** (built on Unreal Engine 4) can be executed inside an iOS application container on a physical iPhone 17 Pro Max using userspace compatibility shims derived from [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public).

The game binary (`Stray-Mac-Shipping`) remains the original macOS Mach-O executable. The experiment uses binary platform header adaptation, dynamic library load path adjustments, and runtime shims (AppKit -> UIKit, IOKit GPU discovery, Metal storage mode translation) to bridge platform differences.

> [!IMPORTANT]
> **Research Only — No Game Distribution:** This repository contains exclusively documentation, diagnostic analysis, and compatibility shims. It does **not** contain or distribute game executables, PAK archives, copyrighted textures, 3D models, audio, or provisioning credentials.

---

## 2. Current Engineering Status

```mermaid
flowchart LR
    A["Stage 1: Launch & Stability"] --> B["Stage 2: UE4 Init"]
    B --> C["Stage 3: Metal RHI"]
    C --> D["Stage 4: First Render"]
    D --> E["Stages 5-9: Gameplay & Polish"]

    style A fill:#ff9966,stroke:#333,stroke-width:2px
    style B fill:#ffff99,stroke:#333,stroke-width:2px
    style C fill:#eeeeee,stroke:#333
    style D fill:#eeeeee,stroke:#333
    style E fill:#eeeeee,stroke:#333
```

### Verified Facts (Confirmed on Physical Hardware)
- **Target Hardware:** iPhone 17 Pro Max, iOS 27.3, Apple Silicon.
- **Binary Conversion:** Mach-O load command converted to iOS platform via `vtool`; signed with Personal Team profile and installed via `devicectl` (Exit Code 0).
- **Filesystem Case-Sensitivity:** The blocking modal alert (*Unreal Engine does not support running from case-sensitive file systems*) is bypassed via an `NSURL` hook returning `NO` for `NSURLVolumeSupportsCaseSensitiveNamesKey`.
- **ICU Resource Discovery:** The fatal crash `ICU data directory was not discovered` is resolved by deploying extracted ICU resource data (3,463 files) to `Documents/stray/StrayICU` with a shim redirect.
- **Hardware Recognition:** Sysctl hooks spoofing `hw.model` as `Mac16,12` enable Unreal Engine to match the platform as `Device Type: Mac16,12` / `Matched Mac as MacGame`.
- **Exit Tracing:** Intercepted `_Exit` hook captures stack backtraces and engine state at termination.

### What Is Not Working (Reality Check)
- **Early Termination:** The process terminates ~3 seconds after launch with exit code 1 (`_Exit(1)` called from `-[UE4AppDelegate runGameThread:]`).
- **No Rendering Yet:** No graphics or user interface appear on screen. Engine state at exit confirms `GDynamicRHI == 0x0`, `GIsRHIInitialized == 0`, and `GIsMetalInitialized == 0`.
- **Controls & Audio:** Neither audio playback nor input systems have been reached or initialized.

---

## 3. Active Investigation: The Early Exit Blocker

Disassembly of `PlatformCreateDynamicRHI` (`0x101a28268`) and `FMetalDynamicRHI::FMetalDynamicRHI` (`0x101219188`) revealed the causal chain of the termination:

1. **Feature Level Fallback:** Without `-metalsm5` in early command-line parsing, feature level defaults to `4`.
2. **Shader Platform Mismatch:** Feature level `4` triggers selection of shader platform 18 (`SP_METAL_MAC_ES3_1` / `"SF_METAL"`).
3. **Fatal Validation:** `FMetalDynamicRHI` compares platform 18 against project `TargetedRHIs` (`SF_METAL_SM5` = 16) defined in `BaseEngine.ini`. The mismatch triggers a low-level fatal error and sets `GIsRequestingExit = 1`.
4. **Milestone 11 Abort:** With `GDynamicRHI` uninstantiated, Milestone 11 attempts to load `GlobalShaderCache-None.bin`, fails, and invokes `_Exit(1)`.

See [docs/CURRENT_BLOCKERS.md](docs/CURRENT_BLOCKERS.md) for full forensic logs, register dumps, and disassembly traces.

---

## 4. Nine-Stage Implementation Roadmap

The project follows a strict 9-stage engineering progression:

| Stage | Goal | Status |
|---|---|---|
| **Stage 1** | **Process Stability & Launch** | **In Progress (Active Blocker)** |
| **Stage 2** | **Unreal Engine Initialization** | **In Progress** |
| **Stage 3** | **Metal & RHI Initialization** | **Blocked by Stage 2** |
| **Stage 4** | **First Screen Rendering Output** | Not Started |
| **Stage 5** | **Scene Geometry & Character Representation** | Not Started |
| **Stage 6** | **Materials, Textures & Lighting** | Not Started |
| **Stage 7** | **Audio Pipeline Recovery** | Not Started |
| **Stage 8** | **Input Controls & Gameplay Handling** | Not Started |
| **Stage 9** | **Performance, Thermals & Long-Session Stability** | Not Started |

Detailed criteria for each stage are maintained in [ROADMAP.md](ROADMAP.md).

---

## 5. Technical Documentation Index

- [PROJECT_STATUS.md](PROJECT_STATUS.md) — Comprehensive evidence matrix and verified test logs.
- [ROADMAP.md](ROADMAP.md) — 9-stage implementation roadmap and passing criteria.
- [CHANGELOG.md](CHANGELOG.md) — Chronological log of changes and milestones.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Deep-dive into shims, Mach-O modification, and runtime bridging.
- [docs/CURRENT_BLOCKERS.md](docs/CURRENT_BLOCKERS.md) — Disassembly, ASLR slide analysis, and exit diagnostics.
- [docs/INSTALLATION.md](docs/INSTALLATION.md) — Step-by-step conversion, signing, deployment, and watchdog setup.
- [docs/METAL-COMPATIBILITY.md](docs/METAL-COMPATIBILITY.md) — Metal storage modes, shader platforms, and GPU family spoofing.
- [archive/previous-development/](archive/previous-development/) — Archived exploratory notes and historical reports.

---

## 6. Upstream & Safety Policies

- **Upstream Project:** Compatibility infrastructure is based on [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public) by Ross Fisher (MIT License). See [UPSTREAM.md](UPSTREAM.md).
- **Publishing Rules:** See [PUBLISHING-SCOPE.md](PUBLISHING-SCOPE.md) for non-distribution policies.
- **Contributing:** See [CONTRIBUTING.md](CONTRIBUTING.md) for research participation guidelines.
