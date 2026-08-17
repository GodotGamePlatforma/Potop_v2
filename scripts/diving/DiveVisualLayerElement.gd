@tool
class_name DiveVisualLayerElement
extends Node2D

enum ResourceKind {
	TEXTURE,
	PACKED_SCENE,
}

enum LoadPolicy {
	SCENE_RESIDENT,
	MANIFEST_STREAMED,
}

const ATTACHMENT_PATH := ^"Attachment"
const CANONICAL_SCRIPT_PATH := "res://scripts/diving/DiveVisualLayerElement.gd"
const VALID_QUALITY_IDS := [&"low", &"medium", &"high"]
const FORBIDDEN_GROUPS := [
	&"gameplay",
	&"interactable",
	&"persistent_world",
	&"world_object",
	&"collision",
]
const FORBIDDEN_VISUAL_NODE_CLASSES := [
	"CollisionObject2D", "CollisionShape2D", "CollisionPolygon2D",
	"Joint2D", "RayCast2D", "ShapeCast2D", "NavigationRegion2D",
	"NavigationLink2D", "NavigationObstacle2D", "CanvasLayer",
	# These built-ins do not need a script to mutate state outside the visual
	# element or the whole canvas. Reject them during SceneState preflight, before
	# instantiation can activate remotes, animation tracks or global modulation.
	"Camera2D", "AudioListener2D", "AudioStreamPlayer2D",
	"RemoteTransform2D", "CanvasModulate", "AnimationPlayer", "AnimationTree",
	"TileMap", "TileMapLayer", "VisibleOnScreenEnabler2D", "TouchScreenButton",
	"Control", "Parallax2D",
]

@export_group("Identity and source")
@export var element_id: StringName = &"":
	set(value):
		element_id = value
		_update_editor_warnings()
@export_enum("Texture", "PackedScene") var resource_kind: int = ResourceKind.TEXTURE:
	set(value):
		resource_kind = value
		_request_editor_preview_refresh()
@export_file var resource_path: String = "":
	set(value):
		resource_path = value
		_request_editor_preview_refresh()
@export_enum("Scene Resident", "Manifest Streamed") var load_policy: int = LoadPolicy.SCENE_RESIDENT:
	set(value):
		load_policy = value
		_update_editor_warnings()

@export_group("Texture presentation")
@export var local_bounds := Rect2():
	set(value):
		local_bounds = value
		_request_editor_preview_refresh()
@export var texture_region := Rect2():
	set(value):
		texture_region = value
		_request_editor_preview_refresh()
@export var centered := false:
	set(value):
		centered = value
		_request_editor_preview_refresh()
@export var visual_modulate := Color.WHITE:
	set(value):
		visual_modulate = value
		_request_editor_preview_refresh()

@export_group("Quality")
@export_enum("low", "medium", "high") var minimum_quality: String = "low":
	set(value):
		minimum_quality = value
		_apply_quality_visibility()
		_update_editor_warnings()

var _graphics_quality := "high"
var _runtime_content: Node
var _preview_refresh_queued := false


func _ready() -> void:
	_apply_quality_visibility()
	if Engine.is_editor_hint():
		_request_editor_preview_refresh()
	elif load_policy == LoadPolicy.SCENE_RESIDENT:
		ensure_scene_resident_resource_loaded()


func visual_local_bounds() -> Rect2:
	return local_bounds


func required_quality_level() -> int:
	return DiveVisualLayerProfile.quality_level(minimum_quality)


func is_enabled_for_quality(quality_id: String) -> bool:
	return DiveVisualLayerProfile.quality_level(quality_id) >= required_quality_level()


func set_graphics_quality(quality_id: String) -> void:
	_graphics_quality = DiveVisualLayerProfile.normalize_quality(quality_id)
	_apply_quality_visibility()


func is_manifest_streamed() -> bool:
	return load_policy == LoadPolicy.MANIFEST_STREAMED


func ensure_scene_resident_resource_loaded() -> bool:
	if load_policy != LoadPolicy.SCENE_RESIDENT:
		return false
	if runtime_content_node() != null:
		return true
	var normalized_path := resource_path.strip_edges()
	if normalized_path.is_empty() or not ResourceLoader.exists(normalized_path):
		push_error("Element scenowy %s wskazuje brakujący zasób %s." % [element_id, normalized_path])
		return false
	var resource := ResourceLoader.load(normalized_path)
	if resource == null:
		push_error("Nie można wczytać zasobu elementu scenowego %s: %s." % [element_id, normalized_path])
		return false
	return attach_runtime_resource(resource)


