class_name DiveVisualChunkStreamer
extends Node2D

## Presentation-only streamer for sparse authored map layers. The JSON manifest
## stores resource paths as plain strings, so opening UnderwaterMap.tscn never
## preloads either master texture or every generated crop.

const DEFAULT_MANIFEST_PATH := "res://assets/diving/world/map_v2/visual_chunks/map_visual_chunks_v1.json"
const DEFAULT_VISIBLE_HALF_EXTENT := Vector2(960.0, 540.0)
const PREFETCH_RING_CHUNKS := 1
const UNLOAD_HYSTERESIS_CHUNKS := 1
const MAX_ATTACHES_PER_FRAME := 2
const LIGHT_MODE_LIT := "lit"
const LIGHT_MODE_UNSHADED := "unshaded"

@export_file("*.json") var manifest_path := DEFAULT_MANIFEST_PATH

var _visual_layers: Node2D
var _manifest_loaded := false
var _manifest_error := ""
var _grid_chunk_size := 1024
var _world_size := Vector2(11_520.0, 6_480.0)
var _entries_by_key: Dictionary = {}
var _loaded_nodes: Dictionary = {}
var _pending_entries: Dictionary = {}
var _desired_keys: Dictionary = {}
var _retained_keys: Dictionary = {}
var _layer_roots: Dictionary = {}
var _last_center_chunk := Vector2i(-9999, -9999)
var _last_visible_half_extent := Vector2(-1.0, -1.0)
var _unshaded_material: CanvasItemMaterial
var _allow_headless_texture_materialization_for_tests := false


func _ready() -> void:
	_visual_layers = get_parent() as Node2D
	_load_manifest()
	set_process(true)


func configure(visual_layers: Node2D, expected_world_size: Vector2) -> void:
	_visual_layers = visual_layers
	if not _manifest_loaded:
		_load_manifest()
	if _manifest_loaded and not _world_size.is_equal_approx(expected_world_size):
		_manifest_error = "Manifest warstw wizualnych ma obszar %s zamiast %s." % [
			_world_size,
			expected_world_size,
		]
		push_error(_manifest_error)
	_resolve_layer_roots()


func update_streaming(
	world_position: Vector2,
	visible_half_extent: Vector2 = Vector2.ZERO,
	force: bool = false
) -> void:
	if not _manifest_loaded:
		_load_manifest()
	if not _manifest_loaded:
		return
	var resolved_half_extent := visible_half_extent
	if resolved_half_extent.x <= 0.0 or resolved_half_extent.y <= 0.0:
		resolved_half_extent = DEFAULT_VISIBLE_HALF_EXTENT
	var center_chunk := Vector2i(
		floori(world_position.x / float(_grid_chunk_size)),
		floori(world_position.y / float(_grid_chunk_size))
	)
	if (
		not force
		and center_chunk == _last_center_chunk
		and resolved_half_extent.is_equal_approx(_last_visible_half_extent)
	):
		return
	_last_center_chunk = center_chunk
	_last_visible_half_extent = resolved_half_extent

	var visible_rect := Rect2(
		world_position - resolved_half_extent,
		resolved_half_extent * 2.0
	)
	var prefetch_rect := visible_rect.grow(float(_grid_chunk_size * PREFETCH_RING_CHUNKS))
	var retained_rect := prefetch_rect.grow(float(_grid_chunk_size * UNLOAD_HYSTERESIS_CHUNKS))
	_desired_keys.clear()
	_retained_keys.clear()
	for key_variant in _entries_by_key.keys():
		var key := str(key_variant)
		var entry: Dictionary = _entries_by_key[key]
		var world_rect: Rect2 = entry.get("_world_rect", Rect2())
		if world_rect.intersects(retained_rect, true):
			_retained_keys[key] = true
		if world_rect.intersects(prefetch_rect, true):
			_desired_keys[key] = true

	for key_variant in _loaded_nodes.keys().duplicate():
		var key := str(key_variant)
		if _retained_keys.has(key):
			continue
		var stale_node := _loaded_nodes.get(key) as Sprite2D
		_loaded_nodes.erase(key)
		if stale_node != null and is_instance_valid(stale_node):
			stale_node.queue_free()

	for key_variant in _desired_keys.keys():
		var key := str(key_variant)
		if _loaded_nodes.has(key) or _pending_entries.has(key):
			continue
		_request_entry(_entries_by_key[key])


