class_name EndingController
extends Control

const CampaignProgressionSystemScript := preload("res://scripts/base/CampaignProgressionSystem.gd")
const NarrativeContentScript := preload("res://scripts/ui/NarrativeContent.gd")

var game_root: Node
var game_state
var _content: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_shell()

func bind(root: Node, state) -> void:
	game_root = root
	game_state = state
	_render()

func _build_shell() -> void:
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color("07141a")
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 24; center.offset_top = 18; center.offset_right = -24; center.offset_bottom = -18
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 660)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0d2025f6"); style.border_color = Color("72d8d0")
	style.set_border_width_all(2); style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 42); margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 42); margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 14)
	scroll.add_child(_content)

func _render() -> void:
	if _content == null:
		return
	for child in _content.get_children():
		child.queue_free()
	if game_state == null or game_state.story_flags == null:
		_add_centered_label("Brak danych finału.", 24, Color.WHITE)
		return
	if bool(game_state.story_flags.energy_choice_pending):
		_render_energy_choice()
	elif not str(game_state.story_flags.final_outcome_id).is_empty():
		_render_common_line_outcome()
	else:
		_add_centered_label("Brak prawidłowego finału Wspólnej Linii.", 24, Color.WHITE)
		_add_menu_button()

func _render_energy_choice() -> void:
	if game_root != null and game_root.has_method("present_ending_prelude_narrative"):
		game_root.call_deferred("present_ending_prelude_narrative")
	_add_centered_label("CZARNY FRONT  •  OSTATNIA DECYZJA", 14, Color("77d7d2"))
	_add_centered_label("WYBIERZ KIERUNEK ENERGII", 34, Color("f2d28b"))
	_add_centered_label("Przystań osiągnęła 100% integralności. Stara sieć utrzyma tylko konfigurację, którą teraz zatwierdzisz.", 17, Color("dbe5e1"))
	_content.add_child(HSeparator.new())
	var campaign = CampaignProgressionSystemScript.new()
	for option in campaign.energy_configuration_options(game_state):
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 5)
		_content.add_child(card)
		var button := Button.new()
		button.name = "EnergyChoice_%s" % str(option.id)
		button.text = str(option.title)
		button.custom_minimum_size = Vector2(0, 48)
		button.disabled = not bool(option.available)
		button.pressed.connect(_on_energy_choice_pressed.bind(str(option.id)))
		card.add_child(button)
		var description := Label.new()
		description.text = str(option.description)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		description.add_theme_color_override("font_color", Color("dbe5e1"))
		card.add_child(description)
		if not str(option.blocker).is_empty():
			var blocker := Label.new()
			blocker.text = "NIEDOSTĘPNE: %s" % str(option.blocker)
			blocker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			blocker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			blocker.add_theme_color_override("font_color", Color("e29b87"))
			card.add_child(blocker)

func _render_common_line_outcome() -> void:
	var story = game_state.story_flags
	var title := ""
	var narrative := ""
	match str(story.final_outcome_id):
		CampaignProgressionSystemScript.OUTCOME_QUIET_AFTER_STORM:
			title = "CISZA PO BURZY"
			narrative = "Cała energia została w Przystani. Pomost 7 wytrzymał Czarny Front, lecz częstotliwość Platformy Północnej odpowiada już tylko szumem."
		CampaignProgressionSystemScript.OUTCOME_DEBT_REPAID:
			title = "DŁUG SPŁACONY"
			narrative = "Przystań przeszła przez noc bez głównego zasilania, a pompy Północnej pracowały bez przerwy. O świcie obie osady ponownie nawiązały kontakt."
		CampaignProgressionSystemScript.OUTCOME_LAST_BRIDGE:
			title = "OSTATNI POMOST"
			narrative = "Rozdzielacz i Radiostacja utrzymały obie platformy na jednej linii. O świcie spoza znanych częstotliwości odpowiedział kolejny ludzki głos."
	_add_centered_label("WSPÓLNA LINIA  •  ZAKOŃCZENIE", 14, Color("77d7d2"))
	_add_centered_label(title, 38, Color("f2d28b"))
	_add_centered_label(narrative, 18, Color("dbe5e1"))
	_content.add_child(HSeparator.new())
	var summary: Dictionary = story.final_summary
	_add_centered_label("Dzień finału: %d     Ocalali: %d     Nadzieja: %d\nIntegralność: %d%%     Udane wyprawy: %d     Śmierci nurków: %d" % [
		int(summary.get("day", game_state.day)), int(summary.get("survivors", game_state.get_alive_survivors().size())),
		int(summary.get("hope", 0)), int(summary.get("platform_integrity", 100)),
		int(summary.get("successful_dives", 0)), int(summary.get("diver_deaths", 0))
	], 17, Color("dbe5e1"))
	_render_chronicle(story.chronicle_summary)
	if game_root != null and game_root.has_method("present_ending_narrative"):
		game_root.call_deferred("present_ending_narrative", NarrativeContentScript.ending_conversation(game_state))
	var continue_button := Button.new()
	continue_button.name = "ContinueCommonLineChronicleButton"
	continue_button.text = "KONTYNUUJ KRONIKĘ"
	continue_button.custom_minimum_size = Vector2(290, 52)
	continue_button.disabled = bool(story.final_chronicle_continued)
	continue_button.pressed.connect(_on_continue_pressed)
	_content.add_child(continue_button)
	_add_menu_button()

