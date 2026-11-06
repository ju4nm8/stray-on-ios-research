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

## Rendering follow-up — Runs 4 and 5 (5 November 2026)

The next on-device iterations reached the level again, but the scene remained only partially visible.

### Run 4 — selective geometry

A physical-device screenshot (2868 × 1320) was captured after entering the level. The visible image contained textured pipework and related environmental geometry against a largely black background. The cat, ground and surrounding walls were not clearly visible in that capture.

This is evidence that some scene objects and their materials can be drawn; it is not evidence that the full level or its lighting/rendering path is correct.

### Run 5 — runtime Early Z experiment

For the next attempt, the runtime `Engine.ini` configuration was changed to set `r.EarlyZPass=2`. The updated configuration was copied to the installed app's data container, and Stray was relaunched. The app reached the level again, including an autosave notification, but the subsequent capture still showed only selected pipe/structural elements against a predominantly black scene. This single test did **not** restore the missing environment.

The Run 5 log also records:
- the four observed core project PAK chunks (`pakchunk0` and the `_s1`, `_s2`, `_s3` variants) opening successfully;
- repeated Metal render-encoder creation and command buffers completing successfully during the sampled interval;
- one telemetry sample around 54 FPS, about 2.67 GB app memory, about 5.52 GB available memory, one reported controller, and nominal thermal state.

These are observations from a short run, not a benchmark. The memory sample does not indicate an obvious memory shortage at that moment. Successful PAK opens do not prove that every required asset was found, loaded, or rendered.

### Interpretation and limits

- The Metal rendering path is active; this is not a complete failure to submit/render frames.
- Some 3D geometry and textured surfaces are visible.
- The latest Run 4/5 captures do not show the cat or a complete recognizable environment.
- Setting `r.EarlyZPass=2` did not visibly resolve the problem in Run 5. This does not prove that Early Z is irrelevant; it only means this isolated runtime change was insufficient.
- No root cause has been established. Lighting/exposure, depth/prepass behavior, culling/LOD, mesh type, material permutations, camera/frustum and scene streaming remain hypotheses to test, not diagnoses.
- This iteration changed a runtime configuration file; the transcript does not show a new source-code fix being compiled and installed during Runs 4/5.

See [rendering follow-up notes](RENDERING-FOLLOW-UP.md) for the test sequence and next discriminating checks.
## Run 6 — improved tunnel rendering and input telemetry (5 November 2026)

After Runs 4/5, the runtime configuration was simplified in `Engine_clean.ini`: most earlier renderer overrides were removed so UE4 could use its normal defaults, with a small number of occlusion-related settings retained. The file was copied to the installed app's data container. The revised AppKit runtime shim used for this run had already been compiled, signed and installed in the Run 3 iteration; Run 6 itself was a configuration test, not a new code build.

Run 6 screenshots (2868 × 1320) showed a more recognizable tunnel environment: tunnel opening and sky/atmospheric effects, concrete walls, pipes, a valve wheel, cables/conduits, vines and textured pipework with rust/moss detail. The interior remained very dark. The cat was not clearly identified in the screenshot descriptions.

The VGC polling log reports one controller and non-zero analog stick axes during user input, while sampled `buttonsMask` values remained `0x0000`. This proves axis values reached the polling path, not that character movement, camera response or button actions worked in-game.

Telemetry samples ranged around 38–56 FPS, with about 2.8 GB app memory, 5.3–5.4 GB available memory and a `fair` thermal state. These are short-run samples, not a benchmark. The last visible task status in the transcript remained running, so long-session stability is not established.

The updated GPU-family hook had been revised after the Run 3 texture-view fatal error, built, signed and installed before Run 4. It no longer force-claims Mac1 and explicitly claims Mac2 while forwarding other queries to Metal. The later excerpts do not show recurrence of the same fatal error, but no controlled A/B test proves causality.

Run 6 is a meaningful visual improvement over Runs 4/5, but full gameplay remains unverified: the cat is not clearly visible, the effect of analog input on the character is not proven, and the tunnel interior remains too dark.

See [RENDERING-FOLLOW-UP.md](RENDERING-FOLLOW-UP.md) for screenshots, configuration context and detailed limitations.