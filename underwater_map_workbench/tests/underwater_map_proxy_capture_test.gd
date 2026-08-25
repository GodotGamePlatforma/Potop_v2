extends SceneTree

const MAP_SCENE_PATH := "res://underwater_map_workbench/UnderwaterMap.tscn"
const OUTPUT_ROOT := "user://test_underwater_map_proxy_capture"
const CAPTURE_RESOLUTION := Vector2i(1280, 720)
const GAMEPLAY_ZOOM := 1.2
const GAMEPLAY_FRAME_COUNT := 6
const GROUND_CONTEXT_SCREEN_PIXELS := 96.0
const TOWER_CAPTURE_FILE := "tower_prototype_01.png"
const TOWER_ENTRY_CAPTURE_FILE := "tower_prototype_01_entry.png"
const TOWER_A_CAPTURE_FILE := "tower_prototype_01_a.png"
const TOWER_B_CAPTURE_FILE := "tower_prototype_01_b.png"
const TOWER_C_CAPTURE_FILE := "tower_prototype_01_c.png"
const TOWER_D_CAPTURE_FILE := "tower_prototype_01_d.png"
const TOWER_SHAFT_CAPTURE_FILE := "tower_prototype_01_shaft.png"
const TOWER_BASEMENT_CAPTURE_FILE := "tower_prototype_01_basement.png"
const TOWER_STRUCTURE_ID := "tower_prototype_01"
const TOWER_ORIGIN := Vector2(7760.0, 3120.0)
const TOWER_SIZE := Vector2(2240.0, 3680.0)
const TOWER_CAPTURE_MARGIN := Vector2(240.0, 240.0)
const TOWER_ENTRY_WORLD_POSITION := Vector2(7800.0, 3280.0)
const TOWER_A_WORLD_POSITION := Vector2(9680.0, 3860.0)
const TOWER_B_WORLD_POSITION := Vector2(8080.0, 4420.0)
const TOWER_C_WORLD_POSITION := Vector2(9640.0, 4700.0)
const TOWER_D_WORLD_POSITION := Vector2(9620.0, 5220.0)
const TOWER_SHAFT_WORLD_POSITION := Vector2(9040.0, 4000.0)
const TOWER_BASEMENT_WORLD_POSITION := Vector2(9240.0, 6620.0)
const VIEWPORT_READY_FRAME_LIMIT := 60
const RENDER_SETTLE_FRAMES := 4

