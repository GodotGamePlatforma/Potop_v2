extends Node

const BaseScene := preload("res://scenes/base/BaseScene.tscn")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")

const BUILDING_SLOTS := {
	"fishing_hut": "top_left",
	"kitchen": "top_center",
	"community_house": "top_right",
	"workshop": "bottom_left",
	"infirmary": "center",
	"diving_station": "bottom_right",
}


func _ready() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(903, DifficultyProfileScript.new())
	state.tutorial.complete()
	_set_representative_buildings(state)

	var base = BaseScene.instantiate()
	add_child(base)
	await get_tree().process_frame
	if base.has_method("set_animation_time_for_tests"):
		base.set_animation_time_for_tests(1.7)
	state.find_survivor("igor").fatigue = 95
	base.bind(null, state)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	if not _assert_badge_matrix(base, state):
		get_tree().quit(1)
		return
	var wide_saved: bool = await _save_snapshot_at_size("base_building_occupancy_hover_16x9.png", Vector2i(1280, 720))
	if not wide_saved:
		return
	var compact_saved: bool = await _save_snapshot_at_size("base_building_occupancy_hover_5x4.png", Vector2i(1280, 1024))
	if not compact_saved:
		return

	print("Building occupancy hover snapshots saved at 16:9 and 5:4; rest, focus, partial, empty and warning states verified.")
	get_tree().quit(0)


func _set_representative_buildings(state) -> void:
	state.buildings.clear()
	for slot_id in state.platform.slot_states.keys():
		var empty_slot: Dictionary = state.platform.slot_states[slot_id]
		empty_slot["building_id"] = ""
		state.platform.slot_states[slot_id] = empty_slot
	for definition_id in BUILDING_SLOTS.keys():
		var building = BuildingStateScript.new()
		building.id = "occupancy_snapshot_%s" % definition_id
		building.definition_id = definition_id
		building.slot_id = BUILDING_SLOTS[definition_id]
		building.level = 1 if definition_id == "kitchen" else 4
		building.is_built = true
		if definition_id == "fishing_hut":
			building.assigned_survivor_ids.assign(["mira", "igor"])
		elif definition_id == "kitchen":
			building.assigned_survivor_ids.assign(["anka"])
		state.buildings.append(building)
		var slot_data: Dictionary = state.platform.slot_states[building.slot_id]
		slot_data["building_id"] = building.id
		state.platform.slot_states[building.slot_id] = slot_data


func _assert_badge_matrix(base: Control, state) -> bool:
	var info_layer := base.get_node_or_null("BaseEnvironment/PlatformBoard/BuildingInfo")
	if info_layer == null or info_layer.get_child_count() != BUILDING_SLOTS.size():
		push_error("BuildingInfo must contain exactly one persistent occupancy badge per typed slot.")
		return false
	for slot_id in BUILDING_SLOTS.values():
		var badge = info_layer.get_node_or_null("BuildingOccupancyBadge_%s" % slot_id)
		if badge == null or badge.visible or badge.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			push_error("Every built building badge must be input-transparent and hidden before pointer hover: %s." % slot_id)
			return false

	var fishing_badge = info_layer.get_node("BuildingOccupancyBadge_top_left")
	var fishing_state: Dictionary = fishing_badge.state_for_tests()
	var fishing_status := fishing_badge.find_child("OccupancyStatus", true, false) as Label
	var fishing_portrait := fishing_badge.find_child("OccupantPortrait_0", true, false)
	var mira = state.find_survivor("mira")
	if int(fishing_state.get("assigned_count", -1)) != 2 or int(fishing_state.get("capacity", -1)) != 3 or not bool(fishing_state.get("has_blocked_worker", false)):
		push_error("The Fishing Hut badge must expose a partial 2/3 roster and warn about its incapable assigned worker.")
		return false
	if fishing_status == null or fishing_status.text != "OBSADA • UWAGA":
		push_error("The partial roster with an incapable worker must retain a textual warning.")
		return false
	if fishing_portrait == null or str(fishing_portrait.get("survivor_id")) != str(mira.portrait_id):
		push_error("The persistent building badge must bind the canonical SurvivorState.portrait_id.")
		return false

	var kitchen_state: Dictionary = info_layer.get_node("BuildingOccupancyBadge_top_center").state_for_tests()
	if int(kitchen_state.get("assigned_count", -1)) != 1 or int(kitchen_state.get("capacity", -1)) != 1:
		push_error("The level-one Kitchen badge must expose a full 1/1 roster.")
		return false

	var empty_badge = info_layer.get_node("BuildingOccupancyBadge_center")
	var empty_state: Dictionary = empty_badge.state_for_tests()
	var empty_status := empty_badge.find_child("OccupancyStatus", true, false) as Label
	if int(empty_state.get("assigned_count", -1)) != 0 or empty_status == null or empty_status.text != "NIEOBSADZONE":
		push_error("A built empty building must retain the explicit NIEOBSADZONE content for hover.")
		return false

	var fishing_slot := base.find_child("Slot_top_left", true, false) as Control
	var empty_slot := base.find_child("Slot_center", true, false) as Control
	if fishing_slot == null or empty_slot == null:
		push_error("The occupancy hover fixture requires the Fishing Hut and Infirmary hitboxes.")
		return false
	fishing_slot.grab_focus()
	if fishing_badge.visible:
		push_error("Keyboard focus must not reveal a pointer-only occupancy badge.")
		return false
	fishing_slot.emit_signal("mouse_entered")
	if not fishing_badge.visible:
		push_error("Pointer hover must reveal the built Fishing Hut badge.")
		return false
	for slot_id in BUILDING_SLOTS.values():
		if slot_id != "top_left" and info_layer.get_node("BuildingOccupancyBadge_%s" % slot_id).visible:
			push_error("Pointer hover must reveal exactly one building badge, not %s." % slot_id)
			return false
	fishing_slot.emit_signal("mouse_exited")
	if fishing_badge.visible:
		push_error("Leaving the Fishing Hut hitbox must hide its occupancy badge.")
		return false
	empty_slot.emit_signal("mouse_entered")
	if not empty_badge.visible:
		push_error("Pointer hover must reveal NIEOBSADZONE for a built empty Infirmary.")
		return false
	empty_slot.emit_signal("mouse_exited")
	if empty_badge.visible:
		push_error("Leaving the empty Infirmary hitbox must hide its occupancy badge.")
		return false
	fishing_slot.emit_signal("mouse_entered")
	return true


func _save_snapshot_at_size(file_name: String, target_size: Vector2i) -> bool:
	get_window().size = target_size
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_size() != target_size:
		push_error("Occupancy snapshot has size %s instead of %s." % [image.get_size(), target_size])
		get_tree().quit(1)
		return false
	var output_path := ProjectSettings.globalize_path("res://tmp/" + file_name)
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save occupancy snapshot. Error: %d" % error)
		get_tree().quit(1)
		return false
	return true
