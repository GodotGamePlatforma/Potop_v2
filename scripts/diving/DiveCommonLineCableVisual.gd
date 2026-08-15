@tool
class_name DiveCommonLineCableVisual
extends Node2D

## Bezkolizyjny, statyczny przewodnik środowiskowy. Punkty są lokalne względem
## głównej liny przy platformie i odpowiadają zatwierdzonej trasie tutoriala.
const ROUTE_POINTS := [
	Vector2(0.0, 0.0),
	Vector2(-509.388, 311.77023),
	Vector2(-2525.388, 191.77023),
	Vector2(-2909.388, 415.77023),
	Vector2(-3245.388, 527.77023),
	Vector2(-3249.388, 551.77023),
	Vector2(-3469.388, 831.77023),
]
const TUTORIAL_ANCHOR_INDICES := [1, 3, 5, 6]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	queue_redraw()


func _draw() -> void:
	var route := PackedVector2Array(ROUTE_POINTS)
	# Osad pod przewodem oddziela go od jasnej liny powrotnej i tła dachów.
	draw_polyline(route, Color("321f1c"), 18.0, true)
	draw_polyline(route, Color("152329"), 12.0, true)
	draw_polyline(route, Color("334b50"), 7.0, true)
	draw_polyline(route, Color(0.42, 0.70, 0.70, 0.58), 2.0, true)

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
		var center: Vector2 = ROUTE_POINTS[anchor_index]
		draw_circle(center, 13.0, Color(0.05, 0.10, 0.11, 0.88))
		draw_arc(center, 13.0, 0.0, TAU, 20, Color(0.69, 0.80, 0.72, 0.76), 3.0, true)
		draw_circle(center, 4.0, Color(0.77, 0.52, 0.28, 0.92))

	# Zakończenia są mechanicznie czytelne: mocowanie platformy i wtyk J-7.
	draw_circle(ROUTE_POINTS[0], 18.0, Color("18292d"))
	draw_arc(ROUTE_POINTS[0], 18.0, 0.0, TAU, 24, Color("89b8b4"), 4.0, true)
	var terminal: Vector2 = ROUTE_POINTS[ROUTE_POINTS.size() - 1]
	draw_circle(terminal, 17.0, Color("18292d"))
	draw_arc(terminal, 17.0, 0.0, TAU, 24, Color("d09351"), 4.0, true)


func _route_length() -> float:
	var total := 0.0
	for index in range(ROUTE_POINTS.size() - 1):
		total += (ROUTE_POINTS[index + 1] - ROUTE_POINTS[index]).length()
	return total


func _sample_route(distance_along: float) -> Dictionary:
	var remaining := maxf(distance_along, 0.0)
	for index in range(ROUTE_POINTS.size() - 1):
		var from: Vector2 = ROUTE_POINTS[index]
		var to: Vector2 = ROUTE_POINTS[index + 1]
		var delta := to - from
		var segment_length := delta.length()
		if remaining <= segment_length or index == ROUTE_POINTS.size() - 2:
			var tangent := delta / maxf(segment_length, 0.001)
			return {
				"point": from + tangent * minf(remaining, segment_length),
				"tangent": tangent,
			}
		remaining -= segment_length
	return {"point": ROUTE_POINTS[ROUTE_POINTS.size() - 1], "tangent": Vector2.LEFT}
