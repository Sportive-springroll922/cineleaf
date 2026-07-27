# Project status

## Current state

Cineleaf is under active development toward `0.1.0`. Source code in the repository must be treated as pre-release until the macOS CI and manual acceptance gates in `PLAN.md` pass.

## Environment

The repository was bootstrapped on Windows 10 Pro (64-bit) with Git 2.54.0 and GitHub CLI 2.94.0. Swift, Xcode, XcodeGen, AVFoundation, Instruments, and a macOS GUI are not available on that host. No local macOS build, launch, export, visual inspection, or performance measurement can be claimed from this environment.

## Release gate

`v0.1.0` and binary release assets remain blocked until all of the following are true on macOS:

- The generated Xcode project builds in Debug and Release.
- Unit, integration, localization, performance-smoke, and UI tests pass.
- A person completes import, edit, text, audio, save, reopen, preview, and export.
- The exported file is independently inspected for duration, dimensions, and audio/video tracks.
- The unsigned app and DMG are opened on a clean test account.
- Performance and cancellation are inspected without obvious freezes or runaway work.

## Reporting rule

Roadmap items are not presented as working features. This file is updated from observed build/test/manual evidence, never from the presence of source code alone.
