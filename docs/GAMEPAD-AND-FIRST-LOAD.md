# Gamepad navigation and first scene-load attempt

## What the user tested

The user paired a PS4 DualShock 4 controller with the iPhone and reports that this made it possible to proceed beyond Stray's brightness-calibration screen and navigate the UI.

The supplied 28-second screen recording:
- is captured at 1320 × 2868 in portrait orientation;
- begins on a Stray menu showing Resume, Settings and Quit;
- shows a transition through a dark interval;
- then shows a rendered 3D view dominated by blue/washed-out surfaces and visible artifacts;
- ends at the iOS Home Screen.

The recording does not establish whether the app was intentionally backgrounded or crashed at the end.

## Performance overlay observations

Across sampled moments in this short recording, the overlay reports approximately:
- 19–31 FPS;
- 3.37–3.42 GB app memory;
- 123–184 MB available memory.

These values are transcribed from the device overlay and should not be treated as a controlled benchmark or a definitive memory-pressure diagnosis. The available-memory figures are low enough to warrant careful monitoring during subsequent scene loading.

## What this proves

- A physical DualShock 4 was used successfully for menu navigation, according to the user.
- The app progresses beyond the brightness-calibration UI.
- The rendering path presents a 3D-looking image after the menu/transition, rather than only the earlier calibration UI.

## What it does not prove

- The 3D scene is correctly loaded or rendered.
- The cat character is visible and controllable.
- Movement, camera and action inputs work during gameplay.
- The app is stable under a longer session.
- Landscape rendering or aspect ratio is fixed.

## Next tests

1. Capture a fresh console log for the same controller-assisted run.
2. Confirm the app process termination reason when leaving the game.
3. Record controller connection state and GameController callbacks.
4. Identify which menu actions are received and whether Unreal reports a connected controller.
5. Inspect the first scene's shader libraries, pipeline state creation, material permutations, texture streaming, render targets, depth and post-processing.
6. Monitor memory and frame time continuously while entering the scene.
7. Keep the current Metal compatibility hooks unchanged until the new rendering evidence identifies a specific fault.
