extends SceneTree

const PACKAGE_MANIFEST_PATH := "res://underwater_map_workbench/structures/tower_three_inlets_02/structure_manifest.json"
const PACKAGE_ROOT := "res://underwater_map_workbench/structures/tower_three_inlets_02/"
const GENERATED_SCENE_PATH := PACKAGE_ROOT + "generated/structure.tscn"
const STRUCTURE_ID := "tower_three_inlets_02"
const VIEWPORT_SIZE := Vector2i(1280, 720)
const STRUCTURE_SIZE := Vector2(2400.0, 3840.0)
const OUTPUT_DIR := "user://test_tower_three_inlets_02_proxy_capture"
const MAX_MOTION_FRAMES := 720
const CAPTURE_STEMS := [
	"01_s0_full",
	"02_s0_panel_a_and_b",
	"03_s1_after_b",
	"04_s2_after_c",
	"05_d_inlet_exposed",
	"06_s3_full",
	"07_s3_facade_egress",
]

var _package_manifest: Dictionary = {}
var _viewport: SubViewport
var _camera: Camera2D
var _structure_root: Node2D
var _controller
var _title_label: Label
var _state_label: Label
var _central_current_overlay: Node2D
var _b_current_overlays: Array[Node2D] = []
var _failed := false
var _written_capture_stems := {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_package_manifest = _load_json(PACKAGE_MANIFEST_PATH)
	if _package_manifest.is_empty():
		_finish()
		return
	if not _prepare_output_dir() or not _build_capture_scene():
		_finish()
		return
	await process_frame
	await RenderingServer.frame_post_draw

	await _capture("01_s0_full", "S0 — wejście przez uszkodzony balkon, A tylko informuje", STRUCTURE_SIZE * 0.5, _fit_zoom())
	await _capture("02_s0_panel_a_and_b", "S0 — panel A (read-only), osłona i wlot B", _focus_center(["panel_a", "inlet_b"]), Vector2(0.58, 0.58))

	var b_result: Dictionary = _controller.control("inlet_b").complete_dive_interaction()
	_assert(bool(b_result.get("success", false)), "Capture wymaga poprawnego przejścia B: %s." % b_result)
	_assert(str(_controller.state_snapshot().get("sequence_state", "")) == "S1", "Capture B musi osiągnąć S1 przed podpisaniem kadru.")
	await _await_barrier_target("g1")
	await _capture("03_s1_after_b", "S1 — B ukończone, G1 otwarte, centralny prąd = 2/3", _focus_center(["inlet_b", "g1"]), Vector2(0.50, 0.50))

	var c_result: Dictionary = _controller.control("inlet_c").complete_dive_interaction()
	_assert(bool(c_result.get("success", false)), "Capture wymaga poprawnego przejścia C: %s." % c_result)
	_assert(str(_controller.state_snapshot().get("sequence_state", "")) == "S2", "Capture C musi osiągnąć S2 przed podpisaniem kadru.")
	await _await_barrier_target("c_shortcut")
	await _await_barrier_target("g2")
	await _capture("04_s2_after_c", "S2 — C ukończone, skrót C i G2 otwarte, centralny prąd = 1/3", _focus_center(["inlet_c", "c_shortcut", "g2"]), Vector2(0.43, 0.43))

	var v1_result: Dictionary = _controller.control("d_v1").complete_dive_interaction()
	_assert(bool(v1_result.get("success", false)), "Capture wymaga poprawnej aktywacji V1: %s." % v1_result)
	await _await_cabinet_target()
	_assert(str(_controller.state_snapshot().get("d_state", "")) == "D_RIGHT_STOP", "Capture V1 musi osiągnąć D_RIGHT_STOP.")
	var v2_result: Dictionary = _controller.control("d_v2").complete_dive_interaction()
	_assert(bool(v2_result.get("success", false)), "Capture wymaga poprawnej aktywacji V2: %s." % v2_result)
	await _await_cabinet_target()
	_assert(str(_controller.state_snapshot().get("d_state", "")) == "D_INLET_EXPOSED", "Capture V2 musi osiągnąć D_INLET_EXPOSED.")
	await _capture("05_d_inlet_exposed", "S2 / D_INLET_EXPOSED — szafa w prawo i w dół, finalny wlot odsłonięty", _focus_center(["d_v1", "d_v2", "inlet_d"]), Vector2(0.64, 0.64))

	var d_result: Dictionary = _controller.control("inlet_d").complete_dive_interaction()
	_assert(bool(d_result.get("success", false)), "Capture wymaga poprawnego zamknięcia D: %s." % d_result)
	_assert(str(_controller.state_snapshot().get("sequence_state", "")) == "S3", "Capture D musi osiągnąć S3 przed podpisaniem kadru.")
	await _await_barrier_target("h3")
	await _await_barrier_target("facade")
	await _capture("06_s3_full", "S3 — B/C/D ukończone, prąd centralny wyłączony", STRUCTURE_SIZE * 0.5, _fit_zoom())
	await _capture("07_s3_facade_egress", "S3 — H3 i fasada otwarte; wyjście opuszcza budynek, nie kończy wyprawy", _focus_center(["h3", "facade"]), Vector2(0.56, 0.56))
	_verify_capture_set()
	_finish()


func _build_capture_scene() -> bool:
	_viewport = SubViewport.new()
	_viewport.name = "TowerThreeInletsCaptureViewport"
	_viewport.size = VIEWPORT_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	root.add_child(_viewport)

	var background_layer := CanvasLayer.new()
	background_layer.layer = -100
	_viewport.add_child(background_layer)
	var background := ColorRect.new()
	background.position = Vector2.ZERO
	background.size = Vector2(VIEWPORT_SIZE)
	background.color = Color("071a25")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_layer.add_child(background)

	var packed_scene := load(GENERATED_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Capture wymaga wygenerowanej prywatnej sceny: %s." % GENERATED_SCENE_PATH)
	if packed_scene == null:
		return false
	_structure_root = packed_scene.instantiate() as Node2D
	_assert(_structure_root != null, "Root wygenerowanej sceny W02 musi być Node2D.")
	if _structure_root == null:
		return false
	_structure_root.position = Vector2.ZERO
	_structure_root.scale = Vector2.ONE
	_viewport.add_child(_structure_root)

	var dynamic_bodies := _structure_root.get_node_or_null("DynamicBodies") as Node2D
	if dynamic_bodies == null:
		dynamic_bodies = Node2D.new()
		dynamic_bodies.name = "DynamicBodies"
		_structure_root.add_child(dynamic_bodies)
	var interactives := _structure_root.get_node_or_null("Interactives") as Node2D
	if interactives == null:
		interactives = Node2D.new()
		interactives.name = "Interactives"
		_structure_root.add_child(interactives)
	var controller_script := _controller_script()
	if controller_script == null:
		return false
	_controller = controller_script.new()
	_controller.name = "TowerThreeInletsCaptureController"
	dynamic_bodies.add_child(_controller)
	var errors = _controller.configure(_effective_structure_record(), interactives)
	_assert(errors.is_empty(), "Capture nie może skonfigurować controller W02: %s." % errors)
	if not errors.is_empty():
		return false

	_add_socket_overlay()
	_add_current_overlay()
	_camera = Camera2D.new()
	_camera.name = "CaptureCamera"
	_camera.enabled = true
	_camera.position = STRUCTURE_SIZE * 0.5
	_camera.zoom = _fit_zoom()
	_viewport.add_child(_camera)
	_build_hud()
	return true


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 100
	_viewport.add_child(hud)
	var top_panel := ColorRect.new()
	top_panel.position = Vector2(16.0, 14.0)
	top_panel.size = Vector2(1248.0, 92.0)
	top_panel.color = Color(0.01, 0.04, 0.06, 0.91)
	hud.add_child(top_panel)
	_title_label = Label.new()
	_title_label.position = Vector2(26.0, 20.0)
	_title_label.size = Vector2(1228.0, 34.0)
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color("d8f4ff"))
	top_panel.add_child(_title_label)
	_state_label = Label.new()
	_state_label.position = Vector2(26.0, 54.0)
	_state_label.size = Vector2(1228.0, 28.0)
	_state_label.add_theme_font_size_override("font_size", 16)
	_state_label.add_theme_color_override("font_color", Color("76d9e6"))
	top_panel.add_child(_state_label)

	var legend := Label.new()
	legend.position = Vector2(18.0, 666.0)
	legend.size = Vector2(1244.0, 36.0)
	legend.text = "ZIELONY: wejście  •  ŻÓŁTY: wyjście  •  CYJAN: interakcja  •  POMARAŃCZOWY: brama  •  FIOLET: szafa D  •  linie: prądy"
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	legend.add_theme_font_size_override("font_size", 15)
	legend.add_theme_color_override("font_color", Color("d7edf2"))
	legend.add_theme_color_override("font_outline_color", Color("001018"))
	legend.add_theme_constant_override("outline_size", 5)
	hud.add_child(legend)


func _add_socket_overlay() -> void:
	var overlay := Node2D.new()
	overlay.name = "SocketDiagnosticOverlay"
	overlay.z_index = 90
	_structure_root.add_child(overlay)
	for socket_value: Variant in _package_manifest.get("sockets", []) as Array:
		var socket := socket_value as Dictionary
		var rect := _rect2(socket.get("local_rect", []))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var kind := str(socket.get("kind", ""))
		var color := _socket_color(kind)
		var polygon := Polygon2D.new()
		polygon.polygon = PackedVector2Array([
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		])
		polygon.color = Color(color.r, color.g, color.b, 0.18)
		overlay.add_child(polygon)
		var border := Line2D.new()
		border.points = PackedVector2Array([
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
			rect.position,
		])
		border.width = 8.0
		border.default_color = color
		overlay.add_child(border)
		var label := Label.new()
		label.position = rect.position + Vector2(8.0, 4.0)
		label.text = str(socket.get("id", "?"))
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", color.lightened(0.25))
		label.add_theme_color_override("font_outline_color", Color("001018"))
		label.add_theme_constant_override("outline_size", 6)
		overlay.add_child(label)


func _add_current_overlay() -> void:
	var currents := (_package_manifest.get("runtime", {}) as Dictionary).get("currents", {}) as Dictionary
	var central := currents.get("central_shaft", {}) as Dictionary
	_central_current_overlay = _add_current_arrow(_socket_center(str(central.get("socket_id", ""))), _vector2(central.get("velocity", [])), Color("ff9d57"), "central")
	var b_current := currents.get("inlet_b", {}) as Dictionary
	_b_current_overlays.append(_add_current_arrow(_b_active_sample(b_current), _vector2(b_current.get("velocity", [])), Color("ff7657"), "B active"))
	_b_current_overlays.append(_add_current_arrow(_socket_center(str(b_current.get("recovery_socket_id", ""))), _vector2(b_current.get("recovery_velocity", [])), Color("68c6ff"), "B recovery"))


func _add_current_arrow(start: Vector2, vector: Vector2, color: Color, label_text: String) -> Node2D:
	var overlay := Node2D.new()
	overlay.name = label_text.to_pascal_case() + "CurrentOverlay"
	overlay.z_index = 95
	_structure_root.add_child(overlay)
	if vector.is_zero_approx():
		return overlay
	var scale_factor := 0.55
	var end := start + vector * scale_factor
	var line := Line2D.new()
	line.width = 14.0
	line.default_color = color
	line.points = PackedVector2Array([start, end])
	overlay.add_child(line)
	var direction := vector.normalized()
	var normal := Vector2(-direction.y, direction.x)
	var arrow := Polygon2D.new()
	arrow.z_index = 95
	arrow.polygon = PackedVector2Array([end, end - direction * 54.0 + normal * 28.0, end - direction * 54.0 - normal * 28.0])
	arrow.color = color
	overlay.add_child(arrow)
	var label := Label.new()
	label.z_index = 96
	label.position = start + Vector2(12.0, 12.0)
	label.text = label_text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color.lightened(0.2))
	label.add_theme_color_override("font_outline_color", Color("001018"))
	label.add_theme_constant_override("outline_size", 5)
	overlay.add_child(label)
	return overlay


