class_name MissionObjectiveDefinition
extends Resource

const SUPPORTED_KINDS: Array[String] = [
	"building_built",
	"artifact_recovered",
	"fixed_device_activated",
	"project_started",
	"project_completed",
	"rescue_outcome",
	"gear_owned",
	"buoy_count",
	"shortcut_count",
	"heavy_recovered_count",
	"crisis_recovered",
]

@export var id: String = ""
@export var kind: String = ""
@export var text: String = ""
@export_multiline var description: String = ""
@export var target_id: String = ""
@export var target_ids: Array[String] = []
@export_range(1, 999, 1) var required_count: int = 1
@export var target_landmark_id: String = ""
@export var landmark_label: String = ""
@export_multiline var guidance: String = ""


func is_valid() -> bool:
	if id.is_empty() or not SUPPORTED_KINDS.has(kind) or text.is_empty() or required_count < 1:
		return false
	return not target_id.is_empty() or not target_ids.is_empty() or kind in [
		"project_started",
		"project_completed",
		"buoy_count",
		"shortcut_count",
		"heavy_recovered_count",
		"crisis_recovered",
	]
