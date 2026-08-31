class_name MedicalCareSystem
extends RefCounted

const InjuryRecoverySystemScript := preload("res://scripts/survivors/InjuryRecoverySystem.gd")
const ProfessionTalentSystemScript := preload("res://scripts/survivors/ProfessionTalentSystem.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const WorkPaceSystemScript := preload("res://base_workbench/systems/WorkPaceSystem.gd")

const PROJECTION_FORMAT_VERSION := 1

const STATUS_APPLIED := "applied"
const STATUS_IDLE := "idle"

const BLOCKER_NONE := ""
const BLOCKER_NO_CAPABLE_WORKERS := "no_capable_workers"
const BLOCKER_INVALID_CAPABILITIES := "invalid_capabilities"
const BLOCKER_NO_PATIENTS := "no_patients"
const BLOCKER_INSUFFICIENT_MEDICINE := "insufficient_medicine"
const BLOCKER_INVALID_PROJECTION := "invalid_projection"
const BLOCKER_STALE_PROJECTION := "stale_projection"
const BLOCKER_ALREADY_APPLIED := "already_applied"

const PHASE_EXPOSED := 0
const PHASE_SYMPTOMATIC := 1
const PHASE_SEVERE := 2
const PHASE_RECOVERING := 3
const PHASE_IMMUNE := 4
const TALENT_REHABILITATOR := "medyk_rehabilitant"

var _injury_recovery_system = InjuryRecoverySystemScript.new()
var _profession_talent_system = ProfessionTalentSystemScript.new()


## Pure projection shared by the Infirmary preview and end-of-day settlement.
## A survivor is represented at most once, so an injury and a disease never
## consume two slots or two medicine doses on the same day.
func project(
	capabilities: Dictionary,
	workforce: Dictionary,
	pace: String,
	recovery_multiplier: float,
	available_medicine: int,
	survivors: Array,
	disease_definitions: Dictionary = {},
	medical_priority_survivor_ids: Array = [],
	workforce_talent_state = null
) -> Dictionary:
	var result := _base_result(workforce)
	var has_rehabilitator := _workforce_has_talent(
		workforce,
		workforce_talent_state,
		TALENT_REHABILITATOR
	)
	var rehabilitator_definition = _profession_talent_system.get_definition(TALENT_REHABILITATOR)
	var rehabilitator_fatigue_delta := int(
		rehabilitator_definition.parameters.get("treated_fatigue_delta", 0)
		if rehabilitator_definition != null
		else 0
	)
	result.merge({
		"projection_format_version": PROJECTION_FORMAT_VERSION,
		"healing_per_patient": int(capabilities.get("healing_per_patient", 0)),
		"effective_healing": 0,
		"medicine_per_patient": int(capabilities.get("medicine_per_patient", 0)),
		"patient_capacity": int(capabilities.get("patient_capacity", 0)),
		"formal_isolation_capacity": int(capabilities.get("formal_isolation_capacity", 0)),
		"patients_requiring_care": 0,
		"treated_count": 0,
		"medicine_spent": 0,
		"medicine_shortage": false,
		"total_health_gain": 0,
		"total_fatigue_reduction": 0,
		"rehabilitator_active": has_rehabilitator,
		"patients": [] as Array[Dictionary],
		"patient_queue": [] as Array[Dictionary],
		"treated_survivor_ids": [] as Array[String],
		"disease_treatment_commitments": [] as Array[Dictionary],
		"medical_priority_survivor_ids": _normalized_unique_ids(medical_priority_survivor_ids),
		"_applied": false,
	})
	var candidates := _patient_snapshots(survivors, disease_definitions)
	_apply_explicit_priority(candidates, result.medical_priority_survivor_ids)
	result.patients_requiring_care = candidates.size()
	result.patient_queue = candidates.duplicate(true)
	if int(result.worker_count) <= 0:
		result.blocker_code = BLOCKER_NO_CAPABLE_WORKERS
		return result
	if not _valid_capabilities(capabilities):
		result.blocker_code = BLOCKER_INVALID_CAPABILITIES
		return result

	var normalized_recovery_multiplier := recovery_multiplier if is_finite(recovery_multiplier) else 0.0
	normalized_recovery_multiplier = maxf(normalized_recovery_multiplier, 0.0)
	var healing_basis := float(result.healing_per_patient) + float(result.specialist_bonus)
	result.effective_healing = maxi(int(round(
		healing_basis
		* WorkPaceSystemScript.output_multiplier(pace)
		* normalized_recovery_multiplier
	)), 0)

	if candidates.is_empty():
		result.blocker_code = BLOCKER_NO_PATIENTS
		return result

	var affordable_count := int(floor(
		float(maxi(available_medicine, 0)) / float(result.medicine_per_patient)
	))
	var treatment_limit := mini(int(result.patient_capacity), affordable_count)
	var treated_count := mini(candidates.size(), treatment_limit)
	result.medicine_shortage = treated_count < mini(candidates.size(), int(result.patient_capacity))
	if treated_count <= 0:
		result.blocker_code = BLOCKER_INSUFFICIENT_MEDICINE
		return result

	var patient_results: Array[Dictionary] = []
	var treated_ids: Array[String] = []
	var disease_commitments: Array[Dictionary] = []
	var total_health_gain := 0
	var total_fatigue_reduction := 0
	for index in range(treated_count):
		var patient: Dictionary = candidates[index]
		var health_before := int(patient.health_before)
		var health_after := mini(health_before + int(result.effective_healing), int(patient.max_health))
		var fatigue_before := int(patient.fatigue_before)
		var fatigue_after := (
			clampi(fatigue_before + rehabilitator_fatigue_delta, 0, 100)
			if has_rehabilitator
			else fatigue_before
		)
		var injury_states: Array[String] = []
		injury_states.assign(patient.injury_states)
		var recovery: Dictionary = _injury_recovery_system.project(
			injury_states,
			health_after,
			int(patient.status_before)
		)
		var injuries_before: Array[String] = []
		injuries_before.assign(recovery.get("before", []))
		var injuries_after: Array[String] = []
		injuries_after.assign(recovery.get("after", []))
		var disease_treatments: Array[Dictionary] = []
		for treatment in patient.get("disease_treatments", []):
			var treatment_copy: Dictionary = treatment.duplicate(true)
			disease_treatments.append(treatment_copy)
			disease_commitments.append({
				"survivor_id": str(patient.survivor_id),
				"disease_id": str(treatment_copy.get("disease_id", "")),
				"phase_before": int(treatment_copy.get("phase_before", -1)),
				"phase_after": int(treatment_copy.get("phase_after", -1)),
				"outcome_code": str(treatment_copy.get("outcome_code", "")),
			})
		var care_reasons: Array[String] = []
		care_reasons.assign(patient.get("care_reasons", []))
		patient_results.append({
			"survivor_id": str(patient.survivor_id),
			"display_name": str(patient.display_name),
			"health_before": health_before,
			"health_after": health_after,
			"health_gain": health_after - health_before,
			"fatigue_before": fatigue_before,
			"fatigue_after": fatigue_after,
			"fatigue_reduction": fatigue_before - fatigue_after,
			"injury_states_before": injuries_before,
			"injury_states_after": injuries_after,
			"status_before": int(recovery.get("status_before", patient.status_before)),
			"status_after": int(recovery.get("status_after", patient.status_before)),
			"care_reasons": care_reasons,
			"disease_treatments": disease_treatments,
			"triage_rank": int(patient.get("triage_rank", 0)),
			"priority_source": str(patient.get("priority_source", "automatic")),
		})
		treated_ids.append(str(patient.survivor_id))
		total_health_gain += health_after - health_before
		total_fatigue_reduction += fatigue_before - fatigue_after

	result.worked = true
	result.status_code = STATUS_APPLIED
	result.treated_count = treated_count
	result.medicine_spent = treated_count * int(result.medicine_per_patient)
	result.total_health_gain = total_health_gain
	result.total_fatigue_reduction = total_fatigue_reduction
	result.patients = patient_results
	result.treated_survivor_ids = treated_ids
	result.disease_treatment_commitments = disease_commitments
	return result


## Applies an already projected result without re-running triage. Validation is
## completed before medicine is spent, so a stale preview cannot partially
## mutate the campaign.
func apply(state, projection: Dictionary) -> Dictionary:
	var result := {
		"applied": false,
		"blocker_code": BLOCKER_NONE,
		"treated_survivor_ids": [] as Array[String],
		"medicine_spent": 0,
	}
	if int(projection.get("projection_format_version", 0)) != PROJECTION_FORMAT_VERSION:
		result.blocker_code = BLOCKER_INVALID_PROJECTION
		return result
	if bool(projection.get("_applied", false)):
		result.blocker_code = BLOCKER_ALREADY_APPLIED
		return result
	if state == null or state.resources == null or not state.has_method("find_survivor"):
		result.blocker_code = BLOCKER_INVALID_PROJECTION
		return result
	if not bool(projection.get("worked", false)):
		projection["_applied"] = true
		result.applied = true
		return result

	var validated_patients: Array = []
	var seen_ids: Dictionary = {}
	var validated_total_fatigue_reduction := 0
	var rehabilitator_definition = _profession_talent_system.get_definition(TALENT_REHABILITATOR)
	var rehabilitator_fatigue_delta := int(
		rehabilitator_definition.parameters.get("treated_fatigue_delta", 0)
		if rehabilitator_definition != null
		else 0
	)
	for patient_result in projection.get("patients", []):
		if not (patient_result is Dictionary):
			result.blocker_code = BLOCKER_INVALID_PROJECTION
			return result
		var survivor_id := str(patient_result.get("survivor_id", ""))
		var survivor = state.find_survivor(survivor_id)
		var expected_fatigue_after := (
			clampi(int(survivor.fatigue) + rehabilitator_fatigue_delta, 0, 100)
			if survivor != null and bool(projection.get("rehabilitator_active", false))
			else int(survivor.fatigue) if survivor != null else -1
		)
		if (
			survivor_id.is_empty()
			or seen_ids.has(survivor_id)
			or survivor == null
			or not survivor.is_present_in_settlement()
			or int(survivor.health) != int(patient_result.get("health_before", -1))
			or int(survivor.fatigue) != int(patient_result.get("fatigue_before", -1))
			or int(survivor.status) != int(patient_result.get("status_before", -1))
			or not _same_string_array(survivor.injury_states, patient_result.get("injury_states_before", []))
			or int(patient_result.get("health_after", -1)) < int(survivor.health)
			or int(patient_result.get("health_after", -1)) > int(survivor.get_max_health())
			or int(patient_result.get("health_gain", -1)) != int(patient_result.get("health_after", -1)) - int(survivor.health)
			or int(patient_result.get("fatigue_after", -1)) < 0
			or int(patient_result.get("fatigue_after", -1)) > int(survivor.fatigue)
			or int(patient_result.get("fatigue_after", -1)) != expected_fatigue_after
			or int(patient_result.get("fatigue_reduction", -1))
				!= int(survivor.fatigue) - int(patient_result.get("fatigue_after", -1))
		):
			result.blocker_code = BLOCKER_STALE_PROJECTION
			return result
		seen_ids[survivor_id] = true
		validated_total_fatigue_reduction += int(patient_result.get("fatigue_reduction", 0))
		validated_patients.append([survivor, patient_result])

	var medicine_spent := int(projection.get("medicine_spent", 0))
	if (
		int(projection.get("treated_count", -1)) != validated_patients.size()
		or int(projection.get("medicine_per_patient", 0)) <= 0
		or medicine_spent < 0
		or medicine_spent != validated_patients.size() * int(projection.get("medicine_per_patient", 0))
		or int(projection.get("total_fatigue_reduction", -1)) != validated_total_fatigue_reduction
	):
		result.blocker_code = BLOCKER_INVALID_PROJECTION
		return result
	if int(state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS)) < medicine_spent:
		result.blocker_code = BLOCKER_STALE_PROJECTION
		return result
	if medicine_spent > 0 and not state.resources.spend(ResourceIdsScript.MEDS_CHEMICALS, medicine_spent):
		result.blocker_code = BLOCKER_STALE_PROJECTION
		return result

	for validated in validated_patients:
		var survivor = validated[0]
		var patient_result: Dictionary = validated[1]
		survivor.health = int(patient_result.health_after)
		survivor.fatigue = int(patient_result.fatigue_after)
		var injury_states_after: Array[String] = []
		injury_states_after.assign(patient_result.get("injury_states_after", []))
		survivor.injury_states.assign(injury_states_after)
		survivor.status = int(patient_result.status_after)

	projection["_applied"] = true
	var treated_ids: Array[String] = []
	treated_ids.assign(projection.get("treated_survivor_ids", []))
	result.applied = true
	result.treated_survivor_ids = treated_ids
	result.medicine_spent = medicine_spent
	return result


