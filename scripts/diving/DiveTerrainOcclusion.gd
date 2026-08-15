class_name DiveTerrainOcclusion
extends RefCounted

const TERRAIN_LIGHT_MASK := 1


## Builds streamed presentation occluders from the exact boundary segments
## already consumed by collision. No independent contour or gameplay topology
## is introduced; unloading the owning collision chunk unloads its shadows too.
static func attach_to(parent: Node, segments: PackedVector2Array) -> int:
	if parent == null or segments.size() < 2:
		return 0
	var segment_count: int = segments.size() / 2
	var outgoing: Dictionary = {}
	var incoming_count: Dictionary = {}
	for segment_index in range(segment_count):
		var start := segments[segment_index * 2]
		var finish := segments[segment_index * 2 + 1]
		var outgoing_indices: Array = outgoing.get(start, [])
		outgoing_indices.append(segment_index)
		outgoing[start] = outgoing_indices
		incoming_count[finish] = int(incoming_count.get(finish, 0)) + 1

	var seed_order: Array[int] = []
	for segment_index in range(segment_count):
		var start := segments[segment_index * 2]
		if int(incoming_count.get(start, 0)) == 0:
			seed_order.append(segment_index)
	for segment_index in range(segment_count):
		seed_order.append(segment_index)

	var visited := PackedByteArray()
	visited.resize(segment_count)
	var occluder_count := 0
	for seed_index in seed_order:
		if visited[seed_index] != 0:
			continue
		var points := PackedVector2Array([segments[seed_index * 2]])
		var current_index := seed_index
		var closed := false
		for _guard in range(segment_count):
			if visited[current_index] != 0:
				break
			visited[current_index] = 1
			var finish := segments[current_index * 2 + 1]
			points.append(finish)
			if finish == points[0]:
				closed = true
				break
			var next_index := -1
			var candidates: Array = outgoing.get(finish, [])
			for candidate_variant in candidates:
				var candidate_index := int(candidate_variant)
				if visited[candidate_index] == 0:
					next_index = candidate_index
					break
			if next_index < 0:
				break
			current_index = next_index

		if closed:
			points.resize(points.size() - 1)
		if points.size() < 2:
			continue
		var polygon := OccluderPolygon2D.new()
		polygon.polygon = points
		polygon.closed = closed and points.size() >= 3
		polygon.cull_mode = OccluderPolygon2D.CULL_DISABLED
		var occluder := LightOccluder2D.new()
		occluder.name = "TerrainOccluder_%d" % occluder_count
		occluder.occluder_light_mask = TERRAIN_LIGHT_MASK
		occluder.sdf_collision = false
		occluder.occluder = polygon
		parent.add_child(occluder)
		occluder_count += 1
	return occluder_count
