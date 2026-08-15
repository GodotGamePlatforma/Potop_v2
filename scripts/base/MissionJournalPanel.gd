class_name MissionJournalPanel
extends Control

signal closed()
signal track_requested(mission_id: String)

const PANEL_Z_INDEX := 84

var _built: bool = false
var _state
var _mission_system
var _selected_mission_id: String = ""
var _active_views: Array = []
var _history_views: Array = []
var _active_ids: Array[String] = []
var _mission_button_group: ButtonGroup
var _initial_focus_control: Control

var _active_count_label: Label
var _history_count_label: Label
var _active_list: VBoxContainer
var _history_list: VBoxContainer
var _detail_empty_label: Label
var _detail_content: VBoxContainer
var _detail_category_label: Label
var _detail_status_label: Label
var _detail_title_label: Label
var _detail_summary_label: Label
var _detail_progress_label: Label
var _detail_target_label: Label
var _objective_list: VBoxContainer
var _track_button: Button
var _close_button: Button


func build() -> void:
	if _built:
		return
	_built = true
	name = "MissionJournalOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = PANEL_Z_INDEX
	visible = false
	set_process(false)
	set_process_unhandled_input(false)

	var dimmer := ColorRect.new()
	dimmer.name = "MissionJournalDimmer"
	dimmer.color = Color(0.008, 0.018, 0.024, 0.91)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	var center := CenterContainer.new()
	center.name = "MissionJournalCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 22.0
	center.offset_top = 18.0
	center.offset_right = -22.0
	center.offset_bottom = -18.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var window := PanelContainer.new()
	window.name = "MissionJournalWindow"
	window.custom_minimum_size = Vector2(1180, 650)
	window.add_theme_stylebox_override("panel", _panel_style(Color("0b151afb"), Color("597277"), 2, 10))
	center.add_child(window)

	var outer_margin := MarginContainer.new()
	outer_margin.name = "MissionJournalMargin"
	outer_margin.add_theme_constant_override("margin_left", 24)
	outer_margin.add_theme_constant_override("margin_top", 18)
	outer_margin.add_theme_constant_override("margin_right", 24)
	outer_margin.add_theme_constant_override("margin_bottom", 16)
	window.add_child(outer_margin)

	var content := VBoxContainer.new()
	content.name = "MissionJournalContent"
	content.add_theme_constant_override("separation", 11)
	outer_margin.add_child(content)

	_build_header(content)
	content.add_child(HSeparator.new())
	_build_columns(content)
	_build_footer(content)


func present(state, mission_system) -> void:
	build()
	refresh(state, mission_system)
	visible = true
	set_process(true)
	set_process_unhandled_input(true)
	call_deferred("_focus_initial_control")


func refresh(state, mission_system) -> void:
	build()
	_state = state
	_mission_system = mission_system
	_active_views.clear()
	_history_views.clear()
	_active_ids.clear()

	if _mission_system != null:
		_active_views = _dictionary_views(_mission_system.active_views(_state))
		_history_views = _dictionary_views(_mission_system.completed_views(_state))

	for view in _active_views:
		var mission_id := str(view.get("id", ""))
		if not mission_id.is_empty() and not _active_ids.has(mission_id):
			_active_ids.append(mission_id)

	if not _contains_mission(_selected_mission_id):
		_selected_mission_id = _first_mission_id(_active_views)
		if _selected_mission_id.is_empty():
			_selected_mission_id = _first_mission_id(_history_views)

	_mission_button_group = ButtonGroup.new()
	_initial_focus_control = null
	_populate_mission_list(_active_list, _active_views, true)
	_populate_mission_list(_history_list, _history_views, false)
	_active_count_label.text = "AKTYWNE  •  %d" % _active_views.size()
	_history_count_label.text = "HISTORIA  •  %d" % _history_views.size()
	_refresh_details()
	if _initial_focus_control == null:
		_initial_focus_control = _close_button


