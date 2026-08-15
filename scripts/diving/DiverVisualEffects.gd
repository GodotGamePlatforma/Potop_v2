extends Node2D

const BUBBLE_TEXTURE_SIZE := 18
const WAKE_TEXTURE_SIZE := 14
const GLINT_TEXTURE_SIZE := 16
const WAKE_MIN_SPEED := 22.0

@onready var diver_sprite: AnimatedSprite2D = get_parent().get_node("AnimatedSprite2D")
@onready var breath_socket: Marker2D = get_parent().get_node_or_null("AnimatedSprite2D/BreathSocket") as Marker2D
@onready var fin_upper_socket: Marker2D = get_parent().get_node_or_null("AnimatedSprite2D/FinUpperSocket") as Marker2D
@onready var fin_lower_socket: Marker2D = get_parent().get_node_or_null("AnimatedSprite2D/FinLowerSocket") as Marker2D
@onready var tool_hand_socket: Marker2D = get_parent().get_node_or_null("AnimatedSprite2D/ToolHandSocket") as Marker2D
@onready var leak_valve_socket: Marker2D = get_parent().get_node_or_null("AnimatedSprite2D/LeakValveSocket") as Marker2D

var _bubble_emitter: GPUParticles2D
var _wake_upper_emitter: GPUParticles2D
var _wake_lower_emitter: GPUParticles2D
var _leak_emitter: GPUParticles2D
var _tool_emitter: GPUParticles2D
var _cue_emitter: GPUParticles2D
var _bubble_material: ParticleProcessMaterial
var _wake_upper_material: ParticleProcessMaterial
var _wake_lower_material: ParticleProcessMaterial
var _leak_material: ParticleProcessMaterial
var _tool_material: ParticleProcessMaterial
var _cue_material: ParticleProcessMaterial
var _graphics_quality := "high"
var _reduced_motion := false
var _leak_intensity := 0.0
var _interaction_action: StringName = &""
var _interaction_progress := 0.0
var _is_towing := false
var _breath_clock := 1.85


func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = (get_parent() as CanvasItem).z_index - 1
	var budget := _quality_budget()
	var bubble_texture := _create_bubble_texture()
	var wake_texture := _create_wake_texture()
	var glint_texture := _create_glint_texture()

	_bubble_material = _create_bubble_material()
	_bubble_emitter = _create_emitter(
		"BreathEmitter",
		int(budget["bubble"]),
		0.92,
		bubble_texture,
		_bubble_material,
		true,
		41031
	)
	_bubble_emitter.explosiveness = 0.48
	_bubble_emitter.randomness = 0.74
	_bubble_emitter.visibility_rect = Rect2(-120, -190, 240, 260)
	_bubble_emitter.z_index = 2

	_wake_upper_material = _create_wake_material()
	_wake_upper_emitter = _create_emitter(
		"WakeEmitterUpper",
		int(budget["wake_upper"]),
		1.1,
		wake_texture,
		_wake_upper_material,
		false,
		41047
	)
	_wake_upper_emitter.randomness = 0.84
	_wake_upper_emitter.visibility_rect = Rect2(-150, -100, 300, 200)

	_wake_lower_material = _create_wake_material()
	_wake_lower_emitter = _create_emitter(
		"WakeEmitterLower",
		int(budget["wake_lower"]),
		1.1,
		wake_texture,
		_wake_lower_material,
		false,
		41057
	)
	_wake_lower_emitter.randomness = 0.88
	_wake_lower_emitter.visibility_rect = Rect2(-150, -100, 300, 200)

	_leak_material = _create_leak_material()
	_leak_emitter = _create_emitter(
		"LeakEmitter",
		int(budget["leak"]),
		1.15,
		bubble_texture,
		_leak_material,
		false,
		41077
	)
	_leak_emitter.randomness = 0.58
	_leak_emitter.visibility_rect = Rect2(-100, -160, 200, 220)
	_leak_emitter.z_index = 2

	_tool_material = _create_tool_material()
	_tool_emitter = _create_emitter(
		"ToolEmitter",
		int(budget["tool"]),
		0.42,
		glint_texture,
		_tool_material,
		false,
		41081
	)
	_tool_emitter.randomness = 0.72
	_tool_emitter.visibility_rect = Rect2(-70, -70, 140, 140)
	_tool_emitter.z_index = 2

	_cue_material = _create_cue_material()
	_cue_emitter = _create_emitter(
		"CueEmitter",
		int(budget["cue"]),
		0.48,
		glint_texture,
		_cue_material,
		true,
		41113
	)
	_cue_emitter.explosiveness = 0.92
	_cue_emitter.randomness = 0.66
	_cue_emitter.visibility_rect = Rect2(-120, -120, 240, 240)
	_cue_emitter.z_index = 3
	_apply_graphics_quality()


