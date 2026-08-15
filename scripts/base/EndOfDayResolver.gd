class_name EndOfDayResolver
extends RefCounted

const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const ReportStateScript := preload("res://scripts/data/ReportState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const ProductionSystemScript := preload("res://scripts/base/ProductionSystem.gd")
const DivingEquipmentSystemScript := preload("res://scripts/base/DivingEquipmentSystem.gd")
const PolicyStateScript := preload("res://scripts/data/PolicyState.gd")
const StormSystemScript := preload("res://scripts/base/StormSystem.gd")
const SectorPersistenceSystemScript := preload("res://scripts/diving/SectorPersistenceSystem.gd")
const CampaignProgressionSystemScript := preload("res://scripts/base/CampaignProgressionSystem.gd")
const SettlementEventSystemScript := preload("res://scripts/base/SettlementEventSystem.gd")
const MissionSystemScript := preload("res://scripts/base/MissionSystem.gd")
const CareerProgressionSystemScript := preload("res://scripts/base/CareerProgressionSystem.gd")
const WorkerAssignmentSystemScript := preload("res://scripts/base/WorkerAssignmentSystem.gd")
const BuildingWorkSystemScript := preload("res://scripts/base/BuildingWorkSystem.gd")
const InjuryRecoverySystemScript := preload("res://scripts/base/InjuryRecoverySystem.gd")
const MedicalCareSystemScript := preload("res://scripts/base/MedicalCareSystem.gd")
const DiseaseSystemScript := preload("res://scripts/base/DiseaseSystem.gd")
const RationAllocationSystemScript := preload("res://scripts/base/RationAllocationSystem.gd")
const WorkPaceSystemScript := preload("res://scripts/base/WorkPaceSystem.gd")
const CompetencySystemScript := preload("res://scripts/base/CompetencySystem.gd")
const ProfessionTalentSystemScript := preload("res://scripts/base/ProfessionTalentSystem.gd")

const TALENT_CRISIS_PORTIONING := "kucharz_porcjowanie_kryzysowe"
const TALENT_COMFORTING_MEAL := "kucharz_pokrzepiajacy_posilek"
const TALENT_PROPHYLACTICIAN := "medyk_profilaktyk"
const TALENT_MEDIATOR := "organizator_mediator"
const TALENT_INSTRUCTOR := "organizator_instruktor"

var _ration_by_survivor: Dictionary = {}
var _storm_system = StormSystemScript.new()
var _persistence_system = SectorPersistenceSystemScript.new()
var _campaign_system = CampaignProgressionSystemScript.new()
var _settlement_event_system = SettlementEventSystemScript.new()
var _mission_system = MissionSystemScript.new()
var _injury_recovery_system = InjuryRecoverySystemScript.new()
var _career_progression_system = CareerProgressionSystemScript.new()
var _worker_assignment_system = WorkerAssignmentSystemScript.new()
var _ration_allocation_system = RationAllocationSystemScript.new()
var _building_work_system = BuildingWorkSystemScript.new()
var _medical_care_system = MedicalCareSystemScript.new()
var _disease_system = DiseaseSystemScript.new()
var _profession_talent_system = ProfessionTalentSystemScript.new()
var _work_pace_system = WorkPaceSystemScript
var _project_worked_today: bool = false
var _community_hope_gain_today: int = 0
var _work_hope_delta_today: int = 0
var _capable_worker_snapshot: Dictionary = {}
var _worker_efficiency_snapshot: Dictionary = {}
var _committed_work_events: Array[Dictionary] = []
var _general_experience_awarded_ids: Dictionary = {}
var _practice_awarded_keys: Dictionary = {}
var _mentored_practice_keys: Dictionary = {}
var _instructor_awarded_ids: Dictionary = {}
var _ration_talent_ids_today: Array[String] = []
var _active_diver_ids: Dictionary = {}
var _medical_care_projection: Dictionary = {}
var _disease_hope_delta_today: int = 0
var _disease_outbreak_episode_today: int = 0

func resolve(state, dive_result = null, persist: bool = true):
	# Normalize legacy or externally inconsistent rosters before freezing the day.
	# An already locked plan remains immutable; later participant capture filters
	# its frozen IDs through the current survivor state and work capability.
	_worker_assignment_system.reconcile_assignments(state)
	if state.has_method("lock_day_plan") and state.current_day_plan != null and not bool(state.current_day_plan.locked):
		state.lock_day_plan(state.current_expedition_setup)
	var report = ReportStateScript.new()
	report.title = "Raport końca dnia %d" % state.day
	report.day = state.day
	report.includes_dive = dive_result != null
	_ration_by_survivor.clear()
	_project_worked_today = false
	_community_hope_gain_today = 0
	_work_hope_delta_today = 0
	_disease_hope_delta_today = 0
	_disease_outbreak_episode_today = 0
	_medical_care_projection.clear()
	_committed_work_events.clear()
	_general_experience_awarded_ids.clear()
	_practice_awarded_keys.clear()
	_mentored_practice_keys.clear()
	_instructor_awarded_ids.clear()
	_ration_talent_ids_today.clear()
	_active_diver_ids.clear()
	_capture_capable_worker_snapshot(state)
	var previous_pressure = state.pressure_state

	_apply_dive_result(state, dive_result, report)
	_resolve_fishing(state, report)
	_resolve_kitchen_processing(state, report)
	_resolve_workshop_and_repairs(state, report)
	_resolve_medical_care(state, report)
	_resolve_community_work(state, report)
	_resolve_rations(state, report)
	_resolve_hunger(state, report)
	_resolve_fatigue(state, dive_result, report)
	_resolve_diseases(state, report)
	_resolve_work_tension(state, report)
	_resolve_hope(state, dive_result, report)
	_resolve_career_progression(state, report)
	_resolve_morale(state, report)
	_resolve_conflicts(state, report)
	_resolve_storm_damage(state, report)
	_resolve_deaths(state, dive_result, report)
	_campaign_system.resolve_day_outcome(state, report)
	_mission_system.reconcile(state)
	state.last_end_day_report = report
	_advance_day(state, report)
	state.prepare_pressure_for_day(previous_pressure, dive_result)
	# Resolve the autoload dynamically so standalone domain tests can still use
	# canonical fallbacks, while production receives the already validated data.
	var tree_root = Engine.get_main_loop().root
	var database = tree_root.get_node_or_null("GameDatabase") if tree_root != null else null
	var event_definitions: Dictionary = database.settlement_events if database != null else {}
	var event_balance = database.settlement_event_balance if database != null else null
	var pending_event = _settlement_event_system.prepare_event_for_day(
		state,
		event_definitions,
		state.pressure_state,
		event_balance
	)
	_generate_morning_report(state, report)
	if pending_event != null and state.last_morning_report != null:
		state.last_morning_report.add_warning("Poranek przyniósł wydarzenie wymagające decyzji Przystani.")
	if state.has_method("archive_end_day_report"):
		state.archive_end_day_report(report)
	if state.current_phase not in [GamePhaseScript.Phase.GAME_OVER, GamePhaseScript.Phase.ENDING]:
		state.current_phase = GamePhaseScript.Phase.END_DAY_REPORT
	if persist:
		_save_game(state, report)
	return report

func _apply_dive_result(state, dive_result, report) -> void:
	if dive_result == null:
		report.add_entry("Tego dnia nie zorganizowano wyprawy.")
		return
	_active_diver_ids[str(dive_result.diver_id)] = true
	var diving_station = state.find_building_by_definition("diving_station")
	var station_id := str(diving_station.id) if diving_station != null else ""
	var station_pace := _work_pace_system.pace_for_building(state, diving_station)
	var station_support_ids := _expedition_support_worker_ids(state, diving_station, str(dive_result.diver_id))
	if bool(dive_result.diver_dead):
		_apply_diver_death(state, dive_result, report)
	_append_dive_disease_exposures(state, dive_result, report)

	_campaign_system.apply_dive_result(state, dive_result, report)
	for resource_id in dive_result.collected_items.keys():
		var amount = int(dive_result.collected_items[resource_id])
		state.resources.add_amount(resource_id, amount)
		report.add_entry("Z wyprawy odzyskano %d x %s." % [amount, ResourceIdsScript.display_name(resource_id)])

	for survivor in dive_result.rescued_survivors:
		if survivor == null:
			continue
		if state.find_survivor(str(survivor.id)) != null:
			report.add_warning("Pominięto powtórny zapis uratowanego mieszkańca %s." % survivor.display_name)
			continue
		state.survivors.append(survivor)
		var condition := "po stabilizacji" if not survivor.injury_states.has("critical_rescue") else "w stanie krytycznym"
		report.add_entry("Uratowano %s (%s). Dołącza do Przystani %s." % [survivor.display_name, survivor.profession, condition])

	var persistence_summary := _persistence_system.apply_result(state.underwater_world, dive_result)
	if int(persistence_summary.buoys) > 0:
		report.add_entry("Ustawiono %d trwałą boję orientacyjną." % int(persistence_summary.buoys))
	if int(persistence_summary.shortcuts) > 0:
		report.add_entry("Otwarto %d trwały skrót pod wodą." % int(persistence_summary.shortcuts))
	if int(persistence_summary.heavy_objects) > 0:
		report.add_entry("Oznaczono %d ciężki obiekt do wydobycia." % int(persistence_summary.heavy_objects))
	if int(persistence_summary.backpacks) > 0:
		report.add_entry("Zaktualizowano stan odzyskiwanego plecaka.")
	if int(persistence_summary.dropped_loot) == 1:
		report.add_entry("Zaktualizowano stan porzuconego pakunku pod wodą.")
	elif int(persistence_summary.dropped_loot) > 1:
		report.add_entry("Zaktualizowano stan %d porzuconych pakunków pod wodą." % int(persistence_summary.dropped_loot))
	for outcome in dive_result.rescue_outcomes.values():
		if str(outcome.get("status", "")) == "dead":
			report.add_warning("Ocalały holowany przez nurka nie przeżył utraty wyprawy.")

	if dive_result.suit_condition_remaining < 100:
		report.add_warning("Kombinezon wrócił w stanie %d%%." % dive_result.suit_condition_remaining)
	if dive_result.cold_exposure >= 25.0:
		report.add_warning("Nurek wrócił wychłodzony: %.0f%% ekspozycji na zimno." % dive_result.cold_exposure)
	if dive_result.repair_kit_uses > 0:
		report.add_entry("Podczas wyprawy zużyto zestaw naprawczy do załatania kombinezonu.")
	if not dive_result.noise_events.is_empty():
		var noise_labels: Array[String] = []
		for action_id in dive_result.noise_events:
			noise_labels.append(_noise_action_display_name(str(action_id)))
		report.add_entry("Zarejestrowane źródła hałasu: %s." % ", ".join(noise_labels))
	for risk_event in dive_result.risk_events:
		if str(risk_event).begins_with("threat_attack:"):
			report.add_warning("Nurek został zaatakowany przez podwodne zagrożenie.")
		elif str(risk_event).begins_with("operator_rescue:"):
			report.add_warning("Operator liny awaryjnie wyciągnął nieprzytomnego nurka.")
	if dive_result.emergency_extraction and not dive_result.lost_items.is_empty():
		var lost_count := 0
		for amount in dive_result.lost_items.values():
			lost_count += int(amount)
		report.add_warning("Awaryjne wyciągnięcie uratowało nurka, ale utracono %d sztuk niesionego łupu." % lost_count)

	if dive_result.diver_dead:
		var removed_gear := DivingEquipmentSystemScript.new().apply_lost_gear(state, dive_result.lost_gear)
		var backpack_gear := _recoverable_gear_for_lost_backpack(removed_gear, dive_result.recovered_gear_ids)
		var backpack_is_empty: bool = dive_result.lost_items.is_empty() and backpack_gear.is_empty()
		for gear_id in removed_gear:
			var definition = ResourceLoader.load("res://data/diving_gear/%s.tres" % gear_id)
			report.add_warning("Utracono wyposażenie: %s." % (definition.display_name if definition != null else gear_id))
		state.underwater_world.dead_divers[dive_result.diver_id] = dive_result.body_location_if_dead
		state.underwater_world.lost_backpacks[dive_result.diver_id] = {
			"diver_id": dive_result.diver_id,
			"landmark_id": dive_result.body_location_if_dead,
			"world_position": dive_result.death_world_position,
			"items": dive_result.lost_items.duplicate(true),
			"gear_ids": backpack_gear,
			"lost_on_day": state.day,
			"recovered": backpack_is_empty,
		}
		var report_landmark_id := str(dive_result.body_location_if_dead).strip_edges()
		if report_landmark_id.is_empty():
			report_landmark_id = str(dive_result.backpack_location_if_lost).get_slice("@", 0).strip_edges()
		report.add_warning("Nurek nie wrócił. Plecak pozostał w rejonie: %s." % _landmark_report_label(state, report_landmark_id))
	else:
		var restored_gear := DivingEquipmentSystemScript.new().restore_recovered_gear(state, dive_result.recovered_gear_ids)
		for gear_id in restored_gear:
			var definition = ResourceLoader.load("res://data/diving_gear/%s.tres" % gear_id)
			report.add_entry("Odzyskano wyposażenie: %s." % (definition.display_name if definition != null else gear_id))
		var diver = state.find_survivor(dive_result.diver_id)
		if diver != null:
			if dive_result.health_remaining >= 0:
				diver.health = clampi(dive_result.health_remaining, 0, diver.get_max_health())
			for injury_id in dive_result.diver_injuries:
				if not diver.injury_states.has(str(injury_id)):
					diver.injury_states.append(str(injury_id))
				report.add_warning("%s wraca z urazem: %s." % [diver.display_name, _injury_display_name(str(injury_id))])
			var levels_gained: int = diver.add_experience(dive_result.experience_gained)
			if dive_result.experience_gained > 0:
				report.add_entry("%s zdobywa %d PD za wyprawę." % [diver.display_name, dive_result.experience_gained])
			if levels_gained > 0:
				report.add_entry("%s osiąga poziom %d i otrzymuje %d punkt rozwoju." % [diver.display_name, diver.level, levels_gained])
			# The expedition consumes today's work, not the persistent staffing
			# decision. Restore the status from the building roster instead of
			# silently dismissing a living diver after every return.
			_worker_assignment_system.reconcile_assignments(state)
			report.add_entry("Nurek wrócił z %.0f jednostkami tlenu." % dive_result.oxygen_remaining)
	_commit_work_event(
		"nurek",
		"dive",
		[str(dive_result.diver_id)],
		false,
		not bool(dive_result.diver_dead),
		station_id,
		station_pace
	)
	if not station_support_ids.is_empty():
		_commit_work_event("nurek", "expedition_support", station_support_ids, false, true, station_id, station_pace)


func _apply_diver_death(state, dive_result, report) -> void:
	var diver_id := str(dive_result.diver_id)
	var diver = state.find_survivor(diver_id)
	if diver == null:
		return
	var was_dead := int(diver.status) == SurvivorStateScript.Status.DEAD
	diver.status = SurvivorStateScript.Status.DEAD
	diver.health = 0
	_remove_worker_from_snapshot(diver_id)
	_worker_assignment_system.reconcile_assignments(state)
	if not was_dead:
		report.add_warning("%s zginął podczas wyprawy." % diver.display_name)
	diver.disease_cases.clear()


func _append_dive_disease_exposures(state, dive_result, report) -> void:
	if state == null or state.disease_campaign == null or dive_result == null:
		return
	var added := 0
	for exposure in dive_result.disease_exposures:
		if exposure == null or not exposure.has_method("detached_copy"):
			continue
		var detached = exposure.detached_copy()
		if detached == null:
			continue
		state.disease_campaign.pending_exposures.append(detached)
		added += 1
	if added > 0:
		report.add_entry("Wynik wyprawy przekazuje %d narażenie chorobowe do nocnego rozliczenia." % added)


func _recoverable_gear_for_lost_backpack(removed_base_gear: Array[String], recovered_gear: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for gear_id in removed_base_gear:
		_append_recoverable_gear(result, str(gear_id))
	# Sprzęt wyjęty podczas tej wyprawy ze starego plecaka nie trafił jeszcze do
	# DivingEquipmentState. Po śmierci musi więc przejść bezpośrednio do nowego plecaka.
	for gear_id in recovered_gear:
		_append_recoverable_gear(result, str(gear_id))
	return result

func _append_recoverable_gear(target: Array[String], gear_id: String) -> void:
	if gear_id.is_empty() or target.has(gear_id):
		return
	var path := "res://data/diving_gear/%s.tres" % gear_id
	if not ResourceLoader.exists(path):
		return
	var definition = ResourceLoader.load(path)
	if definition == null or bool(definition.is_emergency_default) or str(definition.equipment_slot).is_empty():
		return
	target.append(gear_id)

func _resolve_fishing(state, report) -> void:
	var building = state.find_building_by_definition("fishing_hut")
	var staffed_building = _staffed_active_building(state, "fishing_hut")
	var capabilities := (
		_building_capabilities("fishing_hut", building.level)
		if building != null
		else {}
	)
	var workforce := _building_workforce(state, staffed_building, "production_bonus")
	var integrity := int(state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY))
	var projection: Dictionary = _building_work_system.project_fishing(
		capabilities,
		workforce,
		_building_work_pace(state, building),
		integrity,
		float(state.platform.fishing_pressure)
	)
	state.platform.fishing_pressure = float(projection.get(
		"fishing_pressure_after_catch",
		state.platform.fishing_pressure
	))
	if str(projection.get("blocker_code", "")) == BuildingWorkSystemScript.BLOCKER_INVALID_CAPABILITIES:
		report.add_warning("Chata Rybacka nie ma poprawnych danych produkcji i nie może dziś łowić.")
		return
	if not bool(projection.get("worked", false)):
		return
	var worker_ids: Array[String] = []
	worker_ids.assign(projection.get("worker_ids", []))
	_commit_building_work(state, staffed_building, "fishing", worker_ids)
	var produced_food := int(projection.get("food_produced", 0))
	if produced_food <= 0:
		report.add_warning("Chata Rybacka wróciła dziś bez połowu.")
		return
	state.resources.add_amount(ResourceIdsScript.FOOD, produced_food)
	report.add_entry("Chata Rybacka dostarczyła %d jedzenia." % produced_food)
	if state.platform.fishing_pressure >= 0.25:
		report.add_warning("Presja na łowisko wynosi %d%% i ogranicza kolejne połowy." % int(round(state.platform.fishing_pressure * 100.0)))

func _resolve_kitchen_processing(state, report) -> void:
	var building = _staffed_active_building(state, "kitchen")
	if building == null:
		return
	var capabilities := _building_capabilities("kitchen", building.level)
	var efficiency := float(capabilities.get("ration_efficiency", 0.0))
	efficiency += _specialist_bonus_total(state, building, "ration_efficiency_bonus")
	efficiency *= _work_pace_system.output_multiplier(_building_work_pace(state, building))
	efficiency = _ration_allocation_system.normalized_efficiency(efficiency)
	report.add_entry("Kuchnia jest gotowa ograniczyć koszt faktycznie wydanych racji o %d%%." % int(round(efficiency * 100.0)))

func _resolve_workshop_and_repairs(state, report) -> void:
	var workshop = _staffed_active_building(state, "workshop")
	var workshop_worker_ids := _snapshot_worker_ids(state, workshop)
	_project_worked_today = false
	if workshop == null:
		return
	var production_result: Dictionary = ProductionSystemScript.new().resolve_workshop_queue(
		state,
		report,
		_building_work_pace(state, workshop),
		true,
		_building_workforce(state, workshop, "").get("talent_ids", [])
	)
	if bool(production_result.get("worked", false)):
		_commit_building_work(state, workshop, "craft_diving_gear", workshop_worker_ids)
	elif _resolve_heavy_object_recovery(state, report):
		# Jedno odzyskanie jest atomową transakcją świata i używa stałej,
		# normalnej procedury zamiast mnożenia nagrody ciężkiego obiektu.
		_commit_building_work(state, workshop, "heavy_recovery", workshop_worker_ids, WorkPaceSystemScript.WORK_PACE_NORMAL)
	elif _resolve_workshop_repairs(state, report):
		_commit_building_work(state, workshop, "platform_repair", workshop_worker_ids)

func _resolve_heavy_object_recovery(state, report) -> bool:
	var workshop = _staffed_active_building(state, "workshop")
	if workshop == null:
		return false
	var capabilities := _building_capabilities("workshop", workshop.level)
	if not bool(capabilities.get("heavy_recovery_enabled", false)):
		return false
	for object_id in state.underwater_world.marked_heavy_objects.duplicate():
		var definition: Dictionary = state.underwater_world.blueprint.get_heavy_object(str(object_id))
		if definition.is_empty():
			continue
		for resource_id in definition.get("rewards", {}).keys():
			state.resources.add_amount(str(resource_id), int(definition.rewards[resource_id]))
		state.underwater_world.marked_heavy_objects.erase(str(object_id))
		if not state.underwater_world.recovered_heavy_objects.has(str(object_id)):
			state.underwater_world.recovered_heavy_objects.append(str(object_id))
		report.add_entry("Warsztat wydobył ciężki obiekt: %s." % str(definition.get("display_name", object_id)))
		return true
	return false

func _resolve_medical_care(state, report) -> void:
	var infirmary = state.find_building_by_definition("infirmary")
	var capabilities: Dictionary = {}
	if infirmary != null and infirmary.is_active():
		capabilities = _building_capabilities("infirmary", infirmary.level)
	var workforce := _building_workforce(state, infirmary, "healing_bonus") if infirmary != null and infirmary.is_active() else {
		"worker_count": 0,
		"worker_ids": [] as Array[String],
		"worker_units": 0.0,
		"specialist_bonus": 0.0,
	}
	var recovery_multiplier := float(state.difficulty_profile.recovery_speed_multiplier) if state.difficulty_profile != null else 1.0
	var priorities: Array[String] = []
	if state.current_day_plan != null:
		priorities.assign(state.current_day_plan.medical_priority_survivor_ids)
	_medical_care_projection = _medical_care_system.project(
		capabilities,
		workforce,
		_building_work_pace(state, infirmary),
		recovery_multiplier,
		int(state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS)),
		state.survivors,
		_disease_definitions(),
		priorities,
		workforce.get("talent_ids", [])
	)
	var blocker_code := str(_medical_care_projection.get("blocker_code", ""))
	if blocker_code == MedicalCareSystemScript.BLOCKER_INVALID_CAPABILITIES:
		report.add_warning("Lecznica nie ma poprawnych danych leczenia i nie może dziś działać.")
		return
	var apply_result := _medical_care_system.apply(state, _medical_care_projection)
	if not bool(apply_result.get("applied", false)):
		report.add_warning("Nie udało się atomowo zastosować zaplanowanej opieki medycznej.")
		return
	if bool(_medical_care_projection.get("worked", false)):
		for patient_result in _medical_care_projection.get("patients", []):
			var survivor = state.find_survivor(str(patient_result.get("survivor_id", "")))
			if survivor == null:
				continue
			var treatment_names: Array[String] = []
			for treatment in patient_result.get("disease_treatments", []):
				treatment_names.append(str(treatment.get("display_name", treatment.get("disease_id", "choroba"))))
			var detail := ""
			if not treatment_names.is_empty():
				detail = "; terapia: %s" % ", ".join(treatment_names)
			report.add_entry("%s otrzymuje opiekę medyczną i odzyskuje %d zdrowia%s." % [
				survivor.display_name,
				int(patient_result.get("health_gain", 0)),
				detail,
			])
		var worker_ids: Array[String] = []
		worker_ids.assign(_medical_care_projection.get("worker_ids", []))
		_commit_building_work(state, infirmary, "medical_care", worker_ids)
	if bool(_medical_care_projection.get("medicine_shortage", false)):
		report.add_warning("Lecznicy zabrakło leków dla kolejnych pacjentów.")