func dismiss() -> void:
	if not _built:
		return
	set_process(false)
	set_process_unhandled_input(false)
	var focus_owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()
	visible = false


func is_open() -> bool:
	return _built and visible


func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.name = "MissionJournalHeader"
	header.add_theme_constant_override("separation", 18)
	parent.add_child(header)

	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 2)
	header.add_child(heading)

	var eyebrow := Label.new()
	eyebrow.text = "KRONIKA PRZYSTANI  •  CELE KAMPANII"
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", Color("88b5b3"))
	heading.add_child(eyebrow)

	var title := Label.new()
	title.name = "MissionJournalTitle"
	title.text = "DZIENNIK ZADAŃ"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("f1d28f"))
	heading.add_child(title)

	_close_button = Button.new()
	_close_button.name = "MissionJournalCloseButton"
	_close_button.text = "ZAMKNIJ  ✕"
	_close_button.custom_minimum_size = Vector2(148, 42)
	_close_button.focus_mode = Control.FOCUS_ALL
	_close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_button.add_theme_font_size_override("font_size", 13)
	_close_button.add_theme_color_override("font_color", Color("e3ece9"))
	_close_button.add_theme_stylebox_override("normal", _button_style(Color("17262b"), Color("486268"), 1))
	_close_button.add_theme_stylebox_override("hover", _button_style(Color("263a40"), Color("7ba3a6"), 2))
	_close_button.add_theme_stylebox_override("pressed", _button_style(Color("101b1f"), Color("58777b"), 2))
	_close_button.pressed.connect(_request_close)
	header.add_child(_close_button)


func _build_columns(parent: VBoxContainer) -> void:
	var columns := HBoxContainer.new()
	columns.name = "MissionJournalColumns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	parent.add_child(columns)

	var index_panel := PanelContainer.new()
	index_panel.name = "MissionJournalIndexPanel"
	index_panel.custom_minimum_size = Vector2(382, 0)
	index_panel.add_theme_stylebox_override("panel", _panel_style(Color("101e23e8"), Color("314b51"), 1, 6))
	columns.add_child(index_panel)

	var index_margin := MarginContainer.new()
	index_margin.add_theme_constant_override("margin_left", 13)
	index_margin.add_theme_constant_override("margin_top", 12)
	index_margin.add_theme_constant_override("margin_right", 13)
	index_margin.add_theme_constant_override("margin_bottom", 12)
	index_panel.add_child(index_margin)

	var index_content := VBoxContainer.new()
	index_content.add_theme_constant_override("separation", 8)
	index_margin.add_child(index_content)

	_active_count_label = _section_label("AKTYWNE", Color("e6c77f"), "MissionJournalActiveCount")
	index_content.add_child(_active_count_label)
	var active_scroll := ScrollContainer.new()
	active_scroll.name = "MissionJournalActiveScroll"
	active_scroll.custom_minimum_size = Vector2(0, 205)
	active_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	active_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	active_scroll.focus_mode = Control.FOCUS_NONE
	index_content.add_child(active_scroll)
	_active_list = VBoxContainer.new()
	_active_list.name = "MissionJournalActiveList"
	_active_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_list.add_theme_constant_override("separation", 7)
	active_scroll.add_child(_active_list)

	index_content.add_child(HSeparator.new())
	_history_count_label = _section_label("HISTORIA", Color("92aaa8"), "MissionJournalHistoryCount")
	index_content.add_child(_history_count_label)
	var history_scroll := ScrollContainer.new()
	history_scroll.name = "MissionJournalHistoryScroll"
	history_scroll.custom_minimum_size = Vector2(0, 150)
	history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	history_scroll.focus_mode = Control.FOCUS_NONE
	index_content.add_child(history_scroll)
	_history_list = VBoxContainer.new()
	_history_list.name = "MissionJournalHistoryList"
	_history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_list.add_theme_constant_override("separation", 7)
	history_scroll.add_child(_history_list)

	var divider := VSeparator.new()
	divider.name = "MissionJournalDivider"
	columns.add_child(divider)

	_build_detail_column(columns)


