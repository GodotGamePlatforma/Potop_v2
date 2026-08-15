class_name SettlementEventSystem
extends RefCounted

const DEFAULT_BALANCE_PATH := "res://data/balance/settlement_events.tres"
const EVENT_CADENCE_SALT := 73_041
const EVENT_CARD_SALT := 73_063
const MAX_EVENT_SEVERITY := 3

const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const RandomServiceScript := preload("res://scripts/core/RandomService.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const SettlementEventChoiceSnapshotScript := preload("res://scripts/data/SettlementEventChoiceSnapshot.gd")
const SettlementEventOfferSnapshotScript := preload("res://scripts/data/SettlementEventOfferSnapshot.gd")
const SettlementEventStateScript := preload("res://scripts/data/SettlementEventState.gd")

var _balance_validation_cache: Dictionary = {}

func prepare_event_for_day(
	state,
	event_definitions: Dictionary = {},
	pressure_state = null,
	balance_definition = null
) -> Resource:
	if state == null:
		return null
	var definitions := event_definitions if not event_definitions.is_empty() else _load_event_definitions()
	if state.has_method("has_pending_settlement_event") and state.has_pending_settlement_event():
		var pending_snapshot = state.pending_settlement_event.offer_snapshot
		if pending_snapshot == null or pending_snapshot.get_script() != SettlementEventOfferSnapshotScript:
			return null
		if not pending_snapshot.validation_errors().is_empty():
			return null
		if not _state_matches_offer(state.pending_settlement_event, pending_snapshot):
			return null
		if pressure_state != null and not _commit_offer(pressure_state, pending_snapshot):
			return null
		return state.pending_settlement_event
	if int(state.settlement_event_roll_day) == int(state.day):
		if pressure_state != null and not _has_committed_morning(pressure_state):
			_commit_quiet_morning(pressure_state)
		return null
	var balance = _resolve_balance(balance_definition)
	var analysis := selection_analysis(state, definitions, pressure_state, balance)
	if not bool(analysis.get("can_roll", false)):
		# A tutorial-protected morning is still a resolved morning.  Persist the
		# audit day together with the quiet commitment so the end-of-day candidate
		# satisfies the same durable contract as an actual event roll.  Invalid
		# definitions or balance data intentionally remain uncommitted and are
		# rejected by the persistence boundary instead of being hidden as "quiet".
		var no_roll_status := str(analysis.get("status", ""))
		if no_roll_status in ["before_minimum_day", "tutorial", "tutorial_protection"]:
			state.settlement_event_roll_day = int(state.day)
			_commit_quiet_morning(pressure_state)
		return null
	state.settlement_event_roll_day = int(state.day)
	var selected_event_id := str(analysis.get("selected_event_id", ""))
	if selected_event_id.is_empty():
		_commit_quiet_morning(pressure_state)
		return null
	var selected_definition = definitions.get(selected_event_id)
	if selected_definition == null:
		_commit_quiet_morning(pressure_state)
		return null
	return _set_pending_event(state, selected_definition, pressure_state)


func selection_analysis(
	state,
	event_definitions: Dictionary,
	pressure_state = null,
	balance_definition = null,
	cadence_sample_override: float = -1.0,
	card_sample_override: float = -1.0,
	ignore_roll_guard: bool = false
) -> Dictionary:
	var result := {
		"status": "invalid_state",
		"can_roll": false,
		"metrics": {},
		"candidates": [],
		"rejected_candidates": {},
		"base_event_probability": 0.0,
		"need_probability_bonus": 0.0,
		"event_probability": 0.0,
		"quiet_probability": 1.0,
		"total_event_weight": 0.0,
		"cadence_sample": 0.0,
		"card_sample": 0.0,
		"selected_event_id": "",
		"forced_event_id": "",
	}
	if state == null:
		return result
	var balance = _resolve_balance(balance_definition)
	if not _is_balance_valid(balance):
		result.status = "invalid_balance"
		return result
	if event_definitions.is_empty():
		result.status = "missing_event_definitions"
		return result
	if not ignore_roll_guard:
		if state.has_method("has_pending_settlement_event") and state.has_pending_settlement_event():
			var pending_snapshot = state.pending_settlement_event.offer_snapshot
			if (
				pending_snapshot == null
				or pending_snapshot.get_script() != SettlementEventOfferSnapshotScript
				or not pending_snapshot.validation_errors().is_empty()
				or not _state_matches_offer(state.pending_settlement_event, pending_snapshot)
			):
				result.status = "invalid_pending_snapshot"
				return result
			result.status = "pending_event"
			result.selected_event_id = str(pending_snapshot.event_id)
			return result
		if int(state.settlement_event_roll_day) == int(state.day):
			result.status = "already_rolled"
			return result
	if int(state.day) < int(balance.minimum_event_day):
		result.status = "before_minimum_day"
		return result
	if state.tutorial != null and state.tutorial.has_method("is_active") and state.tutorial.is_active():
		result.status = "tutorial"
		return result
	if int(state.current_phase) in [GamePhaseScript.Phase.GAME_OVER, GamePhaseScript.Phase.ENDING]:
		result.status = "terminal_phase"
		return result
	if pressure_state != null:
		if bool(_read_value(pressure_state, "tutorial_protected", false)):
			result.status = "tutorial_protection"
			return result
		if int(_read_value(pressure_state, "day", int(state.day))) != int(state.day):
			result.status = "stale_pressure_state"
			return result

	var metrics := _selection_metrics(state, pressure_state)
	result.metrics = metrics
	var candidate_ids: Array[String] = []
	for raw_event_id in event_definitions.keys():
		candidate_ids.append(str(raw_event_id))
	candidate_ids.sort()
	var candidates: Array = []
	var rejected: Dictionary = {}
	for event_id in candidate_ids:
		var definition = event_definitions.get(event_id)
		var reason := _event_ineligibility_reason(state, definition, event_definitions, pressure_state, balance)
		if reason.is_empty():
			candidates.append(definition)
		else:
			rejected[event_id] = reason
	# The workforce guarantee is evaluated from the hard-eligible pool. A soft
	# recovery preference may shape ordinary mornings, but cannot erase a card
	# that satisfies the explicit crisis guarantee.
	var forced_ids := _forced_workforce_candidate_ids(candidates, state, metrics, balance)
	if pressure_state != null:
		var before_recovery_filter: Array = candidates.duplicate()
		var recovery_candidates := _apply_recovery_preference(candidates, state, pressure_state, balance, metrics)
		candidates = []
		for definition in before_recovery_filter:
			if recovery_candidates.has(definition) or forced_ids.has(str(definition.id)):
				candidates.append(definition)
			else:
				rejected[str(definition.id)] = "recovery_preference"
	result.rejected_candidates = rejected

	var entries: Array[Dictionary] = []
	var total_event_weight := 0.0
	for definition in candidates:
		var breakdown := event_weight_breakdown(state, definition, pressure_state, balance, metrics)
		var final_weight := maxf(float(breakdown.get("final_weight", 0.0)), 0.0)
		if final_weight <= 0.0:
			rejected[str(definition.id)] = "zero_weight"
			continue
		var entry := {
			"event_id": str(definition.id),
			"category": str(definition.category),
			"tone": str(definition.tone),
			"recovery_role": str(definition.recovery_role),
			"base_weight": float(definition.base_weight),
			"final_weight": final_weight,
			"conditional_probability": 0.0,
			"morning_probability": 0.0,
			"weight_breakdown": breakdown,
		}
		entries.append(entry)
		total_event_weight += final_weight
	result.candidates = entries
	result.total_event_weight = total_event_weight
	result.rejected_candidates = rejected
	result.status = "ready"
	result.can_roll = true
	if entries.is_empty() or total_event_weight <= 0.0:
		return result
	var forced_entry_ids: Array[String] = []
	for entry in entries:
		var entry_id := str(entry.event_id)
		if forced_ids.has(entry_id):
			forced_entry_ids.append(entry_id)
	forced_ids = forced_entry_ids

	var base_event_probability := _base_event_probability(state, balance)
	var need_bonus := _need_probability_bonus(entries, balance)
	var event_probability := clampf(
		base_event_probability + need_bonus,
		float(balance.minimum_event_probability),
		float(balance.maximum_event_probability)
	)
	if not forced_ids.is_empty():
		event_probability = 1.0
	result.base_event_probability = base_event_probability
	result.need_probability_bonus = need_bonus
	result.event_probability = event_probability
	result.quiet_probability = 1.0 - event_probability

	var selectable_weight := 0.0
	for entry in entries:
		if forced_ids.is_empty() or forced_ids.has(str(entry.event_id)):
			selectable_weight += float(entry.final_weight)
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var is_selectable := forced_ids.is_empty() or forced_ids.has(str(entry.event_id))
		var conditional := float(entry.final_weight) / selectable_weight if is_selectable and selectable_weight > 0.0 else 0.0
		entry.conditional_probability = conditional
		entry.morning_probability = conditional * event_probability
		entries[index] = entry
	result.candidates = entries

	var cadence_sample := clampf(
		cadence_sample_override if cadence_sample_override >= 0.0 else RandomServiceScript.sample_for_seed(int(state.seed), int(state.day), EVENT_CADENCE_SALT),
		0.0,
		0.999999
	)
	var card_sample := clampf(
		card_sample_override if card_sample_override >= 0.0 else RandomServiceScript.sample_for_seed(int(state.seed), int(state.day), EVENT_CARD_SALT),
		0.0,
		0.999999
	)
	result.cadence_sample = cadence_sample
	result.card_sample = card_sample
	if cadence_sample >= event_probability:
		return result
	var selected_event_id := _select_weighted_entry(entries, selectable_weight, card_sample, forced_ids)
	result.selected_event_id = selected_event_id
	if not forced_ids.is_empty():
		result.forced_event_id = selected_event_id
	return result

func is_event_eligible(
	state,
	definition,
	event_definitions: Dictionary = {},
	pressure_state = null,
	balance_definition = null
) -> bool:
	var definitions := event_definitions if not event_definitions.is_empty() else _load_event_definitions()
	var balance = _resolve_balance(balance_definition)
	if not _is_balance_valid(balance):
		return false
	return _event_ineligibility_reason(state, definition, definitions, pressure_state, balance).is_empty()


func _event_ineligibility_reason(state, definition, _event_definitions: Dictionary, pressure_state, balance) -> String:
	if state == null:
		return "invalid_state"
	if balance == null:
		return "invalid_balance"
	if definition == null or not definition.has_method("is_valid") or not definition.is_valid():
		return "invalid_definition"
	if int(state.day) < maxi(int(balance.minimum_event_day), int(definition.minimum_day)):
		return "before_minimum_day"
	var crisis_active := state.story_flags != null and bool(state.story_flags.crisis_active)
	if pressure_state != null:
		crisis_active = bool(_read_value(pressure_state, "crisis_active", crisis_active))
	if crisis_active and not bool(definition.allow_during_crisis):
		return "crisis_blocked"

	var population: int = state.get_alive_survivors().size()
	if pressure_state != null:
		population = int(_read_value(pressure_state, "population", population))
	if population < int(definition.minimum_population) or population > int(definition.maximum_population):
		return "population_range"
	for resource_id in definition.required_resource_minimums.keys():
		if state.resources.get_amount(str(resource_id)) < int(definition.required_resource_minimums[resource_id]):
			return "required_resource:" + str(resource_id)
	var survivor_definitions := _load_survivor_definitions()
	var has_available_choice := false
	var fallback_available := false
	for choice in definition.choices:
		if choice == null:
			continue
		var evaluation := _evaluate_choice(state, choice, survivor_definitions)
		if bool(evaluation.get("available", false)):
			has_available_choice = true
			if str(choice.id) == str(definition.fallback_choice_id):
				fallback_available = true
	if not has_available_choice:
		return "no_available_choice"
	if not fallback_available:
		return "fallback_unavailable"

	for past_event in state.settlement_event_history:
		if past_event == null:
			continue
		var candidate_history_key := str(definition.history_key)
		var past_history_key := str(_read_value(past_event, "history_key", ""))
		if past_history_key.is_empty():
			past_history_key = str(past_event.event_id)
		var same_event := past_history_key == candidate_history_key
		var past_once := bool(_read_value(past_event, "once_per_campaign", false))
		if same_event and (past_once or bool(definition.once_per_campaign)):
			return "once_per_campaign"
		var past_cooldown_days := maxi(int(_read_value(past_event, "cooldown_days", 0)), 0)
		var direct_cooldown := maxi(past_cooldown_days, int(definition.cooldown_days))
		if same_event and int(state.day) - int(past_event.offered_day) <= direct_cooldown:
			return "event_cooldown"
		var past_cooldown_group := str(_read_value(past_event, "cooldown_group", ""))
		if past_cooldown_group.is_empty() or str(definition.cooldown_group).is_empty():
			continue
		if past_cooldown_group != str(definition.cooldown_group):
			continue
		var group_cooldown := maxi(int(definition.cooldown_days), past_cooldown_days)
		if int(state.day) - int(past_event.offered_day) <= group_cooldown:
			return "group_cooldown"

	if pressure_state == null:
		return ""
	var max_severity := clampi(int(_read_value(pressure_state, "max_event_severity", MAX_EVENT_SEVERITY)), 0, MAX_EVENT_SEVERITY)
	if int(definition.severity) > max_severity:
		return "severity_cap"
	if int(_read_value(pressure_state, "major_event_cooldown_days_remaining", 0)) > 0 and int(definition.severity) >= 2:
		return "major_event_cooldown"
	var pressure_budget := maxf(float(_read_value(pressure_state, "pressure_budget", 0.0)), 0.0)
	if float(definition.pressure_cost) > pressure_budget + 0.0001:
		return "pressure_budget"
	if bool(_read_value(pressure_state, "prefer_relief", false)) and str(definition.tone) == "hardship":
		return "hardship_on_recovery_day"
	var active_tags := _active_pressure_tags(pressure_state)
	for raw_tag in definition.exclusive_tags:
		if active_tags.has(str(raw_tag)):
			return "exclusive_tag:" + str(raw_tag)
	var blocked_impact_tags := _string_array(_read_value(pressure_state, "blocked_impact_tags", []))
	for raw_tag in definition.impact_tags:
		if blocked_impact_tags.has(str(raw_tag)):
			return "blocked_impact:" + str(raw_tag)
	return ""


func event_weight(state, definition, pressure_state = null, balance_definition = null) -> float:
	return float(event_weight_breakdown(state, definition, pressure_state, balance_definition).get("final_weight", 0.0))


func event_weight_breakdown(
	state,
	definition,
	pressure_state = null,
	balance_definition = null,
	metrics_override: Dictionary = {}
) -> Dictionary:
	var result := {
		"event_id": str(_read_value(definition, "id", "")),
		"base_weight": 0.0,
		"trigger_breakdown": [],
		"need_multiplier": 0.0,
		"tone_multiplier": 1.0,
		"recovery_multiplier": 1.0,
		"preferred_impact_multiplier": 1.0,
		"preferred_impact_tags": [],
		"available_choice_impact_tags": [],
		"raw_weight": 0.0,
		"minimum_weight": 0.0,
		"maximum_weight": 0.0,
		"final_weight": 0.0,
	}
	if state == null or definition == null:
		return result
	var balance = _resolve_balance(balance_definition)
	if balance == null or not balance.has_method("evaluate_trigger"):
		return result
	var base_weight := maxf(float(definition.base_weight), 0.0)
	result.base_weight = base_weight
	if base_weight <= 0.0:
		return result
	var metrics := metrics_override if not metrics_override.is_empty() else _selection_metrics(state, pressure_state)
	var available_choice_impacts := _available_choice_impact_tags(state, definition, metrics, balance)
	var need_multiplier := 1.0
	var trigger_breakdown: Array[Dictionary] = []
	var trigger_tags := _effective_trigger_tags(definition)
	for trigger_tag in trigger_tags:
		var tag_result: Dictionary = balance.evaluate_trigger(trigger_tag, metrics)
		var raw_multiplier := maxf(float(tag_result.get("multiplier", 0.0)), 0.0)
		var trigger_rule = balance.find_trigger_rule(trigger_tag) if balance.has_method("find_trigger_rule") else null
		var required_impacts := _string_array(_read_value(trigger_rule, "required_available_impact_tags", []))
		if raw_multiplier > 1.0 and not _has_available_required_impact(required_impacts, available_choice_impacts):
			tag_result = tag_result.duplicate(true)
			tag_result["unsuppressed_multiplier"] = raw_multiplier
			tag_result["multiplier"] = 1.0
			tag_result["suppressed_reason"] = "no_affordable_matching_choice"
		trigger_breakdown.append(tag_result)
		need_multiplier *= maxf(float(tag_result.get("multiplier", 0.0)), 0.0)
	var tone_multiplier := _profile_tone_multiplier(state, str(definition.tone))
	var recovery_multiplier := 1.0
	if pressure_state != null:
		var prefer_relief := bool(_read_value(pressure_state, "prefer_relief", false))
		if prefer_relief:
			if _event_matches_recovery(available_choice_impacts, _recovery_roles(pressure_state)):
				recovery_multiplier = float(balance.recovery_match_weight_multiplier)
	var preferred_impact_multiplier := 1.0
	var matched_impacts: Array[String] = []
	if pressure_state != null:
		var preferred_impacts := _string_array(_read_value(pressure_state, "preferred_impact_tags", []))
		for impact_tag in available_choice_impacts:
			if preferred_impacts.has(str(impact_tag)):
				matched_impacts.append(str(impact_tag))
				preferred_impact_multiplier *= float(balance.preferred_impact_weight_multiplier)
	var raw_weight := base_weight * need_multiplier * tone_multiplier * recovery_multiplier * preferred_impact_multiplier
	var minimum_weight := base_weight * float(balance.minimum_weight_multiplier)
	var maximum_weight := base_weight * float(balance.maximum_weight_multiplier)
	result.trigger_breakdown = trigger_breakdown
	result.need_multiplier = need_multiplier
	result.tone_multiplier = tone_multiplier
	result.recovery_multiplier = recovery_multiplier
	result.preferred_impact_multiplier = preferred_impact_multiplier
	result.preferred_impact_tags = matched_impacts
	result.available_choice_impact_tags = available_choice_impacts
	result.raw_weight = raw_weight
	result.minimum_weight = minimum_weight
	result.maximum_weight = maximum_weight
	result.final_weight = clampf(raw_weight, minimum_weight, maximum_weight)
	return result

func preview_choice(state, choice, survivor_definitions: Dictionary = {}) -> Dictionary:
	# Runtime pending przekazuje ChoiceSnapshot. Gałąź definicji pozostaje tym samym
	# czystym ewaluatorem używanym podczas selekcji i atomowego budowania oferty.
	if choice != null and choice.get_script() == SettlementEventChoiceSnapshotScript:
		var snapshot_survivor_ids: Array[String] = []
		var snapshot_survivor_names: Array[String] = []
		for survivor in choice.survivor_states:
			if survivor != null:
				snapshot_survivor_ids.append(str(survivor.id))
				snapshot_survivor_names.append(str(survivor.display_name))
		return {
			"available": bool(choice.available),
			"reason": str(choice.unavailable_reason),
			"applied_resource_deltas": choice.applied_resource_deltas.duplicate(true),
			"resource_amounts_after": {},
			"added_survivor_ids": snapshot_survivor_ids,
			"added_survivor_names": snapshot_survivor_names,
			"summary": str(choice.effect_summary),
			"preview_summary": str(choice.effect_summary),
		}
	var evaluation := _evaluate_choice(state, choice, survivor_definitions)
	if not bool(evaluation.get("available", false)):
		return {
			"available": false,
			"reason": str(evaluation.get("reason", "Decyzja jest niedostępna.")),
			"applied_resource_deltas": {},
			"resource_amounts_after": {},
			"added_survivor_ids": [],
			"added_survivor_names": [],
			"summary": str(evaluation.get("reason", "Decyzja jest niedostępna.")),
			"preview_summary": str(evaluation.get("reason", "Decyzja jest niedostępna.")),
		}
	var summary := str(evaluation.get("summary", "Bez zmian"))
	return {
		"available": true,
		"reason": "",
		"applied_resource_deltas": evaluation.get("applied_resource_deltas", {}).duplicate(true),
		"resource_amounts_after": evaluation.get("resource_amounts_after", {}).duplicate(true),
		"added_survivor_ids": Array(evaluation.get("added_survivor_ids", [])).duplicate(),
		"added_survivor_names": Array(evaluation.get("added_survivor_names", [])).duplicate(),
		"summary": summary,
		"preview_summary": summary,
	}

func resolve_choice(
	state,
	_event_definitions: Dictionary,
	_survivor_definitions: Dictionary,
	choice_id: String
) -> Dictionary:
	if state == null or not state.has_method("has_pending_settlement_event") or not state.has_pending_settlement_event():
		return {"success": false, "message": "Brak wydarzenia oczekującego na decyzję."}
	if state.resources == null:
		return {"success": false, "message": "Brak magazynu kampanii."}
	var event_state = state.pending_settlement_event
	if int(event_state.offered_day) != int(state.day):
		return {"success": false, "message": "Wydarzenie nie należy do bieżącego dnia."}
	if not event_state.has_method("resolve"):
		return {"success": false, "message": "Stan wydarzenia nie obsługuje rozstrzygnięcia."}
	var offer = event_state.offer_snapshot
	if offer == null or offer.get_script() != SettlementEventOfferSnapshotScript:
		return {"success": false, "message": "Brak zapisanej migawki wydarzenia."}
	if not offer.validation_errors().is_empty():
		return {"success": false, "message": "Migawka wydarzenia jest uszkodzona."}
	if not _state_matches_offer(event_state, offer):
		return {"success": false, "message": "Migawka nie odpowiada oczekującemu wydarzeniu."}
	var choice = offer.find_choice(choice_id)
	if choice == null:
		return {"success": false, "message": "Nieznana decyzja wydarzenia."}
	if not bool(choice.available):
		return {"success": false, "message": str(choice.unavailable_reason)}
	var resource_amounts_after: Dictionary = {}
	for raw_resource_id in offer.expected_resource_baseline.keys():
		var resource_id := str(raw_resource_id)
		if not ResourceIdsScript.all().has(resource_id):
			return {"success": false, "message": "Migawka używa nieznanego zasobu."}
		var expected_amount := int(offer.expected_resource_baseline[raw_resource_id])
		if state.resources.get_amount(resource_id) != expected_amount:
			return {"success": false, "message": "Stan zasobów zmienił się od chwili złożenia oferty."}
	for raw_resource_id in choice.applied_resource_deltas.keys():
		var resource_id := str(raw_resource_id)
		if not offer.expected_resource_baseline.has(resource_id):
			return {"success": false, "message": "Skutek decyzji nie należy do zapisanej bazy zasobów."}
		var after := int(offer.expected_resource_baseline[resource_id]) + int(choice.applied_resource_deltas[raw_resource_id])
		if after < 0 or (resource_id in [ResourceIdsScript.HOPE, ResourceIdsScript.PLATFORM_INTEGRITY] and after > 100):
			return {"success": false, "message": "Skutek decyzji wykracza poza dozwolony zakres zasobu."}
		resource_amounts_after[resource_id] = after
	var new_survivors: Array = []
	var added_survivor_ids: Array[String] = []
	for survivor_snapshot in choice.survivor_states:
		if survivor_snapshot == null:
			return {"success": false, "message": "Migawka decyzji zawiera pustego mieszkańca."}
		var survivor_id := str(survivor_snapshot.id)
		if survivor_id.is_empty() or added_survivor_ids.has(survivor_id) or state.find_survivor(survivor_id) != null:
			return {"success": false, "message": "Migawka decyzji ma niepoprawną relację mieszkańca."}
		for raw_related_id in survivor_snapshot.relationship_links.keys():
			var related_id := str(raw_related_id)
			if related_id.is_empty() or (state.find_survivor(related_id) == null and not _snapshot_has_survivor(choice, related_id)):
				return {"success": false, "message": "Migawka decyzji wskazuje nieznaną relację mieszkańca."}
		added_survivor_ids.append(survivor_id)
		new_survivors.append(survivor_snapshot.duplicate(true))

	# Wszystkie kandydaty są gotowe. Dopiero teraz zaczyna się mutacja stanu.
	var resource_ids := _sorted_resource_ids(resource_amounts_after)
	for resource_id in resource_ids:
		state.resources.set_amount(resource_id, int(resource_amounts_after[resource_id]))
	for survivor in new_survivors:
		state.survivors.append(survivor)

	var applied_deltas: Dictionary = choice.applied_resource_deltas.duplicate(true)
	event_state.resolve(choice_id, int(state.day), str(choice.result_text), applied_deltas, added_survivor_ids)
	state.settlement_event_history.append(event_state)
	state.pending_settlement_event = null
	if state.current_day_plan != null and not bool(state.current_day_plan.locked):
		state.current_day_plan.sync_from_state(state)
	return {
		"success": true,
		"message": str(choice.result_text),
		"summary": str(choice.effect_summary),
		"applied_resource_deltas": applied_deltas,
		"added_survivor_ids": added_survivor_ids,
	}

func _evaluate_choice(state, choice, survivor_definitions: Dictionary) -> Dictionary:
	if state == null or choice == null:
		return {"available": false, "reason": "Brak danych decyzji."}
	if state.resources == null:
		return {"available": false, "reason": "Brak magazynu kampanii."}

	var reason := _choice_resource_unavailability_reason(state, choice)

	var new_survivors: Array = []
	var added_survivor_ids: Array[String] = []
	var added_survivor_names: Array[String] = []
	for raw_survivor_id in choice.survivor_definition_ids:
		var survivor_id := str(raw_survivor_id)
		if not survivor_definitions.has(survivor_id):
			if reason.is_empty():
				reason = "Brak danych mieszkańca."
			continue
		if added_survivor_ids.has(survivor_id):
			if reason.is_empty():
				reason = "Decyzja powtarza tę samą osobę."
			continue
		var survivor_definition = survivor_definitions.get(survivor_id)
		var survivor = survivor_definition.create_state() if survivor_definition != null and survivor_definition.has_method("create_state") else null
		if survivor == null:
			if reason.is_empty():
				reason = "Nie udało się utworzyć mieszkańca %s." % survivor_id
			continue
		new_survivors.append(survivor)
		added_survivor_ids.append(str(survivor.id))
		added_survivor_names.append(str(survivor.display_name))
		if state.find_survivor(survivor_id) != null and reason.is_empty():
			reason = "Ta osoba jest już w Przystani."

	var applied_deltas: Dictionary = {}
	var resource_amounts_after: Dictionary = {}
	var resource_ids := _sorted_resource_ids(choice.resource_deltas)
	for resource_id in resource_ids:
		var before: int = state.resources.get_amount(resource_id)
		var delta := _scaled_resource_delta(state, resource_id, int(choice.resource_deltas[resource_id]))
		var after: int = before + delta
		if resource_id in [ResourceIdsScript.HOPE, ResourceIdsScript.PLATFORM_INTEGRITY]:
			after = clampi(after, 0, 100)
		else:
			after = maxi(after, 0)
		resource_amounts_after[resource_id] = after
		applied_deltas[resource_id] = after - before

	return {
		"available": reason.is_empty(),
		"reason": reason,
		"applied_resource_deltas": applied_deltas,
		"resource_amounts_after": resource_amounts_after,
		"added_survivor_ids": added_survivor_ids,
		"added_survivor_names": added_survivor_names,
		"new_survivors": new_survivors,
		"summary": _preview_summary(applied_deltas, added_survivor_names),
	}

func build_offer_snapshot(state, definition, survivor_definitions: Dictionary = {}) -> Resource:
	# Jedyna granica przejścia z edytowalnych definicji do trwałej oferty.
	# Po zwrocie runtime nie może już konsultować live `.tres` tej instancji.
	if state == null or state.resources == null or definition == null or not definition.has_method("is_valid") or not definition.is_valid():
		return null
	var definitions := survivor_definitions if not survivor_definitions.is_empty() else _load_survivor_definitions()
	var snapshot = SettlementEventOfferSnapshotScript.new()
	snapshot.event_id = str(definition.id)
	snapshot.history_key = str(definition.history_key)
	snapshot.category = str(definition.category)
	snapshot.title = str(definition.title)
	snapshot.body = str(definition.body)
	snapshot.fallback_choice_id = str(definition.fallback_choice_id)
	snapshot.tone = str(definition.tone)
	snapshot.severity = int(definition.severity)
	snapshot.pressure_cost = float(definition.pressure_cost)
	snapshot.cooldown_group = str(definition.cooldown_group)
	snapshot.cooldown_days = int(definition.cooldown_days)
	snapshot.once_per_campaign = bool(definition.once_per_campaign)
	var baseline: Dictionary = {}
	for choice in definition.choices:
		if choice == null:
			return null
		for raw_resource_id in choice.resource_deltas.keys():
			var resource_id := str(raw_resource_id)
			if not ResourceIdsScript.all().has(resource_id):
				return null
			baseline[resource_id] = state.resources.get_amount(resource_id)
	snapshot.expected_resource_baseline = baseline
	for choice in definition.choices:
		var evaluation := _evaluate_choice(state, choice, definitions)
		var choice_snapshot = SettlementEventChoiceSnapshotScript.new()
		choice_snapshot.id = str(choice.id)
		choice_snapshot.label = str(choice.label)
		choice_snapshot.preview = str(choice.preview)
		choice_snapshot.result_text = str(choice.result_text)
		choice_snapshot.available = bool(evaluation.get("available", false))
		choice_snapshot.unavailable_reason = str(evaluation.get("reason", ""))
		choice_snapshot.applied_resource_deltas = evaluation.get("applied_resource_deltas", {}).duplicate(true)
		choice_snapshot.impact_tags.assign(_string_array(choice.impact_tags))
		choice_snapshot.effect_summary = str(evaluation.get("summary", "Bez zmian"))
		for survivor in evaluation.get("new_survivors", []):
			choice_snapshot.survivor_states.append(survivor.duplicate(true))
		snapshot.choices.append(choice_snapshot)
	return snapshot if snapshot.validation_errors().is_empty() else null


func _set_pending_event(state, definition, pressure_state = null) -> Resource:
	var snapshot = build_offer_snapshot(state, definition)
	if snapshot == null or not _commit_offer(pressure_state, snapshot):
		return null
	var event_state = SettlementEventStateScript.new()
	event_state.setup_offer(snapshot, int(state.day))
	state.pending_settlement_event = event_state
	state.settlement_event_roll_day = int(state.day)
	return event_state

func _commit_offer(pressure_state, snapshot) -> bool:
	if pressure_state == null or snapshot == null:
		return pressure_state == null and snapshot != null
	if pressure_state is Object and pressure_state.has_method("commit_event"):
		return bool(pressure_state.commit_event(str(snapshot.event_id), str(snapshot.tone), int(snapshot.severity), float(snapshot.pressure_cost)))
	if _has_committed_morning(pressure_state):
		return (
			not bool(_read_value(pressure_state, "quiet_morning", false))
			and str(_read_value(pressure_state, "committed_event_id", "")) == str(snapshot.event_id)
			and str(_read_value(pressure_state, "committed_event_tone", "")) == str(snapshot.tone)
			and int(_read_value(pressure_state, "committed_event_severity", -1)) == int(snapshot.severity)
			and is_equal_approx(float(_read_value(pressure_state, "spent_pressure_budget", -1.0)), float(snapshot.pressure_cost))
		)
	_set_value_if_present(pressure_state, "committed_event_id", str(snapshot.event_id))
	_set_value_if_present(pressure_state, "committed_event_tone", str(snapshot.tone))
	_set_value_if_present(pressure_state, "committed_event_severity", int(snapshot.severity))
	_set_value_if_present(pressure_state, "spent_pressure_budget", float(snapshot.pressure_cost))
	_set_value_if_present(pressure_state, "quiet_morning", false)
	return true

func _has_committed_morning(pressure_state) -> bool:
	if pressure_state == null:
		return false
	if pressure_state is Object and pressure_state.has_method("has_committed_morning"):
		return bool(pressure_state.has_committed_morning())
	return bool(_read_value(pressure_state, "quiet_morning", false)) or not str(_read_value(pressure_state, "committed_event_id", "")).is_empty()

func _commit_quiet_morning(pressure_state) -> void:
	if pressure_state == null:
		return
	if pressure_state is Object and pressure_state.has_method("commit_quiet_morning"):
		pressure_state.commit_quiet_morning()
		return
	_set_value_if_present(pressure_state, "committed_event_id", "")
	_set_value_if_present(pressure_state, "committed_event_tone", "")
	_set_value_if_present(pressure_state, "committed_event_severity", 0)
	_set_value_if_present(pressure_state, "spent_pressure_budget", 0.0)
	_set_value_if_present(pressure_state, "quiet_morning", true)

func _apply_recovery_preference(candidates: Array, state, pressure_state, balance, metrics: Dictionary) -> Array:
	if pressure_state == null or not bool(_read_value(pressure_state, "prefer_relief", false)):
		return candidates
	var safe_candidates: Array = []
	for definition in candidates:
		if _string_array(balance.recovery_safe_tones).has(str(definition.tone)):
			safe_candidates.append(definition)
	if safe_candidates.is_empty():
		return []
	var roles := _recovery_roles(pressure_state)
	if roles.is_empty():
		return safe_candidates
	var has_matching_candidate := false
	for definition in safe_candidates:
		if _event_matches_recovery(_available_choice_impact_tags(state, definition, metrics, balance), roles):
			has_matching_candidate = true
			break
	# A named recovery need must not summon an unrelated "gift". If the pool has
	# no matching safe card, the quiet-day candidate is the logical relief. When
	# a match exists, keep the other safe cards as a real baseline so the
	# configurable recovery multiplier changes the actual weighted distribution.
	return safe_candidates if has_matching_candidate else []

func _event_matches_recovery(available_impact_tags: Array[String], recovery_roles: Array[String]) -> bool:
	if available_impact_tags.is_empty() or recovery_roles.is_empty():
		return false
	for raw_impact_tag in available_impact_tags:
		var impact_tag := str(raw_impact_tag)
		for role in recovery_roles:
			if _impact_tag_matches_role(impact_tag, role):
				return true
	return false

func _impact_tag_matches_role(impact_tag: String, role: String) -> bool:
	match role:
		"food":
			return impact_tag in ["food_relief"]
		"materials":
			return impact_tag in ["material_relief"]
		"workforce":
			return impact_tag in ["workforce_relief", "population_gain"]
		"hope":
			return impact_tag in ["hope_relief"]
		"integrity":
			return impact_tag in ["integrity_relief"]
		"medicine":
			return impact_tag in ["medicine_relief"]
	return false

func _available_choice_impact_tags(state, definition, metrics: Dictionary, balance) -> Array[String]:
	var result: Array[String] = []
	if state == null or definition == null:
		return result
	var survivor_definitions := _load_survivor_definitions()
	for choice in definition.choices:
		if choice == null:
			continue
		var evaluation := _evaluate_choice(state, choice, survivor_definitions)
		if not bool(evaluation.get("available", false)):
			continue
		var newcomer_count := _string_array(_read_value(choice, "survivor_definition_ids", [])).size()
		var population_expansion_supported := newcomer_count <= 0 or _population_expansion_is_supported(newcomer_count, metrics, balance)
		for raw_tag in _string_array(_read_value(choice, "impact_tags", [])):
			var tag := str(raw_tag)
			if not population_expansion_supported and tag in ["workforce_relief", "population_gain"]:
				continue
			if not tag.is_empty() and not result.has(tag):
				result.append(tag)
	return result

func _choice_resource_unavailability_reason(state, choice) -> String:
	if state == null or choice == null or state.resources == null:
		return "Brak magazynu kampanii."
	for resource_id in choice.resource_deltas.keys():
		var delta := int(choice.resource_deltas[resource_id])
		if str(resource_id) in [ResourceIdsScript.HOPE, ResourceIdsScript.PLATFORM_INTEGRITY]:
			continue
		if delta < 0 and state.resources.get_amount(str(resource_id)) < -delta:
			return "Brakuje: %s (%d)." % [ResourceIdsScript.display_name(str(resource_id)), -delta]
	return ""

func _has_available_required_impact(required_impacts: Array[String], available_impact_tags: Array[String]) -> bool:
	if required_impacts.is_empty():
		return false
	for impact_tag in required_impacts:
		if available_impact_tags.has(impact_tag):
			return true
	return false

func _recovery_roles(pressure_state) -> Array[String]:
	return _string_array(_read_value(pressure_state, "recovery_roles", []))

func _active_pressure_tags(pressure_state) -> Array[String]:
	return _string_array(_read_value(pressure_state, "active_pressure_tags", []))

func _effective_trigger_tags(definition) -> Array[String]:
	if definition != null and definition.has_method("effective_trigger_tags"):
		return definition.effective_trigger_tags()
	var result: Array[String] = []
	if definition != null:
		result.assign(definition.trigger_tags)
	return result


func _selection_metrics(state, pressure_state = null) -> Dictionary:
	var alive_count: int = state.get_alive_survivors().size()
	var healthy_workers := _healthy_worker_count(state)
	var food_days := maxf(float(state.get_food_days_left()), 0.0)
	var hope: int = state.resources.get_amount(ResourceIdsScript.HOPE)
	var integrity: int = state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY)
	var material_stock: int = state.resources.get_amount(ResourceIdsScript.PLANKS) + state.resources.get_amount(ResourceIdsScript.SCRAP)
	var medicine_stock: int = state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS)
	var free_shelter: int = _shelter_capacity(state) - alive_count
	if pressure_state != null:
		alive_count = int(_read_value(pressure_state, "population", alive_count))
		healthy_workers = int(_read_value(pressure_state, "healthy_workers", healthy_workers))
		food_days = maxf(float(_read_value(pressure_state, "food_days", food_days)), 0.0)
		hope = int(_read_value(pressure_state, "hope", hope))
		integrity = int(_read_value(pressure_state, "platform_integrity", integrity))
		material_stock = int(_read_value(pressure_state, "basic_materials", material_stock))
		medicine_stock = int(_read_value(pressure_state, "medicines", medicine_stock))
		free_shelter = int(_read_value(pressure_state, "free_shelter", free_shelter))
	return {
		"alive_count": alive_count,
		"healthy_workers": healthy_workers,
		"food_days": food_days,
		"hope": hope,
		"integrity": integrity,
		"material_stock": material_stock,
		"medicine_stock": medicine_stock,
		"free_shelter": free_shelter,
	}


