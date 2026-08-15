class_name BuildingPanel
extends PanelContainer

signal closed()
signal build_requested(slot_id: String, definition_id: String)
signal upgrade_requested(building_id: String)
signal worker_picker_requested(building_id: String, slot_index: int)
signal dive_requested()
signal diver_selected(survivor_id: String)
signal production_requested(building_id: String, recipe_id: String)
signal gear_equipped(slot_id: String, gear_id: String)
signal entry_point_selected(entry_point_id: String)
signal survivor_development_requested(survivor_id: String, stat_id: String)
signal career_promotion_requested(survivor_id: String, profession_id: String)
signal profession_talent_requested(survivor_id: String, talent_id: String)
signal work_pace_selected(building_id: String, work_pace: String)
signal medical_priority_changed(survivor_id: String, desired: bool)

const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const WorkerAssignmentRailScript := preload("res://scripts/base/WorkerAssignmentRail.gd")
const DivingStationHudScript := preload("res://scripts/base/DivingStationHud.gd")
const CareerProgressionSystemScript := preload("res://scripts/base/CareerProgressionSystem.gd")
const ProfessionTalentSystemScript := preload("res://scripts/base/ProfessionTalentSystem.gd")
const BuildingEffectSystemScript := preload("res://scripts/base/BuildingEffectSystem.gd")
const CampaignProgressionSystemScript := preload("res://scripts/base/CampaignProgressionSystem.gd")
const WorkPaceSystemScript := preload("res://scripts/base/WorkPaceSystem.gd")
const MedicalCareSystemScript := preload("res://scripts/base/MedicalCareSystem.gd")
const DiseaseSystemScript := preload("res://scripts/base/DiseaseSystem.gd")
const CompetencySystemScript := preload("res://scripts/base/CompetencySystem.gd")
const SurvivorPortraitScript := preload("res://scripts/ui/SurvivorPortrait.gd")
const SurvivorInfoPresenterScript := preload("res://scripts/ui/SurvivorInfoPresenter.gd")

var _state
var _slot_id: String
var _definition
var _building
var _building_system
var _production_system
var _building_art: Texture2D
var _career_progression_system = CareerProgressionSystemScript.new()
var _profession_talent_system = ProfessionTalentSystemScript.new()
var _building_effect_system = BuildingEffectSystemScript.new()
var _campaign_progression_system = CampaignProgressionSystemScript.new()
var _work_pace_system = WorkPaceSystemScript
var _disease_system = DiseaseSystemScript.new()
var _tutorial_step: int
var _selected_community_survivor_id: String = ""
var _selected_community_profession_by_survivor: Dictionary = {}
var _restore_scroll_after_rebuild: int = -1
var _reset_scrolls_to_top_after_rebuild: bool = false
var _focus_community_picker_after_rebuild: bool = false
var _focus_community_profession_picker_after_rebuild: bool = false
var _focus_control_after_rebuild: String = ""
var _view_key: String = ""
var _details_expanded: bool = false
var _station_profile_details_expanded: bool = false
var _station_equipment_details_expanded: bool = false
var _station_hud
var _selected_workshop_recipe_id: String = ""
var _focus_scope: Control
var _external_focus_scopes: Array[Control] = []
var _right_sidebar_host: VBoxContainer

const WORKSPACE_MIN_WIDTH := 720.0
const WORKSPACE_MIN_HEIGHT := 520.0
const RIGHT_SIDEBAR_MIN_WIDTH := 264.0

# Dwie celowe strefy zarządzania bazą: morska rama HUD-u i ciepła,
# papierowa przestrzeń robocza. Nie mieszamy ich przez dziedziczenie Theme,
# ponieważ prawa szyna jest niezależnym rodzeństwem centralnego panelu.
const UI_CANVAS := Color("092f37")
const UI_HEADER := Color("10464e")
const UI_SIDEBAR := Color("0b3940")
const UI_SIDEBAR_RAISED := Color("15545a")
const UI_SIDEBAR_BORDER := Color("2c7277")
const UI_PANEL := Color("efe7d7")
const UI_SURFACE := Color("e4d9c5")
const UI_SURFACE_RAISED := Color("f7f0e2")
const UI_BORDER := Color("c7b38e")
const UI_BORDER_SUBTLE := Color("d8c8ad")
const UI_TEXT := Color("203b3b")
const UI_TEXT_MUTED := Color("607578")
const UI_DARK_TEXT := Color("f2f0e7")
const UI_DARK_TEXT_MUTED := Color("b6cac6")
const UI_TEAL := Color("147b80")
const UI_TEAL_LIGHT := Color("79c4c0")
const UI_AMBER := Color("f2af36")
const UI_AMBER_HOVER := Color("ffcb62")
const UI_AMBER_DARK := Color("a66318")
const UI_GREEN := Color("9bc85c")
const UI_CORAL := Color("ce6252")

func _ready() -> void:
	# Panel wypełnia część dużego workspace'u pozostałą po lewej szynie.
	custom_minimum_size = Vector2(WORKSPACE_MIN_WIDTH, WORKSPACE_MIN_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_workspace_theme()
	add_theme_stylebox_override("panel", _panel_style())
	set_process_unhandled_input(true)


func _apply_workspace_theme() -> void:
	theme = _interface_theme(UI_TEXT, UI_TEXT_MUTED)


func _interface_theme(ink: Color, muted_ink: Color) -> Theme:
	var workspace_theme := Theme.new()
	for type_name in ["Label", "Button", "OptionButton", "CheckButton"]:
		workspace_theme.set_color("font_color", type_name, ink)
		workspace_theme.set_color("font_hover_color", type_name, ink)
		workspace_theme.set_color("font_pressed_color", type_name, ink)
		workspace_theme.set_color("font_focus_color", type_name, ink)
		workspace_theme.set_color("font_disabled_color", type_name, Color(muted_ink, 0.58))
	return workspace_theme


func _apply_sidebar_theme(sidebar: Control) -> void:
	if sidebar != null and is_instance_valid(sidebar):
		sidebar.theme = _interface_theme(UI_DARK_TEXT, UI_DARK_TEXT_MUTED)


func _content_ink(content: Control) -> Color:
	return UI_DARK_TEXT if bool(content.get_meta("dark_surface", false)) else UI_TEXT


func _content_muted_ink(content: Control) -> Color:
	return UI_DARK_TEXT_MUTED if bool(content.get_meta("dark_surface", false)) else UI_TEXT_MUTED


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or _has_visible_child_window():
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	var focus_root := _focus_scope if _focus_scope != null and is_instance_valid(_focus_scope) else self
	if focus_owner == null or not _focus_owner_is_allowed(focus_owner, focus_root):
		focus_initial()


func set_focus_scope(scope: Control) -> void:
	_focus_scope = scope


func set_right_sidebar_host(host: VBoxContainer) -> void:
	_right_sidebar_host = host
	if _right_sidebar_host != null and is_instance_valid(_right_sidebar_host):
		_apply_sidebar_theme(_right_sidebar_host)


func set_external_focus_scopes(scopes: Array[Control]) -> void:
	_external_focus_scopes.clear()
	for scope in scopes:
		if scope != null and is_instance_valid(scope):
			_external_focus_scopes.append(scope)


func _focus_owner_is_allowed(focus_owner: Control, focus_root: Control) -> bool:
	if focus_owner == focus_root or focus_root.is_ancestor_of(focus_owner):
		return true
	for scope in _external_focus_scopes:
		if scope != null and is_instance_valid(scope) and (focus_owner == scope or scope.is_ancestor_of(focus_owner)):
			return true
	return false

func configure(state, slot_id: String, definition, building, building_system, production_system, tutorial_step: int, building_art: Texture2D = null) -> void:
	var previous_tutorial_step := _tutorial_step
	var next_view_key := "%s:%s" % [slot_id, str(building.id) if building != null else str(definition.id)]
	if next_view_key != _view_key:
		_view_key = next_view_key
		_details_expanded = false
		_station_profile_details_expanded = false
		_station_equipment_details_expanded = false
		_selected_workshop_recipe_id = ""
		_restore_scroll_after_rebuild = -1
		_reset_scrolls_to_top_after_rebuild = true
	_state = state
	_slot_id = slot_id
	_definition = definition
	_building = building
	_building_system = building_system
	_production_system = production_system
	_tutorial_step = tutorial_step
	_building_art = building_art
	if definition != null and definition.id == "workshop" and tutorial_step == TutorialStateScript.Step.CRAFT_RESCUE_KNIFE:
		if previous_tutorial_step == TutorialStateScript.Step.STAFF_WORKSHOP:
			_restore_scroll_after_rebuild = 0
			_focus_control_after_rebuild = "Craft_tutorial_rescue_knife"
	_update_requested_size()
	_rebuild()

func refresh_layout(available_size: Vector2 = Vector2.ZERO) -> void:
	_update_requested_size(available_size)


func _update_requested_size(available_size: Vector2 = Vector2.ZERO) -> void:
	if available_size.x <= 0.0 or available_size.y <= 0.0:
		available_size = size if size.x > 0.0 and size.y > 0.0 else Vector2(WORKSPACE_MIN_WIDTH, WORKSPACE_MIN_HEIGHT)
	custom_minimum_size = Vector2(
		minf(WORKSPACE_MIN_WIDTH, maxf(available_size.x, 360.0)),
		minf(WORKSPACE_MIN_HEIGHT, maxf(available_size.y, 360.0))
	)

func _rebuild() -> void:
	_station_hud = null
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_clear_right_sidebar_host()

	var shell := VBoxContainer.new()
	shell.name = "BuildingWorkspaceShell"
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_constant_override("separation", 0)
	add_child(shell)

	var header_panel := PanelContainer.new()
	header_panel.name = "BuildingWorkspaceHeader"
	header_panel.custom_minimum_size = Vector2(0, 122)
	header_panel.add_theme_stylebox_override("panel", _header_style())
	shell.add_child(header_panel)
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 14)
	header_margin.add_theme_constant_override("margin_top", 9)
	header_margin.add_theme_constant_override("margin_right", 10)
	header_margin.add_theme_constant_override("margin_bottom", 8)
	header_panel.add_child(header_margin)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header_margin.add_child(header)
	if _building_art != null:
		var building_art := TextureRect.new()
		building_art.name = "BuildingHeaderArt"
		building_art.custom_minimum_size = Vector2(126, 0)
		building_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		building_art.texture = _building_art
		building_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		building_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		building_art.modulate = Color(1.0, 1.0, 1.0, 0.94)
		building_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(building_art)

	var heading_column := VBoxContainer.new()
	heading_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_column.add_theme_constant_override("separation", 2)
	header.add_child(heading_column)

	var title := Label.new()
	title.name = "BuildingTitleLabel"
	title.text = _definition.display_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UI_DARK_TEXT)
	heading_column.add_child(title)

	var status := Label.new()
	status.name = "BuildingStatusLabel"
	status.text = "●  %s" % _status_text()
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", _status_color())
	status.add_theme_font_size_override("font_size", 11)
	heading_column.add_child(status)

	var purpose := Label.new()
	purpose.name = "BuildingPurposeLabel"
	purpose.text = _definition.description
	purpose.tooltip_text = _definition.description
	purpose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	purpose.max_lines_visible = 3
	purpose.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	purpose.add_theme_font_size_override("font_size", 12)
	purpose.add_theme_color_override("font_color", UI_DARK_TEXT_MUTED)
	heading_column.add_child(purpose)

	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "×"
	close_button.tooltip_text = "Zamknij  [Esc]"
	close_button.custom_minimum_size = Vector2(40, 40)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.focus_mode = Control.FOCUS_ALL
	close_button.add_theme_font_size_override("font_size", 21)
	close_button.add_theme_color_override("font_color", UI_DARK_TEXT)
	close_button.add_theme_color_override("font_hover_color", UI_DARK_TEXT)
	close_button.add_theme_stylebox_override("normal", _compact_button_style(UI_SIDEBAR, UI_SIDEBAR_BORDER, 1))
	close_button.add_theme_stylebox_override("hover", _compact_button_style(UI_CANVAS, UI_TEAL_LIGHT, 2))
	close_button.add_theme_stylebox_override("pressed", _compact_button_style(UI_CANVAS, UI_AMBER, 2))
	close_button.add_theme_stylebox_override("focus", _compact_button_style(UI_SIDEBAR, UI_TEAL_LIGHT, 2))
	close_button.pressed.connect(func(): closed.emit())
	header.add_child(close_button)

	_build_content_split(shell)
	var has_scroll_restore := _restore_scroll_after_rebuild >= 0
	var scroll_target := maxi(_restore_scroll_after_rebuild, 0)
	_restore_scroll_after_rebuild = -1
	var should_reset_scrolls_to_top := _reset_scrolls_to_top_after_rebuild
	_reset_scrolls_to_top_after_rebuild = false
	var panel_scroll := _active_scroll()
	if has_scroll_restore and panel_scroll != null:
		panel_scroll.follow_focus = false
	if _focus_community_picker_after_rebuild:
		_focus_community_picker_after_rebuild = false
		var community_card := find_child("CommunitySurvivorCard_%s" % _selected_community_survivor_id, true, false) as Button
		if community_card != null:
			community_card.call_deferred("grab_focus")
	if _focus_community_profession_picker_after_rebuild:
		_focus_community_profession_picker_after_rebuild = false
		var profession_picker := find_child("CommunityProfessionPicker", true, false) as OptionButton
		if profession_picker != null:
			profession_picker.call_deferred("grab_focus")
	if not _focus_control_after_rebuild.is_empty():
		var focus_name := _focus_control_after_rebuild
		_focus_control_after_rebuild = ""
		var focus_control := _find_workspace_control(focus_name)
		if focus_control != null:
			focus_control.call_deferred("grab_focus")
	call_deferred("_configure_focus_loop")
	if has_scroll_restore and panel_scroll != null:
		call_deferred("_finish_scroll_restore", panel_scroll, scroll_target)
	elif should_reset_scrolls_to_top:
		call_deferred("_finish_initial_scroll_reset")

