extends SceneTree

const UserSettingsScript := preload("res://scripts/core/UserSettings.gd")

const TEST_PRIMARY := "user://test_native_window_settings.cfg"
const TEST_PENDING := "user://test_native_window_settings.pending.cfg"
const TEST_BACKUP := "user://test_native_window_settings.backup.cfg"
const VERIFY_FRAME_LIMIT := 45
const SAFE_RESOLUTION_PAIRS := [
	[Vector2i(1280, 720), Vector2i(1600, 900)],
	[Vector2i(960, 540), Vector2i(1280, 720)],
	[Vector2i(800, 450), Vector2i(960, 540)],
	[Vector2i(640, 360), Vector2i(800, 450)],
]

var _failed := false
var _initial_window_state: Dictionary = {}
var _window_state_captured := false


func _initialize() -> void:
	call_deferred("_run")


func _finalize() -> void:
	# Best-effort fallback for parser/runtime failures that interrupt _run() before
	# its awaited cleanup completes.
	_restore_initial_window_state_immediate()
	_cleanup_test_files()


func _run() -> void:
	await process_frame
	_capture_initial_window_state()
	_cleanup_test_files()

	var settings = UserSettingsScript.new()
	settings.configure_paths(TEST_PRIMARY, TEST_PENDING, TEST_BACKUP)
	settings.initialize(self, false)
	var capability: Dictionary = settings.display_geometry_capability()
	if not bool(capability.get("supported", false)):
		print("Native window settings test SKIP: %s" % str(capability.get("reason", "unsupported display environment")))
		await _restore_initial_window_state()
		_cleanup_test_files()
		quit(0)
		return

	var resolutions := _select_safe_resolution_pair()
	if resolutions.size() != 2:
		print("Native window settings test SKIP: current screen has no two safe client resolutions.")
		await _restore_initial_window_state()
		_cleanup_test_files()
		quit(0)
		return

	var base_snapshot: Dictionary = settings.snapshot()
	var first_candidate := _candidate_with_display(base_snapshot, "windowed", resolutions[0])
	var second_candidate := _candidate_with_display(base_snapshot, "windowed", resolutions[1])
	var borderless_candidate := _candidate_with_display(base_snapshot, "borderless", resolutions[1])

	var first_verification: Dictionary = await _apply_and_wait(settings, first_candidate, "first safe windowed resolution")
	_assert_verified_windowed(first_verification, resolutions[0], "first safe windowed resolution")

	var second_verification: Dictionary = await _apply_and_wait(settings, second_candidate, "second safe windowed resolution")
	_assert_verified_windowed(second_verification, resolutions[1], "second safe windowed resolution")
	_assert(DisplayServer.window_get_size() != resolutions[0], "The second native resize must measurably differ from the first one.")

	var first_rollback: Dictionary = await _apply_and_wait(settings, first_candidate, "windowed rollback")
	_assert_verified_windowed(first_rollback, resolutions[0], "windowed rollback")

	var borderless_verification: Dictionary = await _apply_and_wait(settings, borderless_candidate, "borderless fullscreen")
	_assert(bool(borderless_verification.get("supported", false)) and bool(borderless_verification.get("matches", false)), "Borderless output must be confirmed by UserSettings.verify_display_output().")
	_assert(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Borderless mode must reach the real fullscreen window mode.")
	var fullscreen_size := DisplayServer.window_get_size()
	var fullscreen_screen := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(fullscreen_screen)
	_assert(
		fullscreen_size.x == screen_size.x and absi(fullscreen_size.y - screen_size.y) <= 1,
		"Borderless fullscreen must use the current screen size (allowing Godot's one-pixel Windows fullscreen margin)."
	)

	var fullscreen_rollback: Dictionary = await _apply_and_wait(settings, first_candidate, "fullscreen rollback")
	_assert_verified_windowed(fullscreen_rollback, resolutions[0], "fullscreen rollback")

	await _restore_initial_window_state()
	_cleanup_test_files()
	if _failed:
		quit(1)
		return
	print("Native window settings test passed: two client sizes, borderless fullscreen and rollback match DisplayServer state.")
	quit(0)


func _candidate_with_display(base_snapshot: Dictionary, mode: String, resolution: Vector2i) -> Dictionary:
	var candidate := base_snapshot.duplicate(true)
	var display: Dictionary = candidate.get("display", {}).duplicate(true)
	display["mode"] = mode
	display["resolution"] = resolution
	candidate["display"] = display
	return candidate


func _apply_and_wait(settings, candidate: Dictionary, context: String) -> Dictionary:
	var apply_error := int(settings.apply(candidate.duplicate(true), false))
	_assert(apply_error == OK, "Applying %s must succeed (error %d)." % [context, apply_error])
	if apply_error != OK:
		return {}
	var expected: Dictionary = candidate.get("display", {}).duplicate(true)
	var verification: Dictionary = {}
	for _frame in range(VERIFY_FRAME_LIMIT):
		await process_frame
		verification = settings.verify_display_output(expected)
		if bool(verification.get("supported", false)) and bool(verification.get("matches", false)):
			break
	return verification


func _assert_verified_windowed(verification: Dictionary, expected_size: Vector2i, context: String) -> void:
	_assert(bool(verification.get("supported", false)), "%s must remain supported by the native display backend." % context.capitalize())
	_assert(bool(verification.get("matches", false)), "%s must be confirmed by UserSettings.verify_display_output(): %s" % [context.capitalize(), str(verification.get("reason", ""))])
	_assert(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "%s must use the real windowed mode." % context.capitalize())
	_assert(not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS), "%s must restore native decorations." % context.capitalize())
	_assert(DisplayServer.window_get_size() == expected_size, "%s must measure exactly %s through DisplayServer.window_get_size()." % [context.capitalize(), expected_size])


