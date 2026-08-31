extends SceneTree

const DifficultyDirectorScript := preload("res://scripts/campaign/DifficultyDirector.gd")
const PressureStateScript := preload("res://scripts/data/PressureState.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const SettlementEventStateScript := preload("res://scripts/data/SettlementEventState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const WeatherStateScript := preload("res://scripts/data/WeatherState.gd")

var _failed := false

func _initialize() -> void:
	var director = DifficultyDirectorScript.new()
	_test_determinism_and_no_mutation(director)
	_test_exact_critical_boundaries(director)
	_test_hysteresis(director)
	_test_recovery_and_recent_dives(director)
	_test_tutorial_protection(director)
	_test_committed_morning_metadata()
	_test_pressure_resource_roundtrip()
	if _failed:
		quit(1)
		return
	print("Difficulty director test passed: determinism, boundaries, gates, hysteresis, recovery, committed morning, Resource roundtrip and immutability work.")
	quit(0)

func _test_determinism_and_no_mutation(director) -> void:
	var state = _ready_state(91_001, 5)
	var previous = PressureStateScript.new()
	previous.day = 4
	previous.band = PressureStateScript.Band.NORMAL
	previous.recent_dive_outcomes.assign([PressureStateScript.DIVE_SUCCESS])
	previous.reason_codes.assign(["unchanged"])
	var state_before := _state_fingerprint(state)
	var previous_outcomes: Array = previous.recent_dive_outcomes.duplicate()
	var previous_reasons: Array = previous.reason_codes.duplicate()
	var first = director.build_for_day(state, previous)
	var second = director.build_for_day(state, previous)
	_assert(first != null and first.is_valid_for_day(5), "Migawka musi należeć do dokładnie jednego bieżącego dnia.")
	_assert(first.debug_summary == second.debug_summary, "Te same jawne dane wejściowe muszą tworzyć identyczną migawkę bez RNG.")
	_assert(is_equal_approx(first.strain, second.strain) and first.band == second.band and is_equal_approx(first.pressure_budget, second.pressure_budget), "Strain, band i budget muszą być deterministyczne.")
	_assert(_state_fingerprint(state) == state_before, "Director nie może mutować GameState, profilu, zasobów ani mieszkańców.")
	_assert(previous.recent_dive_outcomes == previous_outcomes and previous.reason_codes == previous_reasons, "Director nie może mutować poprzedniej migawki.")
	_assert(not first.debug_summary.is_empty(), "Migawka musi wyjaśniać wynik w debug_summary.")

func _test_exact_critical_boundaries(director) -> void:
	var state = _ready_state(91_002, 6)
	state.resources.set_amount(ResourceIdsScript.FOOD, 6)
	var at_half_day = director.build_for_day(state)
	_assert(not at_half_day.has_critical_gate("food_below_half_day"), "Dokładnie 0,5 dnia jedzenia nie może przejść bramki `< 0,5`.")
	state.resources.set_amount(ResourceIdsScript.FOOD, 5)
	var below_half_day = director.build_for_day(state)
	_assert(below_half_day.has_critical_gate("food_below_half_day") and below_half_day.band == PressureStateScript.Band.CRISIS, "Zapas poniżej 0,5 dnia musi wymusić CRISIS.")
	_assert(is_zero_approx(below_half_day.pressure_budget) and below_half_day.max_event_severity == 1 and below_half_day.prefer_relief, "CRISIS może dopuścić tylko zerokosztową kartę ulgi severity 1, bez dodatkowej presji.")
	_assert(below_half_day.blocked_impact_tags.has("food_cost") and below_half_day.blocked_impact_tags.has("food_demand") and below_half_day.preferred_impact_tags.has("food_relief"), "Krytyczne jedzenie musi jawnie blokować dalsze koszty i preferować skutek food_relief.")
	_assert(below_half_day.active_pressure_tags.has("food_critical") and below_half_day.recovery_roles.has("food"), "Director musi zamrozić jawny tag wykluczający i rolę regeneracji, aby selektor nie odtwarzał progów.")

	state = _ready_state(91_003, 6)
	state.survivors[0].hunger = 84
	_assert(not director.build_for_day(state).has_critical_gate("hunger_critical"), "Głód 84 pozostaje poniżej twardej granicy.")
	state.survivors[0].hunger = 85
	var critical_hunger = director.build_for_day(state)
	_assert(critical_hunger.has_critical_gate("hunger_critical") and critical_hunger.active_pressure_tags.has("food_critical"), "Maksymalny głód 85 musi uruchomić twardą bramkę i wspólny tag food_critical.")

	state = _ready_state(91_004, 6)
	state.resources.set_amount(ResourceIdsScript.HOPE, 15)
	_assert(not director.build_for_day(state).has_critical_gate("hope_critical"), "Nadzieja 15 jest granicą bez bramki `< 15`.")
	state.resources.set_amount(ResourceIdsScript.HOPE, 14)
	var critical_hope = director.build_for_day(state)
	_assert(critical_hope.has_critical_gate("hope_critical") and critical_hope.active_pressure_tags.has("hope_critical") and critical_hope.recovery_roles.has("hope"), "Nadzieja 14 musi uruchomić twardą bramkę i jawną rolę pomocy.")

	state = _ready_state(91_005, 6)
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 25)
	_assert(not director.build_for_day(state).has_critical_gate("integrity_critical"), "Integralność 25 jest granicą bez bramki `< 25`.")
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 24)
	var critical_integrity = director.build_for_day(state)
	_assert(critical_integrity.has_critical_gate("integrity_critical"), "Integralność 24 musi uruchomić twardą bramkę.")
	_assert(critical_integrity.blocked_impact_tags.has("integrity_risk") and critical_integrity.preferred_impact_tags.has("integrity_relief"), "Krytyczna integralność musi blokować dalsze ryzyko i preferować naprawę.")
	_assert(critical_integrity.active_pressure_tags.has("integrity_critical") and critical_integrity.recovery_roles.has("integrity"), "Krytyczna integralność musi przekazać selektorowi gotowy tag i rolę bez drugiego progu.")

	state = _ready_state(91_006, 6)
	state.survivors[0].fatigue = 90
	_assert(not director.build_for_day(state).has_critical_gate("workforce_critical"), "Dwie zdolne osoby nie mogą uruchomić bramki `<= 1`.")
	state.survivors[1].fatigue = 90
	var critical_workforce = director.build_for_day(state)
	_assert(critical_workforce.has_critical_gate("workforce_critical"), "Jedna zdolna osoba musi uruchomić bramkę kryzysową.")
	_assert(critical_workforce.preferred_impact_tags.has("workforce_relief") and critical_workforce.preferred_impact_tags.has("population_gain"), "Brak pracowników musi produkować jawne preferencje skutków wspierających kadrę.")
	_assert(critical_workforce.active_pressure_tags.has("workforce_critical") and critical_workforce.recovery_roles.has("workforce"), "Krytyczna kadra musi przekazać selektorowi gotową rolę workforce.")

	state = _ready_state(91_007, 6)
	var death = DiveResultScript.new()
	death.diver_id = "igor"
	death.returned_alive = false
	death.diver_dead = true
	var after_death = director.build_for_day(state, null, death)
	_assert(after_death.has_critical_gate("diver_died_yesterday") and after_death.last_diver_death_day == 5, "Śmierć właśnie rozliczonego nurka musi być jawna przez cały następny dzień.")
	_assert(after_death.active_pressure_tags.has("recent_death") and after_death.recovery_roles.has("medicine"), "Śmierć nurka musi produkować stabilny tag i jawną rolę pomocy medycznej, bez parsowania tekstu reason code.")

