class_name UnderwaterWorldState
extends Resource

const WorldBlueprintScript := preload("res://scripts/data/WorldBlueprint.gd")
const WorldDeltaScript := preload("res://scripts/data/WorldDelta.gd")

@export var blueprint: Resource = WorldBlueprintScript.new()
@export var delta: Resource = WorldDeltaScript.new()

var generated_seed: int:
	get:
		_ensure_data()
		return int(blueprint.campaign_seed)
	set(value):
		_ensure_data()
		blueprint.campaign_seed = value

var map_source_version: int:
	get:
		_ensure_data()
		return int(blueprint.map_source_version)
	set(value):
		_ensure_data()
		blueprint.map_source_version = value

var world_dimensions: Vector2i:
	get:
		_ensure_data()
		return Vector2i(blueprint.world_size)

var entry_sector_id: String:
	get:
		_ensure_data()
		return blueprint.entry_landmark_id

var active_sector_id: String:
	get:
		_ensure_data()
		return delta.active_landmark_id if not delta.active_landmark_id.is_empty() else blueprint.entry_landmark_id
	set(value):
		_ensure_data()
		var resolved: String = blueprint.resolve_landmark_id(value)
		delta.active_landmark_id = resolved if not resolved.is_empty() else blueprint.entry_landmark_id

var sector_blueprints: Array[Dictionary]:
	get:
		_ensure_data()
		return blueprint.landmarks

var sector_lookup: Dictionary:
	get:
		_ensure_data()
		return blueprint.landmark_lookup

var discovered_sectors: Array[String]:
	get:
		_ensure_data()
		return delta.discovered_landmarks

var opened_containers: Array[String]:
	get:
		_ensure_data()
		return delta.opened_containers

var collected_items: Array[String]:
	get:
		_ensure_data()
		return delta.collected_items

var remaining_container_contents: Dictionary:
	get:
		_ensure_data()
		return delta.remaining_container_contents

var dead_divers: Dictionary:
	get:
		_ensure_data()
		return delta.dead_divers

var lost_backpacks: Dictionary:
	get:
		_ensure_data()
		return delta.lost_backpacks

var dropped_loot_piles: Dictionary:
	get:
		_ensure_data()
		return delta.dropped_loot_piles
	set(value):
		_ensure_data()
		delta.dropped_loot_piles = value.duplicate(true)

var rescued_or_dead_survivors: Dictionary:
	get:
		_ensure_data()
		return delta.rescued_or_dead_survivors

var placed_buoys: Array[String]:
	get:
		_ensure_data()
		return delta.placed_buoys

var marked_heavy_objects: Array[String]:
	get:
		_ensure_data()
		return delta.marked_heavy_objects

var recovered_heavy_objects: Array[String]:
	get:
		_ensure_data()
		return delta.recovered_heavy_objects

var opened_shortcuts: Array[String]:
	get:
		_ensure_data()
		return delta.opened_shortcuts

var activated_fixed_devices: Array[String]:
	get:
		_ensure_data()
		return delta.activated_fixed_devices

var collapsed_paths: Array[String]:
	get:
		_ensure_data()
		return delta.collapsed_paths

var depleted_biological_nodes: Dictionary:
	get:
		_ensure_data()
		return delta.depleted_biological_nodes

func setup(seed_value: int) -> void:
	blueprint = WorldBlueprintScript.new()
	blueprint.campaign_seed = maxi(seed_value, 1)
	delta = WorldDeltaScript.new()
	delta.clear()

func sector_count() -> int:
	_ensure_data()
	return blueprint.landmarks.size()

func get_sector_blueprint(sector_id: String) -> Dictionary:
	_ensure_data()
	return blueprint.get_landmark(sector_id)

func get_stream_chunk_keys(world_position: Vector2, radius: Vector2i = Vector2i.ONE) -> Array[String]:
	_ensure_data()
	var result: Array[String] = []
	var center: Vector2i = blueprint.chunk_coord_at(world_position)
	var safe_radius := Vector2i(maxi(radius.x, 0), maxi(radius.y, 0))
	var safe_chunk_size := maxi(blueprint.chunk_size, 1)
	var grid_size := Vector2i(
		ceili(blueprint.world_size.x / float(safe_chunk_size)),
		ceili(blueprint.world_size.y / float(safe_chunk_size))
	)
	for y in range(center.y - safe_radius.y, center.y + safe_radius.y + 1):
		for x in range(center.x - safe_radius.x, center.x + safe_radius.x + 1):
			if x < 0 or y < 0 or x >= grid_size.x or y >= grid_size.y:
				continue
			result.append(blueprint.chunk_key(Vector2i(x, y)))
	return result

func _ensure_data() -> void:
	if blueprint == null:
		blueprint = WorldBlueprintScript.new()
	if delta == null:
		delta = WorldDeltaScript.new()
