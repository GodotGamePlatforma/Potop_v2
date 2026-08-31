class_name RosterRotationSystem
extends RefCounted

const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const DiseaseCaseStateScript := preload("res://scripts/data/DiseaseCaseState.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")

const SUPPORTED_DURATION_DAYS: Array[int] = [2, 3, 4]
const MIN_FISHING_HUT_LEVEL := 2
const MIN_COMMUNITY_HOUSE_LEVEL := 1
const MAX_ACTIVE_BOAT_EXPEDITIONS := 1
const MAX_DAILY_DEPARTURES := 1
const MAX_RETURN_CANDIDATES := 2
const EXPEDITION_ID_PREFIX := "boat_expedition"
const CANDIDATE_ID_PREFIX := "expedition_recruit"
const DEPARTURE_WITH_PROVISIONS := "with_provisions"
const DEPARTURE_WITHOUT_PROVISIONS := "without_provisions"
const DEPARTURE_HOPE_WITH_PROVISIONS := -6
const DEPARTURE_HOPE_WITHOUT_PROVISIONS := -10
const DEPARTURE_VULNERABILITY_HOPE := -4
const PRESENCE_ACTIVE := "active"
const PRESENCE_WAITING_FOR_RETURN := "waiting_for_return"
const PRESENCE_LOST := "lost"
const VALID_CANDIDATE_PROFESSION_IDS: Array[String] = [
	"rybak",
	"kucharz",
	"mechanik",
	"medyk",
	"organizator",
	"nurek",
]


static func supported_duration_days() -> Array[int]:
	return SUPPORTED_DURATION_DAYS.duplicate()


static func is_supported_duration(duration_days: int) -> bool:
	return SUPPORTED_DURATION_DAYS.has(duration_days)


static func return_day(launch_day: int, duration_days: int) -> int:
	if launch_day < 1 or not is_supported_duration(duration_days):
		return -1
	return launch_day + duration_days


static func provision_food_cost(food_per_adult: int, duration_days: int) -> int:
	if food_per_adult < 1 or not is_supported_duration(duration_days):
		return -1
	return food_per_adult * duration_days


static func provision_cost(food_per_adult: int, duration_days: int) -> Dictionary:
	var food_cost := provision_food_cost(food_per_adult, duration_days)
	return {ResourceIdsScript.FOOD: food_cost} if food_cost > 0 else {}


static func expedition_instance_id(campaign_seed: int, sequence: int) -> String:
	if campaign_seed < 1 or sequence < 1:
		return ""
	return "%s:%d:%d" % [EXPEDITION_ID_PREFIX, campaign_seed, sequence]


static func candidate_instance_id(expedition_id: String, candidate_index: int) -> String:
	if expedition_id.strip_edges().is_empty() or candidate_index < 1 or candidate_index > MAX_RETURN_CANDIDATES:
		return ""
	return "%s:%s:%d" % [CANDIDATE_ID_PREFIX, expedition_id, candidate_index]


static func is_valid_candidate_profession(profession_id: String) -> bool:
	return VALID_CANDIDATE_PROFESSION_IDS.has(profession_id)


static func is_away_on_boat(survivor_id: String, active_expedition) -> bool:
	return (
		active_expedition != null
		and not survivor_id.strip_edges().is_empty()
		and str(active_expedition.get("leader_survivor_id")) == survivor_id
	)


static func living_survivors(survivors: Array) -> Array:
	var result: Array = []
	for survivor in survivors:
		if survivor != null and survivor.get_script() == SurvivorStateScript and survivor.is_alive():
			result.append(survivor)
	return result


static func present_survivors(survivors: Array, active_expedition = null) -> Array:
	var result: Array = []
	for survivor in living_survivors(survivors):
		if survivor.is_present_in_settlement() and not is_away_on_boat(str(survivor.id), active_expedition):
			result.append(survivor)
	return result


static func reserved_roster_count(survivors: Array) -> int:
	return living_survivors(survivors).size()


static func work_blocker(survivor, active_expedition = null) -> String:
	if survivor == null or survivor.get_script() != SurvivorStateScript:
		return "Nie znaleziono mieszkańca."
	if is_away_on_boat(str(survivor.id), active_expedition):
		return "Mieszkaniec prowadzi ekspedycję łodzią i nie może pracować w Przystani."
	return str(survivor.work_blocker())


static func dive_blocker(survivor, active_expedition = null) -> String:
	if survivor == null or survivor.get_script() != SurvivorStateScript:
		return "Nie znaleziono mieszkańca."
	if is_away_on_boat(str(survivor.id), active_expedition):
		return "Mieszkaniec prowadzi ekspedycję łodzią i nie może nurkować."
	return str(survivor.dive_blocker())