func _resolve_community_work(state, report) -> void:
	_community_hope_gain_today = 0
	var community_house = _staffed_active_building(state, "community_house")
	if community_house == null:
		return
	var capabilities := _building_capabilities("community_house", community_house.level)
	var workforce := _building_workforce(state, community_house, "hope_bonus")
	var projection: Dictionary = _building_work_system.project_community_work(
		capabilities,
		workforce,
		_building_work_pace(state, community_house)
	)
	if str(projection.get("blocker_code", "")) == BuildingWorkSystemScript.BLOCKER_INVALID_CAPABILITIES:
		report.add_warning("Dom Wspólnoty nie ma poprawnych danych Nadziei i nie może dziś działać.")
		return
	if not bool(projection.get("worked", false)):
		return
	_community_hope_gain_today = int(projection.get("hope_gain", 0))
	var worker_ids: Array[String] = []
	worker_ids.assign(projection.get("worker_ids", []))
	_commit_building_work(state, community_house, "community", worker_ids)
	if _community_hope_gain_today <= 0:
		report.add_entry("Dom Wspólnoty nie wytworzył dziś dodatniego wkładu Nadziei.")
		return
	report.add_entry("Dom Wspólnoty wzmacnia Nadzieję o %d." % _community_hope_gain_today)

func _resolve_rations(state, report) -> void:
	_ration_by_survivor.clear()
	_ration_talent_ids_today.clear()
	var alive = state.get_alive_survivors()
	if alive.is_empty():
		return
	var food_per_adult := int(state.difficulty_profile.food_per_adult) if state.difficulty_profile != null else 4
	var available_food := int(state.resources.get_amount(ResourceIdsScript.FOOD))
	var ration_efficiency := 0.0
	var kitchen = _staffed_active_building(state, "kitchen")
	var kitchen_worker_ids := _snapshot_worker_ids(state, kitchen)
	if kitchen != null:
		ration_efficiency = float(_building_capabilities("kitchen", kitchen.level).get("ration_efficiency", 0.0))
		ration_efficiency += _specialist_bonus_total(state, kitchen, "ration_efficiency_bonus")
		ration_efficiency *= _work_pace_system.output_multiplier(_building_work_pace(state, kitchen))
	ration_efficiency = _ration_allocation_system.normalized_efficiency(ration_efficiency)
	var policy := int(state.active_policies.ration_policy) if state.active_policies != null else PolicyStateScript.RationPolicy.FULL
	if state.current_day_plan != null:
		policy = int(state.current_day_plan.ration_policy)
	var alive_ids: Array[String] = []
	for survivor in alive:
		alive_ids.append(str(survivor.id))
	var allocation := _ration_allocation_system.project(
		policy,
		alive_ids,
		available_food,
		food_per_adult,
		ration_efficiency,
		_planned_diver_id(state)
	)
	var allocation_cost := int(allocation.get("cost", 0))
	if allocation_cost > 0 and not state.resources.spend(ResourceIdsScript.FOOD, allocation_cost):
		for survivor_id in alive_ids:
			_ration_by_survivor[survivor_id] = RationAllocationSystemScript.RATION_NONE
		report.add_warning("Nie udało się wydać zaplanowanych racji; jedzenie pozostało w magazynie.")
		return
	var projected_rations: Dictionary = allocation.get("ration_by_survivor_id", {})
	for survivor_id in alive_ids:
		_ration_by_survivor[survivor_id] = str(projected_rations.get(survivor_id, RationAllocationSystemScript.RATION_NONE))
	_report_ration_allocation(state, allocation, report)
	if allocation_cost > 0:
		_ration_talent_ids_today.assign(_building_workforce(state, kitchen, "").get("talent_ids", []))
		_commit_building_work(state, kitchen, "ration_preparation", kitchen_worker_ids)


