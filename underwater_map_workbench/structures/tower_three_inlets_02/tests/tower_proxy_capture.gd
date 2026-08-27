extends SceneTree

const PACKAGE_MANIFEST_PATH := "res://underwater_map_workbench/structures/tower_three_inlets_02/structure_manifest.json"
const PACKAGE_ROOT := "res://underwater_map_workbench/structures/tower_three_inlets_02/"
const GENERATED_SCENE_PATH := PACKAGE_ROOT + "generated/structure.tscn"
const STRUCTURE_ID := "tower_three_inlets_02"
const VIEWPORT_SIZE := Vector2i(1280, 720)
const STRUCTURE_SIZE := Vector2(2400.0, 3840.0)
const OUTPUT_DIR := "user://test_tower_three_inlets_02_proxy_capture"
const FACADE_PROOF_PATH := OUTPUT_DIR + "/facade_aperture_proof.json"
const MAX_MOTION_FRAMES := 720
const RENAMED_FACADE_SOCKET_ID := "capture_typed_door_socket"
const RENAMED_EGRESS_SOCKET_ID := "capture_typed_ocean_socket"
const RENAMED_FACADE_LABEL := "neutralny element testowy"
const RENAMED_FACADE_SYMBOL := "?"
const CAPTURE_STEMS := [
	"01_s0_full",
	"02_facade_closed_probe",
	"03_s0_panel_a_and_b",
	"04_s1_after_b",
	"05_s2_after_c",
	"06_d_inlet_exposed",
	"07_facade_mid_probe",
	"08_s3_full",
	"09_facade_open_probe",
	"10_facade_open_clean",
]

