extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")

const CAPTURE_RESOLUTION := Vector2i(1280, 720)
const DEFAULT_CAMERA_SPEED := 600.0
const MIN_CAMERA_SPEED := 100.0
const MAX_CAMERA_SPEED := 2400.0
const DEFAULT_MOVIE_FPS := 30
const ROUTE_PATTERN := "horizontal_row_serpentine"
const MIN_MOVIE_WARMUP_FRAMES := 180
const STREAM_SETTLE_FRAME_LIMIT := 240
const CAMERA_CENTER_EPSILON := 1.5
const COVERAGE_EPSILON := 0.05
const TELEMETRY_INTERVAL_SECONDS := 0.1
const GUIDE_MANIFEST_PATH := "res://assets/diving/world/layout_guides/full_map/underwater_map_layout_guide_v1.json"

var _artifact_directory := ""
var _frames_directory := ""
var _quality := "high"
var _reduced_motion := false
var _camera_speed := DEFAULT_CAMERA_SPEED
var _movie_fps := DEFAULT_MOVIE_FPS
var _game
var _dive
var _camera: Camera2D
var _terrain_renderer: UnderwaterTerrainRenderer
var _curtain: CanvasLayer
var _route: Array[Dictionary] = []
var _x_centers: Array[float] = []
var _y_centers: Array[float] = []
var _visible_world_size := Vector2.ZERO
var _world_size := Vector2.ZERO
var _telemetry_file: FileAccess
var _next_telemetry_sample := 0.0
var _route_elapsed := 0.0
var _route_distance := 0.0
var _route_start_frame := 0
var _route_end_frame := 0
var _presentation_clock_enabled := false
var _route_clock_active := false
var _maximum_pending_chunks := 0
var _stream_wait_frames := 0
var _visited_regions: Dictionary = {}
var _failure_message := ""
var _session_state_unchanged := false
var _gameplay_signature_unchanged := false


func _ready() -> void:
	get_viewport().gui_disable_input = true
	var options := _parse_options(OS.get_cmdline_user_args())
	if not _configure_options(options):
		return
	if not _prepare_artifact_directories():
		return
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		_fail("Dive map visual survey requires a native, non-headless Godot window.")
		return

	var isolation_id := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var save_prefix := "user://test_dive_map_visual_survey_%s" % isolation_id
	SaveManager.configure_paths(
		save_prefix + ".tres",
		save_prefix + ".pending.tres",
		save_prefix + ".backup.tres"
	)
	SaveManager.set_persistence_enabled(false)
	if not str(SaveManager.save_path).begins_with("user://test_dive_map_visual_survey_"):
		_fail("Dive map visual survey could not isolate SaveManager paths.")
		return
	_curtain = _build_curtain()
	_game = GameRootScene.instantiate()
	add_child(_game)
	add_child(_curtain)
	await get_tree().process_frame
	if not await _configure_native_runtime():
		return
	if not _game.start_new_campaign("standard", 103, false, false):
		_fail("Dive map visual survey could not start a non-persistent standard campaign.")
		return
	await get_tree().process_frame

	var setup = ExpeditionSetupScript.new()
	setup.diver_id = "igor"
	setup.day = 12
	setup.oxygen_capacity = 100.0
	setup.backpack_capacity = 6
	setup.target_sector = "dead_city_rooftops_001"
	setup.selected_objective = "visual_survey"
	setup.tutorial_mode = false
	setup.equipped_gear["light"] = "diving_lantern_mk1"
	_game.game_state.tutorial.complete()
	var underwater_world = _game.game_state.underwater_world
	if not underwater_world.opened_shortcuts.has("SC-01"):
		underwater_world.opened_shortcuts.append("SC-01")
	if not underwater_world.activated_fixed_devices.has("junction_j7"):
		underwater_world.activated_fixed_devices.append("junction_j7")
	_game.start_dive(setup)
	for _frame in range(3):
		await get_tree().process_frame

	_dive = _game.current_scene
	if not _validate_and_prepare_dive_runtime():
		return
	if not _build_coverage_route():
		return
	if not _open_telemetry():
		return

	print("DIVE_MAP_VISUAL_SURVEY_PHASE fixture_ready")
	var session_before := _session_invariant_snapshot()
	print("DIVE_MAP_VISUAL_SURVEY_PHASE invariant_captured")
	var signature_before := _gameplay_signature()
	var first_position: Vector2 = _route[0].get("position", Vector2.ZERO)
	_apply_probe_position(first_position, true)
	var initial_wait := await _settle_visual_chunks(first_position)
	if initial_wait < 0:
		return
	print("DIVE_MAP_VISUAL_SURVEY_PHASE streaming_ready frames=%d" % initial_wait)
	for _frame in range(3):
		_apply_probe_position(first_position, false)
		await get_tree().process_frame

	if OS.has_feature("movie"):
		while Engine.get_process_frames() < MIN_MOVIE_WARMUP_FRAMES:
			_apply_probe_position(first_position, false)
			await get_tree().process_frame

	_curtain.visible = false
	# The native renderer can expose the previously completed curtain frame for
	# more than one process tick. Prime several visible draws before the route
	# clock starts so frame_000 and the trimmed movie both begin on live map art.
	for _frame in range(3):
		_apply_probe_position(first_position, false)
		await get_tree().process_frame
	_route_elapsed = 0.0
	_route_start_frame = Engine.get_process_frames()
	_route_clock_active = true
	if not await _run_visible_route(initial_wait):
		return
	_route_end_frame = Engine.get_process_frames()
	_route_clock_active = false
	_curtain.visible = true
	await get_tree().process_frame
	if _telemetry_file != null:
		_telemetry_file.close()
		_telemetry_file = null

	if _session_invariant_snapshot() != session_before:
		_fail("Visual survey changed local dive-session gameplay state.")
		return
	_session_state_unchanged = true
	if _gameplay_signature() != signature_before:
		_fail("Visual survey changed the map gameplay signature.")
		return
	_gameplay_signature_unchanged = true
	if _visited_regions.size() != 4:
		_fail("Visual survey did not sample all four presentation regions.")
		return
	if not _write_manifest("PASS"):
		return

	print(
		"DIVE_MAP_VISUAL_SURVEY_PASS cells=%d columns=%d rows=%d distance=%.2f duration=%.2f artifacts=%s"
		% [
			_route.size(),
			_x_centers.size(),
			_y_centers.size(),
			_route_distance,
			_visible_route_duration_seconds(),
			_artifact_directory,
		]
	)
	get_tree().quit(0)


