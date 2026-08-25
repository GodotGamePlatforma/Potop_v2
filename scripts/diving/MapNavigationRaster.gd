class_name MapNavigationRaster
extends RefCounted

static var _cached_rasters: Dictionary = {}

## Shared composition of the manifest-derived semantic terrain cells plus local
## MapObstacle records into the runtime navigation grid. The image entry point
## remains an adapter for fixtures and derivative checks; production gameplay
## consumes build_from_cells() from the workbench compiler output.
##
## Passing a positive chunk_size additionally exposes
## boundary_segments_by_chunk. Its x:y keys identify the chunk containing the
## traversable source cell that emitted each segment; global boundary_segments
## remain byte-for-byte compatible with the ungrouped result.

static func build(
	image: Image,
	world_size: Vector2,
	obstacle_spawns: Array,
	chunk_size: int = 0,
	include_boundary_data: bool = true
) -> Dictionary:
	if image == null or image.is_empty():
		return {"errors": PackedStringArray(["Nie można odczytać tekstury nawigacji sceny mapy."])}
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return {"errors": PackedStringArray(["Tekstura nawigacji sceny mapy ma nieprawidłowy rozmiar."])}
	var cells := PackedByteArray()
	cells.resize(width * height)
	for y in range(height):
		for x in range(width):
			# Preserve the established map-mask contract: bright pixels are
			# blocked (0), darker pixels are traversable (1).
			cells[y * width + x] = 0 if image.get_pixel(x, y).r > 0.5 else 1
	return build_from_cells(
		cells,
		width,
		height,
		world_size,
		obstacle_spawns,
		chunk_size,
		include_boundary_data
	)


## Applies manifest-authored obstacles and derives collision boundaries from an
## already compiled semantic terrain raster. The input array is never mutated;
## this lets the manifest-derived base raster be cached and shared by compiler
## and runtime without obstacle records leaking between calls.
static func build_from_cells(
	base_cells: PackedByteArray,
	width: int,
	height: int,
	world_size: Vector2,
	obstacle_spawns: Array,
	chunk_size: int = 0,
	include_boundary_data: bool = true
) -> Dictionary:
	var errors := PackedStringArray()
	if width <= 0 or height <= 0 or base_cells.size() != width * height:
		errors.append("Scenowy raster makroterenu ma nieprawidłowy rozmiar.")
		return {"errors": errors}
	if world_size.x <= 0.0 or world_size.y <= 0.0:
		errors.append("Scena mapy ma nieprawidłowy rozmiar świata.")
		return {"errors": errors}

	var cell_scale := Vector2(world_size.x / float(width), world_size.y / float(height))
	var cells := base_cells.duplicate()

	for raw_record in obstacle_spawns:
		if not (raw_record is Dictionary):
			errors.append("Scena mapy zawiera przeszkodę o nieprawidłowym rekordzie.")
			continue
		var record: Dictionary = raw_record
		if not bool(record.get("blocks_navigation", true)):
			continue
		var polygon := polygon_for_record(record)
		if polygon.size() < 3:
			errors.append("Przeszkoda %s nie ma poprawnego obrysu nawigacyjnego." % str(record.get("id", "")))
			continue
		_rasterize_blocking_polygon(cells, width, height, cell_scale, polygon)
	var boundary_data: Dictionary = {}
	if include_boundary_data:
		boundary_data = _build_boundary_data(
			cells,
			width,
			height,
			cell_scale,
			chunk_size
		)

	return {
		"errors": errors,
		"cells": cells,
		"width": width,
		"height": height,
		"cell_scale": cell_scale,
		"boundary_segments": boundary_data.get("segments", PackedVector2Array()),
		"boundary_segments_by_chunk": boundary_data.get("segments_by_chunk", {}),
	}


