class_name SectorPersistenceSystem
extends RefCounted


func record_fixed_device_completion_for_attempt(
	session,
	dive_map,
	device_id: String,
	shortcut_id: String,
) -> bool:
	if session == null:
		return false
	var resolved_device_id := device_id.strip_edges()
	var resolved_shortcut_id := shortcut_id.strip_edges()
	if resolved_device_id.is_empty():
		return false
	if resolved_shortcut_id.is_empty():
		if not session.activated_fixed_devices.has(resolved_device_id):
			session.activated_fixed_devices.append(resolved_device_id)
		return true
	if (
		dive_map == null
		or not dive_map.has_method("open_shortcut_for_attempt")
		or not bool(dive_map.call("open_shortcut_for_attempt", resolved_shortcut_id))
	):
		return false
	return session.record_safe_return_only_world_link(
		resolved_device_id,
		resolved_shortcut_id,
	)


func populate_result(session, result) -> void:
	if session == null or result == null:
		return
	result.opened_containers.assign(session.opened_containers)
	result.collected_world_item_ids.assign(session.collected_world_item_ids)
	result.remaining_container_contents = session.remaining_container_contents.duplicate(true)
	result.placed_buoys.assign(session.placed_buoys)
	result.opened_shortcuts.assign(session.opened_shortcuts)
	result.activated_fixed_devices.assign(session.activated_fixed_devices)
	if not _is_safe_return(result):
		_erase_ids(result.opened_shortcuts, session.safe_return_only_opened_shortcuts)
		_erase_ids(result.activated_fixed_devices, session.safe_return_only_activated_fixed_devices)
	result.marked_heavy_objects.assign(session.marked_heavy_objects)
	result.recovered_backpacks = session.recovered_backpacks.duplicate(true)
	result.recovered_gear_ids.assign(session.recovered_gear_ids)
	result.dropped_loot_updates = session.dropped_loot_updates.duplicate(true)

func apply_result(world, result) -> Dictionary:
	var summary := {
		"discovered": 0,
		"containers": 0,
		"buoys": 0,
		"shortcuts": 0,
		"fixed_devices": 0,
		"heavy_objects": 0,
		"backpacks": 0,
		"dropped_loot": 0,
		"rescues": 0,
	}
	if world == null or result == null:
		return summary

	for landmark_id in result.discovered_sectors:
		if _append_unique(world.discovered_sectors, str(landmark_id)):
			summary.discovered += 1

	for container_id in result.opened_containers:
		var id := str(container_id)
		if _append_unique(world.opened_containers, id):
			summary.containers += 1
		world.remaining_container_contents.erase(id)
	for container_id in result.remaining_container_contents.keys():
		var id := str(container_id)
		world.remaining_container_contents[id] = result.remaining_container_contents[container_id].duplicate(true)
		world.opened_containers.erase(id)
	for item_id in result.collected_world_item_ids:
		_append_unique(world.collected_items, str(item_id))

	for buoy_id in result.placed_buoys:
		if _append_unique(world.placed_buoys, str(buoy_id)):
			summary.buoys += 1
	for shortcut_id in result.opened_shortcuts:
		if _append_unique(world.opened_shortcuts, str(shortcut_id)):
			summary.shortcuts += 1
	for device_id in result.activated_fixed_devices:
		if _append_unique(world.activated_fixed_devices, str(device_id)):
			summary.fixed_devices += 1
	for object_id in result.marked_heavy_objects:
		if world.recovered_heavy_objects.has(str(object_id)):
			continue
		if _append_unique(world.marked_heavy_objects, str(object_id)):
			summary.heavy_objects += 1

	for backpack_id in result.recovered_backpacks.keys():
		var id := str(backpack_id)
		if not world.lost_backpacks.has(id):
			continue
		var record: Dictionary = world.lost_backpacks[id].duplicate(true)
		var update: Dictionary = result.recovered_backpacks[backpack_id]
		record["items"] = update.get("items", {}).duplicate(true)
		record["gear_ids"] = update.get("gear_ids", []).duplicate()
		record["recovered"] = bool(update.get("recovered", false))
		world.lost_backpacks[id] = record
		summary.backpacks += 1

	var next_dropped_loot: Dictionary = world.dropped_loot_piles.duplicate(true)
	for pile_id in result.dropped_loot_updates.keys():
		var id := str(pile_id)
		if id.is_empty():
			continue
		var previous = next_dropped_loot.get(id)
		var update_value = result.dropped_loot_updates[pile_id]
		if not (update_value is Dictionary):
			continue
		var update: Dictionary = update_value.duplicate(true)
		var remaining_items := _normalized_items(update.get("items", {}))
		if update.is_empty() or bool(update.get("recovered", false)) or remaining_items.is_empty():
			if next_dropped_loot.has(id):
				next_dropped_loot.erase(id)
				summary.dropped_loot += 1
			continue
		update["persistence_id"] = id
		update["items"] = remaining_items
		update["created_day"] = maxi(int(update.get("created_day", 0)), 0)
		update["recovered"] = false
		if previous != update:
			next_dropped_loot[id] = update
			summary.dropped_loot += 1
	world.dropped_loot_piles = next_dropped_loot

	for encounter_id in result.rescue_outcomes.keys():
		var id := str(encounter_id)
		var outcome: Dictionary = result.rescue_outcomes[encounter_id].duplicate(true)
		if outcome.is_empty() or str(outcome.get("status", "")).is_empty():
			continue
		if world.rescued_or_dead_survivors.get(id, {}) != outcome:
			world.rescued_or_dead_survivors[id] = outcome
			summary.rescues += 1

	return summary


func _is_safe_return(result) -> bool:
	return bool(result.returned_alive) and not bool(result.diver_dead) and not bool(result.emergency_extraction)


func _erase_ids(values: Array[String], excluded_ids: Array[String]) -> void:
	for excluded_id in excluded_ids:
		values.erase(excluded_id)


func _append_unique(values: Array[String], value: String) -> bool:
	if value.is_empty() or values.has(value):
		return false
	values.append(value)
	return true

func _normalized_items(value) -> Dictionary:
	var result: Dictionary = {}
	if not (value is Dictionary):
		return result
	for resource_id in value.keys():
		var id := str(resource_id)
		var amount := maxi(int(value[resource_id]), 0)
		if not id.is_empty() and amount > 0:
			result[id] = amount
	return result
