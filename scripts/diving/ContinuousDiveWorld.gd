class_name ContinuousDiveWorld
extends Node2D

const WorldStateScript := preload("res://scripts/data/UnderwaterWorldState.gd")
const MapSceneCompilerScript := preload("res://underwater_map_workbench/runtime/UnderwaterMapSceneCompiler.gd")
const ContainerScript := preload("res://scripts/diving/DiveLootContainer.gd")
const DiseaseHazardContainerScript := preload("res://scripts/diving/DiveDiseaseHazardContainer.gd")
const WorldPickupScript := preload("res://scripts/diving/DiveWorldPickup.gd")
const ExitLineScript := preload("res://scripts/diving/DiveExitLine.gd")
const ThreatScript := preload("res://scripts/diving/DiveThreat.gd")
const LostBackpackScript := preload("res://scripts/diving/DiveLostBackpack.gd")
const DroppedLootScript := preload("res://scripts/diving/DiveDroppedLoot.gd")
const PersistentInteractableScript := preload("res://scripts/diving/DivePersistentInteractable.gd")
const RescueSurvivorScript := preload("res://scripts/diving/DiveRescueSurvivor.gd")
const DifficultyMathScript := preload("res://scripts/core/DifficultyMath.gd")
const NavigationSnapshotScript := preload("res://scripts/diving/DiveNavigationSnapshot.gd")
const MapNavigationRasterScript := preload("res://scripts/diving/MapNavigationRaster.gd")
const TerrainOcclusionScript := preload("res://scripts/diving/DiveTerrainOcclusion.gd")

const STREAM_RADIUS_CHUNKS := 3
const DROPPED_LOOT_MERGE_DISTANCE := 96.0
const AUTHORED_VISUAL_META := &"authored_map_visual"
const AUTHORED_VISUAL_SCENE_PATH_META := &"authored_map_visual_scene_path"

var exit_line: DiveExitLine
var containers: Array[DiveLootContainer] = []
var world_pickups: Array[DiveWorldPickup] = []
var threats: Array[Node2D] = []
var persistent_interactables: Array[DivePersistentInteractable] = []
var lost_backpacks: Array[DiveLostBackpack] = []
var dropped_loot_piles: Array[DiveDroppedLoot] = []
var rescue_survivors: Array[DiveRescueSurvivor] = []
var persistent_opened: Array[String] = []
var persistent_remaining_contents: Dictionary = {}
var active_sector_id: String = ""
var streamed_sector_ids: Array[String] = []
var active_chunk_keys: Array[String] = []

var _world_state
var _blueprint
var _expedition_setup
var _nav_cells := PackedByteArray()
var _grid_width: int = 0
var _grid_height: int = 0
var _cell_scale := Vector2.ONE
var _collision_segment_count: int = 0
var _last_stream_chunk := Vector2i(-9999, -9999)
var _start_position := Vector2.ZERO
var _dropped_loot_fallback_sequence: int = 0
var _runtime_dynamic: Node2D
var _collision_segments_by_chunk: Dictionary = {}
var _loaded_collision_chunks: Dictionary = {}
var _collision_chunks_root: Node2D
var _structure_roots_container: Node2D
var _structure_roots_by_id: Dictionary = {}
var _structure_collision_segments_by_id: Dictionary = {}
var _collision_partition_active := false
var _graphics_quality := "high"
var _reduced_motion := false
var _last_stream_radius := Vector2i(-1, -1)
var _snapshot_analysis_mode := false
var _static_authored_visual_bindings: Array[Dictionary] = []

func _ready() -> void:
	if _blueprint == null:
		var default_world = WorldStateScript.new()
		default_world.setup(1)
		var map_errors := MapSceneCompilerScript.new().generate(default_world, 1)
		for map_error in map_errors:
			push_error("Nie udało się załadować sceny mapy: %s" % map_error)
		if not map_errors.is_empty():
			return
		configure(default_world, default_world.entry_sector_id)

func configure(world_state, sector_id: String = "", expedition_setup = null) -> void:
	var map_errors := PackedStringArray()
	if world_state == null:
		world_state = WorldStateScript.new()
		world_state.setup(1)
		map_errors = MapSceneCompilerScript.new().generate(world_state, 1)
		for map_error in map_errors:
			push_error("Nie udało się załadować sceny mapy: %s" % map_error)
	else:
		map_errors = MapSceneCompilerScript.new().ensure_world_is_current(world_state)
		for map_error in map_errors:
			push_error("Kampania nie odpowiada scenie mapy: %s" % map_error)
	if not map_errors.is_empty() or world_state.blueprint == null:
		if map_errors.is_empty():
			push_error("Nie udało się skonfigurować świata: brak WorldBlueprint.")
		return

	_world_state = world_state
	_blueprint = world_state.blueprint
	_expedition_setup = expedition_setup
	var resolved_id: String = _blueprint.resolve_landmark_id(sector_id)
	active_sector_id = resolved_id if not resolved_id.is_empty() else _blueprint.entry_landmark_id
	persistent_opened.assign(_world_state.opened_containers)
	persistent_remaining_contents = _world_state.remaining_container_contents.duplicate(true)

	_rebuild_world()
	reset_attempt()
	if not _snapshot_analysis_mode:
		update_streaming(start_position(), true)


## Design-time certification still builds the canonical raster and real
## interactable/threat nodes, but omits presentation and streamed physics that
## are not part of DiveNavigationSnapshot.
func set_snapshot_analysis_mode(enabled: bool) -> void:
	_snapshot_analysis_mode = enabled

func _runtime_root() -> Node2D:
	if _runtime_dynamic != null and is_instance_valid(_runtime_dynamic):
		return _runtime_dynamic
	_runtime_dynamic = get_node_or_null("RuntimeDynamic") as Node2D
	if _runtime_dynamic == null:
		_runtime_dynamic = Node2D.new()
		_runtime_dynamic.name = "RuntimeDynamic"
		add_child(_runtime_dynamic)
	return _runtime_dynamic

func _runtime_add_child(node: Node) -> void:
	_runtime_root().add_child(node)

func _clear_runtime_dynamic() -> void:
	_static_authored_visual_bindings.clear()
	_structure_roots_by_id.clear()
	_structure_collision_segments_by_id.clear()
	_structure_roots_container = null
	_collision_partition_active = false
	var root := _runtime_root()
	for child in root.get_children():
		root.remove_child(child)
		child.free()

func reset_attempt() -> void:
	_reset_dropped_loot_piles()
	for container in containers:
		if persistent_opened.has(container.container_id):
			container.restore_contents({})
		elif persistent_remaining_contents.has(container.container_id):
			container.restore_contents(persistent_remaining_contents[container.container_id])
		else:
			container.restore_initial_contents()
	for pickup in world_pickups:
		if pickup != null and is_instance_valid(pickup):
			pickup.reset_attempt()
	for threat in threats:
		if threat != null and is_instance_valid(threat) and threat.has_method("reset_attempt"):
			threat.reset_attempt()
	for interactable in persistent_interactables:
		if interactable != null and is_instance_valid(interactable):
			interactable.reset_attempt()
	for rescue_survivor in rescue_survivors:
		if rescue_survivor != null and is_instance_valid(rescue_survivor):
			rescue_survivor.reset_attempt()
	_reset_structure_dynamic_bodies()


func _reset_structure_dynamic_bodies() -> void:
	for root_value in _structure_roots_by_id.values():
		if not root_value is Node2D:
			continue
		var dynamic_bodies := (root_value as Node2D).get_node_or_null("DynamicBodies")
		if dynamic_bodies == null:
			continue
		if dynamic_bodies.has_method("reset_attempt"):
			dynamic_bodies.call("reset_attempt")
		for descendant in dynamic_bodies.find_children("*", "", true, false):
			if descendant.has_method("reset_attempt"):
				descendant.call("reset_attempt")

func start_position() -> Vector2:
	return _start_position

func world_size() -> Vector2:
	return _blueprint.world_size if _blueprint != null else Vector2.ONE


func terrain_visual_profiles() -> Array[Resource]:
	return []


func set_graphics_quality(quality_id: String) -> void:
	var normalized := quality_id if quality_id in ["low", "medium", "high"] else "high"
	var quality_changed := normalized != _graphics_quality
	_graphics_quality = normalized
	_apply_interactable_visual_setting(&"set_graphics_quality", _graphics_quality)
	if quality_changed:
		_refresh_static_authored_visuals()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_apply_interactable_visual_setting(&"set_reduced_motion", enabled)


func set_interactable_visual_time_for_tests(time_seconds: float) -> void:
	_apply_interactable_visual_setting(&"set_visual_time_for_tests", maxf(time_seconds, 0.0))


