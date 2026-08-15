extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const WeatherStateScript := preload("res://scripts/data/WeatherState.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")

const CAPTURE_RESOLUTION := Vector2i(1280, 720)
const CAPTURE_FPS := 60
const MOVIE_WARMUP_FRAME := 300
const DEFAULT_DURATION_SECONDS := 10.0
const DAY_ONE_CAMPAIGN_SEED := 4_214
const SHARED_WIND := Vector2(0.76, 0.65)
const TOPDOWN_CAMERA_POSITION := Vector3(0.0, 60.0, 0.0)
const TOPDOWN_CAMERA_TARGET := Vector3(0.0, 0.0, 0.0)
const TOPDOWN_CAMERA_UP := Vector3(0.0, 0.0, -1.0)
const TOPDOWN_CAMERA_SIZE := 52.0
const BUILDING_SLOTS := {
	"fishing_hut": "top_left",
	"kitchen": "top_center",
	"community_house": "top_right",
	"workshop": "bottom_left",
	"infirmary": "center",
	"diving_station": "bottom_right",
}


func _ready() -> void:
	get_viewport().gui_disable_input = true
	var options := _parse_options(OS.get_cmdline_user_args())
	var case_id := str(options.get("case", "storm_high"))
	var duration_seconds := maxf(float(options.get("duration", DEFAULT_DURATION_SECONDS)), 2.0)
	var case_config := _case_config(case_id)
	if case_config.is_empty():
		_fail("Unknown ocean motion capture case: %s" % case_id)
		return
	var wind_option := _parse_wind_option(options)
	if not bool(wind_option.get("ok", false)):
		_fail(str(wind_option.get("error", "Invalid --wind option.")))
		return
	var wind_direction := Vector2(wind_option.get("direction", SHARED_WIND.normalized()))
	var scattering_mode := str(options.get("scattering", "production")).strip_edges().to_lower()
	if scattering_mode not in ["production", "on", "off"]:
		_fail("--scattering must be 'production', 'on' or 'off', got: %s" % scattering_mode)
		return
	var camera_mode := str(options.get("camera", "production")).strip_edges().to_lower()
	if camera_mode not in ["production", "topdown"]:
		_fail("--camera must be 'production' or 'topdown', got: %s" % camera_mode)
		return

	var curtain := _build_curtain()
	var game = GameRootScene.instantiate()
	add_child(game)
	add_child(curtain)
	await get_tree().process_frame
	if not await _configure_native_runtime(game, str(case_config.quality)):
		return
	if not game.start_new_campaign("standard", DAY_ONE_CAMPAIGN_SEED, false, false):
		_fail("Ocean motion capture could not start the real standard campaign flow.")
		return
	for _frame in range(3):
		await get_tree().process_frame

	var state = game.game_state
	var base = game.current_scene
	if not _validate_runtime(state, base):
		_fail("Ocean motion capture must use the real GameRoot -> BaseScene flow.")
		return
	var capture_weather = _weather_for(str(case_config.weather))
	capture_weather.wind_direction = wind_direction
	capture_weather.ensure_compatibility(1)
	state.weather = capture_weather
	if case_config.has("rain_intensity"):
		state.weather.rain_intensity = clampf(float(case_config.rain_intensity), 0.0, 1.0)
	if case_config.has("buildings_level"):
		_set_all_buildings(state, clampi(int(case_config.buildings_level), 1, 4))
	base.bind(game, state)
	base.set_graphics_quality(str(case_config.quality))
	_seed_particles(base)
	base.set_animation_time_for_tests(0.0)
	_apply_audit_overrides(base, case_config)
	if not _apply_directional_audit_options(base, scattering_mode, camera_mode):
		return

	# Movie Maker records startup as well. Keep it black while the real scene,
	# shaders and temporal effects warm up, then begin every case from phase zero.
	# The resulting MP4 is trimmed at the first non-black frame.
	if OS.has_feature("movie"):
		while Engine.get_process_frames() < MOVIE_WARMUP_FRAME:
			await get_tree().process_frame
	else:
		var realtime_warmup := 0.0
		while realtime_warmup < 3.0:
			await get_tree().process_frame
			realtime_warmup += get_process_delta_time()

	_restart_looping_particles(base)
	var environment = base.get("_environment")
	if environment == null:
		_fail("BaseScene did not expose its built BaseEnvironment to the audit harness.")
		return
	environment.set("_elapsed", 0.0)
	base.set_animation_time_for_tests(0.0)
	await RenderingServer.frame_post_draw
	environment.set("_elapsed", 0.0)
	base.clear_animation_time_override()
	if camera_mode == "topdown":
		_configure_topdown_camera(environment.world_3d.camera as Camera3D)
	if not _validate_and_print_rain_particle_diagnostics(
		environment.world_3d,
		float(state.weather.rain_intensity) > 0.025
	):
		return
	curtain.visible = false
	print(
		"OCEAN_CAPTURE_START case=%s quality=%s movie=%s process_frame=%d duration=%.2f wind_x=%.6f wind_z=%.6f scattering=%s camera=%s"
		% [
			case_id,
			str(case_config.quality),
			str(OS.has_feature("movie")),
			Engine.get_process_frames(),
			duration_seconds,
			wind_direction.x,
			wind_direction.y,
			scattering_mode,
			camera_mode,
		]
	)

	if OS.has_feature("movie"):
		await _run_movie_frames(roundi(duration_seconds * CAPTURE_FPS))
	else:
		await _run_realtime_profile(
			duration_seconds,
			case_id,
			str(case_config.quality),
			environment,
			wind_direction,
			scattering_mode,
			camera_mode
		)
	get_tree().quit(0)


