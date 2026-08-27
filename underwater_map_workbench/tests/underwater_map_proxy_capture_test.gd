extends SceneTree

const MAP_RUNTIME_SCRIPT_PATH := "res://underwater_map_workbench/runtime/UnderwaterMapRuntime.gd"
const MAP_MANIFEST_PATH := "res://underwater_map_workbench/map_manifest.json"
const MAP_SCENE_PATH := "res://underwater_map_workbench/UnderwaterMap.tscn"
const UnderwaterMapRuntimeScript := preload(MAP_RUNTIME_SCRIPT_PATH)

const OUTPUT_ROOT := "user://test_underwater_map_visual_survey"
const REPORT_FILE_NAME := "visual_survey.json"
const OVERVIEW_FILE_NAME := "overview.png"
const CAPTURE_RESOLUTION := Vector2i(1280, 720)
const OVERVIEW_RESOLUTION := Vector2i(3840, 2160)
const GAMEPLAY_ZOOM := 1.2
const VIEWPORT_READY_FRAME_LIMIT := 60
const RUNTIME_READY_FRAME_LIMIT := 240
const RESIDENCY_SETTLE_TIMEOUT_MSEC := 20_000
const REQUIRED_STABLE_DRAWS := 2
const CAPTURE_CLEAR_COLOR := Color("071d2a")
const REQUIRED_SURVEY_KINDS := [
	"landmark_approach",
	"structure_entrance_approach",
	"vertical_sector",
	"overview_tile",
]
const GAP_INSPECTION_LAYERS := ["L01", "L02"]

const SNAPSHOT_INTEGER_FIELDS := [
	"generation",
	"settled_generation",
	"visible_missing_count",
	"failed_path_count",
	"resident_texture_count",
	"resident_pixels",
	"pending_pixels",
	"in_flight_count",
	"estimated_rgba8_bytes",
	"peak_resident_pixels",
	"budget_overcommit_pixels",
]

