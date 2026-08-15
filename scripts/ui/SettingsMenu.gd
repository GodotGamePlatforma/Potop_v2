class_name SettingsMenu
extends Control

signal closed

const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")

const DISPLAY_CONFIRM_SECONDS := 15
const DISPLAY_VERIFY_FRAME_LIMIT := 30
const TEST_TONE_SECONDS := 0.42
const TEST_TONE_HZ := 440.0
const TEST_TONE_SAMPLE_RATE := 44_100
const EMPTY_BINDING_LABEL := "—"

const DISPLAY_MODES := [
	{"label": "OKNO", "value": "windowed"},
	{"label": "PEŁNY EKRAN BEZ RAMEK", "value": "borderless"},
]
const WINDOW_RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]
const FPS_LIMITS := [
	{"label": "30 FPS", "value": 30},
	{"label": "60 FPS", "value": 60},
	{"label": "120 FPS", "value": 120},
	{"label": "144 FPS", "value": 144},
	{"label": "BEZ LIMITU", "value": 0},
]
const QUALITY_LEVELS := [
	{"label": "NISKA", "value": "low"},
	{"label": "ŚREDNIA", "value": "medium"},
	{"label": "WYSOKA", "value": "high"},
]
const MANAGED_ACTIONS := [
	{"id": "dive_left", "label": "Płyń w lewo", "context": "dive"},
	{"id": "dive_right", "label": "Płyń w prawo", "context": "dive"},
	{"id": "dive_up", "label": "Płyń w górę", "context": "dive"},
	{"id": "dive_down", "label": "Płyń w dół", "context": "dive"},
	{"id": "dive_interact", "label": "Akcja kontekstowa", "context": "dive"},
	{"id": "dive_sprint", "label": "Sprint", "context": "dive"},
	{"id": "dive_repair", "label": "Napraw kombinezon", "context": "dive"},
	{"id": "dive_quiet_repair", "label": "Cicha naprawa kombinezonu", "context": "dive"},
	{"id": "dive_light_toggle", "label": "Włącz/wyłącz latarnię", "context": "dive"},
	{"id": "dive_inventory", "label": "Otwórz plecak", "context": "dive"},
	{"id": "dive_weapon_knife", "label": "Wybierz nóż", "context": "dive"},
	{"id": "dive_weapon_ranged", "label": "Wybierz harpun", "context": "dive"},
	{"id": "open_mission_journal", "label": "Otwórz dziennik misji", "context": "base"},
	{"id": "open_day_reports", "label": "Otwórz raporty dnia", "context": "base"},
]

@onready var display_category_button: Button = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/NavigationPanel/NavigationMargin/CategoryButtons/DisplayCategoryButton
@onready var audio_category_button: Button = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/NavigationPanel/NavigationMargin/CategoryButtons/AudioCategoryButton
@onready var controls_category_button: Button = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/NavigationPanel/NavigationMargin/CategoryButtons/ControlsCategoryButton
@onready var general_category_button: Button = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/NavigationPanel/NavigationMargin/CategoryButtons/GeneralCategoryButton

@onready var display_section: VBoxContainer = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/DisplaySection
@onready var audio_section: VBoxContainer = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/AudioSection
@onready var controls_section: VBoxContainer = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/ControlsSection
@onready var general_section: VBoxContainer = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/GeneralSection
@onready var content_scroll: ScrollContainer = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll

@onready var display_mode_picker: OptionButton = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/DisplaySection/DisplayGrid/DisplayModePicker
@onready var resolution_picker: OptionButton = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/DisplaySection/DisplayGrid/ResolutionPicker
@onready var vsync_check: CheckButton = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/DisplaySection/DisplayGrid/VsyncCheck
@onready var fps_picker: OptionButton = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/DisplaySection/DisplayGrid/FpsPicker
@onready var quality_picker: OptionButton = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/DisplaySection/DisplayGrid/QualityPicker
@onready var display_warning: Label = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/DisplaySection/DisplayWarning

@onready var master_volume_slider: HSlider = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/AudioSection/VolumeRow/MasterVolumeSlider
@onready var volume_value_label: Label = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/AudioSection/VolumeRow/VolumeValue
@onready var master_mute_check: CheckButton = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/AudioSection/MasterMuteCheck
@onready var test_tone_button: Button = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/AudioSection/TestToneButton
@onready var test_tone_player: AudioStreamPlayer = $TestTonePlayer

@onready var binding_rows: GridContainer = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/ControlsSection/BindingRows
@onready var binding_status: Label = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/ControlsSection/BindingStatus

@onready var reduced_motion_check: CheckButton = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/GeneralSection/ReducedMotionCheck
@onready var pause_focus_check: CheckButton = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Body/ContentCard/ContentMargin/ContentScroll/Sections/GeneralSection/PauseFocusCheck

@onready var close_button: Button = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Header/CloseButton
@onready var defaults_button: Button = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Footer/DefaultsButton
@onready var status_label: Label = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Footer/StatusLabel
@onready var cancel_button: Button = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Footer/CancelButton
@onready var apply_button: Button = $SafeMargin/Center/SettingsPanel/OuterMargin/RootLayout/Footer/ApplyButton

