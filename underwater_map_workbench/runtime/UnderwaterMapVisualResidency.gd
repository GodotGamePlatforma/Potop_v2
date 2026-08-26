class_name UnderwaterMapVisualResidency
extends RefCounted

## Owns transient camera-windowed residency for generated L01/L02 texture stubs.
## Requests cannot be cancelled. Every accepted/adopted request remains tracked
## until ResourceLoader reports a terminal status; loaded obsolete results are
## retrieved and immediately released by this manager.

enum PathState {
	IDLE,
	LOADING,
	RESIDENT,
	FAILED,
}

enum WindowPriority {
	VISIBLE,
	PREFETCH,
	RETAIN,
	ABSENT,
}

const STREAMED_LAYER_IDS := [&"L01", &"L02"]
const STREAMED_KIND := "texture_rect"
const STREAMED_CONTRACT := "camera_windowed_texture_v1"
const WORKBENCH_RESOURCE_ROOT := "res://underwater_map_workbench/"
const ESTIMATED_RGBA8_BYTES_PER_PIXEL := 4

var _profile: UnderwaterMapVisualResidencyProfile
var _visual_layers: Node2D
var _configured := false
var _invalidated := true
var _selection_error := ""

var _bindings_by_id: Dictionary = {}
var _paths: Dictionary = {}
var _classification_signature := ""

var _generation := 0
var _settled_generation := 0
var _last_world_position := Vector2.ZERO
var _last_visible_half_extent := Vector2.ZERO

var _request_count := 0
var _terminal_request_count := 0
var _cache_reuse_count := 0
var _failure_count := 0
var _eviction_count := 0
var _peak_resident_pixels := 0
var _remaining_commits_this_tick := 0
var _commit_budget_frame := -1
var _telemetry: Dictionary = {}


func configure(
	visual_layers: Node2D,
	profile: UnderwaterMapVisualResidencyProfile,
) -> PackedStringArray:
	_release_current_bindings()
	_profile = profile
	_visual_layers = visual_layers
	_configured = false
	_selection_error = ""
	_invalidated = true
	_classification_signature = ""
	_generation += 1

	var errors := PackedStringArray()
	if _profile == null:
		errors.append("Rezydencja grafiki mapy wymaga profilu.")
	else:
		errors.append_array(_profile.validation_errors())
	if _visual_layers == null or not is_instance_valid(_visual_layers):
		errors.append("Rezydencja grafiki mapy wymaga korzenia VisualLayers.")
	if not errors.is_empty():
		_update_telemetry()
		return errors

	var descriptors_by_path: Dictionary = {}
	for layer_id in STREAMED_LAYER_IDS:
		var layer := _visual_layers.get_node_or_null(NodePath(str(layer_id)))
		if not layer is Node2D:
			errors.append("VisualLayers nie zawiera warstwy %s." % str(layer_id))
			continue
		for group_node in layer.get_children():
			for asset_node in group_node.get_children():
				_register_stub_binding(
					asset_node,
					str(layer_id),
					descriptors_by_path,
					errors,
				)

	_prune_orphan_paths()
	_configured = errors.is_empty()
	if not _configured:
		_clear_all_binding_textures()
	_update_telemetry()
	return errors


func detach() -> void:
	_release_current_bindings()
	_visual_layers = null
	_profile = null
	_configured = false
	_invalidated = true
	_selection_error = ""
	_classification_signature = ""
	_generation += 1
	_prune_orphan_paths()
	_update_telemetry()


func update_window(
	world_position: Vector2,
	visible_half_extent: Vector2,
	force: bool = false,
) -> void:
	_last_world_position = world_position
	_last_visible_half_extent = visible_half_extent
	_begin_poll_cycle()
	if not _configured:
		_poll_requests()
		_prune_orphan_paths()
		_update_telemetry()
		return

	var classifications := _compute_classifications(force)
	_apply_classifications(classifications, force)
	_poll_requests()
	_evict_absent_residents()
	_trim_to_budget()
	_start_eligible_requests()
	_prune_orphan_paths()
	_update_telemetry()


func poll_pending_requests() -> void:
	_begin_poll_cycle()
	_poll_requests()
	if _configured:
		_evict_absent_residents()
		_trim_to_budget()
		_start_eligible_requests()
	_prune_orphan_paths()
	_update_telemetry()


