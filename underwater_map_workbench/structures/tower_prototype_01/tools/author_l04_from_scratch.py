#!/usr/bin/env python3
"""Author W01 L04 directly at its canonical native resolution.

The existing ``tower_interior.png`` is deliberately not an input.  This script
starts with an empty RGBA raster and reads only canonical package derivatives:
the native open-water mask and structure truth used to keep runtime mechanisms
visually quiet.  It never resizes, upscales, downscales, or resamples an image.
"""

from __future__ import annotations

import argparse
import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


NATIVE_SIZE = (2240, 3680)
SEED = 0x4C30345F573031

# Independent cool-water palette.  Architecture and all solid material remain
# the responsibility of L05; L04 intentionally contains no structural forms.
DEPTH_STOPS = (
    (0, (7, 29, 42)),
    (420, (17, 55, 67)),
    (980, (18, 61, 73)),
    (1680, (15, 54, 68)),
    (2400, (11, 44, 58)),
    (3100, (8, 38, 52)),
    (3680, (7, 36, 49)),
)
ENTRY_WATER = (7, 29, 42)

# Soft, non-architectural native-coordinate fields: cx, cy, rx, ry, rotation,
# and RGB lift.  No field aligns to the 40-unit topology grid.
MIST_FIELDS = (
    (470.0, 610.0, 390.0, 270.0, -0.31, (4.2, 7.0, 7.2)),
    (1730.0, 1020.0, 330.0, 520.0, 0.42, (3.0, 7.8, 8.4)),
    (760.0, 1750.0, 480.0, 250.0, 0.18, (2.4, 6.0, 7.3)),
    (1680.0, 2360.0, 410.0, 300.0, -0.53, (2.0, 5.2, 6.8)),
    (990.0, 3140.0, 520.0, 340.0, 0.37, (2.2, 5.5, 7.4)),
)


def _smoothstep(value: float) -> float:
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)


def _depth_color(y: int) -> tuple[float, float, float]:
    for index in range(len(DEPTH_STOPS) - 1):
        y0, color0 = DEPTH_STOPS[index]
        y1, color1 = DEPTH_STOPS[index + 1]
        if y <= y1:
            weight = _smoothstep((y - y0) / float(y1 - y0))
            return tuple(
                color0[channel] * (1.0 - weight) + color1[channel] * weight
                for channel in range(3)
            )
    return tuple(float(value) for value in DEPTH_STOPS[-1][1])