func _process(delta: float) -> void:
	if not _presentation_clock_enabled or _dive == null or _terrain_renderer == null:
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	_terrain_renderer.advance_animation(delta)
	_dive._update_current_presentation(delta)
	_dive._update_environment_lighting(delta)
	if _route_clock_active:
		_route_elapsed += delta


func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var result := {}
	for argument in arguments:
		var text := str(argument)
		if not text.begins_with("--") or not text.contains("="):
			continue
		var separator := text.find("=")
		result[text.substr(2, separator - 2)] = text.substr(separator + 1)
	return result


func _configure_options(options: Dictionary) -> bool:
	_artifact_directory = str(options.get("artifact-dir", "")).strip_edges()
	if _artifact_directory.is_empty() or not _artifact_directory.is_absolute_path():
		_fail("--artifact-dir must be an absolute external directory.")
		return false
	_quality = str(options.get("quality", "high")).strip_edges().to_lower()
	if _quality not in ["low", "medium", "high"]:
		_fail("--quality must be low, medium or high.")
		return false
	var reduced_text := str(options.get("reduced-motion", "false")).strip_edges().to_lower()
	if reduced_text not in ["true", "false"]:
		_fail("--reduced-motion must be true or false.")
		return false
	_reduced_motion = reduced_text == "true"
	var speed_text := str(options.get("speed", str(DEFAULT_CAMERA_SPEED))).strip_edges()
	if not speed_text.is_valid_float():
		_fail("--speed must be a finite number of world units per second.")
		return false
	_camera_speed = speed_text.to_float()
	if not is_finite(_camera_speed) or _camera_speed < MIN_CAMERA_SPEED or _camera_speed > MAX_CAMERA_SPEED:
		_fail("--speed must stay between %.0f and %.0f." % [MIN_CAMERA_SPEED, MAX_CAMERA_SPEED])
		return false
	var fps_text := str(options.get("movie-fps", str(DEFAULT_MOVIE_FPS))).strip_edges()
	if not fps_text.is_valid_int():
		_fail("--movie-fps must be an integer.")
		return false
	_movie_fps = fps_text.to_int()
	if _movie_fps < 1 or _movie_fps > 240:
		_fail("--movie-fps must stay between 1 and 240.")
		return false
	return true


func _prepare_artifact_directories() -> bool:
	var directory_error := DirAccess.make_dir_recursive_absolute(_artifact_directory)
	if directory_error != OK:
		_fail("Could not create visual-survey artifact directory: %s" % _artifact_directory)
		return false
	_frames_directory = _artifact_directory.path_join("frames")
	directory_error = DirAccess.make_dir_recursive_absolute(_frames_directory)
	if directory_error != OK:
		_fail("Could not create visual-survey frames directory: %s" % _frames_directory)
		return false
	return true


