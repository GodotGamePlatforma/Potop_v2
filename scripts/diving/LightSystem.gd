class_name LightSystem
extends RefCounted

const TerrainOcclusionScript := preload("res://scripts/diving/DiveTerrainOcclusion.gd")
const LIGHT_TEXTURE_SIZE := 256
const FALLBACK_SHALLOW_VISIBILITY_MAX_DEPTH := 35.0
const FALLBACK_DEEP_DARKNESS_MIN_DEPTH := 105.0
const FALLBACK_SHALLOW_AMBIENT := Color(0.96, 0.98, 1.0, 1.0)
const FALLBACK_DEEP_AMBIENT := Color(0.32, 0.38, 0.48, 1.0)
const FALLBACK_TRANSITION_POWER := 1.0

var _radial_texture: GradientTexture2D

func configure(
	ambient: CanvasModulate,
	point_light: PointLight2D,
	gear_definition,
	light_enabled: bool = true,
	lighting_definition = null,
	depth: float = 0.0
) -> bool:
	update_ambient(ambient, depth, lighting_definition)
	if point_light == null or gear_definition == null or not gear_definition.is_valid_light():
		if point_light != null:
			point_light.enabled = false
		return false
	var radial_texture := _get_radial_texture(float(gear_definition.light_inner_radius), float(gear_definition.light_outer_radius))
	if point_light.texture != radial_texture:
		point_light.texture = radial_texture
	point_light.texture_scale = (float(gear_definition.light_outer_radius) * 2.0) / float(LIGHT_TEXTURE_SIZE)
	point_light.energy = maxf(float(gear_definition.light_energy), 0.0)
	point_light.color = gear_definition.light_color
	point_light.blend_mode = Light2D.BLEND_MODE_ADD
	point_light.shadow_enabled = true
	point_light.shadow_item_cull_mask = TerrainOcclusionScript.TERRAIN_LIGHT_MASK
	point_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	point_light.shadow_filter_smooth = 3.0
	point_light.enabled = light_enabled
	return true


func set_light_enabled(point_light: PointLight2D, gear_definition, light_enabled: bool) -> bool:
	var can_emit: bool = point_light != null and gear_definition != null and gear_definition.is_valid_light()
	if point_light != null:
		point_light.enabled = can_emit and light_enabled
	return can_emit and light_enabled


func update_ambient(ambient: CanvasModulate, depth: float, lighting_definition = null) -> Color:
	var color := ambient_color_for_depth(depth, lighting_definition)
	if ambient != null:
		ambient.color = color
	return color


func ambient_color_for_depth(depth: float, lighting_definition = null) -> Color:
	var shallow_depth := FALLBACK_SHALLOW_VISIBILITY_MAX_DEPTH
	var deep_depth := FALLBACK_DEEP_DARKNESS_MIN_DEPTH
	var shallow_color := FALLBACK_SHALLOW_AMBIENT
	var deep_color := FALLBACK_DEEP_AMBIENT
	var transition_power := FALLBACK_TRANSITION_POWER
	if lighting_definition != null:
		shallow_depth = float(lighting_definition.shallow_visibility_max_depth)
		deep_depth = float(lighting_definition.deep_darkness_min_depth)
		shallow_color = Color(lighting_definition.shallow_ambient_color)
		deep_color = Color(lighting_definition.deep_ambient_color)
		transition_power = float(lighting_definition.transition_power)
	var linear_ratio := inverse_lerp(shallow_depth, maxf(deep_depth, shallow_depth + 0.001), depth)
	var powered_ratio := pow(clampf(linear_ratio, 0.0, 1.0), maxf(transition_power, 0.01))
	var shaped_ratio := smoothstep(0.0, 1.0, powered_ratio)
	return shallow_color.lerp(deep_color, shaped_ratio)

func _get_radial_texture(inner_radius: float, outer_radius: float) -> GradientTexture2D:
	var inner_ratio := clampf(inner_radius / maxf(outer_radius, 1.0), 0.0, 0.92)
	var core_ratio := inner_ratio * 0.42
	var shoulder := minf(inner_ratio + 0.22, 0.90)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, core_ratio, inner_ratio, shoulder, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.96, 0.98, 1.0, 0.96),
		Color(0.78, 0.86, 0.92, 0.82),
		Color(0.34, 0.44, 0.52, 0.42),
		Color(0.0, 0.0, 0.0, 0.0),
	])
	if _radial_texture == null:
		_radial_texture = GradientTexture2D.new()
		_radial_texture.width = LIGHT_TEXTURE_SIZE
		_radial_texture.height = LIGHT_TEXTURE_SIZE
		_radial_texture.fill = GradientTexture2D.FILL_RADIAL
		_radial_texture.fill_from = Vector2(0.5, 0.5)
		_radial_texture.fill_to = Vector2(1.0, 0.5)
	_radial_texture.gradient = gradient
	return _radial_texture
