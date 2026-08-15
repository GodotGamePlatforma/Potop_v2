extends Node

const BaseScene := preload("res://scenes/base/BaseScene.tscn")
const BuildingEffectSystemScript := preload("res://scripts/base/BuildingEffectSystem.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const DiseaseCaseStateScript := preload("res://scripts/data/DiseaseCaseState.gd")
const DiseaseSystemScript := preload("res://scripts/base/DiseaseSystem.gd")
const DiveScene := preload("res://scenes/diving/DiveScene.tscn")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const DiseaseExposureStateScript := preload("res://scripts/data/DiseaseExposureState.gd")
const DiveDiseaseHazardContainerScript := preload("res://scripts/diving/DiveDiseaseHazardContainer.gd")
const EndOfDayResolverScript := preload("res://scripts/base/EndOfDayResolver.gd")
const ExpeditionPreparationSystemScript := preload("res://scripts/base/ExpeditionPreparationSystem.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const WorkerAssignmentSystemScript := preload("res://scripts/base/WorkerAssignmentSystem.gd")

var _failed := false


class DiveRootStub extends Node:
	var last_result

	func finish_dive(result) -> bool:
		last_result = result
		return true

	func tutorial_event(_event_id: String) -> bool:
		return false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("Disease epidemic flow: loading definitions")
	GameDatabase.load_definitions()
	print("Disease epidemic flow: R1-06 source")
	await _test_r1_06_typed_source()
	print("Disease epidemic flow: tutorial boundary")
	await _test_tutorial_has_no_disease_decision()
	print("Disease epidemic flow: emergency isolation without Infirmary")
	await _test_emergency_isolation_without_infirmary()
	print("Disease epidemic flow: base presentation and commands")
	await _test_disease_presentation_and_day_plan_commands()
	await _settle(3)
	await get_tree().create_timer(0.1).timeout
	if _failed:
		get_tree().quit(1)
		return
	print("Disease and epidemic flow test passed: R1-06, typed presentation, epidemic status, medical triage and isolation commands share the canonical disease model.")
	get_tree().quit(0)


func _test_r1_06_typed_source() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(73062, DifficultyProfileScript.new())
	state.tutorial.complete()
	var setup = _make_setup(state, false)
	state.current_expedition_setup = setup
	var fixture := await _spawn_dive(state)
	print("Disease epidemic flow: R1-06 dive spawned")
	var dive = fixture.dive
	var stub: DiveRootStub = fixture.stub
	var hazard = _hospital_container(dive)
	_assert(hazard != null, "R1-06 musi tworzyć magazyn ratunkowy.")
	_assert(hazard != null and hazard.get_script() == DiveDiseaseHazardContainerScript, "Po tutorialu magazyn R1-06 musi być jawnym kontenerem zagrożenia chorobowego.")
	if hazard == null or hazard.get_script() != DiveDiseaseHazardContainerScript:
		await _dispose_fixture(fixture)
		return
	_assert(hazard.contents.get(ResourceIdsScript.MEDS_CHEMICALS, 0) == 5, "Magazyn R1-06 musi zachować nagrodę +5 leków.")
	_assert(state.disease_campaign.pending_exposures.is_empty(), "Samo utworzenie świata nurkowania nie może mutować kampanii chorobowej.")

	dive._open_container(hazard)
	await _settle()
	var overlay := dive.find_child("DiseaseHazardOverlay", true, false) as Control
	var title := dive.find_child("DiseaseHazardTitle", true, false) as Label
	var body := dive.find_child("DiseaseHazardBody", true, false) as Label
	_assert(overlay != null and overlay.visible, "Interakcja musi najpierw otworzyć decyzję o narażeniu, nie panel łupu.")
	_assert(dive._pending_container == null and not hazard.opened, "Przed decyzją magazyn i łup muszą pozostać zamknięte.")
	_assert(dive.session.disease_exposures.is_empty() and state.disease_campaign.pending_exposures.is_empty(), "Wyświetlenie ostrzeżenia nie może tworzyć narażenia lokalnego ani kampanijnego.")
	_assert(title != null and "GORĄCZKA ZALEWOWA" in title.text and body != null and "+3" in body.text and "5" in body.text, "Ostrzeżenie musi podać nazwę choroby, presję i nagrodę przed decyzją.")

	var decline := dive.find_child("DeclineDiseaseHazardButton", true, false) as Button
	var accept := dive.find_child("AcceptDiseaseHazardButton", true, false) as Button
	_assert(decline != null, "Decyzja R1-06 musi mieć jawny przycisk odmowy.")
	_assert(accept != null, "Decyzja R1-06 musi mieć jawny przycisk akceptacji.")
	_assert(decline != null and decline.has_focus(), "Bezpieczna odmowa musi otrzymać początkowy fokus decyzji R1-06.")
	await _press_key(fixture.viewport, KEY_TAB)
	_assert(accept != null and accept.has_focus(), "Tab musi przejść z odmowy wyłącznie do akceptacji hazardu.")
	await _press_key(fixture.viewport, KEY_TAB)
	_assert(decline != null and decline.has_focus(), "Fokus decyzji R1-06 musi zapętlać się między jej dwiema akcjami.")
	await _press_key(fixture.viewport, KEY_ESCAPE)
	await _settle()
	_assert(not overlay.visible and not hazard.opened and dive.session.disease_exposures.is_empty(), "Esc musi być równoważny bezpiecznej odmowie bez narażenia i bez łupu.")

	dive._open_container(hazard)
	await _settle()
	if decline != null:
		decline.pressed.emit()
		await _settle()
	_assert(not overlay.visible and not hazard.opened, "Odmowa musi zamknąć decyzję bez otwarcia magazynu.")
	_assert(hazard.contents.get(ResourceIdsScript.MEDS_CHEMICALS, 0) == 5, "Odmowa nie może zmienić nagrody w magazynie.")
	_assert(dive.session.disease_exposures.is_empty() and state.disease_campaign.pending_exposures.is_empty(), "Odmowa nie może mutować sesji ani GameState.")

	dive._open_container(hazard)
	await _settle()
	accept = dive.find_child("AcceptDiseaseHazardButton", true, false) as Button
	if accept != null:
		accept.pressed.emit()
		await _settle()
	_assert(not overlay.visible and dive._pending_container == hazard and dive._loot_panel.visible, "Akceptacja musi dopiero teraz otworzyć prawdziwy panel łupu.")
	_assert(dive.session.disease_exposures.size() == 1, "Akceptacja musi utworzyć dokładnie jedno lokalne narażenie.")
	_assert(state.disease_campaign.pending_exposures.is_empty(), "Nawet zaakceptowany hazard nie może bezpośrednio mutować GameState.")
	if dive.session.disease_exposures.size() == 1:
		var exposure = dive.session.disease_exposures[0]
		_assert(exposure.get_script() == DiseaseExposureStateScript, "Narażenie w sesji musi zachować typ DiseaseExposureState.")
		_assert(exposure.disease_id == "flood_fever" and exposure.target_survivor_id == "igor", "Narażenie musi wskazać kanoniczną chorobę i nurka.")
		_assert(exposure.source_kind == "dive" and exposure.source_id == "R1-06", "Narażenie musi zachować typowane źródło dive/R1-06.")
		_assert(exposure.pressure == 3 and exposure.acquired_day == state.day and exposure.is_valid(), "Narażenie R1-06 musi mieć presję 3, bieżący dzień i przechodzić walidację.")

	dive._take_pending_loot()
	await _settle()
	_assert(dive.session.carried_items.get(ResourceIdsScript.MEDS_CHEMICALS, 0) == 5, "Po akceptacji standardowy system łupu musi przenieść +5 leków.")
	dive._finish_success()
	await _settle()
	print("Disease epidemic flow: R1-06 result produced")
	var result = stub.last_result
	_assert(result != null and result.disease_exposures.size() == 1, "Zakończona wyprawa musi przenieść dokładnie jedno narażenie przez DiveResult.")
	_assert(result != null and result.collected_items.get(ResourceIdsScript.MEDS_CHEMICALS, 0) == 5, "DiveResult musi zachować nagrodę magazynu R1-06.")
	_assert(state.disease_campaign.pending_exposures.is_empty(), "Stub przyjmujący DiveResult dowodzi, że scena nurkowania sama nie dopisuje ekspozycji do kampanii.")
	if result != null and result.disease_exposures.size() == 1 and dive.session.disease_exposures.size() == 1:
		_assert(result.disease_exposures[0] != dive.session.disease_exposures[0], "DiveResult musi otrzymać odłączoną kopię typowanego narażenia.")
		dive.session.disease_exposures[0].pressure = 99
		_assert(result.disease_exposures[0].pressure == 3, "Mutacja lokalnej sesji po wyniku nie może zmienić DiveResult.")
	if result != null:
		var medicine_before_resolution: int = state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS)
		var report = EndOfDayResolverScript.new().resolve(state, result, false)
		print("Disease epidemic flow: R1-06 resolved into campaign")
		var igor = state.find_survivor("igor")
		_assert(report != null and state.day == 2, "Prawdziwy EndOfDayResolver musi rozliczyć wynik wyprawy i przejść do następnego dnia.")
		_assert(state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS) == medicine_before_resolution + 5, "Resolver musi przyznać dokładnie łup +5 leków z tego samego DiveResult.")
		_assert(state.disease_campaign.pending_exposures.is_empty(), "Nocne rozliczenie musi atomowo zużyć oczekujące narażenie R1-06.")
		_assert(igor != null and igor.disease_cases.size() == 1, "Resolver musi utworzyć u Igora dokładnie jeden typowany przypadek z narażenia R1-06.")
		if igor != null and igor.disease_cases.size() == 1:
			var disease_case = igor.disease_cases[0]
			_assert(disease_case.get_script() == DiseaseCaseStateScript and disease_case.phase == DiseaseCaseStateScript.Phase.EXPOSED, "Narażenie z bieżącego dnia musi pozostać w typowanym etapie Narażenie do kolejnego rozliczenia.")
			_assert(disease_case.exposure_pressure == 3 and disease_case.source_kind == "dive" and disease_case.source_id == "R1-06", "Przypadek po resolverze musi zachować presję i tożsamość źródła z DiveResult.")
			var forecast := BuildingEffectSystemScript.new().disease_case_plan_projection(state, "igor", disease_case)
			_assert(
				bool(forecast.get("valid", false))
				and str(forecast.get("source_id", "")) == "R1-06"
				and int(forecast.get("exposure_pressure", -1)) == 3
				and str(forecast.get("ration_id", "")) == "full"
				and int(forecast.get("ration_pressure_modifier", 99)) == -1
				and int(forecast.get("adverse_conditions_pressure", 99)) == 0
				and int(forecast.get("difficulty_pressure_modifier", 99)) == 0
				and bool(forecast.get("exposure_resolves_today", false))
				and int(forecast.get("projected_pressure", -1)) == 2
				and int(forecast.get("infection_threshold", -1)) == 4
				and bool(forecast.get("projected_case_cleared", false)),
				"Kanoniczna prognoza R1-06 musi zachować presję bazową i pokazać pełną rację jako jedyny modyfikator, który wygasza narażenie 2/4."
			)
			var forecast_viewport := SubViewport.new()
			forecast_viewport.name = "ExposedForecastBaseViewport"
			forecast_viewport.size = Vector2i(1280, 720)
			forecast_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(forecast_viewport)
			var forecast_base = BaseScene.instantiate()
			forecast_base.seed_user_settings_before_ready("low", true)
			forecast_viewport.add_child(forecast_base)
			forecast_base.bind(null, state)
			await _settle()
			forecast_base.call("_open_survivor_panel", "igor")
			await _settle()
			var forecast_label := forecast_base.find_child("DiseaseForecast_flood_fever", true, false) as Label
			var expected_forecast := "ŹRÓDŁO  •  dive / R1-06  •  presja bazowa 3\nPRESJA  •  racja pełna -1  •  warunki +0  •  trudność +0  •  prognoza 2 / próg 4  •  rozliczenie narażenia TAK\nKONIEC DNIA  •  USUNIĘCIE PRZYPADKU  •  terapia NIE  •  izolacja NIE  •  naturalny powrót NIE 0/2  •  zdrowie +0"
			_assert(forecast_label != null and forecast_label.text == expected_forecast, "Karta narażenia R1-06 musi 1:1 prezentować kanoniczną prognozę presji, składników i końca dnia.")
			forecast_base.queue_free()
			await get_tree().process_frame
			forecast_viewport.queue_free()
			await get_tree().process_frame
	await _dispose_fixture(fixture)
	print("Disease epidemic flow: R1-06 fixture disposed")


