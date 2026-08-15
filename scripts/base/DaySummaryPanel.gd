class_name DaySummaryPanel
extends Control

signal acknowledged()

var _built: bool = false
var _title_label: Label
var _subtitle_label: Label
var _warning_count_label: Label
var _window: PanelContainer
var _stats_row: HBoxContainer
var _status_card: PanelContainer
var _loot_card: PanelContainer
var _duration_card: PanelContainer
var _status_value: Label
var _loot_value: Label
var _duration_value: Label
var _highlights_panel: PanelContainer
var _highlights_scroll: ScrollContainer
var _highlights_list: VBoxContainer
var _report_columns: HBoxContainer
var _details_divider: VSeparator
var _warnings_column: VBoxContainer
var _entries_list: VBoxContainer
var _warnings_list: VBoxContainer
var _morning_title: Label
var _morning_label: Label
var _continue_button: Button

const MAX_HIGHLIGHTS: int = 4


func build() -> void:
	if _built:
		return
	_built = true
	name = "DaySummaryOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 90
	visible = false
	set_process(false)

	var shade := ColorRect.new()
	shade.name = "DaySummaryDimmer"
	shade.color = Color(0.015, 0.028, 0.034, 0.86)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 24.0
	center.offset_top = 20.0
	center.offset_right = -24.0
	center.offset_bottom = -20.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_window = PanelContainer.new()
	_window.name = "DaySummaryWindow"
	_window.custom_minimum_size = Vector2(860, 0)
	_window.add_theme_stylebox_override("panel", _panel_style(Color("0d191dfc"), Color("a77a40"), 2, 9))
	center.add_child(_window)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 20)
	outer_margin.add_theme_constant_override("margin_top", 10)
	outer_margin.add_theme_constant_override("margin_right", 20)
	outer_margin.add_theme_constant_override("margin_bottom", 10)
	_window.add_child(outer_margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	outer_margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	content.add_child(header)

	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 3)
	header.add_child(heading)

	var eyebrow := Label.new()
	eyebrow.text = "RAPORT PRZYSTANI  •  PODSUMOWANIE"
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", Color("91b9b7"))
	heading.add_child(eyebrow)

	_title_label = Label.new()
	_title_label.name = "DaySummaryTitle"
	_title_label.add_theme_font_size_override("font_size", 26)
	_title_label.add_theme_color_override("font_color", Color("f1d498"))
	heading.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.name = "DaySummarySubtitle"
	_subtitle_label.add_theme_font_size_override("font_size", 13)
	_subtitle_label.add_theme_color_override("font_color", Color("b9c6c4"))
	heading.add_child(_subtitle_label)

	_warning_count_label = Label.new()
	_warning_count_label.name = "DaySummaryWarningCount"
	_warning_count_label.custom_minimum_size = Vector2(138, 34)
	_warning_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_warning_count_label.add_theme_font_size_override("font_size", 13)
	header.add_child(_warning_count_label)

	content.add_child(HSeparator.new())

	_stats_row = HBoxContainer.new()
	_stats_row.custom_minimum_size = Vector2(0, 50)
	_stats_row.add_theme_constant_override("separation", 8)
	content.add_child(_stats_row)
	_status_value = _add_stat_card(_stats_row, "WYPRAWA", "DaySummaryStatusValue")
	_status_card = _stat_card_for(_status_value)
	_loot_value = _add_stat_card(_stats_row, "ŁUP", "DaySummaryLootValue")
	_loot_card = _stat_card_for(_loot_value)
	_duration_value = _add_stat_card(_stats_row, "CZAS POD WODĄ", "DaySummaryDurationValue")
	_duration_card = _stat_card_for(_duration_value)

	_highlights_panel = PanelContainer.new()
	_highlights_panel.name = "DaySummaryHighlightsPanel"
	_highlights_panel.add_theme_stylebox_override("panel", _panel_style(Color("102429e8"), Color("4f7775"), 1, 6))
	content.add_child(_highlights_panel)
	var highlights_margin := MarginContainer.new()
	highlights_margin.add_theme_constant_override("margin_left", 11)
	highlights_margin.add_theme_constant_override("margin_top", 7)
	highlights_margin.add_theme_constant_override("margin_right", 11)
	highlights_margin.add_theme_constant_override("margin_bottom", 7)
	_highlights_panel.add_child(highlights_margin)
	var highlights_content := VBoxContainer.new()
	highlights_content.add_theme_constant_override("separation", 5)
	highlights_margin.add_child(highlights_content)
	var highlights_header := HBoxContainer.new()
	highlights_header.add_theme_constant_override("separation", 12)
	highlights_content.add_child(highlights_header)
	var highlights_title := _section_title("NAJWAŻNIEJSZE", Color("e0c486"))
	highlights_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	highlights_header.add_child(highlights_title)
	var highlights_hint := Label.new()
	highlights_hint.text = "kluczowe zmiany i ryzyka"
	highlights_hint.add_theme_font_size_override("font_size", 13)
	highlights_hint.add_theme_color_override("font_color", Color("7fa29f"))
	highlights_header.add_child(highlights_hint)
	_highlights_scroll = ScrollContainer.new()
	_highlights_scroll.name = "DaySummaryHighlightsScroll"
	_highlights_scroll.custom_minimum_size = Vector2(0, 48)
	_highlights_scroll.focus_mode = Control.FOCUS_NONE
	_highlights_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	highlights_content.add_child(_highlights_scroll)
	_highlights_list = VBoxContainer.new()
	_highlights_list.name = "DaySummaryHighlights"
	_highlights_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_highlights_list.add_theme_constant_override("separation", 4)
	_highlights_scroll.add_child(_highlights_list)

	_report_columns = HBoxContainer.new()
	_report_columns.custom_minimum_size = Vector2(0, 88)
	_report_columns.add_theme_constant_override("separation", 14)
	content.add_child(_report_columns)

	var entries_column := VBoxContainer.new()
	entries_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries_column.size_flags_stretch_ratio = 1.45
	entries_column.add_theme_constant_override("separation", 5)
	_report_columns.add_child(entries_column)
	entries_column.add_child(_section_title("SZCZEGÓŁOWY PRZEBIEG", Color("d8c28e")))
	var entries_scroll := ScrollContainer.new()
	entries_scroll.name = "DaySummaryEntriesScroll"
	entries_scroll.focus_mode = Control.FOCUS_NONE
	entries_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entries_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	entries_column.add_child(entries_scroll)
	_entries_list = VBoxContainer.new()
	_entries_list.name = "DaySummaryEntries"
	_entries_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_list.add_theme_constant_override("separation", 5)
	entries_scroll.add_child(_entries_list)

	_details_divider = VSeparator.new()
	_report_columns.add_child(_details_divider)

	_warnings_column = VBoxContainer.new()
	_warnings_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_warnings_column.size_flags_stretch_ratio = 1.0
	_warnings_column.add_theme_constant_override("separation", 5)
	_report_columns.add_child(_warnings_column)
	_warnings_column.add_child(_section_title("OSTRZEŻENIA  •  PEŁNA LISTA", Color("e39a83")))
	var warnings_scroll := ScrollContainer.new()
	warnings_scroll.name = "DaySummaryWarningsScroll"
	warnings_scroll.focus_mode = Control.FOCUS_NONE
	warnings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	warnings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_warnings_column.add_child(warnings_scroll)
	_warnings_list = VBoxContainer.new()
	_warnings_list.name = "DaySummaryWarnings"
	_warnings_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_warnings_list.add_theme_constant_override("separation", 5)
	warnings_scroll.add_child(_warnings_list)

	var morning_panel := PanelContainer.new()
	morning_panel.name = "DaySummaryMorningPanel"
	morning_panel.add_theme_stylebox_override("panel", _panel_style(Color("14262ad9"), Color("365c60"), 1, 6))
	content.add_child(morning_panel)
	var morning_margin := MarginContainer.new()
	morning_margin.add_theme_constant_override("margin_left", 11)
	morning_margin.add_theme_constant_override("margin_top", 6)
	morning_margin.add_theme_constant_override("margin_right", 11)
	morning_margin.add_theme_constant_override("margin_bottom", 6)
	morning_panel.add_child(morning_margin)
	var morning_content := VBoxContainer.new()
	morning_content.add_theme_constant_override("separation", 3)
	morning_margin.add_child(morning_content)
	_morning_title = Label.new()
	_morning_title.name = "DaySummaryMorningTitle"
	_morning_title.add_theme_font_size_override("font_size", 13)
	_morning_title.add_theme_color_override("font_color", Color("87b9b5"))
	morning_content.add_child(_morning_title)
	_morning_label = Label.new()
	_morning_label.name = "DaySummaryMorningBrief"
	_morning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_morning_label.max_lines_visible = 2
	_morning_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_morning_label.add_theme_font_size_override("font_size", 13)
	_morning_label.add_theme_color_override("font_color", Color("d0dcda"))
	morning_content.add_child(_morning_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(actions)
	_continue_button = Button.new()
	_continue_button.name = "DaySummaryContinueButton"
	_continue_button.custom_minimum_size = Vector2(260, 42)
	_continue_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_continue_button.focus_mode = Control.FOCUS_ALL
	_continue_button.focus_neighbor_left = NodePath(".")
	_continue_button.focus_neighbor_top = NodePath(".")
	_continue_button.focus_neighbor_right = NodePath(".")
	_continue_button.focus_neighbor_bottom = NodePath(".")
	_continue_button.focus_next = NodePath(".")
	_continue_button.focus_previous = NodePath(".")
	_continue_button.add_theme_font_size_override("font_size", 15)
	_continue_button.add_theme_color_override("font_color", Color("fff0cf"))
	_continue_button.add_theme_stylebox_override("normal", _button_style(Color("875522"), Color("dba957"), 2))
	_continue_button.add_theme_stylebox_override("hover", _button_style(Color("a66b29"), Color("f1c66f"), 2))
	_continue_button.add_theme_stylebox_override("pressed", _button_style(Color("67401c"), Color("c9974d"), 2))
	_continue_button.pressed.connect(func(): acknowledged.emit())
	actions.add_child(_continue_button)


func present(report, morning_report, dive_result, next_day: int) -> void:
	build()
	if report == null:
		dismiss()
		return

	var completed_day := int(report.day) if int(report.day) > 0 else maxi(next_day - 1, 1)
	_title_label.text = "DZIEŃ %d ZAKOŃCZONY" % completed_day
	_subtitle_label.text = "Rozliczono pracę Przystani i konsekwencje podjętych decyzji." if dive_result == null else "Rozliczono wyprawę, pracę Przystani i konsekwencje podjętych decyzji."
	_continue_button.text = "ROZPOCZNIJ DZIEŃ %d" % next_day
	var warning_count: int = report.warnings.size()
	if morning_report != null:
		warning_count += morning_report.warnings.size()
	_configure_warning_badge(warning_count)
	_configure_expedition_stats(dive_result)
	_populate_highlights(report, morning_report)
	_populate_report_list(_entries_list, report.entries, false)
	_populate_report_list(_warnings_list, report.warnings, true)
	_configure_details_layout(report.entries, report.warnings)
	_configure_morning_brief(morning_report, next_day)
	visible = true
	set_process(true)
	_window.call_deferred("reset_size")
	_continue_button.call_deferred("grab_focus")


func dismiss() -> void:
	set_process(false)
	var focus_owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()
	visible = false


func _process(_delta: float) -> void:
	if not visible or _continue_button == null or not is_inside_tree():
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null or not is_ancestor_of(focus_owner):
		_continue_button.grab_focus()


func _configure_warning_badge(warning_count: int) -> void:
	_warning_count_label.text = "BEZ OSTRZEŻEŃ" if warning_count == 0 else "%d  %s" % [warning_count, _warning_word(warning_count)]
	var accent := Color("79b6a6") if warning_count == 0 else Color("e0957f")
	_warning_count_label.add_theme_color_override("font_color", accent)
	_warning_count_label.add_theme_stylebox_override("normal", _panel_style(Color("172523e6") if warning_count == 0 else Color("2a1918e6"), accent, 1, 5))


func _warning_word(count: int) -> String:
	if count == 1:
		return "UWAGA"
	var last_two := count % 100
	var last_digit := count % 10
	var is_teen_exception := last_two >= 12 and last_two <= 14
	return "UWAGI" if not is_teen_exception and last_digit >= 2 and last_digit <= 4 else "UWAG"


func _configure_expedition_stats(dive_result) -> void:
	_status_value.remove_theme_color_override("font_color")
	var has_expedition := dive_result != null
	_loot_card.visible = has_expedition
	_duration_card.visible = has_expedition
	if dive_result == null:
		_status_card.add_theme_stylebox_override("panel", _panel_style(Color("142729e8"), Color("527a75"), 1, 5))
		_status_value.text = "BEZ WYPRAWY"
		_status_value.add_theme_color_override("font_color", Color("aebcba"))
		_loot_value.text = "—"
		_duration_value.text = "—"
		return

	_status_card.add_theme_stylebox_override("panel", _panel_style(Color("132328e8"), Color("405f61"), 1, 5))
	if bool(dive_result.diver_dead):
		_status_value.text = "NUREK NIE WRÓCIŁ"
		_status_value.add_theme_color_override("font_color", Color("ee8d79"))
		var lost_count := _sum_items(dive_result.lost_items)
		_loot_value.text = "UTRACONO %d SZT." % lost_count if lost_count > 0 else "UTRACONY"
	elif bool(dive_result.emergency_extraction):
		_status_value.text = "AWARYJNY POWRÓT"
		_status_value.add_theme_color_override("font_color", Color("e6bb72"))
		_loot_value.text = _loot_summary(dive_result.collected_items)
	else:
		_status_value.text = "BEZPIECZNY POWRÓT"
		_status_value.add_theme_color_override("font_color", Color("79c2a5"))
		_loot_value.text = _loot_summary(dive_result.collected_items)
	_duration_value.text = _format_duration(float(dive_result.dive_duration))


func _configure_morning_brief(morning_report, next_day: int) -> void:
	_morning_title.text = "PORANEK  •  DZIEŃ %d" % next_day
	var lines: Array[String] = []
	if morning_report != null:
		for warning in morning_report.warnings:
			lines.append("UWAGA: %s" % str(warning))
		for entry in morning_report.entries:
			lines.append(str(entry))
	_morning_label.text = "Nowy plan dnia jest gotowy." if lines.is_empty() else "  •  ".join(lines)


func _populate_highlights(report, morning_report) -> void:
	_clear_container(_highlights_list)
	var highlights: Array[Dictionary] = []
	var seen: Dictionary = {}

	for warning in report.warnings:
		_append_highlight(highlights, seen, str(warning), true)
		if highlights.size() >= MAX_HIGHLIGHTS:
			break

	if highlights.size() < MAX_HIGHLIGHTS and morning_report != null:
		for warning in morning_report.warnings:
			_append_highlight(highlights, seen, "Na poranek: %s" % str(warning), true)
			if highlights.size() >= MAX_HIGHLIGHTS:
				break

	var ranked_entries: Array[Dictionary] = []
	for index in range(report.entries.size()):
		var entry_text := str(report.entries[index])
		if _is_technical_entry(entry_text) or seen.has(entry_text):
			continue
		ranked_entries.append({
			"text": entry_text,
			"priority": _entry_priority(entry_text),
			"order": index,
		})
	ranked_entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_priority := int(left.get("priority", 0))
		var right_priority := int(right.get("priority", 0))
		if left_priority == right_priority:
			return int(left.get("order", 0)) < int(right.get("order", 0))
		return left_priority > right_priority
	)
	for ranked_entry in ranked_entries:
		_append_highlight(highlights, seen, str(ranked_entry.get("text", "")), false)
		if highlights.size() >= MAX_HIGHLIGHTS:
			break

	if highlights.size() < 3 and morning_report != null:
		for entry in morning_report.entries:
			_append_highlight(highlights, seen, "Na poranek: %s" % str(entry), false)
			if highlights.size() >= 3:
				break

	_highlights_panel.visible = not highlights.is_empty()
	if highlights.is_empty():
		return
	for highlight in highlights:
		_highlights_list.add_child(_highlight_row(
			str(highlight.get("text", "")),
			bool(highlight.get("warning", false))
		))
	_highlights_scroll.custom_minimum_size.y = clampf(float(highlights.size() * 23), 42.0, 92.0)


