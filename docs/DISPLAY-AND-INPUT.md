# Display and input investigation

## Display issue observed

The phase-G recording shows Stray's brightness-calibration screen, but the landscape presentation is distorted. The supplied image is 1808 × 816 pixels and UI elements visibly appear stretched/compressed.

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

The phase-G log contains several `SHIM touch began` entries. This confirms UIKit received touch beginnings. It does not confirm that `touchesMoved`, `touchesEnded`, synthetic mouse events, Slate input, Unreal input mappings or gameplay actions work end-to-end. The statistics report `controllers=0`; this is not sufficient to conclude that touch input is broken or to establish whether a physical controller was tested.

## Planned input investigation

Trace UIKit touch begin/move/end/cancel, view-to-viewport coordinate conversion, synthetic NSEvent/platform mouse events, Slate application and `FGenericApplicationMessageHandler`, Unreal player input and Stray's actual action bindings. Only after identifying original bindings should virtual controls be designed. A candidate layout is a left movement zone, right camera drag and action buttons with proper multi-touch tracking and cancellation. This is proposed, not implemented.

## Direct launch issue

Command-line launch supplies the project path and `-basedir`. Direct icon launch reportedly closes immediately. Missing arguments are plausible but unconfirmed; compare argv, current working directory, bundle paths and startup logs before implementing a fallback.
