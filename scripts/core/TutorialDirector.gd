class_name TutorialDirector
extends RefCounted

const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const DifficultyMathScript := preload("res://scripts/core/DifficultyMath.gd")

const BUILDING_COMPLETED := "building_completed"
const COMMUNITY_WORKER_ASSIGNED := "community_worker_assigned"
const RATIONS_SELECTED := "rations_selected"
const FIRST_DAY_ENDED := "first_day_ended"
const IGOR_ASSIGNED := "igor_assigned"
const DIVE_STARTED := "dive_started"
const MOVEMENT_COMPLETED := "movement_completed"
const OXYGEN_EXPLAINED := "oxygen_explained"
const MANDATORY_CONTAINER_OPENED := "mandatory_container_opened"
const MANDATORY_LOOT_COMPLETED := "mandatory_loot_completed"
const BLOCKED_PASSAGE_SEEN := "blocked_passage_seen"
const FIRST_DIVE_COMPLETED := "first_dive_completed"
const WORKSHOP_WORKER_ASSIGNED := "workshop_worker_assigned"
const RESCUE_KNIFE_CRAFTED := "rescue_knife_crafted"
const JUNCTION_J7_ACTIVATED := "junction_j7_activated"
const FINAL_DIVE_COMPLETED := "final_dive_completed"

const RESCUE_KNIFE_COST := {"scrap": 3, "fabric_rubber": 2}
const FIRST_DIVE_SUPPORT_LOOT := {"food": 1, "planks": 1}
const REQUIRED_BUILDINGS := ["community_house", "diving_station", "workshop"]
const DIVE_SESSION_EVENTS := [
	DIVE_STARTED,
	MOVEMENT_COMPLETED,
	OXYGEN_EXPLAINED,
	MANDATORY_CONTAINER_OPENED,
	MANDATORY_LOOT_COMPLETED,
	BLOCKED_PASSAGE_SEEN,
	JUNCTION_J7_ACTIVATED,
]

func apply_starting_supply_package(state) -> void:
	if state == null or state.resources == null:
		return
	var multiplier := float(state.difficulty_profile.build_cost_multiplier) if state.difficulty_profile != null else 1.0
	var required: Dictionary = {}
	for definition_id in REQUIRED_BUILDINGS:
		var definition = ResourceLoader.load("res://base_workbench/data/buildings/%s.tres" % definition_id)
		if definition == null:
			continue
		var cost: Dictionary = DifficultyMathScript.scale_cost(definition.get_build_cost(), multiplier)
		for resource_id in cost:
			required[str(resource_id)] = int(required.get(str(resource_id), 0)) + int(cost[resource_id])
	for resource_id in required:
		state.resources.set_amount(str(resource_id), maxi(state.resources.get_amount(str(resource_id)), int(required[resource_id])))

func construction_blocker(state, definition_id: String) -> String:
	if state == null or state.tutorial == null or not state.tutorial.is_active():
		return ""
	var expected := ""
	match int(state.tutorial.step):
		TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE:
			expected = "community_house"
		TutorialStateScript.Step.BUILD_DIVING_STATION:
			expected = "diving_station"
		TutorialStateScript.Step.BUILD_WORKSHOP:
			expected = "workshop"
		_:
			return "Najpierw wykonaj bieżący krok samouczka."
	return "" if definition_id == expected else "Samouczek prowadzi teraz do innego budynku."

func handle_event(state, event_id: String, payload: String = "") -> bool:
	if state == null or state.tutorial == null or not state.tutorial.is_active():
		return false
	return handle_tutorial_event(state.tutorial, event_id, payload)