func attach_runtime_resource(resource: Resource) -> bool:
	detach_runtime_resource()
	var content: Node
	match resource_kind:
		ResourceKind.TEXTURE:
			var texture := resource as Texture2D
			if texture == null:
				push_error("Element %s oczekiwał Texture2D." % element_id)
				return false
			var texture_errors := _loaded_texture_validation_errors(texture)
			if not texture_errors.is_empty():
				for texture_error in texture_errors:
					push_error("Element %s: %s" % [element_id, texture_error])
				return false
			content = _build_texture_sprite(texture)
		ResourceKind.PACKED_SCENE:
			var packed_scene := resource as PackedScene
			if packed_scene == null:
				push_error("Element %s oczekiwał PackedScene." % element_id)
				return false
			var preflight_errors := packed_scene_preflight_validation_errors(packed_scene)
			if not preflight_errors.is_empty():
				for preflight_error in preflight_errors:
					push_error("Element %s: %s" % [element_id, preflight_error])
				return false
			content = packed_scene.instantiate()
			if not (content is Node2D):
				push_error("Element %s wymaga korzenia Node2D w PackedScene." % element_id)
				if content != null:
					content.free()
				return false
			var subtree_errors := visual_subtree_validation_errors(content)
			if not subtree_errors.is_empty():
				for subtree_error in subtree_errors:
					push_error("Element %s: %s" % [element_id, subtree_error])
				content.free()
				return false
		_:
			push_error("Element %s ma nieobsługiwany resource_kind %d." % [element_id, resource_kind])
			return false
	var attachment := _attachment_root()
	if attachment == null:
		push_error("Element %s nie ma węzła Attachment." % element_id)
		content.free()
		return false
	attachment.add_child(content)
	content.owner = null
	_runtime_content = content
	return true


func detach_runtime_resource() -> void:
	if _runtime_content == null or not is_instance_valid(_runtime_content):
		_runtime_content = null
		return
	var stale := _runtime_content
	_runtime_content = null
	var parent := stale.get_parent()
	if parent != null:
		parent.remove_child(stale)
	stale.free()


func runtime_content_node() -> Node:
	return _runtime_content if _runtime_content != null and is_instance_valid(_runtime_content) else null


func refresh_editor_preview() -> void:
	if Engine.is_editor_hint():
		_refresh_editor_preview()


