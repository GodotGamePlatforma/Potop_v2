extends SceneTree

const MapCompilerScript := preload("res://scripts/diving/UnderwaterMapSceneCompiler.gd")
const MapSceneScript := preload("res://scripts/diving/UnderwaterMapScene.gd")
const MapObjectScript := preload("res://scripts/diving/DiveMapObject.gd")
const MapConnectionScript := preload("res://scripts/diving/DiveMapConnection.gd")
const MapNavigationRasterScript := preload("res://scripts/diving/MapNavigationRaster.gd")
const NavigationSnapshotScript := preload("res://scripts/diving/DiveNavigationSnapshot.gd")
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
const LANDMARK_GAMEPLAY_MARGIN := 8.0
const IMPLICIT_LANDMARK_LINKS := {
	"rescue_hotel_leon": "R1-03",
	"ship_engine_r1": "R1-07",
	"shipyard_winch_r3": "R3-02",
	"scrapyard_generator_r3": "R3-06",
}

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

const SIX_LAYER_VISUALS_PATH := "VisualLayers/SixLayerVisuals"
const LAYER_ELEMENT_TEMPLATE_PATH := "res://scenes/diving/map_visuals/LayerVisualElement.tscn"
const RESIDENT_ELEMENT_TEST_TEXTURE := "res://assets/diving/world/map_v2/visual_chunks/environment_decoration/chunk_04_01.png"
const EXPECTED_VISUAL_LAYER_IDS: Array[StringName] = [
	&"L00_base_color",
	&"L01_ultra_far_silhouettes",
	&"L02_far_structures",
	&"L03_mid_drift_props",
	&"L04_near_terrain_skin",
	&"L05_foreground_occluders",
]
const LEGACY_VISUAL_ELEMENT_COUNT := 15

var _failures := 0


func _initialize() -> void:
	var compiler = MapCompilerScript.new()
	var world = WorldStateScript.new()
	world.setup(91_001)
	var generation_errors: PackedStringArray = compiler.generate(world, 91_001)
	_assert(generation_errors.is_empty(), "Scena mapy musi kompilować się bez błędów: %s" % "; ".join(generation_errors))
	_test_prefab_catalog()
	_test_shared_obstacle_raster()
	_test_chunked_boundary_segments()
	if generation_errors.is_empty():
		_test_compiled_manifest(compiler, world)
		_test_stale_source_version_is_rejected(compiler, world)
		_test_stale_gameplay_signature_is_rejected(compiler, world)
		_test_unique_authoring_ids()
		_test_six_layer_authoring_contract(compiler)
		_test_visual_manifest_compiler_gate(compiler)
		_test_visual_only_change_preserves_signature(compiler)
		_test_gameplay_position_change_updates_signature(compiler)
		_test_landmark_position_change_updates_signature(compiler)
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


func _test_compiled_manifest(compiler, world) -> void:
	var blueprint = world.blueprint
	_assert(int(blueprint.map_source_version) == int(MapCompilerScript.MAP_SOURCE_VERSION), "Migawka musi wskazywać aktualną wersję sceny.")
	_assert(not str(blueprint.map_gameplay_signature).is_empty(), "Migawka musi wskazywać bieżącą tożsamość gameplayową mapy.")
	_assert(not str(blueprint.map_id).is_empty(), "Scena musi przekazać stabilne Map ID.")
	_assert(str(blueprint.map_gameplay_signature).length() == 64, "Mapa musi otrzymać 64-znakowy podpis gameplayowy.")
	_assert(not blueprint.entry_landmark_id.is_empty() and blueprint.landmark_lookup.has(blueprint.entry_landmark_id), "Entry Point musi wskazywać istniejący landmark.")
	_assert(blueprint.fixed_device_spawns.size() == 6, "Mapa musi kompilować J-7, Archiwum, dwa etapy R-3, Rozdzielnię C-4 i gniazdo Rozdzielacza.")
	_assert(blueprint.landmarks.size() == 27, "Mapa po usunięciu Banku Nasion musi zawierać dokładnie 27 landmarków.")
	_assert(blueprint.connections.size() == 43, "Mapa po usunięciu tras Banku Nasion musi zawierać dokładnie 43 połączenia.")
	_assert(blueprint.shortcut_spawns.size() == 7, "Mapa po usunięciu SC-02 musi zachować dokładnie siedem trwałych skrótów.")
	_assert(not blueprint.landmark_lookup.has("R2-04"), "Usunięty Bank Nasion R2-04 nie może wrócić do blueprintu.")
	_assert(_record_by_id(blueprint.connections, "C019").is_empty() and _record_by_id(blueprint.connections, "C020").is_empty() and _record_by_id(blueprint.connections, "C021").is_empty(), "Trasy zależne od R2-04 muszą pozostać usunięte.")
	_assert(_record_by_id(blueprint.connections, "SC-02").is_empty() and _record_by_id(blueprint.shortcut_spawns, "SC-02").is_empty(), "Połączenie i brama SC-02 Bank Nasion — Archiwum muszą pozostać usunięte.")
	_assert(_record_by_id(blueprint.loot_spawns, "seed_bank_vault").is_empty(), "Kapsuła Banku Nasion nie może wrócić jako źródło łupu.")
	_assert_regular_connection_reachability(blueprint)
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
	_assert_landmark_centers_are_diver_clear(compiler, blueprint)
	_assert_linked_gameplay_stays_with_landmark(blueprint)
	var r1_j7: Dictionary = _record_by_id(blueprint.landmarks, "R1-04")
	_assert(str(r1_j7.get("visual_scene_path", "")) == R1_J7_ART_CELL_VISUAL_PATH, "Parking R1-04 musi instancjować zatwierdzony ArtCell Węzła J-7.")
	_assert(int(r1_j7.get("visual_z_index", 0)) == -60, "Lokalna skóra terenu R1/J-7 musi pozostać za terenem i obiektami gameplayowymi.")
	_assert_visual_scene_collision_free(R1_J7_ART_CELL_VISUAL_PATH, "ArtCell R1-04/J-7")
	_assert_r1_j7_terrain_skin_contract()
	var r3_power_plant: Dictionary = _record_by_id(blueprint.landmarks, "R3-04")
	_assert(str(r3_power_plant.get("visual_scene_path", "")).is_empty(), "Elektrownia R3-04 nie może mieć lokalnej Visual Scene po usunięciu odrzuconego tła.")
	_assert(int(r3_power_plant.get("visual_z_index", 0)) == 0, "R3-04 na wspólnym tle regionu nie może zachowywać lokalnego z-indexu usuniętego tła.")
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
		"greenhouse_supply_box": 14,
		"park_service_shed": 7,
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
		"R2": ["greenhouse_supply_box", "park_service_shed", "pickup_r2_food_01"],
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


