class_name WorkerAssignmentRail
extends PanelContainer

signal worker_picker_requested(building_id: String, slot_index: int)

const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const BuildingEffectSystemScript := preload("res://base_workbench/systems/BuildingEffectSystem.gd")
const WorkerAssignmentSystemScript := preload("res://base_workbench/systems/WorkerAssignmentSystem.gd")
const SurvivorPortraitScript := preload("res://scripts/ui/SurvivorPortrait.gd")
const SurvivorInfoPresenterScript := preload("res://scripts/ui/SurvivorInfoPresenter.gd")

const UI_CANVAS := Color("092f37")
const UI_PANEL := Color("0b3940")
const UI_SURFACE := Color("10464e")
const UI_SURFACE_RAISED := Color("15545a")
const UI_BORDER := Color("2c7277")
const UI_BORDER_SUBTLE := Color("1d5a60")
const UI_TEXT := Color("f2f0e7")
const UI_TEXT_MUTED := Color("b6cac6")
const UI_TEAL := Color("79c4c0")
const UI_AMBER := Color("f2af36")
const UI_AMBER_HOVER := Color("ffcb62")
const UI_GREEN := Color("9bc85c")
const UI_CORAL := Color("ce6252")

var _state
var _definition
var _building
var _tutorial_step: int
var _compact_side: bool = false
var _building_effect_system = BuildingEffectSystemScript.new()
var _worker_assignment_system = WorkerAssignmentSystemScript.new()

func configure(state, definition, building, tutorial_step: int, compact_side: bool = false) -> void:
	_state = state
	_definition = definition
	_building = building
	_tutorial_step = tutorial_step
	_compact_side = compact_side
	custom_minimum_size = Vector2(0, 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", _rail_style())
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var margin := MarginContainer.new()
	var outer_margin := 6 if _compact_side else 12
	margin.add_theme_constant_override("margin_left", outer_margin)
	margin.add_theme_constant_override("margin_top", outer_margin)
	margin.add_theme_constant_override("margin_right", outer_margin)
	margin.add_theme_constant_override("margin_bottom", outer_margin)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)

	var worker_slots: int = _definition.get_worker_slots(_building.level)
	var header := HBoxContainer.new()
	content.add_child(header)
	var eyebrow := Label.new()
	eyebrow.text = "OBSADA"
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eyebrow.add_theme_font_size_override("font_size", 12 if _compact_side else 13)
	eyebrow.add_theme_color_override("font_color", UI_TEXT_MUTED if _compact_side else UI_TEAL)
	header.add_child(eyebrow)
	var occupancy := Label.new()
	occupancy.text = "%d/%d" % [_building.assigned_survivor_ids.size(), worker_slots]
	occupancy.tooltip_text = "%d z %d stanowisk zajętych" % [_building.assigned_survivor_ids.size(), worker_slots]
	occupancy.add_theme_color_override("font_color", UI_GREEN if _building.assigned_survivor_ids.size() >= worker_slots else UI_AMBER)
	occupancy.add_theme_font_size_override("font_size", 12 if _compact_side else 13)
	header.add_child(occupancy)

	for slot_index in range(worker_slots):
		_build_worker_slot(content, slot_index)

	if not _compact_side:
		var hint := Label.new()
		hint.text = (
			"Zmiana przydziału przenosi mieszkańca z poprzedniego budynku."
			if _assignments_editable()
			else _assignment_lock_reason()
		)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", UI_TEXT_MUTED)
		content.add_child(hint)

