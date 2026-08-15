class_name WorkerCandidatePickerPanel
extends PanelContainer

signal closed()
signal survivor_chosen(building_id: String, slot_index: int, survivor_id: String)

const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const SurvivorPortraitScript := preload("res://scripts/ui/SurvivorPortrait.gd")
const WorkerAssignmentSystemScript := preload("res://scripts/base/WorkerAssignmentSystem.gd")
const BuildingEffectSystemScript := preload("res://scripts/base/BuildingEffectSystem.gd")
const DiseaseSystemScript := preload("res://scripts/base/DiseaseSystem.gd")
const CompetencySystemScript := preload("res://scripts/base/CompetencySystem.gd")
const ProfessionTalentSystemScript := preload("res://scripts/base/ProfessionTalentSystem.gd")
const SurvivorInfoPresenterScript := preload("res://scripts/ui/SurvivorInfoPresenter.gd")

var _state
var _definition
var _building
var _slot_index: int = 0
var _tutorial_step: int = 0
var _wide_layout: bool = true
var _focused_survivor_id: String = ""
var _candidate_buttons: Array[Button] = []
var _worker_assignment_system = WorkerAssignmentSystemScript.new()
var _building_effect_system = BuildingEffectSystemScript.new()
var _disease_system = DiseaseSystemScript.new()
var _profession_talent_system = ProfessionTalentSystemScript.new()

var _detail_portrait
var _detail_name: Label
var _detail_profession: Label
var _detail_talents: Label
var _detail_state: Label
var _detail_assignment: Label
var _detail_traits: Label
var _detail_positive_trait: Label
var _detail_negative_trait: Label
var _detail_stats: Dictionary = {}
var _detail_competencies: Dictionary = {}


func configure(state, definition, building, slot_index: int, tutorial_step: int) -> void:
	_state = state
	_definition = definition
	_building = building
	_slot_index = slot_index
	_tutorial_step = tutorial_step
	_focused_survivor_id = _initial_candidate_id()
	_rebuild()


func refresh_layout(viewport_size: Vector2 = Vector2.ZERO) -> void:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var next_wide := viewport_size.x >= 1050.0
	custom_minimum_size = Vector2(
		minf(1040.0, maxf(viewport_size.x - 72.0, 320.0)),
		minf(640.0, maxf(viewport_size.y - 112.0, 360.0))
	)
	if next_wide != _wide_layout:
		_wide_layout = next_wide
		if _state != null and _building != null:
			_rebuild()


func focus_initial() -> void:
	for button in _candidate_buttons:
		if button != null and button.is_visible_in_tree() and not button.disabled:
			button.grab_focus()
			return
	var back := find_child("WorkerCandidateBackButton", true, false) as Button
	if back != null:
		back.grab_focus()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_candidate_buttons.clear()
	_detail_portrait = null
	_detail_name = null
	_detail_profession = null
	_detail_talents = null
	_detail_state = null
	_detail_assignment = null
	_detail_traits = null
	_detail_positive_trait = null
	_detail_negative_trait = null
	_detail_stats.clear()
	_detail_competencies.clear()

	add_theme_stylebox_override("panel", _panel_style(Color("081215fc"), Color("67959a"), 2, 7))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	margin.add_child(shell)
	_build_header(shell)

	var scroll := ScrollContainer.new()
	scroll.name = "WorkerCandidateScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	var body := GridContainer.new()
	body.name = "WorkerCandidateBody"
	body.columns = 3 if _wide_layout else 1
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("h_separation", 12)
	body.add_theme_constant_override("v_separation", 12)
	scroll.add_child(body)

	_build_candidate_details(body)
	_build_candidate_roster(body)
	_build_current_slot(body)
	_update_candidate_details(_focused_survivor_id)
	call_deferred("focus_initial")


func _build_header(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	parent.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	header.add_child(titles)
	var eyebrow := Label.new()
	eyebrow.text = "OBSADA  •  %s" % (str(_definition.display_name).to_upper() if _definition != null else "BUDYNEK")
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", Color("7fc7c5"))
	titles.add_child(eyebrow)
	var title := Label.new()
	title.name = "WorkerCandidateTitle"
	title.text = "Wybierz mieszkańca — %s" % _role_name(_slot_index)
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color("f0d08a"))
	titles.add_child(title)
	var back := Button.new()
	back.name = "WorkerCandidateBackButton"
	back.text = "WRÓĆ"
	back.tooltip_text = "Wróć do obsady budynku bez wprowadzania zmiany."
	back.custom_minimum_size = Vector2(92, 40)
	back.pressed.connect(func(): closed.emit())
	header.add_child(back)


