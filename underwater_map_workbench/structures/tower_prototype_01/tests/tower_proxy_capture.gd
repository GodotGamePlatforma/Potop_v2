extends SceneTree

const CompilerScript := preload("res://underwater_map_workbench/runtime/UnderwaterMapSceneCompiler.gd")
const LocalRuntimeScript := preload("res://underwater_map_workbench/runtime/UnderwaterMapRuntime.gd")
const WorldStateScript := preload("res://scripts/data/UnderwaterWorldState.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")

const MAP_SCENE_PATH := "res://underwater_map_workbench/UnderwaterMap.tscn"
const OUTPUT_ROOT := "user://test_tower_prototype_01_proxy_capture"
const CAMPAIGN_SEED := 73_331
const CAPTURE_RESOLUTION := Vector2i(1280, 720)
const GAMEPLAY_ZOOM := 1.2
const TOWER_CAPTURE_FILE := "tower_prototype_01.png"
const TOWER_ENTRY_CAPTURE_FILE := "tower_prototype_01_entry.png"
const TOWER_A_CAPTURE_FILE := "tower_prototype_01_a.png"
const TOWER_B_CAPTURE_FILE := "tower_prototype_01_b.png"
const TOWER_C_CAPTURE_FILE := "tower_prototype_01_c.png"
const TOWER_D_CAPTURE_FILE := "tower_prototype_01_d.png"
const TOWER_SHAFT_CAPTURE_FILE := "tower_prototype_01_shaft.png"
const TOWER_BASEMENT_CAPTURE_FILE := "tower_prototype_01_basement.png"
const TOWER_RUNTIME_INITIAL_CAPTURE_FILE := "tower_prototype_01_runtime_initial.png"
const TOWER_RUNTIME_ELEVATOR_CAPTURE_FILE := "tower_prototype_01_runtime_elevator_mid.png"
const TOWER_RUNTIME_COMPLETE_CAPTURE_FILE := "tower_prototype_01_runtime_complete.png"
const TOWER_RUNTIME_B_LATCH_CAPTURE_FILE := "tower_prototype_01_runtime_b_latched.png"
const TOWER_RUNTIME_C_CONTACT_CAPTURE_FILE := "tower_prototype_01_runtime_c_contact.png"
const TOWER_RUNTIME_C_LATCH_CAPTURE_FILE := "tower_prototype_01_runtime_c_latched.png"
const TOWER_RUNTIME_D_PRESSURE_CAPTURE_FILE := "tower_prototype_01_runtime_d_pressure.png"
const TOWER_RUNTIME_D_ACTUATOR_CAPTURE_FILE := "tower_prototype_01_runtime_d_actuator.png"
const TOWER_RUNTIME_D_FAULT_CAPTURE_FILE := "tower_prototype_01_runtime_d_fault.png"
const TOWER_RUNTIME_D_RESET_CAPTURE_FILE := "tower_prototype_01_runtime_d_reset.png"
const TOWER_RUNTIME_D_RELEASE_CAPTURE_FILE := "tower_prototype_01_runtime_d_release.png"
const TOWER_RUNTIME_ARCHIVE_CAPTURE_FILE := "tower_prototype_01_runtime_archive_open.png"
const TOWER_POWER_START_CAPTURE_FILE := "tower_prototype_01_power_start.png"
const TOWER_POWER_RED_ACTIVE_CAPTURE_FILE := "tower_prototype_01_power_red_active.png"
const TOWER_POWER_BLUE_LOCKED_CAPTURE_FILE := "tower_prototype_01_power_blue_locked.png"
const TOWER_POWER_BLUE_ACTIVE_CAPTURE_FILE := "tower_prototype_01_power_blue_active.png"
const TOWER_POWER_YELLOW_ACTIVE_CAPTURE_FILE := "tower_prototype_01_power_yellow_active.png"
const TOWER_POWER_FAULT_CAPTURE_FILE := "tower_prototype_01_power_fault.png"
const TOWER_STRUCTURE_ID := "tower_prototype_01"
const TOWER_PACKAGE_SCENE_PATH := "res://underwater_map_workbench/structures/tower_prototype_01/generated/structure.tscn"
const TOWER_STRUCTURE_TEXTURE_PATH := "res://underwater_map_workbench/structures/tower_prototype_01/assets/visual/tower_structure.png"
const TOWER_INTERIOR_TEXTURE_PATH := "res://underwater_map_workbench/structures/tower_prototype_01/assets/visual/tower_interior.png"
const TOWER_CAPTURE_MARGIN := Vector2(240.0, 240.0)
const VIEWPORT_READY_FRAME_LIMIT := 60
const RENDER_SETTLE_FRAMES := 4

