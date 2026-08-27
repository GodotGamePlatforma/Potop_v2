extends Node2D

const StructureInteractableScript := preload("res://underwater_map_workbench/structures/tower_prototype_01/runtime/DiveStructureInteractable.gd")
const PowerDistributorPanelScript := preload("res://underwater_map_workbench/structures/tower_prototype_01/runtime/DivePowerDistributorPanel.gd")
const MechanismVisualScript := preload("res://underwater_map_workbench/structures/tower_prototype_01/runtime/DiveTowerMechanismVisual.gd")
const DiverControllerScript := preload("res://diver_workbench/runtime/DiverController.gd")

const CONTRACT_ID := "enterable_tower_sequence_v3"
const POWER_LOGIC_CONTRACT_ID := "three_lever_deduction_v2"
const POWER_EVALUATION_MODE := "on_toggle"
const PUBLIC_GATE_ATTEMPT_COMPLETE: StringName = &"attempt_complete"
const REQUIRED_POWER_LEVER_IDS := ["a_lever_1", "a_lever_2", "a_lever_3"]
const DIVE_PLAYER_GROUP := DiverControllerScript.DIVE_PLAYER_GROUP
const SAFETY_MARGIN := 40.0
const TARGET_EPSILON := 0.5
const MECHANISM_Z_INDEX := -10
const REQUIRED_GROUP_IDS := [
	"red_route",
	"blue_route",
	"yellow_route",
	"shortcut_b",
	"shortcut_c",
	"hatch_d",
	"hatch_basement",
]
const REQUIRED_CONTROL_KIND_COUNTS := {
	"power_distributor": 1,
	"red_relay": 1,
	"blue_lock": 1,
	"d_valve": 3,
	"d_reset": 1,
	"basement_hatch_control": 1,
}
const REQUIRED_CIRCUIT_DEFINITIONS := {
	"red": {
		"positions": ["down", "down", "down"],
		"symbol": "circle",
		"barrier_group_id": "red_route",
	},
	"blue": {
		"positions": ["up", "down", "up"],
		"symbol": "triangle",
		"barrier_group_id": "blue_route",
	},
	"yellow": {
		"positions": ["down", "up", "up"],
		"symbol": "square",
		"barrier_group_id": "yellow_route",
	},
}
const REQUIRED_DIAGNOSTIC_IDS := [
	"all_branches_open",
	"right_branch_unterminated",
	"middle_right_overload",
	"split_outer_feed",
	"left_middle_crossfeed",
]
const D_STEP_NAMES := {
	1: "WYRÓWNANIE CIŚNIENIA",
	2: "ZASILENIE SIŁOWNIKA",
	3: "ZWOLNIENIE RYGLA",
}

var structure_id: String = ""

var _runtime_config: Dictionary = {}
var _socket_records: Dictionary = {}
var _barrier_groups: Dictionary = {}
var _control_definitions: Dictionary = {}
var _controls: Dictionary = {}
var _interactives_root: Node2D
var _power_panel
var _power_control_id := ""
var _power_lever_order := PackedStringArray()
var _power_lever_definitions: Dictionary = {}
var _power_initial_positions: Dictionary = {}
var _power_lever_positions: Dictionary = {}
var _power_circuits: Dictionary = {}
var _power_diagnostics: Dictionary = {}
var _power_clues: Dictionary = {}
var _matched_circuit_id := ""
var _active_circuit_id := ""
var _power_status := "ready"
var _power_has_been_toggled := false
var _power_diagnostic_id := ""
var _power_diagnostic_message := ""

var _elevator_body: AnimatableBody2D
var _elevator_safety_area: Area2D
var _elevator_stops: Dictionary = {}
var _elevator_speed := 240.0
var _elevator_initial_stop_id := ""
var _elevator_current_stop_id := ""
var _elevator_target_stop_id := ""
var _elevator_locked := false
var _trolley_contact_closed := false
var _elevator_visual

var _feedback_player: AudioStreamPlayer
var _last_feedback_kind := ""

var _red_latched := false
var _blue_latched := false
var _d_progress := 0
var _d_requires_reset := false
var _d_complete := false
var _basement_open := false


func configure(structure_record: Dictionary, interactives_root: Node2D) -> PackedStringArray:
	var errors := _configuration_errors(structure_record, interactives_root)
	if not errors.is_empty():
		return errors
	structure_id = str(structure_record.get("id", ""))
	_runtime_config = (structure_record.get("runtime", {}) as Dictionary).duplicate(true)
	_interactives_root = interactives_root
	_index_sockets(structure_record.get("sockets", []) as Array)
	set_meta(&"structure_id", structure_id)
	set_meta(&"runtime_contract", CONTRACT_ID)
	_build_elevator(_runtime_config.get("elevator", {}) as Dictionary)
	_build_barrier_groups(_runtime_config.get("barrier_groups", []) as Array)
	_build_interactives(_runtime_config.get("interactives", []) as Array)
	_build_feedback_audio()
	reset_attempt()
	return errors


func reset_attempt() -> void:
	_red_latched = false
	_blue_latched = false
	_d_progress = 0
	_d_requires_reset = false
	_d_complete = false
	_basement_open = false
	_elevator_locked = false
	_trolley_contact_closed = false
	_power_has_been_toggled = false
	_power_lever_positions = _power_initial_positions.duplicate(true)
	_matched_circuit_id = ""
	_active_circuit_id = ""
	_power_status = "ready"
	_power_diagnostic_id = ""
	_power_diagnostic_message = ""
	for group_id_value: Variant in _barrier_groups.keys():
		var group_id := str(group_id_value)
		_set_barrier_group_open(group_id, false, true)
		_snap_barrier_group_to_target(group_id)
	_elevator_current_stop_id = _elevator_initial_stop_id
	_elevator_target_stop_id = _elevator_initial_stop_id
	if _elevator_body != null and _elevator_stops.has(_elevator_initial_stop_id):
		_teleport_animatable(_elevator_body, _elevator_stops[_elevator_initial_stop_id] as Vector2)
		_set_elevator_safety_position(_elevator_body.position)
	_evaluate_power_logic()
	_refresh_control_availability()
	_refresh_trolley_visual()


func activate_control(control_id: String) -> Dictionary:
	return _activate_control(control_id)


func activate_power_lever(lever_id: String) -> Dictionary:
	return _activate_power_lever(lever_id)


func power_lever(lever_id: String):
	if _power_panel == null:
		return null
	return _power_panel.lever(lever_id)


func power_lever_ids() -> PackedStringArray:
	return _power_lever_order.duplicate()


func power_circuit_state(circuit_id: String) -> String:
	return str(_circuit_states_snapshot().get(circuit_id, "locked"))


func control(control_id: String):
	return _controls.get(control_id, null)


func barrier_group_is_open(group_id: String) -> bool:
	if not _barrier_groups.has(group_id):
		return false
	return bool((_barrier_groups[group_id] as Dictionary).get("open", false))


func barrier_group_reached_target(group_id: String) -> bool:
	if not _barrier_groups.has(group_id):
		return false
	var group: Dictionary = _barrier_groups[group_id]
	for member_value: Variant in group.get("members", []):
		var member := member_value as Dictionary
		var body := member.get("body", null) as AnimatableBody2D
		var target: Vector2 = member.get("target_position", Vector2.ZERO)
		if (
			body == null
			or body.position.distance_to(target) > TARGET_EPSILON
			or not bool(body.get_meta(&"reached_target", false))
			or bool(body.get_meta(&"target_open", false)) != bool(group.get("open", false))
		):
			return false
	return true


