extends RefCounted


const MOTION_DELTA := 1.0 / 60.0
const SPEED_MULTIPLIER := 1.5
const STREAM_EXTENT := Vector2(900.0, 600.0)
const TARGET_DISTANCE := 8.0
const STAGNANT_TICKS := 90
const MAX_TOTAL_MOTION_TICKS := 36_000
const PHYSICS_SYNC_STRIDE := 12
const PATH_WAYPOINT_STRIDE_CELLS := 4
const ROUTE_DESIRED_SPEED := 150.0
const GATE_APPROACH_DISTANCES := [120.0, 140.0, 160.0, 200.0, 240.0, 280.0]
const CURRENT_APPROACH_MARGIN := 120.0
const REAL_DIVER_ROUTE_CLEARANCE := 52.5

const JUNCTION_J7_ID := "junction_j7"
const ARCHIVE_TERMINAL_ID := "archive_terminal"
const R3_DIAGNOSTIC_ID := "r3_diagnostic_panel"
const R3_GENERATOR_ID := "r3_generator"
const C4_SWITCHBOARD_ID := "c4_switchboard"
const C4_SPLITTER_ID := "c4_splitter_mount"
const TUTORIAL_GATE_ID := "SC-01"
const CENTRAL_RETURN_GATE_ID := "shortcut_central_return"
const C4_SERVICE_GATE_ID := "shortcut_c4_service"

var _tree: SceneTree
var _map: Node2D
var _diver: CharacterBody2D
var _errors := PackedStringArray()
var _last_loaded_keys: Array[String] = []
var _stream_fingerprints: Dictionary = {}
var _total_motion_ticks := 0
var _report := {
	"contract": "s_loop_real_diver_integration_v1",
	"fixed_delta": MOTION_DELTA,
	"movement_multiplier": SPEED_MULTIPLIER,
	"routes": [],
	"gates": [],
	"currents": [],
	"stream_windows": [],
	"stop_turn": {},
}


