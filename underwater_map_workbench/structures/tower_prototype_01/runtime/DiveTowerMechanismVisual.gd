extends Node2D

var _mechanism_kind: StringName = &"bulkhead"
var _visual_size := Vector2(80.0, 120.0)
var _accent := Color(0.48, 0.68, 0.72, 1.0)
var _visual_state := "closed"
var _wheel_phase := 0.0
var _signal_phase := 0.0


func configure(mechanism_kind: StringName, visual_size: Vector2, accent: Color) -> void:
	_mechanism_kind = mechanism_kind
	_visual_size = visual_size
	_accent = accent
	set_meta(&"mechanism_kind", _mechanism_kind)
	set_meta(&"native_visual_size", _visual_size)
	set_meta(&"native_visual_rect", Rect2(-_visual_size * 0.5, _visual_size))
	set_meta(&"visual_state", _visual_state)
	if _mechanism_kind == &"empty_service_trolley":
		set_meta(&"open_aperture_local_rect", _empty_service_trolley_aperture_rect())
		set_meta(&"open_aperture_expected_transparent", true)
	set_process(true)
	queue_redraw()


func set_visual_state(state: String) -> void:
	if _visual_state == state:
		return
	_visual_state = state
	_signal_phase = 0.0
	set_meta(&"visual_state", _visual_state)
	queue_redraw()


func visual_state() -> String:
	return _visual_state


func _process(delta: float) -> void:
	var wheels_are_moving := _visual_state in ["moving_down", "returning"]
	var signal_is_active := _visual_state in [
		"moving_down",
		"returning",
		"blocked_by_diver",
		"contact_closed",
		"opening",
		"closing",
		"moving",
	]
	if wheels_are_moving:
		_wheel_phase = fmod(_wheel_phase + maxf(delta, 0.0) * 4.0, TAU)
	if signal_is_active:
		_signal_phase = fmod(_signal_phase + maxf(delta, 0.0) * 4.0, TAU)
	if wheels_are_moving or signal_is_active:
		queue_redraw()


func _draw() -> void:
	match _mechanism_kind:
		&"empty_service_trolley":
			_draw_empty_service_trolley()
		&"horizontal_bulkhead":
			_draw_bulkhead(true)
		&"archive_hatch":
			_draw_archive_hatch()
		_:
			_draw_bulkhead(false)


