#!/usr/bin/env python3
"""Build the presentation-only signed-distance contour for the dive terrain.

The source PNG remains the canonical navigation/collision mask.  This tool only
derives a smoother raster for the terrain shader and records enough hashes to
make the generated asset reproducible and reviewable.
"""

from __future__ import annotations

import argparse
from array import array
from hashlib import sha256
from io import BytesIO
import json
import math
from pathlib import Path
import sys

from PIL import Image, ImageFilter


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = REPOSITORY_ROOT / "assets/diving/world/map_v2/world_collision_grid.png"
OUTPUT_PATH = REPOSITORY_ROOT / "assets/diving/world/map_v2/world_collision_render_sdf_v1.png"
MANIFEST_PATH = REPOSITORY_ROOT / "assets/diving/world/map_v2/world_collision_render_sdf_v1.json"
GENERATOR_VERSION = 1
BLOCKED_THRESHOLD = 128
SPREAD_TEXELS = 12.0
SMOOTH_RADIUS_TEXELS = 1.75
INFINITY = 0x3FFFFFFF


def _row_squared_distances(features: bytes, width: int, height: int) -> array:
    distances = array("I", [INFINITY]) * (width * height)
    for y in range(height):
        offset = y * width
        nearest = -width * 2
        for x in range(width):
            if features[offset + x]:
                nearest = x
                distances[offset + x] = 0
            elif nearest >= 0:
                delta = x - nearest
                distances[offset + x] = delta * delta
        nearest = width * 3
        for x in range(width - 1, -1, -1):
            if features[offset + x]:
                nearest = x
            elif nearest < width:
                delta = nearest - x
                candidate = delta * delta
                if candidate < distances[offset + x]:
                    distances[offset + x] = candidate
    return distances


def _squared_euclidean_distance(features: bytes, width: int, height: int) -> array:
    """Exact 2D EDT using row passes plus lower envelopes of parabolas."""
    rows = _row_squared_distances(features, width, height)
    result = array("I", [INFINITY]) * (width * height)
    sites = [0] * height
    boundaries = [0.0] * (height + 1)

    for x in range(width):
        finite_rows = [y for y in range(height) if rows[y * width + x] < INFINITY]
        if not finite_rows:
            continue

        envelope_size = 0
        sites[0] = finite_rows[0]
        boundaries[0] = -math.inf
        boundaries[1] = math.inf
        for q in finite_rows[1:]:
            q_value = rows[q * width + x]
            while True:
                p = sites[envelope_size]
                p_value = rows[p * width + x]
                intersection = (
                    (float(q_value) + float(q * q))
                    - (float(p_value) + float(p * p))
                ) / float(2 * (q - p))
                if intersection > boundaries[envelope_size] or envelope_size == 0:
                    break
                envelope_size -= 1
            envelope_size += 1
            sites[envelope_size] = q
            boundaries[envelope_size] = intersection
            boundaries[envelope_size + 1] = math.inf

        envelope_index = 0
        for y in range(height):
            while boundaries[envelope_index + 1] < float(y):
                envelope_index += 1
            site = sites[envelope_index]
            delta = y - site
            result[y * width + x] = rows[site * width + x] + delta * delta
    return result


def _png_bytes(source: Image.Image) -> tuple[bytes, int, int]:
    grayscale = source.convert("L")
    width, height = grayscale.size
    samples = grayscale.tobytes()
    blocked = bytes(1 if value >= BLOCKED_THRESHOLD else 0 for value in samples)
    traversable = bytes(0 if value else 1 for value in blocked)
    if not any(blocked) or not any(traversable):
        raise ValueError("The source mask must contain both blocked and traversable pixels.")

    distance_to_blocked = _squared_euclidean_distance(blocked, width, height)
    distance_to_traversable = _squared_euclidean_distance(traversable, width, height)
    encoded = bytearray(width * height)
    normalization = 2.0 * SPREAD_TEXELS
    for index, is_blocked in enumerate(blocked):
        if is_blocked:
            signed_distance = math.sqrt(float(distance_to_traversable[index]))
        else:
            signed_distance = -math.sqrt(float(distance_to_blocked[index]))
        normalized = max(0.0, min(1.0, 0.5 + signed_distance / normalization))
        encoded[index] = int(normalized * 255.0 + 0.5)

    # The exact EDT inherits the eight-world-unit staircase of the semantic
    # raster.  A symmetric presentation-only blur of the signed field rounds
    # that contour without changing the source mask or any gameplay consumer.
    output = Image.frombytes("L", (width, height), bytes(encoded)).filter(
        ImageFilter.GaussianBlur(radius=SMOOTH_RADIUS_TEXELS)
    )
    buffer = BytesIO()
    output.save(buffer, format="PNG", optimize=False, compress_level=9)
    return buffer.getvalue(), width, height


def _manifest_bytes(source_bytes: bytes, png_bytes: bytes, width: int, height: int) -> bytes:
    manifest = {
        "blocked_threshold": BLOCKED_THRESHOLD,
        "generator": "tools/build_dive_terrain_sdf.py",
        "generator_version": GENERATOR_VERSION,
        "height": height,
        "output_path": "res://assets/diving/world/map_v2/world_collision_render_sdf_v1.png",
        "output_sha256": sha256(png_bytes).hexdigest(),
        "semantic_contract": "bright_blocked_dark_traversable",
        "smooth_radius_texels": SMOOTH_RADIUS_TEXELS,
        "source_path": "res://assets/diving/world/map_v2/world_collision_grid.png",
        "source_sha256": sha256(source_bytes).hexdigest(),
        "spread_texels": SPREAD_TEXELS,
        "width": width,
    }
    return (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def _matches(path: Path, expected: bytes) -> bool:
    return path.is_file() and path.read_bytes() == expected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify that the committed PNG and manifest match a fresh deterministic build",
    )
    args = parser.parse_args()

    source_bytes = SOURCE_PATH.read_bytes()
    with Image.open(BytesIO(source_bytes)) as source:
        png_bytes, width, height = _png_bytes(source)
    manifest_bytes = _manifest_bytes(source_bytes, png_bytes, width, height)

    if args.check:
        stale = []
        if not _matches(OUTPUT_PATH, png_bytes):
            stale.append(str(OUTPUT_PATH.relative_to(REPOSITORY_ROOT)))
        if not _matches(MANIFEST_PATH, manifest_bytes):
            stale.append(str(MANIFEST_PATH.relative_to(REPOSITORY_ROOT)))
        if stale:
            print("Stale derived terrain SDF: " + ", ".join(stale), file=sys.stderr)
            return 1
        print(f"Terrain SDF is deterministic and current: {width}x{height}.")
        return 0

    OUTPUT_PATH.write_bytes(png_bytes)
    MANIFEST_PATH.write_bytes(manifest_bytes)
    print(
        "Built presentation-only terrain SDF: "
        f"{width}x{height}, {len(png_bytes)} bytes, sha256={sha256(png_bytes).hexdigest()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
