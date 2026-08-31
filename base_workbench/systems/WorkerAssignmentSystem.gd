class_name WorkerAssignmentSystem
extends RefCounted

const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")


func assign_worker(state, survivor_id: String, building_id: String, max_workers: int = 1) -> bool:
	if state == null:
		return false
	var building = state.find_building(building_id)
	if building == null:
		return false
	var slot_index: int = building.assigned_survivor_ids.find(survivor_id)
	if slot_index < 0:
		slot_index = building.assigned_survivor_ids.size()
	return assign_worker_to_slot(state, building_id, slot_index, survivor_id, max_workers)


func assign_worker_to_slot(
	state,
	building_id: String,
	slot_index: int,
	survivor_id: String,
	max_workers: int = 1
) -> bool:
	if not _can_edit_assignments(state):
		return false
	var target_building = state.find_building(building_id)
	if target_building == null or not target_building.is_active():
		return false
	if max_workers <= 0 or slot_index < 0 or slot_index >= max_workers:
		return false

	var previous_survivor_id := ""
	if slot_index < target_building.assigned_survivor_ids.size():
		previous_survivor_id = str(target_building.assigned_survivor_ids[slot_index])
	if previous_survivor_id == survivor_id:
		return true

	var survivor = null
	if not survivor_id.is_empty():
		survivor = state.find_survivor(survivor_id)
		if not assignment_candidate_blocker(state, survivor_id, building_id, slot_index).is_empty():
			return false
	elif previous_survivor_id.is_empty():
		return false

	# Build the complete target roster before mutating either side of the
	# assignment. The compact array format stays compatible with existing saves:
	# clearing a slot closes the gap, while assigning beyond the current tail
	# appends to the first representable position.
	var updated_target_ids: Array[String] = []
	for assigned_id in target_building.assigned_survivor_ids:
		var normalized_id := str(assigned_id)
		if normalized_id == survivor_id:
			continue
		if not previous_survivor_id.is_empty() and normalized_id == previous_survivor_id:
			continue
		updated_target_ids.append(normalized_id)
	if not survivor_id.is_empty():
		updated_target_ids.insert(mini(slot_index, updated_target_ids.size()), survivor_id)
	if updated_target_ids.size() > max_workers:
		return false

	if not survivor_id.is_empty():
		for building in state.buildings:
			if building == null or building == target_building:
				continue
			_erase_all(building.assigned_survivor_ids, survivor_id)
	target_building.assigned_survivor_ids.assign(updated_target_ids)
	if (
		survivor != null
		and state.current_day_plan != null
		and str(state.current_day_plan.selected_diver_id) == survivor_id
	):
		state.current_day_plan.selected_diver_id = ""

	if not previous_survivor_id.is_empty():
		_refresh_survivor_assignment(state, previous_survivor_id)
	if survivor != null:
		survivor.current_assignment = building_id
		survivor.status = SurvivorStateScript.Status.WORKING
	_sync_unlocked_day_plan(state)
	return true


func assignment_candidate_blocker(
	state,
	survivor_id: String,
	building_id: String = "",
	slot_index: int = -1
) -> String:
	if state == null:
		return "Brak stanu kampanii."
	if state.has_method("day_plan_edit_blocker"):
		var plan_blocker := str(state.day_plan_edit_blocker())
		if not plan_blocker.is_empty():
			return plan_blocker
	elif not _can_edit_assignments(state):
		return "Obsady nie można zmieniać po zablokowaniu planu dnia."
	return assignment_role_blocker(state, survivor_id, building_id, slot_index)