func _test_tutorial_has_no_disease_decision() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(73063, DifficultyProfileScript.new())
	var setup = _make_setup(state, true)
	state.current_expedition_setup = setup
	var fixture := await _spawn_dive(state)
	var dive = fixture.dive
	var container = _hospital_container(dive)
	_assert(container != null, "Fixture tutoriala musi nadal zawierać autorski magazyn R1-06.")
	_assert(container != null and container.get_script() != DiveDiseaseHazardContainerScript, "W tutorialu magazyn R1-06 nie może tworzyć decyzji chorobowej.")
	if container != null:
		dive._open_container(container)
		await _settle()
		var overlay := dive.find_child("DiseaseHazardOverlay", true, false) as Control
		_assert(overlay != null and not overlay.visible, "Interakcja tutorialowa nigdy nie może pokazać hazardu chorobowego.")
		_assert(dive.session.disease_exposures.is_empty() and state.disease_campaign.pending_exposures.is_empty(), "Tutorial nie może wyprodukować narażenia.")
	await _dispose_fixture(fixture)

	var viewport := SubViewport.new()
	viewport.name = "CleanDiseaseCampaignBaseViewport"
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var base = BaseScene.instantiate()
	base.seed_user_settings_before_ready("low", true)
	viewport.add_child(base)
	base.bind(null, state)
	await _settle()
	var resource_summary := base.find_child("ResourceSummary", true, false) as RichTextLabel
	_assert(resource_summary != null and "CHOR" not in resource_summary.text and "EPID" not in resource_summary.text and "Zdrowie osady:" not in resource_summary.tooltip_text, "Czysta kampania nie może rezerwować ani pokazywać segmentu chorobowego w pasku zasobów.")
	base.queue_free()
	await get_tree().process_frame
	viewport.queue_free()
	await get_tree().process_frame


