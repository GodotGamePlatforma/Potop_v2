extends Area2D

const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")

@export var control_id: String = ""
@export var display_name: String = "Sterowanie konstrukcji"
@export var interaction_seconds: float = 0.8
@export var required_tool: String = ""
@export var interaction_action: String = "activate"

var _activation_callback := Callable()
var _available := false
var _focused := false
var _progress := 0.0
var _visual_size := Vector2(72.0, 48.0)
var _interaction_extent := Vector2(72.0, 48.0)
var _interaction_shape_size := Vector2(72.0, 48.0)
var _visual_kind: StringName = &"default"
var _visual_role: StringName = &"default"
var _visual_state := "locked"
var _visual_telemetry: Dictionary = {}
var _animation_phase := 0.0
var _power_lever_id := ""
var _power_lever_position := "up"


func configure(definition: Dictionary, socket_rect: Rect2, activation_callback: Callable) -> void:
	control_id = str(definition.get("id", ""))
	display_name = str(definition.get("display_name", control_id))
	interaction_seconds = maxf(float(definition.get("interaction_seconds", 0.8)), 0.1)
	required_tool = str(definition.get("required_tool", ""))
	interaction_action = str(definition.get("interaction_action", "activate"))
	_activation_callback = activation_callback
	position = socket_rect.get_center()
	_interaction_extent = socket_rect.size
	_visual_size = Vector2(
		clampf(socket_rect.size.x, 48.0, 320.0),
		clampf(socket_rect.size.y, 40.0, 120.0)
	)
	_interaction_shape_size = socket_rect.size
	_visual_role = StringName(str(definition.get("visual_role", definition.get("kind", "default"))))
	z_index = 8
	set_meta(&"structure_control_id", control_id)
	set_meta(&"socket_rect", socket_rect)
	set_meta(&"native_visual_size", _visual_size)
	set_meta(&"native_visual_rect", Rect2(-_visual_size * 0.5, _visual_size))
	set_meta(&"visual_role", _visual_role)
	set_visual_state(_visual_role, "locked")


func configure_power_lever(
	panel_control_id: String,
	lever_definition: Dictionary,
	interaction_seconds_value: float,
	interaction_action_value: String,
	lever_rect: Rect2,
	activation_callback: Callable
) -> void:
	_power_lever_id = str(lever_definition.get("id", ""))
	var lever_display_name := str(lever_definition.get("display_name", _power_lever_id))
	configure({
		"id": "%s:%s" % [panel_control_id, _power_lever_id],
		"display_name": lever_display_name,
		"interaction_seconds": interaction_seconds_value,
		"interaction_action": interaction_action_value,
		"visual_role": "power_lever",
	}, lever_rect, activation_callback)
	_visual_kind = &"power_lever"
	_visual_role = &"power_lever"
	_interaction_shape_size = lever_rect.size
	_visual_size = lever_rect.size
	set_meta(&"power_lever_id", _power_lever_id)
	set_meta(&"visual_role", _visual_role)
	set_power_lever_position(str(lever_definition.get("initial_position", "up")))


func _ready() -> void:
	add_to_group(&"dive_interactable")
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	monitorable = true
	_build_interaction_shape()
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if _focused or _visual_state.begins_with("ready") or _visual_state in ["fault", "contact_closed", "latched", "completed", "bolt_released", "open"]:
		_animation_phase = fmod(_animation_phase + maxf(delta, 0.0) * 3.6, TAU)
		queue_redraw()


func set_available(available: bool) -> void:
	if _available == available:
		return
	_available = available
	if not _available:
		_focused = false
		_progress = 0.0
	set_meta(&"available", _available)
	queue_redraw()


func set_visual_state(role: StringName, state: String, telemetry: Dictionary = {}) -> void:
	_visual_role = role
	_visual_state = state
	_visual_telemetry = telemetry.duplicate(true)
	_animation_phase = 0.0
	set_meta(&"visual_role", _visual_role)
	set_meta(&"visual_state", _visual_state)
	set_meta(&"visual_telemetry", _visual_telemetry)
	queue_redraw()


func visual_role() -> StringName:
	return _visual_role


func visual_state() -> String:
	return _visual_state


func visual_telemetry() -> Dictionary:
	return _visual_telemetry.duplicate(true)


func can_interact() -> bool:
	return _available and _activation_callback.is_valid()


