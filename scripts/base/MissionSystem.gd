class_name MissionSystem
extends RefCounted

const CampaignProgressionSystemScript := preload("res://scripts/base/CampaignProgressionSystem.gd")
const MissionProgressStateScript := preload("res://scripts/data/MissionProgressState.gd")
const MISSION_DIRECTORY := "res://data/missions"

const FOUNDATION_HARBOR := "foundation_harbor"
const OLD_SIGNAL := "old_signal"
const LEADERSHIP_CRISIS := "leadership_crisis"

const ID_ALIASES := {
	"voice_from_hotel": "rescue_leon",
}

var _definitions: Dictionary = {}
var _campaign_progression = CampaignProgressionSystemScript.new()


func definitions() -> Dictionary:
	_ensure_definitions()
	return _definitions.duplicate()


func mission_definition(mission_id: String):
	_ensure_definitions()
	return _definitions.get(_canonical_id(mission_id), null)


func reconcile(state) -> bool:
	_ensure_definitions()
	var progress = _progress_for(state, true)
	if progress == null:
		return false

	var changed: bool = progress.ensure_compatibility()
	changed = _canonicalize_progress(progress) or changed
	changed = progress.ensure_compatibility() or changed
	var ordered_definitions := _sorted_definitions()
	var iteration_limit := maxi(ordered_definitions.size() * 3, 12)

	for _iteration in range(iteration_limit):
		var iteration_changed := false
		for definition in ordered_definitions:
			var mission_id := str(definition.id)
			if progress.is_active(mission_id):
				continue
			if progress.is_completed(mission_id) or progress.is_failed(mission_id):
				if _should_reactivate(state, definition):
					iteration_changed = progress.reactivate(mission_id, _activation_day(state, definition)) or iteration_changed
				continue
			if _can_activate(state, progress, definition):
				iteration_changed = progress.activate(mission_id, _activation_day(state, definition)) or iteration_changed

		for raw_mission_id in progress.active_mission_ids.duplicate():
			var mission_id := _canonical_id(str(raw_mission_id))
			var definition = _definitions.get(mission_id, null)
			if definition == null:
				continue
			match _mission_outcome(state, definition):
				"completed":
					iteration_changed = progress.complete(mission_id, _state_day(state)) or iteration_changed
				"failed":
					iteration_changed = progress.fail(mission_id, _state_day(state)) or iteration_changed

		changed = iteration_changed or changed
		if not iteration_changed:
			break

	changed = _reconcile_tracking(progress) or changed
	return changed


func track_mission(state, mission_id: String) -> bool:
	reconcile(state)
	var progress = _progress_for(state, false)
	if progress == null:
		return false
	var canonical_id := _canonical_id(mission_id)
	if not progress.is_active(canonical_id):
		return false
	var urgent_id := _active_urgent_mission_id(progress)
	if not urgent_id.is_empty() and canonical_id != urgent_id:
		return false
	if progress.tracked_mission_id == canonical_id:
		return false
	progress.tracked_mission_id = canonical_id
	if urgent_id.is_empty():
		progress.resume_mission_id = ""
	return true


func mission_view(state, mission_id: String) -> Dictionary:
	reconcile(state)
	var progress = _progress_for(state, false)
	if progress == null:
		return {}
	var definition = mission_definition(mission_id)
	if definition == null:
		return {}
	return _build_mission_view(state, progress, definition)


func tracked_mission_view(state) -> Dictionary:
	reconcile(state)
	var progress = _progress_for(state, false)
	if progress == null or progress.tracked_mission_id.is_empty():
		return {}
	var definition = mission_definition(progress.tracked_mission_id)
	if definition == null or not progress.is_active(str(definition.id)):
		return {}
	return _build_mission_view(state, progress, definition)


func active_views(state) -> Array:
	reconcile(state)
	var progress = _progress_for(state, false)
	if progress == null:
		return []
	var result: Array = []
	for definition in _sorted_definitions():
		if progress.is_active(str(definition.id)):
			result.append(_build_mission_view(state, progress, definition))
	return result


