class_name BuildingPresentation
extends Control

enum VisualState {
	EMPTY,
	CONSTRUCTION_PLANNED,
	UPGRADE_PLANNED,
	ACTIVE_UNSTAFFED,
	ACTIVE_STAFFED,
	BLOCKED,
	DAMAGED,
	ACTIVE_IDLE,
}

const BlueprintShader := preload("res://base_workbench/assets/environment/building_blueprint_overlay.gdshader")

const STEEL_DARK := Color(0.11, 0.17, 0.18, 1.0)
const STEEL_EDGE := Color(0.35, 0.38, 0.34, 1.0)
const WEATHERED_WOOD := Color(0.38, 0.27, 0.17, 1.0)
const TARP_COLOR := Color(0.07, 0.17, 0.17, 1.0)
const AMBER := Color(0.96, 0.61, 0.22, 1.0)
const WARM_LIGHT := Color(1.0, 0.67, 0.30, 1.0)
const COOL_SIGNAL := Color(0.35, 0.76, 0.78, 1.0)
const DAMAGE_SIGNAL := Color(0.83, 0.28, 0.19, 1.0)

var visual_state: int = VisualState.EMPTY
var definition_id: String = ""
var target_level_texture: Texture2D
var wind_direction := Vector2.RIGHT
var wind_strength := 0.0
var reduced_motion := false

var _blueprint_layer: TextureRect
var _blueprint_material: ShaderMaterial
var _elapsed := 0.0
var _displayed_time := 0.0
var _forced_animation_time := -1.0
var _state_revision := 0
var _entry_started_at := -1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _ready() -> void:
	_build_blueprint_layer()
	_apply_blueprint_state()
	_apply_animation_time(_displayed_time)
	_update_processing()
	queue_redraw()


func configure(
	new_visual_state: int,
	new_definition_id: String,
	new_target_level_texture: Texture2D = null,
	new_wind_direction: Vector2 = Vector2.RIGHT,
	new_wind_strength: float = 0.0,
	new_reduced_motion: bool = false
) -> void:
	var normalized_state := clampi(new_visual_state, VisualState.EMPTY, VisualState.ACTIVE_IDLE)
	var normalized_definition := new_definition_id.strip_edges()
	var state_changed := (
		normalized_state != visual_state
		or normalized_definition != definition_id
		or new_target_level_texture != target_level_texture
	)
	if state_changed:
		visual_state = normalized_state
		definition_id = normalized_definition
		target_level_texture = new_target_level_texture
		_state_revision += 1
		_apply_blueprint_state()
	set_environment(new_wind_direction, new_wind_strength)
	set_reduced_motion(new_reduced_motion)
	if state_changed:
		_update_processing()
		queue_redraw()


func set_environment(new_wind_direction: Vector2, new_wind_strength: float) -> void:
	var normalized_direction := new_wind_direction.normalized() if new_wind_direction.length_squared() > 0.0001 else Vector2.RIGHT
	var normalized_strength := clampf(new_wind_strength, 0.0, 1.5)
	if wind_direction.is_equal_approx(normalized_direction) and is_equal_approx(wind_strength, normalized_strength):
		return
	wind_direction = normalized_direction
	wind_strength = normalized_strength
	queue_redraw()


func set_reduced_motion(value: bool) -> void:
	if reduced_motion == value:
		return
	reduced_motion = value
	if _blueprint_material != null:
		_blueprint_material.set_shader_parameter("reduced_motion", 1.0 if reduced_motion else 0.0)
	_update_processing()
	queue_redraw()


func set_animation_time_for_tests(seconds: float) -> void:
	_forced_animation_time = maxf(seconds, 0.0)
	_apply_animation_time(_forced_animation_time)
	_update_processing()


func clear_animation_time_override() -> void:
	if _forced_animation_time < 0.0:
		return
	_elapsed = _displayed_time
	_forced_animation_time = -1.0
	_update_processing()


func get_animation_time() -> float:
	return _displayed_time


func get_state_revision() -> int:
	return _state_revision


func play_state_entry() -> void:
	if visual_state not in [VisualState.CONSTRUCTION_PLANNED, VisualState.UPGRADE_PLANNED]:
		return
	if reduced_motion or _forced_animation_time >= 0.0:
		_entry_started_at = -1.0
		queue_redraw()
		return
	_entry_started_at = _displayed_time
	queue_redraw()


func is_blueprint_visible() -> bool:
	return _blueprint_layer != null and _blueprint_layer.visible


