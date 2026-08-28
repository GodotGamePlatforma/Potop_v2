extends SceneTree

const FORMAT_VERSION := 2
const DEFAULT_DAYS := 14
const DEFAULT_REPEAT := 2
const STARTING_MEDICINE := 5
const STARTING_HOPE := 60
const DIVE_HAZARD_SOURCE_ID := "contaminated_salvage"

const GameStateScript := preload("res://scripts/data/GameState.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const DiseaseCaseStateScript := preload("res://scripts/data/DiseaseCaseState.gd")
const DiseaseExposureStateScript := preload("res://scripts/data/DiseaseExposureState.gd")
const ReportStateScript := preload("res://scripts/data/ReportState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const DiseaseSystemScript := preload("res://scripts/survivors/DiseaseSystem.gd")
const MedicalCareSystemScript := preload("res://base_workbench/systems/MedicalCareSystem.gd")
const EndOfDayResolverScript := preload("res://scripts/campaign/EndOfDayResolver.gd")
const WorkPaceSystemScript := preload("res://base_workbench/systems/WorkPaceSystem.gd")
const FloodFever := preload("res://data/diseases/flood_fever.tres")
const InfirmaryDefinition := preload("res://base_workbench/data/buildings/infirmary.tres")

const PROFILE_PATHS := {
	"easy": "res://data/difficulty/easy.tres",
	"standard": "res://data/difficulty/standard.tres",
	"hard": "res://data/difficulty/hard.tres",
}
const DEFAULT_PROFILE_IDS: Array[String] = ["easy", "standard", "hard"]
const DEFAULT_POPULATIONS: Array[int] = [3, 5, 7]
const DEFAULT_SCENARIO_IDS: Array[String] = [
	"prepared",
	"frugal_natural",
	"late_outbreak_response",
	"no_response",
]
const VALID_MODES: Array[String] = ["all", "pressure", "strategies", "isolation"]
const VALID_FORMATS: Array[String] = ["table", "json"]

var _arguments: Dictionary = {}
var _disease_system = DiseaseSystemScript.new()
var _medical_care_system = MedicalCareSystemScript.new()
var _death_resolver = EndOfDayResolverScript.new()
var _definitions := {"flood_fever": FloodFever}


func _initialize() -> void:
	_arguments = _parse_arguments(OS.get_cmdline_user_args())
	call_deferred("_run")


func _run() -> void:
	var configuration := _validated_configuration()
	if not bool(configuration.get("ok", false)):
		_finish(configuration, 2)
		return

	var report := _build_report(configuration)
	if not bool(report.get("ok", false)):
		_finish(report, 2)
		return

	var repeat_count := int(configuration.repeat)
	var baseline_fingerprint := _fingerprint(report)
	for _repeat_index in range(1, repeat_count):
		var repeated := _build_report(configuration)
		if not bool(repeated.get("ok", false)):
			_finish(repeated, 2)
			return
		if _fingerprint(repeated) != baseline_fingerprint:
			_finish({
				"ok": false,
				"failure_code": "NON_DETERMINISTIC_REPORT",
				"failure_message": "Identyczne wejścia nie dały identycznego raportu balansowego.",
			}, 2)
			return
	report.repeat_count = repeat_count
	report.deterministic_repeat_match = true

	if str(configuration.output_format) == "table":
		_print_human_report(report)
	_finish(report, 0)


func _validated_configuration() -> Dictionary:
	var profile_result := _parse_string_list(
		str(_arguments.get("profiles", ",".join(DEFAULT_PROFILE_IDS))),
		PROFILE_PATHS.keys()
	)
	if not bool(profile_result.get("ok", false)):
		return profile_result
	var scenario_result := _parse_string_list(
		str(_arguments.get("scenarios", ",".join(DEFAULT_SCENARIO_IDS))),
		DEFAULT_SCENARIO_IDS
	)
	if not bool(scenario_result.get("ok", false)):
		return scenario_result
	var population_result := _parse_population_list(
		str(_arguments.get("populations", "3,5,7"))
	)
	if not bool(population_result.get("ok", false)):
		return population_result

	var mode := str(_arguments.get("mode", "all")).strip_edges().to_lower()
	if mode not in VALID_MODES:
		return _configuration_error("UNKNOWN_MODE", "Nieznany --mode=%s. Dozwolone: %s." % [mode, ", ".join(VALID_MODES)])
	var output_format := str(_arguments.get("format", "table")).strip_edges().to_lower()
	if output_format not in VALID_FORMATS:
		return _configuration_error("UNKNOWN_FORMAT", "Nieznany --format=%s. Dozwolone: %s." % [output_format, ", ".join(VALID_FORMATS)])

	var days_text := str(_arguments.get("days", DEFAULT_DAYS))
	if not days_text.is_valid_int():
		return _configuration_error("INVALID_DAYS", "--days musi być liczbą całkowitą.")
	var days := int(days_text)
	if days < 2 or days > 60:
		return _configuration_error("INVALID_DAYS", "--days musi mieścić się w zakresie 2..60.")

	var repeat_text := str(_arguments.get("repeat", DEFAULT_REPEAT))
	if not repeat_text.is_valid_int():
		return _configuration_error("INVALID_REPEAT", "--repeat musi być liczbą całkowitą.")
	var repeat_count := int(repeat_text)
	if repeat_count < 1 or repeat_count > 5:
		return _configuration_error("INVALID_REPEAT", "--repeat musi mieścić się w zakresie 1..5.")

	return {
		"ok": true,
		"mode": mode,
		"output_format": output_format,
		"days": days,
		"repeat": repeat_count,
		"profiles": profile_result.values,
		"scenarios": scenario_result.values,
		"populations": population_result.values,
		"include_trace": bool(_arguments.get("trace", false)),
	}


func _build_report(configuration: Dictionary) -> Dictionary:
	var report := {
		"ok": true,
		"format_version": FORMAT_VERSION,
		"scope": {
			"kind": "deterministic_disease_domain_balance",
			"includes": ["DiseaseSystem", "MedicalCareSystem", "central_death_step"],
			"excludes": ["food_economy", "random_weather", "settlement_events", "autosave", "subjective_ui_playtest"],
			"interpretation": "Niekorzystny wynik jest sygnałem do przeglądu balansu, nie automatyczną porażką testu.",
		},
		"definition": {
			"id": str(FloodFever.id),
			"version": int(FloodFever.definition_version),
			"signature": str(FloodFever.configuration_signature),
			"authored_dive_pressure": int(FloodFever.authored_source_pressures.get(DIVE_HAZARD_SOURCE_ID, 0)),
		},
		"configuration": {
			"mode": str(configuration.mode),
			"days": int(configuration.days),
			"profiles": configuration.profiles.duplicate(),
			"populations": configuration.populations.duplicate(),
			"scenarios": configuration.scenarios.duplicate(),
			"include_trace": bool(configuration.include_trace),
		},
		"scenario_definitions": _selected_scenario_definitions(configuration.scenarios),
	}

	var mode := str(configuration.mode)
	if mode in ["all", "pressure"]:
		var pressure_oracle := _run_pressure_oracle(configuration.profiles)
		if not bool(pressure_oracle.get("ok", false)):
			return pressure_oracle
		report.pressure_oracle = pressure_oracle
	if mode in ["all", "strategies"]:
		var strategies := _run_strategy_matrix(configuration)
		if not bool(strategies.get("ok", false)):
			return strategies
		report.strategy_matrix = strategies
	if mode in ["all", "isolation"]:
		var isolation := _run_isolation_capacity_comparison()
		if not bool(isolation.get("ok", false)):
			return isolation
		report.isolation_capacity = isolation
	return report


func _run_pressure_oracle(profile_ids: Array) -> Dictionary:
	var rows: Array[Dictionary] = []
	for profile_id_value in profile_ids:
		var profile_id := str(profile_id_value)
		for base_pressure in [1, 2, 3]:
			for ration in ["full", "half", "none"]:
				for adverse_pressure in [0, 1]:
					var state_result := _new_state(profile_id, 3, 2)
					if not bool(state_result.get("ok", false)):
						return state_result
					var state = state_result.state
					var disease_case = _new_case(DiseaseCaseStateScript.Phase.EXPOSED, 1, base_pressure, "oracle", "pressure")
					if disease_case == null:
						return _runtime_error("INVALID_CASE_FIXTURE", "Nie udało się utworzyć przypadku oracle presji.")
					disease_case.last_resolved_day = 1
					state.find_survivor("igor").disease_cases.append(disease_case)
					var rations := _uniform_rations(state, "full")
					rations["igor"] = ration
					var projection := _disease_system.project_day(
						state,
						_definitions,
						rations,
						[],
						[],
						[],
						{
							"formal_isolation_capacity": 0,
							"adverse_conditions_pressure": adverse_pressure,
							"disease_pressure_modifier": int(state.difficulty_profile.disease_pressure_modifier),
						}
					)
					if not bool(projection.get("valid", false)):
						return _projection_error("PRESSURE_ORACLE_FAILED", profile_id, "pressure_oracle", 3, 2, projection)
					var cases_after := _projected_cases_for(projection, "igor")
					var outcome := "cleared"
					if not cases_after.is_empty():
						outcome = _phase_id(int(cases_after[0].phase))
					rows.append({
						"profile_id": profile_id,
						"difficulty_pressure_modifier": int(state.difficulty_profile.disease_pressure_modifier),
						"base_pressure": base_pressure,
						"ration": ration,
						"adverse_conditions_pressure": adverse_pressure,
						"outcome": outcome,
					})
	return {"ok": true, "cell_count": rows.size(), "rows": rows}


func _run_strategy_matrix(configuration: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = []
	for scenario_id_value in configuration.scenarios:
		var scenario_id := str(scenario_id_value)
		for profile_id_value in configuration.profiles:
			var profile_id := str(profile_id_value)
			for population_value in configuration.populations:
				var population := int(population_value)
				var row := _simulate_strategy(
					scenario_id,
					profile_id,
					population,
					int(configuration.days),
					bool(configuration.include_trace)
				)
				if not bool(row.get("ok", false)):
					return row
				rows.append(row)
	return {"ok": true, "run_count": rows.size(), "rows": rows}


func _simulate_strategy(
	scenario_id: String,
	profile_id: String,
	population: int,
	days: int,
	include_trace: bool
) -> Dictionary:
	var scenario := _scenario_definition(scenario_id)
	if scenario.is_empty():
		return _runtime_error("UNKNOWN_SCENARIO", "Nieznany scenariusz %s." % scenario_id)
	var start_day := int(scenario.start_day)
	var state_result := _new_state(profile_id, population, start_day)
	if not bool(state_result.get("ok", false)):
		return state_result
	var state = state_result.state
	state.resources.set_amount(ResourceIdsScript.MEDS_CHEMICALS, STARTING_MEDICINE)
	state.resources.set_amount(ResourceIdsScript.HOPE, STARTING_HOPE)
	var seed_result := _seed_scenario(state, scenario)
	if not bool(seed_result.get("ok", false)):
		return seed_result

	var metrics := {
		"ok": true,
		"scenario_id": scenario_id,
		"profile_id": profile_id,
		"profile_name": str(state.difficulty_profile.profile_name),
		"difficulty_pressure_modifier": int(state.difficulty_profile.disease_pressure_modifier),
		"population": population,
		"days_simulated": days,
		"starting_day": start_day,
		"starting_medicine": STARTING_MEDICINE,
		"medicine_spent": 0,
		"prophylaxis_doses": 0,
		"treatment_doses": 0,
		"medicine_shortage_days": 0,
		"care_unavailable_days": 0,
		"care_unavailable_reasons": {},
		"transmissions": 0,
		"work_contact_transmissions": 0,
		"community_contact_transmissions": 0,
		"peak_active": 0,
		"peak_contagious": 0,
		"outbreak_episodes": 0,
		"outbreak_days": 0,
		"first_outbreak_day": 0,
		"last_contained_day": 0,
		"disease_hope_delta": 0,
		"minimum_hope": STARTING_HOPE,
		"disease_health_lost": 0,
		"severe_damage_person_days": 0,
		"disease_deaths": 0,
		"containment_days_with_deaths": 0,
		"containment_left_no_living_survivors": false,
		"isolation_person_days": 0,
		"formal_isolation_person_days": 0,
		"emergency_isolation_person_days": 0,
		"active_case_person_days": 0,
		"contagious_case_person_days": 0,
		"phase_person_days": {
			"exposed": 0,
			"symptomatic": 0,
			"severe": 0,
			"recovering": 0,
			"immune": 0,
		},
		"work_equivalent_days_lost": 0.0,
		"dive_blocked_person_days": 0,
		"first_symptomatic_day": 0,
		"first_severe_day": 0,
		"first_case_free_day": 0,
	}
	var ever_exposed: Dictionary = {}
	var ever_symptomatic: Dictionary = {}
	var ever_severe: Dictionary = {}
	var trace: Array[Dictionary] = []

	for day_offset in range(days):
		var current_day := int(state.day)
		_record_phase_history(state, current_day, metrics, ever_exposed, ever_symptomatic, ever_severe)
		var isolated_ids := _strategy_isolated_ids(state, scenario_id, day_offset)
		var rations := _strategy_rations(state, scenario_id, day_offset)
		var work_snapshot := _strategy_work_snapshot(state, isolated_ids)
		metrics.isolation_person_days += isolated_ids.size()
		metrics.work_equivalent_days_lost += float(work_snapshot.work_equivalent_loss)
		metrics.dive_blocked_person_days += int(work_snapshot.dive_blocked)

		var care_result := _apply_strategy_care(state, scenario_id, day_offset, isolated_ids)
		if not bool(care_result.get("ok", false)):
			return care_result
		metrics.medicine_spent += int(care_result.medicine_spent)
		if bool(care_result.medicine_shortage):
			metrics.medicine_shortage_days += 1
		if (
			bool(care_result.care_requested)
			and int(care_result.patients_requiring_care) > 0
			and not bool(care_result.care_worked)
		):
			metrics.care_unavailable_days += 1
			var care_blocker_code := str(care_result.care_blocker_code)
			metrics.care_unavailable_reasons[care_blocker_code] = int(
				metrics.care_unavailable_reasons.get(care_blocker_code, 0)
			) + 1
		for commitment in care_result.commitments:
			if int(commitment.get("phase_before", -1)) == DiseaseCaseStateScript.Phase.EXPOSED:
				metrics.prophylaxis_doses += 1
			else:
				metrics.treatment_doses += 1

		var projection := _disease_system.project_day(
			state,
			_definitions,
			rations,
			work_snapshot.events,
			isolated_ids,
			care_result.commitments,
			{
				"formal_isolation_capacity": int(care_result.formal_isolation_capacity),
				"adverse_conditions_pressure": int(scenario.adverse_conditions_pressure),
				"disease_pressure_modifier": int(state.difficulty_profile.disease_pressure_modifier),
			}
		)
		if not bool(projection.get("valid", false)):
			return _projection_error("STRATEGY_PROJECTION_FAILED", profile_id, scenario_id, population, current_day, projection)

		var transmissions_today: Array = projection.get("transmissions", [])
		metrics.transmissions += transmissions_today.size()
		for transmission in transmissions_today:
			if str(transmission.get("source_kind", "")) == "work_contact":
				metrics.work_contact_transmissions += 1
			else:
				metrics.community_contact_transmissions += 1
		metrics.formal_isolation_person_days += projection.get("formal_isolated_survivor_ids", []).size()
		metrics.emergency_isolation_person_days += projection.get("emergency_isolated_survivor_ids", []).size()
		for survivor_result in projection.get("survivor_results", []):
			var health_delta := int(survivor_result.get("health_delta", 0))
			if health_delta < 0:
				metrics.disease_health_lost += abs(health_delta)
				metrics.severe_damage_person_days += 1

		var apply_result := _disease_system.apply_day(state, projection)
		if not bool(apply_result.get("applied", false)):
			return _runtime_error("STRATEGY_APPLY_FAILED", "Nie udało się zastosować projekcji %s/%s/pop%d/dzień%d: %s." % [profile_id, scenario_id, population, current_day, str(apply_result.get("blocker_code", ""))])

		var disease_hope_delta := int(apply_result.get("hope_delta", 0))
		metrics.disease_hope_delta += disease_hope_delta
		state.resources.set_amount(
			ResourceIdsScript.HOPE,
			clampi(int(state.resources.get_amount(ResourceIdsScript.HOPE)) + disease_hope_delta, 0, 100)
		)
		metrics.minimum_hope = mini(
			int(metrics.minimum_hope),
			int(state.resources.get_amount(ResourceIdsScript.HOPE))
		)
		if disease_hope_delta == DiseaseSystemScript.OUTBREAK_HOPE_LOSS and int(metrics.first_outbreak_day) == 0:
			metrics.first_outbreak_day = current_day
		if disease_hope_delta == DiseaseSystemScript.OUTBREAK_HOPE_RECOVERY:
			metrics.last_contained_day = current_day

		var alive_before := _present_survivor_ids(state)
		_death_resolver._resolve_deaths(state, null, ReportStateScript.new())
		var alive_after := _present_survivor_ids(state)
		var deaths_today := alive_before.size() - alive_after.size()
		metrics.disease_deaths += deaths_today
		if disease_hope_delta == DiseaseSystemScript.OUTBREAK_HOPE_RECOVERY and deaths_today > 0:
			metrics.containment_days_with_deaths += 1
			if alive_after.is_empty():
				metrics.containment_left_no_living_survivors = true

		_record_phase_history(state, current_day, metrics, ever_exposed, ever_symptomatic, ever_severe)
		var presentation := _disease_system.campaign_presentation(state, _definitions)
		var active_after := int(presentation.get("active_case_count", 0))
		var contagious_after := int(presentation.get("contagious_case_count", 0))
		metrics.peak_active = maxi(int(metrics.peak_active), active_after)
		metrics.peak_contagious = maxi(int(metrics.peak_contagious), contagious_after)
		metrics.active_case_person_days += active_after
		metrics.contagious_case_person_days += contagious_after
		var phase_counts_after := _phase_counts(state)
		for phase_key in metrics.phase_person_days.keys():
			metrics.phase_person_days[phase_key] = int(metrics.phase_person_days[phase_key]) + int(
				phase_counts_after.get(phase_key, 0)
			)
		metrics.outbreak_episodes = int(state.disease_campaign.outbreak_episode)
		if bool(state.disease_campaign.outbreak_active):
			metrics.outbreak_days += 1

		var no_active_disease := (
			int(presentation.get("active_case_count", 0)) == 0
			and int(presentation.get("pending_exposure_count", 0)) == 0
			and not bool(state.disease_campaign.outbreak_active)
		)
		if no_active_disease:
			if int(metrics.first_case_free_day) == 0:
				metrics.first_case_free_day = current_day

		if include_trace:
			trace.append(_daily_trace(
				state,
				current_day,
				projection,
				care_result,
				work_snapshot,
				isolated_ids,
				disease_hope_delta,
				alive_before.size() - alive_after.size()
			))
		state.day = current_day + 1
		state.begin_new_day_plan()

	metrics.people_ever_exposed = ever_exposed.size()
	metrics.people_ever_symptomatic = ever_symptomatic.size()
	metrics.people_ever_severe = ever_severe.size()
	metrics.secondary_attack_rate = snappedf(
		float(maxi(ever_symptomatic.size() - int(scenario.primary_seed_count), 0))
		/ float(maxi(population - 1, 1)),
		0.001
	)
	metrics.work_equivalent_days_lost = snappedf(float(metrics.work_equivalent_days_lost), 0.001)
	metrics.final_medicine = int(state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS))
	metrics.final_hope = int(state.resources.get_amount(ResourceIdsScript.HOPE))
	metrics.final_living = _present_survivor_ids(state).size()
	var final_presentation := _disease_system.campaign_presentation(state, _definitions)
	metrics.final_active = int(final_presentation.get("active_case_count", 0))
	metrics.final_contagious = int(final_presentation.get("contagious_case_count", 0))
	metrics.final_pending_exposures = int(final_presentation.get("pending_exposure_count", 0))
	metrics.final_outbreak_active = bool(state.disease_campaign.outbreak_active)
	if include_trace:
		metrics.trace = trace
	return metrics


func _run_isolation_capacity_comparison() -> Dictionary:
	var rows: Array[Dictionary] = []
	for formal_capacity in [0, 2, 4]:
		var state_result := _new_state("hard", 7, 2)
		if not bool(state_result.get("ok", false)):
			return state_result
		var state = state_result.state
		var isolated_ids: Array[String] = ["anka", "igor", "mira"]
		for survivor_id in isolated_ids:
			var disease_case = _new_case(DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, int(FloodFever.infection_threshold), "isolation_comparison", "source")
			if disease_case == null:
				return _runtime_error("INVALID_CASE_FIXTURE", "Nie udało się utworzyć przypadku porównania izolacji.")
			disease_case.last_resolved_day = 1
			state.find_survivor(survivor_id).disease_cases.append(disease_case)
		var projection := _disease_system.project_day(
			state,
			_definitions,
			_uniform_rations(state, "none"),
			[],
			isolated_ids,
			[],
			{
				"formal_isolation_capacity": formal_capacity,
				"adverse_conditions_pressure": 1,
				"disease_pressure_modifier": int(state.difficulty_profile.disease_pressure_modifier),
			}
		)
		if not bool(projection.get("valid", false)):
			return _projection_error("ISOLATION_COMPARISON_FAILED", "hard", "isolation", 7, 2, projection)
		rows.append({
			"formal_capacity": formal_capacity,
			"formal_isolated": projection.get("formal_isolated_survivor_ids", []).size(),
			"emergency_isolated": projection.get("emergency_isolated_survivor_ids", []).size(),
			"transmissions": projection.get("transmissions", []).size(),
			"settlement_contact_cap": maxi(1, ceili(7.0 / 4.0)),
		})
	return {"ok": true, "rows": rows}


func _new_state(profile_id: String, population: int, day: int) -> Dictionary:
	var profile_path := str(PROFILE_PATHS.get(profile_id, ""))
	if profile_path.is_empty() or not ResourceLoader.exists(profile_path):
		return _runtime_error("PROFILE_NOT_FOUND", "Brak profilu %s." % profile_id)
	var profile = ResourceLoader.load(profile_path)
	if profile == null or not profile.has_method("is_valid") or not profile.is_valid():
		return _runtime_error("INVALID_PROFILE", "Profil %s nie przechodzi walidacji." % profile_id)
	var snapshot = profile.create_campaign_snapshot()
	if snapshot == null or not snapshot.is_valid():
		return _runtime_error("INVALID_PROFILE_SNAPSHOT", "Nie udało się zamrozić profilu %s." % profile_id)

	var state = GameStateScript.new()
	state.day = day
	state.seed = 87000 + population * 100 + day
	state.difficulty_profile = snapshot
	state.survivors.clear()
	var survivor_ids: Array[String] = ["igor", "anka", "mira"]
	for index in range(4, population + 1):
		survivor_ids.append("sim_%02d" % index)
	for survivor_id in survivor_ids:
		var survivor = SurvivorStateScript.new()
		survivor.id = survivor_id
		survivor.display_name = survivor_id.capitalize()
		survivor.base_max_health = 100
		survivor.health = 100
		survivor.hunger = 0
		survivor.fatigue = 0
		survivor.morale = 55
		survivor.status = SurvivorStateScript.Status.AVAILABLE
		survivor.current_assignment = ""
		survivor.disease_cases.clear()
		state.survivors.append(survivor)
	state.disease_campaign.outbreak_active = false
	state.disease_campaign.outbreak_id = ""
	state.disease_campaign.outbreak_started_day = 0
	state.disease_campaign.outbreak_episode = 0
	state.disease_campaign.last_contained_day = 0
	state.disease_campaign.peak_cases = 0
	state.disease_campaign.last_resolved_day = maxi(day - 1, 0)
	state.disease_campaign.pending_exposures.clear()
	for resource_id in ResourceIdsScript.all():
		state.resources.set_amount(str(resource_id), 0)
	state.resources.set_amount(ResourceIdsScript.MEDS_CHEMICALS, STARTING_MEDICINE)
	state.resources.set_amount(ResourceIdsScript.HOPE, STARTING_HOPE)
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 100)
	state.resources.set_amount(ResourceIdsScript.FOOD, 999)
	state.begin_new_day_plan()
	return {"ok": true, "state": state}


func _seed_scenario(state, scenario: Dictionary) -> Dictionary:
	if bool(scenario.starts_symptomatic):
		var disease_case = _new_case(
			DiseaseCaseStateScript.Phase.SYMPTOMATIC,
			1,
			int(FloodFever.infection_threshold),
			"simulation",
			str(scenario.id)
		)
		if disease_case == null:
			return _runtime_error("INVALID_CASE_FIXTURE", "Nie udało się utworzyć przypadku początkowego dla %s." % str(scenario.id))
		disease_case.phase_started_day = 1
		disease_case.last_resolved_day = 1
		state.find_survivor("igor").disease_cases.append(disease_case)
		state.disease_campaign.last_resolved_day = 1
		return {"ok": true}
	var source_pressure := int(FloodFever.authored_source_pressures.get(DIVE_HAZARD_SOURCE_ID, 0))
	var exposure = DiseaseExposureStateScript.create(
		str(FloodFever.id),
		"igor",
		"dive",
		DIVE_HAZARD_SOURCE_ID,
		source_pressure,
		int(state.day)
	)
	if exposure == null or not exposure.is_valid():
		return _runtime_error("INVALID_EXPOSURE_FIXTURE", "Nie udało się utworzyć domenowego narażenia podczas nurkowania.")
	state.disease_campaign.pending_exposures.append(exposure)
	return {"ok": true}


func _new_case(phase: int, acquired_day: int, pressure: int, source_kind: String, source_id: String):
	var disease_case = DiseaseCaseStateScript.new()
	if not disease_case.setup_from_definition(FloodFever, phase, acquired_day, pressure, source_kind, source_id):
		return null
	return disease_case


func _strategy_isolated_ids(state, scenario_id: String, _day_offset: int) -> Array[String]:
	var result: Array[String] = []
	for survivor in state.survivors:
		if survivor == null or not survivor.is_present_in_settlement():
			continue
		var phase := _active_phase(survivor)
		var should_isolate := false
		match scenario_id:
			"prepared":
				should_isolate = phase in [
					DiseaseCaseStateScript.Phase.EXPOSED,
					DiseaseCaseStateScript.Phase.SYMPTOMATIC,
					DiseaseCaseStateScript.Phase.SEVERE,
				]
			"frugal_natural":
				should_isolate = phase in [DiseaseCaseStateScript.Phase.SYMPTOMATIC, DiseaseCaseStateScript.Phase.SEVERE]
			"late_outbreak_response":
				should_isolate = bool(state.disease_campaign.outbreak_active) and phase in [DiseaseCaseStateScript.Phase.SYMPTOMATIC, DiseaseCaseStateScript.Phase.SEVERE]
			"no_response":
				should_isolate = false
		if should_isolate:
			result.append(str(survivor.id))
	result.sort_custom(func(left: String, right: String) -> bool:
		var left_survivor = state.find_survivor(left)
		var right_survivor = state.find_survivor(right)
		var left_key := "%d|%09d|%s" % [_isolation_phase_priority(_active_phase(left_survivor)), int(left_survivor.health), left]
		var right_key := "%d|%09d|%s" % [_isolation_phase_priority(_active_phase(right_survivor)), int(right_survivor.health), right]
		return left_key < right_key
	)
	return result


func _strategy_rations(state, scenario_id: String, _day_offset: int) -> Dictionary:
	var result: Dictionary = {}
	for survivor in state.survivors:
		if survivor == null or not survivor.is_present_in_settlement():
			continue
		var ration := "full"
		match scenario_id:
			"prepared":
				ration = "full"
			"frugal_natural":
				var phase := _active_phase(survivor)
				ration = "full" if phase in [DiseaseCaseStateScript.Phase.SYMPTOMATIC, DiseaseCaseStateScript.Phase.SEVERE] else "half"
			"late_outbreak_response":
				ration = "full" if bool(state.disease_campaign.outbreak_active) else "none"
			"no_response":
				ration = "none"
		result[str(survivor.id)] = ration
	return result


func _strategy_work_snapshot(state, isolated_ids: Array[String]) -> Dictionary:
	var worker_ids: Array[String] = []
	var work_equivalent_loss := 0.0
	var dive_blocked := 0
	for survivor in state.survivors:
		if survivor == null or not survivor.is_present_in_settlement():
			continue
		var survivor_id := str(survivor.id)
		var isolated := survivor_id in isolated_ids
		var contribution := 0.0
		if not isolated and survivor.can_work():
			contribution = clampf(float(survivor.work_efficiency()), 0.0, 1.0)
			worker_ids.append(survivor_id)
		work_equivalent_loss += 1.0 - contribution
		if isolated or not survivor.can_dive():
			dive_blocked += 1
	worker_ids.sort()
	var events: Array[Dictionary] = []
	if not worker_ids.is_empty():
		events.append({
			"building_id": "simulation_shared_work",
			"action_id": "shared_shift",
			"worker_ids": worker_ids,
		})
	return {
		"events": events,
		"worker_ids": worker_ids,
		"work_equivalent_loss": work_equivalent_loss,
		"dive_blocked": dive_blocked,
	}


func _apply_strategy_care(state, scenario_id: String, _day_offset: int, isolated_ids: Array[String]) -> Dictionary:
	var care_enabled := false
	var infirmary_level := 0
	match scenario_id:
		"prepared":
			care_enabled = true
			infirmary_level = 3
		"late_outbreak_response":
			care_enabled = bool(state.disease_campaign.outbreak_active)
			infirmary_level = 1
	if not care_enabled:
		return {
			"ok": true,
			"care_requested": false,
			"care_worked": false,
			"care_blocker_code": "",
			"patients_requiring_care": 0,
			"medicine_spent": 0,
			"medicine_shortage": false,
			"commitments": [] as Array[Dictionary],
			"formal_isolation_capacity": 0,
		}
	var level_definition = InfirmaryDefinition.get_level_definition(infirmary_level)
	if level_definition == null:
		return _runtime_error("INFIRMARY_LEVEL_MISSING", "Brak poziomu %d Lecznicy." % infirmary_level)
	var capabilities: Dictionary = level_definition.capabilities
	var medic = state.find_survivor("mira")
	var medic_available: bool = (
		medic != null
		and medic.is_present_in_settlement()
		and str(medic.id) not in isolated_ids
		and medic.can_work()
	)
	var workforce := {
		"worker_count": 1 if medic_available else 0,
		"worker_ids": ["mira"] if medic_available else [] as Array[String],
		"worker_units": float(medic.work_efficiency()) if medic_available else 0.0,
		"specialist_bonus": 0.0,
	}
	var priorities := _medical_priority_ids(state)
	var projection := _medical_care_system.project(
		capabilities,
		workforce,
		WorkPaceSystemScript.WORK_PACE_NORMAL,
		float(state.difficulty_profile.recovery_speed_multiplier),
		int(state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS)),
		state.survivors,
		_definitions,
		priorities
	)
	var apply_result := _medical_care_system.apply(state, projection)
	if not bool(apply_result.get("applied", false)):
		return _runtime_error("MEDICAL_APPLY_FAILED", "Nie udało się zastosować opieki w %s, dzień %d: %s." % [scenario_id, int(state.day), str(apply_result.get("blocker_code", ""))])
	var commitments: Array[Dictionary] = []
	for commitment in projection.get("disease_treatment_commitments", []):
		commitments.append(commitment.duplicate(true))
	return {
		"ok": true,
		"care_requested": true,
		"care_worked": bool(projection.get("worked", false)),
		"care_blocker_code": str(projection.get("blocker_code", "")),
		"patients_requiring_care": int(projection.get("patients_requiring_care", 0)),
		"medicine_spent": int(apply_result.get("medicine_spent", 0)),
		"medicine_shortage": bool(projection.get("medicine_shortage", false)),
		"commitments": commitments,
		"formal_isolation_capacity": int(capabilities.get("formal_isolation_capacity", 0)),
		"treated_survivor_ids": projection.get("treated_survivor_ids", []).duplicate(),
	}