func _draw_empty_service_trolley() -> void:
	var half := _visual_size * 0.5
	var native_bounds := Rect2(-half, _visual_size)
	var frame := native_bounds.grow(-5.0)
	var state_accent := _accent
	if _visual_state == "blocked_by_diver":
		state_accent = Color(0.95, 0.28, 0.22, 1.0).lerp(Color(1.0, 0.72, 0.24, 1.0), (sin(_signal_phase) + 1.0) * 0.5)
	elif _visual_state in ["contact_closed", "latched_floor_7"]:
		state_accent = Color(0.34, 0.92, 0.68, 1.0)
	elif _visual_state in ["moving_down", "returning"]:
		state_accent = Color(0.92, 0.68, 0.26, 1.0)

	# Wózek jest otwartą kratownicą: nie rysuj pełnej płyty pod ramą.
	draw_rect(frame, Color(0.12, 0.20, 0.22, 1.0), false, 10.0)
	draw_rect(frame.grow(-6.0), Color(0.48, 0.56, 0.55, 1.0), false, 3.0)
	var open_aperture := _empty_service_trolley_aperture_rect()
	draw_rect(open_aperture, Color(0.30, 0.45, 0.47, 1.0), false, 4.0)
	var deck := Rect2(Vector2(-half.x + 18.0, half.y - 52.0), Vector2(_visual_size.x - 36.0, 34.0))
	draw_rect(deck, Color(0.12, 0.20, 0.21, 1.0), true)
	draw_rect(deck.grow(-2.5), state_accent.darkened(0.28), false, 5.0)
	for grate_index: int in range(13):
		var grate_x := lerpf(deck.position.x + 12.0, deck.end.x - 12.0, float(grate_index) / 12.0)
		draw_line(Vector2(grate_x, deck.position.y + 5.0), Vector2(grate_x, deck.end.y - 5.0), Color(0.38, 0.43, 0.40, 1.0), 2.0)
	for bar_index: int in range(7):
		var x := lerpf(-half.x + 30.0, half.x - 30.0, float(bar_index) / 6.0)
		draw_line(Vector2(x, -half.y + 22.0), Vector2(x, half.y - 55.0), Color(0.27, 0.38, 0.39, 1.0), 5.0)
	draw_line(Vector2(-half.x + 24.0, -half.y + 28.0), Vector2(half.x - 24.0, -half.y + 28.0), Color(0.42, 0.55, 0.56, 1.0), 7.0)
	draw_line(Vector2(-half.x + 24.0, 0.0), Vector2(half.x - 24.0, 0.0), Color(0.20, 0.34, 0.37, 1.0), 5.0)
	draw_line(Vector2(-half.x + 28.0, -half.y + 34.0), Vector2(half.x - 28.0, half.y - 60.0), Color(0.35, 0.30, 0.23, 0.72), 4.0)
	draw_line(Vector2(half.x - 28.0, -half.y + 34.0), Vector2(-half.x + 28.0, half.y - 60.0), Color(0.25, 0.34, 0.34, 0.72), 4.0)
	for corner_x: float in [-half.x + 26.0, half.x - 26.0]:
		draw_line(Vector2(corner_x, -half.y + 24.0), Vector2(corner_x, half.y - 30.0), Color(0.52, 0.62, 0.62, 1.0), 8.0)
	for roller_x: float in [-half.x + 56.0, half.x - 56.0]:
		_draw_roller(Vector2(roller_x, half.y - 20.0), 14.0, _wheel_phase)
		draw_circle(Vector2(roller_x, -half.y + 18.0), 11.0, Color(0.08, 0.12, 0.13, 1.0))
		draw_circle(Vector2(roller_x, -half.y + 18.0), 11.0, state_accent.darkened(0.2), false, 4.0)
	# Środek nie dostaje żadnego wypełnienia: przez kratownicę musi być widoczne tło świata.
	# Mechaniczny odbierak styku C jest częścią wózka, ale nie tworzy kabiny.
	var contact_arm_x := half.x - 58.0
	draw_line(Vector2(contact_arm_x, -26.0), Vector2(contact_arm_x, 28.0), Color(0.46, 0.39, 0.28, 1.0), 9.0)
	draw_line(Vector2(contact_arm_x, -24.0), Vector2(half.x - 22.0, -8.0), state_accent.darkened(0.18), 8.0)
	for rust_mark: Vector2 in [Vector2(-half.x + 44.0, 36.0), Vector2(-74.0, -half.y + 31.0), Vector2(82.0, half.y - 35.0), Vector2(half.x - 96.0, -half.y + 29.0)]:
		draw_circle(rust_mark, 5.0, Color(0.43, 0.25, 0.14, 0.82))
	if _visual_state in ["contact_closed", "latched_floor_7"]:
		draw_circle(Vector2(half.x - 38.0, 0.0), 13.0, state_accent.darkened(0.08))
		var contact_radius := 20.0
		if _visual_state == "contact_closed":
			contact_radius += (sin(_signal_phase) + 1.0) * 1.5
			draw_circle(Vector2(half.x - 38.0, 0.0), contact_radius, Color(state_accent.r, state_accent.g, state_accent.b, 0.46), false, 4.0)


func _empty_service_trolley_aperture_rect() -> Rect2:
	var half := _visual_size * 0.5
	return Rect2(
		Vector2(-half.x + 76.0, -half.y + 50.0),
		Vector2(_visual_size.x - 152.0, _visual_size.y - 116.0),
	)


