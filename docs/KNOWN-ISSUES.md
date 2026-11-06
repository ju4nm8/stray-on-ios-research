# Known issues and verification status

| Item | Current observation | Status |
|---|---|---|
| Direct icon launch | User reports immediate close from SpringBoard | Not diagnosed |
| Landscape presentation | Image/UI visibly stretched in earlier capture | Issue confirmed; root cause unknown |
| Portrait presentation | Latest recording is 1320 × 2868 portrait | Observed; correctness not assessed |
| UIKit touch input | Phase-G log contains touch-began entries | Receipt confirmed; gameplay mapping unverified |
| PS4 DualShock 4 | User reports successfully navigating beyond brightness calibration and through UI | Menu navigation reported working; gameplay actions not verified |
| 3D scene rendering | Runs 4/5 show selected textured pipes/structural geometry against a mostly black scene; cat, ground and surrounding walls are not clearly visible in the latest captures | Partial rendering confirmed; scene remains visually incorrect |
| Main menu | Latest recording shows Resume / Settings / Quit | Menu visible; exact game state not independently established |
| Gameplay | Latest Run 4/5 captures do not show a complete recognizable environment or clearly visible cat; gameplay actions remain unverified | Not verified |
| Performance | Earlier controller recording showed roughly 19–31 FPS; a Run 5 telemetry sample showed about 54 FPS | Short, non-comparable samples only; not benchmarked |
| Memory | Earlier controller recording showed app around 3.37–3.42 GB and 123–184 MB available; Run 5 sample showed about 2.67 GB app memory and 5.52 GB available | Varies by run; no memory-pressure diagnosis from these samples |
| Metal rendering/storage | Phase-G hooks translate observed Managed requests to Shared; Runs 4/5 show render encoders and completed command buffers | Rendering path active in sampled intervals; broader correctness unproven |
| Audio | No structured test recorded | Not tested |
| Long-session stability | Short recordings only | Not tested |
| Background/foreground | Earlier app transitioned to background and process ended with status 0; latest clip ends at Home Screen | No crash cause established |

Update this file only when new evidence exists. Include device/OS version, steps, redacted logs and whether a result is implemented, built, installed or verified on-device.

## Latest rendering experiment

Run 5 tested runtime `r.EarlyZPass=2` after copying the updated configuration to the installed app's data container. The level loaded to the same broad visual failure: only selected pipe/structural elements were apparent against a mostly black scene. The test did not establish Early Z as the root cause or eliminate it as a contributing factor. See [RENDERING-FOLLOW-UP.md](RENDERING-FOLLOW-UP.md).