var _capture_host: Node2D
var _map: Node2D
var _camera: Camera2D
var _failed := false
var _viewport_world_size := Vector2.ZERO
var _overview_world_lock_check_count := 0
var _overview_transform_check_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		_fail("Visual survey capture requires a native, non-embedded Godot window.")
		return
	if not await _configure_capture_viewport():
		return
	if not _prepare_output_directory():
		return
	if not await _instantiate_runtime():
		return

	_viewport_world_size = Vector2(CAPTURE_RESOLUTION) / GAMEPLAY_ZOOM
	var world_size := _runtime_world_size()
	if not _is_positive_finite_vector(world_size):
		_fail("UnderwaterMapRuntime returned an invalid world size: %s." % str(world_size))
		return

	var plan_value: Variant = _map.call(
		"visual_survey_plan",
		CAPTURE_RESOLUTION,
		GAMEPLAY_ZOOM,
	)
	if not (plan_value is Array):
		_fail("visual_survey_plan(viewport_size_pixels, camera_zoom) must return an Array.")
		return
	var survey_plan: Array[Dictionary] = []
	for plan_item in plan_value as Array:
		if not (plan_item is Dictionary):
			_fail("Every visual survey plan item must be a Dictionary.")
			return
		survey_plan.append((plan_item as Dictionary).duplicate(true))
	var plan_metadata := _read_visual_survey_plan_metadata("initial plan")
	if plan_metadata.is_empty():
		return
	var source_snapshot_value: Variant = plan_metadata.get("source_snapshot", null)
	if not source_snapshot_value is Dictionary:
		_fail("visual_survey_plan_metadata() must publish its exact source_snapshot.")
		return
	var source_snapshot := (source_snapshot_value as Dictionary).duplicate(true)
	if not _source_snapshot_is_stable(source_snapshot, "after initial plan"):
		return
	if not _validate_source_scene_binding(source_snapshot, "after initial plan"):
		return
	if not _validate_survey_plan(survey_plan, world_size):
		return
	if str(plan_metadata.get("plan_sha256", "")) != str(survey_plan[0].get("plan_sha256", "")):
		_fail("Visual survey targets and metadata do not share the same plan_sha256.")
		return
	var coverage_value: Variant = plan_metadata.get("coverage_contract", null)
	if not coverage_value is Dictionary:
		_fail("visual_survey_plan_metadata() must publish coverage_contract.")
		return
	if not _validate_survey_coverage(
		survey_plan,
		world_size,
		coverage_value as Dictionary,
	):
		return
	if not _validate_declared_survey_counts(survey_plan, plan_metadata):
		return
	var repeated_plan_value: Variant = _map.call(
		"visual_survey_plan",
		CAPTURE_RESOLUTION,
		GAMEPLAY_ZOOM,
	)
	if not repeated_plan_value is Array:
		_fail("Repeated visual_survey_plan call must return an Array.")
		return
	var repeated_plan: Array[Dictionary] = []
	for repeated_item: Variant in repeated_plan_value as Array:
		if not repeated_item is Dictionary:
			_fail("Repeated visual survey plan contains a non-Dictionary item.")
			return
		repeated_plan.append((repeated_item as Dictionary).duplicate(true))
	var repeated_metadata := _read_visual_survey_plan_metadata("repeated plan")
	if repeated_metadata.is_empty():
		return
	if _survey_plan_signature(survey_plan) != _survey_plan_signature(repeated_plan):
		_fail("Visual survey plan must be deterministic for one stable runtime snapshot.")
		return
	if (
		str(repeated_metadata.get("plan_sha256", ""))
		!= str(plan_metadata.get("plan_sha256", ""))
		or JSON.stringify(
			_json_safe(repeated_metadata.get("coverage_contract", {})),
			"",
			true,
			true,
		)
		!= JSON.stringify(
			_json_safe(plan_metadata.get("coverage_contract", {})),
			"",
			true,
			true,
		)
	):
		_fail("Repeated visual survey metadata differs from the initial plan contract.")
		return
	var repeated_source_value: Variant = repeated_metadata.get("source_snapshot", null)
	if (
		not repeated_source_value is Dictionary
		or str((repeated_source_value as Dictionary).get("dependency_fingerprint", ""))
		!= str(source_snapshot.get("dependency_fingerprint", ""))
	):
		_fail("Repeated visual survey plan used a different dependency snapshot.")
		return
	if not _source_snapshot_is_stable(source_snapshot, "after repeated plan"):
		return

	var overview_image := Image.create(
		OVERVIEW_RESOLUTION.x,
		OVERVIEW_RESOLUTION.y,
		false,
		Image.FORMAT_RGBA8,
	)
	overview_image.fill(Color.BLACK)
	var overview_coverage := Image.create(
		OVERVIEW_RESOLUTION.x,
		OVERVIEW_RESOLUTION.y,
		false,
		Image.FORMAT_L8,
	)
	overview_coverage.fill(Color.BLACK)

	var captures: Array[Dictionary] = []
	var overview_tile_count := 0
	for plan_index in range(survey_plan.size()):
		if plan_index % 32 == 0 and not _source_snapshot_is_stable(
			source_snapshot,
			"before target %d" % plan_index,
		):
			return
		var record := survey_plan[plan_index]
		var capture_result: Dictionary = await _capture_plan_record(
			plan_index,
			record,
			world_size,
			overview_image,
			overview_coverage,
		)
		if capture_result.is_empty():
			return
		captures.append(capture_result)
		if bool(record["overview"]):
			overview_tile_count += 1

	if (
		_overview_world_lock_check_count != overview_tile_count
		or _overview_transform_check_count != overview_tile_count
	):
		_fail(
			"Every overview tile must pass both world-lock and stitch transform checks."
		)
		return
	if not _overview_coverage_complete(overview_coverage):
		_fail("Overview survey tiles do not cover every output pixel.")
		return
	if not _image_has_non_clear_sample(overview_image):
		_fail("Overview contains only the configured clear color; no map render was captured.")
		return
	if not _source_snapshot_is_stable(source_snapshot, "capture end"):
		return
	if not _save_image(OVERVIEW_FILE_NAME, overview_image):
		return

	var final_snapshot := _read_residency_snapshot("final report")
	if final_snapshot.is_empty():
		return
	var report := {
		"schema": "underwater_map_visual_survey_v2",
		"technical_capture_only": true,
		"certifies_art": false,
		"certifies_reachability": false,
		"runtime_script": MAP_RUNTIME_SCRIPT_PATH,
		"source_snapshot": _json_safe(source_snapshot),
		"plan_metadata": plan_metadata,
		"output_root": OUTPUT_ROOT,
		"capture_resolution": CAPTURE_RESOLUTION,
		"overview_resolution": OVERVIEW_RESOLUTION,
		"gameplay_zoom": GAMEPLAY_ZOOM,
		"viewport_world_size": _viewport_world_size,
		"world_size": world_size,
		"survey_plan": survey_plan,
		"captures": captures,
		"overview": {
			"file": OVERVIEW_FILE_NAME,
			"tile_count": overview_tile_count,
			"world_locked": true,
			"world_lock_check_count": _overview_world_lock_check_count,
			"stitch_transform_check_count": _overview_transform_check_count,
		},
		"final_telemetry": final_snapshot,
	}
	if not _source_snapshot_is_stable(source_snapshot, "before final report"):
		return
	if not _save_report(report):
		return

	print(
		"Underwater map visual survey saved: %s"
		% ProjectSettings.globalize_path(OUTPUT_ROOT)
	)
	_cleanup_scene()
	quit(0)


func _configure_capture_viewport() -> bool:
	root.gui_disable_input = true
	RenderingServer.set_default_clear_color(Color("071d2a"))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(CAPTURE_RESOLUTION)
	Engine.max_fps = 0
	for _frame in range(VIEWPORT_READY_FRAME_LIMIT):
		await process_frame
		if Vector2i(root.get_texture().get_size()) == CAPTURE_RESOLUTION:
			return true
	_fail(
		"Native capture viewport did not reach %s; last rendered size was %s."
		% [str(CAPTURE_RESOLUTION), str(root.get_texture().get_size())]
	)
	return false


func _instantiate_runtime() -> bool:
	_capture_host = Node2D.new()
	_capture_host.name = "UnderwaterMapVisualSurveyHost"
	root.add_child(_capture_host)

	var runtime_instance: Variant = UnderwaterMapRuntimeScript.new()
	if not (runtime_instance is Node2D):
		if runtime_instance != null and runtime_instance is Object:
			(runtime_instance as Object).free()
		_fail("UnderwaterMapRuntime must instantiate as Node2D.")
		return false
	_map = runtime_instance as Node2D
	_map.name = "UnderwaterMapRuntimeSurvey"
	_capture_host.add_child(_map)

	_camera = Camera2D.new()
	_camera.name = "VisualSurveyCamera"
	_camera.position_smoothing_enabled = false
	_camera.zoom = Vector2.ONE * GAMEPLAY_ZOOM
	_camera.enabled = true
	_capture_host.add_child(_camera)
	_camera.make_current()

	for _frame in range(RUNTIME_READY_FRAME_LIMIT):
		await process_frame
		if _runtime_api_ready() and _runtime_world_is_ready():
			return true
	_fail(
		"UnderwaterMapRuntime did not publish its survey API and positive world size "
		+ "within %d frames." % RUNTIME_READY_FRAME_LIMIT
	)
	return false


