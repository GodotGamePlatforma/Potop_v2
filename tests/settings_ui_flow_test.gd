extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")

const TEST_SETTINGS_PRIMARY := "user://test_settings_ui.cfg"
const TEST_SETTINGS_PENDING := "user://test_settings_ui.pending.cfg"
const TEST_SETTINGS_BACKUP := "user://test_settings_ui.backup.cfg"
const TEST_SAVE_PRIMARY := "user://test_settings_ui_autosave.tres"
const TEST_SAVE_PENDING := "user://test_settings_ui_autosave.pending.tres"
const TEST_SAVE_BACKUP := "user://test_settings_ui_autosave.backup.tres"

var _failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup_test_files()
	SaveManager.configure_paths(TEST_SAVE_PRIMARY, TEST_SAVE_PENDING, TEST_SAVE_BACKUP)

	var game_root = GameRootScene.instantiate()
	add_child(game_root)
	await get_tree().process_frame
	await get_tree().process_frame
	game_root.user_settings.configure_paths(TEST_SETTINGS_PRIMARY, TEST_SETTINGS_PENDING, TEST_SETTINGS_BACKUP)

	var menu: Control = game_root.current_scene as Control
	_assert(menu != null and menu.name == "MainMenu", "GameRoot should start on the real main menu.")
	if menu == null:
		await _finish(game_root)
		return

	var settings_button := menu.find_child("SettingsButton", true, false) as Button
	var overlay := menu.find_child("SettingsOverlay", true, false) as Control
	_assert(settings_button != null and overlay != null, "Main menu should expose the settings button and SettingsOverlay.")
	if settings_button == null or overlay == null:
		await _finish(game_root)
		return

	var baseline: Dictionary = game_root.user_settings.snapshot()
	settings_button.pressed.emit()
	await get_tree().process_frame
	_assert(overlay.visible, "USTAWIENIA should open the blocking settings modal.")

	await _test_audio_preview_and_cancel(game_root, overlay, baseline)
	await _test_audio_apply_and_persistence(game_root, menu, overlay, settings_button)
	await _test_display_rollback(game_root, menu, overlay, settings_button)
	await _test_control_capture_and_conflict(game_root, menu, overlay, settings_button)
	await _test_scene_quality_and_accessibility_propagation(game_root)

	await _finish(game_root)


func _test_audio_preview_and_cancel(game_root, overlay: Control, baseline: Dictionary) -> void:
	var audio_button := overlay.find_child("AudioCategoryButton", true, false) as Button
	var slider := overlay.find_child("MasterVolumeSlider", true, false) as HSlider
	var tone_button := overlay.find_child("TestToneButton", true, false) as Button
	var tone_player := overlay.find_child("TestTonePlayer", true, false) as AudioStreamPlayer
	var cancel_button := overlay.find_child("CancelButton", true, false) as Button
	_assert(audio_button != null and slider != null and tone_button != null and tone_player != null and cancel_button != null, "Audio category should expose preview, test-tone and cancel controls.")
	if audio_button == null or slider == null or tone_button == null or tone_player == null or cancel_button == null:
		return
	audio_button.pressed.emit()
	slider.value = 0.31
	await get_tree().process_frame
	var master_bus := AudioServer.get_bus_index(&"Master")
	_assert(master_bus >= 0 and is_equal_approx(AudioServer.get_bus_volume_linear(master_bus), 0.31), "Moving the slider should preview the real Master volume.")
	tone_button.pressed.emit()
	await get_tree().process_frame
	var tone_stream := tone_player.stream as AudioStreamWAV
	_assert(tone_stream != null and not tone_stream.data.is_empty() and tone_player.playing, "The audio test button should play a generated WAV through Master.")
	cancel_button.pressed.emit()
	await get_tree().process_frame
	_assert(not overlay.visible, "ANULUJ should close the modal.")
	_assert(game_root.user_settings.snapshot() == baseline, "ANULUJ should leave the committed snapshot unchanged.")
	if master_bus >= 0:
		_assert(is_equal_approx(AudioServer.get_bus_volume_linear(master_bus), float(baseline["audio"]["master_volume"])), "ANULUJ should restore the previous Master preview.")


