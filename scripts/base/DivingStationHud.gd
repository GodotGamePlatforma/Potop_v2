class_name DivingStationHud
extends VBoxContainer

signal dive_requested()
signal diver_selected(survivor_id: String)
signal gear_equipped(slot_id: String, gear_id: String)
signal entry_point_selected(entry_point_id: String)
signal disclosure_state_changed(profile_expanded: bool, equipment_expanded: bool)

const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const ExpeditionPreparationSystemScript := preload("res://scripts/base/ExpeditionPreparationSystem.gd")
const DiseaseSystemScript := preload("res://scripts/base/DiseaseSystem.gd")
const CompetencySystemScript := preload("res://scripts/base/CompetencySystem.gd")
const SurvivorPortraitScript := preload("res://scripts/ui/SurvivorPortrait.gd")
const SurvivorInfoPresenterScript := preload("res://scripts/ui/SurvivorInfoPresenter.gd")

# Stacja jest osadzona w jasnym obszarze działania BuildingPanel.
const UI_WORKSPACE := Color("f7f0e2")
const UI_CARD := Color("e4d9c5")
const UI_LINE := Color("c7b38e")
const UI_TEXT := Color("203b3b")
const UI_MUTED := Color("607578")
const UI_TEAL := Color("147b80")
const UI_AMBER := Color("a66318")
const UI_AMBER_BRIGHT := Color("f2af36")
const UI_GREEN := Color("4f843c")
const UI_GREEN_SURFACE := Color("e6f0d9")
const UI_CORAL := Color("a83e36")
const UI_CORAL_SURFACE := Color("f5e4df")
const UI_MARINE := Color("10464e")

var _state
var _definition
var _building
var _building_system
var _database
var _tutorial_step: int
var _preparation_system = ExpeditionPreparationSystemScript.new()
var _disease_system = DiseaseSystemScript.new()
var _show_actions: bool = true
var _profile_details_expanded: bool = false
var _equipment_details_expanded: bool = false

func set_disclosure_state(profile_expanded: bool, equipment_expanded: bool) -> void:
	_profile_details_expanded = profile_expanded
	_equipment_details_expanded = equipment_expanded

func configure(state, definition, building, building_system, tutorial_step: int, show_actions: bool = true) -> void:
	_state = state
	_definition = definition
	_building = building
	_building_system = building_system
	_database = _resolve_database()
	_tutorial_step = tutorial_step
	_show_actions = show_actions
	custom_minimum_size = Vector2(0, 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var diver = _current_diver()
	add_child(_build_readiness_banner(diver))
	var expedition_workspace := HBoxContainer.new()
	expedition_workspace.name = "DiverSelectionWorkspace"
	expedition_workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	expedition_workspace.add_theme_constant_override("separation", 10)
	expedition_workspace.add_child(_build_diver_candidates_panel())
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 8)
	details.add_child(_build_diver_panel(diver))
	details.add_child(_build_equipment_panel(diver))
	expedition_workspace.add_child(details)
	add_child(expedition_workspace)
	if _show_actions:
		_build_action_row()

func is_ready() -> bool:
	return _has_valid_diver()

func readiness_text() -> String:
	return _readiness_text(_current_diver())


func _build_diver_candidates_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "DiverCandidatePanel"
	panel.custom_minimum_size = Vector2(210, 280)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _section_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)
	_add_eyebrow(content, "ZAŁOGA WYPRAWY")
	_add_wrapped_label(content, "Wybierz wolnego mieszkańca. Obsada budynków nie może nurkować.", UI_MUTED, 10)
	var scroll := ScrollContainer.new()
	scroll.name = "DiverCandidateScroll"
	scroll.custom_minimum_size = Vector2(190, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)
	if _state == null:
		return panel
	for survivor in _state.survivors:
		if survivor == null or not survivor.is_present_in_settlement():
			continue
		list.add_child(_diver_candidate_button(survivor))
	if _state.current_day_plan != null and not str(_state.current_day_plan.selected_diver_id).is_empty():
		var clear_button := Button.new()
		clear_button.name = "DiverSelectionClear"
		clear_button.text = "ZAPOMNIJ NURKA"
		clear_button.disabled = not _state.can_edit_day_plan()
		clear_button.tooltip_text = _day_plan_edit_blocker() if clear_button.disabled else "Usuń zapamiętany wybór nurka."
		if not clear_button.disabled:
			clear_button.pressed.connect(func(): diver_selected.emit(""))
		content.add_child(clear_button)
	return panel


