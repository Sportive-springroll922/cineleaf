# Project status

## Current state

Cineleaf is a feature-complete **pre-release source build** for the planned `0.1.0` workflow. It is public and usable for development, but it is not tagged or offered as a download until a person finishes the hands-on Mac checks below.

## Verified automatically on macOS

GitHub Actions run [30235867829](https://github.com/luucabg/cineleaf/actions/runs/30235867829) passed on 27 July 2026 with Xcode 16.4 build 16F6 and Apple Swift 6.1.2.

- 39 `CineleafCore` unit/performance tests passed.
- 15 application integration/localization tests passed.
- 2 critical UI flows passed for project creation and the Spanish interface.
- Synthetic video/audio tests exercised import, thumbnails, waveforms, streaming audio analysis, silence detection, beat detection, freeze-frame generation, reverse playback, effects, consolidation, composition, cancellation, and MP4 export.
- Export output was programmatically checked for expected dimensions, duration, video, and audio.
- Release packaging built an optimized, ad-hoc-signed universal `arm64`/`x86_64` app plus ZIP, DMG, and verified SHA-256 checksums.
- The same run covered saved export presets, reusable looks, safe multi-clip property paste, total cache-size reporting, and large-project edit/save-reopen performance cases.

## Working source features

- Project create/open/save, canvas and frame-rate presets, autosave, recovery, recents, missing media, relinking, and portable media consolidation.
- Asynchronous import, metadata, thumbnails, downsampled waveforms, bounded caches, clear-cache controls, and lightweight preview proxies.
- Multi-track move/trim/split/delete/duplicate/ripple/insert/overwrite, snapping, mute/lock/enable, groups, links, markers, visible-range indexing, and bounded undo/redo.
- Composed preview and verified export with transforms, crop, opacity, text/images, audio mix, fades, color, Core Image effects, keyframes, speed, reverse, freeze frames, and clip-edge transitions.
- On-device-only automatic captions, SRT/WebVTT import/export, voiceover, normalization, silence review/removal, and beat markers.
- English/Spanish UI, keyboard commands, local diagnostics, original branding, public documentation, and reproducible packaging.

## Measured performance

Run [30235867829](https://github.com/luucabg/cineleaf/actions/runs/30235867829) measured the editing engine on the `macos-15` CI class. Settled visible-range queries over 10,000 clips reached about 0.04 ms, a one-hour 100-clip/10-track validation about 0.4 ms, a move/trim/split sequence about 1.7 ms, and JSON encode/decode of that large project about 12–19 ms. See [Documentation/PERFORMANCE.md](Documentation/PERFORMANCE.md) for raw ranges, environment gaps, and limitations.

## Environment limitation

The active workstation is Windows 10 Pro and cannot run Xcode, AVFoundation, Instruments, or a macOS GUI. CI proves compilation and automated behavior; it cannot prove subjective visual quality, real-time playback smoothness, microphone experience, Gatekeeper flow, or prolonged use on a physical Mac.

## Release gate still open

Do not create `v0.1.0` until a person on macOS has:

- completed import, edit, text, effects, audio, subtitles, save, reopen, preview, and export;
- watched and independently inspected the exported file;
- tested proxy/original quality separation, cancellation, voiceover permission, and on-device caption availability;
- opened the unsigned app and DMG on a clean test account;
- profiled a large project for hangs, leaks, memory growth, file activity, and energy use;
- captured real English/Spanish screenshots with non-private licensed or generated media.

The exact next action on a Mac is:

```bash
git clone https://github.com/luucabg/cineleaf.git
cd cineleaf
brew install xcodegen
xcodegen generate
open Cineleaf.xcodeproj
```

Run the workflow above from Xcode, then run `./scripts/build_release.sh` and install the resulting `dist/Cineleaf-0.1.0-macOS.dmg` on a clean test account. Record the Mac model, processor, memory, macOS version, results, and screenshots before creating `v0.1.0`.

## Reporting rule

Source presence is not treated as a shipped public release. Automated evidence, manual evidence, and untested limitations remain visibly separate.
