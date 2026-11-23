# Display and input investigation

## Display findings

My Phase-G calibration capture was landscape (1808 × 816 pixels) and showed visibly stretched/compressed UI elements.

Later Run 4–6 captures were landscape at 2868 × 1320 and showed the level. This confirms that I can capture the game in landscape, but it does not by itself prove that the viewport, safe areas or aspect ratio are correct.

An earlier DualShock 4 recording was portrait (1320 × 2868). I keep that as historical evidence only; it is not proof that portrait is the intended rendering mode.

Items I still need to verify:
- UIKit scene orientation and rotation callbacks;
- hosting `UIView` frame/bounds and safe-area insets;
- `contentScaleFactor`;
- `UIScreen` logical/native bounds;
- `CAMetalLayer.drawableSize` and `contentsScale`;
- Unreal `FMetalView`, viewport dimensions and Slate layout;
- coordinate transforms and aspect-ratio policy.

I want UIKit, the Metal drawable and the Unreal viewport to agree. I will preserve the game's aspect ratio rather than applying arbitrary anisotropic scaling. If the intended game aspect ratio differs from the device, I will use a deliberate fit/fill strategy.

## Input findings

Phase-G logs contain `SHIM touch began` entries. This confirms that UIKit received touch beginnings, but it does not prove touch-to-gameplay mapping.

I paired a PS4 DualShock 4 with the iPhone and used it to navigate past brightness calibration and through Stray's menus. The captured menu showed Resume / Settings / Quit.

In Run 6, VGC polling logs showed one controller and non-zero left- and right-stick axes during input. Sampled `buttonsMask` values remained `0x0000`. I can confirm that analog values reached the shim's polling path; I cannot yet confirm that Unreal applied them to player movement or camera control. The sampled logs also do not show a pressed face/shoulder button.

What I still need to verify:
- player movement in a loaded level;
- camera control;
- action bindings such as jump, interact and meow;
- controller hot-plug, reconnect and disconnect handling;
- whether Unreal receives a native GameController device or a compatibility event path.

The earlier Phase-G stats counter reported `controllers=0`; that was a separate run before the later DualShock 4 menu-navigation test.

## Rendering issue after the first scene load

My first menu-to-level attempt produced a blue/washed-out 3D view with obvious artifacts. Runs 4–6 then improved the visible environment, with Run 6 showing a recognizable tunnel, pipes, structures, sky and atmospheric effects. The tunnel interior remains too dark, and the cat is not clearly confirmed in the latest captures.

Possible investigation areas (still hypotheses, not confirmed causes):
- shader library/function availability and pipeline variants;
- cooked shader platform compatibility;
- material permutation or feature-level mismatch;
- texture formats, streaming and mip residency;
- render-target formats and storage modes;
- depth/stencil and blending behavior;
- lighting, exposure, post-processing and color-space configuration;
- camera/frustum/viewport dimensions;
- resource lifetime and CPU/GPU synchronization after the Managed-to-Shared adaptation.

I should instrument the incorrect draw path and compare expected versus actual pixel formats, shader functions, render-target sizes and feature-level decisions. I should not assume that the Managed-to-Shared hook is the sole cause.

## Direct launch from the iOS icon

I have now successfully opened Stray directly from its iOS Home Screen icon. This supersedes the earlier observation that direct icon launch closed immediately. I have not yet used that fact to claim long-session stability or complete gameplay.