func _diver_candidate_button(survivor) -> Button:
	var button := Button.new()
	button.name = "DiverCandidate_%s" % str(survivor.id)
	button.custom_minimum_size = Vector2(0, 48)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var selected := _state != null and _state.current_day_plan != null and str(_state.current_day_plan.selected_diver_id) == str(survivor.id)
	var blocker := _preparation_system.diver_selection_blocker(_state, _building, _definition, str(survivor.id))
	button.text = "%s\n%s" % [str(survivor.display_name), _candidate_availability_label(selected, blocker)]
	button.tooltip_text = _candidate_tooltip(selected, blocker)
	button.disabled = not selected and not blocker.is_empty()
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", UI_TEXT)
	button.add_theme_color_override("font_hover_color", UI_TEXT)
	button.add_theme_color_override("font_focus_color", UI_TEXT)
	button.add_theme_color_override("font_disabled_color", Color(UI_MUTED, 0.70))
	button.add_theme_stylebox_override("normal", _candidate_style(selected, false))
	button.add_theme_stylebox_override("hover", _candidate_style(selected, true))
	if not button.disabled:
		button.pressed.connect(func(): diver_selected.emit(str(survivor.id)))
	return button


func _candidate_availability_label(selected: bool, blocker: String) -> String:
	if selected:
		return "WYBRANY DO WYPRAWY"
	if blocker.is_empty():
		return "GOTOWY DO WYBORU"
	var normalized := blocker.to_lower()
	if normalized.contains("obsadzony w budynku"):
		return "ZAJĘTY W BUDYNKU"
	if normalized.contains("izolacji"):
		return "W IZOLACJI"
	if normalized.contains("tutoriala"):
		return "NIEDOSTĘPNY W TUTORIALU"
	if normalized.contains("nie może nurkować") or normalized.contains("nie moze nurkowac"):
		return "NIEZDOLNY DO NURKOWANIA"
	return "NIEDOSTĘPNY"


func _candidate_tooltip(selected: bool, blocker: String) -> String:
	if selected:
		return "Wybrany nurek wyprawy."
	if blocker.is_empty():
		return "Wybierz do wyprawy."
	return blocker

func _build_readiness_banner(diver) -> PanelContainer:
	var ready := _has_valid_diver()
	var panel := PanelContainer.new()
	panel.name = "DiveReadinessPanel"
	panel.add_theme_stylebox_override("panel", _readiness_style(ready))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	margin.add_child(row)
	var marker := Label.new()
	marker.text = "✓" if ready else "!"
	marker.add_theme_font_size_override("font_size", 19)
	marker.add_theme_color_override("font_color", UI_GREEN if ready else UI_CORAL)
	row.add_child(marker)
	var readiness_label := Label.new()
	readiness_label.name = "DiveReadinessLabel"
	readiness_label.text = _readiness_text(diver)
	readiness_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readiness_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	readiness_label.add_theme_font_size_override("font_size", 12)
	readiness_label.add_theme_color_override("font_color", UI_GREEN if ready else UI_CORAL)
	row.add_child(readiness_label)
	return panel

