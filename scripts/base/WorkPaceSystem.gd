class_name WorkPaceSystem
extends RefCounted

const WORK_PACE_CAREFUL := "careful"
const WORK_PACE_NORMAL := "normal"
const WORK_PACE_INTENSE := "intense"

const MIN_TENSION := 0
const MAX_TENSION := 3


static func valid_paces() -> Array[String]:
	var result: Array[String] = [
		WORK_PACE_CAREFUL,
		WORK_PACE_NORMAL,
		WORK_PACE_INTENSE,
	]
	return result


static func is_valid_pace(pace: String) -> bool:
	return pace in valid_paces()


static func normalize_pace(pace) -> String:
	var normalized := str(pace)
	return normalized if is_valid_pace(normalized) else WORK_PACE_NORMAL


static func pace_label(pace) -> String:
	match normalize_pace(pace):
		WORK_PACE_CAREFUL:
			return "Ostrożne"
		WORK_PACE_INTENSE:
			return "Intensywne"
	return "Normalne"


static func output_multiplier(pace) -> float:
	match normalize_pace(pace):
		WORK_PACE_CAREFUL:
			return 0.75
		WORK_PACE_INTENSE:
			return 1.25
	return 1.0


static func worker_fatigue_gain(pace) -> int:
	match normalize_pace(pace):
		WORK_PACE_CAREFUL:
			return 4
		WORK_PACE_INTENSE:
			return 14
	return 8


static func diver_fatigue_gain(dive_duration: float, pace) -> int:
	var duration_component := mini(floori(maxf(dive_duration, 0.0) / 120.0), 14)
	var base_fatigue := 16 + duration_component
	return int(round(float(base_fatigue) * output_multiplier(pace)))


static func community_worker_adjustment(pace) -> int:
	match normalize_pace(pace):
		WORK_PACE_CAREFUL:
			return -1
		WORK_PACE_INTENSE:
			return 1
	return 0


static func pace_for_building(state, building) -> String:
	if building == null:
		return WORK_PACE_NORMAL
	var building_id := str(_read_property(building, "id", ""))
	var plan = _read_property(state, "current_day_plan", null)
	var planned_paces = _read_property(plan, "building_work_paces", {})
	if planned_paces is Dictionary and not building_id.is_empty() and planned_paces.has(building_id):
		return normalize_pace(planned_paces[building_id])
	return normalize_pace(_read_property(building, "work_pace", WORK_PACE_NORMAL))


static func tension_transition(previous_tension: int, pace, worked: bool) -> Dictionary:
	var previous := clampi(previous_tension, MIN_TENSION, MAX_TENSION)
	var current := previous
	var normalized_pace := normalize_pace(pace)
	var relieved := false
	if not worked:
		current = maxi(previous - 2, MIN_TENSION)
	else:
		match normalized_pace:
			WORK_PACE_CAREFUL:
				current = maxi(previous - 2, MIN_TENSION)
				relieved = current < previous
			WORK_PACE_INTENSE:
				current = mini(previous + 1, MAX_TENSION)
			_:
				current = maxi(previous - 1, MIN_TENSION)
	return {
		"previous": previous,
		"current": current,
		"delta": current - previous,
		"pace": normalized_pace,
		"worked": worked,
		"relieved": relieved,
		"intense": worked and normalized_pace == WORK_PACE_INTENSE,
	}


static func workforce_band(worker_count: int) -> int:
	var normalized_count := maxi(worker_count, 0)
	if normalized_count <= 3:
		return 0
	if normalized_count <= 6:
		return 1
	return 2


static func _read_property(value, property_name: String, fallback):
	if value == null:
		return fallback
	if value is Dictionary:
		return value.get(property_name, fallback)
	if not value is Object:
		return fallback
	if not value.has_method("get_property_list"):
		return fallback
	for property in value.get_property_list():
		if str(property.get("name", "")) == property_name:
			return value.get(property_name)
	return fallback
