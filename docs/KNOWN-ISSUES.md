# Known issues and verification status

I update this matrix when I have new evidence from the physical iPhone. I keep successful launch, correct rendering, working controls and long-session stability as separate claims.

| Item | Current observation | Status |
|---|---|---|
| Direct icon launch | I successfully opened Stray directly from its iOS Home Screen icon on 6 November 2026. | **Confirmed working** in the current setup; long-session stability is a separate test. |
| Command-line launch | Earlier successful launches supplied the project path and `-basedir`. | Historical launch method; no longer the only working entry point. |
| Landscape presentation | Earlier captures showed stretched/compressed UI. Run 4–6 screenshots are landscape (2868 × 1320), but I have not completed a deliberate geometry/aspect-ratio verification. | Historical distortion observed; current correctness not fully verified. |
| Portrait presentation | An earlier controller recording was captured at 1320 × 2868. | Observed; not a current target-mode validation. |
| UIKit touch input | Phase-G logs contain touch-began entries. | Receipt confirmed; gameplay mapping not verified. |
| PS4 DualShock 4 | I navigated the menus with the controller. Run 6 recorded non-zero stick axes with sampled `buttonsMask=0x0000`; Run 7 briefly recorded `buttonsMask=0x0001`. | Menu navigation confirmed; the brief mask transition does not prove in-game movement, camera response or a working action. |
| 3D scene rendering | Run 6 captures show a recognizable tunnel with textured pipes, concrete structures, cables/conduits, vines, sky and atmospheric effects. The interior remains very dark. | Major visual improvement; lighting and complete scene correctness remain unresolved. |
| Cat / skeletal-mesh visibility | The first Phase J1 screenshot was initially interpreted as showing the cat/backpack, but later Phase J1 and Runs 7–8 captures did not corroborate it. Static environment geometry renders; the cat mesh is not clearly visible. | **Unresolved.** Current investigation points to the skeletal/dynamic-mesh path; GPU skinning, material/shading and GFur remain hypotheses. |
| Main menu | Earlier captures show Resume / Settings / Quit. | Menu reached in earlier tests. |
| Gameplay | I can reach a 3D level, but I have not yet demonstrated the visible cat moving and responding to camera/action controls through a complete gameplay segment. | Not yet verified. |
| Performance | Run 5 sampled about 54 FPS; Run 6 varied around 38–56 FPS; Phase J1 HUD showed about 42.85 FPS; Run 7 showed about 59 FPS; Run 8 sampled about 40 FPS. | Short, non-comparable samples only; not benchmarked and not evidence of stable 60 FPS. |
| Memory | Run 6 samples showed about 2.8 GB app memory and 5.3–5.4 GB available memory. Earlier tests differed. | Varies by run; no memory-pressure diagnosis from these samples. |
| Metal rendering/storage | Phase-G hooks translate observed Managed requests to Shared. The revised GPU-family hook was built/signed/installed before Run 4; Runs 4–6 progressed without the same texture-view fatal error in the supplied excerpts. | Rendering path active; the exact causal effect of the family hook is not proven by a controlled A/B test. |
| Audio | I have not completed a structured audio test. | Not tested. |
| Long-session stability | The available runs are short, and the Run 6 transcript ended while logging was still running. | Not tested. |
| Background/foreground | An earlier run ended after moving to the background; the latest icon-launch confirmation does not include a lifecycle test. | Not verified. |

## Configuration history

- Run 5 tested `r.EarlyZPass=2`; the visible scene remained mostly black.
- Run 6 used `Engine_clean.ini`, removing most experimental renderer overrides and restoring more of UE4's normal renderer defaults.
- Run 8 deployed `Engine_run8.ini` into the app data container with GPU skin-cache-related settings. Static level geometry continued rendering, but the cat was still not clearly visible; this did not verify a fix.
- The revised `ShimSupportsFamily` implementation was compiled, signed and installed before Run 4. Later logs do not show the same Run 3 texture-view fatal error, but I have not established causality with an A/B test.
- In the Phase J session, I re-signed and installed the existing app bundle. The transcript does not show a new source-code build of the game/shims during that pass.

## Next verification steps

1. Isolate the skeletal-mesh rendering failure and make the cat visible; test GFur separately rather than treating it as the proven cause.
2. Improve tunnel exposure/lighting while preserving the geometry now visible.
3. Record stick axes and button transitions alongside visible character/camera response and a known in-game action.
4. Validate UIKit bounds, `CAMetalLayer.drawableSize`, Unreal viewport and rotation in landscape.
5. Run a longer test and collect frame-time, memory, thermal, audio and lifecycle evidence.