class_name DiveCurrentVisual
extends Node2D

const FIELD_HALF_SIZE := Vector2(760.0, 430.0)
const QUALITY_BUDGETS := {
	"low": 20,
	"medium": 30,
	"high": 40,
}
const REFERENCE_CURRENT_SPEED := 90.0
const FADE_IN_PER_SECOND := 3.6
const FADE_OUT_PER_SECOND := 2.4
const MIN_VECTOR_LENGTH_SQUARED := 0.0001
const DIRECTION_GLYPHS := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]

var _sample_vector := Vector2.ZERO
var _last_nonzero_vector := Vector2.RIGHT
var _target_intensity: float = 0.0
var _intensity: float = 0.0
var _visual_time: float = 0.0
var _test_mode: bool = false
var _reduced_motion: bool = false
var _graphics_quality: String = "high"


func _init() -> void:
	top_level = true
	z_as_relative = false
	# Water motion belongs above the distant background, but below the authored
	# collider and rock-transition layers (-20 and -10). This keeps streaks from
	# being painted across solid walls.
	z_index = -30
	visible = false


func _ready() -> void:
	queue_redraw()


func update_sample(
	current_vector: Vector2,
	world_anchor: Vector2,
	delta: float,
	snap_transition: bool = false
) -> void:
	global_position = world_anchor
	_sample_vector = current_vector
	if current_vector.length_squared() > MIN_VECTOR_LENGTH_SQUARED:
		_last_nonzero_vector = current_vector
		_target_intensity = clampf(current_vector.length() / REFERENCE_CURRENT_SPEED, 0.0, 1.0)
	else:
		_target_intensity = 0.0

	if snap_transition:
		_intensity = _target_intensity
	else:
		var fade_rate := FADE_IN_PER_SECOND if _target_intensity > _intensity else FADE_OUT_PER_SECOND
		_intensity = move_toward(_intensity, _target_intensity, maxf(delta, 0.0) * fade_rate)
	if not _test_mode and not _reduced_motion:
		_visual_time += maxf(delta, 0.0)
	visible = _intensity > 0.001 or _target_intensity > 0.001
	queue_redraw()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	queue_redraw()


func set_graphics_quality(quality_id: String) -> void:
	_graphics_quality = quality_id if QUALITY_BUDGETS.has(quality_id) else "high"
	queue_redraw()


func graphics_quality() -> String:
	return _graphics_quality


func sample_budget() -> int:
	return int(QUALITY_BUDGETS.get(_graphics_quality, QUALITY_BUDGETS["high"]))


func reduced_motion_enabled() -> bool:
	return _reduced_motion


func set_visual_time_for_tests(time_seconds: float, snap_transition: bool = true) -> void:
	_test_mode = true
	_visual_time = maxf(time_seconds, 0.0)
	if snap_transition:
		_intensity = _target_intensity
	visible = _intensity > 0.001 or _target_intensity > 0.001
	queue_redraw()


func sampled_vector() -> Vector2:
	return _sample_vector


func visual_time() -> float:
	return _visual_time


func intensity() -> float:
	return _intensity


func is_test_mode() -> bool:
	return _test_mode


static func direction_symbol_for_vector(vector: Vector2) -> String:
	if vector.length_squared() <= MIN_VECTOR_LENGTH_SQUARED:
		return ""
	var sector: int = posmod(int(round(vector.angle() / (PI * 0.25))), DIRECTION_GLYPHS.size())
	return str(DIRECTION_GLYPHS[sector])


func _draw() -> void:
	if _intensity <= 0.001 or _last_nonzero_vector.length_squared() <= MIN_VECTOR_LENGTH_SQUARED:
		return
	var direction := _last_nonzero_vector.normalized()
	var flow_vector := _last_nonzero_vector
	for index in range(sample_budget()):
		var depth_factor := _seed_unit(index, 3)
		var base_position := Vector2(
			lerpf(-FIELD_HALF_SIZE.x, FIELD_HALF_SIZE.x, _seed_unit(index, 11)),
			lerpf(-FIELD_HALF_SIZE.y, FIELD_HALF_SIZE.y, _seed_unit(index, 29))
		)
		var role := _seed_unit(index, 47)
		var speed_factor := lerpf(0.50, 1.08, depth_factor)
		if role >= 0.60:
			speed_factor *= 0.35 if role < 0.90 else 0.20
		var rise := Vector2(0.0, -_visual_time * lerpf(1.4, 4.2, depth_factor)) if role >= 0.90 else Vector2.ZERO
		var point := _wrap_to_field(base_position + flow_vector * _visual_time * speed_factor + rise)
		var alpha := _intensity * lerpf(0.065, 0.18, depth_factor)
		var color := Color(
			lerpf(0.48, 0.76, depth_factor),
			lerpf(0.76, 0.94, depth_factor),
			lerpf(0.84, 1.0, depth_factor),
			alpha
		)
		if role < 0.60:
			var angle_jitter := deg_to_rad(lerpf(-3.0, 3.0, _seed_unit(index, 71)))
			var streak_direction := direction.rotated(angle_jitter)
			var perpendicular := Vector2(-streak_direction.y, streak_direction.x)
			var streak_length := lerpf(5.0, 17.0, _intensity) * lerpf(0.68, 1.10, depth_factor)
			var line_width := lerpf(0.55, 1.15, depth_factor)
			var start := point - streak_direction * streak_length
			var middle := start.lerp(point, 0.52) + perpendicular * lerpf(-1.8, 1.8, _seed_unit(index, 83))
			var points := PackedVector2Array([start, middle, point])
			var glow := Color(color.r, color.g, color.b, color.a * 0.24)
			draw_polyline(points, glow, line_width + 1.15, true)
			draw_polyline(PackedVector2Array([middle.lerp(point, 0.18), point]), color, line_width, true)
			draw_circle(point, lerpf(0.35, 0.72, depth_factor), Color(color.r, color.g, color.b, color.a * 0.72))
		elif role < 0.90:
			draw_circle(point, lerpf(0.38, 0.92, depth_factor), Color(color.r, color.g, color.b, color.a * 0.62))
		else:
			var bubble_radius := lerpf(1.2, 2.6, depth_factor)
			draw_arc(point, bubble_radius, 0.0, TAU, 12, Color(color.r, color.g, color.b, color.a * 0.78), 0.7, true)


func _wrap_to_field(point: Vector2) -> Vector2:
	return Vector2(
		fposmod(point.x + FIELD_HALF_SIZE.x, FIELD_HALF_SIZE.x * 2.0) - FIELD_HALF_SIZE.x,
		fposmod(point.y + FIELD_HALF_SIZE.y, FIELD_HALF_SIZE.y * 2.0) - FIELD_HALF_SIZE.y
	)


static func _seed_unit(index: int, salt: int) -> float:
	var quadratic := (index + salt + 11) * (index + salt + 11) * 131
	var mixed := posmod((index + 1) * 92_821 + (salt + 3) * 68_917 + quadratic, 104_729)
	return float(mixed) / 104_728.0
