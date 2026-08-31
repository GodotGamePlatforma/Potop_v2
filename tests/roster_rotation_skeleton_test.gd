extends SceneTree

const BoatExpeditionOutcomeSnapshotScript := preload("res://scripts/data/BoatExpeditionOutcomeSnapshot.gd")
const BoatExpeditionCandidateDecisionScript := preload("res://scripts/data/BoatExpeditionCandidateDecision.gd")
const BoatExpeditionReturnStateScript := preload("res://scripts/data/BoatExpeditionReturnState.gd")
const BoatExpeditionStateScript := preload("res://scripts/data/BoatExpeditionState.gd")
const CrewDepartureRecordScript := preload("res://scripts/data/CrewDepartureRecord.gd")
const DiseaseCaseStateScript := preload("res://scripts/data/DiseaseCaseState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const RosterRotationSystemScript := preload("res://scripts/survivors/RosterRotationSystem.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const FloodFever := preload("res://data/diseases/flood_fever.tres")

var _failed := false


func _initialize() -> void:
	_test_duration_and_cost_contract()
	_test_domain_blockers()
	_test_presence_contract()
	_test_frozen_expedition_contract()
	_test_return_partition_contract()
	_test_atomic_return_batch_contract()
	_test_departure_record_contract()
	if _failed:
		quit(1)
		return
	print("Roster rotation skeleton test passed: presence, terminal boundaries, exact provisions, frozen outcomes, atomic return decisions and departure history are typed and validated without activating gameplay.")
	quit(0)


func _test_duration_and_cost_contract() -> void:
	_assert(RosterRotationSystemScript.supported_duration_days() == [2, 3, 4], "Boat expeditions must support exactly 2, 3 and 4 days.")
	for duration_days in [2, 3, 4]:
		_assert(RosterRotationSystemScript.return_day(7, duration_days) == 7 + duration_days, "Return day must equal launch day plus duration.")
		_assert(RosterRotationSystemScript.provision_food_cost(4, duration_days) == 4 * duration_days, "The full travel ration must be reserved at launch.")
	_assert(RosterRotationSystemScript.return_day(7, 5) == -1, "Unsupported duration must not produce a return day.")
	_assert(RosterRotationSystemScript.expedition_instance_id(808, 3) == "boat_expedition:808:3", "Expedition identity must be stable and campaign-scoped.")
	_assert(RosterRotationSystemScript.candidate_instance_id("boat_expedition:808:3", 2) == "expedition_recruit:boat_expedition:808:3:2", "Candidate identity must be stable and expedition-scoped.")


func _test_domain_blockers() -> void:
	_assert(RosterRotationSystemScript.boat_launch_blocker(1, 0, 3, 2, 4, 20).contains("Chaty Rybackiej II"), "Fishing Hut I must not launch a boat expedition.")
	_assert(RosterRotationSystemScript.boat_launch_blocker(2, 1, 3, 2, 4, 20).contains("już trwa"), "Only one boat expedition may be active.")
	_assert(RosterRotationSystemScript.boat_launch_blocker(2, 0, 1, 2, 4, 20).contains("pozostać"), "The last present resident must stay in the settlement.")
	_assert(RosterRotationSystemScript.boat_launch_blocker(2, 0, 3, 4, 4, 15).contains("Brakuje jedzenia"), "Launch must reject an incomplete travel ration.")
	_assert(RosterRotationSystemScript.boat_launch_blocker(2, 0, 3, 4, 4, 16).is_empty(), "A fully provisioned supported expedition must pass the structural blocker.")

	_assert(RosterRotationSystemScript.crew_departure_blocker(1, true, true, true, 3, 6, 0).contains("samouczka"), "Tutorial must protect the starting roster.")
	_assert(RosterRotationSystemScript.crew_departure_blocker(1, false, true, true, 3, 6, 6).contains("już opuściła"), "The shared daily departure quota must reject a second departure.")
	_assert(RosterRotationSystemScript.crew_departure_blocker(1, false, true, true, 3, 6, 5).is_empty(), "A first post-tutorial departure on an editable day must pass the structural blocker.")
	_assert(RosterRotationSystemScript.candidate_acceptance_blocker(4, 3, 1).is_empty(), "One free reserved shelter place must accept one candidate.")
	_assert(RosterRotationSystemScript.candidate_acceptance_blocker(4, 4, 1).contains("Brakuje"), "An away leader must remain part of reserved roster capacity.")
	_assert(RosterRotationSystemScript.boat_terminal_boundary_blocker(7, 2, true, 3, false, false).is_empty(), "An expedition returning before the known Front may launch.")
	_assert(RosterRotationSystemScript.boat_terminal_boundary_blocker(7, 3, true, 3, false, false).contains("Czarnego Frontu"), "A return on or after the terminal Front boundary must be rejected.")
	_assert(RosterRotationSystemScript.boat_terminal_boundary_blocker(7, 2, false, 0, true, false).contains("nadejściu"), "A terminal campaign may not launch another boat expedition.")

	var sick_leader = _candidate()
	var active_case := DiseaseCaseStateScript.new()
	_assert(active_case.setup_from_definition(FloodFever, DiseaseCaseStateScript.Phase.SYMPTOMATIC, 5, 40, "test", "boat_leader"), "The active disease fixture must validate.")
	sick_leader.disease_cases.append(active_case)
	_assert(not RosterRotationSystemScript.boat_leader_blocker(sick_leader).is_empty(), "A leader with an active disease case must not launch.")
	var immune_leader = _candidate()
	var immune_case := DiseaseCaseStateScript.new()
	_assert(immune_case.setup_from_definition(FloodFever, DiseaseCaseStateScript.Phase.IMMUNE, 5, 0, "test", "boat_leader"), "The immune disease fixture must validate.")
	immune_leader.disease_cases.append(immune_case)
	_assert(RosterRotationSystemScript.boat_leader_blocker(immune_leader).is_empty(), "Completed immunity must not block a healthy boat leader.")


func _test_presence_contract() -> void:
	var mira = _candidate()
	mira.id = "mira"
	var anka = _candidate()
	anka.id = "anka"
	var expedition := BoatExpeditionStateScript.new()
	expedition.leader_survivor_id = "mira"
	var survivors: Array = [mira, anka]
	_assert(RosterRotationSystemScript.living_survivors(survivors).size() == 2, "An away leader must remain in the living roster.")
	_assert(RosterRotationSystemScript.present_survivors(survivors, expedition).size() == 1, "The active expedition must be the canonical owner of leader absence.")
	_assert(RosterRotationSystemScript.reserved_roster_count(survivors) == 2, "An away leader must keep the reserved capacity place.")
	_assert(RosterRotationSystemScript.work_blocker(mira, expedition).contains("ekspedycję łodzią"), "Every base-work consumer needs the same away blocker.")
	_assert(RosterRotationSystemScript.dive_blocker(mira, expedition).contains("ekspedycję łodzią"), "An away leader may not also dive.")
	_assert(RosterRotationSystemScript.settlement_presence_mode(2, 0, 9, 8) == RosterRotationSystemScript.PRESENCE_WAITING_FOR_RETURN, "A temporarily unattended base with a scheduled return must wait instead of ending the campaign.")
	_assert(RosterRotationSystemScript.settlement_presence_mode(1, 0, 7, 8) == RosterRotationSystemScript.PRESENCE_LOST, "A base with no present person and no possible return is lost.")


func _test_frozen_expedition_contract() -> void:
	var outcome = _outcome()
	var expedition := BoatExpeditionStateScript.new()
	expedition.instance_id = RosterRotationSystemScript.expedition_instance_id(808, 1)
	expedition.route_id = "coastal_scouting"
	expedition.leader_survivor_id = "mira"
	expedition.launch_day = 5
	expedition.duration_days = 3
	expedition.return_day = 8
	expedition.fishing_hut_level_at_launch = 3
	expedition.food_per_adult_at_launch = 4
	expedition.leader_health_at_launch = 100
	expedition.reserved_provisions = RosterRotationSystemScript.provision_cost(4, 3)
	expedition.outcome_seed = 55081
	expedition.balance_version = 1
	expedition.balance_signature = "a".repeat(64)
	expedition.outcome_snapshot = outcome.detached_copy()
	_assert(expedition.is_valid(), "A complete active boat-expedition commitment must validate: %s" % "; ".join(expedition.validation_errors()))

	var invalid := expedition.duplicate(true)
	invalid.return_day = 7
	invalid.reserved_provisions[ResourceIdsScript.FOOD] = 13
	var invalid_errors = invalid.validation_errors()
	_assert(invalid_errors.size() >= 2, "A mismatched return day and inexact provisions must both be rejected.")
	_assert(expedition.return_day == 8 and int(expedition.reserved_provisions[ResourceIdsScript.FOOD]) == 12, "Rejected validation must not mutate the valid source commitment.")

	var fatal := expedition.duplicate(true)
	fatal.leader_health_at_launch = 20
	fatal.outcome_snapshot.leader_health_delta = -20
	_assert(not fatal.is_valid(), "The frozen outcome may reduce health but must always leave the returning leader alive.")
	var foreign_candidate := expedition.duplicate(true)
	foreign_candidate.outcome_snapshot.candidate_snapshots[0].id = "expedition_recruit:boat_expedition:999:1:1"
	_assert(not foreign_candidate.is_valid(), "Every candidate identity must be scoped to the expedition that generated it.")
	var invalid_profession := expedition.duplicate(true)
	invalid_profession.outcome_snapshot.candidate_snapshots[0].profession = "radiowiec"
	_assert(not invalid_profession.is_valid(), "A candidate profession without a real gameplay definition must be rejected.")
	var premature_second_candidate := expedition.duplicate(true)
	var second_candidate = _candidate()
	second_candidate.id = RosterRotationSystemScript.candidate_instance_id(expedition.instance_id, 2)
	premature_second_candidate.outcome_snapshot.candidate_snapshots.append(second_candidate)
	_assert(not premature_second_candidate.is_valid(), "A second candidate must require both a four-day expedition and Fishing Hut IV.")
	var valid_two_candidate_expedition := premature_second_candidate.duplicate(true)
	valid_two_candidate_expedition.duration_days = 4
	valid_two_candidate_expedition.return_day = 9
	valid_two_candidate_expedition.fishing_hut_level_at_launch = 4
	valid_two_candidate_expedition.reserved_provisions = RosterRotationSystemScript.provision_cost(4, 4)
	_assert(valid_two_candidate_expedition.is_valid(), "A four-day expedition from Fishing Hut IV may freeze exactly two candidates.")


func _test_return_partition_contract() -> void:
	var pending := BoatExpeditionReturnStateScript.new()
	pending.expedition_id = "boat_expedition:808:1"
	pending.leader_survivor_id = "mira"
	pending.offered_day = 8
	pending.rewards_applied = true
	pending.outcome_snapshot = _outcome()
	_assert(pending.is_valid() and pending.has_pending_candidate_decision(), "A frozen return with candidates and already applied rewards must form a valid mandatory decision.")

	var resolved = pending.duplicate(true)
	resolved.decision_status = BoatExpeditionReturnStateScript.DecisionStatus.RESOLVED
	resolved.resolved_day = 8
	resolved.candidate_decisions.append(_candidate_decision(
		"expedition_recruit:boat_expedition:808:1:1",
		BoatExpeditionCandidateDecisionScript.Choice.ACCEPT_FREE_PLACE
	))
	_assert(resolved.is_valid(), "A resolved one-candidate offer must partition the full frozen candidate set.")
	_assert(resolved.accepted_candidate_ids() == ["expedition_recruit:boat_expedition:808:1:1"], "Accepted candidate IDs must be derived from the typed decisions.")

	var incomplete = pending.duplicate(true)
	incomplete.decision_status = BoatExpeditionReturnStateScript.DecisionStatus.RESOLVED
	incomplete.resolved_day = 8
	_assert(not incomplete.is_valid(), "A resolved return may not silently drop a candidate.")


func _test_atomic_return_batch_contract() -> void:
	var resolved := BoatExpeditionReturnStateScript.new()
	resolved.expedition_id = "boat_expedition:808:1"
	resolved.leader_survivor_id = "mira"
	resolved.offered_day = 8
	resolved.decision_status = BoatExpeditionReturnStateScript.DecisionStatus.RESOLVED
	resolved.resolved_day = 8
	resolved.rewards_applied = true
	resolved.outcome_snapshot = _outcome()
	resolved.candidate_decisions.append(_candidate_decision(
		"expedition_recruit:boat_expedition:808:1:1",
		BoatExpeditionCandidateDecisionScript.Choice.ACCEPT_REPLACING,
		"anka",
		RosterRotationSystemScript.DEPARTURE_WITH_PROVISIONS
	))
	var living_ids: Array[String] = ["mira", "anka", "igor", "leon"]
	var present_ids: Array[String] = ["mira", "anka", "igor", "leon"]
	_assert(
		RosterRotationSystemScript.return_resolution_errors(resolved, 4, living_ids, present_ids, 8, 7).is_empty(),
		"A full shelter must accept exactly one candidate through one explicit atomic replacement."
	)
	_assert(
		not RosterRotationSystemScript.return_resolution_errors(resolved, 4, living_ids, present_ids, 8, 8).is_empty(),
		"A replacement must share the same once-per-day departure quota."
	)
	var last_present_ids: Array[String] = ["anka"]
	_assert(
		RosterRotationSystemScript.return_resolution_errors(resolved, 1, last_present_ids, last_present_ids, 8, 7).is_empty(),
		"The last present resident may be replaced only when the same atomic decision immediately keeps one accepted resident present."
	)
	var invalid := resolved.duplicate(true)
	invalid.candidate_decisions[0].replaced_survivor_id = "away_leader"
	var before_present := present_ids.duplicate()
	_assert(not RosterRotationSystemScript.return_resolution_errors(invalid, 4, living_ids, present_ids, 8, 7).is_empty(), "A replacement target outside the present roster must be rejected.")
	_assert(present_ids == before_present and resolved.candidate_decisions[0].replaced_survivor_id == "anka", "Rejected batch validation must not mutate its inputs or the valid source decision.")


func _test_departure_record_contract() -> void:
	var survivor = _candidate()
	survivor.competency_levels = {"swimming": 2}
	var record = CrewDepartureRecordScript.capture(
		survivor,
		9,
		"candidate_replacement",
		RosterRotationSystemScript.DEPARTURE_WITH_PROVISIONS,
		4
	)
	_assert(record != null and record.is_valid(), "A player-selected departure must preserve a valid immutable history record.")
	_assert(record.survivor_id == survivor.id and record.level == survivor.level and record.competency_levels == {"swimming": 2} and record.provision_cost == {ResourceIdsScript.FOOD: 4} and record.hope_delta == -6, "Departure history must retain identity, development, competencies, exact Hope and the applied provision cost.")
	var invalid = record.duplicate(true)
	invalid.reason_id = "automatic_roster_order"
	invalid.hope_delta = -5
	_assert(invalid.validation_errors().size() >= 2, "Automatic list-order departure and an inconsistent Hope delta must be rejected by the skeleton contract.")

	var vulnerable = _candidate()
	vulnerable.status = SurvivorStateScript.Status.INJURED
	vulnerable.injury_states.assign(["critical_rescue"])
	vulnerable.health = 40
	var vulnerable_record = CrewDepartureRecordScript.capture(
		vulnerable,
		9,
		"player_dismissal",
		RosterRotationSystemScript.DEPARTURE_WITHOUT_PROVISIONS,
		4
	)
	_assert(vulnerable_record.is_valid() and vulnerable_record.hope_delta == -14 and vulnerable_record.provision_cost.is_empty(), "Vulnerability must add one -4 Hope component without stacking reasons, and departure without provisions must spend no resource.")


func _outcome():
	var outcome := BoatExpeditionOutcomeSnapshotScript.new()
	outcome.result_tier = "standard"
	outcome.summary_text = "Ekspedycja wróciła z zapasami i spotkaną osobą."
	outcome.reward_resource_deltas = {ResourceIdsScript.FOOD: 9, ResourceIdsScript.SCRAP: 3}
	outcome.leader_fatigue_delta = 18
	outcome.leader_hunger_delta = 8
	outcome.candidate_snapshots.append(_candidate())
	return outcome


func _candidate():
	var survivor := SurvivorStateScript.new()
	survivor.id = "expedition_recruit:boat_expedition:808:1:1"
	survivor.display_name = "Lena Wrona"
	survivor.profession = "medyk"
	survivor.portrait_id = survivor.id
	survivor.level = 3
	survivor.health = survivor.get_max_health()
	survivor.morale = 48
	return survivor


func _candidate_decision(
	candidate_id: String,
	choice: int,
	replaced_survivor_id: String = "",
	departure_option_id: String = ""
):
	var decision := BoatExpeditionCandidateDecisionScript.new()
	decision.candidate_id = candidate_id
	decision.choice = choice
	decision.replaced_survivor_id = replaced_survivor_id
	decision.departure_option_id = departure_option_id
	return decision


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Roster rotation skeleton test failed: " + message)
