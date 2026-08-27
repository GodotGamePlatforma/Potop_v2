extends AnimatableBody2D

const DIVE_PLAYER_GROUP := &"dive_player"
const TARGET_EPSILON := 0.5

var body_id: String = ""

var _home_local_position := Vector2.ZERO
var _target_local_position := Vector2.ZERO
var _travel_speed := 240.0
var _visual_size := Vector2(80.0, 80.0)
var _safety_margin := 40.0
var _symbol := ""
var _label := ""
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


func reset_home() -> void:
	snap_to_local_position(_home_local_position)


func advance_motion(delta: float) -> bool:
	if reached_target():
		position = _target_local_position
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
	if reached_target():
		position = _target_local_position
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
	elif _symbol.contains("WYJ"):
		_draw_arrow(Vector2.ZERO, Vector2.RIGHT, minf(_visual_size.x, _visual_size.y) * 0.28)


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
