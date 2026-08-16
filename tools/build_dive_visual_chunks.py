#!/usr/bin/env python3
"""Build sparse, presentation-only chunks for the authored underwater map layers.

The source PNGs remain the authoring masters.  Runtime consumes only the generated
manifest and requests individual crops on demand.  Chunk geometry is deliberately
kept out of the gameplay blueprint and its signature.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageChops


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = PROJECT_ROOT / "assets/diving/world/map_v2/visuals"
OUTPUT_ROOT = PROJECT_ROOT / "assets/diving/world/map_v2/visual_chunks"
MANIFEST_PATH = OUTPUT_ROOT / "map_visual_chunks_v1.json"
CHUNK_SIZE = 1024
GUTTER = 2
TRANSPARENT_INNER_MARGIN = 1


@dataclass(frozen=True)
class Layer:
    layer_id: str
    source_name: str
    runtime_parent: str
    z_index: int


LAYERS = (
    Layer(
        "environment_decoration",
        "duzaMapaEnvironmentDecorationLayer-v3.png",
        "EnvironmentDecoration",
        -90,
    ),
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _res_path(path: Path) -> str:
    return "res://" + path.relative_to(PROJECT_ROOT).as_posix()


def _expanded_box(
    box: tuple[int, int, int, int], margin: int, limit: tuple[int, int, int, int]
) -> tuple[int, int, int, int]:
    left, top, right, bottom = box
    limit_left, limit_top, limit_right, limit_bottom = limit
    return (
        max(limit_left, left - margin),
        max(limit_top, top - margin),
        min(limit_right, right + margin),
        min(limit_bottom, bottom + margin),
    )


def _build_layer(layer: Layer, expected_size: tuple[int, int]) -> dict:
    source_path = SOURCE_ROOT / layer.source_name
    with Image.open(source_path) as source_image:
        image = source_image.convert("RGBA")
    if image.size != expected_size:
        raise RuntimeError(
            f"{source_path} has size {image.size}, expected {expected_size}."
        )

    alpha = image.getchannel("A")
    layer_output = OUTPUT_ROOT / layer.layer_id
    layer_output.mkdir(parents=True, exist_ok=True)
    expected_names: set[str] = set()
    chunks: list[dict] = []
    decoded_rgba_bytes = 0
    rendered_pixel_count = 0

    for chunk_y, core_top in enumerate(range(0, image.height, CHUNK_SIZE)):
        for chunk_x, core_left in enumerate(range(0, image.width, CHUNK_SIZE)):
            core_box = (
                core_left,
                core_top,
                min(core_left + CHUNK_SIZE, image.width),
                min(core_top + CHUNK_SIZE, image.height),
            )
            local_alpha_bounds = alpha.crop(core_box).getbbox()
            if local_alpha_bounds is None:
                continue

            alpha_box = (
                core_left + local_alpha_bounds[0],
                core_top + local_alpha_bounds[1],
                core_left + local_alpha_bounds[2],
                core_top + local_alpha_bounds[3],
            )
            render_box = _expanded_box(
                alpha_box, TRANSPARENT_INNER_MARGIN, core_box
            )
            crop_box = _expanded_box(
                render_box, GUTTER, (0, 0, image.width, image.height)
            )
            crop = image.crop(crop_box)

            filename = f"chunk_{chunk_x:02d}_{chunk_y:02d}.png"
            output_path = layer_output / filename
            crop.save(output_path, format="PNG", compress_level=9, optimize=False)
            expected_names.add(filename)

            # The rendered rectangle contains every non-transparent source pixel in
            # this grid cell. The additional crop gutter is sampled by linear
            # filtering but never produces overlapping geometry.
            outside_alpha = alpha.crop(core_box)
            local_render_box = (
                render_box[0] - core_left,
                render_box[1] - core_top,
                render_box[2] - core_left,
                render_box[3] - core_top,
            )
            masked = Image.new("L", outside_alpha.size)
            masked.paste(outside_alpha.crop(local_render_box), local_render_box[:2])
            if ImageChops.subtract(outside_alpha, masked).getbbox() is not None:
                raise RuntimeError(f"Generated render box omits alpha in {output_path}.")

            crop_width = crop_box[2] - crop_box[0]
            crop_height = crop_box[3] - crop_box[1]
            render_width = render_box[2] - render_box[0]
            render_height = render_box[3] - render_box[1]
            decoded_rgba_bytes += crop_width * crop_height * 4
            rendered_pixel_count += render_width * render_height
            chunks.append(
                {
                    "key": f"{layer.layer_id}:{chunk_x}:{chunk_y}",
                    "coord": [chunk_x, chunk_y],
                    "path": _res_path(output_path),
                    "world_rect": [
                        render_box[0],
                        render_box[1],
                        render_width,
                        render_height,
                    ],
                    "texture_region": [
                        render_box[0] - crop_box[0],
                        render_box[1] - crop_box[1],
                        render_width,
                        render_height,
                    ],
                    "source_rect": [
                        crop_box[0],
                        crop_box[1],
                        crop_width,
                        crop_height,
                    ],
                    "sha256": _sha256(output_path),
                }
            )

    for stale_path in sorted(layer_output.glob("chunk_*.png")):
        if stale_path.name not in expected_names:
            stale_path.unlink()

    chunks.sort(key=lambda item: (item["coord"][1], item["coord"][0]))
    return {
        "id": layer.layer_id,
        "runtime_parent": layer.runtime_parent,
        "z_index": layer.z_index,
        "source_path": _res_path(source_path),
        "source_sha256": _sha256(source_path),
        "source_size_bytes": source_path.stat().st_size,
        "source_decoded_rgba_bytes": image.width * image.height * 4,
        "generated_chunk_count": len(chunks),
        "generated_decoded_rgba_bytes": decoded_rgba_bytes,
        "rendered_pixel_count": rendered_pixel_count,
        "chunks": chunks,
    }


def _load_retained_layers(owned_layer_ids: set[str]) -> tuple[dict, list[dict]]:
    if not MANIFEST_PATH.is_file():
        return {}, []
    parsed = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if not isinstance(parsed, dict):
        raise RuntimeError(f"Existing visual manifest is not an object: {MANIFEST_PATH}")
    existing_layers = parsed.get("layers", [])
    if not isinstance(existing_layers, list):
        raise RuntimeError(
            f"Existing visual manifest has no layers array: {MANIFEST_PATH}"
        )
    retained_layers: list[dict] = []
    for layer in existing_layers:
        if not isinstance(layer, dict):
            raise RuntimeError(
                f"Existing visual manifest contains a non-object layer: {MANIFEST_PATH}"
            )
        layer_id = str(layer.get("id", ""))
        if not layer_id:
            raise RuntimeError(
                f"Existing visual manifest contains a layer without id: {MANIFEST_PATH}"
            )
        if layer_id not in owned_layer_ids:
            retained_layers.append(layer)
    return parsed, retained_layers


def main() -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    expected_size = (11_520, 6_480)
    layers = [_build_layer(layer, expected_size) for layer in LAYERS]
    owned_layer_ids = {layer.layer_id for layer in LAYERS}
    manifest, retained_layers = _load_retained_layers(owned_layer_ids)
    manifest.update(
        {
            "schema_version": 1,
            "generator": "tools/build_dive_visual_chunks.py",
            "world_size": list(expected_size),
            "grid_chunk_size": CHUNK_SIZE,
            "filter_gutter": GUTTER,
            "layers": layers + retained_layers,
        }
    )
    MANIFEST_PATH.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )

    source_bytes = sum(layer["source_size_bytes"] for layer in layers)
    generated_files = [
        PROJECT_ROOT / chunk["path"].removeprefix("res://")
        for layer in layers
        for chunk in layer["chunks"]
    ]
    generated_bytes = sum(path.stat().st_size for path in generated_files)
    source_rgba = sum(layer["source_decoded_rgba_bytes"] for layer in layers)
    generated_rgba = sum(layer["generated_decoded_rgba_bytes"] for layer in layers)
    print(
        json.dumps(
            {
                "source_files": len(layers),
                "source_bytes": source_bytes,
                "source_decoded_rgba_bytes": source_rgba,
                "generated_files": len(generated_files),
                "generated_bytes": generated_bytes,
                "generated_decoded_rgba_bytes_all_chunks": generated_rgba,
                "manifest": _res_path(MANIFEST_PATH),
            },
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
