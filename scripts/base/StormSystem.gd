class_name StormSystem
extends RefCounted

const BASE_INTERVAL_DAYS := 4
const BASE_DAMAGE := 6

func is_storm_day(day: int, frequency_multiplier: float = 1.0) -> bool:
	var interval := maxi(int(round(float(BASE_INTERVAL_DAYS) / maxf(frequency_multiplier, 0.01))), 1)
	return day > 0 and day % interval == 0

func calculate_damage(damage_multiplier: float = 1.0) -> int:
	return maxi(int(round(float(BASE_DAMAGE) * maxf(damage_multiplier, 0.0))), 0)
