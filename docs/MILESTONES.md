# Milestone log

I use the phase labels below to organize my experiments. They are internal project milestones, not official upstream releases.

## Baseline compatibility probe

I first launched a small AppKit + Metal probe through the shim. Its logs showed the `NSApplication` to `UIApplicationMain` bridge, Metal pipeline creation and receipt of touch events. This validated the basic bridge, not Stray itself.

## Stray bundle conversion

I converted my original Stray macOS app into an iOS-compatible bundle layout. The work included RPATH rewriting, preservation of minimum macOS version metadata where needed, a corrected Mac project descriptor sidecar and redirects for project and ICU resources. I keep the original app and its four PAK files as local data; I do not publish them in this repository.

## Platform and resource compatibility

- I adapted Unreal's case-sensitive-filesystem check through a targeted `NSURL` hook.
- I supplied a runtime `-basedir` and observed `chdir` succeeding.
- I added ICU redirects.
- I adapted `hw.model` so Unreal selected its Mac game platform path.
- I corrected dynamic-library loading through RPATH changes and case-insensitive resolution for a library filename mismatch.
- I extended the IOKit shim to provide the GPU registry structure Unreal expects, backed by information from the iPhone's actual Metal device.

## Phases E/F — reaching Metal RHI

I advanced the app into `FMetalDynamicRHI` initialization. An earlier attempt failed because Unreal's GPU descriptor list was empty. I found that the installed IOKit shim did not expose the expected newer exports, corrected it and verified the updated exports in the installed bundle.

## Phase F3 — GPU descriptor found; Managed storage failure

The IOKit adapter constructed a GPU descriptor from the iPhone GPU. Unreal then reached texture creation, but Metal rejected `MTLStorageModeManaged` (numeric value 1), which this iOS device does not accept. The validation failure occurred while Unreal initialized system textures.

## Phase G — initial Stray interface

I added targeted hooks for concrete Metal descriptor/runtime classes and translated the observed Managed texture storage requests to Shared. The phase-G log records Managed-to-Shared texture conversions, a no-op `synchronizeTexture` blit operation, successful Metal library loading, render-loop samples around 59–62 FPS during part of the run, UIKit touch-began entries and Stray's autosave warning/brightness-calibration interface.

The process later exited with status 0 after the app moved to the background. I did not observe the earlier Metal validation crash in that phase-G run.

### What Phase G did not establish

- I had not confirmed arrival at the main menu.
- I had not demonstrated gameplay.
- I had not verified touch-to-gameplay mapping.
- The landscape presentation was visibly distorted.
- Direct icon launch was still failing in that earlier iteration; that problem has since been resolved in a later test.
- Long-session stability and performance were still untested.

## DualShock 4 navigation and first scene-load attempt

I later paired a PS4 DualShock 4 with the iPhone and used it to move beyond brightness calibration and navigate Stray's menus. I recorded the Resume / Settings / Quit menu and a transition into a 3D view.

That first 3D view was blue/washed out and visibly corrupted. I could not identify the cat or a correctly rendered playable scene. The short recording showed approximately 19–31 FPS, around 3.37–3.42 GB of app memory and 123–184 MB available memory. These were brief overlay readings, not a controlled benchmark or a diagnosis of memory pressure.

The recording ended at the iOS Home Screen. I could not determine from that clip alone whether the app had crashed or had been intentionally backgrounded.

## Run 3 — GPU-family and texture-view investigation

During a later attempt, UE4 entered a fatal-error loop after Metal rejected a texture view whose source format was `RGBA8Unorm_sRGB` while the requested view format was `R8Unorm`. I traced the investigation to UE4's `ToSRGBFormat` path and the shim's `supportsFamily:` interception.

I revised `ShimSupportsFamily`: I stopped force-claiming Mac1, explicitly claimed Mac2 and allowed the real Metal implementation to answer other GPU-family queries. I compiled, signed and installed the revised `libShim_AppKit.dylib` before Run 4. Runs 4–6 then progressed into the level without the same fatal error appearing in the supplied log excerpts. This is consistent with the revision mitigating that specific failure, but I have not run a controlled A/B test proving causality.

## Runs 4 and 5 — selective geometry and Early Z test

In Run 4, I captured selected textured pipes and structural geometry against a mostly black background. The cat, ground and surrounding walls were not clearly visible.

In Run 5, I changed the runtime `Engine.ini` to set `r.EarlyZPass=2`, copied the configuration into the app's data container and relaunched Stray. The scene still showed selected structures against a predominantly black background. That single setting did not restore the missing environment.

The Run 5 log recorded successful opens for the four observed core project PAK chunks, repeated Metal render-encoder creation and completed command buffers. A telemetry sample showed about 54 FPS, 2.67 GB app memory, 5.52 GB available memory, one controller and nominal thermal state. Those readings do not prove that every asset was loaded or rendered.

## Run 6 — improved tunnel rendering and input telemetry

After Runs 4/5, I created `Engine_clean.ini` to remove most experimental renderer overrides and let UE4 use its normal defaults, while retaining a small number of occlusion-related settings. I copied it into the installed app's data container. Run 6 was a runtime-configuration test, not a new source-code build.

Run 6 screenshots (2868 × 1320) showed a more recognizable tunnel: an opening with visible sky and atmospheric effects, concrete walls, pipes, a valve wheel, cables/conduits, vines and textured pipework with rust/moss detail. The interior remained very dark, and I could not clearly identify the cat in the screenshot descriptions.