func _medical_priority_ids(state) -> Array[String]:
	var candidates: Array[String] = []
	for survivor in state.survivors:
		if survivor == null or not survivor.is_present_in_settlement() or _active_phase(survivor) < 0:
			continue
		candidates.append(str(survivor.id))
	candidates.sort_custom(func(left: String, right: String) -> bool:
		var left_survivor = state.find_survivor(left)
		var right_survivor = state.find_survivor(right)
		var left_key := "%d|%09d|%s" % [_medical_phase_priority(_active_phase(left_survivor)), int(left_survivor.health), left]
		var right_key := "%d|%09d|%s" % [_medical_phase_priority(_active_phase(right_survivor)), int(right_survivor.health), right]
		return left_key < right_key
	)
	return candidates


func _record_phase_history(
	state,
	day: int,
	metrics: Dictionary,
	ever_exposed: Dictionary,
	ever_symptomatic: Dictionary,
	ever_severe: Dictionary
) -> void:
	for survivor in state.survivors:
		if survivor == null or not survivor.is_present_in_settlement():
			continue
		for disease_case in survivor.disease_cases:
			if disease_case == null or str(disease_case.disease_id) != str(FloodFever.id):
				continue
			var survivor_id := str(survivor.id)
			match int(disease_case.phase):
				DiseaseCaseStateScript.Phase.EXPOSED:
					ever_exposed[survivor_id] = true
				DiseaseCaseStateScript.Phase.SYMPTOMATIC:
					ever_exposed[survivor_id] = true
					ever_symptomatic[survivor_id] = true
					if int(metrics.first_symptomatic_day) == 0:
						metrics.first_symptomatic_day = day
				DiseaseCaseStateScript.Phase.SEVERE:
					ever_exposed[survivor_id] = true
					ever_symptomatic[survivor_id] = true
					ever_severe[survivor_id] = true
					if int(metrics.first_symptomatic_day) == 0:
						metrics.first_symptomatic_day = day
					if int(metrics.first_severe_day) == 0:
						metrics.first_severe_day = day
				DiseaseCaseStateScript.Phase.RECOVERING, DiseaseCaseStateScript.Phase.IMMUNE:
					ever_exposed[survivor_id] = true


