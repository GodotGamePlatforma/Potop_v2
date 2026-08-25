class_name DiveInteractableVisualEffects
extends Node2D

const EFFECT_ROLES := [
	"container",
	"pickup",
	"buoy",
	"shortcut",
	"heavy",
	"device",
	"rescue",
	"exit",
]

var _effect_role := "container"
var _context_id := ""
var _stable_id := "interactable"
var _state_tag := ""
var _visual_variant := ""
var _colors: Dictionary = {}
var _quality_level := 2
var _reduced_motion := false
var _resolved := false
var _focused := false
var _interaction_progress := 0.0
var _radius := 56.0
var _depth_ratio := 0.0
var _visual_time := 0.0
var _time_locked := false
var _stable_phase := 0.0
var _target_sprite: Sprite2D
var _shader_accepts_interactable_parameters := false


func _ready() -> void:
	z_index = 3
	set_process(not _reduced_motion and not _time_locked)
	_apply_sprite_material_parameters()
	queue_redraw()


func configure(
	effect_role: String,
	context_id: String,
	stable_id: String,
	colors: Dictionary,
	quality_level: int,
	reduced_motion: bool,
	resolved: bool,
	radius: float,
	depth_ratio: float,
	target_sprite: Sprite2D = null,
	state_tag: String = "",
	visual_variant: String = ""
) -> void:
	_effect_role = effect_role if effect_role in EFFECT_ROLES else "container"
	_context_id = context_id.strip_edges()
	_stable_id = stable_id if not stable_id.is_empty() else "interactable"
	_state_tag = state_tag
	_visual_variant = visual_variant.strip_edges().to_lower()
	_colors = colors.duplicate(true)
	_quality_level = clampi(quality_level, 0, 2)
	_reduced_motion = reduced_motion
	_resolved = resolved
	_radius = maxf(radius, 18.0)
	_depth_ratio = clampf(depth_ratio, 0.0, 1.0)
	_target_sprite = target_sprite
	_stable_phase = _stable_sample(97) * TAU
	_refresh_target_material_support()
	set_process(not _reduced_motion and not _time_locked)
	_apply_sprite_material_parameters()
	queue_redraw()


func set_interaction_presentation(focused: bool, progress: float) -> void:
	_focused = focused
	_interaction_progress = clampf(progress, 0.0, 1.0) if focused else 0.0
	_apply_sprite_material_parameters()
	queue_redraw()


func set_visual_time_for_tests(time_seconds: float) -> void:
	_visual_time = maxf(time_seconds, 0.0)
	_time_locked = true
	set_process(false)
	_apply_sprite_material_parameters()
	queue_redraw()


func release_visual_time_override() -> void:
	_time_locked = false
	set_process(not _reduced_motion)


func presentation_state() -> Dictionary:
	return {
		"role": _effect_role,
		"context_id": _context_id,
		"stable_id": _stable_id,
		"state_tag": _state_tag,
		"visual_variant": _visual_variant,
		"colors": _colors.duplicate(true),
		"quality_level": _quality_level,
		"reduced_motion": _reduced_motion,
		"resolved": _resolved,
		"focused": _focused,
		"interaction_progress": _interaction_progress,
		"visual_time": _display_time(),
		"time_locked": _time_locked,
		"stable_phase": _stable_phase,
		"detail_budget": _detail_budget(),
		"depth_ratio": _depth_ratio,
	}


func _process(delta: float) -> void:
	_visual_time += maxf(delta, 0.0)
	if not is_visible_in_tree():
		return
	_apply_sprite_material_parameters()
	queue_redraw()


func _draw() -> void:
	# Godot 4.7.1's dummy renderer can race RID allocation while async textures load.
	# Headless tests validate presentation state, while native runs validate pixels.
	if DisplayServer.get_name() == "headless":
		return
	if _colors.is_empty():
		return
	_draw_ambient_motes()
	match _effect_role:
		"pickup":
			_draw_pickup_material()
		"buoy":
			_draw_buoy_material()
		"shortcut":
			_draw_shortcut_material()
		"heavy":
			_draw_heavy_material()
		"device":
			_draw_device_material()
		"rescue":
			_draw_rescue_material()
		"exit":
			_draw_exit_material()
		_:
			_draw_container_material()
	if _focused:
		_draw_interaction_material_cue()


