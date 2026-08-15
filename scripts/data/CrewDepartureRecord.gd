class_name CrewDepartureRecord
extends Resource

const VALID_REASON_IDS: Array[String] = ["player_dismissal", "candidate_replacement", "chronicle_departure"]
const DiseaseCaseStateScript := preload("res://scripts/data/DiseaseCaseState.gd")
const CompetencySystemScript := preload("res://scripts/base/CompetencySystem.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const RosterRotationSystemScript := preload("res://scripts/base/RosterRotationSystem.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")

@export var survivor_id: String = ""
@export var display_name: String = ""
@export var portrait_id: String = ""
@export var departure_day: int = 0
@export var reason_id: String = ""
@export var departure_option_id: String = ""
@export var profession: String = ""
@export var secondary_profession: String = ""
@export var level: int = 1
@export var experience: int = 0
@export var unspent_skill_points: int = 0
@export var experience_by_job: Dictionary = {}
@export var competency_levels: Dictionary = {}
@export var base_max_health: int = 1
@export var health_bonus: int = 0
@export var health: int = 1
@export var hunger: int = 0
@export var fatigue: int = 0
@export var morale: int = 0
@export var injury_states: Array[String] = []
@export var disease_case_snapshots: Array[Resource] = []
@export var vulnerability_reason_ids: Array[String] = []
@export var base_hope_delta: int = 0
@export var vulnerability_hope_delta: int = 0
@export var hope_delta: int = 0
@export var provision_cost: Dictionary = {}


static func capture(
	survivor,
	day: int,
	departure_reason_id: String,
	departure_option: String,
	food_per_adult: int
):
	if survivor == null or survivor.get_script() != SurvivorStateScript:
		return null
	var record = new()
	record.survivor_id = str(survivor.id)
	record.display_name = str(survivor.display_name)
	record.portrait_id = str(survivor.portrait_id)
	record.departure_day = day
	record.reason_id = departure_reason_id
	record.departure_option_id = departure_option
	record.profession = str(survivor.profession)
	record.secondary_profession = str(survivor.secondary_profession)
	record.level = int(survivor.level)
	record.experience = int(survivor.experience)
	record.unspent_skill_points = int(survivor.unspent_skill_points)
	record.experience_by_job = survivor.experience_by_job.duplicate(true)
	record.competency_levels = survivor.competency_levels.duplicate(true)
	record.base_max_health = int(survivor.base_max_health)
	record.health_bonus = int(survivor.health_bonus)
	record.health = int(survivor.health)
	record.hunger = int(survivor.hunger)
	record.fatigue = int(survivor.fatigue)
	record.morale = int(survivor.morale)
	record.injury_states.assign(survivor.injury_states)
	record.vulnerability_reason_ids = RosterRotationSystemScript.departure_vulnerability_reasons(survivor)
	record.base_hope_delta = RosterRotationSystemScript.departure_base_hope_delta(departure_option)
	record.vulnerability_hope_delta = RosterRotationSystemScript.departure_vulnerability_hope_delta(survivor)
	record.hope_delta = record.base_hope_delta + record.vulnerability_hope_delta
	record.provision_cost = RosterRotationSystemScript.departure_provision_cost(departure_option, food_per_adult)
	for disease_case in survivor.disease_cases:
		if disease_case != null and disease_case.get_script() == DiseaseCaseStateScript:
			record.disease_case_snapshots.append(disease_case.duplicate(true))
	return record


func validation_errors() -> PackedStringArray:
	var errors: Array[String] = []
	if survivor_id.strip_edges().is_empty() or display_name.strip_edges().is_empty():
		errors.append("Rejestr odejścia mieszkańca nie ma pełnej tożsamości.")
	if departure_day < 1:
		errors.append("Rejestr odejścia mieszkańca ma niepoprawny dzień.")
	if not VALID_REASON_IDS.has(reason_id):
		errors.append("Rejestr odejścia mieszkańca ma nieznany powód.")
	if departure_option_id not in [RosterRotationSystemScript.DEPARTURE_WITH_PROVISIONS, RosterRotationSystemScript.DEPARTURE_WITHOUT_PROVISIONS]:
		errors.append("Rejestr odejścia mieszkańca ma nieznany wariant rozstania.")
	if (
		profession.strip_edges().is_empty()
		or level < 1
		or experience < 0
		or unspent_skill_points < 0
		or base_max_health < 1
		or health_bonus < 0
		or health < 1
		or health > base_max_health + health_bonus
	):
		errors.append("Rejestr odejścia mieszkańca ma niepoprawną migawkę rozwoju albo zdrowia.")
	for field_name in ["hunger", "fatigue", "morale"]:
		var value := int(get(field_name))
		if value < 0 or value > 100:
			errors.append("Rejestr odejścia ma %s poza zakresem 0..100." % field_name)
	var expected_base_delta := RosterRotationSystemScript.departure_base_hope_delta(departure_option_id)
	var expected_vulnerability_delta := RosterRotationSystemScript.DEPARTURE_VULNERABILITY_HOPE if not vulnerability_reason_ids.is_empty() else 0
	if base_hope_delta != expected_base_delta or vulnerability_hope_delta != expected_vulnerability_delta or hope_delta != base_hope_delta + vulnerability_hope_delta:
		errors.append("Rejestr odejścia ma niespójne składniki delty Nadziei.")
	_validate_unique_strings(errors, injury_states, "uraz")
	_validate_unique_strings(errors, vulnerability_reason_ids, "powód dodatkowej kary")
	var seen_disease_ids: Dictionary = {}
	for disease_case in disease_case_snapshots:
		if disease_case == null or disease_case.get_script() != DiseaseCaseStateScript or not disease_case.is_valid():
			errors.append("Rejestr odejścia ma niepoprawną migawkę choroby.")
			continue
		var disease_id := str(disease_case.disease_id)
		if seen_disease_ids.has(disease_id):
			errors.append("Rejestr odejścia ma powieloną chorobę %s." % disease_id)
		else:
			seen_disease_ids[disease_id] = true
	for profession_id in experience_by_job.keys():
		if str(profession_id).strip_edges().is_empty() or typeof(experience_by_job[profession_id]) != TYPE_INT or int(experience_by_job[profession_id]) < 0:
			errors.append("Rejestr odejścia ma niepoprawną praktykę zawodową.")
	for competency_id in competency_levels.keys():
		var competency_level := int(competency_levels[competency_id])
		if not CompetencySystemScript.is_valid_id(str(competency_id)) or competency_level < 1 or competency_level > CompetencySystemScript.MAX_LEVEL:
			errors.append("Rejestr odejścia ma niepoprawną kompetencję %s." % competency_id)
	if departure_option_id == RosterRotationSystemScript.DEPARTURE_WITH_PROVISIONS:
		if (
			provision_cost.size() != 1
			or not provision_cost.has(ResourceIdsScript.FOOD)
			or typeof(provision_cost[ResourceIdsScript.FOOD]) != TYPE_INT
			or int(provision_cost[ResourceIdsScript.FOOD]) < 1
		):
			errors.append("Odejście z prowiantem musi zapisać dokładnie dodatni koszt jedzenia.")
	elif not provision_cost.is_empty():
		errors.append("Odejście bez prowiantu nie może zapisać kosztu zasobów.")
	return PackedStringArray(errors)


func is_valid() -> bool:
	return validation_errors().is_empty()


static func _validate_unique_strings(errors: Array[String], values: Array[String], label: String) -> void:
	var seen: Dictionary = {}
	for value in values:
		var normalized := value.strip_edges()
		if normalized.is_empty() or seen.has(normalized):
			errors.append("Rejestr odejścia ma pusty albo powielony wpis: %s." % label)
		else:
			seen[normalized] = true
