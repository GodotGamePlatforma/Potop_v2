extends Node

const DiverScene := preload("res://scenes/diving/Diver.tscn")
const DiveScene := preload("res://scenes/diving/DiveScene.tscn")
const DiverSocketProfileScript := preload("res://scripts/definitions/DiverSocketProfile.gd")
const SocketProfile := preload("res://assets/diving/diver/diver_socket_profile.tres")
const DiveSessionStateScript := preload("res://scripts/data/DiveSessionState.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_test_socket_resource_contract()
	_test_pre_ready_quality_bridge()
	await _test_terminal_suppresses_action_context()
	await _test_runtime_presentation_contract()
	if _failures.is_empty():
		print("DIVER PRESENTATION TEST PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _test_socket_resource_contract() -> void:
	_check(SocketProfile != null, "Diver socket profile should load.")
	if SocketProfile == null:
		return
	var errors: PackedStringArray = SocketProfile.validation_errors()
	_check(errors.is_empty(), "Diver socket profile should validate: %s" % errors)
	var sample_count := 0
	for animation_name: StringName in DiverSocketProfileScript.REQUIRED_ANIMATIONS:
		for socket_id: StringName in DiverSocketProfileScript.REQUIRED_SOCKETS:
			for frame in range(SocketProfile.frame_count):
				var right: Vector2 = SocketProfile.position_for(animation_name, socket_id, frame, false)
				var left: Vector2 = SocketProfile.position_for(animation_name, socket_id, frame, true)
				_check(left.is_equal_approx(Vector2(-right.x, right.y)), "Socket %s/%s/%d should mirror only X." % [animation_name, socket_id, frame])
				sample_count += 1
	_check(sample_count == 288, "Diver socket profile should expose exactly 288 authored samples.")


func _test_pre_ready_quality_bridge() -> void:
	var dive := DiveScene.instantiate()
	dive.seed_user_settings_before_ready("low", true)
	var visual_effects := dive.get_node_or_null("Diver/VisualEffects")
	_check(visual_effects != null, "Dive scene should expose diver presentation VFX before ready.")
	if visual_effects != null:
		var state: Dictionary = visual_effects.graphics_quality_state()
		_check(state.get("quality") == "low", "Cold-start graphics profile should reach diver VFX before allocation.")
		_check(state.get("reduced_motion") == true, "Cold-start reduced-motion setting should reach diver VFX before allocation.")
	dive.free()


func _test_terminal_suppresses_action_context() -> void:
	var dive := DiveScene.instantiate()
	add_child(dive)
	await get_tree().process_frame
	dive.setup = ExpeditionSetupScript.new()
	dive.session = DiveSessionStateScript.new()
	dive.session.suit_condition = 100
	var live_diver := dive.get_node("Diver") as DiverController
	live_diver.set_visual_context(0.0, &"repair", 0.65, false)
	dive._ending = true
	dive._process(0.016)
	var terminal_state: Dictionary = live_diver.presentation_state()
	_check(terminal_state.get("interaction_action") == &"" and is_zero_approx(float(terminal_state.get("interaction_progress", -1.0))), "A terminal or failed-finish screen should suppress stale interaction presentation.")
	dive.queue_free()
	await get_tree().process_frame


func _test_runtime_presentation_contract() -> void:
	var diver := DiverScene.instantiate()
	var visual_effects := diver.get_node("VisualEffects")
	visual_effects.set_graphics_quality("low")
	visual_effects.set_reduced_motion(true)
	add_child(diver)
	await get_tree().process_frame

	var low_reduced: Dictionary = visual_effects.graphics_quality_state()
	_check(low_reduced.get("emitter_count") == 6, "Diver should allocate the six contextual presentation emitters.")
	_check(low_reduced.get("bubble_count") == 3, "Cold-start low/reduced should allocate the reduced bubble budget directly.")
	_check(low_reduced.get("wake_upper_count") == 1 and low_reduced.get("wake_lower_count") == 1, "Cold-start low/reduced should allocate one wake particle per fin.")
	_check(low_reduced.get("leak_count") == 1 and low_reduced.get("tool_count") == 1, "Cold-start low/reduced should allocate reduced contextual budgets.")

	visual_effects.set_graphics_quality("high")
	visual_effects.set_reduced_motion(false)
	var high: Dictionary = visual_effects.graphics_quality_state()
	_check(high.get("bubble_count") == 10, "High profile should expose the authored breath budget.")
	_check(high.get("wake_count") == 16, "High profile should split the authored wake budget across both fins.")
	_check(high.get("leak_count") == 6 and high.get("tool_count") == 6 and high.get("cue_count") == 10, "High profile should expose all contextual VFX budgets.")
	_check(float(high.get("bubble_lifetime", 99.0)) < 1.05, "A sprint breath pulse should finish before the next authored breath interval instead of restarting live particles.")

	var sprite := diver.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var breath := diver.get_node("AnimatedSprite2D/BreathSocket") as Marker2D
	sprite.play(&"swim")
	sprite.pause()
	sprite.set_frame_and_progress(5, 0.0)
	sprite.flip_h = false
	diver._update_socket_markers()
	var authored: Vector2 = SocketProfile.position_for(&"swim", &"breath", 5, false)
	_check(breath.position.is_equal_approx(authored), "Runtime breath socket should use the discrete authored sample for the visible frame.")
	sprite.flip_h = true
	diver._update_socket_markers()
	_check(breath.position.is_equal_approx(Vector2(-authored.x, authored.y)), "Runtime sockets should mirror with the diver facing direction.")

	var lantern_cone := diver.get_node("LanternCone") as Polygon2D
	var dive_light := diver.get_node("DiveLight") as PointLight2D
	sprite.flip_h = false
	diver._update_socket_markers()
	diver.set_lantern_presentation(true, Color(0.72, 0.9, 1.0, 1.0), 350.0, 1.0)
	var lantern_state: Dictionary = diver.lantern_presentation_state()
	_check(bool(lantern_state.get("visible", false)) and is_equal_approx(float(lantern_state.get("scale", 0.0)), 1.0), "Lantern I should expose its presentation cone at canonical scale.")
	_check(int(lantern_state.get("z_index", 0)) == -21 and not bool(lantern_state.get("z_as_relative", true)), "The lantern volume should remain behind semantic terrain on an absolute canvas layer.")
	_check(lantern_cone.position.is_equal_approx(diver.to_local(dive_light.global_position)) and lantern_cone.scale.x > 0.0, "The right-facing lantern cone should stay mounted at the authored lamp socket.")
	sprite.flip_h = true
	diver._update_socket_markers()
	diver._update_light_mount()
	_check(lantern_cone.position.is_equal_approx(diver.to_local(dive_light.global_position)) and lantern_cone.scale.x < 0.0, "The left-facing lantern cone should mirror around the same authored lamp socket.")
	var cone_scale_before_reduced := lantern_cone.scale
	diver.set_reduced_motion(true)
	_check(lantern_cone.visible and lantern_cone.scale.is_equal_approx(cone_scale_before_reduced), "Reduced motion must not weaken or resize the static lantern signal.")
	diver.set_lantern_presentation(false, Color.WHITE, 350.0, 0.0)
	_check(not lantern_cone.visible, "Switching the lantern off should hide only its presentation cone.")

	var wake_upper := visual_effects.get_node("WakeEmitterUpper") as GPUParticles2D
	var wake_lower := visual_effects.get_node("WakeEmitterLower") as GPUParticles2D
	diver.velocity = Vector2(90.0, 0.0)
	diver.current_velocity = Vector2(90.0, 0.0)
	visual_effects._update_wake()
	_check(not wake_upper.emitting and not wake_lower.emitting, "Passive current drift should not create fin propulsion wakes.")
	diver.velocity = Vector2(120.0, 0.0)
	diver.current_velocity = Vector2(20.0, 0.0)
	visual_effects._update_wake()
	_check(wake_upper.emitting and wake_lower.emitting, "Water-relative propulsion should create wakes at both fin sockets.")

	diver.set_visual_context(0.8, &"repair", 0.5, true)
	visual_effects._update_leak()
	visual_effects._update_tool()
	var leak := visual_effects.get_node("LeakEmitter") as GPUParticles2D
	var tool := visual_effects.get_node("ToolEmitter") as GPUParticles2D
	_check(leak.emitting and tool.emitting, "Leak and successful-work contexts should remain distinct, readable signals.")
	_check(leak.global_position.is_equal_approx(diver.visual_socket_global(&"leak_valve")), "Leak VFX should follow the authored tank-valve socket.")
	_check(tool.global_position.is_equal_approx(diver.visual_socket_global(&"tool_hand")), "Tool VFX should follow the authored hand socket.")

	var root_position: Vector2 = diver.position
	var body_shape := (diver.get_node("CollisionShape2D") as CollisionShape2D).shape
	var interaction_shape := (diver.get_node("InteractionRange/CollisionShape2D") as CollisionShape2D).shape
	diver.play_visual_cue(&"repair", diver.global_position + Vector2(80.0, -20.0), 1.0)
	diver._update_presentation_pose(0.08)
	_check(diver.position.is_equal_approx(root_position), "Presentation cues must never move the CharacterBody2D root.")
	_check((diver.get_node("CollisionShape2D") as CollisionShape2D).shape == body_shape, "Presentation cues must not replace or resize the gameplay collider.")
	_check((diver.get_node("InteractionRange/CollisionShape2D") as CollisionShape2D).shape == interaction_shape, "Presentation cues must not replace the interaction shape.")

	diver.set_visual_context(0.0, &"", 0.0, false)
	diver._clear_visual_cue()
	visual_effects.reset_presentation()
	var cleared: Dictionary = diver.presentation_state()
	_check(is_zero_approx(float(cleared.get("leak_intensity", -1.0))), "Clearing presentation context should stop the leak signal.")
	_check(cleared.get("interaction_action") == &"" and cleared.get("is_towing") == false, "Clearing presentation context should not leave stale action state.")
	for emitter_name: String in ["BreathEmitter", "WakeEmitterUpper", "WakeEmitterLower", "LeakEmitter", "ToolEmitter", "CueEmitter"]:
		_check(not (visual_effects.get_node(emitter_name) as GPUParticles2D).emitting, "Presentation reset should stop and clear %s." % emitter_name)
	diver.queue_free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