func interaction_distance_to(world_position: Vector2) -> float:
	var local_delta := to_local(world_position)
	var half_extent := _interaction_extent * 0.5
	var outside := Vector2(
		maxf(absf(local_delta.x) - half_extent.x, 0.0),
		maxf(absf(local_delta.y) - half_extent.y, 0.0)
	)
	return outside.length()


func interaction_text() -> String:
	if _visual_kind == &"power_lever":
		var target_position := "dół" if _power_lever_position == "up" else "górę"
		return "Przytrzymaj %s: %s → %s" % [
			InputPromptScript.action_text(&"dive_interact"),
			display_name.to_lower(),
			target_position,
		]
	return "Przytrzymaj %s: %s" % [
		InputPromptScript.action_text(&"dive_interact"),
		display_name.to_lower(),
	]


func required_tool_display_name() -> String:
	return required_tool.replace("_", " ")


func set_interaction_presentation(focused: bool, progress: float) -> void:
	_focused = focused and _available
	_progress = clampf(progress, 0.0, 1.0) if _focused else 0.0
	queue_redraw()


func set_power_lever_position(position_name: String) -> void:
	if position_name != "up" and position_name != "down":
		return
	_power_lever_position = position_name
	set_meta(&"power_lever_position", _power_lever_position)
	queue_redraw()


func power_lever_position() -> String:
	return _power_lever_position


func complete_dive_interaction() -> Dictionary:
	if not can_interact():
		return {
			"success": false,
			"message": "To sterowanie nie jest teraz dostępne.",
			"interaction_action": interaction_action,
		}
	var callback_result: Variant = _activation_callback.call(control_id)
	var result: Dictionary = callback_result as Dictionary if callback_result is Dictionary else {}
	result["success"] = bool(result.get("success", false))
	result["message"] = str(result.get("message", "Sterowanie nie odpowiedziało."))
	result["interaction_action"] = str(result.get("interaction_action", interaction_action))
	result["control_id"] = control_id
	return result


func _build_interaction_shape() -> void:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		collision = CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		add_child(collision)
	var shape := RectangleShape2D.new()
	shape.size = _interaction_shape_size
	collision.shape = shape


func _draw() -> void:
	match _visual_role:
		&"power_lever":
			_draw_power_lever()
		&"red_relay_bank":
			_draw_red_relay()
		&"trolley_interlock":
			_draw_trolley_interlock()
		&"pressure_equalization", &"actuator_power", &"bolt_release":
			_draw_d_station()
		&"d_reset_guard":
			_draw_d_reset()
		&"archive_access":
			_draw_archive_access()
		_:
			_draw_default_control()


func _draw_default_control() -> void:
	var half := _visual_size * 0.5
	var panel := Rect2(-half, _visual_size).grow(-3.0)
	var edge := _state_color()
	draw_rect(panel, Color(0.10, 0.18, 0.20, 1.0), true)
	draw_rect(panel, edge, false, 5.0)
	draw_circle(Vector2(-half.x + 18.0, 0.0), minf(_visual_size.y * 0.16, 11.0), edge)
	_draw_progress_bar(half)


func _draw_red_relay() -> void:
	var half := _visual_size * 0.5
	var panel := Rect2(-half, _visual_size).grow(-4.0)
	var edge := _state_color(Color(0.88, 0.28, 0.25, 1.0))
	draw_rect(panel, Color(0.055, 0.105, 0.12, 1.0), true)
	draw_rect(panel, edge.darkened(0.32), false, 7.0)
	draw_rect(panel.grow(-8.0), Color(0.36, 0.43, 0.42, 1.0), false, 3.0)
	var usable_width := _visual_size.x - 52.0
	draw_line(Vector2(-half.x + 20.0, -half.y + 28.0), Vector2(half.x - 20.0, -half.y + 28.0), Color(0.48, 0.28, 0.17, 1.0), 7.0)
	draw_line(Vector2(-half.x + 20.0, half.y - 28.0), Vector2(half.x - 20.0, half.y - 28.0), Color(0.32, 0.22, 0.17, 1.0), 7.0)
	for relay_index: int in range(3):
		var center := Vector2(-usable_width * 0.33 + usable_width * 0.33 * float(relay_index), -4.0)
		var relay_rect := Rect2(center - Vector2(28.0, 27.0), Vector2(56.0, 54.0))
		draw_rect(relay_rect, Color(0.12, 0.18, 0.19, 1.0), true)
		draw_rect(relay_rect, Color(0.52, 0.42, 0.34, 1.0), false, 4.0)
		draw_circle(center + Vector2(-15.0, -12.0), 7.0, Color(0.72, 0.70, 0.60, 1.0))
		draw_circle(center + Vector2(15.0, -12.0), 7.0, Color(0.72, 0.70, 0.60, 1.0))
		for coil_index: int in range(4):
			var coil_y := center.y + 4.0 + float(coil_index) * 6.0
			draw_line(Vector2(center.x - 17.0, coil_y), Vector2(center.x + 17.0, coil_y), Color(0.50, 0.27, 0.16, 1.0), 3.0)
		var arm_y := center.y + (8.0 if _visual_state == "latched" else -2.0)
		draw_line(Vector2(center.x - 20.0, arm_y), Vector2(center.x + 20.0, arm_y - 5.0), edge.darkened(0.15), 6.0)
	draw_circle(Vector2(half.x - 20.0, -half.y + 20.0), 8.0, edge.darkened(0.12))
	_draw_progress_bar(half)