func _draw_ambient_motes() -> void:
	var count := _detail_budget()
	var time := _display_time()
	var rise_scale := lerpf(1.0, 0.76, _depth_ratio)
	var role_grounded := _effect_role in ["container", "heavy", "shortcut", "device"]
	for index in range(count):
		var speed := (0.055 + _stable_sample(index * 17 + 3) * 0.045) * rise_scale
		var cycle := fposmod(time * speed + _stable_sample(index * 29 + 5), 1.0)
		var x := lerpf(-_radius * 0.58, _radius * 0.58, _stable_sample(index * 41 + 7))
		var rise := _radius * (0.28 if role_grounded else 0.52)
		var y_start := _radius * (0.46 if role_grounded else 0.30)
		var drift := sin(time * 0.46 + _stable_phase + float(index) * 1.73) * _radius * 0.035
		var position := Vector2(x + drift, y_start - cycle * rise)
		var life_alpha := sin(cycle * PI)
		var state_scale := 0.58 if _resolved else 1.0
		var alpha := (0.16 + 0.055 * float(_quality_level)) * life_alpha * state_scale
		if _focused:
			alpha *= 1.28
		_draw_ambient_particle(position, index, alpha, time)


func _draw_ambient_particle(position: Vector2, index: int, alpha: float, time: float) -> void:
	var silt := _palette_color("silt", Color("72878a"), alpha)
	var accent := _palette_color("accent", Color("75cbd0"), alpha * 0.92)
	match _effect_role:
		"shortcut":
			var sway := sin(time * 0.72 + _stable_phase + float(index)) * 2.4
			draw_polyline(PackedVector2Array([
				position + Vector2(0.0, 3.0),
				position + Vector2(sway * 0.45, 0.0),
				position + Vector2(sway, -4.0),
			]), silt, 1.25, true)
		"device":
			var size := 1.5 + _stable_sample(index * 13 + 11) * 1.6
			draw_colored_polygon(PackedVector2Array([
				position + Vector2(0.0, -size),
				position + Vector2(size * 0.72, 0.0),
				position + Vector2(0.0, size),
				position + Vector2(-size * 0.72, 0.0),
			]), accent)
		"heavy":
			var direction := Vector2(3.4, -1.8).rotated(_stable_sample(index * 19 + 2) * 0.5 - 0.25)
			draw_line(position - direction * 0.5, position + direction * 0.5, silt, 1.15, true)
			draw_line(position + direction * 0.15, position + direction * 0.15 + Vector2(-1.4, -2.0), accent, 0.9, true)
		_:
			var bubble_radius := 1.2 + _stable_sample(index * 23 + 13) * 1.7
			draw_arc(position, bubble_radius, -2.65, 1.35, 8, silt, 1.0, true)
			draw_circle(position + Vector2(-bubble_radius * 0.28, -bubble_radius * 0.25), 0.65, accent)


func _draw_container_material() -> void:
	var time := _display_time()
	var signal_color := _palette_color("rim" if _resolved else "accent", Color("79d1d5"), 1.0)
	var pulse := 0.72 + sin(time * 1.12 + _stable_phase) * 0.16
	var alpha := (0.22 + _focus_strength() * 0.42) * pulse
	if _resolved:
		alpha *= 0.44
	draw_line(Vector2(-9.0, -2.0), Vector2(9.0, -2.0), _with_alpha(signal_color, alpha * 0.72), 1.5, true)
	draw_circle(Vector2(0.0, -2.0), 2.4, _with_alpha(signal_color, alpha))
	if _interaction_progress > 0.0:
		var release := Vector2.from_angle(-1.9 + _interaction_progress * 1.2) * (8.0 + _interaction_progress * 5.0)
		draw_line(Vector2(0.0, -6.0), release + Vector2(0.0, -6.0), _with_alpha(signal_color, 0.36 + _interaction_progress * 0.34), 1.2, true)


