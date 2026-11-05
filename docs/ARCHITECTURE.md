# Architecture notes

## Scope

The experiment takes a native ARM64 macOS application bundle and runs it inside an iOS application container using the upstream macos-on-ios compatibility approach. The game binary is not a native iOS build of Stray. iOS signing and platform constraints still apply.

## Relevant layers

1. **Converted bundle.** The macOS app tree is placed under an iOS-compatible bundle layout. The conversion adjusts Mach-O platform metadata, load paths and RPATHs, then signs with a development identity.
2. **Framework compatibility.** macOS-only dependencies are redirected through shim dylibs. AppKit behavior is bridged onto UIKit.
3. **Resource discovery.** Unreal expects project-relative paths and Mac bundle resource locations. The working setup uses a project sidecar, ICU sidecar, path redirects and runtime base directory.
4. **Platform/GPU discovery.** The Mac build queries IOKit. The iOS adapter supplies the expected registry structure using information from the actual iPhone Metal device. The phase-G log identifies Apple A19 Pro GPU and AGXMetalG18P.
5. **Metal adaptation.** A key incompatibility was macOS-only Managed storage. Targeted hooks convert observed requests to Shared for iOS. Details and caveats are in [METAL-COMPATIBILITY.md](METAL-COMPATIBILITY.md).
6. **Rendering and input.** Unreal/Slate renders the game's initial UI. UIKit touch-began events are logged, but propagation into game actions is unverified. Landscape sizing and aspect ratio remain unresolved.

## Launch contract observed in phase G

The successful command-line launch supplied the relative path to `Hk_project.uproject` and a `-basedir` pointing to `.../Hk_project/Binaries/Mac` inside the installed app. The bundle container UUID changes across installations; runtime setup must discover the current path and never hard-code an old UUID.

A rendered initial UI does not prove that all assets, gameplay systems, save behavior, audio, input or later levels work.