func _base_event_probability(state, balance) -> float:
	var profile = _read_value(state, "difficulty_profile", null)
	var quiet_percentage := float(_read_value(profile, "quiet_day_weight", float(balance.fallback_quiet_day_percentage)))
	return clampf(
		1.0 - clampf(quiet_percentage / 100.0, 0.0, 1.0),
		float(balance.minimum_event_probability),
		float(balance.maximum_event_probability)
	)


func _need_probability_bonus(entries: Array[Dictionary], balance) -> float:
	var active_bonuses: Dictionary = {}
	for entry in entries:
		var breakdown: Dictionary = entry.get("weight_breakdown", {})
		for tag_result in breakdown.get("trigger_breakdown", []):
			var trigger_tag := str(tag_result.get("trigger_tag", ""))
			if trigger_tag.is_empty():
				continue
			var rule = balance.find_trigger_rule(trigger_tag)
			if rule != null and float(tag_result.get("multiplier", 1.0)) >= float(rule.bonus_activation_multiplier):
				active_bonuses[trigger_tag] = maxf(float(rule.event_probability_bonus), 0.0)
	var total := 0.0
	for raw_bonus in active_bonuses.values():
		total += float(raw_bonus)
	return minf(total, float(balance.maximum_need_probability_bonus))


func _forced_workforce_candidate_ids(definitions: Array, state, metrics: Dictionary, balance) -> Array[String]:
	var result: Array[String] = []
	if not bool(balance.force_workforce_recovery):
		return result
	var workforce_is_critical := (
		int(metrics.get("alive_count", 999)) <= int(balance.critical_alive_maximum)
		or int(metrics.get("healthy_workers", 999)) <= int(balance.critical_healthy_workers_maximum)
	)
	if not workforce_is_critical:
		return result
	for definition in definitions:
		if definition == null or str(definition.recovery_role) != str(balance.forced_recovery_role):
			continue
		var available_impacts := _available_choice_impact_tags(state, definition, metrics, balance)
		if not available_impacts.has("workforce_relief") and not available_impacts.has("population_gain"):
			continue
		var newcomer_count := _maximum_new_survivor_count(definition)
		if newcomer_count <= 0:
			continue
		if not _population_expansion_is_supported(newcomer_count, metrics, balance):
			continue
		result.append(str(definition.id))
	return result


