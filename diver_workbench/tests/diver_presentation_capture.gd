extends Node2D

const DiverScene := preload("res://diver_workbench/runtime/Diver.tscn")
const LightSystemScript := preload("res://scripts/diving/LightSystem.gd")
const LanternMk1 := preload("res://data/diving_gear/diving_lantern_mk1.tres")
const LanternMk2 := preload("res://data/diving_gear/diving_lantern_mk2.tres")
const CAPTURE_ROOT := "res://tmp/diver_presentation_qa/capture"
const CAPTURE_FPS := 24
const DURATION_SECONDS := 8.0
const CAPTURE_RESOLUTION := Vector2i(1280, 720)

var _diver: DiverController
var _visual_effects: Node
var _status: Label
var _triggered: Dictionary = {}
var _show_socket_overlay := false
var _show_light_overlay := false
var _show_envelope_overlay := false
var _contact_wall_rect := Rect2()
var _light_qa_geometry: Node2D


func _ready() -> void:
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		push_error("Diver presentation capture requires a native Godot window.")
		get_tree().quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = CAPTURE_FPS
	RenderingServer.set_default_clear_color(Color("061c25"))
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_ROOT)) != OK:
		push_error("Could not create diver presentation capture directory.")
		get_tree().quit(1)
		return
	_build_preview()
	for _frame in range(12):
		await get_tree().process_frame
	if get_viewport().get_texture().get_size() != Vector2(CAPTURE_RESOLUTION):
		push_error("Diver capture requires a 1280 x 720 viewport, got %s." % get_viewport().get_texture().get_size())
		get_tree().quit(1)
		return
	if not await _capture_motion_profile("high_normal", "high", false):
		get_tree().quit(1)
		return
	if not await _capture_motion_profile("high_reduced", "high", true):
		get_tree().quit(1)
		return
	if not await _capture_quality_matrix():
		get_tree().quit(1)
		return
	if not await _capture_socket_matrix():
		get_tree().quit(1)
		return
	if not await _capture_envelope_matrix():
		get_tree().quit(1)
		return
	if not await _capture_lantern_matrix():
		get_tree().quit(1)
		return
	var performance_report := await _profile_presentation_cost()
	var report_path := "%s/performance.json" % CAPTURE_ROOT
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		push_error("Could not save diver presentation performance report.")
		get_tree().quit(1)
		return
	report_file.store_string(JSON.stringify(performance_report, "  "))
	report_file.close()
	print("Diver presentation capture saved: motion, quality/reduced matrix, sockets, %s envelope/contact matrix, radial lantern matrix and performance." % _physical_envelope_label())
	print("DIVER_PRESENTATION_PERFORMANCE %s" % JSON.stringify(performance_report))
	get_tree().quit(0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(CAPTURE_RESOLUTION)), Color("061c25"), true)
	if _show_light_overlay:
		_draw_light_qa_background()
		return
	draw_circle(Vector2(640, 370), 170.0, Color(0.04, 0.22, 0.28, 0.92))
	for radius: float in [94.0, 132.0, 170.0]:
		draw_arc(Vector2(640, 370), radius, 0.0, TAU, 96, Color(0.18, 0.56, 0.59, 0.12), 1.0)
	draw_line(Vector2(610, 370), Vector2(670, 370), Color(0.95, 0.70, 0.26, 0.34), 1.0)
	draw_line(Vector2(640, 340), Vector2(640, 400), Color(0.95, 0.70, 0.26, 0.34), 1.0)
	if _show_envelope_overlay:
		_draw_envelope_qa_overlay()
	if not _show_socket_overlay or _diver == null or not _diver.has_method("visual_socket_global"):
		return
	var socket_colors := {
		&"breath": Color("f05cda"),
		&"fin_upper": Color("43e8eb"),
		&"fin_lower": Color("618cff"),
		&"tool_hand": Color("62ed67"),
		&"lamp": Color("ffd84c"),
		&"leak_valve": Color("ff5e62"),
	}
	for socket_id: StringName in socket_colors:
		var point: Vector2 = _diver.visual_socket_global(socket_id)
		var color: Color = socket_colors[socket_id]
		draw_circle(point, 5.0, Color(color.r, color.g, color.b, 0.32))
		draw_arc(point, 8.0, 0.0, TAU, 20, color, 1.4)
		draw_line(point - Vector2(8, 0), point + Vector2(8, 0), color, 1.0)
		draw_line(point - Vector2(0, 8), point + Vector2(0, 8), color, 1.0)


