# Rendering follow-up — Runs 4–6

Date: 5 November 2026  
Target: iPhone 17 Pro Max, physical device  
Project: original Stray macOS Apple-silicon build running through the macos-on-ios compatibility layer

## Run 4 — selective scene rendering

I captured the level at 2868 × 1320. The screenshot showed textured pipework and related environmental geometry against a largely black background. I could not clearly identify the cat, ground or surrounding walls.

This established that some geometry and textured surfaces were being drawn. It did not establish that the whole map, its lighting or the player character was rendering correctly.

## Run 5 — Early Z configuration experiment

I changed the runtime configuration to set:

```ini
r.EarlyZPass=2
```

I copied the updated `Engine_fixed.ini` into the installed app's data container, stopped the running process and relaunched Stray. The game reached the level again, including an autosave notice, but the next capture still showed selected pipes/structures against a mostly black scene.

**Result:** this configuration change did not visibly restore the missing environment. I do not have enough evidence to conclude that Early Z is or is not the root cause.

## Run 5 log observations

The log showed:
- successful opens for `pakchunk0-MacNoEditor.pak` and its `_s1`, `_s2` and `_s3` variants;
- repeated Metal render-encoder creation;
- Metal command buffers completing successfully in sampled entries;
- one telemetry sample of approximately 54 FPS, 199 CPU, 2669 MB app memory, 5523 MB available memory, 50 threads, one reported controller, 225 loops and nominal thermal state.

These are single-run telemetry observations, not a controlled benchmark. The memory sample does not indicate an obvious shortage at that specific moment. PAK files opening does not prove that every map, asset or object was successfully loaded and rendered.

## Run 6 — cleaner renderer configuration

After Runs 4/5, I created `Engine_clean.ini` to remove most of the experimental renderer overrides and let UE4 use its normal defaults, while retaining a small number of occlusion-related settings. I copied it into the installed app's data container. Run 6 was a runtime configuration deployment, not a new source-code build.

The revised AppKit runtime shim used in Run 6 had already been compiled, signed and installed before Run 4. I had revised `ShimSupportsFamily` after the Run 3 texture-view assertion: the shim stopped forcing Mac1, explicitly claimed Mac2 and forwarded other GPU-family queries to real Metal.

### Run 6 screenshots

I captured landscape screenshots at 2868 × 1320:
- The 19:34:52 capture showed the tunnel opening, visible sky and atmospheric effects, concrete structures, pipes, a valve wheel, branches and vines. The interior remained very dark compared with the exterior.
- The 19:35:48 live capture showed more of the tunnel corridor: ceiling pipework, hanging cables/conduits, a green/rust-colored pipe and the tunnel portal.
- The 19:36:08 and 19:36:26 captures showed textured pipework with rust, moss, metal bands and rivets. The environment was more recognizable than in Runs 4/5.

The scene improved materially: I was no longer seeing only isolated pipes against an entirely black background. However, I could not clearly identify the cat in the captured image descriptions, and the captures alone do not prove that the character moved correctly through the level.

### Input and performance observations

The VGC polling log reported one controller and recorded non-zero left/right stick axes during my input, for example `L=(0.61,0.47)` and `R=(-0.14,-0.28)`. The same sampled entries showed `buttonsMask=0x0000`. This confirms that analog axis values reached the shim polling path; it does not prove that Unreal applied them to character movement or camera control, and the sampled button mask does not show a pressed face/shoulder button.

Run 6 telemetry samples varied from roughly 38 to 56 FPS. Samples showed approximately 2.8 GB app memory, 5.3–5.4 GB available memory and a `fair` thermal state. These are short-run observations, not a controlled benchmark or proof of long-session stability.

### What I can conclude

- The revised GPU-family shim was compiled, signed and installed before Run 4. Runs 4–6 progressed into the level without the same UE4 pixel-format fatal error appearing in the supplied excerpts. This is consistent with a mitigation, but I have not demonstrated causality with a controlled A/B test.
- Run 6's cleaner renderer configuration coincided with a visibly more complete tunnel environment and visible sky/atmospheric detail.
- The tunnel interior remains unusually dark. I have not demonstrated a definitive lighting, exposure, depth or culling root cause.
- Analog stick values reached the shim polling layer, but I have not confirmed player movement or camera response inside Unreal.
- I have not clearly confirmed the cat in the latest screenshot descriptions; full gameplay remains unverified.
- The screenshots are landscape, but I have not deliberately validated the relationship between the physical display, UIKit bounds, Metal drawable and Unreal viewport.
- The Run 6 transcript ended while the logging task was still running, so I do not have a final long-session stability result from that run.

## Latest launch update — 6 November 2026

I have since successfully opened Stray directly from its iOS Home Screen icon. This supersedes the earlier launch issue described in some initial notes. It confirms that direct icon launch works in my current setup; it does not by itself prove long-session stability or complete gameplay.