func _planned_diver_id(state) -> String:
	if state.current_day_plan != null and state.current_day_plan.expedition_setup != null:
		return str(state.current_day_plan.expedition_setup.diver_id)
	return ""


func _report_ration_allocation(state, allocation: Dictionary, report) -> void:
	var requested_policy := int(allocation.get("requested_policy", PolicyStateScript.RationPolicy.FULL))
	var actual_policy := int(allocation.get("actual_policy", PolicyStateScript.RationPolicy.NONE))
	var available_food := int(allocation.get("available_food", 0))
	var allocation_cost := int(allocation.get("cost", 0))
	var half_cost := int(allocation.get("half_cost", 0))
	var full_cost := int(allocation.get("full_cost", 0))
	var full_ids: Array[String] = []
	full_ids.assign(allocation.get("full_recipient_ids", []))
	var half_ids: Array[String] = []
	half_ids.assign(allocation.get("half_recipient_ids", []))
	var unfed_ids: Array[String] = []
	unfed_ids.assign(allocation.get("unfed_recipient_ids", []))

	if requested_policy == PolicyStateScript.RationPolicy.NONE:
		report.add_warning("Zgodnie z planem dnia nie wydano racji. Bez racji: %s; zapas %d jedzenia zachowano." % [_ration_recipient_names(state, unfed_ids), available_food])
		return

	if requested_policy == PolicyStateScript.RationPolicy.DIVER_PRIORITY:
		if not bool(allocation.get("diver_valid", false)):
			if allocation_cost > 0:
				report.add_warning("Brak poprawnego żyjącego nurka — zastosowano grupowy fallback. Pół racji otrzymali: %s. Zużyto %d jedzenia." % [_ration_recipient_names(state, half_ids), allocation_cost])
			else:
				report.add_warning("Brak poprawnego żyjącego nurka — grupowy fallback wymaga %d jedzenia. Bez racji: %s; zapas %d zachowano." % [half_cost, _ration_recipient_names(state, unfed_ids), available_food])
			return
		var diver_id := str(allocation.get("diver_id", ""))
		var diver_ration := str(allocation.get("ration_by_survivor_id", {}).get(diver_id, RationAllocationSystemScript.RATION_NONE))
		if allocation_cost <= 0:
			report.add_warning("Zapas %d jedzenia nie wystarcza nawet na pół racji dla nurka %s (potrzeba %d). Bez racji: %s; cały zapas zachowano." % [
				available_food,
				_ration_recipient_names(state, [diver_id]),
				int(allocation.get("diver_half_cost", 0)),
				_ration_recipient_names(state, unfed_ids),
			])
			return
		var other_half_ids: Array[String] = []
		for survivor_id in half_ids:
			if survivor_id != diver_id:
				other_half_ids.append(survivor_id)
		report.add_warning("Pierwszeństwo nurka: %s otrzymuje %s. Pozostali z połową racji: %s. Bez racji: %s. Zużyto %d jedzenia." % [
			_ration_recipient_names(state, [diver_id]),
			_ration_display_name(diver_ration),
			_ration_recipient_names(state, other_half_ids),
			_ration_recipient_names(state, unfed_ids),
			allocation_cost,
		])
		return

	if actual_policy == PolicyStateScript.RationPolicy.FULL:
		report.add_entry("Pełną rację otrzymali: %s. Zużyto %d jedzenia." % [_ration_recipient_names(state, full_ids), allocation_cost])
		return
	if actual_policy == PolicyStateScript.RationPolicy.HALF:
		if requested_policy == PolicyStateScript.RationPolicy.FULL:
			report.add_warning("Na pełne racje potrzeba %d jedzenia; zastosowano grupowy fallback. Pół racji otrzymali: %s. Zużyto %d jedzenia." % [full_cost, _ration_recipient_names(state, half_ids), allocation_cost])
		else:
			report.add_warning("Pół racji otrzymali: %s. Zużyto %d jedzenia." % [_ration_recipient_names(state, half_ids), allocation_cost])
		return
	report.add_warning("Na grupową połowę racji potrzeba %d jedzenia, a dostępne jest %d. Bez racji: %s; cały zapas zachowano." % [half_cost, available_food, _ration_recipient_names(state, unfed_ids)])


