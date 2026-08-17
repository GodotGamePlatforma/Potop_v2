class_name DiveVisualChunkStreamer
extends Node2D

## Streams presentation resources into authored DiveVisualLayerElement nodes.
## The composition scene owns every transform; the manifest is only a derived
## integrity/asset registry and never repositions schema-v2 elements.

const DEFAULT_MANIFEST_PATH := "res://assets/diving/world/map_v2/visual_chunks/map_visual_chunks_v2.json"
const DEFAULT_VISIBLE_HALF_EXTENT := Vector2(960.0, 540.0)
const DEFAULT_GRID_CHUNK_SIZE := 1024
const PREFETCH_RING_CHUNKS := 1
const UNLOAD_HYSTERESIS_CHUNKS := 1
const MAX_ATTACHES_PER_FRAME := 4
const MAX_REQUEST_ATTEMPTS_PER_RESIDENCE := 1
const EXPECTED_LAYER_IDS: Array[String] = [
	"L00_base_color",
	"L01_ultra_far_silhouettes",
	"L02_far_structures",
	"L03_mid_drift_props",
	"L04_near_terrain_skin",
	"L05_foreground_occluders",
]

@export_file("*.json") var manifest_path := DEFAULT_MANIFEST_PATH

var _visual_layers: Node2D
var _visual_stack: Node
var _manifest_loaded := false
var _manifest_load_attempted := false
var _manifest_load_attempt_count := 0
var _manifest_error := ""
var _manifest_schema := 0
var _grid_chunk_size := DEFAULT_GRID_CHUNK_SIZE
var _world_size := Vector2(11_520.0, 6_480.0)
var _expected_world_size := Vector2.ZERO
var _has_expected_world_size := false
var _entries_by_key: Dictionary = {}
var _elements_by_key: Dictionary = {}
var _loaded_nodes: Dictionary = {}
var _pending_entries: Dictionary = {}
var _failed_entries: Dictionary = {}
var _request_attempts_by_key: Dictionary = {}
var _desired_keys: Dictionary = {}
var _retained_keys: Dictionary = {}
var _legacy_layer_roots: Dictionary = {}
var _last_center_chunk := Vector2i(-9999, -9999)
var _last_visible_half_extent := Vector2(-1.0, -1.0)
var _last_world_position := Vector2.ZERO
var _graphics_quality := "high"
var _reduced_motion := false
var _request_generation := 1


func _ready() -> void:
	_visual_layers = get_parent() as Node2D
	_load_manifest()
	if _manifest_loaded:
		_resolve_scene_elements()
	set_process(true)


func configure(visual_layers: Node2D, expected_world_size: Vector2) -> void:
	_visual_layers = visual_layers
	_expected_world_size = expected_world_size
	_has_expected_world_size = true
	if not _manifest_loaded:
		_load_manifest()
	if not _manifest_loaded or not _validate_expected_world_size():
		return
	_resolve_scene_elements()


func retry_manifest_load() -> bool:
	## A failed manifest remains terminal during ordinary frame updates. Tooling
	## or an owning runtime may call this method after fixing the external input.
	if _manifest_loaded:
		return true
	_manifest_load_attempted = false
	_load_manifest()
	if _manifest_loaded:
		_resolve_scene_elements()
	return _manifest_loaded


func set_graphics_quality(quality_id: String) -> void:
	var normalized := quality_id if quality_id in ["low", "medium", "high"] else "high"
	if _graphics_quality == normalized:
		return
	_graphics_quality = normalized
	_invalidate_culling()


func set_reduced_motion(enabled: bool) -> void:
	if _reduced_motion == enabled:
		return
	_reduced_motion = enabled
	_invalidate_culling()


