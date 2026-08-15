class_name DayReportJournalPanel
extends Control

signal closed()

const PANEL_Z_INDEX := 82

var _built: bool = false
var _reports: Array = []
var _selected_day: int = 0
var _selected_button: Button
var _day_buttons: Array[Button] = []
var _button_group: ButtonGroup
var _return_focus: Control

var _count_label: Label
var _day_list: VBoxContainer
var _detail_title: Label
var _detail_meta: Label
var _entries_list: VBoxContainer
var _warnings_list: VBoxContainer
var _close_button: Button


func build() -> void:
	if _built:
		return
	_built = true
	name = "DayReportJournalOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = PANEL_Z_INDEX
	visible = false
	set_process(false)
	set_process_unhandled_input(false)

	var dimmer := ColorRect.new()
	dimmer.name = "DayReportJournalDimmer"
	dimmer.color = Color(0.008, 0.018, 0.024, 0.90)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 24.0
	center.offset_top = 24.0
	center.offset_right = -24.0
	center.offset_bottom = -24.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var window := PanelContainer.new()
	window.name = "DayReportJournalWindow"
	window.custom_minimum_size = Vector2(1040, 620)
	window.add_theme_stylebox_override("panel", _panel_style(Color("0b151afb"), Color("597277"), 2, 10))
	center.add_child(window)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 24)
	outer_margin.add_theme_constant_override("margin_top", 18)
	outer_margin.add_theme_constant_override("margin_right", 24)
	outer_margin.add_theme_constant_override("margin_bottom", 18)
	window.add_child(outer_margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 11)
	outer_margin.add_child(content)
	_build_header(content)
	content.add_child(HSeparator.new())
	_build_columns(content)


func present(history: Array) -> void:
	build()
	var focus_owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	_return_focus = focus_owner if focus_owner != null and not is_ancestor_of(focus_owner) else null
	refresh(history)
	visible = true
	set_process(true)
	set_process_unhandled_input(true)
	call_deferred("_focus_selected_control")


func dismiss(restore_focus: bool = true) -> void:
	if not _built:
		return
	set_process(false)
	set_process_unhandled_input(false)
	var focus_owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()
	visible = false
	if restore_focus and is_instance_valid(_return_focus) and not _return_focus.is_queued_for_deletion():
		_return_focus.call_deferred("grab_focus")
	_return_focus = null


func is_open() -> bool:
	return _built and visible


func refresh(history: Array) -> void:
	build()
	_refresh_history(history)


