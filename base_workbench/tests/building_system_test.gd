extends SceneTree

const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const BuildingEffectSystemScript := preload("res://base_workbench/systems/BuildingEffectSystem.gd")
const BuildingSystemScript := preload("res://base_workbench/systems/BuildingSystem.gd")
const BuildingWorkSystemScript := preload("res://base_workbench/systems/BuildingWorkSystem.gd")
const EndOfDayResolverScript := preload("res://scripts/campaign/EndOfDayResolver.gd")
const MedicalCareSystemScript := preload("res://base_workbench/systems/MedicalCareSystem.gd")
const ProductionSystemScript := preload("res://base_workbench/systems/ProductionSystem.gd")
const RationAllocationSystemScript := preload("res://base_workbench/systems/RationAllocationSystem.gd")
const ReportStateScript := preload("res://scripts/data/ReportState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const GameDatabaseScript := preload("res://scripts/core/GameDatabase.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const PolicyStateScript := preload("res://scripts/data/PolicyState.gd")
const WorkPaceSystemScript := preload("res://base_workbench/systems/WorkPaceSystem.gd")
const WorkshopOrderStateScript := preload("res://scripts/data/WorkshopOrderState.gd")

const TEST_HEAVY_OBJECT_ID := "fixture_heavy_object"

const BUILDING_SLOTS := {
	"fishing_hut": "top_left",
	"kitchen": "top_center",
	"community_house": "top_right",
	"workshop": "bottom_left",
	"infirmary": "center",
	"diving_station": "bottom_right",
}
const BUILDING_DEFINITIONS := {
	"fishing_hut": preload("res://base_workbench/data/buildings/fishing_hut.tres"),
	"kitchen": preload("res://base_workbench/data/buildings/kitchen.tres"),
	"community_house": preload("res://base_workbench/data/buildings/community_house.tres"),
	"workshop": preload("res://base_workbench/data/buildings/workshop.tres"),
	"infirmary": preload("res://base_workbench/data/buildings/infirmary.tres"),
	"diving_station": preload("res://base_workbench/data/buildings/diving_station.tres"),
}
const LEVEL_EFFECT_TOKENS := {
	"diving_station:1": ["1 stanowisko", "6 miejsc", "Kombinezon poziomu 1"],
	"diving_station:2": ["2 stanowiska", "10 miejsc", "Operator liny", "50%"],
	"diving_station:3": ["14 miejsc", "1 trwałą boję", "Kombinezon poziomu 3", "„Sonar”", "„komora ciśnieniowa”", "osobnej mechaniki skanowania ani ciśnienia"],
	"diving_station:4": ["3 stanowiska", "16 miejsc", "Technik wyprawy", "2 użycia", "10% mniej", "„Dzwon głębinowy”", "nie tworzy osobnego wyjścia"],
	"fishing_hut:1": ["5 jedzenia", "1.6%"],
	"fishing_hut:2": ["5 jedzenia", "1%", "„Magazyn przynęt”", "osobnego zasobu ani kosztu przynęty"],
	"fishing_hut:3": ["6 jedzenia", "0.8%"],
	"fishing_hut:4": ["6 jedzenia", "0.6%", "„Akwakultura”", "bez osobnej pasywnej hodowli"],
	"kitchen:1": ["Miejsca pracy dla dziennego efektu: 1", "8%", "Kuchnia nie tworzy jedzenia", "„Wędzarnia”", "nie tworzy osobnej produkcji"],
	"kitchen:2": ["Miejsca pracy dla dziennego efektu: 1", "14%", "1 zdolny pracownik"],
	"kitchen:3": ["Miejsca pracy dla dziennego efektu: 2", "20%", "„Spiżarnia”", "magazynu żywności"],
	"kitchen:4": ["Miejsca pracy dla dziennego efektu: 2", "26%", "2 punkty procentowe"],
	"workshop:1": ["3 punktów integralności", "1 zleceń", "100 punktów pracy", "Latarnia nurkowa II"],
	"workshop:2": ["5 punktów integralności", "2 zleceń", "100 punktów pracy", "Butla tlenowa II"],
	"workshop:3": ["7 punktów integralności", "3 zleceń", "200 punktów pracy", "Butla tlenowa III", "ciężki obiekt"],
	"workshop:4": ["10 punktów integralności", "4 zleceń", "300 punktów pracy"],
	"infirmary:1": ["1 rannych", "+12 zdrowia", "1 jednostkę leków", "„Suszarnia”", "konserwacji żywności"],
	"infirmary:2": ["2 rannych", "+18 zdrowia"],
	"infirmary:3": ["4 rannych", "+24 zdrowia", "Formalna Izolatka", "pierwszych 2 osób"],
	"infirmary:4": ["6 rannych", "+32 zdrowia", "Formalna Izolatka", "pierwszych 4 osób"],
	"community_house:1": ["4 suchych miejsc", "+1 Nadziei"],
	"community_house:2": ["7 suchych miejsc", "+2 Nadziei", "drugą specjalizację"],
	"community_house:3": ["11 suchych miejsc", "+3 Nadziei", "drugą specjalizację", "„Radiostacja”", "stabilną łączność", "Wspólnej Linii", "osobnego panelu radia"],
	"community_house:4": ["16 suchych miejsc", "+5 Nadziei", "„Latarnia Przystani”", "systemu nawigacji"],
}
const NEXT_LEVEL_NAME_BOUNDARY_TOKENS := {
	"diving_station:2": "„Sonar”",
	"diving_station:3": "„Dzwon głębinowy”",
	"fishing_hut:1": "„Magazyn przynęt”",
	"fishing_hut:3": "„Akwakultura”",
	"kitchen:1": "„Wędzarnia”",
	"kitchen:2": "„Spiżarnia”",
	"community_house:2": "„Radiostacja”",
	"community_house:3": "„Latarnia Przystani”",
}

const TALENT_FISHING_STEWARD := "rybak_straznik_lowiska"
const TALENT_FORCED_FISHING := "rybak_polow_forsowny"
const TALENT_MAINTAINER := "mechanik_konserwator"
const TALENT_REHABILITATOR := "medyk_rehabilitant"
const REQUIRED_CAPABILITY_FIXTURES := [
	{"building_id": "fishing_hut", "from_level": 1, "capability_id": "food_per_worker"},
	{"building_id": "fishing_hut", "from_level": 1, "capability_id": "fishing_pressure_per_food"},
	{"building_id": "kitchen", "from_level": 1, "capability_id": "ration_efficiency"},
	{"building_id": "community_house", "from_level": 1, "capability_id": "hope_per_worker"},
	{"building_id": "community_house", "from_level": 1, "capability_id": "shelter_capacity"},
	{"building_id": "workshop", "from_level": 1, "capability_id": "platform_repair_per_worker"},
	{"building_id": "workshop", "from_level": 1, "capability_id": "production_queue_capacity"},
	{"building_id": "workshop", "from_level": 1, "capability_id": "production_slots_per_day"},
	{"building_id": "workshop", "from_level": 1, "capability_id": "repair_scrap_cost"},
	{"building_id": "workshop", "from_level": 3, "capability_id": "heavy_recovery_enabled"},
	{"building_id": "infirmary", "from_level": 1, "capability_id": "healing_per_patient"},
	{"building_id": "infirmary", "from_level": 1, "capability_id": "medicine_per_patient"},
	{"building_id": "infirmary", "from_level": 1, "capability_id": "patient_capacity"},
	{"building_id": "diving_station", "from_level": 1, "capability_id": "backpack_slots"},
	{"building_id": "diving_station", "from_level": 1, "capability_id": "can_dive"},
	{"building_id": "diving_station", "from_level": 2, "capability_id": "operator_rescue_enabled"},
	{"building_id": "diving_station", "from_level": 3, "capability_id": "buoy_enabled"},
	{"building_id": "diving_station", "from_level": 4, "capability_id": "buoy_start_enabled"},
	{"building_id": "diving_station", "from_level": 4, "capability_id": "heavy_marking_enabled"},
	{"building_id": "diving_station", "from_level": 4, "capability_id": "technician_support_enabled"},
	{"building_id": "diving_station", "from_level": 4, "capability_id": "technician_suit_damage_multiplier"},
]
const INVALID_CAPABILITY_VALUE_FIXTURES := [
	{"building_id": "fishing_hut", "level": 1, "capability_id": "food_per_worker", "value": 3.0},
	{"building_id": "fishing_hut", "level": 1, "capability_id": "fishing_pressure_per_food", "value": "0.05"},
	{"building_id": "community_house", "level": 1, "capability_id": "hope_per_worker", "value": 0},
	{"building_id": "kitchen", "level": 1, "capability_id": "ration_efficiency", "value": 1.01},
	{"building_id": "workshop", "level": 3, "capability_id": "heavy_recovery_enabled", "value": false},
	{"building_id": "diving_station", "level": 1, "capability_id": "can_dive", "value": 1},
	{"building_id": "diving_station", "level": 4, "capability_id": "technician_suit_damage_multiplier", "value": 0.0},
	{"building_id": "diving_station", "level": 4, "capability_id": "technician_suit_damage_multiplier", "value": 1.0},
]
const REQUIRED_SPECIALIST_BONUS_FIXTURES := [
	{"building_id": "fishing_hut", "bonus_id": "production_bonus"},
	{"building_id": "kitchen", "bonus_id": "ration_efficiency_bonus"},
	{"building_id": "community_house", "bonus_id": "hope_bonus"},
	{"building_id": "workshop", "bonus_id": "repair_bonus"},
	{"building_id": "infirmary", "bonus_id": "healing_bonus"},
	{"building_id": "diving_station", "bonus_id": "oxygen_bonus"},
	{"building_id": "diving_station", "bonus_id": "oxygen_capacity_multiplier"},
]

var _failed := false

func _initialize() -> void:
	_test_database_validates_required_building_contracts()
	_test_shared_building_work_projection_contracts()
	_test_fishing_horizon_balance()
	_test_complete_upgrade_data_and_lifecycle()
	_test_effect_descriptions_for_every_building_level()
	_test_shared_panel_renders_descriptions_for_every_building()
	_test_contextual_work_pace_panel_copy()
	_test_staffing_forecast_matches_day_resolution()
	_test_ration_allocation_contract()
	_test_kitchen_forecast_matches_ration_policies()
	_test_station_diver_capability_uses_expedition_requirements()
	_test_infirmary_injury_forecast_matches_resolution()
	_test_zero_output_workshop_forecast_matches_resolution()
	_test_workshop_priority_preview_skips_non_working_queue_heads()
	_test_local_work_pace_effects()
	_test_house_zero_output_counts_as_real_work()
	_test_work_tension_hope_aggregation()
	_test_daily_building_effects()
	if _failed:
		quit(1)
		return
	print("Building system test passed: all levels expose concrete effects, staffing forecasts match settlement, and daily effects resolve correctly.")
	quit(0)


func _test_database_validates_required_building_contracts() -> void:
	var database = GameDatabaseScript.new()
	var canonical_errors: Array[String] = database.required_building_validation_errors(_building_definition_copies())
	_assert(canonical_errors.is_empty(), "The six canonical building resources should satisfy the GameDatabase contract: %s" % str(canonical_errors))

	var missing_definition := _building_definition_copies()
	missing_definition.erase("kitchen")
	_assert(
		_validation_error_contains_all(database.required_building_validation_errors(missing_definition), ["Brak definicji budynku", "kitchen"]),
		"GameDatabase should reject a missing required building definition."
	)

	var unexpected_definition := _building_definition_copies()
	unexpected_definition["seventh_building"] = BUILDING_DEFINITIONS["kitchen"].duplicate(true)
	_assert(
		_validation_error_contains_all(database.required_building_validation_errors(unexpected_definition), ["Nieoczekiwana definicja budynku", "seventh_building", "dokładnie sześć"]),
		"GameDatabase should reject a seventh definition that has no canonical platform slot."
	)

	var invalid_definition_type := _building_definition_copies()
	invalid_definition_type["infirmary"] = Resource.new()
	_assert(
		_validation_error_contains_all(database.required_building_validation_errors(invalid_definition_type), ["infirmary", "niewłaściwy typ definicji"]),
		"GameDatabase should reject a required entry that is not a BuildingDefinition."
	)

	var invalid_text := _building_definition_copies()
	invalid_text["kitchen"].display_name = "  "
	invalid_text["community_house"].description = "\t"
	var invalid_text_errors: Array[String] = database.required_building_validation_errors(invalid_text)
	_assert(_validation_error_contains_all(invalid_text_errors, ["kitchen", "pustą wartość display_name"]), "Every required building needs a nonempty display_name.")
	_assert(_validation_error_contains_all(invalid_text_errors, ["community_house", "pustą wartość description"]), "Every required building needs a nonempty description.")

	var duplicate_text := _building_definition_copies()
	duplicate_text["kitchen"].display_name = "  %s  " % str(duplicate_text["fishing_hut"].display_name).to_upper()
	duplicate_text["kitchen"].description = "  %s  " % str(duplicate_text["fishing_hut"].description)
	var duplicate_text_errors: Array[String] = database.required_building_validation_errors(duplicate_text)
	_assert(_validation_error_contains_all(duplicate_text_errors, ["fishing_hut", "kitchen", "display_name"]), "Required building display names should remain unique after trimming and case normalization.")
	_assert(_validation_error_contains_all(duplicate_text_errors, ["fishing_hut", "kitchen", "description"]), "Required building descriptions should remain unique after trimming and case normalization.")

	var incomplete_levels := _building_definition_copies()
	var incomplete_workshop = incomplete_levels["workshop"]
	incomplete_workshop.max_level = 3
	incomplete_workshop.levels.remove_at(3)
	var first_workshop_level = incomplete_workshop.get_level_definition(1)
	first_workshop_level.display_name = " "
	first_workshop_level.worker_slots = 0
	var incomplete_level_errors: Array[String] = database.required_building_validation_errors(incomplete_levels)
	_assert(_validation_error_contains_all(incomplete_level_errors, ["workshop", "max_level", "4"]), "A required building should expose exactly four levels through max_level.")
	_assert(_validation_error_contains_all(incomplete_level_errors, ["workshop", "dokładnie cztery"]), "A required building should contain exactly four level resources.")
	_assert(_validation_error_contains_all(incomplete_level_errors, ["workshop", "poziomu 4"]), "A required building should contain every numbered level from 1 through 4.")
	_assert(_validation_error_contains_all(incomplete_level_errors, ["workshop", "poziom 1", "pustą nazwę"]), "Every building level needs a nonempty display name.")
	_assert(_validation_error_contains_all(incomplete_level_errors, ["workshop", "poziom 1", "dodatnią liczbę stanowisk"]), "Every building level needs at least one worker slot.")

	var duplicate_level_number := _building_definition_copies()
	duplicate_level_number["infirmary"].get_level_definition(4).level = 3
	var duplicate_level_errors: Array[String] = database.required_building_validation_errors(duplicate_level_number)
	_assert(_validation_error_contains_all(duplicate_level_errors, ["infirmary", "powieloną definicję poziomu 3"]), "Duplicate level numbers should be rejected.")
	_assert(_validation_error_contains_all(duplicate_level_errors, ["infirmary", "poziomu 4"]), "A duplicated level number should also expose the resulting missing level.")

	var invalid_level_type := _building_definition_copies()
	invalid_level_type["community_house"].levels[1] = Resource.new()
	_assert(
		_validation_error_contains_all(database.required_building_validation_errors(invalid_level_type), ["community_house", "poziom o niewłaściwym typie"]),
		"All four entries should be BuildingLevelDefinition resources."
	)

	for fixture in REQUIRED_CAPABILITY_FIXTURES:
		var building_id := str(fixture.get("building_id", ""))
		var capability_id := str(fixture.get("capability_id", ""))
		var from_level := int(fixture.get("from_level", 1))
		var levels_to_check := [from_level]
		if from_level < 4:
			levels_to_check.append(4)
		for level in levels_to_check:
			var missing_capability := _building_definition_copies()
			missing_capability[building_id].get_level_definition(level).capabilities.erase(capability_id)
			var missing_capability_errors: Array[String] = database.required_building_validation_errors(missing_capability)
			_assert(
				_validation_error_contains_all(missing_capability_errors, [building_id, "poziom %d" % level, capability_id]),
				"GameDatabase should require %s for %s from level %d through level 4." % [capability_id, building_id, from_level]
			)

	for fixture in INVALID_CAPABILITY_VALUE_FIXTURES:
		var building_id := str(fixture.get("building_id", ""))
		var level := int(fixture.get("level", 1))
		var capability_id := str(fixture.get("capability_id", ""))
		var invalid_capability := _building_definition_copies()
		invalid_capability[building_id].get_level_definition(level).capabilities[capability_id] = fixture.get("value")
		var invalid_capability_errors: Array[String] = database.required_building_validation_errors(invalid_capability)
		_assert(
			_validation_error_contains_all(invalid_capability_errors, [building_id, "poziom %d" % level, capability_id, "niepoprawną wartość"]),
			"GameDatabase should reject the wrong type or logical range for %s/%s." % [building_id, capability_id]
		)

	for fixture in REQUIRED_SPECIALIST_BONUS_FIXTURES:
		var building_id := str(fixture.get("building_id", ""))
		var bonus_id := str(fixture.get("bonus_id", ""))
		var missing_bonus := _building_definition_copies()
		missing_bonus[building_id].specialist_bonus.erase(bonus_id)
		_assert(
			_validation_error_contains_all(database.required_building_validation_errors(missing_bonus), [building_id, "premia specjalisty", bonus_id]),
			"GameDatabase should require specialist bonus %s for %s." % [bonus_id, building_id]
		)
		var nonpositive_bonus := _building_definition_copies()
		nonpositive_bonus[building_id].specialist_bonus[bonus_id] = 0
		_assert(
			_validation_error_contains_all(database.required_building_validation_errors(nonpositive_bonus), [building_id, "premia specjalisty", bonus_id, "niepoprawną wartość"]),
			"Specialist bonus %s for %s should be a positive finite number." % [bonus_id, building_id]
		)

	var wrong_bonus_type := _building_definition_copies()
	wrong_bonus_type["workshop"].specialist_bonus["repair_bonus"] = "1"
	_assert(
		_validation_error_contains_all(database.required_building_validation_errors(wrong_bonus_type), ["workshop", "repair_bonus", "niepoprawną wartość"]),
		"A positive-looking specialist bonus still needs a numeric value."
	)
	var neutral_oxygen_multiplier := _building_definition_copies()
	neutral_oxygen_multiplier["diving_station"].specialist_bonus["oxygen_capacity_multiplier"] = 1.0
	_assert(
		_validation_error_contains_all(database.required_building_validation_errors(neutral_oxygen_multiplier), ["diving_station", "oxygen_capacity_multiplier", "niepoprawną wartość"]),
		"The diver oxygen-capacity multiplier should be greater than one so it remains an actual bonus."
	)

	var missing_profession := _building_definition_copies()
	missing_profession["diving_station"].specialist_bonus["profession"] = " "
	_assert(
		_validation_error_contains_all(database.required_building_validation_errors(missing_profession), ["diving_station", "niepustego zawodu"]),
		"Every required building should identify the profession that activates its specialist bonus."
	)
	var final_canonical_errors: Array[String] = database.required_building_validation_errors(_building_definition_copies())
	_assert(final_canonical_errors.is_empty(), "Mutation fixtures must leave the canonical building resources unchanged: %s" % str(final_canonical_errors))
	database.free()


func _building_definition_copies() -> Dictionary:
	var result: Dictionary = {}
	for building_id in BUILDING_DEFINITIONS.keys():
		result[building_id] = BUILDING_DEFINITIONS[building_id].duplicate(true)
	return result


func _validation_error_contains_all(errors: Array[String], fragments: Array) -> bool:
	for error in errors:
		var contains_all := true
		for fragment in fragments:
			if not str(error).contains(str(fragment)):
				contains_all = false
				break
		if contains_all:
			return true
	return false


func _test_shared_building_work_projection_contracts() -> void:
	var state = _new_state()
	var work_system = BuildingWorkSystemScript.new()
	var fishing_definition = BUILDING_DEFINITIONS.get("fishing_hut")
	var frozen_workforce: Dictionary = work_system.workforce_from_capable_ids(
		state,
		fishing_definition,
		["mira", "anka"],
		"production_bonus",
		{"mira": 0.5}
	)
	_assert(
		int(frozen_workforce.get("worker_count", 0)) == 2
		and is_equal_approx(float(frozen_workforce.get("worker_units", -1.0)), 0.5)
		and bool(frozen_workforce.get("uses_frozen_efficiency", false)),
		"A supplied workforce snapshot must never fall back to mutable efficiency when one accepted worker ID is absent from the frozen map."
	)
	var mira = state.find_survivor("mira")
	var anka = state.find_survivor("anka")
	mira.profession_talent_ids = {"rybak": TALENT_FISHING_STEWARD}
	anka.secondary_profession = "rybak"
	anka.profession_talent_ids = {"rybak": TALENT_FISHING_STEWARD}
	var deduplicated_talent_workforce: Dictionary = work_system.workforce_from_capable_ids(
		state,
		fishing_definition,
		["mira", "anka"],
		"production_bonus"
	)
	_assert(
		deduplicated_talent_workforce.get("talent_ids", []) == [TALENT_FISHING_STEWARD],
		"The workforce snapshot must carry each talent ID at most once even when several capable workers share it."
	)
	mira.profession_talent_ids.clear()
	anka.profession_talent_ids.clear()
	anka.secondary_profession = ""

	var fishing_projection: Dictionary = work_system.project_fishing(
		fishing_definition.get_level_definition(4).capabilities,
		work_system.workforce_from_capable_ids(state, fishing_definition, ["mira"], "production_bonus"),
		WorkPaceSystemScript.WORK_PACE_NORMAL,
		100,
		0.18
	)
	_assert(
		bool(fishing_projection.get("worked", false))
		and int(fishing_projection.get("food_produced", -1)) == 6
		and is_equal_approx(float(fishing_projection.get("fishing_pressure_after_recovery", -1.0)), 0.08)
		and is_equal_approx(float(fishing_projection.get("fishing_pressure_after_catch", -1.0)), 0.116),
		"The shared fishing projection must own both catch and the full pressure trajectory."
	)
	var fishing_talent_workforce := work_system.workforce_from_capable_ids(
		state,
		fishing_definition,
		["mira"],
		"production_bonus"
	)
	var steward_workforce := fishing_talent_workforce.duplicate(true)
	steward_workforce.talent_ids = [TALENT_FISHING_STEWARD]
	var steward_projection: Dictionary = work_system.project_fishing(
		fishing_definition.get_level_definition(4).capabilities,
		steward_workforce,
		WorkPaceSystemScript.WORK_PACE_NORMAL,
		100,
		0.18
	)
	_assert(
		int(steward_projection.get("food_produced", -1)) == 6
		and is_equal_approx(float(steward_projection.get("fishing_pressure_multiplier", -1.0)), 0.70)
		and is_equal_approx(float(steward_projection.get("fishing_pressure_after_catch", -1.0)), 0.1052),
		"Strażnik łowiska must preserve the ordinary catch and multiply only its fishing-pressure increase by 0.70."
	)
	var forced_workforce := fishing_talent_workforce.duplicate(true)
	forced_workforce.talent_ids = [TALENT_FORCED_FISHING]
	var forced_projection: Dictionary = work_system.project_fishing(
		fishing_definition.get_level_definition(4).capabilities,
		forced_workforce,
		WorkPaceSystemScript.WORK_PACE_NORMAL,
		100,
		0.18
	)
	_assert(
		int(forced_projection.get("food_produced", -1)) == 7
		and int(forced_projection.get("forced_fishing_food_bonus", 0)) == 1
		and is_equal_approx(float(forced_projection.get("fishing_pressure_multiplier", -1.0)), 1.50)
		and is_equal_approx(float(forced_projection.get("fishing_pressure_after_catch", -1.0)), 0.143),
		"Połów forsowny must add one food after ordinary output and multiply the complete catch pressure by 1.50."
	)
	var mixed_talent_workforce := fishing_talent_workforce.duplicate(true)
	mixed_talent_workforce.talent_ids = [TALENT_FISHING_STEWARD, TALENT_FORCED_FISHING]
	var mixed_talent_projection: Dictionary = work_system.project_fishing(
		fishing_definition.get_level_definition(4).capabilities,
		mixed_talent_workforce,
		WorkPaceSystemScript.WORK_PACE_NORMAL,
		100,
		0.18
	)
	_assert(
		int(mixed_talent_projection.get("food_produced", -1)) == 7
		and is_equal_approx(float(mixed_talent_projection.get("fishing_pressure_multiplier", -1.0)), 1.05)
		and is_equal_approx(float(mixed_talent_projection.get("fishing_pressure_after_catch", -1.0)), 0.1241),
		"Mixed fishing talents must compose once as 0.70 × 1.50 = 1.05, never stack per worker."
	)

	var workshop_definition = BUILDING_DEFINITIONS.get("workshop")
	var workshop_workforce: Dictionary = work_system.workforce_from_capable_ids(state, workshop_definition, ["anka"], "repair_bonus")
	var repair_projection: Dictionary = work_system.project_platform_repair(
		workshop_definition.get_level_definition(4).capabilities,
		workshop_workforce,
		WorkPaceSystemScript.WORK_PACE_INTENSE,
		98,
		10,
		1.0,
		0.0
	)
	_assert(
		bool(repair_projection.get("worked", false))
		and int(repair_projection.get("repair_potential", 0)) > int(repair_projection.get("repair_applied", 0))
		and int(repair_projection.get("repair_applied", -1)) == 2
		and int(repair_projection.get("integrity_after", -1)) == 100,
		"The shared repair projection must distinguish raw potential from the actual change capped at 100 integrity."
	)
	var maintainer_workforce := workshop_workforce.duplicate(true)
	maintainer_workforce.talent_ids = [TALENT_MAINTAINER]
	var canonical_repair: Dictionary = work_system.project_platform_repair(
		workshop_definition.get_level_definition(1).capabilities,
		workshop_workforce,
		WorkPaceSystemScript.WORK_PACE_NORMAL,
		70,
		10,
		1.0,
		0.0
	)
	var maintained_repair: Dictionary = work_system.project_platform_repair(
		workshop_definition.get_level_definition(1).capabilities,
		maintainer_workforce,
		WorkPaceSystemScript.WORK_PACE_NORMAL,
		70,
		10,
		1.0,
		0.0
	)
	_assert(
		int(maintained_repair.get("repair_potential", -1)) == int(canonical_repair.get("repair_potential", -1)) + 2
		and int(maintained_repair.get("maintainer_repair_bonus", 0)) == 2
		and int(maintained_repair.get("scrap_cost", -1)) == int(canonical_repair.get("scrap_cost", -2)),
		"Konserwator must add two repair potential only after positive canonical output and never change scrap cost."
	)
	var blocked_repair: Dictionary = work_system.project_platform_repair(
		workshop_definition.get_level_definition(1).capabilities,
		workshop_workforce,
		WorkPaceSystemScript.WORK_PACE_NORMAL,
		70,
		0,
		1.0,
		0.25
	)
	_assert(
		not bool(blocked_repair.get("worked", true))
		and str(blocked_repair.get("blocker_code", "")) == BuildingWorkSystemScript.BLOCKER_INSUFFICIENT_SCRAP
		and is_equal_approx(float(blocked_repair.get("rounding_carry_after", 0.0)), 0.25),
		"A blocked repair must preserve error-diffusion carry and report no work."
	)

	var patient = state.find_survivor("mira")
	patient.health = patient.get_max_health()
	patient.fatigue = 40
	patient.status = SurvivorStateScript.Status.INJURED
	patient.injury_states.assign(["emergency_extraction"])
	var infirmary_definition = BUILDING_DEFINITIONS.get("infirmary")
	var medical_system = MedicalCareSystemScript.new()
	var medical_workforce: Dictionary = work_system.workforce_from_capable_ids(state, infirmary_definition, ["anka"], "healing_bonus")
	medical_workforce.talent_ids = [TALENT_REHABILITATOR]
	var medical_projection: Dictionary = medical_system.project(
		infirmary_definition.get_level_definition(4).capabilities,
		medical_workforce,
		WorkPaceSystemScript.WORK_PACE_NORMAL,
		1.0,
		1,
		state.survivors
	)
	var medical_patients: Array = medical_projection.get("patients", [])
	_assert(
		bool(medical_projection.get("worked", false))
		and int(medical_projection.get("medicine_spent", 0)) == 1
		and int(medical_projection.get("total_health_gain", -1)) == 0
		and medical_patients.size() == 1
		and int(medical_projection.get("total_fatigue_reduction", -1)) == 4
		and int(medical_patients[0].get("fatigue_before", -1)) == 40
		and int(medical_patients[0].get("fatigue_after", -1)) == 36
		and medical_patients[0].get("injury_states_after", []).is_empty()
		and int(medical_patients[0].get("status_after", -1)) == SurvivorStateScript.Status.AVAILABLE,
		"Treating a full-health injury must remain real medical work even when the numeric health gain is zero."
	)
	var medicine_before_stale: int = state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS)
	patient.fatigue = 41
	var stale_medical_apply: Dictionary = medical_system.apply(state, medical_projection)
	_assert(
		not bool(stale_medical_apply.get("applied", true))
		and str(stale_medical_apply.get("blocker_code", "")) == MedicalCareSystemScript.BLOCKER_STALE_PROJECTION
		and state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS) == medicine_before_stale
		and patient.injury_states == ["emergency_extraction"],
		"A changed fatigue snapshot must reject rehabilitative care atomically before medicine, injury or fatigue mutation."
	)
	var current_medical_projection: Dictionary = medical_system.project(
		infirmary_definition.get_level_definition(4).capabilities,
		medical_workforce,
		WorkPaceSystemScript.WORK_PACE_NORMAL,
		1.0,
		1,
		state.survivors
	)
	var medical_apply: Dictionary = medical_system.apply(state, current_medical_projection)
	_assert(
		bool(medical_apply.get("applied", false))
		and patient.fatigue == 37
		and state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS) == medicine_before_stale - 1,
		"Rehabilitant care must atomically commit exactly four fatigue recovery with the unchanged medical cost."
	)

	var community_definition = BUILDING_DEFINITIONS.get("community_house")
	var community_projection: Dictionary = work_system.project_community_work(
		community_definition.get_level_definition(1).capabilities,
		work_system.workforce_from_capable_ids(state, community_definition, ["anka"], "hope_bonus"),
		WorkPaceSystemScript.WORK_PACE_CAREFUL
	)
	_assert(
		bool(community_projection.get("worked", false))
		and int(community_projection.get("hope_gain", -1)) == 0
		and str(community_projection.get("status_code", "")) == BuildingWorkSystemScript.STATUS_ZERO_OUTPUT,
		"Careful Community House I must remain real work when its direct Hope contribution is zero."
	)


