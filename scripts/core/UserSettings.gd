class_name UserSettings
extends RefCounted

signal settings_applied(settings: Dictionary)

const CURRENT_SCHEMA_VERSION := 1
const SETTINGS_PATH := "user://ostatni_pomost_settings.cfg"
const PENDING_SETTINGS_PATH := "user://ostatni_pomost_settings.pending.cfg"
const BACKUP_SETTINGS_PATH := "user://ostatni_pomost_settings.backup.cfg"

const DISPLAY_MODE_WINDOWED := "windowed"
const DISPLAY_MODE_BORDERLESS := "borderless"
const QUALITY_LOW := "low"
const QUALITY_MEDIUM := "medium"
const QUALITY_HIGH := "high"

const MANAGED_ACTIONS: Array[StringName] = [
	&"dive_left",
	&"dive_right",
	&"dive_up",
	&"dive_down",
	&"dive_interact",
	&"dive_sprint",
	&"dive_repair",
	&"dive_quiet_repair",
	&"dive_light_toggle",
	&"dive_inventory",
	&"dive_weapon_knife",
	&"dive_weapon_ranged",
	&"open_mission_journal",
	&"open_day_reports",
]

const FALLBACK_ACTION_KEYS := {
	"dive_light_toggle": KEY_F,
	"dive_weapon_knife": KEY_1,
	"dive_weapon_ranged": KEY_2,
	"open_mission_journal": KEY_J,
	"open_day_reports": KEY_R,
}

const MIN_RESOLUTION := Vector2i(640, 360)
const MAX_RESOLUTION := Vector2i(7680, 4320)
const MAX_BINDINGS_PER_ACTION := 2
const MAX_FRAME_LIMIT := 1000

var primary_path: String = SETTINGS_PATH
var pending_path: String = PENDING_SETTINGS_PATH
var backup_path: String = BACKUP_SETTINGS_PATH

var _tree: SceneTree
var _defaults: Dictionary = {}
var _current: Dictionary = {}
var _pause_on_focus_loss := false
var _paused_by_focus_loss := false


func initialize(tree: SceneTree, load_from_disk: bool = true) -> void:
	_tree = tree
	_capture_project_defaults()
	_current = _defaults.duplicate(true)
	_connect_window_focus_signals()
	if load_from_disk:
		load_current(true)
	else:
		_apply_current_runtime()
		settings_applied.emit(snapshot())


func snapshot() -> Dictionary:
	_ensure_defaults()
	if _current.is_empty():
		_current = _defaults.duplicate(true)
	return _current.duplicate(true)


func defaults_snapshot() -> Dictionary:
	_ensure_defaults()
	return _defaults.duplicate(true)


func display_geometry_capability() -> Dictionary:
	var headless := DisplayServer.get_name() == "headless"
	var embedded := Engine.is_embedded_in_editor()
	var reason := ""
	if headless:
		reason = "Zmiana geometrii okna jest niedostępna w trybie headless."
	elif embedded:
		reason = "Zmiana geometrii okna jest niedostępna, gdy gra jest osadzona w edytorze Godot."
	elif _tree == null or _tree.root == null:
		reason = "Brak aktywnego głównego okna gry."
	return {
		"supported": reason.is_empty(),
		"embedded": embedded,
		"headless": headless,
		"reason": reason,
	}


func display_output_state() -> Dictionary:
	var state := {
		"mode": "",
		"window_mode": -1,
		"borderless": false,
		"resolution": Vector2i.ZERO,
	}
	if _tree == null or _tree.root == null or DisplayServer.get_name() == "headless":
		return state
	var window_id := _tree.root.get_window_id()
	var window_mode := int(DisplayServer.window_get_mode(window_id))
	state["window_mode"] = window_mode
	match window_mode:
		Window.MODE_FULLSCREEN:
			state["mode"] = DISPLAY_MODE_BORDERLESS
		Window.MODE_EXCLUSIVE_FULLSCREEN:
			state["mode"] = "exclusive_fullscreen"
		_:
			state["mode"] = DISPLAY_MODE_WINDOWED
	state["borderless"] = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, window_id)
	state["resolution"] = DisplayServer.window_get_size(window_id)
	return state


