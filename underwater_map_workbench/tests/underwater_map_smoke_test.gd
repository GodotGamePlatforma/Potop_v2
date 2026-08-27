extends SceneTree

const CompilerScript := preload("res://underwater_map_workbench/runtime/UnderwaterMapSceneCompiler.gd")
const LocalRuntimeScript := preload("res://underwater_map_workbench/runtime/UnderwaterMapRuntime.gd")
const VisualSurveyPlanScript := preload("res://underwater_map_workbench/runtime/UnderwaterMapVisualSurveyPlan.gd")
const WorldStateScript := preload("res://scripts/data/UnderwaterWorldState.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")

const EXPECTED_SCHEMA_VERSION := 6
const EXPECTED_LAYER_IDS := [
	"L00", "L01", "L02", "L03", "L04", "L05", "L06", "L07", "L08", "L09", "L10",
]
const NONBLOCKING_TEXTURE_LAYER_IDS := ["L01", "L02"]
const GROUND_ANCHORED_BACKDROP_LAYER_IDS := ["L01", "L02"]
const NONBLOCKING_BACKDROP_AFFORDANCE := "nonblocking_backdrop"
const STREAMED_BACKDROP_CONTRACT := "camera_windowed_texture_v1"
const PORTAL_BACKDROP_CLEARANCE_CONTRACT := "raster_boundary_opening_clearance_v1"
const PORTAL_BACKDROP_CLEARANCE_HOST_LAYER_ID := "L04"
const PORTAL_BACKDROP_CLEARANCE_OCCLUDED_LAYER_IDS := ["L01", "L02"]
const PORTAL_BACKDROP_CLEARANCE_NORMAL_CORE_CELLS := 5
const PORTAL_BACKDROP_CLEARANCE_TANGENT_PADDING_CELLS := 1
const PORTAL_BACKDROP_CLEARANCE_FEATHER_CELLS := 2
const NO_BLOCKING_AFFORDANCE_POLICY := "no_visual_blockage_in_protected_water"
const OPEN_WATER_BACKDROP_AFFORDANCE_POLICY := "nonblocking_backdrop_may_overlap_open_water"
const COMPOSITION_PROXY_KIND := "composition_proxy"
const BACKDROP_MIN_OPAQUE_SHARE := 0.95
const BACKDROP_MAX_PARTIAL_CANVAS_SHARE := 0.03
const BACKDROP_MAX_LOW_ALPHA_CANVAS_SHARE := 0.0025
const BACKDROP_MIN_BOTTOM_OPAQUE_SHARE := 0.01
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
const L05_TOPOLOGY_MODE := "l05_mask_v1"
const L05_SOURCE_FORMAT := "l05_owned_rect_ops_v2"
const L05_PIXEL_SIZE := Vector2i(576, 324)
const L05_CELL_SIZE := Vector2(40.0, 40.0)
const L05_SURFACE_DETAIL_MASK_PATH := "res://underwater_map_workbench/assets/generated/l05/surface_detail_mask.png"
const STRUCTURE_PACKAGE_REFERENCE_FORMAT := "structure_package_v1"
const STRUCTURE_PACKAGE_FORMAT := "enterable_structure_package_v1"
const STRUCTURE_REGISTRY_PRIVATE_FIELDS := [
	"template_id", "size", "topology_digest", "partition_digest", "sockets", "runtime",
	"controller_script", "package_path", "package_sha256", "local_topology_digest",
	"collision_operations", "structure_scene_path",
]
const WORLD_COLLISION_OWNER_ID := "world"
const OPEN_WATER_OWNER_INDEX := 0
const WORLD_OWNER_INDEX := 1

var _failed := false


func _initialize() -> void:
	var raw_manifest := _load_json_resource(CompilerScript.MANIFEST_PATH, "surowy manifest mapy")
	_assert(not raw_manifest.is_empty(), "Surowy map_manifest.json musi być poprawnym obiektem JSON.")
	if raw_manifest.is_empty():
		_finish()
		return
	var compiler = CompilerScript.new()
	var manifest := compiler.manifest_snapshot()
	_assert(not manifest.is_empty(), "Rozwinięty snapshot manifestu mapy musi przejść walidację runtime.")
	_assert_raw_structure_registry(compiler, raw_manifest, manifest)
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
	_assert_source_dependencies(compiler, manifest)
	var navigation_base: Dictionary = compiler.navigation_base_raster()
	_assert_l05_navigation_base(navigation_base, topology, manifest)
	_validate_manifest_fixtures_if_supported(compiler, manifest)
	_assert_streamed_backdrops_are_scene_stubs(manifest)

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
		_assert_portal_backdrop_clearances(
			generated_visual_layers,
			manifest,
			navigation_base,
			"scena",
		)
	_assert_structure_roots(
		map_root.get_node_or_null("StructureRoots"),
		manifest,
		navigation_base,
		"scena",
	)
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
	_assert_archive_campaign_is_global(blueprint, manifest)

	var runtime = LocalRuntimeScript.new()
	runtime.name = "UnderwaterMapRuntimeSmoke"
	var expedition_setup = ExpeditionSetupScript.new()
	expedition_setup.day = 4
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
	var runtime_dynamic := runtime.get_node_or_null("RuntimeDynamic")
	var runtime_archive_terminal := _direct_child_with_property_value(
		runtime_dynamic,
		"persistent_id",
		"archive_terminal",
	) if runtime_dynamic != null else null
	var compiled_archive_terminal := _record_by_id(blueprint.fixed_device_spawns, "archive_terminal")
	_assert(runtime_archive_terminal is Node2D, "Runtime musi utworzyć globalny archive_terminal.")
	if runtime_archive_terminal is Node2D and not compiled_archive_terminal.is_empty():
		_assert(
			(runtime_archive_terminal as Node2D).position == _vector(compiled_archive_terminal.get("position", [])),
			"Runtime archive_terminal musi wyprowadzać pozycję z bieżącego blueprintu.",
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
	_assert(runtime.collision_segment_count() > 0, "Runtime musi zbudować fizyczne segmenty z authority L05.")
	var runtime_visual_layers := runtime.get_node_or_null("RuntimeDynamic/VisualLayers") as Node2D
	_assert(runtime_visual_layers != null, "Lokalny runtime musi zamontować VisualLayers.")
	if runtime_visual_layers != null:
		_assert_visual_layers(runtime_visual_layers, layer_records, visual, topology, "runtime")
		_assert_visual_content_matches_manifest(runtime_visual_layers, manifest, "runtime")
		_assert_portal_backdrop_clearances(
			runtime_visual_layers,
			manifest,
			navigation_base,
			"runtime",
		)
		_assert_reduced_motion_round_trip(runtime, runtime_visual_layers)
	_assert_runtime_structure_partition(runtime, manifest, navigation_base)

	root.remove_child(runtime)
	runtime.free()
	_finish()


func _assert_raw_structure_registry(
	compiler,
	raw_manifest: Dictionary,
	resolved_manifest: Dictionary,
) -> void:
	_assert(
		int(raw_manifest.get("schema_version", 0)) == EXPECTED_SCHEMA_VERSION,
		"Surowy map_manifest.json musi używać schema_version=6.",
	)
	var structures_value = raw_manifest.get("structures", null)
	_assert(structures_value is Dictionary, "Surowy schema v6 wymaga registry structures.")
	if not structures_value is Dictionary:
		return
	var registry := structures_value as Dictionary
	_assert_exact_dictionary_keys(registry, ["instances"], "surowy structures registry")
	var instances_value = registry.get("instances", null)
	_assert(instances_value is Array, "Surowy structures.instances musi być tablicą registry.")
	if not instances_value is Array:
		return
	var resolved_structures := resolved_manifest.get("structures", {}) as Dictionary
	_assert_exact_dictionary_keys(
		resolved_structures,
		["templates", "instances"],
		"rozwinięty compiler.manifest_snapshot().structures",
	)
	var resolved_instances := resolved_structures.get("instances", []) as Array
	_assert(
		resolved_instances.size() == (instances_value as Array).size(),
		"Rozwinięty snapshot musi zachować liczność registry struktur.",
	)
	for index in range((instances_value as Array).size()):
		var instance_value = (instances_value as Array)[index]
		_assert(instance_value is Dictionary, "Surowy structures.instances[%d] musi być obiektem." % index)
		if not instance_value is Dictionary:
			continue
		var registry_instance := instance_value as Dictionary
		var label := "surowy structures.instances[%d]" % index
		_assert_required_and_optional_dictionary_keys(
			registry_instance,
			["id", "origin", "enabled", "package"],
			["landmark_id"],
			label,
		)
		for private_field in STRUCTURE_REGISTRY_PRIVATE_FIELDS:
			_assert(
				not registry_instance.has(private_field),
				"%s nie może publikować prywatnego pola rozwiniętego %s."
				% [label, private_field],
			)
		var structure_id := str(registry_instance.get("id", ""))
		var package_reference_value = registry_instance.get("package", null)
		_assert(package_reference_value is Dictionary, "%s.package musi być obiektem." % label)
		if not package_reference_value is Dictionary:
			continue
		var package_reference := package_reference_value as Dictionary
		_assert_exact_dictionary_keys(package_reference, ["format", "path", "sha256"], "%s.package" % label)
		_assert(
			str(package_reference.get("format", "")) == STRUCTURE_PACKAGE_REFERENCE_FORMAT,
			"%s.package.format musi mieć wartość %s."
			% [label, STRUCTURE_PACKAGE_REFERENCE_FORMAT],
		)
		var package_path := str(package_reference.get("path", ""))
		var expected_package_path := "structures/%s/structure_manifest.json" % structure_id
		_assert(package_path == expected_package_path, "%s.package.path musi być kanoniczne." % label)
		var package_resource_path := "res://underwater_map_workbench/%s" % package_path
		_assert(FileAccess.file_exists(package_resource_path), "Registry wskazuje brakujący pakiet %s." % package_path)
		var declared_sha := str(package_reference.get("sha256", ""))
		var actual_sha := FileAccess.get_sha256(package_resource_path).to_lower()
		_assert(
			declared_sha.length() == 64
			and declared_sha == declared_sha.to_lower()
			and declared_sha == actual_sha,
			"%s.package.sha256 musi odpowiadać dokładnym bajtom pakietu." % label,
		)
		var package := _load_json_resource(package_resource_path, "pakiet struktury %s" % structure_id)
		var resolved_instance := _record_by_id(resolved_instances, structure_id)
		_assert(not resolved_instance.is_empty(), "Snapshot musi rozwinąć pakiet %s." % structure_id)
		_assert_structure_package_authority(
			package,
			registry_instance,
			resolved_instance,
			package_path,
			actual_sha,
		)

	_assert(
		compiler.has_method("validate_manifest_for_tests"),
		"Compiler musi publikować walidator fixture registry.",
	)
	if compiler.has_method("validate_manifest_for_tests") and not (instances_value as Array).is_empty():
		for private_field in STRUCTURE_REGISTRY_PRIVATE_FIELDS:
			var fixture := raw_manifest.duplicate(true)
			var fixture_instances := ((fixture.get("structures", {}) as Dictionary).get("instances", []) as Array)
			if fixture_instances.is_empty() or not fixture_instances[0] is Dictionary:
				break
			(fixture_instances[0] as Dictionary)[private_field] = true
			var errors: PackedStringArray = compiler.call("validate_manifest_for_tests", fixture)
			_assert(
				not errors.is_empty(),
				"Schema v6 musi odrzucać prywatne pole registry %s." % private_field,
			)


func _assert_structure_package_authority(
	package: Dictionary,
	registry_instance: Dictionary,
	resolved_instance: Dictionary,
	package_path: String,
	package_sha: String,
) -> void:
	var structure_id := str(registry_instance.get("id", ""))
	_assert(str(package.get("format", "")) == STRUCTURE_PACKAGE_FORMAT, "Pakiet %s ma niepoprawny format." % structure_id)
	_assert(
		str(resolved_instance.get("package_path", "")) == package_path
		and str(resolved_instance.get("package_sha256", "")) == package_sha,
		"Rozwinięty snapshot %s musi zachować ścieżkę i SHA registry." % structure_id,
	)
	_assert(not resolved_instance.has("package"), "Rozwinięta instancja %s nie może zachować surowego package ref." % structure_id)
	var collision_value = package.get("collision", null)
	_assert(collision_value is Dictionary, "Pakiet %s musi publikować lokalną kolizję." % structure_id)
	if not collision_value is Dictionary:
		return
	var collision := collision_value as Dictionary
	_assert_exact_dictionary_keys(
		collision,
		["format", "base", "pixel_size", "world_units_per_pixel", "operations"],
		"pakiet %s collision" % structure_id,
	)
	_assert(str(collision.get("format", "")) == "l05_structure_rect_ops_v1", "Pakiet %s ma niepoprawny lokalny format kolizji." % structure_id)
	_assert(str(collision.get("base", "")) == "open_water", "Pakiet %s musi zaczynać lokalnie od open_water." % structure_id)
	var pixel_size := Vector2i(_vector(collision.get("pixel_size", [])))
	_assert(pixel_size.x > 0 and pixel_size.y > 0, "Pakiet %s musi publikować dodatni lokalny pixel_size." % structure_id)
	_assert(_vector(collision.get("world_units_per_pixel", [])) == L05_CELL_SIZE, "Pakiet %s musi mapować lokalny piksel na 40 x 40." % structure_id)
	var operations_value = collision.get("operations", null)
	_assert(operations_value is Array and not (operations_value as Array).is_empty(), "Pakiet %s musi publikować lokalne operations." % structure_id)
	if not operations_value is Array:
		return
	var operation_ids := {}
	for operation_index in range((operations_value as Array).size()):
		var operation_value = (operations_value as Array)[operation_index]
		_assert(operation_value is Dictionary, "Pakiet %s collision.operations[%d] musi być obiektem." % [structure_id, operation_index])
		if not operation_value is Dictionary:
			continue
		var operation := operation_value as Dictionary
		_assert_exact_dictionary_keys(operation, ["id", "op", "rect_px"], "pakiet %s collision.operations[%d]" % [structure_id, operation_index])
		_assert(not operation.has("space") and not operation.has("structure_id"), "Pakiet %s może publikować wyłącznie operacje lokalne." % structure_id)
		var operation_id := str(operation.get("id", ""))
		_assert(not operation_id.is_empty() and not operation_ids.has(operation_id), "Lokalne operation IDs pakietu %s muszą być unikalne." % structure_id)
		operation_ids[operation_id] = true
		_assert(str(operation.get("op", "")) in ["solid_rect", "open_rect"], "Pakiet %s ma niepoprawny lokalny op." % structure_id)
		var rect := operation.get("rect_px", []) as Array
		_assert(
			rect.size() == 4
			and int(rect[0]) >= 0 and int(rect[1]) >= 0
			and int(rect[2]) > 0 and int(rect[3]) > 0
			and int(rect[0]) + int(rect[2]) <= pixel_size.x
			and int(rect[1]) + int(rect[3]) <= pixel_size.y,
			"Pakiet %s ma operację poza lokalnym rastrem." % structure_id,
		)
	var resolved_operations := resolved_instance.get("collision_operations", []) as Array
	_assert(resolved_operations.size() == (operations_value as Array).size(), "Snapshot %s musi rozwinąć wszystkie lokalne operacje." % structure_id)
	for resolved_operation_value in resolved_operations:
		var resolved_operation := resolved_operation_value as Dictionary
		_assert_exact_dictionary_keys(
			resolved_operation,
			["id", "op", "space", "structure_id", "rect_px"],
			"snapshot %s collision operation" % structure_id,
		)
		_assert(
			str(resolved_operation.get("space", "")) == "structure_local_px"
			and str(resolved_operation.get("structure_id", "")) == structure_id,
			"Snapshot %s może rozwijać package collision wyłącznie jako structure_local_px." % structure_id,
		)
	var generated_root := "res://underwater_map_workbench/structures/%s/generated" % structure_id
	for generated_name in [
		"solid_mask_native.png", "open_water_mask_native.png", "boundary_mask_native.png",
		"guide_native.png", "surface_detail_mask_local.png", "structure.tscn",
	]:
		_assert(
			FileAccess.file_exists("%s/%s" % [generated_root, generated_name]),
			"Pakiet %s wymaga pochodnej structures/%s/generated/%s."
			% [structure_id, structure_id, generated_name],
		)
	_assert(
		str(resolved_instance.get("structure_scene_path", "")) == "%s/structure.tscn" % generated_root,
		"Snapshot %s musi wskazywać package-local generated/structure.tscn." % structure_id,
	)


func _assert_manifest_contract(manifest: Dictionary) -> bool:
	var schema_ok := int(manifest.get("schema_version", 0)) == EXPECTED_SCHEMA_VERSION
	_assert(schema_ok, "Rozwinięty manifest musi używać schema_version=6.")
	var revision_value = manifest.get("revision", null)
	var map_value = manifest.get("map", null)
	var regions_value = manifest.get("regions", null)
	var topology_value = manifest.get("topology", null)
	var campaign_value = manifest.get("campaign", null)
	var visual_value = manifest.get("visual", null)
	var structures_value = manifest.get("structures", null)
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
		and structures_value is Dictionary
		and gameplay_value is Dictionary
		and entry_value is Dictionary
		and exit_value is Dictionary
		and landmarks_value is Array
		and depth_value is Array
	)
	_assert(root_types_ok, "Rozwinięty manifest v6 musi publikować kompletne rekordy root, w tym structures.")
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
	_assert(
		str(topology.get("mode", "")) in ["open_world", L05_TOPOLOGY_MODE],
		"Topologia v6 musi używać open_world albo edytowalnego l05_mask_v1.",
	)
	_assert(
		topology.get("collision_source", null) is Dictionary,
		"Topologia musi jawnie publikować collision_source.",
	)
	_assert(
		topology.get("protected_corridors", null) is Array,
		"Topologia musi publikować protected_corridors jako tablicę.",
	)
	if str(topology.get("mode", "")) == L05_TOPOLOGY_MODE:
		var collision: Dictionary = topology.get("collision_source", {})
		_assert(str(collision.get("format", "")) == L05_SOURCE_FORMAT, "L05 musi używać l05_owned_rect_ops_v2.")
		_assert(_vector(collision.get("pixel_size", [])) == Vector2(L05_PIXEL_SIZE), "L05 musi mieć raster 576 x 324.")
		_assert(_vector(collision.get("world_units_per_pixel", [])) == L05_CELL_SIZE, "L05 musi mapować piksel na 40 x 40 jednostek.")
		_assert(
			str(collision.get("canonical_digest", "")).begins_with("topology-v1:"),
			"L05 musi publikować kanoniczny digest geometrii.",
		)
		_assert(
			not str(collision.get("partition_digest", "")).is_empty(),
			"L05 v2 musi publikować partition_digest właścicieli kolizji.",
		)

	_assert_structure_manifest_contract(
		structures_value as Dictionary,
		manifest,
		map_record,
		topology,
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
			"affordance_policy", "geometry_role", "rgb_modulate",
		]:
			_assert(layer.has(key), "Warstwa %s nie publikuje pola %s." % [str(layer.get("id", "?")), key])
	_assert_layer_policy_records(layers, assets_value as Array, topology, manifest)
	return true


