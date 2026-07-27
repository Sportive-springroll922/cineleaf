# Architecture

## Boundaries

`CineleafCore` owns value models, exact timeline arithmetic, validation, editing commands, bounded history, project-format migration, and persistence primitives. It imports Foundation and CoreMedia where exact media interoperation is required, but never SwiftUI.

The `Cineleaf` application owns macOS presentation and Apple media frameworks. Its subsystems are deliberately narrow:

- `App`: application lifecycle, command routing, shared editor state, recent projects, recovery, and language state.
- `Services`: security-scoped media access, metadata, thumbnails, waveforms, cache, composition, playback, export, and local diagnostics.
- `UI`: editor layout, media library, timeline, preview, inspectors, export, settings, and accessible native controls.

Protocols isolate media inspection, thumbnails, waveforms, composition, playback, and export so deterministic fakes can exercise UI and state without decoding media.

## Concurrency

UI state is `@MainActor`. File and media work lives in actors and asynchronous services. Operations accept or observe cancellation, cache only bounded derived data, and identify results by request/project revision before committing them to UI state. Transient drag state is separate from committed project snapshots.

No source video is read into memory in full. AVFoundation streams samples. Thumbnail and waveform requests are bounded, deduplicated, and cancel stale work. Composition changes are coalesced at edit-commit boundaries rather than pointer-move frequency.

## Editing model

Frame-sensitive time is represented by a normalized rational value and converts losslessly to `CMTime` when the denominator fits CoreMedia. Every mutation is validated before commit. A bounded snapshot history provides undo and redo for destructive edits; transient playback and selection are not part of project history.

Tracks own clips. Overlap is permitted on distinct video tracks but rejected within a track unless an editing operation explicitly resolves it. Locked tracks reject mutations. Clip duration must remain positive, source time cannot be negative, and timeline time cannot be negative.

## Rendering

The composition builder maps enabled timeline clips into `AVMutableComposition`, creates video instructions for transforms/opacity/fades, creates audio ramps, and overlays text through Core Animation. Preview and export consume the same render plan so they cannot quietly diverge. Preview may use lower-resolution derived media; export always uses source media.

## Diagnostics and privacy

Local signposts cover project open/save, import, thumbnails, waveforms, composition rebuild, seeking, playback startup, autosave, proxy work, and export. Diagnostics remain on-device and contain no source content, account identifiers, or remote endpoint. Cineleaf has no telemetry or network service.