func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	parent.add_child(header)

	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 3)
	header.add_child(heading)

	var eyebrow := Label.new()
	eyebrow.text = "PRZYSTAŃ  •  ZAPIS KONSEKWENCJI"
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", Color("91b9b7"))
	heading.add_child(eyebrow)

	var title := Label.new()
	title.text = "ARCHIWUM RAPORTÓW"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("f1d498"))
	heading.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Siedem ostatnich zakończonych dni. Wpisy są zapisanymi migawkami i nie uruchamiają ponownie rozliczeń."
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color("aebdba"))
	heading.add_child(subtitle)

	_count_label = Label.new()
	_count_label.name = "DayReportJournalCount"
	_count_label.custom_minimum_size = Vector2(116, 38)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.add_theme_color_override("font_color", Color("8eb9b4"))
	_count_label.add_theme_stylebox_override("normal", _panel_style(Color("142326e6"), Color("45666a"), 1, 5))
	header.add_child(_count_label)

	_close_button = Button.new()
	_close_button.name = "DayReportJournalCloseButton"
	_close_button.text = "ZAMKNIJ  ✕"
	_close_button.custom_minimum_size = Vector2(142, 42)
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
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	parent.add_child(columns)

	var index_panel := PanelContainer.new()
	index_panel.custom_minimum_size = Vector2(245, 0)
	index_panel.add_theme_stylebox_override("panel", _panel_style(Color("101d21e8"), Color("354c51"), 1, 6))
	columns.add_child(index_panel)

	var index_margin := MarginContainer.new()
	index_margin.add_theme_constant_override("margin_left", 12)
	index_margin.add_theme_constant_override("margin_top", 12)
	index_margin.add_theme_constant_override("margin_right", 12)
	index_margin.add_theme_constant_override("margin_bottom", 12)
	index_panel.add_child(index_margin)

	var index_content := VBoxContainer.new()
	index_content.add_theme_constant_override("separation", 9)
	index_margin.add_child(index_content)
	index_content.add_child(_section_title("ZAKOŃCZONE DNI", Color("d8c28e")))

	var day_scroll := ScrollContainer.new()
	day_scroll.name = "DayReportJournalDaysScroll"
	day_scroll.focus_mode = Control.FOCUS_NONE
	day_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	day_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	index_content.add_child(day_scroll)

	_day_list = VBoxContainer.new()
	_day_list.name = "DayReportJournalDays"
	_day_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_day_list.add_theme_constant_override("separation", 7)
	day_scroll.add_child(_day_list)

	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _panel_style(Color("0e191de8"), Color("354c51"), 1, 6))
	columns.add_child(detail_panel)

	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 18)
	detail_margin.add_theme_constant_override("margin_top", 14)
	detail_margin.add_theme_constant_override("margin_right", 18)
	detail_margin.add_theme_constant_override("margin_bottom", 14)
	detail_panel.add_child(detail_margin)

	var detail_content := VBoxContainer.new()
	detail_content.add_theme_constant_override("separation", 9)
	detail_margin.add_child(detail_content)

	_detail_title = Label.new()
	_detail_title.name = "DayReportJournalTitle"
	_detail_title.add_theme_font_size_override("font_size", 23)
	_detail_title.add_theme_color_override("font_color", Color("eed096"))
	detail_content.add_child(_detail_title)

	_detail_meta = Label.new()
	_detail_meta.name = "DayReportJournalMeta"
	_detail_meta.add_theme_font_size_override("font_size", 12)
	_detail_meta.add_theme_color_override("font_color", Color("8fb4b1"))
	detail_content.add_child(_detail_meta)
	detail_content.add_child(HSeparator.new())

	var report_columns := HBoxContainer.new()
	report_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_columns.add_theme_constant_override("separation", 16)
	detail_content.add_child(report_columns)

	var entries_column := VBoxContainer.new()
	entries_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries_column.size_flags_stretch_ratio = 1.4
	entries_column.add_theme_constant_override("separation", 7)
	report_columns.add_child(entries_column)
	entries_column.add_child(_section_title("PRZEBIEG DNIA", Color("d8c28e")))
	var entries_scroll := ScrollContainer.new()
	entries_scroll.name = "DayReportJournalEntriesScroll"
	entries_scroll.focus_mode = Control.FOCUS_NONE
	entries_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entries_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	entries_column.add_child(entries_scroll)
	_entries_list = VBoxContainer.new()
	_entries_list.name = "DayReportJournalEntries"
	_entries_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_list.add_theme_constant_override("separation", 7)
	entries_scroll.add_child(_entries_list)

	report_columns.add_child(VSeparator.new())

	var warnings_column := VBoxContainer.new()
	warnings_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warnings_column.size_flags_stretch_ratio = 1.0
	warnings_column.add_theme_constant_override("separation", 7)
	report_columns.add_child(warnings_column)
	warnings_column.add_child(_section_title("WYMAGA UWAGI", Color("e39a83")))
	var warnings_scroll := ScrollContainer.new()
	warnings_scroll.name = "DayReportJournalWarningsScroll"
	warnings_scroll.focus_mode = Control.FOCUS_NONE
	warnings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	warnings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	warnings_column.add_child(warnings_scroll)
	_warnings_list = VBoxContainer.new()
	_warnings_list.name = "DayReportJournalWarnings"
	_warnings_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_warnings_list.add_theme_constant_override("separation", 7)
	warnings_scroll.add_child(_warnings_list)


func _refresh_history(history: Array) -> void:
	_reports.clear()
	for report in history:
		if report != null and "day" in report and int(report.day) > 0:
			_reports.append(report)
	_reports.sort_custom(func(a, b): return int(a.day) > int(b.day))
	_count_label.text = "%d / 7" % _reports.size()
	_rebuild_day_buttons()
	if _reports.is_empty():
		_selected_day = 0
		_selected_button = null
		_detail_title.text = "BRAK RAPORTÓW"
		_detail_meta.text = "Pierwszy wpis pojawi się po zakończeniu dnia."
		_populate_lines(_entries_list, [], false)
		_populate_lines(_warnings_list, [], true)
		_configure_focus_cycle()
		return

	var selected_report = null
	for report in _reports:
		if int(report.day) == _selected_day:
			selected_report = report
			break
	if selected_report == null:
		selected_report = _reports[0]
	_select_report(selected_report, _button_for_day(int(selected_report.day)))
	_configure_focus_cycle()


