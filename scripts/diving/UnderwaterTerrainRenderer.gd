class_name UnderwaterTerrainRenderer
extends Node2D

const WATER_SHADER: Shader = preload("res://assets/diving/world/shaders/underwater_water.gdshader")
const BACKDROP_SHADER: Shader = preload("res://assets/diving/world/shaders/underwater_biome_backdrop.gdshader")
const TERRAIN_SHADER: Shader = preload("res://assets/diving/world/shaders/underwater_terrain.gdshader")
const QUALITY_IDS: Array[String] = ["low", "medium", "high"]
const REQUIRED_PROFILE_COUNT := 4
const GLOBAL_MATERIAL_KEY := "global_depth_profile"

@export_group("Shared semantic source")
@export var contour_mask: Texture2D
@export var contour_sdf: Texture2D
@export var rock_detail_texture: Texture2D
@export var world_size: Vector2 = Vector2(11_520.0, 6_480.0)
@export_range(64, 2048, 1) var chunk_size: int = 512

@export_group("Region presentation")
@export var region_profiles: Array[UnderwaterRegionVisualProfile] = []

@export_group("Layering")
@export var water_z_index: int = -100
@export var backdrop_z_index: int = -95
@export var terrain_z_index: int = -20

@export_group("Animation")
@export var auto_advance_animation: bool = true:
	set(value):
		auto_advance_animation = value
		if is_inside_tree():
			set_process(auto_advance_animation)

var _active_chunk_keys: Array[String] = []
var _global_water: Polygon2D
var _global_backdrop: Polygon2D
var _global_terrain: Sprite2D
var _water_materials: Dictionary = {}
var _backdrop_materials: Dictionary = {}
var _terrain_materials: Dictionary = {}
var _graphics_quality: String = "high"
var _reduced_motion: bool = false
var _anim_time: float = 0.0
var _water_parent: Node2D
var _backdrop_parent: Node2D
var _terrain_parent: Node2D


func _ready() -> void:
	set_process(auto_advance_animation)


func _process(delta: float) -> void:
	advance_animation(delta)


func configure_layer_roots(
	water_parent: Node2D,
	backdrop_parent: Node2D,
	terrain_parent: Node2D
) -> void:
	if (
		_water_parent == water_parent
		and _backdrop_parent == backdrop_parent
		and _terrain_parent == terrain_parent
	):
		return
	clear_visuals()
	_water_parent = water_parent
	_backdrop_parent = backdrop_parent
	_terrain_parent = terrain_parent


func set_active_chunks(chunk_keys: Array[String]) -> void:
	var requested: Array[String] = []
	var requested_lookup := {}
	for chunk_key in chunk_keys:
		var coordinates := _parse_chunk_key(chunk_key)
		if not _is_chunk_in_bounds(coordinates):
			continue
		var normalized_key := _chunk_key(coordinates)
		if requested_lookup.has(normalized_key):
			continue
		requested_lookup[normalized_key] = true
		requested.append(normalized_key)
	requested.sort()
	_active_chunk_keys = requested
	_ensure_global_water()
	_ensure_global_backdrop()
	_ensure_global_terrain()


func rebuild_visuals() -> void:
	if _global_water != null and is_instance_valid(_global_water):
		_global_water.queue_free()
	_global_water = null
	if _global_backdrop != null and is_instance_valid(_global_backdrop):
		_global_backdrop.queue_free()
	_global_backdrop = null
	if _global_terrain != null and is_instance_valid(_global_terrain):
		_global_terrain.queue_free()
	_global_terrain = null
	_water_materials.clear()
	_backdrop_materials.clear()
	_terrain_materials.clear()
	var requested: Array[String] = []
	requested.assign(_active_chunk_keys)
	_active_chunk_keys.clear()
	set_active_chunks(requested)