The VGC polling log recorded one controller and non-zero left/right analog-stick axes during input, while sampled `buttonsMask` values remained `0x0000`. I can confirm that the axis values reached the shim's polling path; I cannot yet confirm that Unreal applied them to character movement or camera control, or that action buttons worked.

Run 6 telemetry samples ranged around 38–56 FPS, with about 2.8 GB app memory, 5.3–5.4 GB available memory and a `fair` thermal state. These were short-run observations, not a benchmark. The captured transcript still showed the logging task running, so it did not establish long-session stability.

## Direct launch from the iOS icon — confirmed

**Update, 6 November 2026:** I have now successfully opened Stray directly from its iOS Home Screen icon. This resolves the earlier direct-launch blocker for my current setup. I am not claiming that this alone proves sustained stability or complete gameplay; those remain separate tests.

## Current milestone

I can open Stray from its iOS icon and reach a recognizable 3D tunnel environment. The next priorities are to correct the dark interior, clearly capture the cat, verify controller movement/camera/actions inside Unreal, check landscape viewport sizing and complete a longer stability test.

See [KNOWN-ISSUES.md](KNOWN-ISSUES.md), [DISPLAY-AND-INPUT.md](DISPLAY-AND-INPUT.md), [GAMEPAD-AND-FIRST-LOAD.md](GAMEPAD-AND-FIRST-LOAD.md), [RENDERING-FOLLOW-UP.md](RENDERING-FOLLOW-UP.md) and [METAL-COMPATIBILITY.md](METAL-COMPATIBILITY.md).

## Phase J — on-device launch, live scene and skeletal-mesh investigation

### Phase J1 — re-sign, install and render verification

I reviewed the Phase I.2 handoff and existing AppKit runtime hook. The non-blocking window-activation implementation was already present in the working tree, and the packaged AppKit dylib contained the corresponding activation symbol. The transcript does not show a new implementation of that deadlock fix during this pass.

I re-signed the existing app bundle and its embedded frameworks. An initial verification attempt reported a sealed-resource mismatch; I repeated the signing sequence with the frameworks signed before the outer app bundle. The final bundle verification reported a valid signature, and `devicectl` installed the app successfully on the connected iPhone 17 Pro Max.

I launched the installed app and observed Metal library loading, render-encoder creation, drawable presentation and completed command buffers. The Run J1 screenshot sequence showed an active 3D level and the in-game touch HUD. The first screenshot was initially interpreted as showing the cat and B-12 backpack, but later captures and subsequent inspection did not corroborate that reading: the cat is not clearly identifiable in the later scene captures. One subsequent screenshot was black with an iOS notification over the HUD. I therefore do not treat the initial visual interpretation as proof that the cat rendered.

The transcript records a screenshot HUD sample around 42.85 FPS and later log samples near 58 FPS. These are separate short observations, not a stable 60-FPS benchmark. The session used `devicectl device capture screenshot`; I do not see evidence that the requested QuickTime display plus macOS `screencapture` workflow was completed.

### Runs 7–8 — renderer configuration and skeletal-mesh diagnosis

Run 7 produced screenshots of a rainy courtyard and a more detailed tunnel/corridor with pipes, wall textures, rust, moss and interaction prompts. Static environment geometry was rendering, but the cat's skeletal mesh remained absent in the reviewed gameplay captures. A brief VGC log sample showed `buttonsMask=0x0001`; this confirms a bit transition at the shim polling layer, not that a corresponding action worked in-game.

I inspected the packaged `DefaultEngine.ini`, the four project PAK archives, relevant map entries and cat assets. The cat mesh and related material assets exist in the original PAK data, so the evidence does not point to a missing source asset. I then inspected Unreal symbols and structures associated with skeletal meshes and GFur, including `USkeletalMeshComponent`, `FSkeletalMeshSceneProxy`, `UGFurComponent` and `FFurSceneProxy`. The working hypothesis narrowed to the skeletal/dynamic-mesh rendering path on Metal; possible contributors include GPU skinning configuration, masked/subsurface materials and GFur dependencies. None is yet confirmed as the root cause.

For Run 8, I created `Engine_run8.ini` with GPU skin-cache-related settings and copied it into the app's data container at `Library/Preferences/Stray/MacNoEditor/Engine.ini`. I relaunched the existing installed app; the log showed continued Metal rendering and a sample around 40 FPS, 3025 MB app memory, 5167 MB available memory and nominal thermal state. The Run 8 screenshot showed an industrial scene with an orange pipe, concrete structures, vegetation and fog, but did not clearly show the cat. This test did not resolve or prove the skeletal-mesh issue.

### Phase J conclusion

- Direct icon launch remains separately confirmed by my 6 November update.
- The existing Phase I.2 non-blocking activation code was inspected; this session re-signed and installed the existing bundle rather than documenting a new source implementation of that fix.
- Metal rendering and static 3D level geometry are active on the physical iPhone.
- Cat visibility and skeletal-mesh rendering remain unverified/unsuccessful in the later captures.
- Controller input is not yet proven end-to-end. A button-mask transition or visible HUD is not equivalent to verified movement, camera response or action execution.
- The transcript ends during the Run 8 investigation with an active command/task and an Antigravity “out of credits” indicator. There is no final successful gameplay verification in this record.

The next technical priority is to isolate and fix skeletal-mesh rendering before spending more time tuning unrelated visual settings.
