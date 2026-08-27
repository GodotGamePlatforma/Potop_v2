extends Node2D

const StructureInteractableScript := preload("res://underwater_map_workbench/structures/tower_prototype_01/runtime/DiveStructureInteractable.gd")

const CIRCUIT_COLORS := {
	"red": Color(0.96, 0.28, 0.24, 1.0),
	"blue": Color(0.24, 0.62, 1.0, 1.0),
	"yellow": Color(1.0, 0.80, 0.20, 1.0),
}
const STATE_LABELS := {
	"locked": "ZABLOK.",
	"ready": "GOTOWY",
	"active": "AKTYWNY",
	"latched": "ZATRZASK",
}
const STATUS_LABELS := {
	"ready": "GOTOWO",
	"fault": "DIAGNOSTYKA",
	"locked": "OBWÓD ZABLOKOWANY",
	"active": "OBWÓD AKTYWNY",
	"latched": "OBWÓD ZATRZAŚNIĘTY",
}

var control_id := ""

var _panel_rect := Rect2()
var _toggle_callback := Callable()
var _lever_order := PackedStringArray()
var _levers: Dictionary = {}
var _runtime_id_to_lever_id: Dictionary = {}
var _circuits: Array[Dictionary] = []
var _lever_positions: Dictionary = {}
var _circuit_states: Dictionary = {}
var _matched_circuit_id := ""
var _active_circuit_id := ""
var _power_status := "ready"
var _diagnostic_id := ""
var _diagnostic_message := ""
var _clue_text := ""
var _title_label: Label
var _clue_label: Label
var _diagnostic_label: Label
var _circuit_labels: Dictionary = {}


func configure(definition: Dictionary, socket_rect: Rect2, toggle_callback: Callable) -> void:
	control_id = str(definition.get("id", ""))
	_panel_rect = socket_rect
	_toggle_callback = toggle_callback
	z_index = 7
	set_meta(&"structure_control_id", control_id)
	set_meta(&"socket_rect", socket_rect)
	set_meta(&"native_visual_rect", socket_rect)
	var power_logic := definition.get("power_logic", {}) as Dictionary
	set_meta(&"power_logic_contract", str(power_logic.get("contract", "")))
	_circuits.clear()
	var circuit_definitions := power_logic.get("circuits", {}) as Dictionary
	for circuit_id: String in ["red", "blue", "yellow"]:
		var circuit := (circuit_definitions.get(circuit_id, {}) as Dictionary).duplicate(true)
		circuit["id"] = circuit_id
		_circuits.append(circuit)
	_build_levers(definition, power_logic.get("levers", []) as Array)
	_build_status_labels()
	set_runtime_state(_lever_positions, {}, "", "", "ready", "", "", "")


func lever(lever_id: String):
	return _levers.get(lever_id, null)


func lever_ids() -> PackedStringArray:
	return _lever_order.duplicate()


func set_levers_available(available: bool) -> void:
	for lever_id: String in _lever_order:
		var lever = _levers.get(lever_id, null)
		if lever != null:
			lever.set_available(available)


func set_runtime_state(
	lever_positions: Dictionary,
	circuit_states: Dictionary,
	matched_circuit_id: String,
	active_circuit_id: String,
	power_status: String,
	diagnostic_id: String = "",
	diagnostic_message: String = "",
	clue_text: String = ""
) -> void:
	_lever_positions = lever_positions.duplicate(true)
	_circuit_states = circuit_states.duplicate(true)
	_matched_circuit_id = matched_circuit_id
	_active_circuit_id = active_circuit_id
	_power_status = power_status
	_diagnostic_id = diagnostic_id
	_diagnostic_message = diagnostic_message
	_clue_text = clue_text
	for lever_id: String in _lever_order:
		var lever = _levers.get(lever_id, null)
		if lever != null:
			lever.set_power_lever_position(str(_lever_positions.get(lever_id, "up")))
	set_meta(&"matched_circuit_id", _matched_circuit_id)
	set_meta(&"active_circuit_id", _active_circuit_id)
	set_meta(&"power_status", _power_status)
	set_meta(&"diagnostic_id", _diagnostic_id)
	set_meta(&"diagnostic_message", _diagnostic_message)
	set_meta(&"clue_text", _clue_text)
	_refresh_status_labels()
	queue_redraw()


func circuit_visual_state(circuit_id: String) -> String:
	return str(_circuit_states.get(circuit_id, "locked"))


func _build_levers(definition: Dictionary, lever_definitions: Array) -> void:
	_lever_order.clear()
	_levers.clear()
	_runtime_id_to_lever_id.clear()
	_lever_positions.clear()
	var interaction_seconds := float(definition.get("interaction_seconds", 0.8))
	var interaction_action := str(definition.get("interaction_action", "activate"))
	for lever_value: Variant in lever_definitions:
		var lever_definition := (lever_value as Dictionary).duplicate(true)
		var lever_id := str(lever_definition.get("id", ""))
		var lever_rect := _rect_from_value(lever_definition.get("local_rect", null))
		var lever = StructureInteractableScript.new()
		lever.name = ("PowerLever_%s" % lever_id).to_pascal_case()
		lever.configure_power_lever(
			control_id,
			lever_definition,
			interaction_seconds,
			interaction_action,
			lever_rect,
			Callable(self, "_on_lever_activated")
		)
		add_child(lever)
		_lever_order.append(lever_id)
		_levers[lever_id] = lever
		_runtime_id_to_lever_id[lever.control_id] = lever_id
		_lever_positions[lever_id] = str(lever_definition.get("initial_position", "up"))


