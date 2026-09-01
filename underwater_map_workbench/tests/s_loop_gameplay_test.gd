extends SceneTree

const CompilerScript := preload("res://underwater_map_workbench/runtime/UnderwaterMapSceneCompiler.gd")
const RuntimeScript := preload("res://underwater_map_workbench/runtime/UnderwaterMapRuntime.gd")
const WorldStateScript := preload("res://scripts/data/UnderwaterWorldState.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")

const CAMPAIGN_SEED := 73_331

var _failed := false
var _runtime: Node


func _initialize() -> void:
	var compiler = CompilerScript.new()
	var manifest := compiler.manifest_snapshot()
	_assert(not manifest.is_empty(), "Manifest pętli S musi przejść walidację kompilatora.")
	_assert(compiler.generated_scene_is_current(), "Pętla S musi mieć bieżącą deterministyczną UnderwaterMap.tscn.")
	if manifest.is_empty():
		_finish()
		return

	var world = WorldStateScript.new()
	world.setup(CAMPAIGN_SEED)
	var compile_errors: PackedStringArray = compiler.generate(world, CAMPAIGN_SEED)
	_assert(compile_errors.is_empty(), "Manifest pętli S musi kompilować się bez błędów: %s" % "; ".join(compile_errors))
	if not compile_errors.is_empty() or world.blueprint == null:
		_finish()
		return

	var setup = ExpeditionSetupScript.new()
	setup.day = 4
	setup.base_support_level = 1
	setup.can_place_buoys = true
	setup.tutorial_mode = true
	_runtime = RuntimeScript.new()
	_runtime.name = "SLoopGameplayRuntime"
	_runtime.call("configure", world, str(world.blueprint.entry_landmark_id), setup)
	root.add_child(_runtime)

	var gameplay := manifest.get("gameplay", {}) as Dictionary
	var navigation = _runtime.call("navigation_snapshot")
	_assert(bool(navigation.call("is_valid")), "Pętla S musi publikować poprawny produkcyjny raster nawigacji.")
	_assert_s_loop_gameplay_runtime(world.blueprint, gameplay, navigation)
	_finish()


