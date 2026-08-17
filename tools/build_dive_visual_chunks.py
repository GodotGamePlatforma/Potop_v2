#!/usr/bin/env python3
"""Build or verify the presentation-only underwater visual manifest v2.

The original schema-v1 manifest and its 15 PNG crops are frozen inputs.  This
builder adopts them by hash and never opens an archived composition master,
rewrites a crop, deletes stale files, or derives element transforms.  Placement,
rotation, scale, and stretch remain authored exclusively in the six-layer Godot
composition scene.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = PROJECT_ROOT / "assets/diving/world/map_v2/visual_chunks"
FROZEN_V1_PATH = OUTPUT_ROOT / "map_visual_chunks_v1.json"
MANIFEST_V2_PATH = OUTPUT_ROOT / "map_visual_chunks_v2.json"
COMPOSITION_SCENE_PATH = (
    PROJECT_ROOT / "scenes/diving/map_visuals/UnderwaterMapSixLayerVisuals.tscn"
)

FROZEN_V1_SHA256 = (
    "6d4d53bc005a7866d5e3597ca3e62840716260cdcf0eaa6dec906c6a40d8fcb6"
)
FROZEN_V1_LAYER_ID = "environment_decoration"
FROZEN_V1_CHUNK_COUNT = 15


@dataclass(frozen=True)
class VisualLayer:
    layer_id: str
    role: str
    profile_name: str


LAYERS = (
    VisualLayer("L00_base_color", "base_color", "l00_base_color.tres"),
    VisualLayer(
        "L01_ultra_far_silhouettes",
        "ultra_far_silhouettes",
        "l01_ultra_far_silhouettes.tres",
    ),
    VisualLayer("L02_far_structures", "far_structures", "l02_far_structures.tres"),
    VisualLayer("L03_mid_drift_props", "mid_drift_props", "l03_mid_drift_props.tres"),
    VisualLayer(
        "L04_near_terrain_skin",
        "near_terrain_skin",
        "l04_near_terrain_skin.tres",
    ),
    VisualLayer(
        "L05_foreground_occluders",
        "foreground_occluders",
        "l05_foreground_occluders.tres",
    ),
)

RECT_KEYS = ("source_rect", "texture_region", "world_rect")
FORBIDDEN_ELEMENT_KEYS = frozenset(
    {
        "position",
        "rotation",
        "rotation_degrees",
        "scale",
        "skew",
        "transform",
        "transform_2d",
        "z_index",
    }
)


class ManifestError(RuntimeError):
    """Raised when a frozen input or generated manifest violates the contract."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
    except OSError as exc:
        raise ManifestError(f"Cannot hash {path}: {exc}") from exc
    return digest.hexdigest()


def _res_path(path: Path) -> str:
    try:
        relative = path.resolve().relative_to(PROJECT_ROOT.resolve())
    except ValueError as exc:
        raise ManifestError(f"Path is outside the project: {path}") from exc
    return "res://" + relative.as_posix()