func _draw_roller(center: Vector2, radius: float, phase: float) -> void:
	draw_circle(center, radius, Color(0.04, 0.07, 0.08, 1.0))
	draw_circle(center, radius, Color(0.48, 0.58, 0.58, 1.0), false, 4.0)
	for spoke_index: int in range(4):
		var angle := phase + float(spoke_index) * PI * 0.5
		draw_line(center, center + Vector2(cos(angle), sin(angle)) * (radius - 3.0), Color(0.72, 0.70, 0.57, 1.0), 3.0)


func _draw_bulkhead(horizontal: bool) -> void:
	var half := _visual_size * 0.5
	var panel := Rect2(-half, _visual_size).grow(-4.0)
	var edge := _accent
	if _visual_state == "open":
		edge = Color(0.32, 0.75, 0.62, 1.0)
	elif _visual_state in ["opening", "closing", "moving"]:
		var pulse := (sin(_signal_phase) + 1.0) * 0.5
		edge = Color(0.66, 0.42, 0.16, 1.0).lerp(Color(1.0, 0.78, 0.30, 1.0), pulse)
	draw_rect(panel, Color(0.08, 0.15, 0.17, 1.0), true)
	draw_rect(panel, edge.darkened(0.2), false, 7.0)
	var inset := panel.grow(-11.0)
	draw_rect(inset, Color(0.16, 0.24, 0.25, 1.0), true)
	draw_rect(inset, Color(0.43, 0.52, 0.52, 1.0), false, 4.0)
	draw_line(inset.position + Vector2(5.0, 8.0), Vector2(inset.end.x - 5.0, inset.position.y + 8.0), Color(0.57, 0.62, 0.58, 0.54), 3.0)
	if horizontal:
		for rib_index: int in range(3):
			var x := lerpf(inset.position.x + 18.0, inset.end.x - 18.0, float(rib_index) / 2.0)
			draw_line(Vector2(x, inset.position.y + 8.0), Vector2(x, inset.end.y - 8.0), Color(0.30, 0.39, 0.39, 1.0), 8.0)
	else:
		for rib_index: int in range(3):
			var y := lerpf(inset.position.y + 18.0, inset.end.y - 18.0, float(rib_index) / 2.0)
			draw_line(Vector2(inset.position.x + 8.0, y), Vector2(inset.end.x - 8.0, y), Color(0.30, 0.39, 0.39, 1.0), 8.0)
	for corner: Vector2 in [inset.position + Vector2(10.0, 10.0), Vector2(inset.end.x - 10.0, inset.position.y + 10.0), Vector2(inset.position.x + 10.0, inset.end.y - 10.0), inset.end - Vector2(10.0, 10.0)]:
		draw_circle(corner, 5.0, Color(0.72, 0.65, 0.46, 1.0))
	for scratch_index: int in range(3):
		var y := lerpf(inset.position.y + 14.0, inset.end.y - 14.0, float(scratch_index) / 2.0)
		draw_line(Vector2(inset.position.x + 18.0, y), Vector2(inset.end.x - 22.0, y + 5.0), Color(0.48, 0.30, 0.18, 0.46), 2.0)


func _draw_archive_hatch() -> void:
	_draw_bulkhead(true)
	var radius := minf(_visual_size.x, _visual_size.y) * 0.28
	draw_circle(Vector2.ZERO, radius, Color(0.07, 0.15, 0.18, 1.0))
	draw_circle(Vector2.ZERO, radius, Color(0.60, 0.47, 0.29, 1.0), false, 7.0)
	for spoke_index: int in range(6):
		var angle := float(spoke_index) * TAU / 6.0
		draw_line(Vector2.ZERO, Vector2(cos(angle), sin(angle)) * radius, Color(0.55, 0.45, 0.31, 1.0), 6.0)
	draw_circle(Vector2.ZERO, 10.0, Color(0.68, 0.45, 0.22, 1.0))