func _assert_s_loop_gameplay_runtime(blueprint, gameplay: Dictionary, navigation) -> void:
	var expected_device_ids := PackedStringArray([
		"junction_j7",
		"archive_terminal",
		"r3_diagnostic_panel",
		"r3_generator",
		"c4_switchboard",
		"c4_splitter_mount",
	])
	var actual_device_ids := PackedStringArray()
	for device_value in blueprint.fixed_device_spawns:
		if device_value is Dictionary:
			actual_device_ids.append(str((device_value as Dictionary).get("id", "")))
	_assert(actual_device_ids == expected_device_ids, "Pętla S musi zachować dokładną kolejność urządzeń kampanii.")

	var map_current_zones: Array = blueprint.current_zones
	_assert(map_current_zones.size() == 2, "Pętla S musi publikować dokładnie dwa prądy świata.")
	for index in range(map_current_zones.size()):
		var source := (gameplay.get("current_zones", []) as Array)[index] as Dictionary
		var zone := map_current_zones[index] as Dictionary
		var expected_bounds := _rect(source.get("bounds", []))
		var expected_velocity := _vector(source.get("velocity", []))
		_assert(not source.has("rect"), "Manifest prądu ma authorować bounds, nie pochodne rect.")
		_assert(zone.get("bounds", null) is Rect2, "Compiler musi typować current_zones.bounds do Rect2.")
		_assert(zone.get("rect", null) is Rect2, "Compiler musi normalizować current_zones.bounds do runtime rect.")
		_assert(zone.get("bounds", Rect2()) == expected_bounds, "Compiler musi zachować bounds prądu 1:1.")
		_assert(zone.get("rect", Rect2()) == expected_bounds, "Runtime rect prądu musi być równe bounds manifestu.")
		_assert(zone.get("velocity", null) is Vector2, "Compiler musi typować velocity prądu do Vector2.")
		_assert(zone.get("velocity", Vector2.ZERO) == expected_velocity, "Compiler musi zachować velocity prądu 1:1.")
		_assert(
			_runtime.call("current_at", expected_bounds.get_center()) == expected_velocity,
			"ContinuousDiveWorld.current_at() musi zwracać prędkość w środku authored bounds.",
		)
		_assert(
			navigation.call("current_at", expected_bounds.get_center()) == expected_velocity,
			"DiveNavigationSnapshot.current_at() musi zwracać prędkość w środku authored bounds.",
		)
	if map_current_zones.size() == 2:
		_assert(
			not (map_current_zones[0] as Dictionary).get("rect", Rect2()).intersects(
				(map_current_zones[1] as Dictionary).get("rect", Rect2()),
			),
			"Dwa prądy świata nie mogą się nakładać.",
		)
	_assert(_runtime.call("current_at", Vector2(6800, 4800)) == Vector2.ZERO, "Przed prądem Archiwum musi zostać spokojna woda.")
	_assert(_runtime.call("current_at", Vector2(6800, 6800)) == Vector2.ZERO, "Za prądem Archiwum musi zostać 600+ jednostek spokojnej wody.")
	_assert(_runtime.call("current_at", Vector2(16560, 10480)) == Vector2.ZERO, "Przed prądem risk route musi zostać 600+ jednostek spokojnej wody.")
	_assert(_runtime.call("current_at", Vector2(18880, 10480)) == Vector2.ZERO, "Za prądem risk route musi zostać 600+ jednostek spokojnej wody.")

	_assert_runtime_ids(
		_runtime.get("containers"),
		"container_id",
		PackedStringArray([
			"tutorial_market_crate",
			"tutorial_workshop_case",
			"archive_medical_cache",
			"r3_maintenance_crate",
			"c4_lifeline_cache",
			"salvage_basin_cache",
		]),
		"kontenery",
	)
	_assert_runtime_ids(
		_runtime.get("world_pickups"),
		"pickup_id",
		PackedStringArray([
			"pickup_archive_food",
			"pickup_archive_scrap",
			"pickup_r3_planks",
			"pickup_c4_scrap",
		]),
		"znajdźki",
	)
	_assert_runtime_ids(
		_runtime.get("threats"),
		"threat_id",
		PackedStringArray(["eel_c4_risk", "eel_salvage_basin"]),
		"zagrożenia",
	)
	_assert_runtime_ids(
		_runtime.get("rescue_survivors"),
		"encounter_id",
		PackedStringArray(["rescue_leon"]),
		"ocaleni",
	)
	_assert_runtime_ids(
		_runtime.get("persistent_interactables"),
		"persistent_id",
		PackedStringArray([
			"buoy_archive_return",
			"buoy_c4_return",
			"SC-01",
			"shortcut_central_return",
			"shortcut_c4_service",
			"junction_j7",
			"archive_terminal",
			"r3_diagnostic_panel",
			"r3_generator",
			"c4_switchboard",
			"c4_splitter_mount",
			"sunken_transformer",
		]),
		"interakcje trwałe",
	)

	var archive_medicine := _record_by_id(gameplay.get("loot_spawns", []) as Array, "archive_medical_cache")
	var c4_medicine := _record_by_id(gameplay.get("loot_spawns", []) as Array, "c4_lifeline_cache")
	_assert(int((archive_medicine.get("contents", {}) as Dictionary).get("meds_chemicals", 0)) == 1, "Bezpieczna trasa Archiwum musi dostarczać lekarstwo dla Leona.")
	_assert(int((c4_medicine.get("contents", {}) as Dictionary).get("meds_chemicals", 0)) == 1, "Bezpieczna trasa C-4 musi mieć zapas lekarstwa przed Leonem.")
	var leon := _record_by_id(gameplay.get("rescue_spawns", []) as Array, "rescue_leon")
	_assert(str(leon.get("definition_id", "")) == "leon_wrona", "rescue_leon musi używać aktywnej definicji Leon Wrona.")
	var heavy := _record_by_id(gameplay.get("heavy_object_spawns", []) as Array, "sunken_transformer")
	_assert(not heavy.is_empty(), "Salvage basin musi zawierać jeden ciężki obiekt.")
	var heavy_rewards := heavy.get("rewards", {}) as Dictionary
	_assert(
		heavy_rewards.size() == 2
		and int(heavy_rewards.get("scrap", 0)) == 10
		and int(heavy_rewards.get("tech_parts", 0)) == 2,
		"Ciężki obiekt musi publikować znane, dodatnie nagrody.",
	)
	_assert_optional_threat_clearance(gameplay)
	_assert_s_loop_route_replay(navigation)


