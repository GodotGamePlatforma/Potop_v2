extends SceneTree


const ScenarioFactoryScript := preload("res://scripts/diving/DiveRecoveryScenarioFactory.gd")
const AnalyzerScript := preload("res://scripts/diving/DiveRecoveryAnalyzer.gd")
const QueryScript := preload("res://scripts/diving/DiveRecoveryQuery.gd")
const CertificateScript := preload("res://scripts/diving/DiveRecoveryCertificate.gd")
const NavigationSnapshotScript := preload("res://scripts/diving/DiveNavigationSnapshot.gd")
const ContinuousWorldScript := preload("res://scripts/diving/UnderwaterMapRuntime.gd")
const PersistenceValidatorScript := preload("res://scripts/data/GameStatePersistenceValidator.gd")
const ThreatDefinitionScript := preload("res://scripts/definitions/DiveThreatDefinition.gd")

const POLICY_PATH := "res://data/diving_validation/default_safety_policy.tres"
const TUTORIAL_DAY2_PROFILE_PATH := "res://data/diving_validation/profiles/tutorial_day2_station_i.tres"
const TUTORIAL_DAY3_PROFILE_PATH := "res://data/diving_validation/profiles/tutorial_day3_station_i_workshop_i.tres"
const TUTORIAL_FIRST_DIVE_QUERY_PATH := "res://data/diving_validation/queries/tutorial_first_dive_minimum.tres"
const TUTORIAL_SC01_J7_QUERY_PATH := "res://data/diving_validation/queries/tutorial_sc01_j7.tres"
const TUTORIAL_FIRST_DIVE_MANIFEST := {
	"fabric_rubber": 2,
	"food": 1,
	"planks": 1,
	"scrap": 3,
}
const PROFILE_PATHS: Array[String] = [
	"res://data/diving_validation/profiles/tank_i_station_i.tres",
	"res://data/diving_validation/profiles/tank_ii_workshop_ii.tres",
	"res://data/diving_validation/profiles/tank_iii_workshop_iii.tres",
	"res://data/diving_validation/profiles/station_iv_main_line.tres",
]
const ALL_PROFILE_PATHS: Dictionary = {
	"tutorial_day2_station_i": TUTORIAL_DAY2_PROFILE_PATH,
	"tutorial_day3_station_i_workshop_i": TUTORIAL_DAY3_PROFILE_PATH,
	"tank_i_station_i": "res://data/diving_validation/profiles/tank_i_station_i.tres",
	"tank_ii_workshop_ii": "res://data/diving_validation/profiles/tank_ii_workshop_ii.tres",
	"tank_iii_workshop_iii": "res://data/diving_validation/profiles/tank_iii_workshop_iii.tres",
	"station_iv_main_line": "res://data/diving_validation/profiles/station_iv_main_line.tres",
	"station_iv_buoy_b01": "res://data/diving_validation/profiles/station_iv_buoy_b01.tres",
	"station_iv_buoy_b02": "res://data/diving_validation/profiles/station_iv_buoy_b02.tres",
	"station_iv_buoy_b03": "res://data/diving_validation/profiles/station_iv_buoy_b03.tres",
	"story_archive_main_line": "res://data/diving_validation/profiles/story_archive_main_line.tres",
	"story_r3_diagnostic_main_line": "res://data/diving_validation/profiles/story_r3_diagnostic_main_line.tres",
	"story_r3_generator_main_line": "res://data/diving_validation/profiles/story_r3_generator_main_line.tres",
	"story_c4_buoy_b03": "res://data/diving_validation/profiles/story_c4_buoy_b03.tres",
	"story_splitter_buoy_b03": "res://data/diving_validation/profiles/story_splitter_buoy_b03.tres",
}
const STATIC_TARGET_COUNT := 65
const STATIC_RESOURCE_PAIR_QUERY_COUNT := 103
const STATIC_FULL_INTERACTION_QUERY_COUNT := 35
const STATIC_QUERY_COUNT := 138
const STATIC_TARGET_CERTIFICATION_PROFILE: Dictionary = {
	"tutorial_market_crate": "tutorial_day2_station_i",
	"tutorial_workshop_case": "tutorial_day2_station_i",
	"SC-01": "tutorial_day3_station_i_workshop_i",
	"junction_j7": "tutorial_day3_station_i_workshop_i",
	"pickup_r1_food_01": "tank_i_station_i",
	"tutorial_service_locker": "tank_ii_workshop_ii",
	"pharmacy_medicine_case": "tank_ii_workshop_ii",
	"hotel_linen_cache": "tank_ii_workshop_ii",
	"greenhouse_supply_box": "tank_ii_workshop_ii",
	"seed_bank_vault": "tank_ii_workshop_ii",
	"ship_carpentry_store": "tank_ii_workshop_ii",
	"museum_reinforcement_cache": "tank_ii_workshop_ii",
	"archive_maintenance_store": "tank_ii_workshop_ii",
	"park_service_shed": "tank_ii_workshop_ii",
	"garden_center_lumber": "tank_ii_workshop_ii",
	"tangled_support_cache": "tank_ii_workshop_ii",
	"pickup_r1_planks_01": "tank_ii_workshop_ii",
	"pickup_r1_scrap_01": "tank_ii_workshop_ii",
	"pickup_r2_food_01": "tank_ii_workshop_ii",
	"pickup_r2_planks_01": "tank_ii_workshop_ii",
	"rescue_hotel_leon": "tank_ii_workshop_ii",
	"SC-02": "tank_ii_workshop_ii",
	"SC-03": "tank_ii_workshop_ii",
	"hospital_emergency_store": "tank_iii_workshop_iii",
	"hospital_structural_store": "tank_iii_workshop_iii",
	"suburb_renovation_store": "tank_iii_workshop_iii",
	"port_tool_crate": "tank_iii_workshop_iii",
	"factory_control_parts": "tank_iii_workshop_iii",
	"chemical_cabinet": "tank_iii_workshop_iii",
	"shipyard_material_rack": "tank_iii_workshop_iii",
	"power_plant_service_store": "tank_iii_workshop_iii",
	"scrapyard_sorting_cache": "tank_iii_workshop_iii",
	"pickup_r2_scrap_01": "tank_iii_workshop_iii",
	"pickup_r3_food_01": "tank_iii_workshop_iii",
	"pickup_r3_planks_01": "tank_iii_workshop_iii",
	"pickup_r3_scrap_01": "tank_iii_workshop_iii",
	"B-01": "tank_iii_workshop_iii",
	"SC-04": "tank_iii_workshop_iii",
	"SC-05": "tank_iii_workshop_iii",
	"SC-06": "tank_iii_workshop_iii",
	"ship_engine_r1": "station_iv_main_line",
	"laboratory_prototype": "station_iv_main_line",
	"sealed_gate_parts": "station_iv_buoy_b03",
	"pickup_r4_scrap_01": "station_iv_main_line",
	"SC-07": "station_iv_main_line",
	"SC-08": "station_iv_main_line",
	"B-02": "station_iv_buoy_b01",
	"B-03": "station_iv_buoy_b02",
	"shipyard_winch_r3": "station_iv_buoy_b02",
	"scrapyard_generator_r3": "station_iv_buoy_b02",
	"metro_maintenance_store": "station_iv_buoy_b03",
	"bunker_construction_reserve": "station_iv_buoy_b03",
	"city_center_relief_store": "station_iv_buoy_b03",
	"heart_structural_cache": "station_iv_buoy_b03",
	"metro_reconstruction_reserve": "station_iv_buoy_b03",
	"bunker_reconstruction_reserve": "station_iv_buoy_b03",
	"city_reconstruction_reserve": "station_iv_buoy_b03",
	"heart_reconstruction_reserve": "station_iv_buoy_b03",
	"pickup_r4_food_01": "station_iv_buoy_b03",
	"pickup_r4_planks_01": "station_iv_buoy_b03",
	"archive_terminal": "story_archive_main_line",
	"r3_diagnostic_panel": "story_r3_diagnostic_main_line",
	"r3_generator": "story_r3_generator_main_line",
	"c4_switchboard": "story_c4_buoy_b03",
	"c4_splitter_mount": "story_splitter_buoy_b03",
}
const STORY_ROUTE_TARGETS: Dictionary = {
	"story_archive_main_line": ["archive_terminal"],
	"story_r3_diagnostic_main_line": ["r3_diagnostic_panel"],
	"story_r3_generator_main_line": ["r3_generator"],
	"story_c4_buoy_b03": ["c4_switchboard"],
	"story_splitter_buoy_b03": ["c4_splitter_mount"],
}
const STORY_PROFILE_SEQUENCE: Array[String] = [
	"story_archive_main_line",
	"story_r3_diagnostic_main_line",
	"story_r3_generator_main_line",
	"story_c4_buoy_b03",
	"story_splitter_buoy_b03",
]
const PROFILE_ENTRY_CONTRACTS: Dictionary = {
	"station_iv_main_line": {"entry": "R1-00", "buoys": []},
	"station_iv_buoy_b01": {"entry": "R2-02", "buoys": ["B-01"]},
	"station_iv_buoy_b02": {"entry": "R3-01", "buoys": ["B-01", "B-02"]},
	"station_iv_buoy_b03": {"entry": "R4-01", "buoys": ["B-01", "B-02", "B-03"]},
	"story_archive_main_line": {"entry": "R1-00", "buoys": []},
	"story_r3_diagnostic_main_line": {"entry": "R1-00", "buoys": []},
	"story_r3_generator_main_line": {"entry": "R1-00", "buoys": []},
	"story_c4_buoy_b03": {"entry": "R4-01", "buoys": ["B-01", "B-02", "B-03"]},
	"story_splitter_buoy_b03": {"entry": "R4-01", "buoys": ["B-01", "B-02", "B-03"]},
}
const DIFFICULTY_PATHS: Array[String] = [
	"res://data/difficulty/easy.tres",
	"res://data/difficulty/standard.tres",
	"res://data/difficulty/hard.tres",
]
const PROVEN_EARLIEST_ASSIGNMENTS: Array[Dictionary] = [
	{
		"profile_path": "res://data/diving_validation/profiles/tank_i_station_i.tres",
		"query_path": "res://data/diving_validation/queries/tutorial_market_crate_full.tres",
		"target_id": "tutorial_market_crate",
		"earlier_reason_codes": [],
	},
	{
		"profile_path": "res://data/diving_validation/profiles/tank_ii_workshop_ii.tres",
		"query_path": "res://data/diving_validation/queries/greenhouse_supply_fabric_rubber_max.tres",
		"target_id": "greenhouse_supply_box",
		"earlier_reason_codes": ["REQUIRED_TOOL_MISSING"],
	},
	{
		"profile_path": "res://data/diving_validation/profiles/tank_iii_workshop_iii.tres",
		"query_path": "res://data/diving_validation/queries/buoy_b01_deploy.tres",
		"target_id": "B-01",
		"earlier_reason_codes": ["TARGET_NOT_FOUND", "TARGET_NOT_FOUND"],
	},
	{
		"profile_path": "res://data/diving_validation/profiles/station_iv_main_line.tres",
		"query_path": "res://data/diving_validation/queries/ship_engine_r1_mark.tres",
		"target_id": "ship_engine_r1",
		"earlier_reason_codes": ["REQUIRED_TOOL_MISSING", "REQUIRED_TOOL_MISSING", "REQUIRED_TOOL_MISSING"],
	},
]
const PROFILE_PREDECESSORS: Dictionary = {
	"tank_i_station_i": [],
	"tutorial_day2_station_i": ["tank_i_station_i"],
	"tutorial_day3_station_i_workshop_i": ["tutorial_day2_station_i"],
	"tank_ii_workshop_ii": ["tank_i_station_i"],
	"tank_iii_workshop_iii": ["tank_ii_workshop_ii"],
	"station_iv_main_line": ["tank_iii_workshop_iii"],
	"station_iv_buoy_b01": ["station_iv_main_line"],
	"station_iv_buoy_b02": ["station_iv_buoy_b01"],
	"station_iv_buoy_b03": ["station_iv_buoy_b02"],
	"story_archive_main_line": ["tutorial_day3_station_i_workshop_i", "tank_ii_workshop_ii"],
	"story_r3_diagnostic_main_line": ["story_archive_main_line", "tank_iii_workshop_iii"],
	"story_r3_generator_main_line": ["story_r3_diagnostic_main_line"],
	"story_c4_buoy_b03": ["story_r3_generator_main_line", "station_iv_buoy_b03"],
	"story_splitter_buoy_b03": ["story_c4_buoy_b03"],
}
const STATIC_PREFLIGHT_FAILURE_CODES: Array[StringName] = [
	CertificateScript.TARGET_NOT_FOUND,
	CertificateScript.TARGET_UNAVAILABLE,
	CertificateScript.REQUIRED_TOOL_MISSING,
	CertificateScript.SOURCE_AMOUNT_UNAVAILABLE,
	CertificateScript.CAPACITY_SLOT_EXCEEDED,
	CertificateScript.CAPACITY_MASS_EXCEEDED,
]
# Kluczem jest query_id: 103 pary źródło + zasób oraz 35 pełnych interakcji.
# Wypełnia się wyłącznie wynikiem pełnego discovery replayu; pusta mapa celowo
# wymusza czytelny raport zamiast zgadywania najwcześniejszych profili.
const EXPECTED_EARLIEST_PROFILES: Dictionary = {}

var _failed := false
var _enumerated_static_target_ids: Dictionary = {}
var _analyzer = AnalyzerScript.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var earliest_only := OS.get_environment("DIVE_CERT_EARLIEST_ONLY").strip_edges() == "1"
	var exhaustive := OS.get_environment("DIVE_CERT_EXHAUSTIVE").strip_edges() == "1"
	var contract_only := (
		OS.get_environment("DIVE_CERT_CONTRACT_ONLY").strip_edges() == "1"
		or (not earliest_only and not exhaustive)
	)
	if earliest_only and exhaustive:
		_assert(false, "DIVE_CERT_EARLIEST_ONLY i DIVE_CERT_EXHAUSTIVE są wzajemnie wykluczające.")
		quit(1)
		return
	if exhaustive and contract_only:
		_assert(false, "DIVE_CERT_EXHAUSTIVE i DIVE_CERT_CONTRACT_ONLY są wzajemnie wykluczające.")
		quit(1)
		return
	var earliest_shard := _earliest_shard_config(earliest_only)
	if not bool(earliest_shard.get("valid", false)):
		quit(1)
		return
	var certification_difficulty_paths := _certification_difficulty_paths()
	var extended_contract_difficulty_path := _extended_contract_difficulty_path(certification_difficulty_paths)
	_validate_complete_catalog_contract()
	_validate_assignment_table_contract()
	_validate_profile_contracts_and_real_builder()
	_validate_routing_signature_snapshot_lifetime()
	_validate_tutorial_route_resource_contracts()
	_validate_profile_dag_contract(not bool(earliest_shard.get("enabled", false)))
	if earliest_only:
		await _validate_earliest_profile_frontier(earliest_shard)
		if _failed:
			quit(1)
			return
		if bool(earliest_shard.get("enabled", false)):
			print(
				"Dive recovery earliest-profile discovery shard %d/%d passed."
				% [int(earliest_shard.index), int(earliest_shard.count)]
			)
		else:
			print("Dive recovery earliest-profile certification passed for the complete static catalog.")
		quit(0)
		return
	_validate_current_aware_planner_margin()
	_validate_interaction_current_replay()
	if contract_only:
		await _validate_detached_shortcut_sequence()
		if _failed:
			quit(1)
			return
		print("Dive recovery certification contract test passed: planner margin, interaction currents, detached shortcuts and static catalog. Set DIVE_CERT_EXHAUSTIVE=1 for the manual frontier replay.")
		quit(0)
		return
	await _validate_earliest_profile_frontier(earliest_shard)
	if _failed:
		quit(1)
		return
	for assignment_index in range(PROVEN_EARLIEST_ASSIGNMENTS.size()):
		for difficulty_path in certification_difficulty_paths:
			await _validate_assignment_on_public_difficulty(
				PROVEN_EARLIEST_ASSIGNMENTS[assignment_index],
				assignment_index,
				difficulty_path,
				assignment_index == 0 and difficulty_path == extended_contract_difficulty_path,
				difficulty_path == extended_contract_difficulty_path
			)
	_validate_assignment_enumeration_coverage()
	for difficulty_path in certification_difficulty_paths:
		await _validate_tutorial_route(
			TUTORIAL_DAY2_PROFILE_PATH,
			TUTORIAL_FIRST_DIVE_QUERY_PATH,
			["tutorial_market_crate", "tutorial_workshop_case"],
			TUTORIAL_FIRST_DIVE_MANIFEST,
			2,
			false,
			difficulty_path
		)
		await _validate_tutorial_route(
			TUTORIAL_DAY3_PROFILE_PATH,
			TUTORIAL_SC01_J7_QUERY_PATH,
			["SC-01", "junction_j7"],
			{},
			3,
			true,
			difficulty_path
		)
		await _validate_complete_catalog_on_public_difficulty(difficulty_path)
	await _validate_detached_shortcut_sequence()
	if _failed:
		quit(1)
		return
	print("Dive recovery certification test passed: real setup/snapshot, public presets, FEASIBLE/SAFE, stable reasons and no campaign mutation.")
	quit(0)