var _capture_host: Node2D
var _map: Node2D
var _camera: Camera2D
var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		_fail("Proxy capture requires a native, non-embedded Godot window.")
		return
	if not await _configure_capture_viewport():
		return

	var map_resource := ResourceLoader.load(
		MAP_SCENE_PATH,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE,
	)
	if not map_resource is PackedScene:
		_fail("Could not load the exact generated map scene: %s." % MAP_SCENE_PATH)
		return
	var map_instance := (map_resource as PackedScene).instantiate()
	if not map_instance is Node2D:
		if map_instance != null:
			map_instance.free()
		_fail("The generated map scene root must be Node2D.")
		return
	_map = map_instance as Node2D
	if not _validate_map_instance(_map):
		return

	_capture_host = Node2D.new()
	_capture_host.name = "UnderwaterMapProxyCaptureHost"
	root.add_child(_capture_host)
	_capture_host.add_child(_map)
	_camera = Camera2D.new()
	_camera.name = "ProxyCaptureCamera"
	_camera.position_smoothing_enabled = false
	_camera.enabled = true
	_capture_host.add_child(_camera)
	_camera.make_current()

	for _frame in range(RENDER_SETTLE_FRAMES):
		await process_frame
	var viewport_size := Vector2i(root.get_texture().get_size())
	if viewport_size != CAPTURE_RESOLUTION:
		_fail(
			"Rendered viewport has size %s instead of %s."
			% [str(viewport_size), str(CAPTURE_RESOLUTION)]
		)
		return
	if not _prepare_output_directory():
		return

	var world_size: Vector2 = _map.get_meta("world_size")
	var full_zoom := minf(
		float(CAPTURE_RESOLUTION.x) / world_size.x,
		float(CAPTURE_RESOLUTION.y) / world_size.y,
	)
	if not is_finite(full_zoom) or full_zoom <= 0.0:
		_fail("Could not calculate a finite full-composition camera zoom.")
		return
	var captures: Array[Dictionary] = []
	var world_center := world_size * 0.5
	if not await _capture_frame(
		"full_composition.png",
		"full_composition",
		world_center,
		full_zoom,
		captures,
	):
		return
	var tower_capture_rect := Rect2(
		TOWER_ORIGIN - TOWER_CAPTURE_MARGIN,
		TOWER_SIZE + TOWER_CAPTURE_MARGIN * 2.0,
	)
	var tower_zoom := minf(
		float(CAPTURE_RESOLUTION.x) / tower_capture_rect.size.x,
		float(CAPTURE_RESOLUTION.y) / tower_capture_rect.size.y,
	)
	if not await _capture_frame(
		TOWER_CAPTURE_FILE,
		"tower_structure",
		tower_capture_rect.get_center(),
		tower_zoom,
		captures,
	):
		return
	var tower_capture: Dictionary = captures[captures.size() - 1]
	tower_capture["structure_id"] = TOWER_STRUCTURE_ID
	tower_capture["target_world_rect"] = [
		TOWER_ORIGIN.x,
		TOWER_ORIGIN.y,
		TOWER_SIZE.x,
		TOWER_SIZE.y,
	]
	tower_capture["requested_margin"] = [TOWER_CAPTURE_MARGIN.x, TOWER_CAPTURE_MARGIN.y]
	for tower_detail in [
		[TOWER_ENTRY_CAPTURE_FILE, "tower_entry", TOWER_ENTRY_WORLD_POSITION],
		[TOWER_A_CAPTURE_FILE, "tower_a", TOWER_A_WORLD_POSITION],
		[TOWER_B_CAPTURE_FILE, "tower_b", TOWER_B_WORLD_POSITION],
		[TOWER_C_CAPTURE_FILE, "tower_c", TOWER_C_WORLD_POSITION],
		[TOWER_D_CAPTURE_FILE, "tower_d", TOWER_D_WORLD_POSITION],
		[TOWER_SHAFT_CAPTURE_FILE, "tower_shaft", TOWER_SHAFT_WORLD_POSITION],
		[TOWER_BASEMENT_CAPTURE_FILE, "tower_basement", TOWER_BASEMENT_WORLD_POSITION],
	]:
		if not await _capture_frame(
			str(tower_detail[0]),
			str(tower_detail[1]),
			tower_detail[2] as Vector2,
			GAMEPLAY_ZOOM,
			captures,
		):
			return
		var detail_capture: Dictionary = captures[captures.size() - 1]
		detail_capture["structure_id"] = TOWER_STRUCTURE_ID

	var gameplay_half_extent := Vector2(CAPTURE_RESOLUTION) / (2.0 * GAMEPLAY_ZOOM)
	var left_center_x := minf(gameplay_half_extent.x, world_center.x)
	var right_center_x := maxf(left_center_x, world_size.x - gameplay_half_extent.x)
	var ground_baseline_y := world_size.y * 0.5
	var gameplay_center_y := ground_baseline_y - gameplay_half_extent.y
	gameplay_center_y += GROUND_CONTEXT_SCREEN_PIXELS / GAMEPLAY_ZOOM
	gameplay_center_y = clampf(
		gameplay_center_y,
		minf(gameplay_half_extent.y, world_center.y),
		maxf(world_center.y, world_size.y - gameplay_half_extent.y),
	)
	for frame_index in range(GAMEPLAY_FRAME_COUNT):
		var progress := float(frame_index) / float(GAMEPLAY_FRAME_COUNT - 1)
		var camera_position := Vector2(
			lerpf(left_center_x, right_center_x, progress),
			gameplay_center_y,
		)
		if not await _capture_frame(
			"gameplay_%02d.png" % (frame_index + 1),
			"gameplay",
			camera_position,
			GAMEPLAY_ZOOM,
			captures,
		):
			return

	if not _save_capture_manifest(world_size, captures):
		return
	print(
		"Underwater map proxy capture saved: %s"
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


func _validate_map_instance(map_instance: Node2D) -> bool:
	if map_instance.scene_file_path != MAP_SCENE_PATH:
		_fail(
			"Instantiated scene path is %s instead of %s."
			% [map_instance.scene_file_path, MAP_SCENE_PATH]
		)
		return false
	if map_instance.get_node_or_null("VisualLayers") == null:
		_fail("The generated map scene has no VisualLayers root.")
		return false
	var tower_root := map_instance.get_node_or_null("StructureRoots/%s" % TOWER_STRUCTURE_ID) as Node2D
	if tower_root == null:
		_fail("The generated map scene has no StructureRoots/%s." % TOWER_STRUCTURE_ID)
		return false
	if tower_root.position != TOWER_ORIGIN or tower_root.scale != Vector2.ONE:
		_fail("The tower capture target does not match the approved origin/identity scale.")
		return false
	if tower_root.get_meta("size", Vector2.ZERO) != TOWER_SIZE:
		_fail("The tower capture target does not match the approved 2240 x 3680 rect.")
		return false
	if not map_instance.has_meta("world_size"):
		_fail("The generated map scene has no world_size metadata.")
		return false
	var world_size_value = map_instance.get_meta("world_size")
	if not world_size_value is Vector2:
		_fail("The generated map scene world_size metadata must be Vector2.")
		return false
	var world_size: Vector2 = world_size_value
	if (
		not is_finite(world_size.x)
		or not is_finite(world_size.y)
		or world_size.x <= 0.0
		or world_size.y <= 0.0
	):
		_fail("The generated map scene world_size must be finite and positive.")
		return false
	return true


func _prepare_output_directory() -> bool:
	var output_absolute := ProjectSettings.globalize_path(OUTPUT_ROOT)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_absolute)
	if directory_error != OK:
		_fail(
			"Could not create isolated capture directory %s (error %d)."
			% [OUTPUT_ROOT, directory_error]
		)
		return false
	var output_files := [
		"full_composition.png",
		TOWER_CAPTURE_FILE,
		TOWER_ENTRY_CAPTURE_FILE,
		TOWER_A_CAPTURE_FILE,
		TOWER_B_CAPTURE_FILE,
		TOWER_C_CAPTURE_FILE,
		TOWER_D_CAPTURE_FILE,
		TOWER_SHAFT_CAPTURE_FILE,
		TOWER_BASEMENT_CAPTURE_FILE,
		"capture_manifest.json",
	]
	for frame_index in range(GAMEPLAY_FRAME_COUNT):
		output_files.append("gameplay_%02d.png" % (frame_index + 1))
	for file_name in output_files:
		var absolute_path := output_absolute.path_join(str(file_name))
		if FileAccess.file_exists(absolute_path):
			var remove_error := DirAccess.remove_absolute(absolute_path)
			if remove_error != OK:
				_fail(
					"Could not remove stale capture %s (error %d)."
					% [str(file_name), remove_error]
				)
				return false
	return true


