extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")

var _failed := false

func _ready() -> void:
	var game = GameRootScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	_assert(game.get_difficulty_names().has("Niestandardowy"), "Custom difficulty should be exposed now that its editor exists.")
	_assert(not game.start_new_campaign("missing_profile_id", 990, false), "An unknown stable difficulty ID must fail instead of silently starting Standard.")
	game.start_new_campaign("standard", 991, false)
	await get_tree().process_frame
	game.game_state.tutorial.complete()

	var setup = _make_setup()
	var starting_day: int = game.game_state.day
	game.start_dive(setup)
	await get_tree().process_frame
	await get_tree().process_frame
	var dive = game.current_scene
	_assert(dive != null and dive.name == "DiveScene", "Risk flow should start in DiveScene.")
	_assert(dive.dive_map.threats.size() == 1, "The continuous world should instantiate the data-driven first-biome threat.")
	_assert(dive.session.light_enabled and dive.diver_light.enabled, "An equipped Lantern I should start the active attempt switched on.")
	dive._update_ui()
	_assert(dive._hud_dock.light_label.text.contains("WŁ.") and dive._hud_dock.light_label.text.contains("[F]"), "The live HUD must expose the real on-state and current light-toggle binding.")
	var shallow_ambient: Color = dive.ambient_darkness.color
	var original_position: Vector2 = dive.diver.global_position
	dive.diver.global_position = Vector2(5813.0, 5800.0)
	dive._update_environment_lighting()
	var deep_ambient: Color = dive.ambient_darkness.color
	_assert(_luminance(shallow_ambient) > _luminance(deep_ambient), "The live world must become darker when the diver moves from the first region to deep water.")
	dive.diver.global_position = original_position
	dive._update_environment_lighting()
	dive._toggle_diver_light()
	_assert(not dive.session.light_enabled and not dive.diver_light.enabled, "The live light toggle must switch both session state and PointLight2D off.")
	dive._toggle_diver_light()
	_assert(dive.session.light_enabled and dive.diver_light.enabled, "The live light toggle must switch both session state and PointLight2D back on.")
	var equipped_light_id := str(setup.equipped_gear.get("light", ""))
	setup.equipped_gear.erase("light")
	dive.session.light_enabled = true
	dive._configure_lighting()
	_assert(dive._equipped_light_definition == null and not dive.session.light_enabled and not dive.diver_light.enabled, "A setup without an equipped light must not receive the controller's former Lantern I fallback.")
	dive._toggle_diver_light()
	_assert(not dive.session.light_enabled and "Nie wyposażono latarni" in dive._status_message, "Trying to toggle without equipped light must keep it off and explain the required preparation.")
	setup.equipped_gear["light"] = equipped_light_id
	dive.session.light_enabled = true
	dive._configure_lighting()

	var risky_container = null
	for container in dive.dive_map.containers:
		if container.container_id == "tutorial_service_locker":
			risky_container = container
			break
	_assert(risky_container != null and risky_container.required_tool == "crowbar", "The optional locker should require the crowbar in the live scene.")
	dive.diver.reset_at(risky_container.global_position)
	dive._open_container(risky_container)
	_assert(dive.session.noise_events.has("pry") and dive.session.noise_level > 0.0, "Prying the live container should emit local session noise.")
	dive._leave_pending_loot()

	var threat = dive.dive_map.threats[0]
	threat.reset_attempt()
	threat.global_position = dive.diver.global_position + Vector2(12, 0)
	dive.session.noise_level = 0.0
	dive.session.last_noise_position = Vector2(-10000, -10000)
	dive._toggle_diver_light()
	dive._risk_runtime.advance(dive.session, setup, dive.dive_map.threats, dive.diver.global_position, 20.0, false, 1.0, dive._is_diver_light_active())
	var unlit_alert: float = threat.alert_level
	dive._toggle_diver_light()
	dive._risk_runtime.advance(dive.session, setup, dive.dive_map.threats, dive.diver.global_position, 20.0, false, 1.0, dive._is_diver_light_active())
	_assert(is_zero_approx(unlit_alert) and threat.alert_level > unlit_alert, "Only the real on-state may create the threat's light stimulus.")
	threat.global_position = dive.diver.global_position + Vector2(12, 0)
	dive.session.noise_level = 100.0
	dive.session.last_noise_position = dive.diver.global_position
	var health_before: int = dive.session.health
	for index in range(4):
		dive._risk_runtime.advance(dive.session, setup, dive.dive_map.threats, dive.diver.global_position, 80.0, false, 1.0, true)
	_assert(dive.session.health < health_before and dive.session.suit_condition < 100, "An alerted live threat should damage health and suit state.")

	var damaged_condition: int = dive.session.suit_condition
	dive._attempt_suit_repair()
	_assert(dive.session.suit_condition > damaged_condition and dive.session.repair_kit_uses == 1, "R should be backed by the one-use contextual repair action.")
	dive.session.cold_exposure = 75.0
	dive._finish_success()
	await get_tree().process_frame
	await get_tree().process_frame

	var result = game.game_state.last_dive_result
	_assert(game.game_state.day == starting_day + 1, "A risk-bearing safe return should still resolve exactly one day.")
	_assert(result != null and result.repair_kit_uses == 1, "DiveResult should retain the repair-kit cost.")
	_assert(result.noise_events.has("pry") and result.noise_events.has("repair"), "DiveResult should retain contextual action noise.")
	_assert(result.risk_events.has("threat_attack:parking_noise_eel"), "DiveResult should identify the threat that attacked.")
	_assert(result.diver_injuries.has("puncture_wound") and result.diver_injuries.has("hypothermia"), "DiveResult should carry attack and cold injuries.")
	var igor = game.game_state.find_survivor("igor")
	_assert(igor.injury_states.has("puncture_wound") and igor.injury_states.has("hypothermia"), "EndOfDayResolver should apply local dive injuries to the campaign only after return.")
	_assert(_contains_fragment(game.game_state.last_end_day_report.warnings, "podwodne zagrożenie"), "The end-day report should explain the threat attack.")
	_assert(_contains_fragment(game.game_state.last_end_day_report.warnings, "wychłod"), "The end-day report should explain the cold consequence.")

	if _failed:
		await _cleanup_game(game)
		get_tree().quit(1)
		return
	print("Dive risk flow test passed: live tools, noise, threat, repair, result and day report work end to end.")
	await _cleanup_game(game)
	get_tree().quit(0)