func _test_fishing_horizon_balance() -> void:
	var state = _new_state()
	var work_system = BuildingWorkSystemScript.new()
	var definition = BUILDING_DEFINITIONS.get("fishing_hut")
	var scenarios := [
		{"level": 1, "worker_ids": ["mira"], "minimum": 5, "maximum": 6},
		{"level": 2, "worker_ids": ["mira", "anka"], "minimum": 8, "maximum": 10},
		{"level": 3, "worker_ids": ["mira", "anka"], "minimum": 11, "maximum": 13},
		{"level": 4, "worker_ids": ["mira", "anka", "igor"], "minimum": 15, "maximum": 18},
	]
	for scenario in scenarios:
		var level := int(scenario.get("level", 0))
		var workforce: Dictionary = work_system.workforce_from_capable_ids(
			state,
			definition,
			scenario.get("worker_ids", []),
			"production_bonus"
		)
		var pressure := 0.0
		var settled_outputs: Array[int] = []
		for day_index in range(15):
			var projection: Dictionary = work_system.project_fishing(
				definition.get_level_definition(level).capabilities,
				workforce,
				WorkPaceSystemScript.WORK_PACE_NORMAL,
				100,
				pressure
			)
			pressure = float(projection.get("fishing_pressure_after_catch", pressure))
			if day_index >= 10:
				settled_outputs.append(int(projection.get("food_produced", -1)))
		var minimum := int(scenario.get("minimum", 0))
		var maximum := int(scenario.get("maximum", 0))
		for output in settled_outputs:
			_assert(
				output >= minimum and output <= maximum,
				"Fishing Hut level %d should settle inside its long-horizon balance range %d-%d, got %d in the final five days." % [level, minimum, maximum, output]
			)


