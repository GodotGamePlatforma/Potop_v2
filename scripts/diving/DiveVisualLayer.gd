@tool
class_name DiveVisualLayer
extends Node2D

const SPACE_PARALLAX := &"parallax"
const SPACE_WORLD := &"world"
const BUCKET_AUTHORED := &"authored"
const BUCKET_GENERATED := &"generated"
const BUCKET_STREAMED := &"streamed"

const PARALLAX_ROOT_PATH := ^"ParallaxContent"
const WORLD_ROOT_PATH := ^"WorldContent"
const UNBOUNDED_PARALLAX_LIMIT_BEGIN := Vector2(-10_000_000.0, -10_000_000.0)
const UNBOUNDED_PARALLAX_LIMIT_END := Vector2(10_000_000.0, 10_000_000.0)

@export var profile: DiveVisualLayerProfile:
	set(value):
		_disconnect_profile()
		profile = value
		_connect_profile()
		_apply_profile(is_inside_tree())
		if is_inside_tree():
			update_configuration_warnings()

var _reduced_motion := false
var _graphics_quality := "high"
var _authored_scroll_offset := Vector2.ZERO
var _authored_scroll_offset_captured := false


func _ready() -> void:
	_connect_profile()
	_capture_authored_scroll_offset()
	_apply_profile(false)
	set_graphics_quality(_graphics_quality)


func layer_id() -> StringName:
	return profile.layer_id if profile != null else StringName(name)


func content_root(coordinate_space: StringName, bucket: StringName) -> Node2D:
	var space_root: Node2D
	match coordinate_space:
		SPACE_PARALLAX:
			space_root = get_node_or_null(PARALLAX_ROOT_PATH) as Parallax2D
		SPACE_WORLD:
			space_root = get_node_or_null(WORLD_ROOT_PATH) as Node2D
		_:
			return null
	if space_root == null:
		return null
	var child_name := ""
	match bucket:
		BUCKET_AUTHORED:
			child_name = "Authored"
		BUCKET_GENERATED:
			child_name = "Generated"
		BUCKET_STREAMED:
			child_name = "Streamed"
		_:
			return null
	return space_root.get_node_or_null(child_name) as Node2D


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_apply_profile(true)


func reduced_motion_enabled() -> bool:
	return _reduced_motion


func set_graphics_quality(quality_id: String) -> void:
	_graphics_quality = DiveVisualLayerProfile.normalize_quality(quality_id)
	var required_level := profile.minimum_quality_level() if profile != null else 0
	# Keep this wrapper's native visibility as authored scene state. The two
	# content roots are infrastructure quality gates, so quality changes cannot
	# accidentally re-enable a layer hidden by an artist.
	var quality_visible := DiveVisualLayerProfile.quality_level(_graphics_quality) >= required_level
	var parallax_content := get_node_or_null(PARALLAX_ROOT_PATH) as CanvasItem
	var world_content := get_node_or_null(WORLD_ROOT_PATH) as CanvasItem
	if parallax_content != null:
		parallax_content.visible = quality_visible
	if world_content != null:
		world_content.visible = quality_visible
	for element in _element_nodes():
		element.set_graphics_quality(_graphics_quality)


