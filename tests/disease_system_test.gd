extends SceneTree

const DiseaseSystemScript := preload("res://scripts/survivors/DiseaseSystem.gd")
const DiseaseCaseStateScript := preload("res://scripts/data/DiseaseCaseState.gd")
const DiseaseExposureStateScript := preload("res://scripts/data/DiseaseExposureState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const FloodFever := preload("res://data/diseases/flood_fever.tres")
const InfirmaryDefinition := preload("res://base_workbench/data/buildings/infirmary.tres")

const DIVE_HAZARD_SOURCE_ID := "contaminated_salvage"

var _failures := 0
var _system = DiseaseSystemScript.new()
var _definitions := {"flood_fever": FloodFever}


func _initialize() -> void:
	print("Disease system: pure timing, contact limits, recovery, outbreak and atomic apply")
	_test_exposure_response_day_and_threshold()
	_test_contact_snapshot_limits_and_isolation()
	_test_isolation_capacity_boundaries()
	_test_contact_settlement_cap_boundaries()
	_test_treatment_and_natural_recovery()
	_test_outbreak_once_and_projected_death_exclusion()
	_test_outbreak_threshold_boundaries()
	_test_recovering_immunity_and_reexposure()
	_test_atomic_rejection()
	_test_case_plan_projection()
	_test_resilience_competency_pressure()
	_test_campaign_presentation_counts_people()
	if _failures > 0:
		push_error("Disease system test failed with %d assertion(s)." % _failures)
		quit(1)
		return
	print("Disease system test passed.")
	quit(0)


func _test_exposure_response_day_and_threshold() -> void:
	var state = _state(1)
	state.disease_campaign.pending_exposures.append(
		DiseaseExposureStateScript.create("flood_fever", "igor", "dive", DIVE_HAZARD_SOURCE_ID, 3, 1)
	)
	var projection := _project(state, {"igor": "full", "anka": "full", "mira": "full"})
	_assert(bool(projection.get("valid", false)), "A canonical domain dive exposure must project successfully.")
	_assert(state.find_survivor("igor").disease_cases.is_empty() and state.disease_campaign.pending_exposures.size() == 1, "project_day must not mutate cases or consume pending exposure.")
	var igor_result := _survivor_result(projection, "igor")
	_assert(igor_result.get("disease_cases_after", []).size() == 1, "The incoming exposure must become one detached case in the projection.")
	if igor_result.get("disease_cases_after", []).size() == 1:
		_assert(int(igor_result.disease_cases_after[0].phase) == DiseaseCaseStateScript.Phase.EXPOSED, "Exposure acquired on day N must not resolve on night N.")
	_assert(bool(_system.apply_day(state, projection).get("applied", false)), "A complete first-night projection must apply once.")
	_assert(state.find_survivor("igor").disease_cases.size() == 1 and state.disease_campaign.pending_exposures.is_empty(), "Applying must atomically consume pending exposure into one case.")

	state.day = 2
	state.begin_new_day_plan()
	projection = _project(state, {"igor": "full", "anka": "full", "mira": "full"})
	igor_result = _survivor_result(projection, "igor")
	_assert(bool(projection.get("valid", false)) and igor_result.get("disease_cases_after", []).is_empty(), "After a full response day, pressure 3 with full ration (-1) must clear below threshold 4.")

	var threshold_state = _state(2)
	var threshold_case = _case(DiseaseCaseStateScript.Phase.EXPOSED, 1, 3)
	threshold_case.last_resolved_day = 1
	threshold_state.find_survivor("igor").disease_cases.append(threshold_case)
	threshold_state.disease_campaign.last_resolved_day = 1
	var threshold_projection := _project(threshold_state, {"igor": "none", "anka": "full", "mira": "full"})
	var threshold_after: Array = _survivor_result(threshold_projection, "igor").get("disease_cases_after", [])
	_assert(threshold_after.size() == 1 and int(threshold_after[0].phase) == DiseaseCaseStateScript.Phase.SYMPTOMATIC, "Pressure exactly 4 must become symptomatic for the next planning phase.")


func _test_contact_snapshot_limits_and_isolation() -> void:
	var repeated = _state(2)
	repeated.disease_campaign.last_resolved_day = 1
	var source_case = _case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4)
	source_case.last_resolved_day = 1
	repeated.find_survivor("igor").disease_cases.append(source_case)
	var target_case = _case(DiseaseCaseStateScript.Phase.EXPOSED, 1, 2)
	target_case.last_resolved_day = 1
	repeated.find_survivor("anka").disease_cases.append(target_case)
	var work := [{"building_id": "workshop", "action_id": "work", "worker_ids": ["igor", "anka"]}]
	var projection := _system.project_day(
		repeated,
		_definitions,
		{"igor": "full", "anka": "half", "mira": "full"},
		work,
		[],
		[],
		{}
	)
	var target_after: Array = _survivor_result(projection, "anka").get("disease_cases_after", [])
	_assert(projection.transmissions.size() == 1 and int(projection.transmissions[0].pressure) == 2, "One real coworker contact must use symptomatic pressure 2 and respect settlement cap 1 for three residents.")
	_assert(target_after.size() == 1 and int(target_after[0].phase) == DiseaseCaseStateScript.Phase.SYMPTOMATIC, "An older exposed case must accumulate contact 2+2 and resolve at threshold 4.")

	var new_contact = _state(1)
	new_contact.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	projection = _system.project_day(new_contact, _definitions, _full_rations(), work, [], [], {})
	target_after = _survivor_result(projection, "anka").get("disease_cases_after", [])
	_assert(target_after.size() == 1 and int(target_after[0].phase) == DiseaseCaseStateScript.Phase.EXPOSED, "A contact created on night N must remain exposed and cannot chain into symptoms or a new source that night.")

	var solo = _state(1)
	solo.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	var solo_work := [{"building_id": "workshop", "action_id": "work", "worker_ids": ["igor"]}]
	projection = _system.project_day(solo, _definitions, _full_rations(), solo_work, [], [], {})
	_assert(projection.transmissions.is_empty(), "A source who really worked alone must not receive a fallback community contact.")

	var emergency = _state(1)
	emergency.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	projection = _system.project_day(emergency, _definitions, _full_rations(), [], ["anka"], [], {"formal_isolation_capacity": 0})
	_assert(projection.transmissions.size() == 1 and str(projection.transmissions[0].target_survivor_id) == "anka" and int(projection.transmissions[0].pressure) == 1, "An emergency-isolated target may receive only one weaker community contact at pressure 1.")

	var formal = _state(1)
	formal.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	projection = _system.project_day(formal, _definitions, _full_rations(), work, ["anka"], [], {"formal_isolation_capacity": 1})
	_assert(projection.transmissions.is_empty(), "A formally isolated target must receive zero transmission even when a real shared-work contact names that resident.")

	var emergency_source = _state(1)
	emergency_source.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	projection = _system.project_day(emergency_source, _definitions, _full_rations(), [], ["igor"], [], {"formal_isolation_capacity": 0})
	_assert(projection.transmissions.size() == 1 and str(projection.transmissions[0].source_survivor_id) == "igor" and str(projection.transmissions[0].source_kind) == "community_contact" and int(projection.transmissions[0].pressure) == 1, "An emergency-isolated infectious source may emit at most one weak community contact at pressure 1.")

	var formal_source = _state(1)
	formal_source.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	projection = _system.project_day(formal_source, _definitions, _full_rations(), work, ["igor"], [], {"formal_isolation_capacity": 1})
	_assert(projection.transmissions.is_empty(), "A formally isolated source who would otherwise work at 65% must emit zero work and community transmission.")


