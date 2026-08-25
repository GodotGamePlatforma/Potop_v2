extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")

const TEST_SAVE := "user://test_pause_menu_flow.tres"
const TEST_PENDING := "user://test_pause_menu_flow.pending.tres"
const TEST_BACKUP := "user://test_pause_menu_flow.backup.tres"

var _failed: bool = false
var _game
var _pause: PauseMenu
var _quit_requests: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_remove_test_saves()
	SaveManager.configure_paths(TEST_SAVE, TEST_PENDING, TEST_BACKUP)
	_game = GameRootScene.instantiate()
	# Sam runner musi działać podczas pauzy, ale produkcyjny GameRoot nie może
	# odziedziczyć po nim PROCESS_MODE_ALWAYS, bo wtedy sesja nurkowania także
	# omijałaby SceneTree.paused.
	_game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_game)
	await _frames(3)
	_pause = _game.pause_menu as PauseMenu
	_assert(_pause != null, "GameRoot powinien posiadać trwałe PauseMenu poza SceneMount.")
	if _pause == null:
		await _finish()
		return

	await _test_main_menu_escape_scope()
	await _test_intro_escape_priority()
	await _test_base_pause_focus_and_continue()
	await _test_pause_settings_overlay()
	await _test_main_menu_return_cancel_in_base()
	await _test_existing_pause_ownership()
	await _test_optional_base_overlay_priority()
	await _test_manual_save_success_failure_and_retry()
	await _test_mandatory_day_summary_survives_pause()
	await _test_dive_pause_blocker_and_local_overlay()
	await _test_direct_quit_intent_without_confirmation()
	await _test_confirmed_main_menu_return_from_dive()
	await _finish()


func _test_main_menu_escape_scope() -> void:
	_assert(_game.current_scene != null and _game.current_scene.name == "MainMenu", "Test powinien rozpocząć się w prawdziwym menu głównym.")
	await _press_key(KEY_ESCAPE)
	_assert(not _pause.is_open(), "ESC w menu głównym nie może otwierać menu pauzy.")
	_assert(not get_tree().paused, "ESC w menu głównym nie może zatrzymywać drzewa scen.")


func _test_intro_escape_priority() -> void:
	_assert(_game.start_new_campaign("standard", 7311, true, true), "Test powinien uruchomić zapisaną kampanię z intro.")
	await _frames(3)
	_assert(_game.current_scene != null and _game.current_scene.name == "IntroScene", "Kampania testowa powinna wejść do IntroScene.")
	await _press_key(KEY_ESCAPE)
	await _frames(2)
	_assert(_game.current_scene != null and _game.current_scene.name == "BaseScene", "ESC w intro powinien nadal pomijać intro i przechodzić do bazy.")
	_assert(not _pause.is_open() and not get_tree().paused, "Pominięcie intro nie może nawet pozostawić aktywnej pauzy.")