func _capture_frame(
	file_name: String,
	kind: String,
	camera_position: Vector2,
	camera_zoom: float,
	captures: Array[Dictionary],
) -> bool:
	if not is_finite(camera_zoom) or camera_zoom <= 0.0:
		_fail("Capture %s requested an invalid camera zoom." % file_name)
		return false
	_camera.position = camera_position
	_camera.zoom = Vector2.ONE * camera_zoom
	_camera.force_update_scroll()
	for _frame in range(RENDER_SETTLE_FRAMES):
		await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Rendered viewport is unavailable for %s." % file_name)
		return false
	if image.get_size() != CAPTURE_RESOLUTION:
		_fail(
			"Capture %s has size %s instead of %s."
			% [file_name, str(image.get_size()), str(CAPTURE_RESOLUTION)]
		)
		return false
	if not _image_has_multiple_sampled_colors(image):
		_fail("Capture %s is a uniform image; the map did not render visibly." % file_name)
		return false
	var output_path := OUTPUT_ROOT.path_join(file_name)
	var save_error := image.save_png(ProjectSettings.globalize_path(output_path))
	if save_error != OK:
		_fail("Could not save %s (error %d)." % [output_path, save_error])
		return false

	var visible_size := Vector2(CAPTURE_RESOLUTION) / camera_zoom
	captures.append({
		"file": file_name,
		"kind": kind,
		"camera_position": [camera_position.x, camera_position.y],
		"camera_zoom": [camera_zoom, camera_zoom],
		"visible_world_rect": [
			camera_position.x - visible_size.x * 0.5,
			camera_position.y - visible_size.y * 0.5,
			visible_size.x,
			visible_size.y,
		],
	})
	return true


func _image_has_multiple_sampled_colors(image: Image) -> bool:
	var reference := image.get_pixel(0, 0)
	for sample_y in range(9):
		var y := roundi(float(sample_y) * float(CAPTURE_RESOLUTION.y - 1) / 8.0)
		for sample_x in range(17):
			var x := roundi(float(sample_x) * float(CAPTURE_RESOLUTION.x - 1) / 16.0)
			if not image.get_pixel(x, y).is_equal_approx(reference):
				return true
	return false


func _save_capture_manifest(world_size: Vector2, captures: Array[Dictionary]) -> bool:
	var report := {
		"scene_path": MAP_SCENE_PATH,
		"scene_file_path": _map.scene_file_path,
		"manifest_path": str(_map.get_meta("manifest_path", "")),
		"manifest_sha256": str(_map.get_meta("manifest_sha256", "")),
		"revision_id": str(_map.get_meta("revision_id", "")),
		"topology_revision": str(_map.get_meta("topology_revision", "")),
		"presentation_revision": str(_map.get_meta("presentation_revision", "")),
		"resolution": [CAPTURE_RESOLUTION.x, CAPTURE_RESOLUTION.y],
		"world_size": [world_size.x, world_size.y],
		"gameplay_zoom": GAMEPLAY_ZOOM,
		"captures": captures,
	}
	var report_path := OUTPUT_ROOT.path_join("capture_manifest.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		_fail(
			"Could not open %s for writing (error %d)."
			% [report_path, FileAccess.get_open_error()]
		)
		return false
	report_file.store_string(JSON.stringify(report, "  "))
	var write_error := report_file.get_error()
	report_file.close()
	if write_error != OK:
		_fail("Could not save %s (error %d)." % [report_path, write_error])
		return false
	return true


func _cleanup_scene() -> void:
	if _capture_host != null and is_instance_valid(_capture_host):
		_capture_host.free()
	elif _map != null and is_instance_valid(_map):
		_map.free()
	_capture_host = null
	_map = null
	_camera = null


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("Underwater map proxy capture failed: " + message)
	_cleanup_scene()
	quit(1)