func update_streaming(
	world_position: Vector2,
	visible_half_extent: Vector2 = Vector2.ZERO,
	force: bool = false
) -> void:
	if not _manifest_loaded:
		if not _manifest_load_attempted:
			_load_manifest()
			if _manifest_loaded:
				_resolve_scene_elements()
	if not _manifest_loaded:
		return
	var resolved_half_extent := visible_half_extent
	if resolved_half_extent.x <= 0.0 or resolved_half_extent.y <= 0.0:
		resolved_half_extent = DEFAULT_VISIBLE_HALF_EXTENT
	var center_chunk := Vector2i(
		floori(world_position.x / float(_grid_chunk_size)),
		floori(world_position.y / float(_grid_chunk_size))
	)
	# With an active Camera2D, native Parallax2D changes the canvas transform
	# continuously even while the gameplay chunk stays unchanged. Re-evaluate in
	# that case; the element set is sparse and the screen-space test is cheap.
	var has_camera := get_viewport() != null and get_viewport().get_camera_2d() != null
	if (
		not force
		and not has_camera
		and center_chunk == _last_center_chunk
		and resolved_half_extent.is_equal_approx(_last_visible_half_extent)
	):
		return
	_last_center_chunk = center_chunk
	_last_visible_half_extent = resolved_half_extent
	_last_world_position = world_position

	_desired_keys.clear()
	_retained_keys.clear()
	var world_visible_rect := Rect2(world_position - resolved_half_extent, resolved_half_extent * 2.0)
	var world_prefetch_rect := world_visible_rect.grow(float(_grid_chunk_size * PREFETCH_RING_CHUNKS))
	var world_retained_rect := world_prefetch_rect.grow(float(_grid_chunk_size * UNLOAD_HYSTERESIS_CHUNKS))
	var viewport_visible_rect := Rect2()
	var viewport_prefetch_rect := Rect2()
	var viewport_retained_rect := Rect2()
	if has_camera:
		viewport_visible_rect = get_viewport().get_visible_rect()
		var screen_ring := maxf(viewport_visible_rect.size.length() * 0.5, 256.0)
		viewport_prefetch_rect = viewport_visible_rect.grow(screen_ring)
		viewport_retained_rect = viewport_prefetch_rect.grow(screen_ring)

	for key_variant in _entries_by_key.keys():
		var key := str(key_variant)
		var entry: Dictionary = _entries_by_key[key]
		var element := _elements_by_key.get(key) as Node2D
		if element != null and is_instance_valid(element) and not _element_allows_quality(element):
			continue
		var bounds := _entry_bounds(entry, element, has_camera)
		var prefetch_rect := viewport_prefetch_rect if has_camera and element != null else world_prefetch_rect
		var retained_rect := viewport_retained_rect if has_camera and element != null else world_retained_rect
		if bounds.intersects(retained_rect, true):
			_retained_keys[key] = true
		if bounds.intersects(prefetch_rect, true):
			_desired_keys[key] = true
			entry["_priority"] = bounds.get_center().distance_squared_to(prefetch_rect.get_center())
			_entries_by_key[key] = entry
	_clear_inactive_request_state()

	var request_keys: Array[String] = []
	for key_variant in _desired_keys.keys():
		request_keys.append(str(key_variant))
	request_keys.sort_custom(func(first: String, second: String) -> bool:
		var first_priority := float((_entries_by_key[first] as Dictionary).get("_priority", INF))
		var second_priority := float((_entries_by_key[second] as Dictionary).get("_priority", INF))
		if not is_equal_approx(first_priority, second_priority):
			return first_priority < second_priority
		return first < second
	)
	for key in request_keys:
		if _loaded_nodes.has(key) or _pending_entries.has(key) or _has_current_failure(key):
			continue
		_request_entry(_entries_by_key[key])
	_unload_stale_if_ready()