func run(tree: SceneTree, dive_map: Node2D, diver: CharacterBody2D) -> Dictionary:
	_tree = tree
	_map = dive_map
	_diver = diver
	_errors.clear()
	_last_loaded_keys.clear()
	_stream_fingerprints.clear()
	_total_motion_ticks = 0
	_report.routes.clear()
	_report.gates.clear()
	_report.currents.clear()
	_report.stream_windows.clear()
	_report.stop_turn = {}

	_require_public_seams()
	if not _errors.is_empty():
		return _result()

	var navigation = _navigation_snapshot()
	_assert(_navigation_is_valid(navigation), "Production navigation_snapshot must be valid for the real-Diver S-loop replay.")
	var targets := _targets_by_id(navigation)
	var mandatory_containers := _mandatory_containers(navigation)
	_assert(mandatory_containers.size() >= 2, "The public tutorial route must expose at least two ordered mandatory containers.")
	for target_id in [JUNCTION_J7_ID, ARCHIVE_TERMINAL_ID, R3_DIAGNOSTIC_ID, R3_GENERATOR_ID, C4_SWITCHBOARD_ID, C4_SPLITTER_ID]:
		_assert(targets.has(target_id), "The public navigation snapshot must expose campaign target %s." % target_id)
	if not _errors.is_empty():
		return _result()

	var start_position: Vector2 = navigation.get("start_position")
	var j7_position := _target_position(targets[JUNCTION_J7_ID])
	var archive_position := _target_position(targets[ARCHIVE_TERMINAL_ID])
	var r3_diagnostic_position := _target_position(targets[R3_DIAGNOSTIC_ID])
	var r3_generator_position := _target_position(targets[R3_GENERATOR_ID])
	var c4_switchboard_position := _target_position(targets[C4_SWITCHBOARD_ID])
	var c4_splitter_position := _target_position(targets[C4_SPLITTER_ID])

	var tutorial_gate := await _probe_and_open_gate(TUTORIAL_GATE_ID, start_position)
	if tutorial_gate.is_empty():
		return _result()
	navigation = tutorial_gate.navigation
	targets = _targets_by_id(navigation)
	var tutorial_anchors: Array[Vector2] = [start_position]
	for descriptor in mandatory_containers:
		tutorial_anchors.append(_target_position(descriptor))
	tutorial_anchors.append(tutorial_gate.sides.near)
	tutorial_anchors.append(tutorial_gate.sides.far)
	tutorial_anchors.append(j7_position)
	if not await _run_bidirectional_route(navigation, tutorial_anchors, "tutorial/J7"):
		return _result()

	var archive_current := _nearest_current_zone(navigation, archive_position)
	_assert(not archive_current.is_empty(), "Archive upper/lower replay requires a public current zone.")
	var archive_current_points := _current_route_points(archive_current)
	var archive_buoy := _target_for_kind_and_landmark(
		navigation,
		"buoy",
		str((targets[ARCHIVE_TERMINAL_ID] as Dictionary).get("landmark_id", "")),
	)
	_assert(not archive_buoy.is_empty(), "Archive lower route requires a public return-buoy descriptor.")
	if not _errors.is_empty():
		return _result()
	var archive_anchors: Array[Vector2] = [
		j7_position,
		archive_position,
		archive_current_points.upstream,
		archive_current_points.center,
		archive_current_points.downstream,
		_target_position(archive_buoy),
	]
	if not await _run_bidirectional_route(navigation, archive_anchors, "Archive upper/lower"):
		return _result()

	var central_gate := await _probe_and_open_gate(CENTRAL_RETURN_GATE_ID, r3_generator_position)
	if central_gate.is_empty():
		return _result()
	navigation = central_gate.navigation
	targets = _targets_by_id(navigation)
	var r3_anchors: Array[Vector2] = [
		_target_position(archive_buoy),
		r3_diagnostic_position,
		r3_generator_position,
		central_gate.sides.near,
		central_gate.sides.far,
		j7_position,
	]
	if not await _run_bidirectional_route(navigation, r3_anchors, "R3 and central return"):
		return _result()

	var risk_current := _nearest_distinct_current_zone(navigation, c4_switchboard_position, archive_current)
	_assert(not risk_current.is_empty(), "C4 risk route requires the second public current zone.")
	var rescue := _target_for_kind_and_landmark(
		navigation,
		"rescue",
		str((targets[C4_SWITCHBOARD_ID] as Dictionary).get("landmark_id", "")),
	)
	var c4_buoy := _target_for_kind_and_landmark(
		navigation,
		"buoy",
		str((targets[C4_SWITCHBOARD_ID] as Dictionary).get("landmark_id", "")),
	)
	_assert(not rescue.is_empty(), "C4 safe route requires the public rescue descriptor.")
	_assert(not c4_buoy.is_empty(), "C4 safe route requires the public return-buoy descriptor.")
	if not _errors.is_empty():
		return _result()
	var risk_rect: Rect2 = risk_current.get("rect", Rect2())
	var safe_anchors: Array[Vector2] = [
		r3_generator_position,
		_target_position(rescue),
		_target_position(c4_buoy),
		c4_switchboard_position,
		c4_splitter_position,
	]
	if not await _run_bidirectional_route(navigation, safe_anchors, "C4 safe", risk_rect, false):
		return _result()

	var risk_points := _current_route_points(risk_current)
	var risk_anchors: Array[Vector2] = [
		r3_generator_position,
		risk_points.upstream,
		risk_points.center,
		risk_points.downstream,
		c4_switchboard_position,
	]
	if not await _run_bidirectional_route(navigation, risk_anchors, "C4 risk", risk_rect, true):
		return _result()

	for current_zone in [archive_current, risk_current]:
		if not await _audit_current_zone(navigation, current_zone):
			return _result()

	var service_gate := await _probe_and_open_gate(C4_SERVICE_GATE_ID, c4_switchboard_position)
	if service_gate.is_empty():
		return _result()
	navigation = service_gate.navigation
	if not await _audit_stop_and_turn(navigation, service_gate.sides):
		return _result()

	targets = _targets_by_id(navigation)
	var heavy := _target_for_persistent_kind(navigation, "heavy_object")
	_assert(not heavy.is_empty(), "Salvage route requires a public heavy-object descriptor.")
	var salvage_container := _nearest_optional_container(navigation, _target_position(heavy))
	_assert(not salvage_container.is_empty(), "Salvage route requires a nearby optional container descriptor.")
	if not _errors.is_empty():
		return _result()
	var salvage_anchors: Array[Vector2] = [
		c4_splitter_position,
		_target_position(heavy),
		_target_position(salvage_container),
	]
	if not await _run_bidirectional_route(navigation, salvage_anchors, "salvage basin"):
		return _result()

	_assert(_stream_fingerprints.size() >= 2, "The replay must observe at least two different non-empty collision-stream windows.")
	_report["motion_ticks"] = _total_motion_ticks
	_report["stream_window_count"] = _stream_fingerprints.size()
	return _result()


