class_name SettlementEventPanel
extends Control

const OfferSnapshotScript := preload("res://scripts/data/SettlementEventOfferSnapshot.gd")

signal choice_selected(choice_id: String)

var _built: bool = false
var _eyebrow_label: Label
var _category_label: Label
var _title_label: Label
var _body_label: Label
var _context_label: Label
var _window: PanelContainer
var _choices_scroll: ScrollContainer
var _choices: VBoxContainer
var _error_label: Label
var _choice_buttons: Dictionary = {}
var _availability: Dictionary = {}
var _previews: Dictionary = {}

func build() -> void:
	if _built:
		return
	_built = true
	name = "SettlementEventOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	visible = false
	set_process(false)

	var shade := ColorRect.new()
	shade.name = "SettlementEventDimmer"
	shade.color = Color(0.008, 0.018, 0.023, 0.89)
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
	_window.name = "SettlementEventWindow"
	_window.custom_minimum_size = Vector2(840, 0)
	_window.add_theme_stylebox_override("panel", _panel_style(Color("0d191efc"), Color("c58c45"), 2, 9))
	center.add_child(_window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 16)
	_window.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	content.add_child(header)
	_eyebrow_label = Label.new()
	_eyebrow_label.name = "SettlementEventEyebrow"
	_eyebrow_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eyebrow_label.add_theme_font_size_override("font_size", 13)
	_eyebrow_label.add_theme_color_override("font_color", Color("91b9b7"))
	header.add_child(_eyebrow_label)
	_category_label = Label.new()
	_category_label.name = "SettlementEventCategory"
	_category_label.custom_minimum_size = Vector2(146, 28)
	_category_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_category_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_category_label.add_theme_font_size_override("font_size", 13)
	_category_label.add_theme_color_override("font_color", Color("f2d39a"))
	_category_label.add_theme_stylebox_override("normal", _panel_style(Color("2b2118e6"), Color("9c733e"), 1, 5))
	header.add_child(_category_label)

	_title_label = Label.new()
	_title_label.name = "SettlementEventTitle"
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color("f3d59b"))
	content.add_child(_title_label)

	_body_label = Label.new()
	_body_label.name = "SettlementEventBody"
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.max_lines_visible = 3
	_body_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_body_label.add_theme_font_size_override("font_size", 15)
	_body_label.add_theme_color_override("font_color", Color("d6dfdd"))
	content.add_child(_body_label)

	var context_panel := PanelContainer.new()
	context_panel.add_theme_stylebox_override("panel", _panel_style(Color("14262ad9"), Color("365c60"), 1, 5))
	content.add_child(context_panel)
	var context_margin := MarginContainer.new()
	context_margin.add_theme_constant_override("margin_left", 14)
	context_margin.add_theme_constant_override("margin_top", 9)
	context_margin.add_theme_constant_override("margin_right", 14)
	context_margin.add_theme_constant_override("margin_bottom", 9)
	context_panel.add_child(context_margin)
	_context_label = Label.new()
	_context_label.name = "SettlementEventContext"
	_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context_label.add_theme_font_size_override("font_size", 13)
	_context_label.add_theme_color_override("font_color", Color("a9c8c4"))
	context_margin.add_child(_context_label)

	var decision_header := HBoxContainer.new()
	decision_header.add_theme_constant_override("separation", 16)
	content.add_child(decision_header)
	var decision_heading := Label.new()
	decision_heading.text = "DECYZJA PRZYSTANI"
	decision_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decision_heading.add_theme_font_size_override("font_size", 13)
	decision_heading.add_theme_color_override("font_color", Color("d1ae70"))
	decision_header.add_child(decision_heading)
	var decision_hint := Label.new()
	decision_hint.text = "Wybierz jedną opcję — skutek zostanie zastosowany od razu."
	decision_hint.add_theme_font_size_override("font_size", 13)
	decision_hint.add_theme_color_override("font_color", Color("82a4a1"))
	decision_header.add_child(decision_hint)

	_choices_scroll = ScrollContainer.new()
	_choices_scroll.name = "SettlementEventChoicesScroll"
	_choices_scroll.custom_minimum_size = Vector2(0, 136)
	_choices_scroll.focus_mode = Control.FOCUS_NONE
	_choices_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(_choices_scroll)
	_choices = VBoxContainer.new()
	_choices.name = "SettlementEventChoices"
	_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices.add_theme_constant_override("separation", 7)
	_choices_scroll.add_child(_choices)

	_error_label = Label.new()
	_error_label.name = "SettlementEventError"
	_error_label.visible = false
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.max_lines_visible = 2
	_error_label.add_theme_font_size_override("font_size", 13)
	_error_label.add_theme_color_override("font_color", Color("e89980"))
	_error_label.add_theme_stylebox_override("normal", _label_box_style(Color("301b19e8"), Color("9d5d4f")))
	content.add_child(_error_label)