func _build_candidate_details(parent: GridContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "WorkerCandidateDetails"
	panel.custom_minimum_size = Vector2(268, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color("101b1eea"), Color("385157"), 1, 4))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	margin.add_child(content)
	var heading := Label.new()
	heading.text = "WYBRANY MIESZKANIEC"
	heading.add_theme_font_size_override("font_size", 12)
	heading.add_theme_color_override("font_color", Color("8ca9a9"))
	content.add_child(heading)
	_detail_portrait = SurvivorPortraitScript.new()
	_detail_portrait.name = "WorkerCandidateDetailPortrait"
	_detail_portrait.custom_minimum_size = Vector2(112, 138)
	_detail_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(_detail_portrait)
	_detail_name = Label.new()
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_name.add_theme_font_size_override("font_size", 20)
	_detail_name.add_theme_color_override("font_color", Color("f0d08a"))
	content.add_child(_detail_name)
	_detail_profession = _detail_label(content, Color("d6e0dc"), 13)
	_detail_profession.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_talents = _detail_label(content, Color("9fd3a9"), 11)
	_detail_talents.name = "WorkerCandidateDetailTalents"
	_detail_talents.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_state = _detail_label(content, Color("93b9b4"), 12)
	_detail_state.name = "WorkerCandidateDetailState"
	_detail_assignment = _detail_label(content, Color("a8b8b5"), 12)
	_detail_assignment.name = "WorkerCandidateDetailAssignment"
	_build_detail_states(content)
	_build_detail_traits(content)
	_build_detail_competencies(content)


func _build_detail_states(content: VBoxContainer) -> void:
	var heading := _detail_section_heading(content, "STANY", "states")
	heading.name = "WorkerCandidateStatesHeading"
	var grid := GridContainer.new()
	grid.name = "WorkerCandidateStates"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	content.add_child(grid)
	for stat_id in ["health", "hunger", "fatigue", "morale", "oxygen", "carry"]:
		var label := _detail_label(grid, Color("b8c9c5"), 10)
		label.name = "WorkerCandidateStat_%s" % stat_id
		_detail_stats[stat_id] = label


func _build_detail_traits(content: VBoxContainer) -> void:
	_detail_section_heading(content, "CECHY", "traits")
	_detail_positive_trait = _detail_label(content, Color("8fd7a3"), 10)
	_detail_positive_trait.name = "WorkerCandidatePositiveTrait"
	_detail_negative_trait = _detail_label(content, Color("d7ae7f"), 10)
	_detail_negative_trait.name = "WorkerCandidateNegativeTrait"
	_detail_traits = _detail_label(content, Color("79d69b"), 11)
	_detail_traits.name = "WorkerCandidateDetailTraits"


func _build_detail_competencies(content: VBoxContainer) -> void:
	_detail_section_heading(content, "KOMPETENCJE", "competencies")
	var grid := GridContainer.new()
	grid.name = "WorkerCandidateCompetencies"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	content.add_child(grid)
	for competency_id in CompetencySystemScript.IDS:
		var label := _detail_label(grid, Color("9fc7c3"), 10)
		label.name = "WorkerCandidateCompetency_%s" % competency_id
		_detail_competencies[competency_id] = label


func _detail_section_heading(parent: VBoxContainer, title: String, section_id: String) -> Label:
	var label := _detail_label(parent, Color("e0bd69"), 10)
	label.text = title
	label.tooltip_text = SurvivorInfoPresenterScript.section_tooltip(section_id)
	return label


func _build_candidate_roster(parent: GridContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "WorkerCandidateRoster"
	panel.custom_minimum_size = Vector2(430 if _wide_layout else 0, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color("0b1518e8"), Color("405e63"), 1, 4))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	var heading := Label.new()
	heading.text = "MIESZKAŃCY PRZYSTANI"
	heading.add_theme_font_size_override("font_size", 12)
	heading.add_theme_color_override("font_color", Color("8ca9a9"))
	content.add_child(heading)
	var grid := GridContainer.new()
	grid.name = "WorkerCandidateGrid"
	grid.columns = 2 if _wide_layout else 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	var survivors := _candidate_survivors()
	for survivor in survivors:
		_build_candidate_tile(grid, survivor)
	if survivors.is_empty():
		var empty := Label.new()
		empty.text = "Brak mieszkańców, których można pokazać dla tego stanowiska."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color("a6b5b2"))
		grid.add_child(empty)


