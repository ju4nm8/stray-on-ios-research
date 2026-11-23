# Reproduction & Experimentation Guide

This guide describes how an external developer with legal access to macOS `Stray.app` can reproduce the research environment, apply the shims, and test on a physical iOS device.

## Prerequisites

1. **Hardware & Environment:**
   - macOS Sonoma (14.0+) or macOS Sequoia (15.0+) on Apple Silicon (M1/M2/M3/M4).
   - Xcode 15 or later with iOS 17+ SDK and command-line tools installed.
   - Physical iOS device running iOS 17.0+ (iOS Developer Mode enabled).
   - Apple Developer Account (Personal Team or Paid Developer Program).
2. **Software & Python Tools:**
   - Python 3.10+
   - `repak` (`pip install repak`)
   - `devicectl` (included with Xcode 15+)
3. **Proprietary Game Content (Not Provided):**
   - Legitimate copy of `Stray.app` for macOS Apple Silicon (v1.5 / build 99).
   - **Never distribute or share `Stray.app`, executables, or `.pak` files.**

---

## Step-by-Step Reproduction Procedure

### Step 1: Prepare Safe Workspace
Create a separate working directory and clone your `Stray.app` using copy-on-write APFS clone to avoid touching original files:

```bash
mkdir -p StrayPort/work
cp -c -R "/path/to/original/Stray.app" StrayPort/work/Stray.app
```

Verify that the working copy matches original hashes.

---

### Step 2: Compile the Compatibility Shims
Using `clang` from the Xcode iOS SDK, compile the Objective-C source files into dynamic libraries (`arm64` iOS target):

```bash
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)

# 1. Compile libShim_IOKit.dylib
xcrun -sdk iphoneos clang -target arm64-apple-ios17.0 -dynamiclib \
    -isysroot "$SDK_PATH" -fobjc-arc \
    -framework Foundation -framework CoreFoundation -framework Metal \
    -install_name @rpath/libShim_IOKit.dylib \
    source/shims/IOKit.m -o StrayPort/work/libShim_IOKit.dylib

# 2. Compile libShim_AppKit.dylib
xcrun -sdk iphoneos clang -target arm64-apple-ios17.0 -dynamiclib \
    -isysroot "$SDK_PATH" -fobjc-arc \
    -framework Foundation -framework UIKit -framework Metal -framework QuartzCore \
    -install_name @rpath/libShim_AppKit.dylib \
    source/shims/AppKit.m source/shims/AppKit_RuntimeHooks.m \
    -o StrayPort/work/libShim_AppKit.dylib

# 3. Compile libShim_libSystem.dylib
xcrun -sdk iphoneos clang -target arm64-apple-ios17.0 -dynamiclib \
    -isysroot "$SDK_PATH" -fobjc-arc \
    -framework Foundation \
    -install_name @rpath/libShim_libSystem.dylib \
    source/shims/libSystem.m -o StrayPort/work/libShim_libSystem.dylib
```

---

### Step 3: Extract the ICU Localization Tree
Unreal Engine 4 requires its internationalization tree outside the pak file on iOS:

```bash
python3 scripts/extract_icu.py \
    "StrayPort/work/Stray.app/Contents/UE4/Hk_project/Content/Paks/pakchunk0-MacNoEditor.pak" \
    StrayPort/work/icu_stage
```

This extracts `Engine/Content/Internationalization/icudt64l` into `StrayPort/work/icu_stage/StrayICU/icudt64l` and generates a verified SHA-256 manifest.

---

### Step 4: Convert and Rebind the Mach-O Bundle
Run `convert_app.py` to adapt the bundle structure and link against the compiled shims:

```bash
python3 scripts/convert_app.py \
    --working-dir "Contents/UE4/Hk_project/Binaries/Mac" \
    --redirect "Internationalization=Documents/stray/StrayICU" \
    --shim-dir "StrayPort/work" \
    StrayPort/work/Stray.app \
    StrayPort/work/out/Stray.app
```

---

### Step 5: Provisioning and Code Signing
1. Generate a provisioning profile for your test device using Xcode or the developer portal.
2. Sign the bundle with your development identity:

```bash
DEVELOPER_IDENTITY="Apple Development: your.email@example.com (<TEAM_ID>)"
PROVISION_PROFILE="/path/to/your.mobileprovision"

# Embed provisioning profile
cp "$PROVISION_PROFILE" StrayPort/work/out/Stray.app/embedded.mobileprovision

# Sign all nested frameworks and shims first
find StrayPort/work/out/Stray.app/Frameworks -name "*.dylib" -exec \
    codesign --force --sign "$DEVELOPER_IDENTITY" --timestamp=none {} \;

# Sign the main executable with entitlements
codesign --force --sign "$DEVELOPER_IDENTITY" \
    --entitlements configs/profile_template.plist \
    --timestamp=none StrayPort/work/out/Stray.app
```

Verify signature:
```bash
codesign --verify --deep --strict StrayPort/work/out/Stray.app
```

---

### Step 6: Install, Deploy ICU Data, and Run
1. Install the application on your physical device:
```bash
xcrun devicectl device install app --device "<TARGET_DEVICE_UDID>" StrayPort/work/out/Stray.app
```

2. Copy the extracted ICU tree to the app's `Documents` container:
```bash
# Using devicectl or pymobiledevice3 to upload to Documents/stray/StrayICU/icudt64l
```

3. Launch with the safety test runner:
```bash
DEVICE_ID="<TARGET_DEVICE_UDID>" scripts/run_test.sh 45 test_reproduction_run
```