func _create_emitter(
	emitter_name: String,
	particle_count: int,
	lifetime: float,
	texture: Texture2D,
	material: ParticleProcessMaterial,
	one_shot: bool,
	fixed_seed: int
) -> GPUParticles2D:
	var emitter := GPUParticles2D.new()
	emitter.name = emitter_name
	emitter.amount = maxi(particle_count, 1)
	emitter.lifetime = lifetime
	emitter.one_shot = one_shot
	emitter.local_coords = false
	emitter.texture = texture
	emitter.process_material = material
	emitter.use_fixed_seed = true
	emitter.seed = fixed_seed
	emitter.emitting = false
	add_child(emitter)
	return emitter


func set_graphics_quality(quality_id: String) -> void:
	_graphics_quality = quality_id if quality_id in ["low", "medium", "high"] else "high"
	_apply_graphics_quality()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_apply_graphics_quality()


func set_visual_context(
	leak_intensity: float,
	interaction_action: StringName,
	interaction_progress: float,
	is_towing: bool
) -> void:
	_leak_intensity = clampf(leak_intensity, 0.0, 1.0)
	_interaction_action = interaction_action
	_interaction_progress = clampf(interaction_progress, 0.0, 1.0)
	_is_towing = is_towing


func reset_presentation() -> void:
	_leak_intensity = 0.0
	_interaction_action = &""
	_interaction_progress = 0.0
	_is_towing = false
	_breath_clock = 1.85
	for emitter in [
		_bubble_emitter,
		_wake_upper_emitter,
		_wake_lower_emitter,
		_leak_emitter,
		_tool_emitter,
		_cue_emitter,
	]:
		if emitter != null:
			emitter.restart()
			emitter.emitting = false


func play_cue(cue: StringName, target_global_position: Vector2, strength: float = 1.0) -> void:
	if _cue_emitter == null or _cue_material == null:
		return
	var origin := _socket_global(&"leak_valve") if cue == &"hit" else _socket_global(&"tool_hand")
	var direction := target_global_position - origin
	if direction.length_squared() <= 0.001:
		var facing := -1.0 if diver_sprite != null and diver_sprite.flip_h else 1.0
		direction = Vector2(-facing, -0.38) if cue == &"hit" else Vector2(facing, -0.12)
	direction = direction.normalized()
	_cue_emitter.global_position = origin
	_cue_emitter.global_rotation = 0.0
	_cue_material.direction = Vector3(direction.x, direction.y, 0.0)
	var clamped_strength := clampf(strength, 0.25, 1.5)
	match cue:
		&"harpoon_attack":
			_cue_material.color = Color(0.95, 0.70, 0.28, 0.84)
			_cue_material.spread = 12.0
			_cue_material.initial_velocity_min = 38.0 * clamped_strength
			_cue_material.initial_velocity_max = 76.0 * clamped_strength
		&"knife_attack":
			_cue_material.color = Color(0.48, 0.92, 0.86, 0.76)
			_cue_material.spread = 38.0
			_cue_material.initial_velocity_min = 24.0 * clamped_strength
			_cue_material.initial_velocity_max = 52.0 * clamped_strength
		&"repair":
			_cue_material.color = Color(0.42, 0.88, 0.82, 0.72)
			_cue_material.spread = 68.0
			_cue_material.initial_velocity_min = 18.0 * clamped_strength
			_cue_material.initial_velocity_max = 42.0 * clamped_strength
		&"hit":
			_cue_material.color = Color(0.98, 0.31, 0.16, 0.78)
			_cue_material.spread = 54.0
			_cue_material.initial_velocity_min = 32.0 * clamped_strength
			_cue_material.initial_velocity_max = 68.0 * clamped_strength
		_:
			_cue_material.color = Color(0.72, 0.90, 0.76, 0.66)
			_cue_material.spread = 46.0
			_cue_material.initial_velocity_min = 18.0 * clamped_strength
			_cue_material.initial_velocity_max = 38.0 * clamped_strength
	_cue_emitter.emitting = true
	_cue_emitter.restart()


