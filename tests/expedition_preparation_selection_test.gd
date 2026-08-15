extends SceneTree

const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const ExpeditionPreparationSystemScript := preload("res://scripts/base/ExpeditionPreparationSystem.gd")
const WorkerAssignmentSystemScript := preload("res://scripts/base/WorkerAssignmentSystem.gd")
const BuildingEffectSystemScript := preload("res://scripts/base/BuildingEffectSystem.gd")
const DivingStationHudScript := preload("res://scripts/base/DivingStationHud.gd")

const STATION_DEFINITION := preload("res://data/buildings/diving_station.tres")
const SCOUT_TALENT := "nurek_zwiadowca"
const TECHNICIAN_TALENT := "nurek_technik_glebinowy"

var _failed := false


func _initialize() -> void:
	_test_unstaffed_station_and_frozen_setup()
	_test_selection_guards_and_automatic_clearing()
	_test_station_support_uses_the_work_gate()
	_test_candidate_list_delegates_to_the_domain()
	if _failed:
		quit(1)
		return
	print("Expedition preparation selection test passed: independent diver choice, optional Station staffing, frozen carry support and talent snapshots are consistent.")
	quit(0)


func _test_unstaffed_station_and_frozen_setup() -> void:
	var fixture := _fixture()
	var state = fixture.state
	var station = fixture.station
	var preparation = ExpeditionPreparationSystemScript.new()
	var igor = state.find_survivor("igor")
	igor.profession_talent_ids = {"nurek": SCOUT_TALENT}

	_assert(state.current_day_plan.selected_diver_id.is_empty(), "A new day must begin without an implicit diver selection.")
	_assert(preparation.select_diver(state, station, STATION_DEFINITION, "igor"), "A free, present and capable resident should be selectable without staffing the Station.")
	_assert(state.current_day_plan.selected_diver_id == "igor" and station.assigned_survivor_ids.is_empty(), "Selecting a diver must update only DayPlanState, not the Station roster.")
	var analysis := preparation.analyze(state, station, STATION_DEFINITION)
	_assert(bool(analysis.ready), "An active Station with a selected capable diver must be ready even when every Station slot is empty.")
	_assert(not bool(analysis.station_support_assigned) and is_equal_approx(float(analysis.station_staffed_carry_multiplier), 1.0), "An unstaffed Station must preserve the diver's personal carry capacity without an implicit bonus.")
	_assert(is_equal_approx(float(analysis.diver_carry_capacity), float(igor.get_carry_capacity())), "The unstaffed analysis must expose the personal carry capacity as the final value.")

	var setup = preparation.build_setup(state, station, STATION_DEFINITION)
	_assert(setup != null and setup.diver_id == "igor", "The sole setup builder must snapshot the independently selected diver.")
	_assert(is_equal_approx(float(setup.station_staffed_carry_multiplier), 1.0) and is_equal_approx(float(setup.diver_carry_capacity), float(igor.get_carry_capacity())), "The setup must freeze the unstaffed multiplier and resulting carry capacity.")
	_assert(setup.profession_talent_ids == {"nurek": SCOUT_TALENT}, "The setup must snapshot the selected diver's profession talent map.")
	igor.profession_talent_ids["nurek"] = TECHNICIAN_TALENT
	_assert(setup.profession_talent_ids == {"nurek": SCOUT_TALENT}, "Changing the survivor after setup creation must not mutate the frozen talent map.")

	_assert(preparation.clear_selected_diver(state), "An editable plan must allow the diver selection to be cleared explicitly.")
	_assert(state.current_day_plan.selected_diver_id.is_empty(), "Clearing the selection must leave no fallback diver in the plan.")
	_assert(preparation.select_diver(state, station, STATION_DEFINITION, "igor"), "The same valid diver should be selectable again after an explicit clear.")
	state.begin_new_day_plan()
	_assert(state.current_day_plan.selected_diver_id.is_empty(), "Beginning a new day must reset the previous day's diver choice.")


