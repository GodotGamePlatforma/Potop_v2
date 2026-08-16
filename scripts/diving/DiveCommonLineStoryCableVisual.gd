@tool
class_name DiveCommonLineStoryCableVisual
extends Path2D

## Wspólna, bezkolizyjna prezentacja dalszych odcinków Wspólnej Linii.
## Każdy prefab przechowuje własną Curve2D w lokalnym układzie początku
## odcinka; gameplay, kolizja i stan urządzeń pozostają poza tym węzłem.

var _connected_curve: Curve2D


func _enter_tree() -> void:
	_sync_curve_signal()
	set_process(Engine.is_editor_hint())


func _ready() -> void:
	_sync_curve_signal()
	queue_redraw()


func _exit_tree() -> void:
	_disconnect_curve_signal()


func _process(_delta: float) -> void:
	_sync_curve_signal()


func _draw() -> void:
	# The dummy headless renderer cannot allocate the antialias helper texture
	# used by wide polylines. Route data is still testable without rasterizing it.
	if DisplayServer.get_name() == "headless":
		return
	var route := _route_points()
	if route.size() < 2:
		return
	# Poczwórna warstwa zachowuje prowadzenie w każdym regionie, ale miękko
	# osadza przewód w wodzie zamiast rysować ciężką, czarną obwódkę.
	draw_polyline(route, Color("263034"), 17.0, true)
	draw_polyline(route, Color("162c32"), 12.0, true)
	draw_polyline(route, Color("36565a"), 6.5, true)
	draw_polyline(route, Color(0.40, 0.68, 0.64, 0.52), 1.8, true)

	var total_length := _route_length(route)
	var marker_distance := 92.0
	var marker_index := 0
	while marker_distance < total_length - 46.0:
		var sample := _sample_route(route, marker_distance)
		var point: Vector2 = sample.get("point", Vector2.ZERO)
		var tangent: Vector2 = sample.get("tangent", Vector2.RIGHT)
		var normal := tangent.orthogonal()
		var service_color := Color("c28a4f") if marker_index % 4 != 2 else Color("7aa6a2")
		draw_line(point - normal * 8.0, point + normal * 8.0, Color("211714"), 6.0, true)
		draw_line(point - normal * 7.0, point + normal * 7.0, Color(service_color, 0.88), 2.6, true)
		# Mały grot prowadzi wzrok zgodnie z kolejnością fabuły również bez HUD-u.
		if marker_index % 3 == 0:
			var tip := point + tangent * 14.0
			draw_line(tip, point - tangent * 2.0 + normal * 6.0, Color(0.78, 0.62, 0.36, 0.72), 2.2, true)
			draw_line(tip, point - tangent * 2.0 - normal * 6.0, Color(0.78, 0.62, 0.36, 0.72), 2.2, true)
		marker_distance += 132.0
		marker_index += 1

	_draw_connector(route[0], Color("81aaa7"))
	_draw_connector(route[route.size() - 1], Color("d19655"))


func authored_route_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	if curve == null:
		return points
	for point_index in range(curve.point_count):
		points.append(curve.get_point_position(point_index))
	return points


func _route_points() -> PackedVector2Array:
	if curve == null:
		return PackedVector2Array()
	var baked := curve.get_baked_points()
	if baked.size() >= 2:
		return baked
	return authored_route_points()


func _draw_connector(center: Vector2, rim_color: Color) -> void:
	draw_circle(center, 19.0, Color("132329"))
	draw_arc(center, 19.0, 0.0, TAU, 24, Color("251b17"), 7.0, true)
	draw_arc(center, 19.0, 0.0, TAU, 24, rim_color, 3.2, true)
	draw_circle(center, 5.0, Color(0.72, 0.88, 0.82, 0.72))


func _route_length(route: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(route.size() - 1):
		total += route[index].distance_to(route[index + 1])
	return total


func _sample_route(route: PackedVector2Array, distance_along: float) -> Dictionary:
	var remaining := maxf(distance_along, 0.0)
	for index in range(route.size() - 1):
		var from := route[index]
		var to := route[index + 1]
		var delta := to - from
		var segment_length := delta.length()
		if remaining <= segment_length or index == route.size() - 2:
			var tangent := delta / maxf(segment_length, 0.001)
			return {
				"point": from + tangent * minf(remaining, segment_length),
				"tangent": tangent,
			}
		remaining -= segment_length
	return {"point": route[route.size() - 1], "tangent": Vector2.LEFT}


func _sync_curve_signal() -> void:
	if _connected_curve == curve:
		return
	_disconnect_curve_signal()
	_connected_curve = curve
	if _connected_curve != null and not _connected_curve.changed.is_connected(_on_curve_changed):
		_connected_curve.changed.connect(_on_curve_changed)
	queue_redraw()


func _disconnect_curve_signal() -> void:
	if _connected_curve != null and _connected_curve.changed.is_connected(_on_curve_changed):
		_connected_curve.changed.disconnect(_on_curve_changed)
	_connected_curve = null


func _on_curve_changed() -> void:
	queue_redraw()
