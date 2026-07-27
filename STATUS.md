# Project status

## Current state

Cineleaf is a feature-complete **pre-release source build** for the planned `0.1.0` workflow. It is public and usable for development, but it is not tagged or offered as a download until a person finishes the hands-on Mac checks below.

## Verified automatically on macOS

GitHub Actions run [30235389597](https://github.com/luucabg/cineleaf/actions/runs/30235389597) passed on 27 July 2026 with Xcode 16.4 build 16F6 and Apple Swift 6.1.2.

- 36 `CineleafCore` unit/performance tests passed.
- 14 application integration/localization tests passed.
- 2 critical UI flows passed for project creation and the Spanish interface.
- Synthetic video/audio tests exercised import, thumbnails, waveforms, streaming audio analysis, silence detection, beat detection, freeze-frame generation, reverse playback, effects, consolidation, composition, cancellation, and MP4 export.
- Export output was programmatically checked for expected dimensions, duration, video, and audio.
- Release packaging built an optimized, ad-hoc-signed universal `arm64`/`x86_64` app plus ZIP, DMG, and verified SHA-256 checksums.

The next CI run also covers saved export presets, reusable looks, safe multi-clip property paste, and total cache-size reporting. This file will point to that run once it passes.

## Working source features

- Project create/open/save, canvas and frame-rate presets, autosave, recovery, recents, missing media, relinking, and portable media consolidation.
- Asynchronous import, metadata, thumbnails, downsampled waveforms, bounded caches, clear-cache controls, and lightweight preview proxies.
- Multi-track move/trim/split/delete/duplicate/ripple/insert/overwrite, snapping, mute/lock/enable, groups, links, markers, visible-range indexing, and bounded undo/redo.
- Composed preview and verified export with transforms, crop, opacity, text/images, audio mix, fades, color, Core Image effects, keyframes, speed, reverse, freeze frames, and clip-edge transitions.
- On-device-only automatic captions, SRT/WebVTT import/export, voiceover, normalization, silence review/removal, and beat markers.
- English/Spanish UI, keyboard commands, local diagnostics, original branding, public documentation, and reproducible packaging.

## Measured performance

Run [30235037360](https://github.com/luucabg/cineleaf/actions/runs/30235037360) measured the editing engine on the `macos-15` CI class. Warm visible-range queries over 10,000 clips were about 0.04 ms, a one-hour 100-clip/10-track validation about 0.4 ms, and 100-asset serialization about 1.4 ms. See [Documentation/PERFORMANCE.md](Documentation/PERFORMANCE.md) for raw ranges, environment gaps, and limitations.

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

## Reporting rule

Source presence is not treated as a shipped public release. Automated evidence, manual evidence, and untested limitations remain visibly separate.
