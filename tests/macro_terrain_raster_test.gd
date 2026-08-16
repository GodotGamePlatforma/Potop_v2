extends SceneTree

const MacroTerrainRasterScript := preload("res://scripts/diving/MacroTerrainRaster.gd")
const TerrainDerivativesScript := preload("res://scripts/diving/DiveTerrainDerivatives.gd")
const MAP_SCENE_PATH := "res://scenes/diving/UnderwaterMap.tscn"
const NAVIGATION_PNG_PATH := "res://assets/diving/world/map_v2/world_collision_grid.png"
const NAVIGATION_MANIFEST_PATH := "res://assets/diving/world/map_v2/world_collision_grid.json"

const WORLD_SIZE := Vector2(40.0, 32.0)
var _open_left := PackedVector2Array([
	Vector2(0.0, 0.0),
	Vector2(24.0, 0.0),
	Vector2(24.0, 32.0),
	Vector2(0.0, 32.0),
])
var _open_top_right := PackedVector2Array([
	Vector2(16.0, 0.0),
	Vector2(40.0, 0.0),
	Vector2(40.0, 16.0),
	Vector2(16.0, 16.0),
])
var _blocked_center := PackedVector2Array([
	Vector2(8.0, 8.0),
	Vector2(24.0, 8.0),
	Vector2(24.0, 24.0),
	Vector2(8.0, 24.0),
])

var _failures := 0


func _initialize() -> void:
	_test_default_blocked_union_and_island_subtraction()
	_test_scanline_includes_cell_centers_on_boundary()
	_test_hash_is_invariant_to_node_order_start_and_winding()
	_test_node_transforms_are_resolved_in_map_space()
	_test_invalid_authority_is_rejected()
	_test_production_scene_matches_committed_derivatives()
	if _failures > 0:
		push_error("Macro terrain raster test failed with %d assertion(s)." % _failures)
		quit(1)
		return
	print("Macro terrain raster test passed: deterministic cell-center raster and canonical geometry hash.")
	quit(0)


func _test_default_blocked_union_and_island_subtraction() -> void:
	var fixture := _fixture(false)
	var result: Dictionary = MacroTerrainRasterScript.rasterize(fixture, WORLD_SIZE)
	_assert((result.get("errors", PackedStringArray()) as PackedStringArray).is_empty(), "Poprawny fixture nie może zwracać błędów.")
	_assert(int(result.get("width", 0)) == 5, "Raster powinien mieć pięć kolumn siatki 8.")
	_assert(int(result.get("height", 0)) == 4, "Raster powinien mieć cztery wiersze siatki 8.")
	_assert(result.get("cell_scale", Vector2.ZERO) == Vector2(8.0, 8.0), "Raster musi publikować stałą skalę komórki 8.")
	var expected := PackedByteArray([
		1, 1, 1, 1, 1,
		1, 0, 0, 1, 1,
		1, 0, 0, 0, 0,
		1, 1, 1, 0, 0,
	])
	_assert(result.get("cells", PackedByteArray()) == expected, "Raster musi wykonać default blocked, unię open i końcowe blocked islands.")
	_assert(str(result.get("geometry_hash", "")).length() == 64, "Poprawna geometria musi otrzymać hash SHA-256.")
	_assert(str(result.get("cells_hash", "")).length() == 64, "Poprawne komórki muszą otrzymać hash SHA-256.")
	fixture.free()


func _test_scanline_includes_cell_centers_on_boundary() -> void:
	var terrain_navigation := Node2D.new()
	terrain_navigation.name = "TerrainNavigation"
	var traversable_areas := Node2D.new()
	traversable_areas.name = "TraversableAreas"
	var blocked_islands := Node2D.new()
	blocked_islands.name = "BlockedIslands"
	terrain_navigation.add_child(traversable_areas)
	terrain_navigation.add_child(blocked_islands)
	var triangle := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(24.0, 0.0),
		Vector2(0.0, 24.0),
	])
	traversable_areas.add_child(_polygon("BoundaryTriangle", triangle))
	var result: Dictionary = MacroTerrainRasterScript.rasterize(terrain_navigation, Vector2(24.0, 24.0))
	var expected := PackedByteArray([
		1, 1, 1,
		1, 1, 0,
		1, 0, 0,
	])
	_assert(result.get("cells", PackedByteArray()) == expected, "Scanline musi traktować środek komórki leżący na krawędzi jako inside.")
	var cells: PackedByteArray = result.get("cells", PackedByteArray())
	for y in range(3):
		for x in range(3):
			var center := Vector2((float(x) + 0.5) * 8.0, (float(y) + 0.5) * 8.0)
			_assert(
				(cells[y * 3 + x] == 1) == Geometry2D.is_point_in_polygon(center, triangle),
				"Scanline i referencyjne cell-center Geometry2D muszą zgadzać się dla %s." % center
			)
	terrain_navigation.free()