func _build_diver_panel(diver) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "DiverProfilePanel"
	panel.custom_minimum_size = Vector2(0, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _section_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)
	_add_eyebrow(content, "WYBRANY NUREK")

	if diver == null:
		var empty_avatar := PanelContainer.new()
		empty_avatar.custom_minimum_size = Vector2(0, 62)
		empty_avatar.add_theme_stylebox_override("panel", _avatar_style(false))
		var empty_text := Label.new()
		empty_text.text = "BRAK NURKA"
		empty_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_text.add_theme_font_size_override("font_size", 17)
		empty_text.add_theme_color_override("font_color", UI_MUTED)
		empty_avatar.add_child(empty_text)
		content.add_child(empty_avatar)
		_add_wrapped_label(content, "Wybierz wolnego mieszkańca z kolumny Załoga wyprawy.", UI_MUTED, 12)
		return panel
	var preparation_analysis := _preparation_analysis()

	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 10)
	content.add_child(identity)
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(58, 72)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.add_theme_stylebox_override("panel", _avatar_style(true))
	var portrait_margin := MarginContainer.new()
	portrait_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_margin.add_theme_constant_override("margin_left", 2)
	portrait_margin.add_theme_constant_override("margin_top", 2)
	portrait_margin.add_theme_constant_override("margin_right", 2)
	portrait_margin.add_theme_constant_override("margin_bottom", 2)
	avatar.add_child(portrait_margin)
	var portrait = SurvivorPortraitScript.new()
	portrait.name = "DiverPortrait"
	portrait.custom_minimum_size = Vector2(54, 68)
	portrait.configure(str(diver.portrait_id), str(diver.display_name))
	portrait_margin.add_child(portrait)
	identity.add_child(avatar)

	var identity_text := VBoxContainer.new()
	identity_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_text.alignment = BoxContainer.ALIGNMENT_CENTER
	identity.add_child(identity_text)
	var name_label := Label.new()
	name_label.name = "DiverNameLabel"
	name_label.text = diver.display_name
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", UI_TEXT)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	identity_text.add_child(name_label)
	var profession := Label.new()
	var profession_summary: String = str(diver.profession).capitalize()
	if not diver.secondary_profession.is_empty():
		profession_summary += " + " + str(diver.secondary_profession).capitalize()
	profession.text = "%s  •  POZIOM %d  •  %s" % [profession_summary, diver.level, "GOTOWY" if diver.can_dive() else "NIEZDOLNY"]
	profession.tooltip_text = (
		"ZDOLNY — bieżące stany pozwalają wybrać tę osobę do wyprawy."
		if diver.can_dive()
		else "NIEZDOLNY — %s" % diver.dive_blocker()
	)
	profession.add_theme_font_size_override("font_size", 11)
	profession.add_theme_color_override("font_color", UI_GREEN if diver.can_dive() else UI_CORAL)
	identity_text.add_child(profession)
	_add_stat(content, "DiverHealth", "ZDROWIE", diver.health, diver.get_max_health(), UI_CORAL, "%d / %d" % [diver.health, diver.get_max_health()], SurvivorInfoPresenterScript.stat_tooltip(diver, "health"))
	var oxygen_capacity := float(preparation_analysis.get("oxygen_capacity", 0.0))
	_add_stat(content, "DiverOxygen", "POJEMNOŚĆ TLENOWA", oxygen_capacity, oxygen_capacity, UI_TEAL, "%.0f / %.0f" % [oxygen_capacity, oxygen_capacity], "Tlen dostępny na planowanej wyprawie po połączeniu osobistej pojemności, wyposażonej butli i aktywnych premii.")
	var carry_capacity: float = float(preparation_analysis.get("carry_capacity", diver.get_carry_capacity()))
	var carry_tooltip := SurvivorInfoPresenterScript.stat_tooltip(diver, "carry")
	if bool(preparation_analysis.get("station_staffed", false)):
		carry_tooltip += "\n\nObsługa Stacji daje +5% udźwigu na tę wyprawę."
	_add_stat(content, "DiverCarry", "UDŹWIG ŁUPU", carry_capacity, carry_capacity, UI_AMBER, "%.1f kg" % carry_capacity, carry_tooltip)

	var details_button := Button.new()
	details_button.text = "PROFIL, CECHY I STANY  %s" % ("▴" if _profile_details_expanded else "▾")
	details_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	details_button.custom_minimum_size = Vector2(0, 34)
	details_button.add_theme_font_size_override("font_size", 11)
	details_button.add_theme_color_override("font_color", UI_TEAL)
	details_button.add_theme_color_override("font_hover_color", UI_AMBER)
	details_button.add_theme_color_override("font_focus_color", UI_AMBER)
	content.add_child(details_button)
	var details := VBoxContainer.new()
	details.name = "DiverProfileDetails"
	details.visible = _profile_details_expanded
	details.add_theme_constant_override("separation", 5)
	content.add_child(details)
	var biography := Label.new()
	biography.text = diver.biography
	biography.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	biography.add_theme_font_size_override("font_size", 11)
	biography.add_theme_color_override("font_color", UI_MUTED)
	details.add_child(biography)
	var traits_heading := _add_eyebrow(details, "CECHY I UMIEJĘTNOŚCI")
	traits_heading.tooltip_text = "%s\n\n%s" % [SurvivorInfoPresenterScript.section_tooltip("traits"), SurvivorInfoPresenterScript.section_tooltip("competencies")]
	var traits: Array[String] = []
	traits.append("Specjalizacja: %s" % diver.profession.capitalize())
	var oxygen_multiplier := float(preparation_analysis.get("specialist_oxygen_multiplier", 1.0))
	if oxygen_multiplier > 1.0:
		var oxygen_percent := int(round((oxygen_multiplier - 1.0) * 100.0))
		traits.append("Umiejętność: Nurkowanie (+%d%% osobistej pojemności tlenu)" % oxygen_percent)
	if not diver.secondary_profession.is_empty():
		traits.append("Druga specjalizacja: %s" % diver.secondary_profession.capitalize())
	if not diver.positive_trait.is_empty():
		traits.append("Atut: %s" % diver.positive_trait.capitalize())
	if not diver.negative_trait.is_empty():
		traits.append("Słabość: %s" % diver.negative_trait.capitalize())
	traits.append("Udźwig wyprawy: %.1f kg" % carry_capacity)
	var traits_label := _add_wrapped_label(details, "  •  ".join(traits), UI_GREEN, 12, "DiverTraitsLabel")
	traits_label.tooltip_text = "%s\n\n%s" % [
		SurvivorInfoPresenterScript.trait_tooltip(str(diver.positive_trait), true),
		SurvivorInfoPresenterScript.trait_tooltip(str(diver.negative_trait), false),
	]
	var competency_grid := GridContainer.new()
	competency_grid.name = "DiverCompetencies"
	competency_grid.columns = 2
	competency_grid.add_theme_constant_override("h_separation", 10)
	competency_grid.add_theme_constant_override("v_separation", 3)
	details.add_child(competency_grid)
	for competency_id in CompetencySystemScript.IDS:
		var competency := Label.new()
		competency.name = "DiverCompetency_%s" % competency_id
		competency.text = "%s %d/%d" % [str(CompetencySystemScript.LABELS[competency_id]), CompetencySystemScript.level(diver, competency_id), CompetencySystemScript.MAX_LEVEL]
		competency.tooltip_text = CompetencySystemScript.tooltip_text(diver, competency_id)
		competency.add_theme_font_size_override("font_size", 10)
		competency.add_theme_color_override("font_color", UI_TEAL)
		competency_grid.add_child(competency)

	var states_heading := _add_eyebrow(details, "STANY")
	states_heading.tooltip_text = SurvivorInfoPresenterScript.section_tooltip("states")
	var states_label := _add_wrapped_label(details, "  •  ".join(_state_labels(diver)), UI_MUTED, 12, "DiverStatesLabel")
	states_label.tooltip_text = SurvivorInfoPresenterScript.combined_state_tooltip(diver)
	details_button.pressed.connect(_toggle_section.bind(details_button, details, "profile"))
	return panel

