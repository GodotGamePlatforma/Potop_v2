extends Node

const BaseScene := preload("res://scenes/base/BaseScene.tscn")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")

var _failed := false


func _ready() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(941, DifficultyProfileScript.new())
	state.tutorial.complete()

	# Deliberately decouple portrait IDs from resident IDs so the assertions
	# prove that UI consumers bind the canonical portrait_id field.
	state.find_survivor("mira").portrait_id = "anka"
	state.find_survivor("igor").portrait_id = "mira"

	await _test_crew_portrait_bindings(state)
	await _test_diver_portrait_selection(state)
	state = null
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout

	if _failed:
		get_tree().quit(1)
		return
	print("Base portrait binding test passed: Crew rows and the selected Diving Station profile follow SurvivorState.portrait_id without stealing input.")
	get_tree().quit(0)


func _test_crew_portrait_bindings(state) -> void:
	var base = BaseScene.instantiate()
	add_child(base)
	await get_tree().process_frame
	base.bind(null, state)
	await get_tree().process_frame

	var crew_button := base.find_child("CrewButton", true, false) as Button
	_assert(crew_button != null, "The base HUD must expose the Crew button.")
	if crew_button == null:
		base.queue_free()
		await get_tree().process_frame
		return
	crew_button.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame

	var crew_panel := base.find_child("SurvivorsPanel", true, false) as Control
	_assert(crew_panel != null and crew_panel.visible, "Opening Crew must expose the resident list.")
	for survivor in state.get_alive_survivors():
		if survivor.has_method("is_present_in_settlement") and not survivor.is_present_in_settlement():
			continue
		var button := crew_panel.find_child("SurvivorButton_%s" % survivor.id, true, false) as Button if crew_panel != null else null
		var portrait := button.find_child("CrewPortrait_%s" % survivor.id, true, false) if button != null else null
		var row := portrait.get_parent() as HBoxContainer if portrait != null else null
		var summary := button.find_child("SurvivorSummary_%s" % survivor.id, true, false) as Label if button != null else null
		var survivor_scroll := button.get_parent().get_parent() as ScrollContainer if button != null and button.get_parent() != null and button.get_parent().get_parent() != null else null
		_assert(button != null, "Crew must retain a focusable resident button for %s." % survivor.id)
		_assert(portrait != null, "Crew must render an individual portrait for %s." % survivor.id)
		if button == null or portrait == null:
			continue
		_assert(str(portrait.get("survivor_id")) == str(survivor.portrait_id), "Crew portrait for %s must bind SurvivorState.portrait_id." % survivor.id)
		_assert(str(portrait.get("display_name")) == str(survivor.display_name), "Crew portrait for %s must retain the resident display name." % survivor.id)
		_assert(button.focus_mode != Control.FOCUS_NONE, "Crew portrait decoration must not replace the resident button's focus target for %s." % survivor.id)
		_assert(portrait.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Crew portrait decoration must not intercept pointer input for %s." % survivor.id)
		_assert(summary != null and summary.size.x + 0.5 >= summary.get_combined_minimum_size().x, "Crew resident summary must receive enough width for %s." % survivor.id)
		if row != null and survivor_scroll != null:
			var visible_rect := survivor_scroll.get_global_rect()
			var row_rect := row.get_global_rect()
			_assert(row_rect.position.x >= visible_rect.position.x - 0.5 and row_rect.end.x <= visible_rect.end.x + 0.5, "Crew portrait and resident summary must remain inside the visible scroll area for %s." % survivor.id)
		else:
			_assert(false, "Crew row and its visible scroll area must exist for %s." % survivor.id)

	var mira_button := crew_panel.find_child("SurvivorButton_mira", true, false) as Button if crew_panel != null else null
	if mira_button != null:
		mira_button.grab_focus()
		await get_tree().process_frame
		_assert(get_viewport().gui_get_focus_owner() == mira_button, "The Crew row button must remain the keyboard focus owner after adding its portrait.")
		mira_button.emit_signal("pressed")
		await get_tree().process_frame
		await get_tree().process_frame
		var development_panel := base.find_child("SurvivorDevelopmentPanel", true, false) as Control
		_assert(development_panel != null and development_panel.visible, "The portrait-bearing Crew row must still open the resident card when activated.")

	base.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	base = null


func _test_diver_portrait_selection(state) -> void:
	var station := BuildingStateScript.new()
	station.id = "portrait_test_station"
	station.definition_id = "diving_station"
	station.slot_id = "bottom_right"
	station.level = 1
	station.is_built = true
	station.condition = 100
	state.buildings.append(station)
	var slot_data: Dictionary = state.platform.slot_states.get("bottom_right", {})
	slot_data["building_id"] = station.id
	state.platform.slot_states["bottom_right"] = slot_data

	var base = BaseScene.instantiate()
	add_child(base)
	await get_tree().process_frame
	base.bind(null, state)
	await get_tree().process_frame
	var station_slot := base.find_child("Slot_bottom_right", true, false)
	_assert(station_slot != null, "The portrait binding fixture requires the Diving Station slot.")
	if station_slot == null:
		base.queue_free()
		await get_tree().process_frame
		return
	station_slot.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame

	for survivor_id in ["mira", "igor"]:
		var candidate := base.find_child("DiverCandidate_%s" % survivor_id, true, false) as Button
		var survivor = state.find_survivor(survivor_id)
		_assert(candidate != null and not candidate.disabled, "The Diving Station diver rail must expose an enabled DiverCandidate_%s button." % survivor_id)
		if candidate == null or candidate.disabled:
			continue
		candidate.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_assert(str(state.current_day_plan.selected_diver_id) == survivor_id, "Changing the selected diver must update DayPlanState.selected_diver_id to %s." % survivor_id)
		_assert(station.assigned_survivor_ids.is_empty(), "Selecting %s as the diver must not add them to the independent Station staffing roster." % survivor_id)
		_assert(str(survivor.current_assignment).is_empty(), "Selecting %s as the diver must not create a worker assignment." % survivor_id)
		_assert_diver_portrait(base, survivor, "selected diver %s" % survivor_id)

	var clear_selection := base.find_child("DiverSelectionClear", true, false) as Button
	_assert(clear_selection != null and not clear_selection.disabled, "The selected diver profile must expose its enabled clear command.")
	if clear_selection != null and not clear_selection.disabled:
		clear_selection.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_assert(str(state.current_day_plan.selected_diver_id).is_empty() and str(state.preferred_diver_id).is_empty(), "Clearing the selected diver through Base must also forget the remembered preference.")
		_assert(station.assigned_survivor_ids.is_empty(), "Clearing the diver selection must leave the independent Station staffing roster unchanged.")
		_assert(base.find_child("DiverSelectionClear", true, false) == null and base.find_child("DiverPortrait", true, false) == null, "Clearing the diver selection must rerender the Station without a stale clear command or portrait.")

	base.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	base = null


func _assert_diver_portrait(hud: Control, survivor, context: String) -> void:
	var portrait := hud.find_child("DiverPortrait", true, false)
	var name_label := hud.find_child("DiverNameLabel", true, false) as Label
	_assert(portrait != null, "DivingStationHud must render a portrait for the %s." % context)
	_assert(name_label != null and name_label.text == survivor.display_name, "DivingStationHud must render the name of the %s." % context)
	if portrait == null:
		return
	_assert(str(portrait.get("survivor_id")) == str(survivor.portrait_id), "DivingStationHud must bind portrait_id for the %s." % context)
	_assert(str(portrait.get("display_name")) == str(survivor.display_name), "DivingStationHud must configure the display name for the %s." % context)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