func _finish_scroll_restore(panel_scroll: ScrollContainer, scroll_target: int) -> void:
	if not is_instance_valid(panel_scroll) or not panel_scroll.is_inside_tree():
		return
	panel_scroll.scroll_vertical = scroll_target
	await get_tree().process_frame
	if not is_instance_valid(panel_scroll) or not panel_scroll.is_inside_tree():
		return
	panel_scroll.scroll_vertical = scroll_target
	panel_scroll.follow_focus = true


func _finish_initial_scroll_reset() -> void:
	# The initial keyboard focus may be a lower action (for example a recipe or
	# diver candidate). Let that focus settle first, then restore the opening
	# view to the beginning of every building section.
	await get_tree().process_frame
	var scrolls := _managed_scroll_containers()
	for scroll in scrolls:
		scroll.follow_focus = false
		scroll.scroll_vertical = 0
	await get_tree().process_frame
	for scroll in scrolls:
		if not is_instance_valid(scroll) or not scroll.is_inside_tree():
			continue
		scroll.scroll_vertical = 0
		scroll.follow_focus = true


func _managed_scroll_containers() -> Array[ScrollContainer]:
	var scrolls: Array[ScrollContainer] = []
	_append_scroll_containers(self, scrolls)
	_append_scroll_containers(_right_sidebar_host, scrolls)
	return scrolls


func _append_scroll_containers(root: Node, scrolls: Array[ScrollContainer]) -> void:
	if root == null or not is_instance_valid(root):
		return
	if root is ScrollContainer and not scrolls.has(root):
		scrolls.append(root)
	for scroll in root.find_children("*", "ScrollContainer", true, false):
		if scroll is ScrollContainer and not scrolls.has(scroll):
			scrolls.append(scroll)


func _clear_right_sidebar_host() -> void:
	if _right_sidebar_host == null or not is_instance_valid(_right_sidebar_host):
		return
	for child in _right_sidebar_host.get_children():
		_right_sidebar_host.remove_child(child)
		child.queue_free()


func _find_workspace_control(control_name: String) -> Control:
	var candidate := find_child(control_name, true, false) as Control
	if candidate != null:
		return candidate
	if _focus_scope != null and is_instance_valid(_focus_scope):
		return _focus_scope.find_child(control_name, true, false) as Control
	return null

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed("ui_cancel"):
		return
	if _has_visible_child_window():
		return
	closed.emit()
	get_viewport().set_input_as_handled()


func _has_visible_child_window() -> bool:
	for child in find_children("*", "Window", true, false):
		if child is Window and child.visible:
			return true
	return false