func verify_display_output(expected_display) -> Dictionary:
	var expected_source := _as_dictionary(expected_display)
	if expected_source.has("display"):
		expected_source = _section(expected_source, "display")
	var sanitized := sanitize({"display": expected_source})
	var expected: Dictionary = (sanitized["display"] as Dictionary).duplicate(true)
	var actual := display_output_state()
	var capability := display_geometry_capability()
	var result := {
		"supported": bool(capability["supported"]),
		"matches": false,
		"expected": expected,
		"actual": actual,
		"reason": str(capability["reason"]),
	}
	if not bool(capability["supported"]):
		return result

	var actual_window_mode := int(actual["window_mode"])
	if str(expected["mode"]) == DISPLAY_MODE_BORDERLESS:
		result["matches"] = actual_window_mode == Window.MODE_FULLSCREEN
		if not bool(result["matches"]):
			result["reason"] = "Rzeczywisty tryb okna nie jest pełnym ekranem bez ramek."
		return result

	result["matches"] = (
		actual_window_mode == Window.MODE_WINDOWED
		and not bool(actual["borderless"])
		and actual["resolution"] == expected["resolution"]
	)
	if not bool(result["matches"]):
		result["reason"] = "Rzeczywisty tryb lub rozmiar okna nie odpowiada wybranym ustawieniom."
	return result


func sanitize(candidate) -> Dictionary:
	_ensure_defaults()
	var source := _as_dictionary(candidate)
	var sanitized := _defaults.duplicate(true)

	var display_source := _section(source, "display")
	var display_defaults: Dictionary = _defaults["display"]
	var display_mode := str(display_source.get("mode", display_defaults["mode"]))
	if display_mode not in [DISPLAY_MODE_WINDOWED, DISPLAY_MODE_BORDERLESS]:
		display_mode = str(display_defaults["mode"])
	var resolution := display_defaults["resolution"] as Vector2i
	var requested_resolution = display_source.get("resolution", resolution)
	if typeof(requested_resolution) == TYPE_VECTOR2I:
		resolution = Vector2i(
			clampi(requested_resolution.x, MIN_RESOLUTION.x, MAX_RESOLUTION.x),
			clampi(requested_resolution.y, MIN_RESOLUTION.y, MAX_RESOLUTION.y)
		)
	sanitized["display"] = {
		"mode": display_mode,
		"resolution": resolution,
		"vsync": _strict_bool(display_source.get("vsync"), bool(display_defaults["vsync"])),
		"max_fps": clampi(
			_numeric_int(display_source.get("max_fps"), int(display_defaults["max_fps"])),
			0,
			MAX_FRAME_LIMIT
		),
	}

	var graphics_source := _section(source, "graphics")
	var graphics_defaults: Dictionary = _defaults["graphics"]
	var quality := str(graphics_source.get("quality", graphics_defaults["quality"]))
	if quality not in [QUALITY_LOW, QUALITY_MEDIUM, QUALITY_HIGH]:
		quality = str(graphics_defaults["quality"])
	sanitized["graphics"] = {"quality": quality}

	var audio_source := _section(source, "audio")
	var audio_defaults: Dictionary = _defaults["audio"]
	sanitized["audio"] = {
		"master_volume": clampf(
			_numeric_float(audio_source.get("master_volume"), float(audio_defaults["master_volume"])),
			0.0,
			1.0
		),
		"master_muted": _strict_bool(audio_source.get("master_muted"), bool(audio_defaults["master_muted"])),
	}

	var accessibility_source := _section(source, "accessibility")
	var accessibility_defaults: Dictionary = _defaults["accessibility"]
	sanitized["accessibility"] = {
		"reduced_motion": _strict_bool(
			accessibility_source.get("reduced_motion"),
			bool(accessibility_defaults["reduced_motion"])
		),
		"pause_on_focus_loss": _strict_bool(
			accessibility_source.get("pause_on_focus_loss"),
			bool(accessibility_defaults["pause_on_focus_loss"])
		),
	}

	var controls_source := _section(source, "controls")
	var controls_defaults: Dictionary = _defaults["controls"]
	var controls: Dictionary = {}
	for action in MANAGED_ACTIONS:
		var action_id := str(action)
		var fallback_records: Array = controls_defaults.get(action_id, [])
		controls[action_id] = _sanitize_key_records(
			controls_source.get(action_id, fallback_records),
			fallback_records
		)
	sanitized["controls"] = controls
	return sanitized