func _assert_structure_manifest_contract(
	structures: Dictionary,
	manifest: Dictionary,
	map_record: Dictionary,
	topology: Dictionary,
) -> void:
	_assert_exact_dictionary_keys(structures, ["templates", "instances"], "structures")
	var templates_value = structures.get("templates", null)
	var instances_value = structures.get("instances", null)
	_assert(templates_value is Array, "structures.templates musi być tablicą.")
	_assert(instances_value is Array, "structures.instances musi być tablicą.")
	if not templates_value is Array or not instances_value is Array:
		return
	var templates := templates_value as Array
	var instances := instances_value as Array
	_assert(not templates.is_empty(), "Rozwinięty schema v6 musi publikować co najmniej jeden template struktury.")
	_assert(not instances.is_empty(), "Rozwinięty schema v6 musi publikować co najmniej jedną instancję struktury.")
	var template_ids := {}
	for index in range(templates.size()):
		var template_value = templates[index]
		_assert(template_value is Dictionary, "structures.templates[%d] musi być słownikiem." % index)
		if not template_value is Dictionary:
			continue
		var template := template_value as Dictionary
		_assert_exact_dictionary_keys(
			template,
			["id", "kind", "interior_layer_id", "collider_layer_id", "allowed_socket_kinds"],
			"structures.templates[%d]" % index,
		)
		var template_id := str(template.get("id", ""))
		_assert(not template_id.is_empty(), "Template struktury musi mieć ID.")
		_assert(not template_ids.has(template_id), "ID template'ów struktur muszą być unikalne.")
		template_ids[template_id] = template
		_assert(not str(template.get("kind", "")).is_empty(), "Template %s musi mieć kind." % template_id)
		_assert(str(template.get("interior_layer_id", "")) == "L04", "Template %s musi wiązać wnętrze z L04." % template_id)
		_assert(str(template.get("collider_layer_id", "")) == "L05", "Template %s musi wiązać strukturę z L05." % template_id)
		var allowed_socket_kinds = template.get("allowed_socket_kinds", null)
		_assert(allowed_socket_kinds is Array, "Template %s musi publikować allowed_socket_kinds." % template_id)
		if allowed_socket_kinds is Array:
			for socket_kind in allowed_socket_kinds as Array:
				_assert(not str(socket_kind).is_empty(), "Template %s nie może publikować pustego socket kind." % template_id)

	var collision: Dictionary = topology.get("collision_source", {})
	var world_size := _vector(map_record.get("world_size", []))
	var instance_ids := {}
	for index in range(instances.size()):
		var instance_value = instances[index]
		_assert(instance_value is Dictionary, "structures.instances[%d] musi być słownikiem." % index)
		if not instance_value is Dictionary:
			continue
		var instance := instance_value as Dictionary
		_assert_required_and_optional_dictionary_keys(
			instance,
			[
				"id", "template_id", "origin", "size", "enabled",
				"topology_digest", "partition_digest", "sockets", "runtime",
				"controller_script", "package_path", "package_sha256",
				"local_topology_digest", "collision_operations", "structure_scene_path",
			],
			["landmark_id"],
			"structures.instances[%d]" % index,
		)
		var structure_id := str(instance.get("id", ""))
		var template_id := str(instance.get("template_id", ""))
		_assert(not structure_id.is_empty(), "Instancja struktury musi mieć ID.")
		_assert(not instance_ids.has(structure_id), "ID instancji struktur muszą być unikalne.")
		instance_ids[structure_id] = instance
		_assert(template_ids.has(template_id), "Instancja %s musi wskazywać istniejący template_id." % structure_id)
		if instance.has("landmark_id"):
			var landmark_id := str(instance.get("landmark_id", ""))
			_assert(
				not landmark_id.is_empty()
				and not _record_by_id(
					manifest.get("landmarks", []) as Array,
					landmark_id,
				).is_empty(),
				"Opcjonalny landmark_id instancji %s musi wskazywać istniejący landmark." % structure_id,
			)
		var origin := _vector(instance.get("origin", []))
		var size := _vector(instance.get("size", []))
		_assert(_vector_is_grid_aligned(origin, L05_CELL_SIZE), "Instancja %s origin musi leżeć na siatce L05." % structure_id)
		_assert(_vector_is_grid_aligned(size, L05_CELL_SIZE), "Instancja %s size musi leżeć na siatce L05." % structure_id)
		_assert(size.x > 0.0 and size.y > 0.0, "Instancja %s musi mieć dodatni size." % structure_id)
		_assert(
			Rect2(Vector2.ZERO, world_size).encloses(Rect2(origin, size)),
			"Instancja %s musi mieścić się w map.world_size." % structure_id,
		)
		_assert(
			str(instance.get("topology_digest", "")) == str(collision.get("canonical_digest", "")),
			"Instancja %s musi wiązać aktualny topology_digest." % structure_id,
		)
		_assert(
			str(instance.get("partition_digest", "")) == str(collision.get("partition_digest", "")),
			"Instancja %s musi wiązać aktualny partition_digest." % structure_id,
		)
		_assert(typeof(instance.get("enabled", null)) == TYPE_BOOL, "Instancja %s musi publikować logiczne enabled." % structure_id)
		_assert(
			str(instance.get("package_path", "")) == "structures/%s/structure_manifest.json" % structure_id,
			"Rozwinięta instancja %s musi zachować package_path registry." % structure_id,
		)
		_assert(str(instance.get("package_sha256", "")).length() == 64, "Rozwinięta instancja %s musi zachować package_sha256." % structure_id)
		_assert(
			str(instance.get("controller_script", "")).begins_with(
				"res://underwater_map_workbench/structures/%s/" % structure_id
			),
			"Rozwinięta instancja %s musi wskazywać package-local controller_script." % structure_id,
		)
		_assert(
			str(instance.get("local_topology_digest", "")).begins_with("structure-topology-v1:"),
			"Rozwinięta instancja %s musi publikować lokalny digest topologii." % structure_id,
		)
		_assert(instance.get("collision_operations", null) is Array, "Rozwinięta instancja %s musi publikować lokalne collision_operations." % structure_id)
		_assert(
			str(instance.get("structure_scene_path", ""))
			== "res://underwater_map_workbench/structures/%s/generated/structure.tscn" % structure_id,
			"Rozwinięta instancja %s musi wskazywać package-local generated scene." % structure_id,
		)
		var sockets_value = instance.get("sockets", null)
		_assert(sockets_value is Array, "Instancja %s musi publikować sockets jako tablicę." % structure_id)
		if sockets_value is Array and template_ids.has(template_id):
			_assert_structure_sockets(
				sockets_value as Array,
				template_ids[template_id] as Dictionary,
				size,
				structure_id,
			)
		_assert(
			instance.get("runtime", null) is Dictionary,
			"Instancja %s musi publikować runtime jako nieprzezroczysty słownik pakietu."
			% structure_id,
		)


func _assert_structure_sockets(
	sockets: Array,
	template: Dictionary,
	structure_size: Vector2,
	structure_id: String,
) -> void:
	var allowed_kinds: Array = template.get("allowed_socket_kinds", [])
	var socket_ids := {}
	for index in range(sockets.size()):
		var socket_value = sockets[index]
		_assert(socket_value is Dictionary, "%s.sockets[%d] musi być słownikiem." % [structure_id, index])
		if not socket_value is Dictionary:
			continue
		var socket := socket_value as Dictionary
		_assert_exact_dictionary_keys(socket, ["id", "kind", "local_rect"], "%s.sockets[%d]" % [structure_id, index])
		var socket_id := str(socket.get("id", ""))
		_assert(not socket_id.is_empty(), "Socket struktury %s musi mieć ID." % structure_id)
		_assert(not socket_ids.has(socket_id), "Socket IDs struktury %s muszą być unikalne." % structure_id)
		socket_ids[socket_id] = true
		_assert(allowed_kinds.has(str(socket.get("kind", ""))), "Socket %s ma kind niedozwolony przez template." % socket_id)
		var local_rect := _rect(socket.get("local_rect", []))
		_assert(
			Rect2(Vector2.ZERO, structure_size).encloses(local_rect)
			and local_rect.size.x > 0.0
			and local_rect.size.y > 0.0,
			"Socket %s local_rect musi mieścić się w bounds struktury." % socket_id,
		)
		_assert(
			_vector_is_grid_aligned(local_rect.position, L05_CELL_SIZE)
			and _vector_is_grid_aligned(local_rect.size, L05_CELL_SIZE),
			"Socket %s local_rect musi leżeć na siatce L05." % socket_id,
		)


func _assert_layer_policy_records(
	layers: Array,
	assets: Array,
	topology: Dictionary,
	manifest: Dictionary,
) -> void:
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
	for layer_value in layers:
		if not layer_value is Dictionary:
			continue
		var layer := layer_value as Dictionary
		var layer_id := str(layer.get("id", ""))
		var policy := str(layer.get("affordance_policy", ""))
		if layer_id in NONBLOCKING_TEXTURE_LAYER_IDS:
			_assert(
				policy == OPEN_WATER_BACKDROP_AFFORDANCE_POLICY,
				"%s może przecinać otwartą wodę wyłącznie jako niekolidujące tło." % layer_id,
			)
		elif layer_id != authority_layer_id:
			_assert(
				policy == NO_BLOCKING_AFFORDANCE_POLICY,
				"%s musi zachować politykę chronionej wody." % layer_id,
			)
	var asset_ids := {}
	for index in range(assets.size()):
		var asset_value = assets[index]
		_assert(asset_value is Dictionary, "visual.assets[%d] musi być słownikiem." % index)
		if not asset_value is Dictionary:
			continue
		var asset := asset_value as Dictionary
		var asset_id := str(asset.get("id", ""))
		var layer_id := str(asset.get("layer_id", ""))
		var group_id := str(asset.get("group_id", ""))
		var kind := str(asset.get("kind", ""))
		_assert(not asset_id.is_empty(), "Każdy asset wizualny musi mieć ID.")
		_assert(not asset_ids.has(asset_id), "ID assetów wizualnych muszą być unikalne.")
		asset_ids[asset_id] = true
		_assert(EXPECTED_LAYER_IDS.has(layer_id), "Każdy asset musi wskazywać istniejący root L00-L10.")
		_assert(layer_id != "L10", "Zarezerwowane L10 nie może zawierać assetów.")
		_assert(
			asset.has("group_id") and _valid_visual_group_id(group_id),
			"Asset %s musi mieć bezpieczne, niepuste group_id." % asset_id,
		)
		_assert(
			[layer_id, kind] in [
				["L01", "texture_rect"],
				["L01", COMPOSITION_PROXY_KIND],
				["L02", "texture_rect"],
				["L02", COMPOSITION_PROXY_KIND],
				["L05", "collision_masked_material"],
				["L04", "structure_interior_texture"],
				["L05", "structure_owner_masked_texture"],
			],
			"Asset %s ma nieobsługiwaną parę layer_id/kind." % asset_id,
		)
		if kind in ["structure_interior_texture", "structure_owner_masked_texture"]:
			_assert_structure_visual_asset_record(asset, topology, manifest)


func _assert_structure_visual_asset_record(
	asset: Dictionary,
	topology: Dictionary,
	manifest: Dictionary,
) -> void:
	var asset_id := str(asset.get("id", ""))
	_assert_exact_dictionary_keys(
		asset,
		[
			"id", "layer_id", "group_id", "kind", "path", "sha256", "pixel_size",
			"local_rect", "enabled", "affordance", "topology_digest", "partition_digest",
			"structure_id",
		],
		"visual.assets[%s]" % asset_id,
	)
	var kind := str(asset.get("kind", ""))
	var expected_layer_id := "L04" if kind == "structure_interior_texture" else "L05"
	_assert(str(asset.get("layer_id", "")) == expected_layer_id, "Asset struktury %s ma niepoprawną warstwę." % asset_id)
	var structure_id := str(asset.get("structure_id", ""))
	var structure_instance := _structure_instance(manifest, structure_id)
	_assert(not structure_instance.is_empty(), "Asset struktury %s musi wskazywać istniejącą instancję." % asset_id)
	var local_rect := _rect(asset.get("local_rect", []))
	var structure_size := _vector(structure_instance.get("size", []))
	_assert(Rect2(Vector2.ZERO, structure_size).encloses(local_rect), "Asset struktury %s local_rect musi mieścić się w strukturze." % asset_id)
	_assert(_vector(asset.get("pixel_size", [])) == local_rect.size, "Asset struktury %s musi zachować pixel_size/local_rect 1:1." % asset_id)
	var collision: Dictionary = topology.get("collision_source", {})
	_assert(str(asset.get("topology_digest", "")) == str(collision.get("canonical_digest", "")), "Asset struktury %s musi wiązać topology_digest." % asset_id)
	_assert(str(asset.get("partition_digest", "")) == str(collision.get("partition_digest", "")), "Asset struktury %s musi wiązać partition_digest." % asset_id)


func _assert_source_dependencies(compiler, manifest: Dictionary) -> void:
	var dependencies: PackedStringArray = compiler.source_dependency_paths()
	_assert(dependencies.has(CompilerScript.MANIFEST_PATH), "Zależności muszą zawierać jedyny manifest.")
	_assert(dependencies.has(CompilerScript.MAP_SCENE_PATH), "Zależności muszą zawierać scenę pochodną.")
	var topology: Dictionary = manifest.get("topology", {})
	if str(topology.get("mode", "")) == L05_TOPOLOGY_MODE:
		var collision: Dictionary = topology.get("collision_source", {})
		var payload_path := "res://underwater_map_workbench/%s" % str(collision.get("path", ""))
		_assert(dependencies.has(payload_path), "Zależności muszą zawierać edytowalny payload L05.")
		_assert(
			dependencies.has("res://underwater_map_workbench/assets/generated/l05/solid_mask.png"),
			"Zależności muszą zawierać pochodną maskę renderującą L05.",
		)
		_assert(
			dependencies.has("res://underwater_map_workbench/assets/shaders/l05_ground_masked.gdshader"),
			"Zależności muszą zawierać shader spinający materiał z maską L05.",
		)
	var structures := manifest.get("structures", {}) as Dictionary
	for instance_value in structures.get("instances", []):
		if not instance_value is Dictionary:
			continue
		var instance := instance_value as Dictionary
		var structure_id := str(instance.get("id", ""))
		var package_resource_path := "res://underwater_map_workbench/%s" % str(instance.get("package_path", ""))
		var structure_scene_path := str(instance.get("structure_scene_path", ""))
		var generated_root := "res://underwater_map_workbench/structures/%s/generated" % structure_id
		_assert(dependencies.has(package_resource_path), "Zależności muszą zawierać package manifest %s." % structure_id)
		_assert(dependencies.has(structure_scene_path), "Zależności muszą zawierać package PackedScene %s." % structure_id)
		for mask_name in [
			"solid_mask_native.png",
			"open_water_mask_native.png",
			"surface_detail_mask_local.png",
		]:
			_assert(
				dependencies.has("%s/%s" % [generated_root, mask_name]),
				"Zależności muszą zawierać package-local maskę %s/%s." % [structure_id, mask_name],
			)
	for asset_value in (manifest.get("visual", {}) as Dictionary).get("assets", []):
		if asset_value is Dictionary:
			var asset := asset_value as Dictionary
			if str(asset.get("kind", "")) == COMPOSITION_PROXY_KIND:
				_assert(
					str(asset.get("path", "")).is_empty(),
					"Proxy kompozycyjne nie może publikować zależności tekstury.",
				)
				continue
			var asset_path := "res://underwater_map_workbench/%s" % str(asset.get("path", ""))
			_assert(dependencies.has(asset_path), "Zależności muszą zawierać każdy typowany asset wizualny.")