func _assert_landmark_centers_are_diver_clear(compiler, blueprint) -> void:
	var base_raster: Dictionary = compiler.navigation_base_raster()
	var base_errors: PackedStringArray = base_raster.get("errors", PackedStringArray())
	_assert(base_errors.is_empty(), "Scenowy makroteren musi dać się zrasteryzować dla walidacji landmarków: %s" % "; ".join(base_errors))
	if not base_errors.is_empty():
		return
	var width := int(base_raster.get("width", 0))
	var height := int(base_raster.get("height", 0))
	var raster: Dictionary = MapNavigationRasterScript.build_from_cells(
		base_raster.get("cells", PackedByteArray()),
		width,
		height,
		blueprint.world_size,
		blueprint.obstacle_spawns,
		0,
		false
	)
	var raster_errors: PackedStringArray = raster.get("errors", PackedStringArray())
	_assert(raster_errors.is_empty(), "Statyczny raster mapy musi uwzględnić MapObstacle dla walidacji landmarków: %s" % "; ".join(raster_errors))
	if not raster_errors.is_empty():
		return
	width = int(raster.get("width", 0))
	height = int(raster.get("height", 0))
	var cells: PackedByteArray = raster.get("cells", PackedByteArray())
	var cell_scale: Vector2 = raster.get("cell_scale", Vector2.ONE)
	var snapshot = NavigationSnapshotScript.new()
	snapshot.configure(
		blueprint.world_size,
		Vector2i(width, height),
		cell_scale,
		cells,
		NavigationSnapshotScript.DEFAULT_DIVER_CLEARANCE,
		blueprint.entry_position,
		blueprint.exit_position,
		blueprint.current_zones,
		blueprint.regions,
		[],
		[]
	)
	_assert(snapshot.is_valid(), "Statyczny snapshot C35 landmarków musi być kompletny.")
	if not snapshot.is_valid():
		return
	var entry_cell: Vector2i = snapshot.world_to_cell(blueprint.entry_position)
	var reachable: PackedByteArray = MapNavigationRasterScript.reachable_cells(
		snapshot.clear_cells,
		width,
		height,
		entry_cell
	)
	var entry_component_size := _count_marked_cells(reachable)
	var largest_component_size := _largest_open_component_size(snapshot.clear_cells, width, height)
	_assert(
		entry_component_size == largest_component_size and entry_component_size > 0,
		"EntryStation musi należeć do głównej 4-spójnej składowej statycznej maski C35."
	)
	var region_lookup: Dictionary = {}
	for region in blueprint.regions:
		region_lookup[str(region.get("id", ""))] = region
	for landmark in blueprint.landmarks:
		var landmark_id := str(landmark.get("id", ""))
		var position_value = landmark.get("position", null)
		_assert(position_value is Vector2, "Landmark %s musi publikować pozycję Vector2." % landmark_id)
		if not (position_value is Vector2):
			continue
		var position := position_value as Vector2
		var cell: Vector2i = snapshot.world_to_cell(position)
		var cell_index := cell.y * width + cell.x
		_assert(
			snapshot.is_position_open(position),
			"Środek landmarku %s na %s (komórka %s) nie może leżeć na zablokowanym terenie."
			% [landmark_id, position, cell]
		)
		_assert(
			snapshot.is_position_clear(position),
			"Środek landmarku %s na %s (komórka %s) musi zachować C35 dla kapsuły nurka."
			% [landmark_id, position, cell]
		)
		_assert(
			cell_index >= 0 and cell_index < reachable.size() and reachable[cell_index] == 1,
			"Środek landmarku %s na %s (komórka %s) musi należeć do głównej osiągalnej składowej C35."
			% [landmark_id, position, cell]
		)
		var region_id := str(landmark.get("region_id", ""))
		var region: Dictionary = region_lookup.get(region_id, {})
		var region_bounds: Rect2 = region.get("bounds", Rect2())
		_assert(
			not region.is_empty() and region_bounds.has_point(position),
			"Środek landmarku %s musi pozostać w zadeklarowanym regionie %s." % [landmark_id, region_id]
		)


func _count_marked_cells(cells: PackedByteArray) -> int:
	var count := 0
	for value in cells:
		if value == 1:
			count += 1
	return count


func _largest_open_component_size(cells: PackedByteArray, width: int, height: int) -> int:
	if width <= 0 or height <= 0 or cells.size() != width * height:
		return 0
	var visited := PackedByteArray()
	visited.resize(cells.size())
	var largest_size := 0
	for start_index in range(cells.size()):
		if cells[start_index] != 1 or visited[start_index] == 1:
			continue
		var queue := PackedInt32Array([start_index])
		visited[start_index] = 1
		var read_index := 0
		while read_index < queue.size():
			var index := queue[read_index]
			read_index += 1
			var x := index % width
			var y := floori(float(index) / float(width))
			if x > 0:
				var left := index - 1
				if visited[left] == 0 and cells[left] == 1:
					visited[left] = 1
					queue.append(left)
			if x + 1 < width:
				var right := index + 1
				if visited[right] == 0 and cells[right] == 1:
					visited[right] = 1
					queue.append(right)
			if y > 0:
				var above := index - width
				if visited[above] == 0 and cells[above] == 1:
					visited[above] = 1
					queue.append(above)
			if y + 1 < height:
				var below := index + width
				if visited[below] == 0 and cells[below] == 1:
					visited[below] = 1
					queue.append(below)
		largest_size = maxi(largest_size, queue.size())
	return largest_size


func _assert_linked_gameplay_stays_with_landmark(blueprint) -> void:
	var relocated_landmark_ids := {
		"R1-01": true,
		"R1-03": true,
		"R1-05": true,
		"R1-06": true,
		"R1-07": true,
		"R2-01": true,
		"R2-02": true,
		"R2-03": true,
		"R2-05": true,
		"R2-06": true,
		"R3-02": true,
		"R3-06": true,
		"R4-01": true,
		"R4-04": true,
		"R4-05": true,
	}
	var linked_groups := [
		{"name": "loot", "records": blueprint.loot_spawns, "link_field": "landmark_id"},
		{"name": "buoy", "records": blueprint.buoy_spawns, "link_field": "entry_landmark_id"},
		{"name": "fixed_device", "records": blueprint.fixed_device_spawns, "link_field": "landmark_id"},
	]
	for group in linked_groups:
		var category := str(group.get("name", "unknown"))
		var link_field := str(group.get("link_field", ""))
		var records: Array = group.get("records", [])
		for record in records:
			var record_id := str(record.get("id", ""))
			var landmark_id := str(record.get(link_field, ""))
			if landmark_id.is_empty():
				continue
			_assert_gameplay_record_landmark_contract(
				blueprint,
				category,
				record,
				landmark_id,
				relocated_landmark_ids.has(landmark_id)
			)
	var implicitly_linked_groups := [
		{"name": "rescue", "records": blueprint.rescue_spawns},
		{"name": "heavy_object", "records": blueprint.heavy_object_spawns},
	]
	for group in implicitly_linked_groups:
		var category := str(group.get("name", "unknown"))
		var records: Array = group.get("records", [])
		for record in records:
			var record_id := str(record.get("id", ""))
			var landmark_id := str(IMPLICIT_LANDMARK_LINKS.get(record_id, ""))
			if landmark_id.is_empty():
				continue
			_assert_gameplay_record_landmark_contract(blueprint, category, record, landmark_id, true)