func _test_hysteresis(director) -> void:
	var high_edge = _ready_state(91_008, 8)
	_set_pressure_metrics(high_edge, 9, 70, 25, 40, 0, 0)
	var previous_high = PressureStateScript.new()
	previous_high.day = 7
	previous_high.band = PressureStateScript.Band.HIGH
	previous_high.consecutive_high_days = 1
	var previous_normal = PressureStateScript.new()
	previous_normal.day = 7
	previous_normal.band = PressureStateScript.Band.NORMAL
	var held_high = director.build_for_day(high_edge, previous_high)
	var entered_from_normal = director.build_for_day(high_edge, previous_normal)
	_assert(held_high.strain >= DifficultyDirectorScript.EXIT_HIGH_STRAIN and held_high.strain < DifficultyDirectorScript.ENTER_HIGH_STRAIN, "Stan testowy musi leżeć wewnątrz wysokiego pasa histerezy.")
	_assert(held_high.band == PressureStateScript.Band.HIGH and entered_from_normal.band == PressureStateScript.Band.NORMAL, "HIGH ma trwać do progu wyjścia, ale NORMAL nie może wejść przed progiem wejścia.")

	var low_edge = _ready_state(91_009, 8)
	_set_pressure_metrics(low_edge, 18, 35, 35, 50, 10, 1)
	var previous_low = PressureStateScript.new()
	previous_low.day = 7
	previous_low.band = PressureStateScript.Band.LOW
	var held_low = director.build_for_day(low_edge, previous_low)
	var entered_low_from_normal = director.build_for_day(low_edge, previous_normal)
	_assert(held_low.strain > DifficultyDirectorScript.ENTER_LOW_STRAIN and held_low.strain <= DifficultyDirectorScript.EXIT_LOW_STRAIN, "Stan testowy musi leżeć wewnątrz niskiego pasa histerezy.")
	_assert(held_low.band == PressureStateScript.Band.LOW and entered_low_from_normal.band == PressureStateScript.Band.NORMAL, "LOW ma trwać do progu wyjścia, ale NORMAL nie może wejść przed progiem wejścia.")