func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var result := {}
	for argument in arguments:
		var text := str(argument)
		if not text.begins_with("--") or not text.contains("="):
			continue
		var separator := text.find("=")
		result[text.substr(2, separator - 2)] = text.substr(separator + 1)
	return result


func _parse_wind_option(options: Dictionary) -> Dictionary:
	if not options.has("wind"):
		return {"ok": true, "direction": SHARED_WIND.normalized(), "overridden": false}
	var raw_value := str(options.get("wind", "")).strip_edges()
	var components := raw_value.split(",", false)
	if components.size() != 2:
		return {
			"ok": false,
			"error": "--wind must use two comma-separated world-XZ components, for example --wind=0.76,0.65.",
		}
	var x_text := str(components[0]).strip_edges()
	var z_text := str(components[1]).strip_edges()
	if not x_text.is_valid_float() or not z_text.is_valid_float():
		return {
			"ok": false,
			"error": "--wind components must be finite numbers, got: %s" % raw_value,
		}
	var direction := Vector2(x_text.to_float(), z_text.to_float())
	if not is_finite(direction.x) or not is_finite(direction.y):
		return {
			"ok": false,
			"error": "--wind components must be finite numbers, got: %s" % raw_value,
		}
	if direction.length_squared() < 0.001:
		return {
			"ok": false,
			"error": "--wind cannot be a zero-length direction.",
		}
	return {"ok": true, "direction": direction.normalized(), "overridden": true}


func _case_config(case_id: String) -> Dictionary:
	match case_id:
		"calm_high":
			return {"quality": "high", "weather": "calm"}
		"moderate_high":
			return {"quality": "high", "weather": "moderate"}
		"rough_high":
			return {"quality": "high", "weather": "rough"}
		"storm_high":
			return {"quality": "high", "weather": "storm"}
		"storm_high_built":
			return {"quality": "high", "weather": "storm", "buildings_level": 4}
		"storm_high_built_clean":
			return {"quality": "high", "weather": "storm", "buildings_level": 4, "clean_view": true}
		"storm_medium":
			return {"quality": "medium", "weather": "storm"}
		"storm_low":
			return {"quality": "low", "weather": "storm"}
		"storm_high_ssr_off":
			return {"quality": "high", "weather": "storm", "ssr_enabled": false}
		"storm_high_taa":
			return {"quality": "high", "weather": "storm", "taa_enabled": true}
		"rough_high_no_rain":
			return {"quality": "high", "weather": "rough", "rain_intensity": 0.0}
		"storm_high_no_rain":
			return {"quality": "high", "weather": "storm", "rain_intensity": 0.0}
		"calm_high_no_rain":
			return {"quality": "high", "weather": "calm", "rain_intensity": 0.0}
		"moderate_high_no_rain":
			return {"quality": "high", "weather": "moderate", "rain_intensity": 0.0}
		"storm_medium_no_rain":
			return {"quality": "medium", "weather": "storm", "rain_intensity": 0.0}
		"storm_low_no_rain":
			return {"quality": "low", "weather": "storm", "rain_intensity": 0.0}
		"calm_high_clean":
			return {"quality": "high", "weather": "calm", "rain_intensity": 0.0, "clean_view": true}
		"moderate_high_clean":
			return {"quality": "high", "weather": "moderate", "rain_intensity": 0.0, "clean_view": true}
		"rough_high_clean":
			return {"quality": "high", "weather": "rough", "rain_intensity": 0.0, "clean_view": true}
		"storm_high_clean":
			return {"quality": "high", "weather": "storm", "rain_intensity": 0.0, "clean_view": true}
		"storm_medium_clean":
			return {"quality": "medium", "weather": "storm", "rain_intensity": 0.0, "clean_view": true}
		"storm_low_clean":
			return {"quality": "low", "weather": "storm", "rain_intensity": 0.0, "clean_view": true}
		_:
			return {}


