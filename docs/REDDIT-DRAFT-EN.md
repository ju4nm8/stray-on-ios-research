# Reddit post draft — r/macgaming

**Title: Has anyone looked into running the macOS build of Stray on an iPhone? I'm stuck on rendering issues**

Hey, I've been working on an experiment to see whether the original Apple Silicon macOS version of Stray can run on an iPhone, using [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public) as the compatibility base.

I got it to launch from the iOS Home Screen and reach an actual 3D level on my iPhone 17 Pro Max. I can also run, jump, meow and keep progressing through the game, but the visual side is still pretty broken.

The main problems right now:

- The cat itself is invisible, even though its actions respond in-game.
- Parts of the map and environment geometry don't show up.
- Some textures and materials are missing or look wrong.
- Lighting and exposure are inconsistent, with areas that are way too dark.
- I haven't figured out whether this is mainly a UE4 skeletal-mesh/skin-cache issue, a Metal compatibility problem, shader/material behavior, resource streaming, GFur, or something else.

Static environment geometry does render in some areas, so I'm trying to understand why that works while the cat and other parts of the scene don't. I have been looking at Unreal's skeletal mesh path, GPU skinning, masked materials, stencil/LOD dithering, Early Z and Metal feature/format support, but I don't have a confirmed cause yet.

For context, recent short test runs showed around 52–53 FPS median over roughly 94 seconds. That's just telemetry from short sessions; the game is nowhere near visually complete and I am not claiming it's fully playable.

I'd really appreciate ideas from anyone familiar with Unreal Engine's Metal RHI, skeletal mesh rendering, GPU skinning, shader permutations or iOS/Metal resource handling. Even suggestions for a good way to isolate the cause would help.

Project notes and logs: https://github.com/ju4nm8/stray-on-ios-research

This is an unfinished personal compatibility experiment, not a native iOS port. I'm not sharing the game files or assets.
