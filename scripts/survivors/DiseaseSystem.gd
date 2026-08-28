class_name DiseaseSystem
extends RefCounted

const DiseaseCaseStateScript := preload("res://scripts/data/DiseaseCaseState.gd")
const DiseaseCampaignStateScript := preload("res://scripts/data/DiseaseCampaignState.gd")
const DiseaseExposureStateScript := preload("res://scripts/data/DiseaseExposureState.gd")
const DiseaseDefinitionScript := preload("res://scripts/definitions/DiseaseDefinition.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const WeatherStateScript := preload("res://scripts/data/WeatherState.gd")
const CompetencySystemScript := preload("res://scripts/survivors/CompetencySystem.gd")

const PROJECTION_FORMAT_VERSION := 1

const BLOCKER_NONE := ""
const BLOCKER_INVALID_INPUT := "invalid_input"
const BLOCKER_INVALID_DEFINITION := "invalid_definition"
const BLOCKER_STALE_PROJECTION := "stale_projection"
const BLOCKER_ALREADY_RESOLVED := "already_resolved"
const BLOCKER_ALREADY_APPLIED := "already_applied"

const OUTBREAK_HOPE_LOSS := -6
const OUTBREAK_HOPE_RECOVERY := 4


## Pure end-of-day projection. Incoming exposure, simultaneous transmission and
## all stage changes are built from detached snapshots; the campaign is not
## mutated until apply_day() accepts the complete projection.
func project_day(
	state,
	disease_definitions: Dictionary,
	ration_by_survivor: Dictionary,
	work_events: Array,
	isolated_survivor_ids: Array,
	disease_treatment_commitments: Array,
	context: Dictionary = {}
) -> Dictionary:
	var result := _base_projection(state)
	if (
		state == null
		or state.disease_campaign == null
		or not state.has_method("find_survivor")
		or not state.has_method("get_alive_survivors")
	):
		result.blocker_code = BLOCKER_INVALID_INPUT
		return result
	var current_day := int(state.day)
	if current_day < 1:
		result.blocker_code = BLOCKER_INVALID_INPUT
		return result
	if int(state.disease_campaign.last_resolved_day) >= current_day:
		result.blocker_code = BLOCKER_ALREADY_RESOLVED
		return result

	var survivors_by_id: Dictionary = {}
	var present_ids: Array[String] = []
	var all_ids: Array[String] = []
	var health_after: Dictionary = {}
	var cases_by_survivor: Dictionary = {}
	var cases_before_fingerprints: Dictionary = {}
	for survivor in state.survivors:
		if survivor == null:
			continue
		var survivor_id := str(survivor.id)
		if survivor_id.is_empty() or survivors_by_id.has(survivor_id):
			result.blocker_code = BLOCKER_INVALID_INPUT
			return result
		survivors_by_id[survivor_id] = survivor
		all_ids.append(survivor_id)
		health_after[survivor_id] = int(survivor.health)
		var detached_cases: Array[Resource] = []
		for disease_case in survivor.disease_cases:
			if (
				disease_case == null
				or disease_case.get_script() != DiseaseCaseStateScript
				or not disease_case.is_valid()
			):
				result.blocker_code = BLOCKER_INVALID_INPUT
				return result
			var detached_case = disease_case.duplicate(true)
			if detached_case == null or detached_case.get_script() != DiseaseCaseStateScript:
				result.blocker_code = BLOCKER_INVALID_INPUT
				return result
			detached_cases.append(detached_case)
		_sort_cases(detached_cases)
		cases_by_survivor[survivor_id] = detached_cases
		cases_before_fingerprints[survivor_id] = _case_fingerprints(survivor.disease_cases)
		if survivor.is_present_in_settlement():
			present_ids.append(survivor_id)
	all_ids.sort()
	present_ids.sort()

	var normalized_isolation := _normalized_unique_ids(isolated_survivor_ids)
	var formal_capacity := maxi(int(context.get("formal_isolation_capacity", 0)), 0)
	var isolation := _isolation_assignments_from_ids(
		normalized_isolation,
		present_ids,
		formal_capacity
	)
	result.formal_isolated_survivor_ids = isolation.formal_ids
	result.emergency_isolated_survivor_ids = isolation.emergency_ids
	result.isolated_survivor_ids = normalized_isolation

	var worked_ids := _worked_survivor_ids(work_events)
	var source_snapshot := _infectious_source_snapshot(state, present_ids)
	var report_groups := _empty_report_groups()
	var treatment_result := _apply_treatments(
		cases_by_survivor,
		disease_treatment_commitments,
		current_day,
		survivors_by_id,
		report_groups
	)
	if not bool(treatment_result.get("valid", false)):
		result.blocker_code = BLOCKER_INVALID_INPUT
		result.warnings.assign(treatment_result.get("warnings", []))
		return result
	var treated_case_keys: Dictionary = treatment_result.get("treated_case_keys", {})
	var treated_survivor_ids: Array[String] = []
	treated_survivor_ids.assign(treatment_result.get("treated_survivor_ids", []))
	result.treated_survivor_ids = treated_survivor_ids

	var pending: Array = []
	for exposure in state.disease_campaign.pending_exposures:
		if (
			exposure == null
			or exposure.get_script() != DiseaseExposureStateScript
			or not exposure.is_valid()
		):
			result.blocker_code = BLOCKER_INVALID_INPUT
			return result
		pending.append(exposure.duplicate(true))
	_sort_exposures(pending)
	var incoming_result := _apply_exposures(
		pending,
		cases_by_survivor,
		survivors_by_id,
		present_ids,
		disease_definitions,
		current_day,
		report_groups
	)
	if not bool(incoming_result.get("valid", false)):
		result.blocker_code = str(incoming_result.get("blocker_code", BLOCKER_INVALID_DEFINITION))
		result.warnings.assign(incoming_result.get("warnings", []))
		return result

	var transmission_result := _project_transmission(
		source_snapshot,
		cases_by_survivor,
		survivors_by_id,
		present_ids,
		work_events,
		isolation,
		treated_case_keys,
		treated_survivor_ids,
		current_day,
		maxi(int(context.get("contact_prophylaxis_reduction", 0)), 0),
		maxi(int(context.get("minimum_contact_pressure", 1)), 1)
	)
	for change in transmission_result.get("prophylaxis_changes", []):
		report_groups.contact.append("Profilaktyk ogranicza presję kontaktu %s→%s: %d→%d." % [
			str(change.get("source_survivor_id", "?")),
			str(change.get("target_survivor_id", "?")),
			int(change.get("pressure_before", 0)),
			int(change.get("pressure_after", 0)),
		])
	var contact_exposures: Array = transmission_result.get("exposures", [])
	var contact_apply_result := _apply_exposures(
		contact_exposures,
		cases_by_survivor,
		survivors_by_id,
		present_ids,
		disease_definitions,
		current_day,
		report_groups
	)
	if not bool(contact_apply_result.get("valid", false)):
		result.blocker_code = str(contact_apply_result.get("blocker_code", BLOCKER_INVALID_DEFINITION))
		result.warnings.assign(contact_apply_result.get("warnings", []))
		return result
	result.transmissions.assign(transmission_result.get("transmissions", []))

	var adverse_pressure := maxi(int(context.get("adverse_conditions_pressure", 0)), 0)
	var difficulty_pressure_modifier := clampi(int(context.get("disease_pressure_modifier", 0)), -1, 1)
	_progress_cases(
		cases_by_survivor,
		health_after,
		survivors_by_id,
		present_ids,
		ration_by_survivor,
		normalized_isolation,
		worked_ids,
		current_day,
		adverse_pressure,
		difficulty_pressure_modifier,
		report_groups
	)

	var projected_present_ids: Array[String] = []
	for survivor_id in present_ids:
		if int(health_after.get(survivor_id, 0)) > 0:
			projected_present_ids.append(survivor_id)
	var survivor_results: Array[Dictionary] = []
	for survivor_id in all_ids:
		var survivor = survivors_by_id[survivor_id]
		var cases_after: Array[Resource] = []
		if survivor_id in projected_present_ids:
			for disease_case in cases_by_survivor.get(survivor_id, []):
				disease_case.last_resolved_day = current_day
				cases_after.append(disease_case)
			_sort_cases(cases_after)
		survivor_results.append({
			"survivor_id": survivor_id,
			"health_before": int(survivor.health),
			"health_after": maxi(int(health_after.get(survivor_id, survivor.health)), 0),
			"health_delta": maxi(int(health_after.get(survivor_id, survivor.health)), 0) - int(survivor.health),
			"cases_before_fingerprint": cases_before_fingerprints[survivor_id],
			"disease_cases_after": cases_after,
		})
	result.survivor_results = survivor_results

	var counts_before := _case_counts_from_state(state)
	var counts_after := _case_counts_from_projection(survivor_results, survivors_by_id)
	result.active_case_count_before = int(counts_before.active)
	result.active_case_count_after = int(counts_after.active)
	result.contagious_case_count_before = int(counts_before.contagious)
	result.contagious_case_count_after = int(counts_after.contagious)
	result.outbreak_threshold = outbreak_threshold(projected_present_ids.size())

	var campaign_after := _project_outbreak(
		state.disease_campaign,
		int(counts_after.contagious),
		int(result.outbreak_threshold),
		current_day,
		report_groups
	)
	campaign_after["last_resolved_day"] = current_day
	campaign_after["pending_exposures"] = [] as Array[Resource]
	result.campaign_before_fingerprint = _campaign_fingerprint(state.disease_campaign)
	result.campaign_after = campaign_after
	result.outbreak_active_before = bool(state.disease_campaign.outbreak_active)
	result.outbreak_active_after = bool(campaign_after.outbreak_active)
	result.hope_delta = int(campaign_after.get("hope_delta", 0))
	result.outbreak_episode = int(campaign_after.outbreak_episode)
	result.report_entries = _flatten_report_groups(report_groups, false)
	result.report_warnings = _flatten_report_groups(report_groups, true)
	result.valid = true
	return result


## Applies only a complete projection and never re-runs disease rules.
func apply_day(state, projection: Dictionary) -> Dictionary:
	var result := {
		"applied": false,
		"blocker_code": BLOCKER_NONE,
		"hope_delta": 0,
		"outbreak_active": false,
	}
	if bool(projection.get("_applied", false)):
		result.blocker_code = BLOCKER_ALREADY_APPLIED
		return result
	if (
		state == null
		or state.disease_campaign == null
		or int(projection.get("projection_format_version", 0)) != PROJECTION_FORMAT_VERSION
		or not bool(projection.get("valid", false))
		or int(projection.get("day", 0)) != int(state.day)
	):
		result.blocker_code = BLOCKER_STALE_PROJECTION
		return result
	if _campaign_fingerprint(state.disease_campaign) != str(projection.get("campaign_before_fingerprint", "")):
		result.blocker_code = BLOCKER_STALE_PROJECTION
		return result

	var validated: Array = []
	var seen_ids: Dictionary = {}
	for survivor_result in projection.get("survivor_results", []):
		if not (survivor_result is Dictionary):
			result.blocker_code = BLOCKER_STALE_PROJECTION
			return result
		var survivor_id := str(survivor_result.get("survivor_id", ""))
		var survivor = state.find_survivor(survivor_id)
		var health_before := int(survivor_result.get("health_before", -1))
		var health_after := int(survivor_result.get("health_after", -1))
		var health_delta := int(survivor_result.get("health_delta", 1000000))
		if (
			survivor_id.is_empty()
			or seen_ids.has(survivor_id)
			or survivor == null
			or int(survivor.health) != health_before
			or health_after < 0
			or health_after > int(survivor.get_max_health())
			or health_delta != health_after - health_before
			or _case_fingerprints(survivor.disease_cases) != str(survivor_result.get("cases_before_fingerprint", ""))
		):
			result.blocker_code = BLOCKER_STALE_PROJECTION
			return result
		var detached_cases: Array[Resource] = []
		var seen_disease_ids: Dictionary = {}
		for disease_case in survivor_result.get("disease_cases_after", []):
			if (
				disease_case == null
				or disease_case.get_script() != DiseaseCaseStateScript
				or not disease_case.is_valid()
			):
				result.blocker_code = BLOCKER_STALE_PROJECTION
				return result
			var disease_id := str(disease_case.disease_id)
			if disease_id.is_empty() or seen_disease_ids.has(disease_id):
				result.blocker_code = BLOCKER_STALE_PROJECTION
				return result
			seen_disease_ids[disease_id] = true
			var detached_case = disease_case.duplicate(true)
			if detached_case == null or detached_case.get_script() != DiseaseCaseStateScript:
				result.blocker_code = BLOCKER_STALE_PROJECTION
				return result
			detached_cases.append(detached_case)
		if (health_after <= 0 or not survivor.is_present_in_settlement()) and not detached_cases.is_empty():
			result.blocker_code = BLOCKER_STALE_PROJECTION
			return result
		seen_ids[survivor_id] = true
		validated.append([survivor, survivor_result, detached_cases])
	if validated.size() != state.survivors.size():
		result.blocker_code = BLOCKER_STALE_PROJECTION
		return result

	var campaign_after: Dictionary = projection.get("campaign_after", {})
	var detached_campaign = DiseaseCampaignStateScript.new()
	detached_campaign.outbreak_active = bool(campaign_after.get("outbreak_active", false))
	detached_campaign.outbreak_id = str(campaign_after.get("outbreak_id", ""))
	detached_campaign.outbreak_started_day = int(campaign_after.get("outbreak_started_day", 0))
	detached_campaign.outbreak_episode = int(campaign_after.get("outbreak_episode", 0))
	detached_campaign.last_contained_day = int(campaign_after.get("last_contained_day", 0))
	detached_campaign.peak_cases = int(campaign_after.get("peak_cases", 0))
	detached_campaign.last_resolved_day = int(campaign_after.get("last_resolved_day", state.day))
	if detached_campaign.last_resolved_day != int(state.day):
		result.blocker_code = BLOCKER_STALE_PROJECTION
		return result
	var pending_after: Array[Resource] = []
	for exposure in campaign_after.get("pending_exposures", []):
		if (
			exposure == null
			or exposure.get_script() != DiseaseExposureStateScript
			or not exposure.is_valid()
		):
			result.blocker_code = BLOCKER_STALE_PROJECTION
			return result
		var detached_exposure = exposure.duplicate(true)
		if detached_exposure == null or detached_exposure.get_script() != DiseaseExposureStateScript:
			result.blocker_code = BLOCKER_STALE_PROJECTION
			return result
		pending_after.append(detached_exposure)
	detached_campaign.pending_exposures.assign(pending_after)
	if not detached_campaign.validation_errors().is_empty():
		result.blocker_code = BLOCKER_STALE_PROJECTION
		return result

	for record in validated:
		var survivor = record[0]
		var survivor_result: Dictionary = record[1]
		survivor.health = maxi(int(survivor_result.health_after), 0)
		var cases_after: Array[Resource] = record[2]
		survivor.disease_cases.assign(cases_after)

	state.disease_campaign.outbreak_active = bool(detached_campaign.outbreak_active)
	state.disease_campaign.outbreak_id = str(detached_campaign.outbreak_id)
	state.disease_campaign.outbreak_started_day = int(detached_campaign.outbreak_started_day)
	state.disease_campaign.outbreak_episode = int(detached_campaign.outbreak_episode)
	state.disease_campaign.last_contained_day = int(detached_campaign.last_contained_day)
	state.disease_campaign.peak_cases = int(detached_campaign.peak_cases)
	state.disease_campaign.last_resolved_day = int(detached_campaign.last_resolved_day)
	state.disease_campaign.pending_exposures.assign(detached_campaign.pending_exposures)

	projection["_applied"] = true
	result.applied = true
	result.hope_delta = int(projection.get("hope_delta", 0))
	result.outbreak_active = bool(state.disease_campaign.outbreak_active)
	return result


func case_presentation(disease_case, definition = null) -> Dictionary:
	if disease_case == null or disease_case.get_script() != DiseaseCaseStateScript:
		return {}
	var resolved_definition = disease_case.definition_snapshot
	if resolved_definition == null:
		resolved_definition = definition
	var stage = disease_case.current_stage()
	if stage == null and resolved_definition != null:
		stage = resolved_definition.find_stage(disease_case.phase_id())
	return {
		"disease_id": str(disease_case.disease_id),
		"display_name": str(resolved_definition.display_name) if resolved_definition != null else str(disease_case.disease_id),
		"phase": int(disease_case.phase),
		"phase_code": str(disease_case.phase_id()),
		"phase_id": str(disease_case.phase_id()),
		"phase_label": str(stage.display_name) if stage != null else str(disease_case.phase_id()),
		"infectious": bool(stage.infectious) if stage != null else false,
		"contagious": bool(stage.infectious) if stage != null else false,
		"contact_pressure": int(stage.contact_pressure) if stage != null else 0,
		"exposure_pressure": int(disease_case.exposure_pressure),
		"infection_threshold": int(resolved_definition.infection_threshold) if resolved_definition != null else 0,
		"work_efficiency_multiplier": float(stage.work_efficiency_multiplier) if stage != null else 0.0,
		"work_multiplier": float(stage.work_efficiency_multiplier) if stage != null else 0.0,
		"dive_allowed": bool(stage.dive_allowed) if stage != null else false,
		"daily_health_delta": int(stage.daily_health_delta) if stage != null else 0,
		"natural_recovery_days": int(disease_case.natural_recovery_days),
		"natural_recovery_required": int(resolved_definition.natural_recovery_days) if resolved_definition != null else 0,
		"immunity_until_day": int(disease_case.immunity_until_day),
		"acquired_day": int(disease_case.acquired_day),
		"phase_started_day": int(disease_case.phase_started_day),
		"source_kind": str(disease_case.source_kind),
		"source_id": str(disease_case.source_id),
	}


## Pure, player-facing forecast for one known case. The caller supplies the
## canonical ration projection and MedicalCareSystem projection, so UI never
## reimplements treatment, pressure or stage rules.
func case_plan_projection(
	state,
	survivor_id: String,
	disease_case,
	ration_id: String,
	medical_projection: Dictionary = {},
	context: Dictionary = {}
) -> Dictionary:
	var result := case_presentation(disease_case)
	result.merge({
		"valid": false,
		"survivor_id": survivor_id,
		"day": int(state.day) if state != null else 0,
		"ration_id": ration_id,
		"ration_pressure_modifier": 0,
		"adverse_conditions_pressure": 0,
		"difficulty_pressure_modifier": 0,
		"projected_pressure": int(disease_case.exposure_pressure) if disease_case != null else 0,
		"exposure_resolves_today": false,
		"treatment_planned": false,
		"isolated": false,
		"formally_isolated": false,
		"emergency_isolated": false,
		"worked_today": false,
		"natural_recovery_qualified": false,
		"natural_recovery_days_after": int(disease_case.natural_recovery_days) if disease_case != null else 0,
		"projected_phase": int(disease_case.phase) if disease_case != null else -1,
		"projected_phase_code": str(disease_case.phase_id()) if disease_case != null else "",
		"projected_phase_label": "",
		"projected_case_cleared": false,
		"projected_health_delta": 0,
	})
	if state == null or disease_case == null or disease_case.get_script() != DiseaseCaseStateScript:
		return result
	var definition = disease_case.definition_snapshot
	if definition == null:
		return result
	var present_ids := _present_survivor_ids(state)
	var plan_isolated_ids: Array = []
	if state.current_day_plan != null:
		plan_isolated_ids = state.current_day_plan.isolated_survivor_ids
	var isolation := _isolation_assignments_from_ids(
		plan_isolated_ids,
		present_ids,
		maxi(int(context.get("formal_isolation_capacity", 0)), 0)
	)
	result.isolated = survivor_id in plan_isolated_ids
	result.formally_isolated = survivor_id in isolation.formal_ids
	result.emergency_isolated = survivor_id in isolation.emergency_ids
	var worked_ids: Array = context.get("worked_survivor_ids", [])
	result.worked_today = survivor_id in worked_ids
	var commitment_found := false
	for commitment in medical_projection.get("disease_treatment_commitments", []):
		if (
			str(commitment.get("survivor_id", "")) == survivor_id
			and str(commitment.get("disease_id", "")) == str(disease_case.disease_id)
			and int(commitment.get("phase_before", -1)) == int(disease_case.phase)
		):
			commitment_found = true
			break
	result.treatment_planned = commitment_found
	var projected_phase := int(disease_case.phase)
	var projected_cleared := false
	var projected_health_delta := 0
	var natural_days_after := int(disease_case.natural_recovery_days)
	var projected_survivor = state.find_survivor(survivor_id)
	if commitment_found:
		if projected_phase == DiseaseCaseStateScript.Phase.EXPOSED:
			projected_cleared = true
		else:
			projected_phase = DiseaseCaseStateScript.Phase.RECOVERING
			natural_days_after = 0
	elif projected_phase == DiseaseCaseStateScript.Phase.EXPOSED:
		result.exposure_resolves_today = int(disease_case.acquired_day) < int(state.day)
		var ration_modifier := int(definition.ration_pressure_modifiers.get(ration_id, 0))
		var adverse_modifier := mini(
			maxi(int(context.get("adverse_conditions_pressure", 0)), 0),
			int(definition.adverse_conditions_pressure_cap)
		)
		var difficulty_modifier := clampi(int(context.get("disease_pressure_modifier", 0)), -1, 1)
		result.ration_pressure_modifier = ration_modifier
		result.adverse_conditions_pressure = adverse_modifier
		result.difficulty_pressure_modifier = difficulty_modifier
		if bool(result.exposure_resolves_today):
			result.projected_pressure = clampi(
				int(disease_case.exposure_pressure) + ration_modifier + adverse_modifier + difficulty_modifier - CompetencySystemScript.disease_pressure_reduction(projected_survivor),
				0,
				100
			)
			if int(result.projected_pressure) >= int(definition.infection_threshold):
				projected_phase = DiseaseCaseStateScript.Phase.SYMPTOMATIC
			else:
				projected_cleared = true
	elif projected_phase in [DiseaseCaseStateScript.Phase.SYMPTOMATIC, DiseaseCaseStateScript.Phase.SEVERE]:
		var natural_qualified := bool(result.isolated) and ration_id == DiseaseDefinitionScript.RATION_FULL and not bool(result.worked_today)
		result.natural_recovery_qualified = natural_qualified
		natural_days_after = int(disease_case.natural_recovery_days) + 1 if natural_qualified else 0
		if projected_phase == DiseaseCaseStateScript.Phase.SEVERE and int(disease_case.phase_started_day) < int(state.day):
			var severe_stage = definition.find_stage(DiseaseDefinitionScript.PHASE_SEVERE)
			projected_health_delta = int(severe_stage.daily_health_delta) if severe_stage != null else 0
		if natural_days_after >= int(definition.natural_recovery_days):
			projected_phase = DiseaseCaseStateScript.Phase.RECOVERING
			natural_days_after = 0
		elif projected_phase == DiseaseCaseStateScript.Phase.SYMPTOMATIC and int(disease_case.phase_started_day) < int(state.day):
			projected_phase = DiseaseCaseStateScript.Phase.SEVERE
	elif projected_phase == DiseaseCaseStateScript.Phase.RECOVERING:
		if int(state.day) - int(disease_case.phase_started_day) >= int(definition.recovering_days):
			projected_phase = DiseaseCaseStateScript.Phase.IMMUNE
	elif projected_phase == DiseaseCaseStateScript.Phase.IMMUNE:
		if int(state.day) >= int(disease_case.immunity_until_day):
			projected_cleared = true
	result.natural_recovery_days_after = natural_days_after
	result.projected_phase = projected_phase
	result.projected_case_cleared = projected_cleared
	result.projected_health_delta = projected_health_delta
	if projected_cleared:
		result.projected_phase_code = "cleared"
		result.projected_phase_label = "Brak przypadku"
	else:
		var phase_code := _phase_id_for_value(projected_phase)
		var projected_stage = definition.find_stage(phase_code)
		result.projected_phase_code = phase_code
		result.projected_phase_label = str(projected_stage.display_name) if projected_stage != null else phase_code
	result.valid = true
	return result


func campaign_presentation(state, disease_definitions: Dictionary = {}) -> Dictionary:
	if state == null or state.disease_campaign == null:
		return {}
	var cases: Array[Dictionary] = []
	for survivor in state.survivors:
		if survivor == null or not survivor.is_present_in_settlement():
			continue
		for disease_case in survivor.disease_cases:
			var presentation := case_presentation(
				disease_case,
				disease_definitions.get(str(disease_case.disease_id))
			)
			if presentation.is_empty():
				continue
			presentation["survivor_id"] = str(survivor.id)
			presentation["survivor_name"] = str(survivor.display_name)
			cases.append(presentation)
	cases.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_key := "%s|%s" % [str(left.survivor_id), str(left.disease_id)]
		var right_key := "%s|%s" % [str(right.survivor_id), str(right.disease_id)]
		return left_key < right_key
	)
	var active_survivor_ids: Dictionary = {}
	var contagious_survivor_ids: Dictionary = {}
	for presentation in cases:
		if str(presentation.phase_id) != DiseaseDefinitionScript.PHASE_IMMUNE:
			active_survivor_ids[str(presentation.survivor_id)] = true
		if bool(presentation.contagious):
			contagious_survivor_ids[str(presentation.survivor_id)] = true
	var living_count := _present_survivor_ids(state).size()
	return {
		"has_disease_signal": not cases.is_empty() or not state.disease_campaign.pending_exposures.is_empty() or bool(state.disease_campaign.outbreak_active),
		"active_case_count": active_survivor_ids.size(),
		"contagious_case_count": contagious_survivor_ids.size(),
		"pending_exposure_count": state.disease_campaign.pending_exposures.size(),
		"outbreak_active": bool(state.disease_campaign.outbreak_active),
		"outbreak_id": str(state.disease_campaign.outbreak_id),
		"outbreak_episode": int(state.disease_campaign.outbreak_episode),
		"outbreak_started_day": int(state.disease_campaign.outbreak_started_day),
		"last_contained_day": int(state.disease_campaign.last_contained_day),
		"peak_cases": int(state.disease_campaign.peak_cases),
		"outbreak_threshold": outbreak_threshold(living_count),
		"cases": cases,
	}