func _test_isolation_capacity_boundaries() -> void:
	var authored_capacities: Array[int] = []
	for level in range(1, 5):
		authored_capacities.append(int(InfirmaryDefinition.get_level_definition(level).capabilities.get("formal_isolation_capacity", -1)))
	_assert(authored_capacities == [0, 0, 2, 4], "Infirmary levels I-IV must author the exact formal-isolation capacities 0/0/2/4.")

	var state = _state(1)
	_add_survivor(state, "dora")
	_add_survivor(state, "ela")
	state.resources.set_amount(ResourceIdsScript.MEDS_CHEMICALS, 0)
	var ordered_ids: Array[String] = ["mira", "igor", "anka", "dora", "ela"]
	for survivor_id in ordered_ids:
		state.find_survivor(survivor_id).disease_cases.append(_case(DiseaseCaseStateScript.Phase.EXPOSED, 1, 3))
		_assert(_system.set_isolation_intent(state, survivor_id, true), "Emergency isolation must remain available without an Infirmary or medicine for %s." % survivor_id)
	_assert(state.find_building_by_definition("infirmary") == null, "The isolation boundary fixture must not silently contain an Infirmary.")

	var no_formal := _system.isolation_assignments(state, authored_capacities[0])
	_assert(no_formal.formal_ids.is_empty() and no_formal.emergency_ids == ordered_ids, "Capacity zero must keep every ordered intent in emergency isolation.")
	var level_two := _system.isolation_assignments(state, authored_capacities[1])
	_assert(level_two.formal_ids.is_empty() and level_two.emergency_ids == ordered_ids, "Infirmary II must still provide no formal isolation.")
	var level_three := _system.isolation_assignments(state, authored_capacities[2])
	_assert(level_three.formal_ids == ordered_ids.slice(0, 2) and level_three.emergency_ids == ordered_ids.slice(2), "Infirmary III must deterministically assign the first two intents formally and overflow the remaining three to emergency isolation.")
	var level_four := _system.isolation_assignments(state, authored_capacities[3])
	_assert(level_four.formal_ids == ordered_ids.slice(0, 4) and level_four.emergency_ids == ordered_ids.slice(4), "Infirmary IV must deterministically assign four formal places and overflow the fifth intent to emergency isolation.")
	_assert(_system.isolation_assignments(state, 2) == level_three, "Repeated isolation projection must preserve stable formal and emergency ordering.")


