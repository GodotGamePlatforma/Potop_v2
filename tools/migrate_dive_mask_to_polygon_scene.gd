extends SceneTree

## One-shot, parity-gated migration of the legacy semantic PNG into built-in
## Polygon2D nodes inside UnderwaterMap.tscn. This is not a map editor: after
## this bootstrap, the Godot 2D editor and the saved polygons are authoritative.

const MAP_SCENE_PATH := "res://scenes/diving/UnderwaterMap.tscn"
const LEGACY_MASK_PATH := "res://assets/diving/world/map_v2/world_collision_grid.png"
const WORLD_SIZE := Vector2(11_520.0, 6_480.0)
const TERRAIN_PARENT := "Terrain/TerrainNavigation"
const SERIALIZATION_SLICE_WIDTH_CELLS := 180


func _initialize() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(LEGACY_MASK_PATH))
	if image == null or image.is_empty():
		_fail("Nie można odczytać dotychczasowej maski terenu.")
		return
	var extraction := _extract_polygons(image)
	var extraction_errors: PackedStringArray = extraction.get("errors", PackedStringArray())
	if not extraction_errors.is_empty():
		_fail("; ".join(extraction_errors))
		return
	var traversable: Array[PackedVector2Array] = extraction.get("traversable", [])
	var islands: Array[PackedVector2Array] = extraction.get("islands", [])
	traversable = _split_for_serialization(
		traversable,
		Vector2i(image.get_width(), image.get_height())
	)
	var cell_scale := Vector2(
		WORLD_SIZE.x / float(image.get_width()),
		WORLD_SIZE.y / float(image.get_height())
	)
	var scaled_traversable := _scaled_polygons(traversable, cell_scale)
	var scaled_islands := _scaled_polygons(islands, cell_scale)
	var generated := _rasterize(
		scaled_traversable,
		scaled_islands,
		image.get_width(),
		image.get_height(),
		cell_scale
	)
	var expected := _cells_from_image(image)
	var mismatch := _first_mismatch(expected, generated, image.get_width())
	if mismatch != Vector2i(-1, -1):
		_fail("Migracja nie zachowuje komórki %s; scena nie została zmieniona." % mismatch)
		return

	var scene_path := ProjectSettings.globalize_path(MAP_SCENE_PATH)
	var scene_text := FileAccess.get_file_as_string(scene_path)
	if scene_text.is_empty():
		_fail("Nie można odczytać UnderwaterMap.tscn.")
		return
	var generated_start := scene_text.find("[node name=\"TraversableAreas\"")
	var depth_index := scene_text.find("[node name=\"DepthRegions\"")
	if depth_index < 0:
		_fail("Nie znaleziono bezpiecznego miejsca wstawienia przed DepthRegions.")
		return
	var generated_nodes := _terrain_nodes_text(scaled_traversable, scaled_islands)
	var updated_text: String
	if generated_start >= 0:
		updated_text = scene_text.left(generated_start) + generated_nodes + scene_text.substr(depth_index)
	else:
		updated_text = scene_text.left(depth_index) + generated_nodes + scene_text.substr(depth_index)
	var output := FileAccess.open(scene_path, FileAccess.WRITE)
	if output == null:
		_fail("Nie można zapisać UnderwaterMap.tscn.")
		return
	output.store_string(updated_text)
	output.close()
	print(
		"Migracja makroterenu zakończona: %d obszar(y) wody, %d wysp terenu, " % [
			scaled_traversable.size(),
			scaled_islands.size(),
		],
		"%d komórek zgodnych 1:1." % generated.size()
	)
	quit(0)


func _extract_polygons(image: Image) -> Dictionary:
	var errors := PackedStringArray()
	var size := Vector2i(image.get_width(), image.get_height())
	var traversable_bitmap := BitMap.new()
	var blocked_bitmap := BitMap.new()
	traversable_bitmap.create(size)
	blocked_bitmap.create(size)
	for y in range(size.y):
		for x in range(size.x):
			var open := image.get_pixel(x, y).r <= 0.5
			traversable_bitmap.set_bit(x, y, open)
			blocked_bitmap.set_bit(x, y, not open)
	var traversable_raw := traversable_bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, size), 0.0)
	var blocked_raw := blocked_bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, size), 0.0)
	var traversable: Array[PackedVector2Array] = []
	var islands: Array[PackedVector2Array] = []
	for polygon in traversable_raw:
		if polygon.size() >= 3:
			traversable.append(polygon)
	for polygon in blocked_raw:
		if polygon.size() < 3 or _touches_grid_edge(polygon, size):
			continue
		islands.append(polygon)
	if traversable.is_empty():
		errors.append("Maska nie zawiera zamkniętego obszaru otwartej wody.")
	if islands.is_empty():
		errors.append("Maska nie zawiera żadnej wewnętrznej wyspy terenu.")
	return {"errors": errors, "traversable": traversable, "islands": islands}


func _touches_grid_edge(polygon: PackedVector2Array, size: Vector2i) -> bool:
	for point in polygon:
		if point.x <= 0.0 or point.y <= 0.0 or point.x >= size.x or point.y >= size.y:
			return true
	return false