func _require_public_seams() -> void:
	_assert(_map != null and is_instance_valid(_map), "S-loop harness requires a live production map.")
	_assert(_diver != null and is_instance_valid(_diver), "S-loop harness requires a live real Diver CharacterBody2D.")
	if _map == null or _diver == null:
		return
	for method_name in ["navigation_snapshot", "current_at", "update_streaming", "loaded_collision_chunk_keys", "open_shortcut_for_attempt"]:
		_assert(_map.has_method(method_name), "Production map is missing public seam %s." % method_name)
	for method_name in ["simulate_motion_tick", "reset_at", "stop_motion"]:
		_assert(_diver.has_method(method_name), "Production Diver is missing public seam %s." % method_name)


func _navigation_snapshot():
	# The physical body is a 105x60 capsule. Planning against its 52.5-unit
	# long-axis half extent is conservative; move_and_slide remains authoritative.
	return _map.call("navigation_snapshot", REAL_DIVER_ROUTE_CLEARANCE)


func _navigation_is_valid(navigation) -> bool:
	return navigation != null and navigation.has_method("is_valid") and bool(navigation.call("is_valid"))


func _targets_by_id(navigation) -> Dictionary:
	var result: Dictionary = {}
	for descriptor_value in navigation.call("target_descriptors"):
		if not descriptor_value is Dictionary:
			continue
		var descriptor := descriptor_value as Dictionary
		var target_id := str(descriptor.get("id", ""))
		if not target_id.is_empty():
			result[target_id] = descriptor
	return result


func _mandatory_containers(navigation) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for descriptor_value in navigation.call("target_descriptors"):
		if not descriptor_value is Dictionary:
			continue
		var descriptor := descriptor_value as Dictionary
		if str(descriptor.get("kind", "")) == "container" and bool(descriptor.get("mandatory", false)):
			result.append(descriptor)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("mandatory_order", 0)) < int(right.get("mandatory_order", 0))
	)
	return result


func _target_for_kind_and_landmark(navigation, requested_kind: String, landmark_id: String) -> Dictionary:
	for descriptor_value in navigation.call("target_descriptors"):
		if not descriptor_value is Dictionary:
			continue
		var descriptor := descriptor_value as Dictionary
		var actual_kind := str(descriptor.get("kind", ""))
		if actual_kind == "persistent_objective":
			actual_kind = str(descriptor.get("persistent_kind", ""))
		if actual_kind == requested_kind and str(descriptor.get("landmark_id", "")) == landmark_id:
			return descriptor
	return {}


func _target_for_persistent_kind(navigation, persistent_kind: String) -> Dictionary:
	for descriptor_value in navigation.call("target_descriptors"):
		if descriptor_value is Dictionary:
			var descriptor := descriptor_value as Dictionary
			if str(descriptor.get("persistent_kind", "")) == persistent_kind:
				return descriptor
	return {}


func _nearest_optional_container(navigation, anchor: Vector2) -> Dictionary:
	var result: Dictionary = {}
	var best_distance := INF
	for descriptor_value in navigation.call("target_descriptors"):
		if not descriptor_value is Dictionary:
			continue
		var descriptor := descriptor_value as Dictionary
		if str(descriptor.get("kind", "")) != "container" or bool(descriptor.get("mandatory", false)):
			continue
		var distance := anchor.distance_to(_target_position(descriptor))
		if distance < best_distance:
			best_distance = distance
			result = descriptor
	return result


