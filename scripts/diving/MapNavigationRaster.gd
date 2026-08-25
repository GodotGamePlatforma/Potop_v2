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
	include_boundary_data: bool = true,
	solid_owner_cells: PackedInt32Array = PackedInt32Array(),
	owner_ids: PackedStringArray = PackedStringArray()
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
	var owner_partition := _prepare_owner_partition(
		cells,
		solid_owner_cells,
		owner_ids,
		errors
	)
	if not errors.is_empty():
		return {"errors": errors}
	var resolved_owner_cells: PackedInt32Array = owner_partition["solid_owner_cells"]
	var resolved_owner_ids: PackedStringArray = owner_partition["owner_ids"]
	var has_owner_partition := bool(owner_partition["partitioned"])

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
		_rasterize_blocking_polygon(
			cells,
			width,
			height,
			cell_scale,
			polygon,
			resolved_owner_cells,
			1
		)
	var boundary_data: Dictionary = {}
	if include_boundary_data:
		boundary_data = _build_boundary_data(
			cells,
			width,
			height,
			cell_scale,
			chunk_size,
			resolved_owner_cells,
			resolved_owner_ids
		)
		errors.append_array(boundary_data.get("errors", PackedStringArray()))

	return {
		"errors": errors,
		"cells": cells,
		"solid_owner_cells": resolved_owner_cells,
		"owner_ids": resolved_owner_ids,
		"collision_partitioned": has_owner_partition,
		"width": width,
		"height": height,
		"cell_scale": cell_scale,
		"boundary_segments": boundary_data.get("segments", PackedVector2Array()),
		"boundary_segments_by_chunk": boundary_data.get("world_segments_by_chunk", {}),
		"world_segments_by_chunk": boundary_data.get("world_segments_by_chunk", {}),
		"structure_segments_by_id": boundary_data.get("structure_segments_by_id", {}),
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
	include_boundary_data: bool = true,
	solid_owner_cells: PackedInt32Array = PackedInt32Array(),
	owner_ids: PackedStringArray = PackedStringArray()
) -> Dictionary:
	if cache_key.is_empty():
		return build_from_cells(
			base_cells,
			width,
			height,
			world_size,
			obstacle_spawns,
			chunk_size,
			include_boundary_data,
			solid_owner_cells,
			owner_ids
		)
	var effective_cache_key := "%s|scene_cells=%dx%d|collision_chunk=%d|boundary=%d|owners=%d:%d" % [
		cache_key,
		width,
		height,
		maxi(chunk_size, 0),
		int(include_boundary_data),
		hash(solid_owner_cells),
		hash(owner_ids),
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
		include_boundary_data,
		solid_owner_cells,
		owner_ids
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
		chunk_size,
		_default_owner_cells(cells),
		PackedStringArray(["", "world"])
	)
	return (boundary_data.get("world_segments_by_chunk", {}) as Dictionary).duplicate(true)


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
	polygon: PackedVector2Array,
	solid_owner_cells: PackedInt32Array = PackedInt32Array(),
	owner_index: int = 1
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
				var cell_index := y * width + x
				cells[cell_index] = 0
				if solid_owner_cells.size() == cells.size():
					solid_owner_cells[cell_index] = owner_index


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
	var boundary_data := _build_boundary_data(
		cells,
		width,
		height,
		cell_scale,
		0,
		_default_owner_cells(cells),
		PackedStringArray(["", "world"])
	)
	return (boundary_data.get("segments", PackedVector2Array()) as PackedVector2Array).duplicate()


static func _build_boundary_data(
	cells: PackedByteArray,
	width: int,
	height: int,
	cell_scale: Vector2,
	chunk_size: int,
	solid_owner_cells: PackedInt32Array,
	owner_ids: PackedStringArray
) -> Dictionary:
	var segments := PackedVector2Array()
	var world_segments_by_chunk: Dictionary = {}
	var structure_segments_by_id: Dictionary = {}
	var errors := PackedStringArray()
	var full_segment_keys: Dictionary = {}
	var world_segment_count := 0
	var structure_segment_count := 0
	for y in range(height):
		for x in range(width):
			if cells[y * width + x] != 1:
				continue
			var top_left := Vector2(x * cell_scale.x, y * cell_scale.y)
			var top_right := top_left + Vector2(cell_scale.x, 0.0)
			var bottom_left := top_left + Vector2(0.0, cell_scale.y)
			var bottom_right := top_left + cell_scale
			var chunk_key := ""
			if chunk_size > 0:
				chunk_key = "%d:%d" % [
					floori(top_left.x / float(chunk_size)),
					floori(top_left.y / float(chunk_size)),
				]
			if y == 0 or cells[(y - 1) * width + x] == 0:
				var owner := 1 if y == 0 else solid_owner_cells[(y - 1) * width + x]
				var result := _append_owned_boundary_segment(
					segments, world_segments_by_chunk, structure_segments_by_id,
					full_segment_keys, owner_ids, owner, chunk_key, top_left, top_right, errors
				)
				world_segment_count += int(result.x)
				structure_segment_count += int(result.y)
			if x == width - 1 or cells[y * width + x + 1] == 0:
				var owner := 1 if x == width - 1 else solid_owner_cells[y * width + x + 1]
				var result := _append_owned_boundary_segment(
					segments, world_segments_by_chunk, structure_segments_by_id,
					full_segment_keys, owner_ids, owner, chunk_key, top_right, bottom_right, errors
				)
				world_segment_count += int(result.x)
				structure_segment_count += int(result.y)
			if y == height - 1 or cells[(y + 1) * width + x] == 0:
				var owner := 1 if y == height - 1 else solid_owner_cells[(y + 1) * width + x]
				var result := _append_owned_boundary_segment(
					segments, world_segments_by_chunk, structure_segments_by_id,
					full_segment_keys, owner_ids, owner, chunk_key, bottom_right, bottom_left, errors
				)
				world_segment_count += int(result.x)
				structure_segment_count += int(result.y)
			if x == 0 or cells[y * width + x - 1] == 0:
				var owner := 1 if x == 0 else solid_owner_cells[y * width + x - 1]
				var result := _append_owned_boundary_segment(
					segments, world_segments_by_chunk, structure_segments_by_id,
					full_segment_keys, owner_ids, owner, chunk_key, bottom_left, top_left, errors
				)
				world_segment_count += int(result.x)
				structure_segment_count += int(result.y)
	if segments.size() / 2 != world_segment_count + structure_segment_count:
		errors.append("Partycja kolizji nie jest pełną unią segmentów granicznych.")
	return {
		"segments": segments,
		"world_segments_by_chunk": world_segments_by_chunk,
		"structure_segments_by_id": structure_segments_by_id,
		"errors": errors,
	}


