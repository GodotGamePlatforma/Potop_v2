extends SceneTree

const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const MissionProgressStateScript := preload("res://scripts/data/MissionProgressState.gd")
const MissionSystemScript := preload("res://scripts/base/MissionSystem.gd")
const CampaignProgressionSystemScript := preload("res://scripts/base/CampaignProgressionSystem.gd")

const FOUNDATION_HARBOR := "foundation_harbor"
const OLD_SIGNAL := "old_signal"
const LEADERSHIP_CRISIS := "leadership_crisis"
const RESCUE_LEON := "rescue_leon"
const LIGHT_IN_DEPTHS := "light_in_depths"
const MORE_AIR := "more_air"
const RETURN_NETWORK := "return_network"
const HEAVY_RECOVERY := "heavy_recovery"

const FOUNDATION_BUILDINGS: Array[String] = [
	"fishing_hut",
	"kitchen",
	"community_house",
	"workshop",
	"infirmary",
]

var _failed := false


func _initialize() -> void:
	_verify_runtime_catalog_matches_data_directory()
	_verify_tutorial_gate_and_parallel_start()
	_verify_foundation_progress_uses_finished_buildings()
	_verify_old_signal_does_not_wait_for_foundation()
	_verify_crisis_tracking_override_and_restore()
	_verify_crisis_completion_during_override_and_repeatability()
	_verify_story_completion_and_crisis_start_in_one_reconcile()
	_verify_leon_death_fails_the_rescue()
	_verify_side_missions_follow_existing_mechanics()
	_verify_expedition_guidance_uses_parallel_story_mission()
	_verify_compatibility_and_deduplication()

	if _failed:
		quit(1)
		return
	print("Mission system test passed: tutorial gating, parallel missions, derived progress, side objectives, crisis override, rescue failure, expedition guidance and compatibility work.")
	quit(0)


func _verify_runtime_catalog_matches_data_directory() -> void:
	var definitions: Dictionary = MissionSystemScript.new().definitions()
	var resource_ids: Array[String] = []
	var file_names := DirAccess.get_files_at("res://data/missions")
	file_names.sort()
	for file_name in file_names:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var definition = ResourceLoader.load("res://data/missions".path_join(file_name))
		if definition != null and not str(definition.id).is_empty():
			resource_ids.append(str(definition.id))
	_assert(definitions.size() == resource_ids.size(), "MissionSystem should load every mission resource from the canonical data directory exactly once.")
	for mission_id in resource_ids:
		_assert(definitions.has(mission_id), "MissionSystem should expose the validated mission resource %s." % mission_id)


func _verify_tutorial_gate_and_parallel_start() -> void:
	var state = _new_state(9101)
	var system = MissionSystemScript.new()
	system.reconcile(state)
	_assert(not _is_visible(_view(system, state, FOUNDATION_HARBOR)), "The journal must not expose Foundation Harbor before the tutorial is complete.")
	_assert(not _is_visible(_view(system, state, OLD_SIGNAL)), "The journal must not expose Old Signal before the tutorial is complete.")

	state.tutorial.complete()
	system.reconcile(state)
	_assert(_has_status(_view(system, state, FOUNDATION_HARBOR), ["active", "in_progress"]), "Completing the tutorial should activate Foundation Harbor.")
	_assert(_has_status(_view(system, state, OLD_SIGNAL), ["active", "in_progress"]), "Completing the tutorial should activate Old Signal in parallel with Foundation Harbor.")
	_assert(_tracked_mission_id(state) == FOUNDATION_HARBOR, "Foundation Harbor should be tracked by default when the journal opens.")


