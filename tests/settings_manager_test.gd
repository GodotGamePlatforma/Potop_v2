extends SceneTree

const UserSettingsScript := preload("res://scripts/core/UserSettings.gd")

const TEST_PRIMARY := "user://test_user_settings.cfg"
const TEST_PENDING := "user://test_user_settings.pending.cfg"
const TEST_BACKUP := "user://test_user_settings.backup.cfg"
const TEST_BLOCKED_PRIMARY := "user://test_user_settings_blocked_primary"
const TEST_BLOCKED_PENDING := "user://test_user_settings_blocked.pending.cfg"
const TEST_BLOCKED_BACKUP := "user://test_user_settings_blocked.backup.cfg"

var _failed := false
var _settings_applied_count := 0
var _original_max_fps := 0
var _original_msaa := Viewport.MSAA_DISABLED
var _original_master_volume := 1.0
var _original_master_muted := false
var _original_actions: Dictionary = {}


func _initialize() -> void:
	_capture_runtime_state()
	_cleanup_test_files()

	var settings = UserSettingsScript.new()
	settings.configure_paths(TEST_PRIMARY, TEST_PENDING, TEST_BACKUP)
	settings.settings_applied.connect(_on_settings_applied)
	settings.initialize(self, false)

	_test_defaults_are_deep_and_complete(settings)
	_test_sanitization(settings)
	var first_snapshot := _test_runtime_apply_and_audio_preview(settings)
	var second_snapshot := _test_atomic_round_trip_and_fallbacks(settings, first_snapshot)
	_test_failed_promotion_does_not_resurrect_pending(settings)
	_test_reset_paths(settings)

	# The second committed snapshot is intentionally read so the optimizer and
	# static analyzer cannot treat the fallback test as write-only.
	_assert(not second_snapshot.is_empty(), "Round-trip should return a non-empty settings snapshot.")
	_restore_runtime_state()
	_cleanup_test_files()
	_finish()


func _test_defaults_are_deep_and_complete(settings) -> void:
	var defaults: Dictionary = settings.defaults_snapshot()
	for section in ["display", "graphics", "audio", "accessibility", "controls"]:
		_assert(defaults.has(section), "Defaults must contain the %s section." % section)
	var controls: Dictionary = defaults.get("controls", {})
	for action in UserSettingsScript.MANAGED_ACTIONS:
		var action_id := str(action)
		_assert(controls.has(action_id), "Defaults must capture managed action %s." % action_id)
		var records: Array = controls.get(action_id, [])
		_assert(not records.is_empty() and records.size() <= 2, "Managed action %s must have one or two captured key bindings." % action_id)
	_assert(int(controls["dive_light_toggle"][0]["keycode"]) == KEY_F, "The managed light toggle must capture F as its project default.")
	_assert(
		int(controls["dive_quiet_repair"][0]["keycode"]) == KEY_R
		and bool(controls["dive_quiet_repair"][0]["shift_pressed"]),
		"The managed quiet-repair action must capture SHIFT+R including its modifier."
	)

	var changed_copy: Dictionary = settings.defaults_snapshot()
	var changed_display: Dictionary = changed_copy["display"]
	changed_display["max_fps"] = 333
	changed_copy["display"] = changed_display
	_assert(int(settings.defaults_snapshot()["display"]["max_fps"]) != 333, "defaults_snapshot() must return a deep copy.")


func _test_sanitization(settings) -> void:
	var defaults: Dictionary = settings.defaults_snapshot()
	var candidate := {
		"display": {
			"mode": "exclusive",
			"resolution": Vector2i(12, 9000),
			"vsync": "yes",
			"max_fps": -50,
		},
		"graphics": {"quality": "ultra"},
		"audio": {"master_volume": 4.0, "master_muted": "no"},
		"accessibility": {"reduced_motion": 1, "pause_on_focus_loss": true},
		"controls": {
			"dive_left": [
				{"type": "mouse", "keycode": KEY_Q},
				_key_record(KEY_Q),
				_key_record(KEY_Q),
				_key_record(KEY_E),
				_key_record(KEY_T),
			],
		},
	}
	var sanitized: Dictionary = settings.sanitize(candidate)
	_assert(str(sanitized["display"]["mode"]) == str(defaults["display"]["mode"]), "Unknown display modes must fall back to the project default.")
	_assert(sanitized["display"]["resolution"] == Vector2i(640, 4320), "Resolution must be clamped to the supported safety range.")
	_assert(bool(sanitized["display"]["vsync"]) == bool(defaults["display"]["vsync"]), "Non-boolean VSync values must be rejected.")
	_assert(int(sanitized["display"]["max_fps"]) == 0, "Negative frame limits must normalize to unlimited.")
	_assert(str(sanitized["graphics"]["quality"]) == str(defaults["graphics"]["quality"]), "Unknown graphics quality must fall back to the project default.")
	_assert(is_equal_approx(float(sanitized["audio"]["master_volume"]), 1.0), "Master volume must be clamped to one.")
	_assert(bool(sanitized["audio"]["master_muted"]) == bool(defaults["audio"]["master_muted"]), "Non-boolean mute values must be rejected.")
	_assert(bool(sanitized["accessibility"]["reduced_motion"]) == bool(defaults["accessibility"]["reduced_motion"]), "Non-boolean reduced motion values must be rejected.")
	var left_records: Array = sanitized["controls"]["dive_left"]
	_assert(left_records.size() == 2, "Controls must keep at most two unique valid key records.")
	_assert(int(left_records[0]["keycode"]) == KEY_Q and int(left_records[1]["keycode"]) == KEY_E, "Invalid and duplicate key records must be discarded in stable order.")


