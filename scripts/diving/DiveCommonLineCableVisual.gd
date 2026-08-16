@tool
class_name DiveCommonLineCableVisual
extends Path2D

## Bezkolizyjny, statyczny przewodnik środowiskowy. Punkty są lokalne względem
## głównej liny przy platformie. Jedynym źródłem przebiegu jest Curve2D
## zapisana w prefabie, dzięki czemu trasę edytuje się uchwytami widoku 2D.
const TUTORIAL_ANCHOR_INDICES := [1, 3, 5, 6]

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
	# Matowy osad utrzymuje linię czytelną bez ciężkiej, czarnej obwódki.
	draw_polyline(route, Color("273033"), 16.0, true)
	draw_polyline(route, Color("183036"), 10.5, true)
	draw_polyline(route, Color("36565a"), 5.5, true)
	draw_polyline(route, Color(0.38, 0.64, 0.64, 0.48), 1.6, true)

	var total_length := _route_length()
	var marker_distance := 74.0
	var marker_index := 0
	while marker_distance < total_length - 30.0:
		var sample := _sample_route(marker_distance)
		var point: Vector2 = sample.get("point", Vector2.ZERO)
		var tangent: Vector2 = sample.get("tangent", Vector2.RIGHT)
		var normal := tangent.orthogonal()
		var band_color := Color("b58347") if marker_index % 3 != 1 else Color("76999a")
		draw_line(point - normal * 7.0, point + normal * 7.0, Color("241b18"), 5.0, true)
		draw_line(point - normal * 6.0, point + normal * 6.0, Color(band_color, 0.82), 2.3, true)
		marker_distance += 118.0
		marker_index += 1

	for anchor_index in TUTORIAL_ANCHOR_INDICES:
		if curve == null or anchor_index < 0 or anchor_index >= curve.point_count:
			continue
		var center := curve.get_point_position(anchor_index)
		draw_circle(center, 13.0, Color(0.05, 0.10, 0.11, 0.88))
		draw_arc(center, 13.0, 0.0, TAU, 20, Color(0.69, 0.80, 0.72, 0.76), 3.0, true)
		draw_circle(center, 4.0, Color(0.77, 0.52, 0.28, 0.92))

	# Zakończenia są mechanicznie czytelne: mocowanie platformy i wtyk J-7.
	var start := route[0]
	draw_circle(start, 18.0, Color("18292d"))
	draw_arc(start, 18.0, 0.0, TAU, 24, Color("89b8b4"), 4.0, true)
	var terminal := route[route.size() - 1]
	draw_circle(terminal, 17.0, Color("18292d"))
	draw_arc(terminal, 17.0, 0.0, TAU, 24, Color("d09351"), 4.0, true)


func _route_length() -> float:
	var route := _route_points()
	var total := 0.0
	for index in range(route.size() - 1):
		total += (route[index + 1] - route[index]).length()
	return total


func _sample_route(distance_along: float) -> Dictionary:
	var route := _route_points()
	if route.size() < 2:
		return {"point": Vector2.ZERO, "tangent": Vector2.LEFT}
	var remaining := maxf(distance_along, 0.0)
	for index in range(route.size() - 1):
		var from: Vector2 = route[index]
		var to: Vector2 = route[index + 1]
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
