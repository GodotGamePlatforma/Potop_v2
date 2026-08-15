class_name BoatExpeditionReturnState
extends Resource

const CandidateDecisionScript := preload("res://scripts/data/BoatExpeditionCandidateDecision.gd")
const OutcomeSnapshotScript := preload("res://scripts/data/BoatExpeditionOutcomeSnapshot.gd")

enum DecisionStatus {
	PENDING,
	RESOLVED,
}

@export var expedition_id: String = ""
@export var leader_survivor_id: String = ""
@export var offered_day: int = 0
@export var decision_status: int = DecisionStatus.PENDING
@export var resolved_day: int = 0
@export var rewards_applied: bool = false
@export var outcome_snapshot: Resource
@export var candidate_decisions: Array[Resource] = []


func has_pending_candidate_decision() -> bool:
	return decision_status == DecisionStatus.PENDING


func accepted_candidate_ids() -> Array[String]:
	var result: Array[String] = []
	for decision in candidate_decisions:
		if decision != null and decision.get_script() == CandidateDecisionScript and decision.is_acceptance():
			result.append(str(decision.candidate_id))
	return result


func rejected_candidate_ids() -> Array[String]:
	var result: Array[String] = []
	for decision in candidate_decisions:
		if decision != null and decision.get_script() == CandidateDecisionScript and not decision.is_acceptance():
			result.append(str(decision.candidate_id))
	return result


func validation_errors() -> PackedStringArray:
	var errors: Array[String] = []
	if expedition_id.strip_edges().is_empty() or leader_survivor_id.strip_edges().is_empty():
		errors.append("Stan powrotu ekspedycji nie ma pełnej tożsamości.")
	if offered_day < 1:
		errors.append("Stan powrotu ekspedycji ma niepoprawny dzień oferty.")
	if decision_status < DecisionStatus.PENDING or decision_status > DecisionStatus.RESOLVED:
		errors.append("Stan powrotu ekspedycji ma nieznany status decyzji.")
	if not rewards_applied:
		errors.append("Trwały stan powrotu może powstać dopiero po jednorazowym zastosowaniu nagród.")
	if outcome_snapshot == null or outcome_snapshot.get_script() != OutcomeSnapshotScript:
		errors.append("Stan powrotu ekspedycji nie ma typowanej migawki wyniku.")
		return PackedStringArray(errors)
	for outcome_error in outcome_snapshot.validation_errors():
		errors.append(str(outcome_error))

	var candidate_ids: Array[String] = outcome_snapshot.candidate_ids()
	var decided_ids: Dictionary = {}
	var replacement_count := 0
	for decision in candidate_decisions:
		if decision == null or decision.get_script() != CandidateDecisionScript:
			errors.append("Stan powrotu zawiera decyzję o kandydaturze niewłaściwego typu.")
			continue
		for decision_error in decision.validation_errors():
			errors.append(str(decision_error))
		var candidate_id := str(decision.candidate_id)
		if candidate_id.strip_edges().is_empty() or decided_ids.has(candidate_id):
			errors.append("Decyzja powrotu ma pusty albo powielony identyfikator kandydatury.")
		elif not candidate_ids.has(candidate_id):
			errors.append("Decyzja powrotu wskazuje kandydaturę spoza zamrożonej oferty: %s." % candidate_id)
		else:
			decided_ids[candidate_id] = true
		if decision.uses_departure_limit():
			replacement_count += 1
	if replacement_count > 1:
		errors.append("Jedna oferta powrotu może zastąpić najwyżej jedną osobę.")

	if decision_status == DecisionStatus.PENDING:
		if candidate_ids.is_empty():
			errors.append("Oczekująca decyzja powrotu nie zawiera kandydatur.")
		if resolved_day != 0 or not candidate_decisions.is_empty():
			errors.append("Oczekująca decyzja powrotu zawiera przedwcześnie zapisany wynik.")
	else:
		if resolved_day != offered_day:
			errors.append("Decyzja o kandydaturach musi zostać rozstrzygnięta w dniu powrotu.")
		if decided_ids.size() != candidate_ids.size():
			errors.append("Rozstrzygnięta oferta powrotu nie dzieli wszystkich kandydatur na przyjęte i odrzucone.")
	return PackedStringArray(errors)


func is_valid() -> bool:
	return validation_errors().is_empty()