func isolation_change_blocker(state, survivor_id: String, desired: bool) -> String:
	if state == null or state.current_day_plan == null:
		return "Brak aktywnego planu dnia."
	if state.has_method("day_plan_edit_blocker"):
		var plan_blocker := str(state.day_plan_edit_blocker())
		if not plan_blocker.is_empty():
			return plan_blocker
	elif bool(state.current_day_plan.locked):
		return "Plan dnia jest już zablokowany."
	var survivor = state.find_survivor(survivor_id) if state.has_method("find_survivor") else null
	if survivor == null or not survivor.is_present_in_settlement():
		return "Mieszkaniec nie jest obecny w Przystani."
	if not desired:
		return "" if state.current_day_plan.isolated_survivor_ids.has(survivor_id) else "Mieszkaniec nie ma zaplanowanej izolacji."
	for disease_case in survivor.disease_cases:
		if disease_case != null and int(disease_case.phase) in [
			DiseaseCaseStateScript.Phase.EXPOSED,
			DiseaseCaseStateScript.Phase.SYMPTOMATIC,
			DiseaseCaseStateScript.Phase.SEVERE,
		]:
			return ""
	return "Mieszkaniec nie ma przypadku wymagającego izolacji."


func set_isolation_intent(state, survivor_id: String, desired: bool) -> bool:
	if not isolation_change_blocker(state, survivor_id, desired).is_empty():
		return false
	if not state.current_day_plan.set_survivor_isolated(survivor_id, desired):
		return false
	# The diver selection is an editable plan decision, not an assignment.  An
	# isolated resident cannot remain its active target, because the persistence
	# validator and expedition preparation both require a free, non-isolated
	# diver.
	if desired and str(state.current_day_plan.selected_diver_id) == survivor_id:
		state.current_day_plan.selected_diver_id = ""
	return true


