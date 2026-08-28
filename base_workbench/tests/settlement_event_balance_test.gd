extends SceneTree

const GameDatabaseScript := preload("res://scripts/core/GameDatabase.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const DifficultyDirectorScript := preload("res://scripts/campaign/DifficultyDirector.gd")
const SettlementEventSystemScript := preload("res://base_workbench/systems/SettlementEventSystem.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")

const SAMPLE_COUNT := 1_000
const EPSILON := 0.0001

var _failures := 0
var _database
var _system
var _balance


func _initialize() -> void:
	_database = GameDatabaseScript.new()
	_database.load_definitions()
	_system = SettlementEventSystemScript.new()
	_balance = _database.settlement_event_balance

	_test_configuration_contract()
	_test_curve_boundaries_and_injection()
	_test_analysis_is_pure_and_deterministic()
	_test_profile_cadence_and_tones()
	_test_need_targeting()
	_test_critical_workforce_guarantee()
	_test_sampled_distribution_matches_analysis()

	_database.free()
	if _failures == 0:
		print("Settlement event balance test passed: editable curves, two-stage cadence, need targeting, profile axes, critical workforce guarantee and sampled distribution are valid.")
		quit(0)
	else:
		push_error("Settlement event balance test failed with %d assertion(s)." % _failures)
		quit(1)


func _test_configuration_contract() -> void:
	_assert(_database.is_valid(), "GameDatabase powinien walidować balans razem z pełną pulą wydarzeń.")
	_assert(_balance != null and _balance.is_valid(), "Globalny zasób balansu wydarzeń powinien być poprawny.")
	var configured: Array[String] = _balance.configured_trigger_tags()
	var used: Array[String] = []
	for definition in _database.settlement_events.values():
		for trigger_tag in definition.effective_trigger_tags():
			if not used.has(trigger_tag):
				used.append(trigger_tag)
	used.sort()
	_assert(configured == used, "Każdy skonfigurowany trigger tag musi mieć konsumenta i każda karta musi mieć regułę.")

	var invalid = _balance.duplicate(true)
	invalid.maximum_weight_multiplier = invalid.minimum_weight_multiplier * 0.5
	_assert(not invalid.is_valid(), "Odwrócony zakres końcowego mnożnika musi zostać odrzucony.")
	invalid = _balance.duplicate(true)
	invalid.trigger_rules.append(invalid.trigger_rules[0].duplicate(true))
	_assert(not invalid.is_valid(), "Powielona reguła trigger tagu musi zostać odrzucona.")
	invalid = _balance.duplicate(true)
	invalid.forced_recovery_role = "workfroce"
	_assert(not invalid.is_valid(), "Literówka w roli gwarancji workforce musi zostać odrzucona, zamiast po cichu wyłączać zabezpieczenie.")
	invalid = _balance.duplicate(true)
	invalid.recovery_match_weight_multiplier = 0.99
	_assert(not invalid.is_valid(), "Mnożnik dopasowanej pomocy poniżej 1 nie może antypreferować ulgi.")
	invalid = _balance.duplicate(true)
	invalid.preferred_impact_weight_multiplier = 0.99
	_assert(not invalid.is_valid(), "Mnożnik preferowanego skutku poniżej 1 nie może antypreferować ulgi.")
	invalid = _balance.duplicate(true)
	invalid.trigger_rules[0].bonus_activation_multiplier = 1.0
	_assert(not invalid.is_valid(), "Dodatni bonus częstotliwości wymaga progu aktywacji większego niż neutralne ×1.")
	invalid = _balance.duplicate(true)
	invalid.trigger_rules.append(Resource.new())
	_assert(not invalid.is_valid() and invalid.configured_trigger_tags() == configured, "Zasób złego typu ma zostać bezpiecznie odrzucony bez błędu skryptu walidatora.")
	var rejected_analysis: Dictionary = _system.selection_analysis(_state(80_999), _database.settlement_events, null, invalid)
	_assert(rejected_analysis.status == "invalid_balance", "Runtime musi fail-fast odrzucić niepoprawny balans przed losowaniem.")
	invalid = _balance.duplicate(true)
	var band_used_as_curve = invalid.trigger_rules[0].curves[0].bands[0]
	invalid.trigger_rules[0].curves[0] = band_used_as_curve
	_assert(not invalid.is_valid(), "Band w tablicy curves musi dać kontrolowany błąd typu bez dereferencji nieistniejącego metric.")
	invalid = _balance.duplicate(true)
	var curve_used_as_band = invalid.trigger_rules[0].curves[0].duplicate(true)
	invalid.trigger_rules[0].curves[0].bands[0] = curve_used_as_band
	_assert(not invalid.is_valid(), "Curve w tablicy bands musi dać kontrolowany błąd typu bez dereferencji nieistniejącego label.")
	var event_with_wrong_choice = _database.settlement_events["drifting_supply_crates"].duplicate(true)
	event_with_wrong_choice.choices[0] = DifficultyProfileScript.new()
	_assert(not event_with_wrong_choice.is_valid(), "Resource z metodą is_valid, ale bez kontraktu wyboru, musi zostać odrzucony przed odczytem choice.id.")
	var nested_type_database = GameDatabaseScript.new()
	nested_type_database.load_definitions()
	nested_type_database.settlement_events = nested_type_database.settlement_events.duplicate()
	nested_type_database.settlement_events["drifting_supply_crates"] = event_with_wrong_choice
	nested_type_database.validation_errors.clear()
	nested_type_database._validate_settlement_events()
	_assert(not nested_type_database.validation_errors.is_empty(), "GameDatabase ma zamienić zły typ zagnieżdżonego wyboru w błąd danych, nie SCRIPT ERROR.")
	nested_type_database.free()

	var semantic_database = GameDatabaseScript.new()
	var medicine_without_food_cost = _database.settlement_events["trader_at_dawn"].find_choice("trade_for_medicine").duplicate(true)
	medicine_without_food_cost.impact_tags.erase("food_cost")
	semantic_database._validate_settlement_choice_impact_semantics("trader_at_dawn", medicine_without_food_cost)
	_assert(_errors_contain(semantic_database.validation_errors, "food_cost"), "Ujemne jedzenie bez food_cost musi zostać odrzucone przez semantyczny kontrakt tagów.")
	semantic_database.validation_errors.clear()
	var fake_material_relief = _database.settlement_events["trader_at_dawn"].find_choice("trade_for_fabric").duplicate(true)
	fake_material_relief.impact_tags.append("material_relief")
	semantic_database._validate_settlement_choice_impact_semantics("trader_at_dawn", fake_material_relief)
	_assert(_errors_contain(semantic_database.validation_errors, "material_relief"), "Wymiana zmniejszająca deski i złom nie może deklarować material_relief.")
	semantic_database.free()
	var cross_database = GameDatabaseScript.new()
	cross_database.load_definitions()
	cross_database.settlement_events = cross_database.settlement_events.duplicate()
	var population_without_role = cross_database.settlement_events["survivors_on_horizon"].duplicate(true)
	population_without_role.recovery_role = "none"
	cross_database.settlement_events["survivors_on_horizon"] = population_without_role
	cross_database.validation_errors.clear()
	cross_database._validate_settlement_events()
	var missing_consumer_rejected := false
	for validation_error in cross_database.validation_errors:
		if str(validation_error).contains("Gwarancja krytycznej załogi"):
			missing_consumer_rejected = true
	_assert(missing_consumer_rejected, "GameDatabase musi odrzucić gwarancję bez aktywnej karty workforce dodającej mieszkańców.")
	cross_database.free()


func _test_curve_boundaries_and_injection() -> void:
	var metrics := _metrics()
	metrics.food_days = 0.74
	_assert(_trigger_multiplier("food_need", metrics) == 4.0, "food_need poniżej 0,75 dnia powinno dawać ×4.")
	metrics.food_days = 0.75
	_assert(_trigger_multiplier("food_need", metrics) == 2.2, "Granica 0,75 dnia powinna wejść do drugiego przedziału.")
	metrics.food_days = 1.5
	_assert(_trigger_multiplier("food_need", metrics) == 1.0, "Granica 1,5 dnia powinna wrócić do mnożnika bazowego.")
	metrics.food_days = 3.0
	_assert(_trigger_multiplier("food_need", metrics) == 0.6, "Trzy dni żywności powinny obniżać wagę potrzeby żywnościowej.")

	metrics = _metrics()
	metrics.medicine_stock = 0
	_assert(_trigger_multiplier("medicine_need", metrics) == 4.0, "Dokładnie zero leków powinno dawać ×4.")
	metrics.medicine_stock = 1
	_assert(_trigger_multiplier("medicine_need", metrics) == 2.0, "Od jednego do dwóch leków powinno dawać ×2.")
	metrics.medicine_stock = 3
	_assert(_trigger_multiplier("medicine_need", metrics) == 1.0, "Średni zapas leków powinien używać fallback ×1.")
	metrics.medicine_stock = 6
	_assert(_trigger_multiplier("medicine_need", metrics) == 0.6, "Sześć leków powinno obniżać wagę handlarza.")

	metrics = _metrics()
	metrics.healthy_workers = 2
	metrics.free_shelter = 2
	metrics.food_days = 2.0
	_assert(is_equal_approx(_trigger_multiplier("population_need", metrics), 5.2), "Potrzeba ludzi powinna składać się z niezależnych krzywych pracy, schronienia i żywności.")

	var state = _state(81_001)
	var pressure := _pressure(state, {"food_days": 0.6, "basic_materials": 30})
	var supply = _database.settlement_events["drifting_supply_crates"]
	var production_weight: float = _system.event_weight(state, supply, pressure, _balance)
	var tuned_balance = _balance.duplicate(true)
	var tuned_rule = tuned_balance.find_trigger_rule("food_need")
	tuned_rule.curves[0].bands[0].multiplier = 2.0
	var tuned_weight: float = _system.event_weight(state, supply, pressure, tuned_balance)
	_assert(tuned_weight < production_weight, "Wstrzyknięta kopia konfiguracji powinna przewidywalnie zmieniać realną wagę bez edycji kodu.")
	_assert(_trigger_multiplier("food_need", metrics.merged({"food_days": 0.6}, true)) == 4.0, "Strojenie kopii nie może mutować produkcyjnego zasobu.")

	var safe_recovery := _pressure(state, _stable_overrides().merged({"prefer_relief": true, "reason_codes": ["sustained_high_pressure"]}, true))
	var safe_breakdown: Dictionary = _system.event_weight_breakdown(state, supply, safe_recovery, _balance)
	_assert(is_equal_approx(float(safe_breakdown.recovery_multiplier), 1.0), "Ogólny dzień regeneracji powinien filtrować do bezpiecznych tonów bez pozornego wspólnego mnożnika wag.")
	var matching_recovery := _pressure(state, _stable_overrides().merged({"prefer_relief": true, "reason_codes": ["food_low"], "recovery_roles": ["food"]}, true))
	var matching_breakdown: Dictionary = _system.event_weight_breakdown(state, supply, matching_recovery, _balance)
	_assert(is_equal_approx(float(matching_breakdown.recovery_multiplier), float(_balance.recovery_match_weight_multiplier)), "Dopasowana pomoc powinna konsumować osobny mnożnik recovery role.")
	var population_event = _database.settlement_events["survivors_on_horizon"]
	var population_breakdown: Dictionary = _system.event_weight_breakdown(state, population_event, matching_recovery, _balance)
	_assert(is_equal_approx(float(population_breakdown.recovery_multiplier), 1.0), "food_demand nie może być klasyfikowany jako pomoc żywnościowa i premiować nowych mieszkańców podczas niedoboru jedzenia.")
	var matching_analysis: Dictionary = _system.selection_analysis(state, _database.settlement_events, matching_recovery, _balance)
	var neutral_recovery_balance = _balance.duplicate(true)
	neutral_recovery_balance.recovery_match_weight_multiplier = 1.0
	var neutral_matching_analysis: Dictionary = _system.selection_analysis(state, _database.settlement_events, matching_recovery.duplicate(true), neutral_recovery_balance)
	_assert(_candidate_share(matching_analysis, "drifting_supply_crates") > _candidate_share(neutral_matching_analysis, "drifting_supply_crates") * 1.25, "Mnożnik recovery role musi realnie zwiększać udział dopasowanej karty, nie tylko pojawiać się w breakdown.")
	var preferred_impact := _pressure(state, _stable_overrides().merged({"preferred_impact_tags": ["food_relief"]}, true))
	var impact_breakdown: Dictionary = _system.event_weight_breakdown(state, supply, preferred_impact, _balance)
	_assert(is_equal_approx(float(impact_breakdown.preferred_impact_multiplier), float(_balance.preferred_impact_weight_multiplier)), "Preferowany impact z PressureState powinien konsumować konfigurowalny mnożnik balansu.")

	var unaffordable_state = _state(81_003)
	unaffordable_state.resources.set_amount(ResourceIdsScript.FOOD, 0)
	unaffordable_state.resources.set_amount(ResourceIdsScript.SCRAP, 0)
	unaffordable_state.resources.set_amount(ResourceIdsScript.PLANKS, 0)
	var unavailable_medicine := _pressure(unaffordable_state, _stable_overrides().merged({"medicines": 0, "prefer_relief": true, "recovery_roles": ["medicine"], "preferred_impact_tags": ["medicine_relief"]}, true))
	var trader_breakdown: Dictionary = _system.event_weight_breakdown(unaffordable_state, _database.settlement_events["trader_at_dawn"], unavailable_medicine, _balance)
	var trader_trigger: Dictionary = trader_breakdown.trigger_breakdown[0]
	_assert(is_equal_approx(float(trader_trigger.multiplier), 1.0) and str(trader_trigger.get("suppressed_reason", "")) == "no_affordable_matching_choice", "Brak waluty ma zdjąć bonus medicine_need z handlarza, gdy dostępna jest tylko odmowa.")
	_assert(is_equal_approx(float(trader_breakdown.recovery_multiplier), 1.0) and is_equal_approx(float(trader_breakdown.preferred_impact_multiplier), 1.0), "Karta bez wykonalnej ulgi nie może dostać premii recovery ani preferred impact.")
	var unavailable_integrity := _pressure(unaffordable_state, _stable_overrides().merged({"platform_integrity": 30, "preferred_impact_tags": ["integrity_relief"]}, true))
	var mooring_breakdown: Dictionary = _system.event_weight_breakdown(unaffordable_state, _database.settlement_events["torn_mooring"], unavailable_integrity, _balance)
	_assert(is_equal_approx(float(mooring_breakdown.trigger_breakdown[0].multiplier), 1.0) and is_equal_approx(float(mooring_breakdown.preferred_impact_multiplier), 1.0), "Brak materiałów naprawczych ma zdjąć pozorny bonus integrity_relief z karty cumowania.")
	var critical_food_state = _state(81_004)
	critical_food_state.resources.set_amount(ResourceIdsScript.FOOD, 6)
	var critical_food_pressure := _pressure(critical_food_state, _stable_overrides().merged({
		"food_days": 0.375,
		"pressure_budget": 0.0,
		"max_event_severity": 1,
		"prefer_relief": true,
		"critical_gates": ["food_below_half_day"],
		"active_pressure_tags": ["food_critical"],
		"recovery_roles": ["food"],
		"blocked_impact_tags": ["food_cost", "food_demand"],
	}, true))
	var critical_food_analysis: Dictionary = _system.selection_analysis(critical_food_state, _database.settlement_events, critical_food_pressure, _balance)
	_assert(str(critical_food_analysis.rejected_candidates.get("trader_at_dawn", "")) == "blocked_impact:food_cost", "Handlarz nie może ominąć ochrony krytycznego głodu, nawet gdy magazyn ma dokładnie 6 jednostek potrzebnych do transakcji.")

	var no_profile_state = _state(81_002)
	no_profile_state.difficulty_profile = null
	var fallback_analysis: Dictionary = _system.selection_analysis(no_profile_state, _database.settlement_events, _pressure(no_profile_state, _stable_overrides()), _balance)
	_assert(is_equal_approx(float(fallback_analysis.event_probability), 1.0 - float(_balance.fallback_quiet_day_percentage) / 100.0), "Stan techniczny bez profilu powinien użyć jawnej wartości awaryjnej kadencji.")
	var capped_balance = _balance.duplicate(true)
	capped_balance.minimum_event_probability = 0.3
	capped_balance.maximum_event_probability = 0.3
	var capped_analysis: Dictionary = _system.selection_analysis(state, _database.settlement_events, _pressure(state, _stable_overrides()), capped_balance)
	_assert(is_equal_approx(float(capped_analysis.event_probability), 0.3), "Wstrzyknięte granice prawdopodobieństwa powinny realnie ograniczać kadencję.")


func _test_analysis_is_pure_and_deterministic() -> void:
	var state = _state(81_101)
	var pressure := _pressure(state, _stable_overrides())
	var state_before := _state_fingerprint(state)
	var pressure_before := str(pressure)
	var first: Dictionary = _system.selection_analysis(state, _database.settlement_events, pressure, _balance)
	var reversed: Dictionary = {}
	var ids: Array[String] = []
	for event_id in _database.settlement_events.keys():
		ids.append(str(event_id))
	ids.sort()
	ids.reverse()
	for event_id in ids:
		reversed[event_id] = _database.settlement_events[event_id]
	var second: Dictionary = _system.selection_analysis(state, reversed, pressure.duplicate(true), _balance)

	_assert(first.status == "ready" and first.can_roll, "Analiza gotowego poranka powinna zwracać pełny, niezmieniający stanu wynik.")
	_assert(_analysis_signature(first) == _analysis_signature(second), "Kolejność Dictionary nie może zmieniać wag, prawdopodobieństw ani wyniku RNG.")
	_assert(_state_fingerprint(state) == state_before and str(pressure) == pressure_before, "Analiza balansu nie może mutować GameState ani dziennego PressureState.")
	var probability_sum := float(first.quiet_probability)
	for entry in first.candidates:
		probability_sum += float(entry.morning_probability)
	_assert(absf(probability_sum - 1.0) <= EPSILON, "Prawdopodobieństwo ciszy i wszystkich kart powinno sumować się do 1.")
	_assert(int(state.settlement_event_roll_day) == 0 and state.pending_settlement_event == null, "Read-only analiza nie może konsumować losowania dnia.")


func _test_profile_cadence_and_tones() -> void:
	var pressure_overrides := _stable_overrides()
	var easy = _analysis_for_profile("easy", pressure_overrides)
	var standard = _analysis_for_profile("standard", pressure_overrides)
	var hard = _analysis_for_profile("hard", pressure_overrides)
	_assert(is_equal_approx(float(easy.event_probability), 0.40), "Łagodny profil powinien bazowo dawać 40% poranków z wydarzeniem.")
	_assert(is_equal_approx(float(standard.event_probability), 0.55), "Standard powinien bazowo dawać 55% poranków z wydarzeniem.")
	_assert(is_equal_approx(float(hard.event_probability), 0.68), "Surowy profil powinien bazowo dawać 68% poranków z wydarzeniem.")
	_assert(float(easy.quiet_probability) > float(standard.quiet_probability) and float(standard.quiet_probability) > float(hard.quiet_probability), "Profile muszą zachowywać monotoniczną kadencję ciszy.")

	var easy_relief := _conditional_tone_share(easy, "relief")
	var standard_relief := _conditional_tone_share(standard, "relief")
	var hard_relief := _conditional_tone_share(hard, "relief")
	var easy_hardship := _conditional_tone_share(easy, "hardship")
	var standard_hardship := _conditional_tone_share(standard, "hardship")
	var hard_hardship := _conditional_tone_share(hard, "hardship")
	_assert(easy_relief > standard_relief and standard_relief > hard_relief, "Mnożnik relief powinien faktycznie zmieniać udział pomocnych kart.")
	_assert(easy_hardship < standard_hardship and standard_hardship < hard_hardship, "Mnożnik hardship powinien faktycznie zmieniać udział trudnych kart.")


func _test_need_targeting() -> void:
	var baseline := _analysis(_stable_overrides())
	var food := _analysis(_stable_overrides().merged({"food_days": 0.6}, true))
	var materials := _analysis(_stable_overrides().merged({"basic_materials": 5}, true))
	var integrity := _analysis(_stable_overrides().merged({"platform_integrity": 30}, true))
	var hope := _analysis(_stable_overrides().merged({"hope": 18, "food_days": 3.5}, true))
	var medicine := _analysis(_stable_overrides().merged({"medicines": 0}, true))
	var compound := _analysis(_stable_overrides().merged({"food_days": 0.6, "basic_materials": 5}, true))

	_assert(_candidate_share(food, "drifting_supply_crates") >= _candidate_share(baseline, "drifting_supply_crates") * 1.8, "Niedobór żywności powinien silnie podnieść udział dopasowanej karty.")
	_assert(_candidate_share(materials, "drifting_supply_crates") >= _candidate_share(baseline, "drifting_supply_crates") * 1.5, "Niedobór materiałów powinien podnieść udział skrzyń.")
	_assert(_candidate_share(integrity, "torn_mooring") >= _candidate_share(baseline, "torn_mooring") * 1.8, "Niska integralność powinna podnieść udział naprawy cumowania.")
	_assert(_candidate_share(hope, "shared_meal") >= _candidate_share(baseline, "shared_meal") * 1.8, "Niska Nadzieja przy zapasie żywności powinna podnieść udział wspólnego posiłku.")
	_assert(_candidate_share(medicine, "trader_at_dawn") >= _candidate_share(baseline, "trader_at_dawn") * 1.8, "Brak leków powinien podnieść udział handlarza.")
	_assert(float(food.need_probability_bonus) >= 0.08 - EPSILON and float(compound.need_probability_bonus) >= 0.14 - EPSILON, "Pilne potrzeby powinny zwiększać także częstotliwość wydarzeń, z limitem globalnym.")
	_assert(_largest_non_forced_share(compound) <= 0.70 + EPSILON, "Clamp ×5,5 powinien ograniczać dominację pojedynczej karty w złożonym niedoborze.")


func _test_critical_workforce_guarantee() -> void:
	var state = _low_population_state(82_001)
	var real_pressure = DifficultyDirectorScript.new().build_for_day(state)
	var real_analysis: Dictionary = _system.selection_analysis(state, _database.settlement_events, real_pressure, _balance)
	_assert(real_pressure != null and int(real_pressure.band) == 3 and is_zero_approx(float(real_pressure.pressure_budget)) and int(real_pressure.max_event_severity) <= 1, "Krytyczny brak pracowników powinien korzystać z rzeczywistego, ochronnego pasa CRISIS reżysera.")
	_assert(real_analysis.selected_event_id == "survivors_on_horizon" and real_analysis.forced_event_id == "survivors_on_horizon", "Gwarancja populacyjna musi działać z rzeczywistym PressureState, nie tylko ze sztucznym słownikiem testowym.")
	var supported := _pressure(state, {
		"population": 1,
		"healthy_workers": 1,
		"food_days": 3.0,
		"free_shelter": 2,
		"pressure_budget": 0.0,
		"max_event_severity": 1,
		"prefer_relief": true,
		"critical_gates": ["workforce_critical"],
		"reason_codes": ["workforce_critical"],
		"active_pressure_tags": ["workforce_critical"],
		"recovery_roles": ["workforce"],
		"preferred_impact_tags": ["workforce_relief", "population_gain"],
	})
	for seed_value in range(1, 501):
		state.seed = seed_value
		var analysis: Dictionary = _system.selection_analysis(state, _database.settlement_events, supported, _balance)
		_assert(analysis.selected_event_id == "survivors_on_horizon" and analysis.forced_event_id == "survivors_on_horizon", "Każdy seed powinien wymusić pomoc populacyjną przy wspieranym krytycznym braku ludzi.")
		if _failures > 0:
			break

	var starving := supported.duplicate(true)
	starving.food_days = 0.6
	starving.reason_codes = ["workforce_critical", "food_low"]
	starving.active_pressure_tags = ["food_critical", "workforce_critical"]
	starving.recovery_roles = ["food", "workforce"]
	var starving_analysis: Dictionary = _system.selection_analysis(state, _database.settlement_events, starving, _balance)
	_assert(str(starving_analysis.forced_event_id).is_empty() and float(starving_analysis.event_probability) < 1.0, "Gwarancja nie może wymuszać dwóch nowych osób bez minimalnego zapasu żywności.")
	var unsafe_after_accept := supported.duplicate(true)
	unsafe_after_accept.food_days = 2.0
	var unsafe_after_accept_analysis: Dictionary = _system.selection_analysis(state, _database.settlement_events, unsafe_after_accept, _balance)
	_assert(str(unsafe_after_accept_analysis.forced_event_id).is_empty(), "Próg żywności gwarancji musi być liczony po hipotetycznym przyjęciu dwóch osób, nie dla starej populacji.")
	var unsafe_population_breakdown: Dictionary = _system.event_weight_breakdown(state, _database.settlement_events["survivors_on_horizon"], unsafe_after_accept, _balance)
	_assert(not unsafe_population_breakdown.available_choice_impact_tags.has("workforce_relief") and is_equal_approx(float(unsafe_population_breakdown.trigger_breakdown[0].multiplier), 1.0), "Oferta nieutrzymywalnej grupy nie może udawać dostępnej ulgi workforce ani dostać bonusu population_need.")
	_assert(is_equal_approx(float(unsafe_population_breakdown.recovery_multiplier), 1.0) and is_equal_approx(float(unsafe_population_breakdown.preferred_impact_multiplier), 1.0), "Nieutrzymywalna grupa nie może dostać premii regeneracji ani preferowanego skutku.")
	var exact_after_accept := supported.duplicate(true)
	exact_after_accept.food_days = 2.25
	var exact_after_accept_analysis: Dictionary = _system.selection_analysis(state, _database.settlement_events, exact_after_accept, _balance)
	_assert(exact_after_accept_analysis.forced_event_id == "survivors_on_horizon", "Dokładnie 0,75 dnia żywności po przyjęciu grupy powinno przejść granicę gwarancji.")
	var no_shelter := supported.duplicate(true)
	no_shelter.free_shelter = 0
	var no_shelter_analysis: Dictionary = _system.selection_analysis(state, _database.settlement_events, no_shelter, _balance)
	_assert(str(no_shelter_analysis.forced_event_id).is_empty(), "Gwarancja nie może omijać minimalnej liczby miejsc w schronieniu.")
	var dynamic_shelter_balance = _balance.duplicate(true)
	dynamic_shelter_balance.forced_minimum_free_shelter = 0
	var one_bed := supported.duplicate(true)
	one_bed.free_shelter = 1
	var one_bed_analysis: Dictionary = _system.selection_analysis(state, _database.settlement_events, one_bed, dynamic_shelter_balance)
	_assert(str(one_bed_analysis.forced_event_id).is_empty(), "Nawet przy konfiguracyjnym minimum 0 gwarancja nie może przyjąć dwóch osób do jednego wolnego łóżka.")
	var soft_filter_balance = _balance.duplicate(true)
	soft_filter_balance.recovery_safe_tones.assign(["relief"])
	var force_before_soft_filter: Dictionary = _system.selection_analysis(state, _database.settlement_events, supported, soft_filter_balance)
	_assert(force_before_soft_filter.forced_event_id == "survivors_on_horizon", "Twarda gwarancja workforce musi mieć pierwszeństwo przed miękkim filtrem tonu regeneracji.")


func _test_sampled_distribution_matches_analysis() -> void:
	var scenarios := {
		"stable": _stable_overrides(),
		"food_need": _stable_overrides().merged({"food_days": 0.6}, true),
		"low_hope": _stable_overrides().merged({"hope": 18, "food_days": 3.5}, true),
	}
	for scenario_id in scenarios.keys():
		var expected := _analysis(scenarios[scenario_id])
		var first_counts := _sample_counts(scenarios[scenario_id], SAMPLE_COUNT)
		var second_counts := _sample_counts(scenarios[scenario_id], SAMPLE_COUNT)
		_assert(first_counts == second_counts, "Próba %s musi być bitowo deterministyczna." % scenario_id)
		var observed_quiet := float(first_counts.get("quiet", 0)) / float(SAMPLE_COUNT)
		_assert(absf(observed_quiet - float(expected.quiet_probability)) <= 0.05, "Próbkowana cisza %s powinna zgadzać się z analizą w tolerancji 5 pp." % scenario_id)
		for entry in expected.candidates:
			var event_id := str(entry.event_id)
			var observed := float(first_counts.get(event_id, 0)) / float(SAMPLE_COUNT)
			_assert(absf(observed - float(entry.morning_probability)) <= 0.05, "Próbkowany udział %s/%s powinien zgadzać się z jawnym prawdopodobieństwem." % [scenario_id, event_id])


func _analysis(overrides: Dictionary, profile_id: String = "standard") -> Dictionary:
	var profile = _database.get_difficulty_profile(profile_id)
	if profile == null:
		profile = DifficultyProfileScript.new()
	var state = _state(83_001, profile)
	return _system.selection_analysis(state, _database.settlement_events, _pressure(state, overrides), _balance)


func _analysis_for_profile(profile_id: String, overrides: Dictionary) -> Dictionary:
	return _analysis(overrides, profile_id)


func _errors_contain(errors: Array[String], fragment: String) -> bool:
	for error in errors:
		if str(error).contains(fragment):
			return true
	return false


func _sample_counts(overrides: Dictionary, samples: int) -> Dictionary:
	var state = _state(84_001, _database.get_standard_difficulty())
	var pressure := _pressure(state, overrides)
	var counts := {"quiet": 0}
	for seed_value in range(1, samples + 1):
		state.seed = seed_value
		var analysis: Dictionary = _system.selection_analysis(state, _database.settlement_events, pressure, _balance)
		var event_id := str(analysis.selected_event_id)
		var key := event_id if not event_id.is_empty() else "quiet"
		counts[key] = int(counts.get(key, 0)) + 1
	return counts


func _candidate_share(analysis: Dictionary, event_id: String) -> float:
	for entry in analysis.candidates:
		if str(entry.event_id) == event_id:
			return float(entry.conditional_probability)
	return 0.0


func _largest_non_forced_share(analysis: Dictionary) -> float:
	var result := 0.0
	for entry in analysis.candidates:
		result = maxf(result, float(entry.conditional_probability))
	return result


func _conditional_tone_share(analysis: Dictionary, tone: String) -> float:
	var result := 0.0
	for entry in analysis.candidates:
		if str(entry.tone) == tone:
			result += float(entry.conditional_probability)
	return result


func _trigger_multiplier(trigger_tag: String, metrics: Dictionary) -> float:
	return float(_balance.evaluate_trigger(trigger_tag, metrics).get("multiplier", 0.0))


func _analysis_signature(analysis: Dictionary) -> String:
	var entries: Array[String] = []
	for entry in analysis.candidates:
		entries.append("%s:%.6f:%.6f" % [entry.event_id, float(entry.final_weight), float(entry.morning_probability)])
	return "%s|%.6f|%.6f|%s" % [analysis.selected_event_id, float(analysis.event_probability), float(analysis.quiet_probability), ";".join(entries)]


func _stable_overrides() -> Dictionary:
	return {
		"population": 4,
		"healthy_workers": 4,
		"food_days": 2.0,
		"hope": 55,
		"platform_integrity": 70,
		"basic_materials": 25,
		"medicines": 3,
		"free_shelter": 1,
		"pressure_budget": 3.0,
		"max_event_severity": 3,
		"prefer_relief": false,
		"critical_gates": [],
		"reason_codes": [],
		"active_pressure_tags": [],
		"recovery_roles": [],
		"blocked_impact_tags": [],
		"preferred_impact_tags": [],
	}


func _metrics() -> Dictionary:
	return {
		"alive_count": 3,
		"healthy_workers": 4,
		"food_days": 2.0,
		"hope": 55,
		"integrity": 70,
		"material_stock": 25,
		"medicine_stock": 3,
		"free_shelter": 1,
	}


func _pressure(state, overrides: Dictionary = {}) -> Dictionary:
	var metrics := _metrics()
	var pressure := {
		"day": int(state.day),
		"band": 1,
		"strain": 0.4,
		"pressure_budget": 3.0,
		"max_event_severity": 3,
		"prefer_relief": false,
		"tutorial_protected": false,
		"critical_gates": [],
		"reason_codes": [],
		"population": int(metrics.alive_count),
		"food_days": float(metrics.food_days),
		"hope": int(metrics.hope),
		"healthy_workers": int(metrics.healthy_workers),
		"platform_integrity": int(metrics.integrity),
		"basic_materials": int(metrics.material_stock),
		"medicines": int(metrics.medicine_stock),
		"shelter_capacity": 4,
		"free_shelter": int(metrics.free_shelter),
		"recent_dive_outcomes": [],
		"major_event_cooldown_days_remaining": 0,
		"committed_event_id": "",
		"quiet_morning": false,
	}
	pressure.merge(overrides, true)
	pressure.day = int(state.day)
	return pressure


func _state(seed_value: int, profile = null):
	var state = GameStateScript.new()
	state.setup_new_campaign(seed_value, profile if profile != null else DifficultyProfileScript.new())
	state.tutorial.complete()
	state.day = 4
	state.begin_new_day_plan()
	state.settlement_event_roll_day = 0
	return state


func _low_population_state(seed_value: int):
	var state = _state(seed_value, _database.get_standard_difficulty())
	for index in range(1, state.survivors.size()):
		state.survivors[index].status = SurvivorStateScript.Status.DEAD
		state.survivors[index].health = 0
	return state


func _state_fingerprint(state) -> String:
	var survivors: Array[String] = []
	for survivor in state.survivors:
		survivors.append("%s:%d:%d" % [survivor.id, survivor.status, survivor.health])
	return "%d|%d|%d|%s|%s|%d|%s" % [
		state.seed,
		state.day,
		state.settlement_event_roll_day,
		str(state.resources.values),
		";".join(survivors),
		state.settlement_event_history.size(),
		str(state.pending_settlement_event),
	]


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Settlement event balance assertion failed: " + message)
