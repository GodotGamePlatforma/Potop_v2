class_name UnderwaterMapVisualSurveyPlan
extends RefCounted

## Public, presentation-only survey planner. The caller supplies one stable
## manifest snapshot, its canonical navigation raster and the real capture
## viewport. The result contains no landmark, structure or socket identifiers.

const SCHEMA_VERSION := 1
const BACKDROP_LAYERS := ["L01", "L02"]
const LANDMARK_APPROACH_DIRECTIONS := [
	Vector2.LEFT,
	Vector2.UP,
	Vector2.RIGHT,
	Vector2.DOWN,
]
const LANDMARK_APPROACH_VIEWPORT_RATIO := 0.32
const STRUCTURE_APPROACH_VIEWPORT_RATIO := 0.30
const VERTICAL_SECTOR_OVERLAP_RATIO := 0.25
const OVERVIEW_OVERLAP_RATIO := 0.10
const GAP_MAX_COVERAGE_RATIO := 0.20
const FLOAT_QUANTUM := 0.001
const FLOAT_EPSILON := 0.000001


static func build(
	manifest_snapshot: Dictionary,
	navigation_raster: Dictionary,
	viewport_size_pixels: Vector2i,
	camera_zoom: float = 1.0,
) -> Dictionary:
	var errors := PackedStringArray()
	var world_size := _manifest_world_size(manifest_snapshot, errors)
	var raster := _normalized_raster(navigation_raster, world_size, errors)
	if viewport_size_pixels.x <= 0 or viewport_size_pixels.y <= 0:
		errors.append("Visual survey wymaga dodatniego rozmiaru viewportu.")
	if not is_finite(camera_zoom) or camera_zoom <= 0.0:
		errors.append("Visual survey wymaga dodatniego, skończonego zoomu kamery.")
	if not errors.is_empty():
		return _failure(errors)

	var viewport_world_size := Vector2(viewport_size_pixels) / camera_zoom
	viewport_world_size = Vector2(
		minf(viewport_world_size.x, world_size.x),
		minf(viewport_world_size.y, world_size.y),
	)
	var targets: Array[Dictionary] = []
	_append_landmark_approaches(
		targets,
		manifest_snapshot,
		raster,
		world_size,
		viewport_world_size,
		errors,
	)
	var structure_coverage := _append_structure_entrance_approaches(
		targets,
		manifest_snapshot,
		raster,
		world_size,
		viewport_world_size,
		errors,
	)
	var vertical_band_count := _axis_centers(
		world_size.y,
		viewport_world_size.y,
		VERTICAL_SECTOR_OVERLAP_RATIO,
	).size()
	_append_vertical_sectors(
		targets,
		raster,
		world_size,
		viewport_world_size,
	)
	var overview_cells := _overview_cells(world_size, viewport_world_size)
	var gap_component_digests := _append_backdrop_gap_inspections(
		targets,
		manifest_snapshot,
		overview_cells,
		raster,
		world_size,
		viewport_world_size,
	)
	_append_overview_tiles(
		targets,
		overview_cells,
		raster,
		world_size,
		viewport_world_size,
	)
	if not errors.is_empty():
		return _failure(errors)

	var counts := {}
	for target: Dictionary in targets:
		var purpose := str(target.get("purpose", ""))
		counts[purpose] = int(counts.get(purpose, 0)) + 1
	var plan := {
		"schema_version": SCHEMA_VERSION,
		"manifest_snapshot_sha256": _canonical_json(manifest_snapshot).sha256_text(),
		"navigation_raster_sha256": _navigation_digest(raster),
		"viewport": {
			"pixel_size": [viewport_size_pixels.x, viewport_size_pixels.y],
			"camera_zoom": _quantized(camera_zoom),
			"world_footprint": _vector_record(viewport_world_size),
		},
		"world_size": _vector_record(world_size),
		"counts": counts,
		"coverage_contract": {
			"landmark_subject_count": (manifest_snapshot.get("landmarks", []) as Array).size(),
			"active_structure_count": int(structure_coverage.get("structure_count", 0)),
			"structure_opening_count": int(structure_coverage.get("opening_count", 0)),
			"structure_opening_side_count": int(structure_coverage.get("opening_count", 0)) * 2,
			"vertical_band_count": vertical_band_count,
			"gap_component_digests": gap_component_digests,
			"overview_tile_count": overview_cells.size(),
		},
		"targets": targets,
		"errors": [],
	}
	plan["plan_sha256"] = _canonical_json(plan).sha256_text()
	return plan


static func _manifest_world_size(manifest: Dictionary, errors: PackedStringArray) -> Vector2:
	var map_value: Variant = manifest.get("map", null)
	if not map_value is Dictionary:
		errors.append("Visual survey wymaga manifest.map.")
		return Vector2.ZERO
	var world_size := _vector_from_value((map_value as Dictionary).get("world_size", null))
	if not world_size.is_finite() or world_size.x <= 0.0 or world_size.y <= 0.0:
		errors.append("Visual survey wymaga dodatniego manifest.map.world_size.")
		return Vector2.ZERO
	return world_size