func clear_visuals() -> void:
	_active_chunk_keys.clear()
	if _global_water != null and is_instance_valid(_global_water):
		_global_water.queue_free()
	_global_water = null
	if _global_backdrop != null and is_instance_valid(_global_backdrop):
		_global_backdrop.queue_free()
	_global_backdrop = null
	if _global_terrain != null and is_instance_valid(_global_terrain):
		_global_terrain.queue_free()
	_global_terrain = null
	_water_materials.clear()
	_backdrop_materials.clear()
	_terrain_materials.clear()


func set_graphics_quality(quality_id: String) -> void:
	_graphics_quality = quality_id if QUALITY_IDS.has(quality_id) else "high"
	_refresh_dynamic_material_parameters()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_refresh_dynamic_material_parameters()


func set_anim_time(value: float) -> void:
	if not is_finite(value):
		return
	_anim_time = maxf(value, 0.0)
	_refresh_animation_parameter()


func advance_animation(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_anim_time += delta
	_refresh_animation_parameter()


func active_chunk_keys() -> Array[String]:
	var result: Array[String] = []
	result.assign(_active_chunk_keys)
	return result


func presentation_state() -> Dictionary:
	return {
		"active_chunk_count": _active_chunk_keys.size(),
		"active_chunk_keys": active_chunk_keys(),
		"graphics_quality": _graphics_quality,
		"reduced_motion": _reduced_motion,
		"anim_time": _anim_time,
		"uses_shared_contour_mask": contour_mask != null,
		"uses_derived_contour_sdf": contour_sdf != null,
		"uses_detail_texture": rock_detail_texture != null,
		"water_material_count": _water_materials.size(),
		"backdrop_material_count": _backdrop_materials.size(),
		"terrain_material_count": _terrain_materials.size(),
		"uses_global_depth_profiles": _water_materials.size() <= 1 and _backdrop_materials.size() <= 1 and _terrain_materials.size() <= 1,
		"uses_global_water_layer": _global_water != null and is_instance_valid(_global_water),
		"uses_global_backdrop_layer": _global_backdrop != null and is_instance_valid(_global_backdrop),
		"uses_global_terrain_layer": _global_terrain != null and is_instance_valid(_global_terrain),
		"backdrop_z_index": backdrop_z_index,
		"backdrop_quality_level": QUALITY_IDS.find(_graphics_quality),
		"backdrop_reduced_motion": _reduced_motion,
		"backdrop_anim_time": 0.0 if _reduced_motion else _anim_time,
		"water_parent": _node_path_or_empty(_water_parent),
		"backdrop_parent": _node_path_or_empty(_backdrop_parent),
		"terrain_parent": _node_path_or_empty(_terrain_parent),
	}


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if contour_mask == null:
		errors.append("Renderer terenu wymaga wspólnej tekstury contour_mask.")
	elif contour_mask.get_width() <= 0 or contour_mask.get_height() <= 0:
		errors.append("Wspólna tekstura contour_mask ma niepoprawny rozmiar.")
	if contour_sdf == null:
		errors.append("Renderer terenu wymaga prezentacyjnego contour_sdf.")
	elif contour_sdf.get_width() <= 0 or contour_sdf.get_height() <= 0:
		errors.append("Prezentacyjna tekstura contour_sdf ma niepoprawny rozmiar.")
	elif contour_mask != null and contour_sdf.get_size() != contour_mask.get_size():
		errors.append("Prezentacyjna tekstura contour_sdf musi odpowiadać rozmiarowi contour_mask.")
	if rock_detail_texture == null:
		errors.append("Produkcyjny renderer terenu wymaga kafelkowej rock_detail_texture.")
	if world_size.x <= 0.0 or world_size.y <= 0.0:
		errors.append("Rozmiar świata renderera musi być dodatni.")
	if chunk_size < 64:
		errors.append("Rozmiar chunka renderera musi wynosić co najmniej 64.")
	if region_profiles.size() != REQUIRED_PROFILE_COUNT:
		errors.append("Renderer terenu wymaga dokładnie czterech profili regionów.")
	if region_profiles.is_empty():
		return errors

	var sorted_profiles := _sorted_profiles()
	var known_ids := {}
	for profile in sorted_profiles:
		if profile == null:
			errors.append("Lista profili regionów zawiera pusty zasób.")
			continue
		for profile_error in profile.validation_errors():
			errors.append("%s: %s" % [profile.region_id, profile_error])
		if known_ids.has(profile.region_id):
			errors.append("Powielony region_id profilu wizualnego: %s." % profile.region_id)
		known_ids[profile.region_id] = true

	if not sorted_profiles.is_empty() and sorted_profiles[0] != null:
		if sorted_profiles[0].start_depth_ratio > 0.001:
			errors.append("Profile wizualne nie pokrywają początku świata.")
		var previous_end := sorted_profiles[0].end_depth_ratio
		for index in range(1, sorted_profiles.size()):
			var profile := sorted_profiles[index]
			if profile == null:
				continue
			if absf(profile.start_depth_ratio - previous_end) > 0.001:
				errors.append("Profile wizualne muszą tworzyć ciągłe, niepokrywające się pasma głębokości.")
			previous_end = profile.end_depth_ratio
		if previous_end < 0.999:
			errors.append("Profile wizualne nie pokrywają końca świata.")
	return errors


func _ensure_global_water() -> void:
	if _global_water != null and is_instance_valid(_global_water):
		return
	if _sorted_profiles().size() != REQUIRED_PROFILE_COUNT:
		return
	_global_water = Polygon2D.new()
	_global_water.name = "WaterBackground"
	_global_water.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(world_size.x, 0.0),
		world_size,
		Vector2(0.0, world_size.y),
	])
	var parent := _valid_parent_or_self(_water_parent)
	_global_water.z_index = 0 if parent != self else water_z_index
	_global_water.z_as_relative = parent != self
	_global_water.material = _water_material()
	parent.add_child(_global_water)


