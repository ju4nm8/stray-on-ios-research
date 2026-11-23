# Publishing Scope & Safety Checklist

This repository serves as a public research notebook and engineering log documenting compatibility research. It is **not** a distribution channel for game files, compiled bundles, or proprietary software.

---

## Strict Non-Distribution Policy

The following materials are **never** committed or published to this repository:

1. **Proprietary Game Assets & Binaries:**
   - The original `Stray.app` bundle, executable `Stray-Mac-Shipping`, or converted application bundles.
   - Unreal Engine PAK archives (`pakchunk*.pak`), extracted textures, meshes, animations, audio files, cinematics (Bink 2 `.bk2`), or level geometry.
2. **Security Credentials & Code Signing Material:**
   - Apple Developer certificates, private keys, provisioning profiles, or sensitive entitlements.
3. **Private Identifiers & Personal Data:**
   - Physical device UDIDs, Apple Account emails, Personal Team IDs, local Mac user paths (`/Users/<username>/...`), or container UUIDs.
4. **Third-Party Code:**
   - Proprietary Unreal Engine source code or unlicensed third-party code.

---

## Evidence-Based Claims Policy

To maintain scientific and technical credibility:
- **No speculative success:** We do not claim a feature works based on compilation success or indirect hints.
- **On-device verification:** All reported milestones must be backed by concrete physical device logs captured under the test harness.
- **Clear stage delineation:** Launching the process, completing engine initialization, rendering graphics, and running gameplay are distinct technical stages. Passing one does not imply the others.
- **Historical transparency:** Earlier unverified hypotheses and exploratory notes are archived in `archive/previous-development/` rather than deleted or rewritten.

This is an unofficial, independent research experiment. It is not affiliated with, sponsored by, or endorsed by Annapurna Interactive, BlueTwelve Studio, Epic Games, Apple, or the upstream maintainer.