@onready var capture_overlay: Control = $CaptureOverlay
@onready var capture_prompt: Label = $CaptureOverlay/CaptureCenter/CapturePanel/CaptureMargin/CaptureLayout/CapturePrompt
@onready var capture_cancel_button: Button = $CaptureOverlay/CaptureCenter/CapturePanel/CaptureMargin/CaptureLayout/CaptureCancelButton
@onready var display_confirmation: ConfirmationDialog = $DisplayConfirmation
@onready var display_rollback_timer: Timer = $DisplayRollbackTimer

var user_settings
var _original_snapshot: Dictionary = {}
var _draft: Dictionary = {}
var _pending_candidate: Dictionary = {}
var _return_focus: WeakRef
var _binding_buttons: Dictionary = {}
var _category_buttons: Dictionary = {}
var _sections: Dictionary = {}
var _syncing: bool = false
var _capture_action_id: String = ""
var _capture_slot: int = -1
var _awaiting_display_confirmation: bool = false
var _display_seconds_remaining: int = 0
var _display_geometry_capability: Dictionary = {}
var _apply_in_progress: bool = false


func _ready() -> void:
	_build_static_options()
	_build_binding_rows()
	_connect_signals()
	_build_test_tone()
	_show_section("display")
	if not get_viewport().gui_focus_changed.is_connected(_on_gui_focus_changed):
		get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)


func open_with_settings(settings, return_focus: Control = null) -> bool:
	if settings == null:
		return false
	for required_method in [
		"snapshot",
		"defaults_snapshot",
		"sanitize",
		"apply",
		"save_current",
		"preview_audio",
		"get_value",
		"display_geometry_capability",
		"verify_display_output",
	]:
		if not settings.has_method(required_method):
			push_error("SettingsMenu: UserSettings nie udostępnia metody %s()." % required_method)
			return false
	user_settings = settings
	var current = user_settings.snapshot()
	if not current is Dictionary:
		push_error("SettingsMenu: snapshot ustawień nie jest słownikiem.")
		return false
	_original_snapshot = (current as Dictionary).duplicate(true)
	_draft = _sanitize_snapshot(_original_snapshot)
	_return_focus = weakref(return_focus) if return_focus != null else null
	_pending_candidate.clear()
	_awaiting_display_confirmation = false
	_apply_in_progress = false
	_capture_action_id = ""
	_capture_slot = -1
	capture_overlay.hide()
	display_rollback_timer.stop()
	if display_confirmation.visible:
		display_confirmation.hide()
	_refresh_display_geometry_capability()
	_update_action_buttons()
	_sync_from_draft()
	_set_status("")
	_show_section("display")
	show()
	move_to_front()
	display_category_button.call_deferred("grab_focus")
	return true


func _connect_signals() -> void:
	_category_buttons = {
		"display": display_category_button,
		"audio": audio_category_button,
		"controls": controls_category_button,
		"general": general_category_button,
	}
	_sections = {
		"display": display_section,
		"audio": audio_section,
		"controls": controls_section,
		"general": general_section,
	}
	var category_group := ButtonGroup.new()
	category_group.allow_unpress = false
	for category_id in _category_buttons.keys():
		var category_button: Button = _category_buttons[category_id]
		category_button.button_group = category_group
		category_button.pressed.connect(_show_section.bind(str(category_id)))

	display_mode_picker.item_selected.connect(_on_display_mode_selected)
	resolution_picker.item_selected.connect(_on_resolution_selected)
	vsync_check.toggled.connect(_on_vsync_toggled)
	fps_picker.item_selected.connect(_on_fps_selected)
	quality_picker.item_selected.connect(_on_quality_selected)
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	master_volume_slider.drag_ended.connect(_on_master_volume_drag_ended)
	master_mute_check.toggled.connect(_on_master_mute_toggled)
	test_tone_button.pressed.connect(_play_test_tone)
	reduced_motion_check.toggled.connect(_on_reduced_motion_toggled)
	pause_focus_check.toggled.connect(_on_pause_focus_toggled)
	close_button.pressed.connect(_cancel_and_close)
	defaults_button.pressed.connect(_restore_defaults)
	cancel_button.pressed.connect(_cancel_and_close)
	apply_button.pressed.connect(_apply_draft)
	capture_cancel_button.pressed.connect(_cancel_capture)
	display_confirmation.confirmed.connect(_confirm_display_change)
	display_confirmation.canceled.connect(_cancel_display_change)
	display_rollback_timer.timeout.connect(_display_countdown_tick)


func _build_static_options() -> void:
	display_mode_picker.clear()
	for option in DISPLAY_MODES:
		display_mode_picker.add_item(str(option.label))
		display_mode_picker.set_item_metadata(display_mode_picker.item_count - 1, str(option.value))

	resolution_picker.clear()
	var current_screen_size := Vector2i.ZERO
	if DisplayServer.get_name() != "headless":
		current_screen_size = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	for resolution in WINDOW_RESOLUTIONS:
		if current_screen_size != Vector2i.ZERO and (resolution.x > current_screen_size.x or resolution.y > current_screen_size.y):
			continue
		_add_resolution_option(resolution)
	if resolution_picker.item_count == 0:
		_add_resolution_option(Vector2i(1280, 720))

	fps_picker.clear()
	for option in FPS_LIMITS:
		fps_picker.add_item(str(option.label))
		fps_picker.set_item_metadata(fps_picker.item_count - 1, int(option.value))

	quality_picker.clear()
	for option in QUALITY_LEVELS:
		quality_picker.add_item(str(option.label))
		quality_picker.set_item_metadata(quality_picker.item_count - 1, str(option.value))


