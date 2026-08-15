class_name DiveMovementSystem
extends RefCounted


## Pure fixed-step part of DiverController movement. Collision remains owned by
## CharacterBody2D in live play and by DiveNavigationSnapshot in design-time
## recovery replay.
static func advance_velocity(
	previous_velocity: Vector2,
	command_input: Vector2,
	sprint_requested: bool,
	world_current: Vector2,
	speed_multiplier: float,
	delta: float,
	swim_speed: float,
	sprint_speed: float,
	acceleration: float,
	drag: float
) -> Vector2:
	var movement_input := command_input.limit_length(1.0)
	var is_sprinting := sprint_requested and movement_input.length_squared() > 0.01
	var clamped_speed_multiplier := clampf(speed_multiplier, 0.1, 1.5)
	var target_speed := (sprint_speed if is_sprinting else swim_speed) * clamped_speed_multiplier
	var target_velocity := movement_input * target_speed + world_current
	var change_rate := acceleration if movement_input.length_squared() > 0.01 else drag
	return previous_velocity.move_toward(
		target_velocity,
		maxf(change_rate, 0.0) * maxf(delta, 0.0)
	)