def _load_truth(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if value.get("mapping", {}).get("world_units_per_pixel") != [1, 1]:
        raise ValueError("structure truth must preserve 1 world unit per pixel")
    if value.get("size") != [NATIVE_SIZE[0], NATIVE_SIZE[1]]:
        raise ValueError("structure truth has a non-native size")
    return value


def _quiet_factor(truth: dict) -> Image.Image:
    """Return a native-size field suppressing detail around runtime sweeps."""

    zones = Image.new("L", NATIVE_SIZE, 0)
    draw = ImageDraw.Draw(zones)
    sockets = {record["id"]: record for record in truth["sockets"]}

    def add_rect(rect: list[int], padding: int) -> None:
        x, y, width, height = rect
        draw.rectangle(
            (
                max(0, x - padding),
                max(0, y - padding),
                min(NATIVE_SIZE[0] - 1, x + width + padding),
                min(NATIVE_SIZE[1] - 1, y + height + padding),
            ),
            fill=255,
        )

    for socket in truth["sockets"]:
        if socket["kind"] in {"dynamic_door", "control", "moving_elevator"}:
            add_rect(socket["local_rect"], 36 if socket["kind"] != "moving_elevator" else 28)

    for group in truth["runtime"]["barrier_groups"]:
        for member in group["members"]:
            rect = sockets[member["socket_id"]]["local_rect"]
            offset_x, offset_y = member["open_offset"]
            open_rect = [rect[0] + offset_x, rect[1] + offset_y, rect[2], rect[3]]
            add_rect(open_rect, 36)

    # The blur is evaluated at 2240x3680; it is not a scale operation.
    return zones.filter(ImageFilter.GaussianBlur(radius=52.0))


def _author_pixels(mask: Image.Image, quiet: Image.Image) -> Image.Image:
    width, height = NATIVE_SIZE
    mask_bytes = mask.tobytes()
    quiet_bytes = quiet.tobytes()
    pixels = bytearray(width * height * 4)

    field_cache = []
    for cx, cy, rx, ry, angle, lift in MIST_FIELDS:
        cosine = math.cos(angle)
        sine = math.sin(angle)
        field_cache.append((cx, cy, rx, ry, cosine, sine, lift))

    for y in range(height):
        base = _depth_color(y)
        row_offset = y * width
        depth_wave = math.sin(y * 0.0067 + 0.8) * 1.15
        for x in range(width):
            pixel_index = row_offset + x
            if mask_bytes[pixel_index] == 0:
                continue

            quiet_strength = quiet_bytes[pixel_index] / 255.0
            variation_scale = 1.0 - quiet_strength * 0.72
            soft_noise = (
                math.sin(x * 0.0053 + y * 0.0021 + 0.37)
                + math.sin(x * 0.0019 - y * 0.0041 + 1.73)
                + math.sin((x + y) * 0.0013 + 2.41)
            ) * 0.72
            lift_r = 0.0
            lift_g = 0.0
            lift_b = 0.0
            for cx, cy, rx, ry, cosine, sine, lift in field_cache:
                dx = x - cx
                dy = y - cy
                rotated_x = dx * cosine + dy * sine
                rotated_y = -dx * sine + dy * cosine
                distance = (rotated_x / rx) ** 2 + (rotated_y / ry) ** 2
                weight = math.exp(-1.65 * distance)
                lift_r += lift[0] * weight
                lift_g += lift[1] * weight
                lift_b += lift[2] * weight

            red = base[0] + (soft_noise + depth_wave * 0.35 + lift_r) * variation_scale
            green = base[1] + (soft_noise * 1.25 + depth_wave * 0.65 + lift_g) * variation_scale
            blue = base[2] + (soft_noise * 1.35 + depth_wave * 0.8 + lift_b) * variation_scale

            # Match map water at the west entry, then dissolve the seam over a
            # broad, smooth native-coordinate transition instead of drawing a
            # boundary-aligned strip.
            entry_y = math.exp(-((y - 160.0) / 175.0) ** 4)
            entry_x = 1.0 - _smoothstep((x - 120.0) / 340.0)
            entry_weight = min(1.0, max(0.0, entry_y * entry_x))
            red = red * (1.0 - entry_weight) + ENTRY_WATER[0] * entry_weight
            green = green * (1.0 - entry_weight) + ENTRY_WATER[1] * entry_weight
            blue = blue * (1.0 - entry_weight) + ENTRY_WATER[2] * entry_weight

            # Preserve an unmistakably cool open-water hierarchy throughout.
            green = max(green, red + 10.0)
            blue = max(blue, green + 6.0)
            red_i = min(255, max(0, int(round(red))))
            green_i = min(255, max(0, int(round(green))))
            blue_i = min(255, max(0, int(round(blue))))
            offset = pixel_index * 4
            pixels[offset : offset + 4] = bytes((red_i, green_i, blue_i, 255))

    return Image.frombytes("RGBA", NATIVE_SIZE, bytes(pixels))


def _add_particles(image: Image.Image, mask: Image.Image, quiet: Image.Image) -> None:
    rng = random.Random(SEED)
    draw = ImageDraw.Draw(image)
    mask_pixels = mask.load()
    quiet_pixels = quiet.load()
    colors = ((55, 103, 109, 255), (63, 116, 119, 255), (48, 91, 99, 255))
    placed = 0
    attempts = 0
    while placed < 760 and attempts < 20_000:
        attempts += 1
        x = rng.randrange(12, NATIVE_SIZE[0] - 12)
        y = rng.randrange(12, NATIVE_SIZE[1] - 12)
        radius = rng.choice((1, 1, 1, 2, 2, 3))
        if mask_pixels[x, y] != 255 or quiet_pixels[x, y] > 28:
            continue
        if any(
            mask_pixels[min(NATIVE_SIZE[0] - 1, max(0, px)), min(NATIVE_SIZE[1] - 1, max(0, py))]
            != 255
            for px, py in ((x - radius, y), (x + radius, y), (x, y - radius), (x, y + radius))
        ):
            continue
        color = colors[rng.randrange(len(colors))]
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)
        placed += 1
    if placed != 760:
        raise RuntimeError(f"could place only {placed} native particles")


def _enforce_mask(image: Image.Image, mask: Image.Image) -> Image.Image:
    rgba = bytearray(image.tobytes())
    mask_bytes = mask.tobytes()
    for pixel_index, alpha in enumerate(mask_bytes):
        offset = pixel_index * 4
        if alpha == 0:
            rgba[offset : offset + 4] = b"\x00\x00\x00\x00"
        elif alpha == 255:
            rgba[offset + 3] = 255
        else:
            raise ValueError("open-water mask must be binary")
    return Image.frombytes("RGBA", NATIVE_SIZE, bytes(rgba))


def main() -> int:
    script_path = Path(__file__).resolve()
    package_root = script_path.parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mask",
        type=Path,
        default=package_root / "generated" / "open_water_mask_native.png",
    )
    parser.add_argument(
        "--truth",
        type=Path,
        default=package_root / "generated" / "structure_truth.json",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=package_root / "assets" / "visual" / "tower_interior.png",
    )
    args = parser.parse_args()

    mask = Image.open(args.mask)
    if mask.size != NATIVE_SIZE or mask.mode != "L":
        raise ValueError("open-water mask must be native 2240x3680 grayscale")
    truth = _load_truth(args.truth)
    quiet = _quiet_factor(truth)
    authored = _author_pixels(mask, quiet)
    _add_particles(authored, mask, quiet)
    final = _enforce_mask(authored, mask)
    if final.size != NATIVE_SIZE:
        raise AssertionError("authoring changed the native size")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    final.save(args.output, format="PNG", compress_level=9, optimize=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