func isolation_assignments(state, formal_capacity: int) -> Dictionary:
	if state == null or state.current_day_plan == null:
		return {"formal_ids": [] as Array[String], "emergency_ids": [] as Array[String]}
	return _isolation_assignments_from_ids(
		state.current_day_plan.isolated_survivor_ids,
		_present_survivor_ids(state),
		maxi(formal_capacity, 0)
	)


func adverse_conditions_active(state, shelter_capacity: int) -> bool:
	if state == null or state.weather == null or state.resources == null:
		return false
	var adverse_weather := int(state.weather.condition) in [
		WeatherStateScript.Condition.ROUGH,
		WeatherStateScript.Condition.STORM,
	]
	if not adverse_weather:
		return false
	var present_count := _present_survivor_ids(state).size()
	var weak_shelter := present_count > maxi(shelter_capacity, 0)
	var weak_integrity := int(state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY)) < 35
	return weak_shelter or weak_integrity


static func outbreak_threshold(living_count: int) -> int:
	return maxi(2, ceili(float(maxi(living_count, 0)) / 3.0))


func _apply_treatments(
	cases_by_survivor: Dictionary,
	commitments: Array,
	current_day: int,
	survivors_by_id: Dictionary,
	report_groups: Dictionary
) -> Dictionary:
	var normalized: Array[Dictionary] = []
	for raw_commitment in commitments:
		if not (raw_commitment is Dictionary):
			return {"valid": false, "warnings": ["Niepoprawne zobowiązanie terapii choroby."]}
		normalized.append(raw_commitment)
	normalized.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return "%s|%s" % [str(left.get("survivor_id", "")), str(left.get("disease_id", ""))] < "%s|%s" % [str(right.get("survivor_id", "")), str(right.get("disease_id", ""))]
	)
	var treated_case_keys: Dictionary = {}
	var treated_survivor_ids: Array[String] = []
	for commitment in normalized:
		var survivor_id := str(commitment.get("survivor_id", ""))
		var disease_id := str(commitment.get("disease_id", ""))
		var expected_phase := int(commitment.get("phase_before", -1))
		if survivor_id.is_empty() or disease_id.is_empty() or not cases_by_survivor.has(survivor_id):
			return {"valid": false, "warnings": ["Zobowiązanie terapii wskazuje nieznany przypadek."]}
		var cases: Array = cases_by_survivor[survivor_id]
		var case_index := _find_case_index(cases, disease_id)
		if case_index < 0 or int(cases[case_index].phase) != expected_phase:
			return {"valid": false, "warnings": ["Zobowiązanie terapii nie odpowiada bieżącemu etapowi choroby."]}
		var disease_case = cases[case_index]
		var survivor = survivors_by_id.get(survivor_id)
		var survivor_name := str(survivor.display_name) if survivor != null else survivor_id
		var definition = disease_case.definition_snapshot
		var disease_name := str(definition.display_name) if definition != null else disease_id
		if expected_phase == DiseaseCaseStateScript.Phase.EXPOSED:
			cases.remove_at(case_index)
			report_groups.treatment.append("Profilaktyka usuwa narażenie %s u %s." % [disease_name, survivor_name])
		elif expected_phase in [DiseaseCaseStateScript.Phase.SYMPTOMATIC, DiseaseCaseStateScript.Phase.SEVERE]:
			disease_case.phase = DiseaseCaseStateScript.Phase.RECOVERING
			disease_case.phase_started_day = current_day
			disease_case.natural_recovery_days = 0
			disease_case.immunity_until_day = 0
			report_groups.treatment.append("Terapia kieruje %s u %s do rekonwalescencji." % [disease_name, survivor_name])
		else:
			return {"valid": false, "warnings": ["Etap choroby nie kwalifikuje się do terapii."]}
		cases_by_survivor[survivor_id] = cases
		treated_case_keys[_case_key(survivor_id, disease_id)] = true
		if survivor_id not in treated_survivor_ids:
			treated_survivor_ids.append(survivor_id)
	return {
		"valid": true,
		"treated_case_keys": treated_case_keys,
		"treated_survivor_ids": treated_survivor_ids,
	}


