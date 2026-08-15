@tool
class_name DiveMapConnection
extends Path2D

## Authored route between two landmark IDs. The curve and gameplay width are
## visible directly in the 2D editor; runtime receives a deterministic snapshot.
enum Kind {
	MAIN,
	SECONDARY,
	SHORTCUT,
}

@export_group("Identity")
@export var connection_id: String = "":
	set(value):
		connection_id = value.strip_edges()
		queue_redraw()
		update_configuration_warnings()
@export var display_name: String = "":
	set(value):
		display_name = value
		queue_redraw()
@export_multiline var designer_notes: String = ""

@export_group("Route")
@export var from_landmark_id: String = "":
	set(value):
		from_landmark_id = value.strip_edges()
		queue_redraw()
		update_configuration_warnings()
@export var to_landmark_id: String = "":
	set(value):
		to_landmark_id = value.strip_edges()
		queue_redraw()
		update_configuration_warnings()
@export var kind: Kind = Kind.MAIN:
	set(value):
		kind = value
		queue_redraw()
@export_range(40.0, 2000.0, 1.0) var width: float = 160.0:
	set(value):
		width = maxf(value, 40.0)
		queue_redraw()
@export var show_authoring_label: bool = true:
	set(value):
		show_authoring_label = value
		queue_redraw()

var _connected_curve: Curve2D


func _enter_tree() -> void:
	set_process(Engine.is_editor_hint())
	_sync_curve_signal()
	queue_redraw()


func _exit_tree() -> void:
	_disconnect_curve_signal()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and curve != _connected_curve:
		_sync_curve_signal()
		queue_redraw()


func kind_id() -> String:
	match kind:
		Kind.MAIN:
			return "main"
		Kind.SECONDARY:
			return "secondary"
		Kind.SHORTCUT:
			return "shortcut"
	return "main"


func authored_world_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	if curve != null and curve.point_count >= 2:
		var baked_points := curve.get_baked_points()
		if baked_points.size() < 2:
			for index in range(curve.point_count):
				points.append(to_global(curve.get_point_position(index)))
		else:
			for baked_point in baked_points:
				points.append(to_global(baked_point))
		return points
	var endpoints := _find_landmark_endpoints()
	var from_node := endpoints.get("from") as DiveMapObject
	var to_node := endpoints.get("to") as DiveMapObject
	if from_node == null or to_node == null:
		return points
	var from := from_node.global_position
	var to := to_node.global_position
	var direction := to - from
	var bend := direction.normalized().orthogonal() * minf(direction.length() * 0.08, 260.0)
	return PackedVector2Array([from, (from + to) * 0.5 + bend, to])


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if connection_id.is_empty():
		warnings.append("Połączenie wymaga unikalnego Connection ID.")
	if from_landmark_id.is_empty() or to_landmark_id.is_empty():
		warnings.append("Połączenie wymaga obu identyfikatorów landmarków.")
	elif from_landmark_id == to_landmark_id:
		warnings.append("Początek i koniec połączenia nie mogą wskazywać tego samego landmarku.")
	if curve != null and curve.point_count == 1:
		warnings.append("Krzywa połączenia potrzebuje co najmniej dwóch punktów albo powinna pozostać pusta dla trasy automatycznej.")
	if is_inside_tree() and not from_landmark_id.is_empty() and not to_landmark_id.is_empty():
		var endpoints := _find_landmark_endpoints()
		if endpoints.get("from") == null or endpoints.get("to") == null:
			warnings.append("Połączenie wskazuje landmark, którego nie ma w tej scenie.")
	return warnings


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var world_points := authored_world_points()
	if world_points.size() < 2:
		return
	var points := PackedVector2Array()
	for world_point in world_points:
		points.append(to_local(world_point))
	var color := _route_color()
	# The translucent band represents the actual gameplay width. The centerline
	# remains thin enough to edit control points comfortably.
	draw_polyline(points, Color(color.r, color.g, color.b, 0.12), width, true)
	draw_polyline(points, Color(color.r, color.g, color.b, 0.9), 4.0, true)
	draw_circle(points[0], 12.0, Color(color.r, color.g, color.b, 0.35))
	draw_circle(points[points.size() - 1], 12.0, Color(color.r, color.g, color.b, 0.35))
	if show_authoring_label:
		var font := ThemeDB.fallback_font
		if font != null:
			var label := display_name if not display_name.is_empty() else connection_id
			if not label.is_empty():
				draw_string(font, points[points.size() >> 1] + Vector2(18.0, -18.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, color)


func _route_color() -> Color:
	match kind:
		Kind.MAIN:
			return Color("68c9ee")
		Kind.SECONDARY:
			return Color("8ebbd1")
		Kind.SHORTCUT:
			return Color("f3cf65")
	return Color("68c9ee")


func _find_landmark_endpoints() -> Dictionary:
	var result := {"from": null, "to": null}
	var root_node: Node = self
	while root_node.get_parent() != null:
		root_node = root_node.get_parent()
	for node in root_node.find_children("*", "", true, false):
		if not (node is DiveMapObject):
			continue
		var map_object := node as DiveMapObject
		if map_object.kind != DiveMapObject.Kind.LANDMARK:
			continue
		if map_object.object_id == from_landmark_id:
			result["from"] = map_object
		if map_object.object_id == to_landmark_id:
			result["to"] = map_object
		if result["from"] != null and result["to"] != null:
			break
	return result


func _sync_curve_signal() -> void:
	_disconnect_curve_signal()
	_connected_curve = curve
	if _connected_curve != null and not _connected_curve.changed.is_connected(_on_curve_changed):
		_connected_curve.changed.connect(_on_curve_changed)


func _disconnect_curve_signal() -> void:
	if _connected_curve != null and _connected_curve.changed.is_connected(_on_curve_changed):
		_connected_curve.changed.disconnect(_on_curve_changed)
	_connected_curve = null


func _on_curve_changed() -> void:
	queue_redraw()
	update_configuration_warnings()