func _test_base_pause_focus_and_continue() -> void:
	_game.game_state.tutorial.complete()
	_game.reconcile_missions()
	_game.current_scene.bind(_game, _game.game_state)
	await _frames(2)
	# Ten test izoluje globalną pauzę; kanoniczny panel narracyjny ma osobny
	# przepływ i zgodnie z kontraktem przejmuje ESC, dopóki jest otwarty.
	_game.narrative_dialogue_panel.clear()
	var background := _game.current_scene.find_child("DayPlanButton", true, false) as Button
	_assert(background != null, "Baza powinna wystawiać stabilny przycisk Planu dnia do testu fokusu.")
	if background == null:
		return
	background.grab_focus()
	await _frames(1)
	var scene_before = _game.current_scene
	var state_before = _game.game_state
	var day_before := int(_game.game_state.day)
	var phase_before := int(_game.game_state.current_phase)
	var food_before := int(_game.game_state.resources.get_amount(ResourceIdsScript.FOOD))

	await _press_key(KEY_ESCAPE)
	await _frames(2)
	_assert(_pause.is_open() and get_tree().paused, "ESC w bazie powinien otworzyć menu i rzeczywiście zatrzymać drzewo.")
	_assert(_game.current_scene == scene_before and _game.game_state == state_before, "Otwarcie pauzy nie może przeładować sceny ani podmienić GameState.")
	_assert(int(_game.game_state.day) == day_before and int(_game.game_state.current_phase) == phase_before and int(_game.game_state.resources.get_amount(ResourceIdsScript.FOOD)) == food_before, "Otwarcie pauzy nie może mutować dnia, fazy ani zasobów.")
	var backdrop := _pause.find_child("Backdrop", true, false) as Control
	_assert(backdrop != null and backdrop.mouse_filter == Control.MOUSE_FILTER_STOP, "Pauza powinna pełnoekranowo blokować kliknięcia tła.")
	var pause_panel := _pause.find_child("PausePanel", true, false) as Control
	_assert(
		pause_panel != null and pause_panel.size.y <= 620.0 and pause_panel.get_global_rect().end.y <= get_viewport().get_visible_rect().end.y - 24.0,
		"Menu pauzy powinno mieścić wszystkie decyzje bez przewijania i zachować dolny bezpieczny margines przy 1280x720."
	)
	_assert(get_viewport().gui_get_focus_owner() == _pause.continue_button, "Po otwarciu fokus powinien trafić do KONTYNUUJ.")

	background.grab_focus()
	await _frames(2)
	var trapped_focus := get_viewport().gui_get_focus_owner()
	_assert(trapped_focus != null and _pause.is_ancestor_of(trapped_focus), "Fokus nie może uciec z otwartego menu pauzy do zatrzymanej sceny.")
	_pause.quit_button.grab_focus()
	await _frames(1)
	await _press_key(KEY_TAB)
	_assert(get_viewport().gui_get_focus_owner() == _pause.continue_button, "Tab z ostatniej akcji powinien zapętlić fokus do KONTYNUUJ.")
	_pause.continue_button.grab_focus()
	await _frames(1)
	await _press_key(KEY_TAB, true)
	_assert(get_viewport().gui_get_focus_owner() == _pause.quit_button, "Shift+Tab z KONTYNUUJ powinien przejść do WYJDŹ Z GRY.")

	_pause.continue_button.pressed.emit()
	await _frames(2)
	_assert(not _pause.is_open() and not get_tree().paused, "KONTYNUUJ powinno zamknąć menu i wznowić pauzę należącą do menu.")
	_assert(get_viewport().gui_get_focus_owner() == background, "Kontynuacja powinna przywrócić fokus kontrolce sprzed pauzy.")

	await _press_key(KEY_ESCAPE)
	_assert(_pause.is_open() and get_tree().paused, "Menu powinno dać się otworzyć ponownie bez zmiany sceny.")
	await _press_key(KEY_ESCAPE)
	_assert(not _pause.is_open() and not get_tree().paused, "Drugi ESC powinien zachowywać się jak KONTYNUUJ.")
	await _send_escape_echo()
	_assert(not _pause.is_open() and not get_tree().paused, "Powtórzenie klawisza z flagą echo nie może otworzyć pauzy.")


func _test_optional_base_overlay_priority() -> void:
	var opener := _game.current_scene.find_child("DayPlanButton", true, false) as Button
	var popover := _game.current_scene.find_child("DayPlanPopover", true, false) as Control
	_assert(opener != null and popover != null, "Test priorytetu ESC wymaga popoveru Planu dnia.")
	if opener == null or popover == null:
		return
	opener.pressed.emit()
	await _frames(2)
	_assert(popover.visible, "Przycisk Planu dnia powinien otworzyć opcjonalną nakładkę.")
	await _press_key(KEY_ESCAPE)
	await _frames(1)
	_assert(not popover.visible, "Pierwszy ESC powinien zamknąć opcjonalny panel lokalny.")
	_assert(not _pause.is_open() and not get_tree().paused, "ESC zamykający panel lokalny nie może równocześnie otworzyć pauzy.")
	_assert(get_viewport().gui_get_focus_owner() == opener, "Zamknięcie panelu powinno zachować jego dotychczasowy powrót fokusu.")
	await _press_key(KEY_ESCAPE)
	_assert(_pause.is_open() and get_tree().paused, "Dopiero kolejny ESC powinien otworzyć globalną pauzę.")
	_pause.continue_button.pressed.emit()
	await _frames(2)