func completed_views(state) -> Array:
	reconcile(state)
	var progress = _progress_for(state, false)
	if progress == null:
		return []
	var result: Array = []
	for definition in _sorted_definitions():
		var mission_id := str(definition.id)
		if progress.is_completed(mission_id) or progress.is_failed(mission_id):
			result.append(_build_mission_view(state, progress, definition))
	return result


func expedition_guidance(state) -> Dictionary:
	reconcile(state)
	var progress = _progress_for(state, false)
	if progress == null:
		return {}

	var candidate_ids: Array[String] = []
	if progress.is_active(progress.tracked_mission_id):
		candidate_ids.append(progress.tracked_mission_id)
	for definition in _sorted_definitions():
		var mission_id := str(definition.id)
		if progress.is_active(mission_id) and not candidate_ids.has(mission_id):
			candidate_ids.append(mission_id)

	for mission_id in candidate_ids:
		var definition = _definitions.get(mission_id, null)
		if definition == null:
			continue
		for objective in definition.objectives:
			if objective == null or str(objective.target_landmark_id).is_empty():
				continue
			var objective_state := _evaluate_objective(state, objective)
			if bool(objective_state.get("complete", false)) or bool(objective_state.get("failed", false)):
				continue
			return {
				"mission_id": mission_id,
				"title": str(definition.title),
				"guidance": str(objective.guidance) if not str(objective.guidance).is_empty() else str(definition.summary),
				"landmark_id": str(objective.target_landmark_id),
				"landmark_label": str(objective.landmark_label),
			}
	return {}


func _ensure_definitions() -> void:
	if not _definitions.is_empty():
		return
	var file_names := DirAccess.get_files_at(MISSION_DIRECTORY)
	file_names.sort()
	for file_name in file_names:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var definition = ResourceLoader.load(MISSION_DIRECTORY.path_join(file_name))
		if definition == null:
			continue
		var mission_id := str(definition.id)
		if mission_id.is_empty() or _definitions.has(mission_id):
			continue
		_definitions[mission_id] = definition


func _progress_for(state, create_if_missing: bool):
	if state == null or not ("mission_progress" in state):
		return null
	var progress = state.get("mission_progress")
	if progress == null and create_if_missing:
		progress = MissionProgressStateScript.new()
		state.set("mission_progress", progress)
	if progress == null or not progress.has_method("ensure_compatibility"):
		return null
	return progress


func _canonical_id(mission_id: String) -> String:
	var normalized_id := mission_id.strip_edges()
	return str(ID_ALIASES.get(normalized_id, normalized_id))


func _canonicalize_progress(progress) -> bool:
	var changed := false
	for property_name in ["active_mission_ids", "completed_mission_ids", "failed_mission_ids"]:
		var canonical_ids: Array[String] = []
		for raw_id in progress.get(property_name):
			var mission_id := _canonical_id(str(raw_id))
			if not mission_id.is_empty() and not canonical_ids.has(mission_id):
				canonical_ids.append(mission_id)
		if progress.get(property_name) != canonical_ids:
			progress.set(property_name, canonical_ids)
			changed = true

	for property_name in ["started_days", "completed_days", "failed_days"]:
		var original: Dictionary = progress.get(property_name)
		var canonical_days: Dictionary = {}
		for raw_id in original.keys():
			var mission_id := _canonical_id(str(raw_id))
			if mission_id.is_empty():
				continue
			canonical_days[mission_id] = maxi(int(canonical_days.get(mission_id, 0)), int(original[raw_id]))
		if original != canonical_days:
			progress.set(property_name, canonical_days)
			changed = true

	var tracked_id := _canonical_id(progress.tracked_mission_id)
	if tracked_id != progress.tracked_mission_id:
		progress.tracked_mission_id = tracked_id
		changed = true
	var resume_id := _canonical_id(progress.resume_mission_id)
	if resume_id != progress.resume_mission_id:
		progress.resume_mission_id = resume_id
		changed = true
	return changed


