extends Node

## All campaign state is one clean-break format. Earlier campaign files are
## ignored rather than interpreted or deleted automatically.
const SAVE_PATH := "user://ostatni_pomost_campaign.tres"
const TEMP_SAVE_PATH := "user://ostatni_pomost_campaign.pending.tres"
const BACKUP_SAVE_PATH := "user://ostatni_pomost_campaign.backup.tres"
const GameStateScript := preload("res://scripts/data/GameState.gd")
const PersistenceValidatorScript := preload("res://scripts/data/GameStatePersistenceValidator.gd")

var persistence_enabled: bool = true
var save_path: String = SAVE_PATH
var temp_save_path: String = TEMP_SAVE_PATH
var backup_save_path: String = BACKUP_SAVE_PATH
var _forced_save_error_for_tests: Error = OK
var last_validation_errors: PackedStringArray = PackedStringArray()
var load_diagnostics: Dictionary = {}

func save_game(state) -> Error:
	if state == null:
		return ERR_INVALID_PARAMETER
	if not persistence_enabled:
		return OK
	if _forced_save_error_for_tests != OK:
		var forced_error := _forced_save_error_for_tests
		_forced_save_error_for_tests = OK
		return forced_error

	if not (state is Resource) or state.get_script() != GameStateScript:
		return _reject_save(PackedStringArray(["Korzeń zapisu nie jest dokładnym GameState."]))
	var preflight_errors := PersistenceValidatorScript.preflight_errors(state)
	if not preflight_errors.is_empty():
		return _reject_save(preflight_errors)
	var load_errors: PackedStringArray = state.load_validation_errors()
	if not load_errors.is_empty():
		return _reject_save(load_errors)
	var validation_errors: PackedStringArray = state.persistence_validation_errors()
	if not validation_errors.is_empty():
		return _reject_save(validation_errors)
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

func load_game():
	load_diagnostics.clear()
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
	return (
		_load_valid_state(save_path) != null
		or _load_valid_state(temp_save_path) != null
		or _load_valid_state(backup_save_path) != null
	)

func has_any_save_file() -> bool:
	for path in [save_path, temp_save_path, backup_save_path]:
		if FileAccess.file_exists(ProjectSettings.globalize_path(path)):
			return true
	return false

func delete_campaign_storage() -> Error:
	for path in [save_path, temp_save_path, backup_save_path]:
		var absolute_path := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(absolute_path):
			continue
		var remove_error := DirAccess.remove_absolute(absolute_path)
		if remove_error != OK:
			return remove_error
	return OK


func set_persistence_enabled(enabled: bool) -> void:
	persistence_enabled = enabled

func configure_paths(primary: String, pending: String, backup: String) -> void:
	if primary.is_empty() or pending.is_empty() or backup.is_empty():
		return
	save_path = primary
	temp_save_path = pending
	backup_save_path = backup

func reset_paths() -> void:
	save_path = SAVE_PATH
	temp_save_path = TEMP_SAVE_PATH
	backup_save_path = BACKUP_SAVE_PATH
	_forced_save_error_for_tests = OK
	last_validation_errors = PackedStringArray()
	load_diagnostics.clear()


func fail_next_save_for_tests(error: Error = ERR_CANT_CREATE) -> void:
	_forced_save_error_for_tests = error if error != OK else ERR_CANT_CREATE

func _load_valid_state(path: String):
	if not ResourceLoader.exists(path):
		return null
	var loaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (loaded is Resource) or loaded.get_script() != GameStateScript:
		_record_load_rejection(path, PackedStringArray(["Korzeń kandydata nie jest dokładnym GameState."]))
		return null
	var preflight_errors := PersistenceValidatorScript.preflight_errors(loaded)
	if not preflight_errors.is_empty():
		_record_load_rejection(path, preflight_errors)
		return null
	var load_errors: PackedStringArray = loaded.load_validation_errors()
	if not load_errors.is_empty():
		_record_load_rejection(path, load_errors)
		return null
	var validation_errors: PackedStringArray = loaded.persistence_validation_errors()
	if not validation_errors.is_empty():
		_record_load_rejection(path, validation_errors)
		return null
	return loaded


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