func visual_context_at(world_position: Vector2) -> Dictionary:
	if _blueprint == null:
		return {}
	var region: Dictionary = _blueprint.get_region_at(world_position)
	if region.is_empty():
		return {}
	var region_id := str(region.get("id", ""))
	var profile_state := _blended_visual_profile_at(world_position)
	return {
		"region_id": region_id,
		"depth_ratio": clampf(world_position.y / maxf(world_size().y, 1.0), 0.0, 1.0),
		"water_color": profile_state.get("water_color", region.get("water_color", Color(0.035, 0.20, 0.26, 1.0))),
		"accent_color": profile_state.get("caustics_color", region.get("accent_color", Color(0.18, 0.75, 0.80, 1.0))),
		"profile": profile_state,
	}


func _blended_visual_profile_at(world_position: Vector2) -> Dictionary:
	if _blueprint == null:
		return {}
	var region: Dictionary = _blueprint.get_region_at(world_position)
	if region.is_empty():
		return {}
	var depth_ratio := clampf(world_position.y / maxf(world_size().y, 1.0), 0.0, 1.0)
	var region_weights := {}
	var region_id := str(region.get("id", "")).strip_edges().to_lower()
	if not region_id.is_empty():
		region_weights[region_id] = 1.0
	return {
		"water_color": region.get("water_color", Color(0.035, 0.20, 0.26, 1.0)),
		"caustics_color": region.get("accent_color", Color(0.18, 0.75, 0.80, 1.0)),
		"water_clarity": lerpf(0.82, 0.48, depth_ratio),
		"suspended_particle_density": lerpf(0.08, 0.24, depth_ratio),
		"caustics_strength": lerpf(0.32, 0.10, depth_ratio),
		"current_distortion_strength": 0.0,
		"depth_ratio": depth_ratio,
		"region_weights": region_weights,
	}


func _apply_interactable_visual_setting(method: StringName, value: Variant) -> void:
	var candidates: Array[Node] = []
	if exit_line != null:
		candidates.append(exit_line)
	candidates.append_array(containers)
	candidates.append_array(world_pickups)
	candidates.append_array(persistent_interactables)
	candidates.append_array(rescue_survivors)
	var visited := {}
	for candidate in candidates:
		if candidate == null or not is_instance_valid(candidate):
			continue
		var instance_id := candidate.get_instance_id()
		if visited.has(instance_id):
			continue
		visited[instance_id] = true
		if candidate.has_method(method):
			candidate.call(method, value)


func _configure_interactable_presentation(target: Node2D, record: Dictionary, stable_id: String) -> void:
	if target == null:
		return
	var region_hint := _presentation_region_hint(record, stable_id, target.position)
	if target.has_method("configure_visual_context"):
		target.call("configure_visual_context", visual_context_at(target.position), region_hint)
	if target.has_method("set_graphics_quality"):
		target.call("set_graphics_quality", _graphics_quality)
	if target.has_method("set_reduced_motion"):
		target.call("set_reduced_motion", _reduced_motion)


func _presentation_region_hint(record: Dictionary, _stable_id: String, world_position: Vector2) -> String:
	for landmark_key in ["landmark_id", "entry_landmark_id"]:
		var landmark_id := str(record.get(landmark_key, ""))
		if landmark_id.is_empty() or _blueprint == null:
			continue
		var linked_landmark: Dictionary = _blueprint.get_landmark(landmark_id)
		var linked_region := str(linked_landmark.get("region_id", "")).to_upper()
		if not linked_region.is_empty():
			return linked_region
	if _blueprint != null:
		var nearest_landmark: Dictionary = _blueprint.get_nearest_landmark(world_position)
		var nearest_region := str(nearest_landmark.get("region_id", "")).to_upper()
		if not nearest_region.is_empty():
			return nearest_region
	return str(visual_context_at(world_position).get("region_id", "")).to_upper()

func collision_segment_count() -> int:
	return _collision_segment_count

func is_world_position_navigable(world_position: Vector2) -> bool:
	if _grid_width <= 0 or _grid_height <= 0 or _nav_cells.is_empty():
		return false
	var cell := _world_to_cell(world_position)
	return _is_open_cell(cell.x, cell.y)

func nearest_navigable_position(candidate: Vector2, clearance_world: float = 48.0) -> Vector2:
	if _grid_width <= 0 or _grid_height <= 0 or _nav_cells.is_empty():
		return candidate
	return _nearest_open_world_position(candidate, -1, clearance_world)


func navigation_snapshot(
	clearance_world: float = NavigationSnapshotScript.DEFAULT_DIVER_CLEARANCE
) -> DiveNavigationSnapshot:
	var snapshot := NavigationSnapshotScript.new()
	var resolved_exit_position := _start_position
	if exit_line != null and is_instance_valid(exit_line):
		resolved_exit_position = exit_line.global_position
	var current_zones: Array = _blueprint.current_zones if _blueprint != null else []
	var depth_profile_points := PackedVector2Array()
	if _blueprint != null:
		depth_profile_points = _blueprint.depth_profile_points.duplicate()
	snapshot.configure(
		world_size(),
		Vector2i(_grid_width, _grid_height),
		_cell_scale,
		_nav_cells,
		clearance_world,
		_start_position,
		resolved_exit_position,
		current_zones,
		depth_profile_points,
		_navigation_closed_gate_descriptors(),
		_navigation_target_descriptors(),
		_navigation_threat_descriptors()
	)
	return snapshot

func create_or_merge_dropped_loot_pile(
	preferred_id: String,
	loot: Dictionary,
	world_position: Vector2,
	created_day: int
) -> DiveDroppedLoot:
	var normalized_loot := _normalized_loot(loot)
	if normalized_loot.is_empty():
		return null
	var resolved_id := preferred_id.strip_edges()
	if resolved_id.is_empty():
		_dropped_loot_fallback_sequence += 1
		resolved_id = "dropped_loot_%d_runtime_%03d" % [maxi(created_day, 1), _dropped_loot_fallback_sequence]
	var merge_target := _find_dropped_loot_merge_target(resolved_id, world_position)
	if merge_target != null:
		for resource_id in normalized_loot.keys():
			merge_target.contents[resource_id] = int(merge_target.contents.get(resource_id, 0)) + int(normalized_loot[resource_id])
		if merge_target.landmark_id.is_empty():
			merge_target.landmark_id = landmark_id_at(merge_target.global_position)
		merge_target.set_opened(false)
		return merge_target

	var resolved_position := nearest_navigable_position(world_position, 28.0)
	var record := {
		"persistence_id": resolved_id,
		"world_position": resolved_position,
		"landmark_id": landmark_id_at(resolved_position),
		"items": normalized_loot,
		"created_day": maxi(created_day, 0),
		"recovered": false,
	}
	var pile = DroppedLootScript.new()
	pile.name = "DroppedLoot%s" % resolved_id.to_pascal_case()
	pile.configure_dropped_loot(resolved_id, record, true)
	pile.position = resolved_position
	pile.z_index = 6
	_runtime_add_child(pile)
	_configure_interactable_presentation(pile, record, resolved_id)
	containers.append(pile)
	dropped_loot_piles.append(pile)
	return pile

func depth_at(world_position: Vector2) -> float:
	if _blueprint == null:
		return 0.0
	return _blueprint.depth_at(world_position)

func module_name_at(world_position: Vector2) -> String:
	if _blueprint == null:
		return "Nieznany obszar"
	var landmark: Dictionary = _blueprint.get_nearest_landmark(world_position)
	return str(landmark.get("short_name", landmark.get("display_name", "Nieznany obszar")))

func get_nearest_interactable(world_position: Vector2, maximum_distance: float = 125.0):
	var nearest = null
	var nearest_distance := maximum_distance
	for node in get_tree().get_nodes_in_group("dive_interactable"):
		if not is_ancestor_of(node) or not node.has_method("can_interact") or not node.can_interact():
			continue
		var distance := world_position.distance_to(node.global_position)
		if distance <= nearest_distance:
			nearest = node
			nearest_distance = distance
	return nearest

func current_at(world_position: Vector2) -> Vector2:
	if _blueprint == null:
		return Vector2.ZERO
	for zone in _blueprint.current_zones:
		var rect: Rect2 = zone.get("rect", Rect2())
		if rect.has_point(world_position):
			return zone.get("velocity", Vector2.ZERO)
	return Vector2.ZERO


func scout_signal_at(
	world_position: Vector2,
	maximum_distance: float = 640.0,
	minimum_current_speed: float = 60.0
) -> Dictionary:
	var active_threats: Array[Dictionary] = []
	for threat in threats:
		if threat == null or not is_instance_valid(threat):
			continue
		if threat.has_method("is_defeated") and threat.is_defeated():
			continue
		active_threats.append({
			"id": str(threat.get("threat_id")),
			"position": threat.global_position,
		})
	var current_records: Array = _blueprint.current_zones if _blueprint != null else []
	return NavigationSnapshotScript.scout_signal_for_records(
		world_position,
		active_threats,
		current_records,
		maximum_distance,
		minimum_current_speed
	)

