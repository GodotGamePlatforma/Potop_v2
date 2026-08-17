@tool
class_name DiveVisualLayerStack
extends Node2D

const EXPECTED_LAYER_IDS: Array[StringName] = [
	&"L00_base_color",
	&"L01_ultra_far_silhouettes",
	&"L02_far_structures",
	&"L03_mid_drift_props",
	&"L04_near_terrain_skin",
	&"L05_foreground_occluders",
]

@export var validate_on_ready := true

var _layers_by_id: Dictionary = {}
var _reduced_motion := false
var _graphics_quality := "high"


func _ready() -> void:
	_rebuild_layer_index()
	set_graphics_quality(_graphics_quality)
	set_reduced_motion(_reduced_motion)
	if validate_on_ready:
		for error in validation_errors():
			push_error(error)


func layer_root(layer_id: StringName) -> DiveVisualLayer:
	if not _layers_by_id.has(layer_id):
		_rebuild_layer_index()
	return _layers_by_id.get(layer_id) as DiveVisualLayer


func content_root(layer_id: StringName, coordinate_space: StringName, bucket: StringName) -> Node2D:
	var layer := layer_root(layer_id)
	return layer.content_root(coordinate_space, bucket) if layer != null else null


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_rebuild_layer_index()
	for layer_id in EXPECTED_LAYER_IDS:
		var layer := _layers_by_id.get(layer_id) as DiveVisualLayer
		if layer != null:
			layer.set_reduced_motion(enabled)


func reduced_motion_enabled() -> bool:
	return _reduced_motion


func set_graphics_quality(quality_id: String) -> void:
	_graphics_quality = DiveVisualLayerProfile.normalize_quality(quality_id)
	_rebuild_layer_index()
	for layer_id in EXPECTED_LAYER_IDS:
		var layer := _layers_by_id.get(layer_id) as DiveVisualLayer
		if layer != null:
			layer.set_graphics_quality(_graphics_quality)


func graphics_quality() -> String:
	return _graphics_quality


func validation_errors() -> PackedStringArray:
	_rebuild_layer_index()
	var errors := PackedStringArray()
	if (
		not position.is_equal_approx(Vector2.ZERO)
		or not is_zero_approx(rotation)
		or not scale.is_equal_approx(Vector2.ONE)
		or not is_zero_approx(skew)
	):
		errors.append("Korzeń stosu sześciu planów musi zachować identity transform; przesuwaj wyłącznie elementy w Authored.")
	if not z_as_relative or z_index != 0 or top_level:
		errors.append("Korzeń stosu sześciu planów musi dziedziczyć transform i z-order VisualLayers.")
	var direct_layers: Array[DiveVisualLayer] = []
	for child in get_children():
		if child is DiveVisualLayer:
			direct_layers.append(child as DiveVisualLayer)
		else:
			errors.append("Stos sześciu planów nie może zawierać bezpośredniego węzła innego niż DiveVisualLayer: %s." % child.name)
	if direct_layers.size() != EXPECTED_LAYER_IDS.size():
		errors.append("Stos mapy wymaga dokładnie sześciu DiveVisualLayer; ma %d." % direct_layers.size())
	for index in EXPECTED_LAYER_IDS.size():
		var expected_id := EXPECTED_LAYER_IDS[index]
		if index >= direct_layers.size():
			errors.append("Brak wymaganej warstwy %s na pozycji %d." % [expected_id, index])
			continue
		var layer := direct_layers[index]
		if layer.layer_id() != expected_id:
			errors.append("Warstwa na pozycji %d ma ID %s zamiast %s." % [index, layer.layer_id(), expected_id])
	for expected_id in EXPECTED_LAYER_IDS:
		var layer := _layers_by_id.get(expected_id) as DiveVisualLayer
		if layer == null:
			errors.append("Brak wymaganej warstwy %s." % expected_id)
			continue
		for layer_error in layer.validation_errors():
			errors.append(layer_error)
	var previous_z := -4097
	var previous_scale := Vector2(-1.0, -1.0)
	for expected_id in EXPECTED_LAYER_IDS:
		var layer := _layers_by_id.get(expected_id) as DiveVisualLayer
		if layer == null or layer.profile == null:
			continue
		var layer_profile := layer.profile
		if layer_profile.z_index <= previous_z:
			errors.append("z_index warstwy %s musi być większy od poprzedniego planu." % expected_id)
		if (
			layer_profile.normal_scroll_scale.x <= previous_scale.x
			or layer_profile.normal_scroll_scale.y <= previous_scale.y
		):
			errors.append("normal_scroll_scale warstwy %s musi rosnąć w obu osiach względem poprzedniego planu." % expected_id)
		if not layer_profile.reduced_motion_scroll_scale.is_equal_approx(Vector2.ONE):
			errors.append("reduced_motion_scroll_scale warstwy %s musi wynosić Vector2.ONE." % expected_id)
		previous_z = layer_profile.z_index
		previous_scale = layer_profile.normal_scroll_scale
	var terrain_layer := _layers_by_id.get(&"L04_near_terrain_skin") as DiveVisualLayer
	if terrain_layer != null and terrain_layer.profile != null and not terrain_layer.profile.world_locked:
		errors.append("L04_near_terrain_skin musi pozostać world_locked.")
	var foreground_layer := _layers_by_id.get(&"L05_foreground_occluders") as DiveVisualLayer
	if foreground_layer != null and foreground_layer.profile != null and foreground_layer.profile.z_index >= 10:
		errors.append("L05_foreground_occluders musi mieć z_index < 10, aby nie zasłaniać nurka.")
	var element_ids := {}
	for node in find_children("*", "", true, false):
		if not (node is DiveVisualLayerElement):
			continue
		var element := node as DiveVisualLayerElement
		var element_id := String(element.element_id).strip_edges()
		if element_id.is_empty():
			continue
		var element_path := str(get_path_to(element))
		if element_ids.has(element_id):
			errors.append("Stos sześciu planów ma powtórzony element_id %s (%s i %s)." % [element_id, element_ids[element_id], element_path])
		else:
			element_ids[element_id] = element_path
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func presentation_state() -> Dictionary:
	_rebuild_layer_index()
	var layer_states := {}
	var ordered_ids := PackedStringArray()
	for layer_id in EXPECTED_LAYER_IDS:
		ordered_ids.append(String(layer_id))
		var layer := _layers_by_id.get(layer_id) as DiveVisualLayer
		if layer != null:
			layer_states[String(layer_id)] = layer.presentation_state()
	var errors := validation_errors()
	return {
		"valid": errors.is_empty(),
		"validation_errors": errors,
		"layer_count": _layers_by_id.size(),
		"layer_ids": ordered_ids,
		"reduced_motion": _reduced_motion,
		"graphics_quality": _graphics_quality,
		"layers": layer_states,
	}


func _get_configuration_warnings() -> PackedStringArray:
	return validation_errors()


func _rebuild_layer_index() -> void:
	_layers_by_id.clear()
	for child in get_children():
		if not (child is DiveVisualLayer):
			continue
		var layer := child as DiveVisualLayer
		var id := layer.layer_id()
		if id.is_empty() or _layers_by_id.has(id):
			continue
		_layers_by_id[id] = layer
