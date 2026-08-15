class_name DiveLootPanel
extends ColorRect

signal take_amount_requested(resource_id: String, amount: int)
signal take_all_requested
signal recover_gear_requested(gear_id: String)
signal close_requested

const MAX_VISIBLE_ROWS := 4
const ROW_HEIGHT := 58.0
const ROW_SEPARATION := 7.0
const EMPTY_LIST_HEIGHT := 72.0

var _title_label: Label
var _summary_label: Label
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _empty_label: Label
var _take_all_button: Button
var _close_button: Button

var _container
var _session
var _item_name_provider: Callable
var _first_available_action: Control
var _is_built := false


func build() -> void:
	if _is_built:
		return
	_is_built = true
	name = "DiveLootPanel"
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

	var panel := _make_panel(Color("15272af5"), Color("d0a350"), 2)
	panel.custom_minimum_size = Vector2(860, 0)
	center.add_child(panel)

	var content := _margin_content(panel, 24)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	content.add_child(column)

	var eyebrow := Label.new()
	eyebrow.text = "ZNALEZIONY ŁUP  //  WYBIERZ, CO ZABIERASZ"
	eyebrow.add_theme_font_size_override("font_size", 11)
	eyebrow.add_theme_color_override("font_color", Color("8fa8aa"))
	column.add_child(eyebrow)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", Color("f2d18d"))
	column.add_child(_title_label)

	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 13)
	_summary_label.add_theme_color_override("font_color", Color("b9c6c4"))
	column.add_child(_summary_label)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	_add_header_label(header, "PRZEDMIOT", 250, true)
	_add_header_label(header, "DOSTĘPNE", 88)
	_add_header_label(header, "WAGA", 180)
	_add_header_label(header, "ILE", 92)
	_add_header_label(header, "AKCJA", 100)

	var separator := HSeparator.new()
	column.add_child(separator)

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

	_empty_label = Label.new()
	_empty_label.text = "Pojemnik jest pusty."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.custom_minimum_size = Vector2(0, EMPTY_LIST_HEIGHT)
	_empty_label.add_theme_font_size_override("font_size", 16)
	_empty_label.add_theme_color_override("font_color", Color("779197"))
	_rows.add_child(_empty_label)

	var footer_separator := HSeparator.new()
	column.add_child(footer_separator)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)

	_close_button = Button.new()
	_close_button.name = "LeaveLootButton"
	_close_button.text = "Zamknij"
	_close_button.custom_minimum_size = Vector2(118, 42)
	_close_button.pressed.connect(_on_close_pressed)
	footer.add_child(_close_button)

	_take_all_button = Button.new()
	_take_all_button.name = "TakeAllButton"
	_take_all_button.text = "Zabierz wszystko"
	_take_all_button.custom_minimum_size = Vector2(174, 42)
	_take_all_button.add_theme_color_override("font_color", Color("fff0cf"))
	_take_all_button.add_theme_stylebox_override("normal", _action_button_style(false))
	_take_all_button.add_theme_stylebox_override("hover", _action_button_style(true))
	_take_all_button.add_theme_stylebox_override("pressed", _action_button_style(false))
	_take_all_button.add_theme_stylebox_override("focus", _action_button_style(true))
	_take_all_button.pressed.connect(_on_take_all_pressed)
	footer.add_child(_take_all_button)


func present(container, session, item_name_provider: Callable) -> void:
	build()
	_container = container
	_session = session
	_item_name_provider = item_name_provider
	visible = true
	refresh()


func refresh(container = null, session = null, item_name_provider: Callable = Callable()) -> void:
	build()
	if container != null:
		_container = container
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
	_container = null
	_session = null
	_first_available_action = null


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	close_requested.emit()


func _rebuild_rows() -> void:
	_clear_rows()
	_first_available_action = null
	if _container == null or _session == null:
		_title_label.text = "Zawartość pojemnika"
		_summary_label.text = "Brak danych o pojemniku."
		_empty_label = _add_empty_message("Brak zawartości do wyświetlenia.")
		_take_all_button.disabled = true
		_update_list_height(0)
		return

	_title_label.text = str(_container.display_name)
	_summary_label.text = "PLECAK  %d / %d SLOTÓW   •   WAGA  %.1f / %.1f kg   •   WOLNE  %.1f kg" % [
		_session.slots_used(),
		_session.backpack_capacity,
		_session.get_carried_weight(),
		_session.carry_capacity,
		_session.remaining_carry_capacity(),
	]

	var has_any_entry := false
	var has_takeable_resource := false
	var has_recoverable_gear := false
	for resource_key in _container.contents.keys():
		var resource_id := str(resource_key)
		var available := maxi(int(_container.contents[resource_key]), 0)
		if available <= 0:
			continue
		has_any_entry = true
		var max_addable := mini(available, int(_session.max_addable_amount(resource_id, available)))
		var action := _add_resource_row(resource_id, available, max_addable)
		if max_addable > 0:
			has_takeable_resource = true
			if _first_available_action == null:
				_first_available_action = action

	if _container is DiveLostBackpack:
		var backpack := _container as DiveLostBackpack
		for gear_key in backpack.gear_ids:
			var gear_id := str(gear_key)
			if gear_id.is_empty():
				continue
			has_any_entry = true
			has_recoverable_gear = true
			var action := _add_gear_row(gear_id)
			if _first_available_action == null:
				_first_available_action = action

	if not has_any_entry:
		_empty_label = _add_empty_message("Pojemnik jest pusty.")
	_update_list_height(_rows.get_child_count() if has_any_entry else 0)
	var can_take_all := has_takeable_resource or has_recoverable_gear
	_take_all_button.disabled = not can_take_all
	_take_all_button.tooltip_text = "Brak zasobów mieszczących się w plecaku ani sprzętu do odzyskania." if not can_take_all else "Zabierz wszystkie mieszczące się zasoby i odzyskaj sprzęt."


