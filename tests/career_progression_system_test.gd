extends SceneTree

const GameDatabaseScript := preload("res://scripts/core/GameDatabase.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const ReportStateScript := preload("res://scripts/data/ReportState.gd")
const CareerProgressionSystemScript := preload("res://scripts/survivors/CareerProgressionSystem.gd")
const ProfessionTalentSystemScript := preload("res://scripts/survivors/ProfessionTalentSystem.gd")
const EndOfDayResolverScript := preload("res://scripts/campaign/EndOfDayResolver.gd")
const ExpeditionPreparationSystemScript := preload("res://scripts/diving/ExpeditionPreparationSystem.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const PolicyStateScript := preload("res://scripts/data/PolicyState.gd")

var _failed := false

func _initialize() -> void:
	_test_profession_data_and_derived_ranks()
	_test_manual_development_requires_active_community_house()
	_test_manual_secondary_promotion_and_bonus()
	_test_profession_talent_catalog_and_selection()
	_test_actual_work_integration()
	_test_dive_and_support_experience()
	_test_daily_deduplication()
	if _failed:
		quit(1)
		return
	print("Career progression system test passed: capable staffing grants general XP, confirmed work grants practice, and career gates remain canonical.")
	quit(0)

func _test_profession_data_and_derived_ranks() -> void:
	var database = GameDatabaseScript.new()
	database.load_definitions()
	_assert(database.is_valid(), "Profession resources should pass the complete GameDatabase validation: %s" % "; ".join(database.validation_errors))
	_assert(database.professions.size() == 6, "Exactly six executable career paths should be loaded for the six current buildings.")
	database.free()

	var state = _state()
	var survivor = state.find_survivor("mira")
	var career = CareerProgressionSystemScript.new()
	_assert(career.get_rank_id(survivor, "medyk") == CareerProgressionSystemScript.RANK_NOVICE, "A resident without practice should begin as a novice in an unrelated career.")
	for shift in range(2):
		var result := career.record_work(survivor, "medyk")
		_assert(not result.is_empty(), "A confirmed medical shift should produce a progression result.")
	_assert(survivor.level == 2 and survivor.experience == 100 and survivor.get_job_experience("medyk") == 40, "Two staffed shifts should grant 200 personal XP and 40 medical practice.")
	_assert(career.get_rank_id(survivor, "medyk") == CareerProgressionSystemScript.RANK_APPRENTICE, "Forty practice should derive the apprentice rank without extra saved rank state.")
	var infirmary_definition = ResourceLoader.load("res://base_workbench/data/buildings/infirmary.tres")
	_assert(is_zero_approx(float(infirmary_definition.get_specialist_bonus_value(survivor, "healing_bonus"))), "An apprentice should not receive the full specialist bonus before formal promotion.")
	for shift in range(8):
		career.record_work(survivor, "medyk")
	_assert(survivor.level == 6 and survivor.experience == 0 and survivor.unspent_skill_points == 5, "Ten staffed workdays should grant 1000 personal XP across the rising level thresholds.")
	_assert(survivor.get_job_experience("medyk") == 100 and career.get_rank_id(survivor, "medyk") == CareerProgressionSystemScript.RANK_READY, "Practice should cap at 100 and expose readiness instead of auto-promoting.")

	var normalized = SurvivorStateScript.new()
	normalized.profession = "mechanik"
	normalized.secondary_profession = "mechanik"
	normalized.experience_by_job = {"": 50, "medyk": -12, "rybak": 40}
	normalized.ensure_compatibility()
	_assert(normalized.secondary_profession.is_empty() and not normalized.experience_by_job.has("") and normalized.get_job_experience("medyk") == 0 and normalized.get_job_experience("rybak") == 40, "Normalization should remove duplicate specialization, empty keys and negative practice.")

func _test_manual_development_requires_active_community_house() -> void:
	var state = _state()
	var survivor = state.find_survivor("mira")
	var career = CareerProgressionSystemScript.new()
	survivor.unspent_skill_points = 1
	var initial_health: int = survivor.health
	var initial_max_health: int = survivor.get_max_health()

	_assert(
		career.development_blocker(state, survivor, "health").contains("Domu Wspólnoty I"),
		"Spending development points without a Community House should expose the canonical level-one requirement."
	)
	_assert(
		not career.spend_development_point(state, survivor.id, "health")
		and survivor.unspent_skill_points == 1
		and survivor.health == initial_health
		and survivor.get_max_health() == initial_max_health,
		"A rejected development command without a Community House must not mutate the resident."
	)

	var house = _add_building(state, "community", "community_house", "top_right", 1, [])
	_assert(
		house.is_active()
		and career.can_spend_development_point(state, survivor, "health")
		and career.development_blocker(state, survivor, "health").is_empty(),
		"An active Community House I should unlock personal development."
	)

	survivor.unspent_skill_points = 0
	_assert(
		career.development_blocker(state, survivor, "health") == "Brak niewydanych punktów rozwoju."
		and not career.spend_development_point(state, survivor.id, "health")
		and survivor.get_max_health() == initial_max_health,
		"The canonical command should preserve the resident when no point is available."
	)

	survivor.unspent_skill_points = 1
	_assert(
		career.development_blocker(state, survivor, "unknown_stat") == "Ta ścieżka rozwoju nie istnieje."
		and not career.spend_development_point(state, survivor.id, "unknown_stat")
		and survivor.unspent_skill_points == 1
		and survivor.get_max_health() == initial_max_health,
		"An unknown development path should be rejected without consuming the available point."
	)

	_assert(career.spend_development_point(state, survivor.id, "health"), "One valid command should spend one development point in an active Community House I.")
	_assert(
		survivor.unspent_skill_points == 0
		and survivor.health == initial_health + SurvivorStateScript.HEALTH_PER_SKILL_POINT
		and survivor.get_max_health() == initial_max_health + SurvivorStateScript.HEALTH_PER_SKILL_POINT,
		"A successful health development command should apply exactly one canonical stat increase and consume exactly one point."
	)
	_assert(
		not career.spend_development_point(state, survivor.id, "health")
		and survivor.unspent_skill_points == 0
		and survivor.health == initial_health + SurvivorStateScript.HEALTH_PER_SKILL_POINT
		and survivor.get_max_health() == initial_max_health + SurvivorStateScript.HEALTH_PER_SKILL_POINT,
		"Repeating the command after the point is consumed must not apply the development effect twice."
	)

func _test_manual_secondary_promotion_and_bonus() -> void:
	var state = _state()
	var survivor = state.find_survivor("mira")
	var career = CareerProgressionSystemScript.new()
	survivor.set_job_experience("mechanik", 100)
	survivor.current_assignment = "fishing_shift"
	var house = _add_building(state, "community", "community_house", "top_right", 1, [])
	_assert(not career.can_promote(state, survivor, "mechanik") and career.promotion_blocker(state, survivor, "mechanik").contains("Dom Wspólnoty II"), "A level-one Community House should show the exact Sala zgromadzeń blocker.")
	house.level = 2
	_assert(career.promote_secondary_profession(state, survivor.id, "mechanik"), "A present ready resident should receive one secondary profession in an active Community House II.")
	_assert(survivor.profession == "rybak" and survivor.secondary_profession == "mechanik" and survivor.current_assignment == "fishing_shift", "Promotion must preserve the primary profession and current staffing assignment.")
	var workshop_definition = ResourceLoader.load("res://base_workbench/data/buildings/workshop.tres")
	_assert(is_equal_approx(float(workshop_definition.get_specialist_bonus_value(survivor, "repair_bonus")), 1.0), "The secondary mechanic profession should activate the full canonical Workshop bonus.")
	_assert(not career.promote_secondary_profession(state, survivor.id, "medyk"), "A resident may not replace the permanent secondary profession with a third path.")
	var practice_before: int = int(survivor.get_job_experience("medyk"))
	career.record_work(survivor, "medyk")
	_assert(survivor.get_job_experience("medyk") == practice_before + 20, "Real work should remain visible as practice even after the only secondary specialization slot is used.")
	_assert(career.get_rank_id(survivor, "medyk") == CareerProgressionSystemScript.RANK_LOCKED and career.days_until_promotion(survivor, "medyk") == 0, "Other career paths should become explicitly locked instead of promising progress after the secondary slot is used.")

	var departed = SurvivorStateScript.new()
	departed.id = "departed_candidate"
	departed.display_name = "Była mieszkanka"
	departed.profession = "kucharz"
	departed.status = SurvivorStateScript.Status.DEPARTED
	departed.set_job_experience("nurek", 100)
	state.survivors.append(departed)
	_assert(not career.can_promote(state, departed, "nurek"), "Departed residents must never be promotable as people present in the settlement.")


func _test_profession_talent_catalog_and_selection() -> void:
	var talents = ProfessionTalentSystemScript.new()
	_assert(talents.validation_errors().is_empty(), "The authored profession-talent catalog should contain exactly two valid choices for every profession: %s" % "; ".join(talents.validation_errors()))
	_assert(talents.get_all_talent_ids().size() == 12, "The first profession-talent package should expose exactly twelve stable talent IDs.")
	_assert(talents.get_talent_ids_for_profession("rybak") == ["rybak_straznik_lowiska", "rybak_polow_forsowny"], "Fishing talents should retain their authored choice order.")
	var forced_catch = talents.get_definition("rybak_polow_forsowny")
	_assert(forced_catch != null and int(forced_catch.parameters.get("food_bonus", 0)) == 1 and is_equal_approx(float(forced_catch.parameters.get("pressure_multiplier", 0.0)), 1.5), "Talent resources should expose their exact domain parameters instead of hiding balance values in UI code.")
	var mediator = talents.get_definition("organizator_mediator")
	var instructor = talents.get_definition("organizator_instruktor")
	var prophylaxis = talents.get_definition("medyk_profilaktyk")
	var scout = talents.get_definition("nurek_zwiadowca")
	_assert(mediator != null and str(mediator.description).contains("Domu Wspólnoty") and str(mediator.description).contains("Napięcia pracy") and str(mediator.description).contains("przed mnożnikiem trudności"), "Mediator UI copy should state the exact work-tension boundary.")
	_assert(instructor != null and str(instructor.description).contains("tym samym rzeczywistym zdarzeniu pracy") and str(instructor.description).contains("bez talentu Instruktor") and str(instructor.description).contains("maksymalnie do 100"), "Instructor UI copy should state target selection and the practice cap.")
	_assert(prophylaxis != null and str(prophylaxis.description).contains("nie zużywa leku") and str(prophylaxis.description).contains("nie usuwa istniejącego Narażenia") and str(prophylaxis.description).contains("inne źródła"), "Prophylaxis UI copy should distinguish contact prevention from treatment.")
	_assert(scout != null and str(scout.description).contains("jeden z 8 kierunków") and str(scout.description).contains("niepokonanego zagrożenia") and str(scout.description).contains("bez dystansu, nazwy i pozycji"), "Scout UI copy should state the exact information boundary.")

	var state = _state()
	var survivor = state.find_survivor("mira")
	var career = CareerProgressionSystemScript.new()
	survivor.set_job_experience("rybak", 100)
	var house = _add_building(state, "community", "community_house", "top_right", 1, [])
	_assert(not career.can_select_profession_talent(state, survivor, "rybak_straznik_lowiska") and career.profession_talent_selection_blocker(state, survivor, "rybak_straznik_lowiska").contains("Domu Wspólnoty II"), "A formal specialist with enough practice should still need an active Community House II for the permanent talent choice.")
	house.level = 2
	state.current_day_plan.locked = true
	_assert(not career.can_select_profession_talent(state, survivor, "rybak_straznik_lowiska") and career.profession_talent_selection_blocker(state, survivor, "rybak_straznik_lowiska").contains("zablokowany"), "A locked day plan should reject talent selection without changing the resident.")
	state.current_day_plan.locked = false
	var points_before: int = survivor.unspent_skill_points
	_assert(career.can_select_profession_talent(state, survivor, "rybak_straznik_lowiska"), "A present formal specialist with 100 practice should be able to choose either profession talent in an active Community House II.")
	_assert(career.select_profession_talent(state, survivor.id, "rybak_straznik_lowiska"), "The canonical command should apply one valid profession talent.")
	_assert(
		survivor.profession_talent_ids == {"rybak": "rybak_straznik_lowiska"}
		and survivor.unspent_skill_points == points_before
		and ProfessionTalentSystemScript.selected_talent_id(survivor, "rybak") == "rybak_straznik_lowiska"
		and ProfessionTalentSystemScript.has_talent(survivor, "rybak_straznik_lowiska"),
		"Talent selection should be free, stored under its profession and visible through the canonical query API."
	)
	_assert(not career.select_profession_talent(state, survivor.id, "rybak_polow_forsowny") and survivor.profession_talent_ids == {"rybak": "rybak_straznik_lowiska"}, "The mutually exclusive alternative must remain permanently blocked without mutating the selected talent.")
	_assert(not career.can_select_profession_talent(state, survivor, "medyk_rehabilitant") and career.profession_talent_selection_blocker(state, survivor, "medyk_rehabilitant").contains("formalnej specjalizacji"), "Practice alone or an unrelated profession must never unlock another profession's talent.")

func _test_actual_work_integration() -> void:
	var unassigned_state = _state()
	var unassigned = unassigned_state.find_survivor("anka")
	EndOfDayResolverScript.new().resolve(unassigned_state, null, false)
	_assert(unassigned.level == 1 and unassigned.experience == 0 and unassigned.experience_by_job.is_empty(), "An unassigned resident must receive neither staffing XP nor profession practice.")

	var fishing_state = _state()
	_add_building(fishing_state, "fishing", "fishing_hut", "top_left", 1, ["anka"])
	var anka = fishing_state.find_survivor("anka")
	EndOfDayResolverScript.new().resolve(fishing_state, null, false)
	_assert(anka.level == 2 and anka.experience == 0 and anka.get_job_experience("rybak") == 20, "A staffed Fishing Hut should grant 100 personal XP and its real catch should grant fishing practice.")

	var idle_workshop_state = _state()
	_add_building(idle_workshop_state, "workshop", "workshop", "bottom_left", 1, ["anka"])
	idle_workshop_state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 100)
	var idle_mechanic = idle_workshop_state.find_survivor("anka")
	EndOfDayResolverScript.new().resolve(idle_workshop_state, null, false)
	_assert(idle_mechanic.level == 2 and idle_mechanic.experience == 0 and idle_mechanic.get_job_experience("mechanik") == 0, "A capable idle Workshop assignment should grant 100 personal XP but no mechanics practice.")

	var empty_infirmary_state = _state()
	_add_building(empty_infirmary_state, "infirmary", "infirmary", "center", 1, ["anka"])
	var idle_medic = empty_infirmary_state.find_survivor("anka")
	EndOfDayResolverScript.new().resolve(empty_infirmary_state, null, false)
	_assert(idle_medic.level == 2 and idle_medic.experience == 0 and idle_medic.get_job_experience("medyk") == 0, "An Infirmary without a patient should grant staffing XP but no medical practice.")

	var closed_kitchen_state = _state()
	_add_building(closed_kitchen_state, "kitchen", "kitchen", "top_center", 1, ["anka"])
	closed_kitchen_state.active_policies.ration_policy = PolicyStateScript.RationPolicy.NONE
	closed_kitchen_state.current_day_plan.sync_from_state(closed_kitchen_state)
	var idle_cook = closed_kitchen_state.find_survivor("anka")
	EndOfDayResolverScript.new().resolve(closed_kitchen_state, null, false)
	_assert(idle_cook.level == 2 and idle_cook.experience == 0 and idle_cook.get_job_experience("kucharz") == 0, "A Kitchen that issued no ration should grant staffing XP but no cooking practice.")

	var incapable_state = _state()
	_add_building(incapable_state, "fishing", "fishing_hut", "top_left", 1, ["anka"])
	var incapable = incapable_state.find_survivor("anka")
	incapable.fatigue = 95
	EndOfDayResolverScript.new().resolve(incapable_state, null, false)
	_assert(incapable.level == 1 and incapable.experience == 0 and incapable.get_job_experience("rybak") == 0, "A resident who is assigned but incapable in the frozen snapshot must receive neither staffing XP nor practice.")

	var tired_house_state = _state()
	_add_building(tired_house_state, "community", "community_house", "top_right", 1, ["anka"])
	var tired_organizer = tired_house_state.find_survivor("anka")
	tired_organizer.fatigue = 85
	EndOfDayResolverScript.new().resolve(tired_house_state, null, false)
	_assert(tired_organizer.fatigue >= 90 and tired_organizer.level == 2 and tired_organizer.get_job_experience("organizator") == 20, "A capable Community House worker should keep staffing XP and practice even if end-of-day fatigue later crosses the work threshold.")

	var ineffective_repair_state = _state()
	_add_building(ineffective_repair_state, "workshop", "workshop", "bottom_left", 1, ["mira"])
	var ineffective_worker = ineffective_repair_state.find_survivor("mira")
	ineffective_worker.health = 35
	ineffective_worker.hunger = 84
	ineffective_worker.fatigue = 89
	ineffective_worker.morale = 10
	var scrap_before: int = ineffective_repair_state.resources.get_amount(ResourceIdsScript.SCRAP)
	EndOfDayResolverScript.new().resolve(ineffective_repair_state, null, false)
	_assert(ineffective_repair_state.resources.get_amount(ResourceIdsScript.SCRAP) == scrap_before and ineffective_worker.level == 2 and ineffective_worker.get_job_experience("mechanik") == 0, "A zero-point repair must not consume scrap or grant practice, while valid staffing still grants personal XP.")

	var duplicate_assignment_state = _state()
	var fishing = _add_building(duplicate_assignment_state, "fishing", "fishing_hut", "top_left", 1, ["anka"])
	var kitchen = _add_building(duplicate_assignment_state, "kitchen", "kitchen", "top_center", 1, ["anka"])
	var duplicated_worker = duplicate_assignment_state.find_survivor("anka")
	EndOfDayResolverScript.new().resolve(duplicate_assignment_state, null, false)
	_assert(fishing.assigned_survivor_ids == ["anka"] and kitchen.assigned_survivor_ids.is_empty() and duplicated_worker.current_assignment == fishing.id, "Day resolution should reconcile a duplicate roster before freezing participants.")
	_assert(duplicated_worker.level == 2 and duplicated_worker.get_job_experience("rybak") == 20 and duplicated_worker.get_job_experience("kucharz") == 0, "One inconsistent roster entry must never reward or train two careers in the same day.")

func _test_dive_and_support_experience() -> void:
	var state = _state()
	var station = _add_building(state, "station", "diving_station", "bottom_right", 2, ["igor", "anka"])
	var diver = state.find_survivor("mira")
	var operator = state.find_survivor("anka")
	var station_definition = ResourceLoader.load("res://base_workbench/data/buildings/diving_station.tres")
	var preparation = ExpeditionPreparationSystemScript.new()
	_assert(preparation.select_diver(state, station, station_definition, diver.id), "The expedition fixture should select an unassigned diver explicitly.")
	var setup = preparation.build_setup(state, station, station_definition)
	_assert(setup != null and setup.operator_survivor_id == operator.id, "The expedition snapshot should freeze the exact support worker before day resolution.")
	state.current_expedition_setup = setup
	var result = DiveResultScript.new()
	result.diver_id = diver.id
	result.diver_dead = false
	result.experience_gained = 30
	result.oxygen_remaining = 40.0
	result.health_remaining = diver.health
	var report = EndOfDayResolverScript.new().resolve(state, result, false)
	_assert(diver.experience == 30 and diver.get_job_experience("nurek") == 20, "A returning non-specialist diver should keep exactly DiveResult personal XP and gain only diving practice, without a duplicate +10.")
	_assert(operator.level == 2 and operator.experience == 0 and operator.get_job_experience("nurek") == 20, "A capable frozen support worker should gain 100 staffing XP and diving practice for the real expedition.")
	_assert(_report_contains(report.entries, "Doświadczenie pracy"), "The end-of-day report should expose city work and career progression instead of changing hidden state.")

func _test_daily_deduplication() -> void:
	var state = _state()
	var resolver = EndOfDayResolverScript.new()
	resolver._commit_work_event("kucharz", "ration_preparation", ["mira"], true, true)
	resolver._commit_work_event("kucharz", "second_ration_pass", ["mira"], true, true)
	resolver._resolve_career_progression(state, ReportStateScript.new())
	var survivor = state.find_survivor("mira")
	_assert(survivor.level == 2 and survivor.experience == 0 and survivor.get_job_experience("kucharz") == 20, "Duplicate action records in one day must grant personal XP and profession practice only once.")

func _state():
	var state = GameStateScript.new()
	state.setup_new_campaign(940, DifficultyProfileScript.new())
	state.tutorial.complete()
	for resource_id in ResourceIdsScript.all():
		state.resources.set_amount(resource_id, 100)
	state.resources.set_amount(ResourceIdsScript.HOPE, 55)
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 70)
	return state

func _add_building(state, id: String, definition_id: String, slot_id: String, level: int, workers: Array[String]):
	var building = BuildingStateScript.new()
	building.id = id
	building.definition_id = definition_id
	building.slot_id = slot_id
	building.level = level
	building.is_built = true
	building.assigned_survivor_ids.assign(workers)
	state.buildings.append(building)
	if state.platform.slot_states.has(slot_id):
		var slot_data: Dictionary = state.platform.slot_states[slot_id]
		slot_data["building_id"] = building.id
		state.platform.slot_states[slot_id] = slot_data
	for survivor_id in workers:
		var survivor = state.find_survivor(str(survivor_id))
		if survivor != null:
			survivor.current_assignment = building.id
			survivor.status = SurvivorStateScript.Status.WORKING
	return building

func _report_contains(lines: Array[String], fragment: String) -> bool:
	for line in lines:
		if line.contains(fragment):
			return true
	return false

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Career progression system test failed: " + message)