func _build_candidate_tile(parent: GridContainer, survivor) -> void:
	var survivor_id := str(survivor.id)
	var assigned_id := _assigned_survivor_id()
	var is_current := survivor_id == assigned_id
	var blocker := _candidate_blocker(survivor_id)
	var unavailable := not blocker.is_empty() and not is_current
	var tutorial_target := _is_tutorial_target(survivor_id, unavailable)
	var button := Button.new()
	button.name = "WorkerCandidate_%s" % survivor_id
	button.custom_minimum_size = Vector2(196, 156)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_contents = true
	button.focus_mode = Control.FOCUS_ALL
	button.disabled = unavailable
	button.tooltip_text = blocker if unavailable else (
		"NIEZDOLNY • PRZYDZIAŁ ZACHOWANY • WKŁAD 0\n%s" % blocker
		if is_current and not blocker.is_empty()
		else "ZDOLNY — przydział na stanowisko %s będzie dawał aktywny wkład." % _role_name(_slot_index)
	)
	var talent_tooltip := _profession_talent_tooltip(survivor)
	if not talent_tooltip.is_empty():
		button.tooltip_text += "\n\n" + talent_tooltip
	button.add_theme_stylebox_override("normal", _candidate_style(is_current, tutorial_target, false))
	button.add_theme_stylebox_override("hover", _candidate_style(is_current, tutorial_target, true))
	button.add_theme_stylebox_override("pressed", _candidate_style(is_current, tutorial_target, true))
	button.add_theme_stylebox_override("focus", _candidate_style(is_current, tutorial_target, true))
	button.add_theme_stylebox_override("disabled", _candidate_disabled_style())
	button.focus_entered.connect(_on_candidate_focused.bind(survivor_id))
	button.mouse_entered.connect(_on_candidate_focused.bind(survivor_id))
	button.pressed.connect(_on_candidate_pressed.bind(survivor_id))
	parent.add_child(button)
	_candidate_buttons.append(button)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	button.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 9)
	margin.add_child(row)
	var portrait = SurvivorPortraitScript.new()
	portrait.custom_minimum_size = Vector2(68, 86)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.configure(survivor_id, str(survivor.display_name))
	row.add_child(portrait)
	var text_column := VBoxContainer.new()
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 2)
	row.add_child(text_column)
	var name := Label.new()
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name.text = str(survivor.display_name).to_upper()
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.add_theme_font_size_override("font_size", 14)
	name.add_theme_color_override("font_color", Color("f0d08a") if not unavailable else Color("7f8a88"))
	text_column.add_child(name)
	var profession := Label.new()
	profession.mouse_filter = Control.MOUSE_FILTER_IGNORE
	profession.text = "POZ. %d  •  %s" % [int(survivor.level), _profession_summary(survivor)]
	profession.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	profession.add_theme_font_size_override("font_size", 10)
	profession.add_theme_color_override("font_color", Color("b8c9c5") if not unavailable else Color("697472"))
	text_column.add_child(profession)
	var status := Label.new()
	status.name = "WorkerCandidateStatus_%s" % survivor_id
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.text = _candidate_status_text(survivor, blocker, is_current)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 10)
	status.add_theme_color_override("font_color", Color("7dd49a") if blocker.is_empty() else Color("d08a7d") if unavailable else Color("d7b96f"))
	text_column.add_child(status)


