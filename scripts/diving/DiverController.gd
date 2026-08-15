class_name DiverController
extends CharacterBody2D

signal distance_travelled(distance: float)

const DiveMovementSystemScript := preload("res://scripts/diving/DiveMovementSystem.gd")
const DiverSocketProfileScript := preload("res://scripts/definitions/DiverSocketProfile.gd")

@export var swim_speed: float = 175.0
@export var sprint_speed: float = 265.0
@export var acceleration: float = 620.0
@export var drag: float = 760.0
@export var turn_speed: float = 10.0
@export var socket_profile: Resource

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var dive_light: PointLight2D = $DiveLight
@onready var visual_effects: Node2D = $VisualEffects
@onready var breath_socket: Marker2D = $AnimatedSprite2D/BreathSocket
@onready var fin_upper_socket: Marker2D = $AnimatedSprite2D/FinUpperSocket
@onready var fin_lower_socket: Marker2D = $AnimatedSprite2D/FinLowerSocket
@onready var tool_hand_socket: Marker2D = $AnimatedSprite2D/ToolHandSocket
@onready var lamp_socket: Marker2D = $AnimatedSprite2D/LampSocket
@onready var leak_valve_socket: Marker2D = $AnimatedSprite2D/LeakValveSocket
@onready var _visual_base_scale: Vector2 = animated_sprite.scale

const LIGHT_MOUNT_FORWARD_OFFSET := 62.0
const REDUCED_PRESENTATION_MOTION_SCALE := 0.34
const PRESENTATION_POSE_RESPONSE := 13.0
const CUE_DURATIONS := {
	&"knife_attack": 0.30,
	&"harpoon_attack": 0.36,
	&"repair": 0.62,
	&"interaction": 0.42,
	&"hit": 0.48,
}

var input_enabled: bool = true
var current_velocity: Vector2 = Vector2.ZERO
var movement_input: Vector2 = Vector2.ZERO
var is_sprinting: bool = false
var movement_speed_multiplier: float = 1.0
var _reduced_motion := false
var _visual_pose_offset := Vector2.ZERO
var _visual_pose_rotation := 0.0
var _visual_pose_scale := Vector2.ONE
var _leak_intensity := 0.0
var _interaction_action: StringName = &""
var _interaction_progress := 0.0
var _is_towing := false
var _cue_kind: StringName = &""
var _cue_elapsed := 0.0
var _cue_duration := 0.0
var _cue_strength := 0.0
var _cue_direction_local := Vector2.RIGHT


func _ready() -> void:
	if animated_sprite != null:
		animated_sprite.frame_changed.connect(_update_socket_markers)
		animated_sprite.animation_changed.connect(_update_socket_markers)
	_update_socket_markers()
	_update_light_mount()
	_update_readability_material()

func _physics_process(delta: float) -> void:
	if input_enabled:
		movement_input = Input.get_vector("dive_left", "dive_right", "dive_up", "dive_down")
	else:
		movement_input = Vector2.ZERO
	is_sprinting = input_enabled and Input.is_action_pressed("dive_sprint") and movement_input.length_squared() > 0.01
	simulate_motion_tick(
		movement_input,
		is_sprinting,
		current_velocity,
		movement_speed_multiplier,
		delta,
		true
	)


## Public deterministic seam used by both live input and headless route replay.
## The caller supplies the command and environment; collision resolution still
## goes through this CharacterBody2D's real move_and_slide().
func simulate_motion_tick(
	command_input: Vector2,
	sprint_requested: bool,
	world_current: Vector2,
	speed_multiplier: float,
	delta: float,
	update_visual: bool = false
) -> Dictionary:
	movement_input = command_input.limit_length(1.0)
	is_sprinting = sprint_requested and movement_input.length_squared() > 0.01
	current_velocity = world_current
	movement_speed_multiplier = clampf(speed_multiplier, 0.1, 1.5)
	velocity = DiveMovementSystemScript.advance_velocity(
		velocity,
		movement_input,
		is_sprinting,
		current_velocity,
		movement_speed_multiplier,
		delta,
		swim_speed,
		sprint_speed,
		acceleration,
		drag
	)

	var previous_position := global_position
	move_and_slide()
	var travelled := global_position.distance_to(previous_position)
	if travelled > 0.01:
		distance_travelled.emit(travelled)
	if update_visual:
		_update_visual(delta)
	return {
		"previous_position": previous_position,
		"position": global_position,
		"velocity": velocity,
		"travelled": travelled,
		"collided": get_slide_collision_count() > 0,
		"collision_count": get_slide_collision_count(),
	}

