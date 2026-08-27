extends Node

## All campaign state is one clean-break format. Earlier campaign files are
## ignored rather than interpreted or deleted automatically.
const SAVE_PATH := "user://ostatni_pomost_campaign.tres"
const TEMP_SAVE_PATH := "user://ostatni_pomost_campaign.pending.tres"
const BACKUP_SAVE_PATH := "user://ostatni_pomost_campaign.backup.tres"
const REPLACEMENT_GUARD_PATH := "user://ostatni_pomost_campaign.tres.replace_guard"
const REPLACEMENT_GUARD_CONTENT := "ostatni_pomost_campaign_replacement_v1\n"
const GameStateScript := preload("res://scripts/data/GameState.gd")

const REPLACE_STEP_NORMALIZE_PRIMARY := "normalize_primary"
const REPLACE_STEP_PENDING_WRITE := "pending_write"
const REPLACE_STEP_BACKUP_WRITE := "backup_write"
const REPLACE_STEP_BACKUP_PAYLOAD_MISMATCH := "backup_payload_mismatch"
const REPLACE_STEP_PRIMARY_COMMIT := "primary_commit"
const REPLACE_STEP_PRIMARY_COMMIT_AFTER_WRITE := "primary_commit_after_write"
const REPLACE_STEP_PRIMARY_COMMIT_TARGET_LOSS := "primary_commit_target_loss"
const REPLACE_STEP_PRIMARY_COMMIT_INVALID_TARGET := "primary_commit_invalid_target"
const REPLACE_STEP_PRIMARY_COMMIT_FOREIGN_TARGET := "primary_commit_foreign_target"
const REPLACE_STEP_FIRST_PRIMARY_REPAIR := "first_primary_repair"
const REPLACE_STEP_FIRST_BACKUP_REPAIR := "first_backup_repair"
const REPLACE_STEP_FIRST_ROLLBACK_CLEANUP := "first_rollback_cleanup"
const REPLACE_STEP_RECONCILE_REWRITE_NEW := "reconcile_rewrite_new"
const REPLACE_STEP_RECONCILE_RESTORE_OLD := "reconcile_restore_old"
const REPLACE_STEP_RECONCILE_REMOVE_PRIMARY := "reconcile_remove_primary"
const REPLACE_STEP_GUARD_CREATE := "guard_create"
const REPLACE_STEP_GUARD_CLEAR := "guard_clear"
const REPLACE_STEP_COMMITTED_BACKUP_REPAIR := "committed_backup_repair"
const REPLACE_STEP_CLEANUP := "cleanup"

enum CampaignReplacementOutcome {
	NONE,
	PRESERVED,
	COMMITTED,
	IN_DOUBT,
}

var persistence_enabled: bool = true
var save_path: String = SAVE_PATH
var temp_save_path: String = TEMP_SAVE_PATH
var backup_save_path: String = BACKUP_SAVE_PATH
var replacement_guard_path: String = REPLACEMENT_GUARD_PATH
var _forced_save_error_for_tests: Error = OK
var _forced_replacement_failures_for_tests: Dictionary = {}
var _force_next_load_miss_for_tests: bool = false
var _replacement_in_progress: bool = false
var _replacement_guard_started: bool = false
var _replacement_guard_was_preexisting: bool = false
var _replacement_guard_previous_state
var _last_replacement_committed_state
var last_validation_errors: PackedStringArray = PackedStringArray()
var load_diagnostics: Dictionary = {}
var last_replacement_failure_stage: String = ""
var last_replacement_failure_details: PackedStringArray = PackedStringArray()
var last_replacement_outcome: int = CampaignReplacementOutcome.NONE

func save_game(state) -> Error:
	last_validation_errors = PackedStringArray()
	if state == null:
		return ERR_INVALID_PARAMETER
	if not persistence_enabled:
		return OK
	if has_unresolved_campaign_replacement():
		return ERR_BUSY
	if _forced_save_error_for_tests != OK:
		var forced_error := _forced_save_error_for_tests
		_forced_save_error_for_tests = OK
		return forced_error

	if not (state is Resource) or state.get_script() != GameStateScript:
		return _reject_save(PackedStringArray(["Korzeń zapisu nie jest dokładnym GameState."]))
	var load_errors: PackedStringArray = state.load_validation_errors()
	if not load_errors.is_empty():
		return _reject_save(load_errors)
	last_validation_errors = PackedStringArray()
	var save_candidate = state.duplicate(true)
	if save_candidate == null or save_candidate.get_script() != GameStateScript:
		return _reject_save(PackedStringArray(["Nie udało się utworzyć odłączonego kandydata zapisu."]))
	var save_timestamp := Time.get_datetime_string_from_system(true)
	save_candidate.last_saved_at = save_timestamp

	var temp_error := ResourceSaver.save(save_candidate, temp_save_path)
	if temp_error != OK:
		return temp_error
	if _load_valid_state(temp_save_path) == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_save_path))
		return ERR_INVALID_DATA

	var temp_absolute := ProjectSettings.globalize_path(temp_save_path)
	var save_absolute := ProjectSettings.globalize_path(save_path)
	var backup_absolute := ProjectSettings.globalize_path(backup_save_path)
	if FileAccess.file_exists(save_absolute):
		var primary_is_valid := _load_valid_state(save_path) != null
		if primary_is_valid:
			if FileAccess.file_exists(backup_absolute):
				var remove_backup_error := DirAccess.remove_absolute(backup_absolute)
				if remove_backup_error != OK:
					DirAccess.remove_absolute(temp_absolute)
					return remove_backup_error
			var rotate_error := DirAccess.rename_absolute(save_absolute, backup_absolute)
			if rotate_error != OK:
				DirAccess.remove_absolute(temp_absolute)
				return rotate_error
		else:
			var remove_temp_error := DirAccess.remove_absolute(temp_absolute)
			if remove_temp_error != OK:
				return remove_temp_error
			return _reject_save(PackedStringArray([
				"Istniejący zapis kampanii jest nieprawidłowy. Rozpocznij nową kampanię, aby go usunąć.",
			]))

	var replace_error := DirAccess.rename_absolute(temp_absolute, save_absolute)
	if replace_error != OK:
		return replace_error
	state.last_saved_at = save_timestamp
	return OK


