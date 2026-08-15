class_name SettlementEventOfferSnapshot
extends Resource

const VALID_TONES: Array[String] = ["relief", "opportunity", "tradeoff", "hardship"]
const ChoiceSnapshotScript := preload("res://scripts/data/SettlementEventChoiceSnapshot.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")

@export var event_id: String = ""
@export var history_key: String = ""
@export var category: String = ""
@export var title: String = ""
@export_multiline var body: String = ""
@export var choices: Array[Resource] = []
@export var fallback_choice_id: String = ""
@export var expected_resource_baseline: Dictionary = {}
@export var tone: String = ""
@export var severity: int = 0
@export var pressure_cost: float = 0.0
@export var cooldown_group: String = ""
@export var cooldown_days: int = 0
@export var once_per_campaign: bool = false


func find_choice(choice_id: String):
	for choice in choices:
		if choice != null and choice.get_script() == ChoiceSnapshotScript and str(choice.id) == choice_id:
			return choice
	return null


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if event_id.is_empty() or history_key.is_empty() or category.is_empty():
		errors.append("Migawka wydarzenia nie ma pełnej tożsamości.")
	if title.is_empty() or body.is_empty():
		errors.append("Migawka wydarzenia %s nie ma pełnej kopii karty." % event_id)
	if not VALID_TONES.has(tone) or cooldown_group.is_empty() or cooldown_days < 0 or severity < 0 or severity > 3 or not is_finite(pressure_cost) or pressure_cost < 0.0 or pressure_cost > 3.0:
		errors.append("Migawka wydarzenia %s ma niepoprawne metadane historii." % event_id)
	if choices.size() < 2:
		errors.append("Migawka wydarzenia %s ma za mało decyzji." % event_id)
	var seen_choice_ids: Array[String] = []
	var touched_resources: Dictionary = {}
	for choice in choices:
		if choice == null or choice.get_script() != ChoiceSnapshotScript:
			errors.append("Migawka wydarzenia %s zawiera decyzję niewłaściwego typu." % event_id)
			continue
		for choice_error in choice.validation_errors():
			errors.append(str(choice_error))
		var choice_id := str(choice.id)
		if seen_choice_ids.has(choice_id):
			errors.append("Migawka wydarzenia %s powtarza decyzję %s." % [event_id, choice_id])
		else:
			seen_choice_ids.append(choice_id)
		for raw_resource_id in choice.applied_resource_deltas.keys():
			var resource_id := str(raw_resource_id)
			if not ResourceIdsScript.all().has(resource_id) or typeof(choice.applied_resource_deltas[raw_resource_id]) != TYPE_INT:
				errors.append("Decyzja %s ma niepoprawną deltę zasobu %s." % [choice_id, resource_id])
			touched_resources[resource_id] = true
	var fallback = find_choice(fallback_choice_id)
	if fallback == null:
		errors.append("Migawka wydarzenia %s nie ma wskazanej decyzji awaryjnej." % event_id)
	elif not bool(fallback.available):
		errors.append("Decyzja awaryjna wydarzenia %s nie jest dostępna." % event_id)
	else:
		if not fallback.survivor_states.is_empty():
			errors.append("Decyzja awaryjna wydarzenia %s dodaje mieszkańca." % event_id)
		for raw_resource_id in fallback.applied_resource_deltas.keys():
			var resource_id := str(raw_resource_id)
			if resource_id not in [ResourceIdsScript.HOPE, ResourceIdsScript.PLATFORM_INTEGRITY] and int(fallback.applied_resource_deltas[raw_resource_id]) < 0:
				errors.append("Decyzja awaryjna wydarzenia %s ma zwykły koszt zasobu." % event_id)
	if expected_resource_baseline.size() != touched_resources.size():
		errors.append("Baza zasobów wydarzenia %s nie odpowiada unii skutków." % event_id)
	for raw_resource_id in expected_resource_baseline.keys():
		var resource_id := str(raw_resource_id)
		if not touched_resources.has(resource_id) or not ResourceIdsScript.all().has(resource_id) or typeof(expected_resource_baseline[raw_resource_id]) != TYPE_INT or int(expected_resource_baseline[raw_resource_id]) < 0:
			errors.append("Migawka wydarzenia %s ma niepoprawną bazę zasobu." % event_id)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()
