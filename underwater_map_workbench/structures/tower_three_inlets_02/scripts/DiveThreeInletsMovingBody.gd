extends AnimatableBody2D

const DIVE_PLAYER_GROUP := &"dive_player"
const TARGET_EPSILON := 0.5
const VISUAL_STYLE_INDUSTRIAL_PANEL := "industrial_panel"
const VISUAL_STYLE_EGRESS_GRILLE := "egress_grille"
const VISUAL_STATE_CLOSED := "CLOSED"
const VISUAL_STATE_MID := "MID"
const VISUAL_STATE_OPEN := "OPEN"
const APERTURE_EPSILON := 0.001

var body_id: String = ""

var _home_local_position := Vector2.ZERO
var _target_local_position := Vector2.ZERO
var _travel_speed := 240.0
var _visual_size := Vector2(80.0, 80.0)
var _safety_margin := 40.0
var _symbol := ""
var _label := ""
var _visual_style := VISUAL_STYLE_INDUSTRIAL_PANEL
var _open_offset := Vector2.ZERO
var _safety_envelope: Area2D


func configure(
	definition: Dictionary,
	socket_rect: Rect2,
	structure_id: String
) -> PackedStringArray:
	var errors := PackedStringArray()
	body_id = str(definition.get("id", ""))
	if body_id.is_empty():
		errors.append("Ruchome ciało nie ma lokalnego ID.")
	if socket_rect.size.x <= 0.0 or socket_rect.size.y <= 0.0:
		errors.append("Ruchome ciało %s ma pusty socket." % body_id)
	_travel_speed = float(definition.get("travel_speed", 0.0))
	if _travel_speed <= 0.0:
		errors.append("Ruchome ciało %s wymaga dodatniego travel_speed." % body_id)
	_safety_margin = float(definition.get("safety_margin", 40.0))
	if _safety_margin < 0.0:
		errors.append("Ruchome ciało %s ma ujemny safety_margin." % body_id)
	_visual_style = str(definition.get("visual_style", VISUAL_STYLE_INDUSTRIAL_PANEL))
	if _visual_style not in [VISUAL_STYLE_INDUSTRIAL_PANEL, VISUAL_STYLE_EGRESS_GRILLE]:
		errors.append("Ruchome ciało %s ma nieobsługiwany visual_style: %s." % [body_id, _visual_style])
	_open_offset = _vector_from_value(definition.get("open_offset", []))
	if _visual_style == VISUAL_STYLE_EGRESS_GRILLE and _open_offset.is_zero_approx():
		errors.append("Ruchome ciało %s używa egress_grille bez niezerowego open_offset." % body_id)
	if not errors.is_empty():
		return errors

	_label = str(definition.get("label", body_id))
	_symbol = str(definition.get("symbol", ""))
	_visual_size = socket_rect.size
	_home_local_position = socket_rect.get_center()
	_target_local_position = _home_local_position
	position = _home_local_position

	collision_layer = 1
	collision_mask = 0
	sync_to_physics = true
	z_index = int(definition.get("z_index", 7))
	set_meta(&"structure_id", structure_id)
	set_meta(&"dynamic_body_id", body_id)
	set_meta(&"socket_id", str(definition.get("socket_id", "")))
	set_meta(&"safety_group_filter", String(DIVE_PLAYER_GROUP))
	set_meta(&"label", _label)
	set_meta(&"symbol", _symbol)
	set_meta(&"visual_style", _visual_style)

	_build_solid_shape()
	_build_safety_envelope()
	queue_redraw()
	return errors


func request_local_target(target: Vector2) -> void:
	_target_local_position = target
	set_meta(&"target_local_position", _target_local_position)


func snap_to_local_position(target: Vector2) -> void:
	var was_synchronized: bool = sync_to_physics
	sync_to_physics = false
	_target_local_position = target
	position = target
	if is_inside_tree():
		force_update_transform()
	sync_to_physics = was_synchronized
	set_meta(&"target_local_position", _target_local_position)
	queue_redraw()


func reset_home() -> void:
	snap_to_local_position(_home_local_position)


