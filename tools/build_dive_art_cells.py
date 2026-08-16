#!/usr/bin/env python3
"""Compose overlapping authored ArtCells into streamed underwater-map crops.

The source ArtCells are an authoring library. Runtime consumes only the generated
1024-unit crops registered in ``map_visual_chunks_v1.json``; the full composite is
never written to the production asset tree or preloaded by Godot.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
from typing import Any

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LIBRARY = PROJECT_ROOT / "assets/diving/world/art_cells/r1/r1_art_cells_v1.json"
DEFAULT_RUNTIME_MANIFEST = (
    PROJECT_ROOT
    / "assets/diving/world/map_v2/visual_chunks/map_visual_chunks_v1.json"
)
DEFAULT_PREVIEW = PROJECT_ROOT / "tmp/r1_art_cells_composite_preview.png"
CHUNK_SIZE = 1024
GUTTER = 2
LAYER_ID = "r1_art_cells"
RUNTIME_PARENT = "R1ArtCells"
RUNTIME_Z_INDEX = -96
RUNTIME_LIGHT_MODE = "unshaded"


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _res_path(path: Path) -> str:
    return "res://" + path.relative_to(PROJECT_ROOT).as_posix()


def _project_path(resource_path: str) -> Path:
    if not resource_path.startswith("res://"):
        raise RuntimeError(f"ArtCell path is not a res:// path: {resource_path}")
    return PROJECT_ROOT / resource_path.removeprefix("res://")


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as stream:
        parsed = json.load(stream)
    if not isinstance(parsed, dict):
        raise RuntimeError(f"JSON root must be an object: {path}")
    return parsed


def _pair(value: Any, context: str) -> tuple[int, int]:
    if not isinstance(value, list) or len(value) != 2:
        raise RuntimeError(f"{context} must contain exactly two integers.")
    return int(value[0]), int(value[1])


def _validate_library(library: dict[str, Any]) -> None:
    if int(library.get("schema_version", 0)) != 1:
        raise RuntimeError("Unsupported ArtCell library schema.")
    if str(library.get("region_id", "")) != "R1":
        raise RuntimeError("This builder currently expects the R1 ArtCell library.")
    cell_size = _pair(library.get("cell_size", []), "cell_size")
    world_size = _pair(library.get("world_size", []), "world_size")
    overlap = int(library.get("overlap", 0))
    stride = int(library.get("stride", 0))
    if cell_size != (2730, 1536):
        raise RuntimeError(f"R1 cell_size must remain 2730x1536, got {cell_size}.")
    if world_size != (11520, 1536):
        raise RuntimeError(f"R1 world_size must remain 11520x1536, got {world_size}.")
    if overlap != 426 or stride != cell_size[0] - overlap:
        raise RuntimeError("R1 overlap/stride must remain 426/2304.")
    if str(library.get("runtime_layer", "")) != RUNTIME_PARENT:
        raise RuntimeError(f"R1 runtime_layer must remain {RUNTIME_PARENT}.")
    if int(library.get("runtime_z_index", 0)) != RUNTIME_Z_INDEX:
        raise RuntimeError(f"R1 runtime_z_index must remain {RUNTIME_Z_INDEX}.")
    if str(library.get("runtime_light_mode", "")) != RUNTIME_LIGHT_MODE:
        raise RuntimeError(f"R1 runtime_light_mode must remain {RUNTIME_LIGHT_MODE}.")
    cells = library.get("cells", [])
    if not isinstance(cells, list) or len(cells) != 5:
        raise RuntimeError("R1 requires exactly five source ArtCells.")
    expected_origins = [0, 2304, 4608, 6912, 9216]
    seen_ids: set[str] = set()
    for index, cell_variant in enumerate(cells):
        if not isinstance(cell_variant, dict):
            raise RuntimeError(f"ArtCell {index + 1} must be an object.")
        cell_id = str(cell_variant.get("id", ""))
        if not cell_id or cell_id in seen_ids:
            raise RuntimeError(f"ArtCell id is empty or duplicated: {cell_id!r}")
        seen_ids.add(cell_id)
        origin = _pair(cell_variant.get("world_origin", []), f"{cell_id}.world_origin")
        if origin != (expected_origins[index], 0):
            raise RuntimeError(
                f"{cell_id} origin must be {(expected_origins[index], 0)}, got {origin}."
            )
        path = _project_path(str(cell_variant.get("path", "")))
        if not path.is_file():
            raise RuntimeError(f"Missing ArtCell source: {path}")
        with Image.open(path) as image:
            if image.size != cell_size:
                raise RuntimeError(
                    f"{path} has size {image.size}; expected constant {cell_size}."
                )


def _cosine_mask(width: int, height: int) -> Image.Image:
    if width <= 1:
        return Image.new("L", (max(width, 1), height), 255)
    values = bytes(
        round((0.5 - 0.5 * math.cos(math.pi * x / (width - 1))) * 255.0)
        for x in range(width)
    )
    return Image.frombytes("L", (width, 1), values).resize((width, height))


def _compose(library: dict[str, Any]) -> tuple[Image.Image, list[dict[str, Any]]]:
    world_width, world_height = _pair(library["world_size"], "world_size")
    cell_width, cell_height = _pair(library["cell_size"], "cell_size")
    canvas = Image.new("RGB", (world_width, world_height))
    current_right = 0
    source_assets: list[dict[str, Any]] = []

    for index, cell in enumerate(library["cells"]):
        path = _project_path(str(cell["path"]))
        origin_x, origin_y = _pair(cell["world_origin"], f"{cell['id']}.world_origin")
        with Image.open(path) as opened:
            image = opened.convert("RGB")
        if image.size != (cell_width, cell_height) or origin_y != 0:
            raise RuntimeError(f"Invalid normalized source ArtCell: {path}")

        visible_width = min(cell_width, world_width - origin_x)
        if visible_width <= 0:
            raise RuntimeError(f"ArtCell begins outside the R1 canvas: {path}")
        incoming = image.crop((0, 0, visible_width, world_height))

        if index == 0:
            canvas.paste(incoming, (origin_x, 0))
        else:
            overlap_end = min(current_right, origin_x + visible_width)
            overlap_width = overlap_end - origin_x
            if overlap_width <= 0:
                raise RuntimeError(f"ArtCell does not overlap its predecessor: {path}")
            previous_overlap = canvas.crop(
                (origin_x, 0, origin_x + overlap_width, world_height)
            )
            incoming_overlap = incoming.crop((0, 0, overlap_width, world_height))
            blended = Image.composite(
                incoming_overlap,
                previous_overlap,
                _cosine_mask(overlap_width, world_height),
            )
            canvas.paste(blended, (origin_x, 0))
            if visible_width > overlap_width:
                canvas.paste(
                    incoming.crop((overlap_width, 0, visible_width, world_height)),
                    (origin_x + overlap_width, 0),
                )

        current_right = max(current_right, origin_x + visible_width)
        source_assets.append(
            {
                "id": str(cell["id"]),
                "path": _res_path(path),
                "sha256": _sha256(path),
                "size_bytes": path.stat().st_size,
                "world_origin": [origin_x, origin_y],
            }
        )

    if current_right < world_width:
        raise RuntimeError(
            f"ArtCells cover only {current_right} of {world_width} R1 world units."
        )
    return canvas.convert("RGBA"), source_assets


def _expanded_box(
    box: tuple[int, int, int, int], margin: int, limit: tuple[int, int, int, int]
) -> tuple[int, int, int, int]:
    return (
        max(limit[0], box[0] - margin),
        max(limit[1], box[1] - margin),
        min(limit[2], box[2] + margin),
        min(limit[3], box[3] + margin),
    )


def _png_bytes(image: Image.Image) -> bytes:
    output = io.BytesIO()
    image.save(output, format="PNG", compress_level=9, optimize=False)
    return output.getvalue()


def _build_chunks(
    composite: Image.Image,
    output_root: Path,
    check: bool,
) -> tuple[list[dict[str, Any]], int]:
    layer_root = output_root / LAYER_ID
    expected_names: set[str] = set()
    chunks: list[dict[str, Any]] = []
    decoded_rgba_bytes = 0
    image_limit = (0, 0, composite.width, composite.height)

    for chunk_y, top in enumerate(range(0, composite.height, CHUNK_SIZE)):
        for chunk_x, left in enumerate(range(0, composite.width, CHUNK_SIZE)):
            render_box = (
                left,
                top,
                min(left + CHUNK_SIZE, composite.width),
                min(top + CHUNK_SIZE, composite.height),
            )
            crop_box = _expanded_box(render_box, GUTTER, image_limit)
            crop = composite.crop(crop_box)
            data = _png_bytes(crop)
            filename = f"chunk_{chunk_x:02d}_{chunk_y:02d}.png"
            expected_names.add(filename)
            output_path = layer_root / filename
            if check:
                if not output_path.is_file() or output_path.read_bytes() != data:
                    raise RuntimeError(f"Stale generated R1 ArtCell chunk: {output_path}")
            else:
                layer_root.mkdir(parents=True, exist_ok=True)
                output_path.write_bytes(data)

            crop_width = crop_box[2] - crop_box[0]
            crop_height = crop_box[3] - crop_box[1]
            render_width = render_box[2] - render_box[0]
            render_height = render_box[3] - render_box[1]
            decoded_rgba_bytes += crop_width * crop_height * 4
            chunks.append(
                {
                    "coord": [chunk_x, chunk_y],
                    "key": f"{LAYER_ID}:{chunk_x}:{chunk_y}",
                    "path": _res_path(output_path),
                    "sha256": _sha256_bytes(data),
                    "source_rect": [
                        crop_box[0],
                        crop_box[1],
                        crop_width,
                        crop_height,
                    ],
                    "texture_region": [
                        render_box[0] - crop_box[0],
                        render_box[1] - crop_box[1],
                        render_width,
                        render_height,
                    ],
                    "world_rect": [
                        render_box[0],
                        render_box[1],
                        render_width,
                        render_height,
                    ],
                }
            )

    if check:
        actual_names = {path.name for path in layer_root.glob("chunk_*.png")}
        if actual_names != expected_names:
            raise RuntimeError("Generated R1 ArtCell chunk set contains missing/stale files.")
    else:
        for stale_path in layer_root.glob("chunk_*.png"):
            if stale_path.name not in expected_names:
                stale_path.unlink()
    return chunks, decoded_rgba_bytes


def _layer_record(
    library_path: Path,
    library: dict[str, Any],
    source_assets: list[dict[str, Any]],
    chunks: list[dict[str, Any]],
    decoded_rgba_bytes: int,
) -> dict[str, Any]:
    world_width, world_height = _pair(library["world_size"], "world_size")
    return {
        "chunks": chunks,
        "generated_chunk_count": len(chunks),
        "generated_decoded_rgba_bytes": decoded_rgba_bytes,
        "id": LAYER_ID,
        "light_mode": RUNTIME_LIGHT_MODE,
        "rendered_pixel_count": world_width * world_height,
        "runtime_parent": RUNTIME_PARENT,
        "source_assets": source_assets,
        "source_assets_size_bytes": sum(
            int(asset["size_bytes"]) for asset in source_assets
        ),
        "source_decoded_rgba_bytes": sum(2730 * 1536 * 4 for _ in source_assets),
        "source_path": _res_path(library_path),
        "source_sha256": _sha256(library_path),
        "source_size_bytes": library_path.stat().st_size,
        "z_index": RUNTIME_Z_INDEX,
    }


def _update_runtime_manifest(
    runtime_manifest_path: Path,
    layer: dict[str, Any],
    check: bool,
) -> None:
    manifest = _load_json(runtime_manifest_path)
    layers = manifest.get("layers", [])
    if not isinstance(layers, list):
        raise RuntimeError("Runtime visual manifest has no layers array.")
    retained = [
        candidate
        for candidate in layers
        if not isinstance(candidate, dict) or str(candidate.get("id", "")) != LAYER_ID
    ]
    retained.append(layer)
    manifest["layers"] = retained
    manifest["art_cell_generator"] = "tools/build_dive_art_cells.py"
    rendered = (
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    )
    if check:
        if runtime_manifest_path.read_text(encoding="utf-8") != rendered:
            raise RuntimeError(f"Stale runtime visual manifest: {runtime_manifest_path}")
    else:
        runtime_manifest_path.write_text(rendered, encoding="utf-8", newline="\n")


def _save_preview(composite: Image.Image, preview_path: Path) -> None:
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    preview_width = 3840
    preview_height = round(composite.height * preview_width / composite.width)
    preview = composite.resize(
        (preview_width, preview_height), Image.Resampling.LANCZOS
    ).convert("RGB")
    preview.save(preview_path, format="PNG", compress_level=9, optimize=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--library", type=Path, default=DEFAULT_LIBRARY)
    parser.add_argument("--runtime-manifest", type=Path, default=DEFAULT_RUNTIME_MANIFEST)
    parser.add_argument("--preview", type=Path, default=DEFAULT_PREVIEW)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    library_path = args.library.resolve()
    runtime_manifest_path = args.runtime_manifest.resolve()
    preview_path = args.preview.resolve()
    library = _load_json(library_path)
    _validate_library(library)
    composite, source_assets = _compose(library)
    chunks, decoded_rgba_bytes = _build_chunks(
        composite,
        runtime_manifest_path.parent,
        args.check,
    )
    layer = _layer_record(
        library_path,
        library,
        source_assets,
        chunks,
        decoded_rgba_bytes,
    )
    _update_runtime_manifest(runtime_manifest_path, layer, args.check)
    if not args.check:
        _save_preview(composite, preview_path)

    print(
        json.dumps(
            {
                "art_cells": len(source_assets),
                "check": args.check,
                "composite_size": list(composite.size),
                "generated_chunks": len(chunks),
                "preview": _res_path(preview_path)
                if preview_path.is_relative_to(PROJECT_ROOT)
                else str(preview_path),
                "runtime_manifest": _res_path(runtime_manifest_path),
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
