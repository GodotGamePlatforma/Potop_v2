extends SceneTree

const MapCompilerScript := preload("res://scripts/diving/UnderwaterMapSceneCompiler.gd")
const MapSceneScript := preload("res://scripts/diving/UnderwaterMapScene.gd")
const MapObjectScript := preload("res://scripts/diving/DiveMapObject.gd")
const MapConnectionScript := preload("res://scripts/diving/DiveMapConnection.gd")
const MapNavigationRasterScript := preload("res://scripts/diving/MapNavigationRaster.gd")
const RuntimeMapScript := preload("res://scripts/diving/UnderwaterMapRuntime.gd")
const WorldStateScript := preload("res://scripts/data/UnderwaterWorldState.gd")
const CommonLineCableVisualScript := preload("res://scripts/diving/DiveCommonLineCableVisual.gd")

const TUTORIAL_POSITIONS := {
	"exit_line": Vector2(5713.388, 388.22977),
	"tutorial_market_crate": Vector2(5204.0, 700.0),
	"tutorial_workshop_case": Vector2(2804.0, 804.0),
	"SC-01": Vector2(2464.0, 940.0),
	"junction_j7": Vector2(2244.0, 1220.0),
}
const STORY_POSITIONS := {
	"archive_terminal": Vector2(7980.0, 1100.0),
	"rescue_hotel_leon": Vector2(8604.0, 708.0),
	"r3_diagnostic_panel": Vector2(9760.0, 2700.0),
	"r3_generator": Vector2(10300.0, 3040.0),
}
const C4_POSITIONS := {
	"c4_switchboard": Vector2(5700.0, 5800.0),
	"c4_splitter_mount": Vector2(6100.0, 5800.0),
	"heart_structural_cache": Vector2(6500.0, 5800.0),
	"heart_reconstruction_reserve": Vector2(6900.0, 5800.0),
}
const R3_FOOD_PICKUP_POSITION := Vector2(2204.0, 2576.0)
const BUOY_POSITIONS := {
	"B-01": Vector2(3324.0, 1548.0),
	"B-02": Vector2(1778.0, 2485.0),
	"B-03": Vector2(1980.0, 4332.0),
}
const MIN_CRITICAL_INTERACTABLE_SEPARATION := 300.0
const CRITICAL_INTERACTABLE_PAIRS := [
	["archive_terminal", "SC-02"],
	["archive_terminal", "archive_maintenance_store"],
	["rescue_hotel_leon", "hotel_linen_cache"],
	["r3_diagnostic_panel", "r3_generator"],
	["r3_diagnostic_panel", "power_plant_service_store"],
	["r3_generator", "power_plant_service_store"],
	["c4_switchboard", "c4_splitter_mount"],
	["c4_switchboard", "city_reconstruction_reserve"],
	["c4_splitter_mount", "city_reconstruction_reserve"],
	["c4_splitter_mount", "heart_structural_cache"],
	["ship_engine_r1", "ship_carpentry_store"],
	["shipyard_winch_r3", "pickup_r3_planks_01"],
	["shipyard_winch_r3", "shipyard_material_rack"],
	["scrapyard_generator_r3", "pickup_r3_scrap_01"],
	["scrapyard_generator_r3", "scrapyard_sorting_cache"],
]
const CABLE_DECORATION_ID := "common_line_cable_r1_j7"
const CABLE_VISUAL_PATH := "res://scenes/diving/map_visuals/CommonLineCableVisual.tscn"
const STORY_CABLE_VISUAL_PATHS := {
	"common_line_cable_j7_archive": "res://scenes/diving/map_visuals/CommonLineArchiveCableVisual.tscn",
	"common_line_cable_archive_r3": "res://scenes/diving/map_visuals/CommonLineR3CableVisual.tscn",
	"common_line_cable_r3_c4": "res://scenes/diving/map_visuals/CommonLineC4CableVisual.tscn",
}
const STORY_CABLE_ENDPOINTS := {
	"common_line_cable_j7_archive": [TUTORIAL_POSITIONS["junction_j7"], STORY_POSITIONS["archive_terminal"]],
	"common_line_cable_archive_r3": [STORY_POSITIONS["archive_terminal"], STORY_POSITIONS["r3_generator"]],
	"common_line_cable_r3_c4": [STORY_POSITIONS["r3_generator"], C4_POSITIONS["c4_switchboard"]],
}
const EXPECTED_CABLE_CONTROL_POINTS := {
	"res://scenes/diving/map_visuals/CommonLineCableVisual.tscn": [
		Vector2(0.0, 0.0),
		Vector2(-509.388, 311.77023),
		Vector2(-2525.388, 191.77023),
		Vector2(-2909.388, 415.77023),
		Vector2(-3245.388, 527.77023),
		Vector2(-3249.388, 551.77023),
		Vector2(-3469.388, 831.77023),
	],
	"res://scenes/diving/map_visuals/CommonLineArchiveCableVisual.tscn": [
		Vector2(0.0, 0.0),
		Vector2(288.0, -312.0),
		Vector2(296.0, -320.0),
		Vector2(304.0, -328.0),
		Vector2(992.0, -656.0),
		Vector2(2592.0, -664.0),
		Vector2(4192.0, -664.0),
		Vector2(5736.0, -120.0),
	],
	"res://scenes/diving/map_visuals/CommonLineR3CableVisual.tscn": [
		Vector2(0.0, 0.0),
		Vector2(848.0, 312.0),
		Vector2(2168.0, 688.0),
		Vector2(2752.0, 688.0),
		Vector2(2904.0, 696.0),
		Vector2(2952.0, 712.0),
		Vector2(2968.0, 728.0),
		Vector2(3152.0, 1160.0),
		Vector2(3160.0, 1216.0),
		Vector2(3200.0, 1544.0),
		Vector2(3200.0, 1560.0),
		Vector2(3168.0, 1632.0),
		Vector2(3080.0, 1712.0),
		Vector2(2776.0, 1768.0),
		Vector2(1952.0, 1680.0),
		Vector2(1780.0, 1600.0),
		Vector2(2040.0, 1760.0),
		Vector2(2320.0, 1940.0),
	],
	"res://scenes/diving/map_visuals/CommonLineC4CableVisual.tscn": [
		Vector2(0.0, 0.0),
		Vector2(-1080.0, 180.0),
		Vector2(-1128.0, 204.0),
		Vector2(-1872.0, 644.0),
		Vector2(-1944.0, 644.0),
		Vector2(-1976.0, 652.0),
		Vector2(-2232.0, 932.0),
		Vector2(-2232.0, 1244.0),
		Vector2(-2240.0, 1260.0),
		Vector2(-2424.0, 1428.0),
		Vector2(-2464.0, 1428.0),
		Vector2(-2704.0, 1692.0),
		Vector2(-2704.0, 1724.0),
		Vector2(-2712.0, 1740.0),
		Vector2(-2848.0, 1932.0),
		Vector2(-2928.0, 2004.0),
		Vector2(-3376.0, 2204.0),
		Vector2(-3416.0, 2204.0),
		Vector2(-4600.0, 2760.0),
	],
}
const BLOCKAGE_VISUAL_PATH := "res://scenes/diving/map_visuals/TutorialCableBlockageVisual.tscn"
const R1_J7_ART_CELL_VISUAL_PATH := "res://scenes/diving/map_visuals/R1J7ArtCell.tscn"
const R3_POWER_PLANT_MIDGROUND_VISUAL_PATH := "res://scenes/diving/map_visuals/R3PowerPlantMidgroundVisual.tscn"
const R1_ART_CELL_LIBRARY_PATH := "res://assets/diving/world/art_cells/r1/r1_art_cells_v1.json"
const UNDERWATER_MAP_SCENE_PATH := "res://scenes/diving/UnderwaterMap.tscn"
const R1_ART_CELL_SIZE := Vector2i(2730, 1536)
const R1_ART_CELL_WORLD_SIZE := Vector2i(11_520, 1536)
const R1_ART_CELL_OVERLAP := 426
const R1_ART_CELL_STRIDE := 2304
const R1_ART_CELL_Z_INDEX := -96
const R1_ART_CELL_VISUAL_REVISION := 2
const R1_QA_VIEWPORT_SIZE := Vector2i(1280, 720)
const R1_QA_CAMERA_ZOOM := 1.2
const R1_SOURCE_CONTENT_BAND := Rect2i(64, 600, 2602, 650)
const R1_SOURCE_CONTENT_DOWNSAMPLE := 4
const R1_SOURCE_CONTENT_GRADIENT_THRESHOLD := 3
const R1_SOURCE_CONTENT_MIN_COVERAGE := 0.04
const R1_SOURCE_CONTENT_BIN_COUNT := 8
const R1_SOURCE_CONTENT_BIN_MIN_COVERAGE := 0.02
const R1_SOURCE_CONTENT_MIN_PASSING_BINS := 5
const EXPECTED_R1_ART_CELLS := [
	{
		"id": "Background_001",
		"path": "res://assets/diving/world/art_cells/r1/r1_art_cell_001.png",
		"world_origin": Vector2i(0, 0),
	},
	{
		"id": "Background_002",
		"path": "res://assets/diving/world/art_cells/r1/r1_art_cell_002.png",
		"world_origin": Vector2i(2304, 0),
	},
	{
		"id": "Background_003",
		"path": "res://assets/diving/world/art_cells/r1/r1_art_cell_003.png",
		"world_origin": Vector2i(4608, 0),
	},
	{
		"id": "Background_004",
		"path": "res://assets/diving/world/art_cells/r1/r1_art_cell_004.png",
		"world_origin": Vector2i(6912, 0),
	},
	{
		"id": "Background_005",
		"path": "res://assets/diving/world/art_cells/r1/r1_art_cell_005.png",
		"world_origin": Vector2i(9216, 0),
	},
]
const EXPECTED_R1_QA_VISIBILITY_CASES := [
	{
		"id": "Background_001",
		"camera": Vector2i(1365, 960),
		"screen_roi": Rect2i(64, 0, 1152, 540),
	},
	{
		"id": "Background_002",
		"camera": Vector2i(3800, 960),
		"screen_roi": Rect2i(64, 80, 1152, 540),
	},
	{
		"id": "Background_003",
		"camera": Vector2i(5568, 960),
		"screen_roi": Rect2i(64, 0, 1152, 540),
	},
	{
		"id": "Background_004",
		"camera": Vector2i(8192, 960),
		"screen_roi": Rect2i(64, 0, 1152, 540),
	},
	{
		"id": "Background_005",
		"camera": Vector2i(9696, 1120),
		"screen_roi": Rect2i(64, 360, 1152, 344),
	},
]

const REQUIRED_AUTHORING_GROUPS := [
	"VisualLayers",
	"Terrain",
	"Terrain/TerrainNavigation",
	"Terrain/TerrainNavigation/TraversableAreas",
	"Terrain/TerrainNavigation/BlockedIslands",
	"DepthRegions",
	"Landmarks",
	"Entries",
	"Routes",
	"CurrentZones",
	"Gameplay",
	"Gameplay/Containers",
	"Gameplay/Pickups",
	"Gameplay/Threats",
	"Gameplay/HeavyObjects",
	"Gameplay/RescueEncounters",
	"Gameplay/BuoyAnchors",
	"Gameplay/ShortcutGates",
	"Gameplay/FixedDevices",
	"StaticObstacles",
	"Decorations",
	"RuntimeDynamic",
]

const REQUIRED_PREFABS := [
	"MapRegion.tscn",
	"MapLandmark.tscn",
	"MapEntryPoint.tscn",
	"MapExitLine.tscn",
	"MapConnection.tscn",
	"MapCurrentZone.tscn",
	"MapLootContainer.tscn",
	"MapPickup.tscn",
	"MapThreat.tscn",
	"MapHeavyObject.tscn",
	"MapRescue.tscn",
	"MapBuoy.tscn",
	"MapShortcutGate.tscn",
	"MapFixedDevice.tscn",
	"MapObstacle.tscn",
	"MapDecoration.tscn",
]

