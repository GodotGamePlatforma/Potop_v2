extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")

const TEST_SAVE := "user://test_day_transition_performance.tres"
const TEST_PENDING := "user://test_day_transition_performance.pending.tres"
const TEST_BACKUP := "user://test_day_transition_performance.backup.tres"
const MAX_SYNCHRONOUS_TRANSITION_MS := 2000.0

var _failed := false
var _game


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_test_saves()
	SaveManager.configure_paths(TEST_SAVE, TEST_PENDING, TEST_BACKUP)
	_game = GameRootScene.instantiate()
	add_child(_game)
	await _frames(3)

	_assert(
		_game.start_new_campaign("standard", 91_337, true, false),
		"Test powinien uruchomić prawdziwą kampanię z izolowanym persistence.",
	)
	await _frames(3)
	if _game.game_state == null or _game.current_scene == null:
		await _finish()
		return

	_game.game_state.tutorial.complete()
	_game.game_state.resources.set_amount(ResourceIdsScript.FOOD, 1000)
	_game.game_state.resources.set_amount(ResourceIdsScript.HOPE, 80)
	_game.game_state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 90)
	# Day 2 is marked as already rolled so this fixture deterministically reaches
	# normal planning after acknowledging the report.
	_game.game_state.settlement_event_roll_day = 2
	_game.game_state.begin_new_day_plan()
	_game.game_state.current_phase = GamePhaseScript.Phase.BASE_PLANNING
	_game.current_scene.bind(_game, _game.game_state)
	await _frames(2)

	var base_before = _game.current_scene
	var environment_before = base_before.get("_environment")
	var end_day_button := base_before.find_child("EndDayButton", true, false) as Button
	var day_before := int(_game.game_state.day)
	var report_count_before := int(_game.game_state.end_day_report_history.size())
	_assert(end_day_button != null, "Baza musi wystawiać produkcyjny przycisk ZAKOŃCZ DZIEŃ.")
	if end_day_button == null:
		await _finish()
		return

	var end_started_usec := Time.get_ticks_usec()
	end_day_button.pressed.emit()
	var end_day_ms := float(Time.get_ticks_usec() - end_started_usec) / 1000.0
	_assert(
		end_day_ms <= MAX_SYNCHRONOUS_TRANSITION_MS,
		"ZAKOŃCZ DZIEŃ trwało %.1f ms (limit %.1f ms)." % [
			end_day_ms,
			MAX_SYNCHRONOUS_TRANSITION_MS,
		],
	)
	_assert(
		_game.current_scene == base_before
		and _game.current_scene.get("_environment") == environment_before,
		"Rozliczenie dnia nie może przebudowywać BaseScene ani BaseEnvironment.",
	)
	_assert(
		int(_game.game_state.day) == day_before + 1
		and int(_game.game_state.current_phase) == GamePhaseScript.Phase.END_DAY_REPORT
		and _game.game_state.end_day_report_history.size() == report_count_before + 1,
		"Rozliczenie ma jednokrotnie zwiększyć dzień i opublikować dokładnie jeden raport.",
	)

	# A queued/repeated signal after settlement must be rejected by the phase guard.
	end_day_button.pressed.emit()
	_assert(
		int(_game.game_state.day) == day_before + 1
		and _game.game_state.end_day_report_history.size() == report_count_before + 1,
		"Powtórny sygnał ZAKOŃCZ DZIEŃ nie może rozliczyć kolejnego dnia.",
	)
	var persisted_end = SaveManager.load_game()
	_assert(
		persisted_end != null
		and int(persisted_end.current_phase) == GamePhaseScript.Phase.END_DAY_REPORT
		and int(persisted_end.day) == day_before + 1,
		"Atomowy zapis po rozliczeniu musi zawierać raport i nowy numer dnia.",
	)

	var summary_button := base_before.find_child(
		"DaySummaryContinueButton",
		true,
		false
	) as Button
	_assert(
		summary_button != null and summary_button.is_visible_in_tree(),
		"Raport musi wystawiać produkcyjny przycisk ROZPOCZNIJ DZIEŃ.",
	)
	if summary_button == null:
		await _finish()
		return

	var start_started_usec := Time.get_ticks_usec()
	summary_button.pressed.emit()
	var start_day_ms := float(Time.get_ticks_usec() - start_started_usec) / 1000.0
	_assert(
		start_day_ms <= MAX_SYNCHRONOUS_TRANSITION_MS,
		"ROZPOCZNIJ DZIEŃ trwało %.1f ms (limit %.1f ms)." % [
			start_day_ms,
			MAX_SYNCHRONOUS_TRANSITION_MS,
		],
	)
	_assert(
		_game.current_scene == base_before
		and _game.current_scene.get("_environment") == environment_before,
		"Potwierdzenie raportu musi zachować istniejącą scenę i środowisko bazy.",
	)
	_assert(
		int(_game.game_state.current_phase) == GamePhaseScript.Phase.BASE_PLANNING
		and _game.game_state.can_edit_day_plan(),
		"ROZPOCZNIJ DZIEŃ powinno przejść do edytowalnego planowania.",
	)
	summary_button.pressed.emit()
	_assert(
		int(_game.game_state.current_phase) == GamePhaseScript.Phase.BASE_PLANNING
		and int(_game.game_state.day) == day_before + 1,
		"Powtórny sygnał ROZPOCZNIJ DZIEŃ nie może zmienić fazy ani dnia.",
	)
	var persisted_start = SaveManager.load_game()
	_assert(
		persisted_start != null
		and int(persisted_start.current_phase) == GamePhaseScript.Phase.BASE_PLANNING
		and int(persisted_start.day) == day_before + 1,
		"Atomowy zapis rozpoczęcia dnia musi zawierać fazę planowania.",
	)

	print(
		"DAY_TRANSITION_PERFORMANCE end_day_ms=%.1f start_day_ms=%.1f" % [
			end_day_ms,
			start_day_ms,
		]
	)
	await _finish()


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _finish() -> void:
	if _game != null:
		_game.queue_free()
	await _frames(2)
	SaveManager.reset_paths()
	_remove_test_saves()
	if _failed:
		get_tree().quit(1)
		return
	print("Day transition performance test passed: both persisted clicks stay responsive and reuse BaseScene.")
	get_tree().quit(0)


func _remove_test_saves() -> void:
	for path in [TEST_SAVE, TEST_PENDING, TEST_BACKUP]:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Day transition performance test failed: " + message)
