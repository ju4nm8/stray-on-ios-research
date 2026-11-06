# Reddit draft — r/macgaming

**Title:** I can now launch the original macOS build of Stray from the iOS Home Screen on an iPhone 17 Pro Max

I'm experimenting with the macOS-on-iOS compatibility work from [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public), using the original Apple-silicon macOS build of Stray.

I've worked through bundle and resource paths, Unreal's Mac platform detection, IOKit GPU discovery and several Metal compatibility issues. I can now open Stray directly from its iOS Home Screen icon and reach a recognizable 3D tunnel environment on my iPhone 17 Pro Max.

The current result is still incomplete:
- The tunnel environment is visible, including textured pipes, concrete structures, cables, vegetation, sky and atmospheric effects.
- The tunnel interior is much too dark.
- I have not clearly confirmed the cat in my latest captures.
- My VGC logs show analog stick values reaching the shim, but I have not yet verified character movement, camera response or action buttons inside Unreal.
- Short Run 6 telemetry samples varied around 38–56 FPS. These are not benchmark results.

This is **not a claim that Stray is fully playable**, not a native iOS port, and I'm not distributing the game or its assets. I'm documenting the compatibility work and the remaining engineering problems.

Research notes: https://github.com/ju4nm8/stray-on-ios-research

I'd be interested in thoughts from people familiar with Unreal's Mac Metal RHI, UIKit/Metal layer sizing, shader permutations or GameController input bridging.