func _runtime_api_ready() -> bool:
	if _map == null or not is_instance_valid(_map):
		return false
	for method_name in [
		"world_size",
		"update_streaming",
		"visual_survey_plan",
		"visual_survey_plan_metadata",
		"verify_visual_survey_source_snapshot",
		"visual_residency_snapshot",
		"is_visual_survey_window_ready",
		"set_visual_survey_overview_mode",
		"is_visual_survey_overview_world_locked",
	]:
		if not _map.has_method(method_name):
			return false
	return true


func _runtime_world_size() -> Vector2:
	if _map == null or not is_instance_valid(_map) or not _map.has_method("world_size"):
		return Vector2.ZERO
	var value: Variant = _map.call("world_size")
	return value as Vector2 if value is Vector2 else Vector2.ZERO


func _runtime_world_is_ready() -> bool:
	var size := _runtime_world_size()
	return _is_positive_finite_vector(size) and size.x > 1.0 and size.y > 1.0


func _validate_survey_plan(plan: Array[Dictionary], world_size: Vector2) -> bool:
	if plan.is_empty():
		_fail("visual_survey_plan must publish at least one capture target.")
		return false
	var seen_ids := {}
	var overview_count := 0
	var target_count := 0
	var kind_counts := {}
	var shared_plan_sha256 := ""
	var world_bounds := Rect2(Vector2.ZERO, world_size)
	for plan_index in range(plan.size()):
		var record := plan[plan_index]
		for field_name in [
			"id", "kind", "target", "camera", "overview", "world_rect", "plan_sha256",
		]:
			if not record.has(field_name):
				_fail("Survey plan item %d is missing public field '%s'." % [plan_index, field_name])
				return false
		var record_id := str(record["id"]).strip_edges()
		var kind := str(record["kind"]).strip_edges()
		var plan_sha256 := str(record["plan_sha256"]).strip_edges()
		if record_id.is_empty() or kind.is_empty():
			_fail("Survey plan item %d must have non-empty id and kind." % plan_index)
			return false
		if seen_ids.has(record_id):
			_fail("Survey plan contains duplicate public id '%s'." % record_id)
			return false
		seen_ids[record_id] = true
		if not _valid_lower_sha256(plan_sha256):
			_fail("Survey plan item '%s' has an invalid plan_sha256." % record_id)
			return false
		if shared_plan_sha256.is_empty():
			shared_plan_sha256 = plan_sha256
		elif plan_sha256 != shared_plan_sha256:
			_fail("Survey plan items do not share one deterministic plan_sha256.")
			return false
		kind_counts[kind] = int(kind_counts.get(kind, 0)) + 1
		if not (record["target"] is Vector2) or not _is_finite_vector(record["target"] as Vector2):
			_fail("Survey plan item '%s' has an invalid target." % record_id)
			return false
		if not (record["camera"] is Vector2) or not _is_finite_vector(record["camera"] as Vector2):
			_fail("Survey plan item '%s' has an invalid camera." % record_id)
			return false
		if not (record["overview"] is bool):
			_fail("Survey plan item '%s' overview must be bool." % record_id)
			return false
		if not (record["world_rect"] is Rect2):
			_fail("Survey plan item '%s' world_rect must be Rect2." % record_id)
			return false
		var world_rect := record["world_rect"] as Rect2
		if not _is_positive_finite_vector(world_rect.size) or not _is_finite_vector(world_rect.position):
			_fail("Survey plan item '%s' has an invalid world_rect." % record_id)
			return false
		if not _rect_within_world(world_rect, world_bounds):
			_fail("Survey plan item '%s' world_rect lies outside the public world bounds." % record_id)
			return false
		if bool(record["overview"]):
			if not record.has("stitch_world_rect") or not (record["stitch_world_rect"] is Rect2):
				_fail("Overview survey item '%s' has no stitch_world_rect." % record_id)
				return false
			var stitch_world_rect := record["stitch_world_rect"] as Rect2
			if (
				not stitch_world_rect.has_area()
				or not _rect_within_world(stitch_world_rect, world_bounds)
				or not _rect_encloses_with_epsilon(world_rect, stitch_world_rect)
			):
				_fail(
					"Overview survey item '%s' has an invalid central stitch rect; visible=%s, stitch=%s, world=%s."
					% [record_id, str(world_rect), str(stitch_world_rect), str(world_bounds)]
				)
				return false
			overview_count += 1
		else:
			target_count += 1
	if overview_count == 0:
		_fail("visual_survey_plan must contain tiled overview records.")
		return false
	if target_count == 0:
		_fail("visual_survey_plan must contain at least one non-overview survey target.")
		return false
	for required_kind: String in REQUIRED_SURVEY_KINDS:
		if int(kind_counts.get(required_kind, 0)) <= 0:
			_fail("visual_survey_plan is missing required target kind '%s'." % required_kind)
			return false
	return true