func _select_safe_resolution_pair() -> Array:
	if DisplayServer.get_screen_count() <= 0:
		return []
	var screen := clampi(DisplayServer.window_get_current_screen(), 0, DisplayServer.get_screen_count() - 1)
	var usable_size := DisplayServer.screen_get_usable_rect(screen).size
	var client_size := DisplayServer.window_get_size()
	var decorated_size := DisplayServer.window_get_size_with_decorations()
	var decoration_size := Vector2i(
		maxi(decorated_size.x - client_size.x, 0),
		maxi(decorated_size.y - client_size.y, 0)
	)
	# Keep an additional margin so the test never places a decorated window flush
	# against the taskbar or a screen edge.
	var safe_client_limit := usable_size - decoration_size - Vector2i(32, 32)
	for pair in SAFE_RESOLUTION_PAIRS:
		var first: Vector2i = pair[0]
		var second: Vector2i = pair[1]
		if first.x <= safe_client_limit.x and first.y <= safe_client_limit.y and second.x <= safe_client_limit.x and second.y <= safe_client_limit.y:
			return [first, second]
	return []


func _capture_initial_window_state() -> void:
	if DisplayServer.get_name() == "headless" or root == null:
		return
	var window_id := root.get_window_id()
	_initial_window_state = {
		"window_id": window_id,
		"mode": int(DisplayServer.window_get_mode(window_id)),
		"size": DisplayServer.window_get_size(window_id),
		"position": DisplayServer.window_get_position(window_id),
		"borderless": DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, window_id),
	}
	_window_state_captured = true


func _restore_initial_window_state() -> void:
	if not _window_state_captured:
		return
	var window_id := int(_initial_window_state["window_id"])
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED, window_id)
	await process_frame
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false, window_id)
	DisplayServer.window_set_size(_initial_window_state["size"], window_id)
	DisplayServer.window_set_position(_initial_window_state["position"], window_id)
	await process_frame
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, bool(_initial_window_state["borderless"]), window_id)
	DisplayServer.window_set_mode(int(_initial_window_state["mode"]), window_id)
	if int(_initial_window_state["mode"]) == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(_initial_window_state["size"], window_id)
		DisplayServer.window_set_position(_initial_window_state["position"], window_id)
	await process_frame


func _restore_initial_window_state_immediate() -> void:
	if not _window_state_captured or DisplayServer.get_name() == "headless":
		return
	var window_id := int(_initial_window_state["window_id"])
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED, window_id)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false, window_id)
	DisplayServer.window_set_size(_initial_window_state["size"], window_id)
	DisplayServer.window_set_position(_initial_window_state["position"], window_id)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, bool(_initial_window_state["borderless"]), window_id)
	DisplayServer.window_set_mode(int(_initial_window_state["mode"]), window_id)


func _cleanup_test_files() -> void:
	for path in [TEST_PRIMARY, TEST_PENDING, TEST_BACKUP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Native window settings test failed: " + message)