func _split_for_serialization(
	polygons: Array[PackedVector2Array],
	grid_size: Vector2i
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for source in polygons:
		for from_x in range(0, grid_size.x, SERIALIZATION_SLICE_WIDTH_CELLS):
			var to_x := mini(from_x + SERIALIZATION_SLICE_WIDTH_CELLS, grid_size.x)
			var clip := PackedVector2Array([
				Vector2(from_x, 0),
				Vector2(to_x, 0),
				Vector2(to_x, grid_size.y),
				Vector2(from_x, grid_size.y),
			])
			for piece in Geometry2D.intersect_polygons(source, clip):
				if piece.size() >= 3:
					result.append(piece)
	return result


func _scaled_polygons(
	polygons: Array[PackedVector2Array],
	cell_scale: Vector2
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for source in polygons:
		var scaled := PackedVector2Array()
		for point in source:
			scaled.append(point * cell_scale)
		result.append(scaled)
	return result


func _cells_from_image(image: Image) -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(image.get_width() * image.get_height())
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			cells[y * image.get_width() + x] = 1 if image.get_pixel(x, y).r <= 0.5 else 0
	return cells


func _rasterize(
	traversable: Array[PackedVector2Array],
	islands: Array[PackedVector2Array],
	width: int,
	height: int,
	cell_scale: Vector2
) -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(width * height)
	for polygon in traversable:
		_scanline_fill(cells, width, height, cell_scale, polygon, 1)
	for polygon in islands:
		_scanline_fill(cells, width, height, cell_scale, polygon, 0)
	return cells


func _scanline_fill(
	cells: PackedByteArray,
	width: int,
	height: int,
	cell_scale: Vector2,
	polygon: PackedVector2Array,
	value: int
) -> void:
	var min_y := polygon[0].y
	var max_y := polygon[0].y
	for point in polygon:
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)
	var from_y := maxi(0, ceili(min_y / cell_scale.y - 0.5))
	var to_y := mini(height - 1, ceili(max_y / cell_scale.y - 0.5) - 1)
	for y in range(from_y, to_y + 1):
		var sample_y := (float(y) + 0.5) * cell_scale.y
		var intersections: Array[float] = []
		for index in range(polygon.size()):
			var a := polygon[index]
			var b := polygon[(index + 1) % polygon.size()]
			if is_equal_approx(a.y, b.y):
				continue
			var low_y := minf(a.y, b.y)
			var high_y := maxf(a.y, b.y)
			if sample_y < low_y or sample_y >= high_y:
				continue
			var weight := (sample_y - a.y) / (b.y - a.y)
			intersections.append(lerpf(a.x, b.x, weight))
		intersections.sort()
		for pair_index in range(0, intersections.size() - 1, 2):
			var left := intersections[pair_index]
			var right := intersections[pair_index + 1]
			var from_x := maxi(0, ceili(left / cell_scale.x - 0.5))
			var to_x := mini(width - 1, ceili(right / cell_scale.x - 0.5) - 1)
			for x in range(from_x, to_x + 1):
				cells[y * width + x] = value


func _first_mismatch(expected: PackedByteArray, actual: PackedByteArray, width: int) -> Vector2i:
	if expected.size() != actual.size():
		return Vector2i(0, 0)
	for index in range(expected.size()):
		if expected[index] != actual[index]:
			return Vector2i(index % width, index / width)
	return Vector2i(-1, -1)


func _terrain_nodes_text(
	traversable: Array[PackedVector2Array],
	islands: Array[PackedVector2Array]
) -> String:
	var lines := PackedStringArray()
	lines.append("[node name=\"TraversableAreas\" type=\"Node2D\" parent=\"%s\"]" % TERRAIN_PARENT)
	lines.append("editor_description = \"Otwarta woda. Edytuj punkty dzieci Polygon2D narzędziem wielokąta w widoku 2D.\"")
	lines.append("z_index = -1000")
	lines.append("")
	for index in range(traversable.size()):
		lines.append("[node name=\"OpenWater_%03d\" type=\"Polygon2D\" parent=\"%s/TraversableAreas\"]" % [index + 1, TERRAIN_PARENT])
		lines.append("editor_description = \"Semantyczny obszar przechodniej wody; ten Polygon2D jest źródłem mapy.\"")
		lines.append("color = Color(0.035, 0.31, 0.42, 0.24)")
		lines.append("polygon = %s" % _polygon_literal(traversable[index]))
		lines.append("")
	lines.append("[node name=\"BlockedIslands\" type=\"Node2D\" parent=\"%s\"]" % TERRAIN_PARENT)
	lines.append("editor_description = \"Pełny teren wewnątrz otwartej wody. Edytuj punkty dzieci Polygon2D w widoku 2D.\"")
	lines.append("z_index = -999")
	lines.append("")
	for index in range(islands.size()):
		lines.append("[node name=\"BlockedIsland_%03d\" type=\"Polygon2D\" parent=\"%s/BlockedIslands\"]" % [index + 1, TERRAIN_PARENT])
		lines.append("editor_description = \"Semantyczna wyspa pełnego terenu; ten Polygon2D jest źródłem mapy.\"")
		lines.append("color = Color(0.18, 0.21, 0.22, 0.58)")
		lines.append("polygon = %s" % _polygon_literal(islands[index]))
		lines.append("")
	return "\n".join(lines)


func _polygon_literal(polygon: PackedVector2Array) -> String:
	var components := PackedStringArray()
	for point in polygon:
		components.append(_number(point.x))
		components.append(_number(point.y))
	return "PackedVector2Array(%s)" % ", ".join(components)


func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.6f" % value


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
