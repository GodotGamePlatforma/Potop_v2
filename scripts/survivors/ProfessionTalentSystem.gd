class_name ProfessionTalentSystem
extends RefCounted

const TALENTS_PATH := "res://data/profession_talents"
const ProfessionTalentDefinitionScript := preload("res://scripts/definitions/ProfessionTalentDefinition.gd")
const PROFESSION_IDS: Array[String] = [
	"rybak", "kucharz", "mechanik", "medyk", "organizator", "nurek",
]
const EXPECTED_PARAMETERS := {
	"rybak_straznik_lowiska": {"pressure_multiplier": 0.7},
	"rybak_polow_forsowny": {"food_bonus": 1, "pressure_multiplier": 1.5},
	"kucharz_porcjowanie_kryzysowe": {"half_ration_morale_delta": -1},
	"kucharz_pokrzepiajacy_posilek": {"morale_bonus": 1, "morale_threshold_exclusive": 40},
	"mechanik_konserwator": {"repair_integrity_bonus": 2},
	"mechanik_odzysk_materialu": {"minimum_reserved_scrap": 2, "scrap_refund": 1, "uses_per_day": 1},
	"medyk_rehabilitant": {"treated_fatigue_delta": -4},
	"medyk_profilaktyk": {"contact_pressure_reduction": 1, "minimum_contact_pressure": 1},
	"organizator_mediator": {"negative_hope_delta_reduction": 1, "uses_per_day": 1},
	"organizator_instruktor": {"practice_bonus": 10, "uses_per_day": 1},
	"nurek_zwiadowca": {"detection_radius": 640.0, "stationary_seconds": 1.5, "strong_current_threshold": 60.0},
	"nurek_technik_glebinowy": {"hold_seconds": 1.8, "noise_multiplier": 0.25, "repair_amount_multiplier": 0.6},
}
const EXPECTED_TALENT_IDS_BY_PROFESSION := {
	"rybak": ["rybak_straznik_lowiska", "rybak_polow_forsowny"],
	"kucharz": ["kucharz_porcjowanie_kryzysowe", "kucharz_pokrzepiajacy_posilek"],
	"mechanik": ["mechanik_konserwator", "mechanik_odzysk_materialu"],
	"medyk": ["medyk_rehabilitant", "medyk_profilaktyk"],
	"organizator": ["organizator_mediator", "organizator_instruktor"],
	"nurek": ["nurek_zwiadowca", "nurek_technik_glebinowy"],
}

var _definitions: Dictionary = {}
var _load_errors: Array[String] = []


func get_definition(talent_id: String):
	_ensure_definitions()
	return _definitions.get(talent_id)


func get_all_talent_ids() -> Array[String]:
	_ensure_definitions()
	var result: Array[String] = []
	for talent_id in _definitions.keys():
		result.append(str(talent_id))
	result.sort()
	return result


func get_talent_ids() -> Array[String]:
	return get_all_talent_ids()


func get_talent_ids_for_profession(profession_id: String) -> Array[String]:
	_ensure_definitions()
	var result: Array[String] = []
	for talent_id in _definitions.keys():
		var definition = _definitions[talent_id]
		if definition != null and str(definition.profession_id) == profession_id:
			result.append(str(talent_id))
	result.sort_custom(func(left: String, right: String) -> bool:
		var left_definition = _definitions[left]
		var right_definition = _definitions[right]
		if int(left_definition.sort_order) == int(right_definition.sort_order):
			return left < right
		return int(left_definition.sort_order) < int(right_definition.sort_order)
	)
	return result


static func selected_talent_id(holder, profession_id: String) -> String:
	if holder == null or profession_id.is_empty():
		return ""
	var selections = holder.get("profession_talent_ids") if holder is Object else holder.get("profession_talent_ids", {})
	if not selections is Dictionary:
		return ""
	return str(selections.get(profession_id, "")).strip_edges()


static func has_talent(holder, talent_id: String) -> bool:
	if holder == null or talent_id.is_empty():
		return false
	var selections = holder.get("profession_talent_ids") if holder is Object else holder.get("profession_talent_ids", {})
	if not selections is Dictionary:
		return false
	return talent_id in selections.values()


func validation_errors() -> Array[String]:
	_ensure_definitions()
	var errors: Array[String] = _load_errors.duplicate()
	var expected_count := 0
	for profession_id in EXPECTED_TALENT_IDS_BY_PROFESSION.keys():
		var expected_ids: Array = EXPECTED_TALENT_IDS_BY_PROFESSION[profession_id]
		expected_count += expected_ids.size()
		var actual_ids := get_talent_ids_for_profession(str(profession_id))
		if actual_ids.size() != 2:
			errors.append("Zawód %s musi mieć dokładnie dwa talenty, ma: %d." % [profession_id, actual_ids.size()])
		for talent_id in expected_ids:
			if not actual_ids.has(str(talent_id)):
				errors.append("Brakuje talentu %s dla zawodu %s." % [talent_id, profession_id])
	if _definitions.size() != expected_count:
		errors.append("Katalog talentów musi zawierać dokładnie %d pozycji, ma: %d." % [expected_count, _definitions.size()])
	for talent_id in _definitions.keys():
		var definition = _definitions[talent_id]
		var expected: Dictionary = EXPECTED_PARAMETERS.get(str(talent_id), {})
		if definition.parameters != expected:
			errors.append("Talent %s ma parametry inne niż zatwierdzony kontrakt." % talent_id)
	return errors


func _ensure_definitions() -> void:
	if not _definitions.is_empty() or not _load_errors.is_empty():
		return
	if not DirAccess.dir_exists_absolute(TALENTS_PATH):
		_load_errors.append("Brak katalogu talentów zawodowych: %s." % TALENTS_PATH)
		return
	for file_name in DirAccess.get_files_at(TALENTS_PATH):
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var resource_path := TALENTS_PATH.path_join(file_name)
		var definition = ResourceLoader.load(resource_path)
		if definition == null:
			_load_errors.append("Nie można wczytać talentu zawodowego: %s." % resource_path)
			continue
		if definition.get_script() != ProfessionTalentDefinitionScript or not definition.is_valid():
			_load_errors.append("Talent zawodowy ma niepełną definicję: %s." % resource_path)
			continue
		var talent_id := str(definition.id)
		if _definitions.has(talent_id):
			_load_errors.append("Powtórzony identyfikator talentu zawodowego: %s." % talent_id)
			continue
		_definitions[talent_id] = definition
