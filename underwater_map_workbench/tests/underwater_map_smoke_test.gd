extends SceneTree

const CompilerScript := preload("res://underwater_map_workbench/runtime/UnderwaterMapSceneCompiler.gd")
const LocalRuntimeScript := preload("res://underwater_map_workbench/runtime/UnderwaterMapRuntime.gd")
const WorldStateScript := preload("res://scripts/data/UnderwaterWorldState.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")

const EXPECTED_SCHEMA_VERSION := 2
const EXPECTED_LAYER_IDS := [
	"L00", "L01", "L02", "L03", "L04", "L05", "L06", "L07", "L08", "L09", "L10",
]
const BLUEPRINT_GAMEPLAY_ARRAYS := {
	"connections": "connections",
	"current_zones": "current_zones",
	"threat_spawns": "threat_spawns",
	"heavy_object_spawns": "heavy_object_spawns",
	"rescue_spawns": "rescue_spawns",
	"buoy_spawns": "buoy_spawns",
	"shortcut_spawns": "shortcut_spawns",
	"fixed_device_spawns": "fixed_device_spawns",
	"obstacle_spawns": "obstacle_spawns",
	"decoration_spawns": "decoration_spawns",
}
const CAMPAIGN_SEED := 73_331

var _failed := false


func _initialize() -> void:
	var compiler = CompilerScript.new()
	var manifest := compiler.manifest_snapshot()
	_assert(not manifest.is_empty(), "Manifest mapy musi przejść walidację runtime.")
	if manifest.is_empty() or not _assert_manifest_contract(manifest):
		_finish()
		return

	var map_record: Dictionary = manifest["map"]
	var grid: Dictionary = map_record["grid"]
	var revision: Dictionary = manifest["revision"]
	var topology: Dictionary = manifest["topology"]
	var campaign: Dictionary = manifest["campaign"]
	var visual: Dictionary = manifest["visual"]
	var layer_records: Array = visual["layers"]
	var gameplay: Dictionary = manifest["gameplay"]
	var entry: Dictionary = manifest["entry"]
	var exit_record: Dictionary = manifest["exit"]
	var world_size := _vector(map_record["world_size"])
	var cell_size := _vector(grid["cell_size"])
	var navigation_cell_size := _vector(map_record["navigation_cell_size"])
	var grid_size := Vector2i(int(grid["columns"]), int(grid["rows"]))
	var entry_position := _vector(entry["position"])
	var exit_position := _vector(exit_record["position"])
	var entry_landmark_id := str(entry["landmark_id"])
	var canonical_entry_landmark_id := _canonical_landmark_id(manifest["landmarks"], entry_landmark_id)
	_assert(
		world_size.is_equal_approx(Vector2(grid_size) * cell_size),
		"Rozmiar świata musi wynikać z grid.columns, grid.rows i grid.cell_size.",
	)
	_assert(
		navigation_cell_size.x > 0.0 and navigation_cell_size.y > 0.0,
		"Manifest musi publikować dodatni rozmiar komórki nawigacji.",
	)

	var raw_manifest_sha := FileAccess.get_sha256(CompilerScript.MANIFEST_PATH).to_lower()
	_assert(not raw_manifest_sha.is_empty(), "Surowy manifest musi mieć SHA-256.")
	_assert(
		compiler.manifest_sha256() == raw_manifest_sha,
		"Compiler musi publikować SHA surowych bajtów bieżącego manifestu.",
	)
	_assert(
		compiler.generated_scene_is_current(),
		"UnderwaterMap.tscn musi być bieżącym deterministycznym wynikiem manifestu.",
	)
	_validate_manifest_fixtures_if_supported(compiler, manifest)

	var packed_map := ResourceLoader.load(
		CompilerScript.MAP_SCENE_PATH,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE,
	) as PackedScene
	_assert(packed_map != null, "Wygenerowana scena mapy musi się ładować.")
	if packed_map == null:
		_finish()
		return
	var map_root := packed_map.instantiate()
	var scene_gameplay_signature := str(map_root.get_meta("gameplay_signature", ""))
	var scene_presentation_fingerprint := str(map_root.get_meta("presentation_fingerprint", ""))
	_assert_scene_metadata(
		map_root,
		map_record,
		revision,
		campaign,
		topology,
		raw_manifest_sha,
		grid_size,
		cell_size,
		navigation_cell_size,
		world_size,
		scene_gameplay_signature,
		scene_presentation_fingerprint,
	)
	var generated_visual_layers := map_root.get_node_or_null("VisualLayers") as Node2D
	_assert(generated_visual_layers != null, "Wygenerowana scena musi zawierać VisualLayers.")
	if generated_visual_layers != null:
		_assert_visual_layers(generated_visual_layers, layer_records, visual, topology, "scena")
		_assert_visual_content_matches_manifest(generated_visual_layers, manifest, "scena")
	_assert_generated_scene_records(map_root, manifest)
	map_root.free()
	_assert(
		not ResourceLoader.exists("res://scenes/diving/UnderwaterMap.tscn"),
		"Stara kopia sceny poza workbench nie może istnieć.",
	)

	var world = WorldStateScript.new()
	world.setup(CAMPAIGN_SEED)
	var compile_errors: PackedStringArray = compiler.generate(world, CAMPAIGN_SEED)
	_assert(
		compile_errors.is_empty(),
		"Manifest musi kompilować się bez błędów: %s" % "; ".join(compile_errors),
	)
	if not compile_errors.is_empty() or world.blueprint == null:
		_finish()
		return
	var blueprint = world.blueprint
	_assert_blueprint_matches_manifest(
		blueprint,
		manifest,
		scene_gameplay_signature,
		world_size,
		entry_position,
		exit_position,
		canonical_entry_landmark_id,
	)

	var runtime = LocalRuntimeScript.new()
	runtime.name = "UnderwaterMapRuntimeSmoke"
	var expedition_setup = ExpeditionSetupScript.new()
	expedition_setup.day = 3
	expedition_setup.base_support_level = 1
	expedition_setup.tutorial_mode = bool(gameplay.get("tutorial_enabled", false))
	runtime.configure(world, entry_landmark_id, expedition_setup)
	root.add_child(runtime)
	_assert(runtime.world_size() == world_size, "Lokalny runtime musi zachować rozmiar manifestu.")
	_assert(runtime.start_position() == entry_position, "Lokalny runtime musi zachować start manifestu.")
	_assert(
		runtime.exit_line != null and runtime.exit_line.position == exit_position,
		"Lokalny runtime musi zachować punkt powrotu manifestu.",
	)
	var navigation = runtime.navigation_snapshot()
	_assert(navigation.is_valid(), "Lokalny runtime musi wystawić poprawną migawkę nawigacji.")
	var expected_navigation_size := Vector2i(
		ceili(world_size.x / navigation_cell_size.x),
		ceili(world_size.y / navigation_cell_size.y),
	)
	_assert(
		navigation.grid_size == expected_navigation_size,
		"Raster nawigacji musi wyprowadzać rozmiar z manifestu.",
	)
	var runtime_visual_layers := runtime.get_node_or_null("RuntimeDynamic/VisualLayers") as Node2D
	_assert(runtime_visual_layers != null, "Lokalny runtime musi zamontować VisualLayers.")
	if runtime_visual_layers != null:
		_assert_visual_layers(runtime_visual_layers, layer_records, visual, topology, "runtime")
		_assert_visual_content_matches_manifest(runtime_visual_layers, manifest, "runtime")
		_assert_reduced_motion_round_trip(runtime, runtime_visual_layers)

	_assert_root_integration_remains_loadable()
	root.remove_child(runtime)
	runtime.free()
	_finish()