func _daily_trace(
	state,
	day: int,
	projection: Dictionary,
	care_result: Dictionary,
	work_snapshot: Dictionary,
	isolated_ids: Array[String],
	hope_delta: int,
	deaths_today: int
) -> Dictionary:
	var phase_counts := _phase_counts(state)
	return {
		"day": day,
		"phases": phase_counts,
		"active": int(projection.get("active_case_count_after", 0)),
		"contagious": int(projection.get("contagious_case_count_after", 0)),
		"transmissions": projection.get("transmissions", []).size(),
		"formal_isolated": projection.get("formal_isolated_survivor_ids", []).size(),
		"emergency_isolated": projection.get("emergency_isolated_survivor_ids", []).size(),
		"isolated_ids": isolated_ids.duplicate(),
		"worker_ids": work_snapshot.worker_ids.duplicate(),
		"medicine_spent": int(care_result.medicine_spent),
		"medicine_remaining": int(state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS)),
		"outbreak_active": bool(state.disease_campaign.outbreak_active),
		"outbreak_episode": int(state.disease_campaign.outbreak_episode),
		"disease_hope_delta": hope_delta,
		"deaths": deaths_today,
	}


func _phase_counts(state) -> Dictionary:
	var result := {
		"exposed": 0,
		"symptomatic": 0,
		"severe": 0,
		"recovering": 0,
		"immune": 0,
	}
	for survivor in state.survivors:
		if survivor == null or not survivor.is_present_in_settlement():
			continue
		for disease_case in survivor.disease_cases:
			var phase_id := _phase_id(int(disease_case.phase))
			if result.has(phase_id):
				result[phase_id] += 1
	return result


