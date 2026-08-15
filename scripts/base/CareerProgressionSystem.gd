class_name CareerProgressionSystem
extends RefCounted

const ProfessionTalentSystemScript := preload("res://scripts/base/ProfessionTalentSystem.gd")
const PROFESSIONS_PATH := "res://data/professions"
const COMMUNITY_HOUSE_DEFINITION_ID := "community_house"
const DEVELOPMENT_REQUIRED_COMMUNITY_HOUSE_LEVEL := 1
const REQUIRED_COMMUNITY_HOUSE_LEVEL := 2

const RANK_NOVICE := "novice"
const RANK_APPRENTICE := "apprentice"
const RANK_READY := "ready"
const RANK_SPECIALIST := "specialist"
const RANK_LOCKED := "locked"

var _definitions: Dictionary = {}
var _profession_talent_system = ProfessionTalentSystemScript.new()

func get_profession_definition(profession_id: String):
	_ensure_definitions()
	return _definitions.get(profession_id)

func get_profession_ids() -> Array[String]:
	_ensure_definitions()
	var result: Array[String] = []
	for profession_id in _definitions.keys():
		result.append(str(profession_id))
	result.sort_custom(func(left: String, right: String) -> bool:
		var left_definition = _definitions[left]
		var right_definition = _definitions[right]
		if int(left_definition.sort_order) == int(right_definition.sort_order):
			return left < right
		return int(left_definition.sort_order) < int(right_definition.sort_order)
	)
	return result

func profession_for_building(building_definition_id: String) -> String:
	_ensure_definitions()
	for profession_id in _definitions.keys():
		var definition = _definitions[profession_id]
		if str(definition.building_definition_id) == building_definition_id:
			return str(profession_id)
	return ""

func get_rank_id(survivor, profession_id: String) -> String:
	var definition = get_profession_definition(profession_id)
	if survivor == null or definition == null:
		return RANK_NOVICE
	if _has_profession(survivor, profession_id):
		return RANK_SPECIALIST
	if not str(survivor.secondary_profession).is_empty():
		return RANK_LOCKED
	var experience := _job_experience(survivor, profession_id)
	if experience >= int(definition.promotion_experience):
		return RANK_READY
	if experience >= int(definition.apprentice_experience):
		return RANK_APPRENTICE
	return RANK_NOVICE

func get_rank_display_name(survivor, profession_id: String) -> String:
	match get_rank_id(survivor, profession_id):
		RANK_SPECIALIST:
			return "SPECJALISTA"
		RANK_READY:
			return "GOTOWY DO AWANSU"
		RANK_APPRENTICE:
			return "UCZEŃ"
		RANK_LOCKED:
			return "ŚCIEŻKA ZAMKNIĘTA"
	return "NOWICJUSZ"

static func get_specialist_effectiveness(survivor, profession_id: String) -> float:
	if survivor == null or profession_id.is_empty():
		return 0.0
	return 1.0 if _has_profession(survivor, profession_id) else 0.0

func days_until_promotion(survivor, profession_id: String) -> int:
	var definition = get_profession_definition(profession_id)
	if survivor == null or definition == null or _has_profession(survivor, profession_id) or not str(survivor.secondary_profession).is_empty():
		return 0
	var remaining := maxi(int(definition.promotion_experience) - _job_experience(survivor, profession_id), 0)
	return int(ceil(float(remaining) / float(maxi(int(definition.practice_experience_per_workday), 1))))

