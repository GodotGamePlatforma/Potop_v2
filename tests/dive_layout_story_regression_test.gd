extends SceneTree


const ScenarioFactoryScript := preload("res://scripts/diving/DiveRecoveryScenarioFactory.gd")
const AnalyzerScript := preload("res://scripts/diving/DiveRecoveryAnalyzer.gd")
const ContinuousWorldScript := preload("res://scripts/diving/UnderwaterMapRuntime.gd")
const NavigationSnapshotScript := preload("res://scripts/diving/DiveNavigationSnapshot.gd")
const PersistenceValidatorScript := preload("res://scripts/data/GameStatePersistenceValidator.gd")
const CertificateScript := preload("res://scripts/diving/DiveRecoveryCertificate.gd")

const POLICY_PATH := "res://data/diving_validation/default_safety_policy.tres"
const STANDARD_PATH := "res://data/difficulty/standard.tres"
const DIFFICULTY_PATHS := [
	"res://data/difficulty/easy.tres",
	"res://data/difficulty/standard.tres",
	"res://data/difficulty/hard.tres",
]
const STORY_CHECKPOINTS := [
	{
		"path": "res://data/diving_validation/profiles/story_archive_main_line.tres",
		"day": 4,
		"target": "archive_terminal",
		"completed": ["junction_j7"],
	},
	{
		"path": "res://data/diving_validation/profiles/story_r3_diagnostic_main_line.tres",
		"day": 5,
		"target": "r3_diagnostic_panel",
		"completed": ["junction_j7", "archive_terminal"],
	},
	{
		"path": "res://data/diving_validation/profiles/story_r3_generator_main_line.tres",
		"day": 8,
		"target": "r3_generator",
		"completed": ["junction_j7", "archive_terminal", "r3_diagnostic_panel"],
	},
	{
		"path": "res://data/diving_validation/profiles/story_c4_buoy_b03.tres",
		"day": 9,
		"target": "c4_switchboard",
		"completed": ["junction_j7", "archive_terminal", "r3_diagnostic_panel", "r3_generator"],
	},
	{
		"path": "res://data/diving_validation/profiles/story_splitter_buoy_b03.tres",
		"day": 12,
		"target": "c4_splitter_mount",
		"completed": ["junction_j7", "archive_terminal", "r3_diagnostic_panel", "r3_generator", "c4_switchboard"],
	},
]
const BUOY_ENTRY_PROFILES := [
	"res://data/diving_validation/profiles/station_iv_buoy_b01.tres",
	"res://data/diving_validation/profiles/station_iv_buoy_b02.tres",
	"res://data/diving_validation/profiles/station_iv_buoy_b03.tres",
]
const GEOMETRY_REGRESSIONS := [
	{
		"profile": "res://data/diving_validation/profiles/tank_iii_workshop_iii.tres",
		"target": "power_plant_service_store",
	},
	{
		"profile": "res://data/diving_validation/profiles/story_r3_generator_main_line.tres",
		"target": "r3_generator",
	},
	{
		"profile": "res://data/diving_validation/profiles/station_iv_buoy_b03.tres",
		"target": "sealed_gate_parts",
	},
]

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_story_checkpoints()
	await _validate_all_buoy_entries()
	var requested_difficulty := OS.get_environment("DIVE_LAYOUT_DIFFICULTY").strip_edges()
	var requested_target := OS.get_environment("DIVE_LAYOUT_TARGET").strip_edges()
	for difficulty_path in DIFFICULTY_PATHS:
		if not requested_difficulty.is_empty() and not str(difficulty_path).ends_with("/%s.tres" % requested_difficulty):
			continue
		for regression in GEOMETRY_REGRESSIONS:
			if not requested_target.is_empty() and str(regression.target) != requested_target:
				continue
			await _validate_geometry_regression(regression, str(difficulty_path))
	if _failed:
		quit(1)
		return
	print("Dive layout/story regression test passed: legal story days, B-01/B-02/B-03 entries and repaired geometry are certified.")
	quit(0)


func _validate_story_checkpoints() -> void:
	var standard = ResourceLoader.load(STANDARD_PATH)
	for checkpoint in STORY_CHECKPOINTS:
		var profile = ResourceLoader.load(str(checkpoint.path))
		var scenario: Dictionary = ScenarioFactoryScript.new().build(profile, standard)
		var errors: PackedStringArray = scenario.get("errors", PackedStringArray())
		_assert(errors.is_empty(), "Profil fabularny musi powstać przez produkcyjny builder: %s" % str(errors))
		if not errors.is_empty():
			continue
		_assert(int(profile.campaign_day) == int(checkpoint.day), "Profil %s musi używać legalnego dnia %d." % [str(profile.profile_id), int(checkpoint.day)])
		_assert(
			scenario.state.underwater_world.delta.activated_fixed_devices == checkpoint.completed,
			"Profil %s musi zawierać dokładny narastający łańcuch urządzeń." % str(profile.profile_id)
		)
		_assert(
			not scenario.state.underwater_world.delta.activated_fixed_devices.has(str(checkpoint.target)),
			"Bieżący cel %s nie może być ukończony przed certyfikowaną wyprawą." % str(checkpoint.target)
		)
		var story_errors: Array[String] = []
		PersistenceValidatorScript._validate_story(story_errors, scenario.state, {})
		_assert(story_errors.is_empty(), "Profil %s musi mieć spójny typed story state: %s" % [str(profile.profile_id), str(story_errors)])