func _earliest_shard_config(earliest_only: bool) -> Dictionary:
	var count_text := OS.get_environment("DIVE_CERT_EARLIEST_SHARD_COUNT").strip_edges()
	var index_text := OS.get_environment("DIVE_CERT_EARLIEST_SHARD_INDEX").strip_edges()
	if count_text.is_empty() and index_text.is_empty():
		return {"valid": true, "enabled": false, "count": 1, "index": 0}
	if not earliest_only:
		_assert(
			false,
			"DIVE_CERT_EARLIEST_SHARD_COUNT/INDEX wymagają DIVE_CERT_EARLIEST_ONLY=1."
		)
		return {"valid": false, "enabled": false, "count": 1, "index": 0}
	if count_text.is_empty() or index_text.is_empty():
		_assert(
			false,
			"DIVE_CERT_EARLIEST_SHARD_COUNT i DIVE_CERT_EARLIEST_SHARD_INDEX muszą być ustawione razem."
		)
		return {"valid": false, "enabled": false, "count": 1, "index": 0}
	if not count_text.is_valid_int() or not index_text.is_valid_int():
		_assert(false, "Parametry shardingu earliest muszą być liczbami całkowitymi.")
		return {"valid": false, "enabled": false, "count": 1, "index": 0}
	var shard_count := int(count_text)
	var shard_index := int(index_text)
	if shard_count < 1 or shard_count > STATIC_QUERY_COUNT:
		_assert(
			false,
			"DIVE_CERT_EARLIEST_SHARD_COUNT musi należeć do zakresu 1..%d."
			% STATIC_QUERY_COUNT
		)
		return {"valid": false, "enabled": false, "count": shard_count, "index": shard_index}
	if shard_index < 0 or shard_index >= shard_count:
		_assert(
			false,
			"DIVE_CERT_EARLIEST_SHARD_INDEX jest 0-based i musi należeć do zakresu 0..%d."
			% (shard_count - 1)
		)
		return {"valid": false, "enabled": false, "count": shard_count, "index": shard_index}
	return {"valid": true, "enabled": true, "count": shard_count, "index": shard_index}


func _certification_difficulty_paths() -> Array[String]:
	var requested_difficulty := OS.get_environment("DIVE_CERT_DIFFICULTY").strip_edges().to_lower()
	if requested_difficulty.is_empty():
		var all_paths: Array[String] = []
		all_paths.assign(DIFFICULTY_PATHS)
		return all_paths
	var expected_suffix := "/%s.tres" % requested_difficulty
	for difficulty_path in DIFFICULTY_PATHS:
		if difficulty_path.ends_with(expected_suffix):
			var selected_paths: Array[String] = []
			selected_paths.append(difficulty_path)
			return selected_paths
	_assert(false, "DIVE_CERT_DIFFICULTY musi mieć wartość easy, standard albo hard; otrzymano %s." % requested_difficulty)
	return []


func _extended_contract_difficulty_path(difficulty_paths: Array[String]) -> String:
	for difficulty_path in difficulty_paths:
		if difficulty_path.ends_with("standard.tres"):
			return difficulty_path
	return difficulty_paths[0] if not difficulty_paths.is_empty() else ""


func _validate_profile_contracts_and_real_builder() -> void:
	var expected_tanks := ["oxygen_tank_mk1", "oxygen_tank_mk2", "oxygen_tank_mk3", "oxygen_tank_mk3"]
	var expected_station_levels := [1, 2, 3, 4]
	var expected_workshop_levels := [0, 2, 3, 3]
	var standard = ResourceLoader.load("res://data/difficulty/standard.tres")
	var wrong_difficulty = ResourceLoader.load(PROFILE_PATHS[0])
	var wrong_difficulty_scenario: Dictionary = ScenarioFactoryScript.new().build(
		ResourceLoader.load(PROFILE_PATHS[0]),
		wrong_difficulty
	)
	_assert(
		_errors_contain(wrong_difficulty_scenario.get("errors", PackedStringArray()), "difficulty profile has the wrong type"),
		"Fabryka scenariusza musi odrzucić Resource niewłaściwego typu zamiast po cichu użyć domyślnej trudności."
	)
	for index in range(PROFILE_PATHS.size()):
		var profile = ResourceLoader.load(PROFILE_PATHS[index])
		_assert(profile != null and profile.is_valid(), "Każdy publiczny checkpoint certyfikacji musi być poprawnym Resource.")
		if profile == null:
			continue
		_assert(int(profile.station_level) == expected_station_levels[index], "Checkpoint musi zachować zatwierdzony poziom Stacji.")
		_assert(int(profile.workshop_level) == expected_workshop_levels[index], "Checkpoint musi zachować legalny poziom Warsztatu.")
		var scenario: Dictionary = ScenarioFactoryScript.new().build(profile, standard)
		var errors: PackedStringArray = scenario.get("errors", PackedStringArray())
		_assert(errors.is_empty(), "Fabryka checkpointu musi przejść przez rzeczywisty ExpeditionPreparationSystem: %s" % str(errors))
		if not errors.is_empty():
			continue
		_assert(str(scenario.setup.equipped_gear.get("oxygen_tank", "")) == expected_tanks[index], "Setup musi używać legalnie wyposażonej butli checkpointu.")
		_assert(int(scenario.setup.base_support_level) == expected_station_levels[index], "Setup musi pochodzić z rzeczywistego poziomu Stacji.")
		_assert(scenario.state.current_expedition_setup == null, "Fabryka projektowa nie może zapisywać setupu do GameState.")
		if index == 3:
			_assert(str(scenario.setup.start_entry_point) == "R1-00", "Główny checkpoint Stacji IV musi nadal używać normalnej liny platformy.")
			_assert(scenario.state.underwater_world.placed_buoys.is_empty(), "Główny checkpoint Stacji IV nie może pozornie korzystać z boi.")

	var illegal_tank = ResourceLoader.load(PROFILE_PATHS[0]).duplicate(true)
	illegal_tank.profile_id = &"illegal_tank_mk2"
	illegal_tank.oxygen_tank_id = "oxygen_tank_mk2"
	illegal_tank.workshop_level = 1
	_assert(
		not illegal_tank.is_valid() and _errors_contain(illegal_tank.validation_errors(), "oxygen_tank_id requires Workshop level 2"),
		"Butla II nie może wejść do profilu przed legalnym Warsztatem II."
	)
	var illegal_tank_scenario: Dictionary = ScenarioFactoryScript.new().build(illegal_tank, standard)
	_assert(
		_errors_contain(illegal_tank_scenario.get("errors", PackedStringArray()), "oxygen_tank_id requires Workshop level 2"),
		"Fabryka scenariusza musi odrzucić Butlę II poniżej Warsztatu II."
	)
	var illegal_lantern = ResourceLoader.load(PROFILE_PATHS[0]).duplicate(true)
	illegal_lantern.profile_id = &"illegal_lantern_mk2"
	illegal_lantern.light_id = "diving_lantern_mk2"
	illegal_lantern.workshop_level = 0
	_assert(
		not illegal_lantern.is_valid() and _errors_contain(illegal_lantern.validation_errors(), "light_id requires Workshop level 1"),
		"Latarnia II nie może wejść do profilu przed legalnym Warsztatem I."
	)
	var illegal_lantern_scenario: Dictionary = ScenarioFactoryScript.new().build(illegal_lantern, standard)
	_assert(
		_errors_contain(illegal_lantern_scenario.get("errors", PackedStringArray()), "light_id requires Workshop level 1"),
		"Fabryka scenariusza musi odrzucić Latarnię II poniżej Warsztatu I."
	)
	var illegal_harpoon = ResourceLoader.load(PROFILE_PATHS[0]).duplicate(true)
	illegal_harpoon.profile_id = &"illegal_harpoon"
	illegal_harpoon.weapon_id = "harpoon_pistol"
	illegal_harpoon.workshop_level = 1
	_assert(
		not illegal_harpoon.is_valid() and _errors_contain(illegal_harpoon.validation_errors(), "weapon_id requires Workshop level 2"),
		"Pistolet harpunowy nie może wejść do profilu przed legalnym Warsztatem II."
	)
	var illegal_harpoon_scenario: Dictionary = ScenarioFactoryScript.new().build(illegal_harpoon, standard)
	_assert(
		_errors_contain(illegal_harpoon_scenario.get("errors", PackedStringArray()), "weapon_id requires Workshop level 2"),
		"Fabryka scenariusza musi odrzucić Harpun poniżej Warsztatu II."
	)
	var unknown_buoy = ResourceLoader.load("res://data/diving_validation/profiles/station_iv_buoy_b01.tres").duplicate(true)
	unknown_buoy.profile_id = &"unknown_buoy"
	unknown_buoy.placed_buoy_ids.assign(["B-404"])
	var unknown_buoy_scenario: Dictionary = ScenarioFactoryScript.new().build(unknown_buoy, standard)
	_assert(
		_errors_contain(unknown_buoy_scenario.get("errors", PackedStringArray()), "unknown buoy B-404"),
		"Fabryka profilu musi odrzucić nieistniejącą boję zamiast certyfikować inną trasę."
	)
	var missing_entry_buoy = ResourceLoader.load("res://data/diving_validation/profiles/station_iv_buoy_b02.tres").duplicate(true)
	missing_entry_buoy.profile_id = &"missing_entry_buoy"
	missing_entry_buoy.placed_buoy_ids.assign(["B-01"])
	var missing_entry_scenario: Dictionary = ScenarioFactoryScript.new().build(missing_entry_buoy, standard)
	_assert(
		_errors_contain(missing_entry_scenario.get("errors", PackedStringArray()), "has no previously placed matching buoy"),
		"Fabryka profilu musi odrzucić wejście bez odpowiadającej mu wcześniej ustawionej boi."
	)
	var station_iii_main_with_buoy = ResourceLoader.load(PROFILE_PATHS[2]).duplicate(true)
	station_iii_main_with_buoy.profile_id = &"station_iii_main_with_buoy"
	station_iii_main_with_buoy.campaign_day = 3
	station_iii_main_with_buoy.placed_buoy_ids.assign(["B-01"])
	station_iii_main_with_buoy.start_entry_point = "R1-00"
	_assert(
		station_iii_main_with_buoy.is_valid(),
		"Stacja III może zachować wcześniej ustawioną boję, jeśli wyprawa nadal startuje z głównej liny."
	)
	var station_iii_main_scenario: Dictionary = ScenarioFactoryScript.new().build(station_iii_main_with_buoy, standard)
	_assert(
		station_iii_main_scenario.get("errors", PackedStringArray()).is_empty()
		and str(station_iii_main_scenario.setup.start_entry_point) == "R1-00"
		and station_iii_main_scenario.state.underwater_world.placed_buoys == ["B-01"],
		"Fabryka musi zachować boję przy głównym wejściu Stacji III bez udostępniania startu z boi."
	)
	var station_iii_buoy_entry = station_iii_main_with_buoy.duplicate(true)
	station_iii_buoy_entry.profile_id = &"station_iii_buoy_entry"
	station_iii_buoy_entry.start_entry_point = "R2-02"
	_assert(
		not station_iii_buoy_entry.is_valid()
		and _errors_contain(station_iii_buoy_entry.validation_errors(), "non-primary entry requires Diving Station IV"),
		"Dopiero Stacja IV może wybrać wcześniej ustawioną boję jako wejście wyprawy."
	)
	var unknown_shortcut = ResourceLoader.load(PROFILE_PATHS[3]).duplicate(true)
	unknown_shortcut.profile_id = &"unknown_shortcut"
	unknown_shortcut.opened_shortcut_ids.assign(["SC-404"])
	var unknown_shortcut_scenario: Dictionary = ScenarioFactoryScript.new().build(unknown_shortcut, standard)
	_assert(
		_errors_contain(unknown_shortcut_scenario.get("errors", PackedStringArray()), "unknown shortcut SC-404"),
		"Fabryka profilu musi odrzucić nieistniejący skrót."
	)
	var unknown_device = ResourceLoader.load(PROFILE_PATHS[3]).duplicate(true)
	unknown_device.profile_id = &"unknown_device"
	unknown_device.activated_fixed_device_ids.assign(["device_404"])
	var unknown_device_scenario: Dictionary = ScenarioFactoryScript.new().build(unknown_device, standard)
	_assert(
		_errors_contain(unknown_device_scenario.get("errors", PackedStringArray()), "unknown fixed device device_404"),
		"Fabryka profilu musi odrzucić nieistniejące urządzenie fabularne."
	)
	var premature_c4 = ResourceLoader.load(PROFILE_PATHS[3]).duplicate(true)
	premature_c4.profile_id = &"premature_c4"
	premature_c4.campaign_day = 9
	premature_c4.activated_fixed_device_ids.assign(["c4_switchboard"])
	var premature_c4_scenario: Dictionary = ScenarioFactoryScript.new().build(premature_c4, standard)
	_assert(
		_errors_contain(premature_c4_scenario.get("errors", PackedStringArray()), "Aktywna Rozdzielnia C-4 wymaga Generatora R-3"),
		"Fabryka profilu musi odrzucić C-4 bez legalnego łańcucha J-7 → Archiwum → R-3."
	)
	var premature_generator = ResourceLoader.load(PROFILE_PATHS[3]).duplicate(true)
	premature_generator.profile_id = &"premature_generator"
	premature_generator.campaign_day = 8
	premature_generator.story_access_ids.assign(["r3_generator_active"])
	var premature_generator_scenario: Dictionary = ScenarioFactoryScript.new().build(premature_generator, standard)
	_assert(
		_errors_contain(premature_generator_scenario.get("errors", PackedStringArray()), "Stan Generatora R-3 nie odpowiada dniowi aktywacji"),
		"Fabryka profilu musi odrzucić samą flagę Generatora bez trwałego urządzenia i wcześniejszych etapów fabuły."
	)
	var chronologically_impossible = ResourceLoader.load("res://data/diving_validation/profiles/story_splitter_buoy_b03.tres").duplicate(true)
	chronologically_impossible.profile_id = &"chronologically_impossible"
	chronologically_impossible.campaign_day = 1
	var impossible_scenario: Dictionary = ScenarioFactoryScript.new().build(chronologically_impossible, standard)
	_assert(
		_errors_contain(impossible_scenario.get("errors", PackedStringArray()), "junction_j7 cannot be completed before campaign day 3"),
		"Fabryka profilu musi odrzucić kompletny, lecz chronologicznie niemożliwy łańcuch fabuły."
	)

	var archive_profile = ResourceLoader.load(str(ALL_PROFILE_PATHS["story_archive_main_line"]))
	var expected_front_days := {"easy": 15, "standard": 12, "hard": 10}
	for difficulty_path in DIFFICULTY_PATHS:
		var difficulty = ResourceLoader.load(difficulty_path)
		var archive_scenario: Dictionary = ScenarioFactoryScript.new().build(archive_profile, difficulty)
		var archive_errors: PackedStringArray = archive_scenario.get("errors", PackedStringArray())
		_assert(archive_errors.is_empty(), "Checkpoint po J-7 musi odtworzyć legalny licznik Frontu: %s" % str(archive_errors))
		if not archive_errors.is_empty():
			continue
		var archive_story = archive_scenario.state.story_flags
		var expected_days := int(expected_front_days[str(difficulty.profile_id)])
		_assert(
			archive_story.black_front_active
			and not archive_story.black_front_arrived
			and int(archive_story.black_front_days_total) == expected_days
			and int(archive_story.black_front_days_remaining) == expected_days
			and int(archive_story.black_front_started_day) == 3
			and int(archive_story.black_front_last_advanced_day) == 3,
			"Początek dnia 4 musi zachować pełne 15/12/10 dni Frontu zależnie od trudności."
		)
	var diagnostic_profile = ResourceLoader.load(str(ALL_PROFILE_PATHS["story_r3_diagnostic_main_line"]))
	var diagnostic_scenario: Dictionary = ScenarioFactoryScript.new().build(diagnostic_profile, standard)
	_assert(
		diagnostic_scenario.get("errors", PackedStringArray()).is_empty()
		and int(diagnostic_scenario.state.story_flags.black_front_days_remaining) == 11
		and int(diagnostic_scenario.state.story_flags.black_front_last_advanced_day) == 4,
		"Na początku dnia 5 licznik Standard musi odjąć dokładnie ukończony dzień 4."
	)

	var installed_splitter = ResourceLoader.load(str(ALL_PROFILE_PATHS["story_splitter_buoy_b03"])).duplicate(true)
	installed_splitter.profile_id = &"story_splitter_installed_buoy_b03"
	installed_splitter.activated_fixed_device_ids.append("c4_splitter_mount")
	installed_splitter.story_access_ids.append("common_line_splitter_installed")
	var installed_splitter_scenario: Dictionary = ScenarioFactoryScript.new().build(installed_splitter, standard)
	var installed_splitter_errors: PackedStringArray = installed_splitter_scenario.get("errors", PackedStringArray())
	_assert(installed_splitter_errors.is_empty(), "Checkpoint po montażu Rozdzielacza musi być legalny: %s" % str(installed_splitter_errors))
	if installed_splitter_errors.is_empty():
		var installed_story = installed_splitter_scenario.state.story_flags
		_assert(
			installed_story.common_line_splitter_ready
			and installed_story.common_line_splitter_installed
			and int(installed_story.common_line_splitter_completed_day) == 11
			and int(installed_story.common_line_splitter_installed_day) == 12
			and installed_splitter_scenario.state.underwater_world.activated_fixed_devices.has("c4_splitter_mount")
			and not installed_splitter_scenario.setup.selected_gear.has("common_line_splitter"),
			"Zamontowany Rozdzielacz musi mieć typowany stan, trwałe urządzenie i nie wracać do ekwipunku instalacyjnego."
		)
	var installed_without_mount = ResourceLoader.load(str(ALL_PROFILE_PATHS["story_splitter_buoy_b03"])).duplicate(true)
	installed_without_mount.profile_id = &"splitter_installed_without_mount"
	installed_without_mount.story_access_ids.append("common_line_splitter_installed")
	var installed_without_mount_scenario: Dictionary = ScenarioFactoryScript.new().build(installed_without_mount, standard)
	_assert(
		_errors_contain(installed_without_mount_scenario.get("errors", PackedStringArray()), "Stan montażu Rozdzielacza nie odpowiada dniowi instalacji"),
		"Flaga zamontowanego Rozdzielacza bez trwałego c4_splitter_mount musi zostać odrzucona."
	)


