# Cineleaf branding

The identity combines an editing frame, an organic leaf, and a visible cut. It is original project artwork built from simple vector geometry. It uses no SF Symbol, stock image, external logo, or generated raster as its source.

`Sources/cineleaf-icon.svg` and `Sources/cineleaf-wordmark.svg` are the editable masters. `Exports/` contains web-ready SVG and PNG output. The Xcode asset catalog is generated from the same numeric geometry, so every icon size remains consistent.

## Regenerate assets

Python 3.10 or later and Pillow 10 or later are required only for asset generation; they are not application dependencies.

```bash
python3 scripts/generate_branding_assets.py
```

On macOS or Linux the script uses DejaVu Sans when available for the social-preview tagline, with a documented system-font fallback. It removes PNG metadata and writes deterministic dimensions. Review the icon at every generated size after regeneration; visual sign-off is still a human task.

The social preview intentionally contains no interface screenshot. Real screenshots will only be added after the macOS application has been launched and inspected.