func _test_audio_apply_and_persistence(game_root, menu: Control, overlay: Control, settings_button: Button) -> void:
	settings_button.pressed.emit()
	await get_tree().process_frame
	var audio_button := overlay.find_child("AudioCategoryButton", true, false) as Button
	var slider := overlay.find_child("MasterVolumeSlider", true, false) as HSlider
	var apply_button := overlay.find_child("ApplyButton", true, false) as Button
	audio_button.pressed.emit()
	slider.value = 0.37
	apply_button.pressed.emit()
	await get_tree().process_frame
	_assert(not overlay.visible, "ZASTOSUJ should close when no display confirmation is needed.")
	_assert(is_equal_approx(float(game_root.user_settings.get_value("audio", "master_volume", -1.0)), 0.37), "ZASTOSUJ should commit the Master volume.")
	_assert(FileAccess.file_exists(TEST_SETTINGS_PRIMARY), "ZASTOSUJ should atomically install the isolated settings primary file.")
	_assert(menu.find_child("SettingsButton", true, false) == settings_button, "Closing settings should preserve the main-menu control tree.")


func _test_display_rollback(game_root, _menu: Control, overlay: Control, settings_button: Button) -> void:
	var capability: Dictionary = game_root.user_settings.display_geometry_capability()
	var picker := overlay.find_child("ResolutionPicker", true, false) as OptionButton
	if bool(capability.get("supported", false)):
		var baseline_ready: bool = await _establish_supported_display_baseline(game_root.user_settings, picker)
		if not baseline_ready:
			return
	var previous_snapshot: Dictionary = game_root.user_settings.snapshot()
	var previous_display: Dictionary = previous_snapshot.get("display", {}).duplicate(true)
	var previous_actual: Dictionary = game_root.user_settings.display_output_state()

	settings_button.pressed.emit()
	await get_tree().process_frame
	var display_button := overlay.find_child("DisplayCategoryButton", true, false) as Button
	var mode_picker := overlay.find_child("DisplayModePicker", true, false) as OptionButton
	var apply_button := overlay.find_child("ApplyButton", true, false) as Button
	var confirmation := overlay.find_child("DisplayConfirmation", true, false) as ConfirmationDialog
	var display_warning := overlay.find_child("DisplayWarning", true, false) as Label
	var status_label := overlay.find_child("StatusLabel", true, false) as Label
	var cancel_button := overlay.find_child("CancelButton", true, false) as Button
	_assert(
		display_button != null and mode_picker != null and picker != null and apply_button != null
		and confirmation != null and display_warning != null and status_label != null and cancel_button != null,
		"Display category should expose mode, resolution, capability message, confirmation and action controls."
	)
	if (
		display_button == null or mode_picker == null or picker == null or apply_button == null
		or confirmation == null or display_warning == null or status_label == null or cancel_button == null
	):
		return
	display_button.pressed.emit()

	if not bool(capability.get("supported", false)):
		await _test_unsupported_display_environment(
			game_root.user_settings,
			overlay,
			mode_picker,
			picker,
			apply_button,
			confirmation,
			display_warning,
			status_label,
			cancel_button,
			capability,
			previous_display
		)
		return

	await _test_supported_display_rollback(
		game_root.user_settings,
		overlay,
		mode_picker,
		picker,
		apply_button,
		confirmation,
		cancel_button,
		previous_display,
		previous_actual
	)


