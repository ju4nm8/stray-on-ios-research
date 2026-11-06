# Publishing scope and safety checklist

I keep this repository as a public engineering notebook, not as a distribution channel for Stray.

## Material I never publish

- `Stray.app`, the Stray executable, IPA files or converted app bundles.
- Game PAK archives, extracted textures, meshes, audio, fonts, shaders, cinematics or other game assets.
- Apple signing certificates, private keys, provisioning profiles, entitlements containing sensitive capabilities or credentials.
- Device UDIDs, personal filesystem paths, app-container UUIDs, account identifiers or unredacted crash reports.
- Third-party source code unless its license and provenance permit redistribution.

## How I prepare logs

Before publishing logs, I redact `/Users/<name>` and personal volume paths, device/app-container UUIDs, signing identity emails, Team IDs, UDIDs, provisioning details, private file locations and unrelated personal data. I retain enough technical context to explain the issue without exposing identifiers.

## Screenshots and video

I use original captures only when they do not reveal personal notifications, account details or more copyrighted game content than is necessary to document the compatibility experiment. I describe exactly which screen or scene I reached. I do not distribute extracted game assets.

## Evidence-based claims

- I can document that I reached the brightness-calibration screen based on the Phase-G recording.
- I can document the observed 59–62 FPS overlay/log samples during part of that short run, but I do not present them as a benchmark.
- I can now document that I opened Stray directly from its iOS Home Screen icon.
- I do not currently claim that Stray is fully playable, stable over long sessions, a native iOS port or that every Mac game can run on iOS.

This is an unofficial independent experiment. I do not claim affiliation with or endorsement by the upstream maintainer, Apple, Annapurna Interactive or BlueTwelve Studio.