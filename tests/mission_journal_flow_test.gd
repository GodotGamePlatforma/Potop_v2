extends Node

const BaseScene := preload("res://scenes/base/BaseScene.tscn")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const MissionSystemScript := preload("res://scripts/base/MissionSystem.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")

var _failed := false


class MissionRootStub extends Node:
	var game_state
	var mission_system = MissionSystemScript.new()

	func reconcile_tutorial() -> bool:
		return false

	func reconcile_missions() -> bool:
		return mission_system.reconcile(game_state)

	func track_mission(mission_id: String) -> bool:
		return mission_system.track_mission(game_state, mission_id)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(9201, DifficultyProfileScript.new())
	state.tutorial.complete()
	state.current_phase = GamePhaseScript.Phase.BASE_PLANNING
	var stub := MissionRootStub.new()
	stub.game_state = state
	add_child(stub)
	stub.reconcile_missions()

	var base = BaseScene.instantiate()
	add_child(base)
	base.bind(stub, state)
	await get_tree().process_frame
	await get_tree().process_frame

	var tracker := base.find_child("CampaignObjectiveLabel", true, false) as Label
	_assert(tracker != null and tracker.text.contains("FUNDAMENT PRZYSTANI") and tracker.text.contains("0/5"), "Kompaktowy tracker powinien po tutorialu przypiąć Fundament Przystani 0/5.")
	var campaign_panel := base.find_child("CampaignPanel", true, false) as Control
	var compact_checklist := base.find_child("CampaignArtifactsLabel", true, false) as Label
	var open_button := base.find_child("OpenMissionJournalButton", true, false) as Button
	_assert(open_button != null and not open_button.disabled, "Baza powinna udostępniać przycisk pełnego dziennika.")
	_assert(compact_checklist != null and compact_checklist.text.split("\n").size() == 5, "Kompaktowy tracker powinien wypisać dokładnie pięć budynków Fundamentu.")
	_assert(campaign_panel != null and campaign_panel.size.y <= 415.0, "Pięciopunktowa checklista Fundamentu powinna mieścić się w zaprojektowanej wysokości panelu kampanii (jest %.1f px)." % (campaign_panel.size.y if campaign_panel != null else -1.0))
	_assert(campaign_panel != null and open_button != null and open_button.get_global_rect().end.y <= campaign_panel.get_global_rect().end.y + 1.0, "Przycisk dziennika powinien pozostać wewnątrz kompaktowego panelu misji.")
	if open_button != null:
		open_button.pressed.emit()
	await get_tree().process_frame

	var overlay := base.find_child("MissionJournalOverlay", true, false) as Control
	_assert(overlay != null and overlay.visible, "Przycisk dziennika powinien otworzyć pełnoekranowy modal.")
	var foundation_entry := base.find_child("MissionJournalActiveEntry_foundation_harbor", true, false) as Button
	var signal_entry := base.find_child("MissionJournalActiveEntry_old_signal", true, false) as Button
	_assert(foundation_entry != null and signal_entry != null, "Dziennik powinien równolegle listować Fundament Przystani i Stary sygnał.")
	if signal_entry != null:
		signal_entry.pressed.emit()
	await get_tree().process_frame
	var target_guidance := base.find_child("MissionJournalDetailTarget", true, false) as Label
	_assert(target_guidance != null and target_guidance.text.contains("Zalane Archiwum") and target_guidance.text.contains("R1-09"), "Szczegóły misji powinny wskazywać graczowi nazwę i kod miejsca następnego celu.")
	var track_signal := base.find_child("TrackMission_old_signal", true, false) as Button
	_assert(track_signal != null and not track_signal.disabled, "Aktywną równoległą misję fabularną powinno dać się przypiąć.")
	if track_signal != null:
		track_signal.pressed.emit()
	await get_tree().process_frame
	_assert(state.mission_progress.tracked_mission_id == MissionSystemScript.OLD_SIGNAL, "Przycisk ŚLEDŹ powinien zmienić wyłącznie zapisany wybór trackera.")
	_assert(overlay != null and overlay.visible, "Zmiana śledzonej misji nie powinna zamykać dziennika.")
	await _press_key(KEY_J)
	_assert(overlay != null and not overlay.visible, "Ponowne użycie skrótu J powinno zamknąć opcjonalny dziennik.")
	_assert(get_viewport().gui_get_focus_owner() == open_button, "Zamknięcie dziennika skrótem J powinno przywrócić fokus jego przyciskowi w bazie.")

	base.queue_free()
	stub.game_state = null
	stub.queue_free()
	# The base music player stops in BaseController._exit_tree(). Leave one
	# complete frame after that teardown so the audio backend can release its
	# playback objects before SceneTree quits.
	await get_tree().process_frame
	await get_tree().process_frame
	base = null
	stub = null
	state = null
	tracker = null
	campaign_panel = null
	compact_checklist = null
	open_button = null
	overlay = null
	foundation_entry = null
	signal_entry = null
	target_guidance = null
	track_signal = null
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
		return
	print("Mission journal flow test passed: the base tracker defaults to Foundation Harbor, the full journal shows Old Signal in parallel, and tracking is selectable through real UI controls.")
	get_tree().quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Mission journal flow test failed: " + message)


func _press_key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame
