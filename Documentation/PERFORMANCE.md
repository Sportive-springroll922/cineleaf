# Performance

## Measurement status

No macOS measurements have been recorded. The bootstrap host is Windows 10 Pro, where Xcode, AVFoundation, Instruments, and the Cineleaf app cannot run. Invented numbers are intentionally omitted.

## Required baseline environment

Before `0.1.0`, record the Mac model, processor, memory, macOS version, exact Xcode version, build configuration, and thermal/power state. Exercise a generated project of at least one hour with at least 100 mixed clips across 10 tracks.

## Repeatable cases

- Project open and save/reopen
- Timeline initial load, scroll, zoom, move, trim, and split
- Thumbnail and waveform cold/warm cache
- Affected-section composition rebuild
- Playback startup and rapid seeking
- Synthetic media export and cancellation

Capture wall time, main-thread stalls, peak resident memory, file activity, and energy impact. Use XCTest metrics plus Time Profiler, Allocations, Leaks, SwiftUI redraw inspection, File Activity, and Energy Log. Record observed bottlenecks and the exact revision with each result.

## Design budgets

Interactive state changes target roughly 100 ms or less. Timeline drawing virtualizes the visible region with a small preload margin, waveforms use downsampled peaks, thumbnails match display density, caches are bounded, and media/background tasks are cancellable. These are engineering targets, not measured claims.

