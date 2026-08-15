class_name DiveInteractableVisualStyle
extends RefCounted

const REGION_SKIN_SHADER: Shader = preload("res://assets/diving/interactables/interactable_region_skin.gdshader")
const VALID_QUALITIES := ["low", "medium", "high"]


static func resolve_region(explicit_hint: String, visual_context: Dictionary, stable_id: String) -> String:
	var hinted_region := _normalize_region(explicit_hint)
	if not hinted_region.is_empty():
		return hinted_region

	var id_region := _region_from_stable_id(stable_id)
	if not id_region.is_empty():
		return id_region

	return _normalize_region(str(visual_context.get("region_id", "")))


static func palette(region_id: String) -> Dictionary:
	match _normalize_region(region_id):
		"R1":
			return _make_palette(
				"R1",
				Color("a8cad0"), Color("78979a"), Color("69cad2"), Color("b9edf0"),
				Color("091d24"), Color("5f797c"), Color("142b31"), Color("35535a"), Color("88a7a8"),
				1.0, 0.12, 0.21
			)
		"R2":
			return _make_palette(
				"R2",
				Color("9dad80"), Color("617943"), Color("a9bf5f"), Color("d3dda0"),
				Color("101c18"), Color("596343"), Color("18271f"), Color("3c5037"), Color("83936b"),
				2.0, 0.16, 0.28
			)
		"R3":
			return _make_palette(
				"R3",
				Color("c49a72"), Color("9d4f2f"), Color("d99851"), Color("f0c588"),
				Color("21140f"), Color("76513a"), Color("2d1b16"), Color("68402d"), Color("bd8863"),
				3.0, 0.18, 0.32
			)
		"R4":
			return _make_palette(
				"R4",
				Color("758a98"), Color("27353b"), Color("66a9bb"), Color("a1d7df"),
				Color("050a0d"), Color("29363a"), Color("0a1115"), Color("20323a"), Color("607b84"),
				4.0, 0.22, 0.34
			)
		_:
			return _make_palette(
				"", Color("a5b3b4"), Color("657477"), Color("76adb2"), Color("b4d7d9"),
				Color("0b171b"), Color("566568"), Color("16262a"), Color("3d5054"), Color("839497"),
				0.0, 0.10, 0.18
			)


static func apply_sprite(
	sprite: Sprite2D,
	region_id: String,
	stable_id: String,
	quality: String,
	state_strength: float = 1.0
) -> void:
	if sprite == null:
		return
	var colors := palette(region_id)
	var skin_material := sprite.material as ShaderMaterial
	if skin_material != null and skin_material.shader != REGION_SKIN_SHADER:
		# Nie nadpisuj specjalistycznego materiału prefabu; wspólne łuki i osad
		# nadal zapewnią regionalną spójność bez utraty autorskiego efektu.
		return
	if skin_material == null:
		skin_material = ShaderMaterial.new()
		skin_material.shader = REGION_SKIN_SHADER
		sprite.material = skin_material

	skin_material.set_shader_parameter("region_tint", colors["tint"])
	skin_material.set_shader_parameter("patina_color", colors["patina"])
	skin_material.set_shader_parameter("rim_color", colors["rim"])
	skin_material.set_shader_parameter("patina_mode", colors["patina_mode"])
	skin_material.set_shader_parameter("tint_strength", colors["tint_strength"])
	skin_material.set_shader_parameter("patina_strength", colors["patina_strength"])
	skin_material.set_shader_parameter("detail_level", float(quality_level(quality)))
	skin_material.set_shader_parameter("stable_seed", _stable_seed(stable_id))
	skin_material.set_shader_parameter("state_strength", clampf(state_strength, 0.0, 1.0))


static func draw_grounding(
	canvas: CanvasItem,
	radius: float,
	region_id: String,
	stable_id: String,
	quality: String,
	completed: bool = false
) -> void:
	if canvas == null or radius <= 0.0:
		return
	var colors := palette(region_id)
	var level := quality_level(quality)
	var seed := _stable_seed(stable_id)
	var grounded_color: Color = colors["shadow"]
	grounded_color.a = 0.38 if not completed else 0.24
	var silt_color: Color = colors["silt"]
	silt_color.a = 0.32 if not completed else 0.20

	var base_y := radius * 0.50
	var half_width := radius * (0.72 + seed * 0.12)
	var bed_points := PackedVector2Array()
	var point_count := 8 + level * 3
	for point_index in range(point_count + 1):
		var ratio := float(point_index) / float(point_count)
		var x := lerpf(-half_width, half_width, ratio)
		var bowl := sin(ratio * PI) * radius * 0.13
		bed_points.append(Vector2(x, base_y + bowl))
	canvas.draw_polyline(bed_points, grounded_color, 3.0 if level == 0 else 4.0, true)

	var deposit_count := 1 + level
	for deposit_index in range(deposit_count):
		var offset_seed := fmod(seed * 7.31 + float(deposit_index) * 0.37, 1.0)
		var start_x := lerpf(-half_width * 0.74, half_width * 0.52, offset_seed)
		var stroke_length := radius * (0.16 + 0.08 * float(level))
		var y_offset := base_y + radius * (0.09 + float(deposit_index) * 0.055)
		canvas.draw_line(
			Vector2(start_x, y_offset),
			Vector2(start_x + stroke_length, y_offset + radius * 0.025),
			silt_color,
			1.4 if level == 0 else 2.0,
			true
		)


