extends SceneTree

const GameStateScript := preload("res://scripts/data/GameState.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const DiveSessionStateScript := preload("res://scripts/data/DiveSessionState.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const ExpeditionPreparationSystemScript := preload("res://scripts/base/ExpeditionPreparationSystem.gd")
const EndOfDayResolverScript := preload("res://scripts/base/EndOfDayResolver.gd")
const SectorPersistenceSystemScript := preload("res://scripts/diving/SectorPersistenceSystem.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const WorkPaceSystemScript := preload("res://scripts/base/WorkPaceSystem.gd")

var _failed := false

func _initialize() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(991, DifficultyProfileScript.new())
	var station = _building("station", "diving_station", "bottom_right", 4, [])
	var workshop = _building("workshop", "workshop", "bottom_left", 3, ["mira"])
	workshop.work_pace = WorkPaceSystemScript.WORK_PACE_INTENSE
	state.buildings.assign([station, workshop])
	state.current_day_plan.sync_from_state(state)
	state.current_day_plan.selected_diver_id = "igor"
	state.underwater_world.placed_buoys.append("B-01")

	var preparation = ExpeditionPreparationSystemScript.new()
	var station_definition = ResourceLoader.load("res://data/buildings/diving_station.tres")
	var analysis: Dictionary = preparation.analyze(state, station, station_definition)
	_assert(bool(analysis.ready), "An active level-four station with a selected diver should be ready for a dive.")
	_assert(analysis.entry_points.size() == 2, "A placed buoy should add a second entry point for a level-four station.")
	_assert(str(analysis.entry_point_selection_reason).is_empty(), "Multiple entry points should not report a selection blocker.")
	state.underwater_world.placed_buoys.clear()
	var no_buoy_analysis: Dictionary = preparation.analyze(state, station, station_definition)
	_assert(no_buoy_analysis.entry_points.size() == 1 and no_buoy_analysis.entry_point_selection_reason == "Ustaw boję podczas wyprawy, aby odblokować dodatkowe wejście.", "Station IV without a placed buoy should name the missing buoy as the exact selection blocker.")
	station.level = 1
	var level_one_analysis: Dictionary = preparation.analyze(state, station, station_definition)
	_assert(level_one_analysis.entry_points.size() == 1 and level_one_analysis.entry_point_selection_reason == "Stacja Nurkowa IV odblokowuje wybór wejścia z ustawionych boi.", "A lower-level station should name the Station IV capability requirement.")
	station.level = 4
	var underwater_world = state.underwater_world
	state.underwater_world = null
	var no_world_analysis: Dictionary = preparation.analyze(state, station, station_definition)
	_assert(no_world_analysis.entry_points.is_empty() and no_world_analysis.entry_point_selection_reason == "Brak dostępnego wejścia do wody.", "Missing world data must not masquerade as a missing buoy or station capability.")
	state.underwater_world = underwater_world
	state.underwater_world.placed_buoys.append("B-01")
	_assert(state.current_day_plan.select_expedition_entry("R2-02"), "The buoy entry should be selectable before the plan is locked.")
	var setup = preparation.build_setup(state, station, station_definition)
	_assert(setup != null and setup.start_entry_point == "R2-02", "ExpeditionSetup should freeze the selected buoy landmark.")
	_assert(setup.can_place_buoys and setup.can_start_from_buoy and setup.can_mark_heavy_objects, "Level four should retain buoy placement and unlock buoy starts plus heavy marking.")
	_assert(setup.selected_gear.has("lift_bag") and setup.buoy_charges == 1, "The setup should carry one deployable buoy and the heavy-object marking tool.")

	var session = DiveSessionStateScript.new()
	session.begin(setup)
	session.placed_buoys.append("B-02")
	session.opened_shortcuts.append("SC-01")
	session.activated_fixed_devices.append("junction_j7")
	session.marked_heavy_objects.append("ship_engine_r1")
	session.recovered_backpacks["previous_diver"] = {
		"items": {ResourceIdsScript.SCRAP: 1},
		"gear_ids": [],
		"recovered": false,
	}
	session.recovered_gear_ids.append("diving_lantern_mk2")
	var dropped_loot_id: String = session.next_dropped_loot_id()
	var dropped_loot_record := {
		"persistence_id": dropped_loot_id,
		"world_position": Vector2(8120, 760),
		"landmark_id": "R1-07",
		"items": {
			ResourceIdsScript.FOOD: 1,
			ResourceIdsScript.SCRAP: 2,
		},
		"created_day": setup.day,
		"recovered": false,
	}
	session.dropped_loot_updates[dropped_loot_id] = dropped_loot_record.duplicate(true)
	var pickup_id := "pickup_r1_scrap_01"
	session.collected_world_item_ids.append(pickup_id)
	var result = DiveResultScript.new()
	result.diver_id = "igor"
	result.health_remaining = state.find_survivor("igor").health
	var persistence_system = SectorPersistenceSystemScript.new()
	persistence_system.populate_result(session, result)
	_assert(result.placed_buoys.has("B-02") and result.opened_shortcuts.has("SC-01") and result.activated_fixed_devices.has("junction_j7"), "Session exploration changes should cross the boundary only through DiveResult.")
	_assert(result.recovered_backpacks.has("previous_diver") and result.recovered_gear_ids.has("diving_lantern_mk2"), "Backpack and recovered gear updates should be part of DiveResult.")
	_assert(result.dropped_loot_updates.get(dropped_loot_id, {}) == dropped_loot_record, "Dropped-loot updates should cross the expedition boundary unchanged through DiveResult.")
	_assert(result.collected_world_item_ids.has(pickup_id), "A locally collected freestanding item should cross the boundary only through DiveResult.")
	_assert(not state.underwater_world.collected_items.has(pickup_id), "Collecting a freestanding item must not mutate the campaign before result resolution.")

	state.underwater_world.lost_backpacks["previous_diver"] = {
		"diver_id": "previous_diver",
		"landmark_id": "R1-07",
		"world_position": Vector2(9150, 420),
		"items": {ResourceIdsScript.SCRAP: 4},
		"gear_ids": ["diving_lantern_mk2"],
		"lost_on_day": 1,
		"recovered": false,
	}
	var scrap_before: int = state.resources.get_amount(ResourceIdsScript.SCRAP)
	EndOfDayResolverScript.new().resolve(state, result, false)
	_assert(state.underwater_world.placed_buoys.has("B-02"), "A completed result should persist a newly placed buoy.")
	_assert(state.underwater_world.opened_shortcuts.has("SC-01"), "A completed result should persist an opened shortcut.")
	_assert(state.underwater_world.activated_fixed_devices.has("junction_j7"), "A completed result should persist the activated fixed device.")
	_assert(state.story_flags.junction_j7_active and state.story_flags.junction_j7_activated_day == 1, "Persisted J-7 activation should update typed campaign progress exactly once.")
	_assert(state.underwater_world.recovered_heavy_objects.has("ship_engine_r1"), "A staffed Workshop III should retrieve one marked heavy object.")
	_assert(not state.underwater_world.marked_heavy_objects.has("ship_engine_r1"), "A retrieved heavy object should leave the pending queue.")
	_assert(workshop.work_tension == 0, "Atomic heavy recovery should use the fixed Normal procedure even when the Workshop is set to Intense pace.")
	_assert(state.resources.get_amount(ResourceIdsScript.SCRAP) == scrap_before + 10, "Heavy-object rewards should be applied exactly once from blueprint data.")
	var backpack: Dictionary = state.underwater_world.lost_backpacks["previous_diver"]
	_assert(backpack.get("items", {}).get(ResourceIdsScript.SCRAP, 0) == 1, "Partial backpack recovery should persist only the remaining items.")
	_assert(backpack.get("gear_ids", []).is_empty() and not bool(backpack.get("recovered", true)), "Recovered gear should leave a partially emptied backpack without deleting its remaining loot.")
	_assert(state.diving_equipment.owns("diving_lantern_mk2"), "Recovered personal gear should return to DivingEquipmentState after a safe return.")
	_assert(state.underwater_world.collected_items.has(pickup_id), "A completed result should persist the stable ID of a collected freestanding item.")
	var persisted_dropped_loot: Dictionary = state.underwater_world.dropped_loot_piles.get(dropped_loot_id, {})
	_assert(persisted_dropped_loot.get("world_position", Vector2.ZERO) == Vector2(8120, 760), "A completed result should persist the dropped pile at its exact world position.")
	_assert(persisted_dropped_loot.get("items", {}) == dropped_loot_record["items"], "A completed result should persist the dropped pile's exact recoverable contents.")
	_assert(state.current_phase == GamePhaseScript.Phase.END_DAY_REPORT, "A completed expedition should wait for its report before another expedition is simulated.")
	state.current_phase = GamePhaseScript.Phase.BASE_PLANNING

	var recovered_dropped_result = DiveResultScript.new()
	var recovered_dropped_record: Dictionary = dropped_loot_record.duplicate(true)
	recovered_dropped_record["recovered"] = true
	recovered_dropped_result.dropped_loot_updates[dropped_loot_id] = recovered_dropped_record
	persistence_system.apply_result(state.underwater_world, recovered_dropped_result)
	_assert(not state.underwater_world.dropped_loot_piles.has(dropped_loot_id), "A recovered dropped-loot update should remove the persistent pile record.")

	var empty_dropped_loot_id := "dropped_loot_2_igor_002"
	var empty_test_record := {
		"persistence_id": empty_dropped_loot_id,
		"world_position": Vector2(8240, 810),
		"landmark_id": "R1-07",
		"items": {ResourceIdsScript.PLANKS: 2},
		"created_day": 2,
		"recovered": false,
	}
	var create_empty_test_result = DiveResultScript.new()
	create_empty_test_result.dropped_loot_updates[empty_dropped_loot_id] = empty_test_record
	persistence_system.apply_result(state.underwater_world, create_empty_test_result)
	_assert(state.underwater_world.dropped_loot_piles.has(empty_dropped_loot_id), "A non-empty dropped-loot update should create a persistent pile record.")
	var empty_update_result = DiveResultScript.new()
	empty_update_result.dropped_loot_updates[empty_dropped_loot_id] = {}
	persistence_system.apply_result(state.underwater_world, empty_update_result)
	_assert(not state.underwater_world.dropped_loot_piles.has(empty_dropped_loot_id), "An empty dropped-loot update should remove the persistent pile record.")

	var duplicate_result = DiveResultScript.new()
	duplicate_result.diver_id = "igor"
	duplicate_result.health_remaining = state.find_survivor("igor").health
	duplicate_result.marked_heavy_objects.append("ship_engine_r1")
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 100)
	EndOfDayResolverScript.new().resolve(state, duplicate_result, false)
	_assert(state.resources.get_amount(ResourceIdsScript.SCRAP) == scrap_before + 10, "A recovered heavy object must never pay its reward twice.")

	if _failed:
		quit(1)
		return
	print("Persistent exploration test passed: dropped loot, freestanding pickups, backpack recovery, buoys, entry selection, shortcuts and heavy salvage remain transactional and persistent.")
	quit(0)

func _building(id: String, definition_id: String, slot_id: String, level: int, workers: Array[String]):
	var building = BuildingStateScript.new()
	building.id = id
	building.definition_id = definition_id
	building.slot_id = slot_id
	building.level = level
	building.is_built = true
	building.assigned_survivor_ids.assign(workers)
	return building

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Persistent exploration test failed: " + message)
