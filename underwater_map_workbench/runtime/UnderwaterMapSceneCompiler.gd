class_name UnderwaterMapSceneCompiler
extends RefCounted

const WorldStateScript := preload("res://scripts/data/UnderwaterWorldState.gd")
const WorldBlueprintScript := preload("res://scripts/data/WorldBlueprint.gd")

const MANIFEST_PATH := "res://underwater_map_workbench/map_manifest.json"
const MAP_SCENE_PATH := "res://underwater_map_workbench/UnderwaterMap.tscn"
const VISUAL_SURVEY_SOURCE_SNAPSHOT_VERSION := 1
const VISUAL_SURVEY_DEPENDENCY_FINGERPRINT_PREFIX := "visual-survey-dependencies-v1:"
const TRANSITIVE_TEXT_RESOURCE_EXTENSIONS := [
	"tscn", "tres", "gd", "gdshader", "gdshaderinc", "material",
]
const MAP_SOURCE_VERSION := 5
const MANIFEST_SCHEMA_VERSION := 6
const REQUIRED_GRID_SIZE := Vector2i(12, 12)
const REQUIRED_GRID_CELL_SIZE := Vector2(1920.0, 1080.0)
const REQUIRED_WORLD_SIZE := Vector2(23040.0, 12960.0)
const TUTORIAL_MARKET_CRATE_ID := "tutorial_market_crate"
const TUTORIAL_WORKSHOP_CASE_ID := "tutorial_workshop_case"
const TUTORIAL_SHORTCUT_ID := "SC-01"
const TUTORIAL_DEVICE_ID := "junction_j7"
const VISUAL_LAYER_IDS := [
	"L00", "L01", "L02", "L03", "L04", "L05", "L06", "L07", "L08", "L09", "L10",
]
const PARALLAX_LAYER_IDS := ["L01", "L02", "L08", "L09"]
const VISUAL_LAYER_SPACES := {
	"L00": "world_locked",
	"L01": "parallax",
	"L02": "parallax",
	"L03": "world_locked",
	"L04": "world_locked",
	"L05": "world_locked",
	"L06": "world_locked",
	"L07": "world_locked",
	"L08": "parallax",
	"L09": "parallax",
	"L10": "world_locked",
}
const COLLIDER_AUTHORITY_LAYER_ID := "L05"
const RESERVED_VISUAL_LAYER_ID := "L10"
const NO_BLOCKING_AFFORDANCE_POLICY := "no_visual_blockage_in_protected_water"
const OPEN_WATER_BACKDROP_AFFORDANCE_POLICY := "nonblocking_backdrop_may_overlap_open_water"
const NONBLOCKING_TEXTURE_LAYER_IDS := ["L01", "L02"]
const GROUND_ANCHORED_BACKDROP_LAYER_IDS := ["L01", "L02"]
const NONBLOCKING_BACKDROP_AFFORDANCE := "nonblocking_backdrop"
const PORTAL_BACKDROP_CLEARANCE_CONTRACT := "raster_boundary_opening_clearance_v1"
const PORTAL_BACKDROP_CLEARANCE_HOST_LAYER_ID := "L04"
const PORTAL_BACKDROP_CLEARANCE_OCCLUDED_LAYER_IDS := ["L01", "L02"]
const PORTAL_BACKDROP_CLEARANCE_NORMAL_CORE_CELLS := 5
const PORTAL_BACKDROP_CLEARANCE_TANGENT_PADDING_CELLS := 1
const PORTAL_BACKDROP_CLEARANCE_FEATHER_CELLS := 2
const L05_TOPOLOGY_MODE := "l05_mask_v1"
const L05_SOURCE_FORMAT := "l05_owned_rect_ops_v2"
const L05_PIXEL_SIZE := Vector2i(576, 324)
const L05_WORLD_UNITS_PER_PIXEL := Vector2(40.0, 40.0)
const L05_MAPPING := {
	"world_origin": [0, 0],
	"x_axis": "right",
	"y_axis": "down",
	"pixel_reference": "pixel_edge",
	"rounding": "floor",
}
const STRUCTURE_REGISTRY_KEYS := ["instances"]
const STRUCTURE_REGISTRY_INSTANCE_REQUIRED_KEYS := ["id", "origin", "enabled", "package"]
const STRUCTURE_REGISTRY_INSTANCE_OPTIONAL_KEYS := ["landmark_id"]
const STRUCTURE_PACKAGE_REFERENCE_KEYS := ["format", "path", "sha256"]
const STRUCTURE_PACKAGE_REFERENCE_FORMAT := "structure_package_v1"
const STRUCTURE_PACKAGE_FORMAT := "enterable_structure_package_v1"
const STRUCTURE_PACKAGE_KEYS := [
	"schema_version", "format", "template", "size", "local_topology_digest",
	"collision", "sockets", "runtime", "visual_assets", "scripts", "attempt_state",
	"references",
]
const STRUCTURE_PACKAGE_COLLISION_KEYS := [
	"format", "base", "pixel_size", "world_units_per_pixel", "operations",
]
const STRUCTURE_PACKAGE_COLLISION_FORMAT := "l05_structure_rect_ops_v1"
const STRUCTURE_PACKAGE_OPERATION_KEYS := ["id", "op", "rect_px"]
const STRUCTURE_PACKAGE_VISUAL_ASSET_KEYS := [
	"id", "layer_id", "group_id", "kind", "path", "sha256", "pixel_size",
	"local_rect", "enabled", "affordance",
]
const STRUCTURE_PACKAGE_SCRIPT_KEYS := ["role", "path", "sha256"]
const STRUCTURE_PACKAGE_REQUIRED_SCRIPT_ROLE := "controller"
const STRUCTURE_PACKAGE_ATTEMPT_STATE := {
	"persistence": "none",
	"checkpoint": "none",
	"reset": "whole_structure_attempt",
}
const STRUCTURE_PACKAGE_REFERENCE_RECORD_KEYS := [
	"path", "sha256", "role", "authority", "excluded_topics",
]
const STRUCTURE_PACKAGE_REFERENCE_EXCLUDED_TOPICS := [
	"checkpoint", "save_load", "point_of_no_return", "collapse_failure",
]
const L05_SOLID_MASK_PATH := "res://underwater_map_workbench/assets/generated/l05/solid_mask.png"
const L05_SURFACE_DETAIL_MASK_PATH := "res://underwater_map_workbench/assets/generated/l05/surface_detail_mask.png"
const L05_SHADER_PATH := "res://underwater_map_workbench/assets/shaders/l05_ground_masked.gdshader"
const STRUCTURE_CLIP_SHADER_PATH := "res://underwater_map_workbench/assets/shaders/structure_clip_masked.gdshader"
const VISUAL_ASSET_KEYS := [
	"id", "layer_id", "group_id", "kind", "path", "sha256", "pixel_size", "world_rect",
	"enabled", "affordance", "topology_digest",
]
const STRUCTURE_VISUAL_ASSET_KEYS := [
	"id", "layer_id", "group_id", "kind", "path", "sha256", "pixel_size", "local_rect",
	"enabled", "affordance", "topology_digest", "partition_digest", "structure_id",
]
const STRUCTURE_VISUAL_ASSET_KINDS := [
	"structure_interior_texture", "structure_owner_masked_texture",
]
const CAMPAIGN_CONTRACT_ID := "common_line_v1"
const CAMPAIGN_STAGE_CONTRACTS := [
	{"id": "j7", "fixed_device_ids": ["junction_j7"]},
	{"id": "archive", "fixed_device_ids": ["archive_terminal"]},
	{
		"id": "r3",
		"fixed_device_ids": ["r3_diagnostic_panel", "r3_generator"],
	},
	{
		"id": "c4",
		"fixed_device_ids": ["c4_switchboard", "c4_splitter_mount"],
	},
]
const CAMPAIGN_DEVICE_PREREQUISITES := {
	"junction_j7": [],
	"archive_terminal": ["junction_j7"],
	"r3_diagnostic_panel": ["archive_terminal"],
	"r3_generator": ["r3_diagnostic_panel"],
	"c4_switchboard": ["r3_generator"],
	"c4_splitter_mount": ["c4_switchboard"],
}
const PRESENTATION_FIELD_KEYS := [
	"display_name",
	"short_name",
	"label",
	"description",
	"visual_kind",
	"visual_scene_path",
	"visual_offset",
	"visual_scale",
	"visual_rotation",
	"visual_z_index",
	"texture_path",
	"material_path",
	"shader_path",
	"icon_path",
	"backdrop_path",
	"color",
	"modulate",
]

static var _cached_manifest_hash := ""
static var _cached_manifest: Dictionary = {}
static var _cached_source_fingerprint := ""
static var _cached_dependency_paths := PackedStringArray()
static var _cached_dependency_records: Array = []
static var _cached_gameplay_signature := ""
static var _cached_presentation_fingerprint := ""
static var _cached_blueprints: Dictionary = {}
static var _cached_navigation_raster: Dictionary = {}


static func clear_runtime_caches() -> void:
	_cached_manifest_hash = ""
	_cached_manifest.clear()
	_cached_source_fingerprint = ""
	_cached_dependency_paths.clear()
	_cached_dependency_records.clear()
	_cached_gameplay_signature = ""
	_cached_presentation_fingerprint = ""
	_cached_blueprints.clear()
	_cached_navigation_raster.clear()


func generate(world, campaign_seed: int) -> PackedStringArray:
	if world == null or world.get_script() != WorldStateScript:
		return PackedStringArray(["Kompilacja mapy wymaga UnderwaterWorldState."])
	var compilation := _compile_source_map(campaign_seed)
	var errors: PackedStringArray = compilation.get("errors", PackedStringArray())
	if not errors.is_empty():
		return errors
	var blueprint = compilation.get("blueprint")
	if blueprint == null or blueprint.get_script() != WorldBlueprintScript:
		return PackedStringArray(["Manifest nie wygenerował poprawnego WorldBlueprint."])
	world.blueprint = blueprint
	world.delta.clear()
	world.delta.active_landmark_id = blueprint.entry_landmark_id
	world.delta.discovered_landmarks.assign([blueprint.entry_landmark_id])
	world.delta.discovered_chunks.assign([
		blueprint.chunk_key(blueprint.chunk_coord_at(blueprint.entry_position)),
	])
	return PackedStringArray()


func ensure_world_is_current(world) -> PackedStringArray:
	if world == null or world.get_script() != WorldStateScript:
		return PackedStringArray(["Weryfikacja mapy wymaga UnderwaterWorldState."])
	if world.blueprint == null or world.blueprint.get_script() != WorldBlueprintScript:
		return PackedStringArray(["Kampania nie zawiera WorldBlueprint bieżącej mapy."])
	var compilation := _compile_source_map(int(world.blueprint.campaign_seed))
	var errors: PackedStringArray = compilation.get("errors", PackedStringArray())
	if not errors.is_empty():
		return errors
	var current_blueprint = compilation.get("blueprint")
	if current_blueprint == null:
		return PackedStringArray(["Bieżący manifest nie zwrócił blueprintu."])
	if (
		int(current_blueprint.map_source_version) != int(world.blueprint.map_source_version)
		or str(current_blueprint.map_id) != str(world.blueprint.map_id)
		or str(current_blueprint.map_gameplay_signature) != str(world.blueprint.map_gameplay_signature)
	):
		return PackedStringArray(["Zapis kampanii nie odpowiada bieżącemu manifestowi mapy."])
	# Blueprint zapisany w kampanii jest jedynie walidowanym cache runtime'u.
	# Po zgodności podpisu odświeżamy go z jedynego źródła prawdy.
	world.blueprint = current_blueprint
	if not world.delta.discovered_landmarks.has(world.blueprint.entry_landmark_id):
		world.delta.discovered_landmarks.append(world.blueprint.entry_landmark_id)
	return PackedStringArray()


## Compatibility entry point used by diagnostics. The generated scene is a
## derivative, so map_root is intentionally ignored and cannot become a second
## source of gameplay data.
func compile_map(_map_root = null, campaign_seed: int = 1) -> Dictionary:
	return _compile_source_map(campaign_seed)


func validate_manifest_for_tests(manifest: Dictionary) -> PackedStringArray:
	var resolution_errors := PackedStringArray()
	var resolved_manifest := _resolve_structure_packages(manifest, resolution_errors, true)
	if not resolution_errors.is_empty():
		return resolution_errors
	return _manifest_validation_errors(resolved_manifest)


func compile_from_manifest_for_tests(manifest: Dictionary, campaign_seed: int = 1) -> Dictionary:
	var errors := PackedStringArray()
	var resolved_manifest := _resolve_structure_packages(manifest, errors, true)
	if errors.is_empty():
		errors = _manifest_validation_errors(resolved_manifest)
	if not errors.is_empty():
		return {
			"errors": errors,
			"map_gameplay_signature": "",
			"presentation_fingerprint": "",
		}
	var identities := _manifest_identities(resolved_manifest)
	var blueprint = _build_blueprint(
		resolved_manifest,
		str(identities.get("gameplay_signature", "")),
		maxi(campaign_seed, 1)
	)
	return {
		"errors": PackedStringArray(),
		"blueprint": blueprint,
		"map_gameplay_signature": str(identities.get("gameplay_signature", "")),
		"presentation_fingerprint": str(identities.get("presentation_fingerprint", "")),
	}


func manifest_snapshot() -> Dictionary:
	var source := _load_source()
	var errors: PackedStringArray = source.get("errors", PackedStringArray())
	if not errors.is_empty():
		return {}
	return (source.get("manifest", {}) as Dictionary).duplicate(true)


func manifest_sha256() -> String:
	var source := _load_source()
	var errors: PackedStringArray = source.get("errors", PackedStringArray())
	return "" if not errors.is_empty() else str(source.get("manifest_sha256", ""))


func generated_scene_is_current() -> bool:
	var source := _load_source()
	var errors: PackedStringArray = source.get("errors", PackedStringArray())
	return errors.is_empty()


func visual_survey_source_snapshot() -> Dictionary:
	var source := _load_source(true)
	var errors: PackedStringArray = source.get("errors", PackedStringArray())
	if not errors.is_empty():
		return {"errors": errors.duplicate()}
	var manifest: Dictionary = source.get("resolved_manifest", source.get("manifest", {}))
	var raster: Dictionary = source.get("navigation_base_raster", {})
	return {
		"snapshot_version": VISUAL_SURVEY_SOURCE_SNAPSHOT_VERSION,
		"errors": PackedStringArray(),
		"manifest": manifest.duplicate(true),
		"resolved_manifest": manifest.duplicate(true),
		"navigation_base_raster": _duplicate_raster(raster),
		"manifest_sha256": str(source.get("manifest_sha256", "")),
		"dependency_paths": (
			source.get("dependency_paths", PackedStringArray()) as PackedStringArray
		).duplicate(),
		"dependency_records": (source.get("dependency_records", []) as Array).duplicate(true),
		"dependency_fingerprint": str(source.get("dependency_fingerprint", "")),
		"gameplay_signature": str(source.get("gameplay_signature", "")),
		"presentation_fingerprint": str(source.get("presentation_fingerprint", "")),
	}