func _draw_envelope_qa_overlay() -> void:
	if _diver == null:
		return
	if _contact_wall_rect.has_area():
		draw_rect(_contact_wall_rect, Color(0.27, 0.37, 0.41, 0.96), true)
		draw_rect(_contact_wall_rect, Color(0.70, 0.84, 0.84, 0.86), false, 2.0)
	var center := _diver.global_position
	var root_rotation := _diver.global_rotation
	var body_shape := (_diver.get_node("CollisionShape2D") as CollisionShape2D).shape as CapsuleShape2D
	var target_size: Vector2 = _diver.frame_envelope_profile.target_size
	var half_target := target_size * 0.5
	var half_segment := body_shape.height * 0.5 - body_shape.radius
	var target_corners := PackedVector2Array([
		center + Vector2(-half_target.x, -half_target.y).rotated(root_rotation),
		center + Vector2(half_target.x, -half_target.y).rotated(root_rotation),
		center + Vector2(half_target.x, half_target.y).rotated(root_rotation),
		center + Vector2(-half_target.x, half_target.y).rotated(root_rotation),
		center + Vector2(-half_target.x, -half_target.y).rotated(root_rotation),
	])
	draw_polyline(target_corners, Color(0.98, 0.73, 0.25, 0.88), 1.6)
	var axis := Vector2.RIGHT.rotated(root_rotation)
	var normal := axis.rotated(PI * 0.5)
	draw_line(center - axis * half_segment - normal * body_shape.radius, center + axis * half_segment - normal * body_shape.radius, Color(0.38, 0.94, 0.88, 0.95), 2.0)
	draw_line(center - axis * half_segment + normal * body_shape.radius, center + axis * half_segment + normal * body_shape.radius, Color(0.38, 0.94, 0.88, 0.95), 2.0)
	draw_arc(center - axis * half_segment, body_shape.radius, root_rotation + PI * 0.5, root_rotation + PI * 1.5, 28, Color(0.38, 0.94, 0.88, 0.95), 2.0)
	draw_arc(center + axis * half_segment, body_shape.radius, root_rotation - PI * 0.5, root_rotation + PI * 0.5, 28, Color(0.38, 0.94, 0.88, 0.95), 2.0)
	if _diver.has_method("_current_visual_alpha_bounds"):
		var alpha_bounds: Rect2 = _diver._current_visual_alpha_bounds()
		var alpha_corners := PackedVector2Array([
			_diver.global_transform * alpha_bounds.position,
			_diver.global_transform * Vector2(alpha_bounds.end.x, alpha_bounds.position.y),
			_diver.global_transform * alpha_bounds.end,
			_diver.global_transform * Vector2(alpha_bounds.position.x, alpha_bounds.end.y),
			_diver.global_transform * alpha_bounds.position,
		])
		draw_polyline(alpha_corners, Color(0.92, 0.36, 0.58, 0.92), 1.2)
	draw_circle(center, 3.0, Color("ffd36b"))
	draw_line(center - Vector2(8.0, 0.0), center + Vector2(8.0, 0.0), Color("ffd36b"), 1.0)
	draw_line(center - Vector2(0.0, 8.0), center + Vector2(0.0, 8.0), Color("ffd36b"), 1.0)


func _build_preview() -> void:
	_diver = DiverScene.instantiate() as DiverController
	add_child(_diver)
	_diver.position = Vector2(640, 370)
	_diver.set_physics_process(false)
	var camera := _diver.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.enabled = false
	var dive_light := _diver.get_node_or_null("DiveLight") as PointLight2D
	if dive_light != null:
		dive_light.enabled = false
	_build_light_qa_geometry()
	_visual_effects = _diver.get_node_or_null("VisualEffects")
	_status = Label.new()
	_status.position = Vector2(34, 28)
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_color", Color("d8f7f2"))
	add_child(_status)


func _build_light_qa_geometry() -> void:
	_light_qa_geometry = Node2D.new()
	_light_qa_geometry.name = "LightQaGeometry"
	_light_qa_geometry.visible = false
	add_child(_light_qa_geometry)
	_add_light_qa_wall(Rect2(925.0, 165.0, 28.0, 410.0), Color("506875"))
	_add_light_qa_wall(Rect2(315.0, 105.0, 300.0, 26.0), Color("455f6a"))