func _test_emergency_isolation_without_infirmary() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(73065, DifficultyProfileScript.new())
	state.tutorial.complete()
	state.resources.set_amount(ResourceIdsScript.MEDS_CHEMICALS, 0)
	var igor = state.find_survivor("igor")
	var definition = GameDatabase.diseases.get("flood_fever")
	_assert(definition != null and _append_symptomatic_case(igor, definition), "Fixture izolacji awaryjnej wymaga poprawnego przypadku objawowego.")
	_assert(state.find_building_by_definition("infirmary") == null, "Fixture izolacji awaryjnej nie może zawierać Lecznicy.")
	state.current_day_plan.sync_from_state(state)

	var viewport := SubViewport.new()
	viewport.name = "EmergencyIsolationBaseViewport"
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var base = BaseScene.instantiate()
	base.seed_user_settings_before_ready("low", true)
	viewport.add_child(base)
	base.bind(null, state)
	await _settle()
	var crew_button := base.find_child("CrewButton", true, false) as Button
	if crew_button != null:
		crew_button.pressed.emit()
		await _settle()
	var igor_button := base.find_child("SurvivorButton_igor", true, false) as Button
	if igor_button != null:
		igor_button.pressed.emit()
		await _settle()
	var disease_system = DiseaseSystemScript.new()
	var isolation_button := base.find_child("IsolationIntentButton_igor", true, false) as Button
	_assert(isolation_button != null and not isolation_button.disabled and disease_system.isolation_change_blocker(state, "igor", true).is_empty(), "Brak Lecznicy i leków nie może zablokować komendy izolacji awaryjnej.")
	if isolation_button != null:
		isolation_button.pressed.emit()
		await _settle()
	var assignments := disease_system.isolation_assignments(state, 0)
	_assert(assignments.formal_ids.is_empty() and assignments.emergency_ids == ["igor"], "Przy zerowej pojemności formalnej Igor musi trafić dokładnie do izolacji awaryjnej.")
	var forecast := BuildingEffectSystemScript.new().disease_case_plan_projection(state, "igor", igor.disease_cases[0])
	_assert(bool(forecast.get("isolated", false)) and bool(forecast.get("emergency_isolated", false)) and not bool(forecast.get("formally_isolated", true)), "Wspólna prognoza musi sklasyfikować izolację bez Lecznicy wyłącznie jako awaryjną.")
	var forecast_label := base.find_child("DiseaseForecast_flood_fever", true, false) as Label
	_assert(forecast_label != null and "izolacja AWARYJNA" in forecast_label.text, "Karta mieszkańca musi jawnie pokazać graczowi tryb izolacji awaryjnej.")

	base.queue_free()
	await get_tree().process_frame
	viewport.queue_free()
	await get_tree().process_frame