func _assert_l05_navigation_base(
	navigation_base: Dictionary,
	topology: Dictionary,
	manifest: Dictionary,
) -> void:
	var errors: PackedStringArray = navigation_base.get("errors", PackedStringArray())
	_assert(errors.is_empty(), "Bazowy raster L05 musi kompilować się bez błędów: %s" % "; ".join(errors))
	if not errors.is_empty() or str(topology.get("mode", "")) != L05_TOPOLOGY_MODE:
		return
	_assert(int(navigation_base.get("width", 0)) == L05_PIXEL_SIZE.x, "Raster L05 musi mieć szerokość 576.")
	_assert(int(navigation_base.get("height", 0)) == L05_PIXEL_SIZE.y, "Raster L05 musi mieć wysokość 324.")
	_assert(navigation_base.get("cell_scale", Vector2.ZERO) == L05_CELL_SIZE, "Raster L05 musi używać skali 40 x 40.")
	var expected_partition := _rasterize_l05_payload(topology, manifest)
	var expected_cells: PackedByteArray = expected_partition.get("cells", PackedByteArray())
	var expected_owner_cells: PackedInt32Array = expected_partition.get("solid_owner_cells", PackedInt32Array())
	var expected_owner_ids: PackedStringArray = expected_partition.get("owner_ids", PackedStringArray())
	var runtime_cells: PackedByteArray = navigation_base.get("cells", PackedByteArray())
	_assert(runtime_cells.size() == expected_cells.size(), "Runtime i payload L05 muszą mieć identyczną liczbę komórek.")
	_assert(
		str(navigation_base.get("partition_digest", ""))
		== str((topology.get("collision_source", {}) as Dictionary).get("partition_digest", "")),
		"navigation_base_raster musi publikować aktualny partition_digest.",
	)
	var owner_ids_value = navigation_base.get("owner_ids", null)
	var owner_cells_value = navigation_base.get("solid_owner_cells", null)
	_assert(
		typeof(owner_ids_value) == TYPE_PACKED_STRING_ARRAY,
		"navigation_base_raster.owner_ids musi być PackedStringArray.",
	)
	_assert(
		typeof(owner_cells_value) == TYPE_PACKED_INT32_ARRAY,
		"navigation_base_raster.solid_owner_cells musi być PackedInt32Array.",
	)
	var runtime_owner_ids := PackedStringArray()
	var runtime_owner_cells := PackedInt32Array()
	if typeof(owner_ids_value) == TYPE_PACKED_STRING_ARRAY:
		runtime_owner_ids = owner_ids_value as PackedStringArray
	if typeof(owner_cells_value) == TYPE_PACKED_INT32_ARRAY:
		runtime_owner_cells = owner_cells_value as PackedInt32Array
	_assert(runtime_owner_ids == expected_owner_ids, "Raster L05 musi zachować deterministyczną kolejność owner_ids.")
	_assert(runtime_owner_cells == expected_owner_cells, "Raster L05 musi zachować owner każdego solid cell 1:1.")
	var structure_instances: Array = (manifest.get("structures", {}) as Dictionary).get("instances", [])
	_assert(
		runtime_owner_ids.size() == 2 + structure_instances.size(),
		"Raster L05 musi publikować open, world i po jednym owner ID dla każdej zarejestrowanej struktury.",
	)
	if runtime_owner_ids.size() >= 2:
		_assert(runtime_owner_ids[OPEN_WATER_OWNER_INDEX].is_empty(), "owner_ids[0] musi oznaczać open_water.")
		_assert(runtime_owner_ids[WORLD_OWNER_INDEX] == WORLD_COLLISION_OWNER_ID, "owner_ids[1] musi oznaczać world.")
	for instance_value in structure_instances:
		if instance_value is Dictionary:
			var structure_id := str((instance_value as Dictionary).get("id", ""))
			_assert(runtime_owner_ids.has(structure_id), "owner_ids musi zawierać strukturę %s." % structure_id)
	_assert(runtime_owner_cells.size() == runtime_cells.size(), "Owner raster i navigation cells muszą mieć ten sam rozmiar.")
	var solid_count := 0
	var open_count := 0
	var comparable_count := mini(runtime_cells.size(), expected_cells.size())
	for index in range(comparable_count):
		if int(expected_cells[index]) == 0:
			solid_count += 1
			if index < runtime_owner_cells.size():
				_assert(runtime_owner_cells[index] > OPEN_WATER_OWNER_INDEX, "Każda komórka solid musi mieć właściciela.")
		else:
			open_count += 1
			if index < runtime_owner_cells.size():
				_assert(runtime_owner_cells[index] == OPEN_WATER_OWNER_INDEX, "Komórka open_water nie może mieć właściciela kolizji.")
		if int(runtime_cells[index]) != int(expected_cells[index]):
			_assert(false, "Runtime L05 różni się od payloadu przy komórce %d." % index)
			break
	_assert(solid_count > 0, "Bieżący payload L05 musi zawierać grunt stały.")
	_assert(open_count > 0, "Bieżący payload L05 musi pozostawiać otwartą wodę.")


func _rasterize_l05_payload(topology: Dictionary, manifest: Dictionary) -> Dictionary:
	var collision: Dictionary = topology.get("collision_source", {})
	var payload_path := str(collision.get("path", ""))
	var resource_path := "res://underwater_map_workbench/%s" % payload_path
	_assert(FileAccess.file_exists(resource_path), "Źródłowy payload L05 musi istnieć.")
	if not FileAccess.file_exists(resource_path):
		return {}
	_assert(
		FileAccess.get_sha256(resource_path).to_lower() == str(collision.get("sha256", "")),
		"SHA źródłowego payloadu L05 musi odpowiadać manifestowi.",
	)
	var file := FileAccess.open(resource_path, FileAccess.READ)
	_assert(file != null, "Test musi móc otworzyć payload L05.")
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	_assert(parsed is Dictionary, "Payload L05 musi być obiektem JSON.")
	if not parsed is Dictionary:
		return {}
	var payload := parsed as Dictionary
	_assert_exact_dictionary_keys(payload, ["schema_version", "base", "operations"], "payload L05 v2")
	_assert(int(payload.get("schema_version", 0)) == 2, "Payload L05 musi używać schema_version=2.")
	_assert(str(payload.get("base", "")) == "open_water", "Payload L05 musi zaczynać od otwartej wody.")
	var owner_ids := PackedStringArray(["", WORLD_COLLISION_OWNER_ID])
	var owner_index_by_id := {WORLD_COLLISION_OWNER_ID: WORLD_OWNER_INDEX}
	var structure_origins_px := {}
	var structure_sizes_px := {}
	var structures: Dictionary = manifest.get("structures", {})
	for instance_value in structures.get("instances", []):
		if not instance_value is Dictionary:
			continue
		var structure_id := str((instance_value as Dictionary).get("id", ""))
		if structure_id.is_empty() or owner_index_by_id.has(structure_id):
			continue
		owner_index_by_id[structure_id] = owner_ids.size()
		owner_ids.append(structure_id)
		var instance := instance_value as Dictionary
		structure_origins_px[structure_id] = Vector2i(
			roundi(_vector(instance.get("origin", [])).x / L05_CELL_SIZE.x),
			roundi(_vector(instance.get("origin", [])).y / L05_CELL_SIZE.y),
		)
		structure_sizes_px[structure_id] = Vector2i(
			roundi(_vector(instance.get("size", [])).x / L05_CELL_SIZE.x),
			roundi(_vector(instance.get("size", [])).y / L05_CELL_SIZE.y),
		)
	var cells := PackedByteArray()
	cells.resize(L05_PIXEL_SIZE.x * L05_PIXEL_SIZE.y)
	cells.fill(1)
	var solid_owner_cells := PackedInt32Array()
	solid_owner_cells.resize(cells.size())
	solid_owner_cells.fill(OPEN_WATER_OWNER_INDEX)
	var operations_value = payload.get("operations", null)
	_assert(operations_value is Array, "Payload L05 musi publikować edytowalną tablicę operations.")
	if not operations_value is Array:
		return {}
	var operation_ids := {}
	var saw_world_owner := false
	for operation_value in operations_value as Array:
		_assert(operation_value is Dictionary, "Każda operacja L05 musi być obiektem.")
		if not operation_value is Dictionary:
			continue
		var operation := operation_value as Dictionary
		var operation_space := str(operation.get("space", ""))
		_assert_exact_dictionary_keys(operation, ["id", "op", "space", "rect_px"], "globalna operacja L05 %s" % str(operation.get("id", "?")))
		_assert(operation_space == "world_px", "Globalny payload L05 może publikować wyłącznie operacje world_px.")
		var operation_id := str(operation.get("id", ""))
		_assert(not operation_id.is_empty() and not operation_ids.has(operation_id), "Operacje L05 muszą mieć unikalne ID.")
		operation_ids[operation_id] = true
		var rect_value = operation.get("rect_px", [])
		_assert(rect_value is Array and (rect_value as Array).size() == 4, "Operacja L05 wymaga rect_px.")
		if not rect_value is Array or (rect_value as Array).size() != 4:
			continue
		var rect := rect_value as Array
		var x := int(rect[0])
		var y := int(rect[1])
		var width := int(rect[2])
		var height := int(rect[3])
		var operation_kind := str(operation.get("op", ""))
		_assert(operation_kind in ["solid_rect", "open_rect"], "Operacja L05 v2 musi być solid_rect albo open_rect.")
		var owner_id := WORLD_COLLISION_OWNER_ID
		saw_world_owner = true
		_assert(
			x >= 0 and y >= 0 and width > 0 and height > 0
			and x + width <= L05_PIXEL_SIZE.x and y + height <= L05_PIXEL_SIZE.y,
			"Operacja L05 musi mieścić się w pełnym rastrze.",
		)
		var value := 0 if operation_kind == "solid_rect" else 1
		var owner_index := int(owner_index_by_id.get(owner_id, OPEN_WATER_OWNER_INDEX))
		for row in range(y, y + height):
			for column in range(x, x + width):
				var cell_index := row * L05_PIXEL_SIZE.x + column
				cells[cell_index] = value
				solid_owner_cells[cell_index] = owner_index if value == 0 else OPEN_WATER_OWNER_INDEX
	_assert(saw_world_owner, "Globalny payload L05 v2 musi zawierać operacje world_px należące do world.")
	var saw_package_operation := false
	for instance_value in structures.get("instances", []):
		if not instance_value is Dictionary:
			continue
		var instance := instance_value as Dictionary
		var structure_id := str(instance.get("id", ""))
		var structure_origin: Vector2i = structure_origins_px.get(structure_id, Vector2i.ZERO)
		var local_size: Vector2i = structure_sizes_px.get(structure_id, Vector2i.ZERO)
		var package_resource_path := "res://underwater_map_workbench/%s" % str(instance.get("package_path", ""))
		var package := _load_json_resource(package_resource_path, "pakiet kolizji %s" % structure_id)
		var package_collision := package.get("collision", {}) as Dictionary
		var package_operations := package_collision.get("operations", []) as Array
		for package_operation_value in package_operations:
			if not package_operation_value is Dictionary:
				continue
			var package_operation := package_operation_value as Dictionary
			_assert_exact_dictionary_keys(
				package_operation,
				["id", "op", "rect_px"],
				"lokalna operacja pakietu %s" % structure_id,
			)
			var operation_id := str(package_operation.get("id", ""))
			_assert(not operation_id.is_empty() and not operation_ids.has(operation_id), "Globalne i package-local operation IDs muszą być unikalne.")
			operation_ids[operation_id] = true
			var rect := package_operation.get("rect_px", []) as Array
			if rect.size() != 4:
				continue
			var local_x := int(rect[0])
			var local_y := int(rect[1])
			var width := int(rect[2])
			var height := int(rect[3])
			_assert(
				local_x >= 0 and local_y >= 0 and width > 0 and height > 0
				and local_x + width <= local_size.x and local_y + height <= local_size.y,
				"Package collision %s musi mieścić się wyłącznie w lokalnym rastrze." % structure_id,
			)
			var operation_kind := str(package_operation.get("op", ""))
			_assert(operation_kind in ["solid_rect", "open_rect"], "Package collision %s ma niepoprawny op." % structure_id)
			var value := 0 if operation_kind == "solid_rect" else 1
			var owner_index := int(owner_index_by_id.get(structure_id, OPEN_WATER_OWNER_INDEX))
			for row in range(structure_origin.y + local_y, structure_origin.y + local_y + height):
				for column in range(structure_origin.x + local_x, structure_origin.x + local_x + width):
					var cell_index := row * L05_PIXEL_SIZE.x + column
					cells[cell_index] = value
					solid_owner_cells[cell_index] = owner_index if value == 0 else OPEN_WATER_OWNER_INDEX
			saw_package_operation = true
	_assert(
		saw_package_operation,
		"Co najmniej jeden zarejestrowany pakiet musi dostarczyć lokalne operacje poza globalnym payloadem.",
	)
	return {
		"cells": cells,
		"owner_ids": owner_ids,
		"solid_owner_cells": solid_owner_cells,
		"partition_digest": str(collision.get("partition_digest", "")),
	}


