class_name SettlementEventState
extends Resource

const OfferSnapshotScript := preload("res://scripts/data/SettlementEventOfferSnapshot.gd")

enum Status {
	PENDING,
	RESOLVED,
}

@export var instance_id: String = ""
@export var event_id: String = ""
@export var history_key: String = ""
@export var category: String = ""
@export var offered_day: int = 0
@export var status: int = Status.PENDING
@export var offer_snapshot: Resource
@export var selected_choice_id: String = ""
@export var resolved_day: int = 0
@export_multiline var result_text: String = ""
@export var applied_resource_deltas: Dictionary = {}
@export var added_survivor_ids: Array[String] = []
@export var tone: String = ""
@export var severity: int = 0
@export var pressure_cost: float = 0.0
@export var cooldown_group: String = ""
@export var cooldown_days: int = 0
@export var once_per_campaign: bool = false

func setup(definition, day: int) -> void:
	event_id = str(definition.id)
	history_key = str(definition.history_key) if "history_key" in definition else event_id
	category = str(definition.category)
	offered_day = day
	instance_id = "%s:%d" % [event_id, offered_day]
	status = Status.PENDING
	offer_snapshot = null
	selected_choice_id = ""
	resolved_day = 0
	result_text = ""
	applied_resource_deltas.clear()
	added_survivor_ids.clear()
	tone = str(definition.tone)
	severity = int(definition.severity)
	pressure_cost = float(definition.pressure_cost)
	cooldown_group = str(definition.cooldown_group)
	cooldown_days = int(definition.cooldown_days)
	once_per_campaign = bool(definition.once_per_campaign)


func setup_offer(snapshot, day: int) -> void:
	if snapshot == null or snapshot.get_script() != OfferSnapshotScript:
		return
	if not snapshot.validation_errors().is_empty() or day < 1:
		return
	event_id = str(snapshot.event_id)
	history_key = str(snapshot.history_key)
	category = str(snapshot.category)
	offered_day = day
	instance_id = "%s:%d" % [event_id, offered_day]
	status = Status.PENDING
	offer_snapshot = snapshot.duplicate(true)
	selected_choice_id = ""
	resolved_day = 0
	result_text = ""
	applied_resource_deltas.clear()
	added_survivor_ids.clear()
	tone = str(snapshot.tone)
	severity = int(snapshot.severity)
	pressure_cost = float(snapshot.pressure_cost)
	cooldown_group = str(snapshot.cooldown_group)
	cooldown_days = int(snapshot.cooldown_days)
	once_per_campaign = bool(snapshot.once_per_campaign)

func is_pending() -> bool:
	return status == Status.PENDING and not event_id.is_empty() and offered_day > 0

func resolve(choice_id: String, day: int, text: String, deltas: Dictionary, survivor_ids: Array[String]) -> void:
	status = Status.RESOLVED
	selected_choice_id = choice_id
	resolved_day = day
	result_text = text
	applied_resource_deltas = deltas.duplicate(true)
	added_survivor_ids.assign(survivor_ids)
	# Pełna oferta jest potrzebna wyłącznie do rozstrzygnięcia. Historia zachowuje
	# lekkie, zamrożone metadane do kontraktu once/cooldown.
	offer_snapshot = null
