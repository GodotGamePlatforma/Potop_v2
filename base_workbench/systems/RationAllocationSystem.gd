class_name RationAllocationSystem
extends RefCounted

const PolicyStateScript := preload("res://scripts/data/PolicyState.gd")

const RATION_FULL := "full"
const RATION_HALF := "half"
const RATION_NONE := "none"
const MAX_RATION_EFFICIENCY := 0.75


## Pure projection shared by the end-of-day resolver and the read-only Kitchen
## forecast. The returned allocation never mutates campaign state or food.
func project(
	policy: int,
	survivor_ids: Array,
	available_food: int,
	food_per_adult: int,
	ration_efficiency: float,
	diver_id: String = ""
) -> Dictionary:
	var ordered_ids := _normalized_survivor_ids(survivor_ids)
	var population := ordered_ids.size()
	var normalized_food := maxi(available_food, 0)
	var effective_efficiency := normalized_efficiency(ration_efficiency)
	var full_cost := full_ration_cost(population, food_per_adult, effective_efficiency)
	var half_cost := group_half_cost(population, full_cost)
	var result := _empty_result(policy, ordered_ids, normalized_food, full_cost, half_cost, diver_id, effective_efficiency)
	if population == 0:
		return result

	match policy:
		PolicyStateScript.RationPolicy.NONE:
			return result
		PolicyStateScript.RationPolicy.HALF:
			return _project_group_half(result, ordered_ids, normalized_food, false)
		PolicyStateScript.RationPolicy.DIVER_PRIORITY:
			if diver_id.is_empty() or not ordered_ids.has(diver_id):
				result["used_group_half_fallback"] = true
				return _project_group_half(result, ordered_ids, normalized_food, true)
			return _project_diver_priority(result, ordered_ids, normalized_food, diver_id)
		_:
			if normalized_food >= full_cost:
				result["actual_policy"] = PolicyStateScript.RationPolicy.FULL
				result["cost"] = full_cost
				for survivor_id in ordered_ids:
					_set_ration(result, survivor_id, RATION_FULL)
				return result
			result["used_group_half_fallback"] = true
			return _project_group_half(result, ordered_ids, normalized_food, true)


func full_ration_cost(population: int, food_per_adult: int, ration_efficiency: float) -> int:
	if population <= 0:
		return 0
	var raw_cost := float(population * maxi(food_per_adult, 0)) * (1.0 - normalized_efficiency(ration_efficiency))
	return maxi(int(round(raw_cost)), population)


func normalized_efficiency(ration_efficiency: float) -> float:
	return clampf(ration_efficiency, 0.0, MAX_RATION_EFFICIENCY)


func group_half_cost(population: int, full_cost: int) -> int:
	if population <= 0:
		return 0
	return maxi(
		int(ceil(float(maxi(full_cost, 0)) / 2.0)),
		int(ceil(float(population) / 2.0))
	)


func mixed_allocation_cost(population: int, full_cost: int, full_count: int, half_count: int) -> int:
	if population <= 0:
		return 0
	var units := 2 * maxi(full_count, 0) + maxi(half_count, 0)
	if units <= 0:
		return 0
	return maxi(
		int(ceil(float(maxi(full_cost, 0) * units) / float(2 * population))),
		int(ceil(float(units) / 2.0))
	)


func _project_group_half(
	result: Dictionary,
	ordered_ids: Array[String],
	available_food: int,
	is_fallback: bool
) -> Dictionary:
	result["used_group_half_fallback"] = bool(result.get("used_group_half_fallback", false)) or is_fallback
	var half_cost := int(result.get("half_cost", 0))
	if available_food < half_cost:
		result["shortage"] = true
		return result
	result["actual_policy"] = PolicyStateScript.RationPolicy.HALF
	result["cost"] = half_cost
	for survivor_id in ordered_ids:
		_set_ration(result, survivor_id, RATION_HALF)
	return result


func _project_diver_priority(
	result: Dictionary,
	ordered_ids: Array[String],
	available_food: int,
	diver_id: String
) -> Dictionary:
	result["diver_valid"] = true
	var population := ordered_ids.size()
	var full_cost := int(result.get("full_cost", 0))
	var full_count := 0
	var half_count := 0
	var diver_full_cost := mixed_allocation_cost(population, full_cost, 1, 0)
	result["diver_full_cost"] = diver_full_cost
	if available_food >= diver_full_cost:
		result["actual_policy"] = PolicyStateScript.RationPolicy.DIVER_PRIORITY
		full_count = 1
		_set_ration(result, diver_id, RATION_FULL)
	else:
		var diver_half_cost := mixed_allocation_cost(population, full_cost, 0, 1)
		result["diver_half_cost"] = diver_half_cost
		if available_food < diver_half_cost:
			result["shortage"] = true
			return result
		result["actual_policy"] = PolicyStateScript.RationPolicy.DIVER_PRIORITY
		half_count = 1
		_set_ration(result, diver_id, RATION_HALF)

	for survivor_id in ordered_ids:
		if survivor_id == diver_id:
			continue
		var candidate_half_count := half_count + 1
		var candidate_cost := mixed_allocation_cost(population, full_cost, full_count, candidate_half_count)
		if candidate_cost > available_food:
			break
		half_count = candidate_half_count
		_set_ration(result, survivor_id, RATION_HALF)

	result["cost"] = mixed_allocation_cost(population, full_cost, full_count, half_count)
	return result


func _empty_result(
	requested_policy: int,
	ordered_ids: Array[String],
	available_food: int,
	full_cost: int,
	half_cost: int,
	diver_id: String,
	effective_efficiency: float
) -> Dictionary:
	var ration_by_survivor_id: Dictionary = {}
	var unfed_recipient_ids: Array[String] = []
	for survivor_id in ordered_ids:
		ration_by_survivor_id[survivor_id] = RATION_NONE
		unfed_recipient_ids.append(survivor_id)
	return {
		"requested_policy": requested_policy,
		"actual_policy": PolicyStateScript.RationPolicy.NONE,
		"available_food": available_food,
		"full_cost": full_cost,
		"half_cost": half_cost,
		"effective_ration_efficiency": effective_efficiency,
		"cost": 0,
		"diver_id": diver_id,
		"diver_valid": false,
		"diver_full_cost": 0,
		"diver_half_cost": 0,
		"used_group_half_fallback": false,
		"shortage": false,
		"ration_by_survivor_id": ration_by_survivor_id,
		"full_recipient_ids": [] as Array[String],
		"half_recipient_ids": [] as Array[String],
		"unfed_recipient_ids": unfed_recipient_ids,
	}


func _set_ration(result: Dictionary, survivor_id: String, ration: String) -> void:
	result.ration_by_survivor_id[survivor_id] = ration
	result.full_recipient_ids.erase(survivor_id)
	result.half_recipient_ids.erase(survivor_id)
	result.unfed_recipient_ids.erase(survivor_id)
	match ration:
		RATION_FULL:
			result.full_recipient_ids.append(survivor_id)
		RATION_HALF:
			result.half_recipient_ids.append(survivor_id)
		_:
			result.unfed_recipient_ids.append(survivor_id)


func _normalized_survivor_ids(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var survivor_id := str(value)
		if not survivor_id.is_empty() and not result.has(survivor_id):
			result.append(survivor_id)
	return result