func _apply_exposures(
	exposures: Array,
	cases_by_survivor: Dictionary,
	survivors_by_id: Dictionary,
	present_ids: Array[String],
	definitions: Dictionary,
	current_day: int,
	report_groups: Dictionary
) -> Dictionary:
	_sort_exposures(exposures)
	for exposure in exposures:
		var target_id := str(exposure.target_survivor_id)
		if target_id not in present_ids or not survivors_by_id.has(target_id):
			continue
		var target = survivors_by_id.get(target_id)
		var target_name := str(target.display_name) if target != null else target_id
		var disease_id := str(exposure.disease_id)
		var cases: Array = cases_by_survivor.get(target_id, [])
		var case_index := _find_case_index(cases, disease_id)
		if case_index >= 0:
			var existing_case = cases[case_index]
			if int(existing_case.phase) == DiseaseCaseStateScript.Phase.EXPOSED:
				existing_case.exposure_pressure = mini(
					int(existing_case.exposure_pressure) + int(exposure.pressure),
					100
				)
				var repeated_group: Array = report_groups.contact if str(exposure.source_kind) in ["work_contact", "community_contact"] else report_groups.source
				repeated_group.append("%s otrzymuje kolejne narażenie %s (+%d presji) ze źródła %s." % [target_name, disease_id, int(exposure.pressure), str(exposure.source_id)])
			continue
		var definition = definitions.get(disease_id)
		if (
			definition == null
			or definition.get_script() != DiseaseDefinitionScript
			or not definition.validation_errors().is_empty()
		):
			return {
				"valid": false,
				"blocker_code": BLOCKER_INVALID_DEFINITION,
				"warnings": ["Brak poprawnej definicji choroby %s." % disease_id],
			}
		var new_case = DiseaseCaseStateScript.new()
		if not new_case.setup_from_definition(
			definition,
			DiseaseCaseStateScript.Phase.EXPOSED,
			mini(int(exposure.acquired_day), current_day),
			int(exposure.pressure),
			str(exposure.source_kind),
			str(exposure.source_id)
		):
			return {"valid": false, "blocker_code": BLOCKER_INVALID_DEFINITION, "warnings": ["Nie można utworzyć przypadku %s." % disease_id]}
		cases.append(new_case)
		_sort_cases(cases)
		cases_by_survivor[target_id] = cases
		var exposure_group: Array = report_groups.contact if str(exposure.source_kind) in ["work_contact", "community_contact"] else report_groups.source
		var source_name := str(exposure.source_id)
		var source_survivor = survivors_by_id.get(str(exposure.source_survivor_id))
		if source_survivor != null:
			source_name = str(source_survivor.display_name)
		exposure_group.append("%s zostaje narażony na %s (+%d presji) przez %s." % [target_name, str(definition.display_name), int(exposure.pressure), source_name])
	return {"valid": true, "warnings": []}


