class_name MissionProgressState
extends Resource

@export var active_mission_ids: Array[String] = []
@export var completed_mission_ids: Array[String] = []
@export var failed_mission_ids: Array[String] = []
@export var started_days: Dictionary = {}
@export var completed_days: Dictionary = {}
@export var failed_days: Dictionary = {}
@export var tracked_mission_id: String = ""
@export var resume_mission_id: String = ""


func ensure_compatibility() -> bool:
	var changed := false
	changed = _sanitize_ids(active_mission_ids) or changed
	changed = _sanitize_ids(completed_mission_ids) or changed
	changed = _sanitize_ids(failed_mission_ids) or changed

	for mission_id in completed_mission_ids:
		if active_mission_ids.has(mission_id):
			active_mission_ids.erase(mission_id)
			changed = true
		if failed_mission_ids.has(mission_id):
			failed_mission_ids.erase(mission_id)
			changed = true
	for mission_id in failed_mission_ids:
		if active_mission_ids.has(mission_id):
			active_mission_ids.erase(mission_id)
			changed = true

	changed = _sanitize_days(started_days) or changed
	changed = _sanitize_days(completed_days) or changed
	changed = _sanitize_days(failed_days) or changed

	var normalized_tracked := tracked_mission_id.strip_edges()
	if tracked_mission_id != normalized_tracked:
		tracked_mission_id = normalized_tracked
		changed = true
	var normalized_resume := resume_mission_id.strip_edges()
	if resume_mission_id != normalized_resume:
		resume_mission_id = normalized_resume
		changed = true
	# Śledzony cel albo cel powrotu może zakończyć się między rekoncyliacjami.
	# Zachowujemy jego ID, aby MissionSystem mógł wybrać aktywnego następcę.
	return changed


func is_active(mission_id: String) -> bool:
	return active_mission_ids.has(mission_id)


func is_completed(mission_id: String) -> bool:
	return completed_mission_ids.has(mission_id)


func is_failed(mission_id: String) -> bool:
	return failed_mission_ids.has(mission_id)


func activate(mission_id: String, day: int) -> bool:
	var normalized_id := mission_id.strip_edges()
	if normalized_id.is_empty() or is_active(normalized_id) or is_completed(normalized_id) or is_failed(normalized_id):
		return false
	active_mission_ids.append(normalized_id)
	if not started_days.has(normalized_id):
		started_days[normalized_id] = maxi(day, 0)
	return true


func reactivate(mission_id: String, day: int) -> bool:
	var normalized_id := mission_id.strip_edges()
	if normalized_id.is_empty() or is_active(normalized_id):
		return false
	completed_mission_ids.erase(normalized_id)
	failed_mission_ids.erase(normalized_id)
	completed_days.erase(normalized_id)
	failed_days.erase(normalized_id)
	active_mission_ids.append(normalized_id)
	started_days[normalized_id] = maxi(day, 0)
	return true


func complete(mission_id: String, day: int) -> bool:
	var normalized_id := mission_id.strip_edges()
	if normalized_id.is_empty() or is_completed(normalized_id):
		return false
	active_mission_ids.erase(normalized_id)
	failed_mission_ids.erase(normalized_id)
	completed_mission_ids.append(normalized_id)
	completed_days[normalized_id] = maxi(day, 0)
	return true


func fail(mission_id: String, day: int) -> bool:
	var normalized_id := mission_id.strip_edges()
	if normalized_id.is_empty() or is_completed(normalized_id) or is_failed(normalized_id):
		return false
	active_mission_ids.erase(normalized_id)
	failed_mission_ids.append(normalized_id)
	failed_days[normalized_id] = maxi(day, 0)
	return true


func _sanitize_ids(values: Array[String]) -> bool:
	var sanitized: Array[String] = []
	for value in values:
		var mission_id := str(value).strip_edges()
		if not mission_id.is_empty() and not sanitized.has(mission_id):
			sanitized.append(mission_id)
	if values == sanitized:
		return false
	values.assign(sanitized)
	return true


func _sanitize_days(values: Dictionary) -> bool:
	var sanitized: Dictionary = {}
	for raw_key in values.keys():
		var mission_id := str(raw_key).strip_edges()
		if not mission_id.is_empty():
			sanitized[mission_id] = maxi(int(values[raw_key]), 0)
	if values == sanitized:
		return false
	values.clear()
	values.merge(sanitized, true)
	return true