func resource_content_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if resource_path.strip_edges().is_empty() or not ResourceLoader.exists(resource_path):
		return errors
	var extension := resource_path.get_extension().to_lower()
	var packed_scene_extensions := ResourceLoader.get_recognized_extensions_for_type("PackedScene")
	match resource_kind:
		ResourceKind.TEXTURE:
			# Imported images report concrete runtime classes (for example
			# CompressedTexture2D), so the Texture2D type hint plus a scene-extension
			# exclusion is the non-materializing check for sparse bitmap assets.
			if packed_scene_extensions.has(extension) and extension not in ["res", "tres"]:
				errors.append("Zasób %s nie jest Texture2D." % resource_path)
			elif extension in ["res", "tres"]:
				# Generic .res/.tres extensions can represent several Resource types.
				# Resolve only that ambiguous case and explicitly bypass the cache.
				var ambiguous_resource := ResourceLoader.load(
					resource_path,
					"Texture2D",
					ResourceLoader.CACHE_MODE_IGNORE_DEEP
				)
				if not (ambiguous_resource is Texture2D):
					errors.append("Zasób %s nie jest Texture2D." % resource_path)
			elif not ResourceLoader.exists(resource_path, "Texture2D"):
				errors.append("Zasób %s nie jest Texture2D." % resource_path)
		ResourceKind.PACKED_SCENE:
			if not packed_scene_extensions.has(extension):
				errors.append("Zasób %s nie jest PackedScene." % resource_path)
				return errors
			# A manifest-streamed scene stays unloaded until it becomes visible.
			# attach_runtime_resource() performs the same preflight before it may
			# instantiate. Scene-resident/editor content is validated eagerly.
			if load_policy == LoadPolicy.MANIFEST_STREAMED and not Engine.is_editor_hint():
				return errors
			var packed_scene := ResourceLoader.load(resource_path) as PackedScene
			if packed_scene == null:
				errors.append("Nie można wczytać PackedScene %s." % resource_path)
				return errors
			errors.append_array(packed_scene_preflight_validation_errors(packed_scene))
			if not errors.is_empty():
				return errors
			var content := packed_scene.instantiate()
			if not (content is Node2D):
				errors.append("PackedScene %s wymaga korzenia Node2D." % resource_path)
			else:
				errors.append_array(visual_subtree_validation_errors(content))
			if content != null:
				content.free()
	return errors


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var normalized_id := String(element_id).strip_edges()
	if normalized_id.is_empty():
		errors.append("Element warstwy wymaga stabilnego element_id.")
	if resource_kind < ResourceKind.TEXTURE or resource_kind > ResourceKind.PACKED_SCENE:
		errors.append("Element %s ma nieobsługiwany resource_kind." % normalized_id)
	if load_policy < LoadPolicy.SCENE_RESIDENT or load_policy > LoadPolicy.MANIFEST_STREAMED:
		errors.append("Element %s ma nieobsługiwany load_policy." % normalized_id)
	if resource_path.strip_edges().is_empty():
		errors.append("Element %s wymaga resource_path." % normalized_id)
	elif not resource_path.begins_with("res://"):
		errors.append("Element %s wymaga ścieżki res://." % normalized_id)
	elif not ResourceLoader.exists(resource_path):
		errors.append("Element %s wskazuje brakujący zasób %s." % [normalized_id, resource_path])
	if not _is_finite_rect(local_bounds) or local_bounds.size.x < 0.0 or local_bounds.size.y < 0.0:
		errors.append("Element %s ma niepoprawne local_bounds." % normalized_id)
	if not _is_finite_rect(texture_region) or texture_region.size.x < 0.0 or texture_region.size.y < 0.0:
		errors.append("Element %s ma niepoprawne texture_region." % normalized_id)
	if resource_kind == ResourceKind.TEXTURE and (local_bounds.size.x <= 0.0 or local_bounds.size.y <= 0.0):
		errors.append("Element teksturowy %s wymaga dodatnich local_bounds." % normalized_id)
	if load_policy == LoadPolicy.MANIFEST_STREAMED and (local_bounds.size.x <= 0.0 or local_bounds.size.y <= 0.0):
		errors.append("Element streamowany %s wymaga dodatnich local_bounds do cullingu." % normalized_id)
	if (
		resource_kind == ResourceKind.TEXTURE
		and texture_region.size.x > 0.0
		and texture_region.size.y > 0.0
		and not local_bounds.size.is_equal_approx(texture_region.size)
	):
		errors.append("Element teksturowy %s wymaga local_bounds.size zgodnego z texture_region.size." % normalized_id)
	if minimum_quality.strip_edges().to_lower() not in ["low", "medium", "high"]:
		errors.append("Element %s ma nieznany minimum_quality: %s." % [normalized_id, minimum_quality])
	if not _is_finite_transform():
		errors.append("Element %s ma niepoprawny transform." % normalized_id)
	if not z_as_relative or z_index != 0:
		errors.append("Element %s musi dziedziczyć pasmo z-order i mieć lokalny z_index = 0." % normalized_id)
	if top_level:
		errors.append("Element %s nie może używać top_level." % normalized_id)
	var attachment := _attachment_root()
	if attachment == null:
		errors.append("Element %s wymaga węzła Attachment typu Node2D." % normalized_id)
	else:
		if not _is_identity_node2d(attachment):
			errors.append("Element %s wymaga identity transform węzła Attachment." % normalized_id)
		if not attachment.z_as_relative or attachment.z_index != 0 or attachment.top_level:
			errors.append("Element %s wymaga Attachment dziedziczącego transform i z-order elementu." % normalized_id)
	errors.append_array(resource_content_validation_errors())
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func _get_configuration_warnings() -> PackedStringArray:
	return validation_errors()