var _failures := 0


func _initialize() -> void:
	var compiler = MapCompilerScript.new()
	var world = WorldStateScript.new()
	world.setup(91_001)
	var generation_errors: PackedStringArray = compiler.generate(world, 91_001)
	_assert(generation_errors.is_empty(), "Scena mapy musi kompilować się bez błędów: %s" % "; ".join(generation_errors))
	_test_prefab_catalog()
	_test_r1_art_cell_layer()
	_test_shared_obstacle_raster()
	_test_chunked_boundary_segments()
	if generation_errors.is_empty():
		_test_compiled_manifest(world)
		_test_stale_source_version_is_rejected(compiler, world)
		_test_unique_authoring_ids()
		_test_visual_only_change_preserves_signature(compiler)
		_test_gameplay_position_change_updates_signature(compiler)
		_test_cable_transform_preserves_signature(compiler)
		_test_loot_content_change_updates_signature(compiler)
		_test_terrain_presentation_preserves_signature(compiler)
		_test_curve_route_is_compiled(compiler)
		_test_chunk_size_changes_signature(compiler)
		_test_obstacle_transform_is_compiled(compiler)
		_test_decoration_without_visual_is_rejected(compiler)
		_test_duplicate_id_is_rejected(compiler)
		await _test_runtime_layer_preserves_authored_siblings(world)
	if _failures > 0:
		push_error("Underwater map scene test failed with %d assertion(s)." % _failures)
		quit(1)
		return
	print("Underwater map scene test passed: Godot Polygon2D terrain, scene prefabs, Path2D cables and the shared runtime raster are validated.")
	quit(0)


func _test_prefab_catalog() -> void:
	for prefab_name in REQUIRED_PREFABS:
		var prefab_path := "res://scenes/diving/map_objects/%s" % prefab_name
		_assert(ResourceLoader.exists(prefab_path), "Brakuje prefabu authoringu mapy: %s." % prefab_path)


func _test_r1_art_cell_layer() -> void:
	var packed := ResourceLoader.load(UNDERWATER_MAP_SCENE_PATH) as PackedScene
	_assert(packed != null, "Scena mapy musi dać się załadować do kontroli warstwy R1 ArtCells.")
	if packed == null:
		return
	var map_root := packed.instantiate()
	var layer := map_root.get_node_or_null("VisualLayers/R1ArtCells") as Node2D
	_assert(layer != null, "UnderwaterMap musi publikować prezentacyjny slot VisualLayers/R1ArtCells.")
	if layer != null:
		_assert(layer.z_index == R1_ART_CELL_Z_INDEX, "R1 ArtCells muszą leżeć pod dalekim tłem i nie konkurować z kanonicznym terenem.")
		_assert(layer.get_child_count() == 0, "Scena nie może preloadować pełnych ArtCells; slot wypełnia streamer cropów.")
	_assert(FileAccess.file_exists(R1_ART_CELL_LIBRARY_PATH), "Biblioteka źródłowych R1 ArtCells musi być wersjonowanym JSON-em.")
	if FileAccess.file_exists(R1_ART_CELL_LIBRARY_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(R1_ART_CELL_LIBRARY_PATH))
		_assert(parsed is Dictionary, "Biblioteka R1 ArtCells musi mieć poprawny root JSON.")
		if parsed is Dictionary:
			var library: Dictionary = parsed
			var cells: Array = library.get("cells", [])
			_assert(int(library.get("schema_version", 0)) == 1, "Biblioteka R1 ArtCells musi mieć jawną wersję.")
			_assert(int(library.get("visual_revision", 0)) == R1_ART_CELL_VISUAL_REVISION, "Biblioteka R1 ArtCells musi wskazywać zaakceptowaną rewizję wizualną 2.")
			_assert(str(library.get("region_id", "")) == "R1", "Biblioteka ArtCells musi jednoznacznie należeć do R1.")
			var cell_size: Array = library.get("cell_size", [])
			_assert(
				cell_size.size() == 2
				and int(cell_size[0]) == R1_ART_CELL_SIZE.x
				and int(cell_size[1]) == R1_ART_CELL_SIZE.y,
				"Wszystkie R1 ArtCells muszą zachować stałe 2730x1536."
			)
			var world_size: Array = library.get("world_size", [])
			_assert(
				world_size.size() == 2
				and int(world_size[0]) == R1_ART_CELL_WORLD_SIZE.x
				and int(world_size[1]) == R1_ART_CELL_WORLD_SIZE.y,
				"Biblioteka R1 musi pokrywać dokładnie pas 11520x1536."
			)
			_assert(
				int(library.get("overlap", 0)) == R1_ART_CELL_OVERLAP
				and int(library.get("stride", 0)) == R1_ART_CELL_STRIDE,
				"Biblioteka R1 musi zachować zatwierdzony zakład 426 i stride 2304."
			)
			_assert(str(library.get("runtime_layer", "")) == "R1ArtCells", "Biblioteka R1 musi wskazywać wyłącznie slot prezentacyjny R1ArtCells.")
			_assert(int(library.get("runtime_z_index", 0)) == R1_ART_CELL_Z_INDEX, "Biblioteka R1 musi zachować runtime z-index -96.")
			_assert(str(library.get("runtime_light_mode", "")) == "unshaded", "Biblioteka R1 musi wymuszać unshaded dla ekstremalnie dalekiego planu.")
			_assert(cells.size() == EXPECTED_R1_ART_CELLS.size(), "Pełny pas R1 musi składać się z pięciu źródłowych ArtCells.")
			var seen_ids := {}
			var seen_paths := {}
			var source_images_by_id := {}
			for cell_index in range(mini(cells.size(), EXPECTED_R1_ART_CELLS.size())):
				var cell_variant = cells[cell_index]
				_assert(cell_variant is Dictionary, "Każdy wpis biblioteki R1 ArtCells musi być słownikiem.")
				if not (cell_variant is Dictionary):
					continue
				var cell: Dictionary = cell_variant
				var expected: Dictionary = EXPECTED_R1_ART_CELLS[cell_index]
				var cell_id := str(cell.get("id", ""))
				var source_path := str(cell.get("path", ""))
				var world_origin: Array = cell.get("world_origin", [])
				var expected_origin: Vector2i = expected.get("world_origin", Vector2i.ZERO)
				_assert(cell_id == str(expected.get("id", "")), "R1 ArtCell %d musi zachować dokładne ID %s." % [cell_index + 1, expected.get("id", "")])
				_assert(source_path == str(expected.get("path", "")), "R1 ArtCell %s musi zachować dokładną ścieżkę źródła." % cell_id)
				_assert(not seen_ids.has(cell_id), "ID R1 ArtCell nie może się powtarzać: %s." % cell_id)
				_assert(not seen_paths.has(source_path), "Ścieżka źródłowa R1 ArtCell nie może się powtarzać: %s." % source_path)
				seen_ids[cell_id] = true
				seen_paths[source_path] = true
				_assert(
					world_origin.size() == 2
					and int(world_origin[0]) == expected_origin.x
					and int(world_origin[1]) == expected_origin.y,
					"R1 ArtCell %s musi zachować world_origin %s." % [cell_id, expected_origin]
				)
				_assert(FileAccess.file_exists(source_path), "Każdy R1 ArtCell musi wskazywać istniejący PNG: %s." % source_path)
				if FileAccess.file_exists(source_path):
					var source_image := Image.load_from_file(ProjectSettings.globalize_path(source_path))
					_assert(not source_image.is_empty(), "Źródłowy R1 ArtCell musi być poprawnym obrazem: %s." % source_path)
					if not source_image.is_empty():
						_assert(source_image.get_size() == R1_ART_CELL_SIZE, "Źródłowy R1 ArtCell musi mieć rzeczywisty rozmiar 2730x1536: %s." % source_path)
						if source_image.get_size() == R1_ART_CELL_SIZE:
							_assert_r1_source_content(source_image, source_path)
							source_images_by_id[cell_id] = source_image
			_assert_r1_qa_visibility_cases(library, cells)
			_assert_r1_pixel_identical_overlaps(source_images_by_id)
	map_root.free()


func _assert_r1_qa_visibility_cases(library: Dictionary, cells: Array) -> void:
	var cases: Array = library.get("qa_visibility_cases", [])
	_assert(
		cases.size() == EXPECTED_R1_QA_VISIBILITY_CASES.size(),
		"Biblioteka R1 musi publikować dokładnie pięć przypadków QA widoczności."
	)
	var seen_case_ids := {}
	var half_viewport := Vector2(
		float(R1_QA_VIEWPORT_SIZE.x) / (2.0 * R1_QA_CAMERA_ZOOM),
		float(R1_QA_VIEWPORT_SIZE.y) / (2.0 * R1_QA_CAMERA_ZOOM)
	)
	for case_index in range(mini(cases.size(), EXPECTED_R1_QA_VISIBILITY_CASES.size())):
		var case_variant = cases[case_index]
		_assert(case_variant is Dictionary, "Każdy przypadek QA widoczności R1 musi być słownikiem.")
		if not (case_variant is Dictionary):
			continue
		var visibility_case: Dictionary = case_variant
		var expected: Dictionary = EXPECTED_R1_QA_VISIBILITY_CASES[case_index]
		var case_id := str(visibility_case.get("id", ""))
		var camera_values: Array = visibility_case.get("camera", [])
		var roi_values: Array = visibility_case.get("screen_roi", [])
		_assert(
			_visibility_case_has_exact_keys(visibility_case),
			"Przypadek QA %s może zawierać wyłącznie id, camera i screen_roi." % case_id
		)
		var camera_is_valid := _is_exact_integer_array(camera_values, 2)
		var roi_is_valid := _is_exact_integer_array(roi_values, 4)
		_assert(camera_is_valid, "Przypadek QA %s musi mieć dwuelementową całkowitą kamerę." % case_id)
		_assert(roi_is_valid, "Przypadek QA %s musi mieć czteroelementowy całkowity screen_roi." % case_id)
		var camera := Vector2i.ZERO
		var screen_roi := Rect2i()
		if camera_is_valid:
			camera = Vector2i(int(camera_values[0]), int(camera_values[1]))
		if roi_is_valid:
			screen_roi = Rect2i(
				int(roi_values[0]),
				int(roi_values[1]),
				int(roi_values[2]),
				int(roi_values[3])
			)
		var expected_id := str(expected.get("id", ""))
		var expected_camera: Vector2i = expected.get("camera", Vector2i.ZERO)
		var expected_roi: Rect2i = expected.get("screen_roi", Rect2i())
		_assert(case_id == expected_id, "Przypadek QA %d musi zachować dokładne ID %s." % [case_index + 1, expected_id])
		_assert(not seen_case_ids.has(case_id), "ID przypadku QA widoczności nie może się powtarzać: %s." % case_id)
		seen_case_ids[case_id] = true
		_assert(camera == expected_camera, "Przypadek QA %s musi zachować kamerę %s." % [case_id, expected_camera])
		_assert(screen_roi == expected_roi, "Przypadek QA %s musi zachować screen_roi %s." % [case_id, expected_roi])
		if case_index < cells.size() and cells[case_index] is Dictionary:
			_assert(
				case_id == str((cells[case_index] as Dictionary).get("id", "")),
				"Przypadek QA %s musi odpowiadać źródłowemu ArtCell o tym samym ID." % case_id
			)

		var camera_position := Vector2(camera)
		_assert(
			camera_position.x - half_viewport.x >= 0.0
				and camera_position.x + half_viewport.x <= float(R1_ART_CELL_WORLD_SIZE.x)
				and camera_position.y - half_viewport.y >= 0.0
				and camera_position.y + half_viewport.y <= float(R1_ART_CELL_WORLD_SIZE.y),
			"Kamera przypadku QA %s musi mieścić pełny kadr w pasie R1." % case_id
		)
		_assert(
			screen_roi.position.x >= 0
				and screen_roi.position.y >= 0
				and screen_roi.size.x > 0
				and screen_roi.size.y > 0
				and screen_roi.end.x <= R1_QA_VIEWPORT_SIZE.x
				and screen_roi.end.y <= R1_QA_VIEWPORT_SIZE.y,
			"screen_roi przypadku QA %s musi mieścić się w viewport 1280x720." % case_id
		)

		var expected_cell: Dictionary = EXPECTED_R1_ART_CELLS[case_index]
		var cell_origin_i: Vector2i = expected_cell.get("world_origin", Vector2i.ZERO)
		var cell_origin := Vector2(cell_origin_i)
		var cell_end := Vector2(
			minf(float(cell_origin_i.x + R1_ART_CELL_SIZE.x), float(R1_ART_CELL_WORLD_SIZE.x)),
			minf(float(cell_origin_i.y + R1_ART_CELL_SIZE.y), float(R1_ART_CELL_WORLD_SIZE.y))
		)
		var world_roi_begin := (
			camera_position
			- half_viewport
			+ Vector2(screen_roi.position) / R1_QA_CAMERA_ZOOM
		)
		var world_roi_end := (
			camera_position
			- half_viewport
			+ Vector2(screen_roi.end) / R1_QA_CAMERA_ZOOM
		)
		_assert(
			world_roi_begin.x >= cell_origin.x
				and world_roi_begin.y >= cell_origin.y
				and world_roi_end.x <= cell_end.x
				and world_roi_end.y <= cell_end.y,
			"screen_roi przypadku QA %s musi rzutować się w całości wewnątrz jego ArtCell." % case_id
		)


