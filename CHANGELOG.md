# Changelog

All notable changes are recorded here. Cineleaf follows semantic versioning after the first public release.

## Unreleased

### Added

- Native macOS editor with English/Spanish interface, original branding, keyboard commands, accessibility labels, and a custom virtualized AppKit timeline.
- Versioned `.cineleaf` projects, safe v1→v2 migration, autosave/recovery, recents, missing-media relinking, atomic JSON save, and optional portable media consolidation.
- Multi-track editing, snapping, ripple/insert/overwrite, group/link, markers, property copy/paste, bounded undo/redo, speed, reverse, freeze frames, and keyframes.
- Text/image overlays, color adjustments, reusable looks, Core Image effects, clip-edge transitions, subtitles, voiceover, normalization, silence review/removal, and local beat markers.
- On-device-only automatic captions with no cloud fallback plus SRT/WebVTT import and export.
- Cancellable preview proxies, thumbnail/waveform/metadata/derivative caches, cache controls, source/composition reuse, and local diagnostics.
- H.264/HEVC MP4/MOV export with progress, cancellation, disk checks, output validation, saved presets, AAC audio, and 720p through 4K plans.
- Unit, integration, localization, UI, and performance tests; macOS CI; universal ad-hoc-signed app/ZIP/DMG/checksum tooling.

### Performance

- Added binary-search visible timeline indexing and validation fast paths.
- Streamed audio analysis and bounded frame-at-a-time reverse rendering avoid loading complete media into memory.
- Recorded the first non-fabricated macOS CI engine baseline in `Documentation/PERFORMANCE.md`.

### Release status

- Automated macOS builds, tests, synthetic export, and packaging pass.
- `0.1.0` remains unreleased until manual Mac workflow, profiling, installation, and screenshot gates pass.