func _test_complete_upgrade_data_and_lifecycle() -> void:
	var state = _new_state()
	var building_system = BuildingSystemScript.new()
	for definition_id in BUILDING_SLOTS.keys():
		var definition = BUILDING_DEFINITIONS.get(definition_id)
		_assert(definition != null, "Missing definition: %s" % definition_id)
		_assert(definition.levels.size() == 4, "%s should define four levels." % definition_id)
		for level in range(1, 5):
			var level_definition = definition.get_level_definition(level)
			_assert(level_definition != null, "%s is missing level %d." % [definition_id, level])
			if level > 1:
				_assert(not level_definition.upgrade_cost.is_empty(), "%s level %d needs an upgrade cost." % [definition_id, level])
		_assert(building_system.queue_construction(state, BUILDING_SLOTS[definition_id], definition), "Could not queue %s." % definition_id)

	for building in state.buildings:
		_assert(building.is_built and building.level == 1 and building.pending_level == 0, "%s should activate level one immediately." % building.definition_id)

	for target_level in range(2, 5):
		for building in state.buildings:
			var definition = BUILDING_DEFINITIONS.get(building.definition_id)
			_assert(building_system.queue_upgrade(state, building, definition), "Could not queue %s level %d." % [building.definition_id, target_level])
		for building in state.buildings:
			_assert(building.level == target_level and building.pending_level == 0, "%s should reach level %d immediately." % [building.definition_id, target_level])

func _test_effect_descriptions_for_every_building_level() -> void:
	var state = _new_state()
	var effect_system = BuildingEffectSystemScript.new()
	for definition_id in BUILDING_DEFINITIONS.keys():
		var definition = BUILDING_DEFINITIONS.get(definition_id)
		for level in range(1, 5):
			var effect_lines: Array[String] = effect_system.level_effect_lines(state, definition, level)
			_assert(not effect_lines.is_empty(), "%s level %d should expose player-facing effects." % [definition_id, level])
			var effect_text := "\n".join(effect_lines)
			_assert(not effect_text.contains("nie został jeszcze"), "%s level %d should not use a placeholder description." % [definition_id, level])
			_assert(not effect_text.contains("Projekt Świt"), "%s level %d should not expose the retired Project Dawn copy." % [definition_id, level])
			var token_key := "%s:%d" % [definition_id, level]
			for expected_token in LEVEL_EFFECT_TOKENS.get(token_key, []):
				_assert(effect_text.contains(str(expected_token)), "%s level %d should describe the concrete value '%s'. Actual text: %s" % [definition_id, level, expected_token, effect_text])
			if definition_id == "workshop":
				_assert(effect_text.contains("złom jest pobierany raz za skuteczną naprawę"), "Workshop copy must describe one scrap charge per successful daily repair instead of a cost per fractional work unit.")
				_assert(effect_text.contains("100 punktów kończy sprzęt"), "Workshop copy must explain the durable 100-work-point completion unit.")
			if definition_id == "community_house" and level >= 3:
				_assert(effect_text.contains("stabilną łączność") and effect_text.contains("Wspólnej Linii"), "Community House III-IV copy must explain the active Radio Station requirement instead of presenting it as an empty level name.")

			var preview_building = BuildingStateScript.new()
			preview_building.id = "preview_%s_%d" % [definition_id, level]
			preview_building.definition_id = definition_id
			preview_building.level = level
			preview_building.is_built = true
			var preview: Dictionary = effect_system.staffing_preview(state, definition, preview_building)
			var preview_lines: Array = preview.get("lines", [])
			_assert(not preview_lines.is_empty(), "%s level %d should explain the current empty staffing effect." % [definition_id, level])

			var upgrade_lines: Array[String] = effect_system.next_level_change_lines(state, definition, level)
			_assert(not "\n".join(upgrade_lines).contains("Projekt Świt"), "%s level %d upgrade copy should not expose the retired Project Dawn name." % [definition_id, level])
			if level < 4:
				_assert(not upgrade_lines.is_empty(), "%s level %d should explain what its next upgrade changes." % [definition_id, level])
				var upgrade_boundary_token := str(NEXT_LEVEL_NAME_BOUNDARY_TOKENS.get(token_key, ""))
				if not upgrade_boundary_token.is_empty():
					_assert("\n".join(upgrade_lines).contains(upgrade_boundary_token), "%s level %d upgrade copy should bound the implied mechanic in the next level name '%s'." % [definition_id, level, upgrade_boundary_token])
			else:
				_assert(upgrade_lines.is_empty(), "%s level four should not advertise a nonexistent upgrade." % definition_id)