func objective_position(mandatory_opened: int) -> Vector2:
	for container in containers:
		if container.mandatory_order == mandatory_opened and not container.opened:
			return container.global_position
	return exit_line.global_position if exit_line != null else start_position()

func landmark_id_at(world_position: Vector2) -> String:
	if _blueprint == null:
		return ""
	var landmark: Dictionary = _blueprint.get_nearest_landmark(world_position)
	return str(landmark.get("id", ""))

func update_streaming(world_position: Vector2, force: bool = false, visible_half_extent: Vector2 = Vector2.ZERO) -> void:
	if _blueprint == null:
		return
	_refresh_towed_survivor_visual_context()
	var center_chunk: Vector2i = _blueprint.chunk_coord_at(world_position)
	var safe_chunk_size := maxi(_blueprint.chunk_size, 1)
	var stream_radius := Vector2i(
		maxi(STREAM_RADIUS_CHUNKS, ceili(maxf(visible_half_extent.x, 0.0) / float(safe_chunk_size)) + 1),
		maxi(STREAM_RADIUS_CHUNKS, ceili(maxf(visible_half_extent.y, 0.0) / float(safe_chunk_size)) + 1)
	)
	if not force and center_chunk == _last_stream_chunk and stream_radius == _last_stream_radius:
		return
	_last_stream_chunk = center_chunk
	_last_stream_radius = stream_radius
	active_chunk_keys.clear()
	streamed_sector_ids.clear()
	active_chunk_keys.assign(_world_state.get_stream_chunk_keys(world_position, stream_radius))
	for landmark in _blueprint.landmarks:
		var landmark_chunk: Vector2i = _blueprint.chunk_coord_at(landmark.get("position", Vector2.ZERO))
		if absi(landmark_chunk.x - center_chunk.x) <= stream_radius.x and absi(landmark_chunk.y - center_chunk.y) <= stream_radius.y:
			streamed_sector_ids.append(str(landmark.get("id", "")))
	_sync_collision_chunks(active_chunk_keys)


func _refresh_towed_survivor_visual_context() -> void:
	for survivor in rescue_survivors:
		if survivor == null or not is_instance_valid(survivor):
			continue
		if survivor.stage != DiveRescueSurvivor.Stage.TOWING:
			continue
		var context := visual_context_at(survivor.global_position)
		var region_id := str(context.get("region_id", "")).to_upper()
		survivor.sync_visual_context(context, region_id, 0.01)


func present_canonical_terrain_contacts(contacts: Array) -> bool:
	# The clean baseline has no authored terrain impact renderer. Physical world
	# boundaries remain canonical, while this optional presentation hook is off.
	return false


func _reset_dropped_loot_piles() -> void:
	_dropped_loot_fallback_sequence = 0
	for pile in dropped_loot_piles.duplicate():
		if pile == null or not is_instance_valid(pile):
			dropped_loot_piles.erase(pile)
			containers.erase(pile)
			continue
		if not pile.created_in_session:
			continue
		dropped_loot_piles.erase(pile)
		containers.erase(pile)
		var parent: Node = pile.get_parent()
		if parent != null:
			parent.remove_child(pile)
		pile.queue_free()

func _find_dropped_loot_merge_target(persistence_id: String, world_position: Vector2) -> DiveDroppedLoot:
	var nearest: DiveDroppedLoot = null
	var nearest_distance := DROPPED_LOOT_MERGE_DISTANCE
	for pile in dropped_loot_piles:
		if pile == null or not is_instance_valid(pile):
			continue
		if pile.persistence_id == persistence_id:
			return pile
		var distance := pile.global_position.distance_to(world_position)
		if distance <= nearest_distance and _has_open_segment(pile.global_position, world_position):
			nearest = pile
			nearest_distance = distance
	return nearest

func _has_open_segment(from_position: Vector2, to_position: Vector2) -> bool:
	if _grid_width <= 0 or _grid_height <= 0 or _nav_cells.is_empty():
		return false
	var distance := from_position.distance_to(to_position)
	var sample_step := maxf(minf(_cell_scale.x, _cell_scale.y) * 0.5, 2.0)
	var sample_count := maxi(int(ceil(distance / sample_step)), 1)
	for index in range(sample_count + 1):
		var ratio := float(index) / float(sample_count)
		if not is_world_position_navigable(from_position.lerp(to_position, ratio)):
			return false
	return true

func _normalized_loot(value) -> Dictionary:
	var result: Dictionary = {}
	if not (value is Dictionary):
		return result
	for resource_id in value.keys():
		var id := str(resource_id)
		var amount := maxi(int(value[resource_id]), 0)
		if not id.is_empty() and amount > 0:
			result[id] = amount
	return result


func _navigation_target_descriptors() -> Array[Dictionary]:
	var descriptors: Array[Dictionary] = []
	for container in containers:
		if container == null or not is_instance_valid(container):
			continue
		var container_kind := "authored"
		if container.get_script() == LostBackpackScript:
			container_kind = "lost_backpack"
		elif container.get_script() == DroppedLootScript:
			container_kind = "dropped_loot"
		var container_descriptor := {
			"id": container.container_id,
			"kind": "container",
			"container_kind": container_kind,
			"display_name": container.display_name,
			"position": container.global_position,
			"requested_position": _loot_requested_position(container.container_id, container.global_position),
			"landmark_id": landmark_id_at(container.global_position),
			"contents": container.contents.duplicate(true),
			"mandatory": container.mandatory_order >= 0,
			"mandatory_order": container.mandatory_order,
			"story": false,
			"required_tool": container.required_tool,
			"interaction_action": container.interaction_action,
			"interaction_seconds": container.interaction_seconds,
			"available": container.can_interact(),
			"completed": container.opened,
		}
		if container.get_script() == DiseaseHazardContainerScript:
			container_descriptor["disease_hazard"] = true
			container_descriptor["disease_id"] = str(container.disease_id)
			container_descriptor["disease_exposure_pressure"] = int(container.exposure_pressure)
			container_descriptor["disease_source_kind"] = str(container.exposure_source_kind)
			container_descriptor["disease_source_id"] = str(container.exposure_source_id)
		if container_kind == "lost_backpack":
			var gear_ids = container.get("gear_ids")
			container_descriptor["gear_ids"] = gear_ids.duplicate() if gear_ids is Array else []
			container_descriptor["owner_diver_id"] = str(container.get("owner_diver_id"))
		elif container_kind == "dropped_loot":
			container_descriptor["persistence_id"] = str(container.get("persistence_id"))
		descriptors.append(container_descriptor)

	for pickup in world_pickups:
		if pickup == null or not is_instance_valid(pickup):
			continue
		descriptors.append({
			"id": pickup.pickup_id,
			"kind": "pickup",
			"display_name": pickup.display_name,
			"position": pickup.global_position,
			"requested_position": _loot_requested_position(pickup.pickup_id, pickup.global_position),
			"landmark_id": landmark_id_at(pickup.global_position),
			"contents": {pickup.resource_id: 1},
			"full_pickup": true,
			"mandatory": false,
			"story": false,
			"required_tool": "",
			"interaction_action": "collect",
			"interaction_seconds": pickup.interaction_seconds,
			"available": pickup.can_interact(),
			"completed": pickup.collected,
		})

	for rescue_survivor in rescue_survivors:
		if rescue_survivor == null or not is_instance_valid(rescue_survivor):
			continue
		var rescue_definition = rescue_survivor.definition
		var definition_snapshot = rescue_definition.duplicate(true) if rescue_definition is Resource else null
		var rescue_descriptor := {
			"id": rescue_survivor.encounter_id,
			"kind": "rescue",
			"position": rescue_survivor.global_position,
			"requested_position": _rescue_requested_position(rescue_survivor.encounter_id, rescue_survivor.global_position),
			"landmark_id": landmark_id_at(rescue_survivor.global_position),
			"definition": definition_snapshot,
			"definition_id": str(rescue_definition.get("id")) if rescue_definition != null else "",
			"required_tool": rescue_survivor.required_tool,
			"interaction_action": rescue_survivor.interaction_action,
			"interaction_seconds": rescue_survivor.interaction_seconds,
			"stage": int(rescue_survivor.stage),
			"available": rescue_survivor.can_interact(),
			"completed": false,
		}
		if rescue_definition != null:
			rescue_descriptor["stabilization_medicine_cost"] = int(rescue_definition.get("stabilization_medicine_cost"))
			rescue_descriptor["stabilized_health"] = int(rescue_definition.get("stabilized_health"))
			rescue_descriptor["unstabilized_health"] = int(rescue_definition.get("unstabilized_health"))
			rescue_descriptor["stabilized_movement_multiplier"] = float(rescue_definition.get("stabilized_movement_multiplier"))
			rescue_descriptor["unstabilized_movement_multiplier"] = float(rescue_definition.get("unstabilized_movement_multiplier"))
			rescue_descriptor["stabilized_oxygen_multiplier"] = float(rescue_definition.get("stabilized_oxygen_multiplier"))
			rescue_descriptor["unstabilized_oxygen_multiplier"] = float(rescue_definition.get("unstabilized_oxygen_multiplier"))
		descriptors.append(rescue_descriptor)

	for interactable in persistent_interactables:
		if interactable == null or not is_instance_valid(interactable):
			continue
		var persistent_kind := _persistent_kind_name(interactable.kind)
		var persistent_descriptor := {
			"id": interactable.persistent_id,
			"kind": "persistent_objective",
			"persistent_kind": persistent_kind,
			"display_name": interactable.display_name,
			"position": interactable.global_position,
			"requested_position": _persistent_requested_position(
				interactable.persistent_id,
				persistent_kind,
				interactable.global_position
			),
			"landmark_id": landmark_id_at(interactable.global_position),
			"required_tool": interactable.required_tool,
			"interaction_action": interactable.interaction_action,
			"interaction_seconds": interactable.interaction_seconds,
			"available": interactable.can_interact(),
			"completed": interactable.completed,
			"campaign_completed": interactable.campaign_completed,
			"is_obstacle": persistent_kind == "shortcut" and not interactable.completed,
		}
		if persistent_kind == "shortcut":
			persistent_descriptor["obstacle"] = _shortcut_gate_descriptor(interactable)
		elif persistent_kind == "heavy_object" and _blueprint != null:
			var heavy_definition: Dictionary = _blueprint.get_heavy_object(interactable.persistent_id)
			var rewards = heavy_definition.get("rewards", {})
			persistent_descriptor["rewards"] = rewards.duplicate(true) if rewards is Dictionary else {}
		descriptors.append(persistent_descriptor)
	return descriptors