func _draw_trolley_interlock() -> void:
	var half := _visual_size * 0.5
	var panel := Rect2(-half, _visual_size).grow(-4.0)
	var edge := _state_color(Color(0.28, 0.68, 0.92, 1.0))
	draw_rect(panel, Color(0.055, 0.13, 0.17, 1.0), true)
	draw_rect(panel, edge.darkened(0.28), false, 7.0)
	draw_rect(panel.grow(-8.0), Color(0.40, 0.49, 0.50, 1.0), false, 3.0)
	draw_line(Vector2(-half.x + 24.0, -28.0), Vector2(half.x - 24.0, -28.0), Color(0.27, 0.46, 0.54, 1.0), 11.0)
	draw_line(Vector2(-half.x + 24.0, 28.0), Vector2(half.x - 24.0, 28.0), Color(0.27, 0.46, 0.54, 1.0), 11.0)
	var contact_closed := bool(_visual_telemetry.get("contact_closed", false))
	var left_contact := Vector2(-46.0, 0.0)
	var right_contact := Vector2(46.0, 0.0)
	for contact_y: float in [-18.0, 0.0, 18.0]:
		draw_circle(left_contact + Vector2(0.0, contact_y), 8.0, Color(0.67, 0.48, 0.30, 1.0))
		draw_circle(right_contact + Vector2(0.0, contact_y), 8.0, Color(0.67, 0.48, 0.30, 1.0))
	var fork_end_x := right_contact.x if contact_closed else 18.0
	draw_line(Vector2(left_contact.x, -18.0), Vector2(fork_end_x, -18.0), edge.darkened(0.12), 8.0)
	draw_line(Vector2(left_contact.x, 18.0), Vector2(fork_end_x, 18.0), edge.darkened(0.12), 8.0)
	draw_line(Vector2(fork_end_x, -18.0), Vector2(fork_end_x, 18.0), edge.darkened(0.12), 8.0)
	draw_line(Vector2(right_contact.x + 12.0, -32.0), Vector2(half.x - 24.0, -4.0), Color(0.42, 0.48, 0.44, 1.0), 7.0)
	if contact_closed:
		draw_circle(Vector2.ZERO, 27.0 + sin(_animation_phase) * 1.5, Color(edge.r, edge.g, edge.b, 0.32), false, 4.0)
	_draw_progress_bar(half)


func _draw_d_station() -> void:
	var half := _visual_size * 0.5
	var panel := Rect2(-half, _visual_size).grow(-3.0)
	var accent := Color(0.82, 0.57, 0.24, 1.0)
	if _visual_role == &"pressure_equalization":
		accent = Color(0.35, 0.76, 0.78, 1.0)
	elif _visual_role == &"actuator_power":
		accent = Color(0.90, 0.64, 0.24, 1.0)
	elif _visual_role == &"bolt_release":
		accent = Color(0.64, 0.76, 0.38, 1.0)
	var edge := _state_color(accent)
	draw_rect(panel, Color(0.06, 0.12, 0.14, 1.0), true)
	draw_rect(panel, edge.darkened(0.28), false, 6.0)
	draw_rect(panel.grow(-8.0), Color(0.39, 0.47, 0.46, 1.0), false, 3.0)
	match _visual_role:
		&"pressure_equalization":
			_draw_pressure_station(half, edge)
		&"actuator_power":
			_draw_actuator_station(half, edge)
		_:
			_draw_bolt_station(half, edge)
	_draw_progress_bar(half)