func _ration_recipient_names(state, survivor_ids: Array) -> String:
	var names: Array[String] = []
	for survivor_id in survivor_ids:
		var survivor = state.find_survivor(str(survivor_id))
		names.append(str(survivor.display_name) if survivor != null else str(survivor_id))
	return "nikt" if names.is_empty() else ", ".join(names)


func _ration_display_name(ration: String) -> String:
	match ration:
		RationAllocationSystemScript.RATION_FULL:
			return "pełną rację"
		RationAllocationSystemScript.RATION_HALF:
			return "pół racji"
	return "brak racji"

func _resolve_hunger(state, report) -> void:
	for survivor in state.get_alive_survivors():
		var ration = str(_ration_by_survivor.get(survivor.id, "none"))
		match ration:
			"full":
				survivor.hunger = max(survivor.hunger - 18, 0)
			"half":
				survivor.hunger = min(survivor.hunger + 10, 100)
			_:
				survivor.hunger = min(survivor.hunger + 25, 100)
	var has_hungry_survivor = false
	for survivor in state.get_alive_survivors():
		if survivor.hunger >= 40:
			has_hungry_survivor = true
			break
	if has_hungry_survivor:
		report.add_warning("Część mieszkańców zaczyna odczuwać poważny głód.")

func _resolve_fatigue(state, dive_result, report) -> void:
	var worked_pace_by_survivor: Dictionary = {}
	for event in _committed_work_events:
		var pace := _work_pace_system.normalize_pace(str(event.get("work_pace", WorkPaceSystemScript.WORK_PACE_NORMAL)))
		for survivor_id in event.get("worker_ids", []):
			var normalized_id := str(survivor_id)
			if (
				not worked_pace_by_survivor.has(normalized_id)
				or _work_pace_system.worker_fatigue_gain(pace)
				> _work_pace_system.worker_fatigue_gain(str(worked_pace_by_survivor[normalized_id]))
			):
				worked_pace_by_survivor[normalized_id] = pace
	var diver_id := str(dive_result.diver_id) if dive_result != null else ""
	for survivor in state.get_alive_survivors():
		var previous: int = survivor.fatigue
		if survivor.id == diver_id and worked_pace_by_survivor.has(str(survivor.id)):
			var dive_fatigue := _work_pace_system.diver_fatigue_gain(
				float(dive_result.dive_duration),
				str(worked_pace_by_survivor[survivor.id])
			)
			dive_fatigue = maxi(dive_fatigue - CompetencySystemScript.work_fatigue_reduction(survivor), 0)
			survivor.fatigue = mini(survivor.fatigue + dive_fatigue, 100)
		elif worked_pace_by_survivor.has(str(survivor.id)):
			var fatigue_gain := _work_pace_system.worker_fatigue_gain(str(worked_pace_by_survivor[survivor.id]))
			fatigue_gain = maxi(fatigue_gain - CompetencySystemScript.work_fatigue_reduction(survivor), 0)
			survivor.fatigue = mini(survivor.fatigue + fatigue_gain, 100)
		else:
			survivor.fatigue = maxi(survivor.fatigue - 12, 0)
		if survivor.fatigue >= 85 and previous < 85:
			report.add_warning("%s nie może nurkować i pracuje bardzo słabo; od 90 zmęczenia nie może pracować." % survivor.display_name)