func shutdown_and_drain() -> void:
	# Runtime teardown is the one place where waiting is preferable to leaking a
	# ResourceLoader claim. detach() remains non-blocking for rebuild/reconfigure.
	detach()
	var loading_paths := PackedStringArray()
	for path_value in _paths.keys():
		var path := str(path_value)
		var entry: Dictionary = _paths[path]
		if int(entry.get("state", PathState.IDLE)) == PathState.LOADING:
			loading_paths.append(path)
	loading_paths.sort()
	for path in loading_paths:
		var entry: Dictionary = _paths[path]
		var loaded: Resource = _resource_load_threaded_get(path)
		_terminal_request_count += 1
		_commit_terminal_loaded_resource(entry, loaded)
		_paths[path] = entry
	_prune_orphan_paths()
	_update_telemetry()


func invalidate_window() -> void:
	_invalidated = true


func is_visible_window_ready() -> bool:
	return (
		_configured
		and _selection_error.is_empty()
		and int(_telemetry.get("visible_missing_texture_count", 0)) == 0
		and int(_telemetry.get("visible_failed_texture_count", 0)) == 0
	)


func is_settled() -> bool:
	return bool(_telemetry.get("settled", false))


func telemetry_snapshot() -> Dictionary:
	return _telemetry.duplicate(true)


func _register_stub_binding(
	asset_node: Node,
	layer_id: String,
	descriptors_by_path: Dictionary,
	errors: PackedStringArray,
) -> void:
	if str(asset_node.get_meta("kind", "")) != STREAMED_KIND:
		return
	if not asset_node is Node2D:
		errors.append("Stub L01/L02 musi mieć root Node2D.")
		return

	var source_value = asset_node.get_meta("source", null)
	if not source_value is Dictionary:
		errors.append("Stub L01/L02 nie publikuje rekordu source.")
		return
	var source := source_value as Dictionary
	var asset_id := str(asset_node.get_meta("asset_id", source.get("id", ""))).strip_edges()
	if asset_id.is_empty() or _bindings_by_id.has(asset_id):
		errors.append("Stuby L01/L02 wymagają niepustych, unikalnych asset_id.")
		return
	if str(asset_node.get_meta("layer_id", "")) != layer_id:
		errors.append("Stub %s ma niezgodne layer_id." % asset_id)
	if str(asset_node.get_meta("residency_contract", "")) != STREAMED_CONTRACT:
		errors.append("Stub %s ma niepoprawny kontrakt rezydencji." % asset_id)

	var bitmap := asset_node.get_node_or_null("Bitmap") as TextureRect
	if bitmap == null:
		errors.append("Stub %s nie zawiera Bitmap:TextureRect." % asset_id)
		return
	if bitmap.texture != null:
		errors.append("Stub %s nie może preładowywać Texture2D." % asset_id)
		bitmap.texture = null

	var pixel_size_value = asset_node.get_meta("pixel_size", Vector2i.ZERO)
	if not pixel_size_value is Vector2i:
		errors.append("Stub %s ma niepoprawne metadata pixel_size." % asset_id)
		return
	var pixel_size := pixel_size_value as Vector2i
	if pixel_size.x <= 0 or pixel_size.y <= 0:
		errors.append("Stub %s wymaga dodatniego pixel_size." % asset_id)
		return
	var world_rect_value = asset_node.get_meta("world_rect", Rect2())
	if not world_rect_value is Rect2:
		errors.append("Stub %s ma niepoprawne metadata world_rect." % asset_id)
		return
	var world_rect := world_rect_value as Rect2
	if not world_rect.size.is_equal_approx(Vector2(pixel_size)):
		errors.append("Stub %s nie zachowuje natywnego rectu 1:1." % asset_id)

	var canonical_path := _canonical_resource_path(
		str(asset_node.get_meta("resource_path", ""))
	)
	if canonical_path.is_empty() or not canonical_path.begins_with(WORKBENCH_RESOURCE_ROOT):
		errors.append("Stub %s ma niepoprawną lokalną ścieżkę zasobu." % asset_id)
		return
	var expected_source_path := _canonical_resource_path(
		WORKBENCH_RESOURCE_ROOT + str(source.get("path", ""))
	)
	if canonical_path != expected_source_path:
		errors.append("Stub %s ma resource_path niezgodne z source.path." % asset_id)

	var source_sha := str(source.get("sha256", "")).strip_edges()
	var metadata_sha := str(asset_node.get_meta("source_sha256", "")).strip_edges()
	if not _valid_lower_sha256(source_sha) or metadata_sha != source_sha:
		errors.append("Stub %s ma niepoprawny pin SHA-256." % asset_id)
		return

	var descriptor := {
		"sha256": source_sha,
		"pixel_size": pixel_size,
	}
	if descriptors_by_path.has(canonical_path):
		var existing_descriptor: Dictionary = descriptors_by_path[canonical_path]
		if (
			str(existing_descriptor.get("sha256", "")) != source_sha
			or existing_descriptor.get("pixel_size", Vector2i.ZERO) != pixel_size
		):
			errors.append(
				"Kanoniczna ścieżka %s ma sprzeczne deskryptory stubów."
				% canonical_path
			)
			return
	else:
		descriptors_by_path[canonical_path] = descriptor

	var binding := {
		"asset_id": asset_id,
		"path": canonical_path,
		"node": asset_node as Node2D,
		"bitmap": bitmap,
		"pixel_size": pixel_size,
		"enabled": bool(source.get("enabled", true)),
		"priority": WindowPriority.ABSENT,
	}
	_bindings_by_id[asset_id] = binding
	_attach_binding_to_path(canonical_path, asset_id, descriptor)


