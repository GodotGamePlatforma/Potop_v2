extends SceneTree

const MAP_SCENE_PATH := "res://underwater_map_workbench/UnderwaterMap.tscn"
const MAP_MANIFEST_PATH := "res://underwater_map_workbench/map_manifest.json"
const OUTPUT_ROOT := "user://test_tower_prototype_01_proxy_capture"
const CAPTURE_RESOLUTION := Vector2i(1280, 720)
const GAMEPLAY_ZOOM := 1.2
# Single authority for every generated output. Both cleanup and capture generation
# resolve filenames through this collection, so adding a frame cannot leave a
# stale, undeclared PNG behind.
const CAPTURE_FILES := {
	&"tower_structure": "tower_prototype_01.png",
	&"tower_entry": "tower_prototype_01_entry.png",
	&"tower_a": "tower_prototype_01_a.png",
	&"tower_b": "tower_prototype_01_b.png",
	&"tower_c": "tower_prototype_01_c.png",
	&"tower_d": "tower_prototype_01_d.png",
	&"tower_shaft": "tower_prototype_01_shaft.png",
	&"tower_basement": "tower_prototype_01_basement.png",
	&"runtime_initial": "tower_prototype_01_runtime_initial.png",
	&"runtime_door_closed": "tower_prototype_01_runtime_door_closed.png",
	&"runtime_door_mid": "tower_prototype_01_runtime_door_mid.png",
	&"runtime_door_open": "tower_prototype_01_runtime_door_open.png",
	&"runtime_b_latched": "tower_prototype_01_runtime_b_latched.png",
	&"runtime_trolley_moving": "tower_prototype_01_runtime_trolley_moving.png",
	&"runtime_trolley_blocked": "tower_prototype_01_runtime_trolley_blocked.png",
	&"runtime_trolley_returning": "tower_prototype_01_runtime_trolley_returning.png",
	&"runtime_trolley_contact": "tower_prototype_01_runtime_trolley_contact.png",
	&"runtime_trolley_latched": "tower_prototype_01_runtime_trolley_latched.png",
	&"runtime_d_ready": "tower_prototype_01_runtime_d_ready.png",
	&"runtime_d_fault": "tower_prototype_01_runtime_d_fault.png",
	&"runtime_d_reset": "tower_prototype_01_runtime_d_reset.png",
	&"runtime_d_v1": "tower_prototype_01_runtime_d_v1.png",
	&"runtime_d_v2": "tower_prototype_01_runtime_d_v2.png",
	&"runtime_d_v3": "tower_prototype_01_runtime_d_v3.png",
	&"runtime_archive_open": "tower_prototype_01_runtime_archive_open.png",
	&"runtime_complete": "tower_prototype_01_runtime_complete.png",
	&"power_start": "tower_prototype_01_power_start.png",
	&"power_red_active": "tower_prototype_01_power_red_active.png",
	&"power_blue_locked": "tower_prototype_01_power_blue_locked.png",
	&"power_blue_active": "tower_prototype_01_power_blue_active.png",
	&"power_yellow_active": "tower_prototype_01_power_yellow_active.png",
	&"power_fault_all_branches_open": "tower_prototype_01_power_fault_all_branches_open.png",
	&"power_fault_right_branch_unterminated": "tower_prototype_01_power_fault_right_branch_unterminated.png",
	&"power_fault_middle_right_overload": "tower_prototype_01_power_fault_middle_right_overload.png",
	&"power_fault_split_outer_feed": "tower_prototype_01_power_fault_split_outer_feed.png",
	&"power_fault_left_middle_crossfeed": "tower_prototype_01_power_fault_left_middle_crossfeed.png",
	&"manifest": "capture_manifest.json",
}
const TOWER_STRUCTURE_ID := "tower_prototype_01"
const TOWER_PACKAGE_MANIFEST_PATH := "res://underwater_map_workbench/structures/tower_prototype_01/structure_manifest.json"
const TOWER_PACKAGE_SCENE_PATH := "res://underwater_map_workbench/structures/tower_prototype_01/generated/structure.tscn"
const TOWER_STRUCTURE_TEXTURE_PATH := "res://underwater_map_workbench/structures/tower_prototype_01/assets/visual/tower_structure.png"
const TOWER_INTERIOR_TEXTURE_PATH := "res://underwater_map_workbench/structures/tower_prototype_01/assets/visual/tower_interior.png"
const TOWER_CAPTURE_MARGIN := Vector2(240.0, 240.0)
const VIEWPORT_READY_FRAME_LIMIT := 60
const RENDER_SETTLE_FRAMES := 4
const DOOR_MATERIAL_DISTANCE_THRESHOLD := 0.06
const DOOR_CLOSED_COVER_MIN := 0.45
const DOOR_MID_COVER_MIN := 0.10
const DOOR_OPEN_COVER_MAX := 0.08
const DOOR_COVER_STEP_MIN := 0.10
const DOOR_ADJACENT_MASK_DIFFERENCE_MIN := 0.10
const DOOR_ENDPOINT_MASK_DIFFERENCE_MIN := 0.30

var _capture_host: Node2D
var _map: Node2D
var _tower_root: Node2D
var _camera: Camera2D
var _package_manifest: Dictionary = {}
var _background_map_package_sha256 := ""
var _tower_origin := Vector2.ZERO
var _tower_size := Vector2.ZERO
var _tower_detail_positions: Dictionary = {}
var _last_capture_image: Image
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
	var map_manifest := _load_json_dictionary(MAP_MANIFEST_PATH, "map manifest")
	_package_manifest = _load_json_dictionary(TOWER_PACKAGE_MANIFEST_PATH, "local tower package manifest")
	if map_manifest.is_empty() or _package_manifest.is_empty():
		return
	if not _configure_tower_capture_targets(map_manifest, _package_manifest):
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
	if not _mount_local_tower_over_background(_map) or not _validate_map_instance(_map):
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
	var captures: Array[Dictionary] = []
	var tower_capture_rect := Rect2(
		_tower_origin - TOWER_CAPTURE_MARGIN,
		_tower_size + TOWER_CAPTURE_MARGIN * 2.0,
	)
	var tower_zoom := minf(
		float(CAPTURE_RESOLUTION.x) / tower_capture_rect.size.x,
		float(CAPTURE_RESOLUTION.y) / tower_capture_rect.size.y,
	)
	if not await _capture_frame(
		_capture_file(&"tower_structure"),
		"tower_structure",
		tower_capture_rect.get_center(),
		tower_zoom,
		captures,
	):
		return
	var tower_capture: Dictionary = captures[captures.size() - 1]
	tower_capture["structure_id"] = TOWER_STRUCTURE_ID
	tower_capture["target_world_rect"] = [
		_tower_origin.x,
		_tower_origin.y,
		_tower_size.x,
		_tower_size.y,
	]
	tower_capture["requested_margin"] = [TOWER_CAPTURE_MARGIN.x, TOWER_CAPTURE_MARGIN.y]
	for tower_detail in [
		[&"tower_entry", "tower_entry"],
		[&"tower_a", "tower_a"],
		[&"tower_b", "tower_b"],
		[&"tower_c", "tower_c"],
		[&"tower_d", "tower_d"],
		[&"tower_shaft", "tower_shaft"],
		[&"tower_basement", "tower_basement"],
	]:
		if not await _capture_frame(
			_capture_file(StringName(tower_detail[0])),
			str(tower_detail[1]),
			_tower_detail_position(str(tower_detail[1])),
			GAMEPLAY_ZOOM,
			captures,
		):
			return
		var detail_capture: Dictionary = captures[captures.size() - 1]
		detail_capture["structure_id"] = TOWER_STRUCTURE_ID

	if not await _capture_runtime_tower_states(tower_capture_rect, captures):
		return

	if not _save_capture_manifest(world_size, captures):
		return
	print(
		"Tower prototype capture saved: %s"
		% ProjectSettings.globalize_path(OUTPUT_ROOT)
	)
	_cleanup_scene()
	quit(0)