var _package_manifest: Dictionary = {}
var _viewport: SubViewport
var _camera: Camera2D
var _structure_root: Node2D
var _controller
var _title_label: Label
var _state_label: Label
var _hud_layer: CanvasLayer
var _socket_diagnostic_overlay: Node2D
var _aperture_probe: Polygon2D
var _central_current_overlay: Node2D
var _b_current_overlays: Array[Node2D] = []
var _failed := false
var _written_capture_stems := {}
var _facade_phase_records := {}


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
	await _capture_facade_phase("02_facade_closed_probe", "CLOSED", true)
	await _capture("03_s0_panel_a_and_b", "S0 — panel A (read-only), osłona i wlot B", _focus_center(["panel_a", "inlet_b"]), Vector2(0.58, 0.58))

	var b_result: Dictionary = _controller.control("inlet_b").complete_dive_interaction()
	_assert(bool(b_result.get("success", false)), "Capture wymaga poprawnego przejścia B: %s." % b_result)
	_assert(str(_controller.state_snapshot().get("sequence_state", "")) == "S1", "Capture B musi osiągnąć S1 przed podpisaniem kadru.")
	await _await_barrier_target("g1")
	await _capture("04_s1_after_b", "S1 — B ukończone, G1 otwarte, centralny prąd = 2/3", _focus_center(["inlet_b", "g1"]), Vector2(0.50, 0.50))

	var c_result: Dictionary = _controller.control("inlet_c").complete_dive_interaction()
	_assert(bool(c_result.get("success", false)), "Capture wymaga poprawnego przejścia C: %s." % c_result)
	_assert(str(_controller.state_snapshot().get("sequence_state", "")) == "S2", "Capture C musi osiągnąć S2 przed podpisaniem kadru.")
	await _await_barrier_target("c_shortcut")
	await _await_barrier_target("g2")
	await _capture("05_s2_after_c", "S2 — C ukończone, skrót C i G2 otwarte, centralny prąd = 1/3", _focus_center(["inlet_c", "c_shortcut", "g2"]), Vector2(0.43, 0.43))

	var v1_result: Dictionary = _controller.control("d_v1").complete_dive_interaction()
	_assert(bool(v1_result.get("success", false)), "Capture wymaga poprawnej aktywacji V1: %s." % v1_result)
	await _await_cabinet_target()
	_assert(str(_controller.state_snapshot().get("d_state", "")) == "D_RIGHT_STOP", "Capture V1 musi osiągnąć D_RIGHT_STOP.")
	var v2_result: Dictionary = _controller.control("d_v2").complete_dive_interaction()
	_assert(bool(v2_result.get("success", false)), "Capture wymaga poprawnej aktywacji V2: %s." % v2_result)
	await _await_cabinet_target()
	_assert(str(_controller.state_snapshot().get("d_state", "")) == "D_INLET_EXPOSED", "Capture V2 musi osiągnąć D_INLET_EXPOSED.")
	await _capture("06_d_inlet_exposed", "S2 / D_INLET_EXPOSED — szafa w prawo i w dół, finalny wlot odsłonięty", _focus_center(["d_v1", "d_v2", "inlet_d"]), Vector2(0.64, 0.64))

	var d_result: Dictionary = _controller.control("inlet_d").complete_dive_interaction()
	_assert(bool(d_result.get("success", false)), "Capture wymaga poprawnego zamknięcia D: %s." % d_result)
	_assert(str(_controller.state_snapshot().get("sequence_state", "")) == "S3", "Capture D musi osiągnąć S3 przed podpisaniem kadru.")
	await _await_facade_mid_phase()
	await _capture_facade_phase("07_facade_mid_probe", "MID", true)
	await _await_barrier_target("h3")
	await _await_barrier_target("facade")
	await _capture("08_s3_full", "S3 — B/C/D ukończone, prąd centralny wyłączony", STRUCTURE_SIZE * 0.5, _fit_zoom())
	await _capture_facade_phase("09_facade_open_probe", "OPEN", true)
	await _capture_facade_phase("10_facade_open_clean", "OPEN", false)
	_verify_facade_proof()
	_write_facade_proof()
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
	_build_aperture_probe()

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
	var typed_facade := _facade_body() as AnimatableBody2D
	_assert(typed_facade != null, "Capture wymaga bariery wytypowanej relacją dynamic_door→building_egress.")
	if typed_facade != null:
		_assert(str(typed_facade.get_meta(&"socket_id", "")) == RENAMED_FACADE_SOCKET_ID, "Capture musi renderować egress po zmianie nazwy socketu.")
		_assert(str(typed_facade.get_meta(&"label", "")) == RENAMED_FACADE_LABEL, "Capture musi renderować egress po zmianie label.")
		_assert(str(typed_facade.get_meta(&"symbol", "")) == RENAMED_FACADE_SYMBOL, "Capture musi renderować egress po zmianie symbolu.")
		_assert(str(typed_facade.get_meta(&"visual_style", "")) == "egress_grille", "Typowana relacja musi nadal wybrać egress_grille po zmianie nazw.")

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


func _build_aperture_probe() -> void:
	var runtime := _package_manifest.get("runtime", {}) as Dictionary
	var egress_socket := _socket_by_id(str(runtime.get("egress_socket_id", "")))
	var aperture_rect := _rect2(egress_socket.get("local_rect", []))
	_assert(aperture_rect.size.x > 0.0 and aperture_rect.size.y > 0.0, "Capture wymaga prawidłowego building_egress dla probe.")
	_aperture_probe = Polygon2D.new()
	_aperture_probe.name = "FacadeApertureProbe"
	_aperture_probe.z_index = -40
	_aperture_probe.polygon = PackedVector2Array([
		aperture_rect.position,
		Vector2(aperture_rect.end.x, aperture_rect.position.y),
		aperture_rect.end,
		Vector2(aperture_rect.position.x, aperture_rect.end.y),
	])
	_aperture_probe.color = Color(0.92, 0.04, 0.88, 1.0)
	_aperture_probe.visible = false
	_structure_root.add_child(_aperture_probe)


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 100
	_viewport.add_child(_hud_layer)
	var top_panel := ColorRect.new()
	top_panel.position = Vector2(16.0, 14.0)
	top_panel.size = Vector2(1248.0, 92.0)
	top_panel.color = Color(0.01, 0.04, 0.06, 0.91)
	_hud_layer.add_child(top_panel)
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
	_hud_layer.add_child(legend)