func _valid_capabilities(capabilities: Dictionary) -> bool:
	return (
		capabilities.has("healing_per_patient")
		and capabilities.has("medicine_per_patient")
		and capabilities.has("patient_capacity")
		and int(capabilities.healing_per_patient) > 0
		and int(capabilities.medicine_per_patient) > 0
		and int(capabilities.patient_capacity) > 0
	)


func _patient_snapshots(survivors: Array, disease_definitions: Dictionary) -> Array[Dictionary]:
	var patients: Array[Dictionary] = []
	for survivor in survivors:
		if survivor == null or not survivor.is_present_in_settlement():
			continue
		var disease_treatments: Array[Dictionary] = _disease_treatments_for(survivor, disease_definitions)
		var needs_health_or_injury_care: bool = (
			int(survivor.health) < int(survivor.get_max_health())
			or not survivor.injury_states.is_empty()
		)
		if not needs_health_or_injury_care and disease_treatments.is_empty():
			continue
		var injury_states: Array[String] = []
		injury_states.assign(survivor.injury_states)
		var care_reasons: Array[String] = []
		if int(survivor.health) < int(survivor.get_max_health()):
			care_reasons.append("health")
		if not injury_states.is_empty():
			care_reasons.append("injury")
		if not disease_treatments.is_empty():
			care_reasons.append("disease")
		patients.append({
			"survivor_id": str(survivor.id),
			"display_name": str(survivor.display_name),
			"health_before": int(survivor.health),
			"fatigue_before": int(survivor.fatigue),
			"max_health": int(survivor.get_max_health()),
			"injury_states": injury_states,
			"status_before": int(survivor.status),
			"disease_treatments": disease_treatments,
			"care_reasons": care_reasons,
			"triage_rank": _automatic_triage_rank(survivor, disease_treatments),
			"priority_source": "automatic",
		})
	patients.sort_custom(_patient_less)
	return patients


