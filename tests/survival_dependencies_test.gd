extends SceneTree

const CompetencySystemScript := preload("res://scripts/base/CompetencySystem.gd")

const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const BuildingWorkSystemScript := preload("res://scripts/base/BuildingWorkSystem.gd")
const EndOfDayResolverScript := preload("res://scripts/base/EndOfDayResolver.gd")
const WorkerAssignmentSystemScript := preload("res://scripts/base/WorkerAssignmentSystem.gd")
const WorkPaceSystemScript := preload("res://scripts/base/WorkPaceSystem.gd")
const ProductionSystemScript := preload("res://scripts/base/ProductionSystem.gd")
const PolicyStateScript := preload("res://scripts/data/PolicyState.gd")
const ReportStateScript := preload("res://scripts/data/ReportState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")

var _failed := false

func _initialize() -> void:
	_verify_survivor_blocker_contract()

	var resolver = EndOfDayResolverScript.new()
	var report = ReportStateScript.new()

	var regular = _state()
	_add_building(regular, "fishing", "fishing_hut", "top_left", 1, ["anka"])
	var regular_food: int = regular.resources.get_amount(ResourceIdsScript.FOOD)
	resolver._resolve_fishing(regular, report)
	_assert(regular.resources.get_amount(ResourceIdsScript.FOOD) - regular_food == 5, "A rested regular worker should produce five food in Fishing Hut I.")

	var baseline = _state()
	_add_building(baseline, "fishing", "fishing_hut", "top_left", 1, ["mira"])
	var baseline_food: int = baseline.resources.get_amount(ResourceIdsScript.FOOD)
	resolver._resolve_fishing(baseline, report)
	var baseline_output: int = baseline.resources.get_amount(ResourceIdsScript.FOOD) - baseline_food
	_assert(baseline_output == 6, "A rested fisher specialist should produce six food in Fishing Hut I.")

	var pressured = _state()
	_add_building(pressured, "fishing", "fishing_hut", "top_left", 1, ["mira"])
	pressured.platform.fishing_pressure = 0.50
	var pressured_food: int = pressured.resources.get_amount(ResourceIdsScript.FOOD)
	resolver._resolve_fishing(pressured, report)
	var pressured_output: int = pressured.resources.get_amount(ResourceIdsScript.FOOD) - pressured_food
	_assert(pressured_output < baseline_output, "Fishing pressure should reduce the next actual catch.")
	var pressure_after_fishing: float = pressured.platform.fishing_pressure
	pressured.find_survivor("mira").fatigue = 95
	resolver._resolve_fishing(pressured, report)
	_assert(pressured.platform.fishing_pressure < pressure_after_fishing, "An idle fishing ground should regenerate when no capable worker can fish.")

	var fatigued = _state()
	_add_building(fatigued, "fishing", "fishing_hut", "top_left", 1, ["mira"])
	fatigued.find_survivor("mira").fatigue = 70
	var fatigued_food: int = fatigued.resources.get_amount(ResourceIdsScript.FOOD)
	resolver._resolve_fishing(fatigued, report)
	_assert(fatigued.resources.get_amount(ResourceIdsScript.FOOD) - fatigued_food < baseline_output, "Fatigue should reduce building output instead of being a display-only number.")

	var assigned_only_state = _state()
	_add_building(assigned_only_state, "assigned_workshop", "workshop", "bottom_left", 1, ["anka"])
	assigned_only_state.find_survivor("anka").fatigue = 20
	EndOfDayResolverScript.new()._resolve_fatigue(assigned_only_state, null, ReportStateScript.new())
	_assert(assigned_only_state.find_survivor("anka").fatigue == 8, "A remembered assignment without a committed work event should recover fatigue instead of creating a phantom work penalty.")

	var fatigue_state = _state()
	var fatigue_workshop = _add_building(fatigue_state, "workshop", "workshop", "bottom_left", 1, ["anka"])
	fatigue_state.find_survivor("mira").fatigue = 50
	var dive_result = DiveResultScript.new()
	dive_result.diver_id = "igor"
	dive_result.dive_duration = 240.0
	var fatigue_resolver = EndOfDayResolverScript.new()
	fatigue_resolver._commit_work_event("mechanik", "production", ["anka"], true, true, fatigue_workshop.id, PolicyStateScript.WORK_PACE_NORMAL)
	fatigue_resolver._commit_work_event("nurek", "dive", ["igor"], false, true, "diving_station", PolicyStateScript.WORK_PACE_NORMAL)
	fatigue_resolver._resolve_fatigue(fatigue_state, dive_result, report)
	_assert(fatigue_state.find_survivor("anka").fatigue == 8, "A worker should gain fatigue from normal work pace.")
	_assert(fatigue_state.find_survivor("mira").fatigue == 38, "An unassigned resident should recover fatigue.")
	_assert(fatigue_state.find_survivor("igor").fatigue == 18, "A diver should gain duration-scaled fatigue after the dive is recorded as real Station work.")
	var multi_work_state = _state()
	var multi_workshop = _add_building(multi_work_state, "multi_workshop", "workshop", "bottom_left", 1, ["anka"])
	var multi_work_resolver = EndOfDayResolverScript.new()
	multi_work_resolver._commit_work_event("mechanik", "platform_repair", ["anka"], true, true, multi_workshop.id, PolicyStateScript.WORK_PACE_NORMAL)
	multi_work_resolver._commit_work_event("mechanik", "production", ["anka"], true, true, multi_workshop.id, PolicyStateScript.WORK_PACE_INTENSE)
	multi_work_resolver._resolve_fatigue(multi_work_state, null, ReportStateScript.new())
	_assert(multi_work_state.find_survivor("anka").fatigue == 14, "Several confirmed tasks on one day should charge the same worker only once at the highest applicable pace.")

	var combined_hope_state = _state()
	combined_hope_state.resources.set_amount(ResourceIdsScript.HOPE, 50)
	combined_hope_state.difficulty_profile.hope_loss_multiplier = 2.0
	combined_hope_state.difficulty_profile.hope_gain_multiplier = 0.5
	var combined_hope_resolver = EndOfDayResolverScript.new()
	combined_hope_resolver._work_hope_delta_today = -3
	combined_hope_resolver._community_hope_gain_today = 2
	combined_hope_resolver._resolve_hope(combined_hope_state, null, ReportStateScript.new())
	_assert(combined_hope_state.resources.get_amount(ResourceIdsScript.HOPE) == 48, "Difficulty should multiply the combined -1 Hope result once, after work tension and Community contribution are aggregated.")
	var warning_state = _state()
	var warning_workshop = _add_building(warning_state, "warning_workshop", "workshop", "bottom_left", 1, ["mira"])
	warning_state.find_survivor("mira").fatigue = 84
	var fatigue_report = ReportStateScript.new()
	var warning_resolver = EndOfDayResolverScript.new()
	warning_resolver._commit_work_event("mechanik", "production", ["mira"], true, true, warning_workshop.id, PolicyStateScript.WORK_PACE_NORMAL)
	warning_resolver._resolve_fatigue(warning_state, null, fatigue_report)
	_assert(_contains_fragment(fatigue_report.warnings, "nie może nurkować i pracuje bardzo słabo") and _contains_fragment(fatigue_report.warnings, "od 90") and not _contains_fragment(fatigue_report.warnings, "nie może bezpiecznie pracować ani nurkować"), "The fatigue warning must distinguish the 85 diving threshold from the 90 work threshold.")
	var threshold_survivor = warning_state.find_survivor("mira")
	threshold_survivor.fatigue = 85
	_assert(threshold_survivor.can_work() and not threshold_survivor.can_dive(), "Fatigue 85-89 should still permit weak work while blocking dives.")

	var exhausted = fatigue_state.find_survivor("mira")
	exhausted.fatigue = 90
	_assert(not exhausted.can_work() and not exhausted.can_dive(), "Extreme fatigue should block work and diving readiness.")
	var empty_building = _add_building(fatigue_state, "community", "community_house", "top_right", 1, [])
	_assert(not WorkerAssignmentSystemScript.new().assign_worker(fatigue_state, "mira", empty_building.id, 1), "The assignment UI domain should reject an exhausted worker.")

	var morale_state = _state()
	var worker = morale_state.find_survivor("anka")
	var normal_efficiency: float = worker.work_efficiency()
	worker.competency_levels["cooperation"] = 3
	_assert(is_equal_approx(worker.work_efficiency(), minf(normal_efficiency * 1.12, 1.20)), "Cooperation III must compose exactly +12% into the canonical work-efficiency consumer.")
	worker.competency_levels.clear()
	worker.morale = 15
	_assert(worker.work_efficiency() < normal_efficiency and not worker.can_dive(), "Low personal morale should reduce work and block unsafe diving.")
	morale_state.resources.set_amount(ResourceIdsScript.HOPE, 10)
	resolver._resolve_morale(morale_state, report)
	_assert(worker.morale < 15, "Low community Hope plus missing ration should pull personal morale down.")

	var integrity_state = _state()
	var integrity_workshop = _add_building(integrity_state, "integrity_workshop", "workshop", "bottom_left", 1, ["anka"])
	var work_system = BuildingWorkSystemScript.new()
	var workshop_definition = ResourceLoader.load("res://data/buildings/workshop.tres")
	var workshop_capabilities: Dictionary = workshop_definition.get_level_definition(1).capabilities
	var workshop_workforce: Dictionary = work_system.workforce_from_capable_ids(
		integrity_state,
		workshop_definition,
		["anka"],
		"repair_bonus"
	)
	integrity_state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 20)
	var low_integrity_output: float = float(work_system.project_platform_repair(
		workshop_capabilities,
		workshop_workforce,
		WorkPaceSystemScript.pace_for_building(integrity_state, integrity_workshop),
		20,
		100,
		1.0,
		0.0
	).get("work_output_multiplier", 0.0))
	integrity_state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 70)
	var sound_integrity_output: float = float(work_system.project_platform_repair(
		workshop_capabilities,
		workshop_workforce,
		WorkPaceSystemScript.pace_for_building(integrity_state, integrity_workshop),
		70,
		100,
		1.0,
		0.0
	).get("work_output_multiplier", 0.0))
	_assert(low_integrity_output < sound_integrity_output, "Platform integrity should affect real daily work output.")
	integrity_workshop.work_pace = PolicyStateScript.WORK_PACE_INTENSE
	integrity_state.current_day_plan.sync_from_state(integrity_state)
	var intense_output: float = float(work_system.project_platform_repair(
		workshop_capabilities,
		workshop_workforce,
		WorkPaceSystemScript.pace_for_building(integrity_state, integrity_workshop),
		70,
		100,
		1.0,
		0.0
	).get("work_output_multiplier", 0.0))
	_assert(intense_output > sound_integrity_output, "Intense pace should increase real output for the selected building after being frozen in the day plan.")

	var production_state = _state()
	var workshop = _add_building(production_state, "workshop", "workshop", "bottom_left", 1, ["anka"])
	var production = ProductionSystemScript.new()
	var recipe = ResourceLoader.load("res://data/workshop_recipes/diving_lantern_mk2.tres")
	_assert(production.queue_recipe(production_state, workshop, recipe), "A capable staffed workshop should queue a craft.")
	production_state.find_survivor("anka").fatigue = 95
	var exhausted_result: Dictionary = production.resolve_workshop_queue(production_state, report)
	_assert(not exhausted_result.worked and exhausted_result.completed == 0 and workshop.queued_production_orders.size() == 1, "An exhausted workshop crew should postpone, not magically finish or delete, queued production.")
	production_state.find_survivor("anka").fatigue = 0
	var resumed_result: Dictionary = production.resolve_workshop_queue(production_state, report)
	_assert(resumed_result.worked and resumed_result.completed == 1 and production_state.diving_equipment.owns("diving_lantern_mk2"), "Production should resume once a capable worker is available.")

	var easy_repair_cost := _five_day_repair_cost(0.8, resolver, report)
	var standard_repair_cost := _five_day_repair_cost(1.0, resolver, report)
	var hard_repair_cost := _five_day_repair_cost(1.2, resolver, report)
	_assert([easy_repair_cost, standard_repair_cost, hard_repair_cost] == [4, 5, 6], "Five real Workshop repairs should cost 4/5/6 scrap on gentle/standard/harsh settings instead of collapsing to the same rounded value.")

	if _failed:
		quit(1)
		return
	print("Survival dependencies test passed: hunger, fatigue, morale, work pace, integrity, fishing pressure, staffing and production affect one another.")
	quit(0)

