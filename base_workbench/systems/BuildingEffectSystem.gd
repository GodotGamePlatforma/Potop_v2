class_name BuildingEffectSystem
extends RefCounted

const CampaignProgressionSystemScript := preload("res://scripts/campaign/CampaignProgressionSystem.gd")
const BuildingWorkSystemScript := preload("res://base_workbench/systems/BuildingWorkSystem.gd")
const DiseaseSystemScript := preload("res://scripts/survivors/DiseaseSystem.gd")
const ExpeditionPreparationSystemScript := preload("res://scripts/diving/ExpeditionPreparationSystem.gd")
const InjuryRecoverySystemScript := preload("res://scripts/survivors/InjuryRecoverySystem.gd")
const MedicalCareSystemScript := preload("res://base_workbench/systems/MedicalCareSystem.gd")
const PolicyStateScript := preload("res://scripts/data/PolicyState.gd")
const ProductionSystemScript := preload("res://base_workbench/systems/ProductionSystem.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const RationAllocationSystemScript := preload("res://base_workbench/systems/RationAllocationSystem.gd")
const SuitSystemScript := preload("res://scripts/diving/SuitSystem.gd")
const TemperatureSystemScript := preload("res://scripts/diving/TemperatureSystem.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const WorkPaceSystemScript := preload("res://base_workbench/systems/WorkPaceSystem.gd")
const WorkerAssignmentSystemScript := preload("res://base_workbench/systems/WorkerAssignmentSystem.gd")

var _campaign_system = CampaignProgressionSystemScript.new()
var _building_work_system = BuildingWorkSystemScript.new()
var _disease_system = DiseaseSystemScript.new()
var _expedition_preparation_system = ExpeditionPreparationSystemScript.new()
var _injury_recovery_system = InjuryRecoverySystemScript.new()
var _medical_care_system = MedicalCareSystemScript.new()
var _production_system = ProductionSystemScript.new()
var _ration_allocation_system = RationAllocationSystemScript.new()
var _suit_system = SuitSystemScript.new()
var _temperature_system = TemperatureSystemScript.new()
var _work_pace_system = WorkPaceSystemScript
var _worker_assignment_system = WorkerAssignmentSystemScript.new()


## Returns authored, player-facing effects for a completed building level.
## Every numeric balance value comes from the level capabilities, specialist
## bonus, or the system that consumes the value during gameplay.
func level_effect_lines(state, definition, level: int) -> Array[String]:
	var lines: Array[String] = []
	if definition == null:
		return lines
	var level_definition = definition.get_level_definition(level)
	if level_definition == null:
		return lines
	var capabilities: Dictionary = level_definition.capabilities
	var worker_slots := maxi(int(level_definition.worker_slots), 1)

	match str(definition.id):
		"diving_station":
			lines.append(_station_roles_line(worker_slots))
			lines.append("Umożliwia wyprawy po wybraniu wolnego nurka; plecak ekspedycji ma %d miejsc." % int(capabilities.get("backpack_slots", 0)))
			lines.append("Zdolna Obsługa Stacji daje wybranemu nurkowi +%d%% udźwigu." % int(round((float(capabilities.get("staffed_diver_carry_multiplier", 1.0)) - 1.0) * 100.0)))
			lines.append(_station_suit_line(level))
			lines.append("Tempo Stacji skaluje zasięg Operatora i siłę każdej naprawy kombinezonu; nie zmienia szansy ratunku, liczby ładunków ani jakości kombinezonu.")
			var oxygen_multiplier := float(definition.specialist_bonus.get("oxygen_capacity_multiplier", 1.0))
			var oxygen_bonus := int(round(float(definition.specialist_bonus.get("oxygen_bonus", 0.0))))
			lines.append("Specjalista Nurek: +%d%% osobistej pojemności tlenu i +%d jednostek tlenu." % [int(round((oxygen_multiplier - 1.0) * 100.0)), oxygen_bonus])
			if bool(capabilities.get("operator_rescue_enabled", false)):
				lines.append("Operator liny: %d%% szansy na awaryjne wyciągnięcie przy głównej linie; nurek wraca ciężko ranny i bez łupu." % _operator_chance_percent(state))
			if bool(capabilities.get("buoy_enabled", false)):
				lines.append("Nurek może ustawić 1 trwałą boję orientacyjną na wyprawę.")
			if bool(capabilities.get("buoy_start_enabled", false)):
				lines.append("Pozwala rozpoczynać kolejne wyprawy przy wcześniej ustawionej boi.")
			if bool(capabilities.get("heavy_marking_enabled", false)):
				lines.append("Worek wypornościowy pozwala oznaczać ciężkie obiekty do wydobycia przez Warsztat III–IV.")
			if bool(capabilities.get("technician_support_enabled", false)):
				var damage_multiplier := float(capabilities.get("technician_suit_damage_multiplier", 1.0))
				lines.append("Technik wyprawy: 2 użycia zestawu naprawczego i o %d%% mniej uszkodzeń kombinezonu." % int(round((1.0 - damage_multiplier) * 100.0)))
		"fishing_hut":
			lines.append(_workplaces_line(worker_slots))
			lines.append("Każdy zdolny pracownik przy pełnej wydajności: %d jedzenia dziennie." % int(capabilities.get("food_per_worker", 0)))
			lines.append("Specjalista Rybak: +%d jedzenia. Faktyczny połów zależy od stanu obsady, tempa pracy, integralności i presji łowiska." % int(round(float(definition.specialist_bonus.get("production_bonus", 0.0)))))
			lines.append("Każde uzyskane jedzenie zwiększa presję łowiska o %s; niższa presja oznacza lepszy kolejny połów." % _format_percent(float(capabilities.get("fishing_pressure_per_food", 0.0))))
		"kitchen":
			lines.append(_workplaces_line(worker_slots))
			lines.append("Co najmniej 1 zdolny pracownik obniża koszt wszystkich racji o %s. Kuchnia nie tworzy jedzenia." % _format_percent(float(capabilities.get("ration_efficiency", 0.0))))
			lines.append("Każdy Kucharz dodaje %d punkty procentowe; suma jest następnie skalowana tempem Kuchni i ograniczana do 75%%." % int(round(float(definition.specialist_bonus.get("ration_efficiency_bonus", 0.0)) * 100.0)))
		"workshop":
			lines.append(_workplaces_line(worker_slots))
			lines.append("Bez innego zadania wykonuje jedną naprawę dziennie: każdy zdolny pracownik wnosi do %d punktów integralności, a złom jest pobierany raz za skuteczną naprawę (bazowo %d)." % [int(capabilities.get("platform_repair_per_worker", 0)), int(capabilities.get("repair_scrap_cost", 0))])
			lines.append("Kolejka mieści %d zleceń; dzienna baza produkcji to %d punktów pracy, skalowanych tempem (100 punktów kończy sprzęt)." % [int(capabilities.get("production_queue_capacity", 0)), int(capabilities.get("production_slots_per_day", 0)) * 100])
			var recipes := _workshop_recipe_names(level, false)
			if not recipes.is_empty():
				lines.append("Dostępny sprzęt: %s." % ", ".join(recipes))
			if bool(capabilities.get("heavy_recovery_enabled", false)):
				lines.append("Jeżeli produkcja nie otrzyma dodatnich punktów pracy, wydobywa 1 oznaczony ciężki obiekt zamiast naprawy.")
			lines.append("Specjalista Mechanik: +%d punkt naprawy platformy. Priorytet dnia: produkcja → ciężki odzysk → naprawa." % int(round(float(definition.specialist_bonus.get("repair_bonus", 0.0)))))
		"infirmary":
			lines.append(_workplaces_line(worker_slots))
			lines.append("Przy zdolnej obsadzie leczy do %d rannych dziennie: bazowo +%d zdrowia za %d jednostkę leków na pacjenta, przed profilem trudności; osiągnięte zdrowie może też zagoić uraz i przywrócić zdolność do pracy." % [int(capabilities.get("patient_capacity", 0)), int(capabilities.get("healing_per_patient", 0)), int(capabilities.get("medicine_per_patient", 0))])
			lines.append("Każdy Medyk dodaje +%d do leczenia przed tempem Lecznicy i profilem trudności." % int(round(float(definition.specialist_bonus.get("healing_bonus", 0.0)))))
			var formal_capacity := int(capabilities.get("formal_isolation_capacity", 0))
			if formal_capacity > 0:
				lines.append("Formalna Izolatka całkowicie odcina transmisję dla pierwszych %d osób w kolejności planu izolacji." % formal_capacity)
		"community_house":
			lines.append("Bez obsady zapewnia %d suchych miejsc schronienia; każde brakujące miejsce daje −4 nominalnej Nadziei podczas rozliczenia." % int(capabilities.get("shelter_capacity", 0)))
			lines.append(_workplaces_line(worker_slots))
			lines.append("Każdy zdolny pracownik wnosi +%d Nadziei, Organizator +%d; tempo koryguje wkład każdej osoby o −1/0/+1." % [int(capabilities.get("hope_per_worker", 0)), int(round(float(definition.specialist_bonus.get("hope_bonus", 0.0))))])
			lines.append("Aktywny Dom pozwala rozwijać trwałe statystyki mieszkańców.")
			if level >= 2:
				lines.append("Dom Wspólnoty II–IV pozwala formalnie nadać jedną trwałą drugą specjalizację po zdobyciu 100 praktyki.")
		_:
			lines.append(_workplaces_line(worker_slots))
	_append_level_name_boundary(lines, str(definition.id), level)
	return lines


func _append_level_name_boundary(lines: Array[String], definition_id: String, level: int) -> void:
	match definition_id:
		"diving_station":
			if level == 3:
				lines.append("„Sonar” i „komora ciśnieniowa” są nazwą poziomu; nie uruchamiają osobnej mechaniki skanowania ani ciśnienia.")
			elif level == 4:
				lines.append("„Dzwon głębinowy” jest nazwą poziomu; nie tworzy osobnego wyjścia ani obiektu Dzwonu — aktywnym skutkiem jest start przy wcześniej ustawionej boi.")
		"fishing_hut":
			if level == 2:
				lines.append("„Magazyn przynęt” jest nazwą poziomu; nie tworzy osobnego zasobu ani kosztu przynęty.")
			elif level == 4:
				lines.append("„Akwakultura” jest nazwą poziomu; nadal rozlicza połów i presję łowiska, bez osobnej pasywnej hodowli ani odradzania biologii.")
		"kitchen":
			if level < 3:
				lines.append("„Wędzarnia” jest częścią nazwy; nie tworzy osobnej produkcji ani zapasu żywności.")
			else:
				lines.append("„Wędzarnia” i „Spiżarnia” są nazwami; nie tworzą osobnej produkcji ani magazynu żywności.")
		"infirmary":
			lines.append("„Suszarnia” jest częścią nazwy; nie uruchamia osobnej produkcji ani konserwacji żywności.")
		"community_house":
			if level >= 3:
				lines.append("„Radiostacja” zapewnia stabilną łączność potrzebną do końcowej konfiguracji Wspólnej Linii; nie otwiera osobnego panelu radia ani namierzania.")
			if level >= 4:
				lines.append("„Latarnia Przystani” jest nazwą etapu; nie dodaje osobnego światła, sygnału ani systemu nawigacji.")


## Returns a concise comparison shown beside an upgrade decision.
func next_level_change_lines(state, definition, current_level: int) -> Array[String]:
	var lines: Array[String] = []
	if definition == null or current_level >= int(definition.max_level):
		return lines
	var current_definition = definition.get_level_definition(current_level)
	var next_definition = definition.get_level_definition(current_level + 1)
	if current_definition == null or next_definition == null:
		return lines
	var current: Dictionary = current_definition.capabilities
	var next: Dictionary = next_definition.capabilities
	if int(current_definition.worker_slots) != int(next_definition.worker_slots):
		lines.append("Stanowiska: %d → %d." % [int(current_definition.worker_slots), int(next_definition.worker_slots)])

	match str(definition.id):
		"diving_station":
			lines.append("Plecak ekspedycji: %d → %d miejsc." % [int(current.get("backpack_slots", 0)), int(next.get("backpack_slots", 0))])
			var current_damage_reduction := 100 - _suit_system.calculate_damage(100, current_level, 1.0)
			var next_damage_reduction := 100 - _suit_system.calculate_damage(100, current_level + 1, 1.0)
			var base_cold_rate := _temperature_system.exposure_rate(160.0, 1, 1.0, 1.0)
			var current_cold_rate := _temperature_system.exposure_rate(160.0, current_level, 1.0, 1.0)
			var next_cold_rate := _temperature_system.exposure_rate(160.0, current_level + 1, 1.0, 1.0)
			var current_cold_reduction := int(round((1.0 - current_cold_rate / base_cold_rate) * 100.0)) if base_cold_rate > 0.0 else 0
			var next_cold_reduction := int(round((1.0 - next_cold_rate / base_cold_rate) * 100.0)) if base_cold_rate > 0.0 else 0
			lines.append("Kombinezon: ochrona przed uszkodzeniami %d%% → %d%%; ograniczenie wychłodzenia %d%% → %d%%; naprawa %d → %d." % [current_damage_reduction, next_damage_reduction, current_cold_reduction, next_cold_reduction, _suit_system.repair_amount(current_level), _suit_system.repair_amount(current_level + 1)])
			_append_new_station_capabilities(lines, state, current, next)
		"fishing_hut":
			if int(current.get("food_per_worker", 0)) != int(next.get("food_per_worker", 0)):
				lines.append("Połów na pełną jednostkę pracy: %d → %d jedzenia." % [int(current.get("food_per_worker", 0)), int(next.get("food_per_worker", 0))])
			lines.append("Presja za 1 jedzenie: %s → %s." % [_format_percent(float(current.get("fishing_pressure_per_food", 0.0))), _format_percent(float(next.get("fishing_pressure_per_food", 0.0)))])
		"kitchen":
			lines.append("Oszczędność racji: %s → %s." % [_format_percent(float(current.get("ration_efficiency", 0.0))), _format_percent(float(next.get("ration_efficiency", 0.0)))])
		"workshop":
			lines.append("Naprawa na pełną jednostkę pracy: %d → %d integralności." % [int(current.get("platform_repair_per_worker", 0)), int(next.get("platform_repair_per_worker", 0))])
			lines.append("Kolejka: %d → %d; dzienna baza produkcji: %d → %d punktów." % [int(current.get("production_queue_capacity", 0)), int(next.get("production_queue_capacity", 0)), int(current.get("production_slots_per_day", 0)) * 100, int(next.get("production_slots_per_day", 0)) * 100])
			var unlocked_recipes := _workshop_recipe_names(current_level + 1, true)
			if not unlocked_recipes.is_empty():
				lines.append("Nowe receptury: %s." % ", ".join(unlocked_recipes))
			if not bool(current.get("heavy_recovery_enabled", false)) and bool(next.get("heavy_recovery_enabled", false)):
				lines.append("Odblokuje wydobywanie oznaczonych ciężkich obiektów.")
		"infirmary":
			lines.append("Leczenie pacjenta: +%d → +%d zdrowia; pacjenci dziennie: %d → %d." % [int(current.get("healing_per_patient", 0)), int(next.get("healing_per_patient", 0)), int(current.get("patient_capacity", 0)), int(next.get("patient_capacity", 0))])
			var current_isolation := int(current.get("formal_isolation_capacity", 0))
			var next_isolation := int(next.get("formal_isolation_capacity", 0))
			if current_isolation != next_isolation:
				lines.append("Miejsca formalnej izolacji: %d → %d." % [current_isolation, next_isolation])
		"community_house":
			lines.append("Schronienie: %d → %d miejsc; wkład pracownika: +%d → +%d Nadziei." % [int(current.get("shelter_capacity", 0)), int(next.get("shelter_capacity", 0)), int(current.get("hope_per_worker", 0)), int(next.get("hope_per_worker", 0))])
			if current_level < 2 and current_level + 1 >= 2:
				lines.append("Odblokuje formalny awans do jednej drugiej specjalizacji.")
	_append_level_name_boundary(lines, str(definition.id), current_level + 1)
	return lines


## Read-only forecast for the current roster and current campaign state.
## The forecast is recalculated whenever the panel rebuilds after an assignment.
func staffing_preview(state, definition, building) -> Dictionary:
	var result := {
		"active": false,
		"mode": "inactive",
		"amount": 0,
		"unit": "",
		"assigned_count": 0,
		"capable_count": 0,
		"capable_worker_ids": [],
		"incapable_worker_ids": [],
		"lines": [] as Array[String],
	}
	if state == null or definition == null or building == null:
		result.lines.append("Brak danych budynku — efekt obsady wynosi 0.")
		return result
	var level_definition = definition.get_level_definition(int(building.level))
	if level_definition == null:
		result.lines.append("Brak danych bieżącego poziomu — efekt obsady wynosi 0.")
		return result
	var assigned := _assigned_survivors(state, building)
	var capable := (
		_station_capable_workers(state, definition, building)
		if str(definition.id) == "diving_station"
		else _capable_workers(assigned)
	)
	var isolated_ids := _planned_isolated_survivor_ids(state)
	capable = capable.filter(func(survivor) -> bool:
		return survivor != null and str(survivor.id) not in isolated_ids
	)
	result.assigned_count = assigned.size()
	result.capable_count = capable.size()
	result.capable_worker_ids = _survivor_ids(capable)
	result.incapable_worker_ids = _noncapable_ids(assigned, capable)
	if not building.is_active():
		result.lines.append("Efekt obsady: 0 — budynek jest obecnie nieaktywny.")
		if str(definition.id) == "fishing_hut":
			_append_fishing_pressure_forecast(
				result,
				_fishing_projection(state, definition, building, [], level_definition.capabilities)
			)
		return result
	result.active = true

	if str(definition.id) == "diving_station":
		return _station_preview(state, definition, building, result)

	if capable.is_empty():
		if assigned.is_empty():
			result.lines.append("Efekt obsady dzisiaj: 0 — przydziel co najmniej jednego zdolnego pracownika.")
		else:
			result.lines.append("Efekt obsady dzisiaj: 0 — przydzieleni mieszkańcy są czasowo niezdolni do pracy: %s." % ", ".join(_survivor_names(assigned)))
		if str(definition.id) == "community_house":
			_append_shelter_status(result.lines, state, level_definition.capabilities)
		elif str(definition.id) == "fishing_hut":
			_append_fishing_pressure_forecast(
				result,
				_fishing_projection(state, definition, building, [], level_definition.capabilities)
			)
		elif str(definition.id) == "infirmary":
			_preview_infirmary(state, definition, [], level_definition.capabilities, result)
		return result

	result.lines.append("Zdolna obsada: %d z %d stanowisk (%s)." % [capable.size(), int(level_definition.worker_slots), ", ".join(_survivor_names(capable))])
	match str(definition.id):
		"fishing_hut":
			_preview_fishing(state, definition, building, capable, level_definition.capabilities, result)
		"kitchen":
			_preview_kitchen(state, definition, building, capable, level_definition.capabilities, result)
		"workshop":
			_preview_workshop(state, definition, building, capable, level_definition.capabilities, result)
		"infirmary":
			_preview_infirmary(state, definition, capable, level_definition.capabilities, result)
		"community_house":
			_preview_community(state, definition, capable, level_definition.capabilities, result)
		_:
			result.mode = "staffed"
			result.lines.append("Budynek ma zdolną obsadę i wykona swoją dzienną pracę podczas rozliczenia.")
	return result


## Canonical read-only Infirmary projection for every UI consumer. It mirrors
## the resolver's capable-worker and isolation boundary without calling
## staffing_preview(), which keeps the projection free of UI recursion.
func medical_care_projection(state) -> Dictionary:
	if state == null:
		return {}
	var infirmary = state.find_building_by_definition("infirmary")
	var definition = ResourceLoader.load("res://base_workbench/data/buildings/infirmary.tres")
	var capabilities: Dictionary = {}
	var capable: Array = []
	if infirmary != null and infirmary.is_active() and definition != null:
		var level_definition = definition.get_level_definition(int(infirmary.level))
		if level_definition != null:
			capabilities = level_definition.capabilities
		capable = _capable_workers(_assigned_survivors(state, infirmary))
		var isolated_ids := _planned_isolated_survivor_ids(state)
		capable = capable.filter(func(survivor) -> bool:
			return survivor != null and str(survivor.id) not in isolated_ids
		)
	var priorities: Array[String] = []
	if state.current_day_plan != null:
		priorities.assign(state.current_day_plan.medical_priority_survivor_ids)
	var recovery_multiplier := float(state.difficulty_profile.recovery_speed_multiplier) if state.difficulty_profile != null else 1.0
	return _medical_care_system.project(
		capabilities,
		_workforce_from_survivors(state, definition, capable, "healing_bonus") if definition != null else {},
		_building_work_pace(state, infirmary),
		recovery_multiplier,
		int(state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS)),
		state.survivors,
		_disease_definitions(),
		priorities
	)


## Aggregates the shared ration and medical projections into DiseaseSystem's
## one-case forecast, so cards never rebuild resolver orchestration.
func disease_case_plan_projection(state, survivor_id: String, disease_case) -> Dictionary:
	if state == null or disease_case == null:
		return {}
	var ration_projection := ration_forecast(state)
	var allocation: Dictionary = ration_projection.get("allocation", {})
	var ration_by_survivor: Dictionary = allocation.get("ration_by_survivor_id", {})
	var ration_id := str(ration_by_survivor.get(survivor_id, "none"))
	var medical_projection := medical_care_projection(state)
	var formal_capacity := int(medical_projection.get("formal_isolation_capacity", 0))
	var adverse := _disease_system.adverse_conditions_active(state, shelter_capacity_for_state(state))
	return _disease_system.case_plan_projection(
		state,
		survivor_id,
		disease_case,
		ration_id,
		medical_projection,
		{
			"formal_isolation_capacity": formal_capacity,
			"adverse_conditions_pressure": 1 if adverse else 0,
			"disease_pressure_modifier": int(state.difficulty_profile.disease_pressure_modifier) if state.difficulty_profile != null else 0,
		}
	)


## Short, slot-specific explanation displayed directly on an assigned worker card.
## Values describe that worker's direct contribution; the aggregate card above
## remains the authoritative forecast after global day modifiers and priorities.
func worker_contribution_line(state, definition, building, slot_index: int, survivor) -> String:
	if survivor == null:
		return "Wkład dzisiaj: 0 — stanowisko nieobsadzone."
	if building == null or not building.is_active():
		return "Wkład dzisiaj: 0 — budynek jest nieaktywny."
	var role_blocker := _worker_assignment_system.assignment_role_blocker(
		state,
		str(survivor.id),
		str(building.id),
		slot_index
	)
	if not role_blocker.is_empty():
		return "Wkład dzisiaj: 0 — %s" % role_blocker
	var level_definition = definition.get_level_definition(int(building.level)) if definition != null else null
	if level_definition == null:
		return "Wkład dzisiaj: 0 — brak danych poziomu."
	var capabilities: Dictionary = level_definition.capabilities

	match str(definition.id):
		"diving_station":
			var analysis: Dictionary = _expedition_preparation_system.analyze(state, building, definition)
			match slot_index:
				0:
					if not bool(analysis.get("station_staffed", false)):
						return "Obsługa Stacji: czeka na wolnego, wybranego nurka."
					return "Obsługa Stacji: +%d%% udźwigu dla wybranego nurka." % int(round((float(analysis.get("station_staffed_carry_multiplier", 1.0)) - 1.0) * 100.0))
				1:
					if not bool(analysis.get("operator_assigned", false)):
						return "Operator: ratunek awaryjny 0%."
					if not bool(analysis.get("operator_rescue_available", false)):
						return "Operator: 0% przy starcie z boi; ratunek działa tylko przy głównej linie."
					return "Operator: %d%% ratunku do %.0f jedn. od liny." % [int(round(float(analysis.get("operator_rescue_effective_chance", 0.0)) * 100.0)), float(analysis.get("operator_rescue_max_distance", 440.0))]
				2:
					if not bool(analysis.get("technician_assigned", false)):
						return "Technik: brak dodatkowego wsparcia wyprawy."
					return "Technik: %d użycia naprawy • −%d%% uszkodzeń kombinezonu." % [int(analysis.get("repair_kit_charges", 2)), int(round(float(analysis.get("technician_suit_damage_reduction", 0.10)) * 100.0))]
		"fishing_hut":
			var fishing_workforce := _workforce_from_survivors(state, definition, [survivor], "production_bonus")
			var base_food := float(capabilities.get("food_per_worker", 0)) * float(fishing_workforce.get("worker_units", 0.0))
			var fishing_bonus := float(fishing_workforce.get("specialist_bonus", 0.0))
			return "Wkład bazowy: %.1f jedzenia%s przed presją, tempem i integralnością." % [base_food + fishing_bonus, " (Rybak +%d)" % int(round(fishing_bonus)) if fishing_bonus > 0.0 else ""]
		"kitchen":
			var ration_forecast_result := ration_forecast(state)
			if int(ration_forecast_result.get("amount", 0)) <= 0:
				if _planned_ration_policy(state) == PolicyStateScript.RationPolicy.NONE:
					return "Wkład dzisiaj: 0 — plan dnia wyłącza wydawanie racji."
				return "Wkład dzisiaj: 0 — prognoza nie przewiduje wydania racji."
			var ration_bonus := float(_workforce_from_survivors(state, definition, [survivor], "ration_efficiency_bonus").get("specialist_bonus", 0.0))
			if ration_bonus > 0.0:
				return "Utrzymuje pracę Kuchni i dodaje %s oszczędności przed tempem." % _format_percentage_points(ration_bonus)
			return "Utrzymuje poziomową oszczędność racji skalowaną tempem; kolejny zwykły pracownik jej nie zwiększa."
		"workshop":
			var workshop_preview := staffing_preview(state, definition, building)
			match str(workshop_preview.get("mode", "")):
				"production":
					var production_workforce := _workforce_from_survivors(
						state,
						definition,
						[survivor],
						"repair_bonus"
					)
					var queue_analysis := _production_system.analyze_workshop_queue(
						state,
						_building_work_pace(state, building),
						true,
						production_workforce.get("talent_ids", [])
					)
					return "Obsługuje produkcję: %d z %d punktów planowanej pracy; niższe zadania są dziś wstrzymane." % [
						int(queue_analysis.get("points_applied", 0)),
						int(queue_analysis.get("points_budget", 0)),
					]
				"heavy_recovery":
					return "Obsługuje wyciągarkę: 1 oznaczony ciężki obiekt według stałej normalnej procedury."
				"idle", "repair_blocked", "repair_no_output":
					return "Gotowy do pracy, lecz dzisiejszy plan nie uruchomi zadania Warsztatu."
			if bool(capabilities.get("heavy_recovery_enabled", false)) and state.underwater_world != null and not state.underwater_world.marked_heavy_objects.is_empty():
				return "Obsługuje wyciągarkę: 1 oznaczony ciężki obiekt zamiast naprawy platformy."
			if state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY) >= 100:
				return "Gotowy do pracy, lecz platforma ma 100% integralności i nie ma wcześniejszego zadania."
			var repair_workforce := _workforce_from_survivors(state, definition, [survivor], "repair_bonus")
			var repair := float(capabilities.get("platform_repair_per_worker", 0)) * float(repair_workforce.get("worker_units", 0.0))
			var repair_bonus := float(repair_workforce.get("specialist_bonus", 0.0))
			return "Wkład naprawczy: %.1f integralności%s przed tempem i stanem platformy." % [repair + repair_bonus, " (Mechanik +%d)" % int(round(repair_bonus)) if repair_bonus > 0.0 else ""]
		"infirmary":
			var healing_bonus := float(_workforce_from_survivors(state, definition, [survivor], "healing_bonus").get("specialist_bonus", 0.0))
			if healing_bonus > 0.0:
				return "Utrzymuje leczenie i dodaje +%d do bazy każdego pacjenta przed tempem i profilem trudności." % int(round(healing_bonus))
			return "Utrzymuje leczenie skalowane tempem do %d pacjentów; kolejny zwykły pracownik nie zwiększa limitu." % int(capabilities.get("patient_capacity", 0))
		"community_house":
			var community_projection := _building_work_system.project_community_work(
				capabilities,
				_workforce_from_survivors(state, definition, [survivor], "hope_bonus"),
				_building_work_pace(state, building)
			)
			var hope_bonus := int(community_projection.get("specialist_bonus", 0))
			var contribution := int(community_projection.get("hope_gain", 0))
			return "Wkład po tempie: +%d nominalnej Nadziei%s." % [contribution, " (Organizator +%d)" % hope_bonus if hope_bonus > 0 else ""]
	return "Zdolny pracownik uruchamia dzienny efekt budynku."


