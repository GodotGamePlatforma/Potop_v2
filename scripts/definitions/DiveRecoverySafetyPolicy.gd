class_name DiveRecoverySafetyPolicy
extends Resource


@export var policy_id: StringName = &"default_recovery"
@export_range(0.001, 0.1, 0.001) var fixed_step_seconds: float = 1.0 / 30.0
@export_range(0.0, 0.95, 0.01) var minimum_oxygen_reserve_ratio: float = 0.20
@export_range(0.0, 0.95, 0.01) var minimum_health_reserve_ratio: float = 0.25
@export_range(0, 100, 1) var minimum_suit_condition: int = 30
@export_range(0.0, 100.0, 1.0) var maximum_cold_exposure: float = 88.0
@export_range(1, 8, 1) var planner_cell_stride: int = 4
## Dodatkowy prześwit wymagany tylko dla krawędzi planera przecinających
## aktywną strefę prądu; poza prądem obowiązuje kanoniczny gabaryt replayu.
@export_range(0.0, 64.0, 1.0) var planner_clearance_margin_world: float = 16.0
@export_range(1000, 1000000, 1000) var maximum_planner_expansions: int = 300_000
@export_range(30.0, 3600.0, 10.0) var maximum_replay_seconds: float = 900.0
@export_range(0.0, 120.0, 1.0) var threat_route_penalty_seconds: float = 36.0


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if str(policy_id).strip_edges().is_empty():
		errors.append("policy_id must not be empty")
	if not is_finite(fixed_step_seconds) or fixed_step_seconds < 0.001 or fixed_step_seconds > 0.1:
		errors.append("fixed_step_seconds must be between 0.001 and 0.1")
	if not is_finite(minimum_oxygen_reserve_ratio) or minimum_oxygen_reserve_ratio < 0.0 or minimum_oxygen_reserve_ratio > 0.95:
		errors.append("minimum_oxygen_reserve_ratio must be between 0 and 0.95")
	if not is_finite(minimum_health_reserve_ratio) or minimum_health_reserve_ratio < 0.0 or minimum_health_reserve_ratio > 0.95:
		errors.append("minimum_health_reserve_ratio must be between 0 and 0.95")
	if minimum_suit_condition < 0 or minimum_suit_condition > 100:
		errors.append("minimum_suit_condition must be between 0 and 100")
	if not is_finite(maximum_cold_exposure) or maximum_cold_exposure < 0.0 or maximum_cold_exposure > 100.0:
		errors.append("maximum_cold_exposure must be between 0 and 100")
	if planner_cell_stride < 1 or planner_cell_stride > 8:
		errors.append("planner_cell_stride must be between 1 and 8")
	if not is_finite(planner_clearance_margin_world) or planner_clearance_margin_world < 0.0 or planner_clearance_margin_world > 64.0:
		errors.append("planner_clearance_margin_world must be between 0 and 64")
	if maximum_planner_expansions < 1000:
		errors.append("maximum_planner_expansions must be at least 1000")
	if not is_finite(maximum_replay_seconds) or maximum_replay_seconds < 30.0:
		errors.append("maximum_replay_seconds must be at least 30")
	if not is_finite(threat_route_penalty_seconds) or threat_route_penalty_seconds < 0.0:
		errors.append("threat_route_penalty_seconds must be non-negative")
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()
