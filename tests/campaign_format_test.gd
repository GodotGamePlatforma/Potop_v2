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
const REPLACEMENT_GUARD := PRIMARY + ".replace_guard"
const EXPECTED := "user://test_campaign_format.expected.tres"
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
	_test_campaign_replacement(manager)
	_cleanup(false)
	state.format_revision = GameFormatScript.CAMPAIGN_FORMAT_REVISION - 1
	for current_path in [PRIMARY, PENDING, BACKUP]:
		_assert(ResourceSaver.save(state.duplicate(true), current_path) == OK, "Niezgodny format musi powstać poza granicą zapisu w %s." % current_path)
	_assert(not manager.has_save() and manager.load_game() == null, "Niezgodny format nie może zostać wczytany.")
	_assert(manager.delete_campaign_storage() == OK, "Usunięcie bieżącej kampanii musi objąć trzy snapshoty i trwałą blokadę replacement.")
	_assert(not manager.has_any_save_file(), "Usunięcie namespace musi faktycznie usunąć primary, pending, backup i blokadę replacement.")
	_assert(_legacy_fixture_is_untouched(), "Usunięcie bieżącej kampanii nie może usuwać starego zapisu.")
	root.remove_child(manager); manager.free(); _cleanup()
	if _failed: quit(1); return
	print("Campaign format test passed: roundtrip, atomic rejection and format isolation."); quit(0)