static func boat_leader_blocker(survivor, active_expedition = null) -> String:
	var blocker := dive_blocker(survivor, active_expedition)
	if not blocker.is_empty():
		return blocker
	for disease_case in survivor.disease_cases:
		if disease_case == null or disease_case.get_script() != DiseaseCaseStateScript:
			continue
		if not disease_case.is_valid() or int(disease_case.phase) != DiseaseCaseStateScript.Phase.IMMUNE:
			return "Dowódca może wypłynąć wyłącznie bez aktywnego przypadku choroby albo z odpornością."
	return ""


static func boat_terminal_boundary_blocker(
	current_day: int,
	duration_days: int,
	black_front_active: bool,
	black_front_days_remaining: int,
	black_front_arrived: bool,
	energy_choice_pending: bool
) -> String:
	if current_day < 1 or not is_supported_duration(duration_days):
		return "Nie można wyliczyć granicy powrotu ekspedycji."
	if black_front_arrived or energy_choice_pending:
		return "Po nadejściu Czarnego Frontu nie można rozpocząć nowej ekspedycji łodzią."
	if black_front_active and (black_front_days_remaining < 1 or duration_days >= black_front_days_remaining):
		return "Ekspedycja nie może przekroczyć znanego terminu Czarnego Frontu."
	return ""


static func settlement_presence_mode(
	living_survivor_count: int,
	present_survivor_count: int,
	active_return_day: int,
	current_day: int
) -> String:
	if living_survivor_count < 1:
		return PRESENCE_LOST
	if present_survivor_count > 0:
		return PRESENCE_ACTIVE
	if active_return_day >= current_day and current_day >= 1:
		return PRESENCE_WAITING_FOR_RETURN
	return PRESENCE_LOST


static func departure_vulnerability_reasons(survivor) -> Array[String]:
	var reasons: Array[String] = []
	if survivor == null or survivor.get_script() != SurvivorStateScript:
		return reasons
	for disease_case in survivor.disease_cases:
		if disease_case != null and disease_case.get_script() == DiseaseCaseStateScript and disease_case.is_infectious():
			reasons.append("infectious_disease")
			break
	if int(survivor.status) == SurvivorStateScript.Status.INJURED:
		reasons.append("incapacitating_injury")
	if survivor.health_ratio() < 0.5:
		reasons.append("low_health")
	return reasons


static func departure_base_hope_delta(departure_option_id: String) -> int:
	match departure_option_id:
		DEPARTURE_WITH_PROVISIONS:
			return DEPARTURE_HOPE_WITH_PROVISIONS
		DEPARTURE_WITHOUT_PROVISIONS:
			return DEPARTURE_HOPE_WITHOUT_PROVISIONS
	return 0


static func departure_vulnerability_hope_delta(survivor) -> int:
	return DEPARTURE_VULNERABILITY_HOPE if not departure_vulnerability_reasons(survivor).is_empty() else 0


static func departure_provision_cost(departure_option_id: String, food_per_adult: int) -> Dictionary:
	if departure_option_id == DEPARTURE_WITH_PROVISIONS and food_per_adult > 0:
		return {ResourceIdsScript.FOOD: food_per_adult}
	if departure_option_id == DEPARTURE_WITHOUT_PROVISIONS:
		return {}
	return {}


static func boat_launch_blocker(
	fishing_hut_level: int,
	active_expedition_count: int,
	present_survivor_count: int,
	duration_days: int,
	food_per_adult: int,
	available_food: int
) -> String:
	if fishing_hut_level < MIN_FISHING_HUT_LEVEL:
		return "Ekspedycje łodzią wymagają Chaty Rybackiej II."
	if active_expedition_count >= MAX_ACTIVE_BOAT_EXPEDITIONS:
		return "Jedna ekspedycja łodzią już trwa."
	if not is_supported_duration(duration_days):
		return "Ekspedycja łodzią może trwać wyłącznie 2, 3 albo 4 dni."
	if present_survivor_count <= 1:
		return "W Przystani musi pozostać co najmniej jedna osoba."
	var food_cost := provision_food_cost(food_per_adult, duration_days)
	if food_cost < 1:
		return "Nie można wyliczyć prowiantu ekspedycji."
	if available_food < food_cost:
		return "Brakuje jedzenia na pełny prowiant ekspedycji."
	return ""