func _active_phase(survivor) -> int:
	if survivor == null:
		return -1
	for disease_case in survivor.disease_cases:
		if disease_case != null and str(disease_case.disease_id) == str(FloodFever.id):
			return int(disease_case.phase)
	return -1


func _phase_id(phase: int) -> String:
	match phase:
		DiseaseCaseStateScript.Phase.EXPOSED:
			return "exposed"
		DiseaseCaseStateScript.Phase.SYMPTOMATIC:
			return "symptomatic"
		DiseaseCaseStateScript.Phase.SEVERE:
			return "severe"
		DiseaseCaseStateScript.Phase.RECOVERING:
			return "recovering"
		DiseaseCaseStateScript.Phase.IMMUNE:
			return "immune"
	return "unknown"


func _isolation_phase_priority(phase: int) -> int:
	match phase:
		DiseaseCaseStateScript.Phase.SEVERE:
			return 0
		DiseaseCaseStateScript.Phase.SYMPTOMATIC:
			return 1
		DiseaseCaseStateScript.Phase.EXPOSED:
			return 2
	return 3


func _medical_phase_priority(phase: int) -> int:
	return _isolation_phase_priority(phase)


func _uniform_rations(state, ration: String) -> Dictionary:
	var result: Dictionary = {}
	for survivor in state.survivors:
		if survivor != null and survivor.is_present_in_settlement():
			result[str(survivor.id)] = ration
	return result