func apply(candidate, persist: bool = false) -> Error:
	var previous := snapshot()
	_current = sanitize(candidate)
	_apply_current_runtime()
	if persist:
		var save_error := save_current()
		if save_error != OK:
			_current = previous
			_apply_current_runtime()
			return save_error
	settings_applied.emit(snapshot())
	return OK


func save_current() -> Error:
	_ensure_defaults()
	if _current.is_empty():
		_current = _defaults.duplicate(true)
	_current = sanitize(_current)

	var config := ConfigFile.new()
	config.set_value("meta", "schema_version", CURRENT_SCHEMA_VERSION)
	for section_name in ["display", "graphics", "audio", "accessibility"]:
		var section: Dictionary = _current[section_name]
		for key in section.keys():
			config.set_value(section_name, str(key), section[key])
	var controls: Dictionary = _current["controls"]
	for action in MANAGED_ACTIONS:
		var action_id := str(action)
		config.set_value("controls", action_id, controls.get(action_id, []))

	var save_error := config.save(pending_path)
	if save_error != OK:
		return save_error
	var pending_result := _read_valid_settings(pending_path)
	if int(pending_result.get("error", ERR_INVALID_DATA)) != OK or pending_result.get("settings", {}) != _current:
		_remove_if_exists(pending_path)
		return ERR_INVALID_DATA

	var primary_absolute := ProjectSettings.globalize_path(primary_path)
	var pending_absolute := ProjectSettings.globalize_path(pending_path)
	var backup_absolute := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(primary_path):
		var primary_result := _read_valid_settings(primary_path)
		if int(primary_result.get("error", ERR_INVALID_DATA)) == OK:
			if FileAccess.file_exists(backup_path):
				var remove_backup_error := DirAccess.remove_absolute(backup_absolute)
				if remove_backup_error != OK:
					_remove_if_exists(pending_path)
					return remove_backup_error
			var rotate_error := DirAccess.rename_absolute(primary_absolute, backup_absolute)
			if rotate_error != OK:
				_remove_if_exists(pending_path)
				return rotate_error
		else:
			var remove_invalid_error := DirAccess.remove_absolute(primary_absolute)
			if remove_invalid_error != OK:
				_remove_if_exists(pending_path)
				return remove_invalid_error

	var replace_error := DirAccess.rename_absolute(pending_absolute, primary_absolute)
	if replace_error != OK:
		# Nieudana promocja nie może zostawić poprawnego pending jako kandydata,
		# którego load_current() potraktuje przy następnym uruchomieniu jak zapisany.
		_remove_if_exists(pending_path)
		if not FileAccess.file_exists(primary_path) and FileAccess.file_exists(backup_path):
			var restore_error := DirAccess.copy_absolute(backup_absolute, primary_absolute)
			if restore_error != OK:
				push_warning(
					"UserSettings: nie udało się odtworzyć primary z backup po błędzie promocji (kod %d)." % restore_error
				)
		return replace_error
	return OK


func load_current(apply_runtime: bool = true) -> Error:
	_ensure_defaults()
	var found_any_file := false
	for path in [primary_path, pending_path, backup_path]:
		var result := _read_valid_settings(path)
		if bool(result.get("exists", false)):
			found_any_file = true
		if int(result.get("error", ERR_FILE_NOT_FOUND)) != OK:
			continue
		_current = result["settings"].duplicate(true)
		if apply_runtime:
			_apply_current_runtime()
			settings_applied.emit(snapshot())
		return OK

	_current = _defaults.duplicate(true)
	if apply_runtime:
		_apply_current_runtime()
		settings_applied.emit(snapshot())
	return ERR_INVALID_DATA if found_any_file else OK