def _project_path(resource_path: str) -> Path:
    if not resource_path.startswith("res://"):
        raise ManifestError(f"Expected a res:// path, got {resource_path!r}.")
    resolved = (PROJECT_ROOT / resource_path.removeprefix("res://")).resolve()
    try:
        resolved.relative_to(PROJECT_ROOT.resolve())
    except ValueError as exc:
        raise ManifestError(f"Resource path escapes the project: {resource_path}") from exc
    return resolved


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ManifestError(f"Cannot read {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ManifestError(f"Invalid JSON in {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ManifestError(f"Expected a JSON object in {path}.")
    return value


def _require_int_list(value: Any, length: int, label: str) -> list[int]:
    if (
        not isinstance(value, list)
        or len(value) != length
        or any(isinstance(item, bool) or not isinstance(item, int) for item in value)
    ):
        raise ManifestError(f"{label} must contain exactly {length} integers.")
    return list(value)


def _validate_rect(value: Any, label: str) -> list[int]:
    rect = _require_int_list(value, 4, label)
    if rect[2] <= 0 or rect[3] <= 0:
        raise ManifestError(f"{label} must have positive width and height.")
    return rect


def _load_frozen_v1() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    actual_manifest_hash = _sha256(FROZEN_V1_PATH)
    if actual_manifest_hash != FROZEN_V1_SHA256:
        raise ManifestError(
            "Frozen schema-v1 manifest changed: "
            f"expected {FROZEN_V1_SHA256}, got {actual_manifest_hash}."
        )

    manifest = _read_json(FROZEN_V1_PATH)
    if manifest.get("schema_version") != 1:
        raise ManifestError("Frozen input must use schema_version 1.")
    world_size = _require_int_list(manifest.get("world_size"), 2, "v1.world_size")
    if world_size != [11_520, 6_480]:
        raise ManifestError(f"Unexpected v1 world_size: {world_size}.")

    layers = manifest.get("layers")
    if not isinstance(layers, list) or len(layers) != 1:
        raise ManifestError("Frozen v1 manifest must contain exactly one layer.")
    source_layer = layers[0]
    if not isinstance(source_layer, dict):
        raise ManifestError("Frozen v1 layer must be an object.")
    if source_layer.get("id") != FROZEN_V1_LAYER_ID:
        raise ManifestError(
            f"Unexpected frozen v1 layer id: {source_layer.get('id')!r}."
        )
    if source_layer.get("source_archived") is not True:
        raise ManifestError(
            "Frozen v1 source must remain marked archived; the builder will not open it."
        )

    chunks = source_layer.get("chunks")
    if not isinstance(chunks, list) or len(chunks) != FROZEN_V1_CHUNK_COUNT:
        raise ManifestError(
            f"Frozen v1 must contain exactly {FROZEN_V1_CHUNK_COUNT} chunks."
        )
    if source_layer.get("generated_chunk_count") != FROZEN_V1_CHUNK_COUNT:
        raise ManifestError("Frozen v1 generated_chunk_count is inconsistent.")

    adopted: list[dict[str, Any]] = []
    seen_keys: set[str] = set()
    seen_paths: set[str] = set()
    for index, raw_chunk in enumerate(chunks):
        label = f"v1.layers[0].chunks[{index}]"
        if not isinstance(raw_chunk, dict):
            raise ManifestError(f"{label} must be an object.")
        key = raw_chunk.get("key")
        resource_path = raw_chunk.get("path")
        expected_hash = raw_chunk.get("sha256")
        if not isinstance(key, str) or not key:
            raise ManifestError(f"{label}.key must be a non-empty string.")
        if key in seen_keys:
            raise ManifestError(f"Duplicate frozen chunk key: {key}.")
        if not isinstance(resource_path, str):
            raise ManifestError(f"{label}.path must be a string.")
        if resource_path in seen_paths:
            raise ManifestError(f"Duplicate frozen chunk path: {resource_path}.")
        if not isinstance(expected_hash, str) or len(expected_hash) != 64:
            raise ManifestError(f"{label}.sha256 must be a SHA-256 hex digest.")

        crop_path = _project_path(resource_path)
        expected_crop_root = (OUTPUT_ROOT / FROZEN_V1_LAYER_ID).resolve()
        try:
            crop_path.relative_to(expected_crop_root)
        except ValueError as exc:
            raise ManifestError(
                f"Frozen crop is outside its protected directory: {resource_path}."
            ) from exc
        if not crop_path.is_file():
            raise ManifestError(f"Frozen crop is missing: {resource_path}.")
        actual_hash = _sha256(crop_path)
        if actual_hash != expected_hash:
            raise ManifestError(
                f"Frozen crop changed: {resource_path}; "
                f"expected {expected_hash}, got {actual_hash}."
            )

        adopted_chunk = {
            "coord": _require_int_list(raw_chunk.get("coord"), 2, f"{label}.coord"),
            "key": key,
            "path": resource_path,
            "sha256": expected_hash,
        }
        for rect_key in RECT_KEYS:
            adopted_chunk[rect_key] = _validate_rect(
                raw_chunk.get(rect_key), f"{label}.{rect_key}"
            )
        adopted.append(adopted_chunk)
        seen_keys.add(key)
        seen_paths.add(resource_path)

    crop_root = (OUTPUT_ROOT / FROZEN_V1_LAYER_ID).resolve()
    actual_crop_paths = {
        _res_path(path) for path in crop_root.glob("chunk_*.png") if path.is_file()
    }
    if actual_crop_paths != seen_paths:
        missing = sorted(seen_paths - actual_crop_paths)
        unexpected = sorted(actual_crop_paths - seen_paths)
        raise ManifestError(
            "Frozen crop set differs from schema v1; "
            f"missing={missing}, unexpected={unexpected}."
        )

    return manifest, adopted


def _build_manifest() -> dict[str, Any]:
    v1, adopted_chunks = _load_frozen_v1()
    if not COMPOSITION_SCENE_PATH.is_file():
        raise ManifestError(
            "Six-layer composition scene is missing: "
            f"{_res_path(COMPOSITION_SCENE_PATH)}."
        )

    layer_records: list[dict[str, str]] = []
    for layer in LAYERS:
        profile_path = PROJECT_ROOT / "data/diving_visuals/layers" / layer.profile_name
        if not profile_path.is_file():
            raise ManifestError(f"Visual layer profile is missing: {_res_path(profile_path)}.")
        layer_records.append(
            {
                "id": layer.layer_id,
                "profile_path": _res_path(profile_path),
                "profile_sha256": _sha256(profile_path),
                "role": layer.role,
            }
        )

    manifest = {
        "composition_scene": {
            "path": _res_path(COMPOSITION_SCENE_PATH),
            "sha256": _sha256(COMPOSITION_SCENE_PATH),
        },
        "generator": "tools/build_dive_visual_chunks.py",
        "layers": layer_records,
        "payloads": [
            {
                "elements": adopted_chunks,
                "id": "legacy_environment_decoration",
                "legacy_rects_authority": "integrity_and_migration_only",
                "mode": "adopt_verify_only",
                "placement_authority": "composition_scene_elements",
                "source_layer_id": FROZEN_V1_LAYER_ID,
                "source_manifest": {
                    "path": _res_path(FROZEN_V1_PATH),
                    "sha256": FROZEN_V1_SHA256,
                },
                "target_layer": "L02_far_structures",
            }
        ],
        "schema_version": 2,
        "transform_authority": "composition_scene_only",
        "world_size": _require_int_list(v1.get("world_size"), 2, "v1.world_size"),
    }
    _validate_v2(manifest)
    return manifest


def _validate_v2(manifest: dict[str, Any]) -> None:
    if manifest.get("schema_version") != 2:
        raise ManifestError("Generated manifest must use schema_version 2.")
    if manifest.get("transform_authority") != "composition_scene_only":
        raise ManifestError("Element transforms must remain composition-scene authority.")
    if manifest.get("world_size") != [11_520, 6_480]:
        raise ManifestError("Generated manifest has an unexpected world_size.")

    composition = manifest.get("composition_scene")
    if not isinstance(composition, dict):
        raise ManifestError("composition_scene must be an object.")
    if composition.get("path") != _res_path(COMPOSITION_SCENE_PATH):
        raise ManifestError("composition_scene.path is not canonical.")
    if not isinstance(composition.get("sha256"), str):
        raise ManifestError("composition_scene.sha256 is missing.")

    layers = manifest.get("layers")
    if not isinstance(layers, list) or len(layers) != len(LAYERS):
        raise ManifestError("Generated manifest must contain exactly six layers.")
    actual_layer_ids = [item.get("id") for item in layers if isinstance(item, dict)]
    expected_layer_ids = [layer.layer_id for layer in LAYERS]
    if actual_layer_ids != expected_layer_ids:
        raise ManifestError(
            f"Layer order/identity mismatch: expected {expected_layer_ids}, "
            f"got {actual_layer_ids}."
        )
    for index, (record, expected_layer) in enumerate(zip(layers, LAYERS)):
        if not isinstance(record, dict):
            raise ManifestError(f"layers[{index}] must be an object.")
        expected_profile_path = _res_path(
            PROJECT_ROOT
            / "data/diving_visuals/layers"
            / expected_layer.profile_name
        )
        if record.get("role") != expected_layer.role:
            raise ManifestError(f"layers[{index}].role is not canonical.")
        if record.get("profile_path") != expected_profile_path:
            raise ManifestError(f"layers[{index}].profile_path is not canonical.")
        if not isinstance(record.get("profile_sha256"), str):
            raise ManifestError(f"layers[{index}].profile_sha256 is missing.")

    payloads = manifest.get("payloads")
    if not isinstance(payloads, list) or len(payloads) != 1:
        raise ManifestError("Generated manifest must contain one adopted payload.")
    payload = payloads[0]
    if not isinstance(payload, dict):
        raise ManifestError("Adopted payload must be an object.")
    if payload.get("mode") != "adopt_verify_only":
        raise ManifestError("Legacy payload must use adopt_verify_only mode.")
    if payload.get("target_layer") != "L02_far_structures":
        raise ManifestError("Legacy payload must target L02_far_structures.")
    if payload.get("placement_authority") != "composition_scene_elements":
        raise ManifestError("Legacy placement must remain scene-element authority.")
    if payload.get("legacy_rects_authority") != "integrity_and_migration_only":
        raise ManifestError("Legacy rects must not become runtime placement authority.")
    source_manifest = payload.get("source_manifest")
    if not isinstance(source_manifest, dict):
        raise ManifestError("Legacy source_manifest must be an object.")
    if source_manifest.get("path") != _res_path(FROZEN_V1_PATH):
        raise ManifestError("Legacy source_manifest.path is not canonical.")
    if source_manifest.get("sha256") != FROZEN_V1_SHA256:
        raise ManifestError("Legacy source_manifest.sha256 is not frozen v1.")

    elements = payload.get("elements")
    if not isinstance(elements, list) or len(elements) != FROZEN_V1_CHUNK_COUNT:
        raise ManifestError(
            f"Adopted payload must contain exactly {FROZEN_V1_CHUNK_COUNT} elements."
        )
    for index, element in enumerate(elements):
        if not isinstance(element, dict):
            raise ManifestError(f"payload element {index} must be an object.")
        forbidden = FORBIDDEN_ELEMENT_KEYS.intersection(element)
        if forbidden:
            raise ManifestError(
                f"payload element {index} contains scene-owned transform fields: "
                f"{sorted(forbidden)}."
            )
        for rect_key in RECT_KEYS:
            _validate_rect(element.get(rect_key), f"payload.elements[{index}].{rect_key}")


def _serialize(manifest: dict[str, Any]) -> bytes:
    return (
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")


def _atomic_write(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent, prefix=f".{path.name}.", suffix=".tmp"
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, path)
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise


def _print_summary(mode: str, manifest: dict[str, Any], status: str) -> None:
    payload = manifest["payloads"][0]
    print(
        json.dumps(
            {
                "adopted_payload_mode": payload["mode"],
                "composition_scene": manifest["composition_scene"]["path"],
                "frozen_crops_verified": len(payload["elements"]),
                "frozen_v1_sha256": FROZEN_V1_SHA256,
                "layers": [layer["id"] for layer in manifest["layers"]],
                "manifest": _res_path(MANIFEST_V2_PATH),
                "mode": mode,
                "status": status,
                "transform_authority": manifest["transform_authority"],
            },
            indent=2,
            sort_keys=True,
        )
    )


def _build() -> None:
    manifest = _build_manifest()
    content = _serialize(manifest)
    if MANIFEST_V2_PATH.is_file() and MANIFEST_V2_PATH.read_bytes() == content:
        status = "up_to_date"
    else:
        _atomic_write(MANIFEST_V2_PATH, content)
        status = "written_atomically"
    _print_summary("build", manifest, status)


def _check() -> None:
    manifest = _build_manifest()
    expected = _serialize(manifest)
    if not MANIFEST_V2_PATH.is_file():
        raise ManifestError(
            f"Generated manifest is missing: {_res_path(MANIFEST_V2_PATH)}."
        )
    actual = MANIFEST_V2_PATH.read_bytes()
    if actual != expected:
        raise ManifestError(
            "Generated manifest is stale or non-canonical; run "
            "tools/build_dive_visual_chunks.py --build."
        )
    _print_summary("check", manifest, "up_to_date")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--build",
        action="store_true",
        help="Validate frozen inputs and atomically write schema-v2 manifest.",
    )
    mode.add_argument(
        "--check",
        action="store_true",
        help="Validate inputs and manifest freshness without writing any file.",
    )
    args = parser.parse_args()

    try:
        if args.build:
            _build()
        else:
            _check()
    except ManifestError as exc:
        parser.exit(1, f"ERROR: {exc}\n")


if __name__ == "__main__":
    main()
