# Display and input investigation

## Display issue observed

The phase-G calibration capture was landscape (1808 × 816 pixels) and showed visibly stretched/compressed UI elements.

The later DualShock 4 recording is portrait (1320 × 2868 pixels). It does not prove that landscape has been corrected or that portrait is the intended rendering mode.

Potential investigation points, not confirmed root causes:
- UIKit scene orientation and rotation callbacks;
- hosting UIView frame/bounds and safe-area insets;
- `contentScaleFactor`;
- `UIScreen` logical/native bounds;
- `CAMetalLayer.drawableSize` and `contentsScale`;
- Unreal `FMetalView`, viewport dimensions and Slate layout;
- coordinate transforms and aspect-ratio policy.

The fix should make UIKit, Metal drawable and Unreal viewport dimensions agree. Preserve aspect ratio rather than applying arbitrary anisotropic scaling. If the game's intended aspect ratio differs from the device, choose a deliberate fit/fill strategy.

## Input issue observed

Phase G logs contain `SHIM touch began` entries. This confirms UIKit received touch beginnings, but does not prove touch-to-gameplay mapping.

In a later test, the user paired a PS4 DualShock 4 and reports that it successfully navigated past brightness calibration and through game menus. This is meaningful evidence that iOS controller input is reaching at least the UI navigation path. The supplied recording shows a Resume / Settings / Quit menu.

What remains unverified:
- player movement in a loaded level;
- camera control;
- action bindings such as jump/interact/meow;
- controller hot-plug/reconnect and disconnect handling;
- whether the engine sees a native GameController device or a compatibility event path.

The earlier phase-G stats counter reported `controllers=0`, but that was a separate test and does not override the later user-reported DualShock 4 result.

## First scene-load rendering issue

After the menu/transition, the latest recording shows a large blue/washed-out 3D view with obvious artifacts. No recognizable cat character or correctly rendered playable scene is visible. This should be investigated separately from menu rendering.

Potential areas to inspect (hypotheses only):
- shader library/function availability and pipeline variants;
- cooked shader platform compatibility;
- material permutation or feature-level mismatch;
- texture formats, streaming and mip residency;
- render-target formats and storage modes;
- depth/stencil and blending behavior;
- lighting, exposure, post-processing and color-space configuration;
- camera/frustum/viewport dimensions;
- resource lifetime and CPU/GPU synchronization after Managed-to-Shared adaptation.

Instrument the failing/incorrect draw path and compare expected versus actual pixel formats, shader functions, render-target sizes and feature-level decisions. Do not assume the Managed-to-Shared hook is the sole cause.

The overlay in the short recording shows roughly 19–31 FPS, app memory around 3.37–3.42 GB and available memory around 123–184 MB. Treat this as a possible memory/performance concern, not a diagnosis.

## Direct launch issue

Command-line launch supplies the project path and `-basedir`. Direct icon launch reportedly closes immediately. Missing arguments are plausible but unconfirmed; compare argv, current working directory, bundle paths and startup logs before implementing a fallback.
