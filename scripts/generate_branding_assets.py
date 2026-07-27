#!/usr/bin/env python3
"""Generate Cineleaf raster branding from documented vector geometry."""

from __future__ import annotations

from pathlib import Path
import math
import shutil

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
EXPORTS = ROOT / "Branding" / "Exports"
APP_ICONS = ROOT / "Cineleaf" / "Assets.xcassets" / "AppIcon.appiconset"
MASTER_SIZE = 1024
SCALE = 4


def cubic(p0, p1, p2, p3, steps=80):
    points = []
    for index in range(steps + 1):
        t = index / steps
        u = 1 - t
        points.append((
            u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
            u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1],
        ))
    return points


def scaled(points):
    return [(round(x * SCALE), round(y * SCALE)) for x, y in points]


def icon_master():
    image = Image.new("RGBA", (MASTER_SIZE * SCALE, MASTER_SIZE * SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(scaled([(64, 64), (960, 960)]), radius=208 * SCALE, fill="#142E28")
    frame_segments = [
        [(238, 340), (238, 270), (278, 230), (350, 230)],
        [(674, 230), (746, 230), (786, 270), (786, 340)],
        [(238, 684), (238, 754), (278, 794), (350, 794)],
        [(674, 794), (746, 794), (786, 754), (786, 684)],
    ]
    for segment in frame_segments:
        draw.line(scaled(segment), fill="#8AE1AF", width=34 * SCALE, joint="curve")

    leaf = cubic((300, 728), (286, 508), (422, 334), (736, 278))
    leaf += cubic((736, 278), (744, 510), (620, 704), (338, 754))
    leaf += cubic((338, 754), (319, 758), (302, 746), (300, 728), 16)
    draw.polygon(scaled(leaf), fill="#E8FFF1")

    cut = cubic((330, 718), (456, 614), (558, 502), (698, 326))
    draw.line(scaled(cut), fill="#142E28", width=44 * SCALE, joint="curve")
    for start, end in [((397, 668), (331, 611)), ((500, 572), (425, 505)), ((604, 462), (532, 400))]:
        draw.line(scaled([start, end]), fill="#142E28", width=28 * SCALE)
    return image.resize((MASTER_SIZE, MASTER_SIZE), Image.Resampling.LANCZOS)


def font(size, bold=False):
    names = ["DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf", "Arial Bold.ttf" if bold else "Arial.ttf"]
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def social_preview(icon):
    image = Image.new("RGB", (1280, 640), "#F3F7F4")
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((64, 56, 1216, 584), radius=42, fill="#E6EFE9")
    icon_small = icon.resize((260, 260), Image.Resampling.LANCZOS)
    image.paste(icon_small, (116, 190), icon_small)
    draw.text((430, 220), "Cineleaf", font=font(104, bold=True), fill="#142E28")
    draw.text((434, 350), "Free, native video editing for macOS", font=font(34), fill="#327C60")
    draw.rounded_rectangle((434, 417, 824, 465), radius=24, fill="#D2E8DA")
    draw.text((460, 427), "Private  |  Local-first  |  Open source", font=font(20, bold=True), fill="#1D553F")
    return image


def save_png(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def main():
    EXPORTS.mkdir(parents=True, exist_ok=True)
    APP_ICONS.mkdir(parents=True, exist_ok=True)
    icon = icon_master()
    save_png(icon, EXPORTS / "cineleaf-icon-1024.png")
    for size in (16, 32, 64, 128, 256, 512, 1024):
        save_png(icon.resize((size, size), Image.Resampling.LANCZOS), APP_ICONS / f"icon-{size}.png")
    save_png(social_preview(icon), EXPORTS / "github-social-preview.png")
    shutil.copyfile(ROOT / "Branding" / "Sources" / "cineleaf-icon.svg", EXPORTS / "cineleaf-icon.svg")
    for path in [EXPORTS / "cineleaf-icon-1024.png", EXPORTS / "github-social-preview.png"]:
        with Image.open(path) as generated:
            generated.verify()
    print("Generated Cineleaf branding and AppIcon assets.")


if __name__ == "__main__":
    main()