func _assert_gameplay_record_landmark_contract(
	blueprint,
	category: String,
	record: Dictionary,
	landmark_id: String,
	require_containment: bool
) -> void:
	var record_id := str(record.get("id", ""))
	var landmark: Dictionary = blueprint.get_landmark(landmark_id)
	_assert(not landmark.is_empty(), "Powiązany cel %s/%s wskazuje brakujący landmark %s." % [category, record_id, landmark_id])
	if landmark.is_empty():
		return
	var position_value = record.get("position", null)
	_assert(position_value is Vector2, "Powiązany cel %s/%s musi publikować pozycję Vector2." % [category, record_id])
	if not (position_value is Vector2):
		return
	if require_containment:
		var landmark_position: Vector2 = landmark.get("position", Vector2.ZERO)
		var landmark_size: Vector2 = landmark.get("size", Vector2.ZERO)
		var landmark_bounds := Rect2(landmark_position - landmark_size * 0.5, landmark_size)
		var safe_bounds := landmark_bounds.grow(-LANDMARK_GAMEPLAY_MARGIN)
		_assert(
			_rect_inclusive_has_point(safe_bounds, position_value as Vector2),
			"Powiązany cel %s/%s na %s musi mieścić się w bounds landmarku %s z marginesem %.0f jednostek."
			% [category, record_id, position_value, landmark_id, LANDMARK_GAMEPLAY_MARGIN]
		)
	_assert(
		_nearest_landmark_id(blueprint, record) == landmark_id,
		"Powiązany cel %s/%s musi zachować landmark %s jako najbliższy."
		% [category, record_id, landmark_id]
	)


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


