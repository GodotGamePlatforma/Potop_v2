#!/usr/bin/env python3
"""Build or verify the deterministic UnderwaterMap.tscn derivative."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import os
import re
import struct
import sys
import tempfile
import unicodedata
import zlib
from pathlib import Path
from typing import Any, Iterable


WORKBENCH_DIR = Path(__file__).resolve().parents[1]
MANIFEST_PATH = WORKBENCH_DIR / "map_manifest.json"
SCENE_PATH = WORKBENCH_DIR / "UnderwaterMap.tscn"
L05_GENERATED_DIR = WORKBENCH_DIR / "assets" / "generated" / "l05"
L05_GENERATED_PATHS = {
    "solid_mask": L05_GENERATED_DIR / "solid_mask.png",
    "open_water_mask": L05_GENERATED_DIR / "open_water_mask.png",
    "boundary_mask": L05_GENERATED_DIR / "boundary_mask.png",
    "full_map_guide": L05_GENERATED_DIR / "full_map_guide.png",
    "truth_package": L05_GENERATED_DIR / "truth_package.json",
}
L05_SHADER_PATH = "assets/shaders/l05_ground_masked.gdshader"
L05_SOLID_MASK_RESOURCE_PATH = (
    "res://underwater_map_workbench/assets/generated/l05/solid_mask.png"
)
L05_SHADER_RESOURCE_PATH = (
    "res://underwater_map_workbench/assets/shaders/l05_ground_masked.gdshader"
)

EXPECTED_LAYER_IDS = tuple(f"L{index:02d}" for index in range(11))
PARALLAX_LAYER_IDS = frozenset(("L01", "L02", "L08", "L09"))
NONBLOCKING_TEXTURE_LAYER_IDS = frozenset(("L01", "L02"))
GROUND_ANCHORED_BACKDROP_LAYER_IDS = frozenset(("L01", "L02"))
NONBLOCKING_BACKDROP_AFFORDANCE = "nonblocking_backdrop"
LAYER_KEYS = frozenset(
    (
        "id",
        "role",
        "space",
        "z_index",
        "parallax_scale",
        "enabled",
        "reserved",
        "affordance_policy",
        "geometry_role",
    )
)
VISUAL_ASSET_KEYS = frozenset(
    (
        "id",
        "layer_id",
        "kind",
        "path",
        "sha256",
        "pixel_size",
        "world_rect",
        "enabled",
        "affordance",
        "topology_digest",
    )
)
L05_MODE = "l05_mask_v1"
L05_SOURCE_FORMAT = "l05_rect_ops_v1"
L05_PIXEL_SIZE = (576, 324)
L05_WORLD_UNITS_PER_PIXEL = (40.0, 40.0)
L05_MAPPING = {
    "world_origin": [0, 0],
    "x_axis": "right",
    "y_axis": "down",
    "pixel_reference": "pixel_edge",
    "rounding": "floor",
}
REQUIRED_GAMEPLAY_COLLECTIONS = (
    "loot_spawns",
    "shortcut_spawns",
    "fixed_device_spawns",
    "connections",
    "pickups",
    "current_zones",
    "threat_spawns",
    "heavy_object_spawns",
    "rescue_spawns",
    "buoy_spawns",
    "obstacle_spawns",
    "decoration_spawns",
)
NON_SPATIAL_COLLECTIONS = frozenset(("connections",))
NO_BLOCKING_POLICY = "no_visual_blockage_in_protected_water"
MAP_SOURCE_VERSION = 5
REQUIRED_GRID_SIZE = (12, 12)
REQUIRED_GRID_CELL_SIZE = (1920.0, 1080.0)
REQUIRED_WORLD_SIZE = (23040.0, 12960.0)
REGION_PRESENTATION_FIELDS = frozenset(
    ("display_name", "water_color", "accent_color", "backdrop_path")
)
LANDMARK_PRESENTATION_FIELDS = frozenset(
    (
        "display_name",
        "short_name",
        "visual_kind",
        "visual_scene_path",
        "backdrop_path",
    )
)
GAMEPLAY_PRESENTATION_FIELDS = frozenset(
    (
        "display_name",
        "short_name",
        "label",
        "description",
        "visual_kind",
        "visual_scene_path",
        "visual_offset",
        "visual_scale",
        "visual_rotation",
        "visual_z_index",
        "texture_path",
        "material_path",
        "shader_path",
        "icon_path",
        "backdrop_path",
        "color",
        "modulate",
    )
)
CAMPAIGN_STAGE_CONTRACT = (
    ("j7", ("junction_j7",)),
    ("archive", ("archive_terminal",)),
    (
        "r3",
        ("r3_diagnostic_panel", "r3_generator"),
    ),
    (
        "c4",
        ("c4_switchboard", "c4_splitter_mount"),
    ),
)
CAMPAIGN_DEVICE_ORDER = tuple(
    device_id
    for _stage_id, device_ids in CAMPAIGN_STAGE_CONTRACT
    for device_id in device_ids
)
FORBIDDEN_LANDMARK_IDS = frozenset(("R1-09", "R3-04", "R4-06"))


class ManifestError(ValueError):
    pass


def _object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ManifestError(f"{label} must be an object")
    return value


def _array(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise ManifestError(f"{label} must be an array")
    return value


def _non_empty_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ManifestError(f"{label} must be a non-empty string")
    return value


def _boolean(value: Any, label: str) -> bool:
    if not isinstance(value, bool):
        raise ManifestError(f"{label} must be a boolean")
    return value


def _number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ManifestError(f"{label} must be a number")
    resolved = float(value)
    if not math.isfinite(resolved):
        raise ManifestError(f"{label} must be finite")
    return resolved


def _integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ManifestError(f"{label} must be an integer")
    return value


def _positive_number(value: Any, label: str) -> float:
    resolved = _number(value, label)
    if resolved <= 0.0:
        raise ManifestError(f"{label} must be positive")
    return resolved


def _positive_integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ManifestError(f"{label} must be a positive integer")
    return value


def _pair(value: Any, label: str) -> tuple[float, float]:
    if not isinstance(value, list) or len(value) != 2:
        raise ManifestError(f"{label} must be a two-number array")
    return (_number(value[0], f"{label}[0]"), _number(value[1], f"{label}[1]"))


def _rect(value: Any, label: str) -> tuple[float, float, float, float]:
    if not isinstance(value, list) or len(value) != 4:
        raise ManifestError(f"{label} must be a four-number array")
    return tuple(_number(component, f"{label}[{index}]") for index, component in enumerate(value))  # type: ignore[return-value]


def _color(value: Any, label: str) -> str:
    if not isinstance(value, str):
        raise ManifestError(f"{label} must be an RGB/RGBA hex string")
    normalized = value.strip().lstrip("#")
    if len(normalized) not in (6, 8) or any(character not in "0123456789abcdefABCDEF" for character in normalized):
        raise ManifestError(f"{label} must be an RGB/RGBA hex string")
    return normalized.lower()


def _sha256(value: Any, label: str, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise ManifestError(f"{label} must be a SHA-256 string")
    if allow_empty and value == "":
        return value
    if not re.fullmatch(r"[0-9a-f]{64}", value):
        raise ManifestError(f"{label} must be a lowercase SHA-256 string")
    return value


def _require_keys(record: dict[str, Any], keys: Iterable[str], label: str) -> None:
    missing = [key for key in keys if key not in record]
    if missing:
        raise ManifestError(f"{label} misses: {', '.join(missing)}")


def _package_asset_path(value: Any, label: str) -> tuple[str, Path]:
    path = _non_empty_string(value, label)
    if "\\" in path or not path.startswith("assets/"):
        raise ManifestError(f"{label} must be a package-relative assets/... path")
    parts = Path(path).parts
    if Path(path).is_absolute() or ".." in parts or "." in parts:
        raise ManifestError(f"{label} must not escape the workbench package")
    resolved = (WORKBENCH_DIR / Path(path)).resolve()
    try:
        resolved.relative_to(WORKBENCH_DIR.resolve())
    except ValueError as error:
        raise ManifestError(f"{label} must remain inside the workbench") from error
    return path, resolved


def _png_dimensions(raw: bytes, label: str) -> tuple[int, int]:
    if len(raw) < 24 or raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise ManifestError(f"{label} must be a PNG file")
    chunk_length = struct.unpack(">I", raw[8:12])[0]
    if raw[12:16] != b"IHDR" or chunk_length != 13 or len(raw) < 33:
        raise ManifestError(f"{label} has an invalid PNG IHDR")
    width, height = struct.unpack(">II", raw[16:24])
    if width <= 0 or height <= 0:
        raise ManifestError(f"{label} must have positive PNG dimensions")
    return width, height


def _read_hashed_png(
    path_value: Any,
    sha_value: Any,
    pixel_size_value: Any,
    label: str,
) -> tuple[str, Path, tuple[int, int]]:
    package_path, filesystem_path = _package_asset_path(path_value, f"{label}.path")
    if not filesystem_path.is_file():
        raise ManifestError(f"{label}.path does not exist: {package_path}")
    expected_sha = _sha256(sha_value, f"{label}.sha256")
    raw = filesystem_path.read_bytes()
    actual_sha = hashlib.sha256(raw).hexdigest()
    if actual_sha != expected_sha:
        raise ManifestError(
            f"{label}.sha256 is stale; expected {actual_sha} for {package_path}"
        )
    declared_size = _pair(pixel_size_value, f"{label}.pixel_size")
    if any(not component.is_integer() or component <= 0 for component in declared_size):
        raise ManifestError(f"{label}.pixel_size must contain positive integers")
    actual_size = _png_dimensions(raw, package_path)
    if actual_size != (int(declared_size[0]), int(declared_size[1])):
        raise ManifestError(
            f"{label}.pixel_size does not match PNG dimensions {actual_size}"
        )
    return package_path, filesystem_path, actual_size


def _validate_position(
    position: Any,
    label: str,
    world_size: tuple[float, float],
) -> tuple[float, float]:
    resolved = _pair(position, label)
    if resolved[0] < 0.0 or resolved[1] < 0.0:
        raise ManifestError(f"{label} lies outside the map")
    if resolved[0] >= world_size[0] or resolved[1] >= world_size[1]:
        raise ManifestError(f"{label} lies outside the map")
    return resolved


def _position_in_bounds(
    position: tuple[float, float],
    bounds: tuple[float, float, float, float],
) -> bool:
    x, y, width, height = bounds
    return x <= position[0] < x + width and y <= position[1] < y + height


def _canonical_sha256(value: Any) -> str:
    normalized = _normalize_canonical_numbers(value)
    try:
        encoded = json.dumps(
            normalized,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    except (TypeError, ValueError) as error:
        raise ManifestError(f"manifest cannot be canonicalized: {error}") from error
    return hashlib.sha256(encoded).hexdigest()


def _normalize_canonical_numbers(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            key: _normalize_canonical_numbers(nested)
            for key, nested in value.items()
        }
    if isinstance(value, list):
        return [_normalize_canonical_numbers(nested) for nested in value]
    if isinstance(value, bool) or value is None or isinstance(value, (str, int)):
        return value
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ManifestError("manifest canonical numbers must be finite")
        return int(value) if value.is_integer() else value
    return value


def _topology_identity_projection(manifest: dict[str, Any]) -> dict[str, Any]:
    topology = _object(manifest.get("topology"), "topology")
    if topology.get("mode") != L05_MODE:
        return copy.deepcopy(topology)
    collision = _object(topology.get("collision_source"), "topology.collision_source")
    return {
        "mode": topology.get("mode"),
        "authority_layer": topology.get("authority_layer"),
        "collision_source": {
            "format": collision.get("format"),
            "canonical_digest": collision.get("canonical_digest"),
            "pixel_size": copy.deepcopy(collision.get("pixel_size")),
            "world_units_per_pixel": copy.deepcopy(
                collision.get("world_units_per_pixel")
            ),
            "mapping": copy.deepcopy(collision.get("mapping")),
            "encoding": copy.deepcopy(collision.get("encoding")),
        },
        "protected_corridors": copy.deepcopy(topology.get("protected_corridors")),
    }


def _gameplay_signature(manifest: dict[str, Any]) -> str:
    payload = {
        "map": copy.deepcopy(manifest["map"]),
        "depth_profile": copy.deepcopy(manifest["depth_profile"]),
        "regions": [
            {
                key: copy.deepcopy(value)
                for key, value in region.items()
                if key not in REGION_PRESENTATION_FIELDS
                and not key.startswith("visual_")
            }
            for region in manifest["regions"]
        ],
        "topology": _topology_identity_projection(manifest),
        "entry": copy.deepcopy(manifest["entry"]),
        "exit": copy.deepcopy(manifest["exit"]),
        "landmarks": [
            {
                key: copy.deepcopy(value)
                for key, value in landmark.items()
                if key not in LANDMARK_PRESENTATION_FIELDS
                and not key.startswith("visual_")
            }
            for landmark in manifest["landmarks"]
        ],
        "gameplay": _gameplay_semantic_projection(manifest["gameplay"]),
        "campaign": copy.deepcopy(manifest["campaign"]),
    }
    return f"manifest-v2:{_canonical_sha256(payload)}"


def _presentation_fingerprint(manifest: dict[str, Any]) -> str:
    revision = _object(manifest.get("revision"), "revision")
    payload = {
        "presentation_revision": revision["presentation_revision"],
        "map": {
            "grid": copy.deepcopy(manifest["map"]["grid"]),
            "world_size": copy.deepcopy(manifest["map"]["world_size"]),
        },
        "regions": copy.deepcopy(manifest["regions"]),
        "landmarks": copy.deepcopy(manifest["landmarks"]),
        "topology": _topology_identity_projection(manifest),
        "gameplay": copy.deepcopy(manifest["gameplay"]),
        "campaign": copy.deepcopy(manifest["campaign"]),
        "visual": copy.deepcopy(manifest["visual"]),
    }
    return f"presentation-v2:{_canonical_sha256(payload)}"


def _gameplay_semantic_projection(gameplay: dict[str, Any]) -> dict[str, Any]:
    projection: dict[str, Any] = {}
    for collection_name, value in gameplay.items():
        if collection_name == "decoration_spawns":
            continue
        if not isinstance(value, list):
            projection[collection_name] = copy.deepcopy(value)
            continue
        projected_records: list[Any] = []
        for record in value:
            if not isinstance(record, dict):
                projected_records.append(copy.deepcopy(record))
                continue
            projected_records.append(
                {
                    key: copy.deepcopy(nested)
                    for key, nested in record.items()
                    if key not in GAMEPLAY_PRESENTATION_FIELDS
                    and not key.startswith("visual_")
                }
            )
        projection[collection_name] = projected_records
    return projection


def _iter_gameplay_collections(
    gameplay: dict[str, Any],
) -> Iterable[tuple[str, list[Any]]]:
    for key, value in gameplay.items():
        if key in ("tutorial_enabled", "tutorial_route"):
            continue
        if isinstance(value, list):
            yield key, value


def _validate_map(manifest: dict[str, Any]) -> tuple[float, float]:
    map_record = _object(manifest["map"], "map")
    _require_keys(
        map_record,
        ("id", "source_version", "grid", "navigation_cell_size", "world_size", "chunk_size"),
        "map",
    )
    _non_empty_string(map_record["id"], "map.id")
    if (
        isinstance(map_record["source_version"], bool)
        or not isinstance(map_record["source_version"], int)
        or map_record["source_version"] != MAP_SOURCE_VERSION
    ):
        raise ManifestError(
            f"map.source_version must be exactly {MAP_SOURCE_VERSION}"
        )
    _positive_integer(map_record["chunk_size"], "map.chunk_size")

    grid = _object(map_record["grid"], "map.grid")
    _require_keys(grid, ("columns", "rows", "cell_size"), "map.grid")
    columns = _positive_integer(grid["columns"], "map.grid.columns")
    rows = _positive_integer(grid["rows"], "map.grid.rows")
    cell_size = _pair(grid["cell_size"], "map.grid.cell_size")
    if min(cell_size) <= 0.0:
        raise ManifestError("map.grid.cell_size must be positive")
    if (columns, rows) != REQUIRED_GRID_SIZE:
        raise ManifestError("map.grid must be exactly 12 x 12")
    if cell_size != REQUIRED_GRID_CELL_SIZE:
        raise ManifestError("map.grid.cell_size must be exactly 1920 x 1080")

    world_size = _pair(map_record["world_size"], "map.world_size")
    expected_world_size = (columns * cell_size[0], rows * cell_size[1])
    if world_size != expected_world_size:
        raise ManifestError("map.world_size must equal the grid extent")
    if world_size != REQUIRED_WORLD_SIZE:
        raise ManifestError("map.world_size must be exactly 23040 x 12960")

    navigation_cell_size = _pair(
        map_record["navigation_cell_size"],
        "map.navigation_cell_size",
    )
    if min(navigation_cell_size) <= 0.0:
        raise ManifestError("map.navigation_cell_size must be positive")
    for extent, cell in zip(world_size, navigation_cell_size):
        quotient = extent / cell
        if not math.isclose(quotient, round(quotient), rel_tol=0.0, abs_tol=1.0e-9):
            raise ManifestError("map.navigation_cell_size must divide the world extent")
    return world_size


def _validate_revision(manifest: dict[str, Any]) -> None:
    revision = _object(manifest["revision"], "revision")
    _require_keys(
        revision,
        ("revision_id", "topology_revision", "presentation_revision"),
        "revision",
    )
    _non_empty_string(revision["revision_id"], "revision.revision_id")
    _non_empty_string(revision["topology_revision"], "revision.topology_revision")
    _non_empty_string(
        revision["presentation_revision"],
        "revision.presentation_revision",
    )


def _validate_regions(
    manifest: dict[str, Any],
    world_size: tuple[float, float],
) -> dict[str, tuple[float, float, float, float]]:
    regions = _array(manifest["regions"], "regions")
    if not regions:
        raise ManifestError("regions must contain at least one region")
    region_bounds: dict[str, tuple[float, float, float, float]] = {}
    for index, value in enumerate(regions):
        label = f"regions[{index}]"
        region = _object(value, label)
        _require_keys(
            region,
            ("id", "display_name", "bounds", "water_color", "accent_color"),
            label,
        )
        region_id = _non_empty_string(region["id"], f"{label}.id")
        if region_id == "exit" or region_id in region_bounds:
            raise ManifestError(f"{label}.id must be unique")
        _non_empty_string(region["display_name"], f"{label}.display_name")
        bounds = _rect(region["bounds"], f"{label}.bounds")
        if bounds[0] < 0.0 or bounds[1] < 0.0 or bounds[2] <= 0.0 or bounds[3] <= 0.0:
            raise ManifestError(f"{label}.bounds must be a positive map rectangle")
        if bounds[0] + bounds[2] > world_size[0] or bounds[1] + bounds[3] > world_size[1]:
            raise ManifestError(f"{label}.bounds lies outside the map")
        _color(region["water_color"], f"{label}.water_color")
        _color(region["accent_color"], f"{label}.accent_color")
        region_bounds[region_id] = bounds
    return region_bounds


def _validate_visual(
    manifest: dict[str, Any],
    world_size: tuple[float, float],
    topology_build: dict[str, Any],
) -> None:
    visual = _object(manifest["visual"], "visual")
    _require_keys(
        visual,
        (
            "water_color",
            "deep_water_color",
            "grid_color",
            "border_color",
            "station_color",
            "grid_width",
            "border_width",
            "layers",
            "assets",
        ),
        "visual",
    )
    for key in (
        "water_color",
        "deep_water_color",
        "grid_color",
        "border_color",
        "station_color",
    ):
        _color(visual[key], f"visual.{key}")
    _positive_number(visual["grid_width"], "visual.grid_width")
    _positive_number(visual["border_width"], "visual.border_width")
    if "diagnostic_grid_enabled" in visual:
        _boolean(
            visual["diagnostic_grid_enabled"],
            "visual.diagnostic_grid_enabled",
        )
    elif topology_build.get("mode") == L05_MODE:
        raise ManifestError(
            "visual.diagnostic_grid_enabled is required for l05_mask_v1"
        )

    layers = _array(visual["layers"], "visual.layers")
    if len(layers) != len(EXPECTED_LAYER_IDS):
        raise ManifestError("visual.layers must contain exactly L00-L10")
    previous_z_index: int | None = None
    for index, expected_id in enumerate(EXPECTED_LAYER_IDS):
        label = f"visual.layers[{index}]"
        layer = _object(layers[index], label)
        if set(layer) != LAYER_KEYS:
            raise ManifestError(
                f"{label} must contain exactly: {', '.join(sorted(LAYER_KEYS))}"
            )
        if layer["id"] != expected_id:
            raise ManifestError("visual.layers must be ordered exactly L00-L10")
        _non_empty_string(layer["role"], f"{label}.role")
        _boolean(layer["enabled"], f"{label}.enabled")
        _boolean(layer["reserved"], f"{label}.reserved")
        _non_empty_string(
            layer["affordance_policy"],
            f"{label}.affordance_policy",
        )
        _non_empty_string(layer["geometry_role"], f"{label}.geometry_role")
        z_index = _integer(layer["z_index"], f"{label}.z_index")
        if previous_z_index is not None and z_index <= previous_z_index:
            raise ManifestError("visual layer z_index values must be strictly increasing")
        previous_z_index = z_index
        parallax_scale = _pair(
            layer["parallax_scale"],
            f"{label}.parallax_scale",
        )
        if min(parallax_scale) <= 0.0:
            raise ManifestError(f"{label}.parallax_scale must be positive")
        if expected_id in PARALLAX_LAYER_IDS:
            if layer["space"] != "parallax":
                raise ManifestError(f"{label}.space must be parallax")
            if parallax_scale == (1.0, 1.0):
                raise ManifestError(f"{label}.parallax_scale must be differential")
            if (
                expected_id in GROUND_ANCHORED_BACKDROP_LAYER_IDS
                and parallax_scale[1] != 1.0
            ):
                raise ManifestError(
                    f"{label}.parallax_scale.y must be exactly 1 "
                    "for a ground-anchored backdrop"
                )
        else:
            if layer["space"] != "world_locked":
                raise ManifestError(f"{label}.space must be world_locked")
            if parallax_scale != (1.0, 1.0):
                raise ManifestError(f"{label}.parallax_scale must be [1, 1]")

        if expected_id == "L05":
            if (
                layer["role"] != "collider_authority"
                or layer["geometry_role"] != "collider_authority"
                or layer["affordance_policy"] != "collider_authority"
            ):
                raise ManifestError("L05 must be the collider authority")
            if not layer["enabled"] or layer["reserved"]:
                raise ManifestError("L05 must be enabled and not reserved")
        elif expected_id == "L10":
            if layer["enabled"] or not layer["reserved"]:
                raise ManifestError("L10 must be disabled and reserved")
            if layer["geometry_role"] != "none":
                raise ManifestError("L10 must not own geometry")
            if layer["affordance_policy"] != NO_BLOCKING_POLICY:
                raise ManifestError("L10 must preserve the protected-water policy")
        else:
            if not layer["enabled"] or layer["reserved"]:
                raise ManifestError(f"{expected_id} must be enabled and not reserved")
            if layer["geometry_role"] != "none":
                raise ManifestError(f"{expected_id} must not own collider geometry")
            if layer["affordance_policy"] != NO_BLOCKING_POLICY:
                raise ManifestError(
                    f"{expected_id} must preserve the protected-water policy"
                )

    assets = _array(visual["assets"], "visual.assets")
    asset_ids: set[str] = set()
    for index, asset_value in enumerate(assets):
        label = f"visual.assets[{index}]"
        asset = _object(asset_value, label)
        if set(asset) != VISUAL_ASSET_KEYS:
            raise ManifestError(
                f"{label} must contain exactly: "
                + ", ".join(sorted(VISUAL_ASSET_KEYS))
            )
        asset_id = _non_empty_string(asset["id"], f"{label}.id")
        if asset_id in asset_ids:
            raise ManifestError(f"{label}.id must be unique")
        asset_ids.add(asset_id)
        layer_id = _non_empty_string(asset["layer_id"], f"{label}.layer_id")
        kind = _non_empty_string(asset["kind"], f"{label}.kind")
        if (layer_id, kind) not in {
            ("L01", "texture_rect"),
            ("L02", "texture_rect"),
            ("L05", "collision_masked_material"),
        }:
            raise ManifestError(
                f"{label} must be L01-L02/texture_rect "
                "or L05/collision_masked_material"
            )
        _boolean(asset["enabled"], f"{label}.enabled")
        _non_empty_string(asset["affordance"], f"{label}.affordance")
        _, _, pixel_size = _read_hashed_png(
            asset["path"],
            asset["sha256"],
            asset["pixel_size"],
            label,
        )
        world_rect = _rect(asset["world_rect"], f"{label}.world_rect")
        if (
            world_rect[0] < 0.0
            or world_rect[1] < 0.0
            or world_rect[2] <= 0.0
            or world_rect[3] <= 0.0
            or world_rect[0] + world_rect[2] > world_size[0]
            or world_rect[1] + world_rect[3] > world_size[1]
        ):
            raise ManifestError(f"{label}.world_rect lies outside the map")
        topology_digest = asset["topology_digest"]
        if not isinstance(topology_digest, str):
            raise ManifestError(f"{label}.topology_digest must be a string")
        if layer_id in NONBLOCKING_TEXTURE_LAYER_IDS:
            if topology_digest != "":
                raise ManifestError(
                    f"{label} on {layer_id} requires an empty topology_digest"
                )
            if asset["affordance"] != NONBLOCKING_BACKDROP_AFFORDANCE:
                raise ManifestError(
                    f"{label} on {layer_id} requires "
                    f"affordance={NONBLOCKING_BACKDROP_AFFORDANCE}"
                )
            if pixel_size[0] * world_rect[3] != pixel_size[1] * world_rect[2]:
                raise ManifestError(
                    f"{label}.pixel_size aspect ratio must match world_rect "
                    "to prevent non-uniform stretching"
                )
        elif layer_id == "L05":
            if topology_build.get("mode") != L05_MODE:
                raise ManifestError(
                    f"{label} requires topology.mode={L05_MODE}"
                )
            if topology_digest != topology_build.get("canonical_digest"):
                raise ManifestError(
                    f"{label}.topology_digest must match collision_source.canonical_digest"
                )
            if world_rect != (0.0, 0.0, world_size[0], world_size[1]):
                raise ManifestError(
                    f"{label}.world_rect must cover the complete world"
                )
            shader_path = WORKBENCH_DIR / L05_SHADER_PATH
            if not shader_path.is_file():
                raise ManifestError(f"missing L05 shader: {L05_SHADER_PATH}")


def _validate_topology(
    manifest: dict[str, Any],
    world_size: tuple[float, float],
    *,
    verify_declarations: bool = True,
) -> dict[str, Any]:
    topology = _object(manifest["topology"], "topology")
    _require_keys(
        topology,
        ("mode", "authority_layer", "collision_source", "protected_corridors"),
        "topology",
    )
    mode = _non_empty_string(topology["mode"], "topology.mode")
    if mode not in ("open_world", L05_MODE):
        raise ManifestError(
            f"topology.mode must be open_world or {L05_MODE}"
        )
    if topology["authority_layer"] != "L05":
        raise ManifestError("topology.authority_layer must be L05")

    collision = _object(topology["collision_source"], "topology.collision_source")
    base_collision_keys = {
        "format",
        "path",
        "sha256",
        "pixel_size",
        "world_units_per_pixel",
        "encoding",
    }
    expected_collision_keys = (
        base_collision_keys
        if mode == "open_world"
        else base_collision_keys | {"canonical_digest", "mapping"}
    )
    if set(collision) != expected_collision_keys:
        raise ManifestError(
            "topology.collision_source must contain exactly: "
            + ", ".join(sorted(expected_collision_keys))
        )
    source_format = _non_empty_string(
        collision["format"],
        "topology.collision_source.format",
    )
    if not isinstance(collision["path"], str):
        raise ManifestError("topology.collision_source.path must be a string")
    pixel_size = _pair(
        collision["pixel_size"],
        "topology.collision_source.pixel_size",
    )
    world_units_per_pixel = _pair(
        collision["world_units_per_pixel"],
        "topology.collision_source.world_units_per_pixel",
    )
    encoding = _object(
        collision["encoding"],
        "topology.collision_source.encoding",
    )
    if set(encoding) != {"solid", "open_water"}:
        raise ManifestError(
            "topology.collision_source.encoding must contain exactly solid and open_water"
        )
    solid = encoding["solid"]
    open_water = encoding["open_water"]
    if (
        isinstance(solid, bool)
        or not isinstance(solid, int)
        or isinstance(open_water, bool)
        or not isinstance(open_water, int)
        or solid < 0
        or solid > 255
        or open_water < 0
        or open_water > 255
        or solid == open_water
    ):
        raise ManifestError(
            "topology.collision_source.encoding must use distinct 8-bit values"
        )

    if solid != 0 or open_water != 255:
        raise ManifestError(
            "collision encoding must use solid=0 and open_water=255"
        )

    topology_build: dict[str, Any]
    if mode == "open_world":
        if source_format != "none":
            raise ManifestError("open_world requires collision_source.format none")
        if collision["path"] != "" or collision["sha256"] != "":
            raise ManifestError("a none collision source must have empty path and sha256")
        if pixel_size != (0.0, 0.0) or world_units_per_pixel != (0.0, 0.0):
            raise ManifestError("a none collision source must have zero sizes")
        topology_build = {"mode": "open_world"}
    else:
        if source_format != L05_SOURCE_FORMAT:
            raise ManifestError(
                f"{L05_MODE} requires collision_source.format={L05_SOURCE_FORMAT}"
            )
        if pixel_size != tuple(float(value) for value in L05_PIXEL_SIZE):
            raise ManifestError(
                f"{L05_SOURCE_FORMAT} requires pixel_size={list(L05_PIXEL_SIZE)}"
            )
        if world_units_per_pixel != L05_WORLD_UNITS_PER_PIXEL:
            raise ManifestError(
                f"{L05_SOURCE_FORMAT} requires world_units_per_pixel="
                f"{list(L05_WORLD_UNITS_PER_PIXEL)}"
            )
        navigation_cell_size = _pair(
            _object(manifest["map"], "map")["navigation_cell_size"],
            "map.navigation_cell_size",
        )
        if navigation_cell_size != L05_WORLD_UNITS_PER_PIXEL:
            raise ManifestError(
                "map.navigation_cell_size must match the L05 40 x 40 pixel mapping"
            )
        if (
            pixel_size[0] * world_units_per_pixel[0],
            pixel_size[1] * world_units_per_pixel[1],
        ) != world_size:
            raise ManifestError("L05 pixel mapping must cover the complete world")
        mapping = _object(
            collision.get("mapping"),
            "topology.collision_source.mapping",
        )
        if mapping != L05_MAPPING:
            raise ManifestError(
                "topology.collision_source.mapping must exactly match the L05 v1 mapping"
            )
        package_path, payload_path = _package_asset_path(
            collision["path"],
            "topology.collision_source.path",
        )
        if not payload_path.is_file():
            raise ManifestError(f"L05 payload does not exist: {package_path}")
        payload_raw = payload_path.read_bytes()
        actual_payload_sha = hashlib.sha256(payload_raw).hexdigest()
        if verify_declarations:
            expected_payload_sha = _sha256(
                collision["sha256"],
                "topology.collision_source.sha256",
            )
            if actual_payload_sha != expected_payload_sha:
                raise ManifestError(
                    "topology.collision_source.sha256 is stale; "
                    f"expected {actual_payload_sha} for {package_path}"
                )
        try:
            payload = json.loads(payload_raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ManifestError(f"invalid L05 payload JSON: {error}") from error
        payload = _object(payload, "L05 payload")
        if set(payload) != {"schema_version", "base", "operations"}:
            raise ManifestError(
                "L05 payload must contain exactly schema_version, base and operations"
            )
        if payload["schema_version"] != 1:
            raise ManifestError("L05 payload schema_version must be 1")
        if payload["base"] != "open_water":
            raise ManifestError("L05 payload base must be open_water")
        operations = _array(payload["operations"], "L05 payload.operations")
        cells = bytearray([open_water]) * (L05_PIXEL_SIZE[0] * L05_PIXEL_SIZE[1])
        operation_ids: set[str] = set()
        for index, operation_value in enumerate(operations):
            label = f"L05 payload.operations[{index}]"
            operation = _object(operation_value, label)
            if set(operation) != {"id", "op", "rect_px"}:
                raise ManifestError(f"{label} must contain exactly id, op and rect_px")
            operation_id = _non_empty_string(operation["id"], f"{label}.id")
            if operation_id in operation_ids:
                raise ManifestError(f"{label}.id must be unique")
            operation_ids.add(operation_id)
            operation_kind = operation["op"]
            if operation_kind not in ("solid_rect", "open_rect"):
                raise ManifestError(
                    f"{label}.op must be solid_rect or open_rect"
                )
            rect_value = operation["rect_px"]
            if (
                not isinstance(rect_value, list)
                or len(rect_value) != 4
                or any(isinstance(value, bool) or not isinstance(value, int) for value in rect_value)
            ):
                raise ManifestError(f"{label}.rect_px must contain four integers")
            x, y, width, height = rect_value
            if x < 0 or y < 0 or width <= 0 or height <= 0:
                raise ManifestError(f"{label}.rect_px must be a positive raster rectangle")
            if x + width > L05_PIXEL_SIZE[0] or y + height > L05_PIXEL_SIZE[1]:
                raise ManifestError(f"{label}.rect_px lies outside the L05 raster")
            value = solid if operation_kind == "solid_rect" else open_water
            row_bytes = bytes([value]) * width
            for row in range(y, y + height):
                start = row * L05_PIXEL_SIZE[0] + x
                cells[start : start + width] = row_bytes
        digest_payload = {
            "mapping": copy.deepcopy(mapping),
            "encoding": copy.deepcopy(encoding),
            "pixel_size": list(L05_PIXEL_SIZE),
            "cells_hex": bytes(cells).hex(),
        }
        canonical_digest = f"topology-v1:{_canonical_sha256(digest_payload)}"
        declared_digest = collision["canonical_digest"]
        if verify_declarations:
            if (
                not isinstance(declared_digest, str)
                or not re.fullmatch(r"topology-v1:[0-9a-f]{64}", declared_digest)
            ):
                raise ManifestError(
                    "topology.collision_source.canonical_digest must be topology-v1:<sha256>"
                )
            if declared_digest != canonical_digest:
                raise ManifestError(
                    "topology.collision_source.canonical_digest is stale; "
                    f"expected {canonical_digest}"
                )
        topology_build = {
            "mode": L05_MODE,
            "payload_path": package_path,
            "payload_sha256": actual_payload_sha,
            "canonical_digest": canonical_digest,
            "pixel_size": L05_PIXEL_SIZE,
            "world_units_per_pixel": L05_WORLD_UNITS_PER_PIXEL,
            "mapping": copy.deepcopy(mapping),
            "encoding": copy.deepcopy(encoding),
            "cells": bytes(cells),
        }

    corridors = _array(
        topology["protected_corridors"],
        "topology.protected_corridors",
    )
    corridor_ids: set[str] = set()
    for index, value in enumerate(corridors):
        label = f"topology.protected_corridors[{index}]"
        corridor = _object(value, label)
        _require_keys(corridor, ("id", "points", "clearance"), label)
        corridor_id = _non_empty_string(corridor["id"], f"{label}.id")
        if corridor_id in corridor_ids:
            raise ManifestError(f"{label}.id must be unique")
        corridor_ids.add(corridor_id)
        points = _array(corridor["points"], f"{label}.points")
        if len(points) < 2:
            raise ManifestError(f"{label}.points must contain at least two points")
        for point_index, point in enumerate(points):
            _validate_position(
                point,
                f"{label}.points[{point_index}]",
                world_size,
            )
        _positive_number(corridor["clearance"], f"{label}.clearance")
    return topology_build


def _validate_depth_profile(manifest: dict[str, Any]) -> None:
    depth_profile = _array(manifest["depth_profile"], "depth_profile")
    if len(depth_profile) != 5:
        raise ManifestError("depth_profile must contain exactly five points")
    resolved = [
        _pair(point, f"depth_profile[{index}]")
        for index, point in enumerate(depth_profile)
    ]
    if resolved[0] != (0.0, 8.0) or resolved[-1] != (1.0, 160.0):
        raise ManifestError(
            "depth_profile endpoints must be exactly [0, 8] and [1, 160]"
        )
    if any(point[0] < 0.0 or point[0] > 1.0 or point[1] < 0.0 for point in resolved):
        raise ManifestError("depth_profile points must use normalized x and non-negative depth")
    if any(
        resolved[index][0] <= resolved[index - 1][0]
        or resolved[index][1] <= resolved[index - 1][1]
        for index in range(1, len(resolved))
    ):
        raise ManifestError("depth_profile coordinates must be strictly increasing")


def _validate_landmarks(
    manifest: dict[str, Any],
    world_size: tuple[float, float],
    region_bounds: dict[str, tuple[float, float, float, float]],
) -> tuple[dict[str, dict[str, Any]], set[str]]:
    landmarks = _array(manifest["landmarks"], "landmarks")
    by_id: dict[str, dict[str, Any]] = {}
    for index, value in enumerate(landmarks):
        label = f"landmarks[{index}]"
        landmark = _object(value, label)
        _require_keys(
            landmark,
            (
                "id",
                "display_name",
                "short_name",
                "region_id",
                "position",
                "size",
                "role",
            ),
            label,
        )
        landmark_id = _non_empty_string(landmark["id"], f"{label}.id")
        if landmark_id in FORBIDDEN_LANDMARK_IDS:
            raise ManifestError(f"{label}.id uses forbidden legacy ID {landmark_id}")
        if landmark_id == "exit" or landmark_id in by_id or landmark_id in region_bounds:
            raise ManifestError(f"{label}.id must be globally unique")
        _non_empty_string(landmark["display_name"], f"{label}.display_name")
        _non_empty_string(landmark["short_name"], f"{label}.short_name")
        _non_empty_string(landmark["role"], f"{label}.role")
        region_id = _non_empty_string(landmark["region_id"], f"{label}.region_id")
        if region_id not in region_bounds:
            raise ManifestError(f"{label}.region_id references an unknown region")
        position = _validate_position(
            landmark["position"],
            f"{label}.position",
            world_size,
        )
        if not _position_in_bounds(position, region_bounds[region_id]):
            raise ManifestError(f"{label}.position lies outside its region")
        size = _pair(landmark["size"], f"{label}.size")
        if min(size) <= 0.0:
            raise ManifestError(f"{label}.size must be positive")
        by_id[landmark_id] = landmark
    return by_id, set(by_id)


def _validate_item_contents(value: Any, label: str) -> dict[str, int]:
    contents = _object(value, label)
    if not contents:
        raise ManifestError(f"{label} must not be empty")
    for item_id, amount in contents.items():
        _non_empty_string(item_id, f"{label} item id")
        _positive_integer(amount, f"{label}.{item_id}")
    return contents


def _ordered_subsequence(needle: list[str], haystack: list[str]) -> bool:
    position = 0
    for value in haystack:
        if position < len(needle) and value == needle[position]:
            position += 1
    return position == len(needle)


def _validate_gameplay(
    manifest: dict[str, Any],
    world_size: tuple[float, float],
    landmarks_by_id: dict[str, dict[str, Any]],
    landmark_ids: set[str],
    region_ids: set[str],
) -> dict[str, dict[str, Any]]:
    gameplay = _object(manifest["gameplay"], "gameplay")
    _require_keys(
        gameplay,
        ("tutorial_enabled", "tutorial_route", *REQUIRED_GAMEPLAY_COLLECTIONS),
        "gameplay",
    )
    tutorial_enabled = _boolean(
        gameplay["tutorial_enabled"],
        "gameplay.tutorial_enabled",
    )
    route_values = _array(gameplay["tutorial_route"], "gameplay.tutorial_route")
    route = [
        _non_empty_string(value, f"gameplay.tutorial_route[{index}]")
        for index, value in enumerate(route_values)
    ]
    for collection_name in REQUIRED_GAMEPLAY_COLLECTIONS:
        _array(gameplay[collection_name], f"gameplay.{collection_name}")
    if (
        manifest["topology"]["mode"] == "open_world"
        and gameplay["obstacle_spawns"]
    ):
        raise ManifestError("open_world requires gameplay.obstacle_spawns to be empty")

    records_by_id: dict[str, dict[str, Any]] = {}
    collection_by_id: dict[str, str] = {}
    all_ids = set(landmark_ids) | region_ids
    all_ids.add("exit")
    for collection_name, records in _iter_gameplay_collections(gameplay):
        for index, value in enumerate(records):
            label = f"gameplay.{collection_name}[{index}]"
            record = _object(value, label)
            record_id = _non_empty_string(record.get("id"), f"{label}.id")
            if record_id in all_ids:
                raise ManifestError(f"{label}.id must be globally unique")
            all_ids.add(record_id)
            records_by_id[record_id] = record
            collection_by_id[record_id] = collection_name
            if collection_name not in NON_SPATIAL_COLLECTIONS and "position" not in record:
                raise ManifestError(f"{label}.position is required")
            if collection_name == "connections":
                _require_keys(record, ("from_id", "to_id", "path_points"), label)
                path_points = _array(record["path_points"], f"{label}.path_points")
                if len(path_points) < 2:
                    raise ManifestError(
                        f"{label}.path_points must contain at least two points"
                    )
                for point_index, point in enumerate(path_points):
                    _validate_position(
                        point,
                        f"{label}.path_points[{point_index}]",
                        world_size,
                    )
            if "position" in record:
                _validate_position(record["position"], f"{label}.position", world_size)
            if "contents" in record:
                _validate_item_contents(record["contents"], f"{label}.contents")

    for collection_name, records in _iter_gameplay_collections(gameplay):
        for index, value in enumerate(records):
            record = _object(value, f"gameplay.{collection_name}[{index}]")
            for reference_key in ("landmark_id", "connection_id", "from_id", "to_id"):
                if reference_key not in record or record[reference_key] == "":
                    continue
                reference = _non_empty_string(
                    record[reference_key],
                    f"gameplay.{collection_name}[{index}].{reference_key}",
                )
                if reference_key == "connection_id":
                    if collection_by_id.get(reference) != "connections":
                        raise ManifestError(
                            f"gameplay.{collection_name}[{index}].connection_id "
                            "must reference gameplay.connections"
                        )
                elif reference_key == "landmark_id" or (
                    collection_name == "connections"
                    and reference_key in ("from_id", "to_id")
                ):
                    if reference not in landmark_ids:
                        raise ManifestError(
                            f"gameplay.{collection_name}[{index}].{reference_key} "
                            "references an unknown landmark"
                        )
                elif reference not in all_ids:
                    raise ManifestError(
                        f"gameplay.{collection_name}[{index}].{reference_key} "
                        "references an unknown manifest ID"
                    )
            if collection_name == "fixed_device_spawns":
                prerequisite_values = _array(
                    record.get("prerequisite_device_ids"),
                    f"gameplay.{collection_name}[{index}].prerequisite_device_ids",
                )
                seen_prerequisites: set[str] = set()
                for prerequisite_index, value in enumerate(prerequisite_values):
                    prerequisite_id = _non_empty_string(
                        value,
                        f"gameplay.{collection_name}[{index}]."
                        f"prerequisite_device_ids[{prerequisite_index}]",
                    )
                    if prerequisite_id == record["id"]:
                        raise ManifestError(
                            f"gameplay.{collection_name}[{index}] cannot depend on itself"
                        )
                    if prerequisite_id in seen_prerequisites:
                        raise ManifestError(
                            f"gameplay.{collection_name}[{index}] has duplicate prerequisites"
                        )
                    if collection_by_id.get(prerequisite_id) != "fixed_device_spawns":
                        raise ManifestError(
                            f"gameplay.{collection_name}[{index}] prerequisite "
                            f"{prerequisite_id} must reference a fixed device"
                        )
                    seen_prerequisites.add(prerequisite_id)

    if any(route_id not in all_ids for route_id in route):
        raise ManifestError("gameplay.tutorial_route references an unknown manifest ID")

    if tutorial_enabled:
        entry_landmark_id = _non_empty_string(
            manifest["entry"].get("landmark_id"),
            "entry.landmark_id",
        )
        required_landmark = landmarks_by_id.get(entry_landmark_id)
        if required_landmark is None or required_landmark.get("role") != "dive_station":
            raise ManifestError(
                "tutorial_enabled requires entry.landmark_id to reference role dive_station"
            )
        required_collections = {
            "tutorial_market_crate": "loot_spawns",
            "tutorial_workshop_case": "loot_spawns",
            "SC-01": "shortcut_spawns",
            "junction_j7": "fixed_device_spawns",
        }
        for required_id, expected_collection in required_collections.items():
            if required_id not in records_by_id:
                raise ManifestError(f"tutorial_enabled requires ID {required_id}")
            if collection_by_id[required_id] != expected_collection:
                raise ManifestError(
                    f"{required_id} must be in gameplay.{expected_collection}"
                )

        market = records_by_id["tutorial_market_crate"]
        workshop = records_by_id["tutorial_workshop_case"]
        if market.get("mandatory_order") != 0 or workshop.get("mandatory_order") != 1:
            raise ManifestError("tutorial loot must preserve mandatory order 0 then 1")
        market_contents = _validate_item_contents(
            market.get("contents"),
            "tutorial_market_crate.contents",
        )
        workshop_contents = _validate_item_contents(
            workshop.get("contents"),
            "tutorial_workshop_case.contents",
        )
        if market_contents.get("food", 0) < 6:
            raise ManifestError("tutorial_market_crate must contain at least 6 food")
        for item_id, minimum in (("fabric_rubber", 2), ("planks", 4), ("scrap", 3)):
            if workshop_contents.get(item_id, 0) < minimum:
                raise ManifestError(
                    f"tutorial_workshop_case must contain at least {minimum} {item_id}"
                )

        shortcut = records_by_id["SC-01"]
        if shortcut.get("required_tool") != "knife":
            raise ManifestError("SC-01 must require the knife")
        if shortcut.get("interaction_action") != "cut":
            raise ManifestError("SC-01 must use the cut interaction")
        junction = records_by_id["junction_j7"]
        if junction.get("available_from_day") != 3:
            raise ManifestError("junction_j7 must become available on day 3")
        if junction.get("interaction_action") != "activate":
            raise ManifestError("junction_j7 must use the activate interaction")

        required_route = [
            entry_landmark_id,
            "tutorial_market_crate",
            "tutorial_workshop_case",
            "SC-01",
            "junction_j7",
            "exit",
        ]
        if not _ordered_subsequence(required_route, route):
            raise ManifestError(
                "tutorial_route must preserve the required tutorial ID order"
            )
    return records_by_id


def _validate_campaign(
    manifest: dict[str, Any],
    landmarks_by_id: dict[str, dict[str, Any]],
) -> None:
    campaign = _object(manifest["campaign"], "campaign")
    _require_keys(campaign, ("contract_id", "stages"), "campaign")
    if campaign["contract_id"] != "common_line_v1":
        raise ManifestError("campaign.contract_id must be common_line_v1")
    stages = _array(campaign["stages"], "campaign.stages")
    if len(stages) != len(CAMPAIGN_STAGE_CONTRACT):
        raise ManifestError("campaign.stages must contain exactly j7, archive, r3 and c4")

    fixed_devices = {
        str(record["id"]): record
        for record in manifest["gameplay"]["fixed_device_spawns"]
    }
    flattened_device_ids: list[str] = []
    for index, expected in enumerate(CAMPAIGN_STAGE_CONTRACT):
        expected_stage_id, expected_device_ids = expected
        label = f"campaign.stages[{index}]"
        stage = _object(stages[index], label)
        _require_keys(stage, ("id", "landmark_id", "fixed_device_ids"), label)
        stage_id = _non_empty_string(stage["id"], f"{label}.id")
        if stage_id != expected_stage_id:
            raise ManifestError(
                "campaign stage order must be exactly j7, archive, r3, c4"
            )
        landmark_id = _non_empty_string(
            stage["landmark_id"],
            f"{label}.landmark_id",
        )
        if landmark_id not in landmarks_by_id:
            raise ManifestError(
                f"campaign stage {stage_id} references unknown landmark {landmark_id}"
            )
        device_values = _array(
            stage["fixed_device_ids"],
            f"{label}.fixed_device_ids",
        )
        device_ids = tuple(
            _non_empty_string(value, f"{label}.fixed_device_ids[{device_index}]")
            for device_index, value in enumerate(device_values)
        )
        if device_ids != expected_device_ids:
            raise ManifestError(
                f"campaign stage {stage_id} has an invalid fixed-device sequence"
            )
        flattened_device_ids.extend(device_ids)
        for device_id in device_ids:
            device = fixed_devices.get(device_id)
            if device is None:
                raise ManifestError(
                    f"campaign device {device_id} is missing from fixed_device_spawns"
                )
            if device.get("landmark_id") != landmark_id:
                raise ManifestError(
                    f"campaign device {device_id} must reference landmark {landmark_id}"
                )

    if tuple(flattened_device_ids) != CAMPAIGN_DEVICE_ORDER:
        raise ManifestError("campaign fixed-device order is invalid")
    previous_device_id: str | None = None
    for device_id in CAMPAIGN_DEVICE_ORDER:
        device = fixed_devices[device_id]
        prerequisites = _array(
            device.get("prerequisite_device_ids"),
            f"fixed device {device_id}.prerequisite_device_ids",
        )
        expected_prerequisites = (
            [] if previous_device_id is None else [previous_device_id]
        )
        if prerequisites != expected_prerequisites:
            raise ManifestError(
                f"campaign device {device_id} must have prerequisites "
                f"{expected_prerequisites}"
            )
        previous_device_id = device_id


def _validate_entry_exit(
    manifest: dict[str, Any],
    world_size: tuple[float, float],
    landmark_ids: set[str],
) -> None:
    entry = _object(manifest["entry"], "entry")
    exit_record = _object(manifest["exit"], "exit")
    _require_keys(entry, ("landmark_id", "position"), "entry")
    _require_keys(exit_record, ("position",), "exit")
    landmark_id = _non_empty_string(entry["landmark_id"], "entry.landmark_id")
    if landmark_id not in landmark_ids:
        raise ManifestError("entry.landmark_id references an unknown landmark")
    _validate_position(entry["position"], "entry.position", world_size)
    _validate_position(exit_record["position"], "exit.position", world_size)


def load_and_validate_manifest() -> tuple[
    dict[str, Any], str, str, str, dict[str, Any]
]:
    raw = MANIFEST_PATH.read_bytes()
    try:
        manifest = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ManifestError(f"invalid JSON: {error}") from error
    if not isinstance(manifest, dict):
        raise ManifestError("manifest root must be an object")
    _require_keys(
        manifest,
        (
            "schema_version",
            "revision",
            "map",
            "visual",
            "depth_profile",
            "regions",
            "topology",
            "entry",
            "exit",
            "landmarks",
            "gameplay",
            "campaign",
        ),
        "manifest",
    )
    if manifest["schema_version"] != 2:
        raise ManifestError("schema_version must be 2")
    if "region" in manifest:
        raise ManifestError("schema_version 2 uses regions; legacy region is not allowed")

    _validate_revision(manifest)
    world_size = _validate_map(manifest)
    region_bounds = _validate_regions(manifest, world_size)
    topology_build = _validate_topology(manifest, world_size)
    _validate_visual(manifest, world_size, topology_build)
    _validate_depth_profile(manifest)
    landmarks_by_id, landmark_ids = _validate_landmarks(
        manifest,
        world_size,
        region_bounds,
    )
    _validate_entry_exit(manifest, world_size, landmark_ids)
    _validate_gameplay(
        manifest,
        world_size,
        landmarks_by_id,
        landmark_ids,
        set(region_bounds),
    )
    _validate_campaign(manifest, landmarks_by_id)

    manifest_sha = hashlib.sha256(raw).hexdigest()
    return (
        manifest,
        manifest_sha,
        _gameplay_signature(manifest),
        _presentation_fingerprint(manifest),
        topology_build,
    )


def _gd_number(value: Any) -> str:
    resolved = float(value)
    if resolved.is_integer():
        return str(int(resolved))
    return format(resolved, ".8g")


def _gd_vector(value: Any, label: str) -> str:
    x, y = _pair(value, label)
    return f"Vector2({_gd_number(x)}, {_gd_number(y)})"


def _gd_color(value: Any, label: str, alpha_override: int | None = None) -> str:
    normalized = _color(value, label)
    red = int(normalized[0:2], 16) / 255.0
    green = int(normalized[2:4], 16) / 255.0
    blue = int(normalized[4:6], 16) / 255.0
    alpha = int(normalized[6:8], 16) / 255.0 if len(normalized) == 8 else 1.0
    if alpha_override is not None:
        alpha = alpha_override / 255.0
    return "Color(%s, %s, %s, %s)" % tuple(
        _gd_number(component) for component in (red, green, blue, alpha)
    )


def _gd_points(points: Iterable[tuple[float, float]]) -> str:
    flattened = ", ".join(
        _gd_number(component)
        for point in points
        for component in point
    )
    return f"PackedVector2Array({flattened})"


def _gd_string(value: Any) -> str:
    return json.dumps(str(value), ensure_ascii=False)


def _gd_variant(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return _gd_string(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return _gd_number(value)
    if isinstance(value, list):
        return "[" + ", ".join(_gd_variant(item) for item in value) + "]"
    if isinstance(value, dict):
        pairs = (
            f"{_gd_string(key)}: {_gd_variant(value[key])}"
            for key in sorted(value)
        )
        return "{" + ", ".join(pairs) + "}"
    raise ManifestError(f"cannot serialize {type(value).__name__} to a scene variant")


def _png_chunk(chunk_type: bytes, payload: bytes) -> bytes:
    checksum = zlib.crc32(chunk_type)
    checksum = zlib.crc32(payload, checksum) & 0xFFFFFFFF
    return (
        struct.pack(">I", len(payload))
        + chunk_type
        + payload
        + struct.pack(">I", checksum)
    )


def _encode_png_gray8(width: int, height: int, pixels: bytes) -> bytes:
    if len(pixels) != width * height:
        raise ManifestError("grayscale PNG payload has an invalid size")
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        start = y * width
        rows.extend(pixels[start : start + width])
    header = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", header)
        + _png_chunk(b"IDAT", zlib.compress(bytes(rows), level=9))
        + _png_chunk(b"IEND", b"")
    )


def _encode_png_rgba8(width: int, height: int, pixels: bytes) -> bytes:
    if len(pixels) != width * height * 4:
        raise ManifestError("RGBA PNG payload has an invalid size")
    rows = bytearray()
    row_width = width * 4
    for y in range(height):
        rows.append(0)
        start = y * row_width
        rows.extend(pixels[start : start + row_width])
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", header)
        + _png_chunk(b"IDAT", zlib.compress(bytes(rows), level=9))
        + _png_chunk(b"IEND", b"")
    )


def _l05_boundary_mask(cells: bytes, width: int, height: int) -> bytes:
    boundary = bytearray(width * height)
    for y in range(height):
        for x in range(width):
            index = y * width + x
            value = cells[index]
            for neighbor_x, neighbor_y in (
                (x - 1, y),
                (x + 1, y),
                (x, y - 1),
                (x, y + 1),
            ):
                if (
                    0 <= neighbor_x < width
                    and 0 <= neighbor_y < height
                    and cells[neighbor_y * width + neighbor_x] != value
                ):
                    boundary[index] = 255
                    break
    return bytes(boundary)


def _render_l05_artifacts(
    topology_build: dict[str, Any],
    manifest_sha: str,
) -> dict[Path, bytes]:
    if topology_build.get("mode") != L05_MODE:
        return {}
    width, height = topology_build["pixel_size"]
    cells: bytes = topology_build["cells"]
    solid_value = int(topology_build["encoding"]["solid"])
    open_water_value = int(topology_build["encoding"]["open_water"])
    solid_mask = bytes(255 if value == solid_value else 0 for value in cells)
    open_water_mask = bytes(
        255 if value == open_water_value else 0 for value in cells
    )
    boundary_mask = _l05_boundary_mask(cells, width, height)
    guide = bytearray(width * height * 4)
    for index, value in enumerate(cells):
        if boundary_mask[index] == 255:
            color = (255, 0, 255, 255)
        elif value == solid_value:
            color = (0, 0, 0, 255)
        else:
            color = (0, 255, 255, 255)
        start = index * 4
        guide[start : start + 4] = bytes(color)
    artifacts = {
        L05_GENERATED_PATHS["solid_mask"]: _encode_png_gray8(
            width, height, solid_mask
        ),
        L05_GENERATED_PATHS["open_water_mask"]: _encode_png_gray8(
            width, height, open_water_mask
        ),
        L05_GENERATED_PATHS["boundary_mask"]: _encode_png_gray8(
            width, height, boundary_mask
        ),
        L05_GENERATED_PATHS["full_map_guide"]: _encode_png_rgba8(
            width, height, bytes(guide)
        ),
    }
    artifact_records = {}
    for name in (
        "solid_mask",
        "open_water_mask",
        "boundary_mask",
        "full_map_guide",
    ):
        path = L05_GENERATED_PATHS[name]
        artifact_records[name] = {
            "path": path.relative_to(WORKBENCH_DIR).as_posix(),
            "sha256": hashlib.sha256(artifacts[path]).hexdigest(),
        }
    truth_package = {
        "generated": True,
        "authority": False,
        "manifest_sha256": manifest_sha,
        "payload_path": topology_build["payload_path"],
        "payload_sha256": topology_build["payload_sha256"],
        "canonical_digest": topology_build["canonical_digest"],
        "pixel_size": list(topology_build["pixel_size"]),
        "world_units_per_pixel": list(topology_build["world_units_per_pixel"]),
        "mapping": copy.deepcopy(topology_build["mapping"]),
        "encoding": copy.deepcopy(topology_build["encoding"]),
        "solid_cell_count": sum(value == solid_value for value in cells),
        "open_water_cell_count": sum(value == open_water_value for value in cells),
        "artifacts": artifact_records,
    }
    artifacts[L05_GENERATED_PATHS["truth_package"]] = (
        json.dumps(
            truth_package,
            ensure_ascii=False,
            sort_keys=True,
            indent=2,
        )
        + "\n"
    ).encode("utf-8")
    return artifacts


def _safe_node_name(value: str) -> str:
    ascii_value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    sanitized = re.sub(r"[^A-Za-z0-9_]+", "_", ascii_value).strip("_")
    return sanitized or "Record"


def _append_layer_root(lines: list[str], layer: dict[str, Any]) -> None:
    layer_id = str(layer["id"])
    node_type = "Parallax2D" if layer["space"] == "parallax" else "Node2D"
    scale_label = f"visual.layers.{layer_id}.parallax_scale"
    lines.extend(
        (
            "",
            f'[node name="{layer_id}" type="{node_type}" parent="VisualLayers"]',
            f"z_index = {int(layer['z_index'])}",
            f"visible = {'true' if layer['enabled'] else 'false'}",
        )
    )
    if node_type == "Parallax2D":
        lines.append(
            f"scroll_scale = {_gd_vector(layer['parallax_scale'], scale_label)}"
        )
    lines.extend(
        (
            f"metadata/layer_id = {_gd_string(layer_id)}",
            f"metadata/role = {_gd_string(layer['role'])}",
            f"metadata/space = {_gd_string(layer['space'])}",
            f"metadata/parallax_scale = {_gd_vector(layer['parallax_scale'], scale_label)}",
            f"metadata/enabled = {'true' if layer['enabled'] else 'false'}",
            f"metadata/reserved = {'true' if layer['reserved'] else 'false'}",
            f"metadata/affordance_policy = {_gd_string(layer['affordance_policy'])}",
            f"metadata/geometry_role = {_gd_string(layer['geometry_role'])}",
        )
    )


def _scene_visual_asset_resources(
    manifest: dict[str, Any],
) -> tuple[list[str], list[str], list[dict[str, Any]]]:
    assets: list[dict[str, Any]] = manifest["visual"]["assets"]
    if not assets:
        return [], [], []
    ext_resources: list[str] = []
    sub_resources: list[str] = []
    bindings: list[dict[str, Any]] = []
    has_l05 = any(asset["layer_id"] == "L05" for asset in assets)
    if has_l05:
        ext_resources.extend(
            (
                f'[ext_resource type="Shader" path="{L05_SHADER_RESOURCE_PATH}" id="Shader_l05_ground"]',
                f'[ext_resource type="Texture2D" path="{L05_SOLID_MASK_RESOURCE_PATH}" id="Texture_l05_solid"]',
            )
        )
    for index, asset in enumerate(assets):
        texture_id = f"Texture_asset_{index:04d}"
        resource_path = (
            "res://underwater_map_workbench/" + str(asset["path"])
        )
        ext_resources.append(
            f'[ext_resource type="Texture2D" path="{resource_path}" id="{texture_id}"]'
        )
        binding: dict[str, Any] = {
            "asset": asset,
            "index": index,
            "texture_id": texture_id,
        }
        if asset["kind"] == "collision_masked_material":
            material_id = f"ShaderMaterial_asset_{index:04d}"
            binding["material_id"] = material_id
            sub_resources.extend(
                (
                    "",
                    f'[sub_resource type="ShaderMaterial" id="{material_id}"]',
                    'shader = ExtResource("Shader_l05_ground")',
                    'shader_parameter/topology_mask = ExtResource("Texture_l05_solid")',
                    f'shader_parameter/ground_texture = ExtResource("{texture_id}")',
                )
            )
        bindings.append(binding)
    return ext_resources, sub_resources, bindings


def _append_visual_assets(
    lines: list[str],
    bindings: list[dict[str, Any]],
) -> None:
    for binding in bindings:
        asset: dict[str, Any] = binding["asset"]
        index = int(binding["index"])
        asset_id = str(asset["id"])
        layer_id = str(asset["layer_id"])
        x, y, width, height = _rect(
            asset["world_rect"],
            f"visual.assets[{index}].world_rect",
        )
        node_name = f"Asset{index:04d}_{_safe_node_name(asset_id)}"
        if asset["kind"] == "texture_rect":
            lines.extend(
                (
                    "",
                    f'[node name="{node_name}" type="TextureRect" parent="VisualLayers/{layer_id}"]',
                    f"offset_left = {_gd_number(x)}",
                    f"offset_top = {_gd_number(y)}",
                    f"offset_right = {_gd_number(x + width)}",
                    f"offset_bottom = {_gd_number(y + height)}",
                    f'texture = ExtResource("{binding["texture_id"]}")',
                    "expand_mode = 1",
                    "stretch_mode = 0",
                    "mouse_filter = 2",
                    f"visible = {'true' if asset['enabled'] else 'false'}",
                )
            )
        else:
            lines.extend(
                (
                    "",
                    f'[node name="{node_name}" type="ColorRect" parent="VisualLayers/{layer_id}"]',
                    f"offset_left = {_gd_number(x)}",
                    f"offset_top = {_gd_number(y)}",
                    f"offset_right = {_gd_number(x + width)}",
                    f"offset_bottom = {_gd_number(y + height)}",
                    f'material = SubResource("{binding["material_id"]}")',
                    "mouse_filter = 2",
                    f"visible = {'true' if asset['enabled'] else 'false'}",
                )
            )
        lines.extend(
            (
                f"metadata/asset_id = {_gd_string(asset_id)}",
                f"metadata/layer_id = {_gd_string(layer_id)}",
                f"metadata/kind = {_gd_string(asset['kind'])}",
                f"metadata/source = {_gd_variant(asset)}",
            )
        )


def _append_l00_content(
    lines: list[str],
    manifest: dict[str, Any],
    world_size: tuple[float, float],
) -> None:
    map_record = manifest["map"]
    grid = map_record["grid"]
    columns = int(grid["columns"])
    rows = int(grid["rows"])
    cell_width, cell_height = _pair(grid["cell_size"], "map.grid.cell_size")
    world_width, world_height = world_size
    visual = manifest["visual"]
    full_world = [
        (0.0, 0.0),
        (world_width, 0.0),
        (world_width, world_height),
        (0.0, world_height),
    ]
    lines.extend(
        (
            "",
            '[node name="Water" type="Polygon2D" parent="VisualLayers/L00"]',
            f"polygon = {_gd_points(full_world)}",
            f'color = {_gd_color(visual["water_color"], "visual.water_color")}',
            "",
            '[node name="DeepWater" type="Polygon2D" parent="VisualLayers/L00"]',
            f"polygon = {_gd_points([(0.0, world_height * 0.58), (world_width, world_height * 0.58), (world_width, world_height), (0.0, world_height)])}",
            f'color = {_gd_color(visual["deep_water_color"], "visual.deep_water_color", 0xB8)}',
        )
    )
    if not bool(visual.get("diagnostic_grid_enabled", True)):
        return
    lines.extend(
        (
            "",
            '[node name="Grid" type="Node2D" parent="VisualLayers/L00"]',
        )
    )
    grid_color = _color(visual["grid_color"], "visual.grid_color")
    grid_width = _positive_number(visual["grid_width"], "visual.grid_width")
    for column in range(1, columns):
        x = column * cell_width
        lines.extend(
            (
                "",
                f'[node name="Column{column:03d}" type="Line2D" parent="VisualLayers/L00/Grid"]',
                f"points = {_gd_points([(x, 0.0), (x, world_height)])}",
                f"width = {_gd_number(grid_width)}",
                f'default_color = {_gd_color(grid_color, "visual.grid_color", 0x70)}',
                "antialiased = true",
            )
        )
    for row in range(1, rows):
        y = row * cell_height
        lines.extend(
            (
                "",
                f'[node name="Row{row:03d}" type="Line2D" parent="VisualLayers/L00/Grid"]',
                f"points = {_gd_points([(0.0, y), (world_width, y)])}",
                f"width = {_gd_number(grid_width)}",
                f'default_color = {_gd_color(grid_color, "visual.grid_color", 0x70)}',
                "antialiased = true",
            )
        )


def _append_landmarks(lines: list[str], manifest: dict[str, Any]) -> None:
    visual = manifest["visual"]
    marker_color = _color(visual["station_color"], "visual.station_color")
    lines.extend(
        (
            "",
            '[node name="Landmarks" type="Node2D" parent="VisualLayers/L03"]',
        )
    )
    for index, landmark in enumerate(manifest["landmarks"]):
        node_name = f"Landmark{index:04d}_{_safe_node_name(str(landmark['id']))}"
        label_text = f"{landmark['id']}  {str(landmark['display_name']).upper()}"
        lines.extend(
            (
                "",
                f'[node name="{node_name}" type="Node2D" parent="VisualLayers/L03/Landmarks"]',
                f"position = {_gd_vector(landmark['position'], f'landmarks[{index}].position')}",
                f"metadata/landmark_id = {_gd_string(landmark['id'])}",
                f"metadata/region_id = {_gd_string(landmark['region_id'])}",
                f"metadata/role = {_gd_string(landmark['role'])}",
                'metadata/affordance = "nonblocking_marker"',
                "",
                f'[node name="HorizontalMarker" type="Line2D" parent="VisualLayers/L03/Landmarks/{node_name}"]',
                f"points = {_gd_points([(-20.0, 0.0), (20.0, 0.0)])}",
                "width = 4",
                f'default_color = {_gd_color(marker_color, "visual.station_color")}',
                "antialiased = true",
                'metadata/affordance = "nonblocking_marker"',
                "",
                f'[node name="VerticalMarker" type="Line2D" parent="VisualLayers/L03/Landmarks/{node_name}"]',
                f"points = {_gd_points([(0.0, -20.0), (0.0, 20.0)])}",
                "width = 4",
                f'default_color = {_gd_color(marker_color, "visual.station_color")}',
                "antialiased = true",
                'metadata/affordance = "nonblocking_marker"',
            )
        )
        lines.extend(
            (
                "",
                f'[node name="Label" type="Label" parent="VisualLayers/L03/Landmarks/{node_name}"]',
                "offset_left = -210",
                "offset_top = 28",
                "offset_right = 210",
                "offset_bottom = 72",
                f"text = {_gd_string(label_text)}",
                "horizontal_alignment = 1",
                "theme_override_font_sizes/font_size = 20",
                'metadata/affordance = "nonblocking_marker"',
            )
        )


def _append_world_border(
    lines: list[str],
    manifest: dict[str, Any],
    world_size: tuple[float, float],
) -> None:
    visual = manifest["visual"]
    world_width, world_height = world_size
    border_color = _color(visual["border_color"], "visual.border_color")
    border_width = _positive_number(visual["border_width"], "visual.border_width")
    lines.extend(
        (
            "",
            '[node name="WorldBorder" type="Line2D" parent="VisualLayers/L05"]',
            f"points = {_gd_points([(0.0, 0.0), (world_width, 0.0), (world_width, world_height), (0.0, world_height), (0.0, 0.0)])}",
            f"width = {_gd_number(border_width)}",
            f'default_color = {_gd_color(border_color, "visual.border_color")}',
            "antialiased = true",
            'metadata/geometry_role = "collider_authority"',
        )
    )


def _append_manifest_regions(lines: list[str], manifest: dict[str, Any]) -> None:
    lines.extend(
        (
            "",
            '[node name="ManifestRegions" type="Node2D" parent="."]',
            "visible = false",
        )
    )
    for index, region in enumerate(manifest["regions"]):
        node_name = f"Region{index:04d}_{_safe_node_name(str(region['id']))}"
        lines.extend(
            (
                "",
                f'[node name="{node_name}" type="Node2D" parent="ManifestRegions"]',
                f"metadata/region_id = {_gd_string(region['id'])}",
                f"metadata/display_name = {_gd_string(region['display_name'])}",
                f"metadata/bounds = {_gd_variant(region['bounds'])}",
                f"metadata/water_color = {_gd_string(region['water_color'])}",
                f"metadata/accent_color = {_gd_string(region['accent_color'])}",
            )
        )


def _append_manifest_markers(lines: list[str], manifest: dict[str, Any]) -> None:
    lines.extend(
        (
            "",
            '[node name="ManifestMarkers" type="Node2D" parent="."]',
            "visible = false",
            "",
            '[node name="Entry" type="Marker2D" parent="ManifestMarkers"]',
            f"position = {_gd_vector(manifest['entry']['position'], 'entry.position')}",
            f"metadata/object_id = {_gd_string(manifest['entry']['landmark_id'])}",
            'metadata/kind = "entry"',
            "",
            '[node name="Exit" type="Marker2D" parent="ManifestMarkers"]',
            f"position = {_gd_vector(manifest['exit']['position'], 'exit.position')}",
            'metadata/object_id = "exit"',
            'metadata/kind = "exit"',
        )
    )
    gameplay = manifest["gameplay"]
    for collection_index, (collection_name, records) in enumerate(
        _iter_gameplay_collections(gameplay)
    ):
        collection_node = (
            f"Collection{collection_index:03d}_{_safe_node_name(collection_name)}"
        )
        lines.extend(
            (
                "",
                f'[node name="{collection_node}" type="Node2D" parent="ManifestMarkers"]',
                f"metadata/collection = {_gd_string(collection_name)}",
            )
        )
        for record_index, record in enumerate(records):
            node_name = (
                f"Record{record_index:04d}_{_safe_node_name(str(record['id']))}"
            )
            node_type = "Marker2D" if "position" in record else "Node2D"
            lines.extend(
                (
                    "",
                    f'[node name="{node_name}" type="{node_type}" parent="ManifestMarkers/{collection_node}"]',
                    f"metadata/object_id = {_gd_string(record['id'])}",
                    f"metadata/kind = {_gd_string(collection_name)}",
                    f"metadata/source = {_gd_variant(record)}",
                )
            )
            if "position" in record:
                lines.append(
                    f"position = {_gd_vector(record['position'], f'gameplay.{collection_name}[{record_index}].position')}"
                )


def render_scene(
    manifest: dict[str, Any],
    manifest_sha: str,
    gameplay_signature: str,
    presentation_fingerprint: str,
    topology_build: dict[str, Any],
) -> str:
    map_record = manifest["map"]
    grid = map_record["grid"]
    columns = int(grid["columns"])
    rows = int(grid["rows"])
    cell_width, cell_height = _pair(grid["cell_size"], "map.grid.cell_size")
    world_size = _pair(map_record["world_size"], "map.world_size")
    world_width, world_height = world_size
    ext_resources, sub_resources, asset_bindings = _scene_visual_asset_resources(
        manifest
    )
    load_steps = 1 + len(ext_resources) + sum(
        1 for line in sub_resources if line.startswith("[sub_resource")
    )
    scene_header = (
        f"[gd_scene load_steps={load_steps} format=3]"
        if ext_resources or sub_resources
        else "[gd_scene format=3]"
    )
    lines = [
        "; Generated by underwater_map_workbench/tools/build_underwater_map.py.",
        "; Edit map_manifest.json, never this file by hand.",
        scene_header,
    ]
    if ext_resources or sub_resources:
        lines.extend(("", *ext_resources, *sub_resources, ""))
    else:
        lines.append("")
    lines.extend([
        '[node name="UnderwaterMap" type="Node2D"]',
        'metadata/manifest_path = "res://underwater_map_workbench/map_manifest.json"',
        f'metadata/manifest_sha256 = "{manifest_sha}"',
        f'metadata/schema_version = {manifest["schema_version"]}',
        f'metadata/source_version = {map_record["source_version"]}',
        f"metadata/revision = {_gd_variant(manifest['revision'])}",
        f'metadata/gameplay_signature = "{gameplay_signature}"',
        f'metadata/presentation_fingerprint = "{presentation_fingerprint}"',
        f'metadata/revision_id = {_gd_string(manifest["revision"]["revision_id"])}',
        f'metadata/topology_revision = {_gd_string(manifest["revision"]["topology_revision"])}',
        f'metadata/presentation_revision = {_gd_string(manifest["revision"]["presentation_revision"])}',
        f"metadata/grid_size = Vector2i({columns}, {rows})",
        f"metadata/cell_size = Vector2({_gd_number(cell_width)}, {_gd_number(cell_height)})",
        f'metadata/navigation_cell_size = {_gd_vector(map_record["navigation_cell_size"], "map.navigation_cell_size")}',
        f"metadata/world_size = Vector2({_gd_number(world_width)}, {_gd_number(world_height)})",
        f"metadata/topology = {_gd_variant(manifest['topology'])}",
        f"metadata/campaign = {_gd_variant(manifest['campaign'])}",
    ])
    if topology_build.get("mode") == L05_MODE:
        lines.extend(
            (
                f"metadata/payload_sha256 = {_gd_string(topology_build['payload_sha256'])}",
                f"metadata/canonical_digest = {_gd_string(topology_build['canonical_digest'])}",
            )
        )
    lines.extend(("", '[node name="VisualLayers" type="Node2D" parent="."]'))
    layers_by_id = {
        str(layer["id"]): layer
        for layer in manifest["visual"]["layers"]
    }
    for layer_id in EXPECTED_LAYER_IDS:
        layer = layers_by_id[layer_id]
        _append_layer_root(lines, layer)
        if layer_id == "L00":
            _append_l00_content(lines, manifest, world_size)
        elif layer_id == "L03":
            _append_landmarks(lines, manifest)
        elif layer_id == "L05" and topology_build.get("mode") == "open_world":
            _append_world_border(lines, manifest, world_size)
    _append_visual_assets(lines, asset_bindings)
    _append_manifest_regions(lines, manifest)
    _append_manifest_markers(lines, manifest)
    return "\n".join(lines) + "\n"


def _write_outputs_atomically(outputs: dict[Path, bytes]) -> None:
    temporary_paths: list[tuple[Path, Path]] = []
    try:
        for destination, content in outputs.items():
            destination.parent.mkdir(parents=True, exist_ok=True)
            descriptor, temporary_name = tempfile.mkstemp(
                dir=destination.parent,
                prefix=f".{destination.name}.",
                suffix=".tmp",
            )
            temporary_path = Path(temporary_name)
            temporary_paths.append((temporary_path, destination))
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(content)
                stream.flush()
                os.fsync(stream.fileno())
        for temporary_path, destination in temporary_paths:
            os.replace(temporary_path, destination)
    except BaseException:
        for temporary_path, _destination in temporary_paths:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass
        raise


def _refresh_l05_source() -> None:
    original_raw = MANIFEST_PATH.read_bytes()
    original_sha = hashlib.sha256(original_raw).hexdigest()
    try:
        manifest = json.loads(original_raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ManifestError(f"invalid JSON: {error}") from error
    manifest = _object(manifest, "manifest")
    topology = _object(manifest.get("topology"), "topology")
    if topology.get("mode") != L05_MODE:
        raise ManifestError(
            f"--refresh-l05-source requires topology.mode={L05_MODE}"
        )
    world_size = _validate_map(manifest)
    topology_build = _validate_topology(
        manifest,
        world_size,
        verify_declarations=False,
    )
    collision = _object(
        topology.get("collision_source"),
        "topology.collision_source",
    )
    visual = _object(manifest.get("visual"), "visual")
    assets = _array(visual.get("assets"), "visual.assets")
    active_l05_assets: list[dict[str, Any]] = []
    for index, asset_value in enumerate(assets):
        asset = _object(asset_value, f"visual.assets[{index}]")
        if asset.get("layer_id") == "L05" and asset.get("enabled") is True:
            active_l05_assets.append(asset)
    if len(active_l05_assets) != 1:
        raise ManifestError(
            "--refresh-l05-source requires exactly one enabled L05 visual asset"
        )
    actual_sha = str(topology_build["payload_sha256"])
    canonical_digest = str(topology_build["canonical_digest"])
    changed = False
    if collision.get("sha256") != actual_sha:
        collision["sha256"] = actual_sha
        changed = True
    if collision.get("canonical_digest") != canonical_digest:
        collision["canonical_digest"] = canonical_digest
        changed = True
    active_l05_asset = active_l05_assets[0]
    if active_l05_asset.get("topology_digest") != canonical_digest:
        active_l05_asset["topology_digest"] = canonical_digest
        changed = True

    if not changed:
        load_and_validate_manifest()
        if hashlib.sha256(MANIFEST_PATH.read_bytes()).hexdigest() != original_sha:
            raise ManifestError("no-op refresh unexpectedly changed map_manifest.json")
        print(
            "L05 source declarations are current; map_manifest.json unchanged "
            f"({actual_sha}, {canonical_digest})"
        )
        return

    updated_raw = (
        json.dumps(
            manifest,
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    ).encode("utf-8")
    _write_outputs_atomically({MANIFEST_PATH: updated_raw})
    try:
        load_and_validate_manifest()
    except (OSError, ManifestError) as error:
        _write_outputs_atomically({MANIFEST_PATH: original_raw})
        raise ManifestError(
            f"refreshed L05 declarations failed full validation: {error}"
        ) from error
    print(
        "Refreshed L05 source declarations in map_manifest.json "
        f"({actual_sha}, {canonical_digest})"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--build", action="store_true", help="write the deterministic scene")
    mode.add_argument("--check", action="store_true", help="verify that the scene is current")
    mode.add_argument(
        "--refresh-l05-source",
        action="store_true",
        help="refresh L05 payload SHA and canonical digest in the manifest",
    )
    args = parser.parse_args()
    if args.refresh_l05_source:
        try:
            _refresh_l05_source()
        except (OSError, ManifestError) as error:
            print(f"underwater map manifest error: {error}", file=sys.stderr)
            return 1
        return 0
    try:
        (
            manifest,
            manifest_sha,
            gameplay_signature,
            presentation_fingerprint,
            topology_build,
        ) = load_and_validate_manifest()
        expected = render_scene(
            manifest,
            manifest_sha,
            gameplay_signature,
            presentation_fingerprint,
            topology_build,
        )
        expected_outputs = _render_l05_artifacts(topology_build, manifest_sha)
        expected_outputs[SCENE_PATH] = expected.encode("utf-8")
    except (OSError, ManifestError) as error:
        print(f"underwater map manifest error: {error}", file=sys.stderr)
        return 1
    if args.check:
        for output_path, expected_bytes in expected_outputs.items():
            if not output_path.exists():
                print(f"generated output is missing: {output_path}", file=sys.stderr)
                return 1
            if output_path.read_bytes() != expected_bytes:
                relative_path = output_path.relative_to(WORKBENCH_DIR)
                print(f"{relative_path} is stale; run with --build", file=sys.stderr)
                return 1
        print(
            "UnderwaterMap.tscn and generated L05 outputs are current "
            f"({manifest_sha}, {gameplay_signature}, {presentation_fingerprint})"
        )
        return 0
    try:
        _write_outputs_atomically(expected_outputs)
    except OSError as error:
        print(f"cannot write generated outputs atomically: {error}", file=sys.stderr)
        return 1
    print(
        f"Built {SCENE_PATH} from {MANIFEST_PATH} "
        f"({manifest_sha}, {gameplay_signature}, {presentation_fingerprint})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
