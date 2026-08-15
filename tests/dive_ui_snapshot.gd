extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const BuildingSystemScript := preload("res://scripts/base/BuildingSystem.gd")
const ExpeditionPreparationSystemScript := preload("res://scripts/base/ExpeditionPreparationSystem.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const DivingStationDefinition := preload("res://data/buildings/diving_station.tres")
const DiveCurrentVisualScript := preload("res://scripts/diving/DiveCurrentVisual.gd")
const DiveLootContainerScript := preload("res://scripts/diving/DiveLootContainer.gd")
const PersistentInteractableScript := preload("res://scripts/diving/DivePersistentInteractable.gd")
const DiveRescueSurvivorScript := preload("res://scripts/diving/DiveRescueSurvivor.gd")
const DiveExitLineScript := preload("res://scripts/diving/DiveExitLine.gd")

var _game: Node
var _exit_requested := false

func _ready() -> void:
	var game = GameRootScene.instantiate()
	_game = game
	add_child(game)
	await get_tree().process_frame
	if not game.start_new_campaign("standard", 102, false):
		push_error("Dive UI snapshot could not create the clean revision-2 campaign fixture.")
		_request_exit(1)
		return
	await get_tree().process_frame

	var setup = _prepare_first_tutorial_dive(game)
	if setup == null:
		return
	setup.can_place_buoys = true
	setup.buoy_charges = 1
	setup.can_mark_heavy_objects = true
	var snapshot_backpack_landmark: Dictionary = game.game_state.underwater_world.blueprint.get_landmark("R4-01")
	game.game_state.underwater_world.lost_backpacks["snapshot_diver"] = {
		"diver_id": "snapshot_diver",
		"landmark_id": "R4-01",
		"world_position": snapshot_backpack_landmark.get("position", Vector2.ZERO),
		"items": {"scrap": 1},
		"gear_ids": [],
		"lost_on_day": 1,
		"recovered": false,
	}
	game.game_state.underwater_world.dropped_loot_piles["snapshot_bundle"] = {
		"persistence_id": "snapshot_bundle",
		"landmark_id": "R4-01",
		"world_position": snapshot_backpack_landmark.get("position", Vector2.ZERO) + Vector2(120, 0),
		"items": {"scrap": 1},
		"created_day": 1,
		"recovered": false,
	}
	game.start_dive(setup)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var dive = game.current_scene
	if dive == null or dive.name != "DiveScene":
		push_error("Dive UI snapshot could not enter DiveScene through the active tutorial start contract.")
		_request_exit(1)
		return
	if not _assert_camera_framing(dive):
		return
	if not _assert_minimal_hud(dive):
		return
	if not _save_snapshot("dive_tutorial_start.png"):
		return
	dive.setup.equipped_gear["light"] = "diving_lantern_mk2"
	dive._configure_lighting()
	dive._update_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _save_snapshot("dive_lantern_mk2.png"):
		return
	dive.setup.equipped_gear["light"] = "diving_lantern_mk1"
	dive._configure_lighting()
	dive._update_ui()

	var pickup_by_resource := {}
	for pickup in dive.dive_map.world_pickups:
		if not pickup_by_resource.has(pickup.resource_id):
			pickup_by_resource[pickup.resource_id] = pickup
	if not _assert_pickup_set(pickup_by_resource):
		return
	var food_pickup = pickup_by_resource["food"]
	var pickup_center: Vector2 = food_pickup.global_position
	food_pickup.global_position = pickup_center + Vector2(0.0, -90.0)
	pickup_by_resource["planks"].global_position = pickup_center + Vector2(135.0, -15.0)
	pickup_by_resource["scrap"].global_position = pickup_center + Vector2(-135.0, 15.0)
	dive.diver.reset_at(pickup_center)
	dive._update_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if not _save_snapshot("dive_freestanding_pickups.png"):
		return
	if not await _save_interactable_art_snapshot(dive, pickup_center):
		return
	if not await _save_rescue_and_return_snapshot(dive, pickup_center):
		return

	dive._open_container(dive.dive_map.containers[0])
	await get_tree().process_frame
	if not _save_snapshot("dive_loot_panel.png"):
		return
	dive._take_pending_loot()
	dive._open_container(dive.dive_map.containers[1])
	dive._take_pending_loot()
	dive._open_inventory()
	await get_tree().process_frame
	if not _save_snapshot("dive_inventory_panel.png"):
		return
	dive._close_inventory()
	var authored_current_vector_value = _find_non_axis_current_vector(dive)
	if authored_current_vector_value == null:
		push_error("Dive current snapshot could not find an authored non-axis current vector.")
		_request_exit(1)
		return
	var authored_current_vector: Vector2 = authored_current_vector_value * dive._difficulty_modifier("current_strength_multiplier")
	dive.set_current_visual_sample_for_tests(authored_current_vector, 2.75)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _assert_current_presentation(dive, authored_current_vector):
		return
	if not _save_snapshot("dive_current_vector.png"):
		return
	var current_container = _find_container(dive.dive_map.containers, "tutorial_service_locker")
	if current_container == null:
		push_error("Dive risk snapshot is missing the authored current-zone container.")
		_request_exit(1)
		return
	dive.diver.reset_at(current_container.global_position)
	dive.session.oxygen_left = 19.0
	dive._update_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _save_snapshot("dive_risk_and_inventory.png"):
		return

	dive.session.oxygen_left = 0.0
	dive._on_oxygen_depleted()
	await get_tree().process_frame
	if not _save_snapshot("dive_tutorial_retry.png"):
		return

	print("Dive UI snapshots saved: Lantern I, Lantern II, freestanding pickups, selective loot, drop inventory, deterministic current, interactable art, rescue and return art, risk and tutorial retry states.")
	_request_exit(0)

func _prepare_first_tutorial_dive(game):
	if game.game_state == null:
		push_error("Dive UI snapshot could not create a clean campaign state.")
		_request_exit(1)
		return null

	game.game_state.tutorial.step = TutorialStateScript.Step.BUILD_DIVING_STATION
	var building_system = BuildingSystemScript.new()
	var construction_blocker := building_system.construction_blocker(game.game_state, "bottom_right", DivingStationDefinition)
	if not construction_blocker.is_empty():
		push_error("Dive UI snapshot could not prepare Station I: %s" % construction_blocker)
		_request_exit(1)
		return null
	if not building_system.queue_construction(game.game_state, "bottom_right", DivingStationDefinition):
		push_error("Dive UI snapshot could not build Station I through BuildingSystem.")
		_request_exit(1)
		return null

	var station = game.game_state.find_building_by_definition("diving_station")
	game.game_state.tutorial.step = TutorialStateScript.Step.START_FIRST_DIVE
	var preparation_system = ExpeditionPreparationSystemScript.new()
	var diver_blocker := preparation_system.diver_selection_blocker(game.game_state, station, DivingStationDefinition, "igor")
	if not diver_blocker.is_empty():
		push_error("Dive UI snapshot could not select Igor as the independent diver: %s" % diver_blocker)
		_request_exit(1)
		return null
	if not preparation_system.select_diver(game.game_state, station, DivingStationDefinition, "igor"):
		push_error("Dive UI snapshot could not persist Igor in the current day plan.")
		_request_exit(1)
		return null

	var setup = preparation_system.build_setup(game.game_state, station, DivingStationDefinition, GameDatabase.items)
	if setup == null:
		push_error("Dive UI snapshot could not build the first tutorial ExpeditionSetup.")
		_request_exit(1)
		return null
	return setup

func _save_interactable_art_snapshot(dive, center: Vector2) -> bool:
	var supply_crate = _find_container_visual(dive.dive_map.containers, DiveLootContainerScript.VisualKind.SUPPLY_CRATE)
	var tool_locker = _find_container_visual(dive.dive_map.containers, DiveLootContainerScript.VisualKind.TOOL_LOCKER)
	var lost_backpack = dive.dive_map.lost_backpacks[0] if not dive.dive_map.lost_backpacks.is_empty() else null
	var dropped_bundle = dive.dive_map.dropped_loot_piles[0] if not dive.dive_map.dropped_loot_piles.is_empty() else null
	var buoy = _find_persistent_visual(dive.dive_map.persistent_interactables, PersistentInteractableScript.Kind.BUOY)
	var shortcut = _find_persistent_visual(dive.dive_map.persistent_interactables, PersistentInteractableScript.Kind.SHORTCUT)
	var ship_engine = _find_persistent_visual(dive.dive_map.persistent_interactables, PersistentInteractableScript.Kind.HEAVY_OBJECT, "ship_engine_r1")
	var shipyard_winch = _find_persistent_visual(dive.dive_map.persistent_interactables, PersistentInteractableScript.Kind.HEAVY_OBJECT, "shipyard_winch_r3")
	var industrial_generator = _find_persistent_visual(dive.dive_map.persistent_interactables, PersistentInteractableScript.Kind.HEAVY_OBJECT, "scrapyard_generator_r3")
	var noise_eel = dive.dive_map.threats[0] if not dive.dive_map.threats.is_empty() else null
	var staged_variants := [
		{"label": "supply_crate", "node": supply_crate, "offset": Vector2(-360, -205)},
		{"label": "tool_locker", "node": tool_locker, "offset": Vector2(-180, -205)},
		{"label": "lost_backpack", "node": lost_backpack, "offset": Vector2(180, -205)},
		{"label": "dropped_bundle", "node": dropped_bundle, "offset": Vector2(360, -205)},
		{"label": "shortcut", "node": shortcut, "offset": Vector2(-155, -15)},
		{"label": "ship_engine_r1", "node": ship_engine, "offset": Vector2(75, -15)},
		{"label": "shipyard_winch_r3", "node": shipyard_winch, "offset": Vector2(245, -15)},
		{"label": "scrapyard_generator_r3", "node": industrial_generator, "offset": Vector2(405, -15)},
		{"label": "buoy", "node": buoy, "offset": Vector2(-365, -15)},
		{"label": "noise_eel", "node": noise_eel, "offset": Vector2(0, 175)},
	]
	var missing_variants: Array[String] = []
	var staged_nodes: Array = []
	for variant in staged_variants:
		var staged_node = variant.get("node")
		if staged_node == null:
			missing_variants.append(str(variant.get("label", "unknown")))
			continue
		staged_nodes.append(staged_node)
	if not missing_variants.is_empty():
		push_error("Dive interactable art snapshot is missing production visual variants: %s." % ", ".join(missing_variants))
		_request_exit(1)
		return false

	var visibility_states: Array = []
	for node in dive.dive_map.containers:
		visibility_states.append([node, node.visible])
		node.visible = false
	for node in dive.dive_map.world_pickups:
		visibility_states.append([node, node.visible])
		node.visible = false
	for node in dive.dive_map.persistent_interactables:
		visibility_states.append([node, node.visible])
		node.visible = false
	for node in dive.dive_map.rescue_survivors:
		visibility_states.append([node, node.visible])
		node.visible = false
	for node in dive.dive_map.threats:
		visibility_states.append([node, node.visible])
		node.visible = false
	if dive.dive_map.exit_line != null:
		visibility_states.append([dive.dive_map.exit_line, dive.dive_map.exit_line.visible])
		dive.dive_map.exit_line.visible = false
	var current_visual = dive.current_visual()
	if current_visual != null:
		visibility_states.append([current_visual, current_visual.visible])
		current_visual.visible = false

	var transform_states: Array = []
	for staged_node in staged_nodes:
		transform_states.append([staged_node, staged_node.global_transform])
	var original_diver_position: Vector2 = dive.diver.global_position
	var original_light_id: String = str(dive.setup.equipped_gear.get("light", "diving_lantern_mk1"))
	var dive_was_processing: bool = dive.is_processing()
	var diver_input_was_enabled: bool = dive.diver.input_enabled
	var eel_was_processing: bool = noise_eel.is_processing()
	var original_eel_alert: float = noise_eel.alert_level
	var hud = dive.get_node_or_null("DiveHUD")
	var hud_was_visible: bool = hud.visible if hud != null else true
	var diver_sprite = dive.diver.get_node_or_null("AnimatedSprite2D")
	var diver_sprite_was_visible: bool = diver_sprite.visible if diver_sprite != null else true
	var diver_effects = dive.diver.get_node_or_null("VisualEffects")
	var diver_effects_were_visible: bool = diver_effects.visible if diver_effects != null else true

	dive.set_process(false)
	dive.diver.input_enabled = false
	noise_eel.set_process(false)
	dive.diver.reset_at(center)
	dive.setup.equipped_gear["light"] = "diving_lantern_mk2"
	dive._configure_lighting()
	if hud != null:
		hud.visible = false
	if diver_sprite != null:
		diver_sprite.visible = false
	if diver_effects != null:
		diver_effects.visible = false

	for variant in staged_variants:
		var staged_node = variant.get("node")
		var staged_offset: Vector2 = variant.get("offset", Vector2.ZERO)
		staged_node.visible = true
		staged_node.global_position = center + staged_offset
		staged_node.global_rotation = 0.0
	noise_eel.set_alert(58.0)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var saved := _save_snapshot("dive_interactable_art.png")

	for state in transform_states:
		state[0].global_transform = state[1]
	for state in visibility_states:
		state[0].visible = state[1]
	noise_eel.set_alert(original_eel_alert)
	noise_eel.set_process(eel_was_processing)
	dive.diver.reset_at(original_diver_position)
	dive.setup.equipped_gear["light"] = original_light_id
	dive._configure_lighting()
	dive.diver.input_enabled = diver_input_was_enabled
	dive.set_process(dive_was_processing)
	if hud != null:
		hud.visible = hud_was_visible
	if diver_sprite != null:
		diver_sprite.visible = diver_sprite_was_visible
	if diver_effects != null:
		diver_effects.visible = diver_effects_were_visible
	dive._update_ui()
	return saved

func _save_rescue_and_return_snapshot(dive, center: Vector2) -> bool:
	var definition = ResourceLoader.load("res://data/survivors/leon_wrona.tres")
	if definition == null:
		push_error("Dive rescue snapshot could not load Leon's encounter definition.")
		_request_exit(1)
		return false

	var visibility_states: Array = []
	for node in dive.dive_map.containers:
		visibility_states.append([node, node.visible])
		node.visible = false
	for node in dive.dive_map.world_pickups:
		visibility_states.append([node, node.visible])
		node.visible = false
	for node in dive.dive_map.persistent_interactables:
		visibility_states.append([node, node.visible])
		node.visible = false
	for node in dive.dive_map.rescue_survivors:
		visibility_states.append([node, node.visible])
		node.visible = false
	for node in dive.dive_map.threats:
		visibility_states.append([node, node.visible])
		node.visible = false
	if dive.dive_map.exit_line != null:
		visibility_states.append([dive.dive_map.exit_line, dive.dive_map.exit_line.visible])
		dive.dive_map.exit_line.visible = false
	var current_visual = dive.current_visual()
	if current_visual != null:
		visibility_states.append([current_visual, current_visual.visible])
		current_visual.visible = false

	var return_line = DiveExitLineScript.new()
	return_line.name = "SnapshotReturnLine"
	return_line.configure(1)
	return_line.z_index = 5
	dive.dive_map.add_child(return_line)
	var return_bell = DiveExitLineScript.new()
	return_bell.name = "SnapshotReturnBell"
	return_bell.configure(4)
	return_bell.z_index = 5
	dive.dive_map.add_child(return_bell)

	var trapped = DiveRescueSurvivorScript.new()
	trapped.name = "SnapshotLeonTrapped"
	trapped.configure("snapshot_leon_trapped", definition, DiveRescueSurvivorScript.Stage.TRAPPED)
	trapped.z_index = 7
	dive.dive_map.add_child(trapped)
	var freed = DiveRescueSurvivorScript.new()
	freed.name = "SnapshotLeonFreed"
	freed.configure("snapshot_leon_freed", definition, DiveRescueSurvivorScript.Stage.FREED)
	freed.z_index = 7
	dive.dive_map.add_child(freed)
	var towing = DiveRescueSurvivorScript.new()
	towing.name = "SnapshotLeonTowing"
	towing.configure("snapshot_leon_towing", definition, DiveRescueSurvivorScript.Stage.TOWING)
	towing.z_index = 7
	dive.dive_map.add_child(towing)

	var snapshot_nodes := [return_line, return_bell, trapped, freed, towing]
	for node in snapshot_nodes:
		var sprite_name := "ExitLineSprite" if node is DiveExitLine else "RescueSprite"
		var sprite := node.get_node_or_null(sprite_name) as Sprite2D
		if sprite != null and sprite.texture != null:
			continue
		push_error("Dive rescue snapshot found a runtime object without its production sprite: %s." % node.name)
		_request_exit(1)
		return false

	var original_diver_position: Vector2 = dive.diver.global_position
	var original_light_id: String = str(dive.setup.equipped_gear.get("light", "diving_lantern_mk1"))
	var dive_was_processing: bool = dive.is_processing()
	var diver_input_was_enabled: bool = dive.diver.input_enabled
	var hud = dive.get_node_or_null("DiveHUD")
	var hud_was_visible: bool = hud.visible if hud != null else true
	var diver_effects = dive.diver.get_node_or_null("VisualEffects")
	var diver_effects_were_visible: bool = diver_effects.visible if diver_effects != null else true

	dive.set_process(false)
	dive.diver.input_enabled = false
	dive.diver.reset_at(center)
	dive.setup.equipped_gear["light"] = "diving_lantern_mk2"
	dive._configure_lighting()
	if hud != null:
		hud.visible = false
	if diver_effects != null:
		diver_effects.visible = false

	return_line.global_position = center + Vector2(-380, 72)
	return_bell.global_position = center + Vector2(-220, 72)
	trapped.global_position = center + Vector2(100, -120)
	freed.global_position = center + Vector2(320, -120)
	towing.global_position = center + Vector2(-58, 28)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var saved := _save_snapshot("dive_rescue_and_return.png")

	for node in snapshot_nodes:
		node.free()
	for state in visibility_states:
		state[0].visible = state[1]
	dive.diver.reset_at(original_diver_position)
	dive.setup.equipped_gear["light"] = original_light_id
	dive._configure_lighting()
	dive.diver.input_enabled = diver_input_was_enabled
	dive.set_process(dive_was_processing)
	if hud != null:
		hud.visible = hud_was_visible
	if diver_effects != null:
		diver_effects.visible = diver_effects_were_visible
	dive._update_ui()
	return saved

func _assert_pickup_set(pickup_by_resource: Dictionary) -> bool:
	for resource_id in ["food", "planks", "scrap"]:
		if pickup_by_resource.has(resource_id):
			continue
		push_error("Dive UI snapshot is missing the '%s' freestanding pickup." % resource_id)
		_request_exit(1)
		return false
	return true

func _find_container(containers: Array, container_id: String):
	for container in containers:
		if container.container_id == container_id:
			return container
	return null

func _find_container_visual(containers: Array, visual_kind: int):
	for container in containers:
		if container.visual_kind == visual_kind and not container.opened:
			return container
	for container in containers:
		if container.visual_kind == visual_kind:
			return container
	return null

func _find_persistent_visual(interactables: Array, kind: int, persistent_id: String = ""):
	for interactable in interactables:
		if interactable.kind != kind:
			continue
		if not persistent_id.is_empty() and interactable.persistent_id != persistent_id:
			continue
		if not interactable.completed:
			return interactable
	for interactable in interactables:
		if interactable.kind == kind and (persistent_id.is_empty() or interactable.persistent_id == persistent_id):
			return interactable
	return null

func _find_non_axis_current_vector(dive):
	if dive.game_state == null or dive.game_state.underwater_world == null or dive.game_state.underwater_world.blueprint == null:
		return null
	for zone in dive.game_state.underwater_world.blueprint.current_zones:
		var vector: Vector2 = zone.get("velocity", Vector2.ZERO)
		if not is_zero_approx(vector.x) and not is_zero_approx(vector.y):
			return vector
	return null

func _assert_current_presentation(dive, applied_current: Vector2) -> bool:
	var expected_symbol: String = DiveCurrentVisualScript.direction_symbol_for_vector(applied_current)
	var visual = dive.current_visual()
	if applied_current.length_squared() <= 0.01 or expected_symbol.is_empty():
		push_error("Dive current snapshot is not positioned inside an authored current zone.")
		_request_exit(1)
		return false
	if visual == null or not visual.sampled_vector().is_equal_approx(applied_current) or visual.intensity() <= 0.0:
		push_error("Dive current snapshot does not visualize the exact applied current vector.")
		_request_exit(1)
		return false
	if not visual.is_test_mode() or not is_equal_approx(visual.visual_time(), 2.75):
		push_error("Dive current snapshot requires an explicit frozen presentation time.")
		_request_exit(1)
		return false
	if dive._current_label.text != "PRĄD WODNY  %s" % expected_symbol:
		push_error("Dive current HUD does not show the eight-direction symbol for the applied vector.")
		_request_exit(1)
		return false
	return true

func _assert_minimal_hud(dive) -> bool:
	if dive == null or dive._hud_dock == null or dive._hud_dock.size.y > 80.0:
		push_error("Dive UI snapshot requires a bottom HUD no taller than 80 pixels.")
		_request_exit(1)
		return false
	if dive._tutorial_panel == null or not dive._tutorial_panel.visible or dive._tutorial_panel.size.y > 112.0 or dive._tutorial_title.text.is_empty():
		push_error("Dive tutorial should keep a readable persistent instruction no taller than 112 pixels. Visible=%s size=%s text='%s'" % [dive._tutorial_panel.visible if dive._tutorial_panel != null else false, dive._tutorial_panel.size if dive._tutorial_panel != null else Vector2.ZERO, dive._tutorial_title.text if dive._tutorial_title != null else "<missing>"])
		_request_exit(1)
		return false
	if not dive._tutorial_body.visible or dive._tutorial_body.text.strip_edges().is_empty():
		push_error("The current tutorial action must stay visible without requiring a tooltip.")
		_request_exit(1)
		return false
	if dive._navigation_panel == null or dive._navigation_panel.size.y > 42.0 or not dive._return_label.text.contains("LINA") or dive._objective_label.text.contains("\n"):
		push_error("Return and objective navigation should share one compact line. Return='%s' objective='%s' size=%s" % [dive._return_label.text, dive._objective_label.text, dive._navigation_panel.size if dive._navigation_panel != null else Vector2.ZERO])
		_request_exit(1)
		return false
	var previous_target_id: String = dive.setup.objective_target_landmark_id
	var previous_target_label: String = dive.setup.objective_target_label
	var previous_tutorial_mode: bool = dive.setup.tutorial_mode
	dive.setup.tutorial_mode = false
	dive.setup.objective_target_landmark_id = "R1-09"
	dive.setup.objective_target_label = "Zalane Archiwum"
	var mission_navigation: String = dive._compact_objective_text()
	dive.setup.objective_target_landmark_id = previous_target_id
	dive.setup.objective_target_label = previous_target_label
	dive.setup.tutorial_mode = previous_tutorial_mode
	if not mission_navigation.contains("ZALANE ARCHIWUM") or mission_navigation.contains("\n"):
		push_error("Compact navigation must retain the tracked mission location, direction and distance: '%s'." % mission_navigation)
		_request_exit(1)
		return false
	var previous_oxygen: float = dive.session.oxygen_left
	var previous_status: String = dive._status_message
	var previous_status_time: float = dive._status_message_time
	dive.session.oxygen_left = dive.session.oxygen_capacity * 0.09
	dive._status_message = "Zabrano przedmiot."
	dive._status_message_time = 3.0
	dive._update_ui()
	var critical_warning_visible: bool = dive._warning_label.text == "TLEN KRYTYCZNY"
	dive.session.oxygen_left = previous_oxygen
	dive._status_message = previous_status
	dive._status_message_time = previous_status_time
	dive._update_ui()
	if not critical_warning_visible:
		push_error("A transient status toast must never replace the critical oxygen alarm.")
		_request_exit(1)
		return false
	return true

func _assert_camera_framing(dive) -> bool:
	var camera := dive.diver.get_node_or_null("Camera2D") as Camera2D if dive != null and dive.diver != null else null
	if camera == null or not camera.zoom.is_equal_approx(Vector2(1.2, 1.2)):
		push_error("Dive camera should keep the approved 1.20 close framing. Actual zoom: %s" % [camera.zoom if camera != null else Vector2.ZERO])
		_request_exit(1)
		return false
	if not camera.position_smoothing_enabled or not is_equal_approx(camera.position_smoothing_speed, 7.0):
		push_error("Closer dive framing should retain the stable 7.0 position smoothing contract.")
		_request_exit(1)
		return false
	return true

func _save_snapshot(file_name: String) -> bool:
	var image := get_viewport().get_texture().get_image()
	var output_directory := ProjectSettings.globalize_path("res://tmp")
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error != OK:
		push_error("Could not prepare the dive UI snapshot output directory. Error: %d" % directory_error)
		_request_exit(1)
		return false
	var output_path := output_directory.path_join(file_name)
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save dive UI snapshot. Error: %d" % error)
		_request_exit(1)
		return false
	return true

func _request_exit(exit_code: int) -> void:
	if _exit_requested:
		return
	_exit_requested = true
	call_deferred("_teardown_and_quit", exit_code)

func _teardown_and_quit(exit_code: int) -> void:
	if is_instance_valid(_game) and _game.is_inside_tree():
		_game.call("show_main_menu")
		await get_tree().process_frame
		await get_tree().process_frame
	if is_instance_valid(_game):
		_game.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	_game = null
	get_tree().quit(exit_code)