static func _normalized_raster(
	raster: Dictionary,
	world_size: Vector2,
	errors: PackedStringArray,
) -> Dictionary:
	var upstream_errors: Variant = raster.get("errors", [])
	if upstream_errors is Array or upstream_errors is PackedStringArray:
		for upstream_error: Variant in upstream_errors:
			errors.append(str(upstream_error))
	var width := int(raster.get("width", 0))
	var height := int(raster.get("height", 0))
	var cell_scale := _vector_from_value(raster.get("cell_scale", null))
	var cells := PackedByteArray()
	var cells_value: Variant = raster.get("cells", null)
	if cells_value is PackedByteArray:
		cells = (cells_value as PackedByteArray).duplicate()
	elif cells_value is Array:
		for cell_value: Variant in cells_value as Array:
			cells.append(clampi(int(cell_value), 0, 1))
	else:
		errors.append("Visual survey wymaga navigation_raster.cells.")
	if width <= 0 or height <= 0:
		errors.append("Visual survey wymaga dodatnich wymiarów rastra nawigacji.")
	if not cell_scale.is_finite() or cell_scale.x <= 0.0 or cell_scale.y <= 0.0:
		errors.append("Visual survey wymaga dodatniego navigation_raster.cell_scale.")
	if width > 0 and height > 0 and cells.size() != width * height:
		errors.append("Visual survey otrzymał raster o niezgodnej liczbie komórek.")
	if (
		world_size.is_finite()
		and world_size.x > 0.0
		and world_size.y > 0.0
		and cell_scale.is_finite()
		and cell_scale.x > 0.0
		and cell_scale.y > 0.0
		and not Vector2(width * cell_scale.x, height * cell_scale.y).is_equal_approx(world_size)
	):
		errors.append("Raster nawigacji nie pokrywa dokładnie rozmiaru świata survey.")
	var has_open_cell := false
	for cell_value: int in cells:
		if cell_value == 1:
			has_open_cell = true
			break
	if not cells.is_empty() and not has_open_cell:
		errors.append("Raster nawigacji survey nie zawiera otwartej wody.")
	return {
		"width": width,
		"height": height,
		"cell_scale": cell_scale,
		"cells": cells,
	}


static func _append_landmark_approaches(
	targets: Array[Dictionary],
	manifest: Dictionary,
	raster: Dictionary,
	world_size: Vector2,
	viewport_world_size: Vector2,
	errors: PackedStringArray,
) -> void:
	var landmarks_value: Variant = manifest.get("landmarks", [])
	if not landmarks_value is Array:
		errors.append("Visual survey wymaga tablicy landmarks.")
		return
	var records: Array[Dictionary] = []
	for landmark_value: Variant in landmarks_value as Array:
		if not landmark_value is Dictionary:
			errors.append("Visual survey otrzymał landmark niebędący obiektem.")
			continue
		var landmark: Dictionary = landmark_value as Dictionary
		var position: Vector2 = _vector_from_value(landmark.get("position", null))
		var size: Vector2 = _vector_from_value(landmark.get("size", null))
		var footprint := Rect2(position - size * 0.5, size)
		if not _rect_inside_world(footprint, world_size):
			errors.append("Visual survey otrzymał niepoprawną kopertę landmarku.")
			continue
		var identity_projection: Dictionary = {"footprint": _rect_record(footprint)}
		records.append({
			"digest": _canonical_json(identity_projection).sha256_text(),
			"footprint": footprint,
		})
	_sort_records_by_digest(records)
	var previous_digest: String = ""
	var duplicate_rank: int = 0
	var approach_margin: float = maxf(
		minf(viewport_world_size.x, viewport_world_size.y)
		* LANDMARK_APPROACH_VIEWPORT_RATIO,
		maxf(
			(raster.get("cell_scale", Vector2.ONE) as Vector2).x,
			(raster.get("cell_scale", Vector2.ONE) as Vector2).y,
		) * 3.0,
	)
	for record: Dictionary in records:
		var digest: String = str(record.get("digest", ""))
		if digest == previous_digest:
			duplicate_rank += 1
		else:
			previous_digest = digest
			duplicate_rank = 0
		var footprint: Rect2 = record.get("footprint", Rect2())
		var focus: Vector2 = footprint.get_center()
		var seen_anchor_cells: Dictionary = {}
		var appended: int = 0
		for direction: Vector2 in LANDMARK_APPROACH_DIRECTIONS:
			var edge_distance: float = (
				footprint.size.x * 0.5
				if not is_zero_approx(direction.x)
				else footprint.size.y * 0.5
			)
			var edge_position: Vector2 = focus + direction * edge_distance
			var candidate: Vector2 = edge_position + direction * approach_margin
			var anchor: Vector2 = _nearest_open_position(
				candidate,
				raster,
				edge_position,
				direction,
				footprint,
			)
			if not anchor.is_finite():
				continue
			var anchor_cell: Vector2i = _world_to_cell(anchor, raster)
			if seen_anchor_cells.has(anchor_cell):
				continue
			seen_anchor_cells[anchor_cell] = true
			var identity: Dictionary = {
				"subject": digest,
				"rank": duplicate_rank,
				"direction": _vector_record(direction),
			}
			targets.append(_target(
				"landmark_approach",
				anchor,
				anchor,
				focus,
				(focus - anchor).normalized(),
				viewport_world_size,
				world_size,
				false,
				identity,
				{
					"survey_subject": digest,
					"subject_rank": duplicate_rank,
					"landmark_footprint": _rect_record(footprint),
					"approach_direction": _vector_record(direction),
				},
			))
			appended += 1
		if appended == 0:
			var fallback: Vector2 = _nearest_open_position(
				focus,
				raster,
				Vector2.ZERO,
				Vector2.ZERO,
				footprint,
			)
			if not fallback.is_finite():
				errors.append("Visual survey nie znalazł otwartego podejścia do landmarku.")
				continue
			targets.append(_target(
				"landmark_approach",
				fallback,
				fallback,
				focus,
				Vector2.ZERO,
				viewport_world_size,
				world_size,
				false,
				{"subject": digest, "rank": duplicate_rank, "fallback": true},
				{
					"survey_subject": digest,
					"subject_rank": duplicate_rank,
					"landmark_footprint": _rect_record(footprint),
					"approach_direction": _vector_record(Vector2.ZERO),
				},
			))