func _population_expansion_is_supported(newcomer_count: int, metrics: Dictionary, balance) -> bool:
	if newcomer_count <= 0 or balance == null:
		return newcomer_count <= 0
	var effective_alive := maxi(int(metrics.get("alive_count", 0)), 1)
	var free_shelter := int(metrics.get("free_shelter", 0))
	if free_shelter < maxi(int(balance.forced_minimum_free_shelter), newcomer_count):
		return false
	var projected_population := effective_alive + newcomer_count
	var projected_food_days := maxf(float(metrics.get("food_days", 0.0)), 0.0) * float(effective_alive) / float(projected_population)
	return projected_food_days + 0.0001 >= float(balance.forced_minimum_food_days)


func _maximum_new_survivor_count(definition) -> int:
	var result := 0
	if definition == null:
		return result
	for choice in definition.choices:
		if choice == null:
			continue
		result = maxi(result, _string_array(_read_value(choice, "survivor_definition_ids", [])).size())
	return result


func _select_weighted_entry(
	entries: Array[Dictionary],
	total_weight: float,
	sample: float,
	allowed_ids: Array[String] = []
) -> String:
	if entries.is_empty() or total_weight <= 0.0:
		return ""
	var cursor := sample * total_weight
	var last_selectable_id := ""
	for entry in entries:
		var event_id := str(entry.event_id)
		if not allowed_ids.is_empty() and not allowed_ids.has(event_id):
			continue
		last_selectable_id = event_id
		cursor -= float(entry.final_weight)
		if cursor <= 0.0:
			return event_id
	return last_selectable_id