func _add_resolution_option(resolution: Vector2i) -> void:
	for index in range(resolution_picker.item_count):
		if _resolution_from_variant(resolution_picker.get_item_metadata(index)) == resolution:
			return
	resolution_picker.add_item("%d × %d" % [resolution.x, resolution.y])
	resolution_picker.set_item_metadata(resolution_picker.item_count - 1, resolution)


func _build_binding_rows() -> void:
	for child in binding_rows.get_children():
		child.queue_free()
	_binding_buttons.clear()
	var ordered_actions: Array = []
	for action in MANAGED_ACTIONS:
		if str(action.context) == "dive":
			ordered_actions.append(action)
	for action in MANAGED_ACTIONS:
		if str(action.context) != "dive":
			ordered_actions.append(action)
	for action in ordered_actions:
		var action_id := str(action.id)
		var row := GridContainer.new()
		row.name = "BindingRow_%s" % action_id
		row.columns = 3
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 0)
		binding_rows.add_child(row)

		var label := Label.new()
		label.custom_minimum_size = Vector2(0, 32)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = str(action.label)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.tooltip_text = str(action.label)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		row.add_child(label)

		for slot in range(2):
			var button := Button.new()
			button.name = "Binding_%s_%d" % [action_id, slot]
			button.custom_minimum_size = Vector2(78, 32)
			button.text = EMPTY_BINDING_LABEL
			button.add_theme_font_size_override("font_size", 12)
			button.tooltip_text = "Zmień główny klawisz" if slot == 0 else "Zmień lub usuń dodatkowy klawisz"
			button.pressed.connect(_begin_capture.bind(action_id, slot))
			row.add_child(button)
			_binding_buttons[_binding_key(action_id, slot)] = button

func _show_section(section_id: String) -> void:
	for current_id in _sections.keys():
		var section: Control = _sections[current_id]
		section.visible = str(current_id) == section_id
	for current_id in _category_buttons.keys():
		var button: Button = _category_buttons[current_id]
		button.set_pressed_no_signal(str(current_id) == section_id)
	content_scroll.scroll_vertical = 0


func _sync_from_draft() -> void:
	_syncing = true
	var display := _section(_draft, "display")
	var graphics := _section(_draft, "graphics")
	var audio := _section(_draft, "audio")
	var accessibility := _section(_draft, "accessibility")

	_select_metadata(display_mode_picker, str(display.get("mode", "windowed")))
	var resolution := _resolution_from_variant(display.get("resolution", Vector2i(1280, 720)))
	if resolution == Vector2i.ZERO:
		resolution = Vector2i(1280, 720)
	_add_resolution_option(resolution)
	_select_metadata(resolution_picker, resolution)
	vsync_check.set_pressed_no_signal(bool(display.get("vsync", true)))
	vsync_check.text = "WŁĄCZONA" if vsync_check.button_pressed else "WYŁĄCZONA"
	_select_metadata(fps_picker, int(display.get("max_fps", 60)))
	_select_metadata(quality_picker, str(graphics.get("quality", "high")))

	master_volume_slider.set_value_no_signal(clampf(float(audio.get("master_volume", 0.8)), 0.0, 1.0))
	master_mute_check.set_pressed_no_signal(bool(audio.get("master_muted", false)))
	_update_volume_label()

	reduced_motion_check.set_pressed_no_signal(bool(accessibility.get("reduced_motion", false)))
	pause_focus_check.set_pressed_no_signal(bool(accessibility.get("pause_on_focus_loss", true)))
	_refresh_binding_labels()
	_syncing = false
	_update_display_geometry_controls()


func _select_metadata(picker: OptionButton, wanted) -> bool:
	for index in range(picker.item_count):
		var metadata = picker.get_item_metadata(index)
		if metadata == wanted:
			picker.select(index)
			return true
		if wanted is Vector2i and _resolution_from_variant(metadata) == wanted:
			picker.select(index)
			return true
	return false


func _refresh_display_geometry_capability() -> void:
	_display_geometry_capability = {
		"supported": false,
		"embedded": false,
		"headless": false,
		"reason": "Nie udało się sprawdzić możliwości zmiany geometrii okna.",
	}
	if user_settings == null:
		return
	var capability = user_settings.display_geometry_capability()
	if capability is Dictionary:
		_display_geometry_capability = (capability as Dictionary).duplicate(true)


func _display_geometry_supported() -> bool:
	return bool(_display_geometry_capability.get("supported", false))