func _assert_runtime_ids(nodes, property_name: String, expected: PackedStringArray, label: String) -> void:
	var actual := PackedStringArray()
	for node_value in nodes:
		if node_value is Object:
			actual.append(str((node_value as Object).get(property_name)))
	_assert(actual == expected, "Runtime %s musi utworzyć dokładne ID w kolejności manifestu: %s." % [label, ", ".join(expected)])


func _assert_optional_threat_clearance(gameplay: Dictionary) -> void:
	var devices := gameplay.get("fixed_device_spawns", []) as Array
	var map_current_zones := gameplay.get("current_zones", []) as Array
	for threat_value in gameplay.get("threat_spawns", []):
		if not threat_value is Dictionary:
			continue
		var threat := threat_value as Dictionary
		var threat_position := _vector(threat.get("position", []))
		for device_value in devices:
			if device_value is Dictionary:
				_assert(
					threat_position.distance_to(_vector((device_value as Dictionary).get("position", []))) >= 650.0,
					"Opcjonalny noise eel nie może znaleźć się bliżej niż 650 jednostek od celu kampanii.",
				)
		for current_value in map_current_zones:
			if current_value is Dictionary:
				_assert(
					not _rect((current_value as Dictionary).get("bounds", [])).has_point(threat_position),
					"Noise eel nie może leżeć wewnątrz authored prądu.",
				)