func graphics_quality_state() -> Dictionary:
	return {
		"quality": _graphics_quality,
		"reduced_motion": _reduced_motion,
		"bubble_count": _bubble_emitter.amount if _bubble_emitter != null else 0,
		"wake_count": (
			(_wake_upper_emitter.amount if _wake_upper_emitter != null else 0)
			+ (_wake_lower_emitter.amount if _wake_lower_emitter != null else 0)
		),
		"wake_upper_count": _wake_upper_emitter.amount if _wake_upper_emitter != null else 0,
		"wake_lower_count": _wake_lower_emitter.amount if _wake_lower_emitter != null else 0,
		"leak_count": _leak_emitter.amount if _leak_emitter != null else 0,
		"tool_count": _tool_emitter.amount if _tool_emitter != null else 0,
		"cue_count": _cue_emitter.amount if _cue_emitter != null else 0,
		"bubble_lifetime": _bubble_emitter.lifetime if _bubble_emitter != null else 0.0,
		"wake_lifetime": _wake_upper_emitter.lifetime if _wake_upper_emitter != null else 0.0,
		"leak_lifetime": _leak_emitter.lifetime if _leak_emitter != null else 0.0,
		"bubble_speed_scale": _bubble_emitter.speed_scale if _bubble_emitter != null else 0.0,
		"wake_speed_scale": _wake_upper_emitter.speed_scale if _wake_upper_emitter != null else 0.0,
		"emitter_count": 6 if _bubble_emitter != null else 0,
	}


func _quality_budget() -> Dictionary:
	var budget := {
		"bubble": 4 if _graphics_quality == "low" else 7 if _graphics_quality == "medium" else 10,
		"wake_upper": 2 if _graphics_quality == "low" else 4 if _graphics_quality == "medium" else 8,
		"wake_lower": 2 if _graphics_quality == "low" else 5 if _graphics_quality == "medium" else 8,
		"leak": 2 if _graphics_quality == "low" else 4 if _graphics_quality == "medium" else 6,
		"tool": 2 if _graphics_quality == "low" else 4 if _graphics_quality == "medium" else 6,
		"cue": 4 if _graphics_quality == "low" else 7 if _graphics_quality == "medium" else 10,
	}
	if _reduced_motion:
		budget["bubble"] = maxi(ceili(float(budget["bubble"]) * 0.60), 1)
		budget["wake_upper"] = maxi(ceili(float(budget["wake_upper"]) * 0.50), 1)
		budget["wake_lower"] = maxi(ceili(float(budget["wake_lower"]) * 0.50), 1)
		budget["leak"] = maxi(ceili(float(budget["leak"]) * 0.50), 1)
		budget["tool"] = maxi(ceili(float(budget["tool"]) * 0.50), 1)
		budget["cue"] = maxi(ceili(float(budget["cue"]) * 0.65), 1)
	return budget