func _build_detail_column(parent: HBoxContainer) -> void:
	var detail_panel := PanelContainer.new()
	detail_panel.name = "MissionJournalDetailPanel"
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _panel_style(Color("0f1b20e8"), Color("344f55"), 1, 6))
	parent.add_child(detail_panel)

	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 22)
	detail_margin.add_theme_constant_override("margin_top", 18)
	detail_margin.add_theme_constant_override("margin_right", 22)
	detail_margin.add_theme_constant_override("margin_bottom", 16)
	detail_panel.add_child(detail_margin)

	var detail_root := VBoxContainer.new()
	detail_root.name = "MissionJournalDetailRoot"
	detail_root.add_theme_constant_override("separation", 10)
	detail_margin.add_child(detail_root)

	_detail_empty_label = Label.new()
	_detail_empty_label.name = "MissionJournalEmptyDetails"
	_detail_empty_label.text = "Brak zadań do wyświetlenia."
	_detail_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_empty_label.add_theme_font_size_override("font_size", 16)
	_detail_empty_label.add_theme_color_override("font_color", Color("78908e"))
	detail_root.add_child(_detail_empty_label)

	_detail_content = VBoxContainer.new()
	_detail_content.name = "MissionJournalDetails"
	_detail_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_content.add_theme_constant_override("separation", 10)
	detail_root.add_child(_detail_content)

	var detail_meta := HBoxContainer.new()
	detail_meta.add_theme_constant_override("separation", 10)
	_detail_content.add_child(detail_meta)
	_detail_category_label = _badge_label("MissionJournalDetailCategory")
	_detail_category_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_meta.add_child(_detail_category_label)
	_detail_status_label = _badge_label("MissionJournalDetailStatus")
	_detail_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	detail_meta.add_child(_detail_status_label)

	_detail_title_label = Label.new()
	_detail_title_label.name = "MissionJournalDetailTitle"
	_detail_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_title_label.add_theme_font_size_override("font_size", 25)
	_detail_title_label.add_theme_color_override("font_color", Color("f0d49a"))
	_detail_content.add_child(_detail_title_label)

	_detail_summary_label = Label.new()
	_detail_summary_label.name = "MissionJournalDetailSummary"
	_detail_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_summary_label.add_theme_font_size_override("font_size", 14)
	_detail_summary_label.add_theme_color_override("font_color", Color("c3d0ce"))
	_detail_content.add_child(_detail_summary_label)

	var progress_panel := PanelContainer.new()
	progress_panel.name = "MissionJournalProgressPanel"
	progress_panel.add_theme_stylebox_override("panel", _panel_style(Color("14262bd9"), Color("35575c"), 1, 5))
	_detail_content.add_child(progress_panel)
	var progress_margin := MarginContainer.new()
	progress_margin.add_theme_constant_override("margin_left", 13)
	progress_margin.add_theme_constant_override("margin_top", 8)
	progress_margin.add_theme_constant_override("margin_right", 13)
	progress_margin.add_theme_constant_override("margin_bottom", 8)
	progress_panel.add_child(progress_margin)
	var progress_stack := VBoxContainer.new()
	progress_stack.add_theme_constant_override("separation", 4)
	progress_margin.add_child(progress_stack)
	_detail_progress_label = Label.new()
	_detail_progress_label.name = "MissionJournalDetailProgress"
	_detail_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_progress_label.add_theme_font_size_override("font_size", 13)
	_detail_progress_label.add_theme_color_override("font_color", Color("d7bf82"))
	progress_stack.add_child(_detail_progress_label)
	_detail_target_label = Label.new()
	_detail_target_label.name = "MissionJournalDetailTarget"
	_detail_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_target_label.add_theme_font_size_override("font_size", 13)
	_detail_target_label.add_theme_color_override("font_color", Color("8fc1bd"))
	progress_stack.add_child(_detail_target_label)

	var objectives_header := Label.new()
	objectives_header.text = "CELE"
	objectives_header.add_theme_font_size_override("font_size", 12)
	objectives_header.add_theme_color_override("font_color", Color("91adab"))
	_detail_content.add_child(objectives_header)

	var objective_scroll := ScrollContainer.new()
	objective_scroll.name = "MissionJournalObjectiveScroll"
	objective_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	objective_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	objective_scroll.focus_mode = Control.FOCUS_NONE
	_detail_content.add_child(objective_scroll)
	_objective_list = VBoxContainer.new()
	_objective_list.name = "MissionJournalObjectiveList"
	_objective_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_objective_list.add_theme_constant_override("separation", 7)
	objective_scroll.add_child(_objective_list)

	var detail_actions := HBoxContainer.new()
	detail_actions.name = "MissionJournalDetailActions"
	detail_actions.alignment = BoxContainer.ALIGNMENT_END
	_detail_content.add_child(detail_actions)
	_track_button = Button.new()
	_track_button.name = "MissionJournalTrackButton"
	_track_button.text = "ŚLEDŹ"
	_track_button.custom_minimum_size = Vector2(190, 44)
	_track_button.focus_mode = Control.FOCUS_ALL
	_track_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_track_button.add_theme_font_size_override("font_size", 14)
	_track_button.add_theme_color_override("font_color", Color("fff0cb"))
	_track_button.add_theme_stylebox_override("normal", _button_style(Color("80531f"), Color("d7a955"), 2))
	_track_button.add_theme_stylebox_override("hover", _button_style(Color("a66b27"), Color("f0ca72"), 2))
	_track_button.add_theme_stylebox_override("pressed", _button_style(Color("5e3c19"), Color("bb8c42"), 2))
	_track_button.add_theme_stylebox_override("disabled", _button_style(Color("26302f"), Color("4b6460"), 1))
	_track_button.pressed.connect(_on_track_pressed)
	detail_actions.add_child(_track_button)