func _build_equipment_panel(diver) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "DiverEquipmentPanel"
	panel.custom_minimum_size = Vector2(0, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _section_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)
	_add_eyebrow(content, "WYPOSAŻENIE NURKA")

	var station_kit := HBoxContainer.new()
	station_kit.add_theme_constant_override("separation", 10)
	content.add_child(station_kit)
	station_kit.add_child(_equipment_card("KOMBINEZON", "Poziom %d" % _building.level, "Ochrona stacji"))
	var analysis := _preparation_analysis()
	var carry_capacity: float = float(analysis.get("carry_capacity", diver.get_carry_capacity() if diver != null else 0.0))
	var backpack_detail := "Sloty i udźwig nurka"
	if bool(analysis.get("station_staffed", false)):
		backpack_detail = "Sloty i udźwig • +5% dzięki obsadzie Stacji"
	station_kit.add_child(_equipment_card("PLECAK", "%d miejsc  •  %.1f kg" % [_backpack_capacity(), carry_capacity], backpack_detail))

	var details := VBoxContainer.new()
	details.name = "DiverEquipmentDetails"
	details.visible = _equipment_details_expanded
	details.add_theme_constant_override("separation", 6)

	var details_button := Button.new()
	details_button.text = "SPRZĘT I NARZĘDZIA  %s" % ("▴" if _equipment_details_expanded else "▾")
	details_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	details_button.custom_minimum_size = Vector2(0, 34)
	details_button.add_theme_font_size_override("font_size", 11)
	details_button.add_theme_color_override("font_color", UI_TEAL)
	details_button.add_theme_color_override("font_hover_color", UI_AMBER)
	details_button.add_theme_color_override("font_focus_color", UI_AMBER)
	content.add_child(details_button)
	content.add_child(details)
	var oxygen_tank_title := Label.new()
	oxygen_tank_title.text = "BUTLA TLENOWA"
	oxygen_tank_title.add_theme_font_size_override("font_size", 12)
	oxygen_tank_title.add_theme_color_override("font_color", UI_MUTED)
	details.add_child(oxygen_tank_title)
	_build_oxygen_tank_picker(details)

	var light_title := Label.new()
	light_title.text = "ŹRÓDŁO ŚWIATŁA"
	light_title.add_theme_font_size_override("font_size", 12)
	light_title.add_theme_color_override("font_color", UI_MUTED)
	details.add_child(light_title)
	_build_light_picker(details)
	_build_entry_picker(details)
	_add_eyebrow(details, "NARZĘDZIA STACJI")
	var tools := GridContainer.new()
	tools.columns = 3
	tools.add_theme_constant_override("h_separation", 6)
	tools.add_theme_constant_override("v_separation", 6)
	details.add_child(tools)
	tools.add_child(_tool_card("NÓŻ", "Sieci i rośliny"))
	tools.add_child(_tool_card("ŁOM", "Drzwi i szafki"))
	tools.add_child(_tool_card("NAPRAWA", "Łata kombinezon"))
	var preparation_analysis := _preparation_analysis()
	var capabilities: Dictionary = preparation_analysis.get("capabilities", {})
	if bool(capabilities.get("buoy_enabled", false)):
		tools.add_child(_tool_card("BOJA", "1 na wyprawę"))
	if bool(capabilities.get("heavy_marking_enabled", false)):
		tools.add_child(_tool_card("WOREK", "Ciężki odzysk"))
	if bool(capabilities.get("technician_support_enabled", false)) and bool(preparation_analysis.get("technician_assigned", false)):
		tools.add_child(_tool_card(
			"TECHNIK",
			"%d użycia naprawy • −%d%% uszkodzeń" % [
				int(preparation_analysis.get("repair_kit_charges", 2)),
				int(round(float(preparation_analysis.get("technician_suit_damage_reduction", 0.0)) * 100.0)),
			]
		))

	details_button.pressed.connect(_toggle_section.bind(details_button, details, "equipment"))
	return panel