func _test_contact_settlement_cap_boundaries() -> void:
	var four = _state(1)
	_add_survivor(four, "zeta")
	four.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	four.find_survivor("anka").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	var projection := _project(four, _rations_for_state(four))
	_assert(projection.transmissions.size() == 1, "Contact settlement cap must remain 1 at exactly four living residents.")

	var five = _state(1)
	_add_survivor(five, "zeta")
	_add_survivor(five, "eta")
	five.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	five.find_survivor("anka").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SEVERE, 1, 4))
	projection = _project(five, _rations_for_state(five))
	var source_ids: Dictionary = {}
	var target_ids: Dictionary = {}
	for transmission in projection.transmissions:
		source_ids[str(transmission.source_survivor_id)] = true
		target_ids[str(transmission.target_survivor_id)] = true
	_assert(projection.transmissions.size() == 2, "Contact settlement cap must jump directly from 1 to 2 at five living residents.")
	_assert(source_ids.size() == 2 and target_ids.size() == 2, "At the cap boundary every source and target may participate at most once per day.")


func _test_treatment_and_natural_recovery() -> void:
	var treated = _state(1)
	treated.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	var commitment := [{"survivor_id": "igor", "disease_id": "flood_fever", "phase_before": DiseaseCaseStateScript.Phase.SYMPTOMATIC}]
	var projection := _system.project_day(treated, _definitions, _full_rations(), [], [], commitment, {})
	var treated_after: Array = _survivor_result(projection, "igor").get("disease_cases_after", [])
	_assert(projection.transmissions.is_empty() and treated_after.size() == 1 and int(treated_after[0].phase) == DiseaseCaseStateScript.Phase.RECOVERING, "Therapy must move a known symptomatic source to recovery before transmission.")

	var natural = _state(2)
	natural.disease_campaign.last_resolved_day = 1
	var natural_case = _case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4)
	natural_case.last_resolved_day = 1
	natural.find_survivor("igor").disease_cases.append(natural_case)
	projection = _system.project_day(natural, _definitions, _full_rations(), [], ["igor"], [], {"formal_isolation_capacity": 0})
	var first_after = _survivor_result(projection, "igor")
	_assert(first_after.disease_cases_after.size() == 1 and int(first_after.disease_cases_after[0].phase) == DiseaseCaseStateScript.Phase.SEVERE and int(first_after.disease_cases_after[0].natural_recovery_days) == 1, "First isolated, non-working, full-ration day must carry recovery count while untreated symptoms advance to severe.")
	_assert(bool(_system.apply_day(natural, projection).get("applied", false)), "First natural-recovery projection must apply.")
	natural.day = 3
	natural.begin_new_day_plan()
	projection = _system.project_day(natural, _definitions, _full_rations(), [], ["igor"], [], {"formal_isolation_capacity": 0})
	var second_after = _survivor_result(projection, "igor")
	_assert(second_after.disease_cases_after.size() == 1 and int(second_after.disease_cases_after[0].phase) == DiseaseCaseStateScript.Phase.RECOVERING, "Second consecutive qualified day must enter recovery.")
	_assert(int(second_after.health_delta) == -15, "A severe case must still lose 15 health on the day natural improvement completes.")