func _verify_foundation_progress_uses_finished_buildings() -> void:
	var state = _new_state(9102)
	var system = MissionSystemScript.new()
	state.tutorial.complete()
	system.reconcile(state)
	_assert_progress(_view(system, state, FOUNDATION_HARBOR), 0, 5, "A fresh post-tutorial harbor should show 0/5 remaining foundation buildings.")

	var queued = _building("queued_fishing", "fishing_hut", "top_left", false)
	state.buildings.append(queued)
	system.reconcile(state)
	_assert_progress(_view(system, state, FOUNDATION_HARBOR), 0, 5, "A queued but unfinished building must not count toward Foundation Harbor.")

	queued.is_built = true
	for definition_id in FOUNDATION_BUILDINGS:
		if definition_id == "fishing_hut":
			continue
		state.buildings.append(_building("foundation_%s" % definition_id, definition_id, _slot_for_building(definition_id), true))
	system.reconcile(state)
	var completed_view := _view(system, state, FOUNDATION_HARBOR)
	_assert_progress(completed_view, 5, 5, "Five finished non-station buildings should produce Foundation Harbor progress 5/5.")
	_assert(_has_status(completed_view, ["completed", "complete"]), "Foundation Harbor should complete when all five remaining buildings are finished.")


func _verify_old_signal_does_not_wait_for_foundation() -> void:
	var state = _new_state(9103)
	var system = MissionSystemScript.new()
	state.tutorial.complete()
	system.reconcile(state)
	system.track_mission(state, OLD_SIGNAL)

	_activate_archive_terminal(state)
	system.reconcile(state)
	_assert(_has_status(_view(system, state, OLD_SIGNAL), ["completed", "complete"]), "Activating the Archive terminal should complete the Common Line Map mission.")
	_assert(_tracked_mission_id(state) == FOUNDATION_HARBOR, "Completing the Common Line Map mission should return tracking to the active foundation objective.")
	_assert_progress(_view(system, state, FOUNDATION_HARBOR), 0, 5, "The independent foundation mission should remain unfinished at 0/5.")


func _verify_crisis_tracking_override_and_restore() -> void:
	var state = _new_state(9105)
	var system = MissionSystemScript.new()
	state.tutorial.complete()
	system.reconcile(state)
	system.track_mission(state, OLD_SIGNAL)
	_assert(_tracked_mission_id(state) == OLD_SIGNAL, "The player should be able to track Old Signal before a crisis.")

	state.story_flags.crisis_active = true
	state.story_flags.crisis_days_remaining = 3
	system.reconcile(state)
	_assert(_tracked_mission_id(state) == LEADERSHIP_CRISIS, "An active leadership crisis must override the player's tracked mission.")
	_assert(_has_status(_view(system, state, LEADERSHIP_CRISIS), ["active", "in_progress"]), "The crisis override should expose an active crisis mission.")

	state.story_flags.crisis_active = false
	state.story_flags.crisis_days_remaining = 0
	state.story_flags.set_flag("leadership_crisis_survived", true)
	system.reconcile(state)
	_assert(_has_status(_view(system, state, LEADERSHIP_CRISIS), ["completed", "complete"]), "The survived crisis flag should complete the crisis mission.")
	_assert(_tracked_mission_id(state) == OLD_SIGNAL, "Resolving the crisis should restore the previously tracked mission.")