func _test_selection_guards_and_automatic_clearing() -> void:
	var fixture := _fixture()
	var state = fixture.state
	var station = fixture.station
	var preparation = ExpeditionPreparationSystemScript.new()
	var assignments = WorkerAssignmentSystemScript.new()

	_assert(assignments.assign_worker_to_slot(state, station.id, 0, "mira", 1), "The guard fixture must assign Mira as ordinary Station support.")
	var assigned_blocker := preparation.diver_selection_blocker(state, station, STATION_DEFINITION, "mira")
	_assert(not assigned_blocker.is_empty() and not preparation.select_diver(state, station, STATION_DEFINITION, "mira"), "A resident assigned to any building must not also be selectable as the diver.")

	var anka = state.find_survivor("anka")
	anka.fatigue = 85
	var fatigue_blocker := preparation.diver_selection_blocker(state, station, STATION_DEFINITION, "anka")
	_assert(anka.can_work() and not anka.can_dive(), "The threshold fixture must remain work-capable while failing dive readiness.")
	_assert(fatigue_blocker == anka.dive_blocker() and not preparation.select_diver(state, station, STATION_DEFINITION, "anka"), "The diver selector must expose the exact central dive blocker at the 85% fatigue boundary.")

	_assert(preparation.select_diver(state, station, STATION_DEFINITION, "igor"), "Igor must remain selectable while a different resident staffs the Station.")
	_assert(state.current_day_plan.set_survivor_isolated("igor", true), "The editable plan must accept an isolation intent.")
	_assert(state.current_day_plan.selected_diver_id.is_empty(), "Planning isolation for the selected diver must clear the choice atomically.")
	_assert(state.current_day_plan.set_survivor_isolated("igor", false), "The fixture must be able to end the isolation intent before continuing.")

	_assert(preparation.select_diver(state, station, STATION_DEFINITION, "igor"), "Igor must be selectable again after isolation is removed.")
	_assert(assignments.assign_worker_to_slot(state, station.id, 0, "igor", 1), "Assigning the selected diver to a building should remain an ordinary valid work command.")
	_assert(state.current_day_plan.selected_diver_id.is_empty(), "A successful building assignment must synchronize the plan and clear the conflicting diver selection.")

	_assert(assignments.assign_worker_to_slot(state, station.id, 0, "", 1), "The fixture must release Igor from Station work before the lock test.")
	_assert(preparation.select_diver(state, station, STATION_DEFINITION, "igor"), "Igor must be selectable before locking the plan.")
	_assert(state.lock_day_plan(), "The fixture must lock the day plan.")
	_assert(not preparation.clear_selected_diver(state), "A locked day plan must reject clearing the selected diver.")
	_assert(not preparation.select_diver(state, station, STATION_DEFINITION, "anka"), "A locked day plan must reject replacing the selected diver.")
	_assert(state.current_day_plan.selected_diver_id == "igor", "Rejected locked edits must preserve the frozen selection.")


