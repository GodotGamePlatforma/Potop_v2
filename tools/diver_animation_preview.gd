extends Node2D

const DiverScene := preload("res://scenes/diving/Diver.tscn")
const CAPTURE_FPS := 24
const DURATION := 8.0
const CAPTURE_ROOT := "user://tool_artifacts/diver_runtime_capture"

var _diver: DiverController
var _status: Label


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#061f29"))
	_build_preview()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not await _capture_profile("normal", false):
		get_tree().quit(1)
		return
	if not await _capture_profile("reduced", true):
		get_tree().quit(1)
		return
	print("Diver runtime animation preview frames saved: normal and reduced motion.")
	get_tree().quit(0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color("#061f29"), true)
	for radius: float in [92.0, 128.0]:
		draw_arc(Vector2(640, 360), radius, 0.0, TAU, 96, Color(0.18, 0.55, 0.60, 0.12), 1.0)
	draw_line(Vector2(620, 360), Vector2(660, 360), Color(0.96, 0.74, 0.26, 0.55), 1.0)
	draw_line(Vector2(640, 340), Vector2(640, 380), Color(0.96, 0.74, 0.26, 0.55), 1.0)


func _build_preview() -> void:
	_diver = DiverScene.instantiate() as DiverController
	add_child(_diver)
	_diver.position = Vector2(640, 360)
	_diver.scale = Vector2(2.0, 2.0)
	_diver.set_physics_process(false)
	var camera := _diver.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.enabled = false
	var visual_effects := _diver.get_node_or_null("VisualEffects") as Node2D
	if visual_effects != null:
		visual_effects.visible = false
	var dive_light := _diver.get_node_or_null("DiveLight") as PointLight2D
	if dive_light != null:
		dive_light.enabled = false
	_status = Label.new()
	_status.position = Vector2(34, 28)
	_status.add_theme_font_size_override("font_size", 24)
	_status.add_theme_color_override("font_color", Color("#d8f7f2"))
	add_child(_status)


func _capture_profile(profile_name: String, reduced_motion: bool) -> bool:
	var output_dir := "%s/%s" % [CAPTURE_ROOT, profile_name]
	var absolute_dir := ProjectSettings.globalize_path(output_dir)
	if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
		push_error("Could not create diver preview directory: %s" % absolute_dir)
		return false
	_diver.reset_at(Vector2(640, 360))
	_diver.set_reduced_motion(reduced_motion)
	for frame_index in range(int(DURATION * CAPTURE_FPS)):
		var preview_time := float(frame_index) / float(CAPTURE_FPS)
		_apply_preview_state(preview_time, 1.0 / float(CAPTURE_FPS))
		_status.text = "NURKOWANIE — %s   |   %s   |   PODGLĄD 2×" % [_diver.animated_sprite.animation.to_upper(), "REDUCED MOTION" if reduced_motion else "PEŁNY RUCH"]
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var frame_image := get_viewport().get_texture().get_image()
		var save_error := frame_image.save_png("%s/frame_%04d.png" % [output_dir, frame_index])
		if save_error != OK:
			push_error("Could not save diver preview frame %d for %s." % [frame_index, profile_name])
			return false
	return true


func _apply_preview_state(preview_time: float, delta: float) -> void:
	var state_time := preview_time
	var movement := Vector2.ZERO
	var sprinting := false
	var loop_duration := 2.0
	if preview_time >= 2.0 and preview_time < 4.0:
		state_time = preview_time - 2.0
		movement = Vector2.RIGHT
		loop_duration = 1.0
	elif preview_time >= 4.0 and preview_time < 5.6:
		state_time = preview_time - 4.0
		movement = Vector2.RIGHT
		sprinting = true
		loop_duration = 0.8
	elif preview_time >= 5.6 and preview_time < 6.6:
		state_time = preview_time - 5.6
		movement = Vector2.RIGHT
		loop_duration = 1.0
	elif preview_time >= 6.6:
		state_time = preview_time - 6.6
	_diver.movement_input = movement
	_diver.is_sprinting = sprinting
	_diver.velocity = movement * (265.0 if sprinting else 175.0)
	_diver._update_visual(delta)
	var phase := fposmod(state_time / loop_duration, 1.0)
	_diver._set_animation_phase(_diver.animated_sprite, phase)
	_diver.animated_sprite.pause()
	_diver._update_presentation_pose(delta)