func _visibility_case_has_exact_keys(visibility_case: Dictionary) -> bool:
	if visibility_case.size() != 3:
		return false
	return (
		visibility_case.has("id")
		and visibility_case.has("camera")
		and visibility_case.has("screen_roi")
	)


func _is_exact_integer_array(values: Array, expected_size: int) -> bool:
	if values.size() != expected_size:
		return false
	for value in values:
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			return false
		if float(value) != float(int(value)):
			return false
	return true


func _assert_r1_source_content(source_image: Image, source_path: String) -> void:
	var normalized := source_image.duplicate() as Image
	normalized.convert(Image.FORMAT_RGB8)
	var source_data := normalized.get_data()
	var source_width := normalized.get_width()
	var downsampled_width := floori(
		float(R1_SOURCE_CONTENT_BAND.size.x) / float(R1_SOURCE_CONTENT_DOWNSAMPLE)
	)
	var downsampled_height := floori(
		float(R1_SOURCE_CONTENT_BAND.size.y) / float(R1_SOURCE_CONTENT_DOWNSAMPLE)
	)
	var downsampled := PackedByteArray()
	downsampled.resize(downsampled_width * downsampled_height)
	for output_y in range(downsampled_height):
		for output_x in range(downsampled_width):
			var red_sum := 0
			var green_sum := 0
			var blue_sum := 0
			for block_y in range(R1_SOURCE_CONTENT_DOWNSAMPLE):
				var source_offset := (
					(
						R1_SOURCE_CONTENT_BAND.position.y
						+ output_y * R1_SOURCE_CONTENT_DOWNSAMPLE
						+ block_y
					) * source_width
					+ R1_SOURCE_CONTENT_BAND.position.x
					+ output_x * R1_SOURCE_CONTENT_DOWNSAMPLE
				) * 3
				for _block_x in range(R1_SOURCE_CONTENT_DOWNSAMPLE):
					red_sum += int(source_data[source_offset])
					green_sum += int(source_data[source_offset + 1])
					blue_sum += int(source_data[source_offset + 2])
					source_offset += 3
			var weighted_sum := 299 * red_sum + 587 * green_sum + 114 * blue_sum
			downsampled[output_y * downsampled_width + output_x] = clampi(
				int(float(weighted_sum + 8000) / 16000.0),
				0,
				255
			)

	var structured_count := 0
	var total_count := 0
	var bin_structured := PackedInt32Array()
	var bin_totals := PackedInt32Array()
	bin_structured.resize(R1_SOURCE_CONTENT_BIN_COUNT)
	bin_totals.resize(R1_SOURCE_CONTENT_BIN_COUNT)
	var gradient_width := downsampled_width - 1
	var gradient_height := downsampled_height - 1
	for y in range(gradient_height):
		for x in range(gradient_width):
			var offset := y * downsampled_width + x
			var gradient := maxi(
				absi(int(downsampled[offset + 1]) - int(downsampled[offset])),
				absi(int(downsampled[offset + downsampled_width]) - int(downsampled[offset]))
			)
			var bin_index := mini(
				R1_SOURCE_CONTENT_BIN_COUNT - 1,
				floori(float(x * R1_SOURCE_CONTENT_BIN_COUNT) / float(gradient_width))
			)
			total_count += 1
			bin_totals[bin_index] += 1
			if gradient >= R1_SOURCE_CONTENT_GRADIENT_THRESHOLD:
				structured_count += 1
				bin_structured[bin_index] += 1

	var global_coverage := float(structured_count) / float(maxi(total_count, 1))
	var passing_bins := 0
	var formatted_bins := PackedStringArray()
	for bin_index in range(R1_SOURCE_CONTENT_BIN_COUNT):
		var bin_coverage := (
			float(bin_structured[bin_index])
			/ float(maxi(bin_totals[bin_index], 1))
		)
		formatted_bins.append("%.2f%%" % (bin_coverage * 100.0))
		if bin_coverage >= R1_SOURCE_CONTENT_BIN_MIN_COVERAGE:
			passing_bins += 1
	_assert(
		global_coverage >= R1_SOURCE_CONTENT_MIN_COVERAGE
			and passing_bins >= R1_SOURCE_CONTENT_MIN_PASSING_BINS,
		(
			"Źródłowy R1 ArtCell ma za mało autorskiej struktury: %s; global=%.2f%% "
			+ "(minimum %.2f%%), segmenty=%d/%d (minimum %d), bins=[%s]."
		) % [
			source_path,
			global_coverage * 100.0,
			R1_SOURCE_CONTENT_MIN_COVERAGE * 100.0,
			passing_bins,
			R1_SOURCE_CONTENT_BIN_COUNT,
			R1_SOURCE_CONTENT_MIN_PASSING_BINS,
			", ".join(formatted_bins),
		]
	)


func _assert_r1_pixel_identical_overlaps(source_images_by_id: Dictionary) -> void:
	for cell_index in range(1, EXPECTED_R1_ART_CELLS.size()):
		var previous_id := str(EXPECTED_R1_ART_CELLS[cell_index - 1].get("id", ""))
		var current_id := str(EXPECTED_R1_ART_CELLS[cell_index].get("id", ""))
		if not source_images_by_id.has(previous_id) or not source_images_by_id.has(current_id):
			continue
		var previous := (source_images_by_id[previous_id] as Image).duplicate() as Image
		var current := (source_images_by_id[current_id] as Image).duplicate() as Image
		previous.convert(Image.FORMAT_RGBA8)
		current.convert(Image.FORMAT_RGBA8)
		var previous_overlap := previous.get_region(
			Rect2i(
				R1_ART_CELL_SIZE.x - R1_ART_CELL_OVERLAP,
				0,
				R1_ART_CELL_OVERLAP,
				R1_ART_CELL_SIZE.y
			)
		)
		var current_overlap := current.get_region(
			Rect2i(0, 0, R1_ART_CELL_OVERLAP, R1_ART_CELL_SIZE.y)
		)
		_assert(
			previous_overlap.get_data() == current_overlap.get_data(),
			"Zakład %s/%s musi być identyczny pikselowo na pełnych 426 px."
			% [previous_id, current_id]
		)