func _build_oxygen_tank_picker(content: VBoxContainer, detail_content: VBoxContainer = null) -> void:
	var description_host := detail_content if detail_content != null else content
	var picker := OptionButton.new()
	picker.name = "OxygenTankGearPicker"
	picker.custom_minimum_size = Vector2(0, 44)
	var selected_index := -1
	var equipped_id: String = _state.diving_equipment.get_equipped("oxygen_tank") if _state.diving_equipment != null else ""
	if _state.diving_equipment != null:
		for gear_id in _state.diving_equipment.owned_gear_ids:
			var definition = _database.diving_gear.get(str(gear_id)) if _database != null else null
			if definition == null or str(definition.equipment_slot) != "oxygen_tank":
				continue
			var item_index := picker.item_count
			picker.add_item("%s  •  %.0f jednostek" % [definition.display_name, definition.oxygen_capacity])
			picker.set_item_metadata(item_index, str(definition.id))
			if str(definition.id) == equipped_id:
				selected_index = item_index
	if picker.item_count == 0:
		picker.add_item("Brak butli tlenowej")
		picker.disabled = true
		picker.tooltip_text = "Nie posiadasz sprawnej butli tlenowej."
	else:
		picker.select(maxi(selected_index, 0))
		picker.disabled = not _state.can_edit_day_plan()
		if picker.disabled:
			picker.tooltip_text = _day_plan_edit_blocker()
		picker.item_selected.connect(_on_oxygen_tank_selected.bind(picker))
	content.add_child(picker)
	var equipped_definition = _database.diving_gear.get(equipped_id) if _database != null else null
	if equipped_definition != null:
		var final_capacity := float(_preparation_analysis().get("oxygen_capacity", 0.0))
		var description := "%s: bazowa pojemność %.0f jednostek." % [equipped_definition.display_name, equipped_definition.oxygen_capacity]
		if final_capacity > 0.0:
			description += " Po rozwoju nurka i premiach wyprawa otrzyma %.0f jednostek tlenu." % final_capacity
		else:
			description += " Przydziel nurka, aby zobaczyć końcową pojemność wyprawy."
		_add_wrapped_label(description_host, description, UI_MUTED, 11, "EquippedOxygenTankDescription")
	else:
		_add_wrapped_label(description_host, "Wybierz posiadaną butlę. Bez sprawnej butli wyprawa nie może się rozpocząć.", UI_CORAL, 11, "EquippedOxygenTankDescription")