func _process(_delta: float) -> void:
	if _pending_entries.is_empty():
		_unload_stale_if_ready()
		return
	var pending_keys: Array[String] = []
	for key_variant in _pending_entries.keys():
		pending_keys.append(str(key_variant))
	pending_keys.sort_custom(func(first: String, second: String) -> bool:
		var first_priority := float((_pending_entries[first] as Dictionary).get("_priority", INF))
		var second_priority := float((_pending_entries[second] as Dictionary).get("_priority", INF))
		if not is_equal_approx(first_priority, second_priority):
			return first_priority < second_priority
		return first < second
	)
	var attached_this_frame := 0
	for key in pending_keys:
		var entry: Dictionary = _pending_entries[key]
		var path := str(entry.get("path", ""))
		var pending_generation := int(entry.get("_generation", 0))
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_pending_entries.erase(key)
			if pending_generation != _request_generation:
				_mark_culling_dirty()
				continue
			_mark_entry_failed(key, pending_generation)
			push_error("Nie udało się wczytać elementu warstwy %s." % path)
			continue
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			continue
		var resource := ResourceLoader.load_threaded_get(path)
		_pending_entries.erase(key)
		if resource == null:
			if pending_generation != _request_generation:
				_mark_culling_dirty()
				continue
			_mark_entry_failed(key, pending_generation)
			push_error("Element warstwy nie jest zasobem Godot: %s." % path)
			continue
		if pending_generation != _request_generation:
			# The post-invalidation culling pass skipped this still-pending key.
			# Re-arm the cache so a camera-less caller's next identical update can
			# request it for the current generation instead of hitting early return.
			_mark_culling_dirty()
			continue
		if not _retained_keys.has(key):
			continue
		if not _attach_entry(entry, resource):
			_mark_entry_failed(key, pending_generation)
			continue
		attached_this_frame += 1
		if attached_this_frame >= MAX_ATTACHES_PER_FRAME:
			break
	_unload_stale_if_ready()


func _request_entry(entry: Dictionary) -> void:
	var key := str(entry.get("key", ""))
	var path := str(entry.get("path", ""))
	if key.is_empty() or not _begin_entry_request(key):
		return
	if path.is_empty():
		_mark_entry_failed(key, _request_generation)
		return
	var request_error := ResourceLoader.load_threaded_request(
		path,
		"",
		true,
		ResourceLoader.CACHE_MODE_IGNORE
	)
	if request_error != OK:
		_mark_entry_failed(key, _request_generation)
		push_error("Nie udało się zlecić wczytania elementu warstwy %s (%d)." % [path, request_error])
		return
	var pending := entry.duplicate(true)
	pending["_generation"] = _request_generation
	_pending_entries[key] = pending


func _attach_entry(entry: Dictionary, resource: Resource) -> bool:
	var key := str(entry.get("key", ""))
	if _loaded_nodes.has(key):
		return true
	var element := _elements_by_key.get(key) as Node2D
	if element != null and is_instance_valid(element) and element.has_method("attach_runtime_resource"):
		if not bool(element.attach_runtime_resource(resource)):
			push_error("Nie można podpiąć zasobu do autorskiego elementu %s." % key)
			return false
		var content: Node2D
		if element.has_method("runtime_content_node"):
			content = element.runtime_content_node() as Node2D
		if content == null:
			push_error("Autorski element %s nie utworzył treści runtime." % key)
			return false
		content.set_meta(&"visual_chunk_key", key)
		_loaded_nodes[key] = content
		return true
	# Compatibility path for an explicitly selected schema-v1 manifest. New v2
	# never reaches it because every placement must have a scene element.
	var texture := resource as Texture2D
	if texture == null:
		push_error("Legacy visual chunk nie jest Texture2D: %s." % entry.get("path", ""))
		return false
	var parent_name := str(entry.get("runtime_parent", ""))
	var layer_root := _legacy_layer_roots.get(parent_name) as Node2D
	if layer_root == null or not is_instance_valid(layer_root):
		push_error("Brak legacy slotu VisualLayers/%s dla chunka %s." % [parent_name, key])
		return false
	var world_rect: Rect2 = entry.get("_legacy_world_rect", Rect2())
	var texture_region: Rect2 = entry.get("_texture_region", Rect2())
	var sprite := Sprite2D.new()
	sprite.name = "%s_%s" % [parent_name, key.replace(":", "_")]
	sprite.centered = false
	sprite.position = world_rect.position
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	sprite.region_enabled = true
	sprite.region_rect = texture_region
	sprite.region_filter_clip_enabled = false
	sprite.set_meta(&"visual_chunk_key", key)
	layer_root.add_child(sprite)
	_loaded_nodes[key] = sprite
	return true