func _add_socket_overlay() -> void:
	_socket_diagnostic_overlay = Node2D.new()
	_socket_diagnostic_overlay.name = "SocketDiagnosticOverlay"
	_socket_diagnostic_overlay.z_index = 90
	_structure_root.add_child(_socket_diagnostic_overlay)
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
		_socket_diagnostic_overlay.add_child(polygon)
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
		_socket_diagnostic_overlay.add_child(border)
		var label := Label.new()
		label.position = rect.position + Vector2(8.0, 4.0)
		label.text = str(socket.get("id", "?"))
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", color.lightened(0.25))
		label.add_theme_color_override("font_outline_color", Color("001018"))
		label.add_theme_constant_override("outline_size", 6)
		_socket_diagnostic_overlay.add_child(label)


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


func _capture(file_stem: String, title: String, camera_position: Vector2, camera_zoom: Vector2) -> Image:
	_camera.position = camera_position
	_camera.zoom = camera_zoom
	_title_label.text = title
	var snapshot: Dictionary = _controller.state_snapshot()
	_refresh_current_overlays(snapshot)
	if _hud_layer != null and not _hud_layer.visible:
		if _central_current_overlay != null:
			_central_current_overlay.visible = false
		for overlay: Node2D in _b_current_overlays:
			overlay.visible = false
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
	return image


func _capture_facade_phase(file_stem: String, expected_state: String, show_probe: bool) -> void:
	var facade := _facade_body() as AnimatableBody2D
	_assert(facade != null, "Capture fazy %s wymaga ruchomego egress_grille." % expected_state)
	if facade == null:
		return
	var was_processing: bool = _controller.is_physics_processing()
	_controller.set_physics_process(false)
	_set_capture_chrome_visible(false)
	_aperture_probe.visible = show_probe
	facade.queue_redraw()
	var title := "FASADA %s — CLOSED→MID→OPEN / clear aperture" % expected_state
	var image: Image = await _capture(file_stem, title, _focus_center(["facade"]), Vector2(1.2, 1.2))
	var aperture_rect: Rect2 = facade.call(&"aperture_rect_in_parent")
	var body_rect: Rect2 = facade.call(&"body_rect_in_parent")
	var overlap_ratio := _rect_overlap_ratio(body_rect, aperture_rect)
	var probe_ratio := _probe_pixel_ratio(image, aperture_rect) if show_probe else -1.0
	var output_path := "%s/%s.png" % [OUTPUT_DIR, file_stem]
	var record := {
		"phase": expected_state,
		"visual_style": str(facade.call(&"visual_style")),
		"visual_state": str(facade.call(&"visual_state")),
		"commanded_open": _controller.barrier_is_commanded_open("facade"),
		"open": _controller.barrier_is_open("facade"),
		"reached_target": _controller.barrier_reached_target("facade"),
		"open_progress": float(facade.call(&"open_progress")),
		"aperture_clear_fraction": float(facade.call(&"aperture_clear_fraction")),
		"body_aperture_overlap_ratio": overlap_ratio,
		"probe_visible": show_probe,
		"probe_open_water_pixel_ratio": probe_ratio,
		"body_rect": _rect_to_array(body_rect),
		"aperture_rect": _rect_to_array(aperture_rect),
		"png_path": output_path,
		"png_sha256": FileAccess.get_sha256(output_path),
	}
	_facade_phase_records[file_stem] = record
	_assert(str(record.get("visual_style", "")) == "egress_grille", "Capture fasady musi używać typowanego egress_grille.")
	_assert(str(record.get("visual_state", "")) == expected_state, "Capture %s oczekiwał fazy %s: %s." % [file_stem, expected_state, record])
	_aperture_probe.visible = false
	_set_capture_chrome_visible(true)
	_controller.set_physics_process(was_processing)