func request_barrier_group_open(group_id: String, open: bool) -> bool:
	return _set_barrier_group_open(group_id, open, false)


func barrier_group_safety_clear(group_id: String) -> bool:
	if not _barrier_groups.has(group_id):
		return false
	var group: Dictionary = _barrier_groups[group_id]
	for member_value: Variant in group.get("members", []):
		var safety_area := (member_value as Dictionary).get("safety_area", null) as Area2D
		if not _safety_area_clear(safety_area):
			return false
	return true


func elevator_current_stop_id() -> String:
	return _elevator_current_stop_id


func elevator_target_stop_id() -> String:
	return _elevator_target_stop_id


func elevator_reached_stop(stop_id: String) -> bool:
	if _elevator_body == null or not _elevator_stops.has(stop_id):
		return false
	return _elevator_current_stop_id == stop_id


func elevator_safety_clear() -> bool:
	return _safety_area_clear(_elevator_safety_area)


func is_public_gate_open(gate_id: StringName) -> bool:
	return gate_id == PUBLIC_GATE_ATTEMPT_COMPLETE and _basement_open


func state_snapshot() -> Dictionary:
	var group_states := {}
	for group_id_value: Variant in _barrier_groups.keys():
		var group_id := str(group_id_value)
		group_states[group_id] = barrier_group_is_open(group_id)
	return {
		"lever_positions": _power_lever_positions.duplicate(true),
		"matched_circuit_id": _matched_circuit_id,
		"active_circuit_id": _active_circuit_id,
		"power_status": _power_status,
		"power_diagnostic_id": _power_diagnostic_id,
		"power_diagnostic_message": _power_diagnostic_message,
		"circuit_states": _circuit_states_snapshot(),
		"red_latched": _red_latched,
		"blue_latched": _blue_latched,
		"d_progress": _d_progress,
		"d_requires_reset": _d_requires_reset,
		"d_complete": _d_complete,
		"basement_open": _basement_open,
		"elevator_current_stop_id": _elevator_current_stop_id,
		"elevator_target_stop_id": _elevator_target_stop_id,
		"elevator_local_position": _elevator_body.position if _elevator_body != null else Vector2.ZERO,
		"elevator_safety_clear": elevator_safety_clear(),
		"elevator_safety_global_position": _elevator_safety_area.global_position if _elevator_safety_area != null else Vector2.ZERO,
		"elevator_locked": _elevator_locked,
		"trolley_contact_closed": _trolley_contact_closed,
		"trolley_visual_state": _elevator_visual.visual_state() if _elevator_visual != null else "",
		"last_feedback_kind": _last_feedback_kind,
		"attempt_complete": is_public_gate_open(PUBLIC_GATE_ATTEMPT_COMPLETE),
		"barrier_groups": group_states,
	}


func _physics_process(delta: float) -> void:
	_advance_motion(maxf(delta, 0.0))


func _advance_motion(delta: float) -> void:
	_apply_power_outputs()
	var elevator_arrived := _advance_elevator(delta)
	var contact_changed := _sync_trolley_contact(true)
	for group_id_value: Variant in _barrier_groups.keys():
		var group: Dictionary = _barrier_groups[str(group_id_value)]
		var speed := float(group.get("travel_speed", 320.0))
		for member_value: Variant in group.get("members", []):
			var member := member_value as Dictionary
			var body := member.get("body", null) as AnimatableBody2D
			if body == null:
				continue
			var target: Vector2 = member.get("target_position", body.position)
			body.position = body.position.move_toward(target, speed * delta)
			if body.position.distance_to(target) <= TARGET_EPSILON:
				body.position = target
			_refresh_barrier_member_visual(group, member)
	if elevator_arrived or contact_changed:
		_refresh_control_availability()
	_refresh_trolley_visual()


func _advance_elevator(delta: float) -> bool:
	if (
		_elevator_body == null
		or _elevator_target_stop_id.is_empty()
		or not _elevator_stops.has(_elevator_target_stop_id)
	):
		return false
	var target: Vector2 = _elevator_stops[_elevator_target_stop_id]
	var current_position := _elevator_body.position
	if current_position.distance_to(target) <= TARGET_EPSILON:
		_elevator_body.position = target
		var changed := _elevator_current_stop_id != _elevator_target_stop_id
		_elevator_current_stop_id = _elevator_target_stop_id
		_set_elevator_safety_position(target)
		return changed
	if not elevator_safety_clear():
		_refresh_trolley_visual()
		return false
	_elevator_current_stop_id = ""
	var next_position := current_position.move_toward(target, _elevator_speed * delta)
	_elevator_body.position = next_position
	_set_elevator_safety_position(next_position)
	if next_position.distance_to(target) <= TARGET_EPSILON:
		_elevator_body.position = target
		_elevator_current_stop_id = _elevator_target_stop_id
		_set_elevator_safety_position(target)
		return true
	return false


func _activate_control(control_id: String) -> Dictionary:
	if not _control_definitions.has(control_id):
		return _failure("Nieznane sterowanie konstrukcji.")
	var definition: Dictionary = _control_definitions[control_id]
	var kind := str(definition.get("kind", ""))
	var result := {}
	match kind:
		"power_distributor":
			result = _failure("Użyj jednej z trzech dźwigni rozdzielni A.")
		"red_relay":
			result = _activate_red_relay()
		"blue_lock":
			result = _activate_blue_lock()
		"d_valve":
			result = _activate_d_valve(int(definition.get("step", 0)))
		"d_reset":
			result = _activate_d_reset()
		"basement_hatch_control":
			result = _activate_basement_hatch()
		_:
			result = _failure("Sterowanie ma nieobsługiwany typ.")
	result["interaction_action"] = str(definition.get("interaction_action", "activate"))
	_refresh_control_availability()
	return result


func _activate_power_lever(lever_id: String) -> Dictionary:
	if not _power_lever_positions.has(lever_id):
		return _failure("Nieznana dźwignia rozdzielni A.")
	var previous_position := str(_power_lever_positions[lever_id])
	var next_position := "down" if previous_position == "up" else "up"
	_power_lever_positions[lever_id] = next_position
	_power_has_been_toggled = true
	_evaluate_power_logic()
	_refresh_control_availability()
	var lever_name := lever_id
	var lever_definition := _power_lever_definition(lever_id)
	if not lever_definition.is_empty():
		lever_name = str(lever_definition.get("display_name", lever_id))
	match _power_status:
		"active":
			return _success("%s przełączona. Obwód %s odpowiada." % [lever_name, _active_circuit_id.to_upper()])
		"latched":
			return _success("%s przełączona. Obwód %s pozostaje zatrzaśnięty." % [lever_name, _matched_circuit_id.to_upper()])
		"locked":
			return _success("%s przełączona. Tor %s jest rozpoznany, ale jeszcze odcięty." % [lever_name, _matched_circuit_id.to_upper()])
		_:
			return _success("%s przełączona. %s" % [lever_name, _power_diagnostic_message])