func _capture(file_stem: String, title: String, camera_position: Vector2, camera_zoom: Vector2) -> void:
	_camera.position = camera_position
	_camera.zoom = camera_zoom
	_title_label.text = title
	var snapshot: Dictionary = _controller.state_snapshot()
	_refresh_current_overlays(snapshot)
	_state_label.text = "state=%s   D=%s   B/C/D=%s/%s/%s   central=%.3f   facade=%s" % [
		str(snapshot.get("sequence_state", "?")),
		str(snapshot.get("d_state", "?")),
		str(snapshot.get("b_complete", false)),
		str(snapshot.get("c_complete", false)),
		str(snapshot.get("d_complete", false)),
		float(snapshot.get("central_current_multiplier", -1.0)),
		str(_controller.barrier_is_open("facade")),
	]
	await process_frame
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	_assert(not image.is_empty(), "Capture %s nie może zwrócić pustego obrazu." % file_stem)
	_assert(Vector2i(image.get_width(), image.get_height()) == VIEWPORT_SIZE, "Capture %s musi mieć dokładnie 1280x720." % file_stem)
	var output_path := "%s/%s.png" % [OUTPUT_DIR, file_stem]
	var error := image.save_png(output_path)
	_assert(error == OK, "Nie można zapisać capture %s (error=%s)." % [output_path, error])
	if error == OK:
		_written_capture_stems[file_stem] = true
		print("W02 capture: %s" % ProjectSettings.globalize_path(output_path))


