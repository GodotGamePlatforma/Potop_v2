class_name DiveProgressionProfile
extends Resource


const ALLOWED_STORY_ACCESS_IDS: Array[String] = [
	"rescue_knife_unlocked",
	"archive_terminal_active",
	"r3_regulator_ready",
	"r3_generator_active",
	"c4_switchboard_active",
	"common_line_splitter_ready",
	"common_line_splitter_installed",
]
const DIVING_GEAR_DIRECTORY := "res://data/diving_gear"
const WORKSHOP_RECIPE_DIRECTORY := "res://data/workshop_recipes"

@export var profile_id: StringName = &""
@export var display_name: String = ""
@export_range(1, 1000000, 1) var campaign_day: int = 1
@export_range(1, 4, 1) var station_level: int = 1
@export_range(0, 4, 1) var workshop_level: int = 0
@export var diver_id: String = "igor"
@export var oxygen_tank_id: String = "oxygen_tank_mk1"
@export var light_id: String = "diving_lantern_mk1"
@export var weapon_id: String = ""
@export var support_worker_ids: Array[String] = []
@export var placed_buoy_ids: Array[String] = []
@export var opened_shortcut_ids: Array[String] = []
@export var activated_fixed_device_ids: Array[String] = []
@export var start_entry_point: String = "R1-00"
@export var story_access_ids: Array[String] = []


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if str(profile_id).strip_edges().is_empty():
		errors.append("profile_id must not be empty")
	if display_name.strip_edges().is_empty():
		errors.append("display_name must not be empty")
	if campaign_day < 1:
		errors.append("campaign_day must be at least 1")
	if station_level < 1 or station_level > 4:
		errors.append("station_level must be between 1 and 4")
	if workshop_level < 0 or workshop_level > 4:
		errors.append("workshop_level must be between 0 and 4")
	if diver_id.strip_edges().is_empty():
		errors.append("diver_id must not be empty")
	_validate_gear_legality(errors, oxygen_tank_id, "oxygen_tank_id", "oxygen_tank", false)
	_validate_gear_legality(errors, light_id, "light_id", "light", false)
	_validate_gear_legality(errors, weapon_id, "weapon_id", "weapon", true)
	if start_entry_point.strip_edges().is_empty():
		errors.append("start_entry_point must not be empty")
	if station_level < 4 and start_entry_point != "R1-00":
		errors.append("non-primary entry requires Diving Station IV")
	if start_entry_point != "R1-00" and placed_buoy_ids.is_empty():
		errors.append("non-primary entry requires a previously placed buoy")
	_validate_unique_ids(errors, support_worker_ids, "support_worker_ids")
	_validate_unique_ids(errors, placed_buoy_ids, "placed_buoy_ids")
	_validate_unique_ids(errors, opened_shortcut_ids, "opened_shortcut_ids")
	_validate_unique_ids(errors, activated_fixed_device_ids, "activated_fixed_device_ids")
	_validate_unique_ids(errors, story_access_ids, "story_access_ids")
	for access_id in story_access_ids:
		if access_id not in ALLOWED_STORY_ACCESS_IDS:
			errors.append("unknown story access id: %s" % access_id)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func _validate_gear_legality(
	errors: PackedStringArray,
	gear_id: String,
	field_name: String,
	expected_slot: String,
	optional: bool
) -> void:
	var normalized_id := gear_id.strip_edges()
	if normalized_id.is_empty():
		if not optional:
			errors.append("%s must not be empty" % field_name)
		return
	var gear_path := DIVING_GEAR_DIRECTORY.path_join("%s.tres" % normalized_id)
	var gear = ResourceLoader.load(gear_path) if ResourceLoader.exists(gear_path) else null
	if gear == null or str(gear.get("id")) != normalized_id:
		errors.append("%s references unknown diving gear %s" % [field_name, normalized_id])
		return
	if str(gear.get("equipment_slot")) != expected_slot:
		errors.append("%s must reference gear from slot %s" % [field_name, expected_slot])
		return
	if bool(gear.get("is_emergency_default")):
		return
	var recipe_path := WORKSHOP_RECIPE_DIRECTORY.path_join("%s.tres" % normalized_id)
	var recipe = ResourceLoader.load(recipe_path) if ResourceLoader.exists(recipe_path) else null
	if recipe == null or str(recipe.get("output_gear_id")) != normalized_id:
		errors.append("%s has no legal Workshop acquisition recipe" % field_name)
		return
	var required_level := int(recipe.get("required_workshop_level"))
	if workshop_level < required_level:
		errors.append(
			"%s requires Workshop level %d, configured level is %d"
			% [field_name, required_level, workshop_level]
		)


func _validate_unique_ids(errors: PackedStringArray, values: Array[String], field_name: String) -> void:
	var seen: Dictionary = {}
	for value in values:
		var normalized := value.strip_edges()
		if normalized.is_empty():
			errors.append("%s must not contain empty ids" % field_name)
		elif seen.has(normalized):
			errors.append("%s contains duplicate id %s" % [field_name, normalized])
		else:
			seen[normalized] = true