func _apply_graphics_quality() -> void:
	if _bubble_emitter == null:
		return
	var budget := _quality_budget()
	_bubble_emitter.amount = int(budget["bubble"])
	_wake_upper_emitter.amount = int(budget["wake_upper"])
	_wake_lower_emitter.amount = int(budget["wake_lower"])
	_leak_emitter.amount = int(budget["leak"])
	_tool_emitter.amount = int(budget["tool"])
	_cue_emitter.amount = int(budget["cue"])

	_bubble_emitter.lifetime = 0.62 if _reduced_motion else 0.92
	_wake_upper_emitter.lifetime = 0.62 if _reduced_motion else 1.1
	_wake_lower_emitter.lifetime = 0.62 if _reduced_motion else 1.1
	_leak_emitter.lifetime = 0.72 if _reduced_motion else 1.15
	_tool_emitter.lifetime = 0.24 if _reduced_motion else 0.42
	_cue_emitter.lifetime = 0.30 if _reduced_motion else 0.48
	_bubble_emitter.speed_scale = 0.78 if _reduced_motion else 1.0
	_wake_upper_emitter.speed_scale = 0.72 if _reduced_motion else 1.0
	_wake_lower_emitter.speed_scale = 0.72 if _reduced_motion else 1.0
	_leak_emitter.speed_scale = 0.78 if _reduced_motion else 1.0
	_tool_emitter.speed_scale = 0.82 if _reduced_motion else 1.0
	_cue_emitter.speed_scale = 0.86 if _reduced_motion else 1.0
	_bubble_emitter.modulate = Color(1.0, 1.0, 1.0, 0.72 if _reduced_motion else 0.90)
	_wake_upper_emitter.modulate = Color(1.0, 1.0, 1.0, 0.54 if _reduced_motion else 0.82)
	_wake_lower_emitter.modulate = Color(1.0, 1.0, 1.0, 0.54 if _reduced_motion else 0.82)
	_leak_emitter.modulate = Color(1.0, 1.0, 1.0, 0.62 if _reduced_motion else 0.84)
	_tool_emitter.modulate = Color(1.0, 1.0, 1.0, 0.58 if _reduced_motion else 0.82)
	_cue_emitter.modulate = Color(1.0, 1.0, 1.0, 0.72 if _reduced_motion else 0.92)
	_bubble_material.spread = 11.0 if _reduced_motion else 17.0
	_wake_upper_material.spread = 20.0 if _reduced_motion else 32.0
	_wake_lower_material.spread = 20.0 if _reduced_motion else 32.0
	_leak_material.spread = 10.0 if _reduced_motion else 17.0
	_tool_material.spread = 18.0 if _reduced_motion else 30.0


func _process(delta: float) -> void:
	if diver_sprite == null:
		return
	_update_breath(delta)
	_update_wake()
	_update_leak()
	_update_tool()


func _update_breath(delta: float) -> void:
	if _bubble_emitter == null:
		return
	_bubble_emitter.global_position = _socket_global(&"breath")
	_bubble_emitter.global_rotation = 0.0
	_breath_clock += maxf(delta, 0.0)
	var interval := 2.15
	match diver_sprite.animation:
		&"swim":
			interval = 1.55
		&"sprint":
			interval = 1.05
	if _breath_clock < interval:
		return
	_breath_clock = fposmod(_breath_clock, interval)
	_bubble_emitter.emitting = true
	_bubble_emitter.restart()