func _project_transmission(
	sources: Array[Dictionary],
	cases_by_survivor: Dictionary,
	survivors_by_id: Dictionary,
	present_ids: Array[String],
	work_events: Array,
	isolation: Dictionary,
	treated_case_keys: Dictionary,
	treated_survivor_ids: Array[String],
	current_day: int,
	contact_prophylaxis_reduction: int = 0,
	minimum_contact_pressure: int = 1
) -> Dictionary:
	var exposures: Array[Resource] = []
	var transmissions: Array[Dictionary] = []
	var prophylaxis_changes: Array[Dictionary] = []
	var contacted_targets: Dictionary = {}
	var contacted_sources: Dictionary = {}
	var cap := maxi(1, ceili(float(present_ids.size()) / 4.0))
	var formal_ids: Array = isolation.formal_ids
	var emergency_ids: Array = isolation.emergency_ids
	var work_contacts := _work_contact_candidates(work_events)
	for source in sources:
		if exposures.size() >= cap:
			break
		var source_id := str(source.survivor_id)
		var disease_id := str(source.disease_id)
		if contacted_sources.has(source_id) or treated_case_keys.has(_case_key(source_id, disease_id)) or source_id in formal_ids:
			continue
		var definition = source.definition
		var stage = source.stage
		if definition == null or stage == null or not bool(stage.infectious):
			continue

		var source_work_records: Array = work_contacts.get(source_id, [])
		var source_worked := work_contacts.has(source_id) and source_id not in emergency_ids
		var candidates: Array[Dictionary] = []
		if source_worked:
			for record in source_work_records:
				var target_id := str(record.target_id)
				if target_id not in emergency_ids and _contact_target_allowed(target_id, source_id, disease_id, cases_by_survivor, present_ids, formal_ids, treated_survivor_ids, contacted_targets):
					candidates.append(record)
		else:
			for target_id in present_ids:
				if _contact_target_allowed(target_id, source_id, disease_id, cases_by_survivor, present_ids, formal_ids, treated_survivor_ids, contacted_targets):
					candidates.append({"target_id": target_id, "source_id": "settlement:%d" % current_day})
		if candidates.is_empty():
			continue
		candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			var left_key := "%s|%s" % [str(left.target_id), str(left.source_id)]
			var right_key := "%s|%s" % [str(right.target_id), str(right.source_id)]
			return left_key < right_key
		)
		var chosen: Dictionary = candidates[0]
		var pressure := (
			int(definition.emergency_isolation_contact_pressure)
			if source_id in emergency_ids or str(chosen.target_id) in emergency_ids
			else int(stage.contact_pressure)
		)
		if source_worked:
			pressure = maxi(
				pressure - CompetencySystemScript.emitted_disease_pressure_reduction(survivors_by_id.get(source_id)),
				0
			)
		if pressure <= 0:
			continue
		var pressure_before_prophylaxis := pressure
		if contact_prophylaxis_reduction > 0:
			pressure = maxi(
				pressure - contact_prophylaxis_reduction,
				maxi(minimum_contact_pressure, 1)
			)
		if pressure != pressure_before_prophylaxis:
			prophylaxis_changes.append({
				"source_survivor_id": source_id,
				"target_survivor_id": str(chosen.target_id),
				"pressure_before": pressure_before_prophylaxis,
				"pressure_after": pressure,
			})
		var source_kind := "work_contact" if source_worked else "community_contact"
		var exposure = DiseaseExposureStateScript.create(
			disease_id,
			str(chosen.target_id),
			source_kind,
			str(chosen.source_id),
			pressure,
			current_day,
			source_id
		)
		exposures.append(exposure)
		contacted_sources[source_id] = true
		contacted_targets[str(chosen.target_id)] = true
		transmissions.append({
			"disease_id": disease_id,
			"source_survivor_id": source_id,
			"target_survivor_id": str(chosen.target_id),
			"source_kind": source_kind,
			"source_id": str(chosen.source_id),
			"pressure": pressure,
		})
	return {
		"exposures": exposures,
		"transmissions": transmissions,
		"settlement_cap": cap,
		"prophylaxis_changes": prophylaxis_changes,
	}