func _attach_binding_to_path(
	canonical_path: String,
	asset_id: String,
	descriptor: Dictionary,
) -> void:
	var entry: Dictionary = _paths.get(canonical_path, {})
	var descriptor_changed: bool = (
		not entry.is_empty()
		and (
			str(entry.get("sha256", "")) != str(descriptor.get("sha256", ""))
			or entry.get("pixel_size", Vector2i.ZERO) != descriptor.get(
				"pixel_size",
				Vector2i.ZERO,
			)
		)
	)
	if entry.is_empty():
		entry = _new_path_entry(canonical_path, descriptor)
	elif descriptor_changed:
		var request_in_flight := int(entry.get("state", PathState.IDLE)) == PathState.LOADING
		if int(entry.get("state", PathState.IDLE)) == PathState.RESIDENT:
			_drop_resident_texture(entry)
		if not request_in_flight:
			entry["state"] = PathState.IDLE
			entry["failure"] = ""
		# request_* preserves the descriptor that entered ResourceLoader. The live
		# descriptor must still advance while that request is in flight so the
		# terminal result is recognized as obsolete and discarded.
		entry["sha256"] = str(descriptor.get("sha256", ""))
		entry["pixel_size"] = descriptor.get("pixel_size", Vector2i.ZERO)
		var size := entry["pixel_size"] as Vector2i
		entry["pixel_count"] = size.x * size.y
		entry["cache_replace_required"] = true
	var binding_ids: Array = entry.get("binding_ids", [])
	if not binding_ids.has(asset_id):
		binding_ids.append(asset_id)
	entry["binding_ids"] = binding_ids
	_paths[canonical_path] = entry


func _new_path_entry(canonical_path: String, descriptor: Dictionary) -> Dictionary:
	var pixel_size := descriptor.get("pixel_size", Vector2i.ZERO) as Vector2i
	return {
		"path": canonical_path,
		"sha256": str(descriptor.get("sha256", "")),
		"pixel_size": pixel_size,
		"pixel_count": pixel_size.x * pixel_size.y,
		"binding_ids": [],
		"state": PathState.IDLE,
		"texture": null,
		"priority": WindowPriority.ABSENT,
		"distance_squared": INF,
		"last_required_generation": 0,
		"last_visible_generation": 0,
		"resident_generation": 0,
		"request_generation": 0,
		"request_sha256": "",
		"request_pixel_size": Vector2i.ZERO,
		"cache_replace_required": false,
		"progress": 0.0,
		"failure": "",
	}


func _release_current_bindings() -> void:
	_clear_all_binding_textures()
	_bindings_by_id.clear()
	for path_value in _paths.keys():
		var path := str(path_value)
		var entry: Dictionary = _paths[path]
		entry["binding_ids"] = []
		entry["priority"] = WindowPriority.ABSENT
		entry["distance_squared"] = INF
		if int(entry.get("state", PathState.IDLE)) == PathState.RESIDENT:
			_drop_resident_texture(entry)
			entry["state"] = PathState.IDLE
		_paths[path] = entry


func _clear_all_binding_textures() -> void:
	for binding_value in _bindings_by_id.values():
		if not binding_value is Dictionary:
			continue
		var bitmap := (binding_value as Dictionary).get("bitmap") as TextureRect
		if bitmap != null and is_instance_valid(bitmap):
			bitmap.texture = null


