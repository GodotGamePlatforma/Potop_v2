class_name MissionDefinition
extends Resource

@export var id: String = ""
@export var category: String = "side"
@export var title: String = ""
@export_multiline var summary: String = ""
@export_multiline var completion_text: String = ""
@export_multiline var failure_text: String = ""
@export_range(0, 9999, 1) var sort_order: int = 100
@export var urgent: bool = false
@export var auto_track_on_activate: bool = false
@export var repeatable: bool = false
@export var prerequisite_mission_ids: Array[String] = []
@export var unlock_kind: String = "always"
@export var unlock_target_id: String = ""
@export_range(0, 99, 1) var unlock_required_level: int = 0
@export var objectives: Array[Resource] = []


func is_valid() -> bool:
	if id.is_empty() or category.is_empty() or title.is_empty() or summary.is_empty():
		return false
	if unlock_kind.is_empty() or objectives.is_empty():
		return false
	var objective_ids: Array[String] = []
	for objective in objectives:
		if objective == null or not objective.has_method("is_valid") or not objective.is_valid():
			return false
		var objective_id := str(objective.id)
		if objective_ids.has(objective_id):
			return false
		objective_ids.append(objective_id)
	return true
