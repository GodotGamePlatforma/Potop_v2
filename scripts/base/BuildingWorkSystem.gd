class_name BuildingWorkSystem
extends RefCounted

const DifficultyMathScript := preload("res://scripts/core/DifficultyMath.gd")
const ProfessionTalentSystemScript := preload("res://scripts/base/ProfessionTalentSystem.gd")
const WorkPaceSystemScript := preload("res://scripts/base/WorkPaceSystem.gd")

const FISHING_DAILY_PRESSURE_RECOVERY := 0.10
const FISHING_IDLE_PRESSURE_RECOVERY := 0.15
const MAXIMUM_FISHING_PRESSURE := 0.65
const MINIMUM_FISHING_EFFICIENCY := 0.35
const TALENT_FISHING_STEWARD := "rybak_straznik_lowiska"
const TALENT_FORCED_FISHING := "rybak_polow_forsowny"
const TALENT_MAINTAINER := "mechanik_konserwator"

const STATUS_APPLIED := "applied"
const STATUS_IDLE := "idle"
const STATUS_ZERO_OUTPUT := "zero_output"

const BLOCKER_NONE := ""
const BLOCKER_NO_CAPABLE_WORKERS := "no_capable_workers"
const BLOCKER_INVALID_CAPABILITIES := "invalid_capabilities"
const BLOCKER_FULL_INTEGRITY := "full_integrity"
const BLOCKER_INSUFFICIENT_SCRAP := "insufficient_scrap"

var _profession_talent_system = ProfessionTalentSystemScript.new()


## Builds a transient input shared by read-only forecasts and day settlement.
## The caller owns eligibility and passes IDs already accepted as capable. When
## a frozen efficiency map is supplied, missing entries intentionally contribute
## zero instead of falling back to mutable survivor state.
func workforce_from_capable_ids(
	state,
	definition,
	capable_worker_ids: Array,
	specialist_bonus_id: String,
	frozen_efficiency_by_worker = null
) -> Dictionary:
	var worker_ids: Array[String] = []
	var talent_ids: Array[String] = []
	var worker_units := 0.0
	var specialist_bonus := 0.0
	var use_frozen_efficiency := frozen_efficiency_by_worker is Dictionary
	var frozen_efficiency: Dictionary = {}
	if use_frozen_efficiency:
		frozen_efficiency = frozen_efficiency_by_worker
	if state == null or not state.has_method("find_survivor"):
		return _workforce_result(worker_ids, talent_ids, worker_units, specialist_bonus, use_frozen_efficiency)

	for worker_id in capable_worker_ids:
		var normalized_id := str(worker_id)
		if normalized_id.is_empty() or worker_ids.has(normalized_id):
			continue
		var survivor = state.find_survivor(normalized_id)
		if survivor == null:
			continue
		worker_ids.append(normalized_id)
		for talent_id in _survivor_talent_ids(survivor):
			if not talent_ids.has(talent_id):
				talent_ids.append(talent_id)
		if use_frozen_efficiency:
			if frozen_efficiency.has(normalized_id):
				worker_units += maxf(float(frozen_efficiency[normalized_id]), 0.0)
		else:
			worker_units += maxf(float(survivor.work_efficiency()), 0.0)
		if definition != null and not specialist_bonus_id.is_empty():
			specialist_bonus += float(definition.get_specialist_bonus_value(survivor, specialist_bonus_id))

	talent_ids.sort()
	return _workforce_result(worker_ids, talent_ids, worker_units, specialist_bonus, use_frozen_efficiency)