func _validate_all_buoy_entries() -> void:
	var standard = ResourceLoader.load(STANDARD_PATH)
	for profile_path in BUOY_ENTRY_PROFILES:
		var profile = ResourceLoader.load(str(profile_path))
		var scenario: Dictionary = ScenarioFactoryScript.new().build(profile, standard)
		var errors: PackedStringArray = scenario.get("errors", PackedStringArray())
		_assert(errors.is_empty(), "Profil wejścia z boi musi przejść builder: %s" % str(errors))
		if not errors.is_empty():
			continue
		var world = ContinuousWorldScript.new()
		world.set_snapshot_analysis_mode(true)
		world.configure(scenario.state.underwater_world, str(scenario.setup.start_entry_point), scenario.setup)
		root.add_child(world)
		await process_frame
		var active_buoy := _buoy_for_entry(scenario.state.underwater_world.blueprint.buoy_spawns, str(profile.start_entry_point))
		var expected_start: Vector2 = world.nearest_navigable_position(
			active_buoy.get("position", Vector2.ZERO),
			NavigationSnapshotScript.DEFAULT_DIVER_CLEARANCE
		)
		_assert(str(scenario.setup.start_entry_point) == str(profile.start_entry_point), "Builder musi przekazać wybrane wejście %s." % str(profile.start_entry_point))
		_assert(world.start_position() == expected_start, "Wejście %s musi materializować start przy fizycznej kotwicy boi." % str(profile.start_entry_point))
		_assert(world.exit_line.global_position == active_buoy.get("position", Vector2.ZERO), "Wejście %s musi zakotwiczyć powrót przy swojej boi." % str(profile.start_entry_point))
		_assert(world.start_position().distance_to(world.exit_line.global_position) <= 1.0, "Wejście %s musi umieścić nurka bezpośrednio przy aktywnej linie." % str(profile.start_entry_point))
		var active_buoy_runtime_count := 0
		for interactable in world.persistent_interactables:
			if str(interactable.persistent_id) == str(active_buoy.get("id", "")):
				active_buoy_runtime_count += 1
		_assert(active_buoy_runtime_count == 0, "Aktywna boja nie może dublować prezentacji ExitLine: %s." % str(active_buoy.get("id", "")))
		world.queue_free()
		await process_frame


func _validate_geometry_regression(regression: Dictionary, difficulty_path: String) -> void:
	var profile = ResourceLoader.load(str(regression.profile))
	var difficulty = ResourceLoader.load(difficulty_path)
	var scenario: Dictionary = ScenarioFactoryScript.new().build(profile, difficulty)
	var errors: PackedStringArray = scenario.get("errors", PackedStringArray())
	_assert(errors.is_empty(), "Profil regresji geometrii musi przejść builder: %s" % str(errors))
	if not errors.is_empty():
		return
	var world = ContinuousWorldScript.new()
	world.set_snapshot_analysis_mode(true)
	world.configure(scenario.state.underwater_world, str(scenario.setup.start_entry_point), scenario.setup)
	root.add_child(world)
	await process_frame
	var snapshot = world.navigation_snapshot()
	var analyzer = AnalyzerScript.new()
	var query = null
	for candidate in analyzer.queries_for_static_targets(snapshot):
		if candidate.target_ids == [str(regression.target)]:
			query = candidate
			break
	_assert(query != null, "Cel %s musi mieć deterministyczne zapytanie." % str(regression.target))
	if query != null:
		var report = analyzer.analyze_query(
			scenario.setup,
			snapshot,
			query,
			ResourceLoader.load(POLICY_PATH),
			profile.profile_id,
			difficulty.profile_id
		)
		_assert(
			report.feasible and report.safe and report.reason_code == CertificateScript.OK_SAFE,
			"Naprawiony cel %s musi być FEASIBLE/SAFE na %s; wynik %s."
			% [
				str(regression.target),
				str(difficulty.profile_id),
				"%s: %s" % [str(report.reason_code), str(report.certificates[0].reason_detail) if not report.certificates.is_empty() else "bez certyfikatu"],
			]
		)
	world.queue_free()
	await process_frame


func _buoy_for_entry(records: Array[Dictionary], entry_id: String) -> Dictionary:
	for record in records:
		if str(record.get("entry_landmark_id", "")) == entry_id:
			return record
	return {}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