func _set_capture_chrome_visible(visible: bool) -> void:
	if _hud_layer != null:
		_hud_layer.visible = visible
	if _socket_diagnostic_overlay != null:
		_socket_diagnostic_overlay.visible = visible
	if _central_current_overlay != null:
		_central_current_overlay.visible = visible
	for overlay: Node2D in _b_current_overlays:
		overlay.visible = visible


func _probe_pixel_ratio(image: Image, aperture_rect: Rect2) -> float:
	if image.is_empty():
		return 0.0
	var canvas_transform := _structure_root.get_global_transform_with_canvas()
	var screen_a := canvas_transform * aperture_rect.position
	var screen_b := canvas_transform * aperture_rect.end
	var screen_min := Vector2(minf(screen_a.x, screen_b.x), minf(screen_a.y, screen_b.y))
	var screen_max := Vector2(maxf(screen_a.x, screen_b.x), maxf(screen_a.y, screen_b.y))
	var margin := maxi(int(round(10.0 * maxf(_camera.zoom.x, _camera.zoom.y))), 2)
	var x_start := clampi(int(ceil(screen_min.x)) + margin, 0, image.get_width() - 1)
	var x_end := clampi(int(floor(screen_max.x)) - margin, x_start + 1, image.get_width())
	var y_start := clampi(int(ceil(screen_min.y)) + margin, 0, image.get_height() - 1)
	var y_end := clampi(int(floor(screen_max.y)) - margin, y_start + 1, image.get_height())
	var sample_count := 0
	var probe_count := 0
	for y: int in range(y_start, y_end, 2):
		for x: int in range(x_start, x_end, 2):
			var pixel := image.get_pixel(x, y)
			sample_count += 1
			if pixel.r > 0.55 and pixel.b > 0.50 and pixel.g < 0.25:
				probe_count += 1
	_assert(sample_count > 0, "Capture fasady musi mieć niepustą siatkę próbek apertury.")
	return float(probe_count) / float(maxi(sample_count, 1))


func _rect_overlap_ratio(body_rect: Rect2, aperture_rect: Rect2) -> float:
	if aperture_rect.size.x <= 0.0 or aperture_rect.size.y <= 0.0:
		return 0.0
	var overlap := body_rect.intersection(aperture_rect)
	return clampf(
		(overlap.size.x * overlap.size.y) / (aperture_rect.size.x * aperture_rect.size.y),
		0.0,
		1.0
	)


