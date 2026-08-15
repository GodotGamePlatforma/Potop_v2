class_name UnderwaterEnvironment2D
extends Node2D

const POST_PROCESS_SHADER: Shader = preload("res://assets/diving/world/shaders/underwater_post_process.gdshader")
const CAUSTICS_SHADER: Shader = preload("res://assets/diving/world/shaders/underwater_caustics.gdshader")
const LIGHT_SHAFTS_SHADER: Shader = preload("res://assets/diving/world/shaders/underwater_light_shafts.gdshader")

const POST_PROCESS_CANVAS_LAYER := 1
const VALID_GRAPHICS_QUALITIES := ["low", "medium", "high"]
const DEFAULT_WORLD_SIZE := Vector2(11520.0, 6480.0)
const DEFAULT_REGION_COLOR := Color(0.035, 0.20, 0.26, 1.0)
const DEFAULT_ACCENT_COLOR := Color(0.18, 0.75, 0.80, 1.0)
const REFERENCE_CURRENT_SPEED := 90.0
const PARTICLE_TEXTURE_SIZE := 16
const EFFECT_HALF_EXTENT := Vector2(920.0, 540.0)
const REDUCED_MOTION_RATE := 0.08

var _world_size := DEFAULT_WORLD_SIZE
var _visual_profiles: Array[Resource] = []
var _graphics_quality := "high"
var _reduced_motion := false
var _visual_time := 0.0
var _depth_ratio := 0.0
var _region_color := DEFAULT_REGION_COLOR
var _accent_color := DEFAULT_ACCENT_COLOR
var _water_clarity := 0.7
var _suspended_particle_density := 0.35
var _profile_caustics_strength := 0.35
var _current_vector := Vector2.ZERO
var _smoothed_flow := Vector2.ZERO
var _diver_position := Vector2.ZERO
var _quality_caustics_intensity := 0.055
var _quality_light_shafts_intensity := 0.035

var _post_process_layer: CanvasLayer
var _post_process_rect: ColorRect
var _post_process_material: ShaderMaterial
var _caustics: Polygon2D
var _caustics_material: ShaderMaterial
var _light_shafts: Polygon2D
var _light_shafts_material: ShaderMaterial
var _far_particles: GPUParticles2D
var _near_particles: GPUParticles2D
var _far_particle_material: ParticleProcessMaterial
var _near_particle_material: ParticleProcessMaterial
var _near_particle_budget := 0


func _ready() -> void:
	_ensure_effect_nodes()
	_apply_graphics_quality()
	_apply_reduced_motion()
	_apply_environment_parameters()


func configure(world_size: Vector2, visual_profiles: Array[Resource] = []) -> void:
	_world_size = Vector2(maxf(world_size.x, 1.0), maxf(world_size.y, 1.0))
	_visual_profiles.assign(visual_profiles)
	_ensure_effect_nodes()
	_resize_local_field()
	_apply_environment_parameters()


func set_graphics_quality(quality_id: String) -> void:
	_graphics_quality = quality_id if quality_id in VALID_GRAPHICS_QUALITIES else "high"
	_ensure_effect_nodes()
	_apply_graphics_quality()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_ensure_effect_nodes()
	_apply_reduced_motion()


func update_environment(
	depth_ratio: float,
	region_color: Color = DEFAULT_REGION_COLOR,
	accent_color: Color = DEFAULT_ACCENT_COLOR,
	current_vector: Vector2 = Vector2.ZERO,
	diver_position: Vector2 = Vector2.ZERO,
	delta: float = 0.0,
	water_clarity: float = 0.7,
	suspended_particle_density: float = 0.35,
	caustics_strength: float = 0.35
) -> void:
	_ensure_effect_nodes()
	_depth_ratio = clampf(depth_ratio, 0.0, 1.0)
	_region_color = region_color
	_accent_color = accent_color
	_water_clarity = clampf(water_clarity, 0.0, 1.0)
	_suspended_particle_density = clampf(suspended_particle_density, 0.0, 1.0)
	_profile_caustics_strength = clampf(caustics_strength, 0.0, 1.0)
	_current_vector = current_vector
	_diver_position = diver_position

	var safe_delta := maxf(delta, 0.0)
	var motion_rate := REDUCED_MOTION_RATE if _reduced_motion else 1.0
	_visual_time += safe_delta * motion_rate
	var normalized_flow := current_vector / REFERENCE_CURRENT_SPEED
	normalized_flow = normalized_flow.limit_length(1.0)
	if safe_delta <= 0.0:
		_smoothed_flow = normalized_flow
	else:
		var response := 1.0 - exp(-safe_delta * 3.5)
		_smoothed_flow = _smoothed_flow.lerp(normalized_flow, response)

	_caustics.global_position = diver_position
	_light_shafts.global_position = diver_position
	_far_particles.global_position = diver_position
	_near_particles.global_position = diver_position
	_apply_environment_parameters()


