class_name DiverCameraProfile
extends Resource

## Tunable, presentation-only contract for the diver camera look-ahead.
## Distances are world units and response values are exponential-equivalent rates per second.

@export_range(0.0, 100.0, 0.5) var movement_dead_zone := 12.0
@export_range(0.0, 1.0, 0.01) var minimum_intent_alignment := 0.8
@export_range(0.0, 300.0, 1.0) var swim_lead_distance := 72.0
@export_range(0.0, 300.0, 1.0) var sprint_lead_distance := 112.0
@export_range(0.1, 30.0, 0.1) var swim_response := 5.0
@export_range(0.1, 30.0, 0.1) var sprint_response := 8.0
@export_range(0.1, 30.0, 0.1) var recenter_response := 6.0


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for value: float in [
		movement_dead_zone,
		minimum_intent_alignment,
		swim_lead_distance,
		sprint_lead_distance,
		swim_response,
		sprint_response,
		recenter_response,
	]:
		if not is_finite(value):
			errors.append("Camera profile values must be finite.")
			return errors
	if movement_dead_zone < 0.0:
		errors.append("movement_dead_zone cannot be negative.")
	if minimum_intent_alignment <= 0.0 or minimum_intent_alignment > 1.0:
		errors.append("minimum_intent_alignment must be in the (0, 1] range.")
	if swim_lead_distance <= 0.0:
		errors.append("swim_lead_distance must be positive.")
	if sprint_lead_distance <= swim_lead_distance:
		errors.append("sprint_lead_distance must be greater than swim_lead_distance.")
	if swim_response <= 0.0 or recenter_response <= 0.0:
		errors.append("Swim and recenter response rates must be positive.")
	if sprint_response <= swim_response:
		errors.append("sprint_response must be greater than swim_response.")
	return errors