func present(
	event_state,
	offer_snapshot,
	state,
	_availability_by_choice: Dictionary = {},
	_preview_by_choice: Dictionary = {}
) -> void:
	build()
	if event_state == null or offer_snapshot == null or offer_snapshot.get_script() != OfferSnapshotScript or state == null:
		dismiss()
		return
	if not offer_snapshot.validation_errors().is_empty():
		dismiss()
		return
	if str(event_state.event_id) != str(offer_snapshot.event_id) or str(event_state.history_key) != str(offer_snapshot.history_key):
		dismiss()
		return
	_eyebrow_label.text = "PORANEK  •  DZIEŃ %d  •  WYDARZENIE" % int(event_state.offered_day)
	_category_label.text = _category_name(str(offer_snapshot.category)).to_upper()
	_title_label.text = str(offer_snapshot.title)
	_body_label.text = str(offer_snapshot.body)
	_context_label.text = _settlement_context(state)
	_availability.clear()
	_previews.clear()
	for choice in offer_snapshot.choices:
		if choice == null:
			continue
		_availability[str(choice.id)] = {
			"available": bool(choice.available),
			"reason": str(choice.unavailable_reason),
			"preview_summary": str(choice.effect_summary),
		}
		_previews[str(choice.id)] = str(choice.effect_summary)
	_error_label.visible = false
	_error_label.text = ""
	_populate_choices(offer_snapshot)
	visible = true
	set_process(true)
	_window.call_deferred("reset_size")
	_focus_first_available()

func dismiss() -> void:
	set_process(false)
	var focus_owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()
	visible = false

func show_error(message: String) -> void:
	_error_label.text = message
	_error_label.visible = true
	_set_buttons_enabled(true)
	_window.call_deferred("reset_size")

func _populate_choices(offer_snapshot) -> void:
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	_choice_buttons.clear()
	var choices_height := 0.0
	var choice_count := 0
	for choice in offer_snapshot.choices:
		if choice == null:
			continue
		var choice_id := str(choice.id)
		var availability: Dictionary = _availability.get(choice_id, {"available": false, "reason": "Decyzja jest niedostępna."})
		var is_available := bool(availability.get("available", false))
		var exact_preview := _preview_text(choice, availability, choice_id)
		var unavailable_reason := str(availability.get("reason", "Decyzja jest niedostępna.")).strip_edges()
		if unavailable_reason.is_empty():
			unavailable_reason = "Decyzja jest niedostępna."
		choice_count += 1
		var button := Button.new()
		button.name = "SettlementEventChoice_%s" % choice_id
		button.custom_minimum_size = Vector2(0, 82 if not is_available else 66)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = _choice_button_text(
			choice_count,
			str(choice.label),
			exact_preview,
			unavailable_reason,
			is_available,
			str(choice.preview)
		)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.disabled = not is_available
		button.tooltip_text = unavailable_reason if not is_available else "Skutek: %s" % exact_preview
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_color_override("font_color", Color("f4e7cd"))
		button.add_theme_color_override("font_hover_color", Color("fff0ce"))
		button.add_theme_color_override("font_disabled_color", Color("c4aaa1"))
		button.add_theme_stylebox_override("normal", _button_style(Color("1b3035"), Color("527174"), 1))
		button.add_theme_stylebox_override("hover", _button_style(Color("284348"), Color("d2a45c"), 2))
		button.add_theme_stylebox_override("pressed", _button_style(Color("15282c"), Color("a97c3f"), 2))
		button.add_theme_stylebox_override("disabled", _button_style(Color("201d1ddd"), Color("76554d"), 1))
		button.pressed.connect(_on_choice_pressed.bind(choice_id))
		_choices.add_child(button)
		_choice_buttons[choice_id] = button
		choices_height += button.custom_minimum_size.y
	if choice_count > 1:
		choices_height += float((choice_count - 1) * 7)
	_choices_scroll.custom_minimum_size.y = clampf(choices_height, 66.0, 220.0)
	_configure_choice_focus_cycle()


