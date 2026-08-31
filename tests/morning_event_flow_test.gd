extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const SettlementEventStateScript := preload("res://scripts/data/SettlementEventState.gd")
const SettlementEventSystemScript := preload("res://base_workbench/systems/SettlementEventSystem.gd")

var _failed: bool = false

func _ready() -> void:
	await _run_accept_flow()
	await _run_reject_flow()
	await _run_quiet_morning_flow()
	if _failed:
		get_tree().quit(1)
		return
	print("Morning event flow test passed: summary -> saved event -> mandatory choice -> planning works for accept, reject and a quiet morning.")
	get_tree().quit(0)

func _run_accept_flow() -> void:
	var game = await _new_game(81_001)
	if game == null:
		return
	_prepare_for_population_event(game)
	game.end_day()
	_install_population_event_for_ui_test(game)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(game.game_state.day == 3 and game.game_state.current_phase == GamePhaseScript.Phase.END_DAY_REPORT, "Rozliczenie dnia 2 powinno zatrzymać się na modalnym podsumowaniu dnia.")
	_assert(game.game_state.has_pending_settlement_event() and game.game_state.pending_settlement_event.event_id == "survivors_on_horizon", "Test UI powinien mieć jawnie przygotowaną kartę dwóch ocalałych.")
	var summary := game.current_scene.find_child("DaySummaryOverlay", true, false) as Control
	var event_overlay := game.current_scene.find_child("SettlementEventOverlay", true, false) as Control
	var report_journal_button := game.current_scene.find_child("DayReportJournalButton", true, false) as Button
	var report_journal := game.current_scene.find_child("DayReportJournalOverlay", true, false) as Control
	var report_count_before: int = game.game_state.end_day_report_history.size()
	_assert(summary != null and summary.visible, "Najpierw musi być widoczne podsumowanie poprzedniego dnia.")
	_assert(event_overlay != null and not event_overlay.visible, "Wydarzenie nie może zasłonić wcześniejszego podsumowania.")
	_assert(not game.game_state.can_edit_day_plan(), "Podsumowanie powinno blokować plan nowego dnia.")
	_assert(report_count_before == 1 and report_journal_button != null and report_journal_button.disabled, "Raport dnia powinien być już zapisany, lecz archiwum nie może przykryć obowiązkowego podsumowania.")

	var summary_button := game.current_scene.find_child("DaySummaryContinueButton", true, false) as Button
	_assert(summary_button != null, "Podsumowanie powinno mieć działający przycisk rozpoczęcia dnia.")
	if summary_button == null:
		await _remove_game(game)
		return
	summary_button.pressed.emit()
	await get_tree().process_frame
	_assert(game.game_state.current_phase == GamePhaseScript.Phase.DAY_START_REPORT, "Po podsumowaniu pending event powinien przejąć istniejącą fazę poranka.")
	_assert(not summary.visible and event_overlay.visible, "Po potwierdzeniu podsumowania powinien pojawić się wyłącznie modal wydarzenia.")
	_assert(not game.game_state.can_edit_day_plan(), "Nie można planować ani rozpocząć wyprawy przed obowiązkową decyzją.")
	_assert(report_journal_button != null and report_journal_button.disabled, "Archiwum raportów powinno pozostać zablokowane podczas obowiązkowego wydarzenia poranka.")
	if report_journal_button != null:
		report_journal_button.pressed.emit()
	await get_tree().process_frame
	_assert(report_journal != null and not report_journal.visible, "Ręczny sygnał przycisku nie może ominąć fazy DAY_START_REPORT.")
	var title := game.current_scene.find_child("SettlementEventTitle", true, false) as Label
	var body := game.current_scene.find_child("SettlementEventBody", true, false) as Label
	var accept_button := game.current_scene.find_child("SettlementEventChoice_accept", true, false) as Button
	var reject_button := game.current_scene.find_child("SettlementEventChoice_reject", true, false) as Button
	_assert(title != null and title.text.contains("DWOJE") and body != null and body.text.contains("dwie osoby"), "Panel powinien wyświetlić treść zapisanej definicji.")
	_assert(accept_button != null and reject_button != null and not accept_button.disabled and not reject_button.disabled, "Obie decyzje moralne powinny być widoczne i wykonywalne.")
	if report_journal_button != null:
		report_journal_button.grab_focus()
		await get_tree().process_frame
		var event_focus := get_viewport().gui_get_focus_owner()
		_assert(event_focus != null and event_overlay.is_ancestor_of(event_focus), "Fokus klawiatury i pada musi pozostać wewnątrz obowiązkowego wydarzenia poranka.")
	if accept_button == null:
		await _remove_game(game)
		return
	var survivors_before: int = game.game_state.survivors.size()
	accept_button.pressed.emit()
	await get_tree().process_frame
	_assert(game.game_state.current_phase == GamePhaseScript.Phase.BASE_PLANNING and game.game_state.can_edit_day_plan(), "Po zapisaniu decyzji normalne planowanie powinno zostać odblokowane.")
	_assert(not event_overlay.visible and game.game_state.survivors.size() == survivors_before + 2, "Przyjęcie powinno zamknąć panel i dodać dokładnie dwie osoby.")
	_assert(game.game_state.end_day_report_history.size() == report_count_before and report_journal_button != null and not report_journal_button.disabled, "Potwierdzenie raportu i wybór wydarzenia nie mogą dodać drugiego wpisu, a po decyzji archiwum powinno być dostępne.")
	_assert(game.current_scene.find_child("SurvivorButton_zofia_kruk", true, false) != null and game.current_scene.find_child("SurvivorButton_pawel_mazur", true, false) != null, "Nowi mieszkańcy powinni natychmiast pojawić się w prawdziwym UI bazy.")
	_assert(not game.resolve_settlement_event("accept") and game.game_state.survivors.size() == survivors_before + 2, "Ponowny sygnał nie może powtórzyć rozstrzygniętej decyzji.")
	await _remove_game(game)

