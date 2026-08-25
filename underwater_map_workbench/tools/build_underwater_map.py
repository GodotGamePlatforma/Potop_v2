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
import sys
import tempfile
import unicodedata
from pathlib import Path
from typing import Any, Iterable


WORKBENCH_DIR = Path(__file__).resolve().parents[1]
MANIFEST_PATH = WORKBENCH_DIR / "map_manifest.json"
SCENE_PATH = WORKBENCH_DIR / "UnderwaterMap.tscn"

EXPECTED_LAYER_IDS = tuple(f"L{index:02d}" for index in range(11))
PARALLAX_LAYER_IDS = frozenset(("L01", "L02", "L08", "L09"))
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
        "topology": copy.deepcopy(manifest["topology"]),
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
        "topology": copy.deepcopy(manifest["topology"]),
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
    if assets:
        raise ManifestError(
            "visual.assets must remain empty until the typed visual renderer is implemented"
        )


def _validate_topology(
    manifest: dict[str, Any],
    world_size: tuple[float, float],
) -> None:
    topology = _object(manifest["topology"], "topology")
    _require_keys(
        topology,
        ("mode", "authority_layer", "collision_source", "protected_corridors"),
        "topology",
    )
    mode = _non_empty_string(topology["mode"], "topology.mode")
    if mode != "open_world":
        raise ManifestError("the foundation supports only topology.mode open_world")
    if topology["authority_layer"] != "L05":
        raise ManifestError("topology.authority_layer must be L05")

    collision = _object(topology["collision_source"], "topology.collision_source")
    _require_keys(
        collision,
        (
            "format",
            "path",
            "sha256",
            "pixel_size",
            "world_units_per_pixel",
            "encoding",
        ),
        "topology.collision_source",
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
    _require_keys(encoding, ("solid", "open_water"), "topology.collision_source.encoding")
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

    if source_format != "none":
        raise ManifestError(
            "the foundation supports only topology.collision_source.format none"
        )
    if collision["path"] != "" or collision["sha256"] != "":
        raise ManifestError("a none collision source must have empty path and sha256")
    if pixel_size != (0.0, 0.0) or world_units_per_pixel != (0.0, 0.0):
        raise ManifestError("a none collision source must have zero sizes")
    if solid != 0 or open_water != 255:
        raise ManifestError(
            "the foundation collision encoding must use solid=0 and open_water=255"
        )

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


def load_and_validate_manifest() -> tuple[dict[str, Any], str, str, str]:
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
    _validate_visual(manifest, world_size)
    _validate_topology(manifest, world_size)
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
) -> str:
    map_record = manifest["map"]
    grid = map_record["grid"]
    columns = int(grid["columns"])
    rows = int(grid["rows"])
    cell_width, cell_height = _pair(grid["cell_size"], "map.grid.cell_size")
    world_size = _pair(map_record["world_size"], "map.world_size")
    world_width, world_height = world_size
    lines = [
        "; Generated by underwater_map_workbench/tools/build_underwater_map.py.",
        "; Edit map_manifest.json, never this file by hand.",
        "[gd_scene format=3]",
        "",
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
        "",
        '[node name="VisualLayers" type="Node2D" parent="."]',
    ]
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
        elif layer_id == "L05":
            _append_world_border(lines, manifest, world_size)
    _append_manifest_regions(lines, manifest)
    _append_manifest_markers(lines, manifest)
    return "\n".join(lines) + "\n"


def _write_scene_atomically(content: str) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        dir=SCENE_PATH.parent,
        prefix=f".{SCENE_PATH.name}.",
        suffix=".tmp",
    )
    temporary_path = Path(temporary_name)
    try:
        stream = os.fdopen(descriptor, "w", encoding="utf-8", newline="\n")
        descriptor = -1
        with stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, SCENE_PATH)
    except BaseException:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            temporary_path.unlink(missing_ok=True)
        except OSError:
            pass
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--build", action="store_true", help="write the deterministic scene")
    mode.add_argument("--check", action="store_true", help="verify that the scene is current")
    args = parser.parse_args()
    try:
        (
            manifest,
            manifest_sha,
            gameplay_signature,
            presentation_fingerprint,
        ) = load_and_validate_manifest()
        expected = render_scene(
            manifest,
            manifest_sha,
            gameplay_signature,
            presentation_fingerprint,
        )
    except (OSError, ManifestError) as error:
        print(f"underwater map manifest error: {error}", file=sys.stderr)
        return 1
    if args.check:
        if not SCENE_PATH.exists():
            print(f"generated scene is missing: {SCENE_PATH}", file=sys.stderr)
            return 1
        if SCENE_PATH.read_text(encoding="utf-8") != expected:
            print("UnderwaterMap.tscn is stale; run with --build", file=sys.stderr)
            return 1
        print(
            "UnderwaterMap.tscn is current "
            f"({manifest_sha}, {gameplay_signature}, {presentation_fingerprint})"
        )
        return 0
    try:
        _write_scene_atomically(expected)
    except OSError as error:
        print(f"cannot write generated scene atomically: {error}", file=sys.stderr)
        return 1
    print(
        f"Built {SCENE_PATH} from {MANIFEST_PATH} "
        f"({manifest_sha}, {gameplay_signature}, {presentation_fingerprint})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