var _capture_host: Node2D
var _map: Node2D
var _camera: Camera2D
var _tower_origin := Vector2.ZERO
var _tower_size := Vector2.ZERO
var _tower_detail_positions: Dictionary = {}
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
	var source_manifest := CompilerScript.new().manifest_snapshot()
	if source_manifest.is_empty() or not _configure_tower_capture_targets(source_manifest):
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
		_tower_origin.x,
		_tower_origin.y,
		_tower_size.x,
		_tower_size.y,
	]
	tower_capture["requested_margin"] = [TOWER_CAPTURE_MARGIN.x, TOWER_CAPTURE_MARGIN.y]
	for tower_detail in [
		[TOWER_ENTRY_CAPTURE_FILE, "tower_entry"],
		[TOWER_A_CAPTURE_FILE, "tower_a"],
		[TOWER_B_CAPTURE_FILE, "tower_b"],
		[TOWER_C_CAPTURE_FILE, "tower_c"],
		[TOWER_D_CAPTURE_FILE, "tower_d"],
		[TOWER_SHAFT_CAPTURE_FILE, "tower_shaft"],
		[TOWER_BASEMENT_CAPTURE_FILE, "tower_basement"],
	]:
		if not await _capture_frame(
			str(tower_detail[0]),
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


func _configure_tower_capture_targets(manifest: Dictionary) -> bool:
	var structures_value = manifest.get("structures", null)
	if not structures_value is Dictionary:
		_fail("The active manifest has no structures record for capture framing.")
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
		_fail("The active manifest has no structure instance %s." % TOWER_STRUCTURE_ID)
		return false
	_tower_origin = _manifest_vector2(tower_instance.get("origin", null))
	_tower_size = _manifest_vector2(tower_instance.get("size", null))
	if not _tower_origin.is_finite() or not _tower_size.is_finite() or _tower_size.x <= 0.0 or _tower_size.y <= 0.0:
		_fail("The tower capture target must publish a finite, positive manifest origin and size.")
		return false

	var socket_rects := {}
	var sockets_value = tower_instance.get("sockets", null)
	if not sockets_value is Array:
		_fail("The tower capture target has no manifest socket array.")
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
	if tower_root.position != _tower_origin or tower_root.scale != Vector2.ONE:
		_fail("The generated tower root does not match its manifest origin and identity scale.")
		return false
	if tower_root.get_meta("size", Vector2.ZERO) != _tower_size:
		_fail("The generated tower root does not match its manifest size.")
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
		TOWER_CAPTURE_FILE,
		TOWER_ENTRY_CAPTURE_FILE,
		TOWER_A_CAPTURE_FILE,
		TOWER_B_CAPTURE_FILE,
		TOWER_C_CAPTURE_FILE,
		TOWER_D_CAPTURE_FILE,
		TOWER_SHAFT_CAPTURE_FILE,
		TOWER_BASEMENT_CAPTURE_FILE,
		TOWER_RUNTIME_INITIAL_CAPTURE_FILE,
		TOWER_RUNTIME_ELEVATOR_CAPTURE_FILE,
		TOWER_RUNTIME_COMPLETE_CAPTURE_FILE,
		TOWER_POWER_START_CAPTURE_FILE,
		TOWER_POWER_RED_ACTIVE_CAPTURE_FILE,
		TOWER_POWER_BLUE_LOCKED_CAPTURE_FILE,
		TOWER_POWER_BLUE_ACTIVE_CAPTURE_FILE,
		TOWER_POWER_YELLOW_ACTIVE_CAPTURE_FILE,
		TOWER_POWER_FAULT_CAPTURE_FILE,
		"capture_manifest.json",
	]
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