func _update_display_geometry_controls() -> void:
	var geometry_supported := _display_geometry_supported()
	var display := _section(_draft, "display")
	var mode := str(display.get("mode", "windowed"))
	var capability_reason := str(_display_geometry_capability.get("reason", "")).strip_edges()
	display_mode_picker.disabled = not geometry_supported
	resolution_picker.disabled = not geometry_supported or mode != "windowed"

	var message := ""
	if bool(_display_geometry_capability.get("embedded", false)):
		message = "Zmiana trybu i rozdzielczości jest niedostępna w osadzonym podglądzie. Wyłącz \"Embed Game on Next Play\" w edytorze Godot i uruchom grę ponownie."
	elif bool(_display_geometry_capability.get("headless", false)):
		message = "Zmiana trybu i rozdzielczości jest niedostępna w trybie headless."
	elif not geometry_supported:
		message = "Zmiana trybu i rozdzielczości jest niedostępna."
		if not capability_reason.is_empty():
			message += " %s" % capability_reason
	elif mode == "borderless":
		message = "Tryb bezramkowy korzysta z natywnej rozdzielczości bieżącego monitora. Zapamiętana rozdzielczość okna zostanie użyta po powrocie do trybu okienkowego."
	else:
		message = "Zmiana trybu lub rozdzielczości wymaga potwierdzenia w ciągu 15 sekund. W przeciwnym razie poprzedni obraz zostanie przywrócony."
	if not geometry_supported and not capability_reason.is_empty() and capability_reason not in message:
		message += "\nPowód: %s" % capability_reason
	display_warning.text = message
	display_mode_picker.tooltip_text = message
	resolution_picker.tooltip_text = message


func _on_display_mode_selected(index: int) -> void:
	if _syncing or not _valid_picker_index(display_mode_picker, index):
		return
	var mode := str(display_mode_picker.get_item_metadata(index))
	_set_section_value("display", "mode", mode)
	_update_display_geometry_controls()


func _on_resolution_selected(index: int) -> void:
	if _syncing or not _valid_picker_index(resolution_picker, index):
		return
	_set_section_value("display", "resolution", _resolution_from_variant(resolution_picker.get_item_metadata(index)))


func _on_vsync_toggled(enabled: bool) -> void:
	if _syncing:
		return
	_set_section_value("display", "vsync", enabled)
	vsync_check.text = "WŁĄCZONA" if enabled else "WYŁĄCZONA"


func _on_fps_selected(index: int) -> void:
	if _syncing or not _valid_picker_index(fps_picker, index):
		return
	_set_section_value("display", "max_fps", int(fps_picker.get_item_metadata(index)))


func _on_quality_selected(index: int) -> void:
	if _syncing or not _valid_picker_index(quality_picker, index):
		return
	_set_section_value("graphics", "quality", str(quality_picker.get_item_metadata(index)))


func _on_master_volume_changed(value: float) -> void:
	if _syncing:
		return
	_set_section_value("audio", "master_volume", clampf(value, 0.0, 1.0))
	_update_volume_label()
	_preview_audio()


func _on_master_volume_drag_ended(value_changed: bool) -> void:
	if value_changed and not master_mute_check.button_pressed:
		_play_test_tone()


func _on_master_mute_toggled(enabled: bool) -> void:
	if _syncing:
		return
	_set_section_value("audio", "master_muted", enabled)
	_preview_audio()
	if enabled:
		test_tone_player.stop()
	else:
		_play_test_tone()


func _on_reduced_motion_toggled(enabled: bool) -> void:
	if not _syncing:
		_set_section_value("accessibility", "reduced_motion", enabled)


func _on_pause_focus_toggled(enabled: bool) -> void:
	if not _syncing:
		_set_section_value("accessibility", "pause_on_focus_loss", enabled)


func _update_volume_label() -> void:
	volume_value_label.text = "%d%%" % int(round(master_volume_slider.value * 100.0))


func _preview_audio() -> void:
	if user_settings != null:
		user_settings.preview_audio(_section(_draft, "audio").duplicate(true))


func _play_test_tone() -> void:
	_preview_audio()
	if bool(_section(_draft, "audio").get("master_muted", false)):
		_set_status("Dźwięk główny jest wyciszony.", true)
		return
	test_tone_player.stop()
	test_tone_player.play()
	_set_status("Odtworzono dźwięk testowy przez magistralę Master.")


func _build_test_tone() -> void:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = TEST_TONE_SAMPLE_RATE
	stream.stereo = false
	var frame_count := int(round(TEST_TONE_SAMPLE_RATE * TEST_TONE_SECONDS))
	var samples := PackedByteArray()
	samples.resize(frame_count * 2)
	for frame in range(frame_count):
		var progress := float(frame) / float(maxi(frame_count - 1, 1))
		var envelope := minf(progress / 0.08, 1.0) * minf((1.0 - progress) / 0.16, 1.0)
		var sample := int(round(sin(TAU * TEST_TONE_HZ * float(frame) / float(TEST_TONE_SAMPLE_RATE)) * 0.2 * envelope * 32767.0))
		samples.encode_s16(frame * 2, clampi(sample, -32768, 32767))
	stream.data = samples
	test_tone_player.stream = stream


func _begin_capture(action_id: String, slot: int) -> void:
	_capture_action_id = action_id
	_capture_slot = slot
	var action_label := _action_label(action_id)
	var slot_label := "główny" if slot == 0 else "dodatkowy"
	capture_prompt.text = "%s\nPrzypisanie: %s" % [action_label, slot_label]
	capture_overlay.show()
	capture_overlay.move_to_front()
	capture_cancel_button.grab_focus()


