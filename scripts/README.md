# Build, Extraction & Automation Scripts

This directory contains standalone tools and scripts for converting, extracting, and testing the adapted application bundle on iOS devices.

## Scripts Overview

### 1. `convert_app.py`
Extends the upstream conversion script to adapt a macOS `.app` bundle for iOS:
- Rewrites Mach-O load commands (`LC_LOAD_DYLIB` pointing to shim dylibs instead of missing macOS system frameworks).
- Applies bundle adjustments (Info.plist adaptation, resource directory normalization).
- Supports `--working-dir` to embed `SHIMWorkingDirectory`.
- Supports `--redirect` to configure path redirection in `SHIMPathRedirects`.

### 2. `extract_icu.py`
Standalone Python script to extract the Unreal Engine Internationalization (ICU) data tree from a game `.pak` file without distributing proprietary assets:
- Uses `repak` to locate and extract `Engine/Content/Internationalization/icudt64l/...`.
- Outputs a verified SHA-256 manifest of the extracted tree.
- Resolves the fatal launch error: `ICU data directory was not discovered`.

Usage:
```bash
python3 extract_icu.py <path/to/pakchunk0-MacNoEditor.pak> <output_directory>
```

### 3. `run_test.sh`
Automated on-device test runner with safety controls:
- Connects to the target iOS device via `xcrun devicectl`.
- Spawns an independent watchdog process to guarantee execution time limits.
- Launches the application with console log capture.
- Performs post-run verification and cleanup to ensure no orphaned processes remain.

Usage:
```bash
DEVICE_ID="<YOUR_UDID>" ./run_test.sh 45 test_run_name
```

### 4. `watchdog_stray.sh`
Independent background safety supervisor:
- Monitors the target process PID on the device.
- Terminates the process if execution exceeds the specified safety threshold (maximum 80 seconds).
- Protects physical test devices from runaway loops, thermal overload, or hangs.

### 5. `run_icu_test.sh`
Specialized runner for verifying ICU redirection and early boot progress without requiring full test harness overhead.