static func build_cached(
	cache_key: String,
	image: Image,
	world_size: Vector2,
	obstacle_spawns: Array,
	chunk_size: int = 0,
	include_boundary_data: bool = true
) -> Dictionary:
	if cache_key.is_empty():
		return build(image, world_size, obstacle_spawns, chunk_size, include_boundary_data)
	var effective_cache_key := "%s|collision_chunk=%d|boundary=%d" % [
		cache_key,
		maxi(chunk_size, 0),
		int(include_boundary_data),
	]
	if _cached_rasters.has(effective_cache_key):
		return (_cached_rasters[effective_cache_key] as Dictionary).duplicate(true)
	var raster := build(image, world_size, obstacle_spawns, chunk_size, include_boundary_data)
	if (raster.get("errors", PackedStringArray()) as PackedStringArray).is_empty():
		_cached_rasters[effective_cache_key] = raster.duplicate(true)
	return raster


static func build_from_cells_cached(
	cache_key: String,
	base_cells: PackedByteArray,
	width: int,
	height: int,
	world_size: Vector2,
	obstacle_spawns: Array,
	chunk_size: int = 0,
	include_boundary_data: bool = true
) -> Dictionary:
	if cache_key.is_empty():
		return build_from_cells(
			base_cells,
			width,
			height,
			world_size,
			obstacle_spawns,
			chunk_size,
			include_boundary_data
		)
	var effective_cache_key := "%s|scene_cells=%dx%d|collision_chunk=%d|boundary=%d" % [
		cache_key,
		width,
		height,
		maxi(chunk_size, 0),
		int(include_boundary_data),
	]
	if _cached_rasters.has(effective_cache_key):
		return (_cached_rasters[effective_cache_key] as Dictionary).duplicate(true)
	var raster := build_from_cells(
		base_cells,
		width,
		height,
		world_size,
		obstacle_spawns,
		chunk_size,
		include_boundary_data
	)
	if (raster.get("errors", PackedStringArray()) as PackedStringArray).is_empty():
		_cached_rasters[effective_cache_key] = raster.duplicate(true)
	return raster


static func boundary_segments_by_chunk(
	cells: PackedByteArray,
	width: int,
	height: int,
	cell_scale: Vector2,
	chunk_size: int
) -> Dictionary:
	if (
		chunk_size <= 0
		or width <= 0
		or height <= 0
		or cells.size() < width * height
		or cell_scale.x <= 0.0
		or cell_scale.y <= 0.0
	):
		return {}
	var boundary_data := _build_boundary_data(
		cells,
		width,
		height,
		cell_scale,
		chunk_size
	)
	return (boundary_data.get("segments_by_chunk", {}) as Dictionary).duplicate(true)


static func polygon_for_record(record: Dictionary) -> PackedVector2Array:
	var authored = record.get("navigation_polygon", PackedVector2Array())
	if typeof(authored) == TYPE_PACKED_VECTOR2_ARRAY and authored.size() >= 3:
		return authored

	var center: Vector2 = record.get("position", Vector2.ZERO)
	var size: Vector2 = record.get("size", Vector2.ONE)
	var object_scale: Vector2 = record.get("object_scale", record.get("scale", Vector2.ONE))
	var rotation := float(record.get("rotation", 0.0))
	var skew := float(record.get("skew", 0.0))
	var transform := Transform2D(rotation, object_scale, skew, center)
	var half := size * 0.5
	return PackedVector2Array([
		transform * Vector2(-half.x, -half.y),
		transform * Vector2(half.x, -half.y),
		transform * Vector2(half.x, half.y),
		transform * Vector2(-half.x, half.y),
	])


static func cell_at(position: Vector2, cell_scale: Vector2) -> Vector2i:
	return Vector2i(
		floori(position.x / maxf(cell_scale.x, 0.0001)),
		floori(position.y / maxf(cell_scale.y, 0.0001))
	)


static func cell_is_open(
	cells: PackedByteArray,
	width: int,
	height: int,
	cell: Vector2i
) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < width
		and cell.y < height
		and cells[cell.y * width + cell.x] == 1
	)


static func _rasterize_blocking_polygon(
	cells: PackedByteArray,
	width: int,
	height: int,
	cell_scale: Vector2,
	polygon: PackedVector2Array
) -> void:
	var bounds := _polygon_bounds(polygon)
	var from := cell_at(bounds.position, cell_scale)
	var to := cell_at(bounds.end, cell_scale)
	for y in range(maxi(from.y, 0), mini(to.y, height - 1) + 1):
		for x in range(maxi(from.x, 0), mini(to.x, width - 1) + 1):
			var cell_rect := Rect2(
				Vector2(x * cell_scale.x, y * cell_scale.y),
				cell_scale
			)
			if _polygon_intersects_rect(polygon, cell_rect):
				cells[y * width + x] = 0


