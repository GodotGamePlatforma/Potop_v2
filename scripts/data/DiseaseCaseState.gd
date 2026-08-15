class_name DiseaseCaseState
extends Resource

const DiseaseDefinitionScript := preload("res://scripts/definitions/DiseaseDefinition.gd")

enum Phase {
	EXPOSED,
	SYMPTOMATIC,
	SEVERE,
	RECOVERING,
	IMMUNE,
}

const PHASE_IDS: Array[String] = [
	DiseaseDefinitionScript.PHASE_EXPOSED,
	DiseaseDefinitionScript.PHASE_SYMPTOMATIC,
	DiseaseDefinitionScript.PHASE_SEVERE,
	DiseaseDefinitionScript.PHASE_RECOVERING,
	DiseaseDefinitionScript.PHASE_IMMUNE,
]

@export var disease_id: String = ""
@export_range(1, 999, 1) var definition_version: int = 1
@export var definition_signature: String = ""
@export var definition_snapshot: Resource
@export_enum("Exposed", "Symptomatic", "Severe", "Recovering", "Immune") var phase: int = Phase.EXPOSED
@export_range(1, 1000000, 1) var acquired_day: int = 1
@export_range(1, 1000000, 1) var phase_started_day: int = 1
@export_range(0, 1000000, 1) var natural_recovery_days: int = 0
@export_range(0, 1000000, 1) var severe_days: int = 0
@export_range(0, 1000000, 1) var immunity_until_day: int = 0
@export_range(0, 100, 1) var exposure_pressure: int = 0
@export var source_kind: String = ""
@export var source_id: String = ""
@export_range(0, 1000000, 1) var last_resolved_day: int = 0


func setup_from_definition(
	definition,
	initial_phase: int,
	day: int,
	pressure: int,
	case_source_kind: String,
	case_source_id: String
) -> bool:
	if definition == null or definition.get_script() != DiseaseDefinitionScript or not definition.validation_errors().is_empty():
		return false
	if initial_phase < Phase.EXPOSED or initial_phase > Phase.IMMUNE or day < 1:
		return false
	var snapshot = definition.create_snapshot()
	if snapshot == null:
		return false
	disease_id = str(snapshot.id)
	definition_version = int(snapshot.definition_version)
	definition_signature = str(snapshot.configuration_signature)
	definition_snapshot = snapshot
	phase = initial_phase
	acquired_day = day
	phase_started_day = day
	natural_recovery_days = 0
	severe_days = 0
	immunity_until_day = day + int(snapshot.immunity_days) if initial_phase == Phase.IMMUNE else 0
	exposure_pressure = maxi(pressure, 0)
	source_kind = case_source_kind
	source_id = case_source_id
	last_resolved_day = 0
	return validation_errors().is_empty()


func phase_id() -> String:
	return PHASE_IDS[phase] if phase >= Phase.EXPOSED and phase <= Phase.IMMUNE else ""


static func phase_from_id(value: String) -> int:
	return PHASE_IDS.find(value)


func current_stage():
	if definition_snapshot == null or definition_snapshot.get_script() != DiseaseDefinitionScript:
		return null
	return definition_snapshot.find_stage(phase_id())


func work_efficiency_multiplier() -> float:
	var stage = current_stage()
	return clampf(float(stage.work_efficiency_multiplier), 0.0, 1.0) if stage != null else 0.0


func can_dive() -> bool:
	var stage = current_stage()
	return stage != null and bool(stage.dive_allowed)


func is_infectious() -> bool:
	var stage = current_stage()
	return stage != null and bool(stage.infectious)


func validation_errors() -> PackedStringArray:
	var errors: Array[String] = []
	if disease_id.strip_edges().is_empty():
		errors.append("Przypadek choroby nie ma disease_id.")
	if definition_version < 1:
		errors.append("Przypadek choroby nie ma dodatniej wersji definicji.")
	if definition_signature.length() != 64:
		errors.append("Przypadek choroby nie ma pełnego podpisu definicji.")
	if definition_snapshot == null or not (definition_snapshot is Resource) or definition_snapshot.get_script() != DiseaseDefinitionScript:
		errors.append("Przypadek choroby nie ma typowanej zamrożonej definicji.")
	else:
		for definition_error in definition_snapshot.validation_errors():
			errors.append("Zamrożona definicja: %s" % definition_error)
		if str(definition_snapshot.id) != disease_id:
			errors.append("disease_id przypadku nie odpowiada zamrożonej definicji.")
		if int(definition_snapshot.definition_version) != definition_version:
			errors.append("Wersja przypadku nie odpowiada zamrożonej definicji.")
		if str(definition_snapshot.configuration_signature) != definition_signature:
			errors.append("Podpis przypadku nie odpowiada zamrożonej definicji.")
	if phase < Phase.EXPOSED or phase > Phase.IMMUNE or phase_id().is_empty():
		errors.append("Przypadek choroby ma nieznany etap.")
	elif definition_snapshot != null and definition_snapshot.get_script() == DiseaseDefinitionScript and current_stage() == null:
		errors.append("Zamrożona definicja nie zawiera bieżącego etapu przypadku.")
	if acquired_day < 1 or phase_started_day < acquired_day:
		errors.append("Daty nabycia i początku etapu przypadku są niespójne.")
	if natural_recovery_days < 0 or severe_days < 0:
		errors.append("Liczniki zdrowienia i stanu ciężkiego nie mogą być ujemne.")
	if phase == Phase.IMMUNE:
		if immunity_until_day < phase_started_day:
			errors.append("Odporność nie ma poprawnego dnia końca.")
	elif immunity_until_day != 0:
		errors.append("Przypadek poza odpornością nie może mieć immunity_until_day.")
	if exposure_pressure < 0 or exposure_pressure > 100:
		errors.append("Presja przypadku musi mieścić się w zakresie 0..100.")
	if source_kind.strip_edges().is_empty() or source_id.strip_edges().is_empty():
		errors.append("Przypadek choroby nie ma pełnej tożsamości źródła.")
	if last_resolved_day < 0 or (last_resolved_day > 0 and last_resolved_day < acquired_day):
		errors.append("Ostatni rozliczony dzień przypadku jest niespójny.")
	return PackedStringArray(errors)


func is_valid() -> bool:
	return validation_errors().is_empty()