func worker_is_capable(state, definition, building, slot_index: int, survivor) -> bool:
	if survivor == null or definition == null or building == null:
		return false
	return _worker_assignment_system.assignment_role_blocker(
		state,
		str(survivor.id),
		str(building.id),
		slot_index
	).is_empty()


func _station_preview(state, definition, building, result: Dictionary) -> Dictionary:
	var analysis: Dictionary = _expedition_preparation_system.analyze(state, building, definition)
	var diver = analysis.get("diver")
	if diver == null:
		result.lines.append("Nurek: brak — wyprawa jest niedostępna.")
	elif not diver.can_dive():
		result.lines.append("Nurek %s: wkład 0 — %s" % [diver.display_name, diver.dive_blocker()])
	else:
		var oxygen_capacity := float(analysis.get("oxygen_capacity", 0.0))
		var backpack_capacity := int(analysis.get("backpack_capacity", 0))
		result.lines.append("Nurek %s: %.0f jednostek tlenu, %d miejsc w plecaku i %.1f kg udźwigu." % [diver.display_name, oxygen_capacity, backpack_capacity, float(analysis.get("carry_capacity", diver.get_carry_capacity()))])
		if bool(analysis.get("station_staffed", false)):
			result.lines.append("Obsługa Stacji aktywna: +5% udźwigu wybranego nurka.")
		result.amount = int(round(oxygen_capacity))
		result.unit = "jednostek tlenu"
	if bool(analysis.get("ready", false)):
		result.mode = "dive_ready"
		result.lines.append("Gotowość: wyprawa może rozpocząć się teraz.")
	else:
		result.mode = "dive_blocked"
		result.lines.append("Gotowość: %s" % str(analysis.get("reason", "wyprawa jest zablokowana")))
	result.lines.append("Tempo %s: naprawa kombinezonu +%d stanu." % [
		str(analysis.get("work_pace_label", "Normalne")).to_lower(),
		int(analysis.get("suit_repair_amount", _suit_system.repair_amount(int(building.level)))),
	])

	var capabilities: Dictionary = analysis.get("capabilities", {})
	if bool(capabilities.get("operator_rescue_enabled", false)):
		if bool(analysis.get("operator_assigned", false)):
			if bool(analysis.get("operator_rescue_available", false)):
				result.lines.append("Operator %s: %d%% szansy ratunku do %.0f jednostek od głównej liny; ratunek porzuca cały łup." % [_survivor_name_for_id(state, str(analysis.get("operator_survivor_id", ""))), int(round(float(analysis.get("operator_rescue_effective_chance", 0.0)) * 100.0)), float(analysis.get("operator_rescue_max_distance", 440.0))])
			else:
				result.lines.append("Operator %s: efektywna szansa ratunku 0%% — wybrano start z boi, a wyciągnięcie działa tylko przy głównej linie." % _survivor_name_for_id(state, str(analysis.get("operator_survivor_id", ""))))
		else:
			result.lines.append("Operator liny: brak zdolnej obsady — szansa awaryjnego ratunku 0%.")
	if bool(capabilities.get("technician_support_enabled", false)):
		if bool(analysis.get("technician_assigned", false)):
			result.lines.append("Technik %s: %d użycia zestawu naprawczego i o %d%% mniej uszkodzeń kombinezonu." % [_survivor_name_for_id(state, str(analysis.get("technician_survivor_id", ""))), int(analysis.get("repair_kit_charges", 2)), int(round(float(analysis.get("technician_suit_damage_reduction", 0.10)) * 100.0))])
		else:
			result.lines.append("Technik wyprawy: brak zdolnej obsady — 1 użycie zestawu i brak dodatkowej ochrony.")
	return result


