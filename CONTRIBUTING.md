# Contributing to Stray iOS Research

Contributions that advance technical accuracy, engineering rigor, and reproducible findings are welcome.

The project prioritizes evidence-backed documentation, forensic disassembly, and reproducible observations over speculative discussions.

---

## Areas Where Contributions Help

1. **Unreal Engine 4 Runtime Internals:**
   - Insights into `FEngineLoop::PreInit`, `PlatformCreateDynamicRHI`, and feature-level negotiation in UE4 custom builds.
   - Command-line parsing and initialization order for early configuration tables (`GEngineIni`, `TargetedRHIs`).
2. **Metal RHI & Shader Architecture:**
   - Behavior of `FMetalDynamicRHI` on Apple Silicon iOS devices when running a macOS-compiled engine binary.
   - Shader Model 5 (`SF_METAL_SM5`) pipeline state object (PSO) compilation and caching on iOS Metal runtimes.
3. **Instrumentation & Shims:**
   - Clean, reentrancy-safe POSIX / Foundation hooks for `libShim_libSystem.dylib`.
   - Suggestions for safe memory monitoring and log flushing before process shutdown.

---

## Submission Guidelines

- All documentation and pull requests must adhere to the [Publishing Scope & Safety Checklist](PUBLISHING-SCOPE.md).
- **Never submit proprietary assets, PAK contents, binaries, or signing certificates.**
- Every claim of progress must be accompanied by reproducible logs, backtraces, or telemetry captured on physical hardware.
- Adhere to the 9-stage framework defined in [ROADMAP.md](ROADMAP.md).
