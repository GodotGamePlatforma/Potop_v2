@tool
class_name DiveMapObject
extends Node2D

## A visible, editor-authored map object. Designers place instances of the
## supplied prefab scenes directly in UnderwaterMap.tscn, configure gameplay
## data through the Inspector and may attach a presentation-only PackedScene.
## The map compiler converts these nodes into a runtime WorldBlueprint.
enum Kind {
	LANDMARK,
	ENTRY_POINT,
	EXIT_LINE,
	LOOT_CONTAINER,
	PICKUP,
	CURRENT_ZONE,
	THREAT,
	HEAVY_OBJECT,
	RESCUE,
	BUOY,
	SHORTCUT_GATE,
	OBSTACLE,
	DECORATION,
	REGION,
	FIXED_DEVICE,
}

const PREVIEW_META := &"underwater_map_visual_preview"
const MAP_CONNECTION_SCRIPT_PATH := "res://scripts/diving/DiveMapConnection.gd"
const OBSTACLE_POLYGON_NODE_PATH := ^"NavigationPolygon"
const MIN_VISUAL_SCALE := 0.001

@export_group("Identity")
@export var kind: Kind = Kind.DECORATION:
	set(value):
		kind = value
		notify_property_list_changed()
		queue_redraw()
		update_configuration_warnings()
@export var object_id: String = "":
	set(value):
		object_id = value.strip_edges()
		queue_redraw()
		update_configuration_warnings()
@export var display_name: String = "":
	set(value):
		display_name = value
		queue_redraw()
@export_multiline var designer_notes: String = ""

@export_group("Map")
@export var region_id: String = ""
@export var linked_object_id: String = ""
@export var bounds_size: Vector2 = Vector2(180.0, 120.0):
	set(value):
		bounds_size = Vector2(maxf(absf(value.x), 8.0), maxf(absf(value.y), 8.0))
		queue_redraw()
@export var depth_range: Vector2 = Vector2.ZERO
@export var accent_color: Color = Color("68c9ee"):
	set(value):
		accent_color = value
		queue_redraw()
@export var water_color: Color = Color("075b7e")
@export var landmark_role: String = ""
@export var visual_kind: String = ""
@export var aliases: PackedStringArray = PackedStringArray()
@export var anchor_id: String = ""

@export_group("Interaction")
@export var contents: Dictionary = {}
@export var pickup_item: ItemDefinition
@export_range(1, 99, 1) var pickup_amount: int = 1
@export var required_tool: String = ""
@export var interaction_action: String = "open"
@export_range(0.0, 30.0, 0.05) var interaction_seconds: float = 1.15
@export var mandatory_order: int = -1
@export var difficulty_scaled_contents: bool = true
@export var disease_id: String = ""
@export_range(0, 20, 1) var disease_exposure_pressure: int = 0

@export_group("Specialised gameplay")
@export var current_velocity: Vector2 = Vector2.ZERO:
	set(value):
		current_velocity = value
		queue_redraw()
@export var threat_definition: DiveThreatDefinition
@export var rescue_definition: RescueEncounterDefinition
@export var gate_width: float = 170.0
@export var device_role: String = ""
@export_range(1, 999, 1) var available_from_day: int = 1
@export var blocks_navigation: bool = true

@export_group("Visual prefab")
## Presentation only. Gameplay collision and interactions remain owned by this
## authoring node and its exported fields, never by nodes inside visual_scene.
@export var visual_scene: PackedScene:
	set(value):
		visual_scene = value
		_queue_preview_refresh()
		update_configuration_warnings()
@export var visual_offset: Vector2 = Vector2.ZERO:
	set(value):
		visual_offset = value
		_queue_preview_refresh()
@export_range(-360.0, 360.0, 0.1) var visual_rotation_degrees: float = 0.0:
	set(value):
		visual_rotation_degrees = value
		_queue_preview_refresh()
@export var visual_scale: Vector2 = Vector2.ONE:
	set(value):
		visual_scale = _safe_visual_scale(value)
		_queue_preview_refresh()
		update_configuration_warnings()
@export_range(-4096, 4096, 1) var visual_z_index: int = 0:
	set(value):
		visual_z_index = value
		_queue_preview_refresh()
@export var preview_visual_in_editor: bool = true:
	set(value):
		preview_visual_in_editor = value
		_queue_preview_refresh()
@export var show_authoring_marker: bool = true:
	set(value):
		show_authoring_marker = value
		queue_redraw()

var _preview_instance: Node2D
var _preview_refresh_queued := false


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		var polygon_node := _obstacle_polygon_node()
		if polygon_node != null and not polygon_node.item_rect_changed.is_connected(_on_obstacle_polygon_changed):
			polygon_node.item_rect_changed.connect(_on_obstacle_polygon_changed)
		_queue_preview_refresh()