func _process(_delta: float) -> void:
	if _pending_entries.is_empty():
		return
	var attached_this_frame := 0
	for key_variant in _pending_entries.keys().duplicate():
		var key := str(key_variant)
		var entry: Dictionary = _pending_entries[key]
		var path := str(entry.get("path", ""))
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_pending_entries.erase(key)
			push_error("Nie udało się wczytać wizualnego chunka %s." % path)
			continue
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			continue
		var texture := ResourceLoader.load_threaded_get(path) as Texture2D
		_pending_entries.erase(key)
		if texture == null:
			push_error("Wizualny chunk nie jest Texture2D: %s." % path)
			continue
		if not _retained_keys.has(key):
			continue
		_attach_entry(entry, texture)
		attached_this_frame += 1
		if attached_this_frame >= MAX_ATTACHES_PER_FRAME:
			break


func _request_entry(entry: Dictionary) -> void:
	# Most headless tests validate the manifest and culling contract without a
	# renderer. Only the dedicated streamer test opts into dummy texture objects.
	if (
		DisplayServer.get_name() == "headless"
		and not _allow_headless_texture_materialization_for_tests
	):
		return
	var key := str(entry.get("key", ""))
	var path := str(entry.get("path", ""))
	if key.is_empty() or path.is_empty():
		return
	var request_error := ResourceLoader.load_threaded_request(
		path,
		"Texture2D",
		true,
		ResourceLoader.CACHE_MODE_IGNORE
	)
	if request_error != OK:
		push_error("Nie udało się zlecić wczytania wizualnego chunka %s (%d)." % [path, request_error])
		return
	_pending_entries[key] = entry


func enable_headless_texture_materialization_for_tests() -> void:
	_allow_headless_texture_materialization_for_tests = true


func _attach_entry(entry: Dictionary, texture: Texture2D) -> void:
	var key := str(entry.get("key", ""))
	if _loaded_nodes.has(key):
		return
	var parent_name := str(entry.get("runtime_parent", ""))
	var layer_root := _layer_roots.get(parent_name) as Node2D
	if layer_root == null or not is_instance_valid(layer_root):
		push_error("Brak slotu VisualLayers/%s dla chunka %s." % [parent_name, key])
		return
	var world_rect: Rect2 = entry.get("_world_rect", Rect2())
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
	if str(entry.get("_light_mode", LIGHT_MODE_LIT)) == LIGHT_MODE_UNSHADED:
		sprite.material = _unshaded_chunk_material()
	sprite.set_meta(&"visual_chunk_key", key)
	layer_root.add_child(sprite)
	_loaded_nodes[key] = sprite


func _load_manifest() -> void:
	if _manifest_loaded:
		return
	_entries_by_key.clear()
	_manifest_error = ""
	if not FileAccess.file_exists(manifest_path):
		_manifest_error = "Brak manifestu warstw wizualnych: %s." % manifest_path
		push_error(_manifest_error)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (parsed is Dictionary):
		_manifest_error = "Manifest warstw wizualnych nie jest słownikiem JSON."
		push_error(_manifest_error)
		return
	var manifest: Dictionary = parsed
	if int(manifest.get("schema_version", 0)) != 1:
		_manifest_error = "Nieobsługiwana wersja manifestu warstw wizualnych."
		push_error(_manifest_error)
		return
	_grid_chunk_size = maxi(int(manifest.get("grid_chunk_size", 0)), 1)
	_world_size = _vector2_from_array(manifest.get("world_size", []))
	var layers = manifest.get("layers", [])
	if not (layers is Array):
		_manifest_error = "Manifest warstw wizualnych nie zawiera tablicy layers."
		push_error(_manifest_error)
		return
	for layer_variant in layers:
		if not (layer_variant is Dictionary):
			continue
		var layer: Dictionary = layer_variant
		var runtime_parent := str(layer.get("runtime_parent", ""))
		var light_mode := str(layer.get("light_mode", LIGHT_MODE_LIT))
		if light_mode not in [LIGHT_MODE_LIT, LIGHT_MODE_UNSHADED]:
			_manifest_error = "Manifest zawiera nieobsługiwany light_mode warstwy %s: %s." % [runtime_parent, light_mode]
			push_error(_manifest_error)
			return
		var chunks = layer.get("chunks", [])
		if not (chunks is Array):
			continue
		for chunk_variant in chunks:
			if not (chunk_variant is Dictionary):
				continue
			var entry: Dictionary = chunk_variant.duplicate(true)
			var key := str(entry.get("key", ""))
			if key.is_empty() or _entries_by_key.has(key):
				_manifest_error = "Manifest zawiera pusty albo powtórzony klucz chunka: %s." % key
				push_error(_manifest_error)
				return
			entry["runtime_parent"] = runtime_parent
			entry["_light_mode"] = light_mode
			entry["_world_rect"] = _rect2_from_array(entry.get("world_rect", []))
			entry["_texture_region"] = _rect2_from_array(entry.get("texture_region", []))
			entry["_source_rect"] = _rect2_from_array(entry.get("source_rect", []))
			_entries_by_key[key] = entry
	_manifest_loaded = not _entries_by_key.is_empty()
	if not _manifest_loaded:
		_manifest_error = "Manifest warstw wizualnych nie zawiera żadnych chunków."
		push_error(_manifest_error)
		return
	_resolve_layer_roots()