func _can_activate(state, progress, definition) -> bool:
	for prerequisite_id in definition.prerequisite_mission_ids:
		if not progress.is_completed(_canonical_id(str(prerequisite_id))):
			return false

	match str(definition.unlock_kind):
		"always":
			return true
		"tutorial_complete", "tutorial_completed":
			return _tutorial_completed(state)
		"building_built":
			return _building_level(state, str(definition.unlock_target_id)) >= maxi(int(definition.unlock_required_level), 1)
		"building_level":
			return _building_level(state, str(definition.unlock_target_id)) >= maxi(int(definition.unlock_required_level), 1)
		"heavy_recovery_available":
			return (_building_level(state, "diving_station") >= 4 and _building_level(state, "workshop") >= 3) or _world_count(state, "recovered_heavy_objects") > 0
		"crisis_active", "crisis_started":
			return _crisis_has_started(state)
	return false


func _should_reactivate(state, definition) -> bool:
	if not bool(definition.repeatable):
		return false
	match str(definition.unlock_kind):
		"crisis_active", "crisis_started":
			var story = _story(state)
			return story != null and bool(story.crisis_active)
	return false


func _mission_outcome(state, definition) -> String:
	if definition.objectives.is_empty():
		return ""
	var all_complete := true
	for objective in definition.objectives:
		var objective_state := _evaluate_objective(state, objective)
		if bool(objective_state.get("failed", false)):
			return "failed"
		if not bool(objective_state.get("complete", false)):
			all_complete = false
	return "completed" if all_complete else ""


func _evaluate_objective(state, objective) -> Dictionary:
	var required := maxi(int(objective.required_count), 1)
	var current := 0
	var complete := false
	var failed := false
	var status_text := ""
	var extra: Dictionary = {}

	match str(objective.kind):
		"building_built":
			complete = _building_level(state, str(objective.target_id)) >= 1
			current = 1 if complete else 0
			status_text = "Wybudowano." if complete else "Jeszcze nie wybudowano. Budynek w kolejce nie jest ukończony."
		"fixed_device_activated":
			complete = (
				state != null
				and "underwater_world" in state
				and state.underwater_world != null
				and state.underwater_world.delta != null
				and state.underwater_world.delta.activated_fixed_devices.has(str(objective.target_id))
			)
			current = 1 if complete else 0
			status_text = "Urządzenie uruchomione, dane przesłane." if complete else "Urządzenie nieaktywne."
		"rescue_outcome":
			var rescue_status := _rescue_status(state, str(objective.target_id))
			complete = rescue_status == "rescued"
			failed = rescue_status == "dead"
			current = 1 if complete else 0
			if complete:
				status_text = "Ocalały wrócił do Przystani."
			elif failed:
				status_text = "Nie udało się uratować ocalałego."
			else:
				status_text = "Los ocalałego pozostaje nierozstrzygnięty."
		"gear_owned":
			for gear_id in _objective_target_ids(objective):
				if _has_gear_evidence(state, gear_id):
					complete = true
					break
			current = 1 if complete else 0
			status_text = "Sprzęt wykonany." if complete else "Wykonaj sprzęt w Warsztacie Odzysku."
		"buoy_count":
			current = mini(_world_count(state, "placed_buoys"), required)
			complete = current >= required
			status_text = "Boje: %d/%d." % [current, required]
		"shortcut_count":
			current = mini(_world_count(state, "opened_shortcuts"), required)
			complete = current >= required
			status_text = "Otwarte skróty: %d/%d." % [current, required]
		"heavy_recovered_count":
			current = mini(_world_count(state, "recovered_heavy_objects"), required)
			complete = current >= required
			status_text = "Ciężkie znaleziska: %d/%d." % [current, required]
		"crisis_recovered":
			var story = _story(state)
			var crisis_active := story != null and bool(story.crisis_active)
			complete = story != null and not crisis_active and story.has_method("has_flag") and story.has_flag("leadership_crisis_survived")
			failed = story != null and str(story.game_over_reason) == "leadership_collapse"
			current = 1 if complete else 0
			status_text = "Wspólnota odzyskała nadzieję." if complete else "Przystań upadła w kryzysie." if failed else "Podnieś Nadzieję do 15, zanim minie czas."

	var result := {
		"current": current,
		"required": required,
		"complete": complete,
		"failed": failed,
		"status_text": status_text,
	}
	result.merge(extra, true)
	return result


