class_name SurvivorState
extends Resource

const DEFAULT_BASE_OXYGEN_CAPACITY := 100.0
const DEFAULT_BASE_CARRY_CAPACITY := 18.0
const HEALTH_PER_SKILL_POINT := 10
const OXYGEN_PER_SKILL_POINT := 10.0
const CARRY_CAPACITY_PER_SKILL_POINT := 4.0
const MAX_LEVEL := 99
const WORK_MIN_HEALTH_RATIO := 0.35
const WORK_MAX_HUNGER_EXCLUSIVE := 85
const WORK_MAX_FATIGUE_EXCLUSIVE := 90
const WORK_MIN_MORALE := 10
const DIVE_MIN_HEALTH_RATIO := 0.50
const DIVE_MAX_HUNGER_EXCLUSIVE := 65
const DIVE_MAX_FATIGUE_EXCLUSIVE := 85
const DIVE_MIN_MORALE := 20
const DiseaseCaseStateScript := preload("res://scripts/data/DiseaseCaseState.gd")
const CompetencySystemScript := preload("res://scripts/base/CompetencySystem.gd")
const ProfessionTalentSystemScript := preload("res://scripts/base/ProfessionTalentSystem.gd")

enum Status {
	AVAILABLE,
	WORKING,
	DIVING,
	RESTING,
	INJURED,
	DEAD,
	DEPARTED,
}

@export var id: String = ""
@export var display_name: String = ""
@export var age_group: String = "adult"
@export var biography: String = ""
@export var profession: String = ""
@export var secondary_profession: String = ""
@export var experience_by_job: Dictionary = {}
@export var portrait_id: String = ""
@export_range(1, MAX_LEVEL) var level: int = 1
@export_range(0, 1000000) var experience: int = 0
@export_range(0, 1000) var unspent_skill_points: int = 0
@export var competency_levels: Dictionary = {}
@export var profession_talent_ids: Dictionary = {}
@export_range(1, 10000) var base_max_health: int = 100
@export_range(0, 10000) var health_bonus: int = 0
@export var health: int = 100
@export_range(1.0, 10000.0, 1.0) var base_oxygen_capacity: float = DEFAULT_BASE_OXYGEN_CAPACITY
@export_range(0.0, 10000.0, 1.0) var oxygen_capacity_bonus: float = 0.0
@export_range(1.0, 10000.0, 0.5) var base_carry_capacity: float = DEFAULT_BASE_CARRY_CAPACITY
@export_range(0.0, 10000.0, 0.5) var carry_capacity_bonus: float = 0.0
@export_range(0, 100) var hunger: int = 0
@export_range(0, 100) var fatigue: int = 0
@export_range(0, 100) var morale: int = 55
@export var positive_trait: String = ""
@export var negative_trait: String = ""
@export var relationship_links: Dictionary = {}
@export var current_assignment: String = ""
@export var injury_states: Array[String] = []
@export var disease_cases: Array[Resource] = []
@export var status: int = Status.AVAILABLE

func work_blocker() -> String:
	if status not in [Status.AVAILABLE, Status.WORKING, Status.RESTING]:
		return _status_blocker("pracować")
	var disease_blocker := _typed_disease_blocker(false)
	if not disease_blocker.is_empty():
		return disease_blocker
	if health_ratio() < WORK_MIN_HEALTH_RATIO:
		return "Zdrowie jest niższe niż 35%."
	if hunger >= WORK_MAX_HUNGER_EXCLUSIVE:
		return "Głód wynosi co najmniej 85%."
	if fatigue >= WORK_MAX_FATIGUE_EXCLUSIVE:
		return "Zmęczenie wynosi co najmniej 90%."
	if morale < WORK_MIN_MORALE:
		return "Morale jest niższe niż 10%."
	return ""


func can_work() -> bool:
	return work_blocker().is_empty()


func dive_blocker() -> String:
	if status not in [Status.AVAILABLE, Status.WORKING]:
		return _status_blocker("nurkować")
	var disease_blocker := _typed_disease_blocker(true)
	if not disease_blocker.is_empty():
		return disease_blocker
	if health_ratio() < DIVE_MIN_HEALTH_RATIO:
		return "Zdrowie jest niższe niż 50%."
	if hunger >= DIVE_MAX_HUNGER_EXCLUSIVE:
		return "Głód wynosi co najmniej 65%."
	if fatigue >= DIVE_MAX_FATIGUE_EXCLUSIVE:
		return "Zmęczenie wynosi co najmniej 85%."
	if morale < DIVE_MIN_MORALE:
		return "Morale jest niższe niż 20%."
	return ""