func _preview_fishing(state, definition, building, capable: Array, capabilities: Dictionary, result: Dictionary) -> void:
	var projection := _fishing_projection(state, definition, building, capable, capabilities)
	var produced_food := int(projection.get("food_produced", 0))
	result.mode = "fishing"
	result.amount = produced_food
	result.unit = ResourceIdsScript.display_name(ResourceIdsScript.FOOD)
	result.lines.append("Prognoza przy obecnym stanie planu: +%d jedzenia na koniec dnia." % produced_food)
	result.lines.append("Podstawa %d na pełną jednostkę pracy • Rybacy +%d • łączna wydajność obsady %d%%. Wynik uwzględnia tempo, integralność i presję łowiska." % [
		int(projection.get("food_per_worker", 0)),
		int(projection.get("specialist_bonus", 0)),
		int(round(float(projection.get("worker_units", 0.0)) * 100.0)),
	])
	_append_fishing_pressure_forecast(result, projection)


func _append_fishing_pressure_forecast(result: Dictionary, projection: Dictionary) -> void:
	var pressure_now := float(projection.get("fishing_pressure_before", 0.0))
	var pressure_after_recovery := float(projection.get("fishing_pressure_after_recovery", pressure_now))
	var pressure_after_catch := float(projection.get("fishing_pressure_after_catch", pressure_after_recovery))
	result["fishing_pressure_now"] = pressure_now
	result["fishing_pressure_after_recovery"] = pressure_after_recovery
	result["fishing_pressure_after_catch"] = pressure_after_catch
	result.lines.append("Presja łowiska: %s teraz → %s po regeneracji → %s po prognozowanym połowie." % [
		_format_percent(pressure_now),
		_format_percent(pressure_after_recovery),
		_format_percent(pressure_after_catch),
	])