func _test_disease_presentation_and_day_plan_commands() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(73064, DifficultyProfileScript.new())
	state.tutorial.complete()
	state.resources.set_amount(ResourceIdsScript.MEDS_CHEMICALS, 10)
	var igor = state.find_survivor("igor")
	var anka = state.find_survivor("anka")
	var mira = state.find_survivor("mira")
	var definition = GameDatabase.diseases.get("flood_fever")
	_assert(definition != null, "Test UI wymaga zwalidowanej definicji flood_fever z GameDatabase.")
	if definition == null:
		return
	var station = _add_building(state, "test_disease_station", "diving_station", "bottom_right", 1, [])
	var infirmary = _add_building(state, "test_disease_infirmary", "infirmary", "center", 3, ["mira"])
	_assert(station != null and infirmary != null and igor.current_assignment.is_empty() and station.assigned_survivor_ids.is_empty() and mira.current_assignment == infirmary.id, "Fixture musi rozdzielać niezależnego nurka od opcjonalnej obsady Stacji i zachować jawny roster Lecznicy.")
	state.current_day_plan.sync_from_state(state)
	_assert(state.current_day_plan.set_selected_diver("igor") and state.current_day_plan.selected_diver_id == "igor", "Fixture musi wybrać Igora jako niezależnego nurka przed wystąpieniem choroby.")
	_assert(_append_symptomatic_case(igor, definition), "Igor musi otrzymać poprawny typowany przypadek objawowy.")
	_assert(_append_symptomatic_case(anka, definition), "Anka musi otrzymać poprawny typowany przypadek objawowy.")

	var disease_system = DiseaseSystemScript.new()
	var isolated_sources: Array[String] = ["igor", "anka"]
	var projection := disease_system.project_day(
		state,
		GameDatabase.diseases,
		{"mira": "full", "anka": "full", "igor": "full"},
		[],
		isolated_sources,
		[],
		{"formal_isolation_capacity": 2}
	)
	_assert(bool(projection.get("valid", false)), "Dwa typowane przypadki objawowe muszą dać poprawną projekcję dnia.")
	_assert(bool(projection.get("outbreak_active_after", false)) and int(projection.get("outbreak_threshold", 0)) == 2, "Dwa zakaźne przypadki w trzyosobowej osadzie muszą osiągnąć domenowy próg epidemii 2.")
	var applied: Dictionary = disease_system.apply_day(state, projection)
	_assert(bool(applied.get("applied", false)) and state.disease_campaign.outbreak_active, "Zastosowana projekcja musi ustanowić kanoniczny aktywny stan epidemii.")
	if not anka.disease_cases.is_empty():
		anka.disease_cases[0].phase = DiseaseCaseStateScript.Phase.SEVERE

	var viewport := SubViewport.new()
	viewport.name = "DiseaseEpidemicBaseViewport"
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var base = BaseScene.instantiate()
	base.seed_user_settings_before_ready("low", true)
	viewport.add_child(base)
	base.bind(null, state)
	await _settle()

	var crew_button := base.find_child("CrewButton", true, false) as Button
	var epidemic_status := base.find_child("EpidemicStatusLabel", true, false) as Label
	var resource_summary := base.find_child("ResourceSummary", true, false) as RichTextLabel
	_assert(resource_summary != null and "EPID" in resource_summary.text and "2/2" in resource_summary.text, "Aktywna epidemia musi wyróżnić kompaktowy segment EPID aktywne/zakaźne w pasku zasobów.")
	_assert(resource_summary != null and resource_summary.tooltip_text.ends_with("Zdrowie osady: aktywne przypadki 2 • zakaźni 2 • oczekujące narażenia 0 • próg epidemii 2."), "Tooltip Zdrowia osady musi podawać wyłącznie kanoniczne liczniki campaign_presentation.")
	_assert(crew_button != null and "EPIDEMIA" in crew_button.text, "Aktywna epidemia musi być widoczna już na przycisku Załogi.")
	_assert(epidemic_status != null and "EPIDEMIA AKTYWNA" in epidemic_status.text and "2 / próg 2" in epidemic_status.text, "Panel Załogi musi prezentować aktywną epidemię i wartości z campaign_presentation.")
	var risk_station_slot := base.find_child("Slot_bottom_right", true, false) as Control
	if risk_station_slot != null:
		risk_station_slot.emit_signal("pressed")
		await _settle()
	var risk_assignment_rail := base.find_child("BuildingStaffingRail", true, false) as PanelContainer
	var risk_worker_change := risk_assignment_rail.find_child("WorkerChangeButton", true, false) as Button if risk_assignment_rail != null else null
	_assert(risk_assignment_rail != null and risk_worker_change != null, "WorkerAssignmentRail Stacji musi udostępniać zmianę pierwszego stanowiska.")
	if risk_worker_change != null:
		risk_worker_change.pressed.emit()
		await _settle()
	var risk_worker_picker := base.find_child("WorkerCandidatePickerPanel", true, false) as PanelContainer
	var risk_igor_candidate := risk_worker_picker.find_child("WorkerCandidate_igor", true, false) as Button if risk_worker_picker != null else null
	var risk_anka_candidate := risk_worker_picker.find_child("WorkerCandidate_anka", true, false) as Button if risk_worker_picker != null else null
	var risk_detail := risk_worker_picker.find_child("WorkerCandidateDetailTraits", true, false) as Label if risk_worker_picker != null else null
	_assert(risk_worker_picker != null and risk_worker_picker.visible and risk_igor_candidate != null and risk_anka_candidate != null and risk_detail != null, "WorkerCandidatePickerPanel musi pokazać oba typowane przypadki chorobowe.")
	if risk_igor_candidate != null:
		risk_igor_candidate.mouse_entered.emit()
	_assert(risk_detail != null and risk_detail.text == "ryzyko kontaktu: Gorączka Zalewowa +2", "Rail obsady musi pokazać kanoniczną presję kontaktu +2 dla zakaźnego kandydata w Objawach.")
	if risk_anka_candidate != null:
		risk_anka_candidate.mouse_entered.emit()
	_assert(risk_detail != null and risk_detail.text == "ryzyko kontaktu: Gorączka Zalewowa +3", "Rail obsady musi pokazać kanoniczną presję kontaktu +3 dla kandydata w Stanie ciężkim.")
	var risk_picker_back := risk_worker_picker.find_child("WorkerCandidateBackButton", true, false) as Button if risk_worker_picker != null else null
	if risk_picker_back != null:
		risk_picker_back.pressed.emit()
		await _settle()
	var risk_building_panel := base.find_child("BuildingPanel", true, false) as Control
	var risk_building_close := risk_building_panel.find_child("CloseButton", true, false) as Button if risk_building_panel != null else null
	if risk_building_close != null:
		risk_building_close.pressed.emit()
		await _settle()
	if crew_button != null:
		crew_button.pressed.emit()
		await _settle()
	var igor_button := base.find_child("SurvivorButton_igor", true, false) as Button
	_assert(igor_button != null and "Gorączka Zalewowa" in igor_button.tooltip_text, "Lista Załogi musi sygnalizować typowaną chorobę Igora.")
	if igor_button != null:
		igor_button.pressed.emit()
		await _settle()
	var disease_title := base.find_child("DiseaseTitle_flood_fever", true, false) as Label
	var disease_effects := base.find_child("DiseaseEffects_flood_fever", true, false) as Label
	_assert(disease_title != null and "GORĄCZKA ZALEWOWA" in disease_title.text and "OBJAWY" in disease_title.text, "Karta mieszkańca musi pokazać nazwę i etap z case_presentation.")
	_assert(disease_effects != null and "Zakaźność: TAK" in disease_effects.text and "Praca: 65%" in disease_effects.text and "Nurkowanie: ZABLOKOWANE" in disease_effects.text, "Karta mieszkańca musi pokazać zakaźność oraz skutki pracy i nurkowania z definicji etapu.")

	var isolation_button := base.find_child("IsolationIntentButton_igor", true, false) as Button
	var isolation_blocker := disease_system.isolation_change_blocker(state, "igor", true)
	_assert(state.current_day_plan.selected_diver_id == "igor" and igor.current_assignment.is_empty(), "Przed izolacją Igor musi pozostać aktywnym niezależnym nurkiem, a nie pracownikiem Stacji.")
	_assert(isolation_button != null and isolation_blocker.is_empty() and not isolation_button.disabled, "Objawowy mieszkaniec w edytowalnym planie musi mieć dostępną domenową komendę izolacji.")
	if isolation_button != null:
		isolation_button.pressed.emit()
		await _settle()
	_assert("igor" in state.current_day_plan.isolated_survivor_ids, "Przycisk izolacji musi zmienić wyłącznie kanoniczny DayPlanState przez DiseaseSystem.")
	_assert(state.current_day_plan.selected_diver_id.is_empty(), "Izolacja aktywnego nurka musi wyczyścić DayPlanState.selected_diver_id.")
	_assert(igor.current_assignment.is_empty() and station.assigned_survivor_ids.is_empty(), "Izolacja niezależnego nurka nie może utworzyć ani zmienić opcjonalnej obsady Stacji Nurkowej.")
	var assignment_system = WorkerAssignmentSystemScript.new()
	var assignment_blocker := assignment_system.assignment_candidate_blocker(state, "igor")
	_assert("izolacja" in assignment_blocker.to_lower() and "0 pracy" in assignment_blocker, "Kanoniczny blocker nowego przydziału musi jawnie wyjaśniać izolację i zerowy wkład pracy.")
	var rejected_assignment := assignment_system.assign_worker(state, "igor", infirmary.id, 2)
	_assert(not rejected_assignment and igor.current_assignment.is_empty() and station.assigned_survivor_ids.is_empty() and infirmary.assigned_survivor_ids == ["mira"], "Próba nowego przydziału izolowanego Igora musi zostać odrzucona bez naruszenia obu rosterów.")
	var disease_plan := base.find_child("DiseasePlan_flood_fever", true, false) as Label
	_assert(disease_plan != null and "izolacja TAK" in disease_plan.text, "Karta choroby musi po komendzie odświeżyć status planowanej izolacji.")
	var symptomatic_case = igor.disease_cases[0] if not igor.disease_cases.is_empty() else null
	var symptomatic_forecast := BuildingEffectSystemScript.new().disease_case_plan_projection(state, "igor", symptomatic_case)
	_assert(
		bool(symptomatic_forecast.get("valid", false))
		and bool(symptomatic_forecast.get("isolated", false))
		and bool(symptomatic_forecast.get("formally_isolated", false))
		and not bool(symptomatic_forecast.get("emergency_isolated", true))
		and bool(symptomatic_forecast.get("treatment_planned", false))
		and not bool(symptomatic_forecast.get("natural_recovery_qualified", true))
		and int(symptomatic_forecast.get("natural_recovery_days_after", -1)) == 0
		and str(symptomatic_forecast.get("projected_phase_code", "")) == "recovering"
		and int(symptomatic_forecast.get("projected_health_delta", 99)) == 0,
		"Kanoniczna prognoza objawowego Igora musi odróżnić formalną izolację i planowaną terapię od naturalnego powrotu."
	)
	var symptomatic_forecast_label := base.find_child("DiseaseForecast_flood_fever", true, false) as Label
	var expected_symptomatic_forecast := "ŹRÓDŁO  •  dive / R1-06  •  presja bazowa 4\nPRESJA  •  racja pełna +0  •  warunki +0  •  trudność +0  •  prognoza 4 / próg 4  •  rozliczenie narażenia NIE\nKONIEC DNIA  •  REKONWALESCENCJA  •  terapia TAK  •  izolacja FORMALNA  •  naturalny powrót NIE 0/2  •  zdrowie +0"
	_assert(symptomatic_forecast_label != null and symptomatic_forecast_label.text == expected_symptomatic_forecast, "Karta izolowanego przypadku objawowego musi 1:1 pokazać domenową prognozę terapii, izolacji i etapu końca dnia.")

	var survivor_close := base.find_child("CloseSurvivorDevelopment", true, false) as Button
	if survivor_close != null:
		survivor_close.pressed.emit()
		await _settle()
	var station_slot := base.find_child("Slot_bottom_right", true, false) as Control
	if station_slot != null:
		station_slot.emit_signal("pressed")
		await _settle()
	var readiness := base.find_child("DiveReadinessLabel", true, false) as Label
	var diver_candidate := base.find_child("DiverCandidate_igor", true, false) as Button
	var station_definition = GameDatabase.buildings.get("diving_station")
	var preparation := ExpeditionPreparationSystemScript.new().analyze(state, station, station_definition)
	_assert(not bool(preparation.get("ready", true)) and str(preparation.get("reason", "")) == "Wybierz wolnego mieszkańca z listy nurków.", "Po izolacji Stacja musi wymagać jawnego wyboru nowego nurka.")
	_assert(readiness != null and readiness.text == "NIEGOTOWY  •  Wybierz wolnego mieszkańca z listy nurków.", "HUD Stacji musi poprosić o wybór nowego nurka po wyczyszczeniu selected_diver_id.")
	_assert(diver_candidate != null and diver_candidate.disabled and "W IZOLACJI" in diver_candidate.text, "Izolowany Igor musi pozostać widoczny na liście nurków jako niedostępny kandydat, nie jako obsada Stacji.")
	var worker_assignment_rail := base.find_child("BuildingStaffingRail", true, false) as PanelContainer
	var worker_occupant := worker_assignment_rail.find_child("WorkerOccupantLabel", true, false) as Label if worker_assignment_rail != null else null
	var worker_change := worker_assignment_rail.find_child("WorkerChangeButton", true, false) as Button if worker_assignment_rail != null else null
	_assert(worker_assignment_rail != null and worker_occupant != null and worker_occupant.text == "NIEOBSADZONE" and worker_change != null, "WorkerAssignmentRail musi utrzymać niezależne, nieobsadzone stanowisko Stacji.")
	if worker_change != null:
		worker_change.pressed.emit()
		await _settle()
	var worker_picker := base.find_child("WorkerCandidatePickerPanel", true, false) as PanelContainer
	var igor_worker_candidate := worker_picker.find_child("WorkerCandidate_igor", true, false) as Button if worker_picker != null else null
	var igor_worker_status := worker_picker.find_child("WorkerCandidateStatus_igor", true, false) as Label if worker_picker != null else null
	_assert(worker_picker != null and worker_picker.visible and igor_worker_candidate != null and igor_worker_candidate.disabled, "WorkerCandidatePickerPanel musi pozostawić izolowanego Igora jako widocznego, niedostępnego kandydata do obsady.")
	_assert(igor_worker_status != null and "WKŁAD 0" in igor_worker_status.text and assignment_blocker in igor_worker_status.text, "WorkerCandidatePickerPanel musi pokazać dokładny domenowy blocker izolacji i zerowy wkład.")
	if igor_worker_candidate != null:
		igor_worker_candidate.mouse_entered.emit()
	var isolated_contact_risk := worker_picker.find_child("WorkerCandidateDetailTraits", true, false) as Label if worker_picker != null else null
	_assert(isolated_contact_risk != null and isolated_contact_risk.text == "Kontakt zawodowy: brak dodatkowej presji.", "Po zaplanowaniu izolacji picker obsady nie może nadal przedstawiać Igora jako źródła kontaktu zawodowego.")
	var worker_picker_back := worker_picker.find_child("WorkerCandidateBackButton", true, false) as Button if worker_picker != null else null
	if worker_picker_back != null:
		worker_picker_back.pressed.emit()
		await _settle()
	var building_panel := base.find_child("BuildingPanel", true, false) as Control
	var building_close := building_panel.find_child("CloseButton", true, false) as Button if building_panel != null else null
	if building_close != null:
		building_close.pressed.emit()
		await _settle()

	var infirmary_slot := base.find_child("Slot_center", true, false) as Control
	if infirmary_slot != null:
		infirmary_slot.emit_signal("pressed")
		await _settle()
	building_panel = base.find_child("BuildingPanel", true, false) as Control
	var care_projection: Dictionary = building_panel.call("_medical_care_projection") if building_panel != null else {}
	var care_summary := base.find_child("MedicalCareSummaryLabel", true, false) as Label
	var care_queue := base.find_child("MedicalCareQueue", true, false) as VBoxContainer
	var isolation_capacity := base.find_child("IsolationCapacityLabel", true, false) as Label
	var expected_care_count := "%d z %d" % [
		int(care_projection.get("treated_count", -1)),
		int(care_projection.get("patients_requiring_care", -1)),
	]
	var expected_medicine_cost := "= %d jednostek leków" % int(care_projection.get("medicine_spent", -1))
	_assert(care_summary != null and expected_care_count in care_summary.text and expected_medicine_cost in care_summary.text, "Lecznica musi prezentować pojemność i koszt z tej samej projekcji MedicalCareSystem.")
	_assert(care_queue != null and care_queue.find_child("MedicalPatient_igor", false, false) != null and care_queue.find_child("MedicalPatient_anka", false, false) != null, "Wspólna kolejka Lecznicy musi zawierać oba przypadki chorobowe dokładnie raz.")
	_assert(isolation_capacity != null and "formalna 1 / 2" in isolation_capacity.text and "awaryjna 0" in isolation_capacity.text and "Igor Sowa" in isolation_capacity.text, "Lecznica III musi pokazać domenowy przydział izolacji formalnej oraz brak izolacji awaryjnej.")
	var priority_button := base.find_child("MedicalPriority_igor", true, false) as Button
	_assert(priority_button != null and not priority_button.disabled, "Wiersz Igora musi udostępnić jawny priorytet wspólnego triage.")
	if priority_button != null:
		priority_button.pressed.emit()
		await _settle()
	_assert(state.current_day_plan.medical_priority_survivor_ids == ["igor"], "Priorytet terapii musi zapisać się wyłącznie w kanonicznym DayPlanState.")
	care_queue = base.find_child("MedicalCareQueue", true, false) as VBoxContainer
	_assert(care_queue != null and care_queue.get_child_count() >= 1 and str(care_queue.get_child(0).name) == "MedicalPatient_igor", "Po priorytecie ta sama projekcja triage musi przenieść Igora na początek kolejki.")
	building_panel = base.find_child("BuildingPanel", true, false) as Control
	building_close = building_panel.find_child("CloseButton", true, false) as Button if building_panel != null else null
	if building_close != null:
		building_close.pressed.emit()
		await _settle()

	state.current_day_plan.locked = true
	base.bind(null, state)
	await _settle()
	crew_button = base.find_child("CrewButton", true, false) as Button
	if crew_button != null:
		crew_button.pressed.emit()
		await _settle()
	igor_button = base.find_child("SurvivorButton_igor", true, false) as Button
	if igor_button != null:
		igor_button.pressed.emit()
		await _settle()
	isolation_button = base.find_child("IsolationIntentButton_igor", true, false) as Button
	var locked_blocker := disease_system.isolation_change_blocker(state, "igor", false)
	_assert(isolation_button != null and isolation_button.disabled and isolation_button.tooltip_text == locked_blocker, "Zablokowany plan musi pokazać dokładny blocker komendy zakończenia izolacji.")
	base.call("_on_survivor_isolation_changed", "igor", false)
	_assert("igor" in state.current_day_plan.isolated_survivor_ids and state.current_day_plan.selected_diver_id.is_empty() and station.assigned_survivor_ids.is_empty(), "Bezpośrednie wywołanie handlera nie może ominąć blokady ani zmienić wyboru nurka lub rosteru.")

	base.queue_free()
	await get_tree().process_frame
	viewport.queue_free()
	await get_tree().process_frame


