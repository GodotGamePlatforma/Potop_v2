extends SceneTree

const SaveManagerScript := preload("res://scripts/core/SaveManager.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const GameFormatScript := preload("res://scripts/data/GameFormat.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")

const PRIMARY := "user://test_campaign_format.tres"
const PENDING := "user://test_campaign_format.pending.tres"
const BACKUP := "user://test_campaign_format.backup.tres"
const LEGACY := "user://test_ostatni_pomost_common_line_autosave.tres"
const LEGACY_SENTINEL := "legacy-save-must-remain-untouched"
var _failed := false

func _initialize() -> void:
	_cleanup()
	_assert(_write_legacy_fixture(), "Fixture starego zapisu musi zostać utworzony.")
	var manager = SaveManagerScript.new()
	root.add_child(manager)
	manager.configure_paths(PRIMARY, PENDING, BACKUP)
	_assert(SaveManagerScript.SAVE_PATH == "user://ostatni_pomost_campaign.tres", "Autosave kampanii musi używać jedynej bieżącej przestrzeni nazw.")
	var state = GameStateScript.new()
	state.setup_new_campaign(25_001, DifficultyProfileScript.new())
	_assert(state.format_revision == GameFormatScript.CAMPAIGN_FORMAT_REVISION, "Nowa kampania musi używać jedynej bieżącej rewizji formatu.")
	state.story_flags.junction_j7_active = true; state.story_flags.junction_j7_activated_day = 1
	state.story_flags.black_front_arrived = true
	state.story_flags.energy_configuration = "harbor"
	state.story_flags.final_outcome_id = "quiet_after_storm"
	state.story_flags.final_resolved_day = 1
	state.story_flags.first_full_integrity_day = 1
	state.story_flags.full_integrity_days = 1
	state.story_flags.successful_dives = 4
	state.story_flags.final_summary = {"day": 1, "survivors": 3, "hope": 50, "platform_integrity": 100, "successful_dives": 4, "diver_deaths": 0}
	state.day = 2; state.current_phase = GamePhaseScript.Phase.ENDING
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 100)
	var community = BuildingStateScript.new()
	var operator = state.survivors[0]
	community.id = "final_radio"; community.definition_id = "community_house"; community.slot_id = "top_right"; community.level = 3
	community.assigned_survivor_ids.assign([operator.id])
	state.buildings.append(community)
	var slot_data: Dictionary = state.platform.slot_states[community.slot_id]
	slot_data["building_id"] = community.id; state.platform.slot_states[community.slot_id] = slot_data
	operator.current_assignment = community.id; operator.status = SurvivorStateScript.Status.WORKING
	operator.competency_levels = {"swimming": 2, "oxygen_economy": 3, "resilience": 1}
	state.story_flags.chronicle_summary = {
		"outcome_id": "quiet_after_storm", "ending_title": "CISZA PO BURZY", "black_front_day": 1,
		"first_full_integrity_day": 1, "integrity_before_storm": 100, "integrity_after_storm": 100,
		"full_integrity_days": 1, "dives": 4, "safe_returns": 4, "diver_deaths": 0,
		"recovered_backpacks": 0, "living_survivors": ["Mira", "Anka", "Igor"], "dead_survivors": [],
		"accepted_survivors": [], "rejected_survivors": [], "rescued_survivors": 0, "leon_fate": "nierozstrzygnięty",
		"buildings": [{"definition_id": "community_house", "level": 3}], "resources": {},
		"r3_active": false, "c4_active": false, "splitter_installed": false, "radio_active": true,
		"energy_configuration": "harbor", "north_platform_survived": false, "hope": 50, "important_decisions": []
	}
	state.prepare_weather_for_day(); state.prepare_pressure_for_day(); state.begin_new_day_plan()
	state.preferred_diver_id = "igor"
	state.underwater_world.delta.activated_fixed_devices.assign(["junction_j7"])
	_assert(manager.save_game(state) == OK, "Bieżący format kampanii musi przejść zapis.")
	_assert(_legacy_fixture_is_untouched(), "Zapis bieżącej kampanii nie może modyfikować starego pliku.")
	var loaded = manager.load_game()
	_assert(loaded != null and loaded.format_revision == GameFormatScript.CAMPAIGN_FORMAT_REVISION and loaded.story_flags.chronicle_summary.outcome_id == "quiet_after_storm" and loaded.preferred_diver_id == "igor", "Bieżący format musi zachować Kronikę i zapamiętanego nurka.")
	var loaded_operator = loaded.find_survivor(operator.id) if loaded != null else null
	_assert(loaded_operator != null and loaded_operator.competency_levels == {"swimming": 2, "oxygen_economy": 3, "resilience": 1}, "Bieżący format musi zachować kompetencje.")
	operator.competency_levels["active_dash"] = 1
	_assert(manager.save_game(state) == ERR_INVALID_DATA, "Nieznana kompetencja musi zostać odrzucona.")
	var preserved = manager.load_game()
	var preserved_operator = preserved.find_survivor(operator.id) if preserved != null else null
	_assert(preserved_operator != null and preserved_operator.competency_levels == {"swimming": 2, "oxygen_economy": 3, "resilience": 1}, "Odrzucony zapis nie może nadpisać primary.")
	_cleanup(false)
	var stale_map_state = preserved.duplicate(true) if preserved != null else null
	_assert(stale_map_state != null, "Fixture kampanii ze starą sygnaturą mapy wymaga poprawnego bieżącego zapisu.")
	if stale_map_state != null:
		var current_signature := str(stale_map_state.underwater_world.blueprint.map_gameplay_signature)
		var stale_signature := "0".repeat(64) if current_signature != "0".repeat(64) else "f".repeat(64)
		stale_map_state.underwater_world.blueprint.map_gameplay_signature = stale_signature
		for candidate_path in [PRIMARY, PENDING, BACKUP]:
			_assert(
				ResourceSaver.save(stale_map_state.duplicate(true), candidate_path) == OK,
				"Fixture starej sygnatury mapy musi powstać dla %s." % candidate_path
			)
		var stale_hashes_before := _storage_hashes()
		_assert(not manager.has_save(), "Żaden kandydat ze starą sygnaturą mapy nie może włączyć Kontynuuj.")
		_assert(manager.load_game() == null, "Primary, pending ani backup ze starą sygnaturą mapy nie mogą zostać wczytane jako fallback.")
		_assert(
			_storage_hashes() == stale_hashes_before,
			"Odrzucenie starej sygnatury mapy nie może mutować primary, pending ani backupu."
		)
		for candidate_path in [PRIMARY, PENDING, BACKUP]:
			_assert(
				_diagnostic_mentions(manager, candidate_path, "nie odpowiada bieżącemu manifestowi mapy"),
				"Diagnostyka %s musi jawnie wskazać clean break sygnatury mapy." % candidate_path
			)
	_cleanup(false)
	state.format_revision = GameFormatScript.CAMPAIGN_FORMAT_REVISION - 1
	_assert(ResourceSaver.save(state, PRIMARY) == OK, "Niezgodny format musi powstać poza granicą zapisu.")
	_assert(not manager.has_save() and manager.load_game() == null, "Niezgodny format nie może zostać wczytany.")
	_assert(manager.delete_campaign_storage() == OK, "Usunięcie bieżącej kampanii musi objąć jej trzy pliki.")
	_assert(not manager.has_any_save_file(), "Stary plik nie może być traktowany jako bieżąca kampania.")
	_assert(_legacy_fixture_is_untouched(), "Usunięcie bieżącej kampanii nie może usuwać starego zapisu.")
	root.remove_child(manager); manager.free(); _cleanup()
	if _failed: quit(1); return
	print("Campaign format test passed: roundtrip, atomic rejection and format isolation."); quit(0)

func _cleanup(include_legacy: bool = true) -> void:
	var paths := [PRIMARY, PENDING, BACKUP]
	if include_legacy:
		paths.append(LEGACY)
	for path in paths:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute): DirAccess.remove_absolute(absolute)

func _write_legacy_fixture() -> bool:
	var file := FileAccess.open(LEGACY, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(LEGACY_SENTINEL)
	file.close()
	return true

func _legacy_fixture_is_untouched() -> bool:
	var file := FileAccess.open(LEGACY, FileAccess.READ)
	if file == null:
		return false
	var contents := file.get_as_text()
	file.close()
	return contents == LEGACY_SENTINEL

func _storage_hashes() -> Dictionary:
	var hashes := {}
	for path in [PRIMARY, PENDING, BACKUP]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _diagnostic_mentions(manager, path: String, fragment: String) -> bool:
	var errors: PackedStringArray = manager.load_diagnostics.get(path, PackedStringArray())
	for error in errors:
		if str(error).contains(fragment):
			return true
	return false

func _assert(condition: bool, message: String) -> void:
	if not condition: _failed = true; push_error("Campaign format test failed: " + message)
