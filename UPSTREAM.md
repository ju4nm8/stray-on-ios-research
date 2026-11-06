# Upstream project and attribution

My research depends on the compatibility infrastructure in [zorrobyte/macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public).

The upstream repository describes a method for running native Apple-silicon macOS applications on iPhone/iPad by converting bundle layout and Mach-O metadata, re-signing for the target device and supplying iOS shims for macOS-only frameworks.

This repository is my **Stray-specific research log**. I do not claim that I created the underlying conversion framework.

## Attribution and license

The upstream repository publishes an MIT license with this copyright notice:

Copyright (c) 2026 Ross Fisher

When I redistribute upstream code or substantial portions of it, I must preserve the upstream copyright and permission notice and comply with the complete upstream license. See the canonical [upstream LICENSE](https://github.com/zorrobyte/macos-on-ios-public/blob/main/LICENSE).

The upstream MIT license does not grant me rights to Stray, its executable, game assets, Apple frameworks or other third-party material.

## How I keep the project boundary clear

- I cite upstream when I describe the conversion framework.
- I identify Stray-specific experiments separately from inherited infrastructure.
- I do not copy upstream code into this repository unless I understand its provenance and license headers.
- I do not imply endorsement by the upstream maintainer.