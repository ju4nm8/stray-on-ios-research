# Build, Installation & Testing Guide

This guide describes the complete procedure for adapting, codesigning, deploying, and running **Stray** on a physical iPhone using the compatibility framework.

> [!CAUTION]
> **Preserve the Original Bundle:** Never perform modifications directly on your primary `Stray.app` installation. Always work on an APFS clone (`cp -c`) or development copy.

---

## 1. Prerequisites

### Host System
- **Machine:** Apple Silicon Mac (M-series processor).
- **Operating System:** macOS 14.0 or newer.
- **Xcode:** Xcode 15.0 or newer with command-line tools installed.
- **Tools:** `vtool`, `install_name_tool`, `codesign`, `devicectl`, Python 3.

### Target Device
- **Device:** iPhone 17 Pro Max (or compatible Apple Silicon iPhone/iPad).
- **iOS Version:** iOS 17.0 or newer (tested on iOS 27.3).
- **Developer Mode:** Enabled on the device (Settings -> Privacy & Security -> Developer Mode).
- **Connection:** Connected via USB and paired with the host Mac.

### Apple Developer Account
- A valid Apple Developer Personal Team profile or standard Apple Developer Account.
- Provisioning profile configured for the bundle identifier `com.ju4nm8.strayios`.

---

## 2. Bundle Conversion Workflow

The conversion process adapts the macOS Mach-O binary and bundle directory layout into an iOS-compliant structure:

```bash
# 1. Create a clean working copy using APFS copy-on-write
cp -c -R "/Volumes/Disco Juan/Projects/Stray iOS/Stray.app" "work/Stray.app"

# 2. Modify Mach-O platform headers (macOS -> iOS)
vtool -set-build-version ios 17.0 27.1 \
  -replace -output "work/Stray.app/Contents/MacOS/Stray-Mac-Shipping" \
  "work/Stray.app/Contents/MacOS/Stray-Mac-Shipping"

# 3. Compile runtime shims
make -C upstream/macos-on-ios-public/shim

# 4. Inject shim dynamic libraries into the bundle
cp upstream/macos-on-ios-public/shim/build/*.dylib "work/Stray.app/Contents/Frameworks/"

# 5. Adjust dynamic library load commands and RPATHs
install_name_tool -add_rpath "@executable_path/../Frameworks" \
  "work/Stray.app/Contents/MacOS/Stray-Mac-Shipping"
```

---

## 3. Code Signing & Entitlements

iOS strictly enforces code signature validation and sealed resource requirements. Frameworks must be signed from the inside out:

```bash
IDENTITY="Apple Development: your.name@example.com (TEAM_ID)"
ENTITLEMENTS="work/entitlements.plist"

# 1. Sign all embedded dynamic libraries and frameworks
for dylib in work/Stray.app/Contents/Frameworks/*.dylib; do
  codesign --force --sign "$IDENTITY" --timestamp=none "$dylib"
done

# 2. Sign the outer application bundle with entitlements
codesign --force --sign "$IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  --timestamp=none \
  "work/Stray.app"

# 3. Verify signature validity
codesign --verify --deep --strict "work/Stray.app"
```

---

## 4. Device Deployment & Resource Provisioning

### Deploy via `devicectl`
```bash
# Install application bundle to connected device
xcrun devicectl device install app \
  --device <DEVICE_UUID> \
  "work/Stray.app"
```

### Provision Container Resources (ICU & Sidecars)
Unreal Engine requires ICU internationalization files and project descriptors placed into the application's data container:

```bash
# Copy extracted ICU data directory to app container Documents
xcrun devicectl device copy to \
  --device <DEVICE_UUID> \
  --domain-type appDataContainer \
  --domain-identifier com.ju4nm8.strayios \
  --source "work/icu_stage/StrayICU" \
  --destination "Documents/stray/"
```

---

## 5. Controlled Execution & Host Watchdog

To prevent device overheating or runaway background processes, all test executions must be governed by the independent host watchdog:

```bash
# Launch test with 40-second automated watchdog supervisor
./tools/run_test.sh --timeout 40 --extra-args "-log -metalsm5"
```

The watchdog monitors process state, streams console logs to `artifacts/logs/`, and issues a termination signal (`devicectl process terminate / kill`) if execution exceeds the configured safety ceiling.
