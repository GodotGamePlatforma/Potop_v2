#!/usr/bin/env python3
"""Focused unit coverage for geometry-driven portal backdrop clearances."""

from __future__ import annotations

import copy
import importlib.util
import sys
import unittest
from pathlib import Path


WORKBENCH_DIR = Path(__file__).resolve().parents[1]
BUILDER_PATH = WORKBENCH_DIR / "tools" / "build_underwater_map.py"
SPEC = importlib.util.spec_from_file_location(
    "portal_backdrop_clearance_builder",
    BUILDER_PATH,
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Cannot load builder from {BUILDER_PATH}")
BUILDER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BUILDER
SPEC.loader.exec_module(BUILDER)


def _fixture(structure_id: str = "structure_alpha") -> dict:
    width = 12
    height = 10
    solid = 1
    open_water = 0
    cells = bytearray([solid] * (width * height))

    def open_cell(x: int, y: int) -> None:
        cells[y * width + x] = open_water

    # One left-boundary run and one right-boundary run have open continuity.
    for y in range(3, 5):
        open_cell(2, y)
        open_cell(3, y)
    for y in range(4, 7):
        open_cell(6, y)
        open_cell(7, y)

    # This top-boundary run is sealed outside and must not create a clearance.
    for x in range(4, 6):
        open_cell(x, 2)

    return {
        "mode": BUILDER.L05_MODE,
        "pixel_size": (width, height),
        "world_units_per_pixel": (40, 40),
        "cells": bytes(cells),
        "encoding": {"solid": solid, "open_water": open_water},
        "structure_build": {
            "instances": [
                {
                    "id": structure_id,
                    "enabled": True,
                    "origin_px": (3, 2),
                    "size_px": (4, 5),
                    "origin": (120, 80),
                    "size": (160, 200),
                    "source": {
                        "package_path": f"structures/{structure_id}/structure_manifest.json",
                        "template_id": f"template_{structure_id}",
                        "sockets": [{"id": f"socket_{structure_id}"}],
                    },
                }
            ]
        },
    }


def _manifest() -> dict:
    return {
        "visual": {
            "water_color": "071d2a",
            "layers": [
                {"id": "L01", "z_index": -90},
                {"id": "L02", "z_index": -80},
                {"id": "L03", "z_index": -30},
                {"id": "L04", "z_index": -20},
            ],
        }
    }


class PortalBackdropClearanceTest(unittest.TestCase):
    def test_one_clearance_per_traversable_run_and_none_for_sealed_run(self) -> None:
        clearances = BUILDER._portal_backdrop_clearances(_fixture())

        self.assertEqual(2, len(clearances))
        self.assertEqual([80, 120], sorted(int(item["span"]) for item in clearances))
        self.assertEqual(
            ["vertical", "vertical"],
            sorted(str(item["geometry"]["axis"]) for item in clearances),
        )
        for clearance in clearances:
            geometry = clearance["geometry"]
            self.assertEqual(
                {
                    "axis",
                    "boundary_cell",
                    "run_start_cell",
                    "run_end_cell",
                    "outward_cell",
                    "cell_size",
                },
                set(geometry),
            )
            self.assertEqual(
                BUILDER._canonical_sha256(geometry),
                clearance["geometry_digest"],
            )
            core_x, core_y, core_width, core_height = clearance["core_rect"]
            outer_x, outer_y, outer_width, outer_height = clearance["outer_rect"]
            self.assertEqual(240, core_width)
            self.assertEqual(int(clearance["span"]) + 80, core_height)
            self.assertEqual(core_x - 40, outer_x)
            self.assertEqual(core_y - 40, outer_y)
            self.assertEqual(core_width + 80, outer_width)
            self.assertEqual(core_height + 80, outer_height)

    def test_identity_and_package_names_cannot_change_digest_or_presentation(self) -> None:
        first_topology = _fixture("structure_alpha")
        renamed_topology = copy.deepcopy(first_topology)
        renamed_instance = renamed_topology["structure_build"]["instances"][0]
        renamed_instance["id"] = "randomized_7f0e"
        renamed_instance["source"] = {
            "package_path": "structures/randomized_7f0e/private.json",
            "template_id": "unrelated_template_name",
            "sockets": [{"id": "renamed_private_socket"}],
        }

        first_clearances = BUILDER._portal_backdrop_clearances(first_topology)
        renamed_clearances = BUILDER._portal_backdrop_clearances(renamed_topology)
        self.assertEqual(first_clearances, renamed_clearances)

        first_lines: list[str] = []
        renamed_lines: list[str] = []
        BUILDER._append_portal_backdrop_clearances(
            first_lines,
            _manifest(),
            first_topology,
        )
        BUILDER._append_portal_backdrop_clearances(
            renamed_lines,
            _manifest(),
            renamed_topology,
        )
        first_render = "\n".join(first_lines)
        renamed_render = "\n".join(renamed_lines)
        self.assertEqual(first_render, renamed_render)
        self.assertNotIn("structure_alpha", first_render)
        self.assertNotIn("randomized_7f0e", first_render)
        self.assertNotIn("private.json", first_render)
        self.assertIn("z_as_relative = false", first_render)
        self.assertIn("z_index = -79", first_render)
        self.assertIn("metadata/clearance_count = 2", first_render)
        self.assertIn("metadata/feather_outer_tint = 0.82", first_render)

    def test_generated_fragment_is_visual_only_and_deterministic(self) -> None:
        topology = _fixture()
        lines_a: list[str] = []
        lines_b: list[str] = []
        BUILDER._append_portal_backdrop_clearances(lines_a, _manifest(), topology)
        BUILDER._append_portal_backdrop_clearances(lines_b, _manifest(), topology)
        rendered = "\n".join(lines_a)

        self.assertEqual(lines_a, lines_b)
        self.assertNotIn("Area2D", rendered)
        self.assertNotIn("CollisionObject2D", rendered)
        self.assertNotIn("CollisionShape2D", rendered)
        self.assertNotIn("CollisionPolygon2D", rendered)
        self.assertNotIn("StaticBody2D", rendered)
        self.assertNotIn("PackedColorArray(Color", rendered)
        self.assertIn(
            "vertex_colors = PackedColorArray("
            "0.022509804, 0.093254902, 0.13505882, 1, "
            "0.02745098, 0.11372549, 0.16470588, 1, "
            "0.02745098, 0.11372549, 0.16470588, 1, "
            "0.022509804, 0.093254902, 0.13505882, 1)",
            rendered,
        )
        vertex_color_lines = [
            line
            for line in lines_a
            if line.startswith("vertex_colors = PackedColorArray(")
        ]
        self.assertEqual(8, len(vertex_color_lines))
        for line in vertex_color_lines:
            components = line.removeprefix(
                "vertex_colors = PackedColorArray("
            ).removesuffix(")").split(", ")
            self.assertEqual(["1", "1", "1", "1"], components[3::4])
        self.assertEqual(8, rendered.count("color = Color(1, 1, 1, 1)"))
        self.assertEqual(
            2,
            rendered.count(
                "color = Color(0.02745098, 0.11372549, 0.16470588, 1)"
            ),
        )
        self.assertEqual(2, rendered.count('metadata/role = "portal_backdrop_clearance_core"'))
        self.assertEqual(8, rendered.count('metadata/role = "portal_backdrop_clearance_feather"'))

    def test_clearance_must_remain_below_l03_and_l04(self) -> None:
        invalid_manifest = _manifest()
        for layer in invalid_manifest["visual"]["layers"]:
            if layer["id"] == "L03":
                layer["z_index"] = -85

        with self.assertRaisesRegex(
            BUILDER.ManifestError,
            "below L03/L04",
        ):
            BUILDER._append_portal_backdrop_clearances(
                [],
                invalid_manifest,
                _fixture(),
            )

    def test_no_structure_or_no_open_continuity_produces_no_clearance(self) -> None:
        self.assertEqual(
            [],
            BUILDER._portal_backdrop_clearances({"mode": "open_world"}),
        )

        no_structure = _fixture()
        no_structure["structure_build"]["instances"] = []
        self.assertEqual([], BUILDER._portal_backdrop_clearances(no_structure))

        sealed = _fixture()
        width, height = sealed["pixel_size"]
        sealed["cells"] = bytes([sealed["encoding"]["solid"]] * (width * height))
        self.assertEqual([], BUILDER._portal_backdrop_clearances(sealed))
        sealed_lines: list[str] = []
        BUILDER._append_portal_backdrop_clearances(
            sealed_lines,
            _manifest(),
            sealed,
        )
        sealed_render = "\n".join(sealed_lines)
        self.assertIn("metadata/clearance_count = 0", sealed_render)
        self.assertNotIn('[node name="Clearance_', sealed_render)

    def test_duplicate_enabled_geometry_fails_closed(self) -> None:
        duplicated = _fixture()
        second_instance = copy.deepcopy(
            duplicated["structure_build"]["instances"][0]
        )
        second_instance["id"] = "structure_beta"
        second_instance["source"]["package_path"] = (
            "structures/structure_beta/structure_manifest.json"
        )
        duplicated["structure_build"]["instances"].append(second_instance)

        with self.assertRaisesRegex(
            BUILDER.ManifestError,
            "duplicate portal backdrop clearance geometry",
        ):
            BUILDER._portal_backdrop_clearances(duplicated)


if __name__ == "__main__":
    unittest.main(verbosity=2)
