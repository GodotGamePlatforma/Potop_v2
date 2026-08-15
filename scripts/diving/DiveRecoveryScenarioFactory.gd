class_name DiveRecoveryScenarioFactory
extends RefCounted


const GameStateScript := preload("res://scripts/data/GameState.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const ExpeditionPreparationSystemScript := preload("res://scripts/base/ExpeditionPreparationSystem.gd")
const CampaignProgressionSystemScript := preload("res://scripts/base/CampaignProgressionSystem.gd")
const ProgressionProfileScript := preload("res://scripts/definitions/DiveProgressionProfile.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const PersistenceValidatorScript := preload("res://scripts/data/GameStatePersistenceValidator.gd")

const VALIDATION_SEED := 72_056
const DIVING_STATION_DEFINITION_PATH := "res://data/buildings/diving_station.tres"
const ITEM_DEFINITIONS_PATH := "res://data/items"
const MINIMUM_FIXED_DEVICE_COMPLETION_DAY: Dictionary = {
	"junction_j7": 3,
	"archive_terminal": 4,
	"r3_diagnostic_panel": 5,
	"r3_generator": 8,
	"c4_switchboard": 9,
	"c4_splitter_mount": 12,
}
const MINIMUM_STORY_ACCESS_DAY: Dictionary = {
	"rescue_knife_unlocked": 3,
	"archive_terminal_active": 4,
	"r3_regulator_ready": 7,
	"r3_generator_active": 8,
	"c4_switchboard_active": 9,
	"common_line_splitter_ready": 11,
	"common_line_splitter_installed": 12,
}


func build(progression_profile, difficulty_profile) -> Dictionary:
	var errors := PackedStringArray()
	if progression_profile == null or progression_profile.get_script() != ProgressionProfileScript:
		errors.append("progression profile has the wrong type")
	elif not progression_profile.is_valid():
		errors.append_array(progression_profile.validation_errors())
	if difficulty_profile == null or difficulty_profile.get_script() != DifficultyProfileScript:
		errors.append("difficulty profile has the wrong type")
	elif not difficulty_profile.is_valid():
		errors.append("difficulty profile is invalid")
	if not errors.is_empty():
		return {"errors": errors}

	var state = GameStateScript.new()
	state.setup_new_campaign(VALIDATION_SEED, difficulty_profile)
	state.day = int(progression_profile.campaign_day)
	state.prepare_weather_for_day(state.day)
	state.begin_new_day_plan()
	state.tutorial.complete()
	_validate_world_access(state, progression_profile, errors)
	if not errors.is_empty():
		return {"errors": errors}

	var station_definition = ResourceLoader.load(DIVING_STATION_DEFINITION_PATH)
	if station_definition == null:
		return {"errors": PackedStringArray(["diving station definition is missing"])}
	var station = _build_station(state, progression_profile, errors)
	if station == null:
		return {"errors": errors}
	state.buildings = [station]
	if int(progression_profile.workshop_level) > 0:
		state.buildings.append(_build_workshop(int(progression_profile.workshop_level)))
	state.current_day_plan.sync_from_state(state)

	_apply_story_access(state, progression_profile.story_access_ids)
	_apply_persistent_access(state, progression_profile)
	_materialize_story_prerequisites(state)
	var story_errors: Array[String] = []
	PersistenceValidatorScript._validate_story(story_errors, state, {})
	if not story_errors.is_empty():
		for story_error in story_errors:
			errors.append("illegal story checkpoint: %s" % story_error)
		return {"errors": errors}
	if not _apply_equipment(state, progression_profile, errors):
		return {"errors": errors}

	var item_definitions := _load_item_definitions(errors)
	if not errors.is_empty():
		return {"errors": errors}
	var setup = ExpeditionPreparationSystemScript.new().build_setup(
		state,
		station,
		station_definition,
		item_definitions
	)
	if setup == null:
		errors.append("ExpeditionPreparationSystem rejected the legal validation scenario")
		return {"errors": errors}
	if str(setup.start_entry_point) != str(progression_profile.start_entry_point):
		errors.append(
			"ExpeditionPreparationSystem resolved entry %s instead of requested %s"
			% [str(setup.start_entry_point), str(progression_profile.start_entry_point)]
		)
		return {"errors": errors}
	return {
		"errors": errors,
		"state": state,
		"station": station,
		"setup": setup,
		"progression_profile": progression_profile,
		"difficulty_profile": state.difficulty_profile,
		"item_definitions": item_definitions,
	}


func _validate_world_access(state, profile, errors: PackedStringArray) -> void:
	if state == null or state.underwater_world == null or state.underwater_world.blueprint == null:
		errors.append("validation scenario has no compiled underwater blueprint")
		return
	var blueprint = state.underwater_world.blueprint
	var buoy_entry_by_id: Dictionary = {}
	for buoy in blueprint.buoy_spawns:
		buoy_entry_by_id[str(buoy.get("id", ""))] = str(buoy.get("entry_landmark_id", ""))
	var available_entry_ids: Dictionary = {str(blueprint.entry_landmark_id): true}
	for buoy_id in profile.placed_buoy_ids:
		if not buoy_entry_by_id.has(buoy_id):
			errors.append("placed_buoy_ids references unknown buoy %s" % buoy_id)
			continue
		available_entry_ids[str(buoy_entry_by_id[buoy_id])] = true
	var requested_entry := str(profile.start_entry_point)
	if not blueprint.landmark_lookup.has(requested_entry):
		errors.append("start_entry_point references unknown landmark %s" % requested_entry)
	elif not available_entry_ids.has(requested_entry):
		errors.append("start_entry_point %s has no previously placed matching buoy" % requested_entry)

	var shortcut_ids: Dictionary = {}
	for shortcut in blueprint.shortcut_spawns:
		shortcut_ids[str(shortcut.get("id", ""))] = true
	for shortcut_id in profile.opened_shortcut_ids:
		if not shortcut_ids.has(shortcut_id):
			errors.append("opened_shortcut_ids references unknown shortcut %s" % shortcut_id)

	var fixed_device_ids: Dictionary = {}
	for fixed_device in blueprint.fixed_device_spawns:
		fixed_device_ids[str(fixed_device.get("id", ""))] = true
	for fixed_device_id in profile.activated_fixed_device_ids:
		if not fixed_device_ids.has(fixed_device_id):
			errors.append("activated_fixed_device_ids references unknown fixed device %s" % fixed_device_id)
		elif int(profile.campaign_day) < int(MINIMUM_FIXED_DEVICE_COMPLETION_DAY.get(fixed_device_id, 1)):
			errors.append(
				"fixed device %s cannot be completed before campaign day %d"
				% [fixed_device_id, int(MINIMUM_FIXED_DEVICE_COMPLETION_DAY[fixed_device_id])]
			)
	for story_access_id in profile.story_access_ids:
		var minimum_day := int(MINIMUM_STORY_ACCESS_DAY.get(story_access_id, 1))
		if int(profile.campaign_day) < minimum_day:
			errors.append(
				"story access %s cannot be available before campaign day %d"
				% [story_access_id, minimum_day]
			)


func _build_station(state, profile, errors: PackedStringArray):
	var diver = state.find_survivor(str(profile.diver_id))
	if diver == null:
		errors.append("unknown diver id: %s" % str(profile.diver_id))
		return null
	var station = BuildingStateScript.new()
	station.id = "validation_diving_station"
	station.definition_id = "diving_station"
	station.slot_id = "validation_edge"
	station.level = int(profile.station_level)
	station.condition = 100
	station.is_built = true
	station.pending_level = 0
	# The diver is selected by the editable day plan and must stay free of the
	# shared Station roster.  Support workers use the ordinary worker slots.
	state.current_day_plan.selected_diver_id = str(diver.id)

	var maximum_workers := int(ResourceLoader.load(DIVING_STATION_DEFINITION_PATH).get_level_definition(station.level).worker_slots)
	for support_id in profile.support_worker_ids:
		if station.assigned_survivor_ids.size() >= maximum_workers:
			errors.append("support workers exceed Diving Station worker slots")
			break
		var support = state.find_survivor(str(support_id))
		if support == null or str(support.id) == str(diver.id):
			errors.append("invalid support worker id: %s" % str(support_id))
			continue
		support.current_assignment = station.id
		station.assigned_survivor_ids.append(str(support.id))
	return station if errors.is_empty() else null


func _build_workshop(level: int):
	var workshop = BuildingStateScript.new()
	workshop.id = "validation_workshop"
	workshop.definition_id = "workshop"
	workshop.slot_id = "validation_interior"
	workshop.level = level
	workshop.condition = 100
	workshop.is_built = true
	workshop.pending_level = 0
	return workshop


func _apply_story_access(state, access_ids: Array[String]) -> void:
	if state.story_flags == null:
		return
	for access_id in access_ids:
		state.story_flags.set(access_id, true)
		state.story_flags.set_flag(access_id, true)


func _apply_persistent_access(state, profile) -> void:
	var delta = state.underwater_world.delta
	delta.placed_buoys.assign(profile.placed_buoy_ids)
	delta.opened_shortcuts.assign(profile.opened_shortcut_ids)
	delta.activated_fixed_devices.assign(profile.activated_fixed_device_ids)
	state.current_day_plan.expedition_entry_point = str(profile.start_entry_point)


func _materialize_story_prerequisites(state) -> void:
	## Validation profiles represent legal campaign checkpoints, not a loose
	## collection of tools. Mirror the typed story state and its persistence
	## timestamps for every already completed fixed device.
	var story = state.story_flags
	if story == null:
		return
	var completed: Array[String] = state.underwater_world.delta.activated_fixed_devices
	if completed.has("junction_j7"):
		story.junction_j7_active = true
		story.rescue_knife_unlocked = true
		story.junction_j7_activated_day = mini(3, int(state.day))
		story.set_flag("junction_j7_active", true)
		story.set_flag("rescue_knife_unlocked", true)
		_materialize_black_front_countdown(state)
	if completed.has("archive_terminal"):
		story.archive_terminal_active = true
		story.archive_map_transmitted = true
		story.archive_terminal_activated_day = mini(4, int(state.day))
		story.set_flag("archive_terminal_active", true)
	if completed.has("r3_diagnostic_panel"):
		story.r3_diagnosed = true
		story.r3_diagnosed_day = mini(5, int(state.day))
		story.set_flag("r3_diagnosed", true)
	if story.r3_regulator_ready:
		story.r3_regulator_completed_day = mini(7, int(state.day))
		story.set_flag("r3_regulator_ready", true)
	if completed.has("r3_generator"):
		story.r3_regulator_ready = true
		story.r3_regulator_completed_day = mini(7, int(state.day))
		story.set_flag("r3_regulator_ready", true)
		story.r3_generator_active = true
		story.r3_generator_activated_day = mini(8, int(state.day))
		story.set_flag("r3_generator_active", true)
	if completed.has("c4_switchboard"):
		story.c4_switchboard_active = true
		story.c4_switchboard_activated_day = mini(9, int(state.day))
		story.set_flag("c4_switchboard_active", true)
	if story.common_line_splitter_ready:
		story.common_line_splitter_completed_day = mini(11, int(state.day))
		story.set_flag("common_line_splitter_ready", true)
	if completed.has("c4_splitter_mount"):
		story.common_line_splitter_ready = true
		story.common_line_splitter_completed_day = mini(11, int(state.day))
		story.common_line_splitter_installed = true
		story.common_line_splitter_installed_day = mini(12, int(state.day))
		story.set_flag("common_line_splitter_ready", true)
		story.set_flag("common_line_splitter_installed", true)


func _materialize_black_front_countdown(state) -> void:
	var story = state.story_flags
	var started_day := int(story.junction_j7_activated_day)
	var total_days := CampaignProgressionSystemScript.new().black_front_days_for_profile(state.difficulty_profile)
	# A validation profile represents the beginning of its campaign day. The day
	# currently being planned has not advanced the countdown yet.
	var completed_days_after_j7 := maxi(int(state.day) - started_day - 1, 0)
	story.black_front_days_total = total_days
	story.black_front_days_remaining = maxi(total_days - completed_days_after_j7, 0)
	story.black_front_started_day = started_day
	story.black_front_last_advanced_day = started_day + mini(completed_days_after_j7, total_days)
	story.black_front_active = story.black_front_days_remaining > 0
	story.black_front_arrived = not story.black_front_active
	story.set_flag("black_front_countdown_started", true)
	story.set_flag("black_front_arrived", story.black_front_arrived)


func _apply_equipment(state, profile, errors: PackedStringArray) -> bool:
	var requested_gear: Array[String] = [str(profile.oxygen_tank_id), str(profile.light_id)]
	if not str(profile.weapon_id).is_empty():
		requested_gear.append(str(profile.weapon_id))
	for gear_id in requested_gear:
		var path := "res://data/diving_gear/%s.tres" % gear_id
		var definition = ResourceLoader.load(path) if ResourceLoader.exists(path) else null
		if definition == null or str(definition.equipment_slot).is_empty():
			errors.append("unknown diving gear id: %s" % gear_id)
			continue
		state.diving_equipment.add_gear(gear_id)
		if not state.diving_equipment.equip(str(definition.equipment_slot), gear_id):
			errors.append("could not equip diving gear id: %s" % gear_id)
	return errors.is_empty()


func _load_item_definitions(errors: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for file_name in DirAccess.get_files_at(ITEM_DEFINITIONS_PATH):
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var path := ITEM_DEFINITIONS_PATH.path_join(file_name)
		var definition = ResourceLoader.load(path)
		if definition == null or str(definition.get("id")).is_empty():
			errors.append("invalid item definition: %s" % path)
			continue
		result[str(definition.get("id"))] = definition
	return result