func _unload_stale_if_ready() -> void:
	if not _all_desired_loaded():
		return
	for key_variant in _loaded_nodes.keys().duplicate():
		var key := str(key_variant)
		if _retained_keys.has(key):
			continue
		var element := _elements_by_key.get(key) as Node2D
		if element != null and is_instance_valid(element) and element.has_method("detach_runtime_resource"):
			element.detach_runtime_resource()
		else:
			var stale_node := _loaded_nodes.get(key) as Node2D
			if stale_node != null and is_instance_valid(stale_node):
				stale_node.queue_free()
		_loaded_nodes.erase(key)


func _all_desired_loaded() -> bool:
	for key_variant in _desired_keys.keys():
		var key := str(key_variant)
		if not _loaded_nodes.has(key) and not _has_current_failure(key):
			return false
	return true


func _begin_entry_request(key: String) -> bool:
	if key.is_empty() or _has_current_failure(key):
		return false
	var attempts := int(_request_attempts_by_key.get(key, 0))
	if attempts >= MAX_REQUEST_ATTEMPTS_PER_RESIDENCE:
		_failed_entries[key] = _request_generation
		return false
	_request_attempts_by_key[key] = attempts + 1
	return true


func _mark_entry_failed(key: String, generation: int) -> void:
	# A request that completed after its element left the desired set must not
	# poison a later re-entry. Only the current desired residence is terminal.
	if generation != _request_generation or not _desired_keys.has(key):
		return
	_failed_entries[key] = generation


func _has_current_failure(key: String) -> bool:
	return int(_failed_entries.get(key, -1)) == _request_generation


func _clear_inactive_request_state() -> void:
	for key_variant in _failed_entries.keys().duplicate():
		var key := str(key_variant)
		if not _desired_keys.has(key):
			_failed_entries.erase(key)
	for key_variant in _request_attempts_by_key.keys().duplicate():
		var key := str(key_variant)
		if not _desired_keys.has(key):
			_request_attempts_by_key.erase(key)


func _load_manifest() -> void:
	if _manifest_loaded or _manifest_load_attempted:
		return
	_manifest_load_attempted = true
	_manifest_load_attempt_count += 1
	_entries_by_key.clear()
	_manifest_error = ""
	_manifest_schema = 0
	if not FileAccess.file_exists(manifest_path):
		_fail_manifest("Brak manifestu warstw wizualnych: %s." % manifest_path)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (parsed is Dictionary):
		_fail_manifest("Manifest warstw wizualnych nie jest słownikiem JSON.")
		return
	var manifest: Dictionary = parsed
	_manifest_schema = int(manifest.get("schema_version", 0))
	_world_size = _vector2_from_array(manifest.get("world_size", []))
	if not _validate_expected_world_size():
		return
	if _manifest_schema == 2:
		_parse_schema_v2(manifest)
	elif _manifest_schema == 1:
		_parse_schema_v1(manifest)
	else:
		_fail_manifest("Nieobsługiwana wersja manifestu warstw wizualnych: %d." % _manifest_schema)
		return
	if _entries_by_key.is_empty():
		_fail_manifest("Manifest warstw wizualnych nie zawiera żadnych elementów.")
		return
	_manifest_loaded = _manifest_error.is_empty()


func _parse_schema_v2(manifest: Dictionary) -> void:
	if str(manifest.get("transform_authority", "")) != "composition_scene_only":
		_fail_manifest("Manifest v2 musi pozostawić transformy scenie kompozycji.")
		return
	var layers = manifest.get("layers", [])
	if not (layers is Array) or layers.size() != EXPECTED_LAYER_IDS.size():
		_fail_manifest("Manifest v2 musi zawierać dokładnie sześć warstw L00-L05.")
		return
	for index in range(EXPECTED_LAYER_IDS.size()):
		var layer_variant = layers[index]
		if not (layer_variant is Dictionary) or str(layer_variant.get("id", "")) != EXPECTED_LAYER_IDS[index]:
			_fail_manifest("Manifest v2 ma niepoprawną kolejność lub ID warstwy %d." % index)
			return
	var payloads = manifest.get("payloads", [])
	if not (payloads is Array):
		_fail_manifest("Manifest v2 nie zawiera tablicy payloads.")
		return
	for payload_variant in payloads:
		if not (payload_variant is Dictionary):
			continue
		var payload: Dictionary = payload_variant
		var target_layer := str(payload.get("target_layer", ""))
		if not EXPECTED_LAYER_IDS.has(target_layer):
			_fail_manifest("Payload v2 wskazuje nieznaną warstwę %s." % target_layer)
			return
		if str(payload.get("placement_authority", "")) != "composition_scene_elements":
			_fail_manifest("Payload v2 próbuje przejąć transformy elementów sceny.")
			return
		var elements = payload.get("elements", [])
		if not (elements is Array):
			continue
		for element_variant in elements:
			if not (element_variant is Dictionary):
				continue
			var entry: Dictionary = element_variant.duplicate(true)
			entry["runtime_parent"] = target_layer
			if not _register_manifest_entry(entry):
				return


