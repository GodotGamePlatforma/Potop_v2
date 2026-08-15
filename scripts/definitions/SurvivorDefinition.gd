class_name SurvivorDefinition
extends Resource

const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")

@export var id: String = ""
@export var display_name: String = ""
@export var age_group: String = "adult"
@export_multiline var biography: String = ""
@export var profession: String = ""
@export var secondary_profession: String = ""
@export var positive_trait: String = ""
@export var negative_trait: String = ""
@export var portrait_id: String = ""
@export_range(1, 10000) var health: int = 100
@export_range(0, 100) var morale: int = 55

func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() and not profession.is_empty() and health > 0

func create_state():
	var survivor = SurvivorStateScript.new()
	survivor.id = id
	survivor.display_name = display_name
	survivor.age_group = age_group
	survivor.biography = biography
	survivor.profession = profession
	survivor.secondary_profession = secondary_profession
	survivor.positive_trait = positive_trait
	survivor.negative_trait = negative_trait
	survivor.portrait_id = id if portrait_id.is_empty() else portrait_id
	survivor.health = health
	survivor.morale = morale
	survivor.status = SurvivorStateScript.Status.AVAILABLE
	survivor.ensure_compatibility()
	return survivor