func _test_runtime_apply_and_audio_preview(settings) -> Dictionary:
	var candidate: Dictionary = settings.defaults_snapshot()
	var display: Dictionary = candidate["display"]
	display["max_fps"] = 137
	display["mode"] = "borderless"
	display["resolution"] = Vector2i(1600, 900)
	display["vsync"] = false
	candidate["display"] = display
	var graphics: Dictionary = candidate["graphics"]
	graphics["quality"] = "high"
	candidate["graphics"] = graphics
	var audio: Dictionary = candidate["audio"]
	audio["master_volume"] = 0.42
	audio["master_muted"] = false
	candidate["audio"] = audio
	var accessibility: Dictionary = candidate["accessibility"]
	accessibility["reduced_motion"] = true
	accessibility["pause_on_focus_loss"] = true
	candidate["accessibility"] = accessibility
	var controls: Dictionary = candidate["controls"]
	controls["dive_left"] = [_key_record(KEY_Q)]
	controls["dive_light_toggle"] = [_key_record(KEY_G)]
	controls["open_mission_journal"] = [_key_record(KEY_M, true)]
	controls["open_day_reports"] = [_key_record(KEY_P)]
	candidate["controls"] = controls

	var previous_signal_count := _settings_applied_count
	_assert(settings.apply(candidate, false) == OK, "Applying sanitized settings without persistence must succeed.")
	_assert(_settings_applied_count == previous_signal_count + 1, "Successful apply must emit settings_applied exactly once.")
	_assert(Engine.max_fps == 137, "Display frame limit must be applied to Engine.max_fps even in headless tests.")
	_assert(root.msaa_2d == Viewport.MSAA_4X, "High graphics quality must map to 4x 2D MSAA.")
	_assert(bool(settings.get_value("accessibility", "reduced_motion", false)), "get_value() must read the current sanitized section value.")
	_assert(_action_has_key(&"dive_left", KEY_Q, false), "Runtime InputMap must receive the remapped dive action.")
	_assert(_action_has_key(&"dive_light_toggle", KEY_G, false), "Runtime InputMap must receive the remapped light-toggle action.")
	_assert(_action_has_key(&"open_mission_journal", KEY_M, true), "Runtime InputMap must receive the remapped mission journal action.")
	_assert(_action_has_key(&"open_day_reports", KEY_P, false), "Runtime InputMap must receive the remapped day reports action.")
	_test_focus_pause_ownership(settings)

	var master_bus := AudioServer.get_bus_index(&"Master")
	_assert(master_bus >= 0, "Godot must expose the built-in Master bus.")
	if master_bus >= 0:
		_assert(is_equal_approx(AudioServer.get_bus_volume_linear(master_bus), 0.42), "Apply must set the Master bus linear volume.")
		_assert(not AudioServer.is_bus_mute(master_bus), "Apply must set the Master bus mute state.")
		settings.preview_audio({"master_volume": 0.17, "master_muted": true})
		_assert(is_equal_approx(AudioServer.get_bus_volume_linear(master_bus), 0.17) and AudioServer.is_bus_mute(master_bus), "preview_audio() must change the real Master bus without changing the snapshot.")
		_assert(is_equal_approx(float(settings.snapshot()["audio"]["master_volume"]), 0.42), "Audio preview must not mutate the committed settings snapshot.")
		settings.preview_audio(settings.snapshot()["audio"])
		_assert(is_equal_approx(AudioServer.get_bus_volume_linear(master_bus), 0.42) and not AudioServer.is_bus_mute(master_bus), "Audio preview must be restorable from snapshot().")
	return settings.snapshot()


