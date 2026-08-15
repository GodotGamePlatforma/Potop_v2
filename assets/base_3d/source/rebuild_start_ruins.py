"""Deterministically rebuild the six start-platform ruins.

Run with Blender, for example:

    blender --background start_platform_ruins.blend \
        --python rebuild_start_ruins.py -- --save --export

The script deliberately reuses the authored level-I components and their PBR
materials.  It does not touch the six slot roots, anchors, type markers, or any
Built_<slot>_L1..L4 object.  Re-running it replaces only the six
Ruin_<slot>_Geometry meshes.
"""

from __future__ import annotations

import argparse
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector


SLOTS = (
    "top_left",
    "top_center",
    "top_right",
    "bottom_left",
    "center",
    "bottom_right",
)

SOURCE_LEVEL_ONE = {
    "top_left": "Built_top_left_L1_Geometry",
    "top_center": "Built_top_center_L1_Geometry",
    "top_right": "Built_top_right_L1_Geometry",
    "bottom_left": "Built_bottom_left_L1_Geometry",
    "center": "Built_center_L1_Geometry",
    "bottom_right": "Built_bottom_right_L1_Geometry",
}


@dataclass(frozen=True)
class Component:
    vertex_indices: frozenset[int]
    polygon_count: int
    center: Vector
    dimensions: Vector
    material_names: frozenset[str]


@dataclass(frozen=True)
class PartSpec:
    material: str
    center: tuple[float, float, float]
    offset: tuple[float, float, float] = (0.0, 0.0, 0.0)
    rotation_degrees: tuple[float, float, float] = (0.0, 0.0, 0.0)
    scale: tuple[float, float, float] = (1.0, 1.0, 1.0)


