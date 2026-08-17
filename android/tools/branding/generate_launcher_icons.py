#!/usr/bin/env python3
"""Generate deterministic Android launcher icons from the Maurya master artwork."""

from __future__ import annotations

import hashlib
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
MASTER = Path(__file__).with_name("maurya_launcher_master.png")
RES = ROOT / "app" / "src" / "main" / "res"
PLAY_STORE = ROOT / "app" / "src" / "main" / "ic_launcher-playstore.png"

DENSITIES = {
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}
BACKGROUND = (5, 4, 9, 255)
ADAPTIVE_ART_SCALE = 0.74
ROUND_ART_SCALE = 0.92


def square_art(source: Image.Image, size: int, scale: float = 1.0) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), BACKGROUND)
    art_size = max(1, round(size * scale))
    art = source.resize((art_size, art_size), Image.Resampling.LANCZOS)
    offset = ((size - art_size) // 2, (size - art_size) // 2)
    canvas.alpha_composite(art, offset)
    return canvas


def round_art(source: Image.Image, size: int) -> Image.Image:
    icon = square_art(source, size, ROUND_ART_SCALE)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    icon.putalpha(mask)
    return icon


def save_webp(image: Image.Image, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, "WEBP", lossless=True, method=6)


def main() -> None:
    if not MASTER.is_file():
        raise SystemExit(f"missing launcher master: {MASTER}")

    with Image.open(MASTER) as opened:
        source = opened.convert("RGBA")
    if source.width != source.height or source.width < 512:
        raise SystemExit("launcher master must be square and at least 512 px")

    square_art(source, 512).save(PLAY_STORE, "PNG", optimize=True)

    for density, (legacy_size, foreground_size) in DENSITIES.items():
        directory = RES / f"mipmap-{density}"
        save_webp(square_art(source, legacy_size), directory / "ic_launcher.webp")
        save_webp(round_art(source, legacy_size), directory / "ic_launcher_round.webp")
        save_webp(
            square_art(source, foreground_size, ADAPTIVE_ART_SCALE),
            directory / "ic_launcher_foreground.webp",
        )

    digest = hashlib.sha256(MASTER.read_bytes()).hexdigest()
    print(f"generated launcher icons from {MASTER.name} ({digest})")


if __name__ == "__main__":
    main()