func _test_campaign_replacement(manager) -> void:
	manager.last_replacement_failure_stage = "outer_transaction"
	manager.last_replacement_failure_details = PackedStringArray(["outer details"])
	manager.set("_replacement_in_progress", true)
	_assert(manager.replace_campaign(null) == ERR_BUSY, "Reentrant null call must be rejected before it can clear the outer guard.")
	_assert(bool(manager.get("_replacement_in_progress")), "Reentrant call must not release the outer transaction guard.")
	_assert(manager.last_replacement_failure_stage == "outer_transaction" and manager.last_replacement_failure_details == PackedStringArray(["outer details"]), "Reentrant call must not overwrite diagnostics owned by the outer transaction.")
	manager.set("_replacement_in_progress", false)
	manager.last_replacement_failure_stage = ""
	manager.last_replacement_failure_details = PackedStringArray()

	var failure_steps := [
		SaveManagerScript.REPLACE_STEP_PENDING_WRITE,
		SaveManagerScript.REPLACE_STEP_BACKUP_WRITE,
		SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT,
	]
	for index in range(failure_steps.size()):
		_cleanup(false)
		var old_state = _new_campaign(31_000 + index * 10)
		_assert(manager.save_game(old_state) == OK, "Fixture starej kampanii musi zostać zapisany przed failpointem %s." % failure_steps[index])
		var old_id := str(old_state.campaign_id)
		var replacement = _new_campaign(31_001 + index * 10)
		manager.fail_next_campaign_replacement_for_tests(failure_steps[index], ERR_CANT_CREATE)
		_assert(manager.replace_campaign(replacement) == ERR_CANT_CREATE, "Failpoint %s musi zwrócić kontrolowaną porażkę." % failure_steps[index])
		var preserved = manager.load_game()
		_assert(preserved != null and str(preserved.campaign_id) == old_id, "Failpoint %s musi pozostawić starą kampanię jako wynik odczytu." % failure_steps[index])
		_assert(str(replacement.last_saved_at).is_empty(), "Porażka %s nie może mutować wejściowego kandydata." % failure_steps[index])
		_assert(manager.replace_campaign(replacement) == OK, "Retry po failpoincie %s musi zakończyć transakcję." % failure_steps[index])
		_assert(not str(replacement.last_saved_at).is_empty(), "Sukces retry musi opublikować timestamp w wejściowym kandydacie.")
		_assert_only_valid_campaign_snapshot(manager, replacement, "retry po %s" % failure_steps[index])
		_assert(_valid_campaign_id(PRIMARY) == str(replacement.campaign_id), "Sukces musi zatwierdzić nową kampanię w primary.")
		_assert(_valid_campaign_id(BACKUP) == str(replacement.campaign_id), "Sukces musi zachować nową kampanię także w backup.")
		_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(PENDING)), "Zwykły sukces musi usunąć przejściowy pending.")

	_cleanup(false)
	var divergent_old = _new_campaign(31_100)
	_assert(manager.save_game(divergent_old) == OK, "Fixture rozbieżnej kanonizacji wymaga starej kampanii.")
	var divergent_old_canonical = manager.load_game()
	var divergent_new = _new_campaign(31_101)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_BACKUP_PAYLOAD_MISMATCH, ERR_INVALID_DATA)
	_assert(manager.replace_campaign(divergent_new) == ERR_INVALID_DATA, "Różne payloady dwóch niezależnych zapisów muszą zatrzymać transakcję przed commitem.")
	_assert(manager.last_replacement_failure_stage == SaveManagerScript.REPLACE_STEP_BACKUP_WRITE, "Rozbieżność niezależnych zapisów musi wskazać etap backup.")
	var divergent_preserved = manager.load_game()
	_assert(divergent_preserved != null and bool(manager.call("_same_campaign_snapshot_identity", divergent_preserved, divergent_old_canonical)), "Rozbieżność niezależnych zapisów musi zachować dokładną starą kampanię.")
	_assert(manager.replace_campaign(divergent_new) == OK, "Retry po rozbieżności niezależnych zapisów musi zakończyć transakcję.")
	_assert_only_valid_campaign_snapshot(manager, divergent_new, "retry po rozbieżnej kanonizacji")

	for source_path in [PENDING, BACKUP]:
		_cleanup(false)
		var fallback_old = _new_campaign(32_000 + (1 if source_path == PENDING else 2))
		_assert(ResourceSaver.save(fallback_old, source_path) == OK, "Poprawna poprzednia kampania musi powstać wyłącznie w %s." % source_path)
		manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_NORMALIZE_PRIMARY, ERR_CANT_CREATE)
		var fallback_new = _new_campaign(32_100 + (1 if source_path == PENDING else 2))
		_assert(manager.replace_campaign(fallback_new) == ERR_CANT_CREATE, "Błąd normalizacji %s musi być kontrolowany." % source_path)
		var fallback_loaded = manager.load_game()
		_assert(fallback_loaded != null and str(fallback_loaded.campaign_id) == str(fallback_old.campaign_id), "Błąd normalizacji musi zachować źródłową kampanię w %s." % source_path)
		_assert(manager.replace_campaign(fallback_new) == OK, "Retry musi znormalizować %s i zatwierdzić nową kampanię." % source_path)
		_assert_only_valid_campaign_snapshot(manager, fallback_new, "normalizacja %s" % source_path)

	_cleanup(false)
	var no_old_candidate = _new_campaign(33_001)
	var empty_hashes := _storage_hashes()
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT, ERR_CANT_CREATE)
	_assert(manager.replace_campaign(no_old_candidate) == ERR_CANT_CREATE, "Pierwsza kampania musi móc bezpiecznie odrzucić błąd przed commitem.")
	_assert(_storage_hashes() == empty_hashes and manager.load_game() == null, "Porażka pierwszej kampanii przed commitem nie może opublikować stagingu.")
	_assert(manager.replace_campaign(no_old_candidate) == OK, "Retry pierwszej kampanii musi zatwierdzić primary.")
	_assert_only_valid_campaign_snapshot(manager, no_old_candidate, "pierwsza kampania")

	var first_campaign_recovery_template = no_old_candidate.duplicate(true)
	for first_campaign_recovery_step in [
		SaveManagerScript.REPLACE_STEP_BACKUP_PAYLOAD_MISMATCH,
		SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT_TARGET_LOSS,
	]:
		_cleanup(false)
		var recovered_first = first_campaign_recovery_template.duplicate(true)
		recovered_first.campaign_id = "first-recovery-%s" % first_campaign_recovery_step
		recovered_first.last_saved_at = ""
		manager.fail_next_campaign_replacement_for_tests(first_campaign_recovery_step, ERR_CANT_CREATE)
		_assert(manager.replace_campaign(recovered_first) == OK, "Pierwsza kampania musi pojednać jednorazową awarię %s przez niezależną większość." % first_campaign_recovery_step)
		_assert_only_valid_campaign_snapshot(manager, recovered_first, "pierwsza kampania po %s" % first_campaign_recovery_step)
		_assert(_valid_campaign_id(PRIMARY) == str(recovered_first.campaign_id), "Recovery pierwszej kampanii po %s musi zakończyć się dokładnym primary." % first_campaign_recovery_step)
		_assert(_valid_campaign_id(BACKUP) == str(recovered_first.campaign_id), "Recovery pierwszej kampanii po %s musi zakończyć się dokładnym backup." % first_campaign_recovery_step)
		_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(PENDING)), "Recovery pierwszej kampanii po %s musi posprzątać świadka pending." % first_campaign_recovery_step)

	_cleanup(false)
	var pair_recovered_first = first_campaign_recovery_template.duplicate(true)
	pair_recovered_first.campaign_id = "first-recovery-pair"
	pair_recovered_first.last_saved_at = ""
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT_TARGET_LOSS, ERR_CANT_CREATE)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_FIRST_PRIMARY_REPAIR, ERR_CANT_CREATE)
	_assert(manager.replace_campaign(pair_recovered_first) == OK, "Brak primary i jednorazowa porażka jego naprawy muszą zatwierdzić dokładną parę pending/backup.")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(PRIMARY)), "Recovery pair pierwszej kampanii nie może udawać, że primary istnieje.")
	_assert(_valid_campaign_id(PENDING) == str(pair_recovered_first.campaign_id) and _valid_campaign_id(BACKUP) == str(pair_recovered_first.campaign_id), "Recovery pair pierwszej kampanii musi zachować dwa dokładne świadki.")
	_assert_only_valid_campaign_snapshot(manager, pair_recovered_first, "pierwsza kampania jako recovery pair")

	_cleanup(false)
	var repaired_backup_first = first_campaign_recovery_template.duplicate(true)
	repaired_backup_first.campaign_id = "first-recovery-backup-retry"
	repaired_backup_first.last_saved_at = ""
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_BACKUP_PAYLOAD_MISMATCH, ERR_INVALID_DATA)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_FIRST_BACKUP_REPAIR, ERR_CANT_CREATE)
	_assert(manager.replace_campaign(repaired_backup_first) == OK, "Dokładne primary/pending muszą pozwolić ponowić jednorazowo nieudaną naprawę backup przed publikacją sukcesu.")
	_assert_only_valid_campaign_snapshot(manager, repaired_backup_first, "retry naprawy backup pierwszej kampanii")
	_assert(_valid_campaign_id(PRIMARY) == str(repaired_backup_first.campaign_id) and _valid_campaign_id(BACKUP) == str(repaired_backup_first.campaign_id), "Retry naprawy musi zakończyć się dokładnym primary/backup.")

	_cleanup(false)
	var repeatedly_divergent_backup = first_campaign_recovery_template.duplicate(true)
	repeatedly_divergent_backup.campaign_id = "first-recovery-backup-repeated-failure"
	repeatedly_divergent_backup.last_saved_at = ""
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_BACKUP_PAYLOAD_MISMATCH, ERR_INVALID_DATA)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_FIRST_BACKUP_REPAIR, ERR_CANT_CREATE)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_COMMITTED_BACKUP_REPAIR, ERR_CANT_CREATE)
	_assert(manager.replace_campaign(repeatedly_divergent_backup) != OK, "Druga porażka naprawy rozbieżnego backupu nie może opublikować niepełnego sukcesu.")
	_assert(manager.last_replacement_outcome == SaveManagerScript.CampaignReplacementOutcome.IN_DOUBT, "Rozbieżny poprawny backup przy kanonicznym primary musi zachować trwałe IN_DOUBT.")
	_assert(FileAccess.file_exists(ProjectSettings.globalize_path(REPLACEMENT_GUARD)) and manager.load_game() == null and not manager.has_save(), "Rozbieżna kopia po commicie musi pozostawić wszystkie publiczne granice odczytu zamknięte.")
	var divergent_primary_private = ResourceLoader.load(PRIMARY, "", ResourceLoader.CACHE_MODE_IGNORE)
	var divergent_backup_private = ResourceLoader.load(BACKUP, "", ResourceLoader.CACHE_MODE_IGNORE)
	_assert(divergent_primary_private != null and divergent_backup_private != null and not bool(manager.call("_same_campaign_snapshot_identity", divergent_primary_private, divergent_backup_private)), "Fixture musi rzeczywiście pozostawić dwa poprawne, lecz rozbieżne snapshoty.")
	var repaired_after_repeated_failure = first_campaign_recovery_template.duplicate(true)
	repaired_after_repeated_failure.campaign_id = "first-recovery-after-repeated-failure"
	repaired_after_repeated_failure.last_saved_at = ""
	_assert(manager.replace_campaign(repaired_after_repeated_failure) == OK, "Retry po wielokrotnej porażce naprawy musi uzgodnić wszystkie istniejące kopie do nowego kanonu.")
	_assert_only_valid_campaign_snapshot(manager, repaired_after_repeated_failure, "retry po wielokrotnej porażce naprawy backup")

	_cleanup(false)
	var no_quorum_first = first_campaign_recovery_template.duplicate(true)
	no_quorum_first.campaign_id = "first-no-quorum-in-doubt"
	no_quorum_first.last_saved_at = ""
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_BACKUP_PAYLOAD_MISMATCH, ERR_INVALID_DATA)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_PENDING_WRITE, ERR_CANT_CREATE)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_FIRST_ROLLBACK_CLEANUP, ERR_CANT_CREATE)
	_assert(manager.replace_campaign(no_quorum_first) != OK, "Brak quorum i niemożliwy rollback pierwszej kampanii nie mogą zostać zgłoszone jako sukces.")
	_assert(manager.last_replacement_outcome == SaveManagerScript.CampaignReplacementOutcome.IN_DOUBT, "Brak quorum z niepotwierdzonym rollbackiem musi mieć jawny wynik IN_DOUBT, nie fałszywe PRESERVED.")
	_assert(not manager.has_save(), "IN_DOUBT musi wyłączyć Continue w bieżącym procesie.")
	_assert(manager.load_game() == null, "Publiczny loader nie może ominąć blokady IN_DOUBT.")
	var private_no_quorum_info: Dictionary = manager.call("_first_valid_campaign_candidate")
	_assert(not private_no_quorum_info.is_empty(), "Fixture musi prywatnie dowieść, że zwykła porażka byłaby fałszywa, ponieważ poprawny kandydat nadal jest obserwowalny.")

	_cleanup(false)
	var dissenting_primary_first = first_campaign_recovery_template.duplicate(true)
	dissenting_primary_first.campaign_id = "first-dissenting-primary-in-doubt"
	dissenting_primary_first.last_saved_at = ""
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT_FOREIGN_TARGET, ERR_CANT_CREATE)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_FIRST_PRIMARY_REPAIR, ERR_CANT_CREATE)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_FIRST_ROLLBACK_CLEANUP, ERR_CANT_CREATE)
	_assert(manager.replace_campaign(dissenting_primary_first) != OK, "Obcy primary, nieudana naprawa i niepotwierdzony rollback nie mogą zostać zgłoszone jako sukces.")
	_assert(manager.last_replacement_outcome == SaveManagerScript.CampaignReplacementOutcome.IN_DOUBT, "Obcy primary zasłaniający dokładną większość musi zakończyć się IN_DOUBT.")
	_assert(not manager.has_save(), "Niejednoznaczny obcy primary musi zablokować Continue do uzgodnienia zapisu.")

	_cleanup(false)
	var invalid = _new_campaign(33_100)
	invalid.format_revision = GameFormatScript.CAMPAIGN_FORMAT_REVISION - 1
	for invalid_path in [PRIMARY, PENDING, BACKUP]:
		_assert(ResourceSaver.save(invalid.duplicate(true), invalid_path) == OK, "Fixture nieprawidłowego namespace musi powstać w %s." % invalid_path)
	var invalid_hashes := _storage_hashes()
	var invalid_replacement = _new_campaign(33_101)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT, ERR_CANT_CREATE)
	_assert(manager.replace_campaign(invalid_replacement) == ERR_CANT_CREATE, "Błąd przed commitem nie może usuwać nieprawidłowego namespace z pierwotnego przypadku.")
	_assert(_storage_hashes() == invalid_hashes, "Błąd przed commitem musi pozostawić wszystkie nieprawidłowe pliki byte-for-byte bez zmian.")
	_assert(manager.has_any_save_file() and not manager.has_save(), "Po kontrolowanej porażce nieprawidłowy namespace nadal istnieje, ale nie może stać się kampanią do kontynuacji.")
	_assert(manager.replace_campaign(invalid_replacement) == OK, "Brak poprawnej starej kampanii nie może blokować bezpiecznego zastąpienia nieprawidłowych plików.")
	_assert_only_valid_campaign_snapshot(manager, invalid_replacement, "zastąpienie nieprawidłowego namespace")
	var same_metadata_stale_payload = invalid_replacement.duplicate(true)
	same_metadata_stale_payload.resources.add_amount("food", 1)
	_assert(same_metadata_stale_payload.load_validation_errors().is_empty(), "Fixture obcego payloadu z tą samą metryką musi pozostać poprawną kampanią.")
	_assert(not bool(manager.call("_same_campaign_snapshot_identity", same_metadata_stale_payload, invalid_replacement)), "Równe ID i timestampy nie mogą ukryć różnicy w payloadzie kampanii.")
	var near_float_payload = invalid_replacement.duplicate(true)
	near_float_payload.weather.foam_intensity = float(near_float_payload.weather.foam_intensity) + 0.000001
	_assert(near_float_payload.load_validation_errors().is_empty(), "Minimalnie odmienny float musi pozostać poprawnym fixture payloadu.")
	_assert(not bool(manager.call("_same_campaign_snapshot_identity", near_float_payload, invalid_replacement)), "Porównanie snapshotu nie może używać tolerancji gameplayowej dla różnych wartości float.")

	_cleanup(false)
	var crash_old = _new_campaign(34_001)
	var crash_new = _new_campaign(34_002)
	crash_old.last_saved_at = "2026-08-27T08:00:00"
	crash_new.last_saved_at = "2026-08-27T08:01:00"
	_assert(ResourceSaver.save(crash_old, PRIMARY) == OK, "Fixture przerwania przed commitem wymaga starego primary.")
	_assert(ResourceSaver.save(crash_new, PENDING) == OK and ResourceSaver.save(crash_new, BACKUP) == OK, "Fixture przerwania przed commitem wymaga dwóch kopii nowego snapshotu.")
	var before_commit_loaded = manager.load_game()
	_assert(before_commit_loaded != null and str(before_commit_loaded.campaign_id) == str(crash_old.campaign_id), "Przerwanie przed commitem musi deterministycznie wybrać stary primary.")
	_assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(PRIMARY)) == OK, "Fixture przerwania po commicie musi móc usunąć stary primary.")
	var after_commit_loaded = manager.load_game()
	_assert(after_commit_loaded != null and str(after_commit_loaded.campaign_id) == str(crash_new.campaign_id), "Brak primary po punkcie przełączenia musi odzyskać kompletny nowy pending/backup.")

	_cleanup(false)
	var reported_old = _new_campaign(34_101)
	_assert(manager.save_game(reported_old) == OK, "Fixture błędu po zapisie wymaga starego primary.")
	var reported_new = _new_campaign(34_102)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT_AFTER_WRITE, ERR_CANT_CREATE)
	_assert(manager.replace_campaign(reported_new) == OK, "Błąd zgłoszony po widocznym zapisie dokładnego nowego primary musi zostać rozpoznany jako commit.")
	_assert_only_valid_campaign_snapshot(manager, reported_new, "niejednoznaczny błąd po widocznym commicie")

	_cleanup(false)
	var lost_target_old = _new_campaign(34_201)
	_assert(manager.save_game(lost_target_old) == OK, "Fixture utraty celu wymaga starego primary.")
	var lost_target_new = _new_campaign(34_202)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT_TARGET_LOSS, ERR_CANT_CREATE)
	_assert(manager.replace_campaign(lost_target_new) == OK, "Brak primary przy dwóch dokładnych kopiach recovery musi zostać rozpoznany jako zatwierdzona nowa kampania.")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(PRIMARY)), "Symulacja utraty celu musi rzeczywiście pozostawić primary niewidoczne.")
	_assert_only_valid_campaign_snapshot(manager, lost_target_new, "recovery po utracie primary")
	var recovered_after_target_loss = manager.load_game()
	_assert(recovered_after_target_loss != null and bool(manager.call("_same_campaign_snapshot_identity", recovered_after_target_loss, lost_target_new)), "Odczyt po utracie primary musi odzyskać dokładny nowy snapshot.")
	_assert(manager.save_game(recovered_after_target_loss) == OK, "Zwykły zapis po recovery bez primary musi odtworzyć primary i pozostać używalny.")
	_assert(_valid_campaign_id(PRIMARY) == str(lost_target_new.campaign_id), "Zapis po recovery musi przywrócić primary tej samej nowej kampanii.")

	for ambiguous_target_step in [
		SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT_INVALID_TARGET,
		SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT_FOREIGN_TARGET,
	]:
		_cleanup(false)
		var ambiguous_old = _new_campaign(34_300 if ambiguous_target_step == SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT_INVALID_TARGET else 34_400)
		_assert(manager.save_game(ambiguous_old) == OK, "Fixture pojednania %s wymaga starego primary." % ambiguous_target_step)
		var ambiguous_new = _new_campaign(34_301 if ambiguous_target_step == SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT_INVALID_TARGET else 34_401)
		manager.fail_next_campaign_replacement_for_tests(ambiguous_target_step, ERR_CANT_CREATE)
		_assert(manager.replace_campaign(ambiguous_new) == OK, "Niejednoznaczny %s musi zostać pojednany do nowej albo starej kampanii; jednorazowy błąd powinien domknąć nową." % ambiguous_target_step)
		_assert_only_valid_campaign_snapshot(manager, ambiguous_new, "pojednanie %s" % ambiguous_target_step)
		_assert(_valid_campaign_id(PRIMARY) == str(ambiguous_new.campaign_id), "Pojednanie %s musi opublikować dokładny nowy primary." % ambiguous_target_step)
		var ambiguous_loaded = manager.load_game()
		_assert(ambiguous_loaded != null and manager.save_game(ambiguous_loaded) == OK, "Kampania po pojednaniu %s musi obsługiwać kolejny zwykły zapis." % ambiguous_target_step)
		_assert(_valid_campaign_id(PRIMARY) == str(ambiguous_new.campaign_id), "Kolejny zapis po pojednaniu %s nie może zmienić tożsamości kampanii." % ambiguous_target_step)

	for irreconcilable_target_step in [
		SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT_INVALID_TARGET,
		SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT_FOREIGN_TARGET,
	]:
		_cleanup(false)
		var irreconcilable_old = _new_campaign(34_500 if irreconcilable_target_step == SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT_INVALID_TARGET else 34_600)
		_assert(manager.save_game(irreconcilable_old) == OK, "Fixture nieuzgadnialnego %s wymaga starego primary." % irreconcilable_target_step)
		var irreconcilable_old_canonical = manager.load_game()
		var irreconcilable_new = _new_campaign(34_501 if irreconcilable_target_step == SaveManagerScript.REPLACE_STEP_PRIMARY_COMMIT_INVALID_TARGET else 34_601)
		manager.fail_next_campaign_replacement_for_tests(irreconcilable_target_step, ERR_CANT_CREATE)
		manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_RECONCILE_REWRITE_NEW, ERR_CANT_CREATE)
		manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_RECONCILE_RESTORE_OLD, ERR_CANT_CREATE)
		manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_RECONCILE_REMOVE_PRIMARY, ERR_CANT_CREATE)
		_assert(manager.replace_campaign(irreconcilable_new) != OK, "Wielokrotna awaria pojednania %s nie może zostać zgłoszona jako sukces." % irreconcilable_target_step)
		_assert(manager.last_replacement_outcome == SaveManagerScript.CampaignReplacementOutcome.IN_DOUBT, "Wielokrotna awaria %s musi być IN_DOUBT, nie fałszywym PRESERVED." % irreconcilable_target_step)
		_assert(not manager.has_save(), "IN_DOUBT po %s musi wyłączyć Continue w bieżącym procesie." % irreconcilable_target_step)
		_assert(manager.load_game() == null, "Publiczny loader musi pozostać fail-closed po %s." % irreconcilable_target_step)
		var private_irreconcilable_info: Dictionary = manager.call("_first_valid_campaign_candidate")
		var private_irreconcilable_loaded = private_irreconcilable_info.get("state")
		_assert(private_irreconcilable_loaded != null and not bool(manager.call("_same_campaign_snapshot_identity", private_irreconcilable_loaded, irreconcilable_old_canonical)), "Fixture %s musi prywatnie dowieść, że zwykła porażka byłaby fałszywa." % irreconcilable_target_step)

	_assert(FileAccess.file_exists(ProjectSettings.globalize_path(REPLACEMENT_GUARD)), "IN_DOUBT musi pozostawić trwałą blokadę w tym samym namespace.")
	var restarted_manager = SaveManagerScript.new()
	root.add_child(restarted_manager)
	restarted_manager.configure_paths(PRIMARY, PENDING, BACKUP)
	_assert(restarted_manager.last_replacement_outcome == SaveManagerScript.CampaignReplacementOutcome.IN_DOUBT, "Nowa instancja SaveManagera musi odtworzyć IN_DOUBT z trwałej blokady.")
	_assert(not restarted_manager.has_save() and restarted_manager.load_game() == null, "Restart procesu nie może ponownie włączyć ani wczytać nieuzgodnionej kampanii.")
	var blocked_autosave = _new_campaign(34_700)
	_assert(restarted_manager.save_game(blocked_autosave) == ERR_BUSY, "Zwykły autosave nie może modyfikować namespace objętego IN_DOUBT.")
	var failed_retry = _new_campaign(34_701)
	restarted_manager.fail_next_save_for_tests(ERR_CANT_CREATE)
	_assert(restarted_manager.replace_campaign(failed_retry) == ERR_CANT_CREATE, "Nieudany retry przed zapisem musi zwrócić rzeczywisty błąd.")
	_assert(restarted_manager.last_replacement_outcome == SaveManagerScript.CampaignReplacementOutcome.IN_DOUBT, "Nieudany retry nie może zrzucić sticky IN_DOUBT do PRESERVED.")
	_assert(FileAccess.file_exists(ProjectSettings.globalize_path(REPLACEMENT_GUARD)) and not restarted_manager.has_save() and restarted_manager.load_game() == null, "Nieudany retry musi zachować trwałą blokadę odczytu.")
	var resolved_retry = _new_campaign(34_702)
	_assert(restarted_manager.replace_campaign(resolved_retry) == OK, "Udany retry musi pojednać trwały IN_DOUBT do jednej nowej kampanii.")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(REPLACEMENT_GUARD)), "Dopiero zweryfikowany commit może usunąć trwałą blokadę.")
	var restarted_loaded = restarted_manager.load_game()
	_assert(restarted_loaded != null and bool(restarted_manager.call("_same_campaign_snapshot_identity", restarted_loaded, resolved_retry)), "Po udanym retry loader musi widzieć dokładny nowy kanon.")
	root.remove_child(restarted_manager)
	restarted_manager.free()

	_cleanup(false)
	var cleanup_old = _new_campaign(35_001)
	_assert(manager.save_game(cleanup_old) == OK, "Fixture błędu cleanup wymaga starej kampanii.")
	var cleanup_new = _new_campaign(35_002)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_CLEANUP, ERR_CANT_CREATE)
	_assert(manager.replace_campaign(cleanup_new) == OK, "Błąd cleanup po commicie nie może zmienić zatwierdzonej transakcji w porażkę.")
	_assert_only_valid_campaign_snapshot(manager, cleanup_new, "cleanup po commicie")

	_cleanup(false)
	var identity_old = _new_campaign(36_001)
	_assert(manager.save_game(identity_old) == OK, "Fixture kolizji tożsamości wymaga starej kampanii.")
	var identity_hashes := _storage_hashes()
	var identity_collision = _new_campaign(36_002)
	identity_collision.campaign_id = identity_old.campaign_id
	_assert(manager.replace_campaign(identity_collision) == ERR_INVALID_PARAMETER, "Zastąpienie nie może przyjąć tożsamości bieżącej kampanii jako nowej.")
	_assert(_storage_hashes() == identity_hashes and _valid_campaign_id(PRIMARY) == str(identity_old.campaign_id), "Kolizja tożsamości nie może mutować namespace.")

	_test_replacement_guard_failpoints(manager)
	_test_guarded_crash_snapshots()
	_test_all_storage_state_combinations(manager)