func _validate_survey_coverage(
	plan: Array[Dictionary],
	world_size: Vector2,
	coverage_contract: Dictionary,
) -> bool:
	for field_name in [
		"landmark_subject_count",
		"active_structure_count",
		"structure_opening_count",
		"structure_opening_side_count",
		"vertical_band_count",
		"gap_component_digests",
		"overview_tile_count",
	]:
		if not coverage_contract.has(field_name):
			_fail("Visual survey coverage contract is missing '%s'." % field_name)
			return false

	var landmark_subjects := {}
	var structure_envelopes := {}
	var opening_sides := {}
	var vertical_bands := {}
	var vertical_intervals: Array[Vector2] = []
	var gap_components := {"L01": {}, "L02": {}}
	var overview_grids := {}
	var opening_side_total := 0
	for record: Dictionary in plan:
		var kind := str(record.get("kind", ""))
		match kind:
			"landmark_approach":
				var subject := str(record.get("survey_subject", ""))
				var subject_rank := int(record.get("subject_rank", -1))
				var footprint := _rect_from_record(record.get("landmark_footprint", null))
				var target := record["target"] as Vector2
				if (
					not _valid_lower_sha256(subject)
					or subject_rank < 0
					or not footprint.has_area()
					or footprint.grow(0.001).has_point(target)
				):
					_fail("Landmark survey target does not prove an approach outside its public footprint.")
					return false
				landmark_subjects["%s:%d" % [subject, subject_rank]] = true
			"structure_entrance_approach":
				var envelope := str(record.get("structure_envelope", ""))
				var opening := str(record.get("opening_digest", ""))
				var side := int(record.get("approach_side", 0))
				var structure_bounds := _rect_from_record(record.get("structure_bounds", null))
				if (
					not _valid_lower_sha256(envelope)
					or not _valid_lower_sha256(opening)
					or side not in [-1, 1]
					or not structure_bounds.has_area()
				):
					_fail("Structure entrance survey target has an invalid anonymous geometry contract.")
					return false
				structure_envelopes[envelope] = true
				var opening_side_list: Array = opening_sides.get(opening, [])
				if side in opening_side_list:
					_fail("Structure opening '%s' repeats approach side %d." % [opening, side])
					return false
				opening_side_list.append(side)
				opening_sides[opening] = opening_side_list
				opening_side_total += 1
			"vertical_sector":
				var band := int(record.get("vertical_band", -1))
				var vertical_rect := record["world_rect"] as Rect2
				if band < 0 or vertical_bands.has(band) or not vertical_rect.has_area():
					_fail("Vertical survey bands must be unique, non-negative and non-empty.")
					return false
				vertical_bands[band] = true
				vertical_intervals.append(Vector2(vertical_rect.position.y, vertical_rect.end.y))
			"backdrop_gap_inspection":
				var layer := str(record.get("inspection_scope", ""))
				var component := str(record.get("gap_component", ""))
				if (
					layer not in GAP_INSPECTION_LAYERS
					or not _valid_lower_sha256(component)
					or not bool(record.get("inspection_only", false))
				):
					_fail("Backdrop gap target must be anonymous, dynamic and inspection-only.")
					return false
				var layer_components := gap_components[layer] as Dictionary
				layer_components[component] = true
				gap_components[layer] = layer_components
			"overview_tile":
				var grid_value: Variant = record.get("overview_grid", null)
				if not grid_value is Array or (grid_value as Array).size() != 2:
					_fail("Overview survey target is missing its public grid coordinate.")
					return false
				var grid_key := "%d:%d" % [int((grid_value as Array)[0]), int((grid_value as Array)[1])]
				if overview_grids.has(grid_key):
					_fail("Overview survey repeats grid cell '%s'." % grid_key)
					return false
				overview_grids[grid_key] = true

	if landmark_subjects.size() != int(coverage_contract["landmark_subject_count"]):
		_fail("Visual survey does not cover every manifest-derived landmark footprint.")
		return false
	if structure_envelopes.size() != int(coverage_contract["active_structure_count"]):
		_fail("Visual survey does not cover every active structure envelope.")
		return false
	if opening_sides.size() != int(coverage_contract["structure_opening_count"]):
		_fail("Visual survey does not cover every raster-derived structure opening.")
		return false
	if opening_side_total != int(coverage_contract["structure_opening_side_count"]):
		_fail("Visual survey does not cover exactly two sides of every structure opening.")
		return false
	for opening: String in opening_sides:
		var required_sides := opening_sides[opening] as Array
		if required_sides.size() != 2 or -1 not in required_sides or 1 not in required_sides:
			_fail("Structure opening '%s' does not contain both opposing approach sides." % opening)
			return false
	if vertical_bands.size() != int(coverage_contract["vertical_band_count"]):
		_fail("Visual survey vertical band count does not match the dynamic coverage contract.")
		return false
	if not _vertical_intervals_cover_world(vertical_intervals, world_size.y):
		_fail("Visual survey vertical sectors leave an uncovered depth interval.")
		return false
	if overview_grids.size() != int(coverage_contract["overview_tile_count"]):
		_fail("Visual survey overview grid does not match the dynamic tile contract.")
		return false

	var expected_gap_value: Variant = coverage_contract["gap_component_digests"]
	if not expected_gap_value is Dictionary:
		_fail("Visual survey gap_component_digests must be a Dictionary.")
		return false
	var expected_gaps := expected_gap_value as Dictionary
	for gap_layer: String in GAP_INSPECTION_LAYERS:
		var expected_layer_value: Variant = expected_gaps.get(gap_layer, [])
		if not (expected_layer_value is Array or expected_layer_value is PackedStringArray):
			_fail("Backdrop gap coverage for %s must be an array." % gap_layer)
			return false
		var expected_count := 0
		for expected_component_value: Variant in expected_layer_value:
			expected_count += 1
			if not _valid_lower_sha256(str(expected_component_value)):
				_fail("Backdrop gap coverage for %s contains an invalid component digest." % gap_layer)
				return false
		var expected_components := _string_set(expected_layer_value)
		if expected_components.size() != expected_count:
			_fail("Backdrop gap coverage for %s repeats a component digest." % gap_layer)
			return false
		var actual_components := gap_components[gap_layer] as Dictionary
		if expected_components != actual_components:
			_fail(
				"Backdrop gap coverage for %s differs from the current geometry-derived components."
				% gap_layer
			)
			return false
	return true


