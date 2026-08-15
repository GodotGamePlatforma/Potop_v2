extends SceneTree

const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const EndOfDayResolverScript := preload("res://scripts/base/EndOfDayResolver.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const GameDatabaseScript := preload("res://scripts/core/GameDatabase.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")

func _initialize() -> void:
	var database = GameDatabaseScript.new()
	database.load_definitions()
	if not database.is_valid():
		push_error("Smoke test failed: GameDatabase validation found: %s" % "; ".join(database.validation_errors))
		quit(1)
		return
	database.difficulty_profiles.clear()
	database.buildings.clear()
	database.items.clear()
	database.diving_gear.clear()
	database.workshop_recipes.clear()
	database.free()
	var state = GameStateScript.new()
	var profile = DifficultyProfileScript.new()
	state.setup_new_campaign(123, profile)

	var starting_day = state.day
	var starting_food = state.resources.get_amount(ResourceIdsScript.FOOD)

	var result = DiveResultScript.new()
	result.diver_id = "igor"
	result.returned_alive = true
	result.oxygen_remaining = 42.0
	result.add_item(ResourceIdsScript.FOOD, 8)
	result.add_item(ResourceIdsScript.PLANKS, 4)

	var resolved_plan = state.current_day_plan
	var report = EndOfDayResolverScript.new().resolve(state, result, false)

	if state.day != starting_day + 1:
		push_error("Smoke test failed: day did not advance.")
		quit(1)
		return

	if state.last_morning_report == null or report == null:
		push_error("Smoke test failed: reports were not generated.")
		quit(1)
		return
	if report.day != starting_day or not report.includes_dive or state.current_phase != GamePhaseScript.Phase.END_DAY_REPORT:
		push_error("Smoke test failed: completed-day report metadata or pending report phase is invalid.")
		quit(1)
		return

	if state.current_day_plan == null or state.current_day_plan.day != state.day or state.current_day_plan.locked:
		push_error("Smoke test failed: a fresh editable day plan was not created for the next day.")
		quit(1)
		return
	if resolved_plan == null or not resolved_plan.locked:
		push_error("Smoke test failed: the resolved day plan was not locked before simulation.")
		quit(1)
		return

	if state.resources.get_amount(ResourceIdsScript.FOOD) >= starting_food + 8:
		push_error("Smoke test failed: rations were not consumed.")
		quit(1)
		return

	print("Smoke test passed: day advanced, dive loot applied, rations resolved.")
	quit(0)
