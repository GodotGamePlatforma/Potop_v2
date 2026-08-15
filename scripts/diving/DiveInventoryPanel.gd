class_name DiveInventoryPanel
extends ColorRect

signal drop_amount_requested(resource_id: String, amount: int)
signal close_requested

const MAX_VISIBLE_ROWS := 4
const ROW_HEIGHT := 58.0
const ROW_SEPARATION := 7.0
const EMPTY_LIST_HEIGHT := 72.0

var _summary_label: Label
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _close_button: Button

var _session
var _item_name_provider: Callable
var _first_drop_button: Button
var _is_built := false


func build() -> void:
	if _is_built:
		return
	_is_built = true
	name = "DiveInventoryPanel"
	color = Color("0a1b1fc2")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 110
	visible = false

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := _make_panel(Color("15272af5"), Color("b66d58"), 2)
	panel.custom_minimum_size = Vector2(820, 0)
	center.add_child(panel)

	var content := _margin_content(panel, 24)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	content.add_child(column)

	var eyebrow := Label.new()
	eyebrow.text = "PLECAK NURKA  //  ZARZĄDZANIE ŁADUNKIEM"
	eyebrow.add_theme_font_size_override("font_size", 11)
	eyebrow.add_theme_color_override("font_color", Color("8fa8aa"))
	column.add_child(eyebrow)

	var title := Label.new()
	title.text = "Zawartość plecaka"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("f2e4c5"))
	column.add_child(title)

	var warning_panel := _make_panel(Color("2b1c18e8"), Color("b66d58"))
	column.add_child(warning_panel)
	var warning_margin := _margin_content(warning_panel, 10)
	var warning := Label.new()
	warning.text = "Porzucone przedmioty utworzą w tym miejscu trwały pakunek. Możesz odzyskać go podczas tej lub kolejnej wyprawy."
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_font_size_override("font_size", 13)
	warning.add_theme_color_override("font_color", Color("efc1ad"))
	warning_margin.add_child(warning)

	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 13)
	_summary_label.add_theme_color_override("font_color", Color("b9c6c4"))
	column.add_child(_summary_label)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	_add_header_label(header, "PRZEDMIOT", 280, true)
	_add_header_label(header, "ILOŚĆ I WAGA", 230)
	_add_header_label(header, "ILE", 92)
	_add_header_label(header, "AKCJA", 100)

	column.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, EMPTY_LIST_HEIGHT)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(_scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 7)
	_scroll.add_child(_rows)

	var empty_label := Label.new()
	empty_label.text = "Plecak jest pusty."
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.custom_minimum_size = Vector2(0, EMPTY_LIST_HEIGHT)
	empty_label.add_theme_font_size_override("font_size", 16)
	empty_label.add_theme_color_override("font_color", Color("779197"))
	_rows.add_child(empty_label)

	column.add_child(HSeparator.new())

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(footer)
	_close_button = Button.new()
	_close_button.name = "CloseInventoryButton"
	_close_button.text = "Zamknij"
	_close_button.custom_minimum_size = Vector2(128, 42)
	_close_button.pressed.connect(_on_close_pressed)
	footer.add_child(_close_button)


func present(session, item_name_provider: Callable) -> void:
	build()
	_session = session
	_item_name_provider = item_name_provider
	visible = true
	refresh()


func refresh(session = null, item_name_provider: Callable = Callable()) -> void:
	build()
	if session != null:
		_session = session
	if item_name_provider.is_valid():
		_item_name_provider = item_name_provider

	_rebuild_rows()
	if visible and is_inside_tree():
		call_deferred("_focus_initial_control")


func dismiss() -> void:
	if not _is_built:
		return
	var focus_owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()
	visible = false
	_session = null
	_first_drop_button = null


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	close_requested.emit()


func _rebuild_rows() -> void:
	_clear_rows()
	_first_drop_button = null
	if _session == null:
		_summary_label.text = "Brak danych o plecaku."
		_add_empty_message("Brak zawartości do wyświetlenia.")
		_update_list_height(0)
		return

	_summary_label.text = "PLECAK  %d / %d SLOTÓW   •   WAGA  %.1f / %.1f kg   •   WOLNE  %.1f kg" % [
		_session.slots_used(),
		_session.backpack_capacity,
		_session.get_carried_weight(),
		_session.carry_capacity,
		_session.remaining_carry_capacity(),
	]

	var has_items := false
	for resource_key in _session.carried_item_order:
		var resource_id := str(resource_key)
		var amount := maxi(int(_session.carried_items.get(resource_id, 0)), 0)
		if amount <= 0:
			continue
		has_items = true
		var drop_button := _add_item_row(resource_id, amount)
		if _first_drop_button == null:
			_first_drop_button = drop_button

	if not has_items:
		_add_empty_message("Plecak jest pusty.")
	_update_list_height(_rows.get_child_count() if has_items else 0)