func _validate_complete_catalog_contract() -> void:
	_assert(STATIC_TARGET_CERTIFICATION_PROFILE.size() == STATIC_TARGET_COUNT, "Katalog musi przypisywać dokładnie 65 statycznych celów gameplayowych do legalnych profili certyfikacji.")
	var recovery_policy = ResourceLoader.load(POLICY_PATH)
	_assert(recovery_policy != null and recovery_policy.is_valid(), "Publiczna polityka certyfikacji musi być poprawnym Resource.")
	if recovery_policy != null:
		_assert(is_equal_approx(float(recovery_policy.planner_clearance_margin_world), 16.0), "Planner musi zachować jawny margines 16 jednostek ponad fizyczny gabaryt replayu.")
		var invalid_margin = recovery_policy.duplicate(true)
		invalid_margin.planner_clearance_margin_world = 65.0
		_assert(not invalid_margin.is_valid(), "Polityka musi odrzucać margines planera większy niż 64 jednostki.")
	_assert(STORY_PROFILE_SEQUENCE.size() == STORY_ROUTE_TARGETS.size(), "Każdy profil fabularny musi wystąpić dokładnie raz w sekwencji certyfikacji.")
	var unique_story_profiles: Dictionary = {}
	for story_profile_id in STORY_PROFILE_SEQUENCE:
		_assert(not unique_story_profiles.has(story_profile_id), "Sekwencja fabularna nie może powtarzać profilu %s." % story_profile_id)
		unique_story_profiles[story_profile_id] = true
	var profile_target_counts: Dictionary = {}
	for target_value in STATIC_TARGET_CERTIFICATION_PROFILE.keys():
		var target_id := str(target_value)
		var profile_id := str(STATIC_TARGET_CERTIFICATION_PROFILE[target_value])
		_assert(not target_id.is_empty(), "Katalog profili certyfikacji nie może zawierać pustego target_id.")
		_assert(ALL_PROFILE_PATHS.has(profile_id), "Cel %s wskazuje nieznany profil %s." % [target_id, profile_id])
		profile_target_counts[profile_id] = int(profile_target_counts.get(profile_id, 0)) + 1
	for profile_value in ALL_PROFILE_PATHS.keys():
		var profile_id := str(profile_value)
		var profile_path := str(ALL_PROFILE_PATHS[profile_value])
		var profile = ResourceLoader.load(profile_path)
		_assert(profile != null and profile.is_valid(), "Profil pełnego katalogu musi być poprawny: %s." % profile_path)
		if profile == null:
			continue
		_assert(str(profile.profile_id) == profile_id, "Klucz profilu %s musi odpowiadać profile_id Resource." % profile_id)
		_assert(int(profile_target_counts.get(profile_id, 0)) > 0, "Każdy profil katalogu musi certyfikować co najmniej jeden cel: %s." % profile_id)
	for entry_profile_value in PROFILE_ENTRY_CONTRACTS:
		var entry_profile_id := str(entry_profile_value)
		var entry_profile = ResourceLoader.load(str(ALL_PROFILE_PATHS.get(entry_profile_id, "")))
		var entry_contract: Dictionary = PROFILE_ENTRY_CONTRACTS[entry_profile_value]
		_assert(entry_profile != null, "Kontrakt wejścia wskazuje brakujący profil %s." % entry_profile_id)
		if entry_profile == null:
			continue
		_assert(str(entry_profile.start_entry_point) == str(entry_contract.entry), "Profil %s musi zachować przypisane wejście certyfikacyjne." % entry_profile_id)
		_assert(entry_profile.placed_buoy_ids == entry_contract.buoys, "Profil %s musi zawierać dokładny narastający zestaw boi." % entry_profile_id)
	var standard = ResourceLoader.load("res://data/difficulty/standard.tres")
	var completed_story_devices: Array[String] = ["junction_j7"]
	for story_profile_id in STORY_PROFILE_SEQUENCE:
		_assert(STORY_ROUTE_TARGETS.has(story_profile_id), "Sekwencja fabularna wskazuje profil bez przypisanego celu: %s." % story_profile_id)
		var story_profile = ResourceLoader.load(str(ALL_PROFILE_PATHS.get(story_profile_id, "")))
		var scenario: Dictionary = ScenarioFactoryScript.new().build(story_profile, standard)
		var errors: PackedStringArray = scenario.get("errors", PackedStringArray())
		_assert(errors.is_empty(), "Profil sekwencji fabularnej %s musi przejść przez produkcyjny builder: %s" % [story_profile_id, str(errors)])
		if not errors.is_empty():
			continue
		var persistence_errors: Array[String] = []
		PersistenceValidatorScript._validate_story(persistence_errors, scenario.state, {})
		_assert(
			persistence_errors.is_empty(),
			"Profil sekwencji fabularnej %s musi mieć legalny typed story state oraz oś dni: %s"
			% [story_profile_id, str(persistence_errors)]
		)
		_assert(
			story_profile.activated_fixed_device_ids == completed_story_devices,
			"Profil %s musi zawierać dokładnie narastającą sekwencję wcześniejszych urządzeń." % story_profile_id
		)
		_assert(
			scenario.state.underwater_world.activated_fixed_devices == completed_story_devices,
			"Profil %s musi przenieść dokładną sekwencję wcześniejszych urządzeń do odłączonego WorldDelta." % story_profile_id
		)
		for target_id in STORY_ROUTE_TARGETS[story_profile_id]:
			_assert(str(STATIC_TARGET_CERTIFICATION_PROFILE.get(str(target_id), "")) == story_profile_id, "Cel fabularny %s musi należeć do własnego pełnego profilu." % str(target_id))
			_assert(str(target_id) not in completed_story_devices, "Bieżący cel fabularny %s nie może być ukończony przed certyfikowaną trasą." % str(target_id))
			completed_story_devices.append(str(target_id))
	var invalid_activated = ResourceLoader.load(str(ALL_PROFILE_PATHS["story_archive_main_line"])).duplicate(true)
	invalid_activated.profile_id = &"invalid_duplicate_activated_device"
	invalid_activated.activated_fixed_device_ids.assign(["junction_j7", "junction_j7"])
	_assert(
		not invalid_activated.is_valid() and _errors_contain(invalid_activated.validation_errors(), "activated_fixed_device_ids contains duplicate id junction_j7"),
		"Profil progresji musi odrzucać powielone wcześniejsze urządzenie."
	)


func _validate_complete_catalog_on_public_difficulty(difficulty_path: String) -> void:
	var difficulty = ResourceLoader.load(difficulty_path)
	var observed_assigned_ids: Dictionary = {}
	var enumerated_ids: Dictionary = {}
	var profile_ids: Array[String] = []
	profile_ids.assign(ALL_PROFILE_PATHS.keys())
	profile_ids.sort()
	for profile_id in profile_ids:
		var assigned_target_ids := _catalog_targets_for_profile(profile_id)
		if assigned_target_ids.is_empty():
			continue
		await _validate_catalog_profile_on_difficulty(
			profile_id,
			assigned_target_ids,
			difficulty,
			observed_assigned_ids,
			enumerated_ids
		)
	var expected_ids: Array[String] = []
	expected_ids.assign(STATIC_TARGET_CERTIFICATION_PROFILE.keys())
	expected_ids.sort()
	var observed_ids: Array[String] = []
	observed_ids.assign(observed_assigned_ids.keys())
	observed_ids.sort()
	_assert(observed_ids == expected_ids, "Macierz %s musi wykonać każde z 65 przypisań dokładnie raz." % str(difficulty.profile_id))
	if difficulty_path.ends_with("standard.tres"):
		var all_enumerated_ids: Array[String] = []
		all_enumerated_ids.assign(enumerated_ids.keys())
		all_enumerated_ids.sort()
		_assert(all_enumerated_ids == expected_ids, "Katalog 65 celów musi być pełny względem unii rzeczywistych snapshotów progresji.")


func _validate_catalog_profile_on_difficulty(
	profile_id: String,
	assigned_target_ids: Array[String],
	difficulty,
	observed_assigned_ids: Dictionary,
	enumerated_ids: Dictionary
) -> void:
	var profile = ResourceLoader.load(str(ALL_PROFILE_PATHS.get(profile_id, "")))
	var policy = ResourceLoader.load(POLICY_PATH)
	var scenario: Dictionary = ScenarioFactoryScript.new().build(profile, difficulty)
	var errors: PackedStringArray = scenario.get("errors", PackedStringArray())
	var profile_label := "%s × %s" % [profile_id, str(difficulty.profile_id)]
	_assert(errors.is_empty(), "Pełny profil %s musi powstać przez rzeczywisty builder: %s" % [profile_label, str(errors)])
	if not errors.is_empty():
		return
	var delta_before := _delta_projection(scenario.state.underwater_world.delta)
	var world = ContinuousWorldScript.new()
	world.set_snapshot_analysis_mode(true)
	world.configure(scenario.state.underwater_world, str(scenario.setup.start_entry_point), scenario.setup)
	root.add_child(world)
	await process_frame
	var snapshot = world.navigation_snapshot()
	_assert(snapshot != null and snapshot.is_valid(), "Pełny profil %s musi używać rzeczywistego snapshotu mapy." % profile_label)
	if snapshot == null or not snapshot.is_valid():
		world.queue_free()
		await process_frame
		return
	var threat_descriptors: Array[Dictionary] = snapshot.threat_descriptors()
	_assert(
		threat_descriptors.size() == 1 and str(threat_descriptors[0].get("id", "")) == "parking_noise_eel",
		"Każdy profil %s musi certyfikować trasę z aktywnym wdrożonym zagrożeniem." % profile_label
	)
	var descriptor_lookup: Dictionary = {}
	for descriptor in snapshot.target_descriptors():
		var descriptor_id := str(descriptor.get("id", ""))
		_assert(not descriptor_id.is_empty() and not descriptor_lookup.has(descriptor_id), "Snapshot %s musi publikować unikalne ID celów." % profile_label)
		if descriptor_id.is_empty() or descriptor_lookup.has(descriptor_id):
			continue
		descriptor_lookup[descriptor_id] = descriptor
		enumerated_ids[descriptor_id] = true
	var query_lookup: Dictionary = {}
	var query_ids: Dictionary = {}
	for query in _analyzer.queries_for_static_targets(snapshot):
		if query == null or query.target_ids.size() != 1:
			continue
		var query_target_id := str(query.target_ids[0])
		var query_id := str(query.query_id)
		_assert(not query_ids.has(query_id), "Profil %s nie może powtarzać query_id %s." % [profile_label, query_id])
		query_ids[query_id] = true
		var target_queries: Array = query_lookup.get(query_target_id, [])
		target_queries.append(query)
		query_lookup[query_target_id] = target_queries
	for target_id in assigned_target_ids:
		_assert(descriptor_lookup.has(target_id), "Przypisany cel %s musi istnieć w snapshotcie %s." % [target_id, profile_label])
		_assert(query_lookup.has(target_id), "Przypisany cel %s musi mieć publiczne zapytanie dla każdej gwarantowanej interakcji lub pary zasobowej w %s." % [target_id, profile_label])
		if not descriptor_lookup.has(target_id) or not query_lookup.has(target_id):
			continue
		var descriptor: Dictionary = descriptor_lookup[target_id]
		var target_queries: Array = query_lookup[target_id]
		_validate_generated_queries_for_descriptor(target_queries, descriptor, profile_label)
		for query in target_queries:
			var report = _analyzer.analyze_query(
				scenario.setup,
				snapshot,
				query,
				policy,
				profile.profile_id,
				difficulty.profile_id
			)
			var target_label := "%s [%s] @ %s" % [target_id, str(query.query_id), profile_label]
			_assert(report.feasible, "Cel katalogu musi być FEASIBLE: %s (%s)." % [target_label, str(report.reason_code)])
			_assert(report.safe, "Cel katalogu musi być SAFE: %s (%s)." % [target_label, str(report.reason_code)])
			_assert(report.reason_code == CertificateScript.OK_SAFE, "Pełny certyfikat %s musi kończyć się OK_SAFE." % target_label)
			_assert(report.certificates.size() == 1 and report.certificates[0].target_ids == [target_id], "Certyfikat %s musi zachować dokładnie swój cel." % target_label)
			_validate_certificate_design_output(report, scenario.setup, [descriptor], target_label)
			_validate_certified_query_amount(report, query, descriptor, target_label)
			if STORY_ROUTE_TARGETS.has(profile_id) and target_id in STORY_ROUTE_TARGETS[profile_id]:
				_assert(bool(query.require_full_targets), "Trasa fabularna %s musi certyfikować pełną interakcję i normalny powrót." % target_label)
		observed_assigned_ids[target_id] = true
	_assert(_delta_projection(scenario.state.underwater_world.delta) == delta_before, "Pełna macierz %s nie może mutować WorldDelta." % profile_label)
	_assert(scenario.state.current_expedition_setup == null and scenario.state.last_dive_result == null, "Pełna macierz %s nie może mutować GameState." % profile_label)
	world.queue_free()
	await process_frame