func _build_current_slot(parent: GridContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "WorkerCurrentSlot"
	panel.custom_minimum_size = Vector2(224, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color("10191bea"), Color("54777b"), 1, 4))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	var heading := Label.new()
	heading.text = "OBSADZONE PRZEZ"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 12)
	heading.add_theme_color_override("font_color", Color("8ca9a9"))
	content.add_child(heading)
	var survivor = _assigned_survivor()
	var occupant := Label.new()
	occupant.name = "WorkerCurrentOccupant"
	occupant.text = str(survivor.display_name).to_upper() if survivor != null else "NIKT"
	occupant.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	occupant.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	occupant.add_theme_font_size_override("font_size", 18)
	occupant.add_theme_color_override("font_color", Color("f0d08a") if survivor != null else Color("a9b5b2"))
	content.add_child(occupant)
	var portrait_holder := CenterContainer.new()
	portrait_holder.custom_minimum_size = Vector2(0, 118)
	content.add_child(portrait_holder)
	if survivor != null:
		var portrait = SurvivorPortraitScript.new()
		portrait.name = "WorkerCurrentPortrait"
		portrait.custom_minimum_size = Vector2(88, 108)
		portrait.configure(str(survivor.id), str(survivor.display_name))
		portrait_holder.add_child(portrait)
	else:
		var empty := Label.new()
		empty.text = "—"
		empty.add_theme_font_size_override("font_size", 36)
		empty.add_theme_color_override("font_color", Color("526165"))
		portrait_holder.add_child(empty)
	var role := Label.new()
	role.text = _role_name(_slot_index).to_upper()
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role.add_theme_font_size_override("font_size", 12)
	role.add_theme_color_override("font_color", Color("d6b96f"))
	content.add_child(role)
	var contribution := Label.new()
	contribution.name = "WorkerCurrentEffectLabel"
	contribution.text = _building_effect_system.worker_contribution_line(
		_state,
		_definition,
		_building,
		_slot_index,
		survivor
	)
	contribution.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contribution.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	contribution.add_theme_font_size_override("font_size", 10)
	contribution.add_theme_color_override("font_color", Color("8fcaa4") if survivor != null else Color("75898c"))
	content.add_child(contribution)
	var clear := Button.new()
	clear.name = "WorkerClearButton"
	clear.text = "ZWOLNIJ STANOWISKO"
	clear.custom_minimum_size = Vector2(0, 42)
	clear.disabled = survivor == null or not _assignments_editable()
	clear.tooltip_text = (
		"Usuń bieżący przydział."
		if not clear.disabled
		else "Stanowisko jest już wolne."
		if survivor == null
		else _assignment_lock_reason()
	)
	clear.pressed.connect(_on_clear_pressed)
	content.add_child(clear)


