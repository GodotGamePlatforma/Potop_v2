class_name DiveNavigationSnapshot
extends RefCounted


const WorldBlueprintScript := preload("res://scripts/data/WorldBlueprint.gd")
const DEFAULT_DIVER_CLEARANCE := 35.0
const SHORTCUT_GATE_HEIGHT := 28.0
const MAX_BASE_CLEARANCE_CACHE_ENTRIES := 8

static var _base_clear_cells_cache: Dictionary = {}
static var _base_clear_cells_cache_order: Array[String] = []


var world_size: Vector2 = Vector2.ZERO
var grid_size: Vector2i = Vector2i.ZERO
var cell_scale: Vector2 = Vector2.ONE
var clearance_world: float = DEFAULT_DIVER_CLEARANCE
var start_position: Vector2 = Vector2.ZERO
var exit_position: Vector2 = Vector2.ZERO
var open_cells := PackedByteArray()
var clear_cells := PackedByteArray()
var current_zones: Array[Dictionary] = []
var depth_profile_points := PackedVector2Array()
var closed_shortcut_gates: Array[Dictionary] = []
var targets: Array[Dictionary] = []
var threats: Array[Dictionary] = []


func configure(
	world_extent: Vector2,
	grid_extent: Vector2i,
	grid_cell_scale: Vector2,
	source_open_cells: PackedByteArray,
	requested_clearance_world: float,
	resolved_start_position: Vector2,
	resolved_exit_position: Vector2,
	source_current_zones: Array,
	source_depth_profile_points: PackedVector2Array,
	source_closed_shortcut_gates: Array,
	source_targets: Array,
	source_threats: Array = []
) -> void:
	world_size = world_extent
	grid_size = grid_extent
	cell_scale = grid_cell_scale
	clearance_world = maxf(requested_clearance_world, 0.0)
	start_position = resolved_start_position
	exit_position = resolved_exit_position
	open_cells = source_open_cells.duplicate()
	_copy_dictionary_array(source_current_zones, current_zones)
	depth_profile_points = source_depth_profile_points.duplicate()
	_copy_dictionary_array(source_closed_shortcut_gates, closed_shortcut_gates)
	_copy_dictionary_array(source_targets, targets)
	_copy_dictionary_array(source_threats, threats)
	_rebuild_clear_cells()


func is_valid() -> bool:
	return (
		world_size.x > 0.0
		and world_size.y > 0.0
		and grid_size.x > 0
		and grid_size.y > 0
		and cell_scale.x > 0.0
		and cell_scale.y > 0.0
		and open_cells.size() == grid_size.x * grid_size.y
		and clear_cells.size() == open_cells.size()
		and WorldBlueprintScript.depth_profile_validation_errors(depth_profile_points).is_empty()
	)


func world_to_cell(world_position: Vector2) -> Vector2i:
	if cell_scale.x <= 0.0 or cell_scale.y <= 0.0:
		return Vector2i(-1, -1)
	return Vector2i(
		floori(world_position.x / cell_scale.x),
		floori(world_position.y / cell_scale.y)
	)


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(
		(float(cell.x) + 0.5) * cell_scale.x,
		(float(cell.y) + 0.5) * cell_scale.y
	)


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func is_cell_open(cell: Vector2i) -> bool:
	if not is_cell_in_bounds(cell):
		return false
	return open_cells[_cell_index(cell)] == 1


func is_cell_clear(cell: Vector2i) -> bool:
	if not is_cell_in_bounds(cell):
		return false
	return clear_cells[_cell_index(cell)] == 1


func is_position_open(world_position: Vector2) -> bool:
	return is_cell_open(world_to_cell(world_position))


func is_position_clear(world_position: Vector2) -> bool:
	return is_cell_clear(world_to_cell(world_position))


func is_segment_clear(from_position: Vector2, to_position: Vector2) -> bool:
	if not is_position_clear(from_position) or not is_position_clear(to_position):
		return false
	var delta := to_position - from_position
	if delta.length_squared() <= 0.000001:
		return true
	var cell := world_to_cell(from_position)
	var end_cell := world_to_cell(to_position)
	var step_x := int(signf(delta.x))
	var step_y := int(signf(delta.y))
	var next_boundary_x := (
		(float(cell.x + 1) * cell_scale.x)
		if step_x > 0
		else (float(cell.x) * cell_scale.x)
	)
	var next_boundary_y := (
		(float(cell.y + 1) * cell_scale.y)
		if step_y > 0
		else (float(cell.y) * cell_scale.y)
	)
	var t_max_x := (next_boundary_x - from_position.x) / delta.x if step_x != 0 else INF
	var t_max_y := (next_boundary_y - from_position.y) / delta.y if step_y != 0 else INF
	var t_delta_x := cell_scale.x / absf(delta.x) if step_x != 0 else INF
	var t_delta_y := cell_scale.y / absf(delta.y) if step_y != 0 else INF
	while cell != end_cell:
		if cell.x == end_cell.x:
			cell.y += step_y
			t_max_y += t_delta_y
		elif cell.y == end_cell.y:
			cell.x += step_x
			t_max_x += t_delta_x
		elif is_equal_approx(t_max_x, t_max_y):
			var horizontal := cell + Vector2i(step_x, 0)
			var vertical := cell + Vector2i(0, step_y)
			if not is_cell_clear(horizontal) or not is_cell_clear(vertical):
				return false
			cell += Vector2i(step_x, step_y)
			t_max_x += t_delta_x
			t_max_y += t_delta_y
		elif t_max_x < t_max_y:
			cell.x += step_x
			t_max_x += t_delta_x
		else:
			cell.y += step_y
			t_max_y += t_delta_y
		if not is_cell_clear(cell):
			return false
	return true


