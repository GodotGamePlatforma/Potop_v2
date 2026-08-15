class_name DiveTutorialOutcome
extends RefCounted

const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")

var baseline_step: int = -1
var final_step: int = -1
var event_ids: Array[String] = []


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if baseline_step not in [
		TutorialStateScript.Step.START_FIRST_DIVE,
		TutorialStateScript.Step.START_FINAL_DIVE,
	]:
		errors.append("Wynik tutoriala ma niepoprawny krok początkowy.")
	if final_step not in [
		TutorialStateScript.Step.DIVE_RETURN_TO_LINE,
		TutorialStateScript.Step.FINAL_RETURN_TO_LINE,
	]:
		errors.append("Wynik tutoriala nie kończy się przy bezpiecznym powrocie do liny.")
	if event_ids.is_empty():
		errors.append("Wynik tutoriala nie zawiera zaakceptowanych zdarzeń sesji.")
	for event_id in event_ids:
		if event_id.strip_edges().is_empty():
			errors.append("Wynik tutoriala zawiera puste zdarzenie.")
			break
	return errors


func detached_copy() -> DiveTutorialOutcome:
	var copy := DiveTutorialOutcome.new()
	copy.baseline_step = baseline_step
	copy.final_step = final_step
	copy.event_ids.assign(event_ids)
	return copy