func _configure_tower_capture_targets(map_manifest: Dictionary, package_manifest: Dictionary) -> bool:
	var structures_value = map_manifest.get("structures", null)
	if not structures_value is Dictionary:
		_fail("The read-only map manifest has no structures record for capture placement.")
		return false
	var instances_value = (structures_value as Dictionary).get("instances", null)
	if not instances_value is Array:
		_fail("The active manifest has no structures.instances array for capture framing.")
		return false
	var tower_instance: Dictionary = {}
	for instance_value in instances_value as Array:
		if instance_value is Dictionary and str((instance_value as Dictionary).get("id", "")) == TOWER_STRUCTURE_ID:
			tower_instance = instance_value as Dictionary
			break
	if tower_instance.is_empty():
		_fail("The read-only map manifest has no structure instance %s." % TOWER_STRUCTURE_ID)
		return false
	_tower_origin = _manifest_vector2(tower_instance.get("origin", null))
	_tower_size = _manifest_vector2(package_manifest.get("size", null))
	if not _tower_origin.is_finite() or not _tower_size.is_finite() or _tower_size.x <= 0.0 or _tower_size.y <= 0.0:
		_fail("Map placement and local package must publish finite tower origin and size.")
		return false
	if not bool(tower_instance.get("enabled", false)):
		_fail("The read-only map placement for %s must remain enabled." % TOWER_STRUCTURE_ID)
		return false
	var package_pin := tower_instance.get("package", {}) as Dictionary
	if str(package_pin.get("path", "")) != "structures/tower_prototype_01/structure_manifest.json":
		_fail("The map placement points at an unexpected tower package path.")
		return false
	_background_map_package_sha256 = str(package_pin.get("sha256", ""))
	if _background_map_package_sha256.is_empty():
		_fail("The read-only map placement has no provenance pin for W01.")
		return false

	var socket_rects := {}
	var sockets_value = package_manifest.get("sockets", null)
	if not sockets_value is Array:
		_fail("The local tower package has no socket array.")
		return false
	for socket_value in sockets_value as Array:
		if not socket_value is Dictionary:
			continue
		var socket := socket_value as Dictionary
		var local_rect := _manifest_rect2(socket.get("local_rect", null))
		if local_rect.position.is_finite() and local_rect.size.is_finite() and local_rect.size.x > 0.0 and local_rect.size.y > 0.0:
			socket_rects[str(socket.get("id", ""))] = local_rect

	var detail_socket_ids := {
		"tower_entry": "entry_floor_12_broken_window",
		"tower_a": "control_a_distributor",
		"tower_b": "control_b_red_relay",
		"tower_c": "control_c_blue_lock",
		"tower_d": "control_d_valve_v2",
		"tower_shaft": "elevator_upper_travel",
		"tower_red_door": "gate_red_east",
	}
	_tower_detail_positions.clear()
	for detail_id in detail_socket_ids:
		var socket_id := str(detail_socket_ids[detail_id])
		if not socket_rects.has(socket_id):
			_fail("The tower capture target is missing manifest socket %s." % socket_id)
			return false
		var socket_rect: Rect2 = socket_rects[socket_id]
		_tower_detail_positions[detail_id] = _tower_origin + socket_rect.get_center()

	var basement_control_id := "control_basement_hatch"
	var basement_hatch_id := "hatch_basement"
	if not socket_rects.has(basement_control_id) or not socket_rects.has(basement_hatch_id):
		_fail("The tower capture target is missing basement framing sockets.")
		return false
	var basement_control: Rect2 = socket_rects[basement_control_id]
	var basement_hatch: Rect2 = socket_rects[basement_hatch_id]
	_tower_detail_positions["tower_basement"] = _tower_origin + Vector2(
		basement_control.get_center().x,
		basement_hatch.get_center().y + basement_hatch.size.y,
	)
	return true


func _tower_detail_position(detail_id: String) -> Vector2:
	var fallback := _tower_origin + _tower_size * 0.5
	return Vector2(_tower_detail_positions.get(detail_id, fallback))


