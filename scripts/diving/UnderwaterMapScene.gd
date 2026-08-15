@tool
class_name UnderwaterMapScene
extends Node2D

## The single authoring source for the underwater world. Designers work with
## normal Godot scene instances in the Scene Tree, Inspector and 2D viewport.
## Runtime never writes campaign progress back into this scene.
const MAP_COMPILER_PATH := "res://scripts/diving/UnderwaterMapSceneCompiler.gd"
const REQUIRED_AUTHORING_NODES := [
	"VisualLayers",
	"Terrain",
	"DepthRegions",
	"Landmarks",
	"Entries",
	"Routes",
	"CurrentZones",
	"Gameplay",
	"Gameplay/Containers",
	"Gameplay/Pickups",
	"Gameplay/Threats",
	"Gameplay/HeavyObjects",
	"Gameplay/RescueEncounters",
	"Gameplay/BuoyAnchors",
	"Gameplay/ShortcutGates",
	"StaticObstacles",
	"Decorations",
	"RuntimeDynamic",
]

@export_group("Map identity")
@export var map_id: String = "underwater_map":
	set(value):
		map_id = value.strip_edges()
		update_configuration_warnings()
@export var world_size: Vector2 = Vector2(11_520.0, 6_480.0):
	set(value):
		world_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		queue_redraw()
		update_configuration_warnings()
@export_range(64, 2048, 1) var chunk_size: int = 512:
	set(value):
		chunk_size = maxi(value, 64)
		queue_redraw()
@export var navigation_grid_texture: Texture2D:
	set(value):
		navigation_grid_texture = value
		update_configuration_warnings()

@export_group("Terrain presentation")
@export var terrain_render_sdf_texture: Texture2D:
	set(value):
		terrain_render_sdf_texture = value
		update_configuration_warnings()
@export var terrain_detail_texture: Texture2D:
	set(value):
		terrain_detail_texture = value
		update_configuration_warnings()
@export var terrain_visual_profiles: Array[Resource] = []:
	set(value):
		terrain_visual_profiles = value
		update_configuration_warnings()

@export_group("Authoring viewport")
@export var show_terrain_mask_preview: bool = true:
	set(value):
		show_terrain_mask_preview = value
		queue_redraw()
@export var show_world_bounds: bool = true:
	set(value):
		show_world_bounds = value
		queue_redraw()
@export var show_chunk_grid: bool = false:
	set(value):
		show_chunk_grid = value
		queue_redraw()
@export var world_bounds_color: Color = Color(0.42, 0.81, 0.91, 0.92):
	set(value):
		world_bounds_color = value
		queue_redraw()
@export var chunk_grid_color: Color = Color(0.42, 0.81, 0.91, 0.16):
	set(value):
		chunk_grid_color = value
		queue_redraw()

@export_group("Authoring actions")
@export_tool_button("Waliduj mapę", "Callable") var validate_map_action: Callable = validate_map_in_editor
@export_tool_button("Odśwież podglądy prefabów", "Reload") var refresh_previews_action: Callable = refresh_editor_previews

var _last_validation_errors := PackedStringArray()


func validate_map_in_editor() -> void:
	if not Engine.is_editor_hint():
		return
	_last_validation_errors.clear()
	var compiler_script := load(MAP_COMPILER_PATH) as Script
	if compiler_script == null:
		_last_validation_errors.append("Nie można załadować kompilatora mapy.")
	else:
		var compiler = compiler_script.new()
		var result: Dictionary = compiler.compile_map(self, 1)
		_last_validation_errors = result.get("errors", PackedStringArray())
	if _last_validation_errors.is_empty():
		print("[UnderwaterMap] Walidacja zakończona: scena jest gotowa do kompilacji runtime.")
	else:
		for validation_error in _last_validation_errors:
			push_error("[UnderwaterMap] %s" % validation_error)
	update_configuration_warnings()


func refresh_editor_previews() -> void:
	if not Engine.is_editor_hint():
		return
	var refreshed := 0
	for node in find_children("*", "", true, false):
		if node is DiveMapObject:
			(node as DiveMapObject).refresh_editor_preview()
			refreshed += 1
	print("[UnderwaterMap] Odświeżono podglądy prefabów: %d." % refreshed)
	queue_redraw()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if map_id.is_empty():
		warnings.append("Mapa wymaga stabilnego Map ID.")
	if navigation_grid_texture == null:
		warnings.append("Mapa wymaga bazowej tekstury nawigacji.")
	if terrain_render_sdf_texture == null:
		warnings.append("Mapa wymaga prezentacyjnego SDF wyprowadzonego z tekstury nawigacji.")
	elif navigation_grid_texture != null and terrain_render_sdf_texture.get_size() != navigation_grid_texture.get_size():
		warnings.append("Prezentacyjny SDF musi mieć rozmiar zgodny z teksturą nawigacji.")
	if terrain_detail_texture == null:
		warnings.append("Mapa wymaga prezentacyjnego materiału skał.")
	if terrain_visual_profiles.size() != 4:
		warnings.append("Mapa wymaga dokładnie czterech profili prezentacyjnych regionów.")
	else:
		for profile in terrain_visual_profiles:
			if profile == null:
				warnings.append("Profil prezentacyjny regionu nie może być pusty.")
				continue
			if profile.has_method("validation_errors"):
				for profile_error in profile.validation_errors():
					warnings.append("Profil prezentacyjny: %s" % profile_error)
	for required_path in REQUIRED_AUTHORING_NODES:
		if get_node_or_null(required_path) == null:
			warnings.append("Brakuje wymaganej grupy authoringu: %s." % required_path)
	for validation_error in _last_validation_errors:
		warnings.append("Walidacja: %s" % validation_error)
	return warnings


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if show_terrain_mask_preview and navigation_grid_texture != null:
		draw_texture_rect(navigation_grid_texture, Rect2(Vector2.ZERO, world_size), false, Color(0.14, 0.20, 0.22, 0.48), false)
	if show_chunk_grid:
		var safe_chunk_size := maxi(chunk_size, 1)
		var x := 0
		while x <= ceili(world_size.x):
			draw_line(Vector2(x, 0.0), Vector2(x, world_size.y), chunk_grid_color, 1.0)
			x += safe_chunk_size
		var y := 0
		while y <= ceili(world_size.y):
			draw_line(Vector2(0.0, y), Vector2(world_size.x, y), chunk_grid_color, 1.0)
			y += safe_chunk_size
	if show_world_bounds:
		draw_rect(Rect2(Vector2.ZERO, world_size), world_bounds_color, false, 5.0)