func _test_hash_is_invariant_to_node_order_start_and_winding() -> void:
	var baseline_fixture := _fixture(false)
	var reordered_fixture := _fixture(true)
	var baseline: Dictionary = MacroTerrainRasterScript.rasterize(baseline_fixture, WORLD_SIZE)
	var reordered: Dictionary = MacroTerrainRasterScript.rasterize(reordered_fixture, WORLD_SIZE)
	_assert(
		baseline.get("cells", PackedByteArray()) == reordered.get("cells", PackedByteArray()),
		"Zmiana kolejności węzłów, punktu startowego i windingu nie może zmieniać komórek."
	)
	_assert(
		str(baseline.get("geometry_hash", "")) == str(reordered.get("geometry_hash", "")),
		"Hash geometrii musi być niezależny od kolejności węzłów, punktu startowego i windingu."
	)
	var changed_polygon := reordered_fixture.get_node("TraversableAreas/RightFirst") as Polygon2D
	changed_polygon.polygon = PackedVector2Array([
		Vector2(16.0, 0.0),
		Vector2(32.0, 0.0),
		Vector2(32.0, 16.0),
		Vector2(16.0, 16.0),
	])
	var changed: Dictionary = MacroTerrainRasterScript.rasterize(reordered_fixture, WORLD_SIZE)
	_assert(
		str(changed.get("geometry_hash", "")) != str(baseline.get("geometry_hash", "")),
		"Rzeczywista zmiana geometrii musi zmieniać hash."
	)
	baseline_fixture.free()
	reordered_fixture.free()


func _test_node_transforms_are_resolved_in_map_space() -> void:
	var transformed_fixture := _fixture(false)
	(transformed_fixture.get_node("TraversableAreas/OpenLeft") as Polygon2D).position = Vector2(8.0, 0.0)
	(transformed_fixture.get_node("BlockedIslands/Center") as Polygon2D).offset = Vector2(8.0, 0.0)
	var transformed: Dictionary = MacroTerrainRasterScript.rasterize(transformed_fixture, WORLD_SIZE)

	var baked_fixture := _fixture(false)
	var baked_open := baked_fixture.get_node("TraversableAreas/OpenLeft") as Polygon2D
	var baked_open_points := PackedVector2Array()
	for point in baked_open.polygon:
		baked_open_points.append(point + Vector2(8.0, 0.0))
	baked_open.polygon = baked_open_points
	var baked_island := baked_fixture.get_node("BlockedIslands/Center") as Polygon2D
	var baked_island_points := PackedVector2Array()
	for point in baked_island.polygon:
		baked_island_points.append(point + Vector2(8.0, 0.0))
	baked_island.polygon = baked_island_points
	var baked: Dictionary = MacroTerrainRasterScript.rasterize(baked_fixture, WORLD_SIZE)
	_assert((transformed.get("errors", PackedStringArray()) as PackedStringArray).is_empty(), "Transformacje i offset zgodne z siatką muszą być prawidłowym authoringiem Godot.")
	_assert(transformed.get("cells", PackedByteArray()) == baked.get("cells", PackedByteArray()), "Transformacje Polygon2D muszą dawać te same komórki co wypieczone punkty mapy.")
	_assert(str(transformed.get("geometry_hash", "")) == str(baked.get("geometry_hash", "")), "Hash musi opisywać geometrię po transformacji, nie lokalne punkty noda.")

	var root := Node2D.new()
	var terrain := Node2D.new()
	root.add_child(terrain)
	terrain.add_child(transformed_fixture)
	terrain.position = Vector2(8.0, 0.0)
	transformed_fixture.position = Vector2(-8.0, 0.0)
	var through_ancestors: Dictionary = MacroTerrainRasterScript.rasterize(
		transformed_fixture,
		WORLD_SIZE,
		root
	)
	_assert(through_ancestors.get("cells", PackedByteArray()) == transformed.get("cells", PackedByteArray()), "Raster musi uwzględniać pełny łańcuch transformacji do korzenia mapy.")
	root.free()
	baked_fixture.free()