func _verify_crisis_completion_during_override_and_repeatability() -> void:
	var state = _new_state(9111)
	var system = MissionSystemScript.new()
	state.tutorial.complete()
	system.reconcile(state)
	system.track_mission(state, OLD_SIGNAL)

	state.story_flags.crisis_active = true
	state.story_flags.crisis_days_remaining = 3
	system.reconcile(state)
	_activate_archive_terminal(state)
	system.reconcile(state)
	_assert(_has_status(_view(system, state, OLD_SIGNAL), ["completed", "complete"]), "A story mission may complete while the urgent crisis owns the tracker.")
	_assert(_tracked_mission_id(state) == LEADERSHIP_CRISIS, "The active crisis must keep priority even when the suspended story mission completes.")

	state.story_flags.crisis_active = false
	state.story_flags.crisis_days_remaining = 0
	state.story_flags.set_flag("leadership_crisis_survived", true)
	system.reconcile(state)
	_assert(_tracked_mission_id(state) == FOUNDATION_HARBOR, "After the crisis, tracking should return to the active foundation objective when the unused story successor is disabled.")

	state.story_flags.crisis_active = true
	state.story_flags.crisis_days_remaining = 3
	state.story_flags.crisis_started_day += 1
	system.reconcile(state)
	var repeated_crisis := _view(system, state, LEADERSHIP_CRISIS)
	_assert(_has_status(repeated_crisis, ["active", "in_progress"]), "A later leadership crisis should reactivate the repeatable urgent mission.")
	_assert_progress(repeated_crisis, 0, 1, "A previous crisis success must not auto-complete a newly active crisis.")
	_assert(_tracked_mission_id(state) == LEADERSHIP_CRISIS, "Every active leadership crisis must override the current tracker.")

	state.story_flags.crisis_active = false
	state.story_flags.crisis_days_remaining = 0
	system.reconcile(state)
	_assert(_has_status(_view(system, state, LEADERSHIP_CRISIS), ["completed", "complete"]), "The repeatable crisis mission should complete again after recovery.")
	_assert(_tracked_mission_id(state) == FOUNDATION_HARBOR, "Resolving a repeated crisis should restore the real active objective rather than a disabled successor.")


func _verify_story_completion_and_crisis_start_in_one_reconcile() -> void:
	var state = _new_state(9112)
	var system = MissionSystemScript.new()
	state.tutorial.complete()
	system.reconcile(state)
	system.track_mission(state, OLD_SIGNAL)

	_activate_archive_terminal(state)
	state.story_flags.crisis_active = true
	state.story_flags.crisis_days_remaining = 3
	system.reconcile(state)
	_assert(_tracked_mission_id(state) == LEADERSHIP_CRISIS, "A crisis starting in the same reconciliation as story completion must still take urgent priority.")

	state.story_flags.crisis_active = false
	state.story_flags.crisis_days_remaining = 0
	state.story_flags.set_flag("leadership_crisis_survived", true)
	system.reconcile(state)
	_assert(_tracked_mission_id(state) == FOUNDATION_HARBOR, "A simultaneous story completion and crisis start must preserve the real active objective when the unused successor is disabled.")


func _verify_leon_death_fails_the_rescue() -> void:
	var state = _new_state(9106)
	var system = MissionSystemScript.new()
	state.tutorial.complete()
	state.underwater_world.rescued_or_dead_survivors["rescue_hotel_leon"] = {
		"status": "dead",
		"survivor_id": "leon",
		"stabilized": false,
	}
	system.reconcile(state)
	_assert(_has_status(_view(system, state, RESCUE_LEON), ["failed"]), "Leon's persistent dead outcome must fail his rescue mission.")


func _verify_side_missions_follow_existing_mechanics() -> void:
	var state = _new_state(9109)
	var system = MissionSystemScript.new()
	state.tutorial.complete()
	var station = _building("support_station", "diving_station", "bottom_center", true)
	station.level = 4
	var workshop = _building("support_workshop", "workshop", "bottom_left", true)
	workshop.level = 3
	state.buildings.append_array([station, workshop])
	system.reconcile(state)
	_assert(_has_status(_view(system, state, LIGHT_IN_DEPTHS), ["active", "in_progress"]), "A built Workshop should reveal the lantern development mission.")
	_assert(_has_status(_view(system, state, MORE_AIR), ["active", "in_progress"]), "Workshop II+ should reveal the oxygen-tank development mission.")
	_assert(_has_status(_view(system, state, RETURN_NETWORK), ["active", "in_progress"]), "Diving Station III+ should reveal the navigation-network mission.")
	_assert(_has_status(_view(system, state, HEAVY_RECOVERY), ["active", "in_progress"]), "Station IV plus Workshop III should reveal heavy recovery.")

	state.diving_equipment.add_gear("diving_lantern_mk2")
	state.diving_equipment.add_gear("oxygen_tank_mk2")
	state.underwater_world.placed_buoys.append("mission_test_buoy")
	state.underwater_world.opened_shortcuts.append("mission_test_shortcut")
	state.underwater_world.recovered_heavy_objects.append("mission_test_heavy_object")
	system.reconcile(state)
	for mission_id in [LIGHT_IN_DEPTHS, MORE_AIR, RETURN_NETWORK, HEAVY_RECOVERY]:
		_assert(_has_status(_view(system, state, mission_id), ["completed", "complete"]), "Side mission %s should complete from the corresponding persistent campaign state." % mission_id)