func _append_highlight(target: Array[Dictionary], seen: Dictionary, text: String, warning: bool) -> void:
	var normalized := text.strip_edges()
	if normalized.is_empty() or target.size() >= MAX_HIGHLIGHTS or seen.has(normalized):
		return
	seen[normalized] = true
	target.append({"text": normalized, "warning": warning})


func _entry_priority(text: String) -> int:
	var normalized := text.to_lower()
	for critical_word in ["zgin", "umiera", "uszkodz", "głód", "kryzys", "utrac", "nie zorganizowano"]:
		if normalized.contains(critical_word):
			return 80
	for change_word in ["odzyskano", "wyprodukow", "napraw", "ukończ", "zakończ", "zbudow", "nadzie", "jedzenia", "racje"]:
		if normalized.contains(change_word):
			return 50
	return 10


func _highlight_row(text: String, warning: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	var badge := Label.new()
	badge.custom_minimum_size = Vector2(58, 20)
	badge.text = "UWAGA" if warning else "ZMIANA"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", Color("f0a08a") if warning else Color("83c1b2"))
	badge.add_theme_stylebox_override("normal", _panel_style(
		Color("321d1be0") if warning else Color("17302de0"),
		Color("9b5d52") if warning else Color("477c72"),
		1,
		4
	))
	row.add_child(badge)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("e8b0a0") if warning else Color("d6dfdc"))
	row.add_child(label)
	return row