# Centers refer to connected components in the corresponding authored L1 mesh.
# The transformations make the selected parts visibly broken without changing
# the slot footprint or pretending that level I has already been completed.
RUIN_PARTS: dict[str, tuple[PartSpec, ...]] = {
    "top_left": (
        PartSpec("M_WetSalvageWood", (1.95, 2.42, 0.97), (-0.20, 0.05, -0.22), (5.0, -7.0, -5.0), (0.82, 0.82, 0.38)),
        PartSpec("M_FadedTeal", (1.95, 1.29, 0.78), (-0.30, 0.12, -0.12), (0.0, 9.0, -8.0), (0.68, 1.0, 0.72)),
        PartSpec("M_WeatheredSteel", (2.65, 1.85, 2.15), (-0.28, 0.12, -0.92), (14.0, -9.0, -8.0), (0.72, 0.78, 0.62)),
        PartSpec("M_BleachedWood", (3.85, 0.45, 1.01), (0.02, 0.04, -0.08), (0.0, 18.0, 4.0), (1.0, 1.0, 0.82)),
        PartSpec("M_BleachedWood", (4.95, 0.45, 1.01), (-0.12, 0.10, -0.28), (0.0, -34.0, -7.0), (1.0, 1.0, 0.64)),
        PartSpec("M_BleachedWood", (4.40, 0.45, 2.04), (-0.14, 0.08, -0.42), (0.0, 10.0, 14.0), (0.72, 1.0, 1.0)),
        PartSpec("M_DeepSteel", (4.17, 2.52, 0.42), (-0.05, 0.02, 0.0), (7.0, 0.0, -10.0)),
        PartSpec("M_RustOxide", (3.93, 2.52, 0.42), (-0.05, 0.02, 0.0), (7.0, 0.0, -10.0)),
        PartSpec("M_RustOxide", (4.42, 2.52, 0.42), (-0.05, 0.02, 0.0), (7.0, 0.0, -10.0)),
        PartSpec("M_WetRope", (4.14, 2.52, 0.42), (-0.05, 0.02, 0.0), (7.0, 0.0, -10.0)),
        PartSpec("M_WetRope", (4.31, 2.52, 0.42), (-0.05, 0.02, 0.0), (7.0, 0.0, -10.0)),
        PartSpec("M_BleachedWood", (0.70, 0.45, 0.28), (0.16, 0.20, 0.04), (0.0, 0.0, 16.0)),
        PartSpec("M_WetRope", (4.17, 0.44, 1.03), (-0.04, 0.04, -0.24), (0.0, 18.0, 8.0), (1.0, 1.0, 0.72)),
        PartSpec("M_WetRope", (4.64, 0.44, 1.03), (-0.04, 0.04, -0.24), (0.0, 18.0, 8.0), (1.0, 1.0, 0.72)),
        PartSpec("M_WetRope", (4.40, 0.44, 0.65), (-0.04, 0.04, -0.24), (0.0, 18.0, 8.0), (0.72, 1.0, 1.0)),
        PartSpec("M_WetRope", (4.40, 0.44, 1.40), (-0.04, 0.04, -0.24), (0.0, 18.0, 8.0), (0.72, 1.0, 1.0)),
    ),
    "top_center": (
        PartSpec("M_WeatheredSteel", (2.36, 2.20, 1.08), (0.05, 0.04, -0.18), (4.0, -5.0, 3.0), (0.80, 0.80, 0.38)),
        PartSpec("M_RustFresh", (2.36, 0.61, 0.99), (-0.62, 0.12, -0.18), (0.0, 8.0, -5.0), (0.55, 1.0, 0.62)),
        PartSpec("M_DeepSteel", (2.65, 1.42, 2.38), (0.20, 0.14, -1.02), (18.0, 7.0, 9.0), (0.66, 0.74, 0.56)),
        PartSpec("M_GalvanizedSteel", (2.65, 0.11, 0.51), (0.08, 0.12, 0.05), (0.0, 0.0, -5.0), (0.88, 1.0, 1.0)),
        PartSpec("M_RustOxide", (1.20, 0.11, 0.25), (0.06, 0.12, 0.02), (0.0, 12.0, -5.0)),
        PartSpec("M_RustOxide", (4.11, 0.11, 0.25), (0.06, 0.12, -0.10), (0.0, -22.0, -5.0), (1.0, 1.0, 0.72)),
        PartSpec("M_RustOxide", (1.40, 2.62, 3.07), (-0.08, -0.02, -1.00), (0.0, 19.0, -7.0), (1.0, 1.0, 0.62)),
        PartSpec("M_RustDark", (1.40, 2.62, 4.30), (-0.45, -0.02, -1.80), (0.0, 26.0, -7.0), (0.90, 0.90, 0.90)),
        PartSpec("M_DeepSteel", (3.74, 0.54, 0.86), (0.22, 0.16, -0.08), (0.0, -10.0, 8.0), (0.80, 1.0, 0.72)),
    ),
    "top_right": (
        PartSpec("M_WetSalvageWood", (2.78, 2.29, 1.05), (0.0, 0.08, -0.24), (5.0, -4.0, 4.0), (0.82, 0.80, 0.34)),
        PartSpec("M_FadedBlueCanvas", (2.78, 0.50, 0.96), (-0.46, 0.18, -0.10), (0.0, 8.0, 7.0), (0.58, 1.0, 0.68)),
        PartSpec("M_BleachedWood", (2.78, 0.43, 0.84), (0.18, 0.14, -0.08), (0.0, -12.0, -14.0), (0.90, 1.0, 0.82)),
        PartSpec("M_DeepSteel", (1.26, 0.43, 1.14), (-0.12, 0.12, -0.18), (0.0, 12.0, 7.0), (0.90, 1.0, 0.78)),
        PartSpec("M_WeatheredSteel", (2.78, 1.39, 2.45), (-0.22, 0.24, -1.02), (16.0, -8.0, -10.0), (0.66, 0.72, 0.55)),
        PartSpec("M_BleachedWood", (2.78, 0.08, 0.26), (0.0, 0.15, 0.04), (0.0, 0.0, 4.0)),
        PartSpec("M_RustOxide", (2.78, 2.29, 2.57), (0.04, 0.0, -0.76), (0.0, 7.0, -8.0), (0.66, 1.0, 1.0)),
    ),
    "bottom_left": (
        PartSpec("M_DeepSteel", (1.98, 2.44, 1.12), (-0.10, 0.05, -0.22), (4.0, -5.0, -3.0), (0.82, 0.80, 0.36)),
        PartSpec("M_SafetyOchre", (1.98, 1.05, 1.04), (-0.48, 0.16, -0.16), (0.0, 8.0, -5.0), (0.62, 1.0, 0.66)),
        PartSpec("M_WetGraphiteSteel", (2.18, 0.97, 0.91), (0.15, 0.12, -0.08), (0.0, -12.0, 7.0), (0.78, 1.0, 0.72)),
        PartSpec("M_WeatheredSteel", (1.98, 2.44, 2.35), (-0.18, 0.18, -1.02), (15.0, 6.0, 8.0), (0.68, 0.72, 0.62)),
        PartSpec("M_RustOxide", (4.21, 0.60, 1.20), (0.04, 0.10, -0.10), (0.0, 14.0, 4.0), (1.0, 1.0, 0.82)),
        PartSpec("M_RustOxide", (5.28, 0.60, 1.20), (-0.12, 0.10, -0.34), (0.0, -30.0, -8.0), (1.0, 1.0, 0.62)),
        PartSpec("M_SafetyYellow", (4.74, 0.60, 2.40), (-0.10, 0.10, -0.54), (0.0, 12.0, -7.0), (0.72, 1.0, 1.0)),
        PartSpec("M_FadedMarineBlue", (4.33, 2.76, 0.69), (-0.06, -0.06, 0.0), (6.0, 0.0, -9.0)),
        PartSpec("M_SafetyOchre", (4.87, 2.76, 0.56), (-0.06, -0.06, 0.0), (6.0, 0.0, -9.0)),
        PartSpec("M_RustOxide", (4.33, 2.76, 0.16), (-0.06, -0.06, 0.0), (6.0, 0.0, -9.0)),
        PartSpec("M_RustOxide", (4.87, 2.76, 0.12), (-0.06, -0.06, 0.0), (6.0, 0.0, -9.0)),
        PartSpec("M_RustFresh", (4.76, 0.60, 0.54), (-0.08, 0.10, 0.0), (0.0, 12.0, -7.0)),
        PartSpec("M_SafetyYellow", (1.29, 0.93, 0.18), (-0.42, 0.12, 0.02), (0.0, 0.0, -5.0)),
        PartSpec("M_DeepSteel", (1.61, 0.93, 0.18), (-0.42, 0.12, 0.02), (0.0, 0.0, -5.0)),
        PartSpec("M_SafetyYellow", (1.93, 0.93, 0.18), (-0.42, 0.12, 0.02), (0.0, 0.0, -5.0)),
        PartSpec("M_DeepSteel", (2.25, 0.93, 0.18), (-0.42, 0.12, 0.02), (0.0, 0.0, -5.0)),
        PartSpec("M_SafetyYellow", (2.57, 0.93, 0.18), (-0.42, 0.12, 0.02), (0.0, 0.0, -5.0)),
    ),
    "center": (
        PartSpec("M_WeatheredOffWhite", (2.40, 2.01, 0.82), (-0.08, 0.08, -0.22), (4.0, -5.0, 3.0), (0.84, 0.80, 0.36)),
        PartSpec("M_WeatheredOffWhite", (2.70, 3.83, 1.87), (0.0, -0.42, -0.52), (12.0, -5.0, -5.0), (0.72, 0.82, 0.76)),
        PartSpec("M_WeatheredOffWhite", (2.70, 2.77, 3.19), (-0.20, -0.10, -1.46), (18.0, 7.0, -8.0), (0.62, 0.78, 0.72)),
        PartSpec("M_WeatheredOffWhite", (2.70, 0.41, 2.65), (0.26, 0.14, -1.06), (-14.0, -8.0, 11.0), (0.60, 0.80, 0.72)),
        PartSpec("M_FadedBlueCanvas", (2.40, 0.23, 0.98), (-0.42, 0.14, -0.16), (0.0, 10.0, -6.0), (0.62, 1.0, 0.66)),
        PartSpec("M_WeatheredOffWhite", (3.36, 0.17, 0.89), (0.18, 0.12, -0.08), (0.0, -8.0, 10.0), (0.86, 1.0, 0.82)),
        PartSpec("M_MedicalRed", (3.36, 0.10, 1.56), (0.18, 0.12, -0.24), (0.0, -8.0, 10.0), (0.90, 1.0, 0.90)),
        PartSpec("M_DeepSteel", (1.55, 0.17, 1.14), (-0.12, 0.12, -0.22), (0.0, 12.0, -7.0), (0.86, 1.0, 0.72)),
        PartSpec("M_GalvanizedSteel", (1.15, 2.41, 3.00), (0.18, 0.06, -1.28), (0.0, -18.0, 6.0), (1.0, 1.0, 0.72)),
    ),
    "bottom_right": (
        PartSpec("M_FadedMarineBlue", (1.45, 2.52, 0.91), (0.02, 0.06, -0.22), (4.0, -5.0, 3.0), (0.82, 0.80, 0.36)),
        PartSpec("M_DeepSteel", (1.45, 1.28, 0.92), (-0.32, 0.14, -0.14), (0.0, 9.0, -6.0), (0.68, 1.0, 0.66)),
        PartSpec("M_SafetyOchre", (2.35, 1.21, 0.82), (0.12, 0.14, -0.10), (0.0, -10.0, 9.0), (0.86, 1.0, 0.76)),
        PartSpec("M_WeatheredSteel", (1.45, 2.52, 1.93), (-0.08, 0.18, -0.82), (14.0, 6.0, -8.0), (0.74, 0.76, 0.62)),
        PartSpec("M_SafetyOchre", (3.45, 2.81, 1.60), (0.0, 0.05, -0.14), (0.0, 15.0, 4.0), (1.0, 1.0, 0.82)),
        PartSpec("M_RustOxide", (5.15, 2.81, 1.60), (-0.14, 0.05, -0.42), (0.0, -30.0, -8.0), (1.0, 1.0, 0.62)),
        PartSpec("M_SafetyYellow", (4.30, 2.81, 3.19), (-0.14, 0.05, -0.72), (0.0, 10.0, -8.0), (0.74, 1.0, 1.0)),
        PartSpec("M_DeepSteel", (4.30, 2.81, 1.58), (-0.10, 0.05, -0.32), (0.0, 8.0, -8.0), (0.72, 1.0, 0.82)),
        PartSpec("M_DeepSteel", (4.28, 2.78, 2.64), (-0.10, 0.03, -0.66), (8.0, 0.0, -10.0)),
        PartSpec("M_RustOxide", (4.00, 2.78, 2.64), (-0.10, 0.03, -0.66), (8.0, 0.0, -10.0)),
        PartSpec("M_RustOxide", (4.56, 2.78, 2.64), (-0.10, 0.03, -0.66), (8.0, 0.0, -10.0)),
        PartSpec("M_WetRope", (4.24, 2.78, 2.64), (-0.10, 0.03, -0.66), (8.0, 0.0, -10.0)),
        PartSpec("M_WetRope", (4.43, 2.78, 2.64), (-0.10, 0.03, -0.66), (8.0, 0.0, -10.0)),
        PartSpec("M_FadedMarineBlue", (0.38, 3.44, 0.61), (0.08, -0.08, 0.0), (5.0, 0.0, 10.0)),
        PartSpec("M_RustOxide", (0.38, 3.44, 0.13), (0.08, -0.08, 0.0), (5.0, 0.0, 10.0)),
        PartSpec("M_SafetyOchre", (4.28, 0.78, 0.14), (-0.08, 0.08, 0.0), (4.0, 0.0, -7.0)),
        PartSpec("M_GalvanizedSteel", (4.28, 0.78, 1.24), (-0.08, 0.08, -0.24), (4.0, 0.0, -7.0), (0.90, 0.90, 0.78)),
    ),
}


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--save", action="store_true", help="Save the edited .blend in place.")
    parser.add_argument(
        "--export",
        nargs="?",
        const="",
        default=None,
        help="Export GLB. With no value, use ../start_platform_ruins.glb.",
    )
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(argv)