func _test_focus_pause_ownership(settings) -> void:
	paused = false
	settings.call("_on_window_focus_exited")
	_assert(paused, "Enabled focus-loss handling should pause an active tree.")
	settings.call("_on_window_focus_entered")
	_assert(not paused, "Focus return should resume a tree paused by UserSettings itself.")
	paused = true
	settings.call("_on_window_focus_exited")
	settings.call("_on_window_focus_entered")
	_assert(paused, "Focus return must not resume a tree that was already paused by another system.")
	paused = false


func _test_atomic_round_trip_and_fallbacks(settings, first_snapshot: Dictionary) -> Dictionary:
	_assert(settings.save_current() == OK, "The first atomic settings save must succeed.")
	_assert(FileAccess.file_exists(TEST_PRIMARY), "A successful save must install the primary config.")
	_assert(not FileAccess.file_exists(TEST_PENDING), "A successful save must not leave the pending config behind.")

	var second_candidate := first_snapshot.duplicate(true)
	var second_audio: Dictionary = second_candidate["audio"]
	second_audio["master_volume"] = 0.73
	second_audio["master_muted"] = true
	second_candidate["audio"] = second_audio
	var second_controls: Dictionary = second_candidate["controls"]
	second_controls["open_mission_journal"] = [_key_record(KEY_K)]
	second_controls["open_day_reports"] = [_key_record(KEY_L, true)]
	second_candidate["controls"] = second_controls
	_assert(settings.apply(second_candidate, true) == OK, "Applying and atomically persisting the second snapshot must succeed.")
	var second_snapshot: Dictionary = settings.snapshot()
	_assert(FileAccess.file_exists(TEST_BACKUP), "The second save must rotate the previous valid primary into backup.")

	var copied_primary := ConfigFile.new()
	_assert(copied_primary.load(TEST_PRIMARY) == OK and copied_primary.save(TEST_PENDING) == OK, "The test must be able to create a valid pending recovery candidate.")
	_write_invalid_schema(TEST_PRIMARY)
	_assert(settings.load_current(true) == OK, "A corrupt primary must recover from a valid pending config.")
	_assert(is_equal_approx(float(settings.snapshot()["audio"]["master_volume"]), 0.73), "Pending recovery must win before backup.")
	_assert(_action_has_key(&"open_mission_journal", KEY_K, false), "Pending recovery must restore the mission journal binding.")
	_assert(_action_has_key(&"open_day_reports", KEY_L, true), "Pending recovery must restore the day reports binding.")

	_remove_test_file(TEST_PENDING)
	_assert(settings.load_current(true) == OK, "A corrupt primary without pending must recover from backup.")
	_assert(is_equal_approx(float(settings.snapshot()["audio"]["master_volume"]), float(first_snapshot["audio"]["master_volume"])), "Backup recovery must restore the previous committed snapshot.")
	_assert(_action_has_key(&"open_mission_journal", KEY_M, true), "Backup recovery must round-trip the prior mission journal binding.")
	_assert(_action_has_key(&"open_day_reports", KEY_P, false), "Backup recovery must round-trip the prior day reports binding.")

	_write_invalid_schema(TEST_BACKUP)
	_assert(settings.load_current(false) == ERR_INVALID_DATA, "When every existing candidate is invalid, load_current() must report invalid data.")
	_assert(settings.snapshot() == settings.defaults_snapshot(), "Invalid primary, pending and backup must fall back to deep project defaults.")
	return second_snapshot


func _test_failed_promotion_does_not_resurrect_pending(settings) -> void:
	var blocked_primary_absolute := ProjectSettings.globalize_path(TEST_BLOCKED_PRIMARY)
	_remove_test_file(TEST_BLOCKED_PENDING)
	_remove_test_file(TEST_BLOCKED_BACKUP)
	if DirAccess.dir_exists_absolute(blocked_primary_absolute):
		DirAccess.remove_absolute(blocked_primary_absolute)
	_assert(DirAccess.make_dir_absolute(blocked_primary_absolute) == OK, "The test must create a directory that blocks the final pending-to-primary rename.")

	settings.configure_paths(TEST_BLOCKED_PRIMARY, TEST_BLOCKED_PENDING, TEST_BLOCKED_BACKUP)
	var previous: Dictionary = settings.snapshot()
	var candidate := previous.duplicate(true)
	var audio: Dictionary = candidate["audio"]
	audio["master_volume"] = 0.19
	candidate["audio"] = audio
	var save_error := int(settings.apply(candidate, true))
	_assert(save_error != OK, "A primary path occupied by a directory must fail the final settings promotion.")
	_assert(settings.snapshot() == previous, "A failed persistent apply must restore the previous runtime snapshot.")
	_assert(not FileAccess.file_exists(TEST_BLOCKED_PENDING), "A failed final promotion must remove pending so it cannot be resurrected on the next load.")
	_assert(settings.load_current(false) == OK, "With no valid primary, pending or backup, loading after a failed promotion should fall back safely.")
	_assert(settings.snapshot() == settings.defaults_snapshot(), "A failed promotion must not become a valid recovery candidate on the next load.")

	settings.configure_paths(TEST_PRIMARY, TEST_PENDING, TEST_BACKUP)
	DirAccess.remove_absolute(blocked_primary_absolute)
	_remove_test_file(TEST_BLOCKED_PENDING)
	_remove_test_file(TEST_BLOCKED_BACKUP)