func _test_invalid_authority_is_rejected() -> void:
	var transformed_fixture := _fixture(false)
	(transformed_fixture.get_node("TraversableAreas/OpenLeft") as Polygon2D).position = Vector2(0.001, 0.0)
	_assert(_has_errors(transformed_fixture), "Transformacja dająca punkt poza siatką 8 musi zostać odrzucona.")
	transformed_fixture.free()

	var offset_fixture := _fixture(false)
	(offset_fixture.get_node("BlockedIslands/Center") as Polygon2D).offset = Vector2(0.001, 0.0)
	_assert(_has_errors(offset_fixture), "Offset dający punkt poza siatką 8 musi zostać odrzucony.")
	offset_fixture.free()

	var off_grid_fixture := _fixture(false)
	(off_grid_fixture.get_node("TraversableAreas/OpenLeft") as Polygon2D).polygon = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(23.999, 0.0),
		Vector2(24.0, 32.0),
		Vector2(0.0, 32.0),
	])
	_assert(_has_errors(off_grid_fixture), "Wierzchołek poza siatką 8 musi zostać odrzucony.")
	off_grid_fixture.free()

	var crossing_fixture := _fixture(false)
	(crossing_fixture.get_node("TraversableAreas/OpenLeft") as Polygon2D).polygon = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(24.0, 24.0),
		Vector2(0.0, 24.0),
		Vector2(24.0, 0.0),
	])
	_assert(_has_errors(crossing_fixture), "Samoprzecinający Polygon2D musi zostać odrzucony.")
	crossing_fixture.free()