func _test_shared_panel_renders_descriptions_for_every_building() -> void:
	var building_panel_script = load("res://base_workbench/ui/BuildingPanel.gd")
	_assert(building_panel_script != null, "The shared BuildingPanel script should load for the all-building UI regression.")
	if building_panel_script == null:
		return
	var building_system = BuildingSystemScript.new()
	var production_system = ProductionSystemScript.new()
	var game_database = get_root().get_node_or_null("GameDatabase")
	var owns_test_database := false
	if game_database == null:
		game_database = GameDatabaseScript.new()
		game_database.name = "GameDatabase"
		get_root().add_child(game_database)
		owns_test_database = true
	if game_database.workshop_recipes.is_empty():
		game_database.load_definitions()
	for definition_id in BUILDING_DEFINITIONS.keys():
		var state = _new_state()
		var definition = BUILDING_DEFINITIONS.get(definition_id)
		var slot_id: String = str(BUILDING_SLOTS.get(definition_id, ""))

		var construction_panel = building_panel_script.new()
		get_root().add_child(construction_panel)
		construction_panel.configure(state, slot_id, definition, null, building_system, production_system, state.tutorial.step)
		_assert_panel_purpose(construction_panel, definition, "%s purpose before construction" % definition_id)
		_assert_unique_panel_label_visibility(construction_panel, "BuildingPurposeLabel", true, "%s purpose before construction" % definition_id)
		_assert_nonempty_panel_label(construction_panel, "ConstructionBenefitsLabel", "%s construction benefits" % definition_id)
		construction_panel.free()

		_assert(building_system.queue_construction(state, slot_id, definition), "%s should build immediately for panel coverage." % definition_id)
		var building = state.find_building_by_definition(definition_id)
		if definition_id == "workshop":
			state.tutorial.complete()

		var active_panel = building_panel_script.new()
		get_root().add_child(active_panel)
		if definition_id == "diving_station":
			_assert(state.current_day_plan.set_selected_diver("igor"), "The Diving Station panel fixture needs a directly selected free diver.")
		active_panel.configure(state, slot_id, definition, building, building_system, production_system, state.tutorial.step)
		_assert_panel_purpose(active_panel, definition, "%s active purpose" % definition_id)
		_assert_nonempty_panel_label(active_panel, "CurrentLevelBenefitsLabel", "%s current-level benefits" % definition_id)
		_assert_nonempty_panel_label(active_panel, "StaffContributionLabel", "%s current staffing effect" % definition_id)
		_assert_nonempty_panel_label(active_panel, "WorkerEffectLabel", "%s first worker contribution" % definition_id)
		_assert_unique_panel_label_visibility(active_panel, "BuildingPurposeLabel", true, "%s active purpose" % definition_id)
		_assert_unique_panel_label_visibility(active_panel, "StaffContributionLabel", true, "%s current staffing effect" % definition_id)
		_assert_unique_panel_label_visibility(active_panel, "CurrentLevelBenefitsLabel", false, "%s collapsed full-level effect" % definition_id)
		var action_scroll := active_panel.find_child("PanelScroll", true, false) as ScrollContainer
		var staffing_sidebar := active_panel.find_child("BuildingStaffingSidePanel", true, false) as Control
		var construction_sidebar := active_panel.find_child("BuildingConstructionSidePanel", true, false) as Control
		_assert(action_scroll != null and staffing_sidebar != null and construction_sidebar != null, "%s active panel should expose one dominant action area and the two right-side operations panels." % definition_id)
		_assert(active_panel.find_child("BuildingTabs", true, false) == null, "%s must not duplicate staffing and upgrade as tabs once they are permanently visible on the right." % definition_id)
		if definition_id == "diving_station":
			var station_footer := active_panel.find_child("DiveActionFooter", true, false) as Control
			var dive_button := active_panel.find_child("DiveButton", true, false) as Button
			var profile_details := active_panel.find_child("DiverProfileDetails", true, false) as Control
			var equipment_details := active_panel.find_child("DiverEquipmentDetails", true, false) as Control
			_assert(station_footer != null and dive_button != null, "The Diving Station must keep its NURKUJ action in a dedicated visible footer.")
			_assert(action_scroll != null and dive_button != null and not action_scroll.is_ancestor_of(dive_button), "The Diving Station NURKUJ action must not be pushed below the main content scroll.")
			_assert(profile_details != null and not profile_details.visible and equipment_details != null and not equipment_details.visible, "The Diving Station must keep long secondary profile and equipment details collapsed by default.")
		if definition_id == "workshop":
			var recipe_grid := active_panel.find_child("WorkshopRecipeGrid", true, false) as GridContainer
			var lantern_tile := active_panel.find_child("RecipeTile_diving_lantern_mk2", true, false) as Button
			var tank_tile := active_panel.find_child("RecipeTile_oxygen_tank_mk2", true, false) as Button
			_assert(recipe_grid != null and recipe_grid.get_child_count() >= 4, "The Workshop should render the complete unlocked equipment catalog from recipe definitions, not only the first level-valid action.")
			_assert(lantern_tile != null and tank_tile != null, "The Workshop catalog should expose separate selectable Lantern and Oxygen Tank tiles.")
			active_panel.call("_on_workshop_recipe_selected", "oxygen_tank_mk2", "RecipeTile_oxygen_tank_mk2")
			var selected_tank_action := active_panel.find_child("Craft_oxygen_tank_mk2", true, false) as Button
			var tank_recipe = game_database.workshop_recipes.get("oxygen_tank_mk2") if game_database != null else null
			var expected_tank_blocker := production_system.queue_recipe_blocker(state, building, tank_recipe)
			_assert(selected_tank_action != null and selected_tank_action.disabled and selected_tank_action.tooltip_text == expected_tank_blocker, "Selecting a higher-level recipe tile should show one canonical action with the exact ProductionSystem blocker.")
		active_panel.free()

		if definition_id == "fishing_hut":
			building.condition = 0
			var inactive_panel = building_panel_script.new()
			get_root().add_child(inactive_panel)
			inactive_panel.configure(state, slot_id, definition, building, building_system, production_system, state.tutorial.step)
			var inactive_copy := _panel_label_text(inactive_panel)
			_assert(inactive_copy.contains("NIEAKTYWNY"), "A defensively inactive building record should remain visibly blocked.")
			_assert(not inactive_copy.contains("Stan techniczny") and not inactive_copy.contains("Stan 0%") and not inactive_copy.contains("USZKODZONY"), "BuildingPanel should not present per-building technical condition as an active player-facing mechanic.")
			inactive_panel.free()
			building.condition = 100
	if owns_test_database:
		game_database.free()

func _assert_nonempty_panel_label(panel: Node, label_name: String, context: String) -> void:
	var label := panel.find_child(label_name, true, false) as Label
	_assert(label != null and not label.text.strip_edges().is_empty(), "The shared BuildingPanel should render a nonempty %s label named %s." % [context, label_name])


func _assert_panel_purpose(panel: Node, definition, context: String) -> void:
	var label := panel.find_child("BuildingPurposeLabel", true, false) as Label
	_assert(
		label != null
		and label.text == str(definition.description)
		and label.tooltip_text == str(definition.description)
		and label.max_lines_visible >= 3,
		"The shared BuildingPanel should expose the complete authored description for %s in its fixed header and tooltip." % context
	)


func _assert_unique_panel_label_visibility(panel: Node, label_name: String, expected_visible: bool, context: String) -> void:
	var matches := panel.find_children(label_name, "Label", true, false)
	_assert(matches.size() == 1, "The shared BuildingPanel should render exactly one %s label named %s." % [context, label_name])
	if matches.size() != 1:
		return
	var label := matches[0] as Label
	_assert(label != null and _is_control_visible_within(label, panel) == expected_visible, "The shared BuildingPanel should render %s as %s by default." % [context, "visible" if expected_visible else "collapsed"])


func _is_control_visible_within(control: Control, boundary: Node) -> bool:
	var current: Node = control
	while current != null:
		if current is CanvasItem and not (current as CanvasItem).visible:
			return false
		if current == boundary:
			return true
		current = current.get_parent()
	return false


func _panel_label_text(panel: Node) -> String:
	var lines: Array[String] = []
	for node in panel.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null:
			lines.append(label.text)
	return "\n".join(lines)


func _test_contextual_work_pace_panel_copy() -> void:
	var fishing_state = _new_state()
	var fishing_hut = _add_staffed_building(fishing_state, "fishing_hut", "top_left", 1, "mira")
	fishing_hut.work_pace = WorkPaceSystemScript.WORK_PACE_INTENSE
	fishing_hut.work_tension = 2
	fishing_state.current_day_plan.sync_from_state(fishing_state)
	var fishing_copy := _work_pace_panel_copy(fishing_state, "fishing_hut", fishing_hut)
	_assert(fishing_copy.contains("Połów ×1,25"), "The Fishing Hut pace hint should name the locally scaled catch instead of a generic settlement effect.")
	_assert(
		fishing_copy.contains("Tylko przy realnej pracy")
		and fishing_copy.contains("+14 zmęczenia")
		and fishing_copy.contains("Napięcie +1 (bieżąco 2→3)"),
		"The intense hint should condition its fatigue and tension increase on confirmed real work."
	)
	_assert(
		fishing_copy.contains("Bez realnej pracy: odpoczynek −12")
		and fishing_copy.contains("Napięcie −2 (bieżąco 2→0)")
		and fishing_copy.contains("niezależnie od ustawienia"),
		"Every local pace hint should disclose the shared no-work recovery and tension rule."
	)

	var house_state = _new_state()
	var house = _add_staffed_building(house_state, "community_house", "top_right", 1, "anka")
	house.work_pace = WorkPaceSystemScript.WORK_PACE_INTENSE
	house.work_tension = 1
	house_state.current_day_plan.sync_from_state(house_state)
	var house_copy := _work_pace_panel_copy(house_state, "community_house", house)
	_assert(
		house_copy.contains("koryguje poziomowy wkład każdego pracownika o +1 na osobę")
		and house_copy.contains("−1/0/+1")
		and house_copy.contains("to nie jest mnożnik")
		and not house_copy.contains("×1,25"),
		"The Community House hint must expose its discrete per-worker adjustment and never promise a multiplier."
	)

	var station_state = _new_state()
	var station = _add_staffed_building(station_state, "diving_station", "bottom_right", 1, "igor")
	station.work_pace = WorkPaceSystemScript.WORK_PACE_CAREFUL
	station_state.current_day_plan.sync_from_state(station_state)
	var station_copy := _work_pace_panel_copy(station_state, "diving_station", station)
	_assert(
		station_copy.contains("Zasięg Operatora i naprawa kombinezonu ×0,75")
		and station_copy.contains("Nurek zamiast zwykłego +4")
		and station_copy.contains("round((16 + min(floor(czas wyprawy / 120), 14)) × tempo Stacji)"),
		"The Station hint should preserve the diver's duration formula while keeping ordinary support fatigue explicit."
	)

	var heavy_state = _new_state()
	var heavy_workshop = _add_staffed_building(heavy_state, "workshop", "bottom_left", 3, "anka")
	heavy_workshop.work_pace = WorkPaceSystemScript.WORK_PACE_CAREFUL
	heavy_workshop.work_tension = 2
	_add_test_heavy_object(heavy_state)
	heavy_state.underwater_world.marked_heavy_objects.append(TEST_HEAVY_OBJECT_ID)
	heavy_state.current_day_plan.sync_from_state(heavy_state)
	var heavy_copy := _work_pace_panel_copy(heavy_state, "workshop", heavy_workshop)
	_assert(
		heavy_copy.contains("ciężki odzysk")
		and heavy_copy.contains("stałej procedury Normalnej")
		and heavy_copy.contains("+8 zmęczenia")
		and heavy_copy.contains("Napięcie −1")
		and heavy_copy.contains("Wybór Ostrożne nie zmienia tego zadania")
		and not heavy_copy.contains("×0,75"),
		"Heavy recovery should expose the fixed Normal procedure instead of the Workshop's selected pace."
	)


func _work_pace_panel_copy(state, definition_id: String, building) -> String:
	var building_panel_script = load("res://base_workbench/ui/BuildingPanel.gd")
	if building_panel_script == null:
		_assert(false, "BuildingPanel must load before its work-pace copy can be inspected.")
		return ""
	var panel = building_panel_script.new()
	get_root().add_child(panel)
	panel.configure(
		state,
		str(BUILDING_SLOTS.get(definition_id, "")),
		BUILDING_DEFINITIONS.get(definition_id),
		building,
		BuildingSystemScript.new(),
		ProductionSystemScript.new(),
		state.tutorial.step
	)
	var label := panel.find_child("BuildingWorkPaceHint", true, false) as Label
	var result := label.text if label != null else ""
	_assert(label != null and not result.is_empty(), "BuildingPanel should expose a named, nonempty contextual work-pace hint for %s." % definition_id)
	panel.free()
	return result