func _build_light_picker(content: VBoxContainer, detail_content: VBoxContainer = null) -> void:
	var description_host := detail_content if detail_content != null else content
	var picker := OptionButton.new()
	picker.name = "LightGearPicker"
	picker.custom_minimum_size = Vector2(0, 44)
	var selected_index := -1
	var equipped_id: String = _state.diving_equipment.get_equipped("light") if _state.diving_equipment != null else ""
	if _state.diving_equipment != null:
		for gear_id in _state.diving_equipment.owned_gear_ids:
			var definition = _database.diving_gear.get(str(gear_id)) if _database != null else null
			if definition == null or str(definition.equipment_slot) != "light":
				continue
			var item_index := picker.item_count
			picker.add_item("%s  •  zasięg %.0f" % [definition.display_name, definition.light_outer_radius])
			picker.set_item_metadata(item_index, str(definition.id))
			if str(definition.id) == equipped_id:
				selected_index = item_index
	if picker.item_count == 0:
		picker.add_item("Brak latarni")
		picker.disabled = true
		picker.tooltip_text = "Nie posiadasz sprawnego źródła światła."
	else:
		picker.select(maxi(selected_index, 0))
		picker.disabled = not _state.can_edit_day_plan()
		if picker.disabled:
			picker.tooltip_text = _day_plan_edit_blocker()
		picker.item_selected.connect(_on_light_selected.bind(picker))
	content.add_child(picker)
	var equipped_definition = _database.diving_gear.get(equipped_id) if _database != null else null
	if equipped_definition != null:
		_add_wrapped_label(description_host, "%s: pełna widoczność do %.0f, miękkie wygasanie do %.0f jednostek." % [equipped_definition.display_name, equipped_definition.light_inner_radius, equipped_definition.light_outer_radius], UI_MUTED, 11, "EquippedLightDescription")
	else:
		_add_wrapped_label(description_host, "Wybierz posiadaną latarnię. Bez światła wyprawa nie może się rozpocząć.", UI_CORAL, 11, "EquippedLightDescription")

func _build_entry_picker(content: VBoxContainer, detail_content: VBoxContainer = null) -> void:
	var description_host := detail_content if detail_content != null else content
	var title := Label.new()
	title.text = "WEJŚCIE DO WODY"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", UI_MUTED)
	content.add_child(title)
	var picker := OptionButton.new()
	picker.name = "EntryPointPicker"
	picker.custom_minimum_size = Vector2(0, 42)
	var analysis := _preparation_analysis()
	var entries: Array = analysis.get("entry_points", [])
	var selected_id := str(analysis.get("selected_entry_point", ""))
	var selected_index := 0
	for entry in entries:
		var index := picker.item_count
		picker.add_item(str(entry.get("label", "Wejście")))
		picker.set_item_metadata(index, str(entry.get("id", "")))
		if str(entry.get("id", "")) == selected_id:
			selected_index = index
	if picker.item_count == 0:
		picker.add_item("Brak dostępnego wejścia")
		picker.disabled = true
		picker.tooltip_text = str(analysis.get("entry_point_selection_reason", "Brak dostępnego wejścia do wody."))
	else:
		picker.select(selected_index)
		picker.disabled = picker.item_count <= 1 or not _state.can_edit_day_plan()
		if not _state.can_edit_day_plan():
			picker.tooltip_text = _day_plan_edit_blocker()
		elif picker.item_count <= 1:
			picker.tooltip_text = str(analysis.get("entry_point_selection_reason", "Brak alternatywnego wejścia do wody."))
		picker.item_selected.connect(_on_entry_point_selected.bind(picker))
	content.add_child(picker)
	if picker.item_count <= 1:
		_add_wrapped_label(
			description_host,
			str(analysis.get("entry_point_selection_reason", "Brak alternatywnego wejścia do wody.")),
			UI_MUTED,
			11
		)
	else:
		_add_wrapped_label(description_host, "Wybrane wejście zostanie zapisane w planie dnia i zamrożone przy starcie wyprawy.", UI_MUTED, 11)

func _build_action_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(create_dive_button())
	if _building.pending_level > _building.level:
		var pending := Label.new()
		pending.text = "Rozbudowa do poziomu %d oczekuje na migrację starszego zapisu." % _building.pending_level
		pending.add_theme_font_size_override("font_size", 12)
		pending.add_theme_color_override("font_color", UI_AMBER)
		add_child(pending)