func _test_compiled_manifest(world) -> void:
	var blueprint = world.blueprint
	_assert(int(blueprint.map_source_version) == int(MapCompilerScript.MAP_SOURCE_VERSION), "Migawka musi wskazywać aktualną wersję sceny.")
	_assert(not str(blueprint.map_gameplay_signature).is_empty(), "Migawka musi wskazywać bieżącą tożsamość gameplayową mapy.")
	_assert(not str(blueprint.map_id).is_empty(), "Scena musi przekazać stabilne Map ID.")
	_assert(str(blueprint.map_gameplay_signature).length() == 64, "Mapa musi otrzymać 64-znakowy podpis gameplayowy.")
	_assert(not blueprint.entry_landmark_id.is_empty() and blueprint.landmark_lookup.has(blueprint.entry_landmark_id), "Entry Point musi wskazywać istniejący landmark.")
	_assert(blueprint.fixed_device_spawns.size() == 6, "Mapa musi kompilować J-7, Archiwum, dwa etapy R-3, Rozdzielnię C-4 i gniazdo Rozdzielacza.")
	_assert(blueprint.shortcut_spawns.size() == 8, "Mapa musi zachować dokładnie osiem istniejących skrótów; blokada kabla wykorzystuje SC-01 zamiast tworzyć dziewiąty.")
	_assert(_vectors_match(blueprint.exit_position, TUTORIAL_POSITIONS["exit_line"]), "Lina platformy musi zachować zatwierdzoną pozycję startową kabla.")
	var junction: Dictionary = _record_by_id(blueprint.fixed_device_spawns, "junction_j7")
	_assert(junction.get("id", "") == "junction_j7" and junction.get("device_role", "") == "common_line_junction", "J-7 musi zachować stabilne ID i typowaną rolę urządzenia.")
	_assert(int(junction.get("available_from_day", 0)) == 3, "J-7 musi być dostępne dopiero w trzecim dniu kampanii.")
	_assert(_record_position_matches(junction, TUTORIAL_POSITIONS["junction_j7"]), "J-7 musi kończyć kabel w zatwierdzonej pozycji tutoriala.")
	var archive_terminal: Dictionary = _record_by_id(blueprint.fixed_device_spawns, "archive_terminal")
	_assert(archive_terminal.get("landmark_id", "") == "R1-09" and archive_terminal.get("device_role", "") == "common_line_archive_terminal", "Terminal Archiwum musi należeć do R1-09 i zachować typowaną rolę.")
	_assert(int(archive_terminal.get("available_from_day", 0)) == 4 and archive_terminal.get("required_tool", "") == "crowbar", "Terminal Archiwum musi być dostępny po tutorialu i wymagać łomu.")
	_assert(_record_position_matches(archive_terminal, STORY_POSITIONS["archive_terminal"]), "Terminal Archiwum musi zachować zatwierdzony, rozdzielony punkt interakcji.")
	var r3_diagnostic: Dictionary = _record_by_id(blueprint.fixed_device_spawns, "r3_diagnostic_panel")
	_assert(r3_diagnostic.get("landmark_id", "") == "R3-04" and r3_diagnostic.get("required_tool", "") == "r3_diagnostic_access", "Diagnostyka R-3 musi należeć do Elektrowni i wymagać zamrożonego dostępu uzyskanego po Archiwum.")
	_assert(_record_position_matches(r3_diagnostic, STORY_POSITIONS["r3_diagnostic_panel"]), "Panel diagnostyczny R-3 musi mieć własny, zatwierdzony punkt interakcji.")
	var r3_generator: Dictionary = _record_by_id(blueprint.fixed_device_spawns, "r3_generator")
	_assert(r3_generator.get("landmark_id", "") == "R3-04" and r3_generator.get("required_tool", "") == "r3_regulator", "Generator R-3 musi wymagać wykonanego Regulatora R-3.")
	_assert(_record_position_matches(r3_generator, STORY_POSITIONS["r3_generator"]), "Generator R-3 musi mieć własny, zatwierdzony punkt interakcji.")
	var c4_switchboard: Dictionary = _record_by_id(blueprint.fixed_device_spawns, "c4_switchboard")
	_assert(c4_switchboard.get("landmark_id", "") == "R4-06" and c4_switchboard.get("required_tool", "") == "c4_control_access", "Rozdzielnia C-4 musi należeć do Serca i wymagać aktywnego sterowania R-3.")
	_assert(_record_position_matches(c4_switchboard, C4_POSITIONS["c4_switchboard"]), "Rozdzielnia C-4 musi mieć własny, zatwierdzony punkt interakcji.")
	var splitter_mount: Dictionary = _record_by_id(blueprint.fixed_device_spawns, "c4_splitter_mount")
	_assert(splitter_mount.get("landmark_id", "") == "R4-06" and splitter_mount.get("required_tool", "") == "common_line_splitter", "Gniazdo Rozdzielacza musi należeć do Serca i wymagać wykonanego Rozdzielacza.")
	_assert(_record_position_matches(splitter_mount, C4_POSITIONS["c4_splitter_mount"]), "Gniazdo Rozdzielacza C-4 musi mieć własny, zatwierdzony punkt interakcji.")
	_assert(blueprint.entry_position != Vector2.ZERO and blueprint.exit_position != Vector2.ZERO, "Scena musi zawierać jawne pozycje wejścia i wyjścia.")
	_assert(not blueprint.regions.is_empty(), "Mapa musi zawierać co najmniej jeden region.")
	_assert(not blueprint.landmarks.is_empty(), "Mapa musi zawierać co najmniej jeden landmark.")
	var r1_j7: Dictionary = _record_by_id(blueprint.landmarks, "R1-04")
	_assert(str(r1_j7.get("visual_scene_path", "")) == R1_J7_ART_CELL_VISUAL_PATH, "Parking R1-04 musi instancjować zatwierdzony ArtCell Węzła J-7.")
	_assert(int(r1_j7.get("visual_z_index", 0)) == -60, "Płyta R1/J-7 musi pozostać za terenem i obiektami gameplayowymi.")
	_assert_visual_scene_collision_free(R1_J7_ART_CELL_VISUAL_PATH, "ArtCell R1-04/J-7")
	var r3_power_plant: Dictionary = _record_by_id(blueprint.landmarks, "R3-04")
	_assert(str(r3_power_plant.get("visual_scene_path", "")) == R3_POWER_PLANT_MIDGROUND_VISUAL_PATH, "Elektrownia R3-04 musi instancjować zatwierdzony autorski średni plan.")
	_assert(int(r3_power_plant.get("visual_z_index", 0)) == -56, "Średni plan R3-04 musi pozostać za terenem i obiektami gameplayowymi.")
	_assert_visual_scene_collision_free(R3_POWER_PLANT_MIDGROUND_VISUAL_PATH, "Autorski średni plan R3-04")
	_assert(not blueprint.loot_spawns.is_empty(), "Mapa musi zawierać prefab źródła łupu lub itemu.")
	for loot_record in blueprint.loot_spawns:
		_assert(
			not str(loot_record.get("landmark_id", "")).is_empty(),
			"Każde źródło łupu i każdy pickup muszą jawnie wskazywać swój landmark: %s."
			% str(loot_record.get("id", ""))
		)
	var expected_food_by_loot_id := {
		"tutorial_market_crate": 6,
		"pharmacy_medicine_case": 4,
		"hotel_linen_cache": 6,
		"pickup_r1_food_01": 1,
		"greenhouse_supply_box": 8,
		"seed_bank_vault": 11,
		"park_service_shed": 2,
		"pickup_r2_food_01": 1,
		"port_tool_crate": 3,
		"power_plant_service_store": 3,
		"scrapyard_sorting_cache": 3,
		"pickup_r3_food_01": 1,
		"metro_maintenance_store": 2,
		"bunker_construction_reserve": 2,
		"city_center_relief_store": 4,
		"pickup_r4_food_01": 1,
	}
	var expected_food_ids_by_region := {
		"R1": ["tutorial_market_crate", "pharmacy_medicine_case", "hotel_linen_cache", "pickup_r1_food_01"],
		"R2": ["greenhouse_supply_box", "seed_bank_vault", "park_service_shed", "pickup_r2_food_01"],
		"R3": ["port_tool_crate", "power_plant_service_store", "scrapyard_sorting_cache", "pickup_r3_food_01"],
		"R4": ["metro_maintenance_store", "bunker_construction_reserve", "city_center_relief_store", "pickup_r4_food_01"],
	}
	var expected_food_by_region := {"R1": 17, "R2": 22, "R3": 10, "R4": 9}
	var total_food := 0
	for loot_record in blueprint.loot_spawns:
		var contents: Dictionary = loot_record.get("contents", {})
		var food_amount := int(contents.get("food", 0))
		total_food += food_amount
		if food_amount > 0:
			var loot_id := str(loot_record.get("id", ""))
			_assert(expected_food_by_loot_id.has(loot_id), "Każde źródło żywności musi należeć do jawnego kontraktu regionalnego: %s." % loot_id)
			_assert(food_amount == int(expected_food_by_loot_id.get(loot_id, -1)), "Źródło %s musi zachować uzgodnioną ilość żywności." % loot_id)
	_assert(total_food == 58, "Standardowa mapa musi zawierać dokładnie 58 jednostek żywności.")
	for region_id in expected_food_ids_by_region.keys():
		var region_food := 0
		for loot_id in expected_food_ids_by_region.get(region_id, []):
			var record := _record_by_id(blueprint.loot_spawns, str(loot_id))
			var contents: Dictionary = record.get("contents", {})
			region_food += int(contents.get("food", 0))
		_assert(region_food == int(expected_food_by_region.get(region_id, -1)), "Region %s musi zachować uzgodniony budżet żywności." % region_id)
	var tutorial_food: Dictionary = _record_by_id(blueprint.loot_spawns, "tutorial_market_crate")
	_assert(int(tutorial_food.get("mandatory_order", -1)) == 0 and int(tutorial_food.get("contents", {}).get("food", 0)) == 6, "Obowiązkowe 6 żywności tutoriala musi pozostać dokładne; runtime wyłącza skalowanie dla każdego mandatory_order >= 0.")
	_assert(_record_position_matches(tutorial_food, TUTORIAL_POSITIONS["tutorial_market_crate"]), "Skrzynia targowa musi leżeć na pierwszym zakotwiczeniu kabla.")
	var tutorial_workshop: Dictionary = _record_by_id(blueprint.loot_spawns, "tutorial_workshop_case")
	_assert(_record_position_matches(tutorial_workshop, TUTORIAL_POSITIONS["tutorial_workshop_case"]), "Skrzynia warsztatowa musi leżeć na drugim zakotwiczeniu kabla.")
	var r3_food_pickup: Dictionary = _record_by_id(blueprint.loot_spawns, "pickup_r3_food_01")
	_assert(_record_position_matches(r3_food_pickup, R3_FOOD_PICKUP_POSITION), "Żywność R-3 musi zachować punkt z bezpiecznym prześwitem i odstępem selektora.")
	_assert(_nearest_landmark_id(blueprint, r3_food_pickup) == "R3-01", "Żywność R-3 musi przestrzennie należeć do Nadbrzeża R3-01 zgodnie z authored linkiem.")
	var structural_cache: Dictionary = _record_by_id(blueprint.loot_spawns, "heart_structural_cache")
	_assert(_record_position_matches(structural_cache, C4_POSITIONS["heart_structural_cache"]), "Rdzeń konstrukcyjny musi być oddzielony od urządzeń C-4.")
	var reconstruction_reserve: Dictionary = _record_by_id(blueprint.loot_spawns, "heart_reconstruction_reserve")
	_assert(_record_position_matches(reconstruction_reserve, C4_POSITIONS["heart_reconstruction_reserve"]), "Rezerwa odbudowy musi być oddzielona od pozostałych interakcji C-4.")
	_assert(not blueprint.heavy_object_spawns.is_empty(), "Mapa musi zawierać prefab ciężkiego obiektu.")
	_assert(not blueprint.rescue_spawns.is_empty(), "Mapa musi zawierać prefab celu ratunkowego.")
	var leon: Dictionary = _record_by_id(blueprint.rescue_spawns, "rescue_hotel_leon")
	_assert(_record_position_matches(leon, STORY_POSITIONS["rescue_hotel_leon"]), "Leon musi mieć własny, zatwierdzony punkt interakcji w hotelu.")
	_assert(_nearest_landmark_id(blueprint, leon) == "R1-03", "Punkt ratunku Leona musi przestrzennie należeć do Zatopionego Hotelu R1-03.")
	_assert(_nearest_landmark_id(blueprint, _record_by_id(blueprint.heavy_object_spawns, "ship_engine_r1")) == "R1-07", "Silnik statku musi pozostać przy Statku w Ulicy R1-07.")
	_assert(_nearest_landmark_id(blueprint, _record_by_id(blueprint.heavy_object_spawns, "shipyard_winch_r3")) == "R3-02", "Wyciągarka musi pozostać przy Starej Stoczni R3-02.")
	_assert(_nearest_landmark_id(blueprint, _record_by_id(blueprint.heavy_object_spawns, "scrapyard_generator_r3")) == "R3-06", "Ciężki generator musi pozostać przy Złomowisku R3-06.")
	_assert(not blueprint.buoy_spawns.is_empty(), "Mapa musi zawierać prefab boi.")
	for buoy_id in BUOY_POSITIONS:
		var buoy: Dictionary = _record_by_id(blueprint.buoy_spawns, buoy_id)
		_assert(
			_record_position_matches(buoy, BUOY_POSITIONS[buoy_id]),
			"Kotwica %s musi zachować zatwierdzony, bezpieczny punkt wejścia." % buoy_id
		)
	_assert(not blueprint.shortcut_spawns.is_empty(), "Mapa musi zawierać prefab bramy skrótu.")
	_assert(_has_authoring_kind(blueprint.decoration_spawns, "exit_line"), "Linia wyjścia musi zachować rekord prezentacyjny do przypięcia prefabu.")
	var cable_blockage: Dictionary = _record_by_id(blueprint.shortcut_spawns, "SC-01")
	_assert(_record_position_matches(cable_blockage, TUTORIAL_POSITIONS["SC-01"]), "Blokada SC-01 musi leżeć na zatwierdzonym zakotwiczeniu kabla.")
	_assert(str(cable_blockage.get("connection_id", "")) == "SC-01", "Blokada kabla musi zachować istniejące połączenie SC-01.")
	_assert(str(cable_blockage.get("required_tool", "")) == "knife", "Blokada kabla musi wymagać noża.")
	_assert(str(cable_blockage.get("interaction_action", "")) == "cut", "Blokada kabla musi publikować akcję przecięcia.")
	_assert(str(cable_blockage.get("visual_scene_path", "")) == BLOCKAGE_VISUAL_PATH, "SC-01 musi używać dedykowanego prefabu sieci i roślinności.")
	var cable_decoration: Dictionary = _record_by_id(blueprint.decoration_spawns, CABLE_DECORATION_ID)
	_assert(str(cable_decoration.get("visual_scene_path", "")) == CABLE_VISUAL_PATH, "Kabel platforma — J-7 musi mieć jawny prefab wizualny.")
	_assert(not bool(cable_decoration.get("blocks_navigation", true)), "Kabel jest wskazówką prezentacyjną i nie może blokować nawigacji.")
	_assert(_record_position_matches(cable_decoration, TUTORIAL_POSITIONS["exit_line"]), "Początek prefabu kabla musi być zakotwiczony przy linie platformy.")
	_assert_visual_scene_collision_free(CABLE_VISUAL_PATH, "Prefab kabla")
	_assert_visual_scene_collision_free(BLOCKAGE_VISUAL_PATH, "Prefab blokady kabla")
	_assert_tutorial_cable_anchors(cable_decoration)
	_assert_story_cables_are_non_blocking(blueprint)
	_assert_critical_interactable_separation(blueprint)
	_assert_all_selectable_interactables_are_separated(blueprint)
	_assert_unique_static_gameplay_positions(blueprint)


