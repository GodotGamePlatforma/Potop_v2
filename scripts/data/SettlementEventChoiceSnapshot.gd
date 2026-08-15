class_name SettlementEventChoiceSnapshot
extends Resource

const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")

@export var id: String = ""
@export var label: String = ""
@export var preview: String = ""
@export_multiline var result_text: String = ""
@export var available: bool = false
@export var unavailable_reason: String = ""
@export var applied_resource_deltas: Dictionary = {}
@export var survivor_states: Array[Resource] = []
@export var impact_tags: Array[String] = []
@export var effect_summary: String = ""


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty():
		errors.append("Brak identyfikatora decyzji.")
	if label.is_empty() or result_text.is_empty():
		errors.append("Decyzja %s nie ma pełnej kopii tekstu." % id)
	if effect_summary.is_empty():
		errors.append("Decyzja %s nie ma zamrożonego podsumowania skutku." % id)
	if available and not unavailable_reason.is_empty():
		errors.append("Dostępna decyzja %s ma powód niedostępności." % id)
	if not available and unavailable_reason.is_empty():
		errors.append("Niedostępna decyzja %s nie ma powodu." % id)
	var seen_survivor_ids: Array[String] = []
	for survivor in survivor_states:
		if survivor == null or survivor.get_script() != SurvivorStateScript:
			errors.append("Decyzja %s zawiera niepoprawną migawkę mieszkańca." % id)
			continue
		var survivor_id := str(survivor.id)
		if survivor_id.is_empty() or seen_survivor_ids.has(survivor_id):
			errors.append("Decyzja %s ma pusty lub powielony identyfikator mieszkańca." % id)
		else:
			seen_survivor_ids.append(survivor_id)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()
