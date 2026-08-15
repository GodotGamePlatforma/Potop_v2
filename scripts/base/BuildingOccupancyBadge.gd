class_name BuildingOccupancyBadge
extends PanelContainer

const SurvivorPortraitScript := preload("res://scripts/ui/SurvivorPortrait.gd")

const PANEL_COLOR := Color("0a1519ed")
const PANEL_BORDER_COLOR := Color("587075")
const PANEL_ACCENT_COLOR := Color("d7b870")
const TEXT_COLOR := Color("d9e3df")
const MUTED_COLOR := Color("8fa3a2")
const EMPTY_BORDER_COLOR := Color("40585d")
const READY_BORDER_COLOR := Color("5d8584")
const WARNING_COLOR := Color("efb15f")
const WARNING_BORDER_COLOR := Color("b47742")
const PORTRAIT_SIZE := Vector2(28.0, 34.0)

var _slot_id := ""
var _building_name := ""
var _capacity := 0
var _workers: Array[Dictionary] = []
var _should_show := false
var _hovered := false
var _content: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_theme_stylebox_override("panel", _panel_style(PANEL_COLOR, PANEL_BORDER_COLOR, 1, 4))
	_rebuild()


func configure(
	new_slot_id: String,
	new_building_name: String,
	new_capacity: int,
	new_workers: Array,
	new_should_show: bool
) -> void:
	_slot_id = new_slot_id
	_building_name = new_building_name
	_capacity = clampi(new_capacity, 0, 3)
	_workers.clear()
	for value in new_workers:
		if value is Dictionary and _workers.size() < _capacity:
			_workers.append((value as Dictionary).duplicate(true))
	_should_show = new_should_show
	visible = _should_show and _hovered
	if is_node_ready():
		_rebuild()


func set_hovered(hovered: bool) -> void:
	_hovered = hovered
	visible = _should_show and _hovered


func state_for_tests() -> Dictionary:
	var portrait_ids: Array[String] = []
	var display_names: Array[String] = []
	var blockers: Array[String] = []
	for worker in _workers:
		portrait_ids.append(str(worker.get("portrait_id", "")))
		display_names.append(str(worker.get("display_name", "")))
		blockers.append(str(worker.get("blocker", "")))
	return {
		"slot_id": _slot_id,
		"visible": visible,
		"hovered": _hovered,
		"has_built_building": _should_show,
		"building_name": _building_name,
		"capacity": _capacity,
		"assigned_count": _workers.size(),
		"has_blocked_worker": _has_blocked_worker(),
		"portrait_ids": portrait_ids,
		"display_names": display_names,
		"blockers": blockers,
	}


func _rebuild() -> void:
	if _content != null:
		remove_child(_content)
		_content.queue_free()
		_content = null
	visible = _should_show and _hovered
	if not _should_show:
		return

	var margin := MarginContainer.new()
	margin.name = "BadgeMargin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)
	_content = margin

	var stack := VBoxContainer.new()
	stack.name = "BadgeContent"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 1)
	margin.add_child(stack)

	var header := HBoxContainer.new()
	header.name = "BadgeHeader"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 4)
	stack.add_child(header)

	var title := Label.new()
	title.name = "BuildingName"
	title.text = _building_name.to_upper()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", PANEL_ACCENT_COLOR)
	header.add_child(title)

	var count := Label.new()
	count.name = "OccupancyCount"
	count.text = "%d/%d" % [_workers.size(), _capacity]
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.add_theme_font_size_override("font_size", 10)
	count.add_theme_color_override("font_color", WARNING_COLOR if _has_blocked_worker() else TEXT_COLOR)
	header.add_child(count)

	var divider := HSeparator.new()
	divider.name = "BadgeDivider"
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.add_theme_color_override("separator", Color("355159"))
	stack.add_child(divider)

	var body := HBoxContainer.new()
	body.name = "BadgeBody"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	stack.add_child(body)

	var portraits := HBoxContainer.new()
	portraits.name = "OccupancyPortraits"
	portraits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portraits.add_theme_constant_override("separation", 2)
	body.add_child(portraits)
	for slot_index in range(_capacity):
		portraits.add_child(_portrait_cell(slot_index))

	var copy := VBoxContainer.new()
	copy.name = "OccupancyCopy"
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 0)
	body.add_child(copy)

	var status := Label.new()
	status.name = "OccupancyStatus"
	status.text = _status_text()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_theme_font_size_override("font_size", 8)
	status.add_theme_color_override("font_color", WARNING_COLOR if _has_blocked_worker() else MUTED_COLOR)
	copy.add_child(status)

	var names := Label.new()
	names.name = "OccupantNames"
	names.text = _names_text()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.size_flags_vertical = Control.SIZE_EXPAND_FILL
	names.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	names.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_theme_font_size_override("font_size", 9)
	names.add_theme_color_override("font_color", TEXT_COLOR if not _workers.is_empty() else MUTED_COLOR)
	copy.add_child(names)