func _test_staffing_forecast_matches_day_resolution() -> void:
	var state = _new_state()
	var building = _add_staffed_building(state, "fishing_hut", "top_left", 4, "mira")
	state.platform.fishing_pressure = 0.18
	var definition = BUILDING_DEFINITIONS.get("fishing_hut")
	var effect_system = BuildingEffectSystemScript.new()
	var preview: Dictionary = effect_system.staffing_preview(state, definition, building)
	var preview_text := "\n".join(preview.get("lines", []))
	_assert(str(preview.get("mode", "")) == "fishing", "A staffed Fishing Hut should expose the fishing forecast mode.")
	_assert(int(preview.get("amount", -1)) == 6, "Fishing Hut IV with Mira at 18% pressure should forecast six food.")
	_assert(preview_text.contains("+6 jedzenia"), "The aggregate staffing text should show the forecasted six food.")
	_assert(
		preview_text.contains("18% teraz → 8% po regeneracji → 11.6% po prognozowanym połowie"),
		"The Fishing Hut forecast should expose the exact pressure trajectory used by the resolver."
	)
	_assert(
		is_equal_approx(float(preview.get("fishing_pressure_now", -1.0)), 0.18)
		and is_equal_approx(float(preview.get("fishing_pressure_after_recovery", -1.0)), 0.08)
		and is_equal_approx(float(preview.get("fishing_pressure_after_catch", -1.0)), 0.116),
		"The Fishing Hut projection should retain exact pressure values before recovery, after recovery and after the catch."
	)
	var worker_line := effect_system.worker_contribution_line(state, definition, building, 0, state.find_survivor("mira"))
	_assert(worker_line.contains("7.0 jedzenia") and worker_line.contains("Rybak +1"), "Mira's worker card should explain her seven-food base contribution and specialist bonus.")

	var food_before: int = state.resources.get_amount(ResourceIdsScript.FOOD)
	EndOfDayResolverScript.new()._resolve_fishing(state, ReportStateScript.new())
	var settled_food: int = state.resources.get_amount(ResourceIdsScript.FOOD) - food_before
	_assert(settled_food == int(preview.get("amount", -1)), "The fishing forecast should exactly match the end-of-day food settlement.")
	_assert(is_equal_approx(float(state.platform.fishing_pressure), float(preview.get("fishing_pressure_after_catch", -1.0))), "The forecasted final fishing pressure should exactly match end-of-day settlement.")

	var idle_state = _new_state()
	var idle_hut = _add_staffed_building(idle_state, "fishing_hut", "top_left", 4, "mira")
	idle_hut.assigned_survivor_ids.clear()
	idle_state.find_survivor("mira").current_assignment = ""
	idle_state.find_survivor("mira").status = SurvivorStateScript.Status.AVAILABLE
	idle_state.platform.fishing_pressure = 0.18
	var idle_preview: Dictionary = effect_system.staffing_preview(idle_state, definition, idle_hut)
	var idle_preview_text := "\n".join(idle_preview.get("lines", []))
	_assert(idle_preview_text.contains("18% teraz → 3% po regeneracji → 3% po prognozowanym połowie"), "An unstaffed Fishing Hut should show the resolver's larger idle recovery and zero catch.")
	EndOfDayResolverScript.new()._resolve_fishing(idle_state, ReportStateScript.new())
	_assert(is_equal_approx(float(idle_state.platform.fishing_pressure), float(idle_preview.get("fishing_pressure_after_catch", -1.0))), "The idle pressure forecast should exactly match the resolver's unstaffed recovery.")

func _test_ration_allocation_contract() -> void:
	var system = RationAllocationSystemScript.new()
	var survivor_ids: Array[String] = ["mira", "anka", "igor"]
	_assert(system.full_ration_cost(3, 4, 0.0) == 12, "Three standard full rations should cost twelve food without a Kitchen.")
	_assert(system.group_half_cost(3, 12) == 6, "Group HALF should cost half of the full group cost when that exceeds the population floor.")
	_assert(system.full_ration_cost(3, 4, 0.75) == 3 and system.group_half_cost(3, 3) == 2, "At maximum Kitchen efficiency, three HALF rations must cost two food instead of the full-ration floor of three.")
	var capped := system.project(PolicyStateScript.RationPolicy.FULL, survivor_ids, 100, 4, 1.5)
	_assert(is_equal_approx(float(capped.effective_ration_efficiency), 0.75) and int(capped.cost) == 3, "The shared ration projection must clamp future Kitchen bonuses at 75% in both cost and presentation data.")
	_assert(system.mixed_allocation_cost(3, 12, 1, 1) == 6, "One full and one half ration should use the single proportional mixed-allocation formula.")

	var full := system.project(PolicyStateScript.RationPolicy.FULL, survivor_ids, 12, 4, 0.0)
	_assert(int(full.cost) == 12 and full.full_recipient_ids == survivor_ids, "FULL should atomically feed the whole living roster when affordable.")
	var full_fallback := system.project(PolicyStateScript.RationPolicy.FULL, survivor_ids, 8, 4, 0.0)
	_assert(int(full_fallback.cost) == 6 and int(full_fallback.actual_policy) == PolicyStateScript.RationPolicy.HALF and full_fallback.half_recipient_ids == survivor_ids, "FULL shortage should fall back to one group HALF allocation.")
	var full_shortage := system.project(PolicyStateScript.RationPolicy.FULL, survivor_ids, 5, 4, 0.0)
	_assert(int(full_shortage.cost) == 0 and bool(full_shortage.shortage) and full_shortage.unfed_recipient_ids == survivor_ids, "Failed FULL and HALF attempts must allocate nothing, leaving the caller's food untouched.")
	var half_shortage := system.project(PolicyStateScript.RationPolicy.HALF, survivor_ids, 5, 4, 0.0)
	_assert(int(half_shortage.cost) == 0 and bool(half_shortage.shortage), "HALF must be all-or-none without consuming a remainder.")

	# Igor is last in the stable roster. Six food can reserve his full ration and
	# then the largest affordable prefix of other HALF recipients (Mira only).
	var priority := system.project(PolicyStateScript.RationPolicy.DIVER_PRIORITY, survivor_ids, 6, 4, 0.0, "igor")
	_assert(int(priority.cost) == 6 and str(priority.ration_by_survivor_id.get("igor")) == "full", "DIVER_PRIORITY must reserve the diver's full ration before earlier roster entries.")
	_assert(priority.half_recipient_ids == ["mira"] and priority.unfed_recipient_ids == ["anka"], "DIVER_PRIORITY must extend the allocation through the largest stable prefix of other survivors.")
	var diver_half := system.project(PolicyStateScript.RationPolicy.DIVER_PRIORITY, survivor_ids, 3, 4, 0.0, "igor")
	_assert(int(diver_half.cost) == 2 and str(diver_half.ration_by_survivor_id.get("igor")) == "half" and diver_half.unfed_recipient_ids == ["mira", "anka"], "When a full diver ration is unaffordable, the system must reserve a half ration for the diver before anyone else.")
	var diver_shortage := system.project(PolicyStateScript.RationPolicy.DIVER_PRIORITY, survivor_ids, 1, 4, 0.0, "igor")
	_assert(int(diver_shortage.cost) == 0 and int(diver_shortage.actual_policy) == PolicyStateScript.RationPolicy.NONE and int(diver_shortage.diver_half_cost) == 2 and bool(diver_shortage.shortage) and diver_shortage.unfed_recipient_ids == survivor_ids, "A valid diver still receives nothing when even the reserved HALF is unaffordable; actual_policy must remain NONE and the remainder must stay untouched.")
	var missing_diver := system.project(PolicyStateScript.RationPolicy.DIVER_PRIORITY, survivor_ids, 6, 4, 0.0)
	_assert(not bool(missing_diver.diver_valid) and int(missing_diver.actual_policy) == PolicyStateScript.RationPolicy.HALF and missing_diver.half_recipient_ids == survivor_ids, "DIVER_PRIORITY without a valid living diver must use the exact group HALF fallback.")
	var missing_diver_shortage := system.project(PolicyStateScript.RationPolicy.DIVER_PRIORITY, survivor_ids, 5, 4, 0.0, "dead_diver")
	_assert(int(missing_diver_shortage.cost) == 0 and bool(missing_diver_shortage.shortage), "An unaffordable no-diver fallback must preserve all food and feed nobody.")