func _test_outbreak_once_and_projected_death_exclusion() -> void:
	var outbreak = _state(1)
	outbreak.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	outbreak.find_survivor("anka").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	var projection := _project(outbreak, _full_rations())
	_assert(int(projection.outbreak_threshold) == 2 and bool(projection.outbreak_active_after) and int(projection.hope_delta) == -6, "Two contagious people in a three-person settlement must start one outbreak with Hope -6.")
	_assert(str(projection.campaign_after.outbreak_id) == "outbreak:1:1" and int(projection.outbreak_episode) == 1, "Outbreak identity must be stable episode identity outbreak:day:episode.")
	_assert(bool(_system.apply_day(outbreak, projection).get("applied", false)), "Outbreak start projection must apply once.")
	outbreak.day = 2
	outbreak.begin_new_day_plan()
	projection = _project(outbreak, _full_rations())
	_assert(bool(projection.outbreak_active_after) and int(projection.hope_delta) == 0 and int(projection.outbreak_episode) == 1, "A continuing first episode must not repeat its Hope -6 transition.")
	_assert(bool(_system.apply_day(outbreak, projection).get("applied", false)), "The continuing outbreak projection must apply without replaying Hope.")
	outbreak.day = 3
	outbreak.begin_new_day_plan()
	var commitments := [
		{"survivor_id": "igor", "disease_id": "flood_fever", "phase_before": int(outbreak.find_survivor("igor").disease_cases[0].phase)},
		{"survivor_id": "anka", "disease_id": "flood_fever", "phase_before": int(outbreak.find_survivor("anka").disease_cases[0].phase)},
	]
	projection = _system.project_day(outbreak, _definitions, _full_rations(), [], [], commitments, {})
	_assert(not bool(projection.outbreak_active_after) and int(projection.hope_delta) == 4 and int(projection.outbreak_episode) == 1, "First night with no contagious case must contain the same episode and emit Hope +4 exactly once.")
	_assert(bool(_system.apply_day(outbreak, projection).get("applied", false)), "The first containment transition must apply once.")
	outbreak.day = 4
	outbreak.begin_new_day_plan()
	projection = _project(outbreak, _full_rations())
	_assert(not bool(projection.outbreak_active_after) and int(projection.hope_delta) == 0 and int(projection.outbreak_episode) == 1, "A night after containment must not repeat its Hope +4 transition.")
	_assert(bool(_system.apply_day(outbreak, projection).get("applied", false)), "The post-containment projection must apply without replaying Hope.")
	outbreak.day = 5
	outbreak.begin_new_day_plan()
	for survivor_id in ["igor", "anka"]:
		var survivor = outbreak.find_survivor(survivor_id)
		survivor.disease_cases.clear()
		var repeated_case = _case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 4, 4)
		repeated_case.last_resolved_day = 4
		survivor.disease_cases.append(repeated_case)
	projection = _project(outbreak, _full_rations())
	_assert(bool(projection.outbreak_active_after) and int(projection.hope_delta) == -6 and int(projection.outbreak_episode) == 2 and str(projection.campaign_after.outbreak_id) == "outbreak:5:2", "A later recurrence must start a distinct second episode with one fresh Hope -6 transition.")

	var dying = _state(2)
	dying.disease_campaign.last_resolved_day = 1
	for survivor_id in ["igor", "anka"]:
		var survivor = dying.find_survivor(survivor_id)
		survivor.health = 10
		var severe = _case(DiseaseCaseStateScript.Phase.SEVERE, 1, 4)
		severe.phase_started_day = 1
		severe.last_resolved_day = 1
		survivor.disease_cases.append(severe)
	projection = _project(dying, _full_rations())
	_assert(int(projection.contagious_case_count_after) == 0 and not bool(projection.outbreak_active_after), "People projected to die from severe health loss must not count toward outbreak state or denominator.")
	_assert(_survivor_result(projection, "igor").disease_cases_after.is_empty(), "A projected terminal resident must leave no typed cases for central cleanup.")


