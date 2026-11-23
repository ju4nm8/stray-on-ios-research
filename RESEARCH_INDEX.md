# Stray on iOS Research Repository — Technical Index

Welcome to the Stray on iOS compatibility research repository.

This branch (`publication/compatibility-shims-and-diagnostics`) publishes original compatibility shims, reproduction scripts, configuration templates, sanitized runtime execution logs, forensic crash analyses, and comprehensive architectural documentation to assist external Unreal Engine and Metal developers in diagnosing and solving remaining compatibility hurdles.

---

## Technical Directory Layout

### 1. [`source/shims/`](source/shims/) — Original Compatibility Shims
Objective-C dynamic libraries bridging macOS-specific APIs to iOS:
- **`IOKit.m`**: Synthetic IOKit GPU accelerator service adapter. Resolves null pointer dereference (`ldr w8, [x19, #0x28]`) in `FMetalDynamicRHI`.
- **`AppKit_RuntimeHooks.m`**: Metal storage mode translator (`Managed` -> `Shared`), UMA cache coherency stubs, and GPU family spoofing (`Mac2` -> YES, `Apple1..3` -> NO).
- **`AppKit.m`**: UIKit application fiber, early `FMemory::Realloc` command-line injection (`ShimSyncUnrealGSavedCommandLine`), and in-memory logging output device.
- **`libSystem.m`**: Case-normalizing `dlopen` interposer (resolving `libAPEXFramework` -> `libApexFramework`), filesystem redirection, and case-sensitivity bypass.
- **`Metal.m` & `CoreGraphics.m`**: Stubs for missing macOS symbols on iOS.

### 2. [`scripts/`](scripts/) — Tools & Automation
- **`convert_app.py`**: Automated Mach-O load command rewriter and bundle adapter.
- **`extract_icu.py`**: Standalone tool extracting the Unreal Engine ICU localization tree from `pakchunk0-MacNoEditor.pak` without distributing game assets.
- **`run_test.sh`**: Controlled on-device test runner with watchdog coordination and PID verification.
- **`watchdog_stray.sh`**: Independent background supervisor enforcing maximum execution limits.

### 3. [`configs/`](configs/) — Configuration Templates
- **`Info-ios.plist.template`**: Documented bundle configuration including `SHIMWorkingDirectory` and `SHIMPathRedirects`.
- **`profile_template.plist`**: Sanitized entitlement definitions for code signing.
- **`GameUserSettings.ini.template`**: Pre-configured Unreal Engine 4 graphics settings.

### 4. [`logs/`](logs/) — Sanitized Runtime Evidence
- **`test33_metal_rhi_60fps_sanitized.log`**: Device execution log demonstrating full Metal RHI initialization, texture storage mode conversion, and stable present loop.
- **`test31_iokit_gpu_descriptor_sanitized.log`**: Console log showing synthetic IOKit GPU adapter initialization (`Apple A19 Pro GPU`).
- **`test30_physx_case_hook_sanitized.log`**: Console log showing case-insensitive dynamic library loading.
- **`test1_nsurl_case_fix_sanitized.log`**: Console log showing case-sensitivity check bypass.

### 5. [`diagnostics/`](diagnostics/) — Static Analysis & Symbol Audits
- **`gap_main_exe_symbols.txt`**: Static gap audit of missing iOS frameworks and symbols.
- **`metal_shader_scan.txt`**: Scan of Metal shader libraries and bytecode signatures.
- **`executable_load_commands.txt`**: Dump of Mach-O load commands from `Stray-Mac-Shipping`.
- **`macho_analysis.txt`**: Section headers and binary layout analysis.

### 6. [`research/`](research/) — Technical Research & Forensic Reports
- **`METAL_RHI_AND_PHYSX_RESOLUTION.md`**: Executive summary and timeline of the Metal RHI and PhysX crash resolutions.
- **`QWEN_METAL_INDEPENDENT_AUDIT.md`**: Independent engineering review of the synthetic IOKit GPU adapter.
- **`BUG_TO_SOURCE_MAP.md`**: Exhaustive mapping of observed symptoms to engine code and disassembly offsets.
- **`OPENCODE_SOURCE_AUDIT.md`**: Comparative analysis of Unreal Engine classes, cameras, and skeletal meshes.
- **`ANTIGRAVITY_SOURCE_ANALYSIS.md`**: Deep dive into camera initialization and bone limits.
- **`CLAUDE_FINDINGS.md`**: Analysis of global shader cache lookup and exit code forensics.
- **`DECISIONS.md`**: Architectural decision records.

### 7. [`documentation/`](documentation/) — Project Documentation
- **[`ARCHITECTURE.md`](documentation/ARCHITECTURE.md)**: End-to-end technical architecture of the translation layer.
- **[`CURRENT_BLOCKERS.md`](documentation/CURRENT_BLOCKERS.md)**: Grounded physical device state and technical breakdown of open rendering blockers.
- **[`REPRODUCTION_GUIDE.md`](documentation/REPRODUCTION_GUIDE.md)**: Step-by-step reproduction instructions for developers with macOS `Stray.app`.
- **[`CONTRIBUTION_CALL_FOR_HELP.md`](documentation/CONTRIBUTION_CALL_FOR_HELP.md)**: Clear list of technical questions where Unreal Engine 4 and Metal expertise is urgently needed.
- **[`LICENSING_AND_PROVENANCE.md`](documentation/LICENSING_AND_PROVENANCE.md)**: Full copyright, licensing, and attribution register.

---

## Community Contribution

We welcome contributions from graphics engineers, Unreal Engine specialists, and iOS developers! Please review [`documentation/CONTRIBUTION_CALL_FOR_HELP.md`](documentation/CONTRIBUTION_CALL_FOR_HELP.md) for current focus areas.