func _test_kitchen_forecast_matches_ration_policies() -> void:
	var effect_system = BuildingEffectSystemScript.new()
	var no_kitchen_state = _new_state()
	no_kitchen_state.resources.set_amount(ResourceIdsScript.FOOD, 6)
	var no_kitchen_forecast: Dictionary = effect_system.ration_forecast(no_kitchen_state)
	var no_kitchen_text := "\n".join(no_kitchen_forecast.get("lines", []))
	_assert(str(no_kitchen_forecast.get("mode", "")) == "rations_half_fallback" and int(no_kitchen_forecast.get("amount", -1)) == 6, "The day-plan ration forecast must remain available without a Kitchen and expose the real FULL-to-HALF fallback cost.")
	_assert(no_kitchen_text.contains("Brak czynnej Kuchni") and no_kitchen_text.contains("obecny zapas") and no_kitchen_text.contains("pewny połów 0") and no_kitchen_text.contains("wyniku wyprawy"), "The building-independent forecast must disclose zero Kitchen efficiency, deterministic fishing and the remaining unknown dive result.")

	var unstaffed_state = _new_state()
	var unstaffed_kitchen = BuildingStateScript.new()
	unstaffed_kitchen.id = "test_unstaffed_kitchen"
	unstaffed_kitchen.definition_id = "kitchen"
	unstaffed_kitchen.slot_id = "top_center"
	unstaffed_kitchen.level = 1
	unstaffed_kitchen.is_built = true
	unstaffed_state.buildings.append(unstaffed_kitchen)
	unstaffed_state.resources.set_amount(ResourceIdsScript.FOOD, 6)
	var unstaffed_forecast: Dictionary = effect_system.ration_forecast(unstaffed_state)
	_assert(int(unstaffed_forecast.get("amount", -1)) == 6 and "\n".join(unstaffed_forecast.get("lines", [])).contains("nie ma zdolnej obsady"), "An unstaffed Kitchen must not hide the ration forecast or grant its efficiency.")

	var frozen_plan_state = _new_state()
	frozen_plan_state.resources.set_amount(ResourceIdsScript.FOOD, 6)
	frozen_plan_state.active_policies.ration_policy = PolicyStateScript.RationPolicy.FULL
	frozen_plan_state.current_day_plan.ration_policy = PolicyStateScript.RationPolicy.HALF
	frozen_plan_state.current_day_plan.locked = true
	var frozen_plan_forecast: Dictionary = effect_system.ration_forecast(frozen_plan_state)
	_assert(str(frozen_plan_forecast.get("mode", "")) == "rations_half" and int(frozen_plan_forecast.get("amount", -1)) == 6, "A locked DayPlan must remain the forecast source even if mutable active policies diverge.")

	var frozen_roster_state = _new_state()
	var frozen_roster_kitchen = _add_staffed_building(frozen_roster_state, "kitchen", "top_center", 1, "anka")
	frozen_roster_state.resources.set_amount(ResourceIdsScript.FOOD, 100)
	frozen_roster_state.current_day_plan.sync_from_state(frozen_roster_state)
	frozen_roster_state.current_day_plan.locked = true
	# A transient live-roster mutation must not erase the already frozen plan.
	# The bidirectional assignment is intentionally left intact for the worker.
	frozen_roster_kitchen.assigned_survivor_ids.clear()
	var frozen_roster_forecast: Dictionary = effect_system.ration_forecast(frozen_roster_state)
	var frozen_roster_resolver = EndOfDayResolverScript.new()
	var frozen_roster_before := int(frozen_roster_state.resources.get_amount(ResourceIdsScript.FOOD))
	frozen_roster_resolver._resolve_rations(frozen_roster_state, ReportStateScript.new())
	var frozen_roster_cost := frozen_roster_before - int(frozen_roster_state.resources.get_amount(ResourceIdsScript.FOOD))
	_assert(int(frozen_roster_forecast.get("amount", -1)) == 11 and frozen_roster_cost == 11, "Forecast and resolver must both consume the locked Kitchen roster instead of the later mutable building array.")

	var fishing_threshold_state = _new_state()
	_add_staffed_building(fishing_threshold_state, "fishing_hut", "top_left", 1, "mira")
	fishing_threshold_state.resources.set_amount(ResourceIdsScript.FOOD, 5)
	var before_fishing_forecast: Dictionary = effect_system.ration_forecast(fishing_threshold_state)
	var before_fishing_text := "\n".join(before_fishing_forecast.get("lines", []))
	var sequence_resolver = EndOfDayResolverScript.new()
	sequence_resolver._resolve_fishing(fishing_threshold_state, ReportStateScript.new())
	var before_rations := int(fishing_threshold_state.resources.get_amount(ResourceIdsScript.FOOD))
	sequence_resolver._resolve_rations(fishing_threshold_state, ReportStateScript.new())
	var sequence_cost := before_rations - int(fishing_threshold_state.resources.get_amount(ResourceIdsScript.FOOD))
	_assert(int(before_fishing_forecast.get("projected_fishing_food", -1)) == 6 and int(before_fishing_forecast.get("amount", -1)) == 6 and sequence_cost == 6, "The shared forecast must include deterministic fishing and match the real fishing-to-rations threshold settlement.")
	_assert(before_fishing_text.contains("zapas 5") and before_fishing_text.contains("pewny połów 6") and before_fishing_text.contains("bez nieznanego wyniku wyprawy"), "The forecast must separate deterministic fishing from the genuinely unknown dive result.")

	var expectations := {
		PolicyStateScript.RationPolicy.FULL: "rations_full",
		PolicyStateScript.RationPolicy.HALF: "rations_half",
		PolicyStateScript.RationPolicy.NONE: "ration_none",
		PolicyStateScript.RationPolicy.DIVER_PRIORITY: "rations_diver_priority",
	}
	for policy in expectations.keys():
		var state = _new_state()
		var kitchen = _add_staffed_building(state, "kitchen", "top_center", 1, "anka")
		state.resources.set_amount(ResourceIdsScript.FOOD, 100)
		state.active_policies.ration_policy = int(policy)
		state.current_day_plan.ration_policy = int(policy)
		if int(policy) == PolicyStateScript.RationPolicy.DIVER_PRIORITY:
			var setup = ExpeditionSetupScript.new()
			setup.diver_id = "igor"
			state.current_day_plan.expedition_setup = setup
			state.current_day_plan.selected_diver_id = "igor"
		var preview: Dictionary = BuildingEffectSystemScript.new().staffing_preview(state, BUILDING_DEFINITIONS.kitchen, kitchen)
		var food_before := int(state.resources.get_amount(ResourceIdsScript.FOOD))
		EndOfDayResolverScript.new()._resolve_rations(state, ReportStateScript.new())
		var settled_cost := food_before - int(state.resources.get_amount(ResourceIdsScript.FOOD))
		_assert(str(preview.get("mode", "")) == str(expectations[policy]), "Kitchen preview should expose the selected ration policy mode.")
		_assert(int(preview.get("amount", -1)) == settled_cost, "Kitchen forecasted food cost should exactly match ration settlement for policy %d." % int(policy))

	var no_ration_state = _new_state()
	var no_ration_kitchen = _add_staffed_building(no_ration_state, "kitchen", "top_center", 1, "anka")
	no_ration_state.active_policies.ration_policy = PolicyStateScript.RationPolicy.NONE
	no_ration_state.current_day_plan.ration_policy = PolicyStateScript.RationPolicy.NONE
	var no_ration_preview: Dictionary = BuildingEffectSystemScript.new().staffing_preview(no_ration_state, BUILDING_DEFINITIONS.kitchen, no_ration_kitchen)
	var worker_line := BuildingEffectSystemScript.new().worker_contribution_line(no_ration_state, BUILDING_DEFINITIONS.kitchen, no_ration_kitchen, 0, no_ration_state.find_survivor("anka"))
	_assert(int(no_ration_preview.get("amount", -1)) == 0 and worker_line.contains("Wkład dzisiaj: 0"), "No-ration policy must show zero Kitchen work in both aggregate and worker forecasts.")

	var insufficient_state = _new_state()
	var insufficient_kitchen = _add_staffed_building(insufficient_state, "kitchen", "top_center", 1, "anka")
	insufficient_state.resources.set_amount(ResourceIdsScript.FOOD, 5)
	var insufficient_preview: Dictionary = BuildingEffectSystemScript.new().staffing_preview(insufficient_state, BUILDING_DEFINITIONS.kitchen, insufficient_kitchen)
	var insufficient_before := int(insufficient_state.resources.get_amount(ResourceIdsScript.FOOD))
	var insufficient_report = ReportStateScript.new()
	var insufficient_resolver = EndOfDayResolverScript.new()
	insufficient_resolver._resolve_rations(insufficient_state, insufficient_report)
	var insufficient_cost := insufficient_before - int(insufficient_state.resources.get_amount(ResourceIdsScript.FOOD))
	var insufficient_worker_line := BuildingEffectSystemScript.new().worker_contribution_line(insufficient_state, BUILDING_DEFINITIONS.kitchen, insufficient_kitchen, 0, insufficient_state.find_survivor("anka"))
	_assert(str(insufficient_preview.get("mode", "")) == "ration_insufficient" and int(insufficient_preview.get("amount", -1)) == insufficient_cost, "Insufficient-food Kitchen forecast should match the resolver's fallback consumption and zero-work outcome.")
	_assert(insufficient_cost == 0 and insufficient_state.resources.get_amount(ResourceIdsScript.FOOD) == insufficient_before, "An unaffordable FULL-to-HALF fallback must preserve every unit of undistributed food.")
	_assert(insufficient_worker_line.contains("Wkład dzisiaj: 0") and insufficient_resolver._committed_work_events.is_empty(), "A Kitchen worker must show zero contribution and receive no work commit when no ration is issued.")
	_assert("\n".join(insufficient_preview.get("lines", [])).contains("zostanie zachowany"), "The Kitchen forecast must disclose that an insufficient remainder stays in storage.")
	_assert("\n".join(insufficient_report.warnings).contains("cały zapas zachowano"), "The end-of-day report must disclose that an insufficient remainder was preserved.")

	var insufficient_half_state = _new_state()
	var insufficient_half_kitchen = _add_staffed_building(insufficient_half_state, "kitchen", "top_center", 1, "anka")
	insufficient_half_state.resources.set_amount(ResourceIdsScript.FOOD, 5)
	insufficient_half_state.active_policies.ration_policy = PolicyStateScript.RationPolicy.HALF
	insufficient_half_state.current_day_plan.ration_policy = PolicyStateScript.RationPolicy.HALF
	var insufficient_half_preview: Dictionary = BuildingEffectSystemScript.new().staffing_preview(insufficient_half_state, BUILDING_DEFINITIONS.kitchen, insufficient_half_kitchen)
	EndOfDayResolverScript.new()._resolve_rations(insufficient_half_state, ReportStateScript.new())
	_assert(int(insufficient_half_preview.get("amount", -1)) == 0 and insufficient_half_state.resources.get_amount(ResourceIdsScript.FOOD) == 5, "An unaffordable explicit HALF policy must also preserve every unit of food and forecast zero consumption.")

	var no_dive_state = _new_state()
	var no_dive_kitchen = _add_staffed_building(no_dive_state, "kitchen", "top_center", 1, "anka")
	no_dive_state.resources.set_amount(ResourceIdsScript.FOOD, 6)
	no_dive_state.active_policies.ration_policy = PolicyStateScript.RationPolicy.DIVER_PRIORITY
	no_dive_state.current_day_plan.ration_policy = PolicyStateScript.RationPolicy.DIVER_PRIORITY
	no_dive_state.current_day_plan.expedition_setup = null
	var no_dive_preview: Dictionary = BuildingEffectSystemScript.new().staffing_preview(no_dive_state, BUILDING_DEFINITIONS.kitchen, no_dive_kitchen)
	var no_dive_report = ReportStateScript.new()
	EndOfDayResolverScript.new()._resolve_rations(no_dive_state, no_dive_report)
	var no_dive_text := "\n".join(no_dive_preview.get("lines", [])) + "\n" + "\n".join(no_dive_report.warnings)
	_assert(str(no_dive_preview.get("mode", "")) == "rations_half_diver_fallback" and int(no_dive_preview.get("amount", -1)) == 6, "A no-expedition DIVER_PRIORITY forecast must expose the actual group HALF fallback and its cost.")
	_assert(no_dive_state.resources.get_amount(ResourceIdsScript.FOOD) == 0 and no_dive_text.contains("Brak poprawnego żyjącego nurka") and no_dive_text.contains("Mira Boruta") and no_dive_text.contains("Anka Ryl") and no_dive_text.contains("Igor Sowa"), "The no-diver forecast and report must name the fallback and every actual HALF recipient.")

	var priority_state = _new_state()
	var priority_kitchen = _add_staffed_building(priority_state, "kitchen", "top_center", 1, "anka")
	priority_state.resources.set_amount(ResourceIdsScript.FOOD, 6)
	priority_state.active_policies.ration_policy = PolicyStateScript.RationPolicy.DIVER_PRIORITY
	priority_state.current_day_plan.ration_policy = PolicyStateScript.RationPolicy.DIVER_PRIORITY
	var priority_setup = ExpeditionSetupScript.new()
	priority_setup.diver_id = "igor"
	priority_state.current_day_plan.expedition_setup = priority_setup
	priority_state.current_day_plan.selected_diver_id = "igor"
	var priority_preview: Dictionary = BuildingEffectSystemScript.new().staffing_preview(priority_state, BUILDING_DEFINITIONS.kitchen, priority_kitchen)
	var priority_report = ReportStateScript.new()
	var priority_resolver = EndOfDayResolverScript.new()
	priority_resolver._resolve_rations(priority_state, priority_report)
	priority_resolver._resolve_hunger(priority_state, priority_report)
	var priority_text := "\n".join(priority_preview.get("lines", [])) + "\n" + "\n".join(priority_report.warnings)
	_assert(int(priority_preview.get("amount", -1)) == 6 and priority_state.resources.get_amount(ResourceIdsScript.FOOD) == 0, "The mixed DIVER_PRIORITY preview cost must exactly match the resolver's one atomic spend.")
	_assert(priority_state.find_survivor("igor").hunger == 0 and priority_state.find_survivor("mira").hunger == 10 and priority_state.find_survivor("anka").hunger == 25, "The projected mixed portions must drive the diver, stable HALF prefix, and unfed survivor through their matching hunger effects.")
	_assert(priority_text.contains("Igor Sowa") and priority_text.contains("pełn") and priority_text.contains("Mira Boruta") and priority_text.contains("połow") and priority_text.contains("Anka Ryl") and priority_text.contains("Bez racji"), "The DIVER_PRIORITY forecast and report must identify the diver's reserved ration, the stable HALF prefix, and unfed survivors.")

	var priority_shortage_state = _new_state()
	var priority_shortage_kitchen = _add_staffed_building(priority_shortage_state, "kitchen", "top_center", 1, "anka")
	priority_shortage_state.resources.set_amount(ResourceIdsScript.FOOD, 1)
	priority_shortage_state.active_policies.ration_policy = PolicyStateScript.RationPolicy.DIVER_PRIORITY
	priority_shortage_state.current_day_plan.ration_policy = PolicyStateScript.RationPolicy.DIVER_PRIORITY
	var priority_shortage_setup = ExpeditionSetupScript.new()
	priority_shortage_setup.diver_id = "igor"
	priority_shortage_state.current_day_plan.expedition_setup = priority_shortage_setup
	priority_shortage_state.current_day_plan.selected_diver_id = "igor"
	var priority_shortage_preview: Dictionary = BuildingEffectSystemScript.new().staffing_preview(priority_shortage_state, BUILDING_DEFINITIONS.kitchen, priority_shortage_kitchen)
	var priority_shortage_report = ReportStateScript.new()
	EndOfDayResolverScript.new()._resolve_rations(priority_shortage_state, priority_shortage_report)
	var priority_shortage_text := "\n".join(priority_shortage_preview.get("lines", [])) + "\n" + "\n".join(priority_shortage_report.warnings)
	_assert(str(priority_shortage_preview.get("mode", "")) == "ration_insufficient" and int(priority_shortage_preview.get("amount", -1)) == 0 and priority_shortage_state.resources.get_amount(ResourceIdsScript.FOOD) == 1, "An unaffordable reserved HALF must forecast zero consumption and preserve the diver-priority remainder.")
	_assert(priority_shortage_text.contains("nie wystarcza nawet na pół racji") and priority_shortage_text.contains("cały zapas") and priority_shortage_text.contains("Igor Sowa"), "The valid-diver shortage forecast and report must explain the failed reservation and preserved stock.")

func _test_station_diver_capability_uses_expedition_requirements() -> void:
	var state = _new_state()
	var station = _add_staffed_building(state, "diving_station", "bottom_right", 1, "igor")
	var station_service = state.find_survivor("igor")
	station_service.status = SurvivorStateScript.Status.RESTING
	_assert(station_service.can_work() and not station_service.can_dive(), "The regression fixture should remain generally work-capable but fail the stricter expedition requirements.")
	_assert(state.current_day_plan.set_selected_diver("mira"), "A free capable resident must be selectable independently of Station service.")

	var definition = BUILDING_DEFINITIONS.get("diving_station")
	var effect_system = BuildingEffectSystemScript.new()
	var preview: Dictionary = effect_system.staffing_preview(state, definition, station)
	var preview_text := "\n".join(preview.get("lines", []))
	_assert(str(preview.get("mode", "")) == "dive_ready", "A selected free diver and a merely work-capable Station service worker must keep the expedition ready.")
	_assert(int(preview.get("capable_count", -1)) == 1, "The Station roster should count a work-capable service worker even when that person cannot dive.")
	_assert(preview_text.contains("Mira Boruta") and preview_text.contains("+5% udźwigu"), "The Station forecast should show the independently selected diver and the staffed carry bonus.")
	var worker_line := effect_system.worker_contribution_line(state, definition, station, 0, station_service)
	_assert(worker_line.contains("Obsługa Stacji") and worker_line.contains("+5%"), "The first Station worker card should present support contribution, not a diver blocker.")

func _test_infirmary_injury_forecast_matches_resolution() -> void:
	var state = _new_state()
	var infirmary = _add_staffed_building(state, "infirmary", "center", 4, "anka")
	var patient = state.find_survivor("mira")
	patient.health = patient.get_max_health()
	patient.status = SurvivorStateScript.Status.INJURED
	patient.injury_states.assign(["emergency_extraction"])

	var definition = BUILDING_DEFINITIONS.get("infirmary")
	var effect_system = BuildingEffectSystemScript.new()
	var preview: Dictionary = effect_system.staffing_preview(state, definition, infirmary)
	var preview_text := "\n".join(preview.get("lines", []))
	_assert(str(preview.get("mode", "")) == "medical_care", "An injured full-health resident should still be forecast as a patient.")
	_assert(int(preview.get("amount", -1)) == 0, "A full-health injury treatment should forecast zero health gain without hiding its injury recovery.")
	_assert(preview_text.contains("Mira") and preview_text.contains("urazy:") and preview_text.contains("brak") and preview_text.contains("odzyska status dostępny"), "The Infirmary forecast should show the exact injury removal and status recovery for the patient.")

	var medicines_before: int = state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS)
	EndOfDayResolverScript.new()._resolve_medical_care(state, ReportStateScript.new())
	_assert(state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS) == medicines_before - 1, "The predicted full-health injury treatment should consume one medicine.")
	_assert(patient.injury_states.is_empty(), "The end-of-day treatment should remove the same emergency-extraction injury shown by the forecast.")
	_assert(patient.status == SurvivorStateScript.Status.AVAILABLE, "The end-of-day treatment should restore the same available status shown by the forecast.")