func _test_unique_authoring_ids() -> void:
	var map_root := _instantiate_map()
	if map_root == null:
		return
	_assert(str(map_root.get("navigation_cells_sha256")).length() == 64, "Scena musi przechowywać eksportowalny skrót komórek makroterenu.")
	_assert(str(map_root.get("navigation_signature_sha256")).length() == 64, "Scena musi przechowywać stabilny skrót zgodności zapisu mapy.")
	var object_ids: Dictionary = {}
	var connection_ids: Dictionary = {}
	for node in map_root.find_children("*", "", true, false):
		if node is DiveMapObject:
			var object := node as DiveMapObject
			_assert(not object.object_id.is_empty(), "Każdy prefab obiektu, w tym dekoracja, musi mieć Object ID.")
			_assert(not object_ids.has(object.object_id), "Object ID musi być unikalne: %s." % object.object_id)
			object_ids[object.object_id] = true
		elif node is DiveMapConnection:
			var connection := node as DiveMapConnection
			_assert(not connection.connection_id.is_empty(), "Każda trasa musi mieć Connection ID.")
			_assert(not connection_ids.has(connection.connection_id), "Connection ID musi być unikalne: %s." % connection.connection_id)
			connection_ids[connection.connection_id] = true
	for group_path in REQUIRED_AUTHORING_GROUPS:
		_assert(map_root.get_node_or_null(group_path) != null, "Scena musi mieć wymaganą gałąź authoringu: %s." % group_path)
	map_root.free()


func _test_visual_only_change_preserves_signature(compiler) -> void:
	var map_root := _instantiate_map()
	if map_root == null:
		return
	var baseline: Dictionary = compiler.compile_map(map_root, 91_003)
	var baseline_errors: PackedStringArray = baseline.get("errors", PackedStringArray())
	_assert(baseline_errors.is_empty(), "Bazowa scena musi kompilować się przed testem prezentacji.")
	if not baseline_errors.is_empty():
		map_root.free()
		return
	var authored_object: DiveMapObject
	for node in map_root.find_children("*", "", true, false):
		if node is DiveMapObject and (node as DiveMapObject).kind == DiveMapObject.Kind.LOOT_CONTAINER:
			authored_object = node as DiveMapObject
			break
	_assert(authored_object != null, "Test wymaga co najmniej jednego kontenera w scenie.")
	if authored_object == null:
		map_root.free()
		return
	authored_object.visual_offset += Vector2(17.0, -9.0)
	authored_object.visual_rotation_degrees += 7.5
	authored_object.skew += deg_to_rad(3.0)
	authored_object.visual_scene = ResourceLoader.load(R3_POWER_PLANT_MIDGROUND_VISUAL_PATH) as PackedScene
	authored_object.visual_z_index -= 56
	var changed: Dictionary = compiler.compile_map(map_root, 91_003)
	var changed_errors: PackedStringArray = changed.get("errors", PackedStringArray())
	_assert(changed_errors.is_empty(), "Zmiana prezentacyjna nie może zepsuć kompilacji mapy.")
	if changed_errors.is_empty():
		var baseline_blueprint = baseline.get("blueprint")
		var changed_blueprint = changed.get("blueprint")
		_assert(str(baseline_blueprint.map_gameplay_signature) == str(changed_blueprint.map_gameplay_signature), "Scena, warstwa z, offset, obrót i skew prezentacji nie mogą zmieniać podpisu gameplayowego obiektu punktowego.")
		var changed_record := _record_by_id(changed_blueprint.loot_spawns, authored_object.object_id)
		_assert(changed_record.get("visual_offset", Vector2.ZERO) == authored_object.visual_offset, "Kompilator musi przekazać offset prefabu do runtime.")
		_assert(str(changed_record.get("visual_scene_path", "")) == R3_POWER_PLANT_MIDGROUND_VISUAL_PATH and int(changed_record.get("visual_z_index", 0)) == authored_object.visual_z_index, "Kompilator musi przekazać prefab i z-index prezentacji do runtime.")
	map_root.free()


func _test_gameplay_position_change_updates_signature(compiler) -> void:
	var map_root := _instantiate_map()
	if map_root == null:
		return
	var baseline: Dictionary = compiler.compile_map(map_root, 91_015)
	var baseline_errors: PackedStringArray = baseline.get("errors", PackedStringArray())
	_assert(baseline_errors.is_empty(), "Bazowa scena musi kompilować się przed testem pozycji gameplayowej.")
	if baseline_errors.is_empty():
		var tutorial_container := _authored_object_by_id(map_root, "tutorial_market_crate")
		_assert(tutorial_container != null, "Test pozycji gameplayowej wymaga tutorial_market_crate.")
		if tutorial_container != null:
			tutorial_container.position += Vector2(8.0, 0.0)
			var changed: Dictionary = compiler.compile_map(map_root, 91_015)
			var changed_errors: PackedStringArray = changed.get("errors", PackedStringArray())
			_assert(changed_errors.is_empty(), "Niewielkie przesunięcie kontenera na otwartej komórce nie może zepsuć kompilacji mapy.")
			if changed_errors.is_empty():
				var baseline_blueprint = baseline.get("blueprint")
				var changed_blueprint = changed.get("blueprint")
				_assert(
					str(baseline_blueprint.map_gameplay_signature) != str(changed_blueprint.map_gameplay_signature),
					"Zmiana pozycji statycznego interaktywnego przedmiotu musi zmieniać podpis gameplayowy mapy."
				)
	map_root.free()


func _test_cable_transform_preserves_signature(compiler) -> void:
	var map_root := _instantiate_map()
	if map_root == null:
		return
	var baseline: Dictionary = compiler.compile_map(map_root, 91_016)
	var baseline_errors: PackedStringArray = baseline.get("errors", PackedStringArray())
	_assert(baseline_errors.is_empty(), "Bazowa scena musi kompilować się przed testem transformacji kabla.")
	if baseline_errors.is_empty():
		var cable_decoration := _authored_object_by_id(map_root, CABLE_DECORATION_ID)
		_assert(cable_decoration != null, "Test transformacji prezentacyjnej wymaga dekoracji kabla platforma — J-7.")
		if cable_decoration != null:
			cable_decoration.position += Vector2(17.0, -9.0)
			cable_decoration.rotation += 0.07
			cable_decoration.scale = Vector2(1.01, 0.99)
			var changed: Dictionary = compiler.compile_map(map_root, 91_016)
			var changed_errors: PackedStringArray = changed.get("errors", PackedStringArray())
			_assert(changed_errors.is_empty(), "Zmiana transformacji bezkolizyjnego kabla nie może zepsuć kompilacji mapy.")
			if changed_errors.is_empty():
				var baseline_blueprint = baseline.get("blueprint")
				var changed_blueprint = changed.get("blueprint")
				var changed_record := _record_by_id(changed_blueprint.decoration_spawns, CABLE_DECORATION_ID)
				_assert(
					str(baseline_blueprint.map_gameplay_signature) == str(changed_blueprint.map_gameplay_signature),
					"Transformacja kabla-dekoracji nie może zmieniać podpisu gameplayowego mapy."
				)
				_assert(
					_record_position_matches(changed_record, cable_decoration.global_position),
					"Kompilator musi mimo to przekazać zmienioną transformację kabla do prezentacji runtime."
				)
	map_root.free()


func _test_loot_content_change_updates_signature(compiler) -> void:
	var map_root := _instantiate_map()
	if map_root == null:
		return
	var baseline: Dictionary = compiler.compile_map(map_root, 91_014)
	var baseline_errors: PackedStringArray = baseline.get("errors", PackedStringArray())
	_assert(baseline_errors.is_empty(), "Bazowa scena musi kompilować się przed testem zawartości łupu.")
	if baseline_errors.is_empty():
		var authored_object: DiveMapObject
		for node in map_root.find_children("*", "", true, false):
			if node is DiveMapObject and (node as DiveMapObject).object_id == "hotel_linen_cache":
				authored_object = node as DiveMapObject
				break
		_assert(authored_object != null, "Test podpisu zawartości wymaga hotel_linen_cache.")
		if authored_object != null:
			authored_object.contents = authored_object.contents.duplicate(true)
			authored_object.contents["food"] = int(authored_object.contents.get("food", 0)) + 1
			var changed: Dictionary = compiler.compile_map(map_root, 91_014)
			var changed_errors: PackedStringArray = changed.get("errors", PackedStringArray())
			_assert(changed_errors.is_empty(), "Poprawna zmiana zawartości łupu nie może zepsuć kompilacji mapy.")
			if changed_errors.is_empty():
				var baseline_blueprint = baseline.get("blueprint")
				var changed_blueprint = changed.get("blueprint")
				_assert(str(baseline_blueprint.map_gameplay_signature) != str(changed_blueprint.map_gameplay_signature), "Zmiana zawartości łupu musi zmieniać podpis gameplayowy mapy.")
	map_root.free()


func _test_terrain_presentation_preserves_signature(compiler) -> void:
	var map_root := _instantiate_map()
	if map_root == null:
		return
	var baseline: Dictionary = compiler.compile_map(map_root, 91_013)
	var baseline_errors: PackedStringArray = baseline.get("errors", PackedStringArray())
	_assert(baseline_errors.is_empty(), "Bazowa scena musi kompilować się przed testem prezentacji terenu.")
	if baseline_errors.is_empty():
		_assert(map_root.terrain_render_sdf_texture != null, "Scena mapy musi przypisywać pochodny SDF konturu terenu.")
		_assert(map_root.terrain_render_sdf_texture.get_size() == map_root.navigation_grid_texture.get_size(), "Pochodny SDF musi odpowiadać siatce kanonicznej maski.")
		var profile = map_root.terrain_visual_profiles[0]
		profile = profile.duplicate(true)
		profile.rock_edge_color = Color(0.91, 0.27, 0.18, 1.0)
		profile.backdrop_tint = Color(0.18, 0.54, 0.37, 1.0)
		profile.backdrop_accent = Color(0.84, 0.48, 0.30, 1.0)
		profile.backdrop_strength = 0.31
		profile.backdrop_motion_scale = 1.47
		profile.backdrop_motif_scale = 1.63
		map_root.terrain_visual_profiles[0] = profile
		map_root.terrain_detail_texture = GradientTexture2D.new()
		var changed_sdf_image: Image = map_root.terrain_render_sdf_texture.get_image().duplicate()
		var changed_sdf_sample: Color = changed_sdf_image.get_pixel(0, 0)
		changed_sdf_image.set_pixel(0, 0, Color(1.0 - changed_sdf_sample.r, 0.0, 0.0, 1.0))
		map_root.terrain_render_sdf_texture = ImageTexture.create_from_image(changed_sdf_image)
		var changed: Dictionary = compiler.compile_map(map_root, 91_013)
		var changed_errors: PackedStringArray = changed.get("errors", PackedStringArray())
		_assert(changed_errors.is_empty(), "Zmiana profilu i materiału terenu nie może zepsuć kompilacji mapy.")
		if changed_errors.is_empty():
			var baseline_blueprint = baseline.get("blueprint")
			var changed_blueprint = changed.get("blueprint")
			_assert(str(baseline_blueprint.map_gameplay_signature) == str(changed_blueprint.map_gameplay_signature), "Profil, materiał i pochodny SDF terenu nie mogą zmieniać podpisu gameplayowego.")
	map_root.free()


