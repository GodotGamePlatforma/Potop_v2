class_name DiseaseCampaignState
extends Resource

const DiseaseExposureStateScript := preload("res://scripts/data/DiseaseExposureState.gd")

@export var outbreak_active: bool = false
@export var outbreak_id: String = ""
@export_range(0, 1000000, 1) var outbreak_started_day: int = 0
@export_range(0, 1000000, 1) var outbreak_episode: int = 0
@export_range(0, 1000000, 1) var last_contained_day: int = 0
@export_range(0, 1000000, 1) var peak_cases: int = 0
@export_range(0, 1000000, 1) var last_resolved_day: int = 0
@export var pending_exposures: Array[Resource] = []


func validation_errors() -> PackedStringArray:
	var errors: Array[String] = []
	for field in [
		{"name": "outbreak_started_day", "value": outbreak_started_day},
		{"name": "outbreak_episode", "value": outbreak_episode},
		{"name": "last_contained_day", "value": last_contained_day},
		{"name": "peak_cases", "value": peak_cases},
		{"name": "last_resolved_day", "value": last_resolved_day},
	]:
		if int(field.value) < 0:
			errors.append("%s nie może być ujemne." % field.name)
	var has_outbreak_history := not outbreak_id.is_empty() or outbreak_started_day > 0 or outbreak_episode > 0 or peak_cases > 0
	if outbreak_active and (outbreak_id.is_empty() or outbreak_started_day < 1 or outbreak_episode < 1 or peak_cases < 1):
		errors.append("Aktywna epidemia nie ma pełnej tożsamości, początku, numeru epizodu lub szczytu.")
	elif not outbreak_active and has_outbreak_history and (outbreak_id.is_empty() or outbreak_started_day < 1 or outbreak_episode < 1 or peak_cases < 1):
		errors.append("Historia epidemii nie ma pełnej tożsamości, początku, numeru epizodu lub szczytu.")
	if has_outbreak_history:
		var expected_outbreak_id := "outbreak:%d:%d" % [outbreak_started_day, outbreak_episode]
		if outbreak_id != expected_outbreak_id:
			errors.append("Tożsamość epizodu epidemii nie odpowiada dniowi początku i numerowi epizodu.")
	if outbreak_active and last_contained_day > 0 and last_contained_day >= outbreak_started_day:
		errors.append("Poprzedni dzień opanowania musi poprzedzać początek aktywnego epizodu.")
	elif not outbreak_active and has_outbreak_history and last_contained_day < outbreak_started_day:
		errors.append("Dzień opanowania zakończonego epizodu nie może poprzedzać jego początku.")
	for index in range(pending_exposures.size()):
		var exposure = pending_exposures[index]
		if exposure == null or not (exposure is Resource) or exposure.get_script() != DiseaseExposureStateScript:
			errors.append("Oczekujące narażenie %d ma niepoprawny typ." % index)
			continue
		for exposure_error in exposure.validation_errors():
			errors.append("Oczekujące narażenie %d: %s" % [index, exposure_error])
	return PackedStringArray(errors)


func is_valid() -> bool:
	return validation_errors().is_empty()