func _state(profile = null):
	var state = GameStateScript.new()
	state.setup_new_campaign(805, profile if profile != null else DifficultyProfileScript.new())
	state.tutorial.complete()
	for resource_id in ResourceIdsScript.all():
		state.resources.set_amount(resource_id, 100)
	state.resources.set_amount(ResourceIdsScript.HOPE, 55)
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 70)
	return state


func _verify_survivor_blocker_contract() -> void:
	var survivor = _ready_survivor()
	for status in [SurvivorStateScript.Status.AVAILABLE, SurvivorStateScript.Status.WORKING, SurvivorStateScript.Status.RESTING]:
		survivor.status = status
		_assert(survivor.work_blocker().is_empty() and survivor.can_work(), "Available, working and resting residents at the exact safe limits must remain eligible to work.")

	for status in [SurvivorStateScript.Status.AVAILABLE, SurvivorStateScript.Status.WORKING]:
		survivor.status = status
		_assert(survivor.dive_blocker().is_empty() and survivor.can_dive(), "Available and working residents at the exact safe limits must remain eligible to dive.")

	var status_reason_templates := {
		SurvivorStateScript.Status.DIVING: "Mieszkaniec jest obecnie na wyprawie i nie może %s.",
		SurvivorStateScript.Status.INJURED: "Uraz nie pozwala mieszkańcowi %s.",
		SurvivorStateScript.Status.DEAD: "Zmarły mieszkaniec nie może %s.",
		SurvivorStateScript.Status.DEPARTED: "Mieszkaniec opuścił Przystań i nie może %s.",
	}
	for status in status_reason_templates:
		survivor = _ready_survivor()
		survivor.status = int(status)
		var reason_template := str(status_reason_templates[status])
		_assert(survivor.work_blocker() == reason_template % "pracować" and not survivor.can_work(), "Every non-working resident status must expose its canonical work blocker.")
		_assert(survivor.dive_blocker() == reason_template % "nurkować" and not survivor.can_dive(), "Every absent or incapacitated resident status must expose its canonical dive blocker.")

	survivor = _ready_survivor()
	survivor.status = SurvivorStateScript.Status.RESTING
	_assert(survivor.dive_blocker() == "Bieżący status mieszkańca nie pozwala mu nurkować." and not survivor.can_dive(), "Resting must remain valid for work while exposing the canonical dive blocker.")

	survivor = _ready_survivor()
	survivor.health = 35
	survivor.hunger = 84
	survivor.fatigue = 89
	survivor.morale = 10
	_assert(survivor.work_blocker().is_empty() and survivor.can_work(), "Work thresholds must be inclusive on the safe side: health 35%, hunger 84, fatigue 89 and morale 10.")
	survivor.health = 34
	survivor.hunger = 85
	survivor.fatigue = 90
	survivor.morale = 9
	_assert(survivor.work_blocker() == "Zdrowie jest niższe niż 35%.", "Health below 35% must have priority over all simultaneous work blockers.")
	survivor.health = 35
	_assert(survivor.work_blocker() == "Głód wynosi co najmniej 85%.", "Hunger 85 must be the next canonical work blocker once health reaches 35%.")
	survivor.hunger = 84
	_assert(survivor.work_blocker() == "Zmęczenie wynosi co najmniej 90%.", "Fatigue 90 must block work once higher-priority limits are safe.")
	survivor.fatigue = 89
	_assert(survivor.work_blocker() == "Morale jest niższe niż 10%.", "Morale 9 must block work once higher-priority limits are safe.")
	survivor.morale = 10
	_assert(survivor.work_blocker().is_empty() and survivor.can_work(), "Returning every work value to its exact safe boundary must clear the blocker.")

	survivor = _ready_survivor()
	survivor.health = 50
	survivor.hunger = 64
	survivor.fatigue = 84
	survivor.morale = 20
	_assert(survivor.dive_blocker().is_empty() and survivor.can_dive(), "Dive thresholds must be inclusive on the safe side: health 50%, hunger 64, fatigue 84 and morale 20.")
	survivor.health = 49
	survivor.hunger = 65
	survivor.fatigue = 85
	survivor.morale = 19
	_assert(survivor.dive_blocker() == "Zdrowie jest niższe niż 50%.", "Health below 50% must have priority over all simultaneous dive blockers.")
	survivor.health = 50
	_assert(survivor.dive_blocker() == "Głód wynosi co najmniej 65%.", "Hunger 65 must be the next canonical dive blocker once health reaches 50%.")
	survivor.hunger = 64
	_assert(survivor.dive_blocker() == "Zmęczenie wynosi co najmniej 85%.", "Fatigue 85 must block diving once higher-priority limits are safe.")
	survivor.fatigue = 84
	_assert(survivor.dive_blocker() == "Morale jest niższe niż 20%.", "Morale 19 must block diving once higher-priority limits are safe.")
	survivor.morale = 20
	_assert(survivor.dive_blocker().is_empty() and survivor.can_dive(), "Returning every dive value to its exact safe boundary must clear the blocker.")

	var valid_stat_ids := ["health", "oxygen", "oxygen_capacity", "carry", "carry_capacity"]
	for stat_id in valid_stat_ids:
		survivor = _ready_survivor()
		survivor.unspent_skill_points = 1
		_assert(survivor.skill_point_blocker(stat_id).is_empty() and survivor.can_spend_skill_point(stat_id), "Every canonical development path and compatibility alias must accept one available skill point.")
		survivor.unspent_skill_points = 0
		_assert(survivor.skill_point_blocker(stat_id) == "Brak niewydanych punktów rozwoju." and not survivor.can_spend_skill_point(stat_id), "Every valid development path must expose the no-points blocker exactly at zero.")

	for invalid_stat_id in ["", "Health", "unknown"]:
		survivor = _ready_survivor()
		survivor.unspent_skill_points = 1
		_assert(survivor.skill_point_blocker(invalid_stat_id) == "Ta ścieżka rozwoju nie istnieje." and not survivor.can_spend_skill_point(invalid_stat_id), "Unknown development paths must expose the canonical domain blocker even when a point is available.")
		survivor.unspent_skill_points = 0
		_assert(survivor.skill_point_blocker(invalid_stat_id) == "Ta ścieżka rozwoju nie istnieje.", "An unknown path must take priority over the simultaneous no-points blocker.")

	survivor = _ready_survivor()
	survivor.unspent_skill_points = 4
	for competency_id in CompetencySystemScript.IDS:
		_assert(survivor.skill_point_blocker(competency_id).is_empty(), "Every passive competency must be a canonical development path.")
	_assert(survivor.spend_skill_point("swimming") and CompetencySystemScript.level(survivor, "swimming") == 1, "A competency purchase must spend one point and persist its first level.")
	survivor.spend_skill_point("swimming"); survivor.spend_skill_point("swimming")
	_assert(is_equal_approx(CompetencySystemScript.swimming_multiplier(survivor), 1.15), "Swimming level three must provide exactly +15% speed.")
	_assert(survivor.skill_point_blocker("swimming") == "Ta kompetencja osiągnęła maksymalny poziom.", "A level-three competency must reject another purchase before checking spare points.")