def _require_object(name: str, expected_type: str | None = None) -> bpy.types.Object:
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise RuntimeError(f"Missing required object: {name}")
    if expected_type is not None and obj.type != expected_type:
        raise RuntimeError(f"{name} must be {expected_type}, got {obj.type}")
    return obj


def _require_material(name: str) -> bpy.types.Material:
    material = bpy.data.materials.get(name)
    if material is None:
        raise RuntimeError(f"Missing required material: {name}")
    return material


def _connected_components(obj: bpy.types.Object) -> list[Component]:
    mesh = obj.data
    adjacency = [set() for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)

    remaining = set(range(len(mesh.vertices)))
    components: list[Component] = []
    polygons_by_vertex: list[list[bpy.types.MeshPolygon]] = [[] for _ in mesh.vertices]
    for polygon in mesh.polygons:
        for vertex_index in polygon.vertices:
            polygons_by_vertex[vertex_index].append(polygon)

    while remaining:
        seed = min(remaining)
        remaining.remove(seed)
        stack = [seed]
        vertices = {seed}
        while stack:
            vertex_index = stack.pop()
            for neighbor in adjacency[vertex_index]:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    vertices.add(neighbor)
                    stack.append(neighbor)

        polygon_indices: set[int] = set()
        for vertex_index in vertices:
            polygon_indices.update(p.index for p in polygons_by_vertex[vertex_index])
        polygons = [mesh.polygons[index] for index in sorted(polygon_indices)]
        coordinates = [mesh.vertices[index].co for index in vertices]
        minimum = Vector((
            min(coordinate.x for coordinate in coordinates),
            min(coordinate.y for coordinate in coordinates),
            min(coordinate.z for coordinate in coordinates),
        ))
        maximum = Vector((
            max(coordinate.x for coordinate in coordinates),
            max(coordinate.y for coordinate in coordinates),
            max(coordinate.z for coordinate in coordinates),
        ))
        material_names = frozenset(
            obj.material_slots[polygon.material_index].material.name
            for polygon in polygons
            if polygon.material_index < len(obj.material_slots)
            and obj.material_slots[polygon.material_index].material is not None
        )
        components.append(
            Component(
                vertex_indices=frozenset(vertices),
                polygon_count=len(polygons),
                center=(minimum + maximum) * 0.5,
                dimensions=maximum - minimum,
                material_names=material_names,
            )
        )
    return components


