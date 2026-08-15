class_name ProfessionTalentDefinition
extends Resource

@export var id: String = ""
@export var profession_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var parameters: Dictionary = {}
@export_range(0, 100, 1) var sort_order: int = 0


func is_valid() -> bool:
	return (
		not id.strip_edges().is_empty()
		and not profession_id.strip_edges().is_empty()
		and not display_name.strip_edges().is_empty()
		and not description.strip_edges().is_empty()
		and not parameters.is_empty()
	)