func set_visual_time_for_tests(time_seconds: float) -> void:
	_visual_time = maxf(time_seconds, 0.0)
	_ensure_effect_nodes()
	_apply_environment_parameters()


func environment_state() -> Dictionary:
	return {
		"world_size": _world_size,
		"visual_profile_count": _visual_profiles.size(),
		"quality": _graphics_quality,
		"reduced_motion": _reduced_motion,
		"visual_time": _visual_time,
		"depth_ratio": _depth_ratio,
		"region_color": _region_color,
		"accent_color": _accent_color,
		"water_clarity": _water_clarity,
		"suspended_particle_density": _suspended_particle_density,
		"profile_caustics_strength": _profile_caustics_strength,
		"current_vector": _current_vector,
		"smoothed_flow": _smoothed_flow,
		"diver_position": _diver_position,
		"post_process_layer": POST_PROCESS_CANVAS_LAYER,
		"refraction_enabled": _graphics_quality != "low" and not _reduced_motion,
		"caustics_intensity": _quality_caustics_intensity * clampf(_profile_caustics_strength * 1.25, 0.22, 1.0),
		"light_shafts_intensity": _quality_light_shafts_intensity * lerpf(0.72, 1.0, _water_clarity),
		"far_particle_count": _far_particles.amount if _far_particles != null else 0,
		"near_particle_count": _near_particle_budget,
	}


func _ensure_effect_nodes() -> void:
	if _post_process_layer != null:
		return
	_build_post_process()
	_build_light_shafts()
	_build_caustics()
	_build_particles()


func _build_post_process() -> void:
	_post_process_layer = CanvasLayer.new()
	_post_process_layer.name = "UnderwaterPostProcess"
	_post_process_layer.layer = POST_PROCESS_CANVAS_LAYER
	add_child(_post_process_layer)

	_post_process_material = ShaderMaterial.new()
	_post_process_material.shader = POST_PROCESS_SHADER
	_post_process_rect = ColorRect.new()
	_post_process_rect.name = "ScreenColorGrade"
	_post_process_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_process_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_post_process_rect.material = _post_process_material
	_post_process_layer.add_child(_post_process_rect)


func _build_caustics() -> void:
	_caustics_material = ShaderMaterial.new()
	_caustics_material.shader = CAUSTICS_SHADER
	_caustics = Polygon2D.new()
	_caustics.name = "LocalCaustics"
	_caustics.top_level = true
	_caustics.z_as_relative = false
	_caustics.z_index = -25
	_caustics.material = _caustics_material
	_caustics.color = Color.WHITE
	add_child(_caustics)
	_resize_local_field()


func _build_light_shafts() -> void:
	_light_shafts_material = ShaderMaterial.new()
	_light_shafts_material.shader = LIGHT_SHAFTS_SHADER
	_light_shafts = Polygon2D.new()
	_light_shafts.name = "VolumetricLightShafts"
	_light_shafts.top_level = true
	_light_shafts.z_as_relative = false
	_light_shafts.z_index = -28
	_light_shafts.material = _light_shafts_material
	_light_shafts.color = Color.WHITE
	add_child(_light_shafts)


func _build_particles() -> void:
	var particle_texture := _create_mote_texture()
	_far_particle_material = _create_particle_material(false)
	_near_particle_material = _create_particle_material(true)
	_far_particles = _create_particle_emitter("FarSuspendedMatter", particle_texture, _far_particle_material, 6.8)
	_near_particles = _create_particle_emitter("NearSuspendedMatter", particle_texture, _near_particle_material, 4.2)
	_far_particles.z_index = -24
	_near_particles.z_index = 6
	add_child(_far_particles)
	add_child(_near_particles)


func _create_particle_emitter(
	node_name: String,
	particle_texture: Texture2D,
	particle_material: ParticleProcessMaterial,
	lifetime: float
) -> GPUParticles2D:
	var emitter := GPUParticles2D.new()
	emitter.name = node_name
	emitter.top_level = true
	emitter.z_as_relative = false
	emitter.amount = 1
	emitter.lifetime = lifetime
	emitter.preprocess = lifetime
	emitter.randomness = 0.84
	emitter.local_coords = false
	emitter.fixed_fps = 30
	emitter.fract_delta = true
	emitter.visibility_rect = Rect2(-EFFECT_HALF_EXTENT * 1.45, EFFECT_HALF_EXTENT * 2.90)
	emitter.texture = particle_texture
	emitter.process_material = particle_material
	emitter.emitting = true
	return emitter


