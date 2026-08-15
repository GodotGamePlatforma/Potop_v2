extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const TEST_SAVE_PRIMARY := "user://test_settings_snapshot_autosave.tres"
const TEST_SAVE_PENDING := "user://test_settings_snapshot_autosave.pending.tres"
const TEST_SAVE_BACKUP := "user://test_settings_snapshot_autosave.backup.tres"

const SNAPSHOTS := {
	"main_menu": "settings_main_menu.png",
	"main_menu_5_4": "settings_main_menu_5_4.png",
	"main_menu_21_9": "settings_main_menu_21_9.png",
	"display": "settings_display.png",
	"audio": "settings_audio.png",
	"controls": "settings_controls.png",
	"general": "settings_general.png",
}

var _failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	SaveManager.configure_paths(TEST_SAVE_PRIMARY, TEST_SAVE_PENDING, TEST_SAVE_BACKUP)
	var output_directory := ProjectSettings.globalize_path("res://tmp")
	if not DirAccess.dir_exists_absolute(output_directory):
		DirAccess.make_dir_recursive_absolute(output_directory)
	var game_root = GameRootScene.instantiate()
	add_child(game_root)
	await get_tree().process_frame
	await get_tree().process_frame
	var menu: Control = game_root.current_scene as Control
	var settings_button := menu.find_child("SettingsButton", true, false) as Button
	var overlay := menu.find_child("SettingsOverlay", true, false) as Control
	var key_art := menu.find_child("KeyArt", true, false) as TextureRect
	var menu_panel := menu.get_node_or_null("Center/MenuPanel") as Control
	var settings_panel := overlay.find_child("SettingsPanel", true, false) as Control if overlay != null else null
	if settings_button == null or overlay == null or key_art == null or menu_panel == null or settings_panel == null:
		push_error("Settings UI snapshot failed: menu controls are missing.")
		SaveManager.reset_paths()
		get_tree().quit(1)
		return
	if (
		key_art.texture == null
		or key_art.texture.resource_path != "res://assets/ui/main_menu_key_art_v1.png"
		or key_art.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_COVERED
		or menu.theme == null
		or menu.theme.resource_path != "res://assets/ui/main_menu_theme.tres"
	):
		_failed = true
		push_error("Settings UI snapshot failed: the clean single-campaign menu art/theme contract is invalid.")
	if menu_panel.get_global_rect().end.x > 624.0:
		_failed = true
		push_error("Settings UI snapshot failed: the menu panel should stay in the dark left rail at 1280x720.")
	await _capture(SNAPSHOTS["main_menu"])
	await _capture_at_window_size(Vector2i(1280, 1024), SNAPSHOTS["main_menu_5_4"])
	await _capture_at_window_size(Vector2i(1680, 720), SNAPSHOTS["main_menu_21_9"])
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	settings_button.pressed.emit()
	await get_tree().process_frame
	_validate_settings_panel(settings_panel, "display")
	await _capture(SNAPSHOTS["display"])
	for category_id: String in ["audio", "controls", "general"]:
		var button_name: String = {
			"audio": "AudioCategoryButton",
			"controls": "ControlsCategoryButton",
			"general": "GeneralCategoryButton",
		}[category_id]
		var category_button := overlay.find_child(button_name, true, false) as Button
		category_button.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_validate_settings_panel(settings_panel, category_id)
		await _capture(SNAPSHOTS[category_id])
	game_root.queue_free()
	SaveManager.reset_paths()
	if _failed:
		get_tree().quit(1)
		return
	print("Settings UI snapshots written: main menu aspects, display, audio, controls and general.")
	get_tree().quit(0)


func _capture_at_window_size(window_size: Vector2i, file_name: String) -> void:
	get_window().size = window_size
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture(file_name)


func _validate_settings_panel(panel: Control, category_id: String) -> void:
	var panel_rect := panel.get_global_rect()
	var viewport_rect := get_viewport().get_visible_rect()
	if not viewport_rect.encloses(panel_rect):
		_failed = true
		push_error("Settings UI snapshot failed: panel leaves the viewport in category %s." % category_id)


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		_failed = true
		push_error("Settings UI snapshot failed: viewport image is empty for %s." % file_name)
		return
	var error := image.save_png(ProjectSettings.globalize_path("res://tmp/" + file_name))
	if error != OK:
		_failed = true
		push_error("Settings UI snapshot failed: could not save %s (error %d)." % [file_name, error])