func _navigation_closed_gate_descriptors() -> Array[Dictionary]:
	var descriptors: Array[Dictionary] = []
	for interactable in persistent_interactables:
		if (
			interactable == null
			or not is_instance_valid(interactable)
			or interactable.kind != PersistentInteractableScript.Kind.SHORTCUT
		):
			continue
		var descriptor := _shortcut_gate_descriptor(interactable)
		if bool(descriptor.get("active", false)):
			descriptors.append(descriptor)
	return descriptors


func _navigation_threat_descriptors() -> Array[Dictionary]:
	var descriptors: Array[Dictionary] = []
	for threat in threats:
		if threat == null or not is_instance_valid(threat):
			continue
		var definition = threat.get("definition")
		descriptors.append({
			"id": str(threat.get("threat_id")),
			"kind": "threat",
			"defeated": bool(threat.is_defeated()) if threat.has_method("is_defeated") else false,
			"position": threat.global_position,
			"requested_position": _threat_requested_position(str(threat.get("threat_id")), threat.global_position),
			"landmark_id": landmark_id_at(threat.global_position),
			"definition": definition.duplicate(true) if definition is Resource else null,
			"definition_id": str(definition.get("id")) if definition != null else "",
		})
	return descriptors


func _shortcut_gate_descriptor(interactable: DivePersistentInteractable) -> Dictionary:
	var gate_transform := interactable.global_transform
	var gate_size := Vector2(interactable.gate_width, NavigationSnapshotScript.SHORTCUT_GATE_HEIGHT)
	var collision := interactable.get_node_or_null("ShortcutGateCollision/CollisionShape2D") as CollisionShape2D
	var collision_active := not interactable.completed
	if collision != null:
		gate_transform = collision.global_transform
		collision_active = collision_active and not collision.disabled
		if collision.shape is RectangleShape2D:
			gate_size = (collision.shape as RectangleShape2D).size
	return {
		"id": interactable.persistent_id,
		"transform": gate_transform,
		"position": gate_transform.origin,
		"rotation": gate_transform.get_rotation(),
		"size": gate_size,
		"active": collision_active,
	}


func _persistent_kind_name(kind: int) -> String:
	match kind:
		PersistentInteractableScript.Kind.BUOY:
			return "buoy"
		PersistentInteractableScript.Kind.SHORTCUT:
			return "shortcut"
		PersistentInteractableScript.Kind.HEAVY_OBJECT:
			return "heavy_object"
		PersistentInteractableScript.Kind.FIXED_DEVICE:
			return "fixed_device"
	return "unknown"


func _loot_requested_position(target_id: String, fallback: Vector2) -> Vector2:
	if _blueprint == null:
		return fallback
	for spawn in _blueprint.loot_spawns:
		if str(spawn.get("id", "")) != target_id:
			continue
		return spawn.get("position", fallback)
	return fallback


func _rescue_requested_position(target_id: String, fallback: Vector2) -> Vector2:
	if _blueprint == null:
		return fallback
	for spawn in _blueprint.rescue_spawns:
		if str(spawn.get("id", "")) != target_id:
			continue
		return spawn.get("position", fallback)
	return fallback


func _persistent_requested_position(target_id: String, kind: String, fallback: Vector2) -> Vector2:
	if _blueprint == null:
		return fallback
	match kind:
		"buoy":
			for spawn in _blueprint.buoy_spawns:
				if str(spawn.get("id", "")) == target_id:
					return spawn.get("position", fallback)
			var landmark: Dictionary = _blueprint.get_landmark_by_anchor(target_id)
			return landmark.get("position", fallback) + Vector2(0.0, -48.0)
		"shortcut":
			for spawn in _blueprint.shortcut_spawns:
				if str(spawn.get("id", "")) == target_id:
					return spawn.get("position", fallback)
			if _blueprint.connection_lookup.has(target_id):
				var connection: Dictionary = _blueprint.connections[int(_blueprint.connection_lookup[target_id])]
				var points: PackedVector2Array = connection.get("path_points", PackedVector2Array())
				if points.size() >= 2:
					return points[points.size() >> 1]
		"heavy_object":
			var definition: Dictionary = _blueprint.get_heavy_object(target_id)
			return definition.get("position", fallback)
		"fixed_device":
			for spawn in _blueprint.fixed_device_spawns:
				if str(spawn.get("id", "")) == target_id:
					return spawn.get("position", fallback)
	return fallback


func _threat_requested_position(target_id: String, fallback: Vector2) -> Vector2:
	if _blueprint == null:
		return fallback
	for spawn in _blueprint.threat_spawns:
		if str(spawn.get("id", "")) != target_id:
			continue
		return spawn.get("position", fallback)
	return fallback

func _rebuild_world() -> void:
	# Authored map nodes may be added beside this runtime layer in DiveScene.
	# Rebuilding a campaign is only allowed to replace transient presentation and
	# gameplay nodes, never a scene-authored child.
	_clear_runtime_dynamic()
	containers.clear()
	world_pickups.clear()
	threats.clear()
	persistent_interactables.clear()
	rescue_survivors.clear()
	lost_backpacks.clear()
	dropped_loot_piles.clear()
	exit_line = null
	_last_stream_chunk = Vector2i(-9999, -9999)
	_last_stream_radius = Vector2i(-1, -1)
	_collision_segments_by_chunk.clear()
	_structure_collision_segments_by_id.clear()
	_loaded_collision_chunks.clear()
	_collision_chunks_root = null
	_collision_partition_active = false
	if not _snapshot_analysis_mode:
		_build_source_visual_layers()
		_build_source_structure_roots()
	_build_navigation_from_source()
	if not _snapshot_analysis_mode:
		_build_authored_visual_prefabs()
	_start_position = _resolved_start_position()
	if not is_world_position_navigable(_start_position):
		push_error("Entry Point sceny mapy nie leży na przechodniej komórce nawigacji.")
	_build_interactables()

func _build_source_visual_layers() -> void:
	var visual_layers := MapSceneCompilerScript.new().create_visual_layers()
	if visual_layers == null:
		push_error("Scena mapy nie zawiera warstwy VisualLayers.")
		return
	visual_layers.name = "VisualLayers"
	_runtime_add_child(visual_layers)