func reset_at(world_position: Vector2) -> void:
	global_position = world_position
	velocity = Vector2.ZERO
	current_velocity = Vector2.ZERO
	movement_input = Vector2.ZERO
	is_sprinting = false
	movement_speed_multiplier = 1.0
	rotation = 0.0
	if animated_sprite != null:
		animated_sprite.flip_h = false
		animated_sprite.modulate = Color.WHITE
		animated_sprite.play(&"idle")
		_reset_presentation_pose(animated_sprite)
	_visual_pose_offset = Vector2.ZERO
	_visual_pose_rotation = 0.0
	_visual_pose_scale = Vector2.ONE
	_leak_intensity = 0.0
	_interaction_action = &""
	_interaction_progress = 0.0
	_is_towing = false
	_clear_visual_cue()
	if visual_effects != null and visual_effects.has_method("reset_presentation"):
		visual_effects.reset_presentation()
	_update_socket_markers()
	_update_light_mount()
	_update_readability_material()
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.reset_smoothing()

func _update_visual(delta: float) -> void:
	if animated_sprite == null:
		return
	_advance_visual_cue(delta)
	var is_swimming := movement_input.length_squared() > 0.01
	var target_animation: StringName = &"idle"
	if is_swimming:
		target_animation = &"sprint" if is_sprinting else &"swim"
	var target_flip := animated_sprite.flip_h
	if is_swimming and absf(movement_input.x) > 0.05:
		target_flip = movement_input.x < 0.0
	if animated_sprite.animation != target_animation:
		_switch_animation_preserving_phase(target_animation, target_flip)
	else:
		animated_sprite.flip_h = target_flip
	_update_presentation_pose(delta)
	_update_socket_markers()
	_update_light_mount()
	_update_readability_material()
	var target_rotation := 0.0
	if is_swimming:
		target_rotation = movement_input.angle()
		if animated_sprite.flip_h:
			target_rotation = wrapf(target_rotation - PI, -PI, PI)
	rotation = lerp_angle(rotation, target_rotation, minf(1.0, delta * turn_speed))


func _switch_animation_preserving_phase(target_animation: StringName, target_flip: bool) -> void:
	var normalized_phase := _animation_phase(animated_sprite)
	animated_sprite.flip_h = target_flip
	animated_sprite.play(target_animation)
	_set_animation_phase(animated_sprite, normalized_phase)
	animated_sprite.modulate = Color.WHITE


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_update_presentation_pose(0.0)
	_update_socket_markers()
	_update_light_mount()
	_update_readability_material()


## Receives presentation-only values derived from the canonical dive session.
## None of them is used by movement, collision, interaction timing or damage.
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
	if visual_effects != null and visual_effects.has_method("set_visual_context"):
		visual_effects.set_visual_context(
			_leak_intensity,
			_interaction_action,
			_interaction_progress,
			_is_towing
		)


func play_visual_cue(
	cue: StringName,
	target_global_position: Vector2,
	strength: float = 1.0
) -> void:
	if not CUE_DURATIONS.has(cue):
		return
	_cue_kind = cue
	_cue_elapsed = 0.0
	_cue_duration = float(CUE_DURATIONS[cue])
	_cue_strength = clampf(strength, 0.0, 1.5)
	var global_direction := target_global_position - global_position
	if global_direction.length_squared() <= 0.001:
		global_direction = Vector2(-1.0 if animated_sprite != null and animated_sprite.flip_h else 1.0, -0.18)
	var local_target := to_local(global_position + global_direction.normalized())
	var local_origin := to_local(global_position)
	_cue_direction_local = (local_target - local_origin).normalized()
	if visual_effects != null and visual_effects.has_method("play_cue"):
		visual_effects.play_cue(cue, target_global_position, _cue_strength)


func visual_socket_global(socket_id: StringName) -> Vector2:
	var marker := _marker_for_socket(socket_id)
	if marker == null:
		return global_position
	return marker.global_position


func presentation_state() -> Dictionary:
	return {
		"leak_intensity": _leak_intensity,
		"interaction_action": _interaction_action,
		"interaction_progress": _interaction_progress,
		"is_towing": _is_towing,
		"cue": _cue_kind,
		"cue_time_left": maxf(_cue_duration - _cue_elapsed, 0.0),
	}