func _test_pause_settings_overlay() -> void:
	await _press_key(KEY_ESCAPE)
	await _frames(2)
	_assert(_pause.is_open() and get_tree().paused, "Ustawienia pauzy powinny być otwierane nad zatrzymaną bazą.")
	_pause.settings_button.pressed.emit()
	await _frames(3)
	var settings_menu = _game.pause_settings_menu
	_assert(settings_menu != null and settings_menu.visible, "USTAWIENIA powinny otworzyć ten sam pełny panel UserSettings nad pauzą.")
	_assert(_pause.is_open() and get_tree().paused, "Otwarcie ustawień nie może zamknąć pauzy ani wznowić symulacji.")
	var focus_owner := get_viewport().gui_get_focus_owner()
	_assert(focus_owner != null and settings_menu.is_ancestor_of(focus_owner), "Fokus powinien zostać przekazany do modalnych ustawień.")
	settings_menu.cancel_button.pressed.emit()
	await _frames(3)
	_assert(not settings_menu.visible and _pause.is_open() and get_tree().paused, "Zamknięcie ustawień powinno wrócić do nadal otwartej pauzy.")
	_assert(get_viewport().gui_get_focus_owner() == _pause.settings_button, "Po ustawieniach fokus powinien wrócić do ich przycisku w pauzie.")
	_pause.continue_button.pressed.emit()
	await _frames(2)


func _test_main_menu_return_cancel_in_base() -> void:
	await _press_key(KEY_ESCAPE)
	await _frames(2)
	var state_before = _game.game_state
	var saved_before = SaveManager.load_game()
	_pause.main_menu_button.pressed.emit()
	await _frames(2)
	var confirmation := _pause.find_child("MainMenuConfirmation", true, false) as ConfirmationDialog
	_assert(confirmation != null and confirmation.visible, "POWRÓT DO MENU GŁÓWNEGO musi wymagać jawnego potwierdzenia.")
	_assert(confirmation.dialog_text.contains("bez zapisywania") and confirmation.dialog_text.contains("autosave"), "Potwierdzenie w bazie musi wyjaśniać brak ukrytego autosave.")
	_assert(_pause.is_open() and get_tree().paused and _game.game_state == state_before, "Samo otwarcie potwierdzenia nie może zmieniać runtime ani pauzy.")
	confirmation.get_cancel_button().pressed.emit()
	await _frames(2)
	var saved_after_cancel = SaveManager.load_game()
	_assert(not confirmation.visible and _pause.is_open() and get_tree().paused, "ANULUJ powinno wrócić do menu pauzy.")
	_assert(saved_before != null and saved_after_cancel != null and str(saved_after_cancel.campaign_id) == str(saved_before.campaign_id), "Anulowane wyjście nie może dotknąć pliku zapisu.")
	_assert(get_viewport().gui_get_focus_owner() == _pause.main_menu_button, "Po anulowaniu fokus powinien wrócić do akcji menu głównego.")
	_pause.continue_button.pressed.emit()
	await _frames(2)


func _test_existing_pause_ownership() -> void:
	get_tree().paused = true
	_assert(_game.open_pause_menu(), "Menu powinno dać się pokazać nad pauzą należącą już do innego systemu.")
	await _frames(2)
	_assert(_pause.is_open() and get_tree().paused, "Otwarcie nad istniejącą pauzą powinno zachować zatrzymane drzewo.")
	_pause.continue_button.pressed.emit()
	await _frames(2)
	_assert(not _pause.is_open() and get_tree().paused, "Zamknięcie menu nie może zdjąć pauzy, której samo nie założyło.")
	get_tree().paused = false
	await _frames(1)


