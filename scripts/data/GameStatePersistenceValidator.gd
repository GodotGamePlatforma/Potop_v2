class_name GameStatePersistenceValidator
extends RefCounted

## Structural and aggregate validation for the campaign persistence boundary.
##
## `preflight_errors()` deliberately performs no domain calls on nested
## resources.  It only confirms their exact scripts and the collection shapes
## needed by the load boundary. `validation_errors()` runs only after the
## resource graph has been confirmed safe to inspect.

const MAX_END_DAY_REPORT_HISTORY := 7

const GameFormatScript := preload("res://scripts/data/GameFormat.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const ResourceStorageScript := preload("res://scripts/data/ResourceStorage.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const CompetencySystemScript := preload("res://scripts/survivors/CompetencySystem.gd")
const CareerProgressionSystemScript := preload("res://scripts/survivors/CareerProgressionSystem.gd")
const ProfessionTalentSystemScript := preload("res://scripts/survivors/ProfessionTalentSystem.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const PlatformStateScript := preload("res://scripts/data/PlatformState.gd")
const UnderwaterWorldStateScript := preload("res://scripts/data/UnderwaterWorldState.gd")
const WorldBlueprintScript := preload("res://scripts/data/WorldBlueprint.gd")
const WorldDeltaScript := preload("res://scripts/data/WorldDelta.gd")
const StoryProgressStateScript := preload("res://scripts/data/StoryProgressState.gd")
const PolicyStateScript := preload("res://scripts/data/PolicyState.gd")
const SettlementEventStateScript := preload("res://scripts/data/SettlementEventState.gd")
const WeatherStateScript := preload("res://scripts/data/WeatherState.gd")
const PressureStateScript := preload("res://scripts/data/PressureState.gd")
const ReportStateScript := preload("res://scripts/data/ReportState.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const DivingEquipmentStateScript := preload("res://scripts/data/DivingEquipmentState.gd")
const DayPlanStateScript := preload("res://scripts/data/DayPlanState.gd")
const MissionProgressStateScript := preload("res://scripts/data/MissionProgressState.gd")
const WorkshopOrderStateScript := preload("res://scripts/data/WorkshopOrderState.gd")
const DiseaseCaseStateScript := preload("res://scripts/data/DiseaseCaseState.gd")
const DiseaseExposureStateScript := preload("res://scripts/data/DiseaseExposureState.gd")
const DiseaseCampaignStateScript := preload("res://scripts/data/DiseaseCampaignState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const DifficultyMathScript := preload("res://scripts/core/DifficultyMath.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const GameDatabaseScript := preload("res://scripts/core/GameDatabase.gd")
const MapSceneCompilerScript := preload("res://underwater_map_workbench/runtime/UnderwaterMapSceneCompiler.gd")

const OFFER_SNAPSHOT_SCRIPT_PATH := "res://scripts/data/SettlementEventOfferSnapshot.gd"
const CHOICE_SNAPSHOT_SCRIPT_PATH := "res://scripts/data/SettlementEventChoiceSnapshot.gd"
const GAME_STATE_SCRIPT_PATH := "res://scripts/data/GameState.gd"
const VALID_GAME_OVER_REASONS: Array[String] = ["settlement_lost", "platform_destroyed", "leadership_collapse", "black_front_unprepared"]
const VALID_PRESSURE_CRITICAL_GATES: Array[String] = [
	"food_below_half_day", "hunger_critical", "hope_critical", "integrity_critical", "workforce_critical", "diver_died_yesterday",
]
const VALID_BLOCKED_IMPACT_TAGS: Array[String] = ["food_cost", "food_demand", "integrity_risk"]
const VALID_PREFERRED_IMPACT_TAGS: Array[String] = [
	"food_relief", "material_relief", "workforce_relief", "population_gain", "hope_relief", "integrity_relief", "medicine_relief",
]

const SLOT_DEFINITIONS := {
	"top_left": {"definition_id": "fishing_hut", "is_edge": true},
	"top_center": {"definition_id": "kitchen", "is_edge": false},
	"top_right": {"definition_id": "community_house", "is_edge": true},
	"bottom_left": {"definition_id": "workshop", "is_edge": true},
	"center": {"definition_id": "infirmary", "is_edge": false},
	"bottom_right": {"definition_id": "diving_station", "is_edge": true},
}

static var _standalone_database = null


static func _game_database():
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var singleton = main_loop.root.get_node_or_null("GameDatabase")
		if singleton != null and not singleton.buildings.is_empty():
			return singleton
	if _standalone_database == null:
		_standalone_database = GameDatabaseScript.new()
		_standalone_database.load_definitions()
	return _standalone_database


static func _release_standalone_database() -> void:
	if _standalone_database == null:
		return
	_standalone_database.free()
	_standalone_database = null


static func preflight_errors(state) -> PackedStringArray:
	var errors: Array[String] = []
	if not _has_script_path(state, GAME_STATE_SCRIPT_PATH):
		errors.append("Korzeń zapisu nie jest dokładnym GameState.")
		return PackedStringArray(errors)

	var format_revision := int(state.format_revision)
	if format_revision != GameFormatScript.CAMPAIGN_FORMAT_REVISION:
		errors.append("Nieobsługiwana rewizja formatu kampanii: %d." % format_revision)
		return PackedStringArray(errors)

	_require_exact(errors, state.difficulty_profile, DifficultyProfileScript, "difficulty_profile")
	_require_exact(errors, state.resources, ResourceStorageScript, "resources")
	_require_exact(errors, state.platform, PlatformStateScript, "platform")
	_require_exact(errors, state.underwater_world, UnderwaterWorldStateScript, "underwater_world")
	_require_exact(errors, state.story_flags, StoryProgressStateScript, "story_flags")
	_require_exact(errors, state.active_policies, PolicyStateScript, "active_policies")
	_require_exact(errors, state.weather, WeatherStateScript, "weather")
	_require_exact(errors, state.tutorial, TutorialStateScript, "tutorial")
	_require_exact(errors, state.diving_equipment, DivingEquipmentStateScript, "diving_equipment")
	_require_exact(errors, state.current_day_plan, DayPlanStateScript, "current_day_plan")
	if typeof(state.preferred_diver_id) != TYPE_STRING:
		errors.append("preferred_diver_id nie jest Stringiem.")

	_require_exact(errors, state.mission_progress, MissionProgressStateScript, "mission_progress")
	_require_exact(errors, state.pressure_state, PressureStateScript, "pressure_state")
	_require_exact(errors, state.disease_campaign, DiseaseCampaignStateScript, "disease_campaign")

	_check_exact_array(errors, state.survivors, SurvivorStateScript, "survivors")
	_check_exact_array(errors, state.buildings, BuildingStateScript, "buildings")
	_check_exact_array(errors, state.settlement_event_history, SettlementEventStateScript, "settlement_event_history")
	_check_exact_array(errors, state.end_day_report_history, ReportStateScript, "end_day_report_history")
	_check_optional_exact(errors, state.pending_settlement_event, SettlementEventStateScript, "pending_settlement_event")
	_check_optional_exact(errors, state.last_morning_report, ReportStateScript, "last_morning_report")
	_check_optional_exact(errors, state.last_end_day_report, ReportStateScript, "last_end_day_report")
	_check_optional_exact(errors, state.last_dive_result, DiveResultScript, "last_dive_result")
	_check_optional_exact(errors, state.current_expedition_setup, ExpeditionSetupScript, "current_expedition_setup")
	if _is_exact(state.last_dive_result, DiveResultScript):
		_check_exact_array(errors, state.last_dive_result.rescued_survivors, SurvivorStateScript, "last_dive_result.rescued_survivors")
		_check_exact_array(errors, state.last_dive_result.disease_exposures, DiseaseExposureStateScript, "last_dive_result.disease_exposures")
		for field_name in ["discovered_sectors", "placed_buoys", "opened_shortcuts", "activated_fixed_devices", "opened_containers", "collected_world_item_ids", "marked_heavy_objects", "recovered_gear_ids", "story_flags_unlocked", "lost_gear", "diver_injuries", "noise_events", "risk_events"]:
			_check_string_array(errors, state.last_dive_result.get(field_name), "last_dive_result.%s" % field_name)
		for field_name in ["remaining_container_contents", "recovered_backpacks", "dropped_loot_updates", "rescue_outcomes"]:
			var nested_records = state.last_dive_result.get(field_name)
			if not (nested_records is Dictionary):
				errors.append("last_dive_result.%s nie jest słownikiem." % field_name)
				continue
			for record_id in nested_records.keys():
				if not (nested_records[record_id] is Dictionary):
					errors.append("last_dive_result.%s[%s] nie jest słownikiem." % [field_name, record_id])

	if _is_exact(state.underwater_world, UnderwaterWorldStateScript):
		_require_exact(errors, state.underwater_world.blueprint, WorldBlueprintScript, "underwater_world.blueprint")
		_require_exact(errors, state.underwater_world.delta, WorldDeltaScript, "underwater_world.delta")
		if _is_exact(state.underwater_world.blueprint, WorldBlueprintScript):
			for field_name in ["regions", "landmarks", "connections", "loot_spawns", "current_zones", "threat_spawns", "heavy_object_spawns", "rescue_spawns", "buoy_spawns", "shortcut_spawns", "obstacle_spawns", "decoration_spawns"]:
				_check_dictionary_array(errors, state.underwater_world.blueprint.get(field_name), "underwater_world.blueprint.%s" % field_name)
		if _is_exact(state.underwater_world.delta, WorldDeltaScript):
			_append_world_delta_preflight(errors, state.underwater_world.delta)
	if _is_exact(state.current_day_plan, DayPlanStateScript):
		_check_optional_exact(errors, state.current_day_plan.expedition_setup, ExpeditionSetupScript, "current_day_plan.expedition_setup")
		_check_dictionary_array(errors, state.current_day_plan.building_orders, "current_day_plan.building_orders")
		for assignment_id in state.current_day_plan.worker_assignments.keys():
			if not (state.current_day_plan.worker_assignments[assignment_id] is Array):
				errors.append("current_day_plan.worker_assignments[%s] nie jest tablicą." % assignment_id)
		if not (state.current_day_plan.building_work_paces is Dictionary):
			errors.append("current_day_plan.building_work_paces nie jest słownikiem.")
		else:
			for building_id_value in state.current_day_plan.building_work_paces.keys():
				if typeof(building_id_value) != TYPE_STRING:
					errors.append("current_day_plan.building_work_paces zawiera klucz, który nie jest Stringiem.")
				if typeof(state.current_day_plan.building_work_paces[building_id_value]) != TYPE_STRING:
					errors.append("current_day_plan.building_work_paces[%s] nie jest Stringiem." % building_id_value)
		_check_string_only_array(errors, state.current_day_plan.medical_priority_survivor_ids, "current_day_plan.medical_priority_survivor_ids")
		_check_string_only_array(errors, state.current_day_plan.isolated_survivor_ids, "current_day_plan.isolated_survivor_ids")
		if typeof(state.current_day_plan.selected_diver_id) != TYPE_STRING:
			errors.append("current_day_plan.selected_diver_id nie jest Stringiem.")

	for building_index in range(state.buildings.size()):
		var building = state.buildings[building_index]
		if not _is_exact(building, BuildingStateScript):
			continue
		_check_string_array(errors, building.assigned_survivor_ids, "buildings[%d].assigned_survivor_ids" % building_index)
		_check_exact_array(errors, building.queued_production_orders, WorkshopOrderStateScript, "buildings[%d].queued_production_orders" % building_index)

	_append_profession_talent_preflight(errors, state)
	_append_event_snapshot_preflight(errors, state)
	_append_disease_preflight(errors, state)
	return PackedStringArray(errors)


static func _append_profession_talent_preflight(errors: Array[String], state) -> void:
	for survivor_index in range(state.survivors.size()):
		var survivor = state.survivors[survivor_index]
		if _is_exact(survivor, SurvivorStateScript):
			_check_dictionary_property(errors, survivor, "profession_talent_ids", "survivors[%d].profession_talent_ids" % survivor_index)
	if _is_exact(state.last_dive_result, DiveResultScript):
		for survivor_index in range(state.last_dive_result.rescued_survivors.size()):
			var survivor = state.last_dive_result.rescued_survivors[survivor_index]
			if _is_exact(survivor, SurvivorStateScript):
				_check_dictionary_property(
					errors,
					survivor,
					"profession_talent_ids",
					"last_dive_result.rescued_survivors[%d].profession_talent_ids" % survivor_index
				)
	if state.pending_settlement_event != null:
		var snapshot = state.pending_settlement_event.get("offer_snapshot")
		if _has_script_path(snapshot, OFFER_SNAPSHOT_SCRIPT_PATH):
			for choice_index in range(snapshot.choices.size()):
				var choice = snapshot.choices[choice_index]
				if not _has_script_path(choice, CHOICE_SNAPSHOT_SCRIPT_PATH):
					continue
				for survivor_index in range(choice.survivor_states.size()):
					var survivor = choice.survivor_states[survivor_index]
					if _is_exact(survivor, SurvivorStateScript):
						_check_dictionary_property(
							errors,
							survivor,
							"profession_talent_ids",
							"offer_snapshot.choices[%d].survivor_states[%d].profession_talent_ids" % [choice_index, survivor_index]
						)
	if _is_exact(state.current_expedition_setup, ExpeditionSetupScript):
		_check_dictionary_property(errors, state.current_expedition_setup, "profession_talent_ids", "current_expedition_setup.profession_talent_ids")
	if _is_exact(state.current_day_plan, DayPlanStateScript) and _is_exact(state.current_day_plan.expedition_setup, ExpeditionSetupScript):
		_check_dictionary_property(errors, state.current_day_plan.expedition_setup, "profession_talent_ids", "current_day_plan.expedition_setup.profession_talent_ids")


static func _append_disease_preflight(errors: Array[String], state) -> void:
	if _is_exact(state.disease_campaign, DiseaseCampaignStateScript):
		_check_exact_array(
			errors,
			state.disease_campaign.pending_exposures,
			DiseaseExposureStateScript,
			"disease_campaign.pending_exposures"
		)
	for survivor_index in range(state.survivors.size()):
		var survivor = state.survivors[survivor_index]
		if _is_exact(survivor, SurvivorStateScript):
			_check_exact_array(errors, survivor.disease_cases, DiseaseCaseStateScript, "survivors[%d].disease_cases" % survivor_index)
	if _is_exact(state.last_dive_result, DiveResultScript):
		for survivor_index in range(state.last_dive_result.rescued_survivors.size()):
			var survivor = state.last_dive_result.rescued_survivors[survivor_index]
			if _is_exact(survivor, SurvivorStateScript):
				_check_exact_array(
					errors,
					survivor.disease_cases,
					DiseaseCaseStateScript,
					"last_dive_result.rescued_survivors[%d].disease_cases" % survivor_index
				)
	if state.pending_settlement_event == null:
		return
	var snapshot = state.pending_settlement_event.get("offer_snapshot")
	if not _has_script_path(snapshot, OFFER_SNAPSHOT_SCRIPT_PATH):
		return
	for choice_index in range(snapshot.choices.size()):
		var choice = snapshot.choices[choice_index]
		if not _has_script_path(choice, CHOICE_SNAPSHOT_SCRIPT_PATH):
			continue
		_check_exact_array(
			errors,
			choice.survivor_states,
			SurvivorStateScript,
			"offer_snapshot.choices[%d].survivor_states" % choice_index
		)
		for survivor_index in range(choice.survivor_states.size()):
			var survivor = choice.survivor_states[survivor_index]
			if _is_exact(survivor, SurvivorStateScript):
				_check_exact_array(
					errors,
					survivor.disease_cases,
					DiseaseCaseStateScript,
					"offer_snapshot.choices[%d].survivor_states[%d].disease_cases" % [choice_index, survivor_index]
				)


static func _append_world_delta_preflight(errors: Array[String], delta) -> void:
	for field_name in ["discovered_landmarks", "discovered_chunks", "opened_containers", "collected_items", "placed_buoys", "marked_heavy_objects", "recovered_heavy_objects", "opened_shortcuts", "activated_fixed_devices", "collapsed_paths"]:
		_check_string_array(errors, delta.get(field_name), "underwater_world.delta.%s" % field_name)
	for container_id in delta.remaining_container_contents.keys():
		if not (delta.remaining_container_contents[container_id] is Dictionary):
			errors.append("remaining_container_contents[%s] nie jest słownikiem." % container_id)
	for field_name in ["lost_backpacks", "dropped_loot_piles", "rescued_or_dead_survivors"]:
		var records: Dictionary = delta.get(field_name)
		for record_id in records.keys():
			if not (records[record_id] is Dictionary):
				errors.append("underwater_world.delta.%s[%s] nie jest słownikiem." % [field_name, record_id])
				continue
			if field_name in ["lost_backpacks", "dropped_loot_piles"] and not (records[record_id].get("items", {}) is Dictionary):
				errors.append("underwater_world.delta.%s[%s].items nie jest słownikiem." % [field_name, record_id])


static func validation_errors(state) -> PackedStringArray:
	var errors: Array[String] = []
	for preflight_error in preflight_errors(state):
		errors.append(str(preflight_error))
	if not errors.is_empty():
		return PackedStringArray(errors)
	return _validation_errors_after_preflight(state, true)


## Used only by GameState.load_validation_errors() after exact-script preflight
## and ensure_world_is_current() have both succeeded.
static func validation_errors_after_map_refresh(state) -> PackedStringArray:
	return _validation_errors_after_preflight(state, false)


static func _validation_errors_after_preflight(
	state,
	validate_current_scene_snapshot: bool
) -> PackedStringArray:
	var errors: Array[String] = []
	if int(state.format_revision) != GameFormatScript.CAMPAIGN_FORMAT_REVISION:
		errors.append("Walidacja agregatu wymaga rewizji %d, otrzymano %d." % [GameFormatScript.CAMPAIGN_FORMAT_REVISION, state.format_revision])
		return PackedStringArray(errors)

	_validate_root(errors, state)
	_validate_resources(errors, state.resources)
	var profession_talent_system = ProfessionTalentSystemScript.new()
	for catalog_error in profession_talent_system.validation_errors():
		errors.append("Katalog talentów zawodowych: %s" % catalog_error)
	var survivor_by_id := _validate_survivors(errors, state.survivors, profession_talent_system)
	_validate_preferred_diver(errors, state, survivor_by_id)
	_validate_disease_state(errors, state, survivor_by_id)
	var building_by_id := _validate_buildings(errors, state, survivor_by_id)
	_validate_platform(errors, state.platform, building_by_id)
	_validate_story(errors, state, survivor_by_id)
	_validate_policies(errors, state)
	_validate_equipment(errors, state.diving_equipment)
	_validate_world(errors, state, validate_current_scene_snapshot)
	_validate_missions(errors, state)
	_validate_reports(errors, state)
	_validate_weather_and_pressure(errors, state)
	_validate_day_plan(errors, state, survivor_by_id, building_by_id)
	_validate_runtime_snapshots(errors, state, survivor_by_id)
	_validate_workshop_orders(errors, state)
	_validate_events(errors, state, survivor_by_id)
	_validate_morning_commitment(errors, state)
	var result := PackedStringArray(errors)
	_release_standalone_database()
	return result


static func _validate_root(errors: Array[String], state) -> void:
	if str(state.campaign_id).strip_edges().is_empty():
		errors.append("Kampania nie ma campaign_id.")
	if str(state.created_at).strip_edges().is_empty():
		errors.append("Kampania nie ma created_at.")
	if int(state.day) < 1:
		errors.append("Numer dnia kampanii musi być dodatni.")
	if int(state.seed) < 1:
		errors.append("Seed kampanii musi być dodatni.")
	if not GamePhaseScript.LABELS.has(int(state.current_phase)):
		errors.append("Faza kampanii ma nieznaną wartość %d." % int(state.current_phase))
	elif int(state.current_phase) in [GamePhaseScript.Phase.MAIN_MENU, GamePhaseScript.Phase.EXPEDITION_SETUP, GamePhaseScript.Phase.DIVING, GamePhaseScript.Phase.DIVE_RESULT, GamePhaseScript.Phase.DAY_RESOLUTION]:
		errors.append("Przejściowa faza %s nie może być punktem autosave." % GamePhaseScript.label(int(state.current_phase)))
	if state.difficulty_profile == null or not bool(state.difficulty_profile.snapshot_sealed):
		errors.append("Profil trudności kampanii nie jest zamrożoną migawką.")
	elif not state.difficulty_profile.has_valid_configuration_signature():
		errors.append("Podpis konfiguracji trudności jest niepoprawny.")
	for profile_error in state.difficulty_profile.validation_errors():
		errors.append("Profil trudności: %s" % profile_error)


static func _validate_resources(errors: Array[String], storage) -> void:
	var known_ids := ResourceIdsScript.all()
	for resource_id in known_ids:
		if not storage.values.has(resource_id):
			errors.append("Magazyn nie zawiera wymaganego zasobu %s." % resource_id)
	for raw_id in storage.values.keys():
		var resource_id := str(raw_id)
		if not known_ids.has(resource_id):
			errors.append("Magazyn zawiera nieznany zasób %s." % resource_id)
		if typeof(storage.values[raw_id]) != TYPE_INT:
			errors.append("Wartość zasobu %s nie jest liczbą całkowitą." % resource_id)
		elif int(storage.values[raw_id]) < 0:
			errors.append("Wartość zasobu %s jest ujemna." % resource_id)
		elif resource_id in [ResourceIdsScript.HOPE, ResourceIdsScript.PLATFORM_INTEGRITY] and int(storage.values[raw_id]) > 100:
			errors.append("Wartość zasobu %s wykracza poza zakres 0..100." % resource_id)


static func _validate_survivors(errors: Array[String], survivors: Array, profession_talent_system) -> Dictionary:
	var result: Dictionary = {}
	for survivor in survivors:
		var survivor_id := str(survivor.id).strip_edges()
		if survivor_id.is_empty():
			errors.append("Mieszkaniec nie ma ID.")
			continue
		if result.has(survivor_id):
			errors.append("Powtórzone ID mieszkańca: %s." % survivor_id)
			continue
		result[survivor_id] = survivor
		if str(survivor.display_name).strip_edges().is_empty():
			errors.append("Mieszkaniec %s nie ma nazwy." % survivor_id)
		if int(survivor.level) < 1 or int(survivor.level) > SurvivorStateScript.MAX_LEVEL:
			errors.append("Mieszkaniec %s ma niepoprawny poziom." % survivor_id)
		if int(survivor.experience) < 0 or int(survivor.unspent_skill_points) < 0:
			errors.append("Mieszkaniec %s ma ujemny postęp rozwoju." % survivor_id)
		_validate_competencies(errors, survivor.competency_levels, "mieszkańca %s" % survivor_id)
		_validate_profession_talent_map(
			errors,
			survivor.profession_talent_ids,
			[str(survivor.profession), str(survivor.secondary_profession)],
			"mieszkańca %s" % survivor_id,
			profession_talent_system,
			survivor
		)
		if int(survivor.base_max_health) < 1 or int(survivor.health_bonus) < 0:
			errors.append("Mieszkaniec %s ma niepoprawną bazę lub premię zdrowia." % survivor_id)
		if not is_finite(float(survivor.base_oxygen_capacity)) or float(survivor.base_oxygen_capacity) < 1.0 or not is_finite(float(survivor.oxygen_capacity_bonus)) or float(survivor.oxygen_capacity_bonus) < 0.0:
			errors.append("Mieszkaniec %s ma niepoprawną pojemność tlenu." % survivor_id)
		if not is_finite(float(survivor.base_carry_capacity)) or float(survivor.base_carry_capacity) < 1.0 or not is_finite(float(survivor.carry_capacity_bonus)) or float(survivor.carry_capacity_bonus) < 0.0:
			errors.append("Mieszkaniec %s ma niepoprawny udźwig." % survivor_id)
		if int(survivor.status) < SurvivorStateScript.Status.AVAILABLE or int(survivor.status) > SurvivorStateScript.Status.DEPARTED:
			errors.append("Mieszkaniec %s ma nieznany status." % survivor_id)
		if int(survivor.health) < 0 or int(survivor.health) > int(survivor.get_max_health()):
			errors.append("Mieszkaniec %s ma zdrowie poza zakresem." % survivor_id)
		elif int(survivor.status) == SurvivorStateScript.Status.DEAD and int(survivor.health) != 0:
			errors.append("Zmarły mieszkaniec %s musi mieć zdrowie równe 0." % survivor_id)
		elif int(survivor.status) not in [SurvivorStateScript.Status.DEAD, SurvivorStateScript.Status.DEPARTED] and int(survivor.health) == 0:
			errors.append("Obecny mieszkaniec %s ma zerowe zdrowie, ale nie został rozstrzygnięty jako zmarły." % survivor_id)
		for field_name in ["hunger", "fatigue", "morale"]:
			var value := int(survivor.get(field_name))
			if value < 0 or value > 100:
				errors.append("Mieszkaniec %s ma %s poza zakresem 0..100." % [survivor_id, field_name])
		if int(survivor.status) in [SurvivorStateScript.Status.DEAD, SurvivorStateScript.Status.DEPARTED] and not str(survivor.current_assignment).is_empty():
			errors.append("Terminalny lub nieobecny mieszkaniec %s nadal ma przydział." % survivor_id)
		for profession_id in survivor.experience_by_job.keys():
			if str(profession_id).strip_edges().is_empty() or int(survivor.experience_by_job[profession_id]) < 0:
				errors.append("Mieszkaniec %s ma niepoprawny zapis praktyki zawodu." % survivor_id)
		if not str(survivor.secondary_profession).is_empty() and str(survivor.secondary_profession) == str(survivor.profession):
			errors.append("Mieszkaniec %s powtarza główny zawód jako drugą specjalizację." % survivor_id)
		_validate_unique_nonempty_strings(errors, survivor.injury_states, "urazów mieszkańca %s" % survivor_id)
	for survivor_id in result.keys():
		var survivor = result[survivor_id]
		for raw_related_id in survivor.relationship_links.keys():
			var related_id := str(raw_related_id).strip_edges()
			var relationship_value = survivor.relationship_links[raw_related_id]
			if related_id.is_empty() or not result.has(related_id):
				errors.append("Mieszkaniec %s ma relację do nieistniejącej osoby %s." % [survivor_id, related_id])
			if typeof(relationship_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(relationship_value)):
				errors.append("Mieszkaniec %s ma relację %s o niepoprawnej wartości." % [survivor_id, related_id])
	return result


static func _validate_disease_state(errors: Array[String], state, survivor_by_id: Dictionary) -> void:
	var campaign = state.disease_campaign
	for campaign_error in campaign.validation_errors():
		errors.append("Stan chorób kampanii: %s" % campaign_error)
	var known_disease_ids: Array[String] = []
	for disease_id_value in _game_database().diseases.keys():
		known_disease_ids.append(str(disease_id_value))
	known_disease_ids.sort()

	var living_present_count := 0
	var active_case_count := 0
	var contagious_case_count := 0
	for survivor_id in survivor_by_id.keys():
		var survivor = survivor_by_id[survivor_id]
		_validate_disease_case_collection(
			errors,
			survivor.disease_cases,
			known_disease_ids,
			int(state.day),
			int(campaign.last_resolved_day),
			"mieszkańca %s" % survivor_id
		)
		if not survivor.is_alive() or not survivor.is_present_in_settlement():
			if not survivor.disease_cases.is_empty():
				errors.append("Martwy lub nieobecny mieszkaniec %s zachował typowany przypadek choroby." % survivor_id)
			continue
		living_present_count += 1
		var survivor_has_active_case := false
		var survivor_has_contagious_case := false
		for disease_case in survivor.disease_cases:
			if not _is_exact(disease_case, DiseaseCaseStateScript):
				continue
			if int(disease_case.phase) != DiseaseCaseStateScript.Phase.IMMUNE:
				survivor_has_active_case = true
			if disease_case.is_infectious():
				survivor_has_contagious_case = true
		if survivor_has_active_case:
			active_case_count += 1
		if survivor_has_contagious_case:
			contagious_case_count += 1

	_validate_exposure_collection(
		errors,
		campaign.pending_exposures,
		known_disease_ids,
		survivor_by_id,
		int(state.day),
		int(campaign.last_resolved_day),
		true,
		"oczekujących narażeń kampanii"
	)
	if state.last_dive_result != null:
		_validate_exposure_collection(
			errors,
			state.last_dive_result.disease_exposures,
			known_disease_ids,
			survivor_by_id,
			int(state.day),
			-1,
			false,
			"narażeń ostatniej wyprawy"
		)

	if int(campaign.last_resolved_day) < 0 or int(campaign.last_resolved_day) > int(state.day):
		errors.append("Ostatni rozliczony dzień chorób jest poza osią czasu kampanii.")
	for date_field in ["outbreak_started_day", "last_contained_day"]:
		if int(campaign.get(date_field)) < 0 or int(campaign.get(date_field)) > int(state.day):
			errors.append("Pole %s epidemii jest poza osią czasu kampanii." % date_field)
	if int(campaign.last_contained_day) > 0 and int(campaign.last_contained_day) > int(campaign.last_resolved_day):
		errors.append("Epidemia została opanowana po ostatnim rozliczonym dniu chorób.")
	if not bool(campaign.outbreak_active) and not str(campaign.outbreak_id).is_empty() and int(campaign.last_contained_day) < 1:
		errors.append("Zakończony epizod epidemii nie ma dnia opanowania.")

	var outbreak_threshold := maxi(2, int(ceil(float(living_present_count) / 3.0)))
	if bool(campaign.outbreak_active):
		var outbreak_cases := contagious_case_count
		if outbreak_cases < 1:
			errors.append("Aktywna epidemia nie ma już żadnego zakaźnego przypadku i powinna być opanowana.")
		if int(campaign.peak_cases) < outbreak_threshold:
			errors.append("Aktywna epidemia nie ma zarejestrowanego szczytu osiągającego próg %d." % outbreak_threshold)
		if int(campaign.peak_cases) < outbreak_cases:
			errors.append("Szczyt epidemii jest niższy od bieżącej liczby zakaźnych przypadków.")
	elif contagious_case_count >= outbreak_threshold:
		errors.append("Liczba zakaźnych mieszkańców osiąga próg epidemii bez aktywnego epizodu.")

	_validate_pressure_disease_metrics(
		errors,
		state,
		living_present_count,
		active_case_count,
		contagious_case_count
	)


static func _validate_disease_case_collection(
	errors: Array[String],
	cases,
	known_disease_ids: Array[String],
	current_day: int,
	campaign_last_resolved_day: int,
	context: String
) -> void:
	if not (cases is Array):
		errors.append("Kolekcja przypadków %s nie jest tablicą." % context)
		return
	var seen_disease_ids: Dictionary = {}
	for index in range(cases.size()):
		var disease_case = cases[index]
		if not _is_exact(disease_case, DiseaseCaseStateScript):
			errors.append("Przypadek %d %s ma niepoprawny typ." % [index, context])
			continue
		for case_error in disease_case.validation_errors():
			errors.append("Przypadek %s/%d: %s" % [context, index, case_error])
		var disease_id := str(disease_case.disease_id)
		if seen_disease_ids.has(disease_id):
			errors.append("Przypadki %s powtarzają chorobę %s." % [context, disease_id])
		else:
			seen_disease_ids[disease_id] = true
		if not known_disease_ids.is_empty() and not known_disease_ids.has(disease_id):
			errors.append("Przypadek %s wskazuje nieznaną chorobę %s." % [context, disease_id])
		if current_day > 0:
			if int(disease_case.acquired_day) > current_day or int(disease_case.phase_started_day) > current_day:
				errors.append("Przypadek %s ma datę z przyszłości." % context)
			if int(disease_case.last_resolved_day) > current_day:
				errors.append("Przypadek %s został rozliczony w przyszłości." % context)
		if campaign_last_resolved_day >= 0 and int(disease_case.last_resolved_day) > campaign_last_resolved_day:
			errors.append("Przypadek %s wyprzedza ostatni rozliczony dzień kampanii chorobowej." % context)


static func _validate_exposure_collection(
	errors: Array[String],
	exposures,
	known_disease_ids: Array[String],
	survivor_by_id: Dictionary,
	current_day: int,
	minimum_exclusive_day: int,
	require_living_target: bool,
	context: String
) -> void:
	if not (exposures is Array):
		errors.append("Kolekcja %s nie jest tablicą." % context)
		return
	var seen_records: Dictionary = {}
	for index in range(exposures.size()):
		var exposure = exposures[index]
		if not _is_exact(exposure, DiseaseExposureStateScript):
			errors.append("Narażenie %d w %s ma niepoprawny typ." % [index, context])
			continue
		for exposure_error in exposure.validation_errors():
			errors.append("Narażenie %s/%d: %s" % [context, index, exposure_error])
		if not known_disease_ids.has(str(exposure.disease_id)):
			errors.append("Narażenie %s wskazuje nieznaną chorobę %s." % [context, exposure.disease_id])
		var target_id := str(exposure.target_survivor_id)
		if not survivor_by_id.has(target_id):
			errors.append("Narażenie %s wskazuje nieistniejący cel %s." % [context, target_id])
		elif require_living_target and (not survivor_by_id[target_id].is_alive() or not survivor_by_id[target_id].is_present_in_settlement()):
			errors.append("Oczekujące narażenie wskazuje martwy lub nieobecny cel %s." % target_id)
		var source_survivor_id := str(exposure.source_survivor_id)
		if not source_survivor_id.is_empty() and not survivor_by_id.has(source_survivor_id):
			errors.append("Narażenie %s wskazuje nieistniejącą osobę źródłową %s." % [context, source_survivor_id])
		if int(exposure.acquired_day) > current_day:
			errors.append("Narażenie %s ma dzień z przyszłości." % context)
		if minimum_exclusive_day >= 0 and int(exposure.acquired_day) <= minimum_exclusive_day:
			errors.append("Oczekujące narażenie nie jest późniejsze od ostatniego rozliczonego dnia chorób.")
		var record_key := "\u001f".join([
			str(exposure.disease_id), target_id, str(exposure.source_kind), str(exposure.source_id),
			source_survivor_id, str(exposure.acquired_day),
		])
		if seen_records.has(record_key):
			errors.append("Kolekcja %s zawiera powtórzone narażenie." % context)
		else:
			seen_records[record_key] = true


static func _validate_buildings(errors: Array[String], state, survivor_by_id: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var seen_slots: Dictionary = {}
	var seen_definitions: Dictionary = {}
	var assigned_owner: Dictionary = {}
	for building in state.buildings:
		var building_id := str(building.id).strip_edges()
		var definition_id := str(building.definition_id).strip_edges()
		var slot_id := str(building.slot_id).strip_edges()
		if building_id.is_empty():
			errors.append("Budynek nie ma ID.")
			continue
		if result.has(building_id):
			errors.append("Powtórzone ID budynku: %s." % building_id)
			continue
		result[building_id] = building
		if not _game_database().buildings.has(definition_id):
			errors.append("Budynek %s ma nieznaną definicję %s." % [building_id, definition_id])
		else:
			var definition = _game_database().buildings[definition_id]
			if int(building.level) < 1 or int(building.level) > int(definition.max_level):
				errors.append("Budynek %s ma poziom poza zakresem definicji." % building_id)
		if not SLOT_DEFINITIONS.has(slot_id):
			errors.append("Budynek %s wskazuje nieznany slot %s." % [building_id, slot_id])
		elif str(SLOT_DEFINITIONS[slot_id].definition_id) != definition_id:
			errors.append("Budynek %s nie pasuje do definicji slotu %s." % [building_id, slot_id])
		if seen_slots.has(slot_id):
			errors.append("Slot %s zawiera więcej niż jeden budynek." % slot_id)
		seen_slots[slot_id] = building_id
		if seen_definitions.has(definition_id):
			errors.append("Definicja budynku %s występuje więcej niż raz." % definition_id)
		seen_definitions[definition_id] = building_id
		if int(building.condition) < 0 or int(building.condition) > 100:
			errors.append("Budynek %s ma stan poza zakresem 0..100." % building_id)
		if int(building.construction_progress) < 0 or int(building.construction_progress) > 100:
			errors.append("Budynek %s ma niepoprawny postęp budowy." % building_id)
		if not bool(building.is_built) or int(building.construction_progress) != 100 or int(building.pending_level) != 0:
			errors.append("Budynek %s nie jest ukończony zgodnie z kontraktem natychmiastowej budowy." % building_id)
		if not _is_valid_work_pace(str(building.work_pace)):
			errors.append("Budynek %s ma nieznane tempo pracy %s." % [building_id, building.work_pace])
		if int(building.work_tension) < 0 or int(building.work_tension) > 3:
			errors.append("Budynek %s ma Napięcie pracy poza zakresem 0..3." % building_id)
		var local_workers: Dictionary = {}
		for worker_id_value in building.assigned_survivor_ids:
			var worker_id := str(worker_id_value)
			if local_workers.has(worker_id) or assigned_owner.has(worker_id):
				errors.append("Mieszkaniec %s występuje wielokrotnie w obsadzie budynków." % worker_id)
				continue
			local_workers[worker_id] = true
			assigned_owner[worker_id] = building_id
			if not survivor_by_id.has(worker_id):
				errors.append("Budynek %s wskazuje nieistniejącego mieszkańca %s." % [building_id, worker_id])
			elif not survivor_by_id[worker_id].is_present_in_settlement():
				errors.append("Budynek %s ma nieobecnego mieszkańca %s w obsadzie." % [building_id, worker_id])
			elif str(survivor_by_id[worker_id].current_assignment) != building_id:
				errors.append("Przydział mieszkańca %s nie wskazuje z powrotem budynku %s." % [worker_id, building_id])
	for survivor_id in survivor_by_id.keys():
		var assignment := str(survivor_by_id[survivor_id].current_assignment)
		if not assignment.is_empty() and (not result.has(assignment) or assigned_owner.get(survivor_id, "") != assignment):
			errors.append("Mieszkaniec %s ma wiszący lub jednostronny przydział %s." % [survivor_id, assignment])
	return result


static func _validate_platform(errors: Array[String], platform, building_by_id: Dictionary) -> void:
	if int(platform.support_level) < 1:
		errors.append("Poziom wsparcia platformy musi być dodatni.")
	if not _in_float_range(float(platform.fishing_pressure), 0.0, 1.0):
		errors.append("Presja połowowa platformy jest poza zakresem.")
	if not _in_float_range(float(platform.repair_scrap_rounding_carry), -0.5, 0.5):
		errors.append("Reszta zaokrąglenia naprawy jest poza zakresem.")
	if platform.slot_states.size() != SLOT_DEFINITIONS.size():
		errors.append("Platforma nie zawiera dokładnie sześciu kanonicznych slotów.")
	for slot_id in SLOT_DEFINITIONS.keys():
		if not platform.slot_states.has(slot_id) or not (platform.slot_states[slot_id] is Dictionary):
			errors.append("Brakuje poprawnego stanu slotu %s." % slot_id)
			continue
		var slot: Dictionary = platform.slot_states[slot_id]
		var expected: Dictionary = SLOT_DEFINITIONS[slot_id]
		if str(slot.get("definition_id", "")) != str(expected.definition_id) or bool(slot.get("is_edge", false)) != bool(expected.is_edge):
			errors.append("Slot %s ma zmienioną tożsamość lub geometrię logiczną." % slot_id)
		var building_id := str(slot.get("building_id", ""))
		if not building_id.is_empty():
			if not building_by_id.has(building_id):
				errors.append("Slot %s wskazuje nieistniejący budynek %s." % [slot_id, building_id])
			elif str(building_by_id[building_id].slot_id) != slot_id or str(building_by_id[building_id].definition_id) != str(expected.definition_id):
				errors.append("Referencja slotu %s i budynku %s nie jest obustronna." % [slot_id, building_id])
	for building_id in building_by_id.keys():
		var building = building_by_id[building_id]
		if str(platform.slot_states.get(building.slot_id, {}).get("building_id", "")) != building_id:
			errors.append("Budynek %s nie jest zapisany w swoim slocie %s." % [building_id, building.slot_id])


static func _validate_story(errors: Array[String], state, survivor_by_id: Dictionary) -> void:
	var story = state.story_flags
	if int(story.act) < StoryProgressStateScript.ACT_COMMON_LINE or int(story.act) > StoryProgressStateScript.ACT_EPILOGUE:
		errors.append("Akt fabuły jest poza zakresem.")
	for counter_name in ["successful_dives", "diver_deaths", "rescued_survivor_count", "crisis_days_remaining"]:
		if int(story.get(counter_name)) < 0:
			errors.append("Licznik fabularny %s jest ujemny." % counter_name)
	if bool(story.junction_j7_active) != (int(story.junction_j7_activated_day) > 0):
		errors.append("Stan węzła J-7 nie odpowiada dniowi aktywacji.")
	if bool(story.archive_terminal_active) != (int(story.archive_terminal_activated_day) > 0):
		errors.append("Stan terminala Archiwum nie odpowiada dniowi aktywacji.")
	if bool(story.archive_map_transmitted) != bool(story.archive_terminal_active):
		errors.append("Transmisja mapy nie odpowiada stanowi terminala Archiwum.")
	if bool(story.archive_terminal_active) and not bool(story.junction_j7_active):
		errors.append("Terminal Archiwum nie może poprzedzać uruchomienia J-7.")
	if bool(story.archive_terminal_active) and not state.underwater_world.delta.activated_fixed_devices.has("archive_terminal"):
		errors.append("Typowany stan Archiwum nie ma odpowiadającego trwałego urządzenia świata.")
	if bool(story.r3_diagnosed) != (int(story.r3_diagnosed_day) > 0):
		errors.append("Stan diagnostyki R-3 nie odpowiada dniowi wykonania.")
	if bool(story.r3_diagnosed) and (not bool(story.archive_terminal_active) or not state.underwater_world.delta.activated_fixed_devices.has("r3_diagnostic_panel")):
		errors.append("Diagnostyka R-3 wymaga Archiwum i odpowiadającego urządzenia świata.")
	if bool(story.r3_regulator_ready) != (int(story.r3_regulator_completed_day) > 0):
		errors.append("Stan Regulatora R-3 nie odpowiada dniowi ukończenia.")
	if bool(story.r3_regulator_ready) and not bool(story.r3_diagnosed):
		errors.append("Regulator R-3 nie może poprzedzać diagnostyki generatora.")
	if bool(story.r3_generator_active) != (int(story.r3_generator_activated_day) > 0):
		errors.append("Stan Generatora R-3 nie odpowiada dniowi aktywacji.")
	if bool(story.r3_generator_active) and (not bool(story.r3_regulator_ready) or not state.underwater_world.delta.activated_fixed_devices.has("r3_generator")):
		errors.append("Aktywny Generator R-3 wymaga gotowego regulatora i odpowiadającego urządzenia świata.")
	if bool(story.c4_switchboard_active) != (int(story.c4_switchboard_activated_day) > 0):
		errors.append("Stan Rozdzielni C-4 nie odpowiada dniowi aktywacji.")
	if bool(story.c4_switchboard_active) and (not bool(story.r3_generator_active) or not state.underwater_world.delta.activated_fixed_devices.has("c4_switchboard")):
		errors.append("Aktywna Rozdzielnia C-4 wymaga Generatora R-3 i odpowiadającego urządzenia świata.")
	if bool(story.common_line_splitter_ready) != (int(story.common_line_splitter_completed_day) > 0):
		errors.append("Stan Rozdzielacza nie odpowiada dniowi ukończenia produkcji.")
	if bool(story.common_line_splitter_ready) and not bool(story.c4_switchboard_active):
		errors.append("Gotowy Rozdzielacz wymaga aktywnej Rozdzielni C-4.")
	if bool(story.common_line_splitter_installed) != (int(story.common_line_splitter_installed_day) > 0):
		errors.append("Stan montażu Rozdzielacza nie odpowiada dniowi instalacji.")
	if bool(story.common_line_splitter_installed) and (not bool(story.common_line_splitter_ready) or not state.underwater_world.delta.activated_fixed_devices.has("c4_splitter_mount")):
		errors.append("Zamontowany Rozdzielacz wymaga gotowego urządzenia i odpowiadającego punktu świata.")
	if bool(story.black_front_active) and (not bool(story.junction_j7_active) or int(story.black_front_days_total) not in [10, 12, 15] or int(story.black_front_days_remaining) < 1 or int(story.black_front_days_remaining) > int(story.black_front_days_total)):
		errors.append("Aktywny licznik Czarnego Frontu jest niespójny.")
	if bool(story.black_front_arrived) and (bool(story.black_front_active) or int(story.black_front_days_remaining) != 0):
		errors.append("Przybycie Czarnego Frontu jest niespójne z licznikiem.")
	if int(story.first_full_integrity_day) < 0 or int(story.full_integrity_days) < 0:
		errors.append("Telemetria pełnej integralności nie może być ujemna.")
	if (int(story.first_full_integrity_day) == 0) != (int(story.full_integrity_days) == 0):
		errors.append("Pierwszy dzień pełnej integralności i licznik takich dni są niespójne.")
	if int(story.first_full_integrity_day) > int(state.day):
		errors.append("Pierwszy dzień pełnej integralności wykracza poza oś kampanii.")
	var energy_configuration := str(story.energy_configuration).strip_edges()
	var final_outcome_id := str(story.final_outcome_id).strip_edges()
	if bool(story.energy_choice_pending) and (not bool(story.black_front_arrived) or state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY) != 100 or not energy_configuration.is_empty() or not final_outcome_id.is_empty()):
		errors.append("Oczekujący wybór energii nie odpowiada gotowemu finałowi Czarnego Frontu.")
	if not energy_configuration.is_empty() and energy_configuration not in ["harbor", "north", "common_line"]:
		errors.append("Finał zawiera nieznaną konfigurację energii %s." % energy_configuration)
	var expected_final_outcome: String = str({"harbor": "quiet_after_storm", "north": "debt_repaid", "common_line": "last_bridge"}.get(energy_configuration, ""))
	if final_outcome_id != expected_final_outcome:
		errors.append("Wynik finału nie odpowiada wybranej konfiguracji energii.")
	if not final_outcome_id.is_empty():
		if bool(story.energy_choice_pending) or not bool(story.black_front_arrived) or int(story.final_resolved_day) < 1:
			errors.append("Rozstrzygnięty finał ma niespójną oś czasu albo nadal oczekuje na wybór.")
		if bool(story.north_platform_survived) != (energy_configuration != "harbor"):
			errors.append("Los Platformy Północnej nie odpowiada konfiguracji energii.")
		if energy_configuration in ["north", "common_line"] and (not bool(story.r3_generator_active) or not bool(story.c4_switchboard_active)):
			errors.append("Wybrana konfiguracja dla Północnej wymaga R-3 i C-4.")
		if energy_configuration == "common_line":
			if not bool(story.common_line_splitter_installed):
				errors.append("Wspólna Linia wymaga zamontowanego Rozdzielacza.")
			var community = state.find_building_by_definition("community_house")
			var has_radio_operator := false
			if community != null and community.is_active() and int(community.level) >= 3:
				for survivor_id in community.assigned_survivor_ids:
					var survivor = state.find_survivor(str(survivor_id))
					if survivor != null and survivor.can_work():
						has_radio_operator = true
						break
			if community == null or not community.is_active() or int(community.level) < 3 or not has_radio_operator:
				errors.append("Wspólna Linia wymaga Radiostacji w Domu Wspólnoty III i zdolnej obsady.")
		for field_name in ["day", "survivors", "hope", "platform_integrity", "successful_dives", "diver_deaths"]:
			if not story.final_summary.has(field_name) or typeof(story.final_summary[field_name]) != TYPE_INT:
				errors.append("Podsumowanie finału nie zawiera całkowitego pola %s." % field_name)
		_validate_common_line_chronicle(errors, story)
	elif int(story.final_resolved_day) != 0 or bool(story.north_platform_survived) or not story.final_summary.is_empty() or bool(story.final_chronicle_continued) or not story.chronicle_summary.is_empty():
		errors.append("Nierozstrzygnięty finał zachował dane wyniku.")
	for raw_flag_id in story.flags.keys():
		if str(raw_flag_id).strip_edges().is_empty() or typeof(story.flags[raw_flag_id]) != TYPE_BOOL:
			errors.append("Flaga fabularna %s ma pusty identyfikator albo nie jest wartością logiczną." % raw_flag_id)
	var expected_act := StoryProgressStateScript.ACT_EPILOGUE if bool(story.final_chronicle_continued) else StoryProgressStateScript.ACT_COMMON_LINE
	if int(story.act) != expected_act:
		errors.append("Etap Wspólnej Linii nie odpowiada stanowi Kroniki.")
	if bool(story.final_chronicle_continued) and final_outcome_id.is_empty():
		errors.append("Kontynuacja nowej Kroniki wymaga rozstrzygniętego finału energii.")

	_validate_story_phase(errors, state)


static func _validate_common_line_chronicle(errors: Array[String], story) -> void:
	var summary: Dictionary = story.chronicle_summary
	var integer_fields: Array[String] = ["black_front_day", "first_full_integrity_day", "integrity_before_storm", "integrity_after_storm", "full_integrity_days", "dives", "safe_returns", "diver_deaths", "recovered_backpacks", "rescued_survivors", "hope"]
	for field_name in integer_fields:
		if not summary.has(field_name) or typeof(summary[field_name]) != TYPE_INT or int(summary[field_name]) < 0:
			errors.append("Kronika nie zawiera poprawnego całkowitego pola %s." % field_name)
	for field_name in ["living_survivors", "dead_survivors", "accepted_survivors", "rejected_survivors", "buildings", "important_decisions"]:
		if not summary.has(field_name) or not (summary[field_name] is Array):
			errors.append("Kronika nie zawiera poprawnej listy %s." % field_name)
	for field_name in ["resources"]:
		if not summary.has(field_name) or not (summary[field_name] is Dictionary):
			errors.append("Kronika nie zawiera słownika %s." % field_name)
	for field_name in ["outcome_id", "ending_title", "leon_fate", "energy_configuration"]:
		if not summary.has(field_name) or typeof(summary[field_name]) != TYPE_STRING:
			errors.append("Kronika nie zawiera tekstowego pola %s." % field_name)
	for field_name in ["r3_active", "c4_active", "splitter_installed", "radio_active", "north_platform_survived"]:
		if not summary.has(field_name) or typeof(summary[field_name]) != TYPE_BOOL:
			errors.append("Kronika nie zawiera logicznego pola %s." % field_name)
	if summary.get("outcome_id", "") != story.final_outcome_id or summary.get("energy_configuration", "") != story.energy_configuration:
		errors.append("Kronika nie odpowiada rozstrzygniętemu wynikowi energii.")
	if int(summary.get("integrity_before_storm", -1)) != 100 or int(summary.get("integrity_after_storm", -1)) != 100:
		errors.append("Wariant bez dodatkowych obrażeń musi zachować 100% integralności przed i po Froncie.")
	if int(summary.get("safe_returns", -1)) != int(story.successful_dives) or int(summary.get("diver_deaths", -1)) != int(story.diver_deaths):
		errors.append("Kronika nie odpowiada telemetrii wypraw.")


static func _validate_story_phase(errors: Array[String], state) -> void:
	var story = state.story_flags
	var phase := int(state.current_phase)
	if bool(story.crisis_active):
		if int(story.crisis_days_remaining) < 1 or int(story.crisis_days_remaining) > 3:
			errors.append("Aktywny kryzys ma niepoprawną liczbę pozostałych dni.")
		if int(story.crisis_started_day) < 1 or int(story.crisis_started_day) >= int(state.day) or int(story.crisis_days_remaining) + int(state.day) - int(story.crisis_started_day) != 4:
			errors.append("Oś czasu aktywnego kryzysu jest niespójna.")
		if phase not in [GamePhaseScript.Phase.END_DAY_REPORT, GamePhaseScript.Phase.DAY_START_REPORT, GamePhaseScript.Phase.CRISIS]:
			errors.append("Aktywny kryzys występuje w fazie, która nie potrafi go obsłużyć.")
	elif int(story.crisis_days_remaining) != 0:
		errors.append("Nieaktywny kryzys zachował dodatnią liczbę pozostałych dni.")
	if phase == GamePhaseScript.Phase.CRISIS and not bool(story.crisis_active):
		errors.append("Faza CRISIS nie ma aktywnego kryzysu fabularnego.")
	if phase == GamePhaseScript.Phase.BASE_PLANNING and bool(story.crisis_active):
		errors.append("Faza planowania bazowego nie może pomijać aktywnego kryzysu.")

	var reason := str(story.game_over_reason).strip_edges()
	if not reason.is_empty() and not VALID_GAME_OVER_REASONS.has(reason):
		errors.append("Fabuła zawiera nieznaną przyczynę końca kampanii %s." % reason)
	if phase == GamePhaseScript.Phase.GAME_OVER:
		if not VALID_GAME_OVER_REASONS.has(reason):
			errors.append("Faza GAME_OVER nie ma znanej przyczyny.")
		if int(story.game_over_day) != int(state.day) - 1:
			errors.append("Dzień końca kampanii nie odpowiada ostatniemu rozliczonemu dniowi.")
		if bool(story.crisis_active):
			errors.append("Stan GAME_OVER nie może jednocześnie utrzymywać aktywnego kryzysu.")
		var alive_count: int = state.get_alive_survivors().size()
		var integrity := int(state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY))
		var hope := int(state.resources.get_amount(ResourceIdsScript.HOPE))
		if reason == "settlement_lost" and alive_count != 0:
			errors.append("Przyczyna settlement_lost nie odpowiada żyjącemu rosterowi.")
		elif reason == "platform_destroyed" and (alive_count <= 0 or integrity != 0):
			errors.append("Przyczyna platform_destroyed nie odpowiada stanowi Przystani lub precedencji końca gry.")
		elif reason == "leadership_collapse" and (alive_count <= 0 or integrity <= 0 or hope >= 15):
			errors.append("Przyczyna leadership_collapse nie odpowiada stanowi Nadziei lub precedencji końca gry.")
		elif reason == "black_front_unprepared" and (not bool(story.black_front_arrived) or integrity == 100):
			errors.append("Przyczyna black_front_unprepared nie odpowiada przybyciu Frontu lub Integralności.")
	elif not reason.is_empty():
		errors.append("Przyczyna końca kampanii istnieje poza fazą GAME_OVER.")

	if phase == GamePhaseScript.Phase.ENDING:
		var common_line_ending := bool(story.energy_choice_pending) or not str(story.final_outcome_id).is_empty()
		if not common_line_ending or bool(story.crisis_active) or not reason.is_empty():
			errors.append("Faza ENDING nie opisuje oczekującego albo rozstrzygniętego finału.")


static func _validate_policies(errors: Array[String], state) -> void:
	var policies = state.active_policies
	if int(policies.ration_policy) not in [PolicyStateScript.RationPolicy.FULL, PolicyStateScript.RationPolicy.HALF, PolicyStateScript.RationPolicy.NONE, PolicyStateScript.RationPolicy.DIVER_PRIORITY]:
		errors.append("Polityka racji ma nieznaną wartość.")


static func _is_valid_work_pace(work_pace: String) -> bool:
	return work_pace in [
		PolicyStateScript.WORK_PACE_CAREFUL,
		PolicyStateScript.WORK_PACE_NORMAL,
		PolicyStateScript.WORK_PACE_INTENSE,
	]


static func _validate_equipment(errors: Array[String], equipment) -> void:
	var seen: Dictionary = {}
	for gear_id_value in equipment.owned_gear_ids:
		var gear_id := str(gear_id_value)
		if seen.has(gear_id):
			errors.append("Wyposażenie %s występuje wielokrotnie w magazynie." % gear_id)
		seen[gear_id] = true
		if not _game_database().diving_gear.has(gear_id):
			errors.append("Magazyn wyposażenia zawiera nieznane ID %s." % gear_id)
	for slot_id_value in equipment.equipped_by_slot.keys():
		var slot_id := str(slot_id_value)
		var gear_id := str(equipment.equipped_by_slot[slot_id_value])
		if not seen.has(gear_id) or not _game_database().diving_gear.has(gear_id):
			errors.append("Slot %s wskazuje nieposiadane lub nieznane wyposażenie %s." % [slot_id, gear_id])
		elif str(_game_database().diving_gear[gear_id].equipment_slot) != slot_id:
			errors.append("Wyposażenie %s nie pasuje do slotu %s." % [gear_id, slot_id])
	for required_slot in [DivingEquipmentStateScript.LIGHT_SLOT, DivingEquipmentStateScript.OXYGEN_TANK_SLOT]:
		if str(equipment.equipped_by_slot.get(required_slot, "")).is_empty():
			errors.append("Brakuje wyposażenia w wymaganym slocie %s." % required_slot)
	for emergency_gear_id in [DivingEquipmentStateScript.STARTING_LIGHT_ID, DivingEquipmentStateScript.STARTING_OXYGEN_TANK_ID]:
		if not seen.has(emergency_gear_id):
			errors.append("Magazyn wyposażenia nie zawiera awaryjnego zestawu %s." % emergency_gear_id)


static func _validate_world(
	errors: Array[String],
	state,
	validate_current_scene_snapshot: bool = true
) -> void:
	var world = state.underwater_world
	var blueprint = world.blueprint
	var delta = world.delta
	if int(blueprint.map_source_version) != MapSceneCompilerScript.MAP_SOURCE_VERSION:
		errors.append("Migawka mapy nie ma bieżącej wersji źródła.")
	if int(blueprint.campaign_seed) != int(state.seed):
		errors.append("Migawka mapy nie odpowiada seedowi kampanii.")
	if str(blueprint.map_id).strip_edges().is_empty() or str(blueprint.map_gameplay_signature).strip_edges().is_empty():
		errors.append("Migawka mapy nie ma kompletnej tożsamości źródła.")
	if validate_current_scene_snapshot:
		_validate_current_scene_snapshot(errors, state, blueprint)
	var landmark_ids := _record_ids(errors, blueprint.landmarks, "landmarku")
	var landmark_refs: Dictionary = landmark_ids.duplicate(true)
	var connection_ids := _record_ids(errors, blueprint.connections, "połączenia")
	var shortcut_ids := _plain_record_ids(blueprint.shortcut_spawns)
	var fixed_device_ids := _record_ids(errors, blueprint.fixed_device_spawns, "urządzenia stałego")
	_record_ids(errors, blueprint.loot_spawns, "źródła łupu")
	var container_ids: Dictionary = {}
	var initial_container_contents_by_id: Dictionary = {}
	var collected_world_item_ids: Dictionary = {}
	for loot_spawn in blueprint.loot_spawns:
		var loot_id := str(loot_spawn.get("id", ""))
		if str(loot_spawn.get("spawn_kind", "container")) == "pickup":
			collected_world_item_ids[loot_id] = true
			continue
		container_ids[loot_id] = true
		var contents = loot_spawn.get("contents", {})
		if contents is Dictionary:
			initial_container_contents_by_id[loot_id] = _runtime_initial_container_contents(
				state,
				loot_spawn
			)
			for raw_item_id in contents.keys():
				collected_world_item_ids["%s:%s" % [loot_id, str(raw_item_id)]] = true
	var heavy_ids := _record_ids(errors, blueprint.heavy_object_spawns, "ciężkiego obiektu")
	var rescue_ids := _record_ids(errors, blueprint.rescue_spawns, "spotkania ratunkowego")
	var rescue_by_id: Dictionary = {}
	for rescue_spawn in blueprint.rescue_spawns:
		rescue_by_id[str(rescue_spawn.get("id", ""))] = rescue_spawn
	var buoy_ids := _plain_record_ids(blueprint.buoy_spawns)
	for landmark in blueprint.landmarks:
		var canonical_landmark_id := str(landmark.get("id", ""))
		for raw_alias in landmark.get("aliases", []):
			var alias := str(raw_alias).strip_edges()
			if alias.is_empty() or landmark_refs.has(alias):
				errors.append("Blueprint zawiera pusty lub niejednoznaczny alias landmarku %s." % alias)
				continue
			landmark_refs[alias] = canonical_landmark_id
	if not landmark_ids.has(str(blueprint.entry_landmark_id)):
		errors.append("Wejściowy landmark świata nie istnieje.")
	for connection in blueprint.connections:
		if not landmark_ids.has(str(connection.get("from_id", ""))) or not landmark_ids.has(str(connection.get("to_id", ""))):
			errors.append("Połączenie %s ma wiszącą referencję landmarku." % connection.get("id", ""))
		if not (connection.get("path_points", PackedVector2Array()) is PackedVector2Array) or connection.get("path_points", PackedVector2Array()).size() < 2:
			errors.append("Połączenie %s nie ma poprawnej trasy." % connection.get("id", ""))
	_validate_unique_subset(errors, delta.discovered_landmarks, landmark_refs, "odkrytych landmarków")
	_validate_unique_subset(errors, delta.discovered_chunks, _dictionary_key_set(blueprint.chunk_index), "odkrytych chunków")
	_validate_unique_subset(errors, delta.opened_containers, container_ids, "otwartych źródeł łupu")
	_validate_unique_subset(errors, delta.collected_items, collected_world_item_ids, "zebranych obiektów świata")
	_validate_unique_subset(errors, delta.placed_buoys, buoy_ids, "boi")
	_validate_unique_subset(errors, delta.opened_shortcuts, shortcut_ids, "otwartych skrótów")
	_validate_unique_subset(errors, delta.activated_fixed_devices, fixed_device_ids, "uruchomionych urządzeń stałych")
	_validate_unique_subset(errors, delta.collapsed_paths, connection_ids, "zawalonych ścieżek")
	_validate_unique_subset(errors, delta.marked_heavy_objects, heavy_ids, "oznaczonych ciężkich obiektów")
	_validate_unique_subset(errors, delta.recovered_heavy_objects, heavy_ids, "odzyskanych ciężkich obiektów")
	for heavy_id in delta.marked_heavy_objects:
		if delta.recovered_heavy_objects.has(heavy_id):
			errors.append("Ciężki obiekt %s jest jednocześnie oznaczony i odzyskany." % heavy_id)
	if not str(delta.active_landmark_id).is_empty() and not landmark_refs.has(str(delta.active_landmark_id)):
		errors.append("Aktywny landmark świata nie istnieje.")
	for container_id_value in delta.remaining_container_contents.keys():
		var container_id := str(container_id_value)
		if not container_ids.has(container_id) or delta.opened_containers.has(container_id):
			errors.append("Pozostała zawartość wskazuje nieznane lub jednocześnie otwarte źródło %s." % container_id)
		_validate_item_amounts(errors, delta.remaining_container_contents[container_id_value], "zawartości źródła %s" % container_id)
		if initial_container_contents_by_id.has(container_id) and delta.remaining_container_contents[container_id_value] is Dictionary:
			var initial_contents: Dictionary = initial_container_contents_by_id[container_id]
			for item_id_value in delta.remaining_container_contents[container_id_value].keys():
				var item_id := str(item_id_value)
				if not initial_contents.has(item_id) or int(delta.remaining_container_contents[container_id_value][item_id_value]) > int(initial_contents.get(item_id, 0)):
					errors.append("Pozostała zawartość źródła %s tworzy nieautoryzowaną kopię %s." % [container_id, item_id])
	for diver_id_value in delta.dead_divers.keys():
		var dead_diver_id := str(diver_id_value).strip_edges()
		if dead_diver_id.is_empty() or not landmark_refs.has(str(delta.dead_divers[diver_id_value])):
			errors.append("Rekord śmierci nurka ma niepoprawne ID lub landmark.")
		elif not delta.lost_backpacks.has(dead_diver_id):
			errors.append("Rekord śmierci nurka %s nie ma odpowiadającego trwałego plecaka." % dead_diver_id)
		else:
			var dead_diver = state.find_survivor(dead_diver_id)
			if dead_diver == null or int(dead_diver.status) != SurvivorStateScript.Status.DEAD or int(dead_diver.health) != 0:
				errors.append("Rekord śmierci nurka %s nie odpowiada martwej osobie w trwałym rosterze." % dead_diver_id)
	for backpack_id in delta.lost_backpacks.keys():
		_validate_persistent_loot_record(errors, str(backpack_id), delta.lost_backpacks[backpack_id], landmark_refs, true, int(state.day), delta.dead_divers)
	for pile_id in delta.dropped_loot_piles.keys():
		_validate_persistent_loot_record(errors, str(pile_id), delta.dropped_loot_piles[pile_id], landmark_refs, false, int(state.day), delta.dead_divers)
	for encounter_id in delta.rescued_or_dead_survivors.keys():
		if not rescue_ids.has(str(encounter_id)) or not (delta.rescued_or_dead_survivors[encounter_id] is Dictionary):
			errors.append("Stan ratunku wskazuje nieznane spotkanie %s lub ma zły kształt." % encounter_id)
			continue
		var outcome: Dictionary = delta.rescued_or_dead_survivors[encounter_id]
		var status := str(outcome.get("status", ""))
		var survivor_id := str(outcome.get("survivor_id", "")).strip_edges()
		var rescue_definition_id := str(rescue_by_id.get(str(encounter_id), {}).get("definition_id", ""))
		var rescue_definition = _game_database().rescue_encounters.get(rescue_definition_id)
		var authored_survivor_id := str(rescue_definition.survivor_id) if rescue_definition != null else ""
		if status not in ["rescued", "dead"] or survivor_id.is_empty() or survivor_id != authored_survivor_id or typeof(outcome.get("stabilized", null)) != TYPE_BOOL:
			errors.append("Stan ratunku %s ma niepoprawny status, osobę albo flagę stabilizacji." % encounter_id)
		elif status == "rescued" and state.find_survivor(survivor_id) == null:
			errors.append("Uratowana osoba %s nie istnieje w trwałym rosterze." % survivor_id)
	for biological_id_value in delta.depleted_biological_nodes.keys():
		var biological_id := str(biological_id_value).strip_edges()
		var biological_record = delta.depleted_biological_nodes[biological_id_value]
		if biological_id.is_empty() or not (biological_record is Dictionary) or typeof(biological_record.get("depleted_day", null)) != TYPE_INT or int(biological_record.get("depleted_day", 0)) < 1 or int(biological_record.get("depleted_day", 0)) > int(state.day):
			errors.append("Stan wyczerpanego węzła biologicznego %s ma niepoprawny kształt lub dzień." % biological_id)


static func _runtime_initial_container_contents(state, loot_spawn: Dictionary) -> Dictionary:
	var authored_value = loot_spawn.get("contents", {})
	if not (authored_value is Dictionary):
		return {}
	var authored_contents: Dictionary = authored_value
	var source_id := str(loot_spawn.get("id", ""))
	var multiplier := 1.0
	# Runtime keeps mandatory and explicitly fixed sources exact by using a
	# neutral multiplier. Project artifacts remain exact independently, while
	# ordinary filler in the same container follows the campaign snapshot.
	if (
		bool(loot_spawn.get("difficulty_scaled_contents", true))
		and int(loot_spawn.get("mandatory_order", -1)) < 0
	):
		multiplier = maxf(float(state.difficulty_profile.loot_density_multiplier), 0.01)
	var result: Dictionary = {}
	for item_id_value in authored_contents.keys():
		var item_id := str(item_id_value)
		var authored_amount := int(authored_contents[item_id_value])
		var initial_amount := DifficultyMathScript.scale_loot_amount(
			authored_amount,
			multiplier,
			int(state.seed),
			source_id,
			item_id,
			1
		)
		if initial_amount > 0:
			result[item_id] = initial_amount
	return result


static func _validate_missions(errors: Array[String], state) -> void:
	var progress = state.mission_progress
	var seen: Dictionary = {}
	for field_name in ["active_mission_ids", "completed_mission_ids", "failed_mission_ids"]:
		for mission_id_value in progress.get(field_name):
			var mission_id := str(mission_id_value)
			if not _game_database().missions.has(mission_id):
				errors.append("Dziennik zawiera nieznaną misję %s." % mission_id)
			if seen.has(mission_id):
				errors.append("Misja %s występuje w wielu stanach dziennika." % mission_id)
			seen[mission_id] = true
	for field_name in ["started_days", "completed_days", "failed_days"]:
		for mission_id_value in progress.get(field_name).keys():
			var mission_id := str(mission_id_value)
			var changed_day := int(progress.get(field_name)[mission_id_value])
			if not _game_database().missions.has(mission_id) or changed_day < 0 or changed_day > int(state.day):
				errors.append("Metadane dnia misji %s w %s są niepoprawne." % [mission_id, field_name])
	for selected_id in [str(progress.tracked_mission_id), str(progress.resume_mission_id)]:
		if not selected_id.is_empty() and not _game_database().missions.has(selected_id):
			errors.append("Dziennik wskazuje nieznaną śledzoną misję %s." % selected_id)


static func _validate_reports(errors: Array[String], state) -> void:
	if state.end_day_report_history.size() > MAX_END_DAY_REPORT_HISTORY:
		errors.append("Archiwum raportów przekracza limit.")
	var previous_day := 0
	for report in state.end_day_report_history:
		if int(report.day) < 1 or int(report.day) >= int(state.day):
			errors.append("Archiwalny raport nie opisuje zakończonego dnia.")
		if int(report.day) <= previous_day:
			errors.append("Archiwum raportów nie jest ściśle chronologiczne.")
		previous_day = maxi(previous_day, int(report.day))
	if state.last_morning_report != null and (int(state.last_morning_report.day) < 1 or int(state.last_morning_report.day) > int(state.day)):
		errors.append("Raport poranka ma dzień poza kampanią.")
	if state.last_end_day_report != null and (int(state.last_end_day_report.day) < 1 or int(state.last_end_day_report.day) >= int(state.day)):
		errors.append("Ostatni raport dnia ma niepoprawny numer.")
	if int(state.current_phase) == GamePhaseScript.Phase.END_DAY_REPORT:
		if state.last_end_day_report == null or int(state.last_end_day_report.day) != int(state.day) - 1:
			errors.append("Faza END_DAY_REPORT nie ma raportu ostatniego rozliczonego dnia.")
		else:
			var archived_pending_report = null
			for archived_report in state.end_day_report_history:
				if int(archived_report.day) == int(state.last_end_day_report.day):
					archived_pending_report = archived_report
					break
			if archived_pending_report == null:
				errors.append("Raport oczekujący na potwierdzenie nie ma migawki w archiwum.")
			elif not _reports_match(state.last_end_day_report, archived_pending_report):
				errors.append("Raport oczekujący na potwierdzenie różni się od swojej migawki archiwalnej.")


static func _reports_match(first, second) -> bool:
	return (
		first != null
		and second != null
		and int(first.day) == int(second.day)
		and str(first.title) == str(second.title)
		and bool(first.includes_dive) == bool(second.includes_dive)
		and first.entries == second.entries
		and first.warnings == second.warnings
	)


static func _validate_weather_and_pressure(errors: Array[String], state) -> void:
	if int(state.weather.day) != int(state.day):
		errors.append("Pogoda nie odpowiada bieżącemu dniowi.")
	if int(state.weather.condition) < WeatherStateScript.Condition.CALM or int(state.weather.condition) > WeatherStateScript.Condition.STORM:
		errors.append("Pogoda ma nieznany stan.")
	for field_name in ["sea_intensity", "rain_intensity", "foam_intensity", "splash_intensity"]:
		if not _in_float_range(float(state.weather.get(field_name)), 0.0, 1.0):
			errors.append("Pole pogody %s jest poza zakresem." % field_name)
	if not _in_float_range(float(state.weather.motion_intensity), 0.0, 1.4):
		errors.append("Natężenie ruchu pogody jest poza zakresem.")
	if not _in_float_range(float(state.weather.wave_speed_multiplier), 0.5, 1.5):
		errors.append("Mnożnik prędkości fal pogody jest poza zakresem.")
	var wind: Vector2 = state.weather.wind_direction
	if not is_finite(wind.x) or not is_finite(wind.y) or wind.length_squared() < 0.001 or not is_equal_approx(wind.length(), 1.0):
		errors.append("Kierunek wiatru nie jest skończonym wektorem jednostkowym.")
	if not state.pressure_state.is_valid_for_day(int(state.day)):
		errors.append("Migawka presji nie odpowiada bieżącemu dniowi kampanii.")
	_validate_pressure_snapshot(errors, state)


static func _validate_pressure_snapshot(errors: Array[String], state) -> void:
	var pressure = state.pressure_state
	if not _in_float_range(float(pressure.strain), 0.0, 1.0) or not _in_float_range(float(pressure.pressure_budget), 0.0, 3.0) or not is_finite(float(pressure.spent_pressure_budget)) or float(pressure.spent_pressure_budget) < 0.0 or float(pressure.spent_pressure_budget) > float(pressure.pressure_budget) + 0.0001:
		errors.append("Migawka presji ma niepoprawne strain, budget albo wydany budżet.")
	if int(pressure.population) < 0 or not is_finite(float(pressure.food_days)) or float(pressure.food_days) < 0.0:
		errors.append("Migawka presji ma niepoprawną populację lub zapas dni jedzenia.")
	if not _in_float_range(float(pressure.average_hunger), 0.0, 100.0) or int(pressure.max_hunger) < 0 or int(pressure.max_hunger) > 100:
		errors.append("Migawka presji ma niepoprawne metryki głodu.")
	if int(pressure.hope) < 0 or int(pressure.hope) > 100 or int(pressure.platform_integrity) < 0 or int(pressure.platform_integrity) > 100:
		errors.append("Migawka presji ma Nadzieję lub integralność poza zakresem.")
	if int(pressure.healthy_workers) < 0 or int(pressure.healthy_workers) > int(pressure.population):
		errors.append("Migawka presji ma niepoprawną liczbę zdolnych pracowników.")
	if int(pressure.basic_materials) < 0 or int(pressure.medicines) < 0 or int(pressure.shelter_capacity) < 0:
		errors.append("Migawka presji ma ujemne zapasy lub pojemność schronienia.")
	if int(pressure.free_shelter) != int(pressure.shelter_capacity) - int(pressure.population):
		errors.append("Wolne schronienie w migawce presji nie odpowiada pojemności i populacji.")
	if int(pressure.story_act) < StoryProgressStateScript.ACT_COMMON_LINE or int(pressure.story_act) > StoryProgressStateScript.ACT_EPILOGUE:
		errors.append("Migawka presji ma akt fabuły poza zakresem.")
	elif int(pressure.story_act) != int(state.story_flags.act):
		errors.append("Akt fabuły w migawce presji nie odpowiada kampanii.")
	if bool(pressure.crisis_active) != bool(state.story_flags.crisis_active):
		errors.append("Flaga kryzysu w migawce presji nie odpowiada fabule.")
	if int(pressure.weather_condition) != int(state.weather.condition) or bool(pressure.storm_today) != (int(state.weather.condition) == WeatherStateScript.Condition.STORM):
		errors.append("Pogoda zamrożona w presji nie odpowiada migawce pogody dnia.")
	_validate_pressure_daily_limits(errors, pressure)

	_check_unique_known_strings(errors, pressure.critical_gates, VALID_PRESSURE_CRITICAL_GATES, "krytycznych bramek presji")
	_validate_unique_nonempty_strings(errors, pressure.reason_codes, "kodów diagnostycznych presji")
	_check_unique_known_strings(errors, pressure.blocked_impact_tags, VALID_BLOCKED_IMPACT_TAGS, "blokowanych skutków presji")
	_check_unique_known_strings(errors, pressure.preferred_impact_tags, VALID_PREFERRED_IMPACT_TAGS, "preferowanych skutków presji")
	var expected_critical_gates: Array[String] = []
	if float(pressure.food_days) < 0.5:
		expected_critical_gates.append("food_below_half_day")
	if int(pressure.max_hunger) >= 85:
		expected_critical_gates.append("hunger_critical")
	if int(pressure.hope) < 15:
		expected_critical_gates.append("hope_critical")
	if int(pressure.platform_integrity) < 25:
		expected_critical_gates.append("integrity_critical")
	if int(pressure.healthy_workers) <= 1:
		expected_critical_gates.append("workforce_critical")
	if int(pressure.last_diver_death_day) == int(state.day) - 1 and int(state.day) > 1:
		expected_critical_gates.append("diver_died_yesterday")
	if not _same_string_set(pressure.critical_gates, expected_critical_gates):
		errors.append("Krytyczne bramki presji nie odpowiadają jej zamrożonym metrykom.")

	var expected_blocked: Array[String] = []
	if float(pressure.food_days) < 0.5 or int(pressure.max_hunger) >= 85:
		expected_blocked.assign(["food_cost", "food_demand"])
	if int(pressure.platform_integrity) < 25:
		expected_blocked.append("integrity_risk")
	if not _same_string_set(pressure.blocked_impact_tags, expected_blocked):
		errors.append("Blokowane skutki presji nie odpowiadają jej zamrożonym metrykom.")

	var expected_preferred: Array[String] = []
	if float(pressure.food_days) < 1.5 or float(pressure.average_hunger) >= 50.0:
		expected_preferred.append("food_relief")
	if int(pressure.basic_materials) < 20:
		expected_preferred.append("material_relief")
	if int(pressure.healthy_workers) <= 2:
		expected_preferred.append("workforce_relief")
		expected_preferred.append("population_gain")
	if int(pressure.hope) < 35:
		expected_preferred.append("hope_relief")
	if int(pressure.platform_integrity) < 45:
		expected_preferred.append("integrity_relief")
	if int(pressure.medicines) == 0:
		expected_preferred.append("medicine_relief")
	if bool(pressure.disease_outbreak_active) and not expected_preferred.has("medicine_relief"):
		expected_preferred.append("medicine_relief")
	if not _same_string_set(pressure.preferred_impact_tags, expected_preferred):
		errors.append("Preferowane skutki presji nie odpowiadają jej zamrożonym metrykom.")

	var expected_active_tags: Array[String] = []
	if expected_critical_gates.has("food_below_half_day") or expected_critical_gates.has("hunger_critical"):
		expected_active_tags.append("food_critical")
	if expected_critical_gates.has("hope_critical"):
		expected_active_tags.append("hope_critical")
	if expected_critical_gates.has("integrity_critical"):
		expected_active_tags.append("integrity_critical")
	if expected_critical_gates.has("workforce_critical"):
		expected_active_tags.append("workforce_critical")
	if int(pressure.free_shelter) <= 0:
		expected_active_tags.append("no_shelter")
	if expected_critical_gates.has("diver_died_yesterday") or pressure.recent_dive_outcomes.has(PressureStateScript.DIVE_DEATH):
		expected_active_tags.append("recent_death")
	if bool(pressure.storm_today):
		expected_active_tags.append("storm_today")
	if bool(pressure.disease_outbreak_active):
		expected_active_tags.append("disease_outbreak")
	if not _same_string_set(pressure.active_pressure_tags, expected_active_tags):
		errors.append("Aktywne tagi presji nie odpowiadają jej zamrożonym metrykom.")

	var expected_roles: Array[String] = []
	var role_by_preferred_tag := {
		"food_relief": "food", "material_relief": "materials", "workforce_relief": "workforce",
		"population_gain": "workforce", "hope_relief": "hope", "integrity_relief": "integrity", "medicine_relief": "medicine",
	}
	for preferred_tag in expected_preferred:
		var role := str(role_by_preferred_tag.get(preferred_tag, ""))
		if not role.is_empty() and not expected_roles.has(role):
			expected_roles.append(role)
	if expected_active_tags.has("recent_death") and not expected_roles.has("medicine"):
		expected_roles.append("medicine")
	if not _same_string_set(pressure.recovery_roles, expected_roles):
		errors.append("Role regeneracji presji nie odpowiadają jej aktywnym potrzebom.")
	var requires_crisis_band: bool = not pressure.critical_gates.is_empty() or bool(pressure.crisis_active)
	if (int(pressure.band) == PressureStateScript.Band.CRISIS) != requires_crisis_band:
		errors.append("Pasmo CRISIS nie odpowiada krytycznym bramkom ani aktywnemu kryzysowi.")
	if pressure.recent_dive_outcomes.size() > PressureStateScript.MAX_RECENT_DIVES:
		errors.append("Historia ostatnich wypraw w presji przekracza limit.")
	_validate_pressure_outcomes(errors, pressure.recent_dive_outcomes)
	var recent_successes: int = pressure.recent_dive_outcomes.count(PressureStateScript.DIVE_SUCCESS)
	var recent_failures: int = pressure.recent_dive_outcomes.count(PressureStateScript.DIVE_FAILURE) + pressure.recent_dive_outcomes.count(PressureStateScript.DIVE_DEATH)
	if int(pressure.recent_successful_dives) != recent_successes or int(pressure.recent_failed_dives) != recent_failures:
		errors.append("Liczniki ostatnich wypraw nie odpowiadają historii presji.")
	for date_field in ["last_diver_death_day", "last_hardship_event_day"]:
		if int(pressure.get(date_field)) < 0 or int(pressure.get(date_field)) > maxi(int(state.day) - 1, 0):
			errors.append("Pole %s presji wskazuje niemożliwy dzień." % date_field)
	if int(pressure.recovery_days_remaining) < 0 or int(pressure.recovery_days_remaining) > 1 or int(pressure.major_event_cooldown_days_remaining) < 0 or int(pressure.major_event_cooldown_days_remaining) > 2:
		errors.append("Liczniki odpoczynku lub cooldownu presji są poza zakresem producenta.")
	if int(pressure.consecutive_high_days) < 0 or int(pressure.consecutive_high_days) > int(state.day):
		errors.append("Licznik kolejnych dni wysokiej presji jest poza zakresem.")
	elif int(pressure.band) in [PressureStateScript.Band.LOW, PressureStateScript.Band.NORMAL] and int(pressure.consecutive_high_days) != 0:
		errors.append("Niskie lub normalne pasmo presji zachowało licznik wysokich dni.")
	elif int(pressure.band) in [PressureStateScript.Band.HIGH, PressureStateScript.Band.CRISIS] and int(pressure.consecutive_high_days) < 1:
		errors.append("Wysokie lub kryzysowe pasmo presji nie ma dodatniego licznika serii.")
	var expected_recovery_needed: bool = int(pressure.consecutive_high_days) >= 2 or int(pressure.band) == PressureStateScript.Band.CRISIS
	if bool(pressure.recovery_needed) != expected_recovery_needed:
		errors.append("Flaga recovery_needed nie odpowiada serii wysokiej presji.")
	var expected_prefer_relief: bool = (
		int(pressure.band) in [PressureStateScript.Band.HIGH, PressureStateScript.Band.CRISIS]
		or int(pressure.recovery_days_remaining) > 0
		or expected_recovery_needed
		or bool(pressure.disease_outbreak_active)
	)
	if bool(pressure.prefer_relief) != expected_prefer_relief:
		errors.append("Flaga prefer_relief nie odpowiada pasmu ani regeneracji presji.")


static func _validate_pressure_disease_metrics(
	errors: Array[String],
	state,
	living_count: int,
	active_case_count: int,
	contagious_case_count: int
) -> void:
	var pressure = state.pressure_state
	for field_name in ["disease_outbreak_active", "active_disease_cases", "contagious_disease_cases"]:
		if not _has_property(pressure, field_name):
			errors.append("Migawka presji nie ma pola chorobowego %s wymaganego przez bieżący format kampanii." % field_name)
			return
	var stored_active := int(pressure.active_disease_cases)
	var stored_contagious := int(pressure.contagious_disease_cases)
	if stored_active < 0 or stored_contagious < 0 or stored_contagious > stored_active or stored_active > living_count:
		errors.append("Metryki chorobowe presji nie spełniają 0 <= contagious <= active <= living.")
	if stored_active != active_case_count or stored_contagious != contagious_case_count:
		errors.append("Metryki chorobowe presji nie odpowiadają typowanym przypadkom żyjących mieszkańców.")
	if bool(pressure.disease_outbreak_active) != bool(state.disease_campaign.outbreak_active):
		errors.append("Flaga epidemii w presji nie odpowiada stanowi kampanii chorobowej.")


static func _validate_pressure_daily_limits(errors: Array[String], pressure) -> void:
	var expected_budget := clampf((1.0 - float(pressure.strain)) * 3.0, 0.0, 3.0)
	var expected_max_severity := 3
	match int(pressure.band):
		PressureStateScript.Band.NORMAL:
			expected_budget = minf(expected_budget, 2.0)
			expected_max_severity = 2
		PressureStateScript.Band.HIGH:
			expected_budget = minf(expected_budget, 0.75)
			expected_max_severity = 1
		PressureStateScript.Band.CRISIS:
			expected_budget = 0.0
			expected_max_severity = 1
	if bool(pressure.storm_today):
		expected_budget = minf(expected_budget, 0.5)
		expected_max_severity = mini(expected_max_severity, 1)
	if int(pressure.recovery_days_remaining) > 0:
		expected_budget = 0.0
		expected_max_severity = mini(expected_max_severity, 1)
	elif bool(pressure.recovery_needed):
		expected_budget = minf(expected_budget, 0.25)
		expected_max_severity = mini(expected_max_severity, 1)
	if bool(pressure.tutorial_protected):
		expected_budget = 0.0
		expected_max_severity = 0
	elif bool(pressure.disease_outbreak_active):
		expected_max_severity = mini(expected_max_severity, 1)
	if not is_equal_approx(float(pressure.pressure_budget), expected_budget) or int(pressure.max_event_severity) != expected_max_severity:
		errors.append("Limity wydarzeń presji nie odpowiadają zamrożonym metrykom dnia.")


static func _validate_pressure_outcomes(errors: Array[String], values: Array) -> void:
	for outcome in values:
		if str(outcome) not in [PressureStateScript.DIVE_SUCCESS, PressureStateScript.DIVE_FAILURE, PressureStateScript.DIVE_DEATH]:
			errors.append("Historia presji zawiera nieznany wynik wyprawy %s." % outcome)


static func _validate_day_plan(errors: Array[String], state, survivor_by_id: Dictionary, building_by_id: Dictionary) -> void:
	var plan = state.current_day_plan
	if int(plan.day) != int(state.day):
		errors.append("Plan dnia nie odpowiada bieżącemu dniowi.")
	if bool(plan.locked):
		errors.append("Punkt autosave nie może zawierać zablokowanego planu przejściowego.")
	if int(plan.ration_policy) not in [PolicyStateScript.RationPolicy.FULL, PolicyStateScript.RationPolicy.HALF, PolicyStateScript.RationPolicy.NONE, PolicyStateScript.RationPolicy.DIVER_PRIORITY]:
		errors.append("Plan dnia ma nieznaną politykę racji.")
	elif int(plan.ration_policy) != int(state.active_policies.ration_policy):
		errors.append("Edytowalny plan dnia i kanoniczna polityka racji są rozjechane.")
	_validate_planned_survivor_ids(errors, plan.medical_priority_survivor_ids, survivor_by_id, "priorytetu medycznego")
	_validate_planned_survivor_ids(errors, plan.isolated_survivor_ids, survivor_by_id, "izolacji")
	_validate_selected_diver(errors, state, plan, survivor_by_id)
	var expected_work_paces: Dictionary = {}
	var expected_assignments: Dictionary = {}
	var expected_orders: Array[Dictionary] = []
	for building in state.buildings:
		expected_work_paces[str(building.id)] = str(building.work_pace)
		expected_assignments[str(building.id)] = building.assigned_survivor_ids.duplicate()
		if not bool(building.is_built):
			expected_orders.append({"type": "construction", "building_id": str(building.id)})
		elif int(building.pending_level) > int(building.level):
			expected_orders.append({"type": "upgrade", "building_id": str(building.id), "target_level": int(building.pending_level)})
		for production_order in building.queued_production_orders:
			if production_order == null:
				continue
			expected_orders.append({
				"type": "production",
				"building_id": str(building.id),
				"order_instance_id": str(production_order.instance_id),
				"recipe_id": str(production_order.recipe_id),
			})
	if plan.building_work_paces != expected_work_paces:
		errors.append("Migawka temp planu dnia nie odpowiada kanonicznym tempom budynków.")
	if plan.worker_assignments != expected_assignments:
		errors.append("Migawka obsady planu dnia nie odpowiada uporządkowanym rosterom budynków.")
	if plan.building_orders != expected_orders:
		errors.append("Migawka zleceń planu dnia nie odpowiada kanonicznemu stanowi budynków.")
	for building_id_value in plan.worker_assignments.keys():
		var building_id := str(building_id_value)
		if not building_by_id.has(building_id) or not (plan.worker_assignments[building_id_value] is Array):
			errors.append("Plan dnia ma wiszący lub źle zapisany przydział budynku %s." % building_id)
			continue
		for survivor_id in plan.worker_assignments[building_id_value]:
			if not survivor_by_id.has(str(survivor_id)):
				errors.append("Plan dnia wskazuje nieistniejącego mieszkańca %s." % survivor_id)
	for building_id_value in plan.building_work_paces.keys():
		var building_id := str(building_id_value)
		var planned_pace := str(plan.building_work_paces[building_id_value])
		if not building_by_id.has(building_id):
			errors.append("Plan dnia ma tempo dla nieistniejącego budynku %s." % building_id)
		elif not _is_valid_work_pace(planned_pace):
			errors.append("Plan dnia ma nieznane tempo %s dla budynku %s." % [planned_pace, building_id])
	for order in plan.building_orders:
		var building_id := str(order.get("building_id", ""))
		if not building_by_id.has(building_id) or str(order.get("type", "")) not in ["construction", "upgrade", "production"]:
			errors.append("Plan dnia zawiera niepoprawne zlecenie budynku.")
	if plan.expedition_setup != null and int(plan.expedition_setup.day) != int(state.day):
		errors.append("Wyprawa w planie należy do innego dnia.")
	if plan.expedition_setup != null:
		errors.append("Edytowalny punkt autosave nie może zachowywać przejściowej migawki wyprawy w planie.")
	var entry_point_id := str(plan.expedition_entry_point)
	if not entry_point_id.is_empty() and state.underwater_world.blueprint.resolve_landmark_id(entry_point_id).is_empty():
		errors.append("Plan dnia wskazuje nieznany punkt wejścia wyprawy %s." % entry_point_id)


static func _validate_selected_diver(errors: Array[String], state, plan, survivor_by_id: Dictionary) -> void:
	var selected_diver_id := str(plan.selected_diver_id)
	if selected_diver_id.is_empty():
		return
	if not survivor_by_id.has(selected_diver_id):
		errors.append("Wybrany nurek planu dnia %s nie istnieje." % selected_diver_id)
		return
	var survivor = survivor_by_id[selected_diver_id]
	if not survivor.is_alive() or not survivor.is_present_in_settlement():
		errors.append("Wybrany nurek %s nie jest żyjący i obecny w Przystani." % selected_diver_id)
	if selected_diver_id in plan.isolated_survivor_ids:
		errors.append("Wybrany nurek %s jest objęty izolacją w planie dnia." % selected_diver_id)
	for building in state.buildings:
		if building != null and selected_diver_id in building.assigned_survivor_ids:
			errors.append("Wybrany nurek %s pozostaje w rosterze budynku %s." % [selected_diver_id, building.id])
	var reverse_assignment := str(survivor.current_assignment).strip_edges()
	if not reverse_assignment.is_empty():
		errors.append("Wybrany nurek %s ma niepusty odwrotny przydział %s." % [selected_diver_id, reverse_assignment])
	if not survivor.can_dive():
		errors.append("Wybrany nurek %s nie spełnia warunków can_dive()." % selected_diver_id)


static func _validate_preferred_diver(errors: Array[String], state, survivor_by_id: Dictionary) -> void:
	var preferred_diver_id := str(state.preferred_diver_id).strip_edges()
	if preferred_diver_id.is_empty():
		return
	if not survivor_by_id.has(preferred_diver_id):
		errors.append("Zapamiętany nurek %s nie istnieje." % preferred_diver_id)
		return
	var survivor = survivor_by_id[preferred_diver_id]
	if not survivor.is_alive():
		errors.append("Zapamiętany nurek %s nie żyje ani nie jest dostępny w kampanii." % preferred_diver_id)


static func _validate_planned_survivor_ids(
	errors: Array[String],
	values: Array,
	survivor_by_id: Dictionary,
	context: String
) -> void:
	var seen_ids: Dictionary = {}
	for raw_survivor_id in values:
		var survivor_id := str(raw_survivor_id).strip_edges()
		if survivor_id.is_empty() or seen_ids.has(survivor_id):
			errors.append("Lista %s zawiera pusty lub powtórzony identyfikator %s." % [context, survivor_id])
			continue
		seen_ids[survivor_id] = true
		if not survivor_by_id.has(survivor_id):
			errors.append("Lista %s wskazuje nieistniejącego mieszkańca %s." % [context, survivor_id])
		elif not survivor_by_id[survivor_id].is_alive() or not survivor_by_id[survivor_id].is_present_in_settlement():
			errors.append("Lista %s wskazuje nieżyjącego lub nieobecnego mieszkańca %s." % [context, survivor_id])


static func _validate_runtime_snapshots(errors: Array[String], state, survivor_by_id: Dictionary) -> void:
	if state.current_expedition_setup != null:
		errors.append("Punkt autosave nie może zachowywać przejściowego current_expedition_setup.")
	for setup in [state.current_expedition_setup, state.current_day_plan.expedition_setup]:
		if setup == null:
			continue
		if str(setup.diver_id).is_empty() or not survivor_by_id.has(str(setup.diver_id)):
			errors.append("Migawka wyprawy wskazuje nieistniejącego nurka.")
		_validate_expedition_carry_snapshot(errors, setup)
		if _has_property(setup, "profession_talent_ids"):
			_validate_profession_talent_map(
				errors,
				setup.get("profession_talent_ids"),
				[str(setup.diver_profession), str(setup.diver_secondary_profession)],
				"migawki wyprawy nurka %s" % str(setup.diver_id),
				ProfessionTalentSystemScript.new()
			)
		else:
			errors.append("Migawka wyprawy nie ma wymaganej mapy profession_talent_ids.")
		for gear_id in setup.selected_gear:
			if str(gear_id) not in ["knife", "crowbar", "repair_kit", "lift_bag"] and not _game_database().diving_gear.has(str(gear_id)):
				errors.append("Migawka wyprawy wskazuje nieznane wyposażenie %s." % gear_id)
		for slot_id in setup.equipped_gear.keys():
			var gear_id := str(setup.equipped_gear[slot_id])
			if not _game_database().diving_gear.has(gear_id) or str(_game_database().diving_gear[gear_id].equipment_slot) != str(slot_id):
				errors.append("Migawka wyprawy ma niepoprawne wyposażenie %s w slocie %s." % [gear_id, slot_id])
	if state.last_dive_result != null:
		var result = state.last_dive_result
		var result_diver_id := str(result.diver_id)
		if result_diver_id.is_empty() or not survivor_by_id.has(result_diver_id):
			errors.append("Ostatni wynik wyprawy nie wskazuje nurka z trwałego rosteru.")
		if bool(result.returned_alive) == bool(result.diver_dead):
			errors.append("Ostatni wynik wyprawy nie ma dokładnie jednego terminalnego wyniku: powrót albo śmierć.")
		if bool(result.diver_dead):
			if int(result.health_remaining) not in [-1, 0]:
				errors.append("Śmiertelny wynik wyprawy musi zapisywać health_remaining jako sentinel -1 albo 0.")
			if survivor_by_id.has(result_diver_id) and int(survivor_by_id[result_diver_id].status) != SurvivorStateScript.Status.DEAD:
				errors.append("Śmiertelny wynik wyprawy nie odpowiada statusowi nurka w rosterze.")
		elif bool(result.returned_alive):
			var health_remaining := int(result.health_remaining)
			if health_remaining < -1 or health_remaining == 0:
				errors.append("Bezpieczny powrót z wyprawy ma niepoprawne health_remaining; dozwolony jest sentinel -1 albo dodatnia wartość.")
			elif health_remaining > 0 and survivor_by_id.has(result_diver_id) and health_remaining > int(survivor_by_id[result_diver_id].get_max_health()):
				errors.append("Bezpieczny powrót z wyprawy ma health_remaining powyżej maksymalnego zdrowia nurka.")
		if bool(result.emergency_extraction) and (not bool(result.returned_alive) or bool(result.diver_dead)):
			errors.append("Awaryjne wyciągnięcie ma niespójny terminalny wynik nurka.")
		if not is_finite(float(result.oxygen_remaining)) or float(result.oxygen_remaining) < 0.0 or not _in_float_range(float(result.cold_exposure), 0.0, 100.0) or not is_finite(float(result.dive_duration)) or float(result.dive_duration) < 0.0:
			errors.append("Ostatni wynik wyprawy ma niepoprawne metryki tlenu, zimna lub czasu.")
		if int(result.suit_condition_remaining) < 0 or int(result.suit_condition_remaining) > 100 or int(result.repair_kit_uses) < 0 or int(result.experience_gained) < 0:
			errors.append("Ostatni wynik wyprawy ma niepoprawny stan sprzętu lub postęp.")
		_validate_item_amounts(errors, result.collected_items, "wyniku wyprawy")
		_validate_item_amounts(errors, result.lost_items, "utraconego łupu wyprawy")
		for rescued_survivor in result.rescued_survivors:
			if rescued_survivor != null and not survivor_by_id.has(str(rescued_survivor.id)):
				errors.append("Ostatni wynik wyprawy zawiera uratowaną osobę nieobecną w trwałym rosterze: %s." % rescued_survivor.id)
			if _is_exact(rescued_survivor, SurvivorStateScript):
				_validate_profession_talent_map(
					errors,
					rescued_survivor.profession_talent_ids,
					[str(rescued_survivor.profession), str(rescued_survivor.secondary_profession)],
					"migawki uratowanej osoby %s" % rescued_survivor.id,
					ProfessionTalentSystemScript.new(),
					rescued_survivor
				)
				var known_disease_ids: Array[String] = []
				for disease_id_value in _game_database().diseases.keys():
					known_disease_ids.append(str(disease_id_value))
				_validate_disease_case_collection(
					errors,
					rescued_survivor.disease_cases,
					known_disease_ids,
					int(state.day),
					int(state.disease_campaign.last_resolved_day),
					"migawki uratowanej osoby %s" % rescued_survivor.id
				)
		_validate_last_dive_result_links(errors, state, result, survivor_by_id)
	if int(state.tutorial.step) < TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE or int(state.tutorial.step) > TutorialStateScript.Step.COMPLETED:
		errors.append("Tutorial ma nieznany krok.")


static func _validate_expedition_carry_snapshot(errors: Array[String], setup) -> void:
	var staffed_multiplier := float(setup.station_staffed_carry_multiplier)
	if not is_finite(staffed_multiplier) or (staffed_multiplier != 1.0 and staffed_multiplier != 1.05):
		errors.append("Migawka wyprawy ma niepoprawny station_staffed_carry_multiplier; dozwolone jest dokładnie 1.0 albo 1.05.")
	var carry_capacity := float(setup.diver_carry_capacity)
	if not is_finite(carry_capacity) or carry_capacity <= 0.0:
		errors.append("Migawka wyprawy ma niepoprawny diver_carry_capacity; wymagany jest skończony dodatni udźwig.")


static func _validate_last_dive_result_links(errors: Array[String], state, result, survivor_by_id: Dictionary) -> void:
	for field_name in [
		"discovered_sectors", "placed_buoys", "opened_shortcuts", "activated_fixed_devices", "opened_containers", "collected_world_item_ids",
		"marked_heavy_objects", "recovered_gear_ids", "story_flags_unlocked", "lost_gear", "diver_injuries", "noise_events", "risk_events",
	]:
		_validate_unique_nonempty_strings(errors, result.get(field_name), "pola last_dive_result.%s" % field_name)

	var allowed_lost_gear: Dictionary = {"knife": true, "crowbar": true, "repair_kit": true, "lift_bag": true}
	for gear_id in _game_database().diving_gear.keys():
		allowed_lost_gear[str(gear_id)] = true
	for gear_id_value in result.lost_gear:
		if not allowed_lost_gear.has(str(gear_id_value)):
			errors.append("Ostatni wynik wyprawy zawiera nieznane utracone wyposażenie %s." % gear_id_value)
	for gear_id_value in result.recovered_gear_ids:
		var recovered_gear_id := str(gear_id_value)
		if not _game_database().diving_gear.has(recovered_gear_id):
			errors.append("Ostatni wynik wyprawy zawiera nieznane odzyskane wyposażenie %s." % gear_id_value)
		elif bool(result.returned_alive) and not state.diving_equipment.owns(recovered_gear_id):
			errors.append("Odzyskane wyposażenie %s z bezpiecznej wyprawy nie istnieje w trwałym magazynie." % recovered_gear_id)
		elif bool(result.diver_dead):
			var death_backpack: Dictionary = state.underwater_world.delta.lost_backpacks.get(str(result.diver_id), {})
			if not death_backpack.get("gear_ids", []).has(recovered_gear_id):
				errors.append("Odzyskane wyposażenie %s ze śmiertelnej wyprawy nie trafiło do trwałego plecaka." % recovered_gear_id)

	var blueprint = state.underwater_world.blueprint
	var delta = state.underwater_world.delta
	var container_ids: Dictionary = {}
	var collected_world_item_ids: Dictionary = {}
	for loot_spawn in blueprint.loot_spawns:
		var loot_id := str(loot_spawn.get("id", ""))
		if str(loot_spawn.get("spawn_kind", "container")) == "pickup":
			collected_world_item_ids[loot_id] = true
		else:
			container_ids[loot_id] = true
			var contents = loot_spawn.get("contents", {})
			if contents is Dictionary:
				for item_id in contents.keys():
					collected_world_item_ids["%s:%s" % [loot_id, str(item_id)]] = true
	var shortcut_ids := _plain_record_ids(blueprint.shortcut_spawns)
	var fixed_device_ids := _plain_record_ids(blueprint.fixed_device_spawns)
	var heavy_ids := _plain_record_ids(blueprint.heavy_object_spawns)
	var rescue_ids: Dictionary = {}
	for rescue_spawn in blueprint.rescue_spawns:
		rescue_ids[str(rescue_spawn.get("id", ""))] = rescue_spawn
	var buoy_ids := _plain_record_ids(blueprint.buoy_spawns)

	for landmark_id_value in result.discovered_sectors:
		var landmark_id := str(landmark_id_value)
		var canonical_id := str(blueprint.resolve_landmark_id(landmark_id))
		if canonical_id.is_empty():
			errors.append("Ostatni wynik wyprawy wskazuje nieznany odkryty landmark %s." % landmark_id)
		elif not _landmark_array_contains(blueprint, delta.discovered_landmarks, canonical_id):
			errors.append("Odkryty landmark %s z ostatniej wyprawy nie istnieje w trwałym WorldDelta." % landmark_id)
	for buoy_id_value in result.placed_buoys:
		var buoy_id := str(buoy_id_value)
		if not buoy_ids.has(buoy_id) or not delta.placed_buoys.has(buoy_id):
			errors.append("Boja %s z ostatniej wyprawy nie jest legalna lub nie została utrwalona." % buoy_id)
	for connection_id_value in result.opened_shortcuts:
		var connection_id := str(connection_id_value)
		if not shortcut_ids.has(connection_id) or not delta.opened_shortcuts.has(connection_id):
			errors.append("Skrót %s z ostatniej wyprawy nie jest legalny lub nie został utrwalony." % connection_id)
	for device_id_value in result.activated_fixed_devices:
		var device_id := str(device_id_value)
		if not fixed_device_ids.has(device_id) or not delta.activated_fixed_devices.has(device_id):
			errors.append("Urządzenie %s z ostatniej wyprawy nie jest legalne lub nie zostało utrwalone." % device_id)
	for container_id_value in result.opened_containers:
		var container_id := str(container_id_value)
		if not container_ids.has(container_id) or not delta.opened_containers.has(container_id):
			errors.append("Otwarte źródło %s z ostatniej wyprawy nie jest legalne ani utrwalone." % container_id)
		if result.remaining_container_contents.has(container_id):
			errors.append("Ostatnia wyprawa oznacza źródło %s jednocześnie jako puste i częściowo zachowane." % container_id)
	for world_item_id_value in result.collected_world_item_ids:
		var world_item_id := str(world_item_id_value)
		if not collected_world_item_ids.has(world_item_id) or not delta.collected_items.has(world_item_id):
			errors.append("Obiekt świata %s z ostatniej wyprawy nie jest legalny lub nie został utrwalony." % world_item_id)
	for heavy_id_value in result.marked_heavy_objects:
		var heavy_id := str(heavy_id_value)
		if not heavy_ids.has(heavy_id) or (not delta.marked_heavy_objects.has(heavy_id) and not delta.recovered_heavy_objects.has(heavy_id)):
			errors.append("Ciężki obiekt %s z ostatniej wyprawy nie jest legalny ani utrwalony jako oznaczony lub odzyskany." % heavy_id)

	for container_id_value in result.remaining_container_contents.keys():
		var container_id := str(container_id_value)
		if not container_ids.has(container_id):
			errors.append("Ostatni wynik wyprawy zachowuje zawartość nieznanego źródła %s." % container_id)
		_validate_item_amounts(errors, result.remaining_container_contents[container_id_value], "pozostałej zawartości wyprawy %s" % container_id)
		if not delta.remaining_container_contents.has(container_id) or delta.remaining_container_contents[container_id] != result.remaining_container_contents[container_id_value]:
			errors.append("Pozostała zawartość źródła %s nie odpowiada trwałemu WorldDelta." % container_id)

	_validate_last_dive_backpack_updates(errors, result, delta)
	_validate_last_dive_dropped_loot_updates(errors, result, delta)
	_validate_last_dive_rescue(errors, result, delta, rescue_ids, survivor_by_id)

	if bool(result.returned_alive) and not bool(result.emergency_extraction) and not result.lost_items.is_empty():
		errors.append("Zwykły bezpieczny powrót nie może zawierać utraconego łupu.")
	if (bool(result.diver_dead) or bool(result.emergency_extraction)) and not result.collected_items.is_empty():
		errors.append("Śmierć albo wyciągnięcie Operatora nie może jednocześnie przyznać łupu osadzie.")
	if bool(result.diver_dead):
		var diver_id := str(result.diver_id)
		var body_landmark := str(blueprint.resolve_landmark_id(str(result.body_location_if_dead)))
		if body_landmark.is_empty():
			errors.append("Śmiertelny wynik wyprawy nie wskazuje legalnego landmarku ciała.")
		elif not delta.dead_divers.has(diver_id) or str(blueprint.resolve_landmark_id(str(delta.dead_divers.get(diver_id, "")))) != body_landmark:
			errors.append("Położenie ciała w ostatnim wyniku nie odpowiada trwałemu WorldDelta.")
		if not delta.lost_backpacks.has(diver_id):
			errors.append("Śmiertelny wynik wyprawy nie ma trwałego rekordu plecaka nurka.")
		if str(result.backpack_location_if_lost).strip_edges().is_empty():
			errors.append("Śmiertelny wynik wyprawy nie ma opisu położenia plecaka.")
		if not is_finite(result.death_world_position.x) or not is_finite(result.death_world_position.y):
			errors.append("Śmiertelny wynik wyprawy ma niepoprawną pozycję śmierci.")


static func _validate_last_dive_backpack_updates(errors: Array[String], result, delta) -> void:
	for backpack_id_value in result.recovered_backpacks.keys():
		var backpack_id := str(backpack_id_value).strip_edges()
		var update: Dictionary = result.recovered_backpacks[backpack_id_value]
		if backpack_id.is_empty() or not delta.lost_backpacks.has(backpack_id):
			errors.append("Aktualizacja plecaka %s z ostatniej wyprawy nie ma trwałego rekordu." % backpack_id)
			continue
		_validate_item_amounts(errors, update.get("items", {}), "aktualizacji plecaka %s" % backpack_id)
		if not (update.get("gear_ids", null) is Array) or typeof(update.get("recovered", null)) != TYPE_BOOL:
			errors.append("Aktualizacja plecaka %s ma niepoprawny gear_ids albo recovered." % backpack_id)
			continue
		_validate_unique_nonempty_strings(errors, update.get("gear_ids", []), "odzyskiwanego wyposażenia plecaka %s" % backpack_id)
		for gear_id in update.get("gear_ids", []):
			if not _game_database().diving_gear.has(str(gear_id)):
				errors.append("Aktualizacja plecaka %s zawiera nieznane wyposażenie %s." % [backpack_id, gear_id])
		var persisted: Dictionary = delta.lost_backpacks[backpack_id]
		for field_name in ["items", "gear_ids", "recovered"]:
			if persisted.get(field_name) != update.get(field_name):
				errors.append("Aktualizacja plecaka %s nie odpowiada WorldDelta w polu %s." % [backpack_id, field_name])


static func _validate_last_dive_dropped_loot_updates(errors: Array[String], result, delta) -> void:
	for pile_id_value in result.dropped_loot_updates.keys():
		var pile_id := str(pile_id_value).strip_edges()
		var update: Dictionary = result.dropped_loot_updates[pile_id_value]
		if pile_id.is_empty():
			errors.append("Aktualizacja porzuconego łupu ma pusty identyfikator.")
			continue
		_validate_item_amounts(errors, update.get("items", {}), "aktualizacji pakunku %s" % pile_id)
		if typeof(update.get("recovered", null)) != TYPE_BOOL:
			errors.append("Aktualizacja pakunku %s nie ma logicznej flagi recovered." % pile_id)
		var items = update.get("items", {})
		var is_tombstone: bool = bool(update.get("recovered", false)) or not (items is Dictionary) or items.is_empty()
		if is_tombstone:
			if delta.dropped_loot_piles.has(pile_id):
				errors.append("Odzyskany pakunek %s nadal istnieje w trwałym świecie." % pile_id)
			continue
		var expected: Dictionary = update.duplicate(true)
		expected["persistence_id"] = pile_id
		expected["items"] = items.duplicate(true)
		expected["created_day"] = maxi(int(expected.get("created_day", 0)), 0)
		expected["recovered"] = false
		if not delta.dropped_loot_piles.has(pile_id) or delta.dropped_loot_piles[pile_id] != expected:
			errors.append("Aktywny pakunek %s z ostatniej wyprawy nie odpowiada trwałemu WorldDelta." % pile_id)


static func _validate_last_dive_rescue(errors: Array[String], result, delta, rescue_ids: Dictionary, survivor_by_id: Dictionary) -> void:
	if result.rescued_survivors.size() > 1 or result.rescue_outcomes.size() > 1:
		errors.append("Jedna wyprawa nie może zawierać więcej niż jednego wyniku ratunku.")
	var rescued_ids: Dictionary = {}
	for survivor in result.rescued_survivors:
		var survivor_id := str(survivor.id).strip_edges()
		if survivor_id.is_empty() or rescued_ids.has(survivor_id) or not survivor_by_id.has(survivor_id):
			errors.append("Migawka uratowanej osoby ma pusty, powtórzony lub nieutrwalony identyfikator %s." % survivor_id)
		rescued_ids[survivor_id] = true
	for encounter_id_value in result.rescue_outcomes.keys():
		var encounter_id := str(encounter_id_value).strip_edges()
		var outcome: Dictionary = result.rescue_outcomes[encounter_id_value]
		var status := str(outcome.get("status", ""))
		var survivor_id := str(outcome.get("survivor_id", "")).strip_edges()
		var rescue_spawn: Dictionary = rescue_ids.get(encounter_id, {})
		var rescue_definition_id := str(rescue_spawn.get("definition_id", ""))
		var rescue_definition = _game_database().rescue_encounters.get(rescue_definition_id)
		var authored_survivor_id := str(rescue_definition.survivor_id) if rescue_definition != null else ""
		if not rescue_ids.has(encounter_id) or status not in ["rescued", "dead"] or survivor_id.is_empty() or survivor_id != authored_survivor_id or typeof(outcome.get("stabilized", null)) != TYPE_BOOL:
			errors.append("Wynik ratunku %s ma nieznane ID, status albo niepełny rekord." % encounter_id)
		if not delta.rescued_or_dead_survivors.has(encounter_id) or delta.rescued_or_dead_survivors[encounter_id] != outcome:
			errors.append("Wynik ratunku %s nie odpowiada trwałemu WorldDelta." % encounter_id)
		if status == "rescued" and (not bool(result.returned_alive) or rescued_ids.size() != 1 or not rescued_ids.has(survivor_id)):
			errors.append("Status rescued nie odpowiada bezpiecznemu powrotowi i migawce uratowanej osoby.")
		elif status == "dead" and (not bool(result.diver_dead) or not rescued_ids.is_empty()):
			errors.append("Status dead spotkania ratunkowego nie odpowiada śmierci wyprawy.")
	if not rescued_ids.is_empty() and result.rescue_outcomes.is_empty():
		errors.append("Uratowana osoba nie ma odpowiadającego wyniku spotkania ratunkowego.")


static func _plain_record_ids(records: Array) -> Dictionary:
	var result: Dictionary = {}
	for record in records:
		result[str(record.get("id", ""))] = true
	return result


static func _landmark_array_contains(blueprint, values: Array, canonical_id: String) -> bool:
	for value in values:
		if str(blueprint.resolve_landmark_id(str(value))) == canonical_id:
			return true
	return false


static func _validate_workshop_orders(errors: Array[String], state) -> void:
	var workshops: Array = []
	var known_gear: Array[String] = []
	for gear_id in _game_database().diving_gear.keys():
		known_gear.append(str(gear_id))
	for building in state.buildings:
		if str(building.definition_id) == "workshop":
			workshops.append(building)
		for order_error in building.production_order_validation_errors(ResourceIdsScript.all(), known_gear):
			errors.append(order_error)
		if str(building.definition_id) == "workshop":
			var definition = _game_database().buildings.get("workshop")
			var level_definition = definition.get_level_definition(int(building.level)) if definition != null else null
			var queue_capacity := maxi(int(level_definition.capabilities.get("production_queue_capacity", 1)), 1) if level_definition != null else 1
			if building.queued_production_orders.size() > queue_capacity:
				errors.append("Warsztat %s przekracza pojemność kolejki %d." % [building.id, queue_capacity])
			var previous_normal_sequence := 0
			for order in building.queued_production_orders:
				if order != null and int(order.queued_day) > int(state.day):
					errors.append("Zlecenie %s pochodzi z przyszłego dnia." % order.instance_id)
				if order == null or order.get_script() != WorkshopOrderStateScript:
					continue
				var sequence := int(order.sequence_number(str(building.id)))
				if sequence <= previous_normal_sequence:
					errors.append("Kolejka Warsztatu %s narusza rosnące FIFO sekwencji." % building.id)
				previous_normal_sequence = maxi(previous_normal_sequence, sequence)
	if workshops.size() > 1:
		errors.append("Kampania zawiera więcej niż jeden Warsztat.")


static func _validate_events(errors: Array[String], state, survivor_by_id: Dictionary) -> void:
	var previous_day := 0
	for event_state in state.settlement_event_history:
		if int(event_state.status) != SettlementEventStateScript.Status.RESOLVED:
			errors.append("Historia wydarzeń zawiera wpis nierozstrzygnięty.")
		if int(event_state.offered_day) < 1 or int(event_state.offered_day) != int(event_state.resolved_day) or int(event_state.resolved_day) > int(state.day):
			errors.append("Historia wydarzeń ma niespójną relację dni.")
		if int(event_state.offered_day) <= previous_day:
			errors.append("Historia wydarzeń nie jest ściśle rosnąca po dniu oferty.")
		previous_day = maxi(previous_day, int(event_state.offered_day))
		if str(event_state.event_id).is_empty() or str(event_state.selected_choice_id).is_empty():
			errors.append("Rozstrzygnięte wydarzenie nie ma ID lub wyboru.")
		if str(event_state.instance_id) != "%s:%d" % [str(event_state.event_id), int(event_state.offered_day)]:
			errors.append("Rozstrzygnięte wydarzenie ma niespójne instance_id.")
		_validate_resource_delta_dictionary(errors, event_state.applied_resource_deltas, "historii wydarzenia %s" % event_state.event_id)
		var added_ids: Dictionary = {}
		for survivor_id_value in event_state.added_survivor_ids:
			var survivor_id := str(survivor_id_value)
			if survivor_id.is_empty() or added_ids.has(survivor_id) or not survivor_by_id.has(survivor_id):
				errors.append("Historia wydarzenia %s ma pustą, powtórzoną lub nieistniejącą dodaną osobę %s." % [event_state.event_id, survivor_id])
			added_ids[survivor_id] = true
		_append_history_metadata_errors(errors, event_state)
	if state.pending_settlement_event == null:
		if int(state.current_phase) == GamePhaseScript.Phase.DAY_START_REPORT:
			errors.append("Faza DAY_START_REPORT nie ma oczekującego wydarzenia.")
		return
	var pending = state.pending_settlement_event
	if (
		int(pending.status) != SettlementEventStateScript.Status.PENDING
		or not str(pending.selected_choice_id).is_empty()
		or int(pending.resolved_day) != 0
		or not str(pending.result_text).is_empty()
		or not pending.applied_resource_deltas.is_empty()
		or not pending.added_survivor_ids.is_empty()
	):
		errors.append("Oczekujące wydarzenie ma stan inny niż czyste PENDING.")
	if int(pending.offered_day) != int(state.day):
		errors.append("Oczekujące wydarzenie nie należy do bieżącego dnia.")
	if int(state.current_phase) not in [GamePhaseScript.Phase.END_DAY_REPORT, GamePhaseScript.Phase.DAY_START_REPORT]:
		errors.append("Oczekujące wydarzenie istnieje poza raportem końca dnia lub obowiązkową fazą decyzji poranka.")
	if previous_day >= int(pending.offered_day):
		errors.append("Historia i pending wydarzenie zajmują ten sam lub późniejszy poranek.")
	if str(pending.instance_id) != "%s:%d" % [str(pending.event_id), int(pending.offered_day)]:
		errors.append("Oczekujące wydarzenie ma niespójne instance_id.")
	_validate_pending_snapshot(errors, state, pending, survivor_by_id)


static func _validate_morning_commitment(errors: Array[String], state) -> void:
	var roll_day := int(state.settlement_event_roll_day)
	if roll_day < 0 or roll_day > int(state.day):
		errors.append("Dzień losowania wydarzenia osady jest poza osią czasu kampanii.")
	var pressure = state.pressure_state
	if pressure == null or not pressure.has_method("has_committed_morning"):
		errors.append("Migawka presji nie obsługuje audytu decyzji poranka.")
		return
	var has_commitment: bool = pressure.has_committed_morning()
	var terminal_phase: bool = int(state.current_phase) in [GamePhaseScript.Phase.GAME_OVER, GamePhaseScript.Phase.ENDING]
	if not terminal_phase:
		if int(state.day) >= 3 and roll_day != int(state.day):
			errors.append("Trwały stan dnia nie zawiera wyniku losowania bieżącego poranka.")
		if not has_commitment:
			errors.append("Migawka presji nie ma zapisanego wyniku decyzji poranka.")

	var pending = state.pending_settlement_event
	if pending != null:
		if roll_day != int(state.day) or int(pending.offered_day) != int(state.day):
			errors.append("Oczekujące wydarzenie i audyt losowania nie należą do bieżącego poranka.")
		if not has_commitment or bool(pressure.quiet_morning) or str(pressure.committed_event_id) != str(pending.event_id):
			errors.append("Commit presji nie odpowiada oczekującemu wydarzeniu poranka.")
		else:
			_append_committed_event_metadata_errors(errors, pressure, pending)
		return

	if terminal_phase:
		return
	if int(state.day) < 3:
		if has_commitment and not bool(pressure.quiet_morning):
			errors.append("Chroniony poranek tutoriala musi być zapisany jako spokojny.")
		return
	if not has_commitment or bool(pressure.quiet_morning):
		return
	var resolved_event = null
	for index in range(state.settlement_event_history.size() - 1, -1, -1):
		var candidate = state.settlement_event_history[index]
		if int(candidate.offered_day) == int(state.day) and int(candidate.resolved_day) == int(state.day):
			resolved_event = candidate
			break
	if resolved_event == null or str(resolved_event.event_id) != str(pressure.committed_event_id):
		errors.append("Commit wydarzenia poranka nie ma odpowiadającego wpisu w historii decyzji.")
		return
	_append_committed_event_metadata_errors(errors, pressure, resolved_event)


static func _append_committed_event_metadata_errors(errors: Array[String], pressure, event_state) -> void:
	if str(pressure.committed_event_tone) != str(event_state.tone):
		errors.append("Ton commitu presji nie odpowiada zamrożonej ofercie wydarzenia %s." % event_state.event_id)
	if int(pressure.committed_event_severity) != int(event_state.severity):
		errors.append("Dotkliwość commitu presji nie odpowiada zamrożonej ofercie wydarzenia %s." % event_state.event_id)
	if not is_equal_approx(float(pressure.spent_pressure_budget), float(event_state.pressure_cost)):
		errors.append("Koszt presji commitu nie odpowiada zamrożonej ofercie wydarzenia %s." % event_state.event_id)


static func _append_event_snapshot_preflight(errors: Array[String], state) -> void:
	if state.pending_settlement_event != null:
		var snapshot = state.pending_settlement_event.get("offer_snapshot")
		if not _has_script_path(snapshot, OFFER_SNAPSHOT_SCRIPT_PATH):
			errors.append("pending_settlement_event.offer_snapshot ma niepoprawny typ.")
		elif typeof(snapshot.get("choices")) != TYPE_ARRAY:
			errors.append("offer_snapshot.choices nie jest tablicą.")
		else:
			for choice_index in range(snapshot.choices.size()):
				if not _has_script_path(snapshot.choices[choice_index], CHOICE_SNAPSHOT_SCRIPT_PATH):
					errors.append("offer_snapshot.choices[%d] ma niepoprawny typ." % choice_index)


static func _validate_pending_snapshot(errors: Array[String], state, pending, survivor_by_id: Dictionary) -> void:
	var snapshot = pending.get("offer_snapshot")
	if not _has_script_path(snapshot, OFFER_SNAPSHOT_SCRIPT_PATH):
		return
	if str(snapshot.event_id) != str(pending.event_id) or str(snapshot.history_key).is_empty():
		errors.append("Migawka wydarzenia nie odpowiada kontenerowi lub nie ma history_key.")
	for snapshot_error in snapshot.validation_errors():
		errors.append("Migawka wydarzenia: %s" % snapshot_error)
	for field_name in ["history_key", "category", "tone", "severity", "pressure_cost", "cooldown_group", "cooldown_days", "once_per_campaign"]:
		if pending.get(field_name) != snapshot.get(field_name):
			errors.append("Pole %s stanu wydarzenia różni się od zamrożonej oferty." % field_name)
	var touched_resources: Dictionary = {}
	var choice_ids: Dictionary = {}
	var fallback = null
	for choice in snapshot.choices:
		var choice_id := str(choice.id)
		if choice_id.is_empty() or choice_ids.has(choice_id):
			errors.append("Migawka wydarzenia ma pusty albo powtórzony choice_id.")
		choice_ids[choice_id] = true
		if choice_id == str(snapshot.fallback_choice_id):
			fallback = choice
		for resource_id_value in choice.applied_resource_deltas.keys():
			var resource_id := str(resource_id_value)
			if not ResourceIdsScript.all().has(resource_id) or typeof(choice.applied_resource_deltas[resource_id_value]) != TYPE_INT:
				errors.append("Wybór %s ma nieznaną lub niecałkowitą deltę zasobu %s." % [choice_id, resource_id])
			touched_resources[resource_id] = true
		var known_disease_ids: Array[String] = []
		for disease_id_value in _game_database().diseases.keys():
			known_disease_ids.append(str(disease_id_value))
		for survivor in choice.get("survivor_states"):
			if _is_exact(survivor, SurvivorStateScript):
				_validate_disease_case_collection(
					errors,
					survivor.disease_cases,
					known_disease_ids,
					int(state.day),
					int(state.disease_campaign.last_resolved_day),
					"migawki wyboru %s/%s" % [choice_id, survivor.id]
				)
		if bool(choice.available):
			var local_survivors: Dictionary = {}
			for survivor in choice.get("survivor_states"):
				if not _is_exact(survivor, SurvivorStateScript):
					errors.append("Dostępny wybór %s zawiera osobę niepoprawnego typu." % choice_id)
					continue
				var survivor_id := str(survivor.id)
				if survivor_id.is_empty() or local_survivors.has(survivor_id) or survivor_by_id.has(survivor_id):
					errors.append("Dostępny wybór %s zawiera pustą, powtórzoną lub już obecną osobę %s." % [choice_id, survivor_id])
				local_survivors[survivor_id] = true
				_append_snapshot_survivor_core_errors(errors, survivor, "wyboru %s" % choice_id)
			for survivor in choice.get("survivor_states"):
				if not _is_exact(survivor, SurvivorStateScript):
					continue
				for raw_related_id in survivor.relationship_links.keys():
					var related_id := str(raw_related_id).strip_edges()
					var relationship_value = survivor.relationship_links[raw_related_id]
					if related_id.is_empty() or (not survivor_by_id.has(related_id) and not local_survivors.has(related_id)):
						errors.append("Dostępny wybór %s zawiera relację osoby %s do nieznanego ID %s." % [choice_id, survivor.id, related_id])
					if typeof(relationship_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(relationship_value)):
						errors.append("Dostępny wybór %s zawiera relację o niepoprawnej wartości." % choice_id)
			for raw_resource_id in choice.applied_resource_deltas.keys():
				var resource_id := str(raw_resource_id)
				if not snapshot.expected_resource_baseline.has(resource_id) or typeof(snapshot.expected_resource_baseline[resource_id]) != TYPE_INT or typeof(choice.applied_resource_deltas[raw_resource_id]) != TYPE_INT:
					continue
				var after := int(snapshot.expected_resource_baseline[resource_id]) + int(choice.applied_resource_deltas[raw_resource_id])
				if after < 0 or (resource_id in [ResourceIdsScript.HOPE, ResourceIdsScript.PLATFORM_INTEGRITY] and after > 100):
					errors.append("Dostępny wybór %s ma niewykonalny skutek zasobu %s." % [choice_id, resource_id])
	if fallback == null or not bool(fallback.available):
		errors.append("Migawka wydarzenia nie ma dostępnego fallbacku.")
	if snapshot.expected_resource_baseline.size() != touched_resources.size():
		errors.append("Baseline wydarzenia nie obejmuje dokładnie dotykanych zasobów.")
	for resource_id in touched_resources.keys():
		if not snapshot.expected_resource_baseline.has(resource_id) or typeof(snapshot.expected_resource_baseline[resource_id]) != TYPE_INT:
			errors.append("Baseline wydarzenia nie ma poprawnej wartości %s." % resource_id)
		elif int(snapshot.expected_resource_baseline[resource_id]) != int(state.resources.values.get(resource_id, -1)):
			errors.append("Baseline wydarzenia dla %s nie odpowiada aktualnemu magazynowi." % resource_id)


static func _validate_resource_delta_dictionary(errors: Array[String], deltas, context: String) -> void:
	if not (deltas is Dictionary):
		errors.append("Delty %s nie są słownikiem." % context)
		return
	for resource_id_value in deltas.keys():
		var resource_id := str(resource_id_value)
		if not ResourceIdsScript.all().has(resource_id) or typeof(deltas[resource_id_value]) != TYPE_INT:
			errors.append("Delty %s zawierają nieznany lub niecałkowity zasób %s." % [context, resource_id])


static func _append_history_metadata_errors(errors: Array[String], event_state) -> void:
	for field_name in ["history_key", "category", "tone", "cooldown_group"]:
		if not _has_property(event_state, field_name):
			errors.append("Historia wydarzenia nie ma pola %s wymaganego przez bieżący format kampanii." % field_name)
			continue
		if str(event_state.get(field_name)).strip_edges().is_empty():
			errors.append("Historia wydarzenia ma puste pole %s." % field_name)
	if _has_property(event_state, "tone") and str(event_state.tone) not in ["relief", "opportunity", "tradeoff", "hardship"]:
		errors.append("Historia wydarzenia ma nieznany ton %s." % event_state.tone)
	if not _has_property(event_state, "severity") or int(event_state.severity) < 0 or int(event_state.severity) > 3:
		errors.append("Historia wydarzenia ma niepoprawne severity.")
	if not _has_property(event_state, "cooldown_days") or int(event_state.cooldown_days) < 0:
		errors.append("Historia wydarzenia ma niepoprawne cooldown_days.")
	if not _has_property(event_state, "pressure_cost") or not is_finite(float(event_state.pressure_cost)) or float(event_state.pressure_cost) < 0.0 or float(event_state.pressure_cost) > 3.0:
		errors.append("Historia wydarzenia ma niepoprawny pressure_cost.")


static func _event_history_contract_matches(actual, expected) -> bool:
	if actual == null or expected == null:
		return false
	for field_name in ["event_id", "history_key", "category", "tone", "cooldown_group"]:
		if str(actual.get(field_name)) != str(expected.get(field_name)):
			return false
	for field_name in ["severity", "cooldown_days"]:
		if int(actual.get(field_name)) != int(expected.get(field_name)):
			return false
	if bool(actual.once_per_campaign) != bool(expected.once_per_campaign):
		return false
	return is_equal_approx(float(actual.pressure_cost), float(expected.pressure_cost))


static func _validate_persistent_loot_record(
	errors: Array[String],
	record_id: String,
	value,
	landmark_ids: Dictionary,
	is_backpack: bool,
	current_day: int,
	dead_divers: Dictionary
) -> void:
	if record_id.is_empty() or not (value is Dictionary):
		errors.append("Trwały rekord łupu ma pusty identyfikator lub zły typ.")
		return
	var record: Dictionary = value
	var world_position = record.get("world_position", null)
	if not (world_position is Vector2) or not is_finite(world_position.x) or not is_finite(world_position.y):
		errors.append("Trwały rekord %s nie ma world_position." % record_id)
	var landmark_id := str(record.get("landmark_id", ""))
	if landmark_id.is_empty() or not landmark_ids.has(landmark_id):
		errors.append("Trwały rekord %s wskazuje nieznany landmark." % record_id)
	_validate_item_amounts(errors, record.get("items", {}), "trwałego rekordu %s" % record_id)
	if typeof(record.get("recovered", null)) != TYPE_BOOL:
		errors.append("Trwały rekord %s nie ma logicznej flagi recovered." % record_id)
	var recovered := bool(record.get("recovered", false))
	if is_backpack:
		var diver_id := str(record.get("diver_id", "")).strip_edges()
		if diver_id.is_empty() or diver_id != record_id:
			errors.append("Plecak %s nie ma diver_id zgodnego z kluczem rekordu." % record_id)
		elif not dead_divers.has(diver_id):
			errors.append("Plecak %s nie ma odpowiadającego rekordu śmierci nurka." % record_id)
		elif landmark_ids.has(landmark_id) and landmark_ids.has(str(dead_divers[diver_id])) and _canonical_landmark_ref(landmark_ids, landmark_id) != _canonical_landmark_ref(landmark_ids, str(dead_divers[diver_id])):
			errors.append("Plecak %s i rekord śmierci wskazują różne landmarki." % record_id)
		if typeof(record.get("lost_on_day", null)) != TYPE_INT or int(record.get("lost_on_day", 0)) < 1 or int(record.get("lost_on_day", 0)) > current_day:
			errors.append("Plecak %s ma niepoprawny dzień utraty." % record_id)
		var gear_ids = record.get("gear_ids", null)
		if not (gear_ids is Array):
			errors.append("Plecak %s nie ma tablicy gear_ids." % record_id)
			gear_ids = []
		var seen_gear: Dictionary = {}
		for gear_id in gear_ids:
			var gear_definition = _game_database().diving_gear.get(str(gear_id))
			if gear_definition == null:
				errors.append("Plecak %s zawiera nieznane wyposażenie %s." % [record_id, gear_id])
			elif bool(gear_definition.is_emergency_default) or str(gear_definition.equipment_slot).is_empty():
				errors.append("Plecak %s zawiera niewłaściwą awaryjną lub bezslotową kopię wyposażenia %s." % [record_id, gear_id])
			if seen_gear.has(str(gear_id)):
				errors.append("Plecak %s powtarza wyposażenie %s." % [record_id, gear_id])
			seen_gear[str(gear_id)] = true
		var items = record.get("items", {})
		var backpack_empty: bool = items is Dictionary and items.is_empty() and gear_ids.is_empty()
		if recovered != backpack_empty:
			errors.append("Plecak %s ma flagę recovered niespójną z zawartością." % record_id)
	else:
		if str(record.get("persistence_id", "")) != record_id:
			errors.append("Pakunek %s ma niespójne persistence_id." % record_id)
		if typeof(record.get("created_day", null)) != TYPE_INT or int(record.get("created_day", 0)) < 1 or int(record.get("created_day", 0)) > current_day:
			errors.append("Pakunek %s ma niepoprawny dzień utworzenia." % record_id)
		var pile_items = record.get("items", {})
		if recovered or not (pile_items is Dictionary) or pile_items.is_empty():
			errors.append("Aktywny pakunek %s musi zawierać łup i nie może być oznaczony jako odzyskany." % record_id)


static func _canonical_landmark_ref(landmark_ids: Dictionary, landmark_id: String) -> String:
	var resolved = landmark_ids.get(landmark_id, landmark_id)
	return str(resolved) if resolved is String else landmark_id


static func _validate_item_amounts(errors: Array[String], value, context: String) -> void:
	if not (value is Dictionary):
		errors.append("Lista przedmiotów %s nie jest słownikiem." % context)
		return
	for item_id_value in value.keys():
		var item_id := str(item_id_value)
		if not _game_database().items.has(item_id):
			errors.append("%s zawiera nieznany przedmiot %s." % [context.capitalize(), item_id])
		if typeof(value[item_id_value]) != TYPE_INT or int(value[item_id_value]) <= 0:
			errors.append("%s zawiera niepoprawną ilość przedmiotu %s." % [context.capitalize(), item_id])


static func _record_ids(errors: Array[String], records: Array, label: String) -> Dictionary:
	var ids: Dictionary = {}
	for value in records:
		if not (value is Dictionary):
			errors.append("Blueprint zawiera rekord %s o złym typie." % label)
			continue
		var id := str(value.get("id", ""))
		if id.is_empty() or ids.has(id):
			errors.append("Blueprint zawiera pusty lub powtórzony identyfikator %s." % label)
			continue
		ids[id] = true
	return ids


static func _validate_current_scene_snapshot(errors: Array[String], state, blueprint) -> void:
	var expected_world = UnderwaterWorldStateScript.new()
	var compilation_errors: PackedStringArray = MapSceneCompilerScript.new().generate(
		expected_world,
		int(state.seed)
	)
	for compilation_error in compilation_errors:
		errors.append("Nie udało się skompilować bieżącej sceny mapy: %s" % compilation_error)
	var expected = expected_world.blueprint
	if expected == null or not compilation_errors.is_empty():
		if expected == null and compilation_errors.is_empty():
			errors.append("Nie udało się utworzyć migawki bieżącej sceny mapy do walidacji.")
		return
	# WorldBlueprint saved in the campaign is a validated runtime cache. The
	# gameplay signature covers every gameplay-bearing record and the navigation
	# mask, while intentionally omitting presentation-only prefab metadata.
	# Comparing complete arrays here would incorrectly reject a campaign after a
	# harmless art, label or visual-offset edit.
	for field_name in [
		"campaign_seed",
		"map_source_version",
		"map_id",
		"map_gameplay_signature",
		"world_size",
		"entry_landmark_id",
		"entry_position",
		"exit_position",
		"chunk_size",
	]:
		if not _canonical_value_matches(blueprint.get(field_name), expected.get(field_name)):
			errors.append("Migawka kampanii różni się od bieżącej sceny mapy w polu %s." % field_name)


static func _canonical_value_matches(actual, expected) -> bool:
	var actual_type := typeof(actual)
	var expected_type := typeof(expected)
	if actual_type in [TYPE_INT, TYPE_FLOAT] and expected_type in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(actual), float(expected))
	if actual_type != expected_type:
		return false
	match actual_type:
		TYPE_VECTOR2:
			return actual.is_equal_approx(expected)
		TYPE_VECTOR3:
			return actual.is_equal_approx(expected)
		TYPE_RECT2:
			return actual.position.is_equal_approx(expected.position) and actual.size.is_equal_approx(expected.size)
		TYPE_COLOR:
			return (
				is_equal_approx(actual.r, expected.r)
				and is_equal_approx(actual.g, expected.g)
				and is_equal_approx(actual.b, expected.b)
				and is_equal_approx(actual.a, expected.a)
			)
		TYPE_ARRAY:
			if actual.size() != expected.size():
				return false
			for index in range(actual.size()):
				if not _canonical_value_matches(actual[index], expected[index]):
					return false
			return true
		TYPE_DICTIONARY:
			if actual.size() != expected.size():
				return false
			for key in expected.keys():
				if not actual.has(key) or not _canonical_value_matches(actual[key], expected[key]):
					return false
			return true
		TYPE_PACKED_VECTOR2_ARRAY:
			if actual.size() != expected.size():
				return false
			for index in range(actual.size()):
				if not actual[index].is_equal_approx(expected[index]):
					return false
			return true
		_:
			return actual == expected


static func _dictionary_key_set(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_key in value.keys():
		result[str(raw_key)] = true
	return result


static func _validate_unique_subset(errors: Array[String], values: Array, allowed: Dictionary, label: String) -> void:
	var seen: Dictionary = {}
	for value in values:
		var id := str(value)
		if id.is_empty() or seen.has(id):
			errors.append("Lista %s zawiera pusty lub powtórzony wpis." % label)
		elif not allowed.has(id):
			errors.append("Lista %s wskazuje nieznane ID %s." % [label, id])
		seen[id] = true


static func _check_unique_known_strings(errors: Array[String], values: Array, allowed: Array[String], label: String) -> void:
	var seen: Dictionary = {}
	for value in values:
		var id := str(value)
		if id.is_empty() or seen.has(id) or not allowed.has(id):
			errors.append("Lista %s zawiera pusty, powtórzony lub nieznany wpis %s." % [label, id])
		seen[id] = true


static func _validate_unique_nonempty_strings(errors: Array[String], values: Array, label: String) -> void:
	var seen: Dictionary = {}
	for raw_value in values:
		var value := str(raw_value).strip_edges()
		if value.is_empty() or seen.has(value):
			errors.append("Lista %s zawiera pusty lub powtórzony wpis %s." % [label, value])
		seen[value] = true


static func _same_string_set(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	var seen: Dictionary = {}
	for value in left:
		seen[str(value)] = true
	if seen.size() != left.size():
		return false
	for value in right:
		if not seen.has(str(value)):
			return false
	return true


static func _append_snapshot_survivor_core_errors(errors: Array[String], survivor, context: String) -> void:
	var survivor_id := str(survivor.id).strip_edges()
	if survivor_id.is_empty() or str(survivor.display_name).strip_edges().is_empty():
		errors.append("Migawka mieszkańca %s nie ma pełnej tożsamości." % context)
	if int(survivor.level) < 1 or int(survivor.level) > SurvivorStateScript.MAX_LEVEL or int(survivor.experience) < 0 or int(survivor.unspent_skill_points) < 0:
		errors.append("Migawka mieszkańca %s ma niepoprawny rozwój." % context)
	if int(survivor.base_max_health) < 1 or int(survivor.health_bonus) < 0 or int(survivor.health) <= 0 or int(survivor.health) > int(survivor.get_max_health()):
		errors.append("Migawka mieszkańca %s ma niepoprawne zdrowie." % context)
	if not is_finite(float(survivor.base_oxygen_capacity)) or float(survivor.base_oxygen_capacity) < 1.0 or not is_finite(float(survivor.oxygen_capacity_bonus)) or float(survivor.oxygen_capacity_bonus) < 0.0:
		errors.append("Migawka mieszkańca %s ma niepoprawną pojemność tlenu." % context)
	if not is_finite(float(survivor.base_carry_capacity)) or float(survivor.base_carry_capacity) < 1.0 or not is_finite(float(survivor.carry_capacity_bonus)) or float(survivor.carry_capacity_bonus) < 0.0:
		errors.append("Migawka mieszkańca %s ma niepoprawny udźwig." % context)
	if int(survivor.status) in [SurvivorStateScript.Status.DEAD, SurvivorStateScript.Status.DEPARTED] or not str(survivor.current_assignment).is_empty():
		errors.append("Migawka mieszkańca %s nie opisuje nowej, obecnej i nieprzydzielonej osoby." % context)
	for field_name in ["hunger", "fatigue", "morale"]:
		if int(survivor.get(field_name)) < 0 or int(survivor.get(field_name)) > 100:
			errors.append("Migawka mieszkańca %s ma %s poza zakresem." % [context, field_name])
	_validate_competencies(errors, survivor.competency_levels, "migawki mieszkańca %s" % context)
	_validate_profession_talent_map(
		errors,
		survivor.profession_talent_ids,
		[str(survivor.profession), str(survivor.secondary_profession)],
		"migawki mieszkańca %s" % context,
		ProfessionTalentSystemScript.new(),
		survivor
	)
	_validate_unique_nonempty_strings(errors, survivor.injury_states, "urazów migawki %s" % context)


static func _is_exact(value, script: Script) -> bool:
	return value != null and value is Object and value.get_script() == script


static func _validate_competencies(errors: Array[String], levels: Dictionary, context: String) -> void:
	for raw_id in levels.keys():
		var competency_id := str(raw_id)
		var competency_level := int(levels[raw_id])
		if not CompetencySystemScript.is_valid_id(competency_id):
			errors.append("Nieznana kompetencja %s w danych %s." % [competency_id, context])
		elif competency_level < 1 or competency_level > CompetencySystemScript.MAX_LEVEL:
			errors.append("Kompetencja %s w danych %s ma poziom poza zakresem 1..3." % [competency_id, context])


static func _validate_profession_talent_map(
	errors: Array[String],
	selections,
	formal_profession_values: Array,
	context: String,
	profession_talent_system,
	survivor = null
) -> void:
	if not (selections is Dictionary):
		errors.append("Mapa talentów zawodowych %s nie jest słownikiem." % context)
		return
	if selections.size() > 2:
		errors.append("Mapa talentów zawodowych %s przekracza limit dwóch formalnych profesji." % context)

	var formal_professions: Dictionary = {}
	for profession_id_value in formal_profession_values:
		var profession_id := str(profession_id_value).strip_edges()
		if not profession_id.is_empty():
			formal_professions[profession_id] = true
	var career = CareerProgressionSystemScript.new() if survivor != null else null
	for raw_profession_id in selections.keys():
		if typeof(raw_profession_id) != TYPE_STRING:
			errors.append("Mapa talentów zawodowych %s ma nietekstowy klucz profesji." % context)
			continue
		var profession_id := str(raw_profession_id).strip_edges()
		var raw_talent_id = selections[raw_profession_id]
		if profession_id.is_empty() or typeof(raw_talent_id) != TYPE_STRING or str(raw_talent_id).strip_edges().is_empty():
			errors.append("Mapa talentów zawodowych %s ma pustą profesję albo talent." % context)
			continue
		var talent_id := str(raw_talent_id).strip_edges()
		if not formal_professions.has(profession_id):
			errors.append("Talent %s w danych %s należy do nieformalnej profesji %s." % [talent_id, context, profession_id])
		var talent_definition = profession_talent_system.get_definition(talent_id)
		if talent_definition == null:
			errors.append("Nieznany talent zawodowy %s w danych %s." % [talent_id, context])
			continue
		if str(talent_definition.profession_id) != profession_id:
			errors.append("Talent %s w danych %s nie należy do profesji %s." % [talent_id, context, profession_id])
		if survivor == null:
			continue
		var profession_definition = career.get_profession_definition(profession_id)
		if profession_definition == null:
			errors.append("Talent %s w danych %s wskazuje nieznaną ścieżkę zawodową." % [talent_id, context])
			continue
		var required_practice := int(profession_definition.promotion_experience)
		if int(survivor.get_job_experience(profession_id)) < required_practice:
			errors.append("Talent %s w danych %s wybrano przed progiem praktyki %d." % [talent_id, context, required_practice])


static func _has_script_path(value, script_path: String) -> bool:
	return value != null and value is Object and value.get_script() != null and str(value.get_script().resource_path) == script_path


static func _require_exact(errors: Array[String], value, script: Script, field_name: String) -> void:
	if not _is_exact(value, script):
		errors.append("Pole %s ma niepoprawny lub pusty typ." % field_name)


static func _check_optional_exact(errors: Array[String], value, script: Script, field_name: String) -> void:
	if value != null and not _is_exact(value, script):
		errors.append("Pole %s ma niepoprawny typ." % field_name)


static func _check_exact_array(errors: Array[String], values, script: Script, field_name: String) -> void:
	if typeof(values) != TYPE_ARRAY:
		errors.append("Pole %s nie jest tablicą." % field_name)
		return
	for index in range(values.size()):
		if not _is_exact(values[index], script):
			errors.append("Pole %s[%d] ma niepoprawny typ." % [field_name, index])


static func _check_string_array(errors: Array[String], values, field_name: String) -> void:
	if typeof(values) != TYPE_ARRAY:
		errors.append("Pole %s nie jest tablicą." % field_name)
		return
	for index in range(values.size()):
		if typeof(values[index]) != TYPE_STRING and typeof(values[index]) != TYPE_STRING_NAME:
			errors.append("Pole %s[%d] nie jest identyfikatorem tekstowym." % [field_name, index])


static func _check_string_only_array(errors: Array[String], values, field_name: String) -> void:
	if typeof(values) != TYPE_ARRAY:
		errors.append("Pole %s nie jest tablicą." % field_name)
		return
	for index in range(values.size()):
		if typeof(values[index]) != TYPE_STRING:
			errors.append("Pole %s[%d] nie jest Stringiem." % [field_name, index])


static func _check_dictionary_array(errors: Array[String], values, field_name: String) -> void:
	if typeof(values) != TYPE_ARRAY:
		errors.append("Pole %s nie jest tablicą." % field_name)
		return
	for index in range(values.size()):
		if not (values[index] is Dictionary):
			errors.append("Pole %s[%d] nie jest słownikiem." % [field_name, index])


static func _check_dictionary_property(errors: Array[String], value: Object, property_name: String, field_name: String) -> void:
	if not _has_property(value, property_name):
		errors.append("Pole %s nie istnieje." % field_name)
	elif not (value.get(property_name) is Dictionary):
		errors.append("Pole %s nie jest słownikiem." % field_name)


static func _has_property(value: Object, property_name: String) -> bool:
	for property in value.get_property_list():
		if str(property.name) == property_name:
			return true
	return false


static func _in_float_range(value: float, minimum: float, maximum: float) -> bool:
	return is_finite(value) and value >= minimum and value <= maximum