func _validate_generated_queries_for_descriptor(
	target_queries: Array,
	descriptor: Dictionary,
	profile_label: String
) -> void:
	var target_id := str(descriptor.get("id", ""))
	var contents := _normalized_descriptor_contents(descriptor)
	var requires_full := _descriptor_requires_full_query(descriptor)
	if contents.is_empty() or requires_full:
		_assert(target_queries.size() == 1, "Cel %s @ %s musi mieć dokładnie jedno zapytanie pełnej interakcji." % [target_id, profile_label])
		if target_queries.size() != 1:
			return
		var query = target_queries[0]
		_assert(str(query.query_id) == "target_%s" % target_id, "Pełne zapytanie celu %s musi mieć deterministyczne query_id." % target_id)
		_assert(str(query.resource_id).is_empty() and int(query.requested_amount) == 0, "Pełne zapytanie celu %s nie może udawać zapytania pojedynczego zasobu." % target_id)
		_assert(bool(query.require_full_targets) == requires_full, "Cel %s musi zachować kontrakt pełnego obiektu." % target_id)
		return

	var expected_resource_ids: Array[String] = []
	expected_resource_ids.assign(contents.keys())
	expected_resource_ids.sort()
	_assert(
		target_queries.size() == expected_resource_ids.size(),
		"Zwykły kontener %s @ %s musi mieć po jednym zapytaniu dla każdego z %d autorskich zasobów."
		% [target_id, profile_label, expected_resource_ids.size()]
	)
	var observed_resource_ids: Array[String] = []
	for query in target_queries:
		var resource_id := str(query.resource_id)
		_assert(not resource_id.is_empty() and contents.has(resource_id), "Zapytanie kontenera %s wskazuje nieautorski zasób %s." % [target_id, resource_id])
		_assert(not observed_resource_ids.has(resource_id), "Kontener %s nie może powtarzać certyfikatu zasobu %s." % [target_id, resource_id])
		observed_resource_ids.append(resource_id)
		_assert(str(query.query_id) == "target_%s_%s_max" % [target_id, resource_id], "Para %s + %s musi mieć deterministyczne query_id." % [target_id, resource_id])
		_assert(int(query.requested_amount) == 0 and not bool(query.require_full_targets), "Para %s + %s musi raportować bezpieczne maksimum zwykłego kontenera." % [target_id, resource_id])
	observed_resource_ids.sort()
	_assert(observed_resource_ids == expected_resource_ids, "Enumeracja kontenera %s musi pokrywać dokładnie wszystkie autorskie resource_id." % target_id)


func _validate_certified_query_amount(report, query, descriptor: Dictionary, target_label: String) -> void:
	if report.certificates.size() != 1:
		return
	var certificate = report.certificates[0]
	_assert(report.query_id == query.query_id and certificate.query_id == query.query_id, "Raport %s musi zachować tożsamość konkretnego źródła lub interakcji." % target_label)
	var contents := _normalized_descriptor_contents(descriptor)
	var resource_id := str(query.resource_id)
	if not resource_id.is_empty():
		var authored_amount := int(contents.get(resource_id, 0))
		var recovered_amount := int(certificate.recovered_items.get(resource_id, 0))
		_assert(report.requested_resource_id == resource_id and int(report.requested_amount) == 0, "Raport %s musi jednoznacznie wskazywać resource_id źródła i tryb bezpiecznego maksimum." % target_label)
		_assert(authored_amount > 0, "Certyfikat %s musi wskazywać dodatnią autorską ilość źródłową." % target_label)
		_assert(recovered_amount >= 1 and recovered_amount <= authored_amount, "Certyfikat %s musi bezpiecznie odzyskać co najmniej jedną sztukę z własnego źródła." % target_label)
		_assert(int(report.recovered_amount) == recovered_amount, "Raport %s musi podawać odzyskaną ilość dla wskazanej pary źródło + zasób." % target_label)
		_assert(int(certificate.maximum_recoverable_amount) == recovered_amount, "Raport %s musi podawać bezpieczne maksimum wybranej pary źródło + zasób." % target_label)
		return
	if not bool(query.require_full_targets):
		return
	for authored_resource_id in contents.keys():
		_assert(
			int(certificate.recovered_items.get(str(authored_resource_id), 0)) == int(contents[authored_resource_id]),
			"Pełny certyfikat %s musi odzyskać cały autorski manifest zasobu %s." % [target_label, str(authored_resource_id)]
		)


func _validate_certificate_design_output(
	report,
	setup,
	descriptors: Array,
	target_label: String
) -> void:
	if report.certificates.size() != 1:
		return
	var certificate = report.certificates[0]
	_assert(certificate.entry_id == str(setup.start_entry_point), "Wynik %s musi podawać faktyczne aktywne wejście." % target_label)
	for descriptor_value in descriptors:
		var descriptor: Dictionary = descriptor_value
		var target_id := str(descriptor.get("id", ""))
		_assert(certificate.target_positions.has(target_id), "Wynik %s musi podawać pozycję celu %s." % [target_label, target_id])
		_assert(Vector2(certificate.target_positions.get(target_id, Vector2.ZERO)).is_equal_approx(descriptor.get("position", Vector2.ZERO)), "Pozycja celu %s w wyniku %s musi pochodzić ze snapshotu." % [target_id, target_label])
	_assert(not certificate.route.is_empty(), "Wynik %s musi zawierać pełną trasę wyprawy." % target_label)
	_assert(float(certificate.oxygen_required) > 0.0, "Wynik %s musi podawać dodatni wymagany tlen." % target_label)
	_assert(is_equal_approx(float(certificate.oxygen_required) + float(certificate.oxygen_remaining), float(setup.oxygen_capacity)), "Wynik %s musi bilansować tlen wymagany i pozostały do pojemności butli." % target_label)
	var expected_mass := 0.0
	for resource_value in certificate.recovered_items.keys():
		var resource_id := str(resource_value)
		expected_mass += float(certificate.recovered_items[resource_value]) * maxf(float(setup.item_weights.get(resource_id, 1.0)), 0.01)
	_assert(is_equal_approx(float(certificate.cargo_mass), expected_mass), "Wynik %s musi podawać rzeczywisty ciężar odzyskanego ładunku." % target_label)
	_assert(int(certificate.cargo_slots) == certificate.recovered_items.size(), "Wynik %s musi podawać liczbę zajętych slotów ładunku." % target_label)
	_assert(float(certificate.threat_exposure_seconds) >= 0.0, "Wynik %s musi podawać nieujemną ekspozycję na przeciwników." % target_label)
	var serialized: Dictionary = report.to_dictionary()
	_assert(int(serialized.get("required_trip_count", 0)) == 1, "Wynik %s musi podawać liczbę wymaganych wypraw." % target_label)
	var serialized_certificates: Array = serialized.get("certificates", [])
	_assert(serialized_certificates.size() == 1, "Wynik JSON %s musi zawierać dokładnie jeden certyfikat." % target_label)
	if serialized_certificates.size() != 1:
		return
	var serialized_certificate: Dictionary = serialized_certificates[0]
	for required_key in [
		"entry_id",
		"target_positions",
		"route",
		"oxygen_required",
		"oxygen_remaining",
		"oxygen_reserve_ratio",
		"cargo_mass",
		"cargo_slots",
		"maximum_recoverable_amount",
		"threat_exposure_seconds",
		"reason_code",
		"reason_detail",
	]:
		_assert(serialized_certificate.has(required_key), "Wynik JSON %s musi zawierać pole %s." % [target_label, required_key])
	_assert((serialized_certificate.get("route", []) as Array).size() == certificate.route.size(), "Domyślna serializacja wyniku %s nie może pomijać trasy." % target_label)