func handle_tutorial_event(tutorial, event_id: String, payload: String = "") -> bool:
	if tutorial == null or not tutorial.is_active():
		return false
	match event_id:
		BUILDING_COMPLETED:
			if payload == "community_house":
				return tutorial.advance(TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE, TutorialStateScript.Step.BUILD_DIVING_STATION)
			if payload == "diving_station":
				return tutorial.advance(TutorialStateScript.Step.BUILD_DIVING_STATION, TutorialStateScript.Step.ASSIGN_COMMUNITY_WORKER)
			if payload == "workshop":
				return tutorial.advance(TutorialStateScript.Step.BUILD_WORKSHOP, TutorialStateScript.Step.ASSIGN_DIVER_FIRST)
		COMMUNITY_WORKER_ASSIGNED:
			return tutorial.advance(TutorialStateScript.Step.ASSIGN_COMMUNITY_WORKER, TutorialStateScript.Step.SET_RATIONS)
		RATIONS_SELECTED:
			return tutorial.advance(TutorialStateScript.Step.SET_RATIONS, TutorialStateScript.Step.END_FIRST_DAY)
		FIRST_DAY_ENDED:
			return tutorial.advance(TutorialStateScript.Step.END_FIRST_DAY, TutorialStateScript.Step.BUILD_WORKSHOP)
		IGOR_ASSIGNED:
			return tutorial.advance(TutorialStateScript.Step.ASSIGN_DIVER_FIRST, TutorialStateScript.Step.START_FIRST_DIVE)
		DIVE_STARTED:
			if tutorial.step == TutorialStateScript.Step.START_FIRST_DIVE:
				return tutorial.advance(TutorialStateScript.Step.START_FIRST_DIVE, TutorialStateScript.Step.DIVE_MOVEMENT)
			if tutorial.step == TutorialStateScript.Step.START_FINAL_DIVE:
				return tutorial.advance(TutorialStateScript.Step.START_FINAL_DIVE, TutorialStateScript.Step.ACTIVATE_JUNCTION_J7)
		MOVEMENT_COMPLETED:
			return tutorial.advance(TutorialStateScript.Step.DIVE_MOVEMENT, TutorialStateScript.Step.DIVE_OXYGEN)
		OXYGEN_EXPLAINED:
			return tutorial.advance(TutorialStateScript.Step.DIVE_OXYGEN, TutorialStateScript.Step.DIVE_OPEN_CONTAINER)
		MANDATORY_CONTAINER_OPENED:
			return tutorial.advance(TutorialStateScript.Step.DIVE_OPEN_CONTAINER, TutorialStateScript.Step.DIVE_INVENTORY)
		MANDATORY_LOOT_COMPLETED:
			return tutorial.advance(TutorialStateScript.Step.DIVE_INVENTORY, TutorialStateScript.Step.DIVE_BLOCKED_PASSAGE)
		BLOCKED_PASSAGE_SEEN:
			return tutorial.advance(TutorialStateScript.Step.DIVE_BLOCKED_PASSAGE, TutorialStateScript.Step.DIVE_RETURN_TO_LINE)
		FIRST_DIVE_COMPLETED:
			return tutorial.advance(TutorialStateScript.Step.DIVE_RETURN_TO_LINE, TutorialStateScript.Step.STAFF_WORKSHOP)
		WORKSHOP_WORKER_ASSIGNED:
			return tutorial.advance(TutorialStateScript.Step.STAFF_WORKSHOP, TutorialStateScript.Step.CRAFT_RESCUE_KNIFE)
		RESCUE_KNIFE_CRAFTED:
			return tutorial.advance(TutorialStateScript.Step.CRAFT_RESCUE_KNIFE, TutorialStateScript.Step.START_FINAL_DIVE)
		JUNCTION_J7_ACTIVATED:
			return tutorial.advance(TutorialStateScript.Step.ACTIVATE_JUNCTION_J7, TutorialStateScript.Step.FINAL_RETURN_TO_LINE)
		FINAL_DIVE_COMPLETED:
			if tutorial.step == TutorialStateScript.Step.FINAL_RETURN_TO_LINE:
				tutorial.complete()
				return true
	return false


func validate_dive_outcome(state, outcome: DiveTutorialOutcome) -> PackedStringArray:
	var errors := PackedStringArray()
	if state == null or state.tutorial == null or not state.tutorial.is_active():
		errors.append("Kampania nie ma aktywnego tutoriala do zatwierdzenia.")
		return errors
	if outcome == null:
		errors.append("Wynik nurkowania nie zawiera rezultatu tutoriala.")
		return errors
	errors.append_array(outcome.validation_errors())
	if int(state.tutorial.step) != outcome.baseline_step:
		errors.append("Bazowy krok tutoriala wyniku nie odpowiada kampanii.")
	if not errors.is_empty():
		return errors

	var projected = state.tutorial.duplicate(true)
	for event_id in outcome.event_ids:
		if event_id not in DIVE_SESSION_EVENTS:
			errors.append("Wynik nurkowania zawiera zdarzenie spoza sesji tutoriala: %s." % event_id)
			return errors
		if not handle_tutorial_event(projected, event_id):
			errors.append("Sekwencja zdarzeń tutoriala nie jest poprawna dla kroku %d: %s." % [int(projected.step), event_id])
			return errors
	if int(projected.step) != outcome.final_step:
		errors.append("Końcowy krok tutoriala nie odpowiada sekwencji zdarzeń wyniku.")
	return errors