## Next useful checks

1. Improve tunnel exposure/lighting without regressing the geometry now visible.
2. Capture a frame where the cat is clearly visible.
3. Match controller axis/button logs to visible movement, camera response and actions inside Unreal.
4. Validate landscape UIKit bounds, Metal drawable size and Unreal viewport dimensions.
5. Run a longer session and record frame time, memory, thermal state, audio and app lifecycle behavior.

See [KNOWN-ISSUES.md](KNOWN-ISSUES.md), [METAL-COMPATIBILITY.md](METAL-COMPATIBILITY.md) and [DISPLAY-AND-INPUT.md](DISPLAY-AND-INPUT.md).

## Runs 7–8 and Phase J follow-up — 5 November 2026

### Run 7 — 3D level and input polling

Run 7 captures showed a rainy courtyard and a more detailed tunnel/corridor with pipes, textured walls, rust/moss detail and interaction prompts. The level's static geometry was clearly present, but the cat's skeletal mesh was not clearly visible in the reviewed gameplay captures.

A short VGC polling sample changed from `buttonsMask=0x0000` to `buttonsMask=0x0001`. This is evidence that a button bit reached the shim polling path; it is not proof that Unreal performed the associated action. The screenshot HUD reported roughly 59 FPS, but that single sample does not establish sustained performance.

### Run 8 — GPU skin-cache configuration experiment

I created `Engine_run8.ini` with GPU skin-cache-related renderer settings and copied it into the installed app's data container as `Library/Preferences/Stray/MacNoEditor/Engine.ini`. I relaunched the existing app without a documented new source-code build.

The log showed Metal render-encoder creation and completed command buffers. A telemetry sample reported approximately 40 FPS, 3025 MB app memory, 5167 MB available memory and nominal thermal state. The screenshot showed static industrial geometry (including a prominent orange pipe, concrete structures, vegetation and fog), but did not clearly show the cat.

**Result:** the Run 8 configuration did not verify that the cat or other skeletal meshes had been restored.

### Skeletal-mesh investigation

I inspected the original PAK contents and found the cat mesh/material assets, relevant map references and GFur plugin metadata. I also inspected symbols and code paths associated with `USkeletalMeshComponent`, `FSkeletalMeshSceneProxy`, `UGFurComponent` and `FFurSceneProxy`.

The evidence narrows the problem to the skeletal/dynamic-mesh rendering path while static geometry renders. GPU skinning configuration, masked/subsurface material behavior and GFur are candidates for controlled tests. I have not isolated a definitive cause or implemented a verified rendering fix.

### Phase J status

- Metal continues rendering a live 3D level on the iPhone.
- Cat visibility remains unverified; the first Phase J1 screenshot was initially read as showing the cat/backpack, but later captures did not corroborate that reading.
- Controller HUD visibility and a single button-mask transition are not proof of working gameplay controls.
- The transcript ends during the Run 8 investigation with a task still running and an Antigravity out-of-credits indicator. There is no final end-to-end gameplay result in this log.


## Run 9 — Early Z, stencil dithering and subsurface test

I created `Engine_run9.ini` to test a combined renderer configuration: `r.EarlyZPass=1`, stencil-for-LOD-dither changes, subsurface scattering quality and GPU skin-cache-related settings. I copied the file into the app data container and relaunched the existing installed build. No new source-code build is recorded for this run.

The log showed Metal render encoders and completed command buffers. One short telemetry sample reported about 62 FPS, 1426 MB app memory, 6766 MB available memory, one controller and nominal thermal state. This is not a sustained benchmark.

I saved a landscape screenshot at 2868 × 1320 using `devicectl`. The later macOS `screencapture` attempt failed with “could not create image from display.” I tried converting the saved image to BMP and inspecting it with a simple pixel/ASCII script, but the transcript ends before a reliable diagnosis or a controlled visual comparison is recorded.

## Manual gameplay and current rendering state — 6 November 2026

I manually confirmed that the gameplay controls work: I can run, jump, meow and trigger other actions, and continue progressing through the game's sequence even though the cat is not visible in the rendered image. Input/gameplay response is therefore not the current blocker. I should preserve the existing control implementation unless a reproducible input regression appears.

The remaining problem is visual completeness. The cat mesh is absent from the image, a substantial amount of scene content is missing or incorrectly rendered, and lighting/exposure problems remain obvious. Rendering has improved incrementally between runs, but the scene is still visually poor compared with the intended game.

The Run 9 configuration did not produce a documented, verified fix before the transcript snapshot. Antigravity's final state in the supplied record shows the Run 9 launch/log command still running and an “out of credits” indicator. The next work should focus on isolating the missing mesh/asset rendering and lighting defects, not re-testing controls that already work.
