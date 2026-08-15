class_name MacroTerrainRaster
extends RefCounted

## Deterministic CPU rasterization of the scene-authored macro terrain.
##
## TerrainNavigation contains the source polygons. TraversableAreas opens cells
## from an initially blocked grid, then BlockedIslands closes cells again. Only
## direct Polygon2D children participate. Their normal Node2D transforms and
## Polygon2D offsets are resolved into map-local space before the result is
## validated on the fixed eight-world-unit lattice.

const GRID_STEP := 8.0
const TRAVERSABLE_AREAS_PATH := NodePath("TraversableAreas")
const BLOCKED_ISLANDS_PATH := NodePath("BlockedIslands")
const HASH_SCHEMA := "macro_terrain_geometry_v1"
const EPSILON := 0.0001


static func rasterize(
	terrain_navigation: Node2D,
	world_size: Vector2,
	authority_root: Node2D = null
) -> Dictionary:
	var errors := PackedStringArray()
	var grid_size := _validated_grid_size(world_size, errors)
	if terrain_navigation == null:
		errors.append("Makroteren wymaga węzła TerrainNavigation.")
		return _error_result(errors)
	var effective_authority_root := authority_root if authority_root != null else terrain_navigation
	if not effective_authority_root.is_ancestor_of(terrain_navigation) and effective_authority_root != terrain_navigation:
		errors.append("TerrainNavigation musi należeć do wskazanego korzenia mapy.")
		return _error_result(errors)

	var traversable_areas := terrain_navigation.get_node_or_null(TRAVERSABLE_AREAS_PATH) as Node2D
	var blocked_islands := terrain_navigation.get_node_or_null(BLOCKED_ISLANDS_PATH) as Node2D
	if traversable_areas == null:
		errors.append("TerrainNavigation wymaga grupy TraversableAreas typu Node2D.")
	if blocked_islands == null:
		errors.append("TerrainNavigation wymaga grupy BlockedIslands typu Node2D.")
	if traversable_areas == null or blocked_islands == null:
		return _error_result(errors)

	var traversable_polygons := _collect_polygons(
		traversable_areas,
		"TraversableAreas",
		effective_authority_root,
		world_size,
		errors
	)
	var blocked_polygons := _collect_polygons(
		blocked_islands,
		"BlockedIslands",
		effective_authority_root,
		world_size,
		errors
	)
	if traversable_polygons.is_empty():
		errors.append("TraversableAreas wymaga co najmniej jednego poprawnego Polygon2D.")
	if not errors.is_empty():
		return _error_result(errors)

	var width := grid_size.x
	var height := grid_size.y
	var cells := PackedByteArray()
	cells.resize(width * height)
	for polygon in traversable_polygons:
		if not _rasterize_polygon(cells, width, height, polygon, 1):
			errors.append("TraversableAreas nie tworzy parzystych przecięć scanline.")
			return _error_result(errors)
	for polygon in blocked_polygons:
		if not _rasterize_polygon(cells, width, height, polygon, 0):
			errors.append("BlockedIslands nie tworzy parzystych przecięć scanline.")
			return _error_result(errors)

	return {
		"errors": errors,
		"cells": cells,
		"width": width,
		"height": height,
		"cell_scale": Vector2(GRID_STEP, GRID_STEP),
		"geometry_hash": _geometry_hash(grid_size, traversable_polygons, blocked_polygons),
		"cells_hash": sha256_bytes(cells),
	}


static func _validated_grid_size(world_size: Vector2, errors: PackedStringArray) -> Vector2i:
	if (
		not is_finite(world_size.x)
		or not is_finite(world_size.y)
		or world_size.x <= 0.0
		or world_size.y <= 0.0
	):
		errors.append("Makroteren wymaga dodatniego, skończonego rozmiaru świata.")
		return Vector2i.ZERO
	var grid_width := roundi(world_size.x / GRID_STEP)
	var grid_height := roundi(world_size.y / GRID_STEP)
	if (
		absf(world_size.x - float(grid_width) * GRID_STEP) > EPSILON
		or absf(world_size.y - float(grid_height) * GRID_STEP) > EPSILON
	):
		errors.append("Rozmiar świata makroterenu musi być wielokrotnością siatki 8 jednostek.")
		return Vector2i.ZERO
	return Vector2i(grid_width, grid_height)