## Deterministic fishing income that resolves before rations. Dive loot is not
## part of this projection, so callers can present a guaranteed no-loot basis.
func projected_fishing_food(state) -> int:
	if state == null:
		return 0
	var fishing_hut = state.find_building_by_definition("fishing_hut")
	if fishing_hut == null or not fishing_hut.is_active():
		return 0
	var definition = ResourceLoader.load("res://base_workbench/data/buildings/fishing_hut.tres")
	if definition == null:
		return 0
	var level_definition = definition.get_level_definition(int(fishing_hut.level))
	if level_definition == null:
		return 0
	var capable := _capable_workers(_assigned_survivors(state, fishing_hut))
	if capable.is_empty():
		return 0
	return int(_fishing_projection(
		state,
		definition,
		fishing_hut,
		capable,
		level_definition.capabilities
	).get("food_produced", 0))


func _fishing_projection(state, definition, building, capable: Array, capabilities: Dictionary) -> Dictionary:
	var workforce := _workforce_from_survivors(state, definition, capable, "production_bonus")
	var integrity := int(state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY))
	return _building_work_system.project_fishing(
		capabilities,
		workforce,
		_building_work_pace(state, building),
		integrity,
		float(state.platform.fishing_pressure)
	)


## Shared read-only ration forecast used by both the day-plan popover and the
## Kitchen panel. It remains available when there is no Kitchen or no capable
## Kitchen worker, because rations are a settlement rule rather than a building
## action. It includes deterministic fishing, which resolves before rations;
## only the future dive result remains outside the guaranteed projection.
func ration_forecast(state) -> Dictionary:
	var result := {
		"active": false,
		"mode": "ration_none",
		"amount": 0,
		"unit": "jedzenia na dzisiejsze racje",
		"assigned_count": 0,
		"capable_count": 0,
		"capable_worker_ids": [] as Array[String],
		"raw_ration_efficiency": 0.0,
		"effective_ration_efficiency": 0.0,
		"lines": [] as Array[String],
	}
	if state == null or state.resources == null:
		result.lines.append("Brak danych kampanii — nie można obliczyć racji.")
		return result

	var kitchen = state.find_building_by_definition("kitchen")
	var kitchen_definition = ResourceLoader.load("res://base_workbench/data/buildings/kitchen.tres")
	var capable: Array = []
	var specialist_bonus := 0.0
	var raw_efficiency := 0.0
	if kitchen != null:
		var assigned := _assigned_survivors(state, kitchen)
		capable = _capable_workers(assigned)
		result.assigned_count = assigned.size()
		result.capable_count = capable.size()
		result.capable_worker_ids = _survivor_ids(capable)
		if kitchen.is_active() and kitchen_definition != null and not capable.is_empty():
			var level_definition = kitchen_definition.get_level_definition(int(kitchen.level))
			if level_definition != null:
				raw_efficiency = float(level_definition.capabilities.get("ration_efficiency", 0.0))
				specialist_bonus = float(_workforce_from_survivors(
					state,
					kitchen_definition,
					capable,
					"ration_efficiency_bonus"
				).get("specialist_bonus", 0.0))
				raw_efficiency += specialist_bonus
				raw_efficiency *= _work_pace_system.output_multiplier(_building_work_pace(state, kitchen))
				result.active = true

	var effective_efficiency := _ration_allocation_system.normalized_efficiency(raw_efficiency)
	result.raw_ration_efficiency = raw_efficiency
	result.effective_ration_efficiency = effective_efficiency
	if bool(result.active):
		result.lines.append("Kuchnia obniży koszt racji o %s; Kucharze wnoszą %s przed tempem budynku." % [_format_percent(effective_efficiency), _format_percentage_points(specialist_bonus)])
	elif kitchen == null or not bool(kitchen.is_built):
		result.lines.append("Brak czynnej Kuchni: racje są liczone bez oszczędności.")
	elif not kitchen.is_active():
		result.lines.append("Kuchnia jest obecnie nieaktywna: racje są liczone bez oszczędności.")
	elif capable.is_empty():
		result.lines.append("Kuchnia nie ma zdolnej obsady: racje są liczone bez oszczędności.")
	else:
		result.lines.append("Kuchnia nie ma poprawnych danych poziomu: racje są liczone bez oszczędności.")

	var current_food := int(state.resources.get_amount(ResourceIdsScript.FOOD))
	var projected_fishing := projected_fishing_food(state)
	var available_food := current_food + projected_fishing
	result["current_food"] = current_food
	result["projected_fishing_food"] = projected_fishing
	result["forecast_available_food"] = available_food
	result.lines.append("Podstawa prognozy: obecny zapas %d + pewny połów %d = %d jedzenia przed racjami; bez nieznanego wyniku wyprawy." % [current_food, projected_fishing, available_food])
	var food_per_adult := int(state.difficulty_profile.food_per_adult) if state.difficulty_profile != null else 4
	var policy := _planned_ration_policy(state)
	var alive_ids: Array[String] = []
	for survivor in state.get_alive_survivors():
		alive_ids.append(str(survivor.id))
	var allocation := _ration_allocation_system.project(
		policy,
		alive_ids,
		available_food,
		food_per_adult,
		effective_efficiency,
		_planned_diver_id(state)
	)
	result["allocation"] = allocation
	_append_ration_forecast(state, result, allocation, policy, alive_ids, available_food)
	return result


