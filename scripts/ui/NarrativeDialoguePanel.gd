class_name NarrativeDialoguePanel
extends Control

signal dismissed(message_key: String)
signal cue_started(message_key: String, line_index: int, cue_id: String)
signal cue_activity_changed(active: bool)

const SurvivorPortraitScript := preload("res://scripts/ui/SurvivorPortrait.gd")
const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")
const NarrativeAudioCatalogScript := preload("res://scripts/ui/NarrativeAudioCatalog.gd")

const PANEL_MAX_WIDTH := 820.0
const PANEL_MIN_HEIGHT := 188.0
const PANEL_MAX_HEIGHT := 216.0
const COMPACT_BREAKPOINT := 760.0
const LINE_TYPE_DIALOGUE := "dialogue"
const LINE_TYPE_STAGE_DIRECTION := "stage_direction"
const LINE_TYPE_WORLD_EVENT := "world_event"

var _message_key: String = ""
var _lines: Array[Dictionary] = []
var _line_index: int = -1
var _backdrop: ColorRect
var _dialogue_panel: PanelContainer
var _dialogue_margin: MarginContainer
var _dialogue_row: HBoxContainer
var _left_portrait_frame: PanelContainer
var _right_portrait_frame: PanelContainer
var _left_portrait: Control
var _right_portrait: Control
var _text_column: VBoxContainer
var _context_label: Label
var _speaker_label: Label
var _line_kind_label: Label
var _title_label: Label
var _body_label: RichTextLabel
var _shortcut_label: Label
var _continue_button: Button
var _cue_player: AudioStreamPlayer
var _active_cue_id: String = ""
var _last_cue_token: String = ""
var _cue_active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_audio_player()
	_build_ui()
	visible = false
	resized.connect(_layout_dialogue)


func present(conversation: Dictionary, resolved_lines: Array[Dictionary]) -> void:
	_stop_current_cue(true)
	_message_key = str(conversation.get("key", ""))
	_lines.assign(resolved_lines)
	_line_index = 0
	var scene_context := str(conversation.get("scene_context", "")).strip_edges()
	_context_label.text = scene_context
	_context_label.visible = not scene_context.is_empty()
	_title_label.text = str(conversation.get("title", conversation.get("dialogue_title", "ROZMOWA")))
	visible = not _message_key.is_empty() and not _lines.is_empty()
	if not visible:
		clear()
		return
	_enter_current_line()
	_layout_dialogue()
	_continue_button.call_deferred("grab_focus")


func advance() -> void:
	if not visible:
		return
	if _line_index + 1 < _lines.size():
		_line_index += 1
		_enter_current_line()
		_continue_button.call_deferred("grab_focus")
		return
	dismiss()


func dismiss() -> void:
	if not visible:
		return
	var dismissed_key := _message_key
	clear()
	dismissed.emit(dismissed_key)


func clear() -> void:
	_stop_current_cue(true)
	_message_key = ""
	_lines.clear()
	_line_index = -1
	visible = false


func is_open() -> bool:
	return visible


func message_key() -> String:
	return _message_key


func line_index() -> int:
	return _line_index


func line_count() -> int:
	return _lines.size()


func current_line_type() -> String:
	if _line_index < 0 or _line_index >= _lines.size():
		return ""
	return _normalized_line_type(_lines[_line_index])


func current_side() -> String:
	if _line_index < 0 or _line_index >= _lines.size():
		return ""
	if _normalized_line_type(_lines[_line_index]) != LINE_TYPE_DIALOGUE:
		return ""
	return str(_lines[_line_index].get("side", "left"))


func current_cue_id() -> String:
	return _active_cue_id


func is_cue_playing() -> bool:
	return _cue_player != null and _cue_player.playing and not _active_cue_id.is_empty()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var is_echo := event is InputEventKey and (event as InputEventKey).echo
	if event.is_action_pressed(&"ui_accept") and not is_echo:
		advance()
	if event is InputEventKey or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()


func _render_line() -> void:
	if _line_index < 0 or _line_index >= _lines.size():
		return
	var line: Dictionary = _lines[_line_index]
	var line_type := _normalized_line_type(line)
	var speaker: Dictionary = line.get("speaker", {}) if line_type == LINE_TYPE_DIALOGUE else {}
	var side := str(line.get("side", "left"))
	if side not in ["left", "right"]:
		side = "left"
	_apply_line_type_presentation(line_type, side, speaker)
	_body_label.text = str(line.get("body", ""))
	_shortcut_label.text = "%d / %d   •   %s" % [
		_line_index + 1,
		_lines.size(),
		InputPromptScript.action_text(&"ui_accept", 2),
	]
	_continue_button.text = "ZAMKNIJ" if _line_index + 1 == _lines.size() else "DALEJ"
	_continue_button.tooltip_text = (
		"Zamknij scenę i wróć do Bazy."
		if _line_index + 1 == _lines.size()
		else "Pokaż następną część sceny."
	)
	if line_type == LINE_TYPE_DIALOGUE:
		_show_speaker_portrait(side, speaker)