func _append_symptomatic_case(survivor, definition) -> bool:
	if survivor == null:
		return false
	var disease_case = DiseaseCaseStateScript.new()
	if not disease_case.setup_from_definition(
		definition,
		DiseaseCaseStateScript.Phase.SYMPTOMATIC,
		1,
		4,
		"dive",
		"R1-06"
	):
		return false
	survivor.disease_cases.append(disease_case)
	return true


func _add_building(
	state,
	building_id: String,
	definition_id: String,
	slot_id: String,
	level: int,
	worker_ids: Array[String]
):
	var building = BuildingStateScript.new()
	building.id = building_id
	building.definition_id = definition_id
	building.slot_id = slot_id
	building.level = level
	building.is_built = true
	building.condition = 100
	building.assigned_survivor_ids.assign(worker_ids)
	state.buildings.append(building)
	var slot_data: Dictionary = state.platform.slot_states[slot_id]
	slot_data["building_id"] = building.id
	state.platform.slot_states[slot_id] = slot_data
	for survivor_id in worker_ids:
		var survivor = state.find_survivor(survivor_id)
		if survivor != null:
			survivor.current_assignment = building.id
	return building


func _make_setup(state, tutorial_mode: bool):
	var setup = ExpeditionSetupScript.new()
	var diver = state.find_survivor("igor")
	setup.capture_diver(diver, 160.0)
	setup.capture_item_weights(GameDatabase.items)
	setup.diver_carry_capacity = 100.0
	setup.backpack_capacity = 12
	setup.oxygen_capacity = 600.0
	setup.selected_gear.assign(["knife", "crowbar", "repair_kit"])
	setup.equipped_gear = {
		"oxygen_tank": "oxygen_tank_mk1",
		"light": "diving_lantern_mk1",
	}
	setup.start_entry_point = "R1-06"
	setup.target_sector = "R1-06"
	setup.day = state.day
	setup.tutorial_mode = tutorial_mode
	setup.base_support_level = 1
	setup.difficulty_modifiers = {"loot_density_multiplier": 1.0}
	return setup


func _spawn_dive(state) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "DiseaseEpidemicDiveViewport"
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var stub := DiveRootStub.new()
	viewport.add_child(stub)
	var dive = DiveScene.instantiate()
	viewport.add_child(dive)
	dive.bind(stub, state)
	await _settle()
	return {"viewport": viewport, "stub": stub, "dive": dive}


func _hospital_container(dive):
	if dive == null or dive.dive_map == null:
		return null
	for container in dive.dive_map.containers:
		if container != null and str(container.container_id) == "hospital_emergency_store":
			return container
	return null


func _dispose_fixture(fixture: Dictionary) -> void:
	var viewport = fixture.get("viewport")
	if viewport != null and is_instance_valid(viewport):
		viewport.queue_free()
	await get_tree().process_frame


func _settle(frames: int = 3) -> void:
	for _frame in range(frames):
		await get_tree().process_frame


func _press_key(viewport: SubViewport, keycode: int) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	viewport.push_input(press, true)
	await get_tree().process_frame
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	viewport.push_input(release, true)
	await get_tree().process_frame


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Disease and epidemic flow test failed: " + message)