func _parse_schema_v1(manifest: Dictionary) -> void:
	_grid_chunk_size = maxi(int(manifest.get("grid_chunk_size", DEFAULT_GRID_CHUNK_SIZE)), 1)
	var layers = manifest.get("layers", [])
	if not (layers is Array):
		_fail_manifest("Manifest v1 nie zawiera tablicy layers.")
		return
	for layer_variant in layers:
		if not (layer_variant is Dictionary):
			continue
		var layer: Dictionary = layer_variant
		var runtime_parent := str(layer.get("runtime_parent", ""))
		var chunks = layer.get("chunks", [])
		if not (chunks is Array):
			continue
		for chunk_variant in chunks:
			if not (chunk_variant is Dictionary):
				continue
			var entry: Dictionary = chunk_variant.duplicate(true)
			entry["runtime_parent"] = runtime_parent
			if not _register_manifest_entry(entry):
				return


func _register_manifest_entry(entry: Dictionary) -> bool:
	var key := str(entry.get("key", ""))
	var path := str(entry.get("path", ""))
	if key.is_empty() or path.is_empty() or _entries_by_key.has(key):
		_fail_manifest("Manifest zawiera pusty albo powtórzony element: %s." % key)
		return false
	entry["_legacy_world_rect"] = _rect2_from_array(entry.get("world_rect", []))
	entry["_texture_region"] = _rect2_from_array(entry.get("texture_region", []))
	entry["_source_rect"] = _rect2_from_array(entry.get("source_rect", []))
	_entries_by_key[key] = entry
	return true


func _resolve_scene_elements() -> void:
	_elements_by_key.clear()
	_legacy_layer_roots.clear()
	if _visual_layers == null:
		_visual_layers = get_parent() as Node2D
	if _visual_layers == null:
		return
	_visual_stack = _visual_layers.get_node_or_null("SixLayerVisuals")
	if _visual_stack != null:
		for node in _visual_stack.find_children("*", "", true, false):
			if not _node_has_property(node, &"element_id") or not node.has_method("visual_local_bounds"):
				continue
			var key := str(node.get("element_id"))
			if key.is_empty() or _elements_by_key.has(key):
				_fail_manifest("Scena kompozycji ma pusty albo powtórzony element %s." % key)
				continue
			_elements_by_key[key] = node
	if _manifest_schema == 2:
		for mapping_error in scene_manifest_mapping_errors():
			_fail_manifest(mapping_error)
		for key_variant in _entries_by_key.keys():
			var key := str(key_variant)
			if not _elements_by_key.has(key):
				continue
			var entry: Dictionary = _entries_by_key[key]
			var element := _elements_by_key[key] as Node
			if _node_has_property(element, &"resource_path"):
				var authored_path := str(element.get("resource_path"))
				if authored_path != str(entry.get("path", "")):
					_fail_manifest("Element %s wskazuje inny zasób niż manifest v2." % key)
		_manifest_loaded = _manifest_error.is_empty() and not _entries_by_key.is_empty()
		return
	# Explicit v1 compatibility: prefer the new L02 streamed bucket, then the
	# historical direct parent when used by a legacy fixture.
	if _visual_stack != null and _visual_stack.has_method("content_root"):
		var migrated_root = _visual_stack.content_root("L02_far_structures", "world", "streamed")
		if migrated_root is Node2D:
			_legacy_layer_roots["EnvironmentDecoration"] = migrated_root
	var historical := _visual_layers.get_node_or_null("EnvironmentDecoration") as Node2D
	if historical != null:
		_legacy_layer_roots["EnvironmentDecoration"] = historical


