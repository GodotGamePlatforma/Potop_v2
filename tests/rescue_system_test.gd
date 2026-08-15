extends SceneTree

const GameStateScript := preload("res://scripts/data/GameState.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const DiveSessionStateScript := preload("res://scripts/data/DiveSessionState.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const DiveRescueSurvivorScript := preload("res://scripts/diving/DiveRescueSurvivor.gd")
const RescueSystemScript := preload("res://scripts/diving/RescueSystem.gd")
const SectorPersistenceSystemScript := preload("res://scripts/diving/SectorPersistenceSystem.gd")
const EndOfDayResolverScript := preload("res://scripts/base/EndOfDayResolver.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const GameDatabaseScript := preload("res://scripts/core/GameDatabase.gd")

var _failed := false

func _initialize() -> void:
	var definition = ResourceLoader.load("res://data/survivors/leon_wrona.tres")
	_assert(definition != null and definition.is_valid(), "The first rescue definition should be valid and data-driven.")
	var database = GameDatabaseScript.new()
	database.load_definitions()
	_assert(database != null and database.rescue_encounters.has("leon_wrona"), "GameDatabase should load rescue definitions.")

	var setup = _make_setup()
	var session = DiveSessionStateScript.new()
	session.begin(setup)
	_assert(session.add_item(ResourceIdsScript.MEDS_CHEMICALS, 2) == 2, "Medicine should enter the normal backpack before stabilization.")
	var encounter = DiveRescueSurvivorScript.new()
	encounter.configure("rescue_hotel_leon", definition)
	encounter.mark_freed()
	var rescue = RescueSystemScript.new()
	var tow: Dictionary = rescue.begin_tow(session, encounter, true)
	_assert(bool(tow.get("success", false)), "A freed survivor should be towable after stabilization.")
	_assert(session.carried_items.get(ResourceIdsScript.MEDS_CHEMICALS, 0) == 1, "Stabilization should consume medicine from real carried loot.")
	_assert(session.towed_survivor != null and session.towed_survivor.health == definition.stabilized_health, "The local session should carry the stabilized survivor snapshot.")
	_assert(session.towed_survivor.status == SurvivorStateScript.Status.INJURED and session.towed_survivor.injury_states.has("rescue_recovery"), "A stabilized rescue should still arrive injured.")
	_assert(rescue.movement_multiplier(session, definition) == definition.stabilized_movement_multiplier, "Towing should reduce movement according to the definition.")
	_assert(rescue.oxygen_multiplier(session, definition) == definition.stabilized_oxygen_multiplier, "Towing should increase oxygen use according to the definition.")

	var result = DiveResultScript.new()
	result.diver_id = "igor"
	result.health_remaining = 100
	result.oxygen_remaining = 30.0
	result.collected_items = session.carried_items.duplicate(true)
	rescue.populate_success_result(session, result)
	_assert(result.rescued_survivors.size() == 1, "A safe return should transfer the survivor through DiveResult.")
	_assert(result.rescue_outcomes.get("rescue_hotel_leon", {}).get("status", "") == "rescued", "A safe return should carry a stable persistent outcome.")

	var world_only_state = GameStateScript.new()
	world_only_state.setup_new_campaign(431, DifficultyProfileScript.new())
	SectorPersistenceSystemScript.new().apply_result(world_only_state.underwater_world, result)
	_assert(world_only_state.find_survivor("leon") == null, "Applying world persistence alone must not mutate the base population.")
	_assert(world_only_state.underwater_world.rescued_or_dead_survivors.has("rescue_hotel_leon"), "The rescue outcome should persist in WorldDelta.")

	var state = GameStateScript.new()
	state.setup_new_campaign(432, DifficultyProfileScript.new())
	state.resources.set_amount(ResourceIdsScript.FOOD, 100)
	state.resources.set_amount(ResourceIdsScript.MEDS_CHEMICALS, 1)
	state.resources.set_amount(ResourceIdsScript.HOPE, 55)
	state.buildings.append(_building("infirmary", "infirmary", "center", 1, ["anka"]))
	var food_before: int = state.resources.get_amount(ResourceIdsScript.FOOD)
	var report = EndOfDayResolverScript.new().resolve(state, result, false)
	var leon = state.find_survivor("leon")
	_assert(leon != null and state.get_alive_survivors().size() == 4, "The rescued person should join the base exactly once.")
	_assert(leon.health == 60 and leon.injury_states.is_empty() and leon.status == SurvivorStateScript.Status.AVAILABLE, "A staffed infirmary should prioritize, heal and release the stabilized rescue patient.")
	_assert(state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS) == 1, "One returned medicine and one infirmary treatment should balance to the starting stock.")
	_assert(state.resources.get_amount(ResourceIdsScript.FOOD) == food_before - 16, "The rescued adult should consume a full ration on the arrival day.")
	_assert(state.resources.get_amount(ResourceIdsScript.HOPE) == 65, "Return, loot and rescue should raise Hope, while the missing fourth shelter place should offset part of the gain.")
	_assert(_report_contains(report.entries, "Uratowano Leon Wrona") and _report_contains(report.warnings, "Brakuje suchego miejsca"), "The report should explain both the rescue and its shelter consequence.")

	var critical_session = DiveSessionStateScript.new()
	critical_session.begin(setup)
	var critical_encounter = DiveRescueSurvivorScript.new()
	critical_encounter.configure("rescue_hotel_leon", definition)
	critical_encounter.mark_freed()
	var critical_tow: Dictionary = rescue.begin_tow(critical_session, critical_encounter, false)
	_assert(bool(critical_tow.get("success", false)), "Rescue without medicine should remain executable.")
	_assert(critical_session.towed_survivor.health == definition.unstabilized_health and critical_session.towed_survivor.injury_states.has("critical_rescue"), "Unstabilized towing should create a critical arrival state.")
	_assert(rescue.movement_multiplier(critical_session, definition) < rescue.movement_multiplier(session, definition), "Unstabilized towing should be slower than stabilized towing.")
	_assert(rescue.oxygen_multiplier(critical_session, definition) > rescue.oxygen_multiplier(session, definition), "Unstabilized towing should consume more oxygen.")
	var death_result = DiveResultScript.new()
	rescue.populate_death_result(critical_session, death_result)
	_assert(death_result.rescued_survivors.is_empty() and death_result.rescue_outcomes.get("rescue_hotel_leon", {}).get("status", "") == "dead", "Losing a dive while towing should never add the survivor to the base.")

	critical_session.reset_attempt()
	_assert(critical_session.towed_survivor == null and critical_session.rescued_survivor_ids.is_empty(), "Retry should discard the entire local rescue attempt.")

	encounter.free()
	critical_encounter.free()
	database.free()
	if _failed:
		quit(1)
		return
	print("Rescue system test passed: stabilization, towing costs, death, persistence, infirmary, food, shelter, Hope and reports are connected.")
	quit(0)

func _make_setup():
	var setup = ExpeditionSetupScript.new()
	setup.diver_id = "igor"
	setup.diver_health = 100
	setup.diver_health_capacity = 100
	setup.oxygen_capacity = 120.0
	setup.backpack_capacity = 6
	setup.diver_carry_capacity = 18.0
	setup.item_weights = {ResourceIdsScript.MEDS_CHEMICALS: 0.7}
	setup.selected_gear.assign(["knife", "crowbar", "repair_kit", "diving_lantern_mk1"])
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
	push_error("Rescue system test failed: " + message)