func _activate_red_relay() -> Dictionary:
	if _red_latched:
		return _failure("Czerwony przekaźnik jest już zatrzaśnięty.")
	if not _power_circuit_is_active("red"):
		return _failure("Obwód awaryjny RED nie ma jeszcze ciągłości.")
	_red_latched = true
	_set_barrier_group_open("red_route", true, false)
	_set_barrier_group_open("shortcut_b", true, false)
	_evaluate_power_logic()
	_play_feedback("red_relay_latched")
	return _success("RED zatrzaśnięty. Otworzono skrót z B do A.")


func _activate_blue_lock() -> Dictionary:
	if _blue_latched:
		return _failure("Niebieski rygiel jest już zatrzaśnięty.")
	if not _power_circuit_is_active("blue"):
		return _failure("Tor BLUE nie steruje teraz pustym wózkiem serwisowym.")
	if not _trolley_contact_closed:
		return _failure("Poczekaj na pusty wózek i fizyczne domknięcie styku C.")
	_blue_latched = true
	_elevator_locked = true
	_elevator_current_stop_id = "floor_7"
	_elevator_target_stop_id = "floor_7"
	_set_barrier_group_open("blue_route", true, false)
	_set_barrier_group_open("shortcut_c", true, false)
	_evaluate_power_logic()
	_play_feedback("trolley_latched")
	return _success("Pusty wózek i BLUE zatrzaśnięte. Otworzono skrót z C do A.")


func _activate_d_valve(step: int) -> Dictionary:
	if not _power_circuit_is_active("yellow"):
		return _failure("Układ D nie ma zasilania z obwodu YELLOW.")
	if _d_complete:
		return _failure("Sekwencja zaworów jest już ukończona.")
	if _d_requires_reset:
		return _failure("Błędna sekwencja. Użyj pokrętła RESET.")
	var expected_step := _d_progress + 1
	if step != expected_step:
		_d_requires_reset = true
		_play_feedback("d_fault")
		return _failure("BŁĄD KOLEJNOŚCI: oczekiwano „%s”. Użyj RESET D." % str(D_STEP_NAMES.get(expected_step, "ETAPU")))
	_d_progress = step
	_play_feedback("d_step_%d" % step)
	if _d_progress == 3:
		_d_complete = true
		_set_barrier_group_open("hatch_d", true, false)
		return _success("ZWOLNIENIE RYGLA potwierdzone. Właz w dół jest otwarty.")
	return _success("%s — potwierdzone." % str(D_STEP_NAMES.get(step, "ETAP D")))


func _activate_d_reset() -> Dictionary:
	if not _power_circuit_is_active("yellow"):
		return _failure("Układ D nie jest teraz zasilany obwodem YELLOW.")
	if _d_complete:
		return _failure("Ukończonej sekwencji D nie można cofnąć podczas tej próby.")
	_d_progress = 0
	_d_requires_reset = false
	_play_feedback("d_reset")
	return _success("RESET D wykonany. Rozpocznij od WYRÓWNANIA CIŚNIENIA.")


func _activate_basement_hatch() -> Dictionary:
	if not _d_complete:
		return _failure("Najpierw zwolnij rygiel w sekwencji D.")
	if _basement_open:
		return _failure("Wejście do Archiwum jest już otwarte.")
	_basement_open = true
	_set_barrier_group_open("hatch_basement", true, false)
	_play_feedback("archive_open")
	return _success("Archiwum otwarte. Próba wieżowca ukończona.")


func _set_elevator_target(stop_id: String) -> bool:
	if _elevator_locked or not _elevator_stops.has(stop_id):
		return false
	_elevator_target_stop_id = stop_id
	return true


func _evaluate_power_logic() -> void:
	_matched_circuit_id = _matching_power_circuit_id()
	_active_circuit_id = ""
	_power_diagnostic_id = ""
	_power_diagnostic_message = ""
	match _matched_circuit_id:
		"red":
			if not _red_latched:
				_active_circuit_id = "red"
		"blue":
			if _red_latched and not _blue_latched:
				_active_circuit_id = "blue"
		"yellow":
			if _blue_latched:
				_active_circuit_id = "yellow"
	var circuit_states := _circuit_states_snapshot()
	if _matched_circuit_id.is_empty():
		if _power_has_been_toggled:
			_power_status = "fault"
			var diagnostic := _matching_power_diagnostic()
			_power_diagnostic_id = str(diagnostic.get("reason_id", ""))
			_power_diagnostic_message = str(diagnostic.get("message", ""))
		else:
			_power_status = "ready"
	else:
		_power_status = str(circuit_states.get(_matched_circuit_id, "locked"))
	_apply_power_outputs()
	_sync_power_panel_state(circuit_states)


func _apply_power_outputs() -> void:
	_set_barrier_group_open(_power_barrier_group_id("red"), _red_latched or _active_circuit_id == "red", false)
	_set_barrier_group_open(_power_barrier_group_id("blue"), _blue_latched or _active_circuit_id == "blue", false)
	_set_barrier_group_open(_power_barrier_group_id("yellow"), _active_circuit_id == "yellow", false)
	if not _blue_latched:
		_set_elevator_target("floor_7" if _active_circuit_id == "blue" else "floor_12")
	_sync_trolley_contact(false)
	_refresh_trolley_visual()


func _matching_power_circuit_id() -> String:
	var current_positions: Array[String] = []
	for lever_id: String in _power_lever_order:
		current_positions.append(str(_power_lever_positions.get(lever_id, "up")))
	for circuit_id: String in ["red", "blue", "yellow"]:
		if not _power_circuits.has(circuit_id):
			continue
		var circuit := _power_circuits[circuit_id] as Dictionary
		var required_positions := circuit.get("positions", []) as Array
		if required_positions.size() != current_positions.size():
			continue
		var matches := true
		for position_index: int in range(current_positions.size()):
			if str(required_positions[position_index]) != current_positions[position_index]:
				matches = false
				break
		if matches:
			return circuit_id
	return ""


func _matching_power_diagnostic() -> Dictionary:
	var current_positions: Array[String] = []
	for lever_id: String in _power_lever_order:
		current_positions.append(str(_power_lever_positions.get(lever_id, "up")))
	for reason_id_value: Variant in _power_diagnostics.keys():
		var reason_id := str(reason_id_value)
		var diagnostic := _power_diagnostics[reason_id] as Dictionary
		if _string_array_equals(diagnostic.get("positions", null), current_positions):
			var result := diagnostic.duplicate(true)
			result["reason_id"] = reason_id
			return result
	return {}


func _current_clue_id() -> String:
	if not _red_latched:
		return "red"
	if not _blue_latched:
		return "blue"
	return "yellow"


func _current_clue_text() -> String:
	return str(_power_clues.get(_current_clue_id(), ""))


func _circuit_states_snapshot() -> Dictionary:
	return {
		"red": "latched" if _red_latched else ("active" if _active_circuit_id == "red" else "ready"),
		"blue": (
			"latched"
			if _blue_latched
			else ("locked" if not _red_latched else ("active" if _active_circuit_id == "blue" else "ready"))
		),
		"yellow": (
			"locked"
			if not _blue_latched
			else ("active" if _active_circuit_id == "yellow" else "ready")
		),
	}