func current_at(world_position: Vector2) -> Vector2:
	for zone in current_zones:
		var rect: Rect2 = zone.get("rect", Rect2())
		if rect.has_point(world_position):
			return zone.get("velocity", Vector2.ZERO)
	return Vector2.ZERO


func scout_signal_at(
	world_position: Vector2,
	maximum_distance: float = 640.0,
	minimum_current_speed: float = 60.0
) -> Dictionary:
	return scout_signal_for_records(
		world_position,
		threats,
		current_zones,
		maximum_distance,
		minimum_current_speed
	)


static func scout_signal_for_records(
	world_position: Vector2,
	threat_records: Array,
	current_records: Array,
	maximum_distance: float = 640.0,
	minimum_current_speed: float = 60.0
) -> Dictionary:
	var best: Dictionary = {}
	var safe_maximum := maxf(maximum_distance, 0.0)
	for record_variant in threat_records:
		if not record_variant is Dictionary:
			continue
		var record := record_variant as Dictionary
		if bool(record.get("defeated", false)):
			continue
		var target_position = record.get("position", null)
		if not target_position is Vector2:
			continue
		var distance := world_position.distance_to(target_position)
		if distance <= 0.0001 or distance > safe_maximum:
			continue
		var candidate := {
			"kind": "threat",
			"id": str(record.get("id", "")),
			"direction": target_position - world_position,
			"distance": distance,
			"priority": 0,
		}
		if _scout_candidate_precedes(candidate, best):
			best = candidate

	for index in range(current_records.size()):
		var record_variant = current_records[index]
		if not record_variant is Dictionary:
			continue
		var record := record_variant as Dictionary
		var velocity = record.get("velocity", Vector2.ZERO)
		var rect = record.get("rect", Rect2())
		if not velocity is Vector2 or not rect is Rect2:
			continue
		if velocity.length() < maxf(minimum_current_speed, 0.0) or rect.has_point(world_position):
			continue
		var nearest_point := Vector2(
			clampf(world_position.x, rect.position.x, rect.end.x),
			clampf(world_position.y, rect.position.y, rect.end.y)
		)
		var distance := world_position.distance_to(nearest_point)
		if distance <= 0.0001 or distance > safe_maximum:
			continue
		var candidate := {
			"kind": "current",
			"id": str(record.get("id", "current_%d" % index)),
			"direction": nearest_point - world_position,
			"distance": distance,
			"priority": 1,
		}
		if _scout_candidate_precedes(candidate, best):
			best = candidate

	if best.is_empty():
		return {}
	best.erase("priority")
	return best


static func _scout_candidate_precedes(candidate: Dictionary, current_best: Dictionary) -> bool:
	if current_best.is_empty():
		return true
	var candidate_distance := float(candidate.get("distance", INF))
	var best_distance := float(current_best.get("distance", INF))
	if not is_equal_approx(candidate_distance, best_distance):
		return candidate_distance < best_distance
	var candidate_priority := int(candidate.get("priority", 99))
	var best_priority := int(current_best.get("priority", 99))
	if candidate_priority != best_priority:
		return candidate_priority < best_priority
	return str(candidate.get("id", "")) < str(current_best.get("id", ""))


func depth_at(world_position: Vector2) -> float:
	return WorldBlueprintScript.depth_at_world_y(
		depth_profile_points,
		world_size.y,
		world_position.y
	)


func target_descriptors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_copy_dictionary_array(targets, result)
	return result


func threat_descriptors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_copy_dictionary_array(threats, result)
	return result


func closed_gate_descriptors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_copy_dictionary_array(closed_shortcut_gates, result)
	return result