func _validate_manifest_fixtures_if_supported(compiler, manifest: Dictionary) -> void:
	_assert(compiler.has_method("validate_manifest_for_tests"), "Compiler musi publikować validate_manifest_for_tests.")
	_assert(compiler.has_method("compile_from_manifest_for_tests"), "Compiler musi publikować compile_from_manifest_for_tests.")
	if not compiler.has_method("validate_manifest_for_tests") or not compiler.has_method("compile_from_manifest_for_tests"):
		return
	_validate_exact_map_dimensions(compiler, manifest)
	_validate_structure_fixtures(compiler, manifest)
	_validate_visual_element_fixtures(compiler, manifest)
	for layer_id: String in _active_nonblocking_texture_layer_ids(manifest):
		_validate_backdrop_aspect_ratio(compiler, manifest, layer_id)
		if layer_id in GROUND_ANCHORED_BACKDROP_LAYER_IDS:
			_validate_backdrop_ground_anchor(compiler, manifest, layer_id)
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

		var tint_fixture := manifest.duplicate(true)
		var tint_layers: Array = (tint_fixture["visual"] as Dictionary)["layers"]
		var tint_l01 := tint_layers[1] as Dictionary
		tint_l01["rgb_modulate"] = "4f6270"
		var tint_compilation = compiler.call(
			"compile_from_manifest_for_tests",
			tint_fixture,
			CAMPAIGN_SEED,
		)
		_assert(tint_compilation is Dictionary, "Tint fixture musi zwrócić wynik kompilacji.")
		if tint_compilation is Dictionary:
			var tint_errors: PackedStringArray = tint_compilation.get("errors", PackedStringArray())
			_assert(
				tint_errors.is_empty(),
				"Tint fixture musi kompilować się bez błędów: %s" % "; ".join(tint_errors),
			)
			_assert(
				str(tint_compilation.get("map_gameplay_signature", ""))
				== str(baseline_compilation.get("map_gameplay_signature", "")),
				"Zmiana rgb_modulate nie może zmieniać gameplay signature.",
			)
			_assert(
				str(tint_compilation.get("presentation_fingerprint", ""))
				!= str(baseline_compilation.get("presentation_fingerprint", "")),
				"Zmiana rgb_modulate musi zmienić presentation fingerprint.",
			)

		var alpha_tint_fixture := manifest.duplicate(true)
		var alpha_tint_layers: Array = (alpha_tint_fixture["visual"] as Dictionary)["layers"]
		(alpha_tint_layers[1] as Dictionary)["rgb_modulate"] = "4f627080"
		_assert_manifest_rejected_with_fragment(
			compiler,
			alpha_tint_fixture,
			"rgb_modulate",
			"Manifest musi odrzucać rgb_modulate zawierający kanał alfa.",
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


func _active_nonblocking_texture_layer_ids(manifest: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var visual: Dictionary = manifest.get("visual", {})
	for asset_value in visual.get("assets", []):
		if not asset_value is Dictionary:
			continue
		var asset := asset_value as Dictionary
		if str(asset.get("kind", "")) in [
			"structure_interior_texture", "structure_owner_masked_texture",
		]:
			continue
		var layer_id := str(asset.get("layer_id", ""))
		if (
			bool(asset.get("enabled", true))
			and str(asset.get("kind", "")) == "texture_rect"
			and layer_id in NONBLOCKING_TEXTURE_LAYER_IDS
			and not result.has(layer_id)
		):
			result.append(layer_id)
	return result


func _assert_streamed_backdrops_are_scene_stubs(manifest: Dictionary) -> void:
	var scene_file := FileAccess.open(CompilerScript.MAP_SCENE_PATH, FileAccess.READ)
	_assert(scene_file != null, "Scena mapy musi być czytelna do kontroli zależności rezydencji.")
	if scene_file == null:
		return
	var scene_text := scene_file.get_as_text()
	var visual: Dictionary = manifest.get("visual", {})
	for asset_value in visual.get("assets", []):
		if not asset_value is Dictionary:
			continue
		var asset := asset_value as Dictionary
		if (
			str(asset.get("kind", "")) != "texture_rect"
			or str(asset.get("layer_id", "")) not in NONBLOCKING_TEXTURE_LAYER_IDS
		):
			continue
		var resource_path := "res://underwater_map_workbench/%s" % str(asset.get("path", ""))
		_assert(
			not scene_text.contains('[ext_resource type="Texture2D" path="%s"' % resource_path),
			"UnderwaterMap.tscn nie może rezydentować %s jako Texture2D ext_resource."
			% str(asset.get("id", "")),
		)


func _validate_structure_fixtures(compiler, manifest: Dictionary) -> void:
	var structure_records: Array = (manifest.get("structures", {}) as Dictionary).get("instances", [])
	_assert(not structure_records.is_empty(), "Fixture struktur wymaga co najmniej jednego zarejestrowanego pakietu.")
	if structure_records.is_empty() or not structure_records[0] is Dictionary:
		return
	var source_instance := structure_records[0] as Dictionary
	var structure_id := str(source_instance.get("id", ""))
	var template_id := str(source_instance.get("template_id", ""))

	var missing_template_fixture := manifest.duplicate(true)
	var missing_template_instance := _structure_instance(missing_template_fixture, structure_id)
	if not missing_template_instance.is_empty():
		missing_template_instance["template_id"] = "__missing_structure_template__"
		_assert_manifest_rejected_with_fragment(
			compiler,
			missing_template_fixture,
			"template_id",
			"Walidator musi odrzucać instancję wskazującą nieznany template.",
		)

	var optional_landmark_fixture := manifest.duplicate(true)
	var optional_landmark_instance := _structure_instance(optional_landmark_fixture, structure_id)
	if not optional_landmark_instance.is_empty():
		optional_landmark_instance.erase("landmark_id")
		var optional_landmark_errors: PackedStringArray = compiler.call(
			"validate_manifest_for_tests",
			optional_landmark_fixture,
		)
		_assert(
			optional_landmark_errors.is_empty(),
			"Brak opcjonalnego landmark_id musi być legalny: %s"
			% "; ".join(optional_landmark_errors),
		)
		var landmarks: Array = manifest.get("landmarks", [])
		if not landmarks.is_empty() and landmarks[0] is Dictionary:
			optional_landmark_instance["landmark_id"] = str((landmarks[0] as Dictionary).get("id", ""))
			var valid_landmark_errors: PackedStringArray = compiler.call(
				"validate_manifest_for_tests",
				optional_landmark_fixture,
			)
			_assert(
				valid_landmark_errors.is_empty(),
				"Obecny landmark_id wskazujący istniejący landmark musi być legalny: %s"
				% "; ".join(valid_landmark_errors),
			)
		optional_landmark_instance["landmark_id"] = "__missing_landmark__"
		_assert_manifest_rejected_with_fragment(
			compiler,
			optional_landmark_fixture,
			"landmark_id",
			"Walidator musi odrzucać obecny landmark_id wskazujący nieznany landmark.",
		)

	var off_grid_fixture := manifest.duplicate(true)
	var off_grid_instance := _structure_instance(off_grid_fixture, structure_id)
	if not off_grid_instance.is_empty():
		var off_grid_origin: Array = (off_grid_instance.get("origin", []) as Array).duplicate()
		off_grid_origin[0] = int(off_grid_origin[0]) + 1
		off_grid_instance["origin"] = off_grid_origin
		_assert_manifest_rejected_with_fragment(
			compiler,
			off_grid_fixture,
			"wyrównana do rastra L05",
			"Walidator musi odrzucać origin struktury poza siatką L05.",
		)

	var outside_socket_fixture := manifest.duplicate(true)
	var outside_socket_instance := _structure_instance(outside_socket_fixture, structure_id)
	var structure_template := _structure_template(outside_socket_fixture, template_id)
	if not outside_socket_instance.is_empty() and not structure_template.is_empty():
		var allowed_kinds: Array = structure_template.get("allowed_socket_kinds", [])
		if not allowed_kinds.is_empty():
			var sockets: Array = outside_socket_instance.get("sockets", [])
			sockets.append({
				"id": "__map_smoke_socket__",
				"kind": str(allowed_kinds[0]),
				"local_rect": [0, 0, int(L05_CELL_SIZE.x), int(L05_CELL_SIZE.y)],
			})
			var valid_socket_errors: PackedStringArray = compiler.call(
				"validate_manifest_for_tests",
				outside_socket_fixture,
			)
			_assert(
				valid_socket_errors.is_empty(),
				"Typowany socket wewnątrz bounds musi przechodzić walidację: %s"
				% "; ".join(valid_socket_errors),
			)
			(sockets[sockets.size() - 1] as Dictionary)["local_rect"] = [
				1, 0, int(L05_CELL_SIZE.x), int(L05_CELL_SIZE.y),
			]
			_assert_manifest_rejected_with_fragment(
				compiler,
				outside_socket_fixture,
				"wyrównany do rastra L05",
				"Walidator musi odrzucać socket local_rect poza siatką L05.",
			)
			var structure_size := _vector(outside_socket_instance.get("size", []))
			(sockets[sockets.size() - 1] as Dictionary)["local_rect"] = [
				int(structure_size.x) - 40,
				int(structure_size.y) - 40,
				80,
				80,
			]
			_assert_manifest_rejected_with_fragment(
				compiler,
				outside_socket_fixture,
				"local_rect",
				"Walidator musi odrzucać socket local_rect wychodzący poza bounds struktury.",
			)

	var duplicate_socket_fixture := manifest.duplicate(true)
	var duplicate_socket_instance := _structure_instance(duplicate_socket_fixture, structure_id)
	if not duplicate_socket_instance.is_empty():
		var duplicate_sockets: Array = duplicate_socket_instance.get("sockets", [])
		if not duplicate_sockets.is_empty():
			duplicate_sockets.append((duplicate_sockets[0] as Dictionary).duplicate(true))
			_assert_manifest_rejected_with_fragment(
				compiler,
				duplicate_socket_fixture,
				"unikalnego lokalnie ID",
				"Walidator musi odrzucać zduplikowane ID socketu.",
			)

	var bad_socket_kind_fixture := manifest.duplicate(true)
	var bad_socket_kind_instance := _structure_instance(bad_socket_kind_fixture, structure_id)
	if not bad_socket_kind_instance.is_empty():
		var bad_kind_sockets: Array = bad_socket_kind_instance.get("sockets", [])
		if not bad_kind_sockets.is_empty():
			(bad_kind_sockets[0] as Dictionary)["kind"] = "__unsupported_socket_kind__"
			_assert_manifest_rejected_with_fragment(
				compiler,
				bad_socket_kind_fixture,
				"kind nie jest dozwolony",
				"Walidator musi odrzucać kind socketu spoza template.",
			)

	var stale_partition_fixture := manifest.duplicate(true)
	var stale_partition_instance := _structure_instance(stale_partition_fixture, structure_id)
	if not stale_partition_instance.is_empty():
		stale_partition_instance["partition_digest"] = "partition-v1:stale-fixture"
		_assert_manifest_rejected_with_fragment(
			compiler,
			stale_partition_fixture,
			"partition_digest",
			"Walidator musi odrzucać strukturę ze starym partition_digest.",
		)

	var invalid_runtime_fixture := manifest.duplicate(true)
	var invalid_runtime_instance := _structure_instance(invalid_runtime_fixture, structure_id)
	if not invalid_runtime_instance.is_empty():
		invalid_runtime_instance["runtime"] = []
		_assert_manifest_rejected_with_fragment(
			compiler,
			invalid_runtime_fixture,
			"runtime musi być obiektem",
			"Mapa musi odrzucać runtime pakietu, który nie jest słownikiem.",
		)

	var opaque_runtime_fixture := manifest.duplicate(true)
	var opaque_runtime_instance := _structure_instance(opaque_runtime_fixture, structure_id)
	if not opaque_runtime_instance.is_empty():
		var opaque_runtime: Dictionary = opaque_runtime_instance.get("runtime", {})
		opaque_runtime["__package_owned_smoke_probe__"] = {"values": [1, 2, 3]}
		var opaque_runtime_errors: PackedStringArray = compiler.call(
			"validate_manifest_for_tests",
			opaque_runtime_fixture,
		)
		_assert(
			opaque_runtime_errors.is_empty(),
			"Mapa musi traktować prywatny payload runtime pakietu jako nieprzezroczysty: %s"
			% "; ".join(opaque_runtime_errors),
		)

func _validate_visual_element_fixtures(compiler, manifest: Dictionary) -> void:
	var bad_group_fixture := manifest.duplicate(true)
	var bad_group_proxy := _ensure_proxy_fixture_asset(bad_group_fixture)
	bad_group_proxy["group_id"] = "bad/group"
	_assert_manifest_rejected_with_fragment(
		compiler,
		bad_group_fixture,
		"group_id",
		"Walidator musi odrzucać niebezpieczne group_id proxy.",
	)

	var sourced_proxy_fixture := manifest.duplicate(true)
	var sourced_proxy := _ensure_proxy_fixture_asset(sourced_proxy_fixture)
	sourced_proxy["path"] = "assets/visual/proxy-must-not-have-a-texture.png"
	sourced_proxy["sha256"] = "0000000000000000000000000000000000000000000000000000000000000000"
	_assert_manifest_rejected_with_fragment(
		compiler,
		sourced_proxy_fixture,
		"proxy kompozycyjne",
		"Walidator musi odrzucać proxy z path lub sha256.",
	)

	var resized_proxy_fixture := manifest.duplicate(true)
	var resized_proxy := _ensure_proxy_fixture_asset(resized_proxy_fixture)
	var resized_pixel_size: Array = (resized_proxy.get("pixel_size", []) as Array).duplicate()
	resized_pixel_size[0] = int(resized_pixel_size[0]) + 1
	resized_proxy["pixel_size"] = resized_pixel_size
	_assert_manifest_rejected_with_fragment(
		compiler,
		resized_proxy_fixture,
		"1:1 bez skalowania",
		"Walidator musi odrzucać proxy o pixel_size innym niż world_rect.size.",
	)

	var outside_structure_asset_fixture := manifest.duplicate(true)
	var outside_structure_asset := _first_structure_visual_asset(outside_structure_asset_fixture)
	if not outside_structure_asset.is_empty():
		var outside_structure_id := str(outside_structure_asset.get("structure_id", ""))
		var outside_structure := _structure_instance(outside_structure_asset_fixture, outside_structure_id)
		var outside_structure_size := _vector(outside_structure.get("size", []))
		outside_structure_asset["local_rect"] = [outside_structure_size.x - 40.0, 0, 80, 80]
		_assert_manifest_rejected_with_fragment(
			compiler,
			outside_structure_asset_fixture,
			"local_rect",
			"Walidator musi odrzucać structure-local asset poza bounds jego struktury.",
		)

	var stale_structure_asset_fixture := manifest.duplicate(true)
	var stale_structure_asset := _first_structure_visual_asset(stale_structure_asset_fixture)
	if not stale_structure_asset.is_empty():
		stale_structure_asset["partition_digest"] = "partition-v1:stale-fixture"
		_assert_manifest_rejected_with_fragment(
			compiler,
			stale_structure_asset_fixture,
			"partition_digest",
			"Walidator musi odrzucać structure-local asset starego partition_digest.",
		)


func _first_structure_visual_asset(manifest: Dictionary) -> Dictionary:
	var visual: Dictionary = manifest.get("visual", {})
	for asset_value in visual.get("assets", []):
		if (
			asset_value is Dictionary
			and str((asset_value as Dictionary).get("kind", "")) in [
				"structure_interior_texture", "structure_owner_masked_texture",
			]
		):
			return asset_value as Dictionary
	return {}


func _ensure_proxy_fixture_asset(fixture: Dictionary) -> Dictionary:
	var visual: Dictionary = fixture.get("visual", {})
	var assets: Array = visual.get("assets", [])
	for asset_value in assets:
		if asset_value is Dictionary and str((asset_value as Dictionary).get("kind", "")) == COMPOSITION_PROXY_KIND:
			return asset_value as Dictionary
	var fixture_id := "__composition_proxy_fixture__"
	while not _record_by_id(assets, fixture_id).is_empty():
		fixture_id += "x"
	var proxy := {
		"id": fixture_id,
		"layer_id": "L01",
		"group_id": "Elements",
		"kind": COMPOSITION_PROXY_KIND,
		"path": "",
		"sha256": "",
		"pixel_size": [16, 16],
		"world_rect": [0, 0, 16, 16],
		"enabled": true,
		"affordance": NONBLOCKING_BACKDROP_AFFORDANCE,
		"topology_digest": "",
	}
	assets.append(proxy)
	return proxy


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


func _validate_backdrop_aspect_ratio(
	compiler,
	manifest: Dictionary,
	layer_id: String,
) -> void:
	var fixture := manifest.duplicate(true)
	var visual: Dictionary = fixture.get("visual", {})
	var assets: Array = visual.get("assets", [])
	for asset_value in assets:
		if not asset_value is Dictionary:
			continue
		var asset := asset_value as Dictionary
		if (
			str(asset.get("layer_id", "")) != layer_id
			or str(asset.get("kind", "")) != "texture_rect"
		):
			continue
		var world_rect: Array = (asset.get("world_rect", []) as Array).duplicate()
		if world_rect.size() != 4:
			_assert(false, "Fixture proporcji %s wymaga poprawnego world_rect." % layer_id)
			return
		world_rect[3] = float(world_rect[3]) - 40.0
		asset["world_rect"] = world_rect
		_assert_manifest_rejected(
			compiler,
			fixture,
			"%s musi odrzucać world_rect o proporcji innej niż pixel_size źródła."
			% layer_id,
		)
		return
	_assert(false, "Fixture proporcji wymaga aktywnego texture_rect na %s." % layer_id)


func _validate_backdrop_ground_anchor(
	compiler,
	manifest: Dictionary,
	layer_id: String,
) -> void:
	var fixture := manifest.duplicate(true)
	var visual: Dictionary = fixture.get("visual", {})
	var layers: Array = visual.get("layers", [])
	for layer_value in layers:
		if not layer_value is Dictionary:
			continue
		var layer := layer_value as Dictionary
		if str(layer.get("id", "")) != layer_id:
			continue
		var parallax_scale: Array = (layer.get("parallax_scale", []) as Array).duplicate()
		if parallax_scale.size() != 2:
			_assert(false, "Fixture kotwicy %s wymaga poprawnej parallax_scale." % layer_id)
			return
		parallax_scale[1] = 0.5
		layer["parallax_scale"] = parallax_scale
		_assert_manifest_rejected(
			compiler,
			fixture,
			"%s musi odrzucać pionowe odklejenie tła od gruntu." % layer_id,
		)
		return
	_assert(false, "Fixture kotwicy wymaga aktywnej warstwy %s." % layer_id)


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


func _assert_manifest_rejected_with_fragment(
	compiler,
	fixture: Dictionary,
	expected_fragment: String,
	message: String,
) -> void:
	var result = compiler.call("validate_manifest_for_tests", fixture)
	_assert(typeof(result) == TYPE_PACKED_STRING_ARRAY, "Walidator fixture musi zwracać PackedStringArray.")
	if typeof(result) != TYPE_PACKED_STRING_ARRAY:
		return
	var errors := result as PackedStringArray
	_assert(not errors.is_empty(), message)
	var matching_error := false
	var normalized_fragment := expected_fragment.to_lower()
	for error in errors:
		if str(error).to_lower().contains(normalized_fragment):
			matching_error = true
			break
	_assert(
		matching_error,
		"%s Otrzymane błędy: %s" % [message, "; ".join(errors)],
	)


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
	_assert(int(map_root.get_meta("schema_version", 0)) == EXPECTED_SCHEMA_VERSION, "Scena musi publikować schema v6.")
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
	if str(topology.get("mode", "")) == L05_TOPOLOGY_MODE:
		var collision: Dictionary = topology.get("collision_source", {})
		_assert(
			str(map_root.get_meta("payload_sha256", "")) == str(collision.get("sha256", "")),
			"Scena musi publikować SHA edytowalnego payloadu L05.",
		)
		_assert(
			str(map_root.get_meta("canonical_digest", "")) == str(collision.get("canonical_digest", "")),
			"Scena musi publikować kanoniczny digest geometrii L05.",
		)


func _assert_structure_roots(
	structure_roots_value,
	manifest: Dictionary,
	navigation_base: Dictionary,
	owner_label: String,
) -> void:
	_assert(structure_roots_value is Node2D, "%s musi publikować top-level StructureRoots:Node2D." % owner_label)
	if not structure_roots_value is Node2D:
		return
	var structure_roots := structure_roots_value as Node2D
	_assert(
		structure_roots.position == Vector2.ZERO
		and is_zero_approx(structure_roots.rotation)
		and structure_roots.scale == Vector2.ONE,
		"%s/StructureRoots musi mieć identity transform." % owner_label,
	)
	var structures: Dictionary = manifest.get("structures", {})
	var instances: Array = structures.get("instances", [])
	var enabled_instances: Array[Dictionary] = []
	for instance_value in instances:
		if instance_value is Dictionary and bool((instance_value as Dictionary).get("enabled", false)):
			enabled_instances.append(instance_value as Dictionary)
	_assert(
		structure_roots.get_child_count() == enabled_instances.size(),
		"%s/StructureRoots musi zawierać dokładnie aktywne instancje manifestu." % owner_label,
	)
	var expected_boundary_sets := _expected_boundary_sets_by_owner(navigation_base)
	for instance in enabled_instances:
		var structure_id := str(instance.get("id", ""))
		var structure_root := structure_roots.get_node_or_null(structure_id)
		_assert(structure_root is Node2D, "%s/StructureRoots musi zawierać %s:Node2D." % [owner_label, structure_id])
		if not structure_root is Node2D:
			continue
		_assert_structure_root_node(
			structure_root as Node2D,
			instance,
			expected_boundary_sets.get(structure_id, {}) as Dictionary,
			_structure_visual_assets(manifest, structure_id),
			owner_label,
		)


func _assert_structure_root_node(
	structure_root: Node2D,
	instance: Dictionary,
	expected_boundary_set: Dictionary,
	structure_assets: Array[Dictionary],
	owner_label: String,
) -> void:
	var structure_id := str(instance.get("id", ""))
	if owner_label == "scena":
		_assert_structure_root_is_package_scene_instance(structure_root, instance)
	var expected_children := PackedStringArray([
		"InteriorVisual", "StructureVisual", "StaticCollision", "DynamicBodies", "Interactives",
	])
	var actual_children := PackedStringArray()
	for child in structure_root.get_children():
		actual_children.append(str(child.name))
	_assert(actual_children == expected_children, "%s/%s musi mieć dokładną lokalną hierarchię struktury." % [owner_label, structure_id])
	_assert(
		structure_root.position == _vector(instance.get("origin", []))
		and is_zero_approx(structure_root.rotation)
		and structure_root.scale == Vector2.ONE,
		"%s/%s musi używać wyłącznie origin manifestu na identity root." % [owner_label, structure_id],
	)
	_assert(structure_root.visible == bool(instance.get("enabled", false)), "%s/%s musi wyprowadzać visible z enabled." % [owner_label, structure_id])
	_assert(str(structure_root.get_meta("structure_id", "")) == structure_id, "%s/%s musi publikować structure_id." % [owner_label, structure_id])
	_assert(
		_manifest_value_matches(instance, structure_root.get_meta("source", {})),
		"%s/%s musi publikować rekord instancji 1:1." % [owner_label, structure_id],
	)
	var expected_runtime = instance.get("runtime", {})
	_assert(
		_manifest_value_matches(expected_runtime, structure_root.get_meta("runtime", {})),
		"%s/%s musi publikować opcjonalny rekord runtime 1:1." % [owner_label, structure_id],
	)
	var interior := structure_root.get_node_or_null("InteriorVisual") as Node2D
	var structure_visual := structure_root.get_node_or_null("StructureVisual") as Node2D
	var static_collision := structure_root.get_node_or_null("StaticCollision") as StaticBody2D
	var dynamic_bodies := structure_root.get_node_or_null("DynamicBodies") as Node2D
	var interactives := structure_root.get_node_or_null("Interactives") as Node2D
	_assert(interior != null and interior.z_index == -20, "%s/%s/InteriorVisual musi być L04 z=-20." % [owner_label, structure_id])
	_assert(structure_visual != null and structure_visual.z_index == 0, "%s/%s/StructureVisual musi być L05 z=0." % [owner_label, structure_id])
	if interior != null:
		_assert(str(interior.get_meta("logical_layer_id", "")) == "L04", "%s/%s/InteriorVisual musi publikować L04." % [owner_label, structure_id])
		_assert(
			interior.get_node_or_null("Backwall") == null,
			"%s/%s/InteriorVisual nie może zawierać pozamanifestowego Backwall." % [owner_label, structure_id],
		)
		_assert(
			interior.get_node_or_null("Label") == null,
			"%s/%s/InteriorVisual nie może zawierać bezwarunkowego Label PROXY." % [owner_label, structure_id],
		)
	if structure_visual != null:
		_assert(str(structure_visual.get_meta("logical_layer_id", "")) == "L05", "%s/%s/StructureVisual musi publikować L05." % [owner_label, structure_id])
	_assert(static_collision != null, "%s/%s musi zawierać StaticCollision:StaticBody2D." % [owner_label, structure_id])
	_assert(dynamic_bodies != null, "%s/%s musi zawierać DynamicBodies:Node2D." % [owner_label, structure_id])
	_assert(interactives != null, "%s/%s musi zawierać Interactives:Node2D." % [owner_label, structure_id])
	_assert_structure_visual_assets(interior, structure_visual, structure_assets, structure_id, owner_label)
	_assert_structure_runtime_lifecycle(dynamic_bodies, instance, owner_label)
	for local_root in [interior, structure_visual, static_collision, dynamic_bodies, interactives]:
		if local_root is Node2D:
			var local_root_2d := local_root as Node2D
			_assert(
				local_root_2d.position == Vector2.ZERO
				and is_zero_approx(local_root_2d.rotation)
				and local_root_2d.scale == Vector2.ONE,
				"%s/%s child roots muszą mieć identity transform." % [owner_label, structure_id],
			)
	if static_collision != null:
		_assert(static_collision.collision_layer != 0, "%s/%s/StaticCollision musi należeć do fizyki świata." % [owner_label, structure_id])
		var collision_children := static_collision.get_children()
		var collision_shapes: Array[CollisionShape2D] = []
		for collision_child in collision_children:
			if collision_child is CollisionShape2D:
				collision_shapes.append(collision_child as CollisionShape2D)
		_assert(collision_shapes.size() == 1, "%s/%s/StaticCollision musi mieć dokładnie jeden CollisionShape2D." % [owner_label, structure_id])
		if owner_label == "scena":
			_assert(collision_children.size() == 1, "%s/%s/StaticCollision nie może wypiekać dodatkowych dzieci runtime." % [owner_label, structure_id])
		if collision_shapes.size() == 1:
			var collision_shape := collision_shapes[0]
			_assert(collision_shape != null, "%s/%s/StaticCollision child musi być CollisionShape2D." % [owner_label, structure_id])
			if collision_shape != null:
				_assert(
					collision_shape.position == Vector2.ZERO
					and is_zero_approx(collision_shape.rotation)
					and collision_shape.scale == Vector2.ONE,
					"%s/%s shape musi mieć identity transform." % [owner_label, structure_id],
				)
				_assert(collision_shape.shape is ConcavePolygonShape2D, "%s/%s shape musi być ConcavePolygonShape2D." % [owner_label, structure_id])
				if collision_shape.shape is ConcavePolygonShape2D:
					var actual_boundary_set := _world_segment_set_from_shape(
						collision_shape,
						collision_shape.shape as ConcavePolygonShape2D,
					)
					_assert_segment_sets_equal(
						actual_boundary_set,
						expected_boundary_set,
						"%s/%s local collider" % [owner_label, structure_id],
					)
	_assert_structure_root_moves_as_group(structure_root, instance, static_collision, owner_label)


func _structure_visual_assets(manifest: Dictionary, structure_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var visual: Dictionary = manifest.get("visual", {})
	for asset_value in visual.get("assets", []):
		if not asset_value is Dictionary:
			continue
		var asset := asset_value as Dictionary
		if (
			str(asset.get("structure_id", "")) == structure_id
			and str(asset.get("kind", "")) in [
				"structure_interior_texture", "structure_owner_masked_texture",
			]
		):
			result.append(asset)
	return result


func _assert_structure_visual_assets(
	interior: Node2D,
	structure_visual: Node2D,
	structure_assets: Array[Dictionary],
	structure_id: String,
	owner_label: String,
) -> void:
	for layer_id in ["L04", "L05"]:
		var local_root := interior if layer_id == "L04" else structure_visual
		if local_root == null:
			continue
		var expected_groups: Array[Dictionary] = []
		for asset in structure_assets:
			if str(asset.get("layer_id", "")) != layer_id:
				continue
			var group_id := str(asset.get("group_id", ""))
			var group_record: Dictionary = {}
			for candidate in expected_groups:
				if str(candidate.get("id", "")) == group_id:
					group_record = candidate
					break
			if group_record.is_empty():
				group_record = {"id": group_id, "assets": []}
				expected_groups.append(group_record)
			(group_record["assets"] as Array).append(asset)
		var actual_groups: Array[Node] = []
		for child in local_root.get_children():
			if child.has_meta("group_id"):
				actual_groups.append(child)
		if layer_id == "L04":
			_assert(
				local_root.get_child_count() == actual_groups.size(),
				"%s/%s/InteriorVisual może zawierać wyłącznie manifestowe grupy assetów."
				% [owner_label, structure_id],
			)
		_assert(
			actual_groups.size() == expected_groups.size(),
			"%s/%s/%s musi wyprowadzać grupy structure-local z visual.assets."
			% [owner_label, structure_id, str(local_root.name)],
		)
		for group_index in range(mini(actual_groups.size(), expected_groups.size())):
			var group_node := actual_groups[group_index]
			var expected_group := expected_groups[group_index]
			var group_id := str(expected_group.get("id", ""))
			_assert(group_node is Node2D, "%s/%s/%s grupa %s musi być Node2D." % [owner_label, structure_id, layer_id, group_id])
			_assert(str(group_node.get_meta("group_id", "")) == group_id, "%s/%s grupa assetów ma niepoprawne group_id." % [owner_label, structure_id])
			_assert(str(group_node.get_meta("layer_id", "")) == layer_id, "%s/%s grupa assetów ma niepoprawne layer_id." % [owner_label, structure_id])
			_assert(str(group_node.get_meta("structure_id", "")) == structure_id, "%s/%s grupa assetów ma niepoprawne structure_id." % [owner_label, structure_id])
			if group_node is Node2D:
				var group_2d := group_node as Node2D
				_assert(group_2d.position == Vector2.ZERO and group_2d.scale == Vector2.ONE and is_zero_approx(group_2d.rotation), "%s/%s grupa assetów musi zachować identity transform." % [owner_label, structure_id])
			var expected_assets: Array = expected_group.get("assets", [])
			_assert(group_node.get_child_count() == expected_assets.size(), "%s/%s grupa %s ma niepoprawną liczbę assetów." % [owner_label, structure_id, group_id])
			for asset_index in range(mini(group_node.get_child_count(), expected_assets.size())):
				_assert_structure_local_asset_node(
					group_node.get_child(asset_index),
					expected_assets[asset_index] as Dictionary,
					structure_id,
					owner_label,
				)


func _assert_structure_local_asset_node(
	asset_node: Node,
	asset: Dictionary,
	structure_id: String,
	owner_label: String,
) -> void:
	var asset_id := str(asset.get("id", ""))
	var local_rect := _rect(asset.get("local_rect", []))
	var pixel_size_value := _vector(asset.get("pixel_size", []))
	var pixel_size := Vector2i(int(pixel_size_value.x), int(pixel_size_value.y))
	_assert(asset_node is Node2D, "%s/%s asset %s musi być Node2D." % [owner_label, structure_id, asset_id])
	if asset_node is Node2D:
		var asset_2d := asset_node as Node2D
		_assert(asset_2d.position == local_rect.position, "%s/%s asset %s musi używać local_rect.position." % [owner_label, structure_id, asset_id])
		_assert(asset_2d.scale == Vector2.ONE and is_zero_approx(asset_2d.rotation), "%s/%s asset %s nie może być skalowany ani obracany." % [owner_label, structure_id, asset_id])
		_assert(asset_2d.visible == bool(asset.get("enabled", true)), "%s/%s asset %s musi zachować enabled." % [owner_label, structure_id, asset_id])
	for metadata_key in ["asset_id", "structure_id", "layer_id", "group_id", "kind", "topology_digest", "partition_digest"]:
		var source_key: String = "id" if metadata_key == "asset_id" else str(metadata_key)
		_assert(
			asset_node.get_meta(metadata_key, null) == asset.get(source_key, null),
			"%s/%s asset %s ma nieaktualne metadata %s."
			% [owner_label, structure_id, asset_id, metadata_key],
		)
	_assert(asset_node.get_meta("local_rect", Rect2()) == local_rect, "%s/%s asset %s musi publikować local_rect." % [owner_label, structure_id, asset_id])
	_assert(asset_node.get_meta("pixel_size", Vector2i.ZERO) == pixel_size, "%s/%s asset %s musi publikować pixel_size." % [owner_label, structure_id, asset_id])
	_assert(_manifest_value_matches(asset, asset_node.get_meta("source", {})), "%s/%s asset %s musi publikować source 1:1." % [owner_label, structure_id, asset_id])
	_assert(asset_node.get_child_count() == 1, "%s/%s asset %s musi zawierać tylko Bitmap." % [owner_label, structure_id, asset_id])
	var bitmap := asset_node.get_node_or_null("Bitmap") as TextureRect
	_assert(bitmap != null, "%s/%s asset %s wymaga Bitmap:TextureRect." % [owner_label, structure_id, asset_id])
	if bitmap == null:
		return
	_assert(bitmap.scale == Vector2.ONE, "%s/%s Bitmap %s nie może być skalowany." % [owner_label, structure_id, asset_id])
	_assert(_control_local_rect(bitmap) == Rect2(Vector2.ZERO, local_rect.size), "%s/%s Bitmap %s musi zachować natywny local_rect." % [owner_label, structure_id, asset_id])
	_assert(bitmap.texture != null and bitmap.texture.get_size() == Vector2(pixel_size), "%s/%s Bitmap %s musi mapować PNG 1:1." % [owner_label, structure_id, asset_id])
	var material := bitmap.material as ShaderMaterial
	_assert(material != null and material.shader != null, "%s/%s Bitmap %s musi używać maskującego ShaderMaterial." % [owner_label, structure_id, asset_id])
	if material == null or material.shader == null:
		return
	_assert(
		material.shader.resource_path == "res://underwater_map_workbench/assets/shaders/structure_clip_masked.gdshader",
		"%s/%s Bitmap %s musi używać kanonicznego shadera struktury." % [owner_label, structure_id, asset_id],
	)
	var expected_mask_name := (
		"open_water_mask_native.png"
		if str(asset.get("kind", "")) == "structure_interior_texture"
		else "solid_mask_native.png"
	)
	var clip_mask := material.get_shader_parameter("clip_mask") as Texture2D
	var surface_detail_mask := material.get_shader_parameter("surface_detail_mask") as Texture2D
	var expected_mask_path := "res://underwater_map_workbench/structures/%s/generated/%s" % [structure_id, expected_mask_name]
	var expected_surface_detail_path := (
		"res://underwater_map_workbench/structures/%s/generated/surface_detail_mask_local.png"
		% structure_id
	)
	_assert(clip_mask != null and clip_mask.resource_path == expected_mask_path, "%s/%s Bitmap %s ma niepoprawną lokalną maskę klipowania." % [owner_label, structure_id, asset_id])
	_assert(material.get_shader_parameter("local_rect_origin") == local_rect.position, "%s/%s Bitmap %s ma niepoprawny local_rect_origin." % [owner_label, structure_id, asset_id])
	_assert(material.get_shader_parameter("local_rect_size") == local_rect.size, "%s/%s Bitmap %s ma niepoprawny local_rect_size." % [owner_label, structure_id, asset_id])
	var structure_root: Node = asset_node.get_parent().get_parent().get_parent()
	var structure_size: Vector2 = structure_root.get_meta("size", Vector2.ZERO) if structure_root != null else Vector2.ZERO
	_assert(material.get_shader_parameter("structure_size") == structure_size, "%s/%s Bitmap %s ma niepoprawny structure_size." % [owner_label, structure_id, asset_id])
	var detail_enabled := str(asset.get("kind", "")) == "structure_owner_masked_texture"
	_assert(
		bool(material.get_shader_parameter("detail_enabled")) == detail_enabled,
		"%s/%s Bitmap %s ma niepoprawny przełącznik detalu L05."
		% [owner_label, structure_id, asset_id],
	)
	_assert(
		surface_detail_mask != null
		and surface_detail_mask.resource_path == expected_surface_detail_path
		and surface_detail_mask.get_size() == structure_size / L05_CELL_SIZE,
		"%s/%s Bitmap %s musi wskazywać package-local crop detalu L05."
		% [owner_label, structure_id, asset_id],
	)
	_assert(
		material.get_shader_parameter("world_size") == Vector2(23040.0, 12960.0),
		"%s/%s Bitmap %s musi mapować detal do pełnego świata."
		% [owner_label, structure_id, asset_id],
	)
	_assert(
		material.get_shader_parameter("world_rect_origin") == (asset_node as Node2D).global_position,
		"%s/%s Bitmap %s musi mapować detal world-locked od globalnego początku assetu."
		% [owner_label, structure_id, asset_id],
	)


func _assert_structure_runtime_lifecycle(
	dynamic_bodies: Node2D,
	instance: Dictionary,
	owner_label: String,
) -> void:
	if dynamic_bodies == null:
		return
	var structure_id := str(instance.get("id", ""))
	var runtime_value = instance.get("runtime", null)
	if owner_label == "scena":
		_assert(
			dynamic_bodies.get_child_count() == 0,
			"%s/%s scena źródłowa nie może wypiekać aktywnego kontrolera pakietu."
			% [owner_label, structure_id],
		)
		return
	if not runtime_value is Dictionary or (runtime_value as Dictionary).is_empty():
		_assert(
			dynamic_bodies.get_child_count() == 0,
			"%s/%s bez payloadu runtime nie może montować kontrolera."
			% [owner_label, structure_id],
		)
		return
	_assert(
		dynamic_bodies.get_child_count() == 1,
		"%s/%s musi montować dokładnie jeden package-local kontroler runtime."
		% [owner_label, structure_id],
	)
	if dynamic_bodies.get_child_count() != 1:
		return
	var controller := dynamic_bodies.get_child(0)
	_assert(
		controller.has_method("configure") and controller.has_method("reset_attempt"),
		"%s/%s kontroler musi publikować publiczny lifecycle configure()/reset_attempt()."
		% [owner_label, structure_id],
	)
	var controller_script = controller.get_script()
	_assert(
		controller_script is Script
		and (controller_script as Script).resource_path == str(instance.get("controller_script", "")),
		"%s/%s musi montować controller_script wskazany przez rozwinięty pakiet."
		% [owner_label, structure_id],
	)


func _assert_structure_root_is_package_scene_instance(
	structure_root: Node2D,
	instance: Dictionary,
) -> void:
	var structure_id := str(instance.get("id", ""))
	var scene_path := str(instance.get("structure_scene_path", ""))
	var expected_scene_path := (
		"res://underwater_map_workbench/structures/%s/generated/structure.tscn"
		% structure_id
	)
	_assert(scene_path == expected_scene_path, "Instancja %s musi wskazywać package PackedScene." % structure_id)
	_assert(
		structure_root.scene_file_path == scene_path,
		"Mapowy StructureRoots/%s musi być instancją package PackedScene, nie kopią węzłów."
		% structure_id,
	)
	var packed_scene := ResourceLoader.load(
		scene_path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE,
	) as PackedScene
	_assert(packed_scene != null, "Package PackedScene %s musi się ładować." % structure_id)
	if packed_scene == null:
		return
	var package_root := packed_scene.instantiate() as Node2D
	_assert(package_root != null, "Package PackedScene %s musi mieć root Node2D." % structure_id)
	if package_root == null:
		return
	_assert(
		package_root.position == Vector2.ZERO
		and is_zero_approx(package_root.rotation)
		and package_root.scale == Vector2.ONE,
		"Package-local scene %s musi zachować identity root." % structure_id,
	)
	_assert(
		package_root.scene_file_path == scene_path,
		"Bezpośrednia instancja package scene %s musi zachować scene_file_path." % structure_id,
	)
	_assert(
		package_root.get_child_count() == structure_root.get_child_count(),
		"Mapowa instancja %s musi zachować pełną hierarchię package scene." % structure_id,
	)
	for child_index in range(mini(package_root.get_child_count(), structure_root.get_child_count())):
		var package_child := package_root.get_child(child_index)
		var map_child := structure_root.get_child(child_index)
		_assert(
			package_child.name == map_child.name and package_child.get_class() == map_child.get_class(),
			"Mapowa instancja %s musi zachować package-local child identity." % structure_id,
		)
		if package_child is Node2D and map_child is Node2D:
			_assert(
				(package_child as Node2D).transform == (map_child as Node2D).transform,
				"Mapowa instancja %s nie może nadpisywać lokalnych child transformów package scene."
				% structure_id,
			)
	package_root.free()


func _assert_structure_root_moves_as_group(
	structure_root: Node2D,
	instance: Dictionary,
	static_collision: StaticBody2D,
	owner_label: String,
) -> void:
	var sockets: Array = instance.get("sockets", [])
	if sockets.is_empty() or static_collision == null:
		return
	var collision_shape := static_collision.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape == null or not collision_shape.shape is ConcavePolygonShape2D:
		return
	var segments := (collision_shape.shape as ConcavePolygonShape2D).segments
	if segments.is_empty():
		return
	var first_socket := sockets[0] as Dictionary
	var socket_center := _rect(first_socket.get("local_rect", [])).get_center()
	var original_root_position := structure_root.position
	var original_collision_point := (
		structure_root.transform
		* static_collision.transform
		* collision_shape.transform
		* segments[0]
	)
	var original_socket_center := structure_root.transform * socket_center
	var child_transforms := {}
	for child in structure_root.get_children():
		if child is Node2D:
			child_transforms[child] = (child as Node2D).transform
	var delta := Vector2(80.0, -40.0)
	structure_root.position += delta
	var moved_collision_point := (
		structure_root.transform
		* static_collision.transform
		* collision_shape.transform
		* segments[0]
	)
	_assert(
		moved_collision_point.is_equal_approx(original_collision_point + delta),
		"%s/%s collider musi przesuwać się dokładnie z rootem struktury."
		% [owner_label, str(instance.get("id", ""))],
	)
	_assert(
		(structure_root.transform * socket_center).is_equal_approx(original_socket_center + delta),
		"%s/%s sockety muszą przesuwać się dokładnie z rootem struktury."
		% [owner_label, str(instance.get("id", ""))],
	)
	for child_value in child_transforms:
		var child := child_value as Node2D
		_assert(
			child.transform == child_transforms[child_value],
			"%s/%s lokalne transformy dzieci nie mogą zmieniać się przy przesunięciu rootu."
			% [owner_label, str(instance.get("id", ""))],
		)
	structure_root.position = original_root_position


func _assert_runtime_structure_partition(
	runtime: Node,
	manifest: Dictionary,
	navigation_base: Dictionary,
) -> void:
	var runtime_structure_roots := runtime.get_node_or_null("RuntimeDynamic/StructureRoots")
	_assert_structure_roots(runtime_structure_roots, manifest, navigation_base, "runtime")
	var expected_by_owner := _expected_boundary_sets_by_owner(navigation_base)
	var expected_world: Dictionary = expected_by_owner.get(WORLD_COLLISION_OWNER_ID, {})
	var expected_structure_union := {}
	for owner_id in expected_by_owner:
		if str(owner_id) in ["", WORLD_COLLISION_OWNER_ID]:
			continue
		_merge_segment_set(expected_structure_union, expected_by_owner[owner_id] as Dictionary)
	var runtime_global := _runtime_global_segment_set(runtime)
	_assert_segment_sets_equal(runtime_global, expected_world, "runtime global collision")
	var runtime_local := {}
	if runtime_structure_roots != null:
		for collision_shape in runtime_structure_roots.find_children("*", "CollisionShape2D", true, false):
			if collision_shape is CollisionShape2D and (collision_shape as CollisionShape2D).shape is ConcavePolygonShape2D:
				_merge_segment_set(
					runtime_local,
					_world_segment_set_from_shape(
						collision_shape as CollisionShape2D,
						(collision_shape as CollisionShape2D).shape as ConcavePolygonShape2D,
					),
				)
	_assert_segment_sets_equal(runtime_local, expected_structure_union, "runtime local structure collision")
	for segment_key in runtime_local:
		_assert(not runtime_global.has(segment_key), "Globalny i lokalny collider muszą mieć rozłączne segmenty: %s." % segment_key)
	var runtime_union := runtime_global.duplicate()
	_merge_segment_set(runtime_union, runtime_local)
	var expected_union := {}
	for owner_id in expected_by_owner:
		if str(owner_id).is_empty():
			continue
		_merge_segment_set(expected_union, expected_by_owner[owner_id] as Dictionary)
	_assert_segment_sets_equal(runtime_union, expected_union, "runtime union pełnych boundaries L05")
	if runtime.has_method("collision_segment_count"):
		_assert(int(runtime.call("collision_segment_count")) == expected_union.size(), "collision_segment_count musi obejmować dokładną unię global+structure.")


func _expected_boundary_sets_by_owner(navigation_base: Dictionary) -> Dictionary:
	var result := {}
	var width := int(navigation_base.get("width", 0))
	var height := int(navigation_base.get("height", 0))
	var cell_scale: Vector2 = navigation_base.get("cell_scale", Vector2.ONE)
	var cells: PackedByteArray = navigation_base.get("cells", PackedByteArray())
	var owner_ids: PackedStringArray = navigation_base.get("owner_ids", PackedStringArray())
	var owner_cells: PackedInt32Array = navigation_base.get("solid_owner_cells", PackedInt32Array())
	for owner_id in owner_ids:
		result[str(owner_id)] = {}
	if not result.has(WORLD_COLLISION_OWNER_ID):
		result[WORLD_COLLISION_OWNER_ID] = {}
	if cells.size() != width * height or owner_cells.size() != cells.size():
		return result
	var directions := [
		[Vector2i(0, -1), Vector2(0, 0), Vector2(1, 0)],
		[Vector2i(1, 0), Vector2(1, 0), Vector2(1, 1)],
		[Vector2i(0, 1), Vector2(1, 1), Vector2(0, 1)],
		[Vector2i(-1, 0), Vector2(0, 1), Vector2(0, 0)],
	]
	for y in range(height):
		for x in range(width):
			var cell_index := y * width + x
			if int(cells[cell_index]) == 0:
				continue
			for direction_value in directions:
				var direction := direction_value[0] as Vector2i
				var neighbor := Vector2i(x, y) + direction
				var outside := neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= width or neighbor.y >= height
				var owner_index := WORLD_OWNER_INDEX
				if not outside:
					var neighbor_index := neighbor.y * width + neighbor.x
					if int(cells[neighbor_index]) != 0:
						continue
					owner_index = int(owner_cells[neighbor_index])
				if owner_index <= OPEN_WATER_OWNER_INDEX or owner_index >= owner_ids.size():
					_assert(false, "Boundary L05 musi wskazywać poprawnego ownera.")
					continue
				var owner_id := str(owner_ids[owner_index])
				var cell_origin := Vector2(x * cell_scale.x, y * cell_scale.y)
				var from_point := cell_origin + (direction_value[1] as Vector2) * cell_scale
				var to_point := cell_origin + (direction_value[2] as Vector2) * cell_scale
				(result[owner_id] as Dictionary)[_segment_key(from_point, to_point)] = true
	return result


func _runtime_global_segment_set(runtime: Node) -> Dictionary:
	var result := {}
	var chunks_value = runtime.get("_collision_segments_by_chunk")
	_assert(chunks_value is Dictionary, "Runtime musi przechowywać globalne boundary segments per chunk.")
	if not chunks_value is Dictionary:
		return result
	for segments_value in (chunks_value as Dictionary).values():
		if not segments_value is PackedVector2Array:
			continue
		var segments := segments_value as PackedVector2Array
		_assert(segments.size() % 2 == 0, "Globalne segmenty kolizji muszą tworzyć pary.")
		for index in range(0, segments.size() - 1, 2):
			var segment_key := _segment_key(segments[index], segments[index + 1])
			_assert(not result.has(segment_key), "Globalny segment kolizji nie może występować dwukrotnie: %s." % segment_key)
			result[segment_key] = true
	return result


func _world_segment_set_from_shape(
	collision_shape: CollisionShape2D,
	shape: ConcavePolygonShape2D,
) -> Dictionary:
	var result := {}
	var segments := shape.segments
	_assert(segments.size() > 0 and segments.size() % 2 == 0, "ConcavePolygonShape2D musi publikować niepuste pary segmentów.")
	for index in range(0, segments.size() - 1, 2):
		var from_point := collision_shape.to_global(segments[index])
		var to_point := collision_shape.to_global(segments[index + 1])
		var segment_key := _segment_key(from_point, to_point)
		_assert(not result.has(segment_key), "Lokalny shape nie może dublować segmentu %s." % segment_key)
		result[segment_key] = true
	return result


func _segment_key(from_point: Vector2, to_point: Vector2) -> String:
	var first := Vector2(roundf(from_point.x), roundf(from_point.y))
	var second := Vector2(roundf(to_point.x), roundf(to_point.y))
	if first.x > second.x or (is_equal_approx(first.x, second.x) and first.y > second.y):
		var swap := first
		first = second
		second = swap
	return "%d,%d|%d,%d" % [int(first.x), int(first.y), int(second.x), int(second.y)]


func _merge_segment_set(target: Dictionary, source: Dictionary) -> void:
	for segment_key in source:
		_assert(not target.has(segment_key), "Segment kolizji nie może należeć do dwóch ownerów: %s." % segment_key)
		target[segment_key] = true


func _assert_segment_sets_equal(actual: Dictionary, expected: Dictionary, label: String) -> void:
	_assert(actual.size() == expected.size(), "%s ma %d segmentów zamiast %d." % [label, actual.size(), expected.size()])
	for segment_key in expected:
		if not actual.has(segment_key):
			_assert(false, "%s nie zawiera segmentu %s." % [label, segment_key])
			return


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
				var expected_world_position := _resolved_manifest_world_position(source_record, manifest)
				_assert(
					record_node is Node2D and (record_node as Node2D).position == expected_world_position,
					"Kolekcja %s[%d] musi publikować rozwiązaną pozycję świata." % [collection_name, index],
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
	_assert_record_sequence(
		(manifest.get("structures", {}) as Dictionary).get("instances", []),
		blueprint.structure_spawns,
		"structures.instances",
	)
	_assert_structure_blueprint_envelopes(blueprint.structure_spawns)

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


func _assert_structure_blueprint_envelopes(structure_spawns: Array[Dictionary]) -> void:
	for structure in structure_spawns:
		var structure_id := str(structure.get("id", ""))
		_assert(not structure_id.is_empty(), "Każda struktura blueprintu musi zachować stable ID registry.")
		_assert(
			structure.get("runtime", null) is Dictionary,
			"Blueprint struktury %s musi zachować nieprzezroczysty słownik runtime pakietu."
			% structure_id,
		)
		_assert(
			str(structure.get("controller_script", "")).begins_with(
				"res://underwater_map_workbench/structures/%s/" % structure_id
			),
			"Blueprint struktury %s musi zachować package-local controller_script."
			% structure_id,
		)
		for socket_value in structure.get("sockets", []):
			if socket_value is Dictionary:
				_assert(
					(socket_value as Dictionary).get("local_rect", null) is Rect2,
					"Blueprint struktury %s musi dekodować socket.local_rect do Rect2."
					% structure_id,
				)


func _assert_archive_campaign_is_global(blueprint, manifest: Dictionary) -> void:
	var source_archive := _record_by_id(
		manifest.get("landmarks", []) as Array,
		"flooded_archive",
	)
	_assert(not source_archive.is_empty(), "Manifest musi publikować flooded_archive.")
	if not source_archive.is_empty():
		_assert(not source_archive.has("position_space"), "flooded_archive nie może dziedziczyć przestrzeni lokalnej struktury.")
		_assert(not source_archive.has("structure_id"), "flooded_archive nie może wskazywać lokalnej struktury.")
	var source_terminal := _record_by_id(
		(manifest.get("gameplay", {}) as Dictionary).get("fixed_device_spawns", []) as Array,
		"archive_terminal",
	)
	_assert(not source_terminal.is_empty(), "Manifest musi publikować archive_terminal.")
	if not source_terminal.is_empty():
		_assert(not source_terminal.has("position_space"), "Globalny archive_terminal nie może publikować position_space override.")
		_assert(not source_terminal.has("structure_id"), "archive_terminal nie może wskazywać lokalnej struktury.")
		_assert(not source_terminal.has("local_position"), "Manifest nie może utrzymywać drugiej lokalnej pozycji archive_terminal.")
	var compiled_archive: Dictionary = blueprint.get_landmark("flooded_archive")
	_assert(not compiled_archive.is_empty(), "Blueprint musi zawierać flooded_archive.")
	if not compiled_archive.is_empty() and not source_archive.is_empty():
		_assert(
			_vector(compiled_archive.get("position", [])) == _vector(source_archive.get("position", [])),
			"Blueprint musi wyprowadzać globalną pozycję flooded_archive z manifestu.",
		)
	var compiled_terminal := _record_by_id(blueprint.fixed_device_spawns, "archive_terminal")
	_assert(not compiled_terminal.is_empty(), "Blueprint musi zawierać archive_terminal.")
	if compiled_terminal.is_empty():
		return
	_assert(str(compiled_terminal.get("position_space", "")) == "world", "Blueprint musi jawnie znormalizować archive_terminal do world.")
	_assert(str(compiled_terminal.get("structure_id", "")).is_empty(), "Blueprint archive_terminal nie może wskazywać lokalnej struktury.")
	_assert(not compiled_terminal.has("local_position"), "Blueprint globalnego archive_terminal nie może tworzyć local_position.")
	if not source_terminal.is_empty():
		_assert(
			_vector(compiled_terminal.get("position", [])) == _vector(source_terminal.get("position", [])),
			"Blueprint musi wyprowadzać globalną pozycję archive_terminal z manifestu.",
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
		if key == "position" and str(source.get("position_space", "world")) == "structure_local":
			_assert(compiled.has("local_position"), "%s nie zachował lokalnej pozycji manifestu." % label)
			if compiled.has("local_position"):
				_assert(
					_manifest_value_matches(source[key], compiled["local_position"]),
					"%s.local_position różni się od lokalnej pozycji manifestu." % label,
				)
			continue
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


func _assert_portal_backdrop_clearances(
	visual_layers: Node2D,
	manifest: Dictionary,
	navigation_base: Dictionary,
	owner_label: String,
) -> void:
	var host_layer := visual_layers.get_node_or_null(
		PORTAL_BACKDROP_CLEARANCE_HOST_LAYER_ID
	) as Node2D
	_assert(host_layer != null, "%s musi zawierać host L04 clearance wejść." % owner_label)
	if host_layer == null:
		return
	var clearance_root := host_layer.get_node_or_null(
		"PortalBackdropClearances"
	) as Node2D
	_assert(
		clearance_root != null,
		"%s musi publikować typowany PortalBackdropClearances." % owner_label,
	)
	if clearance_root == null:
		return
	_assert(
		clearance_root.position == Vector2.ZERO
		and is_zero_approx(clearance_root.rotation)
		and clearance_root.scale == Vector2.ONE,
		"%s PortalBackdropClearances musi zachować identity transform." % owner_label,
	)
	_assert(
		not clearance_root.z_as_relative,
		"%s PortalBackdropClearances musi mieć absolutny world-locked z-index." % owner_label,
	)
	var layers_by_id := {}
	for layer_value: Variant in (manifest.get("visual", {}) as Dictionary).get("layers", []):
		if layer_value is Dictionary:
			var layer := layer_value as Dictionary
			layers_by_id[str(layer.get("id", ""))] = layer
	var backdrop_z := -2_147_483_648
	for layer_id: String in PORTAL_BACKDROP_CLEARANCE_OCCLUDED_LAYER_IDS:
		var layer: Dictionary = layers_by_id.get(layer_id, {})
		backdrop_z = maxi(backdrop_z, int(layer.get("z_index", backdrop_z)))
	var host_record: Dictionary = layers_by_id.get(
		PORTAL_BACKDROP_CLEARANCE_HOST_LAYER_ID,
		{},
	)
	_assert(
		clearance_root.z_index > backdrop_z
		and clearance_root.z_index < int(host_record.get("z_index", 0)),
		"%s PortalBackdropClearances musi być nad L01/L02 i pod L04." % owner_label,
	)
	_assert(
		str(clearance_root.get_meta("contract", ""))
		== PORTAL_BACKDROP_CLEARANCE_CONTRACT,
		"%s PortalBackdropClearances ma nieaktualny kontrakt." % owner_label,
	)
	_assert(
		str(clearance_root.get_meta("role", "")) == "portal_backdrop_clearance"
		and str(clearance_root.get_meta("space", "")) == "world_locked"
		and bool(clearance_root.get_meta("visual_only", false)),
		"%s PortalBackdropClearances musi być typowanym visual-only world-locked rootem."
		% owner_label,
	)
	_assert(
		clearance_root.get_meta("occluded_layer_ids", PackedStringArray())
		== PackedStringArray(PORTAL_BACKDROP_CLEARANCE_OCCLUDED_LAYER_IDS)
		and str(clearance_root.get_meta("host_layer_id", ""))
		== PORTAL_BACKDROP_CLEARANCE_HOST_LAYER_ID,
		"%s PortalBackdropClearances może zasłaniać wyłącznie L01/L02 pod L04."
		% owner_label,
	)
	_assert(
		int(clearance_root.get_meta("normal_core_cells", 0))
		== PORTAL_BACKDROP_CLEARANCE_NORMAL_CORE_CELLS
		and int(clearance_root.get_meta("tangent_padding_cells", 0))
		== PORTAL_BACKDROP_CLEARANCE_TANGENT_PADDING_CELLS
		and int(clearance_root.get_meta("feather_cells", 0))
		== PORTAL_BACKDROP_CLEARANCE_FEATHER_CELLS,
		"%s PortalBackdropClearances musi mieć ograniczony padding i feather." % owner_label,
	)

	var expected_openings := {}
	var structures: Dictionary = manifest.get("structures", {})
	for instance_value: Variant in structures.get("instances", []):
		if not instance_value is Dictionary:
			continue
		var instance := instance_value as Dictionary
		if not bool(instance.get("enabled", false)):
			continue
		var bounds := Rect2(
			_vector(instance.get("origin", [])),
			_vector(instance.get("size", [])),
		)
		var openings: Array[Dictionary] = VisualSurveyPlanScript._detect_structure_openings(
			bounds,
			navigation_base,
		)
		for opening: Dictionary in openings:
			var opening_key := _portal_opening_key(
				opening.get("center", Vector2.ZERO) as Vector2,
				opening.get("outward", Vector2.ZERO) as Vector2,
				float(opening.get("span", 0.0)),
			)
			expected_openings[opening_key] = int(expected_openings.get(opening_key, 0)) + 1
	var expected_count := 0
	for count_value: Variant in expected_openings.values():
		expected_count += int(count_value)
	_assert(expected_count > 0, "%s musi wyprowadzić co najmniej jeden otwór struktury." % owner_label)
	_assert(
		clearance_root.get_child_count() == expected_count
		and int(clearance_root.get_meta("clearance_count", -1)) == expected_count,
		"%s musi publikować dokładnie jeden clearance na raster-derived opening run."
		% owner_label,
	)

	var cell_scale: Vector2 = navigation_base.get("cell_scale", Vector2.ONE)
	var geometry_records: Array = []
	var previous_digest := ""
	var expected_visual_children := PackedStringArray([
		"Core", "FeatherLeft", "FeatherRight", "FeatherTop", "FeatherBottom",
	])
	var expected_water_color := Color.from_string(
		"#%s" % str((manifest.get("visual", {}) as Dictionary).get("water_color", "")),
		Color.TRANSPARENT,
	)
	for clearance_value: Node in clearance_root.get_children():
		_assert(clearance_value is Node2D, "%s clearance musi być Node2D." % owner_label)
		if not clearance_value is Node2D:
			continue
		var clearance := clearance_value as Node2D
		var geometry_digest := str(clearance.get_meta("geometry_digest", ""))
		_assert(
			_valid_lower_sha256(geometry_digest),
			"%s clearance wymaga poprawnego geometry_digest." % owner_label,
		)
		_assert(
			previous_digest.is_empty() or geometry_digest > previous_digest,
			"%s clearance musi zachować deterministyczną kolejność digestów." % owner_label,
		)
		previous_digest = geometry_digest
		_assert(
			str(clearance.name) == "Clearance_%s" % geometry_digest,
			"%s clearance nie może używać prywatnego ID w nazwie." % owner_label,
		)
		var geometry_value: Variant = clearance.get_meta("source_geometry", null)
		_assert(geometry_value is Dictionary, "%s clearance wymaga source_geometry." % owner_label)
		if not geometry_value is Dictionary:
			continue
		var geometry := geometry_value as Dictionary
		_assert(
			_dictionary_has_only_keys(geometry, [
				"contract", "axis", "boundary_cell", "run_start_cell", "run_end_cell",
				"outward_cell", "cell_size",
			]),
			"%s clearance source_geometry nie może zawierać ID, ścieżki ani nazwy pakietu."
			% owner_label,
		)
		_assert(
			str(geometry.get("contract", "")) == PORTAL_BACKDROP_CLEARANCE_CONTRACT
			and JSON.stringify(geometry, "", true, true).sha256_text().to_lower()
			== geometry_digest,
			"%s clearance digest musi wynikać wyłącznie z anonimowej geometrii."
			% owner_label,
		)
		geometry_records.append(geometry.duplicate(true))
		var opening_center: Vector2 = clearance.get_meta("opening_center", Vector2(INF, INF))
		var outward: Vector2 = clearance.get_meta("outward", Vector2.ZERO)
		var span := float(clearance.get_meta("span", 0.0))
		var opening_key := _portal_opening_key(opening_center, outward, span)
		var remaining := int(expected_openings.get(opening_key, 0))
		_assert(
			remaining > 0,
			"%s clearance musi odpowiadać raster-derived traversable boundary run."
			% owner_label,
		)
		if remaining > 0:
			expected_openings[opening_key] = remaining - 1
		var core_rect: Rect2 = clearance.get_meta("core_rect", Rect2())
		var outer_rect: Rect2 = clearance.get_meta("outer_rect", Rect2())
		_assert(
			core_rect.get_center().is_equal_approx(opening_center),
			"%s clearance core musi być wycentrowany na otworze." % owner_label,
		)
		if not outward.is_zero_approx() and absf(outward.x) > 0.0:
			_assert(
				is_equal_approx(
					core_rect.size.x,
					cell_scale.x * PORTAL_BACKDROP_CLEARANCE_NORMAL_CORE_CELLS * 2.0,
				)
				and is_equal_approx(
					core_rect.size.y,
					span + cell_scale.y * PORTAL_BACKDROP_CLEARANCE_TANGENT_PADDING_CELLS * 2.0,
				),
				"%s pionowy clearance ma nieograniczony core." % owner_label,
			)
		else:
			_assert(
				is_equal_approx(
					core_rect.size.y,
					cell_scale.y * PORTAL_BACKDROP_CLEARANCE_NORMAL_CORE_CELLS * 2.0,
				)
				and is_equal_approx(
					core_rect.size.x,
					span + cell_scale.x * PORTAL_BACKDROP_CLEARANCE_TANGENT_PADDING_CELLS * 2.0,
				),
				"%s poziomy clearance ma nieograniczony core." % owner_label,
			)
		_assert(
			outer_rect.position.is_equal_approx(
				core_rect.position - cell_scale * PORTAL_BACKDROP_CLEARANCE_FEATHER_CELLS
			)
			and outer_rect.size.is_equal_approx(
				core_rect.size + cell_scale * PORTAL_BACKDROP_CLEARANCE_FEATHER_CELLS * 2.0
			),
			"%s clearance feather musi mieć dokładnie ograniczony rasterowy margines."
			% owner_label,
		)
		_assert(bool(clearance.get_meta("visual_only", false)), "%s clearance musi być visual-only." % owner_label)
		var actual_visual_children := PackedStringArray()
		for visual_child: Node in clearance.get_children():
			actual_visual_children.append(str(visual_child.name))
			_assert(visual_child is Polygon2D, "%s clearance może zawierać wyłącznie Polygon2D." % owner_label)
			if visual_child is Polygon2D:
				var polygon := visual_child as Polygon2D
				_assert(polygon.polygon.size() == 4, "%s clearance polygon musi być quadem." % owner_label)
				_assert(polygon.color.is_equal_approx(expected_water_color), "%s clearance musi używać water_color." % owner_label)
		_assert(
			actual_visual_children == expected_visual_children,
			"%s clearance musi zawierać dokładnie Core i cztery Feathery." % owner_label,
		)
		var descendants: Array[Node] = [clearance]
		descendants.append_array(clearance.find_children("*", "", true, false))
		for descendant: Node in descendants:
			_assert(
				not (
					descendant is CollisionObject2D
					or descendant is CollisionShape2D
					or descendant is CollisionPolygon2D
				),
				"%s clearance nie może zawierać fizyki, Area2D ani stanu." % owner_label,
			)
	for remaining_value: Variant in expected_openings.values():
		_assert(int(remaining_value) == 0, "%s nie może pominąć traversable opening run." % owner_label)
	var aggregate_digest := JSON.stringify(geometry_records, "", true, true).sha256_text().to_lower()
	_assert(
		str(clearance_root.get_meta("geometry_digest", "")) == aggregate_digest,
		"%s PortalBackdropClearances aggregate digest musi odpowiadać geometrii."
		% owner_label,
	)


func _portal_opening_key(center: Vector2, outward: Vector2, span: float) -> String:
	return "%.3f,%.3f|%.0f,%.0f|%.3f" % [
		center.x, center.y, outward.x, outward.y, span,
	]


func _dictionary_has_only_keys(value: Dictionary, expected_keys: Array) -> bool:
	if value.size() != expected_keys.size():
		return false
	for key_value: Variant in expected_keys:
		if not value.has(str(key_value)):
			return false
	return true


func _valid_lower_sha256(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for index in range(value.length()):
		if not "0123456789abcdef".contains(value.substr(index, 1)):
			return false
	return true


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

	var expected_groups_by_layer := _expected_visual_groups_by_layer(manifest["visual"] as Dictionary)
	for layer_id in EXPECTED_LAYER_IDS:
		var layer_root := visual_layers.get_node_or_null(layer_id)
		if layer_root == null:
			continue
		var group_nodes: Array[Node] = []
		for child in layer_root.get_children():
			if child.has_meta("group_id"):
				group_nodes.append(child)
		var expected_groups: Array = expected_groups_by_layer.get(layer_id, [])
		_assert(
			group_nodes.size() == expected_groups.size(),
			"%s/%s musi wyprowadzać dokładnie grupy wynikające z visual.assets." % [owner_label, layer_id],
		)
		for group_index in range(mini(group_nodes.size(), expected_groups.size())):
			var group_node := group_nodes[group_index]
			var expected_group := expected_groups[group_index] as Dictionary
			_assert_visual_group_node(
				group_node,
				layer_id,
				str(expected_group.get("id", "")),
				expected_group.get("assets", []) as Array,
				owner_label,
			)


func _expected_visual_groups_by_layer(visual: Dictionary) -> Dictionary:
	var result := {}
	for layer_id in EXPECTED_LAYER_IDS:
		result[layer_id] = []
	for asset_value in visual.get("assets", []):
		if not asset_value is Dictionary:
			continue
		var asset := asset_value as Dictionary
		if str(asset.get("kind", "")) in [
			"structure_interior_texture", "structure_owner_masked_texture",
		]:
			continue
		var layer_id := str(asset.get("layer_id", ""))
		var group_id := str(asset.get("group_id", ""))
		if not result.has(layer_id):
			continue
		var groups := result[layer_id] as Array
		var expected_group: Dictionary = {}
		for group_value in groups:
			if group_value is Dictionary and str((group_value as Dictionary).get("id", "")) == group_id:
				expected_group = group_value as Dictionary
				break
		if expected_group.is_empty():
			expected_group = {"id": group_id, "assets": []}
			groups.append(expected_group)
		(expected_group["assets"] as Array).append(asset)
	return result


func _assert_visual_group_node(
	group_node: Node,
	layer_id: String,
	group_id: String,
	expected_assets: Array,
	owner_label: String,
) -> void:
	_assert(group_node is Node2D, "%s/%s/%s musi być neutralnym Node2D." % [owner_label, layer_id, group_id])
	_assert(str(group_node.name) == group_id, "%s/%s musi zachować nazwę grupy %s." % [owner_label, layer_id, group_id])
	_assert(not group_node.has_meta("asset_id"), "%s/%s/%s nie może udawać elementu." % [owner_label, layer_id, group_id])
	_assert(
		str(group_node.get_meta("group_id", "")) == group_id,
		"%s/%s/%s musi publikować group_id manifestu." % [owner_label, layer_id, group_id],
	)
	_assert(
		str(group_node.get_meta("layer_id", "")) == layer_id,
		"%s/%s/%s musi publikować layer_id manifestu." % [owner_label, layer_id, group_id],
	)
	if group_node is Node2D:
		var group_2d := group_node as Node2D
		_assert(group_2d.position == Vector2.ZERO, "%s/%s/%s musi mieć pozycję identity." % [owner_label, layer_id, group_id])
		_assert(group_2d.scale == Vector2.ONE, "%s/%s/%s nie może skalować elementów." % [owner_label, layer_id, group_id])
	var asset_nodes := group_node.get_children()
	_assert(
		asset_nodes.size() == expected_assets.size(),
		"%s/%s/%s musi zachować liczność elementów manifestu." % [owner_label, layer_id, group_id],
	)
	for index in range(mini(asset_nodes.size(), expected_assets.size())):
		var asset_node := asset_nodes[index]
		var source_asset := expected_assets[index] as Dictionary
		_assert(
			str(asset_node.get_meta("asset_id", "")) == str(source_asset.get("id", "")),
			"%s/%s/%s musi zachować kolejność elementów manifestu." % [owner_label, layer_id, group_id],
		)
		_assert(
			_manifest_value_matches(source_asset, asset_node.get_meta("source", {})),
			"%s/%s/%s asset musi zachować rekord source 1:1." % [owner_label, layer_id, group_id],
		)
		_assert_typed_asset_node(asset_node, source_asset, owner_label)


func _assert_typed_asset_node(asset_node: Node, source_asset: Dictionary, owner_label: String) -> void:
	var asset_id := str(source_asset.get("id", ""))
	var layer_id := str(source_asset.get("layer_id", ""))
	var group_id := str(source_asset.get("group_id", ""))
	var kind := str(source_asset.get("kind", ""))
	var expected_rect := _rect(source_asset.get("world_rect", []))
	var expected_pixel_size_value := _vector(source_asset.get("pixel_size", []))
	var expected_pixel_size := Vector2i(int(expected_pixel_size_value.x), int(expected_pixel_size_value.y))
	_assert(asset_node is Node2D, "%s asset %s musi mieć osobny root Node2D." % [owner_label, asset_id])
	if asset_node is Node2D:
		var element_root := asset_node as Node2D
		_assert(
			element_root.position == expected_rect.position,
			"%s asset %s musi brać pozycję z world_rect manifestu." % [owner_label, asset_id],
		)
		_assert(
			element_root.scale == Vector2.ONE,
			"%s asset %s nie może używać transformu skali." % [owner_label, asset_id],
		)
		_assert(element_root.visible == bool(source_asset.get("enabled", true)), "%s asset %s musi zachować enabled." % [owner_label, asset_id])
	_assert(str(asset_node.get_meta("layer_id", "")) == layer_id, "%s asset %s musi publikować layer_id." % [owner_label, asset_id])
	_assert(str(asset_node.get_meta("group_id", "")) == group_id, "%s asset %s musi publikować group_id." % [owner_label, asset_id])
	_assert(str(asset_node.get_meta("kind", "")) == kind, "%s asset %s musi publikować kind." % [owner_label, asset_id])
	_assert(asset_node.get_meta("world_rect", Rect2()) == expected_rect, "%s asset %s musi publikować world_rect 1:1." % [owner_label, asset_id])
	_assert(asset_node.get_meta("pixel_size", Vector2i.ZERO) == expected_pixel_size, "%s asset %s musi publikować pixel_size." % [owner_label, asset_id])
	if kind == "texture_rect":
		_assert(
			layer_id in NONBLOCKING_TEXTURE_LAYER_IDS,
			"%s asset %s texture_rect może należeć wyłącznie do L01 albo L02."
			% [owner_label, asset_id],
		)
		_assert(
			str(source_asset.get("affordance", "")) == NONBLOCKING_BACKDROP_AFFORDANCE,
			"%s asset %s na %s musi być nieblokującym tłem."
			% [owner_label, asset_id, layer_id],
		)
		_assert(asset_node.get_child_count() == 1, "%s asset %s texture_rect musi mieć tylko child Bitmap." % [owner_label, asset_id])
		var expected_resource_path := "res://underwater_map_workbench/%s" % str(source_asset.get("path", ""))
		_assert(
			str(asset_node.get_meta("residency_contract", "")) == STREAMED_BACKDROP_CONTRACT,
			"%s asset %s musi publikować kontrakt rezydencji okna kamery."
			% [owner_label, asset_id],
		)
		_assert(
			str(asset_node.get_meta("resource_path", "")) == expected_resource_path,
			"%s asset %s musi publikować kanoniczną ścieżkę źródła."
			% [owner_label, asset_id],
		)
		_assert(
			str(asset_node.get_meta("source_sha256", "")) == str(source_asset.get("sha256", "")),
			"%s asset %s musi publikować SHA źródła."
			% [owner_label, asset_id],
		)
		var bitmap_node := asset_node.get_node_or_null("Bitmap")
		_assert(bitmap_node is TextureRect, "%s asset %s na %s musi mieć child Bitmap:TextureRect." % [owner_label, asset_id, layer_id])
		if bitmap_node is TextureRect:
			var texture_rect := bitmap_node as TextureRect
			_assert(texture_rect.scale == Vector2.ONE, "%s bitmapa %s nie może być skalowana." % [owner_label, asset_id])
			_assert(
				_control_local_rect(texture_rect) == Rect2(Vector2.ZERO, expected_rect.size),
				"%s bitmapa %s musi zajmować natywny rect elementu." % [owner_label, asset_id],
			)
			_assert(
				texture_rect.texture == null,
				"%s asset %s musi pozostać pustym stubem do czasu selekcji okna kamery."
				% [owner_label, asset_id],
			)
			var source_texture := ResourceLoader.load(
				expected_resource_path,
				"Texture2D",
				ResourceLoader.CACHE_MODE_IGNORE,
			) as Texture2D
			_assert(source_texture != null, "%s źródło assetu %s musi być poprawną teksturą." % [owner_label, asset_id])
			if source_texture != null:
				_assert(
					expected_rect.size == source_texture.get_size()
					and source_texture.get_size() == _vector(source_asset.get("pixel_size", [])),
					"%s źródło assetu %s musi zachować natywne mapowanie 1:1."
					% [owner_label, asset_id],
				)
				_assert_backdrop_alpha_contract(source_texture, asset_id, owner_label)
	elif kind == COMPOSITION_PROXY_KIND:
		_assert(layer_id in NONBLOCKING_TEXTURE_LAYER_IDS, "%s proxy %s może należeć tylko do L01 albo L02." % [owner_label, asset_id])
		_assert(str(source_asset.get("path", "")).is_empty(), "%s proxy %s nie może mieć path." % [owner_label, asset_id])
		_assert(str(source_asset.get("sha256", "")).is_empty(), "%s proxy %s nie może mieć sha256." % [owner_label, asset_id])
		_assert(expected_rect.size == Vector2(expected_pixel_size), "%s proxy %s musi zachować rect 1:1." % [owner_label, asset_id])
		_assert(asset_node.get_child_count() == 3, "%s proxy %s musi mieć wyłącznie Fill, Outline i Label." % [owner_label, asset_id])
		var fill_node := asset_node.get_node_or_null("Fill")
		var outline_node := asset_node.get_node_or_null("Outline")
		var label_node := asset_node.get_node_or_null("Label")
		_assert(fill_node is ColorRect, "%s proxy %s musi mieć Fill:ColorRect." % [owner_label, asset_id])
		_assert(outline_node is Line2D, "%s proxy %s musi mieć Outline:Line2D." % [owner_label, asset_id])
		_assert(label_node is Label, "%s proxy %s musi mieć Label:Label." % [owner_label, asset_id])
		if fill_node is ColorRect:
			var fill := fill_node as ColorRect
			_assert(fill.scale == Vector2.ONE, "%s proxy %s nie może skalować Fill." % [owner_label, asset_id])
			_assert(_control_local_rect(fill) == Rect2(Vector2.ZERO, expected_rect.size), "%s proxy %s Fill musi zachować rect 1:1." % [owner_label, asset_id])
			_assert(fill.material == null, "%s proxy %s Fill nie może używać tekstury ani materiału." % [owner_label, asset_id])
		if outline_node is Line2D:
			var outline := outline_node as Line2D
			var expected_outline := PackedVector2Array([
				Vector2.ZERO,
				Vector2(expected_rect.size.x, 0.0),
				expected_rect.size,
				Vector2(0.0, expected_rect.size.y),
				Vector2.ZERO,
			])
			_assert(outline.scale == Vector2.ONE, "%s proxy %s nie może skalować Outline." % [owner_label, asset_id])
			_assert(outline.points == expected_outline, "%s proxy %s Outline musi obrysowywać dokładny rect." % [owner_label, asset_id])
			_assert(outline.texture == null, "%s proxy %s Outline nie może mieć tekstury." % [owner_label, asset_id])
		if label_node is Label:
			var proxy_label := label_node as Label
			var expected_dimensions := "%d x %d" % [int(expected_rect.size.x), int(expected_rect.size.y)]
			_assert(proxy_label.scale == Vector2.ONE, "%s proxy %s nie może skalować Label." % [owner_label, asset_id])
			_assert(proxy_label.text.begins_with(asset_id) and proxy_label.text.contains(expected_dimensions), "%s proxy %s Label musi publikować ID i rozmiar." % [owner_label, asset_id])
		for descendant in asset_node.find_children("*", "", true, false):
			_assert(not descendant is TextureRect and not descendant is Sprite2D, "%s proxy %s nie może zawierać bitmapy." % [owner_label, asset_id])
	elif kind == "collision_masked_material":
		_assert(asset_node.get_child_count() == 1, "%s asset %s L05 musi mieć tylko child Material." % [owner_label, asset_id])
		var material_node := asset_node.get_node_or_null("Material")
		_assert(material_node is ColorRect, "%s asset %s na L05 musi mieć child Material:ColorRect." % [owner_label, asset_id])
		if not material_node is ColorRect:
			return
		var color_rect := material_node as ColorRect
		_assert(color_rect.scale == Vector2.ONE, "%s materiał assetu %s nie może być skalowany." % [owner_label, asset_id])
		_assert(_control_local_rect(color_rect) == Rect2(Vector2.ZERO, expected_rect.size), "%s materiał assetu %s musi zachować rect elementu." % [owner_label, asset_id])
		var material := color_rect.material as ShaderMaterial
		_assert(material != null and material.shader != null, "%s asset %s musi używać ShaderMaterial." % [owner_label, asset_id])
		if material == null:
			return
		var topology_mask := material.get_shader_parameter("topology_mask") as Texture2D
		var ground_texture := material.get_shader_parameter("ground_texture") as Texture2D
		var surface_detail_mask := material.get_shader_parameter("surface_detail_mask") as Texture2D
		var texture_tiling_value: Variant = material.get_shader_parameter("texture_tiling")
		_assert(topology_mask != null, "%s asset %s musi używać wygenerowanej maski L05." % [owner_label, asset_id])
		_assert(ground_texture != null, "%s asset %s musi używać materiału gruntu." % [owner_label, asset_id])
		_assert(
			surface_detail_mask != null
			and surface_detail_mask.resource_path == L05_SURFACE_DETAIL_MASK_PATH
			and surface_detail_mask.get_size() == Vector2(L05_PIXEL_SIZE),
			"%s asset %s musi używać kanonicznej maski detalu L05."
			% [owner_label, asset_id],
		)
		if topology_mask != null:
			_assert(topology_mask.get_size() == Vector2(L05_PIXEL_SIZE), "%s maska assetu %s musi mieć 576 x 324." % [owner_label, asset_id])
		if ground_texture != null:
			var expected_native_tiling := Vector2(
				expected_rect.size.x / ground_texture.get_width(),
				expected_rect.size.y / ground_texture.get_height(),
			)
			_assert(
				texture_tiling_value is Vector2
				and (texture_tiling_value as Vector2).is_equal_approx(expected_native_tiling),
				"%s materiał assetu %s musi powtarzać teksturę w natywnej gęstości 1 piksel = 1 jednostka świata."
				% [owner_label, asset_id],
			)
			_assert(
				ground_texture.get_size() == _vector(source_asset.get("pixel_size", [])),
				"%s materiał assetu %s musi odpowiadać pixel_size manifestu." % [owner_label, asset_id],
			)
	else:
		_assert(false, "%s asset %s ma nieobsługiwany kind=%s." % [owner_label, asset_id, kind])


func _control_local_rect(control: Control) -> Rect2:
	return Rect2(
		Vector2(control.offset_left, control.offset_top),
		Vector2(
			control.offset_right - control.offset_left,
			control.offset_bottom - control.offset_top,
		),
	)


func _assert_backdrop_alpha_contract(texture: Texture2D, asset_id: String, owner_label: String) -> void:
	var image := texture.get_image()
	_assert(image != null, "%s asset %s musi udostępniać obraz do kontroli alfy." % [owner_label, asset_id])
	if image == null:
		return
	if image.is_compressed():
		var decompress_error := image.decompress()
		_assert(
			decompress_error == OK,
			"%s asset %s musi dać się zdekompresować do kontroli alfy." % [owner_label, asset_id],
		)
		if decompress_error != OK:
			return
	image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var pixel_count := width * height
	var data := image.get_data()
	_assert(
		data.size() == pixel_count * 4,
		"%s asset %s musi dostarczać kompletne RGBA8." % [owner_label, asset_id],
	)
	if data.size() != pixel_count * 4:
		return
	var nonzero := 0
	var opaque := 0
	var partial := 0
	var low_alpha := 0
	var bottom_opaque := 0
	var lowest_opaque_y := -1
	for pixel_index in range(pixel_count):
		var alpha := int(data[pixel_index * 4 + 3])
		if alpha == 0:
			continue
		nonzero += 1
		if alpha >= 250:
			opaque += 1
			var y := int(pixel_index / width)
			lowest_opaque_y = maxi(lowest_opaque_y, y)
			if y == height - 1:
				bottom_opaque += 1
		else:
			partial += 1
			if alpha <= 15:
				low_alpha += 1
	_assert(nonzero > 0 and opaque > 0, "%s asset %s musi zawierać kryjące budynki." % [owner_label, asset_id])
	_assert(
		nonzero < pixel_count,
		"%s asset %s musi pozostawiać przezroczyste przerwy między budynkami." % [owner_label, asset_id],
	)
	if nonzero == 0:
		return
	_assert(
		float(opaque) / float(nonzero) >= BACKDROP_MIN_OPAQUE_SHARE,
		"%s asset %s nie może mieć półprzezroczystych brył budynków." % [owner_label, asset_id],
	)
	_assert(
		float(partial) / float(pixel_count) <= BACKDROP_MAX_PARTIAL_CANVAS_SHARE,
		"%s asset %s może używać częściowej alfy tylko na wąskiej krawędzi." % [owner_label, asset_id],
	)
	_assert(
		float(low_alpha) / float(pixel_count) <= BACKDROP_MAX_LOW_ALPHA_CANVAS_SHARE,
		"%s asset %s nie może zawierać szerokiego półprzezroczystego halo." % [owner_label, asset_id],
	)
	_assert(
		lowest_opaque_y == height - 1,
		"%s asset %s musi stykać się z dolną krawędzią bez szczeliny nad L05." % [owner_label, asset_id],
	)
	_assert(
		float(bottom_opaque) / float(width) >= BACKDROP_MIN_BOTTOM_OPAQUE_SHARE,
		"%s asset %s musi mieć kryjącą podstawę schowaną za L05." % [owner_label, asset_id],
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
		var expected_modulate := Color.from_string("#%s" % str(layer.get("rgb_modulate", "ffffff")), Color.WHITE)
		_assert((node as Node2D).modulate == expected_modulate, "%s/%s musi zachować manifestowy rgb_modulate." % [owner_label, layer_id])
		_assert(is_equal_approx(expected_modulate.a, 1.0), "%s/%s rgb_modulate nie może zmieniać alfy." % [owner_label, layer_id])
		_assert(node.has_meta("rgb_modulate") and node.get_meta("rgb_modulate") == expected_modulate, "%s/%s musi publikować rgb_modulate w metadata." % [owner_label, layer_id])
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


func _valid_visual_group_id(value: String) -> bool:
	if value.is_empty() or not "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".contains(value.left(1)):
		return false
	for index in range(1, value.length()):
		if not "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_".contains(value.substr(index, 1)):
			return false
	return true


func _record_by_id(records: Array, record_id: String) -> Dictionary:
	for value in records:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == record_id:
			return value as Dictionary
	return {}


func _structure_template(manifest: Dictionary, template_id: String) -> Dictionary:
	var structures_value = manifest.get("structures", null)
	if not structures_value is Dictionary:
		return {}
	var templates_value = (structures_value as Dictionary).get("templates", null)
	if not templates_value is Array:
		return {}
	return _record_by_id(templates_value as Array, template_id)


func _structure_instance(manifest: Dictionary, structure_id: String) -> Dictionary:
	var structures_value = manifest.get("structures", null)
	if not structures_value is Dictionary:
		return {}
	var instances_value = (structures_value as Dictionary).get("instances", null)
	if not instances_value is Array:
		return {}
	return _record_by_id(instances_value as Array, structure_id)


func _resolved_manifest_world_position(record: Dictionary, manifest: Dictionary) -> Vector2:
	var position := _vector(record.get("position", []))
	if str(record.get("position_space", "world")) != "structure_local":
		return position
	var structure := _structure_instance(manifest, str(record.get("structure_id", "")))
	if structure.is_empty():
		return Vector2(INF, INF)
	return _vector(structure.get("origin", [])) + position


func _assert_exact_dictionary_keys(record: Dictionary, expected_keys: Array, label: String) -> void:
	var actual := PackedStringArray()
	for key in record.keys():
		actual.append(str(key))
	actual.sort()
	var expected := PackedStringArray()
	for key in expected_keys:
		expected.append(str(key))
	expected.sort()
	_assert(
		actual == expected,
		"%s musi zawierać dokładnie pola [%s], otrzymano [%s]."
		% [label, ", ".join(expected), ", ".join(actual)],
	)


func _assert_required_and_optional_dictionary_keys(
	record: Dictionary,
	required_keys: Array,
	optional_keys: Array,
	label: String,
) -> void:
	for key in required_keys:
		_assert(record.has(key), "%s nie zawiera wymaganego pola %s." % [label, str(key)])
	for key in record.keys():
		_assert(
			key in required_keys or key in optional_keys,
			"%s zawiera niedozwolone pole %s." % [label, str(key)],
		)


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


func _direct_child_with_any_meta(
	parent: Node,
	meta_keys: Array,
	expected_value: String,
) -> Node:
	for child in parent.get_children():
		for meta_key in meta_keys:
			if str(child.get_meta(str(meta_key), "")) == expected_value:
				return child
	return null


func _direct_child_with_property_value(
	parent: Node,
	property_name: String,
	expected_value: String,
) -> Node:
	for child in parent.get_children():
		for property_record in child.get_property_list():
			if str((property_record as Dictionary).get("name", "")) != property_name:
				continue
			if str(child.get(property_name)) == expected_value:
				return child
			break
	return null


func _vector_is_grid_aligned(value: Vector2, grid_step: Vector2) -> bool:
	if not value.is_finite() or grid_step.x <= 0.0 or grid_step.y <= 0.0:
		return false
	return (
		is_equal_approx(value.x / grid_step.x, round(value.x / grid_step.x))
		and is_equal_approx(value.y / grid_step.y, round(value.y / grid_step.y))
	)


func _load_json_resource(resource_path: String, label: String) -> Dictionary:
	_assert(FileAccess.file_exists(resource_path), "%s nie istnieje: %s." % [label, resource_path])
	if not FileAccess.file_exists(resource_path):
		return {}
	var file := FileAccess.open(resource_path, FileAccess.READ)
	_assert(file != null, "Nie można otworzyć %s: %s." % [label, resource_path])
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	_assert(parsed is Dictionary, "%s musi być obiektem JSON." % label)
	return parsed as Dictionary if parsed is Dictionary else {}


func _vector(value) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Vector2i:
		return Vector2(value as Vector2i)
	if not value is Array or (value as Array).size() != 2:
		return Vector2(INF, INF)
	return Vector2(float(value[0]), float(value[1]))


func _rect(value) -> Rect2:
	if value is Rect2:
		return value as Rect2
	if value is Rect2i:
		return Rect2(value as Rect2i)
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
	print("Underwater map smoke test passed: schema-v6 package registry, partitioned L05 collision, generated package scenes, blueprint and local runtime parity.")
	quit(0)