func _build_footer(parent: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.name = "MissionJournalFooter"
	parent.add_child(footer)
	var hint := Label.new()
	hint.text = "Wybierz wpis, aby zobaczyć szczegóły.  •  ESC zamyka dziennik."
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color("718785"))
	footer.add_child(hint)


func _populate_mission_list(container: VBoxContainer, views: Array, active: bool) -> void:
	_clear_container(container)
	if views.is_empty():
		var empty := Label.new()
		empty.name = "MissionJournalActiveEmpty" if active else "MissionJournalHistoryEmpty"
		empty.text = "Brak aktywnych zadań." if active else "Historia jest jeszcze pusta."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color("6f8583"))
		container.add_child(empty)
		return

	for view in views:
		var mission_id := str(view.get("id", ""))
		if mission_id.is_empty():
			continue
		var entry := Button.new()
		entry.name = "%s_%s" % ["MissionJournalActiveEntry" if active else "MissionJournalHistoryEntry", _safe_node_suffix(mission_id)]
		entry.custom_minimum_size = Vector2(0, 66)
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.focus_mode = Control.FOCUS_ALL
		entry.toggle_mode = true
		entry.button_group = _mission_button_group
		entry.button_pressed = mission_id == _selected_mission_id
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		entry.text = "%s  •  %s\n%s" % [
			_category_display(str(view.get("category", ""))),
			_status_display(str(view.get("status", "active" if active else "completed"))),
			str(view.get("title", mission_id)),
		]
		entry.tooltip_text = str(view.get("summary", ""))
		entry.add_theme_font_size_override("font_size", 12)
		entry.add_theme_color_override("font_color", _entry_text_color(view, active))
		entry.add_theme_stylebox_override("normal", _button_style(Color("132329"), Color("2f484e"), 1))
		entry.add_theme_stylebox_override("hover", _button_style(Color("1d343a"), Color("64878a"), 1))
		entry.add_theme_stylebox_override("pressed", _button_style(Color("203a3f"), Color("d2ad61"), 2))
		entry.add_theme_stylebox_override("focus", _button_style(Color("1b3036"), Color("e0c071"), 2))
		entry.pressed.connect(_on_mission_selected.bind(mission_id))
		container.add_child(entry)
		if _initial_focus_control == null:
			_initial_focus_control = entry