func replace_campaign(state) -> Error:
	if _replacement_in_progress:
		# A nested caller must not clear the guard or diagnostics owned by the
		# transaction already in progress.
		return ERR_BUSY
	last_validation_errors = PackedStringArray()
	last_replacement_failure_stage = ""
	last_replacement_failure_details = PackedStringArray()
	_replacement_guard_was_preexisting = _campaign_replacement_guard_exists()
	_replacement_guard_started = _replacement_guard_was_preexisting
	_replacement_guard_previous_state = null
	last_replacement_outcome = (
		CampaignReplacementOutcome.IN_DOUBT
		if _replacement_guard_was_preexisting
		else CampaignReplacementOutcome.NONE
	)
	_last_replacement_committed_state = null
	load_diagnostics.clear()
	if state == null:
		return _finish_campaign_replacement(
			ERR_INVALID_PARAMETER,
			"candidate",
			PackedStringArray(["Kandydat nowej kampanii nie istnieje."])
		)
	if not persistence_enabled:
		_last_replacement_committed_state = state.duplicate(true) if state is Resource else state
		last_replacement_outcome = CampaignReplacementOutcome.COMMITTED
		return OK
	_replacement_in_progress = true

	if _forced_save_error_for_tests != OK:
		var forced_save_error := _forced_save_error_for_tests
		_forced_save_error_for_tests = OK
		return _finish_campaign_replacement(
			forced_save_error,
			"before_write",
			PackedStringArray(["Kontrolowany błąd zapisu przed rozpoczęciem transakcji."])
		)
	if not _configured_campaign_paths_are_distinct():
		return _finish_campaign_replacement(
			ERR_INVALID_PARAMETER,
			"paths",
			PackedStringArray(["Ścieżki primary, pending i backup muszą być różnymi plikami."])
		)
	if not (state is Resource) or state.get_script() != GameStateScript:
		return _finish_campaign_replacement(
			ERR_INVALID_PARAMETER,
			"candidate",
			PackedStringArray(["Korzeń zastępującej kampanii nie jest dokładnym GameState."])
		)

	var input_errors: PackedStringArray = state.load_validation_errors()
	if not input_errors.is_empty():
		last_validation_errors = input_errors.duplicate()
		return _finish_campaign_replacement(ERR_INVALID_DATA, "candidate_validation", input_errors)
	var replacement_candidate = state.duplicate(true)
	if replacement_candidate == null or replacement_candidate.get_script() != GameStateScript:
		return _finish_campaign_replacement(
			ERR_INVALID_DATA,
			"candidate_copy",
			PackedStringArray(["Nie udało się utworzyć odłączonego snapshotu nowej kampanii."])
		)
	replacement_candidate.last_saved_at = Time.get_datetime_string_from_system(true)
	var detached_errors: PackedStringArray = replacement_candidate.load_validation_errors()
	if not detached_errors.is_empty():
		last_validation_errors = detached_errors.duplicate()
		return _finish_campaign_replacement(ERR_INVALID_DATA, "candidate_validation", detached_errors)

	# FileAccess save-and-swap writes through a same-directory temporary file. On
	# Windows Godot closes it with ReplaceFileW, avoiding DirAccess.rename's
	# remove(destination) + MoveFileW window. This setting is intentionally kept
	# enabled for the rest of the process; the public API exposes no getter that
	# would let us restore an earlier global value safely.
	OS.set_use_file_access_save_and_swap(true)

	var previous_info := _first_valid_campaign_candidate()
	var previous_state = previous_info.get("state")
	var previous_path := str(previous_info.get("path", ""))
	if previous_state != null and str(previous_state.campaign_id) == str(replacement_candidate.campaign_id):
		return _finish_campaign_replacement(
			ERR_INVALID_PARAMETER,
			"candidate_identity",
			PackedStringArray(["Nowa kampania musi mieć inną tożsamość niż zastępowana kampania."])
		)

	if previous_state == null:
		var first_guard_error := _begin_campaign_replacement_guard(null)
		if first_guard_error != OK:
			return _finish_campaign_replacement(
				first_guard_error,
				REPLACE_STEP_GUARD_CREATE,
				PackedStringArray(["Nie udało się trwale zablokować odczytu na czas zastąpienia kampanii."])
			)
		return _replace_first_campaign(replacement_candidate, state)

	if previous_path != save_path:
		var normalize_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_NORMALIZE_PRIMARY)
		if normalize_failpoint != OK:
			return _finish_campaign_replacement(
				normalize_failpoint,
				REPLACE_STEP_NORMALIZE_PRIMARY,
				PackedStringArray(["Kontrolowany błąd przed normalizacją poprzedniej kampanii."])
			)
		var normalize_error := _write_and_validate_snapshot(previous_state, save_path)
		if normalize_error != OK:
			return _finish_campaign_replacement(
				normalize_error,
				REPLACE_STEP_NORMALIZE_PRIMARY,
				PackedStringArray(["Nie udało się znormalizować poprzedniej kampanii do primary."])
			)

	var guard_error := _begin_campaign_replacement_guard(previous_state)
	if guard_error != OK:
		return _finish_campaign_replacement(
			guard_error,
			REPLACE_STEP_GUARD_CREATE,
			PackedStringArray(["Nie udało się trwale zablokować odczytu na czas zastąpienia kampanii."])
		)

	var pending_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_PENDING_WRITE)
	if pending_failpoint != OK:
		return _finish_campaign_replacement(
			pending_failpoint,
			REPLACE_STEP_PENDING_WRITE,
			PackedStringArray(["Kontrolowany błąd przed zapisem pending."])
		)
	var pending_error := _write_and_validate_snapshot(replacement_candidate, temp_save_path, false)
	if pending_error != OK:
		return _finish_campaign_replacement(
			pending_error,
			REPLACE_STEP_PENDING_WRITE,
			PackedStringArray(["Nie udało się zapisać i zwalidować pending nowej kampanii."])
		)
	var serialized_candidate = _load_valid_state(temp_save_path)
	if serialized_candidate == null:
		return _finish_campaign_replacement(
			ERR_INVALID_DATA,
			REPLACE_STEP_PENDING_WRITE,
			PackedStringArray(["Zwalidowany pending nie jest dostępny do kanonizacji snapshotu."])
		)

	var backup_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_BACKUP_WRITE)
	if backup_failpoint != OK:
		return _finish_campaign_replacement(
			backup_failpoint,
			REPLACE_STEP_BACKUP_WRITE,
			PackedStringArray(["Kontrolowany błąd przed zapisem backup."])
		)
	var backup_snapshot = replacement_candidate
	var mismatch_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_BACKUP_PAYLOAD_MISMATCH)
	if mismatch_failpoint != OK:
		backup_snapshot = _mismatched_campaign_snapshot_for_tests(replacement_candidate)
	var backup_error := _write_and_validate_snapshot(backup_snapshot, backup_save_path, false)
	if backup_error != OK:
		return _finish_campaign_replacement(
			backup_error,
			REPLACE_STEP_BACKUP_WRITE,
			PackedStringArray(["Nie udało się zapisać i zwalidować backup nowej kampanii."])
		)
	var independently_serialized_backup = _load_valid_state(backup_save_path)
	if independently_serialized_backup == null:
		return _finish_campaign_replacement(
			ERR_INVALID_DATA,
			REPLACE_STEP_BACKUP_WRITE,
			PackedStringArray(["Zwalidowany backup nie jest dostępny do porównania kanonicznego."])
		)
	var independent_mismatch := _campaign_snapshot_mismatch_path(serialized_candidate, independently_serialized_backup)
	if not independent_mismatch.is_empty():
		return _finish_campaign_replacement(
			ERR_INVALID_DATA,
			REPLACE_STEP_BACKUP_WRITE,
			PackedStringArray([
				"Dwa niezależne zapisy nowej kampanii nie dały identycznego stanu: %s." % independent_mismatch,
			])
		)

	var commit_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_PRIMARY_COMMIT)
	if commit_failpoint != OK:
		return _finish_campaign_replacement(
			commit_failpoint,
			REPLACE_STEP_PRIMARY_COMMIT,
			PackedStringArray(["Kontrolowany błąd przed finalnym commitem primary."])
		)
	var commit_error := OK
	var target_loss_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_PRIMARY_COMMIT_TARGET_LOSS)
	if target_loss_failpoint != OK:
		# Test-only model of a platform reporting an error after the old target has
		# stopped being visible but before the caller can observe a new primary.
		var primary_absolute := ProjectSettings.globalize_path(save_path)
		if FileAccess.file_exists(primary_absolute):
			DirAccess.remove_absolute(primary_absolute)
		commit_error = target_loss_failpoint
	else:
		var invalid_target_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_PRIMARY_COMMIT_INVALID_TARGET)
		var foreign_target_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_PRIMARY_COMMIT_FOREIGN_TARGET)
		if invalid_target_failpoint != OK:
			_write_campaign_commit_target_for_tests(serialized_candidate, true)
			commit_error = invalid_target_failpoint
		elif foreign_target_failpoint != OK:
			_write_campaign_commit_target_for_tests(serialized_candidate, false)
			commit_error = foreign_target_failpoint
		else:
			commit_error = _write_and_validate_snapshot(serialized_candidate, save_path)
			var after_write_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_PRIMARY_COMMIT_AFTER_WRITE)
			if after_write_failpoint != OK:
				# Test-only model of a close-time diagnostic reported after the exact new
				# primary has already become visible.
				commit_error = after_write_failpoint
	if commit_error != OK:
		var resolution := _resolve_ambiguous_campaign_commit(serialized_candidate, previous_state, commit_error)
		if bool(resolution.get("committed", false)):
			state.last_saved_at = str(serialized_candidate.last_saved_at)
			if bool(resolution.get("primary_is_new", false)):
				_complete_committed_campaign_best_effort(serialized_candidate)
			return _finish_campaign_replacement(OK, "", PackedStringArray(), serialized_candidate)
		return _finish_campaign_replacement(
			int(resolution.get("error", commit_error)),
			REPLACE_STEP_PRIMARY_COMMIT,
			resolution.get("details", PackedStringArray(["Finalny commit nie zmienił primary na nową kampanię."])),
			null,
			CampaignReplacementOutcome.IN_DOUBT if bool(resolution.get("in_doubt", false)) else CampaignReplacementOutcome.PRESERVED
		)

	# From this point every valid candidate belongs to the new campaign. Cleanup
	# cannot be reported as a failed replacement because the old primary is gone.
	state.last_saved_at = str(serialized_candidate.last_saved_at)
	_complete_committed_campaign_best_effort(serialized_candidate)
	return _finish_campaign_replacement(OK, "", PackedStringArray(), serialized_candidate)