func _resolve_diseases(state, report) -> void:
	var isolated_ids: Array[String] = []
	if state.current_day_plan != null:
		isolated_ids.assign(state.current_day_plan.isolated_survivor_ids)
	var infirmary = state.find_building_by_definition("infirmary")
	var formal_capacity := 0
	if infirmary != null and infirmary.is_active():
		formal_capacity = int(_building_capabilities("infirmary", infirmary.level).get("formal_isolation_capacity", 0))
	var adverse := _disease_system.adverse_conditions_active(state, _shelter_capacity(state))
	var difficulty_pressure := int(state.difficulty_profile.disease_pressure_modifier) if state.difficulty_profile != null else 0
	var treatment_commitments: Array = _medical_care_projection.get("disease_treatment_commitments", [])
	var infirmary_talent_ids: Array = []
	if infirmary != null and infirmary.is_active():
		infirmary_talent_ids.assign(_building_workforce(state, infirmary, "").get("talent_ids", []))
	var prophylaxis_active := infirmary_talent_ids.has(TALENT_PROPHYLACTICIAN)
	var prophylaxis_definition = _profession_talent_system.get_definition(TALENT_PROPHYLACTICIAN)
	var projection := _disease_system.project_day(
		state,
		_disease_definitions(),
		_ration_by_survivor,
		_committed_work_events,
		isolated_ids,
		treatment_commitments,
		{
			"formal_isolation_capacity": formal_capacity,
			"adverse_conditions_pressure": 1 if adverse else 0,
			"disease_pressure_modifier": difficulty_pressure,
			"contact_prophylaxis_reduction": int(prophylaxis_definition.parameters.get("contact_pressure_reduction", 1)) if prophylaxis_active and prophylaxis_definition != null else 0,
			"minimum_contact_pressure": int(prophylaxis_definition.parameters.get("minimum_contact_pressure", 1)) if prophylaxis_active and prophylaxis_definition != null else 1,
		}
	)
	if not bool(projection.get("valid", false)):
		report.add_warning("Nie udało się przygotować spójnego nocnego rozliczenia chorób (%s)." % str(projection.get("blocker_code", "invalid")))
		for warning in projection.get("warnings", []):
			report.add_warning(str(warning))
		return
	var apply_result := _disease_system.apply_day(state, projection)
	if not bool(apply_result.get("applied", false)):
		report.add_warning("Nie udało się atomowo zastosować nocnego rozliczenia chorób.")
		return
	_disease_hope_delta_today = int(apply_result.get("hope_delta", 0))
	_disease_outbreak_episode_today = int(projection.get("outbreak_episode", 0))
	for entry in projection.get("report_entries", []):
		report.add_entry(str(entry))
	for warning in projection.get("report_warnings", []):
		report.add_warning(str(warning))


func _resolve_work_tension(state, report) -> void:
	var work_by_building: Dictionary = {}
	for event in _committed_work_events:
		var building_id := str(event.get("building_id", ""))
		if building_id.is_empty():
			continue
		if not work_by_building.has(building_id):
			work_by_building[building_id] = {
				"work_pace": _work_pace_system.normalize_pace(str(event.get("work_pace", WorkPaceSystemScript.WORK_PACE_NORMAL))),
				"worker_ids": [] as Array[String],
			}
		var record: Dictionary = work_by_building[building_id]
		for survivor_id in event.get("worker_ids", []):
			var normalized_id := str(survivor_id)
			if not normalized_id.is_empty() and not record.worker_ids.has(normalized_id):
				record.worker_ids.append(normalized_id)
		work_by_building[building_id] = record

	var highest_intense_tension := 0
	var intense_worker_ids: Array[String] = []
	var intense_any := false
	var relieved_any := false
	var change_lines: Array[String] = []
	for building in state.buildings:
		if building == null:
			continue
		var building_id := str(building.id)
		var worked := work_by_building.has(building_id)
		var work_record: Dictionary = work_by_building.get(building_id, {})
		var recorded_worker_ids: Array = work_record.get("worker_ids", [])
		var pace := str(work_record.get("work_pace", _building_work_pace(state, building)))
		var transition: Dictionary = _work_pace_system.tension_transition(int(building.work_tension), pace, worked)
		var previous := int(transition.get("previous", building.work_tension))
		var current := int(transition.get("current", previous))
		building.work_tension = current
		if worked:
			change_lines.append("%s — %s, %d os.: %d→%d" % [
				_building_display_name(building),
				_work_pace_system.pace_label(pace),
				recorded_worker_ids.size(),
				previous,
				current,
			])
		elif previous != current:
			change_lines.append("%s — bez pracy: %d→%d" % [_building_display_name(building), previous, current])
		if bool(transition.get("relieved", false)):
			relieved_any = true
		if bool(transition.get("intense", false)):
			intense_any = true
			highest_intense_tension = maxi(highest_intense_tension, current)
			for survivor_id in recorded_worker_ids:
				if not intense_worker_ids.has(str(survivor_id)):
					intense_worker_ids.append(str(survivor_id))

	var intense_workforce_band := _work_pace_system.workforce_band(intense_worker_ids.size())
	if intense_any:
		_work_hope_delta_today = -mini(
			highest_intense_tension + intense_workforce_band,
			5
		)
	elif relieved_any:
		_work_hope_delta_today = 1
	else:
		_work_hope_delta_today = 0
	var hope_delta_before_mediator := _work_hope_delta_today
	if _work_hope_delta_today < 0 and _actual_community_worker_has_talent(state, TALENT_MEDIATOR):
		var mediator_definition = _profession_talent_system.get_definition(TALENT_MEDIATOR)
		var reduction := int(mediator_definition.parameters.get("negative_hope_delta_reduction", 1)) if mediator_definition != null else 1
		_work_hope_delta_today = mini(_work_hope_delta_today + maxi(reduction, 0), 0)
		report.add_entry("Mediator łagodzi nominalną karę Napięcia: %d→%d Nadziei." % [hope_delta_before_mediator, _work_hope_delta_today])
	if not change_lines.is_empty():
		report.add_entry("Napięcie pracy: %s." % "; ".join(change_lines))
	if _work_hope_delta_today < 0:
		report.add_warning("Forsowanie pracy: −%d nominalnej Nadziei (Napięcie %d + próg obsady %d)." % [
			abs(_work_hope_delta_today),
			highest_intense_tension,
			intense_workforce_band,
		])
	elif _work_hope_delta_today > 0:
		report.add_entry("Rozładowane Napięcie pracy wzmacnia nominalną Nadzieję o 1.")
	else:
		report.add_entry("Tempo pracy: 0 nominalnej Nadziei.")

func _resolve_hope(state, dive_result, report) -> void:
	var delta = _work_hope_delta_today
	if dive_result != null:
		if dive_result.diver_dead:
			delta -= 15
		else:
			delta += 4
			if dive_result.collected_items.size() > 0:
				delta += 2
			if dive_result.rescued_survivors.size() > 0:
				delta += 8 * dive_result.rescued_survivors.size()

	for ration in _ration_by_survivor.values():
		if ration == "half":
			delta -= 2
		elif ration == "none":
			delta -= 8

	delta += _community_hope_gain_today

	var unsheltered := maxi(state.get_alive_survivors().size() - _shelter_capacity(state), 0)
	if unsheltered > 0:
		var shelter_penalty := unsheltered * 4
		delta -= shelter_penalty
		report.add_warning("Brakuje suchego miejsca dla %d mieszkańców. Nadzieja spada o %d." % [unsheltered, shelter_penalty])

	if state.difficulty_profile != null:
		var hope_multiplier: float = state.difficulty_profile.hope_gain_multiplier if delta >= 0 else state.difficulty_profile.hope_loss_multiplier
		delta = int(round(float(delta) * hope_multiplier))
	var current = state.resources.get_amount(ResourceIdsScript.HOPE)
	state.resources.set_amount(ResourceIdsScript.HOPE, clamp(current + delta, 0, 100))
	var ordinary_after: int = state.resources.get_amount(ResourceIdsScript.HOPE)
	report.add_entry("Nadzieja: %d -> %d." % [current, ordinary_after])
	if _disease_hope_delta_today != 0:
		var disease_after: int = clampi(ordinary_after + _disease_hope_delta_today, 0, 100)
		state.resources.set_amount(ResourceIdsScript.HOPE, disease_after)
		report.add_entry("Zmiana epidemii (epizod %d): Nadzieja %d -> %d (%+d dokładnie raz)." % [
			_disease_outbreak_episode_today,
			ordinary_after,
			disease_after,
			_disease_hope_delta_today,
		])

func _resolve_morale(state, report) -> void:
	var hope: int = state.resources.get_amount(ResourceIdsScript.HOPE)
	var low_morale := 0
	for survivor in state.get_alive_survivors():
		var morale_before := int(survivor.morale)
		var pull := clampi(hope - survivor.morale, -5, 5)
		if pull < 0:
			pull = -maxi(abs(pull) - CompetencySystemScript.low_hope_morale_loss_reduction(survivor), 1)
		var ration := str(_ration_by_survivor.get(survivor.id, "none"))
		var ration_delta := 1 if ration == "full" else -2 if ration == "half" else -6
		if ration == "half" and _ration_talent_ids_today.has(TALENT_CRISIS_PORTIONING):
			var portioning_definition = _profession_talent_system.get_definition(TALENT_CRISIS_PORTIONING)
			ration_delta = int(portioning_definition.parameters.get("half_ration_morale_delta", -1)) if portioning_definition != null else -1
		elif ration == "full" and _ration_talent_ids_today.has(TALENT_COMFORTING_MEAL):
			var meal_definition = _profession_talent_system.get_definition(TALENT_COMFORTING_MEAL)
			var threshold := int(meal_definition.parameters.get("morale_threshold_exclusive", 40)) if meal_definition != null else 40
			if morale_before < threshold:
				ration_delta += int(meal_definition.parameters.get("morale_bonus", 1)) if meal_definition != null else 1
		survivor.morale = clampi(survivor.morale + pull + ration_delta, 0, 100)
		if survivor.morale < 20:
			low_morale += 1
	if low_morale > 0:
		report.add_warning("%d mieszkańców ma morale poniżej 20 i pracuje wyraźnie słabiej." % low_morale)

