class_name OxygenSystem
extends RefCounted

const IDLE_RATE := 0.12
const SWIM_RATE := 0.34
const SPRINT_RATE := 0.68

func consume(current: float, delta: float, multiplier: float = 1.0) -> float:
	return max(current - delta * multiplier, 0.0)

func consumption_rate(
	is_moving: bool,
	is_sprinting: bool,
	load_ratio: float,
	in_current: bool,
	load_surcharge_multiplier: float = 1.0
) -> float:
	var rate := IDLE_RATE
	if is_moving:
		rate = SWIM_RATE
	if is_sprinting:
		rate = SPRINT_RATE
	rate *= 1.0 + clampf(load_ratio, 0.0, 1.0) * 0.32 * maxf(load_surcharge_multiplier, 0.0)
	if in_current and is_moving:
		rate *= 1.18
	return rate
