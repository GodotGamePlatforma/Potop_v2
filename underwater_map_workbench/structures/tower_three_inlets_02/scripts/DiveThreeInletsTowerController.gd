extends Node2D

const ThreeInletsInteractableScript := preload(
	"res://underwater_map_workbench/structures/tower_three_inlets_02/scripts/DiveThreeInletsInteractable.gd"
)
const ThreeInletsMovingBodyScript := preload(
	"res://underwater_map_workbench/structures/tower_three_inlets_02/scripts/DiveThreeInletsMovingBody.gd"
)

const CONTRACT_ID := "three_inlets_tower_sequence_v1"
const REQUIRED_BARRIER_IDS := ["g1", "c_shortcut", "g2", "h3", "facade"]
const REQUIRED_CONTROL_IDS := ["panel_a", "inlet_b", "inlet_c", "d_v1", "d_v2", "d_reset", "inlet_d"]
const D_CONTROL_IDS := ["d_v1", "d_v2", "d_reset", "inlet_d"]
const CABINET_ID := "cabinet_d"
const CURRENT_CENTRAL_ID := "central_shaft"
const CURRENT_INLET_B_ID := "inlet_b"
const VISUAL_ROLE_SOLID_PANEL := "solid_panel"
const VISUAL_ROLE_EGRESS_GRILLE := "egress_grille"
const SUPPORTED_VISUAL_ROLES := [VISUAL_ROLE_SOLID_PANEL, VISUAL_ROLE_EGRESS_GRILLE]

const D_START := "D_START"
const D_MOVING_RIGHT := "D_MOVING_RIGHT"
const D_RIGHT_STOP := "D_RIGHT_STOP"
const D_MOVING_DOWN := "D_MOVING_DOWN"
const D_INLET_EXPOSED := "D_INLET_EXPOSED"
const D_ERROR_SAFE := "D_ERROR_SAFE"
const D_COMPLETE := "D_COMPLETE"

var structure_id: String = ""

var _configured := false
var _runtime_config: Dictionary = {}
var _socket_rects: Dictionary = {}
var _barriers: Dictionary = {}
var _control_definitions: Dictionary = {}
var _controls: Dictionary = {}
var _interactives_root: Node2D
var _cabinet
var _cabinet_right_position := Vector2.ZERO
var _cabinet_down_position := Vector2.ZERO

var _b_complete := false
var _c_complete := false
var _d_complete := false
var _d_state := D_START


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
	set_meta(&"persistence", "none")
	set_meta(&"checkpoint", "none")

	errors.append_array(_build_barriers(_runtime_config.get("barriers", []) as Array))
	errors.append_array(_build_cabinet(_runtime_config.get("cabinet", {}) as Dictionary))
	errors.append_array(_build_interactives(_runtime_config.get("interactives", []) as Array))
	if not errors.is_empty():
		return errors

	_configured = true
	reset_attempt()
	return errors


func reset_attempt() -> void:
	if not _configured:
		return
	_b_complete = false
	_c_complete = false
	_d_complete = false
	_d_state = D_START
	for barrier_id: String in REQUIRED_BARRIER_IDS:
		_set_barrier_open(barrier_id, false, true)
	if _cabinet != null:
		_cabinet.reset_home()
	_refresh_control_availability()


func activate_control(control_id: String) -> Dictionary:
	if not _configured or not _control_definitions.has(control_id):
		return _failure("Nieznane sterowanie wieżowca.", "activate")
	var definition := _control_definitions[control_id] as Dictionary
	var action := str(definition.get("interaction_action", "activate"))
	if _d_input_locked() and control_id in D_CONTROL_IDS:
		var ignored := _failure("Mechanizm D jest w ruchu. Wejście zostało zignorowane.", action)
		ignored["ignored"] = true
		ignored["control_id"] = control_id
		ignored["sequence_state"] = _sequence_state()
		ignored["d_state"] = _d_state
		return ignored

	var result: Dictionary
	match control_id:
		"panel_a":
			result = _inspect_panel_a(action)
		"inlet_b":
			result = _activate_inlet_b(action)
		"inlet_c":
			result = _activate_inlet_c(action)
		"d_v1", "d_v2", "d_reset", "inlet_d":
			result = _activate_d_control(control_id, action)
		_:
			result = _failure("Sterowanie ma nieobsługiwane ID.", action)
	result["control_id"] = control_id
	result["sequence_state"] = _sequence_state()
	result["d_state"] = _d_state
	_refresh_control_availability()
	return result