func _disease_treatments_for(survivor, disease_definitions: Dictionary) -> Array[Dictionary]:
	var treatments: Array[Dictionary] = []
	for disease_case in survivor.disease_cases:
		if disease_case == null:
			continue
		var phase := int(disease_case.phase)
		if phase not in [PHASE_EXPOSED, PHASE_SYMPTOMATIC, PHASE_SEVERE]:
			continue
		var disease_id := str(disease_case.disease_id)
		var definition = disease_definitions.get(disease_id, disease_case.definition_snapshot)
		var display_name := disease_id
		if definition != null and not str(definition.display_name).strip_edges().is_empty():
			display_name = str(definition.display_name)
		var phase_after := -1 if phase == PHASE_EXPOSED else PHASE_RECOVERING
		treatments.append({
			"disease_id": disease_id,
			"display_name": display_name,
			"phase_before": phase,
			"phase_after": phase_after,
			"outcome_code": "prophylaxis_clears" if phase == PHASE_EXPOSED else "treatment_to_recovering",
		})
	treatments.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.disease_id) < str(right.disease_id)
	)
	return treatments


func _automatic_triage_rank(survivor, disease_treatments: Array[Dictionary]) -> int:
	var phases: Array[int] = []
	for treatment in disease_treatments:
		phases.append(int(treatment.get("phase_before", -1)))
	if phases.has(PHASE_SEVERE) or survivor.injury_states.has("critical_rescue"):
		return 0
	if int(survivor.health) < int(survivor.get_max_health()) or not survivor.injury_states.is_empty():
		return 1
	if phases.has(PHASE_SYMPTOMATIC):
		return 2
	return 3


