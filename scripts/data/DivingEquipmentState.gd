class_name DivingEquipmentState
extends Resource

const STARTING_LIGHT_ID := "diving_lantern_mk1"
const STARTING_OXYGEN_TANK_ID := "oxygen_tank_mk1"
const LIGHT_SLOT := "light"
const OXYGEN_TANK_SLOT := "oxygen_tank"

@export var owned_gear_ids: Array[String] = []
@export var equipped_by_slot: Dictionary = {}

func setup_defaults() -> void:
	owned_gear_ids.clear()
	equipped_by_slot.clear()
	add_gear(STARTING_LIGHT_ID)
	equip(LIGHT_SLOT, STARTING_LIGHT_ID)
	add_gear(STARTING_OXYGEN_TANK_ID)
	equip(OXYGEN_TANK_SLOT, STARTING_OXYGEN_TANK_ID)

func ensure_defaults() -> void:
	if not owns(STARTING_LIGHT_ID):
		add_gear(STARTING_LIGHT_ID)
	var equipped_light := get_equipped(LIGHT_SLOT)
	if equipped_light.is_empty() or not owns(equipped_light):
		equip(LIGHT_SLOT, STARTING_LIGHT_ID)
	if not owns(STARTING_OXYGEN_TANK_ID):
		add_gear(STARTING_OXYGEN_TANK_ID)
	var equipped_oxygen_tank := get_equipped(OXYGEN_TANK_SLOT)
	if equipped_oxygen_tank.is_empty() or not owns(equipped_oxygen_tank):
		equip(OXYGEN_TANK_SLOT, STARTING_OXYGEN_TANK_ID)

func owns(gear_id: String) -> bool:
	return owned_gear_ids.has(gear_id)

func add_gear(gear_id: String) -> bool:
	if gear_id.is_empty() or owns(gear_id):
		return false
	owned_gear_ids.append(gear_id)
	return true

func remove_gear(gear_id: String) -> bool:
	if not owns(gear_id):
		return false
	owned_gear_ids.erase(gear_id)
	for slot_id in equipped_by_slot.keys():
		if str(equipped_by_slot[slot_id]) == gear_id:
			equipped_by_slot.erase(slot_id)
	return true

func equip(slot_id: String, gear_id: String) -> bool:
	if slot_id.is_empty() or gear_id.is_empty() or not owns(gear_id):
		return false
	equipped_by_slot[slot_id] = gear_id
	return true

func get_equipped(slot_id: String) -> String:
	return str(equipped_by_slot.get(slot_id, ""))
