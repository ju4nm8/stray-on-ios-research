# Known issues and verification status

| Item | Current observation | Status |
|---|---|---|
| Direct icon launch | User reports immediate close from SpringBoard | Not diagnosed |
| Landscape presentation | Image/UI visibly stretched in capture | Issue confirmed; root cause unknown |
| Touch input | UIKit touch-began entries appear in log | Receipt confirmed; gameplay input unverified |
| Physical controller | Statistics showed `controllers=0` | Not validated with a paired controller |
| Main menu | Not shown in supplied recording | Not confirmed |
| Gameplay | No playable session demonstrated | Not verified |
| Metal Managed storage | Phase-G hooks translate observed requests to Shared | Initial UI path passes; broader correctness unproven |
| Audio | No structured test recorded | Not tested |
| Long-session stability | Short run only | Not tested |
| Background/foreground | App transitioned to background and process ended with status 0 | Observed; lifecycle quality unestablished |

Update this file only when new evidence exists. Include device/OS version, steps, redacted logs and whether a result is implemented, built, installed or verified on-device.