func _exit_tree() -> void:
	_preview_refresh_queued = false
	_clear_visual_preview()


func kind_id() -> String:
	match kind:
		Kind.LANDMARK:
			return "landmark"
		Kind.ENTRY_POINT:
			return "entry_point"
		Kind.EXIT_LINE:
			return "exit_line"
		Kind.LOOT_CONTAINER:
			return "loot_container"
		Kind.PICKUP:
			return "pickup"
		Kind.CURRENT_ZONE:
			return "current_zone"
		Kind.THREAT:
			return "threat"
		Kind.HEAVY_OBJECT:
			return "heavy_object"
		Kind.RESCUE:
			return "rescue"
		Kind.BUOY:
			return "buoy"
		Kind.SHORTCUT_GATE:
			return "shortcut_gate"
		Kind.FIXED_DEVICE:
			return "fixed_device"
		Kind.OBSTACLE:
			return "obstacle"
		Kind.DECORATION:
			return "decoration"
		Kind.REGION:
			return "region"
	return "unknown"


func authored_world_polygon() -> PackedVector2Array:
	var authored_polygon := _authored_local_obstacle_polygon()
	if authored_polygon.size() >= 3:
		var transformed := PackedVector2Array()
		for point in authored_polygon:
			transformed.append(global_transform * point)
		return transformed
	var half := bounds_size * 0.5
	return PackedVector2Array([
		global_transform * Vector2(-half.x, -half.y),
		global_transform * Vector2(half.x, -half.y),
		global_transform * Vector2(half.x, half.y),
		global_transform * Vector2(-half.x, half.y),
	])


func authored_world_bounds() -> Rect2:
	var polygon := authored_world_polygon()
	if polygon.is_empty():
		return Rect2(global_position, Vector2.ZERO)
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for index in range(1, polygon.size()):
		bounds = bounds.expand(polygon[index])
	return bounds


func visual_record_fields() -> Dictionary:
	return {
		"visual_scene_path": visual_scene.resource_path if visual_scene != null else "",
		"visual_offset": visual_offset,
		"visual_rotation": deg_to_rad(visual_rotation_degrees),
		"visual_scale": visual_scale,
		"visual_z_index": visual_z_index,
		"visual_object_rotation": global_rotation,
		"visual_object_scale": global_scale,
		"visual_object_skew": global_skew,
	}


func refresh_editor_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	_clear_visual_preview()
	if not preview_visual_in_editor or visual_scene == null:
		return
	var scene_errors := visual_scene_validation_errors()
	if not scene_errors.is_empty():
		return
	var candidate := visual_scene.instantiate()
	if not (candidate is Node2D):
		if candidate != null:
			candidate.free()
		return
	# Keep the prefab root's own transform intact.  The internal anchor carries
	# only the offset/rotation/scale authored on the map object.
	_preview_instance = Node2D.new()
	_preview_instance.name = "__VisualPreview"
	_preview_instance.set_meta(PREVIEW_META, true)
	_preview_instance.position = visual_offset
	_preview_instance.rotation = deg_to_rad(visual_rotation_degrees)
	_preview_instance.scale = visual_scale
	_preview_instance.z_index = visual_z_index
	_preview_instance.process_mode = Node.PROCESS_MODE_DISABLED
	_preview_instance.add_child(candidate)
	# Internal, ownerless children are visible in the 2D viewport but are never
	# serialized into UnderwaterMap.tscn.
	add_child(_preview_instance, false, Node.INTERNAL_MODE_FRONT)


