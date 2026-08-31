extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")

const CAPTURE_RESOLUTION := Vector2i(1280, 720)
const EXPECTED_NAVIGATION_ORDER := [
	"top_left",
	"top_center",
	"top_right",
	"bottom_left",
	"center",
	"bottom_right",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_viewport().gui_disable_input = true
	var game = GameRootScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	game.start_new_campaign("standard", 9041, false)
	await _settle()
	# Ten test izoluje workspace bazy; dialog fabularny ma własny kontrakt i
	# osobny snapshot, więc nie może przyciemniać dowodu wizualnego panelu.
	game.narrative_dialogue_panel.clear()
	await _settle()

	var state = game.game_state
	var base_scene = game.current_scene
	if base_scene.has_method("set_animation_time_for_tests"):
		base_scene.set_animation_time_for_tests(1.7)
	_ensure_built_workshop(state)
	state.tutorial.complete()
	if state.current_day_plan != null:
		state.current_day_plan.locked = false
	base_scene.bind(game, state)
	await _settle()

	var workshop_slot := base_scene.find_child("Slot_bottom_left", true, false) as Control
	_assert(workshop_slot != null, "Brakuje kanonicznego slotu Warsztatu.")
	if workshop_slot == null:
		return
	workshop_slot.emit_signal("pressed")
	await _settle()

	var modal := base_scene.find_child("BuildingModal", true, false) as ColorRect
	var workspace := base_scene.find_child("BuildingManagementWorkspace", true, false) as Control
	var resource_bar := base_scene.find_child("ResourceBar", true, false) as Control
	var end_day := base_scene.find_child("EndDayButton", true, false) as Button
	var rail := base_scene.find_child("BuildingNavigationRail", true, false) as Control
	var rail_scroll := base_scene.find_child("BuildingNavigationScroll", true, false) as ScrollContainer
	var navigation := base_scene.find_child("BuildingNavigationList", true, false) as VBoxContainer
	var panel := base_scene.find_child("BuildingPanel", true, false) as Control
	var title := base_scene.find_child("BuildingTitleLabel", true, false) as Label
	var header := base_scene.find_child("BuildingWorkspaceHeader", true, false) as Control
	var header_art := base_scene.find_child("BuildingHeaderArt", true, false) as TextureRect
	var action_scroll := base_scene.find_child("PanelScroll", true, false) as ScrollContainer
	var sidebar := base_scene.find_child("BuildingRightSidebar", true, false) as Control
	var staffing_sidebar := base_scene.find_child("BuildingStaffingSidePanel", true, false) as Control
	var construction_sidebar := base_scene.find_child("BuildingConstructionSidePanel", true, false) as Control
	var tutorial := base_scene.find_child("TutorialPanel", true, false) as Control
	var campaign_panel := base_scene.find_child("CampaignPanel", true, false) as Control
	_assert(modal != null and workspace != null and resource_bar != null and end_day != null and rail != null and rail_scroll != null and navigation != null and panel != null, "Tryb zarządzania wymaga przezroczystego blockera, aktywnego HUD-u, workspace, szyny i BuildingPanel.")
	if modal == null or workspace == null or resource_bar == null or end_day == null or rail == null or rail_scroll == null or navigation == null or panel == null:
		return

	var viewport_rect := Rect2(Vector2.ZERO, Vector2(CAPTURE_RESOLUTION))
	var workspace_rect := workspace.get_global_rect()
	_assert(modal.visible and panel.visible, "Otwarcie budynku musi pokazać Tryb Zarządzania Bazą.")
	_assert(is_zero_approx(modal.color.a) and modal.mouse_filter == Control.MOUSE_FILTER_STOP, "Pełnoekranowy blocker ma być wizualnie przezroczysty, ale zatrzymywać wejście do platformy.")
	_assert(viewport_rect.encloses(workspace_rect) and workspace_rect.position.x >= 60.0 and workspace_rect.position.y >= 64.0, "Workspace ma pozostawiać widoczne boczne obrzeża i osobny pas górnego HUD-u.")
	_assert(workspace_rect.end.x <= 1220.0 and workspace_rect.end.y <= 640.0 and workspace_rect.get_area() < viewport_rect.get_area() * 0.75, "Workspace ma być zauważalnie mniejszy od ekranu i odsłaniać bazę dookoła.")
	_assert(resource_bar.get_global_rect().end.y < workspace_rect.position.y and not end_day.get_global_rect().intersects(workspace_rect), "Workspace nie może przecinać górnego panelu ani przycisku ZAKOŃCZ DZIEŃ.")
	_assert(resource_bar.z_index > modal.z_index and end_day.z_index > modal.z_index, "Górny panel i ZAKOŃCZ DZIEŃ muszą znajdować się nad blockerem wejścia.")
	_assert(panel.size.x >= 720.0 and panel.size.y >= 560.0, "Centralny Panel budynku ma czytelnie wypełniać przestrzeń pomiędzy dwiema szynami.")
	_assert(not end_day.disabled, "Kadr kontrolny ma pokazywać aktywny przycisk ZAKOŃCZ DZIEŃ nad otwartym budynkiem.")
	_assert(rail.size.x >= 110.0 and rail.get_global_rect().end.y <= workspace.get_global_rect().end.y + 0.5, "Lewa szyna ma pozostać czytelna i mieścić się w workspace.")
	_assert(navigation.get_child_count() == EXPECTED_NAVIGATION_ORDER.size(), "Lewa szyna musi zawierać dokładnie sześć kafelków.")
	_assert(rail_scroll.scroll_vertical == 0, "Przy 1280×720 sześć podstawowych kafelków nie może wymagać przewijania.")
	_assert(header != null and header.visible and header_art != null and header_art.texture != null and action_scroll != null and sidebar != null and staffing_sidebar != null and construction_sidebar != null, "Panel musi mieć stały morski nagłówek z ilustracją budynku, szerokie DZIAŁANIE i dwa obszary prawego paska.")
	_assert(sidebar != null and action_scroll != null and sidebar.size.x >= 250.0 and sidebar.size.x <= 280.0 and action_scroll.size.x > sidebar.size.x * 2.5, "Prawy pasek OBSADA/BUDOWA ma zachować szerokość referencyjnej karty, a DZIAŁANIE ma otrzymać zdecydowaną większość szerokości.")
	_assert(sidebar != null and sidebar.get_parent() == workspace and not panel.is_ancestor_of(sidebar), "Prawa szyna ma być niezależnym sąsiadem centralnego Panelu, analogicznie do lewej nawigacji.")
	_assert(staffing_sidebar != null and construction_sidebar != null and staffing_sidebar.get_global_rect().end.y + 10.0 <= construction_sidebar.get_global_rect().position.y, "OBSADA oraz BUDOWA/ROZBUDOWA muszą pozostać oddzielnymi kartami prawej kolumny.")
	_assert(base_scene.find_child("BuildingTabs", true, false) == null and base_scene.find_child("BuildingWorkspaceFooter", true, false) == null, "Obsada i rozbudowa nie mogą pozostać zdublowanymi zakładkami ani dolną stopką.")
	var staffing_rail := sidebar.find_child("BuildingStaffingRail", true, false) as Control
	_assert(staffing_rail != null and sidebar.find_child("UpgradeButton", true, false) != null, "Prawy pasek musi pokazywać obsadę oraz przycisk rozbudowy.")
	_assert(_staffing_card_contract_holds(staffing_sidebar, staffing_rail), "Karta OBSADA ma zachować ciemną ramę, portret, tożsamość, zmęczenie oraz akcję ZMIEŃ.")
	_assert(tutorial != null and not tutorial.visible, "Ukończony tutorial nie może pokazywać nieaktywnej kapsuły nad panelem budynku.")
	_assert(campaign_panel != null and not campaign_panel.visible, "Tracker kampanii ma ustąpić przezroczystym obrzeżom, aby nie konkurować z widokiem bazy.")
	_assert(title != null and title.text.contains("Warsztat"), "Po otwarciu slotu panel musi jednoznacznie nazwać Warsztat.")
	_assert(_navigation_contract_holds(navigation, "bottom_left"), "Kafelki muszą zachować kanoniczną kolejność, miniatury, stan tekstowy i zaznaczenie Warsztatu.")
	_assert_building_scrolls_start_at_top(panel, sidebar, "otwarciu Warsztatu")
	var focus_owner := get_viewport().gui_get_focus_owner()
	_assert(focus_owner != null and workspace.is_ancestor_of(focus_owner), "Workspace musi rozpocząć pracę z fokusem w wybranym budynku.")
	_assert(_marine_shell_warm_workspace_contract_holds(resource_bar, panel, header, rail, staffing_sidebar, construction_sidebar), "Górny HUD oraz obie szyny muszą tworzyć ciemną morską powłokę, a centralny BuildingPanel — jasną, ciepłą przestrzeń z morskim nagłówkiem.")

	if not await _save_snapshot("base_management_workshop.png"):
		return

	var station_button := base_scene.find_child("BuildingNav_bottom_right", true, false) as Button
	_assert(station_button != null, "Szyna musi udostępniać kafelek Stacji Nurkowej.")
	if station_button == null:
		return
	station_button.emit_signal("pressed")
	await _settle()
	title = base_scene.find_child("BuildingTitleLabel", true, false) as Label
	_assert(modal.visible and panel.visible and title != null and title.text.contains("Stacja Nurkowa"), "Kafelek ma przełączyć zawartość na Stację bez zamykania workspace.")
	_assert(bool(station_button.get_meta("selected", false)), "Kafelek Stacji musi potwierdzić wybór nie tylko kolorem.")
	_assert_building_scrolls_start_at_top(panel, sidebar, "przełączeniu na Stację Nurkową")
	var workshop_button := base_scene.find_child("BuildingNav_bottom_left", true, false) as Button
	_assert(workshop_button != null and not bool(workshop_button.get_meta("selected", false)), "Po zmianie kontekstu poprzedni kafelek nie może pozostać zaznaczony.")

	var outside_event := InputEventMouseButton.new()
	outside_event.button_index = MOUSE_BUTTON_LEFT
	outside_event.pressed = true
	outside_event.position = Vector2(18, 360)
	outside_event.global_position = outside_event.position
	base_scene._on_modal_background_gui_input(outside_event)
	await _settle()
	_assert(modal.visible and bool(station_button.get_meta("selected", false)), "Kliknięcie przezroczystego obrzeża nie może zamknąć trybu ani zgubić wybranego budynku.")

	var close_button := panel.find_child("CloseButton", true, false) as Button
	_assert(close_button != null, "Pełnoekranowy tryb musi mieć jawny przycisk zamknięcia.")
	if close_button != null:
		close_button.emit_signal("pressed")
		await _settle()
		var station_slot := base_scene.find_child("Slot_bottom_right", true, false) as Control
		_assert(not modal.visible and station_slot != null and get_viewport().gui_get_focus_owner() == station_slot, "Zamknięcie musi zwrócić fokus do ostatnio wybranego slotu.")

	var workshop = state.find_building_by_definition("workshop")
	state.buildings.erase(workshop)
	var workshop_slot_data: Dictionary = state.platform.slot_states["bottom_left"]
	workshop_slot_data["building_id"] = ""
	state.platform.slot_states["bottom_left"] = workshop_slot_data
	state.day = 2
	state.tutorial.step = TutorialStateScript.Step.BUILD_WORKSHOP
	base_scene.bind(game, state)
	await _settle()
	workshop_slot.emit_signal("pressed")
	await _settle()

	var tutorial_title := base_scene.find_child("TutorialTitle", true, false) as Label
	var tutorial_body := base_scene.find_child("TutorialBody", true, false) as Label
	var tutorial_close := panel.find_child("CloseButton", true, false) as Button
	construction_sidebar = base_scene.find_child("BuildingConstructionSidePanel", true, false) as Control
	var build_button: Button = construction_sidebar.find_child("BuildButton", true, false) as Button if construction_sidebar != null else null
	workspace_rect = workspace.get_global_rect()
	_assert(modal.visible and panel.visible and tutorial.visible, "Kadr tutoriala wymaga otwartego Warsztatu i widocznej kapsuły prowadzenia.")
	_assert(tutorial.z_index > modal.z_index and tutorial.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Kapsuła tutoriala musi być nad menu i przepuszczać jego wejście.")
	_assert(tutorial.get_global_rect().intersects(workspace_rect), "Kapsuła prowadzenia ma być wizualnie nałożona na otwarte menu Warsztatu.")
	_assert(tutorial_close != null and not tutorial.get_global_rect().intersects(tutorial_close.get_global_rect()), "Kapsuła prowadzenia nie może wizualnie zasłonić przycisku zamknięcia menu.")
	_assert(tutorial_title != null and tutorial_title.text == "DZIEŃ 2  •  WARSZTAT", "Kadr musi pokazywać pełny tytuł kroku Warsztatu.")
	_assert(tutorial_body != null and "Odbuduj podświetlony Warsztat Odzysku I." in tutorial_body.text, "Kadr musi zachować pełne polecenie odbudowy Warsztatu.")
	_assert(build_button != null and construction_sidebar != null and construction_sidebar.is_ancestor_of(build_button), "Odbudowa ma pozostać w dolnej części prawego paska razem z kosztami.")
	_assert(get_viewport().gui_get_focus_owner() == build_button, "Przycisk ODBUDUJ w zewnętrznej prawej szynie ma otrzymać fokus tutoriala.")
	if not await _save_snapshot("base_management_workshop_tutorial.png"):
		return

	game.queue_free()
	await get_tree().process_frame
	print("Base management workspace snapshot passed: transparent inset layout, dominant action column, narrow staffing/build sidebar, active HUD clearance, six-tile navigation, tutorial overlay, marine-shell/warm-workspace palette, focus and close paths satisfy ARD-0090 and ARD-0091.")
	get_tree().quit(0)


func _ensure_built_workshop(state) -> void:
	var workshop = state.find_building_by_definition("workshop")
	if workshop == null:
		workshop = BuildingStateScript.new()
		workshop.id = "base_management_snapshot_workshop"
		workshop.definition_id = "workshop"
		workshop.slot_id = "bottom_left"
		state.buildings.append(workshop)
	workshop.level = 1
	workshop.is_built = true
	workshop.condition = 100
	var residents: Array = state.get_alive_survivors()
	if not residents.is_empty():
		var worker = residents[0]
		var assigned_ids: Array[String] = [str(worker.id)]
		workshop.assigned_survivor_ids = assigned_ids
		worker.current_assignment = workshop.id
	var slot_data: Dictionary = state.platform.slot_states["bottom_left"]
	slot_data["building_id"] = workshop.id
	state.platform.slot_states["bottom_left"] = slot_data


func _navigation_contract_holds(navigation: VBoxContainer, selected_slot_id: String) -> bool:
	for index in range(EXPECTED_NAVIGATION_ORDER.size()):
		var slot_id: String = EXPECTED_NAVIGATION_ORDER[index]
		var button := navigation.get_child(index) as Button
		if button == null or button.name != "BuildingNav_%s" % slot_id:
			return false
		var icon := button.find_child("BuildingNavIcon", true, false) as TextureRect
		var label := button.find_child("BuildingNavLabel", true, false) as Label
		if icon == null or icon.texture == null or label == null or label.text.strip_edges().is_empty():
			return false
		if str(button.get_meta("state_text", "")).is_empty():
			return false
		if bool(button.get_meta("selected", false)) != (slot_id == selected_slot_id):
			return false
	return true


func _assert_building_scrolls_start_at_top(panel: Control, sidebar: Control, context: String) -> void:
	var scrolls: Array[ScrollContainer] = []
	for root in [panel, sidebar]:
		if root == null:
			continue
		for node in root.find_children("*", "ScrollContainer", true, false):
			var scroll := node as ScrollContainer
			if scroll != null and not scrolls.has(scroll):
				scrolls.append(scroll)
	_assert(not scrolls.is_empty(), "Panel budynku musi zawierać przewijane sekcje do kontroli pozycji po %s." % context)
	for scroll in scrolls:
		_assert(scroll.scroll_vertical == 0, "Sekcja %s musi rozpocząć się od góry po %s." % [scroll.name, context])


func _marine_shell_warm_workspace_contract_holds(
	resource_bar: Control,
	panel: Control,
	header: Control,
	rail: Control,
	staffing_sidebar: Control,
	construction_sidebar: Control,
) -> bool:
	var resource_style := resource_bar.get_theme_stylebox("panel") as StyleBoxFlat
	var panel_style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	var header_style := header.get_theme_stylebox("panel") as StyleBoxFlat
	var rail_style := rail.get_theme_stylebox("panel") as StyleBoxFlat
	var staffing_style := staffing_sidebar.get_theme_stylebox("panel") as StyleBoxFlat if staffing_sidebar != null else null
	var construction_style := construction_sidebar.get_theme_stylebox("panel") as StyleBoxFlat if construction_sidebar != null else null
	if resource_style == null or panel_style == null or header_style == null or rail_style == null or staffing_style == null or construction_style == null:
		return false
	return (
		_is_dark_marine(resource_style.bg_color)
		and _is_teal_structure(resource_style.border_color)
		and _is_dark_marine(header_style.bg_color)
		and _is_teal_structure(header_style.border_color)
		and _is_dark_marine(rail_style.bg_color)
		and _is_teal_structure(rail_style.border_color)
		and _is_dark_marine(staffing_style.bg_color)
		and _is_teal_structure(staffing_style.border_color)
		and _is_dark_marine(construction_style.bg_color)
		and _is_teal_structure(construction_style.border_color)
		and _is_warm_bright_surface(panel_style.bg_color)
		and _is_warm_separator(panel_style.border_color)
	)


func _is_dark_marine(color: Color) -> bool:
	return (
		color.r <= 0.16
		and color.g <= 0.40
		and color.b <= 0.45
		and color.g >= color.r + 0.08
		and color.b >= color.g * 0.85
	)


func _is_teal_structure(color: Color) -> bool:
	return color.g >= 0.25 and color.g >= color.r * 1.25 and color.b >= color.r * 1.25


func _is_warm_bright_surface(color: Color) -> bool:
	return color.r >= 0.75 and color.g >= 0.70 and color.b >= 0.60 and color.r >= color.b + 0.05


func _is_warm_separator(color: Color) -> bool:
	return color.r >= 0.60 and color.g >= 0.50 and color.b >= 0.36 and color.r >= color.b + 0.10


func _staffing_card_contract_holds(sidebar: Control, staffing_rail: Control) -> bool:
	if sidebar == null or staffing_rail == null:
		return false
	var sidebar_style := sidebar.get_theme_stylebox("panel") as StyleBoxFlat
	var rail_style := staffing_rail.get_theme_stylebox("panel") as StyleBoxFlat
	var occupant := staffing_rail.find_child("WorkerOccupantLabel", true, false) as Label
	var fatigue := staffing_rail.find_child("WorkerFatigueLabel", true, false) as Label
	var change := staffing_rail.find_child("WorkerChangeButton", true, false) as Button
	if sidebar_style == null or rail_style == null or occupant == null or fatigue == null or change == null:
		return false
	var visible_rect := sidebar.get_global_rect()
	for control in [occupant, fatigue, change]:
		if not visible_rect.encloses(control.get_global_rect()):
			return false
	var has_dark_teal_shell := (
		_is_dark_marine(sidebar_style.bg_color)
		and _is_teal_structure(sidebar_style.border_color)
		and _is_dark_marine(rail_style.bg_color)
	)
	return (
		has_dark_teal_shell
		and not occupant.text.strip_edges().is_empty()
		and fatigue.text.begins_with("ZMĘCZENIE")
		and change.text == "ZMIEŃ"
	)


func _save_snapshot(file_name: String) -> bool:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_size() != CAPTURE_RESOLUTION:
		push_error("Zrzut trybu zarządzania ma rozmiar %s zamiast %s." % [str(image.get_size()), str(CAPTURE_RESOLUTION)])
		get_tree().quit(1)
		return false
	var output_dir := ProjectSettings.globalize_path("user://test_base_snapshots")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var error := image.save_png(output_dir.path_join(file_name))
	if error != OK:
		push_error("Nie udało się zapisać zrzutu trybu zarządzania: %d." % error)
		get_tree().quit(1)
		return false
	return true


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("Base management workspace snapshot failed: " + message)
	get_tree().quit(1)