func _set_all_buildings(state, level: int) -> void:
	state.buildings.clear()
	for slot_id in state.platform.slot_states.keys():
		var empty_slot: Dictionary = state.platform.slot_states[slot_id]
		empty_slot["building_id"] = ""
		state.platform.slot_states[slot_id] = empty_slot
	for definition_id in BUILDING_SLOTS.keys():
		var building = BuildingStateScript.new()
		building.id = "capture_%s" % definition_id
		building.definition_id = definition_id
		building.slot_id = BUILDING_SLOTS[definition_id]
		building.level = level
		building.is_built = true
		state.buildings.append(building)
		var slot_data: Dictionary = state.platform.slot_states[building.slot_id]
		slot_data["building_id"] = building.id
		state.platform.slot_states[building.slot_id] = slot_data


func _validate_and_print_rain_particle_diagnostics(world: Node, expects_contacts: bool) -> bool:
	if world == null:
		_fail("Rain diagnostics require the production BaseWorld3D.")
		return false
	var values := PackedStringArray()
	var valid := true
	for node_name in ["RainVolume3D", "RainNear3D", "RainContactImpacts3D", "RainNearContactImpacts3D"]:
		var particles := world.get_node_or_null(node_name) as GPUParticles3D
		if particles == null:
			values.append("%s=missing" % node_name)
			valid = false
			continue
		var captured_aabb := particles.capture_aabb()
		values.append(
			"%s_aabb=%s_visible=%s_emitting=%s"
			% [node_name, str(captured_aabb), str(particles.visible), str(particles.emitting)]
		)
		if expects_contacts and node_name.contains("ContactImpacts"):
			# capture_aabb() grows even an empty pool by the draw mesh radius. A
			# spread above one metre is therefore the conservative signal that this
			# particular parent actually delivered collision events during warm-up.
			if particles.emitting or maxf(captured_aabb.size.x, captured_aabb.size.z) <= 1.0:
				valid = false
	print("RAIN_CAPTURE_DIAGNOSTICS %s" % " ".join(values))
	if not valid:
		_fail("Rain capture did not observe independent dormant mid/near contact pools after native Forward+ warm-up.")
	return valid


func _weather_for(condition_id: String):
	match condition_id:
		"calm":
			return _profile(WeatherStateScript.Condition.CALM, 0.31, 0.34, 0.31, 0.20, 0.10, 0.72)
		"rough":
			return _profile(WeatherStateScript.Condition.ROUGH, 0.78, 0.70, 0.84, 0.72, 0.68, 1.10)
		"storm":
			return _profile(WeatherStateScript.Condition.STORM, 1.00, 1.00, 1.16, 1.00, 1.00, 1.34)
		_:
			return _profile(WeatherStateScript.Condition.MODERATE, 0.56, 0.52, 0.58, 0.46, 0.38, 0.90)


func _profile(condition: int, sea: float, rain: float, motion: float, foam: float, splash: float, speed: float):
	var weather = WeatherStateScript.new()
	weather.day = 1
	weather.condition = condition
	weather.sea_intensity = sea
	weather.rain_intensity = rain
	weather.motion_intensity = motion
	weather.foam_intensity = foam
	weather.splash_intensity = splash
	weather.wave_speed_multiplier = speed
	weather.wind_direction = SHARED_WIND
	weather.ensure_compatibility(1)
	return weather