func _compute_classifications(force: bool) -> Dictionary:
	var result: Dictionary = {}
	_selection_error = ""
	if _visual_layers == null or not is_instance_valid(_visual_layers):
		_selection_error = "VisualLayers nie istnieje."
		return result
	if not _visual_layers.is_inside_tree():
		_selection_error = "VisualLayers nie znajduje się w drzewie sceny."
		return result
	if force:
		_visual_layers.force_update_transform()
	var viewport_rect := _visual_layers.get_viewport_rect()
	if viewport_rect.size.x <= 0.0 or viewport_rect.size.y <= 0.0:
		_selection_error = "Viewport mapy ma pusty rect."
		return result
	var prefetch_rect := _grown_viewport_rect(
		viewport_rect,
		_profile.prefetch_margin_viewports,
	)
	var retain_rect := _grown_viewport_rect(
		viewport_rect,
		_profile.retention_margin_viewports,
	)
	var viewport_center := viewport_rect.get_center()

	for asset_id_value in _bindings_by_id.keys():
		var asset_id := str(asset_id_value)
		var binding: Dictionary = _bindings_by_id[asset_id]
		var priority := WindowPriority.ABSENT
		var distance_squared := INF
		var node := binding.get("node") as Node2D
		if (
			bool(binding.get("enabled", true))
			and node != null
			and is_instance_valid(node)
			and node.is_inside_tree()
			and node.is_visible_in_tree()
		):
			var screen_rect := _binding_viewport_rect(binding)
			distance_squared = screen_rect.get_center().distance_squared_to(viewport_center)
			if viewport_rect.intersects(screen_rect, true):
				priority = WindowPriority.VISIBLE
			elif prefetch_rect.intersects(screen_rect, true):
				priority = WindowPriority.PREFETCH
			elif retain_rect.intersects(screen_rect, true):
				priority = WindowPriority.RETAIN
		binding["priority"] = priority
		_bindings_by_id[asset_id] = binding

		var path := str(binding.get("path", ""))
		var existing: Dictionary = result.get(path, {
			"priority": WindowPriority.ABSENT,
			"distance_squared": INF,
		})
		if (
			priority < int(existing.get("priority", WindowPriority.ABSENT))
			or (
				priority == int(existing.get("priority", WindowPriority.ABSENT))
				and distance_squared < float(existing.get("distance_squared", INF))
			)
		):
			existing["priority"] = priority
			existing["distance_squared"] = distance_squared
		result[path] = existing
	return result


func _apply_classifications(classifications: Dictionary, force: bool) -> void:
	var signature_parts := PackedStringArray()
	var sorted_paths := PackedStringArray()
	for path_value in _paths.keys():
		sorted_paths.append(str(path_value))
	sorted_paths.sort()
	for path in sorted_paths:
		var classification: Dictionary = classifications.get(path, {
			"priority": WindowPriority.ABSENT,
			"distance_squared": INF,
		})
		signature_parts.append(
			"%s|%d" % [path, int(classification.get("priority", WindowPriority.ABSENT))]
		)
	var signature := "\n".join(signature_parts)
	if force or _invalidated or signature != _classification_signature:
		_generation += 1
		_classification_signature = signature
		_invalidated = false

	for path in sorted_paths:
		var entry: Dictionary = _paths[path]
		var classification: Dictionary = classifications.get(path, {
			"priority": WindowPriority.ABSENT,
			"distance_squared": INF,
		})
		var priority := int(classification.get("priority", WindowPriority.ABSENT))
		entry["priority"] = priority
		entry["distance_squared"] = float(classification.get("distance_squared", INF))
		if priority <= WindowPriority.PREFETCH:
			entry["last_required_generation"] = _generation
		if priority == WindowPriority.VISIBLE:
			entry["last_visible_generation"] = _generation
		_paths[path] = entry
		if int(entry.get("state", PathState.IDLE)) == PathState.RESIDENT:
			_assign_resident_texture(entry)


func _binding_viewport_rect(binding: Dictionary) -> Rect2:
	var node := binding.get("node") as Node2D
	var pixel_size := binding.get("pixel_size", Vector2i.ZERO) as Vector2i
	var size := Vector2(pixel_size)
	var transform := node.get_global_transform_with_canvas()
	var points := PackedVector2Array([
		transform * Vector2.ZERO,
		transform * Vector2(size.x, 0.0),
		transform * size,
		transform * Vector2(0.0, size.y),
	])
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)


func _grown_viewport_rect(viewport_rect: Rect2, margin_viewports: float) -> Rect2:
	var margin := viewport_rect.size * margin_viewports
	return viewport_rect.grow_individual(margin.x, margin.y, margin.x, margin.y)