func _target_position(descriptor: Dictionary) -> Vector2:
	var position_value: Variant = descriptor.get("position", Vector2.ZERO)
	return position_value as Vector2 if position_value is Vector2 else Vector2.ZERO


func _nearest_current_zone(navigation, anchor: Vector2) -> Dictionary:
	var result: Dictionary = {}
	var best_distance := INF
	for zone_value in navigation.get("current_zones"):
		if not zone_value is Dictionary:
			continue
		var zone := zone_value as Dictionary
		var rect: Rect2 = zone.get("rect", Rect2())
		var distance := anchor.distance_to(rect.get_center())
		if distance < best_distance:
			best_distance = distance
			result = zone
	return result


func _nearest_distinct_current_zone(navigation, anchor: Vector2, excluded: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var best_distance := INF
	for zone_value in navigation.get("current_zones"):
		if not zone_value is Dictionary:
			continue
		var zone := zone_value as Dictionary
		if str(zone.get("id", "")) == str(excluded.get("id", "")):
			continue
		var rect: Rect2 = zone.get("rect", Rect2())
		var distance := anchor.distance_to(rect.get_center())
		if distance < best_distance:
			best_distance = distance
			result = zone
	return result


func _current_route_points(zone: Dictionary) -> Dictionary:
	var rect: Rect2 = zone.get("rect", Rect2())
	var velocity: Vector2 = zone.get("velocity", Vector2.ZERO)
	var direction := velocity.normalized()
	var half_extent := absf(direction.x) * rect.size.x * 0.5 + absf(direction.y) * rect.size.y * 0.5
	var distance := half_extent + CURRENT_APPROACH_MARGIN
	return {
		"upstream": rect.get_center() - direction * distance,
		"center": rect.get_center(),
		"downstream": rect.get_center() + direction * distance,
	}


func _probe_and_open_gate(gate_id: String, reference_position: Vector2) -> Dictionary:
	var navigation = _navigation_snapshot()
	var gate := _gate_descriptor(navigation, gate_id)
	_assert(not gate.is_empty(), "Closed public gate descriptor %s must exist before activation." % gate_id)
	if gate.is_empty():
		return {}
	var sides := _gate_sides(navigation, gate, reference_position)
	_assert(not sides.is_empty(), "Gate %s must expose two clear public approaches." % gate_id)
	if sides.is_empty():
		return {}
	_assert(
		not bool(navigation.call("is_segment_clear", sides.near, sides.far)),
		"Gate %s must block its approach segment before public activation." % gate_id,
	)
	if not await _probe_closed_gate(navigation, gate_id, gate, sides):
		return {}
	_assert(bool(_map.call("open_shortcut_for_attempt", gate_id)), "Public activation must open gate %s." % gate_id)
	await _tree.process_frame
	await _tree.physics_frame
	await _tree.physics_frame
	var opened_navigation = _navigation_snapshot()
	_assert(
		bool(opened_navigation.call("is_segment_clear", sides.near, sides.far)),
		"Gate %s must publish a clear segment after public activation." % gate_id,
	)
	_report.gates.append({
		"id": gate_id,
		"closed_collision": true,
		"opened_publicly": true,
		"approach_distance": (sides.near as Vector2).distance_to(gate.get("position", Vector2.ZERO)),
	})
	return {"navigation": opened_navigation, "sides": sides}


func _gate_descriptor(navigation, gate_id: String) -> Dictionary:
	for descriptor_value in navigation.call("closed_gate_descriptors"):
		if descriptor_value is Dictionary and str((descriptor_value as Dictionary).get("id", "")) == gate_id:
			return descriptor_value as Dictionary
	return {}


func _gate_sides(navigation, gate: Dictionary, reference_position: Vector2) -> Dictionary:
	var transform: Transform2D = gate.get("transform", Transform2D.IDENTITY)
	var center := transform.origin
	var normal := transform.y.normalized()
	var tangent := transform.x.normalized()
	if normal.is_zero_approx() or tangent.is_zero_approx():
		return {}
	for distance_value in GATE_APPROACH_DISTANCES:
		var distance := float(distance_value)
		var side_a := center - normal * distance
		var side_b := center + normal * distance
		if not bool(navigation.call("is_position_clear", side_a)) or not bool(navigation.call("is_position_clear", side_b)):
			continue
		var near := side_a if reference_position.distance_to(side_a) <= reference_position.distance_to(side_b) else side_b
		var far := side_b if near == side_a else side_a
		var directed_normal := (far - near).normalized()
		return {
			"near": near,
			"far": far,
			"center": center,
			"normal": directed_normal,
			"tangent": tangent,
		}
	return {}


func _probe_closed_gate(navigation, gate_id: String, gate: Dictionary, sides: Dictionary) -> bool:
	await _reset_and_stream(sides.near, "closed-%s" % gate_id)
	if not _errors.is_empty():
		return false
	var center: Vector2 = gate.get("position", Vector2.ZERO)
	var normal: Vector2 = sides.normal
	var initial_side := (sides.near as Vector2 - center).dot(normal)
	var collided := false
	for tick in range(240):
		if not await _prepare_motion_tick(navigation, tick):
			return false
		var current := _current_at(_diver.global_position)
		var command := ((sides.far as Vector2) - _diver.global_position).normalized()
		var previous := _diver.global_position
		var motion := _diver.call("simulate_motion_tick", command, true, current, SPEED_MULTIPLIER, MOTION_DELTA, true) as Dictionary
		_total_motion_ticks += 1
		if not _validate_motion_tick(navigation, previous, current, motion, true):
			return false
		if bool(motion.get("collided", false)):
			collided = true
			break
		var current_side := (_diver.global_position - center).dot(normal)
		if initial_side * current_side < 0.0:
			_assert(false, "Real Diver crossed closed gate %s before public activation." % gate_id)
			return false
	_assert(collided, "Real Diver must physically collide with closed gate %s." % gate_id)
	_diver.call("stop_motion")
	return collided and _errors.is_empty()


func _run_bidirectional_route(
	navigation,
	anchors: Array[Vector2],
	label: String,
	classification_rect: Rect2 = Rect2(),
	require_rect_overlap: bool = false
) -> bool:
	var points := _build_dense_route(navigation, anchors, label)
	if points.is_empty():
		return false
	if classification_rect.has_area():
		var overlaps := false
		for point in points:
			if classification_rect.has_point(point):
				overlaps = true
				break
		_assert(
			overlaps == require_rect_overlap,
			"Route %s current-zone classification mismatch: overlap=%s expected=%s." % [label, overlaps, require_rect_overlap],
		)
		if not _errors.is_empty():
			return false
	await _reset_and_stream(points[0], label)
	if not _errors.is_empty():
		return false
	var forward_ticks_before := _total_motion_ticks
	var forward_distance := await _follow_points(navigation, points, label + " forward")
	if forward_distance < 0.0:
		return false
	var reversed := points.duplicate()
	reversed.reverse()
	var backward_distance := await _follow_points(navigation, reversed, label + " backout")
	if backward_distance < 0.0:
		return false
	_assert(_diver.global_position.distance_to(points[0]) <= TARGET_DISTANCE * 1.5, "Route %s must physically return to its start." % label)
	_report.routes.append({
		"label": label,
		"waypoints": points.size(),
		"forward_distance": forward_distance,
		"backout_distance": backward_distance,
		"motion_ticks": _total_motion_ticks - forward_ticks_before,
	})
	return _errors.is_empty()


func _build_dense_route(navigation, anchors: Array[Vector2], label: String) -> Array[Vector2]:
	if anchors.size() < 2:
		_assert(false, "Route %s requires at least two anchors." % label)
		return []
	var grid := _build_astar_grid(navigation)
	if grid == null:
		return []
	var result: Array[Vector2] = []
	for index in range(anchors.size() - 1):
		var start_cell := _nearest_clear_cell(navigation, anchors[index])
		var end_cell := _nearest_clear_cell(navigation, anchors[index + 1])
		if start_cell.x < 0 or end_cell.x < 0:
			_assert(false, "Route %s cannot resolve clear cells for anchor leg %d." % [label, index])
			return []
		var id_path := grid.get_id_path(start_cell, end_cell)
		if id_path.is_empty():
			_assert(false, "Route %s has no public navigation path for leg %d." % [label, index])
			return []
		var raw_leg: Array[Vector2] = []
		for cell_value in id_path:
			raw_leg.append(navigation.call("cell_center", cell_value as Vector2i))
		var leg := _simplify_dense_path(navigation, raw_leg)
		if not result.is_empty() and not leg.is_empty() and result[-1].is_equal_approx(leg[0]):
			leg.remove_at(0)
		result.append_array(leg)
	return result


func _build_astar_grid(navigation) -> AStarGrid2D:
	var grid_size_value: Variant = navigation.get("grid_size")
	if not grid_size_value is Vector2i:
		_assert(false, "Navigation snapshot must publish a typed grid_size.")
		return null
	var grid_size := grid_size_value as Vector2i
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, grid_size)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if not bool(navigation.call("is_cell_clear", cell)):
				grid.set_point_solid(cell, true)
	return grid


