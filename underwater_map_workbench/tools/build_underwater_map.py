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
import subprocess
import sys
import tempfile
import unicodedata
import zlib
from collections import deque
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterable


WORKBENCH_DIR = Path(__file__).resolve().parents[1]
ROOT_TOOLS_DIR = WORKBENCH_DIR.parent / "tools"
if str(ROOT_TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_TOOLS_DIR))

from workbench_lock import (  # noqa: E402
    InterprocessWorkspaceLock,
    WorkspaceLockError,
)
from workbench_contract import (  # noqa: E402
    ContractError,
    ISOLATED_EOL_PROOF_KEY_ENV,
    ISOLATED_EOL_PROOF_PATH_ENV,
    assert_tracked_lf_eol,
    repository_root,
    verify_isolated_eol_proof,
)

MANIFEST_PATH = WORKBENCH_DIR / "map_manifest.json"
SCENE_PATH = WORKBENCH_DIR / "UnderwaterMap.tscn"
MAP_SCHEMA_VERSION = 6
L05_GENERATED_DIR = WORKBENCH_DIR / "assets" / "generated" / "l05"
L05_GENERATED_PATHS = {
    "solid_mask": L05_GENERATED_DIR / "solid_mask.png",
    "open_water_mask": L05_GENERATED_DIR / "open_water_mask.png",
    "boundary_mask": L05_GENERATED_DIR / "boundary_mask.png",
    "full_map_guide": L05_GENERATED_DIR / "full_map_guide.png",
    "surface_detail_mask": L05_GENERATED_DIR / "surface_detail_mask.png",
    "truth_package": L05_GENERATED_DIR / "truth_package.json",
}
L05_SHADER_PATH = "assets/shaders/l05_ground_masked.gdshader"
L05_SOLID_MASK_RESOURCE_PATH = (
    "res://underwater_map_workbench/assets/generated/l05/solid_mask.png"
)
L05_SURFACE_DETAIL_MASK_RESOURCE_PATH = (
    "res://underwater_map_workbench/assets/generated/l05/surface_detail_mask.png"
)
L05_SHADER_RESOURCE_PATH = (
    "res://underwater_map_workbench/assets/shaders/l05_ground_masked.gdshader"
)

