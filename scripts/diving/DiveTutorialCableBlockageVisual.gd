@tool
class_name DiveTutorialCableBlockageVisual
extends Node2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	queue_redraw()


func _draw() -> void:
	# Zbita sieć i roślinność oplatają kabel, ale nie przejmują kolizji gameplayu.
	draw_line(Vector2(-94, 8), Vector2(94, -8), Color("241b18"), 18.0, true)
	draw_line(Vector2(-94, 8), Vector2(94, -8), Color("31474b"), 10.0, true)
	draw_line(Vector2(-94, 8), Vector2(94, -8), Color(0.47, 0.71, 0.68, 0.48), 2.0, true)

	var mesh_color := Color(0.42, 0.49, 0.39, 0.78)
	var mesh_shadow := Color(0.08, 0.12, 0.11, 0.86)
	for y in range(-42, 43, 14):
		draw_line(Vector2(-88, y), Vector2(88, y + 16), mesh_shadow, 4.0, true)
		draw_line(Vector2(-88, y), Vector2(88, y + 16), mesh_color, 1.6, true)
	for x in range(-84, 85, 18):
		draw_line(Vector2(x, -45), Vector2(x + 24, 47), mesh_shadow, 4.0, true)
		draw_line(Vector2(x, -45), Vector2(x + 24, 47), mesh_color, 1.5, true)

	var plant_color := Color(0.24, 0.45, 0.31, 0.92)
	var plant_edge := Color(0.49, 0.68, 0.38, 0.72)
	for base_x in [-76.0, -44.0, 39.0, 72.0]:
		var stem := PackedVector2Array([
			Vector2(base_x, 47),
			Vector2(base_x - 8, 24),
			Vector2(base_x + 7, 5),
			Vector2(base_x - 3, -25),
		])
		draw_polyline(stem, Color("14251c"), 7.0, true)
		draw_polyline(stem, plant_color, 3.0, true)
		draw_line(stem[1], stem[1] + Vector2(-15, -7), plant_edge, 4.0, true)
		draw_line(stem[2], stem[2] + Vector2(14, -9), plant_edge, 4.0, true)

	# Ciepła taśma serwisowa skupia wzrok na miejscu użycia noża.
	for offset in [-11.0, 11.0]:
		draw_line(Vector2(offset - 2, -18), Vector2(offset + 2, 18), Color("2b2018"), 7.0, true)
		draw_line(Vector2(offset - 2, -17), Vector2(offset + 2, 17), Color("c48a49"), 3.0, true)
	draw_arc(Vector2.ZERO, 27.0, -0.85, 0.85, 12, Color(0.86, 0.67, 0.36, 0.84), 3.0, true)