func _test_recovery_and_recent_dives(director) -> void:
	var state = _ready_state(91_010, 10)
	var event_state = SettlementEventStateScript.new()
	event_state.event_id = "test_hardship"
	event_state.offered_day = 9
	event_state.resolved_day = 9
	event_state.status = SettlementEventStateScript.Status.RESOLVED
	event_state.applied_resource_deltas = {ResourceIdsScript.PLATFORM_INTEGRITY: -12}
	state.settlement_event_history.append(event_state)
	var failed = DiveResultScript.new()
	failed.returned_alive = true
	failed.emergency_extraction = true
	var recovery = director.build_for_day(state, null, failed)
	_assert(recovery.is_recovery_day() and recovery.last_hardship_event_day == 9, "Ciężki skutek wydarzenia poprzedniego dnia musi dać dzień regeneracji.")
	_assert(recovery.prefer_relief and is_zero_approx(recovery.pressure_budget) and recovery.max_event_severity <= 1, "Dzień regeneracji nie może dokładać płatnej presji.")
	_assert(recovery.recent_dive_outcomes == [PressureStateScript.DIVE_FAILURE] and recovery.recent_failed_dives == 1, "Awaryjne wyciągnięcie jest jawną porażką ostatniej wyprawy.")

	state.day = 11
	state.prepare_weather_for_day(11)
	state.settlement_event_history.clear()
	var success = DiveResultScript.new()
	success.returned_alive = true
	var after_recovery = director.build_for_day(state, recovery, success)
	_assert(not after_recovery.is_recovery_day(), "Jednodniowa regeneracja musi wygasnąć deterministycznie.")
	_assert(after_recovery.recent_dive_outcomes == [PressureStateScript.DIVE_FAILURE, PressureStateScript.DIVE_SUCCESS], "Historia ma zachować trzy ostatnie faktyczne wyprawy w kolejności.")
	_assert(after_recovery.recent_successful_dives == 1 and after_recovery.recent_failed_dives == 1, "Zamrożone liczniki wypraw muszą odpowiadać historii.")

func _test_tutorial_protection(director) -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(91_011, DifficultyProfileScript.new())
	var protected = director.build_for_day(state)
	_assert(protected.tutorial_protected and is_zero_approx(protected.pressure_budget) and protected.max_event_severity == 0, "Aktywny tutorial musi całkowicie zablokować dodatkową presję.")
	_assert(protected.reason_codes.has("tutorial_protection"), "Ochrona tutoriala musi mieć jawny reason code.")

func _test_committed_morning_metadata() -> void:
	var pressure = PressureStateScript.new()
	pressure.day = 4
	pressure.pressure_budget = 1.5
	pressure.max_event_severity = 2
	_assert(not pressure.has_committed_morning() and pressure.committed_event_id.is_empty() and not pressure.quiet_morning, "Nowa migawka nie może udawać już wybranego poranka.")
	_assert(pressure.commit_event("test_event", "hardship", 2, 1.25), "Pierwszy wybór wydarzenia powinien zostać zamrożony w migawce.")
	_assert(pressure.has_committed_morning() and pressure.committed_event_id == "test_event" and pressure.committed_event_tone == "hardship", "Migawka musi przechować ID oraz ton wydarzenia.")
	_assert(pressure.committed_event_severity == 2 and is_equal_approx(pressure.spent_pressure_budget, 1.25), "Migawka musi przechować severity i rzeczywiście wydany budżet.")
	_assert(not pressure.commit_quiet_morning(), "Po zamrożeniu wydarzenia nie wolno nadpisać poranka wynikiem quiet.")
	pressure.committed_event_id = ""
	pressure.committed_event_tone = "broken"
	pressure.committed_event_severity = 99
	pressure.spent_pressure_budget = 99.0
	pressure.quiet_morning = true
	_assert(not pressure.is_valid_for_day(4), "Sprzeczne lub przekraczające budżet metadane nie mogą przejść walidacji zapisu.")
	pressure.ensure_compatibility(4)
	_assert(pressure.quiet_morning and pressure.committed_event_tone.is_empty() and pressure.committed_event_severity == 0 and is_zero_approx(pressure.spent_pressure_budget), "Normalizacja quiet morning musi usunąć sprzeczne metadane wydarzenia.")
	_assert(pressure.is_valid_for_day(4), "Znormalizowana migawka musi ponownie spełniać kontrakt zapisu.")
	_assert(pressure.debug_summary.contains("morning="), "Debug summary musi ujawniać zamrożony wynik selekcji poranka.")