func _portrait_cell(slot_index: int) -> PanelContainer:
	var worker: Dictionary = _workers[slot_index] if slot_index < _workers.size() else {}
	var is_assigned := not worker.is_empty()
	var is_ready := bool(worker.get("ready", false)) if is_assigned else false
	var border_color := READY_BORDER_COLOR if is_ready else (WARNING_BORDER_COLOR if is_assigned else EMPTY_BORDER_COLOR)

	var cell := PanelContainer.new()
	cell.name = "OccupancySlot_%d" % slot_index
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.custom_minimum_size = PORTRAIT_SIZE
	cell.add_theme_stylebox_override("panel", _panel_style(Color("091216f4"), border_color, 1, 2))

	var stage := Control.new()
	stage.name = "PortraitStage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.custom_minimum_size = PORTRAIT_SIZE
	cell.add_child(stage)
	if not is_assigned:
		var empty_marker := Label.new()
		empty_marker.name = "EmptyOccupancySlot_%d" % slot_index
		empty_marker.text = "—"
		empty_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
		empty_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_marker.add_theme_font_size_override("font_size", 12)
		empty_marker.add_theme_color_override("font_color", MUTED_COLOR)
		stage.add_child(empty_marker)
		return cell

	var portrait = SurvivorPortraitScript.new()
	portrait.name = "OccupantPortrait_%d" % slot_index
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 1
	portrait.offset_top = 1
	portrait.offset_right = -1
	portrait.offset_bottom = -1
	stage.add_child(portrait)
	portrait.configure(str(worker.get("portrait_id", "")), str(worker.get("display_name", "")))

	if not is_ready:
		var warning := Label.new()
		warning.name = "OccupancyWarning_%d" % slot_index
		warning.text = "!"
		warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
		warning.anchor_left = 1.0
		warning.anchor_right = 1.0
		warning.offset_left = -11
		warning.offset_top = 1
		warning.offset_right = -1
		warning.offset_bottom = 13
		warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warning.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		warning.add_theme_font_size_override("font_size", 9)
		warning.add_theme_color_override("font_color", Color("fff2cf"))
		warning.add_theme_color_override("font_shadow_color", Color("402313"))
		warning.add_theme_constant_override("shadow_offset_x", 1)
		warning.add_theme_constant_override("shadow_offset_y", 1)
		stage.add_child(warning)
	return cell


func _status_text() -> String:
	if _workers.is_empty():
		return "NIEOBSADZONE"
	if _has_blocked_worker():
		return "OBSADA • UWAGA"
	return "OBSADZONE PRZEZ"


func _names_text() -> String:
	if _workers.is_empty():
		return "Wolne stanowiska"
	var names: Array[String] = []
	for worker in _workers:
		var display_name := str(worker.get("display_name", "Nieznana osoba")).strip_edges()
		if _workers.size() == 1:
			names.append(display_name)
		else:
			var parts := display_name.split(" ", false)
			names.append(str(parts[0]) if not parts.is_empty() else display_name)
	return " • ".join(names)


func _has_blocked_worker() -> bool:
	for worker in _workers:
		if not bool(worker.get("ready", false)):
			return true
	return false


func _panel_style(background: Color, border: Color, border_width: int, corner_radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.shadow_color = Color("00000078")
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	return style