func _draw_pressure_station(half: Vector2, edge: Color) -> void:
	var completed := _visual_state in ["completed", "bolt_released"]
	var wheel_radius := minf(_visual_size.x, _visual_size.y) * 0.25
	var wheel_angle := 0.72 if completed else sin(_animation_phase) * 0.035
	draw_circle(Vector2(0.0, 9.0), wheel_radius + 8.0, Color(0.13, 0.19, 0.19, 1.0))
	draw_circle(Vector2(0.0, 9.0), wheel_radius, Color(0.055, 0.09, 0.10, 1.0))
	draw_circle(Vector2(0.0, 9.0), wheel_radius, edge.darkened(0.08), false, 7.0)
	for spoke_index: int in range(6):
		var angle := wheel_angle + float(spoke_index) * TAU / 6.0
		draw_line(Vector2(0.0, 9.0), Vector2(0.0, 9.0) + Vector2(cos(angle), sin(angle)) * wheel_radius, edge.darkened(0.14), 5.0)
	draw_circle(Vector2(0.0, 9.0), 8.0, Color(0.68, 0.43, 0.22, 1.0))
	var gauge_center := Vector2(0.0, -half.y + 22.0)
	draw_arc(gauge_center, 16.0, PI, TAU, 18, Color(0.69, 0.78, 0.75, 1.0), 4.0)
	var needle_angle := -2.55 if not completed else -0.62
	draw_line(gauge_center, gauge_center + Vector2(cos(needle_angle), sin(needle_angle)) * 13.0, Color(0.66, 0.39, 0.18, 1.0), 3.0)


func _draw_actuator_station(half: Vector2, edge: Color) -> void:
	var completed := _visual_state in ["completed", "bolt_released"]
	var body_rect := Rect2(Vector2(-38.0, -22.0), Vector2(76.0, 44.0))
	draw_rect(body_rect, Color(0.13, 0.20, 0.21, 1.0), true)
	draw_rect(body_rect, Color(0.48, 0.53, 0.49, 1.0), false, 5.0)
	for coil_index: int in range(6):
		var x := -27.0 + float(coil_index) * 11.0
		draw_line(Vector2(x, -17.0), Vector2(x, 17.0), Color(0.50, 0.29, 0.16, 1.0), 4.0)
	var piston_end := 43.0 if completed else 20.0 + sin(_animation_phase) * 1.5
	draw_line(Vector2(0.0, 22.0), Vector2(0.0, piston_end), edge.darkened(0.08), 10.0)
	draw_rect(Rect2(Vector2(-18.0, piston_end - 4.0), Vector2(36.0, 12.0)), Color(0.46, 0.49, 0.44, 1.0), true)
	draw_line(Vector2(-half.x + 16.0, -half.y + 25.0), Vector2(-44.0, -12.0), Color(0.31, 0.46, 0.49, 1.0), 7.0)
	draw_line(Vector2(half.x - 16.0, -half.y + 25.0), Vector2(44.0, -12.0), Color(0.31, 0.46, 0.49, 1.0), 7.0)


func _draw_bolt_station(half: Vector2, edge: Color) -> void:
	var released := _visual_state == "bolt_released"
	var housing := Rect2(Vector2(-42.0, -20.0), Vector2(84.0, 40.0))
	draw_rect(housing, Color(0.11, 0.18, 0.19, 1.0), true)
	draw_rect(housing, Color(0.49, 0.53, 0.48, 1.0), false, 5.0)
	var bolt_x := 15.0 if released else 40.0
	draw_line(Vector2(-38.0, 0.0), Vector2(bolt_x, 0.0), edge.darkened(0.12), 13.0)
	draw_rect(Rect2(Vector2(bolt_x - 5.0, -16.0), Vector2(14.0, 32.0)), Color(0.58, 0.43, 0.27, 1.0), true)
	var lever_angle := -0.74 if released else 0.52 + sin(_animation_phase) * 0.025
	var pivot := Vector2(-22.0, 30.0)
	draw_circle(pivot, 10.0, Color(0.54, 0.39, 0.24, 1.0))
	draw_line(pivot, pivot + Vector2(cos(lever_angle), sin(lever_angle)) * 46.0, edge.darkened(0.08), 9.0)
	draw_line(Vector2(half.x - 18.0, -half.y + 18.0), Vector2(half.x - 18.0, half.y - 18.0), Color(0.35, 0.29, 0.21, 1.0), 6.0)