func control(control_id: String):
	return _controls.get(control_id, null)


func barrier_is_open(barrier_id: String) -> bool:
	if not _barriers.has(barrier_id):
		return false
	var barrier := _barriers[barrier_id] as Dictionary
	var body = barrier.get("body", null)
	return bool(barrier.get("commanded_open", false)) and body != null and body.reached_target()


func barrier_is_commanded_open(barrier_id: String) -> bool:
	if not _barriers.has(barrier_id):
		return false
	return bool((_barriers[barrier_id] as Dictionary).get("commanded_open", false))


func barrier_reached_target(barrier_id: String) -> bool:
	if not _barriers.has(barrier_id):
		return false
	var body = (_barriers[barrier_id] as Dictionary).get("body", null)
	return body != null and body.reached_target()


func barrier_open_progress(barrier_id: String) -> float:
	if not _barriers.has(barrier_id):
		return 0.0
	var barrier := _barriers[barrier_id] as Dictionary
	var body = barrier.get("body", null)
	if body == null:
		return 0.0
	var closed_position: Vector2 = barrier.get("closed_position", Vector2.ZERO)
	var open_position: Vector2 = barrier.get("open_position", Vector2.ZERO)
	var travel_distance := closed_position.distance_to(open_position)
	if travel_distance <= 0.0:
		return 0.0
	return clampf(closed_position.distance_to(body.position) / travel_distance, 0.0, 1.0)


func barrier_safety_clear(barrier_id: String) -> bool:
	if not _barriers.has(barrier_id):
		return false
	var body = (_barriers[barrier_id] as Dictionary).get("body", null)
	return body != null and body.safety_clear()


func cabinet_reached_target() -> bool:
	return _cabinet != null and not _d_input_locked() and _cabinet.reached_target()


func cabinet_safety_clear() -> bool:
	return _cabinet != null and _cabinet.safety_clear()


func current_at_world_position(world_position: Vector2) -> Vector2:
	if not _configured:
		return Vector2.ZERO
	var local_position := to_local(world_position)
	var local_current := Vector2.ZERO
	var currents := _runtime_config.get("currents", {}) as Dictionary
	var central := currents.get(CURRENT_CENTRAL_ID, {}) as Dictionary
	var central_rect := _socket_rect(str(central.get("socket_id", "")))
	if central_rect.has_point(local_position):
		var multipliers := central.get("stage_multipliers", []) as Array
		var stage_index := clampi(_completed_inlet_count(), 0, multipliers.size() - 1)
		local_current += _vector_from_value(central.get("velocity", Vector2.ZERO)) * float(multipliers[stage_index])

	var inlet_b := currents.get(CURRENT_INLET_B_ID, {}) as Dictionary
	if _completed_inlet_count() == int(inlet_b.get("active_stage", 0)):
		local_current += _inlet_b_current_at(local_position, inlet_b)
	return global_transform.basis_xform(local_current)