func _nearest_clear_cell(navigation, world_position: Vector2) -> Vector2i:
	var origin: Vector2i = navigation.call("world_to_cell", world_position)
	for radius in range(0, 13):
		var best := Vector2i(-1, -1)
		var best_distance := INF
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				if radius > 0 and x > origin.x - radius and x < origin.x + radius and y > origin.y - radius and y < origin.y + radius:
					continue
				var cell := Vector2i(x, y)
				if not bool(navigation.call("is_cell_clear", cell)):
					continue
				var center: Vector2 = navigation.call("cell_center", cell)
				var distance := center.distance_squared_to(world_position)
				if distance < best_distance:
					best_distance = distance
					best = cell
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func _simplify_dense_path(navigation, raw: Array[Vector2]) -> Array[Vector2]:
	if raw.size() <= 2:
		return raw.duplicate()
	var result: Array[Vector2] = [raw[0]]
	var index := 0
	while index < raw.size() - 1:
		var next_index := mini(index + PATH_WAYPOINT_STRIDE_CELLS, raw.size() - 1)
		while next_index > index + 1 and not bool(navigation.call("is_segment_clear", raw[index], raw[next_index])):
			next_index -= 1
		result.append(raw[next_index])
		index = next_index
	return result


func _follow_points(navigation, points: Array[Vector2], label: String) -> float:
	var travelled := 0.0
	for index in range(1, points.size()):
		var distance := await _move_to(navigation, points[index], "%s waypoint %d/%d" % [label, index, points.size() - 1])
		if distance < 0.0:
			return -1.0
		travelled += distance
	return travelled


