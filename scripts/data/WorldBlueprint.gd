class_name WorldBlueprint
extends Resource

const DEPTH_PROFILE_POINT_COUNT := 5
const SURFACE_DEPTH_METERS := 8.0
const MAXIMUM_DEPTH_METERS := 160.0

@export var campaign_seed: int = 1
## Runtime snapshot compiled from the workbench map_manifest.json through the
## generated UnderwaterMap.tscn. The manifest is semantic authority; the scene
## is its deterministic derivative.
@export var map_source_version: int = 0
@export var map_id: String = ""
@export var map_gameplay_signature: String = ""
@export var world_size: Vector2 = Vector2.ZERO
## Compiled copy of the manifest-owned curve: x is normalized global Y, y is
## physical depth in metres. Region membership never participates in sampling.
@export var depth_profile_points: PackedVector2Array = default_depth_profile_points()
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
	depth_profile_points.clear()
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

func depth_at(world_position: Vector2) -> float:
	return depth_at_world_y(depth_profile_points, world_size.y, world_position.y)

static func default_depth_profile_points() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, SURFACE_DEPTH_METERS),
		Vector2(0.237, 35.0),
		Vector2(0.401, 70.0),
		Vector2(0.607, 115.0),
		Vector2(1.0, MAXIMUM_DEPTH_METERS),
	])

static func depth_profile_validation_errors(points: PackedVector2Array) -> PackedStringArray:
	var errors := PackedStringArray()
	if points.size() != DEPTH_PROFILE_POINT_COUNT:
		errors.append(
			"Profil musi zawierać dokładnie %d punktów (proporcja wysokości, metry)."
			% DEPTH_PROFILE_POINT_COUNT
		)
		return errors
	for index in range(points.size()):
		var point := points[index]
		if not is_finite(point.x) or not is_finite(point.y):
			errors.append("Punkt %d profilu zawiera wartość niefinitywną." % index)
			continue
		if point.x < 0.0 or point.x > 1.0:
			errors.append("Punkt %d profilu musi mieć proporcję wysokości w zakresie 0..1." % index)
		if index > 0:
			var previous := points[index - 1]
			if point.x <= previous.x:
				errors.append("Proporcje wysokości profilu muszą być ściśle rosnące.")
			if point.y <= previous.y:
				errors.append("Głębokość profilu musi być ściśle rosnąca.")
	if not is_equal_approx(points[0].x, 0.0):
		errors.append("Pierwszy punkt profilu musi zaczynać się przy proporcji 0.")
	if not is_equal_approx(points[0].y, SURFACE_DEPTH_METERS):
		errors.append("Pierwszy punkt profilu musi mieć głębokość %.1f m." % SURFACE_DEPTH_METERS)
	var last := points[points.size() - 1]
	if not is_equal_approx(last.x, 1.0):
		errors.append("Ostatni punkt profilu musi kończyć się przy proporcji 1.")
	if not is_equal_approx(last.y, MAXIMUM_DEPTH_METERS):
		errors.append("Ostatni punkt profilu musi mieć głębokość %.1f m." % MAXIMUM_DEPTH_METERS)
	return errors

static func depth_at_world_y(
	points: PackedVector2Array,
	world_height: float,
	world_y: float
) -> float:
	var profile := points
	if profile.size() < 2:
		profile = default_depth_profile_points()
	var normalized_y := clampf(world_y / maxf(world_height, 1.0), 0.0, 1.0)
	if normalized_y <= profile[0].x:
		return profile[0].y
	for index in range(1, profile.size()):
		var previous := profile[index - 1]
		var current := profile[index]
		if normalized_y > current.x:
			continue
		var segment_ratio := clampf(
			(normalized_y - previous.x) / maxf(current.x - previous.x, 0.000001),
			0.0,
			1.0
		)
		return lerpf(previous.y, current.y, segment_ratio)
	return profile[profile.size() - 1].y

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