func state_snapshot() -> Dictionary:
	var barrier_states := {}
	for barrier_id: String in REQUIRED_BARRIER_IDS:
		barrier_states[barrier_id] = {
			"commanded_open": barrier_is_commanded_open(barrier_id),
			"open": barrier_is_open(barrier_id),
			"open_progress": barrier_open_progress(barrier_id),
			"reached_target": barrier_reached_target(barrier_id),
			"safety_clear": barrier_safety_clear(barrier_id),
		}
	var cabinet_state := {
		"local_position": _cabinet.position if _cabinet != null else Vector2.ZERO,
		"target_local_position": _cabinet.target_local_position() if _cabinet != null else Vector2.ZERO,
		"reached_target": cabinet_reached_target(),
		"safety_clear": cabinet_safety_clear(),
	}
	return {
		"contract": CONTRACT_ID,
		"structure_id": structure_id,
		"sequence_state": _sequence_state(),
		"b_complete": _b_complete,
		"c_complete": _c_complete,
		"d_complete": _d_complete,
		"d_state": _d_state,
		"d_input_locked": _d_input_locked(),
		"central_current_multiplier": _central_current_multiplier(),
		"b_current_active": _b_current_active(),
		"barriers": barrier_states,
		"cabinet": cabinet_state,
		"egress_open": barrier_is_open("facade"),
		"attempt_state": {
			"persistence": "none",
			"checkpoint": "none",
		},
	}


func _physics_process(delta: float) -> void:
	if not _configured:
		return
	for barrier_id: String in REQUIRED_BARRIER_IDS:
		var body = (_barriers[barrier_id] as Dictionary).get("body", null)
		if body != null:
			body.advance_motion(delta)
	if _cabinet == null:
		return
	var arrived: bool = bool(_cabinet.advance_motion(delta))
	if not arrived:
		return
	if _d_state == D_MOVING_RIGHT:
		_d_state = D_RIGHT_STOP
		_refresh_control_availability()
	elif _d_state == D_MOVING_DOWN:
		_d_state = D_INLET_EXPOSED
		_refresh_control_availability()


func _inspect_panel_a(action: String) -> Dictionary:
	var result := _success(
		"A: stan %s; zamknięte wloty %d/3; prąd szybu %.3f; G1=%s, G2=%s, H3=%s." % [
			_sequence_state(),
			_completed_inlet_count(),
			_central_current_multiplier(),
			"OTWARTA" if barrier_is_open("g1") else "ZAMKNIĘTA",
			"OTWARTA" if barrier_is_open("g2") else "ZAMKNIĘTA",
			"OTWARTA" if barrier_is_open("h3") else "ZAMKNIĘTA",
		],
		action,
		false
	)
	result["read_only"] = true
	result["effect"] = "read_only"
	return result


func _activate_inlet_b(action: String) -> Dictionary:
	if _b_complete:
		return _failure("Wlot B jest już zamknięty.", action)
	if _sequence_state() != "S0":
		return _failure("Wlot B nie jest dostępny w bieżącym stanie.", action)
	_b_complete = true
	_set_barrier_open("g1", true, false)
	return _success("Wlot B zamknięty. Prąd szybu osłabł do 2/3; G1 otwiera się.", action)


func _activate_inlet_c(action: String) -> Dictionary:
	if not _b_complete:
		return _failure("Najpierw zamknij wlot B.", action)
	if _c_complete:
		return _failure("Wlot C jest już zamknięty.", action)
	if _sequence_state() != "S1":
		return _failure("Wlot C nie jest dostępny w bieżącym stanie.", action)
	_c_complete = true
	_set_barrier_open("c_shortcut", true, false)
	_set_barrier_open("g2", true, false)
	return _success("Wlot C zamknięty. Otwierają się skrót C i G2; prąd szybu osłabł do 1/3.", action)