func _create_scroll_page(node_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	return scroll

func _create_page_content(scroll: ScrollContainer, minimum_content_width: float = -1.0) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	var content_width := minimum_content_width if minimum_content_width > 0.0 else 280.0
	content.custom_minimum_size = Vector2(content_width, 0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	return content

func _panel_scroll() -> ScrollContainer:
	return find_child("PanelScroll", true, false) as ScrollContainer

func _active_scroll() -> ScrollContainer:
	return _panel_scroll()

func _build_construction_content(content: VBoxContainer) -> void:
	var level_definition = _definition.get_level_definition(1)
	if level_definition != null:
		_add_section_title(content, "Poziom I: %s" % level_definition.display_name)
	_add_effect_card(
		content,
		"CO DAJE ODBUDOWA",
		_building_effect_system.level_effect_lines(_state, _definition, 1),
		"ConstructionBenefitsLabel",
		UI_TEAL
	)
	var tutorial_blocks: bool = _state.tutorial.is_active() and not _building_system.construction_blocker(_state, _slot_id, _definition).is_empty()
	if tutorial_blocks:
		_add_hint(content, "Najpierw wykonaj polecenia tutoriala i odbuduj Stację Nurkową.")

func _build_pending_content(content: VBoxContainer) -> void:
	_add_section_title(content, "Odbudowa zaplanowana")
	_add_body(content, "Materiały zostały zabezpieczone. Zniszczony szkielet zostanie przywrócony do działania po zakończeniu dnia.")
	_add_effect_card(
		content,
		"PO UKOŃCZENIU ODBUDOWY",
		_building_effect_system.level_effect_lines(_state, _definition, 1),
		"ConstructionBenefitsLabel",
		UI_TEAL
	)
	_add_hint(content, "Wróć na planszę i użyj przycisku Zakończ dzień.")

func _build_content_split(shell: VBoxContainer) -> void:
	var split := HBoxContainer.new()
	split.name = "BuildingContentSplit"
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 8)
	shell.add_child(split)

	var action_column := VBoxContainer.new()
	action_column.name = "BuildingActionColumn"
	action_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_column.add_theme_constant_override("separation", 8)
	split.add_child(action_column)

	var action_scroll := _create_scroll_page("PanelScroll")
	action_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_column.add_child(action_scroll)
	var action_content := _create_page_content(action_scroll)
	if _building == null:
		_build_construction_content(action_content)
	elif not _building.is_built:
		_build_pending_content(action_content)
	else:
		_build_action_overview(action_content)
		if _definition.id == "diving_station":
			_build_station_dive_footer(action_column)

	var sidebar := _right_sidebar_host
	if sidebar == null or not is_instance_valid(sidebar):
		sidebar = VBoxContainer.new()
		split.add_child(sidebar)
	sidebar.name = "BuildingRightSidebar"
	_apply_sidebar_theme(sidebar)
	sidebar.custom_minimum_size = Vector2(RIGHT_SIDEBAR_MIN_WIDTH, 0)
	sidebar.size_flags_horizontal = Control.SIZE_SHRINK_END
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", 12)
	_build_staffing_sidebar(sidebar)
	_build_construction_sidebar(sidebar)


func _build_station_dive_footer(action_column: VBoxContainer) -> void:
	if _station_hud == null:
		return
	var footer := PanelContainer.new()
	footer.name = "DiveActionFooter"
	footer.custom_minimum_size = Vector2(0, 68)
	footer.size_flags_vertical = Control.SIZE_SHRINK_END
	footer.add_theme_stylebox_override("panel", _station_footer_style())
	action_column.add_child(footer)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	footer.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var summary := VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(summary)
	var heading := Label.new()
	heading.text = "WYPRAWA"
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", UI_AMBER)
	summary.add_child(heading)
	var readiness := Label.new()
	readiness.name = "DiveFooterReadinessLabel"
	readiness.text = _station_hud.readiness_text()
	readiness.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	readiness.max_lines_visible = 2
	readiness.add_theme_font_size_override("font_size", 11)
	readiness.add_theme_color_override("font_color", UI_GREEN if _station_hud.is_ready() else UI_CORAL)
	summary.add_child(readiness)
	row.add_child(_station_hud.create_dive_button())


func _build_staffing_sidebar(sidebar: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "BuildingStaffingSidePanel"
	panel.custom_minimum_size = Vector2(0, 170)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.15
	panel.add_theme_stylebox_override("panel", _staffing_sidebar_style())
	sidebar.add_child(panel)
	var scroll := _create_scroll_page("StaffingScroll")
	panel.add_child(scroll)
	var content := _create_page_content(scroll, RIGHT_SIDEBAR_MIN_WIDTH - 40.0)
	content.set_meta("dark_surface", true)
	if _building == null or not _building.is_active():
		_add_section_title(content, "OBSADA")
		_add_body(content, "Odbuduj budynek, aby przydzielić do niego mieszkańców.")
		return
	var assignment_rail = WorkerAssignmentRailScript.new()
	assignment_rail.name = "BuildingStaffingRail"
	assignment_rail.configure(_state, _definition, _building, _tutorial_step, true)
	assignment_rail.worker_picker_requested.connect(_on_worker_picker_requested)
	content.add_child(assignment_rail)


func _build_construction_sidebar(sidebar: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "BuildingConstructionSidePanel"
	panel.custom_minimum_size = Vector2(0, 170)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.85
	panel.add_theme_stylebox_override("panel", _sidebar_style())
	sidebar.add_child(panel)
	var shell := VBoxContainer.new()
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(shell)
	var scroll := _create_scroll_page("UpgradeScroll")
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(scroll)
	var content := _create_page_content(scroll, RIGHT_SIDEBAR_MIN_WIDTH - 40.0)
	content.set_meta("dark_surface", true)
	_build_construction_sidebar_content(content)
	_build_construction_sidebar_action(shell)


func _build_construction_sidebar_content(content: VBoxContainer) -> void:
	if _building == null:
		_add_section_title(content, "BUDOWA")
		var level_definition = _definition.get_level_definition(1)
		if level_definition != null:
			_add_body(content, "Poziom I: %s" % level_definition.display_name)
		_add_section_title(content, "Wymagane materiały")
		var build_cost: Dictionary = _building_system.get_build_cost(_state, _definition)
		_add_cost_rows(content, build_cost)
		var build_blocker := str(_building_system.construction_blocker(_state, _slot_id, _definition))
		if not build_blocker.is_empty():
			_add_hint(content, build_blocker)
		return
	if not _building.is_built or _building.pending_level > _building.level:
		_add_section_title(content, "BUDOWA")
		_add_status_callout(content, "STARSZY ZAPIS", "Aktywacja czeka na migrację stanu.", UI_AMBER)
		return
	if _building.level >= _definition.max_level:
		_add_section_title(content, "ROZBUDOWA")
		_add_status_callout(content, "MAKSYMALNY POZIOM", "Budynek osiągnął pełną dostępną sprawność.", UI_GREEN)
		return
	_add_section_title(content, "ROZBUDOWA")
	var next_level_definition = _definition.get_level_definition(_building.level + 1)
	if next_level_definition != null:
		_add_body(content, "Poziom %d → %d: %s" % [_building.level, _building.level + 1, next_level_definition.display_name])
	_add_section_title(content, "Wymagane materiały")
	var upgrade_cost: Dictionary = _building_system.get_upgrade_cost(_state, _definition, _building.level)
	_add_cost_rows(content, upgrade_cost)
	var upgrade_blocker := str(_building_system.upgrade_blocker(_state, _building, _definition))
	if not upgrade_blocker.is_empty():
		_add_hint(content, upgrade_blocker)


func _build_construction_sidebar_action(shell: VBoxContainer) -> void:
	if _building == null:
		var build_button := Button.new()
		build_button.name = "BuildButton"
		build_button.text = "ODBUDUJ"
		build_button.custom_minimum_size = Vector2(0, 46)
		var build_cost: Dictionary = _building_system.get_build_cost(_state, _definition)
		var build_blocker := str(_building_system.construction_blocker(_state, _slot_id, _definition))
		build_button.disabled = not build_blocker.is_empty()
		build_button.tooltip_text = build_blocker if not build_blocker.is_empty() else _cost_tooltip(build_cost, "Koszt odbudowy")
		build_button.pressed.connect(func(): build_requested.emit(_slot_id, _definition.id))
		build_button.add_theme_stylebox_override("normal", _primary_button_style(false))
		build_button.add_theme_stylebox_override("hover", _primary_button_style(true))
		_apply_primary_button_text(build_button)
		if (_tutorial_step == TutorialStateScript.Step.BUILD_DIVING_STATION and _definition.id == "diving_station") or (_tutorial_step == TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE and _definition.id == "community_house") or (_tutorial_step == TutorialStateScript.Step.BUILD_WORKSHOP and _definition.id == "workshop"):
			build_button.add_theme_stylebox_override("normal", _target_button_style())
		shell.add_child(build_button)
		return
	if _building.is_built and _building.level < _definition.max_level:
		var upgrade_button := Button.new()
		upgrade_button.name = "UpgradeButton"
		upgrade_button.text = "ROZBUDUJ"
		upgrade_button.custom_minimum_size = Vector2(0, 46)
		var upgrade_cost: Dictionary = _building_system.get_upgrade_cost(_state, _definition, _building.level)
		var upgrade_blocker := str(_building_system.upgrade_blocker(_state, _building, _definition))
		upgrade_button.disabled = not upgrade_blocker.is_empty()
		upgrade_button.tooltip_text = upgrade_blocker if not upgrade_blocker.is_empty() else _cost_tooltip(upgrade_cost, "Koszt następnego poziomu")
		upgrade_button.pressed.connect(func(): upgrade_requested.emit(_building.id))
		upgrade_button.add_theme_stylebox_override("normal", _sidebar_secondary_button_style(false))
		upgrade_button.add_theme_stylebox_override("hover", _sidebar_secondary_button_style(true))
		shell.add_child(upgrade_button)

func _build_action_overview(content: VBoxContainer) -> void:
	if _definition.id == "diving_station":
		_station_hud = DivingStationHudScript.new()
		_station_hud.set_disclosure_state(_station_profile_details_expanded, _station_equipment_details_expanded)
		_station_hud.configure(_state, _definition, _building, _building_system, _tutorial_step, false)
		_station_hud.dive_requested.connect(func(): dive_requested.emit())
		_station_hud.diver_selected.connect(_on_station_diver_selected)
		_station_hud.gear_equipped.connect(_on_station_gear_equipped)
		_station_hud.entry_point_selected.connect(_on_station_entry_point_selected)
		_station_hud.disclosure_state_changed.connect(_on_station_disclosure_state_changed)
		content.add_child(_station_hud)
	_add_operational_summary(content)
	_add_operational_effects(content)
	_build_work_pace_control(content)
	if _definition.id != "diving_station":
		_build_standard_active_content(content)


func _build_work_pace_control(content: VBoxContainer) -> void:
	if _building == null:
		return
	_add_section_title(content, "Tempo tego budynku")
	var picker := OptionButton.new()
	picker.name = "BuildingWorkPacePicker"
	picker.custom_minimum_size = Vector2(0, 40)
	var pace_ids := [
		WorkPaceSystemScript.WORK_PACE_CAREFUL,
		WorkPaceSystemScript.WORK_PACE_NORMAL,
		WorkPaceSystemScript.WORK_PACE_INTENSE,
	]
	var selected_pace := _work_pace_system.pace_for_building(_state, _building)
	for pace_id in pace_ids:
		picker.add_item(_work_pace_system.pace_label(str(pace_id)))
		var index := picker.item_count - 1
		picker.set_item_metadata(index, str(pace_id))
		if str(pace_id) == selected_pace:
			picker.select(index)
	var editable: bool = _state != null and _state.can_edit_day_plan()
	picker.disabled = not editable
	picker.tooltip_text = _day_plan_edit_blocker() if not editable else "Ustaw tempo wyłącznie dla tego budynku."
	picker.item_selected.connect(_on_building_work_pace_selected.bind(picker))
	content.add_child(picker)

	var tension := clampi(int(_building.work_tension), 0, 3)
	var preview: Dictionary = _building_effect_system.staffing_preview(_state, _definition, _building)
	var hint := _work_pace_hint(selected_pace, tension, str(preview.get("mode", "")))
	_add_hint(content, "Napięcie pracy: %d/3. %s" % [tension, hint], "BuildingWorkPaceHint")


func _work_pace_hint(selected_pace: String, tension: int, preview_mode: String) -> String:
	var fixed_task_label := _fixed_work_task_label(preview_mode)
	if not fixed_task_label.is_empty():
		return (
			"Dzisiejsze zadanie — %s — używa stałej procedury Normalnej: efekt bez skali tempa. "
			% fixed_task_label
			+ _work_pace_consequence_copy(WorkPaceSystemScript.WORK_PACE_NORMAL, tension)
			+ " Wybór %s nie zmienia tego zadania." % _work_pace_system.pace_label(selected_pace)
		)

	var effect_copy := ""
	if str(_definition.id) == "community_house":
		var adjustment := _work_pace_system.community_worker_adjustment(selected_pace)
		effect_copy = (
			"Dom Wspólnoty koryguje poziomowy wkład każdego pracownika o %s na osobę "
			% _signed_work_value(adjustment)
			+ "(Ostrożne/Normalne/Intensywne = −1/0/+1; to nie jest mnożnik)."
		)
	else:
		effect_copy = "%s ×%s." % [
			_scaled_work_effect_label(preview_mode),
			_work_pace_multiplier_text(selected_pace),
		]

	var result := "%s %s" % [effect_copy, _work_pace_consequence_copy(selected_pace, tension)]
	if str(_definition.id) == "diving_station":
		result += (
			" Nurek zamiast zwykłego +%d otrzymuje "
			% _work_pace_system.worker_fatigue_gain(selected_pace)
			+ "round((16 + min(floor(czas wyprawy / 120), 14)) × tempo Stacji)."
		)
	return result


func _work_pace_consequence_copy(pace: String, tension: int) -> String:
	var work_transition: Dictionary = _work_pace_system.tension_transition(tension, pace, true)
	var idle_transition: Dictionary = _work_pace_system.tension_transition(tension, pace, false)
	var work_rule: Dictionary = _work_pace_system.tension_transition(2, pace, true)
	var idle_rule: Dictionary = _work_pace_system.tension_transition(2, pace, false)
	return (
		"Tylko przy realnej pracy: pracujący +%d zmęczenia, Napięcie %s (bieżąco %d→%d). "
		% [
			_work_pace_system.worker_fatigue_gain(pace),
			_signed_work_value(int(work_rule.get("delta", 0))),
			int(work_transition.get("previous", tension)),
			int(work_transition.get("current", tension)),
		]
		+ "Bez realnej pracy: odpoczynek −12 i Napięcie %s (bieżąco %d→%d), niezależnie od ustawienia."
		% [
			_signed_work_value(int(idle_rule.get("delta", 0))),
			int(idle_transition.get("previous", tension)),
			int(idle_transition.get("current", tension)),
		]
	)


func _fixed_work_task_label(preview_mode: String) -> String:
	match preview_mode:
		"heavy_recovery":
			return "ciężki odzysk"
	return ""


func _scaled_work_effect_label(preview_mode: String) -> String:
	match str(_definition.id):
		"diving_station":
			return "Zasięg Operatora i naprawa kombinezonu"
		"fishing_hut":
			return "Połów"
		"kitchen":
			return "Sprawność Kuchni przed limitem 75%"
		"workshop":
			if preview_mode == "production":
				return "Punkty produkcji"
			if preview_mode == "platform_repair":
				return "Automatyczna naprawa platformy"
			return "Punkty produkcji i automatyczna naprawa platformy"
		"infirmary":
			return "Leczenie"
	return "Aktywny efekt budynku"


func _work_pace_multiplier_text(pace: String) -> String:
	return ("%.2f" % _work_pace_system.output_multiplier(pace)).replace(".", ",")


func _signed_work_value(value: int) -> String:
	if value > 0:
		return "+%d" % value
	if value < 0:
		return "−%d" % abs(value)
	return "0"


func _on_building_work_pace_selected(index: int, picker: OptionButton) -> void:
	if _building == null or _state == null or not _state.can_edit_day_plan():
		return
	var panel_scroll := _active_scroll()
	_restore_scroll_after_rebuild = panel_scroll.scroll_vertical if panel_scroll != null else 0
	_focus_control_after_rebuild = str(picker.name)
	work_pace_selected.emit(str(_building.id), str(picker.get_item_metadata(index)))

func _build_standard_active_content(content: VBoxContainer) -> void:
	if _definition.id == "workshop":
		_build_workshop_production_content(content)
	elif _definition.id == "community_house":
		_build_community_development_content(content)
	elif _definition.id == "infirmary":
		_build_infirmary_care_content(content)
	else:
		_add_hint(content, "Ten budynek pracuje automatycznie po zakończeniu dnia. Ustaw obsadę w zakładce OBSADA, aby zobaczyć rzeczywisty wynik.")


func _build_infirmary_care_content(content: VBoxContainer) -> void:
	_add_section_title(content, "Kolejka opieki na dziś")
	var projection := _medical_care_projection()
	var needing_care := int(projection.get("patients_requiring_care", 0))
	var treated_count := int(projection.get("treated_count", 0))
	var patient_capacity := int(projection.get("patient_capacity", 0))
	var medicine_per_patient := int(projection.get("medicine_per_patient", 0))
	var medicine_spent := int(projection.get("medicine_spent", 0))
	var effective_healing := int(projection.get("effective_healing", 0))
	var summary := Label.new()
	summary.name = "MedicalCareSummaryLabel"
	summary.text = (
		"Plan: %d z %d potrzebujących • pojemność %d • +%d zdrowia/os.\n"
		+ "Koszt: %d × %d = %d jednostek leków%s"
	) % [
		treated_count,
		needing_care,
		patient_capacity,
		effective_healing,
		treated_count,
		medicine_per_patient,
		medicine_spent,
		" • NIEDOBÓR" if bool(projection.get("medicine_shortage", false)) else "",
	]
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 13)
	summary.add_theme_color_override("font_color", UI_TEXT)
	content.add_child(summary)

	var blocker_text := _medical_care_blocker_text(str(projection.get("blocker_code", "")))
	if not blocker_text.is_empty():
		_add_hint(content, blocker_text, "MedicalCareBlockerLabel")

	var queue := VBoxContainer.new()
	queue.name = "MedicalCareQueue"
	queue.add_theme_constant_override("separation", 7)
	content.add_child(queue)
	var treated_ids: Array[String] = []
	treated_ids.assign(projection.get("treated_survivor_ids", []))
	var priority_ids: Array[String] = []
	if _state != null and _state.current_day_plan != null:
		priority_ids.assign(_state.current_day_plan.medical_priority_survivor_ids)
	for index in range(projection.get("patient_queue", []).size()):
		var patient: Dictionary = projection.patient_queue[index]
		_add_medical_queue_row(queue, patient, index, treated_ids, priority_ids)
	if needing_care <= 0:
		_add_hint(queue, "Nikt nie wymaga dziś leczenia urazu, zdrowia ani choroby.")

	var formal_capacity := int(projection.get("formal_isolation_capacity", 0))
	var isolation_assignments := _disease_system.isolation_assignments(_state, formal_capacity)
	var formal_ids: Array[String] = []
	formal_ids.assign(isolation_assignments.get("formal_ids", []))
	var emergency_ids: Array[String] = []
	emergency_ids.assign(isolation_assignments.get("emergency_ids", []))
	var formal_names := _survivor_names(formal_ids)
	var emergency_names := _survivor_names(emergency_ids)
	var isolation := Label.new()
	isolation.name = "IsolationCapacityLabel"
	isolation.text = "IZOLACJA  •  formalna %d / %d  •  awaryjna %d" % [
		formal_ids.size(),
		formal_capacity,
		emergency_ids.size(),
	]
	if not formal_names.is_empty():
		isolation.text += "\nFormalna: %s" % ", ".join(formal_names)
	if not emergency_names.is_empty():
		isolation.text += "\nAwaryjna: %s" % ", ".join(emergency_names)
	isolation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	isolation.add_theme_font_size_override("font_size", 12)
	isolation.add_theme_color_override("font_color", UI_AMBER)
	content.add_child(isolation)


func _survivor_names(survivor_ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for survivor_id in survivor_ids:
		var survivor = _state.find_survivor(survivor_id) if _state != null else null
		result.append(str(survivor.display_name) if survivor != null else survivor_id)
	return result


func _medical_care_projection() -> Dictionary:
	if _state == null:
		return {}
	return _building_effect_system.medical_care_projection(_state)


func _add_medical_queue_row(
	parent: VBoxContainer,
	patient: Dictionary,
	queue_index: int,
	treated_ids: Array[String],
	priority_ids: Array[String]
) -> void:
	var survivor_id := str(patient.get("survivor_id", ""))
	var row := PanelContainer.new()
	row.name = "MedicalPatient_%s" % survivor_id
	row.add_theme_stylebox_override("panel", _effect_card_style(UI_GREEN))
	parent.add_child(row)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_bottom", 7)
	row.add_child(margin)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	margin.add_child(line)
	var reasons: Array[String] = []
	for raw_reason in patient.get("care_reasons", []):
		match str(raw_reason):
			"health": reasons.append("zdrowie")
			"injury": reasons.append("uraz")
			"disease": reasons.append("choroba")
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "%d. %s  •  %s  •  %s" % [
		queue_index + 1,
		str(patient.get("display_name", survivor_id)),
		", ".join(reasons),
		"OPIEKA ZAPLANOWANA" if survivor_id in treated_ids else "POZA DZISIEJSZYM LIMITEM",
	]
	if not patient.get("disease_treatments", []).is_empty():
		var treatment_names: Array[String] = []
		for treatment in patient.disease_treatments:
			treatment_names.append(str(treatment.get("display_name", treatment.get("disease_id", "choroba"))))
		label.text += "\nTerapia: %s" % ", ".join(treatment_names)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", UI_TEXT)
	line.add_child(label)
	var prioritized: bool = survivor_id in priority_ids
	var priority_button := Button.new()
	priority_button.name = "MedicalPriority_%s" % survivor_id
	priority_button.text = "Usuń priorytet" if prioritized else "Nadaj priorytet"
	priority_button.disabled = _state == null or not _state.can_edit_day_plan()
	priority_button.tooltip_text = (
		_day_plan_edit_blocker()
		if priority_button.disabled
		else "Jawny priorytet zmienia kolejność wspólnego triage, nie tworzy drugiej kolejki."
	)
	priority_button.pressed.connect(_on_medical_priority_pressed.bind(survivor_id, not prioritized, str(priority_button.name)))
	line.add_child(priority_button)


func _on_medical_priority_pressed(survivor_id: String, desired: bool, focus_name: String) -> void:
	var panel_scroll := _active_scroll()
	_restore_scroll_after_rebuild = panel_scroll.scroll_vertical if panel_scroll != null else 0
	_focus_control_after_rebuild = focus_name
	medical_priority_changed.emit(survivor_id, desired)


func _medical_care_blocker_text(blocker_code: String) -> String:
	match blocker_code:
		MedicalCareSystemScript.BLOCKER_NO_CAPABLE_WORKERS:
			return "Lecznica nie ma zdolnej obsady; kolejka pozostaje widoczna, ale dziś nie wykona opieki."
		MedicalCareSystemScript.BLOCKER_INVALID_CAPABILITIES:
			return "Definicja bieżącego poziomu Lecznicy nie ma poprawnych parametrów opieki."
		MedicalCareSystemScript.BLOCKER_NO_PATIENTS:
			return "Brak pacjentów wymagających opieki."
		MedicalCareSystemScript.BLOCKER_INSUFFICIENT_MEDICINE:
			return "Brakuje leków na choć jednego pacjenta."
	return ""

func _add_operational_summary(content: VBoxContainer) -> void:
	var level_definition = _definition.get_level_definition(_building.level)
	var level_name := str(level_definition.display_name) if level_definition != null else ""
	var summary_text := "POZIOM %d" % _building.level
	if not level_name.is_empty():
		summary_text += "  •  %s" % level_name.to_upper()
	_add_status_callout(content, _status_text(), summary_text, _status_color())

func _add_status_callout(content: VBoxContainer, heading_text: String, body_text: String, accent: Color) -> void:
	var card := PanelContainer.new()
	card.name = "BuildingOperationalSummary"
	var dark_surface := bool(content.get_meta("dark_surface", false))
	card.add_theme_stylebox_override("panel", _status_card_style(accent, dark_surface))
	content.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 9)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var marker := Label.new()
	marker.text = "●"
	marker.add_theme_font_size_override("font_size", 17)
	marker.add_theme_color_override("font_color", accent)
	row.add_child(marker)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 1)
	row.add_child(text_column)
	var heading := Label.new()
	heading.text = heading_text
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", _content_ink(content))
	text_column.add_child(heading)
	var body := Label.new()
	body.text = body_text
	body.add_theme_font_size_override("font_size", 11)
	body.add_theme_color_override("font_color", _content_muted_ink(content))
	text_column.add_child(body)

func _add_operational_effects(content: VBoxContainer) -> void:
	if _building == null:
		return

	var staffing_preview: Dictionary = _building_effect_system.staffing_preview(_state, _definition, _building)
	_add_effect_card(
		content,
		"WYNIK DZISIAJ",
		staffing_preview.get("lines", []),
		"StaffContributionLabel",
		_staffing_preview_color(staffing_preview)
	)

	var details_button := Button.new()
	details_button.name = "BuildingDetailsButton"
	var details_title := "PEŁNY EFEKT POZIOMU"
	details_button.text = "%s  %s" % [details_title, "▴" if _details_expanded else "▾"]
	details_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	details_button.custom_minimum_size = Vector2(0, 36)
	details_button.add_theme_font_size_override("font_size", 12)
	details_button.add_theme_color_override("font_color", UI_TEAL)
	content.add_child(details_button)

	var details := VBoxContainer.new()
	details.name = "BuildingDetailsContent"
	details.visible = _details_expanded
	details.add_theme_constant_override("separation", 7)
	content.add_child(details)
	_add_effect_card(
		details,
		"PEŁNY EFEKT POZIOMU",
		_building_effect_system.level_effect_lines(_state, _definition, _building.level),
		"CurrentLevelBenefitsLabel",
		UI_TEAL
	)
	if _building.is_built:
		var explanation := Label.new()
		explanation.text = "Obsadę i koszt rozbudowy obsłużysz w wąskim pasku po prawej. Ten obszar pozostaje miejscem działania budynku."
		explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		explanation.add_theme_font_size_override("font_size", 11)
		explanation.add_theme_color_override("font_color", UI_TEXT_MUTED)
		details.add_child(explanation)
	details_button.pressed.connect(_toggle_details.bind(details_button, details, details_title))

func _toggle_details(button: Button, details: VBoxContainer, details_title: String = "SZCZEGÓŁY") -> void:
	_details_expanded = not _details_expanded
	details.visible = _details_expanded
	button.text = "%s  %s" % [details_title, "▴" if _details_expanded else "▾"]

func _cost_tooltip(cost: Dictionary, heading: String) -> String:
	if cost.is_empty():
		return "Brak danych kosztu."
	var rows: Array[String] = [heading + ":"]
	for resource_id in cost.keys():
		rows.append("%s: %d / %d" % [ResourceIdsScript.display_name(str(resource_id)), _state.resources.get_amount(str(resource_id)), int(cost[resource_id])])
	return "\n".join(rows)


func _day_plan_edit_blocker() -> String:
	if _state == null:
		return "Brak aktywnego stanu kampanii."
	if _state.has_method("day_plan_edit_blocker"):
		return str(_state.day_plan_edit_blocker())
	return "" if _state.can_edit_day_plan() else "Plan dnia jest już zablokowany."


func _community_development_blocker(survivor, stat_id: String) -> String:
	return _career_progression_system.development_blocker(_state, survivor, stat_id)

func _build_community_development_content(content: VBoxContainer) -> void:
	content.add_child(HSeparator.new())
	_add_section_title(content, "ROZWÓJ MIESZKAŃCÓW")
	_add_hint(content, "Wybierz osobę, wydaj punkty cech, zatwierdź drugą specjalizację albo wybierz jej trwały talent zawodowy.")

	var survivors: Array = []
	for survivor in _state.get_alive_survivors():
		if survivor.is_present_in_settlement():
			survivors.append(survivor)
	if survivors.is_empty():
		_add_hint(content, "W Przystani nie ma obecnie mieszkańców, których można rozwijać.")
		return
	if not _building.is_active():
		_add_hint(content, "Wydawanie punktów rozwoju wymaga aktywnego Domu Wspólnoty I.")

	var selected_survivor = _resolve_selected_community_survivor(survivors)
	var roster_grid := GridContainer.new()
	roster_grid.name = "CommunityCrewGrid"
	roster_grid.columns = 2
	roster_grid.add_theme_constant_override("h_separation", 8)
	roster_grid.add_theme_constant_override("v_separation", 8)
	content.add_child(roster_grid)
	for survivor in survivors:
		_add_community_survivor_card(roster_grid, survivor, survivor.id == selected_survivor.id)

	var identity := Label.new()
	identity.name = "CommunityDevelopmentIdentity"
	var identity_professions: String = str(selected_survivor.profession).to_upper()
	if not selected_survivor.secondary_profession.is_empty():
		identity_professions += " + " + selected_survivor.secondary_profession.to_upper()
	identity.text = "%s  •  %s" % [selected_survivor.display_name.to_upper(), identity_professions]
	identity.add_theme_font_size_override("font_size", 16)
	identity.add_theme_color_override("font_color", UI_AMBER)
	content.add_child(identity)

	var progress := Label.new()
	progress.name = "CommunityDevelopmentProgress"
	progress.text = "POZIOM %d  •  PD %d / %d  •  PUNKTY ROZWOJU %d" % [
		selected_survivor.level,
		selected_survivor.experience,
		selected_survivor.experience_to_next_level(),
		selected_survivor.unspent_skill_points,
	]
	progress.add_theme_color_override("font_color", UI_TEAL)
	content.add_child(progress)

	var stats := Label.new()
	stats.name = "CommunityDevelopmentStats"
	stats.text = "Zdrowie %d/%d  •  Tlen %.0f  •  Udźwig %.1f kg\nGłód %d%%  •  Zmęczenie %d%%  •  Morale %d%%" % [
		selected_survivor.health,
		selected_survivor.get_max_health(),
		selected_survivor.get_oxygen_capacity(),
		selected_survivor.get_carry_capacity(),
		selected_survivor.hunger,
		selected_survivor.fatigue,
		selected_survivor.morale,
	]
	stats.add_theme_font_size_override("font_size", 13)
	stats.tooltip_text = SurvivorInfoPresenterScript.combined_state_tooltip(selected_survivor)
	content.add_child(stats)
	var traits := Label.new()
	traits.name = "CommunityDevelopmentTraits"
	traits.text = "Atut: %s  •  Słabość: %s" % [
		str(selected_survivor.positive_trait).capitalize(),
		str(selected_survivor.negative_trait).capitalize(),
	]
	traits.tooltip_text = "%s\n\n%s" % [
		SurvivorInfoPresenterScript.trait_tooltip(str(selected_survivor.positive_trait), true),
		SurvivorInfoPresenterScript.trait_tooltip(str(selected_survivor.negative_trait), false),
	]
	traits.add_theme_font_size_override("font_size", 12)
	traits.add_theme_color_override("font_color", UI_GREEN)
	content.add_child(traits)

	var actions := GridContainer.new()
	actions.name = "CommunityDevelopmentActions"
	actions.columns = 3 if custom_minimum_size.x >= 900.0 else 1
	actions.add_theme_constant_override("h_separation", 10)
	actions.add_theme_constant_override("v_separation", 8)
	content.add_child(actions)
	_add_community_development_button(actions, selected_survivor, "health", "ZDROWIE +10", "Większy margines na urazy i wychłodzenie.")
	_add_community_development_button(actions, selected_survivor, "oxygen", "TLEN +10", "Dłuższa bezpieczna wyprawa.")
	_add_community_development_button(actions, selected_survivor, "carry", "UDŹWIG +4 kg", "Więcej zasobów lub bezpieczniejszy powrót.")

	_add_section_title(content, "Kompetencje pasywne")
	_add_hint(content, "Każda kompetencja ma %d poziomy i kosztuje jeden punkt rozwoju za poziom." % CompetencySystemScript.MAX_LEVEL)
	var competencies := GridContainer.new()
	competencies.name = "CommunityCompetencyActions"
	competencies.columns = 2 if custom_minimum_size.x >= 760.0 else 1
	competencies.add_theme_constant_override("h_separation", 10)
	competencies.add_theme_constant_override("v_separation", 8)
	content.add_child(competencies)
	for competency_id in CompetencySystemScript.IDS:
		var competency_level := CompetencySystemScript.level(selected_survivor, competency_id)
		_add_community_development_button(
			competencies,
			selected_survivor,
			competency_id,
			"%s  %d/%d" % [CompetencySystemScript.LABELS[competency_id], competency_level, CompetencySystemScript.MAX_LEVEL],
			str(CompetencySystemScript.DESCRIPTIONS[competency_id])
		)

	if selected_survivor.unspent_skill_points <= 0:
		_add_hint(content, "%s nie ma teraz niewydanych punktów. Kolejny punkt otrzyma przy awansie." % selected_survivor.display_name)

	_build_community_career_content(content, selected_survivor)

func _add_community_survivor_card(parent: GridContainer, survivor, selected: bool) -> void:
	var card := Button.new()
	card.name = "CommunitySurvivorCard_%s" % survivor.id
	card.set_meta("survivor_id", str(survivor.id))
	card.custom_minimum_size = Vector2(194, 154)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_ALL
	card.tooltip_text = "Pokaż szczegóły i rozwój osoby %s." % survivor.display_name
	card.add_theme_stylebox_override("normal", _community_survivor_card_style(selected, false))
	card.add_theme_stylebox_override("hover", _community_survivor_card_style(selected, true))
	card.add_theme_stylebox_override("focus", _community_survivor_card_style(true, true))
	card.add_theme_stylebox_override("pressed", _community_survivor_card_style(true, true))
	card.pressed.connect(_on_community_survivor_card_pressed.bind(str(survivor.id)))
	parent.add_child(card)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	var portrait = SurvivorPortraitScript.new()
	portrait.name = "CommunityPortrait_%s" % survivor.id
	portrait.custom_minimum_size = Vector2(70, 92)
	portrait.configure(str(survivor.portrait_id), str(survivor.display_name))
	row.add_child(portrait)
	var copy := VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 3)
	row.add_child(copy)
	var name_label := Label.new()
	name_label.text = str(survivor.display_name).to_upper()
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", UI_TEXT)
	copy.add_child(name_label)
	var level_label := Label.new()
	level_label.text = "POZIOM %d" % survivor.level
	level_label.add_theme_font_size_override("font_size", 11)
	level_label.add_theme_color_override("font_color", UI_TEAL)
	copy.add_child(level_label)
	var assignment_label := Label.new()
	assignment_label.text = "BEZ PRZYDZIAŁU" if str(survivor.current_assignment).is_empty() else "OBSADA • %s" % str(survivor.current_assignment).to_upper()
	assignment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	assignment_label.add_theme_font_size_override("font_size", 10)
	assignment_label.add_theme_color_override("font_color", UI_TEXT_MUTED)
	copy.add_child(assignment_label)
	var alert_label := Label.new()
	var development_alerts: Array[String] = []
	if survivor.unspent_skill_points > 0:
		development_alerts.append("%d PKT DO WYDANIA" % survivor.unspent_skill_points)
	if _has_ready_career_path(survivor):
		development_alerts.append("GOTOWY AWANS")
	if _has_ready_talent_choice(survivor):
		development_alerts.append("TALENT DO WYBORU")
	alert_label.text = "▲ %s" % " • ".join(development_alerts) if not development_alerts.is_empty() else "SZCZEGÓŁY"
	alert_label.add_theme_font_size_override("font_size", 10)
	alert_label.add_theme_color_override("font_color", UI_AMBER if not development_alerts.is_empty() else UI_TEXT_MUTED)
	copy.add_child(alert_label)