func _enter_current_line() -> void:
	_render_line()
	_play_current_line_cue()


func _play_current_line_cue() -> void:
	if _line_index < 0 or _line_index >= _lines.size():
		_stop_current_cue()
		return
	var cue_token := "%s:%d" % [_message_key, _line_index]
	if cue_token == _last_cue_token:
		return
	_last_cue_token = cue_token
	_stop_current_cue()
	var cue_id := str(_lines[_line_index].get("cue_id", "")).strip_edges()
	if cue_id.is_empty():
		return
	var stream := NarrativeAudioCatalogScript.stream_for(cue_id)
	if stream == null or _cue_player == null:
		return
	_cue_player.stream = stream
	_cue_player.play()
	if not _cue_player.playing:
		_cue_player.stream = null
		return
	_active_cue_id = cue_id
	_set_cue_active(true)
	cue_started.emit(_message_key, _line_index, cue_id)


func _stop_current_cue(reset_token: bool = false) -> void:
	if _cue_player != null:
		_cue_player.stop()
		_cue_player.stream = null
	_active_cue_id = ""
	_set_cue_active(false)
	if reset_token:
		_last_cue_token = ""


func _set_cue_active(active: bool) -> void:
	if _cue_active == active:
		return
	_cue_active = active
	cue_activity_changed.emit(active)


func _on_cue_finished() -> void:
	if _cue_player != null:
		_cue_player.stream = null
	_active_cue_id = ""
	_set_cue_active(false)


func _normalized_line_type(line: Dictionary) -> String:
	var line_type := str(line.get("line_type", LINE_TYPE_DIALOGUE))
	if line_type in [LINE_TYPE_STAGE_DIRECTION, LINE_TYPE_WORLD_EVENT]:
		return line_type
	return LINE_TYPE_DIALOGUE


func _apply_line_type_presentation(line_type: String, side: String, speaker: Dictionary) -> void:
	var is_dialogue := line_type == LINE_TYPE_DIALOGUE
	_left_portrait_frame.visible = is_dialogue
	_right_portrait_frame.visible = is_dialogue
	_speaker_label.visible = is_dialogue
	_line_kind_label.visible = not is_dialogue
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if is_dialogue else HORIZONTAL_ALIGNMENT_CENTER
	if is_dialogue:
		_speaker_label.text = "%s  •  %s" % [
			str(speaker.get("display_name", "")),
			str(speaker.get("role_label", "")),
		]
		_speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if side == "right" else HORIZONTAL_ALIGNMENT_LEFT
		_body_label.add_theme_color_override("default_color", Color("d5e0dd"))
		return
	if line_type == LINE_TYPE_WORLD_EVENT:
		_line_kind_label.text = "ZMIANA W ŚWIECIE"
		_line_kind_label.add_theme_color_override("font_color", Color("e4b966"))
		_body_label.add_theme_color_override("default_color", Color("f0d89d"))
	else:
		_line_kind_label.text = "OPIS SCENY"
		_line_kind_label.add_theme_color_override("font_color", Color("8fb0aa"))
		_body_label.add_theme_color_override("default_color", Color("b8c8c4"))


func _show_speaker_portrait(side: String, speaker: Dictionary) -> void:
	var has_portrait := bool(speaker.get("has_portrait", false))
	_left_portrait_frame.modulate = Color.WHITE if has_portrait and side == "left" else Color(1, 1, 1, 0)
	_right_portrait_frame.modulate = Color.WHITE if has_portrait and side == "right" else Color(1, 1, 1, 0)
	if not has_portrait:
		return
	var portrait: Control = _right_portrait if side == "right" else _left_portrait
	portrait.call(
		"configure",
		str(speaker.get("portrait_id", "")),
		str(speaker.get("display_name", ""))
	)


func _build_audio_player() -> void:
	_cue_player = AudioStreamPlayer.new()
	_cue_player.name = "NarrativeCuePlayer"
	_cue_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	_cue_player.bus = &"Master"
	_cue_player.volume_db = -2.0
	_cue_player.max_polyphony = 1
	_cue_player.finished.connect(_on_cue_finished)
	add_child(_cue_player)


