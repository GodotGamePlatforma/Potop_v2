class_name BuildingDefinition
extends Resource

const CareerProgressionSystemScript := preload("res://scripts/survivors/CareerProgressionSystem.gd")

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var max_level: int = 1
@export var requires_edge: bool = false
@export var levels: Array = []
@export var specialist_bonus: Dictionary = {}

func get_level_definition(target_level: int):
	for level_definition in levels:
		if level_definition != null and int(level_definition.level) == target_level:
			return level_definition
	return null

func get_build_cost() -> Dictionary:
	var level_definition = get_level_definition(1)
	return level_definition.build_cost if level_definition != null else {}

func get_upgrade_cost(current_level: int) -> Dictionary:
	var next_level_definition = get_level_definition(current_level + 1)
	return next_level_definition.upgrade_cost if next_level_definition != null else {}

func get_worker_slots(current_level: int) -> int:
	var level_definition = get_level_definition(current_level)
	return max(int(level_definition.worker_slots), 1) if level_definition != null else 1

func get_specialist_bonus_value(survivor, bonus_id: String, default_value: float = 0.0) -> float:
	if survivor == null or specialist_bonus.is_empty():
		return default_value
	var profession_id := str(specialist_bonus.get("profession", ""))
	if profession_id.is_empty():
		return default_value
	var effectiveness := CareerProgressionSystemScript.get_specialist_effectiveness(survivor, profession_id)
	var specialist_value := float(specialist_bonus.get(bonus_id, default_value))
	return lerpf(default_value, specialist_value, effectiveness)
