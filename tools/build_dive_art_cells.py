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
VISUAL_REVISION = 2
QA_VIEWPORT_SIZE = (1280, 720)
QA_CAMERA_ZOOM = 1.2
QA_VISIBILITY_CASES = (
    ("Background_001", (1365, 960), (64, 0, 1152, 540)),
    ("Background_002", (3800, 960), (64, 80, 1152, 540)),
    ("Background_003", (5568, 960), (64, 0, 1152, 540)),
    ("Background_004", (8192, 960), (64, 0, 1152, 540)),
    ("Background_005", (9696, 1120), (64, 360, 1152, 344)),
)
SOURCE_CONTENT_BAND = (64, 600, 2666, 1250)
SOURCE_CONTENT_DOWNSAMPLE = 4
SOURCE_CONTENT_GRADIENT_THRESHOLD = 3
SOURCE_CONTENT_MIN_COVERAGE = 0.04
SOURCE_CONTENT_BIN_COUNT = 8
SOURCE_CONTENT_BIN_MIN_COVERAGE = 0.02
SOURCE_CONTENT_MIN_PASSING_BINS = 5


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


def _integer_tuple(value: Any, length: int, context: str) -> tuple[int, ...]:
    if not isinstance(value, list) or len(value) != length:
        raise RuntimeError(f"{context} must contain exactly {length} integers.")
    result: list[int] = []
    for component in value:
        if (
            isinstance(component, bool)
            or not isinstance(component, (int, float))
            or not float(component).is_integer()
        ):
            raise RuntimeError(f"{context} must contain exactly {length} integers.")
        result.append(int(component))
    return tuple(result)


def _source_content_metrics(image: Image.Image) -> tuple[float, list[float]]:
    band = image.convert("RGB").crop(SOURCE_CONTENT_BAND)
    source_width, source_height = band.size
    downsample = SOURCE_CONTENT_DOWNSAMPLE
    downsampled_width = source_width // downsample
    downsampled_height = source_height // downsample
    source_data = band.tobytes()
    downsampled = bytearray(downsampled_width * downsampled_height)

    # Use fixed 4x4 box averages and integer BT.601 luma so the Python and
    # Godot validators have identical sampling and rounding semantics.
    for output_y in range(downsampled_height):
        for output_x in range(downsampled_width):
            red_sum = 0
            green_sum = 0
            blue_sum = 0
            for block_y in range(downsample):
                source_offset = (
                    ((output_y * downsample + block_y) * source_width)
                    + output_x * downsample
                ) * 3
                for _block_x in range(downsample):
                    red_sum += source_data[source_offset]
                    green_sum += source_data[source_offset + 1]
                    blue_sum += source_data[source_offset + 2]
                    source_offset += 3
            weighted_sum = 299 * red_sum + 587 * green_sum + 114 * blue_sum
            downsampled[output_y * downsampled_width + output_x] = (
                weighted_sum + 8000
            ) // 16000

    structured_count = 0
    total_count = 0
    bin_structured = [0] * SOURCE_CONTENT_BIN_COUNT
    bin_totals = [0] * SOURCE_CONTENT_BIN_COUNT
    gradient_width = downsampled_width - 1
    gradient_height = downsampled_height - 1
    for y in range(gradient_height):
        for x in range(gradient_width):
            offset = y * downsampled_width + x
            gradient = max(
                abs(downsampled[offset + 1] - downsampled[offset]),
                abs(downsampled[offset + downsampled_width] - downsampled[offset]),
            )
            bin_index = min(
                SOURCE_CONTENT_BIN_COUNT - 1,
                x * SOURCE_CONTENT_BIN_COUNT // gradient_width,
            )
            total_count += 1
            bin_totals[bin_index] += 1
            if gradient >= SOURCE_CONTENT_GRADIENT_THRESHOLD:
                structured_count += 1
                bin_structured[bin_index] += 1

    global_coverage = structured_count / total_count
    bin_coverage = [
        bin_structured[index] / bin_totals[index]
        for index in range(SOURCE_CONTENT_BIN_COUNT)
    ]
    return global_coverage, bin_coverage


def _validate_source_content(image: Image.Image, path: Path) -> None:
    global_coverage, bin_coverage = _source_content_metrics(image)
    passing_bins = sum(
        coverage >= SOURCE_CONTENT_BIN_MIN_COVERAGE for coverage in bin_coverage
    )
    if (
        global_coverage < SOURCE_CONTENT_MIN_COVERAGE
        or passing_bins < SOURCE_CONTENT_MIN_PASSING_BINS
    ):
        formatted_bins = ", ".join(f"{coverage:.2%}" for coverage in bin_coverage)
        raise RuntimeError(
            f"R1 ArtCell source has insufficient authored structure: {path}; "
            f"global={global_coverage:.2%} (minimum "
            f"{SOURCE_CONTENT_MIN_COVERAGE:.2%}), passing_bins={passing_bins}/"
            f"{SOURCE_CONTENT_BIN_COUNT} (minimum "
            f"{SOURCE_CONTENT_MIN_PASSING_BINS}), bins=[{formatted_bins}]."
        )