func _manifest_vector2(value) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2(NAN, NAN)
	var values := value as Array
	if typeof(values[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(values[1]) not in [TYPE_INT, TYPE_FLOAT]:
		return Vector2(NAN, NAN)
	return Vector2(float(values[0]), float(values[1]))


func _manifest_rect2(value) -> Rect2:
	if not value is Array or (value as Array).size() != 4:
		return Rect2(Vector2(NAN, NAN), Vector2(NAN, NAN))
	var values := value as Array
	for component in values:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT]:
			return Rect2(Vector2(NAN, NAN), Vector2(NAN, NAN))
	return Rect2(
		Vector2(float(values[0]), float(values[1])),
		Vector2(float(values[2]), float(values[3])),
	)


func _json_vector(value: Variant) -> Array:
	if value is Vector2:
		var vector := value as Vector2
		return [vector.x, vector.y]
	return []


func _json_rect(value: Variant) -> Array:
	if value is Rect2:
		var rect := value as Rect2
		return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	return []


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


func _load_json_dictionary(path: String, label: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Could not open %s at %s (error %d)." % [label, path, FileAccess.get_open_error()])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_fail("%s must be a JSON dictionary: %s." % [label, path])
		return {}
	return parsed as Dictionary


func _mount_local_tower_over_background(map_instance: Node2D) -> bool:
	var structure_roots := map_instance.get_node_or_null("StructureRoots") as Node2D
	if structure_roots == null:
		_fail("The generated map background has no StructureRoots root.")
		return false
	var background_tower := structure_roots.get_node_or_null(TOWER_STRUCTURE_ID) as Node2D
	if background_tower == null:
		_fail("The generated map background has no placement node for %s." % TOWER_STRUCTURE_ID)
		return false
	if not background_tower.position.is_equal_approx(_tower_origin):
		_fail("The generated map background placement disagrees with read-only map_manifest origin.")
		return false
	var child_index := background_tower.get_index()
	var inherited_z_index := background_tower.z_index
	background_tower.free()
	var package_resource := ResourceLoader.load(
		TOWER_PACKAGE_SCENE_PATH,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE,
	)
	if not package_resource is PackedScene:
		_fail("Could not load the sealed local package scene: %s." % TOWER_PACKAGE_SCENE_PATH)
		return false
	var package_instance := (package_resource as PackedScene).instantiate()
	if not package_instance is Node2D:
		if package_instance != null:
			package_instance.free()
		_fail("The sealed local package scene root must be Node2D.")
		return false
	_tower_root = package_instance as Node2D
	_tower_root.name = TOWER_STRUCTURE_ID
	_tower_root.position = _tower_origin
	_tower_root.scale = Vector2.ONE
	_tower_root.z_index = inherited_z_index
	_tower_root.visible = true
	structure_roots.add_child(_tower_root)
	structure_roots.move_child(_tower_root, child_index)
	return true


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
	if _tower_root == null or _tower_root.scene_file_path != TOWER_PACKAGE_SCENE_PATH:
		_fail("The visible W01 root is not an instance of the sealed local package scene.")
		return false
	if _tower_root.position != _tower_origin or _tower_root.scale != Vector2.ONE:
		_fail("The local package root does not match map placement and identity scale.")
		return false
	if str(_tower_root.get_meta("structure_id", "")) != TOWER_STRUCTURE_ID or _tower_root.get_meta("size", Vector2.ZERO) != _tower_size:
		_fail("The local package root does not publish the expected structure id and package size.")
		return false
	var local_package_sha256 := FileAccess.get_sha256(TOWER_PACKAGE_MANIFEST_PATH)
	if local_package_sha256.is_empty() or str(_tower_root.get_meta("package_manifest_sha256", "")) != local_package_sha256:
		_fail("The local generated scene is not built from the currently sealed package manifest.")
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
	for file_name_value: Variant in CAPTURE_FILES.values():
		var file_name := str(file_name_value)
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


func _capture_runtime_tower_states(
	tower_capture_rect: Rect2,
	captures: Array[Dictionary],
) -> bool:
	if _tower_root == null:
		_fail("Runtime capture has no mounted local package root.")
		return false
	var dynamic_bodies := _tower_root.get_node_or_null("DynamicBodies") as Node2D
	var interactives := _tower_root.get_node_or_null("Interactives") as Node2D
	if dynamic_bodies == null or interactives == null:
		_fail("The local package scene must publish DynamicBodies and Interactives roots.")
		return false
	var controller_script_path := str(_tower_root.get_meta("controller_script", ""))
	var controller_script := ResourceLoader.load(
		controller_script_path,
		"Script",
		ResourceLoader.CACHE_MODE_IGNORE,
	) as Script
	if controller_script == null:
		_fail("Could not load the local package controller script: %s." % controller_script_path)
		return false
	var controller := controller_script.new() as Node
	if controller == null or not controller.has_method("configure"):
		if controller != null:
			controller.free()
		_fail("The local package controller script does not expose configure().")
		return false
	controller.name = "%sRuntime" % TOWER_STRUCTURE_ID.to_pascal_case()
	dynamic_bodies.add_child(controller)
	var configure_value: Variant = controller.call(
		"configure",
		_effective_local_structure_record(controller_script_path),
		interactives,
	)
	if not configure_value is PackedStringArray or not (configure_value as PackedStringArray).is_empty():
		_fail("Could not mount the local package runtime: %s." % configure_value)
		return false
	for _frame in range(RENDER_SETTLE_FRAMES):
		await process_frame
	if not controller.has_method("activate_control"):
		_fail("The mounted local package controller has no runtime control API.")
		return false
	var tower_zoom := minf(
		float(CAPTURE_RESOLUTION.x) / tower_capture_rect.size.x,
		float(CAPTURE_RESOLUTION.y) / tower_capture_rect.size.y,
	)
	if not await _capture_frame(
		_capture_file(&"runtime_initial"),
		"tower_runtime_initial",
		tower_capture_rect.get_center(),
		tower_zoom,
		captures,
	):
		return false
	var lever_ids := _runtime_power_lever_ids(controller)
	if lever_ids.size() != 3:
		return false
	var start_positions := _ordered_power_positions(
		lever_ids,
		PackedStringArray(["up", "up", "up"]),
	)
	var red_positions := _ordered_power_positions(
		lever_ids,
		PackedStringArray(["down", "down", "down"]),
	)
	var blue_positions := _ordered_power_positions(
		lever_ids,
		PackedStringArray(["up", "down", "up"]),
	)
	var yellow_positions := _ordered_power_positions(
		lever_ids,
		PackedStringArray(["down", "up", "up"]),
	)
	var fault_positions := _ordered_power_positions(
		lever_ids,
		PackedStringArray(["down", "up", "down"]),
	)
	if not await _capture_runtime_power_state(
		controller,
		_capture_file(&"power_start"),
		"tower_runtime_power_start",
		start_positions,
		"",
		"",
		"ready",
		{"red": "ready", "blue": "locked", "yellow": "locked"},
		captures,
	):
		return false
	if not await _capture_all_power_diagnostics(controller, lever_ids, captures):
		return false
	var red_door := _runtime_barrier_body(controller, "gate_red_east")
	if red_door == null:
		return false
	var red_door_closed_position := red_door.position
	var red_door_open_offset := _runtime_barrier_open_offset("red_route", "gate_red_east")
	if not red_door_open_offset.is_finite() or red_door_open_offset.is_zero_approx():
		_fail("RED door capture could not resolve a finite, non-zero manifest open offset.")
		return false
	var red_door_open_position := red_door_closed_position + red_door_open_offset
	var door_closed_capture_index := captures.size()
	if not await _capture_runtime_door_state(
		controller,
		red_door,
		_capture_file(&"runtime_door_closed"),
		"tower_runtime_door_closed",
		"closed",
		true,
		false,
		true,
		0.0,
		0.02,
		red_door_closed_position,
		red_door_open_position,
		captures,
	):
		return false
	var red_door_closed_image := _last_capture_image.duplicate() as Image
	var red_door_closed_background := await _capture_runtime_door_background(red_door)
	if red_door_closed_background == null:
		return false
	for lever_id: String in lever_ids:
		if not _activate_runtime_power_lever(controller, lever_id):
			return false
	controller.set_physics_process(false)
	var red_power_capture_ok := await _capture_runtime_power_state(
		controller,
		_capture_file(&"power_red_active"),
		"tower_runtime_power_red_active",
		red_positions,
		"red",
		"red",
		"active",
		{"red": "active", "blue": "locked", "yellow": "locked"},
		captures,
	)
	controller.set_physics_process(true)
	if not red_power_capture_ok:
		return false
	if not await _await_runtime_barrier_travel_window(
		controller,
		red_door,
		red_door_closed_position,
		red_door_open_position,
		0.40,
		0.60,
	):
		return false
	controller.set_physics_process(false)
	var red_door_mid_position := red_door.position
	var door_mid_capture_index := captures.size()
	var door_mid_capture_ok := await _capture_runtime_door_state(
		controller,
		red_door,
		_capture_file(&"runtime_door_mid"),
		"tower_runtime_door_mid",
		"opening",
		false,
		true,
		false,
		0.40,
		0.60,
		red_door_closed_position,
		red_door_open_position,
		captures,
	)
	var red_door_mid_image: Image = null
	var red_door_mid_background: Image = null
	if door_mid_capture_ok:
		red_door_mid_image = _last_capture_image.duplicate() as Image
		red_door_mid_background = await _capture_runtime_door_background(red_door)
	controller.set_physics_process(true)
	if not door_mid_capture_ok or red_door_mid_background == null:
		return false
	if not await _await_runtime_barrier_group_settle(controller, "red_route"):
		_fail("RED door did not reach its open target before the open-state capture.")
		return false
	var door_open_capture_index := captures.size()
	if not await _capture_runtime_door_state(
		controller,
		red_door,
		_capture_file(&"runtime_door_open"),
		"tower_runtime_door_open",
		"open",
		true,
		true,
		true,
		0.98,
		1.02,
		red_door_closed_position,
		red_door_open_position,
		captures,
	):
		return false
	var red_door_open_image := _last_capture_image.duplicate() as Image
	var red_door_open_background := await _capture_runtime_door_background(red_door)
	if red_door_open_background == null:
		return false
	var door_triptych_proof := _runtime_door_triptych_roi_proof(
		red_door,
		red_door_closed_position,
		red_door_mid_position,
		red_door_open_position,
		red_door_closed_image,
		red_door_closed_background,
		red_door_mid_image,
		red_door_mid_background,
		red_door_open_image,
		red_door_open_background,
	)
	if door_triptych_proof.is_empty():
		return false
	for capture_index: int in [door_closed_capture_index, door_mid_capture_index, door_open_capture_index]:
		var door_capture: Dictionary = captures[capture_index]
		door_capture["dynamic_door_triptych_roi_proof"] = door_triptych_proof.duplicate(true)
	for lever_index: int in [0, 2]:
		if not _activate_runtime_power_lever(controller, lever_ids[lever_index]):
			return false
	if not await _capture_runtime_power_state(
		controller,
		_capture_file(&"power_blue_locked"),
		"tower_runtime_power_blue_locked_before_b",
		blue_positions,
		"blue",
		"",
		"locked",
		{"red": "ready", "blue": "locked", "yellow": "locked"},
		captures,
	):
		return false
	for lever_index: int in [0, 2]:
		if not _activate_runtime_power_lever(controller, lever_ids[lever_index]):
			return false
	if _validated_runtime_power_state(
		controller,
		"RED restored before B",
		red_positions,
		"red",
		"red",
		"active",
		{"red": "active", "blue": "locked", "yellow": "locked"},
	).is_empty():
		return false
	if not _activate_runtime_control(controller, "b_red_relay"):
		return false
	if not await _capture_runtime_detail(
		controller,
		_capture_file(&"runtime_b_latched"),
		"tower_runtime_b_latched",
		"tower_b",
		captures,
	):
		return false
	var trolley_blocker := _spawn_runtime_trolley_blocker(controller, _tower_root)
	if trolley_blocker == null:
		return false
	await physics_frame
	await physics_frame
	if bool(controller.call("elevator_safety_clear")):
		var blocker_snapshot: Variant = controller.call("state_snapshot")
		_fail(
			"Runtime trolley blocker did not occupy the real safety envelope: blocker=%s snapshot=%s."
			% [trolley_blocker.global_position, blocker_snapshot]
		)
		return false
	for lever_index: int in [0, 2]:
		if not _activate_runtime_power_lever(controller, lever_ids[lever_index]):
			return false
	if not await _capture_runtime_power_state(
		controller,
		_capture_file(&"power_blue_active"),
		"tower_runtime_power_blue_active_after_b",
		blue_positions,
		"blue",
		"blue",
		"active",
		{"red": "latched", "blue": "active", "yellow": "locked"},
		captures,
	):
		return false
	for _frame_index: int in range(5):
		await physics_frame
	if not await _capture_runtime_trolley_state(
		controller,
		_capture_file(&"runtime_trolley_blocked"),
		"tower_runtime_trolley_blocked",
		"blocked_by_diver",
		captures,
	):
		return false
	trolley_blocker.queue_free()
	await physics_frame
	await physics_frame
	if not await _await_runtime_elevator_progress(controller, 880.0):
		_fail("Runtime elevator did not reach the requested mid-travel capture position.")
		return false
	if not await _capture_runtime_trolley_state(
		controller,
		_capture_file(&"runtime_trolley_moving"),
		"tower_runtime_trolley_moving",
		"moving_down",
		captures,
	):
		return false
	if not _activate_runtime_power_lever(controller, lever_ids[2]):
		return false
	for _frame_index: int in range(5):
		await physics_frame
	if not await _capture_runtime_trolley_state(
		controller,
		_capture_file(&"runtime_trolley_returning"),
		"tower_runtime_trolley_returning",
		"returning",
		captures,
	):
		return false
	if not await _await_runtime_elevator_stop(controller, "floor_12"):
		_fail("Runtime trolley did not return to floor_12 before the second descent.")
		return false
	if not _activate_runtime_power_lever(controller, lever_ids[2]):
		return false
	if not await _await_runtime_elevator_stop(controller, "floor_7"):
		_fail("Runtime elevator did not reach floor_7 before the completed-state capture.")
		return false
	if not await _capture_runtime_trolley_state(
		controller,
		_capture_file(&"runtime_trolley_contact"),
		"tower_runtime_trolley_contact",
		"contact_closed",
		captures,
	):
		return false
	if not _activate_runtime_control(controller, "c_blue_lock"):
		return false
	for lever_index: int in [0, 1]:
		if not _activate_runtime_power_lever(controller, lever_ids[lever_index]):
			return false
	if not await _capture_runtime_power_state(
		controller,
		_capture_file(&"power_yellow_active"),
		"tower_runtime_power_yellow_active_after_c",
		yellow_positions,
		"yellow",
		"yellow",
		"active",
		{"red": "latched", "blue": "latched", "yellow": "active"},
		captures,
	):
		return false
	if not await _capture_runtime_trolley_state(
		controller,
		_capture_file(&"runtime_trolley_latched"),
		"tower_runtime_trolley_latched",
		"latched_floor_7",
		captures,
	):
		return false
	if not _activate_runtime_power_lever(controller, lever_ids[2]):
		return false
	if _validated_runtime_power_state(
		controller,
		"split_outer_feed after C",
		fault_positions,
		"",
		"",
		"fault",
		{"red": "latched", "blue": "latched", "yellow": "ready"},
		"split_outer_feed",
	).is_empty():
		return false
	if not _activate_runtime_power_lever(controller, lever_ids[2]):
		return false
	if _validated_runtime_power_state(
		controller,
		"YELLOW restored after fault capture",
		yellow_positions,
		"yellow",
		"yellow",
		"active",
		{"red": "latched", "blue": "latched", "yellow": "active"},
	).is_empty():
		return false
	if not await _capture_runtime_detail(
		controller,
		_capture_file(&"runtime_d_ready"),
		"tower_runtime_d_ready",
		"tower_d",
		captures,
	):
		return false
	if not _activate_runtime_control_expect_d_fault(controller, "d_valve_v2"):
		return false
	if not await _capture_runtime_detail(
		controller,
		_capture_file(&"runtime_d_fault"),
		"tower_runtime_d_fault",
		"tower_d",
		captures,
	):
		return false
	if not _activate_runtime_control(controller, "d_reset"):
		return false
	if not await _capture_runtime_detail(
		controller,
		_capture_file(&"runtime_d_reset"),
		"tower_runtime_d_reset",
		"tower_d",
		captures,
	):
		return false
	if not _activate_runtime_control(controller, "d_valve_v1"):
		return false
	if not await _capture_runtime_detail(
		controller,
		_capture_file(&"runtime_d_v1"),
		"tower_runtime_d_pressure",
		"tower_d",
		captures,
	):
		return false
	if not _activate_runtime_control(controller, "d_valve_v2"):
		return false
	if not await _capture_runtime_detail(
		controller,
		_capture_file(&"runtime_d_v2"),
		"tower_runtime_d_actuator",
		"tower_d",
		captures,
	):
		return false
	if not _activate_runtime_control(controller, "d_valve_v3"):
		return false
	if not await _capture_runtime_detail(
		controller,
		_capture_file(&"runtime_d_v3"),
		"tower_runtime_d_release",
		"tower_d",
		captures,
	):
		return false
	if not _activate_runtime_control(controller, "basement_hatch_control"):
		return false
	if not await _await_runtime_barriers_settle(controller):
		_fail("Archive capture requires every barrier, including hatch_basement, at its target.")
		return false
	if (
		not bool(controller.call("barrier_group_is_open", "hatch_basement"))
		or not bool(controller.call("barrier_group_reached_target", "hatch_basement"))
	):
		_fail("Archive capture requires hatch_basement logical open and physically reached_target.")
		return false
	if not await _capture_runtime_detail(
		controller,
		_capture_file(&"runtime_archive_open"),
		"tower_runtime_archive_open",
		"tower_basement",
		captures,
	):
		return false
	if not await _capture_frame(
		_capture_file(&"runtime_complete"),
		"tower_runtime_complete",
		tower_capture_rect.get_center(),
		tower_zoom,
		captures,
	):
		return false
	return true


func _effective_local_structure_record(controller_script_path: String) -> Dictionary:
	return {
		"id": TOWER_STRUCTURE_ID,
		"template_id": str((_package_manifest.get("template", {}) as Dictionary).get("id", "")),
		"origin": [_tower_origin.x, _tower_origin.y],
		"size": (_package_manifest.get("size", []) as Array).duplicate(true),
		"sockets": (_package_manifest.get("sockets", []) as Array).duplicate(true),
		"runtime": (_package_manifest.get("runtime", {}) as Dictionary).duplicate(true),
		"controller_script": controller_script_path,
		"structure_scene_path": TOWER_PACKAGE_SCENE_PATH,
	}


func _capture_all_power_diagnostics(
	controller: Node,
	lever_ids: PackedStringArray,
	captures: Array[Dictionary],
) -> bool:
	var diagnostic_cases := [
		{
			"file_id": &"power_fault_all_branches_open",
			"reason_id": "all_branches_open",
			"positions": PackedStringArray(["up", "up", "up"]),
		},
		{
			"file_id": &"power_fault_right_branch_unterminated",
			"reason_id": "right_branch_unterminated",
			"positions": PackedStringArray(["up", "up", "down"]),
		},
		{
			"file_id": &"power_fault_middle_right_overload",
			"reason_id": "middle_right_overload",
			"positions": PackedStringArray(["up", "down", "down"]),
		},
		{
			"file_id": &"power_fault_split_outer_feed",
			"reason_id": "split_outer_feed",
			"positions": PackedStringArray(["down", "up", "down"]),
		},
		{
			"file_id": &"power_fault_left_middle_crossfeed",
			"reason_id": "left_middle_crossfeed",
			"positions": PackedStringArray(["down", "down", "up"]),
		},
	]
	for case_value: Variant in diagnostic_cases:
		var diagnostic_case := case_value as Dictionary
		controller.call("reset_attempt")
		var positions: PackedStringArray = diagnostic_case["positions"]
		if positions == PackedStringArray(["up", "up", "up"]):
			# Neutral reset is intentionally ready. Re-entering U/U/U through a
			# physical lever toggle publishes the diagnostic for that wiring.
			if not _activate_runtime_power_lever(controller, lever_ids[0]):
				return false
			if not _activate_runtime_power_lever(controller, lever_ids[0]):
				return false
		elif not _set_runtime_power_pattern(controller, lever_ids, positions):
			return false
		var reason_id := str(diagnostic_case["reason_id"])
		if not await _capture_runtime_power_state(
			controller,
			_capture_file(StringName(diagnostic_case["file_id"])),
			"tower_runtime_power_fault_%s" % reason_id,
			_ordered_power_positions(lever_ids, positions),
			"",
			"",
			"fault",
			{"red": "ready", "blue": "locked", "yellow": "locked"},
			captures,
			reason_id,
		):
			return false
	controller.call("reset_attempt")
	return true


func _capture_runtime_power_state(
	controller: Node,
	file_name: String,
	kind: String,
	expected_lever_positions: Dictionary,
	expected_matched_circuit_id: String,
	expected_active_circuit_id: String,
	expected_power_status: String,
	expected_circuit_states: Dictionary,
	captures: Array[Dictionary],
	expected_diagnostic_id: String = "",
) -> bool:
	var power_state := _validated_runtime_power_state(
		controller,
		kind,
		expected_lever_positions,
		expected_matched_circuit_id,
		expected_active_circuit_id,
		expected_power_status,
		expected_circuit_states,
		expected_diagnostic_id,
	)
	if power_state.is_empty():
		return false
	if not await _capture_frame(
		file_name,
		kind,
		_tower_detail_position("tower_a"),
		GAMEPLAY_ZOOM,
		captures,
	):
		return false
	var capture: Dictionary = captures[captures.size() - 1]
	capture["structure_id"] = TOWER_STRUCTURE_ID
	capture["runtime_power_state"] = power_state
	return true


func _capture_runtime_detail(
	controller: Node,
	file_name: String,
	capture_id: String,
	detail_id: String,
	captures: Array[Dictionary],
	camera_position_override: Variant = null,
) -> bool:
	var camera_position := _tower_detail_position(detail_id)
	if camera_position_override is Vector2:
		camera_position = camera_position_override as Vector2
	if not await _capture_frame(
		file_name,
		capture_id,
		camera_position,
		GAMEPLAY_ZOOM,
		captures,
	):
		return false
	var snapshot: Dictionary = controller.call("state_snapshot") as Dictionary
	var capture: Dictionary = captures[captures.size() - 1]
	capture["structure_id"] = TOWER_STRUCTURE_ID
	capture["runtime_visual_state"] = {
		"power_status": str(snapshot.get("power_status", "")),
		"power_diagnostic_id": str(snapshot.get("power_diagnostic_id", "")),
		"red_latched": bool(snapshot.get("red_latched", false)),
		"blue_latched": bool(snapshot.get("blue_latched", false)),
		"trolley_contact_closed": bool(snapshot.get("trolley_contact_closed", false)),
		"trolley_visual_state": str(snapshot.get("trolley_visual_state", "")),
		"elevator_current_stop_id": str(snapshot.get("elevator_current_stop_id", "")),
		"elevator_target_stop_id": str(snapshot.get("elevator_target_stop_id", "")),
		"elevator_local_position": _json_vector(snapshot.get("elevator_local_position", null)),
		"elevator_safety_clear": bool(snapshot.get("elevator_safety_clear", false)),
		"barrier_groups": (snapshot.get("barrier_groups", {}) as Dictionary).duplicate(true),
		"d_progress": int(snapshot.get("d_progress", 0)),
		"d_requires_reset": bool(snapshot.get("d_requires_reset", false)),
		"d_complete": bool(snapshot.get("d_complete", false)),
		"basement_open": bool(snapshot.get("basement_open", false)),
		"attempt_complete": bool(snapshot.get("attempt_complete", false)),
	}
	return true


func _capture_runtime_door_state(
	controller: Node,
	door: AnimatableBody2D,
	file_name: String,
	capture_id: String,
	expected_visual_state: String,
	expected_reached_target: bool,
	expected_group_open: bool,
	expected_group_reached_target: bool,
	minimum_travel_fraction: float,
	maximum_travel_fraction: float,
	closed_position: Vector2,
	open_position: Vector2,
	captures: Array[Dictionary],
) -> bool:
	var state := _validated_runtime_door_state(
		controller,
		door,
		capture_id,
		expected_visual_state,
		expected_reached_target,
		expected_group_open,
		expected_group_reached_target,
		minimum_travel_fraction,
		maximum_travel_fraction,
		closed_position,
		open_position,
	)
	if state.is_empty():
		return false
	if not await _capture_runtime_detail(
		controller,
		file_name,
		capture_id,
		"tower_red_door",
		captures,
	):
		return false
	var capture: Dictionary = captures[captures.size() - 1]
	capture["dynamic_door_state"] = state
	return true


func _validated_runtime_door_state(
	controller: Node,
	door: AnimatableBody2D,
	capture_id: String,
	expected_visual_state: String,
	expected_reached_target: bool,
	expected_group_open: bool,
	expected_group_reached_target: bool,
	minimum_travel_fraction: float,
	maximum_travel_fraction: float,
	closed_position: Vector2,
	open_position: Vector2,
) -> Dictionary:
	var visual_state := str(door.get_meta(&"visual_state", ""))
	var reached_target := bool(door.get_meta(&"reached_target", false))
	var target_open := bool(door.get_meta(&"target_open", false))
	var target_position_value: Variant = door.get_meta(&"target_position", null)
	var mechanism_visual := _runtime_door_visual(door)
	var mechanism_visual_state := (
		str(mechanism_visual.get_meta(&"visual_state", ""))
		if mechanism_visual != null
		else ""
	)
	var native_visual_rect_value: Variant = (
		mechanism_visual.get_meta(&"native_visual_rect", null)
		if mechanism_visual != null
		else null
	)
	var group_open := bool(controller.call("barrier_group_is_open", "red_route"))
	var group_reached_target := bool(controller.call("barrier_group_reached_target", "red_route"))
	var travel_fraction := _barrier_travel_fraction(door.position, closed_position, open_position)
	var expected_target_position := open_position if expected_group_open else closed_position
	var projected_position := closed_position + (open_position - closed_position) * travel_fraction
	var perpendicular_drift := door.position.distance_to(projected_position)
	var state := {
		"barrier_group_id": str(door.get_meta(&"barrier_group_id", "")),
		"socket_id": str(door.get_meta(&"socket_id", "")),
		"visual_state": visual_state,
		"mechanism_visual_state": mechanism_visual_state,
		"native_visual_rect": _json_rect(native_visual_rect_value),
		"reached_target": reached_target,
		"target_open": target_open,
		"group_open": group_open,
		"group_reached_target": group_reached_target,
		"travel_fraction": travel_fraction,
		"position": _json_vector(door.position),
		"closed_position": _json_vector(closed_position),
		"open_position": _json_vector(open_position),
	}
	if (
		str(state["barrier_group_id"]) != "red_route"
		or str(state["socket_id"]) != "gate_red_east"
		or visual_state != expected_visual_state
		or mechanism_visual == null
		or mechanism_visual_state != expected_visual_state
		or not native_visual_rect_value is Rect2
		or (native_visual_rect_value as Rect2).size.x <= 0.0
		or (native_visual_rect_value as Rect2).size.y <= 0.0
		or reached_target != expected_reached_target
		or target_open != expected_group_open
		or group_open != expected_group_open
		or group_reached_target != expected_group_reached_target
		or not is_finite(travel_fraction)
		or travel_fraction < minimum_travel_fraction
		or travel_fraction > maximum_travel_fraction
		or perpendicular_drift > 0.05
		or not target_position_value is Vector2
		or (target_position_value as Vector2).distance_to(expected_target_position) > 0.05
	):
		_fail(
			"Dynamic RED door capture %s does not match its semantic state contract: %s."
			% [capture_id, state]
		)
		return {}
	return state


func _runtime_barrier_body(controller: Node, socket_id: String) -> AnimatableBody2D:
	for body_value: Variant in controller.find_children("*", "AnimatableBody2D", true, false):
		var body := body_value as AnimatableBody2D
		if (
			str(body.get_meta(&"dynamic_kind", "")) == "dynamic_door"
			and str(body.get_meta(&"socket_id", "")) == socket_id
		):
			return body
	_fail("Runtime capture could not find dynamic door body for socket %s." % socket_id)
	return null


func _runtime_door_visual(door: AnimatableBody2D) -> Node2D:
	for visual_value: Variant in door.find_children("*", "Node2D", true, false):
		var visual := visual_value as Node2D
		if visual.has_meta(&"native_visual_rect") and visual.has_meta(&"visual_state"):
			return visual
	return null


func _runtime_barrier_open_offset(group_id: String, socket_id: String) -> Vector2:
	var runtime := _package_manifest.get("runtime", {}) as Dictionary
	for group_value: Variant in runtime.get("barrier_groups", []):
		if not group_value is Dictionary:
			continue
		var group := group_value as Dictionary
		if str(group.get("id", "")) != group_id:
			continue
		for member_value: Variant in group.get("members", []):
			if not member_value is Dictionary:
				continue
			var member := member_value as Dictionary
			if str(member.get("socket_id", "")) == socket_id:
				return _manifest_vector2(member.get("open_offset", null))
	return Vector2(NAN, NAN)


func _capture_runtime_trolley_state(
	controller: Node,
	file_name: String,
	capture_id: String,
	expected_visual_state: String,
	captures: Array[Dictionary],
) -> bool:
	var snapshot_value: Variant = controller.call("state_snapshot")
	if not snapshot_value is Dictionary:
		_fail("Runtime trolley state %s returned no snapshot." % capture_id)
		return false
	var snapshot := snapshot_value as Dictionary
	if str(snapshot.get("trolley_visual_state", "")) != expected_visual_state:
		_fail(
			"Runtime trolley state %s expected %s, got %s."
			% [capture_id, expected_visual_state, str(snapshot.get("trolley_visual_state", ""))]
		)
		return false
	var local_position_value: Variant = snapshot.get("elevator_local_position", null)
	if not local_position_value is Vector2 or not controller is Node2D:
		_fail("Runtime trolley state %s has no physical position." % capture_id)
		return false
	var trolley_world_position := (controller as Node2D).to_global(local_position_value as Vector2)
	if not await _capture_runtime_detail(
		controller,
		file_name,
		capture_id,
		"tower_shaft",
		captures,
		trolley_world_position,
	):
		return false
	var capture: Dictionary = captures[captures.size() - 1]
	capture["expected_trolley_visual_state"] = expected_visual_state
	if expected_visual_state == "contact_closed":
		var aperture_proof := await _trolley_open_aperture_capture_proof(controller)
		if aperture_proof.is_empty():
			return false
		capture["open_aperture_proof"] = aperture_proof
	return true


func _spawn_runtime_trolley_blocker(controller: Node, structure_root: Node2D) -> CharacterBody2D:
	if not controller is Node2D or structure_root == null:
		_fail("Runtime trolley blocker fixture requires a Node2D controller and structure root.")
		return null
	var safety_shape: CollisionShape2D = null
	for area_value: Variant in controller.find_children("*", "Area2D", true, false):
		var area := area_value as Area2D
		if str(area.get_meta(&"socket_id", "")) != "elevator_upper_travel":
			continue
		for shape_value: Variant in area.find_children("*", "CollisionShape2D", true, false):
			var candidate := shape_value as CollisionShape2D
			if not candidate.disabled and candidate.shape != null:
				safety_shape = candidate
				break
		if safety_shape != null:
			break
	if safety_shape == null:
		_fail("Runtime trolley blocker fixture could not discover the active elevator safety Shape2D.")
		return null
	var blocker := CharacterBody2D.new()
	blocker.name = "ProxyCaptureTrolleyBlocker"
	blocker.add_to_group(&"dive_player")
	blocker.collision_layer = 1
	blocker.collision_mask = 1
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(40.0, 70.0)
	collision.shape = shape
	blocker.add_child(collision)
	blocker.position = structure_root.to_local(safety_shape.global_position)
	structure_root.add_child(blocker)
	blocker.force_update_transform()
	return blocker


func _validated_runtime_power_state(
	controller: Node,
	state_label: String,
	expected_lever_positions: Dictionary,
	expected_matched_circuit_id: String,
	expected_active_circuit_id: String,
	expected_power_status: String,
	expected_circuit_states: Dictionary,
	expected_diagnostic_id: String = "",
) -> Dictionary:
	if not controller.has_method("state_snapshot"):
		_fail("Runtime power state %s has no public state_snapshot API." % state_label)
		return {}
	var snapshot_value: Variant = controller.call("state_snapshot")
	if not snapshot_value is Dictionary:
		_fail("Runtime power state %s returned a non-dictionary snapshot." % state_label)
		return {}
	var snapshot := snapshot_value as Dictionary
	var fields_match := (
		_dictionary_matches_exact(snapshot.get("lever_positions", null), expected_lever_positions)
		and str(snapshot.get("matched_circuit_id", "")) == expected_matched_circuit_id
		and str(snapshot.get("active_circuit_id", "")) == expected_active_circuit_id
		and str(snapshot.get("power_status", "")) == expected_power_status
		and _dictionary_matches_exact(snapshot.get("circuit_states", null), expected_circuit_states)
	)
	if not expected_diagnostic_id.is_empty():
		fields_match = (
			fields_match
			and str(snapshot.get("power_diagnostic_id", "")) == expected_diagnostic_id
			and not str(snapshot.get("power_diagnostic_message", "")).is_empty()
		)
	if not fields_match:
		_fail(
			"Runtime power state %s does not match the capture contract: snapshot=%s."
			% [state_label, str(snapshot)]
		)
		return {}
	return {
		"lever_positions": (snapshot.get("lever_positions", {}) as Dictionary).duplicate(true),
		"matched_circuit_id": expected_matched_circuit_id,
		"active_circuit_id": expected_active_circuit_id,
		"power_status": expected_power_status,
		"circuit_states": (snapshot.get("circuit_states", {}) as Dictionary).duplicate(true),
		"power_diagnostic_id": str(snapshot.get("power_diagnostic_id", "")),
		"power_diagnostic_message": str(snapshot.get("power_diagnostic_message", "")),
	}


func _runtime_power_lever_ids(controller: Node) -> PackedStringArray:
	if not controller.has_method("power_lever_ids"):
		_fail("Runtime tower controller has no public power_lever_ids API.")
		return PackedStringArray()
	var lever_ids_value: Variant = controller.call("power_lever_ids")
	if not lever_ids_value is PackedStringArray:
		_fail("Runtime tower power_lever_ids must return PackedStringArray.")
		return PackedStringArray()
	var lever_ids: PackedStringArray = lever_ids_value
	var expected_ids := PackedStringArray(["a_lever_1", "a_lever_2", "a_lever_3"])
	if lever_ids != expected_ids:
		_fail(
			"Runtime tower power lever IDs must be %s in circuit-pattern order; got %s."
			% [str(expected_ids), str(lever_ids)]
		)
		return PackedStringArray()
	var seen_ids := {}
	for lever_id: String in lever_ids:
		if lever_id.is_empty() or seen_ids.has(lever_id):
			_fail("Runtime tower power lever IDs must be non-empty and unique.")
			return PackedStringArray()
		seen_ids[lever_id] = true
	return lever_ids.duplicate()


func _ordered_power_positions(
	lever_ids: PackedStringArray,
	positions: PackedStringArray,
) -> Dictionary:
	if lever_ids.size() != positions.size():
		_fail("Runtime power position fixture does not match the lever count.")
		return {}
	var result := {}
	for lever_index: int in range(lever_ids.size()):
		result[lever_ids[lever_index]] = positions[lever_index]
	return result


func _activate_runtime_power_lever(controller: Node, lever_id: String) -> bool:
	if not controller.has_method("activate_power_lever"):
		_fail("Runtime tower controller has no public activate_power_lever API.")
		return false
	var result: Variant = controller.call("activate_power_lever", lever_id)
	if not result is Dictionary or not bool((result as Dictionary).get("success", false)):
		var snapshot: Variant = controller.call("state_snapshot") if controller.has_method("state_snapshot") else {}
		_fail(
			"Runtime capture could not toggle power lever %s: result=%s state=%s."
			% [lever_id, str(result), str(snapshot)]
		)
		return false
	return true


func _set_runtime_power_pattern(
	controller: Node,
	lever_ids: PackedStringArray,
	target_positions: PackedStringArray,
) -> bool:
	var snapshot_value: Variant = controller.call("state_snapshot")
	if not snapshot_value is Dictionary:
		_fail("Runtime tower returned no state while setting a power pattern.")
		return false
	var current_positions := (snapshot_value as Dictionary).get("lever_positions", {}) as Dictionary
	for lever_index: int in range(lever_ids.size()):
		var lever_id := lever_ids[lever_index]
		if str(current_positions.get(lever_id, "up")) == target_positions[lever_index]:
			continue
		if not _activate_runtime_power_lever(controller, lever_id):
			return false
		current_positions[lever_id] = target_positions[lever_index]
	return true


func _dictionary_matches_exact(actual_value: Variant, expected: Dictionary) -> bool:
	if not actual_value is Dictionary:
		return false
	var actual := actual_value as Dictionary
	if actual.size() != expected.size():
		return false
	for key: Variant in expected.keys():
		if not actual.has(key) or actual[key] != expected[key]:
			return false
	return true


func _await_runtime_elevator_progress(controller: Node, minimum_local_y: float) -> bool:
	for _frame in range(420):
		var snapshot: Variant = controller.call("state_snapshot")
		if snapshot is Dictionary:
			var position_value: Variant = (snapshot as Dictionary).get("elevator_local_position", null)
			if position_value is Vector2 and (position_value as Vector2).y >= minimum_local_y:
				return true
		await physics_frame
	return false


func _await_runtime_elevator_stop(controller: Node, stop_id: String) -> bool:
	for _frame in range(420):
		if bool(controller.call("elevator_reached_stop", stop_id)):
			return true
		await physics_frame
	return false


func _await_runtime_barrier_travel_window(
	controller: Node,
	door: AnimatableBody2D,
	closed_position: Vector2,
	open_position: Vector2,
	minimum_fraction: float,
	maximum_fraction: float,
) -> bool:
	for _frame in range(180):
		if not is_instance_valid(door):
			_fail("RED door disappeared before the deterministic MID capture.")
			return false
		var travel_fraction := _barrier_travel_fraction(door.position, closed_position, open_position)
		var visual_state := str(door.get_meta(&"visual_state", ""))
		var reached_target := bool(door.get_meta(&"reached_target", false))
		if travel_fraction > maximum_fraction:
			_fail(
				"RED door skipped the deterministic MID window: fraction=%.4f state=%s reached=%s."
				% [travel_fraction, visual_state, reached_target]
			)
			return false
		if travel_fraction >= minimum_fraction:
			if (
				visual_state != "opening"
				or reached_target
				or not bool(controller.call("barrier_group_is_open", "red_route"))
				or bool(controller.call("barrier_group_reached_target", "red_route"))
			):
				_fail(
					"RED door entered the MID travel window without opening semantics: fraction=%.4f state=%s reached=%s."
					% [travel_fraction, visual_state, reached_target]
				)
				return false
			return true
		await physics_frame
	_fail("RED door did not enter the deterministic 40-60 percent MID window.")
	return false


func _barrier_travel_fraction(
	position: Vector2,
	closed_position: Vector2,
	open_position: Vector2,
) -> float:
	var travel := open_position - closed_position
	var travel_length_squared := travel.length_squared()
	if travel_length_squared <= 0.0001:
		return NAN
	return (position - closed_position).dot(travel) / travel_length_squared


func _await_runtime_barrier_group_settle(controller: Node, group_id: String) -> bool:
	for _frame in range(180):
		if bool(controller.call("barrier_group_reached_target", group_id)):
			return true
		await physics_frame
	return false


func _await_runtime_barriers_settle(controller: Node) -> bool:
	var group_ids := [
		"red_route",
		"blue_route",
		"yellow_route",
		"shortcut_b",
		"shortcut_c",
		"hatch_d",
		"hatch_basement",
	]
	for _frame in range(180):
		var settled := true
		for group_id: String in group_ids:
			if not bool(controller.call("barrier_group_reached_target", group_id)):
				settled = false
				break
		if settled:
			return true
		await physics_frame
	return false


func _activate_runtime_control(controller: Node, control_id: String) -> bool:
	var result: Variant = controller.call("activate_control", control_id)
	if not result is Dictionary or not bool((result as Dictionary).get("success", false)):
		var snapshot: Variant = controller.call("state_snapshot") if controller.has_method("state_snapshot") else {}
		_fail(
			"Runtime capture could not activate %s: result=%s state=%s."
			% [control_id, str(result), str(snapshot)]
		)
		return false
	return true


func _activate_runtime_control_expect_d_fault(controller: Node, control_id: String) -> bool:
	var result_value: Variant = controller.call("activate_control", control_id)
	var result: Dictionary = result_value as Dictionary if result_value is Dictionary else {}
	if bool(result.get("success", true)):
		_fail(
			"Runtime capture expected %s to enter a diagnostic fault: result=%s state=%s."
			% [control_id, result, controller.call("state_snapshot")]
		)
		return false
	var snapshot_value: Variant = controller.call("state_snapshot")
	if not snapshot_value is Dictionary:
		_fail("Runtime D fault returned no state snapshot.")
		return false
	var snapshot := snapshot_value as Dictionary
	if not bool(snapshot.get("d_requires_reset", false)) or int(snapshot.get("d_progress", -1)) != 0:
		_fail("Runtime D fault must set d_requires_reset=true without advancing progress: %s." % snapshot)
		return false
	for d_control_id: String in ["d_valve_v1", "d_valve_v2", "d_valve_v3", "d_reset"]:
		var d_control = controller.call("control", d_control_id)
		if not d_control is Node or str((d_control as Node).get_meta(&"visual_state", "")) != "fault":
			_fail("Runtime D fault must render %s with visual_state=fault." % d_control_id)
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
	_last_capture_image = image
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


func _capture_runtime_door_background(door: AnimatableBody2D) -> Image:
	var mechanism_visual := _runtime_door_visual(door)
	if mechanism_visual == null:
		_fail("Dynamic door ROI proof could not find its MechanismVisual.")
		return null
	var was_visible := mechanism_visual.visible
	mechanism_visual.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var background_image := root.get_texture().get_image()
	mechanism_visual.visible = was_visible
	await process_frame
	await RenderingServer.frame_post_draw
	if (
		background_image == null
		or background_image.is_empty()
		or background_image.get_size() != CAPTURE_RESOLUTION
	):
		_fail("Dynamic door ROI proof could not render a matching background reference.")
		return null
	return background_image


func _runtime_door_triptych_roi_proof(
	door: AnimatableBody2D,
	closed_position: Vector2,
	mid_position: Vector2,
	open_position: Vector2,
	closed_image: Image,
	closed_background: Image,
	mid_image: Image,
	mid_background: Image,
	open_image: Image,
	open_background: Image,
) -> Dictionary:
	var mechanism_visual := _runtime_door_visual(door)
	if mechanism_visual == null:
		_fail("Dynamic door triptych proof could not find its material visual.")
		return {}
	var native_visual_rect_value: Variant = mechanism_visual.get_meta(&"native_visual_rect", null)
	if not native_visual_rect_value is Rect2:
		_fail("Dynamic door triptych proof has no native visual rect.")
		return {}
	var native_visual_rect := native_visual_rect_value as Rect2
	var closed_screen_rect := _runtime_door_screen_rect(
		door,
		mechanism_visual,
		closed_position,
		native_visual_rect,
	)
	var mid_screen_rect := _runtime_door_screen_rect(
		door,
		mechanism_visual,
		mid_position,
		native_visual_rect,
	)
	var open_screen_rect := _runtime_door_screen_rect(
		door,
		mechanism_visual,
		open_position,
		native_visual_rect,
	)
	var opening_roi := _clipped_capture_roi(closed_screen_rect.grow(-8.0))
	var swept_roi := _clipped_capture_roi(
		closed_screen_rect.merge(mid_screen_rect).merge(open_screen_rect).grow(4.0)
	)
	if opening_roi.size.x <= 0 or opening_roi.size.y <= 0 or swept_roi.size.x <= 0 or swept_roi.size.y <= 0:
		_fail("Dynamic door triptych proof produced an empty screen ROI.")
		return {}
	var closed_material := _door_material_mask(closed_image, closed_background, opening_roi)
	var mid_material := _door_material_mask(mid_image, mid_background, opening_roi)
	var open_material := _door_material_mask(open_image, open_background, opening_roi)
	if closed_material.is_empty() or mid_material.is_empty() or open_material.is_empty():
		return {}
	var sample_count := int(closed_material.get("sample_count", 0))
	if sample_count <= 0:
		_fail("Dynamic door triptych proof sampled no opening pixels.")
		return {}
	var closed_cover := float(closed_material.get("material_count", 0)) / float(sample_count)
	var mid_cover := float(mid_material.get("material_count", 0)) / float(sample_count)
	var open_cover := float(open_material.get("material_count", 0)) / float(sample_count)
	var closed_mask: PackedByteArray = closed_material.get("mask", PackedByteArray())
	var mid_mask: PackedByteArray = mid_material.get("mask", PackedByteArray())
	var open_mask: PackedByteArray = open_material.get("mask", PackedByteArray())
	var closed_mid_difference := _binary_mask_difference_ratio(closed_mask, mid_mask)
	var mid_open_difference := _binary_mask_difference_ratio(mid_mask, open_mask)
	var closed_open_difference := _binary_mask_difference_ratio(closed_mask, open_mask)
	if (
		closed_cover < DOOR_CLOSED_COVER_MIN
		or mid_cover < DOOR_MID_COVER_MIN
		or open_cover > DOOR_OPEN_COVER_MAX
		or closed_cover - mid_cover < DOOR_COVER_STEP_MIN
		or mid_cover - open_cover < DOOR_COVER_STEP_MIN
		or closed_mid_difference < DOOR_ADJACENT_MASK_DIFFERENCE_MIN
		or mid_open_difference < DOOR_ADJACENT_MASK_DIFFERENCE_MIN
		or closed_open_difference < DOOR_ENDPOINT_MASK_DIFFERENCE_MIN
	):
		_fail(
			"Dynamic door triptych must visibly clear its material opening: cover closed=%.3f mid=%.3f open=%.3f; mask delta closed-mid=%.3f mid-open=%.3f closed-open=%.3f."
			% [
				closed_cover,
				mid_cover,
				open_cover,
				closed_mid_difference,
				mid_open_difference,
				closed_open_difference,
			]
		)
		return {}
	return {
		"contract": "closed_mid_open_material_cover_progression",
		"socket_id": "gate_red_east",
		"barrier_group_id": "red_route",
		"opening_roi_screen": _json_rect(Rect2(opening_roi.position, opening_roi.size)),
		"swept_roi_screen": _json_rect(Rect2(swept_roi.position, swept_roi.size)),
		"state_screen_rects": {
			"closed": _json_rect(closed_screen_rect),
			"mid": _json_rect(mid_screen_rect),
			"open": _json_rect(open_screen_rect),
		},
		"travel_fraction": {
			"closed": _barrier_travel_fraction(closed_position, closed_position, open_position),
			"mid": _barrier_travel_fraction(mid_position, closed_position, open_position),
			"open": _barrier_travel_fraction(open_position, closed_position, open_position),
		},
		"material_cover_ratio": {
			"closed": closed_cover,
			"mid": mid_cover,
			"open": open_cover,
		},
		"material_pixel_count": {
			"closed": int(closed_material.get("material_count", 0)),
			"mid": int(mid_material.get("material_count", 0)),
			"open": int(open_material.get("material_count", 0)),
		},
		"mask_difference_ratio": {
			"closed_mid": closed_mid_difference,
			"mid_open": mid_open_difference,
			"closed_open": closed_open_difference,
		},
		"sample_count": sample_count,
	}


func _runtime_door_screen_rect(
	door: AnimatableBody2D,
	mechanism_visual: Node2D,
	body_position: Vector2,
	local_visual_rect: Rect2,
) -> Rect2:
	var parent_canvas := door.get_parent() as CanvasItem
	if parent_canvas == null or mechanism_visual.get_parent() != door:
		return Rect2()
	var body_transform := door.transform
	body_transform.origin = body_position
	var local_to_screen := (
		parent_canvas.get_global_transform_with_canvas()
		* body_transform
		* mechanism_visual.transform
	)
	return _transformed_rect_aabb(local_visual_rect, local_to_screen)


func _transformed_rect_aabb(rect: Rect2, transform: Transform2D) -> Rect2:
	var corners := [
		transform * rect.position,
		transform * Vector2(rect.end.x, rect.position.y),
		transform * rect.end,
		transform * Vector2(rect.position.x, rect.end.y),
	]
	var minimum: Vector2 = corners[0]
	var maximum: Vector2 = corners[0]
	for corner_value: Variant in corners:
		var corner := corner_value as Vector2
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


func _clipped_capture_roi(screen_rect: Rect2) -> Rect2i:
	var minimum := Vector2i(
		maxi(0, floori(screen_rect.position.x)),
		maxi(0, floori(screen_rect.position.y)),
	)
	var maximum := Vector2i(
		mini(CAPTURE_RESOLUTION.x, ceili(screen_rect.end.x)),
		mini(CAPTURE_RESOLUTION.y, ceili(screen_rect.end.y)),
	)
	var size := maximum - minimum
	return Rect2i(minimum, Vector2i(maxi(0, size.x), maxi(0, size.y)))


func _door_material_mask(image: Image, background: Image, roi: Rect2i) -> Dictionary:
	if (
		image == null
		or background == null
		or image.is_empty()
		or background.is_empty()
		or image.get_size() != CAPTURE_RESOLUTION
		or background.get_size() != CAPTURE_RESOLUTION
	):
		_fail("Dynamic door material proof received mismatched images.")
		return {}
	var sample_count := roi.size.x * roi.size.y
	if sample_count <= 0:
		return {}
	var mask := PackedByteArray()
	mask.resize(sample_count)
	var material_count := 0
	var sample_index := 0
	for y: int in range(roi.position.y, roi.end.y):
		for x: int in range(roi.position.x, roi.end.x):
			if _rgb_distance(image.get_pixel(x, y), background.get_pixel(x, y)) > DOOR_MATERIAL_DISTANCE_THRESHOLD:
				mask[sample_index] = 1
				material_count += 1
			sample_index += 1
	return {
		"mask": mask,
		"material_count": material_count,
		"sample_count": sample_count,
	}


func _binary_mask_difference_ratio(first: PackedByteArray, second: PackedByteArray) -> float:
	if first.is_empty() or first.size() != second.size():
		return 0.0
	var difference_count := 0
	for index: int in range(first.size()):
		if first[index] != second[index]:
			difference_count += 1
	return float(difference_count) / float(first.size())


func _trolley_open_aperture_capture_proof(controller: Node) -> Dictionary:
	var trolley_visual := _runtime_trolley_visual(controller)
	if trolley_visual == null:
		_fail("Trolley aperture proof could not find MechanismVisual.")
		return {}
	var aperture_value: Variant = trolley_visual.get_meta(&"open_aperture_local_rect", null)
	if (
		not aperture_value is Rect2
		or (aperture_value as Rect2).size.x <= 0.0
		or (aperture_value as Rect2).size.y <= 0.0
		or not bool(trolley_visual.get_meta(&"open_aperture_expected_transparent", false))
	):
		_fail("Trolley MechanismVisual does not publish a valid transparent aperture contract.")
		return {}
	if _last_capture_image == null or _last_capture_image.is_empty():
		_fail("Trolley aperture proof has no exact captured frame.")
		return {}
	var captured_image := _last_capture_image
	var was_visible := trolley_visual.visible
	trolley_visual.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var background_image := root.get_texture().get_image()
	trolley_visual.visible = was_visible
	await process_frame
	await RenderingServer.frame_post_draw
	if background_image == null or background_image.is_empty() or background_image.get_size() != captured_image.get_size():
		_fail("Trolley aperture proof could not render the matching background reference.")
		return {}
	var aperture := aperture_value as Rect2
	var sample_count := 0
	var background_match_count := 0
	var opaque_fill_like_count := 0
	var transform := trolley_visual.get_global_transform_with_canvas()
	var rejected_fill := Color(0.01, 0.025, 0.03, 1.0)
	for sample_y: int in range(7):
		for sample_x: int in range(17):
			var local_point := Vector2(
				lerpf(aperture.position.x + 8.0, aperture.end.x - 8.0, (float(sample_x) + 0.5) / 17.0),
				lerpf(aperture.position.y + 8.0, aperture.end.y - 8.0, (float(sample_y) + 0.5) / 7.0),
			)
			var screen_point := transform * local_point
			var pixel := Vector2i(roundi(screen_point.x), roundi(screen_point.y))
			if pixel.x < 0 or pixel.y < 0 or pixel.x >= captured_image.get_width() or pixel.y >= captured_image.get_height():
				continue
			var captured_color := captured_image.get_pixelv(pixel)
			var background_color := background_image.get_pixelv(pixel)
			sample_count += 1
			if _rgb_distance(captured_color, background_color) <= 0.045:
				background_match_count += 1
			if _rgb_distance(captured_color, rejected_fill) <= 0.055:
				opaque_fill_like_count += 1
	if sample_count <= 0:
		_fail("Trolley aperture proof produced no in-frame samples.")
		return {}
	var background_match_ratio := float(background_match_count) / float(sample_count)
	var opaque_fill_like_ratio := float(opaque_fill_like_count) / float(sample_count)
	if background_match_ratio < 0.35 or opaque_fill_like_ratio > 0.35:
		_fail(
			"Trolley aperture must reveal the rendered world instead of an opaque dark plate: background_match=%.3f opaque_fill_like=%.3f samples=%d."
			% [background_match_ratio, opaque_fill_like_ratio, sample_count]
		)
		return {}
	return {
		"contract": "transparent_world_background_visible",
		"sample_count": sample_count,
		"background_match_ratio": background_match_ratio,
		"opaque_fill_like_ratio": opaque_fill_like_ratio,
	}


func _runtime_trolley_visual(controller: Node) -> Node2D:
	for body_value: Variant in controller.find_children("*", "AnimatableBody2D", true, false):
		var body := body_value as AnimatableBody2D
		if str(body.get_meta(&"dynamic_kind", "")) != "empty_maintenance_trolley":
			continue
		return body.get_node_or_null("MechanismVisual") as Node2D
	return null


func _rgb_distance(first: Color, second: Color) -> float:
	return Vector3(first.r - second.r, first.g - second.g, first.b - second.b).length()


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
	var expected_files := {}
	for file_name_value: Variant in CAPTURE_FILES.values():
		var file_name := str(file_name_value)
		if file_name != _capture_file(&"manifest"):
			expected_files[file_name] = true
	var captured_files := {}
	for capture_value: Variant in captures:
		var capture := capture_value as Dictionary
		var file_name := str(capture.get("file", ""))
		if file_name.is_empty() or captured_files.has(file_name):
			_fail("Capture generation produced an empty or duplicate filename: %s." % file_name)
			return false
		captured_files[file_name] = true
	if not _dictionary_matches_exact(captured_files, expected_files):
		_fail(
			"Capture generation must produce every CAPTURE_FILES PNG exactly once: expected=%s actual=%s."
			% [expected_files.keys(), captured_files.keys()]
		)
		return false
	var report := {
		"resolution": [CAPTURE_RESOLUTION.x, CAPTURE_RESOLUTION.y],
		"world_size": [world_size.x, world_size.y],
		"gameplay_zoom": GAMEPLAY_ZOOM,
		"mount_mode": "local_package_over_read_only_map_background",
		"background_map": {
			"scene_path": MAP_SCENE_PATH,
			"scene_file_path": _map.scene_file_path,
			"manifest_path": MAP_MANIFEST_PATH,
			"manifest_sha256": FileAccess.get_sha256(MAP_MANIFEST_PATH),
			"scene_manifest_sha256": str(_map.get_meta("manifest_sha256", "")),
			"revision_id": str(_map.get_meta("revision_id", "")),
			"topology_revision": str(_map.get_meta("topology_revision", "")),
			"presentation_revision": str(_map.get_meta("presentation_revision", "")),
			"tower_package_pin": _background_map_package_sha256,
		},
		"tower_package": {
			"package_manifest_path": TOWER_PACKAGE_MANIFEST_PATH,
			"package_manifest_sha256": FileAccess.get_sha256(TOWER_PACKAGE_MANIFEST_PATH),
			"scene_package_manifest_sha256": str(_tower_root.get_meta("package_manifest_sha256", "")),
			"structure_scene_path": TOWER_PACKAGE_SCENE_PATH,
			"structure_scene_sha256": FileAccess.get_sha256(TOWER_PACKAGE_SCENE_PATH),
			"controller_script": str(_tower_root.get_meta("controller_script", "")),
			"placement_origin": [_tower_origin.x, _tower_origin.y],
			"size": [_tower_size.x, _tower_size.y],
			"structure_texture_path": TOWER_STRUCTURE_TEXTURE_PATH,
			"structure_texture_sha256": FileAccess.get_sha256(TOWER_STRUCTURE_TEXTURE_PATH),
			"interior_texture_path": TOWER_INTERIOR_TEXTURE_PATH,
			"interior_texture_sha256": FileAccess.get_sha256(TOWER_INTERIOR_TEXTURE_PATH),
		},
		"captures": captures,
	}
	var report_path := OUTPUT_ROOT.path_join(_capture_file(&"manifest"))
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


func _capture_file(capture_id: StringName) -> String:
	if not CAPTURE_FILES.has(capture_id):
		_fail("Capture file id is not declared in CAPTURE_FILES: %s." % capture_id)
		return ""
	return str(CAPTURE_FILES[capture_id])


func _cleanup_scene() -> void:
	if _capture_host != null and is_instance_valid(_capture_host):
		_capture_host.free()
	elif _map != null and is_instance_valid(_map):
		_map.free()
	_capture_host = null
	_map = null
	_tower_root = null
	_camera = null


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error("Underwater map proxy capture failed: " + message)
	_cleanup_scene()
	quit(1)
