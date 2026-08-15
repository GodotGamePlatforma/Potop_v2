extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const PersistentInteractableScript := preload("res://scripts/diving/DivePersistentInteractable.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")

var _failed := false

func _ready() -> void:
	var game = GameRootScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	var campaign_started: bool = game.start_new_campaign("standard", 992, false)
	_assert(campaign_started, "Persistent exploration fixture should start a campaign without persistence.")
	if not campaign_started:
		await _cleanup_game(game)
		get_tree().quit(1)
		return
	await get_tree().process_frame
	game.game_state.tutorial.complete()

	var workshop = BuildingStateScript.new()
	workshop.id = "workshop"
	workshop.definition_id = "workshop"
	workshop.slot_id = "bottom_left"
	workshop.level = 3
	workshop.is_built = true
	workshop.assigned_survivor_ids.assign(["mira"])
	game.game_state.buildings.append(workshop)
	var entry_position: Vector2 = game.game_state.underwater_world.blueprint.get_landmark("R1-00").get("position", Vector2.ZERO)
	game.game_state.underwater_world.lost_backpacks["old_diver"] = {
		"diver_id": "old_diver",
		"landmark_id": "R1-00",
		"world_position": entry_position + Vector2(90, 0),
		"items": {ResourceIdsScript.SCRAP: 2},
		"gear_ids": ["diving_lantern_mk2"],
		"lost_on_day": 1,
		"recovered": false,
	}

	var setup = _make_setup()
	var starting_day: int = game.game_state.day
	game.start_dive(setup)
	await get_tree().process_frame
	await get_tree().physics_frame
	var dive = game.current_scene
	_assert(dive != null and dive.name == "DiveScene", "Persistent exploration flow should enter DiveScene.")
	_assert(dive.dive_map.lost_backpacks.size() == 1, "The live world should instantiate the persisted lost backpack.")

	var buoy = _first_kind(dive.dive_map.persistent_interactables, PersistentInteractableScript.Kind.BUOY, false)
	var shortcut = _first_kind(dive.dive_map.persistent_interactables, PersistentInteractableScript.Kind.SHORTCUT, false)
	var heavy_object = _first_kind(dive.dive_map.persistent_interactables, PersistentInteractableScript.Kind.HEAVY_OBJECT, false)
	_assert(buoy != null and shortcut != null and heavy_object != null, "The live world should expose a buoy anchor, closed shortcut and unmarked heavy object.")
	_assert(buoy.visual_texture() != null and shortcut.visual_texture() != null and heavy_object.visual_texture() != null, "Every live persistent interaction should have a production world sprite.")
	var buoy_id: String = buoy.persistent_id
	var shortcut_id: String = shortcut.persistent_id
	var heavy_object_id: String = heavy_object.persistent_id
	dive._complete_persistent_interaction(buoy)
	dive._complete_persistent_interaction(shortcut)
	dive._complete_persistent_interaction(heavy_object)
	_assert(dive.session.buoy_charges == 0 and dive.session.placed_buoys.has(buoy.persistent_id), "Placing a buoy should consume the one local charge.")
	_assert(dive.session.opened_shortcuts.has(shortcut.persistent_id), "Opening a shortcut should remain local until DiveResult.")
	_assert(dive.session.marked_heavy_objects.has(heavy_object.persistent_id), "Marking a heavy object should remain local until DiveResult.")

	var backpack = dive.dive_map.lost_backpacks[0]
	var backpack_sprite := backpack.get_node_or_null("ContainerSprite") as Sprite2D
	_assert(backpack.visual_texture() != null and backpack.visual_texture().resource_path == "res://assets/diving/interactables/lost_backpack.png" and backpack_sprite != null and backpack_sprite.texture == backpack.visual_texture(), "A lost backpack should use its dedicated recovery sprite.")
	dive._open_container(backpack)
	dive._take_pending_loot()
	_assert(dive.session.carried_items.get(ResourceIdsScript.SCRAP, 0) == 2, "Recovered backpack loot should enter the normal session inventory.")
	_assert(dive.session.recovered_gear_ids.has("diving_lantern_mk2"), "Recovered personal gear should stay local until the dive ends.")
	_assert(not dive.session.opened_containers.has(backpack.container_id) and not dive.session.remaining_container_contents.has(backpack.container_id), "A lost backpack must not leak into the normal container-persistence dictionaries.")
	dive._start_attempt(true)
	_assert(dive.session.placed_buoys.is_empty() and dive.session.opened_shortcuts.is_empty() and dive.session.marked_heavy_objects.is_empty(), "Retry should discard every local persistent-exploration change.")
	_assert(dive.session.recovered_gear_ids.is_empty() and backpack.gear_ids.has("diving_lantern_mk2") and backpack.contents.get(ResourceIdsScript.SCRAP, 0) == 2, "Retry should restore both backpack loot and recovered gear from the campaign record.")
	dive._complete_persistent_interaction(buoy)
	dive._complete_persistent_interaction(shortcut)
	dive._complete_persistent_interaction(heavy_object)
	dive._open_container(backpack)
	dive._take_pending_loot()
	dive.diver.reset_at(backpack.global_position + Vector2(170, 0))
	dive._drop_inventory_amount(ResourceIdsScript.SCRAP, 1)
	_assert(dive.session.carried_items.get(ResourceIdsScript.SCRAP, 0) == 1, "Dropping during a dive should remove only the chosen amount from the carried stack.")
	_assert(dive.dive_map.dropped_loot_piles.size() == 1, "Dropping during a dive should create one physical package in the live world.")
	var dropped_pile = dive.dive_map.dropped_loot_piles[0]
	var dropped_pile_sprite := dropped_pile.get_node_or_null("ContainerSprite") as Sprite2D
	_assert(dropped_pile.visual_texture() != null and dropped_pile.visual_texture().resource_path == "res://assets/diving/interactables/dropped_bundle.png" and dropped_pile_sprite != null and dropped_pile_sprite.texture == dropped_pile.visual_texture(), "Dropped inventory should use a bundle sprite distinct from containers and backpacks.")
	var dropped_pile_id: String = dropped_pile.persistence_id
	var dropped_pile_position: Vector2 = dropped_pile.global_position
	_assert(dropped_pile.contents.get(ResourceIdsScript.SCRAP, 0) == 1 and dive.session.dropped_loot_updates.has(dropped_pile_id), "The local package update should preserve the exact recoverable contents.")
	dive._finish_success()
	await get_tree().process_frame
	await get_tree().process_frame

	var result = game.game_state.last_dive_result
	_assert(game.game_state.day == starting_day + 1, "Persistent exploration should still resolve exactly one day.")
	_assert(result != null and result.placed_buoys.has(buoy_id), "DiveResult should carry the placed buoy.")
	_assert(game.game_state.underwater_world.opened_shortcuts.has(shortcut_id), "The finished dive should persist the opened shortcut.")
	_assert(game.game_state.underwater_world.recovered_heavy_objects.has(heavy_object_id), "Workshop III should retrieve the marked heavy object during day resolution.")
	_assert(bool(game.game_state.underwater_world.lost_backpacks["old_diver"].get("recovered", false)), "A fully emptied backpack should remain as a recovered historical record.")
	_assert(game.game_state.diving_equipment.owns("diving_lantern_mk2"), "Safely recovered gear should return to campaign equipment.")
	var persisted_package: Dictionary = game.game_state.underwater_world.dropped_loot_piles.get(dropped_pile_id, {})
	_assert(persisted_package.get("items", {}).get(ResourceIdsScript.SCRAP, 0) == 1, "A package left behind on a completed expedition should persist into the campaign world.")
	_assert(persisted_package.get("world_position", Vector2.ZERO) == dropped_pile_position, "A persisted package should retain its exact navigable world position.")
	_assert(game.game_state.current_phase == GamePhaseScript.Phase.END_DAY_REPORT, "A later expedition must remain blocked until the completed day's report is acknowledged.")
	_assert(game.acknowledge_day_report(), "The persistent-exploration flow should explicitly acknowledge the completed day's report.")
	await get_tree().process_frame

	var recovery_setup = _make_setup(game.game_state.day)
	game.start_dive(recovery_setup)
	await get_tree().process_frame
	await get_tree().physics_frame
	var recovery_dive = game.current_scene
	_assert(recovery_dive != null and recovery_dive.name == "DiveScene", "A later expedition should enter the live world normally.")
	var recovered_pile = _find_dropped_pile(recovery_dive.dive_map.dropped_loot_piles, dropped_pile_id)
	_assert(recovered_pile != null and recovered_pile.contents.get(ResourceIdsScript.SCRAP, 0) == 1, "A package left on an earlier expedition should be instantiated and recoverable later.")
	_assert(recovered_pile.global_position == dropped_pile_position, "The later expedition should restore the package at the same world position.")
	recovery_dive._open_container(recovered_pile)
	recovery_dive._take_pending_amount(ResourceIdsScript.SCRAP, 1)
	_assert(recovery_dive.session.carried_items.get(ResourceIdsScript.SCRAP, 0) == 1 and recovered_pile.opened, "Taking the package should return its item to the normal backpack inventory.")
	recovery_dive._finish_success()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(not game.game_state.underwater_world.dropped_loot_piles.has(dropped_pile_id), "A fully recovered package should be removed from persistent world state after the later expedition resolves.")

	if not _failed:
		print("Persistent exploration flow test passed: live interactions and recoverable dropped packages cross DiveResult and resolve into the campaign exactly once.")
	await _cleanup_game(game)
	get_tree().quit(1 if _failed else 0)