func _refresh_details() -> void:
	if _selected_mission_id.is_empty() or _mission_system == null:
		_show_empty_details()
		return

	var raw_view = _mission_system.mission_view(_state, _selected_mission_id)
	if not raw_view is Dictionary or raw_view.is_empty():
		_show_empty_details()
		return
	var view: Dictionary = raw_view
	_detail_empty_label.visible = false
	_detail_content.visible = true
	_detail_category_label.text = _category_display(str(view.get("category", "")))
	var status := str(view.get("status", "active" if _active_ids.has(_selected_mission_id) else "completed"))
	_detail_status_label.text = _status_display(status)
	_apply_status_badge(_detail_status_label, status)
	_detail_title_label.text = str(view.get("title", _selected_mission_id))
	_detail_summary_label.text = str(view.get("summary", ""))
	_detail_summary_label.visible = not _detail_summary_label.text.strip_edges().is_empty()

	var progress = view.get("progress", "")
	var target = view.get("target", "")
	_detail_progress_label.text = _progress_display(progress, target)
	_detail_progress_label.visible = not _detail_progress_label.text.is_empty()
	_detail_target_label.text = _objective_guidance_display(view.get("objectives", []))
	if _detail_target_label.text.is_empty():
		_detail_target_label.text = _target_display(target)
	_detail_target_label.visible = not _detail_target_label.text.is_empty()
	_populate_objectives(view.get("objectives", []), _selected_mission_id)

	var is_active_mission := _active_ids.has(_selected_mission_id)
	var tracked := bool(view.get("tracked", false))
	var urgent_tracking_id := _active_urgent_mission_id()
	var blocked_by_urgent := not urgent_tracking_id.is_empty() and urgent_tracking_id != _selected_mission_id
	_track_button.visible = is_active_mission
	_track_button.name = "TrackMission_%s" % _safe_node_suffix(_selected_mission_id)
	_track_button.text = "ŚLEDZONE" if tracked else "KRYZYS MA PIERWSZEŃSTWO" if blocked_by_urgent else "ŚLEDŹ"
	_track_button.disabled = tracked or blocked_by_urgent
	if tracked:
		_track_button.tooltip_text = "To zadanie jest śledzone w HUD-zie."
	elif blocked_by_urgent:
		_track_button.tooltip_text = "Po zakończeniu pilnego kryzysu dziennik przywróci poprzednio śledzone zadanie."
	else:
		_track_button.tooltip_text = "Pokaż to zadanie jako bieżący cel."


func _show_empty_details() -> void:
	_detail_empty_label.visible = true
	_detail_content.visible = false
	_clear_container(_objective_list)
	_track_button.visible = false