func _establish_supported_display_baseline(settings, picker: OptionButton) -> bool:
	_assert(picker != null and picker.item_count > 0, "Supported display testing requires at least one safe resolution option.")
	if picker == null or picker.item_count == 0:
		return false
	var baseline_resolution = picker.get_item_metadata(0)
	_assert(baseline_resolution is Vector2i, "Resolution metadata must use Vector2i values.")
	if not baseline_resolution is Vector2i:
		return false
	var candidate: Dictionary = settings.snapshot()
	var display: Dictionary = candidate.get("display", {}).duplicate(true)
	display["mode"] = "windowed"
	display["resolution"] = baseline_resolution
	candidate["display"] = display
	var apply_error := int(settings.apply(candidate, false))
	_assert(apply_error == OK, "Preparing a native windowed baseline must succeed.")
	if apply_error != OK:
		return false
	var verification: Dictionary = await _wait_for_verified_display(settings, display)
	_assert(bool(verification.get("supported", false)) and bool(verification.get("matches", false)), "The native windowed baseline must match DisplayServer before UI rollback testing: %s" % str(verification.get("reason", "")))
	return bool(verification.get("supported", false)) and bool(verification.get("matches", false))


func _test_unsupported_display_environment(
	settings,
	overlay: Control,
	mode_picker: OptionButton,
	resolution_picker: OptionButton,
	apply_button: Button,
	confirmation: ConfirmationDialog,
	display_warning: Label,
	status_label: Label,
	cancel_button: Button,
	capability: Dictionary,
	previous_display: Dictionary
) -> void:
	var capability_reason := str(capability.get("reason", "")).strip_edges()
	_assert(not capability_reason.is_empty(), "Unsupported display geometry must provide a visible reason.")
	_assert(mode_picker.disabled and resolution_picker.disabled, "Headless or embedded UI must disable mode and resolution pickers.")
	_assert(not apply_button.disabled, "Unsupported geometry must not disable Apply for VSync, FPS or quality settings.")
	_assert(capability_reason in display_warning.text, "DisplayWarning must include the capability reason instead of pretending geometry can change.")

	# Disabled controls cannot be changed by a player, but emitting a synthetic
	# selection protects against regressions that would still stage geometry and
	# open the 15-second confirmation in unsupported environments.
	var alternate_mode_index := -1
	var previous_mode := str(previous_display.get("mode", "windowed"))
	for index in range(mode_picker.item_count):
		if str(mode_picker.get_item_metadata(index)) != previous_mode:
			alternate_mode_index = index
			break
	_assert(alternate_mode_index >= 0, "Display mode picker should expose an alternate value for the unsupported-geometry guard test.")
	if alternate_mode_index >= 0:
		mode_picker.select(alternate_mode_index)
		mode_picker.item_selected.emit(alternate_mode_index)
	apply_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(overlay.visible, "Rejecting unsupported geometry must keep settings open with an explanation.")
	_assert(not confirmation.visible, "Unsupported geometry must never open a fake display confirmation countdown.")
	_assert(settings.snapshot().get("display", {}) == previous_display, "Unsupported geometry must leave the committed display snapshot unchanged.")
	_assert(capability_reason in status_label.text, "The failed Apply attempt must explain the unsupported display environment.")

	var defaults_button := overlay.find_child("DefaultsButton", true, false) as Button
	_assert(defaults_button != null, "Settings must expose the defaults action in an unsupported display environment.")
	if defaults_button == null:
		cancel_button.pressed.emit()
		await get_tree().process_frame
		return
	var defaults: Dictionary = settings.defaults_snapshot()
	defaults_button.pressed.emit()
	apply_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not overlay.visible, "Restoring defaults in embedded/headless mode must still apply all supported settings and close the menu.")
	_assert(settings.snapshot().get("display", {}) == previous_display, "Unsupported defaults reset must preserve the committed mode and resolution.")
	_assert(settings.snapshot().get("audio", {}) == defaults.get("audio", {}), "Unsupported defaults reset must still restore supported audio defaults.")
	_assert(settings.snapshot().get("graphics", {}) == defaults.get("graphics", {}), "Unsupported defaults reset must still restore supported graphics defaults.")