func _preview_text(choice, availability: Dictionary, choice_id: String) -> String:
	var exact_preview = _previews.get(
		choice_id,
		availability.get("preview_summary", availability.get("summary", str(choice.preview)))
	)
	if exact_preview is Dictionary:
		exact_preview = exact_preview.get("preview_summary", exact_preview.get("summary", str(choice.preview)))
	var preview_text := str(exact_preview).strip_edges()
	return preview_text if not preview_text.is_empty() else "Bez zmian"


func _choice_button_text(
	index: int,
	label: String,
	exact_preview: String,
	unavailable_reason: String,
	is_available: bool,
	authored_preview: String
) -> String:
	var heading := "%02d   %s" % [index, label]
	if is_available:
		return "%s\nSKUTEK  •  %s" % [heading, exact_preview]
	var possible_effect := authored_preview.strip_edges()
	if possible_effect.is_empty():
		possible_effect = "Bez zmian"
	return "%s\nMOŻLIWY SKUTEK  •  %s\nNIEDOSTĘPNE  •  %s" % [
		heading,
		possible_effect,
		unavailable_reason,
	]

func _on_choice_pressed(choice_id: String) -> void:
	_set_buttons_enabled(false)
	choice_selected.emit(choice_id)

func _set_buttons_enabled(enabled: bool) -> void:
	for choice_id in _choice_buttons.keys():
		var button = _choice_buttons[choice_id]
		var availability: Dictionary = _availability.get(str(choice_id), {})
		button.disabled = not enabled or not bool(availability.get("available", false))
	_configure_choice_focus_cycle()

func _focus_first_available() -> void:
	var button := _first_available_button()
	if button != null:
		button.call_deferred("grab_focus")


func _process(_delta: float) -> void:
	if not visible or not is_inside_tree():
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		return
	var button := _first_available_button()
	if button != null:
		button.grab_focus()


func _first_available_button() -> Button:
	for child in _choices.get_children():
		if child is Button and not (child as Button).disabled:
			return child as Button
	return null


func _configure_choice_focus_cycle() -> void:
	var buttons: Array[Button] = []
	for child in _choices.get_children():
		if child is Button and not (child as Button).disabled:
			buttons.append(child as Button)
	if buttons.size() < 2:
		return
	for index in range(buttons.size()):
		var button := buttons[index]
		var previous := buttons[(index - 1 + buttons.size()) % buttons.size()]
		var next := buttons[(index + 1) % buttons.size()]
		button.focus_previous = button.get_path_to(previous)
		button.focus_next = button.get_path_to(next)
		button.focus_neighbor_top = button.get_path_to(previous)
		button.focus_neighbor_bottom = button.get_path_to(next)

func _settlement_context(state) -> String:
	var alive: int = state.get_alive_survivors().size()
	var healthy := 0
	for survivor in state.get_alive_survivors():
		if survivor.can_work():
			healthy += 1
	return "Mieszkańcy  %d  •  Zdolni do pracy  %d  •  Jedzenie  %.1f dnia  •  Nadzieja  %d  •  Integralność  %d%%" % [
		alive,
		healthy,
		float(state.get_food_days_left()),
		state.resources.get_amount("hope"),
		state.resources.get_amount("platform_integrity"),
	]

func _category_name(category: String) -> String:
	match category:
		"population":
			return "Ocaleni"
		"supplies":
			return "Zapasy"
		"platform":
			return "Platforma"
		"society":
			return "Społeczność"
		"trade":
			return "Handel"
	return "Przystań"

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


func _label_box_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := _panel_style(fill, border, 1, 4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _button_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := _panel_style(fill, border, width, 5)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
