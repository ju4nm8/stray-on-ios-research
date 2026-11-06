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