func _configure_native_runtime() -> bool:
	var settings: Dictionary = _game.user_settings.snapshot()
	var display: Dictionary = settings.get("display", {}).duplicate(true)
	display["mode"] = "windowed"
	display["resolution"] = CAPTURE_RESOLUTION
	display["vsync"] = false
	display["max_fps"] = 0
	settings["display"] = display
	settings["graphics"] = {"quality": _quality}
	var accessibility: Dictionary = settings.get("accessibility", {}).duplicate(true)
	accessibility["reduced_motion"] = _reduced_motion
	settings["accessibility"] = accessibility
	var general: Dictionary = settings.get("general", {}).duplicate(true)
	general["pause_on_focus_loss"] = false
	settings["general"] = general
	if _game.user_settings.apply(settings, false) != OK:
		_fail("Dive map visual survey could not apply native capture settings.")
		return false
	for _frame in range(60):
		await get_tree().process_frame
		if Vector2i(get_viewport().get_texture().get_size()) == CAPTURE_RESOLUTION:
			return true
	_fail(
		"Dive map visual survey requires a %dx%d render target, got %s."
		% [CAPTURE_RESOLUTION.x, CAPTURE_RESOLUTION.y, str(get_viewport().get_texture().get_size())]
	)
	return false


func _validate_and_prepare_dive_runtime() -> bool:
	if _dive == null or _dive.name != "DiveScene":
		_fail("Visual survey must use the real GameRoot -> DiveScene runtime.")
		return false
	if bool(_game.campaign_persistence_enabled):
		_fail("Visual survey must keep campaign persistence disabled.")
		return false
	_camera = _dive.diver.get_node_or_null("Camera2D") as Camera2D
	if _camera == null or not _camera.enabled:
		_fail("Visual survey requires the production diver Camera2D.")
		return false
	_dive.set_process(false)
	_dive.diver.input_enabled = false
	_dive.diver.set_physics_process(false)
	_dive.set_graphics_quality(_quality)
	_dive.set_reduced_motion(_reduced_motion)
	_terrain_renderer = _dive.dive_map.get_node_or_null(
		"RuntimeDynamic/VisualLayers/TerrainRenderer"
	) as UnderwaterTerrainRenderer
	if _terrain_renderer == null:
		_fail("Visual survey could not find the production terrain renderer.")
		return false
	_terrain_renderer.auto_advance_animation = false
	_presentation_clock_enabled = true
	_dive.session.light_enabled = false
	_dive._apply_diver_light_state()
	var hud := _dive.get_node_or_null("DiveHUD") as CanvasLayer
	if hud == null:
		_fail("Visual survey could not find the production DiveHUD to hide it.")
		return false
	hud.visible = false
	for visual_path in ["AnimatedSprite2D", "VisualEffects", "LanternCone"]:
		var visual := _dive.diver.get_node_or_null(visual_path) as CanvasItem
		if visual != null:
			visual.visible = false
	var dive_light := _dive.diver.get_node_or_null("DiveLight") as PointLight2D
	if dive_light != null:
		dive_light.enabled = false
		dive_light.visible = false
	_camera.position_smoothing_enabled = false
	_camera.reset_smoothing()
	_camera.force_update_scroll()
	return true


func _build_coverage_route() -> bool:
	_world_size = _dive.dive_map.world_size()
	var viewport_size := Vector2(get_viewport().get_texture().get_size())
	var zoom := _camera.zoom.abs()
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		_fail("Visual survey camera zoom must be positive.")
		return false
	_visible_world_size = viewport_size / zoom
	_x_centers = _axis_camera_centers(_world_size.x, _visible_world_size.x)
	_y_centers = _axis_camera_centers(_world_size.y, _visible_world_size.y)
	if _x_centers.is_empty() or _y_centers.is_empty():
		_fail("Visual survey could not derive a camera coverage grid.")
		return false
	if not _validate_axis_coverage(_x_centers, _world_size.x, _visible_world_size.x):
		_fail("Visual survey camera columns do not cover the full map width.")
		return false
	if not _validate_axis_coverage(_y_centers, _world_size.y, _visible_world_size.y):
		_fail("Visual survey camera rows do not cover the full map height.")
		return false
	if not _validate_guide_manifest():
		return false

	_route.clear()
	for row_index in range(_y_centers.size()):
		var column_indices: Array[int] = []
		if row_index % 2 == 0:
			for column_index in range(_x_centers.size()):
				column_indices.append(column_index)
		else:
			for column_index in range(_x_centers.size() - 1, -1, -1):
				column_indices.append(column_index)
		for column_index in column_indices:
			_route.append({
				"cell_id": "C%02d-R%02d" % [column_index + 1, row_index + 1],
				"column": column_index + 1,
				"row": row_index + 1,
				"grid_index": row_index * _x_centers.size() + column_index,
				"route_index": _route.size(),
				"position": Vector2(_x_centers[column_index], _y_centers[row_index]),
			})
	if not _validate_horizontal_serpentine_route():
		return false
	_route_distance = 0.0
	for index in range(1, _route.size()):
		var previous: Vector2 = _route[index - 1].get("position", Vector2.ZERO)
		var current: Vector2 = _route[index].get("position", Vector2.ZERO)
		_route_distance += previous.distance_to(current)
	return true