func _test_supported_display_rollback(
	settings,
	overlay: Control,
	mode_picker: OptionButton,
	resolution_picker: OptionButton,
	apply_button: Button,
	confirmation: ConfirmationDialog,
	cancel_button: Button,
	previous_display: Dictionary,
	previous_actual: Dictionary
) -> void:
	_assert(not mode_picker.disabled and not resolution_picker.disabled, "Native windowed display controls must remain interactive.")
	var expected_display := previous_display.duplicate(true)
	var replacement_index := -1
	for index in range(resolution_picker.item_count):
		if resolution_picker.get_item_metadata(index) != previous_display.get("resolution", Vector2i.ZERO):
			replacement_index = index
			break
	if replacement_index >= 0:
		var replacement_resolution = resolution_picker.get_item_metadata(replacement_index)
		resolution_picker.select(replacement_index)
		resolution_picker.item_selected.emit(replacement_index)
		expected_display["resolution"] = replacement_resolution
	else:
		var borderless_index := -1
		for index in range(mode_picker.item_count):
			if str(mode_picker.get_item_metadata(index)) == "borderless":
				borderless_index = index
				break
		_assert(borderless_index >= 0, "A supported display must offer either a second resolution or borderless mode for rollback testing.")
		if borderless_index < 0:
			cancel_button.pressed.emit()
			return
		mode_picker.select(borderless_index)
		mode_picker.item_selected.emit(borderless_index)
		expected_display["mode"] = "borderless"

	apply_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(confirmation.visible, "Changing resolution should require the 15-second confirmation dialog.")
	var changed_verification: Dictionary = await _wait_for_verified_display(settings, expected_display)
	_assert(bool(changed_verification.get("supported", false)) and bool(changed_verification.get("matches", false)), "The applied UI display choice must match the real DisplayServer output: %s" % str(changed_verification.get("reason", "")))
	var changed_actual: Dictionary = settings.display_output_state()
	_assert(changed_actual.get("resolution", Vector2i.ZERO) == DisplayServer.window_get_size(), "Supported UI apply must measure the real client size through DisplayServer.window_get_size().")
	_assert(int(changed_actual.get("window_mode", -1)) == int(DisplayServer.window_get_mode()), "Supported UI apply must measure the real native window mode.")
	if str(expected_display.get("mode", "windowed")) == "windowed":
		_assert(DisplayServer.window_get_size() == expected_display.get("resolution", Vector2i.ZERO), "Windowed UI apply must reach the selected physical client size.")
	else:
		_assert(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Borderless UI apply must reach the native fullscreen mode.")

	confirmation.get_cancel_button().pressed.emit()
	for _frame in range(45):
		await get_tree().process_frame
		if not apply_button.disabled:
			break
	var rollback_verification: Dictionary = await _wait_for_verified_display(settings, previous_display)
	_assert(bool(rollback_verification.get("supported", false)) and bool(rollback_verification.get("matches", false)), "Rejecting confirmation must restore a DisplayServer output matching the previous display snapshot: %s" % str(rollback_verification.get("reason", "")))
	_assert(not apply_button.disabled, "The verified cancel rollback must finish before another display attempt is accepted.")
	_assert(settings.snapshot().get("display", {}) == previous_display, "Rejecting display confirmation should restore the complete previous display snapshot.")
	_assert(DisplayServer.window_get_size() == previous_actual.get("resolution", Vector2i.ZERO), "Display rollback must restore the previous real client size, not only the settings snapshot.")
	_assert(int(DisplayServer.window_get_mode()) == int(previous_actual.get("window_mode", -1)), "Display rollback must restore the previous real window mode.")
	_assert(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS) == bool(previous_actual.get("borderless", false)), "Display rollback must restore the previous real borderless flag.")

	_assert(_stage_display_choice(mode_picker, resolution_picker, expected_display), "The display choice must be stageable again for pre-save verification.")
	apply_button.pressed.emit()
	var reapplied_verification: Dictionary = await _wait_for_verified_display(settings, expected_display)
	_assert(bool(reapplied_verification.get("matches", false)) and confirmation.visible, "The repeated display choice must reach the real output and reopen confirmation.")

	# Simulate a window-manager or external-code change while the 15-second
	# confirmation is visible. Confirm must measure DisplayServer again instead
	# of trusting the unchanged logical UserSettings snapshot.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await get_tree().process_frame
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_size(previous_actual.get("resolution", Vector2i(1280, 720)))
	await get_tree().process_frame
	confirmation.get_ok_button().pressed.emit()
	for _frame in range(45):
		await get_tree().process_frame
		if not apply_button.disabled:
			break
	var tamper_rollback: Dictionary = await _wait_for_verified_display(settings, previous_display)
	_assert(bool(tamper_rollback.get("matches", false)), "A physical resize before confirmation must trigger a verified rollback.")
	_assert(not apply_button.disabled, "A verified mismatch rollback must finish before another display attempt is accepted.")
	_assert(overlay.visible and not confirmation.visible, "A mismatched physical output must not close settings or report a saved success.")
	_assert(settings.snapshot().get("display", {}) == previous_display, "A mismatched physical output must not persist the pending display candidate.")

	_assert(_stage_display_choice(mode_picker, resolution_picker, expected_display), "The display choice must remain stageable after the mismatch rollback.")
	apply_button.pressed.emit()
	var final_apply_verification: Dictionary = await _wait_for_verified_display(settings, expected_display)
	_assert(bool(final_apply_verification.get("matches", false)) and confirmation.visible, "A final valid display apply must reach the real output before confirmation.")
	confirmation.get_ok_button().pressed.emit()
	for _frame in range(45):
		await get_tree().process_frame
		if not overlay.visible:
			break
	_assert(not overlay.visible, "Confirming a physically verified output must save it and close settings.")
	_assert(settings.snapshot().get("display", {}) == expected_display, "Display confirmation must persist exactly the verified candidate.")
	var confirmed_verification: Dictionary = await _wait_for_verified_display(settings, expected_display)
	_assert(bool(confirmed_verification.get("matches", false)), "The confirmed display candidate must remain equal to the real DisplayServer output.")


