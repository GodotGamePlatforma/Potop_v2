@tool
class_name DiveCommonLineStoryCableVisual
extends Node2D

## Wspólna, bezkolizyjna prezentacja dalszych odcinków Wspólnej Linii.
## Konkretne prefaby publikują własne ROUTE_POINTS w lokalnym układzie początku
## odcinka; gameplay, kolizja i stan urządzeń pozostają poza tym węzłem.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	queue_redraw()


func _draw() -> void:
	var route := _story_route_points()
	if route.size() < 2:
		return
	# Poczwórna warstwa utrzymuje czytelność przewodu w jasnych dachach,
	# zielonych osiedlach, rdzy R-3 i prawie czarnym Sercu.
	draw_polyline(route, Color("241815"), 20.0, true)
	draw_polyline(route, Color("101d22"), 14.0, true)
	draw_polyline(route, Color("385157"), 8.0, true)
	draw_polyline(route, Color(0.45, 0.76, 0.72, 0.62), 2.4, true)

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


func _story_route_points() -> PackedVector2Array:
	return PackedVector2Array()


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