func _validate_horizontal_serpentine_route() -> bool:
	var column_count := _x_centers.size()
	var row_count := _y_centers.size()
	var expected_count := column_count * row_count
	if _route.size() != expected_count:
		_fail(
			"Visual survey route must contain every grid cell exactly once: expected=%d actual=%d."
			% [expected_count, _route.size()]
		)
		return false
	var seen_cells: Dictionary = {}
	for route_index in range(_route.size()):
		var cell: Dictionary = _route[route_index]
		var row_index := floori(float(route_index) / float(column_count))
		var row_offset := route_index % column_count
		var expected_column_index := row_offset if row_index % 2 == 0 else column_count - 1 - row_offset
		var expected_cell_id := "C%02d-R%02d" % [expected_column_index + 1, row_index + 1]
		var cell_id := str(cell.get("cell_id", ""))
		if cell_id != expected_cell_id:
			_fail(
				"Visual survey route is not a left-to-right-first horizontal serpentine at index %d: expected=%s actual=%s."
				% [route_index, expected_cell_id, cell_id]
			)
			return false
		if seen_cells.has(cell_id):
			_fail("Visual survey route visits grid cell %s more than once." % cell_id)
			return false
		seen_cells[cell_id] = true
		var actual_position: Vector2 = cell.get("position", Vector2.ZERO)
		if (
			int(cell.get("column", 0)) != expected_column_index + 1
			or int(cell.get("row", 0)) != row_index + 1
			or int(cell.get("grid_index", -1)) != row_index * column_count + expected_column_index
			or int(cell.get("route_index", -1)) != route_index
			or not actual_position.is_equal_approx(
				Vector2(_x_centers[expected_column_index], _y_centers[row_index])
			)
		):
			_fail("Visual survey route metadata is inconsistent at %s." % cell_id)
			return false
	return true


func _axis_camera_centers(axis_length: float, visible_length: float) -> Array[float]:
	var centers: Array[float] = []
	var half_visible := visible_length * 0.5
	var maximum_center := maxf(axis_length - half_visible, half_visible)
	var center := half_visible
	while center < maximum_center - COVERAGE_EPSILON:
		centers.append(center)
		center += visible_length
	if centers.is_empty() or centers.back() < maximum_center - COVERAGE_EPSILON:
		centers.append(maximum_center)
	return centers


func _validate_axis_coverage(centers: Array[float], axis_length: float, visible_length: float) -> bool:
	var half_visible := visible_length * 0.5
	if centers[0] - half_visible > COVERAGE_EPSILON:
		return false
	if centers.back() + half_visible < axis_length - COVERAGE_EPSILON:
		return false
	for index in range(1, centers.size()):
		if centers[index] - centers[index - 1] > visible_length + COVERAGE_EPSILON:
			return false
	return true


func _validate_guide_manifest() -> bool:
	if not FileAccess.file_exists(GUIDE_MANIFEST_PATH):
		_fail("Visual survey requires the full-map layout-guide manifest.")
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(GUIDE_MANIFEST_PATH))
	if not parsed is Dictionary:
		_fail("Full-map layout-guide manifest is not valid JSON.")
		return false
	var manifest: Dictionary = parsed
	var camera_grid: Dictionary = manifest.get("camera_grid", {})
	var manifest_world := _vector2_from_array(manifest.get("world_size", []))
	var manifest_visible := _vector2_from_array(camera_grid.get("visible_world_size", []))
	if not manifest_world.is_equal_approx(_world_size):
		_fail("Layout-guide world size does not match the production dive runtime.")
		return false
	if not manifest_visible.is_equal_approx(_visible_world_size):
		_fail("Layout-guide camera footprint does not match the production camera.")
		return false
	if int(camera_grid.get("columns", 0)) != _x_centers.size() or int(camera_grid.get("rows", 0)) != _y_centers.size():
		_fail("Layout-guide camera grid does not match the derived survey grid.")
		return false
	return true


