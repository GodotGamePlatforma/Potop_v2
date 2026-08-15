extends SceneTree

const GameStateScript := preload("res://scripts/data/GameState.gd")
const GameFormatScript := preload("res://scripts/data/GameFormat.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const BuildingSystemScript := preload("res://scripts/base/BuildingSystem.gd")
const WorkerAssignmentSystemScript := preload("res://scripts/base/WorkerAssignmentSystem.gd")
const ExpeditionPreparationSystemScript := preload("res://scripts/base/ExpeditionPreparationSystem.gd")
const EndOfDayResolverScript := preload("res://scripts/base/EndOfDayResolver.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const TutorialDirectorScript := preload("res://scripts/core/TutorialDirector.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const SaveManagerScript := preload("res://scripts/core/SaveManager.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")

const TEST_SAVE := "user://test_tutorial_return_save.tres"
const TEST_PENDING := "user://test_tutorial_return_save.pending.tres"
const TEST_BACKUP := "user://test_tutorial_return_save.backup.tres"

var _failed := false

func _initialize() -> void:
	_remove_test_saves()
	var save_manager = SaveManagerScript.new()
	save_manager.configure_paths(TEST_SAVE, TEST_PENDING, TEST_BACKUP)
	var state = GameStateScript.new()
	state.setup_new_campaign(321, DifficultyProfileScript.new())
	var director = TutorialDirectorScript.new()
	var buildings = BuildingSystemScript.new()
	var assignments = WorkerAssignmentSystemScript.new()

	_assert(state.format_revision == GameFormatScript.CAMPAIGN_FORMAT_REVISION, "Aktywny kontrakt kampanii wymaga bieżącej rewizji formatu.")
	_assert(state.tutorial.step == TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE, "Dzień 1 powinien zacząć się od Domu Wspólnoty.")
	_assert(_build(state, buildings, director, "community_house"), "Pakiet tutorialowy powinien finansować Dom Wspólnoty.")
	_assert(state.tutorial.step == TutorialStateScript.Step.BUILD_DIVING_STATION, "Drugim budynkiem powinna być Stacja.")
	_assert(_build(state, buildings, director, "diving_station"), "Pakiet tutorialowy powinien finansować Stację.")

	var community = state.find_building_by_definition("community_house")
	_assert(assignments.assign_worker(state, "mira", community.id, 1), "Mira powinna móc obsadzić Dom.")
	_assert(director.handle_event(state, TutorialDirectorScript.COMMUNITY_WORKER_ASSIGNED), "Obsada Domu powinna przejść do racji.")
	_assert(director.handle_event(state, TutorialDirectorScript.RATIONS_SELECTED), "Świadomy wybór racji powinien odblokować koniec dnia.")
	_assert(director.handle_event(state, TutorialDirectorScript.FIRST_DAY_ENDED), "Dzień 1 powinien zakończyć się dopiero po wszystkich celach.")
	EndOfDayResolverScript.new().resolve(state, null, false)
	state.current_phase = GamePhaseScript.Phase.BASE_PLANNING
	_assert(state.day == 2 and state.tutorial.step == TutorialStateScript.Step.BUILD_WORKSHOP, "Dzień 2 powinien prowadzić do Warsztatu.")

	_assert(_build(state, buildings, director, "workshop"), "Pakiet tutorialowy powinien finansować Warsztat przed nurkowaniem.")
	var station = state.find_building_by_definition("diving_station")
	var station_definition = ResourceLoader.load("res://data/buildings/diving_station.tres")
	_assert(ExpeditionPreparationSystemScript.new().select_diver(state, station, station_definition, "igor"), "Igor powinien móc zostać wybranym nurkiem niezależnie od obsady Stacji.")
	_assert(director.reconcile_base_progress(state), "Wybór Igora powinien odblokować pierwsze zejście.")
	for event_id in [TutorialDirectorScript.DIVE_STARTED, TutorialDirectorScript.MOVEMENT_COMPLETED, TutorialDirectorScript.OXYGEN_EXPLAINED, TutorialDirectorScript.MANDATORY_CONTAINER_OPENED, TutorialDirectorScript.MANDATORY_LOOT_COMPLETED, TutorialDirectorScript.BLOCKED_PASSAGE_SEEN, TutorialDirectorScript.FIRST_DIVE_COMPLETED]:
		_assert(director.handle_event(state, event_id), "Pierwsza wyprawa powinna przejść krok: %s." % event_id)
	EndOfDayResolverScript.new().resolve(state, null, false)
	_assert(state.current_phase == GamePhaseScript.Phase.END_DAY_REPORT, "Powrót z pierwszej wyprawy powinien zatrzymać się na zapisanym raporcie dnia.")
	_assert(state.settlement_event_roll_day == state.day and state.pressure_state.has_committed_morning() and state.pressure_state.quiet_morning, "Chroniony dzień 3 musi zapisać audyt spokojnego poranka zamiast pozostawić niepełny kandydat autosave.")
	var validation_errors: PackedStringArray = state.persistence_validation_errors()
	_assert(validation_errors.is_empty(), "Kandydat po pierwszym nurkowaniu musi przejść pełną walidację persistence: %s" % "; ".join(validation_errors))
	save_manager.fail_next_save_for_tests(ERR_CANT_CREATE)
	_assert(save_manager.save_game(state) == ERR_CANT_CREATE, "Kontrolowana pierwsza awaria zapisu powinna zachować kandydata do ponowienia.")
	_assert(save_manager.save_game(state) == OK, "Ponowienie tego samego rozliczonego kandydata po pierwszej wyprawie musi zapisać się poprawnie.")
	var reloaded = save_manager.load_game()
	_assert(reloaded != null and reloaded.day == 3 and reloaded.tutorial.step == TutorialStateScript.Step.STAFF_WORKSHOP and reloaded.current_phase == GamePhaseScript.Phase.END_DAY_REPORT, "Roundtrip po ponowieniu musi zachować dzień 3, krok Warsztatu i obowiązkowy raport.")
	state.current_phase = GamePhaseScript.Phase.BASE_PLANNING
	_assert(state.day == 3 and state.tutorial.step == TutorialStateScript.Step.STAFF_WORKSHOP, "Bezpieczny powrót powinien rozpocząć dzień 3 przy Warsztacie.")
	var recovered_result = DiveResultScript.new()
	recovered_result.returned_alive = true
	recovered_result.tutorial_completed = true
	state.last_dive_result = recovered_result
	state.tutorial.step = TutorialStateScript.Step.DIVE_OPEN_CONTAINER
	_assert(director.reconcile_base_progress(state), "Dzień 3 z rozliczonym pierwszym nurkowaniem musi naprawić utknięty krok nurkowy.")
	_assert(state.tutorial.step == TutorialStateScript.Step.STAFF_WORKSHOP, "Naprawiony zapis dnia 3 musi prowadzić do obsadzenia Warsztatu.")

	var workshop = state.find_building_by_definition("workshop")
	_assert(assignments.assign_worker(state, "anka", workshop.id, 1), "Anka powinna móc obsadzić Warsztat.")
	_assert(director.handle_event(state, TutorialDirectorScript.WORKSHOP_WORKER_ASSIGNED), "Obsada Warsztatu powinna odblokować Nóż.")
	state.resources.add_amount(ResourceIdsScript.SCRAP, 3)
	state.resources.add_amount(ResourceIdsScript.FABRIC_RUBBER, 2)
	_assert(director.craft_rescue_knife(state), "Obowiązkowy łup powinien finansować natychmiastowy Nóż.")
	_assert(state.story_flags.rescue_knife_unlocked and state.tutorial.step == TutorialStateScript.Step.START_FINAL_DIVE, "Nóż powinien być trwały i odblokować finałowe zejście.")
	_assert(director.handle_event(state, TutorialDirectorScript.DIVE_STARTED), "Finałowe zejście powinno prowadzić do J-7.")
	_assert(director.handle_event(state, TutorialDirectorScript.JUNCTION_J7_ACTIVATED), "Aktywacja J-7 powinna wymagać normalnego powrotu.")
	_assert(director.handle_event(state, TutorialDirectorScript.FINAL_DIVE_COMPLETED), "Bezpieczny finałowy powrót powinien zakończyć tutorial.")
	_assert(not state.tutorial.is_active(), "Po trzech dniach samouczek nie może blokować swobodnej gry.")
	_remove_test_saves()
	reloaded = null
	state = null
	save_manager.free()

	if _failed:
		quit(1)
		return
	print("Tutorial flow test passed: three guided days, guaranteed economy, rescue knife and J-7 return.")
	quit(0)

func _build(state, system, director, definition_id: String) -> bool:
	var definition = ResourceLoader.load("res://data/buildings/%s.tres" % definition_id)
	var slot_id := ""
	for candidate in state.platform.slot_states:
		if str(state.platform.slot_states[candidate].get("definition_id", "")) == definition_id:
			slot_id = str(candidate)
			break
	return not slot_id.is_empty() and system.queue_construction(state, slot_id, definition) and director.handle_event(state, TutorialDirectorScript.BUILDING_COMPLETED, definition_id)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Tutorial flow test failed: " + message)


func _remove_test_saves() -> void:
	for path in [TEST_SAVE, TEST_PENDING, TEST_BACKUP]:
		var absolute_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute_path):
			DirAccess.remove_absolute(absolute_path)