func scene_manifest_mapping_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if _manifest_schema != 2:
		return errors
	var manifest_counts := {}
	for key_variant in _entries_by_key.keys():
		var key := str(key_variant)
		manifest_counts[key] = int(manifest_counts.get(key, 0)) + 1
	var scene_counts := {}
	var streamed_scene_counts := {}
	if _visual_stack != null:
		for node in _visual_stack.find_children("*", "", true, false):
			if not _node_has_property(node, &"element_id") or not node.has_method("visual_local_bounds"):
				continue
			var key := str(node.get("element_id"))
			scene_counts[key] = int(scene_counts.get(key, 0)) + 1
			if node.has_method("is_manifest_streamed") and bool(node.is_manifest_streamed()):
				streamed_scene_counts[key] = int(streamed_scene_counts.get(key, 0)) + 1
	for key_variant in manifest_counts.keys():
		var key := str(key_variant)
		var scene_count := int(scene_counts.get(key, 0))
		var streamed_scene_count := int(streamed_scene_counts.get(key, 0))
		if scene_count != 1:
			errors.append(
				"Wpis manifestu v2 %s wymaga dokładnie jednego scenowego elementu; znaleziono %d."
				% [key, scene_count]
			)
		elif streamed_scene_count != 1:
			errors.append("Element %s z manifestu v2 musi używać trybu Manifest Streamed." % key)
	for key_variant in streamed_scene_counts.keys():
		var key := str(key_variant)
		var manifest_count := int(manifest_counts.get(key, 0))
		if manifest_count != 1:
			errors.append(
				"Scenowy element Manifest Streamed %s wymaga dokładnie jednego wpisu manifestu v2; znaleziono %d."
				% [key, manifest_count]
			)
	return errors


func _entry_bounds(entry: Dictionary, element: Node2D, screen_space: bool) -> Rect2:
	if element == null or not is_instance_valid(element):
		return entry.get("_legacy_world_rect", Rect2())
	var local_bounds := element.visual_local_bounds() as Rect2
	if screen_space:
		return _transform_rect(local_bounds, element.get_global_transform_with_canvas())
	return _transform_rect(local_bounds, element.global_transform)


func _element_allows_quality(element: Node2D) -> bool:
	var authored_visible := element.visible
	if element.is_inside_tree():
		authored_visible = element.is_visible_in_tree()
	if not authored_visible:
		return false
	if element.has_method("is_enabled_for_quality"):
		return bool(element.is_enabled_for_quality(_graphics_quality))
	return true


func _invalidate_culling() -> void:
	_mark_culling_dirty()
	_request_generation += 1
	_failed_entries.clear()
	_request_attempts_by_key.clear()


func _mark_culling_dirty() -> void:
	_last_center_chunk = Vector2i(-9999, -9999)
	_last_visible_half_extent = Vector2(-1.0, -1.0)


func _validate_expected_world_size() -> bool:
	if not _has_expected_world_size or _world_size.is_equal_approx(_expected_world_size):
		return true
	_fail_manifest("Manifest warstw wizualnych ma obszar %s zamiast %s." % [
		_world_size,
		_expected_world_size,
	])
	return false


func _fail_manifest(message: String) -> void:
	var should_log := _manifest_error.is_empty() or not _manifest_error.contains(message)
	if _manifest_error.is_empty():
		_manifest_error = message
	elif not _manifest_error.contains(message):
		_manifest_error += "\n" + message
	_manifest_loaded = false
	if should_log:
		push_error(message)


func manifest_loaded() -> bool:
	return _manifest_loaded


func manifest_error() -> String:
	return _manifest_error


func manifest_entry_count() -> int:
	return _entries_by_key.size()


func manifest_load_attempt_count() -> int:
	return _manifest_load_attempt_count


func loaded_chunk_keys() -> Array[String]:
	return _sorted_dictionary_keys(_loaded_nodes)


