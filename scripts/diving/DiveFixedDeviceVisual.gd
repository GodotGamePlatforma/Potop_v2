@tool
class_name DiveFixedDeviceVisual
extends Node2D

@export_enum("junction", "archive", "diagnostic", "generator", "switchboard", "splitter") var device_kind := "junction":
	set(value):
		device_kind = value
		queue_redraw()

@export_enum("R1", "R2", "R3", "R4") var region_id := "R1":
	set(value):
		region_id = value
		queue_redraw()


func _draw() -> void:
	var colors := _palette()
	_draw_settled_shadow(colors)
	match device_kind:
		"archive":
			_draw_archive_terminal(colors)
		"diagnostic":
			_draw_diagnostic_panel(colors)
		"generator":
			_draw_rust_generator(colors)
		"switchboard":
			_draw_switchboard(colors)
		"splitter":
			_draw_splitter_mount(colors)
		_:
			_draw_junction(colors)
	_draw_region_wear(colors)


func _palette() -> Dictionary:
	match region_id.to_upper():
		"R2":
			return {"dark": Color("17211b"), "body": Color("475849"), "mid": Color("708064"), "edge": Color("91b27a"), "accent": Color("76c969"), "wear": Color("60743d")}
		"R3":
			return {"dark": Color("241715"), "body": Color("5b4436"), "mid": Color("8a6848"), "edge": Color("c0925e"), "accent": Color("df873d"), "wear": Color("9c4c2f")}
		"R4":
			return {"dark": Color("081017"), "body": Color("263542"), "mid": Color("41586a"), "edge": Color("6f8fa4"), "accent": Color("6096e7"), "wear": Color("172a34")}
		_:
			return {"dark": Color("10242a"), "body": Color("365967"), "mid": Color("5e8790"), "edge": Color("91c3c4"), "accent": Color("67c7d6"), "wear": Color("536e68")}


func _draw_settled_shadow(colors: Dictionary) -> void:
	draw_arc(Vector2(3, 44), 48, PI * 0.17, PI * 0.80, 15, Color(colors.dark, 0.48), 7.0, true)
	draw_line(Vector2(-39, 45), Vector2(31, 43), Color(colors.wear, 0.42), 2.5, true)


func _draw_junction(colors: Dictionary) -> void:
	# Pionowa puszka przyłączeniowa z dwoma starymi kablami i mechaniczną dźwignią.
	draw_line(Vector2(-23, 45), Vector2(-20, -43), colors.dark, 10.0, true)
	draw_line(Vector2(25, 45), Vector2(22, -41), colors.dark, 8.0, true)
	draw_rect(Rect2(-34, -42, 68, 80), colors.dark, true)
	draw_polygon(PackedVector2Array([Vector2(-29, -37), Vector2(28, -32), Vector2(29, 31), Vector2(-28, 35)]), PackedColorArray([colors.body]))
	draw_rect(Rect2(-22, -25, 44, 39), colors.mid, true)
	draw_line(Vector2(-17, -18), Vector2(17, -18), colors.edge, 2.0, true)
	for x in [-13.0, 0.0, 13.0]:
		draw_circle(Vector2(x, -7), 4.5, colors.dark)
		draw_circle(Vector2(x, -7), 2.3, colors.accent)
	draw_line(Vector2(14, 17), Vector2(24, 32), colors.dark, 6.0, true)
	draw_circle(Vector2(24, 32), 5.0, colors.edge)


func _draw_archive_terminal(colors: Dictionary) -> void:
	# Szeroki terminal o niskiej sylwetce; dwa zamknięte czytniki i zimny ekran.
	draw_polygon(PackedVector2Array([Vector2(-62, 22), Vector2(-55, -30), Vector2(52, -34), Vector2(61, 23), Vector2(48, 39), Vector2(-51, 39)]), PackedColorArray([colors.dark]))
	draw_polygon(PackedVector2Array([Vector2(-51, 17), Vector2(-46, -23), Vector2(45, -27), Vector2(51, 18)]), PackedColorArray([colors.body]))
	draw_rect(Rect2(-34, -17, 56, 24), colors.mid, true)
	draw_rect(Rect2(-29, -13, 46, 15), Color(colors.accent, 0.72), true)
	draw_line(Vector2(-25, -6), Vector2(12, -6), colors.edge, 2.0, true)
	for center in [Vector2(34, -9), Vector2(35, 9)]:
		draw_circle(center, 8.0, colors.dark)
		draw_circle(center, 4.5, colors.edge)
	draw_line(Vector2(-41, 30), Vector2(43, 30), colors.edge, 3.0, true)


func _draw_diagnostic_panel(colors: Dictionary) -> void:
	# Otwarta kaseta serwisowa z wykresem i trzema portami diagnostycznymi.
	draw_polygon(PackedVector2Array([Vector2(-49, -39), Vector2(48, -35), Vector2(43, 38), Vector2(-45, 42)]), PackedColorArray([colors.dark]))
	draw_rect(Rect2(-39, -30, 77, 60), colors.body, true)
	draw_rect(Rect2(-30, -21, 43, 24), Color(colors.mid, 0.95), true)
	draw_polyline(PackedVector2Array([Vector2(-26, -8), Vector2(-17, -13), Vector2(-8, -5), Vector2(0, -17), Vector2(9, -7)]), colors.accent, 2.5, true)
	for index in range(3):
		var center := Vector2(-24 + index * 22, 18)
		draw_circle(center, 7.0, colors.dark)
		draw_circle(center, 3.2, colors.edge)
	draw_line(Vector2(39, -26), Vector2(55, -41), colors.edge, 4.0, true)
	draw_line(Vector2(39, 27), Vector2(56, 40), colors.edge, 4.0, true)