func _add_light_qa_wall(rect: Rect2, color: Color) -> void:
	var polygon := PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.end,
		rect.position + Vector2(0.0, rect.size.y),
	])
	var visual := Polygon2D.new()
	visual.polygon = polygon
	visual.color = color
	_light_qa_geometry.add_child(visual)
	var occluder_polygon := OccluderPolygon2D.new()
	occluder_polygon.closed = true
	occluder_polygon.polygon = polygon
	var occluder := LightOccluder2D.new()
	occluder.occluder = occluder_polygon
	occluder.occluder_light_mask = 1
	_light_qa_geometry.add_child(occluder)


func _draw_light_qa_background() -> void:
	var center := Vector2(640.0, 370.0)
	for x in range(40, CAPTURE_RESOLUTION.x, 80):
		draw_line(Vector2(x, 0), Vector2(x, CAPTURE_RESOLUTION.y), Color(0.22, 0.38, 0.42, 0.16), 1.0)
	for y in range(40, CAPTURE_RESOLUTION.y, 80):
		draw_line(Vector2(0, y), Vector2(CAPTURE_RESOLUTION.x, y), Color(0.22, 0.38, 0.42, 0.16), 1.0)
	for distance: float in [150.0, 300.0, 430.0]:
		for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			var marker := center + direction * distance
			draw_circle(marker, 9.0, Color(0.43, 0.67, 0.70, 0.72))
			draw_arc(marker, 13.0, 0.0, TAU, 24, Color(0.75, 0.91, 0.90, 0.85), 1.5)
	draw_circle(center, 5.0, Color("ffd36b"))
	draw_arc(center, 12.0, 0.0, TAU, 32, Color("ffd36b"), 2.0)
	draw_line(center - Vector2(18.0, 0.0), center + Vector2(18.0, 0.0), Color("ffd36b"), 1.0)
	draw_line(center - Vector2(0.0, 18.0), center + Vector2(0.0, 18.0), Color("ffd36b"), 1.0)


func _set_profile(quality: String, reduced_motion: bool) -> void:
	_diver.reset_at(Vector2(640, 370))
	_diver.set_reduced_motion(reduced_motion)
	if _visual_effects != null:
		if _visual_effects.has_method("set_graphics_quality"):
			_visual_effects.set_graphics_quality(quality)
		if _visual_effects.has_method("set_reduced_motion"):
			_visual_effects.set_reduced_motion(reduced_motion)
		if _visual_effects.has_method("reset_presentation"):
			_visual_effects.reset_presentation()
	_triggered.clear()


func _capture_motion_profile(folder_name: String, quality: String, reduced_motion: bool) -> bool:
	var output_dir := "%s/%s" % [CAPTURE_ROOT, folder_name]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)) != OK:
		push_error("Could not create diver motion capture directory: %s." % output_dir)
		return false
	_set_profile(quality, reduced_motion)
	_show_socket_overlay = false
	queue_redraw()
	for frame_index in range(roundi(DURATION_SECONDS * CAPTURE_FPS)):
		var preview_time := float(frame_index) / float(CAPTURE_FPS)
		_apply_preview_state(preview_time, 1.0 / float(CAPTURE_FPS))
		_status.text = "NUREK — %s  |  %s  |  %s" % [
			_diver.animated_sprite.animation.to_upper(),
			quality.to_upper(),
			"REDUCED MOTION" if reduced_motion else "PEŁNY RUCH",
		]
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if not _save_viewport_png("%s/frame_%04d.png" % [output_dir, frame_index]):
			return false
	return true