func _update_wake() -> void:
	if _wake_upper_emitter == null or _wake_lower_emitter == null:
		return
	var diver := get_parent() as DiverController
	var water_relative_velocity := diver.velocity - diver.current_velocity
	var speed := water_relative_velocity.length()
	_wake_upper_emitter.global_position = _socket_global(&"fin_upper")
	_wake_lower_emitter.global_position = _socket_global(&"fin_lower")
	_wake_upper_emitter.global_rotation = 0.0
	_wake_lower_emitter.global_rotation = 0.0
	var should_emit := speed >= WAKE_MIN_SPEED
	_wake_upper_emitter.emitting = should_emit
	_wake_lower_emitter.emitting = should_emit
	if not should_emit:
		return
	var wake_direction := (-water_relative_velocity.normalized() + Vector2.UP * 0.12).normalized()
	var normalized_speed := clampf(speed / 265.0, 0.0, 1.0)
	for material in [_wake_upper_material, _wake_lower_material]:
		material.direction = Vector3(wake_direction.x, wake_direction.y, 0.0)
		material.initial_velocity_min = lerpf(12.0, 20.0, normalized_speed)
		material.initial_velocity_max = lerpf(22.0, 40.0, normalized_speed)


func _update_leak() -> void:
	if _leak_emitter == null or _leak_material == null:
		return
	_leak_emitter.global_position = _socket_global(&"leak_valve")
	_leak_emitter.global_rotation = 0.0
	_leak_emitter.emitting = _leak_intensity > 0.001
	if not _leak_emitter.emitting:
		return
	var facing := -1.0 if diver_sprite.flip_h else 1.0
	var direction := Vector2(-0.24 * facing, -0.97).normalized()
	_leak_material.direction = Vector3(direction.x, direction.y, 0.0)
	_leak_material.initial_velocity_min = lerpf(12.0, 28.0, _leak_intensity)
	_leak_material.initial_velocity_max = lerpf(24.0, 48.0, _leak_intensity)


func _update_tool() -> void:
	if _tool_emitter == null or _tool_material == null:
		return
	_tool_emitter.global_position = _socket_global(&"tool_hand")
	_tool_emitter.global_rotation = 0.0
	_tool_emitter.emitting = _interaction_progress > 0.001
	if not _tool_emitter.emitting:
		return
	_tool_material.color = (
		Color(0.43, 0.90, 0.84, 0.64)
		if _interaction_action == &"repair"
		else Color(0.90, 0.70, 0.34, 0.56)
	)


func _socket_global(socket_id: StringName) -> Vector2:
	var marker: Marker2D
	match socket_id:
		&"breath":
			marker = breath_socket
		&"fin_upper":
			marker = fin_upper_socket
		&"fin_lower":
			marker = fin_lower_socket
		&"tool_hand":
			marker = tool_hand_socket
		&"leak_valve":
			marker = leak_valve_socket
	return marker.global_position if marker != null else (get_parent() as Node2D).global_position


func _create_bubble_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0.0, -1.0, 0.0)
	material.spread = 17.0
	material.gravity = Vector3(0.0, -7.0, 0.0)
	material.initial_velocity_min = 22.0
	material.initial_velocity_max = 43.0
	material.scale_min = 0.28
	material.scale_max = 0.78
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 2.8
	material.color_ramp = _create_bubble_fade()
	return material


func _create_wake_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(-1.0, -0.1, 0.0)
	material.spread = 32.0
	material.gravity = Vector3(0.0, -1.4, 0.0)
	material.initial_velocity_min = 12.0
	material.initial_velocity_max = 26.0
	material.scale_min = 0.34
	material.scale_max = 0.92
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 4.2
	material.color_ramp = _create_wake_fade()
	return material


func _create_leak_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(-0.2, -1.0, 0.0)
	material.spread = 17.0
	material.gravity = Vector3(0.0, -9.0, 0.0)
	material.initial_velocity_min = 12.0
	material.initial_velocity_max = 32.0
	material.scale_min = 0.24
	material.scale_max = 0.58
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 1.8
	material.color_ramp = _create_leak_fade()
	return material


func _create_tool_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0.0, -1.0, 0.0)
	material.spread = 30.0
	material.gravity = Vector3(0.0, 12.0, 0.0)
	material.initial_velocity_min = 10.0
	material.initial_velocity_max = 24.0
	material.scale_min = 0.20
	material.scale_max = 0.52
	material.damping_min = 8.0
	material.damping_max = 16.0
	material.color = Color(0.90, 0.70, 0.34, 0.56)
	return material