func _populate_objectives(raw_objectives, mission_id: String) -> void:
	_clear_container(_objective_list)
	if not raw_objectives is Array or raw_objectives.is_empty():
		var empty := Label.new()
		empty.name = "MissionJournalObjectivesEmpty"
		empty.text = "Brak dodatkowych celów."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color("718482"))
		_objective_list.add_child(empty)
		return

	var index := 0
	for raw_objective in raw_objectives:
		if not raw_objective is Dictionary:
			continue
		var objective: Dictionary = raw_objective
		var complete := bool(objective.get("complete", false))
		var failed := bool(objective.get("failed", false))
		var accent := Color("d87e70") if failed else Color("72bc98") if complete else Color("779a9a")
		var marker := "✕" if failed else "✓" if complete else "○"

		var card := PanelContainer.new()
		card.name = "MissionObjective_%s_%d" % [_safe_node_suffix(mission_id), index]
		card.add_theme_stylebox_override("panel", _panel_style(Color("122127d9"), accent.darkened(0.35), 1, 4))
		_objective_list.add_child(card)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 11)
		margin.add_theme_constant_override("margin_top", 7)
		margin.add_theme_constant_override("margin_right", 11)
		margin.add_theme_constant_override("margin_bottom", 7)
		card.add_child(margin)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		margin.add_child(row)
		var marker_label := Label.new()
		marker_label.text = marker
		marker_label.custom_minimum_size = Vector2(22, 0)
		marker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker_label.add_theme_font_size_override("font_size", 17)
		marker_label.add_theme_color_override("font_color", accent)
		row.add_child(marker_label)
		var text_stack := VBoxContainer.new()
		text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_stack.add_theme_constant_override("separation", 2)
		row.add_child(text_stack)
		var objective_text := Label.new()
		objective_text.text = str(objective.get("text", "Cel zadania"))
		objective_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		objective_text.add_theme_font_size_override("font_size", 13)
		objective_text.add_theme_color_override("font_color", Color("84908e") if complete else Color("ddb0a6") if failed else Color("d2dcda"))
		text_stack.add_child(objective_text)
		var status_text := str(objective.get("status_text", "")).strip_edges()
		if not status_text.is_empty():
			var status_label := Label.new()
			status_label.text = status_text
			status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			status_label.add_theme_font_size_override("font_size", 11)
			status_label.add_theme_color_override("font_color", accent)
			text_stack.add_child(status_label)
		index += 1


func _on_mission_selected(mission_id: String) -> void:
	_selected_mission_id = mission_id
	_refresh_details()


func _on_track_pressed() -> void:
	if _selected_mission_id.is_empty() or not _active_ids.has(_selected_mission_id):
		return
	track_requested.emit(_selected_mission_id)


func _request_close() -> void:
	dismiss()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not event.is_action_pressed("ui_cancel"):
		return
	_request_close()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_open() or not is_inside_tree():
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null or not is_ancestor_of(focus_owner):
		_focus_initial_control()


func _focus_initial_control() -> void:
	if not is_open():
		return
	var target := _initial_focus_control if is_instance_valid(_initial_focus_control) else _close_button
	if target != null and target.visible and not target.is_queued_for_deletion():
		target.grab_focus()


func _dictionary_views(raw_views) -> Array:
	var result: Array = []
	if not raw_views is Array:
		return result
	for raw_view in raw_views:
		if raw_view is Dictionary:
			result.append(raw_view)
	return result


func _contains_mission(mission_id: String) -> bool:
	if mission_id.is_empty():
		return false
	for view in _active_views:
		if str(view.get("id", "")) == mission_id:
			return true
	for view in _history_views:
		if str(view.get("id", "")) == mission_id:
			return true
	return false


func _first_mission_id(views: Array) -> String:
	for view in views:
		var mission_id := str(view.get("id", ""))
		if not mission_id.is_empty():
			return mission_id
	return ""


func _progress_display(progress, target) -> String:
	if progress is Dictionary:
		var current = progress.get("current", progress.get("value", ""))
		var required = progress.get("target", progress.get("required", target))
		var label := str(progress.get("label", "")).strip_edges()
		var value_text := _ratio_text(current, required)
		if not label.is_empty() and not value_text.is_empty():
			return "POSTĘP  •  %s  •  %s" % [label, value_text]
		if not label.is_empty():
			return "POSTĘP  •  %s" % label
		return "POSTĘP  •  %s" % value_text if not value_text.is_empty() else ""
	if _is_number(progress) and _is_number(target):
		return "POSTĘP  •  %s" % _ratio_text(progress, target)
	var text := str(progress).strip_edges()
	return "POSTĘP  •  %s" % text if not text.is_empty() else ""


func _target_display(target) -> String:
	if _is_number(target) or target == null:
		return ""
	var text := str(target).strip_edges()
	return "CEL / MIEJSCE  •  %s" % text if not text.is_empty() else ""


