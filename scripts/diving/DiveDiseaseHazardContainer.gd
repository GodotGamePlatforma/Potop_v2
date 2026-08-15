class_name DiveDiseaseHazardContainer
extends "res://scripts/diving/DiveLootContainer.gd"

const DiseaseExposureStateScript := preload("res://scripts/data/DiseaseExposureState.gd")

@export var disease_id: String = ""
@export var exposure_pressure: int = 0
@export var exposure_source_kind: String = "dive"
@export var exposure_source_id: String = ""

var exposure_accepted: bool = false


func configure_hazard(
	id: String,
	title: String,
	loot: Dictionary,
	hazard_disease_id: String,
	hazard_pressure: int,
	hazard_source_kind: String,
	hazard_source_id: String,
	required_tool_id: String = "",
	action_id: String = "open",
	required_seconds: float = 1.15
) -> void:
	configure(id, title, loot, -1, required_tool_id, action_id, required_seconds)
	disease_id = hazard_disease_id.strip_edges()
	exposure_pressure = maxi(hazard_pressure, 0)
	exposure_source_kind = hazard_source_kind.strip_edges()
	exposure_source_id = hazard_source_id.strip_edges()
	exposure_accepted = false
	set_visual_semantic("hazard")


func has_pending_hazard_decision() -> bool:
	return can_interact() and not exposure_accepted


func accept_exposure(target_survivor_id: String, acquired_day: int) -> DiseaseExposureState:
	if not has_pending_hazard_decision():
		return null
	var exposure := DiseaseExposureStateScript.create(
		disease_id,
		target_survivor_id,
		exposure_source_kind,
		exposure_source_id,
		exposure_pressure,
		acquired_day
	) as DiseaseExposureState
	if exposure == null or not exposure.is_valid():
		return null
	exposure_accepted = true
	return exposure


func restore_initial_contents() -> void:
	exposure_accepted = false
	super.restore_initial_contents()


func restore_contents(loot: Dictionary) -> void:
	exposure_accepted = false
	super.restore_contents(loot)


func interaction_text() -> String:
	if has_pending_hazard_decision():
		return "Przytrzymaj %s: zbadaj skażony %s" % [
			InputPromptScript.action_text(&"dive_interact"),
			display_name.to_lower(),
		]
	return super.interaction_text()
