class_name UnderwaterMapSceneCompiler
extends RefCounted

const WorldStateScript := preload("res://scripts/data/UnderwaterWorldState.gd")
const WorldBlueprintScript := preload("res://scripts/data/WorldBlueprint.gd")

const MANIFEST_PATH := "res://underwater_map_workbench/map_manifest.json"
const MAP_SCENE_PATH := "res://underwater_map_workbench/UnderwaterMap.tscn"
const MAP_SOURCE_VERSION := 5
const MANIFEST_SCHEMA_VERSION := 2
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
const NONBLOCKING_TEXTURE_LAYER_IDS := ["L01", "L02"]
const GROUND_ANCHORED_BACKDROP_LAYER_IDS := ["L01", "L02"]
const NONBLOCKING_BACKDROP_AFFORDANCE := "nonblocking_backdrop"
const L05_TOPOLOGY_MODE := "l05_mask_v1"
const L05_SOURCE_FORMAT := "l05_rect_ops_v1"
const L05_PIXEL_SIZE := Vector2i(576, 324)
const L05_WORLD_UNITS_PER_PIXEL := Vector2(40.0, 40.0)
const L05_MAPPING := {
	"world_origin": [0, 0],
	"x_axis": "right",
	"y_axis": "down",
	"pixel_reference": "pixel_edge",
	"rounding": "floor",
}
const L05_SOLID_MASK_PATH := "res://underwater_map_workbench/assets/generated/l05/solid_mask.png"
const L05_SHADER_PATH := "res://underwater_map_workbench/assets/shaders/l05_ground_masked.gdshader"
const VISUAL_ASSET_KEYS := [
	"id", "layer_id", "kind", "path", "sha256", "pixel_size", "world_rect",
	"enabled", "affordance", "topology_digest",
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
static var _cached_gameplay_signature := ""
static var _cached_presentation_fingerprint := ""
static var _cached_blueprints: Dictionary = {}
static var _cached_navigation_raster: Dictionary = {}


static func clear_runtime_caches() -> void:
	_cached_manifest_hash = ""
	_cached_manifest.clear()
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
	return _manifest_validation_errors(manifest)


func compile_from_manifest_for_tests(manifest: Dictionary, campaign_seed: int = 1) -> Dictionary:
	var errors := _manifest_validation_errors(manifest)
	if not errors.is_empty():
		return {
			"errors": errors,
			"map_gameplay_signature": "",
			"presentation_fingerprint": "",
		}
	var identities := _manifest_identities(manifest)
	var blueprint = _build_blueprint(
		manifest,
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


func source_dependency_paths() -> PackedStringArray:
	var paths := PackedStringArray([MANIFEST_PATH, MAP_SCENE_PATH])
	if not FileAccess.file_exists(MANIFEST_PATH):
		return paths
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return paths
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return paths
	var manifest := parsed as Dictionary
	var topology_value = manifest.get("topology", null)
	if topology_value is Dictionary:
		var collision_value = (topology_value as Dictionary).get("collision_source", null)
		if collision_value is Dictionary:
			_append_source_path(paths, str((collision_value as Dictionary).get("path", "")))
		if str((topology_value as Dictionary).get("mode", "")) == L05_TOPOLOGY_MODE:
			paths.append(L05_SOLID_MASK_PATH)
			paths.append(L05_SHADER_PATH)
	var visual_value = manifest.get("visual", null)
	if visual_value is Dictionary:
		var assets_value = (visual_value as Dictionary).get("assets", null)
		if assets_value is Array:
			for asset_value in assets_value as Array:
				if asset_value is Dictionary:
					_append_source_path(paths, str((asset_value as Dictionary).get("path", "")))
	return paths


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


func navigation_base_raster() -> Dictionary:
	var source := _load_source()
	var errors: PackedStringArray = source.get("errors", PackedStringArray())
	if not errors.is_empty():
		return {"errors": errors}
	if not _cached_navigation_raster.is_empty():
		return _duplicate_raster(_cached_navigation_raster)
	var manifest: Dictionary = source.get("manifest", {})
	var map_record: Dictionary = manifest.get("map", {})
	var topology: Dictionary = manifest.get("topology", {})
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
	if topology_mode == "open_world":
		var world_extent := _json_vector(map_record.get("world_size", []))
		grid_extent = Vector2i(
			roundi(world_extent.x / cell_extent.x),
			roundi(world_extent.y / cell_extent.y)
		)
		cells.resize(grid_extent.x * grid_extent.y)
		cells.fill(1)
	else:
		var topology_errors := PackedStringArray()
		var decoded := _decode_l05_collision_source(topology, topology_errors)
		if not topology_errors.is_empty():
			return {"errors": topology_errors}
		grid_extent = L05_PIXEL_SIZE
		cell_extent = L05_WORLD_UNITS_PER_PIXEL
		var encoded_cells: PackedByteArray = decoded.get("cells", PackedByteArray())
		var solid_value := int(decoded.get("solid", 0))
		cells.resize(encoded_cells.size())
		for index in range(encoded_cells.size()):
			cells[index] = 0 if int(encoded_cells[index]) == solid_value else 1
	_cached_navigation_raster = {
		"errors": PackedStringArray(),
		"width": grid_extent.x,
		"height": grid_extent.y,
		"cell_scale": cell_extent,
		"cells": cells,
	}
	return _duplicate_raster(_cached_navigation_raster)


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
			"macro_raster": navigation_base_raster(),
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
		"macro_raster": navigation_base_raster(),
	}


func _load_source() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {"errors": PackedStringArray(["Brak jedynego manifestu mapy: %s." % MANIFEST_PATH])}
	var manifest_hash := FileAccess.get_sha256(MANIFEST_PATH).to_lower()
	if manifest_hash.is_empty():
		return {"errors": PackedStringArray(["Nie można policzyć SHA-256 manifestu mapy."])}
	if manifest_hash == _cached_manifest_hash and not _cached_manifest.is_empty():
		var cached_manifest_errors := _manifest_validation_errors(_cached_manifest)
		if not cached_manifest_errors.is_empty():
			return {"errors": cached_manifest_errors}
		var cached_scene_errors := _generated_scene_errors(
			_cached_manifest,
			manifest_hash,
			_cached_gameplay_signature,
			_cached_presentation_fingerprint
		)
		if not cached_scene_errors.is_empty():
			return {"errors": cached_scene_errors}
		return {
			"errors": PackedStringArray(),
			"manifest": _cached_manifest.duplicate(true),
			"manifest_sha256": manifest_hash,
			"gameplay_signature": _cached_gameplay_signature,
			"presentation_fingerprint": _cached_presentation_fingerprint,
		}
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return {"errors": PackedStringArray(["Nie można otworzyć manifestu mapy."])}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"errors": PackedStringArray(["Manifest mapy nie jest poprawnym obiektem JSON."])}
	var manifest := parsed as Dictionary
	var errors := _manifest_validation_errors(manifest)
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
	if manifest_hash != _cached_manifest_hash:
		_cached_manifest_hash = manifest_hash
		_cached_manifest = manifest.duplicate(true)
		_cached_gameplay_signature = gameplay_signature
		_cached_presentation_fingerprint = presentation_fingerprint
		_cached_blueprints.clear()
		_cached_navigation_raster.clear()
	return {
		"errors": PackedStringArray(),
		"manifest": manifest.duplicate(true),
		"manifest_sha256": manifest_hash,
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
	if str(expected_topology.get("mode", "")) == L05_TOPOLOGY_MODE:
		var expected_collision: Dictionary = expected_topology.get("collision_source", {})
		if str(root.get_meta("payload_sha256", "")).to_lower() != str(expected_collision.get("sha256", "")):
			errors.append("Scena mapy ma nieaktualny payload_sha256 L05.")
		if str(root.get_meta("canonical_digest", "")) != str(expected_collision.get("canonical_digest", "")):
			errors.append("Scena mapy ma nieaktualny canonical_digest L05.")
		errors.append_array(_generated_l05_mask_errors(expected_topology))
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
	var visual_layers := root.get_node_or_null("VisualLayers") as Node2D
	if visual_layers == null:
		errors.append("Scena mapy nie zawiera VisualLayers.")
	else:
		var expected_visual: Dictionary = expected_manifest.get("visual", {})
		var expected_layers: Array = expected_visual.get("layers", [])
		errors.append_array(_generated_visual_layer_errors(visual_layers, expected_layers))
	root.free()
	return errors


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

	_validate_topology(
		topology_value as Dictionary,
		world_size,
		navigation_cell_size,
		errors
	)
	_validate_visual(
		visual_value as Dictionary,
		world_size,
		topology_value as Dictionary,
		errors
	)

	var gameplay := gameplay_value as Dictionary
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
			if gameplay_key != "connections" and not _point_inside_world(_json_vector(record.get("position", null)), world_size):
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
		blueprint.fixed_device_spawns.append(_spatial_gameplay_record(source as Dictionary))
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
		"gameplay": _gameplay_semantic_projection(manifest.get("gameplay", {}) as Dictionary),
		"campaign": (manifest.get("campaign", {}) as Dictionary).duplicate(true),
	}
	var revision: Dictionary = manifest.get("revision", {})
	var map_record: Dictionary = manifest.get("map", {})
	var presentation_payload := {
		"presentation_revision": revision.get("presentation_revision", ""),
		"map": {
			"grid": (map_record.get("grid", {}) as Dictionary).duplicate(true),
			"world_size": (map_record.get("world_size", []) as Array).duplicate(true),
		},
		"regions": (manifest.get("regions", []) as Array).duplicate(true),
		"landmarks": (manifest.get("landmarks", []) as Array).duplicate(true),
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
		if node is Parallax2D and (node as Parallax2D).scroll_scale != expected_scale:
			errors.append("Warstwa %s sceny ma nieaktualny scroll_scale." % layer_id)
		if layer_id == RESERVED_VISUAL_LAYER_ID and node.get_child_count() != 0:
			errors.append("Zarezerwowana warstwa L10 sceny musi pozostać pusta.")
	return errors


func _validate_visual(
	visual: Dictionary,
	world_size: Vector2,
	topology: Dictionary,
	errors: PackedStringArray
) -> void:
	for color_key in ["water_color", "deep_water_color", "grid_color", "border_color", "station_color"]:
		if not _valid_json_color(visual.get(color_key, null)):
			errors.append("visual.%s musi być kolorem RGB/RGBA hex." % color_key)
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
		"affordance_policy", "geometry_role",
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
		if layer_id == COLLIDER_AUTHORITY_LAYER_ID:
			if str(layer.get("role", "")) != "collider_authority":
				errors.append("L05 musi mieć role=collider_authority.")
			if str(layer.get("geometry_role", "")) != "collider_authority":
				errors.append("L05 musi być jedynym geometry_role=collider_authority.")
			if str(layer.get("affordance_policy", "")) != "collider_authority":
				errors.append("L05 musi używać affordance_policy=collider_authority.")
			if not bool(layer.get("enabled", false)) or bool(layer.get("reserved", true)):
				errors.append("L05 musi być włączone i niezarezerwowane.")
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
	for index in range(assets.size()):
		var asset := assets[index]
		var label := "visual.assets[%d]" % index
		if not _dictionary_has_exact_keys(asset, VISUAL_ASSET_KEYS):
			errors.append("%s musi zawierać wyłącznie pełny kontrakt typowanego assetu." % label)
		var asset_id_value = asset.get("id", null)
		var asset_id := str(asset_id_value).strip_edges()
		if not asset_id_value is String or asset_id.is_empty() or asset_ids.has(asset_id):
			errors.append("visual.assets wymaga niepustych, unikalnych ID.")
		else:
			asset_ids[asset_id] = true
		var layer_id_value = asset.get("layer_id", null)
		var layer_id := str(layer_id_value).strip_edges()
		var kind_value = asset.get("kind", null)
		var kind := str(kind_value).strip_edges()
		if (
			not layer_id_value is String
			or not kind_value is String
			or not [
				["L01", "texture_rect"],
				["L02", "texture_rect"],
				["L05", "collision_masked_material"],
			].has(
				[layer_id, kind]
			)
		):
			errors.append(
				"Asset %s musi być L01-L02/texture_rect albo L05/collision_masked_material."
				% asset_id
			)
		if typeof(asset.get("enabled", null)) != TYPE_BOOL:
			errors.append("Asset %s ma niepoprawne enabled." % asset_id)
		var affordance_value = asset.get("affordance", null)
		if not affordance_value is String or str(affordance_value).strip_edges().is_empty():
			errors.append("Asset %s wymaga niepustego affordance." % asset_id)
		_validate_hashed_png_asset(asset, label, errors)
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
			if (
				pixel_size.x > 0.0
				and pixel_size.y > 0.0
				and (
					pixel_size.x * world_rect.size.y
					!= pixel_size.y * world_rect.size.x
				)
			):
				errors.append(
					"Asset %s %s musi zachować dokładną proporcję pixel_size zgodną z world_rect."
					% [layer_id, asset_id]
				)
		elif layer_id == "L05":
			var collision_value = topology.get("collision_source", null)
			var expected_digest := ""
			if collision_value is Dictionary:
				expected_digest = str((collision_value as Dictionary).get("canonical_digest", ""))
			if str(topology.get("mode", "")) != L05_TOPOLOGY_MODE:
				errors.append("Asset L05 %s wymaga topology.mode=%s." % [asset_id, L05_TOPOLOGY_MODE])
			if str(topology_digest_value) != expected_digest:
				errors.append("Asset L05 %s musi wskazywać canonical_digest kolidera." % asset_id)
			if world_rect != Rect2(Vector2.ZERO, world_size):
				errors.append("Asset L05 %s musi pokrywać cały świat." % asset_id)
			if not ResourceLoader.exists(L05_SHADER_PATH):
				errors.append("Brak shadera maskującego grafikę L05.")


func _validate_topology(
	topology: Dictionary,
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
		collision_keys.append_array(["canonical_digest", "mapping"])
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
		_decode_l05_collision_source(topology, errors)

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


func _append_source_path(paths: PackedStringArray, package_path: String) -> void:
	var resource_path := _package_resource_path(package_path)
	if not resource_path.is_empty() and not paths.has(resource_path):
		paths.append(resource_path)


func _package_resource_path(package_path: String) -> String:
	var normalized := package_path.strip_edges()
	if normalized.is_empty() or not normalized.begins_with("assets/") or normalized.contains("\\"):
		return ""
	var parts := normalized.split("/", true)
	for part in parts:
		if part.is_empty() or part in [".", ".."]:
			return ""
	return "res://underwater_map_workbench/%s" % normalized


func _validate_hashed_png_asset(
	asset: Dictionary,
	label: String,
	errors: PackedStringArray
) -> void:
	var path_value = asset.get("path", null)
	if not path_value is String:
		errors.append("%s.path musi być Stringiem." % label)
		return
	var resource_path := _package_resource_path(str(path_value))
	if resource_path.is_empty():
		errors.append("%s.path musi pozostać lokalną ścieżką assets/... warsztatu." % label)
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
	errors: PackedStringArray
) -> Dictionary:
	var initial_error_count := errors.size()
	var collision_value = topology.get("collision_source", null)
	if not collision_value is Dictionary:
		errors.append("L05 wymaga obiektu topology.collision_source.")
		return {}
	var collision := collision_value as Dictionary
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
	if not _is_integral_number(payload.get("schema_version", null)) or int(payload.get("schema_version", 0)) != 1:
		errors.append("Payload L05 musi używać schema_version=1.")
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
	var operation_ids := {}
	for index in range((operations_value as Array).size()):
		var operation_value = (operations_value as Array)[index]
		var label := "L05 operations[%d]" % index
		if not operation_value is Dictionary:
			errors.append("%s musi być obiektem." % label)
			continue
		var operation := operation_value as Dictionary
		if not _dictionary_has_exact_keys(operation, ["id", "op", "rect_px"]):
			errors.append("%s musi zawierać wyłącznie id, op i rect_px." % label)
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
		if (
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
		for row in range(y, y + height):
			var start := row * L05_PIXEL_SIZE.x + x
			for cell_index in range(start, start + width):
				cells[cell_index] = fill_value
	if errors.size() > initial_error_count:
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
	return {
		"cells": cells,
		"solid": int(solid_value),
		"open_water": int(open_water_value),
		"payload_sha256": actual_sha,
		"canonical_digest": canonical_digest,
	}


func _generated_l05_mask_errors(topology: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var decoded := _decode_l05_collision_source(topology, errors)
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
	return errors


func _valid_topology_digest(value: String) -> bool:
	if not value.begins_with("topology-v1:"):
		return false
	return _valid_sha256(value.trim_prefix("topology-v1:"), false)


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


func _duplicate_raster(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	var cells: PackedByteArray = source.get("cells", PackedByteArray())
	result["cells"] = cells.duplicate()
	return result