func _vector2_from_array(value) -> Vector2:
	if not value is Array or value.size() != 2:
		return Vector2.ZERO
	return Vector2(float(value[0]), float(value[1]))


func _open_telemetry() -> bool:
	_telemetry_file = FileAccess.open(_artifact_directory.path_join("telemetry.jsonl"), FileAccess.WRITE)
	if _telemetry_file == null:
		_fail("Could not open telemetry.jsonl for the visual survey.")
		return false
	return true


func _run_visible_route(initial_wait_frames: int) -> bool:
	_next_telemetry_sample = TELEMETRY_INTERVAL_SECONDS
	_write_telemetry_sample(str(_route[0].get("cell_id", "")), str(_route[0].get("cell_id", "")))
	if not await _capture_cell_frame(_route[0], initial_wait_frames):
		return false
	for index in range(1, _route.size()):
		var from_cell: Dictionary = _route[index - 1]
		var to_cell: Dictionary = _route[index]
		if not await _move_between_cells(from_cell, to_cell):
			return false
		var endpoint: Vector2 = to_cell.get("position", Vector2.ZERO)
		_apply_probe_position(endpoint, false)
		await get_tree().process_frame
		var waited := await _settle_visual_chunks(endpoint)
		if waited < 0:
			return false
		_stream_wait_frames += waited
		if not await _capture_cell_frame(to_cell, waited):
			return false
	return true


func _move_between_cells(from_cell: Dictionary, to_cell: Dictionary) -> bool:
	var start: Vector2 = from_cell.get("position", Vector2.ZERO)
	var finish: Vector2 = to_cell.get("position", Vector2.ZERO)
	var distance := start.distance_to(finish)
	if distance <= 0.0:
		return true
	var duration := distance / _camera_speed
	var segment_elapsed := 0.0
	while segment_elapsed < duration:
		var delta := 1.0 / float(_movie_fps) if OS.has_feature("movie") else maxf(get_process_delta_time(), 0.0001)
		segment_elapsed = minf(segment_elapsed + delta, duration)
		var ratio := segment_elapsed / duration
		var position := start.lerp(finish, ratio)
		_apply_probe_position(position, false)
		var visible_time := _visible_route_time_seconds()
		if visible_time + 0.0001 >= _next_telemetry_sample:
			_write_telemetry_sample(str(from_cell.get("cell_id", "")), str(to_cell.get("cell_id", "")))
			_next_telemetry_sample = visible_time + TELEMETRY_INTERVAL_SECONDS
		await get_tree().process_frame
	return true


func _apply_probe_position(world_position: Vector2, force_streaming: bool) -> void:
	_dive.diver.global_position = world_position
	_camera.force_update_scroll()
	_dive.dive_map.update_streaming(
		world_position,
		force_streaming,
		_dive._streaming_visible_half_extent()
	)
	var visual_context: Dictionary = _dive.dive_map.visual_context_at(world_position)
	var region_id := str(visual_context.get("region_id", ""))
	if not region_id.is_empty():
		_visited_regions[region_id] = true


func _settle_visual_chunks(world_position: Vector2) -> int:
	var streamer: Node = _dive.dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/VisualChunkStreamer")
	if streamer == null:
		_fail("Visual survey could not find the production visual chunk streamer.")
		return -1
	for wait_frame in range(STREAM_SETTLE_FRAME_LIMIT + 1):
		var pending: Array[String] = streamer.pending_chunk_keys()
		var desired: Array[String] = streamer.desired_chunk_keys()
		var loaded: Array[String] = streamer.loaded_chunk_keys()
		_maximum_pending_chunks = maxi(_maximum_pending_chunks, pending.size())
		var all_desired_loaded := true
		for desired_key in desired:
			if not loaded.has(desired_key):
				all_desired_loaded = false
				break
		if pending.is_empty() and all_desired_loaded:
			return wait_frame
		if wait_frame >= STREAM_SETTLE_FRAME_LIMIT:
			break
		_apply_probe_position(world_position, false)
		await get_tree().process_frame
	_fail("Visual chunks did not settle during the full-map survey.")
	return -1