func _build_source_structure_roots() -> void:
	var structure_roots := MapSceneCompilerScript.new().create_structure_roots()
	if structure_roots == null:
		push_error("Scena mapy nie zawiera kontenera StructureRoots.")
		return
	structure_roots.name = "StructureRoots"
	_runtime_add_child(structure_roots)
	_structure_roots_container = structure_roots
	_structure_roots_by_id.clear()
	for child in structure_roots.get_children():
		if not child is Node2D:
			continue
		var structure_id := str(child.get_meta("structure_id", ""))
		if structure_id.is_empty() or _structure_roots_by_id.has(structure_id):
			push_error("StructureRoots zawiera niepoprawne lub powtórzone structure_id.")
			continue
		_structure_roots_by_id[structure_id] = child

func _build_authored_visual_prefabs() -> void:
	if _blueprint == null:
		return
	for record in _blueprint.regions:
		_instance_static_authored_visual(record, -4)
	for record in _blueprint.landmarks:
		_instance_static_authored_visual(record, 1)
	for record in _blueprint.current_zones:
		_instance_static_authored_visual(record, 1)
	for record in _blueprint.decoration_spawns:
		if str(record.get("authoring_kind", "")) == "exit_line":
			continue
		_instance_static_authored_visual(record, 2)
	for record in _blueprint.obstacle_spawns:
		_instance_static_authored_visual(record, 3)


func _instance_static_authored_visual(record: Dictionary, layer_z_index: int) -> void:
	if not _record_has_authored_visual(record):
		return
	var anchor := Node2D.new()
	anchor.name = "%sVisual" % str(record.get("id", "MapVisual")).to_pascal_case()
	anchor.position = record.get("position", Vector2.ZERO)
	anchor.z_index = layer_z_index
	_runtime_add_child(anchor)
	if not _attach_authored_visual(anchor, record):
		anchor.get_parent().remove_child(anchor)
		anchor.free()
		return
	_static_authored_visual_bindings.append({"anchor": anchor, "record": record})


func _attach_authored_visual(
	target: Node2D,
	record: Dictionary,
	object_rotation_already_applied: bool = false
) -> bool:
	if target == null or _snapshot_analysis_mode:
		return false
	var scene_path := _resolved_visual_scene_path(record)
	if scene_path.is_empty():
		return false
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		push_error("Nie można załadować prefabu wizualnego %s." % scene_path)
		return false
	var candidate := packed.instantiate()
	if not (candidate is Node2D):
		if candidate != null:
			candidate.free()
		push_error("Prefab wizualny %s musi mieć root Node2D." % scene_path)
		return false
	_disable_visual_collisions(candidate)

	# Zachowujemy tę samą kolejność transformacji co w scenie autorskiej:
	# najpierw obrót/skala obiektu mapy, potem lokalny offset i transformacja
	# przypisanego prefabu. Dzięki temu podgląd edytora i runtime są zgodne.
	var object_wrapper := Node2D.new()
	object_wrapper.name = "AuthoredMapVisual"
	object_wrapper.set_meta(AUTHORED_VISUAL_META, true)
	object_wrapper.set_meta(AUTHORED_VISUAL_SCENE_PATH_META, scene_path)
	object_wrapper.rotation = (
		0.0
		if object_rotation_already_applied
		else float(record.get("visual_object_rotation", 0.0))
	)
	object_wrapper.scale = record.get("visual_object_scale", Vector2.ONE)
	object_wrapper.skew = float(record.get("visual_object_skew", 0.0))
	target.add_child(object_wrapper)

	var visual_wrapper := Node2D.new()
	visual_wrapper.name = "VisualTransform"
	visual_wrapper.position = record.get("visual_offset", Vector2.ZERO)
	visual_wrapper.rotation = float(record.get("visual_rotation", 0.0))
	visual_wrapper.scale = record.get("visual_scale", Vector2.ONE)
	visual_wrapper.z_index = int(record.get("visual_z_index", 0))
	object_wrapper.add_child(visual_wrapper)
	visual_wrapper.add_child(candidate)
	if target.has_method("set_authored_visual_override"):
		target.call("set_authored_visual_override", true)
	return true


func _record_has_authored_visual(record: Dictionary) -> bool:
	return not str(record.get("visual_scene_path", record.get("scene_path", ""))).is_empty()


func _resolved_visual_scene_path(record: Dictionary) -> String:
	if _graphics_quality == "high":
		var high_path := str(record.get("visual_scene_high_path", "")).strip_edges()
		if not high_path.is_empty():
			return high_path
	if _graphics_quality in ["medium", "high"]:
		var medium_path := str(record.get("visual_scene_medium_path", "")).strip_edges()
		if not medium_path.is_empty():
			return medium_path
	return str(record.get("visual_scene_path", record.get("scene_path", ""))).strip_edges()


func _refresh_static_authored_visuals() -> void:
	for binding in _static_authored_visual_bindings:
		var anchor := binding.get("anchor") as Node2D
		if anchor == null or not is_instance_valid(anchor):
			continue
		var record: Dictionary = binding.get("record", {})
		var desired_path := _resolved_visual_scene_path(record)
		var current_wrapper: Node2D
		for child in anchor.get_children():
			if child is Node2D and child.has_meta(AUTHORED_VISUAL_META):
				current_wrapper = child as Node2D
				break
		var current_path := (
			str(current_wrapper.get_meta(AUTHORED_VISUAL_SCENE_PATH_META, ""))
			if current_wrapper != null
			else ""
		)
		if current_path == desired_path:
			continue
		if desired_path.is_empty() or not _attach_authored_visual(anchor, record):
			continue
		var replacement_wrapper: Node2D
		for child in anchor.get_children():
			if (
				child is Node2D
				and child != current_wrapper
				and child.has_meta(AUTHORED_VISUAL_META)
				and str(child.get_meta(AUTHORED_VISUAL_SCENE_PATH_META, "")) == desired_path
			):
				replacement_wrapper = child as Node2D
				break
		if current_wrapper != null and is_instance_valid(current_wrapper):
			anchor.remove_child(current_wrapper)
			current_wrapper.free()
		if replacement_wrapper != null:
			replacement_wrapper.name = "AuthoredMapVisual"


func _disable_visual_collisions(root_node: Node) -> void:
	var nodes: Array[Node] = []
	nodes.append(root_node)
	nodes.append_array(root_node.find_children("*", "", true, false))
	for node in nodes:
		if node is CollisionObject2D:
			var collision_object := node as CollisionObject2D
			collision_object.collision_layer = 0
			collision_object.collision_mask = 0
		if node is Area2D:
			var area := node as Area2D
			area.monitoring = false
			area.monitorable = false
		elif node is CollisionShape2D:
			(node as CollisionShape2D).disabled = true
		elif node is CollisionPolygon2D:
			(node as CollisionPolygon2D).disabled = true


func _presentation_record(authoring_kind: String) -> Dictionary:
	if _blueprint == null:
		return {}
	for record in _blueprint.decoration_spawns:
		if str(record.get("authoring_kind", "")) == authoring_kind:
			return record
	return {}


func _uses_main_entry() -> bool:
	return _blueprint != null and active_sector_id == _blueprint.entry_landmark_id


func _active_entry_buoy() -> Dictionary:
	if _blueprint == null or _world_state == null or _uses_main_entry():
		return {}
	for spawn in _blueprint.buoy_spawns:
		if str(spawn.get("entry_landmark_id", "")) != active_sector_id:
			continue
		var buoy_id := str(spawn.get("id", ""))
		if not buoy_id.is_empty() and _world_state.placed_buoys.has(buoy_id):
			return spawn
	return {}


func _resolved_start_position() -> Vector2:
	if _blueprint == null:
		return Vector2.ZERO
	if _uses_main_entry():
		return _blueprint.entry_position
	var active_buoy := _active_entry_buoy()
	if active_buoy.is_empty():
		return _blueprint.entry_position
	return nearest_navigable_position(
		active_buoy.get("position", _blueprint.entry_position),
		NavigationSnapshotScript.DEFAULT_DIVER_CLEARANCE
	)