func _configure_details_layout(entries: Array[String], warnings: Array[String]) -> void:
	var visible_entry_count := 0
	for entry in entries:
		if not _is_technical_entry(str(entry)):
			visible_entry_count += 1
	var show_warnings := not warnings.is_empty()
	_warnings_column.visible = show_warnings
	_details_divider.visible = show_warnings
	var longest_column := maxi(visible_entry_count, warnings.size() if show_warnings else 0)
	_report_columns.custom_minimum_size.y = clampf(54.0 + float(longest_column * 17), 84.0, 100.0)


func _populate_report_list(container: VBoxContainer, lines: Array[String], warning: bool) -> void:
	_clear_container(container)

	var visible_lines: Array[String] = []
	for line in lines:
		var text := str(line)
		if not warning and _is_technical_entry(text):
			continue
		visible_lines.append(text)
	if visible_lines.is_empty():
		var empty := Label.new()
		empty.text = "Brak nowych ostrzeżeń." if warning else "Brak dodatkowych zdarzeń."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color("75a696") if warning else Color("879492"))
		container.add_child(empty)
		return

	for line in visible_lines:
		var label := Label.new()
		label.text = "%s  %s" % ["!" if warning else "•", line]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color("e7a08d") if warning else Color("cbd5d3"))
		container.add_child(label)