func _test_manual_save_success_failure_and_retry() -> void:
	var state_before = _game.game_state
	var food_before := int(_game.game_state.resources.get_amount(ResourceIdsScript.FOOD))
	_game.game_state.resources.set_amount(ResourceIdsScript.FOOD, food_before + 2)
	await _press_key(KEY_ESCAPE)
	_assert(_pause.is_open() and not _pause.save_button.disabled, "ZAPISZ GRĘ powinno być dostępne w stabilnej fazie planowania bazy.")
	_pause.save_button.pressed.emit()
	await _frames(2)
	var saved = SaveManager.load_game()
	_assert(saved != null and int(saved.resources.get_amount(ResourceIdsScript.FOOD)) == food_before + 2, "Ręczny zapis powinien utrwalić bieżącą zmianę w bezpiecznym zapisie kampanii.")
	_assert(_game.game_state == state_before, "Ręczny zapis nie może podmieniać aktywnej instancji GameState.")
	_assert(_pause.is_open() and get_tree().paused, "Udany zapis powinien pozostawić menu otwarte i grę zatrzymaną.")
	_assert(_pause.status_label.text == "Gra została zapisana.", "Menu powinno pokazać jednoznaczne potwierdzenie udanego zapisu.")
	_assert(not _test_file_exists(TEST_PENDING), "Udany ręczny zapis nie powinien pozostawiać pliku pending.")

	var stable_food := int(saved.resources.get_amount(ResourceIdsScript.FOOD)) if saved != null else food_before + 2
	_game.game_state.resources.set_amount(ResourceIdsScript.FOOD, stable_food + 3)
	SaveManager.fail_next_save_for_tests(ERR_CANT_CREATE)
	_pause.save_button.pressed.emit()
	await _frames(2)
	var after_failure = SaveManager.load_game()
	_assert(after_failure != null and int(after_failure.resources.get_amount(ResourceIdsScript.FOOD)) == stable_food, "Błąd zapisu powinien zachować ostatni poprawny primary.")
	_assert(int(_game.game_state.resources.get_amount(ResourceIdsScript.FOOD)) == stable_food + 3, "Błąd persistence nie może cofać bieżącego stanu runtime.")
	_assert(_pause.is_open() and get_tree().paused and _pause.status_label.text.contains("Nie udało się zapisać"), "Błąd zapisu powinien pozostać w pauzie z czytelnym komunikatem i możliwością ponowienia.")

	_pause.save_button.pressed.emit()
	await _frames(2)
	var after_retry = SaveManager.load_game()
	_assert(after_retry != null and int(after_retry.resources.get_amount(ResourceIdsScript.FOOD)) == stable_food + 3, "Ponowienie po jednorazowym błędzie powinno utrwalić ten sam bieżący stan.")
	_assert(_pause.status_label.text == "Gra została zapisana.", "Udane ponowienie powinno zastąpić komunikat błędu potwierdzeniem.")
	_pause.continue_button.pressed.emit()
	await _frames(2)


func _test_mandatory_day_summary_survives_pause() -> void:
	_assert(_game.end_day(), "Ukończony tutorial powinien pozwolić rozliczyć dzień bez wyprawy.")
	await _frames(4)
	var summary := _game.current_scene.find_child("DaySummaryOverlay", true, false) as Control
	var summary_continue := _game.current_scene.find_child("DaySummaryContinueButton", true, false) as Button
	_assert(summary != null and summary.visible and summary_continue != null, "Rozliczenie powinno otworzyć obowiązkowy raport dnia.")
	var phase_before := int(_game.game_state.current_phase)
	await _press_key(KEY_ESCAPE)
	_assert(_pause.is_open() and get_tree().paused, "ESC powinien móc otworzyć pauzę ponad obowiązkowym raportem.")
	_assert(summary != null and summary.visible and int(_game.game_state.current_phase) == phase_before, "Otwarcie pauzy nie może potwierdzić ani ukryć obowiązkowego raportu.")
	_pause.continue_button.pressed.emit()
	await _frames(2)
	_assert(summary != null and summary.visible and int(_game.game_state.current_phase) == GamePhaseScript.Phase.END_DAY_REPORT, "Po kontynuacji obowiązkowy raport powinien nadal oczekiwać na decyzję.")
	_assert(get_viewport().gui_get_focus_owner() == summary_continue, "Po wznowieniu fokus powinien wrócić do akcji obowiązkowego raportu.")


