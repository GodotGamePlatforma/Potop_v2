extends SceneTree

const BuildingEffectSystemScript := preload("res://scripts/base/BuildingEffectSystem.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const DifficultyDirectorScript := preload("res://scripts/base/DifficultyDirector.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const DiseaseCaseStateScript := preload("res://scripts/data/DiseaseCaseState.gd")
const DiseaseExposureStateScript := preload("res://scripts/data/DiseaseExposureState.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const EndOfDayResolverScript := preload("res://scripts/base/EndOfDayResolver.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const MedicalCareSystemScript := preload("res://scripts/base/MedicalCareSystem.gd")
const ReportStateScript := preload("res://scripts/data/ReportState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const FloodFever := preload("res://data/diseases/flood_fever.tres")
const InfirmaryDefinition := preload("res://data/buildings/infirmary.tres")

var _failures := 0
var _definitions := {"flood_fever": FloodFever}


func _initialize() -> void:
	print("Disease end of day: shared medical care, isolation, Hope, deaths and pressure")
	_test_shared_medical_projection()
	_test_medical_before_disease_and_isolated_worker()
	_test_public_resolve_medical_disease_death_order()
	_test_exact_outbreak_hope()
	_test_central_death_and_dive_cleanup()
	_test_pressure_snapshot()
	if _failures > 0:
		push_error("Disease end-of-day test failed with %d assertion(s)." % _failures)
		quit(1)
		return
	print("Disease end-of-day test passed.")
	quit(0)


func _test_shared_medical_projection() -> void:
	var state = _state(1)
	state.resources.set_amount(ResourceIdsScript.MEDS_CHEMICALS, 3)
	var patient = state.find_survivor("igor")
	patient.health = 40
	patient.injury_states.assign(["critical_rescue"])
	patient.disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	var capabilities: Dictionary = InfirmaryDefinition.get_level_definition(1).capabilities
	var care = MedicalCareSystemScript.new()
	var projection := care.project(
		capabilities,
		{"worker_ids": ["mira"], "worker_units": 1.0, "specialist_bonus": 0.0},
		"normal",
		1.0,
		3,
		state.survivors,
		_definitions,
		["igor"]
	)
	_assert(int(projection.treated_count) == 1 and int(projection.medicine_spent) == 1, "One combined patient must consume exactly one slot and one medicine dose.")
	_assert(projection.patients.size() == 1 and projection.patients[0].care_reasons.has("injury") and projection.patients[0].care_reasons.has("disease"), "The canonical patient row must combine injury and disease reasons.")
	_assert(projection.disease_treatment_commitments.size() == 1, "The same one-dose projection must emit the disease therapy commitment.")
	_assert(bool(care.apply(state, projection).get("applied", false)), "The shared medical projection must apply atomically.")
	_assert(state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS) == 2 and patient.health > 40, "Applying combined care must spend one medicine and heal through the same projection.")
	_assert(int(patient.disease_cases[0].phase) == DiseaseCaseStateScript.Phase.SYMPTOMATIC, "MedicalCareSystem must leave disease mutation to the later DiseaseSystem commitment step.")

	var unstaffed := care.project(
		capabilities,
		{"worker_ids": [], "worker_units": 0.0, "specialist_bonus": 0.0},
		"normal",
		1.0,
		2,
		state.survivors,
		_definitions,
		["igor"]
	)
	_assert(str(unstaffed.blocker_code) == MedicalCareSystemScript.BLOCKER_NO_CAPABLE_WORKERS and unstaffed.patient_queue.size() == 1, "An unstaffed Infirmary must still expose its canonical queue while treating nobody.")


func _test_medical_before_disease_and_isolated_worker() -> void:
	var state = _state(1)
	state.resources.set_amount(ResourceIdsScript.MEDS_CHEMICALS, 3)
	var infirmary = _add_building(state, "infirmary_test", "infirmary", 3, ["mira"])
	var patient = state.find_survivor("igor")
	patient.disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	state.current_day_plan.sync_from_state(state)
	var medical_priority: Array[String] = ["igor"]
	state.current_day_plan.set_medical_priority(medical_priority)
	var resolver = EndOfDayResolverScript.new()
	var report = ReportStateScript.new()
	resolver._capture_capable_worker_snapshot(state)
	resolver._resolve_medical_care(state, report)
	resolver._ration_by_survivor = _full_rations()
	resolver._resolve_diseases(state, report)
	_assert(state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS) == 2, "Resolver medical care must spend exactly one dose for the symptomatic patient.")
	_assert(patient.disease_cases.size() == 1 and int(patient.disease_cases[0].phase) == DiseaseCaseStateScript.Phase.RECOVERING, "Known symptoms must be treated before disease transmission and stage progression.")
	_assert(resolver._medical_care_projection.disease_treatment_commitments.size() == 1, "Resolver must pass the exact shared medical commitment into DiseaseSystem.")

	var isolated = _state(1)
	isolated.resources.set_amount(ResourceIdsScript.MEDS_CHEMICALS, 3)
	var isolated_infirmary = _add_building(isolated, "isolated_infirmary", "infirmary", 3, ["mira"])
	isolated.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	isolated.current_day_plan.sync_from_state(isolated)
	isolated.current_day_plan.set_survivor_isolated("mira", true)
	var effect_preview := BuildingEffectSystemScript.new().staffing_preview(isolated, InfirmaryDefinition, isolated_infirmary)
	_assert(effect_preview.capable_worker_ids.is_empty(), "An isolated medic must remain assigned but contribute zero in the staffing preview.")
	var isolated_resolver = EndOfDayResolverScript.new()
	isolated_resolver._capture_capable_worker_snapshot(isolated)
	isolated_resolver._resolve_medical_care(isolated, ReportStateScript.new())
	_assert(isolated_resolver._medical_care_projection.patient_queue.size() == 1 and int(isolated_resolver._medical_care_projection.treated_count) == 0, "Runtime must match preview: isolated staffing leaves the queue visible but cannot treat.")
	_assert(isolated.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS) == 3 and isolated.find_survivor("mira").current_assignment == isolated_infirmary.id, "Isolation must spend no medicine and preserve the durable roster assignment.")