func _test_curve_route_is_compiled(compiler) -> void:
	var map_root := _instantiate_map()
	if map_root == null:
		return
	var connection: DiveMapConnection
	for node in map_root.find_children("*", "", true, false):
		if node is DiveMapConnection:
			connection = node as DiveMapConnection
			break
	_assert(connection != null, "Test wymaga co najmniej jednego połączenia w scenie.")
	if connection == null:
		map_root.free()
		return
	var landmarks: Dictionary = {}
	for node in map_root.find_children("*", "", true, false):
		if node is DiveMapObject and (node as DiveMapObject).kind == DiveMapObject.Kind.LANDMARK:
			var landmark := node as DiveMapObject
			landmarks[landmark.object_id] = landmark
	var from_landmark := landmarks.get(connection.from_landmark_id) as DiveMapObject
	var to_landmark := landmarks.get(connection.to_landmark_id) as DiveMapObject
	_assert(from_landmark != null and to_landmark != null, "Testowana trasa musi wskazywać istniejące landmarki.")
	if from_landmark == null or to_landmark == null:
		map_root.free()
		return
	var baseline: Dictionary = compiler.compile_map(map_root, 91_007)
	var baseline_errors: PackedStringArray = baseline.get("errors", PackedStringArray())
	_assert(baseline_errors.is_empty(), "Bazowa scena musi kompilować się przed testem Curve2D.")
	if not baseline_errors.is_empty():
		map_root.free()
		return
	var from_world := from_landmark.global_position
	var to_world := to_landmark.global_position
	var midpoint_world := (from_world + to_world) * 0.5
	var toward_center := map_root.world_size * 0.5 - midpoint_world
	if toward_center.length_squared() > 0.001:
		midpoint_world += toward_center.normalized() * minf(from_world.distance_to(to_world) * 0.08, 120.0)
	var authored_curve := Curve2D.new()
	authored_curve.add_point(connection.to_local(from_world))
	authored_curve.add_point(connection.to_local(midpoint_world))
	authored_curve.add_point(connection.to_local(to_world))
	connection.curve = authored_curve
	var changed: Dictionary = compiler.compile_map(map_root, 91_007)
	var changed_errors: PackedStringArray = changed.get("errors", PackedStringArray())
	_assert(changed_errors.is_empty(), "Poprawna ręczna Curve2D musi dać się skompilować: %s" % "; ".join(changed_errors))
	if changed_errors.is_empty():
		var baseline_blueprint = baseline.get("blueprint")
		var changed_blueprint = changed.get("blueprint")
		var route_record := _record_by_id(changed_blueprint.connections, connection.connection_id)
		var path_points: PackedVector2Array = route_record.get("path_points", PackedVector2Array())
		_assert(path_points.size() > 2, "Kompilator musi zapisać wypieczony przebieg krzywej, nie tylko dwa punkty kontrolne.")
		_assert(str(baseline_blueprint.map_gameplay_signature) != str(changed_blueprint.map_gameplay_signature), "Zmiana przebiegu trasy musi zmieniać podpis gameplayowy.")
	map_root.free()


func _test_chunk_size_changes_signature(compiler) -> void:
	var map_root := _instantiate_map()
	if map_root == null:
		return
	var baseline: Dictionary = compiler.compile_map(map_root, 91_006)
	var baseline_errors: PackedStringArray = baseline.get("errors", PackedStringArray())
	_assert(baseline_errors.is_empty(), "Bazowa scena musi kompilować się przed testem rozmiaru chunków.")
	if baseline_errors.is_empty():
		map_root.chunk_size = maxi(map_root.chunk_size + 64, 64)
		var changed: Dictionary = compiler.compile_map(map_root, 91_006)
		var changed_errors: PackedStringArray = changed.get("errors", PackedStringArray())
		_assert(changed_errors.is_empty(), "Poprawny rozmiar chunków nie może zepsuć kompilacji mapy.")
		if changed_errors.is_empty():
			var baseline_blueprint = baseline.get("blueprint")
			var changed_blueprint = changed.get("blueprint")
			_assert(
				str(baseline_blueprint.map_gameplay_signature) != str(changed_blueprint.map_gameplay_signature),
				"Zmiana rozmiaru chunków musi zmieniać podpis gameplayowy."
			)
	map_root.free()


func _test_obstacle_transform_is_compiled(compiler) -> void:
	var map_root := _instantiate_map()
	if map_root == null:
		return
	var baseline: Dictionary = compiler.compile_map(map_root, 91_004)
	var baseline_errors: PackedStringArray = baseline.get("errors", PackedStringArray())
	_assert(baseline_errors.is_empty(), "Bazowa scena musi kompilować się przed testem przeszkody.")
	if not baseline_errors.is_empty():
		map_root.free()
		return
	var obstacle_scene := ResourceLoader.load("res://scenes/diving/map_objects/MapObstacle.tscn") as PackedScene
	_assert(obstacle_scene != null, "Prefab MapObstacle musi dać się załadować do kontroli wielokąta.")
	if obstacle_scene == null:
		map_root.free()
		return
	var obstacle_node := obstacle_scene.instantiate()
	var obstacle := obstacle_node as DiveMapObject
	if obstacle == null:
		map_root.free()
		return
	var obstacle_polygon_node := obstacle.get_node_or_null("NavigationPolygon") as Polygon2D
	_assert(obstacle_polygon_node != null, "MapObstacle musi udostępniać natywne uchwyty dziecka NavigationPolygon: Polygon2D.")
	if obstacle_polygon_node == null:
		map_root.free()
		return
	obstacle.object_id = "test_rotated_obstacle"
	obstacle.display_name = "Testowa obrócona przeszkoda"
	obstacle.bounds_size = Vector2(180.0, 72.0)
	obstacle.position = Vector2(5_760.0, 3_240.0)
	obstacle.rotation = 0.42
	obstacle.scale = Vector2(1.25, 0.8)
	obstacle.skew = 0.11
	obstacle.blocks_navigation = false
	map_root.get_node("StaticObstacles").add_child(obstacle)
	var irregular_obstacle_node := obstacle_scene.instantiate()
	var irregular_obstacle := irregular_obstacle_node as DiveMapObject
	if irregular_obstacle == null:
		map_root.free()
		return
	var irregular_polygon_node := irregular_obstacle.get_node_or_null("NavigationPolygon") as Polygon2D
	_assert(irregular_polygon_node != null, "Druga przeszkoda testowa musi zachować dziecko NavigationPolygon: Polygon2D.")
	if irregular_polygon_node == null:
		map_root.free()
		return
	irregular_obstacle.object_id = "test_irregular_obstacle"
	irregular_obstacle.display_name = "Testowa nieregularna przeszkoda"
	irregular_obstacle.position = Vector2(5_280.0, 3_120.0)
	irregular_obstacle.rotation = -0.18
	irregular_obstacle.scale = Vector2(0.9, 1.15)
	irregular_obstacle.skew = -0.07
	irregular_obstacle.blocks_navigation = false
	var irregular_local_polygon := PackedVector2Array([
		Vector2(-92.0, -34.0),
		Vector2(18.0, -61.0),
		Vector2(104.0, -12.0),
		Vector2(63.0, 58.0),
		Vector2(-71.0, 49.0),
	])
	irregular_polygon_node.polygon = irregular_local_polygon
	map_root.get_node("StaticObstacles").add_child(irregular_obstacle)
	var changed: Dictionary = compiler.compile_map(map_root, 91_004)
	var changed_errors: PackedStringArray = changed.get("errors", PackedStringArray())
	_assert(changed_errors.is_empty(), "Poprawna obrócona przeszkoda scenowa musi dać się skompilować: %s" % "; ".join(changed_errors))
	if changed_errors.is_empty():
		var baseline_blueprint = baseline.get("blueprint")
		var changed_blueprint = changed.get("blueprint")
		var record := _record_by_id(changed_blueprint.obstacle_spawns, obstacle.object_id)
		var polygon: PackedVector2Array = record.get("navigation_polygon", PackedVector2Array())
		_assert(polygon.size() == 4, "Pusty Polygon2D musi zachować prostokątny fallback istniejącej przeszkody.")
		var half := obstacle.bounds_size * 0.5
		var expected_fallback := PackedVector2Array([
			obstacle.global_transform * Vector2(-half.x, -half.y),
			obstacle.global_transform * Vector2(half.x, -half.y),
			obstacle.global_transform * Vector2(half.x, half.y),
			obstacle.global_transform * Vector2(-half.x, half.y),
		])
		_assert_polygon_matches(polygon, expected_fallback, "Prostokątny fallback MapObstacle musi zachować dotychczasową transformację 1:1.")
		var irregular_record := _record_by_id(changed_blueprint.obstacle_spawns, irregular_obstacle.object_id)
		var irregular_polygon: PackedVector2Array = irregular_record.get("navigation_polygon", PackedVector2Array())
		var expected_irregular := PackedVector2Array()
		for local_point in irregular_local_polygon:
			expected_irregular.append(irregular_obstacle.global_transform * local_point)
		_assert_polygon_matches(irregular_polygon, expected_irregular, "Nieregularny MapObstacle musi przekazać każdy punkt Polygon2D po pełnej transformacji.")
		_assert(str(baseline_blueprint.map_gameplay_signature) != str(changed_blueprint.map_gameplay_signature), "Dodanie przeszkody musi zmienić podpis gameplayowy.")
	map_root.free()


func _test_shared_obstacle_raster() -> void:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	var base: Dictionary = MapNavigationRasterScript.build(image, Vector2(80.0, 80.0), [])
	var base_cells: PackedByteArray = base.get("cells", PackedByteArray())
	_assert(MapNavigationRasterScript.cell_is_open(base_cells, 8, 8, Vector2i(4, 4)), "Czarna komórka fixture powinna być przechodnia przed dodaniem przeszkody.")
	var transform := Transform2D(PI * 0.25, Vector2.ONE, 0.13, Vector2(40.0, 40.0))
	var half := Vector2(18.0, 7.0)
	var obstacle := {
		"id": "raster_obstacle",
		"blocks_navigation": true,
		"navigation_polygon": PackedVector2Array([
			transform * Vector2(-half.x, -half.y),
			transform * Vector2(half.x, -half.y),
			transform * Vector2(half.x, half.y),
			transform * Vector2(-half.x, half.y),
		]),
	}
	var blocked: Dictionary = MapNavigationRasterScript.build(image, Vector2(80.0, 80.0), [obstacle])
	var blocked_errors: PackedStringArray = blocked.get("errors", PackedStringArray())
	var blocked_cells: PackedByteArray = blocked.get("cells", PackedByteArray())
	_assert(blocked_errors.is_empty(), "Wspólny raster powinien przyjąć obrócony i pochylony wielokąt przeszkody.")
	_assert(not MapNavigationRasterScript.cell_is_open(blocked_cells, 8, 8, Vector2i(4, 4)), "Obrócona i pochylona przeszkoda musi zablokować środkową komórkę.")