func _test_zero_output_workshop_forecast_matches_resolution() -> void:
	var state = _new_state()
	var workshop = _add_staffed_building(state, "workshop", "bottom_left", 1, "mira")
	var worker = state.find_survivor("mira")
	worker.health = 35
	worker.hunger = 84
	worker.fatigue = 89
	worker.morale = 10
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 70)
	state.resources.set_amount(ResourceIdsScript.SCRAP, 10)

	var definition = BUILDING_DEFINITIONS.get("workshop")
	var preview: Dictionary = BuildingEffectSystemScript.new().staffing_preview(state, definition, workshop)
	var preview_text := "\n".join(preview.get("lines", []))
	_assert(str(preview.get("mode", "")) == "repair_no_output" and int(preview.get("amount", -1)) == 0, "A capable but extremely inefficient worker should forecast zero Workshop repair.")
	_assert(preview_text.contains("zbyt niska") and preview_text.contains("nie zostanie zużyty"), "The zero-output forecast should explicitly say that scrap will not be spent.")

	var integrity_before: int = state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY)
	var scrap_before: int = state.resources.get_amount(ResourceIdsScript.SCRAP)
	var repaired := EndOfDayResolverScript.new()._resolve_workshop_repairs(state, ReportStateScript.new())
	_assert(not repaired, "A rounded zero-point Workshop shift should not count as completed repair work.")
	_assert(state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY) == integrity_before, "A zero-output Workshop shift must not change platform integrity.")
	_assert(state.resources.get_amount(ResourceIdsScript.SCRAP) == scrap_before, "A zero-output Workshop shift must not consume scrap.")


func _test_workshop_priority_preview_skips_non_working_queue_heads() -> void:
	var production_state = _new_state()
	var production_workshop = _add_staffed_building(production_state, "workshop", "bottom_left", 3, "anka")
	production_workshop.work_pace = WorkPaceSystemScript.WORK_PACE_CAREFUL
	var positive_production = ProductionSystemScript.new()
	_assert(positive_production.queue_recipe(production_state, production_workshop, positive_production.get_recipe("diving_lantern_mk2")), "The positive preview fixture should queue a first canonical order.")
	_assert(positive_production.queue_recipe(production_state, production_workshop, positive_production.get_recipe("oxygen_tank_mk2")), "The positive preview fixture should queue a second order for partial overflow.")
	production_state.current_day_plan.sync_from_state(production_state)
	_add_test_heavy_object(production_state)
	production_state.underwater_world.marked_heavy_objects.append(TEST_HEAVY_OBJECT_ID)
	production_state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 40)
	var production_preview: Dictionary = BuildingEffectSystemScript.new().staffing_preview(
		production_state,
		BUILDING_DEFINITIONS.get("workshop"),
		production_workshop
	)
	var production_preview_text := "\n".join(production_preview.get("lines", []))
	_assert(
		str(production_preview.get("mode", "")) == "production"
		and production_preview_text.contains("50/100")
		and not production_preview_text.contains("wydobycie 1 oznaczonego")
		and not production_preview_text.contains("Prognoza przy obecnym stanie planu"),
		"Positive partial production should be forecast as the active priority and hide heavy recovery and platform repair."
	)
	_assert(
		production_workshop.queued_production_orders.size() == 2
		and production_workshop.queued_production_orders[0].work_progress == 0
		and production_workshop.queued_production_orders[1].work_progress == 0
		and production_state.underwater_world.marked_heavy_objects.has(TEST_HEAVY_OBJECT_ID)
		and production_state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY) == 40,
		"Positive Workshop preview must preserve both FIFO progress and every lower-priority target."
	)

	var blocked_state = _new_state()
	var blocked_workshop = _add_staffed_building(blocked_state, "workshop", "bottom_left", 3, "anka")
	var blocked_order = WorkshopOrderStateScript.new()
	blocked_order.setup(
		"workshop_order:%s:1" % blocked_workshop.id,
		"retired_recipe",
		"missing_gear_target",
		"Zamrożony brakujący cel",
		{ResourceIdsScript.SCRAP: 3},
		int(blocked_state.day)
	)
	blocked_workshop.queued_production_orders.append(blocked_order)
	blocked_workshop.next_production_order_sequence = 2
	_add_test_heavy_object(blocked_state)
	blocked_state.underwater_world.marked_heavy_objects.append(TEST_HEAVY_OBJECT_ID)
	var blocked_preview: Dictionary = BuildingEffectSystemScript.new().staffing_preview(
		blocked_state,
		BUILDING_DEFINITIONS.get("workshop"),
		blocked_workshop
	)
	_assert(
		str(blocked_preview.get("mode", "")) == "heavy_recovery"
		and not "\n".join(blocked_preview.get("lines", [])).contains("Dzisiejszy priorytet: produkcja"),
		"A controlled blocked FIFO head applies zero points and must not hide the lower heavy-recovery forecast."
	)
	_assert(
		blocked_workshop.queued_production_orders.size() == 1
		and blocked_workshop.queued_production_orders[0] == blocked_order
		and blocked_order.work_progress == 0,
		"Read-only Workshop analysis must preserve the blocked order, reservation and progress."
	)

	var refund_state = _new_state()
	var refund_workshop = _add_staffed_building(refund_state, "workshop", "bottom_left", 1, "anka")
	refund_state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 70)
	var production = ProductionSystemScript.new()
	var recipe = production.get_recipe("diving_lantern_mk2")
	_assert(production.queue_recipe(refund_state, refund_workshop, recipe), "The refund-head preview fixture should queue one canonical order.")
	_assert(refund_state.diving_equipment.add_gear("diving_lantern_mk2"), "The fixture should emulate recovering the queued gear before Workshop resolution.")
	refund_state.resources.set_amount(ResourceIdsScript.SCRAP, 0)
	var reserved_scrap: int = refund_state.resources.get_amount(ResourceIdsScript.SCRAP)
	var refund_preview: Dictionary = BuildingEffectSystemScript.new().staffing_preview(
		refund_state,
		BUILDING_DEFINITIONS.get("workshop"),
		refund_workshop
	)
	_assert(
		str(refund_preview.get("mode", "")) == "platform_repair"
		and "\n".join(refund_preview.get("lines", [])).contains("Prognoza przy obecnym stanie planu"),
		"A refundable owned-gear head consumes no work points, and its virtual scrap refund should expose the lower platform-repair forecast."
	)
	_assert(
		refund_workshop.queued_production_orders.size() == 1
		and refund_state.resources.get_amount(ResourceIdsScript.SCRAP) == reserved_scrap,
		"Workshop preview must analyze a future refund without mutating the live FIFO or returning materials early."
	)


func _test_local_work_pace_effects() -> void:
	# Two buildings intentionally use opposite paces in one frozen plan. This
	# catches accidental fallback to a single global policy.
	var mixed_state = _new_state()
	var fishing_hut = _add_staffed_building(mixed_state, "fishing_hut", "top_left", 1, "mira")
	var infirmary = _add_staffed_building(mixed_state, "infirmary", "center", 1, "anka")
	fishing_hut.work_pace = WorkPaceSystemScript.WORK_PACE_CAREFUL
	infirmary.work_pace = WorkPaceSystemScript.WORK_PACE_INTENSE
	mixed_state.current_day_plan.sync_from_state(mixed_state)
	var patient = mixed_state.find_survivor("igor")
	patient.health = 50
	var mixed_resolver = EndOfDayResolverScript.new()
	var food_before: int = mixed_state.resources.get_amount(ResourceIdsScript.FOOD)
	mixed_resolver._resolve_fishing(mixed_state, ReportStateScript.new())
	mixed_resolver._resolve_medical_care(mixed_state, ReportStateScript.new())
	_assert(mixed_state.resources.get_amount(ResourceIdsScript.FOOD) - food_before == 5, "Careful Fishing Hut pace should scale Mira's six-food result to five without inheriting the Infirmary pace.")
	_assert(patient.health == 65, "Intense Infirmary pace should heal fifteen health without inheriting the Fishing Hut pace.")
	_assert(
		mixed_state.current_day_plan.building_work_paces.get(fishing_hut.id) == WorkPaceSystemScript.WORK_PACE_CAREFUL
		and mixed_state.current_day_plan.building_work_paces.get(infirmary.id) == WorkPaceSystemScript.WORK_PACE_INTENSE,
		"DayPlanState should freeze independent pace values for both simultaneously active buildings."
	)

	var careful_kitchen_state = _new_state()
	var careful_kitchen = _add_staffed_building(careful_kitchen_state, "kitchen", "top_center", 4, "anka")
	careful_kitchen.work_pace = WorkPaceSystemScript.WORK_PACE_CAREFUL
	careful_kitchen_state.current_day_plan.sync_from_state(careful_kitchen_state)
	careful_kitchen_state.resources.set_amount(ResourceIdsScript.FOOD, 100)
	var careful_kitchen_resolver = EndOfDayResolverScript.new()
	careful_kitchen_resolver._resolve_kitchen_processing(careful_kitchen_state, ReportStateScript.new())
	careful_kitchen_resolver._resolve_rations(careful_kitchen_state, ReportStateScript.new())
	_assert(careful_kitchen_state.resources.get_amount(ResourceIdsScript.FOOD) == 90, "Careful Kitchen IV should spend ten food on three full rations.")

	var intense_kitchen_state = _new_state()
	var intense_kitchen = _add_staffed_building(intense_kitchen_state, "kitchen", "top_center", 4, "anka")
	intense_kitchen.work_pace = WorkPaceSystemScript.WORK_PACE_INTENSE
	intense_kitchen_state.current_day_plan.sync_from_state(intense_kitchen_state)
	intense_kitchen_state.resources.set_amount(ResourceIdsScript.FOOD, 100)
	var intense_kitchen_resolver = EndOfDayResolverScript.new()
	intense_kitchen_resolver._resolve_kitchen_processing(intense_kitchen_state, ReportStateScript.new())
	intense_kitchen_resolver._resolve_rations(intense_kitchen_state, ReportStateScript.new())
	_assert(intense_kitchen_state.resources.get_amount(ResourceIdsScript.FOOD) == 92, "Intense Kitchen IV should spend eight food on the same three full rations.")

	var careful_house_state = _new_state()
	var careful_house = _add_staffed_building(careful_house_state, "community_house", "top_right", 2, "anka")
	careful_house.work_pace = WorkPaceSystemScript.WORK_PACE_CAREFUL
	careful_house_state.current_day_plan.sync_from_state(careful_house_state)
	careful_house_state.resources.set_amount(ResourceIdsScript.HOPE, 50)
	var careful_house_resolver = EndOfDayResolverScript.new()
	careful_house_resolver._resolve_community_work(careful_house_state, ReportStateScript.new())
	careful_house_resolver._resolve_hope(careful_house_state, null, ReportStateScript.new())
	_assert(careful_house_state.resources.get_amount(ResourceIdsScript.HOPE) == 51, "Careful Community House II should contribute one Hope after its discrete -1-per-worker adjustment.")

	var intense_house_state = _new_state()
	var intense_house = _add_staffed_building(intense_house_state, "community_house", "top_right", 2, "anka")
	intense_house.work_pace = WorkPaceSystemScript.WORK_PACE_INTENSE
	intense_house_state.current_day_plan.sync_from_state(intense_house_state)
	intense_house_state.resources.set_amount(ResourceIdsScript.HOPE, 50)
	var intense_house_resolver = EndOfDayResolverScript.new()
	intense_house_resolver._resolve_community_work(intense_house_state, ReportStateScript.new())
	intense_house_resolver._resolve_hope(intense_house_state, null, ReportStateScript.new())
	_assert(intense_house_state.resources.get_amount(ResourceIdsScript.HOPE) == 53, "Intense Community House II should contribute three Hope after its discrete +1-per-worker adjustment.")

	var locked_state = _new_state()
	var locked_fishing = _add_staffed_building(locked_state, "fishing_hut", "top_left", 1, "mira")
	var locked_infirmary = _add_staffed_building(locked_state, "infirmary", "center", 1, "anka")
	locked_fishing.work_pace = WorkPaceSystemScript.WORK_PACE_CAREFUL
	locked_infirmary.work_pace = WorkPaceSystemScript.WORK_PACE_INTENSE
	_assert(locked_state.lock_day_plan(null), "The independent local-pace fixture should freeze one canonical DayPlan.")
	locked_fishing.work_pace = WorkPaceSystemScript.WORK_PACE_INTENSE
	locked_infirmary.work_pace = WorkPaceSystemScript.WORK_PACE_CAREFUL
	_assert(
		WorkPaceSystemScript.pace_for_building(locked_state, locked_fishing) == WorkPaceSystemScript.WORK_PACE_CAREFUL
		and WorkPaceSystemScript.pace_for_building(locked_state, locked_infirmary) == WorkPaceSystemScript.WORK_PACE_INTENSE,
		"A locked DayPlan must preserve two different local paces after the mutable BuildingState values diverge."
	)