## Pure fishing projection. With no effective workforce the fishing ground uses
## the larger idle recovery; a valid staffed shift counts as work even when its
## rounded catch is zero.
func project_fishing(
	capabilities: Dictionary,
	workforce: Dictionary,
	pace: String,
	platform_integrity: int,
	fishing_pressure: float
) -> Dictionary:
	var result := _base_result(workforce)
	var pressure_before := fishing_pressure
	var has_effective_workforce := (
		int(result.worker_count) > 0
		and float(result.worker_units) > 0.0
	)
	var recovery := FISHING_DAILY_PRESSURE_RECOVERY if has_effective_workforce else FISHING_IDLE_PRESSURE_RECOVERY
	var pressure_after_recovery := maxf(pressure_before - recovery, 0.0)
	var has_fishing_steward := _has_workforce_talent(result, TALENT_FISHING_STEWARD)
	var has_forced_fishing := _has_workforce_talent(result, TALENT_FORCED_FISHING)
	var pressure_multiplier := 1.0
	if has_fishing_steward:
		pressure_multiplier *= _talent_float_parameter(TALENT_FISHING_STEWARD, "pressure_multiplier", 1.0)
	if has_forced_fishing:
		pressure_multiplier *= _talent_float_parameter(TALENT_FORCED_FISHING, "pressure_multiplier", 1.0)
	result.merge({
		"food_produced": 0,
		"food_per_worker": int(capabilities.get("food_per_worker", 0)),
		"fishing_pressure_per_food": float(capabilities.get("fishing_pressure_per_food", 0.0)),
		"fishing_pressure_before": pressure_before,
		"fishing_pressure_after_recovery": pressure_after_recovery,
		"fishing_pressure_after_catch": pressure_after_recovery,
		"pressure_recovery": recovery,
		"fishing_efficiency": 1.0,
		"fishing_pressure_multiplier": pressure_multiplier,
		"forced_fishing_food_bonus": 0,
		"has_fishing_steward": has_fishing_steward,
		"has_forced_fishing": has_forced_fishing,
		"work_output_multiplier": _work_output_multiplier(pace, platform_integrity),
	})
	if not has_effective_workforce:
		result.blocker_code = BLOCKER_NO_CAPABLE_WORKERS
		return result
	if (
		not capabilities.has("food_per_worker")
		or not capabilities.has("fishing_pressure_per_food")
		or int(capabilities.get("food_per_worker", 0)) <= 0
		or float(capabilities.get("fishing_pressure_per_food", 0.0)) <= 0.0
	):
		result.blocker_code = BLOCKER_INVALID_CAPABILITIES
		return result

	var specialist_bonus := int(round(float(result.specialist_bonus)))
	var produced_food := int(round(float(result.worker_units) * float(result.food_per_worker))) + specialist_bonus
	var fishing_efficiency := clampf(1.0 - pressure_after_recovery, MINIMUM_FISHING_EFFICIENCY, 1.0)
	produced_food = int(round(float(produced_food) * fishing_efficiency))
	produced_food = maxi(int(round(float(produced_food) * float(result.work_output_multiplier))), 0)
	if has_forced_fishing:
		var forced_food_bonus := _talent_int_parameter(TALENT_FORCED_FISHING, "food_bonus", 0)
		produced_food += forced_food_bonus
		result.forced_fishing_food_bonus = forced_food_bonus
	var pressure_after_catch := pressure_after_recovery
	if produced_food > 0:
		pressure_after_catch = clampf(
			pressure_after_recovery
			+ float(produced_food)
			* float(result.fishing_pressure_per_food)
			* pressure_multiplier,
			0.0,
			MAXIMUM_FISHING_PRESSURE
		)
	result.worked = true
	result.status_code = STATUS_APPLIED if produced_food > 0 else STATUS_ZERO_OUTPUT
	result.food_produced = produced_food
	result.specialist_bonus = specialist_bonus
	result.fishing_efficiency = fishing_efficiency
	result.fishing_pressure_after_catch = pressure_after_catch
	return result


## Pure automatic platform-repair projection. The returned carry represents the
## value that may be committed; failed or blocked attempts retain the input carry.
func project_platform_repair(
	capabilities: Dictionary,
	workforce: Dictionary,
	pace: String,
	platform_integrity: int,
	available_scrap: int,
	repair_cost_multiplier: float,
	repair_rounding_carry: float
) -> Dictionary:
	var result := _base_result(workforce)
	result.merge({
		"integrity_before": platform_integrity,
		"integrity_after": platform_integrity,
		"repair_per_worker": int(capabilities.get("platform_repair_per_worker", 0)),
		"repair_potential": 0,
		"maintainer_repair_bonus": 0,
		"repair_applied": 0,
		"available_scrap": maxi(available_scrap, 0),
		"scrap_cost": 0,
		"scrap_spent": 0,
		"rounding_carry_before": repair_rounding_carry,
		"rounding_carry_after": repair_rounding_carry,
		"work_output_multiplier": _work_output_multiplier(pace, platform_integrity),
	})
	if int(result.worker_count) <= 0 or float(result.worker_units) <= 0.0:
		result.blocker_code = BLOCKER_NO_CAPABLE_WORKERS
		return result
	if platform_integrity >= 100:
		result.blocker_code = BLOCKER_FULL_INTEGRITY
		return result
	if (
		not capabilities.has("platform_repair_per_worker")
		or not capabilities.has("repair_scrap_cost")
		or int(capabilities.get("platform_repair_per_worker", 0)) <= 0
		or int(capabilities.get("repair_scrap_cost", 0)) <= 0
	):
		result.blocker_code = BLOCKER_INVALID_CAPABILITIES
		return result

	var specialist_bonus := int(round(float(result.specialist_bonus)))
	var repair_potential := int(round(float(result.worker_units) * float(result.repair_per_worker))) + specialist_bonus
	repair_potential = maxi(int(round(float(repair_potential) * float(result.work_output_multiplier))), 0)
	var maintainer_bonus := 0
	if repair_potential > 0 and _has_workforce_talent(result, TALENT_MAINTAINER):
		maintainer_bonus = _talent_int_parameter(TALENT_MAINTAINER, "repair_integrity_bonus", 0)
		repair_potential += maintainer_bonus
	result.specialist_bonus = specialist_bonus
	result.maintainer_repair_bonus = maintainer_bonus
	result.repair_potential = repair_potential
	if repair_potential <= 0:
		result.status_code = STATUS_ZERO_OUTPUT
		return result

	var scaled_cost: Dictionary = DifficultyMathScript.scale_amortized_cost_amount(
		int(capabilities.get("repair_scrap_cost", 0)),
		repair_cost_multiplier,
		repair_rounding_carry
	)
	var scrap_cost := int(scaled_cost.get("amount", 0))
	result.scrap_cost = scrap_cost
	if int(result.available_scrap) < scrap_cost:
		result.blocker_code = BLOCKER_INSUFFICIENT_SCRAP
		return result

	var repair_applied := mini(repair_potential, maxi(100 - platform_integrity, 0))
	if repair_applied <= 0:
		result.blocker_code = BLOCKER_FULL_INTEGRITY
		return result
	result.worked = true
	result.status_code = STATUS_APPLIED
	result.repair_applied = repair_applied
	result.integrity_after = mini(platform_integrity + repair_applied, 100)
	result.scrap_spent = scrap_cost
	result.rounding_carry_after = float(scaled_cost.get("next_carry", repair_rounding_carry))
	return result


