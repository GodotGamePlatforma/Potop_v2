class_name TemperatureSystem
extends RefCounted

const MAX_EXPOSURE := 100.0
const HYPOTHERMIA_THRESHOLD := 70.0
const CRITICAL_THRESHOLD := 88.0

func cold_rate_for_depth(depth: float) -> float:
	var depth_ratio := clampf(maxf(depth, 0.0) / 160.0, 0.0, 1.0)
	return 0.035 + pow(depth_ratio, 1.45) * 0.72

func exposure_rate(depth: float, suit_quality: int, suit_condition_multiplier: float, difficulty_multiplier: float = 1.0) -> float:
	var quality_insulation := 1.0 - clampf(float(maxi(suit_quality, 1) - 1) * 0.12, 0.0, 0.42)
	return cold_rate_for_depth(depth) \
		* quality_insulation \
		* maxf(suit_condition_multiplier, 0.0) \
		* maxf(difficulty_multiplier, 0.0)

func advance_exposure(current: float, delta: float, depth: float, suit_quality: int, suit_condition_multiplier: float, difficulty_multiplier: float = 1.0) -> float:
	return clampf(current + exposure_rate(depth, suit_quality, suit_condition_multiplier, difficulty_multiplier) * maxf(delta, 0.0), 0.0, MAX_EXPOSURE)

func movement_multiplier(exposure: float) -> float:
	if exposure < 45.0:
		return 1.0
	return lerpf(1.0, 0.68, inverse_lerp(45.0, MAX_EXPOSURE, clampf(exposure, 45.0, MAX_EXPOSURE)))

func interaction_speed_multiplier(exposure: float) -> float:
	if exposure < 55.0:
		return 1.0
	return lerpf(1.0, 0.58, inverse_lerp(55.0, MAX_EXPOSURE, clampf(exposure, 55.0, MAX_EXPOSURE)))

func health_damage_rate(exposure: float) -> float:
	if exposure < CRITICAL_THRESHOLD:
		return 0.0
	return lerpf(0.12, 0.75, inverse_lerp(CRITICAL_THRESHOLD, MAX_EXPOSURE, clampf(exposure, CRITICAL_THRESHOLD, MAX_EXPOSURE)))

func is_hypothermic(exposure: float) -> bool:
	return exposure >= HYPOTHERMIA_THRESHOLD

func is_critical(exposure: float) -> bool:
	return exposure >= CRITICAL_THRESHOLD