func _power_circuit_is_active(circuit_id: String) -> bool:
	return _active_circuit_id == circuit_id


func _power_lever_definition(lever_id: String) -> Dictionary:
	return _power_lever_definitions.get(lever_id, {}) as Dictionary


func _power_barrier_group_id(circuit_id: String) -> String:
	var circuit := _power_circuits.get(circuit_id, {}) as Dictionary
	return str(circuit.get("barrier_group_id", ""))


func _sync_power_panel_state(circuit_states: Dictionary = {}) -> void:
	if _power_panel == null:
		return
	var states := circuit_states if not circuit_states.is_empty() else _circuit_states_snapshot()
	_power_panel.set_runtime_state(
		_power_lever_positions,
		states,
		_matched_circuit_id,
		_active_circuit_id,
		_power_status,
		_power_diagnostic_id,
		_power_diagnostic_message,
		_current_clue_id(),
		_current_clue_text()
	)


func _set_barrier_group_open(group_id: String, open: bool, force: bool) -> bool:
	if not _barrier_groups.has(group_id):
		return false
	var group: Dictionary = _barrier_groups[group_id]
	if not open and bool(group.get("open", false)) and not force and not barrier_group_safety_clear(group_id):
		return false
	group["open"] = open
	for member_value: Variant in group.get("members", []):
		var member := member_value as Dictionary
		member["target_position"] = (
			member.get("open_position", Vector2.ZERO)
			if open
			else member.get("closed_position", Vector2.ZERO)
		)
		_refresh_barrier_member_visual(group, member)
	_barrier_groups[group_id] = group
	return true


func _refresh_barrier_member_visual(group: Dictionary, member: Dictionary) -> void:
	var body := member.get("body", null) as AnimatableBody2D
	if body == null:
		return
	var target_position: Vector2 = member.get("target_position", body.position)
	var target_open := bool(group.get("open", false))
	var reached_target := body.position.is_equal_approx(target_position)
	var state := ""
	if reached_target:
		state = "open" if target_open else "closed"
	else:
		state = "opening" if target_open else "closing"
	var visual = member.get("visual", null)
	if visual != null:
		visual.set_visual_state(state)
	body.set_meta(&"visual_state", state)
	body.set_meta(&"target_open", target_open)
	body.set_meta(&"target_position", target_position)
	body.set_meta(&"reached_target", reached_target)


func _snap_barrier_group_to_target(group_id: String) -> void:
	if not _barrier_groups.has(group_id):
		return
	var group: Dictionary = _barrier_groups[group_id]
	for member_value: Variant in group.get("members", []):
		var member := member_value as Dictionary
		var body := member.get("body", null) as AnimatableBody2D
		if body != null:
			_teleport_animatable(body, member.get("target_position", body.position))
		_refresh_barrier_member_visual(group, member)


func _build_elevator(definition: Dictionary) -> void:
	var socket_id := str(definition.get("socket_id", ""))
	var travel_rect := _socket_rect(socket_id)
	var cabin_size := _vector_from_value(definition.get("cabin_size", Vector2.ZERO))
	_elevator_speed = float(definition.get("travel_speed", 240.0))
	_elevator_initial_stop_id = str(definition.get("initial_stop_id", ""))
	_elevator_stops.clear()
	for stop_value: Variant in definition.get("stops", []):
		var stop := stop_value as Dictionary
		_elevator_stops[str(stop.get("id", ""))] = _vector_from_value(stop.get("local_center", Vector2.ZERO))
	_elevator_body = AnimatableBody2D.new()
	_elevator_body.name = str(definition.get("id", "elevator")).to_pascal_case()
	_elevator_body.collision_layer = 1
	_elevator_body.collision_mask = 0
	_elevator_body.sync_to_physics = true
	_elevator_body.position = _elevator_stops[_elevator_initial_stop_id]
	_elevator_body.z_index = MECHANISM_Z_INDEX
	_elevator_body.set_meta(&"structure_id", structure_id)
	_elevator_body.set_meta(&"dynamic_kind", "empty_maintenance_trolley")
	_elevator_body.set_meta(&"socket_id", socket_id)
	_elevator_visual = _add_rect_collision_and_visual(
		_elevator_body,
		cabin_size,
		Color(0.34, 0.68, 0.72, 1.0),
		&"empty_service_trolley"
	)
	add_child(_elevator_body)
	_elevator_safety_area = _create_safety_envelope(
		"ElevatorSafetyAnchor",
		_elevator_body.position,
		cabin_size,
		socket_id,
		travel_rect
	)


func _build_barrier_groups(definitions: Array) -> void:
	_barrier_groups.clear()
	for group_value: Variant in definitions:
		var definition := group_value as Dictionary
		var group_id := str(definition.get("id", ""))
		var group_members: Array[Dictionary] = []
		for member_value: Variant in definition.get("members", []):
			var member_definition := member_value as Dictionary
			var socket_id := str(member_definition.get("socket_id", ""))
			var closed_rect := _socket_rect(socket_id)
			var closed_position := closed_rect.get_center()
			var open_position := closed_position + _vector_from_value(member_definition.get("open_offset", Vector2.ZERO))
			var body := AnimatableBody2D.new()
			body.name = ("%s_%s" % [group_id, socket_id]).to_pascal_case()
			body.collision_layer = 1
			body.collision_mask = 0
			body.sync_to_physics = true
			body.position = closed_position
			body.z_index = MECHANISM_Z_INDEX
			body.set_meta(&"structure_id", structure_id)
			body.set_meta(&"dynamic_kind", "dynamic_door")
			body.set_meta(&"barrier_group_id", group_id)
			body.set_meta(&"socket_id", socket_id)
			var mechanism_kind: StringName = (
				&"archive_hatch"
				if group_id == "hatch_basement"
				else (&"horizontal_bulkhead" if closed_rect.size.x >= closed_rect.size.y else &"vertical_bulkhead")
			)
			var visual = _add_rect_collision_and_visual(
				body,
				closed_rect.size,
				Color(0.56, 0.63, 0.61, 1.0),
				mechanism_kind
			)
			add_child(body)
			var safety_area := _create_safety_envelope(
				("%s_%s_safety" % [group_id, socket_id]).to_pascal_case(),
				closed_position,
				closed_rect.size,
				socket_id,
				closed_rect
			)
			group_members.append({
				"body": body,
				"closed_position": closed_position,
				"open_position": open_position,
				"target_position": closed_position,
				"safety_area": safety_area,
				"visual": visual,
			})
		_barrier_groups[group_id] = {
			"open": false,
			"travel_speed": float(definition.get("travel_speed", 320.0)),
			"members": group_members,
		}