func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "NarrativeBackdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.color = Color(0.002, 0.009, 0.012, 0.48)
	add_child(_backdrop)

	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.name = "NarrativeDialogueBox"
	_dialogue_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_dialogue_panel.add_theme_stylebox_override("panel", _dialogue_style())
	add_child(_dialogue_panel)

	_dialogue_margin = MarginContainer.new()
	_dialogue_margin.name = "DialogueMargin"
	_dialogue_panel.add_child(_dialogue_margin)

	_dialogue_row = HBoxContainer.new()
	_dialogue_row.name = "DialogueRow"
	_dialogue_margin.add_child(_dialogue_row)

	var left_portrait := _build_portrait("Left")
	_left_portrait_frame = left_portrait.frame
	_left_portrait = left_portrait.portrait
	_dialogue_row.add_child(_left_portrait_frame)

	_text_column = VBoxContainer.new()
	_text_column.name = "NarrativeTextColumn"
	_text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialogue_row.add_child(_text_column)

	_context_label = Label.new()
	_context_label.name = "NarrativeContextLabel"
	_context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context_label.add_theme_color_override("font_color", Color("789b9a"))
	_context_label.add_theme_color_override("font_outline_color", Color("031014"))
	_context_label.add_theme_constant_override("outline_size", 1)
	_context_label.add_theme_font_size_override("font_size", 10)
	_context_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_context_label.visible = false
	_text_column.add_child(_context_label)

	_speaker_label = Label.new()
	_speaker_label.name = "NarrativeSpeakerLabel"
	_speaker_label.add_theme_color_override("font_color", Color("e4b966"))
	_speaker_label.add_theme_color_override("font_outline_color", Color("031014"))
	_speaker_label.add_theme_constant_override("outline_size", 2)
	_speaker_label.add_theme_font_size_override("font_size", 12)
	_speaker_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text_column.add_child(_speaker_label)

	_line_kind_label = Label.new()
	_line_kind_label.name = "NarrativeLineKindLabel"
	_line_kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line_kind_label.add_theme_color_override("font_outline_color", Color("031014"))
	_line_kind_label.add_theme_constant_override("outline_size", 2)
	_line_kind_label.add_theme_font_size_override("font_size", 11)
	_line_kind_label.visible = false
	_text_column.add_child(_line_kind_label)

	_title_label = Label.new()
	_title_label.name = "NarrativeTitleLabel"
	_title_label.add_theme_color_override("font_color", Color("edf4ef"))
	_title_label.add_theme_color_override("font_outline_color", Color("031014"))
	_title_label.add_theme_constant_override("outline_size", 3)
	_title_label.add_theme_font_size_override("font_size", 19)
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text_column.add_child(_title_label)

	_body_label = RichTextLabel.new()
	_body_label.name = "NarrativeBodyLabel"
	_body_label.custom_minimum_size = Vector2(0, 50)
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.bbcode_enabled = false
	_body_label.fit_content = false
	_body_label.scroll_active = false
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_label.add_theme_color_override("default_color", Color("d5e0dd"))
	_body_label.add_theme_color_override("font_outline_color", Color("031014"))
	_body_label.add_theme_constant_override("outline_size", 1)
	_body_label.add_theme_font_size_override("font_size", 14)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_column.add_child(_body_label)

	var footer := HBoxContainer.new()
	footer.name = "NarrativeFooter"
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 10)
	_text_column.add_child(footer)

	_shortcut_label = Label.new()
	_shortcut_label.name = "NarrativeShortcutLabel"
	_shortcut_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shortcut_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_shortcut_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_shortcut_label.add_theme_color_override("font_color", Color("789b9a"))
	_shortcut_label.add_theme_font_size_override("font_size", 11)
	footer.add_child(_shortcut_label)

	_continue_button = Button.new()
	_continue_button.name = "NarrativeContinueButton"
	_continue_button.custom_minimum_size = Vector2(126, 36)
	_continue_button.focus_mode = Control.FOCUS_ALL
	_continue_button.text = "DALEJ"
	_continue_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_continue_button.focus_neighbor_left = NodePath(".")
	_continue_button.focus_neighbor_top = NodePath(".")
	_continue_button.focus_neighbor_right = NodePath(".")
	_continue_button.focus_neighbor_bottom = NodePath(".")
	_continue_button.focus_next = NodePath(".")
	_continue_button.focus_previous = NodePath(".")
	_continue_button.add_theme_color_override("font_color", Color("d5e0dd"))
	_continue_button.add_theme_color_override("font_hover_color", Color("fff0c2"))
	_continue_button.add_theme_color_override("font_focus_color", Color("fff0c2"))
	_continue_button.add_theme_color_override("font_pressed_color", Color("fff7dc"))
	_continue_button.add_theme_font_size_override("font_size", 14)
	_continue_button.add_theme_stylebox_override("normal", _button_style(Color("102329"), Color("55777a"), 1))
	_continue_button.add_theme_stylebox_override("hover", _button_style(Color("183138"), Color("dfb665"), 2))
	_continue_button.add_theme_stylebox_override("focus", _button_style(Color("183138"), Color("dfb665"), 2))
	_continue_button.add_theme_stylebox_override("pressed", _button_style(Color("263a3d"), Color("f0cc81"), 2))
	_continue_button.pressed.connect(advance)
	footer.add_child(_continue_button)

	var right_portrait := _build_portrait("Right")
	_right_portrait_frame = right_portrait.frame
	_right_portrait = right_portrait.portrait
	_dialogue_row.add_child(_right_portrait_frame)