func _rebuild_day_buttons() -> void:
	for child in _day_list.get_children():
		_day_list.remove_child(child)
		child.queue_free()
	_day_buttons.clear()
	_button_group = ButtonGroup.new()
	_button_group.allow_unpress = false
	for report in _reports:
		var report_day := int(report.day)
		var button := Button.new()
		button.name = "DayReportJournalDay_%d" % report_day
		button.text = "DZIEŃ %d\n%s" % [report_day, "Z WYPRAWĄ" if bool(report.includes_dive) else "BEZ WYPRAWY"]
		button.custom_minimum_size = Vector2(0, 56)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = _button_group
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size", 12)
		button.add_theme_color_override("font_color", Color("cbd8d5"))
		button.add_theme_color_override("font_pressed_color", Color("fff0cf"))
		button.add_theme_stylebox_override("normal", _button_style(Color("142328"), Color("30484d"), 1))
		button.add_theme_stylebox_override("hover", _button_style(Color("20363c"), Color("6a9293"), 1))
		button.add_theme_stylebox_override("pressed", _button_style(Color("66471f"), Color("d5a75b"), 2))
		button.pressed.connect(_select_report.bind(report, button))
		_day_list.add_child(button)
		_day_buttons.append(button)


func _select_report(report, button: Button) -> void:
	if report == null:
		return
	_selected_day = int(report.day)
	_selected_button = button
	if _selected_button != null:
		_selected_button.button_pressed = true
	_detail_title.text = "DZIEŃ %d" % _selected_day
	var warning_count: int = report.warnings.size()
	_detail_meta.text = "%s  •  %d %s" % [
		"ZORGANIZOWANO WYPRAWĘ" if bool(report.includes_dive) else "BEZ WYPRAWY",
		warning_count,
		_warning_word(warning_count),
	]
	_populate_lines(_entries_list, report.entries, false)
	_populate_lines(_warnings_list, report.warnings, true)


func _populate_lines(container: VBoxContainer, lines: Array[String], warning: bool) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

	var visible_lines: Array[String] = []
	for line in lines:
		var text := str(line)
		if not warning and _is_technical_entry(text):
			continue
		visible_lines.append(text)
	if visible_lines.is_empty():
		var empty := Label.new()
		empty.text = "Brak ostrzeżeń w tym raporcie." if warning else "Brak dodatkowych zdarzeń."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color("75a696") if warning else Color("879492"))
		container.add_child(empty)
		return

	for line in visible_lines:
		var label := Label.new()
		label.text = "%s  %s" % ["!" if warning else "•", line]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color("e7a08d") if warning else Color("cbd5d3"))
		container.add_child(label)


func _configure_focus_cycle() -> void:
	var controls: Array[Control] = []
	for button in _day_buttons:
		controls.append(button)
	controls.append(_close_button)
	if controls.size() < 2:
		return
	for index in range(controls.size()):
		var control := controls[index]
		var previous := controls[(index - 1 + controls.size()) % controls.size()]
		var next := controls[(index + 1) % controls.size()]
		control.focus_previous = control.get_path_to(previous)
		control.focus_next = control.get_path_to(next)
		control.focus_neighbor_left = control.get_path_to(previous)
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_neighbor_right = control.get_path_to(next)
		control.focus_neighbor_bottom = control.get_path_to(next)


func _button_for_day(day: int) -> Button:
	for button in _day_buttons:
		if button.name == "DayReportJournalDay_%d" % day:
			return button
	return null


func _process(_delta: float) -> void:
	if not visible or not is_inside_tree():
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null or not is_ancestor_of(focus_owner):
		_focus_selected_control()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_request_close()


func _focus_selected_control() -> void:
	var target: Control = _selected_button if is_instance_valid(_selected_button) else _close_button
	if target != null and target.visible and not target.is_queued_for_deletion():
		target.grab_focus()


func _request_close() -> void:
	dismiss()
	closed.emit()


func _warning_word(count: int) -> String:
	if count == 1:
		return "OSTRZEŻENIE"
	var last_two := count % 100
	var last_digit := count % 10
	var teen_exception := last_two >= 12 and last_two <= 14
	return "OSTRZEŻENIA" if not teen_exception and last_digit >= 2 and last_digit <= 4 else "OSTRZEŻEŃ"


func _is_technical_entry(text: String) -> bool:
	return text in [
		"Przygotowano raport na kolejny poranek.",
		"Kampania zostala zapisana.",
		"Kampania została zapisana.",
	]


func _section_title(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	return label


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
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
