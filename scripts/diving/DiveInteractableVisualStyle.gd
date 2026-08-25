class_name DiveInteractableVisualStyle
extends RefCounted

const INTERACTABLE_SKIN_SHADER: Shader = preload("res://underwater_map_workbench/assets/gameplay/interactables/interactable_region_skin.gdshader")
const INTERACTABLE_EFFECTS_SCRIPT = preload("res://scripts/diving/DiveInteractableVisualEffects.gd")
const VALID_QUALITIES := ["low", "medium", "high"]
const EFFECT_NODE_NAME := "InteractableVisualEffects"
const COLOR_KEYS := [
	"tint",
	"patina",
	"accent",
	"rim",
	"shadow",
	"silt",
	"body_dark",
	"body_mid",
	"body_light",
]
const FLOAT_KEYS := ["patina_mode", "tint_strength", "patina_strength"]


static func resolve_context_id(explicit_hint: String, visual_context: Dictionary) -> String:
	var normalized_hint := explicit_hint.strip_edges()
	if not normalized_hint.is_empty():
		return normalized_hint
	for key in ["context_id", "style_id", "palette_id", "region_id"]:
		var context_id := str(visual_context.get(key, "")).strip_edges()
		if not context_id.is_empty():
			return context_id
	return ""


static func resolve_region(explicit_hint: String, visual_context: Dictionary, _stable_id: String) -> String:
	# Compatibility for existing presenters. The stable ID is deliberately ignored:
	# presentation context must be supplied explicitly by the caller.
	return resolve_context_id(explicit_hint, visual_context)


static func palette(style_source: Variant = {}) -> Dictionary:
	var context := _context_from(style_source)
	var colors := _default_palette()
	_merge_palette_values(colors, context)
	var profile: Variant = context.get("profile", {})
	if profile is Dictionary:
		_merge_palette_values(colors, profile as Dictionary)
	var explicit_colors: Variant = context.get("colors", context.get("visual_colors", {}))
	if explicit_colors is Dictionary:
		_merge_palette_values(colors, explicit_colors as Dictionary)
	if context.get("water_color") is Color:
		colors["tint"] = context["water_color"]
	if context.get("accent_color") is Color:
		colors["accent"] = context["accent_color"]
	if profile is Dictionary and (profile as Dictionary).get("caustics_color") is Color:
		colors["accent"] = (profile as Dictionary)["caustics_color"]
	colors["context_id"] = resolve_context_id("", context)
	return colors


static func apply_sprite(
	sprite: Sprite2D,
	style_source: Variant,
	stable_id: String,
	quality: String,
	state_strength: float = 1.0
) -> void:
	if sprite == null:
		return
	var colors := palette(style_source)
	var skin_material := sprite.material as ShaderMaterial
	if skin_material != null and skin_material.shader != INTERACTABLE_SKIN_SHADER:
		# Nie nadpisuj specjalistycznego materiału prefabu; wspólne łuki i osad
		# nadal zapewnią spójność bez utraty autorskiego efektu.
		return
	if skin_material == null:
		skin_material = ShaderMaterial.new()
		skin_material.shader = INTERACTABLE_SKIN_SHADER
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


static func configure_effect(
	host: Node2D,
	target_sprite: Sprite2D,
	effect_role: String,
	style_source: Variant,
	stable_id: String,
	quality: String,
	reduced_motion: bool,
	resolved: bool,
	radius: float,
	visual_context: Dictionary = {},
	state_tag: String = ""
) -> INTERACTABLE_EFFECTS_SCRIPT:
	var effect: INTERACTABLE_EFFECTS_SCRIPT = _ensure_effect(host)
	if effect == null:
		return null
	var context := visual_context.duplicate(true)
	context.merge(_context_from(style_source), true)
	var visual_variant := str(context.get("effect_variant", context.get("visual_variant", ""))).strip_edges().to_lower()
	if visual_variant.is_empty() and effect_role == "device":
		# `state_tag` jest jawną semantyką prefabu. Może zachować rozpoznawalność
		# urządzenia, ale nie służy do wyprowadzania regionu ani koloru.
		visual_variant = state_tag.strip_edges().to_lower()
	effect.configure(
		effect_role,
		resolve_context_id("", context),
		stable_id,
		palette(context),
		quality_level(quality),
		reduced_motion,
		resolved,
		radius,
		float(context.get("depth_ratio", 0.0)),
		target_sprite,
		state_tag,
		visual_variant
	)
	return effect


static func set_effect_interaction(host: Node2D, focused: bool, progress: float) -> void:
	var effect: INTERACTABLE_EFFECTS_SCRIPT = _effect(host)
	if effect != null:
		effect.set_interaction_presentation(focused, progress)


static func set_effect_time_for_tests(host: Node2D, time_seconds: float) -> void:
	var effect: INTERACTABLE_EFFECTS_SCRIPT = _effect(host)
	if effect != null:
		effect.set_visual_time_for_tests(time_seconds)