func _build_mission_view(state, progress, definition) -> Dictionary:
	var mission_id := str(definition.id)
	var status := "locked"
	if progress.is_active(mission_id):
		status = "active"
	elif progress.is_completed(mission_id):
		status = "completed"
	elif progress.is_failed(mission_id):
		status = "failed"

	var objective_views: Array = []
	var current := 0
	var required := 0
	var readiness_blockers: Array[String] = []
	var ready := false
	for objective in definition.objectives:
		var objective_state := _evaluate_objective(state, objective)
		var objective_current := int(objective_state.get("current", 0))
		var objective_required := maxi(int(objective_state.get("required", 1)), 1)
		current += mini(objective_current, objective_required)
		required += objective_required
		if objective_state.has("blockers"):
			readiness_blockers.assign(objective_state.get("blockers", []))
			ready = bool(objective_state.get("ready", false))
		objective_views.append({
			"id": str(objective.id),
			"kind": str(objective.kind),
			"text": str(objective.text),
			"description": str(objective.description),
			"target_id": str(objective.target_id),
			"target_ids": objective.target_ids.duplicate(),
			"target_landmark_id": str(objective.target_landmark_id),
			"landmark_id": str(objective.target_landmark_id),
			"landmark_label": str(objective.landmark_label),
			"guidance": str(objective.guidance),
			"current": objective_current,
			"required": objective_required,
			"progress": objective_current,
			"target": objective_required,
			"complete": bool(objective_state.get("complete", false)),
			"completed": bool(objective_state.get("complete", false)),
			"failed": bool(objective_state.get("failed", false)),
			"status_text": str(objective_state.get("status_text", "")),
		})

	var result := {
		"id": mission_id,
		"category": str(definition.category),
		"title": str(definition.title),
		"summary": str(definition.summary),
		"completion_text": str(definition.completion_text),
		"failure_text": str(definition.failure_text),
		"status": status,
		"visible": status != "locked",
		"urgent": bool(definition.urgent),
		"tracked": status == "active" and progress.tracked_mission_id == mission_id,
		"sort_order": int(definition.sort_order),
		"objectives": objective_views,
		"progress": current,
		"target": required,
		"current": current,
		"required": required,
		"progress_data": {
			"current": current,
			"required": required,
			"target": required,
		},
		"started_day": int(progress.started_days.get(mission_id, 0)),
		"completed_day": int(progress.completed_days.get(mission_id, 0)),
		"failed_day": int(progress.failed_days.get(mission_id, 0)),
	}
	return result


func _reconcile_tracking(progress) -> bool:
	var changed := false
	var urgent_id := _active_urgent_mission_id(progress)
	if not urgent_id.is_empty():
		if progress.tracked_mission_id != urgent_id:
			var previous_id: String = str(progress.tracked_mission_id)
			var previous_successor := _successor_mission_id(progress, previous_id)
			if previous_id != urgent_id and (progress.is_active(previous_id) or not previous_successor.is_empty()):
				progress.resume_mission_id = previous_id
			progress.tracked_mission_id = urgent_id
			changed = true
		return changed

	if not progress.resume_mission_id.is_empty():
		var resume_id: String = str(progress.resume_mission_id)
		progress.resume_mission_id = ""
		changed = true
		var resume_target := resume_id if progress.is_active(resume_id) else _successor_mission_id(progress, resume_id)
		if progress.is_active(resume_target) and progress.tracked_mission_id != resume_target:
			progress.tracked_mission_id = resume_target
			changed = true

	if not progress.is_active(progress.tracked_mission_id):
		var successor_id := _successor_mission_id(progress, str(progress.tracked_mission_id))
		var default_id := successor_id if not successor_id.is_empty() else _default_tracked_mission_id(progress)
		if progress.tracked_mission_id != default_id:
			progress.tracked_mission_id = default_id
			changed = true
	return changed


func _active_urgent_mission_id(progress) -> String:
	for definition in _sorted_definitions():
		if bool(definition.urgent) and progress.is_active(str(definition.id)):
			return str(definition.id)
	return ""


func _default_tracked_mission_id(progress) -> String:
	for definition in _sorted_definitions():
		if bool(definition.auto_track_on_activate) and progress.is_active(str(definition.id)):
			return str(definition.id)
	for definition in _sorted_definitions():
		if progress.is_active(str(definition.id)):
			return str(definition.id)
	return ""