static func visual_node_class_validation_errors(
	node_type: String,
	relative_path: String,
	require_node2d_root := false
) -> PackedStringArray:
	var errors := PackedStringArray()
	if node_type.is_empty():
		# SceneState uses an empty type for an instanced-scene placeholder. Its
		# concrete nodes are validated recursively through get_node_instance().
		return errors
	if not ClassDB.class_exists(node_type):
		errors.append("Węzeł wizualny %s nie może deklarować skryptu runtime przez typ %s." % [relative_path, node_type])
		return errors
	if require_node2d_root and not ClassDB.is_parent_class(node_type, "Node2D"):
		errors.append("PackedScene wymaga korzenia Node2D, a ma %s." % node_type)
	var forbidden_class := ""
	for candidate in FORBIDDEN_VISUAL_NODE_CLASSES:
		if ClassDB.is_parent_class(node_type, candidate):
			forbidden_class = candidate
			break
	if not forbidden_class.is_empty():
		errors.append("Niedozwolony typ %s w zasobie wizualnym pod %s." % [node_type, relative_path])
	elif not ClassDB.is_parent_class(node_type, "CanvasItem"):
		errors.append("Niedozwolony typ %s pod %s: każdy węzeł zasobu wizualnego musi dziedziczyć CanvasItem." % [node_type, relative_path])
	return errors


static func visual_node_validation_errors(
	node: Node,
	relative_path: String,
	allow_layer_element_script := false,
	require_node2d_root := false,
	require_canvas_parent := false
) -> PackedStringArray:
	var errors := PackedStringArray()
	if node == null:
		errors.append("Zasób wizualny nie utworzył węzła %s." % relative_path)
		return errors
	errors.append_array(visual_node_class_validation_errors(
		String(node.get_class()),
		relative_path,
		require_node2d_root
	))
	var node_script := node.get_script() as Script
	var canonical_layer_element_script := (
		allow_layer_element_script
		and node is DiveVisualLayerElement
		and node_script != null
		and node_script.resource_path == CANONICAL_SCRIPT_PATH
	)
	if node_script != null and not canonical_layer_element_script:
		errors.append("Węzeł wizualny %s nie może uruchamiać własnego skryptu runtime." % relative_path)
	if node is CanvasItem:
		var canvas_item := node as CanvasItem
		if not canvas_item.z_as_relative:
			errors.append("Węzeł wizualny %s musi dziedziczyć z-order warstwy (z_as_relative = true)." % relative_path)
		if canvas_item.z_index != 0:
			errors.append("Węzeł wizualny %s musi mieć lokalny z_index = 0; kolejność ustala drzewo warstwy." % relative_path)
		if canvas_item.top_level:
			errors.append("Węzeł wizualny %s nie może używać top_level, bo odłączyłby transform warstwy." % relative_path)
		if require_canvas_parent and not (node.get_parent() is CanvasItem):
			errors.append("Węzeł wizualny %s ma przerwane dziedziczenie CanvasItem przez zwykły Node." % relative_path)
	for group in node.get_groups():
		if group in FORBIDDEN_GROUPS:
			errors.append("Węzeł %s należy do niedozwolonej grupy %s." % [relative_path, group])
	return errors


static func visual_subtree_validation_errors(root: Node) -> PackedStringArray:
	var errors := PackedStringArray()
	if root == null:
		errors.append("Zasób wizualny nie utworzył korzenia sceny.")
		return errors
	_validate_visual_node(root, root, errors)
	return errors


static func packed_scene_preflight_validation_errors(packed_scene: PackedScene) -> PackedStringArray:
	var errors := PackedStringArray()
	if packed_scene == null:
		errors.append("Brak PackedScene do walidacji.")
		return errors
	_validate_scene_state(packed_scene.get_state(), errors, {})
	return errors


static func _validate_scene_state(state: SceneState, errors: PackedStringArray, visited: Dictionary) -> void:
	if state == null or visited.has(state.get_instance_id()):
		return
	visited[state.get_instance_id()] = true
	_validate_scene_state(state.get_base_scene_state(), errors, visited)
	for node_index in range(state.get_node_count()):
		var node_path := str(state.get_node_path(node_index))
		var node_type := String(state.get_node_type(node_index))
		# The same class allowlist is used for authored nodes and instantiated
		# runtime subtrees. SceneState lets us reject built-ins before _ready() or
		# any other initialization hook can run.
		errors.append_array(visual_node_class_validation_errors(node_type, node_path, node_index == 0))
		for group in state.get_node_groups(node_index):
			if group in FORBIDDEN_GROUPS:
				errors.append("Węzeł %s należy do niedozwolonej grupy %s." % [node_path, group])
		for property_index in range(state.get_node_property_count(node_index)):
			var property_name := state.get_node_property_name(node_index, property_index)
			var property_value = state.get_node_property_value(node_index, property_index)
			if property_value is Script:
				errors.append("Węzeł wizualny %s nie może deklarować skryptu runtime." % node_path)
			match property_name:
				&"script":
					if property_value != null and not (property_value is Script):
						errors.append("Węzeł wizualny %s nie może deklarować skryptu runtime." % node_path)
				&"z_as_relative":
					if not bool(property_value):
						errors.append("Węzeł wizualny %s musi mieć z_as_relative = true." % node_path)
				&"z_index":
					if int(property_value) != 0:
						errors.append("Węzeł wizualny %s musi mieć lokalny z_index = 0." % node_path)
				&"top_level":
					if bool(property_value):
						errors.append("Węzeł wizualny %s nie może używać top_level." % node_path)
		var nested_scene := state.get_node_instance(node_index)
		if nested_scene != null:
			_validate_scene_state(nested_scene.get_state(), errors, visited)


