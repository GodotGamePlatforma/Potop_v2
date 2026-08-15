class_name InputPrompt
extends RefCounted

const DEFAULT_MAX_BINDINGS := 2


static func action_text(action: StringName, max_bindings: int = DEFAULT_MAX_BINDINGS) -> String:
	if not InputMap.has_action(action) or max_bindings <= 0:
		return "—"
	var labels: Array[String] = []
	for input_event in InputMap.action_get_events(action):
		var label := event_text(input_event)
		if label.is_empty() or labels.has(label):
			continue
		labels.append(label)
		if labels.size() >= max_bindings:
			break
	return " / ".join(labels) if not labels.is_empty() else "—"


static func event_text(input_event: InputEvent) -> String:
	if input_event is InputEventKey:
		return _key_event_text(input_event as InputEventKey)
	if input_event is InputEventMouseButton:
		return _mouse_button_text(input_event as InputEventMouseButton)
	if input_event is InputEventJoypadButton:
		return "PAD %d" % (input_event as InputEventJoypadButton).button_index
	return input_event.as_text().to_upper() if input_event != null else ""


static func _key_event_text(input_event: InputEventKey) -> String:
	var keycode: Key = input_event.keycode
	if input_event.physical_keycode != KEY_NONE:
		# The headless display server cannot resolve the active keyboard layout and
		# reports an engine ERROR if queried. Physical key constants remain a safe,
		# deterministic fallback for tests and dedicated runs.
		if DisplayServer.get_name() == "headless":
			keycode = input_event.physical_keycode
		else:
			keycode = DisplayServer.keyboard_get_label_from_physical(input_event.physical_keycode)
			if keycode == KEY_NONE:
				keycode = input_event.physical_keycode
	elif input_event.key_label != KEY_NONE:
		keycode = input_event.key_label
	if keycode == KEY_NONE:
		return ""
	var parts: Array[String] = []
	if input_event.ctrl_pressed and keycode != KEY_CTRL:
		parts.append("CTRL")
	if input_event.alt_pressed and keycode != KEY_ALT:
		parts.append("ALT")
	if input_event.shift_pressed and keycode != KEY_SHIFT:
		parts.append("SHIFT")
	if input_event.meta_pressed and keycode != KEY_META:
		parts.append("META")
	parts.append(_polish_key_name(keycode))
	return "+".join(parts)


static func _polish_key_name(keycode: Key) -> String:
	match keycode:
		KEY_LEFT:
			return "←"
		KEY_RIGHT:
			return "→"
		KEY_UP:
			return "↑"
		KEY_DOWN:
			return "↓"
		KEY_SPACE:
			return "SPACJA"
		KEY_ESCAPE:
			return "ESC"
		KEY_ENTER, KEY_KP_ENTER:
			return "ENTER"
		KEY_BACKSPACE:
			return "BACKSPACE"
		KEY_DELETE:
			return "DELETE"
		KEY_PAGEUP:
			return "PAGE UP"
		KEY_PAGEDOWN:
			return "PAGE DOWN"
		_:
			return OS.get_keycode_string(keycode).to_upper()


static func _mouse_button_text(input_event: InputEventMouseButton) -> String:
	match input_event.button_index:
		MOUSE_BUTTON_LEFT:
			return "LPM"
		MOUSE_BUTTON_RIGHT:
			return "PPM"
		MOUSE_BUTTON_MIDDLE:
			return "ŚPM"
		MOUSE_BUTTON_WHEEL_UP:
			return "KÓŁKO ↑"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "KÓŁKO ↓"
		_:
			return "MYSZ %d" % input_event.button_index