func load_game():
	load_diagnostics.clear()
	if has_unresolved_campaign_replacement():
		load_diagnostics[replacement_guard_path] = PackedStringArray([
			"Niedokończone zastąpienie kampanii wymaga ponowienia NOWEJ GRY przed odczytem.",
		])
		return null
	if _force_next_load_miss_for_tests:
		_force_next_load_miss_for_tests = false
		return null
	var loaded = _load_valid_state(save_path)
	if loaded != null:
		return loaded
	loaded = _load_valid_state(temp_save_path)
	if loaded != null:
		return loaded
	return _load_valid_state(backup_save_path)

func has_save() -> bool:
	# Continue is available only for a complete current-format campaign.
	load_diagnostics.clear()
	if has_unresolved_campaign_replacement():
		return false
	return (
		_load_valid_state(save_path) != null
		or _load_valid_state(temp_save_path) != null
		or _load_valid_state(backup_save_path) != null
	)

func has_any_save_file() -> bool:
	for path in [save_path, temp_save_path, backup_save_path, replacement_guard_path]:
		if FileAccess.file_exists(ProjectSettings.globalize_path(path)):
			return true
	return false


func has_unresolved_campaign_replacement() -> bool:
	var guard_exists := _campaign_replacement_guard_exists()
	if guard_exists:
		last_replacement_outcome = CampaignReplacementOutcome.IN_DOUBT
	return guard_exists

func delete_campaign_storage() -> Error:
	# The durable guard is removed last. A partial deletion therefore remains
	# fail-closed instead of exposing an ambiguous candidate through Continue.
	for path in [save_path, temp_save_path, backup_save_path, replacement_guard_path]:
		var absolute_path := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(absolute_path):
			continue
		var remove_error := DirAccess.remove_absolute(absolute_path)
		if remove_error != OK:
			return remove_error
	last_replacement_outcome = CampaignReplacementOutcome.NONE
	return OK