func _create_cue_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(1.0, 0.0, 0.0)
	material.spread = 42.0
	material.gravity = Vector3(0.0, 10.0, 0.0)
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 48.0
	material.scale_min = 0.24
	material.scale_max = 0.72
	material.damping_min = 10.0
	material.damping_max = 22.0
	material.color = Color(0.74, 0.90, 0.76, 0.72)
	return material


func _create_bubble_fade() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.72, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.62, 0.9, 1.0, 0.0),
		Color(0.7, 0.94, 1.0, 0.62),
		Color(0.76, 0.96, 1.0, 0.46),
		Color(0.82, 0.98, 1.0, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


func _create_wake_fade() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.62, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.56, 0.86, 0.88, 0.0),
		Color(0.58, 0.88, 0.90, 0.46),
		Color(0.42, 0.70, 0.74, 0.24),
		Color(0.30, 0.54, 0.60, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


func _create_leak_fade() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.70, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.54, 0.92, 0.95, 0.0),
		Color(0.58, 0.94, 0.96, 0.70),
		Color(0.64, 0.91, 0.93, 0.42),
		Color(0.72, 0.94, 0.95, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


func _create_bubble_texture() -> ImageTexture:
	var image := Image.create(BUBBLE_TEXTURE_SIZE, BUBBLE_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(BUBBLE_TEXTURE_SIZE - 1, BUBBLE_TEXTURE_SIZE - 1) * 0.5
	var radius := float(BUBBLE_TEXTURE_SIZE) * 0.5
	for y in range(BUBBLE_TEXTURE_SIZE):
		for x in range(BUBBLE_TEXTURE_SIZE):
			var point := Vector2(x, y)
			var distance := point.distance_to(center) / radius
			var ring := 1.0 - smoothstep(0.08, 0.24, absf(distance - 0.72))
			var interior := (1.0 - smoothstep(0.0, 0.78, distance)) * 0.16
			var highlight := 1.0 - smoothstep(0.0, 0.2, point.distance_to(center + Vector2(-2.7, -2.8)) / radius)
			var alpha := clampf(maxf(ring * 0.82, maxf(interior, highlight * 0.92)), 0.0, 1.0)
			image.set_pixel(x, y, Color(0.72, 0.95, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _create_wake_texture() -> ImageTexture:
	var image := Image.create(WAKE_TEXTURE_SIZE, WAKE_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(WAKE_TEXTURE_SIZE - 1, WAKE_TEXTURE_SIZE - 1) * 0.5
	var radius := float(WAKE_TEXTURE_SIZE) * 0.5
	for y in range(WAKE_TEXTURE_SIZE):
		for x in range(WAKE_TEXTURE_SIZE):
			var distance := Vector2(x, y).distance_to(center) / radius
			var alpha := 1.0 - smoothstep(0.08, 0.92, distance)
			alpha *= alpha * 0.88
			image.set_pixel(x, y, Color(0.62, 0.90, 0.92, alpha))
	return ImageTexture.create_from_image(image)


func _create_glint_texture() -> ImageTexture:
	var image := Image.create(GLINT_TEXTURE_SIZE, GLINT_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(GLINT_TEXTURE_SIZE - 1, GLINT_TEXTURE_SIZE - 1) * 0.5
	var radius := float(GLINT_TEXTURE_SIZE) * 0.5
	for y in range(GLINT_TEXTURE_SIZE):
		for x in range(GLINT_TEXTURE_SIZE):
			var delta := Vector2(x, y) - center
			var axial := minf(absf(delta.x), absf(delta.y)) / radius
			var radial := delta.length() / radius
			var alpha := (1.0 - smoothstep(0.0, 0.32, axial)) * (1.0 - smoothstep(0.18, 1.0, radial))
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha * 0.92))
	return ImageTexture.create_from_image(image)