func _test_public_resolve_medical_disease_death_order() -> void:
	var state = _state(2)
	state.resources.set_amount(ResourceIdsScript.MEDS_CHEMICALS, 3)
	_add_building(state, "public_order_infirmary", "infirmary", 1, ["mira"])
	var treated = state.find_survivor("igor")
	treated.health = 40
	treated.injury_states.assign(["critical_rescue"])
	var treated_case = _case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4)
	treated_case.last_resolved_day = 1
	treated.disease_cases.append(treated_case)
	var dying = state.find_survivor("anka")
	dying.health = 10
	var severe_case = _case(DiseaseCaseStateScript.Phase.SEVERE, 1, 4)
	severe_case.phase_started_day = 1
	severe_case.last_resolved_day = 1
	dying.disease_cases.append(severe_case)
	state.current_day_plan.sync_from_state(state)
	var priority: Array[String] = ["igor"]
	state.current_day_plan.set_medical_priority(priority)

	var report = EndOfDayResolverScript.new().resolve(state, null, false)
	var treated_after = state.find_survivor("igor")
	var dying_after = state.find_survivor("anka")
	_assert(report != null and state.day == 3, "The public end-of-day transaction must complete and advance exactly one day.")
	_assert(state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS) == 2, "The public resolver must spend one medicine for the one-slot combined injury-and-disease patient.")
	_assert(treated_after.health > 40 and treated_after.disease_cases.size() == 1 and int(treated_after.disease_cases[0].phase) == DiseaseCaseStateScript.Phase.RECOVERING, "Public resolve must apply shared medical care before DiseaseSystem consumes its treatment commitment.")
	_assert(dying_after.status == SurvivorStateScript.Status.DEAD and dying_after.disease_cases.is_empty(), "Public resolve must apply severe disease health loss before the central death step and then clear typed cases.")
	_assert(_contains_fragment(report.entries, "opiekę medyczną") and _contains_fragment(report.warnings, "umiera"), "The immutable public report must retain both the earlier care result and the later central death result.")