func _activate_d_control(control_id: String, action: String) -> Dictionary:
	if not _c_complete:
		return _failure("Najpierw ukończ wloty B i C.", action)
	if _d_state == D_COMPLETE:
		return _failure("Wlot D jest już zamknięty.", action)
	if _d_state == D_ERROR_SAFE and control_id != "d_reset":
		return _failure("Układ D jest w stanie bezpiecznym. Użyj RESET.", action)

	match control_id:
		"d_v1":
			if _d_state != D_START:
				return _enter_d_error(action, "V1 użyto poza pozycją startową.")
			if not _cabinet.can_travel_to_local_position_safely(_cabinet_right_position):
				return _failure(
					"V1 wstrzymany: nurek znajduje się w torze ruchu szafy.",
					action
				)
			_cabinet.request_local_target(_cabinet_right_position)
			_d_state = D_MOVING_RIGHT
			return _success("V1: szafa D przesuwa się w prawo.", action)
		"d_v2":
			if _d_state != D_RIGHT_STOP:
				return _enter_d_error(action, "V2 wymaga zatrzymania szafy po ruchu w prawo.")
			if not _cabinet.can_travel_to_local_position_safely(_cabinet_down_position):
				return _failure(
					"V2 wstrzymany: nurek znajduje się w torze ruchu szafy.",
					action
				)
			_cabinet.request_local_target(_cabinet_down_position)
			_d_state = D_MOVING_DOWN
			return _success("V2: szafa D przesuwa się w dół.", action)
		"inlet_d":
			if _d_state != D_INLET_EXPOSED:
				return _enter_d_error(action, "Dźwignia wlotu D nie jest jeszcze odsłonięta.")
			_d_complete = true
			_d_state = D_COMPLETE
			_set_barrier_open("h3", true, false)
			_set_barrier_open("facade", true, false)
			return _success("Wlot D zamknięty. Prąd szybu ustał; H3 i wyjście w fasadzie otwierają się.", action)
		"d_reset":
			return _reset_d_while_stable(action)
		_:
			return _failure("Nieznane sterowanie układu D.", action)


func _reset_d_while_stable(action: String) -> Dictionary:
	if _d_input_locked():
		return _failure("RESET jest zablokowany podczas ruchu szafy.", action)
	if _d_state == D_COMPLETE:
		return _failure("Ukończonego wlotu D nie resetuje się w tej próbie.", action)
	if not _cabinet.can_snap_to_local_position_safely(_cabinet.home_local_position()):
		return _failure("RESET wstrzymany: nurek znajduje się w torze bezpiecznego powrotu szafy.", action)
	_cabinet.reset_home()
	_d_state = D_START
	return _success("Układ D wrócił bezpiecznie do pozycji startowej.", action)


func _enter_d_error(action: String, reason: String) -> Dictionary:
	_d_state = D_ERROR_SAFE
	var result := _failure("%s Układ zatrzymany; użyj RESET." % reason, action)
	result["requires_reset"] = true
	result["state_changed"] = true
	return result


func _set_barrier_open(barrier_id: String, should_open: bool, snap: bool) -> void:
	if not _barriers.has(barrier_id):
		return
	var barrier := _barriers[barrier_id] as Dictionary
	barrier["commanded_open"] = should_open
	var body = barrier.get("body", null)
	var target: Vector2 = barrier.get(
		"open_position" if should_open else "closed_position",
		Vector2.ZERO
	)
	if body != null:
		if snap:
			body.snap_to_local_position(target)
		else:
			body.request_local_target(target)
	_barriers[barrier_id] = barrier


func _inlet_b_current_at(local_position: Vector2, definition: Dictionary) -> Vector2:
	for socket_id_value: Variant in definition.get("cover_socket_ids", []):
		if _socket_rect(str(socket_id_value)).has_point(local_position):
			return Vector2.ZERO
	var recovery_socket_id := str(definition.get("recovery_socket_id", ""))
	if _socket_rect(recovery_socket_id).has_point(local_position):
		return _vector_from_value(definition.get("recovery_velocity", Vector2.ZERO))
	var main_socket_id := str(definition.get("socket_id", ""))
	if _socket_rect(main_socket_id).has_point(local_position):
		return _vector_from_value(definition.get("velocity", Vector2.ZERO))
	return Vector2.ZERO


func _central_current_multiplier() -> float:
	var currents := _runtime_config.get("currents", {}) as Dictionary
	var definition := currents.get(CURRENT_CENTRAL_ID, {}) as Dictionary
	var multipliers := definition.get("stage_multipliers", []) as Array
	if multipliers.size() != 4:
		return 0.0
	return float(multipliers[clampi(_completed_inlet_count(), 0, 3)])


