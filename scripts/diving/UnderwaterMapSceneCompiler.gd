class_name UnderwaterMapSceneCompiler
extends RefCounted

const WorldBlueprintScript := preload("res://scripts/data/WorldBlueprint.gd")
const WorldStateScript := preload("res://scripts/data/UnderwaterWorldState.gd")
const MapSceneScript := preload("res://scripts/diving/UnderwaterMapScene.gd")
const MapObjectScript := preload("res://scripts/diving/DiveMapObject.gd")
const MapConnectionScript := preload("res://scripts/diving/DiveMapConnection.gd")
const MapNavigationRasterScript := preload("res://scripts/diving/MapNavigationRaster.gd")
const TerrainDerivativesScript := preload("res://scripts/diving/DiveTerrainDerivatives.gd")

const MAP_SCENE_PATH := "res://scenes/diving/UnderwaterMap.tscn"
## Source version 4 remains stable because the Polygon2D cutover reproduces the
## established semantic cells exactly and changes neither blueprint data nor
## save meaning. Scene polygons are now the authority; the committed PNG is a
## validated rendering cache whose unchanged bytes preserve existing signatures.
const MAP_SOURCE_VERSION := 4
const STABLE_ID_ALLOWED_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-"
const REQUIRED_AUTHORING_NODES := [
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
const VISUAL_ONLY_SIGNATURE_FIELDS := [
	"display_name",
	"short_name",
	"label",
	"visual_kind",
	"accent_color",
	"water_color",
	"backdrop_path",
	"visual_scene_path",
	"scene_path",
	"visual_offset",
	"visual_rotation",
	"visual_scale",
	"visual_z_index",
	"visual_object_rotation",
	"visual_object_scale",
	"visual_object_skew",
	"authoring_kind",
]

## Navigation validation scans the complete collision image. Reuse its result
## while the gameplay signature is unchanged, including across short-lived
## compiler instances created by save/load checks.
static var _navigation_validation_by_signature: Dictionary = {}
static var _compiled_source_by_seed: Dictionary = {}
static var _compiled_source_fingerprint: String = ""
static var _source_dependency_paths := PackedStringArray([MAP_SCENE_PATH])
static var _visual_layers_template: Node2D
static var _navigation_texture_cache: Texture2D
static var _navigation_base_raster_cache: Dictionary = {}
static var _terrain_render_sdf_texture_cache: Texture2D
static var _terrain_detail_texture_cache: Texture2D
static var _terrain_visual_profiles_cache: Array[Resource] = []


static func clear_runtime_caches() -> void:
	if _visual_layers_template != null:
		_visual_layers_template.free()
	_visual_layers_template = null
	_navigation_texture_cache = null
	_navigation_base_raster_cache.clear()
	_terrain_render_sdf_texture_cache = null
	_terrain_detail_texture_cache = null
	_terrain_visual_profiles_cache.clear()
	_source_dependency_paths = PackedStringArray([MAP_SCENE_PATH])


func generate(world, campaign_seed: int) -> PackedStringArray:
	if world == null or world.get_script() != WorldStateScript:
		return PackedStringArray(["Kompilacja mapy wymaga UnderwaterWorldState."])
	var result := _compile_source_map(campaign_seed)
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	if not errors.is_empty():
		return errors
	var blueprint = result.get("blueprint")
	if blueprint == null or blueprint.get_script() != WorldBlueprintScript:
		return PackedStringArray(["Scena mapy nie wygenerowała poprawnego WorldBlueprint."])
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
		return PackedStringArray(["Kampania nie zawiera WorldBlueprint nowej mapy."])
	if int(world.blueprint.map_source_version) != MAP_SOURCE_VERSION:
		return PackedStringArray(["Zapis kampanii nie używa aktualnego źródła mapy."])
	if str(world.blueprint.map_id).is_empty():
		return PackedStringArray(["WorldBlueprint nie wskazuje mapy źródłowej."])
	var compilation := _compile_source_map(int(world.blueprint.campaign_seed))
	var compilation_errors: PackedStringArray = compilation.get("errors", PackedStringArray())
	if not compilation_errors.is_empty():
		return compilation_errors
	var current_blueprint = compilation.get("blueprint")
	if current_blueprint == null:
		return PackedStringArray(["Aktualna scena mapy nie zwróciła blueprintu."])
	if (
		str(current_blueprint.map_id) != str(world.blueprint.map_id)
		or str(current_blueprint.map_gameplay_signature) != str(world.blueprint.map_gameplay_signature)
	):
		return PackedStringArray(["Zapis kampanii nie odpowiada bieżącej scenie mapy."])
	# The scene remains the authority. The saved blueprint is only a runtime
	# cache and is replaced after its gameplay identity has been checked. This
	# intentionally allows presentation-only prefab changes between sessions.
	world.blueprint = current_blueprint
	if not world.blueprint.landmark_lookup.has(world.blueprint.entry_landmark_id):
		return PackedStringArray(["WorldBlueprint nie ma prawidłowego landmarku wejściowego."])
	if not world.delta.discovered_landmarks.has(world.blueprint.entry_landmark_id):
		world.delta.discovered_landmarks.append(world.blueprint.entry_landmark_id)
	return PackedStringArray()


func _compile_source_map(campaign_seed: int) -> Dictionary:
	var normalized_seed := maxi(campaign_seed, 1)
	var source_fingerprint := _source_dependency_fingerprint()
	if source_fingerprint != _compiled_source_fingerprint:
		clear_runtime_caches()
		_compiled_source_fingerprint = source_fingerprint
		_compiled_source_by_seed.clear()
	if _compiled_source_by_seed.has(normalized_seed):
		var cached_blueprint = _compiled_source_by_seed[normalized_seed]
		return {
			"errors": PackedStringArray(),
			"blueprint": cached_blueprint.duplicate(true),
		}
	var source_scene := ResourceLoader.load(MAP_SCENE_PATH) as PackedScene
	if source_scene == null:
		return {"errors": PackedStringArray(["Nie można załadować aktualnej sceny mapy."])}
	var source_root := source_scene.instantiate() as UnderwaterMapScene
	if source_root == null or source_root.get_script() != MapSceneScript:
		if source_root != null:
			source_root.free()
		return {"errors": PackedStringArray(["Scena mapy musi mieć skrypt UnderwaterMapScene."])}
	var compilation := compile_map(source_root, normalized_seed)
	var source_layers := source_root.get_node_or_null("VisualLayers") as Node2D
	if source_layers != null and _visual_layers_template == null:
		_visual_layers_template = source_layers.duplicate() as Node2D
	_navigation_texture_cache = source_root.navigation_grid_texture
	_navigation_base_raster_cache = (
		compilation.get("macro_raster", {}) as Dictionary
	).duplicate(true)
	_terrain_render_sdf_texture_cache = source_root.terrain_render_sdf_texture
	_terrain_detail_texture_cache = source_root.terrain_detail_texture
	_terrain_visual_profiles_cache.assign(source_root.terrain_visual_profiles)
	_cache_source_dependency_paths(source_root)
	_compiled_source_fingerprint = _source_dependency_fingerprint()
	source_root.free()
	var errors: PackedStringArray = compilation.get("errors", PackedStringArray())
	var blueprint = compilation.get("blueprint")
	if errors.is_empty() and blueprint != null:
		_compiled_source_by_seed[normalized_seed] = blueprint.duplicate(true)
	return compilation


static func _source_dependency_fingerprint() -> String:
	var payload := PackedStringArray()
	for dependency_path in _source_dependency_paths:
		if FileAccess.file_exists(dependency_path):
			payload.append("%s:%s" % [dependency_path, FileAccess.get_sha256(dependency_path).to_lower()])
		else:
			payload.append("%s:missing" % dependency_path)
	return "|".join(payload)


static func _cache_source_dependency_paths(source_root: UnderwaterMapScene) -> void:
	var dependencies := PackedStringArray([MAP_SCENE_PATH])
	if OS.has_feature("editor"):
		dependencies.append(TerrainDerivativesScript.NAVIGATION_MANIFEST_PATH)
		dependencies.append(TerrainDerivativesScript.SDF_MANIFEST_PATH)
	_append_resource_path(dependencies, source_root.navigation_grid_texture)
	_append_resource_path(dependencies, source_root.terrain_render_sdf_texture)
	_append_resource_path(dependencies, source_root.terrain_detail_texture)
	for profile in source_root.terrain_visual_profiles:
		_append_resource_path(dependencies, profile)
	dependencies.sort()
	_source_dependency_paths = dependencies


static func _append_resource_path(paths: PackedStringArray, resource: Resource) -> void:
	if resource == null or resource.resource_path.is_empty() or paths.has(resource.resource_path):
		return
	paths.append(resource.resource_path)


func compile_map(map_root: UnderwaterMapScene, campaign_seed: int = 1) -> Dictionary:
	var errors := PackedStringArray()
	if map_root == null:
		return {"errors": PackedStringArray(["Nie można skompilować pustej mapy."])}
	if map_root.map_id.strip_edges().is_empty():
		errors.append("Scena mapy wymaga stabilnego Map ID.")
	if map_root.navigation_grid_texture == null:
		errors.append("Scena mapy nie wskazuje pochodnego rastra nawigacji.")
	if not _is_sha256(map_root.navigation_cells_sha256):
		errors.append("Scena mapy nie zawiera poprawnego skrótu komórek makroterenu.")
	if not _is_sha256(map_root.navigation_signature_sha256):
		errors.append("Scena mapy nie zawiera poprawnego skrótu zgodności zapisu mapy.")
	if map_root.terrain_render_sdf_texture == null:
		errors.append("Scena mapy nie wskazuje prezentacyjnego SDF konturu terenu.")
	elif (
		map_root.navigation_grid_texture != null
		and map_root.terrain_render_sdf_texture.get_size() != map_root.navigation_grid_texture.get_size()
	):
		errors.append("Prezentacyjny SDF konturu musi mieć rozmiar zgodny z teksturą nawigacji.")
	if map_root.terrain_detail_texture == null:
		errors.append("Scena mapy nie wskazuje prezentacyjnego materiału skał.")
	if map_root.terrain_visual_profiles.size() != 4:
		errors.append("Scena mapy wymaga dokładnie czterech profili prezentacyjnych regionów.")
	else:
		for profile in map_root.terrain_visual_profiles:
			if profile == null:
				errors.append("Scena mapy zawiera pusty profil prezentacyjny regionu.")
				continue
			if profile.has_method("validation_errors"):
				for profile_error in profile.validation_errors():
					errors.append("Profil prezentacyjny regionu: %s" % profile_error)
	if map_root.world_size.x <= 0.0 or map_root.world_size.y <= 0.0:
		errors.append("Scena mapy ma nieprawidłowy rozmiar świata.")
	for required_path in REQUIRED_AUTHORING_NODES:
		if map_root.get_node_or_null(required_path) == null:
			errors.append("Scena mapy nie zawiera wymaganej grupy %s." % required_path)

	var macro_raster := TerrainDerivativesScript.rasterize_map(map_root)
	var macro_errors: PackedStringArray = macro_raster.get("errors", PackedStringArray())
	for macro_error in macro_errors:
		errors.append(macro_error)
	if macro_errors.is_empty():
		if str(macro_raster.get("cells_hash", "")) != map_root.navigation_cells_sha256:
			errors.append("Makroteren Polygon2D nie odpowiada zapisanemu skrótowi komórek.")
		if OS.has_feature("editor"):
			for derivative_error in TerrainDerivativesScript.validate_derivatives(map_root, macro_raster, false):
				errors.append(derivative_error)

	var objects: Array[DiveMapObject] = []
	var connections: Array[DiveMapConnection] = []
	for node in map_root.find_children("*", "", true, false):
		if node is DiveMapObject:
			objects.append(node as DiveMapObject)
		elif node is DiveMapConnection:
			connections.append(node as DiveMapConnection)
	objects.sort_custom(Callable(self, "_map_object_less"))
	connections.sort_custom(Callable(self, "_map_connection_less"))
	if objects.is_empty():
		errors.append("Scena mapy nie zawiera żadnych obiektów authoringu.")

	var object_ids: Dictionary = {}
	var region_ids: Dictionary = {}
	var landmark_ids: Dictionary = {}
	var landmark_nodes: Dictionary = {}
	var entry_count := 0
	var exit_count := 0
	var map_bounds := Rect2(Vector2.ZERO, map_root.world_size)
	for object in objects:
		_validate_stable_id(errors, object.object_id, "Object ID", object.name, object_ids)
		if object.kind == DiveMapObject.Kind.REGION and not object.object_id.is_empty():
			region_ids[object.object_id] = true
		if object.kind == DiveMapObject.Kind.LANDMARK and not object.object_id.is_empty():
			landmark_ids[object.object_id] = true
			landmark_nodes[object.object_id] = object
		if object.kind == DiveMapObject.Kind.ENTRY_POINT:
			entry_count += 1
		elif object.kind == DiveMapObject.Kind.EXIT_LINE:
			exit_count += 1
		if not _object_is_inside_map(object, map_bounds):
			errors.append("Obiekt %s (%s) wykracza poza granice mapy." % [object.name, object.object_id])
		_validate_object_authoring_group(errors, map_root, object)
		_append_object_validation_errors(errors, object)

	var connection_ids: Dictionary = {}
	for connection in connections:
		_validate_stable_id(errors, connection.connection_id, "Connection ID", connection.name, connection_ids)
		_validate_connection_authoring_group(errors, map_root, connection)
		if connection.from_landmark_id == connection.to_landmark_id and not connection.from_landmark_id.is_empty():
			errors.append("Połączenie %s nie może prowadzić z landmarku do niego samego." % connection.connection_id)
		var references_exist := (
			landmark_ids.has(connection.from_landmark_id)
			and landmark_ids.has(connection.to_landmark_id)
		)
		if not references_exist:
			errors.append("Połączenie %s wskazuje nieistniejący landmark." % connection.connection_id)
		if connection.curve != null and connection.curve.point_count == 1:
			errors.append("Połączenie %s ma niepełną Curve2D; usuń jedyny punkt albo dodaj drugi." % connection.connection_id)
		var route_points := connection.authored_world_points()
		if route_points.size() < 2:
			errors.append("Połączenie %s nie ma poprawnej trasy." % connection.connection_id)
		else:
			for route_point in route_points:
				if not _point_inside_map(route_point, map_bounds):
					errors.append("Połączenie %s wychodzi poza granice mapy." % connection.connection_id)
					break
			if references_exist:
				var from_position: Vector2 = (landmark_nodes[connection.from_landmark_id] as DiveMapObject).global_position
				var to_position: Vector2 = (landmark_nodes[connection.to_landmark_id] as DiveMapObject).global_position
				var endpoint_tolerance := maxf(connection.width * 0.5, 48.0)
				if route_points[0].distance_to(from_position) > endpoint_tolerance:
					errors.append("Trasa %s nie zaczyna się przy landmarku %s." % [connection.connection_id, connection.from_landmark_id])
				if route_points[route_points.size() - 1].distance_to(to_position) > endpoint_tolerance:
					errors.append("Trasa %s nie kończy się przy landmarku %s." % [connection.connection_id, connection.to_landmark_id])

	for object in objects:
		if object.kind == DiveMapObject.Kind.LANDMARK:
			if object.region_id.is_empty() or not region_ids.has(object.region_id):
				errors.append("Landmark %s musi wskazywać istniejący Region ID." % object.object_id)
		elif object.kind in [DiveMapObject.Kind.ENTRY_POINT, DiveMapObject.Kind.BUOY]:
			if object.linked_object_id.is_empty() or not landmark_ids.has(object.linked_object_id):
				errors.append("Obiekt %s musi wskazywać landmark przez Linked Object ID." % object.object_id)
		elif object.kind == DiveMapObject.Kind.SHORTCUT_GATE:
			if object.linked_object_id.is_empty() or not connection_ids.has(object.linked_object_id):
				errors.append("Brama %s musi wskazywać Connection ID." % object.object_id)
		elif object.kind in [DiveMapObject.Kind.LOOT_CONTAINER, DiveMapObject.Kind.PICKUP]:
			if not object.linked_object_id.is_empty() and not landmark_ids.has(object.linked_object_id):
				errors.append("Źródło łupu %s wskazuje nieistniejący landmark." % object.object_id)
	if entry_count != 1:
		errors.append("Scena mapy musi mieć dokładnie jeden Entry Point.")
	if exit_count != 1:
		errors.append("Scena mapy musi mieć dokładnie jedną Exit Line.")
	if not errors.is_empty():
		return {"errors": errors}

	var blueprint := WorldBlueprintScript.new()
	blueprint.campaign_seed = maxi(campaign_seed, 1)
	blueprint.map_source_version = MAP_SOURCE_VERSION
	blueprint.map_id = map_root.map_id.strip_edges()
	blueprint.world_size = map_root.world_size
	blueprint.chunk_size = map_root.chunk_size
	for object in objects:
		_append_object(blueprint, object)
	for connection in connections:
		blueprint.connections.append(_compile_connection(blueprint, connection))
	blueprint.rebuild_indexes()
	_rebuild_chunk_index(blueprint)
	if blueprint.entry_landmark_id.is_empty():
		for landmark in blueprint.landmarks:
			if str(landmark.get("role", "")) == "entry":
				blueprint.entry_landmark_id = str(landmark.get("id", ""))
				blueprint.entry_position = landmark.get("position", Vector2.ZERO)
				break
	if blueprint.entry_landmark_id.is_empty() or not blueprint.landmark_lookup.has(blueprint.entry_landmark_id):
		return {"errors": PackedStringArray(["Scena mapy potrzebuje landmarku wejściowego lub Entry Point."])}
	if blueprint.exit_position == Vector2.ZERO:
		blueprint.exit_position = blueprint.entry_position
	blueprint.map_gameplay_signature = _gameplay_signature(
		blueprint,
		map_root.navigation_grid_texture,
		map_root.navigation_signature_sha256
	)

	var navigation_errors: PackedStringArray
	if _navigation_validation_by_signature.has(blueprint.map_gameplay_signature):
		navigation_errors = _navigation_validation_by_signature[blueprint.map_gameplay_signature].duplicate()
	else:
		navigation_errors = PackedStringArray()
		_append_navigation_validation_errors(navigation_errors, blueprint, macro_raster)
		_navigation_validation_by_signature[blueprint.map_gameplay_signature] = navigation_errors.duplicate()
	for navigation_error in navigation_errors:
		errors.append(navigation_error)
	if not errors.is_empty():
		return {"errors": errors}
	return {
		"errors": PackedStringArray(),
		"blueprint": blueprint,
		"macro_raster": macro_raster,
	}


func create_visual_layers() -> Node2D:
	if _visual_layers_template != null:
		return _visual_layers_template.duplicate() as Node2D
	var scene := ResourceLoader.load(MAP_SCENE_PATH, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	if scene == null:
		return null
	var map_root := scene.instantiate()
	if map_root == null:
		return null
	var source_layers := map_root.get_node_or_null("VisualLayers") as Node2D
	if source_layers == null:
		map_root.free()
		return null
	var copy := source_layers.duplicate()
	map_root.free()
	return copy as Node2D


func navigation_grid_texture() -> Texture2D:
	if _navigation_texture_cache != null:
		return _navigation_texture_cache
	var scene := ResourceLoader.load(MAP_SCENE_PATH, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	if scene == null:
		return null
	var map_root := scene.instantiate() as UnderwaterMapScene
	if map_root == null:
		return null
	var texture := map_root.navigation_grid_texture
	map_root.free()
	return texture


func navigation_base_raster() -> Dictionary:
	if not _navigation_base_raster_cache.is_empty():
		return _navigation_base_raster_cache.duplicate(true)
	var scene := ResourceLoader.load(MAP_SCENE_PATH, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	if scene == null:
		return {"errors": PackedStringArray(["Nie można załadować scenowego makroterenu."])}
	var map_root := scene.instantiate() as UnderwaterMapScene
	if map_root == null:
		return {"errors": PackedStringArray(["Scena mapy nie udostępnia makroterenu."])}
	var raster := TerrainDerivativesScript.rasterize_map(map_root)
	map_root.free()
	if (raster.get("errors", PackedStringArray()) as PackedStringArray).is_empty():
		_navigation_base_raster_cache = raster.duplicate(true)
	return raster


func terrain_detail_texture() -> Texture2D:
	if _terrain_detail_texture_cache != null:
		return _terrain_detail_texture_cache
	_cache_presentation_configuration()
	return _terrain_detail_texture_cache


func terrain_render_sdf_texture() -> Texture2D:
	if _terrain_render_sdf_texture_cache != null:
		return _terrain_render_sdf_texture_cache
	_cache_presentation_configuration()
	return _terrain_render_sdf_texture_cache


func terrain_visual_profiles() -> Array[Resource]:
	if _terrain_visual_profiles_cache.is_empty():
		_cache_presentation_configuration()
	return _terrain_visual_profiles_cache.duplicate()


func _cache_presentation_configuration() -> void:
	var scene := ResourceLoader.load(MAP_SCENE_PATH, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
	if scene == null:
		return
	var map_root := scene.instantiate() as UnderwaterMapScene
	if map_root == null:
		return
	_terrain_render_sdf_texture_cache = map_root.terrain_render_sdf_texture
	_terrain_detail_texture_cache = map_root.terrain_detail_texture
	_terrain_visual_profiles_cache.assign(map_root.terrain_visual_profiles)
	map_root.free()


func _append_object_validation_errors(errors: PackedStringArray, object: DiveMapObject) -> void:
	if object.display_name.strip_edges().is_empty():
		errors.append("Obiekt %s wymaga czytelnej Display Name." % object.object_id)
	if _uses_axis_aligned_bounds(object.kind) and absf(sin(object.global_rotation * 2.0)) > 0.001:
		errors.append("Obiekt %s używa osiowego Rect2 i może być obracany tylko o wielokrotność 90 stopni." % object.object_id)
	if _uses_axis_aligned_bounds(object.kind) and absf(object.global_skew) > 0.001:
		errors.append("Obiekt %s używa osiowego Rect2 i nie może mieć transformacji Skew." % object.object_id)
	match object.kind:
		DiveMapObject.Kind.REGION:
			if object.depth_range.x < 0.0 or object.depth_range.y < object.depth_range.x:
				errors.append("Region %s ma nieprawidłowy Depth Range." % object.object_id)
		DiveMapObject.Kind.LOOT_CONTAINER:
			if object.contents.is_empty():
				errors.append("Kontener %s nie ma zawartości." % object.object_id)
		DiveMapObject.Kind.PICKUP:
			if object.pickup_item == null or object.pickup_item.id.is_empty():
				errors.append("Pickup %s nie wskazuje poprawnego itemu." % object.object_id)
			elif object.pickup_amount != 1:
				errors.append("Pickup %s musi mieć dokładnie jedną sztukę; większe ilości umieść w kontenerze." % object.object_id)
		DiveMapObject.Kind.THREAT:
			if object.threat_definition == null or object.threat_definition.id.is_empty():
				errors.append("Zagrożenie %s nie wskazuje definicji." % object.object_id)
		DiveMapObject.Kind.RESCUE:
			if object.rescue_definition == null or object.rescue_definition.id.is_empty():
				errors.append("Ratunek %s nie wskazuje definicji." % object.object_id)
		DiveMapObject.Kind.FIXED_DEVICE:
			if object.device_role.strip_edges().is_empty():
				errors.append("Urządzenie %s wymaga stabilnej roli Device Role." % object.object_id)
		DiveMapObject.Kind.DECORATION:
			if object.visual_scene == null:
				errors.append("Dekoracja %s wymaga Visual Scene." % object.object_id)
	for visual_error in object.visual_scene_validation_errors():
		errors.append("Obiekt %s: %s" % [object.object_id, visual_error])


func _append_object(blueprint, object: DiveMapObject) -> void:
	var position := object.global_position
	match object.kind:
		DiveMapObject.Kind.REGION:
			blueprint.regions.append(_with_visual_fields({
				"id": object.object_id,
				"display_name": object.display_name,
				"bounds": object.authored_world_bounds(),
				"depth_range": object.depth_range,
				"accent_color": object.accent_color,
				"water_color": object.water_color,
				"backdrop_path": "",
			}, object))
		DiveMapObject.Kind.LANDMARK:
			blueprint.landmarks.append(_with_visual_fields({
				"id": object.object_id,
				"design_id": object.object_id,
				"display_name": object.display_name,
				"short_name": object.display_name,
				"region_id": object.region_id,
				"position": position,
				"size": object.authored_world_bounds().size,
				"visual_kind": object.visual_kind,
				"role": object.landmark_role,
				"aliases": Array(object.aliases),
				"anchor_id": object.anchor_id,
			}, object))
		DiveMapObject.Kind.ENTRY_POINT:
			blueprint.entry_position = position
			blueprint.entry_landmark_id = object.linked_object_id
			blueprint.decoration_spawns.append(_presentation_record(object))
		DiveMapObject.Kind.EXIT_LINE:
			blueprint.exit_position = position
			blueprint.decoration_spawns.append(_presentation_record(object))
		DiveMapObject.Kind.LOOT_CONTAINER:
			blueprint.loot_spawns.append(_with_visual_fields({
				"id": object.object_id,
				"display_name": object.display_name,
				"position": position,
				"landmark_id": object.linked_object_id,
				"contents": object.contents.duplicate(true),
				"mandatory_order": object.mandatory_order,
				"required_tool": object.required_tool,
				"interaction_action": object.interaction_action,
				"interaction_seconds": object.interaction_seconds,
				"difficulty_scaled_contents": object.difficulty_scaled_contents,
				"disease_id": object.disease_id,
				"disease_exposure_pressure": object.disease_exposure_pressure,
				"disease_source_kind": "dive",
				"disease_source_id": object.linked_object_id if not object.linked_object_id.is_empty() else object.object_id,
			}, object))
		DiveMapObject.Kind.PICKUP:
			blueprint.loot_spawns.append(_with_visual_fields({
				"spawn_kind": "pickup",
				"id": object.object_id,
				"display_name": object.display_name,
				"position": position,
				"landmark_id": object.linked_object_id,
				"contents": {object.pickup_item.id: object.pickup_amount},
				"mandatory_order": -1,
				"required_tool": object.required_tool,
				"interaction_action": "collect",
				"interaction_seconds": 0.0,
			}, object))
		DiveMapObject.Kind.CURRENT_ZONE:
			blueprint.current_zones.append(_with_visual_fields({
				"id": object.object_id,
				"rect": object.authored_world_bounds(),
				"position": position,
				"velocity": object.current_velocity,
				"label": object.display_name,
			}, object))
		DiveMapObject.Kind.THREAT:
			blueprint.threat_spawns.append(_with_visual_fields({
				"id": object.object_id,
				"definition_id": object.threat_definition.id,
				"position": position,
			}, object))
		DiveMapObject.Kind.HEAVY_OBJECT:
			blueprint.heavy_object_spawns.append(_with_visual_fields({
				"id": object.object_id,
				"display_name": object.display_name,
				"position": position,
				"rewards": object.contents.duplicate(true),
				"required_tool": object.required_tool,
				"interaction_action": object.interaction_action,
				"interaction_seconds": object.interaction_seconds,
			}, object))
		DiveMapObject.Kind.RESCUE:
			blueprint.rescue_spawns.append(_with_visual_fields({
				"id": object.object_id,
				"definition_id": object.rescue_definition.id,
				"position": position,
				"required_tool": object.required_tool,
				"interaction_action": object.interaction_action,
				"interaction_seconds": object.interaction_seconds,
			}, object))
		DiveMapObject.Kind.BUOY:
			blueprint.buoy_spawns.append(_with_visual_fields({
				"id": object.object_id,
				"display_name": object.display_name,
				"position": position,
				"entry_landmark_id": object.linked_object_id,
				"required_tool": object.required_tool,
				"interaction_action": object.interaction_action,
				"interaction_seconds": object.interaction_seconds,
			}, object))
		DiveMapObject.Kind.SHORTCUT_GATE:
			blueprint.shortcut_spawns.append(_with_visual_fields({
				"id": object.object_id,
				"connection_id": object.linked_object_id,
				"display_name": object.display_name,
				"position": position,
				"rotation": object.global_rotation,
				"width": object.gate_width,
				"required_tool": object.required_tool,
				"interaction_action": object.interaction_action,
				"interaction_seconds": object.interaction_seconds,
			}, object))
		DiveMapObject.Kind.FIXED_DEVICE:
			blueprint.fixed_device_spawns.append(_with_visual_fields({
				"id": object.object_id,
				"display_name": object.display_name,
				"position": position,
				"landmark_id": object.linked_object_id,
				"device_role": object.device_role,
				"available_from_day": object.available_from_day,
				"required_tool": object.required_tool,
				"interaction_action": object.interaction_action,
				"interaction_seconds": object.interaction_seconds,
			}, object))
		DiveMapObject.Kind.OBSTACLE:
			blueprint.obstacle_spawns.append(_spatial_record(object, true))
		DiveMapObject.Kind.DECORATION:
			blueprint.decoration_spawns.append(_spatial_record(object, false))


func _with_visual_fields(record: Dictionary, object: DiveMapObject) -> Dictionary:
	record["authoring_kind"] = object.kind_id()
	record.merge(object.visual_record_fields(), true)
	return record


func _presentation_record(object: DiveMapObject) -> Dictionary:
	return _with_visual_fields({
		"id": object.object_id,
		"display_name": object.display_name,
		"position": object.global_position,
	}, object)


func _spatial_record(object: DiveMapObject, include_navigation_polygon: bool) -> Dictionary:
	var record := {
		"id": object.object_id,
		"display_name": object.display_name,
		"position": object.global_position,
		"rotation": object.global_rotation,
		"object_scale": object.global_scale,
		"skew": object.global_skew,
		"size": object.bounds_size,
		"blocks_navigation": object.blocks_navigation if include_navigation_polygon else false,
	}
	if include_navigation_polygon:
		record["navigation_polygon"] = object.authored_world_polygon()
	return _with_visual_fields(record, object)


func _compile_connection(blueprint, connection: DiveMapConnection) -> Dictionary:
	var points := connection.authored_world_points()
	if points.size() < 2:
		var from: Vector2 = _landmark_position(blueprint, connection.from_landmark_id)
		var to: Vector2 = _landmark_position(blueprint, connection.to_landmark_id)
		var direction := to - from
		var bend := direction.normalized().orthogonal() * minf(direction.length() * 0.08, 260.0)
		points = PackedVector2Array([from, (from + to) * 0.5 + bend, to])
	return {
		"id": connection.connection_id,
		"display_name": connection.display_name,
		"from_id": connection.from_landmark_id,
		"to_id": connection.to_landmark_id,
		"type": connection.kind_id(),
		"width": connection.width,
		"path_points": points,
	}


func _landmark_position(blueprint, landmark_id: String) -> Vector2:
	var landmark: Dictionary = blueprint.get_landmark(landmark_id)
	return landmark.get("position", Vector2.ZERO)


func _rebuild_chunk_index(blueprint) -> void:
	blueprint.chunk_index.clear()
	for landmark in blueprint.landmarks:
		var landmark_size: Vector2 = landmark.get("size", Vector2.ONE)
		_index_rect(
			blueprint,
			Rect2(landmark.get("position", Vector2.ZERO) - landmark_size * 0.65, landmark_size * 1.3),
			"landmarks",
			str(landmark.get("id", ""))
		)
	for connection in blueprint.connections:
		var points: PackedVector2Array = connection.get("path_points", PackedVector2Array())
		var width := float(connection.get("width", 160.0))
		for index in range(maxi(points.size() - 1, 0)):
			_index_rect(
				blueprint,
				Rect2(points[index], Vector2.ZERO).expand(points[index + 1]).grow(width),
				"connections",
				str(connection.get("id", ""))
			)


func _index_rect(blueprint, rect: Rect2, category: String, object_id: String) -> void:
	var from: Vector2i = blueprint.chunk_coord_at(rect.position)
	var to: Vector2i = blueprint.chunk_coord_at(rect.end)
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var key: String = blueprint.chunk_key(Vector2i(x, y))
			var entry: Dictionary = blueprint.chunk_index.get(key, {"landmarks": [], "connections": []})
			var ids: Array = entry.get(category, [])
			if not ids.has(object_id):
				ids.append(object_id)
			entry[category] = ids
			blueprint.chunk_index[key] = entry


func _gameplay_signature(
	blueprint,
	navigation_texture: Texture2D,
	navigation_signature_sha256: String
) -> String:
	var payload: Array[String] = []
	payload.append("map=%s" % blueprint.map_id)
	payload.append("world=%s" % var_to_str(blueprint.world_size))
	payload.append("chunk=%s" % var_to_str(blueprint.chunk_size))
	payload.append("entry=%s:%s" % [blueprint.entry_landmark_id, var_to_str(blueprint.entry_position)])
	payload.append("exit=%s" % var_to_str(blueprint.exit_position))
	_append_signature_records(payload, "region", blueprint.regions)
	_append_signature_records(payload, "landmark", blueprint.landmarks)
	_append_signature_records(payload, "connection", blueprint.connections)
	_append_signature_records(payload, "loot", blueprint.loot_spawns)
	_append_signature_records(payload, "current", blueprint.current_zones)
	_append_signature_records(payload, "threat", blueprint.threat_spawns)
	_append_signature_records(payload, "heavy", blueprint.heavy_object_spawns)
	_append_signature_records(payload, "rescue", blueprint.rescue_spawns)
	_append_signature_records(payload, "buoy", blueprint.buoy_spawns)
	_append_signature_records(payload, "shortcut", blueprint.shortcut_spawns)
	_append_signature_records(payload, "fixed_device", blueprint.fixed_device_spawns)
	_append_signature_records(payload, "obstacle", blueprint.obstacle_spawns)
	if navigation_texture != null and not navigation_texture.resource_path.is_empty():
		payload.append("navigation_path=%s" % navigation_texture.resource_path)
		payload.append("navigation_hash=%s" % navigation_signature_sha256)
	payload.sort()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update("\n".join(payload).to_utf8_buffer())
	return context.finish().hex_encode()


static func _is_sha256(value: String) -> bool:
	return value.length() == 64 and value.is_valid_hex_number(false)


func _append_signature_records(target: Array[String], category: String, records: Array) -> void:
	var sorted_records: Array[String] = []
	for record_value in records:
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var gameplay_record := record.duplicate(true)
		for field_name in VISUAL_ONLY_SIGNATURE_FIELDS:
			gameplay_record.erase(field_name)
		sorted_records.append("%s:%s:%s" % [category, str(record.get("id", "")), var_to_str(gameplay_record)])
	sorted_records.sort()
	target.append_array(sorted_records)


func _append_navigation_validation_errors(
	errors: PackedStringArray,
	blueprint,
	macro_raster: Dictionary
) -> void:
	var base_cells: PackedByteArray = macro_raster.get("cells", PackedByteArray())
	var width := int(macro_raster.get("width", 0))
	var height := int(macro_raster.get("height", 0))
	if base_cells.is_empty() or width <= 0 or height <= 0:
		return
	var raster: Dictionary = MapNavigationRasterScript.build_from_cells_cached(
		str(blueprint.map_gameplay_signature),
		base_cells,
		width,
		height,
		blueprint.world_size,
		blueprint.obstacle_spawns,
		blueprint.chunk_size
	)
	var raster_errors: PackedStringArray = raster.get("errors", PackedStringArray())
	for raster_error in raster_errors:
		errors.append(raster_error)
	if not raster_errors.is_empty():
		return
	var cells: PackedByteArray = raster.get("cells", PackedByteArray())
	width = int(raster.get("width", 0))
	height = int(raster.get("height", 0))
	var cell_scale: Vector2 = raster.get("cell_scale", Vector2.ONE)

	var targets: Array[Dictionary] = [
		{"label": "punkt wejścia", "position": blueprint.entry_position},
		{"label": "linia wyjścia", "position": blueprint.exit_position},
	]
	for spawn in blueprint.loot_spawns:
		targets.append({
			"label": "źródło łupu %s" % str(spawn.get("id", "")),
			"position": spawn.get("position", Vector2.ZERO),
		})
	for spawn in blueprint.heavy_object_spawns:
		targets.append({"label": "ciężki obiekt %s" % str(spawn.get("id", "")), "position": spawn.get("position", Vector2.ZERO)})
	for spawn in blueprint.rescue_spawns:
		targets.append({"label": "cel ratunkowy %s" % str(spawn.get("id", "")), "position": spawn.get("position", Vector2.ZERO)})
	for spawn in blueprint.buoy_spawns:
		targets.append({"label": "boja %s" % str(spawn.get("id", "")), "position": spawn.get("position", Vector2.ZERO)})
	for spawn in blueprint.shortcut_spawns:
		targets.append({"label": "brama %s" % str(spawn.get("id", "")), "position": spawn.get("position", Vector2.ZERO)})
	for spawn in blueprint.fixed_device_spawns:
		targets.append({"label": "urządzenie %s" % str(spawn.get("id", "")), "position": spawn.get("position", Vector2.ZERO)})
	for spawn in blueprint.threat_spawns:
		targets.append({"label": "zagrożenie %s" % str(spawn.get("id", "")), "position": spawn.get("position", Vector2.ZERO)})

	var map_bounds := Rect2(Vector2.ZERO, blueprint.world_size)
	var entry_cell := MapNavigationRasterScript.cell_at(blueprint.entry_position, cell_scale)
	if (
		not _point_inside_map(blueprint.entry_position, map_bounds)
		or not MapNavigationRasterScript.cell_is_open(cells, width, height, entry_cell)
	):
		errors.append("Punkt wejścia musi leżeć w przechodnim obszarze mapy.")
		return
	var reachable := MapNavigationRasterScript.reachable_cells(cells, width, height, entry_cell)
	for target in targets:
		var label := str(target.get("label", "obiekt"))
		var position: Vector2 = target.get("position", Vector2.ZERO)
		if not _point_inside_map(position, map_bounds):
			errors.append("%s leży poza granicami mapy." % label.capitalize())
			continue
		var cell := MapNavigationRasterScript.cell_at(position, cell_scale)
		if not MapNavigationRasterScript.cell_is_open(cells, width, height, cell):
			errors.append("%s nie leży na przechodniej komórce nawigacji." % label.capitalize())
			continue
		var index := cell.y * width + cell.x
		if index < 0 or index >= reachable.size() or reachable[index] == 0:
			errors.append("%s nie ma przechodniej drogi od punktu wejścia." % label.capitalize())


func _validate_stable_id(
	errors: PackedStringArray,
	value: String,
	label: String,
	node_name: String,
	namespace_ids: Dictionary
) -> void:
	var stable_id := value.strip_edges()
	if stable_id.is_empty():
		errors.append("%s w węźle %s jest puste." % [label, node_name])
		return
	if not _is_valid_stable_id(stable_id):
		errors.append("%s %s zawiera niedozwolone znaki." % [label, stable_id])
	if namespace_ids.has(stable_id):
		errors.append("Powielony identyfikator mapy: %s." % stable_id)
		return
	namespace_ids[stable_id] = true


func _is_valid_stable_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in range(value.length()):
		if STABLE_ID_ALLOWED_CHARS.find(value.substr(index, 1)) < 0:
			return false
	return true


func _object_is_inside_map(object: DiveMapObject, map_bounds: Rect2) -> bool:
	if _uses_authored_bounds(object.kind):
		return _rect_inside_map(object.authored_world_bounds(), map_bounds)
	return _point_inside_map(object.global_position, map_bounds)


func _uses_authored_bounds(kind: int) -> bool:
	return kind in [
		DiveMapObject.Kind.REGION,
		DiveMapObject.Kind.LANDMARK,
		DiveMapObject.Kind.CURRENT_ZONE,
		DiveMapObject.Kind.OBSTACLE,
	]


func _uses_axis_aligned_bounds(kind: int) -> bool:
	return kind in [
		DiveMapObject.Kind.REGION,
		DiveMapObject.Kind.LANDMARK,
		DiveMapObject.Kind.CURRENT_ZONE,
	]


func _rect_inside_map(inner: Rect2, outer: Rect2) -> bool:
	const EPSILON := 0.01
	return (
		inner.position.x >= outer.position.x - EPSILON
		and inner.position.y >= outer.position.y - EPSILON
		and inner.end.x <= outer.end.x + EPSILON
		and inner.end.y <= outer.end.y + EPSILON
	)


func _point_inside_map(point: Vector2, bounds: Rect2) -> bool:
	const EPSILON := 0.01
	return (
		point.x >= bounds.position.x - EPSILON
		and point.y >= bounds.position.y - EPSILON
		and point.x <= bounds.end.x + EPSILON
		and point.y <= bounds.end.y + EPSILON
	)


func _validate_object_authoring_group(
	errors: PackedStringArray,
	map_root: UnderwaterMapScene,
	object: DiveMapObject
) -> void:
	var expected_path := _authoring_path_for_kind(object.kind)
	if expected_path.is_empty():
		return
	var expected_root := map_root.get_node_or_null(expected_path)
	if expected_root == null:
		return
	if object != expected_root and not expected_root.is_ancestor_of(object):
		errors.append(
			"Obiekt %s (%s) musi znajdować się w grupie %s."
			% [object.name, object.object_id, expected_path]
		)


func _validate_connection_authoring_group(
	errors: PackedStringArray,
	map_root: UnderwaterMapScene,
	connection: DiveMapConnection
) -> void:
	var routes_root := map_root.get_node_or_null("Routes")
	if routes_root != null and connection != routes_root and not routes_root.is_ancestor_of(connection):
		errors.append(
			"Połączenie %s (%s) musi znajdować się w grupie Routes."
			% [connection.name, connection.connection_id]
		)


func _authoring_path_for_kind(kind: int) -> String:
	match kind:
		DiveMapObject.Kind.REGION:
			return "DepthRegions"
		DiveMapObject.Kind.LANDMARK:
			return "Landmarks"
		DiveMapObject.Kind.ENTRY_POINT, DiveMapObject.Kind.EXIT_LINE:
			return "Entries"
		DiveMapObject.Kind.CURRENT_ZONE:
			return "CurrentZones"
		DiveMapObject.Kind.LOOT_CONTAINER:
			return "Gameplay/Containers"
		DiveMapObject.Kind.PICKUP:
			return "Gameplay/Pickups"
		DiveMapObject.Kind.THREAT:
			return "Gameplay/Threats"
		DiveMapObject.Kind.HEAVY_OBJECT:
			return "Gameplay/HeavyObjects"
		DiveMapObject.Kind.RESCUE:
			return "Gameplay/RescueEncounters"
		DiveMapObject.Kind.BUOY:
			return "Gameplay/BuoyAnchors"
		DiveMapObject.Kind.SHORTCUT_GATE:
			return "Gameplay/ShortcutGates"
		DiveMapObject.Kind.FIXED_DEVICE:
			return "Gameplay/FixedDevices"
		DiveMapObject.Kind.OBSTACLE:
			return "StaticObstacles"
		DiveMapObject.Kind.DECORATION:
			return "Decorations"
	return ""


func _map_object_less(left: DiveMapObject, right: DiveMapObject) -> bool:
	return _map_object_sort_key(left) < _map_object_sort_key(right)


func _map_object_sort_key(object: DiveMapObject) -> String:
	return "%02d:%s:%s" % [int(object.kind), object.object_id, object.name]


func _map_connection_less(left: DiveMapConnection, right: DiveMapConnection) -> bool:
	var left_key := "%s:%s" % [left.connection_id, left.name]
	var right_key := "%s:%s" % [right.connection_id, right.name]
	return left_key < right_key