func _apply_preview_state(preview_time: float, delta: float) -> void:
	var movement := Vector2.ZERO
	var sprinting := false
	var loop_duration := 2.0
	var state_start := 0.0
	var leak_intensity := 0.0
	var interaction_action: StringName = &""
	var interaction_progress := 0.0
	var towing := false
	if preview_time >= 1.30 and preview_time < 2.80:
		movement = Vector2.RIGHT
		loop_duration = 1.0
		state_start = 1.30
	elif preview_time >= 2.80 and preview_time < 3.80:
		movement = Vector2.RIGHT
		sprinting = true
		loop_duration = 0.8
		state_start = 2.80
	elif preview_time >= 3.80 and preview_time < 4.45:
		movement = Vector2.RIGHT
		loop_duration = 1.0
		state_start = 3.80
		_trigger_once(&"attack", &"harpoon_attack", Vector2(790, 325), 1.0, preview_time, 3.92)
	elif preview_time >= 4.45 and preview_time < 5.30:
		state_start = 4.45
		interaction_action = &"repair"
		interaction_progress = clampf((preview_time - state_start) / 0.78, 0.0, 1.0)
		_trigger_once(&"repair", &"repair", _diver.position + Vector2(44, -24), 1.0, preview_time, 5.18)
	elif preview_time >= 5.30 and preview_time < 6.20:
		movement = Vector2.RIGHT
		loop_duration = 1.0
		state_start = 5.30
		leak_intensity = 0.78
	elif preview_time >= 6.20 and preview_time < 6.80:
		movement = Vector2.RIGHT
		loop_duration = 1.0
		state_start = 6.20
		leak_intensity = 0.78
		_trigger_once(&"hit", &"hit", _diver.position + Vector2(-120, -35), 1.0, preview_time, 6.28)
	elif preview_time >= 6.80 and preview_time < 7.55:
		movement = Vector2.RIGHT
		loop_duration = 1.0
		state_start = 6.80
		towing = true
	else:
		state_start = 7.55 if preview_time >= 7.55 else 0.0
	_diver._movement_input = movement
	_diver._is_sprinting = sprinting
	_diver._current_velocity = Vector2.ZERO
	_diver.velocity = movement * (265.0 if sprinting else 175.0)
	if _diver.has_method("set_visual_context"):
		_diver.set_visual_context(leak_intensity, interaction_action, interaction_progress, towing)
	_diver._update_visual(delta)
	var phase := fposmod((preview_time - state_start) / loop_duration, 1.0)
	_diver._set_animation_phase(_diver.animated_sprite, phase)
	_diver.animated_sprite.pause()
	_diver._update_presentation_pose(delta)
	if _diver.has_method("_update_socket_markers"):
		_diver._update_socket_markers()


func _trigger_once(
	key: StringName,
	cue: StringName,
	target: Vector2,
	strength: float,
	preview_time: float,
	trigger_time: float
) -> void:
	if preview_time < trigger_time or _triggered.has(key):
		return
	_triggered[key] = true
	if _diver.has_method("play_visual_cue"):
		_diver.play_visual_cue(cue, target, strength)


func _capture_quality_matrix() -> bool:
	for quality: String in ["low", "medium", "high"]:
		for reduced_motion: bool in [false, true]:
			_set_profile(quality, reduced_motion)
			for warmup_frame in range(48):
				var time := 5.30 + float(warmup_frame) / float(CAPTURE_FPS)
				_apply_preview_state(time, 1.0 / float(CAPTURE_FPS))
				await get_tree().process_frame
			_status.text = "MACIERZ VFX — %s  |  %s" % [
				quality.to_upper(),
				"REDUCED MOTION" if reduced_motion else "PEŁNY RUCH",
			]
			await RenderingServer.frame_post_draw
			var suffix := "reduced" if reduced_motion else "normal"
			if not _save_viewport_png("%s/matrix_%s_%s.png" % [CAPTURE_ROOT, quality, suffix]):
				return false
	return true


func _capture_socket_matrix() -> bool:
	if not _diver.has_method("visual_socket_global"):
		return true
	_set_profile("high", false)
	_show_socket_overlay = true
	if _visual_effects != null:
		_visual_effects.visible = false
	for animation_name: StringName in [&"idle", &"swim", &"sprint"]:
		for frame: int in [0, 4, 8, 12]:
			for flip_h: bool in [false, true]:
				_diver.animated_sprite.play(animation_name)
				_diver.animated_sprite.pause()
				_diver.animated_sprite.flip_h = flip_h
				_diver.animated_sprite.set_frame_and_progress(frame, 0.0)
				_diver._update_presentation_pose(0.0)
				_diver._update_socket_markers()
				queue_redraw()
				_status.text = "SOCKET QA — %s  |  FRAME %02d  |  %s" % [animation_name.to_upper(), frame, "LEWO" if flip_h else "PRAWO"]
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var side := "left" if flip_h else "right"
				if not _save_viewport_png("%s/socket_%s_%02d_%s.png" % [CAPTURE_ROOT, animation_name, frame, side]):
					return false
	_show_socket_overlay = false
	if _visual_effects != null:
		_visual_effects.visible = true
	queue_redraw()
	return true