func _ensure_global_backdrop() -> void:
	if _global_backdrop != null and is_instance_valid(_global_backdrop):
		return
	if _sorted_profiles().size() != REQUIRED_PROFILE_COUNT:
		return
	_global_backdrop = Polygon2D.new()
	_global_backdrop.name = "DistantBiomeBackground"
	_global_backdrop.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(world_size.x, 0.0),
		world_size,
		Vector2(0.0, world_size.y),
	])
	var parent := _valid_parent_or_self(_backdrop_parent)
	_global_backdrop.z_index = 0 if parent != self else backdrop_z_index
	_global_backdrop.z_as_relative = parent != self
	_global_backdrop.material = _backdrop_material()
	parent.add_child(_global_backdrop)


func _ensure_global_terrain() -> void:
	if _global_terrain != null and is_instance_valid(_global_terrain):
		return
	if contour_mask == null or contour_sdf == null or _sorted_profiles().size() != REQUIRED_PROFILE_COUNT:
		return
	var texture_size := Vector2(contour_sdf.get_size())
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	_global_terrain = Sprite2D.new()
	_global_terrain.name = "TerrainBackground"
	_global_terrain.texture = contour_sdf
	_global_terrain.centered = true
	_global_terrain.position = world_size * 0.5
	_global_terrain.scale = world_size / texture_size
	_global_terrain.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_global_terrain.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	var parent := _valid_parent_or_self(_terrain_parent)
	_global_terrain.z_index = 0 if parent != self else terrain_z_index
	_global_terrain.z_as_relative = parent != self
	_global_terrain.material = _terrain_material()
	parent.add_child(_global_terrain)


func _water_material() -> ShaderMaterial:
	if _water_materials.has(GLOBAL_MATERIAL_KEY):
		return _water_materials[GLOBAL_MATERIAL_KEY] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	_apply_water_profile_parameters(material)
	material.set_shader_parameter("world_height", world_size.y)
	_apply_dynamic_parameters(material)
	_water_materials[GLOBAL_MATERIAL_KEY] = material
	return material


