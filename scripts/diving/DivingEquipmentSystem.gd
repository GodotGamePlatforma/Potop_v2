class_name DivingEquipmentSystem
extends RefCounted

const LIGHT_SLOT := "light"

func equip(state, gear_id: String) -> bool:
	if state == null or state.diving_equipment == null:
		return false
	if state.has_method("can_edit_day_plan") and not state.can_edit_day_plan():
		return false
	var definition = _gear_definition(gear_id)
	if definition == null or str(definition.equipment_slot).is_empty():
		return false
	return state.diving_equipment.equip(str(definition.equipment_slot), gear_id)

func equipped_definition(state, slot_id: String):
	if state == null or state.diving_equipment == null:
		return null
	return _gear_definition(state.diving_equipment.get_equipped(slot_id))

func build_loadout(state) -> Dictionary:
	if state == null or state.diving_equipment == null:
		return {}
	state.diving_equipment.ensure_defaults()
	var result: Dictionary = {}
	for slot_id in state.diving_equipment.equipped_by_slot.keys():
		var gear_id := str(state.diving_equipment.equipped_by_slot[slot_id])
		var definition = _gear_definition(gear_id)
		if definition != null and state.diving_equipment.owns(gear_id) and str(definition.equipment_slot) == str(slot_id):
			result[str(slot_id)] = gear_id
	return result

func apply_lost_gear(state, lost_gear: Array[String]) -> Array[String]:
	var removed: Array[String] = []
	if state == null or state.diving_equipment == null:
		return removed
	for gear_id in lost_gear:
		var definition = _gear_definition(gear_id)
		if definition == null or bool(definition.is_emergency_default):
			continue
		if state.diving_equipment.remove_gear(gear_id):
			removed.append(gear_id)
	state.diving_equipment.ensure_defaults()
	return removed

func restore_recovered_gear(state, recovered_gear: Array[String]) -> Array[String]:
	var restored: Array[String] = []
	if state == null or state.diving_equipment == null:
		return restored
	for gear_id in recovered_gear:
		if _gear_definition(gear_id) == null:
			continue
		if state.diving_equipment.add_gear(gear_id):
			restored.append(gear_id)
	state.diving_equipment.ensure_defaults()
	return restored

func _gear_definition(gear_id: String):
	if gear_id.is_empty():
		return null
	var path := "res://data/diving_gear/%s.tres" % gear_id
	return ResourceLoader.load(path) if ResourceLoader.exists(path) else null
