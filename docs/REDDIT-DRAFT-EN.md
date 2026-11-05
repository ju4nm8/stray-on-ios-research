# Reddit draft — r/macgaming

**Title:** I got the original macOS build of Stray to reach its brightness calibration screen on an iPhone 17 Pro Max

I'm experimenting with the macOS-on-iOS compatibility work from [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public), testing it with the original Apple-silicon macOS build of Stray.

After working through bundle/resource paths, Unreal's Mac platform detection, an IOKit GPU descriptor path and a macOS-vs-iOS Metal storage-mode mismatch, I got the game to render its autosave warning and brightness-calibration UI on an iPhone 17 Pro Max.

A few observations:
- Unreal reaches the initial Stray UI.
- The phase-G log shows Metal library loading and Managed-to-Shared texture conversions.
- The performance overlay/log reported around 59–62 FPS during parts of the short run.
- Landscape presentation is currently distorted.
- Touch events reach UIKit, but end-to-end gameplay input is unproven.
- Launching from the SpringBoard icon still closes immediately; the successful run used command-line arguments.

To be clear: this is **not playable yet**, not an iOS port, and I'm not distributing the game or its assets. I'm documenting compatibility work and remaining issues.

Research notes: https://github.com/ju4nm8/stray-on-ios-research

I'd be interested in thoughts from people familiar with Unreal's Mac Metal RHI, UIKit/Metal layer sizing or input bridging.