func _capture_cell_frame(cell: Dictionary, waited_frames: int) -> bool:
	var position: Vector2 = cell.get("position", Vector2.ZERO)
	_camera.force_update_scroll()
	var actual_center := _camera.get_screen_center_position()
	if actual_center.distance_to(position) > CAMERA_CENTER_EPSILON:
		_fail(
			"Survey camera missed anchor %s: target=%s actual=%s."
			% [str(cell.get("cell_id", "")), str(position), str(actual_center)]
		)
		return false
	# `process_frame` resumes before the next draw. Holding the anchor for one
	# additional full frame makes the previously completed viewport image safe
	# to read without depending on the renderer-thread `frame_post_draw` signal.
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image.is_empty() or image.get_size() != CAPTURE_RESOLUTION:
		_fail("Visual survey produced an empty or incorrectly sized keyframe.")
		return false
	if not _image_has_visible_content(image):
		_fail("Visual survey captured a blank keyframe at %s." % str(cell.get("cell_id", "")))
		return false
	var frame_name := "frame_%03d.png" % int(cell.get("grid_index", -1))
	var save_error := image.save_png(_frames_directory.path_join(frame_name))
	if save_error != OK:
		_fail("Could not save visual-survey keyframe %s." % frame_name)
		return false
	var frame_record := _cell_record(cell, actual_center, waited_frames)
	if not _write_json(
		_frames_directory.path_join("frame_%03d.json" % int(cell.get("grid_index", -1))),
		frame_record
	):
		return false
	return true


func _image_has_visible_content(image: Image) -> bool:
	var step_x := maxi(image.get_width() / 16, 1)
	var step_y := maxi(image.get_height() / 9, 1)
	for y in range(step_y / 2, image.get_height(), step_y):
		for x in range(step_x / 2, image.get_width(), step_x):
			var color := image.get_pixel(x, y)
			if maxf(color.r, maxf(color.g, color.b)) > 0.01:
				return true
	return false


func _write_telemetry_sample(from_cell: String, to_cell: String) -> void:
	if _telemetry_file == null:
		return
	var streamer: Node = _dive.dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/VisualChunkStreamer")
	var pending: Array[String] = streamer.pending_chunk_keys() if streamer != null else []
	var desired: Array[String] = streamer.desired_chunk_keys() if streamer != null else []
	var loaded: Array[String] = streamer.loaded_chunk_keys() if streamer != null else []
	_maximum_pending_chunks = maxi(_maximum_pending_chunks, pending.size())
	var position: Vector2 = _dive.diver.global_position
	var camera_center := _camera.get_screen_center_position()
	var visual_context: Dictionary = _dive.dive_map.visual_context_at(position)
	_telemetry_file.store_line(JSON.stringify({
		"time_seconds": _visible_route_time_seconds(),
		"from_cell": from_cell,
		"to_cell": to_cell,
		"probe_position": [position.x, position.y],
		"camera_center": [camera_center.x, camera_center.y],
		"camera_error": camera_center.distance_to(position),
		"region_id": str(visual_context.get("region_id", "")),
		"landmark_id": _dive.dive_map.landmark_id_at(position),
		"depth": _dive.dive_map.depth_at(position),
		"active_chunk_count": _dive.dive_map.active_chunk_keys.size(),
		"desired_visual_chunks": desired,
		"pending_visual_chunks": pending,
		"loaded_visual_chunks": loaded,
	}))


func _cell_record(cell: Dictionary, actual_center: Vector2, waited_frames: int) -> Dictionary:
	var position: Vector2 = cell.get("position", Vector2.ZERO)
	var visual_context: Dictionary = _dive.dive_map.visual_context_at(position)
	return {
		"cell_id": str(cell.get("cell_id", "")),
		"column": int(cell.get("column", 0)),
		"row": int(cell.get("row", 0)),
		"grid_index": int(cell.get("grid_index", -1)),
		"route_index": int(cell.get("route_index", -1)),
		"target_center": [position.x, position.y],
		"actual_center": [actual_center.x, actual_center.y],
		"camera_error": actual_center.distance_to(position),
		"region_id": str(visual_context.get("region_id", "")),
		"landmark_id": _dive.dive_map.landmark_id_at(position),
		"depth": _dive.dive_map.depth_at(position),
		"movie_time_seconds": _visible_route_time_seconds(),
		"stream_wait_frames": waited_frames,
	}