func _test_replacement_guard_failpoints(manager) -> void:
	_cleanup(false)
	var guard_old = _new_campaign(36_101)
	_assert(manager.save_game(guard_old) == OK, "Fixture awarii utworzenia blokady wymaga poprawnej starej kampanii.")
	var guard_old_canonical = manager.load_game()
	var guard_old_hashes := _storage_hashes()
	var guard_create_candidate = _new_campaign(36_102)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_GUARD_CREATE, ERR_CANT_CREATE)
	_assert(manager.replace_campaign(guard_create_candidate) == ERR_CANT_CREATE, "Awaria utworzenia blokady musi zatrzymać zastąpienie przed pierwszą mutacją namespace.")
	_assert(manager.last_replacement_outcome == SaveManagerScript.CampaignReplacementOutcome.PRESERVED, "Awaria utworzenia blokady przed mutacją musi jawnie zachować starą kampanię.")
	_assert(manager.last_replacement_failure_stage == SaveManagerScript.REPLACE_STEP_GUARD_CREATE, "Awaria utworzenia blokady musi wskazać dokładny etap diagnostyczny.")
	_assert(_storage_hashes() == guard_old_hashes, "Awaria utworzenia blokady musi pozostawić stare pliki byte-for-byte bez zmian.")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(REPLACEMENT_GUARD)), "Nieudane utworzenie blokady nie może pozostawić pozornego markera.")
	var guard_old_after_failure = manager.load_game()
	_assert(guard_old_after_failure != null and bool(manager.call("_same_campaign_snapshot_identity", guard_old_after_failure, guard_old_canonical)), "Po awarii utworzenia blokady loader musi nadal zwracać dokładny stary kanon.")
	_assert(manager.take_last_replacement_committed_state() == null, "Porażka utworzenia blokady nie może publikować canonical handoff.")
	_assert(str(guard_create_candidate.last_saved_at).is_empty(), "Porażka utworzenia blokady nie może mutować wejściowego kandydata.")

	_cleanup(false)
	var invalid_namespace = _new_campaign(36_111)
	invalid_namespace.format_revision = GameFormatScript.CAMPAIGN_FORMAT_REVISION - 1
	for invalid_path in [PRIMARY, PENDING, BACKUP]:
		_assert(ResourceSaver.save(invalid_namespace.duplicate(true), invalid_path) == OK, "Fixture awarii blokady musi utworzyć nieprawidłowy plik %s." % invalid_path)
	var invalid_hashes := _storage_hashes()
	var invalid_guard_candidate = _new_campaign(36_112)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_GUARD_CREATE, ERR_CANT_CREATE)
	_assert(manager.replace_campaign(invalid_guard_candidate) == ERR_CANT_CREATE, "Awaria utworzenia blokady musi zatrzymać również zastąpienie nieprawidłowego namespace.")
	_assert(_storage_hashes() == invalid_hashes, "Bez trwałej blokady nieprawidłowy namespace musi pozostać byte-for-byte bez zmian.")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(REPLACEMENT_GUARD)), "Nieudana blokada nieprawidłowego namespace nie może pozostawić markera.")
	_assert(manager.load_game() == null and not manager.has_save(), "Nieprawidłowy namespace po awarii blokady nie może stać się kampanią do kontynuacji.")
	_assert(manager.take_last_replacement_committed_state() == null, "Awaria blokady nieprawidłowego namespace nie może publikować handoffu.")

	_cleanup(false)
	var guard_clear_old = _new_campaign(36_121)
	_assert(manager.save_game(guard_clear_old) == OK, "Fixture awarii usunięcia blokady wymaga poprawnej starej kampanii.")
	var guard_clear_candidate = _new_campaign(36_122)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_GUARD_CLEAR, ERR_CANT_CREATE)
	_assert(manager.replace_campaign(guard_clear_candidate) == ERR_CANT_CREATE, "Awaria usunięcia blokady po dokładnym commicie nie może zostać zgłoszona jako sukces.")
	_assert(manager.last_replacement_outcome == SaveManagerScript.CampaignReplacementOutcome.IN_DOUBT, "Dokładny commit bez możliwości usunięcia blokady musi pozostać IN_DOUBT.")
	_assert(manager.last_replacement_failure_stage == SaveManagerScript.REPLACE_STEP_GUARD_CLEAR, "Awaria usunięcia blokady musi zachować dokładny etap diagnostyczny.")
	_assert(manager.take_last_replacement_committed_state() == null, "Niepotwierdzony commit nie może opublikować canonical handoff.")
	_assert(FileAccess.file_exists(ProjectSettings.globalize_path(REPLACEMENT_GUARD)), "Awaria usunięcia blokady musi pozostawić trwały marker.")
	var guarded_primary = ResourceLoader.load(PRIMARY, "", ResourceLoader.CACHE_MODE_IGNORE)
	var guarded_backup = ResourceLoader.load(BACKUP, "", ResourceLoader.CACHE_MODE_IGNORE)
	_assert(guarded_primary != null and guarded_backup != null and bool(manager.call("_same_campaign_snapshot_identity", guarded_primary, guarded_backup)), "Fixture guard-clear musi pozostawić dokładny nowy kanon w primary i backup.")
	_assert(manager.load_game() == null and not manager.has_save(), "Bieżący proces musi blokować odczyt dokładnego, lecz nieodblokowanego commitu.")

	var guard_clear_restarted = SaveManagerScript.new()
	root.add_child(guard_clear_restarted)
	guard_clear_restarted.configure_paths(PRIMARY, PENDING, BACKUP)
	_assert(guard_clear_restarted.last_replacement_outcome == SaveManagerScript.CampaignReplacementOutcome.IN_DOUBT, "Restart musi odtworzyć IN_DOUBT po awarii guard-clear.")
	_assert(guard_clear_restarted.load_game() == null and not guard_clear_restarted.has_save(), "Restart nie może ominąć blokady odczytu po awarii guard-clear.")
	_assert(guard_clear_restarted.save_game(_new_campaign(36_123)) == ERR_BUSY, "Autosave po restarcie nie może nadpisać namespace z aktywną blokadą.")
	var guard_clear_failed_retry = _new_campaign(36_124)
	guard_clear_restarted.fail_next_save_for_tests(ERR_CANT_CREATE)
	_assert(guard_clear_restarted.replace_campaign(guard_clear_failed_retry) == ERR_CANT_CREATE, "Nieudany retry po guard-clear musi zwrócić rzeczywisty błąd.")
	_assert(guard_clear_restarted.last_replacement_outcome == SaveManagerScript.CampaignReplacementOutcome.IN_DOUBT and FileAccess.file_exists(ProjectSettings.globalize_path(REPLACEMENT_GUARD)), "Nieudany retry po guard-clear musi zachować sticky IN_DOUBT i marker.")
	var guard_clear_resolved_retry = _new_campaign(36_125)
	_assert(guard_clear_restarted.replace_campaign(guard_clear_resolved_retry) == OK, "Kolejny udany retry musi bezpiecznie uzgodnić commit po guard-clear.")
	var guard_clear_handoff = guard_clear_restarted.take_last_replacement_committed_state()
	var guard_clear_loaded = guard_clear_restarted.load_game()
	_assert(guard_clear_handoff != null and guard_clear_loaded != null and bool(guard_clear_restarted.call("_same_campaign_snapshot_identity", guard_clear_handoff, guard_clear_loaded)), "Dopiero udany retry po guard-clear może opublikować dokładny reloadnięty kanon, nie surowy kandydat.")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(REPLACEMENT_GUARD)), "Udany retry po guard-clear musi usunąć trwałą blokadę.")
	_assert_only_valid_campaign_snapshot(guard_clear_restarted, guard_clear_resolved_retry, "retry po awarii guard-clear")
	root.remove_child(guard_clear_restarted)
	guard_clear_restarted.free()

	_cleanup(false)
	var single_copy_candidate = _new_campaign(36_131)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_BACKUP_WRITE, ERR_CANT_CREATE)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_FIRST_BACKUP_REPAIR, ERR_CANT_CREATE)
	manager.fail_next_campaign_replacement_for_tests(SaveManagerScript.REPLACE_STEP_COMMITTED_BACKUP_REPAIR, ERR_CANT_CREATE)
	_assert(manager.replace_campaign(single_copy_candidate) != OK, "Potrójna awaria backupu pierwszej kampanii nie może opublikować sukcesu z pojedynczym primary.")
	_assert(manager.last_replacement_outcome == SaveManagerScript.CampaignReplacementOutcome.IN_DOUBT, "Pojedynczy primary po utracie obu świadków musi pozostać IN_DOUBT.")
	_assert(manager.last_replacement_failure_stage == SaveManagerScript.REPLACE_STEP_GUARD_CLEAR, "Brak wymaganej redundancji musi zatrzymać finalną bramkę guard-clear.")
	_assert(manager.take_last_replacement_committed_state() == null, "Pojedynczy primary nie może opublikować canonical handoff.")
	_assert(FileAccess.file_exists(ProjectSettings.globalize_path(REPLACEMENT_GUARD)), "Brak backupu po potrójnej awarii musi pozostawić trwałą blokadę.")
	_assert(_valid_campaign_id(PRIMARY) == str(single_copy_candidate.campaign_id), "Fixture potrójnej awarii musi rzeczywiście pozostawić dokładny primary.")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(PENDING)) and not FileAccess.file_exists(ProjectSettings.globalize_path(BACKUP)), "Fixture potrójnej awarii musi dowieść, że poza primary nie pozostał żaden świadek.")
	_assert(manager.load_game() == null and not manager.has_save(), "Pojedynczy primary pod blokadą nie może stać się kampanią do kontynuacji.")
	var single_copy_retry = _new_campaign(36_132)
	_assert(manager.replace_campaign(single_copy_retry) == OK, "Jawny retry musi odbudować pełną redundancję po potrójnej awarii backupu.")
	var single_copy_handoff = manager.take_last_replacement_committed_state()
	var single_copy_loaded = manager.load_game()
	_assert(single_copy_handoff != null and single_copy_loaded != null and bool(manager.call("_same_campaign_snapshot_identity", single_copy_handoff, single_copy_loaded)), "Retry po potrójnej awarii musi opublikować dokładny reloadnięty kanon.")
	_assert(_valid_campaign_id(PRIMARY) == str(single_copy_retry.campaign_id) and _valid_campaign_id(BACKUP) == str(single_copy_retry.campaign_id), "Retry po potrójnej awarii musi zakończyć się dokładnym primary i backup.")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(PENDING)) and not FileAccess.file_exists(ProjectSettings.globalize_path(REPLACEMENT_GUARD)), "Retry po potrójnej awarii musi usunąć pending i trwałą blokadę.")