func _build_status_labels() -> void:
	# Cała prezentacja panelu mieści się w natywnym sockecie 320×120.
	# Wcześniejszy wariant wysuwał clues 104 px ponad collider.
	_clue_label = Label.new()
	_clue_label.name = "DeductionClue"
	_clue_label.position = _panel_rect.position + Vector2(72.0, 3.0)
	_clue_label.size = Vector2(_panel_rect.size.x - 76.0, 34.0)
	_clue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_clue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clue_label.add_theme_font_size_override(&"font_size", 7)
	_clue_label.add_theme_color_override(&"font_color", Color(0.72, 0.82, 0.80, 1.0))
	add_child(_clue_label)
	_diagnostic_label = Label.new()
	_diagnostic_label.name = "DiagnosticReason"
	_diagnostic_label.position = _panel_rect.position + Vector2(72.0, 3.0)
	_diagnostic_label.size = Vector2(_panel_rect.size.x - 76.0, 34.0)
	_diagnostic_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diagnostic_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_diagnostic_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_diagnostic_label.add_theme_font_size_override(&"font_size", 7)
	_diagnostic_label.add_theme_color_override(&"font_color", Color(0.96, 0.68, 0.34, 1.0))
	add_child(_diagnostic_label)
	_title_label = Label.new()
	_title_label.name = "PowerStatus"
	_title_label.position = _panel_rect.position + Vector2(5.0, 3.0)
	_title_label.size = Vector2(63.0, 34.0)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.add_theme_font_size_override(&"font_size", 8)
	_title_label.add_theme_color_override(&"font_color", Color(0.82, 0.95, 0.94, 1.0))
	add_child(_title_label)
	_circuit_labels.clear()


func _refresh_status_labels() -> void:
	if _title_label != null:
		_title_label.text = "A\n%s" % str(STATUS_LABELS.get(_power_status, _power_status.to_upper()))
	if _clue_label != null:
		_clue_label.text = _clue_text
		_clue_label.visible = _diagnostic_message.is_empty()
	if _diagnostic_label != null:
		_diagnostic_label.text = _diagnostic_message
		_diagnostic_label.visible = not _diagnostic_message.is_empty()
	for circuit_value: Variant in _circuits:
		var circuit := circuit_value as Dictionary
		var circuit_id := str(circuit.get("id", ""))
		var label := _circuit_labels.get(circuit_id, null) as Label
		if label == null:
			continue
		var state := str(_circuit_states.get(circuit_id, "locked"))
		label.text = "%s\n%s" % [circuit_id.to_upper(), str(STATE_LABELS.get(state, state.to_upper()))]
		label.add_theme_color_override(&"font_color", _state_color(circuit_id, state))


func _on_lever_activated(runtime_control_id: String) -> Dictionary:
	var lever_id := str(_runtime_id_to_lever_id.get(runtime_control_id, ""))
	if lever_id.is_empty() or not _toggle_callback.is_valid():
		return {"success": false, "message": "Dźwignia rozdzielni nie odpowiada."}
	var callback_result: Variant = _toggle_callback.call(lever_id)
	return callback_result as Dictionary if callback_result is Dictionary else {}


func _draw() -> void:
	var visual_panel_rect := _panel_rect.grow(-2.0)
	draw_rect(visual_panel_rect, Color(0.055, 0.09, 0.105, 0.98), true)
	draw_rect(visual_panel_rect, Color(0.38, 0.58, 0.60, 1.0), false, 4.0)
	draw_line(
		_panel_rect.position + Vector2(0.0, 40.0),
		_panel_rect.position + Vector2(_panel_rect.size.x, 40.0),
		Color(0.25, 0.40, 0.42, 1.0),
		2.0
	)
	var column_width := _panel_rect.size.x / maxf(float(_circuits.size()), 1.0)
	for circuit_index: int in range(_circuits.size()):
		var circuit: Dictionary = _circuits[circuit_index]
		var circuit_id := str(circuit.get("id", ""))
		var state := str(_circuit_states.get(circuit_id, "locked"))
		var center := _panel_rect.position + Vector2(column_width * (float(circuit_index) + 0.5), 46.0)
		draw_line(
			center + Vector2(0.0, 10.0),
			center + Vector2(0.0, 66.0),
			Color(_state_color(circuit_id, state), 0.34),
			5.0
		)
		_draw_symbol(str(circuit.get("symbol", "circle")), center, _state_color(circuit_id, state))


func _draw_symbol(symbol: String, center: Vector2, color: Color) -> void:
	match symbol:
		"triangle":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0.0, -9.0),
				center + Vector2(9.0, 8.0),
				center + Vector2(-9.0, 8.0),
			]), color)
		"square":
			draw_rect(Rect2(center - Vector2(8.0, 8.0), Vector2(16.0, 16.0)), color, true)
		_:
			draw_circle(center, 8.0, color)
	if color.a > 0.0:
		draw_circle(center, 11.0, Color(color.r, color.g, color.b, 0.42), false, 2.0)


func _state_color(circuit_id: String, state: String) -> Color:
	var circuit_color: Color = CIRCUIT_COLORS.get(circuit_id, Color(0.55, 0.72, 0.72, 1.0))
	match state:
		"locked":
			return Color(0.28, 0.34, 0.35, 1.0)
		"ready":
			return circuit_color.darkened(0.38)
		"latched":
			return circuit_color.lightened(0.18)
		_:
			return circuit_color


static func _rect_from_value(value: Variant) -> Rect2:
	if value is Rect2:
		return value as Rect2
	if value is Array and (value as Array).size() == 4:
		var values := value as Array
		return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	return Rect2()