def _find_component(components: Sequence[Component], spec: PartSpec) -> Component:
    target = Vector(spec.center)
    candidates = [component for component in components if spec.material in component.material_names]
    if not candidates:
        raise RuntimeError(f"No component uses {spec.material}")
    selected = min(candidates, key=lambda component: (component.center - target).length)
    distance = (selected.center - target).length
    if distance > 0.06:
        raise RuntimeError(
            f"Component drift for {spec.material} near {tuple(target)}: "
            f"found {tuple(round(value, 4) for value in selected.center)}, distance={distance:.4f}"
        )
    return selected


def _extract_component(
    source: bpy.types.Object,
    root: bpy.types.Object,
    component: Component,
    spec: PartSpec,
    index: int,
) -> bpy.types.Object:
    result = source.copy()
    result.data = source.data.copy()
    result.name = f"__ruin_part_{root.name}_{index:02d}"
    bpy.context.collection.objects.link(result)

    mesh_edit = bmesh.new()
    mesh_edit.from_mesh(result.data)
    mesh_edit.verts.ensure_lookup_table()
    delete_vertices = [
        vertex
        for vertex in mesh_edit.verts
        if vertex.index not in component.vertex_indices
    ]
    bmesh.ops.delete(mesh_edit, geom=delete_vertices, context="VERTS")
    mesh_edit.to_mesh(result.data)
    mesh_edit.free()
    result.data.validate(clean_customdata=False)
    result.data.update()

    result.parent = root
    result.matrix_parent_inverse = Matrix.Identity(4)
    result.matrix_basis = source.matrix_basis.copy()
    result.hide_render = False
    result.hide_viewport = False
    result.hide_set(False)

    bpy.ops.object.select_all(action="DESELECT")
    result.select_set(True)
    bpy.context.view_layer.objects.active = result
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")

    result.location += Vector(spec.offset)
    result.rotation_euler.rotate(
        Euler(tuple(math.radians(value) for value in spec.rotation_degrees), "XYZ")
    )
    result.scale = Vector(spec.scale)
    return result