func _render_chronicle(summary: Dictionary) -> void:
	if summary.is_empty():
		return
	_content.add_child(HSeparator.new())
	_add_centered_label("KRONIKA PRZYSTANI", 25, Color("77d7d2"))
	_add_centered_label("Czarny Front: dzień %d     Pierwsze 100%%: dzień %d     Dni przy 100%%: %d\nIntegralność przed/po: %d%% / %d%%" % [
		int(summary.get("black_front_day", 0)), int(summary.get("first_full_integrity_day", 0)), int(summary.get("full_integrity_days", 0)),
		int(summary.get("integrity_before_storm", 100)), int(summary.get("integrity_after_storm", 100))
	], 16, Color("dbe5e1"))
	_add_centered_label("Wyprawy: %d     Bezpieczne powroty: %d     Śmierci nurków: %d     Odzyskane plecaki: %d" % [
		int(summary.get("dives", 0)), int(summary.get("safe_returns", 0)), int(summary.get("diver_deaths", 0)), int(summary.get("recovered_backpacks", 0))
	], 16, Color("dbe5e1"))
	_add_centered_label("Żyjący: %s\nZmarli: %s\nLos Leona: %s" % [
		_join_or_none(summary.get("living_survivors", [])), _join_or_none(summary.get("dead_survivors", [])), _leon_fate_label(str(summary.get("leon_fate", "nierozstrzygnięty")))
	], 16, Color("dbe5e1"))
	_add_centered_label("Uratowani: %d     Przyjęci: %s\nOdrzuceni: %s" % [
		int(summary.get("rescued_survivors", 0)), _join_or_none(summary.get("accepted_survivors", [])), _join_or_none(summary.get("rejected_survivors", []))
	], 16, Color("dbe5e1"))
	var building_lines: Array[String] = []
	for entry in summary.get("buildings", []):
		if entry is Dictionary:
			building_lines.append("%s — poziom %d" % [_building_label(str(entry.get("definition_id", ""))), int(entry.get("level", 0))])
	_add_centered_label("Budynki: %s" % (", ".join(building_lines) if not building_lines.is_empty() else "brak"), 16, Color("dbe5e1"))
	var resources: Dictionary = summary.get("resources", {})
	_add_centered_label("Zapasy — jedzenie: %d, deski: %d, złom: %d, tkaniny i guma: %d, części: %d, leki: %d" % [
		int(resources.get("food", 0)), int(resources.get("planks", 0)), int(resources.get("scrap", 0)), int(resources.get("fabric_rubber", 0)), int(resources.get("tech_parts", 0)), int(resources.get("meds_chemicals", 0))
	], 16, Color("dbe5e1"))
	_add_centered_label("R-3: %s     C-4: %s     Rozdzielacz: %s     Radiostacja: %s\nPlatforma Północna: %s" % [
		_yes_no(summary.get("r3_active", false)), _yes_no(summary.get("c4_active", false)), _yes_no(summary.get("splitter_installed", false)), _yes_no(summary.get("radio_active", false)),
		"przetrwała" if bool(summary.get("north_platform_survived", false)) else "utracona"
	], 16, Color("dbe5e1"))
	_add_centered_label("Konfiguracja energii: %s     Końcowa Nadzieja: %d" % [
		_energy_configuration_label(str(summary.get("energy_configuration", ""))), int(summary.get("hope", 0))
	], 16, Color("dbe5e1"))
	var decisions: Array = summary.get("important_decisions", [])
	if not decisions.is_empty():
		_add_centered_label("Najważniejsze decyzje:\n• %s" % "\n• ".join(decisions), 15, Color("c5d2ce"))

func _join_or_none(values) -> String:
	return ", ".join(values) if values is Array and not values.is_empty() else "brak"

func _yes_no(value) -> String:
	return "tak" if bool(value) else "nie"

func _building_label(definition_id: String) -> String:
	return {
		"fishing_hut": "Chata rybacka", "kitchen": "Kuchnia", "workshop": "Warsztat",
		"infirmary": "Lecznica", "diving_station": "Stacja nurkowa", "community_house": "Dom Wspólnoty",
	}.get(definition_id, definition_id if not definition_id.is_empty() else "Budynek")

func _leon_fate_label(value: String) -> String:
	return {"rescued": "uratowany", "dead": "zmarł", "nierozstrzygnięty": "nierozstrzygnięty"}.get(value, value)

func _energy_configuration_label(value: String) -> String:
	return {"harbor": "Przystań", "north": "Północna", "common_line": "Wspólna Linia"}.get(value, value)

func _add_centered_label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_content.add_child(label)
	return label

func _add_menu_button() -> void:
	var menu := Button.new()
	menu.name = "EndingMainMenuButton"
	menu.text = "MENU GŁÓWNE"
	menu.custom_minimum_size = Vector2(190, 52)
	menu.pressed.connect(_on_menu_pressed)
	_content.add_child(menu)

func _on_energy_choice_pressed(configuration_id: String) -> void:
	if game_root != null and game_root.choose_energy_configuration(configuration_id):
		game_state = game_root.game_state
		_render()

func _on_continue_pressed() -> void:
	if game_root != null:
		game_root.continue_chronicle()

func _on_menu_pressed() -> void:
	if game_root != null:
		game_root.return_to_main_menu()