func _test_pressure_resource_roundtrip() -> void:
	const TEST_PATH := "user://test_pressure_state_roundtrip.tres"
	var absolute_path := ProjectSettings.globalize_path(TEST_PATH)
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(absolute_path)
	var pressure = PressureStateScript.new()
	pressure.day = 12
	pressure.band = PressureStateScript.Band.NORMAL
	pressure.strain = 0.42
	pressure.pressure_budget = 1.5
	pressure.max_event_severity = 2
	pressure.reason_codes.assign(["food_low"])
	pressure.active_pressure_tags.assign(["food_critical"])
	pressure.recovery_roles.assign(["food"])
	pressure.recent_dive_outcomes.assign([PressureStateScript.DIVE_FAILURE, PressureStateScript.DIVE_SUCCESS])
	pressure.commit_event("roundtrip_event", "tradeoff", 2, 1.0)
	var save_error := ResourceSaver.save(pressure, TEST_PATH)
	_assert(save_error == OK, "PressureState jako Resource musi dać się zapisać samodzielnie.")
	var loaded = ResourceLoader.load(TEST_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	_assert(loaded != null and loaded.is_valid_for_day(12), "Zapisana migawka musi odtworzyć się jako poprawny Resource dnia.")
	_assert(loaded.committed_event_id == "roundtrip_event" and loaded.committed_event_tone == "tradeoff", "Roundtrip musi zachować audyt wybranego wydarzenia.")
	_assert(loaded.reason_codes == ["food_low"] and loaded.recent_dive_outcomes == [PressureStateScript.DIVE_FAILURE, PressureStateScript.DIVE_SUCCESS], "Roundtrip musi zachować reason codes i historię wypraw.")
	_assert(loaded.active_pressure_tags == ["food_critical"] and loaded.recovery_roles == ["food"], "Roundtrip musi zachować jawne tagi wykluczające i role regeneracji.")
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(absolute_path)

func _ready_state(seed_value: int, target_day: int):
	var state = GameStateScript.new()
	state.setup_new_campaign(seed_value, DifficultyProfileScript.new())
	state.tutorial.complete()
	state.day = target_day
	state.prepare_weather_for_day(target_day)
	state.begin_new_day_plan()
	return state

func _set_pressure_metrics(state, food: int, hunger: int, hope: int, integrity: int, materials: int, medicines: int) -> void:
	state.resources.set_amount(ResourceIdsScript.FOOD, food)
	state.resources.set_amount(ResourceIdsScript.HOPE, hope)
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, integrity)
	state.resources.set_amount(ResourceIdsScript.PLANKS, materials)
	state.resources.set_amount(ResourceIdsScript.SCRAP, 0)
	state.resources.set_amount(ResourceIdsScript.MEDS_CHEMICALS, medicines)
	state.weather.condition = WeatherStateScript.Condition.CALM
	for survivor in state.survivors:
		survivor.hunger = hunger

func _state_fingerprint(state) -> String:
	var survivor_values: Array[String] = []
	for survivor in state.survivors:
		survivor_values.append("%s:%d:%d:%d:%d" % [survivor.id, survivor.health, survivor.hunger, survivor.fatigue, survivor.status])
	return "%d|%s|%s|%s|%d|%d|%d" % [
		state.day,
		str(state.resources.values),
		";".join(survivor_values),
		"%d:%d:%.3f:%.3f:%.3f" % [
			state.difficulty_profile.starting_food,
			state.difficulty_profile.food_per_adult,
			state.difficulty_profile.loot_density_multiplier,
			state.difficulty_profile.build_cost_multiplier,
			state.difficulty_profile.oxygen_use_multiplier,
		],
		state.tutorial.step,
		state.settlement_event_history.size(),
		state.story_flags.successful_dives,
	]

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Difficulty director test failed: " + message)