func _build_worker_slot(content: VBoxContainer, slot_index: int) -> void:
	var assigned_id := ""
	if slot_index < _building.assigned_survivor_ids.size():
		assigned_id = str(_building.assigned_survivor_ids[slot_index])
	var assigned_survivor = _state.find_survivor(assigned_id) if not assigned_id.is_empty() else null
	if _compact_side:
		_build_compact_worker_slot(content, slot_index, assigned_survivor)
		return

	var card := PanelContainer.new()
	card.name = "WorkerSlotRow" if slot_index == 0 else "WorkerSlotRow%d" % (slot_index + 1)
	card.add_theme_stylebox_override("panel", _card_style(assigned_survivor != null))
	content.add_child(card)
	var margin := MarginContainer.new()
	var card_margin := 5 if _compact_side else 9
	margin.add_theme_constant_override("margin_left", card_margin)
	margin.add_theme_constant_override("margin_top", card_margin)
	margin.add_theme_constant_override("margin_right", card_margin)
	margin.add_theme_constant_override("margin_bottom", card_margin)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6 if _compact_side else 9)
	margin.add_child(row)

	var avatar := PanelContainer.new()
	var avatar_size := Vector2(28, 38) if _compact_side else Vector2(48, 58)
	avatar.custom_minimum_size = avatar_size
	avatar.add_theme_stylebox_override("panel", _avatar_style(assigned_survivor != null))
	if assigned_survivor != null:
		var portrait = SurvivorPortraitScript.new()
		portrait.custom_minimum_size = avatar_size
		portrait.configure(str(assigned_survivor.id), str(assigned_survivor.display_name))
		avatar.add_child(portrait)
	else:
		var empty := Label.new()
		empty.text = "—"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 16 if _compact_side else 20)
		empty.add_theme_color_override("font_color", UI_TEXT_MUTED)
		avatar.add_child(empty)
	row.add_child(avatar)

	var slot_column := VBoxContainer.new()
	slot_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_column.add_theme_constant_override("separation", 3)
	row.add_child(slot_column)
	var role_row := HBoxContainer.new()
	slot_column.add_child(role_row)
	var role := Label.new()
	role.text = _compact_role_name(slot_index) if _compact_side else _role_name(slot_index).to_upper()
	role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role.add_theme_font_size_override("font_size", 10 if _compact_side else 11)
	role.add_theme_color_override("font_color", UI_TEAL)
	role_row.add_child(role)
	var availability := Label.new()
	availability.name = "WorkerAvailabilityLabel" if slot_index == 0 else "WorkerAvailabilityLabel%d" % (slot_index + 1)
	var assigned_isolated := assigned_survivor != null and _is_isolated(str(assigned_survivor.id))
	var assigned_capable := (
		assigned_survivor != null
		and _building_effect_system.worker_is_capable(
			_state,
			_definition,
			_building,
			slot_index,
			assigned_survivor
		)
	)
	var full_availability := (
		"IZOLACJA"
		if assigned_isolated
		else "ZDOLNY"
		if assigned_capable
		else "NIEZDOLNY"
		if assigned_survivor != null
		else "WOLNE"
	)
	availability.text = _compact_availability_text(full_availability) if _compact_side else full_availability
	if assigned_survivor != null:
		var role_blocker := _worker_assignment_system.assignment_role_blocker(
			_state,
			str(assigned_survivor.id),
			str(_building.id),
			slot_index
		)
		availability.tooltip_text = (
			"ZDOLNY — przydział daje aktywny wkład na tym stanowisku."
			if role_blocker.is_empty()
			else "NIEZDOLNY — wkład na tym stanowisku wynosi 0.\n%s" % role_blocker
		)
	availability.add_theme_font_size_override("font_size", 9 if _compact_side else 10)
	availability.add_theme_color_override("font_color", UI_GREEN if assigned_capable else UI_CORAL if assigned_survivor != null else UI_TEXT_MUTED)
	role_row.add_child(availability)

	var occupant := Label.new()
	occupant.name = "WorkerOccupantLabel" if slot_index == 0 else "WorkerOccupantLabel%d" % (slot_index + 1)
	occupant.text = str(assigned_survivor.display_name).to_upper() if assigned_survivor != null else "NIKT"
	occupant.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	occupant.add_theme_font_size_override("font_size", 11 if _compact_side else 14)
	occupant.add_theme_color_override("font_color", UI_TEXT if assigned_survivor != null else UI_TEXT_MUTED)
	slot_column.add_child(occupant)

	var contribution := Label.new()
	contribution.name = "WorkerEffectLabel" if slot_index == 0 else "WorkerEffectLabel%d" % (slot_index + 1)
	contribution.text = _building_effect_system.worker_contribution_line(
		_state,
		_definition,
		_building,
		slot_index,
		assigned_survivor
	)
	contribution.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contribution.add_theme_font_size_override("font_size", 9 if _compact_side else 10)
	var contribution_color := UI_GREEN if assigned_survivor != null and _building.is_active() and _building_effect_system.worker_is_capable(_state, _definition, _building, slot_index, assigned_survivor) else UI_CORAL
	if assigned_survivor == null:
		contribution_color = UI_TEXT_MUTED
	contribution.add_theme_color_override("font_color", contribution_color)
	slot_column.add_child(contribution)

	var change := Button.new()
	change.name = "WorkerChangeButton" if slot_index == 0 else "WorkerChangeButton%d" % (slot_index + 1)
	change.text = "ZMIEŃ" if assigned_survivor != null else "OBSADŹ" if _compact_side else "WYBIERZ"
	change.custom_minimum_size = Vector2(54, 36) if _compact_side else Vector2(88, 42)
	change.add_theme_font_size_override("font_size", 10 if _compact_side else 12)
	change.disabled = not _assignments_editable()
	change.tooltip_text = (
		"Otwórz kafelki mieszkańców dla stanowiska: %s" % _role_name(slot_index)
		if not change.disabled
		else _assignment_lock_reason()
	)
	change.pressed.connect(_on_change_pressed.bind(slot_index))
	if (_tutorial_step == TutorialStateScript.Step.ASSIGN_COMMUNITY_WORKER and _definition.id == "community_house") or (_tutorial_step == TutorialStateScript.Step.STAFF_WORKSHOP and _definition.id == "workshop"):
		change.add_theme_stylebox_override("normal", _target_style())
	row.add_child(change)