func visual_scene_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if visual_scene == null:
		return errors
	if visual_scene.resource_path.is_empty():
		errors.append("Prefab wizualny musi być zapisanym zasobem .tscn.")
		return errors
	var candidate := visual_scene.instantiate()
	if not (candidate is Node2D):
		if candidate != null:
			candidate.free()
		errors.append("Prefab wizualny musi mieć root Node2D.")
		return errors
	var nodes: Array[Node] = []
	nodes.append(candidate)
	nodes.append_array(candidate.find_children("*", "", true, false))
	for node in nodes:
		var node_script := node.get_script() as Script
		var node_script_path := node_script.resource_path if node_script != null else ""
		if node is DiveMapObject or node_script_path == MAP_CONNECTION_SCRIPT_PATH:
			errors.append("Prefab wizualny nie może zawierać węzłów authoringu mapy.")
			break
		if node is CollisionObject2D or node is CollisionShape2D or node is CollisionPolygon2D:
			errors.append("Prefab wizualny nie może zawierać kolizji; użyj MapObstacle i Bounds Size.")
			break
	candidate.free()
	return errors


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if object_id.is_empty():
		warnings.append("Ten obiekt wymaga unikalnego Object ID.")
	if display_name.strip_edges().is_empty():
		warnings.append("Dodaj czytelną nazwę Display Name dla authoringu i diagnostyki.")
	match kind:
		Kind.LANDMARK:
			if region_id.is_empty():
				warnings.append("Landmark powinien wskazywać istniejący Region ID.")
		Kind.ENTRY_POINT, Kind.BUOY, Kind.SHORTCUT_GATE:
			if linked_object_id.is_empty():
				warnings.append("Ten obiekt wymaga Linked Object ID.")
		Kind.LOOT_CONTAINER:
			if contents.is_empty():
				warnings.append("Kontener nie ma skonfigurowanej zawartości.")
		Kind.PICKUP:
			if pickup_item == null:
				warnings.append("Pickup wymaga przypisanej definicji itemu.")
			if pickup_amount != 1:
				warnings.append("Wolnostojący pickup musi reprezentować dokładnie jedną sztukę.")
		Kind.THREAT:
			if threat_definition == null:
				warnings.append("Zagrożenie wymaga definicji threatu.")
		Kind.RESCUE:
			if rescue_definition == null:
				warnings.append("Obiekt ratunku wymaga definicji ocalałego.")
		Kind.OBSTACLE:
			if blocks_navigation and visual_scene == null:
				warnings.append("Przeszkoda bez Visual Scene jest niewidoczną korektą bazowej maski; przypisz prefab dla nowego widocznego obiektu.")
		Kind.DECORATION:
			if visual_scene == null:
				warnings.append("Dekoracja wymaga Visual Scene, inaczej nie pojawi się w runtime.")
	for visual_error in visual_scene_validation_errors():
		warnings.append(visual_error)
	return warnings


func _validate_property(property: Dictionary) -> void:
	var property_name := str(property.get("name", ""))
	var visible := true
	match property_name:
		"region_id":
			visible = kind == Kind.LANDMARK
		"linked_object_id":
			visible = kind in [
				Kind.ENTRY_POINT,
				Kind.LOOT_CONTAINER,
				Kind.PICKUP,
				Kind.BUOY,
				Kind.SHORTCUT_GATE,
				Kind.FIXED_DEVICE,
			]
		"bounds_size":
			visible = kind in [Kind.LANDMARK, Kind.CURRENT_ZONE, Kind.OBSTACLE, Kind.REGION]
		"depth_range", "accent_color", "water_color":
			visible = kind == Kind.REGION
		"landmark_role", "visual_kind", "aliases", "anchor_id":
			visible = kind == Kind.LANDMARK
		"contents":
			visible = kind in [Kind.LOOT_CONTAINER, Kind.HEAVY_OBJECT]
		"pickup_item", "pickup_amount":
			visible = kind == Kind.PICKUP
		"required_tool", "interaction_action", "interaction_seconds":
			visible = kind in [
				Kind.LOOT_CONTAINER,
				Kind.PICKUP,
				Kind.HEAVY_OBJECT,
				Kind.RESCUE,
				Kind.BUOY,
				Kind.SHORTCUT_GATE,
			]
		"mandatory_order", "difficulty_scaled_contents", "disease_id", "disease_exposure_pressure":
			visible = kind == Kind.LOOT_CONTAINER
		"current_velocity":
			visible = kind == Kind.CURRENT_ZONE
		"threat_definition":
			visible = kind == Kind.THREAT
		"rescue_definition":
			visible = kind == Kind.RESCUE
		"gate_width":
			visible = kind == Kind.SHORTCUT_GATE
		"blocks_navigation":
			visible = kind == Kind.OBSTACLE
	if not visible:
		property["usage"] = PROPERTY_USAGE_NONE