func record_work(
	survivor,
	profession_id: String,
	grant_general_experience: bool = true,
	grant_practice_experience: bool = true
) -> Dictionary:
	var definition = get_profession_definition(profession_id)
	if survivor == null or definition == null or not _is_present(survivor):
		return {}

	var previous_level := int(survivor.level)
	var general_experience_gained := 0
	var levels_gained := 0
	if grant_general_experience:
		var requested_experience := int(definition.general_experience_per_workday)
		var previous_experience := int(survivor.experience)
		levels_gained = int(survivor.add_experience(requested_experience))
		if levels_gained > 0 or int(survivor.experience) != previous_experience:
			general_experience_gained = requested_experience

	var previous_practice := _job_experience(survivor, profession_id)
	var practice_gained := 0
	var current_practice := previous_practice
	if grant_practice_experience:
		var promotion_threshold := int(definition.promotion_experience)
		current_practice = mini(previous_practice + int(definition.practice_experience_per_workday), promotion_threshold)
		practice_gained = current_practice - previous_practice
		if practice_gained > 0:
			survivor.set_job_experience(profession_id, current_practice)

	if general_experience_gained <= 0 and practice_gained <= 0:
		return {}
	return {
		"survivor_id": str(survivor.id),
		"survivor_name": str(survivor.display_name),
		"profession_id": profession_id,
		"profession_name": str(definition.display_name),
		"general_experience_gained": general_experience_gained,
		"levels_gained": levels_gained,
		"previous_level": previous_level,
		"current_level": int(survivor.level),
		"practice_gained": practice_gained,
		"previous_practice": previous_practice,
		"current_practice": current_practice,
		"apprentice_experience": int(definition.apprentice_experience),
		"promotion_experience": int(definition.promotion_experience),
		"reached_apprentice": previous_practice < int(definition.apprentice_experience) and current_practice >= int(definition.apprentice_experience),
		"reached_promotion": previous_practice < int(definition.promotion_experience) and current_practice >= int(definition.promotion_experience),
	}

func development_blocker(state, survivor, stat_id: String) -> String:
	if state == null:
		return "Brak aktywnego stanu kampanii."
	if survivor == null:
		return "Nie znaleziono mieszkańca."
	if not _is_present(survivor):
		return "Rozwój dotyczy tylko osób obecnych w Przystani."
	if state.has_method("day_plan_edit_blocker"):
		var plan_blocker := str(state.day_plan_edit_blocker())
		if not plan_blocker.is_empty():
			return plan_blocker
	elif state.has_method("can_edit_day_plan") and not state.can_edit_day_plan():
		return "Plan dnia jest już zablokowany."
	var community_house = state.find_building_by_definition(COMMUNITY_HOUSE_DEFINITION_ID)
	if (
		community_house == null
		or not community_house.is_active()
		or int(community_house.level) < DEVELOPMENT_REQUIRED_COMMUNITY_HOUSE_LEVEL
	):
		return "Wydawanie punktów rozwoju wymaga aktywnego Domu Wspólnoty I."
	if survivor.has_method("skill_point_blocker"):
		return str(survivor.skill_point_blocker(stat_id))
	return "Ta ścieżka rozwoju nie istnieje."

func can_spend_development_point(state, survivor, stat_id: String) -> bool:
	return development_blocker(state, survivor, stat_id).is_empty()

func spend_development_point(state, survivor_id: String, stat_id: String) -> bool:
	if state == null:
		return false
	var survivor = state.find_survivor(survivor_id)
	if not can_spend_development_point(state, survivor, stat_id):
		return false
	return survivor.spend_skill_point(stat_id)


func profession_talent_selection_blocker(state, survivor, talent_id: String) -> String:
	if state == null:
		return "Brak aktywnego stanu kampanii."
	if survivor == null:
		return "Nie znaleziono mieszkańca."
	var talent_definition = _profession_talent_system.get_definition(talent_id)
	if talent_definition == null:
		return "Ten talent zawodowy nie istnieje."
	if not _is_present(survivor):
		return "Talent może wybrać tylko osoba obecna w Przystani."
	var profession_id := str(talent_definition.profession_id)
	if not _has_profession(survivor, profession_id):
		return "Talent wymaga formalnej specjalizacji: %s." % profession_id.capitalize()
	var selected_id := ProfessionTalentSystemScript.selected_talent_id(survivor, profession_id)
	if not selected_id.is_empty():
		if selected_id == talent_id:
			return "Ten trwały talent jest już aktywny."
		return "Talent dla tej specjalizacji został już wybrany i nie można go zmienić."
	if state.has_method("day_plan_edit_blocker"):
		var plan_blocker := str(state.day_plan_edit_blocker())
		if not plan_blocker.is_empty():
			return plan_blocker
	elif state.has_method("can_edit_day_plan") and not state.can_edit_day_plan():
		return "Plan dnia jest już zablokowany."
	var community_house = state.find_building_by_definition(COMMUNITY_HOUSE_DEFINITION_ID)
	if (
		community_house == null
		or not community_house.is_active()
		or int(community_house.level) < REQUIRED_COMMUNITY_HOUSE_LEVEL
	):
		return "Wybór talentu zawodowego wymaga aktywnego Domu Wspólnoty II."
	var profession_definition = get_profession_definition(profession_id)
	if profession_definition == null:
		return "Ta ścieżka zawodowa nie istnieje."
	var required_practice := int(profession_definition.promotion_experience)
	var practice := _job_experience(survivor, profession_id)
	if practice < required_practice:
		return "Brakuje %d praktyki w ścieżce %s." % [required_practice - practice, profession_definition.display_name]
	return ""