func _validate_declared_survey_counts(
	plan: Array[Dictionary],
	plan_metadata: Dictionary,
) -> bool:
	var declared_value: Variant = plan_metadata.get("counts", null)
	if not declared_value is Dictionary:
		_fail("Visual survey plan metadata must publish dynamic counts.")
		return false
	var actual := {}
	for record: Dictionary in plan:
		var kind := str(record.get("kind", ""))
		actual[kind] = int(actual.get(kind, 0)) + 1
	var declared := declared_value as Dictionary
	if actual.size() != declared.size():
		_fail("Visual survey target kinds differ from the declared dynamic counts.")
		return false
	for kind: String in actual:
		if int(declared.get(kind, -1)) != int(actual[kind]):
			_fail("Visual survey count for '%s' differs from its dynamic plan metadata." % kind)
			return false
	return true


func _vertical_intervals_cover_world(intervals: Array[Vector2], world_height: float) -> bool:
	if intervals.is_empty() or not is_finite(world_height) or world_height <= 0.0:
		return false
	for index in range(1, intervals.size()):
		var current := intervals[index]
		var cursor := index - 1
		while cursor >= 0 and intervals[cursor].x > current.x:
			intervals[cursor + 1] = intervals[cursor]
			cursor -= 1
		intervals[cursor + 1] = current
	var covered_end := 0.0
	for interval: Vector2 in intervals:
		if interval.x > covered_end + 0.001:
			return false
		covered_end = maxf(covered_end, interval.y)
	return covered_end >= world_height - 0.001


func _string_set(value: Variant) -> Dictionary:
	var result := {}
	if value is Array or value is PackedStringArray:
		for item: Variant in value:
			var text := str(item)
			if _valid_lower_sha256(text):
				result[text] = true
	return result


func _capture_plan_record(
	plan_index: int,
	record: Dictionary,
	world_size: Vector2,
	overview_image: Image,
	overview_coverage: Image,
) -> Dictionary:
	var overview_mode := bool(record["overview"])
	_map.call("set_visual_survey_overview_mode", overview_mode)
	await process_frame
	if overview_mode:
		var world_lock_value: Variant = _map.call("is_visual_survey_overview_world_locked")
		if not world_lock_value is bool or not bool(world_lock_value):
			_fail("Overview capture requires every Parallax2D layer to be world-locked.")
			return {}
		_overview_world_lock_check_count += 1
	var camera_position := record["camera"] as Vector2
	_camera.position = camera_position
	_camera.zoom = Vector2.ONE * GAMEPLAY_ZOOM
	_camera.force_update_scroll()
	_map.call(
		"update_streaming",
		camera_position,
		true,
		_viewport_world_size * 0.5,
	)

	var requested_snapshot := _read_residency_snapshot("forced target %d" % plan_index)
	if requested_snapshot.is_empty():
		return {}
	var requested_generation := int(requested_snapshot["generation"])
	var wait_result: Dictionary = await _wait_for_visual_window(
		requested_generation,
		str(record["id"]),
	)
	if wait_result.is_empty():
		return {}

	var viewport_image := root.get_texture().get_image()
	if viewport_image == null or viewport_image.is_empty():
		_fail("Survey target %d produced an empty viewport image." % plan_index)
		return {}
	if viewport_image.get_size() != CAPTURE_RESOLUTION:
		_fail(
			"Survey target %d rendered at %s instead of %s."
			% [plan_index, str(viewport_image.get_size()), str(CAPTURE_RESOLUTION)]
		)
		return {}
	if viewport_image.get_format() != Image.FORMAT_RGBA8:
		viewport_image.convert(Image.FORMAT_RGBA8)
	if overview_mode:
		var post_draw_lock_value: Variant = _map.call("is_visual_survey_overview_world_locked")
		if not post_draw_lock_value is bool or not bool(post_draw_lock_value):
			_fail("Overview world-lock changed before the stitched image was sampled.")
			return {}

	var output_file := ""
	if bool(record["overview"]):
		if not _blit_overview_tile(
			viewport_image,
			record,
			world_size,
			overview_image,
			overview_coverage,
		):
			return {}
	else:
		output_file = "target_%04d.png" % plan_index
		if not _save_image(output_file, viewport_image):
			return {}

	var capture_result := {
		"plan_index": plan_index,
		"id": str(record["id"]),
		"kind": str(record["kind"]),
		"target": record["target"],
		"camera": camera_position,
		"world_rect": record["world_rect"],
		"overview": bool(record["overview"]),
		"file": output_file,
		"requested_generation": requested_generation,
		"requested_telemetry": requested_snapshot,
		"settled_telemetry": wait_result["snapshot"],
		"stable_post_draw_frames": wait_result["stable_post_draw_frames"],
		"settle_elapsed_msec": wait_result["elapsed_msec"],
	}
	if bool(record["overview"]):
		capture_result["stitch_world_rect"] = record["stitch_world_rect"]
	return capture_result