func _test_reset_paths(settings) -> void:
	settings.reset_paths()
	_assert(settings.primary_path == UserSettingsScript.SETTINGS_PATH, "reset_paths() must restore the production primary path.")
	_assert(settings.pending_path == UserSettingsScript.PENDING_SETTINGS_PATH, "reset_paths() must restore the production pending path.")
	_assert(settings.backup_path == UserSettingsScript.BACKUP_SETTINGS_PATH, "reset_paths() must restore the production backup path.")
	settings.configure_paths(TEST_PRIMARY, TEST_PENDING, TEST_BACKUP)


func _key_record(keycode: int, ctrl_pressed: bool = false) -> Dictionary:
	return {
		"type": "key",
		"keycode": keycode,
		"physical_keycode": 0,
		"unicode": keycode if keycode < 128 else 0,
		"shift_pressed": false,
		"alt_pressed": false,
		"ctrl_pressed": ctrl_pressed,
		"meta_pressed": false,
	}


func _action_has_key(action: StringName, keycode: int, ctrl_pressed: bool) -> bool:
	if not InputMap.has_action(action):
		return false
	for input_event in InputMap.action_get_events(action):
		if input_event is InputEventKey:
			var key_event := input_event as InputEventKey
			if int(key_event.keycode) == keycode and bool(key_event.ctrl_pressed) == ctrl_pressed:
				return true
	return false


func _capture_runtime_state() -> void:
	_original_max_fps = Engine.max_fps
	_original_msaa = root.msaa_2d
	var master_bus := AudioServer.get_bus_index(&"Master")
	if master_bus >= 0:
		_original_master_volume = AudioServer.get_bus_volume_linear(master_bus)
		_original_master_muted = AudioServer.is_bus_mute(master_bus)
	for action in UserSettingsScript.MANAGED_ACTIONS:
		var records: Array = []
		if InputMap.has_action(action):
			for input_event in InputMap.action_get_events(action):
				records.append(input_event.duplicate(true))
		_original_actions[str(action)] = {
			"existed": InputMap.has_action(action),
			"events": records,
		}


func _restore_runtime_state() -> void:
	Engine.max_fps = _original_max_fps
	root.msaa_2d = _original_msaa
	var master_bus := AudioServer.get_bus_index(&"Master")
	if master_bus >= 0:
		AudioServer.set_bus_volume_linear(master_bus, _original_master_volume)
		AudioServer.set_bus_mute(master_bus, _original_master_muted)
	for action in UserSettingsScript.MANAGED_ACTIONS:
		var original: Dictionary = _original_actions.get(str(action), {})
		if not bool(original.get("existed", false)):
			if InputMap.has_action(action):
				InputMap.erase_action(action)
			continue
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.5)
		InputMap.action_erase_events(action)
		for input_event in original.get("events", []):
			InputMap.action_add_event(action, input_event)
	paused = false


func _write_invalid_schema(path: String) -> void:
	var invalid := ConfigFile.new()
	invalid.set_value("meta", "schema_version", UserSettingsScript.CURRENT_SCHEMA_VERSION + 1)
	_assert(invalid.save(path) == OK, "The test must be able to write an invalid-schema fixture.")


func _cleanup_test_files() -> void:
	for path in [TEST_PRIMARY, TEST_PENDING, TEST_BACKUP, TEST_BLOCKED_PENDING, TEST_BLOCKED_BACKUP]:
		_remove_test_file(path)
	var blocked_primary_absolute := ProjectSettings.globalize_path(TEST_BLOCKED_PRIMARY)
	if DirAccess.dir_exists_absolute(blocked_primary_absolute):
		DirAccess.remove_absolute(blocked_primary_absolute)


func _remove_test_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _on_settings_applied(_snapshot: Dictionary) -> void:
	_settings_applied_count += 1


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Settings manager test failed: " + message)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("Settings manager test passed: defaults, sanitization, runtime application, controls, audio, focus pause and atomic recovery are valid.")
	quit(0)