func _assert_manifest_contract(manifest: Dictionary) -> bool:
	var schema_ok := int(manifest.get("schema_version", 0)) == EXPECTED_SCHEMA_VERSION
	_assert(schema_ok, "Manifest musi używać schema_version=2.")
	var revision_value = manifest.get("revision", null)
	var map_value = manifest.get("map", null)
	var regions_value = manifest.get("regions", null)
	var topology_value = manifest.get("topology", null)
	var campaign_value = manifest.get("campaign", null)
	var visual_value = manifest.get("visual", null)
	var gameplay_value = manifest.get("gameplay", null)
	var entry_value = manifest.get("entry", null)
	var exit_value = manifest.get("exit", null)
	var landmarks_value = manifest.get("landmarks", null)
	var depth_value = manifest.get("depth_profile", null)
	var root_types_ok := (
		revision_value is Dictionary
		and map_value is Dictionary
		and regions_value is Array
		and topology_value is Dictionary
		and campaign_value is Dictionary
		and visual_value is Dictionary
		and gameplay_value is Dictionary
		and entry_value is Dictionary
		and exit_value is Dictionary
		and landmarks_value is Array
		and depth_value is Array
	)
	_assert(root_types_ok, "Manifest v2 musi publikować kompletne rekordy root.")
	if not schema_ok or not root_types_ok:
		return false

	var revision := revision_value as Dictionary
	for revision_key in ["revision_id", "topology_revision", "presentation_revision"]:
		_assert(
			not str(revision.get(revision_key, "")).is_empty(),
			"Manifest revision.%s nie może być puste." % revision_key,
		)
	var map_record := map_value as Dictionary
	var grid_value = map_record.get("grid", null)
	_assert(grid_value is Dictionary, "Manifest map.grid musi być słownikiem.")
	if not grid_value is Dictionary:
		return false
	var grid := grid_value as Dictionary
	_assert(
		int(grid.get("columns", 0)) > 0 and int(grid.get("rows", 0)) > 0,
		"Wymiary logicznej siatki muszą być dodatnie i pochodzić z manifestu.",
	)
	_assert(_vector(grid.get("cell_size", [])).is_finite(), "map.grid.cell_size musi być wektorem.")
	_assert(_vector(map_record.get("world_size", [])).is_finite(), "map.world_size musi być wektorem.")

	var regions := regions_value as Array
	_assert(not regions.is_empty(), "Manifest musi definiować co najmniej jeden region.")
	var region_ids := {}
	for index in range(regions.size()):
		var region_value = regions[index]
		_assert(region_value is Dictionary, "regions[%d] musi być słownikiem." % index)
		if not region_value is Dictionary:
			continue
		var region_id := str((region_value as Dictionary).get("id", ""))
		_assert(not region_id.is_empty(), "Każdy region musi mieć ID.")
		_assert(not region_ids.has(region_id), "ID regionów muszą być unikalne.")
		region_ids[region_id] = true

	var landmarks := landmarks_value as Array
	var landmark_ids := {}
	for index in range(landmarks.size()):
		var landmark_value = landmarks[index]
		_assert(landmark_value is Dictionary, "landmarks[%d] musi być słownikiem." % index)
		if not landmark_value is Dictionary:
			continue
		var landmark := landmark_value as Dictionary
		var landmark_id := str(landmark.get("id", ""))
		_assert(not landmark_id.is_empty(), "Każdy landmark musi mieć ID.")
		_assert(not landmark_ids.has(landmark_id), "ID landmarków muszą być unikalne.")
		_assert(region_ids.has(str(landmark.get("region_id", ""))), "Landmark musi wskazywać region manifestu.")
		landmark_ids[landmark_id] = true
	var entry := entry_value as Dictionary
	var landmark_refs := _landmark_reference_map(landmarks)
	_assert(
		landmark_refs.has(str(entry.get("landmark_id", ""))),
		"Entry musi wskazywać landmark bieżącego manifestu.",
	)

	var topology := topology_value as Dictionary
	_assert(str(topology.get("mode", "")) == "open_world", "Topologia v2 musi używać mode=open_world.")
	_assert(
		topology.get("collision_source", null) is Dictionary,
		"Topologia musi jawnie publikować collision_source.",
	)
	_assert(
		topology.get("protected_corridors", null) is Array,
		"Topologia musi publikować protected_corridors jako tablicę.",
	)

	var visual := visual_value as Dictionary
	var layers_value = visual.get("layers", null)
	var assets_value = visual.get("assets", null)
	_assert(layers_value is Array, "visual.layers musi być tablicą.")
	_assert(assets_value is Array, "visual.assets musi być jedną globalną tablicą.")
	if not layers_value is Array or not assets_value is Array:
		return false
	var layers := layers_value as Array
	_assert(
		layers.size() == EXPECTED_LAYER_IDS.size(),
		"Stos prezentacyjny musi zawierać dokładnie korzenie L00-L10.",
	)
	for index in range(mini(layers.size(), EXPECTED_LAYER_IDS.size())):
		var layer_value = layers[index]
		_assert(layer_value is Dictionary, "visual.layers[%d] musi być słownikiem." % index)
		if not layer_value is Dictionary:
			continue
		var layer := layer_value as Dictionary
		_assert(
			str(layer.get("id", "")) == EXPECTED_LAYER_IDS[index],
			"visual.layers musi zachować kolejność L00-L10.",
		)
		for key in [
			"id", "role", "space", "z_index", "parallax_scale", "enabled", "reserved",
			"affordance_policy", "geometry_role",
		]:
			_assert(layer.has(key), "Warstwa %s nie publikuje pola %s." % [str(layer.get("id", "?")), key])
	_assert_layer_policy_records(layers, assets_value as Array, topology)
	return true


func _assert_layer_policy_records(layers: Array, assets: Array, topology: Dictionary) -> void:
	var authority_layer_id := str(topology.get("authority_layer", ""))
	var authority_layer := _record_by_id(layers, authority_layer_id)
	_assert(authority_layer_id == "L05", "Topologia musi wskazywać L05 jako authority collidera.")
	_assert(not authority_layer.is_empty(), "visual.layers musi zawierać authority_layer topologii.")
	if not authority_layer.is_empty():
		_assert(str(authority_layer.get("space", "")) == "world_locked", "L05 musi być world_locked.")
		_assert(str(authority_layer.get("role", "")) == "collider_authority", "L05 musi mieć rolę collider_authority.")
		_assert(
			str(authority_layer.get("geometry_role", "")) == "collider_authority",
			"L05 musi publikować geometry_role=collider_authority.",
		)
	var reserved_layer := _record_by_id(layers, "L10")
	_assert(not reserved_layer.is_empty(), "Stos musi zawierać L10.")
	if not reserved_layer.is_empty():
		_assert(not bool(reserved_layer.get("enabled", true)), "L10 musi być wyłączone.")
		_assert(bool(reserved_layer.get("reserved", false)), "L10 musi być zarezerwowane.")
	for index in range(assets.size()):
		var asset_value = assets[index]
		_assert(asset_value is Dictionary, "visual.assets[%d] musi być słownikiem." % index)
		if not asset_value is Dictionary:
			continue
		var layer_id := str((asset_value as Dictionary).get("layer_id", ""))
		_assert(EXPECTED_LAYER_IDS.has(layer_id), "Każdy asset musi wskazywać istniejący root L00-L10.")
		_assert(layer_id != "L10", "Zarezerwowane L10 nie może zawierać assetów.")


