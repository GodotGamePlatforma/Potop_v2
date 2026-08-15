#!/usr/bin/env python3
"""Build a deterministic seamless tile from the authored dive rock detail."""

from __future__ import annotations

import argparse
from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path
import sys

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/diving/world/materials/underwater_rock_detail_v1.png"
OUTPUT = ROOT / "assets/diving/world/materials/underwater_rock_detail_tile_v1.png"
MANIFEST = ROOT / "assets/diving/world/materials/underwater_rock_detail_tile_v1.json"
TILE_SIZE = 1024


def _build(source_bytes: bytes) -> bytes:
    with Image.open(BytesIO(source_bytes)) as source:
        base = source.convert("RGBA").resize(
            (TILE_SIZE // 2, TILE_SIZE // 2), Image.Resampling.LANCZOS
        )
    tile = Image.new("RGBA", (TILE_SIZE, TILE_SIZE))
    tile.paste(base, (0, 0))
    tile.paste(ImageOps.mirror(base), (TILE_SIZE // 2, 0))
    tile.paste(ImageOps.flip(base), (0, TILE_SIZE // 2))
    tile.paste(ImageOps.flip(ImageOps.mirror(base)), (TILE_SIZE // 2, TILE_SIZE // 2))
    buffer = BytesIO()
    tile.save(buffer, format="PNG", optimize=False, compress_level=9)
    return buffer.getvalue()


def _manifest(source_bytes: bytes, output_bytes: bytes) -> bytes:
    value = {
        "generator": "tools/build_dive_rock_detail_tile.py",
        "generator_version": 1,
        "output_path": "res://assets/diving/world/materials/underwater_rock_detail_tile_v1.png",
        "output_sha256": sha256(output_bytes).hexdigest(),
        "source_path": "res://assets/diving/world/materials/underwater_rock_detail_v1.png",
        "source_sha256": sha256(source_bytes).hexdigest(),
        "tile_size": TILE_SIZE,
        "transform": "half_scale_mirrored_2x2",
    }
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    source_bytes = SOURCE.read_bytes()
    output_bytes = _build(source_bytes)
    manifest_bytes = _manifest(source_bytes, output_bytes)
    if args.check:
        stale = []
        if not OUTPUT.is_file() or OUTPUT.read_bytes() != output_bytes:
            stale.append(str(OUTPUT.relative_to(ROOT)))
        if not MANIFEST.is_file() or MANIFEST.read_bytes() != manifest_bytes:
            stale.append(str(MANIFEST.relative_to(ROOT)))
        if stale:
            print("Stale derived rock tile: " + ", ".join(stale), file=sys.stderr)
            return 1
        print("Rock detail tile is deterministic and current.")
        return 0
    OUTPUT.write_bytes(output_bytes)
    MANIFEST.write_bytes(manifest_bytes)
    print(f"Built seamless rock detail tile: {len(output_bytes)} bytes, sha256={sha256(output_bytes).hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
