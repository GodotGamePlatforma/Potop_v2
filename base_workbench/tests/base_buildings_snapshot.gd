extends Node

const BaseScene := preload("res://base_workbench/runtime/BaseScene.tscn")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const BuildingPresentationScript := preload("res://base_workbench/ui/BuildingPresentation.gd")
const WeatherStateScript := preload("res://scripts/data/WeatherState.gd")

const BUILDING_SLOTS := {
	"fishing_hut": "top_left",
	"kitchen": "top_center",
	"community_house": "top_right",
	"workshop": "bottom_left",
	"infirmary": "center",
	"diving_station": "bottom_right",
}

func _ready() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(902, DifficultyProfileScript.new())
	state.tutorial.complete()
	var base = BaseScene.instantiate()
	add_child(base)
	await get_tree().process_frame
	if base.has_method("set_animation_time_for_tests"):
		base.set_animation_time_for_tests(1.7)
	else:
		var environment = base.find_child("BaseEnvironment", true, false)
		if environment != null:
			environment.set_animation_time_for_tests(1.7)

	_set_all_buildings(state, 2)
	state.find_survivor("igor").unspent_skill_points = 1
	state.find_survivor("igor").set_job_experience("medyk", 100)
	base.bind(null, state)
	await get_tree().process_frame
	base.get_node("BaseEnvironment/PlatformBoard/BuildingSlots/Slot_top_right").emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var community_roster := base.find_child("CommunityCrewGrid", true, false) as GridContainer
	var roster_matches := community_roster != null and community_roster.columns == 2 and community_roster.get_child_count() == 3
	for survivor_id in ["mira", "anka", "igor"]:
		var survivor_card := community_roster.get_node_or_null("CommunitySurvivorCard_%s" % survivor_id) as Button if community_roster != null else null
		roster_matches = roster_matches and survivor_card != null and str(survivor_card.get_meta("survivor_id", "")) == survivor_id
	var community_identity := base.find_child("CommunityDevelopmentIdentity", true, false) as Label
	var community_development := base.find_child("CommunityDevelopmentActions", true, false) as GridContainer
	var career_progress := base.find_child("CommunityCareerProgress", true, false) as Label
	var promotion_button := base.find_child("PromoteProfessionButton", true, false) as Button
	if not roster_matches or community_identity == null or not community_identity.text.contains("IGOR SOWA") or community_development == null or community_development.get_child_count() != 3 or career_progress == null or not career_progress.text.contains("GOTOWY DO AWANSU") or promotion_button == null or promotion_button.disabled:
		push_error("Community House II panel should expose the settlement roster, personal development and a ready executable career promotion.")
		get_tree().quit(1)
		return
	var community_scroll := base.find_child("PanelScroll", true, false) as ScrollContainer
	if community_scroll != null:
		community_scroll.scroll_vertical = int(community_scroll.get_v_scroll_bar().max_value)
		await get_tree().process_frame
		await get_tree().process_frame
	if not _save_snapshot("base_community_development.png"):
		return
	base._close_building_panel()

	for level in range(1, 5):
		_set_all_buildings(state, level)
		base.bind(null, state)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		if not _assert_3d_building_variants(base, level):
			get_tree().quit(1)
			return
		if not _save_snapshot("base_all_buildings_level%d.png" % level):
			return

	var moderate_weather = state.weather
	state.weather = _storm_weather()
	base.set_graphics_quality("high")
	base.set_animation_time_for_tests(1.7 / state.weather.wave_speed_multiplier)
	for level in range(1, 5):
		_set_all_buildings(state, level)
		base.bind(null, state)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		if int(state.weather.condition) != WeatherStateScript.Condition.STORM:
			push_error("Storm building snapshots must retain the strongest weather profile.")
			get_tree().quit(1)
			return
		if not _assert_3d_building_variants(base, level):
			get_tree().quit(1)
			return
		if not _save_snapshot("base_storm_all_buildings_level%d.png" % level):
			return
	state.weather = moderate_weather
	base.set_animation_time_for_tests(1.7 / state.weather.wave_speed_multiplier)

	_set_all_buildings(state, 1)
	var idle_workshop = state.find_building_by_definition("workshop")
	idle_workshop.assigned_survivor_ids.assign(["anka"])
	state.resources.set_amount("platform_integrity", 100)
	base.bind(null, state)
	await get_tree().process_frame
	var idle_presentation = base.get_node_or_null("BaseEnvironment/PlatformBoard/Buildings/Presentation_bottom_left")
	if idle_presentation == null or int(idle_presentation.visual_state) != int(BuildingPresentationScript.VisualState.ACTIVE_IDLE):
		push_error("A staffed workshop with a full-integrity platform and no queue must look idle instead of producing fake work effects.")
		get_tree().quit(1)
		return
	idle_workshop.assigned_survivor_ids.clear()
	var staffed_fishing = state.find_building_by_definition("fishing_hut")
	var active_kitchen = state.find_building_by_definition("kitchen")
	var upgraded_workshop = state.find_building_by_definition("workshop")
	var compatibility_blocked_infirmary = state.find_building_by_definition("infirmary")
	var blocked_station = state.find_building_by_definition("diving_station")
	staffed_fishing.assigned_survivor_ids.assign(["anka"])
	active_kitchen.is_built = true
	upgraded_workshop.level = 2
	compatibility_blocked_infirmary.condition = 0
	blocked_station.assigned_survivor_ids.assign(["igor"])
	var igor = state.find_survivor("igor")
	var original_igor_fatigue: int = igor.fatigue
	igor.fatigue = 95
	base.bind(null, state)
	base.set_animation_time_for_tests(2.25)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _assert_motion_state_matrix(base):
		get_tree().quit(1)
		return
	var building_layer := base.get_node("BaseEnvironment/PlatformBoard/Buildings")
	var stable_child_count := building_layer.get_child_count()
	base.bind(null, state)
	await get_tree().process_frame
	if building_layer.get_child_count() != stable_child_count:
		push_error("Persistent building presentations must not duplicate children across repeated renders.")
		get_tree().quit(1)
		return
	if not _save_snapshot("base_building_motion_states.png"):
		return
	igor.fatigue = original_igor_fatigue
	_set_all_buildings(state, 4)

	state.resources.set_amount("scrap", 20)
	state.resources.set_amount("fabric_rubber", 20)
	state.resources.set_amount("tech_parts", 20)
	var workshop = state.find_building_by_definition("workshop")
	workshop.assigned_survivor_ids.assign(["anka"])
	base.bind(null, state)
	await get_tree().process_frame
	base.get_node("BaseEnvironment/PlatformBoard/BuildingSlots/Slot_bottom_left").emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var craft_button := base.find_child("Craft_diving_lantern_mk2", true, false) as Button
	var recipe_grid := base.find_child("WorkshopRecipeGrid", true, false) as GridContainer
	var lantern_tile := base.find_child("RecipeTile_diving_lantern_mk2", true, false) as Button
	var locked_tank_tile := base.find_child("RecipeTile_oxygen_tank_mk2", true, false) as Button
	if craft_button == null or craft_button.disabled:
		push_error("Workshop panel should expose an enabled Lantern II recipe for a staffed workshop with materials.")
		get_tree().quit(1)
		return
	if recipe_grid == null or recipe_grid.get_child_count() < 4 or lantern_tile == null or locked_tank_tile == null:
		push_error("Workshop panel should expose the complete data-driven equipment recipe catalog as selectable tiles, including higher-level recipes.")
		get_tree().quit(1)
		return
	if not _save_snapshot("base_workshop_lantern_recipe.png"):
		return

	base._close_building_panel()
	workshop.level = 2
	base.bind(null, state)
	await get_tree().process_frame
	base.get_node("BaseEnvironment/PlatformBoard/BuildingSlots/Slot_bottom_left").emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var tank_tile := base.find_child("RecipeTile_oxygen_tank_mk2", true, false) as Button
	if tank_tile == null:
		push_error("Workshop level two should retain the Oxygen Tank II catalog tile.")
		get_tree().quit(1)
		return
	tank_tile.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var tank_craft_button := base.find_child("Craft_oxygen_tank_mk2", true, false) as Button
	if tank_craft_button == null or tank_craft_button.disabled:
		push_error("Workshop level two should expose an enabled Oxygen Tank II recipe for a staffed workshop with materials.")
		get_tree().quit(1)
		return
	if not _save_snapshot("base_workshop_oxygen_tank_recipe.png"):
		return

	base._close_building_panel()
	workshop.assigned_survivor_ids.clear()
	state.diving_equipment.add_gear("diving_lantern_mk2")
	state.diving_equipment.equip("light", "diving_lantern_mk2")
	state.diving_equipment.add_gear("oxygen_tank_mk2")
	state.diving_equipment.add_gear("oxygen_tank_mk3")
	state.diving_equipment.equip("oxygen_tank", "oxygen_tank_mk3")
	var station = state.find_building_by_definition("diving_station")
	station.assigned_survivor_ids.assign(["anka"])
	state.current_day_plan.set_selected_diver("igor")
	base.bind(null, state)
	await get_tree().process_frame
	base.get_node("BaseEnvironment/PlatformBoard/BuildingSlots/Slot_bottom_right").emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var light_picker := base.find_child("LightGearPicker", true, false) as OptionButton
	if light_picker == null or light_picker.item_count != 2 or str(light_picker.get_selected_metadata()) != "diving_lantern_mk2":
		push_error("Diving Station panel should allow selecting both owned lanterns and preserve Lantern II as equipped.")
		get_tree().quit(1)
		return
	var oxygen_tank_picker := base.find_child("OxygenTankGearPicker", true, false) as OptionButton
	if oxygen_tank_picker == null or oxygen_tank_picker.item_count != 3 or str(oxygen_tank_picker.get_selected_metadata()) != "oxygen_tank_mk3":
		push_error("Diving Station panel should allow selecting all owned oxygen tanks and preserve Oxygen Tank III as equipped.")
		get_tree().quit(1)
		return
	var diver_name := base.find_child("DiverNameLabel", true, false) as Label
	var health_bar := base.find_child("DiverHealthBar", true, false) as ProgressBar
	var oxygen_bar := base.find_child("DiverOxygenBar", true, false) as ProgressBar
	var traits_label := base.find_child("DiverTraitsLabel", true, false) as Label
	var states_label := base.find_child("DiverStatesLabel", true, false) as Label
	var dive_button := base.find_child("DiveButton", true, false) as Button
	if diver_name == null or diver_name.text != "Igor Sowa" or health_bar == null or oxygen_bar == null or not is_equal_approx(oxygen_bar.value, 185.0) or traits_label == null or states_label == null or dive_button == null:
		push_error("Diving Station panel should expose the diver identity, health, oxygen, traits, states and dive action.")
		get_tree().quit(1)
		return
	if not _save_snapshot("base_diving_lantern_equipment.png"):
		return

	base._close_building_panel()
	station.level = 2
	base.bind(null, state)
	await get_tree().process_frame
	base.get_node("BaseEnvironment/PlatformBoard/BuildingSlots/Slot_bottom_right").emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var operator_change := base.find_child("WorkerChangeButton2", true, false) as Button
	if operator_change == null or operator_change.disabled:
		push_error("Diving Station level two should expose the editable Operator liny slot in the current staffing rail.")
		get_tree().quit(1)
		return
	operator_change.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var mira_candidate := base.find_child("WorkerCandidate_mira", true, false) as Button
	if mira_candidate == null or mira_candidate.disabled:
		push_error("The Operator liny candidate grid should include Mira as an eligible unassigned survivor.")
		get_tree().quit(1)
		return
	mira_candidate.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	if station.assigned_survivor_ids != ["anka", "mira"] or state.find_survivor("mira").current_assignment != station.id:
		push_error("Selecting the second assignment slot should persist the operator after the Station support worker without duplicating UI state.")
		get_tree().quit(1)
		return
	var action_feedback := base.find_child("BaseActionFeedback", true, false) as Control
	var building_panel := base.find_child("BuildingPanel", true, false) as Control
	var building_modal := base.find_child("BuildingModal", true, false) as Control
	var resource_bar := base.find_child("ResourceBar", true, false) as Control
	var tutorial_panel := base.find_child("TutorialPanel", true, false) as Control
	var feedback_rect := action_feedback.get_global_rect() if action_feedback != null else Rect2()
	var panel_rect := building_panel.get_global_rect() if building_panel != null else Rect2()
	var viewport_rect := get_viewport().get_visible_rect()
	if action_feedback == null or not action_feedback.visible or building_panel == null or building_modal == null or resource_bar == null or tutorial_panel == null or not feedback_rect.size.is_equal_approx(Vector2(312.0, 62.0)) or absf(feedback_rect.get_center().x - viewport_rect.get_center().x) > 1.0 or not feedback_rect.intersects(panel_rect) or action_feedback.z_index <= building_modal.z_index or feedback_rect.intersects(resource_bar.get_global_rect()) or feedback_rect.intersects(tutorial_panel.get_global_rect()) or action_feedback.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		push_error("Assignment feedback must be a compact, centered, input-transparent toast layered over the building panel without covering the ResourceBar or tutorial. Visible=%s feedback=%s panel=%s z=%d/%d mouse_filter=%d" % [action_feedback.visible if action_feedback != null else false, feedback_rect, panel_rect, action_feedback.z_index if action_feedback != null else -1, building_modal.z_index if building_modal != null else -1, action_feedback.mouse_filter if action_feedback != null else -1])
		get_tree().quit(1)
		return
	if not _save_snapshot("base_assignment_feedback.png"):
		return

	print("Base building snapshots saved; shared assignment rail and Diving Station HUD verified.")
	get_tree().quit(0)