func advance_motion(delta: float) -> bool:
	if reached_target():
		position = _target_local_position
		queue_redraw()
		return true
	if not safety_clear():
		return false
	var next_position := position.move_toward(
		_target_local_position,
		_travel_speed * maxf(delta, 0.0)
	)
	if not can_travel_to_local_position_safely(next_position):
		return false
	position = next_position
	queue_redraw()
	if reached_target():
		position = _target_local_position
		queue_redraw()
		return true
	return false


func reached_target() -> bool:
	return position.distance_to(_target_local_position) <= TARGET_EPSILON


func is_moving() -> bool:
	return not reached_target()


func safety_clear() -> bool:
	if _safety_envelope == null:
		return true
	for body: Node2D in _safety_envelope.get_overlapping_bodies():
		if body.is_in_group(DIVE_PLAYER_GROUP):
			return false
	return true


func can_travel_to_local_position_safely(target: Vector2) -> bool:
	var parent_2d := get_parent() as Node2D
	if not is_inside_tree() or get_world_2d() == null or parent_2d == null:
		return false
	var safety_size := _visual_size + Vector2.ONE * _safety_margin * 2.0
	var path_length := position.distance_to(target)
	var sample_step := maxf(minf(safety_size.x, safety_size.y) * 0.25, 1.0)
	var sample_count := maxi(int(ceil(path_length / sample_step)), 1)
	var shape := RectangleShape2D.new()
	shape.size = safety_size
	for sample_index: int in range(sample_count + 1):
		var weight := float(sample_index) / float(sample_count)
		var sample_local_position := position.lerp(target, weight)
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		var query_transform := global_transform
		query_transform.origin = parent_2d.to_global(sample_local_position)
		query.transform = query_transform
		query.collision_mask = 1
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.exclude = [get_rid()]
		for hit_value: Variant in get_world_2d().direct_space_state.intersect_shape(query, 128):
			var hit := hit_value as Dictionary
			var collider := hit.get("collider", null) as Node
			if collider != null and collider.is_in_group(DIVE_PLAYER_GROUP):
				return false
	return true


func can_snap_to_local_position_safely(target: Vector2) -> bool:
	return can_travel_to_local_position_safely(target)


func home_local_position() -> Vector2:
	return _home_local_position


func target_local_position() -> Vector2:
	return _target_local_position


func safety_envelope() -> Area2D:
	return _safety_envelope


func visual_style() -> String:
	return _visual_style


func visual_state() -> String:
	if _visual_style != VISUAL_STYLE_EGRESS_GRILLE:
		return VISUAL_STATE_CLOSED
	if position.distance_to(_home_local_position) <= TARGET_EPSILON:
		return VISUAL_STATE_CLOSED
	var open_position := _home_local_position + _open_offset
	if reached_target() and position.distance_to(open_position) <= TARGET_EPSILON:
		return VISUAL_STATE_OPEN
	return VISUAL_STATE_MID


func open_progress() -> float:
	var travel_length_squared := _open_offset.length_squared()
	if travel_length_squared <= APERTURE_EPSILON:
		return 0.0
	return clampf(
		(position - _home_local_position).dot(_open_offset) / travel_length_squared,
		0.0,
		1.0
	)


func aperture_clear_fraction() -> float:
	if _visual_style != VISUAL_STYLE_EGRESS_GRILLE or _open_offset.is_zero_approx():
		return 0.0
	var direction := _open_offset.normalized()
	var travelled := maxf((position - _home_local_position).dot(direction), 0.0)
	var aperture_span := (
		absf(direction.x) * _visual_size.x
		+ absf(direction.y) * _visual_size.y
	)
	return clampf(travelled / maxf(aperture_span, 1.0), 0.0, 1.0)


func aperture_is_clear() -> bool:
	return (
		_visual_style == VISUAL_STYLE_EGRESS_GRILLE
		and aperture_clear_fraction() >= 1.0 - APERTURE_EPSILON
		and not body_rect_in_parent().intersects(aperture_rect_in_parent())
	)


func aperture_rect_in_parent() -> Rect2:
	return Rect2(_home_local_position - _visual_size * 0.5, _visual_size)


func body_rect_in_parent() -> Rect2:
	return Rect2(position - _visual_size * 0.5, _visual_size)