func _test_six_layer_authoring_contract(compiler) -> void:
	var map_root := _instantiate_map()
	if map_root == null:
		return
	var stack := map_root.get_node_or_null(SIX_LAYER_VISUALS_PATH) as DiveVisualLayerStack
	_assert(stack != null, "Scena mapy musi instancjonować edytowalny stos VisualLayers/SixLayerVisuals.")
	if stack == null:
		map_root.free()
		return
	_assert(stack.validation_errors().is_empty(), "Sześciowarstwowa kompozycja musi przechodzić walidację profili, kolejności i bucketów.")
	_assert(
		MapCompilerScript._source_dependency_paths.has(LAYER_ELEMENT_TEMPLATE_PATH),
		"Fingerprint cache kompilatora musi obejmować prefab LayerVisualElement."
	)
	_assert(stack.get_child_count() == EXPECTED_VISUAL_LAYER_IDS.size(), "Stos wizualny musi zawierać dokładnie sześć niezależnych wrapperów warstw.")
	var previous_scroll_scale := Vector2(-INF, -INF)
	var previous_z_index := -1_000_000
	var profile_paths := {}
	var visual_elements: Array[DiveVisualLayerElement] = []
	for layer_index in range(EXPECTED_VISUAL_LAYER_IDS.size()):
		var layer_id := EXPECTED_VISUAL_LAYER_IDS[layer_index]
		var layer := stack.layer_root(layer_id)
		_assert(layer != null, "Brakuje wymaganej warstwy %s." % layer_id)
		if layer == null:
			continue
		_assert(StringName(layer.name) == layer_id, "Nazwa wrappera warstwy musi być identyczna ze stabilnym ID %s." % layer_id)
		_assert(layer.get_index() == layer_index, "Warstwa %s musi zachować stabilną kolejność L00-L05 w scenie." % layer_id)
		_assert(layer.profile != null and layer.profile.layer_id == layer_id, "Warstwa %s musi wskazywać własny walidowany profil." % layer_id)
		if layer.profile != null:
			_assert(not layer.profile.role.strip_edges().is_empty(), "Profil %s musi opisywać jednoznaczną rolę warstwy." % layer_id)
			_assert(not layer.profile.resource_path.is_empty() and not profile_paths.has(layer.profile.resource_path), "Każda warstwa musi mieć odrębny zasób profilu .tres: %s." % layer_id)
			profile_paths[layer.profile.resource_path] = true
			_assert(
				MapCompilerScript._source_dependency_paths.has(layer.profile.resource_path),
				"Fingerprint cache kompilatora musi obejmować faktycznie przypisany profil warstwy %s."
				% layer_id
			)
			_assert(layer.profile.reduced_motion_scroll_scale.is_equal_approx(Vector2.ONE), "Profil %s musi blokować parallax przy reduced motion bez ukrywania warstwy." % layer_id)
			_assert(layer.profile.normal_scroll_scale.x > previous_scroll_scale.x and layer.profile.normal_scroll_scale.y > previous_scroll_scale.y, "Kolejne plany L00-L05 muszą poruszać się coraz szybciej względem kamery.")
			_assert(layer.profile.z_index > previous_z_index and layer.z_index == layer.profile.z_index, "Kolejne plany L00-L05 muszą zachować rosnący z-order profili.")
			previous_scroll_scale = layer.profile.normal_scroll_scale
			previous_z_index = layer.profile.z_index
		var parallax_content := layer.get_node_or_null("ParallaxContent") as Parallax2D
		var world_content := layer.get_node_or_null("WorldContent") as Node2D
		_assert(parallax_content != null, "Warstwa %s musi mieć niezależny ParallaxContent." % layer_id)
		_assert(world_content != null, "Warstwa %s musi mieć niezależny WorldContent." % layer_id)
		for coordinate_space in [&"parallax", &"world"]:
			for bucket in [&"authored", &"generated", &"streamed"]:
				var bucket_root := layer.content_root(coordinate_space, bucket)
				_assert(bucket_root != null, "Warstwa %s musi mieć bucket %s/%s." % [layer_id, coordinate_space, bucket])
		var authored_world := layer.content_root(&"world", &"authored")
		if authored_world != null:
			for descendant in authored_world.find_children("*", "", true, false):
				if descendant is DiveVisualLayerElement:
					visual_elements.append(descendant as DiveVisualLayerElement)
	_assert(bool(stack.layer_root(&"L04_near_terrain_skin").profile.world_locked), "L04 musi pozostać związana z kanonicznym terenem świata.")
	_assert(visual_elements.size() == LEGACY_VISUAL_ELEMENT_COUNT, "Piętnaście istniejących cropów musi być piętnastoma niezależnymi elementami L02, a nie jedną spłaszczoną warstwą.")
	var element_ids := {}
	for element in visual_elements:
		_assert(
			MapCompilerScript._source_dependency_paths.has(element.resource_path),
			"Fingerprint cache kompilatora musi obejmować resource_path elementu %s." % element.element_id
		)
		_assert(not ResourceLoader.has_cached(element.resource_path), "Walidacja sceny nie może preloadować streamowanego cropa %s." % element.element_id)
		_assert(element.get_parent() == stack.content_root(&"L02_far_structures", &"world", &"authored"), "Każdy odziedziczony crop musi być authoringowym elementem L02/WorldContent/Authored.")
		_assert(element.is_valid(), "Każdy element warstwy musi mieć poprawne ID, zasób i lokalne bounds: %s." % element.element_id)
		_assert(element.is_manifest_streamed(), "Odziedziczony crop %s musi jawnie używać streamingu z manifestu." % element.element_id)
		_assert(not element_ids.has(element.element_id), "ID elementu warstwy musi być unikalne: %s." % element.element_id)
		element_ids[element.element_id] = true
	var visibility_layer := stack.layer_root(&"L03_mid_drift_props")
	visibility_layer.visible = false
	stack.set_graphics_quality("low")
	stack.set_reduced_motion(true)
	stack.set_graphics_quality("high")
	stack.set_reduced_motion(false)
	_assert(not visibility_layer.visible, "Autorskie visible=false całej warstwy musi przetrwać zmiany jakości i reduced motion.")
	visibility_layer.visible = true
	if not visual_elements.is_empty():
		var visibility_element := visual_elements[0]
		visibility_element.visible = false
		visibility_element.set_graphics_quality("low")
		visibility_element.set_graphics_quality("high")
		_assert(not visibility_element.visible, "Autorskie visible=false elementu musi przetrwać zmiany jakości.")
		visibility_element.visible = true
	var live_layer := stack.layer_root(&"L03_mid_drift_props")
	var live_parallax := live_layer.get_node_or_null("ParallaxContent") as Parallax2D
	var original_live_scale := live_layer.profile.normal_scroll_scale
	var original_live_z := live_layer.profile.z_index
	var profile_script := live_layer.profile.get_script() as Script
	_assert(profile_script != null and profile_script.is_tool(), "Profil warstwy musi być @tool, aby Inspector stosował emit_changed bez przeładowania sceny.")
	live_layer.profile.normal_scroll_scale = Vector2(0.965, 0.965)
	live_layer.profile.z_index = -61
	_assert(live_parallax.scroll_scale.is_equal_approx(Vector2(0.965, 0.965)) and live_layer.z_index == -61, "Edycja profilu .tres musi na żywo aktualizować scroll_scale i z-order warstwy.")
	live_layer.profile.normal_scroll_scale = original_live_scale
	live_layer.profile.z_index = original_live_z
	for descendant in stack.find_children("*", "", true, false):
		_assert(not (descendant is CollisionObject2D) and not (descendant is CollisionShape2D) and not (descendant is CollisionPolygon2D), "Warstwy prezentacyjne nie mogą dodawać kolizji ani przejmować authority gameplayu: %s." % descendant.name)
	var element_template := ResourceLoader.load(LAYER_ELEMENT_TEMPLATE_PATH) as PackedScene
	_assert(element_template != null, "Projekt musi udostępniać prefab nowego edytowalnego elementu warstwy.")
	if element_template != null:
		var template_instance := element_template.instantiate()
		_assert(template_instance is DiveVisualLayerElement, "Prefab elementu musi być Node2D z kontraktem DiveVisualLayerElement.")
		if template_instance is DiveVisualLayerElement:
			_assert(not template_instance.is_manifest_streamed(), "Nowy element autorski musi domyślnie działać jako scene-resident bez wpisu w manifeście.")
			template_instance.position = Vector2(13.0, -7.0)
			template_instance.rotation = 0.25
			template_instance.scale = Vector2(1.3, 0.7)
			_assert(template_instance.position == Vector2(13.0, -7.0) and is_equal_approx(template_instance.rotation, 0.25) and template_instance.scale == Vector2(1.3, 0.7), "Każdy element musi zachować natywne przesuwanie, obrót i niezależne rozciąganie osi Node2D.")
			template_instance.element_id = &"resident_element_test"
			template_instance.resource_path = RESIDENT_ELEMENT_TEST_TEXTURE
			template_instance.local_bounds = Rect2(0.0, 0.0, 620.0, 167.0)
			_assert(template_instance.ensure_scene_resident_resource_loaded(), "Nowy element scene-resident musi samodzielnie wczytać wskazany zasób bez wpisu w manifeście.")
			_assert(template_instance.runtime_content_node() is Sprite2D, "Element scene-resident z teksturą musi utworzyć runtime Sprite2D w Attachment.")
			template_instance.resource_kind = DiveVisualLayerElement.ResourceKind.PACKED_SCENE
			var mismatched_type_rejected := false
			for validation_error in template_instance.resource_content_validation_errors():
				if String(validation_error).contains("nie jest PackedScene"):
					mismatched_type_rejected = true
					break
			_assert(mismatched_type_rejected, "Walidacja headless musi odrzucać zasób o typie niezgodnym z resource_kind.")
		template_instance.free()
		var invalid_attachment_instance := element_template.instantiate() as DiveVisualLayerElement
		invalid_attachment_instance.element_id = &"invalid_attachment_test"
		invalid_attachment_instance.resource_path = RESIDENT_ELEMENT_TEST_TEXTURE
		invalid_attachment_instance.local_bounds = Rect2(0.0, 0.0, 620.0, 167.0)
		var attachment := invalid_attachment_instance.get_node_or_null("Attachment") as Node2D
		attachment.position = Vector2(4.0, 0.0)
		var attachment_transform_rejected := false
		for validation_error in invalid_attachment_instance.validation_errors():
			if String(validation_error).contains("identity transform węzła Attachment"):
				attachment_transform_rejected = true
				break
		_assert(attachment_transform_rejected, "Attachment musi pozostać neutralnym kontenerem, aby culling odpowiadał obrazowi.")
		invalid_attachment_instance.free()
		var invalid_bounds_instance := element_template.instantiate() as DiveVisualLayerElement
		invalid_bounds_instance.element_id = &"invalid_bounds_test"
		invalid_bounds_instance.resource_path = RESIDENT_ELEMENT_TEST_TEXTURE
		invalid_bounds_instance.load_policy = DiveVisualLayerElement.LoadPolicy.MANIFEST_STREAMED
		invalid_bounds_instance.local_bounds = Rect2(0.0, 0.0, 620.0, 167.0)
		invalid_bounds_instance.texture_region = Rect2(2.0, 2.0, 619.0, 167.0)
		var bounds_mismatch_rejected := false
		for validation_error in invalid_bounds_instance.validation_errors():
			if String(validation_error).contains("local_bounds.size zgodnego z texture_region.size"):
				bounds_mismatch_rejected = true
				break
		_assert(bounds_mismatch_rejected, "Streamowany element teksturowy musi odrzucać bounds niezgodne z rysowanym regionem.")
		invalid_bounds_instance.free()
		var duplicate_instance := element_template.instantiate() as DiveVisualLayerElement
		duplicate_instance.element_id = visual_elements[0].element_id
		duplicate_instance.resource_path = RESIDENT_ELEMENT_TEST_TEXTURE
		duplicate_instance.local_bounds = Rect2(0.0, 0.0, 620.0, 167.0)
		var l03_authored := stack.content_root(&"L03_mid_drift_props", &"parallax", &"authored")
		l03_authored.add_child(duplicate_instance)
		var duplicate_rejected := false
		for validation_error in stack.validation_errors():
			if String(validation_error).contains("powtórzony element_id"):
				duplicate_rejected = true
				break
		_assert(duplicate_rejected, "Walidator stosu musi odrzucać powielone element_id także między warstwami.")
		l03_authored.remove_child(duplicate_instance)
		duplicate_instance.free()
		var misplaced_instance := element_template.instantiate() as DiveVisualLayerElement
		misplaced_instance.element_id = &"misplaced_element_test"
		misplaced_instance.resource_path = RESIDENT_ELEMENT_TEST_TEXTURE
		misplaced_instance.local_bounds = Rect2(0.0, 0.0, 620.0, 167.0)
		var l03_generated := stack.content_root(&"L03_mid_drift_props", &"parallax", &"generated")
		l03_generated.add_child(misplaced_instance)
		var ancestry_rejected := false
		for validation_error in stack.validation_errors():
			if String(validation_error).contains("musi należeć do ParallaxContent/Authored"):
				ancestry_rejected = true
				break
		_assert(ancestry_rejected, "Walidator musi odrzucać ręczny element umieszczony poza bucketem Authored.")
		l03_generated.remove_child(misplaced_instance)
		misplaced_instance.free()
		var unsafe_direct_sprite := Sprite2D.new()
		unsafe_direct_sprite.z_index = 2
		unsafe_direct_sprite.top_level = true
		l03_authored.add_child(unsafe_direct_sprite)
		var direct_z_rejected := false
		for validation_error in stack.validation_errors():
			if String(validation_error).contains("musi dziedziczyć pasmo z-order") or String(validation_error).contains("nie może używać top_level"):
				direct_z_rejected = true
				break
		_assert(direct_z_rejected, "Bezpośredni Sprite2D nie może ominąć transformu ani pasma z-order warstwy.")
		l03_authored.remove_child(unsafe_direct_sprite)
		unsafe_direct_sprite.free()
		var l04_world := stack.layer_root(&"L04_near_terrain_skin").get_node("WorldContent") as Node2D
		l04_world.position = Vector2(5.0, 0.0)
		var terrain_infrastructure_rejected := false
		for validation_error in stack.validation_errors():
			if String(validation_error).contains("L04_near_terrain_skin wymaga WorldContent z identity transform"):
				terrain_infrastructure_rejected = true
				break
		_assert(terrain_infrastructure_rejected, "Infrastruktura L04 nie może odsunąć grafiki terenu od kanonicznej kolizji/SDF.")
		l04_world.position = Vector2.ZERO
		var l03_parallax := stack.layer_root(&"L03_mid_drift_props").get_node("ParallaxContent") as Parallax2D
		var default_limit_begin := l03_parallax.limit_begin
		l03_parallax.limit_begin = Vector2(-1_000.0, -1_000.0)
		var bounded_parallax_rejected := false
		for validation_error in stack.validation_errors():
			if String(validation_error).contains("domyślnych nieaktywnych limitów Parallax2D"):
				bounded_parallax_rejected = true
				break
		_assert(bounded_parallax_rejected, "Aktywne limity Parallax2D muszą być odrzucone, bo łamią dokładną kompensację reduced motion.")
		l03_parallax.limit_begin = default_limit_begin
	var scripted_visual := Node2D.new()
	scripted_visual.set_script(MapObjectScript)
	var scripted_errors := DiveVisualLayerElement.visual_subtree_validation_errors(scripted_visual)
	var script_rejected := false
	for validation_error in scripted_errors:
		if String(validation_error).contains("własnego skryptu runtime"):
			script_rejected = true
			break
	_assert(script_rejected, "PackedScene elementu wizualnego nie może przemycić skryptu gameplay/runtime.")
	scripted_visual.free()
	# Use a real text scene whose `script` property is explicitly serialized.
	# Packing a transient node can normalize its global-script class into the
	# node type, making that synthetic fixture dependent on engine internals.
	var scripted_packed := ResourceLoader.load(CABLE_VISUAL_PATH) as PackedScene
	_assert(scripted_packed != null, "Test preflightu wymaga istniejącego skryptowego PackedScene.")
	var preflight_script_rejected := false
	if scripted_packed != null:
		for validation_error in DiveVisualLayerElement.packed_scene_preflight_validation_errors(scripted_packed):
			var error_text := String(validation_error)
			if error_text.contains("skrypt") and error_text.contains("runtime"):
				preflight_script_rejected = true
				break
	_assert(preflight_script_rejected, "Preflight SceneState musi odrzucić skrypt przed PackedScene.instantiate().")
	var absolute_z_visual := Sprite2D.new()
	absolute_z_visual.z_as_relative = false
	var absolute_z_errors := DiveVisualLayerElement.visual_subtree_validation_errors(absolute_z_visual)
	var absolute_z_rejected := false
	for validation_error in absolute_z_errors:
		if String(validation_error).contains("z_as_relative = true"):
			absolute_z_rejected = true
			break
	_assert(absolute_z_rejected, "PackedScene elementu wizualnego nie może ominąć pasma z-order warstwy.")
	absolute_z_visual.free()
	var visual_layers_parent := map_root.get_node_or_null("VisualLayers") as Node2D
	_assert(visual_layers_parent != null, "Test world-lock wymaga rodzica VisualLayers typu Node2D.")
	if visual_layers_parent != null:
		visual_layers_parent.position = Vector2(5.0, 0.0)
		var shifted_parent_result: Dictionary = compiler.compile_map(map_root, 91_018)
		var shifted_parent_errors: PackedStringArray = shifted_parent_result.get(
			"errors",
			PackedStringArray()
		)
		_assert(
			_packed_strings_contain(shifted_parent_errors, "VisualLayers musi zachować identity transform"),
			"Kompilator musi odrzucać przesunięcie nadrzędnego VisualLayers, które odkleja L04 od kolizji/SDF."
		)
		visual_layers_parent.position = Vector2.ZERO
	var visual_streamer := map_root.get_node_or_null(
		"VisualLayers/VisualChunkStreamer"
	) as DiveVisualChunkStreamer
	_assert(visual_streamer != null, "Produkcyjna scena musi zawierać VisualChunkStreamer.")
	if visual_streamer != null:
		var canonical_manifest_path := visual_streamer.manifest_path
		visual_streamer.manifest_path = (
			"res://assets/diving/world/map_v2/visual_chunks/map_visual_chunks_v1.json"
		)
		var legacy_streamer_result: Dictionary = compiler.compile_map(map_root, 91_018)
		var legacy_streamer_errors: PackedStringArray = legacy_streamer_result.get(
			"errors",
			PackedStringArray()
		)
		_assert(
			_packed_strings_contain(legacy_streamer_errors, "Produkcyjny VisualChunkStreamer musi używać manifestu v2"),
			"Kompilator musi odrzucać produkcyjny streamer wskazujący legacy v1 zamiast scenowego authority v2."
		)
		visual_streamer.manifest_path = canonical_manifest_path
	var baseline: Dictionary = compiler.compile_map(map_root, 91_019)
	var baseline_errors: PackedStringArray = baseline.get("errors", PackedStringArray())
	_assert(baseline_errors.is_empty(), "Bazowa scena musi kompilować się przed testem transformacji sześciu warstw.")
	if baseline_errors.is_empty():
		for element_index in range(visual_elements.size()):
			var element := visual_elements[element_index]
			element.position += Vector2(3.0 + element_index, -2.0)
			element.rotation += 0.01 * float(element_index + 1)
			element.scale *= Vector2(1.01, 0.99)
		var changed: Dictionary = compiler.compile_map(map_root, 91_019)
		var changed_errors: PackedStringArray = changed.get("errors", PackedStringArray())
		_assert(changed_errors.is_empty(), "Transformacje elementów warstw nie mogą zepsuć kompilacji mapy.")
		if changed_errors.is_empty():
			_assert(str(baseline.get("blueprint").map_gameplay_signature) == str(changed.get("blueprint").map_gameplay_signature), "Przesuwanie, obracanie i rozciąganie elementów sześciu warstw nie może zmieniać podpisu gameplayowego.")
	map_root.free()