func _set_all_buildings(state, level: int) -> void:
	state.buildings.clear()
	for slot_id in state.platform.slot_states.keys():
		var empty_slot: Dictionary = state.platform.slot_states[slot_id]
		empty_slot["building_id"] = ""
		state.platform.slot_states[slot_id] = empty_slot
	for definition_id in BUILDING_SLOTS.keys():
		var building = BuildingStateScript.new()
		building.id = "snapshot_%s" % definition_id
		building.definition_id = definition_id
		building.slot_id = BUILDING_SLOTS[definition_id]
		building.level = level
		building.is_built = true
		state.buildings.append(building)
		var slot_data: Dictionary = state.platform.slot_states[building.slot_id]
		slot_data["building_id"] = building.id
		state.platform.slot_states[building.slot_id] = slot_data

func _storm_weather():
	var weather = WeatherStateScript.new()
	weather.condition = WeatherStateScript.Condition.STORM
	weather.sea_intensity = 1.0
	weather.rain_intensity = 1.0
	weather.motion_intensity = 1.16
	weather.foam_intensity = 1.0
	weather.splash_intensity = 1.0
	weather.wave_speed_multiplier = 1.34
	weather.wind_direction = Vector2(0.76, 0.65)
	weather.ensure_compatibility(1)
	return weather