func _draw_pickup_material() -> void:
	var time := _display_time()
	var angle := time * 0.44 + _stable_phase
	var center := Vector2.from_angle(angle) * _radius * 0.46
	var signal_color := _palette_color("rim", Color("a8e2e2"), 0.20 + _focus_strength() * 0.52)
	var length := 2.8 + _focus_strength() * 2.4
	draw_line(center - Vector2(length, 0.0), center + Vector2(length, 0.0), signal_color, 1.1, true)
	draw_line(center - Vector2(0.0, length), center + Vector2(0.0, length), signal_color, 1.1, true)


func _draw_device_material() -> void:
	var time := _display_time()
	var signal_color := _palette_color("rim" if _resolved else "accent", Color("70cbd1"), 1.0)
	if _visual_variant.contains("archive"):
		_draw_archive_terminal_cycle(time, signal_color)
	elif _visual_variant.contains("diagnostic"):
		_draw_diagnostic_cycle(time, signal_color)
	elif _visual_variant.contains("generator"):
		_draw_generator_cycle(time, signal_color)
	elif _visual_variant.contains("switchboard"):
		_draw_switchboard_cycle(time, signal_color)
	elif _visual_variant.contains("splitter"):
		_draw_splitter_cycle(time, signal_color)
	else:
		_draw_junction_cycle(time, signal_color)


func _draw_junction_cycle(time: float, signal_color: Color) -> void:
	var active_index := posmod(int(floor(time * 0.78 + _stable_phase)), 3)
	for index in range(3):
		var active := _resolved or index == active_index
		var alpha := (0.30 if active else 0.10) + _focus_strength() * (0.34 if active else 0.12)
		draw_circle(Vector2(-18.0 + float(index) * 18.0, -18.0), 2.2 if active else 1.6, _with_alpha(signal_color, alpha))
	if _quality_level >= 1:
		var trace_alpha := 0.16 + _focus_strength() * 0.28 + _interaction_progress * 0.16
		draw_polyline(PackedVector2Array([
			Vector2(-26.0, 15.0), Vector2(-8.0, 15.0), Vector2(-8.0, 8.0),
			Vector2(18.0, 8.0), Vector2(18.0, 2.0), Vector2(29.0, 2.0),
		]), _with_alpha(signal_color, trace_alpha), 1.35, true)


func _draw_archive_terminal_cycle(time: float, signal_color: Color) -> void:
	var scan_ratio := fposmod(time * 0.11 + _stable_sample(211), 1.0)
	var scan_y := lerpf(-21.0, 17.0, scan_ratio)
	var alpha := 0.18 + _focus_strength() * 0.38
	draw_line(Vector2(-27.0, scan_y), Vector2(22.0, scan_y), _with_alpha(signal_color, alpha), 1.25, true)
	for index in range(3):
		var row_y := -14.0 + float(index) * 12.0
		var row_width := 13.0 + _stable_sample(223 + index) * 11.0
		draw_line(Vector2(-24.0, row_y), Vector2(-24.0 + row_width, row_y), _with_alpha(signal_color, 0.10 + float(index) * 0.025), 1.0, true)


