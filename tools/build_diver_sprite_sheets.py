#!/usr/bin/env python3
"""Normalize generated diver contact sheets into stable Godot sprite sheets.

The ImageGen source sheets contain four animation poses per row, but their
visual cells are not guaranteed to end on an exact mathematical grid.  This
tool isolates the four dominant connected silhouettes in each row, preserves
their antialiased alpha, stabilizes the chest/helmet anchor and writes a strict
4 x 4 atlas with identical 512 x 256 cells.
"""

from __future__ import annotations

import argparse
import json
from collections import deque
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image


CLIP_NAMES = ("idle", "swim", "sprint")
GRID_COLUMNS = 4
GRID_ROWS = 4
FRAME_COUNT = GRID_COLUMNS * GRID_ROWS
COMPONENT_ALPHA = 24
VISIBLE_ALPHA = 32
MIN_COMPONENT_AREA = 24
MIN_MAIN_AREA = 2_000


@dataclass
class IsolatedFrame:
    clip: str
    index: int
    rgba: np.ndarray
    visible_bbox: tuple[int, int, int, int]
    anchor: tuple[float, float]
    torso_height: float


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build normalized 16-frame diver atlases from alpha contact sheets."
    )
    for clip in CLIP_NAMES:
        parser.add_argument(f"--{clip}", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument(
        "--metrics-path",
        type=Path,
        help="Optional JSON metrics path; defaults to OUTPUT_DIR/animation_build_metrics.json.",
    )
    parser.add_argument("--frame-width", type=int, default=512)
    parser.add_argument("--frame-height", type=int, default=256)
    parser.add_argument("--anchor-x", type=int, default=342)
    parser.add_argument("--anchor-y", type=int, default=116)
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def _bbox(mask: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.nonzero(mask)
    if xs.size == 0:
        raise ValueError("empty alpha silhouette")
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def _row_bands(mask: np.ndarray) -> list[tuple[int, int]]:
    row_counts = mask.sum(axis=1)
    active = row_counts > 80
    groups: list[tuple[int, int]] = []
    start: int | None = None
    for y, enabled in enumerate(active.tolist() + [False]):
        if enabled and start is None:
            start = y
        elif not enabled and start is not None:
            groups.append((start, y))
            start = None
    if len(groups) != GRID_ROWS:
        raise ValueError(f"expected four pose rows, found {len(groups)}: {groups}")

    bands: list[tuple[int, int]] = []
    for index, (top, bottom) in enumerate(groups):
        band_top = 0 if index == 0 else (groups[index - 1][1] + top) // 2
        band_bottom = mask.shape[0] if index == GRID_ROWS - 1 else (
            bottom + groups[index + 1][0]
        ) // 2
        bands.append((band_top, band_bottom))
    return bands


def _connected_components(mask: np.ndarray) -> list[np.ndarray]:
    height, width = mask.shape
    visited = np.zeros(mask.shape, dtype=np.bool_)
    components: list[np.ndarray] = []
    for seed_y, seed_x in np.argwhere(mask):
        if visited[seed_y, seed_x]:
            continue
        queue: deque[tuple[int, int]] = deque([(int(seed_y), int(seed_x))])
        visited[seed_y, seed_x] = True
        points: list[tuple[int, int]] = []
        while queue:
            y, x = queue.popleft()
            points.append((y, x))
            for next_y in range(max(0, y - 1), min(height, y + 2)):
                for next_x in range(max(0, x - 1), min(width, x + 2)):
                    if not visited[next_y, next_x] and mask[next_y, next_x]:
                        visited[next_y, next_x] = True
                        queue.append((next_y, next_x))
        if len(points) >= MIN_COMPONENT_AREA:
            components.append(np.asarray(points, dtype=np.int32))
    return components


def _dilate(mask: np.ndarray, radius: int = 2) -> np.ndarray:
    result = mask.copy()
    for _ in range(radius):
        padded = np.pad(result, 1, mode="constant")
        expanded = np.zeros_like(result)
        for y_offset in range(3):
            for x_offset in range(3):
                expanded |= padded[
                    y_offset : y_offset + result.shape[0],
                    x_offset : x_offset + result.shape[1],
                ]
        result = expanded
    return result


def _isolate_row_frames(
    rgba: np.ndarray, band_top: int, band_bottom: int
) -> list[np.ndarray]:
    band = rgba[band_top:band_bottom]
    component_mask = band[:, :, 3] > COMPONENT_ALPHA
    components = _connected_components(component_mask)
    main_components = sorted(components, key=len, reverse=True)[:GRID_COLUMNS]
    if len(main_components) != GRID_COLUMNS or any(
        len(component) < MIN_MAIN_AREA for component in main_components
    ):
        sizes = sorted((len(component) for component in components), reverse=True)
        raise ValueError(f"could not find four dominant diver silhouettes: {sizes[:12]}")

    main_components.sort(key=lambda points: float(points[:, 1].mean()))
    main_centers = np.asarray(
        [(float(points[:, 1].mean()), float(points[:, 0].mean())) for points in main_components]
    )
    assignments: list[list[np.ndarray]] = [[points] for points in main_components]
    main_ids = {id(points) for points in main_components}
    for points in components:
        if id(points) in main_ids:
            continue
        center = np.asarray([float(points[:, 1].mean()), float(points[:, 0].mean())])
        distances = np.square(main_centers - center).sum(axis=1)
        nearest = int(distances.argmin())
        if float(distances[nearest]) <= 180.0**2:
            assignments[nearest].append(points)

    isolated: list[np.ndarray] = []
    for component_group in assignments:
        keep = np.zeros(component_mask.shape, dtype=np.bool_)
        for points in component_group:
            keep[points[:, 0], points[:, 1]] = True
        keep = _dilate(keep, 2)
        frame = band.copy()
        frame[~keep] = 0
        left, top, right, bottom = _bbox(frame[:, :, 3] > 0)
        padding = 4
        left = max(0, left - padding)
        top = max(0, top - padding)
        right = min(frame.shape[1], right + padding)
        bottom = min(frame.shape[0], bottom + padding)
        isolated.append(frame[top:bottom, left:right])
    return isolated


def _frame_metrics(clip: str, index: int, rgba: np.ndarray) -> IsolatedFrame:
    mask = rgba[:, :, 3] > VISIBLE_ALPHA
    left, top, right, bottom = _bbox(mask)
    width = right - left
    torso_cut = left + int(round(width * 0.56))
    torso_mask = mask.copy()
    torso_mask[:, :torso_cut] = False
    torso_left, torso_top, torso_right, torso_bottom = _bbox(torso_mask)
    torso_alpha = rgba[:, :, 3].astype(np.float64)
    torso_alpha[~torso_mask] = 0.0
    weight = float(torso_alpha.sum())
    ys, xs = np.indices(mask.shape)
    anchor_x = float((xs * torso_alpha).sum() / weight)
    anchor_y = float((ys * torso_alpha).sum() / weight)
    return IsolatedFrame(
        clip=clip,
        index=index,
        rgba=rgba,
        visible_bbox=(left, top, right, bottom),
        anchor=(anchor_x, anchor_y),
        torso_height=float(torso_bottom - torso_top),
    )


def _extract_frames(clip: str, path: Path) -> list[IsolatedFrame]:
    with Image.open(path) as image:
        rgba = np.asarray(image.convert("RGBA"))
    alpha = rgba[:, :, 3] > COMPONENT_ALPHA
    rows = _row_bands(alpha)
    raw_frames: list[np.ndarray] = []
    for band_top, band_bottom in rows:
        raw_frames.extend(_isolate_row_frames(rgba, band_top, band_bottom))
    if len(raw_frames) != FRAME_COUNT:
        raise ValueError(f"{path}: expected 16 frames, found {len(raw_frames)}")
    return [_frame_metrics(clip, index, frame) for index, frame in enumerate(raw_frames)]


def _resample_frame(frame: IsolatedFrame, scale: float) -> tuple[np.ndarray, tuple[float, float]]:
    source = Image.fromarray(frame.rgba, mode="RGBA")
    scaled_size = (
        max(1, int(round(source.width * scale))),
        max(1, int(round(source.height * scale))),
    )
    resized = source.resize(scaled_size, Image.Resampling.LANCZOS)
    return np.asarray(resized), (frame.anchor[0] * scale, frame.anchor[1] * scale)


def _place_frame(
    frame: IsolatedFrame,
    scale: float,
    frame_size: tuple[int, int],
    target_anchor: tuple[int, int],
) -> tuple[Image.Image, dict[str, object]]:
    rgba, scaled_anchor = _resample_frame(frame, scale)
    output = np.zeros((frame_size[1], frame_size[0], 4), dtype=np.uint8)
    paste_x = int(round(target_anchor[0] - scaled_anchor[0]))
    paste_y = int(round(target_anchor[1] - scaled_anchor[1]))

    source_left = max(0, -paste_x)
    source_top = max(0, -paste_y)
    source_right = min(rgba.shape[1], frame_size[0] - paste_x)
    source_bottom = min(rgba.shape[0], frame_size[1] - paste_y)
    if source_left != 0 or source_top != 0 or source_right != rgba.shape[1] or source_bottom != rgba.shape[0]:
        raise ValueError(
            f"{frame.clip}[{frame.index}] would clip at scale {scale:.4f}; "
            f"paste=({paste_x},{paste_y}), source={rgba.shape[1]}x{rgba.shape[0]}"
        )
    output[
        paste_y : paste_y + rgba.shape[0], paste_x : paste_x + rgba.shape[1]
    ] = rgba
    visible = output[:, :, 3] > VISIBLE_ALPHA
    visible_bbox = _bbox(visible)
    margin = min(
        visible_bbox[0],
        visible_bbox[1],
        frame_size[0] - visible_bbox[2],
        frame_size[1] - visible_bbox[3],
    )
    if margin < 8:
        raise ValueError(
            f"{frame.clip}[{frame.index}] has unsafe {margin}px atlas padding: {visible_bbox}"
        )
    metrics = {
        "frame": frame.index,
        "scale": round(scale, 5),
        "source_anchor": [round(frame.anchor[0], 3), round(frame.anchor[1], 3)],
        "target_anchor": list(target_anchor),
        "visible_bbox": list(visible_bbox),
        "minimum_padding": int(margin),
    }
    return Image.fromarray(output, mode="RGBA"), metrics


def _save_atlas(
    clip: str,
    frames: list[IsolatedFrame],
    output_dir: Path,
    frame_size: tuple[int, int],
    target_anchor: tuple[int, int],
    global_torso_height: float,
    force: bool,
) -> dict[str, object]:
    output_path = output_dir / f"diver_{clip}_16f.png"
    if output_path.exists() and not force:
        raise FileExistsError(f"refusing to overwrite {output_path}; pass --force")
    atlas = Image.new(
        "RGBA", (frame_size[0] * GRID_COLUMNS, frame_size[1] * GRID_ROWS), (0, 0, 0, 0)
    )
    frame_metrics: list[dict[str, object]] = []
    for frame in frames:
        correction = global_torso_height / frame.torso_height
        scale = min(1.055, max(0.945, correction))
        normalized, metrics = _place_frame(frame, scale, frame_size, target_anchor)
        atlas.paste(
            normalized,
            ((frame.index % GRID_COLUMNS) * frame_size[0], (frame.index // GRID_COLUMNS) * frame_size[1]),
        )
        frame_metrics.append(metrics)
    output_dir.mkdir(parents=True, exist_ok=True)
    atlas.save(output_path, format="PNG", optimize=True)
    return {
        "clip": clip,
        "file": output_path.name,
        "frame_count": FRAME_COUNT,
        "frame_size": list(frame_size),
        "atlas_size": list(atlas.size),
        "frames": frame_metrics,
    }


def main() -> None:
    args = _parse_args()
    inputs = {clip: getattr(args, clip) for clip in CLIP_NAMES}
    frames_by_clip = {clip: _extract_frames(clip, path) for clip, path in inputs.items()}
    torso_heights = sorted(
        frame.torso_height for frames in frames_by_clip.values() for frame in frames
    )
    global_torso_height = torso_heights[len(torso_heights) // 2]
    frame_size = (args.frame_width, args.frame_height)
    target_anchor = (args.anchor_x, args.anchor_y)
    manifests = [
        _save_atlas(
            clip,
            frames_by_clip[clip],
            args.output_dir,
            frame_size,
            target_anchor,
            global_torso_height,
            args.force,
        )
        for clip in CLIP_NAMES
    ]
    manifest = {
        "layout": [GRID_COLUMNS, GRID_ROWS],
        "frame_size": list(frame_size),
        "stable_anchor": list(target_anchor),
        "normalization_torso_height": global_torso_height,
        "clips": manifests,
    }
    manifest_path = args.metrics_path or args.output_dir / "animation_build_metrics.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