static func release_effect_time_override(host: Node2D) -> void:
	var effect: INTERACTABLE_EFFECTS_SCRIPT = _effect(host)
	if effect != null:
		effect.release_visual_time_override()


static func effect_state(host: Node2D) -> Dictionary:
	var effect: INTERACTABLE_EFFECTS_SCRIPT = _effect(host)
	return effect.presentation_state() if effect != null else {}


static func draw_grounding(
	canvas: CanvasItem,
	radius: float,
	style_source: Variant,
	stable_id: String,
	quality: String,
	completed: bool = false
) -> void:
	if canvas == null or radius <= 0.0:
		return
	var colors := palette(style_source)
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
	style_source: Variant,
	stable_id: String,
	quality: String,
	completed: bool = false,
	emphasis: float = 1.0
) -> void:
	if canvas == null or radius <= 0.0 or emphasis <= 0.0:
		return
	var colors := palette(style_source)
	var level := quality_level(quality)
	var seed := _stable_seed(stable_id)
	var accent: Color = colors["accent"]
	accent.a = clampf((0.66 if not completed else 0.38) * emphasis, 0.0, 0.92)
	var rim: Color = colors["rim"]
	rim.a = clampf((0.20 if not completed else 0.12) * emphasis, 0.0, 0.42)

	# Krótkie, niesymetryczne smugi mineralne są przyklejone do dolnego materiału.
	# Nie otaczają obiektu, dzięki czemu nie czytają się jak nawiasy lub celownik UI.
	var stroke_count := 2 if level >= 2 else 1
	var side := -1.0 if seed < 0.5 else 1.0
	for stroke_index in range(stroke_count):
		var mirrored_side := side if stroke_index == 0 else -side
		var base := Vector2(
			mirrored_side * radius * (0.43 + seed * 0.09),
			radius * (0.36 + float(stroke_index) * 0.075)
		)
		var travel := Vector2(-mirrored_side * radius * (0.16 + seed * 0.05), radius * 0.035)
		canvas.draw_polyline(PackedVector2Array([
			base,
			base + travel * 0.44 + Vector2(0.0, -2.0),
			base + travel,
		]), accent, 1.7 if level == 0 else 2.0, true)
		if level >= 2:
			canvas.draw_line(
				base + travel * 0.28 + Vector2(1.0, 2.0),
				base + travel * 0.72 + Vector2(2.0, 3.0),
				rim,
				1.0,
				true
			)


static func normalize_quality(quality: String) -> String:
	var normalized := quality.strip_edges().to_lower()
	return normalized if normalized in VALID_QUALITIES else "high"


static func quality_level(quality: String) -> int:
	return VALID_QUALITIES.find(normalize_quality(quality))


static func _ensure_effect(host: Node2D) -> INTERACTABLE_EFFECTS_SCRIPT:
	if host == null:
		return null
	var existing := host.get_node_or_null(EFFECT_NODE_NAME)
	if existing != null:
		return existing as INTERACTABLE_EFFECTS_SCRIPT
	var effect := INTERACTABLE_EFFECTS_SCRIPT.new() as INTERACTABLE_EFFECTS_SCRIPT
	effect.name = EFFECT_NODE_NAME
	host.add_child(effect)
	return effect


static func _effect(host: Node2D) -> INTERACTABLE_EFFECTS_SCRIPT:
	if host == null:
		return null
	return host.get_node_or_null(EFFECT_NODE_NAME) as INTERACTABLE_EFFECTS_SCRIPT


static func _stable_seed(stable_id: String) -> float:
	return float(posmod(stable_id.hash(), 100003)) / 100003.0


static func _context_from(style_source: Variant) -> Dictionary:
	if style_source is Dictionary:
		return (style_source as Dictionary).duplicate(true)
	if typeof(style_source) in [TYPE_STRING, TYPE_STRING_NAME]:
		var context_id := str(style_source).strip_edges()
		if not context_id.is_empty():
			return {"context_id": context_id}
	return {}


static func _merge_palette_values(target: Dictionary, values: Dictionary) -> void:
	for key in COLOR_KEYS:
		if values.get(key) is Color:
			target[key] = values[key]
	for key in FLOAT_KEYS:
		if typeof(values.get(key)) in [TYPE_INT, TYPE_FLOAT]:
			target[key] = float(values[key])


static func _default_palette() -> Dictionary:
	return {
		"context_id": "",
		"tint": Color("a5b3b4"),
		"patina": Color("657477"),
		"accent": Color("76adb2"),
		"rim": Color("b4d7d9"),
		"shadow": Color("0b171b"),
		"silt": Color("566568"),
		"body_dark": Color("16262a"),
		"body_mid": Color("3d5054"),
		"body_light": Color("839497"),
		"patina_mode": 0.0,
		"tint_strength": 0.10,
		"patina_strength": 0.18,
	}