func _resolve_conflicts(state, report) -> void:
	if state.resources.get_amount(ResourceIdsScript.HOPE) < 40:
		report.add_warning("Niska Nadzieja zwiastuje kłótnie i odmowy pracy.")

func _resolve_storm_damage(state, report) -> void:
	if state.has_method("prepare_weather_for_day") and (state.weather == null or int(state.weather.day) != state.day):
		state.prepare_weather_for_day(state.day)
	var integrity = state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY)
	var is_storm: bool = state.weather != null and state.weather.has_method("is_storm") and bool(state.weather.is_storm())
	if not is_storm:
		return

	var damage_multiplier := float(state.difficulty_profile.storm_damage_multiplier) if state.difficulty_profile != null else 1.0
	var damage := _storm_system.calculate_damage(damage_multiplier)
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, max(integrity - damage, 0))
	report.add_warning("Nocny sztorm uszkodził platformę o %d punktów." % damage)

func _resolve_deaths(state, _dive_result, report) -> void:
	for survivor in state.get_alive_survivors():
		if survivor.hunger >= 100:
			survivor.health = max(survivor.health - 20, 0)
			report.add_warning("%s traci zdrowie przez skrajny głód." % survivor.display_name)
		if survivor.health <= 0:
			survivor.status = SurvivorStateScript.Status.DEAD
			report.add_warning("%s umiera." % survivor.display_name)
			survivor.disease_cases.clear()

	# Terminal residents must not reserve an invisible workplace. Temporary
	# illness, injury or exhaustion stays in the roster and naturally produces
	# zero through SurvivorState.work_efficiency().
	_worker_assignment_system.reconcile_assignments(state)

func _generate_morning_report(state, report) -> void:
	var morning = ReportStateScript.new()
	morning.title = "Poranny raport dnia %d" % state.day
	morning.day = state.day
	morning.add_entry("Jedzenia wystarczy na %.1f dnia." % state.get_food_days_left())
	morning.add_entry("Nadzieja społeczności: %d." % state.resources.get_amount(ResourceIdsScript.HOPE))
	if state.pressure_state != null:
		morning.add_entry("Sytuacja Przystani: %s." % _pressure_band_description(int(state.pressure_state.band)))
		for gate_id in state.pressure_state.critical_gates:
			var warning := _pressure_gate_warning(str(gate_id))
			if not warning.is_empty():
				morning.add_warning(warning)
		if bool(state.pressure_state.prefer_relief) and state.pressure_state.critical_gates.is_empty():
			morning.add_entry("Po ostatnich trudnościach dzień otrzymuje ograniczoną presję wydarzeń.")
	if state.story_flags != null and bool(state.story_flags.crisis_active):
		morning.add_warning("Kryzys przywództwa: odbuduj Nadzieję do %d. Pozostałe dni: %d." % [CampaignProgressionSystemScript.CRISIS_RECOVERY_HOPE, state.story_flags.crisis_days_remaining])
	if (
		state.story_flags != null
		and bool(state.story_flags.black_front_active)
		and int(state.day) > int(state.story_flags.junction_j7_activated_day) + 1
	):
		morning.add_warning(
			"Czarny Front za: %d dni. Integralność Przystani: %d%%; wymagane dokładnie 100%%." % [
				int(state.story_flags.black_front_days_remaining),
				state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY),
			]
		)
		morning.add_entry("Radio Północnej: %s" % _north_platform_radio_report(state.story_flags))
	if state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY) < 50:
		morning.add_warning("Platforma wymaga napraw.")
	state.last_morning_report = morning
	report.add_entry("Przygotowano raport na kolejny poranek.")


func _north_platform_radio_report(story) -> String:
	var total_days := maxi(int(story.black_front_days_total), 1)
	var remaining_days := clampi(int(story.black_front_days_remaining), 0, total_days)
	var elapsed_days := total_days - remaining_days
	if elapsed_days <= 2:
		return "dolne kondygnacje są zalane, pompy utrzymują część mieszkalną; wyłączono część lamp."
	if remaining_days > total_days / 2:
		return "wyłączono ogrzewanie i urządzenia pomocnicze. Pompy nadal wypychają wodę z części mieszkalnej."
	if remaining_days > 2:
		return "łączność działa z przerwami, a pompy pracują coraz wolniej na słabnącym wspólnym banku."
	return "krótkie transmisje przebijają się przez zakłócenia. Pompy nadal pracują, ale wspólny bank jest na granicy obciążenia."


func _pressure_band_description(band: int) -> String:
	match band:
		0:
			return "stabilna, zapasy pozwalają podejmować ambitniejsze decyzje"
		2:
			return "wysoka presja wydarzeń, ciężkie zdarzenia są ograniczone"
		3:
			return "stan krytyczny, reżyser nie dokłada kolejnej katastrofy"
		_:
			return "zwykła presja wydarzeń"


func _pressure_gate_warning(gate_id: String) -> String:
	match gate_id:
		"food_below_half_day":
			return "Zostało mniej niż pół dnia jedzenia — poranek preferuje pomoc zamiast dodatkowej straty."
		"hunger_critical":
			return "Co najmniej jedna osoba osiągnęła krytyczny poziom głodu."
		"hope_critical":
			return "Nadzieja jest krytycznie niska; ciężkie wydarzenia zostają wstrzymane."
		"integrity_critical":
			return "Integralność platformy jest krytyczna; ciężkie wydarzenia zostają wstrzymane."
		"workforce_critical":
			return "Została najwyżej jedna osoba zdolna do pracy."
		"diver_died_yesterday":
			return "Po śmierci nurka Przystań otrzymuje dzień regeneracji bez nowej ciężkiej presji."
	return ""

func _save_game(state, report) -> void:
	var root = Engine.get_main_loop().root
	var save_manager = root.get_node_or_null("SaveManager") if root != null else null
	if save_manager == null:
		report.add_warning("SaveManager nie jest dostępny w tym trybie uruchomienia.")
		return

	var error = save_manager.save_game(state)
	if error != OK:
		report.add_warning("Nie udało się zapisać kampanii. Kod błędu: %d." % error)

func _advance_day(state, _report) -> void:
	state.day += 1
	if state.has_method("prepare_weather_for_day"):
		state.prepare_weather_for_day(state.day)
	if state.current_phase not in [GamePhaseScript.Phase.CRISIS, GamePhaseScript.Phase.GAME_OVER, GamePhaseScript.Phase.ENDING]:
		state.current_phase = GamePhaseScript.Phase.DAY_START_REPORT
	state.begin_new_day_plan()

func _resolve_workshop_repairs(state, report) -> bool:
	var workshop = _staffed_active_building(state, "workshop")
	if workshop == null:
		return false
	var integrity: int = state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY)
	var capabilities := _building_capabilities("workshop", workshop.level)
	var workforce := _building_workforce(state, workshop, "repair_bonus")
	var repair_multiplier := float(state.difficulty_profile.repair_cost_multiplier) if state.difficulty_profile != null else 1.0
	var projection: Dictionary = _building_work_system.project_platform_repair(
		capabilities,
		workforce,
		_building_work_pace(state, workshop),
		integrity,
		int(state.resources.get_amount(ResourceIdsScript.SCRAP)),
		repair_multiplier,
		float(state.platform.repair_scrap_rounding_carry)
	)
	var blocker_code := str(projection.get("blocker_code", ""))
	if blocker_code == BuildingWorkSystemScript.BLOCKER_INVALID_CAPABILITIES:
		report.add_warning("Warsztat nie ma poprawnych danych automatycznej naprawy.")
		return false
	if str(projection.get("status_code", "")) == BuildingWorkSystemScript.STATUS_ZERO_OUTPUT:
		report.add_warning("Warsztat nie rozpoczął naprawy, ponieważ wydajność obsady była zbyt niska.")
		return false
	if blocker_code == BuildingWorkSystemScript.BLOCKER_INSUFFICIENT_SCRAP:
		report.add_warning("Warsztat nie naprawił platformy z powodu braku złomu.")
		return false
	if not bool(projection.get("worked", false)):
		return false
	var scrap_spent := int(projection.get("scrap_spent", 0))
	if scrap_spent > 0 and not state.resources.spend(ResourceIdsScript.SCRAP, scrap_spent):
		report.add_warning("Warsztat nie naprawił platformy z powodu braku złomu.")
		return false
	state.platform.repair_scrap_rounding_carry = float(projection.get(
		"rounding_carry_after",
		state.platform.repair_scrap_rounding_carry
	))
	state.resources.set_amount(
		ResourceIdsScript.PLATFORM_INTEGRITY,
		int(projection.get("integrity_after", integrity))
	)
	var repaired := int(projection.get("repair_applied", 0))
	report.add_entry("Warsztat naprawił platformę o %d punktów." % repaired)
	return true

