class_name BuildingRebuildIndicator
extends Control

## Purely presentational marker for a ruined building slot. The controller
## supplies affordability from BuildingSystem; this node never reads campaign
## state or accepts input.

const ICON_TEXTURE := preload("res://base_workbench/assets/ui/building_rebuild_indicator.png")
const READY_TINT := Color(1.0, 1.0, 1.0, 0.96)
const DIM_TINT := Color(0.42, 0.56, 0.55, 0.48)

var _is_ruined := false
var _is_affordable := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func present(is_ruined: bool, is_affordable: bool) -> void:
	var visibility_changed := _is_ruined != is_ruined
	var tone_changed := _is_affordable != is_affordable
	_is_ruined = is_ruined
	_is_affordable = is_affordable
	visible = _is_ruined
	if visibility_changed or tone_changed:
		queue_redraw()


func is_affordable_for_tests() -> bool:
	return _is_affordable


func _draw() -> void:
	if not _is_ruined:
		return
	var center := size * 0.5
	var icon_size := clampf(minf(size.x, size.y) * 0.18, 28.0, 36.0)
	var icon_rect := Rect2(center - Vector2.ONE * icon_size * 0.5, Vector2.ONE * icon_size)
	draw_texture_rect(ICON_TEXTURE, icon_rect, false, READY_TINT if _is_affordable else DIM_TINT)
