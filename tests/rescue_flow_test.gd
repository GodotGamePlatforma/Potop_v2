extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const DiveRescueSurvivorScript := preload("res://scripts/diving/DiveRescueSurvivor.gd")

var _failed := false

func _ready() -> void:
	var game = GameRootScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	var campaign_started: bool = game.start_new_campaign("standard", 433, false)
	_assert(campaign_started, "Rescue fixture should start a campaign without persistence.")
	if not campaign_started:
		await _cleanup_game(game)
		get_tree().quit(1)
		return
	await get_tree().process_frame
	game.game_state.tutorial.complete()
	game.game_state.resources.set_amount(ResourceIdsScript.FOOD, 100)
	game.game_state.resources.set_amount(ResourceIdsScript.MEDS_CHEMICALS, 1)
	game.game_state.buildings.append(_building("infirmary", "infirmary", "center", 1, ["anka"]))

	var starting_day: int = game.game_state.day
	game.start_dive(_make_setup())
	await get_tree().process_frame
	await get_tree().physics_frame
	var dive = game.current_scene
	_assert(dive != null and dive.name == "DiveScene", "The live rescue flow should enter DiveScene.")
	_assert(dive.dive_map.rescue_survivors.size() == 1, "The generated world should instantiate the unresolved hotel survivor.")
	var encounter = dive.dive_map.rescue_survivors[0]
	_assert(encounter.stage == DiveRescueSurvivorScript.Stage.TRAPPED, "The first encounter should begin trapped.")
	var rescue_sprite := encounter.get_node_or_null("RescueSprite") as Sprite2D
	var trapped_texture: Texture2D = encounter.visual_texture()
	_assert(trapped_texture != null and trapped_texture.resource_path == "res://assets/diving/rescue/leon_trapped.png", "The trapped encounter should use Leon's production trapped-state sprite.")
	_assert(rescue_sprite != null and rescue_sprite.texture == trapped_texture, "The encounter should attach the trapped texture to RescueSprite.")

	dive.session.add_item(ResourceIdsScript.MEDS_CHEMICALS, 1)
	dive._complete_rescue_interaction(encounter)
	_assert(encounter.stage == DiveRescueSurvivorScript.Stage.FREED and dive._rescue_overlay.visible, "Freeing should open an explicit rescue decision in the live UI.")
	var freed_texture: Texture2D = encounter.visual_texture()
	_assert(freed_texture != null and freed_texture.resource_path == "res://assets/diving/rescue/leon_freed.png" and freed_texture != trapped_texture, "Freeing Leon should switch to a distinct production sprite.")
	_assert(rescue_sprite.texture == freed_texture, "RescueSprite should refresh immediately when Leon is freed.")
	dive._leave_pending_rescue()
	_assert(encounter.can_interact() and not dive._rescue_overlay.visible, "Leaving the decision should keep the survivor available without changing the campaign.")
	dive._complete_rescue_interaction(encounter)
	dive._begin_pending_rescue(true)
	_assert(dive.session.towed_survivor != null and encounter.stage == DiveRescueSurvivorScript.Stage.TOWING, "The stabilized survivor should physically enter towing state.")
	var towing_texture: Texture2D = encounter.visual_texture()
	_assert(towing_texture != null and towing_texture.resource_path == "res://assets/diving/rescue/leon_towing.png" and towing_texture != freed_texture, "Beginning the tow should switch Leon to the compact towing sprite.")
	_assert(rescue_sprite.texture == towing_texture, "RescueSprite should refresh immediately when towing begins.")
	_assert(dive._objective_text().contains("RATUNEK: Leon Wrona") and dive._objective_text().contains("narzędzia zablokowane"), "The HUD objective should explain the active rescue costs and only valid goal.")

	dive.session.suit_condition = 40
	var repair_charge_before: int = dive.session.repair_kit_charges
	dive._attempt_suit_repair()
	_assert(dive.session.suit_condition == 40 and dive.session.repair_kit_charges == repair_charge_before, "Tool use should be blocked while both hands are committed to towing.")
	dive.diver.global_position += Vector2(120, 0)
	var tow_target: Vector2 = dive.diver.global_position + Vector2(-58, 28)
	var tow_distance_before: float = encounter.global_position.distance_to(tow_target)
	for frame in range(5):
		await get_tree().process_frame
	_assert(encounter.global_position.distance_to(tow_target) < tow_distance_before, "The rescued person should visibly follow the diver during towing.")

	dive._start_attempt(true)
	_assert(dive.session.towed_survivor == null and encounter.stage == DiveRescueSurvivorScript.Stage.TRAPPED, "Attempt reset should restore the encounter and remove all local rescue state.")
	_assert(encounter.required_tool == "crowbar" and is_equal_approx(encounter.interaction_seconds, float(encounter.definition.freeing_seconds)), "Retry should restore Leon's authored crowbar requirement and freeing time.")
	_assert(rescue_sprite.texture == trapped_texture, "Retry should restore Leon's trapped-state sprite.")
	_assert(not game.game_state.underwater_world.rescued_or_dead_survivors.has("rescue_hotel_leon"), "Retry must not leak the rescue into the campaign.")
	dive.session.add_item(ResourceIdsScript.MEDS_CHEMICALS, 1)
	dive._complete_rescue_interaction(encounter)
	dive._begin_pending_rescue(true)
	dive._finish_success()
	await get_tree().process_frame
	await get_tree().process_frame

	var result = game.game_state.last_dive_result
	var leon = game.game_state.find_survivor("leon")
	_assert(game.game_state.day == starting_day + 1, "The successful rescue should resolve exactly one campaign day.")
	_assert(result != null and result.rescued_survivors.size() == 1, "The live flow should cross the module boundary through DiveResult.")
	_assert(leon != null and leon.health == 60 and leon.injury_states.is_empty(), "The rescued resident should be treated by the staffed infirmary after arrival.")
	_assert(game.game_state.underwater_world.rescued_or_dead_survivors.get("rescue_hotel_leon", {}).get("status", "") == "rescued", "The live encounter must disappear permanently after a successful return.")
	_assert(_report_contains(game.game_state.last_end_day_report.entries, "Uratowano Leon Wrona"), "The end-of-day report should name the rescued resident.")

	if _failed:
		await _cleanup_game(game)
		get_tree().quit(1)
		return
	print("Rescue flow test passed: freeing, choice UI, towing, tool lock, retry, return and base consequences work end to end.")
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
	setup.diver_health = 100
	setup.diver_health_capacity = 100
	setup.oxygen_capacity = 180.0
	setup.backpack_capacity = 6
	setup.diver_carry_capacity = 18.0
	setup.item_weights = {ResourceIdsScript.MEDS_CHEMICALS: 0.7}
	setup.start_entry_point = "R1-03"
	setup.target_sector = "R1-03"
	setup.selected_gear.assign(["knife", "crowbar", "repair_kit", "diving_lantern_mk1"])
	setup.equipped_gear = {"light": "diving_lantern_mk1"}
	return setup

func _building(id: String, definition_id: String, slot_id: String, level: int, workers: Array[String]):
	var building = BuildingStateScript.new()
	building.id = id
	building.definition_id = definition_id
	building.slot_id = slot_id
	building.level = level
	building.is_built = true
	building.assigned_survivor_ids.assign(workers)
	return building

func _report_contains(lines: Array[String], fragment: String) -> bool:
	for line in lines:
		if line.contains(fragment):
			return true
	return false

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Rescue flow test failed: " + message)