func _poll_requests() -> void:
	var sorted_paths := PackedStringArray()
	for path_value in _paths.keys():
		sorted_paths.append(str(path_value))
	sorted_paths.sort()
	for path in sorted_paths:
		var entry: Dictionary = _paths[path]
		if int(entry.get("state", PathState.IDLE)) != PathState.LOADING:
			continue
		var progress: Array = []
		var status: ResourceLoader.ThreadLoadStatus = (
			_resource_load_threaded_get_status(path, progress)
		)
		if not progress.is_empty():
			entry["progress"] = clampf(float(progress[0]), 0.0, 1.0)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				_paths[path] = entry
			ResourceLoader.THREAD_LOAD_LOADED:
				if _remaining_commits_this_tick <= 0:
					_paths[path] = entry
					continue
				_remaining_commits_this_tick -= 1
				var loaded: Resource = _resource_load_threaded_get(path)
				_terminal_request_count += 1
				_commit_terminal_loaded_resource(entry, loaded)
				_paths[path] = entry
			ResourceLoader.THREAD_LOAD_FAILED:
				# The terminal get releases ResourceLoader's request token even on
				# failure; status polling alone is not request cleanup.
				_resource_load_threaded_get(path)
				_terminal_request_count += 1
				_commit_terminal_request_failure(
					entry,
					"ResourceLoader zgłosił THREAD_LOAD_FAILED.",
				)
				_paths[path] = entry
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				# INVALID means there is no claim left to consume. Calling get here
				# would manufacture a second loader error instead of releasing one.
				_terminal_request_count += 1
				_commit_terminal_request_failure(
					entry,
					"ResourceLoader zgłosił THREAD_LOAD_INVALID_RESOURCE.",
				)
				_paths[path] = entry


func _commit_terminal_loaded_resource(entry: Dictionary, loaded) -> void:
	entry["progress"] = 1.0
	if _request_descriptor_changed(entry):
		entry["texture"] = null
		entry["state"] = PathState.IDLE
		return
	if not loaded is Texture2D:
		_mark_failed(entry, "Załadowany zasób nie jest Texture2D.")
		return
	var texture := loaded as Texture2D
	if texture.get_size() != Vector2(entry.get("pixel_size", Vector2i.ZERO)):
		_mark_failed(entry, "Texture2D ma rozmiar inny niż zadeklarowany pixel_size.")
		return
	entry["cache_replace_required"] = false
	if (
		int(entry.get("priority", WindowPriority.ABSENT)) > WindowPriority.PREFETCH
		or (entry.get("binding_ids", []) as Array).is_empty()
	):
		entry["texture"] = null
		entry["state"] = PathState.IDLE
		return
	entry["texture"] = texture
	entry["state"] = PathState.RESIDENT
	entry["resident_generation"] = _generation
	entry["failure"] = ""
	_assign_resident_texture(entry)


func _commit_terminal_request_failure(entry: Dictionary, message: String) -> void:
	entry["progress"] = 1.0
	if _request_descriptor_changed(entry):
		# A failure belongs to the descriptor captured by request_*. The live
		# descriptor is still eligible and must get one fresh cache-replacing
		# request instead of inheriting a sticky failure from obsolete input.
		_drop_resident_texture(entry)
		entry["state"] = PathState.IDLE
		entry["failure"] = ""
		entry["cache_replace_required"] = true
		return
	_mark_failed(entry, message)


func _request_descriptor_changed(entry: Dictionary) -> bool:
	return (
		str(entry.get("request_sha256", "")) != str(entry.get("sha256", ""))
		or entry.get("request_pixel_size", Vector2i.ZERO) != entry.get(
			"pixel_size",
			Vector2i.ZERO,
		)
	)


func _start_eligible_requests() -> void:
	if _profile == null:
		return
	var available_slots := _profile.max_in_flight_requests - _loading_path_count()
	var candidates: Array[Dictionary] = []
	for path_value in _paths.keys():
		var path := str(path_value)
		var entry: Dictionary = _paths[path]
		var priority := int(entry.get("priority", WindowPriority.ABSENT))
		if (
			int(entry.get("state", PathState.IDLE)) == PathState.IDLE
			and priority <= WindowPriority.PREFETCH
			and not (entry.get("binding_ids", []) as Array).is_empty()
		):
			candidates.append({
				"path": path,
				"priority": priority,
				"distance_squared": float(entry.get("distance_squared", INF)),
			})
	candidates.sort_custom(_request_candidate_before)

	for candidate in candidates:
		if available_slots <= 0 and _remaining_commits_this_tick <= 0:
			break
		var path := str(candidate.get("path", ""))
		var entry: Dictionary = _paths[path]
		var priority := int(candidate.get("priority", WindowPriority.ABSENT))
		var cached: Resource = null
		if not bool(entry.get("cache_replace_required", false)):
			cached = _resource_get_cached_ref(path)
		if cached != null and _remaining_commits_this_tick <= 0:
			continue
		if cached == null and available_slots <= 0:
			continue
		var pixel_count := int(entry.get("pixel_count", 0))
		var fits := _make_room_for(
			pixel_count,
			priority,
			float(candidate.get("distance_squared", INF)),
		)
		if not fits and priority != WindowPriority.VISIBLE:
			continue
		var started_request := _start_path_request(
			path,
			entry,
			cached,
			available_slots > 0,
		)
		_paths[path] = entry
		if started_request:
			available_slots -= 1


