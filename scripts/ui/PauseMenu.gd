class_name PauseMenu
extends Control

signal continue_requested()
signal save_requested()
signal settings_requested()
signal main_menu_requested()
signal quit_requested()

@onready var context_label: Label = $SafeMargin/Center/PausePanel/OuterMargin/Layout/ContextLabel
@onready var continue_button: Button = $SafeMargin/Center/PausePanel/OuterMargin/Layout/ContinueButton
@onready var save_button: Button = $SafeMargin/Center/PausePanel/OuterMargin/Layout/SaveButton
@onready var save_note: Label = $SafeMargin/Center/PausePanel/OuterMargin/Layout/SaveNote
@onready var status_label: Label = $SafeMargin/Center/PausePanel/OuterMargin/Layout/StatusLabel
@onready var settings_button: Button = $SafeMargin/Center/PausePanel/OuterMargin/Layout/SettingsButton
@onready var main_menu_button: Button = $SafeMargin/Center/PausePanel/OuterMargin/Layout/MainMenuButton
@onready var main_menu_note: Label = $SafeMargin/Center/PausePanel/OuterMargin/Layout/MainMenuNote
@onready var quit_button: Button = $SafeMargin/Center/PausePanel/OuterMargin/Layout/QuitButton
@onready var quit_note: Label = $SafeMargin/Center/PausePanel/OuterMargin/Layout/QuitNote

var _return_focus: WeakRef
var _focus_controls: Array[Control] = []
var _last_menu_focus: Control
var _main_menu_confirmation: ConfirmationDialog
var _secondary_modal_open: bool = false


func _ready() -> void:
	continue_button.pressed.connect(func(): continue_requested.emit())
	save_button.pressed.connect(func(): save_requested.emit())
	settings_button.pressed.connect(func(): settings_requested.emit())
	main_menu_button.pressed.connect(_show_main_menu_confirmation)
	quit_button.pressed.connect(func(): quit_requested.emit())
	_main_menu_confirmation = ConfirmationDialog.new()
	_main_menu_confirmation.name = "MainMenuConfirmation"
	_main_menu_confirmation.title = "Powrót do menu głównego"
	_main_menu_confirmation.dialog_text = "Wrócić do menu głównego bez zapisywania?"
	_main_menu_confirmation.ok_button_text = "WRÓĆ BEZ ZAPISU"
	_main_menu_confirmation.cancel_button_text = "ANULUJ"
	_main_menu_confirmation.confirmed.connect(_confirm_main_menu_return)
	_main_menu_confirmation.canceled.connect(_cancel_main_menu_return)
	add_child(_main_menu_confirmation)
	set_process(false)


func open_menu(
	context_text: String,
	save_blocker: String,
	exit_note: String,
	return_note: String = "Postęp od ostatniego zapisu zostanie utracony."
) -> void:
	if visible:
		refresh_save_blocker(save_blocker)
		return
	var focus_owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	_return_focus = weakref(focus_owner) if focus_owner != null and not is_ancestor_of(focus_owner) else null
	context_label.text = context_text
	quit_note.text = exit_note
	main_menu_note.text = return_note
	_main_menu_confirmation.dialog_text = "%s\n\nCzy na pewno wrócić do menu głównego bez zapisywania?" % return_note
	_secondary_modal_open = false
	status_label.text = ""
	status_label.remove_theme_color_override("font_color")
	refresh_save_blocker(save_blocker)
	visible = true
	set_process(true)
	call_deferred("_focus_default")


func close_menu(restore_focus: bool = true) -> void:
	if not visible:
		return
	set_process(false)
	if _main_menu_confirmation != null and _main_menu_confirmation.visible:
		_main_menu_confirmation.hide()
	_secondary_modal_open = false
	var focus_owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()
	visible = false
	_last_menu_focus = null
	if restore_focus and _return_focus != null:
		var target = _return_focus.get_ref()
		if target is Control and is_instance_valid(target) and not target.is_queued_for_deletion() and target.is_visible_in_tree():
			target.call_deferred("grab_focus")
	_return_focus = null


func is_open() -> bool:
	return visible


func refresh_save_blocker(blocker: String) -> void:
	var blocked := not blocker.is_empty()
	save_button.disabled = blocked
	save_button.focus_mode = Control.FOCUS_NONE if blocked else Control.FOCUS_ALL
	save_note.text = blocker if blocked else "Zapisuje bieżący stan kampanii w bezpiecznym punkcie."
	save_note.add_theme_color_override("font_color", Color("d79880") if blocked else Color("89aaa8"))
	_configure_focus_cycle()


func show_save_result(success: bool, message: String) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color("83c5a1") if success else Color("ef927f"))
	if not save_button.disabled:
		_last_menu_focus = save_button
		save_button.call_deferred("grab_focus")


func _input(event: InputEvent) -> void:
	if not visible or _secondary_modal_open or not event.is_action_pressed(&"ui_cancel"):
		return
	if event is InputEventKey and event.echo:
		return
	get_viewport().set_input_as_handled()
	continue_requested.emit()


func _process(_delta: float) -> void:
	if not visible or _secondary_modal_open or not is_inside_tree():
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		_last_menu_focus = focus_owner
		return
	if is_instance_valid(_last_menu_focus) and _last_menu_focus in _focus_controls and not _last_menu_focus.is_queued_for_deletion():
		_last_menu_focus.grab_focus()
	else:
		_focus_default()


func _focus_default() -> void:
	if not visible or continue_button == null:
		return
	_last_menu_focus = continue_button
	continue_button.grab_focus()


func _configure_focus_cycle() -> void:
	if continue_button == null or quit_button == null:
		return
	_focus_controls.clear()
	_focus_controls.append(continue_button)
	if not save_button.disabled:
		_focus_controls.append(save_button)
	_focus_controls.append(settings_button)
	_focus_controls.append(main_menu_button)
	_focus_controls.append(quit_button)
	for index in range(_focus_controls.size()):
		var control := _focus_controls[index]
		var previous := _focus_controls[(index - 1 + _focus_controls.size()) % _focus_controls.size()]
		var next := _focus_controls[(index + 1) % _focus_controls.size()]
		control.focus_previous = control.get_path_to(previous)
		control.focus_next = control.get_path_to(next)
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_neighbor_bottom = control.get_path_to(next)


func set_secondary_modal_open(open: bool) -> void:
	_secondary_modal_open = open
	if not open and visible:
		_last_menu_focus = settings_button
		settings_button.call_deferred("grab_focus")


func _show_main_menu_confirmation() -> void:
	_secondary_modal_open = true
	_main_menu_confirmation.popup_centered()


func _confirm_main_menu_return() -> void:
	_secondary_modal_open = false
	main_menu_requested.emit()


func _cancel_main_menu_return() -> void:
	_secondary_modal_open = false
	_last_menu_focus = main_menu_button
	main_menu_button.call_deferred("grab_focus")
