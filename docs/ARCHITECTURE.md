# Architecture notes

## Scope

The experiment takes a native ARM64 macOS application bundle and runs it inside an iOS application container using the upstream macos-on-ios compatibility approach. The game binary is not a native iOS build of Stray. iOS signing and platform constraints still apply.

## Relevant layers

1. **Converted bundle.** The macOS app tree is placed under an iOS-compatible bundle layout. The conversion adjusts Mach-O platform metadata, load paths and RPATHs, then signs with a development identity.
2. **Framework compatibility.** macOS-only dependencies are redirected through shim dylibs. AppKit behavior is bridged onto UIKit.
3. **Resource discovery.** Unreal expects project-relative paths and Mac bundle resource locations. The working setup uses a project sidecar, ICU sidecar, path redirects and runtime base directory.
4. **Platform/GPU discovery.** The Mac build queries IOKit. The iOS adapter supplies the expected registry structure using information from the actual iPhone Metal device. The phase-G log identifies Apple A19 Pro GPU and AGXMetalG18P.
5. **Metal adaptation.** A key incompatibility was macOS-only Managed storage. Targeted hooks convert observed requests to Shared for iOS. A later `supportsFamily:` shim revision explicitly reports Mac2 and leaves other GPU-family queries to real Metal after an earlier texture-view format assertion. The revised shim was compiled, signed and installed before Run 4; follow-up runs progressed without the same fatal error in the supplied excerpts. Details and caveats are in [METAL-COMPATIBILITY.md](METAL-COMPATIBILITY.md).
6. **Rendering and input.** The app now reaches a recognizable tunnel environment in Run 6, although the interior remains very dark and the cat is not clearly confirmed in the screenshot descriptions. VGC logs show non-zero analog stick axes reaching the polling layer, but sampled button masks are zero and in-game movement/camera response is unverified. UIKit touch-began events are logged, but propagation into game actions is also unverified. Landscape sizing and aspect ratio remain unresolved.

## Launch contract observed in phase G

The successful command-line launch supplied the relative path to `Hk_project.uproject` and a `-basedir` pointing to `.../Hk_project/Binaries/Mac` inside the installed app. The bundle container UUID changes across installations; runtime setup must discover the current path and never hard-code an old UUID.

A rendered initial UI does not prove that all assets, gameplay systems, save behavior, audio, input or later levels work.