func _start_path_request(
	path: String,
	entry: Dictionary,
	cached: Resource,
	allow_threaded_request: bool,
) -> bool:
	if cached != null:
		_remaining_commits_this_tick -= 1
		_cache_reuse_count += 1
		entry["request_generation"] = _generation
		entry["request_sha256"] = str(entry.get("sha256", ""))
		entry["request_pixel_size"] = entry.get("pixel_size", Vector2i.ZERO)
		_commit_terminal_loaded_resource(entry, cached)
		return false
	if not allow_threaded_request:
		return false

	entry["request_generation"] = _generation
	entry["request_sha256"] = str(entry.get("sha256", ""))
	entry["request_pixel_size"] = entry.get("pixel_size", Vector2i.ZERO)
	entry["progress"] = 0.0
	var cache_mode := (
		ResourceLoader.CACHE_MODE_REPLACE
		if bool(entry.get("cache_replace_required", false))
		else ResourceLoader.CACHE_MODE_REUSE
	)
	var request_error: Error = _resource_load_threaded_request(
		path,
		cache_mode,
	)
	if request_error == OK:
		_request_count += 1
		entry["state"] = PathState.LOADING
		return true
	_mark_failed(entry, "Nie można rozpocząć żądania Texture2D: error=%d." % request_error)
	return false


func _resource_load_threaded_request(
	path: String,
	cache_mode: ResourceLoader.CacheMode,
) -> Error:
	return ResourceLoader.load_threaded_request(
		path,
		"Texture2D",
		false,
		cache_mode,
	)


func _resource_load_threaded_get_status(
	path: String,
	progress: Array,
) -> ResourceLoader.ThreadLoadStatus:
	return ResourceLoader.load_threaded_get_status(path, progress)


func _resource_load_threaded_get(path: String) -> Resource:
	return ResourceLoader.load_threaded_get(path)


func _resource_get_cached_ref(path: String) -> Resource:
	return ResourceLoader.get_cached_ref(path)


func _request_candidate_before(left: Dictionary, right: Dictionary) -> bool:
	var left_priority := int(left.get("priority", WindowPriority.ABSENT))
	var right_priority := int(right.get("priority", WindowPriority.ABSENT))
	if left_priority != right_priority:
		return left_priority < right_priority
	var left_distance := float(left.get("distance_squared", INF))
	var right_distance := float(right.get("distance_squared", INF))
	if left_distance != right_distance:
		return left_distance < right_distance
	return str(left.get("path", "")) < str(right.get("path", ""))


func _make_room_for(
	additional_pixels: int,
	candidate_priority: int,
	candidate_distance_squared: float,
) -> bool:
	if _profile == null:
		return false
	while _projected_pixels() + additional_pixels > _profile.resident_pixel_budget:
		var evictions := _eviction_candidates(
			candidate_priority,
			candidate_distance_squared,
		)
		if evictions.is_empty():
			break
		_evict_path(str(evictions[0].get("path", "")))
	return _projected_pixels() + additional_pixels <= _profile.resident_pixel_budget