func _create_particle_material(near_field: bool) -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(EFFECT_HALF_EXTENT.x, EFFECT_HALF_EXTENT.y, 1.0)
	material.direction = Vector3(0.15, -1.0, 0.0)
	material.spread = 52.0 if near_field else 72.0
	material.gravity = Vector3(0.0, -0.35 if near_field else -0.18, 0.0)
	material.initial_velocity_min = 2.0 if near_field else 0.7
	material.initial_velocity_max = 8.0 if near_field else 3.5
	material.scale_min = 0.34 if near_field else 0.10
	material.scale_max = 0.92 if near_field else 0.38
	material.color_ramp = _create_particle_fade(near_field)
	return material


func _create_particle_fade(near_field: bool) -> GradientTexture1D:
	var peak_alpha := 0.34 if near_field else 0.22
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.16, 0.74, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.72, 0.93, 0.94, 0.0),
		Color(0.72, 0.93, 0.94, peak_alpha),
		Color(0.54, 0.82, 0.82, peak_alpha * 0.72),
		Color(0.45, 0.72, 0.74, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


func _create_mote_texture() -> ImageTexture:
	var image := Image.create(PARTICLE_TEXTURE_SIZE, PARTICLE_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(PARTICLE_TEXTURE_SIZE - 1, PARTICLE_TEXTURE_SIZE - 1) * 0.5
	var radius := float(PARTICLE_TEXTURE_SIZE) * 0.5
	for y in range(PARTICLE_TEXTURE_SIZE):
		for x in range(PARTICLE_TEXTURE_SIZE):
			var distance := Vector2(x, y).distance_to(center) / radius
			var alpha := 1.0 - smoothstep(0.05, 0.94, distance)
			alpha *= alpha
			image.set_pixel(x, y, Color(0.78, 0.96, 0.96, alpha))
	return ImageTexture.create_from_image(image)


func _resize_local_field() -> void:
	if _caustics == null:
		return
	var half_extent := EFFECT_HALF_EXTENT
	if is_inside_tree():
		var viewport_half := get_viewport_rect().size * 0.5
		half_extent = Vector2(
			maxf(half_extent.x, viewport_half.x + 220.0),
			maxf(half_extent.y, viewport_half.y + 180.0)
		)
	_caustics.polygon = PackedVector2Array([
		Vector2(-half_extent.x, -half_extent.y),
		Vector2(half_extent.x, -half_extent.y),
		Vector2(half_extent.x, half_extent.y),
		Vector2(-half_extent.x, half_extent.y),
	])
	_caustics.uv = PackedVector2Array([
		Vector2.ZERO,
		Vector2.RIGHT,
		Vector2.ONE,
		Vector2.DOWN,
	])
	if _light_shafts != null:
		_light_shafts.polygon = _caustics.polygon
		_light_shafts.uv = _caustics.uv


func _apply_graphics_quality() -> void:
	if _post_process_material == null:
		return
	var far_budget := 32
	var near_budget := 0
	var refraction := 0.0
	var grain := 0.002
	var bloom := 0.0
	var chromatic_aberration := 0.0
	_quality_caustics_intensity = 0.055
	_quality_light_shafts_intensity = 0.035
	match _graphics_quality:
		"medium":
			far_budget = 56
			near_budget = 8
			refraction = 0.00075
			grain = 0.003
			bloom = 0.032
			chromatic_aberration = 0.00022
			_quality_caustics_intensity = 0.095
			_quality_light_shafts_intensity = 0.068
		"high":
			far_budget = 96
			near_budget = 16
			refraction = 0.00115
			grain = 0.004
			bloom = 0.058
			chromatic_aberration = 0.00042
			_quality_caustics_intensity = 0.14
			_quality_light_shafts_intensity = 0.105

	_far_particles.amount = far_budget
	_near_particles.amount = maxi(near_budget, 1)
	_near_particle_budget = near_budget
	_far_particles.emitting = true
	_near_particles.emitting = near_budget > 0
	_post_process_material.set_shader_parameter("refraction_strength", refraction)
	_post_process_material.set_shader_parameter("grain_strength", grain)
	_post_process_material.set_shader_parameter("quality_level", VALID_GRAPHICS_QUALITIES.find(_graphics_quality))
	_post_process_material.set_shader_parameter("bloom_strength", bloom)
	_post_process_material.set_shader_parameter("chromatic_aberration", chromatic_aberration)
	_light_shafts_material.set_shader_parameter("quality_level", VALID_GRAPHICS_QUALITIES.find(_graphics_quality))
	_apply_environment_parameters()
	_apply_reduced_motion()


func _apply_reduced_motion() -> void:
	if _far_particles == null:
		return
	var particle_speed := 0.12 if _reduced_motion else 1.0
	_far_particles.speed_scale = particle_speed
	_near_particles.speed_scale = particle_speed
	var base_refraction := 0.0
	if _graphics_quality == "medium":
		base_refraction = 0.00075
	elif _graphics_quality == "high":
		base_refraction = 0.00115
	_post_process_material.set_shader_parameter(
		"refraction_strength",
		0.0 if _reduced_motion else base_refraction
	)
	_light_shafts_material.set_shader_parameter("reduced_motion", _reduced_motion)


func _apply_environment_parameters() -> void:
	if _post_process_material == null:
		return
	_post_process_material.set_shader_parameter("anim_time", _visual_time)
	_post_process_material.set_shader_parameter("depth_ratio", _depth_ratio)
	_post_process_material.set_shader_parameter("effect_intensity", 1.0)
	_post_process_material.set_shader_parameter("flow_vector", _smoothed_flow)
	_post_process_material.set_shader_parameter("region_color", _region_color)
	_post_process_material.set_shader_parameter("accent_color", _accent_color)
	_post_process_material.set_shader_parameter("world_anchor", _diver_position)
	_post_process_material.set_shader_parameter("water_clarity", _water_clarity)
	_post_process_material.set_shader_parameter("suspended_particle_density", _suspended_particle_density)
	_post_process_material.set_shader_parameter("caustics_strength", _profile_caustics_strength)

	_caustics_material.set_shader_parameter("anim_time", _visual_time)
	_caustics_material.set_shader_parameter("depth_ratio", _depth_ratio)
	_caustics_material.set_shader_parameter("flow_vector", _smoothed_flow)
	_caustics_material.set_shader_parameter("world_anchor", _diver_position)
	_caustics_material.set_shader_parameter("accent_color", _accent_color)
	_caustics_material.set_shader_parameter(
		"intensity",
		_quality_caustics_intensity * clampf(_profile_caustics_strength * 1.25, 0.22, 1.0)
	)

	_light_shafts_material.set_shader_parameter("anim_time", _visual_time)
	_light_shafts_material.set_shader_parameter("reduced_motion", _reduced_motion)
	_light_shafts_material.set_shader_parameter("flow_vector", _smoothed_flow)
	_light_shafts_material.set_shader_parameter("world_anchor", _diver_position)
	_light_shafts_material.set_shader_parameter("region_color", _region_color)
	_light_shafts_material.set_shader_parameter("accent_color", _accent_color)
	_light_shafts_material.set_shader_parameter(
		"intensity",
		_quality_light_shafts_intensity * lerpf(0.72, 1.0, _water_clarity)
	)
	_apply_particle_flow_and_color()


func _apply_particle_flow_and_color() -> void:
	if _far_particle_material == null:
		return
	var flow_direction := _smoothed_flow
	if flow_direction.length_squared() <= 0.0001:
		flow_direction = Vector2(0.10, -0.35)
	else:
		flow_direction = (flow_direction + Vector2(0.0, -0.18)).normalized()
	_far_particle_material.direction = Vector3(flow_direction.x, flow_direction.y, 0.0)
	_near_particle_material.direction = Vector3(flow_direction.x, flow_direction.y, 0.0)
	var current_boost := clampf(_smoothed_flow.length(), 0.0, 1.0)
	_far_particle_material.initial_velocity_max = lerpf(3.5, 8.0, current_boost)
	_near_particle_material.initial_velocity_max = lerpf(8.0, 16.0, current_boost)
	var particle_color := _region_color.lerp(_accent_color, 0.56).lerp(Color.WHITE, 0.24)
	var density_alpha := lerpf(0.34, 1.0, _suspended_particle_density)
	_far_particle_material.color = Color(particle_color.r, particle_color.g, particle_color.b, 0.78 * density_alpha)
	_near_particle_material.color = Color(particle_color.r, particle_color.g, particle_color.b, 0.92 * density_alpha)
