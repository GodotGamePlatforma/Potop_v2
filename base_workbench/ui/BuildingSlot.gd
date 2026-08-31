class_name BuildingSlot
extends Button

signal slot_selected(slot_id: String)
signal slot_hover_changed(slot_id: String, hovered: bool)
signal slot_highlight_changed(slot_id: String, mode: StringName)

const INTERACTION_RESPONSE_SPEED := 18.0
const ATTENTION_PULSE_PERIOD := 2.8

const HIGHLIGHT_NONE := &"none"
const HIGHLIGHT_FOCUS := &"focus"
const HIGHLIGHT_HOVER := &"hover"
const HIGHLIGHT_PRESSED := &"pressed"
const HIGHLIGHT_TUTORIAL := &"tutorial"

const NORMAL_FILL := Color(0.02, 0.05, 0.07, 0.0)
const NORMAL_BORDER := Color(0.30, 0.70, 0.74, 0.0)
const QUEUED_FILL := Color(0.72, 0.43, 0.16, 0.07)
const QUEUED_BORDER := Color(0.92, 0.64, 0.28, 0.42)
const DISABLED_FILL := Color(0.02, 0.04, 0.05, 0.08)
const DISABLED_BORDER := Color(0.20, 0.25, 0.27, 0.25)

var slot_id: String = ""
var definition_id: String = ""
var is_tutorial_target: bool = false
var is_queued: bool = false
var _visual_rect_ratio := Rect2(0.0, 0.0, 1.0, 1.0)
var _pad_visual: Panel
var _rebuild_indicator: BuildingRebuildIndicator
var _visual_style: StyleBoxFlat
var _hovered := false
var _pointer_down := false
var _animation_elapsed := 0.0
var _forced_animation_time := -1.0
var _reduced_motion := false
var _instant_motion := false
var _style_initialized := false
var _current_fill := NORMAL_FILL
var _current_border := NORMAL_BORDER
var _last_highlight_mode: StringName = HIGHLIGHT_NONE

func _ready() -> void:
	text = ""
	flat = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_hide_button_chrome()
	_pad_visual = Panel.new()
	_pad_visual.name = "PadVisual"
	_pad_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pad_visual)
	_rebuild_indicator = get_node_or_null("RebuildIndicator") as BuildingRebuildIndicator
	if _rebuild_indicator != null:
		_rebuild_indicator.present(false, false)
	_visual_style = _style_box(NORMAL_FILL, NORMAL_BORDER, 1)
	_pad_visual.add_theme_stylebox_override("panel", _visual_style)
	_apply_visual_rect()
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	focus_entered.connect(_on_focus_changed)
	focus_exited.connect(_on_focus_changed)
	_apply_visual_state(_animation_elapsed, 0.0, true)

func _process(delta: float) -> void:
	var animation_time := _forced_animation_time
	var snap := _instant_motion or _forced_animation_time >= 0.0
	if _forced_animation_time < 0.0:
		_animation_elapsed += maxf(delta, 0.0)
		animation_time = _animation_elapsed
	_apply_visual_state(animation_time, delta, snap)

func configure(new_slot_id: String, new_definition_id: String, visual_rect_ratio := Rect2(0.0, 0.0, 1.0, 1.0)) -> void:
	slot_id = new_slot_id
	definition_id = new_definition_id
	set_visual_rect_ratio(visual_rect_ratio)
	_refresh_style()

func set_visual_rect_ratio(value: Rect2) -> void:
	_visual_rect_ratio = value
	_apply_visual_rect()

func set_state(tutorial_target: bool, queued: bool) -> void:
	is_tutorial_target = tutorial_target
	is_queued = queued
	_refresh_style()


func set_rebuild_indicator(is_ruined: bool, is_affordable: bool) -> void:
	if _rebuild_indicator != null:
		_rebuild_indicator.present(is_ruined, is_affordable)

func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_refresh_style(true)

func set_instant_motion(enabled: bool) -> void:
	_instant_motion = enabled
	_refresh_style(true)

func set_animation_time_for_tests(seconds: float) -> void:
	_forced_animation_time = maxf(seconds, 0.0)
	_animation_elapsed = _forced_animation_time
	_refresh_style(true)

func clear_animation_time_override() -> void:
	_forced_animation_time = -1.0
	_refresh_style(true)


