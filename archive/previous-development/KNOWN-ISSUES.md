# Known issues and verification status

I update this matrix when I have new evidence from the physical iPhone. Launch, gameplay response, complete rendering and long-session stability are separate claims.

| Item | Current observation | Status |
|---|---|---|
| Direct icon launch | Stray opens from its iOS Home Screen icon on the iPhone 17 Pro Max. | **Confirmed working** in the current setup. |
| 3D level | The game reaches an in-game 3D level and renders parts of the environment. | **Partially working**; visual content is incomplete. |
| Gameplay actions | Manual testing confirms running, jumping, meowing and progressing through the sequence even with the cat mesh invisible. | **Confirmed in the tested sequence**; this does not mean all gameplay systems are verified. |
| Cat / skeletal mesh | The cat's gameplay actions respond, but its visual mesh is absent from reviewed captures. | **Unresolved.** Skeletal/dynamic-mesh rendering is a leading investigation area, not a proven root cause. |
| Environment geometry | Some static geometry renders, while other level elements are missing or incorrect. | **Partially working.** |
| Materials and textures | Textures/materials appear incomplete, missing or incorrect on portions of the scene. | **Unresolved.** |
| Lighting and exposure | Dark or uneven areas and incorrect lighting remain visible. | **Unresolved.** |
| Potential render causes | Skeletal scene-proxy creation, GPU skinning/skin cache, masked/subsurface materials, stencil/LOD dithering, Early Z, GFur, Metal format/feature support, resource streaming and visibility/culling are under consideration. | **Hypotheses only; no single cause confirmed.** |
| Metal rendering/storage | Metal rendering remains active. The revised GPU-family shim preceded later runs without the same texture-view fatal error in supplied excerpts. | **Observed mitigation candidate**; no controlled A/B proof. |
| Landscape presentation | Captures exist in landscape, but UIKit bounds, `CAMetalLayer.drawableSize` and Unreal viewport sizing have not been deliberately reconciled. | **Not fully verified.** |
| Performance | Runs 16 and 17 showed medians around 52 and 53 FPS over approximately 94 seconds. | **Short samples only**; no sustained benchmark or long-session frame-pacing result. |
| Audio | No structured end-to-end audio test has been completed. | Not tested. |
| Long-session stability | The recorded sessions are short. | Not tested. |
| Background/foreground | No complete lifecycle test has been documented. | Not verified. |

## Recent telemetry

- **Run 16:** median approximately 52 FPS, mean approximately 51.3 FPS, about 91.6% of samples at or above 40 FPS, roughly 94 seconds. Maximum app memory about 2.68 GB; minimum available memory about 5.51 GB; thermal state reported nominal.
- **Run 17:** median approximately 53 FPS, mean approximately 51.9 FPS, about 94.7% of samples at or above 40 FPS, roughly 94 seconds. Maximum app memory about 2.69 GB; minimum available memory about 5.50 GB; thermal state reported nominal.

These are supervisor/log samples from short test windows. They do not establish sustained performance or visual correctness. The screenshots from these runs still need direct visual review.

## Earlier configuration experiments

- Run 5 tested `r.EarlyZPass=2`; the scene remained mostly black.
- Run 6 used `Engine_clean.ini`, removing most experimental renderer overrides.
- Run 8 deployed `Engine_run8.ini` with GPU skin-cache-related settings. Static geometry rendered, but the cat was not visible.
- Run 9 deployed `Engine_run9.ini` with Early Z, stencil/LOD-dither, subsurface and skin-cache-related settings. The short FPS sample improved, but the available record did not show that the cat or missing assets were restored.
- The revised `ShimSupportsFamily` implementation was built, signed and installed before Run 4. Later logs did not show the same Run 3 texture-view fatal error in the supplied excerpts, but causality has not been established through an A/B test.

## Next verification steps

1. Isolate the skeletal-mesh rendering failure with controlled tests and make the cat visible.
2. Determine why other level geometry, materials and textures are missing or incorrect.
3. Investigate lighting, exposure, shadows and post-processing without regressing the geometry that already renders.
4. Verify UIKit bounds, `CAMetalLayer.drawableSize`, Unreal viewport and landscape rotation.
5. Review Run 16/17 screenshots and perform longer, thermally controlled tests for frame pacing, memory, audio and app lifecycle.