func _process(delta: float) -> void:
	if _forced_animation_time >= 0.0 or reduced_motion:
		return
	_elapsed += maxf(delta, 0.0)
	_apply_animation_time(_elapsed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	match visual_state:
		VisualState.CONSTRUCTION_PLANNED:
			_draw_construction(false)
		VisualState.UPGRADE_PLANNED:
			_draw_construction(true)
		VisualState.ACTIVE_UNSTAFFED:
			_draw_type_activity(0.24, false)
			_draw_status_beacon(_p(Vector2(0.80, 0.70)), COOL_SIGNAL, 0.30, false)
		VisualState.ACTIVE_STAFFED:
			_draw_type_activity(1.0, true)
		VisualState.ACTIVE_IDLE:
			# A capable crew is present, but the canonical day forecast has no
			# executable task (for example no patient or a fully repaired platform).
			# Keep the building readable without implying work that will not happen.
			_draw_type_activity(0.30, false)
			_draw_status_beacon(_p(Vector2(0.80, 0.70)), COOL_SIGNAL, 0.24, false)
		VisualState.BLOCKED:
			_draw_type_activity(0.10, false)
			_draw_status_beacon(_p(Vector2(0.80, 0.70)), AMBER, 0.66, true)
		VisualState.DAMAGED:
			_draw_damaged_state()


func _build_blueprint_layer() -> void:
	if _blueprint_layer != null:
		return
	_blueprint_layer = TextureRect.new()
	_blueprint_layer.name = "BlueprintOverlay"
	_blueprint_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blueprint_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_blueprint_layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_blueprint_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blueprint_layer.z_index = -1
	_blueprint_material = ShaderMaterial.new()
	_blueprint_material.shader = BlueprintShader
	_blueprint_layer.material = _blueprint_material
	add_child(_blueprint_layer)


func _apply_blueprint_state() -> void:
	if _blueprint_layer == null:
		return
	_blueprint_layer.texture = target_level_texture
	var construction := visual_state == VisualState.CONSTRUCTION_PLANNED
	var upgrade := visual_state == VisualState.UPGRADE_PLANNED
	_blueprint_layer.visible = target_level_texture != null and (construction or upgrade)
	if not _blueprint_layer.visible:
		return
	if construction:
		_blueprint_material.set_shader_parameter("outline_color", Color(0.38, 0.54, 0.50, 1.0))
		_blueprint_material.set_shader_parameter("outline_strength", 0.070)
		_blueprint_material.set_shader_parameter("base_strength", 0.32)
		_blueprint_material.set_shader_parameter("base_start", 0.77)
	else:
		_blueprint_material.set_shader_parameter("outline_color", Color(0.58, 0.43, 0.28, 1.0))
		_blueprint_material.set_shader_parameter("outline_strength", 0.055)
		_blueprint_material.set_shader_parameter("base_strength", 0.0)
	_blueprint_material.set_shader_parameter("reduced_motion", 1.0 if reduced_motion else 0.0)
	_blueprint_material.set_shader_parameter("anim_time", _displayed_time)


func _apply_animation_time(value: float) -> void:
	_displayed_time = maxf(value, 0.0)
	if _blueprint_material != null:
		_blueprint_material.set_shader_parameter("anim_time", _displayed_time)
	queue_redraw()


func _update_processing() -> void:
	var animated_state := visual_state != VisualState.EMPTY
	set_process(animated_state and not reduced_motion and _forced_animation_time < 0.0)


func _draw_construction(upgrade: bool) -> void:
	var unit := _unit()
	var opacity := (0.88 if upgrade else 0.96) * _entry_factor()
	var left := 0.15 if upgrade else 0.20
	var right := 0.85 if upgrade else 0.80
	var top := 0.24 if upgrade else 0.38
	var bottom := 0.86
	var pole_width := maxf(unit * 0.006, 1.0)
	var steel := _with_alpha(STEEL_EDGE, 0.84 * opacity)
	var shadow := _with_alpha(STEEL_DARK, 0.88 * opacity)

	# A fixed low foundation keeps the visual weight on the mounting point.
	var foundation := PackedVector2Array([
		_p(Vector2(0.27, 0.79)),
		_p(Vector2(0.68, 0.79)),
		_p(Vector2(0.76, 0.84)),
		_p(Vector2(0.36, 0.88)),
		_p(Vector2(0.24, 0.84)),
	])
	draw_colored_polygon(foundation, _with_alpha(STEEL_DARK, 0.66 * opacity))
	draw_polyline(PackedVector2Array([foundation[0], foundation[1], foundation[2], foundation[3], foundation[4], foundation[0]]), steel, pole_width, true)

	var verticals := [left, lerpf(left, right, 0.31), lerpf(left, right, 0.68), right]
	var horizontals := [top, lerpf(top, bottom, 0.34), lerpf(top, bottom, 0.67), bottom]
	for x in verticals:
		draw_line(_p(Vector2(x, top)), _p(Vector2(x, bottom)), shadow, pole_width * 2.2, true)
		draw_line(_p(Vector2(x, top)), _p(Vector2(x, bottom)), steel, pole_width, true)
	for y in horizontals:
		draw_line(_p(Vector2(left, y)), _p(Vector2(right, y)), shadow, pole_width * 2.2, true)
		draw_line(_p(Vector2(left, y)), _p(Vector2(right, y)), steel, pole_width, true)
	for index in range(verticals.size() - 1):
		var x0: float = verticals[index]
		var x1: float = verticals[index + 1]
		var reverse := index % 2 == 1
		var from := _p(Vector2(x0, bottom if reverse else top))
		var to := _p(Vector2(x1, top if reverse else bottom))
		draw_line(from, to, _with_alpha(STEEL_EDGE, 0.46 * opacity), pole_width * 0.72, true)

	_draw_material_piles(opacity)
	_draw_construction_tarp(top, left, right, opacity)
	_draw_status_beacon(_p(Vector2(right + 0.015, lerpf(top, bottom, 0.45))), AMBER, 0.82 * opacity, true)
	_draw_site_entry_dust()


func _entry_factor() -> float:
	if reduced_motion or _entry_started_at < 0.0:
		return 1.0
	return smoothstep(0.0, 0.42, _displayed_time - _entry_started_at)


func _draw_site_entry_dust() -> void:
	if reduced_motion or _entry_started_at < 0.0:
		return
	var age := _displayed_time - _entry_started_at
	if age < 0.0 or age > 0.82:
		return
	var unit := _unit()
	var fade := 1.0 - age / 0.82
	for index in range(5):
		var phase := clampf(age * (0.82 + float(index) * 0.07), 0.0, 1.0)
		var origin := _p(Vector2(0.28 + float(index) * 0.11, 0.84))
		var drift := Vector2(wind_direction.x * unit * 0.018 * phase, -unit * (0.018 + float(index % 2) * 0.008) * phase)
		var radius := unit * (0.010 + phase * 0.014)
		draw_circle(origin + drift, radius, Color(0.45, 0.48, 0.43, 0.065 * fade), true, -1.0, true)


func _draw_material_piles(opacity: float) -> void:
	var unit := _unit()
	var plank_width := maxf(unit * 0.009, 1.0)
	for index in range(4):
		var y := 0.795 + float(index) * 0.015
		var inset := float(index % 2) * 0.012
		draw_line(
			_p(Vector2(0.15 + inset, y)),
			_p(Vector2(0.34 - inset, y - 0.012)),
			_with_alpha(WEATHERED_WOOD, (0.66 - float(index) * 0.06) * opacity),
			plank_width,
			true
		)
	var scrap := PackedVector2Array([
		_p(Vector2(0.67, 0.81)),
		_p(Vector2(0.82, 0.79)),
		_p(Vector2(0.85, 0.84)),
		_p(Vector2(0.70, 0.86)),
	])
	draw_colored_polygon(scrap, _with_alpha(STEEL_DARK, 0.72 * opacity))
	draw_polyline(PackedVector2Array([scrap[0], scrap[1], scrap[2], scrap[3], scrap[0]]), _with_alpha(STEEL_EDGE, 0.50 * opacity), maxf(unit * 0.004, 1.0), true)
	draw_line(_p(Vector2(0.70, 0.82)), _p(Vector2(0.82, 0.81)), _with_alpha(STEEL_EDGE, 0.32 * opacity), maxf(unit * 0.003, 1.0), true)


func _draw_construction_tarp(top: float, left: float, right: float, opacity: float) -> void:
	var unit := _unit()
	var motion_scale := 0.0 if reduced_motion else (0.35 + wind_strength * 0.65)
	var wave := sin(_displayed_time * 1.25 + wind_direction.x * 1.7) * unit * 0.010 * motion_scale
	var drift := wind_direction * unit * 0.010 * wind_strength * motion_scale
	var tarp_top := lerpf(top, 0.64, 0.34)
	var tarp_bottom := tarp_top + 0.17
	var tarp_left := lerpf(left, right, 0.18)
	var tarp_right := lerpf(left, right, 0.82)
	var points := PackedVector2Array([
		_p(Vector2(tarp_left, tarp_top)),
		_p(Vector2(tarp_right, tarp_top)),
		_p(Vector2(tarp_right, tarp_bottom)) + drift + Vector2(wave, -absf(wave) * 0.18),
		_p(Vector2(tarp_left, tarp_bottom)) + drift * 0.62 - Vector2(wave * 0.52, 0.0),
	])
	draw_colored_polygon(points, _with_alpha(TARP_COLOR, 0.72 * opacity))
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), _with_alpha(STEEL_EDGE, 0.62 * opacity), maxf(unit * 0.004, 1.0), true)
	var center_top := points[0].lerp(points[1], 0.5)
	var center_bottom := points[3].lerp(points[2], 0.5) + Vector2(0.0, wave * 0.25)
	draw_line(center_top, center_bottom, _with_alpha(Color(0.35, 0.48, 0.46, 1.0), 0.28 * opacity), maxf(unit * 0.0025, 1.0), true)