func set_persistence_enabled(enabled: bool) -> void:
	persistence_enabled = enabled

func configure_paths(primary: String, pending: String, backup: String) -> void:
	if primary.is_empty() or pending.is_empty() or backup.is_empty():
		return
	save_path = primary
	temp_save_path = pending
	backup_save_path = backup
	replacement_guard_path = "%s.replace_guard" % primary
	last_replacement_outcome = (
		CampaignReplacementOutcome.IN_DOUBT
		if _campaign_replacement_guard_exists()
		else CampaignReplacementOutcome.NONE
	)

func reset_paths() -> void:
	save_path = SAVE_PATH
	temp_save_path = TEMP_SAVE_PATH
	backup_save_path = BACKUP_SAVE_PATH
	replacement_guard_path = REPLACEMENT_GUARD_PATH
	_forced_save_error_for_tests = OK
	_forced_replacement_failures_for_tests.clear()
	_force_next_load_miss_for_tests = false
	_replacement_in_progress = false
	_replacement_guard_started = false
	_replacement_guard_was_preexisting = false
	_replacement_guard_previous_state = null
	_last_replacement_committed_state = null
	last_validation_errors = PackedStringArray()
	load_diagnostics.clear()
	last_replacement_failure_stage = ""
	last_replacement_failure_details = PackedStringArray()
	last_replacement_outcome = CampaignReplacementOutcome.NONE


func fail_next_save_for_tests(error: Error = ERR_CANT_CREATE) -> void:
	_forced_save_error_for_tests = error if error != OK else ERR_CANT_CREATE


func fail_next_campaign_replacement_for_tests(step: String, error: Error = ERR_CANT_CREATE) -> void:
	_forced_replacement_failures_for_tests[step] = error if error != OK else ERR_CANT_CREATE


func miss_next_load_for_tests() -> void:
	_force_next_load_miss_for_tests = true


func take_last_replacement_committed_state():
	var committed_state = _last_replacement_committed_state
	_last_replacement_committed_state = null
	return committed_state.duplicate(true) if committed_state is Resource else committed_state

func _load_valid_state(path: String):
	if not ResourceLoader.exists(path):
		return null
	var loaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (loaded is Resource) or loaded.get_script() != GameStateScript:
		_record_load_rejection(path, PackedStringArray(["Korzeń kandydata nie jest dokładnym GameState."]))
		return null
	var load_errors: PackedStringArray = loaded.load_validation_errors()
	if not load_errors.is_empty():
		_record_load_rejection(path, load_errors)
		return null
	return loaded


func _first_valid_campaign_candidate() -> Dictionary:
	for path in [save_path, temp_save_path, backup_save_path]:
		var loaded = _load_valid_state(path)
		if loaded != null:
			return {"path": path, "state": loaded}
	return {}


func _write_and_validate_snapshot(snapshot, path: String, require_exact_payload: bool = true, accept_observed_after_error: bool = false) -> Error:
	var write_error := ResourceSaver.save(snapshot, path)
	var reloaded = _load_valid_state(path)
	var observed_expected_snapshot := (
		_same_campaign_snapshot_identity(reloaded, snapshot)
		if require_exact_payload
		else _same_campaign_snapshot_metadata(reloaded, snapshot)
	)
	if observed_expected_snapshot and (write_error == OK or accept_observed_after_error):
		# ResourceSaver may not be able to propagate a close-time save-and-swap
		# diagnostic. The persisted, fully validated identity is authoritative.
		return OK
	if reloaded != null and not observed_expected_snapshot:
		push_warning("Zapisany snapshot %s ma inną zawartość niż kandydat: %s." % [path, _campaign_snapshot_mismatch_path(reloaded, snapshot)])
	if write_error != OK:
		return write_error
	return ERR_FILE_CANT_WRITE