func _refresh_current_overlays(snapshot: Dictionary) -> void:
	if _central_current_overlay != null:
		_central_current_overlay.visible = float(snapshot.get("central_current_multiplier", 0.0)) > 0.0
	for overlay: Node2D in _b_current_overlays:
		overlay.visible = bool(snapshot.get("b_current_active", false))


func _focus_center(ids: Array) -> Vector2:
	var points: Array[Vector2] = []
	var runtime := _package_manifest.get("runtime", {}) as Dictionary
	for item_id_value: Variant in ids:
		var item_id := str(item_id_value)
		var socket_id := ""
		for interactive_value: Variant in runtime.get("interactives", []) as Array:
			var interactive := interactive_value as Dictionary
			if str(interactive.get("id", "")) == item_id:
				socket_id = str(interactive.get("socket_id", ""))
		for barrier_value: Variant in runtime.get("barriers", []) as Array:
			var barrier := barrier_value as Dictionary
			if str(barrier.get("id", "")) == item_id:
				socket_id = str(barrier.get("socket_id", ""))
		if socket_id.is_empty() and item_id == "facade":
			socket_id = str(runtime.get("egress_socket_id", ""))
		var socket := _socket_by_id(socket_id)
		if not socket.is_empty():
			var rect := _rect2(socket.get("local_rect", []))
			points.append(rect.get_center())
	if points.is_empty():
		return STRUCTURE_SIZE * 0.5
	var sum := Vector2.ZERO
	for point: Vector2 in points:
		sum += point
	return sum / float(points.size())


