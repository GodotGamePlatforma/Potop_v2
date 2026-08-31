extends SceneTree

const SAMPLE_COUNT := 500
const CRISIS_SAMPLE_COUNT := 150

const GameStateScript := preload("res://scripts/data/GameState.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const WeatherStateScript := preload("res://scripts/data/WeatherState.gd")
const DifficultyDirectorScript := preload("res://scripts/campaign/DifficultyDirector.gd")
const SettlementEventSystemScript := preload("res://base_workbench/systems/SettlementEventSystem.gd")

var _failed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var definitions := _load_event_definitions()
	_assert(definitions.size() == 5, "Symulacja musi obejmować wszystkie pięć autorskich wydarzeń osady.")
	var easy := _simulate_public_profile("res://data/difficulty/easy.tres", definitions)
	var standard := _simulate_public_profile("res://data/difficulty/standard.tres", definitions)
	var hard := _simulate_public_profile("res://data/difficulty/hard.tres", definitions)

	_assert(int(easy.events) < int(standard.events) and int(standard.events) < int(hard.events), "Częstość wydarzeń powinna rosnąć Łagodny < Standard < Surowy w identycznym, stabilnym stanie osady.")
	_assert(int(easy.hardships) < int(standard.hardships) and int(standard.hardships) < int(hard.hardships), "Częstość kart utrudniających powinna rosnąć Łagodny < Standard < Surowy.")
	var easy_help_share := float(easy.helpful) / float(maxi(int(easy.events), 1))
	var hard_help_share := float(hard.helpful) / float(maxi(int(hard.events), 1))
	_assert(easy_help_share > hard_help_share + 0.05, "Łagodny powinien mieć wyraźnie większy udział pomocy wśród rozlosowanych kart niż Surowy.")

	_simulate_crisis_safety(definitions)
	if _failed:
		quit(1)
		return
	print(
		"Difficulty simulation test passed: %d seeds/profile preserve monotonic event pressure (easy %d/%d, standard %d/%d, hard %d/%d) and %d crisis seeds never add hardship." % [
			SAMPLE_COUNT,
			int(easy.events), int(easy.hardships),
			int(standard.events), int(standard.hardships),
			int(hard.events), int(hard.hardships),
			CRISIS_SAMPLE_COUNT,
		]
	)
	quit(0)


func _simulate_public_profile(profile_path: String, definitions: Dictionary) -> Dictionary:
	var profile = ResourceLoader.load(profile_path)
	var state = _stable_state(profile)
	var signature_before := str(state.difficulty_profile.configuration_signature)
	var selector = SettlementEventSystemScript.new()
	var pressure_template = DifficultyDirectorScript.new().build_for_day(state, null, null)
	var result := {"events": 0, "quiet": 0, "helpful": 0, "hardships": 0}
	for sample_index in range(SAMPLE_COUNT):
		var event_id := _roll_once(state, definitions, selector, pressure_template, 30_000 + sample_index)
		if event_id.is_empty():
			result.quiet += 1
			continue
		result.events += 1
		var definition = definitions.get(event_id)
		if str(definition.tone) == "hardship":
			result.hardships += 1
		elif str(definition.tone) in ["relief", "opportunity"]:
			result.helpful += 1
	_assert(int(result.events) + int(result.quiet) == SAMPLE_COUNT, "Każde ziarno musi zakończyć się dokładnie kartą albo spokojnym porankiem.")
	_assert(str(state.difficulty_profile.configuration_signature) == signature_before and state.difficulty_profile.has_valid_configuration_signature(), "Wielokrotne losowanie nie może zmienić zamrożonego profilu kampanii.")
	return result


func _simulate_crisis_safety(definitions: Dictionary) -> void:
	var profile = ResourceLoader.load("res://data/difficulty/standard.tres")
	var state = _stable_state(profile)
	state.resources.set_amount("food", 1)
	state.resources.set_amount("hope", 10)
	state.resources.set_amount("platform_integrity", 20)
	for survivor in state.survivors:
		survivor.hunger = 90
	var selector = SettlementEventSystemScript.new()
	var pressure_template = DifficultyDirectorScript.new().build_for_day(state, null, null)
	var event_count := 0
	var quiet_count := 0
	for sample_index in range(CRISIS_SAMPLE_COUNT):
		var event_id := _roll_once(state, definitions, selector, pressure_template, 70_000 + sample_index)
		var pressure = state.pressure_state
		_assert(pressure.band == pressure.Band.CRISIS and is_zero_approx(float(pressure.pressure_budget)) and int(pressure.max_event_severity) == 1, "Krytyczne bramki muszą wymuszać CRISIS z zerowym budżetem dodatkowego nacisku.")
		if event_id.is_empty():
			quiet_count += 1
			continue
		event_count += 1
		var definition = definitions.get(event_id)
		_assert(str(definition.tone) in ["relief", "opportunity"], "Osada w CRISIS nie może dostać dodatkowej karty hardship.")
		_assert(int(definition.severity) <= 1 and is_zero_approx(float(definition.pressure_cost)), "Karta w CRISIS musi być małą, bezkosztową pomocą.")
	_assert(event_count > 0 and quiet_count > 0, "CRISIS powinien dopuszczać zarówno małą pomoc, jak i spokojny poranek — bez gwarantowania ratunku.")


func _stable_state(profile):
	var state = GameStateScript.new()
	state.setup_new_campaign(1, profile)
	state.tutorial.complete()
	state.day = 5
	state.resources.set_amount("food", 240)
	state.resources.set_amount("hope", 60)
	state.resources.set_amount("platform_integrity", 100)
	state.resources.set_amount("planks", 40)
	state.resources.set_amount("scrap", 40)
	state.resources.set_amount("meds_chemicals", 6)
	for survivor in state.survivors:
		survivor.status = SurvivorStateScript.Status.AVAILABLE
		survivor.health = survivor.get_max_health()
		survivor.hunger = 0
		survivor.fatigue = 0
		survivor.morale = 55
	var weather = WeatherStateScript.new()
	weather.day = state.day
	weather.condition = WeatherStateScript.Condition.CALM
	state.weather = weather
	state.pending_settlement_event = null
	state.settlement_event_history.clear()
	state.settlement_event_roll_day = 0
	return state


func _roll_once(state, definitions: Dictionary, selector, pressure_template, campaign_seed: int) -> String:
	state.seed = campaign_seed
	state.pending_settlement_event = null
	state.settlement_event_roll_day = 0
	state.pressure_state = pressure_template.duplicate(true)
	var pending = selector.prepare_event_for_day(state, definitions, state.pressure_state)
	if pending == null:
		_assert(state.pressure_state.quiet_morning, "Brak karty musi zostać jawnie zapisany jako spokojny poranek.")
		return ""
	var event_id := str(pending.event_id)
	_assert(state.pressure_state.committed_event_id == event_id and not state.pressure_state.quiet_morning, "Wylosowana karta musi odpowiadać commitowi dziennej migawki presji.")
	_assert(float(state.pressure_state.spent_pressure_budget) <= float(state.pressure_state.pressure_budget) + 0.0001, "Selektor nie może przekroczyć zamrożonego budżetu presji.")
	return event_id


func _load_event_definitions() -> Dictionary:
	var result: Dictionary = {}
	for file_name in [
		"drifting_supply_crates.tres",
		"shared_meal.tres",
		"survivors_on_horizon.tres",
		"torn_mooring.tres",
		"trader_at_dawn.tres",
	]:
		var definition = ResourceLoader.load("res://base_workbench/data/events/%s" % file_name)
		if definition != null:
			result[str(definition.id)] = definition
	return result


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Difficulty simulation test failed: " + message)