func can_select_profession_talent(state, survivor, talent_id: String) -> bool:
	return profession_talent_selection_blocker(state, survivor, talent_id).is_empty()


func select_profession_talent(state, survivor_id: String, talent_id: String) -> bool:
	if state == null:
		return false
	var survivor = state.find_survivor(survivor_id)
	if not can_select_profession_talent(state, survivor, talent_id):
		return false
	var definition = _profession_talent_system.get_definition(talent_id)
	if definition == null:
		return false
	survivor.profession_talent_ids[str(definition.profession_id)] = talent_id
	return true


func has_selectable_profession_talent(state, survivor) -> bool:
	if survivor == null:
		return false
	for profession_id in [str(survivor.profession), str(survivor.secondary_profession)]:
		if profession_id.is_empty():
			continue
		for talent_id in _profession_talent_system.get_talent_ids_for_profession(profession_id):
			if can_select_profession_talent(state, survivor, talent_id):
				return true
	return false

func promotion_blocker(state, survivor, profession_id: String) -> String:
	var definition = get_profession_definition(profession_id)
	if state == null or survivor == null:
		return "Nie znaleziono mieszkańca."
	if definition == null:
		return "Ta ścieżka zawodowa nie istnieje."
	if not _is_present(survivor):
		return "Awans dotyczy tylko osób obecnych w Przystani."
	if not state.can_edit_day_plan():
		return "Plan dnia jest już zatwierdzony."
	if str(survivor.profession) == profession_id:
		return "%s ma już tę specjalizację główną." % survivor.display_name
	if not str(survivor.secondary_profession).is_empty():
		if str(survivor.secondary_profession) == profession_id:
			return "%s ma już tę drugą specjalizację." % survivor.display_name
		return "%s ma już wybraną drugą specjalizację. Ten wybór jest trwały." % survivor.display_name
	var community_house = state.find_building_by_definition(COMMUNITY_HOUSE_DEFINITION_ID)
	if community_house == null or not community_house.is_active():
		return "Awans wymaga aktywnego Domu Wspólnoty."
	if int(community_house.level) < REQUIRED_COMMUNITY_HOUSE_LEVEL:
		return "Formalny awans odblokowuje Sala zgromadzeń — Dom Wspólnoty II."
	var practice := _job_experience(survivor, profession_id)
	if practice < int(definition.promotion_experience):
		return "Brakuje %d praktyki w ścieżce %s." % [int(definition.promotion_experience) - practice, definition.display_name]
	return ""

func can_promote(state, survivor, profession_id: String) -> bool:
	return promotion_blocker(state, survivor, profession_id).is_empty()

func promote_secondary_profession(state, survivor_id: String, profession_id: String) -> bool:
	if state == null:
		return false
	var survivor = state.find_survivor(survivor_id)
	if not can_promote(state, survivor, profession_id):
		return false
	survivor.secondary_profession = profession_id
	return true

func _ensure_definitions() -> void:
	if not _definitions.is_empty():
		return
	for file_name in DirAccess.get_files_at(PROFESSIONS_PATH):
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var definition = ResourceLoader.load(PROFESSIONS_PATH.path_join(file_name))
		if definition == null or str(definition.id).is_empty():
			continue
		_definitions[str(definition.id)] = definition

static func _has_profession(survivor, profession_id: String) -> bool:
	if survivor.has_method("has_profession"):
		return bool(survivor.has_profession(profession_id))
	return str(survivor.profession) == profession_id or str(survivor.secondary_profession) == profession_id

func _job_experience(survivor, profession_id: String) -> int:
	if survivor.has_method("get_job_experience"):
		return int(survivor.get_job_experience(profession_id))
	return maxi(int(survivor.experience_by_job.get(profession_id, 0)), 0)

func _is_present(survivor) -> bool:
	if survivor.has_method("is_present_in_settlement"):
		return bool(survivor.is_present_in_settlement())
	return survivor.is_alive()