func _capture_runtime_tower_states(
	tower_capture_rect: Rect2,
	captures: Array[Dictionary],
) -> bool:
	var compiler = CompilerScript.new()
	var manifest := compiler.manifest_snapshot()
	if manifest.is_empty():
		_fail("Runtime capture could not validate the active manifest.")
		return false
	var world = WorldStateScript.new()
	world.setup(CAMPAIGN_SEED)
	var compile_errors: PackedStringArray = compiler.generate(world, CAMPAIGN_SEED)
	if not compile_errors.is_empty() or world.blueprint == null:
		_fail("Runtime capture could not compile the map: %s" % "; ".join(compile_errors))
		return false
	var runtime = LocalRuntimeScript.new()
	runtime.name = "UnderwaterMapRuntimeCapture"
	var expedition_setup = ExpeditionSetupScript.new()
	expedition_setup.day = 4
	expedition_setup.base_support_level = 1
	expedition_setup.tutorial_mode = bool((manifest.get("gameplay", {}) as Dictionary).get("tutorial_enabled", false))
	var entry: Dictionary = manifest.get("entry", {})
	runtime.configure(world, str(entry.get("landmark_id", "")), expedition_setup)
	_capture_host.add_child(runtime)
	_map.visible = false
	for _frame in range(RENDER_SETTLE_FRAMES):
		await process_frame
	var controller := runtime.get_node_or_null(
		"RuntimeDynamic/StructureRoots/%s/DynamicBodies/%sRuntime"
		% [TOWER_STRUCTURE_ID, TOWER_STRUCTURE_ID.to_pascal_case()]
	)
	if controller == null or not controller.has_method("activate_control"):
		_fail("Runtime capture could not find the mounted tower controller.")
		return false
	var tower_zoom := minf(
		float(CAPTURE_RESOLUTION.x) / tower_capture_rect.size.x,
		float(CAPTURE_RESOLUTION.y) / tower_capture_rect.size.y,
	)
	if not await _capture_frame(
		TOWER_RUNTIME_INITIAL_CAPTURE_FILE,
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
		TOWER_POWER_START_CAPTURE_FILE,
		"tower_runtime_power_start",
		start_positions,
		"",
		"",
		"ready",
		{"red": "ready", "blue": "locked", "yellow": "locked"},
		captures,
	):
		return false
	for lever_id: String in lever_ids:
		if not _activate_runtime_power_lever(controller, lever_id):
			return false
	if not await _capture_runtime_power_state(
		controller,
		TOWER_POWER_RED_ACTIVE_CAPTURE_FILE,
		"tower_runtime_power_red_active",
		red_positions,
		"red",
		"red",
		"active",
		{"red": "active", "blue": "locked", "yellow": "locked"},
		captures,
	):
		return false
	for lever_index: int in [0, 2]:
		if not _activate_runtime_power_lever(controller, lever_ids[lever_index]):
			return false
	if not await _capture_runtime_power_state(
		controller,
		TOWER_POWER_BLUE_LOCKED_CAPTURE_FILE,
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
		TOWER_RUNTIME_B_LATCH_CAPTURE_FILE,
		"tower_runtime_b_latched",
		"tower_b",
		captures,
	):
		return false
	for lever_index: int in [0, 2]:
		if not _activate_runtime_power_lever(controller, lever_ids[lever_index]):
			return false
	if not await _capture_runtime_power_state(
		controller,
		TOWER_POWER_BLUE_ACTIVE_CAPTURE_FILE,
		"tower_runtime_power_blue_active_after_b",
		blue_positions,
		"blue",
		"blue",
		"active",
		{"red": "latched", "blue": "active", "yellow": "locked"},
		captures,
	):
		return false
	if not await _await_runtime_elevator_progress(controller, 880.0):
		_fail("Runtime elevator did not reach the requested mid-travel capture position.")
		return false
	if not await _capture_frame(
		TOWER_RUNTIME_ELEVATOR_CAPTURE_FILE,
		"tower_runtime_elevator_mid",
		tower_capture_rect.get_center(),
		tower_zoom,
		captures,
	):
		return false
	if not await _await_runtime_elevator_stop(controller, "floor_7"):
		_fail("Runtime elevator did not reach floor_7 before the completed-state capture.")
		return false
	if not await _capture_runtime_detail(
		controller,
		TOWER_RUNTIME_C_CONTACT_CAPTURE_FILE,
		"tower_runtime_c_contact",
		"tower_c",
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
		TOWER_POWER_YELLOW_ACTIVE_CAPTURE_FILE,
		"tower_runtime_power_yellow_active_after_c",
		yellow_positions,
		"yellow",
		"yellow",
		"active",
		{"red": "latched", "blue": "latched", "yellow": "active"},
		captures,
	):
		return false
	if not await _capture_runtime_detail(
		controller,
		TOWER_RUNTIME_C_LATCH_CAPTURE_FILE,
		"tower_runtime_c_latched",
		"tower_c",
		captures,
	):
		return false
	if not _activate_runtime_power_lever(controller, lever_ids[2]):
		return false
	if not await _capture_runtime_power_state(
		controller,
		TOWER_POWER_FAULT_CAPTURE_FILE,
		"tower_runtime_power_invalid_fault",
		fault_positions,
		"",
		"",
		"fault",
		{"red": "latched", "blue": "latched", "yellow": "ready"},
		captures,
	):
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
	if not _activate_runtime_control_expect_failure(controller, "d_valve_v2"):
		return false
	if not await _capture_runtime_detail(
		controller,
		TOWER_RUNTIME_D_FAULT_CAPTURE_FILE,
		"tower_runtime_d_fault",
		"tower_d",
		captures,
	):
		return false
	if not _activate_runtime_control(controller, "d_reset"):
		return false
	if not await _capture_runtime_detail(
		controller,
		TOWER_RUNTIME_D_RESET_CAPTURE_FILE,
		"tower_runtime_d_reset",
		"tower_d",
		captures,
	):
		return false
	if not _activate_runtime_control(controller, "d_valve_v1"):
		return false
	if not await _capture_runtime_detail(
		controller,
		TOWER_RUNTIME_D_PRESSURE_CAPTURE_FILE,
		"tower_runtime_d_pressure",
		"tower_d",
		captures,
	):
		return false
	if not _activate_runtime_control(controller, "d_valve_v2"):
		return false
	if not await _capture_runtime_detail(
		controller,
		TOWER_RUNTIME_D_ACTUATOR_CAPTURE_FILE,
		"tower_runtime_d_actuator",
		"tower_d",
		captures,
	):
		return false
	if not _activate_runtime_control(controller, "d_valve_v3"):
		return false
	if not await _capture_runtime_detail(
		controller,
		TOWER_RUNTIME_D_RELEASE_CAPTURE_FILE,
		"tower_runtime_d_release",
		"tower_d",
		captures,
	):
		return false
	if not _activate_runtime_control(controller, "basement_hatch_control"):
		return false
	if not await _capture_runtime_detail(
		controller,
		TOWER_RUNTIME_ARCHIVE_CAPTURE_FILE,
		"tower_runtime_archive_open",
		"tower_basement",
		captures,
	):
		return false
	if not await _await_runtime_barriers_settle(controller):
		_fail("Runtime barriers did not reach their completed-state targets.")
		return false
	if not await _capture_frame(
		TOWER_RUNTIME_COMPLETE_CAPTURE_FILE,
		"tower_runtime_complete",
		tower_capture_rect.get_center(),
		tower_zoom,
		captures,
	):
		return false
	runtime.queue_free()
	_map.visible = true
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
) -> bool:
	var power_state := _validated_runtime_power_state(
		controller,
		kind,
		expected_lever_positions,
		expected_matched_circuit_id,
		expected_active_circuit_id,
		expected_power_status,
		expected_circuit_states,
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
) -> bool:
	if not await _capture_frame(
		file_name,
		capture_id,
		_tower_detail_position(detail_id),
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
		"d_progress": int(snapshot.get("d_progress", 0)),
		"d_requires_reset": bool(snapshot.get("d_requires_reset", false)),
		"d_complete": bool(snapshot.get("d_complete", false)),
		"basement_open": bool(snapshot.get("basement_open", false)),
		"attempt_complete": bool(snapshot.get("attempt_complete", false)),
	}
	return true