func _test_dive_pause_blocker_and_local_overlay() -> void:
	_assert(_game.start_new_campaign("standard", 7312, true, false), "Test nurkowania powinien rozpocząć świeżą stabilną kampanię.")
	await _frames(3)
	_game.game_state.tutorial.complete()
	_game.current_scene.bind(_game, _game.game_state)
	var setup = _make_setup(int(_game.game_state.day))
	_game.start_dive(setup)
	await _frames(4)
	var dive = _game.current_scene
	_assert(dive != null and dive.name == "DiveScene", "Poprawny setup powinien wejść do DiveScene.")
	if dive == null or dive.name != "DiveScene":
		return

	await _press_key(KEY_ESCAPE)
	await _frames(2)
	_assert(_pause.is_open() and get_tree().paused, "ESC podczas wyprawy powinien zatrzymać lokalną sesję.")
	_assert(_pause.save_button.disabled and _pause.save_note.text.contains("wyprawy nie można zapisać"), "Podczas nurkowania zapis powinien być wyłączony z konkretnym powodem.")
	_assert(_pause.quit_note.text.contains("Niezakończona wyprawa zostanie utracona"), "Menu powinno jawnie opisać skutek bezpośredniego wyjścia podczas wyprawy.")
	var elapsed_frozen := float(dive.session.elapsed_time)
	var oxygen_frozen := float(dive.session.oxygen_left)
	var position_frozen := Vector2(dive.diver.global_position)
	await _frames(8)
	_assert(is_equal_approx(float(dive.session.elapsed_time), elapsed_frozen), "Czas wyprawy nie może rosnąć pod menu pauzy.")
	_assert(is_equal_approx(float(dive.session.oxygen_left), oxygen_frozen), "Tlen nie może być zużywany pod menu pauzy.")
	_assert(Vector2(dive.diver.global_position).is_equal_approx(position_frozen), "Nurek nie może przemieszczać się pod menu pauzy.")
	var stable_save = SaveManager.load_game()
	_assert(_game.manual_save() == ERR_UNAVAILABLE, "Programatyczna próba ręcznego zapisu w DIVING musi powtórzyć blocker UI.")
	_pause.save_requested.emit()
	await _frames(1)
	var save_after_blocked_request = SaveManager.load_game()
	_assert(stable_save != null and save_after_blocked_request != null and int(save_after_blocked_request.current_phase) == int(stable_save.current_phase), "Zablokowane żądanie zapisu nie może dotknąć ostatniego bezpiecznego pliku.")
	_assert(_pause.is_open() and get_tree().paused, "Zablokowana próba zapisu powinna pozostać w menu pauzy.")

	_pause.continue_button.pressed.emit()
	await _frames(5)
	_assert(float(dive.session.elapsed_time) > elapsed_frozen, "Po KONTYNUUJ lokalny czas wyprawy powinien znów płynąć.")
	dive._open_inventory()
	await _frames(2)
	_assert(dive._inventory_panel.visible, "Test priorytetu powinien otworzyć lokalny plecak nurka.")
	await _press_key(KEY_ESCAPE)
	_assert(not dive._inventory_panel.visible, "Pierwszy ESC powinien zamknąć plecak istniejącą ścieżką DiveController.")
	_assert(not _pause.is_open() and not get_tree().paused, "Zamknięcie plecaka nie może równocześnie otworzyć pauzy.")
	await _press_key(KEY_ESCAPE)
	_assert(_pause.is_open() and get_tree().paused, "Dopiero kolejny ESC powinien zatrzymać wyprawę.")


func _test_direct_quit_intent_without_confirmation() -> void:
	_assert(_pause.is_open() and get_tree().paused, "Test wyjścia powinien działać z otwartego menu pauzy.")
	var production_connection: Callable
	for connection in _pause.quit_requested.get_connections():
		var callable: Callable = connection.get("callable", Callable())
		if callable.is_valid() and callable.get_object() == _game:
			production_connection = callable
			break
	_assert(production_connection.is_valid(), "Żądanie wyjścia PauseMenu powinno mieć produkcyjne połączenie do GameRoot.")
	if production_connection.is_valid():
		_assert(str(production_connection.get_method()) == "_on_pause_quit_requested", "Produkcja powinna delegować wyjście do bezpośredniego handlera GameRoot.")
		_pause.quit_requested.disconnect(production_connection)
	_pause.quit_requested.connect(_on_quit_requested_for_test)
	var runtime_phase_before := int(_game.game_state.current_phase)
	var saved_before = SaveManager.load_game()
	var confirmation_windows := _pause.find_children("*", "ConfirmationDialog", true, false)
	_assert(confirmation_windows.size() == 1 and not (confirmation_windows[0] as ConfirmationDialog).visible, "Tylko powrót do menu może posiadać ukryty dialog; WYJDŹ Z GRY nie może go otwierać.")
	_pause.quit_button.pressed.emit()
	await _frames(1)
	_assert(_quit_requests == 1, "Kliknięcie WYJDŹ Z GRY powinno natychmiast emitować dokładnie jedno żądanie zamknięcia.")
	_assert(not (confirmation_windows[0] as ConfirmationDialog).visible, "Bezpośrednie WYJDŹ Z GRY nie może pokazać potwierdzenia powrotu do menu.")
	_assert(_pause.is_open() and get_tree().paused, "Warstwa prezentacji nie powinna wznawiać wyprawy przed przekazaniem żądania quit.")
	_assert(int(_game.game_state.current_phase) == runtime_phase_before, "Bezpośrednie wyjście nie może zmieniać fazy ani przechodzić przez menu główne.")
	var saved_after = SaveManager.load_game()
	_assert(saved_before != null and saved_after != null and int(saved_after.current_phase) == int(saved_before.current_phase), "Kliknięcie WYJDŹ Z GRY nie może wykonać ukrytego autosave.")
	_pause.continue_button.pressed.emit()
	await _frames(2)