func _progress_cases(
	cases_by_survivor: Dictionary,
	health_after: Dictionary,
	survivors_by_id: Dictionary,
	present_ids: Array[String],
	ration_by_survivor: Dictionary,
	isolated_ids: Array[String],
	worked_ids: Dictionary,
	current_day: int,
	adverse_pressure: int,
	difficulty_pressure_modifier: int,
	report_groups: Dictionary
) -> void:
	for survivor_id in present_ids:
		var survivor = survivors_by_id.get(survivor_id)
		var survivor_name := str(survivor.display_name) if survivor != null else survivor_id
		var cases: Array = cases_by_survivor.get(survivor_id, [])
		var kept_cases: Array[Resource] = []
		for disease_case in cases:
			var definition = disease_case.definition_snapshot
			if definition == null:
				continue
			var phase_before := int(disease_case.phase)
			var keep_case := true
			match phase_before:
				DiseaseCaseStateScript.Phase.EXPOSED:
					if int(disease_case.acquired_day) < current_day:
						var ration := str(ration_by_survivor.get(survivor_id, DiseaseDefinitionScript.RATION_NONE))
						var ration_modifier := int(definition.ration_pressure_modifiers.get(ration, 0))
						var weather_modifier := mini(adverse_pressure, int(definition.adverse_conditions_pressure_cap))
						var total_pressure := clampi(
							int(disease_case.exposure_pressure) + ration_modifier + weather_modifier + difficulty_pressure_modifier - CompetencySystemScript.disease_pressure_reduction(survivor),
							0,
							100
						)
						report_groups.protection.append("Presja %s u %s: %d bazowo, racja %+d, warunki %+d, trudność %+d = %d/%d." % [str(definition.display_name), survivor_name, int(disease_case.exposure_pressure), ration_modifier, weather_modifier, difficulty_pressure_modifier, total_pressure, int(definition.infection_threshold)])
						if total_pressure >= int(definition.infection_threshold):
							disease_case.exposure_pressure = total_pressure
							disease_case.phase = DiseaseCaseStateScript.Phase.SYMPTOMATIC
							disease_case.phase_started_day = current_day
							report_groups.stage.append("%s ma od teraz Objawy choroby %s." % [survivor_name, str(definition.display_name)])
						else:
							keep_case = false
							report_groups.stage.append("Narażenie %s u %s wygasa bez objawów." % [str(definition.display_name), survivor_name])
				DiseaseCaseStateScript.Phase.SYMPTOMATIC, DiseaseCaseStateScript.Phase.SEVERE:
					var full_ration := str(ration_by_survivor.get(survivor_id, DiseaseDefinitionScript.RATION_NONE)) == DiseaseDefinitionScript.RATION_FULL
					var natural_qualified := survivor_id in isolated_ids and full_ration and not worked_ids.has(survivor_id)
					if natural_qualified:
						disease_case.natural_recovery_days += 1
					else:
						disease_case.natural_recovery_days = 0
					if phase_before == DiseaseCaseStateScript.Phase.SEVERE and int(disease_case.phase_started_day) < current_day:
						var severe_stage = definition.find_stage(DiseaseDefinitionScript.PHASE_SEVERE)
						var health_delta := int(severe_stage.daily_health_delta) if severe_stage != null else 0
						disease_case.severe_days += 1
						health_after[survivor_id] = maxi(int(health_after.get(survivor_id, 0)) + health_delta, 0)
						if health_delta != 0:
							report_groups.health.append("%s traci %d zdrowia przez %s." % [survivor_name, abs(health_delta), str(definition.display_name)])
					if int(disease_case.natural_recovery_days) >= int(definition.natural_recovery_days):
						disease_case.phase = DiseaseCaseStateScript.Phase.RECOVERING
						disease_case.phase_started_day = current_day
						disease_case.natural_recovery_days = 0
						report_groups.stage.append("Izolacja, odpoczynek i pełne racje kierują %s do rekonwalescencji." % survivor_name)
					elif phase_before == DiseaseCaseStateScript.Phase.SYMPTOMATIC and int(disease_case.phase_started_day) < current_day:
						disease_case.phase = DiseaseCaseStateScript.Phase.SEVERE
						disease_case.phase_started_day = current_day
						report_groups.stage.append("Choroba %s u %s przechodzi w Stan ciężki." % [str(definition.display_name), survivor_name])
				DiseaseCaseStateScript.Phase.RECOVERING:
					if current_day - int(disease_case.phase_started_day) >= int(definition.recovering_days):
						disease_case.phase = DiseaseCaseStateScript.Phase.IMMUNE
						disease_case.phase_started_day = current_day
						disease_case.immunity_until_day = current_day + int(definition.immunity_days)
						report_groups.stage.append("%s kończy rekonwalescencję i zyskuje odporność na %s." % [survivor_name, str(definition.display_name)])
				DiseaseCaseStateScript.Phase.IMMUNE:
					if current_day >= int(disease_case.immunity_until_day):
						keep_case = false
						report_groups.stage.append("Odporność %s u %s wygasa." % [str(definition.display_name), survivor_name])
			if keep_case:
				kept_cases.append(disease_case)
		_sort_cases(kept_cases)
		cases_by_survivor[survivor_id] = kept_cases