func _build_community_career_content(content: VBoxContainer, survivor) -> void:
	content.add_child(HSeparator.new())
	_add_section_title(content, "Rozwój zawodowy")
	_add_hint(content, "Zdolna obsada: +100 PD. Rzeczywiście wykonana praca: +20 praktyki odpowiedniej dziedziny.")

	var primary_definition = _career_progression_system.get_profession_definition(str(survivor.profession))
	var primary_name := str(primary_definition.display_name) if primary_definition != null else str(survivor.profession).capitalize()
	var secondary_name := "brak — wybór pozostaje wolny"
	if not str(survivor.secondary_profession).is_empty():
		var secondary_definition = _career_progression_system.get_profession_definition(str(survivor.secondary_profession))
		secondary_name = str(secondary_definition.display_name) if secondary_definition != null else str(survivor.secondary_profession).capitalize()
	var summary := Label.new()
	summary.name = "CommunityCareerSummary"
	summary.text = "SPECJALIZACJA GŁÓWNA  •  %s\nDRUGA SPECJALIZACJA  •  %s" % [primary_name.to_upper(), secondary_name.to_upper()]
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_color_override("font_color", UI_AMBER)
	summary.add_theme_font_size_override("font_size", 14)
	content.add_child(summary)

	_build_community_talent_content(content, survivor)

	var profession_ids: Array[String] = []
	for profession_id in _career_progression_system.get_profession_ids():
		if profession_id != str(survivor.profession):
			profession_ids.append(profession_id)
	if profession_ids.is_empty():
		_add_hint(content, "Brak dostępnych dodatkowych ścieżek zawodowych.")
		return

	var selected_profession_id := _resolve_selected_community_profession(survivor, profession_ids)
	var picker := OptionButton.new()
	picker.name = "CommunityProfessionPicker"
	picker.custom_minimum_size = Vector2(0, 44)
	picker.fit_to_longest_item = false
	picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var selected_index := 0
	for profession_id in profession_ids:
		var definition = _career_progression_system.get_profession_definition(profession_id)
		if definition == null:
			continue
		var experience := mini(survivor.get_job_experience(profession_id), int(definition.promotion_experience))
		var rank_name := _career_progression_system.get_rank_display_name(survivor, profession_id)
		picker.add_item("%s  •  %s  •  %d/%d praktyki" % [definition.display_name, rank_name, experience, int(definition.promotion_experience)])
		var item_index := picker.item_count - 1
		picker.set_item_metadata(item_index, profession_id)
		if profession_id == selected_profession_id:
			selected_index = item_index
	picker.select(selected_index)
	picker.item_selected.connect(_on_community_profession_selected.bind(picker, survivor.id))
	content.add_child(picker)

	var definition = _career_progression_system.get_profession_definition(selected_profession_id)
	if definition == null:
		return
	var experience := mini(survivor.get_job_experience(selected_profession_id), int(definition.promotion_experience))
	var rank_id := _career_progression_system.get_rank_id(survivor, selected_profession_id)
	var rank_name := _career_progression_system.get_rank_display_name(survivor, selected_profession_id)
	var progress := Label.new()
	progress.name = "CommunityCareerProgress"
	progress.text = "%s  •  %s  •  %d / %d PRAKTYKI" % [str(definition.display_name).to_upper(), rank_name, experience, int(definition.promotion_experience)]
	progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress.add_theme_color_override("font_color", UI_TEAL if rank_id != CareerProgressionSystemScript.RANK_READY else UI_AMBER)
	progress.add_theme_font_size_override("font_size", 16)
	content.add_child(progress)

	var detail := Label.new()
	detail.name = "CommunityCareerDetail"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.text = "%s %s" % [definition.description, definition.specialist_benefit]
	content.add_child(detail)
	if rank_id == CareerProgressionSystemScript.RANK_NOVICE:
		_add_hint(content, "Do stopnia ucznia brakuje %d praktyki." % maxi(int(definition.apprentice_experience) - experience, 0))
	elif rank_id == CareerProgressionSystemScript.RANK_APPRENTICE:
		_add_hint(content, "Uczeń zna podstawy. Do gotowości do awansu pozostały %d dni rzeczywistej pracy." % _career_progression_system.days_until_promotion(survivor, selected_profession_id))
	elif rank_id == CareerProgressionSystemScript.RANK_READY:
		_add_hint(content, "Praktyka została opanowana. Pełna premia włączy się po formalnym nadaniu drugiej specjalizacji.")
	elif rank_id == CareerProgressionSystemScript.RANK_LOCKED:
		_add_hint(content, "Limit drugiej specjalizacji został już wykorzystany. Zachowana praktyka tej ścieżki nie może być dalej rozwijana ani awansowana.")
	else:
		_add_hint(content, "Ta specjalizacja jest aktywna i zapewnia pełną premię w odpowiednim budynku.")

	var promote_button := Button.new()
	promote_button.name = "PromoteProfessionButton"
	promote_button.custom_minimum_size = Vector2(0, 52)
	var blocker := _career_progression_system.promotion_blocker(_state, survivor, selected_profession_id)
	if str(survivor.secondary_profession) == selected_profession_id:
		promote_button.text = "DRUGA SPECJALIZACJA: %s" % str(definition.display_name).to_upper()
	else:
		promote_button.text = "AWANSUJ: %s" % str(definition.display_name).to_upper()
	promote_button.disabled = not blocker.is_empty()
	promote_button.tooltip_text = blocker if not blocker.is_empty() else "Nadaj tę jedyną, trwałą drugą specjalizację."
	promote_button.pressed.connect(_confirm_community_promotion.bind(survivor.id, selected_profession_id, str(definition.display_name)))
	content.add_child(promote_button)
	if not blocker.is_empty():
		_add_hint(content, blocker)
	else:
		_add_hint(content, "Awans jest natychmiastowy i nie zużywa materiałów ani dnia, ale wybór drugiej specjalizacji jest nieodwracalny.")
	if str(survivor.secondary_profession) == selected_profession_id:
		_add_status_callout(
			content,
			"DRUGA SPECJALIZACJA AKTYWNA",
			"%s korzysta teraz z pełnej premii: %s." % [survivor.display_name, str(definition.display_name)],
			UI_GREEN
		)