func _update_presentation_pose(delta: float) -> void:
	if animated_sprite == null:
		return
	var target_pose := _presentation_pose_for(animated_sprite)
	var target_offset: Vector2 = target_pose["offset"]
	var target_rotation: float = float(target_pose["rotation"])
	var target_scale: Vector2 = target_pose["scale"]
	var blend := 1.0 if delta <= 0.0 else 1.0 - exp(-PRESENTATION_POSE_RESPONSE * delta)
	_visual_pose_offset = _visual_pose_offset.lerp(target_offset, blend)
	_visual_pose_rotation = lerpf(_visual_pose_rotation, target_rotation, blend)
	_visual_pose_scale = _visual_pose_scale.lerp(target_scale, blend)
	_apply_presentation_pose(animated_sprite)


func _presentation_pose_for(sprite: AnimatedSprite2D) -> Dictionary:
	if sprite == null:
		return {"offset": Vector2.ZERO, "rotation": 0.0, "scale": Vector2.ONE}
	var phase := _animation_phase(sprite) * TAU
	var primary_wave := sin(phase)
	var secondary_wave := sin(phase * 2.0 + 0.65)
	var forward_wave := cos(phase)
	var local_offset := Vector2.ZERO
	var local_roll := 0.0
	var stretch := Vector2.ONE
	match sprite.animation:
		&"idle":
			local_offset = Vector2(forward_wave * 0.35, primary_wave * 1.55)
			local_roll = primary_wave * 0.012 + secondary_wave * 0.003
			stretch = Vector2(1.0 + secondary_wave * 0.005, 1.0 - primary_wave * 0.010)
		&"sprint":
			var thrust := (forward_wave + 1.0) * 0.5
			local_offset = Vector2(forward_wave * 2.55, primary_wave * 1.95)
			local_roll = primary_wave * 0.026 + secondary_wave * 0.006
			stretch = Vector2(1.012 + thrust * 0.012, 0.992 - thrust * 0.006)
		_:
			local_offset = Vector2(forward_wave * 1.15, primary_wave * 2.15)
			local_roll = primary_wave * 0.020 + secondary_wave * 0.005
			stretch = Vector2(1.0 + forward_wave * 0.014, 1.0 - primary_wave * 0.018)
	var facing := -1.0 if sprite.flip_h else 1.0
	local_offset.x *= facing
	local_roll *= facing
	var motion_scale := REDUCED_PRESENTATION_MOTION_SCALE if _reduced_motion else 1.0
	var action_pose := _action_pose_for(sprite)
	return {
		"offset": local_offset * motion_scale + action_pose["offset"],
		"rotation": local_roll * motion_scale + float(action_pose["rotation"]),
		"scale": (
			Vector2.ONE + (stretch - Vector2.ONE) * motion_scale
		) * Vector2(action_pose["scale"]),
	}


func _action_pose_for(sprite: AnimatedSprite2D) -> Dictionary:
	var offset := Vector2.ZERO
	var roll := 0.0
	var pose_scale := Vector2.ONE
	var decoration_scale := REDUCED_PRESENTATION_MOTION_SCALE if _reduced_motion else 1.0
	var facing := -1.0 if sprite.flip_h else 1.0
	if _is_towing:
		offset += Vector2(-3.2 * facing, 2.0) * decoration_scale
		roll -= 0.030 * facing * decoration_scale
		pose_scale *= Vector2(0.994, 1.008)
	if _interaction_progress > 0.0:
		var work_pulse := sin(_interaction_progress * PI * 5.0)
		offset += Vector2(0.8 * facing, 1.2 + work_pulse * 0.75) * decoration_scale
		roll += (0.012 + work_pulse * 0.010) * facing * decoration_scale
		pose_scale *= Vector2(1.004, 0.998)
	if _cue_duration > 0.0 and _cue_elapsed < _cue_duration:
		var normalized := clampf(_cue_elapsed / _cue_duration, 0.0, 1.0)
		var cue_motion_scale := 0.62 if _reduced_motion else 1.0
		var envelope := sin(normalized * PI) * _cue_strength * cue_motion_scale
		match _cue_kind:
			&"knife_attack":
				offset += _cue_direction_local * (5.4 * envelope)
				roll += _cue_direction_local.y * 0.055 * envelope
				pose_scale *= Vector2(1.0 + 0.018 * envelope, 1.0 - 0.010 * envelope)
			&"harpoon_attack":
				offset -= _cue_direction_local * (3.2 * envelope)
				roll -= _cue_direction_local.y * 0.036 * envelope
			&"repair":
				offset += Vector2(0.0, 2.2 * envelope)
				roll += facing * 0.025 * envelope
				pose_scale *= Vector2(0.996, 1.0 + 0.012 * envelope)
			&"interaction":
				offset += Vector2(1.4 * facing, -1.1) * envelope
			&"hit":
				offset -= _cue_direction_local * (4.8 * envelope)
				roll += facing * 0.045 * envelope
				pose_scale *= Vector2(1.0 - 0.012 * envelope, 1.0 + 0.018 * envelope)
	return {"offset": offset, "rotation": roll, "scale": pose_scale}


