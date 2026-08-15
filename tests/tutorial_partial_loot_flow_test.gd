extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const TutorialDirectorScript := preload("res://scripts/core/TutorialDirector.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const BuildingSystemScript := preload("res://scripts/base/BuildingSystem.gd")

var _failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GameRootScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	_assert(game.start_new_campaign("standard", 81204, false), "Izolowana kampania tutorialowa musi się uruchomić bez zapisu.")
	await get_tree().process_frame
	game.game_state.day = 2
	game.game_state.begin_new_day_plan()
	game.game_state.tutorial.step = TutorialStateScript.Step.BUILD_WORKSHOP
	var workshop_definition = ResourceLoader.load("res://data/buildings/workshop.tres")
	_assert(BuildingSystemScript.new().queue_construction(game.game_state, "bottom_left", workshop_definition), "Fixture dnia 2 musi legalnie odbudować Warsztat przed pierwszym zejściem.")
	game.game_state.tutorial.step = TutorialStateScript.Step.START_FIRST_DIVE
	_assert_tutorial_mode_asymmetries_are_rejected(game)
	if _failed:
		await _cleanup_game(game)
		get_tree().quit(1)
		return

	var setup = _make_setup(TutorialStateScript.Step.START_FIRST_DIVE)
	game.start_dive(setup)
	await get_tree().process_frame
	await get_tree().process_frame
	var dive = game.current_scene
	_assert(dive != null and dive.name == "DiveScene", "Pierwsze zejście musi otworzyć produkcyjną DiveScene.")
	if dive == null or dive.name != "DiveScene":
		await _cleanup_game(game)
		get_tree().quit(1)
		return
	_assert(dive.tutorial_step() == TutorialStateScript.Step.DIVE_MOVEMENT, "Start pierwszego zejścia musi rozpocząć lokalne prowadzenie ruchem.")
	_assert(game.game_state.tutorial.step == TutorialStateScript.Step.START_FIRST_DIVE, "Aktywna próba nie może przesuwać kursora tutoriala w GameState.")
	_assert(not game.tutorial_event(TutorialDirectorScript.DIVE_STARTED) and game.game_state.tutorial.step == TutorialStateScript.Step.START_FIRST_DIVE, "GameRoot musi odrzucać bezpośrednią mutację tutoriala podczas aktywnego nurkowania.")

	var food_crate = _find_container(dive, "tutorial_market_crate")
	var workshop_crate = _find_container(dive, "tutorial_workshop_case")
	var blockage = _find_persistent_interactable(dive, "SC-01")
	_assert(food_crate != null and workshop_crate != null, "Produkcjna mapa musi zawierać obie oznaczone skrzynie tutoriala.")
	_assert(blockage != null, "Produkcjna mapa musi zawierać blokadę kabla SC-01.")
	_assert(
		blockage != null
		and blockage.kind == DivePersistentInteractable.Kind.SHORTCUT
		and blockage.required_tool == "knife"
		and blockage.interaction_action == "cut",
		"SC-01 musi być fizyczną blokadą kabla przecinaną Nożem ratunkowym."
	)
	_assert(blockage == null or blockage.interaction_text().contains("przetnij"), "Podpowiedź SC-01 musi nazywać przecięcie blokady, nie zwykłe otwarcie skrótu.")
	_assert(not dive.session.has_tool("knife"), "Pierwsze zejście dnia 2 nie może wyposażać Noża przed jego wykonaniem w Warsztacie.")
	dive._update_ui()
	var direction_state: Dictionary = dive._tutorial_direction_indicator.state_for_tests()
	_assert(bool(direction_state.get("visible", false)) and str(direction_state.get("target_label", "")) == "ZASOBY", "Pierwsze zejście musi od początku pokazywać strzałkę wokół nurka prowadzącą do obowiązkowych zasobów.")
	if food_crate == null or workshop_crate == null:
		await _cleanup_game(game)
		get_tree().quit(1)
		return

	# Gracz może dopłynąć do skrzyni przed zakończeniem instrukcji ruchu i tlenu.
	# Interakcja ma zostać zapamiętana, a nie odrzucona przez dokładną bramkę kroku.
	dive._open_container(food_crate)
	_assert(dive.tutorial_step() == TutorialStateScript.Step.DIVE_MOVEMENT, "Wcześniejsze otwarcie skrzyni nie może pominąć instrukcji ruchu.")
	dive._take_pending_amount(ResourceIdsScript.FOOD, 1)
	dive._leave_pending_loot()
	_assert(dive.session.tutorial_opened_mandatory_orders.has(0), "Lokalna sesja musi zapamiętać wcześniejsze otwarcie pierwszej skrzyni.")
	_assert(dive._tutorial_event(TutorialDirectorScript.MOVEMENT_COMPLETED), "Po ruchu lokalny tutorial musi przejść do instrukcji tlenu.")
	dive._tutorial_step_time = 4.0
	dive._update_tutorial_progress()
	_assert(dive.tutorial_step() == TutorialStateScript.Step.DIVE_INVENTORY, "Po instrukcji tlenu wcześniejsze otwarcie skrzyni musi automatycznie zaliczyć krok 3.")
	_assert(game.game_state.tutorial.step == TutorialStateScript.Step.START_FIRST_DIVE, "Postęp sesji nadal nie może mutować kursora kampanii.")
	dive._try_return_to_surface()
	# Reprodukcja ostatniego update'u tej samej klatki po synchronicznej
	# wymianie sceny: odpięty HUD nie może już czytać viewportu.
	dive._update_ui()
	await get_tree().process_frame
	_assert(game.current_scene == dive and game.game_state.current_phase == GamePhaseScript.Phase.DIVING and dive.tutorial_step() == TutorialStateScript.Step.DIVE_INVENTORY, "Tutorialowej wyprawy nie wolno zakończyć przed obejrzeniem blokady i krokiem powrotu.")
	_assert(int(food_crate.contents.get(ResourceIdsScript.FOOD, 0)) == 5 and food_crate.can_interact(), "Po zabraniu jednej racji reszta żywności ma zostać w ponownie dostępnej skrzyni.")
	_assert(dive._mandatory_container_count() == 1, "Cel tutoriala ma prowadzić do drugiej skrzyni mimo częściowej zawartości pierwszej.")

	dive.diver.global_position = workshop_crate.global_position
	dive._open_container(workshop_crate)
	dive._take_pending_amount(ResourceIdsScript.PLANKS, 1)
	dive._take_pending_amount(ResourceIdsScript.SCRAP, 3)
	dive._take_pending_amount(ResourceIdsScript.FABRIC_RUBBER, 2)
	_assert(dive.tutorial_step() == TutorialStateScript.Step.DIVE_BLOCKED_PASSAGE, "Minimalny wskazany łup ma zakończyć krok skrzyń bez ich pełnego opróżnienia.")
	_assert(dive._has_required_tutorial_loot(), "Jedna żywność, jedna deska i koszt Noża muszą wystarczyć do powrotu.")
	dive._update_tutorial_progress()
	_assert(dive.tutorial_step() == TutorialStateScript.Step.DIVE_BLOCKED_PASSAGE, "Po zebraniu łupu przy skrzyni warsztatowej gracz nadal musi popłynąć kablem do SC-01.")
	dive._update_ui()
	direction_state = dive._tutorial_direction_indicator.state_for_tests()
	var expected_blockage_direction: Vector2 = (blockage.global_position - dive.diver.global_position).normalized() if blockage != null else Vector2.ZERO
	_assert(bool(direction_state.get("visible", false)) and str(direction_state.get("target_label", "")) == "BLOKADA KABLA", "Po zebraniu minimum strzałka musi przełączyć się na rzeczywistą blokadę kabla.")
	_assert(Vector2(direction_state.get("direction", Vector2.ZERO)).dot(expected_blockage_direction) > 0.99, "Strzałka dnia 2 musi wskazywać położenie SC-01.")
	dive._try_return_to_surface()
	await get_tree().process_frame
	_assert(game.current_scene == dive and game.game_state.current_phase == GamePhaseScript.Phase.DIVING and dive.tutorial_step() == TutorialStateScript.Step.DIVE_BLOCKED_PASSAGE, "Kompletny łup nie może ominąć obowiązkowego obejrzenia blokady przed powrotem.")
	_assert(int(workshop_crate.contents.get(ResourceIdsScript.PLANKS, 0)) == 3, "Nadmiar desek ma pozostać w skrzyni warsztatowej.")
	dive._leave_pending_loot()

	var pending_food: Dictionary = dive.session.remaining_container_contents.get("tutorial_market_crate", {})
	var pending_workshop: Dictionary = dive.session.remaining_container_contents.get("tutorial_workshop_case", {})
	_assert(int(pending_food.get(ResourceIdsScript.FOOD, 0)) == 5, "Lokalna sesja musi zachować pozostawioną żywność.")
	_assert(int(pending_workshop.get(ResourceIdsScript.PLANKS, 0)) == 3, "Lokalna sesja musi zachować pozostawione deski.")
	dive.diver.global_position = dive.dive_map.exit_line.global_position
	dive._update_tutorial_progress()
	_assert(dive.tutorial_step() == TutorialStateScript.Step.DIVE_BLOCKED_PASSAGE, "Sama bliskość liny nie może zaliczać oględzin odległej blokady kabla.")
	if blockage != null:
		dive.diver.global_position = blockage.global_position + Vector2(0.0, 80.0)
	dive._update_tutorial_progress()
	_assert(dive.tutorial_step() == TutorialStateScript.Step.DIVE_RETURN_TO_LINE, "Po obejrzeniu blokady tutorial ma wskazać powrót.")
	_assert(not dive.session.opened_shortcuts.has("SC-01") and blockage != null and not blockage.completed, "Dzień 2 ma tylko pokazać zamkniętą blokadę — bez Noża nie może jej otworzyć.")
	_assert(game.game_state.tutorial.step == TutorialStateScript.Step.START_FIRST_DIVE, "Kampania ma pozostać na baseline aż do transakcji bezpiecznego powrotu.")

	dive._try_return_to_surface()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var result = game.game_state.last_dive_result
	_assert(result != null and result.returned_alive, "Częściowy łup musi pozwolić na bezpieczne wynurzenie.")
	_assert(result == null or result.tutorial_outcome == null, "Przejściowy rezultat tutoriala nie może wejść do trwałego last_dive_result.")
	_assert(game.game_state.tutorial.step == TutorialStateScript.Step.STAFF_WORKSHOP, "Bezpieczny powrót z częściowym łupem musi kontynuować tutorial w bazie.")
	_assert(int(game.game_state.underwater_world.remaining_container_contents.get("tutorial_market_crate", {}).get(ResourceIdsScript.FOOD, 0)) == 5, "Powrót ma utrwalić żywność pozostawioną w pierwszej skrzyni.")
	_assert(int(game.game_state.underwater_world.remaining_container_contents.get("tutorial_workshop_case", {}).get(ResourceIdsScript.PLANKS, 0)) == 3, "Powrót ma utrwalić deski pozostawione w drugiej skrzyni.")
	_assert(not game.game_state.underwater_world.opened_containers.has("tutorial_market_crate") and not game.game_state.underwater_world.opened_containers.has("tutorial_workshop_case"), "Częściowych skrzyń nie wolno zapisać jako opróżnionych.")

	game.game_state.current_phase = GamePhaseScript.Phase.BASE_PLANNING
	game.show_base()
	await get_tree().process_frame
	await get_tree().process_frame
	var base = game.current_scene
	var workshop_slot = base.get_node_or_null("BaseEnvironment/PlatformBoard/BuildingSlots/Slot_bottom_left")
	_assert(workshop_slot != null, "Dzień 3 musi wskazywać produkcyjny slot Warsztatu.")
	if workshop_slot == null:
		await _cleanup_game(game)
		get_tree().quit(1)
		return
	workshop_slot.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var workshop_sidebar := base.find_child("BuildingStaffingSidePanel", true, false) as Control
	var worker_change := base.find_child("WorkerChangeButton", true, false) as Button
	_assert(workshop_sidebar != null and base.find_child("BuildingTabs", true, false) == null, "Otwarcie Warsztatu ma pokazać stały prawy pasek OBSADA bez zakładek. Wybrany slot: %s." % str(base._selected_slot_id))
	_assert(worker_change != null, "Prawy pasek OBSADA Warsztatu musi zawierać akcję otwarcia kafelków mieszkańców.")
	if workshop_sidebar == null or worker_change == null:
		await _cleanup_game(game)
		get_tree().quit(1)
		return
	worker_change.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var anka_tile := base.find_child("WorkerCandidate_anka", true, false) as Button
	_assert(anka_tile != null and not anka_tile.disabled, "Anka musi być dostępnym kafelkiem mieszkańca dla Warsztatu w tym scenariuszu.")
	if anka_tile == null or anka_tile.disabled:
		await _cleanup_game(game)
		get_tree().quit(1)
		return
	anka_tile.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	workshop_sidebar = base.find_child("BuildingStaffingSidePanel", true, false) as Control
	var knife_button := base.find_child("Craft_tutorial_rescue_knife", true, false) as Button
	_assert(game.game_state.tutorial.step == TutorialStateScript.Step.CRAFT_RESCUE_KNIFE, "Obsadzenie Warsztatu musi przejść do wykonania Noża.")
	_assert(workshop_sidebar != null and base.find_child("BuildingTabs", true, false) == null, "Po obsadzeniu Warsztatu pasek OBSADA pozostaje widoczny, a akcja Noża trafia do szerokiego obszaru DZIAŁANIE.")
	_assert(knife_button != null and knife_button.is_visible_in_tree() and not knife_button.disabled, "Akcja wykonania Noża musi być od razu widoczna i dostępna.")
	_assert(get_viewport().gui_get_focus_owner() == knife_button, "Po zmianie kroku fokus musi wskazywać akcję wykonania Noża, nie ukrytą kontrolkę OBSADY.")
	if knife_button == null or knife_button.disabled:
		await _cleanup_game(game)
		get_tree().quit(1)
		return
	game.show_base()
	await get_tree().process_frame
	await get_tree().process_frame
	base = game.current_scene
	workshop_slot = base.get_node_or_null("BaseEnvironment/PlatformBoard/BuildingSlots/Slot_bottom_left")
	workshop_slot.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	workshop_sidebar = base.find_child("BuildingStaffingSidePanel", true, false) as Control
	knife_button = base.find_child("Craft_tutorial_rescue_knife", true, false) as Button
	_assert(workshop_sidebar != null and knife_button != null and knife_button.is_visible_in_tree(), "Warsztat otwarty już po rekonsyliacji obsady także musi od razu pokazać szerokie DZIAŁANIE i Nóż.")
	knife_button.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(game.game_state.tutorial.step == TutorialStateScript.Step.START_FINAL_DIVE and game.game_state.story_flags.rescue_knife_unlocked, "Wykonanie Noża z widocznej akcji musi odblokować finałowe zejście.")

	var final_setup = _make_setup(TutorialStateScript.Step.START_FINAL_DIVE, true)
	final_setup.day = 3
	game.start_dive(final_setup)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	dive = game.current_scene
	_assert(dive != null and dive.name == "DiveScene" and dive.tutorial_step() == TutorialStateScript.Step.ACTIVATE_JUNCTION_J7, "Finałowe zejście musi otworzyć lokalne prowadzenie do J-7.")
	_assert(game.game_state.tutorial.step == TutorialStateScript.Step.START_FINAL_DIVE, "Finałowa próba nie może przesunąć kursora kampanii przed powrotem.")
	if dive == null or dive.name != "DiveScene":
		await _cleanup_game(game)
		get_tree().quit(1)
		return
	dive._update_ui()
	await get_tree().process_frame
	var junction = _find_persistent_interactable(dive, "junction_j7")
	blockage = _find_persistent_interactable(dive, "SC-01")
	_assert(junction != null, "Produkcjna mapa dnia 3 musi udostępniać Węzeł J-7.")
	_assert(blockage != null and not blockage.completed, "Finałowe zejście musi rozpocząć się z zamkniętą SC-01.")
	_assert(dive.session.has_tool("knife"), "Finałowe zejście musi wyposażyć wykonany Nóż ratunkowy.")
	direction_state = dive._tutorial_direction_indicator.state_for_tests()
	expected_blockage_direction = (blockage.global_position - dive.diver.global_position).normalized() if blockage != null else Vector2.ZERO
	_assert(bool(direction_state.get("visible", false)) and str(direction_state.get("target_label", "")) == "BLOKADA KABLA", "Strzałka finałowego zejścia musi najpierw wskazywać zamkniętą SC-01.")
	_assert(Vector2(direction_state.get("direction", Vector2.ZERO)).dot(expected_blockage_direction) > 0.99, "Strzałka tutoriala musi zachować pełny kierunek blokady, także po skosie.")
	_assert(dive._tutorial_panel.size.y <= 112.0 and dive._tutorial_body.visible and dive._tutorial_body.text.contains("Powrót jest zablokowany"), "Przyczyna blokady powrotu musi być stale widoczna bez tooltipa w kompaktowym panelu.")
	_assert(dive._compact_objective_text().contains("BLOKADA KABLA") and not dive._compact_objective_text().contains("WĘZEŁ J-7"), "Przed przecięciem nawigacja ma prowadzić do SC-01, nie omijać jej celem J-7.")
	dive._interaction_target = dive.dive_map.exit_line
	dive._update_interaction_panel()
	_assert(dive._interaction_label.text.contains("POWRÓT ZABLOKOWANY") and dive._interaction_label.text.contains("BLOKADĘ KABLA") and not dive._interaction_bar.visible, "Przy linie gracz musi zobaczyć pierwszą wymaganą akcję zamiast obietnicy powrotu.")
	dive._try_return_to_surface()
	_assert(game.current_scene == dive and game.game_state.current_phase == GamePhaseScript.Phase.DIVING and dive.tutorial_step() == TutorialStateScript.Step.ACTIVATE_JUNCTION_J7, "Próba powrotu przed J-7 ma pozostać zablokowana bez zmiany kroku.")
	if junction != null:
		dive._complete_persistent_interaction(junction)
	_assert(not dive.session.activated_fixed_devices.has("junction_j7") and dive.tutorial_step() == TutorialStateScript.Step.ACTIVATE_JUNCTION_J7, "Nie wolno aktywować J-7 przed lokalnym przecięciem SC-01, nawet po dotarciu objazdem.")
	if blockage != null:
		dive._complete_persistent_interaction(blockage)
	_assert(dive.session.opened_shortcuts.has("SC-01") and blockage != null and blockage.completed, "Przecięcie SC-01 ma otworzyć fizyczne przejście w lokalnej sesji.")
	dive._update_ui()
	direction_state = dive._tutorial_direction_indicator.state_for_tests()
	var expected_junction_direction: Vector2 = (junction.global_position - dive.diver.global_position).normalized() if junction != null else Vector2.ZERO
	_assert(bool(direction_state.get("visible", false)) and str(direction_state.get("target_label", "")) == "WĘZEŁ J-7", "Po przecięciu SC-01 strzałka musi przełączyć się na Węzeł J-7.")
	_assert(Vector2(direction_state.get("direction", Vector2.ZERO)).dot(expected_junction_direction) > 0.99, "Po przecięciu kierunek celu musi wskazywać rzeczywiste J-7.")
	dive.session.oxygen_left = dive.session.oxygen_capacity * 0.09
	dive._update_ui()
	_assert(dive._warning_label.text == "TLEN KRYTYCZNY", "Alarm krytycznego tlenu musi zachować najwyższy priorytet.")
	_assert(dive._tutorial_body.visible and dive._tutorial_body.text.contains("Powrót jest zablokowany"), "Alarm tlenu nie może ukryć trwałej instrukcji odblokowania powrotu.")
	dive.session.oxygen_left = 0.0
	dive._on_oxygen_depleted()
	dive._retry_tutorial_dive()
	_assert(is_equal_approx(dive.session.oxygen_left, dive.session.oxygen_capacity), "Ponowienie próby ma natychmiast odtworzyć pełny zapas tlenu.")
	_assert(dive.tutorial_step() == TutorialStateScript.Step.ACTIVATE_JUNCTION_J7, "Ponowienie próby nie może pominąć obowiązkowego J-7.")
	_assert(dive.session.tutorial_event_ids.size() == 1 and dive.session.tutorial_event_ids[0] == TutorialDirectorScript.DIVE_STARTED, "Retry musi odtworzyć rezultat tutoriala wyłącznie z baseline nowej próby.")
	_assert(game.game_state.tutorial.step == TutorialStateScript.Step.START_FINAL_DIVE, "Retry nie może mutować kursora tutoriala kampanii.")
	blockage = _find_persistent_interactable(dive, "SC-01")
	_assert(blockage != null and not blockage.completed and not dive.session.opened_shortcuts.has("SC-01"), "Retry musi ponownie zamknąć SC-01 i usunąć lokalny skutek przecięcia.")
	await get_tree().process_frame
	dive._update_ui()
	_assert(dive.session.oxygen_left > 0.0 and dive.session.oxygen_left <= dive.session.oxygen_capacity, "Po resecie sesja ma wznowić zwykłe zużycie tlenu od pełnego zapasu.")
	_assert(dive.tutorial_step() == TutorialStateScript.Step.ACTIVATE_JUNCTION_J7, "Wznowiona sesja nadal musi prowadzić do J-7.")
	_assert(dive._tutorial_body.visible and dive._tutorial_body.text.contains("Powrót jest zablokowany") and dive._compact_objective_text().contains("BLOKADA KABLA"), "Po resecie stała instrukcja i pierwszy cel SC-01 muszą zostać odtworzone.")
	junction = _find_persistent_interactable(dive, "junction_j7")
	dive._interaction_target = null
	if blockage != null:
		dive._complete_persistent_interaction(blockage)
	if junction != null:
		dive._complete_persistent_interaction(junction)
	dive._update_ui()
	_assert(dive.tutorial_step() == TutorialStateScript.Step.FINAL_RETURN_TO_LINE, "Aktywacja J-7 musi natychmiast zmienić lokalny cel na bezpieczny powrót.")
	_assert(game.game_state.tutorial.step == TutorialStateScript.Step.START_FINAL_DIVE, "Aktywacja J-7 pozostaje lokalna do transakcji bezpiecznego powrotu.")
	_assert(dive._compact_objective_text().contains("CEL: LINA") and dive._tutorial_body.text.contains("bezpieczny powrót"), "Po J-7 nawigacja i stały opis muszą prowadzić do głównej liny.")
	direction_state = dive._tutorial_direction_indicator.state_for_tests()
	var expected_line_direction: Vector2 = (dive.dive_map.exit_line.global_position - dive.diver.global_position).normalized()
	_assert(bool(direction_state.get("visible", false)) and str(direction_state.get("target_label", "")) == "LINA", "Po aktywacji J-7 strzałka wokół nurka musi natychmiast przełączyć się na linię.")
	_assert(Vector2(direction_state.get("direction", Vector2.ZERO)).dot(expected_line_direction) > 0.99, "Strzałka powrotu musi wskazywać rzeczywiste położenie głównej liny.")
	dive._try_return_to_surface()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not game.game_state.tutorial.is_active(), "Dopiero bezpieczny powrót po J-7 powinien zakończyć tutorial.")
	_assert(game.game_state.underwater_world.activated_fixed_devices.has("junction_j7"), "Zakończony powrót musi utrwalić aktywację J-7.")
	_assert(game.game_state.underwater_world.opened_shortcuts.has("SC-01"), "Zakończony powrót musi razem z J-7 utrwalić przecięcie SC-01.")

	if _failed:
		await _cleanup_game(game)
		get_tree().quit(1)
		return
	print("Tutorial flow UI test passed: partial loot persists, the Workshop reveals the knife action, and the J-7 return blocker stays explicit.")
	await _cleanup_game(game)
	get_tree().quit(0)