func _resolve_selected_community_profession(survivor, profession_ids: Array[String]) -> String:
	var stored_id := str(_selected_community_profession_by_survivor.get(str(survivor.id), ""))
	if profession_ids.has(stored_id):
		return stored_id
	if profession_ids.has(str(survivor.secondary_profession)):
		_selected_community_profession_by_survivor[str(survivor.id)] = str(survivor.secondary_profession)
		return str(survivor.secondary_profession)
	var selected_id := profession_ids[0]
	var selected_experience := -1
	for profession_id in profession_ids:
		var experience: int = int(survivor.get_job_experience(profession_id))
		if experience > selected_experience:
			selected_id = profession_id
			selected_experience = experience
	_selected_community_profession_by_survivor[str(survivor.id)] = selected_id
	return selected_id


func _build_community_talent_content(content: VBoxContainer, survivor) -> void:
	_add_section_title(content, "Talenty zawodowe")
	_add_hint(content, "Po osiągnięciu 100 praktyki formalna specjalizacja wybiera bez kosztu jeden z dwóch trwałych talentów. Wymagany jest aktywny Dom Wspólnoty II.")
	for profession_id in [str(survivor.profession), str(survivor.secondary_profession)]:
		if profession_id.is_empty():
			continue
		_build_community_talent_section(content, survivor, profession_id)