static func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty():
		return Rect2()
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for index in range(1, polygon.size()):
		bounds = bounds.expand(polygon[index])
	return bounds


static func _polygon_intersects_rect(polygon: PackedVector2Array, rect: Rect2) -> bool:
	for point in polygon:
		if _rect_contains_inclusive(rect, point):
			return true
	var corners := PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
	for corner in corners:
		if Geometry2D.is_point_in_polygon(corner, polygon):
			return true
	for polygon_index in range(polygon.size()):
		var polygon_start := polygon[polygon_index]
		var polygon_end := polygon[(polygon_index + 1) % polygon.size()]
		for corner_index in range(corners.size()):
			var rect_start := corners[corner_index]
			var rect_end := corners[(corner_index + 1) % corners.size()]
			if Geometry2D.segment_intersects_segment(
				polygon_start,
				polygon_end,
				rect_start,
				rect_end
			) != null:
				return true
	return false


static func _rect_contains_inclusive(rect: Rect2, point: Vector2) -> bool:
	return (
		point.x >= rect.position.x
		and point.y >= rect.position.y
		and point.x <= rect.end.x
		and point.y <= rect.end.y
	)


static func _build_boundary_segments(
	cells: PackedByteArray,
	width: int,
	height: int,
	cell_scale: Vector2
) -> PackedVector2Array:
	var boundary_data := _build_boundary_data(cells, width, height, cell_scale, 0)
	return (boundary_data.get("segments", PackedVector2Array()) as PackedVector2Array).duplicate()


static func _build_boundary_data(
	cells: PackedByteArray,
	width: int,
	height: int,
	cell_scale: Vector2,
	chunk_size: int
) -> Dictionary:
	var segments := PackedVector2Array()
	var segments_by_chunk: Dictionary = {}
	for y in range(height):
		for x in range(width):
			if cells[y * width + x] != 1:
				continue
			var top_left := Vector2(x * cell_scale.x, y * cell_scale.y)
			var top_right := top_left + Vector2(cell_scale.x, 0.0)
			var bottom_left := top_left + Vector2(0.0, cell_scale.y)
			var bottom_right := top_left + cell_scale
			var chunk_key := ""
			var chunk_segments := PackedVector2Array()
			if chunk_size > 0:
				chunk_key = "%d:%d" % [
					floori(top_left.x / float(chunk_size)),
					floori(top_left.y / float(chunk_size)),
				]
				chunk_segments = segments_by_chunk.get(
					chunk_key,
					PackedVector2Array()
				)
			var added_to_chunk := false
			if y == 0 or cells[(y - 1) * width + x] == 0:
				segments.append(top_left)
				segments.append(top_right)
				if not chunk_key.is_empty():
					chunk_segments.append(top_left)
					chunk_segments.append(top_right)
					added_to_chunk = true
			if x == width - 1 or cells[y * width + x + 1] == 0:
				segments.append(top_right)
				segments.append(bottom_right)
				if not chunk_key.is_empty():
					chunk_segments.append(top_right)
					chunk_segments.append(bottom_right)
					added_to_chunk = true
			if y == height - 1 or cells[(y + 1) * width + x] == 0:
				segments.append(bottom_right)
				segments.append(bottom_left)
				if not chunk_key.is_empty():
					chunk_segments.append(bottom_right)
					chunk_segments.append(bottom_left)
					added_to_chunk = true
			if x == 0 or cells[y * width + x - 1] == 0:
				segments.append(bottom_left)
				segments.append(top_left)
				if not chunk_key.is_empty():
					chunk_segments.append(bottom_left)
					chunk_segments.append(top_left)
					added_to_chunk = true
			if added_to_chunk:
				segments_by_chunk[chunk_key] = chunk_segments
	return {
		"segments": segments,
		"segments_by_chunk": segments_by_chunk,
	}