func _move_to(navigation, target: Vector2, label: String) -> float:
	var initial_distance := _diver.global_position.distance_to(target)
	var maximum_ticks := mini(maxi(ceili(initial_distance / 120.0 / MOTION_DELTA) + 90, 120), 720)
	var travelled := 0.0
	var stagnant_ticks := 0
	var best_distance := initial_distance
	for tick in range(maximum_ticks):
		var distance_to_target := _diver.global_position.distance_to(target)
		if distance_to_target <= TARGET_DISTANCE:
			return travelled
		if _total_motion_ticks >= MAX_TOTAL_MOTION_TICKS:
			_assert(false, "S-loop replay exceeded the global deterministic motion-tick budget at %s." % label)
			return -1.0
		if not await _prepare_motion_tick(navigation, tick):
			return -1.0
		var current := _current_at(_diver.global_position)
		var desired := (target - _diver.global_position).normalized()
		var sprint_speed := maxf(float(_diver.get("sprint_speed")), 1.0)
		var command := ((desired * ROUTE_DESIRED_SPEED - current) / sprint_speed).limit_length(1.0)
		var previous := _diver.global_position
		var motion := _diver.call("simulate_motion_tick", command, true, current, SPEED_MULTIPLIER, MOTION_DELTA, true) as Dictionary
		_total_motion_ticks += 1
		if not _validate_motion_tick(navigation, previous, current, motion, false):
			_assert(false, "Route %s collided with streamed production physics." % label)
			return -1.0
		travelled += float(motion.get("travelled", 0.0))
		var remaining := _diver.global_position.distance_to(target)
		if remaining < best_distance - 0.25:
			best_distance = remaining
			stagnant_ticks = 0
		else:
			stagnant_ticks += 1
		if stagnant_ticks >= STAGNANT_TICKS:
			_assert(false, "Route %s stagnated %.2f units from its dense waypoint." % [label, remaining])
			return -1.0
	_assert(false, "Route %s timed out %.2f units from its dense waypoint." % [label, _diver.global_position.distance_to(target)])
	return -1.0


