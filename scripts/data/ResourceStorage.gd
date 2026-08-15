class_name ResourceStorage
extends Resource

const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")

@export var values: Dictionary = {}

func setup_defaults(profile = null) -> void:
	values.clear()
	set_amount(ResourceIdsScript.HOPE, 55)
	set_amount(ResourceIdsScript.FOOD, profile.starting_food if profile != null else 48)
	set_amount(ResourceIdsScript.PLANKS, profile.starting_planks if profile != null else 12)
	set_amount(ResourceIdsScript.SCRAP, profile.starting_scrap if profile != null else 8)
	set_amount(ResourceIdsScript.FABRIC_RUBBER, 4)
	set_amount(ResourceIdsScript.TECH_PARTS, 0)
	set_amount(ResourceIdsScript.MEDS_CHEMICALS, 2)
	set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 70)

func get_amount(resource_id: String) -> int:
	return int(values.get(resource_id, 0))

func set_amount(resource_id: String, amount: int) -> void:
	values[resource_id] = max(amount, 0)

func add_amount(resource_id: String, amount: int) -> void:
	set_amount(resource_id, get_amount(resource_id) + amount)

func spend(resource_id: String, amount: int) -> bool:
	if get_amount(resource_id) < amount:
		return false
	add_amount(resource_id, -amount)
	return true