func _verify_expedition_guidance_uses_parallel_story_mission() -> void:
	var state = _new_state(9107)
	var system = MissionSystemScript.new()
	state.tutorial.complete()
	system.reconcile(state)
	_assert(_tracked_mission_id(state) == FOUNDATION_HARBOR, "The setup for expedition guidance requires Foundation Harbor to remain tracked.")

	var guidance = system.expedition_guidance(state)
	_assert(guidance is Dictionary, "Expedition guidance should return a structured Dictionary.")
	if not (guidance is Dictionary):
		return
	_assert(_guidance_mission_id(guidance) == OLD_SIGNAL, "A base-only tracked mission should let the parallel Old Signal mission guide the expedition.")
	_assert(_guidance_landmark_id(guidance) == "R1-09", "Old Signal expedition guidance should point to the authored R1-09 landmark.")


func _verify_compatibility_and_deduplication() -> void:
	var state = _new_state(9108)
	var system = MissionSystemScript.new()
	state.tutorial.complete()
	_assert(state.mission_progress != null, "A new campaign should own MissionProgressState in GameState.")
	_assert(state.mission_progress is MissionProgressStateScript, "GameState.mission_progress should use MissionProgressState.")

	var injected_duplicates := _inject_duplicate_ids_if_supported(state.mission_progress)
	state.mission_progress.ensure_compatibility()
	system.reconcile(state)
	system.reconcile(state)
	_assert(state.mission_progress != null, "MissionProgressState.ensure_compatibility() must preserve mission progress.")
	_assert(_tracked_mission_id(state) == FOUNDATION_HARBOR, "Repeated reconciliation should be idempotent and keep the valid tracked mission.")
	if injected_duplicates:
		_assert(not _mission_state_has_duplicate_ids(state.mission_progress), "MissionProgressState compatibility should deduplicate stored mission identifiers.")


func _new_state(seed: int):
	var state = GameStateScript.new()
	state.setup_new_campaign(seed, DifficultyProfileScript.new())
	return state


func _building(id: String, definition_id: String, slot_id: String, built: bool):
	var building = BuildingStateScript.new()
	building.id = id
	building.definition_id = definition_id
	building.slot_id = slot_id
	building.level = 1
	building.is_built = built
	building.construction_progress = 100 if built else 0
	return building


func _slot_for_building(definition_id: String) -> String:
	match definition_id:
		"fishing_hut":
			return "top_left"
		"kitchen":
			return "top_center"
		"community_house":
			return "top_right"
		"workshop":
			return "bottom_left"
		"infirmary":
			return "center"
	return ""


func _view(system, state, mission_id: String) -> Dictionary:
	var result = system.mission_view(state, mission_id)
	_assert(result is Dictionary, "mission_view(%s) should return a Dictionary." % mission_id)
	return result if result is Dictionary else {}


func _is_visible(view: Dictionary) -> bool:
	return bool(view.get("visible", not view.is_empty()))


func _has_status(view: Dictionary, expected_statuses: Array) -> bool:
	if not _is_visible(view):
		return false
	var status := str(view.get("status", "")).to_lower()
	return expected_statuses.has(status)