func _test_station_support_uses_the_work_gate() -> void:
	var fixture := _fixture()
	var state = fixture.state
	var station = fixture.station
	var preparation = ExpeditionPreparationSystemScript.new()
	var assignments = WorkerAssignmentSystemScript.new()
	var effects = BuildingEffectSystemScript.new()
	var anka = state.find_survivor("anka")
	anka.fatigue = 85

	_assert(assignments.assign_worker_to_slot(state, station.id, 0, "anka", 1), "A resident at 85% fatigue must be accepted as ordinary Station support because the work gate still passes.")
	_assert(effects.worker_is_capable(state, STATION_DEFINITION, station, 0, anka), "Station slot zero must use the ordinary work gate, not dive readiness.")
	_assert(preparation.select_diver(state, station, STATION_DEFINITION, "igor"), "The independent diver must remain selectable beside staffed Station support.")
	var analysis := preparation.analyze(state, station, STATION_DEFINITION)
	var personal_carry := float(state.find_survivor("igor").get_carry_capacity())
	_assert(bool(analysis.ready) and bool(analysis.station_support_assigned), "A capable first Station worker must activate support without becoming the diver.")
	_assert(is_equal_approx(float(analysis.station_staffed_carry_multiplier), 1.05), "The active Station capability must provide exactly the authored +5% carry multiplier.")
	_assert(is_equal_approx(float(analysis.diver_carry_capacity), personal_carry * 1.05), "The analysis must expose personal carry multiplied exactly once by staffed support.")
	var contribution := effects.worker_contribution_line(state, STATION_DEFINITION, station, 0, anka)
	_assert(contribution.contains("Obsługa Stacji") and contribution.contains("+5%") and not contribution.contains("Nurek:"), "The slot-zero contribution must describe support and contain no legacy diver-role assumption.")
	var setup = preparation.build_setup(state, station, STATION_DEFINITION)
	_assert(setup != null and is_equal_approx(float(setup.station_staffed_carry_multiplier), 1.05) and is_equal_approx(float(setup.diver_carry_capacity), personal_carry * 1.05), "The setup must freeze both the support multiplier and final carry result.")
	anka.fatigue = 95
	var blocked_analysis := preparation.analyze(state, station, STATION_DEFINITION)
	_assert(not bool(blocked_analysis.station_support_assigned) and is_equal_approx(float(blocked_analysis.station_staffed_carry_multiplier), 1.0), "Support must disappear when the first Station worker no longer passes the ordinary work gate.")
	_assert(is_equal_approx(float(setup.station_staffed_carry_multiplier), 1.05) and is_equal_approx(float(setup.diver_carry_capacity), personal_carry * 1.05), "Later roster incapacity must not alter the already frozen setup.")


func _test_candidate_list_delegates_to_the_domain() -> void:
	var fixture := _fixture()
	var state = fixture.state
	var station = fixture.station
	var preparation = ExpeditionPreparationSystemScript.new()
	state.find_survivor("anka").fatigue = 85
	_assert(preparation.select_diver(state, station, STATION_DEFINITION, "igor"), "The UI fixture requires an existing selected diver.")
	var hud = DivingStationHudScript.new()
	root.add_child(hud)
	hud.configure(state, STATION_DEFINITION, station, null, int(state.tutorial.step), false)
	var igor_button := hud.find_child("DiverCandidate_igor", true, false) as Button
	var anka_button := hud.find_child("DiverCandidate_anka", true, false) as Button
	var clear_button := hud.find_child("DiverSelectionClear", true, false) as Button
	_assert(igor_button != null and igor_button.text.contains("WYBRANY") and not igor_button.disabled, "The persistent candidate list must visibly bind the current selected diver.")
	_assert(anka_button != null and anka_button.disabled and anka_button.tooltip_text == state.find_survivor("anka").dive_blocker(), "An incapable candidate tile must expose the exact domain blocker.")
	_assert(clear_button != null and not clear_button.disabled, "An editable selected diver must expose a clear command.")
	var emitted_ids: Array[String] = []
	hud.diver_selected.connect(func(survivor_id: String) -> void:
		emitted_ids.append(survivor_id)
	)
	clear_button.pressed.emit()
	_assert(emitted_ids == [""], "The UI clear command must delegate an empty selection without mutating its own copy of plan state.")
	_assert(state.current_day_plan.selected_diver_id == "igor", "DivingStationHud must remain a presentation layer until its emitted command is handled.")
	hud.free()


func _fixture() -> Dictionary:
	var state = GameStateScript.new()
	state.setup_new_campaign(27051, DifficultyProfileScript.new())
	state.tutorial.complete()
	var station = BuildingStateScript.new()
	station.id = "test_diving_station"
	station.definition_id = "diving_station"
	station.slot_id = "bottom_right"
	station.level = 1
	station.is_built = true
	state.buildings.append(station)
	state.current_day_plan.sync_from_state(state)
	return {"state": state, "station": station}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Expedition preparation selection test failed: " + message)
