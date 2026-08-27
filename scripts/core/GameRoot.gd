extends Node

const BASE_SCENE := preload("res://scenes/base/BaseScene.tscn")
const DIVE_SCENE := preload("res://scenes/diving/DiveScene.tscn")
const MAIN_MENU_SCENE := preload("res://scenes/main/MainMenu.tscn")
const INTRO_SCENE := preload("res://scenes/main/IntroScene.tscn")
const GAME_OVER_SCENE := preload("res://scenes/main/GameOverScene.tscn")
const ENDING_SCENE := preload("res://scenes/main/EndingScene.tscn")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const DayCycleControllerScript := preload("res://scripts/core/DayCycleController.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const SceneFlowScript := preload("res://scripts/core/SceneFlow.gd")
const TutorialDirectorScript := preload("res://scripts/core/TutorialDirector.gd")
const CampaignProgressionSystemScript := preload("res://scripts/base/CampaignProgressionSystem.gd")
const SettlementEventSystemScript := preload("res://scripts/base/SettlementEventSystem.gd")
const MissionSystemScript := preload("res://scripts/base/MissionSystem.gd")
const UserSettingsScript := preload("res://scripts/core/UserSettings.gd")
const NarrativeContentScript := preload("res://scripts/ui/NarrativeContent.gd")
const NarrativeSpeakerResolverScript := preload("res://scripts/ui/NarrativeSpeakerResolver.gd")
const NEW_CAMPAIGN_IN_DOUBT_TEXT := "Nie udało się jednoznacznie ustalić wyniku zapisu nowej kampanii. KONTYNUUJ zostało wyłączone; ponów NOWĄ GRĘ, aby bezpiecznie uzgodnić zapis."

enum NewCampaignFailure {
	NONE,
	GAME_DATA,
	PROFILE,
	MAP_SETUP,
	CANDIDATE_VALIDATION,
	PERSISTENCE,
	PERSISTENCE_IN_DOUBT,
}

@onready var scene_mount: Node = $SceneMount
@onready var narrative_dialogue_panel: NarrativeDialoguePanel = $NarrativeLayer/NarrativeDialoguePanel
@onready var pause_menu: PauseMenu = $PauseLayer/PauseMenu
@onready var pause_settings_menu: SettingsMenu = $PauseSettingsLayer/SettingsMenu

var game_state
var current_scene: Node
var campaign_persistence_enabled: bool = true
var user_settings = UserSettingsScript.new()
var _tutorial_director = TutorialDirectorScript.new()
var _settlement_event_system = SettlementEventSystemScript.new()
var _mission_system = MissionSystemScript.new()
var _paused_by_pause_menu: bool = false
var _seen_narrative_keys: Dictionary = {}
var _narrative_sync_queued: bool = false
var _narrative_previous_focus: Control
var last_new_campaign_failure: int = NewCampaignFailure.NONE
var last_new_campaign_failure_details: PackedStringArray = PackedStringArray()
var _last_new_campaign_had_previous_save: bool = false
var _next_new_campaign_map_compiler_for_tests

func _ready() -> void:
	narrative_dialogue_panel.dismissed.connect(_on_narrative_dismissed)
	narrative_dialogue_panel.cue_activity_changed.connect(_on_narrative_cue_activity_changed)
	pause_menu.continue_requested.connect(_close_pause_menu)
	pause_menu.save_requested.connect(_on_pause_save_requested)
	pause_menu.settings_requested.connect(_on_pause_settings_requested)
	pause_menu.main_menu_requested.connect(_on_pause_main_menu_requested)
	pause_menu.quit_requested.connect(_on_pause_quit_requested)
	pause_settings_menu.closed.connect(_on_pause_settings_closed)
	user_settings.settings_applied.connect(_on_user_settings_applied)
	user_settings.initialize(get_tree(), _should_load_user_settings_from_disk())
	GameDatabase.load_definitions()
	show_main_menu()


func _exit_tree() -> void:
	_release_pause_menu_ownership()


func _input(event: InputEvent) -> void:
	if narrative_dialogue_panel != null and narrative_dialogue_panel.is_open():
		if _is_cancel_press(event):
			get_viewport().set_input_as_handled()
		return
	if not _is_cancel_press(event) or pause_menu == null or pause_menu.is_open():
		return
	if not _current_scene_supports_pause_menu():
		return
	if current_scene.has_method("has_cancelable_overlay_open") and bool(current_scene.call("has_cancelable_overlay_open")):
		# Istniejący panel zachowuje pierwszeństwo i sam obsługuje ten event w
		# swojej dotychczasowej ścieżce unhandled input.
		return
	get_viewport().set_input_as_handled()
	open_pause_menu()

func start_new_campaign(profile_id: String = "standard", campaign_seed: int = 0, persist_initial_state: bool = true, play_intro: bool = false, _replace_existing_campaign: bool = false) -> bool:
	_begin_new_campaign_attempt()
	if not GameDatabase.is_valid():
		return _fail_new_campaign(NewCampaignFailure.GAME_DATA)
	var profile = GameDatabase.get_difficulty_profile(profile_id)
	if profile == null:
		return _fail_new_campaign(NewCampaignFailure.PROFILE)
	return _start_new_campaign_with_profile(profile, campaign_seed, persist_initial_state, play_intro)


func start_new_campaign_with_profile(profile: Resource, campaign_seed: int = 0, persist_initial_state: bool = true, play_intro: bool = false, _replace_existing_campaign: bool = false) -> bool:
	_begin_new_campaign_attempt()
	if not GameDatabase.is_valid() or profile == null:
		return _fail_new_campaign(NewCampaignFailure.GAME_DATA if not GameDatabase.is_valid() else NewCampaignFailure.PROFILE)
	if not profile.has_method("is_valid") or not profile.is_valid():
		return _fail_new_campaign(NewCampaignFailure.PROFILE)
	return _start_new_campaign_with_profile(profile, campaign_seed, persist_initial_state, play_intro)


func _start_new_campaign_with_profile(profile: Resource, campaign_seed: int, persist_initial_state: bool, play_intro: bool) -> bool:
	var candidate = GameStateScript.new()
	var map_compiler = _next_new_campaign_map_compiler_for_tests
	_next_new_campaign_map_compiler_for_tests = null
	var setup_errors: PackedStringArray = candidate.setup_new_campaign(campaign_seed, profile, map_compiler)
	if not setup_errors.is_empty():
		return _fail_new_campaign(NewCampaignFailure.MAP_SETUP, setup_errors)
	if candidate.difficulty_profile == null or not candidate.difficulty_profile.has_method("has_valid_configuration_signature") or not candidate.difficulty_profile.has_valid_configuration_signature():
		return _fail_new_campaign(
			NewCampaignFailure.CANDIDATE_VALIDATION,
			PackedStringArray(["Snapshot profilu trudności nie ma poprawnej pieczęci konfiguracji."])
		)
	var candidate_errors: PackedStringArray = candidate.load_validation_errors()
	if not candidate_errors.is_empty():
		return _fail_new_campaign(NewCampaignFailure.CANDIDATE_VALIDATION, candidate_errors)
	if persist_initial_state:
		# Every persisted GameState created as a new campaign uses the same
		# replacement transaction. The retained fifth public argument is only
		# source compatibility for existing callers; it can no longer bypass the
		# safe path by keeping its historical default value.
		var save_error := SaveManager.replace_campaign(candidate)
		if save_error != OK:
			var persistence_details: PackedStringArray = SaveManager.last_replacement_failure_details.duplicate()
			persistence_details.append("%s (%d)" % [error_string(save_error), save_error])
			var persistence_failure := (
				NewCampaignFailure.PERSISTENCE_IN_DOUBT
				if SaveManager.last_replacement_outcome == SaveManager.CampaignReplacementOutcome.IN_DOUBT
				else NewCampaignFailure.PERSISTENCE
			)
			return _fail_new_campaign(persistence_failure, persistence_details)
		# The transaction hands off the exact canonical object that it committed.
		# A second disk read here would introduce a new failure boundary after the
		# old campaign may already be irreversibly replaced.
		var committed_candidate = SaveManager.take_last_replacement_committed_state()
		if committed_candidate != null:
			candidate = committed_candidate
		else:
			# This is an internal contract breach, not a reversible persistence
			# failure: replace_campaign() already returned a committed result. Never
			# claim that the old campaign survived after that point.
			push_warning("SaveManager zatwierdził kampanię bez kanonicznego handoffu; runtime użyje zwalidowanego kandydata wejściowego.")
	_reset_narrative_session()
	campaign_persistence_enabled = persist_initial_state
	game_state = candidate
	_clear_new_campaign_failure()
	if play_intro:
		show_intro()
	else:
		show_base()
	return true


func last_new_campaign_failure_text() -> String:
	if has_unresolved_campaign_replacement():
		return NEW_CAMPAIGN_IN_DOUBT_TEXT
	if last_new_campaign_failure == NewCampaignFailure.NONE:
		return ""
	if last_new_campaign_failure == NewCampaignFailure.PERSISTENCE_IN_DOUBT:
		return NEW_CAMPAIGN_IN_DOUBT_TEXT
	var reason := "wystąpił nieznany błąd"
	match last_new_campaign_failure:
		NewCampaignFailure.GAME_DATA:
			reason = "dane gry są niekompletne lub uszkodzone"
		NewCampaignFailure.PROFILE:
			reason = "wybrany poziom trudności jest nieprawidłowy"
		NewCampaignFailure.MAP_SETUP:
			reason = "dane mapy są nieaktualne lub niespójne"
		NewCampaignFailure.CANDIDATE_VALIDATION:
			reason = "stan startowy nie przeszedł kontroli poprawności"
		NewCampaignFailure.PERSISTENCE:
			reason = "nie udało się bezpiecznie zapisać zmian"
	var suffix := (
		"Dotychczasowa kampania pozostała bez zmian."
		if _last_new_campaign_had_previous_save
		else "Nie utworzono kampanii."
	)
	return "Nie udało się rozpocząć nowej kampanii: %s. %s" % [reason, suffix]


func use_next_new_campaign_map_compiler_for_tests(map_compiler) -> void:
	_next_new_campaign_map_compiler_for_tests = map_compiler


func _begin_new_campaign_attempt() -> void:
	_clear_new_campaign_failure()
	_last_new_campaign_had_previous_save = SaveManager.has_save()


func _clear_new_campaign_failure() -> void:
	last_new_campaign_failure = NewCampaignFailure.NONE
	last_new_campaign_failure_details = PackedStringArray()


func _fail_new_campaign(failure: int, details: PackedStringArray = PackedStringArray()) -> bool:
	# A durable replacement guard outranks the local preflight category. This can
	# happen when a retry after restart fails before reaching SaveManager (for
	# example because the map becomes invalid). The exact local cause remains in
	# diagnostics, but the player must still see the fail-closed disk-state truth.
	last_new_campaign_failure = (
		NewCampaignFailure.PERSISTENCE_IN_DOUBT
		if SaveManager.has_unresolved_campaign_replacement()
		else failure
	)
	last_new_campaign_failure_details = details.duplicate()
	return false

func continue_campaign() -> bool:
	if not GameDatabase.is_valid():
		return false
	if not SaveManager.has_save():
		return false
	var loaded = SaveManager.load_game()
	if loaded == null:
		return false
	game_state = loaded
	_reset_narrative_session()
	campaign_persistence_enabled = true
	reconcile_missions()
	_route_current_phase()
	return true

func has_saved_campaign() -> bool:
	return SaveManager.has_save()


func has_unresolved_campaign_replacement() -> bool:
	return SaveManager.has_unresolved_campaign_replacement()


func has_campaign_storage_for_new_campaign() -> bool:
	return SaveManager.has_any_save_file()


func open_pause_menu() -> bool:
	if pause_menu == null or pause_menu.is_open() or (narrative_dialogue_panel != null and narrative_dialogue_panel.is_open()) or not _current_scene_supports_pause_menu():
		return false
	var tree := get_tree()
	_paused_by_pause_menu = not tree.paused
	if _paused_by_pause_menu:
		tree.paused = true
	pause_menu.open_menu(
		_pause_context_text(),
		manual_save_blocker(),
		_pause_exit_note(),
		_pause_main_menu_note()
	)
	return true


func manual_save_blocker() -> String:
	if game_state == null:
		return "Brak aktywnej kampanii."
	var phase := int(game_state.current_phase)
	match phase:
		GamePhaseScript.Phase.DIVING:
			return "Trwającej wyprawy nie można zapisać. Wróć do Przystani, aby utworzyć bezpieczny zapis."
		GamePhaseScript.Phase.EXPEDITION_SETUP, GamePhaseScript.Phase.DIVE_RESULT, GamePhaseScript.Phase.DAY_RESOLUTION:
			return "Trwa przejście kampanii. Zapis będzie możliwy w następnym bezpiecznym punkcie."
		GamePhaseScript.Phase.MAIN_MENU:
			return "W menu głównym nie ma aktywnego punktu zapisu kampanii."
		GamePhaseScript.Phase.GAME_OVER, GamePhaseScript.Phase.ENDING:
			return "Na tym ekranie zapis ręczny nie jest dostępny."
	if phase not in [
		GamePhaseScript.Phase.DAY_START_REPORT,
		GamePhaseScript.Phase.BASE_PLANNING,
		GamePhaseScript.Phase.END_DAY_REPORT,
		GamePhaseScript.Phase.CRISIS,
	]:
		return "Bieżąca faza nie jest bezpiecznym punktem zapisu."
	if not campaign_persistence_enabled:
		return "Zapis kampanii jest wyłączony w tym trybie uruchomienia."
	if game_state.current_day_plan != null and bool(game_state.current_day_plan.locked):
		return "Zablokowany plan dnia zostanie utrwalony dopiero po zakończeniu rozliczenia."
	if game_state.current_expedition_setup != null:
		return "Trwa przygotowanie wyprawy. Zapis będzie możliwy po powrocie do bezpiecznego punktu."
	return ""


func manual_save() -> Error:
	if not manual_save_blocker().is_empty():
		return ERR_UNAVAILABLE
	return SaveManager.save_game(game_state)


func quit_game_without_save() -> void:
	get_tree().quit(0)

func get_difficulty_names() -> Array[String]:
	var result: Array[String] = []
	for profile in get_difficulty_options():
		result.append(str(profile.profile_name))
	return result


func get_difficulty_options() -> Array:
	return GameDatabase.available_difficulty_profiles()


func get_difficulty_profile(profile_id: String):
	return GameDatabase.get_difficulty_profile(profile_id)

func show_main_menu() -> void:
	if narrative_dialogue_panel != null:
		narrative_dialogue_panel.clear()
	if game_state != null:
		change_phase(GamePhaseScript.Phase.MAIN_MENU)
	_load_scene(MAIN_MENU_SCENE)


func show_intro() -> void:
	if game_state == null:
		show_main_menu()
		return
	_load_scene(INTRO_SCENE)


func finish_intro() -> void:
	if current_scene == null or current_scene.name != "IntroScene":
		return
	show_base()

func change_phase(phase: int) -> void:
	if game_state == null:
		return
	game_state.current_phase = phase

func show_base(preserve_phase: bool = false) -> void:
	if not preserve_phase:
		change_phase(GamePhaseScript.Phase.BASE_PLANNING)
	reconcile_missions()
	_load_scene(BASE_SCENE)

func start_dive(setup) -> void:
	if game_state == null or setup == null:
		return
	if int(game_state.current_phase) not in [GamePhaseScript.Phase.BASE_PLANNING, GamePhaseScript.Phase.CRISIS]:
		return
	var campaign_tutorial_active: bool = game_state.tutorial != null and bool(game_state.tutorial.is_active())
	if campaign_tutorial_active != bool(setup.tutorial_mode):
		push_warning("Odrzucono setup wyprawy z trybem tutoriala niespójnym z kampanią.")
		return
	if campaign_tutorial_active:
		var campaign_tutorial_step := int(game_state.tutorial.step)
		if campaign_tutorial_step not in [
			TutorialStateScript.Step.START_FIRST_DIVE,
			TutorialStateScript.Step.START_FINAL_DIVE,
		]:
			push_warning("Tutorial kampanii nie znajduje się na kroku rozpoczynającym nurkowanie.")
			return
		if int(setup.tutorial_baseline_step) != campaign_tutorial_step:
			push_warning("Setup wyprawy ma nieaktualny bazowy krok tutoriala.")
			return
	if not game_state.lock_day_plan(setup):
		return

	game_state.current_expedition_setup = setup
	var diver = game_state.find_survivor(setup.diver_id)
	if diver != null:
		diver.status = SurvivorStateScript.Status.DIVING
	change_phase(GamePhaseScript.Phase.EXPEDITION_SETUP)
	change_phase(GamePhaseScript.Phase.DIVING)
	_load_scene(DIVE_SCENE)

func finish_dive(result) -> bool:
	if game_state == null or result == null:
		return false
	if int(game_state.current_phase) != GamePhaseScript.Phase.DIVING:
		return false
	if result.get_script() != DiveResultScript:
		push_error("Granica zakończenia nurkowania przyjęła obiekt inny niż DiveResult.")
		return false
	var setup = game_state.current_expedition_setup
	var result_errors: PackedStringArray = result.validation_errors(setup)
	if not result_errors.is_empty():
		push_error("Odrzucono niepoprawny DiveResult: %s" % " | ".join(result_errors))
		return false

	var candidate = game_state.duplicate(true)
	if result.tutorial_completed:
		var tutorial_errors := _tutorial_director.validate_dive_outcome(candidate, result.tutorial_outcome)
		if not tutorial_errors.is_empty():
			push_error("Odrzucono niepoprawny rezultat tutoriala: %s" % " | ".join(tutorial_errors))
			return false
		if not _tutorial_director.apply_dive_outcome(candidate, result.tutorial_outcome):
			return false
		if candidate.tutorial.step == TutorialStateScript.Step.DIVE_RETURN_TO_LINE:
			if not _tutorial_director.handle_event(candidate, TutorialDirectorScript.FIRST_DIVE_COMPLETED):
				return false
		elif candidate.tutorial.step == TutorialStateScript.Step.FINAL_RETURN_TO_LINE:
			if not _tutorial_director.handle_event(candidate, TutorialDirectorScript.FINAL_DIVE_COMPLETED):
				return false
		else:
			return false
	candidate.current_phase = GamePhaseScript.Phase.DIVE_RESULT
	# Wynik tutoriala jest przejściowym wejściem transakcji. W zapisie zostaje
	# wyłącznie zatwierdzony skutek, nie obiekt runtime z sesji nurkowania.
	var persisted_result = result.duplicate(true)
	persisted_result.tutorial_outcome = null
	candidate.last_dive_result = persisted_result
	candidate.current_expedition_setup = null
	candidate.current_phase = GamePhaseScript.Phase.DAY_RESOLUTION
	var report = DayCycleControllerScript.new().resolve_day(candidate, candidate.last_dive_result, false)
	return _commit_resolved_day(candidate, report)

func end_day() -> bool:
	if not end_day_blocker().is_empty():
		return false
	var candidate = game_state.duplicate(true)
	if candidate.tutorial != null and candidate.tutorial.is_active():
		_tutorial_director.handle_event(candidate, TutorialDirectorScript.FIRST_DAY_ENDED)
	if not candidate.lock_day_plan(null):
		return false
	candidate.current_phase = GamePhaseScript.Phase.DAY_RESOLUTION
	var report = DayCycleControllerScript.new().resolve_day(candidate, null, false)
	return _commit_resolved_day(candidate, report)


func end_day_blocker() -> String:
	if game_state == null:
		return "Brak aktywnego stanu kampanii."
	if int(game_state.current_phase) not in [GamePhaseScript.Phase.BASE_PLANNING, GamePhaseScript.Phase.CRISIS]:
		match int(game_state.current_phase):
			GamePhaseScript.Phase.END_DAY_REPORT:
				return "Najpierw potwierdź obowiązkowe podsumowanie zakończonego dnia."
			GamePhaseScript.Phase.DAY_START_REPORT:
				return "Najpierw rozstrzygnij wydarzenie poranka."
			GamePhaseScript.Phase.DAY_RESOLUTION:
				return "Trwa rozliczanie bieżącego dnia."
			GamePhaseScript.Phase.GAME_OVER:
				return "Kampania jest zakończona porażką."
			GamePhaseScript.Phase.ENDING:
				return "Najpierw zakończ bieżące podsumowanie kampanii."
		return "Dzień można zakończyć wyłącznie podczas planowania w bazie lub kryzysu."
	if game_state.tutorial != null and game_state.tutorial.is_active() and int(game_state.tutorial.step) != TutorialStateScript.Step.END_FIRST_DAY:
		return "Najpierw wykonaj bieżący krok samouczka."
	if game_state.has_method("day_plan_edit_blocker"):
		return str(game_state.day_plan_edit_blocker())
	return "" if game_state.can_edit_day_plan() else "Plan dnia jest już zablokowany."


func _commit_resolved_day(candidate, report) -> bool:
	if candidate == null or report == null:
		return false
	if campaign_persistence_enabled:
		var save_error := SaveManager.save_game(candidate)
		if save_error != OK:
			push_warning("Nie udało się zapisać rozliczenia dnia. Kod błędu: %d." % save_error)
			return false
	game_state = candidate
	if not _refresh_base_after_day_resolution():
		_route_current_phase()
	return true


func _refresh_base_after_day_resolution() -> bool:
	if (
		int(game_state.current_phase) != GamePhaseScript.Phase.END_DAY_REPORT
		or current_scene == null
		or current_scene.name != "BaseScene"
		or not current_scene.has_method("bind")
	):
		return false
	# End-day settlement changes data and overlays, not the mounted module. Keeping
	# BaseScene avoids rebuilding the complete 3D environment and UI on the same frame.
	current_scene.call("bind", self, game_state)
	_apply_user_settings_to_scene(current_scene)
	_queue_narrative_sync()
	return true

func acknowledge_day_report() -> bool:
	if game_state == null or int(game_state.current_phase) != GamePhaseScript.Phase.END_DAY_REPORT:
		return false
	var next_phase := GamePhaseScript.Phase.DAY_START_REPORT if game_state.has_pending_settlement_event() else _planning_phase_for_state(game_state)
	var previous_phase := int(game_state.current_phase)
	change_phase(next_phase)
	if campaign_persistence_enabled:
		var save_error := SaveManager.save_game(game_state)
		if save_error != OK:
			change_phase(previous_phase)
			push_warning("Nie udało się zapisać potwierdzenia raportu dnia. Kod błędu: %d." % save_error)
			return false
	_queue_narrative_sync()
	return true

func resolve_settlement_event(choice_id: String) -> bool:
	if game_state == null or int(game_state.current_phase) != GamePhaseScript.Phase.DAY_START_REPORT:
		return false
	if not game_state.has_pending_settlement_event():
		return false
	var candidate = game_state.duplicate(true)
	var result := _settlement_event_system.resolve_choice(
		candidate,
		GameDatabase.settlement_events,
		GameDatabase.survivor_templates,
		choice_id
	)
	if not bool(result.get("success", false)):
		return false
	if candidate.last_morning_report != null:
		candidate.last_morning_report.add_entry("Wydarzenie: %s" % str(result.get("message", "Decyzja została wykonana.")))
	var next_phase := _planning_phase_for_state(candidate)
	candidate.current_phase = next_phase
	_mission_system.reconcile(candidate)
	if campaign_persistence_enabled:
		var save_error := SaveManager.save_game(candidate)
		if save_error != OK:
			push_warning("Nie udało się zapisać decyzji wydarzenia. Kod błędu: %d." % save_error)
			return false
	game_state = candidate
	if current_scene != null and current_scene.has_method("bind"):
		current_scene.call("bind", self, game_state)
	_queue_narrative_sync()
	return true

func continue_chronicle() -> bool:
	if game_state == null:
		return false
	var candidate = game_state.duplicate(true)
	if not CampaignProgressionSystemScript.new().continue_chronicle(candidate):
		return false
	_mission_system.reconcile(candidate)
	if campaign_persistence_enabled and SaveManager.save_game(candidate) != OK:
		return false
	game_state = candidate
	show_base()
	return true

func choose_energy_configuration(configuration_id: String) -> bool:
	if game_state == null or int(game_state.current_phase) != GamePhaseScript.Phase.ENDING:
		return false
	var candidate = game_state.duplicate(true)
	if not CampaignProgressionSystemScript.new().choose_energy_configuration(candidate, configuration_id):
		return false
	if campaign_persistence_enabled and SaveManager.save_game(candidate) != OK:
		return false
	game_state = candidate
	_route_current_phase()
	return true

func return_to_main_menu() -> void:
	_reset_narrative_session()
	_close_pause_menu(false)
	game_state = null
	_load_scene(MAIN_MENU_SCENE)

func tutorial_event(event_id: String, payload: String = "") -> bool:
	if game_state == null or int(game_state.current_phase) == GamePhaseScript.Phase.DIVING:
		return false
	var changed := _tutorial_director.handle_event(game_state, event_id, payload)
	if changed:
		reconcile_missions()
		_queue_narrative_sync()
	return changed

func reconcile_tutorial() -> bool:
	var changed := _tutorial_director.reconcile_base_progress(game_state)
	if changed:
		_queue_narrative_sync()
	return changed

func craft_tutorial_rescue_knife() -> bool:
	var changed := _tutorial_director.craft_rescue_knife(game_state)
	if changed:
		reconcile_missions()
		_queue_narrative_sync()
	return changed

func reconcile_missions() -> bool:
	if game_state == null:
		return false
	var changed := _mission_system.reconcile(game_state)
	return changed

func track_mission(mission_id: String) -> bool:
	if game_state == null or not _mission_system.track_mission(game_state, mission_id):
		return false
	return true

func _route_current_phase() -> void:
	if game_state == null:
		show_main_menu()
		return
	match int(game_state.current_phase):
		GamePhaseScript.Phase.END_DAY_REPORT:
			show_base(true)
		GamePhaseScript.Phase.DAY_START_REPORT:
			if game_state.has_pending_settlement_event():
				show_base(true)
			else:
				show_base()
		GamePhaseScript.Phase.GAME_OVER:
			_load_scene(GAME_OVER_SCENE)
		GamePhaseScript.Phase.ENDING:
			_load_scene(ENDING_SCENE)
		GamePhaseScript.Phase.CRISIS:
			show_base(true)
		_:
			show_base()

func _planning_phase_for_state(state) -> int:
	if state != null and state.story_flags != null and bool(state.story_flags.crisis_active):
		return GamePhaseScript.Phase.CRISIS
	return GamePhaseScript.Phase.BASE_PLANNING

func _load_scene(scene: PackedScene) -> void:
	if narrative_dialogue_panel != null and narrative_dialogue_panel.is_open():
		narrative_dialogue_panel.clear()
	_restore_narrative_focus()
	if pause_menu != null and pause_menu.is_open():
		_close_pause_menu(false)
	# Seed presentation settings before _ready() builds renderer resources. They
	# are applied again after bind because some scenes expose child consumers only
	# once they are in the tree.
	current_scene = SceneFlowScript.replace_child(scene_mount, scene, _seed_user_settings_before_add)
	if current_scene.has_method("bind"):
		current_scene.call("bind", self, game_state)
	_apply_user_settings_to_scene(current_scene)
	_queue_narrative_sync()


func present_ending_conversation(conversation: Dictionary) -> bool:
	return present_ending_narrative(conversation)


func present_ending_narrative(conversation: Dictionary) -> bool:
	if (
		game_state == null
		or current_scene == null
		or current_scene.name != "EndingScene"
		or int(game_state.current_phase) != GamePhaseScript.Phase.ENDING
		or narrative_dialogue_panel == null
		or narrative_dialogue_panel.is_open()
	):
		return false
	return _present_narrative_conversation(conversation)


func present_ending_prelude_narrative() -> bool:
	if (
		game_state == null
		or current_scene == null
		or current_scene.name != "EndingScene"
		or int(game_state.current_phase) != GamePhaseScript.Phase.ENDING
		or narrative_dialogue_panel == null
		or narrative_dialogue_panel.is_open()
	):
		return false
	for conversation in NarrativeContentScript.ending_prelude_conversations(game_state):
		if _present_narrative_conversation(conversation):
			return true
	return false


func _queue_narrative_sync() -> void:
	if _narrative_sync_queued or not is_inside_tree():
		return
	_narrative_sync_queued = true
	call_deferred("_sync_narrative_for_current_scene")


func _sync_narrative_for_current_scene() -> void:
	_narrative_sync_queued = false
	if game_state == null or current_scene == null or narrative_dialogue_panel == null or narrative_dialogue_panel.is_open():
		return
	if current_scene.name != "BaseScene":
		return
	if int(game_state.current_phase) not in [GamePhaseScript.Phase.BASE_PLANNING, GamePhaseScript.Phase.CRISIS]:
		return
	if game_state.has_method("has_pending_settlement_event") and game_state.has_pending_settlement_event():
		return
	var conversations: Array[Dictionary] = []
	if game_state.tutorial != null and game_state.tutorial.is_active():
		var tutorial_conversation: Dictionary = NarrativeContentScript.tutorial_conversation(int(game_state.tutorial.step))
		if not tutorial_conversation.is_empty():
			conversations.append(tutorial_conversation)
	else:
		conversations = NarrativeContentScript.story_conversations(game_state)
	for conversation in conversations:
		if _present_narrative_conversation(conversation):
			return


func _sync_narrative_presenter() -> void:
	_sync_narrative_for_current_scene()


func _reset_narrative_session() -> void:
	if narrative_dialogue_panel != null:
		narrative_dialogue_panel.clear()
	_restore_narrative_focus()
	_seen_narrative_keys.clear()
	_narrative_sync_queued = false


func _present_narrative_conversation(conversation: Dictionary) -> bool:
	var message_key := str(conversation.get("key", ""))
	if message_key.is_empty() or _seen_narrative_keys.has(message_key):
		return false
	var resolved_lines := _resolve_narrative_lines(conversation)
	if resolved_lines.is_empty():
		return false
	_narrative_previous_focus = get_viewport().gui_get_focus_owner()
	narrative_dialogue_panel.present(conversation, resolved_lines)
	return narrative_dialogue_panel.is_open()


func _resolve_narrative_lines(conversation: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source_lines: Array = conversation.get("lines", [])
	for source_line in source_lines:
		if typeof(source_line) != TYPE_DICTIONARY:
			continue
		var line: Dictionary = source_line.duplicate(true)
		var line_type := NarrativeSpeakerResolverScript.normalized_line_type(line)
		line["line_type"] = line_type
		if not NarrativeSpeakerResolverScript.requires_speaker(line):
			result.append(line)
			continue
		var speaker := NarrativeSpeakerResolverScript.resolve(game_state, line)
		if not bool(speaker.get("available", true)):
			continue
		if bool(speaker.get("neutral_report", false)):
			var fallback_body := str(line.get("fallback_body", ""))
			if not fallback_body.is_empty():
				line["body"] = fallback_body
		line["speaker"] = speaker
		result.append(line)
	return result


func _on_narrative_dismissed(message_key: String) -> void:
	if not message_key.is_empty():
		_seen_narrative_keys[message_key] = true
	_restore_narrative_focus()
	if (
		game_state != null
		and current_scene != null
		and current_scene.name == "EndingScene"
		and int(game_state.current_phase) == GamePhaseScript.Phase.ENDING
		and game_state.story_flags != null
		and bool(game_state.story_flags.energy_choice_pending)
	):
		call_deferred("present_ending_prelude_narrative")
		return
	_queue_narrative_sync()


func _on_narrative_cue_activity_changed(active: bool) -> void:
	if current_scene == null or not current_scene.has_method("set_narrative_audio_duck"):
		return
	current_scene.call("set_narrative_audio_duck", active)


func _restore_narrative_focus() -> void:
	if is_instance_valid(_narrative_previous_focus) and _narrative_previous_focus.is_visible_in_tree():
		_narrative_previous_focus.call_deferred("grab_focus")
	_narrative_previous_focus = null


func _seed_user_settings_before_add(scene: Node) -> void:
	if scene == null or user_settings == null or not scene.has_method("seed_user_settings_before_ready"):
		return
	scene.call(
		"seed_user_settings_before_ready",
		str(user_settings.get_value("graphics", "quality", "high")),
		bool(user_settings.get_value("accessibility", "reduced_motion", false))
	)


func _on_user_settings_applied(_settings: Dictionary) -> void:
	_apply_user_settings_to_scene(current_scene)


func _apply_user_settings_to_scene(scene: Node) -> void:
	if scene == null or user_settings == null:
		return
	if scene.has_method("set_graphics_quality"):
		scene.call("set_graphics_quality", str(user_settings.get_value("graphics", "quality", "high")))
	if scene.has_method("set_reduced_motion"):
		scene.call("set_reduced_motion", bool(user_settings.get_value("accessibility", "reduced_motion", false)))


func _should_load_user_settings_from_disk() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var active_scene := get_tree().current_scene
	if active_scene != null and str(active_scene.scene_file_path).begins_with("res://tests/"):
		return false
	for argument in OS.get_cmdline_args():
		var normalized := str(argument).replace("\\", "/")
		if normalized.begins_with("res://tests/") or "/tests/" in normalized:
			return false
	return true


func _close_pause_menu(restore_focus: bool = true) -> void:
	if pause_menu != null:
		pause_menu.close_menu(restore_focus)
	_release_pause_menu_ownership()


func _release_pause_menu_ownership() -> void:
	if not _paused_by_pause_menu:
		return
	var tree := get_tree()
	if tree != null and tree.paused:
		tree.paused = false
	_paused_by_pause_menu = false


func _on_pause_save_requested() -> void:
	var blocker := manual_save_blocker()
	pause_menu.refresh_save_blocker(blocker)
	if not blocker.is_empty():
		pause_menu.show_save_result(false, blocker)
		return
	var save_error := manual_save()
	if save_error == OK:
		pause_menu.show_save_result(true, "Gra została zapisana.")
	else:
		pause_menu.show_save_result(false, "Nie udało się zapisać gry. Sprawdź wolne miejsce i spróbuj ponownie.")


func _on_pause_quit_requested() -> void:
	quit_game_without_save()


func _on_pause_settings_requested() -> void:
	if pause_settings_menu == null or user_settings == null:
		return
	pause_menu.set_secondary_modal_open(true)
	if not pause_settings_menu.open_with_settings(user_settings, pause_menu.settings_button):
		pause_menu.set_secondary_modal_open(false)


func _on_pause_settings_closed() -> void:
	if pause_menu != null and pause_menu.is_open():
		pause_menu.set_secondary_modal_open(false)


func _on_pause_main_menu_requested() -> void:
	return_to_main_menu()


func _current_scene_supports_pause_menu() -> bool:
	return (
		current_scene != null
		and current_scene.has_method("supports_pause_menu")
		and bool(current_scene.call("supports_pause_menu"))
	)


func _pause_context_text() -> String:
	var day := int(game_state.day) if game_state != null else 0
	if current_scene != null and current_scene.name == "DiveScene":
		return "WYPRAWA  •  DZIEŃ %d" % day
	return "PRZYSTAŃ  •  DZIEŃ %d" % day


func _pause_exit_note() -> String:
	if current_scene != null and current_scene.name == "DiveScene":
		return "Niezakończona wyprawa zostanie utracona. Aplikacja zostanie zamknięta bez dodatkowego zapisu."
	return "Aplikacja zostanie zamknięta bez dodatkowego zapisu."


func _pause_main_menu_note() -> String:
	if current_scene != null and current_scene.name == "DiveScene":
		return "Cała niezakończona wyprawa zostanie utracona. Gra wróci do stanu z ostatniego bezpiecznego zapisu."
	return "Niezapisane zmiany od ostatniego zapisu zostaną utracone. Powrót nie utworzy autosave."


func _is_cancel_press(event: InputEvent) -> bool:
	if not event.is_action_pressed(&"ui_cancel"):
		return false
	return not (event is InputEventKey and event.echo)