func _b_current_active() -> bool:
	var currents := _runtime_config.get("currents", {}) as Dictionary
	var definition := currents.get(CURRENT_INLET_B_ID, {}) as Dictionary
	return _completed_inlet_count() == int(definition.get("active_stage", 0))


func _completed_inlet_count() -> int:
	return int(_b_complete) + int(_c_complete) + int(_d_complete)


func _sequence_state() -> String:
	match _completed_inlet_count():
		0:
			return "S0"
		1:
			return "S1"
		2:
			return "S2"
		_:
			return "S3"


func _d_input_locked() -> bool:
	return _d_state == D_MOVING_RIGHT or _d_state == D_MOVING_DOWN


func _refresh_control_availability() -> void:
	var moving := _d_input_locked()
	var d_wrong_order_enabled := (
		not moving
		and _sequence_state() == "S2"
		and _d_state != D_ERROR_SAFE
		and _d_state != D_COMPLETE
	)
	for control_id: String in REQUIRED_CONTROL_IDS:
		var node = _controls.get(control_id, null)
		if node == null:
			continue
		var available := false
		match control_id:
			"panel_a":
				available = true
			"inlet_b":
				available = not moving and _sequence_state() == "S0"
			"inlet_c":
				available = not moving and _sequence_state() == "S1"
			"d_v1":
				available = d_wrong_order_enabled
			"d_v2":
				available = d_wrong_order_enabled
			"inlet_d":
				available = not moving and _sequence_state() == "S2" and _d_state == D_INLET_EXPOSED
			"d_reset":
				available = (
					not moving
					and _sequence_state() == "S2"
					and _d_state != D_COMPLETE
					and _d_state != D_START
				)
		node.set_available(available)