func _assert_3d_building_variants(base: Control, level: int) -> bool:
	var environment = base.get_node_or_null("BaseEnvironment")
	if environment == null or not environment.has_method("world_state_for_tests"):
		push_error("BaseEnvironment must expose the rendered 3D world state to building snapshot tests.")
		return false
	var world_state: Dictionary = environment.world_state_for_tests()
	var ruin_visibility: Dictionary = world_state.get("ruin_visibility", {})
	var building_visibility: Dictionary = world_state.get("building_visibility", {})
	if int(world_state.get("ruin_count", -1)) != BUILDING_SLOTS.size() or ruin_visibility.size() != BUILDING_SLOTS.size() or building_visibility.size() != BUILDING_SLOTS.size():
		push_error("The 3D platform must expose exactly six typed ruins and six sets of completed-building variants.")
		return false
	for definition_id in BUILDING_SLOTS.keys():
		var slot_id: String = BUILDING_SLOTS[definition_id]
		if not _assert_3d_slot_variant(world_state, slot_id, level):
			push_error("The 3D variant contract failed for %s in %s at level %d." % [definition_id, slot_id, level])
			return false
	return true

func _assert_motion_state_matrix(base: Control) -> bool:
	var expected := {
		"top_left": BuildingPresentationScript.VisualState.ACTIVE_STAFFED,
		"top_center": BuildingPresentationScript.VisualState.ACTIVE_UNSTAFFED,
		"top_right": BuildingPresentationScript.VisualState.ACTIVE_UNSTAFFED,
		"bottom_left": BuildingPresentationScript.VisualState.ACTIVE_UNSTAFFED,
		"center": BuildingPresentationScript.VisualState.BLOCKED,
		"bottom_right": BuildingPresentationScript.VisualState.BLOCKED,
	}
	for slot_id in expected.keys():
		var presentation = base.get_node_or_null("BaseEnvironment/PlatformBoard/Buildings/Presentation_%s" % slot_id)
		if presentation == null or int(presentation.visual_state) != int(expected[slot_id]):
			push_error("Building presentation state mismatch for %s." % slot_id)
			return false
		if presentation.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			push_error("Building presentation must never intercept the persistent slot hitbox: %s." % slot_id)
			return false
	var rebuilt_kitchen = base.get_node("BaseEnvironment/PlatformBoard/Buildings/Presentation_top_center")
	var upgraded_workshop = base.get_node("BaseEnvironment/PlatformBoard/Buildings/Presentation_bottom_left")
	if rebuilt_kitchen.is_blueprint_visible() or upgraded_workshop.is_blueprint_visible():
		push_error("Immediate construction and upgrades must show their active variants without a queued blueprint outline.")
		return false
	var environment = base.get_node_or_null("BaseEnvironment")
	if environment == null or not environment.has_method("world_state_for_tests"):
		push_error("BaseEnvironment must expose the rendered 3D world state to the motion-state matrix.")
		return false
	var world_state: Dictionary = environment.world_state_for_tests()
	var expected_3d_levels := {
		"top_left": 1,
		"top_center": 1,
		"top_right": 1,
		"bottom_left": 2,
		"center": 1,
		"bottom_right": 1,
	}
	for slot_id in expected_3d_levels.keys():
		if not _assert_3d_slot_variant(world_state, slot_id, int(expected_3d_levels[slot_id])):
			return false
	return true

