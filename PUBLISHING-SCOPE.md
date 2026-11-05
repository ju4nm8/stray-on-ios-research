# Publishing scope and safety checklist

This repository is a public engineering notebook, not a distribution channel for the game.

## Never publish

- Stray.app, the Stray executable, IPA files, or converted app bundles.
- Game PAK archives, extracted textures, meshes, audio, fonts, shaders, cinematics, or other game assets.
- Apple signing certificates, private keys, provisioning profiles, entitlements containing sensitive capabilities, or credentials.
- Device UDIDs, personal filesystem paths, container UUIDs, account identifiers, or unredacted crash reports.
- Third-party source code unless its license and provenance permit redistribution.

## Before publishing logs

Redact `/Users/<name>` and personal volume paths, device/app-container UUIDs, signing identity emails, Team IDs, UDIDs, provisioning details, private file locations and unrelated personal data. Keep enough technical context to explain the issue without exposing identifiers.

## Screenshots and video

Use original captures only when they do not reveal personal notifications, account details, or copyrighted content beyond what is necessary to document the compatibility experiment. Explain exactly which screen was reached. Do not distribute extracted game assets.

## Evidence-based claims

- “Reaches the brightness-calibration screen” is supported by the phase-G recording.
- “Approximately 59–62 FPS during part of the run” is an observed overlay/log result, not a benchmark.
- “Playable”, “fully working”, “stable”, “native iOS port”, and “runs every Mac game” are not currently supported.

This is an unofficial independent experiment and is not affiliated with or endorsed by the upstream maintainer, Apple, Annapurna Interactive or BlueTwelve Studio.