func _socket_by_id(socket_id: String) -> Dictionary:
	for socket_value: Variant in _package_manifest.get("sockets", []) as Array:
		var socket := socket_value as Dictionary
		if str(socket.get("id", "")) == socket_id:
			return socket
	return {}


func _socket_center(socket_id: String) -> Vector2:
	return _rect2(_socket_by_id(socket_id).get("local_rect", [])).get_center()


func _b_active_sample(b_current: Dictionary) -> Vector2:
	var main_rect := _rect2(_socket_by_id(str(b_current.get("socket_id", ""))).get("local_rect", []))
	var exclusions: Array[Rect2] = []
	for cover_socket_id: Variant in b_current.get("cover_socket_ids", []) as Array:
		exclusions.append(_rect2(_socket_by_id(str(cover_socket_id)).get("local_rect", [])))
	exclusions.append(_rect2(_socket_by_id(str(b_current.get("recovery_socket_id", ""))).get("local_rect", [])))
	for y: int in range(int(main_rect.position.y) + 20, int(main_rect.end.y), 40):
		for x: int in range(int(main_rect.position.x) + 20, int(main_rect.end.x), 40):
			var candidate := Vector2(float(x), float(y))
			var excluded := false
			for exclusion: Rect2 in exclusions:
				if exclusion.has_point(candidate):
					excluded = true
					break
			if not excluded:
				return candidate
	return main_rect.get_center()