func _projected_cases_for(projection: Dictionary, survivor_id: String) -> Array:
	for survivor_result in projection.get("survivor_results", []):
		if str(survivor_result.get("survivor_id", "")) == survivor_id:
			return survivor_result.get("disease_cases_after", [])
	return []


func _present_survivor_ids(state) -> Array[String]:
	var result: Array[String] = []
	for survivor in state.survivors:
		if survivor != null and survivor.is_present_in_settlement():
			result.append(str(survivor.id))
	result.sort()
	return result


func _scenario_definition(scenario_id: String) -> Dictionary:
	match scenario_id:
		"prepared":
			return {
				"id": scenario_id,
				"label": "Przygotowana profilaktyka",
				"primary_seed_count": 1,
				"starts_symptomatic": false,
				"start_day": 1,
				"adverse_conditions_pressure": 1,
				"description": "Skażony odzysk, pełne racje, izolacja każdego aktywnego przypadku i Lecznica III z profilaktyką/terapią.",
			}
		"frugal_natural":
			return {
				"id": scenario_id,
				"label": "Oszczędne zdrowienie naturalne",
				"primary_seed_count": 1,
				"starts_symptomatic": false,
				"start_day": 1,
				"adverse_conditions_pressure": 1,
				"description": "Skażony odzysk, połowa racji w Narażeniu, potem pełna racja, izolacja awaryjna i brak leczenia.",
			}
		"late_outbreak_response":
			return {
				"id": scenario_id,
				"label": "Reakcja dopiero na epidemię",
				"primary_seed_count": 1,
				"starts_symptomatic": false,
				"start_day": 1,
				"adverse_conditions_pressure": 1,
				"description": "Skażony odzysk, początkowo brak racji/izolacji/leczenia; po wybuchu pełne racje, izolacja i Lecznica I.",
			}
		"no_response":
			return {
				"id": scenario_id,
				"label": "Brak reakcji — stress bound",
				"primary_seed_count": 1,
				"starts_symptomatic": false,
				"start_day": 1,
				"adverse_conditions_pressure": 1,
				"description": "Skażony odzysk, brak racji, izolacji i opieki przez cały horyzont; granica skutków, nie rozsądna strategia gracza.",
			}
	return {}


