extends Area2D

const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")

@export var control_id: String = ""
@export var display_name: String = "Sterowanie wieżowca"
@export var interaction_seconds := 0.8
@export var required_tool: String = ""
@export var interaction_action: String = "activate"

var _activation_callback := Callable()
var _available := false
var _focused := false
var _progress := 0.0
var _interaction_extent := Vector2(80.0, 64.0)
var _visual_size := Vector2(80.0, 64.0)
var _signature := "?"
var _shape_kind: StringName = &"diamond"


func configure(
	definition: Dictionary,
	socket_rect: Rect2,
	activation_callback: Callable
) -> void:
	control_id = str(definition.get("id", ""))
	display_name = str(definition.get("display_name", control_id))
	interaction_seconds = maxf(float(definition.get("interaction_seconds", 0.8)), 0.1)
	required_tool = str(definition.get("required_tool", ""))
	interaction_action = str(definition.get("interaction_action", "activate"))
	_signature = str(definition.get("symbol", "?"))
	_shape_kind = _shape_from_signature(_signature)
	_activation_callback = activation_callback
	position = socket_rect.get_center()
	_interaction_extent = socket_rect.size
	_visual_size = Vector2(
		clampf(socket_rect.size.x, 72.0, 168.0),
		clampf(socket_rect.size.y, 56.0, 104.0)
	)
	set_meta(&"structure_control_id", control_id)
	set_meta(&"socket_id", str(definition.get("socket_id", "")))
	set_meta(&"socket_rect", socket_rect)
	set_meta(&"affordance_label", display_name)
	set_meta(&"affordance_symbol", _signature)
	set_meta(&"affordance_signature", _signature)
	set_meta(&"affordance_shape", String(_shape_kind))
	set_meta(&"affordance_redundancy", "display_name+symbol+shape")
	if is_inside_tree():
		_build_interaction_shape()
	queue_redraw()


func _ready() -> void:
	add_to_group(&"dive_interactable")
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	monitorable = true
	_build_interaction_shape()
	queue_redraw()


func set_available(available: bool) -> void:
	if _available == available:
		return
	_available = available
	if not _available:
		_focused = false
		_progress = 0.0
	queue_redraw()


func can_interact() -> bool:
	return _available and _activation_callback.is_valid()


func interaction_distance_to(world_position: Vector2) -> float:
	var local_delta := to_local(world_position)
	var half_extent := _interaction_extent * 0.5
	var outside := Vector2(
		maxf(absf(local_delta.x) - half_extent.x, 0.0),
		maxf(absf(local_delta.y) - half_extent.y, 0.0)
	)
	return outside.length()


func interaction_text() -> String:
	return "Przytrzymaj %s: %s [%s]" % [
		InputPromptScript.action_text(&"dive_interact"),
		display_name.to_lower(),
		_signature,
	]


func required_tool_display_name() -> String:
	return required_tool.replace("_", " ")


func set_interaction_presentation(focused: bool, progress: float) -> void:
	_focused = focused and _available
	_progress = clampf(progress, 0.0, 1.0) if _focused else 0.0
	queue_redraw()


func complete_dive_interaction() -> Dictionary:
	if not can_interact():
		return {
			"success": false,
			"message": "To sterowanie nie jest teraz dostępne.",
			"interaction_action": interaction_action,
			"control_id": control_id,
		}
	var callback_result: Variant = _activation_callback.call(control_id)
	var result: Dictionary = callback_result as Dictionary if callback_result is Dictionary else {}
	result["success"] = bool(result.get("success", false))
	result["message"] = str(result.get("message", "Sterowanie nie odpowiedziało."))
	result["interaction_action"] = str(result.get("interaction_action", interaction_action))
	result["control_id"] = control_id
	return result


func signature() -> String:
	return _signature


func shape_kind() -> StringName:
	return _shape_kind


func _build_interaction_shape() -> void:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		collision = CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		add_child(collision)
	var shape := RectangleShape2D.new()
	shape.size = _interaction_extent
	collision.shape = shape


func _shape_from_signature(value: String) -> StringName:
	if value.contains("≡"):
		return &"status_lines"
	if value.contains("•"):
		return &"circle"
	if value.contains("▲"):
		return &"triangle"
	if value.contains("■"):
		return &"square"
	if value.contains("→"):
		return &"arrow_right"
	if value.contains("↓"):
		return &"arrow_down"
	if value.contains("↺"):
		return &"reset_arc"
	return &"diamond"


func _draw() -> void:
	var half_size := _visual_size * 0.5
	var panel_rect := Rect2(-half_size, _visual_size)
	var base_color := Color(0.08, 0.17, 0.20, 0.96)
	var outline_color := Color(0.40, 0.63, 0.65, 1.0)
	if _available:
		base_color = Color(0.09, 0.30, 0.29, 0.98)
		outline_color = Color(0.56, 0.96, 0.82, 1.0)
	if _focused:
		base_color = base_color.lightened(0.18)
	draw_rect(panel_rect, base_color, true)
	draw_rect(panel_rect, outline_color, false, 4.0)
	_draw_shape(outline_color)
	if _focused and _progress > 0.0:
		var progress_rect := Rect2(
			Vector2(-half_size.x, half_size.y - 7.0),
			Vector2(_visual_size.x * _progress, 7.0)
		)
		draw_rect(progress_rect, Color(0.96, 0.74, 0.24, 1.0), true)


func _draw_shape(color: Color) -> void:
	var radius := minf(_visual_size.x, _visual_size.y) * 0.25
	match _shape_kind:
		&"status_lines":
			for line_index: int in range(3):
				var y := -radius * 0.65 + float(line_index) * radius * 0.65
				draw_line(Vector2(-radius, y), Vector2(radius, y), color, 5.0)
		&"circle":
			draw_circle(Vector2.ZERO, radius, color, false, 6.0)
		&"triangle":
			var points := PackedVector2Array([
				Vector2(0.0, -radius),
				Vector2(radius, radius),
				Vector2(-radius, radius),
				Vector2(0.0, -radius),
			])
			draw_polyline(points, color, 6.0)
		&"square":
			draw_rect(Rect2(Vector2(-radius, -radius), Vector2.ONE * radius * 2.0), color, false, 6.0)
		&"arrow_right":
			_draw_arrow(Vector2.RIGHT, radius, color)
		&"arrow_down":
			_draw_arrow(Vector2.DOWN, radius, color)
		&"reset_arc":
			draw_arc(Vector2.ZERO, radius, -PI * 0.25, PI * 1.5, 24, color, 6.0)
			var tip := Vector2.from_angle(-PI * 0.25) * radius
			draw_line(tip, tip + Vector2(-radius * 0.35, -radius * 0.05), color, 6.0)
			draw_line(tip, tip + Vector2(-radius * 0.05, radius * 0.35), color, 6.0)
		_:
			var diamond := PackedVector2Array([
				Vector2(0.0, -radius),
				Vector2(radius, 0.0),
				Vector2(0.0, radius),
				Vector2(-radius, 0.0),
				Vector2(0.0, -radius),
			])
			draw_polyline(diamond, color, 6.0)


func _draw_arrow(direction: Vector2, radius: float, color: Color) -> void:
	var start := -direction * radius
	var finish := direction * radius
	var perpendicular := Vector2(-direction.y, direction.x)
	draw_line(start, finish, color, 6.0)
	draw_line(finish, finish - direction * radius * 0.55 + perpendicular * radius * 0.45, color, 6.0)
	draw_line(finish, finish - direction * radius * 0.55 - perpendicular * radius * 0.45, color, 6.0)
