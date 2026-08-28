extends SceneTree

const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const ReportStateScript := preload("res://scripts/data/ReportState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const WorkerAssignmentSystemScript := preload("res://base_workbench/systems/WorkerAssignmentSystem.gd")
const WorkerAssignmentRailScript := preload("res://base_workbench/ui/WorkerAssignmentRail.gd")
const ExpeditionPreparationSystemScript := preload("res://scripts/diving/ExpeditionPreparationSystem.gd")
const EndOfDayResolverScript := preload("res://scripts/campaign/EndOfDayResolver.gd")
const PolicyStateScript := preload("res://scripts/data/PolicyState.gd")

var _failed := false

func _initialize() -> void:
	_test_atomic_slots_and_plan_sync()
	_test_locked_plan_and_ui()
	_test_living_diver_stays_assigned_next_day()
	_test_dive_death_is_terminal_before_settlement()
	_test_terminal_workers_are_reconciled()
	_test_temporary_incapacity_keeps_roster_without_output()
	if _failed:
		quit(1)
		return
	print("Worker assignment persistence test passed: slots, plan snapshots, return lifecycle and terminal cleanup are consistent.")
	quit(0)


func _test_atomic_slots_and_plan_sync() -> void:
	var state = _state()
	var station = _add_building(state, "station", "diving_station", "bottom_right", 2)
	var fishing_hut = _add_building(state, "fishing", "fishing_hut", "top_left", 1)
	var assignments = WorkerAssignmentSystemScript.new()

	_assert(assignments.assign_worker_to_slot(state, station.id, 0, "igor", 2), "Igor should fill the first Station slot.")
	_assert(assignments.assign_worker_to_slot(state, fishing_hut.id, 0, "mira", 1), "Mira should fill the Fishing Hut slot.")
	_assert(assignments.assign_worker_to_slot(state, station.id, 1, "mira", 2), "Moving Mira into Station slot two should be atomic.")
	_assert(station.assigned_survivor_ids == ["igor", "mira"], "The target roster should preserve compact slot order.")
	_assert(fishing_hut.assigned_survivor_ids.is_empty(), "A moved worker must disappear from the previous building.")
	_assert(state.find_survivor("mira").current_assignment == station.id, "The reverse assignment index should follow the move.")
	_assert(state.current_day_plan.worker_assignments.get(station.id, []) == ["igor", "mira"], "Every successful edit should immediately synchronize the unlocked day plan.")
	_assert(state.current_day_plan.worker_assignments.get(fishing_hut.id, []).is_empty(), "The synchronized plan should also clear the old building.")

	state.find_survivor("anka").fatigue = 95
	var station_before: Array[String] = []
	station_before.assign(station.assigned_survivor_ids)
	var plan_before: Dictionary = state.current_day_plan.worker_assignments.duplicate(true)
	_assert(not assignments.assign_worker_to_slot(state, station.id, 0, "anka", 2), "An incapable candidate should be rejected before any roster mutation.")
	_assert(station.assigned_survivor_ids == station_before and state.current_day_plan.worker_assignments == plan_before, "A rejected replacement must leave both roster and plan unchanged.")

	_assert(assignments.assign_worker_to_slot(state, station.id, 0, "", 2), "Clearing an occupied compact slot should succeed.")
	_assert(station.assigned_survivor_ids == ["mira"], "Clearing a compact slot should close the gap without changing the save schema.")
	_assert(state.find_survivor("igor").current_assignment.is_empty(), "The displaced worker should no longer point at the Station.")
	_assert(state.find_survivor("igor").status == SurvivorStateScript.Status.AVAILABLE, "The displaced healthy worker should become available.")


func _test_locked_plan_and_ui() -> void:
	var state = _state()
	var station = _add_building(state, "station", "diving_station", "bottom_right", 1)
	var assignments = WorkerAssignmentSystemScript.new()
	var definition = ResourceLoader.load("res://base_workbench/data/buildings/diving_station.tres")
	_assert(ExpeditionPreparationSystemScript.new().select_diver(state, station, definition, "mira"), "Mira should be selected independently as the diver before locking.")
	_assert(assignments.assign_worker_to_slot(state, station.id, 0, "igor", 1), "The Station should be staffed before locking.")
	_assert(state.lock_day_plan(), "The day plan should lock for the UI guard test.")
	_assert(not assignments.assign_worker_to_slot(state, station.id, 0, "mira", 1), "The domain system must reject assignment changes after lock.")
	_assert(station.assigned_survivor_ids == ["igor"], "A locked edit must not alter the persistent roster.")

	var rail = WorkerAssignmentRailScript.new()
	get_root().add_child(rail)
	rail.configure(state, definition, station, state.tutorial.step)
	var change_button := rail.find_child("WorkerChangeButton", true, false) as Button
	var worker_effect := rail.find_child("WorkerEffectLabel", true, false) as Label
	_assert(change_button != null and change_button.disabled, "The visible staffing action should be disabled while the day plan is locked.")
	_assert(worker_effect != null and worker_effect.text == "Obsługa Stacji: +5% udźwigu dla wybranego nurka.", "The assigned Station worker should present the exact active carry-support contribution.")
	rail.free()


func _test_living_diver_stays_assigned_next_day() -> void:
	var state = _state()
	var station = _add_building(state, "station", "diving_station", "bottom_right", 1)
	var assignments = WorkerAssignmentSystemScript.new()
	var definition = ResourceLoader.load("res://base_workbench/data/buildings/diving_station.tres")
	_assert(ExpeditionPreparationSystemScript.new().select_diver(state, station, definition, "igor"), "Igor should be selected independently before the expedition.")
	_assert(assignments.assign_worker_to_slot(state, station.id, 0, "mira", 1), "Mira should staff the Station independently from Igor's dive.")
	state.find_survivor("igor").status = SurvivorStateScript.Status.DIVING

	var result = DiveResultScript.new()
	result.diver_id = "igor"
	result.returned_alive = true
	result.diver_dead = false
	result.oxygen_remaining = 37.0
	result.dive_duration = 120.0
	EndOfDayResolverScript.new().resolve(state, result, false)

	var igor = state.find_survivor("igor")
	_assert(state.day == 2, "A resolved expedition should advance to the next day.")
	var mira = state.find_survivor("mira")
	_assert(station.assigned_survivor_ids == ["mira"], "A living diver must not replace the persistent Station support roster after returning.")
	_assert(igor.current_assignment.is_empty() and igor.status == SurvivorStateScript.Status.AVAILABLE, "The returning diver should become available without acquiring a Station assignment.")
	_assert(mira.current_assignment == station.id and mira.status == SurvivorStateScript.Status.WORKING, "The Station support worker and reverse assignment should persist across the expedition.")
	_assert(not state.current_day_plan.locked and state.current_day_plan.worker_assignments.get(station.id, []) == ["mira"] and state.current_day_plan.selected_diver_id == "igor" and state.preferred_diver_id == "igor", "The next unlocked day plan should keep support staffing independent while restoring the living preferred diver.")


func _test_dive_death_is_terminal_before_settlement() -> void:
	var state = _state()
	var station = _add_building(state, "station", "diving_station", "bottom_right", 1, ["mira"])
	_add_building(state, "infirmary", "infirmary", "center", 1, ["anka"])
	var guest = SurvivorStateScript.new()
	guest.id = "guest"
	guest.display_name = "Gość"
	state.survivors.append(guest)
	var igor = state.find_survivor("igor")
	var station_definition = ResourceLoader.load("res://base_workbench/data/buildings/diving_station.tres")
	_assert(ExpeditionPreparationSystemScript.new().select_diver(state, station, station_definition, "igor"), "The fatal-dive fixture should select Igor independently from Station support.")
	igor.health = 40
	igor.hunger = 20
	igor.fatigue = 42
	igor.morale = 44
	igor.injury_states.assign(["suit_breach"])
	state.resources.set_amount(ResourceIdsScript.FOOD, 50)
	state.resources.set_amount(ResourceIdsScript.MEDS_CHEMICALS, 20)
	state.resources.set_amount(ResourceIdsScript.HOPE, 50)
	state.active_policies.ration_policy = PolicyStateScript.RationPolicy.FULL
	state.current_day_plan.ration_policy = PolicyStateScript.RationPolicy.FULL
	_assert(state.lock_day_plan(), "The death-order regression should use the same frozen plan as a completed expedition.")

	var result = DiveResultScript.new()
	result.diver_id = "igor"
	result.returned_alive = false
	result.diver_dead = true
	result.body_location_if_dead = state.underwater_world.blueprint.entry_landmark_id
	var report = ReportStateScript.new()
	var resolver = EndOfDayResolverScript.new()
	resolver._capture_capable_worker_snapshot(state)
	resolver._apply_dive_result(state, result, report)

	_assert(igor.status == SurvivorStateScript.Status.DEAD and igor.health == 0, "A fatal DiveResult must make the diver terminal inside _apply_dive_result().")
	_assert(igor.current_assignment.is_empty() and station.assigned_survivor_ids == ["mira"], "A fatal independent diver must not remove the living Station support worker.")
	_assert(resolver._snapshot_worker_ids(state, station) == ["mira"], "The frozen capable-worker snapshot must retain only the living Station support worker.")

	var medicine_before: int = state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS)
	resolver._resolve_medical_care(state, report)
	_assert(state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS) == medicine_before, "The Infirmary must not spend medicine on a diver already dead underwater.")
	resolver._resolve_rations(state, report)
	_assert(state.resources.get_amount(ResourceIdsScript.FOOD) == 38, "Only the three living residents should consume full rations after a fatal dive.")
	resolver._resolve_hunger(state, report)
	resolver._resolve_fatigue(state, result, report)
	resolver._resolve_hope(state, result, report)
	resolver._resolve_morale(state, report)
	_assert(igor.hunger == 20 and igor.fatigue == 42 and igor.morale == 44, "A fatal diver must receive no hunger, fatigue, or morale settlement after _apply_dive_result().")
	_assert(state.resources.get_amount(ResourceIdsScript.HOPE) == 35 and not _contains_fragment(report.warnings, "Brakuje suchego miejsca"), "Shelter and Hope must count only the three living residents; the dive-death penalty remains the sole negative Hope effect in this fixture.")
	resolver._resolve_deaths(state, result, report)
	_assert(_count_fragment(report.warnings, "zginął podczas wyprawy") == 1, "The late hunger/health death pass must not apply or report the dive death a second time.")