func _draw_type_activity(intensity: float, staffed: bool) -> void:
	match definition_id:
		"fishing_hut":
			_draw_fishing_activity(intensity, staffed)
		"kitchen":
			_draw_kitchen_activity(intensity, staffed)
		"community_house":
			_draw_community_activity(intensity, staffed)
		"workshop":
			_draw_workshop_activity(intensity, staffed)
		"infirmary":
			_draw_infirmary_activity(intensity, staffed)
		"diving_station":
			_draw_diving_station_activity(intensity, staffed)


func _draw_fishing_activity(intensity: float, staffed: bool) -> void:
	var unit := _unit()
	var center := _p(Vector2(0.42, 0.65))
	var radius := unit * 0.034
	var color := _with_alpha(COOL_SIGNAL, 0.18 * intensity)
	draw_arc(center, radius, 0.0, TAU, 20, color, maxf(unit * 0.004, 1.0), true)
	var angle := 0.0 if reduced_motion or not staffed else _displayed_time * 0.72
	for index in range(4):
		var direction := Vector2.from_angle(angle + TAU * float(index) / 4.0)
		draw_line(center, center + direction * radius * 0.82, color, maxf(unit * 0.003, 1.0), true)
	if staffed:
		_draw_warm_glow(_p(Vector2(0.53, 0.64)), 0.30 * intensity)