func _test_exact_outbreak_hope() -> void:
	var state = _state(1)
	state.resources.set_amount(ResourceIdsScript.HOPE, 50)
	state.difficulty_profile.hope_loss_multiplier = 2.0
	state.difficulty_profile.hope_gain_multiplier = 0.5
	state.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	state.find_survivor("anka").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	var resolver = EndOfDayResolverScript.new()
	resolver._ration_by_survivor = _full_rations()
	var report = ReportStateScript.new()
	resolver._resolve_diseases(state, report)
	resolver._resolve_hope(state, null, report)
	_assert(state.disease_campaign.outbreak_active and resolver._disease_hope_delta_today == -6, "Disease resolution must emit one canonical outbreak transition delta.")
	_assert(state.resources.get_amount(ResourceIdsScript.HOPE) == 44, "Outbreak Hope -6 must be exact and must not be multiplied by the generic x2 loss profile.")
	_assert(_contains_fragment(report.entries, "epizod 1") and _contains_fragment(report.entries, "50 -> 44"), "The immutable report must expose episode and exact before-to-after Hope change.")

	state.day = 2
	state.begin_new_day_plan()
	var continuing_resolver = EndOfDayResolverScript.new()
	continuing_resolver._ration_by_survivor = _full_rations()
	var continuing_report = ReportStateScript.new()
	continuing_resolver._resolve_diseases(state, continuing_report)
	continuing_resolver._resolve_hope(state, null, continuing_report)
	_assert(state.disease_campaign.outbreak_active and continuing_resolver._disease_hope_delta_today == 0, "A continuing outbreak must not replay its start transition on the following night.")
	_assert(state.resources.get_amount(ResourceIdsScript.HOPE) == 44 and not _contains_fragment(continuing_report.entries, "Zmiana epidemii"), "The night after outbreak start must leave Hope unchanged when no other Hope source exists.")

	var contained = _state(2)
	contained.resources.set_amount(ResourceIdsScript.HOPE, 50)
	contained.difficulty_profile.hope_loss_multiplier = 2.0
	contained.difficulty_profile.hope_gain_multiplier = 0.5
	contained.disease_campaign.outbreak_active = true
	contained.disease_campaign.outbreak_id = "outbreak:1:1"
	contained.disease_campaign.outbreak_started_day = 1
	contained.disease_campaign.outbreak_episode = 1
	contained.disease_campaign.peak_cases = 2
	contained.disease_campaign.last_resolved_day = 1
	for survivor_id in ["igor", "anka"]:
		var recovery_case = _case(DiseaseCaseStateScript.Phase.RECOVERING, 1, 4)
		recovery_case.phase_started_day = 1
		recovery_case.last_resolved_day = 1
		contained.find_survivor(survivor_id).disease_cases.append(recovery_case)
	var containment_resolver = EndOfDayResolverScript.new()
	containment_resolver._ration_by_survivor = _full_rations()
	containment_resolver._work_hope_delta_today = 2
	var containment_report = ReportStateScript.new()
	containment_resolver._resolve_diseases(contained, containment_report)
	containment_resolver._resolve_hope(contained, null, containment_report)
	_assert(not contained.disease_campaign.outbreak_active and containment_resolver._disease_hope_delta_today == 4, "The first zero-contagious night must emit the canonical Hope +4 containment transition.")
	_assert(contained.resources.get_amount(ResourceIdsScript.HOPE) == 55, "Ordinary Hope +2 must be scaled to +1 by x0.5, then epidemic Hope +4 must remain exact and unscaled.")
	_assert(_contains_fragment(containment_report.entries, "50 -> 51") and _contains_fragment(containment_report.entries, "51 -> 55 (+4 dokładnie raz)"), "The report must separate scaled ordinary Hope from exact containment Hope.")

	contained.day = 3
	contained.begin_new_day_plan()
	var after_containment = EndOfDayResolverScript.new()
	after_containment._ration_by_survivor = _full_rations()
	var after_report = ReportStateScript.new()
	after_containment._resolve_diseases(contained, after_report)
	after_containment._resolve_hope(contained, null, after_report)
	_assert(after_containment._disease_hope_delta_today == 0 and contained.resources.get_amount(ResourceIdsScript.HOPE) == 55, "The night after containment must not replay Hope +4.")
	_assert(not _contains_fragment(after_report.entries, "Zmiana epidemii"), "Post-containment reports must not repeat the exactly-once epidemic Hope entry.")