func _build_community_talent_section(content: VBoxContainer, survivor, profession_id: String) -> void:
	var profession_definition = _career_progression_system.get_profession_definition(profession_id)
	var profession_name := str(profession_definition.display_name) if profession_definition != null else profession_id.capitalize()
	var talent_ids := _profession_talent_system.get_talent_ids_for_profession(profession_id)
	if talent_ids.is_empty():
		return
	var heading := Label.new()
	heading.name = "ProfessionTalentHeading_%s" % profession_id
	heading.text = "%s  •  WYBÓR TALENTU" % profession_name.to_upper()
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", UI_AMBER)
	content.add_child(heading)

	var selected_id := ProfessionTalentSystemScript.selected_talent_id(survivor, profession_id)
	if not selected_id.is_empty():
		var selected_definition = _profession_talent_system.get_definition(selected_id)
		_add_status_callout(
			content,
			"TALENT AKTYWNY  •  %s" % (str(selected_definition.display_name).to_upper() if selected_definition != null else selected_id.to_upper()),
			str(selected_definition.description) if selected_definition != null else "Trwały wybór został zapisany.",
			UI_GREEN
		)

	var choices := GridContainer.new()
	choices.name = "ProfessionTalentChoices_%s" % profession_id
	choices.columns = 2
	choices.add_theme_constant_override("h_separation", 8)
	choices.add_theme_constant_override("v_separation", 8)
	content.add_child(choices)
	var first_blocker := ""
	var any_available := false
	for talent_id in talent_ids:
		var definition = _profession_talent_system.get_definition(talent_id)
		if definition == null:
			continue
		var blocker := _career_progression_system.profession_talent_selection_blocker(_state, survivor, talent_id)
		if first_blocker.is_empty() and not blocker.is_empty():
			first_blocker = blocker
		if blocker.is_empty():
			any_available = true
		var button := Button.new()
		button.name = "SelectProfessionTalent_%s" % talent_id
		button.text = "%s%s\n%s" % [
			"✓  " if selected_id == talent_id else "",
			str(definition.display_name).to_upper(),
			str(definition.description),
		]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, 126)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not blocker.is_empty()
		button.tooltip_text = "%s\n\n%s" % [
			str(definition.description),
			"Nie można wybrać: %s" % blocker if not blocker.is_empty() else "Kliknij, aby potwierdzić ten bezpłatny i nieodwracalny wybór.",
		]
		button.pressed.connect(_confirm_profession_talent.bind(str(survivor.id), talent_id, str(definition.display_name), profession_name))
		choices.add_child(button)
	if selected_id.is_empty():
		if any_available:
			_add_hint(content, "Wybór jest natychmiastowy, bezpłatny i nieodwracalny. Drugi talent tej specjalizacji zostanie trwale zamknięty.")
		elif not first_blocker.is_empty():
			_add_hint(content, first_blocker)


func _confirm_profession_talent(survivor_id: String, talent_id: String, talent_name: String, profession_name: String) -> void:
	var survivor = _state.find_survivor(survivor_id) if _state != null else null
	if survivor == null or not _career_progression_system.can_select_profession_talent(_state, survivor, talent_id):
		return
	var panel_scroll := _panel_scroll()
	var preserved_scroll := panel_scroll.scroll_vertical if panel_scroll != null else 0
	var dialog := ConfirmationDialog.new()
	dialog.name = "ProfessionTalentConfirmation"
	dialog.title = "Potwierdź talent zawodowy"
	dialog.dialog_text = "Wybrać talent „%s” dla specjalizacji %s osoby %s?\n\nTo bezpłatna, ale trwała decyzja. Drugi talent tej specjalizacji zostanie nieodwracalnie zamknięty." % [talent_name, profession_name, survivor.display_name]
	dialog.ok_button_text = "WYBIERZ TALENT"
	dialog.cancel_button_text = "ANULUJ"
	dialog.confirmed.connect(func():
		_restore_scroll_after_rebuild = preserved_scroll
		_focus_control_after_rebuild = "CommunityProfessionPicker"
		dialog.hide()
		dialog.queue_free()
		profession_talent_requested.emit(survivor_id, talent_id)
	)
	dialog.canceled.connect(func():
		dialog.hide()
		dialog.queue_free()
		var talent_button := find_child("SelectProfessionTalent_%s" % talent_id, true, false) as Button
		if talent_button != null:
			talent_button.call_deferred("grab_focus")
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(620, 280))

func _has_ready_career_path(survivor) -> bool:
	if survivor == null or not str(survivor.secondary_profession).is_empty():
		return false
	for profession_id in _career_progression_system.get_profession_ids():
		if profession_id == str(survivor.profession):
			continue
		var definition = _career_progression_system.get_profession_definition(profession_id)
		if definition != null and survivor.get_job_experience(profession_id) >= int(definition.promotion_experience):
			return true
	return false


func _has_ready_talent_choice(survivor) -> bool:
	return _career_progression_system.has_selectable_profession_talent(_state, survivor)

func _on_community_profession_selected(index: int, picker: OptionButton, survivor_id: String) -> void:
	if index < 0 or index >= picker.item_count:
		return
	_selected_community_profession_by_survivor[survivor_id] = str(picker.get_item_metadata(index))
	var panel_scroll := _panel_scroll()
	_restore_scroll_after_rebuild = panel_scroll.scroll_vertical if panel_scroll != null else 0
	_focus_community_profession_picker_after_rebuild = true
	_rebuild()

func _confirm_community_promotion(survivor_id: String, profession_id: String, profession_name: String) -> void:
	var survivor = _state.find_survivor(survivor_id) if _state != null else null
	if survivor == null or not _career_progression_system.can_promote(_state, survivor, profession_id):
		return
	var panel_scroll := _panel_scroll()
	var preserved_scroll := panel_scroll.scroll_vertical if panel_scroll != null else 0
	var dialog := ConfirmationDialog.new()
	dialog.name = "CareerPromotionConfirmation"
	dialog.title = "Potwierdź drugą specjalizację"
	dialog.dialog_text = "Nadać osobie %s drugą specjalizację „%s”?\n\nTo trwała decyzja — ta osoba nie będzie mogła zdobyć innej drugiej specjalizacji." % [survivor.display_name, profession_name]
	dialog.ok_button_text = "NADAJ SPECJALIZACJĘ"
	dialog.cancel_button_text = "ANULUJ"
	dialog.confirmed.connect(func():
		_restore_scroll_after_rebuild = preserved_scroll
		_focus_control_after_rebuild = "CommunityProfessionPicker"
		career_promotion_requested.emit(survivor_id, profession_id)
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
		var promote_button := find_child("PromoteProfessionButton", true, false) as Button
		if promote_button != null:
			promote_button.call_deferred("grab_focus")
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(560, 240))

func _resolve_selected_community_survivor(survivors: Array):
	for survivor in survivors:
		if survivor.id == _selected_community_survivor_id:
			return survivor
	for survivor in survivors:
		if _has_ready_career_path(survivor):
			_selected_community_survivor_id = survivor.id
			return survivor
	for survivor in survivors:
		if _has_ready_talent_choice(survivor):
			_selected_community_survivor_id = survivor.id
			return survivor
	for survivor in survivors:
		if survivor.unspent_skill_points > 0:
			_selected_community_survivor_id = survivor.id
			return survivor
	_selected_community_survivor_id = survivors[0].id
	return survivors[0]

func _on_community_survivor_card_pressed(survivor_id: String) -> void:
	_selected_community_survivor_id = survivor_id
	var panel_scroll := _panel_scroll()
	_restore_scroll_after_rebuild = 0 if panel_scroll != null else -1
	_focus_community_picker_after_rebuild = true
	_rebuild()

func _add_community_development_button(parent: GridContainer, survivor, stat_id: String, title: String, description: String) -> void:
	var button := Button.new()
	button.name = "Develop_%s" % stat_id
	button.text = "%s\n%s" % [title, description]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0, 64)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var blocker := _community_development_blocker(survivor, stat_id)
	button.disabled = not blocker.is_empty()
	var explanation := (
		CompetencySystemScript.tooltip_text(survivor, stat_id)
		if CompetencySystemScript.is_valid_id(stat_id)
		else description
	)
	button.tooltip_text = "%s\n\n%s" % [
		explanation,
		"Nie można rozwinąć: %s" % blocker if not blocker.is_empty() else "Kliknij, aby wydać jeden punkt rozwoju na trwałe ulepszenie.",
	]
	button.pressed.connect(_on_community_development_pressed.bind(str(survivor.id), stat_id, str(button.name)))
	parent.add_child(button)

func _on_community_development_pressed(survivor_id: String, stat_id: String, focus_name: String) -> void:
	_remember_community_view(focus_name)
	survivor_development_requested.emit(survivor_id, stat_id)

func _remember_community_view(focus_name: String = "") -> void:
	var panel_scroll := _panel_scroll()
	_restore_scroll_after_rebuild = panel_scroll.scroll_vertical if panel_scroll != null else 0
	_focus_control_after_rebuild = focus_name

func _on_worker_picker_requested(building_id: String, slot_index: int) -> void:
	var panel_scroll := _active_scroll()
	_restore_scroll_after_rebuild = panel_scroll.scroll_vertical if panel_scroll != null else 0
	_focus_control_after_rebuild = "WorkerChangeButton" if slot_index == 0 else "WorkerChangeButton%d" % (slot_index + 1)
	worker_picker_requested.emit(building_id, slot_index)


func focus_worker_slot(slot_index: int) -> void:
	var control_name := "WorkerChangeButton" if slot_index == 0 else "WorkerChangeButton%d" % (slot_index + 1)
	var candidate := _find_workspace_control(control_name)
	if candidate != null and candidate.is_visible_in_tree() and candidate.focus_mode != Control.FOCUS_NONE:
		candidate.grab_focus()
		return
	focus_initial()

func _on_station_gear_equipped(slot_id: String, gear_id: String) -> void:
	var panel_scroll := _active_scroll()
	_restore_scroll_after_rebuild = panel_scroll.scroll_vertical if panel_scroll != null else 0
	_focus_control_after_rebuild = "OxygenTankGearPicker" if slot_id == "oxygen_tank" else "LightGearPicker"
	gear_equipped.emit(slot_id, gear_id)

func _on_station_diver_selected(survivor_id: String) -> void:
	var panel_scroll := _active_scroll()
	_restore_scroll_after_rebuild = panel_scroll.scroll_vertical if panel_scroll != null else 0
	_focus_control_after_rebuild = "DiverCandidate_%s" % survivor_id
	diver_selected.emit(survivor_id)

func _on_station_entry_point_selected(entry_point_id: String) -> void:
	var panel_scroll := _active_scroll()
	_restore_scroll_after_rebuild = panel_scroll.scroll_vertical if panel_scroll != null else 0
	_focus_control_after_rebuild = "EntryPointPicker"
	entry_point_selected.emit(entry_point_id)