static func crew_departure_blocker(
	community_house_level: int,
	tutorial_active: bool,
	plan_editable: bool,
	survivor_present: bool,
	present_survivor_count: int,
	current_day: int,
	last_departure_day: int
) -> String:
	if community_house_level < MIN_COMMUNITY_HOUSE_LEVEL:
		return "Odejście mieszkańca wymaga Domu Wspólnoty I."
	if tutorial_active:
		return "Decyzje o odejściu są dostępne po zakończeniu samouczka."
	if not plan_editable:
		return "Składu załogi nie można zmienić po zablokowaniu planu dnia."
	if not survivor_present:
		return "Może odejść wyłącznie osoba obecna w Przystani."
	if present_survivor_count <= 1:
		return "Ostatnia obecna osoba nie może opuścić Przystani."
	if current_day < 1:
		return "Bieżący dzień kampanii jest niepoprawny."
	if last_departure_day == current_day:
		return "Tego dnia jedna osoba już opuściła Przystań."
	return ""


static func candidate_acceptance_blocker(
	shelter_capacity: int,
	living_roster_count: int,
	candidate_count: int
) -> String:
	if candidate_count < 1 or candidate_count > MAX_RETURN_CANDIDATES:
		return "Można przyjąć od jednej do dwóch osób z jednej oferty powrotu."
	if shelter_capacity < 1 or living_roster_count < 0:
		return "Nie można wyliczyć wolnych miejsc w Przystani."
	if living_roster_count + candidate_count > shelter_capacity:
		return "Brakuje zarezerwowanych miejsc schronienia dla wybranych osób."
	return ""


static func return_resolution_errors(
	return_state,
	shelter_capacity: int,
	living_survivor_ids: Array[String],
	present_survivor_ids: Array[String],
	current_day: int,
	last_departure_day: int
) -> PackedStringArray:
	var errors: Array[String] = []
	if return_state == null or not return_state.has_method("validation_errors"):
		return PackedStringArray(["Brak typowanego stanu powrotu ekspedycji."])
	for state_error in return_state.validation_errors():
		errors.append(str(state_error))
	if int(return_state.get("decision_status")) != 1:
		errors.append("Transakcja poranka wymaga rozstrzygniętej oferty powrotu.")
	if current_day < 1 or int(return_state.get("resolved_day")) != current_day:
		errors.append("Decyzja o powrocie musi zostać zatwierdzona w bieżącym dniu.")
	if shelter_capacity < 1:
		errors.append("Pojemność schronienia musi być dodatnia.")

	var living_set := _validated_id_set(living_survivor_ids, "żyjącego rosteru", errors)
	var present_set := _validated_id_set(present_survivor_ids, "obecnego rosteru", errors)
	for survivor_id in present_set.keys():
		if not living_set.has(survivor_id):
			errors.append("Obecna osoba %s nie należy do żyjącego rosteru." % survivor_id)

	var accepted_count := 0
	var replacement_ids: Dictionary = {}
	for decision in return_state.get("candidate_decisions"):
		if decision == null or not decision.has_method("is_acceptance"):
			continue
		if decision.is_acceptance():
			accepted_count += 1
		if not decision.uses_departure_limit():
			continue
		var replacement_id := str(decision.get("replaced_survivor_id"))
		if replacement_ids.has(replacement_id):
			errors.append("Jedna osoba nie może zostać zastąpiona przez dwie kandydatury.")
		elif not present_set.has(replacement_id):
			errors.append("Zastępowana osoba %s musi być obecna w Przystani." % replacement_id)
		else:
			replacement_ids[replacement_id] = true

	if replacement_ids.size() > MAX_DAILY_DEPARTURES:
		errors.append("Jedna oferta powrotu może spowodować najwyżej jedno trwałe odejście.")
	if not replacement_ids.is_empty() and last_departure_day == current_day:
		errors.append("Dzienny limit odejścia został już wykorzystany.")
	var living_after := living_set.size() + accepted_count - replacement_ids.size()
	var present_after := present_set.size() + accepted_count - replacement_ids.size()
	if living_after > shelter_capacity:
		errors.append("Wybrane przyjęcia przekraczają zarezerwowaną pojemność schronienia.")
	if present_after < 1:
		errors.append("Atomowa decyzja nie może pozostawić Przystani bez obecnej osoby.")
	return PackedStringArray(errors)


static func _validated_id_set(ids: Array[String], label: String, errors: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for survivor_id in ids:
		var normalized_id := survivor_id.strip_edges()
		if normalized_id.is_empty() or result.has(normalized_id):
			errors.append("Lista %s ma pusty albo powielony identyfikator." % label)
		else:
			result[normalized_id] = true
	return result