func _validate_manifest_fixtures_if_supported(compiler, manifest: Dictionary) -> void:
	_assert(compiler.has_method("validate_manifest_for_tests"), "Compiler musi publikować validate_manifest_for_tests.")
	_assert(compiler.has_method("compile_from_manifest_for_tests"), "Compiler musi publikować compile_from_manifest_for_tests.")
	if not compiler.has_method("validate_manifest_for_tests") or not compiler.has_method("compile_from_manifest_for_tests"):
		return
	_validate_exact_map_dimensions(compiler, manifest)
	_validate_manifest_owned_campaign_landmark(compiler, manifest)
	var baseline_compilation: Dictionary = {}
	if compiler.has_method("compile_from_manifest_for_tests"):
		var baseline_result = compiler.call("compile_from_manifest_for_tests", manifest.duplicate(true), CAMPAIGN_SEED)
		_assert(
			baseline_result is Dictionary,
			"compile_from_manifest_for_tests musi zwracać Dictionary.",
		)
		if baseline_result is Dictionary:
			baseline_compilation = baseline_result as Dictionary
			var baseline_errors: PackedStringArray = baseline_compilation.get("errors", PackedStringArray())
			_assert(
				baseline_errors.is_empty(),
				"Bieżący manifest musi kompilować się również in-memory: %s" % "; ".join(baseline_errors),
			)
	var fixture := manifest.duplicate(true)
	var fixture_landmarks: Array = fixture.get("landmarks", []).duplicate(true)
	if fixture_landmarks.is_empty() or not fixture_landmarks[0] is Dictionary:
		_assert(false, "Fixture count-free wymaga co najmniej jednego poprawnego rekordu źródłowego.")
		return
	var used_ids := {}
	for landmark_value in fixture_landmarks:
		if landmark_value is Dictionary:
			used_ids[str((landmark_value as Dictionary).get("id", ""))] = true
	var fixture_id := "__count_free_fixture_landmark__"
	while used_ids.has(fixture_id):
		fixture_id += "x"
	var extra_landmark := (fixture_landmarks[0] as Dictionary).duplicate(true)
	extra_landmark["id"] = fixture_id
	extra_landmark["display_name"] = "Count-free fixture"
	extra_landmark["short_name"] = "Fixture"
	fixture_landmarks.append(extra_landmark)
	fixture["landmarks"] = fixture_landmarks
	var fixture_result = compiler.call("validate_manifest_for_tests", fixture)
	_assert(
		typeof(fixture_result) == TYPE_PACKED_STRING_ARRAY,
		"validate_manifest_for_tests musi zwracać PackedStringArray.",
	)
	if typeof(fixture_result) == TYPE_PACKED_STRING_ARRAY:
		var fixture_errors: PackedStringArray = fixture_result
		_assert(
			fixture_errors.is_empty(),
			"Walidator in-memory nie może zamrażać liczby landmarków: %s" % "; ".join(fixture_errors),
		)
	if compiler.has_method("compile_from_manifest_for_tests"):
		var count_compilation = compiler.call("compile_from_manifest_for_tests", fixture, CAMPAIGN_SEED)
		_assert(count_compilation is Dictionary, "Count-free fixture musi zwrócić wynik kompilacji.")
		if count_compilation is Dictionary:
			var count_errors: PackedStringArray = count_compilation.get("errors", PackedStringArray())
			_assert(count_errors.is_empty(), "Count-free fixture musi kompilować się bez błędów: %s" % "; ".join(count_errors))
			var fixture_blueprint = count_compilation.get("blueprint", null)
			_assert(fixture_blueprint != null, "Count-free fixture musi zwrócić blueprint.")
			if fixture_blueprint != null:
				_assert_record_sequence(fixture_landmarks, fixture_blueprint.landmarks, "fixture.landmarks")
			_assert(
				str(count_compilation.get("map_gameplay_signature", ""))
				!= str(baseline_compilation.get("map_gameplay_signature", "")),
				"Dodanie landmarku musi zmienić gameplay signature.",
			)
			_assert(
				str(count_compilation.get("presentation_fingerprint", ""))
				!= str(baseline_compilation.get("presentation_fingerprint", "")),
				"Dodanie renderowanego znacznika landmarku musi zmienić presentation fingerprint.",
			)

		var alias_fixture := manifest.duplicate(true)
		var alias_landmarks: Array = alias_fixture["landmarks"]
		var source_entry_id := str((alias_fixture["entry"] as Dictionary).get("landmark_id", ""))
		var canonical_entry_id := _canonical_landmark_id(alias_landmarks, source_entry_id)
		var alias_target := _record_by_id(alias_landmarks, canonical_entry_id)
		_assert(not alias_target.is_empty(), "Alias fixture wymaga kanonicznego landmarku wejścia.")
		if not alias_target.is_empty():
			var entry_alias := "__entry_alias_fixture__"
			while _landmark_reference_map(alias_landmarks).has(entry_alias):
				entry_alias += "x"
			var aliases: Array = (alias_target.get("aliases", []) as Array).duplicate()
			aliases.append(entry_alias)
			alias_target["aliases"] = aliases
			var alias_entry: Dictionary = alias_fixture["entry"]
			alias_entry["landmark_id"] = entry_alias
			var alias_gameplay: Dictionary = alias_fixture["gameplay"]
			var alias_tutorial_route: Array = (alias_gameplay.get("tutorial_route", []) as Array).duplicate()
			var route_entry_index := alias_tutorial_route.find(source_entry_id)
			_assert(route_entry_index >= 0, "Alias fixture wymaga entry w tutorial_route.")
			if route_entry_index >= 0:
				alias_tutorial_route[route_entry_index] = entry_alias
				alias_gameplay["tutorial_route"] = alias_tutorial_route
			var alias_errors: PackedStringArray = compiler.call("validate_manifest_for_tests", alias_fixture)
			_assert(
				alias_errors.is_empty(),
				"Alias entry musi przechodzić walidację: %s" % "; ".join(alias_errors),
			)
			var alias_compilation = compiler.call("compile_from_manifest_for_tests", alias_fixture, CAMPAIGN_SEED)
			_assert(alias_compilation is Dictionary, "Alias fixture musi zwrócić wynik kompilacji.")
			if alias_compilation is Dictionary:
				var alias_compile_errors: PackedStringArray = alias_compilation.get("errors", PackedStringArray())
				_assert(
					alias_compile_errors.is_empty(),
					"Alias fixture musi kompilować się bez błędów: %s" % "; ".join(alias_compile_errors),
				)
				var alias_blueprint = alias_compilation.get("blueprint", null)
				_assert(alias_blueprint != null, "Alias fixture musi zwrócić blueprint.")
				if alias_blueprint != null:
					_assert(
						str(alias_blueprint.entry_landmark_id) == canonical_entry_id,
						"Blueprint musi canonicalizować alias entry do ID landmarku.",
					)

		var label_fixture := manifest.duplicate(true)
		var label_gameplay: Dictionary = label_fixture["gameplay"]
		var label_devices: Array = label_gameplay["fixed_device_spawns"]
		var first_device: Dictionary = label_devices[0]
		first_device["display_name"] = "%s fixture" % str(first_device.get("display_name", ""))
		var label_compilation = compiler.call("compile_from_manifest_for_tests", label_fixture, CAMPAIGN_SEED)
		_assert(label_compilation is Dictionary, "Label fixture musi zwrócić wynik kompilacji.")
		if label_compilation is Dictionary:
			var label_errors: PackedStringArray = label_compilation.get("errors", PackedStringArray())
			_assert(label_errors.is_empty(), "Label fixture musi przejść walidację: %s" % "; ".join(label_errors))
			_assert(
				str(label_compilation.get("map_gameplay_signature", ""))
				== str(baseline_compilation.get("map_gameplay_signature", "")),
				"Zmiana display_name nie może zmienić gameplay signature.",
			)
			_assert(
				str(label_compilation.get("presentation_fingerprint", ""))
				!= str(baseline_compilation.get("presentation_fingerprint", "")),
				"Zmiana display_name musi zmienić presentation fingerprint.",
			)

		var presentation_fixture := manifest.duplicate(true)
		var presentation_revision: Dictionary = presentation_fixture["revision"].duplicate(true)
		presentation_revision["presentation_revision"] = "%s-fixture" % str(presentation_revision["presentation_revision"])
		presentation_fixture["revision"] = presentation_revision
		var presentation_compilation = compiler.call(
			"compile_from_manifest_for_tests",
			presentation_fixture,
			CAMPAIGN_SEED,
		)
		_assert(presentation_compilation is Dictionary, "Presentation fixture musi zwrócić wynik kompilacji.")
		if presentation_compilation is Dictionary:
			var presentation_errors: PackedStringArray = presentation_compilation.get("errors", PackedStringArray())
			_assert(
				presentation_errors.is_empty(),
				"Presentation fixture musi kompilować się bez błędów: %s" % "; ".join(presentation_errors),
			)
			_assert(
				str(presentation_compilation.get("map_gameplay_signature", ""))
				== str(baseline_compilation.get("map_gameplay_signature", "")),
				"Zmiana presentation_revision nie może zmieniać gameplay signature.",
			)
			_assert(
				str(presentation_compilation.get("presentation_fingerprint", ""))
				!= str(baseline_compilation.get("presentation_fingerprint", "")),
				"Zmiana presentation_revision musi zmienić presentation fingerprint.",
			)