func _capture_capable_worker_snapshot(state) -> void:
	_capable_worker_snapshot.clear()
	_worker_efficiency_snapshot.clear()
	if state == null:
		return
	var isolated_ids: Array[String] = []
	if state.current_day_plan != null:
		isolated_ids.assign(state.current_day_plan.isolated_survivor_ids)
	for building in state.buildings:
		if building == null:
			continue
		var worker_ids: Array[String] = []
		var efficiency_by_worker: Dictionary = {}
		if building.is_active():
			for survivor_id in _planned_worker_ids(state, building):
				var survivor = state.find_survivor(str(survivor_id))
				if (
					survivor != null
					and str(survivor.id) not in isolated_ids
					and str(survivor.current_assignment) == str(building.id)
					and survivor.can_work()
					and not worker_ids.has(str(survivor.id))
				):
					var normalized_id := str(survivor.id)
					worker_ids.append(normalized_id)
					efficiency_by_worker[normalized_id] = float(survivor.work_efficiency())
		_capable_worker_snapshot[str(building.id)] = worker_ids
		_worker_efficiency_snapshot[str(building.id)] = efficiency_by_worker


func _remove_worker_from_snapshot(survivor_id: String) -> void:
	if survivor_id.is_empty():
		return
	for building_id in _capable_worker_snapshot.keys():
		var worker_ids: Array[String] = []
		worker_ids.assign(_capable_worker_snapshot.get(building_id, []))
		worker_ids.erase(survivor_id)
		_capable_worker_snapshot[building_id] = worker_ids
		var efficiency_by_worker: Dictionary = _worker_efficiency_snapshot.get(building_id, {}).duplicate()
		efficiency_by_worker.erase(survivor_id)
		_worker_efficiency_snapshot[building_id] = efficiency_by_worker


func _expedition_support_worker_ids(state, diving_station, diver_id: String) -> Array[String]:
	var capable_ids := _snapshot_worker_ids(state, diving_station)
	capable_ids.erase(diver_id)
	var setup = state.current_day_plan.expedition_setup if state.current_day_plan != null else null
	if setup == null:
		setup = state.current_expedition_setup
	if setup == null:
		return capable_ids
	var frozen_ids: Array[String] = []
	var support_roles := [
		{"assigned": "operator_assigned", "survivor_id": "operator_survivor_id", "slot_index": 1},
		{"assigned": "technician_assigned", "survivor_id": "technician_survivor_id", "slot_index": 2},
	]
	var planned_ids := _planned_worker_ids(state, diving_station)
	for role in support_roles:
		if not bool(setup.get(str(role.assigned))):
			continue
		var survivor_id := str(setup.get(str(role.survivor_id)))
		# Starsze lub ręcznie utworzone setupy nie miały identyfikatorów ról.
		# Flaga roli nadal pozwala bezpiecznie odtworzyć osobę z zamrożonego slotu.
		var slot_index := int(role.slot_index)
		if survivor_id.is_empty() and slot_index < planned_ids.size():
			survivor_id = str(planned_ids[slot_index])
		if not survivor_id.is_empty() and capable_ids.has(survivor_id) and not frozen_ids.has(survivor_id):
			frozen_ids.append(survivor_id)
	return frozen_ids

func _planned_worker_ids(state, building) -> Array[String]:
	var result: Array[String] = []
	if state == null or building == null:
		return result
	var source: Array = building.assigned_survivor_ids
	if (
		state.current_day_plan != null
		and bool(state.current_day_plan.locked)
		and state.current_day_plan.worker_assignments.has(str(building.id))
	):
		source = state.current_day_plan.worker_assignments[str(building.id)]
	for survivor_id in source:
		var normalized_id := str(survivor_id)
		if not normalized_id.is_empty() and not result.has(normalized_id):
			result.append(normalized_id)
	return result

func _snapshot_worker_ids(state, building) -> Array[String]:
	if building == null or not building.is_active():
		return []
	var building_id := str(building.id)
	if _capable_worker_snapshot.has(building_id):
		var stored: Array[String] = []
		stored.assign(_capable_worker_snapshot[building_id])
		return stored
	var result: Array[String] = []
	var isolated_ids: Array = state.current_day_plan.isolated_survivor_ids if state != null and state.current_day_plan != null else []
	for survivor_id in _planned_worker_ids(state, building):
		var survivor = state.find_survivor(str(survivor_id))
		if survivor != null and survivor.can_work() and str(survivor.id) not in isolated_ids:
			result.append(str(survivor.id))
	return result

func _commit_building_work(
	state,
	building,
	action_id: String,
	worker_ids: Array,
	pace_override: String = ""
) -> void:
	if building == null or worker_ids.is_empty():
		return
	var profession_id := _career_progression_system.profession_for_building(str(building.definition_id))
	if profession_id.is_empty():
		return
	var pace := _building_work_pace(state, building) if pace_override.is_empty() else _work_pace_system.normalize_pace(pace_override)
	_commit_work_event(profession_id, action_id, worker_ids, false, true, str(building.id), pace)

func _commit_work_event(
	profession_id: String,
	action_id: String,
	worker_ids: Array,
	grant_general_experience: bool,
	grant_practice_experience: bool,
	building_id: String = "",
	work_pace: String = WorkPaceSystemScript.WORK_PACE_NORMAL
) -> void:
	if profession_id.is_empty() or worker_ids.is_empty():
		return
	var unique_worker_ids: Array[String] = []
	for survivor_id in worker_ids:
		var normalized_id := str(survivor_id)
		if not normalized_id.is_empty() and not unique_worker_ids.has(normalized_id):
			unique_worker_ids.append(normalized_id)
	if unique_worker_ids.is_empty():
		return
	_committed_work_events.append({
		"profession_id": profession_id,
		"action_id": action_id,
		"worker_ids": unique_worker_ids,
		"grant_general_experience": grant_general_experience,
		"grant_practice_experience": grant_practice_experience,
		"building_id": building_id,
		"work_pace": _work_pace_system.normalize_pace(work_pace),
	})


func _actual_community_worker_has_talent(state, talent_id: String) -> bool:
	if state == null or talent_id.is_empty():
		return false
	for event in _committed_work_events:
		if str(event.get("action_id", "")) != "community":
			continue
		var building = state.find_building(str(event.get("building_id", "")))
		if building == null or str(building.definition_id) != "community_house":
			continue
		for survivor_id in event.get("worker_ids", []):
			var survivor = state.find_survivor(str(survivor_id))
			if survivor != null and ProfessionTalentSystemScript.has_talent(survivor, talent_id):
				return true
	return false

func _resolve_career_progression(state, report) -> void:
	var summary_parts: Array[String] = []
	var milestone_entries: Array[String] = []
	# Ogólne PD wynikają z pełnienia zdolnej obsady aktywnego budynku,
	# niezależnie od tego, czy domena budynku mogła tego dnia wykonać efekt.
	# Nurek korzysta z osobnego wyniku wyprawy i nie otrzymuje tej nagrody drugi raz.
	for building in state.buildings:
		if building == null or not building.is_active():
			continue
		var profession_id := _career_progression_system.profession_for_building(str(building.definition_id))
		if profession_id.is_empty():
			continue
		for survivor_id in _snapshot_worker_ids(state, building):
			var normalized_id := str(survivor_id)
			if _active_diver_ids.has(normalized_id) or _general_experience_awarded_ids.has(normalized_id):
				continue
			var survivor = state.find_survivor(normalized_id)
			if survivor == null:
				continue
			_general_experience_awarded_ids[normalized_id] = true
			var staffing_result := _career_progression_system.record_work(survivor, profession_id, true, false)
			if staffing_result.is_empty():
				continue
			summary_parts.append("%s +%d PD za obsadę" % [str(staffing_result.survivor_name), int(staffing_result.general_experience_gained)])
			if int(staffing_result.get("levels_gained", 0)) > 0:
				milestone_entries.append("%s osiąga poziom %d i otrzymuje %d punkt rozwoju." % [
					str(staffing_result.survivor_name),
					int(staffing_result.current_level),
					int(staffing_result.levels_gained),
				])
	for event in _committed_work_events:
		var profession_id := str(event.get("profession_id", ""))
		for survivor_id in event.get("worker_ids", []):
			var normalized_id := str(survivor_id)
			var survivor = state.find_survivor(normalized_id)
			if survivor == null:
				continue
			var practice_key := "%s:%s" % [normalized_id, profession_id]
			var grant_general := bool(event.get("grant_general_experience", true)) and not _general_experience_awarded_ids.has(normalized_id)
			var grant_practice := bool(event.get("grant_practice_experience", true)) and not _practice_awarded_keys.has(practice_key)
			if not grant_general and not grant_practice:
				continue
			if grant_general:
				_general_experience_awarded_ids[normalized_id] = true
			if grant_practice:
				_practice_awarded_keys[practice_key] = true
			var result := _career_progression_system.record_work(survivor, profession_id, grant_general, grant_practice)
			if result.is_empty():
				continue
			var gains: Array[String] = []
			if int(result.get("general_experience_gained", 0)) > 0:
				gains.append("+%d PD" % int(result.general_experience_gained))
			if int(result.get("practice_gained", 0)) > 0:
				gains.append("+%d praktyki %s (%d/%d)" % [
					int(result.practice_gained),
					str(result.profession_name),
					int(result.current_practice),
					int(result.promotion_experience),
				])
			if not gains.is_empty():
				summary_parts.append("%s %s" % [str(result.survivor_name), " / ".join(gains)])
			if int(result.get("levels_gained", 0)) > 0:
				milestone_entries.append("%s osiąga poziom %d i otrzymuje %d punkt rozwoju." % [
					str(result.survivor_name),
					int(result.current_level),
					int(result.levels_gained),
				])
			if bool(result.get("reached_apprentice", false)):
				milestone_entries.append("%s zostaje uczniem w ścieżce %s." % [str(result.survivor_name), str(result.profession_name)])
			if bool(result.get("reached_promotion", false)):
				milestone_entries.append("%s opanował ścieżkę %s i może otrzymać drugą specjalizację w Domu Wspólnoty II." % [str(result.survivor_name), str(result.profession_name)])
	_resolve_instruction_bonuses(state, summary_parts, milestone_entries)
	if report == null:
		return
	if not summary_parts.is_empty():
		report.add_entry("Doświadczenie pracy: %s." % "; ".join(summary_parts))
	for entry in milestone_entries:
		report.add_entry(entry)


