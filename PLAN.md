# Cineleaf implementation plan

The acceptance test for Milestone 1 is a real macOS workflow: create a project, import supported local media, arrange and trim clips, add text and audio, preview the composed timeline, save and reopen the `.cineleaf` package, and export a playable file with the expected dimensions, duration, video, and audio.

## Delivery order

1. Establish the repository, architecture, project format, privacy boundaries, and honest status reporting.
2. Add a reproducible XcodeGen project and a separately testable `CineleafCore` Swift package.
3. Implement rational-time project models, validation, editing commands, bounded undo, migration, atomic persistence, autosave, recent projects, and missing-media state.
4. Implement cancellable AVFoundation services for inspection, thumbnails, waveforms, composition, preview, and export.
5. Build the native SwiftUI/AppKit editor shell and connect every visible action to working behavior.
6. Add English and Spanish string catalogs, accessibility labels, flexible layouts, and a persisted in-app language override.
7. Add unit, integration, UI, localization, and performance test foundations plus release and DMG scripts.
8. Build and test on macOS CI, correct failures, publish the public repository, and only create `v0.1.0` when the complete acceptance test is proven.

## Verification gates

- `swift test --package-path Packages/CineleafCore`
- `xcodegen generate`
- `xcodebuild -project Cineleaf.xcodeproj -scheme Cineleaf -destination 'platform=macOS' build`
- `xcodebuild -project Cineleaf.xcodeproj -scheme Cineleaf -destination 'platform=macOS' test`
- Release configuration build and artifact inspection
- Manual import/edit/save/reopen/export pass on macOS
- Secret, license, localization, and tracked-file audits before every push

The current Windows host cannot run Swift, Xcode, AVFoundation, or a macOS GUI. macOS-only gates therefore run in GitHub Actions and must not be reported as local results.