func _cancel_capture() -> void:
	_capture_action_id = ""
	_capture_slot = -1
	capture_overlay.hide()
	if visible:
		controls_category_button.grab_focus()


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if not _capture_action_id.is_empty():
		get_viewport().set_input_as_handled()
		if key_event.keycode == KEY_ESCAPE:
			_cancel_capture()
			return
		if key_event.keycode == KEY_DELETE:
			if _capture_slot == 1:
				var cleared_action := _capture_action_id
				_set_binding(cleared_action, _capture_slot, {})
				binding_status.text = "Usunięto dodatkowy klawisz dla: %s." % _action_label(cleared_action)
				_cancel_capture()
			else:
				capture_prompt.text = "%s\nGłównego klawisza nie można usunąć. Naciśnij nowy klawisz albo ESC." % _action_label(_capture_action_id)
			return
		if key_event.keycode == KEY_F10:
			capture_prompt.text = "%s\nF10 jest zarezerwowany dla telemetrii deweloperskiej. Wybierz inny klawisz albo naciśnij ESC." % _action_label(_capture_action_id)
			return
		var record := _record_from_key_event(key_event)
		if _binding_is_empty(record):
			return
		var conflicting_action := _find_conflict(_capture_action_id, _capture_slot, record)
		if not conflicting_action.is_empty():
			capture_prompt.text = "%s\nTen klawisz jest już używany przez: %s. Wybierz inny albo naciśnij ESC." % [
				_action_label(_capture_action_id),
				_action_label(conflicting_action),
			]
			return
		var changed_action := _capture_action_id
		_set_binding(changed_action, _capture_slot, record)
		binding_status.text = "Zmieniono przypisanie: %s → %s." % [_action_label(changed_action), _binding_label(record)]
		_cancel_capture()
		return
	if key_event.keycode == KEY_ESCAPE and not display_confirmation.visible:
		get_viewport().set_input_as_handled()
		_cancel_and_close()


func _set_binding(action_id: String, slot: int, record: Dictionary) -> void:
	var controls := _section(_draft, "controls").duplicate(true)
	var slots: Array = _action_bindings(controls, action_id)
	while slots.size() < 2:
		slots.append({})
	slots[slot] = record.duplicate(true)
	controls[action_id] = slots
	_draft["controls"] = controls
	_refresh_binding_labels()


func _refresh_binding_labels() -> void:
	var controls := _section(_draft, "controls")
	for action in MANAGED_ACTIONS:
		var action_id := str(action.id)
		var slots := _action_bindings(controls, action_id)
		for slot in range(2):
			var button: Button = _binding_buttons.get(_binding_key(action_id, slot))
			if button == null:
				continue
			var binding: Dictionary = slots[slot] if slot < slots.size() and slots[slot] is Dictionary else {}
			button.text = _binding_label(binding)
			button.add_theme_color_override("font_color", Color("d9e3df") if not _binding_is_empty(binding) else Color("6f8584"))


func _action_bindings(controls: Dictionary, action_id: String) -> Array:
	var raw = controls.get(action_id, [])
	var result: Array = []
	if raw is Array:
		for value in raw:
			if value is Dictionary:
				result.append((value as Dictionary).duplicate(true))
			if result.size() >= 2:
				break
	while result.size() < 2:
		result.append({})
	return result


func _record_from_key_event(event: InputEventKey) -> Dictionary:
	return {
		"type": "key",
		"keycode": int(event.keycode),
		"physical_keycode": int(event.physical_keycode),
		"unicode": int(event.unicode),
		"shift_pressed": bool(event.shift_pressed),
		"alt_pressed": bool(event.alt_pressed),
		"ctrl_pressed": bool(event.ctrl_pressed),
		"meta_pressed": bool(event.meta_pressed),
	}


func _binding_label(record: Dictionary) -> String:
	if _binding_is_empty(record):
		return EMPTY_BINDING_LABEL
	var event := InputEventKey.new()
	event.keycode = int(record.get("keycode", 0))
	event.physical_keycode = int(record.get("physical_keycode", 0))
	event.unicode = int(record.get("unicode", 0))
	event.shift_pressed = bool(record.get("shift_pressed", false))
	event.alt_pressed = bool(record.get("alt_pressed", false))
	event.ctrl_pressed = bool(record.get("ctrl_pressed", false))
	event.meta_pressed = bool(record.get("meta_pressed", false))
	var label := InputPromptScript.event_text(event)
	return label if not label.is_empty() else EMPTY_BINDING_LABEL


func _find_conflict(action_id: String, slot: int, candidate: Dictionary) -> String:
	var context := _action_context(action_id)
	var controls := _section(_draft, "controls")
	for action in MANAGED_ACTIONS:
		var other_id := str(action.id)
		if str(action.context) != context:
			continue
		var bindings := _action_bindings(controls, other_id)
		for other_slot in range(bindings.size()):
			if other_id == action_id and other_slot == slot:
				continue
			var other: Dictionary = bindings[other_slot] if bindings[other_slot] is Dictionary else {}
			if _bindings_conflict(candidate, other):
				return other_id
	return ""