static func _prepare_owner_partition(
	cells: PackedByteArray,
	provided_owner_cells: PackedInt32Array,
	provided_owner_ids: PackedStringArray,
	errors: PackedStringArray
) -> Dictionary:
	var partitioned := not provided_owner_cells.is_empty() or not provided_owner_ids.is_empty()
	var resolved_owner_cells := provided_owner_cells.duplicate()
	var resolved_owner_ids := provided_owner_ids.duplicate()
	if not partitioned:
		resolved_owner_cells = _default_owner_cells(cells)
		resolved_owner_ids = PackedStringArray(["", "world"])
	elif provided_owner_cells.size() != cells.size():
		errors.append("Partycja właścicieli kolizji ma nieprawidłowy rozmiar rastra.")
	elif provided_owner_ids.size() < 2:
		errors.append("Partycja właścicieli kolizji nie zawiera wpisów open/world.")
	if not errors.is_empty():
		return {}
	if resolved_owner_ids[0] != "" or resolved_owner_ids[1] != "world":
		errors.append("Partycja właścicieli musi zaczynać się od ['', 'world'].")
	var seen_owner_ids: Dictionary = {}
	for owner_index in range(resolved_owner_ids.size()):
		var owner_id := resolved_owner_ids[owner_index]
		if owner_index > 0 and owner_id.is_empty():
			errors.append("Identyfikator właściciela stałej kolizji nie może być pusty.")
		if seen_owner_ids.has(owner_id):
			errors.append("Identyfikator właściciela kolizji %s występuje wielokrotnie." % owner_id)
		seen_owner_ids[owner_id] = true
	for cell_index in range(cells.size()):
		var cell_value := int(cells[cell_index])
		var owner_index := int(resolved_owner_cells[cell_index])
		if cell_value != 0 and cell_value != 1:
			errors.append("Raster nawigacji zawiera wartość inną niż solid/open.")
			break
		if cell_value == 1 and owner_index != 0:
			errors.append("Otwarta komórka rastra ma właściciela stałej kolizji.")
			break
		if cell_value == 0 and (owner_index <= 0 or owner_index >= resolved_owner_ids.size()):
			errors.append("Komórka solid nie ma poprawnego właściciela kolizji.")
			break
	return {
		"solid_owner_cells": resolved_owner_cells,
		"owner_ids": resolved_owner_ids,
		"partitioned": partitioned,
	}


static func _default_owner_cells(cells: PackedByteArray) -> PackedInt32Array:
	var owner_cells := PackedInt32Array()
	owner_cells.resize(cells.size())
	for cell_index in range(cells.size()):
		owner_cells[cell_index] = 1 if cells[cell_index] == 0 else 0
	return owner_cells


static func _append_owned_boundary_segment(
	segments: PackedVector2Array,
	world_segments_by_chunk: Dictionary,
	structure_segments_by_id: Dictionary,
	full_segment_keys: Dictionary,
	owner_ids: PackedStringArray,
	owner_index: int,
	chunk_key: String,
	from: Vector2,
	to: Vector2,
	errors: PackedStringArray
) -> Vector2i:
	if owner_index <= 0 or owner_index >= owner_ids.size():
		errors.append("Segment graniczny nie ma poprawnego właściciela kolizji.")
		return Vector2i.ZERO
	var segment_key := _boundary_segment_key(from, to)
	if full_segment_keys.has(segment_key):
		errors.append("Segment graniczny został przypisany więcej niż raz.")
		return Vector2i.ZERO
	full_segment_keys[segment_key] = true
	segments.append(from)
	segments.append(to)
	var owner_id := owner_ids[owner_index]
	if owner_id == "world":
		if not chunk_key.is_empty():
			var chunk_segments: PackedVector2Array = world_segments_by_chunk.get(
				chunk_key,
				PackedVector2Array()
			)
			chunk_segments.append(from)
			chunk_segments.append(to)
			world_segments_by_chunk[chunk_key] = chunk_segments
		return Vector2i(1, 0)
	var structure_segments: PackedVector2Array = structure_segments_by_id.get(
		owner_id,
		PackedVector2Array()
	)
	structure_segments.append(from)
	structure_segments.append(to)
	structure_segments_by_id[owner_id] = structure_segments
	return Vector2i(0, 1)


static func _boundary_segment_key(from: Vector2, to: Vector2) -> Vector4:
	if from.x < to.x or (is_equal_approx(from.x, to.x) and from.y <= to.y):
		return Vector4(from.x, from.y, to.x, to.y)
	return Vector4(to.x, to.y, from.x, from.y)