func _terrain_material() -> ShaderMaterial:
	if _terrain_materials.has(GLOBAL_MATERIAL_KEY):
		return _terrain_materials[GLOBAL_MATERIAL_KEY] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("has_detail_texture", rock_detail_texture != null)
	if rock_detail_texture != null:
		material.set_shader_parameter("rock_detail_texture", rock_detail_texture)
	_apply_terrain_profile_parameters(material)
	material.set_shader_parameter("world_height", world_size.y)
	material.set_shader_parameter("world_origin", global_position)
	_apply_dynamic_parameters(material)
	_terrain_materials[GLOBAL_MATERIAL_KEY] = material
	return material


func _backdrop_material() -> ShaderMaterial:
	if _backdrop_materials.has(GLOBAL_MATERIAL_KEY):
		return _backdrop_materials[GLOBAL_MATERIAL_KEY] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = BACKDROP_SHADER
	_apply_backdrop_profile_parameters(material)
	material.set_shader_parameter("world_size", world_size)
	material.set_shader_parameter("world_origin", global_position)
	_apply_backdrop_dynamic_parameters(material)
	_backdrop_materials[GLOBAL_MATERIAL_KEY] = material
	return material


func _apply_water_profile_parameters(material: ShaderMaterial) -> void:
	var profiles := _sorted_profiles()
	if profiles.size() != REQUIRED_PROFILE_COUNT:
		return
	material.set_shader_parameter("profile_boundaries", Vector4(
		profiles[0].end_depth_ratio,
		profiles[1].end_depth_ratio,
		profiles[2].end_depth_ratio,
		profiles[3].end_depth_ratio
	))
	for index in range(REQUIRED_PROFILE_COUNT):
		var profile := profiles[index]
		material.set_shader_parameter("water_near_%d" % index, profile.water_near_color)
		material.set_shader_parameter("water_far_%d" % index, profile.water_far_color)
		material.set_shader_parameter("caustics_color_%d" % index, profile.caustics_color)
		material.set_shader_parameter("water_params_%d" % index, Vector4(
			profile.water_clarity,
			profile.caustics_strength,
			profile.suspended_particle_density,
			profile.current_distortion_strength
		))


func _apply_terrain_profile_parameters(material: ShaderMaterial) -> void:
	var profiles := _sorted_profiles()
	if profiles.size() != REQUIRED_PROFILE_COUNT:
		return
	material.set_shader_parameter("profile_boundaries", Vector4(
		profiles[0].end_depth_ratio,
		profiles[1].end_depth_ratio,
		profiles[2].end_depth_ratio,
		profiles[3].end_depth_ratio
	))
	for index in range(REQUIRED_PROFILE_COUNT):
		var profile := profiles[index]
		material.set_shader_parameter("rock_base_%d" % index, Color(
			profile.rock_base_tint.r,
			profile.rock_base_tint.g,
			profile.rock_base_tint.b,
			profile.caustics_strength
		))
		material.set_shader_parameter("rock_shadow_%d" % index, profile.rock_shadow_tint)
		material.set_shader_parameter("rock_edge_%d" % index, profile.rock_edge_color)
		material.set_shader_parameter("rock_params_%d" % index, Vector4(
			profile.detail_world_scale,
			profile.detail_strength,
			profile.edge_width_texels,
			profile.edge_highlight_strength
		))


func _apply_backdrop_profile_parameters(material: ShaderMaterial) -> void:
	var profiles := _sorted_profiles()
	if profiles.size() != REQUIRED_PROFILE_COUNT:
		return
	material.set_shader_parameter("r1_depth_end", profiles[0].end_depth_ratio)
	material.set_shader_parameter("r2_depth_end", profiles[1].end_depth_ratio)
	material.set_shader_parameter("r3_depth_end", profiles[2].end_depth_ratio)
	for index in range(REQUIRED_PROFILE_COUNT):
		var profile := profiles[index]
		var prefix := "r%d" % (index + 1)
		material.set_shader_parameter("%s_backdrop_tint" % prefix, profile.backdrop_tint)
		material.set_shader_parameter("%s_backdrop_accent" % prefix, profile.backdrop_accent)
		material.set_shader_parameter("%s_backdrop_strength" % prefix, profile.backdrop_strength)
		material.set_shader_parameter("%s_backdrop_motion_scale" % prefix, profile.backdrop_motion_scale)
		material.set_shader_parameter("%s_backdrop_motif_scale" % prefix, profile.backdrop_motif_scale)