func _bindings_conflict(first: Dictionary, second: Dictionary) -> bool:
	if _binding_is_empty(first) or _binding_is_empty(second):
		return false
	for modifier in ["shift_pressed", "alt_pressed", "ctrl_pressed", "meta_pressed"]:
		if bool(first.get(modifier, false)) != bool(second.get(modifier, false)):
			return false
	var first_codes := [int(first.get("keycode", 0)), int(first.get("physical_keycode", 0))]
	var second_codes := [int(second.get("keycode", 0)), int(second.get("physical_keycode", 0))]
	for first_code in first_codes:
		if first_code == 0:
			continue
		for second_code in second_codes:
			if first_code == second_code and second_code != 0:
				return true
	return false


func _binding_is_empty(record: Dictionary) -> bool:
	return int(record.get("keycode", 0)) == 0 and int(record.get("physical_keycode", 0)) == 0


func _restore_defaults() -> void:
	if user_settings == null or _apply_in_progress or _awaiting_display_confirmation:
		return
	var defaults = user_settings.defaults_snapshot()
	if not defaults is Dictionary:
		_set_status("Nie udało się odczytać ustawień domyślnych.", true)
		return
	_draft = _sanitize_snapshot(defaults)
	# W osadzonym podglądzie i headless geometria jest celowo nieedytowalna.
	# Reset zachowuje więc jej bieżące wartości, aby nadal można było jednym
	# kliknięciem przywrócić wszystkie rzeczywiście obsługiwane ustawienia.
	if not _display_geometry_supported() and not _original_snapshot.is_empty():
		var reset_display := _section(_draft, "display").duplicate(true)
		var original_display := _section(_original_snapshot, "display")
		reset_display["mode"] = str(original_display.get("mode", "windowed"))
		reset_display["resolution"] = _resolution_from_variant(
			original_display.get("resolution", Vector2i(1280, 720))
		)
		_draft["display"] = reset_display
	_sync_from_draft()
	_preview_audio()
	_set_status("Przywrócono wartości domyślne w podglądzie. Wybierz ZASTOSUJ, aby je zapisać.")


func _sync_picker_metadata_to_draft() -> bool:
	for picker in [display_mode_picker, resolution_picker, fps_picker, quality_picker]:
		if not _valid_picker_index(picker, picker.selected):
			return false

	var selected_resolution := _resolution_from_variant(
		resolution_picker.get_item_metadata(resolution_picker.selected)
	)
	if selected_resolution == Vector2i.ZERO:
		return false
	_set_section_value(
		"display",
		"mode",
		str(display_mode_picker.get_item_metadata(display_mode_picker.selected))
	)
	_set_section_value("display", "resolution", selected_resolution)
	_set_section_value("display", "max_fps", int(fps_picker.get_item_metadata(fps_picker.selected)))
	_set_section_value("graphics", "quality", str(quality_picker.get_item_metadata(quality_picker.selected)))
	_update_display_geometry_controls()
	return true


func _apply_draft() -> void:
	if user_settings == null or _awaiting_display_confirmation or _apply_in_progress:
		return
	_set_apply_in_progress(true)
	_refresh_display_geometry_capability()
	if not _sync_picker_metadata_to_draft():
		_set_status("Nie udało się odczytać wybranych opcji obrazu.", true)
		_set_apply_in_progress(false)
		return
	var candidate := _sanitize_snapshot(_draft)
	if candidate.is_empty():
		_set_status("Ustawienia nie przeszły walidacji.", true)
		_set_apply_in_progress(false)
		return
	var geometry_changed := _display_output_changed(_original_snapshot, candidate)
	if geometry_changed and not _display_geometry_supported():
		var unsupported_reason := str(_display_geometry_capability.get("reason", "")).strip_edges()
		var unsupported_message := "Nie można zastosować zmiany trybu ani rozdzielczości w tym środowisku."
		if not unsupported_reason.is_empty():
			unsupported_message += " %s" % unsupported_reason
		_set_status(unsupported_message, true)
		_update_display_geometry_controls()
		_set_apply_in_progress(false)
		return
	var apply_error := int(user_settings.apply(candidate.duplicate(true), false))
	if apply_error != OK:
		_set_status("Nie udało się zastosować ustawień (kod %d)." % apply_error, true)
		_set_apply_in_progress(false)
		return
	_draft = candidate.duplicate(true)
	if geometry_changed:
		var verification := await _wait_for_display_verification(
			_section(candidate, "display").duplicate(true)
		)
		if verification.is_empty():
			await _rollback_display_change("Nie udało się zweryfikować nowych ustawień obrazu. Przywrócono poprzednie wartości.")
			return
		if not bool(verification.get("supported", false)) or not bool(verification.get("matches", false)):
			var mismatch_reason := str(verification.get("reason", "")).strip_edges()
			var mismatch_message := "Silnik nie potwierdził żądanego trybu lub rozdzielczości. Przywrócono poprzednie ustawienia obrazu."
			if not mismatch_reason.is_empty():
				mismatch_message += " %s" % mismatch_reason
			await _rollback_display_change(mismatch_message)
			return
		_pending_candidate = candidate.duplicate(true)
		_set_apply_in_progress(false)
		_start_display_confirmation()
		return
	var save_error := int(user_settings.save_current())
	if save_error != OK:
		user_settings.apply(_original_snapshot.duplicate(true), false)
		user_settings.preview_audio(_section(_original_snapshot, "audio").duplicate(true))
		_draft = _original_snapshot.duplicate(true)
		_sync_from_draft()
		_set_status("Nie udało się zapisać ustawień (kod %d). Przywrócono poprzednie wartości." % save_error, true)
		_set_apply_in_progress(false)
		return
	_original_snapshot = _settings_snapshot()
	_set_apply_in_progress(false)
	_close_without_restore()