func _test_chunked_boundary_segments() -> void:
	var image := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	image.set_pixel(2, 0, Color.WHITE)
	image.set_pixel(2, 1, Color.WHITE)
	var ungrouped_raster: Dictionary = MapNavigationRasterScript.build(
		image,
		Vector2(40.0, 20.0),
		[]
	)
	var raster: Dictionary = MapNavigationRasterScript.build(
		image,
		Vector2(40.0, 20.0),
		[],
		20
	)
	var global_segments: PackedVector2Array = raster.get(
		"boundary_segments",
		PackedVector2Array()
	)
	var segments_by_chunk: Dictionary = raster.get("boundary_segments_by_chunk", {})
	_assert(
		var_to_str(global_segments) == var_to_str(ungrouped_raster.get("boundary_segments", PackedVector2Array())),
		"Włączenie podziału na chunki nie może zmienić globalnych boundary_segments ani ich kolejności."
	)
	_assert(
		segments_by_chunk.keys() == ["0:0", "1:0"],
		"Segmenty graniczne muszą tworzyć deterministyczne klucze chunków x:y."
	)
	var grouped_point_count := 0
	var unique_segments: Dictionary = {}
	for chunk_key in segments_by_chunk.keys():
		var chunk_segments: PackedVector2Array = segments_by_chunk.get(
			chunk_key,
			PackedVector2Array()
		)
		grouped_point_count += chunk_segments.size()
		for point_index in range(0, chunk_segments.size(), 2):
			var start_key := var_to_str(chunk_segments[point_index])
			var end_key := var_to_str(chunk_segments[point_index + 1])
			var segment_key := (
				"%s>%s" % [start_key, end_key]
				if start_key < end_key
				else "%s>%s" % [end_key, start_key]
			)
			_assert(
				not unique_segments.has(segment_key),
				"Żaden segment graniczny nie może być zduplikowany między chunkami."
			)
			unique_segments[segment_key] = chunk_key
	_assert(
		grouped_point_count == global_segments.size(),
		"Podział na chunki musi zachować wszystkie i tylko globalne segmenty graniczne."
	)
	_assert(
		_segment_owner(segments_by_chunk, Vector2(20.0, 0.0), Vector2(20.0, 10.0)) == "0:0",
		"Granica przy x=20 musi należeć wyłącznie do chunka komórki, która ją wytworzyła."
	)
	_assert(
		_segment_owner(segments_by_chunk, Vector2(30.0, 10.0), Vector2(30.0, 0.0)) == "1:0",
		"Granica przy x=30 musi należeć wyłącznie do chunka komórki po prawej stronie blokady."
	)
	var direct_groups := MapNavigationRasterScript.boundary_segments_by_chunk(
		raster.get("cells", PackedByteArray()),
		4,
		2,
		Vector2(10.0, 10.0),
		20
	)
	_assert(
		var_to_str(direct_groups) == var_to_str(segments_by_chunk),
		"Publiczna metoda podziału musi zwracać ten sam deterministyczny wynik co build()."
	)

	var cache_key := "underwater_map_scene_test_chunked_boundaries"
	var cached_first: Dictionary = MapNavigationRasterScript.build_cached(
		cache_key,
		image,
		Vector2(40.0, 20.0),
		[],
		20
	)
	var mutated_groups: Dictionary = cached_first.get("boundary_segments_by_chunk", {})
	var mutated_chunk: PackedVector2Array = mutated_groups.get("0:0", PackedVector2Array())
	mutated_chunk.append(Vector2(999.0, 999.0))
	mutated_chunk.append(Vector2(1000.0, 1000.0))
	mutated_groups["0:0"] = mutated_chunk
	cached_first["boundary_segments_by_chunk"] = mutated_groups
	var cached_second: Dictionary = MapNavigationRasterScript.build_cached(
		cache_key,
		image,
		Vector2(40.0, 20.0),
		[],
		20
	)
	_assert(
		var_to_str(cached_second.get("boundary_segments_by_chunk", {})) == var_to_str(segments_by_chunk),
		"Cache rastra musi zwracać defensywną kopię zagnieżdżonych segmentów chunków."
	)


func _segment_owner(
	segments_by_chunk: Dictionary,
	segment_start: Vector2,
	segment_end: Vector2
) -> String:
	var owner := ""
	for chunk_key in segments_by_chunk.keys():
		var chunk_segments: PackedVector2Array = segments_by_chunk.get(
			chunk_key,
			PackedVector2Array()
		)
		for point_index in range(0, chunk_segments.size(), 2):
			if (
				chunk_segments[point_index].is_equal_approx(segment_start)
				and chunk_segments[point_index + 1].is_equal_approx(segment_end)
			):
				if not owner.is_empty():
					return "duplicate"
				owner = str(chunk_key)
	return owner


func _test_decoration_without_visual_is_rejected(compiler) -> void:
	var map_root := _instantiate_map()
	if map_root == null:
		return
	var decoration := MapObjectScript.new()
	decoration.kind = MapObjectScript.Kind.DECORATION
	decoration.object_id = "test_decoration_without_visual"
	decoration.display_name = "Dekoracja bez grafiki"
	decoration.position = Vector2(128.0, 128.0)
	map_root.get_node("Decorations").add_child(decoration)
	var result: Dictionary = compiler.compile_map(map_root, 91_008)
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	_assert(not errors.is_empty(), "Dekoracja bez Visual Scene musi zablokować kompilację zamiast tworzyć niewidoczny runtime.")
	map_root.free()


func _test_duplicate_id_is_rejected(compiler) -> void:
	var map_root := _instantiate_map()
	if map_root == null:
		return
	var existing_id := ""
	for node in map_root.find_children("*", "", true, false):
		if node is DiveMapObject and not (node as DiveMapObject).object_id.is_empty():
			existing_id = (node as DiveMapObject).object_id
			break
	var duplicate := MapObjectScript.new()
	duplicate.kind = MapObjectScript.Kind.OBSTACLE
	duplicate.object_id = existing_id
	duplicate.display_name = "Duplikat testowy"
	duplicate.bounds_size = Vector2(32, 32)
	duplicate.position = Vector2(64, 64)
	map_root.get_node("StaticObstacles").add_child(duplicate)
	var result: Dictionary = compiler.compile_map(map_root, 91_002)
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	_assert(not existing_id.is_empty() and not errors.is_empty(), "Powielony Object ID musi zablokować kompilację mapy.")
	map_root.free()


func _test_runtime_layer_preserves_authored_siblings(world) -> void:
	var runtime = RuntimeMapScript.new()
	runtime.name = "RuntimeMapTest"
	var authored_sibling := Node2D.new()
	authored_sibling.name = "AuthoredSentinel"
	runtime.add_child(authored_sibling)
	root.add_child(runtime)
	await process_frame
	runtime.configure(world, world.entry_sector_id)
	_assert(runtime.get_node_or_null("AuthoredSentinel") == authored_sibling, "Przebudowa runtime nie może usuwać node'a dodanego w scenie.")
	root.remove_child(runtime)
	runtime.queue_free()