func _wait_for_visual_window(requested_generation: int, record_id: String) -> Dictionary:
	var started_msec := Time.get_ticks_msec()
	var stable_draws := 0
	var previous_stability_key := PackedInt64Array()
	var last_snapshot := {}
	while Time.get_ticks_msec() - started_msec <= RESIDENCY_SETTLE_TIMEOUT_MSEC:
		await process_frame
		await RenderingServer.frame_post_draw
		var snapshot := _read_residency_snapshot("survey target '%s'" % record_id)
		if snapshot.is_empty():
			return {}
		last_snapshot = snapshot
		var ready_value: Variant = _map.call("is_visual_survey_window_ready")
		if not (ready_value is bool):
			_fail("is_visual_survey_window_ready() must return bool.")
			return {}
		var qualifies := (
			bool(ready_value)
			and bool(snapshot["settled"])
			and int(snapshot["settled_generation"]) >= requested_generation
			and int(snapshot["visible_missing_count"]) == 0
			and int(snapshot["failed_path_count"]) == 0
		)
		if qualifies:
			var stability_key := _snapshot_stability_key(snapshot)
			if stability_key == previous_stability_key:
				stable_draws += 1
			else:
				previous_stability_key = stability_key
				stable_draws = 1
			if stable_draws >= REQUIRED_STABLE_DRAWS:
				return {
					"snapshot": snapshot,
					"stable_post_draw_frames": stable_draws,
					"elapsed_msec": Time.get_ticks_msec() - started_msec,
				}
		else:
			stable_draws = 0
			previous_stability_key = PackedInt64Array()
	_fail(
		"Timed out after %d ms waiting for target '%s' generation %d; last telemetry: %s"
		% [
			RESIDENCY_SETTLE_TIMEOUT_MSEC,
			record_id,
			requested_generation,
			JSON.stringify(_json_safe(last_snapshot)),
		]
	)
	return {}


func _read_residency_snapshot(context: String) -> Dictionary:
	var value: Variant = _map.call("visual_residency_snapshot")
	if not (value is Dictionary):
		_fail("visual_residency_snapshot() must return Dictionary during %s." % context)
		return {}
	var snapshot := (value as Dictionary).duplicate(true)
	if not snapshot.has("settled") or not (snapshot["settled"] is bool):
		_fail("Residency snapshot settled must be bool during %s." % context)
		return {}
	for field_name in SNAPSHOT_INTEGER_FIELDS:
		if not snapshot.has(field_name) or not (snapshot[field_name] is int):
			_fail("Residency snapshot %s must be int during %s." % [field_name, context])
			return {}
		var minimum_value := -1 if field_name == "settled_generation" else 0
		if int(snapshot[field_name]) < minimum_value:
			_fail(
				"Residency snapshot %s is below %d during %s."
				% [field_name, minimum_value, context]
			)
			return {}
	return snapshot


func _snapshot_stability_key(snapshot: Dictionary) -> PackedInt64Array:
	var key := PackedInt64Array()
	key.append(1 if bool(snapshot["settled"]) else 0)
	for field_name in SNAPSHOT_INTEGER_FIELDS:
		key.append(int(snapshot[field_name]))
	return key


func _blit_overview_tile(
	viewport_image: Image,
	record: Dictionary,
	world_size: Vector2,
	overview_image: Image,
	overview_coverage: Image,
) -> bool:
	var camera_position := record["camera"] as Vector2
	var stitch_world_rect := record["stitch_world_rect"] as Rect2
	var visible_rect := Rect2(camera_position - _viewport_world_size * 0.5, _viewport_world_size)
	var source_rect := _scaled_rect(
		stitch_world_rect,
		visible_rect,
		viewport_image.get_size(),
	)
	var destination_rect := _scaled_rect(
		stitch_world_rect,
		Rect2(Vector2.ZERO, world_size),
		OVERVIEW_RESOLUTION,
	)
	if not _overview_stitch_transform_is_consistent(
		stitch_world_rect,
		visible_rect,
		source_rect,
		world_size,
		destination_rect,
	):
		_fail("Overview record '%s' has a discontinuous world-to-stitch transform." % str(record["id"]))
		return false
	_overview_transform_check_count += 1
	if source_rect.size.x <= 0 or source_rect.size.y <= 0:
		_fail("Overview record '%s' maps to an empty viewport region." % str(record["id"]))
		return false
	if destination_rect.size.x <= 0 or destination_rect.size.y <= 0:
		_fail("Overview record '%s' maps to an empty overview region." % str(record["id"]))
		return false
	var existing_coverage := overview_coverage.get_region(destination_rect).get_data()
	if not existing_coverage.is_empty() and existing_coverage.find(255) >= 0:
		_fail("Overview record '%s' overlaps an already owned stitch region." % str(record["id"]))
		return false
	var tile_image := viewport_image.get_region(source_rect)
	if tile_image.is_empty():
		_fail("Overview record '%s' produced an empty tile." % str(record["id"]))
		return false
	if tile_image.get_size() != destination_rect.size:
		tile_image.resize(
			destination_rect.size.x,
			destination_rect.size.y,
			Image.INTERPOLATE_LANCZOS,
		)
	overview_image.blit_rect(
		tile_image,
		Rect2i(Vector2i.ZERO, tile_image.get_size()),
		destination_rect.position,
	)
	overview_coverage.fill_rect(destination_rect, Color.WHITE)
	return true


