class_name SurvivorPortrait
extends Control

const PortraitCatalogScript := preload("res://scripts/ui/PortraitCatalog.gd")
const DESIGN_SIZE := Vector2(104.0, 128.0)
const BACKGROUND_COLOR := Color("0a171c")

var survivor_id: String = ""
var display_name: String = ""
var mirrored_horizontally: bool = false:
	set(value):
		if mirrored_horizontally == value:
			return
		mirrored_horizontally = value
		queue_redraw()

var _resolved_texture: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_resolve_texture()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func configure(new_survivor_id: String, new_display_name: String) -> void:
	if survivor_id == new_survivor_id and display_name == new_display_name:
		return
	survivor_id = new_survivor_id
	display_name = new_display_name
	tooltip_text = new_display_name
	_resolve_texture()
	queue_redraw()


func portrait_texture() -> Texture2D:
	return _resolved_texture


func uses_procedural_fallback() -> bool:
	return _resolved_texture == null


func _resolve_texture() -> void:
	_resolved_texture = PortraitCatalogScript.portrait_texture(survivor_id)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if _resolved_texture != null:
		draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)
		_draw_texture_cover(_resolved_texture)
		return
	_draw_procedural_fallback()


func _draw_texture_cover(texture: Texture2D) -> void:
	var source_size := texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	var scale_factor := maxf(size.x / source_size.x, size.y / source_size.y)
	var draw_size := source_size * scale_factor
	var draw_position := (size - draw_size) * 0.5
	if mirrored_horizontally:
		draw_set_transform(Vector2(size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
	draw_texture_rect(texture, Rect2(draw_position, draw_size), false)


func _draw_procedural_fallback() -> void:
	var draw_origin := Vector2.ZERO
	var draw_scale := Vector2(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	if mirrored_horizontally:
		draw_origin.x = size.x
		draw_scale.x *= -1.0
	draw_set_transform(draw_origin, 0.0, draw_scale)
	var profile := _portrait_profile()
	var accent: Color = profile.accent
	var skin: Color = profile.skin
	var shadow: Color = profile.shadow
	var hair: Color = profile.hair

	draw_rect(Rect2(0, 0, 104, 128), BACKGROUND_COLOR)
	draw_circle(Vector2(52, 58), 57, Color(accent, 0.11))
	for x in range(8, 104, 16):
		draw_line(Vector2(x, 0), Vector2(x - 20, 128), Color(accent, 0.055), 1.0)
	draw_arc(Vector2(52, 59), 49, -2.8, 0.15, 24, Color(accent, 0.28), 1.0)

	if survivor_id == "mira":
		draw_colored_polygon(PackedVector2Array([Vector2(22, 40), Vector2(31, 18), Vector2(70, 18), Vector2(82, 42), Vector2(82, 105), Vector2(66, 116), Vector2(28, 108)]), hair)
	elif survivor_id == "anka":
		draw_colored_polygon(PackedVector2Array([Vector2(25, 43), Vector2(30, 23), Vector2(47, 15), Vector2(73, 22), Vector2(81, 45), Vector2(71, 38), Vector2(62, 29), Vector2(44, 34)]), hair)

	# Ramiona i wysoki kolnierz skafandra tworza rozpoznawalna karte nurka.
	draw_colored_polygon(PackedVector2Array([Vector2(5, 128), Vector2(12, 112), Vector2(35, 101), Vector2(69, 101), Vector2(92, 112), Vector2(99, 128)]), Color("1c3338"))
	draw_colored_polygon(PackedVector2Array([Vector2(18, 128), Vector2(25, 109), Vector2(39, 102), Vector2(52, 116), Vector2(65, 102), Vector2(79, 109), Vector2(86, 128)]), Color("29474b"))
	draw_line(Vector2(13, 119), Vector2(91, 119), Color(accent, 0.55), 2.0)
	draw_rect(Rect2(42, 88, 20, 24), shadow)
	draw_circle(Vector2(27, 62), 7, skin.darkened(0.12))
	draw_circle(Vector2(77, 62), 7, skin.darkened(0.12))

	var face := PackedVector2Array([
		Vector2(29, 46), Vector2(35, 27), Vector2(50, 21), Vector2(68, 27),
		Vector2(76, 46), Vector2(73, 82), Vector2(63, 101), Vector2(51, 108),
		Vector2(40, 101), Vector2(31, 82)
	])
	draw_colored_polygon(face, skin)
	draw_colored_polygon(PackedVector2Array([Vector2(29, 63), Vector2(35, 82), Vector2(44, 101), Vector2(51, 108), Vector2(51, 22), Vector2(36, 27)]), Color(shadow, 0.34))

	if survivor_id == "igor":
		draw_colored_polygon(PackedVector2Array([Vector2(29, 45), Vector2(33, 27), Vector2(48, 17), Vector2(70, 23), Vector2(77, 43), Vector2(66, 36), Vector2(54, 34), Vector2(42, 40)]), hair)
		draw_colored_polygon(PackedVector2Array([Vector2(35, 82), Vector2(72, 82), Vector2(64, 98), Vector2(52, 107), Vector2(40, 98)]), Color(hair, 0.30))
	elif survivor_id == "mira":
		draw_colored_polygon(PackedVector2Array([Vector2(28, 48), Vector2(34, 27), Vector2(49, 18), Vector2(69, 25), Vector2(78, 47), Vector2(67, 35), Vector2(51, 31), Vector2(39, 36)]), hair)
	elif survivor_id == "anka":
		draw_colored_polygon(PackedVector2Array([Vector2(28, 48), Vector2(32, 30), Vector2(47, 18), Vector2(70, 24), Vector2(79, 46), Vector2(65, 34), Vector2(53, 39), Vector2(43, 31)]), hair)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(29, 46), Vector2(35, 25), Vector2(51, 18), Vector2(70, 25), Vector2(77, 46), Vector2(63, 35), Vector2(43, 37)]), hair)

	# Rysy sa celowo wyrazne przy malym rozmiarze HUD-u.
	draw_line(Vector2(36, 56), Vector2(47, 54), hair.darkened(0.22), 2.4)
	draw_line(Vector2(58, 54), Vector2(69, 56), hair.darkened(0.22), 2.4)
	draw_line(Vector2(37, 61), Vector2(47, 61), Color("d7ddd4"), 2.3)
	draw_line(Vector2(58, 61), Vector2(68, 61), Color("d7ddd4"), 2.3)
	draw_circle(Vector2(43, 61), 1.7, Color("142027"))
	draw_circle(Vector2(63, 61), 1.7, Color("142027"))
	draw_line(Vector2(52, 61), Vector2(48, 79), shadow.darkened(0.16), 1.8)
	draw_line(Vector2(48, 79), Vector2(55, 81), shadow.darkened(0.16), 1.5)
	draw_line(Vector2(43, 91), Vector2(61, 90), Color("733e3b"), 2.0)

	if survivor_id == "igor":
		draw_line(Vector2(67, 49), Vector2(62, 57), Color("76564b"), 1.2)
		draw_line(Vector2(66, 51), Vector2(69, 55), Color("76564b"), 1.2)
	elif survivor_id == "mira":
		draw_line(Vector2(37, 65), Vector2(46, 64), Color(accent, 0.65), 1.0)
	elif survivor_id == "anka":
		draw_arc(Vector2(43, 38), 8, PI, TAU, 10, Color("91d4d2"), 2.0)
		draw_arc(Vector2(62, 38), 8, PI, TAU, 10, Color("91d4d2"), 2.0)
		draw_line(Vector2(51, 38), Vector2(54, 38), Color("91d4d2"), 2.0)

	draw_circle(Vector2(52, 119), 4, accent)
	draw_circle(Vector2(52, 119), 1.6, Color("d9f3eb"))


func _portrait_profile() -> Dictionary:
	match survivor_id:
		"mira":
			return {"skin": Color("b97f67"), "shadow": Color("70483f"), "hair": Color("302b31"), "accent": Color("5fc9aa")}
		"anka":
			return {"skin": Color("c89575"), "shadow": Color("775346"), "hair": Color("8b4d31"), "accent": Color("e0b45f")}
		"igor":
			return {"skin": Color("a9765e"), "shadow": Color("61453f"), "hair": Color("263238"), "accent": Color("55c4c9")}
		_:
			var hue := float(abs(survivor_id.hash()) % 1000) / 1000.0
			return {"skin": Color.from_hsv(0.055 + hue * 0.035, 0.35, 0.72), "shadow": Color("654941"), "hair": Color.from_hsv(hue, 0.28, 0.24), "accent": Color.from_hsv(fmod(hue + 0.45, 1.0), 0.48, 0.78)}