func _build_portrait(side_name: String) -> Dictionary:
	var frame := PanelContainer.new()
	frame.name = "NarrativePortraitFrame%s" % side_name
	frame.custom_minimum_size = Vector2(78, 96)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _portrait_style())

	var portrait_margin := MarginContainer.new()
	portrait_margin.add_theme_constant_override("margin_left", 3)
	portrait_margin.add_theme_constant_override("margin_top", 3)
	portrait_margin.add_theme_constant_override("margin_right", 3)
	portrait_margin.add_theme_constant_override("margin_bottom", 3)
	frame.add_child(portrait_margin)

	var portrait := SurvivorPortraitScript.new()
	portrait.name = "NarrativePortrait%s" % side_name
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.mirrored_horizontally = side_name == "Right"
	portrait_margin.add_child(portrait)
	return {"frame": frame, "portrait": portrait}


func _layout_dialogue() -> void:
	if _dialogue_panel == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var is_compact := size.x < COMPACT_BREAKPOINT
	var horizontal_margin := clampf(size.x * 0.04, 10.0, 46.0)
	var panel_width := minf(size.x - horizontal_margin * 2.0, PANEL_MAX_WIDTH)
	var panel_height := clampf(size.y * 0.30, PANEL_MIN_HEIGHT, PANEL_MAX_HEIGHT)
	var bottom_margin := clampf(size.y * 0.035, 12.0, 28.0)
	_dialogue_panel.position = Vector2(
		floorf((size.x - panel_width) * 0.5),
		floorf(size.y - panel_height - bottom_margin)
	)
	_dialogue_panel.size = Vector2(panel_width, panel_height)
	_set_margin_constants(10 if is_compact else 14, 10 if is_compact else 12)
	_dialogue_row.add_theme_constant_override("separation", 9 if is_compact else 13)
	_text_column.add_theme_constant_override("separation", 3 if is_compact else 4)
	var portrait_size := Vector2(62, 78) if is_compact else Vector2(78, 96)
	_left_portrait_frame.custom_minimum_size = portrait_size
	_right_portrait_frame.custom_minimum_size = portrait_size
	_context_label.add_theme_font_size_override("font_size", 9 if is_compact else 10)
	_speaker_label.add_theme_font_size_override("font_size", 10 if is_compact else 12)
	_line_kind_label.add_theme_font_size_override("font_size", 10 if is_compact else 11)
	_title_label.add_theme_font_size_override("font_size", 16 if is_compact else 19)
	_body_label.add_theme_font_size_override("font_size", 13 if is_compact else 14)
	_body_label.custom_minimum_size = Vector2(0, 44 if is_compact else 50)
	_continue_button.custom_minimum_size = Vector2(108, 34) if is_compact else Vector2(126, 36)
	_continue_button.add_theme_font_size_override("font_size", 12 if is_compact else 14)


func _set_margin_constants(horizontal: int, vertical: int) -> void:
	_dialogue_margin.add_theme_constant_override("margin_left", horizontal)
	_dialogue_margin.add_theme_constant_override("margin_top", vertical)
	_dialogue_margin.add_theme_constant_override("margin_right", horizontal)
	_dialogue_margin.add_theme_constant_override("margin_bottom", vertical)


func _dialogue_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("071519f2")
	style.border_color = Color("4c7777")
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.border_width_right = 3
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	style.shadow_color = Color(0, 0, 0, 0.58)
	style.shadow_size = 9
	style.shadow_offset = Vector2(0, 3)
	return style


func _portrait_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("09161a")
	style.border_color = Color("b98d4f")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	return style


func _button_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style
