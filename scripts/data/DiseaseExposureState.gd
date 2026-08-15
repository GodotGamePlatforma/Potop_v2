class_name DiseaseExposureState
extends Resource

@export var disease_id: String = ""
@export var target_survivor_id: String = ""
@export var source_kind: String = ""
@export var source_id: String = ""
@export var source_survivor_id: String = ""
@export_range(1, 100, 1) var pressure: int = 1
@export_range(1, 1000000, 1) var acquired_day: int = 1


static func create(
	exposure_disease_id: String,
	target_id: String,
	exposure_source_kind: String,
	exposure_source_id: String,
	exposure_pressure: int,
	day: int,
	source_survivor: String = ""
):
	var exposure := DiseaseExposureState.new()
	exposure.disease_id = exposure_disease_id
	exposure.target_survivor_id = target_id
	exposure.source_kind = exposure_source_kind
	exposure.source_id = exposure_source_id
	exposure.source_survivor_id = source_survivor
	exposure.pressure = exposure_pressure
	exposure.acquired_day = day
	return exposure


func detached_copy():
	var result = duplicate(true)
	if result != null:
		result.resource_local_to_scene = true
	return result


func validation_errors() -> PackedStringArray:
	var errors: Array[String] = []
	if disease_id.strip_edges().is_empty():
		errors.append("Narażenie nie ma disease_id.")
	if target_survivor_id.strip_edges().is_empty():
		errors.append("Narażenie nie ma target_survivor_id.")
	if source_kind.strip_edges().is_empty() or source_id.strip_edges().is_empty():
		errors.append("Narażenie nie ma pełnej tożsamości źródła.")
	if pressure <= 0 or pressure > 100:
		errors.append("Presja narażenia musi mieścić się w zakresie 1..100.")
	if acquired_day < 1:
		errors.append("Dzień narażenia musi być dodatni.")
	if not source_survivor_id.is_empty() and source_survivor_id == target_survivor_id:
		errors.append("Osoba źródłowa narażenia nie może być jego celem.")
	return PackedStringArray(errors)


func is_valid() -> bool:
	return validation_errors().is_empty()
