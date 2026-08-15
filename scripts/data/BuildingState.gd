class_name BuildingState
extends Resource

const WorkshopOrderStateScript := preload("res://scripts/data/WorkshopOrderState.gd")

@export var id: String = ""
@export var definition_id: String = ""
@export var slot_id: String = ""
@export var level: int = 1
@export var condition: int = 100
@export var assigned_survivor_ids: Array[String] = []
@export var construction_progress: int = 100
@export var is_built: bool = true
@export var pending_level: int = 0
@export_enum("careful", "normal", "intense") var work_pace: String = "normal"
@export_range(0, 3) var work_tension: int = 0
@export var queued_production_orders: Array[WorkshopOrderState] = []
@export var next_production_order_sequence: int = 1

func is_active() -> bool:
	return is_built and pending_level == 0 and condition > 0

func is_under_construction() -> bool:
	return not is_built or pending_level > level


func production_order_validation_errors(
	known_resource_ids: Array[String] = [],
	known_output_gear_ids: Array[String] = []
) -> PackedStringArray:
	var errors: Array[String] = []
	if next_production_order_sequence < 1:
		errors.append("Budynek %s ma licznik zleceń Warsztatu mniejszy niż 1." % id)
	if definition_id != "workshop":
		if not queued_production_orders.is_empty():
			errors.append("Budynek %s nie jest Warsztatem, ale ma zlecenia produkcyjne." % id)
		if next_production_order_sequence != 1:
			errors.append("Budynek %s nie jest Warsztatem, ale ma licznik zleceń różny od 1." % id)
		return PackedStringArray(errors)

	var seen_instance_ids: Dictionary = {}
	var highest_normal_sequence := 0
	for order in queued_production_orders:
		if order == null or order.get_script() != WorkshopOrderStateScript:
			errors.append("Warsztat %s zawiera zlecenie niepoprawnego typu." % id)
			continue
		for order_error in order.validation_errors(id, known_resource_ids, known_output_gear_ids):
			errors.append("Warsztat %s: %s" % [id, order_error])
		if seen_instance_ids.has(order.instance_id):
			errors.append("Warsztat %s powtarza instance_id zlecenia %s." % [id, order.instance_id])
		else:
			seen_instance_ids[order.instance_id] = true
		var sequence := order.sequence_number(id)
		if sequence > 0:
			highest_normal_sequence = maxi(highest_normal_sequence, sequence)
	if next_production_order_sequence <= highest_normal_sequence:
		errors.append(
			"Warsztat %s ma licznik %d niewiększy od aktywnej sekwencji %d."
			% [id, next_production_order_sequence, highest_normal_sequence]
		)
	return PackedStringArray(errors)