## Pure Community House work projection.
func project_community_work(
	capabilities: Dictionary,
	workforce: Dictionary,
	pace: String
) -> Dictionary:
	var result := _base_result(workforce)
	result.merge({
		"hope_per_worker": int(capabilities.get("hope_per_worker", 0)),
		"pace_adjustment_per_worker": WorkPaceSystemScript.community_worker_adjustment(pace),
		"adjusted_hope_per_worker": 0,
		"hope_gain": 0,
	})
	if int(result.worker_count) <= 0:
		result.blocker_code = BLOCKER_NO_CAPABLE_WORKERS
		return result
	if not capabilities.has("hope_per_worker") or int(capabilities.get("hope_per_worker", 0)) <= 0:
		result.blocker_code = BLOCKER_INVALID_CAPABILITIES
		return result

	var adjusted_per_worker := maxi(
		int(result.hope_per_worker) + int(result.pace_adjustment_per_worker),
		0
	)
	var specialist_bonus := int(round(float(result.specialist_bonus)))
	var hope_gain := int(result.worker_count) * adjusted_per_worker + specialist_bonus
	result.worked = true
	result.status_code = STATUS_APPLIED if hope_gain > 0 else STATUS_ZERO_OUTPUT
	result.adjusted_hope_per_worker = adjusted_per_worker
	result.specialist_bonus = specialist_bonus
	result.hope_gain = hope_gain
	return result


func _workforce_result(
	worker_ids: Array[String],
	talent_ids: Array[String],
	worker_units: float,
	specialist_bonus: float,
	uses_frozen_efficiency: bool
) -> Dictionary:
	return {
		"worker_ids": worker_ids,
		"talent_ids": talent_ids,
		"worker_count": worker_ids.size(),
		"worker_units": worker_units,
		"specialist_bonus": specialist_bonus,
		"uses_frozen_efficiency": uses_frozen_efficiency,
	}


func _base_result(workforce: Dictionary) -> Dictionary:
	var worker_ids: Array[String] = []
	worker_ids.assign(workforce.get("worker_ids", []))
	var talent_ids: Array[String] = []
	talent_ids.assign(workforce.get("talent_ids", []))
	return {
		"worked": false,
		"status_code": STATUS_IDLE,
		"blocker_code": BLOCKER_NONE,
		"worker_ids": worker_ids,
		"talent_ids": talent_ids,
		"worker_count": worker_ids.size(),
		"worker_units": maxf(float(workforce.get("worker_units", 0.0)), 0.0),
		"specialist_bonus": float(workforce.get("specialist_bonus", 0.0)),
	}


func _survivor_talent_ids(survivor) -> Array[String]:
	var result: Array[String] = []
	if survivor == null:
		return result
	var selected = survivor.get("profession_talent_ids")
	if not (selected is Dictionary):
		return result
	for raw_talent_id in selected.values():
		var talent_id := str(raw_talent_id).strip_edges()
		if (
			not talent_id.is_empty()
			and not result.has(talent_id)
			and _profession_talent_system.get_definition(talent_id) != null
			and ProfessionTalentSystemScript.has_talent(survivor, talent_id)
		):
			result.append(talent_id)
	return result


func _has_workforce_talent(workforce: Dictionary, talent_id: String) -> bool:
	return workforce.get("talent_ids", []).has(talent_id)


func _talent_float_parameter(talent_id: String, parameter_id: String, fallback: float) -> float:
	var definition = _profession_talent_system.get_definition(talent_id)
	return float(definition.parameters.get(parameter_id, fallback)) if definition != null else fallback


func _talent_int_parameter(talent_id: String, parameter_id: String, fallback: int) -> int:
	var definition = _profession_talent_system.get_definition(talent_id)
	return int(definition.parameters.get(parameter_id, fallback)) if definition != null else fallback


func _work_output_multiplier(pace: String, platform_integrity: int) -> float:
	var pace_multiplier := WorkPaceSystemScript.output_multiplier(pace)
	var integrity_multiplier := 1.0
	if platform_integrity < 50:
		integrity_multiplier = lerpf(
			0.55,
			0.85,
			clampf(float(platform_integrity) / 50.0, 0.0, 1.0)
		)
	return pace_multiplier * integrity_multiplier