EXPECTED_LAYER_IDS = tuple(f"L{index:02d}" for index in range(11))
PARALLAX_LAYER_IDS = frozenset(("L01", "L02", "L08", "L09"))
NONBLOCKING_TEXTURE_LAYER_IDS = frozenset(("L01", "L02"))
STREAMED_BACKDROP_LAYER_IDS = frozenset(("L01", "L02"))
STREAMED_BACKDROP_CONTRACT = "camera_windowed_texture_v1"
GROUND_ANCHORED_BACKDROP_LAYER_IDS = frozenset(("L01", "L02"))
NONBLOCKING_BACKDROP_AFFORDANCE = "nonblocking_backdrop"
COMPOSITION_PROXY_KIND = "composition_proxy"
COMPOSITION_PROXY_FILL_COLOR = "164c6652"
COMPOSITION_PROXY_OUTLINE_COLOR = "ff7a18e6"
COMPOSITION_PROXY_LABEL_COLOR = "fff1dcff"
SAFE_VISUAL_GROUP_ID = re.compile(r"[A-Za-z][A-Za-z0-9_]*\Z")
BACKDROP_MIN_OPAQUE_SHARE = 0.95
BACKDROP_MAX_PARTIAL_CANVAS_SHARE = 0.03
BACKDROP_MAX_LOW_ALPHA_CANVAS_SHARE = 0.0025
BACKDROP_MIN_BOTTOM_OPAQUE_SHARE = 0.01
LAYER_KEYS = frozenset(
    (
        "id",
        "role",
        "space",
        "z_index",
        "parallax_scale",
        "rgb_modulate",
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
        "group_id",
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
STRUCTURE_VISUAL_ASSET_KEYS = frozenset(
    (
        "id",
        "layer_id",
        "group_id",
        "kind",
        "path",
        "sha256",
        "pixel_size",
        "local_rect",
        "enabled",
        "affordance",
        "topology_digest",
        "partition_digest",
        "structure_id",
    )
)
STRUCTURE_INTERIOR_TEXTURE_KIND = "structure_interior_texture"
STRUCTURE_OWNER_MASKED_TEXTURE_KIND = "structure_owner_masked_texture"
STRUCTURE_INTERIOR_AFFORDANCE = "open_water_clipped_interior"
STRUCTURE_OWNER_AFFORDANCE = "exact_owner_solid_surface"
PORTAL_BACKDROP_CLEARANCE_CONTRACT = "raster_boundary_opening_clearance_v2"
PORTAL_BACKDROP_CLEARANCE_HOST_LAYER_ID = "L04"
PORTAL_BACKDROP_CLEARANCE_OCCLUDED_LAYER_IDS = ("L01", "L02")
PORTAL_BACKDROP_CLEARANCE_FOREGROUND_LAYER_IDS = ("L03", "L04")
PORTAL_BACKDROP_CLEARANCE_NORMAL_CORE_CELLS = 3
PORTAL_BACKDROP_CLEARANCE_TANGENT_PADDING_CELLS = 1
PORTAL_BACKDROP_CLEARANCE_FEATHER_CELLS = 1
PORTAL_BACKDROP_CLEARANCE_FEATHER_OUTER_TINT = 0.82
STRUCTURE_CLIP_SHADER_PATH = "assets/shaders/structure_clip_masked.gdshader"
STRUCTURE_CLIP_SHADER_RESOURCE_PATH = (
    "res://underwater_map_workbench/assets/shaders/structure_clip_masked.gdshader"
)
STRUCTURE_NATIVE_WORLD_UNITS_PER_PIXEL = (1.0, 1.0)
STRUCTURE_NATIVE_MAX_TEXTURE_DIMENSION = 4096
STRUCTURE_NATIVE_MAX_TEXTURE_PIXELS = 4096 * 4096
SURFACE_DETAIL_EDGE_VALUES = (255, 184, 112, 48)
L05_MODE = "l05_mask_v1"
L05_SOURCE_FORMAT = "l05_owned_rect_ops_v2"
L05_PIXEL_SIZE = (576, 324)
L05_WORLD_UNITS_PER_PIXEL = (40.0, 40.0)
L05_MAPPING = {
    "world_origin": [0, 0],
    "x_axis": "right",
    "y_axis": "down",
    "pixel_reference": "pixel_edge",
    "rounding": "floor",
}
STRUCTURE_ROOT_KEYS = frozenset(("templates", "instances"))
STRUCTURE_REGISTRY_KEYS = frozenset(("instances",))
STRUCTURE_REGISTRY_INSTANCE_REQUIRED_KEYS = frozenset(
    ("id", "origin", "enabled", "package")
)
STRUCTURE_REGISTRY_INSTANCE_OPTIONAL_KEYS = frozenset(("landmark_id",))
STRUCTURE_PACKAGE_REFERENCE_KEYS = frozenset(("format", "path", "sha256"))
STRUCTURE_PACKAGE_REFERENCE_FORMAT = "structure_package_v1"
STRUCTURE_PACKAGE_FORMAT = "enterable_structure_package_v1"
STRUCTURE_PACKAGE_KEYS = frozenset(
    (
        "schema_version",
        "format",
        "template",
        "size",
        "local_topology_digest",
        "collision",
        "sockets",
        "runtime",
        "visual_assets",
        "scripts",
        "attempt_state",
        "references",
    )
)
STRUCTURE_PACKAGE_COLLISION_KEYS = frozenset(
    ("format", "base", "pixel_size", "world_units_per_pixel", "operations")
)
STRUCTURE_PACKAGE_COLLISION_FORMAT = "l05_structure_rect_ops_v1"
STRUCTURE_PACKAGE_OPERATION_KEYS = frozenset(("id", "op", "rect_px"))
STRUCTURE_PACKAGE_VISUAL_ASSET_KEYS = frozenset(
    (
        "id",
        "layer_id",
        "group_id",
        "kind",
        "path",
        "sha256",
        "pixel_size",
        "local_rect",
        "enabled",
        "affordance",
    )
)
STRUCTURE_PACKAGE_SCRIPT_KEYS = frozenset(("role", "path", "sha256"))
STRUCTURE_PACKAGE_REQUIRED_SCRIPT_ROLE = "controller"
STRUCTURE_PACKAGE_ATTEMPT_STATE = {
    "persistence": "none",
    "checkpoint": "none",
    "reset": "whole_structure_attempt",
}
STRUCTURE_PACKAGE_REFERENCE_KEYS_EXACT = frozenset(
    ("path", "sha256", "role", "authority", "excluded_topics")
)
STRUCTURE_TEMPLATE_KEYS = frozenset(
    (
        "id",
        "kind",
        "interior_layer_id",
        "collider_layer_id",
        "allowed_socket_kinds",
    )
)
STRUCTURE_INSTANCE_REQUIRED_KEYS = frozenset(
    (
        "id",
        "template_id",
        "origin",
        "size",
        "enabled",
        "topology_digest",
        "partition_digest",
        "sockets",
    )
)
STRUCTURE_INSTANCE_OPTIONAL_KEYS = frozenset(
    (
        "landmark_id",
        "runtime",
        "controller_script",
        "package_path",
        "package_sha256",
        "local_topology_digest",
        "collision_operations",
        "structure_scene_path",
    )
)
STRUCTURE_SOCKET_KEYS = frozenset(("id", "kind", "local_rect"))
STRUCTURE_SOLID_COLOR = "274956ff"
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
OPEN_WATER_BACKDROP_POLICY = "nonblocking_backdrop_may_overlap_open_water"
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


def _git_common_directory(project_root: Path | None = None) -> Path:
    """Return one lock identity shared by every linked worktree."""
    root = (project_root or WORKBENCH_DIR.parent).resolve()
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--git-common-dir"],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise WorkspaceLockError(
            f"cannot resolve the shared Git directory for {root}: {error}"
        ) from error
    common_value = result.stdout.strip()
    if result.returncode != 0 or not common_value:
        detail = result.stderr.strip() or f"git exited with {result.returncode}"
        raise WorkspaceLockError(
            f"cannot resolve the shared Git directory for {root}: {detail}"
        )
    common_directory = Path(common_value)
    if not common_directory.is_absolute():
        common_directory = root / common_directory
    return common_directory.resolve()


@contextmanager
def _map_promotion_lock() -> Iterable[None]:
    """Lock Map publication across linked worktrees and legacy local runners."""
    project_root = WORKBENCH_DIR.parent.resolve()
    common_directory = _git_common_directory(project_root)
    # Take the compatibility lock first so a long local FROZEN snapshot does
    # not occupy the repository-wide lock while this publisher waits for it.
    with InterprocessWorkspaceLock(project_root, "map-promotion"):
        if common_directory == project_root:
            yield
            return
        with InterprocessWorkspaceLock(common_directory, "map-promotion"):
            yield


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
    if "\\" in path or not (
        path.startswith("assets/") or path.startswith("structures/")
    ):
        raise ManifestError(
            f"{label} must be a workbench-relative assets/... or structures/... path"
        )
    parts = Path(path).parts
    if Path(path).is_absolute() or ".." in parts or "." in parts:
        raise ManifestError(f"{label} must not escape the workbench package")
    resolved = (WORKBENCH_DIR / Path(path)).resolve()
    try:
        resolved.relative_to(WORKBENCH_DIR.resolve())
    except ValueError as error:
        raise ManifestError(f"{label} must remain inside the workbench") from error
    return path, resolved


def _structure_package_member_path(
    package_directory: Path,
    value: Any,
    label: str,
) -> tuple[str, Path, str]:
    relative_path = _non_empty_string(value, label)
    if "\\" in relative_path:
        raise ManifestError(f"{label} must use forward slashes")
    relative = Path(relative_path)
    if relative.is_absolute() or ".." in relative.parts or "." in relative.parts:
        raise ManifestError(f"{label} must not escape its structure package")
    resolved = (package_directory / relative).resolve()
    try:
        resolved.relative_to(package_directory.resolve())
        workbench_relative = resolved.relative_to(WORKBENCH_DIR.resolve())
    except ValueError as error:
        raise ManifestError(f"{label} must remain inside its structure package") from error
    package_path = workbench_relative.as_posix()
    return (
        package_path,
        resolved,
        f"res://underwater_map_workbench/{package_path}",
    )


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


def _paeth_predictor(left: int, above: int, upper_left: int) -> int:
    prediction = left + above - upper_left
    left_distance = abs(prediction - left)
    above_distance = abs(prediction - above)
    upper_left_distance = abs(prediction - upper_left)
    if left_distance <= above_distance and left_distance <= upper_left_distance:
        return left
    if above_distance <= upper_left_distance:
        return above
    return upper_left


def _decode_png_rgba8(
    raw: bytes,
    label: str,
    width: int,
    height: int,
) -> bytes:
    bit_depth, color_type, compression, filter_method, interlace = raw[24:29]
    if (
        bit_depth != 8
        or color_type != 6
        or compression != 0
        or filter_method != 0
        or interlace != 0
    ):
        raise ManifestError(
            f"{label} must be a non-interlaced RGBA8 PNG"
        )

    idat = bytearray()
    offset = 8
    found_iend = False
    while offset + 12 <= len(raw):
        chunk_length = struct.unpack(">I", raw[offset : offset + 4])[0]
        chunk_end = offset + 12 + chunk_length
        if chunk_end > len(raw):
            raise ManifestError(f"{label} contains a truncated PNG chunk")
        chunk_type = raw[offset + 4 : offset + 8]
        payload = raw[offset + 8 : offset + 8 + chunk_length]
        expected_crc = struct.unpack(">I", raw[offset + 8 + chunk_length : chunk_end])[0]
        actual_crc = zlib.crc32(chunk_type)
        actual_crc = zlib.crc32(payload, actual_crc) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise ManifestError(f"{label} contains a PNG chunk with a stale CRC")
        if chunk_type == b"IDAT":
            idat.extend(payload)
        elif chunk_type == b"IEND":
            found_iend = True
            break
        offset = chunk_end
    if not idat or not found_iend:
        raise ManifestError(f"{label} is missing PNG image data")

    try:
        scanlines = zlib.decompress(bytes(idat))
    except zlib.error as error:
        raise ManifestError(f"{label} contains invalid compressed PNG data") from error
    bytes_per_pixel = 4
    row_width = width * bytes_per_pixel
    expected_size = (row_width + 1) * height
    if len(scanlines) != expected_size:
        raise ManifestError(f"{label} has an unexpected PNG scanline size")

    decoded = bytearray(width * height * bytes_per_pixel)
    previous = bytearray(row_width)
    source_offset = 0
    target_offset = 0
    for _ in range(height):
        filter_type = scanlines[source_offset]
        source_offset += 1
        source_row = scanlines[source_offset : source_offset + row_width]
        source_offset += row_width
        reconstructed = bytearray(row_width)
        for index, value in enumerate(source_row):
            left = reconstructed[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            above = previous[index]
            upper_left = previous[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            if filter_type == 0:
                predictor = 0
            elif filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = above
            elif filter_type == 3:
                predictor = (left + above) // 2
            elif filter_type == 4:
                predictor = _paeth_predictor(left, above, upper_left)
            else:
                raise ManifestError(f"{label} uses an unsupported PNG row filter")
            reconstructed[index] = (value + predictor) & 0xFF
        decoded[target_offset : target_offset + row_width] = reconstructed
        target_offset += row_width
        previous = reconstructed
    return bytes(decoded)


def _validate_ground_anchored_backdrop_png(
    filesystem_path: Path,
    pixel_size: tuple[int, int],
    label: str,
) -> None:
    raw = filesystem_path.read_bytes()
    width, height = pixel_size
    pixels = _decode_png_rgba8(raw, label, width, height)
    total = width * height
    nonzero = 0
    opaque = 0
    partial = 0
    low_alpha = 0
    bottom_opaque = 0
    highest_opaque_y = -1
    transparent_rgb_is_black = True
    partial_rgb_has_white_matte = False

    for pixel_index in range(total):
        offset = pixel_index * 4
        red, green, blue, alpha = pixels[offset : offset + 4]
        if alpha == 0:
            if red != 0 or green != 0 or blue != 0:
                transparent_rgb_is_black = False
            continue
        nonzero += 1
        if alpha >= 250:
            opaque += 1
            y = pixel_index // width
            highest_opaque_y = max(highest_opaque_y, y)
            if y == height - 1:
                bottom_opaque += 1
        else:
            partial += 1
            if alpha <= 15:
                low_alpha += 1
            if red >= 235 and green >= 235 and blue >= 235:
                partial_rgb_has_white_matte = True

    if nonzero == 0 or opaque == 0 or nonzero == total:
        raise ManifestError(
            f"{label} must contain both transparent background and opaque buildings"
        )
    if opaque / nonzero < BACKDROP_MIN_OPAQUE_SHARE:
        raise ManifestError(
            f"{label} has translucent building bodies; at least "
            f"{BACKDROP_MIN_OPAQUE_SHARE:.0%} of visible pixels must be opaque"
        )
    if partial / total > BACKDROP_MAX_PARTIAL_CANVAS_SHARE:
        raise ManifestError(f"{label} has an excessively wide antialias band")
    if low_alpha / total > BACKDROP_MAX_LOW_ALPHA_CANVAS_SHARE:
        raise ManifestError(f"{label} contains a broad near-transparent halo")
    if highest_opaque_y != height - 1:
        raise ManifestError(f"{label} must meet the bottom edge without a visible gap")
    if bottom_opaque / width < BACKDROP_MIN_BOTTOM_OPAQUE_SHARE:
        raise ManifestError(f"{label} needs a visible opaque footing on the bottom edge")
    if not transparent_rgb_is_black:
        raise ManifestError(f"{label} transparent pixels must use black RGB")
    if partial_rgb_has_white_matte:
        raise ManifestError(f"{label} antialias edge still contains the white production matte")


def _validate_structure_visual_png(
    filesystem_path: Path,
    pixel_size: tuple[int, int],
    label: str,
) -> None:
    width, height = pixel_size
    if max(width, height) > STRUCTURE_NATIVE_MAX_TEXTURE_DIMENSION:
        raise ManifestError(
            f"{label} exceeds the structure texture limit of "
            f"{STRUCTURE_NATIVE_MAX_TEXTURE_DIMENSION} pixels per axis"
        )
    if width * height > STRUCTURE_NATIVE_MAX_TEXTURE_PIXELS:
        raise ManifestError(
            f"{label} exceeds the decoded structure texture pixel budget"
        )
    raw = filesystem_path.read_bytes()
    pixels = _decode_png_rgba8(raw, label, width, height)
    has_visible_pixel = False
    transparent_rgb_is_black = True
    for offset in range(0, len(pixels), 4):
        red, green, blue, alpha = pixels[offset : offset + 4]
        if alpha == 0:
            if red != 0 or green != 0 or blue != 0:
                transparent_rgb_is_black = False
        else:
            has_visible_pixel = True
    if not has_visible_pixel:
        raise ManifestError(f"{label} must contain at least one visible pixel")
    if not transparent_rgb_is_black:
        raise ManifestError(f"{label} transparent pixels must use black RGB")


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


def _structure_local_topology(
    package: dict[str, Any],
    label: str,
    *,
    verify_declaration: bool = True,
) -> tuple[str, list[dict[str, Any]]]:
    size = _pair(package["size"], f"{label}.size")
    collision = _object(package["collision"], f"{label}.collision")
    if set(collision) != STRUCTURE_PACKAGE_COLLISION_KEYS:
        raise ManifestError(
            f"{label}.collision must contain exactly: "
            + ", ".join(sorted(STRUCTURE_PACKAGE_COLLISION_KEYS))
        )
    if collision["format"] != STRUCTURE_PACKAGE_COLLISION_FORMAT:
        raise ManifestError(
            f"{label}.collision.format must be {STRUCTURE_PACKAGE_COLLISION_FORMAT}"
        )
    if collision["base"] != "open_water":
        raise ManifestError(f"{label}.collision.base must be open_water")
    pixel_size_value = _pair(
        collision["pixel_size"],
        f"{label}.collision.pixel_size",
    )
    if any(
        not component.is_integer() or component <= 0.0
        for component in pixel_size_value
    ):
        raise ManifestError(
            f"{label}.collision.pixel_size must contain positive integers"
        )
    pixel_size = (int(pixel_size_value[0]), int(pixel_size_value[1]))
    world_units_per_pixel = _pair(
        collision["world_units_per_pixel"],
        f"{label}.collision.world_units_per_pixel",
    )
    if world_units_per_pixel != L05_WORLD_UNITS_PER_PIXEL:
        raise ManifestError(
            f"{label}.collision.world_units_per_pixel must be "
            f"{list(L05_WORLD_UNITS_PER_PIXEL)}"
        )
    if (
        pixel_size[0] * world_units_per_pixel[0],
        pixel_size[1] * world_units_per_pixel[1],
    ) != size:
        raise ManifestError(
            f"{label}.collision pixel mapping must cover the complete structure"
        )

    cells = bytearray([255]) * (pixel_size[0] * pixel_size[1])
    operation_ids: set[str] = set()
    resolved_operations: list[dict[str, Any]] = []
    for index, operation_value in enumerate(
        _array(collision["operations"], f"{label}.collision.operations")
    ):
        operation_label = f"{label}.collision.operations[{index}]"
        operation = _object(operation_value, operation_label)
        if set(operation) != STRUCTURE_PACKAGE_OPERATION_KEYS:
            raise ManifestError(
                f"{operation_label} must contain exactly id, op and rect_px"
            )
        operation_id = _non_empty_string(
            operation["id"],
            f"{operation_label}.id",
        )
        if operation_id in operation_ids:
            raise ManifestError(f"{operation_label}.id must be unique")
        operation_ids.add(operation_id)
        operation_kind = operation["op"]
        if operation_kind not in ("solid_rect", "open_rect"):
            raise ManifestError(
                f"{operation_label}.op must be solid_rect or open_rect"
            )
        rect_value = operation["rect_px"]
        if (
            not isinstance(rect_value, list)
            or len(rect_value) != 4
            or any(
                isinstance(component, bool) or not isinstance(component, int)
                for component in rect_value
            )
        ):
            raise ManifestError(
                f"{operation_label}.rect_px must contain four integers"
            )
        x, y, width, height = rect_value
        if (
            x < 0
            or y < 0
            or width <= 0
            or height <= 0
            or x + width > pixel_size[0]
            or y + height > pixel_size[1]
        ):
            raise ManifestError(
                f"{operation_label}.rect_px lies outside the structure raster"
            )
        value = 0 if operation_kind == "solid_rect" else 255
        row_bytes = bytes([value]) * width
        for row in range(y, y + height):
            start = row * pixel_size[0] + x
            cells[start : start + width] = row_bytes
        resolved_operations.append(
            {
                "id": operation_id,
                "op": operation_kind,
                "space": "structure_local_px",
                "rect_px": copy.deepcopy(rect_value),
            }
        )

    digest_payload = {
        "pixel_size": list(pixel_size),
        "world_units_per_pixel": list(world_units_per_pixel),
        "encoding": {"solid": 0, "open_water": 255},
        "cells_hex": bytes(cells).hex(),
    }
    local_digest = (
        f"structure-topology-v1:{_canonical_sha256(digest_payload)}"
    )
    declared_digest = package["local_topology_digest"]
    if verify_declaration and (
        not isinstance(declared_digest, str)
        or re.fullmatch(
            r"structure-topology-v1:[0-9a-f]{64}",
            declared_digest,
        )
        is None
        or declared_digest != local_digest
    ):
        raise ManifestError(
            f"{label}.local_topology_digest is stale; expected {local_digest}"
        )
    return local_digest, resolved_operations


def _resolve_structure_packages(
    manifest: dict[str, Any],
    *,
    verify_package_hashes: bool = True,
    structure_id_filter: str | None = None,
) -> dict[str, Any]:
    registry = _object(manifest["structures"], "structures")
    if set(registry) == STRUCTURE_ROOT_KEYS:
        # Synthetic expanded fixtures remain usable by low-level validator tests.
        return manifest
    if set(registry) != STRUCTURE_REGISTRY_KEYS:
        raise ManifestError("schema v6 structures must contain exactly instances")

    topology = _object(manifest["topology"], "topology")
    collision_declaration = _object(
        topology["collision_source"],
        "topology.collision_source",
    )
    canonical_digest = str(collision_declaration.get("canonical_digest", ""))
    partition_digest = str(collision_declaration.get("partition_digest", ""))
    if re.fullmatch(r"topology-v1:[0-9a-f]{64}", canonical_digest) is None:
        raise ManifestError(
            "topology.collision_source.canonical_digest must be declared "
            "before resolving structures"
        )
    if re.fullmatch(r"partition-v1:[0-9a-f]{64}", partition_digest) is None:
        raise ManifestError(
            "topology.collision_source.partition_digest must be declared "
            "before resolving structures"
        )

    templates: list[dict[str, Any]] = []
    templates_by_id: dict[str, dict[str, Any]] = {}
    resolved_instances: list[dict[str, Any]] = []
    package_visual_assets: list[dict[str, Any]] = []
    registry_ids: set[str] = set()
    package_paths: set[str] = set()
    selected_structure_found = False

    for index, registry_value in enumerate(
        _array(registry["instances"], "structures.instances")
    ):
        registry_label = f"structures.instances[{index}]"
        record = _object(registry_value, registry_label)
        record_keys = set(record)
        if (
            not STRUCTURE_REGISTRY_INSTANCE_REQUIRED_KEYS.issubset(record_keys)
            or not record_keys.issubset(
                STRUCTURE_REGISTRY_INSTANCE_REQUIRED_KEYS
                | STRUCTURE_REGISTRY_INSTANCE_OPTIONAL_KEYS
            )
        ):
            raise ManifestError(
                f"{registry_label} must contain id, origin, enabled and package; "
                "landmark_id is optional"
            )
        structure_id = _non_empty_string(record["id"], f"{registry_label}.id")
        if re.fullmatch(r"[a-z][a-z0-9_]*", structure_id) is None:
            raise ManifestError(
                f"{registry_label}.id must be lowercase snake_case"
            )
        if structure_id in registry_ids:
            raise ManifestError(f"{registry_label}.id must be unique")
        registry_ids.add(structure_id)
        _pair(record["origin"], f"{registry_label}.origin")
        _boolean(record["enabled"], f"{registry_label}.enabled")
        if "landmark_id" in record:
            _non_empty_string(record["landmark_id"], f"{registry_label}.landmark_id")

        package_reference = _object(
            record["package"],
            f"{registry_label}.package",
        )
        if set(package_reference) != STRUCTURE_PACKAGE_REFERENCE_KEYS:
            raise ManifestError(
                f"{registry_label}.package must contain exactly format, path and sha256"
            )
        if package_reference["format"] != STRUCTURE_PACKAGE_REFERENCE_FORMAT:
            raise ManifestError(
                f"{registry_label}.package.format must be "
                f"{STRUCTURE_PACKAGE_REFERENCE_FORMAT}"
            )
        expected_package_path = (
            f"structures/{structure_id}/structure_manifest.json"
        )
        package_path = _non_empty_string(
            package_reference["path"],
            f"{registry_label}.package.path",
        )
        if package_path != expected_package_path:
            raise ManifestError(
                f"{registry_label}.package.path must be {expected_package_path}"
            )
        if package_path in package_paths:
            raise ManifestError(
                f"{registry_label}.package.path must be referenced exactly once"
            )
        package_paths.add(package_path)
        if structure_id_filter is not None and structure_id != structure_id_filter:
            # A package-local build validates the public registry record, but it
            # must not open another producer's private manifest or members.
            continue
        selected_structure_found = True
        package_filesystem_path = (WORKBENCH_DIR / package_path).resolve()
        try:
            package_filesystem_path.relative_to(WORKBENCH_DIR.resolve())
        except ValueError as error:
            raise ManifestError(
                f"{registry_label}.package.path escapes the workbench"
            ) from error
        if not package_filesystem_path.is_file():
            raise ManifestError(
                f"structure package does not exist: {package_path}"
            )
        package_raw = package_filesystem_path.read_bytes()
        actual_package_sha = hashlib.sha256(package_raw).hexdigest()
        declared_package_sha = _sha256(
            package_reference["sha256"],
            f"{registry_label}.package.sha256",
        )
        if verify_package_hashes and actual_package_sha != declared_package_sha:
            raise ManifestError(
                f"{registry_label}.package.sha256 is stale; "
                f"expected {actual_package_sha}"
            )
        try:
            package = json.loads(package_raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ManifestError(
                f"invalid structure package JSON {package_path}: {error}"
            ) from error
        package = _object(package, f"structure package {structure_id}")
        package_label = f"structure package {structure_id}"
        if set(package) != STRUCTURE_PACKAGE_KEYS:
            raise ManifestError(
                f"{package_label} must contain exactly: "
                + ", ".join(sorted(STRUCTURE_PACKAGE_KEYS))
            )
        if package["schema_version"] != 1:
            raise ManifestError(f"{package_label}.schema_version must be 1")
        if package["format"] != STRUCTURE_PACKAGE_FORMAT:
            raise ManifestError(
                f"{package_label}.format must be {STRUCTURE_PACKAGE_FORMAT}"
            )

        template = _object(package["template"], f"{package_label}.template")
        if set(template) != STRUCTURE_TEMPLATE_KEYS:
            raise ManifestError(
                f"{package_label}.template has an invalid exact key set"
            )
        template_id = _non_empty_string(
            template["id"],
            f"{package_label}.template.id",
        )
        previous_template = templates_by_id.get(template_id)
        if previous_template is None:
            templates_by_id[template_id] = copy.deepcopy(template)
            templates.append(copy.deepcopy(template))
        elif _normalize_canonical_numbers(previous_template) != _normalize_canonical_numbers(template):
            raise ManifestError(
                f"{package_label}.template conflicts with template {template_id}"
            )

        local_topology_digest, collision_operations = _structure_local_topology(
            package,
            package_label,
        )
        for operation in collision_operations:
            operation["structure_id"] = structure_id

        package_directory = package_filesystem_path.parent
        scripts = _array(package["scripts"], f"{package_label}.scripts")
        if not scripts:
            raise ManifestError(f"{package_label}.scripts must contain a controller")
        scripts_by_role: dict[str, str] = {}
        for script_index, script_value in enumerate(scripts):
            script_label = f"{package_label}.scripts[{script_index}]"
            script = _object(script_value, script_label)
            if set(script) != STRUCTURE_PACKAGE_SCRIPT_KEYS:
                raise ManifestError(
                    f"{script_label} must contain exactly role, path and sha256"
                )
            role = _non_empty_string(script["role"], f"{script_label}.role")
            if re.fullmatch(r"[a-z][a-z0-9_]*", role) is None or role in scripts_by_role:
                raise ManifestError(
                    f"{script_label}.role must be unique lowercase snake_case"
                )
            _member_path, script_filesystem_path, script_resource_path = (
                _structure_package_member_path(
                    package_directory,
                    script["path"],
                    f"{script_label}.path",
                )
            )
            if not script_filesystem_path.is_file():
                raise ManifestError(f"{script_label}.path does not exist")
            expected_script_sha = _sha256(
                script["sha256"],
                f"{script_label}.sha256",
            )
            actual_script_sha = hashlib.sha256(
                script_filesystem_path.read_bytes()
            ).hexdigest()
            if actual_script_sha != expected_script_sha:
                raise ManifestError(
                    f"{script_label}.sha256 is stale; expected {actual_script_sha}"
                )
            scripts_by_role[role] = script_resource_path
        if STRUCTURE_PACKAGE_REQUIRED_SCRIPT_ROLE not in scripts_by_role:
            raise ManifestError(
                f"{package_label}.scripts must contain exactly one controller role"
            )

        runtime = _object(package["runtime"], f"{package_label}.runtime")

        attempt_state = _object(
            package["attempt_state"],
            f"{package_label}.attempt_state",
        )
        if attempt_state != STRUCTURE_PACKAGE_ATTEMPT_STATE:
            raise ManifestError(
                f"{package_label}.attempt_state must disable persistence and checkpoints"
            )

        references = _array(package["references"], f"{package_label}.references")
        for reference_index, reference_value in enumerate(references):
            reference_label = f"{package_label}.references[{reference_index}]"
            reference = _object(reference_value, reference_label)
            if set(reference) != STRUCTURE_PACKAGE_REFERENCE_KEYS_EXACT:
                raise ManifestError(f"{reference_label} has an invalid exact key set")
            if reference["authority"] is not False:
                raise ManifestError(f"{reference_label}.authority must be false")
            if reference["role"] != "design_reference_only":
                raise ManifestError(
                    f"{reference_label}.role must be design_reference_only"
                )
            _reference_path, reference_filesystem_path, _resource_path = (
                _structure_package_member_path(
                    package_directory,
                    reference["path"],
                    f"{reference_label}.path",
                )
            )
            if not reference_filesystem_path.is_file():
                raise ManifestError(f"{reference_label}.path does not exist")
            expected_reference_sha = _sha256(
                reference["sha256"],
                f"{reference_label}.sha256",
            )
            actual_reference_sha = hashlib.sha256(
                reference_filesystem_path.read_bytes()
            ).hexdigest()
            if actual_reference_sha != expected_reference_sha:
                raise ManifestError(
                    f"{reference_label}.sha256 is stale; "
                    f"expected {actual_reference_sha}"
                )
            excluded_topics = _array(
                reference["excluded_topics"],
                f"{reference_label}.excluded_topics",
            )
            if set(excluded_topics) != {
                "checkpoint",
                "save_load",
                "point_of_no_return",
                "collapse_failure",
            }:
                raise ManifestError(
                    f"{reference_label}.excluded_topics must explicitly exclude "
                    "the rejected document contracts"
                )

        resolved_assets: list[dict[str, Any]] = []
        for asset_index, asset_value in enumerate(
            _array(package["visual_assets"], f"{package_label}.visual_assets")
        ):
            asset_label = f"{package_label}.visual_assets[{asset_index}]"
            asset = _object(asset_value, asset_label)
            if set(asset) != STRUCTURE_PACKAGE_VISUAL_ASSET_KEYS:
                raise ManifestError(f"{asset_label} has an invalid exact key set")
            asset_path, asset_filesystem_path, _asset_resource_path = (
                _structure_package_member_path(
                    package_directory,
                    asset["path"],
                    f"{asset_label}.path",
                )
            )
            if not asset_filesystem_path.is_file():
                raise ManifestError(f"{asset_label}.path does not exist")
            resolved_asset = copy.deepcopy(asset)
            resolved_asset["path"] = asset_path
            resolved_asset["topology_digest"] = canonical_digest
            resolved_asset["partition_digest"] = partition_digest
            resolved_asset["structure_id"] = structure_id
            resolved_assets.append(resolved_asset)
        package_visual_assets.extend(resolved_assets)

        resolved_instance: dict[str, Any] = {
            "id": structure_id,
            "template_id": template_id,
            "origin": copy.deepcopy(record["origin"]),
            "size": copy.deepcopy(package["size"]),
            "enabled": bool(record["enabled"]),
            "topology_digest": canonical_digest,
            "partition_digest": partition_digest,
            "sockets": copy.deepcopy(package["sockets"]),
            "runtime": copy.deepcopy(runtime),
            "controller_script": scripts_by_role[STRUCTURE_PACKAGE_REQUIRED_SCRIPT_ROLE],
            "package_path": package_path,
            "package_sha256": actual_package_sha,
            "local_topology_digest": local_topology_digest,
            "collision_operations": collision_operations,
            "structure_scene_path": (
                "res://underwater_map_workbench/"
                f"structures/{structure_id}/generated/structure.tscn"
            ),
        }
        if "landmark_id" in record:
            resolved_instance["landmark_id"] = record["landmark_id"]
        resolved_instances.append(resolved_instance)

    if structure_id_filter is not None and not selected_structure_found:
        raise ManifestError(f"unknown structure package: {structure_id_filter}")

    resolved_manifest = copy.deepcopy(manifest)
    resolved_manifest["structures"] = {
        "templates": templates,
        "instances": resolved_instances,
    }
    resolved_visual = _object(resolved_manifest["visual"], "visual")
    resolved_visual["assets"] = [
        *copy.deepcopy(_array(resolved_visual["assets"], "visual.assets")),
        *package_visual_assets,
    ]
    return resolved_manifest


def _structure_semantic_projection(
    structures: dict[str, Any],
) -> dict[str, Any]:
    projected_instances: list[dict[str, Any]] = []
    for value in _array(structures["instances"], "structures.instances"):
        instance = _object(value, "structure instance")
        projected = {
            key: copy.deepcopy(instance[key])
            for key in (
                "id",
                "template_id",
                "origin",
                "size",
                "enabled",
                "topology_digest",
                "partition_digest",
                "sockets",
            )
        }
        if "landmark_id" in instance:
            projected["landmark_id"] = copy.deepcopy(instance["landmark_id"])
        if "runtime" in instance:
            projected["runtime"] = copy.deepcopy(instance["runtime"])
        projected_instances.append(projected)
    return {
        "templates": copy.deepcopy(structures["templates"]),
        "instances": projected_instances,
    }


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
            "partition_digest": collision.get("partition_digest"),
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
        "structures": _structure_semantic_projection(manifest["structures"]),
        "gameplay": _gameplay_semantic_projection(manifest["gameplay"]),
        "campaign": copy.deepcopy(manifest["campaign"]),
    }
    return f"manifest-v2:{_canonical_sha256(payload)}"


def _presentation_fingerprint(manifest: dict[str, Any]) -> str:
    revision = _object(manifest.get("revision"), "revision")
    payload = {
        "presentation_revision": revision["presentation_revision"],
        "portal_backdrop_clearance_contract": PORTAL_BACKDROP_CLEARANCE_CONTRACT,
        "map": {
            "grid": copy.deepcopy(manifest["map"]["grid"]),
            "world_size": copy.deepcopy(manifest["map"]["world_size"]),
        },
        "regions": copy.deepcopy(manifest["regions"]),
        "landmarks": copy.deepcopy(manifest["landmarks"]),
        "structures": _structure_semantic_projection(manifest["structures"]),
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
    if len(_color(visual["water_color"], "visual.water_color")) != 6:
        raise ManifestError("visual.water_color must be an opaque RGB hex color")
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
        rgb_modulate = _color(
            layer["rgb_modulate"],
            f"{label}.rgb_modulate",
        )
        if len(rgb_modulate) != 6:
            raise ManifestError(
                f"{label}.rgb_modulate must be an opaque RGB hex color"
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

        if expected_id == "L00":
            if (
                layer["role"] != "water_base"
                or layer["geometry_role"] != "none"
                or layer["affordance_policy"] != NO_BLOCKING_POLICY
            ):
                raise ManifestError(
                    "L00 must be the nonblocking water_base background"
                )
            if not layer["enabled"] or layer["reserved"]:
                raise ManifestError("L00 must be enabled and not reserved")
            if rgb_modulate != "ffffff":
                raise ManifestError(
                    "L00.rgb_modulate must remain ffffff; water_color is its sole color"
                )
        elif expected_id == "L05":
            if (
                layer["role"] != "collider_authority"
                or layer["geometry_role"] != "collider_authority"
                or layer["affordance_policy"] != "collider_authority"
            ):
                raise ManifestError("L05 must be the collider authority")
            if not layer["enabled"] or layer["reserved"]:
                raise ManifestError("L05 must be enabled and not reserved")
        elif expected_id in NONBLOCKING_TEXTURE_LAYER_IDS:
            if layer["affordance_policy"] != OPEN_WATER_BACKDROP_POLICY:
                raise ManifestError(
                    f"{expected_id} must use the open-water backdrop policy"
                )
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
    element_node_keys: set[tuple[str, str, str, str]] = set()
    structure_build: dict[str, Any] = topology_build["structure_build"]
    for index, asset_value in enumerate(assets):
        label = f"visual.assets[{index}]"
        asset = _object(asset_value, label)
        kind_value = asset.get("kind")
        is_structure_asset = kind_value in {
            STRUCTURE_INTERIOR_TEXTURE_KIND,
            STRUCTURE_OWNER_MASKED_TEXTURE_KIND,
        }
        expected_keys = (
            STRUCTURE_VISUAL_ASSET_KEYS
            if is_structure_asset
            else VISUAL_ASSET_KEYS
        )
        if set(asset) != expected_keys:
            raise ManifestError(
                f"{label} must contain exactly: "
                + ", ".join(sorted(expected_keys))
            )
        asset_id = _non_empty_string(asset["id"], f"{label}.id")
        if asset_id in asset_ids:
            raise ManifestError(f"{label}.id must be unique")
        asset_ids.add(asset_id)
        layer_id = _non_empty_string(asset["layer_id"], f"{label}.layer_id")
        group_id = _non_empty_string(asset["group_id"], f"{label}.group_id")
        if SAFE_VISUAL_GROUP_ID.fullmatch(group_id) is None:
            raise ManifestError(
                f"{label}.group_id must start with a letter and contain only "
                "ASCII letters, digits and underscores"
            )
        kind = _non_empty_string(asset["kind"], f"{label}.kind")
        if (layer_id, kind) not in {
            ("L01", "texture_rect"),
            ("L01", COMPOSITION_PROXY_KIND),
            ("L02", "texture_rect"),
            ("L02", COMPOSITION_PROXY_KIND),
            ("L05", "collision_masked_material"),
            ("L04", STRUCTURE_INTERIOR_TEXTURE_KIND),
            ("L05", STRUCTURE_OWNER_MASKED_TEXTURE_KIND),
        }:
            raise ManifestError(
                f"{label} must be L01-L02/texture_rect|{COMPOSITION_PROXY_KIND} "
                "or a typed L04/L05 structure-local texture"
            )
        structure_id = ""
        if is_structure_asset:
            structure_id = _non_empty_string(
                asset["structure_id"],
                f"{label}.structure_id",
            )
        element_node_key = (
            structure_id,
            layer_id,
            group_id,
            _safe_node_name(asset_id),
        )
        if element_node_key in element_node_keys:
            raise ManifestError(
                f"{label}.id collides with another generated visual node name"
            )
        element_node_keys.add(element_node_key)
        enabled = _boolean(asset["enabled"], f"{label}.enabled")
        _non_empty_string(asset["affordance"], f"{label}.affordance")

        if is_structure_asset:
            instance = structure_build["instances_by_id"].get(structure_id)
            if instance is None:
                raise ManifestError(
                    f"{label}.structure_id references an unknown structure"
                )
            if enabled and not instance["enabled"]:
                raise ManifestError(
                    f"{label} cannot be enabled for a disabled structure"
                )
            local_rect = _rect(asset["local_rect"], f"{label}.local_rect")
            if not _rect_contains_rect(
                (0.0, 0.0, instance["size"][0], instance["size"][1]),
                local_rect,
            ) or local_rect[2] <= 0.0 or local_rect[3] <= 0.0:
                raise ManifestError(
                    f"{label}.local_rect must lie inside its structure"
                )
            for component, step in zip(
                local_rect,
                L05_WORLD_UNITS_PER_PIXEL + L05_WORLD_UNITS_PER_PIXEL,
            ):
                quotient = component / step
                if not math.isclose(
                    quotient,
                    round(quotient),
                    rel_tol=0.0,
                    abs_tol=1.0e-9,
                ):
                    raise ManifestError(
                        f"{label}.local_rect must align to the L05 40 x 40 grid"
                    )
            _, filesystem_path, pixel_size = _read_hashed_png(
                asset["path"],
                asset["sha256"],
                asset["pixel_size"],
                label,
            )
            if local_rect[2:] != (float(pixel_size[0]), float(pixel_size[1])):
                raise ManifestError(
                    f"{label}.local_rect size must equal pixel_size exactly "
                    "(one source pixel per world unit; no resizing)"
                )
            _validate_structure_visual_png(filesystem_path, pixel_size, label)
            topology_digest = asset["topology_digest"]
            partition_digest = asset["partition_digest"]
            if topology_digest != topology_build.get("canonical_digest"):
                raise ManifestError(f"{label}.topology_digest is stale")
            if partition_digest != topology_build.get("partition_digest"):
                raise ManifestError(f"{label}.partition_digest is stale")
            if topology_digest != instance["source"]["topology_digest"]:
                raise ManifestError(
                    f"{label}.topology_digest must match its structure"
                )
            if partition_digest != instance["source"]["partition_digest"]:
                raise ManifestError(
                    f"{label}.partition_digest must match its structure"
                )
            if kind == STRUCTURE_INTERIOR_TEXTURE_KIND:
                if asset["affordance"] != STRUCTURE_INTERIOR_AFFORDANCE:
                    raise ManifestError(
                        f"{label}.affordance must be {STRUCTURE_INTERIOR_AFFORDANCE}"
                    )
            elif asset["affordance"] != STRUCTURE_OWNER_AFFORDANCE:
                raise ManifestError(
                    f"{label}.affordance must be {STRUCTURE_OWNER_AFFORDANCE}"
                )
            shader_path = WORKBENCH_DIR / STRUCTURE_CLIP_SHADER_PATH
            if not shader_path.is_file():
                raise ManifestError(
                    f"missing structure clip shader: {STRUCTURE_CLIP_SHADER_PATH}"
                )
            continue

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
        if kind == COMPOSITION_PROXY_KIND:
            if asset["path"] != "" or asset["sha256"] != "":
                raise ManifestError(
                    f"{label} composition proxy requires empty path and sha256"
                )
            declared_size = _pair(asset["pixel_size"], f"{label}.pixel_size")
            if any(
                not component.is_integer() or component <= 0
                for component in declared_size
            ):
                raise ManifestError(
                    f"{label}.pixel_size must contain positive integers"
                )
            pixel_size = (int(declared_size[0]), int(declared_size[1]))
            if topology_digest != "":
                raise ManifestError(
                    f"{label} composition proxy requires an empty topology_digest"
                )
            if asset["affordance"] != NONBLOCKING_BACKDROP_AFFORDANCE:
                raise ManifestError(
                    f"{label} composition proxy requires "
                    f"affordance={NONBLOCKING_BACKDROP_AFFORDANCE}"
                )
            if world_rect[2:] != (float(pixel_size[0]), float(pixel_size[1])):
                raise ManifestError(
                    f"{label}.world_rect size must equal pixel_size exactly "
                    "(one planned source pixel per world unit; no resizing)"
                )
            continue

        _, filesystem_path, pixel_size = _read_hashed_png(
            asset["path"],
            asset["sha256"],
            asset["pixel_size"],
            label,
        )
        if layer_id in NONBLOCKING_TEXTURE_LAYER_IDS:
            _validate_ground_anchored_backdrop_png(
                filesystem_path,
                pixel_size,
                label,
            )
            if topology_digest != "":
                raise ManifestError(
                    f"{label} on {layer_id} requires an empty topology_digest"
                )
            if asset["affordance"] != NONBLOCKING_BACKDROP_AFFORDANCE:
                raise ManifestError(
                    f"{label} on {layer_id} requires "
                    f"affordance={NONBLOCKING_BACKDROP_AFFORDANCE}"
                )
            if world_rect[2:] != (float(pixel_size[0]), float(pixel_size[1])):
                raise ManifestError(
                    f"{label}.world_rect size must equal pixel_size exactly "
                    "(one source pixel per world unit; no resizing)"
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


def _rect_contains_rect(
    outer: tuple[float, float, float, float],
    inner: tuple[float, float, float, float],
) -> bool:
    return (
        inner[0] >= outer[0]
        and inner[1] >= outer[1]
        and inner[0] + inner[2] <= outer[0] + outer[2]
        and inner[1] + inner[3] <= outer[1] + outer[3]
    )






def _validate_structures(
    manifest: dict[str, Any],
    world_size: tuple[float, float],
) -> dict[str, Any]:
    structures = _object(manifest["structures"], "structures")
    if set(structures) != STRUCTURE_ROOT_KEYS:
        raise ManifestError("structures must contain exactly templates and instances")

    templates = _array(structures["templates"], "structures.templates")
    instances = _array(structures["instances"], "structures.instances")
    templates_by_id: dict[str, dict[str, Any]] = {}
    for index, template_value in enumerate(templates):
        label = f"structures.templates[{index}]"
        template = _object(template_value, label)
        if set(template) != STRUCTURE_TEMPLATE_KEYS:
            raise ManifestError(
                f"{label} must contain exactly: "
                + ", ".join(sorted(STRUCTURE_TEMPLATE_KEYS))
            )
        template_id = _non_empty_string(template["id"], f"{label}.id")
        if template_id in templates_by_id:
            raise ManifestError(f"{label}.id must be unique")
        template_kind = _non_empty_string(template["kind"], f"{label}.kind")
        if re.fullmatch(r"[a-z][a-z0-9_]*", template_kind) is None:
            raise ManifestError(f"{label}.kind must be lowercase snake_case")
        if template["interior_layer_id"] != "L04":
            raise ManifestError(f"{label}.interior_layer_id must be L04")
        if template["collider_layer_id"] != "L05":
            raise ManifestError(f"{label}.collider_layer_id must be L05")
        socket_kinds = _array(
            template["allowed_socket_kinds"],
            f"{label}.allowed_socket_kinds",
        )
        if not socket_kinds:
            raise ManifestError(f"{label}.allowed_socket_kinds must not be empty")
        normalized_socket_kinds: list[str] = []
        for socket_kind_index, socket_kind_value in enumerate(socket_kinds):
            socket_kind = _non_empty_string(
                socket_kind_value,
                f"{label}.allowed_socket_kinds[{socket_kind_index}]",
            )
            if (
                re.fullmatch(r"[a-z][a-z0-9_]*", socket_kind) is None
                or socket_kind in normalized_socket_kinds
            ):
                raise ManifestError(
                    f"{label}.allowed_socket_kinds must contain unique "
                    "lowercase snake_case values"
                )
            normalized_socket_kinds.append(socket_kind)
        templates_by_id[template_id] = template

    instances_by_id: dict[str, dict[str, Any]] = {}
    resolved_instances: list[dict[str, Any]] = []
    generated_node_names: set[str] = set()
    for index, instance_value in enumerate(instances):
        label = f"structures.instances[{index}]"
        instance = _object(instance_value, label)
        instance_keys = set(instance)
        allowed_instance_keys = (
            STRUCTURE_INSTANCE_REQUIRED_KEYS | STRUCTURE_INSTANCE_OPTIONAL_KEYS
        )
        if (
            not STRUCTURE_INSTANCE_REQUIRED_KEYS.issubset(instance_keys)
            or not instance_keys.issubset(allowed_instance_keys)
        ):
            raise ManifestError(
                f"{label} must contain required fields: "
                + ", ".join(sorted(STRUCTURE_INSTANCE_REQUIRED_KEYS))
                + "; optional fields: landmark_id, runtime"
            )
        instance_id = _non_empty_string(instance["id"], f"{label}.id")
        if instance_id in instances_by_id or instance_id in templates_by_id:
            raise ManifestError(f"{label}.id must be globally unique")
        node_name = _safe_node_name(instance_id)
        if node_name in generated_node_names:
            raise ManifestError(f"{label}.id collides with a generated node name")
        generated_node_names.add(node_name)
        template_id = _non_empty_string(
            instance["template_id"],
            f"{label}.template_id",
        )
        template = templates_by_id.get(template_id)
        if template is None:
            raise ManifestError(f"{label}.template_id references an unknown template")
        if "landmark_id" in instance:
            _non_empty_string(instance["landmark_id"], f"{label}.landmark_id")
        origin = _pair(instance["origin"], f"{label}.origin")
        size = _pair(instance["size"], f"{label}.size")
        if min(size) <= 0.0:
            raise ManifestError(f"{label}.size must be positive")
        if (
            origin[0] < 0.0
            or origin[1] < 0.0
            or origin[0] + size[0] > world_size[0]
            or origin[1] + size[1] > world_size[1]
        ):
            raise ManifestError(f"{label} lies outside the map")
        enabled = _boolean(instance["enabled"], f"{label}.enabled")
        topology_digest = instance["topology_digest"]
        partition_digest = instance["partition_digest"]
        if not isinstance(topology_digest, str) or re.fullmatch(
            r"topology-v1:[0-9a-f]{64}", topology_digest
        ) is None:
            raise ManifestError(f"{label}.topology_digest must be topology-v1:<sha256>")
        if not isinstance(partition_digest, str) or re.fullmatch(
            r"partition-v1:[0-9a-f]{64}", partition_digest
        ) is None:
            raise ManifestError(f"{label}.partition_digest must be partition-v1:<sha256>")

        sockets = _array(instance["sockets"], f"{label}.sockets")
        socket_ids: set[str] = set()
        socket_file_names: set[str] = set()
        sockets_by_id: dict[str, dict[str, Any]] = {}
        for socket_index, socket_value in enumerate(sockets):
            socket_label = f"{label}.sockets[{socket_index}]"
            socket = _object(socket_value, socket_label)
            if set(socket) != STRUCTURE_SOCKET_KEYS:
                raise ManifestError(
                    f"{socket_label} must contain exactly id, kind and local_rect"
                )
            socket_id = _non_empty_string(socket["id"], f"{socket_label}.id")
            if socket_id in socket_ids:
                raise ManifestError(f"{socket_label}.id must be unique within its structure")
            socket_ids.add(socket_id)
            socket_file_name = _safe_node_name(socket_id)
            if socket_file_name in socket_file_names:
                raise ManifestError(
                    f"{socket_label}.id collides with another generated socket-card name"
                )
            socket_file_names.add(socket_file_name)
            socket_kind = _non_empty_string(socket["kind"], f"{socket_label}.kind")
            if socket_kind not in template["allowed_socket_kinds"]:
                raise ManifestError(f"{socket_label}.kind is not allowed by its template")
            local_rect = _rect(socket["local_rect"], f"{socket_label}.local_rect")
            if (
                local_rect[0] < 0.0
                or local_rect[1] < 0.0
                or local_rect[2] <= 0.0
                or local_rect[3] <= 0.0
                or local_rect[0] + local_rect[2] > size[0]
                or local_rect[1] + local_rect[3] > size[1]
            ):
                raise ManifestError(f"{socket_label}.local_rect lies outside the structure")
            for component, step in zip(
                local_rect,
                L05_WORLD_UNITS_PER_PIXEL + L05_WORLD_UNITS_PER_PIXEL,
            ):
                quotient = component / step
                if not math.isclose(
                    quotient,
                    round(quotient),
                    rel_tol=0.0,
                    abs_tol=1.0e-9,
                ):
                    raise ManifestError(
                        f"{socket_label}.local_rect must align to the L05 40 x 40 grid"
                    )
            sockets_by_id[socket_id] = socket

        if "runtime" in instance:
            _object(instance["runtime"], f"{label}.runtime")

        resolved = {
            "source": instance,
            "id": instance_id,
            "template": template,
            "origin": origin,
            "size": size,
            "enabled": enabled,
            "sockets_by_id": sockets_by_id,
        }
        instances_by_id[instance_id] = resolved
        resolved_instances.append(resolved)

    return {
        "source": structures,
        "templates": templates,
        "instances": resolved_instances,
        "templates_by_id": templates_by_id,
        "instances_by_id": instances_by_id,
    }


def _validate_structure_bindings(
    structure_build: dict[str, Any],
    landmark_ids: set[str],
    region_ids: set[str],
    topology_build: dict[str, Any],
) -> None:
    expected_topology_digest = str(topology_build.get("canonical_digest", ""))
    expected_partition_digest = str(topology_build.get("partition_digest", ""))
    owner_ids = set(topology_build.get("owner_ids", []))

    for instance in structure_build["instances"]:
        source: dict[str, Any] = instance["source"]
        instance_id = str(instance["id"])
        if instance_id in landmark_ids or instance_id in region_ids or instance_id == "exit":
            raise ManifestError(
                f"structure instance ID {instance_id} collides with another manifest ID"
            )
        landmark_id = source.get("landmark_id")
        if landmark_id is not None and landmark_id not in landmark_ids:
            raise ManifestError(
                f"structure instance {instance_id} references an unknown landmark"
            )
        if source["topology_digest"] != expected_topology_digest:
            raise ManifestError(
                f"structure instance {instance_id}.topology_digest is stale"
            )
        if source["partition_digest"] != expected_partition_digest:
            raise ManifestError(
                f"structure instance {instance_id}.partition_digest is stale"
            )
        if (
            source.get("runtime") is not None
            and instance["enabled"]
            and instance_id not in owner_ids
        ):
            raise ManifestError(
                f"structure instance {instance_id}.runtime requires "
                "an enabled owner partition"
            )


def _validate_topology(
    manifest: dict[str, Any],
    world_size: tuple[float, float],
    structure_build: dict[str, Any],
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
        else base_collision_keys | {"canonical_digest", "partition_digest", "mapping"}
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
        if any(instance["enabled"] for instance in structure_build["instances"]):
            raise ManifestError("enabled structures require an owned L05 collision source")
        if source_format != "none":
            raise ManifestError("open_world requires collision_source.format none")
        if collision["path"] != "" or collision["sha256"] != "":
            raise ManifestError("a none collision source must have empty path and sha256")
        if pixel_size != (0.0, 0.0) or world_units_per_pixel != (0.0, 0.0):
            raise ManifestError("a none collision source must have zero sizes")
        topology_build = {
            "mode": "open_world",
            "structure_build": structure_build,
        }
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
        if payload["schema_version"] != 2:
            raise ManifestError("L05 payload schema_version must be 2")
        if payload["base"] != "open_water":
            raise ManifestError("L05 payload base must be open_water")

        mapping_origin = _pair(
            mapping["world_origin"],
            "topology.collision_source.mapping.world_origin",
        )
        enabled_instances = [
            instance
            for instance in structure_build["instances"]
            if instance["enabled"]
        ]
        owner_ids = ["", "world", *(str(instance["id"]) for instance in enabled_instances)]
        owner_index_by_id = {
            owner_id: owner_index for owner_index, owner_id in enumerate(owner_ids)
        }
        for instance in structure_build["instances"]:
            label = f"structure instance {instance['id']}"
            origin = instance["origin"]
            size = instance["size"]
            origin_px_float = (
                (origin[0] - mapping_origin[0]) / world_units_per_pixel[0],
                (origin[1] - mapping_origin[1]) / world_units_per_pixel[1],
            )
            size_px_float = (
                size[0] / world_units_per_pixel[0],
                size[1] / world_units_per_pixel[1],
            )
            if any(
                not component.is_integer()
                for component in (*origin_px_float, *size_px_float)
            ):
                raise ManifestError(f"{label} must align exactly to the L05 pixel grid")
            origin_px = (int(origin_px_float[0]), int(origin_px_float[1]))
            size_px = (int(size_px_float[0]), int(size_px_float[1]))
            if (
                origin_px[0] < 0
                or origin_px[1] < 0
                or size_px[0] <= 0
                or size_px[1] <= 0
                or origin_px[0] + size_px[0] > L05_PIXEL_SIZE[0]
                or origin_px[1] + size_px[1] > L05_PIXEL_SIZE[1]
            ):
                raise ManifestError(f"{label} raster bounds lie outside L05")
            instance["origin_px"] = origin_px
            instance["size_px"] = size_px

        global_operations = _array(
            payload["operations"],
            "L05 payload.operations",
        )
        for index, operation_value in enumerate(global_operations):
            operation = _object(
                operation_value,
                f"L05 payload.operations[{index}]",
            )
            if operation.get("space") != "world_px":
                raise ManifestError(
                    "the global L05 payload may contain only world_px operations; "
                    "structure-local geometry belongs to its package"
                )
        operations = copy.deepcopy(global_operations)
        for instance in structure_build["instances"]:
            if not instance["enabled"]:
                continue
            operations.extend(
                copy.deepcopy(
                    instance["source"].get("collision_operations", [])
                )
            )
        cells = bytearray([open_water]) * (L05_PIXEL_SIZE[0] * L05_PIXEL_SIZE[1])
        solid_owner_cells = [0] * (L05_PIXEL_SIZE[0] * L05_PIXEL_SIZE[1])
        operation_ids: set[str] = set()
        for index, operation_value in enumerate(operations):
            label = f"L05 payload.operations[{index}]"
            operation = _object(operation_value, label)
            space = operation.get("space")
            if space == "world_px":
                expected_operation_keys = {"id", "op", "space", "rect_px"}
            elif space == "structure_local_px":
                expected_operation_keys = {
                    "id",
                    "op",
                    "space",
                    "structure_id",
                    "rect_px",
                }
            else:
                raise ManifestError(
                    f"{label}.space must be world_px or structure_local_px"
                )
            if set(operation) != expected_operation_keys:
                raise ManifestError(
                    f"{label} has an invalid exact key set for space={space}"
                )
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
            solid_owner_index: int
            if space == "world_px":
                world_x = x
                world_y = y
                if x + width > L05_PIXEL_SIZE[0] or y + height > L05_PIXEL_SIZE[1]:
                    raise ManifestError(f"{label}.rect_px lies outside the L05 raster")
                solid_owner_index = owner_index_by_id["world"]
            else:
                structure_id = _non_empty_string(
                    operation["structure_id"],
                    f"{label}.structure_id",
                )
                instance = structure_build["instances_by_id"].get(structure_id)
                if instance is None:
                    raise ManifestError(f"{label}.structure_id references an unknown structure")
                if not instance["enabled"]:
                    raise ManifestError(f"{label}.structure_id references a disabled structure")
                size_px = instance["size_px"]
                if x + width > size_px[0] or y + height > size_px[1]:
                    raise ManifestError(f"{label}.rect_px lies outside its structure")
                world_x = instance["origin_px"][0] + x
                world_y = instance["origin_px"][1] + y
                solid_owner_index = owner_index_by_id[structure_id]

            is_solid = operation_kind == "solid_rect"
            value = solid if is_solid else open_water
            owner_value = solid_owner_index if is_solid else 0
            row_bytes = bytes([value]) * width
            owner_row = [owner_value] * width
            for row in range(world_y, world_y + height):
                start = row * L05_PIXEL_SIZE[0] + world_x
                cells[start : start + width] = row_bytes
                solid_owner_cells[start : start + width] = owner_row

        for cell_index, value in enumerate(cells):
            owner_index = solid_owner_cells[cell_index]
            if value == solid and owner_index == 0:
                raise ManifestError(
                    f"L05 solid cell {cell_index} does not have a collision owner"
                )
            if value == open_water and owner_index != 0:
                raise ManifestError(
                    f"L05 open-water cell {cell_index} retains a collision owner"
                )
        digest_payload = {
            "mapping": copy.deepcopy(mapping),
            "encoding": copy.deepcopy(encoding),
            "pixel_size": list(L05_PIXEL_SIZE),
            "cells_hex": bytes(cells).hex(),
        }
        canonical_digest = f"topology-v1:{_canonical_sha256(digest_payload)}"
        partition_payload = {
            "owner_ids": owner_ids,
            "solid_owner_cells": solid_owner_cells,
        }
        partition_digest = f"partition-v1:{_canonical_sha256(partition_payload)}"
        declared_digest = collision["canonical_digest"]
        declared_partition_digest = collision["partition_digest"]
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
            if (
                not isinstance(declared_partition_digest, str)
                or not re.fullmatch(
                    r"partition-v1:[0-9a-f]{64}",
                    declared_partition_digest,
                )
            ):
                raise ManifestError(
                    "topology.collision_source.partition_digest must be "
                    "partition-v1:<sha256>"
                )
            if declared_partition_digest != partition_digest:
                raise ManifestError(
                    "topology.collision_source.partition_digest is stale; "
                    f"expected {partition_digest}"
                )
        topology_build = {
            "mode": L05_MODE,
            "payload_path": package_path,
            "payload_sha256": actual_payload_sha,
            "canonical_digest": canonical_digest,
            "partition_digest": partition_digest,
            "pixel_size": L05_PIXEL_SIZE,
            "world_units_per_pixel": L05_WORLD_UNITS_PER_PIXEL,
            "mapping": copy.deepcopy(mapping),
            "encoding": copy.deepcopy(encoding),
            "cells": bytes(cells),
            "owner_ids": owner_ids,
            "solid_owner_cells": solid_owner_cells,
            "structure_build": structure_build,
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


def _resolve_gameplay_position(
    record: dict[str, Any],
    label: str,
    world_size: tuple[float, float],
    structure_build: dict[str, Any],
) -> tuple[float, float]:
    position_space = record.get("position_space", "world")
    if position_space == "world":
        if "structure_id" in record:
            raise ManifestError(
                f"{label}.structure_id is allowed only with position_space=structure_local"
            )
        return _validate_position(record["position"], f"{label}.position", world_size)
    if position_space != "structure_local":
        raise ManifestError(
            f"{label}.position_space must be world or structure_local"
        )
    structure_id = _non_empty_string(
        record.get("structure_id"),
        f"{label}.structure_id",
    )
    instance = structure_build["instances_by_id"].get(structure_id)
    if instance is None:
        raise ManifestError(f"{label}.structure_id references an unknown structure")
    if not instance["enabled"]:
        raise ManifestError(f"{label}.structure_id references a disabled structure")
    local_position = _pair(record["position"], f"{label}.position")
    size = instance["size"]
    if (
        local_position[0] < 0.0
        or local_position[1] < 0.0
        or local_position[0] >= size[0]
        or local_position[1] >= size[1]
    ):
        raise ManifestError(f"{label}.position lies outside its structure")
    origin = instance["origin"]
    resolved = [
        origin[0] + local_position[0],
        origin[1] + local_position[1],
    ]
    return _validate_position(resolved, f"{label}.resolved_position", world_size)


def _validate_gameplay(
    manifest: dict[str, Any],
    world_size: tuple[float, float],
    landmarks_by_id: dict[str, dict[str, Any]],
    landmark_ids: set[str],
    region_ids: set[str],
    structure_build: dict[str, Any],
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
    all_ids = (
        set(landmark_ids)
        | region_ids
        | set(structure_build["instances_by_id"])
    )
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
                _resolve_gameplay_position(
                    record,
                    label,
                    world_size,
                    structure_build,
                )
            elif "position_space" in record or "structure_id" in record:
                raise ManifestError(
                    f"{label} cannot declare position_space or structure_id without position"
                )
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


def _load_and_validate_manifest_raw(raw: bytes) -> tuple[
    dict[str, Any], str, str, str, dict[str, Any]
]:
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
            "structures",
            "gameplay",
            "campaign",
        ),
        "manifest",
    )
    if manifest["schema_version"] != MAP_SCHEMA_VERSION:
        raise ManifestError(
            f"schema_version must be {MAP_SCHEMA_VERSION}"
        )
    if "region" in manifest:
        raise ManifestError(
            f"schema_version {MAP_SCHEMA_VERSION} uses regions; "
            "legacy region is not allowed"
        )

    manifest = _resolve_structure_packages(manifest)
    _validate_revision(manifest)
    world_size = _validate_map(manifest)
    region_bounds = _validate_regions(manifest, world_size)
    structure_build = _validate_structures(manifest, world_size)
    topology_build = _validate_topology(manifest, world_size, structure_build)
    _validate_visual(manifest, world_size, topology_build)
    _validate_depth_profile(manifest)
    landmarks_by_id, landmark_ids = _validate_landmarks(
        manifest,
        world_size,
        region_bounds,
    )
    _validate_structure_bindings(
        structure_build,
        landmark_ids,
        set(region_bounds),
        topology_build,
    )
    _validate_entry_exit(manifest, world_size, landmark_ids)
    _validate_gameplay(
        manifest,
        world_size,
        landmarks_by_id,
        landmark_ids,
        set(region_bounds),
        structure_build,
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


def load_and_validate_manifest() -> tuple[
    dict[str, Any], str, str, str, dict[str, Any]
]:
    return _load_and_validate_manifest_raw(MANIFEST_PATH.read_bytes())


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


def _structure_generated_path(structure_id: str, *parts: str) -> Path:
    return (
        WORKBENCH_DIR
        / "structures"
        / structure_id
        / "generated"
        / Path(*parts)
    )


def _artifact_record(path: Path, content: bytes) -> dict[str, str]:
    return {
        "path": path.relative_to(WORKBENCH_DIR).as_posix(),
        "sha256": hashlib.sha256(content).hexdigest(),
    }


def _binary_boundary_mask(pixels: bytes, width: int, height: int) -> bytes:
    if len(pixels) != width * height:
        raise ManifestError("binary boundary source has an invalid size")
    boundary = bytearray(width * height)
    for y in range(height):
        row_start = y * width
        if pixels[row_start] != 0:
            boundary[row_start] = 255
        if pixels[row_start + width - 1] != 0:
            boundary[row_start + width - 1] = 255
        for x in range(1, width):
            left = row_start + x - 1
            right = left + 1
            if pixels[left] != pixels[right]:
                boundary[left] = 255
                boundary[right] = 255
    for x in range(width):
        if pixels[x] != 0:
            boundary[x] = 255
        bottom = (height - 1) * width + x
        if pixels[bottom] != 0:
            boundary[bottom] = 255
    for y in range(1, height):
        previous_start = (y - 1) * width
        current_start = y * width
        for x in range(width):
            previous = previous_start + x
            current = current_start + x
            if pixels[previous] != pixels[current]:
                boundary[previous] = 255
                boundary[current] = 255
    return bytes(boundary)


def _structure_native_masks(
    topology_build: dict[str, Any],
    instance: dict[str, Any],
) -> tuple[int, int, bytes, bytes, bytes, bytes]:
    instance_id = str(instance["id"])
    width_float, height_float = instance["size"]
    if not width_float.is_integer() or not height_float.is_integer():
        raise ManifestError(
            f"structure {instance_id} needs integer world dimensions for native art"
        )
    width = int(width_float)
    height = int(height_float)
    if max(width, height) > STRUCTURE_NATIVE_MAX_TEXTURE_DIMENSION:
        raise ManifestError(
            f"structure {instance_id} exceeds the native mask limit of "
            f"{STRUCTURE_NATIVE_MAX_TEXTURE_DIMENSION} pixels per axis"
        )
    if width * height > STRUCTURE_NATIVE_MAX_TEXTURE_PIXELS:
        raise ManifestError(
            f"structure {instance_id} exceeds the native mask pixel budget"
        )
    step_x_float, step_y_float = topology_build["world_units_per_pixel"]
    if not step_x_float.is_integer() or not step_y_float.is_integer():
        raise ManifestError("structure native masks require integral L05 cell dimensions")
    step_x = int(step_x_float)
    step_y = int(step_y_float)
    local_cells, cell_width, cell_height = _structure_local_cells(instance)
    if width != cell_width * step_x or height != cell_height * step_y:
        raise ManifestError(
            f"structure {instance_id} native size does not match its L05 cell bounds"
        )
    solid_native = bytearray(width * height)
    open_native = bytearray(width * height)
    for local_cell_y in range(cell_height):
        solid_row = bytearray()
        open_row = bytearray()
        source_row = local_cell_y * cell_width
        for local_cell_x in range(cell_width):
            source_index = source_row + local_cell_x
            solid_row.extend(
                bytes([255 if local_cells[source_index] == 0 else 0])
                * step_x
            )
            open_row.extend(
                bytes([255 if local_cells[source_index] == 255 else 0])
                * step_x
            )
        for native_row_offset in range(step_y):
            destination = (
                (local_cell_y * step_y + native_row_offset) * width
            )
            solid_native[destination : destination + width] = solid_row
            open_native[destination : destination + width] = open_row
    boundary_native = _binary_boundary_mask(bytes(solid_native), width, height)
    guide = bytearray(width * height * 4)
    for pixel_index in range(width * height):
        if boundary_native[pixel_index] != 0:
            color = (255, 0, 255, 255)
        elif solid_native[pixel_index] != 0:
            color = (0, 0, 0, 255)
        elif open_native[pixel_index] != 0:
            color = (0, 255, 255, 255)
        else:
            color = (64, 64, 64, 255)
        target = pixel_index * 4
        guide[target : target + 4] = bytes(color)
    return (
        width,
        height,
        bytes(solid_native),
        bytes(open_native),
        boundary_native,
        bytes(guide),
    )


def _rects_intersect(
    first: tuple[int, int, int, int],
    second: tuple[int, int, int, int],
) -> bool:
    return (
        first[0] < second[0] + second[2]
        and second[0] < first[0] + first[2]
        and first[1] < second[1] + second[3]
        and second[1] < first[1] + first[3]
    )


def _panel_neighbors(
    panel: tuple[int, int, int, int],
    other: tuple[int, int, int, int],
) -> bool:
    horizontal_touch = (
        panel[0] + panel[2] == other[0]
        or other[0] + other[2] == panel[0]
    ) and max(panel[1], other[1]) < min(
        panel[1] + panel[3],
        other[1] + other[3],
    )
    vertical_touch = (
        panel[1] + panel[3] == other[1]
        or other[1] + other[3] == panel[1]
    ) and max(panel[0], other[0]) < min(
        panel[0] + panel[2],
        other[0] + other[2],
    )
    return horizontal_touch or vertical_touch


def _json_bytes(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            indent=2,
        )
        + "\n"
    ).encode("utf-8")


def _surface_detail_mask(topology_build: dict[str, Any]) -> bytes:
    """Return the deterministic RGBA presentation mask derived from L05 truth.

    R is the exposed solid edge distance, G marks seams between different solid
    owners, B marks a generic frame around boundary sockets that have open water
    continuity on both sides, and A is always opaque.  No channel can create
    geometry: RGB is populated only for canonical solid cells.
    """
    width, height = topology_build["pixel_size"]
    cells: bytes = topology_build["cells"]
    solid_value = int(topology_build["encoding"]["solid"])
    owners: list[int] = topology_build["solid_owner_cells"]
    detail = bytearray(width * height * 4)
    for cell_index in range(width * height):
        detail[cell_index * 4 + 3] = 255

    def in_bounds(x: int, y: int) -> bool:
        return 0 <= x < width and 0 <= y < height

    def cell_index(x: int, y: int) -> int:
        return y * width + x

    def is_solid(x: int, y: int) -> bool:
        return in_bounds(x, y) and cells[cell_index(x, y)] == solid_value

    distances = [-1] * (width * height)
    queue: deque[tuple[int, int]] = deque()
    for y in range(height):
        for x in range(width):
            index = cell_index(x, y)
            if cells[index] != solid_value:
                continue
            if any(
                not is_solid(neighbor_x, neighbor_y)
                for neighbor_x, neighbor_y in (
                    (x - 1, y),
                    (x + 1, y),
                    (x, y - 1),
                    (x, y + 1),
                )
            ):
                distances[index] = 0
                queue.append((x, y))
    while queue:
        x, y = queue.popleft()
        index = cell_index(x, y)
        distance = distances[index]
        if distance >= len(SURFACE_DETAIL_EDGE_VALUES) - 1:
            continue
        for neighbor_x, neighbor_y in (
            (x - 1, y),
            (x + 1, y),
            (x, y - 1),
            (x, y + 1),
        ):
            if not is_solid(neighbor_x, neighbor_y):
                continue
            neighbor_index = cell_index(neighbor_x, neighbor_y)
            if distances[neighbor_index] >= 0:
                continue
            distances[neighbor_index] = distance + 1
            queue.append((neighbor_x, neighbor_y))
    for index, distance in enumerate(distances):
        if 0 <= distance < len(SURFACE_DETAIL_EDGE_VALUES):
            detail[index * 4] = SURFACE_DETAIL_EDGE_VALUES[distance]

    for y in range(height):
        for x in range(width):
            index = cell_index(x, y)
            owner = owners[index]
            if cells[index] != solid_value or owner <= 0:
                continue
            for neighbor_x, neighbor_y in ((x + 1, y), (x, y + 1)):
                if not is_solid(neighbor_x, neighbor_y):
                    continue
                neighbor_index = cell_index(neighbor_x, neighbor_y)
                neighbor_owner = owners[neighbor_index]
                if neighbor_owner > 0 and neighbor_owner != owner:
                    detail[index * 4 + 1] = 255
                    detail[neighbor_index * 4 + 1] = 255

    cell_width, cell_height = topology_build["world_units_per_pixel"]
    for instance in topology_build["structure_build"]["instances"]:
        if not instance["enabled"]:
            continue
        origin_x, origin_y = instance["origin_px"]
        size_x, size_y = instance["size_px"]
        structure_width, structure_height = instance["size"]
        for socket_index, socket_value in enumerate(instance["source"].get("sockets", [])):
            socket = _object(socket_value, f"structure socket[{socket_index}]")
            local_x, local_y, local_width, local_height = _rect(
                socket["local_rect"],
                f"structure socket[{socket_index}].local_rect",
            )
            local_left = max(0, math.floor(local_x / cell_width))
            local_top = max(0, math.floor(local_y / cell_height))
            local_right = min(size_x, math.ceil((local_x + local_width) / cell_width))
            local_bottom = min(size_y, math.ceil((local_y + local_height) / cell_height))
            if local_left >= local_right or local_top >= local_bottom:
                continue
            global_left = origin_x + local_left
            global_top = origin_y + local_top
            global_right = origin_x + local_right
            global_bottom = origin_y + local_bottom
            core_open = any(
                not is_solid(x, y)
                for y in range(global_top, global_bottom)
                for x in range(global_left, global_right)
            )
            if not core_open:
                continue
            boundary_sides: list[str] = []
            if local_x <= 0:
                boundary_sides.append("left")
            if local_y <= 0:
                boundary_sides.append("top")
            if local_x + local_width >= structure_width:
                boundary_sides.append("right")
            if local_y + local_height >= structure_height:
                boundary_sides.append("bottom")
            has_open_continuity = False
            for side in boundary_sides:
                if side == "left":
                    has_open_continuity = any(
                        not is_solid(origin_x - 1, y) and not is_solid(origin_x, y)
                        for y in range(global_top, global_bottom)
                    )
                elif side == "right":
                    has_open_continuity = any(
                        not is_solid(origin_x + size_x, y)
                        and not is_solid(origin_x + size_x - 1, y)
                        for y in range(global_top, global_bottom)
                    )
                elif side == "top":
                    has_open_continuity = any(
                        not is_solid(x, origin_y - 1) and not is_solid(x, origin_y)
                        for x in range(global_left, global_right)
                    )
                else:
                    has_open_continuity = any(
                        not is_solid(x, origin_y + size_y)
                        and not is_solid(x, origin_y + size_y - 1)
                        for x in range(global_left, global_right)
                    )
                if has_open_continuity:
                    break
            if not has_open_continuity:
                continue
            for y in range(global_top - 1, global_bottom + 1):
                for x in range(global_left - 1, global_right + 1):
                    if is_solid(x, y):
                        detail[cell_index(x, y) * 4 + 2] = 255
    return bytes(detail)


def _portal_backdrop_clearances(
    topology_build: dict[str, Any],
) -> list[dict[str, Any]]:
    """Derive visual-only backdrop clearances from anonymous boundary openings.

    The stable identity contains only raster geometry.  Structure IDs, package
    paths, socket names and runtime roles are deliberately excluded so a pure
    identifier rename cannot alter either the digest or the presentation.
    """
    if topology_build.get("mode") != L05_MODE:
        return []
    width, height = topology_build["pixel_size"]
    cell_width, cell_height = topology_build["world_units_per_pixel"]
    cells: bytes = topology_build["cells"]
    open_water_value = int(topology_build["encoding"]["open_water"])
    if len(cells) != width * height:
        raise ManifestError("portal backdrop clearance source has an invalid size")

    def is_open(x: int, y: int) -> bool:
        return (
            0 <= x < width
            and 0 <= y < height
            and cells[y * width + x] == open_water_value
        )

    clearances_by_digest: dict[str, dict[str, Any]] = {}

    def append_runs(
        scan_start: int,
        scan_end_exclusive: int,
        inside_fixed: int,
        outside_fixed: int,
        *,
        vertical_scan: bool,
        boundary_cell: int,
        outward_cell: tuple[int, int],
    ) -> None:
        run_start = -1
        for cursor in range(scan_start, scan_end_exclusive + 1):
            run_is_open = False
            if cursor < scan_end_exclusive:
                inside = (
                    (inside_fixed, cursor)
                    if vertical_scan
                    else (cursor, inside_fixed)
                )
                outside = (
                    (outside_fixed, cursor)
                    if vertical_scan
                    else (cursor, outside_fixed)
                )
                run_is_open = is_open(*inside) and is_open(*outside)
            if run_is_open and run_start < 0:
                run_start = cursor
                continue
            if run_is_open or run_start < 0:
                continue

            geometry = {
                "axis": "vertical" if vertical_scan else "horizontal",
                "boundary_cell": boundary_cell,
                "run_start_cell": run_start,
                "run_end_cell": cursor,
                "outward_cell": list(outward_cell),
                "cell_size": [cell_width, cell_height],
            }
            geometry_digest = _canonical_sha256(geometry)
            if geometry_digest in clearances_by_digest:
                raise ManifestError(
                    "duplicate portal backdrop clearance geometry "
                    f"{geometry_digest}"
                )

            if vertical_scan:
                boundary_world = boundary_cell * cell_width
                opening_start = run_start * cell_height
                opening_end = cursor * cell_height
                normal_depth = (
                    PORTAL_BACKDROP_CLEARANCE_NORMAL_CORE_CELLS * cell_width
                )
                tangent_padding = (
                    PORTAL_BACKDROP_CLEARANCE_TANGENT_PADDING_CELLS
                    * cell_height
                )
                core_rect = [
                    boundary_world - normal_depth,
                    opening_start - tangent_padding,
                    normal_depth * 2.0,
                    opening_end - opening_start + tangent_padding * 2.0,
                ]
                opening_center = [
                    boundary_world,
                    (opening_start + opening_end) * 0.5,
                ]
                span = opening_end - opening_start
            else:
                boundary_world = boundary_cell * cell_height
                opening_start = run_start * cell_width
                opening_end = cursor * cell_width
                normal_depth = (
                    PORTAL_BACKDROP_CLEARANCE_NORMAL_CORE_CELLS * cell_height
                )
                tangent_padding = (
                    PORTAL_BACKDROP_CLEARANCE_TANGENT_PADDING_CELLS
                    * cell_width
                )
                core_rect = [
                    opening_start - tangent_padding,
                    boundary_world - normal_depth,
                    opening_end - opening_start + tangent_padding * 2.0,
                    normal_depth * 2.0,
                ]
                opening_center = [
                    (opening_start + opening_end) * 0.5,
                    boundary_world,
                ]
                span = opening_end - opening_start
            feather_x = PORTAL_BACKDROP_CLEARANCE_FEATHER_CELLS * cell_width
            feather_y = PORTAL_BACKDROP_CLEARANCE_FEATHER_CELLS * cell_height
            outer_rect = [
                core_rect[0] - feather_x,
                core_rect[1] - feather_y,
                core_rect[2] + feather_x * 2.0,
                core_rect[3] + feather_y * 2.0,
            ]
            clearances_by_digest[geometry_digest] = {
                "geometry": geometry,
                "geometry_digest": geometry_digest,
                "opening_center": opening_center,
                "outward": list(outward_cell),
                "span": span,
                "core_rect": core_rect,
                "outer_rect": outer_rect,
            }
            run_start = -1

    for instance in topology_build["structure_build"]["instances"]:
        if not instance["enabled"]:
            continue
        origin_x, origin_y = (int(value) for value in instance["origin_px"])
        size_x, size_y = (int(value) for value in instance["size_px"])
        right_exclusive = origin_x + size_x
        bottom_exclusive = origin_y + size_y
        append_runs(
            origin_y,
            bottom_exclusive,
            origin_x,
            origin_x - 1,
            vertical_scan=True,
            boundary_cell=origin_x,
            outward_cell=(-1, 0),
        )
        append_runs(
            origin_y,
            bottom_exclusive,
            right_exclusive - 1,
            right_exclusive,
            vertical_scan=True,
            boundary_cell=right_exclusive,
            outward_cell=(1, 0),
        )
        append_runs(
            origin_x,
            right_exclusive,
            origin_y,
            origin_y - 1,
            vertical_scan=False,
            boundary_cell=origin_y,
            outward_cell=(0, -1),
        )
        append_runs(
            origin_x,
            right_exclusive,
            bottom_exclusive - 1,
            bottom_exclusive,
            vertical_scan=False,
            boundary_cell=bottom_exclusive,
            outward_cell=(0, 1),
        )
    return [
        clearances_by_digest[digest]
        for digest in sorted(clearances_by_digest)
    ]


def _structure_surface_detail_crop(
    topology_build: dict[str, Any],
    instance: dict[str, Any],
    surface_detail_mask: bytes,
) -> tuple[int, int, bytes]:
    """Return the package-local L05-cell crop used by one structure shader."""
    world_width, world_height = topology_build["pixel_size"]
    origin_x, origin_y = instance["origin_px"]
    width, height = instance["size_px"]
    if (
        origin_x < 0
        or origin_y < 0
        or width <= 0
        or height <= 0
        or origin_x + width > world_width
        or origin_y + height > world_height
    ):
        raise ManifestError(
            f"structure {instance['id']} surface-detail crop exceeds L05 bounds"
        )
    if len(surface_detail_mask) != world_width * world_height * 4:
        raise ManifestError("surface-detail source has an invalid RGBA size")
    crop = bytearray(width * height * 4)
    row_bytes = width * 4
    for local_y in range(height):
        source_start = ((origin_y + local_y) * world_width + origin_x) * 4
        target_start = local_y * row_bytes
        crop[target_start : target_start + row_bytes] = surface_detail_mask[
            source_start : source_start + row_bytes
        ]
    return width, height, bytes(crop)


def _render_l05_artifacts(
    topology_build: dict[str, Any],
    manifest_sha: str,
    manifest: dict[str, Any],
    *,
    structure_id_filter: str | None = None,
    include_map_artifacts: bool = True,
) -> dict[Path, bytes]:
    if topology_build.get("mode") != L05_MODE:
        return {}
    width, height = topology_build["pixel_size"]
    cells: bytes = topology_build["cells"]
    solid_value = int(topology_build["encoding"]["solid"])
    open_water_value = int(topology_build["encoding"]["open_water"])
    surface_detail_mask = _surface_detail_mask(topology_build)
    artifacts: dict[Path, bytes] = {}
    artifact_records: dict[str, dict[str, str]] = {}
    if include_map_artifacts:
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
        artifacts.update(
            {
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
                L05_GENERATED_PATHS["surface_detail_mask"]: _encode_png_rgba8(
                    width, height, surface_detail_mask
                ),
            }
        )
        for name in (
            "solid_mask",
            "open_water_mask",
            "boundary_mask",
            "full_map_guide",
            "surface_detail_mask",
        ):
            path = L05_GENERATED_PATHS[name]
            artifact_records[name] = {
                "path": path.relative_to(WORKBENCH_DIR).as_posix(),
                "sha256": hashlib.sha256(artifacts[path]).hexdigest(),
            }
    owner_ids: list[str] = topology_build["owner_ids"]
    solid_owner_cells: list[int] = topology_build["solid_owner_cells"]
    owner_cell_counts = [
        {
            "owner_id": owner_id,
            "cell_count": solid_owner_cells.count(owner_index),
        }
        for owner_index, owner_id in enumerate(owner_ids)
    ]
    structure_assets_by_id: dict[str, list[dict[str, Any]]] = {}
    for asset_value in manifest["visual"]["assets"]:
        asset = _object(asset_value, "visual asset")
        if asset.get("kind") not in {
            STRUCTURE_INTERIOR_TEXTURE_KIND,
            STRUCTURE_OWNER_MASKED_TEXTURE_KIND,
        }:
            continue
        structure_assets_by_id.setdefault(str(asset["structure_id"]), []).append(asset)

    structure_cards = []
    for instance in topology_build["structure_build"]["instances"]:
        source: dict[str, Any] = instance["source"]
        instance_id = str(instance["id"])
        if structure_id_filter is not None and instance_id != structure_id_filter:
            continue
        origin_px = instance["origin_px"]
        size_px = instance["size_px"]
        structure_card = {
            "id": instance_id,
            "template_id": source["template_id"],
            "enabled": instance["enabled"],
            "origin": list(instance["origin"]),
            "size": list(instance["size"]),
            "pixel_rect": [
                origin_px[0],
                origin_px[1],
                size_px[0],
                size_px[1],
            ],
            "topology_digest": source["topology_digest"],
            "partition_digest": source["partition_digest"],
            "sockets": copy.deepcopy(source["sockets"]),
        }
        if "runtime" in source:
            structure_card["runtime"] = copy.deepcopy(source["runtime"])
        if "landmark_id" in source:
            structure_card["landmark_id"] = source["landmark_id"]
        if instance["enabled"]:
            (
                native_width,
                native_height,
                native_solid,
                native_open,
                native_boundary,
                native_guide,
            ) = _structure_native_masks(topology_build, instance)
            (
                detail_width,
                detail_height,
                local_surface_detail,
            ) = _structure_surface_detail_crop(
                topology_build,
                instance,
                surface_detail_mask,
            )
            native_outputs = {
                "solid_mask_native": (
                    _structure_generated_path(
                        instance_id,
                        "solid_mask_native.png",
                    ),
                    _encode_png_gray8(native_width, native_height, native_solid),
                ),
                "open_water_mask_native": (
                    _structure_generated_path(
                        instance_id,
                        "open_water_mask_native.png",
                    ),
                    _encode_png_gray8(native_width, native_height, native_open),
                ),
                "boundary_mask_native": (
                    _structure_generated_path(
                        instance_id,
                        "boundary_mask_native.png",
                    ),
                    _encode_png_gray8(native_width, native_height, native_boundary),
                ),
                "guide_native": (
                    _structure_generated_path(
                        instance_id,
                        "guide_native.png",
                    ),
                    _encode_png_rgba8(native_width, native_height, native_guide),
                ),
                "surface_detail_mask_local": (
                    _structure_generated_path(
                        instance_id,
                        "surface_detail_mask_local.png",
                    ),
                    _encode_png_rgba8(
                        detail_width,
                        detail_height,
                        local_surface_detail,
                    ),
                ),
            }
            native_artifact_records: dict[str, dict[str, str]] = {}
            for artifact_id, (artifact_path, artifact_content) in native_outputs.items():
                artifacts[artifact_path] = artifact_content
                native_artifact_records[artifact_id] = _artifact_record(
                    artifact_path,
                    artifact_content,
                )

            native_mapping = {
                "local_origin": [0, 0],
                "world_units_per_pixel": [1, 1],
                "source_world_units_per_pixel": [
                    int(topology_build["world_units_per_pixel"][0]),
                    int(topology_build["world_units_per_pixel"][1]),
                ],
                "x_axis": "right",
                "y_axis": "down",
                "pixel_reference": "pixel_edge",
                "rounding": "floor",
            }
            structure_assets = structure_assets_by_id.get(instance_id, [])
            panel_rects: set[tuple[int, int, int, int]] = set()
            for asset in structure_assets:
                local_rect = _rect(
                    asset["local_rect"],
                    f"structure asset {asset['id']}.local_rect",
                )
                panel_rects.add(tuple(int(value) for value in local_rect))
            if not panel_rects:
                panel_rects.add((0, 0, native_width, native_height))
            ordered_panel_rects = sorted(
                panel_rects,
                key=lambda rect: (rect[1], rect[0], rect[3], rect[2]),
            )
            panel_ids = {
                rect: "panel_%d_%d_%d_%d" % rect
                for rect in ordered_panel_rects
            }
            socket_rects = {
                str(socket["id"]): tuple(
                    int(value)
                    for value in _rect(
                        socket["local_rect"],
                        f"structure socket {socket['id']}.local_rect",
                    )
                )
                for socket in source["sockets"]
            }
            panel_records = []
            for panel_rect in ordered_panel_rects:
                panel_id = panel_ids[panel_rect]
                panel_assets = sorted(
                    str(asset["id"])
                    for asset in structure_assets
                    if tuple(
                        int(value)
                        for value in _rect(
                            asset["local_rect"],
                            f"structure asset {asset['id']}.local_rect",
                        )
                    )
                    == panel_rect
                )
                panel_socket_ids = sorted(
                    socket_id
                    for socket_id, socket_rect in socket_rects.items()
                    if _rects_intersect(panel_rect, socket_rect)
                )
                neighbor_ids = sorted(
                    panel_ids[other_rect]
                    for other_rect in ordered_panel_rects
                    if other_rect != panel_rect
                    and _panel_neighbors(panel_rect, other_rect)
                )
                panel_card = {
                    "schema_version": 1,
                    "generated": True,
                    "authority": False,
                    "structure_id": instance_id,
                    "panel_id": panel_id,
                    "package_manifest_path": source["package_path"],
                    "package_manifest_sha256": source["package_sha256"],
                    "local_topology_digest": source["local_topology_digest"],
                    "local_rect": list(panel_rect),
                    "native_pixel_rect": list(panel_rect),
                    "source_cell_rect": [
                        panel_rect[0] // int(L05_WORLD_UNITS_PER_PIXEL[0]),
                        panel_rect[1] // int(L05_WORLD_UNITS_PER_PIXEL[1]),
                        panel_rect[2] // int(L05_WORLD_UNITS_PER_PIXEL[0]),
                        panel_rect[3] // int(L05_WORLD_UNITS_PER_PIXEL[1]),
                    ],
                    "mapping": copy.deepcopy(native_mapping),
                    "native_artifacts": copy.deepcopy(native_artifact_records),
                    "asset_ids": panel_assets,
                    "socket_ids": panel_socket_ids,
                    "neighbor_panel_ids": neighbor_ids,
                }
                panel_path = _structure_generated_path(
                    instance_id,
                    "panels",
                    f"{panel_id}.json",
                )
                panel_content = _json_bytes(panel_card)
                artifacts[panel_path] = panel_content
                panel_records.append(
                    {
                        "id": panel_id,
                        "local_rect": list(panel_rect),
                        **_artifact_record(panel_path, panel_content),
                    }
                )

            socket_card_records = []
            for socket in source["sockets"]:
                socket_id = str(socket["id"])
                socket_rect = socket_rects[socket_id]
                socket_card = {
                    "schema_version": 1,
                    "generated": True,
                    "authority": False,
                    "structure_id": instance_id,
                    "socket_id": socket_id,
                    "kind": socket["kind"],
                    "package_manifest_path": source["package_path"],
                    "package_manifest_sha256": source["package_sha256"],
                    "local_topology_digest": source["local_topology_digest"],
                    "local_rect": list(socket_rect),
                    "native_pixel_rect": list(socket_rect),
                    "source_cell_rect": [
                        socket_rect[0] // int(L05_WORLD_UNITS_PER_PIXEL[0]),
                        socket_rect[1] // int(L05_WORLD_UNITS_PER_PIXEL[1]),
                        socket_rect[2] // int(L05_WORLD_UNITS_PER_PIXEL[0]),
                        socket_rect[3] // int(L05_WORLD_UNITS_PER_PIXEL[1]),
                    ],
                    "mapping": copy.deepcopy(native_mapping),
                    "native_artifacts": copy.deepcopy(native_artifact_records),
                    "panel_ids": [
                        panel_ids[panel_rect]
                        for panel_rect in ordered_panel_rects
                        if _rects_intersect(panel_rect, socket_rect)
                    ],
                }
                socket_path = _structure_generated_path(
                    instance_id,
                    "socket_cards",
                    f"{_safe_node_name(socket_id)}.json",
                )
                socket_content = _json_bytes(socket_card)
                artifacts[socket_path] = socket_content
                socket_card_records.append(
                    {
                        "id": socket_id,
                        "kind": socket["kind"],
                        **_artifact_record(socket_path, socket_content),
                    }
                )

            structure_truth = {
                "schema_version": 1,
                "generated": True,
                "authority": False,
                "structure_id": instance_id,
                "package_manifest_path": source["package_path"],
                "package_manifest_sha256": source["package_sha256"],
                "local_topology_digest": source["local_topology_digest"],
                "template_id": source["template_id"],
                "size": [native_width, native_height],
                "mapping": native_mapping,
                "native_artifacts": native_artifact_records,
                "panels": panel_records,
                "socket_cards": socket_card_records,
                "sockets": copy.deepcopy(source["sockets"]),
                "runtime": copy.deepcopy(source.get("runtime", {})),
                "controller_script": source["controller_script"],
                "visual_asset_ids": sorted(
                    str(asset["id"]) for asset in structure_assets
                ),
            }
            structure_truth_path = _structure_generated_path(
                instance_id,
                "structure_truth.json",
            )
            structure_truth_content = _json_bytes(structure_truth)
            artifacts[structure_truth_path] = structure_truth_content
            structure_card["native_artifacts"] = native_artifact_records
            structure_card["panels"] = panel_records
            structure_card["socket_cards"] = socket_card_records
            structure_card["structure_truth"] = _artifact_record(
                structure_truth_path,
                structure_truth_content,
            )
        structure_cards.append(structure_card)
    if include_map_artifacts:
        truth_package = {
            "generated": True,
            "authority": False,
            "manifest_sha256": manifest_sha,
            "payload_path": topology_build["payload_path"],
            "payload_sha256": topology_build["payload_sha256"],
            "canonical_digest": topology_build["canonical_digest"],
            "partition_digest": topology_build["partition_digest"],
            "pixel_size": list(topology_build["pixel_size"]),
            "world_units_per_pixel": list(topology_build["world_units_per_pixel"]),
            "mapping": copy.deepcopy(topology_build["mapping"]),
            "encoding": copy.deepcopy(topology_build["encoding"]),
            "solid_cell_count": sum(value == solid_value for value in cells),
            "open_water_cell_count": sum(value == open_water_value for value in cells),
            "owner_ids": owner_ids,
            "owner_cell_counts": owner_cell_counts,
            "structures": structure_cards,
            "artifacts": artifact_records,
        }
        artifacts[L05_GENERATED_PATHS["truth_package"]] = _json_bytes(truth_package)
    return artifacts


def _safe_node_name(value: str) -> str:
    ascii_value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    sanitized = re.sub(r"[^A-Za-z0-9_]+", "_", ascii_value).strip("_")
    return sanitized or "Record"


def _merged_structure_owner_rectangles(
    topology_build: dict[str, Any],
    instance: dict[str, Any],
) -> list[tuple[int, int, int, int]]:
    grid_width = int(topology_build["pixel_size"][0])
    owner_ids: list[str] = topology_build["owner_ids"]
    owner_index = owner_ids.index(str(instance["id"]))
    owner_cells: list[int] = topology_build["solid_owner_cells"]
    origin_x, origin_y = instance["origin_px"]
    width, height = instance["size_px"]
    active: dict[tuple[int, int], list[int]] = {}
    merged: list[tuple[int, int, int, int]] = []
    for local_y in range(height):
        runs: list[tuple[int, int]] = []
        local_x = 0
        while local_x < width:
            global_index = (origin_y + local_y) * grid_width + origin_x + local_x
            if owner_cells[global_index] != owner_index:
                local_x += 1
                continue
            run_start = local_x
            local_x += 1
            while local_x < width:
                global_index = (
                    (origin_y + local_y) * grid_width + origin_x + local_x
                )
                if owner_cells[global_index] != owner_index:
                    break
                local_x += 1
            runs.append((run_start, local_x - run_start))
        run_keys = set(runs)
        for key in list(active):
            if key not in run_keys:
                x, y, run_width, run_height = active.pop(key)
                merged.append((x, y, run_width, run_height))
        for run_start, run_width in runs:
            key = (run_start, run_width)
            if key in active:
                active[key][3] += 1
            else:
                active[key] = [run_start, local_y, run_width, 1]
    for x, y, run_width, run_height in active.values():
        merged.append((x, y, run_width, run_height))
    merged.sort(key=lambda rect: (rect[1], rect[0], rect[3], rect[2]))
    return merged


def _structure_owner_boundary_segments(
    topology_build: dict[str, Any],
    instance: dict[str, Any],
) -> list[tuple[float, float]]:
    grid_width, grid_height = topology_build["pixel_size"]
    owner_ids: list[str] = topology_build["owner_ids"]
    owner_index = owner_ids.index(str(instance["id"]))
    owner_cells: list[int] = topology_build["solid_owner_cells"]
    cells: bytes = topology_build["cells"]
    solid_value = int(topology_build["encoding"]["solid"])
    origin_x, origin_y = instance["origin_px"]
    width, height = instance["size_px"]
    pixel_width, pixel_height = topology_build["world_units_per_pixel"]
    segments: list[tuple[float, float]] = []

    def is_owned_by_structure(global_x: int, global_y: int) -> bool:
        return (
            0 <= global_x < grid_width
            and 0 <= global_y < grid_height
            and owner_cells[global_y * grid_width + global_x] == owner_index
        )

    def is_solid(global_x: int, global_y: int) -> bool:
        return (
            0 <= global_x < grid_width
            and 0 <= global_y < grid_height
            and cells[global_y * grid_width + global_x] == solid_value
        )

    for local_y in range(height):
        global_y = origin_y + local_y
        for local_x in range(width):
            global_x = origin_x + local_x
            if not is_owned_by_structure(global_x, global_y):
                continue
            left = local_x * pixel_width
            top = local_y * pixel_height
            right = (local_x + 1) * pixel_width
            bottom = (local_y + 1) * pixel_height
            if not is_solid(global_x, global_y - 1):
                segments.extend(((left, top), (right, top)))
            if not is_solid(global_x + 1, global_y):
                segments.extend(((right, top), (right, bottom)))
            if not is_solid(global_x, global_y + 1):
                segments.extend(((right, bottom), (left, bottom)))
            if not is_solid(global_x - 1, global_y):
                segments.extend(((left, bottom), (left, top)))
    return segments


def _structure_local_cells(
    instance: dict[str, Any],
) -> tuple[bytes, int, int]:
    width, height = instance["size_px"]
    cells = bytearray([255]) * (width * height)
    for operation in instance["source"].get("collision_operations", []):
        x, y, rect_width, rect_height = operation["rect_px"]
        value = 0 if operation["op"] == "solid_rect" else 255
        row_bytes = bytes([value]) * rect_width
        for row in range(y, y + rect_height):
            start = row * width + x
            cells[start : start + rect_width] = row_bytes
    return bytes(cells), width, height


def _merged_structure_local_rectangles(
    instance: dict[str, Any],
) -> list[tuple[int, int, int, int]]:
    cells, width, height = _structure_local_cells(instance)
    active: dict[tuple[int, int], list[int]] = {}
    merged: list[tuple[int, int, int, int]] = []
    for y in range(height):
        runs: list[tuple[int, int]] = []
        x = 0
        while x < width:
            if cells[y * width + x] != 0:
                x += 1
                continue
            run_start = x
            x += 1
            while x < width and cells[y * width + x] == 0:
                x += 1
            runs.append((run_start, x - run_start))
        run_keys = set(runs)
        for key in list(active):
            if key not in run_keys:
                left, top, run_width, run_height = active.pop(key)
                merged.append((left, top, run_width, run_height))
        for run_start, run_width in runs:
            key = (run_start, run_width)
            if key in active:
                active[key][3] += 1
            else:
                active[key] = [run_start, y, run_width, 1]
    for left, top, run_width, run_height in active.values():
        merged.append((left, top, run_width, run_height))
    merged.sort(key=lambda rect: (rect[1], rect[0], rect[3], rect[2]))
    return merged


def _structure_local_boundary_segments(
    instance: dict[str, Any],
) -> list[tuple[float, float]]:
    cells, width, height = _structure_local_cells(instance)
    pixel_width, pixel_height = L05_WORLD_UNITS_PER_PIXEL
    segments: list[tuple[float, float]] = []

    def is_solid(x: int, y: int) -> bool:
        return 0 <= x < width and 0 <= y < height and cells[y * width + x] == 0

    for y in range(height):
        for x in range(width):
            if not is_solid(x, y):
                continue
            left = x * pixel_width
            top = y * pixel_height
            right = (x + 1) * pixel_width
            bottom = (y + 1) * pixel_height
            if not is_solid(x, y - 1):
                segments.extend(((left, top), (right, top)))
            if not is_solid(x + 1, y):
                segments.extend(((right, top), (right, bottom)))
            if not is_solid(x, y + 1):
                segments.extend(((right, bottom), (left, bottom)))
            if not is_solid(x - 1, y):
                segments.extend(((left, bottom), (left, top)))
    return segments


def _scene_structure_resources(
    topology_build: dict[str, Any],
    structure_ids: set[str] | None = None,
) -> tuple[list[str], list[dict[str, Any]]]:
    if topology_build.get("mode") != L05_MODE:
        return [], []
    sub_resources: list[str] = []
    bindings: list[dict[str, Any]] = []
    enabled_instances = [
        instance
        for instance in topology_build["structure_build"]["instances"]
        if instance["enabled"]
        and (
            structure_ids is None
            or str(instance["id"]) in structure_ids
        )
    ]
    for index, instance in enumerate(enabled_instances):
        binding = {
            "instance": instance,
            "rectangles_px": _merged_structure_owner_rectangles(
                topology_build,
                instance,
            ),
        }
        segments = _structure_owner_boundary_segments(topology_build, instance)
        if segments:
            shape_id = f"ConcavePolygonShape2D_structure_{index:04d}"
            binding["shape_id"] = shape_id
            sub_resources.extend(
                (
                    "",
                    f'[sub_resource type="ConcavePolygonShape2D" id="{shape_id}"]',
                    f"segments = {_gd_points(segments)}",
                )
            )
        bindings.append(binding)
    return sub_resources, bindings


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
            f"modulate = {_gd_color(layer['rgb_modulate'], f'{scale_label}.rgb_modulate', 255)}",
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
            f"metadata/rgb_modulate = {_gd_color(layer['rgb_modulate'], f'{scale_label}.rgb_modulate', 255)}",
            f"metadata/enabled = {'true' if layer['enabled'] else 'false'}",
            f"metadata/reserved = {'true' if layer['reserved'] else 'false'}",
            f"metadata/affordance_policy = {_gd_string(layer['affordance_policy'])}",
            f"metadata/geometry_role = {_gd_string(layer['geometry_role'])}",
        )
    )


def _is_streamed_backdrop(asset: dict[str, Any]) -> bool:
    return (
        asset["kind"] == "texture_rect"
        and asset["layer_id"] in STREAMED_BACKDROP_LAYER_IDS
    )


def _scene_visual_asset_resources(
    manifest: dict[str, Any],
    *,
    include_structure_assets: bool = True,
    structure_id_filter: str = "",
) -> tuple[list[str], list[str], list[dict[str, Any]]]:
    source_assets: list[dict[str, Any]] = manifest["visual"]["assets"]
    assets: list[dict[str, Any]] = []
    for asset in source_assets:
        is_structure_asset = asset["kind"] in {
            STRUCTURE_INTERIOR_TEXTURE_KIND,
            STRUCTURE_OWNER_MASKED_TEXTURE_KIND,
        }
        if is_structure_asset and not include_structure_assets:
            continue
        if (
            structure_id_filter
            and (
                not is_structure_asset
                or str(asset.get("structure_id", "")) != structure_id_filter
            )
        ):
            continue
        if structure_id_filter and not is_structure_asset:
            continue
        assets.append(asset)
    if not assets:
        return [], [], []
    ext_resources: list[str] = []
    sub_resources: list[str] = []
    bindings: list[dict[str, Any]] = []
    has_l05 = any(
        asset["kind"] == "collision_masked_material" for asset in assets
    )
    if has_l05:
        ext_resources.extend(
            (
                f'[ext_resource type="Shader" path="{L05_SHADER_RESOURCE_PATH}" id="Shader_l05_ground"]',
                f'[ext_resource type="Texture2D" path="{L05_SOLID_MASK_RESOURCE_PATH}" id="Texture_l05_solid"]',
            )
        )
    has_structure_assets = any(
        asset["kind"]
        in {
            STRUCTURE_INTERIOR_TEXTURE_KIND,
            STRUCTURE_OWNER_MASKED_TEXTURE_KIND,
        }
        for asset in assets
    )
    if has_l05:
        ext_resources.append(
            f'[ext_resource type="Texture2D" path="{L05_SURFACE_DETAIL_MASK_RESOURCE_PATH}" '
            'id="Texture_l05_surface_detail"]'
        )
    if has_structure_assets:
        if not structure_id_filter:
            raise ManifestError(
                "structure visual resources require one package-local structure filter"
            )
        structure_detail_path = _structure_generated_path(
            structure_id_filter,
            "surface_detail_mask_local.png",
        )
        structure_detail_resource_path = (
            "res://underwater_map_workbench/"
            + structure_detail_path.relative_to(WORKBENCH_DIR).as_posix()
        )
        ext_resources.append(
            f'[ext_resource type="Texture2D" path="{structure_detail_resource_path}" '
            'id="Texture_l05_surface_detail"]'
        )
        ext_resources.append(
            f'[ext_resource type="Shader" path="{STRUCTURE_CLIP_SHADER_RESOURCE_PATH}" '
            'id="Shader_structure_clip"]'
        )
    structures_by_id = {
        str(instance["id"]): instance
        for instance in manifest["structures"]["instances"]
    }
    structure_mask_resource_ids: dict[tuple[str, str], str] = {}
    for index, asset in enumerate(assets):
        binding: dict[str, Any] = {
            "asset": asset,
            "index": index,
        }
        if asset["kind"] == COMPOSITION_PROXY_KIND:
            bindings.append(binding)
            continue
        resource_path = (
            "res://underwater_map_workbench/" + str(asset["path"])
        )
        if _is_streamed_backdrop(asset):
            binding["resource_path"] = resource_path
            binding["residency_contract"] = STREAMED_BACKDROP_CONTRACT
            bindings.append(binding)
            continue
        texture_id = f"Texture_asset_{index:04d}"
        ext_resources.append(
            f'[ext_resource type="Texture2D" path="{resource_path}" id="{texture_id}"]'
        )
        binding["texture_id"] = texture_id
        if asset["kind"] in {
            STRUCTURE_INTERIOR_TEXTURE_KIND,
            STRUCTURE_OWNER_MASKED_TEXTURE_KIND,
        }:
            structure_id = str(asset["structure_id"])
            binding["structure_id"] = structure_id
            mask_name = (
                "open_water_mask_native"
                if asset["kind"] == STRUCTURE_INTERIOR_TEXTURE_KIND
                else "solid_mask_native"
            )
            mask_key = (structure_id, mask_name)
            mask_resource_id = structure_mask_resource_ids.get(mask_key)
            if mask_resource_id is None:
                mask_resource_id = (
                    f"Texture_structure_mask_{len(structure_mask_resource_ids):04d}"
                )
                structure_mask_resource_ids[mask_key] = mask_resource_id
                mask_path = _structure_generated_path(
                    structure_id,
                    f"{mask_name}.png",
                )
                mask_resource_path = (
                    "res://underwater_map_workbench/"
                    + mask_path.relative_to(WORKBENCH_DIR).as_posix()
                )
                ext_resources.append(
                    f'[ext_resource type="Texture2D" path="{mask_resource_path}" '
                    f'id="{mask_resource_id}"]'
                )
            material_id = f"ShaderMaterial_asset_{index:04d}"
            binding["material_id"] = material_id
            local_x, local_y, local_width, local_height = _rect(
                asset["local_rect"],
                f"visual.assets[{index}].local_rect",
            )
            structure_size = _pair(
                structures_by_id[structure_id]["size"],
                f"structure {structure_id}.size",
            )
            structure_origin = _pair(
                structures_by_id[structure_id]["origin"],
                f"structure {structure_id}.origin",
            )
            world_size = _pair(manifest["map"]["world_size"], "map.world_size")
            sub_resources.extend(
                (
                    "",
                    f'[sub_resource type="ShaderMaterial" id="{material_id}"]',
                    'shader = ExtResource("Shader_structure_clip")',
                    f'shader_parameter/clip_mask = ExtResource("{mask_resource_id}")',
                    'shader_parameter/surface_detail_mask = ExtResource("Texture_l05_surface_detail")',
                    "shader_parameter/detail_enabled = "
                    + (
                        "true"
                        if asset["kind"] == STRUCTURE_OWNER_MASKED_TEXTURE_KIND
                        else "false"
                    ),
                    "shader_parameter/local_rect_origin = "
                    + _gd_vector(
                        [local_x, local_y],
                        f"visual.assets[{index}].local_rect_origin",
                    ),
                    "shader_parameter/local_rect_size = "
                    + _gd_vector(
                        [local_width, local_height],
                        f"visual.assets[{index}].local_rect_size",
                    ),
                    "shader_parameter/structure_size = "
                    + _gd_vector(
                        list(structure_size),
                        f"structure {structure_id}.size",
                    ),
                    "shader_parameter/world_rect_origin = "
                    + _gd_vector(
                        [structure_origin[0] + local_x, structure_origin[1] + local_y],
                        f"visual.assets[{index}].world_rect_origin",
                    ),
                    "shader_parameter/world_size = "
                    + _gd_vector(
                        list(world_size),
                        "map.world_size",
                    ),
                )
            )
        elif asset["kind"] == "collision_masked_material":
            material_id = f"ShaderMaterial_asset_{index:04d}"
            binding["material_id"] = material_id
            _, _, world_width, world_height = _rect(
                asset["world_rect"],
                f"visual.assets[{index}].world_rect",
            )
            pixel_width, pixel_height = _pair(
                asset["pixel_size"],
                f"visual.assets[{index}].pixel_size",
            )
            native_texture_tiling = [
                world_width / pixel_width,
                world_height / pixel_height,
            ]
            sub_resources.extend(
                (
                    "",
                    f'[sub_resource type="ShaderMaterial" id="{material_id}"]',
                    'shader = ExtResource("Shader_l05_ground")',
                    'shader_parameter/topology_mask = ExtResource("Texture_l05_solid")',
                    'shader_parameter/surface_detail_mask = ExtResource("Texture_l05_surface_detail")',
                    f'shader_parameter/ground_texture = ExtResource("{texture_id}")',
                    "shader_parameter/texture_tiling = "
                    + _gd_vector(
                        native_texture_tiling,
                        f"visual.assets[{index}].native_texture_tiling",
                    ),
                )
            )
        bindings.append(binding)
    return ext_resources, sub_resources, bindings


def _append_visual_asset_groups(
    lines: list[str],
    bindings: list[dict[str, Any]],
) -> None:
    emitted: set[tuple[str, str]] = set()
    for binding in bindings:
        if "structure_id" in binding:
            continue
        asset: dict[str, Any] = binding["asset"]
        layer_id = str(asset["layer_id"])
        group_id = str(asset["group_id"])
        key = (layer_id, group_id)
        if key in emitted:
            continue
        emitted.add(key)
        lines.extend(
            (
                "",
                f'[node name="{group_id}" type="Node2D" parent="VisualLayers/{layer_id}"]',
                "scale = Vector2(1, 1)",
                f"metadata/group_id = {_gd_string(group_id)}",
                f"metadata/layer_id = {_gd_string(layer_id)}",
            )
        )


def _append_visual_assets(
    lines: list[str],
    bindings: list[dict[str, Any]],
) -> None:
    _append_visual_asset_groups(lines, bindings)
    for binding in bindings:
        if "structure_id" in binding:
            continue
        asset: dict[str, Any] = binding["asset"]
        index = int(binding["index"])
        asset_id = str(asset["id"])
        layer_id = str(asset["layer_id"])
        group_id = str(asset["group_id"])
        x, y, width, height = _rect(
            asset["world_rect"],
            f"visual.assets[{index}].world_rect",
        )
        pixel_width, pixel_height = _pair(
            asset["pixel_size"],
            f"visual.assets[{index}].pixel_size",
        )
        node_name = _safe_node_name(asset_id)
        group_path = f"VisualLayers/{layer_id}/{group_id}"
        element_path = f"{group_path}/{node_name}"
        lines.extend(
            (
                "",
                f'[node name="{node_name}" type="Node2D" parent="{group_path}"]',
                f"position = Vector2({_gd_number(x)}, {_gd_number(y)})",
                "scale = Vector2(1, 1)",
                f"visible = {'true' if asset['enabled'] else 'false'}",
                f"metadata/asset_id = {_gd_string(asset_id)}",
                f"metadata/layer_id = {_gd_string(layer_id)}",
                f"metadata/group_id = {_gd_string(group_id)}",
                f"metadata/kind = {_gd_string(asset['kind'])}",
                "metadata/world_rect = Rect2("
                f"{_gd_number(x)}, {_gd_number(y)}, "
                f"{_gd_number(width)}, {_gd_number(height)})",
                "metadata/pixel_size = Vector2i("
                f"{int(pixel_width)}, {int(pixel_height)})",
                f"metadata/source = {_gd_variant(asset)}",
            )
        )
        if binding.get("residency_contract") == STREAMED_BACKDROP_CONTRACT:
            lines.extend(
                (
                    f"metadata/residency_contract = {_gd_string(STREAMED_BACKDROP_CONTRACT)}",
                    f"metadata/resource_path = {_gd_string(str(binding['resource_path']))}",
                    f"metadata/source_sha256 = {_gd_string(str(asset['sha256']))}",
                )
            )
        if asset["kind"] == "texture_rect":
            bitmap_lines = [
                "",
                f'[node name="Bitmap" type="TextureRect" parent="{element_path}"]',
                "offset_left = 0.0",
                "offset_top = 0.0",
                f"offset_right = {_gd_number(width)}",
                f"offset_bottom = {_gd_number(height)}",
            ]
            if "texture_id" in binding:
                bitmap_lines.append(
                    f'texture = ExtResource("{binding["texture_id"]}")'
                )
            bitmap_lines.extend(
                (
                    "expand_mode = 1",
                    "stretch_mode = 0",
                    "mouse_filter = 2",
                )
            )
            lines.extend(bitmap_lines)
        elif asset["kind"] == COMPOSITION_PROXY_KIND:
            lines.extend(
                (
                    "",
                    f'[node name="Fill" type="ColorRect" parent="{element_path}"]',
                    "offset_left = 0.0",
                    "offset_top = 0.0",
                    f"offset_right = {_gd_number(width)}",
                    f"offset_bottom = {_gd_number(height)}",
                    f"color = {_gd_color(COMPOSITION_PROXY_FILL_COLOR, 'composition_proxy.fill')}",
                    "mouse_filter = 2",
                    "",
                    f'[node name="Outline" type="Line2D" parent="{element_path}"]',
                    "points = "
                    + _gd_points(
                        (
                            (0.0, 0.0),
                            (width, 0.0),
                            (width, height),
                            (0.0, height),
                            (0.0, 0.0),
                        )
                    ),
                    "width = 12.0",
                    f"default_color = {_gd_color(COMPOSITION_PROXY_OUTLINE_COLOR, 'composition_proxy.outline')}",
                    "antialiased = true",
                    "",
                    f'[node name="Label" type="Label" parent="{element_path}"]',
                    "offset_left = 24.0",
                    "offset_top = 24.0",
                    f"text = {_gd_string(f'{asset_id}  {int(width)} x {int(height)}')}",
                    f"theme_override_colors/font_color = {_gd_color(COMPOSITION_PROXY_LABEL_COLOR, 'composition_proxy.label')}",
                    "theme_override_colors/font_outline_color = Color(0, 0, 0, 0.9)",
                    "theme_override_constants/outline_size = 6",
                    "theme_override_font_sizes/font_size = 48",
                    "mouse_filter = 2",
                )
            )
        else:
            lines.extend(
                (
                    "",
                    f'[node name="Material" type="ColorRect" parent="{element_path}"]',
                    "offset_left = 0.0",
                    "offset_top = 0.0",
                    f"offset_right = {_gd_number(width)}",
                    f"offset_bottom = {_gd_number(height)}",
                    f'material = SubResource("{binding["material_id"]}")',
                    "mouse_filter = 2",
                )
            )


def _append_structure_visual_assets(
    lines: list[str],
    root_path: str,
    structure_id: str,
    bindings: list[dict[str, Any]],
) -> None:
    structure_bindings = [
        binding
        for binding in bindings
        if binding.get("structure_id") == structure_id
    ]
    emitted_groups: set[tuple[str, str]] = set()
    for binding in structure_bindings:
        asset: dict[str, Any] = binding["asset"]
        layer_id = str(asset["layer_id"])
        group_id = str(asset["group_id"])
        mount_name = (
            "InteriorVisual"
            if asset["kind"] == STRUCTURE_INTERIOR_TEXTURE_KIND
            else "StructureVisual"
        )
        group_key = (mount_name, group_id)
        group_path = f"{root_path}/{mount_name}/{group_id}"
        if group_key not in emitted_groups:
            emitted_groups.add(group_key)
            lines.extend(
                (
                    "",
                    f'[node name="{group_id}" type="Node2D" parent="{root_path}/{mount_name}"]',
                    "position = Vector2(0, 0)",
                    "scale = Vector2(1, 1)",
                    f"metadata/group_id = {_gd_string(group_id)}",
                    f"metadata/layer_id = {_gd_string(layer_id)}",
                    f"metadata/structure_id = {_gd_string(structure_id)}",
                )
            )
        index = int(binding["index"])
        asset_id = str(asset["id"])
        node_name = _safe_node_name(asset_id)
        element_path = f"{group_path}/{node_name}"
        x, y, width, height = _rect(
            asset["local_rect"],
            f"visual.assets[{index}].local_rect",
        )
        pixel_width, pixel_height = _pair(
            asset["pixel_size"],
            f"visual.assets[{index}].pixel_size",
        )
        lines.extend(
            (
                "",
                f'[node name="{node_name}" type="Node2D" parent="{group_path}"]',
                f"position = Vector2({_gd_number(x)}, {_gd_number(y)})",
                "scale = Vector2(1, 1)",
                f"visible = {'true' if asset['enabled'] else 'false'}",
                f"metadata/asset_id = {_gd_string(asset_id)}",
                f"metadata/structure_id = {_gd_string(structure_id)}",
                f"metadata/layer_id = {_gd_string(layer_id)}",
                f"metadata/group_id = {_gd_string(group_id)}",
                f"metadata/kind = {_gd_string(asset['kind'])}",
                "metadata/local_rect = Rect2("
                f"{_gd_number(x)}, {_gd_number(y)}, "
                f"{_gd_number(width)}, {_gd_number(height)})",
                "metadata/pixel_size = Vector2i("
                f"{int(pixel_width)}, {int(pixel_height)})",
                f"metadata/topology_digest = {_gd_string(asset['topology_digest'])}",
                f"metadata/partition_digest = {_gd_string(asset['partition_digest'])}",
                f"metadata/source = {_gd_variant(asset)}",
                "",
                f'[node name="Bitmap" type="TextureRect" parent="{element_path}"]',
                "position = Vector2(0, 0)",
                "scale = Vector2(1, 1)",
                "offset_left = 0.0",
                "offset_top = 0.0",
                f"offset_right = {_gd_number(width)}",
                f"offset_bottom = {_gd_number(height)}",
                f'texture = ExtResource("{binding["texture_id"]}")',
                f'material = SubResource("{binding["material_id"]}")',
                "expand_mode = 1",
                "stretch_mode = 0",
                "mouse_filter = 2",
            )
        )


def _append_structure_roots(
    lines: list[str],
    bindings: list[dict[str, Any]],
    manifest: dict[str, Any],
    topology_build: dict[str, Any],
    visual_asset_bindings: list[dict[str, Any]],
) -> None:
    lines.extend(
        (
            "",
            '[node name="StructureRoots" type="Node2D" parent="."]',
            "position = Vector2(0, 0)",
            "scale = Vector2(1, 1)",
        )
    )
    pixel_width, pixel_height = topology_build["world_units_per_pixel"]
    local_interactives: dict[str, list[tuple[str, int, dict[str, Any]]]] = {}
    for collection_name, records in _iter_gameplay_collections(manifest["gameplay"]):
        for record_index, record in enumerate(records):
            if record.get("position_space") != "structure_local":
                continue
            structure_id = str(record.get("structure_id", ""))
            local_interactives.setdefault(structure_id, []).append(
                (collection_name, record_index, record)
            )

    for binding in bindings:
        instance: dict[str, Any] = binding["instance"]
        if not instance["enabled"]:
            continue
        source: dict[str, Any] = instance["source"]
        instance_id = str(instance["id"])
        node_name = _safe_node_name(instance_id)
        root_path = f"StructureRoots/{node_name}"
        size_width, size_height = instance["size"]
        lines.extend(
            (
                "",
                f'[node name="{node_name}" type="Node2D" parent="StructureRoots"]',
                f"position = {_gd_vector(source['origin'], f'structures.instances.{instance_id}.origin')}",
                "scale = Vector2(1, 1)",
                f"visible = {'true' if instance['enabled'] else 'false'}",
                f"metadata/structure_id = {_gd_string(instance_id)}",
                f"metadata/template_id = {_gd_string(source['template_id'])}",
                f"metadata/landmark_id = {_gd_variant(source.get('landmark_id'))}",
                f"metadata/origin = {_gd_vector(source['origin'], f'structures.instances.{instance_id}.origin')}",
                f"metadata/size = {_gd_vector(source['size'], f'structures.instances.{instance_id}.size')}",
                f"metadata/topology_digest = {_gd_string(source['topology_digest'])}",
                f"metadata/partition_digest = {_gd_string(source['partition_digest'])}",
                f"metadata/runtime = {_gd_variant(source.get('runtime', {}))}",
                f"metadata/source = {_gd_variant(source)}",
                "",
                f'[node name="InteriorVisual" type="Node2D" parent="{root_path}"]',
                "position = Vector2(0, 0)",
                "scale = Vector2(1, 1)",
                "z_index = -20",
                'metadata/logical_layer_id = "L04"',
                "",
                f'[node name="StructureVisual" type="Node2D" parent="{root_path}"]',
                "position = Vector2(0, 0)",
                "scale = Vector2(1, 1)",
                "z_index = 0",
                'metadata/logical_layer_id = "L05"',
            )
        )
        for rectangle_index, rectangle in enumerate(binding["rectangles_px"]):
            x, y, width, height = rectangle
            left = x * pixel_width
            top = y * pixel_height
            right = (x + width) * pixel_width
            bottom = (y + height) * pixel_height
            lines.extend(
                (
                    "",
                    f'[node name="Solid{rectangle_index:04d}" type="ColorRect" parent="{root_path}/StructureVisual"]',
                    f"offset_left = {_gd_number(left)}",
                    f"offset_top = {_gd_number(top)}",
                    f"offset_right = {_gd_number(right)}",
                    f"offset_bottom = {_gd_number(bottom)}",
                    f"color = {_gd_color(STRUCTURE_SOLID_COLOR, 'structure.solid')}",
                    "mouse_filter = 2",
                    f"metadata/owner_id = {_gd_string(instance_id)}",
                    "metadata/pixel_rect = Rect2i("
                    f"{x}, {y}, {width}, {height})",
                )
            )

        _append_structure_visual_assets(
            lines,
            root_path,
            instance_id,
            visual_asset_bindings,
        )

        lines.extend(
            (
                "",
                f'[node name="StaticCollision" type="StaticBody2D" parent="{root_path}"]',
                "position = Vector2(0, 0)",
                "scale = Vector2(1, 1)",
                "collision_layer = 1",
                "collision_mask = 0",
            )
        )
        if "shape_id" in binding:
            lines.extend(
                (
                    "",
                    f'[node name="CollisionShape2D" type="CollisionShape2D" parent="{root_path}/StaticCollision"]',
                    "position = Vector2(0, 0)",
                    "scale = Vector2(1, 1)",
                    f"shape = SubResource({_gd_string(binding['shape_id'])})",
                )
            )
        lines.extend(
            (
                "",
                f'[node name="DynamicBodies" type="Node2D" parent="{root_path}"]',
                "position = Vector2(0, 0)",
                "scale = Vector2(1, 1)",
                "",
                f'[node name="Interactives" type="Node2D" parent="{root_path}"]',
                "position = Vector2(0, 0)",
                "scale = Vector2(1, 1)",
            )
        )
        for collection_name, record_index, record in local_interactives.get(
            instance_id,
            [],
        ):
            marker_name = _safe_node_name(str(record["id"]))
            lines.extend(
                (
                    "",
                    f'[node name="{marker_name}" type="Marker2D" parent="{root_path}/Interactives"]',
                    f"position = {_gd_vector(record['position'], f'gameplay.{collection_name}[{record_index}].position')}",
                    "scale = Vector2(1, 1)",
                    f"metadata/object_id = {_gd_string(record['id'])}",
                    f"metadata/kind = {_gd_string(collection_name)}",
                    f"metadata/source = {_gd_variant(record)}",
                )
            )


def _structure_scene_filesystem_path(instance: dict[str, Any]) -> Path:
    resource_path = str(instance["source"]["structure_scene_path"])
    prefix = "res://underwater_map_workbench/"
    if not resource_path.startswith(prefix):
        raise ManifestError(
            f"structure {instance['id']} has an invalid generated scene path"
        )
    relative_path = resource_path[len(prefix) :]
    resolved = (WORKBENCH_DIR / relative_path).resolve()
    try:
        resolved.relative_to(WORKBENCH_DIR.resolve())
    except ValueError as error:
        raise ManifestError("generated structure scene escapes the workbench") from error
    return resolved


def _render_structure_scene(
    manifest: dict[str, Any],
    topology_build: dict[str, Any],
    instance: dict[str, Any],
) -> str:
    instance_id = str(instance["id"])
    source: dict[str, Any] = instance["source"]
    ext_resources, visual_sub_resources, asset_bindings = (
        _scene_visual_asset_resources(
            manifest,
            structure_id_filter=instance_id,
        )
    )
    shape_sub_resources: list[str] = []
    binding: dict[str, Any] = {
        "instance": instance,
        "rectangles_px": _merged_structure_owner_rectangles(
            topology_build,
            instance,
        ),
    }
    segments = _structure_owner_boundary_segments(topology_build, instance)
    if segments:
        shape_id = "ConcavePolygonShape2D_structure_local"
        binding["shape_id"] = shape_id
        shape_sub_resources.extend(
            (
                "",
                f'[sub_resource type="ConcavePolygonShape2D" id="{shape_id}"]',
                f"segments = {_gd_points(segments)}",
            )
        )
    sub_resources = [*visual_sub_resources, *shape_sub_resources]
    temporary_lines: list[str] = []
    _append_structure_roots(
        temporary_lines,
        [binding],
        manifest,
        topology_build,
        asset_bindings,
    )
    node_name = _safe_node_name(instance_id)
    root_path = f"StructureRoots/{node_name}"
    root_header = (
        f'[node name="{node_name}" type="Node2D" parent="StructureRoots"]'
    )
    try:
        start_index = temporary_lines.index(root_header)
    except ValueError as error:
        raise ManifestError(
            f"cannot isolate generated structure root {instance_id}"
        ) from error

    body: list[str] = []
    current_is_root = False
    for original_line in temporary_lines[start_index:]:
        line = original_line
        if line.startswith("[node "):
            current_is_root = line == root_header
            if current_is_root:
                body.extend(
                    (
                        '[node name="StructureRoot" type="Node2D"]',
                        "position = Vector2(0, 0)",
                        "scale = Vector2(1, 1)",
                        "visible = true",
                        "metadata/package_manifest_path = "
                        + _gd_string(
                            "res://underwater_map_workbench/"
                            + str(source["package_path"])
                        ),
                        "metadata/package_manifest_sha256 = "
                        + _gd_string(source["package_sha256"]),
                        "metadata/local_topology_digest = "
                        + _gd_string(source["local_topology_digest"]),
                        "metadata/controller_script = "
                        + _gd_string(source["controller_script"]),
                    )
                )
                continue
            line = line.replace(
                f'parent="{root_path}"',
                'parent="."',
            ).replace(
                f'parent="{root_path}/',
                'parent="',
            )
            body.append(line)
            continue
        if current_is_root:
            if line.startswith(("position = ", "scale = ", "visible = ")):
                continue
            if line.startswith(
                (
                    "metadata/landmark_id = ",
                    "metadata/origin = ",
                    "metadata/topology_digest = ",
                    "metadata/partition_digest = ",
                    "metadata/source = ",
                )
            ):
                continue
        body.append(line)

    load_steps = 1 + len(ext_resources) + sum(
        1 for line in sub_resources if line.startswith("[sub_resource")
    )
    lines = [
        "; Generated by underwater_map_workbench/tools/build_underwater_map.py.",
        "; Edit structure_manifest.json, never this file by hand.",
        (
            f"[gd_scene load_steps={load_steps} format=3]"
            if ext_resources or sub_resources
            else "[gd_scene format=3]"
        ),
    ]
    if ext_resources or sub_resources:
        lines.extend(("", *ext_resources, *sub_resources, ""))
    else:
        lines.append("")
    lines.extend(body)
    return "\n".join(lines) + "\n"


def _render_structure_scenes(
    manifest: dict[str, Any],
    topology_build: dict[str, Any],
) -> dict[Path, bytes]:
    outputs: dict[Path, bytes] = {}
    for instance in topology_build["structure_build"]["instances"]:
        # A disabled package is still independently buildable and checkable.
        outputs[_structure_scene_filesystem_path(instance)] = (
            _render_structure_scene(
                manifest,
                topology_build,
                instance,
            ).encode("utf-8")
        )
    return outputs


def _append_structure_scene_instances(
    lines: list[str],
    topology_build: dict[str, Any],
    scene_resource_ids: dict[str, str],
) -> None:
    lines.extend(
        (
            "",
            '[node name="StructureRoots" type="Node2D" parent="."]',
            "position = Vector2(0, 0)",
            "scale = Vector2(1, 1)",
        )
    )
    for instance in topology_build["structure_build"]["instances"]:
        if not instance["enabled"]:
            continue
        source: dict[str, Any] = instance["source"]
        instance_id = str(instance["id"])
        node_name = _safe_node_name(instance_id)
        resource_id = scene_resource_ids[instance_id]
        lines.extend(
            (
                "",
                f'[node name="{node_name}" parent="StructureRoots" instance=ExtResource("{resource_id}")]',
                f"position = {_gd_vector(source['origin'], f'structures.instances.{instance_id}.origin')}",
                "scale = Vector2(1, 1)",
                "visible = true",
                f"metadata/structure_id = {_gd_string(instance_id)}",
                f"metadata/template_id = {_gd_string(source['template_id'])}",
                f"metadata/landmark_id = {_gd_variant(source.get('landmark_id'))}",
                f"metadata/origin = {_gd_vector(source['origin'], f'structures.instances.{instance_id}.origin')}",
                f"metadata/size = {_gd_vector(source['size'], f'structures.instances.{instance_id}.size')}",
                f"metadata/topology_digest = {_gd_string(source['topology_digest'])}",
                f"metadata/partition_digest = {_gd_string(source['partition_digest'])}",
                f"metadata/runtime = {_gd_variant(source.get('runtime', {}))}",
                f"metadata/controller_script = {_gd_string(source['controller_script'])}",
                f"metadata/package_manifest_path = {_gd_string('res://underwater_map_workbench/' + source['package_path'])}",
                f"metadata/package_manifest_sha256 = {_gd_string(source['package_sha256'])}",
                f"metadata/local_topology_digest = {_gd_string(source['local_topology_digest'])}",
                f"metadata/source = {_gd_variant(source)}",
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


def _append_portal_backdrop_clearances(
    lines: list[str],
    manifest: dict[str, Any],
    topology_build: dict[str, Any],
) -> None:
    layers_by_id = {
        str(layer["id"]): layer
        for layer in manifest["visual"]["layers"]
    }
    missing_layers = [
        layer_id
        for layer_id in (
            *PORTAL_BACKDROP_CLEARANCE_OCCLUDED_LAYER_IDS,
            *PORTAL_BACKDROP_CLEARANCE_FOREGROUND_LAYER_IDS,
        )
        if layer_id not in layers_by_id
    ]
    if missing_layers:
        raise ManifestError(
            "portal backdrop clearance misses visual layers: "
            + ", ".join(missing_layers)
        )
    backdrop_z = max(
        int(layers_by_id[layer_id]["z_index"])
        for layer_id in PORTAL_BACKDROP_CLEARANCE_OCCLUDED_LAYER_IDS
    )
    foreground_z = min(
        int(layers_by_id[layer_id]["z_index"])
        for layer_id in PORTAL_BACKDROP_CLEARANCE_FOREGROUND_LAYER_IDS
    )
    clearance_z = backdrop_z + 1
    if clearance_z >= foreground_z:
        raise ManifestError(
            "portal backdrop clearance requires z-order above L01/L02 "
            "and below L03/L04"
        )
    clearances = _portal_backdrop_clearances(topology_build)
    aggregate_digest = _canonical_sha256(
        [clearance["geometry"] for clearance in clearances]
    )
    root_path = (
        f"VisualLayers/{PORTAL_BACKDROP_CLEARANCE_HOST_LAYER_ID}/"
        "PortalBackdropClearances"
    )
    lines.extend(
        (
            "",
            '[node name="PortalBackdropClearances" type="Node2D" '
            f'parent="VisualLayers/{PORTAL_BACKDROP_CLEARANCE_HOST_LAYER_ID}"]',
            "position = Vector2(0, 0)",
            "scale = Vector2(1, 1)",
            "z_as_relative = false",
            f"z_index = {clearance_z}",
            f"metadata/contract = {_gd_string(PORTAL_BACKDROP_CLEARANCE_CONTRACT)}",
            'metadata/role = "portal_backdrop_clearance"',
            'metadata/space = "world_locked"',
            "metadata/visual_only = true",
            "metadata/occluded_layer_ids = PackedStringArray("
            + ", ".join(
                _gd_string(layer_id)
                for layer_id in PORTAL_BACKDROP_CLEARANCE_OCCLUDED_LAYER_IDS
            )
            + ")",
            f"metadata/host_layer_id = {_gd_string(PORTAL_BACKDROP_CLEARANCE_HOST_LAYER_ID)}",
            f"metadata/geometry_digest = {_gd_string(aggregate_digest)}",
            f"metadata/clearance_count = {len(clearances)}",
            "metadata/normal_core_cells = "
            f"{PORTAL_BACKDROP_CLEARANCE_NORMAL_CORE_CELLS}",
            "metadata/tangent_padding_cells = "
            f"{PORTAL_BACKDROP_CLEARANCE_TANGENT_PADDING_CELLS}",
            "metadata/feather_cells = "
            f"{PORTAL_BACKDROP_CLEARANCE_FEATHER_CELLS}",
            "metadata/feather_outer_tint = "
            f"{_gd_number(PORTAL_BACKDROP_CLEARANCE_FEATHER_OUTER_TINT)}",
        )
    )
    water_color = _gd_color(
        manifest["visual"]["water_color"],
        "visual.water_color",
    )
    shadow = ", ".join(
        (
            _gd_number(PORTAL_BACKDROP_CLEARANCE_FEATHER_OUTER_TINT),
            _gd_number(PORTAL_BACKDROP_CLEARANCE_FEATHER_OUTER_TINT),
            _gd_number(PORTAL_BACKDROP_CLEARANCE_FEATHER_OUTER_TINT),
            "1",
        )
    )
    opaque = "1, 1, 1, 1"
    for clearance in clearances:
        geometry_digest = str(clearance["geometry_digest"])
        node_name = f"Clearance_{geometry_digest}"
        node_path = f"{root_path}/{node_name}"
        core_x, core_y, core_width, core_height = clearance["core_rect"]
        outer_x, outer_y, outer_width, outer_height = clearance["outer_rect"]
        core_right = core_x + core_width
        core_bottom = core_y + core_height
        outer_right = outer_x + outer_width
        outer_bottom = outer_y + outer_height
        core_points = (
            (core_x, core_y),
            (core_right, core_y),
            (core_right, core_bottom),
            (core_x, core_bottom),
        )
        feather_records = (
            (
                "FeatherLeft",
                (
                    (outer_x, core_y),
                    (core_x, core_y),
                    (core_x, core_bottom),
                    (outer_x, core_bottom),
                ),
                (shadow, opaque, opaque, shadow),
            ),
            (
                "FeatherRight",
                (
                    (core_right, core_y),
                    (outer_right, core_y),
                    (outer_right, core_bottom),
                    (core_right, core_bottom),
                ),
                (opaque, shadow, shadow, opaque),
            ),
            (
                "FeatherTop",
                (
                    (core_x, outer_y),
                    (core_right, outer_y),
                    (core_right, core_y),
                    (core_x, core_y),
                ),
                (shadow, shadow, opaque, opaque),
            ),
            (
                "FeatherBottom",
                (
                    (core_x, core_bottom),
                    (core_right, core_bottom),
                    (core_right, outer_bottom),
                    (core_x, outer_bottom),
                ),
                (opaque, opaque, shadow, shadow),
            ),
        )
        lines.extend(
            (
                "",
                f'[node name="{node_name}" type="Node2D" parent="{root_path}"]',
                "position = Vector2(0, 0)",
                "scale = Vector2(1, 1)",
                f"metadata/geometry_digest = {_gd_string(geometry_digest)}",
                f"metadata/source_geometry = {_gd_variant(clearance['geometry'])}",
                "metadata/opening_center = "
                + _gd_vector(
                    clearance["opening_center"],
                    "portal_backdrop_clearance.opening_center",
                ),
                "metadata/outward = "
                + _gd_vector(
                    clearance["outward"],
                    "portal_backdrop_clearance.outward",
                ),
                f"metadata/span = {_gd_number(clearance['span'])}",
                "metadata/core_rect = Rect2("
                f"{_gd_number(core_x)}, {_gd_number(core_y)}, "
                f"{_gd_number(core_width)}, {_gd_number(core_height)})",
                "metadata/outer_rect = Rect2("
                f"{_gd_number(outer_x)}, {_gd_number(outer_y)}, "
                f"{_gd_number(outer_width)}, {_gd_number(outer_height)})",
                "metadata/visual_only = true",
                "",
                f'[node name="Core" type="Polygon2D" parent="{node_path}"]',
                f"polygon = {_gd_points(core_points)}",
                f"color = {water_color}",
                "antialiased = true",
                'metadata/role = "portal_backdrop_clearance_core"',
            )
        )
        for feather_name, feather_points, vertex_colors in feather_records:
            lines.extend(
                (
                    "",
                    f'[node name="{feather_name}" type="Polygon2D" parent="{node_path}"]',
                    f"polygon = {_gd_points(feather_points)}",
                    f"color = {water_color}",
                    "vertex_colors = PackedColorArray("
                    + ", ".join(vertex_colors)
                    + ")",
                    "antialiased = true",
                    'metadata/role = "portal_backdrop_clearance_feather"',
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


def _append_manifest_markers(
    lines: list[str],
    manifest: dict[str, Any],
    structure_build: dict[str, Any],
) -> None:
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
    world_size = _pair(manifest["map"]["world_size"], "map.world_size")
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
                resolved_position = _resolve_gameplay_position(
                    record,
                    f"gameplay.{collection_name}[{record_index}]",
                    world_size,
                    structure_build,
                )
                lines.append(
                    f"position = {_gd_vector(list(resolved_position), f'gameplay.{collection_name}[{record_index}].resolved_position')}"
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
        manifest,
        include_structure_assets=False,
    )
    structure_scene_resource_ids: dict[str, str] = {}
    for index, instance in enumerate(
        topology_build["structure_build"]["instances"]
    ):
        if not instance["enabled"]:
            continue
        instance_id = str(instance["id"])
        resource_id = f"PackedScene_structure_{index:04d}"
        structure_scene_resource_ids[instance_id] = resource_id
        ext_resources.append(
            f'[ext_resource type="PackedScene" '
            f'path="{instance["source"]["structure_scene_path"]}" '
            f'id="{resource_id}"]'
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
        f"metadata/structures = {_gd_variant(manifest['structures'])}",
        f"metadata/campaign = {_gd_variant(manifest['campaign'])}",
    ])
    if topology_build.get("mode") == L05_MODE:
        lines.extend(
            (
                f"metadata/payload_sha256 = {_gd_string(topology_build['payload_sha256'])}",
                f"metadata/canonical_digest = {_gd_string(topology_build['canonical_digest'])}",
                f"metadata/partition_digest = {_gd_string(topology_build['partition_digest'])}",
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
        elif layer_id == PORTAL_BACKDROP_CLEARANCE_HOST_LAYER_ID:
            _append_portal_backdrop_clearances(
                lines,
                manifest,
                topology_build,
            )
        elif layer_id == "L05" and topology_build.get("mode") == "open_world":
            _append_world_border(lines, manifest, world_size)
    _append_visual_assets(lines, asset_bindings)
    _append_structure_scene_instances(
        lines,
        topology_build,
        structure_scene_resource_ids,
    )
    _append_manifest_regions(lines, manifest)
    _append_manifest_markers(
        lines,
        manifest,
        topology_build["structure_build"],
    )
    return "\n".join(lines) + "\n"


def _read_optional_bytes(path: Path) -> bytes | None:
    try:
        return path.read_bytes()
    except FileNotFoundError:
        return None


def _content_fingerprint(raw: bytes) -> str:
    return f"{len(raw)}:{hashlib.sha256(raw).hexdigest()}"


def _path_fingerprint(path: Path) -> str | None:
    raw = _read_optional_bytes(path)
    return None if raw is None else _content_fingerprint(raw)


def _package_member_input_paths(
    package: dict[str, Any],
    package_directory: Path,
    label: str,
) -> list[Path]:
    paths: list[Path] = []
    for collection_name in ("visual_assets", "scripts", "references"):
        for index, value in enumerate(
            _array(package.get(collection_name), f"{label}.{collection_name}")
        ):
            record = _object(value, f"{label}.{collection_name}[{index}]")
            _member_path, filesystem_path, _resource_path = (
                _structure_package_member_path(
                    package_directory,
                    record.get("path"),
                    f"{label}.{collection_name}[{index}].path",
                )
            )
            paths.append(filesystem_path)
    return paths


def _capture_package_input_fingerprint(
    package_path: Path,
    package_raw: bytes,
) -> dict[Path, str | None]:
    try:
        package_value = json.loads(package_raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ManifestError(f"invalid structure package JSON {package_path}: {error}") from error
    package = _object(package_value, f"structure package {package_path.parent.name}")
    paths = [
        package_path,
        *_package_member_input_paths(
            package,
            package_path.parent,
            f"structure package {package_path.parent.name}",
        ),
    ]
    fingerprints = {
        path.resolve(): (
            _content_fingerprint(package_raw)
            if path.resolve() == package_path.resolve()
            else _path_fingerprint(path.resolve())
        )
        for path in paths
    }
    _assert_input_fingerprint(fingerprints)
    return fingerprints


def _capture_manifest_input_fingerprint(
    manifest_raw: bytes,
    *,
    include_map_visual_assets: bool,
    structure_id_filter: str | None = None,
) -> dict[Path, str | None]:
    try:
        manifest_value = json.loads(manifest_raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ManifestError(f"invalid JSON: {error}") from error
    manifest = _object(manifest_value, "manifest")
    fingerprints: dict[Path, str | None] = {
        MANIFEST_PATH.resolve(): _content_fingerprint(manifest_raw)
    }

    topology = _object(manifest.get("topology"), "topology")
    collision_source = _object(
        topology.get("collision_source"),
        "topology.collision_source",
    )
    collision_path_value = collision_source.get("path")
    if collision_path_value:
        _relative_path, collision_path = _package_asset_path(
            collision_path_value,
            "topology.collision_source.path",
        )
        fingerprints[collision_path.resolve()] = _path_fingerprint(
            collision_path.resolve()
        )

    if include_map_visual_assets:
        visual = _object(manifest.get("visual"), "visual")
        for index, asset_value in enumerate(
            _array(visual.get("assets"), "visual.assets")
        ):
            asset = _object(asset_value, f"visual.assets[{index}]")
            asset_path_value = asset.get("path")
            if not asset_path_value:
                continue
            _relative_path, asset_path = _package_asset_path(
                asset_path_value,
                f"visual.assets[{index}].path",
            )
            fingerprints[asset_path.resolve()] = _path_fingerprint(
                asset_path.resolve()
            )

    registry = _object(manifest.get("structures"), "structures")
    if set(registry) == STRUCTURE_REGISTRY_KEYS:
        selected_structure_found = False
        for index, record_value in enumerate(
            _array(registry.get("instances"), "structures.instances")
        ):
            record = _object(record_value, f"structures.instances[{index}]")
            structure_id = _non_empty_string(
                record.get("id"),
                f"structures.instances[{index}].id",
            )
            if structure_id_filter is not None and structure_id != structure_id_filter:
                continue
            selected_structure_found = True
            package_reference = _object(
                record.get("package"),
                f"structures.instances[{index}].package",
            )
            package_relative = _non_empty_string(
                package_reference.get("path"),
                f"structures.instances[{index}].package.path",
            )
            package_path = (WORKBENCH_DIR / package_relative).resolve()
            try:
                package_path.relative_to(WORKBENCH_DIR.resolve())
            except ValueError as error:
                raise ManifestError(
                    f"structures.instances[{index}].package.path escapes the workbench"
                ) from error
            package_raw = package_path.read_bytes()
            package_fingerprints = _capture_package_input_fingerprint(
                package_path,
                package_raw,
            )
            fingerprints.update(package_fingerprints)
        if structure_id_filter is not None and not selected_structure_found:
            raise ManifestError(f"unknown structure package: {structure_id_filter}")

    _assert_input_fingerprint(fingerprints)
    return fingerprints


def _assert_input_fingerprint(
    expected: dict[Path, str | None],
) -> None:
    changed = [
        path
        for path, fingerprint in expected.items()
        if _path_fingerprint(path) != fingerprint
    ]
    if changed:
        labels = ", ".join(
            str(path.relative_to(WORKBENCH_DIR))
            if path.is_relative_to(WORKBENCH_DIR)
            else str(path)
            for path in changed
        )
        raise ManifestError(
            "build inputs changed before publication; retry from a stable sealed "
            f"snapshot: {labels}"
        )


def _restore_output_if_owned(
    destination: Path,
    written_content: bytes,
    original_content: bytes | None,
) -> bool:
    """Restore one output only while it still contains our exact write."""
    if _read_optional_bytes(destination) != written_content:
        return False
    if original_content is None:
        try:
            destination.unlink()
        except FileNotFoundError:
            return False
        return True

    descriptor, temporary_name = tempfile.mkstemp(
        dir=destination.parent,
        prefix=f".{destination.name}.rollback.",
        suffix=".tmp",
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(original_content)
            stream.flush()
            os.fsync(stream.fileno())
        if _read_optional_bytes(destination) != written_content:
            return False
        os.replace(temporary_path, destination)
        return True
    finally:
        temporary_path.unlink(missing_ok=True)


def _publish_outputs_with_cas(
    outputs: dict[Path, bytes],
    *,
    expected_current: dict[Path, bytes | None] | None = None,
    commit_marker: Path | None = None,
) -> None:
    """Publish with per-file atomic replace and set-level CAS/rollback.

    The set is deliberately not described as filesystem-atomic: readers that
    ignore the owner lock can observe intermediate files. Integration writers
    must therefore hold the shared publication lock, keep the scene/receipt
    marker last, and consumers must snapshot through that same boundary.
    """
    if not outputs:
        return
    if commit_marker is not None:
        marker_content = outputs.get(commit_marker)
        if marker_content is None:
            raise ManifestError(
                f"CAS publication commit marker is not an output: {commit_marker}"
            )
        outputs = {
            **{
                path: content
                for path, content in outputs.items()
                if path != commit_marker
            },
            commit_marker: marker_content,
        }
    if expected_current is not None and set(expected_current) != set(outputs):
        raise ManifestError(
            "expected_current must describe exactly every promoted output"
        )
    baseline = (
        dict(expected_current)
        if expected_current is not None
        else {
            destination: _read_optional_bytes(destination)
            for destination in outputs
        }
    )
    for destination, expected_content in baseline.items():
        if _read_optional_bytes(destination) != expected_content:
            raise ManifestError(
                "concurrent edit detected before CAS publication: "
                f"{destination}"
            )

    temporary_paths: list[tuple[Path, Path]] = []
    committed: list[Path] = []
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
        for index, (temporary_path, destination) in enumerate(temporary_paths):
            for committed_path in committed:
                if _read_optional_bytes(committed_path) != outputs[committed_path]:
                    raise ManifestError(
                        "concurrent edit detected during CAS publication: "
                        f"{committed_path}"
                    )
            for _pending_path, pending_destination in temporary_paths[index:]:
                if (
                    _read_optional_bytes(pending_destination)
                    != baseline[pending_destination]
                ):
                    raise ManifestError(
                        "concurrent edit detected during CAS publication: "
                        f"{pending_destination}"
                    )
            os.replace(temporary_path, destination)
            committed.append(destination)
        for destination, content in outputs.items():
            if _read_optional_bytes(destination) != content:
                raise ManifestError(
                    "concurrent edit detected after CAS publication: "
                    f"{destination}"
                )
    except BaseException as error:
        for temporary_path, _destination in temporary_paths:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError:
                pass
        rollback_issues: list[str] = []
        for destination in reversed(committed):
            try:
                restored = _restore_output_if_owned(
                    destination,
                    outputs[destination],
                    baseline[destination],
                )
            except OSError as rollback_error:
                rollback_issues.append(f"{destination}: {rollback_error}")
                continue
            if not restored:
                rollback_issues.append(
                    f"{destination}: rollback refused because bytes changed"
                )
        if rollback_issues:
            raise ManifestError(
                f"CAS publication failed ({error}); "
                "rollback did not overwrite concurrent work: "
                + "; ".join(rollback_issues)
            ) from error
        raise


def _prepare_l05_source_refresh(
    original_raw: bytes,
    *,
    full_manifest_validation: bool,
    verify_package_hashes: bool | None = None,
) -> tuple[bytes, bool, str, str, str]:
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
    resolved_manifest = _resolve_structure_packages(
        manifest,
        verify_package_hashes=(
            full_manifest_validation
            if verify_package_hashes is None
            else verify_package_hashes
        ),
    )
    world_size = _validate_map(resolved_manifest)
    structure_build = _validate_structures(resolved_manifest, world_size)
    topology_build = _validate_topology(
        resolved_manifest,
        world_size,
        structure_build,
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
        if (
            asset.get("kind") == "collision_masked_material"
            and asset.get("layer_id") == "L05"
            and asset.get("enabled") is True
        ):
            active_l05_assets.append(asset)
    if len(active_l05_assets) != 1:
        raise ManifestError(
            "--refresh-l05-source requires exactly one enabled L05 visual asset"
        )
    actual_sha = str(topology_build["payload_sha256"])
    canonical_digest = str(topology_build["canonical_digest"])
    partition_digest = str(topology_build["partition_digest"])
    changed = False
    if collision.get("sha256") != actual_sha:
        collision["sha256"] = actual_sha
        changed = True
    if collision.get("canonical_digest") != canonical_digest:
        collision["canonical_digest"] = canonical_digest
        changed = True
    if collision.get("partition_digest") != partition_digest:
        collision["partition_digest"] = partition_digest
        changed = True
    active_l05_asset = active_l05_assets[0]
    if active_l05_asset.get("topology_digest") != canonical_digest:
        active_l05_asset["topology_digest"] = canonical_digest
        changed = True

    updated_raw = original_raw
    if changed:
        updated_raw = (
            json.dumps(
                manifest,
                ensure_ascii=False,
                indent=2,
            )
            + "\n"
        ).encode("utf-8")
    if full_manifest_validation:
        _load_and_validate_manifest_raw(updated_raw)
    return (
        updated_raw,
        changed,
        actual_sha,
        canonical_digest,
        partition_digest,
    )


def _refresh_l05_source(*, full_manifest_validation: bool = True) -> bytes:
    original_raw = MANIFEST_PATH.read_bytes()
    inputs = _capture_manifest_input_fingerprint(
        original_raw,
        include_map_visual_assets=full_manifest_validation,
    )
    (
        updated_raw,
        changed,
        actual_sha,
        canonical_digest,
        partition_digest,
    ) = _prepare_l05_source_refresh(
        original_raw,
        full_manifest_validation=full_manifest_validation,
    )
    if changed:
        with _map_promotion_lock():
            _assert_input_fingerprint(inputs)
            _publish_outputs_with_cas(
                {MANIFEST_PATH: updated_raw},
                expected_current={MANIFEST_PATH: original_raw},
                commit_marker=MANIFEST_PATH,
            )
    else:
        _assert_input_fingerprint(inputs)
        print(
            "L05 source declarations are current; map_manifest.json unchanged "
            f"({actual_sha}, {canonical_digest}, {partition_digest})"
        )
        return original_raw
    print(
        "Refreshed L05 source declarations in map_manifest.json "
        f"({actual_sha}, {canonical_digest}, {partition_digest})"
    )
    return updated_raw


def _structure_package_path(structure_id: str) -> Path:
    if re.fullmatch(r"[a-z][a-z0-9_]*", structure_id) is None:
        raise ManifestError(
            "structure package ID must be lowercase snake_case"
        )
    package_path = (
        WORKBENCH_DIR
        / "structures"
        / structure_id
        / "structure_manifest.json"
    ).resolve()
    try:
        package_path.relative_to(WORKBENCH_DIR.resolve())
    except ValueError as error:
        raise ManifestError("structure package path escapes the workbench") from error
    if not package_path.is_file():
        raise ManifestError(
            f"structure package does not exist: structures/{structure_id}"
        )
    return package_path


def _prepare_structure_package_seal(
    structure_id: str,
    original_package_raw: bytes,
    *,
    validate_visuals: bool = True,
) -> tuple[bytes, str, str]:
    try:
        package_value = json.loads(original_package_raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ManifestError(
            f"invalid structure package JSON for {structure_id}: {error}"
        ) from error
    package = _object(package_value, f"structure package {structure_id}")
    if set(package) != STRUCTURE_PACKAGE_KEYS:
        raise ManifestError(
            f"structure package {structure_id} has an invalid exact key set"
        )
    if package.get("schema_version") != 1:
        raise ManifestError(f"structure package {structure_id}.schema_version must be 1")
    if package.get("format") != STRUCTURE_PACKAGE_FORMAT:
        raise ManifestError(
            f"structure package {structure_id}.format must be {STRUCTURE_PACKAGE_FORMAT}"
        )
    package_directory = _structure_package_path(structure_id).parent
    changed = False

    local_digest, _operations = _structure_local_topology(
        package,
        f"structure package {structure_id}",
        verify_declaration=False,
    )
    if package.get("local_topology_digest") != local_digest:
        package["local_topology_digest"] = local_digest
        changed = True

    for index, asset_value in enumerate(
        _array(package["visual_assets"], "structure package visual_assets")
    ):
        asset = _object(asset_value, f"visual_assets[{index}]")
        if set(asset) != STRUCTURE_PACKAGE_VISUAL_ASSET_KEYS:
            raise ManifestError(f"visual_assets[{index}] has an invalid exact key set")
        _path, filesystem_path, _resource_path = _structure_package_member_path(
            package_directory,
            asset["path"],
            f"visual_assets[{index}].path",
        )
        if not filesystem_path.is_file():
            raise ManifestError(f"visual_assets[{index}].path does not exist")
        raw = filesystem_path.read_bytes()
        actual_sha = hashlib.sha256(raw).hexdigest()
        actual_size = _png_dimensions(raw, str(asset["path"]))
        if validate_visuals:
            _validate_structure_visual_png(
                filesystem_path,
                actual_size,
                f"visual_assets[{index}]",
            )
        if asset.get("sha256") != actual_sha:
            asset["sha256"] = actual_sha
            changed = True
        if asset.get("pixel_size") != list(actual_size):
            asset["pixel_size"] = list(actual_size)
            changed = True

    for index, script_value in enumerate(
        _array(package["scripts"], "structure package scripts")
    ):
        script = _object(script_value, f"scripts[{index}]")
        if set(script) != STRUCTURE_PACKAGE_SCRIPT_KEYS:
            raise ManifestError(f"scripts[{index}] has an invalid exact key set")
        _path, filesystem_path, _resource_path = _structure_package_member_path(
            package_directory,
            script["path"],
            f"scripts[{index}].path",
        )
        if not filesystem_path.is_file():
            raise ManifestError(f"scripts[{index}].path does not exist")
        actual_sha = hashlib.sha256(filesystem_path.read_bytes()).hexdigest()
        if script.get("sha256") != actual_sha:
            script["sha256"] = actual_sha
            changed = True

    for index, reference_value in enumerate(
        _array(package["references"], "structure package references")
    ):
        reference = _object(reference_value, f"references[{index}]")
        if set(reference) != STRUCTURE_PACKAGE_REFERENCE_KEYS_EXACT:
            raise ManifestError(f"references[{index}] has an invalid exact key set")
        _path, filesystem_path, _resource_path = _structure_package_member_path(
            package_directory,
            reference["path"],
            f"references[{index}].path",
        )
        if not filesystem_path.is_file():
            raise ManifestError(f"references[{index}].path does not exist")
        actual_sha = hashlib.sha256(filesystem_path.read_bytes()).hexdigest()
        if reference.get("sha256") != actual_sha:
            reference["sha256"] = actual_sha
            changed = True

    updated_package_raw = (
        (
            json.dumps(package, ensure_ascii=False, indent=2) + "\n"
        ).encode("utf-8")
        if changed
        else original_package_raw
    )
    actual_package_sha = hashlib.sha256(updated_package_raw).hexdigest()
    return updated_package_raw, actual_package_sha, local_digest


def _seal_structure_package(structure_id: str) -> None:
    package_path = _structure_package_path(structure_id)
    original_package_raw = package_path.read_bytes()
    inputs = _capture_package_input_fingerprint(
        package_path,
        original_package_raw,
    )
    updated_package_raw, package_sha, local_digest = (
        _prepare_structure_package_seal(
            structure_id,
            original_package_raw,
        )
    )
    if updated_package_raw == original_package_raw:
        _assert_input_fingerprint(inputs)
        print(
            f"Structure package {structure_id} is already sealed "
            f"({package_sha}, {local_digest})"
        )
        return
    with InterprocessWorkspaceLock(
        WORKBENCH_DIR.parent,
        f"structure-seal-{structure_id}",
    ):
        _assert_input_fingerprint(inputs)
        _publish_outputs_with_cas(
            {package_path: updated_package_raw},
            expected_current={package_path: original_package_raw},
            commit_marker=package_path,
        )
    print(
        f"Sealed structure package {structure_id} "
        f"({package_sha}, {local_digest})"
    )


def _refresh_structure_packages(
    structure_revisions: Iterable[tuple[str, str]],
    *,
    full_manifest_validation: bool,
) -> None:
    revisions = list(structure_revisions)
    if not revisions:
        raise ManifestError("structure refresh batch must not be empty")
    requested_ids: set[str] = set()
    normalized_revisions: list[tuple[str, str, Path]] = []
    for structure_id, sealed_package_sha256 in revisions:
        if structure_id in requested_ids:
            raise ManifestError(
                f"structure refresh batch contains duplicate ID: {structure_id}"
            )
        requested_ids.add(structure_id)
        package_path = _structure_package_path(structure_id)
        expected_package_sha = _sha256(
            sealed_package_sha256,
            f"--sealed-package-sha256 for {structure_id}",
        )
        normalized_revisions.append(
            (structure_id, expected_package_sha, package_path)
        )

    original_manifest_raw = MANIFEST_PATH.read_bytes()
    inputs = _capture_manifest_input_fingerprint(
        original_manifest_raw,
        include_map_visual_assets=full_manifest_validation,
    )
    try:
        map_manifest_value = json.loads(original_manifest_raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ManifestError(f"invalid JSON: {error}") from error
    map_manifest = _object(map_manifest_value, "manifest")
    registry = _object(map_manifest.get("structures"), "structures")
    if set(registry) != STRUCTURE_REGISTRY_KEYS:
        raise ManifestError(
            "--refresh-structure-package requires schema v6 package registry"
        )
    prepared_revisions: list[tuple[str, dict[str, Any], str, str]] = []
    registry_instances = _array(registry["instances"], "structures.instances")
    for structure_id, expected_package_sha, package_path in normalized_revisions:
        matches = [
            _object(value, "structure registry instance")
            for value in registry_instances
            if isinstance(value, dict) and value.get("id") == structure_id
        ]
        if len(matches) != 1:
            raise ManifestError(
                f"structure registry must contain exactly one {structure_id}"
            )
        registry_record = matches[0]
        package_reference = _object(
            registry_record.get("package"),
            f"structure {structure_id}.package",
        )
        expected_path = f"structures/{structure_id}/structure_manifest.json"
        if package_reference.get("path") != expected_path:
            raise ManifestError(
                f"structure {structure_id} package path must be {expected_path}"
            )
        original_package_raw = package_path.read_bytes()
        sealed_raw, actual_package_sha, local_digest = (
            _prepare_structure_package_seal(
                structure_id,
                original_package_raw,
                validate_visuals=False,
            )
        )
        if sealed_raw != original_package_raw:
            raise ManifestError(
                f"structure package {structure_id} is not sealed; run "
                f"--seal-structure-package {structure_id} in its private workbench first"
            )
        if actual_package_sha != expected_package_sha:
            raise ManifestError(
                f"sealed hand-off for {structure_id} expected {expected_package_sha}, "
                f"but the live private manifest is {actual_package_sha}"
            )
        prepared_revisions.append(
            (structure_id, package_reference, actual_package_sha, local_digest)
        )

    # Apply every verified pin to one in-memory candidate before resolving any
    # package. This avoids an impossible mixed revision when two or more live
    # manifests have advanced together.
    for _structure_id, package_reference, actual_package_sha, _digest in (
        prepared_revisions
    ):
        package_reference["sha256"] = actual_package_sha
    pinned_manifest_raw = (
        json.dumps(map_manifest, ensure_ascii=False, indent=2) + "\n"
    ).encode("utf-8")
    (
        updated_manifest_raw,
        _l05_changed,
        _payload_sha,
        canonical_digest,
        partition_digest,
    ) = _prepare_l05_source_refresh(
        pinned_manifest_raw,
        full_manifest_validation=False,
        verify_package_hashes=True,
    )
    if full_manifest_validation:
        _load_and_validate_manifest_raw(updated_manifest_raw)

    if updated_manifest_raw == original_manifest_raw:
        _assert_input_fingerprint(inputs)
        labels = ", ".join(
            f"{structure_id}={actual_package_sha}"
            for structure_id, _reference, actual_package_sha, _digest in (
                prepared_revisions
            )
        )
        print(
            f"Structure package map pins are current ({labels})"
        )
        return
    with _map_promotion_lock():
        _assert_input_fingerprint(inputs)
        _publish_outputs_with_cas(
            {MANIFEST_PATH: updated_manifest_raw},
            expected_current={MANIFEST_PATH: original_manifest_raw},
            commit_marker=MANIFEST_PATH,
        )
    labels = ", ".join(
        f"{structure_id}={actual_package_sha} ({local_digest})"
        for structure_id, _reference, actual_package_sha, local_digest in (
            prepared_revisions
        )
    )
    print(
        "Promoted sealed structure package batch into map authority "
        f"({labels}; {canonical_digest}, {partition_digest})"
    )


def _refresh_structure_package(
    structure_id: str,
    sealed_package_sha256: str,
) -> None:
    # Preserve the established single-package API while the CLI may submit a
    # closed multi-package batch.
    _refresh_structure_packages(
        [(structure_id, sealed_package_sha256)],
        full_manifest_validation=False,
    )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--build", action="store_true", help="write the deterministic scene")
    mode.add_argument("--check", action="store_true", help="verify that the scene is current")
    mode.add_argument(
        "--build-structure",
        metavar="STRUCTURE_ID",
        help=(
            "write one package-local candidate set into this worktree's "
            "ignored .godot staging lane"
        ),
    )
    mode.add_argument(
        "--check-structure",
        metavar="STRUCTURE_ID",
        help=(
            "verify one package-local candidate set in this worktree's "
            "ignored .godot staging lane"
        ),
    )
    mode.add_argument(
        "--refresh-l05-source",
        action="store_true",
        help=(
            "refresh L05 payload SHA, canonical digest and partition digest "
            "in the manifest"
        ),
    )
    mode.add_argument(
        "--seal-structure-package",
        metavar="STRUCTURE_ID",
        help=(
            "refresh only one private structure manifest's local digest and "
            "member hashes"
        ),
    )
    mode.add_argument(
        "--refresh-structure-package",
        metavar="STRUCTURE_ID",
        action="append",
        help=(
            "promote an already sealed structure manifest into the map "
            "registry pin and composed L05 declarations; repeat together "
            "with --sealed-package-sha256 for one atomic batch"
        ),
    )
    parser.add_argument(
        "--sealed-package-sha256",
        action="append",
        help=(
            "exact structure_manifest.json SHA-256 from the producer's "
            "immutable/FROZEN hand-off; repeat in the same order as "
            "--refresh-structure-package"
        ),
    )
    return parser.parse_args()


def _render_build_candidate(
    manifest_raw: bytes,
) -> tuple[
    dict[Path, bytes],
    dict[str, Any],
    str,
    str,
    str,
]:
    (
        manifest,
        manifest_sha,
        gameplay_signature,
        presentation_fingerprint,
        topology_build,
    ) = _load_and_validate_manifest_raw(manifest_raw)
    expected = render_scene(
        manifest,
        manifest_sha,
        gameplay_signature,
        presentation_fingerprint,
        topology_build,
    )
    expected_outputs = _render_l05_artifacts(
        topology_build,
        manifest_sha,
        manifest,
    )
    expected_outputs.update(
        _render_structure_scenes(
            manifest,
            topology_build,
        )
    )
    expected_outputs[SCENE_PATH] = expected.encode("utf-8")
    return (
        expected_outputs,
        topology_build,
        manifest_sha,
        gameplay_signature,
        presentation_fingerprint,
    )


def _render_structure_build_candidate(
    manifest_raw: bytes,
    structure_id: str,
) -> tuple[dict[Path, bytes], dict[str, Any], str]:
    package_path = _structure_package_path(structure_id)
    package_raw = package_path.read_bytes()
    sealed_raw, _package_sha, _local_digest = _prepare_structure_package_seal(
        structure_id,
        package_raw,
        validate_visuals=False,
    )
    if sealed_raw != package_raw:
        raise ManifestError(
            f"structure package {structure_id} is not sealed; run "
            f"--seal-structure-package {structure_id} first"
        )
    try:
        manifest_value = json.loads(manifest_raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ManifestError(f"invalid JSON: {error}") from error
    manifest = _object(manifest_value, "manifest")
    if manifest.get("schema_version") != MAP_SCHEMA_VERSION:
        raise ManifestError(f"schema_version must be {MAP_SCHEMA_VERSION}")
    manifest = _resolve_structure_packages(
        manifest,
        verify_package_hashes=False,
        structure_id_filter=structure_id,
    )
    world_size = _validate_map(manifest)
    structure_build = _validate_structures(manifest, world_size)
    topology_build = _validate_topology(
        manifest,
        world_size,
        structure_build,
        verify_declarations=False,
    )
    collision_declaration = _object(
        _object(manifest["topology"], "topology")["collision_source"],
        "topology.collision_source",
    )
    declared_payload_sha = _sha256(
        collision_declaration["sha256"],
        "topology.collision_source.sha256",
    )
    if topology_build.get("payload_sha256") != declared_payload_sha:
        raise ManifestError(
            "topology.collision_source.sha256 is stale; "
            f"expected {topology_build.get('payload_sha256')}"
        )
    # The local raster intentionally omits other private packages. Generated
    # package metadata still carries the public, map-owned integration digests.
    topology_build["canonical_digest"] = collision_declaration["canonical_digest"]
    topology_build["partition_digest"] = collision_declaration["partition_digest"]
    instances = [
        instance
        for instance in structure_build["instances"]
        if str(instance["id"]) == structure_id
    ]
    if len(instances) != 1:
        raise ManifestError(f"unknown structure package: {structure_id}")
    manifest_sha = hashlib.sha256(manifest_raw).hexdigest()
    outputs = _render_l05_artifacts(
        topology_build,
        manifest_sha,
        manifest,
        structure_id_filter=structure_id,
        include_map_artifacts=False,
    )
    instance = instances[0]
    outputs[_structure_scene_filesystem_path(instance)] = (
        _render_structure_scene(
            manifest,
            topology_build,
            instance,
        ).encode("utf-8")
    )
    if not outputs:
        raise ManifestError(
            f"no generated outputs for structure package {structure_id}"
        )
    return outputs, topology_build, manifest_sha


def _structure_local_output_root(structure_id: str) -> Path:
    if re.fullmatch(r"[a-z][a-z0-9_]*", structure_id) is None:
        raise ManifestError("structure package ID must be lowercase snake_case")
    return (
        WORKBENCH_DIR.parent
        / ".godot"
        / "underwater_map_structure_builds"
        / structure_id
        / "generated"
    ).resolve()


def _remap_structure_outputs_to_local_lane(
    outputs: dict[Path, bytes],
    structure_id: str,
) -> dict[Path, bytes]:
    authority_root = (
        WORKBENCH_DIR / "structures" / structure_id / "generated"
    ).resolve()
    local_root = _structure_local_output_root(structure_id)
    remapped: dict[Path, bytes] = {}
    for original_path, content in outputs.items():
        resolved = original_path.resolve()
        try:
            relative = resolved.relative_to(authority_root)
        except ValueError as error:
            raise ManifestError(
                f"structure-local renderer returned an output outside {authority_root}: "
                f"{resolved}"
            ) from error
        destination = (local_root / relative).resolve()
        try:
            destination.relative_to(local_root)
        except ValueError as error:
            raise ManifestError("structure-local output escapes its staging lane") from error
        remapped[destination] = content
    return remapped


@contextmanager
def _structure_local_build_lock(structure_id: str) -> Iterable[None]:
    # The scope is the current checkout and the lock name is package-specific:
    # linked worktrees and different structure IDs never share this lane.
    with InterprocessWorkspaceLock(
        WORKBENCH_DIR.parent,
        f"structure-local-build-{structure_id}",
    ):
        yield


def _capture_publication_output_baseline(
    *,
    structure_id: str | None,
) -> dict[Path, bytes | None]:
    roots: list[Path]
    explicit_paths: list[Path] = []
    if structure_id is None:
        roots = [L05_GENERATED_DIR, WORKBENCH_DIR / "structures"]
        explicit_paths.append(SCENE_PATH)
    else:
        roots = [_structure_local_output_root(structure_id)]
    paths: set[Path] = {path.resolve() for path in explicit_paths}
    for root in roots:
        if not root.is_dir():
            continue
        for path in root.rglob("*"):
            if not path.is_file() or path.name.endswith(".import"):
                continue
            if any(
                part.startswith(".") and ".tmp-" in part
                for part in path.relative_to(root).parts
            ):
                continue
            if structure_id is None and "generated" not in path.parts:
                continue
            paths.add(path.resolve())
    return {
        path: _read_optional_bytes(path)
        for path in sorted(paths, key=lambda value: str(value).lower())
    }


def _expected_output_baseline(
    expected_outputs: dict[Path, bytes],
    captured: dict[Path, bytes | None],
) -> dict[Path, bytes | None]:
    return {
        path: captured.get(path.resolve())
        for path in expected_outputs
    }


def _check_expected_outputs(
    expected_outputs: dict[Path, bytes],
    inputs: dict[Path, str | None],
    *,
    structure_id: str | None,
) -> int:
    actual_outputs = {
        path: _read_optional_bytes(path)
        for path in expected_outputs
    }
    _assert_input_fingerprint(inputs)
    for output_path, expected_bytes in expected_outputs.items():
        actual_bytes = actual_outputs[output_path]
        if actual_bytes is None:
            print(f"generated output is missing: {output_path}", file=sys.stderr)
            return 1
        if actual_bytes != expected_bytes:
            try:
                relative_path = output_path.relative_to(WORKBENCH_DIR)
            except ValueError:
                try:
                    relative_path = output_path.relative_to(WORKBENCH_DIR.parent)
                except ValueError:
                    relative_path = output_path
            if structure_id is not None:
                print(
                    f"{relative_path} is stale; run with --build-structure "
                    f"{structure_id}",
                    file=sys.stderr,
                )
            else:
                print(
                    f"{relative_path} is stale; run with --build",
                    file=sys.stderr,
                )
            return 1
    return 0


def _run_render_mode(args: argparse.Namespace) -> int:
    structure_mode_id = args.build_structure or args.check_structure
    manifest_raw = MANIFEST_PATH.read_bytes()
    inputs = _capture_manifest_input_fingerprint(
        manifest_raw,
        include_map_visual_assets=structure_mode_id is None,
        structure_id_filter=structure_mode_id,
    )
    captured_baseline: dict[Path, bytes | None] | None = None
    if args.build:
        with _map_promotion_lock():
            captured_baseline = _capture_publication_output_baseline(
                structure_id=None,
            )
    elif args.build_structure:
        with _structure_local_build_lock(structure_mode_id):
            captured_baseline = _capture_publication_output_baseline(
                structure_id=structure_mode_id,
            )

    if structure_mode_id:
        package_outputs, _topology_build, manifest_sha = (
            _render_structure_build_candidate(
                manifest_raw,
                structure_mode_id,
            )
        )
        package_outputs = _remap_structure_outputs_to_local_lane(
            package_outputs,
            structure_mode_id,
        )
        if args.check_structure:
            result = _check_expected_outputs(
                package_outputs,
                inputs,
                structure_id=structure_mode_id,
            )
            if result != 0:
                return result
            print(
                f"Structure package {structure_mode_id} outputs are current "
                f"({manifest_sha})"
            )
            return 0
        if captured_baseline is None:
            raise ManifestError("missing pre-render structure publication baseline")
        baseline = _expected_output_baseline(
            package_outputs,
            captured_baseline,
        )
        with _structure_local_build_lock(structure_mode_id):
            _assert_input_fingerprint(inputs)
            _publish_outputs_with_cas(
                package_outputs,
                expected_current=baseline,
                commit_marker=(
                    _structure_local_output_root(structure_mode_id)
                    / "structure.tscn"
                ),
            )
        print(
            f"Built structure package {structure_mode_id} candidate in "
            f"{_structure_local_output_root(structure_mode_id)}"
        )
        return 0

    (
        expected_outputs,
        _topology_build,
        manifest_sha,
        gameplay_signature,
        presentation_fingerprint,
    ) = _render_build_candidate(manifest_raw)
    if args.check:
        result = _check_expected_outputs(
            expected_outputs,
            inputs,
            structure_id=None,
        )
        if result != 0:
            return result
        print(
            "UnderwaterMap.tscn and generated L05 outputs are current "
            f"({manifest_sha}, {gameplay_signature}, {presentation_fingerprint})"
        )
        return 0
    if captured_baseline is None:
        raise ManifestError("missing pre-render map publication baseline")
    baseline = _expected_output_baseline(
        expected_outputs,
        captured_baseline,
    )
    with _map_promotion_lock():
        _assert_input_fingerprint(inputs)
        _publish_outputs_with_cas(
            expected_outputs,
            expected_current=baseline,
            commit_marker=SCENE_PATH,
        )
    print(
        f"Built {SCENE_PATH} from {MANIFEST_PATH} "
        f"({manifest_sha}, {gameplay_signature}, {presentation_fingerprint})"
    )
    return 0


def _assert_builder_eol_preflight(args: argparse.Namespace) -> None:
    project_root = WORKBENCH_DIR.parent.resolve()
    try:
        git_root = repository_root(project_root)
    except ContractError as git_error:
        structure_id = args.build_structure or args.check_structure
        proof_path = os.environ.get(ISOLATED_EOL_PROOF_PATH_ENV, "")
        proof_key = os.environ.get(ISOLATED_EOL_PROOF_KEY_ENV, "")
        if not structure_id or not proof_path or not proof_key:
            raise ManifestError(f"tracked EOL preflight failed: {git_error}") from git_error
        try:
            proof = verify_isolated_eol_proof(
                project_root,
                proof_path=proof_path,
                structure_id=structure_id,
                secret_hex=proof_key,
            )
        except ContractError as proof_error:
            raise ManifestError(
                f"isolated tracked EOL proof failed: {proof_error}"
            ) from proof_error
        print(
            "Verified isolated tracked EOL proof "
            f"({proof['source_snapshot_sha256']}, {structure_id})"
        )
        return
    if git_root.resolve() != project_root:
        raise ManifestError(
            "tracked EOL preflight failed: builder project root is nested inside "
            f"a different Git worktree ({git_root})"
        )
    try:
        assert_tracked_lf_eol(git_root)
    except ContractError as error:
        raise ManifestError(f"tracked EOL preflight failed: {error}") from error


def main() -> int:
    args = _parse_args()
    try:
        _assert_builder_eol_preflight(args)
        if args.seal_structure_package:
            _seal_structure_package(args.seal_structure_package)
            return 0
        if args.refresh_l05_source:
            _refresh_l05_source()
            return 0
        if args.refresh_structure_package:
            if not args.sealed_package_sha256:
                raise ManifestError(
                    "--refresh-structure-package requires "
                    "--sealed-package-sha256 from an immutable/FROZEN hand-off"
                )
            structure_ids = (
                [args.refresh_structure_package]
                if isinstance(args.refresh_structure_package, str)
                else list(args.refresh_structure_package)
            )
            sealed_hashes = (
                [args.sealed_package_sha256]
                if isinstance(args.sealed_package_sha256, str)
                else list(args.sealed_package_sha256)
            )
            if len(structure_ids) != len(sealed_hashes):
                raise ManifestError(
                    "every --refresh-structure-package requires exactly one "
                    "--sealed-package-sha256 in the same order"
                )
            _refresh_structure_packages(
                list(zip(structure_ids, sealed_hashes, strict=True)),
                full_manifest_validation=len(structure_ids) > 1,
            )
            return 0
        if args.sealed_package_sha256:
            raise ManifestError(
                "--sealed-package-sha256 is valid only with "
                "--refresh-structure-package"
            )
        return _run_render_mode(args)
    except WorkspaceLockError as error:
        print(f"underwater map publication is busy: {error}", file=sys.stderr)
        return 2
    except (OSError, ManifestError) as error:
        print(f"underwater map manifest error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