func apply_dive_outcome(state, outcome: DiveTutorialOutcome) -> bool:
	if not validate_dive_outcome(state, outcome).is_empty():
		return false
	# Zatwierdzenie następuje jednym przypisaniem dopiero po pełnym odtworzeniu
	# i sprawdzeniu sekwencji na odłączonej kopii kursora.
	state.tutorial.step = outcome.final_step
	return true

func craft_rescue_knife(state) -> bool:
	if state == null or state.tutorial == null or state.tutorial.step != TutorialStateScript.Step.CRAFT_RESCUE_KNIFE:
		return false
	if state.story_flags == null or bool(state.story_flags.rescue_knife_unlocked):
		return false
	for resource_id in RESCUE_KNIFE_COST:
		if state.resources.get_amount(str(resource_id)) < int(RESCUE_KNIFE_COST[resource_id]):
			return false
	for resource_id in RESCUE_KNIFE_COST:
		state.resources.spend(str(resource_id), int(RESCUE_KNIFE_COST[resource_id]))
	state.story_flags.rescue_knife_unlocked = true
	return handle_event(state, RESCUE_KNIFE_CRAFTED)


func has_required_first_dive_loot(carried_items: Dictionary) -> bool:
	for resource_id in FIRST_DIVE_SUPPORT_LOOT:
		if int(carried_items.get(str(resource_id), 0)) < int(FIRST_DIVE_SUPPORT_LOOT[resource_id]):
			return false
	for resource_id in RESCUE_KNIFE_COST:
		if int(carried_items.get(str(resource_id), 0)) < int(RESCUE_KNIFE_COST[resource_id]):
			return false
	return true

func reconcile_base_progress(state) -> bool:
	if state == null or state.tutorial == null or not state.tutorial.is_active():
		return false
	var changed := false
	if _can_recover_completed_first_dive(state):
		state.tutorial.step = TutorialStateScript.Step.STAFF_WORKSHOP
		changed = true
	var community = state.find_building_by_definition("community_house")
	var station = state.find_building_by_definition("diving_station")
	var workshop = state.find_building_by_definition("workshop")
	if state.tutorial.step == TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE and community != null and community.is_active():
		changed = handle_event(state, BUILDING_COMPLETED, "community_house") or changed
	if state.tutorial.step == TutorialStateScript.Step.BUILD_DIVING_STATION and station != null and station.is_active():
		changed = handle_event(state, BUILDING_COMPLETED, "diving_station") or changed
	if state.tutorial.step == TutorialStateScript.Step.ASSIGN_COMMUNITY_WORKER and community != null and not community.assigned_survivor_ids.is_empty():
		changed = handle_event(state, COMMUNITY_WORKER_ASSIGNED) or changed
	if state.tutorial.step == TutorialStateScript.Step.BUILD_WORKSHOP and workshop != null and workshop.is_active():
		changed = handle_event(state, BUILDING_COMPLETED, "workshop") or changed
	if state.tutorial.step == TutorialStateScript.Step.ASSIGN_DIVER_FIRST and state.current_day_plan != null and str(state.current_day_plan.selected_diver_id) == "igor":
		changed = handle_event(state, IGOR_ASSIGNED) or changed
	if state.tutorial.step == TutorialStateScript.Step.STAFF_WORKSHOP and workshop != null and not workshop.assigned_survivor_ids.is_empty():
		changed = handle_event(state, WORKSHOP_WORKER_ASSIGNED) or changed
	if state.tutorial.step == TutorialStateScript.Step.CRAFT_RESCUE_KNIFE and bool(state.story_flags.rescue_knife_unlocked):
		changed = handle_event(state, RESCUE_KNIFE_CRAFTED) or changed
	return changed


func _can_recover_completed_first_dive(state) -> bool:
	if int(state.day) < 3 or state.last_dive_result == null:
		return false
	if not bool(state.last_dive_result.tutorial_completed) or not bool(state.last_dive_result.returned_alive):
		return false
	if state.story_flags == null or bool(state.story_flags.rescue_knife_unlocked):
		return false
	return (
		state.tutorial.step >= TutorialStateScript.Step.DIVE_MOVEMENT
		and state.tutorial.step <= TutorialStateScript.Step.DIVE_RETURN_TO_LINE
	)
