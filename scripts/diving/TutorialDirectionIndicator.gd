class_name TutorialDirectionIndicator
extends Control

const RING_RADIUS := 72.0
const ARROW_LENGTH := 25.0
const ARROW_HALF_WIDTH := 13.0
const TARGET_REACHED_DISTANCE := 36.0
const INDICATOR_SIZE := Vector2(220.0, 220.0)

var target_label: String = ""
var target_distance: float = 0.0
var direction := Vector2.RIGHT


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func present(world_direction: Vector2, label: String, distance: float) -> void:
	target_label = label
	target_distance = maxf(distance, 0.0)
	visible = world_direction.length_squared() > 0.001 and target_distance > TARGET_REACHED_DISTANCE
	if visible:
		direction = world_direction.normalized()
	queue_redraw()


func clear() -> void:
	visible = false
	target_label = ""
	target_distance = 0.0
	queue_redraw()


func state_for_tests() -> Dictionary:
	return {
		"visible": visible,
		"target_label": target_label,
		"target_distance": target_distance,
		"direction": direction,
	}


func _draw() -> void:
	if not visible:
		return
	var amber := Color("f2bd55")
	var shadow := Color("061014b8")
	var ring_color := Color("f2bd5538")
	var center := size * 0.5
	draw_arc(center, RING_RADIUS, -PI, PI, 64, ring_color, 2.0, true)
	var tip := center + direction * (RING_RADIUS + ARROW_LENGTH * 0.5)
	var base := center + direction * (RING_RADIUS - ARROW_LENGTH * 0.5)
	var perpendicular := direction.orthogonal() * ARROW_HALF_WIDTH
	var shadow_offset := Vector2(2.0, 3.0)
	draw_colored_polygon(PackedVector2Array([tip + shadow_offset, base + perpendicular + shadow_offset, base - perpendicular + shadow_offset]), shadow)
	draw_colored_polygon(PackedVector2Array([tip, base + perpendicular, base - perpendicular]), amber)
	draw_polyline(PackedVector2Array([base + perpendicular, tip, base - perpendicular]), Color("fff0ba"), 2.0, true)