func _display_output_changed(before: Dictionary, after: Dictionary) -> bool:
	var old_display := _section(before, "display")
	var new_display := _section(after, "display")
	if str(old_display.get("mode", "windowed")) != str(new_display.get("mode", "windowed")):
		return true
	return _resolution_from_variant(old_display.get("resolution", Vector2i.ZERO)) != _resolution_from_variant(new_display.get("resolution", Vector2i.ZERO))


func _wait_for_display_verification(expected_display: Dictionary, frame_limit: int = DISPLAY_VERIFY_FRAME_LIMIT) -> Dictionary:
	var last_verification: Dictionary = {}
	for _frame in range(maxi(frame_limit, 1)):
		await get_tree().process_frame
		var verification = user_settings.verify_display_output(expected_display.duplicate(true))
		if not verification is Dictionary:
			return {}
		last_verification = (verification as Dictionary).duplicate(true)
		if not bool(last_verification.get("supported", false)) or bool(last_verification.get("matches", false)):
			break
	return last_verification


func _start_display_confirmation() -> void:
	_awaiting_display_confirmation = true
	_update_action_buttons()
	_display_seconds_remaining = DISPLAY_CONFIRM_SECONDS
	_update_display_confirmation_text()
	display_confirmation.popup_centered(Vector2i(560, 220))
	display_rollback_timer.start()


func _display_countdown_tick() -> void:
	if not _awaiting_display_confirmation:
		display_rollback_timer.stop()
		return
	_display_seconds_remaining -= 1
	if _display_seconds_remaining <= 0:
		display_rollback_timer.stop()
		display_confirmation.hide()
		await _rollback_display_change("Minął czas potwierdzenia. Przywrócono poprzedni obraz.")
		return
	_update_display_confirmation_text()


func _update_display_confirmation_text() -> void:
	display_confirmation.dialog_text = "Czy obraz jest czytelny? Zachować nowe ustawienia?\n\nAutomatyczne cofnięcie za %d s." % _display_seconds_remaining


func _confirm_display_change() -> void:
	if not _awaiting_display_confirmation or _apply_in_progress:
		return
	display_rollback_timer.stop()
	_awaiting_display_confirmation = false
	_set_apply_in_progress(true)
	if user_settings == null or _pending_candidate.is_empty():
		await _rollback_display_change("Brakuje oczekujących ustawień obrazu. Przywrócono poprzednie wartości.")
		return

	if _settings_snapshot() != _pending_candidate:
		var reapply_error := int(user_settings.apply(_pending_candidate.duplicate(true), false))
		if reapply_error != OK:
			await _rollback_display_change("Nie udało się ponownie zastosować zatwierdzanych ustawień (kod %d). Przywrócono poprzedni obraz." % reapply_error)
			return

	# Snapshot ustawień może pozostać bez zmian mimo ręcznego przeskalowania
	# okna przez użytkownika albo system. Dlatego przed każdym zapisem ponownie
	# sprawdzamy rzeczywisty output, również gdy kandydat nie wymagał reaplikacji.
	var verification := await _wait_for_display_verification(
		_section(_pending_candidate, "display").duplicate(true)
	)
	if verification.is_empty():
		await _rollback_display_change("Nie udało się zweryfikować zatwierdzanych ustawień obrazu. Przywrócono poprzednie wartości.")
		return
	if not bool(verification.get("supported", false)) or not bool(verification.get("matches", false)):
		var verification_reason := str(verification.get("reason", "")).strip_edges()
		var verification_message := "Zatwierdzane ustawienia nie odpowiadają rzeczywistemu obrazowi. Przywrócono poprzednie wartości."
		if not verification_reason.is_empty():
			verification_message += " %s" % verification_reason
		await _rollback_display_change(verification_message)
		return

	if _settings_snapshot() != _pending_candidate:
		await _rollback_display_change("Nie udało się utrwalić dokładnie zatwierdzonego zestawu ustawień. Przywrócono poprzednie wartości.")
		return
	var save_error := int(user_settings.save_current())
	if save_error != OK:
		await _rollback_display_change("Nie udało się zapisać ustawień (kod %d). Przywrócono poprzedni obraz." % save_error)
		return
	_original_snapshot = _pending_candidate.duplicate(true)
	_pending_candidate.clear()
	_set_apply_in_progress(false)
	_close_without_restore()


func _cancel_display_change() -> void:
	if _awaiting_display_confirmation:
		await _rollback_display_change("Przywrócono poprzednie ustawienia obrazu.")