func _configure_native_runtime(game: Node, quality: String) -> bool:
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		_fail("Ocean motion capture requires a native, non-headless Godot window.")
		return false
	var settings: Dictionary = game.user_settings.snapshot()
	var display: Dictionary = settings.get("display", {}).duplicate(true)
	display["mode"] = "windowed"
	display["resolution"] = CAPTURE_RESOLUTION
	display["vsync"] = false
	display["max_fps"] = 0
	settings["display"] = display
	settings["graphics"] = {"quality": quality}
	var general: Dictionary = settings.get("general", {}).duplicate(true)
	general["pause_on_focus_loss"] = false
	settings["general"] = general
	if game.user_settings.apply(settings, false) != OK:
		_fail("Ocean motion capture could not apply native capture settings.")
		return false
	for _frame in range(30):
		await get_tree().process_frame
		if get_viewport().get_texture().get_size() == Vector2(CAPTURE_RESOLUTION):
			return true
	_fail(
		"Ocean motion capture requires a %dx%d render target, got %s."
		% [CAPTURE_RESOLUTION.x, CAPTURE_RESOLUTION.y, str(get_viewport().get_texture().get_size())]
	)
	return false


func _validate_runtime(state, base: Node) -> bool:
	if state == null or base == null or base.name != "BaseScene":
		return false
	return int(state.day) == 1 and state.tutorial != null and state.tutorial.is_active()


func _build_curtain() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "CaptureWarmupCurtain"
	layer.layer = 4_096
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color.BLACK
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	return layer


func _seed_particles(root: Node) -> void:
	var particle_index := 0
	for particle_node in root.find_children("*", "GPUParticles3D", true, false):
		var particles := particle_node as GPUParticles3D
		particles.use_fixed_seed = true
		particles.seed = 73_251 + particle_index * 977
		particles.preprocess = 0.0
		particle_index += 1


func _restart_looping_particles(root: Node) -> void:
	for particle_node in root.find_children("*", "GPUParticles3D", true, false):
		var particles := particle_node as GPUParticles3D
		# Dormant subemitters must remain dormant: restart(true) flips `emitting`
		# and would turn collision-only impact pools into autonomous origin emitters.
		if not particles.one_shot and particles.emitting:
			particles.restart(true)


func _apply_audit_overrides(base: Node, case_config: Dictionary) -> void:
	var environment = base.get("_environment")
	if environment == null:
		return
	if bool(case_config.get("clean_view", false)):
		var hud_canvas = base.get("_hud_canvas")
		if hud_canvas != null:
			hud_canvas.visible = false
		var slot_layer = base.get("_slot_layer")
		if slot_layer != null:
			slot_layer.visible = false
	if bool(case_config.get("taa_enabled", false)):
		environment.world_viewport.use_taa = true
	if case_config.has("ssr_enabled") and environment.world_3d != null:
		var rendering_environment = environment.world_3d.get("_environment")
		if rendering_environment != null:
			rendering_environment.ssr_enabled = bool(case_config.ssr_enabled)


func _apply_directional_audit_options(base: Node, scattering_mode: String, camera_mode: String) -> bool:
	var environment = base.get("_environment")
	if environment == null or environment.world_3d == null:
		_fail("Directional ocean audit requires the built BaseEnvironment and BaseWorld3D.")
		return false
	var world = environment.world_3d
	if scattering_mode != "production":
		if not world.has_method("set_ocean_scattering_enabled"):
			_fail("BaseWorld3D does not expose set_ocean_scattering_enabled() required by --scattering.")
			return false
		var scattering_enabled := scattering_mode == "on"
		world.call("set_ocean_scattering_enabled", scattering_enabled)
		var world_state: Dictionary = world.state_for_tests()
		if not world_state.has("ocean_scattering_enabled"):
			_fail("BaseWorld3D must expose ocean_scattering_enabled in state_for_tests().")
			return false
		if bool(world_state.get("ocean_scattering_enabled", false)) != scattering_enabled:
			_fail("BaseWorld3D did not apply the requested --scattering=%s mode." % scattering_mode)
			return false
	if camera_mode == "topdown":
		var camera := world.camera as Camera3D
		if camera == null:
			_fail("Top-down ocean audit requires the production BaseWorld3D camera.")
			return false
		_configure_topdown_camera(camera)
		# The 2D board is calibrated to the production camera. A top-down audit is a
		# world-only diagnostic view, so hiding it prevents stale hit regions and HUD
		# chrome from being mistaken for ocean or platform geometry.
		if environment.platform_board != null:
			environment.platform_board.visible = false
		var hud_canvas = base.get("_hud_canvas")
		if hud_canvas != null:
			hud_canvas.visible = false
	return true