func _resolve_instruction_bonuses(state, summary_parts: Array[String], milestone_entries: Array[String]) -> void:
	if state == null:
		return
	var instructor_definition = _profession_talent_system.get_definition(TALENT_INSTRUCTOR)
	var practice_bonus := int(instructor_definition.parameters.get("practice_bonus", 10)) if instructor_definition != null else 10
	if practice_bonus <= 0:
		return
	for event in _committed_work_events:
		var profession_id := str(event.get("profession_id", ""))
		var profession_definition = _career_progression_system.get_profession_definition(profession_id)
		if profession_definition == null:
			continue
		var worker_ids: Array[String] = []
		for survivor_id in event.get("worker_ids", []):
			var normalized_id := str(survivor_id)
			if not normalized_id.is_empty() and not worker_ids.has(normalized_id):
				worker_ids.append(normalized_id)
		worker_ids.sort()
		var instructor_ids: Array[String] = []
		for survivor_id in worker_ids:
			var survivor = state.find_survivor(survivor_id)
			if (
				survivor != null
				and not _instructor_awarded_ids.has(survivor_id)
				and ProfessionTalentSystemScript.has_talent(survivor, TALENT_INSTRUCTOR)
			):
				instructor_ids.append(survivor_id)
		for instructor_id in instructor_ids:
			var candidates: Array[Dictionary] = []
			for target_id in worker_ids:
				if target_id == instructor_id:
					continue
				var target = state.find_survivor(target_id)
				var mentoring_key := "%s:%s" % [target_id, profession_id]
				if (
					target == null
					or ProfessionTalentSystemScript.has_talent(target, TALENT_INSTRUCTOR)
					or _mentored_practice_keys.has(mentoring_key)
				):
					continue
				var practice := int(target.get_job_experience(profession_id))
				if practice >= int(profession_definition.promotion_experience):
					continue
				candidates.append({"survivor": target, "survivor_id": target_id, "practice": practice, "key": mentoring_key})
			if candidates.is_empty():
				continue
			candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
				if int(left.practice) == int(right.practice):
					return str(left.survivor_id) < str(right.survivor_id)
				return int(left.practice) < int(right.practice)
			)
			var selected: Dictionary = candidates[0]
			var selected_survivor = selected.survivor
			var previous_practice := int(selected.practice)
			var current_practice := mini(previous_practice + practice_bonus, int(profession_definition.promotion_experience))
			var gained := current_practice - previous_practice
			if gained <= 0:
				continue
			selected_survivor.set_job_experience(profession_id, current_practice)
			_instructor_awarded_ids[instructor_id] = true
			_mentored_practice_keys[str(selected.key)] = true
			summary_parts.append("%s +%d praktyki %s od Instruktora (%d/%d)" % [
				str(selected_survivor.display_name),
				gained,
				str(profession_definition.display_name),
				current_practice,
				int(profession_definition.promotion_experience),
			])
			if previous_practice < int(profession_definition.apprentice_experience) and current_practice >= int(profession_definition.apprentice_experience):
				milestone_entries.append("%s zostaje uczniem w ścieżce %s." % [str(selected_survivor.display_name), str(profession_definition.display_name)])
			if previous_practice < int(profession_definition.promotion_experience) and current_practice >= int(profession_definition.promotion_experience):
				milestone_entries.append("%s opanował ścieżkę %s i może otrzymać drugą specjalizację w Domu Wspólnoty II." % [str(selected_survivor.display_name), str(profession_definition.display_name)])

func _staffed_active_building(state, definition_id: String):
	var building = state.find_building_by_definition(definition_id)
	if building == null or not building.is_active() or _planned_worker_ids(state, building).is_empty():
		return null
	return building if _effective_worker_units(state, building) > 0.0 else null

func _building_capabilities(definition_id: String, level: int) -> Dictionary:
	var definition = ResourceLoader.load("res://data/buildings/%s.tres" % definition_id)
	var level_definition = definition.get_level_definition(level) if definition != null else null
	return level_definition.capabilities if level_definition != null else {}


func _disease_definitions() -> Dictionary:
	var main_loop = Engine.get_main_loop()
	var tree_root = main_loop.root if main_loop is SceneTree else null
	var database = tree_root.get_node_or_null("GameDatabase") if tree_root != null else null
	if database != null and not database.diseases.is_empty():
		return database.diseases
	var result: Dictionary = {}
	for file_name in DirAccess.get_files_at("res://data/diseases"):
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var definition = ResourceLoader.load("res://data/diseases".path_join(file_name))
		if definition != null and not str(definition.id).is_empty():
			result[str(definition.id)] = definition
	return result


func _building_workforce(state, building, bonus_id: String) -> Dictionary:
	var worker_ids: Array[String] = _snapshot_worker_ids(state, building)
	var definition = null
	var frozen_efficiency = null
	if building != null:
		definition = ResourceLoader.load("res://data/buildings/%s.tres" % building.definition_id)
		var building_id := str(building.id)
		if _worker_efficiency_snapshot.has(building_id):
			frozen_efficiency = _worker_efficiency_snapshot.get(building_id, {})
	return _building_work_system.workforce_from_capable_ids(
		state,
		definition,
		worker_ids,
		bonus_id,
		frozen_efficiency
	)


func _effective_worker_units(state, building) -> float:
	return float(_building_workforce(state, building, "").get("worker_units", 0.0))

func _specialist_bonus_total(state, building, bonus_id: String) -> float:
	return float(_building_workforce(state, building, bonus_id).get("specialist_bonus", 0.0))

func _building_work_pace(state, building) -> String:
	return _work_pace_system.pace_for_building(state, building)


func _building_display_name(building) -> String:
	if building == null:
		return "Budynek"
	var definition = ResourceLoader.load("res://data/buildings/%s.tres" % str(building.definition_id))
	return str(definition.display_name) if definition != null else str(building.definition_id)

func _injury_display_name(injury_id: String) -> String:
	return _injury_recovery_system.display_name(injury_id)

func _landmark_report_label(state, landmark_id: String) -> String:
	var normalized_id := landmark_id.strip_edges()
	if state != null and state.underwater_world != null and state.underwater_world.blueprint != null and not normalized_id.is_empty():
		var landmark: Dictionary = state.underwater_world.blueprint.get_landmark(normalized_id)
		var display_name := str(landmark.get("display_name", "")).strip_edges()
		var resolved_id := str(landmark.get("id", normalized_id)).strip_edges()
		if not display_name.is_empty():
			return "%s (%s)" % [display_name, resolved_id] if not resolved_id.is_empty() else display_name
	if not normalized_id.is_empty():
		return normalized_id
	return "nieznany rejon"

func _noise_action_display_name(action_id: String) -> String:
	match action_id:
		"sprint":
			return "sprint"
		"pry":
			return "podważanie łomem"
		"cut":
			return "cięcie nożem"
		"repair":
			return "naprawa kombinezonu"
		"open":
			return "otwieranie pojemnika"
	return action_id.replace("_", " ")

func _shelter_capacity(state) -> int:
	var community_house = state.find_building_by_definition("community_house")
	if community_house == null or not community_house.is_active():
		return 3
	return maxi(int(_building_capabilities("community_house", community_house.level).get("shelter_capacity", 3)), 3)