func _draw() -> void:
	if not Engine.is_editor_hint() or not show_authoring_marker:
		return
	var color := _marker_color()
	var fill_alpha := 0.08 if visual_scene != null and preview_visual_in_editor else 0.18
	if kind == Kind.REGION:
		fill_alpha = 0.035
	elif kind in [Kind.LANDMARK, Kind.CURRENT_ZONE]:
		fill_alpha = minf(fill_alpha, 0.10)
	match kind:
		Kind.LANDMARK, Kind.CURRENT_ZONE, Kind.REGION:
			draw_rect(Rect2(-bounds_size * 0.5, bounds_size), Color(color.r, color.g, color.b, fill_alpha), true)
			draw_rect(Rect2(-bounds_size * 0.5, bounds_size), color, false, 3.0)
		Kind.OBSTACLE:
			var authored_polygon := _authored_local_obstacle_polygon()
			if authored_polygon.size() >= 3:
				draw_colored_polygon(authored_polygon, Color(color.r, color.g, color.b, maxf(fill_alpha, 0.24)))
				var outline := authored_polygon.duplicate()
				outline.append(authored_polygon[0])
				draw_polyline(outline, color, 4.0, true)
			else:
				draw_rect(Rect2(-bounds_size * 0.5, bounds_size), Color(color.r, color.g, color.b, maxf(fill_alpha, 0.24)), true)
				draw_rect(Rect2(-bounds_size * 0.5, bounds_size), color, false, 4.0)
				draw_line(-bounds_size * 0.5, bounds_size * 0.5, color, 2.0)
				draw_line(Vector2(bounds_size.x * 0.5, -bounds_size.y * 0.5), Vector2(-bounds_size.x * 0.5, bounds_size.y * 0.5), color, 2.0)
		Kind.ENTRY_POINT:
			var entry_points := PackedVector2Array([Vector2(0, -38), Vector2(34, 28), Vector2(-34, 28)])
			draw_colored_polygon(entry_points, Color(color.r, color.g, color.b, 0.28))
			draw_polyline(PackedVector2Array([entry_points[0], entry_points[1], entry_points[2], entry_points[0]]), color, 3.0, true)
		Kind.EXIT_LINE:
			draw_line(Vector2(0, -44), Vector2(0, 44), color, 5.0)
			draw_circle(Vector2(0, -44), 11.0, Color(color.r, color.g, color.b, 0.35))
			draw_arc(Vector2(0, -44), 11.0, 0.0, TAU, 24, color, 3.0, true)
		_:
			draw_circle(Vector2.ZERO, 34.0, Color(color.r, color.g, color.b, fill_alpha + 0.08))
			draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 28, color, 3.0, true)
	if kind == Kind.CURRENT_ZONE and current_velocity.length_squared() > 0.01:
		var arrow := current_velocity.normalized() * minf(maxf(current_velocity.length(), 90.0), 220.0)
		draw_line(Vector2.ZERO, arrow, color, 5.0, true)
		draw_line(arrow, arrow - arrow.normalized().rotated(0.55) * 24.0, color, 5.0, true)
		draw_line(arrow, arrow - arrow.normalized().rotated(-0.55) * 24.0, color, 5.0, true)
	var label := display_name if not display_name.is_empty() else object_id
	if not label.is_empty():
		var font := ThemeDB.fallback_font
		if font != null:
			var id_suffix := " [%s]" % object_id if not object_id.is_empty() and label != object_id else ""
			draw_string(font, Vector2(42.0, 5.0), label + id_suffix, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, color)


func _marker_color() -> Color:
	match kind:
		Kind.LANDMARK:
			return Color("68c9ee")
		Kind.ENTRY_POINT, Kind.EXIT_LINE:
			return Color("f3cf65")
		Kind.LOOT_CONTAINER, Kind.PICKUP:
			return Color("78d79b")
		Kind.CURRENT_ZONE, Kind.THREAT:
			return Color("e6806f")
		Kind.HEAVY_OBJECT, Kind.OBSTACLE:
			return Color("dca96a")
		Kind.RESCUE:
			return Color("d98ce1")
		Kind.BUOY, Kind.SHORTCUT_GATE:
			return Color("a6d8f0")
		Kind.REGION:
			return accent_color
	return Color("b5c1c4")


func _queue_preview_refresh() -> void:
	if not Engine.is_editor_hint() or _preview_refresh_queued:
		return
	_preview_refresh_queued = true
	call_deferred("_apply_queued_preview_refresh")


func _apply_queued_preview_refresh() -> void:
	_preview_refresh_queued = false
	if is_inside_tree():
		refresh_editor_preview()
	queue_redraw()


func _clear_visual_preview() -> void:
	if is_instance_valid(_preview_instance):
		if _preview_instance.get_parent() == self:
			remove_child(_preview_instance)
		_preview_instance.free()
	_preview_instance = null


func _safe_visual_scale(value: Vector2) -> Vector2:
	var result := value
	if absf(result.x) < MIN_VISUAL_SCALE:
		result.x = MIN_VISUAL_SCALE if result.x >= 0.0 else -MIN_VISUAL_SCALE
	if absf(result.y) < MIN_VISUAL_SCALE:
		result.y = MIN_VISUAL_SCALE if result.y >= 0.0 else -MIN_VISUAL_SCALE
	return result


func _authored_local_obstacle_polygon() -> PackedVector2Array:
	if kind != Kind.OBSTACLE:
		return PackedVector2Array()
	var polygon_node := _obstacle_polygon_node()
	if polygon_node == null or polygon_node.polygon.size() < 3:
		return PackedVector2Array()
	var authored_polygon := PackedVector2Array()
	for point in polygon_node.polygon:
		authored_polygon.append(polygon_node.transform * point)
	return authored_polygon


func _obstacle_polygon_node() -> Polygon2D:
	return get_node_or_null(OBSTACLE_POLYGON_NODE_PATH) as Polygon2D


func _on_obstacle_polygon_changed() -> void:
	queue_redraw()
	update_configuration_warnings()
