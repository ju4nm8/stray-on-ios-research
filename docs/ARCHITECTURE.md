# Architecture notes

## Scope

I run a native ARM64 macOS application bundle inside an iOS application container using the compatibility approach from the upstream macos-on-ios project. Stray remains the original macOS build; it is not a native iOS binary. iOS signing and platform restrictions still apply.

## Layers I have worked on

1. **Converted bundle.** I place the macOS app tree in an iOS-compatible bundle layout. The conversion adjusts Mach-O platform metadata and load paths/RPATHs, then signs the app for my development device.
2. **Framework compatibility.** I route macOS-only dependencies through shim dylibs and bridge AppKit behavior onto UIKit.
3. **Resource discovery.** Unreal expects project-relative paths and Mac bundle resource locations. My working setup uses a project sidecar, ICU sidecar, path redirects and a runtime base directory.
4. **Platform/GPU discovery.** The Mac build queries IOKit. My iOS adapter provides the registry structure Unreal expects using information from the iPhone's actual Metal device. The Phase-G log identifies an Apple A19 Pro GPU and `AGXMetalG18P`.
5. **Metal adaptation.** I encountered macOS-only Managed storage requests and added targeted hooks to translate the observed requests to Shared on iOS. I later revised `supportsFamily:` handling after a texture-view format assertion. I document both paths and their limitations in [METAL-COMPATIBILITY.md](METAL-COMPATIBILITY.md).
6. **Rendering and input.** I can now open Stray directly from its iOS icon and reach a recognizable tunnel environment. The Run 6 interior remains very dark, and I have not clearly confirmed the cat. VGC logs show non-zero analog stick axes reaching the polling layer, but I have not verified character movement, camera response or action buttons inside Unreal. I have also not completed the landscape viewport/aspect-ratio verification.

## Launch behavior

Earlier successful command-line launches supplied the relative path to `Hk_project.uproject` and a `-basedir` pointing to `.../Hk_project/Binaries/Mac` inside the installed app. I have since successfully opened Stray directly from its iOS Home Screen icon, so command-line launch is no longer the only working entry point.

The app container UUID changes across installations. My runtime setup must discover the current container path rather than hard-code a previous UUID.

A visible menu or rendered scene does not by itself prove that all assets, gameplay systems, save behavior, audio, input or later levels work.