func _refresh_dynamic_material_parameters() -> void:
	for material_variant in _water_materials.values():
		var material := material_variant as ShaderMaterial
		if material != null:
			_apply_dynamic_parameters(material)
	for material_variant in _backdrop_materials.values():
		var material := material_variant as ShaderMaterial
		if material != null:
			material.set_shader_parameter("world_origin", global_position)
			_apply_backdrop_dynamic_parameters(material)
	for material_variant in _terrain_materials.values():
		var material := material_variant as ShaderMaterial
		if material != null:
			material.set_shader_parameter("world_origin", global_position)
			_apply_dynamic_parameters(material)


func _refresh_animation_parameter() -> void:
	for material_variant in _water_materials.values():
		var material := material_variant as ShaderMaterial
		if material != null:
			material.set_shader_parameter("anim_time", _anim_time)
	for material_variant in _backdrop_materials.values():
		var material := material_variant as ShaderMaterial
		if material != null:
			material.set_shader_parameter("anim_time", 0.0 if _reduced_motion else _anim_time)
	for material_variant in _terrain_materials.values():
		var material := material_variant as ShaderMaterial
		if material != null:
			material.set_shader_parameter("anim_time", _anim_time)


func _apply_dynamic_parameters(material: ShaderMaterial) -> void:
	material.set_shader_parameter("quality_level", float(QUALITY_IDS.find(_graphics_quality)))
	material.set_shader_parameter("reduced_motion", _reduced_motion)
	material.set_shader_parameter("anim_time", _anim_time)


func _apply_backdrop_dynamic_parameters(material: ShaderMaterial) -> void:
	material.set_shader_parameter("quality_level", QUALITY_IDS.find(_graphics_quality))
	material.set_shader_parameter("reduced_motion", _reduced_motion)
	material.set_shader_parameter("anim_time", 0.0 if _reduced_motion else _anim_time)


func _sorted_profiles() -> Array[UnderwaterRegionVisualProfile]:
	var result: Array[UnderwaterRegionVisualProfile] = []
	result.assign(region_profiles)
	result.sort_custom(func(a: UnderwaterRegionVisualProfile, b: UnderwaterRegionVisualProfile) -> bool:
		if a == null:
			return false
		if b == null:
			return true
		return a.start_depth_ratio < b.start_depth_ratio
	)
	return result


func _chunk_world_rect(coordinates: Vector2i) -> Rect2:
	var position := Vector2(coordinates) * float(chunk_size)
	var end := Vector2(
		minf(position.x + float(chunk_size), world_size.x),
		minf(position.y + float(chunk_size), world_size.y)
	)
	return Rect2(position, end - position)


func _chunk_grid_size() -> Vector2i:
	return Vector2i(
		ceili(world_size.x / maxf(float(chunk_size), 1.0)),
		ceili(world_size.y / maxf(float(chunk_size), 1.0))
	)


func _is_chunk_in_bounds(coordinates: Vector2i) -> bool:
	var grid_size := _chunk_grid_size()
	return coordinates.x >= 0 and coordinates.y >= 0 and coordinates.x < grid_size.x and coordinates.y < grid_size.y


func _parse_chunk_key(chunk_key: String) -> Vector2i:
	var parts := chunk_key.split(":", false, 2)
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(parts[0].to_int(), parts[1].to_int())


func _chunk_key(coordinates: Vector2i) -> String:
	return "%d:%d" % [coordinates.x, coordinates.y]


func _valid_parent_or_self(candidate: Node2D) -> Node2D:
	if candidate != null and is_instance_valid(candidate):
		return candidate
	return self


func _node_path_or_empty(node: Node2D) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	return str(node.get_path())