func _test_visual_manifest_compiler_gate(compiler) -> void:
	var map_root := _instantiate_map()
	if map_root == null:
		return
	var stack := map_root.get_node_or_null(SIX_LAYER_VISUALS_PATH) as DiveVisualLayerStack
	_assert(stack != null, "Test manifestu wymaga scenowego stosu sześciu warstw.")
	if stack == null:
		map_root.free()
		return
	var parser := JSON.new()
	var parse_status := parser.parse(
		FileAccess.get_file_as_string(MapCompilerScript.VISUAL_CHUNK_MANIFEST_PATH)
	)
	_assert(parse_status == OK and parser.data is Dictionary, "Produkcyjny manifest v2 musi być poprawnym JSON-em.")
	if parse_status != OK or not (parser.data is Dictionary):
		map_root.free()
		return
	var manifest: Dictionary = parser.data
	var baseline_errors := MapCompilerScript.visual_manifest_validation_errors(
		stack,
		manifest,
		map_root.world_size,
		true
	)
	_assert(
		baseline_errors.is_empty(),
		"Bramka kompilatora musi akceptować aktualny manifest v2 i mapowanie sceny: %s"
		% "; ".join(baseline_errors)
	)
	var export_baseline_errors := MapCompilerScript.visual_manifest_validation_errors(
		stack,
		manifest,
		map_root.world_size,
		false
	)
	_assert(
		export_baseline_errors.is_empty(),
		"Bramka non-strict eksportu musi akceptować zasoby rozwiązywane przez ResourceLoader: %s"
		% "; ".join(export_baseline_errors)
	)
	var export_fingerprint := MapCompilerScript._source_dependency_fingerprint(false)
	_assert(
		export_fingerprint.contains("%s:resource:" % MapCompilerScript.VISUAL_COMPOSITION_SCENE_PATH)
		and export_fingerprint.contains("%s:resource:" % RESIDENT_ELEMENT_TEST_TEXTURE)
		and not export_fingerprint.contains("%s:missing" % MapCompilerScript.VISUAL_COMPOSITION_SCENE_PATH)
		and not export_fingerprint.contains("%s:missing" % RESIDENT_ELEMENT_TEST_TEXTURE),
		"Fingerprint non-editor musi oznaczać importowane sceny i tekstury stabilnym markerem ResourceLoader zamiast :missing."
	)
	var composition_sha := FileAccess.get_sha256(
		MapCompilerScript.VISUAL_COMPOSITION_SCENE_PATH
	).to_lower()
	_assert(
		not export_fingerprint.contains(
			"%s:%s" % [MapCompilerScript.VISUAL_COMPOSITION_SCENE_PATH, composition_sha]
		),
		"Fingerprint non-editor nie może zależeć od źródłowych bajtów importowanej sceny."
	)
	var manifest_sha := FileAccess.get_sha256(
		MapCompilerScript.VISUAL_CHUNK_MANIFEST_PATH
	).to_lower()
	_assert(
		export_fingerprint.contains(
			"%s:%s" % [MapCompilerScript.VISUAL_CHUNK_MANIFEST_PATH, manifest_sha]
		),
		"Fingerprint non-editor może zachować hash bezpośrednio czytelnego manifestu JSON."
	)

	var hash_mismatch_manifest: Dictionary = manifest.duplicate(true)
	var hash_mismatch_composition: Dictionary = hash_mismatch_manifest.get(
		"composition_scene",
		{}
	)
	hash_mismatch_composition["sha256"] = "0".repeat(64)
	hash_mismatch_manifest["composition_scene"] = hash_mismatch_composition
	var non_strict_hash_errors := MapCompilerScript.visual_manifest_validation_errors(
		stack,
		hash_mismatch_manifest,
		map_root.world_size,
		false
	)
	_assert(
		not _packed_strings_contain(non_strict_hash_errors, "Scena kompozycji ma SHA-256"),
		"Bramka non-strict ma wymagać poprawnego formatu SHA, ale nie porównywać źródłowych bajtów eksportowanego zasobu."
	)
	var strict_hash_errors := MapCompilerScript.visual_manifest_validation_errors(
		stack,
		hash_mismatch_manifest,
		map_root.world_size,
		true
	)
	_assert(
		_packed_strings_contain(strict_hash_errors, "Scena kompozycji ma SHA-256"),
		"Bramka strict edytora musi odrzucać nieaktualny source hash kompozycji."
	)
	var malformed_hash_manifest: Dictionary = manifest.duplicate(true)
	var malformed_hash_composition: Dictionary = malformed_hash_manifest.get(
		"composition_scene",
		{}
	)
	malformed_hash_composition["sha256"] = "niepoprawny"
	malformed_hash_manifest["composition_scene"] = malformed_hash_composition
	var malformed_hash_errors := MapCompilerScript.visual_manifest_validation_errors(
		stack,
		malformed_hash_manifest,
		map_root.world_size,
		false
	)
	_assert(
		_packed_strings_contain(malformed_hash_errors, "Scena kompozycji nie zawiera poprawnego SHA-256"),
		"Bramka non-strict nadal musi wymagać poprawnie sformatowanego SHA-256."
	)
	var wrong_type_manifest: Dictionary = manifest.duplicate(true)
	var wrong_type_composition: Dictionary = wrong_type_manifest.get("composition_scene", {})
	wrong_type_composition["path"] = RESIDENT_ELEMENT_TEST_TEXTURE
	wrong_type_manifest["composition_scene"] = wrong_type_composition
	var wrong_type_errors := MapCompilerScript.visual_manifest_validation_errors(
		stack,
		wrong_type_manifest,
		map_root.world_size,
		false
	)
	_assert(
		_packed_strings_contain(wrong_type_errors, "nie jest zasobem typu PackedScene"),
		"Bramka non-strict musi odrzucać istniejący importowany zasób niezgodnego typu."
	)

	var first_layer := stack.layer_root(EXPECTED_VISUAL_LAYER_IDS[0])
	var second_layer := stack.layer_root(EXPECTED_VISUAL_LAYER_IDS[1])
	_assert(first_layer != null and second_layer != null, "Test profilu wymaga pierwszych dwóch warstw.")
	if first_layer != null and second_layer != null:
		var original_profile := first_layer.profile
		first_layer.profile = second_layer.profile
		var replaced_profile_errors := MapCompilerScript.visual_manifest_validation_errors(
			stack,
			manifest,
			map_root.world_size,
			true
		)
		_assert(
			_packed_strings_contain(replaced_profile_errors, "ma faktycznie przypisany profil")
			and _packed_strings_contain(replaced_profile_errors, "zamiast kanonicznego"),
			"Bramka manifestu musi odrzucać profil warstwy podmieniony mimo poprawnych ścieżek w manifeście."
		)
		first_layer.profile = original_profile

	var stale_schema: Dictionary = manifest.duplicate(true)
	stale_schema["schema_version"] = 1
	var stale_schema_errors := MapCompilerScript.visual_manifest_validation_errors(
		stack,
		stale_schema,
		map_root.world_size
	)
	_assert(
		_packed_strings_contain(stale_schema_errors, "schema_version = 2"),
		"Kompilator musi odrzucać manifest inny niż schema v2 przed akceptacją mapy."
	)

	var missing_entry_manifest: Dictionary = manifest.duplicate(true)
	var missing_payloads: Array = missing_entry_manifest.get("payloads", [])
	var missing_payload: Dictionary = missing_payloads[0]
	var missing_elements: Array = missing_payload.get("elements", [])
	var removed_entry: Dictionary = missing_elements.pop_back()
	missing_payload["elements"] = missing_elements
	missing_payloads[0] = missing_payload
	missing_entry_manifest["payloads"] = missing_payloads
	var missing_entry_errors := MapCompilerScript.visual_manifest_validation_errors(
		stack,
		missing_entry_manifest,
		map_root.world_size
	)
	_assert(
		_packed_strings_contain(
			missing_entry_errors,
			"Scenowy element Manifest Streamed %s wymaga dokładnie jednego wpisu manifestu v2"
			% str(removed_entry.get("key", ""))
		),
		"Każdy scenowy MANIFEST_STREAMED musi mieć dokładnie jeden wpis manifestu v2."
	)

	var ghost_entry_manifest: Dictionary = manifest.duplicate(true)
	var ghost_payloads: Array = ghost_entry_manifest.get("payloads", [])
	var ghost_payload: Dictionary = ghost_payloads[0]
	var ghost_elements: Array = ghost_payload.get("elements", [])
	var ghost_entry: Dictionary = removed_entry.duplicate(true)
	ghost_entry["key"] = "manifest_only_test"
	ghost_elements.append(ghost_entry)
	ghost_payload["elements"] = ghost_elements
	ghost_payloads[0] = ghost_payload
	ghost_entry_manifest["payloads"] = ghost_payloads
	var ghost_entry_errors := MapCompilerScript.visual_manifest_validation_errors(
		stack,
		ghost_entry_manifest,
		map_root.world_size
	)
	_assert(
		_packed_strings_contain(
			ghost_entry_errors,
			"Wpis manifestu v2 manifest_only_test wymaga dokładnie jednego scenowego elementu"
		),
		"Każdy wpis manifestu v2 musi mieć dokładnie jeden scenowy element."
	)

	var streamed_elements: Array[DiveVisualLayerElement] = []
	for node in stack.find_children("*", "", true, false):
		if node is DiveVisualLayerElement and (node as DiveVisualLayerElement).is_manifest_streamed():
			streamed_elements.append(node as DiveVisualLayerElement)
	_assert(streamed_elements.size() >= 2, "Test mapowania manifestu wymaga co najmniej dwóch elementów streamowanych.")
	if streamed_elements.size() >= 2:
		var element := streamed_elements[0]
		var original_policy := element.load_policy
		element.load_policy = DiveVisualLayerElement.LoadPolicy.SCENE_RESIDENT
		var resident_result: Dictionary = compiler.compile_map(map_root, 91_020)
		var resident_errors: PackedStringArray = resident_result.get("errors", PackedStringArray())
		_assert(
			_packed_strings_contain(resident_errors, "musi używać trybu Manifest Streamed"),
			"Bramka compile_map musi odrzucać wpis manifestu wskazujący element Scene Resident."
		)
		element.load_policy = original_policy

		var original_resource_path := element.resource_path
		element.resource_path = streamed_elements[1].resource_path
		var path_result: Dictionary = compiler.compile_map(map_root, 91_021)
		var path_errors: PackedStringArray = path_result.get("errors", PackedStringArray())
		_assert(
			_packed_strings_contain(path_errors, "wskazuje inny zasób niż manifest v2"),
			"Bramka compile_map musi odrzucać rozbieżność resource_path scena↔manifest."
		)
		element.resource_path = original_resource_path

		var original_parent := element.get_parent()
		var original_owner := element.owner
		var foreign_layer_parent := stack.content_root(
			&"L03_mid_drift_props",
			&"world",
			&"authored"
		)
		element.owner = null
		original_parent.remove_child(element)
		foreign_layer_parent.add_child(element)
		var layer_result: Dictionary = compiler.compile_map(map_root, 91_022)
		var layer_errors: PackedStringArray = layer_result.get("errors", PackedStringArray())
		_assert(
			_packed_strings_contain(layer_errors, "zamiast wskazanej w manifeście L02_far_structures"),
			"Bramka compile_map musi odrzucać rozbieżność target_layer scena↔manifest."
		)
		foreign_layer_parent.remove_child(element)
		original_parent.add_child(element)
		element.owner = original_owner
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
	authored_object.visual_scene = ResourceLoader.load(BLOCKAGE_VISUAL_PATH) as PackedScene
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
		_assert(str(changed_record.get("visual_scene_path", "")) == BLOCKAGE_VISUAL_PATH and int(changed_record.get("visual_z_index", 0)) == authored_object.visual_z_index, "Kompilator musi przekazać prefab i z-index prezentacji do runtime.")
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


