# Roadmap

## 0.1.0 — usable editor

- Project creation, canvas presets, frame-rate selection, save/open, autosave, recovery, and recent projects
- Local video, audio, and image import with metadata, thumbnails, and waveform data
- Multi-track timeline with selection, move, trim, split, delete, duplicate, snapping, mute, lock, enable, zoom, and scrolling
- Composed AVFoundation preview with play, pause, seek, gaps, transforms, opacity, fades, text, and audio mixing
- Transform, crop mode, video mute, audio level, and fade controls
- Text clips with system fonts, styling, positioning, and simple animation
- H.264/HEVC export to MOV or MP4 with AAC audio, progress, cancellation, and validation
- English and Spanish localization
- Unit, integration, localization, performance, and critical-flow UI tests
- Reproducible unsigned `.app`, `.zip`, `.dmg`, and SHA-256 output

The release is gated on a successful macOS build, automated tests, and a manual end-to-end export. It will not be tagged while those gates are unproven.

## 0.2.0 — everyday editing

Ripple/insert/overwrite edits, linked clips, groups, markers, speed changes, basic keyframes, transitions, color controls, subtitles, voiceover, normalization, proxies, media consolidation, and saved export presets.

## Later — advanced local tools

Chroma key, masks, Vision-powered tracking and segmentation, on-device captions, silence editing, beat markers, nested timelines, LUTs, scopes, metering, and an optional dependency-reviewed extension backend.
