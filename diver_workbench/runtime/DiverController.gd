class_name DiverController
extends CharacterBody2D

signal distance_travelled(distance: float)
signal surface_contacts_reported(contacts: Array)

const DiveMovementSystemScript := preload("res://scripts/diving/DiveMovementSystem.gd")
const DiverSocketProfileScript := preload("res://diver_workbench/definitions/DiverSocketProfile.gd")
const DiverFrameEnvelopeScript := preload("res://diver_workbench/definitions/DiverFrameEnvelope.gd")
const DiverCameraProfileScript := preload("res://diver_workbench/definitions/DiverCameraProfile.gd")
const DiverSuitPresentationProfileScript := preload("res://diver_workbench/definitions/DiverSuitPresentationProfile.gd")
const DIVE_PLAYER_GROUP := &"dive_player"

@export var swim_speed: float = 175.0
@export var sprint_speed: float = 265.0
@export var acceleration: float = 620.0
@export var drag: float = 760.0
@export var turn_speed: float = 10.0
@export var socket_profile: Resource
@export var frame_envelope_profile: Resource
@export var camera_profile: Resource
@export var suit_presentation_profile: Resource

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var handoff_sprite: AnimatedSprite2D = $HandoffSprite2D
@onready var action_sprite: AnimatedSprite2D = $AnimatedSprite2D/ToolHandSocket/ActionSprite2D
@onready var dive_light: PointLight2D = $DiveLight
@onready var visual_effects: Node2D = $VisualEffects
@onready var breath_socket: Marker2D = $AnimatedSprite2D/BreathSocket
@onready var fin_upper_socket: Marker2D = $AnimatedSprite2D/FinUpperSocket
@onready var fin_lower_socket: Marker2D = $AnimatedSprite2D/FinLowerSocket
@onready var tool_hand_socket: Marker2D = $AnimatedSprite2D/ToolHandSocket
@onready var lamp_socket: Marker2D = $AnimatedSprite2D/LampSocket
@onready var leak_valve_socket: Marker2D = $AnimatedSprite2D/LeakValveSocket
@onready var _visual_base_position: Vector2 = animated_sprite.position
@onready var _visual_base_scale: Vector2 = animated_sprite.scale

const REDUCED_PRESENTATION_MOTION_SCALE := 0.34
const PRESENTATION_POSE_RESPONSE := 13.0
const CAMERA_CENTER_SNAP_DISTANCE := 0.05
const CAMERA_CENTER_SNAP_SPEED := 0.05
const CAMERA_CRITICAL_DAMPING_RATE_SCALE := 1.5
const PREVIOUS_AUTHORED_SPRITE_SCALE := 0.34
const DEFAULT_VISUAL_TARGET_SIZE := Vector2(105.0, 60.0)
const TRANSITION_FRAME_COUNT := 16
const TRANSITION_HANDOFF_DURATION := 0.05
const TRANSITION_CLIPS := {
	&"idle|swim": &"transition_idle_swim",
	&"idle|sprint": &"transition_idle_sprint",
	&"swim|sprint": &"transition_swim_sprint",
}
const TRANSITION_DURATIONS := {
	&"idle>swim": 0.30,
	&"swim>idle": 0.36,
	&"idle>sprint": 0.28,
	&"sprint>idle": 0.40,
	&"swim>sprint": 0.28,
	&"sprint>swim": 0.32,
}
const TRANSITION_TARGET_ANCHORS := {
	&"idle>swim": 9,
	&"swim>idle": 13,
	&"idle>sprint": 0,
	&"sprint>idle": 7,
	&"swim>sprint": 9,
	&"sprint>swim": 11,
}
const KNIFE_WEAPON_ID := &"knife"
const KNIFE_ACTION_CLIP := &"knife_swing"
const KNIFE_CONTACT_FRAME := 6.0
const KNIFE_LEGACY_IMPACT_PROGRESS := 0.2666667
const CUE_DURATIONS := {
	&"knife_attack": 0.30,
	&"harpoon_attack": 0.36,
	&"repair": 0.62,
	&"interaction": 0.42,
	&"hit": 0.48,
}

var _input_enabled: bool = true
var _current_velocity: Vector2 = Vector2.ZERO
var _movement_input: Vector2 = Vector2.ZERO
var _is_sprinting: bool = false
var _movement_speed_multiplier: float = 1.0
var _graphics_quality := "high"
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
var _legacy_knife_aim_global := Vector2.RIGHT
var _locomotion_state: StringName = &"idle"
var _locomotion_target: StringName = &"idle"
var _transition_from: StringName = &""
var _transition_to: StringName = &""
var _transition_clip: StringName = &""
var _transition_progress := 0.0
var _transition_duration := 0.0
var _transition_forward := true
var _handoff_active := false
var _handoff_elapsed := 0.0
var _suit_quality := 1
var _legacy_knife_action_active := false
var _attack_active := false
var _attack_id := -1
var _attack_last_completed_id := -1
var _attack_weapon: StringName = &""
var _attack_progress := 0.0
var _attack_impact_progress := 0.0
var _attack_target_global := Vector2.ZERO
var _attack_aim_global := Vector2.RIGHT
var _attack_confirmed := false
var _attack_hit := false
var _attack_contact_global := Vector2.ZERO
var _attack_defeated := false
var _attack_canceled := false
var _camera_lead_world := Vector2.ZERO
var _camera_lead_velocity_world := Vector2.ZERO
var _camera_profile_valid := false
var _camera_follow_smoothing_enabled := true
var _camera_follow_smoothing_captured := false


func _ready() -> void:
	add_to_group(DIVE_PLAYER_GROUP)
	_apply_frame_envelope_profile()
	_capture_camera_follow_smoothing()
	_camera_profile_valid = _validate_camera_profile()
	if animated_sprite != null:
		animated_sprite.frame_changed.connect(_update_socket_markers)
		animated_sprite.animation_changed.connect(_update_socket_markers)
	if handoff_sprite != null:
		handoff_sprite.visible = false
		handoff_sprite.pause()
	if action_sprite != null:
		action_sprite.visible = false
		action_sprite.pause()
	_set_handoff_material_state(false, 1.0)
	_validate_suit_presentation_profile()
	_apply_suit_style()
	_update_socket_markers()
	_update_light_mount()
	_update_readability_material()
	set_graphics_quality(_graphics_quality)
	set_reduced_motion(_reduced_motion)