func _test_outbreak_threshold_boundaries() -> void:
	_assert(DiseaseSystemScript.outbreak_threshold(0) == 2 and DiseaseSystemScript.outbreak_threshold(1) == 2, "Outbreak threshold must have an exact minimum of two at population 0 and 1.")
	_assert(DiseaseSystemScript.outbreak_threshold(6) == 2 and DiseaseSystemScript.outbreak_threshold(7) == 3, "Outbreak threshold must jump from 2 to 3 exactly between populations 6 and 7.")
	var below = _state(1)
	for survivor_id in ["dora", "ela", "franek", "gaja"]:
		_add_survivor(below, survivor_id)
	below.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	below.find_survivor("anka").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	var projection := _project(below, _rations_for_state(below))
	_assert(int(projection.outbreak_threshold) == 3 and not bool(projection.outbreak_active_after), "Two infectious people at population seven must stay just below outbreak threshold three.")
	var at = _state(1)
	for survivor_id in ["dora", "ela", "franek", "gaja"]:
		_add_survivor(at, survivor_id)
	for survivor_id in ["igor", "anka", "mira"]:
		at.find_survivor(survivor_id).disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	projection = _project(at, _rations_for_state(at))
	_assert(int(projection.outbreak_threshold) == 3 and bool(projection.outbreak_active_after), "Three infectious people at population seven must start the outbreak exactly at threshold.")