func _unshaded_chunk_material() -> CanvasItemMaterial:
	if _unshaded_material == null:
		_unshaded_material = CanvasItemMaterial.new()
		_unshaded_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _unshaded_material


func _resolve_layer_roots() -> void:
	_layer_roots.clear()
	if _visual_layers == null:
		_visual_layers = get_parent() as Node2D
	if _visual_layers == null:
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (parsed is Dictionary):
		return
	for layer_variant in (parsed as Dictionary).get("layers", []):
		if not (layer_variant is Dictionary):
			continue
		var layer: Dictionary = layer_variant
		var parent_name := str(layer.get("runtime_parent", ""))
		var layer_root := _visual_layers.get_node_or_null(parent_name) as Node2D
		if layer_root == null:
			push_error("Scena mapy nie zawiera VisualLayers/%s." % parent_name)
			continue
		layer_root.z_index = int(layer.get("z_index", layer_root.z_index))
		_layer_roots[parent_name] = layer_root


func manifest_loaded() -> bool:
	return _manifest_loaded


func manifest_error() -> String:
	return _manifest_error


func manifest_entry_count() -> int:
	return _entries_by_key.size()


func loaded_chunk_keys() -> Array[String]:
	var result: Array[String] = []
	for key in _loaded_nodes.keys():
		result.append(str(key))
	result.sort()
	return result


func pending_chunk_keys() -> Array[String]:
	var result: Array[String] = []
	for key in _pending_entries.keys():
		result.append(str(key))
	result.sort()
	return result


func desired_chunk_keys() -> Array[String]:
	var result: Array[String] = []
	for key in _desired_keys.keys():
		result.append(str(key))
	result.sort()
	return result


func chunk_state(key: String) -> Dictionary:
	if not _entries_by_key.has(key):
		return {}
	var entry: Dictionary = _entries_by_key[key]
	var node := _loaded_nodes.get(key) as Sprite2D
	return {
		"key": key,
		"path": str(entry.get("path", "")),
		"runtime_parent": str(entry.get("runtime_parent", "")),
		"world_rect": entry.get("_world_rect", Rect2()),
		"texture_region": entry.get("_texture_region", Rect2()),
		"loaded": node != null and is_instance_valid(node),
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
		"manifest_path": manifest_path,
		"entry_count": _entries_by_key.size(),
		"desired_count": _desired_keys.size(),
		"pending_count": _pending_entries.size(),
		"loaded_count": _loaded_nodes.size(),
		"all_chunks_decoded_rgba_bytes": all_decoded_bytes,
		"loaded_decoded_rgba_bytes": loaded_decoded_bytes,
		"prefetch_ring_chunks": PREFETCH_RING_CHUNKS,
		"unload_hysteresis_chunks": UNLOAD_HYSTERESIS_CHUNKS,
	}


static func _vector2_from_array(value: Variant) -> Vector2:
	if not (value is Array) or value.size() != 2:
		return Vector2.ZERO
	return Vector2(float(value[0]), float(value[1]))


static func _rect2_from_array(value: Variant) -> Rect2:
	if not (value is Array) or value.size() != 4:
		return Rect2()
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