func _build_navigation_from_source() -> void:
	_grid_width = 0
	_grid_height = 0
	_cell_scale = Vector2.ONE
	_nav_cells = PackedByteArray()
	var base_raster: Dictionary = MapSceneCompilerScript.new().navigation_base_raster()
	var base_errors: PackedStringArray = base_raster.get("errors", PackedStringArray())
	if not base_errors.is_empty():
		for base_error in base_errors:
			push_error("Nie udało się odczytać scenowego makroterenu: %s" % base_error)
		return
	var obstacle_spawns: Array = _blueprint.obstacle_spawns if _blueprint != null else []
	var partition_digest := str(base_raster.get("partition_digest", ""))
	var navigation_cache_key := str(_blueprint.map_gameplay_signature) if _blueprint != null else ""
	if not partition_digest.is_empty():
		navigation_cache_key = "%s|partition=%s" % [navigation_cache_key, partition_digest]
	var raster: Dictionary = MapNavigationRasterScript.build_from_cells_cached(
		navigation_cache_key,
		base_raster.get("cells", PackedByteArray()),
		int(base_raster.get("width", 0)),
		int(base_raster.get("height", 0)),
		world_size(),
		obstacle_spawns,
		_blueprint.chunk_size if _blueprint != null else 512,
		not _snapshot_analysis_mode,
		base_raster.get("solid_owner_cells", PackedInt32Array()),
		base_raster.get("owner_ids", PackedStringArray())
	)
	var raster_errors: PackedStringArray = raster.get("errors", PackedStringArray())
	for raster_error in raster_errors:
		push_error("Nie udało się zbudować nawigacji mapy: %s" % raster_error)
	if not raster_errors.is_empty():
		return
	_grid_width = int(raster.get("width", 0))
	_grid_height = int(raster.get("height", 0))
	_cell_scale = raster.get("cell_scale", Vector2.ONE)
	var compiled_cells: PackedByteArray = raster.get("cells", PackedByteArray())
	_nav_cells = compiled_cells.duplicate()
	if _snapshot_analysis_mode:
		_collision_segments_by_chunk.clear()
		_structure_collision_segments_by_id.clear()
		_collision_segment_count = 0
	else:
		_collision_partition_active = not partition_digest.is_empty()
		var full_segments: PackedVector2Array = raster.get(
			"boundary_segments",
			PackedVector2Array()
		)
		_collision_segment_count = full_segments.size() / 2
		if _collision_partition_active:
			_collision_segments_by_chunk = (
				raster.get("world_segments_by_chunk", {}) as Dictionary
			).duplicate(true)
			_structure_collision_segments_by_id = (
				raster.get("structure_segments_by_id", {}) as Dictionary
			).duplicate(true)
		else:
			_collision_segments_by_chunk = (
				raster.get("boundary_segments_by_chunk", {}) as Dictionary
			).duplicate(true)
			_structure_collision_segments_by_id.clear()
		_validate_collision_partition_count(full_segments)
		_build_collision_segments(
			PackedVector2Array() if _collision_partition_active else full_segments,
			not _collision_partition_active
		)
		_configure_structure_collisions()


func _build_collision_segments(
	cached_segments: PackedVector2Array = PackedVector2Array(),
	allow_full_fallback: bool = true
) -> void:
	var segments := cached_segments.duplicate()
	if segments.is_empty() and allow_full_fallback:
		for y in range(_grid_height):
			for x in range(_grid_width):
				if not _is_open_cell(x, y):
					continue
				var top_left := Vector2(x * _cell_scale.x, y * _cell_scale.y)
				var top_right := top_left + Vector2(_cell_scale.x, 0)
				var bottom_left := top_left + Vector2(0, _cell_scale.y)
				var bottom_right := top_left + _cell_scale
				if not _is_open_cell(x, y - 1):
					segments.append(top_left)
					segments.append(top_right)
				if not _is_open_cell(x + 1, y):
					segments.append(top_right)
					segments.append(bottom_right)
				if not _is_open_cell(x, y + 1):
					segments.append(bottom_right)
					segments.append(bottom_left)
				if not _is_open_cell(x - 1, y):
					segments.append(bottom_left)
					segments.append(top_left)
	_collision_chunks_root = Node2D.new()
	_collision_chunks_root.name = "WorldMaskCollision"
	_runtime_add_child(_collision_chunks_root)


func _validate_collision_partition_count(full_segments: PackedVector2Array) -> void:
	if not _collision_partition_active:
		return
	var partition_segment_count := 0
	for chunk_segments_value in _collision_segments_by_chunk.values():
		if chunk_segments_value is PackedVector2Array:
			partition_segment_count += (chunk_segments_value as PackedVector2Array).size() / 2
	for structure_segments_value in _structure_collision_segments_by_id.values():
		if structure_segments_value is PackedVector2Array:
			partition_segment_count += (structure_segments_value as PackedVector2Array).size() / 2
	if partition_segment_count != full_segments.size() / 2:
		push_error("Partycja kolizji runtime nie jest pełną unią segmentów L05.")


func _configure_structure_collisions() -> void:
	if not _collision_partition_active:
		return
	for structure_id_value in _structure_roots_by_id.keys():
		var structure_id := str(structure_id_value)
		var root := _structure_roots_by_id[structure_id] as Node2D
		if root == null:
			continue
		var static_collision := root.get_node_or_null("StaticCollision") as StaticBody2D
		var collision_shape := (
			static_collision.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if static_collision != null
			else null
		)
		if (
			static_collision == null
			or collision_shape == null
			or not collision_shape.shape is ConcavePolygonShape2D
		):
			push_error("Struktura %s nie zawiera lokalnego ConcavePolygonShape2D." % structure_id)
			continue
		var actual_local_segments := (
			collision_shape.shape as ConcavePolygonShape2D
		).segments
		var expected_global_segments: PackedVector2Array = (
			_structure_collision_segments_by_id.get(
				structure_id,
				PackedVector2Array()
			)
		)
		var expected_local_segments := PackedVector2Array()
		for point in expected_global_segments:
			expected_local_segments.append(root.to_local(to_global(point)))
		if not _segment_sets_equal(actual_local_segments, expected_local_segments):
			push_error("Lokalny kolider struktury %s nie odpowiada partycji L05." % structure_id)
		TerrainOcclusionScript.attach_to(static_collision, actual_local_segments)
	for structure_id_value in _structure_collision_segments_by_id.keys():
		if not _structure_roots_by_id.has(structure_id_value):
			push_error("Partycja L05 wskazuje brakujący korzeń struktury %s." % str(structure_id_value))


func _segment_sets_equal(left: PackedVector2Array, right: PackedVector2Array) -> bool:
	if left.size() != right.size() or left.size() % 2 != 0:
		return false
	var counts: Dictionary = {}
	for index in range(0, left.size(), 2):
		var key := _segment_key(left[index], left[index + 1])
		counts[key] = int(counts.get(key, 0)) + 1
	for index in range(0, right.size(), 2):
		var key := _segment_key(right[index], right[index + 1])
		if not counts.has(key):
			return false
		var remaining := int(counts[key]) - 1
		if remaining <= 0:
			counts.erase(key)
		else:
			counts[key] = remaining
	return counts.is_empty()


func _segment_key(from: Vector2, to: Vector2) -> Vector4:
	var snapped_from := from.snapped(Vector2(0.001, 0.001))
	var snapped_to := to.snapped(Vector2(0.001, 0.001))
	if (
		snapped_from.x < snapped_to.x
		or (is_equal_approx(snapped_from.x, snapped_to.x) and snapped_from.y <= snapped_to.y)
	):
		return Vector4(snapped_from.x, snapped_from.y, snapped_to.x, snapped_to.y)
	return Vector4(snapped_to.x, snapped_to.y, snapped_from.x, snapped_from.y)


func _sync_collision_chunks(chunk_keys: Array[String]) -> void:
	if _collision_chunks_root == null:
		return
	var requested: Dictionary = {}
	for key in chunk_keys:
		requested[key] = true
	for loaded_key in _loaded_collision_chunks.keys():
		if requested.has(loaded_key):
			continue
		var stale := _loaded_collision_chunks[loaded_key] as Node
		_loaded_collision_chunks.erase(loaded_key)
		if stale != null and is_instance_valid(stale):
			stale.queue_free()
	for key in chunk_keys:
		if _loaded_collision_chunks.has(key) or not _collision_segments_by_chunk.has(key):
			continue
		var chunk_segments: PackedVector2Array = _collision_segments_by_chunk[key]
		if chunk_segments.is_empty():
			continue
		var body := StaticBody2D.new()
		body.name = "Chunk_%s" % key.replace(":", "_")
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape2D.new()
		var shape := ConcavePolygonShape2D.new()
		shape.segments = chunk_segments
		collision.shape = shape
		body.add_child(collision)
		TerrainOcclusionScript.attach_to(body, chunk_segments)
		_collision_chunks_root.add_child(body)
		_loaded_collision_chunks[key] = body


func loaded_collision_chunk_keys() -> Array[String]:
	var result: Array[String] = []
	for key in _loaded_collision_chunks.keys():
		result.append(str(key))
	result.sort()
	return result

func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / _cell_scale.x), floori(world_position.y / _cell_scale.y))

func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * _cell_scale.x, (cell.y + 0.5) * _cell_scale.y)