func _preview_kitchen(state, _definition, _building, _capable: Array, _capabilities: Dictionary, result: Dictionary) -> void:
	var forecast := ration_forecast(state)
	result.mode = str(forecast.get("mode", "ration_none"))
	result.amount = int(forecast.get("amount", 0))
	result.unit = str(forecast.get("unit", "jedzenia na dzisiejsze racje"))
	result.lines.append_array(forecast.get("lines", []))


func _append_ration_forecast(
	state,
	result: Dictionary,
	allocation: Dictionary,
	policy: int,
	alive_ids: Array[String],
	available_food: int
) -> void:
	var full_ration_cost := int(allocation.get("full_cost", 0))
	var half_ration_cost := int(allocation.get("half_cost", 0))
	var allocation_cost := int(allocation.get("cost", 0))
	var full_ids: Array[String] = []
	full_ids.assign(allocation.get("full_recipient_ids", []))
	var half_ids: Array[String] = []
	half_ids.assign(allocation.get("half_recipient_ids", []))
	var unfed_ids: Array[String] = []
	unfed_ids.assign(allocation.get("unfed_recipient_ids", []))
	result.amount = allocation_cost

	if alive_ids.is_empty():
		result.mode = "ration_none"
		result.lines.append("Plan dnia: brak żyjących odbiorców racji; jedzenie pozostanie w magazynie.")
		return

	if policy == PolicyStateScript.RationPolicy.NONE:
		result.mode = "ration_none"
		result.lines.append("Plan dnia: bez racji. Bez racji pozostaną: %s; zapas %d jedzenia nie zmieni się." % [_ration_preview_recipient_names(state, unfed_ids), available_food])
		return

	if policy == PolicyStateScript.RationPolicy.DIVER_PRIORITY:
		if not bool(allocation.get("diver_valid", false)):
			if allocation_cost > 0:
				result.mode = "rations_half_diver_fallback"
				result.lines.append("Brak poprawnego żyjącego nurka. Grupowy fallback wyda pół racji: %s, za %d jedzenia." % [_ration_preview_recipient_names(state, half_ids), allocation_cost])
			else:
				result.mode = "ration_insufficient"
				result.lines.append("Brak poprawnego żyjącego nurka. Grupowy fallback wymaga %d jedzenia; bez racji pozostaną: %s, a zapas %d zostanie zachowany." % [half_ration_cost, _ration_preview_recipient_names(state, unfed_ids), available_food])
			return
		var diver_id := str(allocation.get("diver_id", ""))
		var diver_ration := str(allocation.get("ration_by_survivor_id", {}).get(diver_id, RationAllocationSystemScript.RATION_NONE))
		if allocation_cost <= 0:
			result.mode = "ration_insufficient"
			result.lines.append("Zapas %d jedzenia nie wystarcza nawet na pół racji dla nurka %s (potrzeba %d). Bez racji pozostaną: %s; cały zapas zostanie zachowany." % [
				available_food,
				_ration_preview_recipient_names(state, [diver_id]),
				int(allocation.get("diver_half_cost", 0)),
				_ration_preview_recipient_names(state, unfed_ids),
			])
			return
		var other_half_ids: Array[String] = []
		for survivor_id in half_ids:
			if survivor_id != diver_id:
				other_half_ids.append(survivor_id)
		result.mode = "rations_diver_priority" if allocation_cost > 0 else "ration_insufficient"
		result.lines.append("Pierwszeństwo nurka: %s — %s; pozostali z połową racji: %s; bez racji: %s. Łączny koszt: %d jedzenia." % [
			_ration_preview_recipient_names(state, [diver_id]),
			_ration_preview_ration_name(diver_ration),
			_ration_preview_recipient_names(state, other_half_ids),
			_ration_preview_recipient_names(state, unfed_ids),
			allocation_cost,
		])
		return

	if policy == PolicyStateScript.RationPolicy.HALF and allocation_cost > 0:
		result.mode = "rations_half"
		result.lines.append("Plan dnia: pół racji otrzymają %s za %d jedzenia (pełne kosztowałyby %d)." % [_ration_preview_recipient_names(state, half_ids), allocation_cost, full_ration_cost])
	elif policy == PolicyStateScript.RationPolicy.FULL and not full_ids.is_empty():
		result.mode = "rations_full"
		result.lines.append("Plan dnia: pełne racje otrzymają %s za %d jedzenia." % [_ration_preview_recipient_names(state, full_ids), allocation_cost])
	elif policy == PolicyStateScript.RationPolicy.FULL and not half_ids.is_empty():
		result.mode = "rations_half_fallback"
		result.lines.append("Na pełne racje potrzeba %d jedzenia; grupowy fallback wyda pół racji: %s, za %d." % [full_ration_cost, _ration_preview_recipient_names(state, half_ids), allocation_cost])
	else:
		result.mode = "ration_insufficient"
		result.lines.append("Na grupową połowę racji potrzeba %d jedzenia; bez racji pozostaną: %s, a dostępny zapas %d zostanie zachowany." % [half_ration_cost, _ration_preview_recipient_names(state, unfed_ids), available_food])