func _replace_first_campaign(replacement_candidate, input_state) -> Error:
	# There is no previous valid campaign to preserve. The first visible primary
	# is provisional until an independent serialization converges with it. If the
	# two copies disagree, pending becomes a third witness and the exact 2/3
	# majority is repaired into primary and backup before success is published.
	var precommit_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_PRIMARY_COMMIT)
	if precommit_failpoint != OK:
		return _finish_campaign_replacement(
			precommit_failpoint,
			REPLACE_STEP_PRIMARY_COMMIT,
			PackedStringArray(["Kontrolowany błąd przed zatwierdzeniem pierwszego primary."])
		)

	var primary_reported_error := _write_and_validate_snapshot(replacement_candidate, save_path, false, true)
	var target_loss_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_PRIMARY_COMMIT_TARGET_LOSS)
	var invalid_target_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_PRIMARY_COMMIT_INVALID_TARGET)
	var foreign_target_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_PRIMARY_COMMIT_FOREIGN_TARGET)
	var after_write_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_PRIMARY_COMMIT_AFTER_WRITE)
	if target_loss_failpoint != OK:
		var primary_absolute := ProjectSettings.globalize_path(save_path)
		if FileAccess.file_exists(primary_absolute):
			DirAccess.remove_absolute(primary_absolute)
		primary_reported_error = target_loss_failpoint
	elif invalid_target_failpoint != OK:
		_write_campaign_commit_target_for_tests(replacement_candidate, true)
		primary_reported_error = invalid_target_failpoint
	elif foreign_target_failpoint != OK:
		_write_campaign_commit_target_for_tests(replacement_candidate, false)
		primary_reported_error = foreign_target_failpoint
	elif after_write_failpoint != OK:
		primary_reported_error = after_write_failpoint
	var primary_candidate = _load_snapshot_with_matching_metadata(save_path, replacement_candidate)

	var backup_reported_error := OK
	var backup_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_BACKUP_WRITE)
	if backup_failpoint != OK:
		backup_reported_error = backup_failpoint
	else:
		var backup_snapshot = replacement_candidate
		var mismatch_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_BACKUP_PAYLOAD_MISMATCH)
		if mismatch_failpoint != OK:
			backup_snapshot = _mismatched_campaign_snapshot_for_tests(replacement_candidate)
		backup_reported_error = _write_and_validate_snapshot(backup_snapshot, backup_save_path, false, true)
	var backup_candidate = _load_snapshot_with_matching_metadata(backup_save_path, replacement_candidate)

	if _same_campaign_snapshot_identity(primary_candidate, backup_candidate):
		return _complete_first_campaign_commit(primary_candidate, input_state)

	var pending_reported_error := OK
	var pending_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_PENDING_WRITE)
	if pending_failpoint != OK:
		pending_reported_error = pending_failpoint
	else:
		pending_reported_error = _write_and_validate_snapshot(replacement_candidate, temp_save_path, false, true)
	var pending_candidate = _load_snapshot_with_matching_metadata(temp_save_path, replacement_candidate)
	var canonical_candidate = _campaign_snapshot_majority(primary_candidate, backup_candidate, pending_candidate)
	if canonical_candidate == null:
		var cleanup_succeeded := _remove_campaign_namespace_and_verify_no_valid_campaign()
		var no_majority_details := PackedStringArray([
			"Niezależne zapisy pierwszej kampanii nie wyznaczyły identycznej większości 2/3.",
			"Namespace po wycofaniu nie zawiera poprawnej kampanii: %s." % str(cleanup_succeeded),
		])
		return _finish_campaign_replacement(
			_first_non_ok_error([primary_reported_error, backup_reported_error, pending_reported_error], ERR_INVALID_DATA),
			REPLACE_STEP_PRIMARY_COMMIT,
			no_majority_details,
			null,
			CampaignReplacementOutcome.PRESERVED if cleanup_succeeded else CampaignReplacementOutcome.IN_DOUBT
		)

	var primary_repair_error := OK
	if not _same_campaign_snapshot_identity(primary_candidate, canonical_candidate):
		primary_repair_error = _consume_campaign_replacement_failpoint(REPLACE_STEP_FIRST_PRIMARY_REPAIR)
		if primary_repair_error == OK:
			primary_repair_error = _write_and_validate_snapshot(canonical_candidate, save_path)
		primary_candidate = _load_snapshot_with_matching_metadata(save_path, canonical_candidate)
	var backup_repair_error := OK
	if not _same_campaign_snapshot_identity(backup_candidate, canonical_candidate):
		backup_repair_error = _consume_campaign_replacement_failpoint(REPLACE_STEP_FIRST_BACKUP_REPAIR)
		if backup_repair_error == OK:
			backup_repair_error = _write_and_validate_snapshot(canonical_candidate, backup_save_path)
		backup_candidate = _load_snapshot_with_matching_metadata(backup_save_path, canonical_candidate)
	if (
		primary_repair_error != OK
		or backup_repair_error != OK
		or not _same_campaign_snapshot_identity(primary_candidate, canonical_candidate)
		or not _same_campaign_snapshot_identity(backup_candidate, canonical_candidate)
	):
		var primary_is_exact := _same_campaign_snapshot_identity(primary_candidate, canonical_candidate)
		var pending_is_exact := _same_campaign_snapshot_identity(pending_candidate, canonical_candidate)
		var backup_is_exact := _same_campaign_snapshot_identity(backup_candidate, canonical_candidate)
		if primary_is_exact and (pending_is_exact or backup_is_exact):
			# A one-shot repair error can still leave a fully authoritative primary
			# plus an exact witness. Best-effort completion retries backup repair and
			# only then removes pending.
			return _complete_first_campaign_commit(canonical_candidate, input_state)
		var primary_absolute := ProjectSettings.globalize_path(save_path)
		if not FileAccess.file_exists(primary_absolute) and pending_is_exact and backup_is_exact:
			# The same recovery representation used after an ambiguous replacement
			# commit is already authoritative: two exact copies and no primary that
			# could shadow them. Keep both witnesses intact.
			input_state.last_saved_at = str(canonical_candidate.last_saved_at)
			return _finish_campaign_replacement(OK, "", PackedStringArray(), canonical_candidate)
		var cleanup_succeeded := _remove_campaign_namespace_and_verify_no_valid_campaign()
		var repair_details := PackedStringArray([
			"Nie udało się naprawić primary i backup do większościowego snapshotu pierwszej kampanii.",
			"Namespace po wycofaniu nie zawiera poprawnej kampanii: %s." % str(cleanup_succeeded),
		])
		return _finish_campaign_replacement(
			_first_non_ok_error([primary_repair_error, backup_repair_error], ERR_FILE_CANT_WRITE),
			REPLACE_STEP_PRIMARY_COMMIT,
			repair_details,
			null,
			CampaignReplacementOutcome.PRESERVED if cleanup_succeeded else CampaignReplacementOutcome.IN_DOUBT
		)
	return _complete_first_campaign_commit(canonical_candidate, input_state)


func _complete_first_campaign_commit(canonical_candidate, input_state) -> Error:
	input_state.last_saved_at = str(canonical_candidate.last_saved_at)
	_complete_committed_campaign_best_effort(canonical_candidate)
	return _finish_campaign_replacement(OK, "", PackedStringArray(), canonical_candidate)


func _load_snapshot_with_matching_metadata(path: String, expected):
	var loaded = _load_valid_state(path)
	return loaded if _same_campaign_snapshot_metadata(loaded, expected) else null


func _campaign_snapshot_majority(first, second, third):
	if _same_campaign_snapshot_identity(first, second):
		return first
	if _same_campaign_snapshot_identity(first, third):
		return first
	if _same_campaign_snapshot_identity(second, third):
		return second
	return null


func _first_non_ok_error(errors: Array, fallback: Error) -> Error:
	for candidate_error in errors:
		if int(candidate_error) != OK:
			return int(candidate_error)
	return fallback


func _remove_campaign_namespace_and_verify_no_valid_campaign() -> bool:
	if _consume_campaign_replacement_failpoint(REPLACE_STEP_FIRST_ROLLBACK_CLEANUP) != OK:
		return _first_valid_campaign_candidate().is_empty()
	for path in [save_path, temp_save_path, backup_save_path]:
		var absolute_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute_path):
			var remove_error := DirAccess.remove_absolute(absolute_path)
			if remove_error != OK:
				push_warning("Wycofanie pierwszej kampanii nie usunęło %s: %s." % [path, error_string(remove_error)])
	return _first_valid_campaign_candidate().is_empty()