func _objective_guidance_display(raw_objectives) -> String:
	if not raw_objectives is Array:
		return ""
	for raw_objective in raw_objectives:
		if not raw_objective is Dictionary:
			continue
		var objective: Dictionary = raw_objective
		if bool(objective.get("complete", false)) or bool(objective.get("failed", false)):
			continue
		var landmark_id := str(objective.get("landmark_id", objective.get("target_landmark_id", ""))).strip_edges()
		var landmark_label := str(objective.get("landmark_label", "")).strip_edges()
		var guidance := str(objective.get("guidance", "")).strip_edges()
		var destination := landmark_label
		if not landmark_id.is_empty():
			destination = "%s (%s)" % [landmark_label, landmark_id] if not landmark_label.is_empty() else landmark_id
		var lines: Array[String] = []
		if not destination.is_empty():
			lines.append("CEL / MIEJSCE  •  %s" % destination)
		if not guidance.is_empty():
			lines.append(guidance)
		if not lines.is_empty():
			return "\n".join(lines)
	return ""


func _active_urgent_mission_id() -> String:
	for view in _active_views:
		if bool(view.get("urgent", false)):
			return str(view.get("id", ""))
	return ""


func _ratio_text(current, required) -> String:
	var current_text := _compact_number(current)
	var required_text := _compact_number(required)
	if current_text.is_empty():
		return ""
	return "%s / %s" % [current_text, required_text] if not required_text.is_empty() else current_text


func _compact_number(value) -> String:
	if typeof(value) == TYPE_INT:
		return str(int(value))
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		return str(int(round(number))) if is_equal_approx(number, round(number)) else "%.1f" % number
	return str(value).strip_edges()


func _is_number(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _category_display(category: String) -> String:
	match category.strip_edges().to_lower():
		"main", "primary", "glowna", "główna":
			return "GŁÓWNA"
		"development", "growth", "rozwojowa":
			return "ROZWOJOWA"
		"optional", "side", "opcjonalna":
			return "OPCJONALNA"
		"crisis", "emergency", "urgent", "kryzys":
			return "KRYZYS"
	var normalized := category.strip_edges()
	return normalized.to_upper() if not normalized.is_empty() else "ZADANIE"


func _status_display(status: String) -> String:
	match status.strip_edges().to_lower():
		"active", "in_progress", "started":
			return "AKTYWNE"
		"completed", "complete", "success":
			return "UKOŃCZONE"
		"failed", "failure":
			return "NIEUDANE"
		"locked":
			return "ZABLOKOWANE"
	var normalized := status.strip_edges()
	return normalized.to_upper() if not normalized.is_empty() else "AKTYWNE"


func _apply_status_badge(label: Label, status: String) -> void:
	var normalized := status.strip_edges().to_lower()
	var color := Color("d5b467")
	if normalized in ["completed", "complete", "success"]:
		color = Color("76bd99")
	elif normalized in ["failed", "failure"]:
		color = Color("dd7f70")
	elif normalized == "locked":
		color = Color("7b8988")
	label.add_theme_color_override("font_color", color)


func _entry_text_color(view: Dictionary, active: bool) -> Color:
	var status := str(view.get("status", "active" if active else "completed")).to_lower()
	if status in ["failed", "failure"]:
		return Color("e09a8d")
	if status in ["completed", "complete", "success"]:
		return Color("8fb7a5")
	return Color("d7e1df")


func _section_label(text: String, color: Color, node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	return label


func _badge_label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color("8fb8b6"))
	return label


func _clear_container(container: Container) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _safe_node_suffix(value: String) -> String:
	var result := value.strip_edges()
	for character in ["/", "\\", ":", ".", "@", "\"", "%", " "]:
		result = result.replace(character, "_")
	return result if not result.is_empty() else "unknown"


func _panel_style(fill: Color, border: Color, width: int = 1, radius: int = 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _button_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := _panel_style(fill, border, width, 5)
	style.content_margin_left = 13
	style.content_margin_right = 13
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
