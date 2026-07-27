# Project status

## Current state

Cineleaf is under active development toward `0.1.0`. The automated macOS gate passes, but source code must still be treated as pre-release until the manual acceptance gates in `PLAN.md` pass.

## Verified on macOS CI

GitHub Actions run [30231490263](https://github.com/luucabg/cineleaf/actions/runs/30231490263) passed on 27 July 2026 using Xcode 16.4 build 16F6 and Apple Swift 6.1.2.

- 21 `CineleafCore` unit and performance-smoke tests passed.
- 7 application integration and localization tests passed.
- 2 critical UI flows passed, covering project creation and the Spanish interface.
- Synthetic video import, thumbnail generation, waveform generation, cancellation, composition, and MP4 export passed.
- The exported test file was programmatically verified as 1280 × 720 with video, audio, and the expected one-second duration.
- The app built successfully in Release configuration.

CI is automated evidence, not a substitute for a person reviewing playback, interaction quality, screenshots, installation, or a long real-world edit.

## Environment

The repository was bootstrapped on Windows 10 Pro (64-bit) with Git 2.54.0 and GitHub CLI 2.94.0. Swift, Xcode, XcodeGen, AVFoundation, Instruments, and a macOS GUI are not available on that host. No local macOS build, manual launch, visual inspection, or performance measurement can be claimed from this environment; macOS build and automated test evidence comes from GitHub Actions.

## Release gate

`v0.1.0` and binary release assets remain blocked until all of the following are true on macOS:

- The universal release packaging script produces and verifies the app, ZIP, DMG, and checksums.
- A person completes import, edit, text, audio, save, reopen, preview, and export.
- The exported file is independently inspected for duration, dimensions, and audio/video tracks.
- The unsigned app and DMG are opened on a clean test account.
- Performance and cancellation are inspected without obvious freezes or runaway work.

## Reporting rule

Roadmap items are not presented as working features. This file is updated from observed build/test/manual evidence, never from the presence of source code alone.
