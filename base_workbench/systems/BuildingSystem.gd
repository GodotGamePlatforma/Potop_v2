class_name BuildingSystem
extends RefCounted

const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const DifficultyMathScript := preload("res://scripts/core/DifficultyMath.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const TutorialDirectorScript := preload("res://scripts/core/TutorialDirector.gd")

func get_building_for_slot(state, slot_id: String):
	if state == null or state.platform == null:
		return null
	var slot_data: Dictionary = state.platform.slot_states.get(slot_id, {})
	var building_id := str(slot_data.get("building_id", ""))
	return state.find_building(building_id) if not building_id.is_empty() else null

func get_build_cost(state, definition) -> Dictionary:
	return _scaled_cost(state, definition.get_build_cost() if definition != null else {})

func get_upgrade_cost(state, definition, current_level: int) -> Dictionary:
	return _scaled_cost(state, definition.get_upgrade_cost(current_level) if definition != null else {})

func can_afford(state, cost: Dictionary) -> bool:
	if state == null or state.resources == null:
		return false
	for resource_id in cost.keys():
		if state.resources.get_amount(str(resource_id)) < int(cost[resource_id]):
			return false
	return true


func construction_blocker(state, slot_id: String, definition) -> String:
	if state == null:
		return "Brak aktywnego stanu kampanii."
	if definition == null:
		return "Brak definicji budynku."
	if state.platform == null:
		return "Brak stanu platformy."
	if state.resources == null:
		return "Brak stanu magazynu."
	if state.has_method("day_plan_edit_blocker"):
		var plan_blocker := str(state.day_plan_edit_blocker())
		if not plan_blocker.is_empty():
			return plan_blocker
	elif state.has_method("can_edit_day_plan") and not state.can_edit_day_plan():
		return "Plan dnia jest już zablokowany."
	var tutorial_blocker := TutorialDirectorScript.new().construction_blocker(state, str(definition.id))
	if not tutorial_blocker.is_empty():
		return tutorial_blocker
	var slot_data: Dictionary = state.platform.slot_states.get(slot_id, {})
	if slot_data.is_empty():
		return "Wybrany slot platformy nie istnieje."
	if not str(slot_data.get("building_id", "")).is_empty():
		return "Ten slot jest już zajęty przez budynek."
	if str(slot_data.get("definition_id", "")) != str(definition.id):
		return "Ten budynek nie pasuje do wybranego slotu."
	if bool(definition.requires_edge) and not bool(slot_data.get("is_edge", false)):
		return "Ten budynek wymaga slotu na krawędzi platformy."
	var cost := get_build_cost(state, definition)
	if cost.is_empty():
		return "Brak poprawnego kosztu odbudowy."
	return _cost_shortfall_blocker(state, cost)


func upgrade_blocker(state, building, definition) -> String:
	if state == null:
		return "Brak aktywnego stanu kampanii."
	if building == null or definition == null:
		return "Brak danych budynku lub jego definicji."
	if state.resources == null:
		return "Brak stanu magazynu."
	if state.has_method("day_plan_edit_blocker"):
		var plan_blocker := str(state.day_plan_edit_blocker())
		if not plan_blocker.is_empty():
			return plan_blocker
	elif state.has_method("can_edit_day_plan") and not state.can_edit_day_plan():
		return "Plan dnia jest już zablokowany."
	if not bool(building.is_built):
		return "Najpierw ukończ odbudowę budynku."
	if int(building.pending_level) > int(building.level):
		return "Rozbudowa tego budynku jest już zaplanowana na koniec dnia."
	if int(building.level) >= int(definition.max_level):
		return "Budynek osiągnął maksymalny poziom."
	var cost := get_upgrade_cost(state, definition, int(building.level))
	if cost.is_empty():
		return "Brak poprawnego kosztu następnego poziomu."
	return _cost_shortfall_blocker(state, cost)


func queue_construction(state, slot_id: String, definition) -> bool:
	if not construction_blocker(state, slot_id, definition).is_empty():
		return false
	var slot_data: Dictionary = state.platform.slot_states.get(slot_id, {})
	var cost := get_build_cost(state, definition)
	if not _spend_cost(state, cost):
		return false

	var building = BuildingStateScript.new()
	building.id = "building_%s" % definition.id
	building.definition_id = definition.id
	building.slot_id = slot_id
	building.level = 1
	building.condition = 100
	building.construction_progress = 100
	building.is_built = true
	state.buildings.append(building)

	slot_data["building_id"] = building.id
	state.platform.slot_states[slot_id] = slot_data
	return true

func queue_upgrade(state, building, definition) -> bool:
	if not upgrade_blocker(state, building, definition).is_empty():
		return false

	var cost := get_upgrade_cost(state, definition, building.level)
	if not _spend_cost(state, cost):
		return false
	building.level += 1
	building.pending_level = 0
	building.construction_progress = 100
	return true

func _spend_cost(state, cost: Dictionary) -> bool:
	if not can_afford(state, cost):
		return false
	for resource_id in cost.keys():
		state.resources.spend(str(resource_id), int(cost[resource_id]))
	return true


func _cost_shortfall_blocker(state, cost: Dictionary) -> String:
	var shortfalls: Array[String] = []
	for raw_resource_id in cost.keys():
		var resource_id := str(raw_resource_id)
		var missing: int = int(cost[raw_resource_id]) - int(state.resources.get_amount(resource_id))
		if missing > 0:
			shortfalls.append("%s: brakuje %d" % [ResourceIdsScript.display_name(resource_id), missing])
	return "Brak materiałów — %s." % "; ".join(shortfalls) if not shortfalls.is_empty() else ""

func _scaled_cost(state, raw_cost: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var multiplier := 1.0
	if state != null and state.difficulty_profile != null:
		multiplier = state.difficulty_profile.build_cost_multiplier
	result = DifficultyMathScript.scale_cost(raw_cost, multiplier)
	var normalized: Dictionary = {}
	for resource_id in result.keys():
		normalized[str(resource_id)] = int(result[resource_id])
	return normalized