func _run_reject_flow() -> void:
	var game = await _new_game(81_002)
	if game == null:
		return
	_prepare_for_population_event(game)
	game.end_day()
	_install_population_event_for_ui_test(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var summary_button := game.current_scene.find_child("DaySummaryContinueButton", true, false) as Button
	if summary_button == null:
		_assert(false, "Drugi przebieg powinien również pokazać podsumowanie.")
		await _remove_game(game)
		return
	summary_button.pressed.emit()
	await get_tree().process_frame
	var reject_button := game.current_scene.find_child("SettlementEventChoice_reject", true, false) as Button
	var population_before: int = game.game_state.survivors.size()
	var hope_before: int = game.game_state.resources.get_amount(ResourceIdsScript.HOPE)
	if reject_button == null:
		_assert(false, "Panel powinien udostępnić odmowę pomocy.")
		await _remove_game(game)
		return
	reject_button.pressed.emit()
	await get_tree().process_frame
	_assert(game.game_state.current_phase == GamePhaseScript.Phase.BASE_PLANNING, "Odmowa również powinna zakończyć fazę wydarzenia.")
	_assert(game.game_state.survivors.size() == population_before and game.game_state.resources.get_amount(ResourceIdsScript.HOPE) == hope_before - 8, "Odmowa powinna pozostawić populację i jednokrotnie obniżyć Nadzieję.")
	_assert(game.game_state.settlement_event_history.back().selected_choice_id == "reject", "Wybór odmowy musi pozostać w historii kampanii.")
	await _remove_game(game)

func _run_quiet_morning_flow() -> void:
	var game = await _new_game(81_003)
	if game == null:
		return
	game.game_state.day = 2
	game.game_state.begin_new_day_plan()
	game.game_state.settlement_event_roll_day = 3
	game.game_state.resources.set_amount(ResourceIdsScript.FOOD, 1000)
	game.end_day()
	if game.game_state.pressure_state != null:
		game.game_state.pressure_state.commit_quiet_morning()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not game.game_state.has_pending_settlement_event(), "Zapisany spokojny poranek nie powinien tworzyć pustego modala.")
	_assert(game.game_state.pressure_state != null and game.game_state.pressure_state.quiet_morning, "Spokojny poranek powinien być jawnie zapisany także w PressureState.")
	var summary_button := game.current_scene.find_child("DaySummaryContinueButton", true, false) as Button
	if summary_button != null:
		summary_button.pressed.emit()
		await get_tree().process_frame
	_assert(game.game_state.current_phase == GamePhaseScript.Phase.BASE_PLANNING and game.game_state.can_edit_day_plan(), "Bez wydarzenia podsumowanie powinno prowadzić bezpośrednio do planowania.")
	await _remove_game(game)

func _new_game(seed_value: int):
	var game = GameRootScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	var campaign_started: bool = game.start_new_campaign("standard", seed_value, false)
	_assert(campaign_started, "Test powinien rozpocząć kampanię bez dotykania prawdziwego autosave.")
	if not campaign_started:
		await _remove_game(game)
		return null
	await get_tree().process_frame
	return game

func _prepare_for_population_event(game) -> void:
	var state = game.game_state
	state.tutorial.complete()
	state.day = 2
	state.settlement_event_roll_day = 0
	state.resources.set_amount(ResourceIdsScript.FOOD, 1000)
	state.resources.set_amount(ResourceIdsScript.HOPE, 55)
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 80)
	for index in range(1, state.survivors.size()):
		state.survivors[index].status = SurvivorStateScript.Status.DEAD
		state.survivors[index].health = 0
	state.begin_new_day_plan()
	state.current_phase = GamePhaseScript.Phase.BASE_PLANNING

func _install_population_event_for_ui_test(game) -> void:
	# Dobór karty i ograniczenia PressureState mają osobny test domenowy. Ten test
	# sceny jawnie wstrzykuje legalną, zapisaną instancję, aby stabilnie sprawdzać
	# kolejność dwóch modali i oba wybory bez dawnej „gwarancji dwóch ludzi”.
	var state = game.game_state
	var definition = GameDatabase.settlement_events.get("survivors_on_horizon")
	var event_state = SettlementEventStateScript.new()
	var offer_snapshot = SettlementEventSystemScript.new().build_offer_snapshot(state, definition, GameDatabase.survivor_templates)
	event_state.setup_offer(offer_snapshot, int(state.day))
	state.pending_settlement_event = event_state
	state.settlement_event_roll_day = int(state.day)
	if state.pressure_state != null:
		state.pressure_state.quiet_morning = false
		state.pressure_state.committed_event_id = "survivors_on_horizon"
		state.pressure_state.committed_event_tone = str(definition.tone)
		state.pressure_state.committed_event_severity = int(definition.severity)
		state.pressure_state.spent_pressure_budget = float(definition.pressure_cost)
		state.pressure_state.refresh_debug_summary()
	if game.current_scene != null and game.current_scene.has_method("bind"):
		game.current_scene.bind(game, state)

func _remove_game(game) -> void:
	game.show_main_menu()
	await get_tree().process_frame
	await get_tree().process_frame
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Morning event flow test failed: " + message)