func can_dive() -> bool:
	return dive_blocker().is_empty()

func work_efficiency() -> float:
	if not can_work():
		return 0.0
	var hunger_multiplier := 1.0
	if hunger >= 65:
		hunger_multiplier = 0.45
	elif hunger >= 40:
		hunger_multiplier = 0.75
	elif hunger >= 20:
		hunger_multiplier = 0.90
	var fatigue_multiplier := 1.0
	if fatigue >= 85:
		fatigue_multiplier = 0.35
	elif fatigue >= 65:
		fatigue_multiplier = 0.65
	elif fatigue >= 40:
		fatigue_multiplier = 0.90
	var morale_multiplier := 1.05 if morale >= 70 else 0.75 if morale < 20 else 1.0
	var health_multiplier := lerpf(0.65, 1.0, clampf((health_ratio() - 0.35) / 0.65, 0.0, 1.0))
	var baseline := hunger_multiplier * fatigue_multiplier * morale_multiplier * health_multiplier
	return clampf(baseline * disease_work_efficiency_multiplier() * CompetencySystemScript.cooperation_multiplier(self), 0.0, 1.20)


func disease_work_efficiency_multiplier() -> float:
	var result := 1.0
	for disease_case in disease_cases:
		if disease_case == null or disease_case.get_script() != DiseaseCaseStateScript:
			continue
		result = minf(result, float(disease_case.work_efficiency_multiplier()))
	return clampf(result, 0.0, 1.0)

func is_alive() -> bool:
	return status not in [Status.DEAD, Status.DEPARTED]

func is_present_in_settlement() -> bool:
	return status not in [Status.DEAD, Status.DEPARTED]

func has_profession(profession_id: String) -> bool:
	if profession_id.is_empty():
		return false
	return profession == profession_id or secondary_profession == profession_id

func get_job_experience(profession_id: String) -> int:
	if profession_id.is_empty():
		return 0
	return maxi(int(experience_by_job.get(profession_id, 0)), 0)

func set_job_experience(profession_id: String, amount: int) -> void:
	if profession_id.is_empty():
		return
	experience_by_job[profession_id] = maxi(amount, 0)

func ensure_compatibility() -> void:
	level = clampi(level, 1, MAX_LEVEL)
	experience = maxi(experience, 0)
	unspent_skill_points = maxi(unspent_skill_points, 0)
	base_max_health = maxi(base_max_health, 1)
	health_bonus = maxi(health_bonus, 0)
	base_oxygen_capacity = maxf(base_oxygen_capacity, 1.0)
	oxygen_capacity_bonus = maxf(oxygen_capacity_bonus, 0.0)
	base_carry_capacity = maxf(base_carry_capacity, 1.0)
	carry_capacity_bonus = maxf(carry_capacity_bonus, 0.0)
	health = clampi(health, 0, get_max_health())
	if secondary_profession == profession:
		secondary_profession = ""
	var compatible_experience_by_job: Dictionary = {}
	for profession_id in experience_by_job.keys():
		var normalized_id := str(profession_id).strip_edges()
		if not normalized_id.is_empty():
			compatible_experience_by_job[normalized_id] = maxi(int(experience_by_job[profession_id]), 0)
	experience_by_job = compatible_experience_by_job
	if portrait_id.is_empty():
		portrait_id = id
	var compatible_competencies: Dictionary = {}
	for competency_id in competency_levels.keys():
		var normalized_id := str(competency_id)
		var competency_level := clampi(int(competency_levels[competency_id]), 0, CompetencySystemScript.MAX_LEVEL)
		if CompetencySystemScript.is_valid_id(normalized_id) and competency_level > 0:
			compatible_competencies[normalized_id] = competency_level
	competency_levels = compatible_competencies
	var talent_system = ProfessionTalentSystemScript.new()
	var compatible_talents: Dictionary = {}
	for profession_key in profession_talent_ids.keys():
		var profession_id := str(profession_key).strip_edges()
		var talent_id := str(profession_talent_ids[profession_key]).strip_edges()
		var definition = talent_system.get_definition(talent_id)
		if (
			not profession_id.is_empty()
			and definition != null
			and str(definition.profession_id) == profession_id
			and has_profession(profession_id)
		):
			compatible_talents[profession_id] = talent_id
	profession_talent_ids = compatible_talents

