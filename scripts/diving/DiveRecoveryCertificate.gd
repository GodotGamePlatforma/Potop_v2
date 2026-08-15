class_name DiveRecoveryCertificate
extends Resource


const OK_SAFE := &"OK_SAFE"
const OK_FEASIBLE_RESERVE_SHORTFALL := &"OK_FEASIBLE_RESERVE_SHORTFALL"
const INVALID_QUERY := &"INVALID_QUERY"
const INVALID_POLICY := &"INVALID_POLICY"
const INVALID_SETUP := &"INVALID_SETUP"
const INVALID_SNAPSHOT := &"INVALID_SNAPSHOT"
const TARGET_NOT_FOUND := &"TARGET_NOT_FOUND"
const TARGET_UNAVAILABLE := &"TARGET_UNAVAILABLE"
const REQUIRED_TOOL_MISSING := &"REQUIRED_TOOL_MISSING"
const SOURCE_AMOUNT_UNAVAILABLE := &"SOURCE_AMOUNT_UNAVAILABLE"
const CAPACITY_SLOT_EXCEEDED := &"CAPACITY_SLOT_EXCEEDED"
const CAPACITY_MASS_EXCEEDED := &"CAPACITY_MASS_EXCEEDED"
const TARGET_UNREACHABLE := &"TARGET_UNREACHABLE"
const RETURN_UNREACHABLE := &"RETURN_UNREACHABLE"
const SHORTCUT_GATE_STATE_MISMATCH := &"SHORTCUT_GATE_STATE_MISMATCH"
const REPLAY_GEOMETRY_DIVERGED := &"REPLAY_GEOMETRY_DIVERGED"
const REPLAY_LIMIT_EXCEEDED := &"REPLAY_LIMIT_EXCEEDED"
const OXYGEN_DEPLETED := &"OXYGEN_DEPLETED"
const DIVER_DIED := &"DIVER_DIED"
const QUANTITY_NOT_RECOVERED := &"QUANTITY_NOT_RECOVERED"

@export var query_id: StringName = &""
@export var profile_id: StringName = &""
@export var difficulty_profile_id: StringName = &""
@export var safety_policy_id: StringName = &""
@export var trip_index: int = 0
@export var feasible: bool = false
@export var safe: bool = false
@export var reason_code: StringName = INVALID_QUERY
@export var reason_detail: String = ""
@export var entry_id: String = ""
@export var target_ids: Array[String] = []
@export var target_positions: Dictionary = {}
@export var recovered_items: Dictionary = {}
@export var maximum_recoverable_amount: int = 0
@export var oxygen_required: float = 0.0
@export var oxygen_remaining: float = 0.0
@export var oxygen_reserve_ratio: float = 0.0
@export var cargo_mass: float = 0.0
@export var cargo_slots: int = 0
@export var threat_exposure_seconds: float = 0.0
@export var health_remaining: int = 0
@export var health_reserve_ratio: float = 0.0
@export var suit_condition_remaining: int = 0
@export var cold_exposure: float = 0.0
@export var elapsed_seconds: float = 0.0
@export var planner_expansions: int = 0
@export var path_distance: float = 0.0
@export var route: PackedVector2Array = PackedVector2Array()


func to_dictionary(include_route: bool = true) -> Dictionary:
	var serialized_target_positions: Dictionary = {}
	var sorted_target_ids: Array = target_positions.keys()
	sorted_target_ids.sort()
	for target_id_value in sorted_target_ids:
		var target_id := str(target_id_value)
		var target_position: Vector2 = target_positions[target_id_value]
		serialized_target_positions[target_id] = [target_position.x, target_position.y]
	var result := {
		"query_id": str(query_id),
		"profile_id": str(profile_id),
		"difficulty_profile_id": str(difficulty_profile_id),
		"safety_policy_id": str(safety_policy_id),
		"trip_index": trip_index,
		"feasible": feasible,
		"safe": safe,
		"reason_code": str(reason_code),
		"reason_detail": reason_detail,
		"entry_id": entry_id,
		"target_ids": target_ids.duplicate(),
		"target_positions": serialized_target_positions,
		"recovered_items": recovered_items.duplicate(true),
		"maximum_recoverable_amount": maximum_recoverable_amount,
		"oxygen_required": oxygen_required,
		"oxygen_remaining": oxygen_remaining,
		"oxygen_reserve_ratio": oxygen_reserve_ratio,
		"cargo_mass": cargo_mass,
		"cargo_slots": cargo_slots,
		"threat_exposure_seconds": threat_exposure_seconds,
		"health_remaining": health_remaining,
		"health_reserve_ratio": health_reserve_ratio,
		"suit_condition_remaining": suit_condition_remaining,
		"cold_exposure": cold_exposure,
		"elapsed_seconds": elapsed_seconds,
		"planner_expansions": planner_expansions,
		"path_distance": path_distance,
	}
	if include_route:
		var route_values: Array = []
		for point in route:
			route_values.append([point.x, point.y])
		result["route"] = route_values
	return result