func _cleanup_game(game) -> void:
	game.show_main_menu()
	await get_tree().process_frame
	await get_tree().process_frame
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _make_setup():
	var setup = ExpeditionSetupScript.new()
	setup.diver_id = "igor"
	setup.diver_display_name = "Igor Sowa"
	setup.day = 1
	setup.diver_health = 100
	setup.diver_health_capacity = 100
	setup.oxygen_capacity = 100.0
	setup.backpack_capacity = 6
	setup.diver_carry_capacity = 18.0
	setup.item_weights = {
		ResourceIdsScript.FOOD: 1.0,
		ResourceIdsScript.PLANKS: 1.2,
		ResourceIdsScript.SCRAP: 1.5,
	}
	setup.target_sector = "dead_city_rooftops_001"
	setup.selected_objective = "basic_scavenge"
	setup.selected_gear.assign(["knife", "crowbar", "repair_kit", "diving_lantern_mk1"])
	setup.equipped_gear = {"light": "diving_lantern_mk1"}
	setup.suit_quality = 1
	setup.difficulty_modifiers = {
		"oxygen_use_multiplier": 1.0,
		"suit_damage_multiplier": 1.0,
		"cold_rate_multiplier": 1.0,
		"threat_aggression_multiplier": 1.0,
		"current_strength_multiplier": 1.0,
		"noise_range_multiplier": 1.0,
	}
	return setup

func _contains_fragment(values: Array[String], fragment: String) -> bool:
	for value in values:
		if fragment.to_lower() in value.to_lower():
			return true
	return false

func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Dive risk flow test failed: " + message)