func _validate_exact_map_dimensions(compiler, manifest: Dictionary) -> void:
	for axis in ["columns", "rows"]:
		for delta in [-1, 1]:
			var grid_fixture := manifest.duplicate(true)
			var map_record: Dictionary = grid_fixture["map"]
			var grid: Dictionary = map_record["grid"]
			grid[axis] = int(grid[axis]) + delta
			_sync_fixture_world_size(map_record, grid)
			_assert_manifest_rejected(
				compiler,
				grid_fixture,
				"Spójny wewnętrznie grid ze zmianą %s o %+d nie może zastąpić kontraktu 12 x 12."
				% [axis, delta],
			)
	for component in [0, 1]:
		for delta in [-1.0, 1.0]:
			var cell_fixture := manifest.duplicate(true)
			var map_record: Dictionary = cell_fixture["map"]
			var grid: Dictionary = map_record["grid"]
			var cell_size: Array = (grid["cell_size"] as Array).duplicate()
			cell_size[component] = float(cell_size[component]) + delta
			grid["cell_size"] = cell_size
			_sync_fixture_world_size(map_record, grid)
			_assert_manifest_rejected(
				compiler,
				cell_fixture,
				"Spójny wewnętrznie zmieniony cell_size[%d] nie może zastąpić kontraktu 1920 x 1080."
				% component,
			)
	for component in [0, 1]:
		var world_fixture := manifest.duplicate(true)
		var map_record: Dictionary = world_fixture["map"]
		var world_size: Array = (map_record["world_size"] as Array).duplicate()
		world_size[component] = float(world_size[component]) + 1.0
		map_record["world_size"] = world_size
		_assert_manifest_rejected(
			compiler,
			world_fixture,
			"world_size musi dokładnie odpowiadać gridowi i kontraktowi 12 x 12.",
		)


func _validate_manifest_owned_campaign_landmark(compiler, manifest: Dictionary) -> void:
	var fixture := manifest.duplicate(true)
	var campaign: Dictionary = fixture.get("campaign", {})
	var stages: Array = campaign.get("stages", [])
	if stages.is_empty() or not stages[0] is Dictionary:
		_assert(false, "Fixture pozycji kampanii wymaga co najmniej jednego etapu.")
		return
	var stage := stages[0] as Dictionary
	var source_landmark_id := str(stage.get("landmark_id", ""))
	var landmarks: Array = fixture.get("landmarks", [])
	var source_landmark := _record_by_id(landmarks, source_landmark_id)
	if source_landmark.is_empty():
		_assert(false, "Fixture pozycji kampanii wymaga istniejącego landmarku etapu.")
		return
	var fixture_landmark_id := "__campaign_manifest_fixture__"
	while not _record_by_id(landmarks, fixture_landmark_id).is_empty():
		fixture_landmark_id += "x"
	var fixture_landmark := source_landmark.duplicate(true)
	fixture_landmark["id"] = fixture_landmark_id
	fixture_landmark["design_id"] = fixture_landmark_id
	fixture_landmark["display_name"] = "Manifest-owned campaign fixture"
	fixture_landmark["short_name"] = "Fixture"
	fixture_landmark["aliases"] = []
	landmarks.append(fixture_landmark)
	stage["landmark_id"] = fixture_landmark_id
	var stage_device_ids: Array = stage.get("fixed_device_ids", [])
	var gameplay: Dictionary = fixture.get("gameplay", {})
	var fixed_devices: Array = gameplay.get("fixed_device_spawns", [])
	for device_id_value in stage_device_ids:
		var device := _record_by_id(fixed_devices, str(device_id_value))
		if not device.is_empty():
			device["landmark_id"] = fixture_landmark_id
	var errors: PackedStringArray = compiler.call("validate_manifest_for_tests", fixture)
	_assert(
		errors.is_empty(),
		"Fizyczne przypisanie etapu kampanii musi pochodzić z manifestu: %s" % "; ".join(errors),
	)
	var compilation = compiler.call("compile_from_manifest_for_tests", fixture, CAMPAIGN_SEED)
	_assert(compilation is Dictionary, "Fixture pozycji kampanii musi zwrócić wynik kompilacji.")
	if not compilation is Dictionary:
		return
	var compile_errors: PackedStringArray = compilation.get("errors", PackedStringArray())
	_assert(compile_errors.is_empty(), "Fixture pozycji kampanii musi się kompilować: %s" % "; ".join(compile_errors))
	var blueprint = compilation.get("blueprint", null)
	_assert(blueprint != null, "Fixture pozycji kampanii musi zwrócić blueprint.")
	if blueprint == null:
		return
	_assert(not _record_by_id(blueprint.landmarks, fixture_landmark_id).is_empty(), "Blueprint musi przejąć landmark kampanii z manifestu.")
	for device_id_value in stage_device_ids:
		var device := _record_by_id(blueprint.fixed_device_spawns, str(device_id_value))
		_assert(
			str(device.get("landmark_id", "")) == fixture_landmark_id,
			"Blueprint musi przejąć przypisanie urządzenia kampanii z manifestu.",
		)


