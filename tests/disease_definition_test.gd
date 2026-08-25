extends SceneTree

const DiseaseDefinitionScript := preload("res://scripts/definitions/DiseaseDefinition.gd")
const DiseaseCaseStateScript := preload("res://scripts/data/DiseaseCaseState.gd")
const DiseaseExposureStateScript := preload("res://scripts/data/DiseaseExposureState.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const GameDatabaseScript := preload("res://scripts/core/GameDatabase.gd")
const FloodFever := preload("res://data/diseases/flood_fever.tres")

const DIVE_HAZARD_SOURCE_ID := "contaminated_salvage"
const EXPECTED_SIGNATURE := "800e2fdd69a88394ebc501ae79701e453fd2661c6233fcb1b3d4eb60bb925f86"

var _failures := 0


func _initialize() -> void:
	print("Disease definitions: catalog, frozen cases, exposure boundary and survivor effects")
	_test_production_definition()
	_test_snapshot_and_signature()
	_test_case_phase_boundaries()
	_test_exposure_boundary()
	_test_survivor_central_effects()
	_test_database_catalog()
	if _failures > 0:
		push_error("Disease definition test failed with %d assertion(s)." % _failures)
		quit(1)
		return
	print("Disease definition test passed.")
	quit(0)


func _test_production_definition() -> void:
	_assert(FloodFever.get_script() == DiseaseDefinitionScript, "Flood fever must use the exact DiseaseDefinition script.")
	_assert(FloodFever.validation_errors().is_empty(), "Production definition must pass full validation: %s" % "; ".join(FloodFever.validation_errors()))
	_assert(FloodFever.id == "flood_fever" and FloodFever.display_name == "Gorączka Zalewowa", "Production identity must remain stable.")
	_assert(FloodFever.definition_version == 2, "Production definition version must be two after replacing the authored exposure source.")
	_assert(FloodFever.infection_threshold == 4, "Standard infection threshold must be four.")
	_assert(FloodFever.authored_source_pressures == {DIVE_HAZARD_SOURCE_ID: 3}, "The neutral dive hazard must be the only authored source and contribute pressure three.")
	_assert(FloodFever.ration_pressure_modifiers == {"full": -1, "half": 0, "none": 1}, "Actual ration modifiers must be exactly -1/0/+1.")
	_assert(FloodFever.adverse_conditions_pressure_cap == 1, "Adverse weather and shelter may add at most one pressure.")
	_assert(FloodFever.emergency_isolation_contact_pressure == 1, "Emergency isolation community contact pressure must be one.")
	_assert(FloodFever.natural_recovery_days == 2 and FloodFever.recovering_days == 1 and FloodFever.immunity_days == 3, "Recovery and immunity durations must be 2/1/3 days.")
	_assert(FloodFever.treatment_medicine_cost == 1 and FloodFever.prophylaxis_medicine_cost == 1, "Treatment and prophylaxis must each cost one medicine.")
	_assert(FloodFever.configuration_signature == EXPECTED_SIGNATURE, "The authored signature must be explicit and stable.")
	_assert(FloodFever.compute_configuration_signature() == EXPECTED_SIGNATURE, "The computed signature must match authored disease data.")

	var expected := {
		"exposed": {"work": 1.0, "dive": true, "infectious": false, "contact": 0, "health": 0},
		"symptomatic": {"work": 0.65, "dive": false, "infectious": true, "contact": 2, "health": 0},
		"severe": {"work": 0.0, "dive": false, "infectious": true, "contact": 3, "health": -15},
		"recovering": {"work": 0.8, "dive": false, "infectious": false, "contact": 0, "health": 0},
		"immune": {"work": 1.0, "dive": true, "infectious": false, "contact": 0, "health": 0},
	}
	for phase_id in DiseaseDefinitionScript.PHASE_IDS:
		var stage = FloodFever.find_stage(phase_id)
		var contract: Dictionary = expected[phase_id]
		_assert(stage != null, "Every supported phase must have an authored stage: %s." % phase_id)
		if stage == null:
			continue
		_assert(is_equal_approx(float(stage.work_efficiency_multiplier), float(contract.work)), "Work multiplier must match for %s." % phase_id)
		_assert(bool(stage.dive_allowed) == bool(contract.dive), "Dive permission must match for %s." % phase_id)
		_assert(bool(stage.infectious) == bool(contract.infectious), "Infectious flag must match for %s." % phase_id)
		_assert(int(stage.contact_pressure) == int(contract.contact), "Contact pressure must match for %s." % phase_id)
		_assert(int(stage.daily_health_delta) == int(contract.health), "Health delta must match for %s." % phase_id)

	var unbounded = FloodFever.duplicate(true)
	unbounded.ration_pressure_modifiers = {"full": -100000, "half": 0, "none": 1}
	_assert(_errors_contain(unbounded.validation_errors(), "between -10 and 10"), "Generic definition validation must reject unbounded ration pressure.")


func _test_snapshot_and_signature() -> void:
	var snapshot = FloodFever.create_snapshot()
	_assert(snapshot != null and snapshot != FloodFever, "A disease case snapshot must be detached from authored data.")
	_assert(snapshot != null and snapshot.resource_path.is_empty(), "A disease snapshot must not retain the live .tres path.")
	_assert(snapshot != null and snapshot.has_valid_configuration_signature(), "A detached snapshot must preserve its valid configuration signature.")
	if snapshot == null:
		return
	var source_multiplier := float(FloodFever.find_stage("symptomatic").work_efficiency_multiplier)
	snapshot.find_stage("symptomatic").work_efficiency_multiplier = 0.5
	_assert(is_equal_approx(float(FloodFever.find_stage("symptomatic").work_efficiency_multiplier), source_multiplier), "Mutating a snapshot must not mutate production data.")
	_assert(not snapshot.has_valid_configuration_signature(), "Any mutation of frozen tuning must invalidate its signature.")


func _test_case_phase_boundaries() -> void:
	var expectations := {
		DiseaseCaseStateScript.Phase.EXPOSED: {"id": "exposed", "work": 1.0, "dive": true, "infectious": false},
		DiseaseCaseStateScript.Phase.SYMPTOMATIC: {"id": "symptomatic", "work": 0.65, "dive": false, "infectious": true},
		DiseaseCaseStateScript.Phase.SEVERE: {"id": "severe", "work": 0.0, "dive": false, "infectious": true},
		DiseaseCaseStateScript.Phase.RECOVERING: {"id": "recovering", "work": 0.8, "dive": false, "infectious": false},
		DiseaseCaseStateScript.Phase.IMMUNE: {"id": "immune", "work": 1.0, "dive": true, "infectious": false},
	}
	for phase in expectations.keys():
		var disease_case = DiseaseCaseStateScript.new()
		var setup_ok: bool = disease_case.setup_from_definition(FloodFever, int(phase), 5, 4, "test", "phase_boundary")
		var expected: Dictionary = expectations[phase]
		_assert(setup_ok, "Every supported phase must create a valid frozen case: %s." % expected.id)
		_assert(disease_case.phase_id() == expected.id, "Phase enum and stable ID must round-trip for %s." % expected.id)
		_assert(DiseaseCaseStateScript.phase_from_id(expected.id) == int(phase), "Stable phase ID must map back to its enum.")
		_assert(is_equal_approx(disease_case.work_efficiency_multiplier(), float(expected.work)), "Case work multiplier must come from its frozen stage.")
		_assert(disease_case.can_dive() == bool(expected.dive), "Case dive permission must come from its frozen stage.")
		_assert(disease_case.is_infectious() == bool(expected.infectious), "Case infectious state must come from its frozen stage.")
		_assert(disease_case.validation_errors().is_empty(), "A configured %s case must validate: %s" % [expected.id, "; ".join(disease_case.validation_errors())])

	var tampered = DiseaseCaseStateScript.new()
	_assert(tampered.setup_from_definition(FloodFever, DiseaseCaseStateScript.Phase.EXPOSED, 2, 3, "dive", DIVE_HAZARD_SOURCE_ID), "Tamper fixture must start valid.")
	tampered.definition_snapshot.find_stage("exposed").dive_allowed = false
	_assert(_errors_contain(tampered.validation_errors(), "configuration_signature"), "A case with mutated frozen tuning must be rejected, not rebuilt from live data.")


func _test_exposure_boundary() -> void:
	var exposure = DiseaseExposureStateScript.create("flood_fever", "mira", "dive", DIVE_HAZARD_SOURCE_ID, 3, 2)
	_assert(exposure.validation_errors().is_empty(), "A complete domain dive exposure must validate.")
	var detached = exposure.detached_copy()
	_assert(detached != null and detached != exposure and detached.validation_errors().is_empty(), "Exposure clone must be detached and valid.")
	if detached != null:
		detached.pressure = 1
		_assert(exposure.pressure == 3, "Mutating a detached exposure must not mutate its source.")
	var self_contact = DiseaseExposureStateScript.create("flood_fever", "mira", "contact", "igor", 2, 3, "mira")
	_assert(_errors_contain(self_contact.validation_errors(), "nie może być jego celem"), "A survivor cannot be both source and target of one exposure.")


func _test_survivor_central_effects() -> void:
	var survivor = SurvivorStateScript.new()
	survivor.id = "test_survivor"
	survivor.display_name = "Test"
	survivor.health = 100
	survivor.hunger = 0
	survivor.fatigue = 0
	survivor.morale = 55
	_assert(survivor.can_work() and survivor.can_dive(), "A healthy resident should start eligible for work and diving.")

	var symptomatic = DiseaseCaseStateScript.new()
	_assert(symptomatic.setup_from_definition(FloodFever, DiseaseCaseStateScript.Phase.SYMPTOMATIC, 1, 4, "contact", "igor"), "Symptomatic fixture must be valid.")
	survivor.disease_cases.append(symptomatic)
	_assert(is_equal_approx(survivor.disease_work_efficiency_multiplier(), 0.65), "The central disease multiplier must be 65% for symptoms.")
	_assert(is_equal_approx(survivor.work_efficiency(), 0.65), "Existing work efficiency must compose with the minimum disease multiplier.")
	_assert(not survivor.can_dive() and not survivor.dive_blocker().is_empty(), "Symptoms must block diving through the central blocker.")

	symptomatic.phase = DiseaseCaseStateScript.Phase.SEVERE
	_assert(not survivor.can_work() and not survivor.work_blocker().is_empty(), "Severe disease must block work through the central blocker.")
	symptomatic.phase = DiseaseCaseStateScript.Phase.EXPOSED
	_assert(survivor.can_work() and survivor.can_dive(), "Exposure must preserve full work and allow diving.")


func _test_database_catalog() -> void:
	var database = GameDatabaseScript.new()
	database.load_definitions()
	_assert(database.validation_errors.is_empty(), "The complete database must accept the closed disease catalog: %s" % "; ".join(database.validation_errors))
	_assert(database.diseases.size() == 1 and database.get_disease_definition("flood_fever") == database.diseases.get("flood_fever"), "The disease catalog must expose exactly the production flood_fever definition by stable ID.")
	database.free()


func _errors_contain(errors: PackedStringArray, fragment: String) -> bool:
	var folded := fragment.to_lower()
	for error in errors:
		if str(error).to_lower().contains(folded):
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Disease definition assertion failed: " + message)