func _draw_kitchen_activity(intensity: float, staffed: bool) -> void:
	if staffed:
		_draw_smoke(_p(Vector2(0.50, 0.29)), 0.56 * intensity, Color(0.55, 0.61, 0.59, 1.0))
		_draw_warm_glow(_p(Vector2(0.48, 0.62)), 0.42 * intensity)


func _draw_community_activity(intensity: float, staffed: bool) -> void:
	var unit := _unit()
	var center := _p(Vector2(0.50, 0.22))
	_draw_status_beacon(center, COOL_SIGNAL, (0.26 if staffed else 0.12) * intensity, staffed)
	if not staffed:
		return
	var phase := 0.38 if reduced_motion else fposmod(_displayed_time * 0.22, 1.0)
	for index in range(2):
		var local_phase := fposmod(phase + float(index) * 0.45, 1.0)
		var radius := unit * lerpf(0.018, 0.09, local_phase)
		var alpha := (1.0 - local_phase) * 0.11 * intensity
		draw_arc(center, radius, -PI * 0.82, -PI * 0.18, 18, _with_alpha(COOL_SIGNAL, alpha), maxf(unit * 0.003, 1.0), true)
	_draw_warm_glow(_p(Vector2(0.50, 0.58)), 0.24 * intensity)


func _draw_workshop_activity(intensity: float, staffed: bool) -> void:
	if not staffed:
		return
	_draw_warm_glow(_p(Vector2(0.49, 0.57)), 0.36 * intensity)
	_draw_sparks(_p(Vector2(0.49, 0.56)), 0.76 * intensity)


func _draw_infirmary_activity(intensity: float, staffed: bool) -> void:
	var unit := _unit()
	var lamp := _p(Vector2(0.47, 0.57))
	_draw_warm_glow(lamp, (0.34 if staffed else 0.15) * intensity)
	var sway := 0.0 if reduced_motion else sin(_displayed_time * 0.82) * unit * 0.007 * wind_strength
	var cloth_color := _with_alpha(Color(0.72, 0.73, 0.64, 1.0), 0.15 * intensity)
	draw_line(_p(Vector2(0.66, 0.51)), _p(Vector2(0.66, 0.67)) + Vector2(sway, 0.0), cloth_color, maxf(unit * 0.005, 1.0), true)
	draw_line(_p(Vector2(0.69, 0.52)), _p(Vector2(0.69, 0.65)) + Vector2(sway * 0.72, 0.0), cloth_color, maxf(unit * 0.004, 1.0), true)


