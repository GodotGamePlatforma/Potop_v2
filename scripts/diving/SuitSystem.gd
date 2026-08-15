class_name SuitSystem
extends RefCounted

const LEAK_START_CONDITION := 70
const CRITICAL_CONDITION := 30

func apply_damage(condition: int, amount: int) -> int:
	return clampi(condition - maxi(amount, 0), 0, 100)

func calculate_damage(raw_amount: int, suit_quality: int = 1, multiplier: float = 1.0) -> int:
	if raw_amount <= 0 or multiplier <= 0.0:
		return 0
	var quality_reduction := clampf(float(maxi(suit_quality, 1) - 1) * 0.10, 0.0, 0.40)
	return maxi(int(ceil(float(raw_amount) * multiplier * (1.0 - quality_reduction))), 1)

func repair(condition: int, amount: int) -> int:
	return clampi(condition + maxi(amount, 0), 0, 100)

func repair_amount(suit_quality: int) -> int:
	return 30 + clampi(suit_quality - 1, 0, 4) * 5

func is_leaking(condition: int) -> bool:
	return condition < LEAK_START_CONDITION

func is_critical(condition: int) -> bool:
	return condition <= CRITICAL_CONDITION

func leak_health_rate(condition: int) -> float:
	if condition >= LEAK_START_CONDITION:
		return 0.0
	if condition > CRITICAL_CONDITION:
		return lerpf(0.08, 0.42, inverse_lerp(float(LEAK_START_CONDITION), float(CRITICAL_CONDITION), float(condition)))
	if condition > 0:
		return lerpf(0.55, 1.15, inverse_lerp(float(CRITICAL_CONDITION), 0.0, float(condition)))
	return 1.6

func cold_exposure_multiplier(condition: int) -> float:
	if condition >= LEAK_START_CONDITION:
		return 1.0
	return lerpf(1.0, 2.25, inverse_lerp(float(LEAK_START_CONDITION), 0.0, float(condition)))
