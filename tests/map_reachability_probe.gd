extends SceneTree

const MapScene := preload("res://scenes/diving/UnderwaterMap.tscn")

func _initialize() -> void:
	var map = MapScene.instantiate() as UnderwaterMapScene
	var image: Image = map.navigation_grid_texture.get_image()
	var width := image.get_width()
	var height := image.get_height()
	var scale := Vector2(map.world_size.x / width, map.world_size.y / height)
	var cells := PackedByteArray()
	cells.resize(width * height)
	for y in range(height):
		for x in range(width):
			cells[y * width + x] = 0 if image.get_pixel(x, y).r > 0.5 else 1
	var entry := Vector2.ZERO
	var objects: Array[DiveMapObject] = []
	for node in map.find_children("*", "", true, false):
		if node is DiveMapObject:
			var object := node as DiveMapObject
			objects.append(object)
			if object.kind == DiveMapObject.Kind.ENTRY_POINT:
				entry = object.global_position
	var reachable := _reachable(cells, width, height, _cell_at(entry, scale))
	for object in objects:
		if object.kind not in [
			DiveMapObject.Kind.LOOT_CONTAINER, DiveMapObject.Kind.PICKUP, DiveMapObject.Kind.THREAT,
			DiveMapObject.Kind.HEAVY_OBJECT, DiveMapObject.Kind.RESCUE, DiveMapObject.Kind.BUOY,
			DiveMapObject.Kind.SHORTCUT_GATE,
		]:
			continue
		var cell := _cell_at(object.global_position, scale)
		if _is_reachable(reachable, width, height, cell):
			continue
		var nearest := _nearest_reachable(reachable, width, height, cell)
		print("%s|%s|%s|%s" % [object.object_id, object.global_position, cell, _cell_center(nearest, scale)])
	map.free()
	quit()

func _cell_at(position: Vector2, scale: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / scale.x), floori(position.y / scale.y))

func _cell_center(cell: Vector2i, scale: Vector2) -> Vector2:
	return Vector2((cell.x + 0.5) * scale.x, (cell.y + 0.5) * scale.y)

func _is_reachable(reachable: PackedByteArray, width: int, height: int, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height and reachable[cell.y * width + cell.x] == 1

func _reachable(cells: PackedByteArray, width: int, height: int, entry: Vector2i) -> PackedByteArray:
	var reachable := PackedByteArray()
	reachable.resize(width * height)
	if entry.x < 0 or entry.y < 0 or entry.x >= width or entry.y >= height or cells[entry.y * width + entry.x] != 1:
		return reachable
	var queue: Array[int] = [entry.y * width + entry.x]
	reachable[queue[0]] = 1
	var read_index := 0
	while read_index < queue.size():
		var index := queue[read_index]
		read_index += 1
		var cell := Vector2i(index % width, index / width)
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
				continue
			var next_index: int = next.y * width + next.x
			if cells[next_index] != 1 or reachable[next_index] == 1:
				continue
			reachable[next_index] = 1
			queue.append(next_index)
	return reachable

func _nearest_reachable(reachable: PackedByteArray, width: int, height: int, candidate: Vector2i) -> Vector2i:
	var center := Vector2i(clampi(candidate.x, 0, width - 1), clampi(candidate.y, 0, height - 1))
	for radius in range(maxi(width, height)):
		for x in range(center.x - radius, center.x + radius + 1):
			for y in [center.y - radius, center.y + radius]:
				var cell := Vector2i(x, y)
				if _is_reachable(reachable, width, height, cell):
					return cell
		for y in range(center.y - radius + 1, center.y + radius):
			for x in [center.x - radius, center.x + radius]:
				var cell := Vector2i(x, y)
				if _is_reachable(reachable, width, height, cell):
					return cell
	return center