func _test_guarded_crash_snapshots() -> void:
	var crash_cases := [
		{"name": "guard-only", "old_paths": [], "new_paths": []},
		{"name": "old-plus-pending", "old_paths": [PRIMARY], "new_paths": [PENDING]},
		{"name": "old-plus-pending-backup", "old_paths": [PRIMARY], "new_paths": [PENDING, BACKUP]},
		{"name": "committed-all-copies", "old_paths": [], "new_paths": [PRIMARY, PENDING, BACKUP]},
		{"name": "first-singleton", "old_paths": [], "new_paths": [PRIMARY]},
		{"name": "first-quorum", "old_paths": [], "new_paths": [PENDING, BACKUP]},
	]
	for case_index in range(crash_cases.size()):
		_cleanup(false)
		var crash_case: Dictionary = crash_cases[case_index]
		var old_snapshot = _new_campaign(36_200 + case_index * 10)
		var new_snapshot = _new_campaign(36_201 + case_index * 10)
		old_snapshot.last_saved_at = "2026-08-27T11:%02d:00" % case_index
		new_snapshot.last_saved_at = "2026-08-27T12:%02d:00" % case_index
		for old_path in crash_case["old_paths"]:
			_assert(ResourceSaver.save(old_snapshot.duplicate(true), str(old_path)) == OK, "Crash fixture %s musi zapisać stary snapshot w %s." % [crash_case["name"], old_path])
		for new_path in crash_case["new_paths"]:
			_assert(ResourceSaver.save(new_snapshot.duplicate(true), str(new_path)) == OK, "Crash fixture %s musi zapisać nowy snapshot w %s." % [crash_case["name"], new_path])
		_assert(_write_replacement_guard_fixture(), "Crash fixture %s musi utworzyć trwały marker przed restartem." % crash_case["name"])

		var restarted = SaveManagerScript.new()
		root.add_child(restarted)
		restarted.configure_paths(PRIMARY, PENDING, BACKUP)
		_assert(restarted.last_replacement_outcome == SaveManagerScript.CampaignReplacementOutcome.IN_DOUBT, "Crash fixture %s musi po restarcie wejść w IN_DOUBT." % crash_case["name"])
		_assert(restarted.load_game() == null and not restarted.has_save(), "Crash fixture %s nie może po restarcie udostępnić żadnego snapshotu przez publiczny loader/Continue." % crash_case["name"])
		_assert(restarted.save_game(_new_campaign(36_202 + case_index * 10)) == ERR_BUSY, "Crash fixture %s musi blokować zwykły autosave do czasu retry." % crash_case["name"])
		var retry = _new_campaign(36_203 + case_index * 10)
		_assert(restarted.replace_campaign(retry) == OK, "Jawny retry NOWEJ GRY musi uzgodnić crash fixture %s." % crash_case["name"])
		_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(REPLACEMENT_GUARD)), "Retry crash fixture %s musi usunąć marker dopiero po pełnej weryfikacji." % crash_case["name"])
		var retry_handoff = restarted.take_last_replacement_committed_state()
		var retry_loaded = restarted.load_game()
		_assert(retry_handoff != null and retry_loaded != null and bool(restarted.call("_same_campaign_snapshot_identity", retry_handoff, retry_loaded)), "Retry crash fixture %s musi opublikować dokładny reloadnięty kanon." % crash_case["name"])
		_assert_only_valid_campaign_snapshot(restarted, retry, "retry crash fixture %s" % crash_case["name"])
		root.remove_child(restarted)
		restarted.free()