func _is_open_cell(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= _grid_width or y >= _grid_height:
		return false
	return _nav_cells[y * _grid_width + x] == 1

func _nearest_open_world_position(candidate: Vector2, search_radius_cells: int = -1, clearance_world: float = 0.0) -> Vector2:
	var requested_cell := _world_to_cell(candidate)
	var center := Vector2i(
		clampi(requested_cell.x, 0, _grid_width - 1),
		clampi(requested_cell.y, 0, _grid_height - 1)
	)
	var clearance_cells := ceili(maxf(clearance_world, 0.0) / maxf(minf(_cell_scale.x, _cell_scale.y), 1.0))
	if _is_open_cell_with_clearance(center.x, center.y, clearance_cells):
		return candidate
	var maximum_radius := search_radius_cells if search_radius_cells >= 0 else maxi(_grid_width, _grid_height)
	for radius in range(1, maximum_radius + 1):
		var nearest := Vector2.ZERO
		var nearest_distance := INF
		var left := center.x - radius
		var right := center.x + radius
		var top := center.y - radius
		var bottom := center.y + radius
		for x in range(left, right + 1):
			for y in [top, bottom]:
				if not _is_open_cell_with_clearance(x, y, clearance_cells):
					continue
				var position := _cell_center(Vector2i(x, y))
				var distance := position.distance_squared_to(candidate)
				if distance < nearest_distance:
					nearest = position
					nearest_distance = distance
		for y in range(top + 1, bottom):
			for x in [left, right]:
				if not _is_open_cell_with_clearance(x, y, clearance_cells):
					continue
				var position := _cell_center(Vector2i(x, y))
				var distance := position.distance_squared_to(candidate)
				if distance < nearest_distance:
					nearest = position
					nearest_distance = distance
		if nearest_distance < INF:
			return nearest
	return world_size() * 0.5

func _is_open_cell_with_clearance(x: int, y: int, clearance_cells: int) -> bool:
	if not _is_open_cell(x, y):
		return false
	for check_y in range(y - clearance_cells, y + clearance_cells + 1):
		for check_x in range(x - clearance_cells, x + clearance_cells + 1):
			if not _is_open_cell(check_x, check_y):
				return false
	return true

func _build_interactables() -> void:
	var uses_main_entry := _uses_main_entry()
	var active_buoy := _active_entry_buoy()
	exit_line = ExitLineScript.new()
	exit_line.name = "ExitLine"
	exit_line.configure(maxi(int(_expedition_setup.base_support_level), 1) if _expedition_setup != null else 1)
	exit_line.position = (
		_blueprint.exit_position
		if uses_main_entry
		else active_buoy.get("position", _start_position)
	)
	exit_line.z_index = 5
	_runtime_add_child(exit_line)
	var exit_presentation := _presentation_record("exit_line") if uses_main_entry else active_buoy
	var exit_stable_id := (
		"exit_line"
		if uses_main_entry
		else str(active_buoy.get("id", active_sector_id))
	)
	_configure_interactable_presentation(exit_line, exit_presentation, exit_stable_id)
	if uses_main_entry:
		_attach_authored_visual(exit_line, exit_presentation)

	for loot in _blueprint.loot_spawns:
		if str(loot.get("spawn_kind", "container")) == "pickup":
			_build_world_pickup(loot)
			continue
		var id := str(loot.get("id", "loot"))
		var has_disease_hazard := (
			not str(loot.get("disease_id", "")).is_empty()
			and int(loot.get("disease_exposure_pressure", 0)) > 0
			and (_expedition_setup == null or not bool(_expedition_setup.tutorial_mode))
		)
		var container: DiveLootContainer = (
			DiseaseHazardContainerScript.new()
			if has_disease_hazard
			else ContainerScript.new()
		)
		container.name = id.to_pascal_case()
		var requested_position: Vector2 = loot.get("position", Vector2.ZERO)
		container.position = requested_position
		container.z_index = 5
		var scaled_loot := _scaled_initial_loot(
			loot.get("contents", {}),
			id,
			int(loot.get("mandatory_order", -1)),
			bool(loot.get("difficulty_scaled_contents", true))
		)
		if has_disease_hazard:
			(container as DiveDiseaseHazardContainer).configure_hazard(
				id,
				str(loot.get("display_name", "Zasobnik")),
				scaled_loot,
				str(loot.get("disease_id", "")),
				int(loot.get("disease_exposure_pressure", 0)),
				str(loot.get("disease_source_kind", "dive")),
				str(loot.get("disease_source_id", id)),
				str(loot.get("required_tool", "")),
				str(loot.get("interaction_action", "open")),
				float(loot.get("interaction_seconds", 1.15))
			)
		else:
			container.configure(
				id,
				str(loot.get("display_name", "Zasobnik")),
				scaled_loot,
				int(loot.get("mandatory_order", -1)),
				str(loot.get("required_tool", "")),
				str(loot.get("interaction_action", "open")),
				float(loot.get("interaction_seconds", 1.15))
			)
		_runtime_add_child(container)
		_configure_interactable_presentation(container, loot, id)
		_attach_authored_visual(container, loot)
		containers.append(container)

	_build_lost_backpacks()
	_build_dropped_loot_piles()
	_build_buoy_anchors()
	_build_shortcut_gates()
	_build_fixed_devices()
	_build_heavy_objects()
	_build_rescue_survivors()

	for threat_spawn in _blueprint.threat_spawns:
		var definition_id := str(threat_spawn.get("definition_id", ""))
		var definition_path := "res://data/threats/%s.tres" % definition_id
		var threat_definition = ResourceLoader.load(definition_path) if ResourceLoader.exists(definition_path) else null
		if threat_definition == null:
			continue
		var threat = ThreatScript.new()
		var threat_id := str(threat_spawn.get("id", definition_id))
		threat.configure(threat_id, threat_definition)
		threat.position = threat_spawn.get("position", Vector2.ZERO)
		_runtime_add_child(threat)
		_attach_authored_visual(threat, threat_spawn)
		threats.append(threat)

func _build_world_pickup(spawn: Dictionary) -> void:
	var pickup_id := str(spawn.get("id", ""))
	if pickup_id.is_empty() or _world_state.collected_items.has(pickup_id):
		return
	var contents: Dictionary = spawn.get("contents", {})
	if contents.size() != 1:
		push_error("Wolnostojąca znajdźka %s musi zawierać dokładnie jedną sztukę jednego zasobu." % pickup_id)
		return
	var resource_id := str(contents.keys()[0])
	if int(contents.get(resource_id, 0)) != 1:
		push_error("Wolnostojąca znajdźka %s musi reprezentować dokładnie jedną sztukę." % pickup_id)
		return
	var item_path := "res://data/items/%s.tres" % resource_id
	var item_definition = ResourceLoader.load(item_path) if ResourceLoader.exists(item_path) else null
	if item_definition == null:
		push_error("Brak definicji wolnostojącej znajdźki: %s." % resource_id)
		return
	if item_definition.world_pickup_texture == null and not _record_has_authored_visual(spawn):
		push_error("Znajdźka %s wymaga grafiki w definicji albo prefabu wizualnego na mapie." % resource_id)
		return
	var pickup = WorldPickupScript.new()
	pickup.name = "Pickup%s" % pickup_id.to_pascal_case()
	pickup.configure(
		pickup_id,
		resource_id,
		str(spawn.get("display_name", item_definition.display_name)),
		item_definition.world_pickup_texture,
		false
	)
	pickup.position = spawn.get("position", Vector2.ZERO)
	pickup.z_index = 6
	_runtime_add_child(pickup)
	_configure_interactable_presentation(pickup, spawn, pickup_id)
	_attach_authored_visual(pickup, spawn)
	world_pickups.append(pickup)

func _build_lost_backpacks() -> void:
	for backpack_id in _world_state.lost_backpacks.keys():
		var record: Dictionary = _world_state.lost_backpacks[backpack_id]
		if bool(record.get("recovered", false)):
			continue
		var backpack = LostBackpackScript.new()
		backpack.name = "LostBackpack%s" % str(backpack_id).to_pascal_case()
		backpack.configure_backpack(str(backpack_id), record)
		var requested_position: Vector2 = record.get("world_position", Vector2.ZERO)
		if requested_position == Vector2.ZERO:
			var landmark: Dictionary = _blueprint.get_landmark(str(record.get("landmark_id", "")))
			requested_position = landmark.get("position", _start_position)
		backpack.position = _nearest_open_world_position(requested_position, -1, 28.0)
		backpack.z_index = 6
		_runtime_add_child(backpack)
		_configure_interactable_presentation(backpack, record, str(backpack_id))
		containers.append(backpack)
		lost_backpacks.append(backpack)

func _build_dropped_loot_piles() -> void:
	for pile_id in _world_state.dropped_loot_piles.keys():
		var record_value = _world_state.dropped_loot_piles[pile_id]
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value.duplicate(true)
		var items := _normalized_loot(record.get("items", {}))
		if bool(record.get("recovered", false)) or items.is_empty():
			continue
		var id := str(pile_id)
		if id.is_empty():
			continue
		record["persistence_id"] = id
		record["items"] = items
		var requested_position: Vector2 = record.get("world_position", Vector2.ZERO)
		if requested_position == Vector2.ZERO:
			var landmark: Dictionary = _blueprint.get_landmark(str(record.get("landmark_id", "")))
			requested_position = landmark.get("position", _start_position)
		var resolved_position := nearest_navigable_position(requested_position, 28.0)
		if str(record.get("landmark_id", "")).is_empty():
			record["landmark_id"] = landmark_id_at(resolved_position)
		var pile = DroppedLootScript.new()
		pile.name = "DroppedLoot%s" % id.to_pascal_case()
		pile.configure_dropped_loot(id, record, false)
		pile.position = resolved_position
		pile.z_index = 6
		_runtime_add_child(pile)
		_configure_interactable_presentation(pile, record, id)
		containers.append(pile)
		dropped_loot_piles.append(pile)

func _build_buoy_anchors() -> void:
	var active_buoy := _active_entry_buoy()
	var active_buoy_id := str(active_buoy.get("id", ""))
	for spawn in _blueprint.buoy_spawns:
		var buoy_id := str(spawn.get("id", ""))
		if buoy_id.is_empty():
			continue
		# Przy wejściu z boi jej fizyczną prezentacją i interakcją powrotną jest
		# ExitLine. Nie nakładaj w tym samym punkcie ukończonego ReturnBuoy.
		if not active_buoy_id.is_empty() and buoy_id == active_buoy_id:
			continue
		var is_placed: bool = _world_state.placed_buoys.has(buoy_id)
		if not is_placed and (_expedition_setup == null or not bool(_expedition_setup.can_place_buoys)):
			continue
		var buoy = PersistentInteractableScript.new()
		buoy.name = "Buoy%s" % buoy_id.replace("-", "")
		buoy.configure(
			PersistentInteractableScript.Kind.BUOY,
			buoy_id,
			str(spawn.get("display_name", buoy_id)),
			is_placed,
			str(spawn.get("required_tool", "")),
			str(spawn.get("interaction_action", "deploy")),
			float(spawn.get("interaction_seconds", 1.25))
		)
		buoy.position = spawn.get("position", Vector2.ZERO)
		buoy.z_index = 6
		_runtime_add_child(buoy)
		_configure_interactable_presentation(buoy, spawn, buoy_id)
		_attach_authored_visual(buoy, spawn)
		persistent_interactables.append(buoy)

func _build_shortcut_gates() -> void:
	for spawn in _blueprint.shortcut_spawns:
		var shortcut_id := str(spawn.get("id", ""))
		if shortcut_id.is_empty():
			continue
		var gate = PersistentInteractableScript.new()
		gate.name = "Shortcut%s" % shortcut_id.replace("-", "")
		gate.configure(
			PersistentInteractableScript.Kind.SHORTCUT,
			shortcut_id,
			str(spawn.get("display_name", shortcut_id)),
			_world_state.opened_shortcuts.has(shortcut_id),
			str(spawn.get("required_tool", "crowbar")),
			str(spawn.get("interaction_action", "pry")),
			float(spawn.get("interaction_seconds", 2.1)),
			maxf(float(spawn.get("width", 120.0)), 150.0)
		)
		gate.position = spawn.get("position", Vector2.ZERO)
		gate.rotation = float(spawn.get("rotation", 0.0))
		gate.z_index = 6
		_runtime_add_child(gate)
		_configure_interactable_presentation(gate, spawn, shortcut_id)
		_attach_authored_visual(gate, spawn, true)
		persistent_interactables.append(gate)

func _build_heavy_objects() -> void:
	for definition in _blueprint.heavy_object_spawns:
		var object_id := str(definition.get("id", ""))
		if _world_state.recovered_heavy_objects.has(object_id):
			continue
		var heavy_object = PersistentInteractableScript.new()
		heavy_object.name = "Heavy%s" % object_id.to_pascal_case()
		heavy_object.configure(
			PersistentInteractableScript.Kind.HEAVY_OBJECT,
			object_id,
			str(definition.get("display_name", "Ciężki obiekt")),
			_world_state.marked_heavy_objects.has(object_id),
			str(definition.get("required_tool", "lift_bag")),
			str(definition.get("interaction_action", "mark")),
			float(definition.get("interaction_seconds", 1.6))
		)
		heavy_object.position = definition.get("position", Vector2.ZERO)
		heavy_object.z_index = 6
		_runtime_add_child(heavy_object)
		_configure_interactable_presentation(heavy_object, definition, object_id)
		_attach_authored_visual(heavy_object, definition)
		persistent_interactables.append(heavy_object)

func _build_fixed_devices() -> void:
	for definition in _blueprint.fixed_device_spawns:
		var device_id := str(definition.get("id", ""))
		if device_id.is_empty():
			continue
		var expedition_day := int(_expedition_setup.day) if _expedition_setup != null else 1
		if expedition_day < int(definition.get("available_from_day", 1)):
			continue
		var device = PersistentInteractableScript.new()
		device.name = "FixedDevice%s" % device_id.to_pascal_case()
		device.configure(
			PersistentInteractableScript.Kind.FIXED_DEVICE,
			device_id,
			str(definition.get("display_name", device_id)),
			_world_state.activated_fixed_devices.has(device_id),
			str(definition.get("required_tool", "")),
			str(definition.get("interaction_action", "activate")),
			float(definition.get("interaction_seconds", 1.5))
		)
		var device_parent: Node = _runtime_root()
		if str(definition.get("position_space", "world")) == "structure_local":
			var structure_id := str(definition.get("structure_id", ""))
			var structure_root := _structure_roots_by_id.get(structure_id, null) as Node2D
			var interactives_root := (
				structure_root.get_node_or_null("Interactives") as Node2D
				if structure_root != null
				else null
			)
			if interactives_root == null:
				push_error("Nie można zamontować urządzenia %s w strukturze %s." % [device_id, structure_id])
				device.free()
				continue
			device_parent = interactives_root
			device.position = definition.get("local_position", Vector2.ZERO)
		else:
			device.position = definition.get("position", Vector2.ZERO)
		device.z_index = 6
		device_parent.add_child(device)
		_configure_interactable_presentation(device, definition, device_id)
		_attach_authored_visual(device, definition)
		persistent_interactables.append(device)

func _build_rescue_survivors() -> void:
	for spawn in _blueprint.rescue_spawns:
		var encounter_id := str(spawn.get("id", ""))
		var outcome: Dictionary = _world_state.rescued_or_dead_survivors.get(encounter_id, {})
		var outcome_status := str(outcome.get("status", ""))
		if outcome_status in ["rescued", "dead"]:
			continue
		var definition_id := str(spawn.get("definition_id", ""))
		var definition_path := "res://data/survivors/%s.tres" % definition_id
		var definition = ResourceLoader.load(definition_path) if ResourceLoader.exists(definition_path) else null
		if definition == null:
			continue
		var rescue_survivor = RescueSurvivorScript.new()
		rescue_survivor.name = "Rescue%s" % encounter_id.to_pascal_case()
		rescue_survivor.configure(encounter_id, definition)
		rescue_survivor.position = spawn.get("position", Vector2.ZERO)
		rescue_survivor.z_index = 7
		_runtime_add_child(rescue_survivor)
		_configure_interactable_presentation(rescue_survivor, spawn, encounter_id)
		_attach_authored_visual(rescue_survivor, spawn)
		rescue_survivors.append(rescue_survivor)

func _scaled_initial_loot(
	contents: Dictionary,
	stable_source_id: String = "runtime_probe",
	mandatory_order: int = -1,
	difficulty_scaled_contents: bool = true
) -> Dictionary:
	var multiplier := 1.0
	# Oznaczone skrzynie tutoriala są kontraktem nauki i zawsze zachowują
	# autorską zawartość. Jawne nagrody ryzyko/nagroda wyłącza z tego
	# przeliczenia pole difficulty_scaled_contents.
	if difficulty_scaled_contents and mandatory_order < 0 and _expedition_setup != null:
		multiplier = maxf(float(_expedition_setup.difficulty_modifiers.get("loot_density_multiplier", 1.0)), 0.01)
	var campaign_seed := int(_world_state.generated_seed) if _world_state != null else int(_blueprint.campaign_seed) if _blueprint != null else 1
	var result: Dictionary = {}
	for resource_id in contents.keys():
		var amount := int(contents[resource_id])
		var id := str(resource_id)
		var scaled_amount := DifficultyMathScript.scale_loot_amount(
			amount,
			multiplier,
			campaign_seed,
			stable_source_id,
			id,
			1
		)
		if scaled_amount > 0:
			result[id] = scaled_amount
	return result