func _draw_rust_generator(colors: Dictionary) -> void:
	# Ciężki agregat R-3: szeroki korpus, żebra, koło zamachowe i wydech.
	draw_polygon(PackedVector2Array([Vector2(-63, 18), Vector2(-53, -29), Vector2(32, -32), Vector2(57, -14), Vector2(61, 30), Vector2(-54, 36)]), PackedColorArray([colors.dark]))
	draw_rect(Rect2(-48, -22, 69, 45), colors.body, true)
	for x in [-38.0, -26.0, -14.0, -2.0, 10.0]:
		draw_line(Vector2(x, -18), Vector2(x, 18), colors.mid, 5.0, true)
	draw_circle(Vector2(35, 4), 23.0, colors.dark)
	draw_circle(Vector2(35, 4), 15.0, colors.mid)
	draw_circle(Vector2(35, 4), 5.0, colors.accent)
	draw_line(Vector2(-39, -24), Vector2(-43, -43), colors.edge, 7.0, true)
	draw_line(Vector2(-43, -43), Vector2(-31, -47), colors.dark, 6.0, true)
	draw_line(Vector2(-54, 34), Vector2(54, 34), colors.edge, 4.0, true)


func _draw_switchboard(colors: Dictionary) -> void:
	# Rozdzielnia C-4 jest masywna i niemal czarna; dwa pola pozostają czytelne w latarce.
	draw_polygon(PackedVector2Array([Vector2(-60, -46), Vector2(56, -43), Vector2(62, 45), Vector2(-57, 48)]), PackedColorArray([colors.dark]))
	draw_rect(Rect2(-50, -37, 96, 75), colors.body, true)
	draw_line(Vector2(0, -35), Vector2(0, 36), colors.edge, 3.0, true)
	for side in [-1.0, 1.0]:
		var base_x: float = side * 25.0
		draw_rect(Rect2(base_x - 15, -27, 30, 18), colors.mid, true)
		for index in range(3):
			draw_circle(Vector2(base_x - 9 + index * 9, 8), 3.0, colors.dark)
			draw_circle(Vector2(base_x - 9 + index * 9, 8), 1.5, colors.accent)
		draw_line(Vector2(base_x - 11, 22), Vector2(base_x + 11, 22), colors.edge, 3.0, true)
	draw_line(Vector2(-43, 40), Vector2(44, 40), colors.wear, 5.0, true)


func _draw_splitter_mount(colors: Dictionary) -> void:
	# Osprzęt nakłada się na rozdzielnię: otwarte gniazdo oraz trzy rozgałęzienia.
	draw_circle(Vector2.ZERO, 33.0, Color(colors.dark, 0.92))
	draw_arc(Vector2.ZERO, 31.0, -PI * 0.82, PI * 0.82, 30, colors.edge, 6.0, true)
	draw_circle(Vector2.ZERO, 18.0, colors.body)
	draw_circle(Vector2.ZERO, 10.0, colors.dark)
	for angle in [-PI * 0.72, 0.0, PI * 0.72]:
		var inner := Vector2.from_angle(angle) * 29.0
		var outer := Vector2.from_angle(angle) * 53.0
		draw_line(inner, outer, colors.dark, 8.0, true)
		draw_line(inner, outer, colors.accent, 2.2, true)
		draw_circle(outer, 6.0, colors.edge)


func _draw_region_wear(colors: Dictionary) -> void:
	var wear: Color = colors.wear
	var edge: Color = colors.edge
	# Niejednorodne przetarcia i osad łamią zbyt czysty, wektorowy kontur prefabów.
	draw_line(Vector2(-44, -33), Vector2(-31, -29), Color(edge, 0.34), 2.0, true)
	draw_line(Vector2(18, 35), Vector2(38, 31), Color(wear, 0.58), 3.0, true)
	draw_line(Vector2(-31, 27), Vector2(-9, 33), Color(wear, 0.38), 5.0, true)
	for point in [Vector2(-47, 10), Vector2(-17, -36), Vector2(29, 29), Vector2(46, -13)]:
		draw_circle(point, 2.2, Color(wear, 0.48))
	match region_id.to_upper():
		"R3":
			for point in [Vector2(-37, -28), Vector2(-19, 31), Vector2(11, -25), Vector2(43, 27)]:
				draw_circle(point, 4.0, Color(wear, 0.72))
			draw_line(Vector2(-46, 17), Vector2(-20, 24), Color(wear, 0.75), 4.0, true)
		"R4":
			draw_line(Vector2(-49, 37), Vector2(47, 37), Color(wear, 0.82), 8.0, true)
			draw_line(Vector2(-41, 30), Vector2(-20, 20), Color(colors.accent, 0.33), 2.0, true)
		"R2":
			draw_polyline(PackedVector2Array([Vector2(-41, -28), Vector2(-35, -13), Vector2(-39, 2), Vector2(-31, 19), Vector2(-35, 34)]), Color(wear, 0.72), 3.5, true)
		_:
			draw_line(Vector2(-43, 35), Vector2(39, 35), Color(wear, 0.62), 4.0, true)