func _test_recovering_immunity_and_reexposure() -> void:
	var state = _state(1)
	state.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.RECOVERING, 1, 4))
	var projection := _project(state, _full_rations())
	var cases_after: Array = _survivor_result(projection, "igor").disease_cases_after
	_assert(cases_after.size() == 1 and int(cases_after[0].phase) == DiseaseCaseStateScript.Phase.RECOVERING, "Recovering must remain visible for its complete first planning day.")
	_assert(bool(_system.apply_day(state, projection).applied), "Recovery day-one projection must apply.")

	state.day = 2
	state.begin_new_day_plan()
	projection = _project(state, _full_rations())
	cases_after = _survivor_result(projection, "igor").disease_cases_after
	_assert(cases_after.size() == 1 and int(cases_after[0].phase) == DiseaseCaseStateScript.Phase.IMMUNE and int(cases_after[0].immunity_until_day) == 5, "After one full recovery day, immunity must begin with an exact three-planning-day horizon.")
	_assert(bool(_system.apply_day(state, projection).applied), "Recovery-to-immunity projection must apply.")

	for day in [3, 4]:
		state.day = day
		state.begin_new_day_plan()
		if day == 3:
			state.disease_campaign.pending_exposures.append(DiseaseExposureStateScript.create("flood_fever", "igor", "contact", "reinfection", 3, day, "anka"))
		projection = _project(state, _full_rations())
		cases_after = _survivor_result(projection, "igor").disease_cases_after
		_assert(cases_after.size() == 1 and int(cases_after[0].phase) == DiseaseCaseStateScript.Phase.IMMUNE, "Immunity must persist and ignore same-disease exposure during protected planning day %d." % day)
		_assert(bool(_system.apply_day(state, projection).applied), "Protected immunity projection must apply on day %d." % day)

	state.day = 5
	state.begin_new_day_plan()
	state.disease_campaign.pending_exposures.append(DiseaseExposureStateScript.create("flood_fever", "igor", "contact", "expiry_day", 3, 5, "anka"))
	projection = _project(state, _full_rations())
	_assert(_survivor_result(projection, "igor").disease_cases_after.is_empty(), "Immunity must cover planning day five, ignore its exposure, then expire at that day's end.")
	_assert(bool(_system.apply_day(state, projection).applied), "Immunity expiry projection must apply.")

	state.day = 6
	state.begin_new_day_plan()
	state.disease_campaign.pending_exposures.append(DiseaseExposureStateScript.create("flood_fever", "igor", "contact", "after_immunity", 2, 6, "anka"))
	projection = _project(state, _full_rations())
	cases_after = _survivor_result(projection, "igor").disease_cases_after
	_assert(cases_after.size() == 1 and int(cases_after[0].phase) == DiseaseCaseStateScript.Phase.EXPOSED, "After immunity expires, a later source must be able to create a fresh exposed case.")


func _test_atomic_rejection() -> void:
	var health_state = _state(1)
	health_state.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	var projection := _project(health_state, _full_rations())
	var tampered := _survivor_result(projection, "igor")
	tampered.health_after = 999
	tampered.health_delta = 899
	var health_before := int(health_state.find_survivor("igor").health)
	var campaign_before := str(health_state.disease_campaign.outbreak_id)
	_assert(not bool(_system.apply_day(health_state, projection).get("applied", false)), "apply_day must reject an injected health value above max health.")
	_assert(health_state.find_survivor("igor").health == health_before and str(health_state.disease_campaign.outbreak_id) == campaign_before, "A rejected late payload must leave all survivor and campaign state untouched.")

	var duplicate_state = _state(1)
	duplicate_state.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	projection = _project(duplicate_state, _full_rations())
	tampered = _survivor_result(projection, "igor")
	tampered.disease_cases_after.append(tampered.disease_cases_after[0].duplicate(true))
	_assert(not bool(_system.apply_day(duplicate_state, projection).get("applied", false)), "apply_day must reject duplicate disease_id values before its first mutation.")
	_assert(duplicate_state.find_survivor("igor").disease_cases.size() == 1 and not duplicate_state.disease_campaign.outbreak_active, "Duplicate-case rejection must be atomic across survivor and campaign state.")


func _test_case_plan_projection() -> void:
	var state = _state(2)
	var exposed = _case(DiseaseCaseStateScript.Phase.EXPOSED, 1, 3)
	exposed.last_resolved_day = 1
	state.find_survivor("igor").disease_cases.append(exposed)
	state.current_day_plan.set_survivor_isolated("igor", true)
	var forecast := _system.case_plan_projection(
		state,
		"igor",
		exposed,
		"full",
		{},
		{"formal_isolation_capacity": 0, "adverse_conditions_pressure": 1, "disease_pressure_modifier": 1}
	)
	_assert(bool(forecast.valid) and bool(forecast.exposure_resolves_today) and int(forecast.projected_pressure) == 4 and str(forecast.projected_phase_code) == "symptomatic", "The shared case-plan projector must expose ration, weather and difficulty pressure outcome without UI rules.")
	var care := {"disease_treatment_commitments": [{"survivor_id": "igor", "disease_id": "flood_fever", "phase_before": DiseaseCaseStateScript.Phase.EXPOSED}]}
	forecast = _system.case_plan_projection(state, "igor", exposed, "full", care, {})
	_assert(bool(forecast.treatment_planned) and bool(forecast.projected_case_cleared), "The shared forecast must show prophylaxis clearing a known exposure.")