func _add_item_row(resource_id: String, amount: int) -> Button:
	var row_panel := _make_panel(Color("0d1b20e8"), Color("4a5e62"))
	row_panel.custom_minimum_size = Vector2(0, 58)
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_child(row_panel)

	var margin := _margin_content(row_panel, 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var name_label := Label.new()
	name_label.text = _display_name(resource_id)
	name_label.custom_minimum_size = Vector2(280, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color("f2e4c5"))
	row.add_child(name_label)

	var unit_weight := float(_session.get_unit_weight(resource_id))
	var details_label := Label.new()
	details_label.text = "x%d  •  %.1f kg/szt.  •  %.1f kg" % [amount, unit_weight, unit_weight * amount]
	details_label.custom_minimum_size = Vector2(230, 0)
	details_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	details_label.add_theme_font_size_override("font_size", 12)
	details_label.add_theme_color_override("font_color", Color("9eb4b6"))
	row.add_child(details_label)

	var amount_input := SpinBox.new()
	amount_input.custom_minimum_size = Vector2(92, 38)
	amount_input.min_value = 1.0
	amount_input.max_value = float(amount)
	amount_input.value = 1.0
	amount_input.step = 1.0
	amount_input.rounded = true
	amount_input.allow_greater = false
	amount_input.allow_lesser = false
	row.add_child(amount_input)

	var drop_button := Button.new()
	drop_button.name = "Drop_%s" % resource_id
	drop_button.text = "Porzuć"
	drop_button.custom_minimum_size = Vector2(100, 38)
	drop_button.tooltip_text = "Porzuć wybraną liczbę sztuk jako trwały pakunek."
	drop_button.add_theme_color_override("font_color", Color("ffd2bd"))
	drop_button.pressed.connect(_on_drop_pressed.bind(resource_id, amount_input))
	row.add_child(drop_button)
	return drop_button


func _clear_rows() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()


func _update_list_height(item_count: int) -> void:
	if _scroll == null:
		return
	if item_count <= 0:
		_scroll.custom_minimum_size.y = EMPTY_LIST_HEIGHT
		return
	var visible_rows := mini(item_count, MAX_VISIBLE_ROWS)
	_scroll.custom_minimum_size.y = (
		float(visible_rows) * ROW_HEIGHT
		+ float(maxi(visible_rows - 1, 0)) * ROW_SEPARATION
	)


func _add_empty_message(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, EMPTY_LIST_HEIGHT)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("779197"))
	_rows.add_child(label)


func _display_name(resource_id: String) -> String:
	var provided_name := ""
	if _item_name_provider.is_valid():
		provided_name = str(_item_name_provider.call(resource_id)).strip_edges()
	if provided_name.is_empty() or provided_name == resource_id:
		return resource_id.replace("_", " ").capitalize()
	return provided_name


func _focus_initial_control() -> void:
	if not visible or not is_inside_tree():
		return
	if _first_drop_button != null and is_instance_valid(_first_drop_button):
		_first_drop_button.grab_focus()
	else:
		_close_button.grab_focus()


func _on_drop_pressed(resource_id: String, amount_input: SpinBox) -> void:
	if not is_instance_valid(amount_input):
		return
	var amount := maxi(int(round(amount_input.value)), 0)
	if amount > 0:
		drop_amount_requested.emit(resource_id, amount)


func _on_close_pressed() -> void:
	close_requested.emit()


func _add_header_label(parent: HBoxContainer, text_value: String, width: float, expand: bool = false) -> void:
	var label := Label.new()
	label.text = text_value
	label.custom_minimum_size.x = width
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("738f94"))
	parent.add_child(label)


func _make_panel(fill: Color, border: Color, width: int = 1) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _margin_content(parent: Control, amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", amount)
	margin.add_theme_constant_override("margin_top", amount)
	margin.add_theme_constant_override("margin_right", amount)
	margin.add_theme_constant_override("margin_bottom", amount)
	parent.add_child(margin)
	return margin