func _detail_label(parent: Container, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _update_candidate_details(survivor_id: String) -> void:
	if _detail_name == null:
		return
	var survivor = _state.find_survivor(survivor_id) if _state != null and not survivor_id.is_empty() else null
	if survivor == null:
		_detail_portrait.configure("", "Brak mieszkańca")
		_detail_name.text = "BRAK KANDYDATA"
		_detail_profession.text = ""
		_detail_talents.text = ""
		_detail_talents.tooltip_text = ""
		_detail_state.text = ""
		_detail_assignment.text = ""
		_detail_traits.text = ""
		if _detail_positive_trait != null:
			_detail_positive_trait.text = ""
		if _detail_negative_trait != null:
			_detail_negative_trait.text = ""
		for label in _detail_stats.values():
			label.text = ""
		for label in _detail_competencies.values():
			label.text = ""
		return
	var blocker := _candidate_blocker(survivor_id)
	var is_current := survivor_id == _assigned_survivor_id()
	_detail_portrait.configure(survivor_id, str(survivor.display_name))
	_detail_name.text = str(survivor.display_name).to_upper()
	_detail_profession.text = "Poziom %d  •  %s" % [int(survivor.level), _profession_summary(survivor)]
	var talent_names := _profession_talent_names(survivor)
	_detail_talents.text = "TALENTY  •  %s" % " + ".join(talent_names) if not talent_names.is_empty() else "TALENTY  •  BRAK WYBRANYCH"
	_detail_talents.tooltip_text = _profession_talent_tooltip(survivor) if not talent_names.is_empty() else "Talenty wybiera się wyłącznie w aktywnym Domu Wspólnoty II."
	_detail_state.text = _candidate_status_text(survivor, blocker, is_current)
	_detail_state.add_theme_color_override("font_color", Color("7dd49a") if blocker.is_empty() else Color("d7a06f"))
	_detail_state.tooltip_text = (
		"Brak blokad — ta osoba będzie wnosiła aktywny wkład na tym stanowisku."
		if blocker.is_empty()
		else "Dokładna przyczyna niezdolności:\n%s" % blocker
	)
	_detail_assignment.text = _assignment_summary(survivor, is_current)
	for stat_id in _detail_stats.keys():
		var stat_label: Label = _detail_stats[stat_id]
		stat_label.text = SurvivorInfoPresenterScript.stat_text(survivor, str(stat_id))
		stat_label.tooltip_text = SurvivorInfoPresenterScript.stat_tooltip(survivor, str(stat_id))
	_detail_positive_trait.text = "Atut: %s" % str(survivor.positive_trait).capitalize() if not str(survivor.positive_trait).is_empty() else "Atut: brak"
	_detail_positive_trait.tooltip_text = SurvivorInfoPresenterScript.trait_tooltip(str(survivor.positive_trait), true)
	_detail_negative_trait.text = "Słabość: %s" % str(survivor.negative_trait).capitalize() if not str(survivor.negative_trait).is_empty() else "Słabość: brak"
	_detail_negative_trait.tooltip_text = SurvivorInfoPresenterScript.trait_tooltip(str(survivor.negative_trait), false)
	var contact_risk := _contact_risk_summary(survivor)
	if not contact_risk.is_empty():
		_detail_traits.text = contact_risk
		_detail_traits.tooltip_text = "Kontakt przy wspólnej pracy może zwiększyć presję choroby. Wartość pochodzi z bieżącego etapu przypadku chorobowego."
	else:
		_detail_traits.text = "Kontakt zawodowy: brak dodatkowej presji."
		_detail_traits.tooltip_text = "Ta osoba nie wnosi teraz dodatkowej presji choroby przez kontakt zawodowy albo jest objęta izolacją."
	for competency_id in CompetencySystemScript.IDS:
		var competency_label: Label = _detail_competencies[competency_id]
		competency_label.text = "%s %d/%d" % [
			str(CompetencySystemScript.LABELS[competency_id]),
			CompetencySystemScript.level(survivor, competency_id),
			CompetencySystemScript.MAX_LEVEL,
		]
		competency_label.tooltip_text = CompetencySystemScript.tooltip_text(survivor, competency_id)


func _on_candidate_focused(survivor_id: String) -> void:
	_focused_survivor_id = survivor_id
	_update_candidate_details(survivor_id)


func _on_candidate_pressed(survivor_id: String) -> void:
	if _building == null or not _assignments_editable():
		return
	if not _candidate_blocker(survivor_id).is_empty() and survivor_id != _assigned_survivor_id():
		return
	survivor_chosen.emit(str(_building.id), _slot_index, survivor_id)


func _on_clear_pressed() -> void:
	if _building != null and not _assigned_survivor_id().is_empty() and _assignments_editable():
		survivor_chosen.emit(str(_building.id), _slot_index, "")


func _candidate_survivors() -> Array:
	var result: Array = []
	if _state == null or _building == null:
		return result
	var assigned_id := _assigned_survivor_id()
	var current = _state.find_survivor(assigned_id) if not assigned_id.is_empty() else null
	if current != null and current.is_present_in_settlement():
		result.append(current)
	for survivor in _state.get_alive_survivors():
		if survivor == null or not survivor.is_present_in_settlement():
			continue
		if str(survivor.id) == assigned_id:
			continue
		if _building.assigned_survivor_ids.has(str(survivor.id)):
			continue
		result.append(survivor)
	return result


func _initial_candidate_id() -> String:
	var assigned_id := _assigned_survivor_id()
	if not assigned_id.is_empty():
		return assigned_id
	if _state == null or _building == null:
		return ""
	for survivor in _state.get_alive_survivors():
		if survivor == null or not survivor.is_present_in_settlement():
			continue
		if _building.assigned_survivor_ids.has(str(survivor.id)):
			continue
		if _candidate_blocker(str(survivor.id)).is_empty():
			return str(survivor.id)
	return ""


func _assigned_survivor_id() -> String:
	if _building == null or _slot_index < 0 or _slot_index >= _building.assigned_survivor_ids.size():
		return ""
	return str(_building.assigned_survivor_ids[_slot_index])


func _assigned_survivor():
	var survivor_id := _assigned_survivor_id()
	return _state.find_survivor(survivor_id) if _state != null and not survivor_id.is_empty() else null


func _candidate_status_text(survivor, blocker: String, is_current: bool) -> String:
	if blocker.is_empty():
		return "ZDOLNY • JUŻ PRACUJE" if is_current else "ZDOLNY • PO PRZYDZIALE BĘDZIE PRACOWAĆ"
	if is_current:
		return "NIEZDOLNY • PRZYDZIAŁ ZACHOWANY • WKŁAD 0\n%s" % blocker
	return "NIEZDOLNY • PO PRZYDZIALE: WKŁAD 0\n%s" % blocker


func _candidate_blocker(survivor_id: String) -> String:
	if _building == null:
		return "Docelowy budynek nie istnieje."
	return _worker_assignment_system.assignment_candidate_blocker(
		_state,
		survivor_id,
		str(_building.id),
		_slot_index
	)


func _assignment_summary(survivor, is_current: bool) -> String:
	if is_current:
		return "Aktualnie obsadza to stanowisko."
	var assignment_id := str(survivor.current_assignment)
	if assignment_id.is_empty():
		return "Aktualnie: bez przydziału."
	var assignment = _state.find_building(assignment_id)
	if assignment == null:
		return "Aktualnie: inny przydział."
	var definition = GameDatabase.buildings.get(str(assignment.definition_id))
	return "Zmiana przeniesie z: %s." % (str(definition.display_name) if definition != null else str(assignment.definition_id))


func _profession_summary(survivor) -> String:
	var result := str(survivor.profession).capitalize()
	if not str(survivor.secondary_profession).is_empty():
		result += " + " + str(survivor.secondary_profession).capitalize()
	return result


func _profession_talent_names(survivor) -> Array[String]:
	var result: Array[String] = []
	if survivor == null:
		return result
	for profession_id in [str(survivor.profession), str(survivor.secondary_profession)]:
		if profession_id.is_empty():
			continue
		var talent_id := ProfessionTalentSystemScript.selected_talent_id(survivor, profession_id)
		var definition = _profession_talent_system.get_definition(talent_id)
		if definition != null:
			result.append(str(definition.display_name))
	return result


func _profession_talent_tooltip(survivor) -> String:
	var lines: Array[String] = []
	if survivor == null:
		return ""
	for profession_id in [str(survivor.profession), str(survivor.secondary_profession)]:
		if profession_id.is_empty():
			continue
		var talent_id := ProfessionTalentSystemScript.selected_talent_id(survivor, profession_id)
		var definition = _profession_talent_system.get_definition(talent_id)
		if definition != null:
			lines.append("%s — %s" % [str(definition.display_name), str(definition.description)])
	return "Aktywne talenty zawodowe:\n%s" % "\n".join(lines) if not lines.is_empty() else ""


func _contact_risk_summary(survivor) -> String:
	if _is_isolated(str(survivor.id)):
		return ""
	var risks: Array[String] = []
	for disease_case in survivor.disease_cases:
		var presentation := _disease_system.case_presentation(disease_case)
		if bool(presentation.get("infectious", false)) and int(presentation.get("contact_pressure", 0)) > 0:
			risks.append("ryzyko kontaktu: %s +%d" % [
				str(presentation.get("display_name", presentation.get("disease_id", "choroba"))),
				int(presentation.get("contact_pressure", 0)),
			])
	return " • ".join(risks)


func _is_isolated(survivor_id: String) -> bool:
	return (
		_state != null
		and _state.current_day_plan != null
		and survivor_id in _state.current_day_plan.isolated_survivor_ids
	)


func _assignments_editable() -> bool:
	return (
		_state != null
		and _building != null
		and _building.is_active()
		and (not _state.has_method("can_edit_day_plan") or _state.can_edit_day_plan())
	)


func _assignment_lock_reason() -> String:
	if _building == null or not _building.is_active():
		return "Obsada jest zablokowana, dopóki budynek nie będzie aktywny."
	if _state != null and _state.has_method("day_plan_edit_blocker"):
		var blocker := str(_state.day_plan_edit_blocker())
		if not blocker.is_empty():
			return blocker
	return "Obsady nie można zmieniać po zablokowaniu planu dnia."


func _is_tutorial_target(survivor_id: String, unavailable: bool) -> bool:
	if unavailable or _definition == null:
		return false
	return (
		(_tutorial_step == TutorialStateScript.Step.ASSIGN_COMMUNITY_WORKER and str(_definition.id) == "community_house")
		or (_tutorial_step == TutorialStateScript.Step.STAFF_WORKSHOP and str(_definition.id) == "workshop")
	)


func _role_name(slot_index: int) -> String:
	if _definition != null and str(_definition.id) == "diving_station":
		match slot_index:
			0:
				return "Obsługa Stacji"
			1:
				return "Operator liny"
			2:
				return "Technik wyprawy"
	return "Stanowisko %d" % (slot_index + 1)


func _panel_style(fill: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


func _candidate_style(selected: bool, tutorial_target: bool, emphasized: bool) -> StyleBoxFlat:
	var fill := Color("263126") if selected else Color("182326")
	var border := Color("d1a84d") if selected else Color("557277")
	var width := 2 if selected else 1
	if tutorial_target:
		fill = Color("4a351c")
		border = Color("ffd36c")
		width = 3
	elif emphasized:
		fill = fill.lightened(0.08)
		border = border.lightened(0.18)
		width = maxi(width, 2)
	return _panel_style(fill, border, width, 4)


func _candidate_disabled_style() -> StyleBoxFlat:
	return _panel_style(Color("111719d9"), Color("344144"), 1, 4)
