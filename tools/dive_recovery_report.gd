extends SceneTree


const ScenarioFactoryScript := preload("res://scripts/diving/DiveRecoveryScenarioFactory.gd")
const AnalyzerScript := preload("res://scripts/diving/DiveRecoveryAnalyzer.gd")
const ContinuousWorldScript := preload("res://scripts/diving/UnderwaterMapRuntime.gd")

const DEFAULT_POLICY_PATH := "res://data/diving_validation/default_safety_policy.tres"
const DEFAULT_QUERY_PATH := "res://data/diving_validation/queries/tutorial_market_crate_full.tres"
const PROFILE_PATHS: Dictionary = {
	"tutorial_day2_station_i": "res://data/diving_validation/profiles/tutorial_day2_station_i.tres",
	"tutorial_day3_station_i_workshop_i": "res://data/diving_validation/profiles/tutorial_day3_station_i_workshop_i.tres",
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
const DIFFICULTY_PATHS: Dictionary = {
	"easy": "res://data/difficulty/easy.tres",
	"standard": "res://data/difficulty/standard.tres",
	"hard": "res://data/difficulty/hard.tres",
}

var _exit_code := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	if options.has("error"):
		push_error(str(options.error))
		quit(2)
		return
	var profile_ids: Array[String] = []
	var difficulty_ids: Array[String] = []
	profile_ids.assign(PROFILE_PATHS.keys() if bool(options.all_profiles) else [str(options.profile)])
	difficulty_ids.assign(DIFFICULTY_PATHS.keys() if bool(options.all_public_difficulties) else [str(options.difficulty)])
	profile_ids.sort()
	difficulty_ids.sort()
	var output: Array = []
	for profile_id in profile_ids:
		for difficulty_id in difficulty_ids:
			var scenario_reports: Array = await _run_scenario(
				profile_id,
				difficulty_id,
				bool(options.all_targets),
				str(options.target)
			)
			output.append_array(scenario_reports)
	print(JSON.stringify(output, "  ", false))
	quit(_exit_code)


func _run_scenario(profile_id: String, difficulty_id: String, all_targets: bool, target_id: String) -> Array:
	var result: Array = []
	if not PROFILE_PATHS.has(profile_id) or not DIFFICULTY_PATHS.has(difficulty_id):
		_exit_code = 2
		return [{"profile_id": profile_id, "difficulty_profile_id": difficulty_id, "reason_code": "UNKNOWN_PROFILE"}]
	var progression_profile = ResourceLoader.load(str(PROFILE_PATHS[profile_id]))
	var difficulty_profile = ResourceLoader.load(str(DIFFICULTY_PATHS[difficulty_id]))
	var policy = ResourceLoader.load(DEFAULT_POLICY_PATH)
	var scenario: Dictionary = ScenarioFactoryScript.new().build(progression_profile, difficulty_profile)
	var errors: PackedStringArray = scenario.get("errors", PackedStringArray())
	if not errors.is_empty():
		_exit_code = 2
		var error_values: Array[String] = []
		error_values.assign(errors)
		return [{
			"profile_id": profile_id,
			"difficulty_profile_id": difficulty_id,
			"reason_code": "SCENARIO_INVALID",
			"errors": error_values,
		}]

	var world = ContinuousWorldScript.new()
	world.set_snapshot_analysis_mode(true)
	world.configure(
		scenario.state.underwater_world,
		str(scenario.setup.start_entry_point),
		scenario.setup
	)
	root.add_child(world)
	await process_frame
	var snapshot = world.navigation_snapshot()
	var analyzer = AnalyzerScript.new()
	var queries: Array[Resource] = []
	if all_targets or not target_id.is_empty():
		for static_query in analyzer.queries_for_static_targets(snapshot):
			if all_targets or static_query.target_ids == [target_id]:
				queries.append(static_query)
		if queries.is_empty():
			_exit_code = 2
			world.queue_free()
			await process_frame
			return [{
				"profile_id": profile_id,
				"difficulty_profile_id": difficulty_id,
				"target_id": target_id,
				"reason_code": "TARGET_NOT_FOUND",
			}]
	else:
		var query = ResourceLoader.load(DEFAULT_QUERY_PATH).duplicate(true)
		queries.append(query)
	for query in queries:
		var report = analyzer.analyze_query(
			scenario.setup,
			snapshot,
			query,
			policy,
			progression_profile.profile_id,
			difficulty_profile.profile_id
		)
		# Wynik projektowy zawsze zawiera trasę; flaga pozostaje akceptowana dla
		# kompatybilności ze starszymi poleceniami narzędzia.
		result.append(report.to_dictionary(true))
		if difficulty_id in ["easy", "standard", "hard"] and not report.safe:
			_exit_code = 1
	world.queue_free()
	await process_frame
	return result


func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var result := {
		"profile": "tank_i_station_i",
		"difficulty": "standard",
		"target": "",
		"all_profiles": false,
		"all_public_difficulties": false,
		"all_targets": false,
	}
	for argument in arguments:
		if argument == "--all-profiles":
			result.all_profiles = true
		elif argument == "--all-public-difficulties":
			result.all_public_difficulties = true
		elif argument == "--all-targets":
			result.all_targets = true
		elif argument == "--include-routes":
			continue
		elif argument.begins_with("--profile="):
			result.profile = argument.trim_prefix("--profile=")
		elif argument.begins_with("--difficulty="):
			result.difficulty = argument.trim_prefix("--difficulty=")
		elif argument.begins_with("--target="):
			result.target = argument.trim_prefix("--target=")
		else:
			result.error = "Nieznany argument: %s" % argument
	if not PROFILE_PATHS.has(str(result.profile)):
		result.error = "Nieznany profil progresji: %s" % str(result.profile)
	if not DIFFICULTY_PATHS.has(str(result.difficulty)):
		result.error = "Nieznany publiczny preset: %s" % str(result.difficulty)
	return result
