class_name UnderwaterMapRuntime
extends "res://scripts/diving/ContinuousDiveWorld.gd"

const NORMAL_PARALLAX_SCALE_META := &"normal_parallax_scale"
const AUTHORED_PARALLAX_SCALE_META := &"parallax_scale"
const VisualResidencyScript := preload(
	"res://underwater_map_workbench/runtime/UnderwaterMapVisualResidency.gd"
)
const VISUAL_RESIDENCY_PROFILE := preload(
	"res://underwater_map_workbench/runtime/UnderwaterMapVisualResidencyProfile.tres"
)
const VisualSurveyPlanScript := preload(
	"res://underwater_map_workbench/runtime/UnderwaterMapVisualSurveyPlan.gd"
)

var _visual_residency = VisualResidencyScript.new()
var _last_visual_stream_position := Vector2.ZERO
var _last_visual_half_extent := Vector2.ZERO
var _last_visual_survey_source_snapshot: Dictionary = {}
var _last_visual_survey_plan_metadata: Dictionary = {}
var _visual_survey_overview_mode := false
var _visual_survey_previous_reduced_motion := false

## Campaign-facing map host. The authored source is map_manifest.json;
## UnderwaterMap.tscn is its generated derivative and this node owns only
## the transient runtime layer.


func _process(_delta: float) -> void:
	_visual_residency.poll_pending_requests()


func _exit_tree() -> void:
	_visual_residency.shutdown_and_drain()


func _clear_runtime_dynamic() -> void:
	_visual_residency.detach()
	_last_visual_survey_source_snapshot.clear()
	_last_visual_survey_plan_metadata.clear()
	super._clear_runtime_dynamic()


func set_reduced_motion(enabled: bool) -> void:
	super.set_reduced_motion(enabled)
	_apply_visual_layer_motion_setting()
	_visual_residency.invalidate_window()
	_visual_residency.update_window(
		_last_visual_stream_position,
		_last_visual_half_extent,
		true,
	)


func _build_source_visual_layers() -> void:
	super._build_source_visual_layers()
	_apply_visual_layer_motion_setting()
	var visual_layers := get_node_or_null("RuntimeDynamic/VisualLayers") as Node2D
	if visual_layers == null:
		return
	var residency_errors := _visual_residency.configure(
		visual_layers,
		VISUAL_RESIDENCY_PROFILE,
	)
	for residency_error in residency_errors:
		push_error("Nie udało się skonfigurować rezydencji grafiki mapy: %s" % residency_error)


func update_streaming(
	world_position: Vector2,
	force: bool = false,
	visible_half_extent: Vector2 = Vector2.ZERO,
) -> void:
	super.update_streaming(world_position, force, visible_half_extent)
	_last_visual_stream_position = world_position
	_last_visual_half_extent = visible_half_extent
	_visual_residency.update_window(world_position, visible_half_extent, force)


func visual_residency_snapshot() -> Dictionary:
	return _visual_residency.telemetry_snapshot()


func is_visual_survey_window_ready() -> bool:
	var snapshot := _visual_residency.telemetry_snapshot()
	return (
		_visual_residency.is_visible_window_ready()
		and _visual_residency.is_settled()
		and int(snapshot.get("failed_path_count", 0)) == 0
	)


func visual_survey_source_snapshot() -> Dictionary:
	var compiler = MapSceneCompilerScript.new()
	return compiler.visual_survey_source_snapshot()


func verify_visual_survey_source_snapshot(snapshot: Dictionary) -> PackedStringArray:
	var compiler = MapSceneCompilerScript.new()
	return compiler.verify_visual_survey_source_snapshot(snapshot)


func visual_survey_plan_metadata() -> Dictionary:
	return _last_visual_survey_plan_metadata.duplicate(true)


func set_visual_survey_overview_mode(enabled: bool) -> void:
	if enabled == _visual_survey_overview_mode:
		if enabled:
			set_reduced_motion(true)
		return
	if enabled:
		_visual_survey_previous_reduced_motion = _reduced_motion
		_visual_survey_overview_mode = true
		set_reduced_motion(true)
		return
	_visual_survey_overview_mode = false
	set_reduced_motion(_visual_survey_previous_reduced_motion)


func is_visual_survey_overview_world_locked() -> bool:
	if not _visual_survey_overview_mode or not _reduced_motion:
		return false
	var visual_layers := get_node_or_null("RuntimeDynamic/VisualLayers") as Node2D
	if visual_layers == null:
		return false
	return _all_parallax_layers_world_locked(visual_layers)