func _make_setup(day: int = 1):
	var setup = ExpeditionSetupScript.new()
	setup.diver_id = "igor"
	setup.diver_display_name = "Igor Sowa"
	setup.day = day
	setup.diver_health = 100
	setup.diver_health_capacity = 100
	setup.oxygen_capacity = 120.0
	setup.backpack_capacity = 6
	setup.diver_carry_capacity = 18.0
	setup.item_weights = {ResourceIdsScript.SCRAP: 1.5}
	setup.start_entry_point = "R1-00"
	setup.target_sector = "R1-00"
	setup.selected_gear.assign(["knife", "crowbar", "repair_kit", "lift_bag", "diving_lantern_mk1"])
	setup.equipped_gear = {"light": "diving_lantern_mk1"}
	setup.can_place_buoys = true
	setup.can_start_from_buoy = true
	setup.can_mark_heavy_objects = true
	setup.buoy_charges = 1
	return setup

func _first_kind(interactables: Array[DivePersistentInteractable], kind: int, require_completed: bool):
	for interactable in interactables:
		if interactable.kind == kind and interactable.completed == require_completed:
			return interactable
	return null

func _find_dropped_pile(piles: Array[DiveDroppedLoot], persistence_id: String):
	for pile in piles:
		if pile.persistence_id == persistence_id:
			return pile
	return null

func _cleanup_game(game) -> void:
	if game == null:
		return
	game.show_main_menu()
	await get_tree().process_frame
	await get_tree().process_frame
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Persistent exploration flow test failed: " + message)
