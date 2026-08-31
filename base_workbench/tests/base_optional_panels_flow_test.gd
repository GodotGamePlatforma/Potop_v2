extends Node

const BaseScene := preload("res://base_workbench/runtime/BaseScene.tscn")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const BuildingSystemScript := preload("res://base_workbench/systems/BuildingSystem.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const ExpeditionPreparationSystemScript := preload("res://scripts/diving/ExpeditionPreparationSystem.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const MissionSystemScript := preload("res://scripts/campaign/MissionSystem.gd")
const PolicyStateScript := preload("res://scripts/data/PolicyState.gd")
const ProductionSystemScript := preload("res://base_workbench/systems/ProductionSystem.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const ReportStateScript := preload("res://scripts/data/ReportState.gd")
const SettlementEventStateScript := preload("res://scripts/data/SettlementEventState.gd")
const StoryProgressStateScript := preload("res://scripts/data/StoryProgressState.gd")
const TutorialDirectorScript := preload("res://scripts/core/TutorialDirector.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")

const SUPPORTED_LAYOUTS := [
	Vector2(1280, 720),
	Vector2(1600, 900),
	Vector2(1920, 1080),
]

var _failed := false
var _state
var _stub: BaseRootStub
var _base
var _ui_viewport: SubViewport


class BaseRootStub extends Node:
	var game_state
	var mission_system = MissionSystemScript.new()
	var tutorial_director = TutorialDirectorScript.new()

	func reconcile_tutorial() -> bool:
		return tutorial_director.reconcile_base_progress(game_state)

	func reconcile_missions() -> bool:
		return mission_system.reconcile(game_state)

	func track_mission(mission_id: String) -> bool:
		return mission_system.track_mission(game_state, mission_id)

	func tutorial_event(event_id: String) -> bool:
		return tutorial_director.handle_event(game_state, event_id)

	func end_day_blocker() -> String:
		return str(game_state.day_plan_edit_blocker()) if game_state != null else "Brak aktywnego stanu kampanii."


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_state = GameStateScript.new()
	_state.setup_new_campaign(9621, DifficultyProfileScript.new())
	_state.tutorial.complete()
	_state.current_phase = GamePhaseScript.Phase.BASE_PLANNING
	_state.begin_new_day_plan()
	_test_end_day_blocker_contract()
	_ui_viewport = SubViewport.new()
	_ui_viewport.name = "BaseOptionalPanelsViewport"
	_ui_viewport.size = Vector2i(1280, 720)
	_ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_ui_viewport)

	_stub = BaseRootStub.new()
	_stub.game_state = _state
	_ui_viewport.add_child(_stub)
	_stub.reconcile_missions()

	_base = BaseScene.instantiate()
	_base.seed_user_settings_before_ready("low", true)
	_ui_viewport.add_child(_base)
	_base.bind(_stub, _state)
	await _settle()

	await _test_tutorial_ration_selection()
	await _test_light_panel_exclusion()
	await _test_day_plan_popover()
	await _test_survivors_panel()
	await _test_building_panel()
	await _test_open_drawer_resize()
	await _test_campaign_tracker_geometry()
	await _test_domain_blockers_in_ui()

	_base.queue_free()
	_stub.queue_free()
	await get_tree().process_frame
	_ui_viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_base = null
	_stub = null
	_ui_viewport = null
	_state = null
	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
		return
	print("Base optional panels flow test passed: all close paths, focus cycles, click-outside guards, drawer resize, tracker geometry and domain blockers satisfy ARD-0062.")
	get_tree().quit(0)


func _test_tutorial_ration_selection() -> void:
	var ration := _base.find_child("RationPolicyPicker", true, false) as OptionButton
	var tutorial_title := _base.find_child("TutorialTitle", true, false) as Label
	var tutorial_body := _base.find_child("TutorialBody", true, false) as Label
	_assert(ration != null and tutorial_title != null and tutorial_body != null, "Regresja racji tutoriala wymaga kontrolki oraz treści prowadzenia.")
	if ration == null or tutorial_title == null or tutorial_body == null:
		return

	_state.tutorial.step = TutorialStateScript.Step.SET_RATIONS
	_state.active_policies.ration_policy = PolicyStateScript.RationPolicy.FULL
	_state.current_day_plan.ration_policy = PolicyStateScript.RationPolicy.FULL
	_base.bind(_stub, _state)
	await _settle()
	_assert(ration.selected == 0 and ration.is_item_disabled(0) and ration.get_item_text(0) == "Wybierz politykę racji…", "Krok racji musi wymagać jawnego wyboru także przy domyślnych pełnych racjach.")
	_assert("RACJE" in tutorial_title.text, "Przed wyborem tutorial musi nadal wskazywać krok racji.")

	var full_rations_index := _option_item_index(ration, str(PolicyStateScript.RationPolicy.FULL))
	_assert(full_rations_index > 0, "Pełne racje muszą pozostać dostępną polityką po pozycji prowadzącej.")
	if full_rations_index > 0:
		ration.select(full_rations_index)
		ration.item_selected.emit(full_rations_index)
		await _settle()
		_assert(_state.tutorial.step == TutorialStateScript.Step.END_FIRST_DAY, "Jawne wybranie domyślnej polityki musi przesunąć tutorial do końca dnia.")
		_assert("GOTOWE" in tutorial_title.text and "ZAKOŃCZ DZIEŃ" in tutorial_body.text.to_upper(), "Po wyborze racji callout musi od razu prowadzić do zakończenia dnia.")

	_state.tutorial.complete()
	_base.bind(_stub, _state)
	await _settle()


func _test_light_panel_exclusion() -> void:
	var day_opener := _base.find_child("DayPlanButton", true, false) as Button
	var crew_opener := _base.find_child("CrewButton", true, false) as Button
	var day_panel := _base.find_child("DayPlanPopover", true, false) as Control
	var crew_panel := _base.find_child("SurvivorsPanel", true, false) as Control
	var ration := _base.find_child("RationPolicyPicker", true, false) as OptionButton
	_assert(day_opener != null and crew_opener != null and day_panel != null and crew_panel != null and ration != null, "Test wykluczania lekkich paneli wymaga obu przycisków i paneli.")
	if day_opener == null or crew_opener == null or day_panel == null or crew_panel == null or ration == null:
		return
	await _click_control(day_opener)
	await _settle()
	await _click_control(crew_opener)
	await _settle()
	var focus_owner := _ui_viewport.gui_get_focus_owner()
	_assert(not day_panel.visible and crew_panel.visible and focus_owner != null and crew_panel.is_ancestor_of(focus_owner), "Jedno kliknięcie Załogi musi zastąpić otwarty Plan dnia i przejąć fokus.")
	await _click_control(day_opener)
	await _settle()
	_assert(day_panel.visible and not crew_panel.visible and _ui_viewport.gui_get_focus_owner() == ration, "Jedno kliknięcie Planu dnia musi zastąpić otwartą Załogę i przejąć fokus.")
	await _press_key(KEY_ESCAPE)
	await _settle()
	_assert(not day_panel.visible and not crew_panel.visible, "Test wykluczania musi zakończyć się bez otwartego lekkiego panelu.")


func _test_end_day_blocker_contract() -> void:
	var game_root_script = load("res://scripts/core/GameRoot.gd")
	_assert(game_root_script != null, "GameRoot musi się ładować, aby sprawdzić właściciela komendy końca dnia.")
	if game_root_script == null:
		return
	var game_root = game_root_script.new()
	_assert(game_root.end_day_blocker() == "Brak aktywnego stanu kampanii.", "GameRoot musi blokować komendę bez aktywnej kampanii.")
	var state = GameStateScript.new()
	state.setup_new_campaign(9631, DifficultyProfileScript.new())
	state.tutorial.complete()
	state.current_day_plan.locked = false
	game_root.game_state = state
	for phase in [GamePhaseScript.Phase.BASE_PLANNING, GamePhaseScript.Phase.CRISIS]:
		state.current_phase = phase
		_assert(game_root.end_day_blocker().is_empty(), "GameRoot musi pozwalać zakończyć edytowalny dzień w bazie i kryzysie.")
	var phase_reasons := {
		GamePhaseScript.Phase.END_DAY_REPORT: "Najpierw potwierdź obowiązkowe podsumowanie zakończonego dnia.",
		GamePhaseScript.Phase.DAY_START_REPORT: "Najpierw rozstrzygnij wydarzenie poranka.",
		GamePhaseScript.Phase.DAY_RESOLUTION: "Trwa rozliczanie bieżącego dnia.",
		GamePhaseScript.Phase.GAME_OVER: "Kampania jest zakończona porażką.",
		GamePhaseScript.Phase.ENDING: "Najpierw zakończ bieżące podsumowanie kampanii.",
	}
	for phase in phase_reasons:
		state.current_phase = int(phase)
		_assert(game_root.end_day_blocker() == str(phase_reasons[phase]), "Każda faza modalna lub końcowa musi mieć dokładny blocker GameRoot.")
	for phase in [GamePhaseScript.Phase.MAIN_MENU, GamePhaseScript.Phase.EXPEDITION_SETUP, GamePhaseScript.Phase.DIVING, GamePhaseScript.Phase.DIVE_RESULT]:
		state.current_phase = phase
		_assert(game_root.end_day_blocker() == "Dzień można zakończyć wyłącznie podczas planowania w bazie lub kryzysu.", "Pozostałe niedozwolone fazy muszą mieć wspólny blocker GameRoot.")
	state.current_phase = GamePhaseScript.Phase.END_DAY_REPORT
	state.tutorial.step = TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE
	state.current_day_plan.locked = true
	_assert(game_root.end_day_blocker() == str(phase_reasons[GamePhaseScript.Phase.END_DAY_REPORT]), "Faza obowiązkowa musi mieć pierwszeństwo przed tutorialem i blokadą planu.")
	state.current_phase = GamePhaseScript.Phase.BASE_PLANNING
	_assert(game_root.end_day_blocker() == "Najpierw wykonaj bieżący krok samouczka.", "Aktywny krok tutoriala musi poprzedzać blocker planu.")
	state.tutorial.step = TutorialStateScript.Step.END_FIRST_DAY
	_assert(game_root.end_day_blocker() == "Plan dnia został już zatwierdzony i zablokowany.", "Docelowy krok tutoriala musi delegować do blockera planu.")
	state.current_day_plan.locked = false
	_assert(game_root.end_day_blocker().is_empty(), "Docelowy krok tutoriala musi pozwalać zakończyć edytowalny dzień.")
	var pending_event = SettlementEventStateScript.new()
	pending_event.event_id = "test_root_pending_event"
	pending_event.offered_day = state.day
	state.pending_settlement_event = pending_event
	state.current_day_plan.locked = true
	_assert(game_root.end_day_blocker() == "Najpierw rozstrzygnij oczekujące wydarzenie poranka.", "GameRoot musi delegować blokadę oczekującego wydarzenia do GameState.")
	state.current_phase = GamePhaseScript.Phase.DAY_START_REPORT
	_assert(game_root.end_day_blocker() == "Najpierw rozstrzygnij wydarzenie poranka.", "Faza raportu poranka musi mieć pierwszeństwo przed tekstem oczekującego wydarzenia.")
	pending_event.status = SettlementEventStateScript.Status.RESOLVED
	state.current_phase = GamePhaseScript.Phase.CRISIS
	_assert(game_root.end_day_blocker() == "Plan dnia został już zatwierdzony i zablokowany.", "Rozstrzygnięte wydarzenie musi odsłonić blocker planu w kryzysie.")
	state.current_day_plan = null
	_assert(game_root.end_day_blocker().is_empty(), "GameRoot nie może wymyślać blockera w dozwolonej fazie bez migawki planu.")
	game_root.free()


func _test_day_plan_popover() -> void:
	var opener := _base.find_child("DayPlanButton", true, false) as Button
	var panel := _base.find_child("DayPlanPopover", true, false) as Control
	var ration := _base.find_child("RationPolicyPicker", true, false) as OptionButton
	_assert(opener != null and panel != null and ration != null, "Plan dnia musi mieć przycisk, popover i kontrolkę racji.")
	if opener == null or panel == null or ration == null:
		return

	await _click_control(opener)
	await _settle()
	_assert(panel.visible and _ui_viewport.gui_get_focus_owner() == ration, "Otwarcie planu dnia musi przenieść fokus do aktywnej kontrolki racji.")
	await _assert_focus_cycle(panel, "DayPlanPopover")
	await _assert_focus_trap(panel, opener, "DayPlanPopover")
	await _press_key(KEY_ESCAPE)
	await _settle()
	_assert(not panel.visible and _ui_viewport.gui_get_focus_owner() == opener, "Esc musi zamknąć plan dnia i zwrócić fokus przyciskowi otwierającemu.")

	await _click_control(opener)
	await _settle()
	var close := _base.find_child("CloseDayPlanButton", true, false) as Button
	_assert(close != null, "Plan dnia musi mieć jawny przycisk zamknięcia.")
	if close != null:
		await _click_control(close)
		await _settle()
		_assert(not panel.visible and _ui_viewport.gui_get_focus_owner() == opener, "Przycisk X musi zamknąć plan dnia i zwrócić fokus.")

	await _click_control(opener)
	await _settle()
	var slot := _base.find_child("Slot_bottom_right", true, false) as Control
	var modal := _base.find_child("BuildingModal", true, false) as Control
	_assert(slot != null and modal != null, "Test click-outside wymaga prawdziwego slotu i modala budynku.")
	if slot != null and modal != null:
		await _click_at(slot.get_global_rect().get_center())
		await _settle()
		_assert(not panel.visible and not modal.visible, "Click-outside planu musi zamknąć popover bez kliknięcia przez warstwę do slotu.")
		_assert(_ui_viewport.gui_get_focus_owner() == opener, "Click-outside planu musi zwrócić fokus przyciskowi otwierającemu.")


func _test_survivors_panel() -> void:
	var opener := _base.find_child("CrewButton", true, false) as Button
	var panel := _base.find_child("SurvivorsPanel", true, false) as Control
	var list := _base.find_child("SurvivorList", true, false) as Control
	_assert(opener != null and panel != null, "Panel załogi musi mieć przycisk i flyout.")
	if opener == null or panel == null:
		return

	await _click_control(opener)
	await _settle()
	var focus_owner := _ui_viewport.gui_get_focus_owner()
	_assert(panel.visible and focus_owner != null and panel.is_ancestor_of(focus_owner), "Otwarcie załogi musi przenieść fokus do panelu.")
	if list != null:
		_assert(list.is_ancestor_of(focus_owner), "Pierwszy fokus panelu załogi powinien trafić do pierwszej karty mieszkańca.")
	var first_survivor := _base.find_child("SurvivorButton_mira", true, false) as Button
	_assert(first_survivor != null and focus_owner == first_survivor, "Pierwszy fokus panelu załogi musi trafić do karty Miry.")
	await _assert_focus_cycle(panel, "SurvivorsPanel")
	await _assert_focus_trap(panel, opener, "SurvivorsPanel")
	await _press_key(KEY_ESCAPE)
	await _settle()
	_assert(not panel.visible and _ui_viewport.gui_get_focus_owner() == opener, "Esc musi zamknąć załogę i zwrócić fokus.")

	await _click_control(opener)
	await _settle()
	var close := _base.find_child("CloseCrewButton", true, false) as Button
	_assert(close != null, "Panel załogi musi mieć jawny przycisk zamknięcia.")
	if close != null:
		await _click_control(close)
		await _settle()
		_assert(not panel.visible and _ui_viewport.gui_get_focus_owner() == opener, "Przycisk X musi zamknąć załogę i zwrócić fokus.")

	await _click_control(opener)
	await _settle()
	var slot := _base.find_child("Slot_top_right", true, false) as Control
	var modal := _base.find_child("BuildingModal", true, false) as Control
	if slot != null and modal != null:
		await _click_at(slot.get_global_rect().get_center())
		await _settle()
		_assert(not panel.visible and not modal.visible, "Click-outside załogi musi zamknąć panel bez kliknięcia przez warstwę do slotu.")
		_assert(_ui_viewport.gui_get_focus_owner() == opener, "Click-outside załogi musi zwrócić fokus przyciskowi otwierającemu.")


func _test_building_panel() -> void:
	var slot := _base.find_child("Slot_bottom_left", true, false) as Control
	var modal := _base.find_child("BuildingModal", true, false) as Control
	var workspace := _base.find_child("BuildingManagementWorkspace", true, false) as Control
	var panel := _base.find_child("BuildingPanel", true, false) as Control
	_assert(slot != null and modal != null and workspace != null and panel != null, "Test zarządzania budynkiem wymaga slotu, modala, workspace'u i BuildingPanel.")
	if slot == null or modal == null or workspace == null or panel == null:
		return
	var focus_scopes := _building_management_focus_scopes(workspace)

	await _click_control(slot)
	await _settle()
	_assert(modal.visible and workspace.visible and panel.visible and _focus_owner_is_within_scopes(_ui_viewport.gui_get_focus_owner(), focus_scopes), "Otwarcie zarządzania budynkiem musi przejąć fokus w aktywnym zakresie workspace'u i HUD-u.")
	await _assert_focus_cycle_scopes(focus_scopes, "zarządzania budynkiem")
	await _assert_focus_trap(workspace, slot, "Workspace zarządzania budynkiem")
	await _press_key(KEY_ESCAPE)
	await _settle()
	_assert(not modal.visible and _ui_viewport.gui_get_focus_owner() == slot, "Esc musi zamknąć zarządzanie budynkiem i zwrócić fokus slotowi.")

	await _click_control(slot)
	await _settle()
	var close := panel.find_child("CloseButton", true, false) as Button
	_assert(close != null, "Szuflada musi mieć jawny przycisk zamknięcia.")
	if close != null:
		await _click_control(close)
		await _settle()
		_assert(not modal.visible and _ui_viewport.gui_get_focus_owner() == slot, "Przycisk X musi zamknąć szufladę i zwrócić fokus slotowi.")

	await _click_control(slot)
	await _settle()
	await _click_at(Vector2(24, 320))
	await _settle()
	_assert(modal.visible and workspace.visible, "Klik poza workspace'em nie może zamknąć aktywnego zarządzania budynkiem.")
	_assert(_focus_owner_is_within_scopes(_ui_viewport.gui_get_focus_owner(), focus_scopes), "Klik poza workspace'em nie może wypuścić fokusu poza aktywny zakres zarządzania.")
	await _press_key(KEY_ESCAPE)
	await _settle()
	_assert(not modal.visible and _ui_viewport.gui_get_focus_owner() == slot, "Po teście tła Esc musi zamknąć zarządzanie budynkiem i zwrócić fokus slotowi.")


func _test_open_drawer_resize() -> void:
	await _set_layout_size(Vector2(1280, 720))
	var slot := _base.find_child("Slot_bottom_left", true, false) as Control
	var modal := _base.find_child("BuildingModal", true, false) as Control
	var workspace := _base.find_child("BuildingManagementWorkspace", true, false) as Control
	var panel := _base.find_child("BuildingPanel", true, false) as Control
	var navigation_rail := _base.find_child("BuildingNavigationRail", true, false) as Control
	var right_sidebar := _base.find_child("BuildingRightSidebar", true, false) as Control
	var resource_bar := _base.find_child("ResourceBar", true, false) as Control
	var end_day := _base.find_child("EndDayButton", true, false) as Control
	if slot == null or modal == null or workspace == null or panel == null or navigation_rail == null or right_sidebar == null or resource_bar == null or end_day == null:
		_assert(false, "Resize wymaga kompletnego workspace'u zarządzania budynkiem i jego kotwic HUD-u.")
		return
	var focus_scopes := _building_management_focus_scopes(workspace)
	await _click_control(slot)
	await _settle()
	await _set_layout_size(Vector2(960, 540))
	var compact_workspace_rect := workspace.get_global_rect()
	var compact_requested_height := panel.custom_minimum_size.y
	_assert(modal.visible and workspace.visible and panel.visible, "Resize nie może zamknąć otwartego zarządzania budynkiem.")
	_assert(Rect2(Vector2.ZERO, Vector2(960, 540)).encloses(compact_workspace_rect), "Workspace po resize musi mieścić się w widocznym obszarze.")
	_assert(compact_workspace_rect.size.x < 960.0 and compact_workspace_rect.size.y < 540.0, "Workspace musi zachować boczne i pionowe marginesy HUD-u przy 960×540.")
	_assert(not compact_workspace_rect.intersects(resource_bar.get_global_rect()) and not compact_workspace_rect.intersects(end_day.get_global_rect()), "Workspace musi pozostać pomiędzy ResourceBar i EndDayButton.")
	_assert(compact_workspace_rect.encloses(navigation_rail.get_global_rect()) and compact_workspace_rect.encloses(panel.get_global_rect()) and compact_workspace_rect.encloses(right_sidebar.get_global_rect()), "Resize musi zachować lewą nawigację, panel centralny i prawy sidebar wewnątrz workspace'u.")
	_assert(is_equal_approx(panel.size.y, workspace.size.y) and panel.custom_minimum_size.y <= workspace.size.y, "Panel centralny musi dopasować wysokość do kompaktowego workspace'u.")
	_assert(_focus_owner_is_within_scopes(_ui_viewport.gui_get_focus_owner(), focus_scopes), "Resize nie może odebrać fokusu aktywnemu zakresowi zarządzania.")
	await _set_layout_size(Vector2(1280, 720))
	var expanded_workspace_rect := workspace.get_global_rect()
	_assert(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(expanded_workspace_rect), "Workspace po powrocie do 1280×720 musi pozostać w widocznym obszarze.")
	_assert(panel.custom_minimum_size.y > compact_requested_height and panel.custom_minimum_size.y <= workspace.size.y, "Powrót do 1280×720 musi rozszerzyć responsywny panel bez wyjścia poza workspace.")
	_assert(is_equal_approx(panel.size.y, workspace.size.y), "Panel centralny musi wypełniać wysokość rozszerzonego workspace'u.")
	await _press_key(KEY_ESCAPE)
	await _settle()


func _test_campaign_tracker_geometry() -> void:
	await _set_layout_size(Vector2(1280, 720))
	var expand := _base.find_child("CampaignTrackerExpandButton", true, false) as Button
	var panel := _base.find_child("CampaignPanel", true, false) as Control
	var artifacts := _base.find_child("CampaignArtifactsLabel", true, false) as Label
	_assert(expand != null and panel != null and artifacts != null and expand.visible, "Tracker kampanii musi mieć rozwijane szczegóły po ukończeniu tutoriala.")
	if expand == null or panel == null or artifacts == null or not expand.visible:
		return
	if expand.text != "MNIEJ":
		await _click_control(expand)
		await _settle()
	_assert(expand.text == "MNIEJ", "Przycisk trackera musi potwierdzić rozwinięty stan tekstem MNIEJ.")
	_assert(artifacts.visible and not artifacts.text.strip_edges().is_empty(), "Test geometrii musi działać na faktycznie rozwiniętej, niepustej liście celów.")
	for layout in SUPPORTED_LAYOUTS:
		await _set_layout_size(layout)
		for slot_name in ["Slot_top_left", "Slot_top_center", "Slot_top_right", "Slot_bottom_left", "Slot_center", "Slot_bottom_right"]:
			var slot := _base.find_child(slot_name, true, false) as Control
			_assert(slot != null and not panel.get_global_rect().intersects(slot.get_global_rect()), "Rozwinięty CampaignPanel przecina %s przy %d×%d." % [slot_name, int(layout.x), int(layout.y)])
	await _set_layout_size(Vector2(1280, 720))


func _test_domain_blockers_in_ui() -> void:
	_state.story_flags.act = StoryProgressStateScript.ACT_COMMON_LINE
	_base.bind(_stub, _state)
	await _settle()

	for resource_id in ResourceIdsScript.all():
		_state.resources.set_amount(resource_id, 0)
	_base.bind(_stub, _state)
	await _settle()
	var station_slot := _base.find_child("Slot_bottom_right", true, false) as Control
	if station_slot != null:
		await _click_control(station_slot)
		await _settle()
		var build_button := _base.find_child("BuildButton", true, false) as Button
		var definition = GameDatabase.buildings.get("diving_station")
		var expected_build_blocker := BuildingSystemScript.new().construction_blocker(_state, "bottom_right", definition)
		_assert(build_button != null and build_button.disabled and build_button.tooltip_text == expected_build_blocker, "BuildButton musi prezentować dokładnie blocker BuildingSystem.")
		await _press_key(KEY_ESCAPE)
		await _settle()

	var workshop = _add_workshop()
	_base.bind(_stub, _state)
	await _settle()
	var active_slot_tooltip := str(_base.call("_slot_tooltip_text", "bottom_left"))
	_assert(active_slot_tooltip.contains("• aktywny") and not active_slot_tooltip.contains("stan") and not active_slot_tooltip.contains("%"), "Tooltip aktywnego budynku nie może reklamować nieistniejącej zmiennej stanu technicznego.")
	workshop.condition = 0
	var inactive_slot_tooltip := str(_base.call("_slot_tooltip_text", "bottom_left"))
	_assert(inactive_slot_tooltip.contains("budynek nieaktywny") and not inactive_slot_tooltip.contains("stan") and not inactive_slot_tooltip.contains("%"), "Defensywnie zablokowany rekord budynku musi pozostać czytelny bez sugerowania mechaniki uszkodzeń i napraw.")
	workshop.condition = 100
	var workshop_slot := _base.find_child("Slot_bottom_left", true, false) as Control
	if workshop_slot != null:
		await _click_control(workshop_slot)
		await _settle()
		var recipe = GameDatabase.workshop_recipes.get("diving_lantern_mk2")
		var craft_button := _base.find_child("Craft_diving_lantern_mk2", true, false) as Button
		var expected_craft_blocker := ProductionSystemScript.new().queue_recipe_blocker(_state, workshop, recipe)
		_assert(craft_button != null and craft_button.disabled and craft_button.tooltip_text == expected_craft_blocker, "CraftButton musi prezentować dokładnie blocker ProductionSystem.")
		await _press_key(KEY_ESCAPE)
		await _settle()

	var station = _add_diving_station()
	var blocked_worker = _state.find_survivor("mira")
	if blocked_worker != null:
		blocked_worker.fatigue = 90
	_base.bind(_stub, _state)
	await _settle()
	if station_slot != null and station != null:
		await _click_control(station_slot)
		await _settle()
		var station_definition = GameDatabase.buildings.get("diving_station")
		var upgrade_button := _base.find_child("UpgradeButton", true, false) as Button
		var expected_upgrade_blocker := BuildingSystemScript.new().upgrade_blocker(_state, station, station_definition)
		_assert(upgrade_button != null and upgrade_button.disabled and upgrade_button.tooltip_text == expected_upgrade_blocker, "UpgradeButton musi prezentować dokładnie blocker BuildingSystem.")
		var entry_picker := _base.find_child("EntryPointPicker", true, false) as OptionButton
		var entry_analysis := ExpeditionPreparationSystemScript.new().analyze(_state, station, station_definition)
		var expected_entry_reason := str(entry_analysis.get("entry_point_selection_reason", ""))
		_assert(entry_picker != null and entry_picker.disabled and entry_picker.tooltip_text == expected_entry_reason, "EntryPointPicker musi prezentować dokładny powód z analizy przygotowania wyprawy.")
		var worker_picker := _base.find_child("WorkerPicker", true, false) as OptionButton
		if worker_picker != null and blocked_worker != null:
			var worker_index := _option_item_index(worker_picker, blocked_worker.id)
			var worker_reason := str(blocked_worker.work_blocker())
			_assert(worker_index >= 0 and worker_picker.is_item_disabled(worker_index), "Niezdolna do pracy osoba musi być wyłączona w WorkerPicker.")
			if worker_index >= 0:
				_assert(worker_reason in worker_picker.get_item_text(worker_index), "Wyłączony wpis WorkerPicker musi zawierać dokładny blocker mieszkańca.")
		await _press_key(KEY_ESCAPE)
		await _settle()

	_state.current_day_plan.locked = true
	_base.bind(_stub, _state)
	await _settle()
	var ration := _base.find_child("RationPolicyPicker", true, false) as OptionButton
	_assert(ration != null and ration.disabled and ration.tooltip_text == _state.day_plan_edit_blocker(), "Zablokowane racje muszą pokazywać dokładny blocker planu dnia.")
	var end_day := _base.find_child("EndDayButton", true, false) as Button
	_assert(end_day != null and end_day.disabled and end_day.tooltip_text == _state.day_plan_edit_blocker(), "EndDayButton musi prezentować blocker właściciela komendy.")
	if workshop_slot != null:
		await _click_control(workshop_slot)
		await _settle()
		_assert_visible_disabled_controls_have_tooltips(_base)
		await _press_key(KEY_ESCAPE)
		await _settle()
	if station_slot != null and station != null:
		await _click_control(station_slot)
		await _settle()
		var dive_button := _base.find_child("DiveButton", true, false) as Button
		_assert(dive_button != null and dive_button.disabled and dive_button.tooltip_text == _state.day_plan_edit_blocker(), "DiveButton musi prezentować dokładny blocker planu dnia.")
		_assert_visible_disabled_controls_have_tooltips(_base)
		await _press_key(KEY_ESCAPE)
		await _settle()

	_state.current_phase = GamePhaseScript.Phase.END_DAY_REPORT
	_state.end_day_report_history = [ReportStateScript.new()]
	_base.bind(_stub, _state)
	await _settle()
	var mission_journal := _base.find_child("OpenMissionJournalButton", true, false) as Button
	var report_journal := _base.find_child("DayReportJournalButton", true, false) as Button
	_assert(mission_journal != null and mission_journal.disabled and mission_journal.tooltip_text == "Najpierw potwierdź obowiązkowe podsumowanie zakończonego dnia.", "Dziennik misji musi pokazać dokładną blokadę obowiązkowego raportu.")
	_assert(report_journal != null and report_journal.disabled and report_journal.tooltip_text == "Najpierw potwierdź bieżące obowiązkowe podsumowanie dnia.", "Archiwum raportów musi pokazać dokładną blokadę bieżącego podsumowania.")
	_assert(end_day != null and end_day.disabled and end_day.tooltip_text == _state.day_plan_edit_blocker(), "EndDayButton w END_DAY_REPORT musi pokazać przyczynę fazową.")

	_state.current_phase = GamePhaseScript.Phase.BASE_PLANNING
	_state.last_end_day_report = null
	_base.bind(_stub, _state)
	await _settle()
	if station_slot != null:
		await _click_control(station_slot)
		await _settle()
		_state.current_phase = GamePhaseScript.Phase.END_DAY_REPORT
		_state.last_end_day_report = ReportStateScript.new()
		_base.bind(_stub, _state)
		await _settle()
		var modal := _base.find_child("BuildingModal", true, false) as Control
		var summary := _base.find_child("DaySummaryOverlay", true, false) as Control
		_assert(modal != null and not modal.visible and summary != null and summary.visible, "Obowiązkowe podsumowanie musi zamknąć szufladę i przejąć priorytet bez jej późniejszego odsłonięcia.")
		var summary_focus := _ui_viewport.gui_get_focus_owner()
		_assert(summary != null and summary_focus != null and summary.is_ancestor_of(summary_focus), "Obowiązkowe podsumowanie musi przejąć fokus bez zwrotu do zamkniętej szuflady.")
		_state.last_end_day_report = null
		_state.current_phase = GamePhaseScript.Phase.BASE_PLANNING
		_base.bind(_stub, _state)
		await _settle()


func _add_workshop():
	var existing = _state.find_building_by_definition("workshop")
	if existing != null:
		return existing
	var workshop = BuildingStateScript.new()
	workshop.id = "ui_contract_workshop"
	workshop.definition_id = "workshop"
	workshop.slot_id = "bottom_left"
	workshop.level = 1
	workshop.is_built = true
	workshop.condition = 100
	_state.buildings.append(workshop)
	var slot_data: Dictionary = _state.platform.slot_states["bottom_left"]
	slot_data["building_id"] = workshop.id
	_state.platform.slot_states["bottom_left"] = slot_data
	var worker = _state.find_survivor("anka")
	if worker != null:
		workshop.assigned_survivor_ids.assign([worker.id])
		worker.current_assignment = workshop.id
	return workshop


func _add_diving_station():
	var existing = _state.find_building_by_definition("diving_station")
	if existing != null:
		return existing
	var station = BuildingStateScript.new()
	station.id = "ui_contract_diving_station"
	station.definition_id = "diving_station"
	station.slot_id = "bottom_right"
	station.level = 1
	station.is_built = true
	station.condition = 100
	_state.buildings.append(station)
	var slot_data: Dictionary = _state.platform.slot_states["bottom_right"]
	slot_data["building_id"] = station.id
	_state.platform.slot_states["bottom_right"] = slot_data
	return station


func _option_item_index(picker: OptionButton, metadata: String) -> int:
	for index in range(picker.item_count):
		if str(picker.get_item_metadata(index)) == metadata:
			return index
	return -1


func _assert_focus_cycle(panel: Control, panel_name: String) -> void:
	var scopes: Array[Control] = [panel]
	await _assert_focus_cycle_scopes(scopes, panel_name)


func _assert_focus_cycle_scopes(scopes: Array[Control], scope_name: String) -> void:
	var controls: Array[Control] = []
	for scope in scopes:
		_collect_focusable_scope(scope, controls)
	_assert(not controls.is_empty(), "%s musi zawierać kontrolki fokusowalne." % scope_name)
	if controls.is_empty():
		return
	var first := controls[0]
	var last := controls[controls.size() - 1]
	last.grab_focus()
	await get_tree().process_frame
	await _press_key(KEY_TAB)
	_assert(_ui_viewport.gui_get_focus_owner() == first, "Tab z końca zakresu %s musi przejść do pierwszej kontrolki." % scope_name)
	first.grab_focus()
	await get_tree().process_frame
	await _press_key(KEY_TAB, true)
	_assert(_ui_viewport.gui_get_focus_owner() == last, "Shift+Tab z początku zakresu %s musi przejść do ostatniej kontrolki." % scope_name)


func _assert_focus_trap(panel: Control, background_control: Control, panel_name: String) -> void:
	background_control.grab_focus()
	await _settle()
	var focus_owner := _ui_viewport.gui_get_focus_owner()
	_assert(focus_owner != null and panel.is_ancestor_of(focus_owner), "%s musi odzyskać fokus przejęty przez kontrolkę tła." % panel_name)


func _collect_focusable_controls(root: Node, result: Array[Control]) -> void:
	for child in root.get_children():
		if child is Control:
			var control := child as Control
			var disabled := control is BaseButton and (control as BaseButton).disabled
			if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and not disabled and not result.has(control):
				result.append(control)
		_collect_focusable_controls(child, result)


func _collect_focusable_scope(scope: Control, result: Array[Control]) -> void:
	if scope == null or not is_instance_valid(scope):
		return
	var disabled := scope is BaseButton and (scope as BaseButton).disabled
	if scope.is_visible_in_tree() and scope.focus_mode != Control.FOCUS_NONE and not disabled and not result.has(scope):
		result.append(scope)
	_collect_focusable_controls(scope, result)


func _building_management_focus_scopes(workspace: Control) -> Array[Control]:
	var scopes: Array[Control] = [workspace]
	for node_name in ["DayPlanButton", "CrewButton", "DayPlanPopover", "SurvivorsPanel", "EndDayButton"]:
		var scope := _base.find_child(node_name, true, false) as Control
		_assert(scope != null, "Zakres fokusu zarządzania budynkiem wymaga kontrolki %s." % node_name)
		if scope != null:
			scopes.append(scope)
	return scopes


func _focus_owner_is_within_scopes(focus_owner: Control, scopes: Array[Control]) -> bool:
	if focus_owner == null:
		return false
	for scope in scopes:
		if scope != null and is_instance_valid(scope) and (focus_owner == scope or scope.is_ancestor_of(focus_owner)):
			return true
	return false


func _assert_visible_disabled_controls_have_tooltips(root: Node) -> void:
	for node in root.find_children("*", "BaseButton", true, false):
		var control := node as BaseButton
		if control != null and control.is_visible_in_tree() and control.disabled:
			_assert(not control.tooltip_text.strip_edges().is_empty(), "Widoczna zablokowana kontrolka %s musi pokazywać przyczynę." % control.name)


func _set_layout_size(layout_size: Vector2) -> void:
	_ui_viewport.size = Vector2i(roundi(layout_size.x), roundi(layout_size.y))
	await get_tree().process_frame
	await _settle()
	_assert(_base.size.is_equal_approx(layout_size), "Zmiana okna musi wyemitować produkcyjny resize BaseController do %d×%d, otrzymano %.0f×%.0f." % [int(layout_size.x), int(layout_size.y), _base.size.x, _base.size.y])


func _click_control(control: Control) -> void:
	if control == null:
		return
	await _click_at(control.get_global_rect().get_center())


func _click_at(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	_ui_viewport.push_input(motion, true)
	await get_tree().process_frame
	var press := InputEventMouseButton.new()
	press.position = position
	press.global_position = position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	_ui_viewport.push_input(press, true)
	await get_tree().process_frame
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	_ui_viewport.push_input(release, true)
	await get_tree().process_frame


func _press_key(keycode: int, shift_pressed: bool = false) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.shift_pressed = shift_pressed
	press.pressed = true
	_ui_viewport.push_input(press, true)
	await get_tree().process_frame
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	_ui_viewport.push_input(release, true)
	await get_tree().process_frame


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Base optional panels flow test failed: " + message)
