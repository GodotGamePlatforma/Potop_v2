class_name DiveCurrentVisual
extends Node2D

const FIELD_HALF_SIZE := Vector2(760.0, 430.0)
const STREAK_COUNT := 72
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
	for index in range(STREAK_COUNT):
		var depth_factor := _seed_unit(index, 3)
		var speed_factor := lerpf(0.52, 1.18, depth_factor)
		var base_position := Vector2(
			lerpf(-FIELD_HALF_SIZE.x, FIELD_HALF_SIZE.x, _seed_unit(index, 11)),
			lerpf(-FIELD_HALF_SIZE.y, FIELD_HALF_SIZE.y, _seed_unit(index, 29))
		)
		var point := _wrap_to_field(base_position + flow_vector * _visual_time * speed_factor)
		var streak_length := lerpf(10.0, 36.0, _intensity) * lerpf(0.62, 1.15, depth_factor)
		var line_width := lerpf(0.80, 1.70, depth_factor)
		# CanvasModulate intentionally darkens the dive scene heavily. The local
		# alpha therefore needs enough headroom to remain legible in open water.
		var alpha := _intensity * lerpf(0.14, 0.38, depth_factor)
		var color := Color(
			lerpf(0.56, 0.82, depth_factor),
			lerpf(0.82, 0.98, depth_factor),
			lerpf(0.88, 1.0, depth_factor),
			alpha
		)
		draw_line(point - direction * streak_length, point, color, line_width, true)
		if depth_factor > 0.78:
			draw_circle(point, lerpf(0.55, 1.05, depth_factor), color)


func _wrap_to_field(point: Vector2) -> Vector2:
	return Vector2(
		fposmod(point.x + FIELD_HALF_SIZE.x, FIELD_HALF_SIZE.x * 2.0) - FIELD_HALF_SIZE.x,
		fposmod(point.y + FIELD_HALF_SIZE.y, FIELD_HALF_SIZE.y * 2.0) - FIELD_HALF_SIZE.y
	)


static func _seed_unit(index: int, salt: int) -> float:
	var quadratic := (index + salt + 11) * (index + salt + 11) * 131
	var mixed := posmod((index + 1) * 92_821 + (salt + 3) * 68_917 + quadratic, 104_729)
	return float(mixed) / 104_728.0
