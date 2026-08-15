class_name DiseaseDefinition
extends Resource

const DifficultyMathScript := preload("res://scripts/core/DifficultyMath.gd")
const DiseaseStageDefinitionScript := preload("res://scripts/definitions/DiseaseStageDefinition.gd")

const PHASE_EXPOSED := "exposed"
const PHASE_SYMPTOMATIC := "symptomatic"
const PHASE_SEVERE := "severe"
const PHASE_RECOVERING := "recovering"
const PHASE_IMMUNE := "immune"
const PHASE_IDS: Array[String] = [
	PHASE_EXPOSED,
	PHASE_SYMPTOMATIC,
	PHASE_SEVERE,
	PHASE_RECOVERING,
	PHASE_IMMUNE,
]
const EXPECTED_NEXT_PHASE := {
	PHASE_EXPOSED: PHASE_SYMPTOMATIC,
	PHASE_SYMPTOMATIC: PHASE_SEVERE,
	PHASE_SEVERE: PHASE_RECOVERING,
	PHASE_RECOVERING: PHASE_IMMUNE,
	PHASE_IMMUNE: "",
}
const RATION_FULL := "full"
const RATION_HALF := "half"
const RATION_NONE := "none"
const RATION_IDS: Array[String] = [RATION_FULL, RATION_HALF, RATION_NONE]

@export_group("Identity")
@export var id: String = ""
@export var display_name: String = ""
@export_range(1, 999, 1) var definition_version: int = 1
@export var configuration_signature: String = ""

@export_group("Exposure pressure")
@export_range(1, 100, 1) var infection_threshold: int = 4
@export var authored_source_pressures: Dictionary = {}
@export var ration_pressure_modifiers: Dictionary = {
	RATION_FULL: -1,
	RATION_HALF: 0,
	RATION_NONE: 1,
}
@export_range(0, 100, 1) var adverse_conditions_pressure_cap: int = 1
@export_range(0, 100, 1) var emergency_isolation_contact_pressure: int = 1

@export_group("Course and care")
@export_range(1, 100, 1) var natural_recovery_days: int = 2
@export_range(1, 100, 1) var recovering_days: int = 1
@export_range(1, 100, 1) var immunity_days: int = 3
@export_range(0, 100, 1) var treatment_medicine_cost: int = 1
@export_range(0, 100, 1) var prophylaxis_medicine_cost: int = 1
@export var stages: Array[Resource] = []


func find_stage(wanted_phase_id: String):
	for stage in stages:
		if stage != null and stage.get_script() == DiseaseStageDefinitionScript and str(stage.phase_id) == wanted_phase_id:
			return stage
	return null


func create_snapshot():
	if not validation_errors().is_empty():
		return null
	var snapshot = duplicate(true)
	if snapshot == null or snapshot.get_script() != get_script():
		return null
	snapshot.resource_local_to_scene = true
	snapshot.resource_name = "%s [%s v%d]" % [display_name, id, definition_version]
	return snapshot


func compute_configuration_signature() -> String:
	var payload: Array[String] = [
		"id=" + id,
		"display_name=" + display_name,
		"definition_version=" + str(definition_version),
		"infection_threshold=" + str(infection_threshold),
		"adverse_conditions_pressure_cap=" + str(adverse_conditions_pressure_cap),
		"emergency_isolation_contact_pressure=" + str(emergency_isolation_contact_pressure),
		"natural_recovery_days=" + str(natural_recovery_days),
		"recovering_days=" + str(recovering_days),
		"immunity_days=" + str(immunity_days),
		"treatment_medicine_cost=" + str(treatment_medicine_cost),
		"prophylaxis_medicine_cost=" + str(prophylaxis_medicine_cost),
	]
	_append_canonical_int_dictionary(payload, "authored_source_pressures", authored_source_pressures)
	_append_canonical_int_dictionary(payload, "ration_pressure_modifiers", ration_pressure_modifiers)
	for index in range(stages.size()):
		var stage = stages[index]
		if stage == null or stage.get_script() != DiseaseStageDefinitionScript:
			payload.append("stage[%d]=<invalid>" % index)
			continue
		var prefix := "stage[%d]." % index
		payload.append(prefix + "phase_id=" + str(stage.phase_id))
		payload.append(prefix + "display_name=" + str(stage.display_name))
		payload.append(prefix + "next_phase_id=" + str(stage.next_phase_id))
		payload.append(prefix + "work_efficiency_multiplier=" + _canonical_float(float(stage.work_efficiency_multiplier)))
		payload.append(prefix + "dive_allowed=" + str(bool(stage.dive_allowed)))
		payload.append(prefix + "infectious=" + str(bool(stage.infectious)))
		payload.append(prefix + "contact_pressure=" + str(int(stage.contact_pressure)))
		payload.append(prefix + "daily_health_delta=" + str(int(stage.daily_health_delta)))
	return DifficultyMathScript.stable_signature("\n".join(payload))


func has_valid_configuration_signature() -> bool:
	return configuration_signature.length() == 64 and configuration_signature == compute_configuration_signature()