func _build_solid_shape() -> void:
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = _visual_size
	collision.shape = shape
	add_child(collision)


func _build_safety_envelope() -> void:
	_safety_envelope = Area2D.new()
	_safety_envelope.name = "SafetyEnvelope"
	_safety_envelope.collision_layer = 0
	_safety_envelope.collision_mask = 1
	_safety_envelope.monitoring = true
	_safety_envelope.monitorable = false
	_safety_envelope.set_meta(&"reacts_only_to_group", String(DIVE_PLAYER_GROUP))
	_safety_envelope.set_meta(&"dynamic_body_id", body_id)
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = _visual_size + Vector2.ONE * _safety_margin * 2.0
	collision.shape = shape
	_safety_envelope.add_child(collision)
	add_child(_safety_envelope)


func _draw() -> void:
	if _visual_style == VISUAL_STYLE_EGRESS_GRILLE:
		_draw_egress_portal()
		_draw_egress_grille()
		return
	_draw_industrial_panel()


func _draw_industrial_panel() -> void:
	var half_size := _visual_size * 0.5
	var body_rect := Rect2(-half_size, _visual_size)
	draw_rect(body_rect, Color(0.13, 0.25, 0.28, 0.98), true)
	draw_rect(body_rect, Color(0.64, 0.88, 0.84, 1.0), false, 4.0)
	var stripe_color := Color(0.92, 0.70, 0.20, 0.9)
	var stripe_step := 32.0
	var stripe_x := -half_size.x - half_size.y
	while stripe_x < half_size.x + half_size.y:
		var start := Vector2(stripe_x, half_size.y)
		var finish := Vector2(stripe_x + _visual_size.y, -half_size.y)
		var clipped_start := Vector2(clampf(start.x, -half_size.x, half_size.x), start.y)
		var clipped_finish := Vector2(clampf(finish.x, -half_size.x, half_size.x), finish.y)
		draw_line(clipped_start, clipped_finish, stripe_color, 3.0)
		stripe_x += stripe_step
	if _symbol.contains("→"):
		_draw_arrow(Vector2.ZERO, Vector2.RIGHT, minf(_visual_size.x, _visual_size.y) * 0.28)
	elif _symbol.contains("↓"):
		_draw_arrow(Vector2.ZERO, Vector2.DOWN, minf(_visual_size.x, _visual_size.y) * 0.28)
	elif _symbol == "III":
		_draw_barrier_bars(3)
	elif _symbol == "II":
		_draw_barrier_bars(2)
	elif _symbol == "I":
		_draw_barrier_bars(1)
	elif _symbol.contains("▲"):
		_draw_triangle_symbol()
	elif _symbol.contains("■"):
		_draw_square_symbol()


func _draw_egress_portal() -> void:
	var portal_center := _home_local_position - position
	var half_size := _visual_size * 0.5
	var portal_rect := Rect2(portal_center - half_size, _visual_size)
	var state := visual_state()
	var frame_color := Color(0.96, 0.66, 0.18, 0.98)
	if state == VISUAL_STATE_MID:
		frame_color = Color(0.42, 0.88, 0.90, 0.98)
	elif state == VISUAL_STATE_OPEN:
		frame_color = Color(0.45, 0.96, 0.70, 1.0)

	var outer_rect := portal_rect.grow(7.0)
	draw_rect(outer_rect, Color(0.03, 0.09, 0.11, 0.94), false, 12.0)
	draw_rect(outer_rect, frame_color, false, 4.0)
	var corner_length := minf(_visual_size.x, _visual_size.y) * 0.28
	for corner: Vector2 in [outer_rect.position, Vector2(outer_rect.end.x, outer_rect.position.y), outer_rect.end, Vector2(outer_rect.position.x, outer_rect.end.y)]:
		var horizontal_direction := 1.0 if is_equal_approx(corner.x, outer_rect.position.x) else -1.0
		var vertical_direction := 1.0 if is_equal_approx(corner.y, outer_rect.position.y) else -1.0
		draw_line(corner, corner + Vector2(horizontal_direction * corner_length, 0.0), frame_color, 7.0)
		draw_line(corner, corner + Vector2(0.0, vertical_direction * corner_length), frame_color, 7.0)

	if state == VISUAL_STATE_OPEN:
		var guide_start := Vector2(outer_rect.end.x + 10.0, portal_center.y)
		var guide_end := guide_start + Vector2(48.0, 0.0)
		draw_line(guide_start, guide_end, frame_color, 5.0)
		draw_line(guide_end, guide_end + Vector2(-14.0, -12.0), frame_color, 5.0)
		draw_line(guide_end, guide_end + Vector2(-14.0, 12.0), frame_color, 5.0)