func _prepare_motion_tick(navigation, tick: int) -> bool:
	_map.call("update_streaming", _diver.global_position, false, STREAM_EXTENT)
	var loaded := _loaded_collision_keys()
	_assert(not loaded.is_empty(), "Every physical S-loop motion tick must retain a non-empty streamed collision window.")
	if not _errors.is_empty():
		return false
	if loaded != _last_loaded_keys:
		_last_loaded_keys = loaded
		_record_stream_window(loaded)
		await _tree.process_frame
		await _tree.physics_frame
	elif tick % PHYSICS_SYNC_STRIDE == 0:
		await _tree.physics_frame
	return true


func _reset_and_stream(position: Vector2, label: String) -> void:
	_diver.call("reset_at", position)
	_map.call("update_streaming", position, true, STREAM_EXTENT)
	await _tree.process_frame
	await _tree.physics_frame
	await _tree.physics_frame
	_last_loaded_keys = _loaded_collision_keys()
	_assert(not _last_loaded_keys.is_empty(), "Reset %s must hydrate a non-empty production collision window before motion." % label)
	_record_stream_window(_last_loaded_keys)


func _loaded_collision_keys() -> Array[String]:
	var result: Array[String] = []
	for value in _map.call("loaded_collision_chunk_keys"):
		result.append(str(value))
	result.sort()
	return result


func _record_stream_window(keys: Array[String]) -> void:
	if keys.is_empty():
		return
	var fingerprint := ",".join(keys)
	if _stream_fingerprints.has(fingerprint):
		return
	_stream_fingerprints[fingerprint] = true
	_report.stream_windows.append({"loaded_chunk_count": keys.size(), "fingerprint": fingerprint.sha256_text()})


func _current_at(position: Vector2) -> Vector2:
	var value: Variant = _map.call("current_at", position)
	return value as Vector2 if value is Vector2 else Vector2.ZERO


func _validate_motion_tick(navigation, previous: Vector2, current: Vector2, motion: Dictionary, allow_collision: bool) -> bool:
	var position_value: Variant = motion.get("position", _diver.global_position)
	var velocity_value: Variant = motion.get("velocity", _diver.velocity)
	_assert(position_value is Vector2 and (position_value as Vector2).is_finite(), "Real Diver motion must return a finite position.")
	_assert(velocity_value is Vector2 and (velocity_value as Vector2).is_finite(), "Real Diver motion must return a finite velocity.")
	if not position_value is Vector2:
		return false
	var position := position_value as Vector2
	var displacement := position.distance_to(previous)
	var reported := float(motion.get("travelled", -1.0))
	_assert(is_equal_approx(displacement, reported), "simulate_motion_tick travelled must equal the real CharacterBody2D displacement.")
	var sprint_speed := maxf(float(_diver.get("sprint_speed")), 1.0)
	var maximum_step := (sprint_speed * SPEED_MULTIPLIER + current.length()) * MOTION_DELTA + 0.75
	_assert(displacement <= maximum_step, "Real Diver displacement %.3f exceeds the fixed-60Hz no-tunneling bound %.3f." % [displacement, maximum_step])
	_assert(bool(navigation.call("is_position_open", position)), "Real Diver must remain in the public open-water raster after every move_and_slide tick.")
	var collided := bool(motion.get("collided", false))
	return _errors.is_empty() and (allow_collision or not collided)