func _session_invariant_snapshot() -> Dictionary:
	var session = _dive.session
	return {
		"setup": _expedition_setup_snapshot(session.setup),
		"oxygen_left": session.oxygen_left,
		"oxygen_capacity": session.oxygen_capacity,
		"health": session.health,
		"health_capacity": session.health_capacity,
		"starting_health": session.starting_health,
		"suit_condition": session.suit_condition,
		"cold_exposure": session.cold_exposure,
		"noise_level": session.noise_level,
		"last_noise_position": session.last_noise_position,
		"light_enabled": session.light_enabled,
		"repair_kit_charges": session.repair_kit_charges,
		"repair_kit_uses": session.repair_kit_uses,
		"leak_damage_progress": session.leak_damage_progress,
		"cold_damage_progress": session.cold_damage_progress,
		"noise_events": session.noise_events.duplicate(),
		"risk_events": session.risk_events.duplicate(),
		"disease_exposures": session.disease_exposures.duplicate(true),
		"injuries": session.injuries.duplicate(),
		"carried_items": session.carried_items.duplicate(true),
		"carried_item_order": session.carried_item_order.duplicate(),
		"backpack_capacity": session.backpack_capacity,
		"carry_capacity": session.carry_capacity,
		"item_weights": session.item_weights.duplicate(true),
		"remaining_container_contents": session.remaining_container_contents.duplicate(true),
		"opened_containers": session.opened_containers.duplicate(),
		"collected_world_item_ids": session.collected_world_item_ids.duplicate(),
		"rescued_survivor_ids": session.rescued_survivor_ids.duplicate(),
		"towed_survivor": session.towed_survivor,
		"towed_rescue_encounter_id": session.towed_rescue_encounter_id,
		"towed_survivor_stabilized": session.towed_survivor_stabilized,
		"placed_buoys": session.placed_buoys.duplicate(),
		"opened_shortcuts": session.opened_shortcuts.duplicate(),
		"activated_fixed_devices": session.activated_fixed_devices.duplicate(),
		"marked_heavy_objects": session.marked_heavy_objects.duplicate(),
		"recovered_backpacks": session.recovered_backpacks.duplicate(true),
		"recovered_gear_ids": session.recovered_gear_ids.duplicate(),
		"dropped_loot_updates": session.dropped_loot_updates.duplicate(true),
		"dropped_loot_sequence": session.dropped_loot_sequence,
		"buoy_charges": session.buoy_charges,
		"elapsed_time": session.elapsed_time,
		"tutorial_mode": session.tutorial_mode,
		"selected_combat_tool": session.selected_combat_tool,
		"harpoon_ammo": session.harpoon_ammo,
		"combat_cooldown_left": session.combat_cooldown_left,
		"tutorial_opened_mandatory_orders": session.tutorial_opened_mandatory_orders.duplicate(),
		"tutorial_baseline_step": session.tutorial_baseline_step,
		"tutorial_state": session.tutorial_state,
		"tutorial_event_ids": session.tutorial_event_ids.duplicate(),
	}


func _expedition_setup_snapshot(setup: Resource) -> Dictionary:
	if setup == null:
		return {}
	return {
		"diver_id": setup.diver_id,
		"diver_display_name": setup.diver_display_name,
		"diver_profession": setup.diver_profession,
		"diver_secondary_profession": setup.diver_secondary_profession,
		"diver_portrait_id": setup.diver_portrait_id,
		"diver_level": setup.diver_level,
		"diver_experience": setup.diver_experience,
		"diver_experience_to_next_level": setup.diver_experience_to_next_level,
		"diver_health": setup.diver_health,
		"diver_health_capacity": setup.diver_health_capacity,
		"diver_personal_oxygen_capacity": setup.diver_personal_oxygen_capacity,
		"diver_specialist_oxygen_multiplier": setup.diver_specialist_oxygen_multiplier,
		"oxygen_tank_capacity": setup.oxygen_tank_capacity,
		"diver_carry_capacity": setup.diver_carry_capacity,
		"station_staffed_carry_multiplier": setup.station_staffed_carry_multiplier,
		"competency_levels": setup.competency_levels.duplicate(true),
		"profession_talent_ids": setup.profession_talent_ids.duplicate(true),
		"item_weights": setup.item_weights.duplicate(true),
		"selected_gear": setup.selected_gear.duplicate(),
		"equipped_gear": setup.equipped_gear.duplicate(true),
		"weapon_ammunition": setup.weapon_ammunition,
		"backpack_capacity": setup.backpack_capacity,
		"oxygen_capacity": setup.oxygen_capacity,
		"suit_quality": setup.suit_quality,
		"start_entry_point": setup.start_entry_point,
		"target_sector": setup.target_sector,
		"selected_objective": setup.selected_objective,
		"objective_title": setup.objective_title,
		"objective_guidance": setup.objective_guidance,
		"objective_target_landmark_id": setup.objective_target_landmark_id,
		"objective_target_label": setup.objective_target_label,
		"base_support_level": setup.base_support_level,
		"station_work_pace_multiplier": setup.station_work_pace_multiplier,
		"suit_repair_amount": setup.suit_repair_amount,
		"operator_assigned": setup.operator_assigned,
		"technician_assigned": setup.technician_assigned,
		"operator_survivor_id": setup.operator_survivor_id,
		"technician_survivor_id": setup.technician_survivor_id,
		"can_place_buoys": setup.can_place_buoys,
		"can_start_from_buoy": setup.can_start_from_buoy,
		"can_mark_heavy_objects": setup.can_mark_heavy_objects,
		"buoy_charges": setup.buoy_charges,
		"difficulty_modifiers": setup.difficulty_modifiers.duplicate(true),
		"day": setup.day,
		"tutorial_mode": setup.tutorial_mode,
		"tutorial_baseline_step": setup.tutorial_baseline_step,
	}