func _make_setup(tutorial_baseline_step: int, include_knife: bool = false):
	var setup = ExpeditionSetupScript.new()
	setup.diver_id = "igor"
	setup.diver_display_name = "Igor Sowa"
	setup.day = 2
	setup.diver_health = 100
	setup.diver_health_capacity = 100
	setup.oxygen_capacity = 100.0
	setup.backpack_capacity = 6
	setup.diver_carry_capacity = 24.0
	setup.item_weights = {
		ResourceIdsScript.FOOD: 1.0,
		ResourceIdsScript.PLANKS: 1.0,
		ResourceIdsScript.SCRAP: 1.0,
		ResourceIdsScript.FABRIC_RUBBER: 1.0,
	}
	setup.selected_gear.assign(["crowbar", "repair_kit", "diving_lantern_mk1"])
	if include_knife:
		setup.selected_gear.append("knife")
	setup.equipped_gear = {"light": "diving_lantern_mk1"}
	setup.suit_quality = 1
	setup.tutorial_mode = true
	setup.tutorial_baseline_step = tutorial_baseline_step
	setup.difficulty_modifiers = {
		"oxygen_use_multiplier": 1.0,
		"suit_damage_multiplier": 1.0,
		"cold_rate_multiplier": 1.0,
		"threat_aggression_multiplier": 1.0,
		"current_strength_multiplier": 1.0,
		"noise_range_multiplier": 1.0,
	}
	return setup


