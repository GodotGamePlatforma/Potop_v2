extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")

const CAPTURES := [
	{
		"file_name": "tutorial_cable_entry_market_high.png",
		"position": Vector2(5350.0, 620.0),
		"quality": "high",
		"reduced_motion": false,
	},
	{
		"file_name": "tutorial_cable_workshop_blockage_high.png",
		"position": Vector2(2640.0, 930.0),
		"quality": "high",
		"reduced_motion": false,
	},
	{
		"file_name": "tutorial_cable_workshop_blockage_low.png",
		"position": Vector2(2640.0, 930.0),
		"quality": "low",
		"reduced_motion": false,
	},
	{
		"file_name": "tutorial_cable_workshop_blockage_reduced.png",
		"position": Vector2(2640.0, 930.0),
		"quality": "high",
		"reduced_motion": true,
	},
]


func _ready() -> void:
	var game = GameRootScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	if not game.start_new_campaign("standard", 72_013, false):
		push_error("Nie udało się utworzyć kampanii do migawki kabla tutoriala.")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	game.game_state.day = 3
	game.game_state.prepare_weather_for_day(3)
	game.game_state.begin_new_day_plan()
	game.game_state.tutorial.step = TutorialStateScript.Step.START_FINAL_DIVE
	game.game_state.story_flags.rescue_knife_unlocked = true

	var setup = ExpeditionSetupScript.new()
	setup.diver_id = "igor"
	setup.diver_display_name = "Igor Sowa"
	setup.day = 3
	setup.oxygen_capacity = 100.0
	setup.diver_health = 100
	setup.diver_health_capacity = 100
	setup.backpack_capacity = 6
	setup.diver_carry_capacity = 24.0
	setup.target_sector = "dead_city_rooftops_001"
	setup.start_entry_point = "R1-00"
	setup.selected_objective = "visual_regression"
	setup.tutorial_mode = true
	setup.tutorial_baseline_step = TutorialStateScript.Step.START_FINAL_DIVE
	setup.selected_gear.assign(["knife", "crowbar", "repair_kit", "diving_lantern_mk1"])
	setup.equipped_gear = {"light": "diving_lantern_mk1"}
	setup.difficulty_modifiers = {
		"oxygen_use_multiplier": 1.0,
		"suit_damage_multiplier": 1.0,
		"cold_rate_multiplier": 1.0,
		"threat_aggression_multiplier": 1.0,
		"current_strength_multiplier": 1.0,
		"noise_range_multiplier": 1.0,
	}
	game.start_dive(setup)
	await get_tree().process_frame
	await get_tree().process_frame
	var dive = game.current_scene
	if dive == null or dive.name != "DiveScene":
		push_error("Migawka kabla wymaga produkcyjnej DiveScene.")
		get_tree().quit(1)
		return

	for capture in CAPTURES:
		if not await _capture(dive, capture):
			get_tree().quit(1)
			return

	var blockage = _find_persistent_interactable(dive, "SC-01")
	if blockage == null:
		push_error("Migawka kabla nie znalazła SC-01 w runtime.")
		get_tree().quit(1)
		return
	if not await _capture(dive, {
		"file_name": "tutorial_cable_sc01_j7_closed_high.png",
		"position": Vector2(2350.0, 1080.0),
		"quality": "high",
		"reduced_motion": false,
	}):
		get_tree().quit(1)
		return
	dive._complete_persistent_interaction(blockage)
	dive._update_ui()
	if not await _capture(dive, {
		"file_name": "tutorial_cable_workshop_blockage_open_high.png",
		"position": Vector2(2640.0, 930.0),
		"quality": "high",
		"reduced_motion": false,
	}):
		get_tree().quit(1)
		return
	if not await _capture(dive, {
		"file_name": "tutorial_cable_sc01_j7_open_high.png",
		"position": Vector2(2350.0, 1080.0),
		"quality": "high",
		"reduced_motion": false,
	}):
		get_tree().quit(1)
		return

	print("Tutorial cable route snapshots saved: tutorial HUD, high/low/reduced motion and matched closed/open frames.")
	get_tree().quit(0)


func _capture(dive, capture: Dictionary) -> bool:
	var at: Vector2 = dive.dive_map.nearest_navigable_position(capture.get("position", Vector2.ZERO))
	dive.set_graphics_quality(str(capture.get("quality", "high")))
	dive.set_reduced_motion(bool(capture.get("reduced_motion", false)))
	dive.session.light_enabled = false
	dive._apply_diver_light_state()
	dive.diver.reset_at(at)
	dive.dive_map.update_streaming(at, true, dive._streaming_visible_half_extent())
	var terrain_renderer := dive.dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/TerrainRenderer") as UnderwaterTerrainRenderer
	if terrain_renderer != null:
		terrain_renderer.auto_advance_animation = false
		terrain_renderer.set_anim_time(4.0)
	if dive._underwater_environment != null:
		dive._underwater_environment.set_visual_time_for_tests(4.0)
	dive._update_current_presentation(0.0, true)
	dive._update_environment_lighting(0.0)
	dive._update_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	await _settle_visual_chunks(dive)
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Migawka kabla zwróciła pusty obraz.")
		return false
	var output_path := ProjectSettings.globalize_path("res://tmp/%s" % str(capture.get("file_name", "tutorial_cable.png")))
	var save_error := image.save_png(output_path)
	if save_error != OK:
		push_error("Nie udało się zapisać migawki kabla: %s." % output_path)
		return false
	return true


func _settle_visual_chunks(dive) -> void:
	var streamer: Node = dive.dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/VisualChunkStreamer")
	if streamer == null:
		return
	for _frame in range(180):
		var pending: Array[String] = streamer.pending_chunk_keys()
		var desired: Array[String] = streamer.desired_chunk_keys()
		var loaded: Array[String] = streamer.loaded_chunk_keys()
		if pending.is_empty() and loaded.size() >= desired.size():
			return
		await get_tree().process_frame
	push_error("Chunki wizualne nie ustabilizowały się przed migawką kabla.")


func _find_persistent_interactable(dive, persistent_id: String):
	for target in dive.dive_map.persistent_interactables:
		if target.persistent_id == persistent_id:
			return target
	return null
