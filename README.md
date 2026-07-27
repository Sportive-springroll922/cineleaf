<p align="center">
  <img src="Branding/Exports/cineleaf-logo-horizontal.svg" alt="Cineleaf" width="460">
</p>

<p align="center">
  <strong>Fast, private video editing made for Mac.</strong><br>
  Free forever. No account, cloud, ads, subscription, watermark, or tracking.
</p>

<p align="center">
  <a href="https://github.com/luucabg/cineleaf/actions/workflows/ci.yml"><img alt="Build status" src="https://github.com/luucabg/cineleaf/actions/workflows/ci.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-327C60.svg"></a>
  <img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-142E28.svg">
</p>

![Cineleaf — Free, native video editing for macOS](Branding/Exports/github-social-preview.png)

## Cineleaf in plain language

Cineleaf is a video editor for people who want to make a good video without an account, a subscription, or a complicated professional suite. Drop in your videos, photos, and music; cut and arrange them; add text, effects, transitions, or subtitles; then export a clean video.

Everything happens on your Mac. Your footage is never sent to a Cineleaf server because there is no Cineleaf server.

> **Español:** Cineleaf es un editor de vídeo gratuito, privado y nativo para Mac. Permite cortar, ordenar, añadir texto, efectos, audio y subtítulos automáticos sin subir tus archivos, sin cuenta y sin marca de agua. La interfaz está disponible en español e inglés.

> **Current status:** the source is public pre-release software. Automated macOS builds, tests, real synthetic exports, and universal packaging pass. There is no public download yet because the final hands-on review on a real Mac has not been completed. See [STATUS.md](STATUS.md).

## Super optimized for speed

Cineleaf is built to feel exceptionally quick. It is a real native Mac app, not a website inside a desktop window.

- The timeline draws only the part you can see, so a long project does not create thousands of heavy screen controls.
- Difficult 4K footage can use a small, fast preview copy. Final export always goes back to the original file.
- Thumbnails, waveforms, speech recognition, audio analysis, proxies, saving, and export run in the background.
- Old preview work is cancelled when a newer edit makes it unnecessary.
- Repeated media information and preview results are reused instead of read again.
- Memory and disk caches have hard limits, remove old entries, show their size, and can be cleared safely in Settings.
- Audio and video are streamed in chunks; Cineleaf does not load an entire movie into memory.
- Exact frame time prevents the small timing drift common in decimal-second editing.

Measured on the automated macOS runner, a visible-range lookup in a synthetic 10,000-clip timeline took about **0.04 ms after warm-up**; validation of a one-hour, 100-clip/10-track project took about **0.4 ms**; and serializing a 100-asset project took about **1.4 ms**. These are narrow engine measurements, not a claim that every edit or every Mac has the same speed. Full details are in [Documentation/PERFORMANCE.md](Documentation/PERFORMANCE.md).

## What works in the current source

### Everyday editing

- Landscape, vertical, square, and portrait projects at 24, 25, 30, 50, or 60 fps.
- Local video, audio, and image import with useful details, thumbnails, and audio waveforms.
- Multiple video and audio tracks with move, trim, split, duplicate, delete, ripple delete, snapping, mute, lock, group, link, insert, overwrite, markers, and undo/redo.
- A fast native timeline with horizontal scrolling, smooth zoom, visible markers, and familiar keyboard shortcuts.
- Composed preview with gaps, transforms, crop, fit/fill, opacity, text, image overlays, fades, and audio mixing.

### Creative tools

- Speed from 0.25× to 4×, reverse playback, and real freeze frames.
- Position, scale, rotation, opacity, and volume keyframes with smooth interpolation.
- Exposure, contrast, saturation, temperature, tint, highlights, shadows, sharpen, and vignette controls.
- Blur, sharpen, vignette, monochrome, sepia, and bloom effects, plus reusable quick looks.
- Entrance and exit transitions: dissolve-style fade, fade through black, slide, wipe, and blur with duration controls.
- Copy and paste clip properties and effects across selections.
- Styled text using fonts already installed on the Mac, with stroke, shadow, background, alignment, fade, and slide animation.

### Smart tools that stay private