def _add_box(
    root: bpy.types.Object,
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material_name: str,
    rotation_degrees: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.045,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    obj = bpy.context.active_object
    obj.name = name
    obj.parent = root
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.location = Vector(location)
    obj.rotation_euler = Euler(
        tuple(math.radians(value) for value in rotation_degrees), "XYZ"
    )
    obj.dimensions = Vector(dimensions)
    obj.data.materials.append(_require_material(material_name))
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new(name="RuinEdgeWear", type="BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        modifier.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


def _add_cylinder(
    root: bpy.types.Object,
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    material_name: str,
    rotation_degrees: tuple[float, float, float] = (0.0, 0.0, 0.0),
    vertices: int = 12,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth)
    obj = bpy.context.active_object
    obj.name = name
    obj.parent = root
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.location = Vector(location)
    obj.rotation_euler = Euler(
        tuple(math.radians(value) for value in rotation_degrees), "XYZ"
    )
    obj.data.materials.append(_require_material(material_name))
    bevel = obj.modifiers.new(name="RuinEdgeWear", type="BEVEL")
    bevel.width = min(0.055, radius * 0.16)
    bevel.segments = 2
    bevel.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj


def _add_beam_between(
    root: bpy.types.Object,
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    thickness: float,
    material_name: str,
) -> bpy.types.Object:
    start_vector = Vector(start)
    end_vector = Vector(end)
    direction = end_vector - start_vector
    length = direction.length
    if length <= 0.001:
        raise RuntimeError(f"Zero-length ruin beam: {name}")
    obj = _add_box(
        root,
        name,
        tuple((start_vector + end_vector) * 0.5),
        (thickness, thickness, length),
        material_name,
        bevel=min(0.04, thickness * 0.24),
    )
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
    obj.rotation_mode = "XYZ"
    return obj


def _add_foundation_fragments(slot: str, root: bpy.types.Object) -> list[bpy.types.Object]:
    parts = [
        _add_box(root, f"__{slot}_foundation_a", (-1.30, -1.30, 0.12), (2.45, 0.18, 0.18), "M_RustOxide", (0.0, 0.0, 5.0)),
        _add_box(root, f"__{slot}_foundation_b", (1.15, 1.25, 0.13), (2.15, 0.18, 0.20), "M_WeatheredSteel", (0.0, 0.0, -7.0)),
        _add_box(root, f"__{slot}_foundation_c", (-2.00, 0.30, 0.16), (0.18, 1.85, 0.22), "M_DeepSteel", (0.0, 0.0, -5.0)),
    ]
    return parts


def _add_slot_identity(slot: str, root: bpy.types.Object) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []
    if slot == "top_left":
        parts.extend(
            [
                _add_beam_between(root, "__fishing_broken_rack", (-0.45, 1.15, 0.18), (1.25, 1.38, 1.58), 0.11, "M_BleachedWood"),
                _add_beam_between(root, "__fishing_rack_cross", (0.25, 1.30, 1.05), (1.55, 1.22, 1.34), 0.09, "M_WetRope"),
            ]
        )
    elif slot == "top_center":
        parts.extend(
            [
                _add_cylinder(root, "__kitchen_stove_drum", (1.18, 0.70, 0.52), 0.52, 0.72, "M_RustDark", (82.0, 0.0, 8.0), 16),
                _add_cylinder(root, "__kitchen_pot_rim", (1.10, 0.72, 0.70), 0.58, 0.10, "M_GalvanizedSteel", (82.0, 0.0, 8.0), 16),
            ]
        )
    elif slot == "top_right":
        parts.extend(
            [
                _add_beam_between(root, "__community_notice_post_a", (-1.45, 0.65, 0.14), (-1.34, 0.70, 1.60), 0.12, "M_BleachedWood"),
                _add_beam_between(root, "__community_notice_post_b", (0.25, 0.65, 0.14), (0.02, 0.72, 1.16), 0.12, "M_BleachedWood"),
                _add_box(root, "__community_torn_notice", (-0.70, 0.66, 1.05), (1.15, 0.08, 0.48), "M_FadedBlueCanvas", (0.0, 8.0, -5.0), 0.025),
            ]
        )
    elif slot == "bottom_left":
        parts.extend(
            [
                _add_beam_between(root, "__workshop_fallen_girder", (-0.90, 1.10, 0.22), (1.35, 0.78, 0.74), 0.18, "M_SafetyOchre"),
                _add_cylinder(root, "__workshop_scrap_wheel", (1.35, -0.85, 0.50), 0.52, 0.12, "M_RustDark", (90.0, 0.0, 12.0), 16),
            ]
        )
    elif slot == "center":
        parts.extend(
            [
                _add_box(root, "__infirmary_cot", (-0.45, 0.90, 0.30), (1.75, 0.78, 0.14), "M_GalvanizedSteel", (5.0, -4.0, 11.0)),
                _add_beam_between(root, "__infirmary_cot_leg_a", (-1.15, 0.65, 0.13), (-1.10, 0.68, 0.48), 0.07, "M_DeepSteel"),
                _add_beam_between(root, "__infirmary_cot_leg_b", (0.22, 1.10, 0.13), (0.18, 1.08, 0.43), 0.07, "M_DeepSteel"),
            ]
        )
    elif slot == "bottom_right":
        parts.extend(
            [
                _add_beam_between(root, "__diving_broken_ladder_a", (-1.00, -1.18, 0.10), (-0.82, -1.10, 1.40), 0.10, "M_GalvanizedSteel"),
                _add_beam_between(root, "__diving_broken_ladder_b", (-0.38, -1.20, 0.10), (-0.28, -1.10, 1.06), 0.10, "M_GalvanizedSteel"),
                _add_beam_between(root, "__diving_ladder_rung_a", (-0.86, -1.13, 0.48), (-0.34, -1.14, 0.46), 0.07, "M_SafetyOchre"),
                _add_beam_between(root, "__diving_ladder_rung_b", (-0.79, -1.12, 0.82), (-0.31, -1.13, 0.76), 0.07, "M_SafetyOchre"),
            ]
        )
    return parts


def _remove_old_geometry(root: bpy.types.Object) -> None:
    expected_name = f"{root.name}_Geometry"
    old_geometry = bpy.data.objects.get(expected_name)
    if old_geometry is None:
        raise RuntimeError(f"Missing replaceable ruin geometry: {expected_name}")
    if old_geometry.parent != root or old_geometry.type != "MESH":
        raise RuntimeError(f"Unexpected ruin geometry contract for {expected_name}")
    old_mesh = old_geometry.data
    bpy.data.objects.remove(old_geometry, do_unlink=True)
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)


def _join_parts(root: bpy.types.Object, parts: Sequence[bpy.types.Object]) -> bpy.types.Object:
    if not parts:
        raise RuntimeError(f"No generated parts for {root.name}")
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.hide_viewport = False
        part.hide_set(False)
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    result = bpy.context.active_object
    # Blender keeps the active part's transform when joining.  Bake it before
    # moving the origin; otherwise resetting that transform would expand every
    # other joined component by the inverse scale of the first fragment.
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    result.name = f"{root.name}_Geometry"
    result.data.name = f"{result.name}_Mesh"
    result.parent = root
    result.hide_render = False
    result.hide_viewport = False
    result.hide_set(False)

    bpy.context.scene.cursor.location = root.matrix_world.translation
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    if result.location.length > 0.0001:
        raise RuntimeError(
            f"{result.name} origin did not return to the slot root: {tuple(result.location)}"
        )

    # The source parts carry generous bevel topology.  A modest collapse keeps
    # the authored silhouette and UVs while bringing all six highlighted ruins
    # below the intended shared triangle budget.
    decimate = result.modifiers.new(name="RuinTopologyBudget", type="DECIMATE")
    decimate.decimate_type = "COLLAPSE"
    decimate.ratio = 0.78
    decimate.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = result
    bpy.ops.object.modifier_apply(modifier=decimate.name)

    bpy.ops.object.material_slot_remove_unused()
    minimum_z = min(vertex.co.z for vertex in result.data.vertices)
    if minimum_z < 0.02:
        lift = 0.02 - minimum_z
        for vertex in result.data.vertices:
            vertex.co.z += lift
    result.data.validate(clean_customdata=False)
    result.data.update()
    return result


def _assert_result() -> None:
    total_triangles = 0
    for slot in SLOTS:
        root = _require_object(f"Ruin_{slot}", "EMPTY")
        geometry = _require_object(f"Ruin_{slot}_Geometry", "MESH")
        if geometry.parent != root:
            raise RuntimeError(f"{geometry.name} left the slot root")
        if len(geometry.data.polygons) < 120:
            raise RuntimeError(f"{geometry.name} is unexpectedly sparse")
        if not geometry.data.materials:
            raise RuntimeError(f"{geometry.name} has no materials")
        names = {material.name for material in geometry.data.materials if material is not None}
        forbidden_materials = names & {"M_CanonicalDepthProjection", "M_SaltStainedGlass"}
        if forbidden_materials:
            raise RuntimeError(
                f"{geometry.name} still uses forbidden ruin materials: {sorted(forbidden_materials)}"
            )
        if not geometry.data.uv_layers:
            raise RuntimeError(f"{geometry.name} lost its authored UVs")
        if any(len(polygon.vertices) != 3 for polygon in geometry.data.polygons):
            raise RuntimeError(f"{geometry.name} must remain triangulated for stable tangents")
        total_triangles += len(geometry.data.polygons)
        minimum = Vector((
            min(vertex.co.x for vertex in geometry.data.vertices),
            min(vertex.co.y for vertex in geometry.data.vertices),
            min(vertex.co.z for vertex in geometry.data.vertices),
        ))
        maximum = Vector((
            max(vertex.co.x for vertex in geometry.data.vertices),
            max(vertex.co.y for vertex in geometry.data.vertices),
            max(vertex.co.z for vertex in geometry.data.vertices),
        ))
        local_dimensions = maximum - minimum
        if minimum.z < 0.019:
            raise RuntimeError(f"{geometry.name} sinks below the deck: z={minimum.z:.4f}")
        if local_dimensions.x > 5.9 or local_dimensions.y > 4.55:
            raise RuntimeError(
                f"{geometry.name} exceeds its stable slot footprint: "
                f"{tuple(round(value, 3) for value in local_dimensions)}"
            )

    if total_triangles > 7_000:
        raise RuntimeError(
            f"Start ruins exceed the shared 7k triangle budget: {total_triangles}"
        )

    for slot in SLOTS:
        _require_object(f"SlotAnchor_{slot}", "EMPTY")
        for level in range(1, 5):
            _require_object(f"Built_{slot}_L{level}", "EMPTY")


def rebuild() -> None:
    for material_name in {
        spec.material for specs in RUIN_PARTS.values() for spec in specs
    } | {
        "M_RustOxide",
        "M_WeatheredSteel",
        "M_DeepSteel",
        "M_BleachedWood",
        "M_WetRope",
        "M_RustDark",
        "M_GalvanizedSteel",
        "M_FadedBlueCanvas",
        "M_SafetyOchre",
    }:
        _require_material(material_name)

    for slot in SLOTS:
        root = _require_object(f"Ruin_{slot}", "EMPTY")
        source = _require_object(SOURCE_LEVEL_ONE[slot], "MESH")
        components = _connected_components(source)
        _remove_old_geometry(root)

        parts: list[bpy.types.Object] = []
        for index, spec in enumerate(RUIN_PARTS[slot]):
            component = _find_component(components, spec)
            parts.append(_extract_component(source, root, component, spec, index))
        parts.extend(_add_foundation_fragments(slot, root))
        parts.extend(_add_slot_identity(slot, root))
        _join_parts(root, parts)

    projection = bpy.data.materials.get("M_CanonicalDepthProjection")
    if projection is not None and projection.users == 0:
        bpy.data.materials.remove(projection)
    _assert_result()


def _root_descendants(root: bpy.types.Object) -> list[bpy.types.Object]:
    result = [root]
    stack = list(root.children)
    while stack:
        obj = stack.pop()
        result.append(obj)
        stack.extend(obj.children)
    return result


def export_glb(filepath: Path) -> None:
    filepath.parent.mkdir(parents=True, exist_ok=True)
    root = _require_object("Root", "EMPTY")
    export_objects = _root_descendants(root)
    visibility = {
        obj.name: (obj.hide_viewport, obj.hide_render, obj.hide_get())
        for obj in export_objects
    }
    bpy.ops.object.select_all(action="DESELECT")
    try:
        for obj in export_objects:
            obj.hide_viewport = False
            obj.hide_render = False
            obj.hide_set(False)
            obj.select_set(True)
        bpy.context.view_layer.objects.active = root
        bpy.ops.export_scene.gltf(
            filepath=str(filepath),
            check_existing=False,
            export_format="GLB",
            use_selection=True,
            use_visible=False,
            use_renderable=False,
            use_active_collection=False,
            use_active_scene=False,
            export_extras=True,
            export_cameras=False,
            export_lights=False,
            export_yup=True,
            export_apply=False,
            export_materials="EXPORT",
            export_image_format="AUTO",
            export_texcoords=True,
            export_normals=True,
            export_tangents=True,
            export_attributes=False,
            export_unused_images=True,
            export_unused_textures=True,
            export_skins=False,
            export_morph=False,
            export_animations=False,
            export_draco_mesh_compression_enable=False,
            export_meshopt_compression_enable=False,
            export_use_gltfpack=False,
        )
    finally:
        for obj in export_objects:
            hide_viewport, hide_render, hidden = visibility[obj.name]
            obj.hide_viewport = hide_viewport
            obj.hide_render = hide_render
            obj.hide_set(hidden)


def main() -> None:
    args = _arguments()
    if not bpy.data.filepath:
        raise RuntimeError("Open start_platform_ruins.blend before rebuilding ruins")
    rebuild()

    blend_path = Path(bpy.data.filepath).resolve()
    if args.save:
        bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    if args.export is not None:
        export_path = (
            Path(args.export).resolve()
            if args.export
            else blend_path.parent.parent / "start_platform_ruins.glb"
        )
        export_glb(export_path)
    print("START_RUINS_REBUILT")


if __name__ == "__main__":
    main()