static func draw_signal_arcs(
	canvas: CanvasItem,
	radius: float,
	region_id: String,
	stable_id: String,
	quality: String,
	completed: bool = false,
	emphasis: float = 1.0
) -> void:
	if canvas == null or radius <= 0.0 or emphasis <= 0.0:
		return
	var colors := palette(region_id)
	var level := quality_level(quality)
	var seed := _stable_seed(stable_id)
	var accent: Color = colors["accent"]
	accent.a = clampf((0.66 if not completed else 0.38) * emphasis, 0.0, 0.92)
	var rim: Color = colors["rim"]
	rim.a = clampf((0.20 if not completed else 0.12) * emphasis, 0.0, 0.42)

	# Jeden nieregularny ślad na low/medium i dwa na high: to osad/caustics,
	# nie symetryczny celownik UI otaczający każdy obiekt.
	var arc_count := 2 if level >= 2 else 1
	var base_angle := -2.46 + seed * 0.34
	var arc_span := 0.34 + seed * 0.18
	for arc_index in range(arc_count):
		var angle := base_angle + float(arc_index) * (2.12 + seed * 0.51)
		var local_radius := radius * (0.92 + 0.13 * fmod(seed * 5.0 + float(arc_index) * 0.37, 1.0))
		canvas.draw_arc(Vector2.ZERO, local_radius, angle, angle + arc_span, 12, accent, 2.0, true)
		if level >= 2:
			canvas.draw_line(
				Vector2.from_angle(angle + arc_span + 0.10) * (local_radius - 2.0),
				Vector2.from_angle(angle + arc_span + 0.21) * (local_radius + 5.0),
				rim,
				1.2,
				true
			)
	if completed:
		var mark_color := accent
		mark_color.a = clampf(0.72 * emphasis, 0.0, 0.88)
		canvas.draw_line(Vector2(-7.0, 1.0), Vector2(-2.0, 6.0), mark_color, 2.4, true)
		canvas.draw_line(Vector2(-2.0, 6.0), Vector2(8.0, -5.0), mark_color, 2.4, true)


static func normalize_quality(quality: String) -> String:
	var normalized := quality.strip_edges().to_lower()
	return normalized if normalized in VALID_QUALITIES else "high"


static func quality_level(quality: String) -> int:
	return VALID_QUALITIES.find(normalize_quality(quality))


static func _normalize_region(region_id: String) -> String:
	var normalized := region_id.strip_edges().to_upper()
	if normalized in ["R1", "R2", "R3", "R4"]:
		return normalized
	return ""


static func _region_from_stable_id(stable_id: String) -> String:
	var normalized := stable_id.strip_edges().to_lower()
	if normalized.is_empty():
		return ""
	if normalized == "junction_j7" or normalized == "archive_terminal":
		return "R1"
	if normalized.begins_with("c4_"):
		return "R4"
	if normalized.begins_with("r3_"):
		return "R3"
	var padded := "_%s_" % normalized
	for region_index in range(1, 5):
		if padded.contains("_r%d_" % region_index):
			return "R%d" % region_index
	return ""


static func _stable_seed(stable_id: String) -> float:
	return float(posmod(stable_id.hash(), 100003)) / 100003.0


static func _make_palette(
	region_id: String,
	tint: Color,
	patina: Color,
	accent: Color,
	rim: Color,
	shadow: Color,
	silt: Color,
	body_dark: Color,
	body_mid: Color,
	body_light: Color,
	patina_mode: float,
	tint_strength: float,
	patina_strength: float
) -> Dictionary:
	return {
		"region_id": region_id,
		"tint": tint,
		"patina": patina,
		"accent": accent,
		"rim": rim,
		"shadow": shadow,
		"silt": silt,
		"body_dark": body_dark,
		"body_mid": body_mid,
		"body_light": body_light,
		"patina_mode": patina_mode,
		"tint_strength": tint_strength,
		"patina_strength": patina_strength,
	}
