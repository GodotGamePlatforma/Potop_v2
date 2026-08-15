class_name DiseaseStageDefinition
extends Resource

@export var phase_id: String = ""
@export var display_name: String = ""
@export var next_phase_id: String = ""
@export_range(0.0, 1.0, 0.01) var work_efficiency_multiplier: float = 1.0
@export var dive_allowed: bool = true
@export var infectious: bool = false
@export_range(0, 100, 1) var contact_pressure: int = 0
@export_range(-1000, 0, 1) var daily_health_delta: int = 0


func validation_errors(known_phase_ids: Array[String] = []) -> PackedStringArray:
	var errors: Array[String] = []
	if phase_id.strip_edges().is_empty():
		errors.append("phase_id cannot be empty")
	elif not known_phase_ids.is_empty() and not known_phase_ids.has(phase_id):
		errors.append("unknown phase_id: " + phase_id)
	if display_name.strip_edges().is_empty():
		errors.append("display_name cannot be empty")
	if not next_phase_id.is_empty() and not known_phase_ids.is_empty() and not known_phase_ids.has(next_phase_id):
		errors.append("unknown next_phase_id: " + next_phase_id)
	if not is_finite(work_efficiency_multiplier) or work_efficiency_multiplier < 0.0 or work_efficiency_multiplier > 1.0:
		errors.append("work_efficiency_multiplier must be finite and between zero and one")
	if contact_pressure < 0 or contact_pressure > 100:
		errors.append("contact_pressure must be between 0 and 100")
	if infectious != (contact_pressure > 0):
		errors.append("infectious must match whether contact_pressure is positive")
	if daily_health_delta > 0 or daily_health_delta < -1000:
		errors.append("daily_health_delta must be between -1000 and 0")
	return PackedStringArray(errors)


func is_valid(known_phase_ids: Array[String] = []) -> bool:
	return validation_errors(known_phase_ids).is_empty()