func create_dive_button() -> Button:
	var dive_button := Button.new()
	dive_button.name = "DiveButton"
	dive_button.text = "NURKUJ"
	dive_button.custom_minimum_size = Vector2(220, 46)
	var dive_blocker := _day_plan_edit_blocker()
	if dive_blocker.is_empty() and not _has_valid_diver():
		dive_blocker = readiness_text()
	dive_button.disabled = not dive_blocker.is_empty()
	dive_button.tooltip_text = dive_blocker if not dive_blocker.is_empty() else readiness_text()
	dive_button.pressed.connect(func(): dive_requested.emit())
	dive_button.add_theme_stylebox_override("normal", _dive_button_style(false))
	dive_button.add_theme_stylebox_override("hover", _dive_button_style(true))
	if _tutorial_step == TutorialStateScript.Step.START_FIRST_DIVE:
		diver_button_target(dive_button)
	return dive_button

func diver_button_target(button: Button) -> void:
	var style := _dive_button_style(true)
	style.border_color = UI_AMBER_BRIGHT
	style.set_border_width_all(3)
	button.add_theme_stylebox_override("normal", style)

func _toggle_section(button: Button, details: VBoxContainer, section_id: String) -> void:
	details.visible = not details.visible
	if section_id == "profile":
		_profile_details_expanded = details.visible
		button.text = "PROFIL, CECHY I STANY  %s" % ("▴" if details.visible else "▾")
	else:
		_equipment_details_expanded = details.visible
		button.text = "SPRZĘT I NARZĘDZIA  %s" % ("▴" if details.visible else "▾")
	disclosure_state_changed.emit(_profile_details_expanded, _equipment_details_expanded)

func _equipment_card(title: String, value: String, detail: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 64)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _equipment_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.add_theme_color_override("font_color", UI_MUTED)
	column.add_child(title_label)
	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 16)
	value_label.add_theme_color_override("font_color", UI_AMBER)
	column.add_child(value_label)
	var detail_label := Label.new()
	detail_label.text = detail
	detail_label.add_theme_font_size_override("font_size", 11)
	detail_label.add_theme_color_override("font_color", UI_MUTED)
	column.add_child(detail_label)
	return card

func _tool_card(title: String, detail: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 52)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _equipment_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 7)
	card.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", UI_AMBER)
	title_label.add_theme_font_size_override("font_size", 12)
	column.add_child(title_label)
	var detail_label := Label.new()
	detail_label.text = detail
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_label.add_theme_color_override("font_color", UI_MUTED)
	detail_label.add_theme_font_size_override("font_size", 10)
	column.add_child(detail_label)
	return card

func _add_stat(content: VBoxContainer, node_prefix: String, title: String, value: float, maximum: float, color: Color, value_text: String, tooltip: String = "") -> void:
	var labels := HBoxContainer.new()
	content.add_child(labels)
	var title_label := Label.new()
	title_label.text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.add_theme_color_override("font_color", UI_MUTED)
	title_label.tooltip_text = tooltip
	labels.add_child(title_label)
	var value_label := Label.new()
	value_label.name = "%sLabel" % node_prefix
	value_label.text = value_text
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", UI_TEXT)
	value_label.tooltip_text = tooltip
	labels.add_child(value_label)
	var bar := ProgressBar.new()
	bar.name = "%sBar" % node_prefix
	bar.custom_minimum_size = Vector2(0, 11)
	bar.max_value = maxf(maximum, 1.0)
	bar.value = clampf(value, 0.0, bar.max_value)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _bar_style(UI_LINE))
	bar.add_theme_stylebox_override("fill", _bar_style(color))
	bar.tooltip_text = tooltip
	content.add_child(bar)

func _add_eyebrow(content: VBoxContainer, value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UI_AMBER)
	content.add_child(label)
	return label

func _add_wrapped_label(content: VBoxContainer, value: String, color: Color, font_size: int, node_name: String = "") -> Label:
	var label := Label.new()
	if not node_name.is_empty():
		label.name = node_name
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	content.add_child(label)
	return label

func _on_light_selected(index: int, picker: OptionButton) -> void:
	gear_equipped.emit("light", str(picker.get_item_metadata(index)))

func _on_oxygen_tank_selected(index: int, picker: OptionButton) -> void:
	gear_equipped.emit("oxygen_tank", str(picker.get_item_metadata(index)))

func _on_entry_point_selected(index: int, picker: OptionButton) -> void:
	entry_point_selected.emit(str(picker.get_item_metadata(index)))

func _current_diver():
	if _state == null or _state.current_day_plan == null:
		return null
	return _state.find_survivor(str(_state.current_day_plan.selected_diver_id))

func _has_valid_diver() -> bool:
	return bool(_preparation_analysis().get("ready", false))

func _backpack_capacity() -> int:
	return int(_preparation_analysis().get("backpack_capacity", 0))

func _preparation_analysis() -> Dictionary:
	return _preparation_system.analyze(_state, _building, _definition)