func _rect_to_array(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


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


func _await_facade_mid_phase() -> void:
	var facade := _facade_body() as AnimatableBody2D
	_assert(facade != null, "Capture MID wymaga ruchomego egress_grille.")
	if facade == null:
		return
	for _frame: int in range(MAX_MOTION_FRAMES):
		var clear_fraction := float(facade.call(&"aperture_clear_fraction"))
		if clear_fraction >= 0.45 and clear_fraction <= 0.65:
			_assert(str(facade.call(&"visual_state")) == "MID", "Częściowo odsłonięta fasada musi publikować MID.")
			_assert(_controller.barrier_is_commanded_open("facade") and not _controller.barrier_is_open("facade") and not _controller.barrier_reached_target("facade"), "MID musi być commanded, lecz jeszcze nie OPEN/reached.")
			return
		await physics_frame
	_assert(false, "Capture nie osiągnął stabilnego okna MID egress_grille.")


func _await_cabinet_target() -> void:
	for _frame: int in range(MAX_MOTION_FRAMES):
		if _controller.cabinet_reached_target():
			return
		await physics_frame
	_assert(false, "Capture timeout cabinet_d.")


func _facade_body():
	for body_value: Variant in _controller.find_children("*", "AnimatableBody2D", true, false):
		var body := body_value as AnimatableBody2D
		if str(body.get_meta(&"visual_style", "")) == "egress_grille":
			return body
	return null


func _verify_facade_proof() -> void:
	var closed := _facade_phase_records.get("02_facade_closed_probe", {}) as Dictionary
	var mid := _facade_phase_records.get("07_facade_mid_probe", {}) as Dictionary
	var open_probe := _facade_phase_records.get("09_facade_open_probe", {}) as Dictionary
	var open_clean := _facade_phase_records.get("10_facade_open_clean", {}) as Dictionary
	_assert(not closed.is_empty() and not mid.is_empty() and not open_probe.is_empty() and not open_clean.is_empty(), "Capture musi zapisać komplet CLOSED/MID/OPEN probe oraz OPEN clean.")
	if closed.is_empty() or mid.is_empty() or open_probe.is_empty() or open_clean.is_empty():
		return
	var closed_clear := float(closed.get("aperture_clear_fraction", -1.0))
	var mid_clear := float(mid.get("aperture_clear_fraction", -1.0))
	var open_clear := float(open_probe.get("aperture_clear_fraction", -1.0))
	_assert(is_zero_approx(closed_clear), "CLOSED musi zaczynać od clear_fraction=0.")
	_assert(closed_clear < mid_clear and mid_clear < open_clear, "Clear aperture musi rosnąć ściśle monotonicznie CLOSED→MID→OPEN.")
	_assert(is_equal_approx(open_clear, 1.0), "OPEN musi osiągnąć clear_fraction=1.")
	var closed_overlap := float(closed.get("body_aperture_overlap_ratio", -1.0))
	var mid_overlap := float(mid.get("body_aperture_overlap_ratio", -1.0))
	var open_overlap := float(open_probe.get("body_aperture_overlap_ratio", -1.0))
	_assert(is_equal_approx(closed_overlap, 1.0), "CLOSED collider musi wypełniać cały egress.")
	_assert(closed_overlap > mid_overlap and mid_overlap > open_overlap, "Overlap collidera musi maleć ściśle CLOSED→MID→OPEN.")
	_assert(is_zero_approx(open_overlap), "OPEN collider nie może przecinać egressu.")
	var closed_probe := float(closed.get("probe_open_water_pixel_ratio", -1.0))
	var mid_probe := float(mid.get("probe_open_water_pixel_ratio", -1.0))
	var open_probe_ratio := float(open_probe.get("probe_open_water_pixel_ratio", -1.0))
	_assert(closed_probe >= 0.05, "CLOSED egress_grille musi pozostać wizualnie przepuszczalną kratownicą także po zmianie ID/socket/label/symbol.")
	_assert(closed_probe + 0.01 < mid_probe and mid_probe + 0.01 < open_probe_ratio, "Widoczny probe open-water musi rosnąć monotonicznie w renderze CLOSED→MID→OPEN.")
	_assert(open_probe_ratio >= 0.90, "OPEN musi ujawnić co najmniej 0,90 próbek pustej apertury; jest %.3f." % open_probe_ratio)
	_assert(not bool(open_clean.get("probe_visible", true)), "Końcowy OPEN clean nie może zawierać probe ani diagnostycznego panelu.")


func _write_facade_proof() -> void:
	var ordered_records: Array[Dictionary] = []
	for stem: String in ["02_facade_closed_probe", "07_facade_mid_probe", "09_facade_open_probe", "10_facade_open_clean"]:
		ordered_records.append((_facade_phase_records.get(stem, {}) as Dictionary).duplicate(true))
	var payload := {
		"schema_version": 1,
		"kind": "tower_three_inlets_02_facade_aperture_proof",
		"package_manifest_sha256": FileAccess.get_sha256(PACKAGE_MANIFEST_PATH),
		"reads_map_manifest": false,
		"reads_underwater_map_scene": false,
		"typed_fixture": {
			"facade_socket_id": RENAMED_FACADE_SOCKET_ID,
			"egress_socket_id": RENAMED_EGRESS_SOCKET_ID,
			"label": RENAMED_FACADE_LABEL,
			"symbol": RENAMED_FACADE_SYMBOL,
			"resolved_visual_style": "egress_grille",
		},
		"records": ordered_records,
	}
	var file := FileAccess.open(FACADE_PROOF_PATH, FileAccess.WRITE)
	_assert(file != null, "Nie można zapisać facade_aperture_proof.json.")
	if file == null:
		return
	file.store_string(JSON.stringify(payload, "\t") + "\n")
	file.close()
	_assert(FileAccess.file_exists(FACADE_PROOF_PATH), "Brakuje świeżego facade_aperture_proof.json.")


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
	var sockets := (_package_manifest.get("sockets", []) as Array).duplicate(true)
	var runtime := (_package_manifest.get("runtime", {}) as Dictionary).duplicate(true)
	var egress_socket_id := str(runtime.get("egress_socket_id", ""))
	var egress_socket := _record_by_id(sockets, egress_socket_id)
	var egress_rect := _rect_from_value(egress_socket.get("local_rect", []))
	var barriers := runtime.get("barriers", []) as Array
	var typed_barrier: Dictionary = {}
	var typed_barrier_socket_id := ""
	for barrier_value: Variant in barriers:
		var barrier := barrier_value as Dictionary
		var barrier_socket_id := str(barrier.get("socket_id", ""))
		var barrier_socket := _record_by_id(sockets, barrier_socket_id)
		if (
			str(barrier_socket.get("kind", "")) == "dynamic_door"
			and _rect_from_value(barrier_socket.get("local_rect", [])) == egress_rect
		):
			typed_barrier = barrier
			typed_barrier_socket_id = barrier_socket_id
			break
	_assert(not typed_barrier.is_empty(), "Capture musi wyprowadzić egress_grille z relacji dynamic_door→building_egress.")
	for socket_value: Variant in sockets:
		var socket := socket_value as Dictionary
		var socket_id := str(socket.get("id", ""))
		if socket_id == typed_barrier_socket_id:
			socket["id"] = RENAMED_FACADE_SOCKET_ID
		elif socket_id == egress_socket_id:
			socket["id"] = RENAMED_EGRESS_SOCKET_ID
	if not typed_barrier.is_empty():
		typed_barrier["socket_id"] = RENAMED_FACADE_SOCKET_ID
		typed_barrier["label"] = RENAMED_FACADE_LABEL
		typed_barrier["symbol"] = RENAMED_FACADE_SYMBOL
	runtime["egress_socket_id"] = RENAMED_EGRESS_SOCKET_ID
	return {
		"id": STRUCTURE_ID,
		"template_id": str(template.get("id", "")),
		"size": (_package_manifest.get("size", []) as Array).duplicate(true),
		"sockets": sockets,
		"runtime": runtime,
	}


func _record_by_id(records: Array, record_id: String) -> Dictionary:
	for record_value: Variant in records:
		var record := record_value as Dictionary
		if str(record.get("id", "")) == record_id:
			return record
	return {}


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
	var old_proof_path := ProjectSettings.globalize_path(FACADE_PROOF_PATH)
	if FileAccess.file_exists(old_proof_path):
		var proof_remove_error := DirAccess.remove_absolute(old_proof_path)
		_assert(proof_remove_error == OK, "Nie można usunąć starego facade_aperture_proof.json.")
	_written_capture_stems.clear()
	_facade_phase_records.clear()
	return not _failed


func _verify_capture_set() -> void:
	_assert(_written_capture_stems.size() == CAPTURE_STEMS.size(), "Bieżący przebieg musi zapisać dokładnie %d nowych kadrów." % CAPTURE_STEMS.size())
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