func _add_resource_row(resource_id: String, available: int, max_addable: int) -> Button:
	var row_panel := _make_panel(Color("0d1b20e8"), Color("36545b"))
	row_panel.custom_minimum_size = Vector2(0, 58)
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_child(row_panel)

	var margin := _margin_content(row_panel, 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var name_label := Label.new()
	name_label.text = _display_name(resource_id)
	name_label.custom_minimum_size = Vector2(250, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color("f2e4c5"))
	row.add_child(name_label)

	var amount_label := Label.new()
	amount_label.text = "x%d" % available
	amount_label.custom_minimum_size = Vector2(88, 0)
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount_label.add_theme_color_override("font_color", Color("e6bd68"))
	row.add_child(amount_label)

	var unit_weight := float(_session.get_unit_weight(resource_id))
	var weight_label := Label.new()
	weight_label.text = "%.1f kg/szt.  •  %.1f kg" % [unit_weight, unit_weight * available]
	weight_label.custom_minimum_size = Vector2(180, 0)
	weight_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weight_label.add_theme_font_size_override("font_size", 12)
	weight_label.add_theme_color_override("font_color", Color("9eb4b6"))
	row.add_child(weight_label)

	var amount_input := SpinBox.new()
	amount_input.custom_minimum_size = Vector2(92, 38)
	amount_input.step = 1.0
	amount_input.rounded = true
	amount_input.allow_greater = false
	amount_input.allow_lesser = false
	if max_addable > 0:
		amount_input.min_value = 1.0
		amount_input.max_value = float(max_addable)
		amount_input.value = float(max_addable)
	else:
		amount_input.min_value = 0.0
		amount_input.max_value = 0.0
		amount_input.value = 0.0
		amount_input.editable = false
		amount_input.tooltip_text = "Brak wolnego slotu albo udźwigu."
	row.add_child(amount_input)

	var take_button := Button.new()
	take_button.name = "Take_%s" % resource_id
	take_button.text = "Zabierz"
	take_button.custom_minimum_size = Vector2(100, 38)
	take_button.disabled = max_addable <= 0
	take_button.tooltip_text = "Brak wolnego slotu albo udźwigu." if take_button.disabled else "Zabierz wybraną liczbę sztuk."
	take_button.pressed.connect(_on_take_pressed.bind(resource_id, amount_input))
	row.add_child(take_button)
	return take_button


func _add_gear_row(gear_id: String) -> Button:
	var row_panel := _make_panel(Color("10242ae8"), Color("4e8f90"))
	row_panel.custom_minimum_size = Vector2(0, 58)
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_child(row_panel)

	var margin := _margin_content(row_panel, 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var name_label := Label.new()
	name_label.text = _display_name(gear_id)
	name_label.custom_minimum_size = Vector2(250, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color("a5eee1"))
	row.add_child(name_label)

	var kind_label := Label.new()
	kind_label.text = "SPRZĘT"
	kind_label.custom_minimum_size = Vector2(88, 0)
	kind_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kind_label.add_theme_font_size_override("font_size", 11)
	kind_label.add_theme_color_override("font_color", Color("67c9bd"))
	row.add_child(kind_label)

	var note_label := Label.new()
	note_label.text = "Wyposażenie osobiste nurka"
	note_label.custom_minimum_size = Vector2(282, 0)
	note_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note_label.add_theme_font_size_override("font_size", 12)
	note_label.add_theme_color_override("font_color", Color("9eb4b6"))
	row.add_child(note_label)

	var recover_button := Button.new()
	recover_button.name = "Recover_%s" % gear_id
	recover_button.text = "Odzyskaj"
	recover_button.custom_minimum_size = Vector2(100, 38)
	recover_button.tooltip_text = "Odzyskaj ten element wyposażenia."
	recover_button.pressed.connect(_on_recover_gear_pressed.bind(gear_id))
	row.add_child(recover_button)
	return recover_button


func _clear_rows() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_empty_label = null


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


func _add_empty_message(message: String) -> Label:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, EMPTY_LIST_HEIGHT)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("779197"))
	_rows.add_child(label)
	return label


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
	if _first_available_action != null and is_instance_valid(_first_available_action):
		_first_available_action.grab_focus()
	elif not _take_all_button.disabled:
		_take_all_button.grab_focus()
	else:
		_close_button.grab_focus()


func _on_take_pressed(resource_id: String, amount_input: SpinBox) -> void:
	if not is_instance_valid(amount_input) or not amount_input.editable:
		return
	var amount := maxi(int(round(amount_input.value)), 0)
	if amount > 0:
		take_amount_requested.emit(resource_id, amount)


func _on_take_all_pressed() -> void:
	take_all_requested.emit()


func _on_recover_gear_pressed(gear_id: String) -> void:
	recover_gear_requested.emit(gear_id)


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


func _action_button_style(highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("a36929") if highlighted else Color("805020")
	style.border_color = Color("f1c66f") if highlighted else Color("d0a350")
	style.set_border_width_all(2)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style


func _margin_content(parent: Control, amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", amount)
	margin.add_theme_constant_override("margin_top", amount)
	margin.add_theme_constant_override("margin_right", amount)
	margin.add_theme_constant_override("margin_bottom", amount)
	parent.add_child(margin)
	return margin
