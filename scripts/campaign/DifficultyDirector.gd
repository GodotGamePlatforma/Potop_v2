class_name DifficultyDirector
extends RefCounted

const PressureStateScript := preload("res://scripts/data/PressureState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const WeatherStateScript := preload("res://scripts/data/WeatherState.gd")

const ENTER_LOW_STRAIN := 0.28
const EXIT_LOW_STRAIN := 0.38
const ENTER_HIGH_STRAIN := 0.62
const EXIT_HIGH_STRAIN := 0.50
const HARDSHIP_RECOVERY_DAYS := 1
const MAJOR_EVENT_COOLDOWN_DAYS := 2

## Builds the immutable-for-the-day difficulty snapshot. The caller must pass the
## state after advancing to the new day and only the DiveResult just resolved.
## This method does not mutate the state, previous snapshot, profile or RNG.
func build_for_day(state, previous_pressure: Resource = null, resolved_dive_result: Resource = null) -> Resource:
	if state == null:
		return null
	var pressure = PressureStateScript.new()
	pressure.day = maxi(int(state.day), 1)
	_capture_metrics(pressure, state)
	var previous = previous_pressure if _is_previous_day(previous_pressure, pressure.day) else null
	_capture_recent_history(pressure, previous, resolved_dive_result)
	_capture_recovery_state(pressure, state, previous, resolved_dive_result)
	pressure.critical_gates = _critical_gates(pressure, resolved_dive_result)
	pressure.strain = _calculate_strain(pressure)
	pressure.band = _select_band(pressure.strain, pressure.critical_gates, pressure.crisis_active, previous)
	pressure.consecutive_high_days = _consecutive_high_days(pressure.band, previous)
	pressure.recovery_needed = pressure.consecutive_high_days >= 2 or pressure.band == PressureStateScript.Band.CRISIS
	pressure.reason_codes = _reason_codes(pressure)
	pressure.active_pressure_tags = _active_pressure_tags(pressure)
	pressure.blocked_impact_tags = _blocked_impact_tags(pressure)
	pressure.preferred_impact_tags = _preferred_impact_tags(pressure)
	pressure.recovery_roles = _recovery_roles(pressure)
	_apply_daily_limits(pressure)
	pressure.refresh_debug_summary()
	return pressure

func _capture_metrics(pressure, state) -> void:
	var alive: Array = state.get_alive_survivors() if state.has_method("get_alive_survivors") else []
	pressure.population = alive.size()
	pressure.food_days = maxf(float(state.get_food_days_left()), 0.0) if state.has_method("get_food_days_left") else 0.0
	var hunger_total := 0.0
	var highest_hunger := 0
	var workers := 0
	var active_disease_cases := 0
	var contagious_disease_cases := 0
	for survivor in alive:
		if survivor == null:
			continue
		var hunger := clampi(int(survivor.hunger), 0, 100)
		hunger_total += hunger
		highest_hunger = maxi(highest_hunger, hunger)
		if survivor.has_method("can_work") and survivor.can_work():
			workers += 1
		if not survivor.is_present_in_settlement():
			continue
		var has_active_case := false
		var has_contagious_case := false
		for disease_case in survivor.disease_cases:
			if disease_case == null:
				continue
			if str(disease_case.phase_id()) != "immune":
				has_active_case = true
			if disease_case.is_infectious():
				has_contagious_case = true
		if has_active_case:
			active_disease_cases += 1
		if has_contagious_case:
			contagious_disease_cases += 1
	pressure.average_hunger = hunger_total / float(maxi(pressure.population, 1))
	pressure.max_hunger = highest_hunger
	pressure.healthy_workers = workers
	pressure.active_disease_cases = active_disease_cases
	pressure.contagious_disease_cases = contagious_disease_cases
	pressure.disease_outbreak_active = state.disease_campaign != null and bool(state.disease_campaign.outbreak_active)
	pressure.hope = _resource_amount(state, ResourceIdsScript.HOPE)
	pressure.platform_integrity = _resource_amount(state, ResourceIdsScript.PLATFORM_INTEGRITY)
	pressure.basic_materials = _resource_amount(state, ResourceIdsScript.PLANKS) + _resource_amount(state, ResourceIdsScript.SCRAP)
	pressure.medicines = _resource_amount(state, ResourceIdsScript.MEDS_CHEMICALS)
	pressure.shelter_capacity = _shelter_capacity(state)
	pressure.free_shelter = pressure.shelter_capacity - pressure.population
	if state.story_flags != null:
		pressure.story_act = maxi(int(state.story_flags.act), 1)
		pressure.crisis_active = bool(state.story_flags.crisis_active)
	if state.weather != null:
		pressure.weather_condition = int(state.weather.condition)
		pressure.storm_today = state.weather.has_method("is_storm") and state.weather.is_storm()
	pressure.tutorial_protected = pressure.day < 3 or (
		state.tutorial != null
		and state.tutorial.has_method("is_active")
		and state.tutorial.is_active()
	)

func _capture_recent_history(pressure, previous, resolved_dive_result) -> void:
	var outcomes: Array[String] = []
	if previous != null:
		outcomes.assign(previous.recent_dive_outcomes)
	var outcome := _dive_outcome(resolved_dive_result)
	if not outcome.is_empty():
		outcomes.append(outcome)
	while outcomes.size() > PressureStateScript.MAX_RECENT_DIVES:
		outcomes.pop_front()
	pressure.recent_dive_outcomes.assign(outcomes)
	pressure.recent_successful_dives = outcomes.count(PressureStateScript.DIVE_SUCCESS)
	pressure.recent_failed_dives = outcomes.count(PressureStateScript.DIVE_FAILURE) + outcomes.count(PressureStateScript.DIVE_DEATH)
	pressure.last_diver_death_day = int(previous.last_diver_death_day) if previous != null else 0
	if outcome == PressureStateScript.DIVE_DEATH:
		pressure.last_diver_death_day = maxi(pressure.day - 1, 1)

func _capture_recovery_state(pressure, state, previous, resolved_dive_result) -> void:
	pressure.recovery_days_remaining = maxi(int(previous.recovery_days_remaining) - 1, 0) if previous != null else 0
	pressure.major_event_cooldown_days_remaining = maxi(int(previous.major_event_cooldown_days_remaining) - 1, 0) if previous != null else 0
	pressure.last_hardship_event_day = int(previous.last_hardship_event_day) if previous != null else 0
	var hardship := _latest_hardship(state, pressure.day)
	if int(hardship.get("day", 0)) > 0:
		pressure.last_hardship_event_day = int(hardship.day)
		if int(hardship.severity) >= 2:
			pressure.recovery_days_remaining = HARDSHIP_RECOVERY_DAYS
			pressure.major_event_cooldown_days_remaining = MAJOR_EVENT_COOLDOWN_DAYS
	if _dive_outcome(resolved_dive_result) == PressureStateScript.DIVE_DEATH:
		pressure.recovery_days_remaining = HARDSHIP_RECOVERY_DAYS
		pressure.major_event_cooldown_days_remaining = MAJOR_EVENT_COOLDOWN_DAYS

func _critical_gates(pressure, resolved_dive_result) -> Array[String]:
	var gates: Array[String] = []
	if pressure.food_days < 0.5:
		gates.append("food_below_half_day")
	if pressure.max_hunger >= 85:
		gates.append("hunger_critical")
	if pressure.hope < 15:
		gates.append("hope_critical")
	if pressure.platform_integrity < 25:
		gates.append("integrity_critical")
	if pressure.healthy_workers <= 1:
		gates.append("workforce_critical")
	if _dive_outcome(resolved_dive_result) == PressureStateScript.DIVE_DEATH:
		gates.append("diver_died_yesterday")
	return gates

func _calculate_strain(pressure) -> float:
	var result := 0.0
	result += (1.0 - clampf(pressure.food_days / 3.0, 0.0, 1.0)) * 0.22
	result += clampf(pressure.average_hunger / 100.0, 0.0, 1.0) * 0.12
	result += clampf(float(pressure.max_hunger) / 100.0, 0.0, 1.0) * 0.08
	result += clampf((55.0 - float(pressure.hope)) / 55.0, 0.0, 1.0) * 0.16
	var worker_ratio := float(pressure.healthy_workers) / float(maxi(pressure.population, 1))
	result += (1.0 - clampf(worker_ratio, 0.0, 1.0)) * 0.14
	result += clampf((70.0 - float(pressure.platform_integrity)) / 70.0, 0.0, 1.0) * 0.14
	result += (1.0 - clampf(float(pressure.basic_materials) / 25.0, 0.0, 1.0)) * 0.06
	result += (1.0 - clampf(float(pressure.medicines) / 4.0, 0.0, 1.0)) * 0.03
	result += clampf(float(pressure.contagious_disease_cases) / float(maxi(pressure.population, 1)), 0.0, 1.0) * 0.08
	if pressure.free_shelter < 0:
		result += clampf(float(-pressure.free_shelter) / float(maxi(pressure.population, 1)), 0.0, 1.0) * 0.07
	for outcome in pressure.recent_dive_outcomes:
		match outcome:
			PressureStateScript.DIVE_SUCCESS:
				result -= 0.03
			PressureStateScript.DIVE_FAILURE:
				result += 0.06
			PressureStateScript.DIVE_DEATH:
				result += 0.14
	if pressure.storm_today:
		result += 0.10
	elif pressure.weather_condition == WeatherStateScript.Condition.ROUGH:
		result += 0.04
	result += clampf(float(pressure.story_act - 1) / 3.0, 0.0, 1.0) * 0.03
	if pressure.crisis_active:
		result += 0.20
	return clampf(result, 0.0, 1.0)

func _select_band(raw_strain: float, gates: Array[String], crisis_active: bool, previous) -> int:
	if not gates.is_empty() or crisis_active:
		return PressureStateScript.Band.CRISIS
	if previous != null:
		match int(previous.band):
			PressureStateScript.Band.LOW:
				if raw_strain <= EXIT_LOW_STRAIN:
					return PressureStateScript.Band.LOW
			PressureStateScript.Band.HIGH, PressureStateScript.Band.CRISIS:
				if raw_strain >= EXIT_HIGH_STRAIN:
					return PressureStateScript.Band.HIGH
	if raw_strain <= ENTER_LOW_STRAIN:
		return PressureStateScript.Band.LOW
	if raw_strain >= ENTER_HIGH_STRAIN:
		return PressureStateScript.Band.HIGH
	return PressureStateScript.Band.NORMAL

func _consecutive_high_days(current_band: int, previous) -> int:
	if current_band not in [PressureStateScript.Band.HIGH, PressureStateScript.Band.CRISIS]:
		return 0
	return maxi(int(previous.consecutive_high_days), 0) + 1 if previous != null else 1

func _apply_daily_limits(pressure) -> void:
	pressure.pressure_budget = clampf((1.0 - pressure.strain) * 3.0, 0.0, 3.0)
	match pressure.band:
		PressureStateScript.Band.LOW:
			pressure.max_event_severity = 3
		PressureStateScript.Band.NORMAL:
			pressure.pressure_budget = minf(pressure.pressure_budget, 2.0)
			pressure.max_event_severity = 2
		PressureStateScript.Band.HIGH:
			pressure.pressure_budget = minf(pressure.pressure_budget, 0.75)
			pressure.max_event_severity = 1
		PressureStateScript.Band.CRISIS:
			pressure.pressure_budget = 0.0
			# Severity-one relief/opportunity cards with zero pressure cost may
			# still appear; hardship is rejected separately by prefer_relief.
			pressure.max_event_severity = 1
	pressure.prefer_relief = pressure.band in [PressureStateScript.Band.HIGH, PressureStateScript.Band.CRISIS]
	if pressure.storm_today:
		pressure.pressure_budget = minf(pressure.pressure_budget, 0.5)
		pressure.max_event_severity = mini(pressure.max_event_severity, 1)
	if pressure.is_recovery_day():
		pressure.pressure_budget = 0.0
		pressure.max_event_severity = mini(pressure.max_event_severity, 1)
		pressure.prefer_relief = true
	elif pressure.recovery_needed:
		pressure.pressure_budget = minf(pressure.pressure_budget, 0.25)
		pressure.max_event_severity = mini(pressure.max_event_severity, 1)
		pressure.prefer_relief = true
	if pressure.tutorial_protected:
		pressure.pressure_budget = 0.0
		pressure.max_event_severity = 0
	if pressure.disease_outbreak_active:
		pressure.max_event_severity = mini(pressure.max_event_severity, 1)
		pressure.prefer_relief = true

func _reason_codes(pressure) -> Array[String]:
	var reasons: Array[String] = []
	for gate in pressure.critical_gates:
		reasons.append(gate)
	if pressure.tutorial_protected:
		reasons.append("tutorial_protection")
	if pressure.food_days < 1.5 and not reasons.has("food_below_half_day"):
		reasons.append("food_low")
	if pressure.average_hunger >= 50.0 and not reasons.has("hunger_critical"):
		reasons.append("hunger_high")
	if pressure.hope < 35 and not reasons.has("hope_critical"):
		reasons.append("hope_low")
	if pressure.platform_integrity < 45 and not reasons.has("integrity_critical"):
		reasons.append("integrity_low")
	if pressure.healthy_workers < pressure.population and not reasons.has("workforce_critical"):
		reasons.append("workers_impaired")
	if pressure.free_shelter < 0:
		reasons.append("shelter_overcrowded")
	if pressure.medicines == 0:
		reasons.append("medicine_empty")
	if pressure.recent_dive_outcomes.has(PressureStateScript.DIVE_FAILURE):
		reasons.append("recent_dive_failure")
	if pressure.recent_dive_outcomes.has(PressureStateScript.DIVE_DEATH):
		reasons.append("recent_diver_death")
	if pressure.is_recovery_day():
		reasons.append("recovery_day")
	if pressure.recovery_needed:
		reasons.append("sustained_high_pressure")
	if pressure.major_event_cooldown_days_remaining > 0:
		reasons.append("major_event_cooldown")
	if pressure.storm_today:
		reasons.append("storm_today")
	if pressure.active_disease_cases > 0:
		reasons.append("disease_cases_active")
	if pressure.disease_outbreak_active:
		reasons.append("disease_outbreak")
	if pressure.strain < 0.25:
		reasons.append("stable_reserves")
	return reasons


func _blocked_impact_tags(pressure) -> Array[String]:
	var tags: Array[String] = []
	# Nie oferujemy wyborów, których sam kontrakt zakłada dalsze zużycie
	# krytycznie brakującego jedzenia albo ryzyko integralności. Pozostałe
	# bramki są preferencją pomocy, nie twardą cenzurą kart.
	if pressure.food_days < 0.5 or pressure.max_hunger >= 85:
		tags.assign(["food_cost", "food_demand"])
	if pressure.platform_integrity < 25:
		tags.append("integrity_risk")
	return tags


func _preferred_impact_tags(pressure) -> Array[String]:
	var tags: Array[String] = []
	if pressure.food_days < 1.5 or pressure.average_hunger >= 50.0:
		tags.append("food_relief")
	if pressure.basic_materials < 20:
		tags.append("material_relief")
	if pressure.healthy_workers <= 2:
		tags.append("workforce_relief")
		tags.append("population_gain")
	if pressure.hope < 35:
		tags.append("hope_relief")
	if pressure.platform_integrity < 45:
		tags.append("integrity_relief")
	if pressure.medicines == 0 or pressure.disease_outbreak_active:
		tags.append("medicine_relief")
	return tags

func _active_pressure_tags(pressure) -> Array[String]:
	var tags: Array[String] = []
	if pressure.critical_gates.has("food_below_half_day") or pressure.critical_gates.has("hunger_critical"):
		tags.append("food_critical")
	if pressure.critical_gates.has("hope_critical"):
		tags.append("hope_critical")
	if pressure.critical_gates.has("integrity_critical"):
		tags.append("integrity_critical")
	if pressure.critical_gates.has("workforce_critical"):
		tags.append("workforce_critical")
	if pressure.free_shelter <= 0:
		tags.append("no_shelter")
	if pressure.critical_gates.has("diver_died_yesterday") or pressure.recent_dive_outcomes.has(PressureStateScript.DIVE_DEATH):
		tags.append("recent_death")
	if pressure.storm_today:
		tags.append("storm_today")
	if pressure.disease_outbreak_active:
		tags.append("disease_outbreak")
	return tags

func _recovery_roles(pressure) -> Array[String]:
	var roles: Array[String] = []
	for raw_tag in pressure.preferred_impact_tags:
		var role := ""
		match str(raw_tag):
			"food_relief":
				role = "food"
			"material_relief":
				role = "materials"
			"workforce_relief", "population_gain":
				role = "workforce"
			"hope_relief":
				role = "hope"
			"integrity_relief":
				role = "integrity"
			"medicine_relief":
				role = "medicine"
		if not role.is_empty() and not roles.has(role):
			roles.append(role)
	if pressure.active_pressure_tags.has("recent_death") and not roles.has("medicine"):
		roles.append("medicine")
	return roles

func _latest_hardship(state, target_day: int) -> Dictionary:
	var latest := {"day": 0, "severity": 0}
	if not "settlement_event_history" in state:
		return latest
	for event_state in state.settlement_event_history:
		if event_state == null:
			continue
		var resolved_day := int(event_state.resolved_day)
		if resolved_day != target_day - 1:
			continue
		var score := 0.0
		for raw_resource_id in event_state.applied_resource_deltas.keys():
			var resource_id := str(raw_resource_id)
			var delta := int(event_state.applied_resource_deltas[raw_resource_id])
			if delta >= 0:
				continue
			var magnitude := float(-delta)
			if resource_id in [ResourceIdsScript.HOPE, ResourceIdsScript.PLATFORM_INTEGRITY]:
				score += magnitude
			else:
				score += magnitude * 0.75
		var severity := 3 if score >= 18.0 else 2 if score >= 8.0 else 1 if score > 0.0 else 0
		if severity > int(latest.severity):
			latest = {"day": resolved_day, "severity": severity}
	return latest

func _dive_outcome(result) -> String:
	if result == null:
		return ""
	if bool(result.diver_dead):
		return PressureStateScript.DIVE_DEATH
	if not bool(result.returned_alive) or bool(result.emergency_extraction):
		return PressureStateScript.DIVE_FAILURE
	return PressureStateScript.DIVE_SUCCESS

func _resource_amount(state, resource_id: String) -> int:
	return maxi(int(state.resources.get_amount(resource_id)), 0) if state.resources != null else 0

func _shelter_capacity(state) -> int:
	var community_house = state.find_building_by_definition("community_house") if state.has_method("find_building_by_definition") else null
	if community_house == null or not community_house.is_active():
		return 3
	var definition = ResourceLoader.load("res://base_workbench/data/buildings/community_house.tres")
	var level_definition = definition.get_level_definition(int(community_house.level)) if definition != null else null
	return maxi(int(level_definition.capabilities.get("shelter_capacity", 3)), 3) if level_definition != null else 3

func _is_previous_day(previous, target_day: int) -> bool:
	return previous != null and "day" in previous and int(previous.day) == target_day - 1