func _overview_stitch_transform_is_consistent(
	stitch_world_rect: Rect2,
	visible_world_rect: Rect2,
	source_rect: Rect2i,
	world_size: Vector2,
	destination_rect: Rect2i,
) -> bool:
	if source_rect.size.x <= 0 or source_rect.size.y <= 0:
		return false
	if destination_rect.size.x <= 0 or destination_rect.size.y <= 0:
		return false
	var source_projection := _pixel_rect_to_world_rect(
		source_rect,
		visible_world_rect,
		CAPTURE_RESOLUTION,
	)
	var destination_projection := _pixel_rect_to_world_rect(
		destination_rect,
		Rect2(Vector2.ZERO, world_size),
		OVERVIEW_RESOLUTION,
	)
	var source_tolerance := Vector2(
		visible_world_rect.size.x / float(CAPTURE_RESOLUTION.x),
		visible_world_rect.size.y / float(CAPTURE_RESOLUTION.y),
	) * 1.01
	var destination_tolerance := Vector2(
		world_size.x / float(OVERVIEW_RESOLUTION.x),
		world_size.y / float(OVERVIEW_RESOLUTION.y),
	) * 1.01
	return (
		_rect_edges_equal_with_tolerance(
			source_projection,
			stitch_world_rect,
			source_tolerance,
		)
		and _rect_edges_equal_with_tolerance(
			destination_projection,
			stitch_world_rect,
			destination_tolerance,
		)
	)


func _pixel_rect_to_world_rect(
	pixel_rect: Rect2i,
	world_domain: Rect2,
	pixel_domain_size: Vector2i,
) -> Rect2:
	var pixel_size := Vector2(pixel_domain_size)
	var normalized_start := Vector2(pixel_rect.position) / pixel_size
	var normalized_end := Vector2(pixel_rect.end) / pixel_size
	var world_start := world_domain.position + normalized_start * world_domain.size
	var world_end := world_domain.position + normalized_end * world_domain.size
	return Rect2(world_start, world_end - world_start)


func _rect_edges_equal_with_tolerance(
	left: Rect2,
	right: Rect2,
	tolerance: Vector2,
) -> bool:
	return (
		absf(left.position.x - right.position.x) <= tolerance.x
		and absf(left.position.y - right.position.y) <= tolerance.y
		and absf(left.end.x - right.end.x) <= tolerance.x
		and absf(left.end.y - right.end.y) <= tolerance.y
	)


func _scaled_rect(source: Rect2, domain: Rect2, pixel_size: Vector2i) -> Rect2i:
	var normalized_start := (source.position - domain.position) / domain.size
	var normalized_end := (source.end - domain.position) / domain.size
	var start := Vector2i(
		clampi(roundi(normalized_start.x * pixel_size.x), 0, pixel_size.x),
		clampi(roundi(normalized_start.y * pixel_size.y), 0, pixel_size.y),
	)
	var end := Vector2i(
		clampi(roundi(normalized_end.x * pixel_size.x), 0, pixel_size.x),
		clampi(roundi(normalized_end.y * pixel_size.y), 0, pixel_size.y),
	)
	return Rect2i(start, end - start)


func _overview_coverage_complete(coverage_image: Image) -> bool:
	if coverage_image == null or coverage_image.is_empty():
		return false
	var coverage_data := coverage_image.get_data()
	return not coverage_data.is_empty() and coverage_data.find(0) == -1


func _image_has_non_clear_sample(image: Image) -> bool:
	if image == null or image.is_empty():
		return false
	const SAMPLE_STRIDE := 16
	for y in range(0, image.get_height(), SAMPLE_STRIDE):
		for x in range(0, image.get_width(), SAMPLE_STRIDE):
			if not image.get_pixel(x, y).is_equal_approx(CAPTURE_CLEAR_COLOR):
				return true
	return false


func _survey_plan_signature(plan: Array[Dictionary]) -> String:
	return JSON.stringify(_json_safe(plan), "", true, true)


func _read_visual_survey_plan_metadata(context: String) -> Dictionary:
	var metadata_value: Variant = _map.call("visual_survey_plan_metadata")
	if not metadata_value is Dictionary:
		_fail("visual_survey_plan_metadata() must return a Dictionary during %s." % context)
		return {}
	var metadata := (metadata_value as Dictionary).duplicate(true)
	if not _valid_lower_sha256(str(metadata.get("plan_sha256", ""))):
		_fail("Visual survey metadata has an invalid plan_sha256 during %s." % context)
		return {}
	var source_value: Variant = metadata.get("source_snapshot", null)
	if not source_value is Dictionary:
		_fail("Visual survey metadata has no source_snapshot during %s." % context)
		return {}
	var source := source_value as Dictionary
	if (
		not _valid_lower_sha256(str(source.get("manifest_sha256", "")))
		or not str(source.get("dependency_fingerprint", "")).begins_with(
			"visual-survey-dependencies-v1:"
		)
		or not source.get("dependency_records", null) is Array
		or (source.get("dependency_records", []) as Array).is_empty()
	):
		_fail("Visual survey metadata has an incomplete dependency snapshot during %s." % context)
		return {}
	return metadata


