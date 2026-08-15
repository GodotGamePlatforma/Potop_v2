extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")

const TEST_SAVE := "user://test_intro_visual_snapshot.tres"
const TEST_PENDING := "user://test_intro_visual_snapshot.pending.tres"
const TEST_BACKUP := "user://test_intro_visual_snapshot.backup.tres"
const CAPTURE_RESOLUTION := Vector2i(1280, 720)

const BEATS := [
	{"time": 4.0, "file": "intro_01_drowned_city.png"},
	{"time": 18.5, "file": "intro_02_platform_discovery.png"},
	{"time": 25.0, "file": "intro_03_canonical_platform.png"},
	{"time": 34.0, "file": "intro_04_last_bridge.png"},
	{"time": 43.0, "file": "intro_05_title.png"},
]


func _ready() -> void:
	_remove_test_saves()
	SaveManager.configure_paths(TEST_SAVE, TEST_PENDING, TEST_BACKUP)
	var game = GameRootScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	if not await _configure_native_capture(game):
		return
	if not game.start_new_campaign("standard", 808, false, true):
		_fail("Could not create the snapshot campaign.")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var intro = game.current_scene
	if intro == null or intro.name != "IntroScene" or not intro.has_method("set_timeline_time_for_tests"):
		_fail("IntroScene or its deterministic timeline hook is unavailable.")
		return

	var output_directory := ProjectSettings.globalize_path("res://tmp")
	if not DirAccess.dir_exists_absolute(output_directory):
		var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
		if directory_error != OK:
			_fail("Could not create the snapshot directory (error %d)." % directory_error)
			return
	for beat: Dictionary in BEATS:
		intro.call("set_timeline_time_for_tests", float(beat["time"]))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		if image == null or image.is_empty():
			_fail("The rendered viewport is unavailable.")
			return
		if image.get_size() != CAPTURE_RESOLUTION:
			_fail("The rendered viewport has invalid size %s instead of %s." % [str(image.get_size()), str(CAPTURE_RESOLUTION)])
			return
		var error := image.save_png(output_directory.path_join(str(beat["file"])))
		if error != OK:
			_fail("Could not save %s (error %d)." % [str(beat["file"]), error])
			return

	game.free()
	await get_tree().process_frame
	_cleanup()
	print("Intro visual snapshots saved: five deterministic story beats.")
	get_tree().quit(0)


func _configure_native_capture(game: Node) -> bool:
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		_fail("Intro visual snapshots require a native, non-embedded Godot window.")
		return false
	var settings: Dictionary = game.user_settings.snapshot()
	var display: Dictionary = settings.get("display", {}).duplicate(true)
	display["mode"] = "windowed"
	display["resolution"] = CAPTURE_RESOLUTION
	display["vsync"] = false
	display["max_fps"] = 0
	settings["display"] = display
	if game.user_settings.apply(settings, false) != OK:
		_fail("Could not apply the canonical intro capture settings.")
		return false
	for _frame in range(30):
		await get_tree().process_frame
		if get_viewport().get_texture().get_size() == Vector2(CAPTURE_RESOLUTION):
			return true
	_fail("The intro capture target did not reach 1280x720.")
	return false


func _fail(message: String) -> void:
	push_error("Intro visual snapshot failed: " + message)
	_cleanup()
	get_tree().quit(1)


func _cleanup() -> void:
	_remove_test_saves()
	SaveManager.reset_paths()


func _remove_test_saves() -> void:
	for path in [TEST_SAVE, TEST_PENDING, TEST_BACKUP]:
		var absolute_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute_path):
			DirAccess.remove_absolute(absolute_path)