func _configure_topdown_camera(camera: Camera3D) -> void:
	if camera == null:
		return
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = TOPDOWN_CAMERA_SIZE
	camera.current = true
	camera.look_at_from_position(TOPDOWN_CAMERA_POSITION, TOPDOWN_CAMERA_TARGET, TOPDOWN_CAMERA_UP)


func _run_movie_frames(frame_count: int) -> void:
	for _frame in range(frame_count):
		await get_tree().process_frame


func _run_realtime_profile(
	duration_seconds: float,
	case_id: String,
	quality: String,
	environment,
	wind_direction: Vector2,
	scattering_mode: String,
	camera_mode: String
) -> void:
	var frame_times: Array[float] = []
	var render_cpu_times: Array[float] = []
	var gpu_times: Array[float] = []
	var draw_calls: Array[float] = []
	var primitives: Array[float] = []
	var measured_viewports: Array[RID] = [get_viewport().get_viewport_rid()]
	if environment.world_viewport != null:
		var world_viewport_rid: RID = environment.world_viewport.get_viewport_rid()
		if world_viewport_rid != measured_viewports[0]:
			measured_viewports.append(world_viewport_rid)
	for viewport_rid in measured_viewports:
		RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	# RenderingServer measurements are delayed. Exclude their activation frames
	# from the profile just as we exclude the shader/particle warm-up above.
	for _frame in range(4):
		await get_tree().process_frame
	var elapsed := 0.0
	while elapsed < duration_seconds:
		await get_tree().process_frame
		var delta := get_process_delta_time()
		if delta <= 0.0:
			continue
		elapsed += delta
		frame_times.append(delta * 1000.0)
		var render_cpu_ms := RenderingServer.get_frame_setup_time_cpu()
		var gpu_ms := 0.0
		for viewport_rid in measured_viewports:
			render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
			gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
		if render_cpu_ms > 0.0:
			render_cpu_times.append(render_cpu_ms)
		if gpu_ms > 0.0:
			gpu_times.append(gpu_ms)
		draw_calls.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	for viewport_rid in measured_viewports:
		RenderingServer.viewport_set_measure_render_time(viewport_rid, false)
	frame_times.sort()
	render_cpu_times.sort()
	gpu_times.sort()
	draw_calls.sort()
	primitives.sort()
	var average_ms := _average(frame_times)
	print(
		"OCEAN_PERFORMANCE case=%s quality=%s samples=%d avg_ms=%.3f p50_ms=%.3f p95_ms=%.3f p99_ms=%.3f avg_fps=%.2f render_cpu_avg_ms=%.3f render_cpu_p95_ms=%.3f gpu_avg_ms=%.3f gpu_p50_ms=%.3f gpu_p95_ms=%.3f gpu_p99_ms=%.3f measured_viewports=%d draw_calls_avg=%.1f draw_calls_p95=%.1f primitives_avg=%.1f video_mem_mb=%.1f wind_x=%.6f wind_z=%.6f scattering=%s camera=%s"
		% [
			case_id,
			quality,
			frame_times.size(),
			average_ms,
			_percentile(frame_times, 0.50),
			_percentile(frame_times, 0.95),
			_percentile(frame_times, 0.99),
			1000.0 / average_ms if average_ms > 0.0 else 0.0,
			_average(render_cpu_times),
			_percentile(render_cpu_times, 0.95),
			_average(gpu_times),
			_percentile(gpu_times, 0.50),
			_percentile(gpu_times, 0.95),
			_percentile(gpu_times, 0.99),
			measured_viewports.size(),
			_average(draw_calls),
			_percentile(draw_calls, 0.95),
			_average(primitives),
			float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / (1024.0 * 1024.0),
			wind_direction.x,
			wind_direction.y,
			scattering_mode,
			camera_mode,
		]
	)


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _percentile(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var index := clampi(roundi((values.size() - 1) * percentile), 0, values.size() - 1)
	return values[index]


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