func _normalized_descriptor_contents(descriptor: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var raw_contents: Dictionary = descriptor.get("contents", {})
	for resource_value in raw_contents.keys():
		result[str(resource_value)] = int(raw_contents[resource_value])
	return result


func _descriptor_requires_full_query(descriptor: Dictionary) -> bool:
	return (
		bool(descriptor.get("full_pickup", false))
		or bool(descriptor.get("mandatory", false))
		or bool(descriptor.get("story", false))
		or str(descriptor.get("kind", "")) in ["pickup", "rescue", "persistent_objective"]
	)


func _expected_static_query_ids_for_descriptor(descriptor: Dictionary) -> Array[String]:
	var target_id := str(descriptor.get("id", ""))
	var contents := _normalized_descriptor_contents(descriptor)
	if contents.is_empty() or _descriptor_requires_full_query(descriptor):
		return ["target_%s" % target_id]
	var resource_ids: Array[String] = []
	resource_ids.assign(contents.keys())
	resource_ids.sort()
	var result: Array[String] = []
	for resource_id in resource_ids:
		result.append("target_%s_%s_max" % [target_id, resource_id])
	return result


func _catalog_targets_for_profile(profile_id: String) -> Array[String]:
	var result: Array[String] = []
	for target_value in STATIC_TARGET_CERTIFICATION_PROFILE.keys():
		if str(STATIC_TARGET_CERTIFICATION_PROFILE[target_value]) == profile_id:
			result.append(str(target_value))
	result.sort()
	return result


func _validate_assignment_table_contract() -> void:
	_assert(PROVEN_EARLIEST_ASSIGNMENTS.size() == PROFILE_PATHS.size(), "Każdy publiczny checkpoint musi mieć dokładnie jedno udowodnione przypisanie najwcześniejszego celu.")
	var profile_paths: Dictionary = {}
	var query_paths: Dictionary = {}
	var target_ids: Dictionary = {}
	for assignment_index in range(PROVEN_EARLIEST_ASSIGNMENTS.size()):
		var assignment: Dictionary = PROVEN_EARLIEST_ASSIGNMENTS[assignment_index]
		var profile_path := str(assignment.get("profile_path", ""))
		var query_path := str(assignment.get("query_path", ""))
		var target_id := str(assignment.get("target_id", ""))
		var profile = ResourceLoader.load(profile_path)
		_assert(profile_path == PROFILE_PATHS[assignment_index], "Tabela przypisań musi zachować zatwierdzoną kolejność najwcześniejszych profili.")
		_assert(not profile_path.is_empty() and not profile_paths.has(profile_path), "Profil checkpointu musi wystąpić w tabeli dokładnie raz.")
		_assert(not query_path.is_empty() and not query_paths.has(query_path), "Zapytanie checkpointu musi wystąpić w tabeli dokładnie raz.")
		_assert(not target_id.is_empty() and not target_ids.has(target_id), "Cel checkpointu musi wystąpić w tabeli dokładnie raz.")
		_assert(profile != null, "Udowodnione przypisanie najwcześniejszego celu %s musi wskazywać istniejący profil." % target_id)
		_assert(STATIC_TARGET_CERTIFICATION_PROFILE.has(target_id), "Udowodniony najwcześniejszy cel %s musi należeć także do pełnego katalogu legalnych etapów certyfikacji." % target_id)
		profile_paths[profile_path] = true
		query_paths[query_path] = true
		target_ids[target_id] = true
		var earlier_reason_codes: Array = assignment.get("earlier_reason_codes", [])
		_assert(earlier_reason_codes.size() == assignment_index, "Przypisanie musi podać stabilny kod odrzucenia dla każdego wcześniejszego profilu.")
		for reason_code in earlier_reason_codes:
			_assert(not str(reason_code).is_empty(), "Kod odrzucenia wcześniejszego profilu nie może być pusty.")


func _validate_assignment_on_public_difficulty(
	assignment: Dictionary,
	assignment_index: int,
	difficulty_path: String,
	run_extended_contracts: bool,
	run_static_query_coverage: bool
) -> void:
	var profile = ResourceLoader.load(str(assignment.get("profile_path", "")))
	var difficulty = ResourceLoader.load(difficulty_path)
	var policy = ResourceLoader.load(POLICY_PATH)
	var query = ResourceLoader.load(str(assignment.get("query_path", "")))
	var scenario: Dictionary = ScenarioFactoryScript.new().build(profile, difficulty)
	var errors: PackedStringArray = scenario.get("errors", PackedStringArray())
	_assert(errors.is_empty(), "Publiczny preset musi zbudować legalny scenariusz certyfikacji: %s" % str(errors))
	if not errors.is_empty():
		return
	var delta_before := _delta_projection(scenario.state.underwater_world.delta)
	var world = ContinuousWorldScript.new()
	world.set_snapshot_analysis_mode(true)
	world.configure(scenario.state.underwater_world, str(scenario.setup.start_entry_point), scenario.setup)
	root.add_child(world)
	await process_frame
	var snapshot = world.navigation_snapshot()
	_assert(snapshot != null and snapshot.is_valid(), "Certyfikat musi używać rzeczywistego snapshotu kolizji świata.")
	if snapshot == null or not snapshot.is_valid():
		world.queue_free()
		await process_frame
		return

	var analyzer = _analyzer
	if run_static_query_coverage:
		_validate_static_query_coverage(analyzer, snapshot)
	_validate_assignment_query_contract(analyzer, snapshot, query, str(assignment.get("target_id", "")))
	var report = analyzer.analyze_query(
		scenario.setup,
		snapshot,
		query,
		policy,
		profile.profile_id,
		difficulty.profile_id
	)
	var assignment_label := "%s × %s" % [str(profile.profile_id), str(difficulty.profile_id)]
	_assert(report.profile_id == profile.profile_id and report.difficulty_profile_id == difficulty.profile_id, "Raport musi zachować przypisanie profilu i presetu %s." % assignment_label)
	_assert(report.feasible, "Krytyczny cel musi być FEASIBLE dla %s: %s" % [assignment_label, str(report.reason_code)])
	_assert(report.safe, "Krytyczny cel musi być SAFE dla %s: %s" % [assignment_label, str(report.reason_code)])
	_assert(report.reason_code == CertificateScript.OK_SAFE, "Publiczny certyfikat SAFE musi mieć stabilny reason code OK_SAFE.")
	_assert(
		report.certificates.size() == 1
		and report.certificates[0].target_ids == [str(assignment.get("target_id", ""))]
		and report.certificates[0].profile_id == profile.profile_id
		and report.certificates[0].difficulty_profile_id == difficulty.profile_id,
		"Certyfikat musi wskazać konkretny cel oraz przypisanie %s." % assignment_label
	)
	_assert(_delta_projection(scenario.state.underwater_world.delta) == delta_before, "Analizator nie może mutować WorldDelta.")
	_assert(scenario.state.current_expedition_setup == null and scenario.state.last_dive_result == null, "Analizator nie może mutować GameState ani tworzyć DiveResult.")

	for future_assignment_index in range(assignment_index + 1, PROVEN_EARLIEST_ASSIGNMENTS.size()):
		var future_assignment: Dictionary = PROVEN_EARLIEST_ASSIGNMENTS[future_assignment_index]
		var future_query = ResourceLoader.load(str(future_assignment.get("query_path", "")))
		var premature = analyzer.analyze_query(
			scenario.setup,
			snapshot,
			future_query,
			policy,
			profile.profile_id,
			difficulty.profile_id
		)
		var earlier_reason_codes: Array = future_assignment.get("earlier_reason_codes", [])
		var expected_reason_code := str(earlier_reason_codes[assignment_index]) if assignment_index < earlier_reason_codes.size() else ""
		_assert(
			not premature.feasible
			and str(premature.reason_code) == expected_reason_code,
			"Przypisanie %s musi być najwcześniejszym legalnym checkpointem; wcześniejszy profil %s zwrócił %s zamiast %s."
			% [str(future_assignment.get("target_id", "")), str(profile.profile_id), str(premature.reason_code), expected_reason_code]
		)

	if run_extended_contracts and report.certificates.size() == 1:
		var strict_policy = policy.duplicate(true)
		strict_policy.maximum_cold_exposure = 0.0
		var strict_report = analyzer.analyze_query(
			scenario.setup,
			snapshot,
			query,
			strict_policy,
			profile.profile_id,
			difficulty.profile_id
		)
		_assert(strict_report.feasible and not strict_report.safe, "FEASIBLE i SAFE muszą być niezależnymi wynikami polityki rezerwy.")
		_assert(strict_report.reason_code == CertificateScript.OK_FEASIBLE_RESERVE_SHORTFALL, "Brak rezerwy musi mieć stabilny reason code.")

		var missing_query = QueryScript.new()
		missing_query.query_id = &"missing_target"
		missing_query.target_ids.assign(["missing_static_target"])
		var missing_report = analyzer.analyze_query(
			scenario.setup,
			snapshot,
			missing_query,
			policy,
			profile.profile_id,
			difficulty.profile_id
		)
		_assert(not missing_report.feasible and missing_report.reason_code == CertificateScript.TARGET_NOT_FOUND, "Brak celu musi zwracać stabilny reason code TARGET_NOT_FOUND.")

		var repeated_report = analyzer.analyze_query(
			scenario.setup,
			snapshot,
			query,
			policy,
			profile.profile_id,
			difficulty.profile_id
		)
		_assert(_same_certificate(report.certificates[0], repeated_report.certificates[0]), "Fixed-step replay musi być deterministyczny dla identycznego wejścia.")

	world.queue_free()
	await process_frame


func _validate_static_query_coverage(analyzer, snapshot) -> void:
	var required_target_ids: Array[String] = []
	var descriptor_ids: Dictionary = {}
	var expected_query_ids: Dictionary = {}
	var expected_resource_pair_count := 0
	var expected_full_interaction_count := 0
	for descriptor in snapshot.target_descriptors():
		var target_id := str(descriptor.get("id", ""))
		_assert(not target_id.is_empty(), "Każdy statyczny cel musi mieć stabilne ID.")
		_assert(not descriptor_ids.has(target_id), "Statyczny cel nie może powtarzać ID %s." % target_id)
		if target_id.is_empty() or descriptor_ids.has(target_id):
			continue
		descriptor_ids[target_id] = true
		_enumerated_static_target_ids[target_id] = true
		required_target_ids.append(target_id)
		var descriptor_query_ids := _expected_static_query_ids_for_descriptor(descriptor)
		var contents := _normalized_descriptor_contents(descriptor)
		if contents.is_empty() or _descriptor_requires_full_query(descriptor):
			expected_full_interaction_count += 1
		else:
			expected_resource_pair_count += contents.size()
		for query_id in descriptor_query_ids:
			_assert(not expected_query_ids.has(query_id), "Oczekiwane zapytania statyczne nie mogą powtarzać query_id %s." % query_id)
			expected_query_ids[query_id] = true
	_assert(
		expected_query_ids.size() == expected_resource_pair_count + expected_full_interaction_count,
		"Każdy snapshot musi wewnętrznie bilansować pary zasobowe i pełne interakcje."
	)
	var queries: Array[Resource] = analyzer.queries_for_static_targets(snapshot)
	_assert(queries.size() == expected_query_ids.size(), "Generator musi zwrócić pełną enumerację interakcji oraz każdej pary zwykły kontener + resource_id.")
	var covered_target_ids: Dictionary = {}
	var query_ids: Dictionary = {}
	var observed_resource_pair_count := 0
	var observed_full_interaction_count := 0
	for query in queries:
		_assert(query != null and query.is_valid(), "Każde wygenerowane zapytanie celu statycznego musi być poprawne.")
		if query == null:
			continue
		var query_id := str(query.query_id)
		if str(query.resource_id).is_empty():
			observed_full_interaction_count += 1
		else:
			observed_resource_pair_count += 1
		_assert(not query_ids.has(query_id), "Zapytania statyczne nie mogą powtarzać query_id %s." % query_id)
		_assert(expected_query_ids.has(query_id), "Generator zwrócił nieoczekiwane zapytanie statyczne %s." % query_id)
		query_ids[query_id] = true
		_assert(query.target_ids.size() == 1, "Zapytanie statyczne musi wskazywać dokładnie jeden cel.")
		if query.target_ids.size() != 1:
			continue
		var target_id := str(query.target_ids[0])
		covered_target_ids[target_id] = true
	_assert(observed_resource_pair_count == expected_resource_pair_count, "Analyzer musi zachować lokalną liczbę par zwykły kontener + resource_id.")
	_assert(observed_full_interaction_count == expected_full_interaction_count, "Analyzer musi zachować lokalną liczbę pełnych interakcji.")
	_assert(observed_resource_pair_count + observed_full_interaction_count == queries.size(), "Analyzer musi zbilansować lokalny katalog zapytań snapshotu.")
	required_target_ids.sort()
	var covered_target_values: Array[String] = []
	covered_target_values.assign(covered_target_ids.keys())
	covered_target_values.sort()
	_assert(covered_target_values == required_target_ids, "Enumeracja musi być kompletna względem rzeczywistego snapshotu celów.")
	var expected_query_values: Array[String] = []
	expected_query_values.assign(expected_query_ids.keys())
	expected_query_values.sort()
	var observed_query_values: Array[String] = []
	observed_query_values.assign(query_ids.keys())
	observed_query_values.sort()
	_assert(observed_query_values == expected_query_values, "Enumeracja musi być kompletna względem każdego autorskiego resource_id w zwykłych kontenerach.")


func _validate_assignment_query_contract(analyzer, snapshot, assigned_query, expected_target_id: String) -> void:
	_assert(assigned_query != null and assigned_query.is_valid(), "Przypisanie musi wskazywać poprawny publiczny Resource zapytania.")
	if assigned_query == null or not assigned_query.is_valid():
		return
	_assert(assigned_query.target_ids == [expected_target_id], "Przypisane zapytanie musi wskazywać dokładnie deklarowany cel checkpointu.")
	var matching_queries: Array[Resource] = []
	for generated_query in analyzer.queries_for_static_targets(snapshot):
		if generated_query.target_ids == [expected_target_id] and _queries_match_contract(assigned_query, generated_query):
			matching_queries.append(generated_query)
	_assert(matching_queries.size() == 1, "Cel %s musi mieć dokładnie jedno deterministyczne zapytanie statyczne odpowiadające publicznemu Resource." % expected_target_id)
	if matching_queries.size() != 1:
		return
	var generated_query: Resource = matching_queries[0]
	_assert(
		_queries_match_contract(assigned_query, generated_query),
		"Publiczny Resource zapytania %s musi odpowiadać kontraktowi queries_for_static_targets()." % expected_target_id
	)


func _queries_match_contract(left, right) -> bool:
	return (
		left != null
		and right != null
		and left.query_id == right.query_id
		and left.target_ids == right.target_ids
		and str(left.resource_id) == str(right.resource_id)
		and int(left.requested_amount) == int(right.requested_amount)
		and left.normalized_requested_manifest() == right.normalized_requested_manifest()
		and int(left.trip_mode) == int(right.trip_mode)
		and bool(left.allow_combining_sources) == bool(right.allow_combining_sources)
		and bool(left.require_full_targets) == bool(right.require_full_targets)
	)


func _validate_assignment_enumeration_coverage() -> void:
	for assignment in PROVEN_EARLIEST_ASSIGNMENTS:
		var target_id := str(assignment.get("target_id", ""))
		_assert(_enumerated_static_target_ids.has(target_id), "Przypisany cel %s musi należeć do kompletnej enumeracji statycznej." % target_id)


func _validate_profile_dag_contract(require_complete_expected: bool = true) -> void:
	var expected_profile_ids := _sorted_string_values(ALL_PROFILE_PATHS.keys())
	var dag_profile_ids := _sorted_string_values(PROFILE_PREDECESSORS.keys())
	_assert(
		dag_profile_ids == expected_profile_ids,
		"DAG najwcześniejszych profili musi zawierać dokładnie wszystkie 14 publicznych profili."
	)
	var roots: Array[String] = []
	for profile_id in dag_profile_ids:
		var predecessor_values = PROFILE_PREDECESSORS.get(profile_id, null)
		_assert(predecessor_values is Array, "Poprzednicy profilu %s muszą być tablicą." % profile_id)
		if not predecessor_values is Array:
			continue
		var predecessors: Array = predecessor_values
		if predecessors.is_empty():
			roots.append(profile_id)
		var unique_predecessors: Dictionary = {}
		for predecessor_value in predecessors:
			var predecessor_id := str(predecessor_value)
			_assert(ALL_PROFILE_PATHS.has(predecessor_id), "Profil %s wskazuje nieznanego poprzednika %s." % [profile_id, predecessor_id])
			_assert(predecessor_id != profile_id, "Profil %s nie może być własnym poprzednikiem." % profile_id)
			_assert(not unique_predecessors.has(predecessor_id), "Profil %s powtarza poprzednika %s." % [profile_id, predecessor_id])
			unique_predecessors[predecessor_id] = true
	roots.sort()
	_assert(roots == ["tank_i_station_i"], "DAG profili musi mieć dokładnie jeden korzeń tank_i_station_i.")
	var topological_order := _profile_topological_order()
	_assert(
		topological_order.size() == expected_profile_ids.size(),
		"DAG 14 profili musi być acykliczny i każdy profil musi być osiągalny od tank_i_station_i."
	)
	for profile_id in expected_profile_ids:
		_assert(
			profile_id == "tank_i_station_i" or _profile_ancestor_ids(profile_id).has("tank_i_station_i"),
			"Profil %s musi być osiągalny od jedynego korzenia DAG." % profile_id
		)
	_validate_expected_earliest_profile_contract(require_complete_expected)


func _profile_topological_order() -> Array[String]:
	var profile_ids := _sorted_string_values(PROFILE_PREDECESSORS.keys())
	var indegree: Dictionary = {}
	var children: Dictionary = {}
	for profile_id in profile_ids:
		var predecessors: Array = PROFILE_PREDECESSORS.get(profile_id, [])
		indegree[profile_id] = predecessors.size()
		children[profile_id] = []
	for profile_id in profile_ids:
		var predecessors: Array = PROFILE_PREDECESSORS.get(profile_id, [])
		for predecessor_value in predecessors:
			var predecessor_id := str(predecessor_value)
			if not children.has(predecessor_id):
				continue
			var predecessor_children: Array = children[predecessor_id]
			predecessor_children.append(profile_id)
			children[predecessor_id] = predecessor_children
	var ready: Array[String] = []
	for profile_id in profile_ids:
		if int(indegree.get(profile_id, 0)) == 0:
			ready.append(profile_id)
	ready.sort()
	var result: Array[String] = []
	while not ready.is_empty():
		var profile_id := str(ready.pop_front())
		result.append(profile_id)
		var profile_children: Array = children.get(profile_id, [])
		profile_children.sort()
		for child_value in profile_children:
			var child_id := str(child_value)
			indegree[child_id] = int(indegree.get(child_id, 0)) - 1
			if int(indegree[child_id]) == 0:
				ready.append(child_id)
		ready.sort()
	return result


func _profile_ancestor_ids(profile_id: String) -> Dictionary:
	var result: Dictionary = {}
	var pending: Array[String] = []
	for predecessor_value in (PROFILE_PREDECESSORS.get(profile_id, []) as Array):
		pending.append(str(predecessor_value))
	while not pending.is_empty():
		var ancestor_id := str(pending.pop_back())
		if result.has(ancestor_id):
			continue
		result[ancestor_id] = true
		for predecessor_value in (PROFILE_PREDECESSORS.get(ancestor_id, []) as Array):
			pending.append(str(predecessor_value))
	return result


func _validate_expected_earliest_profile_contract(require_complete_expected: bool = true) -> void:
	if EXPECTED_EARLIEST_PROFILES.is_empty():
		return
	if require_complete_expected:
		_assert(
			EXPECTED_EARLIEST_PROFILES.size() == STATIC_QUERY_COUNT,
			"EXPECTED_EARLIEST_PROFILES musi deklarować dokładnie 138 query_id katalogu."
		)
	for query_id in _sorted_string_values(EXPECTED_EARLIEST_PROFILES.keys()):
		_assert(not query_id.is_empty(), "Jawny kontrakt najwcześniejszych profili nie może zawierać pustego query_id.")
		var profile_values = EXPECTED_EARLIEST_PROFILES.get(query_id, null)
		_assert(profile_values is Array, "Najwcześniejsze profile query %s muszą być tablicą." % query_id)
		if not profile_values is Array:
			continue
		var profile_ids := _sorted_string_values(profile_values)
		_assert(not profile_ids.is_empty(), "Query %s musi mieć co najmniej jeden najwcześniejszy profil." % query_id)
		_assert(profile_ids.size() == profile_values.size(), "Query %s nie może powtarzać najwcześniejszego profilu." % query_id)
		for profile_id in profile_ids:
			_assert(ALL_PROFILE_PATHS.has(profile_id), "Query %s wskazuje nieznany najwcześniejszy profil %s." % [query_id, profile_id])
		for left_index in range(profile_ids.size()):
			for right_index in range(left_index + 1, profile_ids.size()):
				var left_profile := profile_ids[left_index]
				var right_profile := profile_ids[right_index]
				_assert(
					not _profile_ancestor_ids(left_profile).has(right_profile)
					and not _profile_ancestor_ids(right_profile).has(left_profile),
					"Wielokrotne minima query %s muszą należeć do nieporównywalnych gałęzi DAG: %s, %s."
					% [query_id, left_profile, right_profile]
				)


func _validate_earliest_profile_frontier(shard: Dictionary = {}) -> void:
	var profile_order := _profile_topological_order()
	if profile_order.size() != ALL_PROFILE_PATHS.size():
		_assert(false, "Nie można uruchomić frontieru na niepoprawnym DAG profili.")
		return
	var frontier_mode := (
		"shard-%d-of-%d" % [int(shard.get("index", 0)) + 1, int(shard.get("count", 1))]
		if bool(shard.get("enabled", false))
		else "complete"
	)
	print(
		"DIVE_RECOVERY_FRONTIER START mode=%s profiles=%d"
		% [frontier_mode, profile_order.size()]
	)
	var safe_profiles_by_query: Dictionary = {}
	var frontier_evidence: Dictionary = {}
	var union_target_ids: Dictionary = {}
	var union_queries: Dictionary = {}
	var standard_difficulty_path := "res://data/difficulty/standard.tres"
	var standard_cases_by_profile: Dictionary = {}
	for profile_index in range(profile_order.size()):
		var profile_id: String = profile_order[profile_index]
		print(
			"DIVE_RECOVERY_FRONTIER BUILD phase=union profile=%s difficulty=standard ordinal=%d/%d"
			% [profile_id, profile_index + 1, profile_order.size()]
		)
		var standard_case: Dictionary = await _build_earliest_profile_case(
			profile_id,
			standard_difficulty_path
		)
		standard_cases_by_profile[profile_id] = standard_case
		_accumulate_snapshot_union(standard_case, union_target_ids, union_queries)
	_validate_snapshot_union_contract(union_target_ids, union_queries)
	var all_query_ids := _sorted_string_values(union_queries.keys())
	var selected_query_ids := _sharded_query_ids(all_query_ids, shard)
	var selected_query_lookup: Dictionary = {}
	for query_id in selected_query_ids:
		selected_query_lookup[query_id] = true
	print(
		"DIVE_RECOVERY_FRONTIER CATALOG mode=%s total_queries=%d selected_queries=%d"
		% [frontier_mode, all_query_ids.size(), selected_query_ids.size()]
	)
	var replayed_candidate_count := 0

	for profile_index in range(profile_order.size()):
		var profile_id: String = profile_order[profile_index]
		print(
			"DIVE_RECOVERY_FRONTIER PROFILE_BEGIN profile=%s ordinal=%d/%d"
			% [profile_id, profile_index + 1, profile_order.size()]
		)
		var profile_cases: Array[Dictionary] = []
		for difficulty_path in DIFFICULTY_PATHS:
			var profile_case: Dictionary
			if difficulty_path == standard_difficulty_path:
				profile_case = standard_cases_by_profile.get(profile_id, {})
			else:
				print(
					"DIVE_RECOVERY_FRONTIER BUILD phase=replay profile=%s difficulty=%s"
					% [profile_id, str(difficulty_path).get_file().get_basename()]
				)
				profile_case = await _build_earliest_profile_case(profile_id, difficulty_path)
			profile_cases.append(profile_case)
			_accumulate_snapshot_union(profile_case, union_target_ids, union_queries)
		for query_id in _profile_case_query_ids(profile_cases):
			if not selected_query_lookup.has(query_id):
				continue
			var safe_profiles: Array = safe_profiles_by_query.get(query_id, [])
			if _has_safe_profile_ancestor(profile_id, safe_profiles):
				continue
			var preflight_result := _preflight_earliest_candidate(profile_cases, query_id)
			if not bool(preflight_result.get("valid", false)):
				print(
					"DIVE_RECOVERY_FRONTIER PREFLIGHT_SKIP profile=%s query=%s reason=%s"
					% [profile_id, query_id, str(preflight_result.get("reason_code", ""))]
				)
				_record_frontier_evidence(frontier_evidence, query_id, profile_id, preflight_result)
				continue
			replayed_candidate_count += 1
			print(
				"DIVE_RECOVERY_FRONTIER REPLAY_BEGIN ordinal=%d profile=%s query=%s difficulties=%d"
				% [replayed_candidate_count, profile_id, query_id, DIFFICULTY_PATHS.size()]
			)
			var replay_result := _replay_earliest_candidate(profile_cases, query_id)
			print(
				"DIVE_RECOVERY_FRONTIER REPLAY_END ordinal=%d profile=%s query=%s safe=%s reason=%s"
				% [
					replayed_candidate_count,
					profile_id,
					query_id,
					str(bool(replay_result.get("safe", false))),
					str(replay_result.get("reason_code", "")),
				]
			)
			_record_frontier_evidence(frontier_evidence, query_id, profile_id, replay_result)
			if bool(replay_result.get("safe", false)):
				safe_profiles.append(profile_id)
				safe_profiles_by_query[query_id] = safe_profiles
		_validate_earliest_cases_are_detached(profile_cases, profile_id)
		print(
			"DIVE_RECOVERY_FRONTIER PROFILE_END profile=%s ordinal=%d/%d"
			% [profile_id, profile_index + 1, profile_order.size()]
		)

	_validate_snapshot_union_contract(union_target_ids, union_queries)
	var actual_earliest_profiles: Dictionary = {}
	for query_id in selected_query_ids:
		var safe_profiles := _sorted_string_values(safe_profiles_by_query.get(query_id, []))
		actual_earliest_profiles[query_id] = safe_profiles
		_assert(
			not safe_profiles.is_empty(),
			"Brak profilu SAFE dla query %s. Dowody frontieru: %s"
			% [query_id, str(frontier_evidence.get(query_id, {}))]
		)
	print(
		"DIVE_RECOVERY_FRONTIER DISCOVERY_END mode=%s selected_queries=%d replayed_candidates=%d"
		% [frontier_mode, selected_query_ids.size(), replayed_candidate_count]
	)
	_validate_or_report_earliest_profiles(
		actual_earliest_profiles,
		union_queries,
		selected_query_ids,
		shard
	)


func _sharded_query_ids(all_query_ids: Array[String], shard: Dictionary) -> Array[String]:
	_assert(
		all_query_ids.size() == STATIC_QUERY_COUNT,
		"Sharding earliest wymaga pełnej, posortowanej unii 138 query_id."
	)
	if not bool(shard.get("enabled", false)):
		return all_query_ids.duplicate()
	var shard_count := int(shard.get("count", 0))
	var shard_index := int(shard.get("index", -1))
	var result: Array[String] = []
	for query_index in range(all_query_ids.size()):
		if query_index % shard_count == shard_index:
			result.append(all_query_ids[query_index])
	var expected_size := int(all_query_ids.size() / shard_count)
	if shard_index < all_query_ids.size() % shard_count:
		expected_size += 1
	_assert(
		result.size() == expected_size and not result.is_empty(),
		"Shard %d/%d musi deterministycznie otrzymać oczekiwaną niepustą część katalogu."
		% [shard_index, shard_count]
	)
	return result


func _build_earliest_profile_case(profile_id: String, difficulty_path: String) -> Dictionary:
	var profile = ResourceLoader.load(str(ALL_PROFILE_PATHS.get(profile_id, "")))
	var difficulty = ResourceLoader.load(difficulty_path)
	_assert(profile != null and profile.is_valid(), "Frontier wymaga poprawnego profilu %s." % profile_id)
	_assert(difficulty != null and difficulty.is_valid(), "Frontier wymaga poprawnego presetu %s." % difficulty_path)
	if profile == null or difficulty == null or not profile.is_valid() or not difficulty.is_valid():
		return {"valid": false, "profile_id": profile_id, "difficulty_path": difficulty_path}
	var scenario: Dictionary = ScenarioFactoryScript.new().build(profile, difficulty)
	var errors: PackedStringArray = scenario.get("errors", PackedStringArray())
	var case_label := "%s × %s" % [profile_id, str(difficulty.profile_id)]
	_assert(errors.is_empty(), "Frontier profilu %s musi powstać przez produkcyjny builder: %s" % [case_label, str(errors)])
	if not errors.is_empty():
		return {"valid": false, "profile_id": profile_id, "difficulty_path": difficulty_path}
	var delta_before := _delta_projection(scenario.state.underwater_world.delta)
	var world = ContinuousWorldScript.new()
	world.set_snapshot_analysis_mode(true)
	world.configure(scenario.state.underwater_world, str(scenario.setup.start_entry_point), scenario.setup)
	root.add_child(world)
	await process_frame
	var snapshot = world.navigation_snapshot()
	_assert(snapshot != null and snapshot.is_valid(), "Frontier %s musi używać rzeczywistego snapshotu mapy." % case_label)
	var queries: Array[Resource] = []
	var queries_by_id: Dictionary = {}
	var queries_by_target: Dictionary = {}
	if snapshot != null and snapshot.is_valid():
		queries = _analyzer.queries_for_static_targets(snapshot)
		for query in queries:
			if query == null or query.target_ids.size() != 1:
				continue
			queries_by_id[str(query.query_id)] = query
			var target_id := str(query.target_ids[0])
			var target_queries: Array = queries_by_target.get(target_id, [])
			target_queries.append(query)
			queries_by_target[target_id] = target_queries
	world.queue_free()
	await process_frame
	if snapshot == null or not snapshot.is_valid():
		return {"valid": false, "profile_id": profile_id, "difficulty_path": difficulty_path}
	return {
		"valid": true,
		"profile": profile,
		"difficulty": difficulty,
		"scenario": scenario,
		"snapshot": snapshot,
		"queries": queries,
		"queries_by_id": queries_by_id,
		"queries_by_target": queries_by_target,
		"delta_before": delta_before,
	}


func _accumulate_snapshot_union(
	profile_case: Dictionary,
	union_target_ids: Dictionary,
	union_queries: Dictionary
) -> void:
	if not bool(profile_case.get("valid", false)):
		return
	var snapshot = profile_case.get("snapshot", null)
	for descriptor in snapshot.target_descriptors():
		var target_id := str(descriptor.get("id", ""))
		_assert(not target_id.is_empty(), "Unia snapshotów nie może zawierać celu bez ID.")
		if not target_id.is_empty():
			union_target_ids[target_id] = true
	var queries: Array = profile_case.get("queries", [])
	for query in queries:
		_assert(query != null and query.is_valid(), "Unia snapshotów może zawierać tylko poprawne zapytania.")
		if query == null or not query.is_valid():
			continue
		var query_id := str(query.query_id)
		if union_queries.has(query_id):
			_assert(
				_queries_match_contract(union_queries[query_id], query),
				"Query %s musi mieć identyczny kontrakt we wszystkich snapshotach progresji." % query_id
			)
		else:
			union_queries[query_id] = query


func _validate_snapshot_union_contract(union_target_ids: Dictionary, union_queries: Dictionary) -> void:
	var observed_target_ids := _sorted_string_values(union_target_ids.keys())
	var expected_target_ids := _sorted_string_values(STATIC_TARGET_CERTIFICATION_PROFILE.keys())
	_assert(observed_target_ids == expected_target_ids, "Unia 14 profili × 3 trudności musi zawierać dokładnie 65 statycznych celów.")
	var resource_pair_count := 0
	var full_interaction_count := 0
	var covered_target_ids: Dictionary = {}
	for query_value in union_queries.values():
		var query = query_value
		if str(query.resource_id).is_empty():
			full_interaction_count += 1
		else:
			resource_pair_count += 1
		if query.target_ids.size() == 1:
			covered_target_ids[str(query.target_ids[0])] = true
	_assert(resource_pair_count == STATIC_RESOURCE_PAIR_QUERY_COUNT, "Unia snapshotów musi zawierać dokładnie 103 pary źródło + zasób.")
	_assert(full_interaction_count == STATIC_FULL_INTERACTION_QUERY_COUNT, "Unia snapshotów musi zawierać dokładnie 35 pełnych interakcji.")
	_assert(union_queries.size() == STATIC_QUERY_COUNT, "Unia snapshotów musi zawierać dokładnie 138 zapytań statycznych.")
	_assert(_sorted_string_values(covered_target_ids.keys()) == expected_target_ids, "Unia 138 zapytań musi pokryć dokładnie wszystkie 65 celów.")


func _profile_case_query_ids(profile_cases: Array[Dictionary]) -> Array[String]:
	var query_ids: Dictionary = {}
	for profile_case in profile_cases:
		if not bool(profile_case.get("valid", false)):
			continue
		var queries_by_id: Dictionary = profile_case.get("queries_by_id", {})
		for query_value in queries_by_id.keys():
			query_ids[str(query_value)] = true
	return _sorted_string_values(query_ids.keys())


func _preflight_earliest_candidate(profile_cases: Array[Dictionary], query_id: String) -> Dictionary:
	var expected_query = null
	for profile_case in profile_cases:
		if not bool(profile_case.get("valid", false)):
			return {"valid": false, "reason_code": CertificateScript.INVALID_SNAPSHOT, "reason_detail": "Niepoprawny przypadek frontieru."}
		var queries_by_id: Dictionary = profile_case.get("queries_by_id", {})
		if not queries_by_id.has(query_id):
			_assert(false, "Query %s potencjalnego minimum musi istnieć na easy, standard i hard." % query_id)
			return {
				"valid": false,
				"reason_code": CertificateScript.TARGET_NOT_FOUND,
				"reason_detail": "Query nie występuje na każdym publicznym poziomie trudności.",
			}
		var query = queries_by_id[query_id]
		if expected_query == null:
			expected_query = query
		else:
			_assert(
				_queries_match_contract(expected_query, query),
				"Query %s musi mieć identyczny kontrakt na easy, standard i hard." % query_id
			)
		var preflight: Dictionary = _analyzer.preflight_sequence(
			profile_case.scenario.setup,
			profile_case.snapshot,
			query,
			ResourceLoader.load(POLICY_PATH)
		)
		if not bool(preflight.get("valid", false)):
			_validate_static_preflight_failure(preflight, query_id)
			return preflight
	return {"valid": true, "reason_code": &"", "reason_detail": ""}


func _validate_static_preflight_failure(preflight: Dictionary, query_id: String) -> void:
	var reason_code := StringName(preflight.get("reason_code", &""))
	_assert(
		reason_code in STATIC_PREFLIGHT_FAILURE_CODES,
		"Preflight query %s może odrzucać wyłącznie statyczny kontrakt celu/narzędzia/źródła/pojemności; otrzymano %s."
		% [query_id, str(reason_code)]
	)


func _replay_earliest_candidate(profile_cases: Array[Dictionary], query_id: String) -> Dictionary:
	var all_safe := true
	var replayed_difficulties: Dictionary = {}
	var observations: Array[String] = []
	for profile_case in profile_cases:
		var difficulty = profile_case.difficulty
		var profile_id := str(profile_case.profile.profile_id)
		replayed_difficulties[str(difficulty.profile_id)] = true
		var queries_by_id: Dictionary = profile_case.get("queries_by_id", {})
		_assert(queries_by_id.has(query_id), "Potencjalne minimum %s musi istnieć na każdym poziomie trudności." % query_id)
		if not queries_by_id.has(query_id):
			all_safe = false
			continue
		var query = queries_by_id[query_id]
		print(
			"DIVE_RECOVERY_FRONTIER DIFFICULTY_BEGIN profile=%s query=%s difficulty=%s"
			% [profile_id, query_id, str(difficulty.profile_id)]
		)
		var report = _analyzer.analyze_query(
			profile_case.scenario.setup,
			profile_case.snapshot,
			query,
			ResourceLoader.load(POLICY_PATH),
			profile_case.profile.profile_id,
			difficulty.profile_id
		)
		print(
			"DIVE_RECOVERY_FRONTIER DIFFICULTY_END profile=%s query=%s difficulty=%s feasible=%s safe=%s reason=%s"
			% [
				profile_id,
				query_id,
				str(difficulty.profile_id),
				str(bool(report.feasible)),
				str(bool(report.safe)),
				str(report.reason_code),
			]
		)
		var query_safe: bool = bool(report.feasible) and bool(report.safe) and report.reason_code == CertificateScript.OK_SAFE
		all_safe = all_safe and query_safe
		observations.append("%s=%s" % [str(difficulty.profile_id), str(report.reason_code)])
	_assert(
		replayed_difficulties.size() == DIFFICULTY_PATHS.size(),
		"Każde potencjalne minimum query %s musi wykonać pełny replay easy + standard + hard." % query_id
	)
	return {
		"valid": true,
		"safe": all_safe,
		"reason_code": CertificateScript.OK_SAFE if all_safe else CertificateScript.OK_FEASIBLE_RESERVE_SHORTFALL,
		"reason_detail": ", ".join(observations),
	}


func _has_safe_profile_ancestor(profile_id: String, safe_profiles: Array) -> bool:
	var ancestors := _profile_ancestor_ids(profile_id)
	for safe_profile_value in safe_profiles:
		if ancestors.has(str(safe_profile_value)):
			return true
	return false


func _record_frontier_evidence(
	frontier_evidence: Dictionary,
	query_id: String,
	profile_id: String,
	result: Dictionary
) -> void:
	var query_evidence: Dictionary = frontier_evidence.get(query_id, {})
	query_evidence[profile_id] = {
		"safe": bool(result.get("safe", false)),
		"reason_code": str(result.get("reason_code", "")),
		"reason_detail": str(result.get("reason_detail", "")),
	}
	frontier_evidence[query_id] = query_evidence


func _validate_earliest_cases_are_detached(profile_cases: Array[Dictionary], profile_id: String) -> void:
	for profile_case in profile_cases:
		if not bool(profile_case.get("valid", false)):
			continue
		var scenario: Dictionary = profile_case.scenario
		_assert(
			_delta_projection(scenario.state.underwater_world.delta) == profile_case.delta_before,
			"Frontier profilu %s nie może mutować WorldDelta." % profile_id
		)
		_assert(
			scenario.state.current_expedition_setup == null and scenario.state.last_dive_result == null,
			"Frontier profilu %s nie może mutować GameState ani tworzyć DiveResult." % profile_id
		)


func _validate_or_report_earliest_profiles(
	actual_profiles: Dictionary,
	union_queries: Dictionary,
	selected_query_ids: Array[String],
	shard: Dictionary
) -> void:
	var all_query_ids := _sorted_string_values(union_queries.keys())
	var query_ids := _sorted_string_values(selected_query_ids)
	var sharded := bool(shard.get("enabled", false))
	_assert(all_query_ids.size() == STATIC_QUERY_COUNT, "Porównanie minimów wymaga pełnej unii 138 query_id.")
	if not sharded:
		_assert(query_ids == all_query_ids, "Pełny przebieg minimów musi obejmować dokładnie 138 query_id.")
	_assert(
		_sorted_string_values(actual_profiles.keys()) == query_ids,
		"Wyznaczone minima muszą odpowiadać dokładnie wybranemu zakresowi query_id."
	)
	for query_id in query_ids:
		var query = union_queries.get(query_id, null)
		if query == null or query.target_ids.size() != 1:
			_assert(false, "Query %s nie wskazuje dokładnie jednego celu." % query_id)
			continue
		var target_id := str(query.target_ids[0])
		var assigned_profile := str(STATIC_TARGET_CERTIFICATION_PROFILE.get(target_id, ""))
		var assigned_ancestors := _profile_ancestor_ids(assigned_profile)
		var assigned_profile_descends_from_minimum := false
		for profile_id in (actual_profiles.get(query_id, []) as Array):
			if str(profile_id) == assigned_profile or assigned_ancestors.has(str(profile_id)):
				assigned_profile_descends_from_minimum = true
		_assert(
			assigned_profile_descends_from_minimum,
			"Legalny przypisany profil %s query %s musi być równy lub późniejszy od co najmniej jednego minimum."
			% [assigned_profile, query_id]
		)
	var differences: Array[String] = []
	if not EXPECTED_EARLIEST_PROFILES.is_empty():
		var declared_query_ids := _sorted_string_values(EXPECTED_EARLIEST_PROFILES.keys())
		if not sharded and declared_query_ids != query_ids:
			differences.append("query_id set: expected=%s actual=%s" % [str(declared_query_ids), str(query_ids)])
		for query_id in query_ids:
			if sharded and not EXPECTED_EARLIEST_PROFILES.has(query_id):
				continue
			var expected := _sorted_string_values(EXPECTED_EARLIEST_PROFILES.get(query_id, []))
			var actual := _sorted_string_values(actual_profiles.get(query_id, []))
			if expected != actual:
				differences.append("%s: expected=%s actual=%s" % [query_id, str(expected), str(actual)])
	if sharded or EXPECTED_EARLIEST_PROFILES.is_empty() or not differences.is_empty():
		_print_discovered_earliest_profiles(actual_profiles, query_ids, shard)
	if EXPECTED_EARLIEST_PROFILES.is_empty() and not sharded:
		_assert(
			false,
			"EXPECTED_EARLIEST_PROFILES jest puste. Discovery ukończone; skopiuj wydrukowaną mapę, aby zamknąć dowód bez zgadywania."
		)
		return
	if not differences.is_empty():
		_assert(
			false,
			"Najwcześniejsze profile różnią się od jawnego kontraktu:\n%s" % "\n".join(differences)
		)


func _print_discovered_earliest_profiles(
	actual_profiles: Dictionary,
	query_ids: Array[String],
	shard: Dictionary
) -> void:
	var sharded := bool(shard.get("enabled", false))
	var shard_suffix := (
		"_SHARD_%d_OF_%d" % [int(shard.get("index", 0)), int(shard.get("count", 1))]
		if sharded
		else ""
	)
	print("EARLIEST_PROFILE_DISCOVERY%s_BEGIN" % shard_suffix)
	print("{")
	for query_id in query_ids:
		var profile_ids := _sorted_string_values(actual_profiles.get(query_id, []))
		print("\t%s: %s," % [JSON.stringify(query_id), JSON.stringify(profile_ids)])
	print("}")
	print("EARLIEST_PROFILE_DISCOVERY%s_END" % shard_suffix)


func _sorted_string_values(values: Array) -> Array[String]:
	var result: Array[String] = []
	var unique_values: Dictionary = {}
	for value in values:
		var string_value := str(value)
		if unique_values.has(string_value):
			continue
		unique_values[string_value] = true
		result.append(string_value)
	result.sort()
	return result


func _validate_tutorial_route_resource_contracts() -> void:
	var day2_profile = ResourceLoader.load(TUTORIAL_DAY2_PROFILE_PATH)
	var day3_profile = ResourceLoader.load(TUTORIAL_DAY3_PROFILE_PATH)
	var first_dive_query = ResourceLoader.load(TUTORIAL_FIRST_DIVE_QUERY_PATH)
	var sc01_j7_query = ResourceLoader.load(TUTORIAL_SC01_J7_QUERY_PATH)
	_assert(day2_profile != null and day2_profile.is_valid(), "Profil certyfikacji pierwszego nurkowania musi być poprawnym Resource.")
	_assert(day3_profile != null and day3_profile.is_valid(), "Profil certyfikacji SC-01 → J-7 musi być poprawnym Resource.")
	_assert(first_dive_query != null and first_dive_query.is_valid(), "Wielozasobowe zapytanie pierwszego nurkowania musi być poprawnym Resource.")
	_assert(sc01_j7_query != null and sc01_j7_query.is_valid(), "Sekwencyjne zapytanie SC-01 → J-7 musi być poprawnym Resource.")
	if day2_profile != null:
		_assert(int(day2_profile.campaign_day) == 2, "Profil pierwszego nurkowania musi budować rzeczywisty dzień 2.")
		var invalid_day = day2_profile.duplicate(true)
		invalid_day.profile_id = &"invalid_campaign_day"
		invalid_day.campaign_day = 0
		_assert(not invalid_day.is_valid() and _errors_contain(invalid_day.validation_errors(), "campaign_day must be at least 1"), "Profil progresji musi odrzucać dzień kampanii mniejszy od 1.")
	if day3_profile != null:
		_assert(int(day3_profile.campaign_day) == 3, "Profil aktywacji J-7 musi budować rzeczywisty dzień 3.")
		_assert(int(day3_profile.workshop_level) == 1, "Profil aktywacji J-7 musi odpowiadać tutorialowemu Warsztatowi I.")
		_assert(day3_profile.story_access_ids == ["rescue_knife_unlocked"], "Profil aktywacji J-7 musi odblokowywać wyłącznie Nóż ratowniczy.")
	if first_dive_query != null:
		_assert(first_dive_query.target_ids == ["tutorial_market_crate", "tutorial_workshop_case"], "Pierwsze nurkowanie musi certyfikować obie skrzynie w kolejności gameplayu.")
		_assert(first_dive_query.normalized_requested_manifest() == TUTORIAL_FIRST_DIVE_MANIFEST, "Pierwsze nurkowanie musi certyfikować dokładne minimum dla Noża i zapasu startowego.")
		var invalid_manifest = first_dive_query.duplicate(true)
		invalid_manifest.query_id = &"invalid_mixed_manifest"
		invalid_manifest.resource_id = "food"
		invalid_manifest.requested_amount = 1
		_assert(not invalid_manifest.is_valid(), "Zapytanie nie może łączyć manifestu wielozasobowego ze starym żądaniem pojedynczego zasobu.")
		var invalid_full_manifest = first_dive_query.duplicate(true)
		invalid_full_manifest.query_id = &"invalid_full_manifest"
		invalid_full_manifest.require_full_targets = true
		_assert(not invalid_full_manifest.is_valid(), "Dokładny manifest częściowego łupu nie może jednocześnie wymuszać pełnego opróżnienia celów.")
	if sc01_j7_query != null:
		_assert(sc01_j7_query.target_ids == ["SC-01", "junction_j7"], "Trasa dnia 3 musi przecinać SC-01 przed aktywacją J-7.")
		_assert(sc01_j7_query.requested_manifest.is_empty(), "Sekwencja urządzeń nie może udawać zapytania ładunkowego.")


func _validate_tutorial_route(
	profile_path: String,
	query_path: String,
	expected_target_ids: Array,
	expected_manifest: Dictionary,
	expected_day: int,
	requires_knife: bool,
	difficulty_path: String
) -> void:
	var profile = ResourceLoader.load(profile_path)
	var difficulty = ResourceLoader.load(difficulty_path)
	var policy = ResourceLoader.load(POLICY_PATH)
	var query = ResourceLoader.load(query_path)
	var scenario: Dictionary = ScenarioFactoryScript.new().build(profile, difficulty)
	var errors: PackedStringArray = scenario.get("errors", PackedStringArray())
	var route_label := "%s × %s" % [str(query.query_id) if query != null else query_path, str(difficulty.profile_id) if difficulty != null else difficulty_path]
	_assert(errors.is_empty(), "Tutorialowa trasa %s musi powstać przez rzeczywisty builder: %s" % [route_label, str(errors)])
	if not errors.is_empty():
		return
	_assert(int(scenario.state.day) == expected_day, "Fabryka trasy %s musi ustawić dzień kampanii z profilu." % route_label)
	_assert(int(scenario.state.current_day_plan.day) == expected_day, "Plan dnia trasy %s musi być zsynchronizowany z profilem." % route_label)
	_assert(int(scenario.setup.day) == expected_day, "ExpeditionSetup trasy %s musi zachować dzień profilu." % route_label)
	_assert(scenario.setup.selected_gear.has("knife") == requires_knife, "Trasa %s ma niepoprawny dostęp do Noża ratowniczego." % route_label)
	var delta_before := _delta_projection(scenario.state.underwater_world.delta)
	var world = ContinuousWorldScript.new()
	world.set_snapshot_analysis_mode(true)
	world.configure(scenario.state.underwater_world, str(scenario.setup.start_entry_point), scenario.setup)
	root.add_child(world)
	await process_frame
	var snapshot = world.navigation_snapshot()
	_assert(snapshot != null and snapshot.is_valid(), "Trasa %s musi używać rzeczywistego snapshotu mapy." % route_label)
	if snapshot == null or not snapshot.is_valid():
		world.queue_free()
		await process_frame
		return
	for target_id in expected_target_ids:
		_assert(not _snapshot_targets(snapshot, str(target_id)).is_empty(), "Snapshot trasy %s musi zawierać cel %s." % [route_label, str(target_id)])
	if expected_target_ids == ["SC-01", "junction_j7"]:
		var shortcut_targets := _snapshot_targets(snapshot, "SC-01")
		_assert(shortcut_targets.size() == 1 and str(shortcut_targets[0].get("required_tool", "")) == "knife", "SC-01 musi wymagać Noża w rzeczywistym snapshotcie dnia 3.")
		_assert(_snapshot_has_closed_gate(snapshot, "SC-01"), "Wejściowy snapshot dnia 3 musi zawierać zamkniętą bramę SC-01.")
	var report = _analyzer.analyze_query(
		scenario.setup,
		snapshot,
		query,
		policy,
		profile.profile_id,
		difficulty.profile_id
	)
	_assert(report.feasible, "Tutorialowa trasa %s musi być FEASIBLE: %s" % [route_label, str(report.reason_code)])
	_assert(report.safe, "Tutorialowa trasa %s musi być SAFE: %s" % [route_label, str(report.reason_code)])
	_assert(report.reason_code == CertificateScript.OK_SAFE, "Tutorialowa trasa %s musi kończyć się stabilnym OK_SAFE." % route_label)
	_assert(report.requested_manifest == expected_manifest, "Raport trasy %s musi zachować wejściowy manifest wielozasobowy." % route_label)
	_assert(report.certificates.size() == 1, "Tutorialowa trasa %s musi być jedną wspólną wyprawą." % route_label)
	if report.certificates.size() == 1:
		var certificate = report.certificates[0]
		_assert(certificate.target_ids == expected_target_ids, "Certyfikat %s musi zachować kolejność wszystkich celów." % route_label)
		for resource_id in expected_manifest.keys():
			_assert(int(certificate.recovered_items.get(str(resource_id), 0)) == int(expected_manifest[resource_id]), "Certyfikat %s musi odzyskać dokładny manifest %s." % [route_label, str(resource_id)])
	var route_descriptors: Array = []
	for target_id in expected_target_ids:
		var matching_targets := _snapshot_targets(snapshot, str(target_id))
		if not matching_targets.is_empty():
			route_descriptors.append(matching_targets[0])
	_validate_certificate_design_output(report, scenario.setup, route_descriptors, route_label)
	_assert(_delta_projection(scenario.state.underwater_world.delta) == delta_before, "Certyfikacja trasy %s nie może mutować WorldDelta." % route_label)
	if expected_target_ids == ["SC-01", "junction_j7"]:
		_assert(_snapshot_has_closed_gate(snapshot, "SC-01"), "Certyfikacja SC-01 → J-7 musi otwierać wyłącznie odłączoną kopię bramy.")
	world.queue_free()
	await process_frame


func _snapshot_targets(snapshot, target_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for descriptor in snapshot.target_descriptors():
		if str(descriptor.get("id", "")) == target_id:
			result.append(descriptor)
	return result


func _snapshot_has_closed_gate(snapshot, gate_id: String) -> bool:
	for gate in snapshot.closed_gate_descriptors():
		if str(gate.get("id", "")) == gate_id:
			return true
	return false


func _validate_detached_shortcut_sequence() -> void:
	var standard = ResourceLoader.load("res://data/difficulty/standard.tres")
	var profile = ResourceLoader.load(PROFILE_PATHS[0])
	var scenario: Dictionary = ScenarioFactoryScript.new().build(profile, standard)
	var errors: PackedStringArray = scenario.get("errors", PackedStringArray())
	_assert(errors.is_empty(), "Sekwencja skrótu wymaga legalnego setupu z rzeczywistego buildera.")
	if not errors.is_empty():
		return
	var snapshot = _shortcut_sequence_snapshot()
	var analyzer = _analyzer
	var policy = ResourceLoader.load(POLICY_PATH).duplicate(true)
	policy.planner_cell_stride = 1
	var mutation_probe = _shortcut_sequence_snapshot()
	var expected_current_zones: Array[Dictionary] = mutation_probe.current_zones.duplicate(true)
	var expected_depth_regions: Array[Dictionary] = mutation_probe.depth_regions.duplicate(true)
	_assert(analyzer._open_shortcut_in_detached_snapshot(mutation_probe, "SC-TEST"), "Fixture musi pozwalać otworzyć skrót w odłączonej migawce.")
	_assert(mutation_probe.current_zones == expected_current_zones, "Otwarcie skrótu nie może usuwać ani zmieniać stref prądów migawki.")
	_assert(mutation_probe.depth_regions == expected_depth_regions, "Otwarcie skrótu nie może usuwać ani zmieniać regionów głębokości migawki.")

	var blocked_query = QueryScript.new()
	blocked_query.query_id = &"blocked_after_gate"
	blocked_query.target_ids.assign(["after_gate_container"])
	var blocked = analyzer.analyze_query(
		scenario.setup,
		snapshot,
		blocked_query,
		policy,
		profile.profile_id,
		standard.profile_id
	)
	_assert(not blocked.feasible and blocked.reason_code == CertificateScript.TARGET_UNREACHABLE, "Zamknięta brama musi blokować cel kontrolny przed interakcją.")

	var sequence_query = QueryScript.new()
	sequence_query.query_id = &"open_shortcut_then_recover"
	sequence_query.target_ids.assign(["SC-TEST", "after_gate_container"])
	sequence_query.allow_combining_sources = true
	var sequence = analyzer.analyze_query(
		scenario.setup,
		snapshot,
		sequence_query,
		policy,
		profile.profile_id,
		standard.profile_id
	)
	_assert(sequence.feasible and sequence.safe, "Interakcja ze skrótem musi odmaskować bramę w odłączonym snapshotcie przed kolejnym odcinkiem.")
	_assert(sequence.certificates.size() == 1 and sequence.certificates[0].target_ids == ["SC-TEST", "after_gate_container"], "Sekwencja musi certyfikować skrót, cel za bramą i normalny powrót.")
	_assert(not snapshot.is_position_clear(Vector2(405.0, 305.0)), "Wejściowy snapshot musi pozostać niemutowany po sekwencyjnym replayu.")


func _validate_routing_signature_snapshot_lifetime() -> void:
	var analyzer = AnalyzerScript.new()
	var policy = ResourceLoader.load(POLICY_PATH)
	var source_snapshot = _planner_margin_snapshot(true)
	var source_snapshot_ref: WeakRef = weakref(source_snapshot)
	var source_signature: String = analyzer._routing_signature(source_snapshot)
	_assert(not source_signature.is_empty(), "Podpis routingu wejściowego snapshotu nie może być pusty.")
	_assert(
		not source_snapshot.has_meta(&"recovery_routing_signature"),
		"Obliczenie podpisu nie może mutować metadanych wejściowego snapshotu."
	)

	var detached_snapshot = analyzer._detached_navigation_snapshot(source_snapshot)
	_assert(
		detached_snapshot != null
		and detached_snapshot.has_meta(&"recovery_routing_signature")
		and str(detached_snapshot.get_meta(&"recovery_routing_signature")) == source_signature,
		"Lokalna kopia replayu musi przechowywać obliczony podpis routingu w metadanych."
	)
	var detached_snapshot_ref: WeakRef = weakref(detached_snapshot)
	detached_snapshot = null
	_assert(
		detached_snapshot_ref.get_ref() == null,
		"Memoizacja podpisu nie może zatrzymywać lokalnej kopii replayu po zwolnieniu ostatniej referencji."
	)

	var planning_snapshot = analyzer._planning_navigation_snapshot(source_snapshot, policy)
	_assert(
		planning_snapshot != null
		and planning_snapshot.has_meta(&"recovery_routing_signature"),
		"Lokalny snapshot bezpieczeństwa planera musi przechowywać podpis routingu w metadanych."
	)
	var planning_snapshot_ref: WeakRef = weakref(planning_snapshot)
	planning_snapshot = null
	_assert(
		planning_snapshot_ref.get_ref() == null,
		"Memoizacja podpisu nie może zatrzymywać snapshotu bezpieczeństwa po zwolnieniu ostatniej referencji."
	)

	source_snapshot = null
	_assert(
		source_snapshot_ref.get_ref() == null,
		"Analizator nie może przechowywać silnej referencji do wejściowego snapshotu po obliczeniu podpisu."
	)


func _validate_current_aware_planner_margin() -> void:
	var standard = ResourceLoader.load("res://data/difficulty/standard.tres")
	var profile = ResourceLoader.load(PROFILE_PATHS[0])
	var scenario: Dictionary = ScenarioFactoryScript.new().build(profile, standard)
	var errors: PackedStringArray = scenario.get("errors", PackedStringArray())
	_assert(errors.is_empty(), "Regresja marginesu planera wymaga legalnego setupu.")
	if not errors.is_empty():
		return
	var policy = ResourceLoader.load(POLICY_PATH).duplicate(true)
	policy.planner_cell_stride = 1

	var narrow_base = _planner_margin_snapshot(true)
	var narrow_safety = _analyzer._planning_navigation_snapshot(narrow_base, policy)
	var narrow_plan: Dictionary = _analyzer._plan_path(
		narrow_base,
		narrow_safety,
		Vector2(105.0, 205.0),
		Vector2(505.0, 205.0),
		10.0,
		scenario.setup,
		0.0,
		null,
		policy
	)
	_assert(bool(narrow_plan.get("found", false)), "Margines prądowy nie może zamknąć wąskiego gardła poza strefą prądu.")

	var tangent_base = _planner_margin_snapshot(false)
	var tangent_safety = _analyzer._planning_navigation_snapshot(tangent_base, policy)
	var point_a := Vector2(105.0, 255.0)
	var point_b := Vector2(305.0, 335.0)
	var point_c := Vector2(505.0, 255.0)
	_assert(tangent_base.is_segment_clear(point_a, point_c), "Fixture stycznej musi być przechodni na bazowym prześwicie.")
	_assert(not tangent_safety.is_segment_clear(point_a, point_c), "Fixture stycznej musi naruszać dodatkowy margines planera.")
	var simplified: PackedVector2Array = _analyzer._simplify_path(
		tangent_base,
		tangent_safety,
		PackedVector2Array([point_a, point_b, point_c]),
		{},
		{}
	)
	_assert(simplified.size() == 3 and simplified[1] == point_b, "Uproszczenie trasy w prądzie musi zachować waypoint odsuwający od skały.")


func _validate_interaction_current_replay() -> void:
	var standard = ResourceLoader.load("res://data/difficulty/standard.tres")
	var profile = ResourceLoader.load(PROFILE_PATHS[0])
	var scenario: Dictionary = ScenarioFactoryScript.new().build(profile, standard)
	var errors: PackedStringArray = scenario.get("errors", PackedStringArray())
	_assert(errors.is_empty(), "Regresja interakcji w prądzie wymaga legalnego setupu.")
	if not errors.is_empty():
		return
	var policy = ResourceLoader.load(POLICY_PATH).duplicate(true)
	policy.planner_cell_stride = 1
	var query = QueryScript.new()
	query.query_id = &"interaction_current_hold"
	query.target_ids.assign(["current_hold_target"])

	var still_report = _analyzer.analyze_query(
		scenario.setup,
		_interaction_current_snapshot(Vector2.ZERO),
		query,
		policy,
		profile.profile_id,
		standard.profile_id
	)
	var moderate_report = _analyzer.analyze_query(
		scenario.setup,
		_interaction_current_snapshot(Vector2(60.0, 0.0)),
		query,
		policy,
		profile.profile_id,
		standard.profile_id
	)
	_assert(still_report.feasible and still_report.safe, "Kontrolna interakcja w spokojnej wodzie musi być SAFE.")
	_assert(moderate_report.feasible and moderate_report.safe, "Nurek musi móc utrzymać pozycję podczas interakcji w umiarkowanym prądzie.")
	if not still_report.certificates.is_empty() and not moderate_report.certificates.is_empty():
		_assert(
			float(moderate_report.certificates[0].oxygen_remaining) < float(still_report.certificates[0].oxygen_remaining),
			"Replay interakcji w prądzie musi naliczać ruch przeciwny do prądu i wyższe zużycie tlenu."
		)
	var threat_report = _analyzer.analyze_query(
		scenario.setup,
		_interaction_current_snapshot(Vector2.ZERO, true),
		query,
		policy,
		profile.profile_id,
		standard.profile_id
	)
	_assert(threat_report.feasible and threat_report.safe, "Kontrolna ekspozycja na zagrożenie nie może unieważniać bezpiecznej interakcji.")
	if not threat_report.certificates.is_empty():
		_assert(float(threat_report.certificates[0].threat_exposure_seconds) > 0.0, "Certyfikat musi naliczać czas przebywania w aktywnym promieniu zagrożenia.")
		var threat_serialized: Dictionary = threat_report.to_dictionary()
		var threat_certificates: Array = threat_serialized.get("certificates", [])
		_assert(not threat_certificates.is_empty() and float((threat_certificates[0] as Dictionary).get("threat_exposure_seconds", 0.0)) > 0.0, "JSON wyniku musi zachować dodatnią ekspozycję na przeciwnika.")

	var excessive_report = _analyzer.analyze_query(
		scenario.setup,
		_interaction_current_snapshot(Vector2(400.0, 0.0)),
		query,
		policy,
		profile.profile_id,
		standard.profile_id
	)
	_assert(
		not excessive_report.feasible and excessive_report.reason_code == CertificateScript.REPLAY_GEOMETRY_DIVERGED,
		"Prąd silniejszy od zdolności utrzymania pozycji musi przerwać interakcję po utracie zasięgu."
	)
	if not excessive_report.certificates.is_empty():
		_assert(
			"utracił zasięg celu" in str(excessive_report.certificates[0].reason_detail),
			"Porażka interakcji w zbyt silnym prądzie musi mieć jednoznaczny reason_detail."
		)


func _interaction_current_snapshot(current_velocity: Vector2, include_threat: bool = false):
	var grid_size := Vector2i(81, 61)
	var open_cells := PackedByteArray()
	open_cells.resize(grid_size.x * grid_size.y)
	open_cells.fill(1)
	var currents: Array[Dictionary] = []
	if current_velocity.length_squared() > 0.01:
		currents.append({
			"id": "interaction_current_fixture",
			"rect": Rect2(0.0, 0.0, 810.0, 610.0),
			"velocity": current_velocity,
		})
	var target_position := Vector2(405.0, 305.0)
	var threats: Array[Dictionary] = []
	if include_threat:
		var threat_definition = ThreatDefinitionScript.new()
		threat_definition.id = "diagnostic_exposure_threat"
		threat_definition.display_name = "Zagrożenie kontrolne"
		threat_definition.noise_detection_radius = 420.0
		threat_definition.light_detection_radius = 155.0
		threat_definition.noise_threshold = 100.0
		threat_definition.light_sensitivity = 0.0
		threat_definition.alert_rate = 0.1
		threat_definition.warning_threshold = 99.0
		threat_definition.attack_threshold = 100.0
		threats.append({
			"id": "diagnostic_exposure_threat",
			"position": target_position,
			"definition": threat_definition,
		})
	var snapshot = NavigationSnapshotScript.new()
	snapshot.configure(
		Vector2(810.0, 610.0),
		grid_size,
		Vector2(10.0, 10.0),
		open_cells,
		35.0,
		target_position,
		target_position,
		currents,
		[],
		[],
		[
			{
				"id": "current_hold_target",
				"kind": "persistent_objective",
				"persistent_kind": "fixed_device",
				"position": target_position,
				"requested_position": target_position,
				"interaction_action": "activate",
				"interaction_seconds": 1.5,
				"available": true,
				"completed": false,
			}
		],
		threats
	)
	return snapshot


func _planner_margin_snapshot(narrow_passage: bool):
	var grid_size := Vector2i(61, 41)
	var open_cells := PackedByteArray()
	open_cells.resize(grid_size.x * grid_size.y)
	open_cells.fill(1)
	var currents: Array[Dictionary] = []
	if narrow_passage:
		for y in range(grid_size.y):
			if y >= 15 and y <= 25:
				continue
			open_cells[y * grid_size.x + 30] = 0
	else:
		open_cells[20 * grid_size.x + 30] = 0
		currents.append({
			"id": "planner_tangent_current",
			"rect": Rect2(100.0, 245.0, 410.0, 20.0),
			"velocity": Vector2(0.0, 60.0),
		})
	var snapshot = NavigationSnapshotScript.new()
	snapshot.configure(
		Vector2(610.0, 410.0),
		grid_size,
		Vector2(10.0, 10.0),
		open_cells,
		35.0,
		Vector2(105.0, 205.0),
		Vector2(505.0, 205.0),
		currents,
		[],
		[],
		[],
		[]
	)
	return snapshot


func _shortcut_sequence_snapshot():
	var grid_size := Vector2i(81, 61)
	var cell_scale := Vector2(10.0, 10.0)
	var open_cells := PackedByteArray()
	open_cells.resize(grid_size.x * grid_size.y)
	open_cells.fill(1)
	for y in range(grid_size.y):
		if y >= 18 and y <= 42:
			continue
		open_cells[y * grid_size.x + 39] = 0
		open_cells[y * grid_size.x + 40] = 0
	var gate_transform := Transform2D(PI * 0.5, Vector2(405.0, 305.0))
	var gate := {
		"id": "SC-TEST",
		"transform": gate_transform,
		"position": gate_transform.origin,
		"rotation": gate_transform.get_rotation(),
		"size": Vector2(190.0, 28.0),
		"active": true,
	}
	var targets := [
		{
			"id": "SC-TEST",
			"kind": "persistent_objective",
			"persistent_kind": "shortcut",
			"position": Vector2(405.0, 305.0),
			"requested_position": Vector2(405.0, 305.0),
			"required_tool": "crowbar",
			"interaction_action": "pry",
			"interaction_seconds": 0.1,
			"available": true,
			"completed": false,
			"is_obstacle": true,
			"obstacle": gate.duplicate(true),
		},
		{
			"id": "after_gate_container",
			"kind": "container",
			"position": Vector2(620.0, 305.0),
			"requested_position": Vector2(620.0, 305.0),
			"contents": {"food": 1},
			"required_tool": "",
			"interaction_action": "open",
			"interaction_seconds": 0.1,
			"available": true,
			"completed": false,
		},
	]
	var snapshot = NavigationSnapshotScript.new()
	snapshot.configure(
		Vector2(810.0, 610.0),
		grid_size,
		cell_scale,
		open_cells,
		35.0,
		Vector2(105.0, 305.0),
		Vector2(105.0, 305.0),
		[
			{
				"id": "shortcut_current_fixture",
				"rect": Rect2(0.0, 0.0, 40.0, 40.0),
				"velocity": Vector2(12.0, 0.0),
			}
		],
		[
			{
				"id": "shortcut_depth_fixture",
				"bounds": Rect2(0.0, 0.0, 810.0, 610.0),
				"depth_range": Vector2(12.0, 24.0),
			}
		],
		[gate],
		targets,
		[]
	)
	return snapshot


func _errors_contain(errors: PackedStringArray, fragment: String) -> bool:
	for error in errors:
		if fragment in error:
			return true
	return false


func _same_certificate(left, right) -> bool:
	return (
		left.reason_code == right.reason_code
		and left.feasible == right.feasible
		and left.safe == right.safe
		and left.route == right.route
		and is_equal_approx(left.oxygen_remaining, right.oxygen_remaining)
		and is_equal_approx(left.cold_exposure, right.cold_exposure)
		and left.health_remaining == right.health_remaining
		and left.suit_condition_remaining == right.suit_condition_remaining
	)


func _delta_projection(delta) -> Dictionary:
	return {
		"active_landmark_id": delta.active_landmark_id,
		"discovered_landmarks": delta.discovered_landmarks.duplicate(),
		"discovered_chunks": delta.discovered_chunks.duplicate(),
		"opened_containers": delta.opened_containers.duplicate(),
		"collected_items": delta.collected_items.duplicate(),
		"remaining_container_contents": delta.remaining_container_contents.duplicate(true),
		"dead_divers": delta.dead_divers.duplicate(true),
		"lost_backpacks": delta.lost_backpacks.duplicate(true),
		"dropped_loot_piles": delta.dropped_loot_piles.duplicate(true),
		"placed_buoys": delta.placed_buoys.duplicate(),
		"opened_shortcuts": delta.opened_shortcuts.duplicate(),
		"activated_fixed_devices": delta.activated_fixed_devices.duplicate(),
		"marked_heavy_objects": delta.marked_heavy_objects.duplicate(),
		"recovered_heavy_objects": delta.recovered_heavy_objects.duplicate(),
		"rescued_or_dead_survivors": delta.rescued_or_dead_survivors.duplicate(true),
		"collapsed_paths": delta.collapsed_paths.duplicate(),
		"depleted_biological_nodes": delta.depleted_biological_nodes.duplicate(true),
	}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