func _patient_less(left: Dictionary, right: Dictionary) -> bool:
	var left_rank := int(left.get("triage_rank", 0))
	var right_rank := int(right.get("triage_rank", 0))
	if left_rank != right_rank:
		return left_rank < right_rank
	var left_max := maxi(int(left.get("max_health", 1)), 1)
	var right_max := maxi(int(right.get("max_health", 1)), 1)
	var left_ratio := float(left.get("health_before", 0)) / float(left_max)
	var right_ratio := float(right.get("health_before", 0)) / float(right_max)
	if not is_equal_approx(left_ratio, right_ratio):
		return left_ratio < right_ratio
	return str(left.get("survivor_id", "")) < str(right.get("survivor_id", ""))


func _apply_explicit_priority(candidates: Array[Dictionary], priority_ids: Array) -> void:
	if candidates.is_empty() or priority_ids.is_empty():
		return
	var by_id: Dictionary = {}
	for candidate in candidates:
		by_id[str(candidate.survivor_id)] = candidate
	var ordered: Array[Dictionary] = []
	for survivor_id in priority_ids:
		var normalized_id := str(survivor_id)
		if not by_id.has(normalized_id):
			continue
		var candidate: Dictionary = by_id[normalized_id]
		candidate.priority_source = "explicit"
		ordered.append(candidate)
		by_id.erase(normalized_id)
	for candidate in candidates:
		if by_id.has(str(candidate.survivor_id)):
			ordered.append(candidate)
	candidates.assign(ordered)


func _normalized_unique_ids(values: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_value in values:
		var value := str(raw_value).strip_edges()
		if not value.is_empty() and value not in result:
			result.append(value)
	return result


func _same_string_array(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if str(left[index]) != str(right[index]):
			return false
	return true


func _workforce_has_talent(
	workforce: Dictionary,
	workforce_talent_state,
	talent_id: String
) -> bool:
	var source = workforce.get("talent_ids", []) if workforce_talent_state == null else workforce_talent_state
	if source is Dictionary:
		if source.get("talent_ids", []).has(talent_id) or bool(source.get(talent_id, false)):
			return true
		for selected_talent_id in source.values():
			if str(selected_talent_id) == talent_id:
				return true
		return false
	if source is Array or source is PackedStringArray:
		return source.has(talent_id)
	return false


func _base_result(workforce: Dictionary) -> Dictionary:
	var worker_ids: Array[String] = []
	worker_ids.assign(workforce.get("worker_ids", []))
	return {
		"worked": false,
		"status_code": STATUS_IDLE,
		"blocker_code": BLOCKER_NONE,
		"worker_ids": worker_ids,
		"worker_count": worker_ids.size(),
		"worker_units": maxf(float(workforce.get("worker_units", 0.0)), 0.0),
		"specialist_bonus": float(workforce.get("specialist_bonus", 0.0)),
	}