static func _append_structure_entrance_approaches(
	targets: Array[Dictionary],
	manifest: Dictionary,
	raster: Dictionary,
	world_size: Vector2,
	viewport_world_size: Vector2,
	errors: PackedStringArray,
) -> Dictionary:
	var coverage := {"structure_count": 0, "opening_count": 0}
	var structures_value: Variant = manifest.get("structures", {})
	if not structures_value is Dictionary:
		errors.append("Visual survey wymaga obiektu structures.")
		return coverage
	var instances_value: Variant = (structures_value as Dictionary).get("instances", [])
	if not instances_value is Array:
		errors.append("Visual survey wymaga tablicy structures.instances.")
		return coverage
	var records: Array[Dictionary] = []
	for instance_value: Variant in instances_value as Array:
		if not instance_value is Dictionary:
			errors.append("Visual survey otrzymał strukturę niebędącą obiektem.")
			continue
		var instance := instance_value as Dictionary
		if not bool(instance.get("enabled", false)):
			continue
		var origin := _vector_from_value(instance.get("origin", null))
		var size := _vector_from_value(instance.get("size", null))
		var bounds := Rect2(origin, size)
		if not _rect_inside_world(bounds, world_size):
			errors.append("Visual survey otrzymał niepoprawną kopertę aktywnej struktury.")
			continue
		if not _rect_aligned_to_raster(bounds, raster):
			errors.append("Koperta aktywnej struktury survey nie jest wyrównana do rastra.")
			continue
		var geometry_projection := {
			"origin": _vector_record(origin),
			"size": _vector_record(size),
		}
		records.append({
			"digest": _canonical_json(geometry_projection).sha256_text(),
			"bounds": bounds,
		})
	_sort_records_by_digest(records)
	var approach_distance := maxf(
		minf(viewport_world_size.x, viewport_world_size.y)
		* STRUCTURE_APPROACH_VIEWPORT_RATIO,
		maxf(
			(raster.get("cell_scale", Vector2.ONE) as Vector2).x,
			(raster.get("cell_scale", Vector2.ONE) as Vector2).y,
		) * 3.0,
	)
	for record: Dictionary in records:
		coverage["structure_count"] = int(coverage["structure_count"]) + 1
		var bounds: Rect2 = record.get("bounds", Rect2())
		var envelope_digest := str(record.get("digest", ""))
		var openings := _detect_structure_openings(bounds, raster)
		if openings.is_empty():
			errors.append("Visual survey nie znalazł wejścia aktywnej struktury.")
		for opening: Dictionary in openings:
			var opening_center: Vector2 = opening.get("center", Vector2.ZERO)
			var outward: Vector2 = opening.get("outward", Vector2.ZERO)
			if outward.is_zero_approx():
				errors.append("Visual survey otrzymał wejście struktury bez kierunku zewnętrznego.")
				continue
			var opening_identity := {
				"envelope": envelope_digest,
				"opening_center": _vector_record(opening_center),
				"outward": _vector_record(outward),
				"span": _quantized(float(opening.get("span", 0.0))),
			}
			var opening_digest := _canonical_json(opening_identity).sha256_text()
			coverage["opening_count"] = int(coverage["opening_count"]) + 1
			var appended_sides := 0
			for side_sign: float in [1.0, -1.0]:
				var side_normal := outward * side_sign
				var candidate := opening_center + side_normal * approach_distance
				var anchor := _nearest_open_position(
					candidate,
					raster,
					opening_center,
					side_normal,
				)
				if not anchor.is_finite():
					continue
				var identity := {
					"envelope": envelope_digest,
					"opening_center": _vector_record(opening_center),
					"outward": _vector_record(outward),
					"span": _quantized(float(opening.get("span", 0.0))),
					"side": int(side_sign),
				}
				targets.append(_target(
					"structure_entrance_approach",
					anchor,
					anchor,
					opening_center,
					(opening_center - anchor).normalized(),
					viewport_world_size,
					world_size,
					false,
					identity,
					{
						"structure_envelope": envelope_digest,
						"structure_bounds": _rect_record(bounds),
						"opening_digest": opening_digest,
						"opening_center": _vector_record(opening_center),
						"approach_side": int(side_sign),
					},
				))
				appended_sides += 1
			if appended_sides != 2:
				errors.append(
					"Visual survey nie znalazł obu stron podejścia do wejścia struktury."
				)
	return coverage