func _planned_diver_id(state) -> String:
	if state.current_day_plan != null:
		return str(state.current_day_plan.selected_diver_id)
	return ""


func _ration_preview_recipient_names(state, survivor_ids: Array) -> String:
	var names: Array[String] = []
	for survivor_id in survivor_ids:
		var survivor = state.find_survivor(str(survivor_id))
		names.append(str(survivor.display_name) if survivor != null else str(survivor_id))
	return "nikt" if names.is_empty() else ", ".join(names)


func _ration_preview_ration_name(ration: String) -> String:
	match ration:
		RationAllocationSystemScript.RATION_FULL:
			return "pełna racja"
		RationAllocationSystemScript.RATION_HALF:
			return "pół racji"
	return "brak racji"


func _preview_workshop(state, definition, building, capable: Array, capabilities: Dictionary, result: Dictionary) -> void:
	var workforce := _workforce_from_survivors(state, definition, capable, "repair_bonus")
	var queue_analysis := _production_system.analyze_workshop_queue(
		state,
		_building_work_pace(state, building),
		true,
		workforce.get("talent_ids", [])
	)
	var canceled_names: Array[String] = []
	canceled_names.assign(queue_analysis.get("canceled_names", []))
	if not canceled_names.is_empty():
		result.lines.append(
			"Bez punktów pracy zostaną anulowane i zwrócone: %s."
			% ", ".join(canceled_names)
		)
	if bool(queue_analysis.get("blocked", false)):
		result.lines.append(str(queue_analysis.get("blocked_message", "Pierwsze zlecenie pozostanie bez zmian.")))
	if bool(queue_analysis.get("worked", false)):
		var work_budget := int(queue_analysis.get("points_budget", 0))
		var points_applied := int(queue_analysis.get("points_applied", 0))
		var completed := int(queue_analysis.get("completed", 0))
		var next_progress := int(queue_analysis.get("next_progress", -1))
		result.mode = "production"
		result.amount = completed
		result.unit = "ukończonych zleceń"
		result.lines.append("Dzisiejszy priorytet: produkcja — %d z %d punktów pracy. Ukończone zlecenia: do %d; dodatni postęp wstrzymuje ciężki odzysk i naprawę." % [points_applied, work_budget, completed])
		if next_progress >= 0:
			result.lines.append("Po rozliczeniu kolejny wpis osiągnie %d/100 punktów." % next_progress)
		return
	if not building.queued_production_orders.is_empty():
		result.lines.append("Kolejka nie otrzyma dodatnich punktów pracy, więc Warsztat przejdzie do kolejnego możliwego zadania.")
	if bool(capabilities.get("heavy_recovery_enabled", false)) and state.underwater_world != null and not state.underwater_world.marked_heavy_objects.is_empty():
		result.mode = "heavy_recovery"
		result.amount = 1
		result.unit = "ciężki obiekt"
		result.lines.append("Dzisiejszy priorytet: wydobycie 1 oznaczonego ciężkiego obiektu według stałej normalnej procedury. Zastępuje ono naprawę platformy.")
		return
	var refunded_cost: Dictionary = queue_analysis.get("refunded_cost", {})
	var current_scrap: int = (
		state.resources.get_amount(ResourceIdsScript.SCRAP)
		+ int(refunded_cost.get(ResourceIdsScript.SCRAP, 0))
	)
	var integrity := int(state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY))
	var repair_multiplier := float(state.difficulty_profile.repair_cost_multiplier) if state.difficulty_profile != null else 1.0
	var projection := _building_work_system.project_platform_repair(
		capabilities,
		workforce,
		_building_work_pace(state, building),
		integrity,
		current_scrap,
		repair_multiplier,
		float(state.platform.repair_scrap_rounding_carry)
	)
	var blocker_code := str(projection.get("blocker_code", ""))
	if blocker_code == BuildingWorkSystemScript.BLOCKER_FULL_INTEGRITY:
		result.mode = "idle"
		result.lines.append("Platforma ma 100% integralności, a żadne wcześniejsze zadanie nie uzyska dodatniego postępu — Warsztat nie zużyje złomu ani nie wykona pracy.")
		return
	if blocker_code == BuildingWorkSystemScript.BLOCKER_INVALID_CAPABILITIES:
		result.mode = "repair_no_output"
		result.lines.append("Prognoza naprawy: 0 — definicja Warsztatu nie zawiera poprawnych danych naprawy. Złom nie zostanie zużyty.")
		return
	if str(projection.get("status_code", "")) == BuildingWorkSystemScript.STATUS_ZERO_OUTPUT:
		result.mode = "repair_no_output"
		result.lines.append("Prognoza naprawy: 0 — bieżąca wydajność obsady po uwzględnieniu planu jest zbyt niska. Złom nie zostanie zużyty.")
		return
	var scrap_cost := int(projection.get("scrap_cost", 0))
	if blocker_code == BuildingWorkSystemScript.BLOCKER_INSUFFICIENT_SCRAP:
		result.mode = "repair_blocked"
		result.lines.append("Prognoza naprawy: 0 — brakuje %d złomu potrzebnego przy obecnym profilu." % maxi(scrap_cost - current_scrap, 0))
		return
	var actual_repair := int(projection.get("repair_applied", 0))
	var repair_potential := int(projection.get("repair_potential", 0))
	var specialist_bonus := int(projection.get("specialist_bonus", 0))
	result.mode = "platform_repair"
	result.amount = actual_repair
	result.unit = "integralności platformy"
	result.lines.append("Prognoza przy obecnym stanie planu: +%d integralności platformy za %d złomu." % [actual_repair, scrap_cost])
	result.lines.append("Potencjał przed limitem 100%%: %d • Mechanicy +%d. Wynik uwzględnia wydajność, tempo pracy i bieżącą integralność." % [repair_potential, specialist_bonus])


