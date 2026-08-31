extends SceneTree

const CampaignProgressionSystemScript := preload("res://scripts/campaign/CampaignProgressionSystem.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const ExpeditionPreparationSystemScript := preload("res://scripts/diving/ExpeditionPreparationSystem.gd")
const GameDatabaseScript := preload("res://scripts/core/GameDatabase.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const MissionSystemScript := preload("res://scripts/campaign/MissionSystem.gd")

var _failed := false

func _initialize() -> void:
	var database = GameDatabaseScript.new()
	database.load_definitions()
	_assert(database.is_valid(), "Baza danych Wspólnej Linii musi być poprawna.")
	var state = GameStateScript.new()
	state.setup_new_campaign(8507, database.get_standard_difficulty())
	_remove_fixed_device_records(state.underwater_world.blueprint, CampaignProgressionSystemScript.ARCHIVE_TERMINAL_DEVICE_ID)
	var campaign = CampaignProgressionSystemScript.new()
	_apply_device(campaign, state, CampaignProgressionSystemScript.JUNCTION_J7_DEVICE_ID)
	state.underwater_world.delta.activated_fixed_devices.append(CampaignProgressionSystemScript.JUNCTION_J7_DEVICE_ID)
	_assert(state.story_flags.junction_j7_active and state.story_flags.junction_j7_activated_day == state.day, "J-7 musi utrwalić aktywny tutorialowy punkt sieci.")
	_assert(state.story_flags.black_front_active and state.story_flags.black_front_days_remaining > 0, "J-7 musi uruchamiać aktywne odliczanie Czarnego Frontu także przed rozmieszczeniem kolejnych urządzeń w manifeście.")
	_assert(campaign.objective_text(state).contains("Archiwum"), "Cel po J-7 musi prowadzić semantycznie do Archiwum przed rozmieszczeniem fizycznego landmarku.")
	var preparation = ExpeditionPreparationSystemScript.new()
	var semantic_archive_guidance: Dictionary = preparation._common_line_expedition_guidance(state)
	_assert(str(semantic_archive_guidance.get("objective_id", "")) == "common_line_archive" and str(semantic_archive_guidance.get("landmark_id", "")).is_empty(), "Przygotowanie wyprawy musi publikować aktywny cel Archiwum bez wymyślania nieumieszczonego landmarku.")
	_assert(str(semantic_archive_guidance.get("landmark_label", "")) == "Zalane Archiwum", "Nieumieszczony cel kampanii musi zachować semantyczną nazwę Archiwum.")
	var entry_id := str(state.underwater_world.blueprint.entry_landmark_id)
	state.underwater_world.blueprint.fixed_device_spawns.append({
		"id": CampaignProgressionSystemScript.ARCHIVE_TERMINAL_DEVICE_ID,
		"display_name": "Archiwum fixture",
		"landmark_id": entry_id,
	})
	var placed_archive_guidance: Dictionary = preparation._common_line_expedition_guidance(state)
	_assert(str(placed_archive_guidance.get("landmark_id", "")) == entry_id and str(placed_archive_guidance.get("landmark_label", "")) == "Archiwum fixture", "Po rozmieszczeniu semantycznego rekordu cel kampanii musi pobrać pozycję i etykietę z bieżącego blueprintu.")
	_remove_fixed_device_records(state.underwater_world.blueprint, CampaignProgressionSystemScript.ARCHIVE_TERMINAL_DEVICE_ID)

	_apply_device(campaign, state, CampaignProgressionSystemScript.ARCHIVE_TERMINAL_DEVICE_ID)
	_assert(state.story_flags.archive_terminal_active and state.story_flags.archive_map_transmitted, "Terminal Archiwum musi utrwalić transmisję także bez rekordu położenia w bieżącym blueprintcie.")
	_assert(campaign.objective_text(state).contains("R-3"), "Po Archiwum kampania musi wskazać semantyczny cel R-3 przed rozmieszczeniem fizycznego landmarku.")
	_apply_device(campaign, state, CampaignProgressionSystemScript.R3_DIAGNOSTIC_DEVICE_ID)
	state.story_flags.r3_regulator_ready = true
	state.story_flags.r3_regulator_completed_day = state.day
	_apply_device(campaign, state, CampaignProgressionSystemScript.R3_GENERATOR_DEVICE_ID)
	_apply_device(campaign, state, CampaignProgressionSystemScript.C4_SWITCHBOARD_DEVICE_ID)
	_assert(state.story_flags.r3_diagnosed and state.story_flags.r3_generator_active and state.story_flags.c4_switchboard_active, "Aktywny quick-flow Archiwum -> R-3 -> C-4 nie może zależeć od tymczasowej topologii mapy.")
	_assert(state.story_flags.act == state.story_flags.ACT_COMMON_LINE, "Sekwencja Wspólnej Linii nie może przełączać kampanii do usuniętego aktu.")
	_test_semantic_mission_activation(database)
	_prepare_persistence_fixture(state)
	var errors: PackedStringArray = state.persistence_validation_errors()
	_assert(errors.is_empty(), "Stan po pierwszym wynurzeniu musi przejść walidację zapisu: %s" % "; ".join(errors))
	database.free()
	if _failed:
		quit(1)
		return
	print("Campaign story system test passed: Archive, R-3 and C-4 stay active without legacy physical landmark IDs.")
	quit(0)


func _test_semantic_mission_activation(database) -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(8511, database.get_standard_difficulty())
	_remove_fixed_device_records(state.underwater_world.blueprint, CampaignProgressionSystemScript.ARCHIVE_TERMINAL_DEVICE_ID)
	state.tutorial.complete()
	var missions = MissionSystemScript.new()
	missions.reconcile(state)
	_assert(state.mission_progress.is_active("old_signal"), "The active Archive mission must not become dormant while its semantic target awaits manifest placement.")
	var mission_view: Dictionary = missions.mission_view(state, "old_signal")
	var objective_views: Array = mission_view.get("objectives", [])
	var objective_view: Dictionary = objective_views[0] if not objective_views.is_empty() else {}
	_assert(str(objective_view.get("landmark_id", "")).is_empty() and str(objective_view.get("landmark_label", "")) == "Zalane Archiwum", "An unplaced Archive objective must retain its semantic label without inventing a physical landmark ID.")
	if state.mission_progress.tracked_mission_id != "old_signal":
		_assert(missions.track_mission(state, "old_signal"), "The active Archive mission must remain trackable before manifest placement.")
	var semantic_guidance: Dictionary = missions.expedition_guidance(state)
	_assert(str(semantic_guidance.get("mission_id", "")) == "old_signal" and str(semantic_guidance.get("landmark_id", "")).is_empty(), "Archive guidance must remain active without claiming an unplaced landmark.")
	_assert(str(semantic_guidance.get("guidance", "")).contains("Archiwum"), "Archive guidance must preserve the active campaign destination name.")
	_assert(not missions._definition_targets_are_available(state, missions.mission_definition("rescue_leon")), "A rescue definition must remain dormant until its rescue record is placed by the manifest.")
	_assert(not missions._definition_targets_are_available(state, missions.mission_definition("return_network")), "A navigation definition must remain dormant until the manifest provides its required buoy placement.")
	_assert(not missions._definition_targets_are_available(state, missions.mission_definition("heavy_recovery")), "A heavy-recovery definition must remain dormant until the manifest contains a heavy object.")

	var entry_id := str(state.underwater_world.blueprint.entry_landmark_id)
	state.underwater_world.blueprint.fixed_device_spawns.append({
		"id": CampaignProgressionSystemScript.ARCHIVE_TERMINAL_DEVICE_ID,
		"display_name": "Terminal testowy",
		"landmark_id": entry_id,
	})
	missions.reconcile(state)
	var guidance: Dictionary = missions.expedition_guidance(state)
	_assert(str(guidance.get("landmark_id", "")) == entry_id and str(guidance.get("landmark_label", "")) == "Terminal testowy", "Once placed, Archive guidance must derive its target and display label from the current blueprint record.")


func _apply_device(campaign, state, device_id: String) -> void:
	var result = DiveResultScript.new()
	result.diver_id = "igor"
	result.activated_fixed_devices.append(device_id)
	campaign.apply_dive_result(state, result, null)


func _remove_fixed_device_records(blueprint, device_id: String) -> void:
	if blueprint == null:
		return
	var index: int = int(blueprint.fixed_device_spawns.size()) - 1
	while index >= 0:
		var record = blueprint.fixed_device_spawns[index]
		if record is Dictionary and str(record.get("id", "")) == device_id:
			blueprint.fixed_device_spawns.remove_at(index)
		index -= 1


func _prepare_persistence_fixture(state) -> void:
	var activated_ids := CampaignProgressionSystemScript.required_map_device_ids()
	activated_ids.resize(5)
	var blueprint = state.underwater_world.blueprint
	var entry_id := str(blueprint.entry_landmark_id)
	for device_id in activated_ids:
		var has_record := false
		for record in blueprint.fixed_device_spawns:
			if record is Dictionary and str(record.get("id", "")) == device_id:
				has_record = true
				break
		if not has_record:
			blueprint.fixed_device_spawns.append({
				"id": device_id,
				"display_name": "Urządzenie kampanii fixture",
				"landmark_id": entry_id,
			})
		if not state.underwater_world.delta.activated_fixed_devices.has(device_id):
			state.underwater_world.delta.activated_fixed_devices.append(device_id)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
