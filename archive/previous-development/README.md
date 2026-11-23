# Archived Documentation — Previous Development Phase

> **Context:** This directory contains documentation, research notes, and exploratory logs created during earlier project iterations prior to November 23, 2026.

## Why These Documents Are Archived

During early development passes, exploratory runs and telemetry logs generated hypotheses and preliminary observations regarding in-game rendering, gameplay controls, and performance metrics (e.g., Runs 4–17 and Phase J). 

Subsequent rigorous technical auditing, forensic disassembly, and controlled device testing on physical hardware established that:
1. The original Unreal Engine 4 runtime had not yet completed early initialization (`GDynamicRHI == 0x0`, `GIsRequestingExit == 1`).
2. Earlier interpretations of scene rendering, cat visibility, or in-game controls were unverified or represented non-reproducible artifacts rather than a functioning game render.
3. To maintain engineering integrity and provide clear public tracking, the project established a **clean technical baseline**.

These historical records are preserved here to maintain a complete and transparent development history, while separating previous exploratory hypotheses from current, evidence-verified milestones.

## Archived Files

| File | Description | Reason for Archival |
|---|---|---|
| `MILESTONES.md` | Early project milestone log (Phases A–J, Runs 1–8). | Superseded by the new verified 9-stage `ROADMAP.md`. |
| `KNOWN-ISSUES.md` | Previous issue matrix referencing unverified 3D scenes. | Superseded by `PROJECT_STATUS.md` and current blockers. |
| `RENDERING-FOLLOW-UP.md` | Exploratory notes on Runs 4–9. | Visual rendering claims were not reproducible in controlled testing. |
| `DISPLAY-AND-INPUT.md` | Early display and DualShock 4 input observations. | Superseded by the current architecture documentation. |
| `GAMEPAD-AND-FIRST-LOAD.md` | Early menu-to-level navigation attempt notes. | Superseded by current initialization focus. |
| `REDDIT-DRAFT-EN.md` | Previous Reddit outreach draft (English). | Superseded; described unverified rendering state. |
| `REDDIT-DRAFT-ES.md` | Previous Reddit outreach draft (Spanish). | Superseded; described unverified rendering state. |

For current project status and active engineering goals, please refer to the root [README.md](../../README.md), [PROJECT_STATUS.md](../../PROJECT_STATUS.md), and [ROADMAP.md](../../ROADMAP.md).