func _build_compact_worker_slot(content: VBoxContainer, slot_index: int, assigned_survivor) -> void:
	var card := PanelContainer.new()
	card.name = "WorkerSlotRow" if slot_index == 0 else "WorkerSlotRow%d" % (slot_index + 1)
	card.add_theme_stylebox_override("panel", _compact_card_style(assigned_survivor != null))
	content.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)

	var slot_label := Label.new()
	slot_label.text = "OBSADZONE PRZEZ:" if assigned_survivor != null else "WOLNE STANOWISKO"
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.add_theme_font_size_override("font_size", 9)
	slot_label.add_theme_color_override("font_color", UI_TEXT_MUTED if assigned_survivor != null else UI_AMBER)
	column.add_child(slot_label)

	var role := Label.new()
	role.text = _role_name(slot_index).to_upper()
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role.add_theme_font_size_override("font_size", 11)
	role.add_theme_color_override("font_color", UI_TEXT)
	column.add_child(role)

	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(64, 70)
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	avatar.add_theme_stylebox_override("panel", _compact_avatar_style(assigned_survivor != null))
	column.add_child(avatar)
	if assigned_survivor != null:
		var portrait = SurvivorPortraitScript.new()
		portrait.custom_minimum_size = Vector2(58, 64)
		portrait.configure(str(assigned_survivor.id), str(assigned_survivor.display_name))
		avatar.add_child(portrait)
	else:
		var empty := Label.new()
		empty.text = "—"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 30)
		empty.add_theme_color_override("font_color", UI_TEXT_MUTED)
		avatar.add_child(empty)

	var identity := Label.new()
	identity.name = "WorkerOccupantLabel" if slot_index == 0 else "WorkerOccupantLabel%d" % (slot_index + 1)
	identity.text = str(assigned_survivor.display_name).to_upper() if assigned_survivor != null else "NIEOBSADZONE"
	identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.add_theme_font_size_override("font_size", 13)
	identity.add_theme_color_override("font_color", UI_TEXT if assigned_survivor != null else UI_TEXT_MUTED)
	column.add_child(identity)

	if assigned_survivor != null:
		var trait_label := Label.new()
		var trait_name := str(assigned_survivor.positive_trait).strip_edges()
		trait_label.text = trait_name.capitalize() if not trait_name.is_empty() else "MIESZKANIEC PRZYSTANI"
		trait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		trait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		trait_label.tooltip_text = SurvivorInfoPresenterScript.trait_tooltip(trait_name, true) if not trait_name.is_empty() else "Brak zapisanej cechy narracyjnej."
		trait_label.add_theme_font_size_override("font_size", 10)
		trait_label.add_theme_color_override("font_color", UI_GREEN)
		column.add_child(trait_label)

		var profession := Label.new()
		profession.text = "%s  •  POZIOM %d" % [_profession_display_name(assigned_survivor), int(assigned_survivor.level)]
		profession.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		profession.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		profession.add_theme_font_size_override("font_size", 9)
		profession.add_theme_color_override("font_color", UI_TEXT)
		column.add_child(profession)

		var fatigue := Label.new()
		fatigue.name = "WorkerFatigueLabel" if slot_index == 0 else "WorkerFatigueLabel%d" % (slot_index + 1)
		fatigue.text = "ZMĘCZENIE %d%%" % int(assigned_survivor.fatigue)
		fatigue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fatigue.tooltip_text = SurvivorInfoPresenterScript.stat_tooltip(assigned_survivor, "fatigue")
		fatigue.add_theme_font_size_override("font_size", 10)
		fatigue.add_theme_color_override("font_color", _fatigue_color(int(assigned_survivor.fatigue)))
		column.add_child(fatigue)

	else:
		var hint := Label.new()
		hint.text = "Wybierz zdolną osobę do tego stanowiska."
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", UI_TEXT_MUTED)
		column.add_child(hint)

	var effect := Label.new()
	effect.name = "WorkerEffectLabel" if slot_index == 0 else "WorkerEffectLabel%d" % (slot_index + 1)
	effect.text = _building_effect_system.worker_contribution_line(
		_state,
		_definition,
		_building,
		slot_index,
		assigned_survivor
	)
	effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.add_theme_font_size_override("font_size", 9)
	effect.add_theme_color_override("font_color", UI_TEXT if assigned_survivor != null else UI_TEXT_MUTED)
	column.add_child(effect)

	var change := Button.new()
	change.name = "WorkerChangeButton" if slot_index == 0 else "WorkerChangeButton%d" % (slot_index + 1)
	change.text = "ZMIEŃ" if assigned_survivor != null else "OBSADŹ"
	change.custom_minimum_size = Vector2(0, 28)
	change.add_theme_font_size_override("font_size", 9)
	change.disabled = not _assignments_editable()
	change.tooltip_text = "Otwórz wybór mieszkańców dla stanowiska: %s" % _role_name(slot_index) if not change.disabled else _assignment_lock_reason()
	change.add_theme_stylebox_override("normal", _compact_action_style(UI_PANEL, UI_BORDER, 1))
	change.add_theme_stylebox_override("hover", _compact_action_style(UI_SURFACE_RAISED, UI_TEAL, 2))
	change.add_theme_stylebox_override("pressed", _compact_action_style(UI_CANVAS, UI_AMBER, 2))
	change.add_theme_stylebox_override("focus", _compact_action_style(UI_SURFACE_RAISED, UI_TEAL, 2))
	change.add_theme_stylebox_override("disabled", _compact_action_style(UI_PANEL, UI_BORDER_SUBTLE, 1))
	change.pressed.connect(_on_change_pressed.bind(slot_index))
	if (_tutorial_step == TutorialStateScript.Step.ASSIGN_COMMUNITY_WORKER and _definition.id == "community_house") or (_tutorial_step == TutorialStateScript.Step.STAFF_WORKSHOP and _definition.id == "workshop"):
		change.add_theme_stylebox_override("normal", _target_style())
	column.add_child(change)
	column.move_child(change, column.get_child_count() - 2)