func _on_station_disclosure_state_changed(profile_expanded: bool, equipment_expanded: bool) -> void:
	_station_profile_details_expanded = profile_expanded
	_station_equipment_details_expanded = equipment_expanded

func focus_initial() -> void:
	if not is_visible_in_tree():
		return
	_configure_focus_loop()
	var preferred_names: Array[String] = []
	if _building == null:
		preferred_names.append("BuildButton")
	elif _tutorial_step == TutorialStateScript.Step.ASSIGN_DIVER_FIRST and _definition != null and _definition.id == "diving_station":
		preferred_names.append("DiverCandidate_igor")
	elif _tutorial_step in [TutorialStateScript.Step.ASSIGN_COMMUNITY_WORKER, TutorialStateScript.Step.STAFF_WORKSHOP]:
		preferred_names.append("WorkerChangeButton")
	elif _definition != null and _definition.id == "diving_station" and _tutorial_step in [TutorialStateScript.Step.START_FIRST_DIVE, TutorialStateScript.Step.START_FINAL_DIVE]:
		preferred_names.append("DiveButton")
	elif _definition != null and _definition.id == "workshop" and _tutorial_step == TutorialStateScript.Step.CRAFT_RESCUE_KNIFE:
		preferred_names.append("Craft_tutorial_rescue_knife")
	elif _definition != null and _definition.id == "community_house":
		preferred_names.append("CommunitySurvivorCard_%s" % _selected_community_survivor_id)
	elif _definition != null and _definition.id == "workshop":
		for craft_node in find_children("Craft_*", "Button", true, false):
			var craft_button := craft_node as Button
			if craft_button != null and craft_button.is_visible_in_tree() and not craft_button.disabled:
				craft_button.grab_focus()
				return
	elif _definition != null and _definition.id == "diving_station":
		preferred_names.append("DiveButton")
	preferred_names.append("BuildingDetailsButton")
	preferred_names.append("CloseButton")
	for control_name in preferred_names:
		var candidate := _find_workspace_control(control_name)
		if candidate == null or not candidate.is_visible_in_tree() or candidate.focus_mode == Control.FOCUS_NONE:
			continue
		if candidate is BaseButton and (candidate as BaseButton).disabled:
			continue
		candidate.grab_focus()
		return

func _configure_focus_loop() -> void:
	if not is_visible_in_tree():
		return
	var controls: Array[Control] = []
	var focus_root := _focus_scope if _focus_scope != null and is_instance_valid(_focus_scope) else self
	_collect_focusable_controls(focus_root, controls)
	for external_scope in _external_focus_scopes:
		_collect_focusable_scope(external_scope, controls)
	if controls.is_empty():
		return
	if controls.size() == 1:
		var only := controls[0]
		only.focus_previous = NodePath(".")
		only.focus_next = NodePath(".")
		only.focus_neighbor_left = NodePath(".")
		only.focus_neighbor_top = NodePath(".")
		only.focus_neighbor_right = NodePath(".")
		only.focus_neighbor_bottom = NodePath(".")
		return
	for index in range(controls.size()):
		var control := controls[index]
		var previous := controls[(index - 1 + controls.size()) % controls.size()]
		var next := controls[(index + 1) % controls.size()]
		var previous_path := control.get_path_to(previous)
		var next_path := control.get_path_to(next)
		control.focus_previous = previous_path
		control.focus_next = next_path
		control.focus_neighbor_left = previous_path
		control.focus_neighbor_top = previous_path
		control.focus_neighbor_right = next_path
		control.focus_neighbor_bottom = next_path

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

func _build_workshop_production_content(content: VBoxContainer) -> void:
	content.add_child(HSeparator.new())
	_add_section_title(content, "Produkcja sprzętu nurkowego")
	if _tutorial_step == TutorialStateScript.Step.CRAFT_RESCUE_KNIFE:
		_add_body(content, "Nóż ratowniczy przecina sieci blokujące kabel Pomostu 7. To jedyne zlecenie tutorialowe wykonywane natychmiast.")
		_add_section_title(content, "Koszt: Nóż ratowniczy")
		_add_cost_rows(content, {ResourceIdsScript.SCRAP: 3, ResourceIdsScript.FABRIC_RUBBER: 2})
		var knife_button := Button.new()
		knife_button.name = "Craft_tutorial_rescue_knife"
		knife_button.text = "Wykonaj natychmiast: Nóż ratowniczy"
		knife_button.custom_minimum_size = Vector2(0, 46)
		var knife_blocker := ""
		if _building.assigned_survivor_ids.is_empty():
			knife_blocker = "Najpierw przydziel zdolnego pracownika do Warsztatu."
		elif _state.resources.get_amount(ResourceIdsScript.SCRAP) < 3 or _state.resources.get_amount(ResourceIdsScript.FABRIC_RUBBER) < 2:
			knife_blocker = "Brak 3 złomu lub 2 tkanin i gumy."
		knife_button.disabled = not knife_blocker.is_empty()
		knife_button.tooltip_text = knife_blocker if not knife_blocker.is_empty() else "Pobierz stały koszt i trwale odblokuj narzędzie."
		knife_button.add_theme_stylebox_override("normal", _target_button_style())
		knife_button.pressed.connect(_on_production_pressed.bind(_building.id, "tutorial_rescue_knife", str(knife_button.name)))
		content.add_child(knife_button)
		return
	if _building.assigned_survivor_ids.is_empty():
		_add_hint(content, "Przydziel pracownika do Warsztatu, aby zaplanować produkcję.")
	if not _building.queued_production_orders.is_empty():
		var daily_work_points := _workshop_daily_work_points()
		var blocker := _workshop_queue_blocker()
		var cumulative_remaining := 0
		for index in range(_building.queued_production_orders.size()):
			var order = _building.queued_production_orders[index]
			if order == null:
				_add_hint(content, "Pozycja %d kolejki ma uszkodzony zapis i nie zostanie automatycznie usunięta." % (index + 1))
				continue
			var reserved_cost := _format_reserved_workshop_cost(order.reserved_cost)
			var required_work_points := maxi(int(order.required_work_points), 1)
			var progress := clampi(int(order.work_progress), 0, required_work_points - 1)
			cumulative_remaining += required_work_points - progress
			var queued_label := "zlecenie ze starszego zapisu" if int(order.queued_day) == 0 else "zlecone dnia %d" % int(order.queued_day)
			var timing := "Termin odroczony — %s" % blocker
			if blocker.is_empty():
				var required_days := maxi(ceili(float(cumulative_remaining) / float(maxi(daily_work_points, 1))), 1)
				var earliest_day := int(_state.day) + required_days - 1
				var queue_reason := "" if required_days <= 1 else " Bloker: pozostała praca wcześniejszych pozycji FIFO."
				timing = "Najwcześniej: koniec dnia %d.%s" % [earliest_day, queue_reason]
			_add_hint(
				content,
				"%d. %s — postęp %d/%d (%s)\nZarezerwowano: %s. %s"
				% [index + 1, str(order.output_display_name), progress, required_work_points, queued_label, reserved_cost, timing]
			)

	# Resolve the autoload through the scene tree so this reusable panel also
	# compiles when loaded dynamically by standalone SceneTree tests.
	var main_loop := Engine.get_main_loop() as SceneTree
	var game_database := main_loop.root.get_node_or_null("GameDatabase") if main_loop != null and main_loop.root != null else null
	if game_database == null:
		_add_hint(content, "Baza definicji sprzętu jest niedostępna.")
		return
	var recipe_ids: Array[String] = []
	for recipe_id in game_database.workshop_recipes.keys():
		var recipe = game_database.workshop_recipes[recipe_id]
		if recipe == null:
			continue
		if not str(recipe.prerequisite_story_flag).is_empty() and (_state.story_flags == null or not _state.story_flags.has_flag(str(recipe.prerequisite_story_flag))):
			continue
		recipe_ids.append(str(recipe_id))
	recipe_ids.sort_custom(func(left_id: String, right_id: String) -> bool:
		var left = game_database.workshop_recipes[left_id]
		var right = game_database.workshop_recipes[right_id]
		if int(left.required_workshop_level) != int(right.required_workshop_level):
			return int(left.required_workshop_level) < int(right.required_workshop_level)
		return str(left.display_name).naturalnocasecmp_to(str(right.display_name)) < 0
	)
	if recipe_ids.is_empty():
		_add_hint(content, "Brak odblokowanych receptur Warsztatu.")
		return
	if not recipe_ids.has(_selected_workshop_recipe_id):
		_selected_workshop_recipe_id = recipe_ids[0]

	_add_hint(content, "Wybierz przedmiot. Katalog rozszerza się automatycznie wraz z nowymi recepturami.")
	var recipe_grid := GridContainer.new()
	recipe_grid.name = "WorkshopRecipeGrid"
	recipe_grid.columns = 3
	recipe_grid.add_theme_constant_override("h_separation", 8)
	recipe_grid.add_theme_constant_override("v_separation", 8)
	content.add_child(recipe_grid)
	for recipe_id in recipe_ids:
		var recipe = game_database.workshop_recipes[recipe_id]
		var selected := recipe_id == _selected_workshop_recipe_id
		var tile := Button.new()
		tile.name = "RecipeTile_%s" % recipe_id
		tile.custom_minimum_size = Vector2(118, 112)
		tile.text = "%s\n%s\nPOZ. %d" % [_workshop_recipe_symbol(recipe), str(recipe.display_name), int(recipe.required_workshop_level)]
		tile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tile.tooltip_text = str(recipe.description)
		tile.add_theme_font_size_override("font_size", 12)
		tile.add_theme_color_override("font_color", UI_AMBER if selected else UI_TEXT)
		tile.add_theme_stylebox_override("normal", _workshop_recipe_tile_style(selected, false))
		tile.add_theme_stylebox_override("hover", _workshop_recipe_tile_style(selected, true))
		tile.add_theme_stylebox_override("focus", _workshop_recipe_tile_style(true, true))
		tile.pressed.connect(_on_workshop_recipe_selected.bind(recipe_id, str(tile.name)))
		recipe_grid.add_child(tile)

	var selected_recipe = game_database.workshop_recipes[_selected_workshop_recipe_id]
	content.add_child(HSeparator.new())
	_add_section_title(content, str(selected_recipe.display_name))
	_add_body(content, str(selected_recipe.description))
	var completion_text := _workshop_recipe_completion_text(selected_recipe)
	if not completion_text.is_empty():
		_add_hint(content, completion_text, "WorkshopSelectedRecipeStatus")
	_add_section_title(content, "Koszt materiałów")
	_add_cost_rows(content, _production_system.get_craft_cost(selected_recipe))
	_add_hint(content, "Wymagany Warsztat: poziom %d. Wymagana praca: %d punktów." % [int(selected_recipe.required_workshop_level), int(selected_recipe.required_work_points)])
	var prerequisite_id := str(selected_recipe.prerequisite_gear_id)
	if not prerequisite_id.is_empty() and not _state.diving_equipment.owns(prerequisite_id):
		var prerequisite_definition = game_database.diving_gear.get(prerequisite_id)
		_add_hint(content, "Wymaga posiadanego sprzętu: %s." % (prerequisite_definition.display_name if prerequisite_definition != null else prerequisite_id))
	if completion_text.is_empty():
		var craft_button := Button.new()
		craft_button.name = "Craft_%s" % selected_recipe.id
		craft_button.text = "Wyprodukuj: %s" % selected_recipe.display_name
		craft_button.custom_minimum_size = Vector2(0, 46)
		var craft_blocker := str(_production_system.queue_recipe_blocker(_state, _building, selected_recipe))
		craft_button.disabled = not craft_blocker.is_empty()
		craft_button.tooltip_text = craft_blocker if not craft_blocker.is_empty() else "Zarezerwuj materiały i dodaj przedmiot do kolejki Warsztatu."
		craft_button.pressed.connect(_on_production_pressed.bind(_building.id, str(selected_recipe.id), str(craft_button.name)))
		content.add_child(craft_button)
	_add_hint(content, "Produkcja zużywa dzienną pracę Warsztatu; tego dnia budynek nie wykonuje automatycznej naprawy platformy.")


