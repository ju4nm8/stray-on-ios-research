# Static Binary Diagnostics & Symbol Analysis

This directory contains static binary analysis reports and symbol audit dumps extracted from the target executable (`Stray-Mac-Shipping`) and its dependent libraries.

## Files Description

### 1. `gap_main_exe_symbols.txt`
Static analysis of missing macOS frameworks and symbols produced by `gap.py`:
- Catalogs frameworks requested by the macOS binary that are absent from iOS (Cocoa, Carbon, IOKit, AudioUnit, OpenGL, AppKit).
- Lists 109 specific exported/imported symbol differences that required shim implementation.

### 2. `metal_shader_scan.txt`
Inspection of embedded Metal shader libraries, metallib signatures, and shader format identifiers (`SF_METAL_SM5`, `SP_METAL`).

### 3. `executable_load_commands.txt`
Dump of Mach-O load commands from `Stray-Mac-Shipping`, showing `LC_LOAD_DYLIB`, `LC_RPATH`, `LC_BUILD_VERSION` (originally macOS 12.0 arm64), and entry points.

### 4. `macho_analysis.txt`
Detailed segment and section layout of the game executable (`__TEXT`, `__DATA`, `__LLVM_COV`, etc.) used during symbol hooking and address slide calculations.

### 5. `rhi_hints.txt`
Hex and string analysis identifying Unreal Engine 4 RHI initialization pathways, command line arguments (`-metalsm5`, `-metal`, `-SaveToUserDir`), and rendering subsystem references.