func _instantiate_map() -> UnderwaterMapScene:
	var scene := ResourceLoader.load(MapCompilerScript.MAP_SCENE_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var map_root: UnderwaterMapScene
	if scene != null:
		map_root = scene.instantiate() as UnderwaterMapScene
	_assert(map_root != null, "Produkcyjna scena mapy musi dać się zinstancjonować.")
	return map_root


func _authored_object_by_id(map_root: UnderwaterMapScene, object_id: String) -> DiveMapObject:
	for node in map_root.find_children("*", "", true, false):
		if node is DiveMapObject and (node as DiveMapObject).object_id == object_id:
			return node as DiveMapObject
	return null


func _assert_tutorial_cable_anchors(cable_record: Dictionary) -> void:
	var packed := ResourceLoader.load(CABLE_VISUAL_PATH) as PackedScene
	_assert(packed != null, "Prefab kabla musi dać się załadować do kontroli zakotwiczeń.")
	if packed == null:
		return
	var cable_visual := packed.instantiate() as Path2D
	_assert(cable_visual != null, "Prefab kabla musi mieć root Path2D do kontroli zakotwiczeń.")
	if cable_visual == null:
		return
	var route_points := _assert_cable_curve(cable_visual, CABLE_VISUAL_PATH)
	var tutorial_anchor_indices: Array = CommonLineCableVisualScript.TUTORIAL_ANCHOR_INDICES
	_assert(route_points.size() >= 7, "Scenowa Curve2D kabla musi zachować pełną trasę od platformy do J-7.")
	_assert(
		var_to_str(tutorial_anchor_indices) == var_to_str([1, 3, 5, 6]),
		"Prefab kabla musi jawnie oznaczać kotwy: targ, warsztat, SC-01 i J-7."
	)
	if route_points.size() < 7:
		cable_visual.free()
		return
	var object_transform := Transform2D(
		float(cable_record.get("visual_object_rotation", 0.0)),
		cable_record.get("visual_object_scale", Vector2.ONE),
		float(cable_record.get("visual_object_skew", 0.0)),
		cable_record.get("position", Vector2.ZERO)
	)
	var visual_transform := Transform2D(
		float(cable_record.get("visual_rotation", 0.0)),
		cable_record.get("visual_scale", Vector2.ONE),
		0.0,
		cable_record.get("visual_offset", Vector2.ZERO)
	)
	var world_transform := object_transform * visual_transform * cable_visual.transform
	var anchor_contract := [
		{"point_index": 0, "position_id": "exit_line"},
		{"point_index": 1, "position_id": "tutorial_market_crate"},
		{"point_index": 3, "position_id": "tutorial_workshop_case"},
		{"point_index": 5, "position_id": "SC-01"},
		{"point_index": 6, "position_id": "junction_j7"},
	]
	for anchor in anchor_contract:
		var point_index := int(anchor.get("point_index", -1))
		var position_id := str(anchor.get("position_id", ""))
		var world_point: Vector2 = world_transform * (route_points[point_index] as Vector2)
		_assert(
			_vectors_match(world_point, TUTORIAL_POSITIONS[position_id]),
			"Trasa kabla musi przechodzić przez kotwę %s w zatwierdzonej pozycji." % position_id
		)
	cable_visual.free()


func _assert_visual_scene_collision_free(scene_path: String, context: String) -> void:
	var packed := ResourceLoader.load(scene_path) as PackedScene
	_assert(packed != null, "%s musi wskazywać istniejący PackedScene." % context)
	if packed == null:
		return
	var candidate := packed.instantiate()
	_assert(candidate is Node2D, "%s musi mieć root Node2D." % context)
	if not (candidate is Node2D):
		if candidate != null:
			candidate.free()
		return
	var visual_nodes: Array[Node] = []
	visual_nodes.append(candidate)
	visual_nodes.append_array(candidate.find_children("*", "", true, false))
	for node in visual_nodes:
		_assert(
			not (node is CollisionObject2D or node is CollisionShape2D or node is CollisionPolygon2D),
			"%s nie może zawierać kolizji: %s." % [context, node.name]
		)
	candidate.free()


func _assert_story_cables_are_non_blocking(blueprint) -> void:
	for decoration_id_value in STORY_CABLE_ENDPOINTS.keys():
		var decoration_id := str(decoration_id_value)
		var record: Dictionary = _record_by_id(blueprint.decoration_spawns, decoration_id)
		_assert(not record.is_empty(), "Mapa musi zawierać odcinek kabla fabularnego %s." % decoration_id)
		if record.is_empty():
			continue
		_assert(
			not bool(record.get("blocks_navigation", true)),
			"Kabel fabularny %s musi pozostać bezkolizyjną dekoracją." % decoration_id
		)
		var visual_path := str(record.get("visual_scene_path", ""))
		var expected_visual_path := str(STORY_CABLE_VISUAL_PATHS.get(decoration_id, ""))
		_assert(
			visual_path == expected_visual_path,
			"Kabel fabularny %s musi używać dedykowanego prefabu %s." % [decoration_id, expected_visual_path]
		)
		_assert_visual_scene_collision_free(visual_path, "Prefab kabla fabularnego %s" % decoration_id)
		_assert_story_cable_endpoints(record, STORY_CABLE_ENDPOINTS[decoration_id])
		if decoration_id == "common_line_cable_archive_r3":
			_assert_story_cable_passes_point(record, STORY_POSITIONS["r3_diagnostic_panel"])


func _assert_story_cable_endpoints(record: Dictionary, expected_endpoints: Array) -> void:
	var decoration_id := str(record.get("id", ""))
	var scene_path := str(record.get("visual_scene_path", ""))
	var packed := ResourceLoader.load(scene_path) as PackedScene
	_assert(packed != null, "Prefab kabla %s musi dać się załadować do kontroli endpointów." % decoration_id)
	if packed == null:
		return
	var cable_visual := packed.instantiate() as Path2D
	_assert(cable_visual != null, "Prefab kabla %s musi mieć root Path2D." % decoration_id)
	if cable_visual == null:
		return
	var route_points := _assert_cable_curve(cable_visual, scene_path)
	_assert(route_points.size() >= 2, "Prefab kabla %s musi publikować co najmniej dwa punkty Curve2D." % decoration_id)
	_assert(expected_endpoints.size() == 2, "Kontrakt kabla %s musi wskazywać dokładnie początek i koniec." % decoration_id)
	if route_points.size() < 2 or expected_endpoints.size() != 2:
		cable_visual.free()
		return
	var object_transform := Transform2D(
		float(record.get("visual_object_rotation", 0.0)),
		record.get("visual_object_scale", Vector2.ONE),
		float(record.get("visual_object_skew", 0.0)),
		record.get("position", Vector2.ZERO)
	)
	var visual_transform := Transform2D(
		float(record.get("visual_rotation", 0.0)),
		record.get("visual_scale", Vector2.ONE),
		0.0,
		record.get("visual_offset", Vector2.ZERO)
	)
	var world_transform := object_transform * visual_transform * cable_visual.transform
	var world_start: Vector2 = world_transform * (route_points[0] as Vector2)
	var world_end: Vector2 = world_transform * (route_points[route_points.size() - 1] as Vector2)
	_assert(
		_vectors_match(world_start, expected_endpoints[0] as Vector2),
		"Kabel %s musi zaczynać się przy zatwierdzonym urządzeniu %s; otrzymano %s."
		% [decoration_id, expected_endpoints[0], world_start]
	)
	_assert(
		_vectors_match(world_end, expected_endpoints[1] as Vector2),
		"Kabel %s musi kończyć się przy zatwierdzonym urządzeniu %s; otrzymano %s."
		% [decoration_id, expected_endpoints[1], world_end]
	)
	cable_visual.free()


func _assert_story_cable_passes_point(record: Dictionary, expected_world_point: Vector2) -> void:
	var packed := ResourceLoader.load(str(record.get("visual_scene_path", ""))) as PackedScene
	if packed == null:
		return
	var cable_visual := packed.instantiate() as Path2D
	if cable_visual == null:
		return
	var route_points := _assert_cable_curve(cable_visual, str(record.get("visual_scene_path", "")))
	var object_transform := Transform2D(
		float(record.get("visual_object_rotation", 0.0)),
		record.get("visual_object_scale", Vector2.ONE),
		float(record.get("visual_object_skew", 0.0)),
		record.get("position", Vector2.ZERO)
	)
	var visual_transform := Transform2D(
		float(record.get("visual_rotation", 0.0)),
		record.get("visual_scale", Vector2.ONE),
		0.0,
		record.get("visual_offset", Vector2.ZERO)
	)
	var world_transform := object_transform * visual_transform * cable_visual.transform
	var passes_point := false
	for route_point in route_points:
		if _vectors_match(world_transform * (route_point as Vector2), expected_world_point):
			passes_point = true
			break
	_assert(passes_point, "Kabel Archiwum — R-3 musi przechodzić przez panel diagnostyczny przed generatorem.")
	cable_visual.free()


func _assert_cable_curve(cable_visual: Path2D, scene_path: String) -> PackedVector2Array:
	var route_points := PackedVector2Array()
	_assert(cable_visual.curve != null, "Prefab kabla %s musi przechowywać scenową Curve2D." % scene_path)
	if cable_visual.curve == null:
		return route_points
	var visual_script := cable_visual.get_script() as Script
	var script_constants: Dictionary = visual_script.get_script_constant_map() if visual_script != null else {}
	_assert(not script_constants.has("ROUTE_POINTS"), "Prefab kabla %s nie może utrzymywać drugiej trasy ROUTE_POINTS w skrypcie." % scene_path)
	for point_index in range(cable_visual.curve.point_count):
		route_points.append(cable_visual.curve.get_point_position(point_index))
		_assert(
			cable_visual.curve.get_point_in(point_index) == Vector2.ZERO
			and cable_visual.curve.get_point_out(point_index) == Vector2.ZERO,
			"Migracja kabla %s musi zachować dotychczasowe proste segmenty i wygląd." % scene_path
		)
	var expected_points: Array = EXPECTED_CABLE_CONTROL_POINTS.get(scene_path, [])
	_assert(not expected_points.is_empty(), "Test musi znać zatwierdzoną trasę kabla %s." % scene_path)
	_assert(route_points.size() == expected_points.size(), "Curve2D kabla %s musi zachować liczbę punktów 1:1." % scene_path)
	for point_index in range(mini(route_points.size(), expected_points.size())):
		_assert(
			_vectors_match(route_points[point_index], expected_points[point_index] as Vector2),
			"Curve2D kabla %s musi zachować punkt %d 1:1." % [scene_path, point_index]
		)
	return route_points


func _assert_polygon_matches(actual: PackedVector2Array, expected: PackedVector2Array, message: String) -> void:
	var matches := actual.size() == expected.size()
	for point_index in range(mini(actual.size(), expected.size())):
		matches = matches and _vectors_match(actual[point_index], expected[point_index])
	_assert(matches, message)


func _assert_critical_interactable_separation(blueprint) -> void:
	var records_by_id := _static_gameplay_records_by_id(blueprint)
	for pair in CRITICAL_INTERACTABLE_PAIRS:
		var first_id := str(pair[0])
		var second_id := str(pair[1])
		_assert(records_by_id.has(first_id), "Kontrakt odstępu wymaga celu %s." % first_id)
		_assert(records_by_id.has(second_id), "Kontrakt odstępu wymaga celu %s." % second_id)
		if not records_by_id.has(first_id) or not records_by_id.has(second_id):
			continue
		var first: Dictionary = records_by_id[first_id]
		var second: Dictionary = records_by_id[second_id]
		var first_position = first.get("position", null)
		var second_position = second.get("position", null)
		_assert(first_position is Vector2 and second_position is Vector2, "Oba cele pary %s/%s muszą publikować pozycję." % [first_id, second_id])
		if not (first_position is Vector2 and second_position is Vector2):
			continue
		var distance := (first_position as Vector2).distance_to(second_position as Vector2)
		_assert(
			distance + 0.001 >= MIN_CRITICAL_INTERACTABLE_SEPARATION,
			"Krytyczne interakcje %s i %s muszą dzielić co najmniej %.0f jednostek; jest %.1f."
			% [first_id, second_id, MIN_CRITICAL_INTERACTABLE_SEPARATION, distance]
		)


func _static_gameplay_records_by_id(blueprint) -> Dictionary:
	var result: Dictionary = {}
	for records in [
		blueprint.loot_spawns,
		blueprint.threat_spawns,
		blueprint.heavy_object_spawns,
		blueprint.rescue_spawns,
		blueprint.buoy_spawns,
		blueprint.shortcut_spawns,
		blueprint.fixed_device_spawns,
	]:
		for record in records:
			var record_id := str(record.get("id", ""))
			if not record_id.is_empty():
				result[record_id] = record
	return result


func _assert_all_selectable_interactables_are_separated(blueprint) -> void:
	var selectable_records: Array[Dictionary] = []
	for records in [
		blueprint.loot_spawns,
		blueprint.heavy_object_spawns,
		blueprint.rescue_spawns,
		blueprint.buoy_spawns,
		blueprint.shortcut_spawns,
		blueprint.fixed_device_spawns,
	]:
		for record in records:
			selectable_records.append(record)
	for first_index in range(selectable_records.size()):
		var first := selectable_records[first_index]
		for second_index in range(first_index + 1, selectable_records.size()):
			var second := selectable_records[second_index]
			var first_position: Vector2 = first.get("position", Vector2.ZERO)
			var second_position: Vector2 = second.get("position", Vector2.ZERO)
			var distance := first_position.distance_to(second_position)
			_assert(
				distance + 0.001 >= MIN_CRITICAL_INTERACTABLE_SEPARATION,
				"Interaktywne cele %s i %s muszą dzielić co najmniej %.0f jednostek, aby selektor nie wybierał sąsiedniego obiektu; jest %.1f."
				% [
					str(first.get("id", "")),
					str(second.get("id", "")),
					MIN_CRITICAL_INTERACTABLE_SEPARATION,
					distance,
				]
			)


func _nearest_landmark_id(blueprint, record: Dictionary) -> String:
	var position_value = record.get("position", null)
	if not (position_value is Vector2):
		return ""
	var landmark: Dictionary = blueprint.get_nearest_landmark(position_value as Vector2)
	return str(landmark.get("id", ""))


func _test_stale_source_version_is_rejected(compiler, world) -> void:
	var stale_world = WorldStateScript.new()
	stale_world.blueprint = world.blueprint.duplicate(true)
	stale_world.delta = world.delta.duplicate(true)
	var stale_blueprint = stale_world.blueprint
	var original_delta = stale_world.delta
	var original_active_landmark_id := str(original_delta.active_landmark_id)
	var original_discovered_landmarks: Array[String] = original_delta.discovered_landmarks.duplicate()
	stale_blueprint.map_source_version = MapCompilerScript.MAP_SOURCE_VERSION - 1

	var errors: PackedStringArray = compiler.ensure_world_is_current(stale_world)
	_assert(errors.has("Zapis kampanii nie używa aktualnego źródła mapy."), "Migawka source-v3 musi zostać odrzucona przed odświeżeniem mapy.")
	_assert(stale_world.blueprint == stale_blueprint, "Odrzucenie nieaktualnej wersji źródła nie może zastąpić blueprintu.")
	_assert(
		stale_world.delta == original_delta
		and str(stale_world.delta.active_landmark_id) == original_active_landmark_id
		and stale_world.delta.discovered_landmarks == original_discovered_landmarks,
		"Odrzucenie nieaktualnej wersji źródła nie może mutować WorldDelta."
	)


func _assert_unique_static_gameplay_positions(blueprint) -> void:
	var static_record_groups := [
		{"name": "loot", "records": blueprint.loot_spawns},
		{"name": "threat", "records": blueprint.threat_spawns},
		{"name": "heavy", "records": blueprint.heavy_object_spawns},
		{"name": "rescue", "records": blueprint.rescue_spawns},
		{"name": "buoy", "records": blueprint.buoy_spawns},
		{"name": "shortcut", "records": blueprint.shortcut_spawns},
		{"name": "fixed_device", "records": blueprint.fixed_device_spawns},
	]
	var position_owners: Dictionary = {}
	for group in static_record_groups:
		var category := str(group.get("name", "unknown"))
		var records: Array = group.get("records", [])
		for record in records:
			var record_id := str(record.get("id", ""))
			var position_value = record.get("position", null)
			_assert(position_value is Vector2, "Statyczny cel %s/%s musi publikować pozycję Vector2." % [category, record_id])
			if not (position_value is Vector2):
				continue
			var position := position_value as Vector2
			var previous_owner := str(position_owners.get(position, ""))
			_assert(
				previous_owner.is_empty(),
				"Statyczne cele gameplayowe nie mogą współdzielić punktu %s: %s i %s/%s." % [position, previous_owner, category, record_id]
			)
			if previous_owner.is_empty():
				position_owners[position] = "%s/%s" % [category, record_id]


func _record_position_matches(record: Dictionary, expected: Vector2) -> bool:
	var position_value = record.get("position", null)
	return position_value is Vector2 and _vectors_match(position_value as Vector2, expected)


func _vectors_match(actual: Vector2, expected: Vector2) -> bool:
	return actual.is_equal_approx(expected)


func _has_authoring_kind(records: Array, authoring_kind: String) -> bool:
	for record in records:
		if str(record.get("authoring_kind", "")) == authoring_kind:
			return true
	return false


func _record_by_id(records: Array, record_id: String) -> Dictionary:
	for record in records:
		if str(record.get("id", "")) == record_id:
			return record
	return {}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Underwater map scene assertion failed: " + message)