func visual_survey_plan(
	viewport_size_pixels: Vector2i,
	camera_zoom: float,
) -> Array[Dictionary]:
	_last_visual_survey_source_snapshot.clear()
	_last_visual_survey_plan_metadata.clear()
	if viewport_size_pixels.x <= 0 or viewport_size_pixels.y <= 0:
		push_error("Visual survey wymaga dodatniego rozmiaru viewportu w pikselach.")
		return []
	if not is_finite(camera_zoom) or camera_zoom <= 0.0:
		push_error("Visual survey wymaga dodatniego, skończonego zoomu kamery.")
		return []
	var compiler = MapSceneCompilerScript.new()
	var source_snapshot: Dictionary = compiler.visual_survey_source_snapshot()
	var source_errors: PackedStringArray = source_snapshot.get("errors", PackedStringArray())
	if not source_errors.is_empty():
		for source_error in source_errors:
			push_error("Nie udało się pobrać snapshotu visual survey: %s" % source_error)
		return []
	_last_visual_survey_source_snapshot = source_snapshot.duplicate(true)
	var raw_plan: Dictionary = VisualSurveyPlanScript.build(
		source_snapshot.get("resolved_manifest", {}) as Dictionary,
		source_snapshot.get("navigation_base_raster", {}) as Dictionary,
		viewport_size_pixels,
		camera_zoom,
	)
	_last_visual_survey_plan_metadata = raw_plan.duplicate(true)
	_last_visual_survey_plan_metadata.erase("targets")
	_last_visual_survey_plan_metadata["source_snapshot"] = (
		_visual_survey_source_verification_snapshot(_last_visual_survey_source_snapshot)
	)
	var errors_value: Variant = raw_plan.get("errors", [])
	if errors_value is Array or errors_value is PackedStringArray:
		for error_value in errors_value:
			push_error("Nie udało się zbudować visual survey: %s" % str(error_value))
		if not errors_value.is_empty():
			return []
	var targets_value: Variant = raw_plan.get("targets", [])
	if not targets_value is Array:
		push_error("Visual survey nie opublikował tablicy targets.")
		return []
	var result: Array[Dictionary] = []
	for target_value in targets_value as Array:
		if not target_value is Dictionary:
			push_error("Visual survey opublikował cel niebędący obiektem.")
			return []
		var target_record := (target_value as Dictionary).duplicate(true)
		var purpose := str(target_record.get("purpose", ""))
		target_record["id"] = str(target_record.get("key", ""))
		target_record["kind"] = purpose
		target_record["target"] = _survey_vector(target_record.get("anchor_position", null))
		target_record["camera"] = _survey_vector(target_record.get("camera_center", null))
		target_record["overview"] = purpose == "overview_tile"
		target_record["world_rect"] = _survey_rect(
			target_record.get("visible_world_rect", null)
		)
		if purpose == "overview_tile":
			target_record["stitch_world_rect"] = _survey_rect(
				target_record.get("stitch_world_rect", null)
			)
		target_record["plan_sha256"] = str(raw_plan.get("plan_sha256", ""))
		result.append(target_record)
	return result


func _visual_survey_source_verification_snapshot(source: Dictionary) -> Dictionary:
	return {
		"snapshot_version": int(source.get("snapshot_version", 0)),
		"manifest_sha256": str(source.get("manifest_sha256", "")),
		"dependency_paths": (
			source.get("dependency_paths", PackedStringArray()) as PackedStringArray
		).duplicate(),
		"dependency_records": (source.get("dependency_records", []) as Array).duplicate(true),
		"dependency_fingerprint": str(source.get("dependency_fingerprint", "")),
		"gameplay_signature": str(source.get("gameplay_signature", "")),
		"presentation_fingerprint": str(source.get("presentation_fingerprint", "")),
	}


func _apply_visual_layer_motion_setting() -> void:
	var visual_layers := get_node_or_null("RuntimeDynamic/VisualLayers") as Node2D
	if visual_layers == null:
		return
	_apply_parallax_motion_recursive(visual_layers)


func _apply_parallax_motion_recursive(node: Node) -> void:
	if node is Parallax2D:
		var parallax := node as Parallax2D
		var normal_scale := _normal_parallax_scale(parallax)
		parallax.scroll_scale = Vector2.ONE if _reduced_motion else normal_scale
	for child in node.get_children():
		_apply_parallax_motion_recursive(child)


func _all_parallax_layers_world_locked(node: Node) -> bool:
	if node is Parallax2D and not (node as Parallax2D).scroll_scale.is_equal_approx(Vector2.ONE):
		return false
	for child in node.get_children():
		if not _all_parallax_layers_world_locked(child):
			return false
	return true


func _normal_parallax_scale(parallax: Parallax2D) -> Vector2:
	var normal_value: Variant = null
	if parallax.has_meta(NORMAL_PARALLAX_SCALE_META):
		normal_value = parallax.get_meta(NORMAL_PARALLAX_SCALE_META)
	if normal_value is Vector2:
		var has_authored_scale := (
			parallax.has_meta(AUTHORED_PARALLAX_SCALE_META)
			and parallax.get_meta(AUTHORED_PARALLAX_SCALE_META) is Vector2
		)
		if not has_authored_scale:
			parallax.set_meta(AUTHORED_PARALLAX_SCALE_META, normal_value)
		return normal_value as Vector2
	var authored_value: Variant = null
	if parallax.has_meta(AUTHORED_PARALLAX_SCALE_META):
		authored_value = parallax.get_meta(AUTHORED_PARALLAX_SCALE_META)
	var normal_scale := (authored_value as Vector2) if authored_value is Vector2 else parallax.scroll_scale
	if not authored_value is Vector2:
		parallax.set_meta(AUTHORED_PARALLAX_SCALE_META, normal_scale)
	parallax.set_meta(NORMAL_PARALLAX_SCALE_META, normal_scale)
	return normal_scale


func _survey_vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Array and (value as Array).size() == 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2.ZERO


func _survey_rect(value: Variant) -> Rect2:
	if value is Rect2:
		return value as Rect2
	if value is Array and (value as Array).size() == 4:
		return Rect2(
			float((value as Array)[0]),
			float((value as Array)[1]),
			float((value as Array)[2]),
			float((value as Array)[3]),
		)
	return Rect2()
