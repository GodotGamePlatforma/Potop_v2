extends Node

const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const WorkerCandidatePickerPanelScript := preload("res://base_workbench/ui/WorkerCandidatePickerPanel.gd")
const WorkerAssignmentSystemScript := preload("res://base_workbench/systems/WorkerAssignmentSystem.gd")

var _failed := false
var _chosen: Array = []


func _ready() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(1608, DifficultyProfileScript.new())
	state.tutorial.complete()
	for resource_id in ResourceIdsScript.all():
		state.resources.set_amount(resource_id, 100)
	var station = BuildingStateScript.new()
	station.id = "candidate_test_station"
	station.definition_id = "diving_station"
	station.slot_id = "bottom_right"
	station.level = 2
	station.is_built = true
	station.assigned_survivor_ids.assign(["igor"])
	state.buildings.append(station)
	state.find_survivor("igor").current_assignment = station.id
	state.find_survivor("igor").profession_talent_ids = {"nurek": "nurek_technik_glebinowy"}
	state.current_day_plan.sync_from_state(state)
	state.find_survivor("igor").fatigue = 85
	state.find_survivor("mira").fatigue = 85

	var backdrop := ColorRect.new()
	backdrop.color = Color("061014")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	var panel = WorkerCandidatePickerPanelScript.new()
	panel.survivor_chosen.connect(func(building_id: String, slot_index: int, survivor_id: String):
		_chosen = [building_id, slot_index, survivor_id]
	)
	center.add_child(panel)
	panel.configure(state, GameDatabase.buildings.get("diving_station"), station, 0, state.tutorial.step)
	panel.refresh_layout(Vector2(1280, 720))
	await get_tree().process_frame

	var igor := panel.find_child("WorkerCandidate_igor", true, false) as Button
	var mira := panel.find_child("WorkerCandidate_mira", true, false) as Button
	var anka := panel.find_child("WorkerCandidate_anka", true, false) as Button
	var clear := panel.find_child("WorkerClearButton", true, false) as Button
	var body := panel.find_child("WorkerCandidateBody", true, false) as GridContainer
	var igor_status := panel.find_child("WorkerCandidateStatus_igor", true, false) as Label
	var mira_status := panel.find_child("WorkerCandidateStatus_mira", true, false) as Label
	var fatigue_detail := panel.find_child("WorkerCandidateStat_fatigue", true, false) as Label
	var production_detail := panel.find_child("WorkerCandidateCompetency_production", true, false) as Label
	var positive_trait := panel.find_child("WorkerCandidatePositiveTrait", true, false) as Label
	var talent_detail := panel.find_child("WorkerCandidateDetailTalents", true, false) as Label
	_assert(igor != null and not igor.disabled, "Bieżący mieszkaniec musi pozostać dostępnym kafelkiem.")
	_assert(igor_status != null and "ZDOLNY • JUŻ PRACUJE" in igor_status.text, "Bieżąca Obsługa Stacji musi używać wspólnej bramki pracy, nie progu nurkowania.")
	_assert(mira != null and not mira.disabled, "Kandydat zdolny do zwykłej pracy musi mieć aktywny kafelek dla Obsługi Stacji.")
	_assert(mira != null and mira.tooltip_text.to_lower().contains("obsługa stacji"), "Aktywny kafelek musi opisywać wspólne stanowisko obsługi.")
	_assert(mira_status != null and "ZDOLNY • PO PRZYDZIALE BĘDZIE PRACOWAĆ" in mira_status.text, "Selektor musi przed kliknięciem pokazać aktywny wkład nowej Obsługi Stacji.")
	_assert(anka != null and not anka.disabled, "Dostępna mieszkanka musi mieć aktywny kafelek.")
	_assert(fatigue_detail != null and "stanowisko Nurka poniżej 85%" in fatigue_detail.tooltip_text, "Stan Zmęczenia musi objaśniać znaczenie i dokładny próg nurkowania po najechaniu.")
	_assert(production_detail != null and "osobisty wkład" in production_detail.tooltip_text and "Aktualny efekt" in production_detail.tooltip_text, "Kompetencja Produkcja musi objaśniać dokładny efekt i bieżący poziom po najechaniu.")
	_assert(positive_trait != null and "Cecha narracyjna" in positive_trait.tooltip_text and "nie zmienia statystyk" in positive_trait.tooltip_text, "Cecha musi jawnie wyjaśniać swoje obecne narracyjne znaczenie po najechaniu.")
	_assert(talent_detail != null and talent_detail.text.contains("Technik głębinowy") and talent_detail.tooltip_text.contains("1,8 sekundy"), "Selektor obsady musi prezentować aktywny talent i jego dokładny efekt bez możliwości zmiany wyboru.")
	_assert(igor.tooltip_text.contains("Technik głębinowy") and igor.tooltip_text.contains("25% zwykłego hałasu"), "Kafelek kandydata musi zachować opis aktywnego talentu w podpowiedzi.")
	_assert(panel.find_children("SelectProfessionTalent_*", "Button", true, false).is_empty(), "Selektor obsady nie może stać się drugą drogą mutowania talentów.")
	_assert(clear != null and not clear.disabled, "Obsadzone stanowisko musi udostępniać zwolnienie.")
	_assert(body != null and body.columns == 3, "Szeroki selektor musi używać trzykolumnowego układu sekcji.")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp"))
		get_viewport().get_texture().get_image().save_png("res://tmp/worker_candidate_picker.png")

	if anka != null:
		anka.pressed.emit()
	_assert(_chosen == [station.id, 0, "anka"], "Kliknięcie kafelka musi emitować dokładną komendę obsady.")
	_chosen.clear()
	if clear != null:
		clear.pressed.emit()
	_assert(_chosen == [station.id, 0, ""], "Zwolnienie stanowiska musi emitować pusty identyfikator dla tego samego slotu.")

	panel.refresh_layout(Vector2(900, 620))
	await get_tree().process_frame
	body = panel.find_child("WorkerCandidateBody", true, false) as GridContainer
	_assert(body != null and body.columns == 1, "Węższy selektor musi składać sekcje w jedną kolumnę.")

	panel.queue_free()
	await get_tree().process_frame
	if _failed:
		get_tree().quit(1)
		return
	print("Worker candidate picker flow test passed: tiles, blockers, commands and responsive layout are consistent.")
	get_tree().quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Worker candidate picker flow test failed: " + message)