func validation_errors() -> PackedStringArray:
	var errors: Array[String] = []
	if not _is_valid_id(id):
		errors.append("id must use lowercase ASCII letters, digits or underscores and cannot be empty")
	if display_name.strip_edges().is_empty():
		errors.append("display_name cannot be empty")
	if definition_version < 1:
		errors.append("definition_version must be at least 1")
	if infection_threshold < 1 or infection_threshold > 100:
		errors.append("infection_threshold must be between 1 and 100")
	if adverse_conditions_pressure_cap < 0 or adverse_conditions_pressure_cap > 100:
		errors.append("adverse_conditions_pressure_cap must be between 0 and 100")
	if emergency_isolation_contact_pressure < 0 or emergency_isolation_contact_pressure > 100:
		errors.append("emergency_isolation_contact_pressure must be between 0 and 100")
	for field in [
		{"name": "natural_recovery_days", "value": natural_recovery_days},
		{"name": "recovering_days", "value": recovering_days},
		{"name": "immunity_days", "value": immunity_days},
	]:
		if int(field.value) < 1 or int(field.value) > 100:
			errors.append("%s must be between 1 and 100" % field.name)
	for field in [
		{"name": "treatment_medicine_cost", "value": treatment_medicine_cost},
		{"name": "prophylaxis_medicine_cost", "value": prophylaxis_medicine_cost},
	]:
		if int(field.value) < 0 or int(field.value) > 100:
			errors.append("%s must be between 0 and 100" % field.name)
	_validate_int_dictionary(errors, authored_source_pressures, "authored_source_pressures", [], true, 1, 100)
	_validate_int_dictionary(errors, ration_pressure_modifiers, "ration_pressure_modifiers", RATION_IDS, false, -10, 10)
	if ration_pressure_modifiers.size() != RATION_IDS.size():
		errors.append("ration_pressure_modifiers must define exactly full, half and none")

	if stages.size() != PHASE_IDS.size():
		errors.append("stages must contain exactly the five supported phases")
	var seen_phase_ids: Dictionary = {}
	for index in range(stages.size()):
		var stage = stages[index]
		if stage == null or not (stage is Resource) or stage.get_script() != DiseaseStageDefinitionScript:
			errors.append("stage %d is missing or has the wrong type" % index)
			continue
		for stage_error in stage.validation_errors(PHASE_IDS):
			errors.append("stage %d: %s" % [index, stage_error])
		var stage_phase_id := str(stage.phase_id)
		if seen_phase_ids.has(stage_phase_id):
			errors.append("duplicate stage phase_id: " + stage_phase_id)
		else:
			seen_phase_ids[stage_phase_id] = true
		if index < PHASE_IDS.size() and stage_phase_id != PHASE_IDS[index]:
			errors.append("stage %d must be phase %s" % [index, PHASE_IDS[index]])
		if EXPECTED_NEXT_PHASE.has(stage_phase_id) and str(stage.next_phase_id) != str(EXPECTED_NEXT_PHASE[stage_phase_id]):
			errors.append("stage %s has an impossible next phase" % stage_phase_id)
	for phase_id in PHASE_IDS:
		if not seen_phase_ids.has(phase_id):
			errors.append("missing stage: " + phase_id)
	var severe_stage = find_stage(PHASE_SEVERE)
	if severe_stage != null and emergency_isolation_contact_pressure > int(severe_stage.contact_pressure):
		errors.append("emergency_isolation_contact_pressure cannot exceed severe contact pressure")
	if configuration_signature.is_empty():
		errors.append("configuration_signature cannot be empty")
	elif not has_valid_configuration_signature():
		errors.append("configuration_signature does not match the disease values")
	return PackedStringArray(errors)


func is_valid() -> bool:
	return validation_errors().is_empty()


static func _append_canonical_int_dictionary(payload: Array[String], prefix: String, values: Dictionary) -> void:
	var keys: Array[String] = []
	for raw_key in values.keys():
		keys.append(str(raw_key))
	keys.sort()
	for key in keys:
		payload.append("%s[%s]=%d" % [prefix, key, int(values.get(key, 0))])


static func _validate_int_dictionary(
	errors: Array[String],
	values: Dictionary,
	field_name: String,
	allowed_keys: Array[String],
	require_positive_values: bool,
	minimum_value: int,
	maximum_value: int
) -> void:
	if values.is_empty():
		errors.append(field_name + " cannot be empty")
		return
	var normalized_keys: Dictionary = {}
	for raw_key in values.keys():
		var key := str(raw_key).strip_edges()
		if typeof(raw_key) != TYPE_STRING or key.is_empty() or normalized_keys.has(key):
			errors.append(field_name + " contains an empty, duplicate or non-String key")
		else:
			normalized_keys[key] = true
		if not allowed_keys.is_empty() and not allowed_keys.has(key):
			errors.append("%s contains unknown key %s" % [field_name, key])
		if typeof(values[raw_key]) != TYPE_INT:
			errors.append("%s[%s] must be an integer" % [field_name, key])
		elif require_positive_values and int(values[raw_key]) <= 0:
			errors.append("%s[%s] must be positive" % [field_name, key])
		elif int(values[raw_key]) < minimum_value or int(values[raw_key]) > maximum_value:
			errors.append("%s[%s] must be between %d and %d" % [field_name, key, minimum_value, maximum_value])


static func _canonical_float(value: float) -> String:
	return "%.6f" % value


static func _is_valid_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var is_lowercase_letter := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not is_lowercase_letter and not is_digit and code != 95:
			return false
	return true