func preview_audio(audio_settings) -> void:
	_ensure_defaults()
	var source := _as_dictionary(audio_settings)
	var defaults: Dictionary = _defaults["audio"]
	var sanitized_audio := {
		"master_volume": clampf(
			_numeric_float(source.get("master_volume"), float(defaults["master_volume"])),
			0.0,
			1.0
		),
		"master_muted": _strict_bool(source.get("master_muted"), bool(defaults["master_muted"])),
	}
	_apply_audio(sanitized_audio)


func get_value(section: String, key: String, default = null):
	if not _current.has(section) or typeof(_current[section]) != TYPE_DICTIONARY:
		return default
	return (_current[section] as Dictionary).get(key, default)


func configure_paths(primary: String, pending: String, backup: String) -> void:
	if primary.is_empty() or pending.is_empty() or backup.is_empty():
		return
	if primary == pending or primary == backup or pending == backup:
		return
	primary_path = primary
	pending_path = pending
	backup_path = backup


func reset_paths() -> void:
	primary_path = SETTINGS_PATH
	pending_path = PENDING_SETTINGS_PATH
	backup_path = BACKUP_SETTINGS_PATH


func _capture_project_defaults() -> void:
	var viewport_width := maxi(int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)), 1)
	var viewport_height := maxi(int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)), 1)
	var configured_window_mode := int(ProjectSettings.get_setting("display/window/size/mode", Window.MODE_WINDOWED))
	var default_mode := DISPLAY_MODE_BORDERLESS if configured_window_mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN] else DISPLAY_MODE_WINDOWED
	var configured_vsync := int(ProjectSettings.get_setting("display/window/vsync/vsync_mode", DisplayServer.VSYNC_ENABLED))

	var master_volume := 1.0
	var master_muted := false
	var master_bus_index := AudioServer.get_bus_index(&"Master")
	if master_bus_index >= 0:
		master_volume = clampf(AudioServer.get_bus_volume_linear(master_bus_index), 0.0, 1.0)
		master_muted = AudioServer.is_bus_mute(master_bus_index)

	var controls: Dictionary = {}
	for action in MANAGED_ACTIONS:
		controls[str(action)] = _project_key_records(action)

	_defaults = {
		"display": {
			"mode": default_mode,
			"resolution": Vector2i(viewport_width, viewport_height),
			"vsync": configured_vsync != DisplayServer.VSYNC_DISABLED,
			"max_fps": clampi(int(ProjectSettings.get_setting("application/run/max_fps", 0)), 0, MAX_FRAME_LIMIT),
		},
		# Quality controls more than MSAA (weather passes and particles), so its
		# project default is explicit instead of being inferred from one renderer
		# flag. High preserves the full presentation that existed before settings.
		"graphics": {"quality": QUALITY_HIGH},
		"audio": {
			"master_volume": master_volume,
			"master_muted": master_muted,
		},
		"accessibility": {
			"reduced_motion": false,
			"pause_on_focus_loss": false,
		},
		"controls": controls,
	}


func _ensure_defaults() -> void:
	if _defaults.is_empty():
		_capture_project_defaults()


func _project_key_records(action: StringName) -> Array:
	var events: Array = []
	var input_setting = ProjectSettings.get_setting("input/%s" % str(action), {})
	if typeof(input_setting) == TYPE_DICTIONARY:
		var configured_events = (input_setting as Dictionary).get("events", [])
		if typeof(configured_events) == TYPE_ARRAY:
			events = configured_events
	if events.is_empty() and InputMap.has_action(action):
		events = InputMap.action_get_events(action)

	var records: Array = []
	for input_event in events:
		if not input_event is InputEventKey:
			continue
		records.append(_key_event_to_record(input_event as InputEventKey))
		if records.size() >= MAX_BINDINGS_PER_ACTION:
			break
	if records.is_empty() and FALLBACK_ACTION_KEYS.has(str(action)):
		var fallback_keycode := int(FALLBACK_ACTION_KEYS[str(action)])
		records.append({
			"type": "key",
			"keycode": fallback_keycode,
			"physical_keycode": 0,
			"unicode": fallback_keycode,
			"shift_pressed": false,
			"alt_pressed": false,
			"ctrl_pressed": false,
			"meta_pressed": false,
		})
	return records