func _eviction_candidates(
	candidate_priority: int,
	candidate_distance_squared: float,
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for path_value in _paths.keys():
		var path := str(path_value)
		var entry: Dictionary = _paths[path]
		if int(entry.get("state", PathState.IDLE)) != PathState.RESIDENT:
			continue
		var priority := int(entry.get("priority", WindowPriority.ABSENT))
		if priority == WindowPriority.VISIBLE:
			continue
		var distance := float(entry.get("distance_squared", INF))
		if (
			priority < candidate_priority
			or (
				priority == candidate_priority
				and distance <= candidate_distance_squared
			)
		):
			continue
		candidates.append({
			"path": path,
			"priority": priority,
			"distance_squared": distance,
			"last_required_generation": int(entry.get("last_required_generation", 0)),
		})
	candidates.sort_custom(_eviction_candidate_before)
	return candidates


func _eviction_candidate_before(left: Dictionary, right: Dictionary) -> bool:
	var left_priority := int(left.get("priority", WindowPriority.ABSENT))
	var right_priority := int(right.get("priority", WindowPriority.ABSENT))
	if left_priority != right_priority:
		return left_priority > right_priority
	var left_distance := float(left.get("distance_squared", INF))
	var right_distance := float(right.get("distance_squared", INF))
	if left_distance != right_distance:
		return left_distance > right_distance
	var left_generation := int(left.get("last_required_generation", 0))
	var right_generation := int(right.get("last_required_generation", 0))
	if left_generation != right_generation:
		return left_generation < right_generation
	return str(left.get("path", "")) < str(right.get("path", ""))


func _evict_absent_residents() -> void:
	var paths_to_evict := PackedStringArray()
	for path_value in _paths.keys():
		var path := str(path_value)
		var entry: Dictionary = _paths[path]
		if (
			int(entry.get("state", PathState.IDLE)) == PathState.RESIDENT
			and int(entry.get("priority", WindowPriority.ABSENT)) == WindowPriority.ABSENT
		):
			paths_to_evict.append(path)
	paths_to_evict.sort()
	for path in paths_to_evict:
		_evict_path(path)


func _trim_to_budget() -> void:
	if _profile == null:
		return
	while _projected_pixels() > _profile.resident_pixel_budget:
		var candidates := _eviction_candidates(WindowPriority.VISIBLE, -INF)
		if candidates.is_empty():
			break
		_evict_path(str(candidates[0].get("path", "")))


func _evict_path(path: String) -> void:
	if not _paths.has(path):
		return
	var entry: Dictionary = _paths[path]
	if int(entry.get("state", PathState.IDLE)) != PathState.RESIDENT:
		return
	_drop_resident_texture(entry)
	entry["state"] = PathState.IDLE
	entry["resident_generation"] = 0
	_paths[path] = entry
	_eviction_count += 1


func _drop_resident_texture(entry: Dictionary) -> void:
	for asset_id_value in entry.get("binding_ids", []) as Array:
		var asset_id := str(asset_id_value)
		if not _bindings_by_id.has(asset_id):
			continue
		var binding: Dictionary = _bindings_by_id[asset_id]
		var bitmap := binding.get("bitmap") as TextureRect
		if bitmap != null and is_instance_valid(bitmap):
			bitmap.texture = null
	entry["texture"] = null


func _assign_resident_texture(entry: Dictionary) -> void:
	var texture := entry.get("texture") as Texture2D
	if texture == null:
		return
	for asset_id_value in entry.get("binding_ids", []) as Array:
		var asset_id := str(asset_id_value)
		if not _bindings_by_id.has(asset_id):
			continue
		var binding: Dictionary = _bindings_by_id[asset_id]
		var bitmap := binding.get("bitmap") as TextureRect
		if bitmap != null and is_instance_valid(bitmap):
			bitmap.texture = texture


func _mark_failed(entry: Dictionary, message: String) -> void:
	_drop_resident_texture(entry)
	entry["state"] = PathState.FAILED
	entry["progress"] = 1.0
	entry["failure"] = message
	_failure_count += 1


func _prune_orphan_paths() -> void:
	var paths_to_remove := PackedStringArray()
	for path_value in _paths.keys():
		var path := str(path_value)
		var entry: Dictionary = _paths[path]
		if (
			(entry.get("binding_ids", []) as Array).is_empty()
			and int(entry.get("state", PathState.IDLE)) != PathState.LOADING
		):
			if int(entry.get("state", PathState.IDLE)) == PathState.RESIDENT:
				_drop_resident_texture(entry)
			paths_to_remove.append(path)
	for path in paths_to_remove:
		_paths.erase(path)


func _loading_path_count() -> int:
	var count := 0
	for entry_value in _paths.values():
		if (
			entry_value is Dictionary
			and int((entry_value as Dictionary).get("state", PathState.IDLE)) == PathState.LOADING
		):
			count += 1
	return count


func _resident_pixels() -> int:
	var pixels := 0
	for entry_value in _paths.values():
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		if int(entry.get("state", PathState.IDLE)) == PathState.RESIDENT:
			pixels += int(entry.get("pixel_count", 0))
	return pixels


func _pending_pixels() -> int:
	var pixels := 0
	for entry_value in _paths.values():
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		if int(entry.get("state", PathState.IDLE)) == PathState.LOADING:
			var request_size := entry.get(
				"request_pixel_size",
				Vector2i.ZERO,
			) as Vector2i
			var request_pixels := request_size.x * request_size.y
			if request_pixels > 0:
				pixels += request_pixels
			else:
				pixels += int(entry.get("pixel_count", 0))
	return pixels


func _projected_pixels() -> int:
	return _resident_pixels() + _pending_pixels()


func _begin_poll_cycle() -> void:
	var process_frame := Engine.get_process_frames()
	if process_frame == _commit_budget_frame:
		return
	_commit_budget_frame = process_frame
	_remaining_commits_this_tick = maxi(
		_profile.max_commits_per_tick if _profile != null else 1,
		1,
	)


func _has_runnable_idle_prefetch(projected_pixels: int) -> bool:
	if _profile == null:
		return false
	for entry_value in _paths.values():
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		if (
			int(entry.get("state", PathState.IDLE)) == PathState.IDLE
			and int(entry.get("priority", WindowPriority.ABSENT)) == WindowPriority.PREFETCH
			and not (entry.get("binding_ids", []) as Array).is_empty()
			and projected_pixels + int(entry.get("pixel_count", 0))
			<= _profile.resident_pixel_budget
		):
			return true
	return false


func _update_telemetry() -> void:
	var resident_pixels := _resident_pixels()
	var pending_pixels := _pending_pixels()
	var projected_pixels := resident_pixels + pending_pixels
	_peak_resident_pixels = maxi(_peak_resident_pixels, resident_pixels)
	var budget := _profile.resident_pixel_budget if _profile != null else 0

	var resident_texture_count := 0
	var failed_texture_count := 0
	var visible_required_texture_count := 0
	var visible_missing_texture_count := 0
	var visible_failed_texture_count := 0
	for entry_value in _paths.values():
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var state := int(entry.get("state", PathState.IDLE))
		var priority := int(entry.get("priority", WindowPriority.ABSENT))
		if state == PathState.RESIDENT:
			resident_texture_count += 1
		elif state == PathState.FAILED:
			failed_texture_count += 1
		if priority == WindowPriority.VISIBLE:
			visible_required_texture_count += 1
			if state != PathState.RESIDENT:
				visible_missing_texture_count += 1
			if state == PathState.FAILED:
				visible_failed_texture_count += 1

	var visible_required_asset_count := 0
	var visible_missing_asset_count := 0
	for binding_value in _bindings_by_id.values():
		if not binding_value is Dictionary:
			continue
		var binding := binding_value as Dictionary
		if int(binding.get("priority", WindowPriority.ABSENT)) != WindowPriority.VISIBLE:
			continue
		visible_required_asset_count += 1
		var path := str(binding.get("path", ""))
		var entry: Dictionary = _paths.get(path, {})
		if int(entry.get("state", PathState.IDLE)) != PathState.RESIDENT:
			visible_missing_asset_count += 1

	var loading_count := _loading_path_count()
	var has_idle_visible := false
	for entry_value in _paths.values():
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		if (
			int(entry.get("priority", WindowPriority.ABSENT)) == WindowPriority.VISIBLE
			and int(entry.get("state", PathState.IDLE)) == PathState.IDLE
		):
			has_idle_visible = true
			break
	var settled := (
		_configured
		and _selection_error.is_empty()
		and loading_count == 0
		and not has_idle_visible
		and not _has_runnable_idle_prefetch(projected_pixels)
	)
	if settled:
		_settled_generation = _generation

	_telemetry = {
		"configured": _configured,
		"cache_mode": "reuse",
		"generation": _generation,
		"settled_generation": _settled_generation,
		"settled": settled and _settled_generation == _generation,
		"selection_error": _selection_error,
		"world_position": _last_world_position,
		"visible_half_extent": _last_visible_half_extent,
		"tracked_asset_count": _bindings_by_id.size(),
		"tracked_canonical_path_count": _paths.size(),
		"resident_texture_count": resident_texture_count,
		"resident_pixels": resident_pixels,
		"estimated_rgba8_bytes": resident_pixels * ESTIMATED_RGBA8_BYTES_PER_PIXEL,
		"peak_resident_pixels": _peak_resident_pixels,
		"pending_pixels": pending_pixels,
		"projected_pixels": projected_pixels,
		"in_flight_count": loading_count,
		"visible_required_texture_count": visible_required_texture_count,
		"visible_missing_texture_count": visible_missing_texture_count,
		"visible_failed_texture_count": visible_failed_texture_count,
		"visible_missing_count": visible_missing_texture_count,
		"visible_required_asset_count": visible_required_asset_count,
		"visible_missing_asset_count": visible_missing_asset_count,
		"failed_texture_count": failed_texture_count,
		"failed_path_count": failed_texture_count,
		"request_count": _request_count,
		"terminal_request_count": _terminal_request_count,
		"outstanding_request_count": maxi(_request_count - _terminal_request_count, 0),
		"cache_reuse_count": _cache_reuse_count,
		"failure_count": _failure_count,
		"eviction_count": _eviction_count,
		"budget_pixels": budget,
		"budget_overcommit_pixels": maxi(projected_pixels - budget, 0),
	}


static func _canonical_resource_path(raw_path: String) -> String:
	var normalized := raw_path.strip_edges().replace("\\", "/")
	if not normalized.begins_with("res://"):
		return ""
	var suffix := normalized.substr("res://".length()).simplify_path()
	while suffix.begins_with("/"):
		suffix = suffix.substr(1)
	if suffix.is_empty() or suffix == "." or suffix.begins_with("../"):
		return ""
	return "res://" + suffix


static func _valid_lower_sha256(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (
			(code >= 48 and code <= 57)
			or (code >= 97 and code <= 102)
		):
			return false
	return true
