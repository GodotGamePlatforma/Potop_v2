class_name ProfessionDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var building_definition_id: String = ""
@export_multiline var description: String = ""
@export_multiline var specialist_benefit: String = ""
@export_range(1, 1000, 1) var general_experience_per_workday: int = 100
@export_range(1, 1000, 1) var practice_experience_per_workday: int = 20
@export_range(1, 100000, 1) var apprentice_experience: int = 40
@export_range(1, 100000, 1) var promotion_experience: int = 100
@export_range(0, 100, 1) var sort_order: int = 0

func is_valid() -> bool:
	return (
		not id.is_empty()
		and not display_name.is_empty()
		and not building_definition_id.is_empty()
		and general_experience_per_workday > 0
		and practice_experience_per_workday > 0
		and apprentice_experience > 0
		and promotion_experience > apprentice_experience
	)
