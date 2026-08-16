#!/usr/bin/env python3
"""Build the derived full-map authoring guide for UnderwaterMap.

The guide is presentation-only.  ``UnderwaterMap.tscn`` remains the authority
for regions and landmarks, while the terrain raster remains a generated view of
the canonical Polygon2D geometry.  The generator deliberately parses those
sources on every run so the guide cannot become a second hand-maintained map.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import re
from pathlib import Path
from typing import Any, Iterable

from PIL import Image, ImageDraw


PROJECT_ROOT = Path(__file__).resolve().parents[1]
GENERATOR_PATH = Path(__file__).resolve()
MAP_SCENE_PATH = PROJECT_ROOT / "scenes/diving/UnderwaterMap.tscn"
MAP_SCRIPT_PATH = PROJECT_ROOT / "scripts/diving/UnderwaterMapScene.gd"
REGION_SCENE_PATH = PROJECT_ROOT / "scenes/diving/map_objects/MapRegion.tscn"
DIVER_SCENE_PATH = PROJECT_ROOT / "scenes/diving/Diver.tscn"
PROJECT_CONFIG_PATH = PROJECT_ROOT / "project.godot"
TERRAIN_PATH = (
    PROJECT_ROOT / "assets/diving/world/map_v2/world_collision_grid.png"
)
TERRAIN_MANIFEST_PATH = TERRAIN_PATH.with_suffix(".json")
DEFAULT_OUTPUT = (
    PROJECT_ROOT
    / "assets/diving/world/layout_guides/full_map/underwater_map_layout_guide_v1.png"
)
DEFAULT_MANIFEST = DEFAULT_OUTPUT.with_suffix(".json")

GENERATOR_VERSION = 2
SCHEMA_VERSION = 2
ASSET_ID = "underwater_map_layout_guide_v1"
WORLD_SIZE = (11_520.0, 6_480.0)
PIXELS_PER_WORLD_UNIT = 3.0 / 8.0
GUIDE_SIZE = (4_320, 2_430)
EXPECTED_REGION_COUNT = 4
EXPECTED_LANDMARK_COUNT = 28

PIXEL_FONT_VERSION = 1
PIXEL_FONT_ROWS = 9
PIXEL_FONT_COLUMNS = 5
PIXEL_FONT_ADVANCE = 6
PIXEL_GLYPHS_7 = {
    " ": ("00000", "00000", "00000", "00000", "00000", "00000", "00000"),
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
    "C": ("01111", "10000", "10000", "10000", "10000", "10000", "01111"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "G": ("01111", "10000", "10000", "10111", "10001", "10001", "01111"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
    "I": ("11111", "00100", "00100", "00100", "00100", "00100", "11111"),
    "J": ("00111", "00010", "00010", "00010", "00010", "10010", "01100"),
    "K": ("10001", "10010", "10100", "11000", "10100", "10010", "10001"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "Q": ("01110", "10001", "10001", "10001", "10101", "10010", "01101"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
    "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
    "W": ("10001", "10001", "10001", "10101", "10101", "11011", "10001"),
    "X": ("10001", "10001", "01010", "00100", "01010", "10001", "10001"),
    "Y": ("10001", "10001", "01010", "00100", "00100", "00100", "00100"),
    "Z": ("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
    "3": ("11110", "00001", "00001", "01110", "00001", "00001", "11110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "10000", "11110", "00001", "00001", "11110"),
    "6": ("01110", "10000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00001", "01110"),
    "-": ("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
    ":": ("00000", "00100", "00100", "00000", "00100", "00100", "00000"),
    ".": ("00000", "00000", "00000", "00000", "00000", "00110", "00110"),
    ",": ("00000", "00000", "00000", "00000", "00110", "00110", "00100"),
    "/": ("00001", "00010", "00010", "00100", "01000", "01000", "10000"),
    "%": ("11001", "11010", "00100", "01000", "10110", "00110", "00000"),
    "|": ("00100", "00100", "00100", "00100", "00100", "00100", "00100"),
    "?": ("01110", "10001", "00001", "00010", "00100", "00000", "00100"),
}
PIXEL_ACUTE_BASES = {"Ć": "C", "Ń": "N", "Ó": "O", "Ś": "S", "Ź": "Z"}
PIXEL_OGONEK_BASES = {"Ą": "A", "Ę": "E"}

NODE_BLOCK_RE = re.compile(
    r'^\[node name="(?P<name>[^"]+)"(?P<header>[^\]]*)\]\r?\n'
    r"(?P<body>.*?)(?=^\[node |\Z)",
    re.MULTILINE | re.DOTALL,
)


class GuideError(RuntimeError):
    """Raised when an authority source cannot satisfy the guide contract."""


def _pixel_glyph(character: str) -> tuple[str, ...]:
    if character == "Ł":
        body = ("10000", "10010", "10100", "11000", "10000", "10000", "11111")
        return ("00000", *body, "00000")
    if character == "Ż":
        return ("00100", *PIXEL_GLYPHS_7["Z"], "00000")
    if character in PIXEL_ACUTE_BASES:
        return ("00010", *PIXEL_GLYPHS_7[PIXEL_ACUTE_BASES[character]], "00000")
    if character in PIXEL_OGONEK_BASES:
        return ("00000", *PIXEL_GLYPHS_7[PIXEL_OGONEK_BASES[character]], "00010")
    body = PIXEL_GLYPHS_7.get(character, PIXEL_GLYPHS_7["?"])
    return ("00000", *body, "00000")


def _normalized_pixel_text(text: str) -> str:
    return text.upper().replace("•", "|").replace("×", "X")


class PixelFont:
    """Small generator-embedded bitmap font with no host font dependency."""

    def __init__(self, scale: int) -> None:
        if scale <= 0:
            raise ValueError("Pixel font scale must be positive.")
        self.scale = scale

    @property
    def height(self) -> int:
        return PIXEL_FONT_ROWS * self.scale

    def measure(self, text: str) -> tuple[int, int]:
        normalized = _normalized_pixel_text(text)
        if not normalized:
            return 0, self.height
        width = (
            len(normalized) * PIXEL_FONT_ADVANCE - 1
        ) * self.scale
        return width, self.height


def _draw_pixel_text(
    draw: ImageDraw.ImageDraw,
    point: tuple[float, float],
    text: str,
    font: PixelFont,
    fill: tuple[int, int, int, int],
    shadow_fill: tuple[int, int, int, int] | None = None,
    shadow_offset: int = 2,
) -> None:
    normalized = _normalized_pixel_text(text)

    def draw_pass(offset_x: int, offset_y: int, color: tuple[int, int, int, int]) -> None:
        origin_x = round(point[0]) + offset_x
        origin_y = round(point[1]) + offset_y
        for index, character in enumerate(normalized):
            glyph_x = origin_x + index * PIXEL_FONT_ADVANCE * font.scale
            for row, bits in enumerate(_pixel_glyph(character)):
                for column, bit in enumerate(bits):
                    if bit != "1":
                        continue
                    left = glyph_x + column * font.scale
                    top = origin_y + row * font.scale
                    draw.rectangle(
                        (
                            left,
                            top,
                            left + font.scale - 1,
                            top + font.scale - 1,
                        ),
                        fill=color,
                    )

    if shadow_fill is not None:
        draw_pass(shadow_offset, shadow_offset, shadow_fill)
    draw_pass(0, 0, fill)


def _embedded_font_record() -> dict[str, Any]:
    supported = sorted(
        set(PIXEL_GLYPHS_7)
        | set(PIXEL_ACUTE_BASES)
        | set(PIXEL_OGONEK_BASES)
        | {"Ł", "Ż"}
    )
    glyphs = {character: list(_pixel_glyph(character)) for character in supported}
    payload = json.dumps(glyphs, ensure_ascii=False, sort_keys=True).encode("utf-8")
    return {
        "family": "Ostatni Pomost embedded 5x9 pixel font",
        "glyph_sha256": _sha256_bytes(payload),
        "provenance": "glyphs_embedded_in_generator",
        "version": PIXEL_FONT_VERSION,
    }


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _res_path(path: Path) -> str:
    return "res://" + path.resolve().relative_to(PROJECT_ROOT).as_posix()


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def _load_json(path: Path) -> dict[str, Any]:
    parsed = json.loads(_read_text(path))
    if not isinstance(parsed, dict):
        raise GuideError(f"JSON root must be an object: {path}")
    return parsed


def _property(body: str, key: str) -> str | None:
    match = re.search(rf"^{re.escape(key)} = (?P<value>.+)$", body, re.MULTILINE)
    return match.group("value").strip() if match else None


def _quoted(body: str, key: str, required: bool = True) -> str:
    value = _property(body, key)
    if value is None:
        if required:
            raise GuideError(f"Missing property {key}.")
        return ""
    match = re.fullmatch(r'"(?P<value>.*)"', value)
    if not match:
        raise GuideError(f"Property {key} is not a quoted string: {value}")
    return match.group("value")


def _numbers(value: str, constructor: str, count: int) -> tuple[float, ...]:
    match = re.fullmatch(rf"{constructor}\((?P<values>[^)]+)\)", value)
    if not match:
        raise GuideError(f"Expected {constructor}(...), got: {value}")
    parts = [part.strip() for part in match.group("values").split(",")]
    if len(parts) != count:
        raise GuideError(f"Expected {count} values in {value}.")
    return tuple(float(part) for part in parts)


def _vector2(body: str, key: str, required: bool = True) -> tuple[float, float] | None:
    value = _property(body, key)
    if value is None:
        if required:
            raise GuideError(f"Missing property {key}.")
        return None
    x, y = _numbers(value, "Vector2", 2)
    return x, y


def _color(body: str, key: str) -> tuple[float, float, float, float]:
    value = _property(body, key)
    if value is None:
        raise GuideError(f"Missing property {key}.")
    red, green, blue, alpha = _numbers(value, "Color", 4)
    return red, green, blue, alpha


def _node_blocks(scene_text: str, parent: str) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    parent_token = f'parent="{parent}"'
    for match in NODE_BLOCK_RE.finditer(scene_text):
        header = match.group("header")
        if parent_token not in header:
            continue
        result.append(
            {
                "name": match.group("name"),
                "header": header,
                "body": match.group("body"),
            }
        )
    return result


def _round_float(value: float) -> float:
    return round(float(value), 6)


def _bounds(center: tuple[float, float], size: tuple[float, float]) -> list[float]:
    return [
        _round_float(center[0] - size[0] * 0.5),
        _round_float(center[1] - size[1] * 0.5),
        _round_float(size[0]),
        _round_float(size[1]),
    ]


def _region_defaults() -> tuple[float, float]:
    text = _read_text(REGION_SCENE_PATH)
    blocks = list(NODE_BLOCK_RE.finditer(text))
    if not blocks:
        raise GuideError("MapRegion.tscn has no root node.")
    value = _vector2(blocks[0].group("body"), "depth_range")
    if value is None:
        raise GuideError("MapRegion.tscn has no default depth_range.")
    return value


def _parse_regions(scene_text: str) -> list[dict[str, Any]]:
    default_depth = _region_defaults()
    regions: list[dict[str, Any]] = []
    for block in _node_blocks(scene_text, "DepthRegions"):
        body = block["body"]
        center = _vector2(body, "position")
        size = _vector2(body, "bounds_size")
        depth = _vector2(body, "depth_range", required=False) or default_depth
        accent = _color(body, "accent_color")
        assert center is not None and size is not None
        regions.append(
            {
                "accent_color_rgba": [_round_float(value) for value in accent],
                "bounds": _bounds(center, size),
                "center": [_round_float(value) for value in center],
                "depth_range": [_round_float(value) for value in depth],
                "id": _quoted(body, "object_id"),
                "name": _quoted(body, "display_name"),
                "size": [_round_float(value) for value in size],
                "source_node_path": f"DepthRegions/{block['name']}",
            }
        )
    regions.sort(key=lambda region: str(region["id"]))
    if len(regions) != EXPECTED_REGION_COUNT:
        raise GuideError(
            f"Expected {EXPECTED_REGION_COUNT} regions, found {len(regions)}."
        )
    if [region["id"] for region in regions] != ["R1", "R2", "R3", "R4"]:
        raise GuideError("DepthRegions must contain R1, R2, R3 and R4 exactly.")
    return regions


def _axis_camera_frames(
    coordinate: float, world_extent: float, visible_extent: float
) -> list[int]:
    count = math.ceil(world_extent / visible_extent)
    starts = [
        min(index * visible_extent, world_extent - visible_extent)
        for index in range(count)
    ]
    frames: list[int] = []
    for index, start in enumerate(starts):
        end = start + visible_extent
        inside = start <= coordinate < end
        if index == count - 1 and math.isclose(coordinate, world_extent):
            inside = True
        if inside:
            frames.append(index + 1)
    return frames


def _camera_cells(
    position: tuple[float, float], visible_size: tuple[float, float]
) -> list[list[int]]:
    columns = _axis_camera_frames(position[0], WORLD_SIZE[0], visible_size[0])
    rows = _axis_camera_frames(position[1], WORLD_SIZE[1], visible_size[1])
    return [[column, row] for row in rows for column in columns]


def _parse_landmarks(
    scene_text: str, visible_size: tuple[float, float]
) -> list[dict[str, Any]]:
    landmarks: list[dict[str, Any]] = []
    for block in _node_blocks(scene_text, "Landmarks"):
        body = block["body"]
        center = _vector2(body, "position")
        size = _vector2(body, "bounds_size")
        assert center is not None and size is not None
        landmarks.append(
            {
                "bounds": _bounds(center, size),
                "camera_cells": _camera_cells(center, visible_size),
                "id": _quoted(body, "object_id"),
                "kind": _quoted(body, "visual_kind"),
                "name": _quoted(body, "display_name"),
                "position": [_round_float(value) for value in center],
                "region_id": _quoted(body, "region_id"),
                "role": _quoted(body, "landmark_role"),
                "size": [_round_float(value) for value in size],
                "source_node_path": f"Landmarks/{block['name']}",
            }
        )
    landmarks.sort(key=lambda landmark: str(landmark["id"]))
    if len(landmarks) != EXPECTED_LANDMARK_COUNT:
        raise GuideError(
            f"Expected {EXPECTED_LANDMARK_COUNT} landmarks, found {len(landmarks)}."
        )
    ids = [str(landmark["id"]) for landmark in landmarks]
    if len(set(ids)) != len(ids):
        raise GuideError("Landmark IDs are not unique.")
    for landmark in landmarks:
        x, y = landmark["position"]
        if not (0.0 <= x <= WORLD_SIZE[0] and 0.0 <= y <= WORLD_SIZE[1]):
            raise GuideError(f"Landmark outside world bounds: {landmark['id']}")
    return landmarks


def _parse_project_viewport() -> tuple[int, int]:
    text = _read_text(PROJECT_CONFIG_PATH)
    width_match = re.search(
        r"^window/size/viewport_width=(\d+)$", text, re.MULTILINE
    )
    height_match = re.search(
        r"^window/size/viewport_height=(\d+)$", text, re.MULTILINE
    )
    if not width_match or not height_match:
        raise GuideError("project.godot has no viewport_width/viewport_height.")
    return int(width_match.group(1)), int(height_match.group(1))


def _parse_camera_zoom() -> tuple[float, float]:
    text = _read_text(DIVER_SCENE_PATH)
    camera_match = re.search(
        r'(?ms)^\[node name="Camera2D"[^\]]*\]\r?\n(?P<body>.*?)(?=^\[node |\Z)',
        text,
    )
    if not camera_match:
        raise GuideError("Diver.tscn has no Camera2D node.")
    zoom = _vector2(camera_match.group("body"), "zoom")
    if zoom is None or zoom[0] <= 0.0 or zoom[1] <= 0.0:
        raise GuideError("Production camera zoom must be positive.")
    return zoom


def _source_record(path: Path) -> dict[str, Any]:
    return {
        "path": _res_path(path),
        "sha256": _sha256(path),
        "size_bytes": path.stat().st_size,
    }


def _camera_contract() -> dict[str, Any]:
    viewport = _parse_project_viewport()
    zoom = _parse_camera_zoom()
    visible = (viewport[0] / zoom[0], viewport[1] / zoom[1])
    columns = math.ceil(WORLD_SIZE[0] / visible[0])
    rows = math.ceil(WORLD_SIZE[1] / visible[1])
    column_starts = [
        min(column * visible[0], WORLD_SIZE[0] - visible[0])
        for column in range(columns)
    ]
    row_starts = [
        min(row * visible[1], WORLD_SIZE[1] - visible[1])
        for row in range(rows)
    ]
    unique_column_widths = [
        visible[0]
        if column < columns - 1
        else WORLD_SIZE[0] - (columns - 1) * visible[0]
        for column in range(columns)
    ]
    unique_row_heights = [
        visible[1]
        if row < rows - 1
        else WORLD_SIZE[1] - (rows - 1) * visible[1]
        for row in range(rows)
    ]
    cells: list[dict[str, Any]] = []
    for row, y in enumerate(row_starts):
        for column, x in enumerate(column_starts):
            cells.append(
                {
                    "bounds": [
                        _round_float(x),
                        _round_float(y),
                        _round_float(visible[0]),
                        _round_float(visible[1]),
                    ],
                    "column": column + 1,
                    "frame_fraction": 1.0,
                    "new_world_coverage_fraction": _round_float(
                        (unique_column_widths[column] * unique_row_heights[row])
                        / (visible[0] * visible[1])
                    ),
                    "guide_bounds": [
                        round(x * PIXELS_PER_WORLD_UNIT),
                        round(y * PIXELS_PER_WORLD_UNIT),
                        round(visible[0] * PIXELS_PER_WORLD_UNIT),
                        round(visible[1] * PIXELS_PER_WORLD_UNIT),
                    ],
                    "id": f"C{column + 1:02d}-R{row + 1:02d}",
                    "row": row + 1,
                }
            )
    return {
        "base_viewport": list(viewport),
        "camera_center_limits": {
            "maximum": [
                _round_float(WORLD_SIZE[0] - visible[0] * 0.5),
                _round_float(WORLD_SIZE[1] - visible[1] * 0.5),
            ],
            "minimum": [
                _round_float(visible[0] * 0.5),
                _round_float(visible[1] * 0.5),
            ],
        },
        "cells": cells,
        "column_frames": [
            {
                "column": column + 1,
                "guide_bounds": [
                    round(x * PIXELS_PER_WORLD_UNIT),
                    0,
                    round(visible[0] * PIXELS_PER_WORLD_UNIT),
                    GUIDE_SIZE[1],
                ],
                "world_bounds": [
                    _round_float(x),
                    0.0,
                    _round_float(visible[0]),
                    _round_float(WORLD_SIZE[1]),
                ],
            }
            for column, x in enumerate(column_starts)
        ],
        "columns": columns,
        "coverage_mode": "full_camera_frames_edge_clamped_with_final_overlap",
        "full_guide_frame_size": [
            round(visible[0] * PIXELS_PER_WORLD_UNIT),
            round(visible[1] * PIXELS_PER_WORLD_UNIT),
        ],
        "full_screen_area_equivalent": _round_float(
            (WORLD_SIZE[0] * WORLD_SIZE[1]) / (visible[0] * visible[1])
        ),
        "last_column": {
            "frame_fraction": 1.0,
            "guide_start_x": round(column_starts[-1] * PIXELS_PER_WORLD_UNIT),
            "new_world_coverage_fraction": _round_float(
                unique_column_widths[-1] / visible[0]
            ),
            "overlap_fraction": _round_float(
                1.0 - unique_column_widths[-1] / visible[0]
            ),
            "overlap_guide_width": round(
                (visible[0] - unique_column_widths[-1]) * PIXELS_PER_WORLD_UNIT
            ),
            "overlap_world_width": _round_float(
                visible[0] - unique_column_widths[-1]
            ),
            "world_start_x": _round_float(column_starts[-1]),
        },
        "last_row": {
            "frame_fraction": 1.0,
            "guide_start_y": round(row_starts[-1] * PIXELS_PER_WORLD_UNIT),
            "new_world_coverage_fraction": _round_float(
                unique_row_heights[-1] / visible[1]
            ),
            "overlap_fraction": _round_float(
                1.0 - unique_row_heights[-1] / visible[1]
            ),
            "overlap_guide_height": round(
                (visible[1] - unique_row_heights[-1]) * PIXELS_PER_WORLD_UNIT
            ),
            "overlap_world_height": _round_float(
                visible[1] - unique_row_heights[-1]
            ),
            "world_start_y": _round_float(row_starts[-1]),
        },
        "raw_full_hd_reference_grid": [6, 6],
        "row_frames": [
            {
                "guide_bounds": [
                    0,
                    round(y * PIXELS_PER_WORLD_UNIT),
                    GUIDE_SIZE[0],
                    round(visible[1] * PIXELS_PER_WORLD_UNIT),
                ],
                "row": row + 1,
                "world_bounds": [
                    0.0,
                    _round_float(y),
                    _round_float(WORLD_SIZE[0]),
                    _round_float(visible[1]),
                ],
            }
            for row, y in enumerate(row_starts)
        ],
        "rows": rows,
        "visible_world_size": [_round_float(value) for value in visible],
        "zoom": [_round_float(value) for value in zoom],
    }


def _to_rgba(color: Iterable[float], alpha: int) -> tuple[int, int, int, int]:
    red, green, blue, _source_alpha = list(color)
    return (
        round(max(0.0, min(1.0, red)) * 255),
        round(max(0.0, min(1.0, green)) * 255),
        round(max(0.0, min(1.0, blue)) * 255),
        alpha,
    )


def _intersection_area(
    first: tuple[int, int, int, int], second: tuple[int, int, int, int]
) -> int:
    width = max(0, min(first[2], second[2]) - max(first[0], second[0]))
    height = max(0, min(first[3], second[3]) - max(first[1], second[1]))
    return width * height


def _label_box(
    text: str,
    font: PixelFont,
    point: tuple[int, int],
    occupied: list[tuple[int, int, int, int]],
) -> tuple[int, int, int, int]:
    text_width, text_height = font.measure(text)
    width = text_width + 18
    height = text_height + 14
    x, y = point
    candidates = [
        (x + 18, y - height - 12),
        (x + 18, y + 12),
        (x - width - 18, y - height - 12),
        (x - width - 18, y + 12),
        (x - width // 2, y - height - 24),
        (x - width // 2, y + 24),
    ]
    best_box: tuple[int, int, int, int] | None = None
    best_penalty: int | None = None
    for left, top in candidates:
        box = (left, top, left + width, top + height)
        outside = (
            max(0, -box[0])
            + max(0, -box[1])
            + max(0, box[2] - GUIDE_SIZE[0])
            + max(0, box[3] - GUIDE_SIZE[1])
        )
        overlap = sum(_intersection_area(box, other) for other in occupied)
        penalty = outside * 100_000 + overlap * 100
        if best_penalty is None or penalty < best_penalty:
            best_box = box
            best_penalty = penalty
    assert best_box is not None
    left = min(max(2, best_box[0]), GUIDE_SIZE[0] - width - 2)
    top = min(max(2, best_box[1]), GUIDE_SIZE[1] - height - 2)
    return left, top, left + width, top + height


def _draw_text_box(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    text: str,
    font: PixelFont,
    outline: tuple[int, int, int, int],
) -> None:
    draw.rounded_rectangle(
        box,
        radius=7,
        fill=(4, 13, 21, 224),
        outline=outline,
        width=2,
    )
    _, text_height = font.measure(text)
    _draw_pixel_text(
        draw,
        (box[0] + 9, box[1] + (box[3] - box[1] - text_height) * 0.5),
        text,
        font,
        fill=(239, 248, 250, 255),
    )


def _render_guide(
    regions: list[dict[str, Any]],
    landmarks: list[dict[str, Any]],
    camera: dict[str, Any],
) -> bytes:
    with Image.open(TERRAIN_PATH) as terrain_source:
        terrain = terrain_source.convert("L")
    if terrain.size != (1_440, 810):
        raise GuideError(f"Terrain grid must be 1440x810, got {terrain.size}.")
    mask = terrain.resize(GUIDE_SIZE, Image.Resampling.NEAREST)
    blocked = Image.new("RGBA", GUIDE_SIZE, (5, 17, 27, 255))
    open_water = Image.new("RGBA", GUIDE_SIZE, (18, 68, 88, 255))
    image = Image.composite(open_water, blocked, mask)

    overlay = Image.new("RGBA", GUIDE_SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")
    region_colors: dict[str, tuple[int, int, int, int]] = {}
    region_font = PixelFont(scale=4)
    grid_font = PixelFont(scale=2)
    label_font = PixelFont(scale=3)
    legend_font = PixelFont(scale=3)
    region_label_boxes: list[tuple[int, int, int, int]] = []

    for region in regions:
        color = _to_rgba(region["accent_color_rgba"], 255)
        region_colors[str(region["id"])] = color
        left, top, width, height = region["bounds"]
        box = (
            round(left * PIXELS_PER_WORLD_UNIT),
            round(top * PIXELS_PER_WORLD_UNIT),
            round((left + width) * PIXELS_PER_WORLD_UNIT),
            round((top + height) * PIXELS_PER_WORLD_UNIT),
        )
        draw.rectangle(box, fill=(*color[:3], 31), outline=(*color[:3], 205), width=4)
        region_label = f"{region['id']}  {region['name']}"
        label_y = min(
            GUIDE_SIZE[1] - 64,
            max(12, round((box[1] + box[3]) * 0.5) - 28),
        )
        text_width, text_height = region_font.measure(region_label)
        region_box = (
            30,
            label_y,
            30 + text_width + 24,
            label_y + text_height + 20,
        )
        _draw_text_box(draw, region_box, region_label, region_font, (*color[:3], 220))
        region_label_boxes.append(region_box)

    overlap_x = camera["last_column"]["guide_start_x"]
    overlap_x_end = overlap_x + camera["last_column"]["overlap_guide_width"]
    overlap_y = camera["last_row"]["guide_start_y"]
    overlap_y_end = overlap_y + camera["last_row"]["overlap_guide_height"]
    draw.rectangle(
        (overlap_x, 0, overlap_x_end, GUIDE_SIZE[1]),
        fill=(255, 197, 82, 21),
    )
    draw.rectangle(
        (0, overlap_y, GUIDE_SIZE[0], overlap_y_end),
        fill=(255, 197, 82, 21),
    )
    vertical_edges = sorted(
        {
            frame["guide_bounds"][0]
            for frame in camera["column_frames"]
        }
        | {
            frame["guide_bounds"][0] + frame["guide_bounds"][2]
            for frame in camera["column_frames"]
        }
    )
    horizontal_edges = sorted(
        {
            frame["guide_bounds"][1]
            for frame in camera["row_frames"]
        }
        | {
            frame["guide_bounds"][1] + frame["guide_bounds"][3]
            for frame in camera["row_frames"]
        }
    )
    for x in vertical_edges[1:-1]:
        draw.line((x, 0, x, GUIDE_SIZE[1]), fill=(214, 238, 243, 155), width=3)
    for y in horizontal_edges[1:-1]:
        draw.line((0, y, GUIDE_SIZE[0], y), fill=(214, 238, 243, 155), width=3)
    draw.rectangle(
        (1, 1, GUIDE_SIZE[0] - 2, GUIDE_SIZE[1] - 2),
        outline=(234, 248, 250, 230),
        width=6,
    )

    for frame in camera["column_frames"]:
        left = frame["guide_bounds"][0]
        right = left + frame["guide_bounds"][2]
        label = f"C{frame['column']:02d}"
        text_width, _ = grid_font.measure(label)
        _draw_pixel_text(
            draw,
            ((left + right - text_width) * 0.5, 8),
            label,
            grid_font,
            fill=(231, 245, 248, 230),
            shadow_fill=(3, 11, 18, 220),
        )
    for frame in camera["row_frames"]:
        top = frame["guide_bounds"][1]
        bottom = top + frame["guide_bounds"][3]
        label = f"R{frame['row']:02d}"
        _, text_height = grid_font.measure(label)
        _draw_pixel_text(
            draw,
            (8, (top + bottom - text_height) * 0.5),
            label,
            grid_font,
            fill=(231, 245, 248, 230),
            shadow_fill=(3, 11, 18, 220),
        )

    occupied: list[tuple[int, int, int, int]] = region_label_boxes.copy()
    for landmark in sorted(landmarks, key=lambda item: (item["position"][1], item["position"][0])):
        color = region_colors[str(landmark["region_id"])]
        left, top, width, height = landmark["bounds"]
        bounds_box = (
            round(left * PIXELS_PER_WORLD_UNIT),
            round(top * PIXELS_PER_WORLD_UNIT),
            round((left + width) * PIXELS_PER_WORLD_UNIT),
            round((top + height) * PIXELS_PER_WORLD_UNIT),
        )
        draw.rectangle(bounds_box, outline=(*color[:3], 165), width=3)

        point = (
            round(landmark["position"][0] * PIXELS_PER_WORLD_UNIT),
            round(landmark["position"][1] * PIXELS_PER_WORLD_UNIT),
        )
        label = f"{landmark['id']}  {landmark['name']}"
        box = _label_box(label, label_font, point, occupied)
        occupied.append(box)
        nearest_x = min(max(point[0], box[0]), box[2])
        nearest_y = min(max(point[1], box[1]), box[3])
        draw.line(
            (point[0], point[1], nearest_x, nearest_y),
            fill=(*color[:3], 210),
            width=3,
        )
        _draw_text_box(draw, box, label, label_font, (*color[:3], 225))
        draw.ellipse(
            (point[0] - 12, point[1] - 12, point[0] + 12, point[1] + 12),
            fill=(*color[:3], 255),
            outline=(244, 250, 252, 255),
            width=4,
        )

    legend_lines = [
        "KAMERA 1.20 | PELNY KADR 400X225 PX | SIATKA 11X11",
        "JASNE: OTWARTA WODA | PROSTOKATY: LANDMARKI | ZOLTY: 20% ZAKLADKI",
    ]
    legend_width = max(
        legend_font.measure(line)[0] for line in legend_lines
    ) + 34
    legend_height = 96
    legend_box = (
        30,
        GUIDE_SIZE[1] - legend_height - 30,
        30 + legend_width,
        GUIDE_SIZE[1] - 30,
    )
    draw.rounded_rectangle(
        legend_box,
        radius=9,
        fill=(4, 13, 21, 230),
        outline=(225, 242, 246, 205),
        width=2,
    )
    for index, line in enumerate(legend_lines):
        _draw_pixel_text(
            draw,
            (legend_box[0] + 17, legend_box[1] + 13 + index * 40),
            line,
            legend_font,
            fill=(238, 248, 250, 255),
        )

    image = Image.alpha_composite(image, overlay)
    output = io.BytesIO()
    image.save(output, format="PNG", compress_level=9, optimize=False)
    return output.getvalue()


def _png_pixel_sha256(png_bytes: bytes) -> str:
    try:
        with Image.open(io.BytesIO(png_bytes)) as source:
            if source.format != "PNG":
                raise GuideError("Guide output is not a PNG image.")
            rgba = source.convert("RGBA")
    except GuideError:
        raise
    except Exception as error:
        raise GuideError(f"Guide output cannot be decoded: {error}") from error
    if rgba.size != GUIDE_SIZE:
        raise GuideError(f"Guide output must be {GUIDE_SIZE}, got {rgba.size}.")
    prefix = f"RGBA:{rgba.width}x{rgba.height}\0".encode("ascii")
    return _sha256_bytes(prefix + rgba.tobytes())


def _manifest(
    output_path: Path,
    png_bytes: bytes,
    regions: list[dict[str, Any]],
    landmarks: list[dict[str, Any]],
    camera: dict[str, Any],
) -> dict[str, Any]:
    terrain_manifest = _load_json(TERRAIN_MANIFEST_PATH)
    scene_text = _read_text(MAP_SCENE_PATH)
    navigation_cells_match = re.search(
        r'^navigation_cells_sha256 = "([0-9a-f]{64})"$', scene_text, re.MULTILINE
    )
    navigation_signature_match = re.search(
        r'^navigation_signature_sha256 = "([0-9a-f]{64})"$',
        scene_text,
        re.MULTILINE,
    )
    if not navigation_cells_match or not navigation_signature_match:
        raise GuideError("Map scene has no valid navigation hashes.")
    return {
        "asset_id": ASSET_ID,
        "authority": {
            "contract": "presentation_only_derived_authoring_guide",
            "map_scene": _source_record(MAP_SCENE_PATH),
            "map_script": _source_record(MAP_SCRIPT_PATH),
            "note": "UnderwaterMap.tscn remains the sole authority for topology, regions and landmarks.",
        },
        "camera_grid": camera,
        "generator": {
            "font": _embedded_font_record(),
            "model": "not_applicable",
            "path": _res_path(GENERATOR_PATH),
            "seed": "not_applicable",
            "sha256": _sha256(GENERATOR_PATH),
            "version": GENERATOR_VERSION,
        },
        "guide_size": list(GUIDE_SIZE),
        "landmark_count": len(landmarks),
        "landmarks": landmarks,
        "map_gameplay_identity": {
            "map_gameplay_signature": {
                "availability": "runtime_compiled_not_serialized_in_authority_scene",
                "value": None,
            },
            "navigation_cells_sha256": navigation_cells_match.group(1),
            "navigation_signature_sha256": navigation_signature_match.group(1),
        },
        "operations": [
            "parse current authored region and landmark nodes from UnderwaterMap.tscn",
            "nearest-neighbor scale the 8-unit terrain grid by 3x",
            "overlay authored region bounds including overlaps",
            "overlay full production-camera frames with the final row and column clamped to world edges",
            "overlay 28 semantic landmark positions and authored bounds",
            "draw labels with the generator-embedded bitmap font",
            "encode RGBA PNG with Pillow compress_level=9 optimize=false",
        ],
        "output": {
            "format": "RGBA PNG",
            "path": _res_path(output_path),
            "pixel_sha256": _png_pixel_sha256(png_bytes),
            "sha256": _sha256_bytes(png_bytes),
            "size_bytes": len(png_bytes),
        },
        "pixels_per_world_unit": PIXELS_PER_WORLD_UNIT,
        "region_count": len(regions),
        "regions": regions,
        "role": "presentation_only_derived_authoring_guide",
        "schema_version": SCHEMA_VERSION,
        "sources": {
            "camera_scene": _source_record(DIVER_SCENE_PATH),
            "project_config": _source_record(PROJECT_CONFIG_PATH),
            "region_scene": _source_record(REGION_SCENE_PATH),
            "terrain_grid": _source_record(TERRAIN_PATH),
            "terrain_manifest": {
                **_source_record(TERRAIN_MANIFEST_PATH),
                "cells_sha256": terrain_manifest.get("cells_sha256"),
                "geometry_sha256": terrain_manifest.get("geometry_sha256"),
                "grid_step": terrain_manifest.get("grid_step"),
                "output_sha256": terrain_manifest.get("output_sha256"),
            },
        },
        "world_size": [_round_float(value) for value in WORLD_SIZE],
    }


def _build_expected(output_path: Path) -> tuple[bytes, str, dict[str, Any]]:
    terrain_manifest = _load_json(TERRAIN_MANIFEST_PATH)
    manifest_world = (
        float(terrain_manifest.get("world_width", 0.0)),
        float(terrain_manifest.get("world_height", 0.0)),
    )
    if manifest_world != WORLD_SIZE:
        raise GuideError(
            f"Terrain manifest world size {manifest_world} does not match {WORLD_SIZE}."
        )
    if _sha256(TERRAIN_PATH) != str(terrain_manifest.get("output_sha256", "")):
        raise GuideError("Terrain grid bytes do not match their manifest hash.")

    camera = _camera_contract()
    visible_size = tuple(float(value) for value in camera["visible_world_size"])
    scene_text = _read_text(MAP_SCENE_PATH)
    regions = _parse_regions(scene_text)
    landmarks = _parse_landmarks(scene_text, visible_size)
    png_bytes = _render_guide(regions, landmarks, camera)
    manifest = _manifest(output_path, png_bytes, regions, landmarks, camera)
    manifest_text = json.dumps(
        manifest, ensure_ascii=False, indent=2, sort_keys=True
    ) + "\n"
    return png_bytes, manifest_text, manifest


def _write_or_check(
    output_path: Path, manifest_path: Path, check: bool
) -> dict[str, Any]:
    png_bytes, manifest_text, manifest = _build_expected(output_path)
    if check:
        if not output_path.is_file():
            raise GuideError(f"Missing generated guide: {output_path}")
        if not manifest_path.is_file():
            raise GuideError(f"Missing generated manifest: {manifest_path}")
        stored_png = output_path.read_bytes()
        stored_manifest = _load_json(manifest_path)
        stored_output = stored_manifest.get("output")
        if not isinstance(stored_output, dict):
            raise GuideError(f"Generated manifest has no output record: {manifest_path}")
        if stored_output.get("sha256") != _sha256_bytes(stored_png):
            raise GuideError(f"Generated guide bytes do not match manifest: {output_path}")
        if stored_output.get("size_bytes") != len(stored_png):
            raise GuideError(f"Generated guide size does not match manifest: {output_path}")
        stored_pixel_sha256 = _png_pixel_sha256(stored_png)
        if stored_output.get("pixel_sha256") != stored_pixel_sha256:
            raise GuideError(f"Generated guide pixels do not match manifest: {output_path}")
        if stored_pixel_sha256 != manifest["output"]["pixel_sha256"]:
            raise GuideError(f"Stale generated guide pixels: {output_path}")
        comparable_expected = json.loads(json.dumps(manifest))
        comparable_expected["output"]["sha256"] = stored_output["sha256"]
        comparable_expected["output"]["size_bytes"] = stored_output["size_bytes"]
        if stored_manifest != comparable_expected:
            raise GuideError(f"Stale generated manifest: {manifest_path}")
        manifest = stored_manifest
    else:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(png_bytes)
        manifest_path.write_text(manifest_text, encoding="utf-8", newline="\n")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    output_path = args.output.resolve()
    manifest_path = args.manifest.resolve()
    manifest = _write_or_check(output_path, manifest_path, args.check)
    print(
        json.dumps(
            {
                "camera_grid": [
                    manifest["camera_grid"]["columns"],
                    manifest["camera_grid"]["rows"],
                ],
                "check": args.check,
                "guide_size": manifest["guide_size"],
                "landmarks": manifest["landmark_count"],
                "manifest": _res_path(manifest_path),
                "output": _res_path(output_path),
                "output_sha256": manifest["output"]["sha256"],
                "regions": manifest["region_count"],
            },
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    try:
        main()
    except GuideError as error:
        raise SystemExit(f"ERROR: {error}") from error