func _resolve_ambiguous_campaign_commit(new_snapshot, previous_snapshot, reported_error: Error) -> Dictionary:
	var primary_after_error = _load_valid_state(save_path)
	if _same_campaign_snapshot_identity(primary_after_error, new_snapshot):
		return {"committed": true, "primary_is_new": true, "error": OK}
	if _same_campaign_snapshot_identity(primary_after_error, previous_snapshot):
		return {
			"committed": false,
			"primary_is_new": false,
			"error": reported_error,
			"details": PackedStringArray(["Finalny commit pozostawił poprzednią kampanię w primary."]),
		}

	var pending_after_error = _load_valid_state(temp_save_path)
	var backup_after_error = _load_valid_state(backup_save_path)
	var has_exact_recovery_pair := (
		_same_campaign_snapshot_identity(pending_after_error, new_snapshot)
		and _same_campaign_snapshot_identity(backup_after_error, new_snapshot)
	)
	var primary_absolute := ProjectSettings.globalize_path(save_path)
	if primary_after_error == null and not FileAccess.file_exists(primary_absolute) and has_exact_recovery_pair:
		push_warning("Commit primary zakończył się niejednoznacznie; nowa kampania pozostaje zatwierdzona w dwóch dokładnych kopiach recovery.")
		return {"committed": true, "primary_is_new": false, "error": OK}

	# An invalid or unrelated visible target cannot be reported as a failed
	# replacement: the caller would then believe that the previous campaign is
	# still authoritative. First complete the new commit, then try a full restore
	# of the old snapshot. Each attempt is verified after a cache-bypassing load.
	var rewrite_new_error := _consume_campaign_replacement_failpoint(REPLACE_STEP_RECONCILE_REWRITE_NEW)
	if rewrite_new_error == OK:
		rewrite_new_error = _write_and_validate_snapshot(new_snapshot, save_path)
	primary_after_error = _load_valid_state(save_path)
	if rewrite_new_error == OK or _same_campaign_snapshot_identity(primary_after_error, new_snapshot):
		push_warning("Niejednoznaczny target primary został pojednany do dokładnego snapshotu nowej kampanii.")
		return {"committed": true, "primary_is_new": true, "error": OK}
	if _same_campaign_snapshot_identity(primary_after_error, previous_snapshot):
		return {
			"committed": false,
			"primary_is_new": false,
			"error": reported_error,
			"details": PackedStringArray(["Ponowienie commitu pozostawiło dokładną poprzednią kampanię."]),
		}

	var restore_old_error := _consume_campaign_replacement_failpoint(REPLACE_STEP_RECONCILE_RESTORE_OLD)
	if restore_old_error == OK:
		restore_old_error = _write_and_validate_snapshot(previous_snapshot, save_path)
	primary_after_error = _load_valid_state(save_path)
	if restore_old_error == OK or _same_campaign_snapshot_identity(primary_after_error, previous_snapshot):
		return {
			"committed": false,
			"primary_is_new": false,
			"error": reported_error,
			"details": PackedStringArray(["Nie udało się zatwierdzić nowej kampanii; przywrócono poprzednią kampanię."]),
		}
	if _same_campaign_snapshot_identity(primary_after_error, new_snapshot):
		return {"committed": true, "primary_is_new": true, "error": OK}

	# If both exact writes were reported as failures but the two sealed recovery
	# copies remain exact, removing an unusable/foreign target restores the same
	# deterministic P -> T -> B read order as a platform-level target-loss commit.
	if has_exact_recovery_pair:
		var remove_error := _consume_campaign_replacement_failpoint(REPLACE_STEP_RECONCILE_REMOVE_PRIMARY)
		if FileAccess.file_exists(primary_absolute):
			if remove_error == OK:
				remove_error = DirAccess.remove_absolute(primary_absolute)
		if remove_error == OK and not FileAccess.file_exists(primary_absolute):
			push_warning("Niejednoznaczny target primary usunięto; nowa kampania pozostaje zatwierdzona w dwóch dokładnych kopiach recovery.")
			return {"committed": true, "primary_is_new": false, "error": OK}

	# A normal failure is truthful only when the observable loader result is the
	# exact previous campaign. A normal success is truthful only for an exact new
	# primary, or for an exact recovery pair with no visible primary. Anything
	# else is explicitly in doubt: callers must not promise that OLD survived.
	primary_after_error = _load_valid_state(save_path)
	if _same_campaign_snapshot_identity(primary_after_error, new_snapshot):
		return {"committed": true, "primary_is_new": true, "error": OK}
	if _same_campaign_snapshot_identity(primary_after_error, previous_snapshot):
		return {
			"committed": false,
			"primary_is_new": false,
			"error": reported_error if reported_error != OK else ERR_FILE_CANT_WRITE,
			"details": PackedStringArray(["Pojednanie zakończyło się dokładną poprzednią kampanią w primary."]),
		}
	if not FileAccess.file_exists(primary_absolute) and has_exact_recovery_pair:
		return {"committed": true, "primary_is_new": false, "error": OK}
	return {
		"committed": false,
		"primary_is_new": false,
		"in_doubt": true,
		"error": reported_error if reported_error != OK else ERR_FILE_CANT_WRITE,
		"details": PackedStringArray([
			"Nie udało się potwierdzić primary jako dokładnej nowej ani dokładnej poprzedniej kampanii; wynik pozostaje niejednoznaczny.",
			"Ponowienie nowego snapshotu: %s; odtworzenie starego: %s." % [error_string(rewrite_new_error), error_string(restore_old_error)],
		]),
	}


func _mismatched_campaign_snapshot_for_tests(snapshot):
	var mismatched = snapshot.duplicate(true)
	if mismatched != null and mismatched.resources != null:
		mismatched.resources.add_amount("food", 1)
	return mismatched


func _write_campaign_commit_target_for_tests(snapshot, invalid: bool) -> void:
	var target = snapshot.duplicate(true)
	if invalid:
		target.format_revision -= 1
	else:
		target.campaign_id = "%s-foreign" % str(target.campaign_id)
		target.resources.add_amount("food", 1)
	ResourceSaver.save(target, save_path)


func _same_campaign_snapshot_identity(left, right) -> bool:
	return (
		_same_campaign_snapshot_metadata(left, right)
		and _persisted_value_mismatch(left, right, {}, "GameState").is_empty()
	)