static func _detect_structure_openings(bounds: Rect2, raster: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var scale: Vector2 = raster.get("cell_scale", Vector2.ONE)
	var left := roundi(bounds.position.x / scale.x)
	var right_exclusive := roundi(bounds.end.x / scale.x)
	var top := roundi(bounds.position.y / scale.y)
	var bottom_exclusive := roundi(bounds.end.y / scale.y)
	_append_boundary_opening_runs(
		result, raster, top, bottom_exclusive, left, left - 1,
		true, bounds.position.x, Vector2.LEFT,
	)
	_append_boundary_opening_runs(
		result, raster, top, bottom_exclusive, right_exclusive - 1, right_exclusive,
		true, bounds.end.x, Vector2.RIGHT,
	)
	_append_boundary_opening_runs(
		result, raster, left, right_exclusive, top, top - 1,
		false, bounds.position.y, Vector2.UP,
	)
	_append_boundary_opening_runs(
		result, raster, left, right_exclusive, bottom_exclusive - 1, bottom_exclusive,
		false, bounds.end.y, Vector2.DOWN,
	)
	return result


static func _append_boundary_opening_runs(
	result: Array[Dictionary],
	raster: Dictionary,
	scan_start: int,
	scan_end_exclusive: int,
	inside_fixed: int,
	outside_fixed: int,
	vertical_scan: bool,
	boundary_coordinate: float,
	outward: Vector2,
) -> void:
	var run_start := -1
	for cursor in range(scan_start, scan_end_exclusive + 1):
		var is_open := false
		if cursor < scan_end_exclusive:
			var inside := (
				Vector2i(inside_fixed, cursor)
				if vertical_scan
				else Vector2i(cursor, inside_fixed)
			)
			var outside := (
				Vector2i(outside_fixed, cursor)
				if vertical_scan
				else Vector2i(cursor, outside_fixed)
			)
			is_open = _cell_is_open(inside, raster) and _cell_is_open(outside, raster)
		if is_open and run_start < 0:
			run_start = cursor
		elif not is_open and run_start >= 0:
			var scale: Vector2 = raster.get("cell_scale", Vector2.ONE)
			var variable_center := float(run_start + cursor) * 0.5
			var center := (
				Vector2(boundary_coordinate, variable_center * scale.y)
				if vertical_scan
				else Vector2(variable_center * scale.x, boundary_coordinate)
			)
			var span := float(cursor - run_start) * (scale.y if vertical_scan else scale.x)
			result.append({"center": center, "outward": outward, "span": span})
			run_start = -1


static func _append_vertical_sectors(
	targets: Array[Dictionary],
	raster: Dictionary,
	world_size: Vector2,
	viewport_world_size: Vector2,
) -> void:
	var centers := _axis_centers(
		world_size.y,
		viewport_world_size.y,
		VERTICAL_SECTOR_OVERLAP_RATIO,
	)
	for index in range(centers.size()):
		var focus := Vector2(world_size.x * 0.5, float(centers[index]))
		var anchor := _nearest_open_position(focus, raster)
		if not anchor.is_finite():
			continue
		targets.append(_target(
			"vertical_sector",
			focus,
			anchor,
			focus,
			Vector2.ZERO,
			viewport_world_size,
			world_size,
			false,
			{
				"band": index,
				"ratio": _quantized(focus.y / world_size.y),
			},
			{
				"vertical_band": index,
				"vertical_ratio": _quantized(focus.y / world_size.y),
			},
		))


static func _overview_cells(
	world_size: Vector2,
	viewport_world_size: Vector2,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var x_centers := _axis_centers(
		world_size.x,
		viewport_world_size.x,
		OVERVIEW_OVERLAP_RATIO,
	)
	var y_centers := _axis_centers(
		world_size.y,
		viewport_world_size.y,
		OVERVIEW_OVERLAP_RATIO,
	)
	for y_index in range(y_centers.size()):
		for x_index in range(x_centers.size()):
			var center := Vector2(float(x_centers[x_index]), float(y_centers[y_index]))
			var stitch_left: float = (
				0.0
				if x_index == 0
				else (float(x_centers[x_index - 1]) + center.x) * 0.5
			)
			var stitch_right: float = (
				world_size.x
				if x_index == x_centers.size() - 1
				else (center.x + float(x_centers[x_index + 1])) * 0.5
			)
			var stitch_top: float = (
				0.0
				if y_index == 0
				else (float(y_centers[y_index - 1]) + center.y) * 0.5
			)
			var stitch_bottom: float = (
				world_size.y
				if y_index == y_centers.size() - 1
				else (center.y + float(y_centers[y_index + 1])) * 0.5
			)
			result.append({
				"grid": Vector2i(x_index, y_index),
				"center": center,
				"rect": Rect2(center - viewport_world_size * 0.5, viewport_world_size),
				"stitch_rect": Rect2(
					Vector2(stitch_left, stitch_top),
					Vector2(stitch_right - stitch_left, stitch_bottom - stitch_top),
				),
			})
	return result


static func _append_overview_tiles(
	targets: Array[Dictionary],
	overview_cells: Array[Dictionary],
	raster: Dictionary,
	world_size: Vector2,
	viewport_world_size: Vector2,
) -> void:
	for cell: Dictionary in overview_cells:
		var center: Vector2 = cell.get("center", Vector2.ZERO)
		var anchor := _nearest_open_position(center, raster)
		if not anchor.is_finite():
			continue
		var grid: Vector2i = cell.get("grid", Vector2i.ZERO)
		targets.append(_target(
			"overview_tile",
			center,
			anchor,
			center,
			Vector2.ZERO,
			viewport_world_size,
			world_size,
			false,
			{
				"grid": [grid.x, grid.y],
				"stitch_world_rect": _rect_record(
					cell.get("stitch_rect", Rect2()) as Rect2
				),
			},
			{
				"overview_grid": [grid.x, grid.y],
				"stitch_world_rect": _rect_record(
					cell.get("stitch_rect", Rect2()) as Rect2
				),
			},
		))


static func _append_backdrop_gap_inspections(
	targets: Array[Dictionary],
	manifest: Dictionary,
	overview_cells: Array[Dictionary],
	raster: Dictionary,
	world_size: Vector2,
	viewport_world_size: Vector2,
) -> Dictionary:
	var gap_components_by_layer := {}
	var layer_data_by_id := _backdrop_layer_data(manifest, world_size)
	for layer_id: String in BACKDROP_LAYERS:
		var layer_component_digests: Array[String] = []
		var layer_data: Dictionary = layer_data_by_id.get(layer_id, {})
		var rects: Array[Rect2] = []
		var rect_values: Variant = layer_data.get("rects", [])
		if rect_values is Array:
			for rect_value: Variant in rect_values as Array:
				if rect_value is Rect2:
					rects.append(rect_value as Rect2)
		var parallax_scale := layer_data.get("parallax_scale", Vector2.ONE) as Vector2
		var sparse_cells: Array[Dictionary] = []
		for overview_cell: Dictionary in overview_cells:
			var inspection_center: Vector2 = overview_cell.get("center", Vector2.ZERO)
			var inspection_rect := Rect2(
				inspection_center * parallax_scale - viewport_world_size * 0.5,
				viewport_world_size,
			)
			var coverage_ratio := 0.0
			if inspection_rect.has_area():
				coverage_ratio = _union_area_clipped(rects, inspection_rect) / inspection_rect.get_area()
			if coverage_ratio <= GAP_MAX_COVERAGE_RATIO + FLOAT_EPSILON:
				var sparse := overview_cell.duplicate(true)
				sparse["coverage_ratio"] = coverage_ratio
				sparse_cells.append(sparse)
		var components: Array = _grid_components(sparse_cells)
		for component: Array in components:
			var component_grid := []
			for component_cell: Dictionary in component:
				var component_grid_position: Vector2i = component_cell.get(
					"grid", Vector2i.ZERO
				)
				component_grid.append([
					component_grid_position.x,
					component_grid_position.y,
				])
			var component_digest := _canonical_json({
				"layer": layer_id,
				"grid": component_grid,
			}).sha256_text()
			layer_component_digests.append(component_digest)
			for sample: Dictionary in _farthest_component_samples(component):
				var center: Vector2 = sample.get("center", Vector2.ZERO)
				var anchor := _nearest_open_position(center, raster)
				if not anchor.is_finite():
					continue
				var grid: Vector2i = sample.get("grid", Vector2i.ZERO)
				var coverage_ratio := float(sample.get("coverage_ratio", 0.0))
				var public_metadata := {
					"inspection_scope": layer_id,
					"gap_component": component_digest,
					"coverage_ratio": _quantized(coverage_ratio),
				}
				targets.append(_target(
					"backdrop_gap_inspection",
					center,
					anchor,
					center,
					Vector2.ZERO,
					viewport_world_size,
					world_size,
					true,
					{
						"layer": layer_id,
						"component": component_digest,
						"grid": [grid.x, grid.y],
						"coverage_ratio": _quantized(coverage_ratio),
					},
					public_metadata,
				))
		gap_components_by_layer[layer_id] = layer_component_digests
	return gap_components_by_layer


static func _backdrop_layer_data(
	manifest: Dictionary,
	world_size: Vector2,
) -> Dictionary:
	var result := {
		"L01": {"rects": [], "parallax_scale": Vector2.ONE},
		"L02": {"rects": [], "parallax_scale": Vector2.ONE},
	}
	var visual_value: Variant = manifest.get("visual", {})
	if not visual_value is Dictionary:
		return result
	var visual := visual_value as Dictionary
	var layers_value: Variant = visual.get("layers", [])
	if layers_value is Array:
		for layer_value: Variant in layers_value as Array:
			if not layer_value is Dictionary:
				continue
			var layer := layer_value as Dictionary
			var layer_id := str(layer.get("id", ""))
			if layer_id not in BACKDROP_LAYERS:
				continue
			var parallax_scale := _vector_from_value(layer.get("parallax_scale", null))
			if (
				parallax_scale.is_finite()
				and parallax_scale.x > 0.0
				and parallax_scale.y > 0.0
			):
				var layer_record_data: Dictionary = result[layer_id]
				layer_record_data["parallax_scale"] = parallax_scale
				result[layer_id] = layer_record_data
	var assets_value: Variant = visual.get("assets", [])
	if not assets_value is Array:
		return result
	var world_bounds := Rect2(Vector2.ZERO, world_size)
	for asset_value: Variant in assets_value as Array:
		if not asset_value is Dictionary:
			continue
		var asset := asset_value as Dictionary
		if not bool(asset.get("enabled", false)):
			continue
		var layer_id := str(asset.get("layer_id", ""))
		if layer_id not in BACKDROP_LAYERS:
			continue
		var asset_rect := _rect_from_value(asset.get("world_rect", null))
		if not asset_rect.has_area():
			continue
		var clipped := asset_rect.intersection(world_bounds)
		if clipped.has_area():
			var asset_layer_data: Dictionary = result[layer_id]
			var rects: Array = asset_layer_data.get("rects", [])
			rects.append(clipped)
			asset_layer_data["rects"] = rects
			result[layer_id] = asset_layer_data
	return result


static func _grid_components(cells: Array[Dictionary]) -> Array:
	var result: Array = []
	var by_grid := {}
	for cell: Dictionary in cells:
		by_grid[cell.get("grid", Vector2i.ZERO)] = cell
	var visited := {}
	for seed: Dictionary in cells:
		var seed_grid: Vector2i = seed.get("grid", Vector2i.ZERO)
		if visited.has(seed_grid):
			continue
		var component: Array[Dictionary] = []
		var queue: Array[Vector2i] = [seed_grid]
		visited[seed_grid] = true
		var cursor := 0
		while cursor < queue.size():
			var current := queue[cursor]
			cursor += 1
			component.append(by_grid[current] as Dictionary)
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
				var neighbor := current + direction
				if by_grid.has(neighbor) and not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
		result.append(component)
	return result


static func _farthest_component_samples(component: Array) -> Array[Dictionary]:
	if component.is_empty():
		return []
	var sample_count := mini(component.size(), maxi(1, ceili(sqrt(float(component.size())))))
	var centroid := Vector2.ZERO
	for cell: Dictionary in component:
		centroid += cell.get("center", Vector2.ZERO) as Vector2
	centroid /= float(component.size())
	var selected: Array[Dictionary] = []
	var selected_grids := {}
	var first: Dictionary = component[0] as Dictionary
	var first_distance := INF
	for candidate: Dictionary in component:
		var candidate_center: Vector2 = candidate.get("center", Vector2.ZERO)
		var distance := candidate_center.distance_squared_to(centroid)
		if (
			distance < first_distance - FLOAT_EPSILON
			or is_equal_approx(distance, first_distance)
			and _grid_less(candidate, first)
		):
			first = candidate
			first_distance = distance
	selected.append(first)
	selected_grids[first.get("grid", Vector2i.ZERO)] = true
	while selected.size() < sample_count:
		var best: Dictionary = {}
		var best_distance := -1.0
		for candidate: Dictionary in component:
			var candidate_grid: Vector2i = candidate.get("grid", Vector2i.ZERO)
			if selected_grids.has(candidate_grid):
				continue
			var candidate_center: Vector2 = candidate.get("center", Vector2.ZERO)
			var nearest_selected_distance := INF
			for selected_cell: Dictionary in selected:
				var selected_center: Vector2 = selected_cell.get("center", Vector2.ZERO)
				nearest_selected_distance = minf(
					nearest_selected_distance,
					candidate_center.distance_squared_to(selected_center),
				)
			if (
				nearest_selected_distance > best_distance + FLOAT_EPSILON
				or is_equal_approx(nearest_selected_distance, best_distance)
				and (best.is_empty() or _grid_less(candidate, best))
			):
				best = candidate
				best_distance = nearest_selected_distance
		if best.is_empty():
			break
		selected.append(best)
		selected_grids[best.get("grid", Vector2i.ZERO)] = true
	return selected


static func _grid_less(left: Dictionary, right: Dictionary) -> bool:
	var left_grid: Vector2i = left.get("grid", Vector2i.ZERO)
	var right_grid: Vector2i = right.get("grid", Vector2i.ZERO)
	return left_grid.y < right_grid.y or (
		left_grid.y == right_grid.y and left_grid.x < right_grid.x
	)


static func _union_area_clipped(rects: Array[Rect2], clip_rect: Rect2) -> float:
	var clipped_rects: Array[Rect2] = []
	var x_values: Array[float] = [clip_rect.position.x, clip_rect.end.x]
	for source_rect: Rect2 in rects:
		var clipped := source_rect.intersection(clip_rect)
		if not clipped.has_area():
			continue
		clipped_rects.append(clipped)
		_append_unique_float(x_values, clipped.position.x)
		_append_unique_float(x_values, clipped.end.x)
	if clipped_rects.is_empty():
		return 0.0
	x_values.sort()
	var area := 0.0
	for x_index in range(x_values.size() - 1):
		var x_start := x_values[x_index]
		var x_end := x_values[x_index + 1]
		if x_end <= x_start + FLOAT_EPSILON:
			continue
		var x_mid := (x_start + x_end) * 0.5
		var intervals: Array[Vector2] = []
		for clipped: Rect2 in clipped_rects:
			if x_mid >= clipped.position.x and x_mid < clipped.end.x:
				intervals.append(Vector2(clipped.position.y, clipped.end.y))
		_sort_intervals(intervals)
		var covered_y := 0.0
		var active_start := 0.0
		var active_end := 0.0
		var has_active := false
		for interval: Vector2 in intervals:
			if not has_active:
				active_start = interval.x
				active_end = interval.y
				has_active = true
			elif interval.x <= active_end + FLOAT_EPSILON:
				active_end = maxf(active_end, interval.y)
			else:
				covered_y += active_end - active_start
				active_start = interval.x
				active_end = interval.y
		if has_active:
			covered_y += active_end - active_start
		area += (x_end - x_start) * covered_y
	return area


static func _sort_intervals(intervals: Array[Vector2]) -> void:
	for index in range(1, intervals.size()):
		var current := intervals[index]
		var cursor := index - 1
		while cursor >= 0 and (
			intervals[cursor].x > current.x
			or is_equal_approx(intervals[cursor].x, current.x)
			and intervals[cursor].y > current.y
		):
			intervals[cursor + 1] = intervals[cursor]
			cursor -= 1
		intervals[cursor + 1] = current


static func _append_unique_float(values: Array[float], value: float) -> void:
	for existing: float in values:
		if is_equal_approx(existing, value):
			return
	values.append(value)


static func _axis_centers(length: float, footprint: float, overlap_ratio: float) -> Array[float]:
	var result: Array[float] = []
	var safe_footprint := minf(maxf(footprint, FLOAT_QUANTUM), length)
	if length <= safe_footprint + FLOAT_EPSILON:
		return [length * 0.5]
	var first := safe_footprint * 0.5
	var last := length - safe_footprint * 0.5
	var step := maxf(safe_footprint * (1.0 - overlap_ratio), FLOAT_QUANTUM)
	var center := first
	while center < last - FLOAT_EPSILON:
		result.append(center)
		center += step
	if result.is_empty() or not is_equal_approx(result[result.size() - 1], last):
		result.append(last)
	return result


static func _target(
	purpose: String,
	desired_camera_center: Vector2,
	anchor_position: Vector2,
	focus_position: Vector2,
	facing: Vector2,
	viewport_world_size: Vector2,
	world_size: Vector2,
	inspection_only: bool,
	identity_material: Dictionary,
	public_metadata: Dictionary = {},
) -> Dictionary:
	var camera_center := _clamped_camera_center(
		desired_camera_center,
		world_size,
		viewport_world_size,
	)
	var visible_rect := Rect2(
		camera_center - viewport_world_size * 0.5,
		viewport_world_size,
	)
	var key_projection := {
		"purpose": purpose,
		"camera_center": _vector_record(camera_center),
		"anchor_position": _vector_record(anchor_position),
		"focus_position": _vector_record(focus_position),
		"facing": _vector_record(facing),
		"identity": identity_material,
	}
	var result := {
		"key": _canonical_json(key_projection).sha256_text(),
		"purpose": purpose,
		"camera_center": _vector_record(camera_center),
		"anchor_position": _vector_record(anchor_position),
		"focus_position": _vector_record(focus_position),
		"facing": _vector_record(facing),
		"visible_world_rect": _rect_record(visible_rect),
		"inspection_only": inspection_only,
	}
	for metadata_key: Variant in public_metadata.keys():
		result[str(metadata_key)] = public_metadata[metadata_key]
	return result


static func _clamped_camera_center(
	candidate: Vector2,
	world_size: Vector2,
	viewport_world_size: Vector2,
) -> Vector2:
	var half := viewport_world_size * 0.5
	return Vector2(
		world_size.x * 0.5
		if world_size.x <= viewport_world_size.x
		else clampf(candidate.x, half.x, world_size.x - half.x),
		world_size.y * 0.5
		if world_size.y <= viewport_world_size.y
		else clampf(candidate.y, half.y, world_size.y - half.y),
	)


static func _nearest_open_position(
	candidate: Vector2,
	raster: Dictionary,
	constraint_origin: Vector2 = Vector2.ZERO,
	constraint_normal: Vector2 = Vector2.ZERO,
	excluded_footprint: Rect2 = Rect2(),
) -> Vector2:
	var width := int(raster.get("width", 0))
	var height := int(raster.get("height", 0))
	var scale: Vector2 = raster.get("cell_scale", Vector2.ONE)
	if width <= 0 or height <= 0:
		return Vector2(INF, INF)
	var start := Vector2i(
		clampi(floori(candidate.x / scale.x), 0, width - 1),
		clampi(floori(candidate.y / scale.y), 0, height - 1),
	)
	var maximum_radius := maxi(width, height)
	for radius in range(maximum_radius + 1):
		var minimum := Vector2i(maxi(start.x - radius, 0), maxi(start.y - radius, 0))
		var maximum := Vector2i(mini(start.x + radius, width - 1), mini(start.y + radius, height - 1))
		var best := Vector2(INF, INF)
		var best_distance := INF
		for y in range(minimum.y, maximum.y + 1):
			for x in range(minimum.x, maximum.x + 1):
				if radius > 0 and x > minimum.x and x < maximum.x and y > minimum.y and y < maximum.y:
					continue
				if not _cell_is_open(Vector2i(x, y), raster):
					continue
				var position := Vector2((x + 0.5) * scale.x, (y + 0.5) * scale.y)
				if (
					excluded_footprint.has_area()
					and excluded_footprint.grow(FLOAT_EPSILON).has_point(position)
				):
					continue
				if (
					not constraint_normal.is_zero_approx()
					and (position - constraint_origin).dot(constraint_normal) < -FLOAT_EPSILON
				):
					continue
				var distance := position.distance_squared_to(candidate)
				if (
					distance < best_distance - FLOAT_EPSILON
					or is_equal_approx(distance, best_distance)
					and (position.y < best.y or is_equal_approx(position.y, best.y) and position.x < best.x)
				):
					best = position
					best_distance = distance
		if best.is_finite():
			return best
	return Vector2(INF, INF)


static func _cell_is_open(cell: Vector2i, raster: Dictionary) -> bool:
	var width := int(raster.get("width", 0))
	var height := int(raster.get("height", 0))
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return false
	var cells: PackedByteArray = raster.get("cells", PackedByteArray())
	return int(cells[cell.y * width + cell.x]) == 1


static func _world_to_cell(world_position: Vector2, raster: Dictionary) -> Vector2i:
	var scale: Vector2 = raster.get("cell_scale", Vector2.ONE)
	return Vector2i(floori(world_position.x / scale.x), floori(world_position.y / scale.y))


static func _rect_aligned_to_raster(bounds: Rect2, raster: Dictionary) -> bool:
	var scale: Vector2 = raster.get("cell_scale", Vector2.ONE)
	for value: float in [
		bounds.position.x / scale.x,
		bounds.position.y / scale.y,
		bounds.end.x / scale.x,
		bounds.end.y / scale.y,
	]:
		if not is_equal_approx(value, round(value)):
			return false
	return true


static func _point_inside_world(point: Vector2, world_size: Vector2) -> bool:
	return (
		point.is_finite()
		and point.x >= 0.0
		and point.y >= 0.0
		and point.x <= world_size.x
		and point.y <= world_size.y
	)


static func _rect_inside_world(bounds: Rect2, world_size: Vector2) -> bool:
	return (
		bounds.has_area()
		and bounds.position.is_finite()
		and bounds.size.is_finite()
		and bounds.position.x >= 0.0
		and bounds.position.y >= 0.0
		and bounds.end.x <= world_size.x
		and bounds.end.y <= world_size.y
	)


static func _sort_records_by_digest(records: Array[Dictionary]) -> void:
	for index in range(1, records.size()):
		var current := records[index]
		var cursor := index - 1
		while cursor >= 0 and str(records[cursor].get("digest", "")) > str(current.get("digest", "")):
			records[cursor + 1] = records[cursor]
			cursor -= 1
		records[cursor + 1] = current


static func _navigation_digest(raster: Dictionary) -> String:
	var cells: PackedByteArray = raster.get("cells", PackedByteArray())
	var projection := {
		"width": int(raster.get("width", 0)),
		"height": int(raster.get("height", 0)),
		"cell_scale": _vector_record(raster.get("cell_scale", Vector2.ONE)),
		"cells_sha256": cells.hex_encode().sha256_text(),
	}
	return _canonical_json(projection).sha256_text()


static func _failure(errors: PackedStringArray) -> Dictionary:
	var error_list: Array[String] = []
	for error: String in errors:
		error_list.append(error)
	return {
		"schema_version": SCHEMA_VERSION,
		"manifest_snapshot_sha256": "",
		"navigation_raster_sha256": "",
		"counts": {},
		"targets": [],
		"errors": error_list,
		"plan_sha256": "",
	}


static func _vector_from_value(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Vector2i:
		return Vector2(value as Vector2i)
	if value is Array and (value as Array).size() == 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2(INF, INF)


static func _rect_from_value(value: Variant) -> Rect2:
	if value is Rect2:
		return value as Rect2
	if value is Rect2i:
		return Rect2(value as Rect2i)
	if value is Array and (value as Array).size() == 4:
		return Rect2(
			float((value as Array)[0]),
			float((value as Array)[1]),
			float((value as Array)[2]),
			float((value as Array)[3]),
		)
	return Rect2()


static func _vector_record(value: Variant) -> Array:
	var vector := _vector_from_value(value)
	return [_quantized(vector.x), _quantized(vector.y)]


static func _rect_record(rect: Rect2) -> Array:
	return [
		_quantized(rect.position.x),
		_quantized(rect.position.y),
		_quantized(rect.size.x),
		_quantized(rect.size.y),
	]


static func _quantized(value: float) -> float:
	return round(value / FLOAT_QUANTUM) * FLOAT_QUANTUM


static func _canonical_json(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			return str(_quantized(float(value)))
		TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(str(value))
		TYPE_VECTOR2:
			return _canonical_json(_vector_record(value))
		TYPE_VECTOR2I:
			var vector := value as Vector2i
			return _canonical_json([vector.x, vector.y])
		TYPE_RECT2:
			return _canonical_json(_rect_record(value as Rect2))
		TYPE_RECT2I:
			return _canonical_json(_rect_record(Rect2(value as Rect2i)))
		TYPE_ARRAY:
			var item_parts := PackedStringArray()
			for item: Variant in value as Array:
				item_parts.append(_canonical_json(item))
			return "[%s]" % ",".join(item_parts)
		TYPE_DICTIONARY:
			var dictionary := value as Dictionary
			var keys := PackedStringArray()
			for key: Variant in dictionary.keys():
				keys.append(str(key))
			keys.sort()
			var field_parts := PackedStringArray()
			for key: String in keys:
				field_parts.append(
					"%s:%s" % [JSON.stringify(key), _canonical_json(dictionary.get(key))]
				)
			return "{%s}" % ",".join(field_parts)
		TYPE_PACKED_BYTE_ARRAY:
			return JSON.stringify((value as PackedByteArray).hex_encode())
		TYPE_PACKED_STRING_ARRAY:
			var string_items := PackedStringArray()
			for item: String in value as PackedStringArray:
				string_items.append(JSON.stringify(item))
			return "[%s]" % ",".join(string_items)
		_:
			return JSON.stringify(str(value))
