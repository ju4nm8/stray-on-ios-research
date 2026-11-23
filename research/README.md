# Research & Forensic Audit Reports

This directory contains in-depth engineering reports, forensic crash analyses, and disassembly notes produced during the compatibility investigation.

## Reports Overview

- **`METAL_RHI_AND_PHYSX_RESOLUTION.md`**: Executive summary and chronology of how the Metal RHI crashes (SIGSEGV `0x28` null dereference, storage mode validation aborts) and PhysX filesystem loader failures were diagnosed and resolved.
- **`QWEN_METAL_INDEPENDENT_AUDIT.md`**: Independent engineering review of the synthetic `IOKit.m` GPU adapter. Analyzes CoreFoundation ownership semantics, ABI conventions, property dictionary formats, and why Unreal's `FMacPlatformGPUManager` requires synthetic `IOAccelerator` properties.
- **`BUG_TO_SOURCE_MAP.md`**: Exhaustive mapping between observed symptoms, exact disassembly offsets, affected engine source files (from public UE4 headers and mod projects), and experimental A/B validation plans.
- **`OPENCODE_SOURCE_AUDIT.md`**: Comparative analysis of Unreal Engine class hierarchies (`CatPawn`, `AHKPlayerController`, `AHKPlayerCameraManager`), skeletal mesh component bounds, camera management, and bone limit differences between Desktop and Mobile profiles.
- **`ANTIGRAVITY_SOURCE_ANALYSIS.md`**: Forensic analysis exploring camera initialization order, pawn occlusion flags, and rendering pipeline hypotheses.
- **`CLAUDE_FINDINGS.md`**: Analysis of global shader cache lookup mechanics, working directory resolution, and exit code classification.
- **`DECISIONS.md`**: Architectural decision log recording technical constraints, rationale for shim designs, and non-viable hypotheses that were formally rejected.