func _test_terminal_workers_are_reconciled() -> void:
	var state = _state()
	var station = _add_building(state, "station", "diving_station", "bottom_right", 1, ["igor"])
	var fishing_hut = _add_building(state, "fishing", "fishing_hut", "top_left", 1, ["mira", "unknown_survivor"])
	var workshop = _add_building(state, "workshop", "workshop", "bottom_left", 1, ["anka"])
	state.find_survivor("mira").status = SurvivorStateScript.Status.DEPARTED
	state.find_survivor("anka").status = SurvivorStateScript.Status.DEPARTED

	var death_result = DiveResultScript.new()
	death_result.diver_id = "igor"
	death_result.diver_dead = true
	EndOfDayResolverScript.new()._apply_dive_result(state, death_result, ReportStateScript.new())

	_assert(station.assigned_survivor_ids.is_empty(), "A dead diver must not remain as invisible Station staff.")
	_assert(fishing_hut.assigned_survivor_ids.is_empty(), "Departed and unknown residents must not reserve Fishing Hut slots.")
	_assert(workshop.assigned_survivor_ids.is_empty(), "A departed resident must not remain as invisible Workshop staff.")
	for survivor_id in ["igor", "mira", "anka"]:
		_assert(state.find_survivor(survivor_id).current_assignment.is_empty(), "Terminal resident %s should have no reverse assignment." % survivor_id)