func _build_barriers(definitions: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	_barriers.clear()
	for definition_value: Variant in definitions:
		var definition := definition_value as Dictionary
		var barrier_id := str(definition.get("id", ""))
		var socket_id := str(definition.get("socket_id", ""))
		var socket_rect := _socket_rect(socket_id)
		var body = ThreeInletsMovingBodyScript.new()
		body.name = barrier_id.to_pascal_case()
		var body_errors: PackedStringArray = body.configure(definition, socket_rect, structure_id)
		if not body_errors.is_empty():
			errors.append_array(body_errors)
			body.free()
			continue
		body.set_meta(&"barrier_id", barrier_id)
		add_child(body)
		var closed_position := socket_rect.get_center()
		var open_position := closed_position + _vector_from_value(definition.get("open_offset", Vector2.ZERO))
		body.snap_to_local_position(closed_position)
		_barriers[barrier_id] = {
			"body": body,
			"commanded_open": false,
			"closed_position": closed_position,
			"open_position": open_position,
		}
	return errors


func _build_cabinet(definition: Dictionary) -> PackedStringArray:
	var socket_id := str(definition.get("socket_id", ""))
	var socket_rect := _socket_rect(socket_id)
	_cabinet = ThreeInletsMovingBodyScript.new()
	_cabinet.name = "CabinetD"
	var errors: PackedStringArray = _cabinet.configure(definition, socket_rect, structure_id)
	if not errors.is_empty():
		_cabinet.free()
		_cabinet = null
		return errors
	_cabinet.set_meta(&"cabinet_id", CABINET_ID)
	add_child(_cabinet)
	var home: Vector2 = _cabinet.home_local_position()
	_cabinet_right_position = home + _vector_from_value(definition.get("move_right", Vector2.ZERO))
	_cabinet_down_position = _cabinet_right_position + _vector_from_value(definition.get("move_down", Vector2.ZERO))
	_cabinet.reset_home()
	return errors


func _build_interactives(definitions: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	_control_definitions.clear()
	_controls.clear()
	for definition_value: Variant in definitions:
		var definition := definition_value as Dictionary
		var control_id := str(definition.get("id", ""))
		var socket_id := str(definition.get("socket_id", ""))
		var socket_rect := _socket_rect(socket_id)
		var interactive = ThreeInletsInteractableScript.new()
		interactive.name = control_id.to_pascal_case()
		interactive.configure(definition, socket_rect, Callable(self, "_on_interactive_activated"))
		_interactives_root.add_child(interactive)
		_control_definitions[control_id] = definition
		_controls[control_id] = interactive
	return errors


func _on_interactive_activated(control_id: String) -> Dictionary:
	return activate_control(control_id)


func _index_sockets(socket_values: Array) -> void:
	_socket_rects.clear()
	for socket_value: Variant in socket_values:
		var socket := socket_value as Dictionary
		_socket_rects[str(socket.get("id", ""))] = _rect_from_value(socket.get("local_rect", []))


func _socket_rect(socket_id: String) -> Rect2:
	return _socket_rects.get(socket_id, Rect2()) as Rect2


func _configuration_errors(
	structure_record: Dictionary,
	interactives_root: Node2D
) -> PackedStringArray:
	var errors := PackedStringArray()
	if _configured:
		errors.append("Kontroler %s może być skonfigurowany tylko raz." % CONTRACT_ID)
	if str(structure_record.get("id", "")).is_empty():
		errors.append("Instancja struktury nie ma stable ID przekazanego przez hosta Mapy.")
	if interactives_root == null:
		errors.append("Host nie przekazał lokalnego Interactives root.")

	var runtime := structure_record.get("runtime", {}) as Dictionary
	if str(runtime.get("contract", "")) != CONTRACT_ID:
		errors.append("Runtime struktury musi używać kontraktu %s." % CONTRACT_ID)
	if structure_record.has("attempt_state"):
		var attempt_state := structure_record.get("attempt_state", {}) as Dictionary
		if str(attempt_state.get("persistence", "")) != "none":
			errors.append("W02 nie może publikować persistence.")
		if str(attempt_state.get("checkpoint", "")) != "none":
			errors.append("W02 nie może publikować checkpointu.")
		if str(attempt_state.get("reset", "")) != "whole_structure_attempt":
			errors.append("W02 musi resetować całą lokalną próbę.")
	if structure_record.has("persistent_id") or runtime.has("persistent_id"):
		errors.append("W02 nie może deklarować persistent_id.")

	var socket_ids := {}
	for socket_value: Variant in structure_record.get("sockets", []) as Array:
		var socket := socket_value as Dictionary
		var socket_id := str(socket.get("id", ""))
		if socket_id.is_empty() or socket_ids.has(socket_id):
			errors.append("Socket struktury ma puste lub zduplikowane ID: %s." % socket_id)
			continue
		var socket_rect := _rect_from_value(socket.get("local_rect", []))
		if socket_rect.size.x <= 0.0 or socket_rect.size.y <= 0.0:
			errors.append("Socket %s ma nieprawidłowy local_rect." % socket_id)
		socket_ids[socket_id] = true

	var barriers := runtime.get("barriers", []) as Array
	var barrier_ids := {}
	for barrier_value: Variant in barriers:
		var barrier := barrier_value as Dictionary
		var barrier_id := str(barrier.get("id", ""))
		barrier_ids[barrier_id] = true
		_validate_socket_reference(barrier, socket_ids, "bariera %s" % barrier_id, errors)
		if _vector_from_value(barrier.get("open_offset", Vector2.ZERO)) == Vector2.ZERO:
			errors.append("Bariera %s wymaga niezerowego open_offset." % barrier_id)
		if float(barrier.get("travel_speed", 0.0)) <= 0.0:
			errors.append("Bariera %s wymaga dodatniego travel_speed." % barrier_id)
		var visual_role := str(barrier.get("visual_role", ""))
		if not visual_role in SUPPORTED_VISUAL_ROLES:
			errors.append("Bariera %s ma nieobsługiwany visual_role: %s." % [barrier_id, visual_role])
		elif barrier_id == "facade" and visual_role != VISUAL_ROLE_EGRESS_GRILLE:
			errors.append("Fasada W02 musi używać visual_role=egress_grille.")
		elif barrier_id != "facade" and visual_role != VISUAL_ROLE_SOLID_PANEL:
			errors.append("Bariera %s musi używać visual_role=solid_panel." % barrier_id)
	if barriers.size() != REQUIRED_BARRIER_IDS.size():
		errors.append("W02 wymaga dokładnie pięciu barier kontraktu.")
	for barrier_id: String in REQUIRED_BARRIER_IDS:
		if not barrier_ids.has(barrier_id):
			errors.append("Brakuje bariery %s." % barrier_id)

	var cabinet := runtime.get("cabinet", {}) as Dictionary
	if str(cabinet.get("id", "")) != CABINET_ID:
		errors.append("Ruchoma szafa musi mieć ID %s." % CABINET_ID)
	_validate_socket_reference(cabinet, socket_ids, "szafa D", errors)
	if _vector_from_value(cabinet.get("move_right", Vector2.ZERO)).x <= 0.0:
		errors.append("Szafa D wymaga dodatniego ruchu move_right na osi X.")
	if _vector_from_value(cabinet.get("move_down", Vector2.ZERO)).y <= 0.0:
		errors.append("Szafa D wymaga dodatniego ruchu move_down na osi Y.")
	if float(cabinet.get("travel_speed", 0.0)) <= 0.0:
		errors.append("Szafa D wymaga dodatniego travel_speed.")
	if str(cabinet.get("visual_role", "")) != VISUAL_ROLE_SOLID_PANEL:
		errors.append("Szafa D musi używać visual_role=solid_panel.")

	var interactives := runtime.get("interactives", []) as Array
	var control_ids := {}
	for definition_value: Variant in interactives:
		var definition := definition_value as Dictionary
		var control_id := str(definition.get("id", ""))
		control_ids[control_id] = true
		_validate_socket_reference(definition, socket_ids, "sterowanie %s" % control_id, errors)
		if str(definition.get("display_name", "")).is_empty():
			errors.append("Sterowanie %s wymaga tekstowego podpisu." % control_id)
		if str(definition.get("symbol", "")).is_empty():
			errors.append("Sterowanie %s wymaga redundantnego symbolu/kształtu." % control_id)
		if float(definition.get("interaction_seconds", 0.0)) <= 0.0:
			errors.append("Sterowanie %s wymaga dodatniego interaction_seconds." % control_id)
		_validate_control_definition(control_id, definition, errors)
	if interactives.size() != REQUIRED_CONTROL_IDS.size():
		errors.append("W02 wymaga dokładnie siedmiu sterowań kontraktu.")
	for control_id: String in REQUIRED_CONTROL_IDS:
		if not control_ids.has(control_id):
			errors.append("Brakuje sterowania %s." % control_id)

	var currents := runtime.get("currents", {}) as Dictionary
	if currents.size() != 2 or not currents.has(CURRENT_CENTRAL_ID) or not currents.has(CURRENT_INLET_B_ID):
		errors.append("W02 wymaga wyłącznie pól prądu central_shaft i inlet_b.")
	else:
		_validate_current_contract(currents, socket_ids, errors)

	var egress_socket_id := str(runtime.get("egress_socket_id", ""))
	if egress_socket_id.is_empty() or not socket_ids.has(egress_socket_id):
		errors.append("W02 wymaga poprawnego egress_socket_id.")
	return errors


func _validate_control_definition(
	control_id: String,
	definition: Dictionary,
	errors: PackedStringArray
) -> void:
	var kind := str(definition.get("kind", ""))
	match control_id:
		"panel_a":
			if kind != "status_panel":
				errors.append("panel_a musi pozostać wyłącznie statusem status_panel.")
		"inlet_b":
			if kind != "inlet_lever" or int(definition.get("stage", -1)) != 0:
				errors.append("inlet_b musi być dźwignią etapu S0.")
		"inlet_c":
			if kind != "inlet_lever" or int(definition.get("stage", -1)) != 1:
				errors.append("inlet_c musi być dźwignią etapu S1.")
		"d_v1", "d_v2":
			if kind != "d_valve":
				errors.append("%s musi mieć kind=d_valve." % control_id)
		"d_reset":
			if kind != "d_reset":
				errors.append("d_reset musi mieć kind=d_reset.")
		"inlet_d":
			if kind != "inlet_lever" or int(definition.get("stage", -1)) != 2:
				errors.append("inlet_d musi być dźwignią etapu S2.")


func _validate_current_contract(
	currents: Dictionary,
	socket_ids: Dictionary,
	errors: PackedStringArray
) -> void:
	var central := currents.get(CURRENT_CENTRAL_ID, {}) as Dictionary
	_validate_socket_reference(central, socket_ids, "prąd central_shaft", errors)
	var multipliers := central.get("stage_multipliers", []) as Array
	var expected := [1.0, 2.0 / 3.0, 1.0 / 3.0, 0.0]
	if multipliers.size() != expected.size():
		errors.append("central_shaft wymaga czterech mnożników 1, 2/3, 1/3, 0.")
	else:
		for index: int in range(expected.size()):
			if not is_equal_approx(float(multipliers[index]), float(expected[index])):
				errors.append("central_shaft ma błędny mnożnik etapu %d." % index)
	if _vector_from_value(central.get("velocity", Vector2.ZERO)) == Vector2.ZERO:
		errors.append("central_shaft wymaga niezerowego velocity.")

	var inlet_b := currents.get(CURRENT_INLET_B_ID, {}) as Dictionary
	_validate_socket_reference(inlet_b, socket_ids, "prąd inlet_b", errors)
	if int(inlet_b.get("active_stage", -1)) != 0:
		errors.append("Prąd inlet_b może być aktywny wyłącznie w S0.")
	var inlet_velocity := _vector_from_value(inlet_b.get("velocity", Vector2.ZERO))
	var recovery_velocity := _vector_from_value(inlet_b.get("recovery_velocity", Vector2.ZERO))
	if inlet_velocity == Vector2.ZERO:
		errors.append("Prąd inlet_b wymaga niezerowego velocity.")
	if recovery_velocity == Vector2.ZERO or inlet_velocity.dot(recovery_velocity) >= 0.0:
		errors.append("Recovery inlet_b musi mieć niezerowy wektor przeciwny do głównego prądu.")
	var cover_socket_ids := inlet_b.get("cover_socket_ids", []) as Array
	if cover_socket_ids.is_empty():
		errors.append("Prąd inlet_b wymaga co najmniej jednego socketu osłony.")
	for socket_id_value: Variant in cover_socket_ids:
		if not socket_ids.has(str(socket_id_value)):
			errors.append("Prąd inlet_b odwołuje się do nieznanej osłony %s." % str(socket_id_value))
	var recovery_socket_id := str(inlet_b.get("recovery_socket_id", ""))
	if recovery_socket_id.is_empty() or not socket_ids.has(recovery_socket_id):
		errors.append("Prąd inlet_b wymaga poprawnego recovery_socket_id.")


func _validate_socket_reference(
	definition: Dictionary,
	socket_ids: Dictionary,
	label: String,
	errors: PackedStringArray
) -> void:
	var socket_id := str(definition.get("socket_id", ""))
	if socket_id.is_empty() or not socket_ids.has(socket_id):
		errors.append("%s odwołuje się do nieznanego socketu %s." % [label, socket_id])


func _rect_from_value(value: Variant) -> Rect2:
	if value is Rect2:
		return value as Rect2
	if value is Array:
		var values := value as Array
		if values.size() == 4:
			return Rect2(
				float(values[0]),
				float(values[1]),
				float(values[2]),
				float(values[3])
			)
	return Rect2()


func _vector_from_value(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Array:
		var values := value as Array
		if values.size() == 2:
			return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO


func _success(message: String, action: String, mutated: bool = true) -> Dictionary:
	return {
		"success": true,
		"message": message,
		"interaction_action": action,
		"mutated": mutated,
	}


func _failure(message: String, action: String) -> Dictionary:
	return {
		"success": false,
		"message": message,
		"interaction_action": action,
		"mutated": false,
	}
