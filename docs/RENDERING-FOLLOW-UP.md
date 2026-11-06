# Rendering follow-up — Runs 4 and 5

Date: 5 November 2026  
Target: iPhone 17 Pro Max, physical device  
Project: Stray macOS Apple-silicon build running through the macos-on-ios compatibility layer

## Run 4 — selective scene rendering

A physical-device screenshot was captured after entering the level (2868 × 1320). The visible scene contained textured pipework and related environmental structures against a largely black background. The cat, ground and surrounding walls were not clearly visible.

This establishes that some geometry and textured surfaces are being drawn. It does not establish that the whole map, its lighting, or the player character is rendering correctly.

## Run 5 — Early Z configuration experiment

The runtime configuration was changed to set:

```ini
r.EarlyZPass=2
```

The updated `Engine_fixed.ini` was copied to the installed app's data container, the running process was stopped, and the app was relaunched. Stray reached the level again, including an autosave notification. The following capture still showed only selected pipes/structural elements with a mostly black surrounding scene.

**Result:** this one configuration change did not visibly restore the missing environment. It is not enough evidence to conclude that Early Z is or is not the root cause.

## Log observations

The Run 5 log showed:

- successful opens for `pakchunk0-MacNoEditor.pak` and its `_s1`, `_s2`, and `_s3` variants;
- repeated Metal render-encoder creation;
- Metal command buffers completing successfully in sampled entries;
- one telemetry sample of approximately 54 FPS, 199 CPU, 2669 MB app memory, 5523 MB available memory, 50 threads, one reported controller, 225 loops, and nominal thermal state.

The FPS, memory and thermal figures are single-run telemetry samples, not a controlled benchmark. The memory sample does not indicate an obvious memory shortage at that specific moment. PAK files opening does not prove that every map, asset or object was successfully loaded and rendered.

## What is established

1. The app reaches the level after the menu.
2. The Metal command submission/presentation path remains active during the sampled interval.
3. Some textured environmental geometry is visible.
4. The scene is still incomplete: most of the surrounding world is black, and the cat is not clearly visible in these latest captures.
5. The Run 5 Early Z configuration change did not solve the visible failure.

## What remains unknown

No single root cause has been demonstrated. The remaining candidates include:

- depth prepass / depth-test behavior;
- lighting, skylight or exposure;
- view-frustum culling, distance culling or LOD;
- differences between static, skeletal and landscape meshes;
- material/shader permutations;
- texture or scene streaming;
- viewport/camera projection and render-target behavior.

These are hypotheses, not diagnoses. Avoid changing several renderer variables together: next tests should isolate one variable at a time and compare captures from the same scene state and camera.

## Source-code and deployment status

The Runs 4/5 work documented here changed a runtime configuration file and copied it into the installed app's data container. The available transcript does not show a source-code patch being compiled and installed during these two runs. Therefore this entry records a configuration experiment, not a new code fix.

No game executable, PAK archive, extracted asset, converted app bundle, signing material, device identifier, private filesystem path or raw device log is included in this repository.

## Next useful checks

1. Reproduce the same scene/camera with the previous Early Z value and with `r.EarlyZPass=2`, changing nothing else.
2. Confirm actual depth attachment formats, load/store actions and depth-test state for a known missing mesh draw.
3. Compare the rendering path for a visible pipe mesh with a missing opaque mesh and with a skeletal mesh.
4. Check whether the missing geometry is culled, submitted but fails depth, or submitted with a black/unlit material.
5. Capture a screenshot and matching log excerpt for each isolated test, then update [KNOWN-ISSUES.md](KNOWN-ISSUES.md).

## Run 6 — cleaner renderer configuration and improved scene visibility (5 November 2026)

Run 6 used the revised AppKit runtime shim that had been compiled, signed and installed before Run 4. The `ShimSupportsFamily` experiment was revised after Run 3's UE4 fatal texture-view assertion: the shim stopped forcing the Mac1 GPU-family claim and explicitly claims Mac2, while allowing the real Metal implementation to answer other family queries. Runs 4–6 then progressed into the level without the same fatal assertion appearing in the supplied excerpts. This is consistent with the change mitigating that specific failure, but the transcript does not show a controlled A/B test proving causality.

### Configuration change

Before Run 6, a new `Engine_clean.ini` was created and copied into the installed app's data container. The intent was to remove most of the earlier renderer overrides and let UE4 use its normal renderer defaults, while retaining a small number of occlusion-related settings. This followed Run 5, where explicitly setting `r.EarlyZPass=2` did not restore the missing environment.

This was a runtime configuration deployment, not a new source-code build in Run 6. The revised shim binary had been built, signed and installed in the preceding Run 3 iteration.

### Device observations

Physical-device screenshots were captured at 2868 × 1320:
- Run 6 at 19:34:52 showed the tunnel opening, visible sky and atmospheric effects, concrete structure, pipes, a valve wheel, branches and vines. The interior remained very dark compared with the exterior.
- A later live capture at 19:35:48 showed more of the tunnel corridor: ceiling pipework, hanging cables/conduits, a green/rust-colored pipe and the tunnel portal.
- Captures at 19:36:08 and 19:36:26 were described in the transcript as showing detailed textured pipework, rust, moss, metal bands and rivets. The surrounding environment was more recognizable than in Runs 4/5.

The scene has therefore improved materially: the evidence is no longer limited to isolated pipes against an entirely black background. However, the captured descriptions do not clearly identify the cat, and they do not by themselves prove that the character is moving correctly through the level.

### Input and performance observations

The VGC polling log reports one controller. It also records non-zero left- and right-stick axes during the user's input, for example values around `L=(0.61,0.47)` and `R=(-0.14,-0.28)`. In the same samples, `buttonsMask=0x0000` is reported. This confirms that analog axis values reached the shim's polling path; it does not prove that Unreal applied them to character movement or camera control, and the sampled button mask does not show a pressed face/shoulder button.

Telemetry samples during Run 6 varied from roughly 38 to 56 FPS. Samples show approximately 2.8 GB app memory, 5.3–5.4 GB available memory and a `fair` thermal state. These are short-run observations, not a controlled benchmark or evidence of long-session stability.

### Current interpretation

- The revised GPU-family shim was compiled, signed and installed before Run 4; Runs 4–6 then proceeded into the level without the same UE4 pixel-format fatal error appearing in the provided log excerpts.
- Run 6's cleaner renderer configuration coincided with a visibly more complete tunnel environment and restored visible sky/atmospheric detail.
- The interior remains unusually dark. No definitive lighting, exposure, depth or culling root cause has been demonstrated.
- Analog stick values are observed at the shim polling layer, but actual player movement and camera response are not independently verified.
- The cat is not clearly confirmed in the latest screenshot descriptions; therefore full gameplay remains unverified.
- Landscape screenshot capture is present, but the correct relationship between the physical display, UIKit bounds, Metal drawable and Unreal viewport still needs a deliberate test.
- At the end of the supplied transcript, the Run 6 logging task was still marked running; there is no final long-session exit/stability result.

See [KNOWN-ISSUES.md](KNOWN-ISSUES.md), [METAL-COMPATIBILITY.md](METAL-COMPATIBILITY.md), and [RENDERING-FOLLOW-UP.md](RENDERING-FOLLOW-UP.md).