func _profile_tone_multiplier(state, tone: String) -> float:
	var profile = _read_value(state, "difficulty_profile", null)
	match tone:
		"relief":
			return maxf(float(_read_value(profile, "relief_event_weight_multiplier", 1.0)), 0.0)
		"hardship":
			return maxf(float(_read_value(profile, "hardship_event_weight_multiplier", 1.0)), 0.0)
	return 1.0


func _resolve_balance(balance_definition = null):
	if balance_definition != null:
		return balance_definition
	return ResourceLoader.load(DEFAULT_BALANCE_PATH)


func _is_balance_valid(balance) -> bool:
	if balance == null or not balance.has_method("is_valid"):
		return false
	var instance_id := int(balance.get_instance_id())
	if _balance_validation_cache.has(instance_id):
		return bool(_balance_validation_cache[instance_id])
	var valid := bool(balance.is_valid())
	_balance_validation_cache[instance_id] = valid
	return valid

func _healthy_worker_count(state) -> int:
	var result := 0
	for survivor in state.get_alive_survivors():
		if survivor.can_work():
			result += 1
	return result

func _shelter_capacity(state) -> int:
	var community_house = state.find_building_by_definition("community_house")
	if community_house == null or not community_house.is_active():
		return 3
	var definition = ResourceLoader.load("res://data/buildings/community_house.tres")
	var level_definition = definition.get_level_definition(int(community_house.level)) if definition != null else null
	return maxi(int(level_definition.capabilities.get("shelter_capacity", 3)), 3) if level_definition != null else 3

