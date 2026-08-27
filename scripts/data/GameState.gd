class_name GameState
extends Resource

const MAX_END_DAY_REPORT_HISTORY := 7

const GameFormatScript := preload("res://scripts/data/GameFormat.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const ResourceStorageScript := preload("res://scripts/data/ResourceStorage.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const PlatformStateScript := preload("res://scripts/data/PlatformState.gd")
const UnderwaterWorldStateScript := preload("res://scripts/data/UnderwaterWorldState.gd")
const StoryProgressStateScript := preload("res://scripts/data/StoryProgressState.gd")
const PolicyStateScript := preload("res://scripts/data/PolicyState.gd")
const ReportStateScript := preload("res://scripts/data/ReportState.gd")
const SettlementEventStateScript := preload("res://scripts/data/SettlementEventState.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const DivingEquipmentStateScript := preload("res://scripts/data/DivingEquipmentState.gd")
const DayPlanStateScript := preload("res://scripts/data/DayPlanState.gd")
const UnderwaterMapSceneCompilerScript := preload("res://underwater_map_workbench/runtime/UnderwaterMapSceneCompiler.gd")
const WeatherStateScript := preload("res://scripts/data/WeatherState.gd")
const WeatherSystemScript := preload("res://scripts/base/WeatherSystem.gd")
const MissionProgressStateScript := preload("res://scripts/data/MissionProgressState.gd")
const PressureStateScript := preload("res://scripts/data/PressureState.gd")
const DiseaseCampaignStateScript := preload("res://scripts/data/DiseaseCampaignState.gd")
const DifficultyDirectorScript := preload("res://scripts/base/DifficultyDirector.gd")
const PersistenceValidatorScript := preload("res://scripts/data/GameStatePersistenceValidator.gd")
const TutorialDirectorScript := preload("res://scripts/core/TutorialDirector.gd")

@export var format_revision: int = GameFormatScript.CAMPAIGN_FORMAT_REVISION
@export var campaign_id: String = ""
@export var created_at: String = ""
@export var last_saved_at: String = ""
@export var day: int = 1
@export var seed: int = 1
@export var current_phase: int = GamePhaseScript.Phase.MAIN_MENU
@export var difficulty_profile: Resource
@export var resources: Resource = ResourceStorageScript.new()
@export var survivors: Array = []
@export var buildings: Array = []
@export var platform: Resource = PlatformStateScript.new()
@export var underwater_world: Resource = UnderwaterWorldStateScript.new()
@export var story_flags: Resource = StoryProgressStateScript.new()
@export var active_policies: Resource = PolicyStateScript.new()
@export var pending_settlement_event: Resource
@export var settlement_event_history: Array = []
@export var settlement_event_roll_day: int = 0
@export var weather: Resource = WeatherStateScript.new()
@export var pressure_state: Resource = PressureStateScript.new()
@export var last_morning_report: Resource
@export var last_end_day_report: Resource
@export var end_day_report_history: Array = []
@export var last_dive_result: Resource
@export var current_expedition_setup: Resource
@export var tutorial: Resource = TutorialStateScript.new()
@export var diving_equipment: Resource = DivingEquipmentStateScript.new()
@export var current_day_plan: Resource = DayPlanStateScript.new()
@export var preferred_diver_id: String = ""
@export var mission_progress: Resource = MissionProgressStateScript.new()
@export var disease_campaign: Resource = DiseaseCampaignStateScript.new()


func _campaign_profile_snapshot(source) -> Resource:
	var candidate = source if source != null else DifficultyProfileScript.new()
	if candidate != null and candidate.has_method("is_valid") and candidate.is_valid() and candidate.has_method("create_campaign_snapshot"):
		var snapshot = candidate.create_campaign_snapshot()
		if snapshot != null and snapshot.has_method("is_valid") and snapshot.is_valid():
			return snapshot
	var fallback = DifficultyProfileScript.new()
	return fallback.create_campaign_snapshot()


func setup_new_campaign(campaign_seed: int = 0, profile = null, map_compiler = null) -> PackedStringArray:
	format_revision = GameFormatScript.CAMPAIGN_FORMAT_REVISION
	campaign_id = "%d-%d" % [int(Time.get_unix_time_from_system()), randi()]
	created_at = Time.get_datetime_string_from_system(true)
	last_saved_at = ""
	day = 1
	seed = campaign_seed if campaign_seed > 0 else int(Time.get_unix_time_from_system())
	current_phase = GamePhaseScript.Phase.BASE_PLANNING
	difficulty_profile = _campaign_profile_snapshot(profile)
	resources = ResourceStorageScript.new()
	resources.setup_defaults(difficulty_profile)
	TutorialDirectorScript.new().apply_starting_supply_package(self)
	platform = PlatformStateScript.new()
	platform.setup_starting_slots()
	underwater_world = UnderwaterWorldStateScript.new()
	underwater_world.setup(seed)
	var resolved_map_compiler = map_compiler if map_compiler != null else UnderwaterMapSceneCompilerScript.new()
	if resolved_map_compiler == null or not resolved_map_compiler.has_method("generate"):
		return PackedStringArray(["Kompilator sceny mapy nie udostępnia operacji generate()."])
	var map_errors: PackedStringArray = resolved_map_compiler.generate(underwater_world, seed)
	if not map_errors.is_empty():
		return map_errors
	story_flags = StoryProgressStateScript.new()
	active_policies = PolicyStateScript.new()
	pending_settlement_event = null
	settlement_event_history = []
	settlement_event_roll_day = 0
	prepare_weather_for_day(day)
	last_morning_report = _create_starting_report()
	last_end_day_report = null
	end_day_report_history = []
	last_dive_result = null
	current_expedition_setup = null
	tutorial = TutorialStateScript.new()
	diving_equipment = DivingEquipmentStateScript.new()
	diving_equipment.setup_defaults()
	preferred_diver_id = ""
	mission_progress = MissionProgressStateScript.new()
	disease_campaign = DiseaseCampaignStateScript.new()
	_setup_starting_survivors()
	_setup_starting_buildings()
	prepare_pressure_for_day(null, null)
	begin_new_day_plan()
	return PackedStringArray()

func load_validation_errors() -> PackedStringArray:
	if int(format_revision) != GameFormatScript.CAMPAIGN_FORMAT_REVISION:
		return PackedStringArray(["Ten zapis nie należy do bieżącego formatu kampanii."])
	var structural_errors := PersistenceValidatorScript.preflight_errors(self)
	if not structural_errors.is_empty():
		return structural_errors
	var map_errors := UnderwaterMapSceneCompilerScript.new().ensure_world_is_current(underwater_world)
	if not map_errors.is_empty():
		return map_errors
	# The map refresh above already compiled and compared the authoritative source.
	# Continue with the aggregate checks without compiling that source a second time.
	return PersistenceValidatorScript.validation_errors_after_map_refresh(self)


func archive_end_day_report(report) -> bool:
	if not _is_valid_end_day_report(report):
		return false
	end_day_report_history.append(report.duplicate(true))
	_normalize_end_day_report_history()
	return true


func _normalize_end_day_report_history() -> void:
	var reports_by_day: Dictionary = {}
	for candidate in end_day_report_history:
		if not _is_valid_end_day_report(candidate):
			continue
		reports_by_day[int(candidate.day)] = candidate.duplicate(true)

	var report_days: Array = reports_by_day.keys()
	report_days.sort()
	var first_index := maxi(report_days.size() - MAX_END_DAY_REPORT_HISTORY, 0)
	var normalized: Array = []
	for index in range(first_index, report_days.size()):
		normalized.append(reports_by_day[report_days[index]])
	end_day_report_history = normalized
func _is_valid_end_day_report(report) -> bool:
	return (
		report != null
		and report is Resource
		and report.get_script() == ReportStateScript
		and int(report.day) > 0
		and int(report.day) < day
	)


func day_plan_edit_blocker() -> String:
	match current_phase:
		GamePhaseScript.Phase.END_DAY_REPORT:
			return "Najpierw potwierdź obowiązkowe podsumowanie zakończonego dnia."
		GamePhaseScript.Phase.DAY_RESOLUTION:
			return "Plan dnia jest rozliczany i nie można go teraz zmieniać."
		GamePhaseScript.Phase.GAME_OVER:
			return "Kampania jest zakończona porażką."
		GamePhaseScript.Phase.ENDING:
			return "Najpierw zakończ bieżące podsumowanie kampanii."
	if has_pending_settlement_event():
		return "Najpierw rozstrzygnij oczekujące wydarzenie poranka."
	if current_day_plan != null and bool(current_day_plan.locked):
		return "Plan dnia został już zatwierdzony i zablokowany."
	return ""


func can_edit_day_plan() -> bool:
	return day_plan_edit_blocker().is_empty()


func has_pending_settlement_event() -> bool:
	return pending_settlement_event != null and pending_settlement_event.has_method("is_pending") and pending_settlement_event.is_pending()

func lock_day_plan(setup = null) -> bool:
	if current_day_plan == null:
		begin_new_day_plan()
	return current_day_plan.lock_for_resolution(self, setup)

func begin_new_day_plan() -> void:
	_reconcile_preferred_diver()
	current_day_plan = DayPlanStateScript.new()
	current_day_plan.begin_for_state(self)


func set_preferred_diver(survivor_id: String) -> void:
	preferred_diver_id = survivor_id.strip_edges()


func clear_preferred_diver() -> void:
	preferred_diver_id = ""


func _reconcile_preferred_diver() -> void:
	preferred_diver_id = preferred_diver_id.strip_edges()
	if preferred_diver_id.is_empty():
		return
	var survivor = find_survivor(preferred_diver_id)
	if survivor == null or not survivor.is_alive():
		preferred_diver_id = ""

func prepare_weather_for_day(target_day: int = -1) -> void:
	var resolved_day := day if target_day < 1 else target_day
	var frequency_multiplier := float(difficulty_profile.storm_frequency_multiplier) if difficulty_profile != null and difficulty_profile.has_method("create_campaign_snapshot") else 1.0
	weather = WeatherSystemScript.new().build_weather(seed, resolved_day, frequency_multiplier)


func prepare_pressure_for_day(previous_pressure: Resource = null, resolved_dive_result: Resource = null) -> void:
	pressure_state = DifficultyDirectorScript.new().build_for_day(self, previous_pressure, resolved_dive_result)
	if pressure_state != null and bool(pressure_state.tutorial_protected) and pressure_state.has_method("commit_quiet_morning"):
		pressure_state.commit_quiet_morning()


func persistence_validation_errors() -> PackedStringArray:
	return PersistenceValidatorScript.validation_errors(self)


func get_alive_survivors() -> Array:
	var result: Array = []
	for survivor in survivors:
		if survivor != null and survivor.is_alive():
			result.append(survivor)
	return result

func find_survivor(id: String):
	for survivor in survivors:
		if survivor != null and survivor.id == id:
			return survivor
	return null

func find_building(id: String):
	for building in buildings:
		if building != null and building.id == id:
			return building
	return null

func find_building_by_definition(definition_id: String):
	for building in buildings:
		if building != null and building.definition_id == definition_id:
			return building
	return null

func get_food_days_left() -> float:
	var alive_count = max(get_alive_survivors().size(), 1)
	var food_per_adult = difficulty_profile.food_per_adult if difficulty_profile != null and difficulty_profile.has_method("create_campaign_snapshot") else 4
	return float(resources.get_amount(ResourceIdsScript.FOOD)) / float(alive_count * food_per_adult)

func _setup_starting_survivors() -> void:
	survivors = [
		_create_survivor("mira", "Mira Boruta", "rybak", "Lowi sprawniej i dobrze zna rytm wody.", "czujna", "zle znosi zamkniecie"),
		_create_survivor("anka", "Anka Ryl", "mechanik", "Naprawiala windy zanim miasto utonelo.", "dokladna", "uparta"),
		_create_survivor("igor", "Igor Sowa", "nurek", "Pierwszy schodzil pod platforme po zapasy.", "odwazny", "ryzykuje za duzo"),
	]

func _setup_starting_buildings() -> void:
	buildings = []

func _create_survivor(id: String, display_name: String, profession: String, biography: String, positive_trait: String, negative_trait: String):
	var survivor = SurvivorStateScript.new()
	survivor.id = id
	survivor.display_name = display_name
	survivor.profession = profession
	survivor.biography = biography
	survivor.positive_trait = positive_trait
	survivor.negative_trait = negative_trait
	survivor.portrait_id = id
	survivor.ensure_compatibility()
	return survivor

func _create_starting_report():
	var report = ReportStateScript.new()
	report.title = "Dzień 1"
	report.day = 1
	report.add_entry("Mira, Anka i Igor znaleźli opuszczoną platformę serwisową. Nazwali ją Przystanią.")
	report.add_entry("Pierwszym zadaniem jest odbudowa Stacji Nurkowej.")
	report.add_warning("Bez dostępu do głębin Przystań szybko zużyje ostatnie zapasy.")
	return report