func _draw_d_reset() -> void:
	var half := _visual_size * 0.5
	var panel := Rect2(-half, _visual_size).grow(-3.0)
	var edge := _state_color(Color(0.95, 0.66, 0.20, 1.0))
	draw_rect(panel, Color(0.08, 0.12, 0.13, 1.0), true)
	draw_rect(panel, edge, false, 5.0)
	for stripe_index: int in range(6):
		var x := -half.x + float(stripe_index) * 40.0
		draw_line(Vector2(x, -half.y + 8.0), Vector2(x + 28.0, half.y - 8.0), Color(0.46, 0.32, 0.13, 1.0), 8.0)
	draw_circle(Vector2.ZERO, minf(half.y - 14.0, 22.0), Color(0.58, 0.12, 0.10, 1.0))
	draw_circle(Vector2.ZERO, minf(half.y - 14.0, 22.0), edge, false, 5.0)
	_draw_progress_bar(half)


func _draw_archive_access() -> void:
	var half := _visual_size * 0.5
	var panel := Rect2(-half, _visual_size).grow(-3.0)
	var edge := _state_color(Color(0.58, 0.72, 0.68, 1.0))
	draw_rect(panel, Color(0.07, 0.14, 0.16, 1.0), true)
	draw_rect(panel, edge, false, 6.0)
	var radius := minf(_visual_size.y * 0.32, 34.0)
	draw_circle(Vector2.ZERO, radius, Color(0.10, 0.20, 0.22, 1.0))
	draw_circle(Vector2.ZERO, radius, Color(0.62, 0.49, 0.31, 1.0), false, 6.0)
	for spoke_index: int in range(6):
		var angle := float(spoke_index) * TAU / 6.0
		draw_line(Vector2.ZERO, Vector2(cos(angle), sin(angle)) * radius, Color(0.64, 0.50, 0.32, 1.0), 5.0)
	draw_circle(Vector2.ZERO, 8.0, edge)
	_draw_progress_bar(half)


func _draw_power_lever() -> void:
	var half := _visual_size * 0.5
	var panel := Rect2(-half, _visual_size).grow(-2.0)
	var outline := Color(0.44, 0.62, 0.64, 1.0)
	var base := Color(0.08, 0.13, 0.15, 1.0)
	if _focused:
		base = base.lightened(0.18)
		outline = Color(0.65, 1.0, 0.88, 1.0)
	draw_rect(panel, base, true)
	draw_rect(panel, outline, false, 4.0)
	var slot_top := -half.y + 15.0
	var slot_bottom := half.y - 15.0
	draw_line(Vector2(0.0, slot_top), Vector2(0.0, slot_bottom), Color(0.02, 0.04, 0.05, 1.0), 10.0)
	draw_line(Vector2(0.0, slot_top), Vector2(0.0, slot_bottom), Color(0.32, 0.42, 0.43, 1.0), 3.0)
	var handle_y := slot_top if _power_lever_position == "up" else slot_bottom
	draw_line(Vector2.ZERO, Vector2(0.0, handle_y), Color(0.72, 0.78, 0.75, 1.0), 6.0)
	var handle_color := Color(0.42, 0.92, 0.74, 1.0) if _power_lever_position == "up" else Color(0.95, 0.66, 0.24, 1.0)
	draw_circle(Vector2(0.0, handle_y), 11.0, handle_color)
	draw_circle(Vector2(0.0, handle_y), 11.0, Color(0.92, 1.0, 0.96, 0.9), false, 2.0)
	_draw_progress_bar(half)


func _state_color(default_accent: Color = Color(0.48, 0.68, 0.72, 1.0)) -> Color:
	if _visual_state == "fault":
		return Color(0.95, 0.22, 0.18, 1.0).lerp(Color(1.0, 0.68, 0.18, 1.0), (sin(_animation_phase) + 1.0) * 0.5)
	if _visual_state in ["latched", "completed", "bolt_released", "open", "contact_closed"]:
		return default_accent.lightened(0.24)
	if _available or _visual_state.begins_with("ready"):
		return default_accent
	return Color(0.30, 0.38, 0.39, 1.0)


func _draw_progress_bar(half: Vector2) -> void:
	if _focused and _progress > 0.0:
		var progress_rect := Rect2(
			Vector2(-half.x + 4.0, half.y - 9.0),
			Vector2((_visual_size.x - 8.0) * _progress, 5.0)
		)
		draw_rect(progress_rect, Color(0.92, 0.72, 0.24, 1.0), true)