func _selected_scenario_definitions(scenario_ids: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for scenario_id in scenario_ids:
		result.append(_scenario_definition(str(scenario_id)))
	return result


func _print_human_report(report: Dictionary) -> void:
	print("=== GORĄCZKA ZALEWOWA — DETERMINISTYCZNY RAPORT BALANSU ===")
	print("Zakres: DiseaseSystem + MedicalCareSystem + centralny krok zgonów; bez ekonomii jedzenia, losowej pogody, wydarzeń i autosave.")
	if report.has("pressure_oracle"):
		print("Macierz presji: %d komórek." % int(report.pressure_oracle.cell_count))
	if report.has("strategy_matrix"):
		print("Scenariusz | Profil | Pop | Objawy | Ciężkie | Kontakty | Epid. dni | Leki | Zgony | Hope chor. | Strata pracy")
		for row in report.strategy_matrix.rows:
			print("%s | %s | %d | %d | %d | %d | %d | %d | %d | %+d | %.2f" % [
				str(row.scenario_id),
				str(row.profile_id),
				int(row.population),
				int(row.people_ever_symptomatic),
				int(row.people_ever_severe),
				int(row.transmissions),
				int(row.outbreak_days),
				int(row.medicine_spent),
				int(row.disease_deaths),
				int(row.disease_hope_delta),
				float(row.work_equivalent_days_lost),
			])
		for row in report.strategy_matrix.rows:
			if bool(row.containment_left_no_living_survivors):
				print("UWAGA: %s/%s/pop%d — opanowanie epidemii zbiegło się ze śmiercią ostatnich mieszkańców." % [
					str(row.scenario_id),
					str(row.profile_id),
					int(row.population),
				])
	if report.has("isolation_capacity"):
		print("Izolacja formalna | Formalni | Awaryjni | Nowe kontakty")
		for row in report.isolation_capacity.rows:
			print("%d | %d | %d | %d" % [
				int(row.formal_capacity),
				int(row.formal_isolated),
				int(row.emergency_isolated),
				int(row.transmissions),
			])


func _parse_arguments(values: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		var argument := str(value)
		if not argument.begins_with("--"):
			continue
		var normalized := argument.trim_prefix("--")
		var separator := normalized.find("=")
		if separator < 0:
			result[normalized.replace("-", "_")] = true
			continue
		var key := normalized.substr(0, separator).replace("-", "_")
		result[key] = normalized.substr(separator + 1)
	return result


func _parse_string_list(value: String, allowed_values: Array) -> Dictionary:
	var allowed: Array[String] = []
	for allowed_value in allowed_values:
		allowed.append(str(allowed_value))
	var result: Array[String] = []
	for raw_value in value.split(",", false):
		var normalized := str(raw_value).strip_edges().to_lower()
		if normalized.is_empty() or normalized not in allowed:
			return _configuration_error("UNKNOWN_LIST_VALUE", "Nieznana wartość '%s'. Dozwolone: %s." % [normalized, ", ".join(allowed)])
		if normalized not in result:
			result.append(normalized)
	if result.is_empty():
		return _configuration_error("EMPTY_LIST", "Lista parametrów nie może być pusta.")
	return {"ok": true, "values": result}


func _parse_population_list(value: String) -> Dictionary:
	var result: Array[int] = []
	for raw_value in value.split(",", false):
		var normalized := str(raw_value).strip_edges()
		if not normalized.is_valid_int():
			return _configuration_error("INVALID_POPULATION", "Populacja '%s' nie jest liczbą całkowitą." % normalized)
		var population := int(normalized)
		if population < 3 or population > 20:
			return _configuration_error("INVALID_POPULATION", "Populacja musi mieścić się w zakresie 3..20.")
		if population not in result:
			result.append(population)
	result.sort()
	if result.is_empty():
		return _configuration_error("EMPTY_POPULATIONS", "Lista populacji nie może być pusta.")
	return {"ok": true, "values": result}


func _configuration_error(code: String, message: String) -> Dictionary:
	return {"ok": false, "failure_code": code, "failure_message": message}


func _runtime_error(code: String, message: String) -> Dictionary:
	return {"ok": false, "failure_code": code, "failure_message": message}


func _projection_error(code: String, profile_id: String, scenario_id: String, population: int, day: int, projection: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"failure_code": code,
		"failure_message": "Projekcja nie powiodła się: profil=%s scenariusz=%s populacja=%d dzień=%d blocker=%s warnings=%s." % [
			profile_id,
			scenario_id,
			population,
			day,
			str(projection.get("blocker_code", "")),
			str(projection.get("warnings", [])),
		],
	}


func _fingerprint(value) -> String:
	return JSON.stringify(_json_safe(value), "", false)


func _finish(result: Dictionary, exit_code: int) -> void:
	print("DISEASE_BALANCE_REPORT=" + JSON.stringify(_json_safe(result), "", false))
	quit(exit_code)


func _json_safe(value):
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort_custom(func(left, right) -> bool: return str(left) < str(right))
		for key in keys:
			result[str(key)] = _json_safe(value[key])
		return result
	if value is Array or value is PackedStringArray:
		var result: Array = []
		for element in value:
			result.append(_json_safe(element))
		return result
	if value is Resource:
		return value.resource_path
	return value