func _validate_source_scene_binding(snapshot: Dictionary, context: String) -> bool:
	var manifest_sha := str(snapshot.get("manifest_sha256", ""))
	var packed_scene := ResourceLoader.load(
		MAP_SCENE_PATH,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE,
	) as PackedScene
	if packed_scene == null:
		_fail("Could not load generated map scene while validating %s." % context)
		return false
	var scene_root := packed_scene.instantiate()
	if scene_root == null:
		_fail("Could not instantiate generated map scene while validating %s." % context)
		return false
	var declared_manifest_sha := str(scene_root.get_meta("manifest_sha256", "")).to_lower()
	scene_root.free()
	if declared_manifest_sha != manifest_sha:
		_fail(
			"Generated map scene is stale during %s: scene declares %s, manifest is %s."
			% [context, declared_manifest_sha, manifest_sha]
		)
		return false
	return true


func _source_snapshot_is_stable(expected: Dictionary, context: String) -> bool:
	var verification_value: Variant = _map.call(
		"verify_visual_survey_source_snapshot",
		expected,
	)
	if not (verification_value is PackedStringArray or verification_value is Array):
		_fail("verify_visual_survey_source_snapshot() returned an invalid value during %s." % context)
		return false
	var verification_errors := PackedStringArray()
	for error_value: Variant in verification_value:
		verification_errors.append(str(error_value))
	if not verification_errors.is_empty():
		_fail(
			"Visual survey dependency closure changed during %s: %s"
			% [context, "; ".join(verification_errors)]
		)
		return false
	return true


func _prepare_output_directory() -> bool:
	var output_absolute := ProjectSettings.globalize_path(OUTPUT_ROOT)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_absolute)
	if directory_error != OK:
		_fail(
			"Could not create isolated survey directory %s (error %d)."
			% [OUTPUT_ROOT, directory_error]
		)
		return false
	var directory := DirAccess.open(OUTPUT_ROOT)
	if directory == null:
		_fail("Could not open isolated survey directory %s." % OUTPUT_ROOT)
		return false
	var stale_files := PackedStringArray()
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		if directory.current_is_dir():
			directory.list_dir_end()
			_fail(
				"Isolated survey directory contains unexpected subdirectory '%s'."
				% entry_name
			)
			return false
		stale_files.append(entry_name)
		entry_name = directory.get_next()
	directory.list_dir_end()
	for stale_file in stale_files:
		var remove_error := directory.remove(stale_file)
		if remove_error != OK:
			_fail(
				"Could not remove stale survey file '%s' (error %d)."
				% [stale_file, remove_error]
			)
			return false
	return true


func _save_image(file_name: String, image: Image) -> bool:
	var output_path := OUTPUT_ROOT.path_join(file_name)
	var error := image.save_png(output_path)
	if error != OK:
		_fail("Could not save survey PNG %s (error %d)." % [output_path, error])
		return false
	return true


func _save_report(report: Dictionary) -> bool:
	var output_path := OUTPUT_ROOT.path_join(REPORT_FILE_NAME)
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail(
			"Could not open survey report %s (error %d)."
			% [output_path, FileAccess.get_open_error()]
		)
		return false
	file.store_string(JSON.stringify(_json_safe(report), "\t", true))
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_fail("Could not write survey report %s (error %d)." % [output_path, write_error])
		return false
	return true


func _json_safe(value: Variant) -> Variant:
	if value is Dictionary:
		var safe_dictionary := {}
		for key in (value as Dictionary).keys():
			safe_dictionary[str(key)] = _json_safe((value as Dictionary)[key])
		return safe_dictionary
	if value is Array:
		var safe_array := []
		for item in value as Array:
			safe_array.append(_json_safe(item))
		return safe_array
	if value is PackedStringArray:
		var safe_strings := []
		for item: String in value as PackedStringArray:
			safe_strings.append(item)
		return safe_strings
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector2i:
		return [value.x, value.y]
	if value is Rect2:
		return {
			"position": _json_safe(value.position),
			"size": _json_safe(value.size),
		}
	if value is Rect2i:
		return {
			"position": _json_safe(value.position),
			"size": _json_safe(value.size),
		}
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	if value is StringName:
		return str(value)
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	return str(value)


func _rect_within_world(rect: Rect2, world_bounds: Rect2) -> bool:
	const EPSILON := 0.01
	return (
		rect.position.x >= world_bounds.position.x - EPSILON
		and rect.position.y >= world_bounds.position.y - EPSILON
		and rect.end.x <= world_bounds.end.x + EPSILON
		and rect.end.y <= world_bounds.end.y + EPSILON
	)


func _rect_encloses_with_epsilon(outer: Rect2, inner: Rect2) -> bool:
	const EPSILON := 0.01
	return (
		inner.position.x >= outer.position.x - EPSILON
		and inner.position.y >= outer.position.y - EPSILON
		and inner.end.x <= outer.end.x + EPSILON
		and inner.end.y <= outer.end.y + EPSILON
	)


func _rect_from_record(value: Variant) -> Rect2:
	if value is Rect2:
		return value as Rect2
	if value is Array and (value as Array).size() == 4:
		for component: Variant in value as Array:
			if not (component is int or component is float):
				return Rect2()
		return Rect2(
			float((value as Array)[0]),
			float((value as Array)[1]),
			float((value as Array)[2]),
			float((value as Array)[3]),
		)
	return Rect2()


func _is_finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


func _is_positive_finite_vector(value: Vector2) -> bool:
	return _is_finite_vector(value) and value.x > 0.0 and value.y > 0.0


func _valid_lower_sha256(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


func _cleanup_scene() -> void:
	if _capture_host != null and is_instance_valid(_capture_host):
		if _capture_host.get_parent() != null:
			_capture_host.get_parent().remove_child(_capture_host)
		_capture_host.free()
	_capture_host = null
	_map = null
	_camera = null


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error(message)
	_cleanup_scene()
	quit(1)