func _build_interactives(definitions: Array) -> void:
	_control_definitions.clear()
	_controls.clear()
	_power_panel = null
	_power_control_id = ""
	_power_lever_order.clear()
	_power_lever_definitions.clear()
	_power_initial_positions.clear()
	_power_lever_positions.clear()
	_power_circuits.clear()
	_power_diagnostics.clear()
	_power_clues.clear()
	for definition_value: Variant in definitions:
		var definition := (definition_value as Dictionary).duplicate(true)
		var control_id := str(definition.get("id", ""))
		var socket_id := str(definition.get("socket_id", ""))
		var control
		if str(definition.get("kind", "")) == "power_distributor":
			_configure_power_logic_runtime(definition)
			control = PowerDistributorPanelScript.new()
			control.name = ("Runtime_%s_Panel" % control_id).to_pascal_case()
			control.configure(definition, _socket_rect(socket_id), Callable(self, "_activate_power_lever"))
			_power_panel = control
		else:
			control = StructureInteractableScript.new()
			control.name = control_id.to_pascal_case()
			control.configure(definition, _socket_rect(socket_id), Callable(self, "_activate_control"))
		control.set_meta(&"structure_id", structure_id)
		control.set_meta(&"socket_id", socket_id)
		if str(definition.get("kind", "")) == "power_distributor":
			for lever_id: String in _power_lever_order:
				var lever = control.lever(lever_id)
				lever.set_meta(&"structure_id", structure_id)
				lever.set_meta(&"socket_id", socket_id)
				lever.set_meta(&"power_panel_control_id", control_id)
		_interactives_root.add_child(control)
		_control_definitions[control_id] = definition
		_controls[control_id] = control


func _configure_power_logic_runtime(definition: Dictionary) -> void:
	_power_control_id = str(definition.get("id", ""))
	var power_logic := definition.get("power_logic", {}) as Dictionary
	for lever_value: Variant in power_logic.get("levers", []):
		var lever_definition := (lever_value as Dictionary).duplicate(true)
		var lever_id := str(lever_definition.get("id", ""))
		_power_lever_order.append(lever_id)
		_power_lever_definitions[lever_id] = lever_definition
		_power_initial_positions[lever_id] = str(lever_definition.get("initial_position", "up"))
	_power_lever_positions = _power_initial_positions.duplicate(true)
	var circuits := power_logic.get("circuits", {}) as Dictionary
	for circuit_id: String in ["red", "blue", "yellow"]:
		_power_circuits[circuit_id] = (circuits.get(circuit_id, {}) as Dictionary).duplicate(true)
	_power_diagnostics = (power_logic.get("diagnostics", {}) as Dictionary).duplicate(true)
	_power_clues = (power_logic.get("clues", {}) as Dictionary).duplicate(true)


func _refresh_control_availability() -> void:
	for control_id_value: Variant in _controls.keys():
		var control_id := str(control_id_value)
		var control = _controls[control_id]
		var definition: Dictionary = _control_definitions[control_id]
		var kind := str(definition.get("kind", ""))
		var available := false
		match kind:
			"power_distributor":
				control.set_levers_available(true)
				continue
			"red_relay":
				available = _power_circuit_is_active("red") and not _red_latched
			"blue_lock":
				available = _power_circuit_is_active("blue") and not _blue_latched and elevator_reached_stop("floor_7")
			"d_valve":
				available = _power_circuit_is_active("yellow") and not _d_complete and not _d_requires_reset
			"d_reset":
				available = _power_circuit_is_active("yellow") and not _d_complete and (_d_progress > 0 or _d_requires_reset)
			"basement_hatch_control":
				available = _d_complete and not _basement_open
		control.set_available(available)
		var role := StringName(str(definition.get("visual_role", kind)))
		var visual_state := "locked"
		var telemetry := {}
		match kind:
			"red_relay":
				visual_state = "latched" if _red_latched else ("ready" if available else "locked")
			"blue_lock":
				visual_state = "latched" if _blue_latched else ("contact_closed" if _trolley_contact_closed else "waiting_for_trolley")
				telemetry["contact_closed"] = _trolley_contact_closed
			"d_valve":
				var step := int(definition.get("step", 0))
				telemetry["step"] = step
				telemetry["progress"] = _d_progress
				if _d_requires_reset:
					visual_state = "fault"
				elif _d_progress >= step:
					visual_state = "bolt_released" if step == 3 else "completed"
				elif available and step == _d_progress + 1:
					visual_state = "ready_step_%d" % step
				else:
					visual_state = "locked"
			"d_reset":
				visual_state = "fault" if _d_requires_reset else ("ready" if available else "locked")
			"basement_hatch_control":
				visual_state = "open" if _basement_open else ("ready" if available else "locked")
		if control.has_method("set_visual_state"):
			control.set_visual_state(role, visual_state, telemetry)
	_sync_power_panel_state()


func _sync_trolley_contact(play_feedback: bool) -> bool:
	var next_contact := (
		elevator_reached_stop("floor_7")
		and (_active_circuit_id == "blue" or _blue_latched)
	)
	if next_contact == _trolley_contact_closed:
		return false
	_trolley_contact_closed = next_contact
	if _elevator_body != null:
		_elevator_body.set_meta(&"trolley_contact_closed", _trolley_contact_closed)
	if play_feedback and _trolley_contact_closed:
		_play_feedback("trolley_contact_closed")
	_refresh_trolley_visual()
	return true


func _refresh_trolley_visual() -> void:
	if _elevator_visual == null or _elevator_body == null:
		return
	var state := "idle_floor_12"
	if _blue_latched:
		state = "latched_floor_7"
	elif _trolley_contact_closed:
		state = "contact_closed"
	elif _elevator_target_stop_id == "floor_7" and not elevator_reached_stop("floor_7"):
		state = "moving_down" if elevator_safety_clear() else "blocked_by_diver"
	elif _elevator_target_stop_id == "floor_12" and not elevator_reached_stop("floor_12"):
		state = "returning" if elevator_safety_clear() else "blocked_by_diver"
	_elevator_visual.set_visual_state(state)
	_elevator_body.set_meta(&"visual_state", state)


func _build_feedback_audio() -> void:
	if _feedback_player != null:
		return
	_feedback_player = AudioStreamPlayer.new()
	_feedback_player.name = "TowerMechanismFeedback"
	_feedback_player.volume_db = -8.0
	add_child(_feedback_player)


func _play_feedback(kind: String) -> void:
	_last_feedback_kind = kind
	set_meta(&"last_feedback_kind", _last_feedback_kind)
	if _feedback_player == null:
		return
	var frequency := 330.0
	var duration := 0.16
	match kind:
		"d_fault":
			frequency = 118.0
			duration = 0.32
		"trolley_contact_closed", "trolley_latched":
			frequency = 520.0
			duration = 0.22
		"archive_open":
			frequency = 240.0
			duration = 0.38
		"d_step_1", "d_step_2", "d_step_3":
			frequency = 350.0 + float(kind.right(1).to_int()) * 85.0
	var stream := _procedural_tone(frequency, duration)
	_feedback_player.stream = stream
	_feedback_player.play()