func _scaled_resource_delta(state, resource_id: String, delta: int) -> int:
	if resource_id != ResourceIdsScript.HOPE or delta == 0 or state.difficulty_profile == null:
		return delta
	var multiplier := float(state.difficulty_profile.hope_gain_multiplier) if delta > 0 else float(state.difficulty_profile.hope_loss_multiplier)
	var magnitude := maxi(int(round(absf(float(delta)) * multiplier)), 1)
	return magnitude if delta > 0 else -magnitude

func _sorted_resource_ids(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for resource_id in ResourceIdsScript.all():
		if values.has(resource_id):
			result.append(resource_id)
	var remaining: Array[String] = []
	for raw_resource_id in values.keys():
		var resource_id := str(raw_resource_id)
		if not result.has(resource_id):
			remaining.append(resource_id)
	remaining.sort()
	result.append_array(remaining)
	return result

func _preview_summary(applied_deltas: Dictionary, added_survivor_names: Array[String]) -> String:
	var parts: Array[String] = []
	for resource_id in _sorted_resource_ids(applied_deltas):
		var delta := int(applied_deltas[resource_id])
		if delta == 0:
			continue
		var sign := "+" if delta > 0 else ""
		parts.append("%s %s%d" % [ResourceIdsScript.display_name(resource_id), sign, delta])
	if not added_survivor_names.is_empty():
		parts.append("Nowi mieszkańcy: %s" % ", ".join(added_survivor_names))
	return "  •  ".join(parts) if not parts.is_empty() else "Bez zmian"


func _snapshot_has_survivor(choice_snapshot, survivor_id: String) -> bool:
	if choice_snapshot == null:
		return false
	for survivor in choice_snapshot.survivor_states:
		if survivor != null and str(survivor.id) == survivor_id:
			return true
	return false


func _state_matches_offer(event_state, offer_snapshot) -> bool:
	if event_state == null or offer_snapshot == null:
		return false
	return (
		str(event_state.event_id) == str(offer_snapshot.event_id)
		and str(event_state.history_key) == str(offer_snapshot.history_key)
		and str(event_state.category) == str(offer_snapshot.category)
		and str(event_state.tone) == str(offer_snapshot.tone)
		and int(event_state.severity) == int(offer_snapshot.severity)
		and is_equal_approx(float(event_state.pressure_cost), float(offer_snapshot.pressure_cost))
		and str(event_state.cooldown_group) == str(offer_snapshot.cooldown_group)
		and int(event_state.cooldown_days) == int(offer_snapshot.cooldown_days)
		and bool(event_state.once_per_campaign) == bool(offer_snapshot.once_per_campaign)
	)

func _read_value(source, property_name: String, fallback):
	if source == null:
		return fallback
	if source is Dictionary:
		return source.get(property_name, fallback)
	if source is Object:
		for property_data in source.get_property_list():
			if str(property_data.get("name", "")) == property_name:
				return source.get(property_name)
	return fallback

func _set_value_if_present(target, property_name: String, value) -> void:
	if target == null:
		return
	if target is Dictionary:
		target[property_name] = value
		return
	if target is Object:
		for property_data in target.get_property_list():
			if str(property_data.get("name", "")) == property_name:
				target.set(property_name, value)
				return

func _string_array(raw_value) -> Array[String]:
	var result: Array[String] = []
	if not (raw_value is Array or raw_value is PackedStringArray):
		return result
	for raw_item in raw_value:
		var item := str(raw_item)
		if not item.is_empty() and not result.has(item):
			result.append(item)
	return result

func _load_event_definitions() -> Dictionary:
	var result: Dictionary = {}
	var path := "res://data/events"
	for file_name in DirAccess.get_files_at(path):
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var definition = ResourceLoader.load(path.path_join(file_name))
		if definition != null and "id" in definition:
			result[str(definition.id)] = definition
	return result


func _load_survivor_definitions() -> Dictionary:
	var result: Dictionary = {}
	var path := "res://data/survivor_templates"
	for file_name in DirAccess.get_files_at(path):
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var definition = ResourceLoader.load(path.path_join(file_name))
		if definition != null and "id" in definition:
			result[str(definition.id)] = definition
	return result