func _assert_progress(view: Dictionary, expected_current: int, expected_required: int, message: String) -> void:
	var progress := _progress_values(view)
	_assert(int(progress.get("current", -1)) == expected_current and int(progress.get("required", -1)) == expected_required, "%s Received %s." % [message, progress])


func _progress_values(view: Dictionary) -> Dictionary:
	var current = _first_value(view, ["current", "progress_current", "completed_count", "count"])
	var required = _first_value(view, ["required", "progress_required", "target", "total"])
	var nested = view.get("progress", null)
	if nested is Dictionary:
		if current == null:
			current = _first_value(nested, ["current", "completed", "count", "value"])
		if required == null:
			required = _first_value(nested, ["required", "target", "total", "max"])
	elif nested is int or nested is float:
		if current == null:
			current = nested
	return {
		"current": int(current) if current != null else -1,
		"required": int(required) if required != null else -1,
	}


func _first_value(source: Dictionary, keys: Array):
	for key in keys:
		if source.has(key):
			return source[key]
	return null


func _tracked_mission_id(state) -> String:
	if state == null or state.mission_progress == null:
		return ""
	for property_name in ["tracked_mission_id", "tracked_id", "current_tracked_mission_id"]:
		if property_name in state.mission_progress:
			return str(state.mission_progress.get(property_name))
	for mission_id in [FOUNDATION_HARBOR, OLD_SIGNAL, LEADERSHIP_CRISIS, RESCUE_LEON]:
		var view = MissionSystemScript.new().mission_view(state, mission_id)
		if view is Dictionary and bool(view.get("tracked", false)):
			return mission_id
	return ""


func _view_mentions(view: Dictionary, id: String, display_fragment: String) -> bool:
	var serialized := str(view).to_lower()
	return serialized.contains(id.to_lower()) or serialized.contains(display_fragment.to_lower())


func _guidance_mission_id(guidance: Dictionary) -> String:
	for key in ["mission_id", "source_mission_id", "guiding_mission_id"]:
		if guidance.has(key):
			return str(guidance[key])
	return ""


func _guidance_landmark_id(guidance: Dictionary) -> String:
	for key in ["landmark_id", "target_landmark_id", "entry_point", "target_sector"]:
		if guidance.has(key):
			return str(guidance[key])
	return ""


func _inject_duplicate_ids_if_supported(progress) -> bool:
	for property_name in ["journal_mission_ids", "mission_ids", "active_mission_ids"]:
		if property_name in progress:
			var duplicates: Array[String] = [OLD_SIGNAL, OLD_SIGNAL, FOUNDATION_HARBOR]
			progress.set(property_name, duplicates)
			return true
	return false


func _mission_state_has_duplicate_ids(progress) -> bool:
	for property_name in ["journal_mission_ids", "mission_ids", "active_mission_ids", "completed_mission_ids", "failed_mission_ids"]:
		if not (property_name in progress):
			continue
		var values = progress.get(property_name)
		if not (values is Array):
			continue
		var unique: Array[String] = []
		for value in values:
			var id := str(value)
			if unique.has(id):
				return true
			unique.append(id)
	return false


func _activate_archive_terminal(state) -> void:
	state.story_flags.junction_j7_active = true
	state.story_flags.junction_j7_activated_day = maxi(1, state.day - 1)
	state.story_flags.archive_terminal_active = true
	state.story_flags.archive_map_transmitted = true
	state.story_flags.archive_terminal_activated_day = state.day
	for device_id in [CampaignProgressionSystemScript.JUNCTION_J7_DEVICE_ID, CampaignProgressionSystemScript.ARCHIVE_TERMINAL_DEVICE_ID]:
		if not state.underwater_world.delta.activated_fixed_devices.has(device_id):
			state.underwater_world.delta.activated_fixed_devices.append(device_id)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Mission system test failed: " + message)