static func _collect_polygons(
	container: Node2D,
	container_label: String,
	authority_root: Node2D,
	world_size: Vector2,
	errors: PackedStringArray
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for child in container.get_children():
		if not (child is Polygon2D):
			errors.append("%s może zawierać wyłącznie bezpośrednie dzieci Polygon2D: %s." % [
				container_label,
				str(child.name),
			])
			continue
		var polygon_node := child as Polygon2D
		var label := "%s/%s" % [container_label, str(polygon_node.name)]
		var local_to_map := _transform_to_ancestor(polygon_node, authority_root, label, errors)
		var map_polygon := PackedVector2Array()
		for point in polygon_node.polygon:
			map_polygon.append(local_to_map * (point + polygon_node.offset))
		var validation_error_count := errors.size()
		_validate_polygon(map_polygon, world_size, label, errors)
		if errors.size() == validation_error_count:
			result.append(map_polygon)
	return result


static func _transform_to_ancestor(
	node: Node2D,
	authority_root: Node2D,
	label: String,
	errors: PackedStringArray
) -> Transform2D:
	var result := Transform2D.IDENTITY
	var current: Node = node
	while current != authority_root:
		if current == null:
			errors.append("%s nie należy do korzenia makroterenu." % label)
			return Transform2D.IDENTITY
		if current is Node2D:
			result = (current as Node2D).transform * result
		current = current.get_parent()
	return result


static func _validate_polygon(
	polygon: PackedVector2Array,
	world_size: Vector2,
	label: String,
	errors: PackedStringArray
) -> void:
	if polygon.size() < 3:
		errors.append("%s wymaga co najmniej trzech wierzchołków." % label)
		return
	var grid_points: Array[Vector2i] = []
	var unique_points := {}
	for point in polygon:
		if not is_finite(point.x) or not is_finite(point.y):
			errors.append("%s zawiera nieskończony wierzchołek." % label)
			return
		if (
			point.x < -EPSILON
			or point.y < -EPSILON
			or point.x > world_size.x + EPSILON
			or point.y > world_size.y + EPSILON
		):
			errors.append("%s wychodzi poza granice świata." % label)
			return
		var grid_point := Vector2i(roundi(point.x / GRID_STEP), roundi(point.y / GRID_STEP))
		var snapped_point := Vector2(float(grid_point.x) * GRID_STEP, float(grid_point.y) * GRID_STEP)
		if point.distance_to(snapped_point) > EPSILON:
			errors.append("%s ma wierzchołek poza siatką 8 jednostek: %s." % [label, point])
			return
		var point_key := "%d:%d" % [grid_point.x, grid_point.y]
		if unique_points.has(point_key):
			errors.append("%s powtarza wierzchołek %s." % [label, point])
			return
		unique_points[point_key] = true
		grid_points.append(grid_point)

	if _twice_signed_area(grid_points) == 0:
		errors.append("%s ma zerowe pole." % label)
		return
	# Keep validation native: a GDScript all-edge-pairs check becomes the
	# dominant cost for the production contour with several thousand points.
	if Geometry2D.triangulate_polygon(polygon).is_empty():
		errors.append("%s ma samoprzecinający się obrys." % label)


static func _twice_signed_area(points: Array[Vector2i]) -> int:
	var result := 0
	for index in range(points.size()):
		var current := points[index]
		var next := points[(index + 1) % points.size()]
		result += current.x * next.y - current.y * next.x
	return result


static func _rasterize_polygon(
	cells: PackedByteArray,
	width: int,
	height: int,
	polygon: PackedVector2Array,
	cell_value: int
) -> bool:
	var grid_polygon: Array[Vector2i] = []
	for point in polygon:
		grid_polygon.append(Vector2i(roundi(point.x / GRID_STEP), roundi(point.y / GRID_STEP)))
	var minimum_y := grid_polygon[0].y
	var maximum_y := grid_polygon[0].y
	for point in grid_polygon:
		minimum_y = mini(minimum_y, point.y)
		maximum_y = maxi(maximum_y, point.y)
	var from_y := clampi(minimum_y, 0, height)
	var to_y_exclusive := clampi(maximum_y, 0, height)

	for y in range(from_y, to_y_exclusive):
		# Scan through cell centers. Vertices are on integer lattice points, so
		# the odd doubled ordinate can never coincide with a vertex.
		var scan_y_doubled := 2 * y + 1
		var intersections: Array[Vector2i] = []
		for edge_index in range(grid_polygon.size()):
			var edge_from := grid_polygon[edge_index]
			var edge_to := grid_polygon[(edge_index + 1) % grid_polygon.size()]
			if edge_from.y == edge_to.y:
				continue
			var lower := edge_from
			var upper := edge_to
			if lower.y > upper.y:
				lower = edge_to
				upper = edge_from
			if scan_y_doubled <= 2 * lower.y or scan_y_doubled >= 2 * upper.y:
				continue
			var delta_y := upper.y - lower.y
			var delta_x := upper.x - lower.x
			var denominator := 2 * delta_y
			var numerator := (
				2 * lower.x * delta_y
				+ (scan_y_doubled - 2 * lower.y) * delta_x
			)
			intersections.append(Vector2i(numerator, denominator))
		intersections.sort_custom(_rational_less)
		if intersections.size() % 2 != 0:
			return false
		for pair_index in range(0, intersections.size(), 2):
			var left := intersections[pair_index]
			var right := intersections[pair_index + 1]
			# Cell center (x + 0.5) is inside, including an exact boundary hit.
			var first_x := _ceil_div(2 * left.x - left.y, 2 * left.y)
			var last_x := _floor_div(2 * right.x - right.y, 2 * right.y)
			first_x = maxi(first_x, 0)
			last_x = mini(last_x, width - 1)
			if first_x > last_x:
				continue
			for x in range(first_x, last_x + 1):
				cells[y * width + x] = cell_value
	return true


static func _rational_less(left: Vector2i, right: Vector2i) -> bool:
	return left.x * right.y < right.x * left.y


static func _floor_div(numerator: int, denominator: int) -> int:
	@warning_ignore("integer_division")
	var quotient := numerator / denominator
	if numerator < 0 and numerator % denominator != 0:
		quotient -= 1
	return quotient


static func _ceil_div(numerator: int, denominator: int) -> int:
	return -_floor_div(-numerator, denominator)


static func _geometry_hash(
	grid_size: Vector2i,
	traversable_polygons: Array[PackedVector2Array],
	blocked_polygons: Array[PackedVector2Array]
) -> String:
	var traversable_keys := PackedStringArray()
	for polygon in traversable_polygons:
		traversable_keys.append(_canonical_polygon_key(polygon))
	traversable_keys.sort()
	var blocked_keys := PackedStringArray()
	for polygon in blocked_polygons:
		blocked_keys.append(_canonical_polygon_key(polygon))
	blocked_keys.sort()

	var payload := PackedStringArray([
		HASH_SCHEMA,
		"grid=%d,%d" % [grid_size.x, grid_size.y],
		"step=8",
	])
	for key in traversable_keys:
		payload.append("open=" + key)
	for key in blocked_keys:
		payload.append("blocked=" + key)
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update("\n".join(payload).to_utf8_buffer())
	return hashing.finish().hex_encode()


static func sha256_bytes(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(bytes)
	return hashing.finish().hex_encode()


static func _canonical_polygon_key(polygon: PackedVector2Array) -> String:
	var forward: Array[Vector2i] = []
	for point in polygon:
		forward.append(Vector2i(roundi(point.x / GRID_STEP), roundi(point.y / GRID_STEP)))
	var reversed := forward.duplicate()
	reversed.reverse()
	var forward_key := _rotation_normalized_key(forward)
	var reversed_key := _rotation_normalized_key(reversed)
	return forward_key if forward_key < reversed_key else reversed_key


static func _rotation_normalized_key(points: Array[Vector2i]) -> String:
	var first_index := 0
	for index in range(1, points.size()):
		if (
			points[index].x < points[first_index].x
			or (
				points[index].x == points[first_index].x
				and points[index].y < points[first_index].y
			)
		):
			first_index = index
	var components := PackedStringArray()
	for offset in range(points.size()):
		var point := points[(first_index + offset) % points.size()]
		components.append("%d,%d" % [point.x, point.y])
	return ";".join(components)


static func _error_result(errors: PackedStringArray) -> Dictionary:
	return {
		"errors": errors,
		"cells": PackedByteArray(),
		"width": 0,
		"height": 0,
		"cell_scale": Vector2(GRID_STEP, GRID_STEP),
		"geometry_hash": "",
		"cells_hash": "",
	}