func _apply_presentation_pose(sprite: AnimatedSprite2D) -> void:
	if sprite == null:
		return
	sprite.position = _visual_pose_offset
	sprite.rotation = _visual_pose_rotation
	sprite.scale = _visual_base_scale * _visual_pose_scale


func _reset_presentation_pose(sprite: AnimatedSprite2D) -> void:
	if sprite == null:
		return
	sprite.position = Vector2.ZERO
	sprite.rotation = 0.0
	sprite.scale = _visual_base_scale


func _animation_phase(sprite: AnimatedSprite2D) -> float:
	if sprite == null or sprite.sprite_frames == null:
		return 0.0
	var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
	if frame_count <= 0:
		return 0.0
	return fposmod((float(sprite.frame) + sprite.frame_progress) / float(frame_count), 1.0)


func _set_animation_phase(sprite: AnimatedSprite2D, normalized_phase: float) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var frame_count := sprite.sprite_frames.get_frame_count(sprite.animation)
	if frame_count <= 0:
		return
	var frame_position := fposmod(normalized_phase, 1.0) * float(frame_count)
	var frame_index := mini(int(floor(frame_position)), frame_count - 1)
	sprite.set_frame_and_progress(frame_index, frame_position - float(frame_index))


func _advance_visual_cue(delta: float) -> void:
	if _cue_duration <= 0.0:
		return
	_cue_elapsed += maxf(delta, 0.0)
	if _cue_elapsed >= _cue_duration:
		_clear_visual_cue()


func _clear_visual_cue() -> void:
	_cue_kind = &""
	_cue_elapsed = 0.0
	_cue_duration = 0.0
	_cue_strength = 0.0
	_cue_direction_local = Vector2.RIGHT


func _update_socket_markers() -> void:
	if animated_sprite == null or socket_profile == null:
		return
	for socket_id in DiverSocketProfileScript.REQUIRED_SOCKETS:
		var marker := _marker_for_socket(socket_id)
		if marker == null:
			continue
		marker.position = socket_profile.position_for(
			animated_sprite.animation,
			socket_id,
			animated_sprite.frame,
			animated_sprite.flip_h
		)


func _marker_for_socket(socket_id: StringName) -> Marker2D:
	match socket_id:
		&"breath":
			return breath_socket
		&"fin_upper":
			return fin_upper_socket
		&"fin_lower":
			return fin_lower_socket
		&"tool_hand":
			return tool_hand_socket
		&"lamp":
			return lamp_socket
		&"leak_valve":
			return leak_valve_socket
	return null


func _update_light_mount() -> void:
	if dive_light == null or animated_sprite == null:
		return
	if lamp_socket != null and socket_profile != null:
		dive_light.global_position = lamp_socket.global_position
	else:
		dive_light.position = Vector2(-LIGHT_MOUNT_FORWARD_OFFSET if animated_sprite.flip_h else LIGHT_MOUNT_FORWARD_OFFSET, 0.0)


func _update_readability_material() -> void:
	if animated_sprite == null or not (animated_sprite.material is ShaderMaterial):
		return
	var shader_material := animated_sprite.material as ShaderMaterial
	var cue_phase := 0.0
	if _cue_duration > 0.0 and _cue_elapsed < _cue_duration:
		cue_phase = sin(clampf(_cue_elapsed / _cue_duration, 0.0, 1.0) * PI) * _cue_strength
	var action_glow := 0.0
	var action_color := Color("e9a93d")
	if _interaction_progress > 0.0:
		action_glow = 0.18 + 0.10 * sin(_interaction_progress * PI * 5.0)
		action_color = Color("75d7d0") if _interaction_action == &"repair" else Color("e9b958")
	if _cue_kind in [&"knife_attack", &"harpoon_attack", &"repair", &"interaction"]:
		action_glow = maxf(action_glow, cue_phase * (0.42 if _cue_kind == &"harpoon_attack" else 0.30))
		action_color = Color("e8bd66") if _cue_kind == &"harpoon_attack" else Color("79ded4")
	var damage_flash := cue_phase * 0.46 if _cue_kind == &"hit" else 0.0
	if _reduced_motion:
		action_glow *= 0.72
		damage_flash *= 0.72
	shader_material.set_shader_parameter(&"action_glow", clampf(action_glow, 0.0, 1.0))
	shader_material.set_shader_parameter(&"damage_flash", clampf(damage_flash, 0.0, 1.0))
	shader_material.set_shader_parameter(&"action_color", action_color)