func _stage_display_choice(mode_picker: OptionButton, resolution_picker: OptionButton, expected_display: Dictionary) -> bool:
	var wanted_mode := str(expected_display.get("mode", "windowed"))
	var mode_index := -1
	for index in range(mode_picker.item_count):
		if str(mode_picker.get_item_metadata(index)) == wanted_mode:
			mode_index = index
			break
	if mode_index < 0:
		return false
	mode_picker.select(mode_index)
	mode_picker.item_selected.emit(mode_index)
	if wanted_mode != "windowed":
		return true

	var wanted_resolution: Vector2i = expected_display.get("resolution", Vector2i.ZERO)
	for index in range(resolution_picker.item_count):
		if resolution_picker.get_item_metadata(index) == wanted_resolution:
			resolution_picker.select(index)
			resolution_picker.item_selected.emit(index)
			return true
	return false


func _wait_for_verified_display(settings, expected_display: Dictionary, frame_limit: int = 45) -> Dictionary:
	var verification: Dictionary = {}
	for _frame in range(frame_limit):
		await get_tree().process_frame
		verification = settings.verify_display_output(expected_display)
		if bool(verification.get("supported", false)) and bool(verification.get("matches", false)):
			break
	return verification


func _test_control_capture_and_conflict(game_root, _menu: Control, overlay: Control, settings_button: Button) -> void:
	settings_button.pressed.emit()
	await get_tree().process_frame
	var controls_button := overlay.find_child("ControlsCategoryButton", true, false) as Button
	var binding_rows := overlay.find_child("BindingRows", true, false) as Container
	var left_primary := overlay.find_child("Binding_dive_left_0", true, false) as Button
	var capture_overlay := overlay.find_child("CaptureOverlay", true, false) as Control
	var capture_prompt := overlay.find_child("CapturePrompt", true, false) as Label
	var apply_button := overlay.find_child("ApplyButton", true, false) as Button
	controls_button.pressed.emit()
	_assert(binding_rows.get_child_count() == 14 and overlay.find_child("Binding_dive_quiet_repair_0", true, false) != null, "Sterowanie should show exactly fourteen managed keyboard action rows, including quiet repair.")

	left_primary.pressed.emit()
	await get_tree().process_frame
	_assert(capture_overlay.visible, "Clicking a binding slot should open the key-capture overlay.")
	overlay.call("_input", _pressed_key(KEY_D))
	_assert(capture_overlay.visible and "już używany" in capture_prompt.text, "A same-context conflict should be rejected with an explanation.")
	overlay.call("_input", _pressed_key(KEY_F10))
	_assert(capture_overlay.visible and "zarezerwowany" in capture_prompt.text, "F10 should remain reserved for developer telemetry.")
	overlay.call("_input", _pressed_key(KEY_Q))
	await get_tree().process_frame
	_assert(not capture_overlay.visible and left_primary.text == "Q", "A free key should update the staged binding and close capture.")
	apply_button.pressed.emit()
	await get_tree().process_frame
	_assert(_action_has_key(&"dive_left", KEY_Q), "Applying controls should rebuild the real InputMap.")