func _key_event_to_record(input_event: InputEventKey) -> Dictionary:
	return {
		"type": "key",
		"keycode": int(input_event.keycode),
		"physical_keycode": int(input_event.physical_keycode),
		"unicode": int(input_event.unicode),
		"shift_pressed": bool(input_event.shift_pressed),
		"alt_pressed": bool(input_event.alt_pressed),
		"ctrl_pressed": bool(input_event.ctrl_pressed),
		"meta_pressed": bool(input_event.meta_pressed),
	}


func _sanitize_key_records(value, fallback_records: Array) -> Array:
	var result: Array = []
	if typeof(value) == TYPE_ARRAY:
		for raw_record in value:
			var record := _sanitize_key_record(raw_record)
			if record.is_empty() or record in result:
				continue
			result.append(record)
			if result.size() >= MAX_BINDINGS_PER_ACTION:
				break
	if result.is_empty():
		return fallback_records.duplicate(true)
	return result


func _sanitize_key_record(value) -> Dictionary:
	var source := _as_dictionary(value)
	if source.is_empty() or str(source.get("type", "")) != "key":
		return {}
	var keycode := _numeric_int(source.get("keycode"), 0)
	var physical_keycode := _numeric_int(source.get("physical_keycode"), 0)
	if keycode <= 0 and physical_keycode <= 0:
		return {}
	if keycode < 0 or physical_keycode < 0:
		return {}
	return {
		"type": "key",
		"keycode": keycode,
		"physical_keycode": physical_keycode,
		"unicode": clampi(_numeric_int(source.get("unicode"), 0), 0, 0x10ffff),
		"shift_pressed": _strict_bool(source.get("shift_pressed"), false),
		"alt_pressed": _strict_bool(source.get("alt_pressed"), false),
		"ctrl_pressed": _strict_bool(source.get("ctrl_pressed"), false),
		"meta_pressed": _strict_bool(source.get("meta_pressed"), false),
	}


func _apply_current_runtime() -> void:
	_apply_display(_current["display"])
	_apply_graphics(_current["graphics"])
	_apply_audio(_current["audio"])
	_apply_accessibility(_current["accessibility"])
	_apply_controls(_current["controls"])


func _apply_display(display_settings: Dictionary) -> void:
	Engine.max_fps = int(display_settings["max_fps"])
	if _tree == null or _tree.root == null:
		return
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if bool(display_settings["vsync"]) else DisplayServer.VSYNC_DISABLED
		)
	if not bool(display_geometry_capability()["supported"]):
		return
	var window := _tree.root
	if str(display_settings["mode"]) == DISPLAY_MODE_BORDERLESS:
		window.mode = Window.MODE_FULLSCREEN
		return
	window.mode = Window.MODE_WINDOWED
	window.borderless = false
	window.size = display_settings["resolution"]
	var screen_count := DisplayServer.get_screen_count()
	if screen_count <= 0:
		return
	var screen := clampi(window.current_screen, 0, screen_count - 1)
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	var centered_offset := (usable_rect.size - window.size) / 2
	window.position = usable_rect.position + Vector2i(maxi(centered_offset.x, 0), maxi(centered_offset.y, 0))


func _apply_graphics(graphics_settings: Dictionary) -> void:
	if _tree == null or _tree.root == null:
		return
	# Godot's GLES3 compatibility renderer does not implement 2D MSAA. Keep the
	# setting and all scene-level quality consumers active without producing an
	# engine warning for an unsupported render-target operation.
	if DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "gl_compatibility":
		_tree.root.msaa_2d = Viewport.MSAA_DISABLED
		return
	match str(graphics_settings["quality"]):
		QUALITY_MEDIUM:
			_tree.root.msaa_2d = Viewport.MSAA_2X
		QUALITY_HIGH:
			_tree.root.msaa_2d = Viewport.MSAA_4X
		_:
			_tree.root.msaa_2d = Viewport.MSAA_DISABLED