static func _validate_visual_node(root: Node, node: Node, errors: PackedStringArray) -> void:
	var relative_path := str(root.get_path_to(node))
	errors.append_array(visual_node_validation_errors(
		node,
		relative_path,
		false,
		node == root,
		node != root
	))
	for child in node.get_children():
		_validate_visual_node(root, child, errors)


func _build_texture_sprite(texture: Texture2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = "Visual"
	sprite.texture = texture
	sprite.centered = centered
	sprite.modulate = visual_modulate
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	if texture_region.size.x > 0.0 and texture_region.size.y > 0.0:
		sprite.region_enabled = true
		sprite.region_rect = texture_region
		sprite.region_filter_clip_enabled = false
	if centered:
		sprite.position = local_bounds.get_center()
	else:
		sprite.position = local_bounds.position
	return sprite


func _attachment_root() -> Node2D:
	return get_node_or_null(ATTACHMENT_PATH) as Node2D


func _loaded_texture_validation_errors(texture: Texture2D) -> PackedStringArray:
	var errors := PackedStringArray()
	if texture == null:
		return errors
	var texture_size := texture.get_size()
	if texture_region.size.x > 0.0 and texture_region.size.y > 0.0:
		var texture_rect := Rect2(Vector2.ZERO, texture_size)
		if not texture_rect.encloses(texture_region):
			errors.append("texture_region wychodzi poza rozmiar tekstury %s." % texture_size)
	if load_policy == LoadPolicy.MANIFEST_STREAMED:
		var drawn_size := texture_region.size if texture_region.size.x > 0.0 and texture_region.size.y > 0.0 else texture_size
		if not local_bounds.size.is_equal_approx(drawn_size):
			errors.append("local_bounds.size %s nie odpowiada rozmiarowi streamowanej grafiki %s." % [local_bounds.size, drawn_size])
	return errors


func _apply_quality_visibility() -> void:
	# The element's own CanvasItem.visible is authored scene state. Quality only
	# gates its attachment, so a deliberately hidden element is never re-enabled
	# by a quality or reduced-motion transition.
	var attachment := _attachment_root()
	if attachment != null:
		attachment.visible = is_enabled_for_quality(_graphics_quality)


func _request_editor_preview_refresh() -> void:
	_update_editor_warnings()
	if not Engine.is_editor_hint() or not is_inside_tree() or _preview_refresh_queued:
		return
	_preview_refresh_queued = true
	call_deferred("_refresh_editor_preview")


func _refresh_editor_preview() -> void:
	_preview_refresh_queued = false
	if not Engine.is_editor_hint():
		return
	detach_runtime_resource()
	if resource_path.strip_edges().is_empty() or not ResourceLoader.exists(resource_path):
		return
	var resource := ResourceLoader.load(resource_path)
	if resource == null:
		return
	attach_runtime_resource(resource)


func _update_editor_warnings() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		update_configuration_warnings()


func _is_finite_transform() -> bool:
	return (
		is_finite(position.x)
		and is_finite(position.y)
		and is_finite(rotation)
		and is_finite(scale.x)
		and is_finite(scale.y)
		and is_finite(skew)
		and not is_zero_approx(scale.x)
		and not is_zero_approx(scale.y)
	)


static func _is_identity_node2d(node: Node2D) -> bool:
	return (
		node.position.is_equal_approx(Vector2.ZERO)
		and is_zero_approx(node.rotation)
		and node.scale.is_equal_approx(Vector2.ONE)
		and is_zero_approx(node.skew)
	)


static func _is_finite_rect(value: Rect2) -> bool:
	return (
		is_finite(value.position.x)
		and is_finite(value.position.y)
		and is_finite(value.size.x)
		and is_finite(value.size.y)
	)