func _rebuild_clear_cells() -> void:
	clear_cells.resize(open_cells.size())
	clear_cells.fill(0)
	if (
		grid_size.x <= 0
		or grid_size.y <= 0
		or cell_scale.x <= 0.0
		or cell_scale.y <= 0.0
		or open_cells.size() != grid_size.x * grid_size.y
	):
		return

	var minimum_cell_extent := maxf(minf(cell_scale.x, cell_scale.y), 1.0)
	var clearance_cells := ceili(clearance_world / minimum_cell_extent)
	var cache_key := _base_clearance_cache_key(clearance_cells)
	if _base_clear_cells_cache.has(cache_key):
		var cached_clear_cells: PackedByteArray = _base_clear_cells_cache[cache_key]
		if cached_clear_cells.size() == open_cells.size():
			clear_cells = cached_clear_cells.duplicate()
		else:
			_base_clear_cells_cache.erase(cache_key)
			_base_clear_cells_cache_order.erase(cache_key)
	if not _base_clear_cells_cache.has(cache_key):
		var prefix_stride := grid_size.x + 1
		var blocked_prefix := PackedInt32Array()
		blocked_prefix.resize(prefix_stride * (grid_size.y + 1))
		for y in range(grid_size.y):
			var row_blocked := 0
			for x in range(grid_size.x):
				if open_cells[y * grid_size.x + x] != 1:
					row_blocked += 1
				blocked_prefix[(y + 1) * prefix_stride + x + 1] = (
					blocked_prefix[y * prefix_stride + x + 1] + row_blocked
				)

		for y in range(grid_size.y):
			for x in range(grid_size.x):
				var cell := Vector2i(x, y)
				if not is_cell_open(cell):
					continue
				if not _has_static_clearance(cell, clearance_cells, blocked_prefix, prefix_stride):
					continue
				clear_cells[_cell_index(cell)] = 1
		_store_base_clear_cells(cache_key, clear_cells)

	for gate in closed_shortcut_gates:
		_mask_closed_gate(gate)


func _base_clearance_cache_key(clearance_cells: int) -> String:
	var hashing_context := HashingContext.new()
	hashing_context.start(HashingContext.HASH_SHA256)
	hashing_context.update(open_cells)
	return "base_clearance_v1|%d|%d|%d|%s" % [
		grid_size.x,
		grid_size.y,
		clearance_cells,
		hashing_context.finish().hex_encode(),
	]


func _store_base_clear_cells(cache_key: String, source: PackedByteArray) -> void:
	if _base_clear_cells_cache.has(cache_key):
		return
	while _base_clear_cells_cache_order.size() >= MAX_BASE_CLEARANCE_CACHE_ENTRIES:
		var oldest_key: String = _base_clear_cells_cache_order.pop_front()
		_base_clear_cells_cache.erase(oldest_key)
	_base_clear_cells_cache[cache_key] = source.duplicate()
	_base_clear_cells_cache_order.append(cache_key)


func _has_static_clearance(
	cell: Vector2i,
	clearance_cells: int,
	blocked_prefix: PackedInt32Array,
	prefix_stride: int
) -> bool:
	if clearance_cells <= 0:
		return true
	var left := cell.x - clearance_cells
	var top := cell.y - clearance_cells
	var right := cell.x + clearance_cells
	var bottom := cell.y + clearance_cells
	if left < 0 or top < 0 or right >= grid_size.x or bottom >= grid_size.y:
		return false
	var blocked_count := (
		blocked_prefix[(bottom + 1) * prefix_stride + right + 1]
		- blocked_prefix[top * prefix_stride + right + 1]
		- blocked_prefix[(bottom + 1) * prefix_stride + left]
		+ blocked_prefix[top * prefix_stride + left]
	)
	return blocked_count == 0


func _mask_closed_gate(gate: Dictionary) -> void:
	if not bool(gate.get("active", true)):
		return
	var gate_transform: Transform2D = gate.get("transform", Transform2D.IDENTITY)
	var gate_size: Vector2 = gate.get("size", Vector2.ZERO)
	if gate_size.x <= 0.0 or gate_size.y <= 0.0:
		return
	var half_cell_diagonal := cell_scale.length() * 0.5
	var expanded_half_size := gate_size * 0.5 + Vector2.ONE * (clearance_world + half_cell_diagonal)
	var corners := PackedVector2Array([
		gate_transform * Vector2(-expanded_half_size.x, -expanded_half_size.y),
		gate_transform * Vector2(expanded_half_size.x, -expanded_half_size.y),
		gate_transform * Vector2(expanded_half_size.x, expanded_half_size.y),
		gate_transform * Vector2(-expanded_half_size.x, expanded_half_size.y),
	])
	var minimum := corners[0]
	var maximum := corners[0]
	for corner in corners:
		minimum.x = minf(minimum.x, corner.x)
		minimum.y = minf(minimum.y, corner.y)
		maximum.x = maxf(maximum.x, corner.x)
		maximum.y = maxf(maximum.y, corner.y)
	var minimum_cell := world_to_cell(minimum)
	var maximum_cell := world_to_cell(maximum)
	var inverse_transform := gate_transform.affine_inverse()
	for y in range(maxi(minimum_cell.y, 0), mini(maximum_cell.y, grid_size.y - 1) + 1):
		for x in range(maxi(minimum_cell.x, 0), mini(maximum_cell.x, grid_size.x - 1) + 1):
			var cell := Vector2i(x, y)
			if not is_cell_clear(cell):
				continue
			var local_position := inverse_transform * cell_center(cell)
			if (
				absf(local_position.x) <= expanded_half_size.x
				and absf(local_position.y) <= expanded_half_size.y
			):
				clear_cells[_cell_index(cell)] = 0


func _cell_index(cell: Vector2i) -> int:
	return cell.y * grid_size.x + cell.x


func _copy_dictionary_array(source: Array, target: Array[Dictionary]) -> void:
	target.clear()
	for value in source:
		if value is Dictionary:
			target.append(value.duplicate(true))