func graphics_quality() -> String:
	return _graphics_quality


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if not _is_identity_transform(self):
		errors.append("Wrapper warstwy %s musi zachować identity transform; przesuwaj elementy wewnątrz Authored." % name)
	if top_level:
		errors.append("Wrapper warstwy %s nie może używać top_level." % name)
	if profile == null:
		errors.append("Węzeł %s nie ma DiveVisualLayerProfile." % name)
	else:
		for profile_error in profile.validation_errors():
			errors.append("%s: %s" % [name, profile_error])
		if StringName(name) != profile.layer_id:
			errors.append("Nazwa wrappera %s musi być identyczna z layer_id %s." % [name, profile.layer_id])
	var parallax := get_node_or_null(PARALLAX_ROOT_PATH)
	if not (parallax is Parallax2D):
		errors.append("Warstwa %s wymaga ParallaxContent typu Parallax2D." % name)
	else:
		var parallax_node := parallax as Parallax2D
		if parallax_node.repeat_size != Vector2.ZERO:
			errors.append("Warstwa %s musi mieć wyłączone repeat_size." % name)
		if parallax_node.autoscroll != Vector2.ZERO:
			errors.append("Warstwa %s musi mieć wyłączony autoscroll." % name)
		if parallax_node.ignore_camera_scroll:
			errors.append("Warstwa %s musi śledzić przesunięcie kamery." % name)
		if not parallax_node.follow_viewport:
			errors.append("Warstwa %s musi mieć follow_viewport = true." % name)
		var authored_scroll_offset := parallax_node.scroll_offset
		if not Engine.is_editor_hint() and _authored_scroll_offset_captured:
			authored_scroll_offset = _authored_scroll_offset
		if not authored_scroll_offset.is_equal_approx(Vector2.ZERO):
			errors.append("Warstwa %s wymaga autorskiego scroll_offset = Vector2.ZERO; przesunięcie kompensacyjne należy wyłącznie do runtime." % name)
		if (
			not parallax_node.limit_begin.is_equal_approx(UNBOUNDED_PARALLAX_LIMIT_BEGIN)
			or not parallax_node.limit_end.is_equal_approx(UNBOUNDED_PARALLAX_LIMIT_END)
		):
			errors.append("Warstwa %s wymaga domyślnych nieaktywnych limitów Parallax2D, aby przełączanie reduced motion było ciągłe." % name)
		if not _has_inherited_z_order(parallax_node):
			errors.append("Warstwa %s wymaga ParallaxContent dziedziczącego transform i lokalny z-order." % name)
		if not _has_identity_orientation(parallax_node):
			errors.append("Warstwa %s wymaga ParallaxContent bez autorskiego obrotu, skali i skew." % name)
	var world := get_node_or_null(WORLD_ROOT_PATH)
	if not (world is Node2D) or world is Parallax2D:
		errors.append("Warstwa %s wymaga WorldContent typu Node2D." % name)
	elif not _is_identity_infrastructure(world as Node2D):
		errors.append("Warstwa %s wymaga WorldContent z identity transform i dziedziczonym z-order." % name)
	for coordinate_space in [SPACE_PARALLAX, SPACE_WORLD]:
		for bucket in [BUCKET_AUTHORED, BUCKET_GENERATED, BUCKET_STREAMED]:
			var bucket_root := content_root(coordinate_space, bucket)
			if bucket_root == null:
				errors.append("Warstwa %s nie ma kontenera %s/%s." % [name, coordinate_space, bucket])
			elif not _is_identity_infrastructure(bucket_root):
				errors.append("Warstwa %s wymaga identity transform i dziedziczonego z-order dla %s/%s." % [name, coordinate_space, bucket])
	var authored_roots: Array[Node2D] = []
	for coordinate_space in [SPACE_PARALLAX, SPACE_WORLD]:
		var authored_root := content_root(coordinate_space, BUCKET_AUTHORED)
		if authored_root != null:
			authored_roots.append(authored_root)
			_validate_authored_visual_tree(authored_root, authored_root, errors)
	for element in _element_nodes():
		var belongs_to_authored := false
		for authored_root in authored_roots:
			if authored_root == element.get_parent() or authored_root.is_ancestor_of(element):
				belongs_to_authored = true
				break
		if not belongs_to_authored:
			errors.append("%s/%s: DiveVisualLayerElement musi należeć do ParallaxContent/Authored albo WorldContent/Authored." % [name, element.name])
		for element_error in element.validation_errors():
			errors.append("%s/%s: %s" % [name, element.name, element_error])
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func presentation_state() -> Dictionary:
	var parallax := get_node_or_null(PARALLAX_ROOT_PATH) as Parallax2D
	var bucket_counts := {}
	for coordinate_space in [SPACE_PARALLAX, SPACE_WORLD]:
		for bucket in [BUCKET_AUTHORED, BUCKET_GENERATED, BUCKET_STREAMED]:
			var root := content_root(coordinate_space, bucket)
			bucket_counts["%s/%s" % [coordinate_space, bucket]] = root.get_child_count() if root != null else -1
	return {
		"layer_id": String(layer_id()),
		"role": profile.role if profile != null else "",
		"z_index": z_index,
		"normal_scroll_scale": profile.normal_scroll_scale if profile != null else Vector2.ONE,
		"reduced_motion_scroll_scale": profile.reduced_motion_scroll_scale if profile != null else Vector2.ONE,
		"scroll_scale": parallax.scroll_scale if parallax != null else Vector2.ONE,
		"scroll_offset": parallax.scroll_offset if parallax != null else Vector2.ZERO,
		"world_locked": profile.world_locked if profile != null else false,
		"reduced_motion": _reduced_motion,
		"graphics_quality": _graphics_quality,
		"visible": visible,
		"element_count": _element_nodes().size(),
		"bucket_counts": bucket_counts,
	}


func _get_configuration_warnings() -> PackedStringArray:
	return validation_errors()