func _test_temporary_incapacity_keeps_roster_without_output() -> void:
	var state = _state()
	var fishing_hut = _add_building(state, "fishing", "fishing_hut", "top_left", 1)
	var assignments = WorkerAssignmentSystemScript.new()
	_assert(assignments.assign_worker_to_slot(state, fishing_hut.id, 0, "mira", 1), "Mira should be assigned while capable.")
	var mira = state.find_survivor("mira")
	mira.fatigue = 95
	var food_before: int = state.resources.get_amount(ResourceIdsScript.FOOD)
	EndOfDayResolverScript.new()._resolve_fishing(state, ReportStateScript.new())

	_assert(state.resources.get_amount(ResourceIdsScript.FOOD) == food_before, "A temporarily incapable worker must contribute zero production.")
	_assert(fishing_hut.assigned_survivor_ids == ["mira"] and mira.current_assignment == fishing_hut.id, "Temporary incapacity should keep the remembered roster and reverse index.")
	_assert(assignments.reconcile_assignments(state) == false, "Reconciliation should not treat temporary exhaustion as a terminal assignment.")

	var definition = ResourceLoader.load("res://base_workbench/data/buildings/fishing_hut.tres")
	var rail = WorkerAssignmentRailScript.new()
	get_root().add_child(rail)
	rail.configure(state, definition, fishing_hut, state.tutorial.step)
	var worker_effect := rail.find_child("WorkerEffectLabel", true, false) as Label
	var fatigue_blocker := assignments.assignment_role_blocker(state, "mira", fishing_hut.id, 0)
	_assert(fatigue_blocker == "Zmęczenie wynosi co najmniej 90%.", "The domain blocker should state the exact active fatigue threshold.")
	_assert(worker_effect != null and worker_effect.text == "Wkład dzisiaj: 0 — %s" % fatigue_blocker, "An exhausted worker card should present the exact domain blocker and zero contribution.")
	rail.free()


func _contains_fragment(lines: Array[String], fragment: String) -> bool:
	return _count_fragment(lines, fragment) > 0


func _count_fragment(lines: Array[String], fragment: String) -> int:
	var count := 0
	for line in lines:
		if line.contains(fragment):
			count += 1
	return count


func _state():
	var state = GameStateScript.new()
	state.setup_new_campaign(1608, DifficultyProfileScript.new())
	state.tutorial.complete()
	for resource_id in ResourceIdsScript.all():
		state.resources.set_amount(resource_id, 100)
	return state


func _add_building(
	state,
	id: String,
	definition_id: String,
	slot_id: String,
	level: int,
	workers: Array[String] = []
):
	var building = BuildingStateScript.new()
	building.id = id
	building.definition_id = definition_id
	building.slot_id = slot_id
	building.level = level
	building.is_built = true
	building.assigned_survivor_ids.assign(workers)
	state.buildings.append(building)
	for survivor_id in workers:
		var survivor = state.find_survivor(str(survivor_id))
		if survivor != null:
			survivor.current_assignment = id
			survivor.status = SurvivorStateScript.Status.WORKING
	if state.current_day_plan != null and not state.current_day_plan.locked:
		state.current_day_plan.sync_from_state(state)
	return building


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Worker assignment persistence test failed: " + message)