def _validate_qa_visibility_cases(
    library: dict[str, Any], cells: list[dict[str, Any]]
) -> None:
    cases = library.get("qa_visibility_cases", [])
    if not isinstance(cases, list) or len(cases) != len(QA_VISIBILITY_CASES):
        raise RuntimeError("R1 requires exactly five qa_visibility_cases.")

    world_width, world_height = _pair(library["world_size"], "world_size")
    cell_width, cell_height = _pair(library["cell_size"], "cell_size")
    half_viewport = (
        QA_VIEWPORT_SIZE[0] / (2.0 * QA_CAMERA_ZOOM),
        QA_VIEWPORT_SIZE[1] / (2.0 * QA_CAMERA_ZOOM),
    )
    seen_ids: set[str] = set()
    for index, expected in enumerate(QA_VISIBILITY_CASES):
        case = cases[index]
        if not isinstance(case, dict):
            raise RuntimeError(f"qa_visibility_cases[{index}] must be an object.")
        if set(case) != {"id", "camera", "screen_roi"}:
            raise RuntimeError(
                f"qa_visibility_cases[{index}] must contain only id, camera and "
                "screen_roi."
            )
        case_id = str(case.get("id", ""))
        camera = _integer_tuple(case.get("camera", []), 2, f"{case_id}.camera")
        screen_roi = _integer_tuple(
            case.get("screen_roi", []), 4, f"{case_id}.screen_roi"
        )
        expected_id, expected_camera, expected_roi = expected
        if case_id != expected_id or case_id != str(cells[index].get("id", "")):
            raise RuntimeError(
                f"qa_visibility_cases[{index}] must target {expected_id}, got {case_id!r}."
            )
        if case_id in seen_ids:
            raise RuntimeError(f"Duplicated qa_visibility_cases id: {case_id}")
        seen_ids.add(case_id)
        if camera != expected_camera or screen_roi != expected_roi:
            raise RuntimeError(
                f"{case_id} QA anchor must remain camera={expected_camera}, "
                f"screen_roi={expected_roi}; got camera={camera}, "
                f"screen_roi={screen_roi}."
            )

        camera_x, camera_y = camera
        if not (
            camera_x - half_viewport[0] >= 0.0
            and camera_x + half_viewport[0] <= world_width
            and camera_y - half_viewport[1] >= 0.0
            and camera_y + half_viewport[1] <= world_height
        ):
            raise RuntimeError(f"{case_id} QA camera falls outside the R1 world.")
        roi_x, roi_y, roi_width, roi_height = screen_roi
        if not (
            roi_x >= 0
            and roi_y >= 0
            and roi_width > 0
            and roi_height > 0
            and roi_x + roi_width <= QA_VIEWPORT_SIZE[0]
            and roi_y + roi_height <= QA_VIEWPORT_SIZE[1]
        ):
            raise RuntimeError(f"{case_id} screen_roi falls outside the QA viewport.")

        cell_origin_x, cell_origin_y = _pair(
            cells[index].get("world_origin", []), f"{case_id}.world_origin"
        )
        world_roi = (
            camera_x - half_viewport[0] + roi_x / QA_CAMERA_ZOOM,
            camera_y - half_viewport[1] + roi_y / QA_CAMERA_ZOOM,
            camera_x
            - half_viewport[0]
            + (roi_x + roi_width) / QA_CAMERA_ZOOM,
            camera_y
            - half_viewport[1]
            + (roi_y + roi_height) / QA_CAMERA_ZOOM,
        )
        cell_right = min(cell_origin_x + cell_width, world_width)
        cell_bottom = min(cell_origin_y + cell_height, world_height)
        if not (
            world_roi[0] >= cell_origin_x
            and world_roi[1] >= cell_origin_y
            and world_roi[2] <= cell_right
            and world_roi[3] <= cell_bottom
        ):
            raise RuntimeError(
                f"{case_id} screen_roi does not project entirely inside its ArtCell."
            )


def _validate_library(library: dict[str, Any]) -> None:
    if int(library.get("schema_version", 0)) != 1:
        raise RuntimeError("Unsupported ArtCell library schema.")
    if int(library.get("visual_revision", 0)) != VISUAL_REVISION:
        raise RuntimeError(f"R1 visual_revision must remain {VISUAL_REVISION}.")
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
    expected_ids = [f"Background_{index:03d}" for index in range(1, 6)]
    seen_ids: set[str] = set()
    validated_cells: list[dict[str, Any]] = []
    previous_right_overlap: bytes | None = None
    for index, cell_variant in enumerate(cells):
        if not isinstance(cell_variant, dict):
            raise RuntimeError(f"ArtCell {index + 1} must be an object.")
        cell_id = str(cell_variant.get("id", ""))
        if not cell_id or cell_id in seen_ids:
            raise RuntimeError(f"ArtCell id is empty or duplicated: {cell_id!r}")
        if cell_id != expected_ids[index]:
            raise RuntimeError(
                f"ArtCell {index + 1} id must be {expected_ids[index]}, got {cell_id!r}."
            )
        seen_ids.add(cell_id)
        origin = _pair(cell_variant.get("world_origin", []), f"{cell_id}.world_origin")
        if origin != (expected_origins[index], 0):
            raise RuntimeError(
                f"{cell_id} origin must be {(expected_origins[index], 0)}, got {origin}."
            )
        path = _project_path(str(cell_variant.get("path", "")))
        if not path.is_file():
            raise RuntimeError(f"Missing ArtCell source: {path}")
        with Image.open(path) as opened:
            if opened.size != cell_size:
                raise RuntimeError(
                    f"{path} has size {opened.size}; expected constant {cell_size}."
                )
            image = opened.convert("RGBA")
        _validate_source_content(image, path)
        left_overlap = image.crop((0, 0, overlap, cell_size[1])).tobytes()
        if previous_right_overlap is not None and left_overlap != previous_right_overlap:
            raise RuntimeError(
                f"Adjacent R1 ArtCell overlap is not pixel-identical before {cell_id}."
            )
        previous_right_overlap = image.crop(
            (cell_size[0] - overlap, 0, cell_size[0], cell_size[1])
        ).tobytes()
        validated_cells.append(cell_variant)

    _validate_qa_visibility_cases(library, validated_cells)


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