func _same_campaign_snapshot_metadata(left, right) -> bool:
	return (
		left != null
		and right != null
		and str(left.campaign_id) == str(right.campaign_id)
		and str(left.created_at) == str(right.created_at)
		and str(left.last_saved_at) == str(right.last_saved_at)
	)


func _campaign_snapshot_mismatch_path(left, right) -> String:
	return _persisted_value_mismatch(left, right, {}, "GameState")


func _persisted_value_mismatch(left, right, visited_pairs: Dictionary, path: String) -> String:
	var left_type := typeof(left)
	if left_type != typeof(right):
		return "%s (różne typy)" % path
	if left_type == TYPE_OBJECT:
		if left == null or right == null:
			return "" if left == right else "%s (null)" % path
		if not (left is Resource) or not (right is Resource):
			return "" if left == right else "%s (obiekt)" % path
		if left.get_script() != right.get_script():
			return "%s (skrypt)" % path
		var pair_key := "%d:%d" % [left.get_instance_id(), right.get_instance_id()]
		if visited_pairs.has(pair_key):
			return ""
		visited_pairs[pair_key] = true
		var left_properties := _stored_property_names(left)
		var right_properties := _stored_property_names(right)
		if left_properties != right_properties:
			return "%s (właściwości %s != %s)" % [path, left_properties, right_properties]
		for property_name in left_properties:
			var mismatch := _persisted_value_mismatch(left.get(property_name), right.get(property_name), visited_pairs, "%s.%s" % [path, property_name])
			if not mismatch.is_empty():
				return mismatch
		return ""
	if left_type == TYPE_ARRAY:
		if left.size() != right.size():
			return "%s (rozmiar tablicy)" % path
		for index in range(left.size()):
			var mismatch := _persisted_value_mismatch(left[index], right[index], visited_pairs, "%s[%d]" % [path, index])
			if not mismatch.is_empty():
				return mismatch
		return ""
	if left_type == TYPE_DICTIONARY:
		if left.size() != right.size():
			return "%s (rozmiar słownika)" % path
		for key in left.keys():
			if not right.has(key):
				return "%s[%s] (brak klucza)" % [path, str(key)]
			var mismatch := _persisted_value_mismatch(left[key], right[key], visited_pairs, "%s[%s]" % [path, str(key)])
			if not mismatch.is_empty():
				return mismatch
		return ""
	return "" if left == right else "%s (wartość)" % path


func _stored_property_names(resource: Resource) -> PackedStringArray:
	var names := PackedStringArray()
	for property in resource.get_property_list():
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var property_name := str(property.get("name", ""))
		if property_name.is_empty() or property_name == "script":
			continue
		names.append(property_name)
	names.sort()
	return names


func _complete_committed_campaign_best_effort(snapshot) -> void:
	var backup_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_COMMITTED_BACKUP_REPAIR)
	if backup_failpoint == OK:
		var existing_backup = _load_valid_state(backup_save_path)
		if not _same_campaign_snapshot_identity(existing_backup, snapshot):
			var backup_error := _write_and_validate_snapshot(snapshot, backup_save_path)
			if backup_error != OK:
				push_warning("Nowa kampania jest zatwierdzona w primary, ale nie udało się odtworzyć backup: %s." % error_string(backup_error))
	else:
		push_warning("Nowa kampania jest zatwierdzona w primary; kontrolowany błąd pominął odtworzenie backup.")
	var cleanup_failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_CLEANUP)
	if cleanup_failpoint != OK:
		push_warning("Nowa kampania jest zatwierdzona; kontrolowany błąd pominął sprzątanie pending.")
		return
	var pending_absolute := ProjectSettings.globalize_path(temp_save_path)
	if not FileAccess.file_exists(pending_absolute):
		return
	var cleanup_error := DirAccess.remove_absolute(pending_absolute)
	if cleanup_error != OK:
		push_warning("Nowa kampania jest zatwierdzona, ale sprzątanie pending zostanie ponowione później: %s." % error_string(cleanup_error))


func _begin_campaign_replacement_guard(previous_state) -> Error:
	_replacement_guard_previous_state = previous_state.duplicate(true) if previous_state is Resource else previous_state
	if _campaign_replacement_guard_exists():
		_replacement_guard_started = true
		return OK
	var failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_GUARD_CREATE)
	if failpoint != OK:
		return failpoint
	var guard_file := FileAccess.open(replacement_guard_path, FileAccess.WRITE)
	if guard_file == null:
		return FileAccess.get_open_error()
	guard_file.store_string(REPLACEMENT_GUARD_CONTENT)
	guard_file.flush()
	guard_file.close()
	_replacement_guard_started = _campaign_replacement_guard_exists()
	return OK if _replacement_guard_started else ERR_FILE_CANT_WRITE


func _campaign_replacement_guard_exists() -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(replacement_guard_path))


func _clear_campaign_replacement_guard() -> Error:
	var failpoint := _consume_campaign_replacement_failpoint(REPLACE_STEP_GUARD_CLEAR)
	if failpoint != OK:
		return failpoint
	var guard_absolute := ProjectSettings.globalize_path(replacement_guard_path)
	if not FileAccess.file_exists(guard_absolute):
		return OK
	var remove_error := DirAccess.remove_absolute(guard_absolute)
	if remove_error != OK:
		return remove_error
	return OK if not FileAccess.file_exists(guard_absolute) else ERR_FILE_CANT_WRITE


func _restore_preserved_campaign_namespace(previous_state) -> bool:
	if previous_state == null:
		# Invalid or legacy-looking files are not campaign candidates and are not
		# silently reinterpreted or deleted. First-campaign rollback already removes
		# any valid provisional snapshots it created; here we only prove that none is
		# observable before clearing the durable guard.
		return _first_valid_campaign_candidate().is_empty()
	var primary = _load_valid_state(save_path)
	if not _same_campaign_snapshot_identity(primary, previous_state):
		if _write_and_validate_snapshot(previous_state, save_path) != OK:
			return false
	var backup = _load_valid_state(backup_save_path)
	if not _same_campaign_snapshot_identity(backup, previous_state):
		if _write_and_validate_snapshot(previous_state, backup_save_path) != OK:
			return false
	var pending_absolute := ProjectSettings.globalize_path(temp_save_path)
	if FileAccess.file_exists(pending_absolute):
		if DirAccess.remove_absolute(pending_absolute) != OK:
			return false
	return (
		_same_campaign_snapshot_identity(_load_valid_state(save_path), previous_state)
		and _same_campaign_snapshot_identity(_load_valid_state(backup_save_path), previous_state)
		and not FileAccess.file_exists(pending_absolute)
	)