func _apply_frame_envelope_profile() -> void:
	if animated_sprite == null or frame_envelope_profile == null:
		return
	var configured_scale: Variant = frame_envelope_profile.get("authored_sprite_scale")
	var configured_position: Variant = frame_envelope_profile.get("authored_sprite_position")
	if configured_scale is Vector2:
		_visual_base_scale = configured_scale
	if configured_position is Vector2:
		_visual_base_position = configured_position
	_reset_presentation_pose(animated_sprite)
	if handoff_sprite != null:
		_reset_presentation_pose(handoff_sprite)


func _physics_process(delta: float) -> void:
	if _input_enabled:
		_movement_input = Input.get_vector("dive_left", "dive_right", "dive_up", "dive_down")
	else:
		_movement_input = Vector2.ZERO
	_is_sprinting = _input_enabled and Input.is_action_pressed("dive_sprint") and _movement_input.length_squared() > 0.01
	simulate_motion_tick(
		_movement_input,
		_is_sprinting,
		_current_velocity,
		_movement_speed_multiplier,
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
	_movement_input = command_input.limit_length(1.0)
	_is_sprinting = sprint_requested and _movement_input.length_squared() > 0.01
	_current_velocity = world_current
	_movement_speed_multiplier = clampf(speed_multiplier, 0.1, 1.5)
	velocity = DiveMovementSystemScript.advance_velocity(
		velocity,
		_movement_input,
		_is_sprinting,
		_current_velocity,
		_movement_speed_multiplier,
		delta,
		swim_speed,
		sprint_speed,
		acceleration,
		drag
	)

	var attempted_velocity := velocity
	var previous_position := global_position
	move_and_slide()
	var surface_contacts: Array[Dictionary] = []
	for collision_index in range(get_slide_collision_count()):
		var collision := get_slide_collision(collision_index)
		if collision == null:
			continue
		var contact_normal := collision.get_normal()
		if not contact_normal.is_finite() or contact_normal.is_zero_approx():
			continue
		surface_contacts.append({
			"collider": collision.get_collider(),
			"position": collision.get_position(),
			"normal": contact_normal.normalized(),
			"opposition_speed": maxf(-attempted_velocity.dot(contact_normal.normalized()), 0.0),
		})
	if not surface_contacts.is_empty():
		surface_contacts_reported.emit(surface_contacts)
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
	_current_velocity = Vector2.ZERO
	_movement_input = Vector2.ZERO
	_is_sprinting = false
	_movement_speed_multiplier = 1.0
	rotation = 0.0
	scale = Vector2.ONE
	if animated_sprite != null:
		animated_sprite.flip_h = false
		animated_sprite.modulate = Color.WHITE
		animated_sprite.play(&"idle")
		_reset_presentation_pose(animated_sprite)
	_locomotion_state = &"idle"
	_locomotion_target = &"idle"
	_clear_locomotion_transition()
	_clear_attack_presentation(true)
	_legacy_knife_action_active = false
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
	_reset_camera_presentation()


## Public integration boundary for root systems. Presentation children stay private
## to the avatar scene and can be reorganized without changing root paths.
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled


func stop_motion() -> void:
	_current_velocity = Vector2.ZERO
	velocity = Vector2.ZERO


func set_world_current(current: Vector2) -> void:
	_current_velocity = current


func set_movement_speed_multiplier(multiplier: float) -> void:
	_movement_speed_multiplier = clampf(multiplier, 0.1, 1.5)


func has_movement_input() -> bool:
	return _movement_input.length_squared() > 0.01


func is_sprint_active() -> bool:
	return _is_sprinting


func light_source() -> PointLight2D:
	if dive_light != null:
		return dive_light
	return get_node_or_null("DiveLight") as PointLight2D


func seed_presentation_settings_before_ready(quality_id: String, reduced_motion: bool) -> void:
	_graphics_quality = quality_id if quality_id in ["low", "medium", "high"] else "high"
	_reduced_motion = reduced_motion
	var pending_effects := get_node_or_null("VisualEffects")
	if pending_effects != null:
		if pending_effects.has_method("set_graphics_quality"):
			pending_effects.set_graphics_quality(_graphics_quality)
		if pending_effects.has_method("set_reduced_motion"):
			pending_effects.set_reduced_motion(_reduced_motion)


func set_graphics_quality(quality_id: String) -> void:
	_graphics_quality = quality_id if quality_id in ["low", "medium", "high"] else "high"
	var effects := visual_effects if visual_effects != null else get_node_or_null("VisualEffects")
	if effects != null and effects.has_method("set_graphics_quality"):
		effects.set_graphics_quality(_graphics_quality)


## Applies only the local material construction treatment. Root equipment owns
## the canonical suit quality and must explicitly bridge its value to this seam.
func set_suit_quality_presentation(value: int) -> void:
	_suit_quality = clampi(value, 1, 4)
	_apply_suit_style()


func configure_camera_world_bounds(world_size: Vector2) -> void:
	var camera := _camera_node()
	if camera == null:
		return
	camera.limit_right = int(world_size.x)
	camera.limit_bottom = int(world_size.y)
	camera.reset_smoothing()


func visual_camera_anchor() -> Vector2:
	var camera := _camera_node()
	if camera != null and camera.is_inside_tree():
		return camera.get_screen_center_position()
	return global_position

func _update_visual(delta: float) -> void:
	if animated_sprite == null:
		return
	_advance_visual_cue(delta)
	var is_swimming := _movement_input.length_squared() > 0.01
	var target_animation: StringName = &"idle"
	if is_swimming:
		target_animation = &"sprint" if _is_sprinting else &"swim"
	var target_flip := animated_sprite.flip_h
	if is_swimming and absf(_movement_input.x) > 0.05:
		target_flip = _movement_input.x < 0.0
	_set_visual_flip_preserving_heading(target_flip)
	_advance_locomotion_graph(target_animation, delta)
	_update_presentation_pose(delta)
	_update_socket_markers()
	var target_rotation := 0.0
	if is_swimming:
		target_rotation = _movement_input.angle()
		if animated_sprite.flip_h:
			target_rotation = wrapf(target_rotation - PI, -PI, PI)
	rotation = lerp_angle(rotation, target_rotation, minf(1.0, delta * turn_speed))
	# Repeated Transform2D angle decomposition can accumulate a tiny uniform scale
	# drift. The gameplay root contract is exactly unit scale, so reassert it after
	# every authored orientation update instead of letting presentation affect shape.
	scale = Vector2.ONE
	_update_action_sprite()
	_update_light_mount()
	_update_readability_material()
	_update_camera_look_ahead(delta)


func _advance_locomotion_graph(desired_state: StringName, delta: float) -> void:
	_locomotion_target = desired_state
	if _transition_clip.is_empty():
		if desired_state != _locomotion_state:
			_begin_locomotion_transition(_locomotion_state, desired_state)
		elif animated_sprite.animation != _locomotion_state:
			animated_sprite.play(_locomotion_state)
			_set_animation_phase(animated_sprite, 0.0)
	else:
		if desired_state == _transition_from:
			_reverse_locomotion_transition()
		elif desired_state != _transition_to:
			_redirect_locomotion_transition(desired_state)
	if not _transition_clip.is_empty():
		_transition_progress = minf(
			_transition_progress + maxf(delta, 0.0) / maxf(_transition_duration, 0.001),
			1.0
		)
		_sample_transition_frame()
		_advance_handoff(delta)
		if _transition_progress >= 1.0:
			_finish_locomotion_transition()


func _begin_locomotion_transition(from_state: StringName, to_state: StringName) -> void:
	var clip := _transition_clip_for(from_state, to_state)
	if clip.is_empty():
		_locomotion_state = to_state
		animated_sprite.play(to_state)
		_set_animation_phase(animated_sprite, 0.0)
		return
	_begin_handoff_from(animated_sprite)
	_transition_from = from_state
	_transition_to = to_state
	_transition_clip = clip
	_transition_progress = 0.0
	_transition_duration = float(
		TRANSITION_DURATIONS.get(_directed_transition_key(from_state, to_state), 0.32)
	)
	_transition_forward = _transition_is_forward(from_state, to_state)
	animated_sprite.play(_transition_clip)
	animated_sprite.pause()
	_sample_transition_frame()
	animated_sprite.modulate = Color.WHITE


func _reverse_locomotion_transition() -> void:
	var previous_from := _transition_from
	_transition_from = _transition_to
	_transition_to = previous_from
	_transition_progress = 1.0 - _transition_progress
	_transition_forward = not _transition_forward
	_transition_duration = float(
		TRANSITION_DURATIONS.get(
			_directed_transition_key(_transition_from, _transition_to),
			0.32
		)
	)
	_sample_transition_frame()


func _redirect_locomotion_transition(new_target: StringName) -> void:
	var dominant_state := _transition_from if _transition_progress < 0.5 else _transition_to
	_begin_handoff_from(animated_sprite)
	_locomotion_state = dominant_state
	_clear_locomotion_transition(false)
	_begin_locomotion_transition(dominant_state, new_target)


func _sample_transition_frame() -> void:
	if animated_sprite == null or _transition_clip.is_empty():
		return
	var authored_progress := _transition_progress if _transition_forward else 1.0 - _transition_progress
	var frame_position := clampf(authored_progress, 0.0, 1.0) * float(TRANSITION_FRAME_COUNT - 1)
	var frame_index := mini(int(floor(frame_position + 0.000001)), TRANSITION_FRAME_COUNT - 1)
	animated_sprite.set_frame_and_progress(frame_index, frame_position - float(frame_index))
	animated_sprite.pause()


func _finish_locomotion_transition() -> void:
	var target_state := _transition_to
	var anchor_frame := int(
		TRANSITION_TARGET_ANCHORS.get(
			_directed_transition_key(_transition_from, target_state),
			0
		)
	)
	_locomotion_state = target_state
	animated_sprite.play(target_state)
	_set_animation_phase(animated_sprite, float(anchor_frame) / 16.0)
	_clear_locomotion_transition()


func _clear_locomotion_transition(clear_handoff: bool = true) -> void:
	_transition_from = &""
	_transition_to = &""
	_transition_clip = &""
	_transition_progress = 0.0
	_transition_duration = 0.0
	_transition_forward = true
	if clear_handoff:
		_handoff_active = false
		_handoff_elapsed = 0.0
		if handoff_sprite != null:
			handoff_sprite.visible = false
		_set_handoff_material_state(false, 1.0)


func _begin_handoff_from(source: AnimatedSprite2D) -> void:
	if source == null or handoff_sprite == null:
		return
	handoff_sprite.animation = source.animation
	handoff_sprite.set_frame_and_progress(source.frame, source.frame_progress)
	handoff_sprite.flip_h = source.flip_h
	handoff_sprite.position = source.position
	handoff_sprite.rotation = source.rotation
	handoff_sprite.scale = source.scale
	handoff_sprite.modulate = source.modulate
	handoff_sprite.pause()
	handoff_sprite.visible = true
	_handoff_active = true
	_handoff_elapsed = 0.0
	_set_handoff_material_state(true, 0.0)


func _advance_handoff(delta: float) -> void:
	if not _handoff_active:
		return
	_handoff_elapsed += maxf(delta, 0.0)
	var mix_value := clampf(_handoff_elapsed / TRANSITION_HANDOFF_DURATION, 0.0, 1.0)
	_set_handoff_material_state(true, mix_value)
	if mix_value >= 1.0:
		_handoff_active = false
		if handoff_sprite != null:
			handoff_sprite.visible = false
		_set_handoff_material_state(false, 1.0)


func _transition_clip_for(from_state: StringName, to_state: StringName) -> StringName:
	return TRANSITION_CLIPS.get(_transition_pair_key(from_state, to_state), &"")


func _transition_pair_key(first: StringName, second: StringName) -> StringName:
	if first == second:
		return &""
	if first in [&"idle", &"swim"] and second in [&"idle", &"swim"]:
		return &"idle|swim"
	if first in [&"idle", &"sprint"] and second in [&"idle", &"sprint"]:
		return &"idle|sprint"
	if first in [&"swim", &"sprint"] and second in [&"swim", &"sprint"]:
		return &"swim|sprint"
	return &""


func _transition_is_forward(from_state: StringName, to_state: StringName) -> bool:
	var pair := _transition_pair_key(from_state, to_state)
	return (
		(pair == &"idle|swim" and from_state == &"idle")
		or (pair == &"idle|sprint" and from_state == &"idle")
		or (pair == &"swim|sprint" and from_state == &"swim")
	)


func _directed_transition_key(from_state: StringName, to_state: StringName) -> StringName:
	return StringName("%s>%s" % [from_state, to_state])


## Horizontal mirroring changes the sprite's local forward vector by PI. Rebase
## the CharacterBody2D angle at the same instant so the visible world heading is
## continuous while steering crosses the vertical axis. The capsule is centrally
## symmetric, therefore this representation-only rebase does not change contact.
func _set_visual_flip_preserving_heading(target_flip: bool) -> void:
	if animated_sprite == null:
		return
	if animated_sprite.flip_h != target_flip:
		rotation = wrapf(rotation + PI, -PI, PI)
		animated_sprite.flip_h = target_flip
	if handoff_sprite != null:
		handoff_sprite.flip_h = target_flip


func set_reduced_motion(enabled: bool) -> void:
	_capture_camera_follow_smoothing()
	var was_reduced := _reduced_motion
	_reduced_motion = enabled
	var camera := _camera_node()
	if camera != null:
		camera.position_smoothing_enabled = _camera_follow_smoothing_enabled and not _reduced_motion
	if _reduced_motion:
		_reset_camera_presentation()
	elif was_reduced and camera != null and camera.is_inside_tree():
		camera.reset_smoothing()
	_update_presentation_pose(0.0)
	_update_socket_markers()
	_update_light_mount()
	_update_readability_material()
	var effects := visual_effects if visual_effects != null else get_node_or_null("VisualEffects")
	if effects != null and effects.has_method("set_reduced_motion"):
		effects.set_reduced_motion(_reduced_motion)


func _validate_camera_profile() -> bool:
	if camera_profile == null or camera_profile.get_script() != DiverCameraProfileScript:
		return false
	var errors: PackedStringArray = camera_profile.validation_errors()
	if not errors.is_empty():
		push_warning("Invalid DiverCameraProfile: %s" % errors)
		return false
	return true


func _camera_node() -> Camera2D:
	return get_node_or_null("Camera2D") as Camera2D


func _capture_camera_follow_smoothing() -> void:
	if _camera_follow_smoothing_captured:
		return
	var camera := _camera_node()
	if camera == null:
		return
	_camera_follow_smoothing_enabled = camera.position_smoothing_enabled
	_camera_follow_smoothing_captured = true


func _reset_camera_presentation() -> void:
	_camera_lead_world = Vector2.ZERO
	_camera_lead_velocity_world = Vector2.ZERO
	var camera := _camera_node()
	if camera == null:
		return
	camera.position = Vector2.ZERO
	if camera.is_inside_tree():
		camera.reset_smoothing()


func _update_camera_look_ahead(delta: float) -> void:
	var camera := _camera_node()
	if camera == null:
		return
	if not _camera_profile_valid:
		_camera_profile_valid = _validate_camera_profile()
	var target_lead := Vector2.ZERO
	var propulsion_speed := 0.0
	if _camera_profile_valid and not _reduced_motion and _movement_input.length_squared() > 0.01:
		var input_direction := _movement_input.normalized()
		var propulsion_velocity := velocity - _current_velocity
		if propulsion_velocity.is_finite() and not propulsion_velocity.is_zero_approx():
			var propulsion_direction := propulsion_velocity.normalized()
			var alignment := propulsion_direction.dot(input_direction)
			var minimum_intent_alignment := float(camera_profile.get("minimum_intent_alignment"))
			var intent_weight := _camera_intent_weight(alignment, minimum_intent_alignment)
			if intent_weight > 0.0:
				var movement_dead_zone := float(camera_profile.get("movement_dead_zone"))
				var authored_speed := sprint_speed if _is_sprinting else swim_speed
				var intended_speed_limit := authored_speed * _movement_speed_multiplier * _movement_input.length()
				propulsion_speed = clampf(propulsion_velocity.dot(input_direction), 0.0, intended_speed_limit)
				if propulsion_speed > movement_dead_zone:
					var lead_distance := _camera_lead_distance(propulsion_speed)
					target_lead = propulsion_direction * lead_distance * intent_weight

	var response := float(camera_profile.get("recenter_response")) if _camera_profile_valid else 1.0
	if not target_lead.is_zero_approx():
		response = _camera_movement_response(propulsion_speed)
	_smooth_camera_lead(target_lead, response, delta)
	if (
		target_lead.is_zero_approx()
		and _camera_lead_world.length() <= CAMERA_CENTER_SNAP_DISTANCE
		and _camera_lead_velocity_world.length() <= CAMERA_CENTER_SNAP_SPEED
	):
		_camera_lead_world = Vector2.ZERO
		_camera_lead_velocity_world = Vector2.ZERO
	camera.position = to_local(global_position + _camera_lead_world)
	# The controller owns the only temporal filter. Keep Camera2D's authored flag as
	# the reduced-motion integration seam, but synchronize its cache once per physics
	# tick so the engine smoother cannot add a second, frame-dependent lag layer.
	if camera.is_inside_tree() and camera.position_smoothing_enabled:
		camera.reset_smoothing()


func _camera_intent_weight(alignment: float, minimum_alignment: float) -> float:
	if alignment < minimum_alignment:
		return 0.0
	if minimum_alignment >= 1.0:
		return 1.0
	return smoothstep(minimum_alignment, 1.0, clampf(alignment, minimum_alignment, 1.0))


func _smooth_camera_lead(target_lead: Vector2, response: float, delta: float) -> void:
	var step := maxf(delta, 0.0)
	# Match the settling window of the profile's original exponential rates while
	# using a critically damped trajectory with continuous camera-lead velocity.
	var frequency := maxf(response, 0.0) * CAMERA_CRITICAL_DAMPING_RATE_SCALE
	if step <= 0.0 or frequency <= 0.0:
		return

	var displacement := _camera_lead_world - target_lead
	var to_target := -displacement
	if not to_target.is_zero_approx():
		var target_direction := to_target.normalized()
		var closing_speed := _camera_lead_velocity_world.dot(target_direction)
		if closing_speed < 0.0:
			# A changed target may put the retained spring velocity on the wrong side
			# of the new route. Remove only that separating component so release and
			# a 180-degree turn move toward the new target on their very first tick.
			_camera_lead_velocity_world -= target_direction * closing_speed

	var spring_term := _camera_lead_velocity_world + displacement * frequency
	var decay := exp(-frequency * step)
	_camera_lead_world = target_lead + (displacement + spring_term * step) * decay
	_camera_lead_velocity_world = (
		_camera_lead_velocity_world - spring_term * frequency * step
	) * decay
	if not _camera_lead_world.is_finite() or not _camera_lead_velocity_world.is_finite():
		_camera_lead_world = target_lead
		_camera_lead_velocity_world = Vector2.ZERO


func _camera_lead_distance(speed: float) -> float:
	var movement_dead_zone := float(camera_profile.get("movement_dead_zone"))
	var swim_distance := float(camera_profile.get("swim_lead_distance"))
	var sprint_distance := float(camera_profile.get("sprint_lead_distance"))
	var swim_reference := maxf(swim_speed, movement_dead_zone + 0.001)
	var sprint_reference := maxf(sprint_speed, swim_reference + 0.001)
	if speed <= swim_reference:
		var swim_weight := smoothstep(movement_dead_zone, swim_reference, speed)
		return swim_distance * swim_weight
	var sprint_weight := smoothstep(swim_reference, sprint_reference, speed)
	return lerpf(swim_distance, sprint_distance, sprint_weight)


func _camera_movement_response(speed: float) -> float:
	var swim_response := float(camera_profile.get("swim_response"))
	var sprint_response := float(camera_profile.get("sprint_response"))
	var swim_reference := maxf(swim_speed, 0.001)
	var sprint_reference := maxf(sprint_speed, swim_reference + 0.001)
	return lerpf(swim_response, sprint_response, smoothstep(swim_reference, sprint_reference, speed))


## Compatibility seam for the root controller. The canonical LightSystem writes
## every emission property directly to light_source(); the avatar only guarantees
## that this single radial source remains centered on its physical root.
func set_lantern_presentation(_enabled: bool, _color: Color, _outer_radius: float, _energy: float) -> void:
	_update_light_mount()


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
	_legacy_knife_action_active = cue == &"knife_attack" and not _attack_active
	var global_direction := target_global_position - global_position
	if global_direction.length_squared() <= 0.001:
		global_direction = Vector2(-1.0 if animated_sprite != null and animated_sprite.flip_h else 1.0, -0.18)
	var local_target := to_local(global_position + global_direction.normalized())
	var local_origin := to_local(global_position)
	_cue_direction_local = (local_target - local_origin).normalized()
	_legacy_knife_aim_global = global_direction.normalized()
	if visual_effects != null and visual_effects.has_method("play_cue"):
		visual_effects.play_cue(cue, target_global_position, _cue_strength)
	_update_action_sprite()


## Presentation-only lifecycle. Root combat supplies the already-resolved target,
## timing and result; this API never performs overlap queries or applies damage.
func begin_attack_presentation(
	attack_id: int,
	weapon_id: StringName,
	target_global_position: Vector2,
	impact_progress: float
) -> bool:
	if attack_id <= 0 or weapon_id != KNIFE_WEAPON_ID:
		return false
	if (
		not target_global_position.is_finite()
		or global_position.distance_squared_to(target_global_position) <= 0.000001
		or not is_finite(impact_progress)
		or impact_progress < 0.05
		or impact_progress > 0.95
	):
		return false
	if _attack_active:
		if attack_id != _attack_id:
			return false
		return (
			weapon_id == _attack_weapon
			and target_global_position.is_equal_approx(_attack_target_global)
			and is_equal_approx(impact_progress, _attack_impact_progress)
		)
	if attack_id <= _attack_last_completed_id:
		return false
	_attack_active = true
	_attack_id = attack_id
	_attack_weapon = weapon_id
	_attack_progress = 0.0
	_attack_impact_progress = impact_progress
	_attack_target_global = target_global_position
	_attack_aim_global = (target_global_position - global_position).normalized()
	_attack_confirmed = false
	_attack_hit = false
	_attack_contact_global = Vector2.ZERO
	_attack_defeated = false
	_attack_canceled = false
	_legacy_knife_action_active = false
	_update_action_sprite()
	_update_readability_material()
	return true


func set_attack_presentation_progress(attack_id: int, normalized_progress: float) -> bool:
	if not _attack_active or attack_id != _attack_id or not is_finite(normalized_progress):
		return false
	var clamped_progress := clampf(normalized_progress, 0.0, 1.0)
	if clamped_progress + 0.000001 < _attack_progress:
		return false
	_attack_progress = maxf(_attack_progress, clamped_progress)
	_update_action_sprite()
	_update_readability_material()
	return true


func confirm_attack_presentation(
	attack_id: int,
	hit: bool,
	contact_global_position: Vector2,
	defeated: bool
) -> bool:
	if not _attack_active or attack_id != _attack_id or _attack_confirmed:
		return false
	if defeated and not hit:
		return false
	if hit and not contact_global_position.is_finite():
		return false
	_attack_confirmed = true
	_attack_hit = hit
	_attack_contact_global = contact_global_position if contact_global_position.is_finite() else _attack_target_global
	_attack_defeated = defeated
	_update_readability_material()
	return true


func end_attack_presentation(attack_id: int, canceled: bool = false) -> bool:
	if not _attack_active or attack_id != _attack_id:
		return false
	_attack_active = false
	_attack_last_completed_id = maxi(_attack_last_completed_id, attack_id)
	_attack_canceled = canceled
	_legacy_knife_action_active = false
	if _cue_kind == &"knife_attack":
		_clear_visual_cue()
	if action_sprite != null:
		action_sprite.visible = false
	_update_readability_material()
	return true


func _clear_attack_presentation(reset_serial: bool) -> void:
	_attack_active = false
	_attack_weapon = &""
	_attack_progress = 0.0
	_attack_impact_progress = 0.0
	_attack_target_global = Vector2.ZERO
	_attack_aim_global = Vector2.RIGHT
	_attack_confirmed = false
	_attack_hit = false
	_attack_contact_global = Vector2.ZERO
	_attack_defeated = false
	_attack_canceled = false
	_legacy_knife_action_active = false
	if reset_serial:
		_attack_id = -1
		_attack_last_completed_id = -1
	if action_sprite != null:
		action_sprite.visible = false


func _update_action_sprite() -> void:
	if action_sprite == null or animated_sprite == null or tool_hand_socket == null:
		return
	var legacy_active := (
		_legacy_knife_action_active
		and _cue_kind == &"knife_attack"
		and _cue_duration > 0.0
		and _cue_elapsed < _cue_duration
	)
	if not _attack_active and not legacy_active:
		action_sprite.visible = false
		return
	var normalized_progress := _attack_progress
	var impact_progress := _attack_impact_progress
	var aim_global := _attack_aim_global
	if not _attack_active:
		normalized_progress = clampf(_cue_elapsed / maxf(_cue_duration, 0.001), 0.0, 1.0)
		impact_progress = KNIFE_LEGACY_IMPACT_PROGRESS
		aim_global = _legacy_knife_aim_global
	var authored_progress := _knife_authored_progress(normalized_progress, impact_progress)
	var frame_count := action_sprite.sprite_frames.get_frame_count(KNIFE_ACTION_CLIP)
	var frame_position := authored_progress * float(maxi(frame_count - 1, 0))
	var frame_index := mini(int(floor(frame_position + 0.000001)), maxi(frame_count - 1, 0))
	action_sprite.animation = KNIFE_ACTION_CLIP
	action_sprite.set_frame_and_progress(frame_index, frame_position - float(frame_index))
	action_sprite.pause()
	# The authored knife points left. A fixed horizontal mirror establishes +X
	# as its local forward axis; full local rotation then supports every aim angle.
	action_sprite.flip_h = true
	var local_direction := tool_hand_socket.to_local(tool_hand_socket.global_position + aim_global)
	action_sprite.rotation = local_direction.angle() if not local_direction.is_zero_approx() else 0.0
	action_sprite.visible = true


func _knife_authored_progress(normalized_progress: float, impact_progress: float) -> float:
	var progress := clampf(normalized_progress, 0.0, 1.0)
	var impact := clampf(impact_progress, 0.05, 0.95)
	var authored_contact := KNIFE_CONTACT_FRAME / float(TRANSITION_FRAME_COUNT - 1)
	if progress <= impact:
		return (progress / impact) * authored_contact
	return authored_contact + ((progress - impact) / (1.0 - impact)) * (1.0 - authored_contact)


func visual_socket_global(socket_id: StringName) -> Vector2:
	var marker := _marker_for_socket(socket_id)
	if marker == null:
		return global_position
	return marker.global_position


func action_visual_alpha_bounds() -> Rect2:
	if action_sprite == null or not action_sprite.visible:
		return Rect2()
	var source_bounds: Rect2 = DiverFrameEnvelopeScript.bounds_for(
		action_sprite.animation,
		action_sprite.frame
	)
	if source_bounds.size.is_zero_approx():
		return Rect2()
	source_bounds = source_bounds.grow(DiverFrameEnvelopeScript.READABILITY_RIM_SOURCE_PADDING)
	var source_corners := PackedVector2Array([
		source_bounds.position,
		Vector2(source_bounds.end.x, source_bounds.position.y),
		source_bounds.end,
		Vector2(source_bounds.position.x, source_bounds.end.y),
	])
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for source_corner in source_corners:
		var corner := source_corner
		if action_sprite.flip_h:
			corner.x = -corner.x
		var root_corner := to_local(action_sprite.to_global(corner))
		minimum = minimum.min(root_corner)
		maximum = maximum.max(root_corner)
	return Rect2(minimum, maximum - minimum)


func presentation_state() -> Dictionary:
	return {
		"leak_intensity": _leak_intensity,
		"interaction_action": _interaction_action,
		"interaction_progress": _interaction_progress,
		"is_towing": _is_towing,
		"cue": _cue_kind,
		"cue_time_left": maxf(_cue_duration - _cue_elapsed, 0.0),
		"suit_quality": _suit_quality,
		"locomotion_state": _locomotion_state,
		"locomotion_target": _locomotion_target,
		"transition_clip": _transition_clip,
		"transition_progress": _transition_progress,
		"transition_duration": _transition_duration,
		"transition_forward": _transition_forward,
		"handoff_active": _handoff_active,
		"attack_active": _attack_active,
		"attack_id": _attack_id,
		"attack_last_completed_id": _attack_last_completed_id,
		"attack_weapon": _attack_weapon,
		"attack_progress": _attack_progress,
		"attack_impact_progress": _attack_impact_progress,
		"attack_confirmed": _attack_confirmed,
		"attack_hit": _attack_hit,
		"attack_contact_global": _attack_contact_global,
		"attack_defeated": _attack_defeated,
		"attack_canceled": _attack_canceled,
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
	_synchronize_handoff_pose()


func _synchronize_handoff_pose() -> void:
	if not _handoff_active or handoff_sprite == null or not handoff_sprite.visible:
		return
	handoff_sprite.flip_h = animated_sprite.flip_h
	handoff_sprite.rotation = animated_sprite.rotation
	handoff_sprite.scale = animated_sprite.scale
	handoff_sprite.position = animated_sprite.position
	var local_main := _transformed_alpha_bounds(
		animated_sprite,
		animated_sprite.scale,
		animated_sprite.rotation
	)
	var local_handoff := _transformed_alpha_bounds(
		handoff_sprite,
		handoff_sprite.scale,
		handoff_sprite.rotation
	)
	var local_union := local_main.merge(local_handoff)
	var fit_scale := minf(
		1.0,
		minf(
			_visual_target_size().x / maxf(local_union.size.x, 0.001),
			_visual_target_size().y / maxf(local_union.size.y, 0.001)
		)
	)
	if fit_scale < 1.0:
		animated_sprite.scale *= fit_scale
		handoff_sprite.scale = animated_sprite.scale
		local_main = _transformed_alpha_bounds(
			animated_sprite,
			animated_sprite.scale,
			animated_sprite.rotation
		)
		local_handoff = _transformed_alpha_bounds(
			handoff_sprite,
			handoff_sprite.scale,
			handoff_sprite.rotation
		)
		local_union = local_main.merge(local_handoff)
	var intended_position := _authored_visual_position(animated_sprite) + _visual_pose_offset
	var half_envelope := _visual_target_size() * 0.5
	var minimum_position := -half_envelope - local_union.position
	var maximum_position := half_envelope - local_union.end
	var fitted_position := Vector2(
		clampf(intended_position.x, minimum_position.x, maximum_position.x),
		clampf(intended_position.y, minimum_position.y, maximum_position.y)
	)
	animated_sprite.position = fitted_position
	handoff_sprite.position = fitted_position


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
	var translation_scale := _presentation_translation_scale()
	var action_pose := _action_pose_for(sprite)
	return {
		"offset": (local_offset * motion_scale + action_pose["offset"]) * translation_scale,
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
	if _attack_active:
		var attack_envelope := sin(clampf(_attack_progress, 0.0, 1.0) * PI)
		var local_attack_direction := to_local(global_position + _attack_aim_global) - to_local(global_position)
		if not local_attack_direction.is_zero_approx():
			local_attack_direction = local_attack_direction.normalized()
		offset += local_attack_direction * (3.8 * attack_envelope * decoration_scale)
		roll += local_attack_direction.y * 0.040 * attack_envelope * decoration_scale
		pose_scale *= Vector2(1.0 + 0.012 * attack_envelope, 1.0 - 0.006 * attack_envelope)
	if _cue_duration > 0.0 and _cue_elapsed < _cue_duration:
		var normalized := clampf(_cue_elapsed / _cue_duration, 0.0, 1.0)
		var cue_motion_scale := 0.62 if _reduced_motion else 1.0
		var envelope := sin(normalized * PI) * _cue_strength * cue_motion_scale
		match _cue_kind:
			&"knife_attack":
				if _legacy_knife_action_active:
					var legacy_direction_local := (
						to_local(global_position + _legacy_knife_aim_global)
						- to_local(global_position)
					).normalized()
					offset += legacy_direction_local * (5.4 * envelope)
					roll += legacy_direction_local.y * 0.055 * envelope
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
	sprite.rotation = _visual_pose_rotation
	var intended_scale := _visual_base_scale * _visual_pose_scale
	var local_bounds := _transformed_alpha_bounds(sprite, intended_scale, sprite.rotation)
	var fit_scale := minf(
		1.0,
		minf(
			_visual_target_size().x / maxf(local_bounds.size.x, 0.001),
			_visual_target_size().y / maxf(local_bounds.size.y, 0.001)
		)
	)
	sprite.scale = intended_scale * fit_scale
	local_bounds = _transformed_alpha_bounds(sprite, sprite.scale, sprite.rotation)
	var intended_position := _authored_visual_position(sprite) + _visual_pose_offset
	var half_envelope: Vector2 = _visual_target_size() * 0.5
	var minimum_position := -half_envelope - local_bounds.position
	var maximum_position := half_envelope - local_bounds.end
	sprite.position = Vector2(
		clampf(intended_position.x, minimum_position.x, maximum_position.x),
		clampf(intended_position.y, minimum_position.y, maximum_position.y)
	)


func _reset_presentation_pose(sprite: AnimatedSprite2D) -> void:
	if sprite == null:
		return
	sprite.position = _authored_visual_position(sprite)
	sprite.rotation = 0.0
	sprite.scale = _visual_base_scale


func _presentation_translation_scale() -> float:
	return minf(absf(_visual_base_scale.x), absf(_visual_base_scale.y)) / PREVIOUS_AUTHORED_SPRITE_SCALE


func _visual_target_size() -> Vector2:
	if frame_envelope_profile != null:
		var configured: Vector2 = frame_envelope_profile.get("target_size")
		if configured.x > 0.0 and configured.y > 0.0:
			return configured
	return DEFAULT_VISUAL_TARGET_SIZE


func _authored_visual_position(sprite: AnimatedSprite2D) -> Vector2:
	if sprite != null and sprite.flip_h:
		return Vector2(-_visual_base_position.x, _visual_base_position.y)
	return _visual_base_position


func _transformed_alpha_bounds(
	sprite: AnimatedSprite2D,
	visual_scale: Vector2,
	visual_rotation: float
) -> Rect2:
	var source_bounds: Rect2 = DiverFrameEnvelopeScript.bounds_for(sprite.animation, sprite.frame)
	if source_bounds.size.is_zero_approx():
		return Rect2()
	source_bounds = source_bounds.grow(DiverFrameEnvelopeScript.READABILITY_RIM_SOURCE_PADDING)
	var source_corners := PackedVector2Array([
		source_bounds.position,
		Vector2(source_bounds.end.x, source_bounds.position.y),
		source_bounds.end,
		Vector2(source_bounds.position.x, source_bounds.end.y),
	])
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for source_corner in source_corners:
		var corner := source_corner
		if sprite.flip_h:
			corner.x = -corner.x
		corner = (corner * visual_scale).rotated(visual_rotation)
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


func _current_visual_alpha_bounds() -> Rect2:
	if animated_sprite == null:
		return Rect2()
	var bounds := _visual_bounds_for_sprite(animated_sprite)
	if _handoff_active and handoff_sprite != null and handoff_sprite.visible:
		bounds = bounds.merge(_visual_bounds_for_sprite(handoff_sprite))
	return bounds


func _visual_bounds_for_sprite(sprite: AnimatedSprite2D) -> Rect2:
	if sprite == null:
		return Rect2()
	var local_bounds := _transformed_alpha_bounds(sprite, sprite.scale, sprite.rotation)
	return Rect2(sprite.position + local_bounds.position, local_bounds.size)


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
	_legacy_knife_aim_global = Vector2.RIGHT
	_legacy_knife_action_active = false
	if not _attack_active and action_sprite != null:
		action_sprite.visible = false


func _update_socket_markers() -> void:
	if animated_sprite == null or socket_profile == null:
		return
	for socket_id in DiverSocketProfileScript.REQUIRED_SOCKETS:
		var marker := _marker_for_socket(socket_id)
		if marker == null:
			continue
		var target_position: Vector2 = socket_profile.position_for(
			animated_sprite.animation,
			socket_id,
			animated_sprite.frame,
			animated_sprite.flip_h
		)
		if _handoff_active and handoff_sprite != null and handoff_sprite.visible:
			var source_position: Vector2 = socket_profile.position_for(
				handoff_sprite.animation,
				socket_id,
				handoff_sprite.frame,
				handoff_sprite.flip_h
			)
			var handoff_mix := clampf(
				_handoff_elapsed / TRANSITION_HANDOFF_DURATION,
				0.0,
				1.0
			)
			target_position = source_position.lerp(target_position, handoff_mix)
		marker.position = target_position


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
	if dive_light == null:
		return
	dive_light.position = Vector2.ZERO


func _update_readability_material() -> void:
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
	if _attack_active:
		var attack_envelope := sin(clampf(_attack_progress, 0.0, 1.0) * PI)
		action_glow = maxf(action_glow, 0.24 + attack_envelope * 0.24)
		var contact_reached := _attack_progress + 0.000001 >= _attack_impact_progress
		action_color = (
			Color("f0c56b")
			if _attack_confirmed and _attack_hit and contact_reached
			else Color("79ded4")
		)
	var damage_flash := cue_phase * 0.46 if _cue_kind == &"hit" else 0.0
	if _reduced_motion:
		action_glow *= 0.72
		damage_flash *= 0.72
	for shader_material in _readability_materials():
		shader_material.set_shader_parameter(&"action_glow", clampf(action_glow, 0.0, 1.0))
		shader_material.set_shader_parameter(&"damage_flash", clampf(damage_flash, 0.0, 1.0))
		shader_material.set_shader_parameter(&"action_color", action_color)


func _validate_suit_presentation_profile() -> bool:
	if (
		suit_presentation_profile == null
		or suit_presentation_profile.get_script() != DiverSuitPresentationProfileScript
	):
		push_warning("Missing or invalid DiverSuitPresentationProfile.")
		return false
	var errors: PackedStringArray = suit_presentation_profile.validation_errors()
	if not errors.is_empty():
		push_warning("Invalid DiverSuitPresentationProfile: %s" % errors)
		return false
	return true


func _apply_suit_style() -> void:
	if suit_presentation_profile == null or not suit_presentation_profile.has_method("style_for"):
		return
	var style: Dictionary = suit_presentation_profile.style_for(_suit_quality)
	for shader_material in _suit_materials():
		shader_material.set_shader_parameter(&"suit_fabric_color", style["fabric_color"])
		shader_material.set_shader_parameter(&"suit_metal_color", style["metal_color"])
		shader_material.set_shader_parameter(&"suit_pattern_color", style["pattern_color"])
		shader_material.set_shader_parameter(&"rim_color", style["rim_color"])
		shader_material.set_shader_parameter(&"suit_style", float(style["style_id"]))
		shader_material.set_shader_parameter(&"suit_fabric_mix", style["fabric_mix"])
		shader_material.set_shader_parameter(&"suit_metal_mix", style["metal_mix"])
		shader_material.set_shader_parameter(&"suit_pattern_strength", style["pattern_strength"])
		shader_material.set_shader_parameter(&"suit_plate_strength", style["plate_strength"])
		shader_material.set_shader_parameter(&"suit_emissive_strength", style["emissive_strength"])
		shader_material.set_shader_parameter(&"accent_strength", style["accent_strength"])
		shader_material.set_shader_parameter(&"outline_width", style["outline_width"])


func _suit_materials() -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	var main_sprite := (
		animated_sprite
		if animated_sprite != null
		else get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	)
	var old_sprite := (
		handoff_sprite
		if handoff_sprite != null
		else get_node_or_null("HandoffSprite2D") as AnimatedSprite2D
	)
	for sprite in [main_sprite, old_sprite]:
		var shader_material := _material_for_sprite(sprite)
		if shader_material != null and shader_material not in materials:
			materials.append(shader_material)
	return materials


func _set_handoff_material_state(enabled: bool, mix_value: float) -> void:
	var main_material := _material_for_sprite(
		animated_sprite
		if animated_sprite != null
		else get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	)
	var old_material := _material_for_sprite(
		handoff_sprite
		if handoff_sprite != null
		else get_node_or_null("HandoffSprite2D") as AnimatedSprite2D
	)
	if main_material != null:
		main_material.set_shader_parameter(&"handoff_enabled", enabled)
		main_material.set_shader_parameter(&"handoff_mix", clampf(mix_value, 0.0, 1.0))
		main_material.set_shader_parameter(&"handoff_role", 1.0)
	if old_material != null:
		old_material.set_shader_parameter(&"handoff_enabled", enabled)
		old_material.set_shader_parameter(&"handoff_mix", clampf(mix_value, 0.0, 1.0))
		old_material.set_shader_parameter(&"handoff_role", 0.0)


func _readability_materials() -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	var main_sprite := (
		animated_sprite
		if animated_sprite != null
		else get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	)
	var old_sprite := (
		handoff_sprite
		if handoff_sprite != null
		else get_node_or_null("HandoffSprite2D") as AnimatedSprite2D
	)
	var weapon_sprite := (
		action_sprite
		if action_sprite != null
		else get_node_or_null("AnimatedSprite2D/ToolHandSocket/ActionSprite2D") as AnimatedSprite2D
	)
	for sprite in [main_sprite, old_sprite, weapon_sprite]:
		var shader_material := _material_for_sprite(sprite)
		if shader_material != null and shader_material not in materials:
			materials.append(shader_material)
	return materials


func _material_for_sprite(sprite: AnimatedSprite2D) -> ShaderMaterial:
	if sprite != null and sprite.material is ShaderMaterial:
		return sprite.material as ShaderMaterial
	return null