func _state_labels(diver) -> Array[String]:
	var labels: Array[String] = []
	labels.append(_health_label(diver.health_ratio()))
	labels.append(_hunger_label(diver.hunger))
	labels.append(_fatigue_label(diver.fatigue))
	labels.append(_morale_label(diver.morale))
	for injury in diver.injury_states:
		labels.append(str(injury).capitalize())
	for disease_case in diver.disease_cases:
		if disease_case == null:
			continue
		var definition = _database.diseases.get(str(disease_case.disease_id)) if _database != null else null
		var presentation := _disease_system.case_presentation(disease_case, definition)
		if presentation.is_empty():
			continue
		labels.append("%s — %s • zakaźność %s • praca %d%% • nurkowanie %s" % [
			str(presentation.get("display_name", "Choroba")),
			str(presentation.get("phase_label", "nieznany etap")),
			"TAK" if bool(presentation.get("contagious", false)) else "NIE",
			int(round(float(presentation.get("work_multiplier", 0.0)) * 100.0)),
			"TAK" if bool(presentation.get("dive_allowed", false)) else "NIE",
		])
	if _state != null and _state.current_day_plan != null and str(diver.id) in _state.current_day_plan.isolated_survivor_ids:
		labels.append("Izolacja zaplanowana — praca i nurkowanie zablokowane")
	return labels


func _resolve_database():
	var main_loop := Engine.get_main_loop()
	if not main_loop is SceneTree or main_loop.root == null:
		return null
	return main_loop.root.get_node_or_null("GameDatabase")

func _health_label(ratio: float) -> String:
	if ratio >= 0.8:
		return "Zdrowy"
	if ratio >= 0.5:
		return "Osłabiony"
	return "Ciężko ranny"

func _hunger_label(value: int) -> String:
	if value < 20:
		return "Najedzony"
	if value < 40:
		return "Głodny"
	if value < 65:
		return "Wygłodzony"
	if value < 85:
		return "Wyczerpany głodem"
	return "Umierający z głodu"

func _fatigue_label(value: int) -> String:
	if value < 25:
		return "Wypoczęty"
	if value < 60:
		return "Zmęczony"
	return "Skrajnie zmęczony"

func _morale_label(value: int) -> String:
	if value >= 70:
		return "Wysokie morale"
	if value >= 40:
		return "Stabilne morale"
	return "Niskie morale"

func _readiness_text(diver) -> String:
	var analysis := _preparation_analysis()
	if not bool(analysis.get("ready", false)):
		return "NIEGOTOWY  •  %s" % str(analysis.get("reason", "Nie można rozpocząć wyprawy."))
	var carry_capacity := float(analysis.get("carry_capacity", diver.get_carry_capacity()))
	var staffed_suffix := " • +5% dzięki obsadzie Stacji" if bool(analysis.get("station_staffed", false)) else ""
	return "GOTOWY DO WYPRAWY  •  %d miejsc, %.1f kg udźwigu, %.0f jednostek tlenu%s." % [int(analysis.backpack_capacity), carry_capacity, float(analysis.oxygen_capacity), staffed_suffix]


func _day_plan_edit_blocker() -> String:
	if _state == null:
		return "Brak aktywnego stanu kampanii."
	if _state.has_method("day_plan_edit_blocker"):
		return str(_state.day_plan_edit_blocker())
	return "" if _state.can_edit_day_plan() else "Plan dnia jest już zablokowany."

func _section_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UI_WORKSPACE, 0.98)
	style.border_color = UI_LINE
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _avatar_style(is_filled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_MARINE if is_filled else UI_CARD
	style.border_color = UI_AMBER_BRIGHT if is_filled else UI_LINE
	style.set_border_width_all(2)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style

func _candidate_style(selected: bool, hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_CARD if selected else (Color("efe7d7") if hovered else UI_WORKSPACE)
	style.border_color = UI_AMBER_BRIGHT if selected else (UI_TEAL if hovered else UI_LINE)
	style.set_border_width_all(2 if selected else 1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style

func _equipment_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_CARD
	style.border_color = UI_LINE
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style

func _readiness_style(is_ready: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_GREEN_SURFACE if is_ready else UI_CORAL_SURFACE
	style.border_color = UI_GREEN if is_ready else UI_CORAL
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style

func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style

func _dive_button_style(is_hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_AMBER_BRIGHT if is_hovered else Color("e5a12d")
	style.border_color = UI_AMBER
	style.set_border_width_all(2)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style
