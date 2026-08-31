class_name SettlementEventDefinition
extends Resource

const ChoiceDefinitionScript := preload("res://base_workbench/definitions/SettlementEventChoiceDefinition.gd")

const VALID_TONES: Array[String] = ["relief", "opportunity", "tradeoff", "hardship"]
const VALID_RECOVERY_ROLES: Array[String] = ["none", "general", "food", "materials", "workforce", "hope", "integrity", "medicine"]
const VALID_TRIGGER_TAGS: Array[String] = [
	"population_need",
	"food_need",
	"material_need",
	"low_integrity",
	"low_hope",
	"food_surplus",
	"medicine_need",
]
const VALID_IMPACT_TAGS: Array[String] = [
	"food_relief",
	"material_relief",
	"workforce_relief",
	"hope_relief",
	"integrity_relief",
	"medicine_relief",
	"population_gain",
	"food_demand",
	"food_cost",
	"material_cost",
	"hope_change",
	"integrity_risk",
	"resource_exchange",
]
const VALID_EXCLUSIVE_TAGS: Array[String] = [
	"food_critical",
	"hope_critical",
	"integrity_critical",
	"workforce_critical",
	"no_shelter",
	"recent_death",
	"storm_today",
]

@export var id: String = ""
@export var history_key: String = ""
@export var category: String = "general"
@export var title: String = ""
@export_multiline var body: String = ""
@export_range(0.0, 1000.0, 0.1) var base_weight: float = 10.0
@export_enum("relief", "opportunity", "tradeoff", "hardship") var tone: String = "tradeoff"
@export_range(0, 3, 1) var severity: int = 1
@export_range(0.0, 3.0, 0.05) var pressure_cost: float = 0.5
@export_range(1, 9999) var minimum_day: int = 3
@export_range(0, 9999) var cooldown_days: int = 3
@export var cooldown_group: String = ""
@export var once_per_campaign: bool = false
@export var allow_during_crisis: bool = true
@export_range(0, 999) var minimum_population: int = 0
@export_range(0, 999) var maximum_population: int = 999
@export var required_resource_minimums: Dictionary = {}
@export var trigger_tags: Array[String] = []
@export var impact_tags: Array[String] = []
@export var exclusive_tags: Array[String] = []
@export_enum("none", "general", "food", "materials", "workforce", "hope", "integrity", "medicine") var recovery_role: String = "none"
@export var fallback_choice_id: String = ""
@export var choices: Array[Resource] = []

func is_valid() -> bool:
	if id.is_empty() or history_key.is_empty() or category.is_empty() or title.is_empty() or body.is_empty():
		return false
	if base_weight <= 0.0 or minimum_day < 1 or cooldown_days < 0:
		return false
	if not VALID_TONES.has(tone) or severity < 0 or severity > 3 or pressure_cost < 0.0 or pressure_cost > 3.0:
		return false
	if cooldown_group.is_empty() or not VALID_RECOVERY_ROLES.has(recovery_role):
		return false
	if minimum_population < 0 or maximum_population < minimum_population:
		return false
	if not _tags_are_valid(trigger_tags):
		return false
	if not _tags_are_valid(impact_tags) or not _tags_are_valid(exclusive_tags):
		return false
	if not _tags_are_known(trigger_tags, VALID_TRIGGER_TAGS):
		return false
	if not _tags_are_known(impact_tags, VALID_IMPACT_TAGS) or not _tags_are_known(exclusive_tags, VALID_EXCLUSIVE_TAGS):
		return false
	if choices.size() < 2:
		return false
	var choice_ids: Array[String] = []
	for choice in choices:
		if choice == null or choice.get_script() != ChoiceDefinitionScript or not choice.is_valid():
			return false
		if choice_ids.has(str(choice.id)):
			return false
		choice_ids.append(str(choice.id))
	var fallback = find_choice(fallback_choice_id)
	if fallback == null or not fallback.survivor_definition_ids.is_empty():
		return false
	for raw_resource_id in fallback.resource_deltas.keys():
		var resource_id := str(raw_resource_id)
		if resource_id in ["hope", "platform_integrity"]:
			continue
		if int(fallback.resource_deltas[raw_resource_id]) < 0:
			return false
	return true

func find_choice(choice_id: String):
	for choice in choices:
		if choice != null and choice.get_script() == ChoiceDefinitionScript and str(choice.id) == choice_id:
			return choice
	return null

func effective_trigger_tags() -> Array[String]:
	var result: Array[String] = []
	for raw_tag in trigger_tags:
		var tag := str(raw_tag)
		if not tag.is_empty() and not result.has(tag):
			result.append(tag)
	return result

func _tags_are_valid(tags: Array[String]) -> bool:
	var seen: Array[String] = []
	for raw_tag in tags:
		var tag := str(raw_tag)
		if tag.is_empty() or seen.has(tag):
			return false
		seen.append(tag)
	return true

func _tags_are_known(tags: Array[String], allowed_tags: Array[String]) -> bool:
	for raw_tag in tags:
		if not allowed_tags.has(str(raw_tag)):
			return false
	return true