func _preview_infirmary(state, _definition, _capable: Array, _capabilities: Dictionary, result: Dictionary) -> void:
	var projection := medical_care_projection(state)
	var effective_healing := int(projection.get("effective_healing", 0))
	var medicine_cost := int(projection.get("medicine_per_patient", 0))
	var patient_capacity := int(projection.get("patient_capacity", 0))
	var patients_requiring_care := int(projection.get("patients_requiring_care", 0))
	var treated_count := int(projection.get("treated_count", 0))
	var total_health_gain := int(projection.get("total_health_gain", 0))
	var specialist_bonus := int(round(float(projection.get("specialist_bonus", 0.0))))
	var healing_basis := int(projection.get("healing_per_patient", 0)) + specialist_bonus
	var patient_forecasts: Array[String] = []
	for patient_result in projection.get("patients", []):
		var patient = state.find_survivor(str(patient_result.get("survivor_id", "")))
		if patient == null:
			continue
		patient_forecasts.append(_patient_recovery_line(
			patient,
			int(patient_result.get("health_before", patient.health)),
			int(patient_result.get("health_after", patient.health)),
			{
				"before": patient_result.get("injury_states_before", []),
				"after": patient_result.get("injury_states_after", []),
				"status_before": int(patient_result.get("status_before", patient.status)),
				"status_after": int(patient_result.get("status_after", patient.status)),
			}
		))
	result.mode = "medical_care" if treated_count > 0 else "medical_idle"
	result.amount = total_health_gain
	result.unit = "zdrowia"
	result.lines.append("Efekt obsady: do %d pacjentów, +%d zdrowia każdemu za %d jednostkę leków. Baza %d, w tym Medycy +%d; wynik uwzględnia tempo i profil trudności." % [patient_capacity, effective_healing, medicine_cost, healing_basis, specialist_bonus])
	if patients_requiring_care <= 0:
		result.lines.append("Dziś nikt nie wymaga leczenia, więc Lecznica nie zużyje leków.")
	elif treated_count <= 0:
		result.lines.append("Leczenia wymaga %d osób, ale zapas leków nie pozwala obsłużyć żadnej." % patients_requiring_care)
	else:
		result.lines.append("Prognoza na dziś: %d z %d potrzebujących pacjentów, łącznie do +%d zdrowia za %d leków." % [treated_count, patients_requiring_care, total_health_gain, int(projection.get("medicine_spent", 0))])
		for patient_forecast in patient_forecasts:
			result.lines.append(patient_forecast)


func _preview_community(state, definition, capable: Array, capabilities: Dictionary, result: Dictionary) -> void:
	_append_shelter_status(result.lines, state, capabilities)
	var community_house = state.find_building_by_definition("community_house")
	var projection := _building_work_system.project_community_work(
		capabilities,
		_workforce_from_survivors(state, definition, capable, "hope_bonus"),
		_building_work_pace(state, community_house)
	)
	var pace_adjustment := int(projection.get("pace_adjustment_per_worker", 0))
	var gain := int(projection.get("hope_gain", 0))
	var specialist_bonus := int(projection.get("specialist_bonus", 0))
	result.mode = "community"
	result.amount = gain
	result.unit = "nominalnej Nadziei"
	var pace_adjustment_text := "+%d" % pace_adjustment if pace_adjustment > 0 else str(pace_adjustment)
	result.lines.append("Wkład obecnej obsady: +%d nominalnej Nadziei, w tym +%d od Organizatorów i %s na osobę z tempa." % [gain, specialist_bonus, pace_adjustment_text])
	result.lines.append("Końcowa zmiana Nadziei połączy ten wkład z racjami, wyprawą i innymi skutkami dnia, a następnie zastosuje profil trudności.")


func _append_shelter_status(lines: Array[String], state, capabilities: Dictionary) -> void:
	var capacity := int(capabilities.get("shelter_capacity", 0))
	var population: int = state.get_alive_survivors().size()
	var free_places := maxi(capacity - population, 0)
	var missing_places := maxi(population - capacity, 0)
	if missing_places > 0:
		lines.append("Schronienie bez obsady: %d miejsc dla %d osób — brakuje %d, więc przy niezmienionej populacji kara wyniesie −%d nominalnej Nadziei (−4 za osobę)." % [capacity, population, missing_places, missing_places * 4])
	else:
		lines.append("Schronienie bez obsady: %d miejsc dla %d osób — wolne miejsca: %d." % [capacity, population, free_places])


func _patient_recovery_line(patient, health_before: int, health_after: int, recovery: Dictionary) -> String:
	var before: Array[String] = []
	before.assign(recovery.get("before", []))
	var after: Array[String] = []
	after.assign(recovery.get("after", []))
	var line := "%s: zdrowie %d → %d" % [patient.display_name, health_before, health_after]
	if before != after:
		line += "; urazy: %s → %s" % [_injury_list_text(before), _injury_list_text(after)]
	elif not before.is_empty():
		line += "; uraz pozostaje: %s" % _injury_list_text(before)
	if int(recovery.get("status_before", -1)) == SurvivorStateScript.Status.INJURED and int(recovery.get("status_after", -1)) == SurvivorStateScript.Status.AVAILABLE:
		line += "; odzyska status dostępny"
	return line + "."


func _injury_list_text(injuries: Array[String]) -> String:
	if injuries.is_empty():
		return "brak"
	var names: Array[String] = []
	for injury_id in injuries:
		names.append(_injury_recovery_system.display_name(str(injury_id)))
	return ", ".join(names)