func _apply_audio(audio_settings: Dictionary) -> void:
	var master_bus_index := AudioServer.get_bus_index(&"Master")
	if master_bus_index < 0:
		return
	AudioServer.set_bus_volume_linear(master_bus_index, clampf(float(audio_settings["master_volume"]), 0.0, 1.0))
	AudioServer.set_bus_mute(master_bus_index, bool(audio_settings["master_muted"]))


func _apply_accessibility(accessibility_settings: Dictionary) -> void:
	_pause_on_focus_loss = bool(accessibility_settings["pause_on_focus_loss"])
	if not _pause_on_focus_loss and _paused_by_focus_loss and _tree != null:
		_tree.paused = false
		_paused_by_focus_loss = false


func _apply_controls(controls: Dictionary) -> void:
	for action in MANAGED_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.5)
		InputMap.action_erase_events(action)
		var records: Array = controls.get(str(action), [])
		for record_value in records:
			var record := _sanitize_key_record(record_value)
			if record.is_empty():
				continue
			var input_event := InputEventKey.new()
			input_event.keycode = int(record["keycode"])
			input_event.physical_keycode = int(record["physical_keycode"])
			input_event.unicode = int(record["unicode"])
			input_event.shift_pressed = bool(record["shift_pressed"])
			input_event.alt_pressed = bool(record["alt_pressed"])
			input_event.ctrl_pressed = bool(record["ctrl_pressed"])
			input_event.meta_pressed = bool(record["meta_pressed"])
			InputMap.action_add_event(action, input_event)


func _connect_window_focus_signals() -> void:
	if _tree == null or _tree.root == null:
		return
	var focus_exited_callable := Callable(self, "_on_window_focus_exited")
	var focus_entered_callable := Callable(self, "_on_window_focus_entered")
	if _tree.root.has_signal("focus_exited") and not _tree.root.is_connected("focus_exited", focus_exited_callable):
		_tree.root.connect("focus_exited", focus_exited_callable)
	if _tree.root.has_signal("focus_entered") and not _tree.root.is_connected("focus_entered", focus_entered_callable):
		_tree.root.connect("focus_entered", focus_entered_callable)


func _on_window_focus_exited() -> void:
	if not _pause_on_focus_loss or _tree == null or _tree.paused:
		return
	_tree.paused = true
	_paused_by_focus_loss = true


func _on_window_focus_entered() -> void:
	if not _paused_by_focus_loss or _tree == null:
		return
	_tree.paused = false
	_paused_by_focus_loss = false


func _read_valid_settings(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"exists": false, "error": ERR_FILE_NOT_FOUND, "settings": {}}
	var config := ConfigFile.new()
	var load_error := config.load(path)
	if load_error != OK:
		return {"exists": true, "error": load_error, "settings": {}}
	if int(config.get_value("meta", "schema_version", 0)) != CURRENT_SCHEMA_VERSION:
		return {"exists": true, "error": ERR_INVALID_DATA, "settings": {}}

	var candidate := defaults_snapshot()
	for section_name in ["display", "graphics", "audio", "accessibility"]:
		var section: Dictionary = candidate[section_name]
		for key in section.keys():
			section[key] = config.get_value(section_name, str(key), section[key])
		candidate[section_name] = section
	var controls: Dictionary = candidate["controls"]
	for action in MANAGED_ACTIONS:
		var action_id := str(action)
		controls[action_id] = config.get_value("controls", action_id, controls.get(action_id, []))
	candidate["controls"] = controls
	return {"exists": true, "error": OK, "settings": sanitize(candidate)}


func _remove_if_exists(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _section(source: Dictionary, section_name: String) -> Dictionary:
	if not source.has(section_name) or typeof(source[section_name]) != TYPE_DICTIONARY:
		return {}
	return source[section_name]


func _as_dictionary(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _strict_bool(value, fallback: bool) -> bool:
	return bool(value) if typeof(value) == TYPE_BOOL else fallback


func _numeric_int(value, fallback: int) -> int:
	return int(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else fallback


func _numeric_float(value, fallback: float) -> float:
	return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else fallback