func _on_change_pressed(slot_index: int) -> void:
	if not _assignments_editable():
		return
	worker_picker_requested.emit(str(_building.id), slot_index)


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


func _is_isolated(survivor_id: String) -> bool:
	return (
		_state != null
		and _state.current_day_plan != null
		and survivor_id in _state.current_day_plan.isolated_survivor_ids
	)

func _role_name(slot_index: int) -> String:
	if _definition.id == "diving_station":
		match slot_index:
			0:
				return "Obsługa Stacji"
			1:
				return "Operator liny"
			2:
				return "Technik wyprawy"
	return "Stanowisko %d" % (slot_index + 1)


func _compact_role_name(slot_index: int) -> String:
	if _definition.id == "diving_station":
		match slot_index:
			0:
				return "OBSŁ."
			1:
				return "OPER."
			2:
				return "TECH."
	return "SLOT %d" % (slot_index + 1)


func _compact_availability_text(value: String) -> String:
	match value:
		"ZDOLNY":
			return "OK"
		"NIEZDOLNY":
			return "0"
		"IZOLACJA":
			return "IZOL."
		_:
			return value


func _profession_display_name(survivor) -> String:
	var profession := str(survivor.profession).strip_edges().replace("_", " ")
	return profession.capitalize() if not profession.is_empty() else "Mieszkaniec"