func _sync_fixture_world_size(map_record: Dictionary, grid: Dictionary) -> void:
	var cell_size: Array = grid["cell_size"]
	map_record["world_size"] = [
		float(grid["columns"]) * float(cell_size[0]),
		float(grid["rows"]) * float(cell_size[1]),
	]


func _assert_manifest_rejected(compiler, fixture: Dictionary, message: String) -> void:
	var result = compiler.call("validate_manifest_for_tests", fixture)
	_assert(typeof(result) == TYPE_PACKED_STRING_ARRAY, "Walidator fixture musi zwracać PackedStringArray.")
	if typeof(result) == TYPE_PACKED_STRING_ARRAY:
		_assert(not (result as PackedStringArray).is_empty(), message)


func _assert_scene_metadata(
	map_root: Node,
	map_record: Dictionary,
	revision: Dictionary,
	campaign: Dictionary,
	topology: Dictionary,
	raw_manifest_sha: String,
	grid_size: Vector2i,
	cell_size: Vector2,
	navigation_cell_size: Vector2,
	world_size: Vector2,
	gameplay_signature: String,
	presentation_fingerprint: String,
) -> void:
	_assert(
		str(map_root.get_meta("manifest_path", "")) == CompilerScript.MANIFEST_PATH,
		"Scena musi wskazywać jedyny manifest warsztatu.",
	)
	_assert(
		str(map_root.get_meta("manifest_sha256", "")).to_lower() == raw_manifest_sha,
		"Scena musi publikować SHA surowych bajtów manifestu.",
	)
	_assert(int(map_root.get_meta("schema_version", 0)) == EXPECTED_SCHEMA_VERSION, "Scena musi publikować schema v2.")
	_assert(
		int(map_root.get_meta("source_version", 0)) == int(map_record.get("source_version", 0)),
		"Scena musi wyprowadzać source_version z manifestu.",
	)
	_assert(
		_manifest_value_matches(revision, map_root.get_meta("revision", {})),
		"Scena musi publikować cały słownik revision 1:1.",
	)
	_assert(
		_manifest_value_matches(campaign, map_root.get_meta("campaign", {})),
		"Scena musi publikować cały strukturalny kontrakt kampanii 1:1.",
	)
	_assert(
		_manifest_value_matches(topology, map_root.get_meta("topology", {})),
		"Scena musi publikować cały słownik topology 1:1.",
	)
	_assert(map_root.get_meta("grid_size", Vector2i.ZERO) == grid_size, "Scena musi zachować grid manifestu.")
	_assert(map_root.get_meta("cell_size", Vector2.ZERO) == cell_size, "Scena musi zachować cell_size manifestu.")
	_assert(
		map_root.get_meta("navigation_cell_size", Vector2.ZERO) == navigation_cell_size,
		"Scena musi zachować navigation_cell_size manifestu.",
	)
	_assert(map_root.get_meta("world_size", Vector2.ZERO) == world_size, "Scena musi zachować world_size manifestu.")
	_assert(not gameplay_signature.is_empty(), "Scena musi publikować osobny gameplay_signature.")
	_assert(not presentation_fingerprint.is_empty(), "Scena musi publikować osobny presentation_fingerprint.")
	_assert(
		gameplay_signature != presentation_fingerprint,
		"Gameplay signature i presentation fingerprint muszą być osobnymi domenami podpisu.",
	)
	_assert(gameplay_signature != raw_manifest_sha, "Gameplay signature nie może być aliasem surowego SHA manifestu.")
	_assert(presentation_fingerprint != raw_manifest_sha, "Presentation fingerprint nie może być aliasem surowego SHA manifestu.")


func _assert_generated_scene_records(map_root: Node, manifest: Dictionary) -> void:
	var regions_root := map_root.get_node_or_null("ManifestRegions")
	_assert(regions_root != null, "Scena musi publikować techniczne ManifestRegions.")
	if regions_root != null:
		var source_regions: Array = manifest["regions"]
		var region_nodes := regions_root.get_children()
		_assert(
			region_nodes.size() == source_regions.size(),
			"ManifestRegions musi wyprowadzać liczbę regionów z manifestu.",
		)
		for index in range(mini(region_nodes.size(), source_regions.size())):
			var source_region: Dictionary = source_regions[index]
			var region_node: Node = region_nodes[index]
			_assert(
				str(region_node.get_meta("region_id", "")) == str(source_region.get("id", "")),
				"ManifestRegions musi zachować ID i kolejność regionów.",
			)
			for key in ["display_name", "bounds", "water_color", "accent_color"]:
				var region_meta_value: Variant = null
				if region_node.has_meta(key):
					region_meta_value = region_node.get_meta(key)
				_assert(
					region_node.has_meta(key) and _manifest_value_matches(source_region.get(key, null), region_meta_value),
					"ManifestRegions[%d].%s musi odpowiadać manifestowi." % [index, key],
				)

	var markers_root := map_root.get_node_or_null("ManifestMarkers")
	_assert(markers_root != null, "Scena musi publikować techniczne ManifestMarkers.")
	if markers_root == null:
		return
	var entry_node := markers_root.get_node_or_null("Entry") as Marker2D
	var exit_node := markers_root.get_node_or_null("Exit") as Marker2D
	_assert(entry_node != null and exit_node != null, "ManifestMarkers musi zawierać Entry i Exit.")
	if entry_node != null:
		_assert(entry_node.position == _vector(manifest["entry"]["position"]), "Marker Entry musi zachować pozycję manifestu.")
		_assert(
			str(entry_node.get_meta("object_id", "")) == str(manifest["entry"]["landmark_id"]),
			"Marker Entry musi zachować dynamiczne ID landmarku.",
		)
	if exit_node != null:
		_assert(exit_node.position == _vector(manifest["exit"]["position"]), "Marker Exit musi zachować pozycję manifestu.")

	var gameplay: Dictionary = manifest["gameplay"]
	var expected_collection_count := 0
	for collection_name in gameplay.keys():
		if collection_name in ["tutorial_enabled", "tutorial_route"] or not gameplay[collection_name] is Array:
			continue
		expected_collection_count += 1
		var collection_node := _direct_child_with_meta(markers_root, "collection", str(collection_name))
		_assert(collection_node != null, "ManifestMarkers musi zawierać kolekcję %s." % collection_name)
		if collection_node == null:
			continue
		var source_records: Array = gameplay[collection_name]
		var record_nodes := collection_node.get_children()
		_assert(
			record_nodes.size() == source_records.size(),
			"Kolekcja %s musi wyprowadzać liczbę rekordów z manifestu." % collection_name,
		)
		for index in range(mini(record_nodes.size(), source_records.size())):
			var source_record: Dictionary = source_records[index]
			var record_node: Node = record_nodes[index]
			_assert(
				str(record_node.get_meta("object_id", "")) == str(source_record.get("id", "")),
				"Kolekcja %s musi zachować ID i kolejność rekordów." % collection_name,
			)
			_assert(
				_manifest_value_matches(source_record, record_node.get_meta("source", {})),
				"Kolekcja %s[%d] musi zachować rekord źródłowy 1:1." % [collection_name, index],
			)
			if source_record.has("position"):
				_assert(
					record_node is Node2D and (record_node as Node2D).position == _vector(source_record["position"]),
					"Kolekcja %s[%d] musi zachować pozycję manifestu." % [collection_name, index],
				)
	var actual_collection_count := 0
	for child in markers_root.get_children():
		if child.has_meta("collection"):
			actual_collection_count += 1
	_assert(
		actual_collection_count == expected_collection_count,
		"ManifestMarkers nie może pomijać ani dodawać kolekcji gameplayowych.",
	)