- **Automatic subtitles on the Mac.** Cineleaf requires Apple’s on-device speech recognition and never falls back to a cloud service.
- Editable subtitle clips plus SRT and WebVTT import/export.
- Silence detection with a review window before Cineleaf removes anything; the result can be undone.
- Local beat detection that places timeline markers for cutting to music.
- Voiceover recording, safe audio normalization, and detachable video audio.

### Faster projects and export

- Lightweight 540p preview proxies with real progress; originals remain untouched and are always used for export.
- A command that collects source media inside the `.cineleaf` project so it remains linked when the project is moved.
- Saved personal export settings.
- H.264 or HEVC export as MP4 or MOV at 720p, 1080p, 1440p, or 4K, with AAC audio, progress, cancellation, disk-space checks, and output verification.
- Autosave, interrupted-session recovery, missing-file detection, relinking, recent projects, and portable versioned project files.
- English and Spanish interface with an in-app language selector.

## Honest current limitations

- The app still needs a person to complete and record the full hands-on workflow, visual review, performance profiling, and unsigned installation test on real Mac hardware.
- Automatic subtitles are disabled when the selected language or Mac does not support Apple’s on-device recognition.
- Current transitions are clip-edge entrance/exit effects. A handle-based transition editor between two adjacent clips is not yet available.
- Noise reduction, chroma key, masks, motion tracking, background removal, nested timelines, LUTs, and color scopes remain future work.
- Intel is compiled and packaged in CI, but has not been exercised on a physical Intel Mac.
- Real application screenshots are intentionally absent until they can be captured from the running app without fabrication or private data.

## Mac requirements

- macOS 14 Sonoma or later.
- Apple Silicon or Intel Mac; the CI release build contains both architectures.
- To build it: Xcode 16.4 (Apple Swift 6.1.2) and XcodeGen 2.42 or later.

## Build it yourself

This section is for developers. Regular users should wait for the first manually verified download.

```bash
brew install xcodegen
git clone https://github.com/luucabg/cineleaf.git
cd cineleaf
xcodegen generate
xcodebuild -project Cineleaf.xcodeproj -scheme Cineleaf -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

Run every automated test:

```bash
swift test --package-path Packages/CineleafCore
xcodebuild -project Cineleaf.xcodeproj -scheme Cineleaf -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

Create an ad-hoc-signed universal app, ZIP, DMG, and SHA-256 checksums:

```bash
./scripts/build_release.sh
```

Files appear in `dist/`. They are not Apple-notarized.

## Installing an unsigned build

1. Drag `Cineleaf.app` into Applications.
2. In Finder, Control-click or right-click Cineleaf and choose **Open**.
3. Choose **Open** again in the warning.
4. If it remains blocked, open **System Settings → Privacy & Security** and choose **Open Anyway** for Cineleaf.

Never disable Gatekeeper or another Mac security feature.

## Privacy

Cineleaf contains no account system, network service, advertisements, analytics, telemetry, tracking, paid API, or watermark. Project files contain edit decisions and local media references. Clearing a cache never removes a project or its source videos. Read [PRIVACY.md](PRIVACY.md).

## Languages and translations

English is the base language and natural Spanish for Spain is included. Choose **Settings → General → Language** in the app.

Contributors can edit `Cineleaf/Resources/Localizable.xcstrings` in Xcode’s String Catalog editor. Every key needs matching English and Spanish entries. Run the localization tests before opening a pull request.

## Learn more or help

- [Current status](STATUS.md)
- [Roadmap](ROADMAP.md)
- [Contributing guide](CONTRIBUTING.md)
- [Architecture](Documentation/ARCHITECTURE.md)
- [Project format](Documentation/PROJECT_FORMAT.md)
- [Rendering pipeline](Documentation/RENDERING_PIPELINE.md)
- [Performance evidence](Documentation/PERFORMANCE.md)
- [Security policy](SECURITY.md)
- [Code of conduct](CODE_OF_CONDUCT.md)

Bug reports and focused contributions are welcome, including wording, translations, accessibility, documentation, testing, and performance work.

## License

Cineleaf uses the [MIT License](LICENSE). It has no third-party runtime dependency outside Apple’s system frameworks. Build-time tools and their licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
