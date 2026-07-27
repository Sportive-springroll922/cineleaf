# Third-party notices

## Application runtime

Cineleaf currently links only Apple system frameworks supplied with macOS: SwiftUI, AppKit, AVFoundation, AVKit, CoreMedia, CoreImage/ImageIO, CoreAnimation/QuartzCore, CoreGraphics, CoreText, AudioToolbox, UniformTypeIdentifiers, Combine, Foundation, and `os`. They are not redistributed by this repository.

`CineleafCore` has no third-party package dependency.

## Build and repository tooling

- **XcodeGen** — MIT License — used to generate the Xcode project; not shipped in Cineleaf.
- **Pillow** — HPND License — used by `scripts/generate_branding_assets.py`; not shipped in Cineleaf.
- **DejaVu Sans** — Bitstream Vera and Arev-derived permissive licenses — used when available to rasterize text in the repository social-preview image; no font file is redistributed.
- **GitHub Actions runner software** — used only in CI under its respective licenses.

The Cineleaf logo, icon, social preview, and UI source are original project assets released under the repository's MIT License.
