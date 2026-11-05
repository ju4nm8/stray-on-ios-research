# Known issues and verification status

| Item | Current observation | Status |
|---|---|---|
| Direct icon launch | User reports immediate close from SpringBoard | Not diagnosed |
| Landscape presentation | Image/UI visibly stretched in earlier capture | Issue confirmed; root cause unknown |
| Portrait presentation | Latest recording is 1320 × 2868 portrait | Observed; correctness not assessed |
| UIKit touch input | Phase-G log contains touch-began entries | Receipt confirmed; gameplay mapping unverified |
| PS4 DualShock 4 | User reports successfully navigating beyond brightness calibration and through UI | Menu navigation reported working; gameplay actions not verified |
| 3D scene rendering | Latest recording shows a blue/washed-out view with visible artifacts | Scene-load/render attempt reached; visual correctness failed |
| Main menu | Latest recording shows Resume / Settings / Quit | Menu visible; exact game state not independently established |
| Gameplay | No clearly recognizable playable scene or character control demonstrated | Not verified |
| Performance | Overlay shows roughly 19–31 FPS in the latest short capture | Observed only; not benchmarked |
| Memory | Overlay shows app around 3.37–3.42 GB and available memory around 123–184 MB | Potential memory-pressure risk; not diagnosed |
| Metal Managed storage | Phase-G hooks translate observed requests to Shared | Initial UI and later rendering path progress; broader correctness unproven |
| Audio | No structured test recorded | Not tested |
| Long-session stability | Short recordings only | Not tested |
| Background/foreground | Earlier app transitioned to background and process ended with status 0; latest clip ends at Home Screen | No crash cause established |

Update this file only when new evidence exists. Include device/OS version, steps, redacted logs and whether a result is implemented, built, installed or verified on-device.