func _validated_runtime_power_state(
	controller: Node,
	state_label: String,
	expected_lever_positions: Dictionary,
	expected_matched_circuit_id: String,
	expected_active_circuit_id: String,
	expected_power_status: String,
	expected_circuit_states: Dictionary,
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


func _activate_runtime_control_expect_failure(controller: Node, control_id: String) -> bool:
	var result_value: Variant = controller.call("activate_control", control_id)
	var result: Dictionary = result_value as Dictionary if result_value is Dictionary else {}
	if bool(result.get("success", true)):
		_fail(
			"Runtime capture expected %s to enter a diagnostic fault: result=%s state=%s."
			% [control_id, result, controller.call("state_snapshot")]
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
		"tower_package": {
			"structure_scene_path": TOWER_PACKAGE_SCENE_PATH,
			"structure_scene_sha256": FileAccess.get_sha256(TOWER_PACKAGE_SCENE_PATH),
			"structure_texture_path": TOWER_STRUCTURE_TEXTURE_PATH,
			"structure_texture_sha256": FileAccess.get_sha256(TOWER_STRUCTURE_TEXTURE_PATH),
			"interior_texture_path": TOWER_INTERIOR_TEXTURE_PATH,
			"interior_texture_sha256": FileAccess.get_sha256(TOWER_INTERIOR_TEXTURE_PATH),
		},
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