func _capture_envelope_matrix() -> bool:
	_set_profile("high", false)
	_show_socket_overlay = false
	_show_envelope_overlay = true
	_contact_wall_rect = Rect2()
	if _visual_effects != null:
		_visual_effects.visible = false
	for animation_name: StringName in [&"idle", &"swim", &"sprint"]:
		for frame: int in [0, 5, 10, 15]:
			for flip_h: bool in [false, true]:
				_diver.reset_at(Vector2(640, 370))
				_diver.animated_sprite.play(animation_name)
				_diver.animated_sprite.pause()
				_diver.animated_sprite.flip_h = flip_h
				_diver.animated_sprite.set_frame_and_progress(frame, 0.0)
				_diver._update_presentation_pose(0.0)
				_diver._update_socket_markers()
				queue_redraw()
				_status.text = "KOPERTA %s — %s  |  FRAME %02d  |  %s\nTURKUS: COLLIDER  •  RÓŻ: ALFA+RIM  •  ZŁOTO: PROFIL AABB" % [_physical_envelope_label(), animation_name.to_upper(), frame, "LEWO" if flip_h else "PRAWO"]
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var side := "left" if flip_h else "right"
				if not _save_viewport_png("%s/envelope_%s_%02d_%s.png" % [CAPTURE_ROOT, animation_name, frame, side]):
					return false
	if not await _capture_contact_case(
		"contact_vertical_right.png",
		Vector2(760.0, 370.0),
		Vector2(10.0, 240.0),
		Vector2(640.0, 370.0),
		Vector2.RIGHT,
		"KONTAKT — PIONOWA ŚCIANA"
	):
		return false
	if not await _capture_contact_case(
		"contact_horizontal_down.png",
		Vector2(640.0, 490.0),
		Vector2(240.0, 10.0),
		Vector2(640.0, 370.0),
		Vector2.DOWN,
		"KONTAKT — POZIOMA ŚCIANA"
	):
		return false
	_show_envelope_overlay = false
	_contact_wall_rect = Rect2()
	if _visual_effects != null:
		_visual_effects.visible = true
	queue_redraw()
	return true


func _capture_contact_case(
	file_name: String,
	wall_position: Vector2,
	wall_size: Vector2,
	diver_start: Vector2,
	direction: Vector2,
	label: String
) -> bool:
	var wall := StaticBody2D.new()
	wall.name = "EnvelopeQaWall"
	wall.position = wall_position
	var wall_shape := RectangleShape2D.new()
	wall_shape.size = wall_size
	var wall_collision := CollisionShape2D.new()
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	add_child(wall)
	_contact_wall_rect = Rect2(wall_position - wall_size * 0.5, wall_size)
	await get_tree().physics_frame
	_diver.reset_at(diver_start)
	_diver.animated_sprite.play(&"swim")
	_diver.animated_sprite.pause()
	_diver.animated_sprite.set_frame_and_progress(0, 0.0)
	await get_tree().physics_frame
	var collided := false
	for _step in range(120):
		var result: Dictionary = _diver.simulate_motion_tick(direction, false, Vector2.ZERO, 1.0, 1.0 / 60.0, true)
		collided = collided or bool(result["collided"])
		if collided:
			break
		await get_tree().physics_frame
	if not collided:
		push_error("Envelope capture did not reach the real wall for %s." % file_name)
		wall.queue_free()
		return false
	_diver._update_presentation_pose(0.0)
	_diver._update_socket_markers()
	_status.text = "%s  |  RZECZYWISTE move_and_slide()\nTURKUS: COLLIDER  •  RÓŻ: ALFA+RIM  •  ZŁOTO: PROFIL %s" % [label, _physical_envelope_label()]
	queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var saved := _save_viewport_png("%s/%s" % [CAPTURE_ROOT, file_name])
	wall.queue_free()
	await get_tree().physics_frame
	_contact_wall_rect = Rect2()
	return saved


func _physical_envelope_label() -> String:
	if _diver == null or _diver.frame_envelope_profile == null:
		return "? × ?"
	var target_size: Vector2 = _diver.frame_envelope_profile.target_size
	return "%d × %d" % [roundi(target_size.x), roundi(target_size.y)]