func _test_scene_quality_and_accessibility_propagation(game_root) -> void:
	var candidate: Dictionary = game_root.user_settings.snapshot()
	var graphics: Dictionary = candidate["graphics"]
	graphics["quality"] = "low"
	candidate["graphics"] = graphics
	var accessibility: Dictionary = candidate["accessibility"]
	accessibility["reduced_motion"] = true
	candidate["accessibility"] = accessibility
	_assert(game_root.user_settings.apply(candidate, false) == OK, "Quality/accessibility settings should apply before scene routing.")
	_assert(game_root.start_new_campaign("standard", 41027, false, false), "The isolated flow should be able to enter the real base scene.")
	await get_tree().process_frame
	await get_tree().process_frame
	var base = game_root.current_scene
	_assert(base != null and base.name == "BaseScene", "Starting an isolated campaign should route to BaseScene.")
	if base == null:
		return
	_assert(str(base.get("_graphics_quality")) == "low", "GameRoot should propagate graphics quality to the active base controller.")
	_assert(base.get("_reduced_motion") == true, "GameRoot should propagate reduced motion to the active base controller.")
	var environment = base.find_child("BaseEnvironment", true, false)
	var quality_state: Dictionary = environment.graphics_quality_state() if environment != null and environment.has_method("graphics_quality_state") else {}
	_assert(str(quality_state.get("quality", "")) == "low" and quality_state.get("sea_mist_visible", true) == false, "Low quality should reach the real environment and disable secondary atmosphere.")
	_assert(environment.world_viewport.msaa_3d == Viewport.MSAA_DISABLED and environment.world_viewport.get_parent().stretch_shrink == 2, "Low quality must configure the 3D target during initial construction, without a transient high preset.")


func _pressed_key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.unicode = int(keycode) if int(keycode) < 128 else 0
	event.pressed = true
	return event


func _action_has_key(action: StringName, keycode: Key) -> bool:
	for input_event in InputMap.action_get_events(action):
		if input_event is InputEventKey and (input_event as InputEventKey).keycode == keycode:
			return true
	return false


func _finish(game_root) -> void:
	if game_root != null and game_root.user_settings != null:
		game_root.user_settings.apply(game_root.user_settings.defaults_snapshot(), false)
	SaveManager.reset_paths()
	_cleanup_test_files()
	if game_root != null:
		game_root.show_main_menu()
		await get_tree().process_frame
		await get_tree().process_frame
		game_root.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	if _failed:
		get_tree().quit(1)
		return
	print("Settings UI flow test passed: modal, audio staging, persistence, display rollback, key capture and scene propagation are valid.")
	get_tree().quit(0)


func _cleanup_test_files() -> void:
	for path in [
		TEST_SETTINGS_PRIMARY,
		TEST_SETTINGS_PENDING,
		TEST_SETTINGS_BACKUP,
		TEST_SAVE_PRIMARY,
		TEST_SAVE_PENDING,
		TEST_SAVE_BACKUP,
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Settings UI flow test failed: " + message)