func _assert_blueprint_matches_manifest(
	blueprint,
	manifest: Dictionary,
	scene_gameplay_signature: String,
	world_size: Vector2,
	entry_position: Vector2,
	exit_position: Vector2,
	entry_landmark_id: String,
) -> void:
	var map_record: Dictionary = manifest["map"]
	var gameplay: Dictionary = manifest["gameplay"]
	_assert(
		int(blueprint.map_source_version) == int(map_record.get("source_version", 0)),
		"Blueprint musi wyprowadzać source_version z manifestu.",
	)
	_assert(str(blueprint.map_id) == str(map_record.get("id", "")), "Blueprint musi wyprowadzać map.id z manifestu.")
	_assert(blueprint.world_size == world_size, "Blueprint musi wyprowadzać rozmiar świata z manifestu.")
	_assert(int(blueprint.chunk_size) == int(map_record.get("chunk_size", 0)), "Blueprint musi wyprowadzać chunk_size z manifestu.")
	_assert(
		str(blueprint.map_gameplay_signature) == scene_gameplay_signature,
		"Blueprint i scena muszą publikować ten sam gameplay signature.",
	)
	_assert(str(blueprint.entry_landmark_id) == entry_landmark_id, "Blueprint musi zachować dynamiczne ID wejścia.")
	_assert(blueprint.entry_position == entry_position, "Blueprint musi zachować pozycję wejścia.")
	_assert(blueprint.exit_position == exit_position, "Blueprint musi zachować pozycję wyjścia.")
	_assert_depth_profile(manifest["depth_profile"], blueprint.depth_profile_points)
	_assert_record_sequence(manifest["regions"], blueprint.regions, "regions")
	_assert_record_sequence(manifest["landmarks"], blueprint.landmarks, "landmarks")

	var expected_loot: Array = (gameplay.get("loot_spawns", []) as Array).duplicate(true)
	for pickup_value in gameplay.get("pickups", []):
		if not pickup_value is Dictionary:
			continue
		var pickup := (pickup_value as Dictionary).duplicate(true)
		pickup["spawn_kind"] = str(pickup.get("spawn_kind", "pickup"))
		expected_loot.append(pickup)
	_assert_record_sequence(expected_loot, blueprint.loot_spawns, "gameplay.loot_spawns+pickups")
	for manifest_key in BLUEPRINT_GAMEPLAY_ARRAYS:
		var blueprint_property := str(BLUEPRINT_GAMEPLAY_ARRAYS[manifest_key])
		_assert_record_sequence(
			gameplay.get(manifest_key, []),
			blueprint.get(blueprint_property),
			"gameplay.%s" % manifest_key,
		)
	for landmark_value in manifest["landmarks"]:
		if landmark_value is Dictionary:
			_assert(
				blueprint.landmark_lookup.has(str((landmark_value as Dictionary).get("id", ""))),
				"Blueprint index musi zawierać każdy landmark manifestu.",
			)
	for connection_value in gameplay.get("connections", []):
		if connection_value is Dictionary:
			_assert(
				blueprint.connection_lookup.has(str((connection_value as Dictionary).get("id", ""))),
				"Blueprint index musi zawierać każde połączenie manifestu.",
			)


func _assert_depth_profile(source_value, compiled: PackedVector2Array) -> void:
	_assert(source_value is Array, "depth_profile manifestu musi być tablicą.")
	if not source_value is Array:
		return
	var source := source_value as Array
	_assert(compiled.size() == source.size(), "Blueprint musi zachować liczbę punktów depth_profile z manifestu.")
	for index in range(mini(source.size(), compiled.size())):
		_assert(
			compiled[index] == _vector(source[index]),
			"Blueprint musi zachować depth_profile[%d] 1:1." % index,
		)


func _assert_record_sequence(source_value, compiled_value, label: String) -> void:
	_assert(source_value is Array, "%s w manifeście musi być tablicą." % label)
	_assert(compiled_value is Array, "%s w blueprint musi być tablicą." % label)
	if not source_value is Array or not compiled_value is Array:
		return
	var source := source_value as Array
	var compiled := compiled_value as Array
	_assert(
		compiled.size() == source.size(),
		"Blueprint musi wyprowadzać liczbę rekordów %s wyłącznie z manifestu." % label,
	)
	for index in range(mini(source.size(), compiled.size())):
		var source_value_at_index = source[index]
		var compiled_value_at_index = compiled[index]
		_assert(source_value_at_index is Dictionary, "%s[%d] manifestu musi być rekordem." % [label, index])
		_assert(compiled_value_at_index is Dictionary, "%s[%d] blueprint musi być rekordem." % [label, index])
		if not source_value_at_index is Dictionary or not compiled_value_at_index is Dictionary:
			continue
		var source_record := source_value_at_index as Dictionary
		var compiled_record := compiled_value_at_index as Dictionary
		_assert(
			str(compiled_record.get("id", "")) == str(source_record.get("id", "")),
			"%s[%d] musi zachować ID i kolejność manifestu." % [label, index],
		)
		_assert_manifest_fields_preserved(source_record, compiled_record, "%s[%d]" % [label, index])


func _assert_manifest_fields_preserved(source: Dictionary, compiled: Dictionary, label: String) -> void:
	for key in source.keys():
		_assert(compiled.has(key), "%s nie zachował pola manifestu %s." % [label, str(key)])
		if not compiled.has(key):
			continue
		_assert(
			_manifest_value_matches(source[key], compiled[key]),
			"%s.%s różni się od manifestu." % [label, str(key)],
		)


