# Configuration Templates & Guide

This directory contains sanitized configuration templates used when preparing and launching the adapted macOS binary on iOS.

## Files

- **`Info-ios.plist.template`**: iOS `Info.plist` used during bundle conversion. Includes essential custom keys:
  - `SHIMWorkingDirectory`: Specifies `Contents/UE4/Hk_project/Binaries/Mac` so relative paths used by the engine (`../../../Engine/...`) resolve cleanly.
  - `SHIMPathRedirects`: Maps virtual engine paths (such as `Internationalization`) to disk locations in the app's `Documents` container.
  - `SHIMAppParentRedirect`: Redirects writes intended for the app root into `Documents/stray`.
- **`profile_template.plist`**: iOS entitlement definitions needed for code signing:
  - `application-identifier`
  - `com.apple.developer.team-identifier`
  - `get-task-allow` (for debugging)
  - `com.apple.developer.kernel.increased-memory-limit` (for extended memory access under iOS 17+)
- **`GameUserSettings.ini.template`**: Unreal Engine 4 user settings file pre-configured for mobile execution:
  - Clamps resolution to 1536x864.
  - Sets Fullscreen WindowMode=0.
  - Applies balanced Scalability settings to maintain memory headroom.

## Note on Credentials

No actual Team IDs, provisioning profiles, or developer certificates are stored in this repository. Developers must supply their own Apple Developer account identifiers when building and signing.