func _test_all_storage_state_combinations(manager) -> void:
	var template = _new_campaign(37_000)
	var paths := [PRIMARY, PENDING, BACKUP]
	for primary_status in range(3):
		for pending_status in range(3):
			for backup_status in range(3):
				_cleanup(false)
				var statuses := [primary_status, pending_status, backup_status]
				var combination := "%d%d%d" % [primary_status, pending_status, backup_status]
				for index in range(paths.size()):
					if statuses[index] == 0:
						continue
					var fixture = template.duplicate(true)
					fixture.campaign_id = "matrix-%s-%d" % [combination, index]
					fixture.created_at = "2026-08-27T09:%02d:00" % (primary_status * 9 + pending_status * 3 + backup_status)
					if statuses[index] == 1:
						fixture.format_revision = GameFormatScript.CAMPAIGN_FORMAT_REVISION - 1
					_assert(ResourceSaver.save(fixture, paths[index]) == OK, "Macierz %s musi utworzyć fixture w %s." % [combination, paths[index]])
				var replacement = template.duplicate(true)
				replacement.campaign_id = "matrix-new-%s" % combination
				replacement.created_at = "2026-08-27T10:%02d:00" % (primary_status * 9 + pending_status * 3 + backup_status)
				_assert(manager.replace_campaign(replacement) == OK, "Każda kombinacja missing/invalid/valid musi być zastępowalna; nie przeszła %s." % combination)
				_assert_only_valid_campaign_snapshot(manager, replacement, "macierz %s" % combination, false)
				_assert(_valid_campaign_id(PRIMARY) == str(replacement.campaign_id), "Macierz %s musi zakończyć się nowym primary." % combination)
				_assert(_valid_campaign_id(BACKUP) == str(replacement.campaign_id), "Macierz %s musi zakończyć się nowym backup." % combination)
				_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(PENDING)), "Macierz %s musi posprzątać pending." % combination)


