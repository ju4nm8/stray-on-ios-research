# Milestone log

Phase labels follow the project's working notes; they are not official upstream releases.

## Baseline probe

A small AppKit + Metal probe was launched through the shim. Logs showed the NSApplication-to-UIApplicationMain bridge, Metal pipeline creation and touch event receipt. This validated the basic bridge only, not Stray.

## Early Stray conversion

The original Stray macOS app was converted to an iOS-compatible bundle layout. Work included RPATH rewriting, preservation of minimum macOS version metadata where needed, a corrected Mac project descriptor sidecar and redirects for project and ICU resources. The original app and four PAK files remain user-owned local data and are not included here.

## Platform and resource compatibility

- Unreal's case-sensitive-filesystem check was adapted through a targeted NSURL hook.
- A runtime `-basedir` was required and `chdir` success was observed.
- ICU redirects were added.
- `hw.model` was adapted so Unreal selected its Mac game platform path.
- Dynamic library loading required RPATH corrections and case-insensitive resolution for a library filename mismatch.
- The IOKit shim was extended to provide the GPU registry structure expected by Unreal, backed by the actual iPhone Metal device identity.

## Phases E/F — reaching Metal RHI

The app advanced into `FMetalDynamicRHI` initialization. An earlier failure occurred because Unreal's GPU descriptor list was empty. Inspection showed that the then-installed IOKit shim did not contain the expected newer exports; this was corrected and verified in the installed bundle.

## Phase F3 — GPU descriptor found; Managed storage failure

The IOKit adapter ran and constructed a GPU descriptor from the iPhone GPU. Unreal reached texture creation but Metal rejected `MTLStorageModeManaged` (value 1), which is not accepted on this iOS device. The validation failure occurred during Unreal system texture initialization.

## Phase G — initial Stray UI appears

The targeted Metal adaptation installed hooks on concrete descriptor/runtime classes and translated observed Managed texture storage requests to Shared. The observed log includes Managed-to-Shared texture conversions, a no-op `synchronizeTexture` blit operation, successful Metal library loading, render-loop statistics around 59–62 FPS for part of the run, UIKit touch-began entries, and the Stray autosave warning/brightness-calibration UI in the recording.

The process ended with exit code 0 after the app transitioned to the background. No phase-G Metal validation crash was observed.

### What phase G does not prove

- Main menu arrival is not confirmed.
- Gameplay is not confirmed.
- Touch-to-gameplay mapping is not confirmed.
- Landscape presentation is visibly distorted.
- Direct SpringBoard icon launch reportedly closes immediately; the cause is unknown.
- Long-session stability and performance are untested.

## Follow-up experiment — DualShock 4 navigation and first scene-load attempt

A later user-recorded test paired a PS4 DualShock 4 controller to the iPhone. The user reports that the controller allowed progression beyond brightness calibration and navigation through the game's UI.

The recording begins on a Stray menu displaying Resume, Settings and Quit. After the user resumes/attempts to continue, the picture transitions through a dark loading-like interval and then displays a large blue/washed-out 3D view with obvious visual artifacts. There is no clearly identifiable cat character or fully recognizable playable scene in the supplied clip.

The on-screen performance overlay during this short recording shows:
- approximately 19–31 FPS across sampled moments;
- app memory around 3.37–3.42 GB;
- available memory around 123–184 MB;
- a portrait capture resolution of 1320 × 2868.

These are readings from the device overlay in one short recording, not a controlled benchmark, and they do not establish the cause of the rendering problem or memory behavior.

### What this follow-up establishes — and what it does not

- **Established by user report:** DualShock 4 input is sufficient to navigate past the brightness calibration and through at least some menus.
- **Visible in the recording:** Stray's UI, a transition, and a rendered but severely corrupted-looking 3D view.
- **Not established:** correct scene/material rendering, visible player character, actual movement through a level, camera control, or sustained gameplay.
- **Not established:** that the earlier landscape/aspect-ratio issue is fixed; this recording is portrait.
- The recording ends at the iOS Home Screen. It does not establish whether the app crashed or was intentionally backgrounded.

## Next investigation

See [KNOWN-ISSUES.md](KNOWN-ISSUES.md), [DISPLAY-AND-INPUT.md](DISPLAY-AND-INPUT.md), and [GAMEPAD-AND-FIRST-LOAD.md](GAMEPAD-AND-FIRST-LOAD.md).
