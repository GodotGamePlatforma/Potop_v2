extends SceneTree

const GameDatabaseScript := preload("res://scripts/core/GameDatabase.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const SettlementEventPanelScript := preload("res://scripts/base/SettlementEventPanel.gd")
const SettlementEventStateScript := preload("res://scripts/data/SettlementEventState.gd")
const SettlementEventSystemScript := preload("res://scripts/base/SettlementEventSystem.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")

var _failures: int = 0

const EXPECTED_FALLBACKS := {
	"drifting_supply_crates": "recover_food",
	"shared_meal": "save_food",
	"survivors_on_horizon": "reject",
	"torn_mooring": "delay_repair",
	"trader_at_dawn": "refuse_trade",
}

func _initialize() -> void:
	var database = GameDatabaseScript.new()
	database.load_definitions()
	_assert(database.is_valid(), "GameDatabase powinien zaakceptować komplet definicji, w tym metadane wydarzeń.")
	_assert(database.settlement_events.size() == 5, "Pula powinna zawierać pięć wydarzeń osady.")
	_assert(database.survivor_templates.size() == 2, "Wydarzenie rekrutacyjne powinno mieć dwa szablony mieszkańców.")
	for event_id in database.settlement_events.keys():
		var definition = database.settlement_events[event_id]
		_assert(definition != null and definition.is_valid(), "Wydarzenie %s powinno mieć pełne, poprawne metadane." % event_id)
		_assert(not str(definition.tone).is_empty() and int(definition.severity) >= 0, "Wydarzenie %s wymaga tonu i severity." % event_id)
		_assert(not str(definition.cooldown_group).is_empty(), "Wydarzenie %s wymaga grupy cooldownu." % event_id)
		_assert(not str(definition.history_key).is_empty(), "Wydarzenie %s wymaga stabilnego history_key." % event_id)
		_assert(definition.find_choice(str(definition.fallback_choice_id)) != null, "Wydarzenie %s wymaga istniejącej decyzji awaryjnej." % event_id)
		_assert(str(definition.fallback_choice_id) == str(EXPECTED_FALLBACKS.get(str(event_id), "")), "Wydarzenie %s ma mieć zamrożony fallback ARD-0063." % event_id)
		_assert(not definition.trigger_tags.is_empty() and not definition.impact_tags.is_empty(), "Wydarzenie %s wymaga jawnych trigger/impact tags." % event_id)
	var invalid_cost_fallback = database.settlement_events["trader_at_dawn"].duplicate(true)
	invalid_cost_fallback.fallback_choice_id = "trade_for_medicine"
	_assert(not invalid_cost_fallback.is_valid(), "Fallback z ujemnym kosztem zwykłego zasobu musi unieważnić definicję.")
	var invalid_survivor_fallback = database.settlement_events["survivors_on_horizon"].duplicate(true)
	invalid_survivor_fallback.fallback_choice_id = "accept"
	_assert(not invalid_survivor_fallback.is_valid(), "Fallback dodający mieszkańca musi unieważnić definicję.")

	var system = SettlementEventSystemScript.new()
	_test_deterministic_frozen_selection(system, database)
	_test_real_pressure_snapshot_commit(system, database)
	_test_pressure_budget_filters_and_recovery(system, database)
	_test_cooldown_group(system, database)
	_test_exact_preview_and_transaction(system, database)
	_test_survivor_preview_and_idempotence(system, database)
	_test_unavailable_cost_preview(system, database)
	_test_snapshot_contract(system, database)

	database.free()
	if _failures == 0:
		print("Settlement event system test passed: frozen pressure determinism, budget/severity/recovery filters, grouped cooldowns, exact preview and transactional idempotence work.")
		quit(0)
	else:
		push_error("Settlement event system test failed with %d assertion(s)." % _failures)
		quit(1)

func _test_deterministic_frozen_selection(system, database) -> void:
	var seed_value := _find_seed_with_event(system, database.settlement_events)
	_assert(seed_value > 0, "Test powinien znaleźć deterministyczny seed z wydarzeniem.")
	if seed_value <= 0:
		return
	var first_state = _event_ready_state(seed_value)
	var second_state = _event_ready_state(seed_value)
	var first_pressure := _pressure_for(first_state)
	var second_pressure := _pressure_for(second_state)
	var reversed_definitions: Dictionary = {}
	var definition_ids: Array[String] = []
	for event_id in database.settlement_events.keys():
		definition_ids.append(str(event_id))
	definition_ids.sort()
	definition_ids.reverse()
	for event_id in definition_ids:
		reversed_definitions[event_id] = database.settlement_events[event_id]

	var first_pending = system.prepare_event_for_day(first_state, database.settlement_events, first_pressure)
	var second_pending = system.prepare_event_for_day(second_state, reversed_definitions, second_pressure)
	_assert(first_pending != null and second_pending != null, "Znaleziony seed powinien utworzyć wydarzenie w obu stanach.")
	if first_pending == null or second_pending == null:
		return
	_assert(first_pending.instance_id == second_pending.instance_id, "Ten sam seed, dzień i PressureState muszą być niezależne od kolejności Dictionary.")
	_assert(first_pending.offer_snapshot != null, "Pending event powinien zapisać kompletną migawkę.")
	_assert(system.prepare_event_for_day(first_state, database.settlement_events, first_pressure) == first_pending, "Ponowne przygotowanie musi zwrócić zapisany event bez rerollu.")
	_assert(str(first_pressure.get("committed_event_id", "")) == str(first_pending.event_id), "PressureState powinien audytować dokładnie wybrane wydarzenie.")
	_assert(not bool(first_pressure.get("quiet_morning", true)), "Poranek z wydarzeniem nie może zostać oznaczony jako spokojny.")

	var supply_only := {"drifting_supply_crates": database.settlement_events["drifting_supply_crates"]}
	var conflict_seed := _find_seed_with_event(system, supply_only)
	_assert(conflict_seed > 0, "Fail-safe commitu wymaga seeda wybierającego kartę.")
	if conflict_seed > 0:
		var conflict_state = _event_ready_state(conflict_seed)
		var conflict_pressure := _pressure_for(conflict_state, {"quiet_morning": true})
		var conflicting_pending = system.prepare_event_for_day(conflict_state, supply_only, conflict_pressure)
		_assert(conflicting_pending == null and not conflict_state.has_pending_settlement_event(), "Sprzeczny commit PressureState nie może zostawić pending eventu bez zgodnego audytu.")
		_assert(bool(conflict_pressure.quiet_morning) and str(conflict_pressure.committed_event_id).is_empty(), "Odrzucony commit nie może nadpisać wcześniejszego spokojnego poranka.")

	# Live resources intentionally disagree, but a supplied PressureState freezes
	# all adaptive event weights for the day.
	var rich_state = _event_ready_state(91_101)
	var poor_state = _event_ready_state(91_101)
	rich_state.resources.set_amount(ResourceIdsScript.FOOD, 100)
	rich_state.resources.set_amount(ResourceIdsScript.HOPE, 90)
	rich_state.resources.set_amount(ResourceIdsScript.PLANKS, 80)
	poor_state.resources.set_amount(ResourceIdsScript.FOOD, 0)
	poor_state.resources.set_amount(ResourceIdsScript.HOPE, 5)
	poor_state.resources.set_amount(ResourceIdsScript.PLANKS, 0)
	var frozen_pressure := _pressure_for(rich_state, {"food_days": 1.25, "hope": 40, "basic_materials": 12})
	var frozen_pressure_copy := frozen_pressure.duplicate(true)
	var supply_event = database.settlement_events["drifting_supply_crates"]
	var rich_weight: float = system.event_weight(rich_state, supply_event, frozen_pressure)
	var poor_weight: float = system.event_weight(poor_state, supply_event, frozen_pressure_copy)
	_assert(is_equal_approx(rich_weight, poor_weight), "Zamrożone metryki nie mogą być drugi raz przeliczone z żywego stanu osady.")

	# Profile event knobs are real consumers, not decorative settings.
	var relief_profile = DifficultyProfileScript.new()
	relief_profile.relief_event_weight_multiplier = 2.0
	var relief_state = _event_ready_state(91_102, relief_profile)
	var boosted_weight: float = system.event_weight(relief_state, supply_event, _pressure_for(relief_state))
	_assert(boosted_weight > system.event_weight(rich_state, supply_event, _pressure_for(rich_state)), "Mnożnik wydarzeń pomocnych profilu powinien zmieniać realną wagę.")

func _test_real_pressure_snapshot_commit(system, database) -> void:
	# Dynamic loading keeps SettlementEventSystem decoupled from PressureState's
	# enum at parse time while still proving the real Resource contract.
	var pressure_script = ResourceLoader.load("res://scripts/data/PressureState.gd")
	_assert(pressure_script != null, "Runtime powinien udostępniać zapisany PressureState.")
	if pressure_script == null:
		return
	var state = _event_ready_state(91_201)
	var pressure = pressure_script.new()
	pressure.day = state.day
	pressure.pressure_budget = 3.0
	pressure.max_event_severity = 3
	pressure.population = state.get_alive_survivors().size()
	pressure.healthy_workers = pressure.population
	pressure.food_days = 2.0
	pressure.hope = 55
	pressure.platform_integrity = 75
	pressure.basic_materials = 20
	pressure.medicines = 3
	pressure.free_shelter = 2
	var definitions := {"drifting_supply_crates": database.settlement_events["drifting_supply_crates"]}
	var pending = system.prepare_event_for_day(state, definitions, pressure)
	_assert(pressure.has_committed_morning(), "Rzeczywisty PressureState powinien zapisać event albo spokojny poranek dokładnie raz.")
	_assert(pressure.is_valid_for_day(state.day), "PressureState powinien pozostać poprawną migawką po commicie selektora.")
	if pending == null:
		_assert(pressure.quiet_morning, "Brak karty powinien zostać odnotowany jako spokojny poranek.")
	else:
		_assert(pressure.committed_event_id == pending.event_id and is_equal_approx(pressure.spent_pressure_budget, 0.0), "Commit wydarzenia powinien zapisać ID i jego rzeczywisty koszt presji.")

func _test_pressure_budget_filters_and_recovery(system, database) -> void:
	var state = _event_ready_state(92_001)
	var torn_event = database.settlement_events["torn_mooring"]
	var supply_event = database.settlement_events["drifting_supply_crates"]
	var population_event = database.settlement_events["survivors_on_horizon"]

	var low_budget := _pressure_for(state, {"pressure_budget": 1.0, "max_event_severity": 3})
	_assert(not system.is_event_eligible(state, torn_event, database.settlement_events, low_budget), "Koszt presji 1.5 nie może wejść do budżetu 1.0.")
	var enough_budget := _pressure_for(state, {"pressure_budget": 2.0, "max_event_severity": 3})
	_assert(system.is_event_eligible(state, torn_event, database.settlement_events, enough_budget), "Wydarzenie powinno przejść przy wystarczającym budżecie i bez krytycznej bramki.")
	var severity_cap := _pressure_for(state, {"pressure_budget": 3.0, "max_event_severity": 1})
	_assert(not system.is_event_eligible(state, torn_event, database.settlement_events, severity_cap), "Severity 2 musi zostać odrzucone przy maksimum 1.")
	var major_cooldown := _pressure_for(state, {"pressure_budget": 3.0, "max_event_severity": 3, "major_event_cooldown_days_remaining": 1})
	_assert(not system.is_event_eligible(state, torn_event, database.settlement_events, major_cooldown), "Cooldown ciężkiego poranka powinien blokować severity 2+, nawet przy wolnym budżecie.")
	_assert(system.is_event_eligible(state, supply_event, database.settlement_events, major_cooldown), "Cooldown ciężkiego poranka nie powinien blokować łagodnego relief severity 1.")
	var critical_integrity := _pressure_for(state, {"pressure_budget": 3.0, "max_event_severity": 3, "platform_integrity": 20, "active_pressure_tags": ["integrity_critical"]})
	_assert(not system.is_event_eligible(state, torn_event, database.settlement_events, critical_integrity), "Exclusive tag powinien zapobiec dokładaniu ciężkiej karty do krytycznej integralności.")
	var storm_pressure := _pressure_for(state, {"pressure_budget": 3.0, "max_event_severity": 3, "reason_codes": ["storm_today"], "active_pressure_tags": ["storm_today"]})
	_assert(not system.is_event_eligible(state, torn_event, database.settlement_events, storm_pressure), "Exclusive tag powinien zapobiec spiętrzeniu ciężkiej karty cumowania ze sztormem.")

	var recovery_pressure := _pressure_for(state, {
		"pressure_budget": 3.0,
		"max_event_severity": 3,
		"prefer_relief": true,
		"reason_codes": ["food_low"],
		"recovery_roles": ["food"],
		"food_days": 0.8,
		"free_shelter": 2,
	})
	_assert(not system.is_event_eligible(state, torn_event, database.settlement_events, recovery_pressure), "Dzień regeneracji nie może dołożyć wydarzenia hardship.")
	_assert(system.is_event_eligible(state, supply_event, database.settlement_events, recovery_pressure), "Pomoc żywnościowa powinna być legalna w dniu regeneracji.")
	var recovery_definitions := {
		"drifting_supply_crates": supply_event,
		"shared_meal": database.settlement_events["shared_meal"],
		"torn_mooring": torn_event,
	}
	var recovery_analysis: Dictionary = system.selection_analysis(state, recovery_definitions, recovery_pressure, database.settlement_event_balance)
	var supply_entry := _analysis_candidate(recovery_analysis, "drifting_supply_crates")
	var meal_entry := _analysis_candidate(recovery_analysis, "shared_meal")
	_assert(recovery_analysis.rejected_candidates.has("torn_mooring"), "Dzień regeneracji powinien usunąć hardship z analizowanej puli.")
	_assert(not supply_entry.is_empty() and not meal_entry.is_empty(), "Dopasowana pomoc i inne bezpieczne karty powinny pozostać w puli, aby recovery było preferencją, a nie ukrytym wymuszeniem.")
	_assert(is_equal_approx(float(supply_entry.get("weight_breakdown", {}).get("recovery_multiplier", 1.0)), float(database.settlement_event_balance.recovery_match_weight_multiplier)), "Karta odpowiadająca potrzebie jedzenia powinna dostać jawny mnożnik recovery.")
	var neutral_recovery_balance = database.settlement_event_balance.duplicate(true)
	neutral_recovery_balance.recovery_match_weight_multiplier = 1.0
	var neutral_recovery_analysis: Dictionary = system.selection_analysis(state, recovery_definitions, recovery_pressure.duplicate(true), neutral_recovery_balance)
	_assert(_analysis_candidate_share(recovery_analysis, "drifting_supply_crates") > _analysis_candidate_share(neutral_recovery_analysis, "drifting_supply_crates"), "Mnożnik recovery powinien realnie zwiększać udział dopasowanej pomocy, nie usuwać pozostałych bezpiecznych kart.")

	var critical_population_state = _low_population_state(92_002)
	var only_population := {"survivors_on_horizon": population_event}
	var workforce_relief := _pressure_for(critical_population_state, {
		"pressure_budget": 0.0,
		"max_event_severity": 1,
		"prefer_relief": true,
		"food_days": 3.0,
		"critical_gates": ["workforce_critical"],
		"active_pressure_tags": ["workforce_critical"],
		"recovery_roles": ["workforce"],
		"free_shelter": 2,
	})
	var workforce_analysis: Dictionary = system.selection_analysis(critical_population_state, only_population, workforce_relief, database.settlement_event_balance)
	_assert(system.is_event_eligible(critical_population_state, population_event, database.settlement_events, workforce_relief), "Przy wolnym schronieniu i jedzeniu karta ludzi może być logiczną ulgą.")
	_assert(is_equal_approx(float(workforce_analysis.event_probability), 1.0) and workforce_analysis.forced_event_id == "survivors_on_horizon", "Kwalifikowany krytyczny brak załogi powinien jawnie wymusić kartę workforce i wyłączyć spokojny poranek.")
	var critical_pressure := _pressure_for(critical_population_state, {
		"pressure_budget": 0.0,
		"max_event_severity": 3,
		"prefer_relief": true,
		"food_days": 0.2,
		"critical_gates": ["food_critical", "workforce_critical"],
		"active_pressure_tags": ["food_critical", "workforce_critical"],
		"recovery_roles": ["food", "workforce"],
		"blocked_impact_tags": ["food_cost", "food_demand"],
		"free_shelter": 2,
	})
	_assert(not system.is_event_eligible(critical_population_state, population_event, database.settlement_events, critical_pressure), "Brak ludzi nie może teleportować karty populacji przez budżet i krytyczny brak jedzenia.")
	var critical_pending = system.prepare_event_for_day(critical_population_state, only_population, critical_pressure)
	_assert(critical_pending == null and bool(critical_pressure.get("quiet_morning", false)), "Gdy pomoc populacyjna jest nielogiczna, selektor powinien zapisać spokojny poranek.")

	var quiet_state = _event_ready_state(92_003)
	var quiet_pressure := _pressure_for(quiet_state, {"pressure_budget": 3.0, "max_event_severity": 0})
	var only_hardship := {"torn_mooring": torn_event}
	_assert(system.prepare_event_for_day(quiet_state, only_hardship, quiet_pressure) == null, "Brak wydarzeń mieszczących się w limicie severity powinien zapisać spokojny poranek.")
	quiet_pressure["max_event_severity"] = 3
	_assert(system.prepare_event_for_day(quiet_state, only_hardship, quiet_pressure) == null, "Zapisany spokojny poranek nie może być rerollowany po zmianie danych wejściowych.")

func _test_cooldown_group(system, database) -> void:
	var state = _event_ready_state(93_001)
	var supply_event = database.settlement_events["drifting_supply_crates"]
	var grouped_event = database.settlement_events["trader_at_dawn"]
	var definitions := {"trader_at_dawn": grouped_event}
	var past = SettlementEventStateScript.new()
	past.setup(supply_event, 3)
	var empty_ids: Array[String] = []
	past.resolve("recover_food", 3, "test", {}, empty_ids)
	state.settlement_event_history.append(past)
	state.day = 8
	state.begin_new_day_plan()
	_assert(not system.is_event_eligible(state, grouped_event, definitions), "Cooldown grupy powinien blokować inną kartę z tej samej rodziny.")
	state.day = 9
	state.begin_new_day_plan()
	_assert(system.is_event_eligible(state, grouped_event, definitions), "Karta z grupy powinna wrócić po pełnym cooldownie.")

	var once_state = _event_ready_state(93_002)
	var population_event = database.settlement_events["survivors_on_horizon"]
	var once_history = SettlementEventStateScript.new()
	once_history.setup(population_event, 3)
	once_history.resolve("reject", 3, "test", {}, empty_ids)
	once_history.cooldown_days = 0
	once_state.settlement_event_history.append(once_history)
	once_state.day = 20
	once_state.begin_new_day_plan()
	var renamed_candidate = population_event.duplicate(true)
	renamed_candidate.once_per_campaign = false
	renamed_candidate.cooldown_days = 0
	_assert(not system.is_event_eligible(once_state, renamed_candidate, {"survivors_on_horizon": renamed_candidate}), "Zamrożone once_per_campaign historii ma blokować ten sam history_key nawet po zmianie live definicji.")

func _test_exact_preview_and_transaction(system, database) -> void:
	var profile = DifficultyProfileScript.new()
	profile.hope_gain_multiplier = 1.2
	var state = _event_ready_state(94_001, profile)
	state.resources.set_amount(ResourceIdsScript.HOPE, 98)
	var meal_event = database.settlement_events["shared_meal"]
	var low_food_state = state.duplicate(true)
	low_food_state.resources.set_amount(ResourceIdsScript.FOOD, 7)
	_assert(not system.is_event_eligible(low_food_state, meal_event, database.settlement_events), "Karta ulgi nie może wejść, gdy jedyna zgodna z jej rolą decyzja wymaga nieosiągalnego kosztu żywności.")
	low_food_state.resources.set_amount(ResourceIdsScript.FOOD, 8)
	_assert(system.is_event_eligible(low_food_state, meal_event, database.settlement_events), "Wspólny posiłek powinien stać się dostępny dokładnie od jawnego minimum 8 żywności.")
	var meal_choice = meal_event.find_choice("hold_meal")
	var pending = SettlementEventStateScript.new()
	var meal_offer = system.build_offer_snapshot(state, meal_event, database.survivor_templates)
	pending.setup_offer(meal_offer, state.day)
	state.pending_settlement_event = pending
	state.settlement_event_roll_day = state.day

	var food_before: int = state.resources.get_amount(ResourceIdsScript.FOOD)
	var hope_before: int = state.resources.get_amount(ResourceIdsScript.HOPE)
	var history_before: int = state.settlement_event_history.size()
	var preview: Dictionary = system.preview_choice(state, meal_choice, database.survivor_templates)
	_assert(bool(preview.get("available", false)), "Wspólny posiłek powinien mieć wykonalny preview.")
	_assert(int(preview.applied_resource_deltas.get(ResourceIdsScript.FOOD, 0)) == -8, "Preview powinien pokazać dokładny koszt żywności.")
	_assert(int(preview.applied_resource_deltas.get(ResourceIdsScript.HOPE, 0)) == 2, "Preview powinien uwzględnić mnożnik Nadziei i clamp 98 -> 100.")
	_assert(str(preview.preview_summary).contains("Nadzieja +2") and not str(preview.preview_summary).contains("+9"), "Summary nie może powtarzać nieprzeliczonego tekstu z definicji.")
	_assert(state.resources.get_amount(ResourceIdsScript.FOOD) == food_before and state.resources.get_amount(ResourceIdsScript.HOPE) == hope_before, "Dry-run nie może mutować magazynu.")
	_assert(state.settlement_event_history.size() == history_before and state.pending_settlement_event == pending, "Dry-run nie może zmienić lifecycle wydarzenia.")

	var panel = SettlementEventPanelScript.new()
	root.add_child(panel)
	panel.present(pending, pending.offer_snapshot, state)
	var meal_button := panel.find_child("SettlementEventChoice_hold_meal", true, false) as Button
	_assert(meal_button != null and meal_button.text.contains("Nadzieja +2") and not meal_button.text.contains("+9"), "Panel powinien prezentować przekazany dokładny preview, nie statyczny opis.")
	panel.free()

	var result: Dictionary = system.resolve_choice(state, database.settlement_events, database.survivor_templates, "hold_meal")
	_assert(bool(result.get("success", false)), "Wspólny posiłek powinien zostać zastosowany po pełnej walidacji.")
	_assert(state.resources.get_amount(ResourceIdsScript.FOOD) - food_before == int(preview.applied_resource_deltas[ResourceIdsScript.FOOD]), "Zastosowana żywność musi zgadzać się z preview.")
	_assert(state.resources.get_amount(ResourceIdsScript.HOPE) - hope_before == int(preview.applied_resource_deltas[ResourceIdsScript.HOPE]), "Zastosowana Nadzieja musi zgadzać się z preview.")
	_assert(state.settlement_event_history.back().applied_resource_deltas == preview.applied_resource_deltas, "Historia powinna zapisać te same delty, które pokazano przed wyborem.")
	var food_after: int = state.resources.get_amount(ResourceIdsScript.FOOD)
	var duplicate: Dictionary = system.resolve_choice(state, database.settlement_events, database.survivor_templates, "hold_meal")
	_assert(not bool(duplicate.get("success", false)) and state.resources.get_amount(ResourceIdsScript.FOOD) == food_after, "Ponowne wywołanie nie może drugi raz pobrać kosztu.")

func _test_survivor_preview_and_idempotence(system, database) -> void:
	var state = _event_ready_state(95_001)
	var population_event = database.settlement_events["survivors_on_horizon"]
	var accept_choice = population_event.find_choice("accept")
	var duplicate_person_state = state.duplicate(true)
	duplicate_person_state.survivors.append(database.survivor_templates["zofia_kruk"].create_state())
	var duplicate_breakdown: Dictionary = system.event_weight_breakdown(duplicate_person_state, population_event, null, database.settlement_event_balance)
	_assert(not duplicate_breakdown.available_choice_impact_tags.has("population_gain"), "Wspólny pełny evaluator ma wyłączyć impact osoby już obecnej także podczas selekcji.")
	var duplicate_offer = system.build_offer_snapshot(duplicate_person_state, population_event, database.survivor_templates)
	_assert(
		duplicate_offer != null
		and not bool(duplicate_offer.find_choice("accept").available)
		and bool(duplicate_offer.find_choice("reject").available),
		"Oferta ma zamrozić niedostępny wybór osoby i nadal dostępny fallback."
	)
	var survivors_before: int = state.survivors.size()
	var preview: Dictionary = system.preview_choice(state, accept_choice, database.survivor_templates)
	_assert(preview.added_survivor_ids == ["zofia_kruk", "pawel_mazur"], "Preview powinien wymienić dokładnie osoby, które zostaną dodane.")
	_assert(state.survivors.size() == survivors_before, "Preview nowych osób nie może mutować kampanii.")

	var pending = SettlementEventStateScript.new()
	pending.setup_offer(system.build_offer_snapshot(state, population_event, database.survivor_templates), state.day)
	state.pending_settlement_event = pending
	state.settlement_event_roll_day = state.day
	var result: Dictionary = system.resolve_choice(state, database.settlement_events, database.survivor_templates, "accept")
	_assert(bool(result.get("success", false)), "Przyjęcie ocalałych powinno być wykonalne.")
	_assert(state.survivors.size() == survivors_before + 2, "Przyjęcie powinno dodać dokładnie dwie osoby.")
	_assert(state.find_survivor("zofia_kruk") != null and state.find_survivor("pawel_mazur") != null, "Nowi mieszkańcy muszą mieć stabilne ID.")
	if state.find_survivor("zofia_kruk") != null:
		_assert(state.find_survivor("zofia_kruk").status == SurvivorStateScript.Status.AVAILABLE, "Nowa osoba powinna być dostępna w bieżącym planie.")
	_assert(state.pending_settlement_event == null and state.settlement_event_history.size() == 1, "Rozstrzygnięcie powinno przenieść pending event do historii.")
	var duplicate: Dictionary = system.resolve_choice(state, database.settlement_events, database.survivor_templates, "accept")
	_assert(not bool(duplicate.get("success", false)) and state.survivors.size() == survivors_before + 2, "Nowi mieszkańcy nie mogą zostać dodani drugi raz.")

func _test_unavailable_cost_preview(system, database) -> void:
	var state = _event_ready_state(96_001)
	state.resources.set_amount(ResourceIdsScript.FOOD, 0)
	var trader = database.settlement_events["trader_at_dawn"]
	var medicine_choice = trader.find_choice("trade_for_medicine")
	var preview: Dictionary = system.preview_choice(state, medicine_choice, database.survivor_templates)
	_assert(not bool(preview.get("available", true)) and str(preview.get("reason", "")).contains("Jedzenie"), "Preview powinien używać tej samej walidacji kosztu co resolver.")


func _test_snapshot_contract(system, database) -> void:
	var state = _event_ready_state(97_001)
	var definition = database.settlement_events["drifting_supply_crates"]
	var offer = system.build_offer_snapshot(state, definition, database.survivor_templates)
	_assert(offer != null and offer.is_valid(), "System powinien zbudować samowystarczalną migawkę oferty.")
	if offer == null:
		return
	var pending = SettlementEventStateScript.new()
	pending.setup_offer(offer, state.day)
	state.pending_settlement_event = pending
	state.settlement_event_roll_day = state.day
	var frozen_result_text := str(offer.find_choice("recover_food").result_text)
	var live_choice = definition.find_choice("recover_food")
	var original_result_text := str(live_choice.result_text)
	live_choice.result_text = "ZMIENIONA DEFINICJA NIE MOŻE WPŁYNĄĆ NA PENDING"
	var result: Dictionary = system.resolve_choice(state, {}, {}, "recover_food")
	live_choice.result_text = original_result_text
	_assert(bool(result.get("success", false)) and str(result.get("message", "")) == frozen_result_text, "Resolver powinien czytać tekst i skutek wyłącznie z migawki, nie z żywej definicji.")
	_assert(state.settlement_event_history.back().offer_snapshot == null, "Historia po rozstrzygnięciu powinna zwolnić ciężką migawkę oferty.")
	_assert(state.settlement_event_history.back().history_key == "drifting_supply_crates" and state.settlement_event_history.back().cooldown_days == 4, "Historia powinna zachować zamrożony klucz i metadane cooldownu.")

	var drift_state = _event_ready_state(97_003)
	var drift_pending = SettlementEventStateScript.new()
	drift_pending.setup_offer(system.build_offer_snapshot(drift_state, definition, database.survivor_templates), drift_state.day)
	drift_state.pending_settlement_event = drift_pending
	drift_state.resources.add_amount(ResourceIdsScript.SCRAP, 1)
	var drift_food_before: int = drift_state.resources.get_amount(ResourceIdsScript.FOOD)
	var drift_result: Dictionary = system.resolve_choice(drift_state, {}, {}, "recover_food")
	_assert(not bool(drift_result.get("success", false)) and drift_state.resources.get_amount(ResourceIdsScript.FOOD) == drift_food_before, "Zmiana dowolnego zasobu z unii baseline ma odrzucić rozstrzygnięcie bez częściowej mutacji.")

func _find_seed_with_event(system, definitions: Dictionary, pressure_template: Dictionary = {}) -> int:
	for seed_value in range(10_000, 10_500):
		var state = _event_ready_state(seed_value)
		var pressure := _pressure_for(state, pressure_template)
		if system.prepare_event_for_day(state, definitions, pressure) != null:
			return seed_value
	return 0

func _analysis_candidate(analysis: Dictionary, event_id: String) -> Dictionary:
	for entry in analysis.get("candidates", []):
		if str(entry.get("event_id", "")) == event_id:
			return entry
	return {}

func _analysis_candidate_share(analysis: Dictionary, event_id: String) -> float:
	return float(_analysis_candidate(analysis, event_id).get("conditional_probability", 0.0))

func _pressure_for(state, overrides: Dictionary = {}) -> Dictionary:
	var alive_count: int = state.get_alive_survivors().size()
	var healthy_workers := 0
	for survivor in state.get_alive_survivors():
		if survivor.can_work():
			healthy_workers += 1
	var pressure := {
		"day": int(state.day),
		"band": 1,
		"strain": 0.5,
		"pressure_budget": 3.0,
		"max_event_severity": 3,
		"prefer_relief": false,
		"tutorial_protected": false,
		"critical_gates": [],
		"reason_codes": [],
		"active_pressure_tags": [],
		"recovery_roles": [],
		"blocked_impact_tags": [],
		"preferred_impact_tags": [],
		"population": alive_count,
		"food_days": 2.0,
		"average_hunger": 20.0,
		"max_hunger": 30.0,
		"hope": 55,
		"healthy_workers": healthy_workers,
		"platform_integrity": 75,
		"basic_materials": 20,
		"medicines": 3,
		"shelter_capacity": 5,
		"free_shelter": 2,
		"recent_dive_outcomes": ["success"],
		"recovery_days_remaining": 0,
		"major_event_cooldown_days_remaining": 0,
		"committed_event_id": "",
		"committed_event_tone": "",
		"committed_event_severity": 0,
		"spent_pressure_budget": 0.0,
		"quiet_morning": false,
	}
	pressure.merge(overrides, true)
	pressure["day"] = int(state.day)
	return pressure

func _event_ready_state(seed_value: int, profile = null):
	var state = GameStateScript.new()
	state.setup_new_campaign(seed_value, profile if profile != null else DifficultyProfileScript.new())
	state.tutorial.complete()
	state.day = 4
	state.begin_new_day_plan()
	state.settlement_event_roll_day = 0
	return state

func _low_population_state(seed_value: int):
	var state = _event_ready_state(seed_value)
	for index in range(1, state.survivors.size()):
		state.survivors[index].status = SurvivorStateScript.Status.DEAD
		state.survivors[index].health = 0
	return state

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Settlement event system assertion failed: " + message)