func _rollback_display_change(message: String) -> bool:
	display_rollback_timer.stop()
	_awaiting_display_confirmation = false
	_pending_candidate.clear()
	_set_apply_in_progress(true)
	var restored := user_settings != null and not _original_snapshot.is_empty()
	var failure_reason := ""
	if restored:
		var rollback_error := int(user_settings.apply(_original_snapshot.duplicate(true), false))
		if rollback_error != OK:
			restored = false
			failure_reason = "Kod błędu zastosowania: %d." % rollback_error
		else:
			user_settings.preview_audio(_section(_original_snapshot, "audio").duplicate(true))
			var verification := await _wait_for_display_verification(
				_section(_original_snapshot, "display").duplicate(true)
			)
			restored = (
				not verification.is_empty()
				and bool(verification.get("supported", false))
				and bool(verification.get("matches", false))
				and _settings_snapshot() == _original_snapshot
			)
			if not restored:
				failure_reason = str(verification.get("reason", "")).strip_edges()
				if failure_reason.is_empty():
					failure_reason = "Rzeczywisty tryb lub rozmiar okna nadal różni się od poprzednich ustawień."
	else:
		failure_reason = "Brak poprzedniej migawki ustawień."

	_draft = _original_snapshot.duplicate(true) if restored else _settings_snapshot()
	_sync_from_draft()
	_set_apply_in_progress(false)
	if restored:
		_set_status(message, true)
	else:
		_set_status("Nie udało się potwierdzić przywrócenia poprzedniego obrazu. %s" % failure_reason, true)
	if visible:
		apply_button.grab_focus()
	return restored


func _cancel_and_close() -> void:
	if _awaiting_display_confirmation or _apply_in_progress:
		return
	test_tone_player.stop()
	_capture_action_id = ""
	_capture_slot = -1
	capture_overlay.hide()
	if user_settings != null and not _original_snapshot.is_empty():
		user_settings.preview_audio(_section(_original_snapshot, "audio").duplicate(true))
	hide()
	_restore_return_focus()
	closed.emit()


func _close_without_restore() -> void:
	test_tone_player.stop()
	_capture_action_id = ""
	_capture_slot = -1
	capture_overlay.hide()
	hide()
	_restore_return_focus()
	closed.emit()


func _restore_return_focus() -> void:
	if _return_focus == null:
		return
	var control = _return_focus.get_ref()
	if control is Control and is_instance_valid(control) and (control as Control).is_visible_in_tree():
		(control as Control).call_deferred("grab_focus")


func _on_gui_focus_changed(control: Control) -> void:
	if not visible or display_confirmation.visible:
		return
	var focus_root: Control = capture_overlay if capture_overlay.visible else self
	if control == null or (control != focus_root and not focus_root.is_ancestor_of(control)):
		var fallback: Control = capture_cancel_button if capture_overlay.visible else display_category_button
		fallback.call_deferred("grab_focus")


func _set_apply_in_progress(in_progress: bool) -> void:
	_apply_in_progress = in_progress
	_update_action_buttons()


func _update_action_buttons() -> void:
	var blocked := _apply_in_progress or _awaiting_display_confirmation
	apply_button.disabled = blocked
	defaults_button.disabled = blocked
	cancel_button.disabled = blocked
	close_button.disabled = blocked


func _set_status(message: String, error: bool = false) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color("e58d78") if error else Color("8fb3b0"))


func _sanitize_snapshot(candidate: Dictionary) -> Dictionary:
	if user_settings == null:
		return candidate.duplicate(true)
	var sanitized = user_settings.sanitize(candidate.duplicate(true))
	return (sanitized as Dictionary).duplicate(true) if sanitized is Dictionary else {}


func _settings_snapshot() -> Dictionary:
	if user_settings == null:
		return {}
	var current = user_settings.snapshot()
	return (current as Dictionary).duplicate(true) if current is Dictionary else {}


func _section(snapshot: Dictionary, section_id: String) -> Dictionary:
	var value = snapshot.get(section_id, {})
	return value as Dictionary if value is Dictionary else {}


func _set_section_value(section_id: String, key: String, value) -> void:
	var section := _section(_draft, section_id).duplicate(true)
	section[key] = value
	_draft[section_id] = section


func _resolution_from_variant(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(roundi(value.x), roundi(value.y))
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	if value is String:
		var normalized := str(value).to_lower().replace("×", "x").replace(" ", "")
		var pieces := normalized.split("x", false)
		if pieces.size() == 2 and pieces[0].is_valid_int() and pieces[1].is_valid_int():
			return Vector2i(int(pieces[0]), int(pieces[1]))
	return Vector2i.ZERO


func _valid_picker_index(picker: OptionButton, index: int) -> bool:
	return index >= 0 and index < picker.item_count


func _binding_key(action_id: String, slot: int) -> String:
	return "%s:%d" % [action_id, slot]


func _action_label(action_id: String) -> String:
	for action in MANAGED_ACTIONS:
		if str(action.id) == action_id:
			return str(action.label)
	return action_id


func _action_context(action_id: String) -> String:
	for action in MANAGED_ACTIONS:
		if str(action.id) == action_id:
			return str(action.context)
	return ""