func _audit_current_zone(navigation, zone: Dictionary) -> bool:
	var points := _current_route_points(zone)
	var velocity: Vector2 = zone.get("velocity", Vector2.ZERO)
	var direction := velocity.normalized()
	_assert(not direction.is_zero_approx(), "Public current zone must publish non-zero velocity.")
	if not _errors.is_empty():
		return false
	await _reset_and_stream(points.center, "current-drift-%s" % str(zone.get("id", "")))
	var drift_start := _diver.global_position
	var collision_ticks := 0
	for tick in range(30):
		if not await _prepare_motion_tick(navigation, tick):
			return false
		var current := _current_at(_diver.global_position)
		var previous := _diver.global_position
		var motion := _diver.call("simulate_motion_tick", Vector2.ZERO, false, current, SPEED_MULTIPLIER, MOTION_DELTA, true) as Dictionary
		_total_motion_ticks += 1
		collision_ticks += 1 if bool(motion.get("collided", false)) else 0
		if not _validate_motion_tick(navigation, previous, current, motion, false):
			return false
	var drift := _diver.global_position - drift_start
	_assert(drift.dot(direction) > 5.0, "Idle real Diver must visibly drift with current %s." % str(zone.get("id", "")))
	_assert(collision_ticks == 0, "Current drift fixture must remain free of physical collisions.")
	var anchors: Array[Vector2] = [points.upstream, points.center, points.downstream]
	if not await _run_bidirectional_route(navigation, anchors, "current %s" % str(zone.get("id", ""))):
		return false
	_report.currents.append({
		"id": str(zone.get("id", "")),
		"velocity": [velocity.x, velocity.y],
		"drift_projection": drift.dot(direction),
		"counter_current": true,
	})
	return _errors.is_empty()


func _audit_stop_and_turn(navigation, sides: Dictionary) -> bool:
	var tangent: Vector2 = sides.tangent
	var near: Vector2 = sides.near
	var far: Vector2 = sides.far
	var tangent_point := Vector2.ZERO
	for signed_distance in [220.0, -220.0, 280.0, -280.0]:
		var candidate := near + tangent * float(signed_distance)
		if bool(navigation.call("is_position_clear", candidate)) and bool(navigation.call("is_segment_clear", candidate, near)):
			tangent_point = candidate
			break
	_assert(not tangent_point.is_zero_approx(), "C4 service approach must expose a clear tangent for the stop-and-turn replay.")
	if not _errors.is_empty():
		return false
	var approach := (near - tangent_point).normalized()
	var crossing := (far - near).normalized()
	var turn_degrees := rad_to_deg(acos(clampf(approach.dot(crossing), -1.0, 1.0)))
	_assert(turn_degrees >= 70.0 and turn_degrees <= 110.0, "Service approach must require a real approximately 90-degree turn, got %.2f." % turn_degrees)
	await _reset_and_stream(tangent_point, "service-stop-turn")
	var approach_points := _build_dense_route(navigation, [tangent_point, near], "service tangent approach")
	if await _follow_points(navigation, approach_points, "service tangent approach") < 0.0:
		return false
	_diver.call("stop_motion")
	var stop_start := _diver.global_position
	for tick in range(45):
		if not await _prepare_motion_tick(navigation, tick):
			return false
		var current := _current_at(_diver.global_position)
		var previous := _diver.global_position
		var motion := _diver.call("simulate_motion_tick", Vector2.ZERO, false, current, SPEED_MULTIPLIER, MOTION_DELTA, true) as Dictionary
		_total_motion_ticks += 1
		if not _validate_motion_tick(navigation, previous, current, motion, false):
			return false
	_assert(_diver.global_position.distance_to(stop_start) <= 1.0, "Stop before the 90-degree service turn must hold position in calm water.")
	_assert(_diver.velocity.length() <= 0.5, "Stop before the 90-degree service turn must settle real Diver velocity.")
	var crossing_points := _build_dense_route(navigation, [near, far, near, tangent_point], "service stop/90/backout")
	if await _follow_points(navigation, crossing_points, "service stop/90/backout") < 0.0:
		return false
	_report.stop_turn = {
		"turn_degrees": turn_degrees,
		"stop_ticks": 45,
		"forward_and_backout": true,
	}
	return _errors.is_empty()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	if not _errors.has(message):
		_errors.append(message)


func _result() -> Dictionary:
	return {
		"success": _errors.is_empty(),
		"errors": _errors.duplicate(),
		"report": _report.duplicate(true),
	}