func _test_house_zero_output_counts_as_real_work() -> void:
	var state = _new_state()
	var house = _add_staffed_building(state, "community_house", "top_right", 1, "anka")
	house.work_pace = WorkPaceSystemScript.WORK_PACE_CAREFUL
	house.work_tension = 2
	state.current_day_plan.sync_from_state(state)
	state.resources.set_amount(ResourceIdsScript.HOPE, 50)
	state.find_survivor("anka").fatigue = 10
	var resolver = EndOfDayResolverScript.new()
	resolver._resolve_community_work(state, ReportStateScript.new())
	_assert(resolver._community_hope_gain_today == 0, "Careful Community House I should round its level contribution down to zero.")
	_assert(
		resolver._committed_work_events.size() == 1
		and str(resolver._committed_work_events[0].get("building_id", "")) == house.id
		and str(resolver._committed_work_events[0].get("work_pace", "")) == WorkPaceSystemScript.WORK_PACE_CAREFUL,
		"A capable House I roster must still commit real careful work when its numeric Hope contribution is zero."
	)
	resolver._resolve_fatigue(state, null, ReportStateScript.new())
	resolver._resolve_work_tension(state, ReportStateScript.new())
	resolver._resolve_hope(state, null, ReportStateScript.new())
	_assert(state.find_survivor("anka").fatigue == 14, "Zero-output real careful House work should add four fatigue instead of granting rest.")
	_assert(house.work_tension == 0 and resolver._work_hope_delta_today == 1, "Zero-output real careful House work should relieve two tension and remain eligible for the one global relief candidate.")
	_assert(state.resources.get_amount(ResourceIdsScript.HOPE) == 51, "The relieved House should add exactly the one aggregated Hope despite producing zero direct House Hope.")


func _test_work_tension_hope_aggregation() -> void:
	var intense_state = _new_state()
	var fishing_hut = _add_staffed_building(intense_state, "fishing_hut", "top_left", 1, "mira")
	var infirmary = _add_staffed_building(intense_state, "infirmary", "center", 1, "anka")
	var idle_kitchen = BuildingStateScript.new()
	idle_kitchen.id = "idle_kitchen"
	idle_kitchen.definition_id = "kitchen"
	idle_kitchen.slot_id = "top_center"
	idle_kitchen.level = 1
	idle_kitchen.is_built = true
	idle_kitchen.work_pace = WorkPaceSystemScript.WORK_PACE_INTENSE
	idle_kitchen.work_tension = 3
	intense_state.buildings.append(idle_kitchen)
	var shelter = BuildingStateScript.new()
	shelter.id = "tension_test_shelter"
	shelter.definition_id = "community_house"
	shelter.slot_id = "top_right"
	shelter.level = 1
	shelter.is_built = true
	intense_state.buildings.append(shelter)
	fishing_hut.work_pace = WorkPaceSystemScript.WORK_PACE_INTENSE
	fishing_hut.work_tension = 1
	infirmary.work_pace = WorkPaceSystemScript.WORK_PACE_INTENSE
	infirmary.work_tension = 2
	intense_state.current_day_plan.sync_from_state(intense_state)
	intense_state.resources.set_amount(ResourceIdsScript.HOPE, 50)
	var intense_resolver = EndOfDayResolverScript.new()
	var intense_report = ReportStateScript.new()
	intense_resolver._commit_work_event("rybak", "fishing", ["mira"], true, true, fishing_hut.id, WorkPaceSystemScript.WORK_PACE_INTENSE)
	intense_resolver._commit_work_event("medyk", "medical_care", ["anka"], true, true, infirmary.id, WorkPaceSystemScript.WORK_PACE_INTENSE)
	intense_resolver._resolve_work_tension(intense_state, intense_report)
	intense_resolver._resolve_hope(intense_state, null, intense_report)
	_assert(fishing_hut.work_tension == 2 and infirmary.work_tension == 3, "Each intensely working building should advance only its own tension by one.")
	_assert(idle_kitchen.work_tension == 1, "An idle building should shed two tension even when intense pace remains selected.")
	_assert(intense_state.resources.get_amount(ResourceIdsScript.HOPE) == 47, "Two intense buildings with two unique workers should apply one global -3 Hope result from the highest tension, not add both penalties.")
	_assert(intense_report.warnings.count("Forsowanie pracy: −3 nominalnej Nadziei (Napięcie 3 + próg obsady 0).") == 1, "An intense-work day should report exactly one nominal Hope penalty from work pace.")

	var relief_state = _new_state()
	var relief_house = _add_staffed_building(relief_state, "community_house", "top_right", 2, "anka")
	relief_house.work_pace = WorkPaceSystemScript.WORK_PACE_CAREFUL
	relief_house.work_tension = 2
	relief_state.current_day_plan.sync_from_state(relief_state)
	relief_state.resources.set_amount(ResourceIdsScript.HOPE, 50)
	var relief_resolver = EndOfDayResolverScript.new()
	var relief_report = ReportStateScript.new()
	relief_resolver._commit_work_event("organizator", "community", ["anka"], true, true, relief_house.id, WorkPaceSystemScript.WORK_PACE_CAREFUL)
	relief_resolver._resolve_work_tension(relief_state, relief_report)
	relief_resolver._resolve_hope(relief_state, null, relief_report)
	_assert(relief_house.work_tension == 0, "Real careful work should remove two local tension from the building.")
	_assert(relief_state.resources.get_amount(ResourceIdsScript.HOPE) == 51, "At least one real careful relief should grant one global Hope, never one point per building.")
	_assert(relief_report.entries.count("Rozładowane Napięcie pracy wzmacnia nominalną Nadzieję o 1.") == 1, "A careful-relief day should report exactly one nominal Hope bonus from work pace.")

	var band_state = _new_state()
	var band_fishing = _add_staffed_building(band_state, "fishing_hut", "top_left", 1, "mira")
	band_fishing.work_pace = WorkPaceSystemScript.WORK_PACE_INTENSE
	band_fishing.work_tension = 1
	band_state.current_day_plan.sync_from_state(band_state)
	var band_resolver = EndOfDayResolverScript.new()
	band_resolver._commit_work_event(
		"rybak",
		"fishing",
		["intense_1", "intense_2", "intense_3", "intense_4"],
		true,
		true,
		band_fishing.id,
		WorkPaceSystemScript.WORK_PACE_INTENSE
	)
	band_resolver._resolve_work_tension(band_state, ReportStateScript.new())
	_assert(
		band_fishing.work_tension == 2 and band_resolver._work_hope_delta_today == -3,
		"Four unique intense workers should cross into workforce band one and combine with the new tension only once."
	)

	var capped_state = _new_state()
	var capped_fishing = _add_staffed_building(capped_state, "fishing_hut", "top_left", 1, "mira")
	var capped_house = _add_staffed_building(capped_state, "community_house", "top_right", 1, "anka")
	capped_fishing.work_pace = WorkPaceSystemScript.WORK_PACE_INTENSE
	capped_fishing.work_tension = 3
	capped_house.work_pace = WorkPaceSystemScript.WORK_PACE_CAREFUL
	capped_house.work_tension = 2
	capped_state.current_day_plan.sync_from_state(capped_state)
	var capped_resolver = EndOfDayResolverScript.new()
	capped_resolver._commit_work_event(
		"organizator",
		"community",
		["anka"],
		true,
		true,
		capped_house.id,
		WorkPaceSystemScript.WORK_PACE_CAREFUL
	)
	capped_resolver._commit_work_event(
		"rybak",
		"fishing",
		["intense_1", "intense_2", "intense_3", "intense_4", "intense_5", "intense_6", "intense_7"],
		true,
		true,
		capped_fishing.id,
		WorkPaceSystemScript.WORK_PACE_INTENSE
	)
	capped_resolver._resolve_work_tension(capped_state, ReportStateScript.new())
	_assert(capped_house.work_tension == 0, "The mixed fixture should still apply local careful tension relief.")
	_assert(
		capped_resolver._work_hope_delta_today == -5,
		"Seven intense workers should enter band two, intense work should override careful relief, and the aggregate penalty should cap at five."
	)

func _test_daily_building_effects() -> void:
	var resolver = EndOfDayResolverScript.new()
	var report = ReportStateScript.new()

	var regular_fishing_state = _new_state()
	_add_staffed_building(regular_fishing_state, "fishing_hut", "top_left", 1, "anka")
	var regular_food_before: int = regular_fishing_state.resources.get_amount(ResourceIdsScript.FOOD)
	resolver._resolve_fishing(regular_fishing_state, report)
	_assert(regular_fishing_state.resources.get_amount(ResourceIdsScript.FOOD) == regular_food_before + 5, "A rested regular worker in Fishing Hut I should produce five food.")

	var specialist_fishing_state = _new_state()
	_add_staffed_building(specialist_fishing_state, "fishing_hut", "top_left", 1, "mira")
	var specialist_food_before: int = specialist_fishing_state.resources.get_amount(ResourceIdsScript.FOOD)
	resolver._resolve_fishing(specialist_fishing_state, report)
	_assert(specialist_fishing_state.resources.get_amount(ResourceIdsScript.FOOD) == specialist_food_before + 6, "Mira should produce five food plus the fisher specialist bonus in Fishing Hut I.")

	var kitchen_state = _new_state()
	_add_staffed_building(kitchen_state, "kitchen", "top_center", 1, "anka")
	kitchen_state.resources.set_amount(ResourceIdsScript.FOOD, 100)
	resolver._resolve_rations(kitchen_state, report)
	_assert(kitchen_state.resources.get_amount(ResourceIdsScript.FOOD) == 89, "Kitchen I should reduce three full rations from 12 to 11 food.")

	var workshop_state = _new_state()
	_add_staffed_building(workshop_state, "workshop", "bottom_left", 1, "anka")
	workshop_state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 70)
	workshop_state.resources.set_amount(ResourceIdsScript.SCRAP, 10)
	resolver._resolve_workshop_repairs(workshop_state, report)
	_assert(workshop_state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY) == 74, "A mechanic in Workshop I should repair four integrity.")
	_assert(workshop_state.resources.get_amount(ResourceIdsScript.SCRAP) == 9, "Workshop repair should spend one scrap.")

	var infirmary_state = _new_state()
	_add_staffed_building(infirmary_state, "infirmary", "center", 1, "anka")
	infirmary_state.find_survivor("mira").health = 50
	resolver._resolve_medical_care(infirmary_state, report)
	_assert(infirmary_state.find_survivor("mira").health == 62, "Infirmary I should restore twelve health.")

	var community_state = _new_state()
	_add_staffed_building(community_state, "community_house", "top_right", 1, "anka")
	community_state.resources.set_amount(ResourceIdsScript.HOPE, 50)
	resolver._resolve_community_work(community_state, report)
	resolver._resolve_hope(community_state, null, report)
	_assert(community_state.resources.get_amount(ResourceIdsScript.HOPE) == 51, "Community House I should add one Hope per worker.")

func _new_state():
	var state = GameStateScript.new()
	state.setup_new_campaign(901, DifficultyProfileScript.new())
	state.tutorial.complete()
	for resource_id in ResourceIdsScript.all():
		state.resources.set_amount(resource_id, 1000)
	state.resources.set_amount(ResourceIdsScript.HOPE, 55)
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 70)
	return state


func _add_test_heavy_object(state) -> void:
	state.underwater_world.blueprint.heavy_object_spawns.append({
		"id": TEST_HEAVY_OBJECT_ID,
		"display_name": "Ciężki obiekt fixture",
		"rewards": {ResourceIdsScript.SCRAP: 2},
	})


func _add_staffed_building(state, definition_id: String, slot_id: String, level: int, survivor_id: String):
	var building = BuildingStateScript.new()
	building.id = "test_%s" % definition_id
	building.definition_id = definition_id
	building.slot_id = slot_id
	building.level = level
	building.is_built = true
	building.assigned_survivor_ids.assign([survivor_id])
	state.buildings.append(building)
	var slot_data: Dictionary = state.platform.slot_states[slot_id]
	slot_data["building_id"] = building.id
	state.platform.slot_states[slot_id] = slot_data
	var survivor = state.find_survivor(survivor_id)
	survivor.current_assignment = building.id
	survivor.status = SurvivorStateScript.Status.WORKING
	return building

func _resume_planning_after_report(state) -> void:
	_assert(state.current_phase == GamePhaseScript.Phase.END_DAY_REPORT, "A non-terminal system-test day should produce a report before the next planning step.")
	state.pending_settlement_event = null
	state.current_phase = GamePhaseScript.Phase.BASE_PLANNING

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Building system test failed: " + message)