func verify_visual_survey_source_snapshot(snapshot: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if int(snapshot.get("snapshot_version", 0)) != VISUAL_SURVEY_SOURCE_SNAPSHOT_VERSION:
		errors.append("Visual survey source snapshot ma nieobsługiwaną wersję.")
		return errors
	var records_value = snapshot.get("dependency_records", null)
	if not records_value is Array or (records_value as Array).is_empty():
		errors.append("Visual survey source snapshot nie zawiera dependency_records.")
		return errors
	var expected_records := (records_value as Array).duplicate(true)
	var expected_fingerprint := str(snapshot.get("dependency_fingerprint", ""))
	if expected_fingerprint != _dependency_fingerprint_for_records(expected_records):
		errors.append("Visual survey source snapshot ma niespójny dependency_fingerprint.")
		return errors
	var paths := PackedStringArray()
	for index in range(expected_records.size()):
		var record_value = expected_records[index]
		if not record_value is Dictionary:
			errors.append("dependency_records[%d] nie jest obiektem." % index)
			continue
		var record := record_value as Dictionary
		var resource_path := str(record.get("path", ""))
		if resource_path.is_empty() or paths.has(resource_path):
			errors.append("dependency_records[%d] ma pustą lub powtórzoną ścieżkę." % index)
			continue
		paths.append(resource_path)
	if not errors.is_empty():
		return errors
	var sorted_paths := paths.duplicate()
	sorted_paths.sort()
	if sorted_paths != paths:
		errors.append("dependency_records nie są uporządkowane deterministycznie.")
		return errors
	for required_path in [MANIFEST_PATH, MAP_SCENE_PATH]:
		if not paths.has(required_path):
			errors.append("Visual survey source snapshot nie zawiera %s." % required_path)
	var declared_paths_value = snapshot.get("dependency_paths", null)
	if (
		declared_paths_value is PackedStringArray
		and (declared_paths_value as PackedStringArray) != paths
	):
		errors.append("dependency_paths nie odpowiadają dependency_records.")
	var manifest_record := _dependency_record_for_path(expected_records, MANIFEST_PATH)
	if (
		not manifest_record.is_empty()
		and (
			str(manifest_record.get("sha256", ""))
			!= str(snapshot.get("manifest_sha256", ""))
		)
	):
		errors.append("manifest_sha256 nie odpowiada rekordowi zależności manifestu.")
	if not errors.is_empty():
		return errors
	var current := _dependency_snapshot_for_paths(paths)
	errors.append_array(current.get("errors", PackedStringArray()))
	if not errors.is_empty():
		return errors
	var current_records: Array = current.get("records", [])
	for index in range(expected_records.size()):
		var expected := expected_records[index] as Dictionary
		var actual := current_records[index] as Dictionary
		if (
			str(actual.get("sha256", "")) != str(expected.get("sha256", ""))
			or int(actual.get("size", -1)) != int(expected.get("size", -2))
		):
			errors.append(
				"Zależność visual survey zmieniła się: %s." % str(expected.get("path", ""))
			)
	if (
		errors.is_empty()
		and str(current.get("fingerprint", "")) != expected_fingerprint
	):
		errors.append("Dependency fingerprint visual survey zmienił się.")
	return errors


func source_dependency_paths() -> PackedStringArray:
	var fallback_paths := PackedStringArray([MANIFEST_PATH, MAP_SCENE_PATH])
	if not FileAccess.file_exists(MANIFEST_PATH):
		return fallback_paths
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return fallback_paths
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return fallback_paths
	var paths := _source_dependency_paths_for_manifest(parsed as Dictionary)
	_append_transitive_resource_dependency_paths(paths)
	return _sorted_unique_dependency_paths(paths)


func _source_dependency_paths_for_manifest(manifest: Dictionary) -> PackedStringArray:
	var paths := PackedStringArray([MANIFEST_PATH, MAP_SCENE_PATH])
	var topology_value = manifest.get("topology", null)
	if topology_value is Dictionary:
		var collision_value = (topology_value as Dictionary).get("collision_source", null)
		if collision_value is Dictionary:
			_append_source_path(paths, str((collision_value as Dictionary).get("path", "")))
		if str((topology_value as Dictionary).get("mode", "")) == L05_TOPOLOGY_MODE:
			paths.append(L05_SOLID_MASK_PATH)
			paths.append(L05_SURFACE_DETAIL_MASK_PATH)
			paths.append(L05_SHADER_PATH)
	var visual_value = manifest.get("visual", null)
	var structure_mask_paths := {}
	if visual_value is Dictionary:
		var assets_value = (visual_value as Dictionary).get("assets", null)
		if assets_value is Array:
			for asset_value in assets_value as Array:
				if asset_value is Dictionary:
					var asset := asset_value as Dictionary
					_append_workbench_source_path(paths, str(asset.get("path", "")))
					var kind := str(asset.get("kind", ""))
					if kind in STRUCTURE_VISUAL_ASSET_KINDS:
						var structure_id := str(asset.get("structure_id", ""))
						var mask_name := "open_water_mask_native.png" if kind == "structure_interior_texture" else "solid_mask_native.png"
						structure_mask_paths[
							"res://underwater_map_workbench/structures/%s/generated/%s"
							% [structure_id, mask_name]
						] = true
						structure_mask_paths[
							"res://underwater_map_workbench/structures/%s/generated/surface_detail_mask_local.png"
							% structure_id
						] = true
	_append_structure_package_dependency_paths(paths, manifest, structure_mask_paths)
	if not structure_mask_paths.is_empty():
		paths.append(STRUCTURE_CLIP_SHADER_PATH)
		for mask_path in structure_mask_paths:
			paths.append(str(mask_path))
	return paths


func _append_structure_package_dependency_paths(
	paths: PackedStringArray,
	manifest: Dictionary,
	structure_mask_paths: Dictionary,
) -> void:
	var structures_value = manifest.get("structures", null)
	if not structures_value is Dictionary:
		return
	var instances_value = (structures_value as Dictionary).get("instances", null)
	if not instances_value is Array:
		return
	for instance_value in instances_value as Array:
		if not instance_value is Dictionary:
			continue
		var instance := instance_value as Dictionary
		var structure_id := str(instance.get("id", "")).strip_edges()
		var package_path := ""
		var package_reference_value = instance.get("package", null)
		if package_reference_value is Dictionary:
			package_path = str((package_reference_value as Dictionary).get("path", ""))
		elif instance.get("package_path", null) is String:
			package_path = str(instance.get("package_path", ""))
		var package_resource_path := _workbench_resource_path(package_path, ["structures"])
		if package_resource_path.is_empty():
			continue
		_append_unique_path(paths, package_resource_path)
		var structure_scene_path := str(instance.get(
			"structure_scene_path",
			"res://underwater_map_workbench/structures/%s/generated/structure.tscn"
			% structure_id,
		))
		if structure_scene_path.begins_with("res://underwater_map_workbench/"):
			_append_unique_path(paths, structure_scene_path)
		if not FileAccess.file_exists(package_resource_path):
			continue
		var package_file := FileAccess.open(package_resource_path, FileAccess.READ)
		if package_file == null:
			continue
		var package_value = JSON.parse_string(package_file.get_as_text())
		package_file.close()
		if not package_value is Dictionary:
			continue
		var package := package_value as Dictionary
		var assets_value = package.get("visual_assets", null)
		if assets_value is Array:
			for asset_value in assets_value as Array:
				if not asset_value is Dictionary:
					continue
				var asset := asset_value as Dictionary
				var member_resource_path := _structure_package_member_resource_path(
					package_path,
					str(asset.get("path", "")),
				)
				_append_unique_path(paths, member_resource_path)
				var kind := str(asset.get("kind", ""))
				if kind in STRUCTURE_VISUAL_ASSET_KINDS and not structure_id.is_empty():
					var mask_name := (
						"open_water_mask_native.png"
						if kind == "structure_interior_texture"
						else "solid_mask_native.png"
					)
					structure_mask_paths[
						"res://underwater_map_workbench/structures/%s/generated/%s"
						% [structure_id, mask_name]
					] = true
					structure_mask_paths[
						"res://underwater_map_workbench/structures/%s/generated/surface_detail_mask_local.png"
						% structure_id
					] = true
		var scripts_value = package.get("scripts", null)
		if scripts_value is Array:
			for script_value in scripts_value as Array:
				if not script_value is Dictionary:
					continue
				_append_unique_path(
					paths,
					_structure_package_member_resource_path(
						package_path,
						str((script_value as Dictionary).get("path", "")),
					),
				)


func _source_dependency_snapshot(
	manifest: Dictionary,
	expected_manifest_hash: String,
) -> Dictionary:
	var paths := _source_dependency_paths_for_manifest(manifest)
	_append_transitive_resource_dependency_paths(paths)
	paths = _sorted_unique_dependency_paths(paths)
	var snapshot := _dependency_snapshot_for_paths(paths)
	var errors: PackedStringArray = snapshot.get("errors", PackedStringArray())
	if errors.is_empty():
		var manifest_record := _dependency_record_for_path(
			snapshot.get("records", []) as Array,
			MANIFEST_PATH,
		)
		if (
			manifest_record.is_empty()
			or str(manifest_record.get("sha256", "")) != expected_manifest_hash
		):
			errors.append("Manifest mapy zmienił się podczas budowania snapshotu źródła.")
	snapshot["errors"] = errors
	return snapshot


func _dependency_snapshot_for_paths(paths: PackedStringArray) -> Dictionary:
	var errors := PackedStringArray()
	var records: Array = []
	for resource_path in paths:
		if not FileAccess.file_exists(resource_path):
			errors.append("Brak zależności visual survey: %s." % resource_path)
			continue
		var dependency_file := FileAccess.open(resource_path, FileAccess.READ)
		if dependency_file == null:
			errors.append("Nie można otworzyć zależności visual survey: %s." % resource_path)
			continue
		var length := dependency_file.get_length()
		dependency_file.close()
		var dependency_sha := FileAccess.get_sha256(resource_path).to_lower()
		if dependency_sha.is_empty():
			errors.append("Nie można policzyć SHA-256 zależności visual survey: %s." % resource_path)
			continue
		records.append({
			"path": resource_path,
			"sha256": dependency_sha,
			"size": length,
		})
	return {
		"errors": errors,
		"paths": paths.duplicate(),
		"records": records,
		"fingerprint": (
			_dependency_fingerprint_for_records(records) if errors.is_empty() else ""
		),
	}


func _dependency_fingerprint_for_records(records: Array) -> String:
	if records.is_empty():
		return ""
	return "%s%s" % [
		VISUAL_SURVEY_DEPENDENCY_FINGERPRINT_PREFIX,
		_canonical_sha256(records),
	]


func _dependency_record_for_path(records: Array, resource_path: String) -> Dictionary:
	for record_value in records:
		if (
			record_value is Dictionary
			and str((record_value as Dictionary).get("path", "")) == resource_path
		):
			return record_value as Dictionary
	return {}


func _append_transitive_resource_dependency_paths(paths: PackedStringArray) -> void:
	var quoted_resource_pattern := RegEx.new()
	var resource_scheme: String = "res:" + "//"
	var quoted_resource_expression: String = "\"" + "(" + resource_scheme + "[^\"\\r\\n]+)" + "\""
	if quoted_resource_pattern.compile(quoted_resource_expression) != OK:
		return
	var queue: Array[String] = []
	for resource_path in paths:
		queue.append(resource_path)
	var visited := {}
	var cursor := 0
	while cursor < queue.size():
		var resource_path := queue[cursor]
		cursor += 1
		if visited.has(resource_path):
			continue
		visited[resource_path] = true
		if resource_path.get_extension().to_lower() not in TRANSITIVE_TEXT_RESOURCE_EXTENSIONS:
			continue
		if not FileAccess.file_exists(resource_path):
			continue
		var resource_file := FileAccess.open(resource_path, FileAccess.READ)
		if resource_file == null:
			continue
		var source_text := resource_file.get_as_text()
		resource_file.close()
		for match_value in quoted_resource_pattern.search_all(source_text):
			var dependency_path := (match_value as RegExMatch).get_string(1)
			if dependency_path.is_empty() or paths.has(dependency_path):
				continue
			paths.append(dependency_path)
			queue.append(dependency_path)


func create_visual_layers() -> Node2D:
	var source := _load_source()
	var errors: PackedStringArray = source.get("errors", PackedStringArray())
	if not errors.is_empty():
		return null
	var packed_scene := ResourceLoader.load(
		MAP_SCENE_PATH,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	if packed_scene == null:
		return null
	var source_root := packed_scene.instantiate() as Node2D
	if source_root == null:
		return null
	var visual_layers := source_root.get_node_or_null("VisualLayers") as Node2D
	if visual_layers == null:
		source_root.free()
		return null
	source_root.remove_child(visual_layers)
	source_root.free()
	return visual_layers


func create_structure_roots() -> Node2D:
	var source := _load_source()
	var errors: PackedStringArray = source.get("errors", PackedStringArray())
	if not errors.is_empty():
		return null
	var packed_scene := ResourceLoader.load(
		MAP_SCENE_PATH,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	if packed_scene == null:
		return null
	var source_root := packed_scene.instantiate() as Node2D
	if source_root == null:
		return null
	var structure_roots := source_root.get_node_or_null("StructureRoots") as Node2D
	if structure_roots == null:
		source_root.free()
		return null
	source_root.remove_child(structure_roots)
	source_root.free()
	return structure_roots


func navigation_base_raster() -> Dictionary:
	var source := _load_source()
	var errors: PackedStringArray = source.get("errors", PackedStringArray())
	if not errors.is_empty():
		return {"errors": errors}
	return _duplicate_raster(source.get("navigation_base_raster", {}) as Dictionary)


func _build_navigation_base_raster(manifest: Dictionary) -> Dictionary:
	var map_record: Dictionary = manifest.get("map", {})
	var topology: Dictionary = manifest.get("topology", {})
	var structures: Dictionary = manifest.get("structures", {})
	var topology_mode := str(topology.get("mode", ""))
	if topology_mode not in ["open_world", L05_TOPOLOGY_MODE]:
		return {
			"errors": PackedStringArray([
				"navigation_base_raster nie obsługuje topology.mode=%s."
				% str(topology.get("mode", "")),
			]),
		}
	var cell_extent := _json_vector(map_record.get("navigation_cell_size", []))
	var grid_extent := Vector2i.ZERO
	var cells := PackedByteArray()
	var solid_owner_cells := PackedInt32Array()
	var owner_ids := PackedStringArray(["", "world"])
	var partition_digest := ""
	if topology_mode == "open_world":
		var world_extent := _json_vector(map_record.get("world_size", []))
		grid_extent = Vector2i(
			roundi(world_extent.x / cell_extent.x),
			roundi(world_extent.y / cell_extent.y)
		)
		cells.resize(grid_extent.x * grid_extent.y)
		cells.fill(1)
		solid_owner_cells.resize(cells.size())
		solid_owner_cells.fill(0)
	else:
		var topology_errors := PackedStringArray()
		var decoded := _decode_l05_collision_source(topology, structures, topology_errors)
		if not topology_errors.is_empty():
			return {"errors": topology_errors}
		grid_extent = L05_PIXEL_SIZE
		cell_extent = L05_WORLD_UNITS_PER_PIXEL
		var encoded_cells: PackedByteArray = decoded.get("cells", PackedByteArray())
		var solid_value := int(decoded.get("solid", 0))
		solid_owner_cells = (
			decoded.get("solid_owner_cells", PackedInt32Array()) as PackedInt32Array
		).duplicate()
		owner_ids = (
			decoded.get("owner_ids", PackedStringArray()) as PackedStringArray
		).duplicate()
		partition_digest = str(decoded.get("partition_digest", ""))
		cells.resize(encoded_cells.size())
		for index in range(encoded_cells.size()):
			cells[index] = 0 if int(encoded_cells[index]) == solid_value else 1
	return {
		"errors": PackedStringArray(),
		"width": grid_extent.x,
		"height": grid_extent.y,
		"cell_scale": cell_extent,
		"cells": cells,
		"solid_owner_cells": solid_owner_cells,
		"owner_ids": owner_ids,
		"partition_digest": partition_digest,
	}


func navigation_grid_texture() -> Texture2D:
	return null


func terrain_render_sdf_texture() -> Texture2D:
	return null


func terrain_detail_texture() -> Texture2D:
	return null


func terrain_visual_profiles() -> Array[Resource]:
	return []


func _compile_source_map(campaign_seed: int) -> Dictionary:
	var normalized_seed := maxi(campaign_seed, 1)
	var source := _load_source()
	var errors: PackedStringArray = source.get("errors", PackedStringArray())
	if not errors.is_empty():
		return {"errors": errors}
	var manifest_hash := str(source.get("manifest_sha256", ""))
	var gameplay_signature := str(source.get("gameplay_signature", ""))
	var presentation_fingerprint := str(source.get("presentation_fingerprint", ""))
	if _cached_blueprints.has(normalized_seed):
		return {
			"errors": PackedStringArray(),
			"blueprint": _cached_blueprints[normalized_seed].duplicate(true),
			"manifest_sha256": manifest_hash,
			"map_gameplay_signature": gameplay_signature,
			"presentation_fingerprint": presentation_fingerprint,
		}
	var manifest: Dictionary = source.get("manifest", {})
	var blueprint = _build_blueprint(manifest, gameplay_signature, normalized_seed)
	if blueprint == null:
		return {"errors": PackedStringArray(["Nie udało się zbudować blueprintu z manifestu."])}
	_cached_blueprints[normalized_seed] = blueprint.duplicate(true)
	return {
		"errors": PackedStringArray(),
		"blueprint": blueprint,
		"manifest_sha256": manifest_hash,
		"map_gameplay_signature": gameplay_signature,
		"presentation_fingerprint": presentation_fingerprint,
	}


func _load_source(verify_dependencies: bool = false) -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {"errors": PackedStringArray(["Brak jedynego manifestu mapy: %s." % MANIFEST_PATH])}
	var manifest_hash := FileAccess.get_sha256(MANIFEST_PATH).to_lower()
	if manifest_hash.is_empty():
		return {"errors": PackedStringArray(["Nie można policzyć SHA-256 manifestu mapy."])}
	if manifest_hash == _cached_manifest_hash and not _cached_manifest.is_empty():
		if not verify_dependencies and not _cached_navigation_raster.is_empty():
			return {
				"errors": PackedStringArray(),
				"manifest": _cached_manifest.duplicate(true),
				"resolved_manifest": _cached_manifest.duplicate(true),
				"navigation_base_raster": _duplicate_raster(_cached_navigation_raster),
				"manifest_sha256": manifest_hash,
				"dependency_paths": _cached_dependency_paths.duplicate(),
				"dependency_records": _cached_dependency_records.duplicate(true),
				"dependency_fingerprint": _cached_source_fingerprint,
				"gameplay_signature": _cached_gameplay_signature,
				"presentation_fingerprint": _cached_presentation_fingerprint,
			}
		var current_dependency_snapshot := _source_dependency_snapshot(
			_cached_manifest,
			manifest_hash,
		)
		var current_errors: PackedStringArray = current_dependency_snapshot.get(
			"errors",
			PackedStringArray(),
		)
		var current_source_fingerprint := str(current_dependency_snapshot.get(
			"fingerprint",
			"",
		))
		if (
			current_errors.is_empty()
			and not current_source_fingerprint.is_empty()
			and current_source_fingerprint == _cached_source_fingerprint
			and not _cached_navigation_raster.is_empty()
		):
			return {
				"errors": PackedStringArray(),
				"manifest": _cached_manifest.duplicate(true),
				"resolved_manifest": _cached_manifest.duplicate(true),
				"navigation_base_raster": _duplicate_raster(_cached_navigation_raster),
				"manifest_sha256": manifest_hash,
				"dependency_paths": (
					current_dependency_snapshot.get("paths", PackedStringArray())
					as PackedStringArray
				).duplicate(),
				"dependency_records": (
					current_dependency_snapshot.get("records", []) as Array
				).duplicate(true),
				"dependency_fingerprint": current_source_fingerprint,
				"gameplay_signature": _cached_gameplay_signature,
				"presentation_fingerprint": _cached_presentation_fingerprint,
			}
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return {"errors": PackedStringArray(["Nie można otworzyć manifestu mapy."])}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"errors": PackedStringArray(["Manifest mapy nie jest poprawnym obiektem JSON."])}
	var source_manifest := parsed as Dictionary
	var dependency_snapshot_before_validation := _source_dependency_snapshot(
		source_manifest,
		manifest_hash,
	)
	var dependency_errors: PackedStringArray = dependency_snapshot_before_validation.get(
		"errors",
		PackedStringArray(),
	)
	if not dependency_errors.is_empty():
		return {"errors": dependency_errors}
	var source_fingerprint_before_validation := str(
		dependency_snapshot_before_validation.get("fingerprint", "")
	)
	var errors := PackedStringArray()
	var manifest := _resolve_structure_packages(source_manifest, errors, false)
	if errors.is_empty():
		errors = _manifest_validation_errors(manifest)
	if not errors.is_empty():
		return {"errors": errors}
	var identities := _manifest_identities(manifest)
	var gameplay_signature := str(identities.get("gameplay_signature", ""))
	var presentation_fingerprint := str(identities.get("presentation_fingerprint", ""))
	errors.append_array(_generated_scene_errors(
		manifest,
		manifest_hash,
		gameplay_signature,
		presentation_fingerprint
	))
	if not errors.is_empty():
		return {"errors": errors}
	var navigation_raster := _build_navigation_base_raster(manifest)
	var raster_errors: PackedStringArray = navigation_raster.get("errors", PackedStringArray())
	if not raster_errors.is_empty():
		return {"errors": raster_errors}
	var dependency_snapshot := _source_dependency_snapshot(manifest, manifest_hash)
	dependency_errors = dependency_snapshot.get("errors", PackedStringArray())
	if not dependency_errors.is_empty():
		return {"errors": dependency_errors}
	var source_fingerprint := str(dependency_snapshot.get("fingerprint", ""))
	if source_fingerprint != source_fingerprint_before_validation:
		return {"errors": PackedStringArray([
			"Zależności źródła mapy zmieniły się podczas walidacji.",
		])}
	if (
		manifest_hash != _cached_manifest_hash
		or source_fingerprint != _cached_source_fingerprint
	):
		_cached_blueprints.clear()
	_cached_manifest_hash = manifest_hash
	_cached_manifest = manifest.duplicate(true)
	_cached_source_fingerprint = source_fingerprint
	_cached_dependency_paths = (
		dependency_snapshot.get("paths", PackedStringArray()) as PackedStringArray
	).duplicate()
	_cached_dependency_records = (
		dependency_snapshot.get("records", []) as Array
	).duplicate(true)
	_cached_gameplay_signature = gameplay_signature
	_cached_presentation_fingerprint = presentation_fingerprint
	_cached_navigation_raster = _duplicate_raster(navigation_raster)
	return {
		"errors": PackedStringArray(),
		"manifest": manifest.duplicate(true),
		"resolved_manifest": manifest.duplicate(true),
		"navigation_base_raster": _duplicate_raster(navigation_raster),
		"manifest_sha256": manifest_hash,
		"dependency_paths": _cached_dependency_paths.duplicate(),
		"dependency_records": _cached_dependency_records.duplicate(true),
		"dependency_fingerprint": source_fingerprint,
		"gameplay_signature": gameplay_signature,
		"presentation_fingerprint": presentation_fingerprint,
	}


func _generated_scene_errors(
	expected_manifest: Dictionary,
	expected_manifest_hash: String,
	expected_gameplay_signature: String,
	expected_presentation_fingerprint: String
) -> PackedStringArray:
	var errors := PackedStringArray()
	if expected_manifest_hash.is_empty():
		errors.append("Nie można zweryfikować sceny bez SHA-256 manifestu.")
		return errors
	if not ResourceLoader.exists(MAP_SCENE_PATH):
		errors.append("Brak wygenerowanej sceny mapy: %s." % MAP_SCENE_PATH)
		return errors
	var packed_scene := ResourceLoader.load(
		MAP_SCENE_PATH,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	if packed_scene == null:
		errors.append("Nie można załadować wygenerowanej sceny mapy.")
		return errors
	var root := packed_scene.instantiate()
	if root == null:
		errors.append("Nie można utworzyć instancji wygenerowanej sceny mapy.")
		return errors
	if str(root.get_meta("manifest_path", "")) != MANIFEST_PATH:
		errors.append("Scena mapy nie wskazuje jedynego manifestu.")
	if str(root.get_meta("manifest_sha256", "")).to_lower() != expected_manifest_hash:
		errors.append("UnderwaterMap.tscn jest nieaktualny względem manifestu; uruchom builder.")
	if str(root.get_meta("gameplay_signature", "")) != expected_gameplay_signature:
		errors.append("Scena mapy ma nieaktualny kanoniczny gameplay_signature.")
	if str(root.get_meta("presentation_fingerprint", "")) != expected_presentation_fingerprint:
		errors.append("Scena mapy ma nieaktualny presentation_fingerprint.")
	var expected_topology: Dictionary = expected_manifest.get("topology", {})
	var expected_structures: Dictionary = expected_manifest.get("structures", {})
	if str(expected_topology.get("mode", "")) == L05_TOPOLOGY_MODE:
		var expected_collision: Dictionary = expected_topology.get("collision_source", {})
		if str(root.get_meta("payload_sha256", "")).to_lower() != str(expected_collision.get("sha256", "")):
			errors.append("Scena mapy ma nieaktualny payload_sha256 L05.")
		if str(root.get_meta("canonical_digest", "")) != str(expected_collision.get("canonical_digest", "")):
			errors.append("Scena mapy ma nieaktualny canonical_digest L05.")
		if str(root.get_meta("partition_digest", "")) != str(expected_collision.get("partition_digest", "")):
			errors.append("Scena mapy ma nieaktualny partition_digest L05.")
		errors.append_array(_generated_l05_mask_errors(expected_topology, expected_structures))
	if int(root.get_meta("schema_version", 0)) != MANIFEST_SCHEMA_VERSION:
		errors.append("Scena mapy ma nieaktualny schema_version.")
	var expected_revision: Dictionary = expected_manifest.get("revision", {})
	var scene_revision = root.get_meta("revision", {})
	if not scene_revision is Dictionary or _canonical_json(scene_revision) != _canonical_json(expected_revision):
		errors.append("Scena mapy ma nieaktualne metadata revision.")
	for revision_key in ["revision_id", "topology_revision", "presentation_revision"]:
		if str(root.get_meta(revision_key, "")) != str(expected_revision.get(revision_key, "")):
			errors.append("Scena mapy ma nieaktualne metadata %s." % revision_key)
	var map_record: Dictionary = expected_manifest.get("map", {})
	var grid: Dictionary = map_record.get("grid", {})
	if int(root.get_meta("source_version", 0)) != int(map_record.get("source_version", 0)):
		errors.append("Scena mapy ma nieaktualną wersję źródła.")
	if root.get_meta("grid_size", Vector2i.ZERO) != Vector2i(
		int(grid.get("columns", 0)),
		int(grid.get("rows", 0))
	):
		errors.append("Scena mapy ma nieaktualne metadata grid_size.")
	if root.get_meta("cell_size", Vector2.ZERO) != _json_vector(grid.get("cell_size", [])):
		errors.append("Scena mapy ma nieaktualne metadata cell_size.")
	if root.get_meta("navigation_cell_size", Vector2.ZERO) != _json_vector(map_record.get("navigation_cell_size", [])):
		errors.append("Scena mapy ma nieaktualne metadata navigation_cell_size.")
	if root.get_meta("world_size", Vector2.ZERO) != _json_vector(map_record.get("world_size", [])):
		errors.append("Scena mapy ma nieaktualne metadata world_size.")
	var scene_topology = root.get_meta("topology", {})
	if not scene_topology is Dictionary or _canonical_json(scene_topology) != _canonical_json(expected_manifest.get("topology", {})):
		errors.append("Scena mapy ma nieaktualne metadata topology.")
	var scene_campaign = root.get_meta("campaign", {})
	if not scene_campaign is Dictionary or _canonical_json(scene_campaign) != _canonical_json(expected_manifest.get("campaign", {})):
		errors.append("Scena mapy ma nieaktualne metadata campaign.")
	var scene_structures = root.get_meta("structures", {})
	if (
		not scene_structures is Dictionary
		or _canonical_json(scene_structures) != _canonical_json(expected_structures)
	):
		errors.append("Scena mapy ma nieaktualne metadata structures.")
	var visual_layers := root.get_node_or_null("VisualLayers") as Node2D
	if visual_layers == null:
		errors.append("Scena mapy nie zawiera VisualLayers.")
	else:
		var expected_visual: Dictionary = expected_manifest.get("visual", {})
		var expected_layers: Array = expected_visual.get("layers", [])
		errors.append_array(_generated_visual_layer_errors(visual_layers, expected_layers))
		errors.append_array(
			_generated_portal_backdrop_clearance_errors(
				visual_layers,
				expected_visual,
			)
		)
	var structure_roots := root.get_node_or_null("StructureRoots") as Node2D
	if structure_roots == null:
		errors.append("Scena mapy nie zawiera StructureRoots.")
	else:
		errors.append_array(_generated_structure_root_errors(
			structure_roots,
			expected_structures,
			expected_manifest.get("visual", {}) as Dictionary,
		))
	root.free()
	return errors


func _resolve_structure_packages(
	manifest: Dictionary,
	errors: PackedStringArray,
	allow_expanded_fixtures: bool,
) -> Dictionary:
	var structures_value = manifest.get("structures", null)
	if not structures_value is Dictionary:
		errors.append("Manifest wymaga obiektu structures.")
		return {}
	var registry := structures_value as Dictionary
	if _dictionary_has_exact_keys(registry, ["templates", "instances"]):
		if allow_expanded_fixtures:
			return manifest.duplicate(true)
		errors.append(
			"Produkcyjny schema v6 wymaga rejestru structures.instances z odwołaniami package."
		)
		return {}
	if not _dictionary_has_exact_keys(registry, STRUCTURE_REGISTRY_KEYS):
		errors.append("Schema v6 structures musi zawierać wyłącznie instances.")
		return {}
	var topology_value = manifest.get("topology", null)
	if not topology_value is Dictionary:
		errors.append("Rozwiązanie pakietów struktur wymaga topology.")
		return {}
	var collision_value = (topology_value as Dictionary).get("collision_source", null)
	if not collision_value is Dictionary:
		errors.append("Rozwiązanie pakietów struktur wymaga topology.collision_source.")
		return {}
	var collision := collision_value as Dictionary
	var canonical_digest := str(collision.get("canonical_digest", ""))
	var partition_digest := str(collision.get("partition_digest", ""))
	if not _valid_topology_digest(canonical_digest):
		errors.append(
			"topology.collision_source.canonical_digest musi być zadeklarowany przed rozwiązaniem struktur."
		)
	if not _valid_partition_digest(partition_digest):
		errors.append(
			"topology.collision_source.partition_digest musi być zadeklarowany przed rozwiązaniem struktur."
		)
	var instances_value = registry.get("instances", null)
	if not instances_value is Array:
		errors.append("structures.instances musi być tablicą rejestru pakietów.")
		return {}
	var templates: Array = []
	var templates_by_id: Dictionary = {}
	var resolved_instances: Array = []
	var package_visual_assets: Array = []
	var registry_ids: Dictionary = {}
	var package_paths: Dictionary = {}
	for index in range((instances_value as Array).size()):
		var registry_record_value = (instances_value as Array)[index]
		var registry_label := "structures.instances[%d]" % index
		if not registry_record_value is Dictionary:
			errors.append("%s musi być obiektem." % registry_label)
			continue
		var registry_record := registry_record_value as Dictionary
		if not _dictionary_has_required_and_optional_keys(
			registry_record,
			STRUCTURE_REGISTRY_INSTANCE_REQUIRED_KEYS,
			STRUCTURE_REGISTRY_INSTANCE_OPTIONAL_KEYS,
		):
			errors.append(
				"%s wymaga id, origin, enabled i package; landmark_id jest opcjonalne."
				% registry_label
			)
		var structure_id_value = registry_record.get("id", null)
		var structure_id := str(structure_id_value).strip_edges()
		if (
			not structure_id_value is String
			or not _valid_lower_snake_case_id(structure_id)
			or registry_ids.has(structure_id)
		):
			errors.append("%s.id musi być unikalnym lowercase snake_case." % registry_label)
			continue
		registry_ids[structure_id] = true
		if not _valid_finite_number_array(registry_record.get("origin", null), 2):
			errors.append("%s.origin musi zawierać dwie skończone liczby." % registry_label)
		if typeof(registry_record.get("enabled", null)) != TYPE_BOOL:
			errors.append("%s.enabled musi być wartością logiczną." % registry_label)
		if registry_record.has("landmark_id"):
			var landmark_value = registry_record.get("landmark_id", null)
			if not landmark_value is String or str(landmark_value).strip_edges().is_empty():
				errors.append("%s.landmark_id musi być niepustym Stringiem." % registry_label)

		var package_reference_value = registry_record.get("package", null)
		if not package_reference_value is Dictionary:
			errors.append("%s.package musi być obiektem." % registry_label)
			continue
		var package_reference := package_reference_value as Dictionary
		if not _dictionary_has_exact_keys(package_reference, STRUCTURE_PACKAGE_REFERENCE_KEYS):
			errors.append("%s.package wymaga wyłącznie format, path i sha256." % registry_label)
			continue
		if str(package_reference.get("format", "")) != STRUCTURE_PACKAGE_REFERENCE_FORMAT:
			errors.append(
				"%s.package.format musi mieć wartość %s."
				% [registry_label, STRUCTURE_PACKAGE_REFERENCE_FORMAT]
			)
		var package_path_value = package_reference.get("path", null)
		var package_path := str(package_path_value).strip_edges()
		var expected_package_path := "structures/%s/structure_manifest.json" % structure_id
		if not package_path_value is String or package_path != expected_package_path:
			errors.append(
				"%s.package.path musi mieć wartość %s."
				% [registry_label, expected_package_path]
			)
			continue
		if package_paths.has(package_path):
			errors.append("%s.package.path może być wskazane dokładnie raz." % registry_label)
			continue
		package_paths[package_path] = true
		var package_resource_path := _workbench_resource_path(package_path, ["structures"])
		if package_resource_path.is_empty() or not FileAccess.file_exists(package_resource_path):
			errors.append("Pakiet struktury nie istnieje: %s." % package_path)
			continue
		var declared_package_sha_value = package_reference.get("sha256", null)
		if (
			not declared_package_sha_value is String
			or not _valid_sha256(str(declared_package_sha_value), false)
		):
			errors.append("%s.package.sha256 musi być małym SHA-256." % registry_label)
			continue
		var actual_package_sha := FileAccess.get_sha256(package_resource_path).to_lower()
		if actual_package_sha != str(declared_package_sha_value):
			errors.append(
				"%s.package.sha256 jest nieaktualne; oczekiwane %s."
				% [registry_label, actual_package_sha]
			)
			continue
		var package_file := FileAccess.open(package_resource_path, FileAccess.READ)
		if package_file == null:
			errors.append("Nie można otworzyć pakietu struktury %s." % structure_id)
			continue
		var package_value = JSON.parse_string(package_file.get_as_text())
		package_file.close()
		if not package_value is Dictionary:
			errors.append("Pakiet struktury %s nie jest poprawnym obiektem JSON." % structure_id)
			continue
		var package := package_value as Dictionary
		var package_label := "structure package %s" % structure_id
		if not _dictionary_has_exact_keys(package, STRUCTURE_PACKAGE_KEYS):
			errors.append("%s ma niepoprawny dokładny zestaw pól." % package_label)
			continue
		if not _is_integral_number(package.get("schema_version", null)) or int(package.get("schema_version", 0)) != 1:
			errors.append("%s.schema_version musi mieć wartość 1." % package_label)
		if str(package.get("format", "")) != STRUCTURE_PACKAGE_FORMAT:
			errors.append(
				"%s.format musi mieć wartość %s." % [package_label, STRUCTURE_PACKAGE_FORMAT]
			)

		var template_value = package.get("template", null)
		var template_id := ""
		if not template_value is Dictionary:
			errors.append("%s.template musi być obiektem." % package_label)
		else:
			var template := template_value as Dictionary
			if not _dictionary_has_exact_keys(template, [
				"id", "kind", "interior_layer_id", "collider_layer_id", "allowed_socket_kinds",
			]):
				errors.append("%s.template ma niepoprawny dokładny zestaw pól." % package_label)
			template_id = str(template.get("id", "")).strip_edges()
			if template_id.is_empty():
				errors.append("%s.template.id musi być niepuste." % package_label)
			elif not templates_by_id.has(template_id):
				templates_by_id[template_id] = template.duplicate(true)
				templates.append(template.duplicate(true))
			elif _canonical_json(templates_by_id[template_id]) != _canonical_json(template):
				errors.append("%s.template koliduje z szablonem %s." % [package_label, template_id])

		var topology_result := _resolve_structure_package_collision(
			package,
			structure_id,
			package_label,
			errors,
		)
		var scripts_by_role := _resolve_structure_package_scripts(
			package,
			package_path,
			package_label,
			errors,
		)
		_validate_structure_package_attempt_state_and_references(
			package,
			package_path,
			package_label,
			errors,
		)
		var resolved_assets := _resolve_structure_package_visual_assets(
			package,
			package_path,
			structure_id,
			canonical_digest,
			partition_digest,
			package_label,
			errors,
		)
		package_visual_assets.append_array(resolved_assets)

		var resolved_instance := {
			"id": structure_id,
			"template_id": template_id,
			"origin": (
				(registry_record.get("origin") as Array).duplicate(true)
				if registry_record.get("origin", null) is Array
				else []
			),
			"size": (
				(package.get("size") as Array).duplicate(true)
				if package.get("size", null) is Array
				else []
			),
			"enabled": bool(registry_record.get("enabled", false)),
			"topology_digest": canonical_digest,
			"partition_digest": partition_digest,
			"sockets": (
				(package.get("sockets") as Array).duplicate(true)
				if package.get("sockets", null) is Array
				else []
			),
			"runtime": (
				(package.get("runtime") as Dictionary).duplicate(true)
				if package.get("runtime", null) is Dictionary
				else {}
			),
			"controller_script": str(scripts_by_role.get(STRUCTURE_PACKAGE_REQUIRED_SCRIPT_ROLE, "")),
			"package_path": package_path,
			"package_sha256": actual_package_sha,
			"local_topology_digest": str(topology_result.get("local_topology_digest", "")),
			"collision_operations": topology_result.get("operations", []).duplicate(true),
			"structure_scene_path": (
				"res://underwater_map_workbench/structures/%s/generated/structure.tscn"
				% structure_id
			),
		}
		if registry_record.has("landmark_id"):
			resolved_instance["landmark_id"] = registry_record.get("landmark_id")
		resolved_instances.append(resolved_instance)

	var resolved_manifest := manifest.duplicate(true)
	resolved_manifest["structures"] = {
		"templates": templates,
		"instances": resolved_instances,
	}
	var resolved_visual_value = resolved_manifest.get("visual", null)
	if resolved_visual_value is Dictionary:
		var resolved_visual := resolved_visual_value as Dictionary
		var existing_assets_value = resolved_visual.get("assets", null)
		if existing_assets_value is Array:
			var merged_assets := (existing_assets_value as Array).duplicate(true)
			merged_assets.append_array(package_visual_assets)
			resolved_visual["assets"] = merged_assets
	return resolved_manifest


func _resolve_structure_package_collision(
	package: Dictionary,
	structure_id: String,
	package_label: String,
	errors: PackedStringArray,
) -> Dictionary:
	var collision_value = package.get("collision", null)
	if not collision_value is Dictionary:
		errors.append("%s.collision musi być obiektem." % package_label)
		return {}
	var collision := collision_value as Dictionary
	if not _dictionary_has_exact_keys(collision, STRUCTURE_PACKAGE_COLLISION_KEYS):
		errors.append("%s.collision ma niepoprawny dokładny zestaw pól." % package_label)
		return {}
	if str(collision.get("format", "")) != STRUCTURE_PACKAGE_COLLISION_FORMAT:
		errors.append(
			"%s.collision.format musi mieć wartość %s."
			% [package_label, STRUCTURE_PACKAGE_COLLISION_FORMAT]
		)
	if str(collision.get("base", "")) != "open_water":
		errors.append("%s.collision.base musi mieć wartość open_water." % package_label)
	var pixel_size_value = collision.get("pixel_size", null)
	if not _valid_positive_integral_array(pixel_size_value, 2):
		errors.append("%s.collision.pixel_size wymaga dwóch dodatnich liczb całkowitych." % package_label)
		return {}
	var pixel_components := pixel_size_value as Array
	var pixel_size := Vector2i(int(pixel_components[0]), int(pixel_components[1]))
	if not _valid_finite_number_array(collision.get("world_units_per_pixel", null), 2):
		errors.append("%s.collision.world_units_per_pixel wymaga dwóch liczb." % package_label)
		return {}
	var world_units_per_pixel := _json_vector(collision.get("world_units_per_pixel", []))
	if world_units_per_pixel != L05_WORLD_UNITS_PER_PIXEL:
		errors.append("%s.collision.world_units_per_pixel musi mieć wartość [40, 40]." % package_label)
	if not _valid_finite_number_array(package.get("size", null), 2):
		errors.append("%s.size wymaga dwóch liczb." % package_label)
		return {}
	var structure_size := _json_vector(package.get("size", []))
	if Vector2(pixel_size) * world_units_per_pixel != structure_size:
		errors.append("%s.collision musi pokrywać cały rozmiar struktury." % package_label)
	var operations_value = collision.get("operations", null)
	if not operations_value is Array:
		errors.append("%s.collision.operations musi być tablicą." % package_label)
		return {}
	var cells := PackedByteArray()
	cells.resize(pixel_size.x * pixel_size.y)
	cells.fill(255)
	var operation_ids: Dictionary = {}
	var resolved_operations: Array = []
	for index in range((operations_value as Array).size()):
		var operation_value = (operations_value as Array)[index]
		var operation_label := "%s.collision.operations[%d]" % [package_label, index]
		if not operation_value is Dictionary:
			errors.append("%s musi być obiektem." % operation_label)
			continue
		var operation := operation_value as Dictionary
		if not _dictionary_has_exact_keys(operation, STRUCTURE_PACKAGE_OPERATION_KEYS):
			errors.append("%s wymaga wyłącznie id, op i rect_px." % operation_label)
			continue
		var operation_id_value = operation.get("id", null)
		var operation_id := str(operation_id_value).strip_edges()
		if (
			not operation_id_value is String
			or operation_id.is_empty()
			or operation_ids.has(operation_id)
		):
			errors.append("%s.id musi być niepuste i unikalne." % operation_label)
			continue
		operation_ids[operation_id] = true
		var operation_kind := str(operation.get("op", ""))
		if operation_kind not in ["solid_rect", "open_rect"]:
			errors.append("%s.op musi być solid_rect albo open_rect." % operation_label)
			continue
		var rect_value = operation.get("rect_px", null)
		if not _valid_integral_array(rect_value, 4):
			errors.append("%s.rect_px wymaga czterech liczb całkowitych." % operation_label)
			continue
		var rect := rect_value as Array
		var x := int(rect[0])
		var y := int(rect[1])
		var width := int(rect[2])
		var height := int(rect[3])
		if (
			x < 0
			or y < 0
			or width <= 0
			or height <= 0
			or x + width > pixel_size.x
			or y + height > pixel_size.y
		):
			errors.append("%s.rect_px wykracza poza raster struktury." % operation_label)
			continue
		var fill_value := 0 if operation_kind == "solid_rect" else 255
		for row in range(y, y + height):
			var start := row * pixel_size.x + x
			for cell_index in range(start, start + width):
				cells[cell_index] = fill_value
		resolved_operations.append({
			"id": operation_id,
			"op": operation_kind,
			"space": "structure_local_px",
			"structure_id": structure_id,
			"rect_px": rect.duplicate(true),
		})
	var digest_payload := {
		"pixel_size": [pixel_size.x, pixel_size.y],
		"world_units_per_pixel": [world_units_per_pixel.x, world_units_per_pixel.y],
		"encoding": {"solid": 0, "open_water": 255},
		"cells_hex": cells.hex_encode(),
	}
	var local_topology_digest := "structure-topology-v1:%s" % _canonical_sha256(digest_payload)
	var declared_digest_value = package.get("local_topology_digest", null)
	if (
		not declared_digest_value is String
		or not _valid_structure_topology_digest(str(declared_digest_value))
		or str(declared_digest_value) != local_topology_digest
	):
		errors.append(
			"%s.local_topology_digest jest nieaktualny; oczekiwane %s."
			% [package_label, local_topology_digest]
		)
	return {
		"local_topology_digest": local_topology_digest,
		"operations": resolved_operations,
	}


func _resolve_structure_package_scripts(
	package: Dictionary,
	package_path: String,
	package_label: String,
	errors: PackedStringArray,
) -> Dictionary:
	var result: Dictionary = {}
	var scripts_value = package.get("scripts", null)
	if not scripts_value is Array:
		errors.append("%s.scripts musi być tablicą." % package_label)
		return result
	if (scripts_value as Array).is_empty():
		errors.append("%s.scripts musi zawierać rolę controller." % package_label)
	for index in range((scripts_value as Array).size()):
		var script_value = (scripts_value as Array)[index]
		var script_label := "%s.scripts[%d]" % [package_label, index]
		if not script_value is Dictionary:
			errors.append("%s musi być obiektem." % script_label)
			continue
		var script := script_value as Dictionary
		if not _dictionary_has_exact_keys(script, STRUCTURE_PACKAGE_SCRIPT_KEYS):
			errors.append("%s wymaga wyłącznie role, path i sha256." % script_label)
			continue
		var role_value = script.get("role", null)
		var role := str(role_value).strip_edges()
		if not role_value is String or not _valid_lower_snake_case_id(role) or result.has(role):
			errors.append("%s.role musi być unikalnym lowercase snake_case." % script_label)
			continue
		var resource_path := _structure_package_member_resource_path(
			package_path,
			str(script.get("path", "")),
		)
		if resource_path.is_empty() or not FileAccess.file_exists(resource_path):
			errors.append("%s.path nie istnieje lub opuszcza pakiet." % script_label)
			continue
		if not _validate_expected_file_sha(resource_path, script.get("sha256", null), script_label, errors):
			continue
		result[role] = resource_path
	if not result.has(STRUCTURE_PACKAGE_REQUIRED_SCRIPT_ROLE):
		errors.append(
			"%s.scripts nie zawiera wymaganej roli %s."
			% [package_label, STRUCTURE_PACKAGE_REQUIRED_SCRIPT_ROLE]
		)
	return result


func _validate_structure_package_attempt_state_and_references(
	package: Dictionary,
	package_path: String,
	package_label: String,
	errors: PackedStringArray,
) -> void:
	var attempt_state_value = package.get("attempt_state", null)
	if (
		not attempt_state_value is Dictionary
		or _canonical_json(attempt_state_value) != _canonical_json(STRUCTURE_PACKAGE_ATTEMPT_STATE)
	):
		errors.append("%s.attempt_state musi wyłączać persistence i checkpointy." % package_label)
	var references_value = package.get("references", null)
	if not references_value is Array:
		errors.append("%s.references musi być tablicą." % package_label)
		return
	for index in range((references_value as Array).size()):
		var reference_value = (references_value as Array)[index]
		var reference_label := "%s.references[%d]" % [package_label, index]
		if not reference_value is Dictionary:
			errors.append("%s musi być obiektem." % reference_label)
			continue
		var reference := reference_value as Dictionary
		if not _dictionary_has_exact_keys(reference, STRUCTURE_PACKAGE_REFERENCE_RECORD_KEYS):
			errors.append("%s ma niepoprawny dokładny zestaw pól." % reference_label)
			continue
		if reference.get("authority", null) != false:
			errors.append("%s.authority musi mieć wartość false." % reference_label)
		if str(reference.get("role", "")) != "design_reference_only":
			errors.append("%s.role musi mieć wartość design_reference_only." % reference_label)
		if not _string_set_equals(
			reference.get("excluded_topics", null),
			STRUCTURE_PACKAGE_REFERENCE_EXCLUDED_TOPICS,
		):
			errors.append("%s.excluded_topics nie zachowuje odrzuconych kontraktów." % reference_label)
		var resolved_reference_path := _structure_package_member_workbench_path(
			package_path,
			str(reference.get("path", "")),
		)
		if resolved_reference_path.is_empty():
			errors.append("%s.path opuszcza pakiet." % reference_label)
		if not reference.get("sha256", null) is String or not _valid_sha256(
			str(reference.get("sha256", "")),
			false,
		):
			errors.append("%s.sha256 musi być małym SHA-256." % reference_label)


func _resolve_structure_package_visual_assets(
	package: Dictionary,
	package_path: String,
	structure_id: String,
	canonical_digest: String,
	partition_digest: String,
	package_label: String,
	errors: PackedStringArray,
) -> Array:
	var result: Array = []
	var assets_value = package.get("visual_assets", null)
	if not assets_value is Array:
		errors.append("%s.visual_assets musi być tablicą." % package_label)
		return result
	for index in range((assets_value as Array).size()):
		var asset_value = (assets_value as Array)[index]
		var asset_label := "%s.visual_assets[%d]" % [package_label, index]
		if not asset_value is Dictionary:
			errors.append("%s musi być obiektem." % asset_label)
			continue
		var asset := asset_value as Dictionary
		if not _dictionary_has_exact_keys(asset, STRUCTURE_PACKAGE_VISUAL_ASSET_KEYS):
			errors.append("%s ma niepoprawny dokładny zestaw pól." % asset_label)
			continue
		var resolved_path := _structure_package_member_workbench_path(
			package_path,
			str(asset.get("path", "")),
		)
		var resource_path := _workbench_resource_path(resolved_path, ["structures"])
		if resolved_path.is_empty() or resource_path.is_empty() or not FileAccess.file_exists(resource_path):
			errors.append("%s.path nie istnieje lub opuszcza pakiet." % asset_label)
			continue
		var resolved_asset := asset.duplicate(true)
		resolved_asset["path"] = resolved_path
		resolved_asset["topology_digest"] = canonical_digest
		resolved_asset["partition_digest"] = partition_digest
		resolved_asset["structure_id"] = structure_id
		result.append(resolved_asset)
	return result


func _manifest_validation_errors(manifest: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not _canonical_numbers_are_finite(manifest):
		errors.append("Manifest nie może zawierać NaN ani nieskończonych liczb.")
	if not _is_integral_number(manifest.get("schema_version", null)) or int(manifest.get("schema_version", 0)) != MANIFEST_SCHEMA_VERSION:
		errors.append("Manifest musi używać schema_version=%d." % MANIFEST_SCHEMA_VERSION)
	var map_value = manifest.get("map", null)
	var revision_value = manifest.get("revision", null)
	var campaign_value = manifest.get("campaign", null)
	var visual_value = manifest.get("visual", null)
	var regions_value = manifest.get("regions", null)
	var topology_value = manifest.get("topology", null)
	var entry_value = manifest.get("entry", null)
	var exit_value = manifest.get("exit", null)
	var landmarks_value = manifest.get("landmarks", null)
	var gameplay_value = manifest.get("gameplay", null)
	var depth_value = manifest.get("depth_profile", null)
	var structures_value = manifest.get("structures", null)
	if (
		not map_value is Dictionary
		or not revision_value is Dictionary
		or not campaign_value is Dictionary
		or not visual_value is Dictionary
		or not regions_value is Array
		or not topology_value is Dictionary
		or not entry_value is Dictionary
		or not exit_value is Dictionary
		or not landmarks_value is Array
		or not gameplay_value is Dictionary
		or not depth_value is Array
		or not structures_value is Dictionary
	):
		errors.append("Manifest nie zawiera kompletnego kontraktu mapy.")
		return errors

	var revision := revision_value as Dictionary
	for revision_key in ["revision_id", "topology_revision", "presentation_revision"]:
		var revision_component = revision.get(revision_key, null)
		if not revision_component is String or str(revision_component).strip_edges().is_empty():
			errors.append("revision.%s musi być niepustym Stringiem." % revision_key)

	var map_record := map_value as Dictionary
	var grid_value = map_record.get("grid", null)
	if not grid_value is Dictionary:
		errors.append("Manifest nie zawiera map.grid.")
		return errors
	var grid := grid_value as Dictionary
	if not _is_integral_number(map_record.get("source_version", null)) or int(map_record.get("source_version", 0)) != MAP_SOURCE_VERSION:
		errors.append("Manifest musi używać map.source_version=%d." % MAP_SOURCE_VERSION)
	var columns_value = grid.get("columns", null)
	var rows_value = grid.get("rows", null)
	var columns := int(columns_value) if _is_integral_number(columns_value) else 0
	var rows := int(rows_value) if _is_integral_number(rows_value) else 0
	if columns <= 0 or rows <= 0:
		errors.append("map.grid columns i rows muszą być dodatnimi liczbami całkowitymi.")
	elif Vector2i(columns, rows) != REQUIRED_GRID_SIZE:
		errors.append("map.grid musi mieć dokładnie 12 x 12 komórek.")
	var cell_size := _json_vector(grid.get("cell_size", null))
	if not cell_size.is_finite() or cell_size.x <= 0.0 or cell_size.y <= 0.0:
		errors.append("map.grid.cell_size musi zawierać dodatni rozmiar komórki.")
	elif cell_size != REQUIRED_GRID_CELL_SIZE:
		errors.append("map.grid.cell_size musi mieć dokładnie 1920 x 1080 jednostek.")
	var world_size := _json_vector(map_record.get("world_size", null))
	if not world_size.is_finite() or world_size.x <= 0.0 or world_size.y <= 0.0:
		errors.append("map.world_size musi zawierać dodatni rozmiar świata.")
	elif columns > 0 and rows > 0 and cell_size.is_finite() and world_size != (
		Vector2(float(columns) * cell_size.x, float(rows) * cell_size.y)
	):
		errors.append("map.world_size musi dokładnie odpowiadać rozmiarowi siatki.")
	elif world_size != REQUIRED_WORLD_SIZE:
		errors.append("map.world_size musi mieć dokładnie 23040 x 12960 jednostek.")
	var navigation_cell_size := _json_vector(map_record.get("navigation_cell_size", null))
	if not navigation_cell_size.is_finite() or navigation_cell_size.x <= 0.0 or navigation_cell_size.y <= 0.0:
		errors.append("map.navigation_cell_size musi zawierać dodatni rozmiar komórki.")
	elif world_size.is_finite() and (
		absf(
			world_size.x / navigation_cell_size.x
			- round(world_size.x / navigation_cell_size.x)
		) > 1.0e-9
		or absf(
			world_size.y / navigation_cell_size.y
			- round(world_size.y / navigation_cell_size.y)
		) > 1.0e-9
	):
		errors.append("map.navigation_cell_size musi dzielić rozmiar świata bez reszty.")
	if (
		not _is_integral_number(map_record.get("chunk_size", null))
		or int(map_record.get("chunk_size", 0)) <= 0
		or not map_record.get("id", null) is String
		or str(map_record.get("id", "")).strip_edges().is_empty()
	):
		errors.append("Mapa wymaga ID i dodatniego chunk_size.")

	var seen_ids := {"exit": true}
	var regions := _dictionary_array(regions_value, "regions", errors)
	if regions.is_empty():
		errors.append("Mapa wymaga co najmniej jednego regionu.")
	var region_ids := {}
	var region_bounds_by_id := {}
	for region in regions:
		var region_id_value = region.get("id", null)
		var region_id := str(region_id_value).strip_edges()
		if not region_id_value is String:
			errors.append("ID regionu musi być Stringiem.")
		_register_unique_id(region_id, "regionu", seen_ids, errors)
		if not region_id.is_empty():
			region_ids[region_id] = true
		var bounds := _json_rect(region.get("bounds", null))
		if not _rect_inside_world(bounds, world_size):
			errors.append("Region %s ma niepoprawne bounds lub wykracza poza mapę." % region_id)
		else:
			region_bounds_by_id[region_id] = bounds
		if str(region.get("display_name", "")).strip_edges().is_empty():
			errors.append("Region %s wymaga nazwy wyświetlanej." % region_id)
		for color_key in ["water_color", "accent_color"]:
			if not _valid_json_color(region.get(color_key, null)):
				errors.append("Region %s wymaga poprawnego koloru %s." % [region_id, color_key])

	var landmarks := landmarks_value as Array
	if landmarks.is_empty():
		errors.append("Mapa wymaga co najmniej landmarku wejściowego.")
	var landmark_ids := {}
	var landmarks_by_id := {}
	for index in range(landmarks.size()):
		var landmark_value = landmarks[index]
		if not landmark_value is Dictionary:
			errors.append("landmarks[%d] musi być obiektem." % index)
			continue
		var landmark := landmark_value as Dictionary
		var landmark_id_value = landmark.get("id", null)
		var landmark_id := str(landmark_id_value).strip_edges()
		if not landmark_id_value is String:
			errors.append("ID landmarku musi być Stringiem.")
		_register_unique_id(landmark_id, "landmarku", seen_ids, errors)
		if not landmark_id.is_empty():
			landmark_ids[landmark_id] = true
			landmarks_by_id[landmark_id] = landmark
		if str(landmark.get("display_name", "")).strip_edges().is_empty():
			errors.append("Landmark %s wymaga nazwy wyświetlanej." % landmark_id)
		if str(landmark.get("short_name", "")).strip_edges().is_empty():
			errors.append("Landmark %s wymaga krótkiej nazwy." % landmark_id)
		if str(landmark.get("role", "")).strip_edges().is_empty():
			errors.append("Landmark %s wymaga roli." % landmark_id)
		var region_id := str(landmark.get("region_id", "")).strip_edges()
		if not region_ids.has(region_id):
			errors.append("Landmark %s wskazuje nieznany region %s." % [landmark_id, region_id])
		var landmark_position := _json_vector(landmark.get("position", null))
		if not _point_inside_world(landmark_position, world_size):
			errors.append("Landmark %s leży poza mapą." % landmark_id)
		elif region_bounds_by_id.has(region_id) and not (region_bounds_by_id[region_id] as Rect2).has_point(landmark_position):
			errors.append("Landmark %s leży poza swoim regionem %s." % [landmark_id, region_id])
		var landmark_size := _json_vector(landmark.get("size", null))
		if not landmark_size.is_finite() or landmark_size.x <= 0.0 or landmark_size.y <= 0.0:
			errors.append("Landmark %s wymaga dodatniego rozmiaru." % landmark_id)
		var aliases_value = landmark.get("aliases", [])
		if not aliases_value is Array:
			errors.append("Landmark %s ma niepoprawną tablicę aliases." % landmark_id)

	var landmark_refs := {}
	for canonical_landmark_id in landmark_ids.keys():
		landmark_refs[canonical_landmark_id] = str(canonical_landmark_id)
	for landmark in landmarks_by_id.values():
		var aliases_value = (landmark as Dictionary).get("aliases", [])
		if not aliases_value is Array:
			continue
		for alias_value in aliases_value as Array:
			var alias := str(alias_value).strip_edges()
			if not alias_value is String or alias.is_empty() or landmark_refs.has(alias) or seen_ids.has(alias):
				errors.append("Alias landmarku %s jest pusty lub niejednoznaczny." % alias)
			else:
				landmark_refs[alias] = str((landmark as Dictionary).get("id", ""))
				seen_ids[alias] = true

	var entry := entry_value as Dictionary
	var exit_record := exit_value as Dictionary
	var entry_landmark_id_value = entry.get("landmark_id", null)
	var entry_landmark_id := str(entry_landmark_id_value).strip_edges()
	var canonical_entry_landmark_id := str(landmark_refs.get(entry_landmark_id, ""))
	if not entry_landmark_id_value is String:
		errors.append("entry.landmark_id musi być Stringiem.")
	if not landmark_refs.has(entry_landmark_id):
		errors.append("Punkt wejścia musi wskazywać landmark zadeklarowany w manifeście.")
	var entry_position := _json_vector(entry.get("position", null))
	if not _point_inside_world(entry_position, world_size):
		errors.append("Punkt wejścia leży poza mapą.")
	elif landmark_refs.has(entry_landmark_id):
		var entry_landmark: Dictionary = landmarks_by_id.get(canonical_entry_landmark_id, {})
		if not entry_position.is_equal_approx(_json_vector(entry_landmark.get("position", null))):
			errors.append("Punkt wejścia musi pokrywać się z pozycją wskazanego landmarku.")
	if not _point_inside_world(_json_vector(exit_record.get("position", null)), world_size):
		errors.append("Punkt powrotu leży poza mapą.")

	var depth_profile := depth_value as Array
	if depth_profile.size() != WorldBlueprintScript.DEPTH_PROFILE_POINT_COUNT:
		errors.append("Profil głębokości musi mieć dokładnie pięć punktów.")
	else:
		var points := PackedVector2Array()
		for value in depth_profile:
			points.append(_json_vector(value))
		errors.append_array(WorldBlueprintScript.depth_profile_validation_errors(points))

	_validate_structures(
		structures_value as Dictionary,
		landmark_ids,
		world_size,
		topology_value as Dictionary,
		seen_ids,
		errors
	)
	_validate_topology(
		topology_value as Dictionary,
		structures_value as Dictionary,
		world_size,
		navigation_cell_size,
		errors
	)
	_validate_visual(
		visual_value as Dictionary,
		world_size,
		topology_value as Dictionary,
		structures_value as Dictionary,
		errors
	)

	var gameplay := gameplay_value as Dictionary
	var structure_instances_by_id := _structure_instances_by_id(structures_value as Dictionary)
	if typeof(gameplay.get("tutorial_enabled", null)) != TYPE_BOOL:
		errors.append("gameplay.tutorial_enabled musi być wartością logiczną.")
	var gameplay_keys := [
		"loot_spawns", "shortcut_spawns", "fixed_device_spawns", "connections",
		"pickups", "current_zones", "threat_spawns", "heavy_object_spawns",
		"rescue_spawns", "buoy_spawns", "obstacle_spawns", "decoration_spawns",
	]
	var records_by_collection := {}
	for gameplay_key in gameplay_keys:
		var records := _dictionary_array(gameplay.get(gameplay_key, null), "gameplay.%s" % gameplay_key, errors)
		records_by_collection[gameplay_key] = records
		for record in records:
			var record_id_value = record.get("id", null)
			var record_id := str(record_id_value).strip_edges()
			if not record_id_value is String:
				errors.append("ID obiektu gameplayu musi być Stringiem.")
			_register_unique_id(record_id, "obiektu gameplayu", seen_ids, errors)
			if gameplay_key != "connections":
				var world_position := _json_vector(record.get("position", null))
				if gameplay_key == "fixed_device_spawns" and str(record.get("position_space", "world")) == "structure_local":
					var structure_id := str(record.get("structure_id", "")).strip_edges()
					if not structure_instances_by_id.has(structure_id):
						errors.append("Urządzenie %s wskazuje nieznaną strukturę %s." % [record_id, structure_id])
					else:
						var structure: Dictionary = structure_instances_by_id[structure_id]
						if not bool(structure.get("enabled", false)):
							errors.append("Urządzenie %s wskazuje wyłączoną strukturę %s." % [record_id, structure_id])
						var local_size := _json_vector(structure.get("size", []))
						if not _point_inside_local_rect(world_position, local_size):
							errors.append("Urządzenie %s leży poza lokalnym obrysem struktury %s." % [record_id, structure_id])
						world_position += _json_vector(structure.get("origin", []))
				elif record.has("position_space") and str(record.get("position_space", "")) != "world":
					errors.append("Obiekt gameplayu %s ma nieobsługiwane position_space." % record_id)
				elif gameplay_key == "fixed_device_spawns" and record.has("structure_id"):
					errors.append("Urządzenie %s może mieć structure_id tylko w structure_local." % record_id)
				if not _point_inside_world(world_position, world_size):
					errors.append("Obiekt gameplayu %s leży poza mapą." % record_id)
			var landmark_id := str(record.get("landmark_id", "")).strip_edges()
			if not landmark_id.is_empty() and not landmark_ids.has(landmark_id):
				errors.append("Obiekt gameplayu %s wskazuje nieznany landmark %s." % [record_id, landmark_id])
			if record.has("contents"):
				var contents_value = record.get("contents", null)
				if not contents_value is Dictionary or (contents_value as Dictionary).is_empty():
					errors.append("Źródło łupu %s wymaga niepustej zawartości." % record_id)
					continue
				for item_id in (contents_value as Dictionary).keys():
					var amount_value = (contents_value as Dictionary)[item_id]
					if (
						str(item_id).strip_edges().is_empty()
						or not _is_integral_number(amount_value)
						or int(amount_value) <= 0
					):
						errors.append("Źródło łupu %s ma niepoprawną ilość zasobu." % record_id)
				if gameplay_key == "pickups" and not _pickup_contents_are_single_item(contents_value as Dictionary):
					errors.append("Pickup %s musi zawierać dokładnie jedną sztukę jednego zasobu." % record_id)

	var connection_ids := {}
	for connection in records_by_collection.get("connections", []):
		var connection_id := str((connection as Dictionary).get("id", ""))
		connection_ids[connection_id] = true
		var from_id := str((connection as Dictionary).get("from_id", "")).strip_edges()
		var to_id := str((connection as Dictionary).get("to_id", "")).strip_edges()
		if not landmark_ids.has(from_id) or not landmark_ids.has(to_id):
			errors.append("Połączenie %s musi wskazywać istniejące landmarki from/to." % connection_id)
		var path_value = (connection as Dictionary).get("path_points", (connection as Dictionary).get("path", null))
		if not path_value is Array or (path_value as Array).size() < 2:
			errors.append("Połączenie %s wymaga co najmniej dwóch punktów trasy." % connection_id)
			continue
		for point_value in path_value as Array:
			if not _point_inside_world(_json_vector(point_value), world_size):
				errors.append("Połączenie %s ma punkt trasy poza mapą." % connection_id)
	for collection_name in records_by_collection.keys():
		for record in records_by_collection[collection_name]:
			var referenced_connection_id := str((record as Dictionary).get("connection_id", "")).strip_edges()
			if not referenced_connection_id.is_empty() and not connection_ids.has(referenced_connection_id):
				errors.append(
					"Obiekt %s wskazuje nieznane połączenie %s."
					% [(record as Dictionary).get("id", ""), referenced_connection_id]
				)
	if (
		str((topology_value as Dictionary).get("mode", "")) == "open_world"
		and not (records_by_collection.get("obstacle_spawns", []) as Array).is_empty()
	):
		errors.append("open_world wymaga pustego gameplay.obstacle_spawns; L05 pozostaje jedynym authority kolizji.")
	_validate_campaign(
		campaign_value as Dictionary,
		landmark_ids,
		records_by_collection.get("fixed_device_spawns", []) as Array,
		errors
	)

	var tutorial_route_value = gameplay.get("tutorial_route", null)
	if not tutorial_route_value is Array:
		errors.append("gameplay.tutorial_route musi być tablicą ID.")
	if bool(gameplay.get("tutorial_enabled", false)):
		_validate_tutorial_roles(
			gameplay,
			records_by_collection,
			landmarks_by_id,
			entry_landmark_id,
			canonical_entry_landmark_id,
			errors
		)
	if tutorial_route_value is Array:
		for route_id_value in tutorial_route_value as Array:
			var route_id := str(route_id_value).strip_edges()
			if not route_id_value is String or route_id.is_empty() or not seen_ids.has(route_id):
				errors.append("gameplay.tutorial_route wskazuje nieznane ID manifestu: %s." % route_id)
	return errors


func _build_blueprint(manifest: Dictionary, gameplay_signature: String, campaign_seed: int):
	var blueprint = WorldBlueprintScript.new()
	var map_record: Dictionary = manifest["map"]
	var entry: Dictionary = manifest["entry"]
	var exit_record: Dictionary = manifest["exit"]
	var gameplay: Dictionary = manifest["gameplay"]
	var structures: Dictionary = manifest["structures"]
	blueprint.campaign_seed = campaign_seed
	blueprint.map_source_version = int(map_record["source_version"])
	blueprint.map_id = str(map_record["id"])
	blueprint.map_gameplay_signature = gameplay_signature
	blueprint.world_size = _json_vector(map_record["world_size"])
	blueprint.chunk_size = int(map_record["chunk_size"])
	blueprint.depth_profile_points.clear()
	for point in manifest["depth_profile"]:
		blueprint.depth_profile_points.append(_json_vector(point))
	blueprint.entry_landmark_id = str(entry["landmark_id"])
	blueprint.entry_position = _json_vector(entry["position"])
	blueprint.exit_position = _json_vector(exit_record["position"])
	for region_source_value in manifest["regions"]:
		blueprint.regions.append(_region_record(region_source_value as Dictionary))
	for landmark_source_value in manifest["landmarks"]:
		blueprint.landmarks.append(_landmark_record(landmark_source_value as Dictionary))
	for structure_source_value in structures["instances"]:
		blueprint.structure_spawns.append(_structure_record(structure_source_value as Dictionary))
	blueprint.rebuild_indexes()
	var canonical_entry_landmark_id := blueprint.resolve_landmark_id(blueprint.entry_landmark_id)
	if not canonical_entry_landmark_id.is_empty():
		blueprint.entry_landmark_id = canonical_entry_landmark_id
	for source in gameplay["connections"]:
		blueprint.connections.append(_connection_record(source as Dictionary))
	for source in gameplay["loot_spawns"]:
		var loot_record := _loot_record(source as Dictionary, blueprint.entry_landmark_id)
		loot_record["spawn_kind"] = str((source as Dictionary).get("spawn_kind", "container"))
		blueprint.loot_spawns.append(loot_record)
	for source in gameplay["pickups"]:
		var pickup_record := _loot_record(source as Dictionary, blueprint.entry_landmark_id)
		pickup_record["spawn_kind"] = "pickup"
		blueprint.loot_spawns.append(pickup_record)
	for source in gameplay["current_zones"]:
		blueprint.current_zones.append(_spatial_gameplay_record(source as Dictionary))
	for source in gameplay["threat_spawns"]:
		blueprint.threat_spawns.append(_spatial_gameplay_record(source as Dictionary))
	for source in gameplay["heavy_object_spawns"]:
		blueprint.heavy_object_spawns.append(_spatial_gameplay_record(source as Dictionary))
	for source in gameplay["rescue_spawns"]:
		blueprint.rescue_spawns.append(_spatial_gameplay_record(source as Dictionary))
	for source in gameplay["buoy_spawns"]:
		blueprint.buoy_spawns.append(_spatial_gameplay_record(source as Dictionary))
	for source in gameplay["shortcut_spawns"]:
		blueprint.shortcut_spawns.append(_spatial_gameplay_record(source as Dictionary))
	for source in gameplay["fixed_device_spawns"]:
		blueprint.fixed_device_spawns.append(_fixed_device_record(
			source as Dictionary,
			blueprint.structure_lookup,
			blueprint.structure_spawns
		))
	for source in gameplay["obstacle_spawns"]:
		blueprint.obstacle_spawns.append(_spatial_gameplay_record(source as Dictionary))
	for source in gameplay["decoration_spawns"]:
		blueprint.decoration_spawns.append(_spatial_gameplay_record(source as Dictionary))
	blueprint.rebuild_indexes()
	_index_blueprint_chunks(blueprint)
	return blueprint


func _region_record(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result["id"] = str(source.get("id", ""))
	result["display_name"] = str(source.get("display_name", result["id"]))
	result["bounds"] = _json_rect(source.get("bounds", []))
	result["water_color"] = _json_color(source.get("water_color", "071d2a"))
	result["accent_color"] = _json_color(source.get("accent_color", "62a8b8"))
	result["backdrop_path"] = str(source.get("backdrop_path", ""))
	return result


func _landmark_record(source: Dictionary) -> Dictionary:
	var result := _spatial_gameplay_record(source)
	var stable_id := str(source.get("id", ""))
	result["id"] = stable_id
	result["design_id"] = str(source.get("design_id", stable_id))
	result["display_name"] = str(source.get("display_name", stable_id))
	result["short_name"] = str(source.get("short_name", result["display_name"]))
	result["region_id"] = str(source.get("region_id", ""))
	result["traversal_form"] = str(source.get("traversal_form", "open_water"))
	result["visual_kind"] = str(source.get("visual_kind", source.get("role", "landmark")))
	result["role"] = str(source.get("role", "landmark"))
	result["aliases"] = (source.get("aliases", []) as Array).duplicate()
	result["anchor_id"] = str(source.get("anchor_id", ""))
	return result


func _connection_record(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result["id"] = str(source.get("id", ""))
	result["from_id"] = str(source.get("from_id", ""))
	result["to_id"] = str(source.get("to_id", ""))
	var path_value = source.get("path_points", source.get("path", []))
	result["path_points"] = _json_vector_array(path_value)
	return result


func _loot_record(source: Dictionary, fallback_landmark_id: String) -> Dictionary:
	var result := _spatial_gameplay_record(source)
	result["id"] = str(source.get("id", ""))
	result["display_name"] = str(source.get("display_name", "Zasobnik"))
	result["landmark_id"] = str(source.get("landmark_id", fallback_landmark_id))
	result["contents"] = (source.get("contents", {}) as Dictionary).duplicate(true)
	result["mandatory_order"] = int(source.get("mandatory_order", -1))
	result["required_tool"] = str(source.get("required_tool", ""))
	result["interaction_action"] = str(source.get("interaction_action", "open"))
	result["interaction_seconds"] = float(source.get("interaction_seconds", 1.15))
	result["difficulty_scaled_contents"] = bool(source.get("difficulty_scaled_contents", true))
	return result


func _spatial_gameplay_record(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	for vector_key in ["position", "size", "center", "direction", "velocity", "extent"]:
		if source.has(vector_key):
			result[vector_key] = _json_vector(source.get(vector_key, []))
	if source.has("bounds"):
		result["bounds"] = _json_rect(source.get("bounds", []))
	if source.has("path_points"):
		result["path_points"] = _json_vector_array(source["path_points"])
	return result


func _structure_record(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result["origin"] = _json_vector(source.get("origin", []))
	result["size"] = _json_vector(source.get("size", []))
	var sockets: Array[Dictionary] = []
	for socket_value in source.get("sockets", []):
		if not socket_value is Dictionary:
			continue
		var socket := (socket_value as Dictionary).duplicate(true)
		socket["local_rect"] = _json_rect(socket.get("local_rect", []))
		sockets.append(socket)
	result["sockets"] = sockets
	if source.has("runtime") and source.get("runtime") is Dictionary:
		# Prywatny payload runtime należy do kontrolera pakietu. Kompilator Mapy
		# przekazuje go bez interpretacji, aby kolejne budynki nie wymagały zmian tutaj.
		result["runtime"] = (source.get("runtime") as Dictionary).duplicate(true)
	return result


func _fixed_device_record(
	source: Dictionary,
	structure_lookup: Dictionary,
	structure_spawns: Array[Dictionary]
) -> Dictionary:
	var result := _spatial_gameplay_record(source)
	var position_space := str(source.get("position_space", "world"))
	result["position_space"] = position_space
	result["structure_id"] = str(source.get("structure_id", ""))
	if position_space != "structure_local":
		return result
	var local_position := _json_vector(source.get("position", []))
	result["local_position"] = local_position
	var structure_index := int(structure_lookup.get(result["structure_id"], -1))
	if structure_index >= 0 and structure_index < structure_spawns.size():
		var structure: Dictionary = structure_spawns[structure_index]
		result["position"] = (structure.get("origin", Vector2.ZERO) as Vector2) + local_position
	return result


func _index_blueprint_chunks(blueprint) -> void:
	blueprint.chunk_index.clear()
	var records: Array[Dictionary] = []
	records.append_array(blueprint.regions)
	records.append_array(blueprint.landmarks)
	records.append_array(blueprint.loot_spawns)
	records.append_array(blueprint.current_zones)
	records.append_array(blueprint.threat_spawns)
	records.append_array(blueprint.heavy_object_spawns)
	records.append_array(blueprint.rescue_spawns)
	records.append_array(blueprint.buoy_spawns)
	records.append_array(blueprint.shortcut_spawns)
	records.append_array(blueprint.fixed_device_spawns)
	records.append_array(blueprint.obstacle_spawns)
	records.append_array(blueprint.decoration_spawns)
	for record in records:
		_index_spatial_record(blueprint, record)
	for structure in blueprint.structure_spawns:
		var origin: Vector2 = structure.get("origin", Vector2.ZERO)
		var size: Vector2 = structure.get("size", Vector2.ZERO)
		_index_rect_record(
			blueprint,
			Rect2(origin, size),
			str(structure.get("id", ""))
		)
	for connection in blueprint.connections:
		_index_connection_path(blueprint, connection)
	_add_chunk_record(
		blueprint,
		blueprint.chunk_coord_at(blueprint.entry_position),
		blueprint.entry_landmark_id
	)


func _index_spatial_record(blueprint, record: Dictionary) -> void:
	var record_id := str(record.get("id", ""))
	if record_id.is_empty():
		return
	var bounds_value = record.get("bounds", null)
	if bounds_value is Rect2 and (bounds_value as Rect2).has_area():
		_index_rect_record(blueprint, bounds_value as Rect2, record_id)
		return
	var position_value = record.get("position", null)
	if not position_value is Vector2 or not (position_value as Vector2).is_finite():
		return
	var position := position_value as Vector2
	var size_value = record.get("size", null)
	if (
		size_value is Vector2
		and (size_value as Vector2).is_finite()
		and (size_value as Vector2).x > 0.0
		and (size_value as Vector2).y > 0.0
	):
		var size := size_value as Vector2
		_index_rect_record(blueprint, Rect2(position - size * 0.5, size), record_id)
		return
	_add_chunk_record(blueprint, blueprint.chunk_coord_at(position), record_id)


func _index_rect_record(blueprint, bounds: Rect2, record_id: String) -> void:
	var world_bounds := Rect2(Vector2.ZERO, blueprint.world_size)
	var clipped := bounds.intersection(world_bounds)
	if not clipped.has_area():
		return
	var last_point := clipped.end - Vector2(0.001, 0.001)
	var first_coord: Vector2i = blueprint.chunk_coord_at(clipped.position)
	var last_coord: Vector2i = blueprint.chunk_coord_at(last_point)
	for chunk_y in range(first_coord.y, last_coord.y + 1):
		for chunk_x in range(first_coord.x, last_coord.x + 1):
			_add_chunk_record(blueprint, Vector2i(chunk_x, chunk_y), record_id)


func _index_connection_path(blueprint, connection: Dictionary) -> void:
	var connection_id := str(connection.get("id", ""))
	var path: PackedVector2Array = connection.get("path_points", PackedVector2Array())
	if connection_id.is_empty() or path.is_empty():
		return
	if path.size() == 1:
		_add_chunk_record(blueprint, blueprint.chunk_coord_at(path[0]), connection_id)
		return
	for index in range(1, path.size()):
		_index_connection_segment(blueprint, connection_id, path[index - 1], path[index])


func _index_connection_segment(
	blueprint,
	record_id: String,
	segment_start: Vector2,
	segment_end: Vector2
) -> void:
	var current: Vector2i = blueprint.chunk_coord_at(segment_start)
	var target: Vector2i = blueprint.chunk_coord_at(segment_end)
	_add_chunk_record(blueprint, current, record_id)
	if current == target:
		return
	var delta := segment_end - segment_start
	var step_x := 1 if delta.x > 0.0 else (-1 if delta.x < 0.0 else 0)
	var step_y := 1 if delta.y > 0.0 else (-1 if delta.y < 0.0 else 0)
	var chunk_size := float(maxi(int(blueprint.chunk_size), 1))
	var t_delta_x := INF if step_x == 0 else absf(chunk_size / delta.x)
	var t_delta_y := INF if step_y == 0 else absf(chunk_size / delta.y)
	var next_boundary_x := float(current.x + (1 if step_x > 0 else 0)) * chunk_size
	var next_boundary_y := float(current.y + (1 if step_y > 0 else 0)) * chunk_size
	var t_max_x := INF if step_x == 0 else (next_boundary_x - segment_start.x) / delta.x
	var t_max_y := INF if step_y == 0 else (next_boundary_y - segment_start.y) / delta.y
	var safety := absi(target.x - current.x) + absi(target.y - current.y) + 4
	while current != target and safety > 0:
		safety -= 1
		if is_equal_approx(t_max_x, t_max_y):
			if step_x != 0:
				_add_chunk_record(blueprint, current + Vector2i(step_x, 0), record_id)
			if step_y != 0:
				_add_chunk_record(blueprint, current + Vector2i(0, step_y), record_id)
			current += Vector2i(step_x, step_y)
			t_max_x += t_delta_x
			t_max_y += t_delta_y
		elif t_max_x < t_max_y:
			current.x += step_x
			t_max_x += t_delta_x
		else:
			current.y += step_y
			t_max_y += t_delta_y
		_add_chunk_record(blueprint, current, record_id)


func _add_chunk_record(blueprint, coord: Vector2i, record_id: String) -> void:
	if record_id.is_empty():
		return
	var chunk_size := float(maxi(int(blueprint.chunk_size), 1))
	var chunk_extent := Vector2i(
		ceili(blueprint.world_size.x / chunk_size),
		ceili(blueprint.world_size.y / chunk_size)
	)
	if coord.x < 0 or coord.y < 0 or coord.x >= chunk_extent.x or coord.y >= chunk_extent.y:
		return
	var key: String = blueprint.chunk_key(coord)
	if not blueprint.chunk_index.has(key):
		blueprint.chunk_index[key] = []
	var chunk_records := blueprint.chunk_index[key] as Array
	if not chunk_records.has(record_id):
		chunk_records.append(record_id)


func _manifest_identities(manifest: Dictionary) -> Dictionary:
	var gameplay_payload := {
		"map": (manifest.get("map", {}) as Dictionary).duplicate(true),
		"depth_profile": (manifest.get("depth_profile", []) as Array).duplicate(true),
		"regions": _records_without_fields(
			manifest.get("regions", []) as Array,
			["display_name", "water_color", "accent_color", "backdrop_path"]
		),
		"topology": _topology_identity_projection(manifest),
		"entry": (manifest.get("entry", {}) as Dictionary).duplicate(true),
		"exit": (manifest.get("exit", {}) as Dictionary).duplicate(true),
		"landmarks": _records_without_fields(
			manifest.get("landmarks", []) as Array,
			["display_name", "short_name", "visual_kind", "visual_scene_path", "backdrop_path"]
		),
		"structures": _structure_semantic_projection(manifest.get("structures", {}) as Dictionary),
		"gameplay": _gameplay_semantic_projection(manifest.get("gameplay", {}) as Dictionary),
		"campaign": (manifest.get("campaign", {}) as Dictionary).duplicate(true),
	}
	var revision: Dictionary = manifest.get("revision", {})
	var map_record: Dictionary = manifest.get("map", {})
	var presentation_payload := {
		"presentation_revision": revision.get("presentation_revision", ""),
		"portal_backdrop_clearance_contract": PORTAL_BACKDROP_CLEARANCE_CONTRACT,
		"map": {
			"grid": (map_record.get("grid", {}) as Dictionary).duplicate(true),
			"world_size": (map_record.get("world_size", []) as Array).duplicate(true),
		},
		"regions": (manifest.get("regions", []) as Array).duplicate(true),
		"landmarks": (manifest.get("landmarks", []) as Array).duplicate(true),
		"structures": _structure_semantic_projection(manifest.get("structures", {}) as Dictionary),
		"topology": _topology_identity_projection(manifest),
		"gameplay": (manifest.get("gameplay", {}) as Dictionary).duplicate(true),
		"campaign": (manifest.get("campaign", {}) as Dictionary).duplicate(true),
		"visual": (manifest.get("visual", {}) as Dictionary).duplicate(true),
	}
	return {
		"gameplay_signature": "manifest-v2:%s" % _canonical_sha256(gameplay_payload),
		"presentation_fingerprint": "presentation-v2:%s" % _canonical_sha256(presentation_payload),
	}


func _topology_identity_projection(manifest: Dictionary) -> Dictionary:
	var topology: Dictionary = manifest.get("topology", {})
	if str(topology.get("mode", "")) != L05_TOPOLOGY_MODE:
		return topology.duplicate(true)
	var collision: Dictionary = topology.get("collision_source", {})
	return {
		"mode": topology.get("mode", null),
		"authority_layer": topology.get("authority_layer", null),
		"collision_source": {
			"format": collision.get("format", null),
			"canonical_digest": collision.get("canonical_digest", null),
			"partition_digest": collision.get("partition_digest", null),
			"pixel_size": (collision.get("pixel_size", []) as Array).duplicate(true),
			"world_units_per_pixel": (
				collision.get("world_units_per_pixel", []) as Array
			).duplicate(true),
			"mapping": (collision.get("mapping", {}) as Dictionary).duplicate(true),
			"encoding": (collision.get("encoding", {}) as Dictionary).duplicate(true),
		},
		"protected_corridors": (
			topology.get("protected_corridors", []) as Array
		).duplicate(true),
	}


func _structure_semantic_projection(structures: Dictionary) -> Dictionary:
	var projected_instances: Array = []
	var instances_value = structures.get("instances", null)
	if instances_value is Array:
		for instance_value in instances_value as Array:
			if not instance_value is Dictionary:
				projected_instances.append(instance_value)
				continue
			var instance := instance_value as Dictionary
			var projected := {}
			for key in [
				"id", "template_id", "origin", "size", "enabled", "topology_digest",
				"partition_digest", "sockets",
			]:
				if instance.has(key):
					projected[key] = instance[key]
			for optional_key in ["landmark_id", "runtime"]:
				if instance.has(optional_key):
					projected[optional_key] = instance[optional_key]
			projected_instances.append(projected)
	var templates_value = structures.get("templates", [])
	return {
		"templates": (
			(templates_value as Array).duplicate(true)
			if templates_value is Array
			else templates_value
		),
		"instances": projected_instances,
	}


func _records_without_fields(records: Array, excluded_fields: Array) -> Array:
	var result := []
	for record_value in records:
		if not record_value is Dictionary:
			result.append(record_value)
			continue
		var record := (record_value as Dictionary).duplicate(true)
		for field_name in excluded_fields:
			record.erase(field_name)
		for raw_key in (record_value as Dictionary).keys():
			if str(raw_key).begins_with("visual_"):
				record.erase(raw_key)
		result.append(record)
	return result


func _gameplay_semantic_projection(gameplay: Dictionary) -> Dictionary:
	var semantic_gameplay := gameplay.duplicate(true)
	semantic_gameplay.erase("decoration_spawns")
	for gameplay_key in semantic_gameplay.keys():
		var collection_value = semantic_gameplay[gameplay_key]
		if str(gameplay_key) == "tutorial_route" or not collection_value is Array:
			continue
		var projected_collection := (collection_value as Array).duplicate(true)
		for index in range(projected_collection.size()):
			var record_value = projected_collection[index]
			if record_value is Dictionary:
				projected_collection[index] = _record_without_presentation_fields(
					record_value as Dictionary
				)
		semantic_gameplay[gameplay_key] = projected_collection
	return semantic_gameplay


func _record_without_presentation_fields(record: Dictionary) -> Dictionary:
	var semantic_record := record.duplicate(true)
	for raw_key in record.keys():
		var key := str(raw_key)
		if PRESENTATION_FIELD_KEYS.has(key) or key.begins_with("visual_"):
			semantic_record.erase(raw_key)
	return semantic_record


func _canonical_sha256(value) -> String:
	return _canonical_json(value).sha256_text().to_lower()


func _canonical_json(value) -> String:
	return JSON.stringify(_canonical_value(value), "", true, true)


func _canonical_value(value):
	match typeof(value):
		TYPE_DICTIONARY:
			var source := value as Dictionary
			var dictionary_result := {}
			for key in source.keys():
				dictionary_result[str(key)] = _canonical_value(source[key])
			return dictionary_result
		TYPE_ARRAY:
			var array_result := []
			for child_value in value as Array:
				array_result.append(_canonical_value(child_value))
			return array_result
		TYPE_FLOAT:
			var number := float(value)
			if is_finite(number) and number == floor(number):
				return int(number)
			return number
		_:
			return value


func _generated_visual_layer_errors(visual_layers: Node2D, expected_layers: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	var children := visual_layers.get_children()
	if children.size() != expected_layers.size():
		errors.append("Scena mapy ma nieaktualną liczbę korzeni VisualLayers.")
	var comparable_count := mini(children.size(), expected_layers.size())
	for index in range(comparable_count):
		var layer_value = expected_layers[index]
		if not layer_value is Dictionary:
			continue
		var layer := layer_value as Dictionary
		var node := children[index]
		var layer_id := str(layer.get("id", ""))
		if str(node.name) != layer_id:
			errors.append("Scena mapy ma nieaktualną kolejność VisualLayers przy %s." % layer_id)
		var expected_space := str(layer.get("space", ""))
		if expected_space == "parallax" and not node is Parallax2D:
			errors.append("Warstwa %s sceny powinna być Parallax2D." % layer_id)
		elif expected_space == "world_locked" and (not node is Node2D or node is Parallax2D):
			errors.append("Warstwa %s sceny powinna być world-locked Node2D." % layer_id)
		for metadata_key in ["role", "space", "enabled", "reserved", "affordance_policy", "geometry_role"]:
			if not node.has_meta(metadata_key) or node.get_meta(metadata_key) != layer.get(metadata_key, null):
				errors.append("Warstwa %s sceny ma nieaktualne metadata %s." % [layer_id, metadata_key])
		if not node.has_meta("layer_id") or str(node.get_meta("layer_id")) != layer_id:
			errors.append("Warstwa %s sceny ma nieaktualne metadata layer_id." % layer_id)
		var expected_scale := _json_vector(layer.get("parallax_scale", []))
		if not node.has_meta("parallax_scale") or node.get_meta("parallax_scale") != expected_scale:
			errors.append("Warstwa %s sceny ma nieaktualne metadata parallax_scale." % layer_id)
		if node is Node2D:
			if (node as Node2D).z_index != int(layer.get("z_index", 0)):
				errors.append("Warstwa %s sceny ma nieaktualny z_index." % layer_id)
			if (node as Node2D).visible != bool(layer.get("enabled", true)):
				errors.append("Warstwa %s sceny ma nieaktualną widoczność." % layer_id)
			var expected_modulate := _json_color(layer.get("rgb_modulate", "ffffff"))
			if (node as Node2D).modulate != expected_modulate:
				errors.append("Warstwa %s sceny ma nieaktualny rgb_modulate." % layer_id)
			if not node.has_meta("rgb_modulate") or node.get_meta("rgb_modulate") != expected_modulate:
				errors.append("Warstwa %s sceny ma nieaktualne metadata rgb_modulate." % layer_id)
		if node is Parallax2D and (node as Parallax2D).scroll_scale != expected_scale:
			errors.append("Warstwa %s sceny ma nieaktualny scroll_scale." % layer_id)
		if layer_id == RESERVED_VISUAL_LAYER_ID and node.get_child_count() != 0:
			errors.append("Zarezerwowana warstwa L10 sceny musi pozostać pusta.")
	return errors


func _generated_portal_backdrop_clearance_errors(
	visual_layers: Node2D,
	expected_visual: Dictionary,
) -> PackedStringArray:
	var errors := PackedStringArray()
	var host_layer := visual_layers.get_node_or_null(
		PORTAL_BACKDROP_CLEARANCE_HOST_LAYER_ID
	) as Node2D
	if host_layer == null:
		errors.append("Scena mapy nie zawiera hosta L04 dla clearance wejść.")
		return errors
	var clearance_root := host_layer.get_node_or_null(
		"PortalBackdropClearances"
	) as Node2D
	if clearance_root == null:
		errors.append("Scena mapy nie zawiera typowanego PortalBackdropClearances.")
		return errors
	if (
		clearance_root.position != Vector2.ZERO
		or clearance_root.rotation != 0.0
		or clearance_root.scale != Vector2.ONE
	):
		errors.append("PortalBackdropClearances musi zachować identity transform.")
	if clearance_root.z_as_relative:
		errors.append("PortalBackdropClearances musi używać absolutnego world-locked z-indexu.")

	var backdrop_z := -2_147_483_648
	var host_z := 2_147_483_647
	var found_backdrop_layers := 0
	var layers_value: Variant = expected_visual.get("layers", [])
	if layers_value is Array:
		for layer_value: Variant in layers_value as Array:
			if not layer_value is Dictionary:
				continue
			var layer := layer_value as Dictionary
			var layer_id := str(layer.get("id", ""))
			if layer_id in PORTAL_BACKDROP_CLEARANCE_OCCLUDED_LAYER_IDS:
				backdrop_z = maxi(backdrop_z, int(layer.get("z_index", backdrop_z)))
				found_backdrop_layers += 1
			elif layer_id == PORTAL_BACKDROP_CLEARANCE_HOST_LAYER_ID:
				host_z = int(layer.get("z_index", host_z))
	if (
		found_backdrop_layers != PORTAL_BACKDROP_CLEARANCE_OCCLUDED_LAYER_IDS.size()
		or host_z == 2_147_483_647
		or clearance_root.z_index <= backdrop_z
		or clearance_root.z_index >= host_z
	):
		errors.append("PortalBackdropClearances musi być nad L01/L02 i pod L04.")
	if str(clearance_root.get_meta("contract", "")) != PORTAL_BACKDROP_CLEARANCE_CONTRACT:
		errors.append("PortalBackdropClearances ma nieaktualny kontrakt geometrii.")
	if str(clearance_root.get_meta("role", "")) != "portal_backdrop_clearance":
		errors.append("PortalBackdropClearances ma nieaktualną rolę prezentacyjną.")
	if str(clearance_root.get_meta("space", "")) != "world_locked":
		errors.append("PortalBackdropClearances musi być world-locked.")
	if not bool(clearance_root.get_meta("visual_only", false)):
		errors.append("PortalBackdropClearances musi jawnie pozostawać visual-only.")
	if (
		clearance_root.get_meta("occluded_layer_ids", PackedStringArray())
		!= PackedStringArray(PORTAL_BACKDROP_CLEARANCE_OCCLUDED_LAYER_IDS)
	):
		errors.append("PortalBackdropClearances może zasłaniać wyłącznie L01/L02.")
	if (
		str(clearance_root.get_meta("host_layer_id", ""))
		!= PORTAL_BACKDROP_CLEARANCE_HOST_LAYER_ID
	):
		errors.append("PortalBackdropClearances musi publikować host L04.")
	if (
		int(clearance_root.get_meta("normal_core_cells", 0))
		!= PORTAL_BACKDROP_CLEARANCE_NORMAL_CORE_CELLS
		or int(clearance_root.get_meta("tangent_padding_cells", 0))
		!= PORTAL_BACKDROP_CLEARANCE_TANGENT_PADDING_CELLS
		or int(clearance_root.get_meta("feather_cells", 0))
		!= PORTAL_BACKDROP_CLEARANCE_FEATHER_CELLS
	):
		errors.append("PortalBackdropClearances ma nieaktualne ograniczenia paddingu/feather.")

	var geometry_records: Array = []
	var previous_digest := ""
	var expected_visual_children := PackedStringArray([
		"Core", "FeatherLeft", "FeatherRight", "FeatherTop", "FeatherBottom",
	])
	for child: Node in clearance_root.get_children():
		if not child is Node2D:
			errors.append("PortalBackdropClearances może zawierać wyłącznie Node2D.")
			continue
		var clearance := child as Node2D
		var geometry_digest := str(clearance.get_meta("geometry_digest", ""))
		if not _valid_sha256(geometry_digest, false):
			errors.append("Portal clearance wymaga poprawnego geometry_digest.")
		elif not previous_digest.is_empty() and geometry_digest <= previous_digest:
			errors.append("Portal clearances muszą mieć deterministyczną kolejność digestów.")
		previous_digest = geometry_digest
		if str(clearance.name) != "Clearance_%s" % geometry_digest:
			errors.append("Portal clearance musi używać nazwy wyłącznie z digestu geometrii.")
		var geometry_value: Variant = clearance.get_meta("source_geometry", null)
		if not geometry_value is Dictionary:
			errors.append("Portal clearance wymaga anonimowego source_geometry.")
			continue
		var geometry := geometry_value as Dictionary
		if not _dictionary_has_exact_keys(geometry, [
			"contract", "axis", "boundary_cell", "run_start_cell", "run_end_cell",
			"outward_cell", "cell_size",
		]):
			errors.append("Portal clearance source_geometry ma nieaktualny typowany schema.")
		if str(geometry.get("contract", "")) != PORTAL_BACKDROP_CLEARANCE_CONTRACT:
			errors.append("Portal clearance source_geometry ma nieaktualny kontrakt.")
		if _canonical_sha256(geometry) != geometry_digest:
			errors.append("Portal clearance geometry_digest nie odpowiada geometrii.")
		geometry_records.append(geometry.duplicate(true))
		var opening_center_value: Variant = clearance.get_meta("opening_center", null)
		var outward_value: Variant = clearance.get_meta("outward", null)
		if not opening_center_value is Vector2 or not (opening_center_value as Vector2).is_finite():
			errors.append("Portal clearance wymaga skończonego opening_center.")
		if (
			not outward_value is Vector2
			or (outward_value as Vector2) not in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
		):
			errors.append("Portal clearance wymaga osiowego kierunku outward.")
		if float(clearance.get_meta("span", 0.0)) <= 0.0:
			errors.append("Portal clearance wymaga dodatniego span.")
		var core_rect_value: Variant = clearance.get_meta("core_rect", null)
		var outer_rect_value: Variant = clearance.get_meta("outer_rect", null)
		if not core_rect_value is Rect2 or not outer_rect_value is Rect2:
			errors.append("Portal clearance wymaga core_rect i outer_rect.")
		else:
			var core_rect := core_rect_value as Rect2
			var outer_rect := outer_rect_value as Rect2
			if (
				core_rect.size.x <= 0.0
				or core_rect.size.y <= 0.0
				or outer_rect.size.x <= core_rect.size.x
				or outer_rect.size.y <= core_rect.size.y
				or outer_rect.position.x > core_rect.position.x
				or outer_rect.position.y > core_rect.position.y
				or outer_rect.end.x < core_rect.end.x
				or outer_rect.end.y < core_rect.end.y
			):
				errors.append("Portal clearance outer_rect musi być ograniczonym featherem core_rect.")
		if not bool(clearance.get_meta("visual_only", false)):
			errors.append("Każdy portal clearance musi jawnie pozostać visual-only.")
		var actual_visual_children := PackedStringArray()
		for visual_child: Node in clearance.get_children():
			actual_visual_children.append(str(visual_child.name))
			if not visual_child is Polygon2D:
				errors.append("Portal clearance może zawierać wyłącznie Polygon2D.")
			elif (visual_child as Polygon2D).polygon.size() != 4:
				errors.append("Portal clearance polygon musi być deterministycznym quadem.")
		if actual_visual_children != expected_visual_children:
			errors.append("Portal clearance ma nieaktualny zestaw Core/Feather.")
		var descendants: Array[Node] = [clearance]
		descendants.append_array(clearance.find_children("*", "", true, false))
		for descendant: Node in descendants:
			if (
				descendant is CollisionObject2D
				or descendant is CollisionShape2D
				or descendant is CollisionPolygon2D
			):
				errors.append("PortalBackdropClearances nie może zawierać fizyki ani Area2D.")
	if int(clearance_root.get_meta("clearance_count", -1)) != clearance_root.get_child_count():
		errors.append("PortalBackdropClearances ma nieaktualną liczbę pochodnych otworów.")
	var aggregate_digest := str(clearance_root.get_meta("geometry_digest", ""))
	if not _valid_sha256(aggregate_digest, false):
		errors.append("PortalBackdropClearances wymaga aggregate geometry_digest.")
	elif aggregate_digest != _canonical_sha256(geometry_records):
		errors.append("PortalBackdropClearances aggregate digest nie odpowiada dzieciom.")
	return errors


func _generated_structure_root_errors(
	structure_roots: Node2D,
	expected_structures: Dictionary,
	expected_visual: Dictionary,
) -> PackedStringArray:
	var errors := PackedStringArray()
	if (
		structure_roots.position != Vector2.ZERO
		or structure_roots.rotation != 0.0
		or structure_roots.scale != Vector2.ONE
	):
		errors.append("StructureRoots musi zachować identity transform.")
	var expected_instances_value = expected_structures.get("instances", null)
	if not expected_instances_value is Array:
		errors.append("Metadata structures nie zawiera tablicy instances.")
		return errors
	var expected_enabled_by_id: Dictionary = {}
	for instance_value in expected_instances_value as Array:
		if not instance_value is Dictionary:
			continue
		var instance := instance_value as Dictionary
		if bool(instance.get("enabled", false)):
			expected_enabled_by_id[str(instance.get("id", ""))] = instance
	var actual_by_id: Dictionary = {}
	for child in structure_roots.get_children():
		if not child is Node2D:
			errors.append("StructureRoots może zawierać wyłącznie korzenie Node2D struktur.")
			continue
		var structure_id := str(child.get_meta("structure_id", ""))
		if structure_id.is_empty() or actual_by_id.has(structure_id):
			errors.append("Korzenie struktur wymagają niepustych, unikalnych metadata structure_id.")
			continue
		actual_by_id[structure_id] = child
		if not expected_enabled_by_id.has(structure_id):
			errors.append("Scena mapy zawiera nieoczekiwany korzeń struktury %s." % structure_id)
			continue
		var expected: Dictionary = expected_enabled_by_id[structure_id]
		var root := child as Node2D
		if (
			root.position != _json_vector(expected.get("origin", []))
			or root.rotation != 0.0
			or root.scale != Vector2.ONE
		):
			errors.append("Struktura %s ma nieaktualny lokalny transform względem StructureRoots." % structure_id)
		for metadata_key in [
			"template_id", "topology_digest", "partition_digest",
		]:
			if root.get_meta(metadata_key, null) != expected.get(metadata_key, null):
				errors.append("Struktura %s ma nieaktualne metadata %s." % [structure_id, metadata_key])
		if expected.has("landmark_id"):
			if (
				not root.has_meta("landmark_id")
				or root.get_meta("landmark_id") != expected.get("landmark_id")
			):
				errors.append("Struktura %s ma nieaktualne metadata landmark_id." % structure_id)
		elif root.has_meta("landmark_id"):
			errors.append("Neutralna struktura %s nie może publikować metadata landmark_id." % structure_id)
		if root.get_meta("origin", Vector2(INF, INF)) != _json_vector(expected.get("origin", [])):
			errors.append("Struktura %s ma nieaktualne metadata origin." % structure_id)
		if root.get_meta("size", Vector2(INF, INF)) != _json_vector(expected.get("size", [])):
			errors.append("Struktura %s ma nieaktualne metadata size." % structure_id)
		var expected_runtime = expected.get("runtime", {})
		if _canonical_json(expected_runtime) != _canonical_json(root.get_meta("runtime", {})):
			errors.append("Struktura %s ma nieaktualne metadata runtime." % structure_id)
		for child_name in ["InteriorVisual", "StructureVisual", "DynamicBodies", "Interactives"]:
			var local_root := root.get_node_or_null(child_name) as Node2D
			if local_root == null:
				errors.append("Struktura %s nie zawiera lokalnego korzenia %s." % [structure_id, child_name])
			elif (
				local_root.position != Vector2.ZERO
				or local_root.rotation != 0.0
				or local_root.scale != Vector2.ONE
			):
				errors.append("Struktura %s/%s musi zachować lokalny identity transform." % [structure_id, child_name])
		var static_collision := root.get_node_or_null("StaticCollision") as StaticBody2D
		if static_collision == null:
			errors.append("Struktura %s nie zawiera lokalnego StaticCollision." % structure_id)
		else:
			if (
				static_collision.position != Vector2.ZERO
				or static_collision.rotation != 0.0
				or static_collision.scale != Vector2.ONE
			):
				errors.append("Struktura %s/StaticCollision musi zachować lokalny identity transform." % structure_id)
			var collision_shape := static_collision.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if collision_shape == null or not collision_shape.shape is ConcavePolygonShape2D:
				errors.append("Struktura %s wymaga ConcavePolygonShape2D w StaticCollision." % structure_id)
			elif (collision_shape.shape as ConcavePolygonShape2D).segments.is_empty():
				errors.append("Struktura %s ma pusty lokalny kolider statyczny." % structure_id)
		errors.append_array(_generated_structure_visual_asset_errors(
			root,
			structure_id,
			expected_visual,
		))
	for structure_id in expected_enabled_by_id.keys():
		if not actual_by_id.has(structure_id):
			errors.append("Scena mapy nie zawiera korzenia struktury %s." % structure_id)
	return errors




func _generated_structure_visual_asset_errors(
	root: Node2D,
	structure_id: String,
	expected_visual: Dictionary,
) -> PackedStringArray:
	var errors := PackedStringArray()
	for asset_value in expected_visual.get("assets", []):
		if not asset_value is Dictionary:
			continue
		var asset := asset_value as Dictionary
		var kind := str(asset.get("kind", ""))
		if (
			str(asset.get("structure_id", "")) != structure_id
			or kind not in STRUCTURE_VISUAL_ASSET_KINDS
		):
			continue
		var local_root_name := "InteriorVisual" if kind == "structure_interior_texture" else "StructureVisual"
		var local_root := root.get_node_or_null(local_root_name) as Node2D
		var group_node := _child_by_metadata(local_root, "group_id", str(asset.get("group_id", "")))
		var asset_node := _child_by_metadata(group_node, "asset_id", str(asset.get("id", "")))
		var local_rect := _json_rect(asset.get("local_rect", null))
		var pixel_size_value := _json_vector(asset.get("pixel_size", null))
		var pixel_size := Vector2i(int(pixel_size_value.x), int(pixel_size_value.y))
		if not asset_node is Node2D:
			errors.append("Struktura %s nie zawiera assetu %s." % [structure_id, str(asset.get("id", ""))])
			continue
		var asset_2d := asset_node as Node2D
		if (
			asset_2d.position != local_rect.position
			or asset_2d.scale != Vector2.ONE
			or asset_node.get_meta("local_rect", Rect2()) != local_rect
			or asset_node.get_meta("pixel_size", Vector2i.ZERO) != pixel_size
			or _canonical_json(asset_node.get_meta("source", {})) != _canonical_json(asset)
		):
			errors.append("Struktura %s ma nieaktualny asset %s." % [structure_id, str(asset.get("id", ""))])
		var bitmap := asset_node.get_node_or_null("Bitmap") as TextureRect
		if (
			bitmap == null
			or bitmap.scale != Vector2.ONE
			or bitmap.texture == null
			or bitmap.texture.get_size() != Vector2(pixel_size)
			or not bitmap.material is ShaderMaterial
		):
			errors.append("Struktura %s ma nieaktualną bitmapę assetu %s." % [structure_id, str(asset.get("id", ""))])
			continue
		var material := bitmap.material as ShaderMaterial
		var expected_mask_name := (
			"open_water_mask_native.png"
			if kind == "structure_interior_texture"
			else "solid_mask_native.png"
		)
		var expected_mask_path := (
			"res://underwater_map_workbench/structures/%s/generated/%s"
			% [structure_id, expected_mask_name]
		)
		var clip_mask := material.get_shader_parameter("clip_mask") as Texture2D
		var surface_detail_mask := material.get_shader_parameter("surface_detail_mask") as Texture2D
		var expected_surface_detail_path := (
			"res://underwater_map_workbench/structures/%s/generated/surface_detail_mask_local.png"
			% structure_id
		)
		var structure_size := root.get_meta("size", Vector2.ZERO) as Vector2
		var expected_surface_detail_size := Vector2(
			structure_size.x / L05_WORLD_UNITS_PER_PIXEL.x,
			structure_size.y / L05_WORLD_UNITS_PER_PIXEL.y,
		)
		var expected_detail_enabled := kind == "structure_owner_masked_texture"
		var expected_world_origin := (
			root.get_meta("origin", Vector2.ZERO) as Vector2
		) + local_rect.position
		if (
			material.shader == null
			or material.shader.resource_path != STRUCTURE_CLIP_SHADER_PATH
			or clip_mask == null
			or clip_mask.resource_path != expected_mask_path
			or surface_detail_mask == null
			or surface_detail_mask.resource_path != expected_surface_detail_path
			or surface_detail_mask.get_size() != expected_surface_detail_size
			or bool(material.get_shader_parameter("detail_enabled")) != expected_detail_enabled
			or material.get_shader_parameter("local_rect_origin") != local_rect.position
			or material.get_shader_parameter("local_rect_size") != local_rect.size
			or material.get_shader_parameter("structure_size") != structure_size
			or material.get_shader_parameter("world_rect_origin") != expected_world_origin
			or material.get_shader_parameter("world_size") != REQUIRED_WORLD_SIZE
		):
			errors.append("Struktura %s ma nieaktualne klipowanie assetu %s." % [structure_id, str(asset.get("id", ""))])
	return errors


func _dictionary_record_by_id(records: Array, record_id: String) -> Dictionary:
	for record_value in records:
		if record_value is Dictionary and str((record_value as Dictionary).get("id", "")) == record_id:
			return record_value as Dictionary
	return {}


func _child_by_metadata(parent: Node, metadata_key: String, expected_value) -> Node:
	if parent == null:
		return null
	for child in parent.get_children():
		if child.has_meta(metadata_key) and child.get_meta(metadata_key) == expected_value:
			return child
	return null


func _validate_visual(
	visual: Dictionary,
	world_size: Vector2,
	topology: Dictionary,
	structures: Dictionary,
	errors: PackedStringArray
) -> void:
	for color_key in ["water_color", "deep_water_color", "grid_color", "border_color", "station_color"]:
		if not _valid_json_color(visual.get(color_key, null)):
			errors.append("visual.%s musi być kolorem RGB/RGBA hex." % color_key)
	var water_color_value := str(visual.get("water_color", "")).strip_edges().trim_prefix("#")
	if _valid_json_color(visual.get("water_color", null)) and water_color_value.length() != 6:
		errors.append("visual.water_color musi być nieprzezroczystym kolorem RGB hex.")
	for width_key in ["grid_width", "border_width"]:
		var width_value = visual.get(width_key, null)
		if typeof(width_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(width_value)) or float(width_value) <= 0.0:
			errors.append("visual.%s musi być dodatnią liczbą." % width_key)
	if visual.has("diagnostic_grid_enabled"):
		if typeof(visual.get("diagnostic_grid_enabled")) != TYPE_BOOL:
			errors.append("visual.diagnostic_grid_enabled musi być wartością logiczną.")
	elif str(topology.get("mode", "")) == L05_TOPOLOGY_MODE:
		errors.append("L05 wymaga jawnego visual.diagnostic_grid_enabled.")
	var layers_value = visual.get("layers", null)
	if not layers_value is Array:
		errors.append("visual.layers musi być tablicą L00-L10.")
		return
	var layers := layers_value as Array
	if layers.size() != VISUAL_LAYER_IDS.size():
		errors.append("visual.layers musi zawierać dokładnie L00-L10.")
	var previous_z_index := -2_147_483_648
	var seen_layer_ids := {}
	var required_layer_keys := [
		"id", "role", "space", "z_index", "parallax_scale", "enabled", "reserved",
		"affordance_policy", "geometry_role", "rgb_modulate",
	]
	for index in range(layers.size()):
		var layer_value = layers[index]
		if not layer_value is Dictionary:
			errors.append("visual.layers[%d] musi być obiektem." % index)
			continue
		var layer := layer_value as Dictionary
		if not _dictionary_has_exact_keys(layer, required_layer_keys):
			errors.append("visual.layers[%d] musi zawierać wyłącznie pełny kontrakt warstwy." % index)
		var layer_id := str(layer.get("id", "")).strip_edges()
		if layer_id.is_empty() or seen_layer_ids.has(layer_id):
			errors.append("ID warstw wizualnych muszą być niepuste i unikalne.")
		seen_layer_ids[layer_id] = true
		if index >= VISUAL_LAYER_IDS.size() or layer_id != str(VISUAL_LAYER_IDS[index]):
			errors.append("visual.layers musi zachować dokładną kolejność L00-L10.")
		for string_key in ["role", "space", "affordance_policy", "geometry_role"]:
			var string_value = layer.get(string_key, null)
			if not string_value is String or str(string_value).strip_edges().is_empty():
				errors.append("Warstwa %s wymaga niepustego pola %s." % [layer_id, string_key])
		if typeof(layer.get("enabled", null)) != TYPE_BOOL or typeof(layer.get("reserved", null)) != TYPE_BOOL:
			errors.append("Warstwa %s wymaga logicznych enabled i reserved." % layer_id)
		var z_value = layer.get("z_index", null)
		if not _is_integral_number(z_value):
			errors.append("Warstwa %s wymaga całkowitego z_index." % layer_id)
		else:
			var z_index := int(z_value)
			if z_index <= previous_z_index:
				errors.append("z_index warstw musi być ściśle rosnący.")
			previous_z_index = z_index
		var parallax_scale := _json_vector(layer.get("parallax_scale", null))
		if not parallax_scale.is_finite() or parallax_scale.x <= 0.0 or parallax_scale.y <= 0.0:
			errors.append("Warstwa %s wymaga dodatniej parallax_scale." % layer_id)
		var rgb_modulate_value = layer.get("rgb_modulate", null)
		if (
			not _valid_json_color(rgb_modulate_value)
			or str(rgb_modulate_value).strip_edges().trim_prefix("#").length() != 6
		):
			errors.append(
				"Warstwa %s wymaga nieprzezroczystego rgb_modulate."
				% layer_id
			)
		var expected_space := str(VISUAL_LAYER_SPACES.get(layer_id, ""))
		if str(layer.get("space", "")) != expected_space:
			errors.append("Warstwa %s musi używać space=%s." % [layer_id, expected_space])
		if expected_space == "world_locked" and not parallax_scale.is_equal_approx(Vector2.ONE):
			errors.append("Warstwa world-locked %s musi mieć parallax_scale=[1,1]." % layer_id)
		if layer_id in PARALLAX_LAYER_IDS and parallax_scale.is_equal_approx(Vector2.ONE):
			errors.append("Warstwa parallax %s musi mieć skalę różną od [1,1]." % layer_id)
		if (
			layer_id in GROUND_ANCHORED_BACKDROP_LAYER_IDS
			and parallax_scale.y != 1.0
		):
			errors.append(
				"Warstwa %s zakotwiczonego tła musi mieć dokładnie parallax_scale.y=1.0."
				% layer_id
			)
		if layer_id == "L00":
			if str(layer.get("role", "")) != "water_base":
				errors.append("L00 musi mieć role=water_base.")
			if str(layer.get("geometry_role", "")) != "none":
				errors.append("L00 nie może posiadać geometrii.")
			if str(layer.get("affordance_policy", "")) != NO_BLOCKING_AFFORDANCE_POLICY:
				errors.append("L00 musi zachować politykę chronionej wody.")
			if not bool(layer.get("enabled", false)) or bool(layer.get("reserved", true)):
				errors.append("L00 musi być włączone i niezarezerwowane.")
			if str(rgb_modulate_value).strip_edges().trim_prefix("#").to_lower() != "ffffff":
				errors.append("L00.rgb_modulate musi pozostać ffffff; jedynym kolorem jest water_color.")
		elif layer_id == COLLIDER_AUTHORITY_LAYER_ID:
			if str(layer.get("role", "")) != "collider_authority":
				errors.append("L05 musi mieć role=collider_authority.")
			if str(layer.get("geometry_role", "")) != "collider_authority":
				errors.append("L05 musi być jedynym geometry_role=collider_authority.")
			if str(layer.get("affordance_policy", "")) != "collider_authority":
				errors.append("L05 musi używać affordance_policy=collider_authority.")
			if not bool(layer.get("enabled", false)) or bool(layer.get("reserved", true)):
				errors.append("L05 musi być włączone i niezarezerwowane.")
		elif layer_id in NONBLOCKING_TEXTURE_LAYER_IDS:
			if str(layer.get("affordance_policy", "")) != OPEN_WATER_BACKDROP_AFFORDANCE_POLICY:
				errors.append("Warstwa %s musi używać polityki otwartego tła." % layer_id)
		elif layer_id == RESERVED_VISUAL_LAYER_ID:
			if bool(layer.get("enabled", true)) or not bool(layer.get("reserved", false)):
				errors.append("L10 musi być wyłączone i zarezerwowane.")
			if str(layer.get("geometry_role", "")) != "none":
				errors.append("L10 nie może posiadać geometrii.")
			if str(layer.get("affordance_policy", "")) != NO_BLOCKING_AFFORDANCE_POLICY:
				errors.append("L10 musi zachować politykę chronionej wody.")
		else:
			if not bool(layer.get("enabled", false)) or bool(layer.get("reserved", true)):
				errors.append("Warstwa %s musi być włączona i niezarezerwowana." % layer_id)
			if str(layer.get("geometry_role", "")) != "none":
				errors.append("Tylko L05 może posiadać geometrię kolizji.")
			if str(layer.get("affordance_policy", "")) != NO_BLOCKING_AFFORDANCE_POLICY:
				errors.append("Warstwa %s musi zachować politykę chronionej wody." % layer_id)

	var assets := _dictionary_array(visual.get("assets", null), "visual.assets", errors)
	var asset_ids := {}
	var structure_instances_by_id := _structure_instances_by_id(structures)
	var collision: Dictionary = topology.get("collision_source", {})
	var expected_topology_digest := str(collision.get("canonical_digest", ""))
	var expected_partition_digest := str(collision.get("partition_digest", ""))
	for index in range(assets.size()):
		var asset := assets[index]
		var label := "visual.assets[%d]" % index
		var kind := str(asset.get("kind", "")).strip_edges()
		var is_structure_asset := kind in STRUCTURE_VISUAL_ASSET_KINDS
		var expected_asset_keys: Array = (
			STRUCTURE_VISUAL_ASSET_KEYS if is_structure_asset else VISUAL_ASSET_KEYS
		)
		if not _dictionary_has_exact_keys(asset, expected_asset_keys):
			errors.append("%s musi zawierać wyłącznie pełny kontrakt typowanego assetu." % label)
		var asset_id_value = asset.get("id", null)
		var asset_id := str(asset_id_value).strip_edges()
		if not asset_id_value is String or asset_id.is_empty() or asset_ids.has(asset_id):
			errors.append("visual.assets wymaga niepustych, unikalnych ID.")
		else:
			asset_ids[asset_id] = true
		var layer_id_value = asset.get("layer_id", null)
		var layer_id := str(layer_id_value).strip_edges()
		var group_id_value = asset.get("group_id", null)
		var group_id := str(group_id_value).strip_edges()
		if (
			not group_id_value is String
			or not _valid_visual_group_id(group_id)
		):
			errors.append("Asset %s wymaga bezpiecznego, niepustego group_id." % asset_id)
		var kind_value = asset.get("kind", null)
		if (
			not layer_id_value is String
			or not kind_value is String
			or not [
				["L01", "texture_rect"],
				["L01", "composition_proxy"],
				["L02", "texture_rect"],
				["L02", "composition_proxy"],
				["L05", "collision_masked_material"],
				["L04", "structure_interior_texture"],
				["L05", "structure_owner_masked_texture"],
			].has(
				[layer_id, kind]
			)
		):
			errors.append(
				"Asset %s ma nieobsługiwaną parę layer_id/kind."
				% asset_id
			)
		if typeof(asset.get("enabled", null)) != TYPE_BOOL:
			errors.append("Asset %s ma niepoprawne enabled." % asset_id)
		var affordance_value = asset.get("affordance", null)
		if not affordance_value is String or str(affordance_value).strip_edges().is_empty():
			errors.append("Asset %s wymaga niepustego affordance." % asset_id)
		if kind == "composition_proxy":
			_validate_composition_proxy_asset(asset, label, errors)
		else:
			_validate_hashed_png_asset(asset, label, errors, is_structure_asset)
		if is_structure_asset:
			var structure_id_value = asset.get("structure_id", null)
			var structure_id := str(structure_id_value).strip_edges()
			if (
				not structure_id_value is String
				or not structure_instances_by_id.has(structure_id)
			):
				errors.append("Asset %s wskazuje nieznaną strukturę %s." % [asset_id, structure_id])
			else:
				var structure: Dictionary = structure_instances_by_id[structure_id]
				if not bool(structure.get("enabled", false)):
					errors.append("Asset %s nie może wskazywać wyłączonej struktury." % asset_id)
				var local_rect := _json_rect(asset.get("local_rect", null))
				var structure_size := _json_vector(structure.get("size", null))
				if not _rect_inside_local(local_rect, structure_size):
					errors.append("Asset %s ma local_rect poza strukturą %s." % [asset_id, structure_id])
				elif (
					not _vector_is_aligned(local_rect.position, L05_WORLD_UNITS_PER_PIXEL)
					or not _vector_is_aligned(local_rect.size, L05_WORLD_UNITS_PER_PIXEL)
				):
					errors.append("Asset %s local_rect musi być wyrównany do rastra L05 40 x 40." % asset_id)
				var pixel_size := _json_vector(asset.get("pixel_size", null))
				if pixel_size.x > 0.0 and pixel_size.y > 0.0 and pixel_size != local_rect.size:
					errors.append(
						"Asset %s musi zachować pixel_size równy local_rect 1:1 bez skalowania."
						% asset_id
					)
			if str(asset.get("topology_digest", "")) != expected_topology_digest:
				errors.append("Asset %s musi wskazywać canonical_digest aktywnej topologii." % asset_id)
			if str(asset.get("partition_digest", "")) != expected_partition_digest:
				errors.append("Asset %s musi wskazywać aktywny partition_digest." % asset_id)
			continue
		var world_rect := _json_rect(asset.get("world_rect", null))
		if not _rect_inside_world(world_rect, world_size):
			errors.append("Asset %s ma world_rect poza mapą." % asset_id)
		var topology_digest_value = asset.get("topology_digest", null)
		if not topology_digest_value is String:
			errors.append("Asset %s wymaga tekstowego topology_digest." % asset_id)
		elif layer_id in NONBLOCKING_TEXTURE_LAYER_IDS:
			if str(topology_digest_value) != "":
				errors.append("Asset %s %s musi mieć puste topology_digest." % [layer_id, asset_id])
			if str(affordance_value) != NONBLOCKING_BACKDROP_AFFORDANCE:
				errors.append(
					"Asset %s %s musi mieć affordance=%s."
					% [layer_id, asset_id, NONBLOCKING_BACKDROP_AFFORDANCE]
				)
			var pixel_size := _json_vector(asset.get("pixel_size", null))
			if pixel_size.x > 0.0 and pixel_size.y > 0.0 and pixel_size != world_rect.size:
				errors.append(
					"Asset %s %s musi zachować pixel_size równy world_rect 1:1 bez skalowania."
					% [layer_id, asset_id]
				)
		elif layer_id == "L05":
			if str(topology.get("mode", "")) != L05_TOPOLOGY_MODE:
				errors.append("Asset L05 %s wymaga topology.mode=%s." % [asset_id, L05_TOPOLOGY_MODE])
			if str(topology_digest_value) != expected_topology_digest:
				errors.append("Asset L05 %s musi wskazywać canonical_digest kolidera." % asset_id)
			if world_rect != Rect2(Vector2.ZERO, world_size):
				errors.append("Asset L05 %s musi pokrywać cały świat." % asset_id)
			if not ResourceLoader.exists(L05_SHADER_PATH):
				errors.append("Brak shadera maskującego grafikę L05.")


func _validate_structures(
	structures: Dictionary,
	landmark_ids: Dictionary,
	world_size: Vector2,
	topology: Dictionary,
	seen_ids: Dictionary,
	errors: PackedStringArray
) -> void:
	if not _dictionary_has_exact_keys(structures, ["templates", "instances"]):
		errors.append("structures musi zawierać wyłącznie templates i instances.")
	var templates := _dictionary_array(structures.get("templates", null), "structures.templates", errors)
	var instances := _dictionary_array(structures.get("instances", null), "structures.instances", errors)
	var template_ids: Dictionary = {}
	for index in range(templates.size()):
		var template: Dictionary = templates[index]
		var label := "structures.templates[%d]" % index
		if not _dictionary_has_exact_keys(template, [
			"id", "kind", "interior_layer_id", "collider_layer_id", "allowed_socket_kinds",
		]):
			errors.append("%s ma niepoprawny zestaw pól." % label)
		var template_id_value = template.get("id", null)
		var template_id := str(template_id_value).strip_edges()
		if (
			not template_id_value is String
			or template_id.is_empty()
			or template_ids.has(template_id)
		):
			errors.append("Szablony struktur wymagają niepustych, unikalnych ID.")
		else:
			template_ids[template_id] = template
		var template_kind_value = template.get("kind", null)
		var template_kind := str(template_kind_value).strip_edges()
		if not template_kind_value is String or not _valid_lower_snake_case_id(template_kind):
			errors.append("%s.kind musi być lowercase snake_case." % label)
		if str(template.get("interior_layer_id", "")) != "L04":
			errors.append("%s.interior_layer_id musi wskazywać world-locked L04." % label)
		if str(template.get("collider_layer_id", "")) != COLLIDER_AUTHORITY_LAYER_ID:
			errors.append("%s.collider_layer_id musi wskazywać authority L05." % label)
		var allowed_socket_kinds_value = template.get("allowed_socket_kinds", null)
		if not allowed_socket_kinds_value is Array:
			errors.append("%s.allowed_socket_kinds musi być tablicą." % label)
		else:
			var allowed_socket_kinds := allowed_socket_kinds_value as Array
			var seen_socket_kinds: Dictionary = {}
			if allowed_socket_kinds.is_empty():
				errors.append("%s.allowed_socket_kinds nie może być puste." % label)
			for socket_kind_index in range(allowed_socket_kinds.size()):
				var socket_kind_value = allowed_socket_kinds[socket_kind_index]
				var socket_kind := str(socket_kind_value).strip_edges()
				if (
					not socket_kind_value is String
					or not _valid_lower_snake_case_id(socket_kind)
					or seen_socket_kinds.has(socket_kind)
				):
					errors.append(
						"%s.allowed_socket_kinds[%d] musi być unikalnym lowercase snake_case."
						% [label, socket_kind_index]
					)
				else:
					seen_socket_kinds[socket_kind] = true
	var collision: Dictionary = topology.get("collision_source", {})
	var expected_topology_digest := str(collision.get("canonical_digest", ""))
	var expected_partition_digest := str(collision.get("partition_digest", ""))
	for index in range(instances.size()):
		var instance: Dictionary = instances[index]
		var label := "structures.instances[%d]" % index
		if not _dictionary_has_required_and_optional_keys(
			instance,
			[
				"id", "template_id", "origin", "size", "enabled",
				"topology_digest", "partition_digest", "sockets",
			],
			[
				"landmark_id", "runtime", "controller_script", "package_path",
				"package_sha256", "local_topology_digest", "collision_operations",
				"structure_scene_path",
			],
		):
			errors.append("%s ma niepoprawny zestaw pól." % label)
		var instance_id_value = instance.get("id", null)
		var instance_id := str(instance_id_value).strip_edges()
		if not instance_id_value is String:
			errors.append("%s.id musi być Stringiem." % label)
		_register_unique_id(instance_id, "struktury", seen_ids, errors)
		if template_ids.has(instance_id):
			errors.append("ID struktury %s koliduje z ID szablonu." % instance_id)
		var template_id_value = instance.get("template_id", null)
		var template_id := str(template_id_value).strip_edges()
		if not template_id_value is String or not template_ids.has(template_id):
			errors.append("Struktura %s wskazuje nieznany template_id %s." % [instance_id, template_id])
		if instance.has("landmark_id"):
			var landmark_id_value = instance.get("landmark_id", null)
			var landmark_id := str(landmark_id_value).strip_edges()
			if (
				not landmark_id_value is String
				or landmark_id.is_empty()
				or not landmark_ids.has(landmark_id)
			):
				errors.append("Struktura %s wskazuje nieznany landmark_id %s." % [instance_id, landmark_id])
		var origin := _json_vector(instance.get("origin", null))
		var size := _json_vector(instance.get("size", null))
		if not _rect_inside_world(Rect2(origin, size), world_size):
			errors.append("Struktura %s ma niepoprawny prostokąt origin/size." % instance_id)
		elif (
			not _vector_is_aligned(origin, L05_WORLD_UNITS_PER_PIXEL)
			or not _vector_is_aligned(size, L05_WORLD_UNITS_PER_PIXEL)
		):
			errors.append("Struktura %s musi być wyrównana do rastra L05 40 x 40." % instance_id)
		if typeof(instance.get("enabled", null)) != TYPE_BOOL:
			errors.append("Struktura %s wymaga logicznego enabled." % instance_id)
		var has_package_metadata := instance.has("package_path")
		for package_field in [
			"controller_script", "package_sha256", "local_topology_digest",
			"collision_operations", "structure_scene_path",
		]:
			if instance.has(package_field) != has_package_metadata:
				errors.append(
					"Struktura %s musi publikować kompletny zestaw rozwiązanych pól pakietu."
					% instance_id
				)
				break
		if has_package_metadata:
			var expected_package_path := "structures/%s/structure_manifest.json" % instance_id
			if str(instance.get("package_path", "")) != expected_package_path:
				errors.append("Struktura %s ma niepoprawne package_path." % instance_id)
			if not _valid_sha256(str(instance.get("package_sha256", "")), false):
				errors.append("Struktura %s ma niepoprawne package_sha256." % instance_id)
			if not _valid_structure_topology_digest(str(instance.get("local_topology_digest", ""))):
				errors.append("Struktura %s ma niepoprawne local_topology_digest." % instance_id)
			if not instance.get("collision_operations", null) is Array:
				errors.append("Struktura %s wymaga collision_operations z pakietu." % instance_id)
			var expected_scene_path := (
				"res://underwater_map_workbench/structures/%s/generated/structure.tscn"
				% instance_id
			)
			if str(instance.get("structure_scene_path", "")) != expected_scene_path:
				errors.append("Struktura %s ma niepoprawne structure_scene_path." % instance_id)
			var controller_script := str(instance.get("controller_script", ""))
			if (
				controller_script.is_empty()
				or not controller_script.begins_with(
					"res://underwater_map_workbench/structures/%s/" % instance_id
				)
			):
				errors.append("Struktura %s ma niepoprawny controller_script." % instance_id)
		var topology_digest_value = instance.get("topology_digest", null)
		if (
			not topology_digest_value is String
			or not _valid_topology_digest(str(topology_digest_value))
			or str(topology_digest_value) != expected_topology_digest
		):
			errors.append("Struktura %s musi wskazywać canonical_digest aktywnej topologii." % instance_id)
		var partition_digest_value = instance.get("partition_digest", null)
		if (
			not partition_digest_value is String
			or not _valid_partition_digest(str(partition_digest_value))
			or str(partition_digest_value) != expected_partition_digest
		):
			errors.append("Struktura %s musi wskazywać aktywny partition_digest." % instance_id)
		var sockets_value = instance.get("sockets", null)
		if not sockets_value is Array:
			errors.append("Struktura %s wymaga tablicy sockets." % instance_id)
		else:
			var socket_ids: Dictionary = {}
			var template: Dictionary = template_ids.get(template_id, {})
			var allowed_socket_kinds: Array = template.get("allowed_socket_kinds", [])
			for socket_index in range((sockets_value as Array).size()):
				var socket_value = (sockets_value as Array)[socket_index]
				var socket_label := "%s.sockets[%d]" % [label, socket_index]
				if not socket_value is Dictionary:
					errors.append("%s musi być obiektem." % socket_label)
					continue
				var socket := socket_value as Dictionary
				if not _dictionary_has_exact_keys(socket, ["id", "kind", "local_rect"]):
					errors.append("%s musi zawierać wyłącznie id, kind i local_rect." % socket_label)
				var socket_id_value = socket.get("id", null)
				var socket_id := str(socket_id_value).strip_edges()
				if (
					not socket_id_value is String
					or socket_id.is_empty()
					or socket_ids.has(socket_id)
				):
					errors.append("%s wymaga niepustego, unikalnego lokalnie ID." % socket_label)
				else:
					socket_ids[socket_id] = true
				var socket_kind_value = socket.get("kind", null)
				var socket_kind := str(socket_kind_value).strip_edges()
				if not socket_kind_value is String or socket_kind not in allowed_socket_kinds:
					errors.append("%s.kind nie jest dozwolony przez szablon." % socket_label)
				var local_rect := _json_rect(socket.get("local_rect", null))
				if not _rect_inside_local(local_rect, size):
					errors.append("%s.local_rect wykracza poza strukturę." % socket_label)
				elif (
					not _vector_is_aligned(local_rect.position, L05_WORLD_UNITS_PER_PIXEL)
					or not _vector_is_aligned(local_rect.size, L05_WORLD_UNITS_PER_PIXEL)
				):
					errors.append(
						"%s.local_rect musi być wyrównany do rastra L05 40 x 40."
						% socket_label
					)
		if instance.has("runtime"):
			var runtime_value = instance.get("runtime", null)
			if not runtime_value is Dictionary:
				errors.append("%s.runtime musi być obiektem." % label)




func _validate_topology(
	topology: Dictionary,
	structures: Dictionary,
	world_size: Vector2,
	navigation_cell_size: Vector2,
	errors: PackedStringArray
) -> void:
	if not _dictionary_has_exact_keys(
		topology,
		["mode", "authority_layer", "collision_source", "protected_corridors"]
	):
		errors.append("topology musi zawierać wyłącznie pełny kontrakt authority L05.")
	var mode_value = topology.get("mode", null)
	var mode := str(mode_value).strip_edges()
	if not mode_value is String or mode.is_empty():
		errors.append("topology.mode musi być niepustym Stringiem.")
	elif mode not in ["open_world", L05_TOPOLOGY_MODE]:
		errors.append("Runtime obsługuje wyłącznie open_world albo %s." % L05_TOPOLOGY_MODE)
	if str(topology.get("authority_layer", "")) != COLLIDER_AUTHORITY_LAYER_ID:
		errors.append("topology.authority_layer musi wskazywać L05.")
	var collision_value = topology.get("collision_source", null)
	if not collision_value is Dictionary:
		errors.append("topology.collision_source musi być obiektem.")
		return
	var collision := collision_value as Dictionary
	var collision_keys := ["format", "path", "sha256", "pixel_size", "world_units_per_pixel", "encoding"]
	if mode == L05_TOPOLOGY_MODE:
		collision_keys.append_array(["canonical_digest", "partition_digest", "mapping"])
	if not _dictionary_has_exact_keys(collision, collision_keys):
		errors.append("topology.collision_source ma niepoprawny zestaw pól dla trybu %s." % mode)
	var source_format_value = collision.get("format", null)
	var source_format := str(source_format_value).strip_edges()
	if not source_format_value is String or source_format.is_empty():
		errors.append("topology.collision_source.format musi być niepustym Stringiem.")
	var path_value = collision.get("path", null)
	var sha_value = collision.get("sha256", null)
	if not path_value is String:
		errors.append("topology.collision_source.path musi być Stringiem.")
	if not sha_value is String:
		errors.append("topology.collision_source.sha256 musi być Stringiem.")
	var pixel_size := _json_vector(collision.get("pixel_size", null))
	var world_units_per_pixel := _json_vector(collision.get("world_units_per_pixel", null))
	var encoding_value = collision.get("encoding", null)
	if not encoding_value is Dictionary:
		errors.append("topology.collision_source.encoding musi być obiektem.")
	else:
		var encoding := encoding_value as Dictionary
		var solid_value = encoding.get("solid", null)
		var open_water_value = encoding.get("open_water", null)
		if (
			not _is_integral_number(solid_value)
			or not _is_integral_number(open_water_value)
			or int(solid_value) < 0
			or int(solid_value) > 255
			or int(open_water_value) < 0
			or int(open_water_value) > 255
			or int(solid_value) == int(open_water_value)
		):
			errors.append("collision_source.encoding wymaga różnych wartości 8-bitowych.")
		elif int(solid_value) != 0 or int(open_water_value) != 255:
			errors.append("Kolizja wymaga encoding solid=0 i open_water=255.")
	if mode == "open_world":
		if source_format != "none":
			errors.append("open_world wymaga collision_source.format=none.")
		if str(path_value) != "" or str(sha_value) != "":
			errors.append("collision_source none wymaga pustych path i sha256.")
		if pixel_size != Vector2.ZERO or world_units_per_pixel != Vector2.ZERO:
			errors.append("collision_source none wymaga zerowych rozmiarów.")
	elif mode == L05_TOPOLOGY_MODE:
		if source_format != L05_SOURCE_FORMAT:
			errors.append("%s wymaga collision_source.format=%s." % [L05_TOPOLOGY_MODE, L05_SOURCE_FORMAT])
		if pixel_size != Vector2(L05_PIXEL_SIZE):
			errors.append("%s wymaga pixel_size 576 x 324." % L05_SOURCE_FORMAT)
		if world_units_per_pixel != L05_WORLD_UNITS_PER_PIXEL:
			errors.append("%s wymaga world_units_per_pixel 40 x 40." % L05_SOURCE_FORMAT)
		if navigation_cell_size != L05_WORLD_UNITS_PER_PIXEL:
			errors.append("map.navigation_cell_size musi odpowiadać mapowaniu L05 40 x 40.")
		if Vector2(pixel_size.x * world_units_per_pixel.x, pixel_size.y * world_units_per_pixel.y) != world_size:
			errors.append("Mapowanie pikseli L05 musi dokładnie pokrywać cały świat.")
		_decode_l05_collision_source(topology, structures, errors)

	var corridors := _dictionary_array(
		topology.get("protected_corridors", null),
		"topology.protected_corridors",
		errors
	)
	var corridor_ids := {}
	for corridor in corridors:
		var corridor_id_value = corridor.get("id", null)
		var corridor_id := str(corridor_id_value).strip_edges()
		if not corridor_id_value is String or corridor_id.is_empty() or corridor_ids.has(corridor_id):
			errors.append("protected_corridors wymaga niepustych, unikalnych ID.")
		else:
			corridor_ids[corridor_id] = true
		var points_value = corridor.get("points", null)
		if not points_value is Array or (points_value as Array).size() < 2:
			errors.append("Korytarz %s wymaga co najmniej dwóch punktów." % corridor_id)
		else:
			for point_value in points_value as Array:
				if not _point_inside_world(_json_vector(point_value), world_size):
					errors.append("Korytarz %s ma punkt poza mapą." % corridor_id)
		var clearance_value = corridor.get("clearance", null)
		if typeof(clearance_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(clearance_value)) or float(clearance_value) <= 0.0:
			errors.append("Korytarz %s wymaga dodatniego clearance." % corridor_id)


func _validate_campaign(
	campaign: Dictionary,
	landmark_ids: Dictionary,
	fixed_device_spawns: Array,
	errors: PackedStringArray
) -> void:
	var contract_id_value = campaign.get("contract_id", null)
	if not contract_id_value is String or str(contract_id_value) != CAMPAIGN_CONTRACT_ID:
		errors.append("campaign.contract_id musi mieć wartość %s." % CAMPAIGN_CONTRACT_ID)
	var stages_value = campaign.get("stages", null)
	if not stages_value is Array:
		errors.append("campaign.stages musi być tablicą etapów Wspólnej Linii.")
		return
	var stages := stages_value as Array
	if stages.size() != CAMPAIGN_STAGE_CONTRACTS.size():
		errors.append("campaign.stages musi zawierać dokładnie etapy j7, archive, r3 i c4.")

	var devices_by_id := {}
	for device_value in fixed_device_spawns:
		if not device_value is Dictionary:
			continue
		var device := device_value as Dictionary
		var device_id := str(device.get("id", "")).strip_edges()
		if not device_id.is_empty():
			devices_by_id[device_id] = device
	for registered_device_id in devices_by_id.keys():
		var registered_device: Dictionary = devices_by_id[registered_device_id]
		var prerequisites_value = registered_device.get("prerequisite_device_ids", null)
		if not prerequisites_value is Array:
			errors.append(
				"Urządzenie %s wymaga tablicy prerequisite_device_ids."
				% registered_device_id
			)
			continue
		for prerequisite_value in prerequisites_value as Array:
			var prerequisite_id := str(prerequisite_value).strip_edges()
			if (
				not prerequisite_value is String
				or prerequisite_id.is_empty()
				or prerequisite_id == str(registered_device_id)
				or not devices_by_id.has(prerequisite_id)
			):
				errors.append(
					"Urządzenie %s ma niepoprawną referencję prerequisite_device_ids."
					% registered_device_id
				)

	var comparable_count := mini(stages.size(), CAMPAIGN_STAGE_CONTRACTS.size())
	for index in range(comparable_count):
		var stage_value = stages[index]
		if not stage_value is Dictionary:
			errors.append("campaign.stages[%d] musi być obiektem." % index)
			continue
		var stage := stage_value as Dictionary
		var expected_stage: Dictionary = CAMPAIGN_STAGE_CONTRACTS[index]
		for required_key in ["id", "landmark_id", "fixed_device_ids"]:
			if not stage.has(required_key):
				errors.append("campaign.stages[%d] nie zawiera pola %s." % [index, required_key])
		var stage_id := str(stage.get("id", ""))
		var stage_landmark_id := str(stage.get("landmark_id", ""))
		if stage_id != str(expected_stage["id"]):
			errors.append("campaign.stages musi zachować kolejność j7 -> archive -> r3 -> c4.")
		if stage_landmark_id.is_empty() or not landmark_ids.has(stage_landmark_id):
			errors.append("Etap %s wskazuje niepoprawny landmark %s." % [stage_id, stage_landmark_id])
		var stage_device_ids_value = stage.get("fixed_device_ids", null)
		if not stage_device_ids_value is Array:
			errors.append("Etap %s wymaga tablicy fixed_device_ids." % stage_id)
			continue
		var stage_device_ids := stage_device_ids_value as Array
		var expected_device_ids: Array = expected_stage["fixed_device_ids"]
		if not _string_array_equals(stage_device_ids, expected_device_ids):
			errors.append("Etap %s ma niepoprawną kolejność fixed_device_ids." % stage_id)
		for device_id_value in stage_device_ids:
			var device_id := str(device_id_value)
			if not device_id_value is String or not devices_by_id.has(device_id):
				errors.append("Etap %s wskazuje brakujące urządzenie %s." % [stage_id, device_id])
				continue
			var device: Dictionary = devices_by_id[device_id]
			if str(device.get("landmark_id", "")) != stage_landmark_id:
				errors.append("Urządzenie %s nie należy do landmarku etapu %s." % [device_id, stage_id])

	for required_device_id in CAMPAIGN_DEVICE_PREREQUISITES.keys():
		if not devices_by_id.has(required_device_id):
			errors.append("Kampania wymaga urządzenia %s." % required_device_id)
			continue
		var required_device: Dictionary = devices_by_id[required_device_id]
		var required_prerequisites_value = required_device.get("prerequisite_device_ids", null)
		var expected_prerequisites: Array = CAMPAIGN_DEVICE_PREREQUISITES[required_device_id]
		if (
			not required_prerequisites_value is Array
			or not _string_array_equals(
				required_prerequisites_value as Array,
				expected_prerequisites
			)
		):
			errors.append(
				"Urządzenie %s narusza pojedynczy łańcuch prerequisite_device_ids."
				% required_device_id
			)


func _string_array_equals(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if not left[index] is String or str(left[index]) != str(right[index]):
			return false
	return true


func _validate_tutorial_roles(
	gameplay: Dictionary,
	records_by_collection: Dictionary,
	landmarks_by_id: Dictionary,
	entry_landmark_id: String,
	canonical_entry_landmark_id: String,
	errors: PackedStringArray
) -> void:
	var tutorial_landmark: Dictionary = landmarks_by_id.get(canonical_entry_landmark_id, {})
	if tutorial_landmark.is_empty() or str(tutorial_landmark.get("role", "")) != "dive_station":
		errors.append("tutorial_enabled wymaga wejściowego landmarku z rolą dive_station.")
	var market := _record_by_id(records_by_collection.get("loot_spawns", []), TUTORIAL_MARKET_CRATE_ID)
	var workshop := _record_by_id(records_by_collection.get("loot_spawns", []), TUTORIAL_WORKSHOP_CASE_ID)
	var shortcut := _record_by_id(records_by_collection.get("shortcut_spawns", []), TUTORIAL_SHORTCUT_ID)
	var junction := _record_by_id(records_by_collection.get("fixed_device_spawns", []), TUTORIAL_DEVICE_ID)
	for required_record in [
		[TUTORIAL_MARKET_CRATE_ID, market],
		[TUTORIAL_WORKSHOP_CASE_ID, workshop],
		[TUTORIAL_SHORTCUT_ID, shortcut],
		[TUTORIAL_DEVICE_ID, junction],
	]:
		if (required_record[1] as Dictionary).is_empty():
			errors.append("tutorial_enabled wymaga ID %s we właściwej kolekcji." % required_record[0])
	if not market.is_empty() and int(market.get("mandatory_order", -1)) != 0:
		errors.append("tutorial_market_crate musi zachować mandatory_order=0.")
	if not workshop.is_empty() and int(workshop.get("mandatory_order", -1)) != 1:
		errors.append("tutorial_workshop_case musi zachować mandatory_order=1.")
	if not market.is_empty():
		var market_contents_value = market.get("contents", null)
		if not market_contents_value is Dictionary or int((market_contents_value as Dictionary).get("food", 0)) < 6:
			errors.append("tutorial_market_crate musi zawierać co najmniej 6 food.")
	if not workshop.is_empty():
		var workshop_contents_value = workshop.get("contents", null)
		if not workshop_contents_value is Dictionary:
			errors.append("tutorial_workshop_case wymaga zawartości tutoriala.")
		else:
			var workshop_contents := workshop_contents_value as Dictionary
			for minimum_record in [["fabric_rubber", 2], ["planks", 4], ["scrap", 3]]:
				if int(workshop_contents.get(minimum_record[0], 0)) < int(minimum_record[1]):
					errors.append("tutorial_workshop_case ma za mało %s." % minimum_record[0])
	if not shortcut.is_empty():
		if str(shortcut.get("required_tool", "")) != "knife":
			errors.append("SC-01 musi wymagać knife.")
		if str(shortcut.get("interaction_action", "")) != "cut":
			errors.append("SC-01 musi używać akcji cut.")
	if not junction.is_empty():
		if int(junction.get("available_from_day", 0)) != 3:
			errors.append("junction_j7 musi być dostępny od dnia 3.")
		if str(junction.get("interaction_action", "")) != "activate":
			errors.append("junction_j7 musi używać akcji activate.")
	var tutorial_route_value = gameplay.get("tutorial_route", null)
	if tutorial_route_value is Array:
		var required_route := [
			entry_landmark_id,
			TUTORIAL_MARKET_CRATE_ID,
			TUTORIAL_WORKSHOP_CASE_ID,
			TUTORIAL_SHORTCUT_ID,
			TUTORIAL_DEVICE_ID,
			"exit",
		]
		if not _ordered_subsequence(required_route, tutorial_route_value as Array):
			errors.append("tutorial_route musi zachować kolejność wymaganych ID tutoriala.")


func _record_by_id(records_value, record_id: String) -> Dictionary:
	if not records_value is Array:
		return {}
	for record_value in records_value as Array:
		if record_value is Dictionary and str((record_value as Dictionary).get("id", "")) == record_id:
			return record_value as Dictionary
	return {}


func _ordered_subsequence(required_values: Array, source_values: Array) -> bool:
	var required_index := 0
	for source_value in source_values:
		if required_index < required_values.size() and str(source_value) == str(required_values[required_index]):
			required_index += 1
	return required_index == required_values.size()


func _register_unique_id(
	record_id: String,
	record_label: String,
	seen_ids: Dictionary,
	errors: PackedStringArray
) -> void:
	if record_id.is_empty():
		errors.append("ID %s nie może być puste." % record_label)
		return
	if seen_ids.has(record_id):
		errors.append("ID %s %s nie jest globalnie unikalne." % [record_label, record_id])
		return
	seen_ids[record_id] = true


func _pickup_contents_are_single_item(contents: Dictionary) -> bool:
	if contents.size() != 1:
		return false
	return int(contents.values()[0]) == 1


func _dictionary_has_exact_keys(source: Dictionary, expected_keys: Array) -> bool:
	if source.size() != expected_keys.size():
		return false
	for key in expected_keys:
		if not source.has(key):
			return false
	return true


func _dictionary_has_required_and_optional_keys(
	source: Dictionary,
	required_keys: Array,
	optional_keys: Array,
) -> bool:
	for key in required_keys:
		if not source.has(key):
			return false
	for key in source.keys():
		if key not in required_keys and key not in optional_keys:
			return false
	return true


func _valid_lower_snake_case_id(value: String) -> bool:
	if value.is_empty() or not "abcdefghijklmnopqrstuvwxyz".contains(value.left(1)):
		return false
	for index in range(1, value.length()):
		if not "abcdefghijklmnopqrstuvwxyz0123456789_".contains(value.substr(index, 1)):
			return false
	return true


func _valid_finite_number_array(value, expected_size: int) -> bool:
	if not value is Array or (value as Array).size() != expected_size:
		return false
	for component in value as Array:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			return false
	return true


func _valid_integral_array(value, expected_size: int) -> bool:
	if not value is Array or (value as Array).size() != expected_size:
		return false
	for component in value as Array:
		if not _is_integral_number(component):
			return false
	return true


func _valid_positive_integral_array(value, expected_size: int) -> bool:
	if not _valid_integral_array(value, expected_size):
		return false
	for component in value as Array:
		if int(component) <= 0:
			return false
	return true


func _string_set_equals(value, expected_values: Array) -> bool:
	if not value is Array:
		return false
	var actual_set: Dictionary = {}
	for item in value as Array:
		if not item is String:
			return false
		actual_set[str(item)] = true
	var expected_set: Dictionary = {}
	for expected_value in expected_values:
		expected_set[str(expected_value)] = true
	return _canonical_json(actual_set) == _canonical_json(expected_set)


func _validate_expected_file_sha(
	resource_path: String,
	expected_sha_value,
	label: String,
	errors: PackedStringArray,
) -> bool:
	if not expected_sha_value is String or not _valid_sha256(str(expected_sha_value), false):
		errors.append("%s.sha256 musi być małym SHA-256." % label)
		return false
	var actual_sha := FileAccess.get_sha256(resource_path).to_lower()
	if actual_sha != str(expected_sha_value):
		errors.append("%s.sha256 jest nieaktualne; oczekiwane %s." % [label, actual_sha])
		return false
	return true


func _is_integral_number(value) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number)


func _canonical_numbers_are_finite(value) -> bool:
	match typeof(value):
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_DICTIONARY:
			for child_value in (value as Dictionary).values():
				if not _canonical_numbers_are_finite(child_value):
					return false
		TYPE_ARRAY:
			for child_value in value as Array:
				if not _canonical_numbers_are_finite(child_value):
					return false
	return true


func _valid_json_color(value) -> bool:
	if not value is String:
		return false
	var normalized := str(value).strip_edges().trim_prefix("#")
	if normalized.length() not in [6, 8]:
		return false
	var lowercase := normalized.to_lower()
	for index in range(lowercase.length()):
		var character := lowercase.substr(index, 1)
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _valid_visual_group_id(value: String) -> bool:
	if value.is_empty() or not "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".contains(value.left(1)):
		return false
	for index in range(1, value.length()):
		if not "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_".contains(
			value.substr(index, 1)
		):
			return false
	return true


func _append_source_path(paths: PackedStringArray, package_path: String) -> void:
	var resource_path := _package_resource_path(package_path)
	_append_unique_path(paths, resource_path)


func _append_workbench_source_path(paths: PackedStringArray, package_path: String) -> void:
	_append_unique_path(paths, _workbench_resource_path(package_path, ["assets", "structures"]))


func _append_unique_path(paths: PackedStringArray, resource_path: String) -> void:
	if not resource_path.is_empty() and not paths.has(resource_path):
		paths.append(resource_path)


func _sorted_unique_dependency_paths(paths: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for resource_path in paths:
		_append_unique_path(result, resource_path)
	result.sort()
	return result


func _package_resource_path(package_path: String) -> String:
	return _workbench_resource_path(package_path, ["assets"])


func _workbench_resource_path(package_path: String, allowed_roots: Array) -> String:
	var normalized := package_path.strip_edges()
	if normalized.is_empty() or normalized.contains("\\") or normalized.begins_with("/"):
		return ""
	var parts := normalized.split("/", true)
	if parts.is_empty() or str(parts[0]) not in allowed_roots:
		return ""
	for part in parts:
		if part.is_empty() or part in [".", ".."] or str(part).contains(":"):
			return ""
	return "res://underwater_map_workbench/%s" % normalized


func _structure_package_member_workbench_path(
	package_path: String,
	member_path: String,
) -> String:
	var normalized_package_path := package_path.strip_edges()
	var normalized_member_path := member_path.strip_edges()
	if (
		normalized_package_path.is_empty()
		or normalized_member_path.is_empty()
		or normalized_member_path.contains("\\")
		or normalized_member_path.begins_with("/")
	):
		return ""
	var member_parts := normalized_member_path.split("/", true)
	for part in member_parts:
		if part.is_empty() or part in [".", ".."] or str(part).contains(":"):
			return ""
	var package_directory := normalized_package_path.get_base_dir()
	if package_directory.is_empty():
		return ""
	var resolved_path := "%s/%s" % [package_directory, normalized_member_path]
	if not resolved_path.begins_with(package_directory + "/"):
		return ""
	if _workbench_resource_path(resolved_path, ["structures"]).is_empty():
		return ""
	return resolved_path


func _structure_package_member_resource_path(
	package_path: String,
	member_path: String,
) -> String:
	var resolved_path := _structure_package_member_workbench_path(package_path, member_path)
	return _workbench_resource_path(resolved_path, ["structures"])


func _validate_composition_proxy_asset(
	asset: Dictionary,
	label: String,
	errors: PackedStringArray
) -> void:
	if asset.get("path", null) != "":
		errors.append("%s proxy kompozycyjne musi mieć puste path." % label)
	if asset.get("sha256", null) != "":
		errors.append("%s proxy kompozycyjne musi mieć puste sha256." % label)
	var pixel_size_value = asset.get("pixel_size", null)
	var declared_integral := pixel_size_value is Array and (pixel_size_value as Array).size() == 2
	if declared_integral:
		for component in pixel_size_value as Array:
			if not _is_integral_number(component) or int(component) <= 0:
				declared_integral = false
				break
	if not declared_integral:
		errors.append(
			"%s proxy kompozycyjne musi deklarować dwie dodatnie całkowite wartości pixel_size."
			% label
		)


func _validate_hashed_png_asset(
	asset: Dictionary,
	label: String,
	errors: PackedStringArray,
	allow_structure_package: bool = false,
) -> void:
	var path_value = asset.get("path", null)
	if not path_value is String:
		errors.append("%s.path musi być Stringiem." % label)
		return
	var allowed_roots: Array = ["assets", "structures"] if allow_structure_package else ["assets"]
	var resource_path := _workbench_resource_path(str(path_value), allowed_roots)
	if resource_path.is_empty():
		errors.append("%s.path musi pozostać lokalną ścieżką źródła warsztatu." % label)
		return
	if not FileAccess.file_exists(resource_path):
		errors.append("%s.path nie istnieje: %s." % [label, path_value])
		return
	var expected_sha_value = asset.get("sha256", null)
	if not expected_sha_value is String or not _valid_sha256(str(expected_sha_value), false):
		errors.append("%s.sha256 musi być małym SHA-256." % label)
		return
	var actual_sha := FileAccess.get_sha256(resource_path).to_lower()
	if actual_sha != str(expected_sha_value):
		errors.append("%s.sha256 jest nieaktualne; oczekiwane %s." % [label, actual_sha])
	var pixel_size_value = asset.get("pixel_size", null)
	var declared_size := _json_vector(pixel_size_value)
	var declared_integral := pixel_size_value is Array and (pixel_size_value as Array).size() == 2
	if declared_integral:
		for component in pixel_size_value as Array:
			if not _is_integral_number(component) or int(component) <= 0:
				declared_integral = false
				break
	if not declared_integral:
		errors.append("%s.pixel_size musi zawierać dwie dodatnie liczby całkowite." % label)
		return
	var actual_size := _png_dimensions(resource_path)
	if actual_size == Vector2i.ZERO:
		errors.append("%s.path musi wskazywać poprawny PNG." % label)
		return
	if actual_size != Vector2i(int(declared_size.x), int(declared_size.y)):
		errors.append("%s.pixel_size nie odpowiada wymiarom PNG %s." % [label, actual_size])


func _decode_l05_collision_source(
	topology: Dictionary,
	structures: Dictionary,
	errors: PackedStringArray
) -> Dictionary:
	var initial_error_count := errors.size()
	var collision_value = topology.get("collision_source", null)
	if not collision_value is Dictionary:
		errors.append("L05 wymaga obiektu topology.collision_source.")
		return {}
	var collision := collision_value as Dictionary
	if str(collision.get("format", "")) != L05_SOURCE_FORMAT:
		errors.append("L05 wymaga collision_source.format=%s." % L05_SOURCE_FORMAT)
		return {}
	var mapping_value = collision.get("mapping", null)
	if (
		not mapping_value is Dictionary
		or _canonical_json(mapping_value) != _canonical_json(L05_MAPPING)
	):
		errors.append("topology.collision_source.mapping nie odpowiada pełnemu mapowaniu L05 v1.")
		return {}
	var encoding_value = collision.get("encoding", null)
	if not encoding_value is Dictionary:
		errors.append("L05 wymaga obiektu encoding.")
		return {}
	var encoding := encoding_value as Dictionary
	var solid_value = encoding.get("solid", null)
	var open_water_value = encoding.get("open_water", null)
	if (
		not _is_integral_number(solid_value)
		or not _is_integral_number(open_water_value)
		or int(solid_value) != 0
		or int(open_water_value) != 255
	):
		errors.append("L05 wymaga encoding solid=0 i open_water=255.")
		return {}
	var path_value = collision.get("path", null)
	if not path_value is String:
		errors.append("L05 collision_source.path musi być Stringiem.")
		return {}
	var resource_path := _package_resource_path(str(path_value))
	if resource_path.is_empty():
		errors.append("L05 collision_source.path musi pozostać lokalną ścieżką assets/... warsztatu.")
		return {}
	if not FileAccess.file_exists(resource_path):
		errors.append("Brak payloadu L05: %s." % path_value)
		return {}
	var expected_sha_value = collision.get("sha256", null)
	if not expected_sha_value is String or not _valid_sha256(str(expected_sha_value), false):
		errors.append("L05 collision_source.sha256 musi być małym SHA-256.")
		return {}
	var actual_sha := FileAccess.get_sha256(resource_path).to_lower()
	if actual_sha != str(expected_sha_value):
		errors.append("L05 collision_source.sha256 jest nieaktualne; oczekiwane %s." % actual_sha)
		return {}
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		errors.append("Nie można otworzyć payloadu L05.")
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		errors.append("Payload L05 nie jest poprawnym obiektem JSON.")
		return {}
	var payload := parsed as Dictionary
	if not _dictionary_has_exact_keys(payload, ["schema_version", "base", "operations"]):
		errors.append("Payload L05 musi zawierać wyłącznie schema_version, base i operations.")
		return {}
	if not _is_integral_number(payload.get("schema_version", null)) or int(payload.get("schema_version", 0)) != 2:
		errors.append("Payload L05 musi używać schema_version=2.")
		return {}
	if str(payload.get("base", "")) != "open_water":
		errors.append("Payload L05 musi używać base=open_water.")
		return {}
	var operations_value = payload.get("operations", null)
	if not operations_value is Array:
		errors.append("Payload L05 wymaga tablicy operations.")
		return {}
	var cells := PackedByteArray()
	cells.resize(L05_PIXEL_SIZE.x * L05_PIXEL_SIZE.y)
	cells.fill(int(open_water_value))
	var solid_owner_cells := PackedInt32Array()
	solid_owner_cells.resize(cells.size())
	solid_owner_cells.fill(0)
	var owner_ids := PackedStringArray(["", "world"])
	var structure_instances_by_id := _structure_instances_by_id(structures)
	var structure_owner_index_by_id: Dictionary = {}
	var instances_value = structures.get("instances", null)
	if not instances_value is Array:
		errors.append("Dekodowanie L05 wymaga structures.instances.")
		return {}
	for instance_value in instances_value as Array:
		if not instance_value is Dictionary:
			continue
		var instance := instance_value as Dictionary
		if not bool(instance.get("enabled", false)):
			continue
		var structure_id := str(instance.get("id", ""))
		if structure_id.is_empty() or structure_owner_index_by_id.has(structure_id):
			errors.append("Dekodowanie L05 wymaga stabilnych, unikalnych ID struktur.")
			continue
		structure_owner_index_by_id[structure_id] = owner_ids.size()
		owner_ids.append(structure_id)
	var merged_operations := (operations_value as Array).duplicate(true)
	var uses_structure_packages := false
	for instance_value in instances_value as Array:
		if not instance_value is Dictionary:
			continue
		var instance := instance_value as Dictionary
		if instance.has("package_path"):
			uses_structure_packages = true
		if not bool(instance.get("enabled", false)):
			continue
		var local_operations_value = instance.get("collision_operations", null)
		if local_operations_value is Array:
			merged_operations.append_array((local_operations_value as Array).duplicate(true))
	if uses_structure_packages:
		for index in range((operations_value as Array).size()):
			var global_operation_value = (operations_value as Array)[index]
			if (
				global_operation_value is Dictionary
				and str((global_operation_value as Dictionary).get("space", "")) != "world_px"
			):
				errors.append(
					"Globalny payload L05 może zawierać tylko operations w space=world_px; "
					+ "geometria struktur należy do pakietów."
				)
	var operation_ids := {}
	for index in range(merged_operations.size()):
		var operation_value = merged_operations[index]
		var label := "L05 operations[%d]" % index
		if not operation_value is Dictionary:
			errors.append("%s musi być obiektem." % label)
			continue
		var operation := operation_value as Dictionary
		var operation_space := str(operation.get("space", ""))
		var expected_operation_keys := ["id", "op", "space", "rect_px"]
		if operation_space == "structure_local_px":
			expected_operation_keys.append("structure_id")
		if not _dictionary_has_exact_keys(operation, expected_operation_keys):
			errors.append("%s ma niepoprawny zestaw pól dla swojej przestrzeni." % label)
			continue
		if operation_space not in ["world_px", "structure_local_px"]:
			errors.append("%s.space musi być world_px albo structure_local_px." % label)
			continue
		var operation_id_value = operation.get("id", null)
		var operation_id := str(operation_id_value).strip_edges()
		if not operation_id_value is String or operation_id.is_empty() or operation_ids.has(operation_id):
			errors.append("%s wymaga niepustego, unikalnego ID." % label)
			continue
		operation_ids[operation_id] = true
		var operation_kind := str(operation.get("op", ""))
		if operation_kind not in ["solid_rect", "open_rect"]:
			errors.append("%s.op musi być solid_rect albo open_rect." % label)
			continue
		var rect_value = operation.get("rect_px", null)
		var rect_valid := rect_value is Array and (rect_value as Array).size() == 4
		if rect_valid:
			for component in rect_value as Array:
				if not _is_integral_number(component):
					rect_valid = false
					break
		if not rect_valid:
			errors.append("%s.rect_px musi zawierać cztery liczby całkowite." % label)
			continue
		var rect_components := rect_value as Array
		var x := int(rect_components[0])
		var y := int(rect_components[1])
		var width := int(rect_components[2])
		var height := int(rect_components[3])
		var owner_index := 1
		if operation_space == "structure_local_px":
			var structure_id_value = operation.get("structure_id", null)
			var structure_id := str(structure_id_value).strip_edges()
			if (
				not structure_id_value is String
				or not structure_instances_by_id.has(structure_id)
				or not structure_owner_index_by_id.has(structure_id)
			):
				errors.append("%s wskazuje nieznane structure_id %s." % [label, structure_id])
				continue
			var structure: Dictionary = structure_instances_by_id[structure_id]
			if not bool(structure.get("enabled", false)):
				errors.append("%s wskazuje wyłączoną strukturę %s." % [label, structure_id])
				continue
			var local_pixel_size := Vector2i(
				roundi(_json_vector(structure.get("size", [])).x / L05_WORLD_UNITS_PER_PIXEL.x),
				roundi(_json_vector(structure.get("size", [])).y / L05_WORLD_UNITS_PER_PIXEL.y)
			)
			if (
				x < 0
				or y < 0
				or width <= 0
				or height <= 0
				or x + width > local_pixel_size.x
				or y + height > local_pixel_size.y
			):
				errors.append("%s.rect_px wykracza poza lokalny raster struktury." % label)
				continue
			var structure_origin := _json_vector(structure.get("origin", []))
			x += roundi(structure_origin.x / L05_WORLD_UNITS_PER_PIXEL.x)
			y += roundi(structure_origin.y / L05_WORLD_UNITS_PER_PIXEL.y)
			owner_index = int(structure_owner_index_by_id[structure_id])
		elif (
			x < 0
			or y < 0
			or width <= 0
			or height <= 0
			or x + width > L05_PIXEL_SIZE.x
			or y + height > L05_PIXEL_SIZE.y
		):
			errors.append("%s.rect_px wykracza poza raster L05." % label)
			continue
		var fill_value := int(solid_value) if operation_kind == "solid_rect" else int(open_water_value)
		var fill_owner := owner_index if operation_kind == "solid_rect" else 0
		for row in range(y, y + height):
			var start := row * L05_PIXEL_SIZE.x + x
			for cell_index in range(start, start + width):
				cells[cell_index] = fill_value
				solid_owner_cells[cell_index] = fill_owner
	if errors.size() > initial_error_count:
		return {}
	for cell_index in range(cells.size()):
		if int(cells[cell_index]) == int(solid_value):
			var owner_index := int(solid_owner_cells[cell_index])
			if owner_index <= 0 or owner_index >= owner_ids.size():
				errors.append("Komórka solid L05 nie ma poprawnego właściciela.")
				return {}
		elif int(solid_owner_cells[cell_index]) != 0:
			errors.append("Komórka open_water L05 ma właściciela kolizji.")
			return {}
	var digest_payload := {
		"mapping": (mapping_value as Dictionary).duplicate(true),
		"encoding": encoding.duplicate(true),
		"pixel_size": [L05_PIXEL_SIZE.x, L05_PIXEL_SIZE.y],
		"cells_hex": cells.hex_encode(),
	}
	var canonical_digest := "topology-v1:%s" % _canonical_sha256(digest_payload)
	var declared_digest_value = collision.get("canonical_digest", null)
	if (
		not declared_digest_value is String
		or not _valid_topology_digest(str(declared_digest_value))
	):
		errors.append("L05 canonical_digest musi mieć format topology-v1:<sha256>.")
		return {}
	if str(declared_digest_value) != canonical_digest:
		errors.append("L05 canonical_digest jest nieaktualny; oczekiwane %s." % canonical_digest)
		return {}
	var partition_payload := {
		"owner_ids": _packed_string_to_array(owner_ids),
		"solid_owner_cells": _packed_int32_to_array(solid_owner_cells),
	}
	var partition_digest := "partition-v1:%s" % _canonical_sha256(partition_payload)
	var declared_partition_digest_value = collision.get("partition_digest", null)
	if (
		not declared_partition_digest_value is String
		or not _valid_partition_digest(str(declared_partition_digest_value))
	):
		errors.append("L05 partition_digest musi mieć format partition-v1:<sha256>.")
		return {}
	if str(declared_partition_digest_value) != partition_digest:
		errors.append("L05 partition_digest jest nieaktualny; oczekiwane %s." % partition_digest)
		return {}
	return {
		"cells": cells,
		"solid_owner_cells": solid_owner_cells,
		"owner_ids": owner_ids,
		"solid": int(solid_value),
		"open_water": int(open_water_value),
		"payload_sha256": actual_sha,
		"canonical_digest": canonical_digest,
		"partition_digest": partition_digest,
	}


func _generated_l05_mask_errors(
	topology: Dictionary,
	structures: Dictionary
) -> PackedStringArray:
	var errors := PackedStringArray()
	var decoded := _decode_l05_collision_source(topology, structures, errors)
	if not errors.is_empty():
		return errors
	if not FileAccess.file_exists(L05_SOLID_MASK_PATH):
		errors.append("Brak wygenerowanej maski L05; uruchom builder.")
		return errors
	var mask_texture := ResourceLoader.load(
		L05_SOLID_MASK_PATH,
		"Texture2D",
		ResourceLoader.CACHE_MODE_IGNORE
	) as Texture2D
	if mask_texture == null:
		errors.append("Wygenerowana maska L05 nie jest poprawnym PNG.")
		return errors
	var mask_image := mask_texture.get_image()
	if mask_image == null or mask_image.is_empty():
		errors.append("Nie można odczytać pikseli wygenerowanej maski L05.")
		return errors
	if mask_image.get_size() != L05_PIXEL_SIZE:
		errors.append("Wygenerowana maska L05 ma niepoprawny rozmiar.")
		return errors
	mask_image.convert(Image.FORMAT_L8)
	var mask_data := mask_image.get_data()
	var encoded_cells: PackedByteArray = decoded.get("cells", PackedByteArray())
	var solid_value := int(decoded.get("solid", 0))
	if mask_data.size() != encoded_cells.size():
		errors.append("Wygenerowana maska L05 ma niepoprawną liczbę pikseli.")
		return errors
	for index in range(encoded_cells.size()):
		var expected_mask_value := 255 if int(encoded_cells[index]) == solid_value else 0
		if int(mask_data[index]) != expected_mask_value:
			errors.append("Wygenerowana maska L05 nie odpowiada payloadowi przy pikselu %d." % index)
			break
	errors.append_array(_generated_l05_surface_detail_mask_errors(decoded, structures))
	return errors


func _generated_l05_surface_detail_mask_errors(
	decoded: Dictionary,
	structures: Dictionary,
) -> PackedStringArray:
	var errors := PackedStringArray()
	if not FileAccess.file_exists(L05_SURFACE_DETAIL_MASK_PATH):
		errors.append("Brak wygenerowanej maski detalu L05; uruchom builder.")
		return errors
	var texture := ResourceLoader.load(
		L05_SURFACE_DETAIL_MASK_PATH,
		"Texture2D",
		ResourceLoader.CACHE_MODE_IGNORE,
	) as Texture2D
	if texture == null:
		errors.append("Wygenerowana maska detalu L05 nie jest poprawnym PNG.")
		return errors
	var image := texture.get_image()
	if image == null or image.is_empty() or image.get_size() != L05_PIXEL_SIZE:
		errors.append("Wygenerowana maska detalu L05 ma niepoprawny rozmiar lub piksele.")
		return errors
	image.convert(Image.FORMAT_RGBA8)
	var actual := image.get_data()
	var expected := _expected_l05_surface_detail_mask(decoded, structures)
	if actual.size() != expected.size():
		errors.append("Wygenerowana maska detalu L05 ma niepoprawną liczbę bajtów.")
		return errors
	for index in range(expected.size()):
		if actual[index] != expected[index]:
			errors.append(
				"Wygenerowana maska detalu L05 jest nieaktualna przy bajcie %d."
				% index
			)
			break
	return errors


func _expected_l05_surface_detail_mask(
	decoded: Dictionary,
	structures: Dictionary,
) -> PackedByteArray:
	var width := L05_PIXEL_SIZE.x
	var height := L05_PIXEL_SIZE.y
	var cells: PackedByteArray = decoded.get("cells", PackedByteArray())
	var solid_value := int(decoded.get("solid", 0))
	var owners: PackedInt32Array = decoded.get("solid_owner_cells", PackedInt32Array())
	var result := PackedByteArray()
	result.resize(width * height * 4)
	for cell_index in range(width * height):
		result[cell_index * 4 + 3] = 255

	var distances := PackedInt32Array()
	distances.resize(width * height)
	distances.fill(-1)
	var queue := PackedInt32Array()
	var directions: Array[Vector2i] = [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]
	for y in range(height):
		for x in range(width):
			var index := y * width + x
			if int(cells[index]) != solid_value:
				continue
			var exposed := false
			for direction in directions:
				var neighbor: Vector2i = Vector2i(x, y) + direction
				if not _l05_cell_is_solid(cells, solid_value, neighbor.x, neighbor.y):
					exposed = true
					break
			if exposed:
				distances[index] = 0
				queue.append(index)
	var queue_head := 0
	while queue_head < queue.size():
		var index := int(queue[queue_head])
		queue_head += 1
		var distance := int(distances[index])
		if distance >= 3:
			continue
		var position := Vector2i(index % width, floori(float(index) / float(width)))
		for direction in directions:
			var neighbor: Vector2i = position + direction
			if not _l05_cell_is_solid(cells, solid_value, neighbor.x, neighbor.y):
				continue
			var neighbor_index: int = neighbor.y * width + neighbor.x
			if int(distances[neighbor_index]) >= 0:
				continue
			distances[neighbor_index] = distance + 1
			queue.append(neighbor_index)
	var edge_values := PackedByteArray([255, 184, 112, 48])
	for index in range(distances.size()):
		var distance := int(distances[index])
		if distance >= 0 and distance < edge_values.size():
			result[index * 4] = edge_values[distance]

	var seam_directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN]
	for y in range(height):
		for x in range(width):
			var index := y * width + x
			var owner := int(owners[index])
			if int(cells[index]) != solid_value or owner <= 0:
				continue
			for direction in seam_directions:
				var neighbor: Vector2i = Vector2i(x, y) + direction
				if not _l05_cell_is_solid(cells, solid_value, neighbor.x, neighbor.y):
					continue
				var neighbor_index: int = neighbor.y * width + neighbor.x
				var neighbor_owner := int(owners[neighbor_index])
				if neighbor_owner > 0 and neighbor_owner != owner:
					result[index * 4 + 1] = 255
					result[neighbor_index * 4 + 1] = 255

	var instances_value = structures.get("instances", [])
	if instances_value is Array:
		for instance_value in instances_value as Array:
			if not instance_value is Dictionary:
				continue
			var instance := instance_value as Dictionary
			if not bool(instance.get("enabled", false)):
				continue
			var origin := _json_vector(instance.get("origin", []))
			var structure_size := _json_vector(instance.get("size", []))
			var origin_px := Vector2i(
				roundi(origin.x / L05_WORLD_UNITS_PER_PIXEL.x),
				roundi(origin.y / L05_WORLD_UNITS_PER_PIXEL.y),
			)
			var size_px := Vector2i(
				roundi(structure_size.x / L05_WORLD_UNITS_PER_PIXEL.x),
				roundi(structure_size.y / L05_WORLD_UNITS_PER_PIXEL.y),
			)
			var sockets_value = instance.get("sockets", [])
			if not sockets_value is Array:
				continue
			for socket_value in sockets_value as Array:
				if not socket_value is Dictionary:
					continue
				var socket_rect := _json_rect((socket_value as Dictionary).get("local_rect", null))
				var local_left := maxi(0, floori(socket_rect.position.x / L05_WORLD_UNITS_PER_PIXEL.x))
				var local_top := maxi(0, floori(socket_rect.position.y / L05_WORLD_UNITS_PER_PIXEL.y))
				var local_right := mini(
					size_px.x,
					ceili(socket_rect.end.x / L05_WORLD_UNITS_PER_PIXEL.x),
				)
				var local_bottom := mini(
					size_px.y,
					ceili(socket_rect.end.y / L05_WORLD_UNITS_PER_PIXEL.y),
				)
				if local_left >= local_right or local_top >= local_bottom:
					continue
				var cell_rect := Rect2i(
					origin_px + Vector2i(local_left, local_top),
					Vector2i(local_right - local_left, local_bottom - local_top),
				)
				if not _l05_rect_has_open_cell(cells, solid_value, cell_rect):
					continue
				var touches_left := socket_rect.position.x <= 0.0
				var touches_top := socket_rect.position.y <= 0.0
				var touches_right := socket_rect.end.x >= structure_size.x
				var touches_bottom := socket_rect.end.y >= structure_size.y
				var has_continuity := false
				if touches_left:
					for y in range(cell_rect.position.y, cell_rect.end.y):
						if (
							not _l05_cell_is_solid(cells, solid_value, origin_px.x - 1, y)
							and not _l05_cell_is_solid(cells, solid_value, origin_px.x, y)
						):
							has_continuity = true
							break
				if not has_continuity and touches_right:
					for y in range(cell_rect.position.y, cell_rect.end.y):
						if (
							not _l05_cell_is_solid(cells, solid_value, origin_px.x + size_px.x, y)
							and not _l05_cell_is_solid(cells, solid_value, origin_px.x + size_px.x - 1, y)
						):
							has_continuity = true
							break
				if not has_continuity and touches_top:
					for x in range(cell_rect.position.x, cell_rect.end.x):
						if (
							not _l05_cell_is_solid(cells, solid_value, x, origin_px.y - 1)
							and not _l05_cell_is_solid(cells, solid_value, x, origin_px.y)
						):
							has_continuity = true
							break
				if not has_continuity and touches_bottom:
					for x in range(cell_rect.position.x, cell_rect.end.x):
						if (
							not _l05_cell_is_solid(cells, solid_value, x, origin_px.y + size_px.y)
							and not _l05_cell_is_solid(cells, solid_value, x, origin_px.y + size_px.y - 1)
						):
							has_continuity = true
							break
				if not has_continuity:
					continue
				for y in range(cell_rect.position.y - 1, cell_rect.end.y + 1):
					for x in range(cell_rect.position.x - 1, cell_rect.end.x + 1):
						if _l05_cell_is_solid(cells, solid_value, x, y):
							result[(y * width + x) * 4 + 2] = 255
	return result


func _l05_cell_is_solid(
	cells: PackedByteArray,
	solid_value: int,
	x: int,
	y: int,
) -> bool:
	if x < 0 or y < 0 or x >= L05_PIXEL_SIZE.x or y >= L05_PIXEL_SIZE.y:
		return false
	return int(cells[y * L05_PIXEL_SIZE.x + x]) == solid_value


func _l05_rect_has_open_cell(
	cells: PackedByteArray,
	solid_value: int,
	rect: Rect2i,
) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not _l05_cell_is_solid(cells, solid_value, x, y):
				return true
	return false


func _valid_topology_digest(value: String) -> bool:
	if not value.begins_with("topology-v1:"):
		return false
	return _valid_sha256(value.trim_prefix("topology-v1:"), false)


func _valid_partition_digest(value: String) -> bool:
	if not value.begins_with("partition-v1:"):
		return false
	return _valid_sha256(value.trim_prefix("partition-v1:"), false)


func _valid_structure_topology_digest(value: String) -> bool:
	if not value.begins_with("structure-topology-v1:"):
		return false
	return _valid_sha256(value.trim_prefix("structure-topology-v1:"), false)


func _png_dimensions(resource_path: String) -> Vector2i:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null or file.get_length() < 24:
		return Vector2i.ZERO
	var signature := file.get_buffer(8)
	var expected_signature := PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10])
	if signature != expected_signature:
		return Vector2i.ZERO
	file.big_endian = true
	var chunk_length := file.get_32()
	var chunk_type := file.get_buffer(4)
	if chunk_length != 13 or chunk_type != "IHDR".to_ascii_buffer():
		return Vector2i.ZERO
	var width := int(file.get_32())
	var height := int(file.get_32())
	if width <= 0 or height <= 0:
		return Vector2i.ZERO
	return Vector2i(width, height)


func _valid_sha256(value: String, allow_empty: bool) -> bool:
	if allow_empty and value.is_empty():
		return true
	if value.length() != 64 or value != value.to_lower():
		return false
	for index in range(value.length()):
		var character := value.substr(index, 1)
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _rect_inside_world(bounds: Rect2, world_size: Vector2) -> bool:
	return (
		bounds.position.is_finite()
		and bounds.size.is_finite()
		and bounds.position.x >= 0.0
		and bounds.position.y >= 0.0
		and bounds.size.x > 0.0
		and bounds.size.y > 0.0
		and bounds.end.x <= world_size.x
		and bounds.end.y <= world_size.y
	)


func _rect_inside_local(bounds: Rect2, size: Vector2) -> bool:
	return _rect_inside_world(bounds, size)


func _vector_is_aligned(value: Vector2, step: Vector2) -> bool:
	if not value.is_finite() or step.x <= 0.0 or step.y <= 0.0:
		return false
	return (
		is_equal_approx(value.x / step.x, round(value.x / step.x))
		and is_equal_approx(value.y / step.y, round(value.y / step.y))
	)


func _structure_instances_by_id(structures: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var instances_value = structures.get("instances", null)
	if not instances_value is Array:
		return result
	for instance_value in instances_value as Array:
		if not instance_value is Dictionary:
			continue
		var instance := instance_value as Dictionary
		var structure_id := str(instance.get("id", ""))
		if not structure_id.is_empty():
			result[structure_id] = instance
	return result


func _packed_string_to_array(source: PackedStringArray) -> Array:
	var result := []
	for value in source:
		result.append(value)
	return result


func _packed_int32_to_array(source: PackedInt32Array) -> Array:
	var result := []
	result.resize(source.size())
	for index in range(source.size()):
		result[index] = int(source[index])
	return result


func _dictionary_array(value, label: String, errors: PackedStringArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		errors.append("%s musi być tablicą." % label)
		return result
	for candidate in value:
		if not candidate is Dictionary:
			errors.append("%s zawiera rekord inny niż obiekt." % label)
			continue
		result.append(candidate)
	return result


func _json_vector_array(value) -> PackedVector2Array:
	if value is PackedVector2Array:
		return (value as PackedVector2Array).duplicate()
	var result := PackedVector2Array()
	if not value is Array:
		return result
	for point_value in value as Array:
		result.append(_json_vector(point_value))
	return result


func _json_vector(value) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2(INF, INF)
	var values := value as Array
	if typeof(values[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(values[1]) not in [TYPE_INT, TYPE_FLOAT]:
		return Vector2(INF, INF)
	return Vector2(float(values[0]), float(values[1]))


func _json_rect(value) -> Rect2:
	if not value is Array or (value as Array).size() != 4:
		return Rect2(Vector2(INF, INF), Vector2.ZERO)
	var values := value as Array
	for component in values:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT]:
			return Rect2(Vector2(INF, INF), Vector2.ZERO)
	return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))


func _json_color(value) -> Color:
	return Color.from_string("#%s" % str(value).trim_prefix("#"), Color(0.03, 0.16, 0.22, 1.0))


func _point_inside_world(point: Vector2, world_size: Vector2) -> bool:
	return point.is_finite() and Rect2(Vector2.ZERO, world_size).has_point(point)


func _point_inside_local_rect(point: Vector2, size: Vector2) -> bool:
	return (
		point.is_finite()
		and size.is_finite()
		and size.x > 0.0
		and size.y > 0.0
		and Rect2(Vector2.ZERO, size).has_point(point)
	)


func _duplicate_raster(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	var cells: PackedByteArray = source.get("cells", PackedByteArray())
	result["cells"] = cells.duplicate()
	var solid_owner_cells: PackedInt32Array = source.get(
		"solid_owner_cells",
		PackedInt32Array()
	)
	result["solid_owner_cells"] = solid_owner_cells.duplicate()
	var owner_ids: PackedStringArray = source.get("owner_ids", PackedStringArray())
	result["owner_ids"] = owner_ids.duplicate()
	return result