func _fatigue_color(fatigue: int) -> Color:
	if fatigue >= 85:
		return UI_CORAL
	if fatigue >= 50:
		return UI_AMBER
	return UI_GREEN


func _rail_style() -> StyleBoxFlat:
	if _compact_side:
		var compact_style := StyleBoxFlat.new()
		compact_style.bg_color = Color(UI_CANVAS, 0.96)
		compact_style.border_color = UI_BORDER
		compact_style.set_border_width_all(1)
		compact_style.corner_radius_top_left = 2
		compact_style.corner_radius_top_right = 2
		compact_style.corner_radius_bottom_left = 2
		compact_style.corner_radius_bottom_right = 2
		return compact_style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UI_SURFACE_RAISED, 0.95)
	style.border_color = UI_BORDER_SUBTLE
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _card_style(is_filled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_SURFACE_RAISED if is_filled else UI_SURFACE
	style.border_color = UI_BORDER if is_filled else UI_BORDER_SUBTLE
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style

func _avatar_style(is_filled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_CANVAS if is_filled else UI_PANEL
	style.border_color = UI_TEAL if is_filled else UI_BORDER_SUBTLE
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style


func _compact_card_style(is_filled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_PANEL if is_filled else UI_SURFACE
	style.border_color = UI_BORDER if is_filled else UI_BORDER_SUBTLE
	style.set_border_width_all(1)
	style.corner_radius_top_left = 1
	style.corner_radius_top_right = 1
	style.corner_radius_bottom_left = 1
	style.corner_radius_bottom_right = 1
	return style


func _compact_avatar_style(is_filled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_CANVAS if is_filled else UI_SURFACE
	style.border_color = UI_BORDER if is_filled else UI_BORDER_SUBTLE
	style.set_border_width_all(2)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	return style


func _compact_action_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 1
	style.corner_radius_top_right = 1
	style.corner_radius_bottom_left = 1
	style.corner_radius_bottom_right = 1
	return style


func _target_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("a66318")
	style.border_color = UI_AMBER_HOVER
	style.set_border_width_all(3)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style