func _assert_3d_slot_variant(world_state: Dictionary, slot_id: String, expected_level: int) -> bool:
	var ruin_visibility: Dictionary = world_state.get("ruin_visibility", {})
	var building_visibility: Dictionary = world_state.get("building_visibility", {})
	if not ruin_visibility.has(slot_id) or not building_visibility.has(slot_id):
		push_error("The 3D world state is missing typed slot %s." % slot_id)
		return false
	var expects_ruin := expected_level == 0
	if bool(ruin_visibility.get(slot_id, false)) != expects_ruin:
		push_error("Slot %s must show %s, but ruin visibility is %s." % [slot_id, "its ruined shell" if expects_ruin else "a completed building", ruin_visibility.get(slot_id, false)])
		return false
	var levels: Dictionary = building_visibility.get(slot_id, {})
	var visible_count := 0
	for candidate_level in range(1, 5):
		if not levels.has(candidate_level):
			push_error("Slot %s must provide a real 3D completed-building variant for level %d." % [slot_id, candidate_level])
			return false
		var is_visible := bool(levels.get(candidate_level, false))
		if is_visible:
			visible_count += 1
		var should_be_visible := expected_level == candidate_level
		if is_visible != should_be_visible:
			push_error("Slot %s has incorrect 3D visibility for level %d: expected %s, got %s." % [slot_id, candidate_level, should_be_visible, is_visible])
			return false
	var expected_visible_count := 0 if expects_ruin else 1
	if visible_count != expected_visible_count:
		push_error("Slot %s must expose exactly %d visible completed-building variant, got %d." % [slot_id, expected_visible_count, visible_count])
		return false
	return true

func _save_snapshot(file_name: String) -> bool:
	var image := get_viewport().get_texture().get_image()
	var output_directory := ProjectSettings.globalize_path("user://test_base_snapshots")
	if not DirAccess.dir_exists_absolute(output_directory):
		var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
		if directory_error != OK:
			push_error("Could not create the building snapshot directory. Error: %d" % directory_error)
			get_tree().quit(1)
			return false
	var error := image.save_png(output_directory.path_join(file_name))
	if error != OK:
		push_error("Could not save building snapshot. Error: %d" % error)
		get_tree().quit(1)
		return false
	return true