func _test_production_scene_matches_committed_derivatives() -> void:
	var packed_scene := ResourceLoader.load(MAP_SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_assert(packed_scene != null, "Produkcyjna scena mapy musi dać się załadować.")
	if packed_scene == null:
		return
	var map_root := packed_scene.instantiate()
	var terrain_navigation := map_root.get_node_or_null("Terrain/TerrainNavigation") as Node2D
	var traversable_areas := map_root.get_node_or_null("Terrain/TerrainNavigation/TraversableAreas") as Node2D
	var blocked_islands := map_root.get_node_or_null("Terrain/TerrainNavigation/BlockedIslands") as Node2D
	_assert(terrain_navigation != null, "Produkcjna mapa musi mieć TerrainNavigation.")
	_assert(traversable_areas != null and traversable_areas.get_child_count() == 15, "Migracja 1:1 musi zachować piętnaście edytowalnych obszarów otwartej wody.")
	_assert(blocked_islands != null and blocked_islands.get_child_count() == 22, "Migracja 1:1 musi zachować dwadzieścia dwie wyspy terenu.")
	if terrain_navigation == null or traversable_areas == null or blocked_islands == null:
		map_root.free()
		return

	var raster: Dictionary = MacroTerrainRasterScript.rasterize(terrain_navigation, map_root.get("world_size"), map_root)
	var errors: PackedStringArray = raster.get("errors", PackedStringArray())
	_assert(errors.is_empty(), "Produkcyjny makroteren Polygon2D musi przejść walidację: %s" % "; ".join(errors))
	var cells: PackedByteArray = raster.get("cells", PackedByteArray())
	_assert(cells.size() == 1_166_400, "Produkcyjny raster musi zachować siatkę 1440 x 810.")
	var open_count := 0
	for cell in cells:
		open_count += int(cell)
	_assert(open_count == 654_943, "Migracja scenowa musi zachować dokładnie 654943 komórki otwartej wody.")

	var image := Image.load_from_file(ProjectSettings.globalize_path(NAVIGATION_PNG_PATH))
	_assert(image != null and image.get_width() == 1440 and image.get_height() == 810, "Pochodny PNG musi zachować rozmiar produkcyjnej siatki.")
	if image != null and image.get_width() == 1440 and image.get_height() == 810:
		var first_difference := Vector2i(-1, -1)
		for y in range(810):
			for x in range(1440):
				var png_open := image.get_pixel(x, y).r <= 0.5
				if png_open != (cells[y * 1440 + x] == 1):
					first_difference = Vector2i(x, y)
					break
			if first_difference.x >= 0:
				break
		_assert(first_difference.x < 0, "Scena Polygon2D i pochodny PNG muszą być zgodne komórka w komórkę; pierwsza różnica: %s." % first_difference)

	var derivative_errors := TerrainDerivativesScript.validate_derivatives(map_root, raster, true)
	_assert(derivative_errors.is_empty(), "Łańcuch manifestów PNG/SDF musi być aktualny: %s" % "; ".join(derivative_errors))
	var manifest_variant = JSON.parse_string(FileAccess.get_file_as_string(NAVIGATION_MANIFEST_PATH))
	_assert(manifest_variant is Dictionary, "Pochodny PNG musi mieć manifest scenowego źródła.")
	if manifest_variant is Dictionary:
		var manifest: Dictionary = manifest_variant
		_assert(str(manifest.get("authority_path", "")) == MAP_SCENE_PATH, "Manifest PNG musi wskazywać UnderwaterMap.tscn jako authority.")
		_assert(str(manifest.get("geometry_sha256", "")) == str(raster.get("geometry_hash", "")), "Manifest PNG musi odpowiadać kanonicznemu hashowi Polygon2D.")
		_assert(str(manifest.get("cells_sha256", "")) == str(map_root.get("navigation_cells_sha256")), "Scena i manifest muszą publikować ten sam eksportowalny skrót komórek.")
		_assert(str(manifest.get("output_sha256", "")) == str(map_root.get("navigation_signature_sha256")), "Scena musi przechowywać stabilny skrót zgodności zapisu bez odczytu surowego PNG w eksporcie.")

	var first_open_index := cells.find(1)
	_assert(first_open_index >= 0, "Produkcyjny raster musi zawierać otwartą wodę do testu nieaktualnej pochodnej.")
	if first_open_index >= 0:
		var cell_x := first_open_index % 1440
		@warning_ignore("integer_division")
		var cell_y := first_open_index / 1440
		var stale_island := _polygon("StaleDerivativeProbe", PackedVector2Array([
			Vector2(cell_x * 8.0, cell_y * 8.0),
			Vector2((cell_x + 1) * 8.0, cell_y * 8.0),
			Vector2((cell_x + 1) * 8.0, (cell_y + 1) * 8.0),
			Vector2(cell_x * 8.0, (cell_y + 1) * 8.0),
		]))
		blocked_islands.add_child(stale_island)
		var changed_raster: Dictionary = MacroTerrainRasterScript.rasterize(terrain_navigation, map_root.get("world_size"), map_root)
		_assert(
			not TerrainDerivativesScript.validate_derivatives(map_root, changed_raster, false).is_empty(),
			"Zmiana authority Polygon2D musi odrzucić nieaktualne pochodne przed kompilacją mapy."
		)
	map_root.free()


func _fixture(reordered: bool) -> Node2D:
	var terrain_navigation := Node2D.new()
	terrain_navigation.name = "TerrainNavigation"
	var traversable_areas := Node2D.new()
	traversable_areas.name = "TraversableAreas"
	var blocked_islands := Node2D.new()
	blocked_islands.name = "BlockedIslands"
	if reordered:
		terrain_navigation.add_child(blocked_islands)
		terrain_navigation.add_child(traversable_areas)
		traversable_areas.add_child(_polygon("RightFirst", _reversed_rotation(_open_top_right, 2)))
		traversable_areas.add_child(_polygon("LeftSecond", _reversed_rotation(_open_left, 1)))
		blocked_islands.add_child(_polygon("DifferentName", _reversed_rotation(_blocked_center, 3)))
	else:
		terrain_navigation.add_child(traversable_areas)
		terrain_navigation.add_child(blocked_islands)
		traversable_areas.add_child(_polygon("OpenLeft", _open_left))
		traversable_areas.add_child(_polygon("OpenTopRight", _open_top_right))
		blocked_islands.add_child(_polygon("Center", _blocked_center))
	return terrain_navigation


func _polygon(node_name: String, points: PackedVector2Array) -> Polygon2D:
	var result := Polygon2D.new()
	result.name = node_name
	result.polygon = points
	return result


func _reversed_rotation(points: PackedVector2Array, start_index: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for offset in range(points.size()):
		var index := posmod(start_index - offset, points.size())
		result.append(points[index])
	return result


func _has_errors(fixture: Node2D) -> bool:
	var result: Dictionary = MacroTerrainRasterScript.rasterize(fixture, WORLD_SIZE)
	return not (result.get("errors", PackedStringArray()) as PackedStringArray).is_empty()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Macro terrain raster assertion failed: " + message)
