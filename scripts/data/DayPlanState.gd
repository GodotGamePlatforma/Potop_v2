class_name DayPlanState
extends Resource

const PolicyStateScript := preload("res://scripts/data/PolicyState.gd")

@export var day: int = 1
@export var locked: bool = false
@export var ration_policy: int = PolicyStateScript.RationPolicy.FULL
@export var building_work_paces: Dictionary = {}
@export var worker_assignments: Dictionary = {}
@export var building_orders: Array[Dictionary] = []
@export var medical_priority_survivor_ids: Array[String] = []
@export var isolated_survivor_ids: Array[String] = []
@export var selected_diver_id: String = ""
@export var expedition_entry_point: String = ""
@export var expedition_setup: Resource

func begin_for_state(state) -> void:
	locked = false
	# Decyzje medyczne obowiązują wyłącznie przez bieżący dzień. Nie wolno ich
	# przenosić do następnego planu, ale zwykłe sync_from_state() w trakcie dnia
	# musi je zachować (np. po zmianie obsady budynku).
	medical_priority_survivor_ids.clear()
	isolated_survivor_ids.clear()
	selected_diver_id = str(state.preferred_diver_id).strip_edges() if state != null else ""
	expedition_entry_point = ""
	expedition_setup = null
	sync_from_state(state)

func sync_from_state(state) -> void:
	if state == null or locked:
		return
	day = int(state.day)
	if state.active_policies != null:
		ration_policy = int(state.active_policies.ration_policy)
	building_work_paces.clear()
	worker_assignments.clear()
	building_orders.clear()
	for building in state.buildings:
		if building == null:
			continue
		building_work_paces[str(building.id)] = str(building.work_pace)
		worker_assignments[building.id] = building.assigned_survivor_ids.duplicate()
		if not building.is_built:
			building_orders.append({"type": "construction", "building_id": building.id})
		elif building.pending_level > building.level:
			building_orders.append({"type": "upgrade", "building_id": building.id, "target_level": building.pending_level})
		for order in building.queued_production_orders:
			if order == null:
				continue
			building_orders.append({
				"type": "production",
				"building_id": building.id,
				"order_instance_id": str(order.instance_id),
				"recipe_id": str(order.recipe_id),
			})
	_clear_invalid_selected_diver(state)

func lock_for_resolution(state, setup = null) -> bool:
	if locked:
		return false
	sync_from_state(state)
	expedition_setup = setup
	locked = true
	return true

func select_expedition_entry(entry_point_id: String) -> bool:
	if locked or entry_point_id.is_empty():
		return false
	expedition_entry_point = entry_point_id
	return true


func set_selected_diver(survivor_id: String) -> bool:
	if locked:
		return false
	var clean_id := survivor_id.strip_edges()
	if clean_id.is_empty():
		return false
	selected_diver_id = clean_id
	return true


func clear_selected_diver() -> bool:
	if locked:
		return false
	selected_diver_id = ""
	return true

func set_medical_priority(survivor_ids: Array[String]) -> bool:
	if locked:
		return false
	var normalized: Array[String] = []
	for survivor_id in survivor_ids:
		var clean_id := str(survivor_id).strip_edges()
		if clean_id.is_empty() or clean_id in normalized:
			continue
		normalized.append(clean_id)
	medical_priority_survivor_ids = normalized
	return true

func set_survivor_isolated(survivor_id: String, desired: bool) -> bool:
	if locked:
		return false
	var clean_id := survivor_id.strip_edges()
	if clean_id.is_empty():
		return false
	if desired:
		if clean_id not in isolated_survivor_ids:
			isolated_survivor_ids.append(clean_id)
		if selected_diver_id == clean_id:
			selected_diver_id = ""
	else:
		isolated_survivor_ids.erase(clean_id)
	return true


func _clear_invalid_selected_diver(state) -> void:
	if selected_diver_id.is_empty() or state == null:
		return
	var survivor = state.find_survivor(selected_diver_id)
	if (
		survivor == null
		or not survivor.is_present_in_settlement()
		or not survivor.can_dive()
		or not str(survivor.current_assignment).is_empty()
		or selected_diver_id in isolated_survivor_ids
		or _is_assigned_in_roster(state, selected_diver_id)
	):
		selected_diver_id = ""


func _is_assigned_in_roster(state, survivor_id: String) -> bool:
	for building in state.buildings:
		if building != null and survivor_id in building.assigned_survivor_ids:
			return true
	return false