func get_max_health() -> int:
	return maxi(base_max_health + health_bonus, 1)

func health_ratio() -> float:
	return clampf(float(health) / float(get_max_health()), 0.0, 1.0)

func get_oxygen_capacity() -> float:
	return maxf(base_oxygen_capacity + oxygen_capacity_bonus, 1.0)

func get_carry_capacity() -> float:
	return maxf(base_carry_capacity + carry_capacity_bonus, 1.0)

func get_expedition_oxygen_capacity(
	oxygen_tank_capacity: float,
	specialist_bonus: float = 0.0,
	specialist_personal_capacity_multiplier: float = 1.0
) -> float:
	var tank_upgrade := oxygen_tank_capacity - DEFAULT_BASE_OXYGEN_CAPACITY
	var personal_capacity := get_oxygen_capacity() * maxf(specialist_personal_capacity_multiplier, 0.01)
	return maxf(personal_capacity + tank_upgrade + specialist_bonus, 1.0)

func experience_to_next_level() -> int:
	return 100 + (level - 1) * 50

func add_experience(amount: int) -> int:
	if amount <= 0 or level >= MAX_LEVEL:
		return 0
	experience += amount
	var levels_gained := 0
	while level < MAX_LEVEL and experience >= experience_to_next_level():
		experience -= experience_to_next_level()
		level += 1
		levels_gained += 1
		unspent_skill_points += 1
	if level >= MAX_LEVEL:
		experience = 0
	return levels_gained

func skill_point_blocker(stat_id: String) -> String:
	if stat_id not in ["health", "oxygen", "oxygen_capacity", "carry", "carry_capacity"] and not CompetencySystemScript.is_valid_id(stat_id):
		return "Ta ścieżka rozwoju nie istnieje."
	if CompetencySystemScript.is_valid_id(stat_id) and CompetencySystemScript.level(self, stat_id) >= CompetencySystemScript.MAX_LEVEL:
		return "Ta kompetencja osiągnęła maksymalny poziom."
	if unspent_skill_points <= 0:
		return "Brak niewydanych punktów rozwoju."
	return ""


func can_spend_skill_point(stat_id: String) -> bool:
	return skill_point_blocker(stat_id).is_empty()


func spend_skill_point(stat_id: String) -> bool:
	if not can_spend_skill_point(stat_id):
		return false
	match stat_id:
		"health":
			health_bonus += HEALTH_PER_SKILL_POINT
			health += HEALTH_PER_SKILL_POINT
		"oxygen", "oxygen_capacity":
			oxygen_capacity_bonus += OXYGEN_PER_SKILL_POINT
		"carry", "carry_capacity":
			carry_capacity_bonus += CARRY_CAPACITY_PER_SKILL_POINT
		_:
			competency_levels[stat_id] = CompetencySystemScript.level(self, stat_id) + 1
	unspent_skill_points -= 1
	return true


func _status_blocker(action: String) -> String:
	match status:
		Status.DIVING:
			return "Mieszkaniec jest obecnie na wyprawie i nie może %s." % action
		Status.INJURED:
			return "Uraz nie pozwala mieszkańcowi %s." % action
		Status.DEAD:
			return "Zmarły mieszkaniec nie może %s." % action
		Status.DEPARTED:
			return "Mieszkaniec opuścił Przystań i nie może %s." % action
	return "Bieżący status mieszkańca nie pozwala mu %s." % action


func _typed_disease_blocker(for_diving: bool) -> String:
	for disease_case in disease_cases:
		if disease_case == null or disease_case.get_script() != DiseaseCaseStateScript:
			continue
		var blocks_action: bool = not disease_case.can_dive() if for_diving else disease_case.work_efficiency_multiplier() <= 0.0
		if not blocks_action:
			continue
		var stage = disease_case.current_stage()
		var definition = disease_case.definition_snapshot
		var disease_name := str(definition.display_name) if definition != null else str(disease_case.disease_id)
		var stage_name: String = str(stage.display_name) if stage != null else disease_case.phase_id()
		return "%s (%s) nie pozwala mieszkańcowi %s." % [disease_name, stage_name, "nurkować" if for_diving else "pracować"]
	return ""