func _test_central_death_and_dive_cleanup() -> void:
	var state = _state(2)
	state.disease_campaign.last_resolved_day = 1
	var patient = state.find_survivor("igor")
	patient.health = 10
	var severe = _case(DiseaseCaseStateScript.Phase.SEVERE, 1, 4)
	severe.phase_started_day = 1
	severe.last_resolved_day = 1
	patient.disease_cases.append(severe)
	var resolver = EndOfDayResolverScript.new()
	resolver._ration_by_survivor = _full_rations()
	var report = ReportStateScript.new()
	resolver._resolve_diseases(state, report)
	_assert(patient.health == 0 and patient.status != SurvivorStateScript.Status.DEAD, "DiseaseSystem must only apply health delta and leave terminalization to the central death step.")
	resolver._resolve_deaths(state, null, report)
	_assert(patient.status == SurvivorStateScript.Status.DEAD and patient.disease_cases.is_empty(), "Central death resolution must terminalize once and clear typed cases after the causal report.")

	var dive_state = _state(1)
	var diver = dive_state.find_survivor("igor")
	diver.disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4))
	var dive_result = DiveResultScript.new()
	dive_result.diver_id = "igor"
	dive_result.diver_dead = true
	var dive_report = ReportStateScript.new()
	resolver._apply_diver_death(dive_state, dive_result, dive_report)
	_assert(diver.status == SurvivorStateScript.Status.DEAD and diver.disease_cases.is_empty(), "Expedition death must also clear typed cases after recording its cause.")
	var exposure = DiseaseExposureStateScript.create("flood_fever", "anka", "dive", "R1-06", 3, 1)
	dive_result.disease_exposures.append(exposure)
	resolver._append_dive_disease_exposures(dive_state, dive_result, dive_report)
	_assert(dive_state.disease_campaign.pending_exposures.size() == 1 and dive_state.disease_campaign.pending_exposures[0] != exposure, "DiveResult exposure must enter the night campaign boundary as a detached pending copy.")


func _test_pressure_snapshot() -> void:
	var state = _state(3)
	state.find_survivor("igor").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 2, 4))
	state.find_survivor("anka").disease_cases.append(_case(DiseaseCaseStateScript.Phase.SEVERE, 2, 4))
	state.disease_campaign.outbreak_active = true
	state.disease_campaign.outbreak_id = "outbreak:2:1"
	state.disease_campaign.outbreak_started_day = 2
	state.disease_campaign.outbreak_episode = 1
	state.disease_campaign.peak_cases = 2
	state.disease_campaign.last_resolved_day = 2
	var pressure = DifficultyDirectorScript.new().build_for_day(state)
	_assert(pressure != null and int(pressure.active_disease_cases) == 2 and int(pressure.contagious_disease_cases) == 2, "Pressure snapshot must freeze affected and contagious people, not report rows.")
	_assert(bool(pressure.disease_outbreak_active) and pressure.active_pressure_tags.has("disease_outbreak"), "Active outbreak must become a typed machine pressure tag.")
	_assert(bool(pressure.prefer_relief) and int(pressure.max_event_severity) <= 1 and pressure.preferred_impact_tags.has("medicine_relief"), "Outbreak must block another heavy hardship and prefer medical relief.")
	_assert(pressure.is_valid_for_day(3), "Disease pressure metrics and directives must pass PressureState validation.")


func _state(day: int):
	var state = GameStateScript.new()
	state.setup_new_campaign(74073 + day, DifficultyProfileScript.new())
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
	for resource_id in ResourceIdsScript.all():
		state.resources.set_amount(resource_id, 100)
	state.resources.set_amount(ResourceIdsScript.HOPE, 55)
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 70)
	return state


func _case(phase: int, acquired_day: int, pressure: int):
	var disease_case = DiseaseCaseStateScript.new()
	_assert(disease_case.setup_from_definition(FloodFever, phase, acquired_day, pressure, "test", "fixture"), "Disease end-of-day fixture must be valid.")
	return disease_case


func _add_building(state, id: String, definition_id: String, level: int, worker_ids: Array[String]):
	var building = BuildingStateScript.new()
	building.id = id
	building.definition_id = definition_id
	building.slot_id = "test_slot_" + id
	building.level = level
	building.is_built = true
	building.assigned_survivor_ids.assign(worker_ids)
	state.buildings.append(building)
	for survivor_id in worker_ids:
		var survivor = state.find_survivor(survivor_id)
		if survivor != null:
			survivor.current_assignment = id
			survivor.status = SurvivorStateScript.Status.WORKING
	return building


func _full_rations() -> Dictionary:
	return {"anka": "full", "igor": "full", "mira": "full"}


func _contains_fragment(lines: Array[String], fragment: String) -> bool:
	for line in lines:
		if fragment in str(line):
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Disease end-of-day assertion failed: " + message)
