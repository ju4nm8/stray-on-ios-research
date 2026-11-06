# Gamepad navigation and first scene-load attempt

I keep this note as the record of my first controller-assisted attempt to move from Stray's menus into a 3D level. Runs 4–6 and the later direct-icon launch update supersede some of the early visual/launch limitations described below.

## Earlier controller-assisted recording

I paired a PS4 DualShock 4 with the iPhone and used it to proceed beyond Stray's brightness-calibration screen and navigate the UI.

My 28-second recording:
- was captured at 1320 × 2868 in portrait orientation;
- began on a Stray menu showing Resume, Settings and Quit;
- showed a transition through a dark interval;
- then showed a 3D view dominated by blue/washed-out surfaces and visible artifacts;
- ended at the iOS Home Screen.

That recording alone did not establish whether I intentionally backgrounded the app or whether it crashed at the end.

## Performance overlay in that earlier recording

Across sampled moments, the overlay showed approximately:
- 19–31 FPS;
- 3.37–3.42 GB app memory;
- 123–184 MB available memory.

These were short overlay readings, not a controlled benchmark or a definitive memory-pressure diagnosis. The low available-memory figures made it important to monitor memory during subsequent scene loading.

## What I established at that stage

- I could use a paired physical DualShock 4 to navigate the menus.
- I could progress beyond the brightness-calibration UI.
- The rendering path produced a 3D-looking image after the menu transition.

## What that early recording did not establish

- correct 3D scene rendering;
- a clearly visible and controllable cat;
- movement, camera and action inputs during gameplay;
- long-session stability;
- correct landscape rendering or aspect ratio.

## What later tests changed

Run 6 improved the visible scene substantially: I captured a recognizable tunnel environment with textured pipework, concrete structure, cables/conduits, vines, sky and atmospheric effects. The interior remained dark, and the cat was not clearly identified in the available screenshot descriptions.

Run 6 VGC polling logs recorded non-zero left/right stick axes, proving that analog values reached the shim polling path. However, sampled `buttonsMask` values remained `0x0000`, and I have not yet demonstrated the resulting character movement, camera response or action bindings inside Unreal.

I have also since confirmed that I can open Stray directly from its iOS Home Screen icon. The earlier direct-launch failure is no longer current.

## Next tests

1. Capture a fresh controller-assisted session and match the input log to visible movement on screen.
2. Verify the controller's face buttons, triggers, sticks and D-pad individually.
3. Confirm that Unreal recognizes the controller and that the game applies the values to the intended actions.
4. Capture a clear frame showing the cat in the level.
5. Monitor memory, frame time, thermal state and app lifecycle during a longer session.
6. Keep the Metal compatibility hooks unchanged unless new evidence identifies a specific fault.