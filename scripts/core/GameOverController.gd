class_name GameOverController
extends Control

const CampaignProgressionSystemScript := preload("res://scripts/campaign/CampaignProgressionSystem.gd")

var game_root: Node
var game_state
var _title: Label
var _description: Label
var _summary: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func bind(root: Node, state) -> void:
	game_root = root
	game_state = state
	_render()

func _build_ui() -> void:
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color("090e12")
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 24
	center.offset_top = 24
	center.offset_right = -24
	center.offset_bottom = -24
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 480)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171719f4")
	style.border_color = Color("a95f55")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 44)
	margin.add_theme_constant_override("margin_top", 38)
	margin.add_theme_constant_override("margin_right", 44)
	margin.add_theme_constant_override("margin_bottom", 34)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)
	var eyebrow := Label.new()
	eyebrow.text = "KRONIKA ZAMKNIĘTA"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_color_override("font_color", Color("c98a78"))
	content.add_child(eyebrow)
	_title = Label.new()
	_title.name = "GameOverTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color("f0c5ad"))
	content.add_child(_title)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_description.add_theme_font_size_override("font_size", 18)
	_description.add_theme_color_override("font_color", Color("d8d5cf"))
	_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_description)
	_summary = Label.new()
	_summary.name = "GameOverSummary"
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.add_theme_color_override("font_color", Color("aab4b2"))
	content.add_child(_summary)
	var menu := Button.new()
	menu.name = "GameOverMainMenuButton"
	menu.text = "WRÓĆ DO MENU GŁÓWNEGO"
	menu.custom_minimum_size = Vector2(0, 54)
	menu.pressed.connect(_on_menu_pressed)
	content.add_child(menu)

func _render() -> void:
	if _title == null:
		return
	var reason := ""
	if game_state != null and game_state.story_flags != null:
		reason = str(game_state.story_flags.game_over_reason)
	var campaign := CampaignProgressionSystemScript.new()
	_title.text = campaign.game_over_title(reason).to_upper()
	_description.text = campaign.game_over_description(reason)
	if game_state != null:
		_summary.text = "Dzień %d  •  Ocalali %d  •  Nadzieja %d  •  Integralność %d%%" % [
			maxi(int(game_state.story_flags.game_over_day), 1) if game_state.story_flags != null else maxi(int(game_state.day) - 1, 1),
			game_state.get_alive_survivors().size(),
			game_state.resources.get_amount("hope"),
			game_state.resources.get_amount("platform_integrity"),
		]

func _on_menu_pressed() -> void:
	if game_root != null:
		game_root.return_to_main_menu()