func _assert_s_loop_route_replay(closed_navigation) -> void:
	_assert_route_bidirectional(
		closed_navigation,
		[
			Vector2(11520, 800),
			Vector2(11040, 1600),
			Vector2(12000, 2100),
			Vector2(11520, 2360),
			Vector2(11520, 800),
		],
		"tutorial day 2",
	)
	_assert(
		not bool(closed_navigation.call("is_segment_clear", Vector2(11520, 2440), Vector2(11520, 3000))),
		"Zamknięte SC-01 musi blokować przejście do celu dnia 3.",
	)
	_assert(bool(_runtime.call("open_shortcut_for_attempt", "SC-01")), "Harness musi otworzyć SC-01 aktywną metodą runtime.")
	var tutorial_navigation = _runtime.call("navigation_snapshot")
	_assert_route_bidirectional(
		tutorial_navigation,
		[
			Vector2(11520, 800),
			Vector2(11040, 1600),
			Vector2(12000, 2100),
			Vector2(11520, 2440),
			Vector2(11520, 3000),
			Vector2(11520, 3300),
		],
		"tutorial day 3",
	)
	_assert_route_bidirectional(
		tutorial_navigation,
		[
			Vector2(11520, 3300),
			Vector2(10800, 2800),
			Vector2(7400, 2800),
			Vector2(6600, 4400),
			Vector2(6800, 5200),
			Vector2(6800, 7000),
			Vector2(12000, 7200),
			Vector2(13920, 7200),
			Vector2(14880, 7600),
		],
		"Archive i R3",
	)

	_assert(
		not bool(tutorial_navigation.call("is_segment_clear", Vector2(12520, 4640), Vector2(12520, 5760))),
		"Zamknięty central return musi blokować krótszy powrót.",
	)
	_assert(bool(_runtime.call("open_shortcut_for_attempt", "shortcut_central_return")), "Harness musi otworzyć central return aktywną metodą runtime.")
	var central_navigation = _runtime.call("navigation_snapshot")
	_assert_route_bidirectional(
		central_navigation,
		[
			Vector2(11520, 3300),
			Vector2(12200, 3600),
			Vector2(12520, 4640),
			Vector2(12520, 5760),
			Vector2(12400, 7000),
			Vector2(13920, 7200),
			Vector2(14880, 7600),
		],
		"central return po otwarciu",
	)

	_assert_route_bidirectional(
		central_navigation,
		[
			Vector2(14880, 7600),
			Vector2(15600, 8200),
			Vector2(16120, 8800),
			Vector2(16960, 8880),
			Vector2(18000, 8880),
			Vector2(19600, 8880),
			Vector2(20400, 8880),
			Vector2(20800, 9200),
			Vector2(20800, 9600),
			Vector2(19680, 9900),
			Vector2(20520, 10300),
		],
		"C-4 safe route",
	)
	_assert_route_bidirectional(
		central_navigation,
		[
			Vector2(14880, 7600),
			Vector2(15600, 8200),
			Vector2(16000, 9600),
			Vector2(16000, 10400),
			Vector2(16800, 10400),
			Vector2(17700, 10480),
			Vector2(18400, 10400),
			Vector2(19680, 10400),
			Vector2(19680, 9900),
			Vector2(20520, 10300),
		],
		"C-4 risk route",
	)
	_assert(
		not bool(central_navigation.call("is_segment_clear", Vector2(17760, 9200), Vector2(17760, 10160))),
		"Zamknięty właz serwisowy C-4 musi rozdzielać safe i risk route.",
	)
	_assert(bool(_runtime.call("open_shortcut_for_attempt", "shortcut_c4_service")), "Harness musi otworzyć właz serwisowy aktywną metodą runtime.")
	var service_navigation = _runtime.call("navigation_snapshot")
	_assert_route_bidirectional(
		service_navigation,
		[
			Vector2(17760, 9200),
			Vector2(17760, 9560),
			Vector2(17760, 9800),
			Vector2(17760, 10160),
		],
		"C-4 service po otwarciu",
	)
	_assert_route_bidirectional(
		service_navigation,
		[
			Vector2(18000, 10400),
			Vector2(18000, 11200),
			Vector2(18240, 11680),
			Vector2(16960, 11680),
			Vector2(15200, 11680),
		],
		"salvage basin",
	)


func _assert_route_bidirectional(navigation, points: Array, label: String) -> void:
	_assert_route_clear(navigation, points, "%s forward" % label)
	var reversed := points.duplicate()
	reversed.reverse()
	_assert_route_clear(navigation, reversed, "%s backout" % label)


func _assert_route_clear(navigation, points: Array, label: String) -> void:
	for index in range(points.size()):
		var point := points[index] as Vector2
		_assert(bool(navigation.call("is_position_clear", point)), "%s: waypoint %d nie ma clearance Nurka." % [label, index])
		if index == 0:
			continue
		_assert(
			bool(navigation.call("is_segment_clear", points[index - 1] as Vector2, point)),
			"%s: segment %d->%d przecina aktywną fizykę L05 albo zamkniętą bramkę." % [label, index - 1, index],
		)


func _record_by_id(records: Array, record_id: String) -> Dictionary:
	for record_value in records:
		if record_value is Dictionary and str((record_value as Dictionary).get("id", "")) == record_id:
			return record_value as Dictionary
	return {}


func _vector(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _rect(value) -> Rect2:
	if value is Rect2:
		return value
	if value is Array and (value as Array).size() == 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Rect2()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _finish() -> void:
	if _runtime != null and is_instance_valid(_runtime):
		root.remove_child(_runtime)
		_runtime.free()
	if _failed:
		quit(1)
		return
	print("S-loop gameplay runtime and bidirectional authored routes passed.")
	quit(0)