func _apply_profile(compensate_offset: bool) -> void:
	if profile == null:
		return
	z_index = profile.z_index
	z_as_relative = false
	var parallax := get_node_or_null(PARALLAX_ROOT_PATH) as Parallax2D
	if parallax == null:
		return
	parallax.repeat_size = Vector2.ZERO
	parallax.autoscroll = Vector2.ZERO
	parallax.ignore_camera_scroll = false
	var target_scale := (
		profile.reduced_motion_scroll_scale
		if _reduced_motion
		else profile.normal_scroll_scale
	)
	if profile.world_locked:
		target_scale = Vector2.ONE
	var previous_scale := parallax.scroll_scale
	var editor_hint := Engine.is_editor_hint()
	var target_offset := _profile_application_scroll_offset(
		parallax.scroll_offset,
		previous_scale,
		target_scale,
		parallax.screen_offset,
		compensate_offset,
		editor_hint
	)
	# Godot computes Parallax2D from its exact, possibly snapped screen_offset.
	# Both setters can skip an internal refresh when the value is unchanged, so
	# finish with the exact repeat-free/unbounded position required by this stack.
	parallax.scroll_scale = target_scale
	parallax.scroll_offset = target_offset
	parallax.position = target_offset + parallax.screen_offset * (Vector2.ONE - target_scale)
	if editor_hint and compensate_offset:
		# A tool-time profile edit must never bake an editor viewport position into
		# the scene. It restores the only valid authored baseline instead.
		_authored_scroll_offset = Vector2.ZERO
		_authored_scroll_offset_captured = true


static func _profile_application_scroll_offset(
	current_offset: Vector2,
	previous_scale: Vector2,
	target_scale: Vector2,
	screen_offset: Vector2,
	compensate_offset: bool,
	editor_hint: bool
) -> Vector2:
	if editor_hint and compensate_offset:
		return Vector2.ZERO
	if compensate_offset and not previous_scale.is_equal_approx(target_scale):
		return current_offset + (target_scale - previous_scale) * screen_offset
	return current_offset


func _capture_authored_scroll_offset() -> void:
	var parallax := get_node_or_null(PARALLAX_ROOT_PATH) as Parallax2D
	if parallax == null:
		return
	_authored_scroll_offset = parallax.scroll_offset
	_authored_scroll_offset_captured = true


func _element_nodes() -> Array[DiveVisualLayerElement]:
	var result: Array[DiveVisualLayerElement] = []
	_collect_elements(self, result)
	return result


func _collect_elements(root: Node, result: Array[DiveVisualLayerElement]) -> void:
	for child in root.get_children():
		if child is DiveVisualLayerElement:
			result.append(child as DiveVisualLayerElement)
		_collect_elements(child, result)


func _validate_authored_visual_tree(root: Node, node: Node, errors: PackedStringArray) -> void:
	if node != root:
		var relative_path := str(root.get_path_to(node))
		var node_errors := DiveVisualLayerElement.visual_node_validation_errors(
			node,
			relative_path,
			node is DiveVisualLayerElement,
			false,
			true
		)
		for node_error in node_errors:
			errors.append("%s/Authored: %s" % [name, node_error])
	for child in node.get_children():
		_validate_authored_visual_tree(root, child, errors)


func _connect_profile() -> void:
	if profile == null:
		return
	var callback := Callable(self, "_on_profile_changed")
	if not profile.changed.is_connected(callback):
		profile.changed.connect(callback)


func _disconnect_profile() -> void:
	if profile == null:
		return
	var callback := Callable(self, "_on_profile_changed")
	if profile.changed.is_connected(callback):
		profile.changed.disconnect(callback)


func _on_profile_changed() -> void:
	_apply_profile(is_inside_tree())
	set_graphics_quality(_graphics_quality)
	update_configuration_warnings()


static func _is_identity_transform(node: Node2D) -> bool:
	return (
		node.position.is_equal_approx(Vector2.ZERO)
		and is_zero_approx(node.rotation)
		and node.scale.is_equal_approx(Vector2.ONE)
		and is_zero_approx(node.skew)
	)


static func _has_identity_orientation(node: Node2D) -> bool:
	return (
		is_zero_approx(node.rotation)
		and node.scale.is_equal_approx(Vector2.ONE)
		and is_zero_approx(node.skew)
	)


static func _has_inherited_z_order(node: CanvasItem) -> bool:
	return node.z_as_relative and node.z_index == 0 and not node.top_level


static func _is_identity_infrastructure(node: Node2D) -> bool:
	return _is_identity_transform(node) and _has_inherited_z_order(node)