func _capture_lantern_matrix() -> bool:
	var dive_light := _diver.light_source()
	if dive_light == null:
		push_error("The radial lantern matrix requires the Diver public PointLight2D.")
		return false
	var ambient := CanvasModulate.new()
	ambient.name = "LightQaAmbient"
	ambient.color = Color(0.20, 0.25, 0.28, 1.0)
	add_child(ambient)
	var light_system = LightSystemScript.new()
	_set_profile("high", false)
	_show_socket_overlay = false
	_show_light_overlay = true
	_light_qa_geometry.visible = true
	if _visual_effects != null:
		_visual_effects.visible = false
	_diver.animated_sprite.play(&"idle")
	_diver.animated_sprite.pause()
	_diver.animated_sprite.set_frame_and_progress(0, 0.0)
	var cases: Array[Dictionary] = [
		{"file": "lantern_off.png", "label": "WYŁĄCZONA", "gear": LanternMk1, "enabled": false, "flip": false},
		{"file": "lantern_mk1_right.png", "label": "LATARNIA I — PRAWO", "gear": LanternMk1, "enabled": true, "flip": false},
		{"file": "lantern_mk1_left.png", "label": "LATARNIA I — LEWO", "gear": LanternMk1, "enabled": true, "flip": true},
		{"file": "lantern_mk2_right.png", "label": "LATARNIA II — PRAWO", "gear": LanternMk2, "enabled": true, "flip": false},
		{"file": "lantern_mk2_left.png", "label": "LATARNIA II — LEWO", "gear": LanternMk2, "enabled": true, "flip": true},
	]
	for capture_case: Dictionary in cases:
		_diver.animated_sprite.flip_h = bool(capture_case["flip"])
		_diver._update_socket_markers()
		_diver._update_light_mount()
		if not light_system.configure(null, dive_light, capture_case["gear"], bool(capture_case["enabled"]), null, 160.0, "high"):
			push_error("Could not configure radial lantern capture case %s." % capture_case["file"])
			ambient.queue_free()
			return false
		_status.text = "RADIALNE ŚWIATŁO — %s  |  ORIGIN (0, 0)" % capture_case["label"]
		queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if not _save_viewport_png("%s/%s" % [CAPTURE_ROOT, capture_case["file"]]):
			ambient.queue_free()
			return false
	dive_light.enabled = false
	_show_light_overlay = false
	_light_qa_geometry.visible = false
	if _visual_effects != null:
		_visual_effects.visible = true
	ambient.queue_free()
	queue_redraw()
	await get_tree().process_frame
	return true


func _profile_presentation_cost() -> Dictionary:
	Engine.max_fps = 0
	_set_profile("high", false)
	for warmup_frame in range(90):
		_apply_preview_state(5.30 + float(warmup_frame) / 60.0, 1.0 / 60.0)
		await get_tree().process_frame
	var viewport_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	for _frame in range(4):
		await get_tree().process_frame
	var render_cpu_ms: Array[float] = []
	var gpu_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var primitives: Array[float] = []
	for sample in range(120):
		_apply_preview_state(5.30 + float(sample) / 60.0, 1.0 / 60.0)
		await get_tree().process_frame
		var cpu_sample := RenderingServer.get_frame_setup_time_cpu() + RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
		var gpu_sample := RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
		if cpu_sample > 0.0:
			render_cpu_ms.append(cpu_sample)
		if gpu_sample > 0.0:
			gpu_ms.append(gpu_sample)
		draw_calls.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	RenderingServer.viewport_set_measure_render_time(viewport_rid, false)
	render_cpu_ms.sort()
	gpu_ms.sort()
	draw_calls.sort()
	primitives.sort()
	return {
		"samples": 120,
		"render_cpu_avg_ms": _average(render_cpu_ms),
		"render_cpu_p95_ms": _percentile(render_cpu_ms, 0.95),
		"gpu_avg_ms": _average(gpu_ms),
		"gpu_p95_ms": _percentile(gpu_ms, 0.95),
		"draw_calls_avg": _average(draw_calls),
		"draw_calls_p95": _percentile(draw_calls, 0.95),
		"primitives_avg": _average(primitives),
		"video_mem_mb": float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / (1024.0 * 1024.0),
		"note": "Isolated presentation harness; repository has no approved numeric GPU/VRAM threshold.",
	}


func _save_viewport_png(path: String) -> bool:
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save diver presentation frame %s (error %d)." % [path, error])
		return false
	return true


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var index := clampi(ceili(float(values.size()) * ratio) - 1, 0, values.size() - 1)
	return values[index]
