class_name BoatExpeditionCandidateDecision
extends Resource

enum Choice {
	REJECT,
	ACCEPT_FREE_PLACE,
	ACCEPT_REPLACING,
}

const DEPARTURE_WITH_PROVISIONS := "with_provisions"
const DEPARTURE_WITHOUT_PROVISIONS := "without_provisions"
const VALID_DEPARTURE_OPTIONS: Array[String] = [
	DEPARTURE_WITH_PROVISIONS,
	DEPARTURE_WITHOUT_PROVISIONS,
]

@export var candidate_id: String = ""
@export var choice: int = Choice.REJECT
@export var replaced_survivor_id: String = ""
@export var departure_option_id: String = ""


func is_acceptance() -> bool:
	return choice in [Choice.ACCEPT_FREE_PLACE, Choice.ACCEPT_REPLACING]


func uses_departure_limit() -> bool:
	return choice == Choice.ACCEPT_REPLACING


func validation_errors() -> PackedStringArray:
	var errors: Array[String] = []
	if candidate_id.strip_edges().is_empty():
		errors.append("Decyzja o kandydaturze nie ma candidate_id.")
	if choice < Choice.REJECT or choice > Choice.ACCEPT_REPLACING:
		errors.append("Decyzja o kandydaturze ma nieznany wybór.")
		return PackedStringArray(errors)

	match choice:
		Choice.REJECT, Choice.ACCEPT_FREE_PLACE:
			if not replaced_survivor_id.is_empty() or not departure_option_id.is_empty():
				errors.append("Odrzucenie albo przyjęcie na wolne miejsce nie może wskazywać zastępowanej osoby ani wariantu odejścia.")
		Choice.ACCEPT_REPLACING:
			if replaced_survivor_id.strip_edges().is_empty() or replaced_survivor_id == candidate_id:
				errors.append("Zastąpienie wymaga innej, jawnie wskazanej osoby z Przystani.")
			if not VALID_DEPARTURE_OPTIONS.has(departure_option_id):
				errors.append("Zastąpienie wymaga poprawnego wariantu odejścia.")
	return PackedStringArray(errors)


func is_valid() -> bool:
	return validation_errors().is_empty()