func _project_outbreak(campaign, contagious_count: int, threshold: int, current_day: int, report_groups: Dictionary) -> Dictionary:
	var result := {
		"outbreak_active": bool(campaign.outbreak_active),
		"outbreak_id": str(campaign.outbreak_id),
		"outbreak_started_day": int(campaign.outbreak_started_day),
		"outbreak_episode": int(campaign.outbreak_episode),
		"last_contained_day": int(campaign.last_contained_day),
		"peak_cases": int(campaign.peak_cases),
		"hope_delta": 0,
	}
	if not bool(campaign.outbreak_active) and contagious_count >= threshold:
		result.outbreak_active = true
		result.outbreak_episode = int(campaign.outbreak_episode) + 1
		result.outbreak_id = "outbreak:%d:%d" % [current_day, int(result.outbreak_episode)]
		result.outbreak_started_day = current_day
		result.last_contained_day = 0
		result.peak_cases = contagious_count
		result.hope_delta = OUTBREAK_HOPE_LOSS
		report_groups.outbreak.append("Rozpoczyna się epidemia (epizod %d): Nadzieja %d." % [int(result.outbreak_episode), OUTBREAK_HOPE_LOSS])
	elif bool(campaign.outbreak_active) and contagious_count <= 0:
		result.outbreak_active = false
		result.last_contained_day = current_day
		result.hope_delta = OUTBREAK_HOPE_RECOVERY
		report_groups.outbreak.append("Epidemia zostaje opanowana (epizod %d): Nadzieja +%d." % [int(result.outbreak_episode), OUTBREAK_HOPE_RECOVERY])
	elif bool(campaign.outbreak_active):
		result.peak_cases = maxi(int(campaign.peak_cases), contagious_count)
	return result


func _infectious_source_snapshot(state, present_ids: Array[String]) -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	for survivor_id in present_ids:
		var survivor = state.find_survivor(survivor_id)
		for disease_case in survivor.disease_cases:
			if disease_case == null or not disease_case.is_infectious():
				continue
			var definition = disease_case.definition_snapshot
			var stage = disease_case.current_stage()
			sources.append({
				"survivor_id": survivor_id,
				"disease_id": str(disease_case.disease_id),
				"phase": int(disease_case.phase),
				"definition": definition,
				"stage": stage,
			})
	sources.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return "%s|%s" % [str(left.survivor_id), str(left.disease_id)] < "%s|%s" % [str(right.survivor_id), str(right.disease_id)]
	)
	return sources


func _contact_target_allowed(
	target_id: String,
	source_id: String,
	disease_id: String,
	cases_by_survivor: Dictionary,
	present_ids: Array[String],
	formal_ids: Array,
	treated_ids: Array[String],
	contacted_targets: Dictionary
) -> bool:
	if (
		target_id == source_id
		or target_id not in present_ids
		or target_id in formal_ids
		or target_id in treated_ids
		or contacted_targets.has(target_id)
	):
		return false
	var cases: Array = cases_by_survivor.get(target_id, [])
	var case_index := _find_case_index(cases, disease_id)
	return case_index < 0 or int(cases[case_index].phase) == DiseaseCaseStateScript.Phase.EXPOSED


func _work_contact_candidates(work_events: Array) -> Dictionary:
	var by_source: Dictionary = {}
	var normalized_events: Array[Dictionary] = []
	for raw_event in work_events:
		if raw_event is Dictionary:
			normalized_events.append(raw_event)
	normalized_events.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return "%s|%s" % [str(left.get("building_id", "")), str(left.get("action_id", ""))] < "%s|%s" % [str(right.get("building_id", "")), str(right.get("action_id", ""))]
	)
	for event in normalized_events:
		var worker_ids := _normalized_unique_ids(event.get("worker_ids", []))
		worker_ids.sort()
		for source_id in worker_ids:
			if not by_source.has(source_id):
				by_source[source_id] = [] as Array[Dictionary]
			var records: Array = by_source[source_id]
			for target_id in worker_ids:
				if target_id == source_id:
					continue
				var duplicate := false
				for existing in records:
					if str(existing.target_id) == target_id:
						duplicate = true
						break
				if not duplicate:
					records.append({"target_id": target_id, "source_id": str(event.get("building_id", "work"))})
			by_source[source_id] = records
	return by_source


func _worked_survivor_ids(work_events: Array) -> Dictionary:
	var result: Dictionary = {}
	for event in work_events:
		if not (event is Dictionary):
			continue
		for survivor_id in event.get("worker_ids", []):
			var normalized_id := str(survivor_id)
			if not normalized_id.is_empty():
				result[normalized_id] = true
	return result


func _isolation_assignments_from_ids(ids: Array, present_ids: Array[String], formal_capacity: int) -> Dictionary:
	var formal_ids: Array[String] = []
	var emergency_ids: Array[String] = []
	for survivor_id in _normalized_unique_ids(ids):
		if survivor_id not in present_ids:
			continue
		if formal_ids.size() < formal_capacity:
			formal_ids.append(survivor_id)
		else:
			emergency_ids.append(survivor_id)
	return {"formal_ids": formal_ids, "emergency_ids": emergency_ids}


