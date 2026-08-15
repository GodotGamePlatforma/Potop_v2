class_name WorldDelta
extends Resource

@export var active_landmark_id: String = ""
@export var discovered_landmarks: Array[String] = []
@export var discovered_chunks: Array[String] = []
@export var opened_containers: Array[String] = []
@export var collected_items: Array[String] = []
@export var remaining_container_contents: Dictionary = {}
@export var dead_divers: Dictionary = {}
@export var lost_backpacks: Dictionary = {}
@export var dropped_loot_piles: Dictionary = {}
@export var rescued_or_dead_survivors: Dictionary = {}
@export var placed_buoys: Array[String] = []
@export var marked_heavy_objects: Array[String] = []
@export var recovered_heavy_objects: Array[String] = []
@export var opened_shortcuts: Array[String] = []
@export var activated_fixed_devices: Array[String] = []
@export var collapsed_paths: Array[String] = []
@export var depleted_biological_nodes: Dictionary = {}

func clear() -> void:
	active_landmark_id = ""
	discovered_landmarks.clear()
	discovered_chunks.clear()
	opened_containers.clear()
	collected_items.clear()
	remaining_container_contents.clear()
	dead_divers.clear()
	lost_backpacks.clear()
	dropped_loot_piles.clear()
	rescued_or_dead_survivors.clear()
	placed_buoys.clear()
	marked_heavy_objects.clear()
	recovered_heavy_objects.clear()
	opened_shortcuts.clear()
	activated_fixed_devices.clear()
	collapsed_paths.clear()
	depleted_biological_nodes.clear()