func _ready_survivor():
	var survivor = SurvivorStateScript.new()
	survivor.base_max_health = 100
	survivor.health_bonus = 0
	survivor.health = 100
	survivor.hunger = 0
	survivor.fatigue = 0
	survivor.morale = 55
	survivor.status = SurvivorStateScript.Status.AVAILABLE
	return survivor

func _contains_fragment(lines: Array[String], fragment: String) -> bool:
	for line in lines:
		if line.contains(fragment):
			return true
	return false


func _five_day_repair_cost(multiplier: float, resolver, report) -> int:
	var profile = DifficultyProfileScript.new()
	profile.repair_cost_multiplier = multiplier
	var state = _state(profile)
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 20)
	_add_building(state, "workshop", "workshop", "bottom_left", 1, ["anka"])
	var scrap_before: int = state.resources.get_amount(ResourceIdsScript.SCRAP)
	for _day in range(5):
		_assert(resolver._resolve_workshop_repairs(state, report), "Każdy dzień próby kosztu powinien wykonać rzeczywistą naprawę Warsztatu.")
	return scrap_before - state.resources.get_amount(ResourceIdsScript.SCRAP)

func _add_building(state, id: String, definition_id: String, slot_id: String, level: int, workers: Array[String]):
	var building = BuildingStateScript.new()
	building.id = id
	building.definition_id = definition_id
	building.slot_id = slot_id
	building.level = level
	building.is_built = true
	building.assigned_survivor_ids.assign(workers)
	state.buildings.append(building)
	for survivor_id in workers:
		var survivor = state.find_survivor(str(survivor_id))
		if survivor != null:
			survivor.current_assignment = id
			survivor.status = SurvivorStateScript.Status.WORKING
	return building

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Survival dependencies test failed: " + message)
