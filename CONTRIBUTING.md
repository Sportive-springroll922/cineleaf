# Contributing to Cineleaf

Thank you for helping make private video editing more accessible.

## Before you start

- Check `STATUS.md` and `ROADMAP.md` so work matches the current milestone.
- For a larger change, open an issue first and describe the user problem.
- Do not add cloud services, tracking, advertisements, paid APIs, copyrighted sample media, or a dependency without a license review.
- Do not present an unfinished control as working.

## Development setup

Use macOS 14 or later, Xcode 16.4 (Apple Swift 6.1.2), and XcodeGen 2.42 or later.

```bash
brew install xcodegen
xcodegen generate
swift test --package-path Packages/CineleafCore
xcodebuild -project Cineleaf.xcodeproj -scheme Cineleaf -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

Keep editing logic in `CineleafCore` when it does not need AppKit, SwiftUI, or AVFoundation. Media work must remain asynchronous, cancellable where possible, and off the main actor. Use rational time for frame-sensitive values.

## Pull requests

Keep changes focused, add regression tests, run the real gates after the last edit, and update user-facing documentation honestly. Include English and natural Spanish translations for every visible string. Use generated, original, public-domain, or correctly licensed test media only.

By contributing, you agree that your contribution is provided under the MIT License and to follow the code of conduct.