func _draw_egress_grille() -> void:
	var half_size := _visual_size * 0.5
	var body_rect := Rect2(-half_size, _visual_size)
	var state := visual_state()
	var metal_color := Color(0.72, 0.80, 0.78, 1.0)
	var accent_color := Color(0.96, 0.66, 0.18, 1.0)
	if state == VISUAL_STATE_MID:
		accent_color = Color(0.42, 0.88, 0.90, 1.0)
	elif state == VISUAL_STATE_OPEN:
		accent_color = Color(0.45, 0.96, 0.70, 1.0)

	draw_rect(body_rect, Color(0.02, 0.08, 0.10, 0.24), true)
	draw_rect(body_rect, Color(0.02, 0.08, 0.10, 0.98), false, 12.0)
	draw_rect(body_rect.grow(-5.0), accent_color, false, 4.0)
	var bar_spacing := 24.0
	var bar_y := -half_size.y + bar_spacing
	while bar_y < half_size.y:
		draw_line(Vector2(-half_size.x + 8.0, bar_y), Vector2(half_size.x - 8.0, bar_y), metal_color, 5.0)
		bar_y += bar_spacing
	draw_line(Vector2(-half_size.x + 8.0, half_size.y - 8.0), Vector2(half_size.x - 8.0, -half_size.y + 8.0), metal_color, 4.0)
	draw_line(Vector2(-half_size.x + 8.0, -half_size.y + 8.0), Vector2(half_size.x - 8.0, half_size.y - 8.0), metal_color, 4.0)
	if state != VISUAL_STATE_CLOSED:
		_draw_arrow(Vector2.ZERO, Vector2.UP, minf(_visual_size.x, _visual_size.y) * 0.34)


func _draw_arrow(center: Vector2, direction: Vector2, length: float) -> void:
	var color := Color(0.96, 0.98, 0.88, 1.0)
	var start := center - direction * length * 0.5
	var finish := center + direction * length * 0.5
	draw_line(start, finish, color, 7.0)
	var perpendicular := Vector2(-direction.y, direction.x)
	draw_line(finish, finish - direction * length * 0.3 + perpendicular * length * 0.25, color, 7.0)
	draw_line(finish, finish - direction * length * 0.3 - perpendicular * length * 0.25, color, 7.0)


func _draw_barrier_bars(count: int) -> void:
	var color := Color(0.96, 0.98, 0.88, 1.0)
	var height := minf(_visual_size.x, _visual_size.y) * 0.48
	var spacing := 18.0
	var start_x := -spacing * float(count - 1) * 0.5
	for index: int in range(count):
		var x := start_x + spacing * float(index)
		draw_line(Vector2(x, -height * 0.5), Vector2(x, height * 0.5), color, 7.0)


func _draw_triangle_symbol() -> void:
	var color := Color(0.96, 0.98, 0.88, 1.0)
	var radius := minf(_visual_size.x, _visual_size.y) * 0.24
	var points := PackedVector2Array([
		Vector2(0.0, -radius),
		Vector2(radius, radius),
		Vector2(-radius, radius),
		Vector2(0.0, -radius),
	])
	draw_polyline(points, color, 7.0)


func _draw_square_symbol() -> void:
	var color := Color(0.96, 0.98, 0.88, 1.0)
	var radius := minf(_visual_size.x, _visual_size.y) * 0.22
	draw_rect(
		Rect2(Vector2(-radius, -radius), Vector2.ONE * radius * 2.0),
		color,
		false,
		7.0
	)


func _vector_from_value(value: Variant) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2.ZERO
	return Vector2(float((value as Array)[0]), float((value as Array)[1]))