func _gameplay_signature() -> String:
	if _game == null or _game.game_state == null or _game.game_state.underwater_world == null:
		return ""
	var blueprint = _game.game_state.underwater_world.blueprint
	return str(blueprint.map_gameplay_signature) if blueprint != null else ""


func _write_manifest(status: String) -> bool:
	var manifest := {
		"schema_version": 1,
		"status": status,
		"failure": _failure_message,
		"kind": "VISUAL_SURVEY",
		"created_at": Time.get_datetime_string_from_system(true, true),
		"godot": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"display_server": DisplayServer.get_name(),
		"movie_maker": OS.has_feature("movie"),
		"movie_fps": _movie_fps,
		"movie_visible_start_seconds": float(_route_start_frame) / float(_movie_fps),
		"movie_visible_duration_seconds": _visible_route_duration_seconds(),
		"quality": _quality,
		"reduced_motion": _reduced_motion,
		"camera_speed": _camera_speed,
		"resolution": [CAPTURE_RESOLUTION.x, CAPTURE_RESOLUTION.y],
		"camera_zoom": [_camera.zoom.x, _camera.zoom.y] if _camera != null else [],
		"visible_world_size": [_visible_world_size.x, _visible_world_size.y],
		"world_size": [_world_size.x, _world_size.y],
		"columns": _x_centers.size(),
		"rows": _y_centers.size(),
		"keyframe_count": _route.size(),
		"route_pattern": ROUTE_PATTERN,
		"route_start_cell": str(_route[0].get("cell_id", "")) if not _route.is_empty() else "",
		"route_end_cell": str(_route[-1].get("cell_id", "")) if not _route.is_empty() else "",
		"route_distance": _route_distance,
		"coverage_fraction": 1.0,
		"coverage_proof": "cartesian_camera_grid_axis_gaps_lte_visible_extent",
		"visited_regions": _visited_regions.keys(),
		"maximum_pending_visual_chunks": _maximum_pending_chunks,
		"stream_wait_frames": _stream_wait_frames,
		"gameplay_signature": _gameplay_signature(),
		"session_state_unchanged": _session_state_unchanged,
		"gameplay_signature_unchanged": _gameplay_signature_unchanged,
		"campaign_persistence_enabled": bool(_game.campaign_persistence_enabled),
		"artifacts": {
			"frames": "frames/frame_000.png..frame_%03d.png" % maxi(_route.size() - 1, 0),
			"telemetry": "telemetry.jsonl",
		},
	}
	return _write_json(_artifact_directory.path_join("run_manifest.json"), manifest)


func _visible_route_duration_seconds() -> float:
	if _route_end_frame <= _route_start_frame:
		return _route_distance / maxf(_camera_speed, 1.0)
	return float(_route_end_frame - _route_start_frame) / float(_movie_fps) if OS.has_feature("movie") else _route_elapsed


func _visible_route_time_seconds() -> float:
	if _route_start_frame <= 0:
		return 0.0
	if OS.has_feature("movie"):
		return maxf(
			float(Engine.get_process_frames() - _route_start_frame) / float(_movie_fps),
			0.0
		)
	return maxf(_route_elapsed, 0.0)


func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Could not write visual-survey JSON artifact: %s" % path)
		return false
	file.store_string(JSON.stringify(value, "  ", true))
	file.store_line("")
	file.close()
	return true


func _build_curtain() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "VisualSurveyWarmupCurtain"
	layer.layer = 4096
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color.BLACK
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	return layer


func _fail(message: String) -> void:
	if _failure_message.is_empty():
		_failure_message = message
	if _telemetry_file != null:
		_telemetry_file.close()
		_telemetry_file = null
	if not _artifact_directory.is_empty() and DirAccess.dir_exists_absolute(_artifact_directory):
		var failure_manifest := {
			"schema_version": 1,
			"status": "FAIL",
			"kind": "VISUAL_SURVEY",
			"failure": _failure_message,
		}
		var file := FileAccess.open(_artifact_directory.path_join("run_manifest.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(failure_manifest, "  ", true))
			file.store_line("")
			file.close()
	push_error(message)
	get_tree().quit(1)