func _test_landmark_position_change_updates_signature(compiler) -> void:
	var map_root := _instantiate_map()
	if map_root == null:
		return
	var baseline: Dictionary = compiler.compile_map(map_root, 91_017)
	var baseline_errors: PackedStringArray = baseline.get("errors", PackedStringArray())
	_assert(baseline_errors.is_empty(), "Bazowa scena musi kompilować się przed testem pozycji landmarku.")
	if baseline_errors.is_empty():
		var authored_landmark := _authored_object_by_id(map_root, "R3-03")
		_assert(authored_landmark != null, "Test podpisu landmarku wymaga R3-03.")
		if authored_landmark != null:
			authored_landmark.position += Vector2(8.0, 0.0)
			var changed: Dictionary = compiler.compile_map(map_root, 91_017)
			var changed_errors: PackedStringArray = changed.get("errors", PackedStringArray())
			_assert(changed_errors.is_empty(), "Niewielkie przesunięcie landmarku nie może zepsuć kompilacji mapy.")
			if changed_errors.is_empty():
				var baseline_blueprint = baseline.get("blueprint")
				var changed_blueprint = changed.get("blueprint")
				var baseline_landmark: Dictionary = baseline_blueprint.get_landmark("R3-03")
				var changed_landmark: Dictionary = changed_blueprint.get_landmark("R3-03")
				_assert(str(changed_landmark.get("id", "")) == str(baseline_landmark.get("id", "")), "Przesunięcie landmarku musi zachować jego stable ID.")
				_assert(changed_landmark.get("position", Vector2.ZERO) != baseline_landmark.get("position", Vector2.ZERO), "Przesunięcie landmarku musi zmienić publikowaną pozycję.")
				_assert(
					str(baseline_blueprint.map_gameplay_signature) != str(changed_blueprint.map_gameplay_signature),
					"Zmiana pozycji landmarku musi zmieniać podpis gameplayowy mapy."
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


func _assert_r1_j7_terrain_skin_contract() -> void:
	var packed := ResourceLoader.load(R1_J7_ART_CELL_VISUAL_PATH) as PackedScene
	_assert(packed != null, "ArtCell R1-04/J-7 musi dać się załadować do kontroli kompozycji.")
	if packed == null:
		return
	var candidate := packed.instantiate() as Node2D
	_assert(candidate != null, "ArtCell R1-04/J-7 musi mieć root Node2D.")
	if candidate == null:
		return
	_assert(candidate.get_node_or_null("FarPlate") == null, "ArtCell R1-04/J-7 nie może zachowywać usuniętego FarPlate.")
	_assert(candidate.find_child("EnvironmentPlate", true, false) == null, "ArtCell R1-04/J-7 nie może zachowywać usuniętego EnvironmentPlate.")
	var terrain_skin := candidate.get_node_or_null("TerrainIntegration/AuthoredTerrainSkin")
	_assert(terrain_skin is Polygon2D, "ArtCell R1-04/J-7 musi zachować SDF-clipped AuthoredTerrainSkin.")
	if terrain_skin is Polygon2D:
		_assert((terrain_skin as Polygon2D).material != null, "AuthoredTerrainSkin R1-04/J-7 musi zachować materiał terenu.")
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


func _test_stale_gameplay_signature_is_rejected(compiler, world) -> void:
	var stale_world = WorldStateScript.new()
	stale_world.blueprint = world.blueprint.duplicate(true)
	stale_world.delta = world.delta.duplicate(true)
	var stale_blueprint = stale_world.blueprint
	var original_delta = stale_world.delta
	stale_world.delta.active_landmark_id = "R2-04"
	stale_world.delta.discovered_landmarks.append("R2-04")
	stale_world.delta.opened_shortcuts.append("SC-02")
	stale_world.delta.opened_containers.append("seed_bank_vault")
	stale_world.delta.collapsed_paths.append("C019")
	var original_delta_projection := _world_delta_projection(original_delta)
	var replacement_signature := "0".repeat(64)
	if replacement_signature == str(stale_blueprint.map_gameplay_signature):
		replacement_signature = "f".repeat(64)
	stale_blueprint.map_gameplay_signature = replacement_signature

	var errors: PackedStringArray = compiler.ensure_world_is_current(stale_world)
	_assert(errors.has("Zapis kampanii nie odpowiada bieżącej scenie mapy."), "Zapis z nieaktualnym podpisem gameplayowym musi zostać jawnie odrzucony.")
	_assert(stale_world.blueprint == stale_blueprint, "Clean break podpisu nie może po cichu zastąpić blueprintu niezgodnego zapisu.")
	_assert(
		stale_world.delta == original_delta
		and _world_delta_projection(stale_world.delta) == original_delta_projection,
		"Odrzucenie nieaktualnego podpisu nie może mutować WorldDelta."
	)


func _world_delta_projection(delta) -> Dictionary:
	return {
		"active_landmark_id": delta.active_landmark_id,
		"discovered_landmarks": delta.discovered_landmarks.duplicate(),
		"discovered_chunks": delta.discovered_chunks.duplicate(),
		"opened_containers": delta.opened_containers.duplicate(),
		"collected_items": delta.collected_items.duplicate(),
		"remaining_container_contents": delta.remaining_container_contents.duplicate(true),
		"dead_divers": delta.dead_divers.duplicate(true),
		"lost_backpacks": delta.lost_backpacks.duplicate(true),
		"dropped_loot_piles": delta.dropped_loot_piles.duplicate(true),
		"rescued_or_dead_survivors": delta.rescued_or_dead_survivors.duplicate(true),
		"placed_buoys": delta.placed_buoys.duplicate(),
		"marked_heavy_objects": delta.marked_heavy_objects.duplicate(),
		"recovered_heavy_objects": delta.recovered_heavy_objects.duplicate(),
		"opened_shortcuts": delta.opened_shortcuts.duplicate(),
		"activated_fixed_devices": delta.activated_fixed_devices.duplicate(),
		"collapsed_paths": delta.collapsed_paths.duplicate(),
		"depleted_biological_nodes": delta.depleted_biological_nodes.duplicate(true),
	}


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


func _rect_inclusive_has_point(rect: Rect2, point: Vector2) -> bool:
	return (
		point.x + 0.001 >= rect.position.x
		and point.y + 0.001 >= rect.position.y
		and point.x - 0.001 <= rect.end.x
		and point.y - 0.001 <= rect.end.y
	)


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


func _assert_regular_connection_reachability(blueprint) -> void:
	var reachable_from_entry := _regular_connection_reachable_ids(
		blueprint,
		str(blueprint.entry_landmark_id)
	)
	_assert(
		reachable_from_entry.size() == blueprint.landmarks.size(),
		"Wszystkie 27 landmarków musi pozostawać w jednej składowej zwykłych połączeń; osiągalne %d/%d."
		% [reachable_from_entry.size(), blueprint.landmarks.size()]
	)
	var reachable_from_archive := _regular_connection_reachable_ids(blueprint, "R1-09")
	_assert(
		reachable_from_archive.has("R3-04"),
		"Zalane Archiwum R1-09 musi zachować zwykłą trasę do Elektrowni R3-04 bez SC-02."
	)
	var reachable_from_r3 := _regular_connection_reachable_ids(blueprint, "R3-04")
	_assert(
		reachable_from_r3.has("R4-06"),
		"Elektrownia R3-04 musi zachować zwykłą trasę do Serca R4-06 i Rozdzielni C-4."
	)


func _regular_connection_reachable_ids(blueprint, start_landmark_id: String) -> Dictionary:
	var adjacency: Dictionary = {}
	for landmark in blueprint.landmarks:
		var landmark_id := str(landmark.get("id", ""))
		if not landmark_id.is_empty():
			adjacency[landmark_id] = []
	for connection in blueprint.connections:
		if str(connection.get("type", "main")) == "shortcut":
			continue
		var from_id := str(connection.get("from_id", ""))
		var to_id := str(connection.get("to_id", ""))
		if not adjacency.has(from_id) or not adjacency.has(to_id):
			continue
		var from_neighbours: Array = adjacency[from_id]
		from_neighbours.append(to_id)
		adjacency[from_id] = from_neighbours
		var to_neighbours: Array = adjacency[to_id]
		to_neighbours.append(from_id)
		adjacency[to_id] = to_neighbours

	var reachable: Dictionary = {}
	if not adjacency.has(start_landmark_id):
		return reachable
	var pending: Array[String] = [start_landmark_id]
	reachable[start_landmark_id] = true
	var read_index := 0
	while read_index < pending.size():
		var current_id := pending[read_index]
		read_index += 1
		for neighbour_value in adjacency.get(current_id, []):
			var neighbour_id := str(neighbour_value)
			if reachable.has(neighbour_id):
				continue
			reachable[neighbour_id] = true
			pending.append(neighbour_id)
	return reachable


func _packed_strings_contain(values: PackedStringArray, fragment: String) -> bool:
	for value in values:
		if value.contains(fragment):
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Underwater map scene assertion failed: " + message)
