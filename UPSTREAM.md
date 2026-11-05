# Upstream project and attribution

This research depends on the compatibility infrastructure in [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public).

The upstream repository describes a method for running native Apple-silicon macOS applications on iPhone/iPad by converting bundle layout and Mach-O metadata, re-signing for the user's device, and supplying iOS shims for macOS-only frameworks.

This repository is a **Stray-specific research log**. It does not claim that the underlying conversion framework was created here.

## Attribution and license

The upstream repository publishes an MIT license with this copyright notice:

Copyright (c) 2026 Ross Fisher

Any redistribution of upstream code or substantial portions must preserve the upstream copyright and permission notice and comply with the complete upstream license. See the canonical [upstream LICENSE](https://github.com/zorrobyte/macos-on-ios-public/blob/main/LICENSE).

The upstream MIT license does not grant rights to Stray, its executable, game assets, Apple frameworks or any third-party material.

## Keep the boundary clear

- Cite upstream when describing the conversion framework.
- Identify Stray-specific experiments separately from inherited infrastructure.
- Do not copy upstream code into this repository until provenance and license headers are understood.
- Do not imply endorsement by the upstream maintainer.