func _test_resilience_competency_pressure() -> void:
	var state = _state(2)
	var igor = state.find_survivor("igor")
	igor.competency_levels["resilience"] = 3
	var exposed = _case(DiseaseCaseStateScript.Phase.EXPOSED, 1, 6)
	exposed.last_resolved_day = 1
	igor.disease_cases.append(exposed)
	var forecast := _system.case_plan_projection(state, "igor", exposed, "full", {}, {})
	_assert(
		bool(forecast.valid)
		and int(forecast.projected_pressure) == 2
		and bool(forecast.projected_case_cleared),
		"Resilience III must subtract exactly three points after the full-ration modifier in the canonical disease projection."
	)


func _test_campaign_presentation_counts_people() -> void:
	var state = _state(1)
	var igor = state.find_survivor("igor")
	igor.disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	# Presentation remains defensive against a malformed duplicate collection:
	# aggregate counters describe people, not serialized case rows.
	igor.disease_cases.append(igor.disease_cases[0].duplicate(true))
	var presentation := _system.campaign_presentation(state, _definitions)
	_assert(int(presentation.active_case_count) == 1 and int(presentation.contagious_case_count) == 1, "Campaign presentation must count an affected person once even if malformed input repeats a case row.")


func _state(day: int):
	var state = GameStateScript.new()
	state.setup_new_campaign(73073 + day, DifficultyProfileScript.new())
	state.tutorial.complete()
	state.day = day
	state.begin_new_day_plan()
	for survivor in state.survivors:
		survivor.status = SurvivorStateScript.Status.AVAILABLE
		survivor.health = survivor.get_max_health()
		survivor.hunger = 0
		survivor.fatigue = 0
		survivor.morale = 55
		survivor.current_assignment = ""
		survivor.disease_cases.clear()
	state.disease_campaign.outbreak_active = false
	state.disease_campaign.outbreak_id = ""
	state.disease_campaign.outbreak_started_day = 0
	state.disease_campaign.outbreak_episode = 0
	state.disease_campaign.last_contained_day = 0
	state.disease_campaign.peak_cases = 0
	state.disease_campaign.last_resolved_day = maxi(day - 1, 0)
	state.disease_campaign.pending_exposures.clear()
	return state


func _case(phase: int, acquired_day: int, pressure: int):
	var disease_case = DiseaseCaseStateScript.new()
	_assert(disease_case.setup_from_definition(FloodFever, phase, acquired_day, pressure, "test", "fixture"), "Disease fixture must be valid.")
	return disease_case


func _project(state, rations: Dictionary) -> Dictionary:
	return _system.project_day(state, _definitions, rations, [], [], [], {})


func _full_rations() -> Dictionary:
	return {"anka": "full", "igor": "full", "mira": "full"}


func _rations_for_state(state) -> Dictionary:
	var result: Dictionary = {}
	for survivor in state.survivors:
		if survivor != null and survivor.is_present_in_settlement():
			result[str(survivor.id)] = "full"
	return result


func _add_survivor(state, survivor_id: String) -> void:
	var survivor = SurvivorStateScript.new()
	survivor.id = survivor_id
	survivor.display_name = survivor_id.capitalize()
	survivor.base_max_health = 100
	survivor.health = 100
	survivor.hunger = 0
	survivor.fatigue = 0
	survivor.morale = 55
	survivor.status = SurvivorStateScript.Status.AVAILABLE
	state.survivors.append(survivor)


func _survivor_result(projection: Dictionary, survivor_id: String) -> Dictionary:
	for result in projection.get("survivor_results", []):
		if str(result.get("survivor_id", "")) == survivor_id:
			return result
	return {}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Disease system assertion failed: " + message)
