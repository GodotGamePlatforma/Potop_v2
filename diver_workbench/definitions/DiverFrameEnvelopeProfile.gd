class_name DiverFrameEnvelopeProfile
extends Resource

const DiverFrameEnvelopeScript := preload("res://diver_workbench/definitions/DiverFrameEnvelope.gd")
const PHYSICAL_ENVELOPE := Vector2(105.0, 60.0)

@export var target_size := PHYSICAL_ENVELOPE
@export var authored_sprite_scale := Vector2(0.239, 0.239)
@export var authored_sprite_position := Vector2(5.497, -3.2265)


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if target_size.x <= 0.0 or target_size.y <= 0.0:
		errors.append("target_size must be positive.")
	if not target_size.is_equal_approx(PHYSICAL_ENVELOPE):
		errors.append("target_size must match the approved 105 x 60 physical collider envelope.")
	if authored_sprite_scale.x <= 0.0 or authored_sprite_scale.y <= 0.0:
		errors.append("authored_sprite_scale must be positive.")
	if not is_equal_approx(authored_sprite_scale.x, authored_sprite_scale.y):
		errors.append("authored_sprite_scale must preserve the source aspect ratio.")
	var base_world_size: Vector2 = DiverFrameEnvelopeScript.SOURCE_UNION.size * authored_sprite_scale
	if base_world_size.x > target_size.x + 0.001 or base_world_size.y > target_size.y + 0.001:
		errors.append("The measured source union does not fit target_size at authored_sprite_scale.")
	var expected_position := -(
		DiverFrameEnvelopeScript.SOURCE_UNION.position
		+ DiverFrameEnvelopeScript.SOURCE_UNION.size * 0.5
	) * authored_sprite_scale
	if not authored_sprite_position.is_equal_approx(expected_position):
		errors.append("authored_sprite_position must center the measured source union on the physical root.")
	return errors