func _case_counts_from_state(state) -> Dictionary:
	var active := 0
	var contagious := 0
	for survivor in state.survivors:
		if survivor == null or not survivor.is_present_in_settlement():
			continue
		var has_active := false
		var has_contagious := false
		for disease_case in survivor.disease_cases:
			if disease_case == null:
				continue
			if int(disease_case.phase) != DiseaseCaseStateScript.Phase.IMMUNE:
				has_active = true
			if disease_case.is_infectious():
				has_contagious = true
		if has_active:
			active += 1
		if has_contagious:
			contagious += 1
	return {"active": active, "contagious": contagious}


func _case_counts_from_projection(survivor_results: Array, survivors_by_id: Dictionary) -> Dictionary:
	var active := 0
	var contagious := 0
	for survivor_result in survivor_results:
		var survivor = survivors_by_id.get(str(survivor_result.survivor_id))
		if survivor == null or not survivor.is_present_in_settlement() or int(survivor_result.get("health_after", 0)) <= 0:
			continue
		var has_active := false
		var has_contagious := false
		for disease_case in survivor_result.get("disease_cases_after", []):
			if int(disease_case.phase) != DiseaseCaseStateScript.Phase.IMMUNE:
				has_active = true
			if disease_case.is_infectious():
				has_contagious = true
		if has_active:
			active += 1
		if has_contagious:
			contagious += 1
	return {"active": active, "contagious": contagious}


func _present_survivor_ids(state) -> Array[String]:
	var result: Array[String] = []
	if state == null:
		return result
	for survivor in state.survivors:
		if survivor != null and survivor.is_present_in_settlement():
			result.append(str(survivor.id))
	result.sort()
	return result


func _find_case_index(cases: Array, disease_id: String) -> int:
	for index in range(cases.size()):
		if cases[index] != null and str(cases[index].disease_id) == disease_id:
			return index
	return -1


func _sort_cases(cases: Array) -> void:
	cases.sort_custom(func(left, right) -> bool:
		var left_key := "%s|%09d" % [str(left.disease_id), int(left.acquired_day)]
		var right_key := "%s|%09d" % [str(right.disease_id), int(right.acquired_day)]
		return left_key < right_key
	)


func _sort_exposures(exposures: Array) -> void:
	exposures.sort_custom(func(left, right) -> bool:
		var left_key := "%09d|%s|%s|%s|%s" % [int(left.acquired_day), str(left.target_survivor_id), str(left.disease_id), str(left.source_kind), str(left.source_id)]
		var right_key := "%09d|%s|%s|%s|%s" % [int(right.acquired_day), str(right.target_survivor_id), str(right.disease_id), str(right.source_kind), str(right.source_id)]
		return left_key < right_key
	)


func _case_fingerprints(cases: Array) -> String:
	var values: Array[String] = []
	for disease_case in cases:
		if disease_case == null:
			values.append("<null>")
			continue
		values.append("|".join([
			str(disease_case.disease_id),
			str(disease_case.definition_version),
			str(disease_case.definition_signature),
			str(disease_case.phase),
			str(disease_case.acquired_day),
			str(disease_case.phase_started_day),
			str(disease_case.natural_recovery_days),
			str(disease_case.severe_days),
			str(disease_case.immunity_until_day),
			str(disease_case.exposure_pressure),
			str(disease_case.source_kind),
			str(disease_case.source_id),
			str(disease_case.last_resolved_day),
		]))
	values.sort()
	return "\n".join(values)


func _campaign_fingerprint(campaign) -> String:
	var exposure_values: Array[String] = []
	for exposure in campaign.pending_exposures:
		if exposure == null:
			exposure_values.append("<null>")
		else:
			exposure_values.append("|".join([
				str(exposure.disease_id),
				str(exposure.target_survivor_id),
				str(exposure.source_kind),
				str(exposure.source_id),
				str(exposure.source_survivor_id),
				str(exposure.pressure),
				str(exposure.acquired_day),
			]))
	exposure_values.sort()
	return "#".join([
		str(campaign.outbreak_active),
		str(campaign.outbreak_id),
		str(campaign.outbreak_started_day),
		str(campaign.outbreak_episode),
		str(campaign.last_contained_day),
		str(campaign.peak_cases),
		str(campaign.last_resolved_day),
		";".join(exposure_values),
	])


func _case_key(survivor_id: String, disease_id: String) -> String:
	return survivor_id + "|" + disease_id


func _phase_id_for_value(phase: int) -> String:
	match phase:
		DiseaseCaseStateScript.Phase.EXPOSED:
			return DiseaseDefinitionScript.PHASE_EXPOSED
		DiseaseCaseStateScript.Phase.SYMPTOMATIC:
			return DiseaseDefinitionScript.PHASE_SYMPTOMATIC
		DiseaseCaseStateScript.Phase.SEVERE:
			return DiseaseDefinitionScript.PHASE_SEVERE
		DiseaseCaseStateScript.Phase.RECOVERING:
			return DiseaseDefinitionScript.PHASE_RECOVERING
		DiseaseCaseStateScript.Phase.IMMUNE:
			return DiseaseDefinitionScript.PHASE_IMMUNE
	return ""


func _normalized_unique_ids(values: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_value in values:
		var value := str(raw_value).strip_edges()
		if not value.is_empty() and value not in result:
			result.append(value)
	return result


func _empty_report_groups() -> Dictionary:
	return {
		"source": [] as Array[String],
		"protection": [] as Array[String],
		"contact": [] as Array[String],
		"stage": [] as Array[String],
		"treatment": [] as Array[String],
		"health": [] as Array[String],
		"outbreak": [] as Array[String],
	}


func _flatten_report_groups(groups: Dictionary, warnings_only: bool) -> Array[String]:
	var result: Array[String] = []
	var keys := ["health", "outbreak"] if warnings_only else ["source", "protection", "contact", "stage", "treatment"]
	for key in keys:
		for entry in groups.get(key, []):
			result.append(str(entry))
	return result


func _base_projection(state) -> Dictionary:
	return {
		"projection_format_version": PROJECTION_FORMAT_VERSION,
		"day": int(state.day) if state != null else 0,
		"valid": false,
		"blocker_code": BLOCKER_NONE,
		"survivor_results": [] as Array[Dictionary],
		"transmissions": [] as Array[Dictionary],
		"warnings": [] as Array[String],
		"report_entries": [] as Array[String],
		"report_warnings": [] as Array[String],
		"formal_isolated_survivor_ids": [] as Array[String],
		"emergency_isolated_survivor_ids": [] as Array[String],
		"isolated_survivor_ids": [] as Array[String],
		"treated_survivor_ids": [] as Array[String],
		"active_case_count_before": 0,
		"active_case_count_after": 0,
		"contagious_case_count_before": 0,
		"contagious_case_count_after": 0,
		"outbreak_threshold": 2,
		"outbreak_active_before": false,
		"outbreak_active_after": false,
		"outbreak_episode": 0,
		"hope_delta": 0,
		"campaign_before_fingerprint": "",
		"campaign_after": {},
		"_applied": false,
	}