func _new_campaign(campaign_seed: int):
	var state = GameStateScript.new()
	var setup_errors: PackedStringArray = state.setup_new_campaign(campaign_seed, DifficultyProfileScript.new())
	_assert(setup_errors.is_empty(), "Fixture nowej kampanii musi przejść inicjalizację mapy: %s" % "; ".join(setup_errors))
	return state


func _valid_campaign_id(path: String) -> String:
	if not ResourceLoader.exists(path):
		return ""
	var loaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or loaded.get_script() != GameStateScript:
		return ""
	var errors: PackedStringArray = loaded.load_validation_errors()
	return str(loaded.campaign_id) if errors.is_empty() else ""


func _assert_only_valid_campaign_snapshot(manager, expected, context: String, verify_expected_payload: bool = true) -> void:
	var canonical = manager.load_game()
	_assert(canonical != null and str(canonical.campaign_id) == str(expected.campaign_id), "%s musi ładować nową kampanię jako kanoniczny snapshot." % context)
	if canonical == null:
		return
	if verify_expected_payload:
		var expected_save_error := ResourceSaver.save(expected.duplicate(true), EXPECTED)
		_assert(expected_save_error == OK, "%s musi utworzyć niezależnie serializowany expected snapshot." % context)
		var expected_canonical = ResourceLoader.load(EXPECTED, "", ResourceLoader.CACHE_MODE_IGNORE) if expected_save_error == OK else null
		_assert(expected_canonical != null and expected_canonical.get_script() == GameStateScript, "%s musi ponownie odczytać expected snapshot." % context)
		if expected_canonical != null and expected_canonical.get_script() == GameStateScript:
			var expected_errors: PackedStringArray = expected_canonical.load_validation_errors()
			_assert(expected_errors.is_empty(), "%s expected snapshot musi przejść pełną walidację: %s" % [context, "; ".join(expected_errors)])
			var expected_mismatch := str(manager.call("_campaign_snapshot_mismatch_path", canonical, expected_canonical))
			_assert(expected_mismatch.is_empty(), "%s musi odpowiadać całemu niezależnie kanonizowanemu kandydatowi; różnica: %s." % [context, expected_mismatch])
		var expected_absolute := ProjectSettings.globalize_path(EXPECTED)
		if FileAccess.file_exists(expected_absolute):
			DirAccess.remove_absolute(expected_absolute)
	var valid_count := 0
	for path in [PRIMARY, PENDING, BACKUP]:
		if not ResourceLoader.exists(path):
			continue
		var loaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if loaded == null or loaded.get_script() != GameStateScript:
			_assert(false, "%s nie może pozostawić nieprawidłowego pliku w %s." % [context, path])
			continue
		var errors: PackedStringArray = loaded.load_validation_errors()
		if not errors.is_empty():
			_assert(false, "%s nie może pozostawić nieprawidłowego kandydata w %s: %s" % [context, path, "; ".join(errors)])
			continue
		valid_count += 1
		var mismatch := str(manager.call("_campaign_snapshot_mismatch_path", loaded, canonical))
		_assert(mismatch.is_empty(), "%s musi pozostawić dokładny nowy snapshot, nie tylko zgodne ID, w %s; różnica: %s." % [context, path, mismatch])
	_assert(valid_count > 0, "%s musi pozostawić co najmniej jeden poprawny kandydat nowej kampanii." % context)

func _cleanup(include_legacy: bool = true) -> void:
	var paths := [PRIMARY, PENDING, BACKUP, REPLACEMENT_GUARD, EXPECTED]
	if include_legacy:
		paths.append(LEGACY)
	for path in paths:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute): DirAccess.remove_absolute(absolute)

func _write_replacement_guard_fixture() -> bool:
	var guard_file := FileAccess.open(REPLACEMENT_GUARD, FileAccess.WRITE)
	if guard_file == null:
		return false
	guard_file.store_string(SaveManagerScript.REPLACEMENT_GUARD_CONTENT)
	guard_file.flush()
	guard_file.close()
	return FileAccess.file_exists(ProjectSettings.globalize_path(REPLACEMENT_GUARD))

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