func _socket_color(kind: String) -> Color:
	match kind:
		"entry_opening":
			return Color("66f09b")
		"building_egress":
			return Color("ffe66d")
		"dynamic_door":
			return Color("ff9d57")
		"moving_obstacle":
			return Color("d18cff")
		_:
			return Color("62d9e8")


func _fit_zoom() -> Vector2:
	var scale_value: float = minf(float(VIEWPORT_SIZE.x - 160) / STRUCTURE_SIZE.x, float(VIEWPORT_SIZE.y - 150) / STRUCTURE_SIZE.y)
	return Vector2.ONE * scale_value


func _await_barrier_target(barrier_id: String) -> void:
	for _frame: int in range(MAX_MOTION_FRAMES):
		if _controller.barrier_reached_target(barrier_id):
			return
		await physics_frame
	_assert(false, "Capture timeout bariery %s." % barrier_id)


func _await_cabinet_target() -> void:
	for _frame: int in range(MAX_MOTION_FRAMES):
		if _controller.cabinet_reached_target():
			return
		await physics_frame
	_assert(false, "Capture timeout cabinet_d.")


func _controller_script() -> Script:
	for script_value: Variant in _package_manifest.get("scripts", []) as Array:
		var script_record := script_value as Dictionary
		if str(script_record.get("role", "")) != "controller":
			continue
		var script := load(PACKAGE_ROOT + str(script_record.get("path", ""))) as Script
		_assert(script != null, "Nie można załadować controller script W02.")
		return script
	_assert(false, "Manifest W02 nie deklaruje controller script.")
	return null


func _effective_structure_record() -> Dictionary:
	var template := _package_manifest.get("template", {}) as Dictionary
	return {
		"id": STRUCTURE_ID,
		"template_id": str(template.get("id", "")),
		"size": (_package_manifest.get("size", []) as Array).duplicate(true),
		"sockets": (_package_manifest.get("sockets", []) as Array).duplicate(true),
		"runtime": (_package_manifest.get("runtime", {}) as Dictionary).duplicate(true),
	}


func _prepare_output_dir() -> bool:
	var absolute_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	var error := DirAccess.make_dir_recursive_absolute(absolute_path)
	_assert(error == OK or error == ERR_ALREADY_EXISTS, "Nie można utworzyć katalogu capture: %s." % absolute_path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return false
	for file_stem: String in CAPTURE_STEMS:
		var old_path := ProjectSettings.globalize_path("%s/%s.png" % [OUTPUT_DIR, file_stem])
		if FileAccess.file_exists(old_path):
			var remove_error := DirAccess.remove_absolute(old_path)
			_assert(remove_error == OK, "Nie można usunąć starego capture przed nowym przebiegiem: %s." % old_path)
	_written_capture_stems.clear()
	return not _failed


func _verify_capture_set() -> void:
	_assert(_written_capture_stems.size() == CAPTURE_STEMS.size(), "Bieżący przebieg musi zapisać dokładnie siedem nowych kadrów.")
	for file_stem: String in CAPTURE_STEMS:
		var output_path := "%s/%s.png" % [OUTPUT_DIR, file_stem]
		_assert(_written_capture_stems.has(file_stem), "Bieżący przebieg nie zapisał kadru %s." % file_stem)
		_assert(FileAccess.file_exists(output_path), "Brakuje świeżego pliku capture %s." % output_path)


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	_assert(file != null, "Nie można otworzyć JSON: %s." % path)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_assert(parsed is Dictionary, "Plik musi być obiektem JSON: %s." % path)
	return parsed as Dictionary if parsed is Dictionary else {}


func _vector2(value: Variant) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2.ZERO
	return Vector2(float((value as Array)[0]), float((value as Array)[1]))


func _rect2(value: Variant) -> Rect2:
	if not value is Array or (value as Array).size() != 4:
		return Rect2()
	return Rect2(float((value as Array)[0]), float((value as Array)[1]), float((value as Array)[2]), float((value as Array)[3]))


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("Tower three inlets proxy captures completed: %s" % ProjectSettings.globalize_path(OUTPUT_DIR))
	quit(0)