func _find_container(dive, container_id: String):
	for container in dive.dive_map.containers:
		if container.container_id == container_id:
			return container
	return null


func _find_persistent_interactable(dive, persistent_id: String):
	for target in dive.dive_map.persistent_interactables:
		if target.persistent_id == persistent_id:
			return target
	return null


func _assert_tutorial_mode_asymmetries_are_rejected(game) -> void:
	var active_tutorial_step := int(game.game_state.tutorial.step)
	var non_tutorial_setup = _make_setup(active_tutorial_step)
	non_tutorial_setup.tutorial_mode = false
	_assert_rejected_start_is_non_mutating(
		game,
		non_tutorial_setup,
		"aktywna kampania tutorialowa z nietutorialowym setupem"
	)
	if int(game.game_state.current_phase) == GamePhaseScript.Phase.DIVING:
		return

	game.game_state.tutorial.complete()
	var tutorial_setup = _make_setup(active_tutorial_step)
	_assert_rejected_start_is_non_mutating(
		game,
		tutorial_setup,
		"nieaktywna kampania tutorialowa z tutorialowym setupem"
	)
	game.game_state.tutorial.step = active_tutorial_step


func _assert_rejected_start_is_non_mutating(game, rejected_setup, case_label: String) -> void:
	var state_before = game.game_state
	var plan_before = state_before.current_day_plan
	var plan_snapshot_before := _day_plan_snapshot(plan_before)
	var phase_before := int(state_before.current_phase)
	var expedition_setup_before = state_before.current_expedition_setup
	var tutorial_step_before := int(state_before.tutorial.step)
	var diver_before = state_before.find_survivor(str(rejected_setup.diver_id))
	var diver_status_before := int(diver_before.status) if diver_before != null else -1
	var scene_before = game.current_scene

	game.start_dive(rejected_setup)

	_assert(game.game_state == state_before, "Odrzucony start nie może podmienić GameState: %s." % case_label)
	_assert(game.current_scene == scene_before, "Odrzucony start nie może zmienić sceny: %s." % case_label)
	_assert(int(game.game_state.current_phase) == phase_before, "Odrzucony start nie może zmienić fazy: %s." % case_label)
	_assert(game.game_state.current_day_plan == plan_before, "Odrzucony start nie może podmienić planu dnia: %s." % case_label)
	_assert(_day_plan_snapshot(game.game_state.current_day_plan) == plan_snapshot_before, "Odrzucony start nie może mutować planu dnia: %s." % case_label)
	_assert(game.game_state.current_expedition_setup == expedition_setup_before, "Odrzucony start nie może przypisać setupu do GameState: %s." % case_label)
	_assert(int(game.game_state.tutorial.step) == tutorial_step_before, "Odrzucony start nie może zmienić kursora tutoriala: %s." % case_label)
	var diver_after = game.game_state.find_survivor(str(rejected_setup.diver_id))
	_assert(diver_after != null and int(diver_after.status) == diver_status_before, "Odrzucony start nie może zmienić statusu nurka: %s." % case_label)


func _day_plan_snapshot(plan) -> String:
	if plan == null:
		return "<null>"
	return var_to_str({
		"day": int(plan.day),
		"locked": bool(plan.locked),
		"ration_policy": int(plan.ration_policy),
		"building_work_paces": plan.building_work_paces.duplicate(true),
		"worker_assignments": plan.worker_assignments.duplicate(true),
		"building_orders": plan.building_orders.duplicate(true),
		"medical_priority_survivor_ids": plan.medical_priority_survivor_ids.duplicate(),
		"isolated_survivor_ids": plan.isolated_survivor_ids.duplicate(),
		"expedition_entry_point": str(plan.expedition_entry_point),
		"expedition_setup": plan.expedition_setup,
	})


func _picker_index_for(picker: OptionButton, survivor_id: String) -> int:
	if picker == null:
		return -1
	for index in range(picker.item_count):
		if str(picker.get_item_metadata(index)) == survivor_id:
			return index
	return -1


func _cleanup_game(game) -> void:
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
	push_error("Tutorial partial loot flow test failed: " + message)
