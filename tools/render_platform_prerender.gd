extends Node

## Rebuilds the static intro platform plate from the real day-one runtime.
##
## Run natively (not headless):
##   godot --path . res://tools/PlatformPrerenderCapture.tscn
##
## The default output is an external candidate in user://tool_artifacts. Pass
## `-- --output=res://assets/intro/platform_prerender.png` only after visually
## approving that candidate.

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")

const CAPTURE_RESOLUTION := Vector2i(1672, 941)
const CAMPAIGN_SEED := 808
const CAPTURE_TIME := 25.0
const DEFAULT_OUTPUT := "user://tool_artifacts/platform_prerender_candidate.png"

var _output_path := DEFAULT_OUTPUT


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output_path = argument.trim_prefix("--output=").strip_edges()
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		_fail("Platform prerender requires a native, non-embedded Godot window.")
		return
	if (not _output_path.begins_with("res://") and not _output_path.begins_with("user://")) or not _output_path.ends_with(".png") or ".." in _output_path:
		_fail("Output must be a PNG path inside res:// or user://.")
		return

	var game = GameRootScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	if not await _configure_capture_window(game):
		game.free()
		return
	if not game.start_new_campaign("standard", CAMPAIGN_SEED, false, false):
		game.free()
		_fail("Could not start the isolated standard day-one campaign.")
		return
	for _frame in range(5):
		await get_tree().process_frame

	var base = game.current_scene
	if base == null or base.name != "BaseScene":
		game.free()
		_fail("The capture must use the real GameRoot -> BaseScene flow.")
		return
	base.set_graphics_quality("high")
	base.set_animation_time_for_tests(CAPTURE_TIME)
	var environment = base.get_node_or_null("BaseEnvironment")
	if environment == null or environment.world_viewport == null or environment.world_3d == null:
		game.free()
		_fail("The live BaseEnvironment world viewport is unavailable.")
		return
	environment.clear_building_highlight()
	var far_rain_veil := environment.find_child("RainFarVeil", true, false) as CanvasItem
	if far_rain_veil != null:
		far_rain_veil.visible = false
	for particle_node in environment.world_3d.find_children("Rain*", "GPUParticles3D", true, false):
		var particles := particle_node as GPUParticles3D
		particles.emitting = false
		particles.visible = false

	for _barrier in range(6):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var image: Image = environment.world_viewport.get_texture().get_image()
	if image == null or image.is_empty():
		var actual_size: Vector2i = image.get_size() if image != null else Vector2i.ZERO
		game.free()
		_fail("World viewport is unavailable (size %s)." % str(actual_size))
		return
	# On high-DPI desktops Godot renders the native window above its requested
	# logical size. Downsampling that same-aspect high-resolution viewport makes
	# the checked-in plate independent of the host DPI while retaining clean AA.
	if image.get_size() != CAPTURE_RESOLUTION:
		image.resize(CAPTURE_RESOLUTION.x, CAPTURE_RESOLUTION.y, Image.INTERPOLATE_LANCZOS)
	var absolute_output := ProjectSettings.globalize_path(_output_path)
	var output_directory := absolute_output.get_base_dir()
	if not DirAccess.dir_exists_absolute(output_directory):
		var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
		if directory_error != OK:
			game.free()
			_fail("Could not create output directory (error %d)." % directory_error)
			return
	var save_error: int = image.save_png(absolute_output)
	if save_error != OK:
		game.free()
		_fail("Could not save the platform prerender (error %d)." % save_error)
		return

	game.free()
	await get_tree().process_frame
	print(
		"Platform prerender saved: %s (%dx%d, standard day 1, seed %d, high, t=%.1f)."
		% [_output_path, CAPTURE_RESOLUTION.x, CAPTURE_RESOLUTION.y, CAMPAIGN_SEED, CAPTURE_TIME]
	)
	get_tree().quit(0)


func _configure_capture_window(game: Node) -> bool:
	var settings: Dictionary = game.user_settings.snapshot()
	var display: Dictionary = settings.get("display", {}).duplicate(true)
	display["mode"] = "windowed"
	display["resolution"] = CAPTURE_RESOLUTION
	display["vsync"] = false
	display["max_fps"] = 0
	settings["display"] = display
	settings["graphics"] = {"quality": "high"}
	if game.user_settings.apply(settings, false) != OK:
		_fail("Could not apply canonical capture settings.")
		return false
	for _frame in range(45):
		await get_tree().process_frame
		var actual_size := get_viewport().get_texture().get_size()
		if actual_size.x >= CAPTURE_RESOLUTION.x and actual_size.y >= CAPTURE_RESOLUTION.y:
			var target_aspect := float(CAPTURE_RESOLUTION.x) / float(CAPTURE_RESOLUTION.y)
			var actual_aspect := actual_size.x / actual_size.y
			if absf(actual_aspect - target_aspect) <= 0.01:
				return true
	_fail(
		"Native capture target did not reach the %dx%d aspect/size contract (got %s)."
		% [CAPTURE_RESOLUTION.x, CAPTURE_RESOLUTION.y, str(get_viewport().get_texture().get_size())]
	)
	return false


func _fail(message: String) -> void:
	push_error("Platform prerender capture failed: " + message)
	get_tree().quit(1)