func _clear_container(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _is_technical_entry(text: String) -> bool:
	return text in [
		"Przygotowano raport na kolejny poranek.",
		"Kampania zostala zapisana.",
		"Kampania została zapisana.",
	]


func _loot_summary(items: Dictionary) -> String:
	var amount := _sum_items(items)
	return "%d SZT.  •  %d TYP." % [amount, items.size()] if amount > 0 else "BRAK ŁUPU"


func _sum_items(items: Dictionary) -> int:
	var result := 0
	for amount in items.values():
		result += maxi(int(amount), 0)
	return result


func _format_duration(duration: float) -> String:
	var total_seconds := maxi(int(round(duration)), 0)
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]


func _add_stat_card(parent: HBoxContainer, title: String, value_name: String) -> Label:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _panel_style(Color("132328e8"), Color("405f61"), 1, 5))
	parent.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 6)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", Color("84a09d"))
	stack.add_child(heading)
	var value := Label.new()
	value.name = value_name
	value.add_theme_font_size_override("font_size", 16)
	value.add_theme_color_override("font_color", Color("e5d8ba"))
	stack.add_child(value)
	return value


func _stat_card_for(value: Label) -> PanelContainer:
	if value == null:
		return null
	var stack := value.get_parent()
	var margin := stack.get_parent() if stack != null else null
	return margin.get_parent() as PanelContainer if margin != null else null


func _section_title(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
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
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style
