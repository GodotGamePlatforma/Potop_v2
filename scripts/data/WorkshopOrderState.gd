class_name WorkshopOrderState
extends Resource

const NORMAL_ID_PREFIX := "workshop_order"

@export var instance_id: String = ""
@export var recipe_id: String = ""
@export var output_gear_id: String = ""
@export var output_campaign_id: String = ""
@export var output_display_name: String = ""
@export_range(1, 10000) var required_work_points: int = 100
@export var reserved_cost: Dictionary = {}
@export var queued_day: int = 1
@export_range(0, 9999) var work_progress: int = 0


func setup(
	order_instance_id: String,
	order_recipe_id: String,
	gear_id: String,
	display_name: String,
	cost: Dictionary,
	day: int
) -> void:
	instance_id = order_instance_id
	recipe_id = order_recipe_id
	output_gear_id = gear_id
	output_display_name = display_name
	reserved_cost = cost.duplicate(true)
	queued_day = day
	work_progress = 0
	required_work_points = 100
	output_campaign_id = ""


func setup_campaign(
	order_instance_id: String,
	order_recipe_id: String,
	campaign_id: String,
	display_name: String,
	cost: Dictionary,
	day: int,
	work_points: int
) -> void:
	setup(order_instance_id, order_recipe_id, "", display_name, cost, day)
	output_campaign_id = campaign_id
	required_work_points = maxi(work_points, 1)


func validation_errors(
	owner_building_id: String = "",
	known_resource_ids: Array[String] = [],
	known_output_gear_ids: Array[String] = []
) -> PackedStringArray:
	var errors: Array[String] = []
	if instance_id.is_empty():
		errors.append("Zlecenie Warsztatu nie ma instance_id.")
	if recipe_id.is_empty():
		errors.append("Zlecenie Warsztatu nie ma recipe_id.")
	if output_gear_id.is_empty() == output_campaign_id.is_empty():
		errors.append("Zlecenie Warsztatu musi mieć dokładnie jeden wynik: sprzęt albo kampania.")
	elif not output_gear_id.is_empty() and not known_output_gear_ids.is_empty() and not known_output_gear_ids.has(output_gear_id):
		errors.append("Zlecenie Warsztatu wskazuje nieznane wyposażenie %s." % output_gear_id)
	if output_display_name.strip_edges().is_empty():
		errors.append("Zlecenie Warsztatu nie ma zamrożonej nazwy wyniku.")
	if required_work_points < 1:
		errors.append("Zlecenie Warsztatu musi wymagać dodatniej liczby punktów pracy.")
	if work_progress < 0 or work_progress >= required_work_points:
		errors.append("Postęp zlecenia Warsztatu musi być mniejszy od wymaganego nakładu pracy.")

	var seen_resource_ids: Dictionary = {}
	for resource_key in reserved_cost.keys():
		var resource_id := str(resource_key)
		if typeof(resource_key) != TYPE_STRING:
			errors.append("Zlecenie Warsztatu zawiera klucz kosztu, który nie jest Stringiem: %s." % resource_id)
		if resource_id.is_empty():
			errors.append("Zlecenie Warsztatu zawiera pusty identyfikator kosztu.")
		elif not known_resource_ids.is_empty() and not known_resource_ids.has(resource_id):
			errors.append("Zlecenie Warsztatu zawiera nieznany zasób kosztu %s." % resource_id)
		if seen_resource_ids.has(resource_id):
			errors.append("Zlecenie Warsztatu powtarza zasób kosztu %s po normalizacji klucza." % resource_id)
		else:
			seen_resource_ids[resource_id] = true
		if typeof(reserved_cost[resource_key]) != TYPE_INT:
			errors.append("Koszt zasobu %s w zleceniu Warsztatu nie jest liczbą całkowitą." % resource_id)
		elif int(reserved_cost[resource_key]) < 0:
			errors.append("Koszt zasobu %s w zleceniu Warsztatu jest ujemny." % resource_id)

	if not instance_id.is_empty():
		_validate_normal_identity(errors, owner_building_id)
	return PackedStringArray(errors)


func is_valid(
	owner_building_id: String = "",
	known_resource_ids: Array[String] = [],
	known_output_gear_ids: Array[String] = []
) -> bool:
	return validation_errors(owner_building_id, known_resource_ids, known_output_gear_ids).is_empty()


func sequence_number(owner_building_id: String) -> int:
	if owner_building_id.is_empty():
		return -1
	var parts := instance_id.split(":", false)
	if parts.size() != 3 or parts[0] != NORMAL_ID_PREFIX or parts[1] != owner_building_id:
		return -1
	var encoded_sequence := str(parts[2])
	if not encoded_sequence.is_valid_int():
		return -1
	var parsed_sequence := int(encoded_sequence)
	return parsed_sequence if parsed_sequence > 0 else -1


func _validate_normal_identity(errors: Array[String], owner_building_id: String) -> void:
	var parts := instance_id.split(":", false)
	if parts.size() != 3 or parts[0] != NORMAL_ID_PREFIX:
		errors.append("Zwykłe zlecenie Warsztatu ma niepoprawny format instance_id: %s." % instance_id)
		return
	if owner_building_id.is_empty() or parts[1] != owner_building_id:
		errors.append("Zlecenie Warsztatu nie należy do budynku %s." % owner_building_id)
	var encoded_sequence := str(parts[2])
	if not encoded_sequence.is_valid_int() or int(encoded_sequence) <= 0:
		errors.append("Zwykłe zlecenie Warsztatu nie ma dodatniej sekwencji: %s." % instance_id)
	if queued_day < 1:
		errors.append("Zwykłe zlecenie Warsztatu musi mieć queued_day >= 1.")
