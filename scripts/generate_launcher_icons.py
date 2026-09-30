#!/usr/bin/env python3
"""Generate deterministic Android launcher assets from the supplied icon."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

INNER_RED = (201, 31, 55, 255)
OUTER_RED = (159, 18, 48, 255)


def edge_connected_white(image: Image.Image) -> Image.Image:
    rgb = image.convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()
    outside = Image.new("L", rgb.size, 0)
    outside_pixels = outside.load()
    queue: deque[tuple[int, int]] = deque()

    def white_like(x: int, y: int) -> bool:
        red, green, blue = pixels[x, y]
        return min(red, green, blue) >= 232 and max(red, green, blue) - min(
            red, green, blue
        ) <= 20

    for x in range(width):
        queue.append((x, 0))
        queue.append((x, height - 1))
    for y in range(height):
        queue.append((0, y))
        queue.append((width - 1, y))

    while queue:
        x, y = queue.popleft()
        if outside_pixels[x, y] or not white_like(x, y):
            continue
        outside_pixels[x, y] = 255
        if x:
            queue.append((x - 1, y))
        if x + 1 < width:
            queue.append((x + 1, y))
        if y:
            queue.append((x, y - 1))
        if y + 1 < height:
            queue.append((x, y + 1))

    rgba = rgb.convert("RGBA")
    rgba.putalpha(ImageChops.invert(outside))
    return rgba


def glyph_foreground(source: Image.Image, outside_alpha: Image.Image) -> Image.Image:
    rgb = source.convert("RGB")
    result = Image.new("RGBA", rgb.size, (255, 255, 255, 0))
    src = rgb.load()
    dst = result.load()
    outside = outside_alpha.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            # The supplied artwork has a lightly antialiased white page edge.
            # Adaptive icons supply their own mask, so only retain the central
            # glyph and never promote those outer edge pixels to foreground.
            if not (
                rgb.width * 0.12 <= x <= rgb.width * 0.88
                and rgb.height * 0.10 <= y <= rgb.height * 0.90
            ):
                continue
            if outside[x, y] == 0:
                continue
            red, green, blue = src[x, y]
            neutral = max(red, green, blue) - min(red, green, blue)
            if neutral > 26:
                continue
            alpha = max(0, min(255, round((min(red, green, blue) - 178) * 3.3)))
            if alpha:
                dst[x, y] = (255, 255, 255, alpha)
    return result


def save_resized(image: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(path, optimize=True)


def fitted_layer(image: Image.Image, side: int, occupancy: float) -> Image.Image:
    """Center the visible artwork inside a predictable launcher safe zone."""
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    output = Image.new("RGBA", (side, side), (255, 255, 255, 0))
    if not bounds:
        return output
    cropped = image.crop(bounds)
    target = round(side * occupancy)
    scale = min(target / cropped.width, target / cropped.height)
    size = (
        max(1, round(cropped.width * scale)),
        max(1, round(cropped.height * scale)),
    )
    cropped = cropped.resize(size, Image.Resampling.LANCZOS)
    offset = ((side - size[0]) // 2, (side - size[1]) // 2)
    output.alpha_composite(cropped, offset)
    return output


def dark_red_background(side: int) -> Image.Image:
    """Create the restrained red background used by legacy launcher icons."""
    image = Image.new("RGBA", (side, side), OUTER_RED)
    pixels = image.load()
    center_x = (side - 1) / 2
    center_y = (side - 1) * 0.46
    radius = side * 0.74
    for y in range(side):
        for x in range(side):
            distance = ((x - center_x) ** 2 + (y - center_y) ** 2) ** 0.5
            amount = min(1.0, distance / radius)
            pixels[x, y] = tuple(
                round(INNER_RED[channel] * (1 - amount) + OUTER_RED[channel] * amount)
                for channel in range(4)
            )
    return image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("res_root", type=Path)
    args = parser.parse_args()

    source = Image.open(args.source).convert("RGB")
    side = min(source.size)
    left = (source.width - side) // 2
    top = (source.height - side) // 2
    source = source.crop((left, top, left + side, top + side))
    cleaned = edge_connected_white(source)
    outside_alpha = cleaned.getchannel("A")
    foreground = glyph_foreground(source, outside_alpha)

    legacy_background = dark_red_background(side)
    legacy_glyph = fitted_layer(foreground, side, 0.58)
    legacy_icon = Image.alpha_composite(legacy_background, legacy_glyph)
    rounded_mask = Image.new("L", (side, side), 0)
    ImageDraw.Draw(rounded_mask).rounded_rectangle(
        (0, 0, side - 1, side - 1), radius=round(side * 0.19), fill=255
    )
    legacy_icon.putalpha(rounded_mask)

    round_icon = Image.alpha_composite(legacy_background, legacy_glyph)
    round_mask = Image.new("L", (side, side), 0)
    ImageDraw.Draw(round_mask).ellipse((0, 0, side - 1, side - 1), fill=255)
    round_icon.putalpha(round_mask)

    adaptive_foreground = fitted_layer(foreground, side, 0.56)

    for density, legacy_size in DENSITIES.items():
        mipmap = args.res_root / f"mipmap-{density}"
        save_resized(legacy_icon, mipmap / "ic_launcher.png", legacy_size)
        save_resized(round_icon, mipmap / "ic_launcher_round.png", legacy_size)

        adaptive_size = round(legacy_size * 2.25)
        drawable = args.res_root / f"drawable-{density}"
        save_resized(
            adaptive_foreground,
            drawable / "ic_launcher_foreground.png",
            adaptive_size,
        )


if __name__ == "__main__":
    main()