func _manifest_value_matches(source, compiled) -> bool:
	if source is Dictionary:
		if not compiled is Dictionary:
			return false
		var source_dictionary := source as Dictionary
		var compiled_dictionary := compiled as Dictionary
		for key in source_dictionary.keys():
			if not compiled_dictionary.has(key) or not _manifest_value_matches(source_dictionary[key], compiled_dictionary[key]):
				return false
		return true
	if source is Array:
		var source_array := source as Array
		if compiled is Vector2:
			return source_array.size() == 2 and (compiled as Vector2) == _vector(source_array)
		if compiled is Vector2i:
			return source_array.size() == 2 and (compiled as Vector2i) == Vector2i(int(source_array[0]), int(source_array[1]))
		if compiled is Rect2:
			return source_array.size() == 4 and (compiled as Rect2) == _rect(source_array)
		if compiled is PackedVector2Array:
			var packed := compiled as PackedVector2Array
			if packed.size() != source_array.size():
				return false
			for index in range(source_array.size()):
				if packed[index] != _vector(source_array[index]):
					return false
			return true
		if not compiled is Array:
			return false
		var compiled_array := compiled as Array
		if source_array.size() != compiled_array.size():
			return false
		for index in range(source_array.size()):
			if not _manifest_value_matches(source_array[index], compiled_array[index]):
				return false
		return true
	if source is String and compiled is StringName:
		return str(source) == str(compiled)
	if source is String and compiled is Color:
		return Color.from_string(
			"#%s" % str(source).trim_prefix("#"),
			Color.TRANSPARENT,
		).is_equal_approx(compiled as Color)
	if (source is int or source is float) and (compiled is int or compiled is float):
		return is_equal_approx(float(source), float(compiled))
	return source == compiled


func _assert_visual_layers(
	visual_layers: Node2D,
	layer_records: Array,
	visual: Dictionary,
	topology: Dictionary,
	owner_label: String,
) -> void:
	var children := visual_layers.get_children()
	_assert(
		children.size() == EXPECTED_LAYER_IDS.size(),
		"VisualLayers %s musi zawierać wyłącznie korzenie L00-L10." % owner_label,
	)
	for index in range(mini(children.size(), EXPECTED_LAYER_IDS.size())):
		var child := children[index]
		var layer: Dictionary = layer_records[index]
		var layer_id := str(layer.get("id", ""))
		_assert(child.name == layer_id, "VisualLayers %s musi zachować kolejność manifestu." % owner_label)
		_assert(layer_id == EXPECTED_LAYER_IDS[index], "Warstwy %s muszą zachować nazwy L00-L10." % owner_label)
		_assert_layer_node_matches_record(child, layer, owner_label)
	var authority_node := visual_layers.get_node_or_null(str(topology.get("authority_layer", "")))
	_assert(authority_node != null, "VisualLayers %s musi zawierać authority_layer collidera." % owner_label)
	if authority_node != null:
		_assert(not authority_node is Parallax2D, "Authority collidera w %s nie może używać paralaksy." % owner_label)
	var reserved_node := visual_layers.get_node_or_null("L10")
	_assert(reserved_node != null, "VisualLayers %s musi zawierać L10." % owner_label)
	if reserved_node != null:
		_assert(reserved_node.get_child_count() == 0, "L10 w %s musi pozostać puste." % owner_label)
		_assert(not bool(reserved_node.get_meta("enabled", true)), "L10 w %s musi być wyłączone." % owner_label)
		_assert(bool(reserved_node.get_meta("reserved", false)), "L10 w %s musi być zarezerwowane." % owner_label)
	for asset_value in visual.get("assets", []):
		if asset_value is Dictionary:
			_assert(
				str((asset_value as Dictionary).get("layer_id", "")) != "L10",
				"L10 nie może mieć assetu w %s." % owner_label,
			)
	_assert_visual_tree_has_no_collision_nodes(visual_layers, owner_label)


func _assert_visual_content_matches_manifest(
	visual_layers: Node2D,
	manifest: Dictionary,
	owner_label: String,
) -> void:
	var landmarks_root := visual_layers.get_node_or_null("L03/Landmarks")
	_assert(landmarks_root != null, "%s musi publikować L03/Landmarks." % owner_label)
	if landmarks_root != null:
		var source_landmarks: Array = manifest["landmarks"]
		var landmark_nodes := landmarks_root.get_children()
		_assert(
			landmark_nodes.size() == source_landmarks.size(),
			"%s musi wyprowadzać liczbę landmarków z manifestu." % owner_label,
		)
		for index in range(mini(landmark_nodes.size(), source_landmarks.size())):
			var source_landmark: Dictionary = source_landmarks[index]
			var landmark_node: Node = landmark_nodes[index]
			_assert(
				str(landmark_node.get_meta("landmark_id", "")) == str(source_landmark.get("id", "")),
				"%s musi zachować ID i kolejność landmarków." % owner_label,
			)
			_assert(
				str(landmark_node.get_meta("region_id", "")) == str(source_landmark.get("region_id", "")),
				"%s landmark musi zachować region_id." % owner_label,
			)
			_assert(
				landmark_node is Node2D and (landmark_node as Node2D).position == _vector(source_landmark.get("position", [])),
				"%s landmark musi zachować pozycję manifestu." % owner_label,
			)

	var expected_assets_by_layer := {}
	for layer_id in EXPECTED_LAYER_IDS:
		expected_assets_by_layer[layer_id] = []
	for asset_value in (manifest["visual"] as Dictionary).get("assets", []):
		if asset_value is Dictionary:
			var asset: Dictionary = asset_value
			(expected_assets_by_layer[str(asset.get("layer_id", ""))] as Array).append(asset)
	for layer_id in EXPECTED_LAYER_IDS:
		var layer_root := visual_layers.get_node_or_null(layer_id)
		if layer_root == null:
			continue
		var asset_nodes := []
		for child in layer_root.get_children():
			if child.has_meta("asset_id"):
				asset_nodes.append(child)
		var expected_assets: Array = expected_assets_by_layer[layer_id]
		_assert(
			asset_nodes.size() == expected_assets.size(),
			"%s/%s musi wyprowadzać liczbę assetów z globalnego visual.assets." % [owner_label, layer_id],
		)
		for index in range(mini(asset_nodes.size(), expected_assets.size())):
			var asset_node: Node = asset_nodes[index]
			var source_asset: Dictionary = expected_assets[index]
			_assert(
				str(asset_node.get_meta("asset_id", "")) == str(source_asset.get("id", "")),
				"%s/%s musi zachować ID i kolejność assetów." % [owner_label, layer_id],
			)
			_assert(
				_manifest_value_matches(source_asset, asset_node.get_meta("source", {})),
				"%s/%s asset musi zachować rekord source 1:1." % [owner_label, layer_id],
			)