func highlight_mode() -> StringName:
	if disabled:
		return HIGHLIGHT_NONE
	# Tutorial guidance replaces the old amber rectangle and remains visible until
	# the director advances the step. Pointer states are still remembered by the
	# control and become visible immediately after the tutorial target is removed.
	if is_tutorial_target:
		return HIGHLIGHT_TUTORIAL
	if _pointer_down:
		return HIGHLIGHT_PRESSED
	if _hovered:
		return HIGHLIGHT_HOVER
	if has_focus():
		return HIGHLIGHT_FOCUS
	return HIGHLIGHT_NONE

func _on_pressed() -> void:
	slot_selected.emit(slot_id)

func _on_mouse_entered() -> void:
	_hovered = true
	_refresh_style()
	slot_hover_changed.emit(slot_id, true)

func _on_mouse_exited() -> void:
	_hovered = false
	_pointer_down = false
	_refresh_style()
	slot_hover_changed.emit(slot_id, false)

func _on_button_down() -> void:
	_pointer_down = true
	_refresh_style()

func _on_button_up() -> void:
	_pointer_down = false
	_refresh_style()

func _on_focus_changed() -> void:
	_refresh_style()

func _refresh_style(snap: bool = false) -> void:
	if not is_inside_tree() or _pad_visual == null:
		return
	var animation_time := _forced_animation_time if _forced_animation_time >= 0.0 else _animation_elapsed
	_apply_visual_state(animation_time, 0.0, snap or _instant_motion or _forced_animation_time >= 0.0)

func _apply_visual_state(animation_time: float, delta: float, snap: bool) -> void:
	if _pad_visual == null or _visual_style == null:
		return
	var target := _target_style(animation_time)
	var target_fill: Color = target["fill"]
	var target_border: Color = target["border"]
	if snap or not _style_initialized:
		_current_fill = target_fill
		_current_border = target_border
		_style_initialized = true
	else:
		var response := 1.0 - exp(-INTERACTION_RESPONSE_SPEED * maxf(delta, 0.0))
		_current_fill = _current_fill.lerp(target_fill, response)
		_current_border = _current_border.lerp(target_border, response)
	_visual_style.bg_color = _current_fill
	_visual_style.border_color = _current_border
	_visual_style.set_border_width_all(int(target["border_width"]))
	_emit_highlight_state_if_changed()

func _target_style(animation_time: float) -> Dictionary:
	var fill := NORMAL_FILL
	var border := NORMAL_BORDER
	var border_width := 1
	# Queue feedback may apply to several slots at once, so it remains a subtle 2D
	# state. The singleton tutorial glow wins defensively if both flags coexist.
	if is_queued and not is_tutorial_target:
		fill = QUEUED_FILL
		border = QUEUED_BORDER
		border_width = 2

	var can_pulse := is_queued and not is_tutorial_target and not disabled and not _hovered and not _pointer_down and not has_focus() and not _reduced_motion and not _instant_motion
	if can_pulse:
		var pulse := 0.5 - 0.5 * cos(TAU * maxf(animation_time, 0.0) / ATTENTION_PULSE_PERIOD)
		var pulse_strength := pulse * 0.10
		var pulse_fill := Color(
			minf(fill.r + 0.08, 1.0),
			minf(fill.g + 0.055, 1.0),
			minf(fill.b + 0.015, 1.0),
			minf(fill.a + 0.07, 1.0)
		)
		fill = fill.lerp(pulse_fill, pulse_strength)
		border = border.lerp(Color(1.0, 0.84, 0.47, 1.0), pulse_strength)

	if disabled:
		fill = DISABLED_FILL
		border = DISABLED_BORDER
		border_width = 1
	return {"fill": fill, "border": border, "border_width": border_width}


func _emit_highlight_state_if_changed() -> void:
	var mode := highlight_mode()
	if mode == _last_highlight_mode:
		return
	_last_highlight_mode = mode
	slot_highlight_changed.emit(slot_id, mode)

func _hide_button_chrome() -> void:
	for style_name in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		add_theme_stylebox_override(style_name, StyleBoxEmpty.new())

func _apply_visual_rect() -> void:
	if _pad_visual == null:
		return
	_pad_visual.anchor_left = _visual_rect_ratio.position.x
	_pad_visual.anchor_top = _visual_rect_ratio.position.y
	_pad_visual.anchor_right = _visual_rect_ratio.end.x
	_pad_visual.anchor_bottom = _visual_rect_ratio.end.y
	_pad_visual.offset_left = 0.0
	_pad_visual.offset_top = 0.0
	_pad_visual.offset_right = 0.0
	_pad_visual.offset_bottom = 0.0

func _style_box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style