func assignment_role_blocker(
	state,
	survivor_id: String,
	building_id: String = "",
	slot_index: int = -1
) -> String:
	if state == null:
		return "Brak stanu kampanii."
	var survivor = state.find_survivor(survivor_id)
	if survivor == null or not survivor.is_present_in_settlement():
		return "Mieszkaniec nie jest obecny w Przystani."
	if _is_isolated_in_current_plan(state, survivor_id):
		return "Zaplanowana izolacja wyklucza nowy przydział i daje tego dnia 0 pracy."
	if not building_id.is_empty():
		var target_building = state.find_building(building_id)
		if target_building == null:
			return "Docelowy budynek nie istnieje."
		if not target_building.is_active():
			return "Docelowy budynek nie jest aktywny."
	return str(survivor.work_blocker()) if survivor.has_method("work_blocker") else ""


func reconcile_assignments(state) -> bool:
	if state == null:
		return false
	var changed := false
	var claimed_survivor_ids: Dictionary = {}

	# Building rosters are authoritative because they preserve compact slot order.
	# Invalid, terminal and duplicate entries cannot reserve invisible workplaces.
	for building in state.buildings:
		if building == null:
			continue
		var normalized_ids: Array[String] = []
		for assigned_id in building.assigned_survivor_ids:
			var survivor_id := str(assigned_id)
			var survivor = state.find_survivor(survivor_id)
			if (
				survivor_id.is_empty()
				or survivor == null
				or not survivor.is_present_in_settlement()
				or claimed_survivor_ids.has(survivor_id)
			):
				changed = true
				continue
			claimed_survivor_ids[survivor_id] = str(building.id)
			normalized_ids.append(survivor_id)
		if building.assigned_survivor_ids != normalized_ids:
			building.assigned_survivor_ids.assign(normalized_ids)
			changed = true

	for survivor in state.survivors:
		if survivor == null:
			continue
		var previous_assignment := str(survivor.current_assignment)
		var previous_status := int(survivor.status)
		_refresh_survivor_assignment(state, str(survivor.id), claimed_survivor_ids)
		if previous_assignment != str(survivor.current_assignment) or previous_status != int(survivor.status):
			changed = true

	if changed:
		if state.current_day_plan != null:
			var selected_diver = state.find_survivor(str(state.current_day_plan.selected_diver_id))
			if selected_diver == null or not str(selected_diver.current_assignment).is_empty() or not selected_diver.is_present_in_settlement():
				state.current_day_plan.selected_diver_id = ""
		_sync_unlocked_day_plan(state)
	return changed


func _can_edit_assignments(state) -> bool:
	return state != null and (not state.has_method("can_edit_day_plan") or state.can_edit_day_plan())


func _is_isolated_in_current_plan(state, survivor_id: String) -> bool:
	return (
		state != null
		and state.current_day_plan != null
		and survivor_id in state.current_day_plan.isolated_survivor_ids
	)


func _refresh_survivor_assignment(state, survivor_id: String, known_assignments: Dictionary = {}) -> void:
	var survivor = state.find_survivor(survivor_id)
	if survivor == null:
		return
	var assignment_id := str(known_assignments.get(survivor_id, ""))
	if assignment_id.is_empty():
		assignment_id = _find_roster_assignment(state, survivor_id)
	if not assignment_id.is_empty() and survivor.is_present_in_settlement():
		survivor.current_assignment = assignment_id
		if survivor.status != SurvivorStateScript.Status.INJURED:
			survivor.status = SurvivorStateScript.Status.WORKING
		return

	survivor.current_assignment = ""
	if survivor.status in [SurvivorStateScript.Status.WORKING, SurvivorStateScript.Status.DIVING]:
		survivor.status = SurvivorStateScript.Status.AVAILABLE


func _find_roster_assignment(state, survivor_id: String) -> String:
	for building in state.buildings:
		if building != null and building.assigned_survivor_ids.has(survivor_id):
			return str(building.id)
	return ""


func _sync_unlocked_day_plan(state) -> void:
	if state.current_day_plan != null and not bool(state.current_day_plan.locked):
		state.current_day_plan.sync_from_state(state)


func _erase_all(values: Array[String], value: String) -> void:
	while values.has(value):
		values.erase(value)