func _assert_layer_node_matches_record(node: Node, layer: Dictionary, owner_label: String) -> void:
	var layer_id := str(layer.get("id", ""))
	var space := str(layer.get("space", ""))
	if space == "parallax":
		_assert(node is Parallax2D, "%s/%s musi być Parallax2D." % [owner_label, layer_id])
	elif space == "world_locked":
		_assert(node is Node2D and not node is Parallax2D, "%s/%s musi być world-locked Node2D." % [owner_label, layer_id])
	else:
		_assert(false, "%s/%s ma nieobsługiwane space=%s." % [owner_label, layer_id, space])
	for metadata_key: String in ["layer_id", "role", "space", "enabled", "reserved", "affordance_policy", "geometry_role"]:
		var manifest_key: String = "id" if metadata_key == "layer_id" else metadata_key
		var metadata_value: Variant = null
		if node.has_meta(metadata_key):
			metadata_value = node.get_meta(metadata_key)
		_assert(
			node.has_meta(metadata_key) and metadata_value == layer.get(manifest_key, null),
			"%s/%s metadata %s musi odpowiadać manifestowi." % [owner_label, layer_id, metadata_key],
		)
	var expected_scale := _vector(layer.get("parallax_scale", []))
	var parallax_scale_value: Variant = null
	if node.has_meta("parallax_scale"):
		parallax_scale_value = node.get_meta("parallax_scale")
	_assert(
		node.has_meta("parallax_scale") and parallax_scale_value == expected_scale,
		"%s/%s musi publikować normalną parallax_scale w metadata." % [owner_label, layer_id],
	)
	if node is Node2D:
		_assert((node as Node2D).z_index == int(layer.get("z_index", 0)), "%s/%s musi zachować z_index." % [owner_label, layer_id])
		_assert((node as Node2D).visible == bool(layer.get("enabled", true)), "%s/%s musi zachować enabled jako visible." % [owner_label, layer_id])
	if node is Parallax2D:
		_assert((node as Parallax2D).scroll_scale == expected_scale, "%s/%s musi używać manifestowej scroll_scale." % [owner_label, layer_id])


func _assert_visual_tree_has_no_collision_nodes(visual_layers: Node, owner_label: String) -> void:
	var nodes: Array[Node] = [visual_layers]
	nodes.append_array(visual_layers.find_children("*", "", true, false))
	for node in nodes:
		var node_label: String = str(node.get_path()) if node.is_inside_tree() else str(node.name)
		_assert(
			not (
				node is CollisionObject2D
				or node is Area2D
				or node is CollisionShape2D
				or node is CollisionPolygon2D
			),
			"VisualLayers %s nie może zawierać węzła fizyki %s (%s)." % [owner_label, node_label, node.get_class()],
		)


func _assert_reduced_motion_round_trip(runtime: Node, visual_layers: Node2D) -> void:
	var roots_before := _root_identity_snapshot(visual_layers)
	var parallax_nodes := _all_parallax_nodes(visual_layers)
	var normal_scales := {}
	for parallax in parallax_nodes:
		var normal_scale: Variant = null
		if parallax.has_meta("parallax_scale"):
			normal_scale = parallax.get_meta("parallax_scale")
		var parallax_label: String = str(parallax.get_path()) if parallax.is_inside_tree() else str(parallax.name)
		_assert(normal_scale is Vector2, "%s musi publikować normalną parallax_scale." % parallax_label)
		if normal_scale is Vector2:
			normal_scales[parallax.get_instance_id()] = normal_scale
	runtime.call("set_reduced_motion", true)
	_assert(
		_root_identity_snapshot(visual_layers) == roots_before,
		"reduced_motion nie może wymieniać ani przestawiać korzeni L00-L10.",
	)
	for parallax in parallax_nodes:
		_assert(parallax.scroll_scale == Vector2.ONE, "reduced_motion musi ustawić wszystkie Parallax2D na scroll_scale=ONE.")
	runtime.call("set_reduced_motion", false)
	_assert(
		_root_identity_snapshot(visual_layers) == roots_before,
		"Wyłączenie reduced_motion nie może wymieniać ani przestawiać korzeni L00-L10.",
	)
	for parallax in parallax_nodes:
		var expected_scale: Vector2 = normal_scales.get(parallax.get_instance_id(), Vector2(INF, INF))
		_assert(
			parallax.scroll_scale == expected_scale,
			"Wyłączenie reduced_motion musi odtworzyć normalną skalę z metadata.",
		)


func _root_identity_snapshot(visual_layers: Node2D) -> Array:
	var snapshot := []
	for child in visual_layers.get_children():
		snapshot.append({"name": str(child.name), "instance_id": child.get_instance_id()})
	return snapshot


func _all_parallax_nodes(visual_layers: Node2D) -> Array[Parallax2D]:
	var result: Array[Parallax2D] = []
	var nodes: Array[Node] = [visual_layers]
	nodes.append_array(visual_layers.find_children("*", "", true, false))
	for node in nodes:
		if node is Parallax2D:
			result.append(node as Parallax2D)
	return result


func _assert_root_integration_remains_loadable() -> void:
	var diver_scene := ResourceLoader.load("res://scenes/diving/Diver.tscn") as PackedScene
	_assert(diver_scene != null, "Rootowa scena nurka musi nadal się ładować.")
	if diver_scene != null:
		var diver := diver_scene.instantiate()
		_assert(diver.get_node_or_null("Camera2D") != null, "Scena nurka musi zachować kamerę.")
		diver.free()
	var dive_scene := ResourceLoader.load("res://scenes/diving/DiveScene.tscn") as PackedScene
	_assert(dive_scene != null, "Rootowy DiveScene musi nadal ładować integrację nurkowania.")
	if dive_scene != null:
		var dive_root := dive_scene.instantiate()
		var world_node := dive_root.get_node_or_null("World")
		_assert(world_node != null and dive_root.get_node_or_null("Diver") != null, "DiveScene musi zachować World i Diver.")
		if world_node != null:
			_assert(world_node.get_script() == LocalRuntimeScript, "DiveScene.World musi używać lokalnego UnderwaterMapRuntime.")
		dive_root.free()


func _record_by_id(records: Array, record_id: String) -> Dictionary:
	for value in records:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == record_id:
			return value as Dictionary
	return {}


func _landmark_reference_map(landmarks: Array) -> Dictionary:
	var refs := {}
	for landmark_value in landmarks:
		if not landmark_value is Dictionary:
			continue
		var landmark := landmark_value as Dictionary
		var landmark_id := str(landmark.get("id", "")).strip_edges()
		if not landmark_id.is_empty():
			refs[landmark_id] = landmark_id
	for landmark_value in landmarks:
		if not landmark_value is Dictionary:
			continue
		var landmark := landmark_value as Dictionary
		var landmark_id := str(landmark.get("id", "")).strip_edges()
		var aliases_value = landmark.get("aliases", [])
		if landmark_id.is_empty() or not aliases_value is Array:
			continue
		for alias_value in aliases_value as Array:
			if not alias_value is String:
				continue
			var alias := str(alias_value).strip_edges()
			if not alias.is_empty() and not refs.has(alias):
				refs[alias] = landmark_id
	return refs


func _canonical_landmark_id(landmarks: Array, landmark_ref: String) -> String:
	return str(_landmark_reference_map(landmarks).get(landmark_ref, ""))


func _direct_child_with_meta(parent: Node, meta_key: String, expected_value: String) -> Node:
	for child in parent.get_children():
		if str(child.get_meta(meta_key, "")) == expected_value:
			return child
	return null


func _vector(value) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2(INF, INF)
	return Vector2(float(value[0]), float(value[1]))


func _rect(value) -> Rect2:
	if not value is Array or (value as Array).size() != 4:
		return Rect2(Vector2(INF, INF), Vector2(INF, INF))
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Underwater map smoke test failed: " + message)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("Underwater map smoke test passed: schema-v2 manifest, generated scene, blueprint and local runtime parity.")
	quit(0)
