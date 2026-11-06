# Known issues and verification status

| Item | Current observation | Status |
|---|---|---|
| Direct icon launch | User reports immediate close from SpringBoard | Not diagnosed |
| Landscape presentation | Image/UI visibly stretched in earlier capture | Issue confirmed; root cause unknown |
| Portrait presentation | Latest recording is 1320 × 2868 portrait | Observed; correctness not assessed |
| UIKit touch input | Phase-G log contains touch-began entries | Receipt confirmed; gameplay mapping unverified |
| PS4 DualShock 4 | One controller reported; Run 6 VGC logs show non-zero left/right stick axes, but sampled `buttonsMask` is `0x0000` | Menu navigation reported working; axis values reach polling, in-game movement/camera response and button actions not verified |
| 3D scene rendering | Run 6 captures show a more recognizable tunnel: textured pipes, concrete structure, cables/conduits, vines, sky and atmospheric effects; tunnel interior remains very dark and cat is not clearly identified | Material visual improvement; lighting and complete scene correctness still unresolved |
| Main menu | Latest recording shows Resume / Settings / Quit | Menu visible; exact game state not independently established |
| Gameplay | Run 6 shows a recognizable tunnel environment and non-zero controller stick axes at the shim; cat visibility and actual movement/action response are not demonstrated | Not verified |
| Performance | Earlier controller recording showed roughly 19–31 FPS; Run 5 sampled about 54 FPS; Run 6 samples varied around 38–56 FPS | Short, non-comparable samples only; not benchmarked |
| Memory | Earlier controller capture showed app around 3.37–3.42 GB and 123–184 MB available; Run 5 about 2.67 GB / 5.52 GB available; Run 6 about 2.8 GB / 5.3–5.4 GB available | Varies by run; no memory-pressure diagnosis from these samples |
| Metal rendering/storage | Phase-G hooks translate observed Managed requests to Shared; revised GPU-family hook was built/signed/installed before Run 4; later Runs 4–6 progress without the same texture-view fatal in the supplied excerpts | Rendering path active; hook is a plausible mitigation, but no controlled A/B proof |
| Audio | No structured test recorded | Not tested |
| Long-session stability | Short recordings only | Not tested |
| Background/foreground | Earlier app transitioned to background and process ended with status 0; latest clip ends at Home Screen | No crash cause established |

Update this file only when new evidence exists. Include device/OS version, steps, redacted logs and whether a result is implemented, built, installed or verified on-device.

## Latest rendering experiment

Run 5 tested runtime `r.EarlyZPass=2` after copying the updated configuration to the installed app's data container. The level loaded to the same broad visual failure: only selected pipe/structural elements were apparent against a mostly black scene. The test did not establish Early Z as the root cause or eliminate it as a contributing factor. See [RENDERING-FOLLOW-UP.md](RENDERING-FOLLOW-UP.md).

## Run 6 update

Run 6 deployed a cleaner `Engine_clean.ini` configuration intended to remove most experimental renderer overrides and restore UE4 defaults. Captures show a substantially more recognizable tunnel environment, with the interior still very dark. VGC logs show non-zero analog stick axes but a zero sampled button mask; input effect on character/camera is not proven. FPS samples ranged around 38–56 with a `fair` thermal state. See [RENDERING-FOLLOW-UP.md](RENDERING-FOLLOW-UP.md).

The revised GPU-family shim was compiled, signed and installed before Run 4. The Run 3 texture-view fatal error does not recur in the excerpts for Runs 4–6, but causality is not proven by an isolated test.