func _campaign_namespace_matches_committed_snapshot(snapshot) -> bool:
	var primary_exists := FileAccess.file_exists(ProjectSettings.globalize_path(save_path))
	var pending_exists := FileAccess.file_exists(ProjectSettings.globalize_path(temp_save_path))
	var backup_exists := FileAccess.file_exists(ProjectSettings.globalize_path(backup_save_path))
	var primary_exact := primary_exists and _same_campaign_snapshot_identity(_load_valid_state(save_path), snapshot)
	var pending_exact := pending_exists and _same_campaign_snapshot_identity(_load_valid_state(temp_save_path), snapshot)
	var backup_exact := backup_exists and _same_campaign_snapshot_identity(_load_valid_state(backup_save_path), snapshot)
	if (
		(primary_exists and not primary_exact)
		or (pending_exists and not pending_exact)
		or (backup_exists and not backup_exact)
	):
		return false
	# A published commit always needs two independently serialized witnesses.
	# Normally these are primary + backup. The only recovery representation is
	# pending + backup when no visible primary can shadow their exact majority.
	return backup_exact and (primary_exact or (not primary_exists and pending_exact))


func _clear_replacement_runtime_context() -> void:
	_replacement_guard_started = false
	_replacement_guard_was_preexisting = false
	_replacement_guard_previous_state = null


func _consume_campaign_replacement_failpoint(step: String) -> Error:
	if not _forced_replacement_failures_for_tests.has(step):
		return OK
	var forced_error := int(_forced_replacement_failures_for_tests[step])
	_forced_replacement_failures_for_tests.erase(step)
	return forced_error if forced_error != OK else ERR_CANT_CREATE


func _finish_campaign_replacement(error: Error, stage: String = "", details: PackedStringArray = PackedStringArray(), committed_state = null, outcome: int = -1) -> Error:
	_replacement_in_progress = false
	var final_error := error
	var final_stage := stage
	var final_details := details.duplicate()
	var final_outcome := (
		CampaignReplacementOutcome.COMMITTED
		if final_error == OK
		else (outcome if outcome >= 0 else CampaignReplacementOutcome.PRESERVED)
	)

	if final_error == OK and _replacement_guard_started:
		if committed_state == null or not _campaign_namespace_matches_committed_snapshot(committed_state):
			final_error = ERR_INVALID_DATA
			final_stage = REPLACE_STEP_GUARD_CLEAR
			final_outcome = CampaignReplacementOutcome.IN_DOUBT
			final_details.append("Po commicie każdy istniejący kandydat primary/pending/backup musi być poprawny i dokładnie równy kanonowi; trwała blokada odczytu pozostaje aktywna.")
		else:
			var clear_committed_guard_error := _clear_campaign_replacement_guard()
			if clear_committed_guard_error != OK:
				final_error = clear_committed_guard_error
				final_stage = REPLACE_STEP_GUARD_CLEAR
				final_outcome = CampaignReplacementOutcome.IN_DOUBT
				final_details.append("Nie udało się usunąć trwałej blokady po zatwierdzonym commicie.")
	elif final_error != OK:
		if _replacement_guard_was_preexisting:
			# A retry may clear a pre-existing durable guard only by committing and
			# validating a complete new campaign. Any failed retry stays sticky.
			final_outcome = CampaignReplacementOutcome.IN_DOUBT
		elif final_outcome == CampaignReplacementOutcome.PRESERVED and _replacement_guard_started:
			if not _restore_preserved_campaign_namespace(_replacement_guard_previous_state):
				final_outcome = CampaignReplacementOutcome.IN_DOUBT
				final_details.append("Nie udało się potwierdzić pełnego przywrócenia poprzedniego namespace; trwała blokada odczytu pozostaje aktywna.")
			else:
				var clear_preserved_guard_error := _clear_campaign_replacement_guard()
				if clear_preserved_guard_error != OK:
					final_outcome = CampaignReplacementOutcome.IN_DOUBT
					final_details.append("Poprzednia kampania jest spójna, ale nie udało się usunąć trwałej blokady odczytu.")

	_forced_replacement_failures_for_tests.clear()
	_clear_replacement_runtime_context()
	if final_error == OK:
		_last_replacement_committed_state = committed_state.duplicate(true) if committed_state is Resource else committed_state
		last_replacement_outcome = CampaignReplacementOutcome.COMMITTED
		last_replacement_failure_stage = ""
		last_replacement_failure_details = PackedStringArray()
		last_validation_errors = PackedStringArray()
		return OK
	_last_replacement_committed_state = null
	last_replacement_outcome = final_outcome
	last_replacement_failure_stage = final_stage
	last_replacement_failure_details = final_details
	return final_error


func _configured_campaign_paths_are_distinct() -> bool:
	var normalized_paths: Dictionary = {}
	for path in [save_path, temp_save_path, backup_save_path, replacement_guard_path]:
		var normalized := ProjectSettings.globalize_path(path).simplify_path().replace("\\", "/")
		if OS.get_name() == "Windows":
			normalized = normalized.to_lower()
		if normalized.is_empty() or normalized_paths.has(normalized):
			return false
		normalized_paths[normalized] = true
	return true


func _reject_save(errors: PackedStringArray) -> Error:
	last_validation_errors = errors.duplicate()
	# Niepoprawny kandydat jest oczekiwanym, kontrolowanym wynikiem granicy
	# persistence. Diagnostyka pozostaje dostępna maszynowo i jako WARNING; ERROR
	# jest zarezerwowany dla nieobsłużonych awarii silnika/testu.
	push_warning("SaveManager odrzucił zapis: %s" % "; ".join(errors))
	return ERR_INVALID_DATA


func _record_load_rejection(path: String, errors: PackedStringArray) -> void:
	load_diagnostics[path] = errors.duplicate()
	push_warning("SaveManager odrzucił kandydata %s: %s" % [path, "; ".join(errors)])
