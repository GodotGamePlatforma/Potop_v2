class_name TutorialDirectionIndicator
extends Control

const RING_RADIUS := 72.0
const ARROW_LENGTH := 20.0
const ARROW_HALF_WIDTH := 9.0
const TARGET_REACHED_DISTANCE := 36.0
const INDICATOR_SIZE := Vector2(220.0, 220.0)
const RING_COLOR := Color("f2bd5518")
const RING_WIDTH := 1.0
const SHADOW_COLOR := Color("06101470")
const SHADOW_OFFSET := Vector2(1.0, 2.0)
const OUTLINE_WIDTH := 1.0

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
		"ring_radius": RING_RADIUS,
		"arrow_length": ARROW_LENGTH,
		"arrow_half_width": ARROW_HALF_WIDTH,
		"target_reached_distance": TARGET_REACHED_DISTANCE,
		"indicator_size": INDICATOR_SIZE,
		"ring_color": RING_COLOR,
		"ring_width": RING_WIDTH,
		"shadow_color": SHADOW_COLOR,
		"shadow_offset": SHADOW_OFFSET,
		"outline_width": OUTLINE_WIDTH,
	}


func _draw() -> void:
	if not visible:
		return
	var amber := Color("f2bd55")
	var center := size * 0.5
	draw_arc(center, RING_RADIUS, -PI, PI, 64, RING_COLOR, RING_WIDTH, true)
	var tip := center + direction * (RING_RADIUS + ARROW_LENGTH * 0.5)
	var base := center + direction * (RING_RADIUS - ARROW_LENGTH * 0.5)
	var perpendicular := direction.orthogonal() * ARROW_HALF_WIDTH
	draw_colored_polygon(PackedVector2Array([tip + SHADOW_OFFSET, base + perpendicular + SHADOW_OFFSET, base - perpendicular + SHADOW_OFFSET]), SHADOW_COLOR)
	draw_colored_polygon(PackedVector2Array([tip, base + perpendicular, base - perpendicular]), amber)
	draw_polyline(PackedVector2Array([base + perpendicular, tip, base - perpendicular]), Color("fff0ba"), OUTLINE_WIDTH, true)