func pending_chunk_keys() -> Array[String]:
	return _sorted_dictionary_keys(_pending_entries)


func failed_chunk_keys() -> Array[String]:
	var result: Array[String] = []
	for key_variant in _failed_entries.keys():
		var key := str(key_variant)
		if _has_current_failure(key):
			result.append(key)
	result.sort()
	return result


func request_attempt_count(key: String) -> int:
	return int(_request_attempts_by_key.get(key, 0))


func desired_chunk_keys() -> Array[String]:
	return _sorted_dictionary_keys(_desired_keys)


func chunk_state(key: String) -> Dictionary:
	if not _entries_by_key.has(key):
		return {}
	var entry: Dictionary = _entries_by_key[key]
	var element := _elements_by_key.get(key) as Node2D
	var node := _loaded_nodes.get(key) as Node2D
	return {
		"key": key,
		"path": str(entry.get("path", "")),
		"runtime_parent": str(entry.get("runtime_parent", "")),
		"world_rect": _entry_bounds(entry, element, false),
		"authored_bounds": _entry_bounds(entry, element, false),
		"legacy_world_rect": entry.get("_legacy_world_rect", Rect2()),
		"texture_region": entry.get("_texture_region", Rect2()),
		"loaded": node != null and is_instance_valid(node),
		"failed": _has_current_failure(key),
		"request_attempts": request_attempt_count(key),
		"element": element,
		"node": node,
	}


func presentation_state() -> Dictionary:
	var all_decoded_bytes := 0
	var loaded_decoded_bytes := 0
	for key_variant in _entries_by_key.keys():
		var key := str(key_variant)
		var entry: Dictionary = _entries_by_key[key]
		var source_rect: Rect2 = entry.get("_source_rect", Rect2())
		var decoded_bytes := int(source_rect.size.x * source_rect.size.y * 4.0)
		all_decoded_bytes += decoded_bytes
		if _loaded_nodes.has(key):
			loaded_decoded_bytes += decoded_bytes
	return {
		"manifest_loaded": _manifest_loaded,
		"manifest_load_attempt_count": _manifest_load_attempt_count,
		"manifest_path": manifest_path,
		"schema_version": _manifest_schema,
		"transform_authority": "composition_scene_only" if _manifest_schema == 2 else "legacy_manifest",
		"entry_count": _entries_by_key.size(),
		"authored_element_count": _elements_by_key.size(),
		"desired_count": _desired_keys.size(),
		"pending_count": _pending_entries.size(),
		"failed_count": failed_chunk_keys().size(),
		"loaded_count": _loaded_nodes.size(),
		"graphics_quality": _graphics_quality,
		"reduced_motion": _reduced_motion,
		"all_chunks_decoded_rgba_bytes": all_decoded_bytes,
		"loaded_decoded_rgba_bytes": loaded_decoded_bytes,
		"prefetch_ring_chunks": PREFETCH_RING_CHUNKS,
		"unload_hysteresis_chunks": UNLOAD_HYSTERESIS_CHUNKS,
		"max_request_attempts_per_residence": MAX_REQUEST_ATTEMPTS_PER_RESIDENCE,
	}


static func _node_has_property(node: Object, property_name: StringName) -> bool:
	if node == null:
		return false
	for property in node.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


static func _sorted_dictionary_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in source.keys():
		result.append(str(key))
	result.sort()
	return result


static func _vector2_from_array(value: Variant) -> Vector2:
	if not (value is Array) or value.size() != 2:
		return Vector2.ZERO
	return Vector2(float(value[0]), float(value[1]))


static func _rect2_from_array(value: Variant) -> Rect2:
	if not (value is Array) or value.size() != 4:
		return Rect2()
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


static func _transform_rect(rect: Rect2, transform: Transform2D) -> Rect2:
	var corners := PackedVector2Array([
		transform * rect.position,
		transform * Vector2(rect.end.x, rect.position.y),
		transform * rect.end,
		transform * Vector2(rect.position.x, rect.end.y),
	])
	var minimum := corners[0]
	var maximum := corners[0]
	for corner in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)