func _assigned_survivors(state, building) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for survivor_id in _planned_worker_ids(state, building):
		var normalized_id := str(survivor_id)
		if normalized_id.is_empty() or seen.has(normalized_id):
			continue
		seen[normalized_id] = true
		var survivor = state.find_survivor(normalized_id)
		if survivor != null:
			result.append(survivor)
	return result


func _planned_worker_ids(state, building) -> Array:
	if state == null or building == null:
		return []
	if (
		state.current_day_plan != null
		and bool(state.current_day_plan.locked)
		and state.current_day_plan.worker_assignments.has(str(building.id))
	):
		return state.current_day_plan.worker_assignments[str(building.id)]
	return building.assigned_survivor_ids


func _planned_isolated_survivor_ids(state) -> Array[String]:
	var result: Array[String] = []
	if state == null or state.current_day_plan == null:
		return result
	for raw_id in state.current_day_plan.isolated_survivor_ids:
		var survivor_id := str(raw_id)
		if not survivor_id.is_empty() and survivor_id not in result:
			result.append(survivor_id)
	return result


func _capable_workers(assigned: Array) -> Array:
	var result: Array = []
	for survivor in assigned:
		if survivor != null and survivor.can_work():
			result.append(survivor)
	return result


func _noncapable_ids(assigned: Array, capable: Array) -> Array[String]:
	var result: Array[String] = []
	var capable_ids := _survivor_ids(capable)
	for survivor in assigned:
		if survivor != null and not capable_ids.has(str(survivor.id)):
			result.append(str(survivor.id))
	return result


func _station_capable_workers(state, definition, building) -> Array:
	var result: Array = []
	for slot_index in range(building.assigned_survivor_ids.size()):
		var survivor = state.find_survivor(str(building.assigned_survivor_ids[slot_index]))
		if worker_is_capable(state, definition, building, slot_index, survivor):
			result.append(survivor)
	return result


func _survivor_ids(survivors: Array) -> Array[String]:
	var result: Array[String] = []
	for survivor in survivors:
		if survivor != null:
			result.append(str(survivor.id))
	return result


func _survivor_names(survivors: Array) -> Array[String]:
	var result: Array[String] = []
	for survivor in survivors:
		if survivor != null:
			result.append(str(survivor.display_name))
	return result


func _survivor_name_for_id(state, survivor_id: String) -> String:
	if state != null and not survivor_id.is_empty():
		var survivor = state.find_survivor(survivor_id)
		if survivor != null:
			return str(survivor.display_name)
	return "obsadzony"


func _workforce_from_survivors(state, definition, survivors: Array, bonus_id: String) -> Dictionary:
	return _building_work_system.workforce_from_capable_ids(
		state,
		definition,
		_survivor_ids(survivors),
		bonus_id
	)


func _building_work_pace(state, building) -> String:
	return _work_pace_system.pace_for_building(state, building)


func _disease_definitions() -> Dictionary:
	var main_loop = Engine.get_main_loop()
	var tree_root = main_loop.root if main_loop is SceneTree else null
	var database = tree_root.get_node_or_null("GameDatabase") if tree_root != null else null
	if database != null:
		return database.diseases
	var result: Dictionary = {}
	for file_name in DirAccess.get_files_at("res://data/diseases"):
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var definition = ResourceLoader.load("res://data/diseases".path_join(file_name))
		if definition != null and not str(definition.id).is_empty():
			result[str(definition.id)] = definition
	return result


func shelter_capacity_for_state(state) -> int:
	var community_house = state.find_building_by_definition("community_house") if state != null else null
	if community_house == null or not community_house.is_active():
		return 3
	var definition = ResourceLoader.load("res://base_workbench/data/buildings/community_house.tres")
	var level_definition = definition.get_level_definition(int(community_house.level)) if definition != null else null
	return maxi(int(level_definition.capabilities.get("shelter_capacity", 3)), 3) if level_definition != null else 3


func _station_roles_line(worker_slots: int) -> String:
	match worker_slots:
		1:
			return "1 stanowisko: Obsługa Stacji."
		2:
			return "2 stanowiska: Obsługa Stacji i Operator liny."
		_:
			return "%d stanowiska: Obsługa Stacji, Operator liny i Technik wyprawy." % worker_slots


func _workplaces_line(worker_slots: int) -> String:
	return "Miejsca pracy dla dziennego efektu: %d." % worker_slots


func _planned_ration_policy(state) -> int:
	var policy := int(state.active_policies.ration_policy) if state != null and state.active_policies != null else PolicyStateScript.RationPolicy.FULL
	if state != null and state.current_day_plan != null:
		policy = int(state.current_day_plan.ration_policy)
	return policy


func _station_suit_line(level: int) -> String:
	var raw_damage := 100
	var reduced_damage := _suit_system.calculate_damage(raw_damage, level, 1.0)
	var damage_reduction := raw_damage - reduced_damage
	var base_cold_rate := _temperature_system.exposure_rate(160.0, 1, 1.0, 1.0)
	var current_cold_rate := _temperature_system.exposure_rate(160.0, level, 1.0, 1.0)
	var cold_reduction := int(round((1.0 - current_cold_rate / base_cold_rate) * 100.0)) if base_cold_rate > 0.0 else 0
	return "Kombinezon poziomu %d: o %d%% mniej uszkodzeń i o %d%% wolniejsze wychłodzenie niż poziom I; naprawa przywraca %d punktów stanu." % [level, damage_reduction, cold_reduction, _suit_system.repair_amount(level)]


func _operator_chance_percent(state) -> int:
	if state != null and state.difficulty_profile != null:
		return int(round(float(state.difficulty_profile.operator_rescue_chance) * 100.0))
	return 50


func _append_new_station_capabilities(lines: Array[String], state, current: Dictionary, next: Dictionary) -> void:
	if not bool(current.get("operator_rescue_enabled", false)) and bool(next.get("operator_rescue_enabled", false)):
		lines.append("Odblokuje Operatora liny: %d%% szansy awaryjnego ratunku przy głównej linie." % _operator_chance_percent(state))
	if not bool(current.get("buoy_enabled", false)) and bool(next.get("buoy_enabled", false)):
		lines.append("Odblokuje 1 trwałą boję na wyprawę.")
	if not bool(current.get("buoy_start_enabled", false)) and bool(next.get("buoy_start_enabled", false)):
		lines.append("Odblokuje start wyprawy przy ustawionej boi.")
	if not bool(current.get("heavy_marking_enabled", false)) and bool(next.get("heavy_marking_enabled", false)):
		lines.append("Odblokuje oznaczanie ciężkich obiektów workiem wypornościowym.")
	if not bool(current.get("technician_support_enabled", false)) and bool(next.get("technician_support_enabled", false)):
		var multiplier := float(next.get("technician_suit_damage_multiplier", 1.0))
		lines.append("Odblokuje Technika: 2 naprawy i o %d%% mniej uszkodzeń kombinezonu." % int(round((1.0 - multiplier) * 100.0)))


func _workshop_recipe_names(level: int, exact_level: bool) -> Array[String]:
	var result: Array[String] = []
	for file_name in DirAccess.get_files_at("res://base_workbench/data/workshop_recipes"):
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var recipe = ResourceLoader.load("res://base_workbench/data/workshop_recipes".path_join(file_name))
		if recipe == null:
			continue
		var required_level := int(recipe.required_workshop_level)
		if (exact_level and required_level == level) or (not exact_level and required_level <= level):
			result.append(str(recipe.display_name))
	result.sort()
	return result


func _format_percent(value: float) -> String:
	var percent := value * 100.0
	if is_equal_approx(percent, roundf(percent)):
		return "%d%%" % int(round(percent))
	return "%.1f%%" % percent


func _format_percentage_points(value: float) -> String:
	var percent := value * 100.0
	if is_equal_approx(percent, roundf(percent)):
		return "%d p.p." % int(round(percent))
	return "%.1f p.p." % percent