func _test_confirmed_main_menu_return_from_dive() -> void:
	_assert(_game.current_scene != null and _game.current_scene.name == "DiveScene", "Potwierdzany powrót powinien zostać sprawdzony podczas aktywnej wyprawy.")
	var safe_save_before = SaveManager.load_game()
	var campaign_id_before := str(safe_save_before.campaign_id) if safe_save_before != null else ""
	var phase_before := int(safe_save_before.current_phase) if safe_save_before != null else -1
	await _press_key(KEY_ESCAPE)
	await _frames(2)
	_assert(_pause.main_menu_note.text.contains("Cała niezakończona wyprawa zostanie utracona"), "Pauza wyprawy musi ostrzec o utracie całego nieukończonego nurkowania.")
	_pause.main_menu_button.pressed.emit()
	await _frames(2)
	var confirmation := _pause.find_child("MainMenuConfirmation", true, false) as ConfirmationDialog
	_assert(confirmation != null and confirmation.visible and confirmation.dialog_text.contains("Cała niezakończona wyprawa"), "Potwierdzenie podczas nurkowania musi powtórzyć ryzyko utraty wyprawy.")
	confirmation.get_ok_button().pressed.emit()
	await _frames(5)
	_assert(_game.current_scene != null and _game.current_scene.name == "MainMenu", "Potwierdzenie powinno wrócić do prawdziwego menu głównego.")
	_assert(_game.game_state == null, "Powrót do menu musi usunąć bieżący stan sesji ze skorupy runtime.")
	_assert(not _pause.is_open() and not get_tree().paused, "Przejście do menu musi zwolnić pauzę należącą do PauseMenu.")
	var safe_save_after = SaveManager.load_game()
	_assert(safe_save_after != null and str(safe_save_after.campaign_id) == campaign_id_before and int(safe_save_after.current_phase) == phase_before, "Powrót bez zapisu nie może utrwalić fazy DIVING ani zmienić ostatniego bezpiecznego zapisu.")


func _make_setup(day: int):
	var setup = ExpeditionSetupScript.new()
	setup.diver_id = "igor"
	setup.day = day
	setup.oxygen_capacity = 100.0
	setup.backpack_capacity = 6
	setup.diver_carry_capacity = 18.0
	setup.item_weights = {
		ResourceIdsScript.FOOD: 1.0,
		ResourceIdsScript.PLANKS: 1.2,
		ResourceIdsScript.SCRAP: 1.5,
	}
	setup.target_sector = "fixture_entry"
	setup.selected_objective = "basic_scavenge"
	setup.tutorial_mode = false
	return setup


func _press_key(keycode: int, shift_pressed: bool = false) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.shift_pressed = shift_pressed
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(1)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(1)


func _send_escape_echo() -> void:
	var press := InputEventKey.new()
	press.keycode = KEY_ESCAPE
	press.pressed = true
	press.echo = true
	Input.parse_input_event(press)
	await _frames(1)
	press.pressed = false
	press.echo = false
	Input.parse_input_event(press)
	await _frames(1)


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _on_quit_requested_for_test() -> void:
	_quit_requests += 1


func _test_file_exists(path: String) -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _pause != null and _pause.is_open():
		_pause.continue_button.pressed.emit()
	await _frames(2)
	get_tree().paused = false
	if _game != null:
		_game.queue_free()
	await _frames(2)
	SaveManager.reset_paths()
	_remove_test_saves()
	if _failed:
		get_tree().quit(1)
		return
	print("Pause menu flow test passed: ESC routing, settings, confirmed no-save menu return, safe manual save, dive blocker, focus and direct quit are valid.")
	get_tree().quit(0)


func _remove_test_saves() -> void:
	for path in [TEST_SAVE, TEST_PENDING, TEST_BACKUP]:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Pause menu flow test failed: " + message)