func _draw_diagnostic_cycle(time: float, signal_color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(9):
		var x := -29.0 + float(index) * 7.25
		var wave := sin(time * 0.84 + _stable_phase + float(index) * 1.18) * (3.0 + _focus_strength() * 2.0)
		points.append(Vector2(x, wave - 4.0))
	draw_polyline(points, _with_alpha(signal_color, 0.24 + _focus_strength() * 0.34), 1.35, true)
	draw_line(Vector2(-30.0, 14.0), Vector2(29.0, 14.0), _with_alpha(signal_color, 0.12), 1.0, true)


func _draw_generator_cycle(time: float, signal_color: Color) -> void:
	var phase := time * 0.38 + _stable_phase
	var center := Vector2(0.0, -2.0)
	draw_arc(center, 16.0, phase, phase + 1.35, 12, _with_alpha(signal_color, 0.24 + _focus_strength() * 0.28), 2.0, true)
	draw_arc(center, 10.0, phase + PI, phase + PI + 1.12, 10, _with_alpha(signal_color, 0.16 + _interaction_progress * 0.28), 1.25, true)
	for index in range(3):
		var spoke := Vector2.from_angle(phase + float(index) * TAU / 3.0) * 13.0
		draw_line(center, center + spoke, _with_alpha(signal_color, 0.12), 1.0, true)


func _draw_switchboard_cycle(time: float, signal_color: Color) -> void:
	for index in range(4):
		var triggered := sin(time * (0.62 + float(index) * 0.07) + _stable_phase + float(index) * 1.41) > 0.42
		var x := -24.0 + float(index) * 16.0
		var alpha := (0.28 if triggered else 0.09) + _focus_strength() * (0.22 if triggered else 0.08)
		draw_line(Vector2(x, -18.0), Vector2(x, 13.0), _with_alpha(signal_color, alpha), 1.4 if triggered else 0.9, true)
		draw_circle(Vector2(x, -21.0), 2.1 if triggered else 1.3, _with_alpha(signal_color, alpha))


func _draw_splitter_cycle(time: float, signal_color: Color) -> void:
	var pulse := 0.5 + sin(time * 0.74 + _stable_phase) * 0.5
	var alpha := 0.18 + pulse * 0.16 + _focus_strength() * 0.28
	draw_line(Vector2(-28.0, 0.0), Vector2(-6.0, 0.0), _with_alpha(signal_color, alpha), 1.5, true)
	for direction in [-1.0, 0.0, 1.0]:
		var endpoint := Vector2(28.0, direction * 19.0)
		draw_polyline(PackedVector2Array([
			Vector2(-6.0, 0.0), Vector2(6.0, direction * 5.0), endpoint,
		]), _with_alpha(signal_color, alpha * (0.72 + 0.16 * direction)), 1.3, true)


func _draw_buoy_material() -> void:
	var time := _display_time()
	var signal_color := _palette_color("rim" if _resolved else "accent", Color("7fd9d2"), 1.0)
	var sway := sin(time * 0.58 + _stable_phase) * 2.8
	draw_line(Vector2(0.0, _radius * 0.42), Vector2(sway, _radius * 0.86), _with_alpha(signal_color, 0.20), 1.5, true)
	var bubble_count := 2 + _quality_level
	for index in range(bubble_count):
		var cycle := fposmod(time * (0.08 + float(index) * 0.008) + _stable_sample(index + 71), 1.0)
		var bubble_position := Vector2(13.0 + sin(time + float(index)) * 3.0, -_radius * (0.20 + cycle * 0.92))
		draw_arc(bubble_position, 1.8 + float(index) * 0.45, -2.8, 1.25, 9, _with_alpha(signal_color, 0.22 + _focus_strength() * 0.14), 1.0, true)


func _draw_shortcut_material() -> void:
	if _resolved:
		return
	var time := _display_time()
	var fiber := _palette_color("patina", Color("69786f"), 0.30 + _focus_strength() * 0.18)
	var signal_color := _palette_color("accent", Color("d08b58"), 0.18 + _focus_strength() * 0.32)
	for index in range(3):
		var y := (float(index) - 1.0) * 7.0
		var sway := sin(time * (0.52 + float(index) * 0.08) + _stable_phase + float(index)) * 3.2
		draw_polyline(PackedVector2Array([
			Vector2(-22.0, y), Vector2(-7.0, y + sway), Vector2(8.0, y - sway * 0.45), Vector2(23.0, y + 1.0),
		]), fiber if index != 1 else signal_color, 1.4, true)


func _draw_heavy_material() -> void:
	var time := _display_time()
	var silt := _palette_color("silt", Color("6f7971"), 0.20 + _focus_strength() * 0.16)
	for index in range(2 + _quality_level):
		var travel := fposmod(time * 0.045 + _stable_sample(index * 31 + 9), 1.0)
		var start := Vector2(lerpf(-_radius * 0.48, _radius * 0.26, travel), _radius * (0.43 + float(index) * 0.055))
		draw_line(start, start + Vector2(_radius * 0.15, -1.5), _with_alpha(silt, silt.a * sin(travel * PI)), 1.4, true)


func _draw_rescue_material() -> void:
	var time := _display_time()
	var signal_color := _palette_color("rim", Color("9edfe0"), 0.28 + _focus_strength() * 0.20)
	var origin := Vector2(-31.0, -17.0)
	var bubble_count := 1 + _quality_level
	for index in range(bubble_count):
		var cycle := fposmod(time * (0.11 + float(index) * 0.012) + _stable_sample(index * 13 + 29), 1.0)
		var bubble_position := origin + Vector2(sin(cycle * TAU + _stable_phase) * 4.0, -cycle * 37.0)
		draw_arc(bubble_position, 1.6 + float(index) * 0.55, -2.7, 1.4, 9, signal_color, 1.0, true)


func _draw_exit_material() -> void:
	var time := _display_time()
	var signal_color := _palette_color("rim", Color("9de0df"), 0.28 + _focus_strength() * 0.20)
	var bubble_count := 3 + _quality_level
	for index in range(bubble_count):
		var cycle := fposmod(time * (0.09 + float(index) * 0.008) + _stable_sample(index * 37 + 17), 1.0)
		var bubble_position := Vector2(26.0 + sin(time * 0.8 + float(index)) * 4.0, -55.0 - cycle * 96.0)
		draw_arc(bubble_position, 2.0 + float(index) * 0.42, -2.75, 1.35, 10, signal_color, 1.0, true)


func _draw_interaction_material_cue() -> void:
	var signal_color := _palette_color("rim", Color("a7e2e1"), 0.38 + _interaction_progress * 0.30)
	var cue_count := 1 if _quality_level == 0 else 2
	for index in range(cue_count):
		var angle := _stable_phase + float(index) * 2.37 + _interaction_progress * 0.84
		var center := Vector2.from_angle(angle) * _radius * (0.48 + float(index) * 0.08)
		var tangent := Vector2.from_angle(angle + PI * 0.5) * (5.0 + _interaction_progress * 3.0)
		draw_line(center - tangent, center + tangent, signal_color, 1.5, true)


func _apply_sprite_material_parameters() -> void:
	if not _shader_accepts_interactable_parameters or _target_sprite == null or not is_instance_valid(_target_sprite):
		return
	var shader_material := _target_sprite.material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return
	shader_material.set_shader_parameter("interactable_anim_time", _display_time())
	shader_material.set_shader_parameter("interactable_focus_strength", _focus_strength())
	shader_material.set_shader_parameter("interactable_motion_strength", 0.36 if _reduced_motion else 1.0)
	shader_material.set_shader_parameter("interactable_role", float(EFFECT_ROLES.find(_effect_role)))
	shader_material.set_shader_parameter("interactable_resolved", 1.0 if _resolved else 0.0)
	shader_material.set_shader_parameter("interactable_depth", _depth_ratio)


func _refresh_target_material_support() -> void:
	_shader_accepts_interactable_parameters = false
	if _target_sprite == null or not is_instance_valid(_target_sprite):
		return
	var shader_material := _target_sprite.material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return
	_shader_accepts_interactable_parameters = shader_material.shader.code.contains(
		"uniform float interactable_anim_time"
	)


func _display_time() -> float:
	return 0.0 if _reduced_motion else _visual_time


func _detail_budget() -> int:
	var budget: int = [1, 2, 4][_quality_level]
	if _resolved:
		budget = maxi(1, budget - 1)
	if _focused:
		budget += 1
	return budget


func _focus_strength() -> float:
	return clampf((0.58 if _focused else 0.0) + _interaction_progress * 0.42, 0.0, 1.0)


func _stable_sample(salt: int) -> float:
	return float(posmod(("%s:%d" % [_stable_id, salt]).hash(), 100003)) / 100003.0


func _palette_color(key: String, fallback: Color, alpha: float) -> Color:
	var color: Color = _colors.get(key, fallback)
	return _with_alpha(color, alpha)


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))