func _draw_diving_station_activity(intensity: float, staffed: bool) -> void:
	var unit := _unit()
	var center := _p(Vector2(0.54, 0.48))
	var radius := unit * 0.029
	var color := _with_alpha(COOL_SIGNAL, (0.24 if staffed else 0.10) * intensity)
	draw_arc(center, radius, 0.0, TAU, 20, color, maxf(unit * 0.004, 1.0), true)
	var angle := -PI * 0.35 if reduced_motion or not staffed else _displayed_time * 0.58
	var needle := Vector2.from_angle(angle) * radius * 0.78
	draw_line(center, center + needle, color, maxf(unit * 0.004, 1.0), true)
	_draw_status_beacon(_p(Vector2(0.62, 0.57)), COOL_SIGNAL, 0.28 * intensity, staffed)


func _draw_damaged_state() -> void:
	_draw_smoke(_p(Vector2(0.55, 0.36)), 0.28, Color(0.32, 0.35, 0.34, 1.0))
	_draw_status_beacon(_p(Vector2(0.79, 0.69)), DAMAGE_SIGNAL, 0.62, true)
	var unit := _unit()
	var crack := PackedVector2Array([
		_p(Vector2(0.45, 0.68)),
		_p(Vector2(0.48, 0.65)),
		_p(Vector2(0.47, 0.72)),
		_p(Vector2(0.51, 0.70)),
	])
	draw_polyline(crack, _with_alpha(DAMAGE_SIGNAL, 0.23), maxf(unit * 0.004, 1.0), true)


func _draw_status_beacon(position: Vector2, color: Color, intensity: float, animated: bool) -> void:
	var unit := _unit()
	var pulse := 1.0
	if animated and not reduced_motion:
		pulse = 0.78 + 0.22 * sin(_displayed_time * 2.35)
	var radius := unit * 0.013
	draw_circle(position, radius * 2.1, _with_alpha(color, 0.055 * intensity * pulse), true, -1.0, true)
	draw_circle(position, radius, _with_alpha(color, 0.42 * intensity * pulse), true, -1.0, true)
	draw_arc(position, radius * 1.25, 0.0, TAU, 16, _with_alpha(color, 0.34 * intensity), maxf(unit * 0.0025, 1.0), true)


func _draw_warm_glow(position: Vector2, intensity: float) -> void:
	var unit := _unit()
	var pulse := 1.0 if reduced_motion else 0.90 + 0.10 * sin(_displayed_time * 1.62 + position.x * 0.01)
	draw_circle(position, unit * 0.052, _with_alpha(WARM_LIGHT, 0.030 * intensity * pulse), true, -1.0, true)
	draw_circle(position, unit * 0.025, _with_alpha(WARM_LIGHT, 0.075 * intensity * pulse), true, -1.0, true)


func _draw_smoke(origin: Vector2, intensity: float, color: Color) -> void:
	var unit := _unit()
	var smoke_direction := Vector2(wind_direction.x * 0.55, -1.0 + wind_direction.y * 0.12).normalized()
	for index in range(4):
		var age := (float(index) + 1.0) / 5.0
		if not reduced_motion:
			age = fposmod(_displayed_time * 0.14 + float(index) * 0.24, 1.0)
		var drift := smoke_direction * unit * lerpf(0.02, 0.15, age) * (0.72 + wind_strength * 0.32)
		var lateral := Vector2(-smoke_direction.y, smoke_direction.x) * sin(age * 8.0 + float(index)) * unit * 0.009
		var radius := unit * lerpf(0.010, 0.032, age)
		var alpha := (1.0 - age) * 0.105 * intensity
		draw_circle(origin + drift + lateral, radius, _with_alpha(color, alpha), true, -1.0, true)


func _draw_sparks(origin: Vector2, intensity: float) -> void:
	var unit := _unit()
	var phase := 0.12 if reduced_motion else fposmod(_displayed_time, 2.85)
	if phase > 0.34:
		return
	var fade := 1.0 - phase / 0.34
	for index in range(5):
		var angle := -PI * 0.92 + float(index) * 0.37
		var direction := Vector2.from_angle(angle)
		var offset := direction * unit * (0.010 + float(index % 3) * 0.007)
		var length := unit * (0.014 + float((index + 1) % 3) * 0.006)
		draw_line(origin + offset, origin + offset + direction * length, _with_alpha(AMBER, 0.44 * intensity * fade), maxf(unit * 0.003, 1.0), true)


func _p(normalized: Vector2) -> Vector2:
	return normalized * size


func _unit() -> float:
	return minf(size.x, size.y)


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))