func _on_workshop_recipe_selected(recipe_id: String, focus_name: String) -> void:
	if recipe_id == _selected_workshop_recipe_id:
		return
	var panel_scroll := _active_scroll()
	_restore_scroll_after_rebuild = panel_scroll.scroll_vertical if panel_scroll != null else 0
	_selected_workshop_recipe_id = recipe_id
	_focus_control_after_rebuild = focus_name
	_rebuild()


func _workshop_recipe_completion_text(recipe) -> String:
	if not str(recipe.output_gear_id).is_empty() and _state.diving_equipment.owns(str(recipe.output_gear_id)):
		return "Ten przedmiot jest już wyprodukowany."
	if str(recipe.output_campaign_id) == "r3_regulator" and (_state.story_flags.r3_regulator_ready or _state.story_flags.r3_generator_active):
		return "To zlecenie fabularne zostało już wykonane."
	if str(recipe.output_campaign_id) == "common_line_splitter" and (_state.story_flags.common_line_splitter_ready or _state.story_flags.common_line_splitter_installed):
		return "To zlecenie fabularne zostało już wykonane."
	if _workshop_has_queued_recipe_or_output(str(recipe.id), str(recipe.output_gear_id)):
		return "Ten przedmiot znajduje się już w kolejce Warsztatu."
	return ""


func _workshop_recipe_symbol(recipe) -> String:
	var recipe_id := str(recipe.id)
	if "lantern" in recipe_id:
		return "LATARNIA"
	if "oxygen_tank" in recipe_id:
		return "TLEN"
	if "harpoon" in recipe_id:
		return "HARPUN"
	return "CZĘŚĆ"


func _workshop_daily_work_points() -> int:
	if _definition == null:
		return 100
	var level_definition = _definition.get_level_definition(int(_building.level))
	var slots := maxi(int(level_definition.capabilities.get("production_slots_per_day", 1)), 1) if level_definition != null else 1
	return int(round(float(slots * 100) * _work_pace_system.output_multiplier(_work_pace_system.pace_for_building(_state, _building))))


func _workshop_queue_blocker() -> String:
	if not bool(_building.is_built):
		return "Warsztat jest w budowie"
	if int(_building.pending_level) > int(_building.level):
		return "trwa ulepszenie Warsztatu"
	if int(_building.condition) <= 0:
		return "Warsztat jest obecnie nieaktywny"
	for survivor_id in _building.assigned_survivor_ids:
		var survivor = _state.find_survivor(str(survivor_id))
		if survivor != null and survivor.can_work():
			return ""
	return "brak zdolnej do pracy obsady"


func _format_reserved_workshop_cost(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for resource_id in [ResourceIdsScript.SCRAP, ResourceIdsScript.FABRIC_RUBBER, ResourceIdsScript.TECH_PARTS]:
		if int(cost.get(resource_id, 0)) > 0:
			parts.append("%d %s" % [int(cost[resource_id]), ResourceIdsScript.display_name(resource_id).to_lower()])
	for raw_resource_id in cost.keys():
		var resource_id := str(raw_resource_id)
		if resource_id in [ResourceIdsScript.SCRAP, ResourceIdsScript.FABRIC_RUBBER, ResourceIdsScript.TECH_PARTS] or int(cost[raw_resource_id]) <= 0:
			continue
		parts.append("%d %s" % [int(cost[raw_resource_id]), ResourceIdsScript.display_name(resource_id).to_lower()])
	return ", ".join(parts) if not parts.is_empty() else "brak materiałów"


func _workshop_has_queued_recipe_or_output(recipe_id: String, output_gear_id: String) -> bool:
	for order in _building.queued_production_orders:
		if order == null or str(order.recipe_id) == recipe_id or str(order.output_gear_id) == output_gear_id:
			return true
	return false

func _on_production_pressed(building_id: String, recipe_id: String, focus_name: String) -> void:
	var panel_scroll := _active_scroll()
	_restore_scroll_after_rebuild = panel_scroll.scroll_vertical if panel_scroll != null else 0
	_focus_control_after_rebuild = focus_name
	production_requested.emit(building_id, recipe_id)

func _add_effect_card(content: VBoxContainer, heading_text: String, raw_lines, label_name: String, accent: Color) -> void:
	var lines: Array[String] = []
	if raw_lines is Array:
		for raw_line in raw_lines:
			var line := str(raw_line).strip_edges()
			if not line.is_empty():
				lines.append(line)
	if lines.is_empty():
		return

	var card := PanelContainer.new()
	card.name = "%sCard" % label_name
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _effect_card_style(accent))
	content.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	var heading := Label.new()
	heading.text = heading_text
	heading.add_theme_font_size_override("font_size", 12)
	heading.add_theme_color_override("font_color", accent)
	column.add_child(heading)

	var body := Label.new()
	body.name = label_name
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", _content_ink(content))
	var body_text := ""
	for line in lines:
		if not body_text.is_empty():
			body_text += "\n"
		body_text += "• %s" % line
	body.text = body_text
	column.add_child(body)

func _add_cost_rows(content: VBoxContainer, cost: Dictionary) -> void:
	if cost.is_empty():
		_add_hint(content, "Koszt nie został jeszcze zdefiniowany.")
		return
	for resource_id in cost.keys():
		var needed := int(cost[resource_id])
		var available: int = _state.resources.get_amount(str(resource_id))
		var row := Label.new()
		row.text = "%s    %d / %d" % [ResourceIdsScript.display_name(str(resource_id)), available, needed]
		row.add_theme_font_size_override("font_size", 13)
		row.add_theme_color_override("font_color", UI_GREEN if available >= needed else UI_CORAL)
		content.add_child(row)

func _add_section_title(content: VBoxContainer, value: String) -> void:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UI_TEAL_LIGHT if bool(content.get_meta("dark_surface", false)) else UI_TEAL)
	content.add_child(label)

func _add_body(content: VBoxContainer, value: String) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", _content_ink(content))
	content.add_child(label)

func _add_hint(content: VBoxContainer, value: String, label_name: String = "") -> void:
	var label := Label.new()
	if not label_name.is_empty():
		label.name = label_name
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", _content_muted_ink(content))
	label.add_theme_font_size_override("font_size", 13)
	content.add_child(label)

func _status_text() -> String:
	if _building == null:
		return "ZRUJNOWANY"
	if not _building.is_built:
		return "STARSZY ZAPIS"
	if _building.pending_level > _building.level:
		return "STARSZY ZAPIS"
	if _building.condition <= 0:
		return "NIEAKTYWNY"
	if _building.assigned_survivor_ids.is_empty():
		if _definition != null and str(_definition.id) == "community_house":
			return "AKTYWNY  •  SCHRONIENIE"
		return "GOTOWY  •  BEZ OBSADY"
	if not _has_capable_assigned_worker():
		return "OBSADA NIEZDOLNA  •  EFEKT 0"
	var preview: Dictionary = _building_effect_system.staffing_preview(_state, _definition, _building)
	match str(preview.get("mode", "")):
		"dive_ready":
			return "GOTOWY DO WYPRAWY"
		"dive_blocked":
			return "OBSADZONY  •  WYPRAWA ZABLOKOWANA"
		"idle":
			return "OBSADZONY  •  BRAK ZADANIA"
		"medical_idle":
			return "OBSADZONY  •  BRAK PACJENTÓW"
		"repair_blocked":
			return "OBSADZONY  •  BRAK ZŁOMU"
		"repair_no_output":
			return "OBSADZONY  •  EFEKT 0"
		"ration_none":
			return "OBSADZONY  •  RACJE WYŁĄCZONE"
		"ration_insufficient":
			return "OBSADZONY  •  ZA MAŁO JEDZENIA"
	return "GOTOWY  •  OBSADZONY"

func _status_color() -> Color:
	if _building == null:
		return UI_DARK_TEXT_MUTED
	if _building.is_under_construction():
		return UI_AMBER
	if _building.condition <= 0:
		return UI_CORAL
	if _building.assigned_survivor_ids.is_empty():
		return UI_GREEN if _definition != null and str(_definition.id) == "community_house" else UI_AMBER
	if not _has_capable_assigned_worker():
		return UI_AMBER
	var mode := str(_building_effect_system.staffing_preview(_state, _definition, _building).get("mode", ""))
	if mode in ["dive_blocked", "idle", "medical_idle", "repair_blocked", "repair_no_output", "ration_none", "ration_insufficient"]:
		return UI_AMBER
	return UI_GREEN

func _has_capable_assigned_worker() -> bool:
	if _building == null or _state == null:
		return false
	for survivor_id in _building.assigned_survivor_ids:
		var survivor = _state.find_survivor(str(survivor_id))
		if survivor != null and survivor.can_work():
			return true
	return false

func _staffing_preview_color(preview: Dictionary) -> Color:
	if not bool(preview.get("active", false)) or int(preview.get("capable_count", 0)) <= 0:
		return UI_CORAL
	var mode := str(preview.get("mode", ""))
	if mode in ["dive_blocked", "idle", "medical_idle", "repair_blocked", "repair_no_output", "ration_none", "ration_insufficient"]:
		return UI_AMBER
	return UI_GREEN


func _apply_primary_button_text(button: Button) -> void:
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, UI_CANVAS)


func _compact_button_style(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UI_PANEL, 0.99)
	style.border_color = UI_BORDER
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 4)
	return style

func _header_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UI_HEADER, 0.98)
	style.border_color = UI_SIDEBAR_BORDER
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	return style

func _sidebar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UI_SIDEBAR, 0.98)
	style.border_color = UI_SIDEBAR_BORDER
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _staffing_sidebar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UI_CANVAS, 0.98)
	style.border_color = UI_SIDEBAR_BORDER
	style.set_border_width_all(2)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style


func _station_footer_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UI_PANEL, 0.98)
	style.border_color = UI_BORDER
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style

func _status_card_style(accent: Color, dark_surface: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UI_SIDEBAR_RAISED if dark_surface else UI_SURFACE_RAISED, 0.95)
	style.border_color = Color(accent.darkened(0.28), 0.78)
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _primary_button_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_AMBER_HOVER if hovered else UI_AMBER
	style.border_color = UI_AMBER_DARK
	style.set_border_width_all(2)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _secondary_button_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_SURFACE_RAISED if hovered else UI_SURFACE
	style.border_color = UI_TEAL if hovered else UI_BORDER_SUBTLE
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _sidebar_secondary_button_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_SIDEBAR_RAISED if hovered else UI_SIDEBAR
	style.border_color = UI_TEAL_LIGHT if hovered else UI_SIDEBAR_BORDER
	style.set_border_width_all(2 if hovered else 1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _effect_card_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UI_SURFACE, 0.94)
	style.border_color = Color(accent.darkened(0.25), 0.82)
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _target_button_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_AMBER_HOVER
	style.border_color = UI_AMBER_DARK
	style.set_border_width_all(3)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _workshop_recipe_tile_style(selected: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_SURFACE_RAISED if hovered else UI_SURFACE
	style.border_color = UI_AMBER if selected else (UI_TEAL if hovered else UI_BORDER_SUBTLE)
	style.set_border_width_all(3 if selected else 1)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 7
	style.content_margin_top = 8
	style.content_margin_right = 7
	style.content_margin_bottom = 8
	return style

func _community_survivor_card_style(selected: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_SURFACE_RAISED if hovered else UI_SURFACE
	style.border_color = UI_AMBER if selected else (UI_TEAL if hovered else UI_BORDER_SUBTLE)
	style.set_border_width_all(3 if selected else 1)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style
