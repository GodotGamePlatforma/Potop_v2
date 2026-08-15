class_name WorldBlueprint
extends Resource

@export var campaign_seed: int = 1
## Runtime snapshot compiled from UnderwaterMap.tscn. It belongs to the parent
## campaign format; the scene and its prefabs are the only map source.
@export var map_source_version: int = 0
@export var map_id: String = ""
@export var map_gameplay_signature: String = ""
@export var world_size: Vector2 = Vector2.ZERO
@export var entry_landmark_id: String = ""
@export var entry_position: Vector2 = Vector2.ZERO
@export var exit_position: Vector2 = Vector2.ZERO
@export var chunk_size: int = 512
@export var regions: Array[Dictionary] = []
@export var landmarks: Array[Dictionary] = []
@export var connections: Array[Dictionary] = []
@export var loot_spawns: Array[Dictionary] = []
@export var current_zones: Array[Dictionary] = []
@export var threat_spawns: Array[Dictionary] = []
@export var heavy_object_spawns: Array[Dictionary] = []
@export var rescue_spawns: Array[Dictionary] = []
@export var buoy_spawns: Array[Dictionary] = []
@export var shortcut_spawns: Array[Dictionary] = []
@export var fixed_device_spawns: Array[Dictionary] = []
@export var obstacle_spawns: Array[Dictionary] = []
@export var decoration_spawns: Array[Dictionary] = []
@export var landmark_lookup: Dictionary = {}
@export var connection_lookup: Dictionary = {}
@export var chunk_index: Dictionary = {}

func clear() -> void:
	map_source_version = 0
	map_id = ""
	map_gameplay_signature = ""
	world_size = Vector2.ZERO
	entry_landmark_id = ""
	entry_position = Vector2.ZERO
	exit_position = Vector2.ZERO
	regions.clear()
	landmarks.clear()
	connections.clear()
	loot_spawns.clear()
	current_zones.clear()
	threat_spawns.clear()
	heavy_object_spawns.clear()
	rescue_spawns.clear()
	buoy_spawns.clear()
	shortcut_spawns.clear()
	fixed_device_spawns.clear()
	obstacle_spawns.clear()
	decoration_spawns.clear()
	landmark_lookup.clear()
	connection_lookup.clear()
	chunk_index.clear()

func rebuild_indexes() -> void:
	landmark_lookup.clear()
	for index in range(landmarks.size()):
		var landmark: Dictionary = landmarks[index]
		landmark_lookup[str(landmark.get("id", ""))] = index
	connection_lookup.clear()
	for index in range(connections.size()):
		var connection: Dictionary = connections[index]
		connection_lookup[str(connection.get("id", ""))] = index

func resolve_landmark_id(landmark_or_alias: String) -> String:
	if landmark_lookup.has(landmark_or_alias):
		return landmark_or_alias
	for landmark in landmarks:
		var aliases: Array = landmark.get("aliases", [])
		if aliases.has(landmark_or_alias):
			return str(landmark.get("id", ""))
	return ""

func get_landmark(landmark_or_alias: String) -> Dictionary:
	var resolved_id := resolve_landmark_id(landmark_or_alias)
	var index := int(landmark_lookup.get(resolved_id, -1))
	if index < 0 or index >= landmarks.size():
		return {}
	return landmarks[index]

func get_landmark_by_anchor(anchor_id: String) -> Dictionary:
	for landmark in landmarks:
		if str(landmark.get("anchor_id", "")) == anchor_id:
			return landmark
	return {}

func get_heavy_object(object_id: String) -> Dictionary:
	for heavy_object in heavy_object_spawns:
		if str(heavy_object.get("id", "")) == object_id:
			return heavy_object
	return {}

func get_region_at(world_position: Vector2) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for region in regions:
		var bounds: Rect2 = region.get("bounds", Rect2())
		if bounds.has_point(world_position):
			var center_distance := world_position.distance_squared_to(bounds.get_center())
			if center_distance < nearest_distance:
				nearest = region
				nearest_distance = center_distance
	return nearest

func get_nearest_landmark(world_position: Vector2) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for landmark in landmarks:
		var position: Vector2 = landmark.get("position", Vector2.ZERO)
		var distance := position.distance_squared_to(world_position)
		if distance < nearest_distance:
			nearest = landmark
			nearest_distance = distance
	return nearest

func chunk_coord_at(world_position: Vector2) -> Vector2i:
	var safe_size := maxi(chunk_size, 1)
	return Vector2i(floori(world_position.x / safe_size), floori(world_position.y / safe_size))

func chunk_key(coord: Vector2i) -> String:
	return "%d:%d" % [coord.x, coord.y]
