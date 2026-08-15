class_name StoryProgressState
extends Resource

const ACT_COMMON_LINE := 1
const ACT_EPILOGUE := 2

@export var flags: Dictionary = {}
@export_range(ACT_COMMON_LINE, ACT_EPILOGUE) var act: int = ACT_COMMON_LINE
@export var crisis_active: bool = false
@export var crisis_days_remaining: int = 0
@export var crisis_started_day: int = 0
@export var game_over_reason: String = ""
@export var game_over_day: int = 0
@export var successful_dives: int = 0
@export var diver_deaths: int = 0
@export var rescued_survivor_count: int = 0
@export var junction_j7_active: bool = false
@export var rescue_knife_unlocked: bool = false
@export var junction_j7_activated_day: int = 0
@export var archive_terminal_active: bool = false
@export var archive_map_transmitted: bool = false
@export var archive_terminal_activated_day: int = 0
@export var r3_diagnosed: bool = false
@export var r3_diagnosed_day: int = 0
@export var r3_regulator_ready: bool = false
@export var r3_regulator_completed_day: int = 0
@export var r3_generator_active: bool = false
@export var r3_generator_activated_day: int = 0
@export var c4_switchboard_active: bool = false
@export var c4_switchboard_activated_day: int = 0
@export var common_line_splitter_ready: bool = false
@export var common_line_splitter_completed_day: int = 0
@export var common_line_splitter_installed: bool = false
@export var common_line_splitter_installed_day: int = 0
@export var black_front_active: bool = false
@export var black_front_days_total: int = 0
@export var black_front_days_remaining: int = 0
@export var black_front_started_day: int = 0
@export var black_front_last_advanced_day: int = 0
@export var black_front_arrived: bool = false
@export var energy_choice_pending: bool = false
@export var energy_configuration: String = ""
@export var final_outcome_id: String = ""
@export var final_resolved_day: int = 0
@export var north_platform_survived: bool = false
@export var final_summary: Dictionary = {}
@export var first_full_integrity_day: int = 0
@export var full_integrity_days: int = 0
@export var final_chronicle_continued: bool = false
@export var chronicle_summary: Dictionary = {}

func set_flag(flag: String, value: bool = true) -> void:
	flags[flag] = value

func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))

func ensure_compatibility() -> void:
	act = clampi(act, ACT_COMMON_LINE, ACT_EPILOGUE)
	crisis_days_remaining = maxi(crisis_days_remaining, 0)
	crisis_started_day = maxi(crisis_started_day, 0)
	game_over_day = maxi(game_over_day, 0)
	successful_dives = maxi(successful_dives, 0)
	diver_deaths = maxi(diver_deaths, 0)
	rescued_survivor_count = maxi(rescued_survivor_count, 0)
	junction_j7_activated_day = maxi(junction_j7_activated_day, 0)
	archive_terminal_activated_day = maxi(archive_terminal_activated_day, 0)
	r3_diagnosed_day = maxi(r3_diagnosed_day, 0)
	r3_regulator_completed_day = maxi(r3_regulator_completed_day, 0)
	r3_generator_activated_day = maxi(r3_generator_activated_day, 0)
	c4_switchboard_activated_day = maxi(c4_switchboard_activated_day, 0)
	common_line_splitter_completed_day = maxi(common_line_splitter_completed_day, 0)
	common_line_splitter_installed_day = maxi(common_line_splitter_installed_day, 0)
	if archive_terminal_active:
		archive_map_transmitted = true
	black_front_days_total = maxi(black_front_days_total, 0)
	black_front_days_remaining = clampi(black_front_days_remaining, 0, black_front_days_total)
	black_front_started_day = maxi(black_front_started_day, 0)
	black_front_last_advanced_day = maxi(black_front_last_advanced_day, 0)
	final_resolved_day = maxi(final_resolved_day, 0)
	first_full_integrity_day = maxi(first_full_integrity_day, 0)
	full_integrity_days = maxi(full_integrity_days, 0)
	if final_chronicle_continued:
		act = ACT_EPILOGUE