func _procedural_tone(frequency: float, duration: float) -> AudioStreamWAV:
	const MIX_RATE := 22050
	var sample_count := maxi(int(duration * float(MIX_RATE)), 1)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for sample_index: int in range(sample_count):
		var time := float(sample_index) / float(MIX_RATE)
		var normalized := float(sample_index) / float(sample_count)
		var envelope := sin(PI * normalized)
		var sample := sin(TAU * frequency * time) * envelope * 0.34
		data.encode_s16(sample_index * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


func _add_rect_collision_and_visual(
	body: AnimatableBody2D,
	size: Vector2,
	color: Color,
	mechanism_kind: StringName
):
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var visual = MechanismVisualScript.new()
	visual.name = "MechanismVisual"
	visual.configure(mechanism_kind, size, color)
	body.add_child(visual)
	return visual


func _create_safety_envelope(
	anchor_name: String,
	local_position: Vector2,
	body_size: Vector2,
	socket_id: String,
	closed_local_rect: Rect2
) -> Area2D:
	var anchor := Node2D.new()
	anchor.name = anchor_name
	anchor.position = local_position
	add_child(anchor)
	var area := Area2D.new()
	area.name = "SafetyEnvelope"
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.monitorable = false
	area.set_meta(&"socket_id", socket_id)
	area.set_meta(&"closed_local_rect", closed_local_rect)
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = body_size + Vector2.ONE * SAFETY_MARGIN * 2.0
	collision.shape = shape
	area.add_child(collision)
	anchor.add_child(area)
	return area


func _safety_area_clear(area: Area2D) -> bool:
	if area == null or not area.is_inside_tree():
		return true
	for body: Node2D in area.get_overlapping_bodies():
		if body.is_in_group(DIVE_PLAYER_GROUP):
			return false
	return true


func _set_elevator_safety_position(local_position: Vector2) -> void:
	if _elevator_safety_area == null:
		return
	var anchor := _elevator_safety_area.get_parent() as Node2D
	if anchor != null:
		anchor.position = local_position


func _teleport_animatable(body: AnimatableBody2D, target_position: Vector2) -> void:
	if body == null:
		return
	var was_synchronized := body.sync_to_physics
	body.sync_to_physics = false
	body.position = target_position
	if body.is_inside_tree():
		body.force_update_transform()
	body.sync_to_physics = was_synchronized


func _configuration_errors(structure_record: Dictionary, interactives_root: Node2D) -> PackedStringArray:
	var errors := PackedStringArray()
	var record_id := str(structure_record.get("id", ""))
	if record_id.is_empty():
		errors.append("Struktura runtime nie ma stabilnego id.")
	if interactives_root == null:
		errors.append("Struktura %s nie ma rootu Interactives." % record_id)
	var runtime_value: Variant = structure_record.get("runtime", null)
	if not runtime_value is Dictionary:
		errors.append("Struktura %s nie ma słownika runtime." % record_id)
		return errors
	var runtime := runtime_value as Dictionary
	if str(runtime.get("contract", "")) != CONTRACT_ID:
		errors.append("Struktura %s ma nieobsługiwany kontrakt runtime." % record_id)
	var socket_errors := _socket_configuration_errors(structure_record.get("sockets", null))
	errors.append_array(socket_errors)
	if not socket_errors.is_empty():
		return errors
	_index_sockets(structure_record.get("sockets", []) as Array)
	errors.append_array(_elevator_configuration_errors(runtime.get("elevator", null)))
	errors.append_array(_barrier_configuration_errors(runtime.get("barrier_groups", null)))
	errors.append_array(_interactive_configuration_errors(runtime.get("interactives", null)))
	return errors


func _socket_configuration_errors(sockets_value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not sockets_value is Array:
		errors.append("Struktura runtime nie ma tablicy sockets.")
		return errors
	var seen := {}
	for socket_value: Variant in sockets_value as Array:
		if not socket_value is Dictionary:
			errors.append("Socket struktury musi być słownikiem.")
			continue
		var socket := socket_value as Dictionary
		var socket_id := str(socket.get("id", ""))
		var rect := _rect_from_value(socket.get("local_rect", null))
		if socket_id.is_empty() or seen.has(socket_id):
			errors.append("Socket struktury ma puste albo powtórzone id: %s." % socket_id)
		elif rect.size.x <= 0.0 or rect.size.y <= 0.0:
			errors.append("Socket %s ma niepoprawny local_rect." % socket_id)
		seen[socket_id] = true
	return errors


func _elevator_configuration_errors(elevator_value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not elevator_value is Dictionary:
		errors.append("Kontrakt wieżowca wymaga jednej konfiguracji elevator.")
		return errors
	var elevator := elevator_value as Dictionary
	var socket_id := str(elevator.get("socket_id", ""))
	if not _socket_records.has(socket_id) or str((_socket_records.get(socket_id, {}) as Dictionary).get("kind", "")) != "moving_elevator":
		errors.append("Winda wskazuje nieznany socket moving_elevator: %s." % socket_id)
	var cabin_size := _vector_from_value(elevator.get("cabin_size", null))
	if cabin_size.x <= 0.0 or cabin_size.y <= 0.0:
		errors.append("Winda ma niepoprawny cabin_size.")
	if float(elevator.get("travel_speed", 0.0)) <= 0.0:
		errors.append("Winda musi mieć dodatni travel_speed.")
	var stops_value: Variant = elevator.get("stops", null)
	if not stops_value is Array:
		errors.append("Winda musi mieć tablicę stops.")
		return errors
	var stops := {}
	for stop_value: Variant in stops_value as Array:
		if not stop_value is Dictionary:
			errors.append("Przystanek windy musi być słownikiem.")
			continue
		var stop := stop_value as Dictionary
		var stop_id := str(stop.get("id", ""))
		if stop_id.is_empty() or stops.has(stop_id):
			errors.append("Przystanek windy ma puste albo powtórzone id: %s." % stop_id)
		stops[stop_id] = _vector_from_value(stop.get("local_center", null))
	for required_stop_id: String in ["floor_12", "floor_7"]:
		if not stops.has(required_stop_id):
			errors.append("Winda nie ma wymaganego przystanku %s." % required_stop_id)
	var initial_stop_id := str(elevator.get("initial_stop_id", ""))
	if not stops.has(initial_stop_id):
		errors.append("Winda wskazuje nieznany initial_stop_id: %s." % initial_stop_id)
	if _socket_records.has(socket_id) and cabin_size.x > 0.0 and cabin_size.y > 0.0:
		var travel_rect := _socket_rect(socket_id)
		for stop_id_value: Variant in stops.keys():
			var center: Vector2 = stops[stop_id_value]
			var cabin_rect := Rect2(center - cabin_size * 0.5, cabin_size)
			if not travel_rect.encloses(cabin_rect):
				errors.append("Kabina na przystanku %s wychodzi poza socket szybu." % str(stop_id_value))
	return errors


func _barrier_configuration_errors(groups_value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not groups_value is Array:
		errors.append("Kontrakt wieżowca wymaga tablicy barrier_groups.")
		return errors
	var groups := groups_value as Array
	if groups.size() != REQUIRED_GROUP_IDS.size():
		errors.append("Kontrakt wieżowca wymaga dokładnie 7 barrier_groups.")
	var seen_groups := {}
	var seen_sockets := {}
	for group_value: Variant in groups:
		if not group_value is Dictionary:
			errors.append("Barrier group musi być słownikiem.")
			continue
		var group := group_value as Dictionary
		var group_id := str(group.get("id", ""))
		if group_id.is_empty() or seen_groups.has(group_id):
			errors.append("Barrier group ma puste albo powtórzone id: %s." % group_id)
		seen_groups[group_id] = true
		if float(group.get("travel_speed", 0.0)) <= 0.0:
			errors.append("Barrier group %s musi mieć dodatni travel_speed." % group_id)
		var members_value: Variant = group.get("members", null)
		if not members_value is Array or (members_value as Array).is_empty():
			errors.append("Barrier group %s nie ma members." % group_id)
			continue
		for member_value: Variant in members_value as Array:
			if not member_value is Dictionary:
				errors.append("Członek barrier group %s musi być słownikiem." % group_id)
				continue
			var member := member_value as Dictionary
			var socket_id := str(member.get("socket_id", ""))
			var socket_kind := str((_socket_records.get(socket_id, {}) as Dictionary).get("kind", ""))
			if socket_kind != "dynamic_door":
				errors.append("Barrier group %s wskazuje nieznany socket dynamic_door: %s." % [group_id, socket_id])
			if seen_sockets.has(socket_id):
				errors.append("Socket dynamiczny %s należy do więcej niż jednej grupy." % socket_id)
			seen_sockets[socket_id] = true
			if not _is_vector_value(member.get("open_offset", null)):
				errors.append("Członek %s nie ma poprawnego open_offset." % socket_id)
	for required_group_id: String in REQUIRED_GROUP_IDS:
		if not seen_groups.has(required_group_id):
			errors.append("Brakuje barrier group %s." % required_group_id)
	return errors


func _interactive_configuration_errors(interactives_value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not interactives_value is Array:
		errors.append("Kontrakt wieżowca wymaga tablicy interactives.")
		return errors
	var interactives := interactives_value as Array
	if interactives.size() != 8:
		errors.append("Kontrakt wieżowca wymaga dokładnie 8 interactives.")
	var seen_ids := {}
	var seen_sockets := {}
	var kind_counts := {}
	var valve_steps := {}
	for definition_value: Variant in interactives:
		if not definition_value is Dictionary:
			errors.append("Interactive wieżowca musi być słownikiem.")
			continue
		var definition := definition_value as Dictionary
		var control_id := str(definition.get("id", ""))
		var socket_id := str(definition.get("socket_id", ""))
		var kind := str(definition.get("kind", ""))
		if control_id.is_empty() or seen_ids.has(control_id):
			errors.append("Interactive ma puste albo powtórzone id: %s." % control_id)
		seen_ids[control_id] = true
		if seen_sockets.has(socket_id):
			errors.append("Socket interactive %s jest użyty więcej niż raz." % socket_id)
		seen_sockets[socket_id] = true
		if str((_socket_records.get(socket_id, {}) as Dictionary).get("kind", "")) != "fixed_interactable":
			errors.append("Interactive %s wskazuje nieznany socket fixed_interactable: %s." % [control_id, socket_id])
		kind_counts[kind] = int(kind_counts.get(kind, 0)) + 1
		if float(definition.get("interaction_seconds", 0.0)) <= 0.0:
			errors.append("Interactive %s musi mieć dodatni interaction_seconds." % control_id)
		if kind != "power_distributor" and str(definition.get("visual_role", "")).is_empty():
			errors.append("Interactive %s nie ma prywatnej visual_role." % control_id)
		if kind == "d_valve":
			var step := int(definition.get("step", 0))
			if step < 1 or step > 3 or valve_steps.has(step):
				errors.append("Zawory D muszą mieć unikalne kroki 1, 2 i 3.")
			valve_steps[step] = true
		elif kind == "power_distributor":
			errors.append_array(_power_logic_configuration_errors(definition))
	for kind_value: Variant in REQUIRED_CONTROL_KIND_COUNTS.keys():
		var kind := str(kind_value)
		if int(kind_counts.get(kind, 0)) != int(REQUIRED_CONTROL_KIND_COUNTS[kind]):
			errors.append("Kontrakt wymaga %d kontrolek rodzaju %s." % [int(REQUIRED_CONTROL_KIND_COUNTS[kind]), kind])
	return errors


func _power_logic_configuration_errors(definition: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var power_logic_value: Variant = definition.get("power_logic", null)
	if not power_logic_value is Dictionary:
		errors.append("Rozdzielnia A nie ma słownika power_logic.")
		return errors
	var power_logic := power_logic_value as Dictionary
	if not _dictionary_has_exact_keys(power_logic, ["contract", "evaluation", "levers", "circuits", "diagnostics", "clues", "clue_summaries"]):
		errors.append("power_logic musi mieć dokładnie contract, evaluation, levers, circuits, diagnostics, clues i clue_summaries.")
	if str(power_logic.get("contract", "")) != POWER_LOGIC_CONTRACT_ID:
		errors.append("Rozdzielnia A ma nieobsługiwany kontrakt power_logic.")
	if str(power_logic.get("evaluation", "")) != POWER_EVALUATION_MODE:
		errors.append("Rozdzielnia A wymaga evaluation=on_toggle.")
	var levers_value: Variant = power_logic.get("levers", null)
	if not levers_value is Array:
		errors.append("Rozdzielnia A wymaga tablicy trzech levers.")
	else:
		var levers := levers_value as Array
		if levers.size() != 3:
			errors.append("Rozdzielnia A wymaga dokładnie trzech levers.")
		var seen_lever_ids := {}
		var lever_order := PackedStringArray()
		var distributor_socket := _socket_rect(str(definition.get("socket_id", "")))
		for lever_value: Variant in levers:
			if not lever_value is Dictionary:
				errors.append("Dźwignia rozdzielni A musi być słownikiem.")
				continue
			var lever := lever_value as Dictionary
			if not _dictionary_has_exact_keys(lever, ["id", "display_name", "initial_position", "local_rect"]):
				errors.append("Dźwignia rozdzielni A ma nieobsługiwany zestaw pól.")
			var lever_id := str(lever.get("id", ""))
			lever_order.append(lever_id)
			if lever_id.is_empty() or seen_lever_ids.has(lever_id):
				errors.append("Dźwignia rozdzielni A ma puste albo powtórzone id: %s." % lever_id)
			seen_lever_ids[lever_id] = true
			if str(lever.get("display_name", "")).is_empty():
				errors.append("Dźwignia %s nie ma display_name." % lever_id)
			if str(lever.get("initial_position", "")) != "up":
				errors.append("Dźwignia %s musi zaczynać w pozycji up." % lever_id)
			var lever_rect := _rect_from_value(lever.get("local_rect", null))
			if lever_rect.size.x <= 0.0 or lever_rect.size.y <= 0.0:
				errors.append("Dźwignia %s ma niepoprawny local_rect." % lever_id)
			elif not distributor_socket.encloses(lever_rect):
				errors.append("Dźwignia %s wychodzi poza socket rozdzielni A." % lever_id)
		if lever_order != PackedStringArray(REQUIRED_POWER_LEVER_IDS):
			errors.append("Rozdzielnia A wymaga lever IDs a_lever_1, a_lever_2, a_lever_3 w tej kolejności.")
	var circuits_value: Variant = power_logic.get("circuits", null)
	if not circuits_value is Dictionary:
		errors.append("Rozdzielnia A wymaga słownika circuits.")
		return errors
	var circuits := circuits_value as Dictionary
	if not _dictionary_has_exact_keys(circuits, ["red", "blue", "yellow"]):
		errors.append("Rozdzielnia A wymaga dokładnie obwodów red, blue i yellow.")
	for circuit_id: String in ["red", "blue", "yellow"]:
		var circuit_value: Variant = circuits.get(circuit_id, null)
		if not circuit_value is Dictionary:
			errors.append("Obwód %s rozdzielni A musi być słownikiem." % circuit_id)
			continue
		var circuit := circuit_value as Dictionary
		if not _dictionary_has_exact_keys(circuit, ["positions", "symbol", "barrier_group_id"]):
			errors.append("Obwód %s ma nieobsługiwany zestaw pól." % circuit_id)
		var expected := REQUIRED_CIRCUIT_DEFINITIONS[circuit_id] as Dictionary
		if not _string_array_equals(circuit.get("positions", null), expected["positions"] as Array):
			errors.append("Obwód %s ma niepoprawny wzorzec positions." % circuit_id)
		if str(circuit.get("symbol", "")) != str(expected["symbol"]):
			errors.append("Obwód %s ma niepoprawny symbol." % circuit_id)
		if str(circuit.get("barrier_group_id", "")) != str(expected["barrier_group_id"]):
			errors.append("Obwód %s wskazuje niepoprawną barrier_group_id." % circuit_id)
	var diagnostics_value: Variant = power_logic.get("diagnostics", null)
	if not diagnostics_value is Dictionary:
		errors.append("Rozdzielnia A wymaga słownika pięciu diagnostics.")
	else:
		var diagnostics := diagnostics_value as Dictionary
		if not _dictionary_has_exact_keys(diagnostics, REQUIRED_DIAGNOSTIC_IDS):
			errors.append("Rozdzielnia A wymaga dokładnie pięciu stabilnych reason_id.")
		var seen_position_keys := {}
		for reason_id: String in REQUIRED_DIAGNOSTIC_IDS:
			var diagnostic_value: Variant = diagnostics.get(reason_id, null)
			if not diagnostic_value is Dictionary:
				errors.append("Diagnostyka %s musi być słownikiem." % reason_id)
				continue
			var diagnostic := diagnostic_value as Dictionary
			if not _dictionary_has_exact_keys(diagnostic, ["positions", "message", "summary"]):
				errors.append("Diagnostyka %s wymaga positions, message i summary." % reason_id)
			var positions_value: Variant = diagnostic.get("positions", null)
			if not positions_value is Array or (positions_value as Array).size() != 3:
				errors.append("Diagnostyka %s wymaga trzech pozycji." % reason_id)
			else:
				var position_parts := PackedStringArray()
				for position_value: Variant in positions_value as Array:
					var position_text := str(position_value)
					if not position_value is String or position_text not in ["up", "down"]:
						errors.append("Diagnostyka %s może używać wyłącznie pozycji String up/down." % reason_id)
					position_parts.append(position_text)
				var position_key := "/".join(position_parts)
				if seen_position_keys.has(position_key):
					errors.append("Diagnostyki A nie mogą powtarzać układu %s." % position_key)
				seen_position_keys[position_key] = true
			if not _is_nonempty_text(diagnostic.get("message", null)):
				errors.append("Diagnostyka %s nie ma komunikatu." % reason_id)
			if not _is_nonempty_text(diagnostic.get("summary", null)):
				errors.append("Diagnostyka %s nie ma krótkiego tekstu prezentacyjnego." % reason_id)
		var valid_position_keys := {}
		for circuit_id: String in ["red", "blue", "yellow"]:
			var circuit_definition := REQUIRED_CIRCUIT_DEFINITIONS[circuit_id] as Dictionary
			var circuit_positions := circuit_definition.get("positions", []) as Array
			var circuit_position_parts := PackedStringArray()
			for position_value: Variant in circuit_positions:
				circuit_position_parts.append(str(position_value))
			valid_position_keys["/".join(circuit_position_parts)] = true
		var expected_invalid_position_keys := {}
		for first_position: String in ["up", "down"]:
			for second_position: String in ["up", "down"]:
				for third_position: String in ["up", "down"]:
					var position_key := "%s/%s/%s" % [first_position, second_position, third_position]
					if not valid_position_keys.has(position_key):
						expected_invalid_position_keys[position_key] = true
		for expected_position_key_value: Variant in expected_invalid_position_keys.keys():
			var expected_position_key := str(expected_position_key_value)
			if not seen_position_keys.has(expected_position_key):
				errors.append("Diagnostyki A nie pokrywają błędnego układu %s." % expected_position_key)
		for seen_position_key_value: Variant in seen_position_keys.keys():
			var seen_position_key := str(seen_position_key_value)
			if not expected_invalid_position_keys.has(seen_position_key):
				errors.append("Diagnostyka A opisuje układ, który nie jest błędnym dopełnieniem: %s." % seen_position_key)
	var clues_value: Variant = power_logic.get("clues", null)
	if not clues_value is Dictionary or not _dictionary_has_exact_keys(clues_value as Dictionary, ["red", "blue", "yellow"]):
		errors.append("Rozdzielnia A wymaga przesłanek red, blue i yellow.")
	else:
		for clue_id: String in ["red", "blue", "yellow"]:
			if not _is_nonempty_text((clues_value as Dictionary).get(clue_id, null)):
				errors.append("Przesłanka %s nie może być pusta." % clue_id)
	var clue_summaries_value: Variant = power_logic.get("clue_summaries", null)
	if not clue_summaries_value is Dictionary or not _dictionary_has_exact_keys(clue_summaries_value as Dictionary, ["red", "blue", "yellow"]):
		errors.append("Rozdzielnia A wymaga krótkich tekstów prezentacyjnych red, blue i yellow.")
	else:
		for clue_id: String in ["red", "blue", "yellow"]:
			if not _is_nonempty_text((clue_summaries_value as Dictionary).get(clue_id, null)):
				errors.append("Krótka przesłanka %s nie może być pusta." % clue_id)
	return errors


static func _is_nonempty_text(value: Variant) -> bool:
	return value is String and not str(value).strip_edges().is_empty()


static func _dictionary_has_exact_keys(value: Dictionary, required_keys: Array) -> bool:
	if value.size() != required_keys.size():
		return false
	for key_value: Variant in required_keys:
		if not value.has(str(key_value)):
			return false
	return true


static func _string_array_equals(value: Variant, expected: Array) -> bool:
	if not value is Array or (value as Array).size() != expected.size():
		return false
	var values := value as Array
	for value_index: int in range(expected.size()):
		if str(values[value_index]) != str(expected[value_index]):
			return false
	return true


func _index_sockets(sockets: Array) -> void:
	_socket_records.clear()
	for socket_value: Variant in sockets:
		var socket := socket_value as Dictionary
		_socket_records[str(socket.get("id", ""))] = socket.duplicate(true)


func _socket_rect(socket_id: String) -> Rect2:
	var socket: Dictionary = _socket_records.get(socket_id, {})
	return _rect_from_value(socket.get("local_rect", null))


static func _is_vector_value(value: Variant) -> bool:
	return value is Vector2 or (value is Array and (value as Array).size() == 2)


static func _vector_from_value(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Array and (value as Array).size() == 2:
		var values := value as Array
		return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO


static func _rect_from_value(value: Variant) -> Rect2:
	if value is Rect2:
		return value as Rect2
	if value is Array and (value as Array).size() == 4:
		var values := value as Array
		return Rect2(
			float(values[0]),
			float(values[1]),
			float(values[2]),
			float(values[3])
		)
	return Rect2()


static func _success(message: String) -> Dictionary:
	return {"success": true, "message": message}


static func _failure(message: String) -> Dictionary:
	return {"success": false, "message": message}