func _successor_mission_id(progress, previous_mission_id: String) -> String:
	if previous_mission_id.is_empty():
		return ""
	for definition in _sorted_definitions():
		var mission_id := str(definition.id)
		if progress.is_active(mission_id) and definition.prerequisite_mission_ids.has(previous_mission_id):
			return mission_id
	var previous_definition = _definitions.get(previous_mission_id, null)
	if previous_definition == null or str(previous_definition.category) != "main":
		return ""
	for definition in _sorted_definitions():
		var mission_id := str(definition.id)
		if (
			progress.is_active(mission_id)
			and str(definition.category) == "main"
			and int(definition.sort_order) > int(previous_definition.sort_order)
		):
			return mission_id
	return ""


func _sorted_definitions() -> Array:
	_ensure_definitions()
	var result: Array = _definitions.values()
	result.sort_custom(_definition_before)
	return result


func _definition_before(left, right) -> bool:
	if int(left.sort_order) == int(right.sort_order):
		return str(left.id) < str(right.id)
	return int(left.sort_order) < int(right.sort_order)


func _tutorial_completed(state) -> bool:
	if state == null or not ("tutorial" in state) or state.tutorial == null:
		return false
	if state.tutorial.has_method("is_active"):
		return not state.tutorial.is_active()
	return false


func _story(state):
	if state == null or not ("story_flags" in state):
		return null
	return state.story_flags


func _state_day(state) -> int:
	if state == null or not ("day" in state):
		return 0
	return maxi(int(state.day), 0)


func _activation_day(state, definition) -> int:
	if str(definition.id) == LEADERSHIP_CRISIS:
		var story = _story(state)
		if story != null and int(story.crisis_started_day) > 0:
			return int(story.crisis_started_day)
	return _state_day(state)


func _building_level(state, definition_id: String) -> int:
	if state == null or not ("buildings" in state):
		return 0
	var highest_level := 0
	for building in state.buildings:
		if building == null or str(building.definition_id) != definition_id or not bool(building.is_built):
			continue
		highest_level = maxi(highest_level, int(building.level))
	return highest_level


func _crisis_has_started(state) -> bool:
	var story = _story(state)
	if story == null:
		return false
	return (
		bool(story.crisis_active)
		or int(story.crisis_started_day) > 0
		or (story.has_method("has_flag") and story.has_flag("leadership_crisis_started"))
		or (story.has_method("has_flag") and story.has_flag("leadership_crisis_survived"))
		or str(story.game_over_reason) == "leadership_collapse"
	)


func _rescue_status(state, rescue_id: String) -> String:
	if state == null or not ("underwater_world" in state) or state.underwater_world == null:
		return ""
	var outcomes: Dictionary = state.underwater_world.rescued_or_dead_survivors
	var outcome = outcomes.get(rescue_id, {})
	return str(outcome.get("status", "")) if outcome is Dictionary else ""


func _objective_target_ids(objective) -> Array[String]:
	var result: Array[String] = []
	var primary_id := str(objective.target_id)
	if not primary_id.is_empty():
		result.append(primary_id)
	for raw_id in objective.target_ids:
		var target_id := str(raw_id)
		if not target_id.is_empty() and not result.has(target_id):
			result.append(target_id)
	return result


func _has_gear_evidence(state, gear_id: String) -> bool:
	if state == null or gear_id.is_empty():
		return false
	if "diving_equipment" in state and state.diving_equipment != null:
		if state.diving_equipment.has_method("owns") and state.diving_equipment.owns(gear_id):
			return true
		if "owned_gear_ids" in state.diving_equipment and state.diving_equipment.owned_gear_ids.has(gear_id):
			return true
	if not ("underwater_world" in state) or state.underwater_world == null:
		return false
	for record in state.underwater_world.lost_backpacks.values():
		if record is Dictionary and record.get("gear_ids", []).has(gear_id):
			return true
	return false


func _world_count(state, property_name: String) -> int:
	if state == null or not ("underwater_world" in state) or state.underwater_world == null:
		return 0
	if not (property_name in state.underwater_world):
		return 0
	var values = state.underwater_world.get(property_name)
	return values.size() if values is Array or values is Dictionary else 0
