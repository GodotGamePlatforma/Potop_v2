extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const WeatherStateScript := preload("res://scripts/data/WeatherState.gd")

const DEFAULT_CAPTURE_RESOLUTION := Vector2i(1280, 720)
const START_CAPTURE_RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1280, 1024)]
const START_CAPTURE_QUALITIES := ["high", "medium", "low"]
const DAY_ONE_CAMPAIGN_SEED := 4_214
const SHARED_WIND := Vector2(0.76, 0.65)
const SHARED_WAVE_PHASE_TIME := 1.7
# Fixed final-frame regions catch black-crushed storm lighting without turning
# this native harness into a slow full-image golden comparison. The broad ROI
# includes the platform silhouette and storm background; the slot ROIs below
# keep the stricter gameplay-space legibility contract.
const STORM_LIGHTING_ROI := Rect2i(220, 85, 835, 550)
const STORM_UNHIGHLIGHTED_SLOT_ROIS := {
	"top_left": Rect2i(285, 230, 180, 120),
	"top_center": Rect2i(485, 230, 200, 120),
	"top_right": Rect2i(790, 230, 180, 120),
	"bottom_left": Rect2i(285, 395, 180, 125),
	"center": Rect2i(485, 395, 200, 125),
}
const STORM_MIN_MEDIAN_LUMINANCE := 0.080
const STORM_MAX_DARK_PIXEL_FRACTION := 0.50
const STORM_SLOT_MIN_MEAN_LUMINANCE := 0.072
const STORM_SLOT_MAX_DARK_PIXEL_FRACTION := 0.60
const LUMINANCE_SAMPLE_STEP := 4

var _capture_resolution := DEFAULT_CAPTURE_RESOLUTION


func _ready() -> void:
	# OS cursor placement must never select a BuildingSlot in a golden image.
	# Programmatic setup below does not rely on GUI input events.
	get_viewport().gui_disable_input = true
	var cases := [
		{
			"quality": "high",
			"file_name": "base_weather_calm.png",
			"weather": _profile(WeatherStateScript.Condition.CALM, 0.31, 0.34, 0.31, 0.20, 0.10, 0.72),
		},
		{
			"quality": "high",
			"file_name": "base_weather_moderate.png",
			# Null deliberately keeps the real seeded day-one WeatherState.
			"weather": null,
		},
		{
			"quality": "high",
			"file_name": "base_weather_rough.png",
			"weather": _profile(WeatherStateScript.Condition.ROUGH, 0.78, 0.70, 0.84, 0.72, 0.68, 1.10),
		},
		{
			"quality": "high",
			"file_name": "base_weather_storm.png",
			"weather": _profile(WeatherStateScript.Condition.STORM, 1.00, 1.00, 1.16, 1.00, 1.00, 1.34),
		},
		{
			"quality": "high",
			"file_name": "base_weather_storm_powered.png",
			"weather": _profile(WeatherStateScript.Condition.STORM, 1.00, 1.00, 1.16, 1.00, 1.00, 1.34),
			"powered": true,
		},
		{
			"quality": "medium",
			"file_name": "base_weather_storm_medium.png",
			"weather": _profile(WeatherStateScript.Condition.STORM, 1.00, 1.00, 1.16, 1.00, 1.00, 1.34),
		},
		{
			"quality": "low",
			"file_name": "base_weather_storm_low.png",
			"weather": _profile(WeatherStateScript.Condition.STORM, 1.00, 1.00, 1.16, 1.00, 1.00, 1.34),
		},
	]
	var user_arguments := _user_arguments()
	var start_capture_mode: bool = str(user_arguments.get("case", "")) == "start"
	if start_capture_mode:
		var start_case := _configure_start_capture_case(user_arguments)
		if start_case.is_empty():
			return
		cases = [start_case]
	for snapshot_case in cases:
		var game = GameRootScene.instantiate()
		add_child(game)
		await get_tree().process_frame
		if not await _configure_native_capture(game, str(snapshot_case.quality)):
			return
		if not game.start_new_campaign("standard", DAY_ONE_CAMPAIGN_SEED, false, false):
			push_error("Base weather snapshot could not start the real standard campaign flow.")
			get_tree().quit(1)
			return
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		# This harness isolates weather and platform legibility. Narrative dialogue
		# has its own visual contract and must not dim the audited world behind it.
		game.narrative_dialogue_panel.clear()
		await get_tree().process_frame

		var state = game.game_state
		var base = game.current_scene
		if not _validate_day_one_runtime(state, base):
			get_tree().quit(1)
			return
		if start_capture_mode and not _validate_start_capture_runtime(state, base, str(snapshot_case.quality)):
			get_tree().quit(1)
			return
		var weather = state.weather
		if snapshot_case.weather != null:
			weather = (snapshot_case.weather as Resource).duplicate(true)
			state.weather = weather
		if bool(snapshot_case.get("powered", false)):
			state.story_flags.junction_j7_active = true
		base.bind(game, state)
		base.set_graphics_quality(str(snapshot_case.quality))
		if bool(snapshot_case.get("powered", false)) and not _validate_powered_capture_runtime(base):
			get_tree().quit(1)
			return
		_prepare_gpu_particles(base)
		base.set_animation_time_for_tests(SHARED_WAVE_PHASE_TIME / weather.wave_speed_multiplier)
		_seek_gpu_particles(base)
		await _render_barriers(4)
		if not _save_snapshot(str(snapshot_case.file_name)):
			return
		game.queue_free()
		await _render_barriers(3)

	if start_capture_mode:
		print(
			"Fresh-runtime day-one start snapshot saved for %s at %dx%d."
			% [str(cases[0].quality), _capture_resolution.x, _capture_resolution.y]
		)
	else:
		print("Fresh-runtime canonical 1280x720 snapshots saved for four weather states, storm after J-7 and storm medium/low.")
	get_tree().quit(0)


func _user_arguments() -> Dictionary:
	var result := {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--"):
			continue
		var separator := argument.find("=")
		if separator <= 2:
			continue
		result[argument.substr(2, separator - 2)] = argument.substr(separator + 1)
	return result


func _configure_start_capture_case(arguments: Dictionary) -> Dictionary:
	var quality := str(arguments.get("quality", "")).to_lower()
	if quality not in START_CAPTURE_QUALITIES:
		push_error("Start snapshot quality must be high, medium or low.")
		get_tree().quit(1)
		return {}
	var resolution_text := str(arguments.get("resolution", ""))
	var resolution_parts := resolution_text.split("x", false, 1)
	if resolution_parts.size() != 2 or not resolution_parts[0].is_valid_int() or not resolution_parts[1].is_valid_int():
		push_error("Start snapshot resolution must be 1280x720 or 1280x1024.")
		get_tree().quit(1)
		return {}
	var resolution := Vector2i(int(resolution_parts[0]), int(resolution_parts[1]))
	if resolution not in START_CAPTURE_RESOLUTIONS:
		push_error("Start snapshot resolution must be 1280x720 or 1280x1024.")
		get_tree().quit(1)
		return {}
	var file_name := str(arguments.get("file", "start_base_%s_%s.png" % [quality, resolution_text])).strip_edges()
	if file_name.is_empty() or file_name.get_file() != file_name or not file_name.ends_with(".png") or ".." in file_name:
		push_error("Start snapshot file must be a plain PNG file name.")
		get_tree().quit(1)
		return {}
	_capture_resolution = resolution
	return {
		"quality": quality,
		"file_name": file_name,
		# Null deliberately preserves the real moderate day-one weather.
		"weather": null,
	}


func _configure_native_capture(game: Node, quality: String) -> bool:
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		push_error("Full-runtime base snapshots require a native, non-headless Godot window.")
		get_tree().quit(1)
		return false
	var settings: Dictionary = game.user_settings.snapshot()
	var display: Dictionary = settings.get("display", {}).duplicate(true)
	display["mode"] = "windowed"
	display["resolution"] = _capture_resolution
	display["vsync"] = false
	display["max_fps"] = 0
	settings["display"] = display
	settings["graphics"] = {"quality": quality}
	if game.user_settings.apply(settings, false) != OK:
		push_error("Full-runtime base snapshots could not apply their capture settings.")
		get_tree().quit(1)
		return false
	for _frame in range(30):
		await get_tree().process_frame
		if get_viewport().get_texture().get_size() == Vector2(_capture_resolution):
			return true
	push_error(
		"Full-runtime base snapshots require a %dx%d render target, got %s."
		% [_capture_resolution.x, _capture_resolution.y, str(get_viewport().get_texture().get_size())]
	)
	get_tree().quit(1)
	return false


func _validate_day_one_runtime(state, base: Node) -> bool:
	if state == null or base == null or base.name != "BaseScene":
		push_error("Base weather snapshot must capture the real GameRoot -> BaseScene flow.")
		return false
	if int(state.day) != 1 or state.tutorial == null or not state.tutorial.is_active():
		push_error("Base weather snapshot must preserve the real active day-one tutorial state.")
		return false
	if state.weather == null or int(state.weather.condition) != WeatherStateScript.Condition.MODERATE:
		push_error("The canonical day-one runtime must begin with moderate weather before profile snapshots are applied.")
		return false
	var tutorial_panel := base.find_child("TutorialPanel", true, false) as Control
	var resource_bar := base.find_child("ResourceBar", true, false) as Control
	if tutorial_panel == null or not tutorial_panel.visible or resource_bar == null:
		push_error("Full-runtime base snapshots must include the HUD and day-one tutorial callout.")
		return false
	if state.story_flags == null or bool(state.story_flags.junction_j7_active):
		push_error("Day-one base snapshots must begin before persisted J-7 activation.")
		return false
	var environment = base.get_node_or_null("BaseEnvironment")
	if environment == null or not environment.has_method("world_state_for_tests"):
		push_error("Day-one base snapshots require the real BaseEnvironment world state.")
		return false
	var world_state: Dictionary = environment.world_state_for_tests()
	if (
		bool(world_state.get("powered_presentation", true))
		or int(world_state.get("light_count", 0)) != 1
		or int(world_state.get("directional_light_count", 0)) != 1
		or int(world_state.get("spot_light_count", -1)) != 0
		or int(world_state.get("omni_light_count", -1)) != 0
		or int(world_state.get("deck_light_mount_count", 0)) != 3
		or int(world_state.get("deck_light_local_light_count", -1)) != 0
		or int(world_state.get("deck_light_beam_count", 0)) != 3
		or int(world_state.get("deck_light_beam_visible_count", -1)) != 0
		or int(world_state.get("deck_light_source_glow_count", 0)) != 3
		or int(world_state.get("deck_light_source_glow_visible_count", -1)) != 0
		or int(world_state.get("deck_light_fixture_geometry_count", -1)) != 0
		or int(world_state.get("deck_light_vfx_geometry_count", 0)) != 6
		or int(world_state.get("deck_light_vfx_shadow_casting_count", -1)) != 0
		or int(world_state.get("deck_light_anchor_match_count", 0)) != 3
		or float(world_state.get("deck_light_aim_alignment_min", 0.0)) <= 0.999
		or float(world_state.get("deck_light_beam_end_clearance_min", 0.0)) <= 0.0
		or float(world_state.get("deck_light_beam_end_clearance_max", 1.0)) >= 0.35
		or bool(world_state.get("amber_lamp_emission_enabled", true))
		or not is_zero_approx(float(world_state.get("amber_lamp_emission_energy", 1.0)))
	):
		push_error("Before J-7 the world must retain only its directional sun while three fixtureless VFX sources and beams stay hidden, with M_AmberLamp emission disabled.")
		return false
	return true


func _validate_start_capture_runtime(state, base: Node, quality: String) -> bool:
	if state.buildings.size() != 0 or state.platform == null or state.platform.slot_states.size() != 6:
		push_error("Start snapshot requires six empty day-one building slots.")
		return false
	for slot_id in state.platform.slot_states:
		var slot_state: Dictionary = state.platform.slot_states[slot_id]
		if not str(slot_state.get("building_id", "")).is_empty():
			push_error("Start snapshot found a completed building in slot %s." % slot_id)
			return false
	var environment = base.get_node_or_null("BaseEnvironment")
	if environment == null or not environment.has_method("world_state_for_tests"):
		push_error("Start snapshot requires the real BaseEnvironment world state.")
		return false
	var world_state: Dictionary = environment.world_state_for_tests()
	if not bool(world_state.get("model_loaded", false)) or int(world_state.get("ruin_count", 0)) != 6 or int(world_state.get("slot_anchor_count", 0)) != 6:
		push_error("Start snapshot requires the imported GLB with six ruins and six anchors.")
		return false
	if str(world_state.get("quality", "")) != quality:
		push_error("Start snapshot renderer did not apply graphics quality %s." % quality)
		return false
	for visible in (world_state.get("ruin_visibility", {}) as Dictionary).values():
		if not bool(visible):
			push_error("Start snapshot hid one of the six ruins.")
			return false
	for levels in (world_state.get("building_visibility", {}) as Dictionary).values():
		for visible in (levels as Dictionary).values():
			if bool(visible):
				push_error("Start snapshot displayed a built variant on day one.")
				return false
	return true


func _validate_powered_capture_runtime(base: Node) -> bool:
	var environment = base.get_node_or_null("BaseEnvironment")
	if environment == null or not environment.has_method("world_state_for_tests"):
		push_error("Powered base snapshot requires the real BaseEnvironment world state.")
		return false
	var world_state: Dictionary = environment.world_state_for_tests()
	if not bool(world_state.get("powered_presentation", false)) or int(world_state.get("amber_lamp_material_count", 0)) <= 0 or bool(world_state.get("amber_lamp_emission_enabled", true)) or not is_zero_approx(float(world_state.get("amber_lamp_emission_energy", 1.0))):
		push_error("Powered base snapshot requires J-7 presentation without M_AmberLamp emission.")
		return false
	if (
		int(world_state.get("light_count", 0)) != 1
		or int(world_state.get("directional_light_count", 0)) != 1
		or int(world_state.get("spot_light_count", -1)) != 0
		or int(world_state.get("omni_light_count", -1)) != 0
		or int(world_state.get("deck_light_mount_count", 0)) != 3
		or int(world_state.get("deck_light_mount_parented_count", 0)) != 3
		or int(world_state.get("deck_light_local_light_count", -1)) != 0
		or int(world_state.get("deck_light_beam_count", 0)) != 3
		or int(world_state.get("deck_light_beam_visible_count", 0)) != 3
		or int(world_state.get("deck_light_beam_parented_count", 0)) != 3
		or int(world_state.get("deck_light_source_glow_count", 0)) != 3
		or int(world_state.get("deck_light_source_glow_visible_count", 0)) != 3
		or int(world_state.get("deck_light_source_glow_parented_count", 0)) != 3
	):
		push_error("Powered base snapshot must retain one shared sun and exactly three mounted source-glow and directional-beam VFX groups without local Light3D nodes.")
		return false
	if int(world_state.get("deck_light_fixture_geometry_count", -1)) != 0 or int(world_state.get("deck_light_vfx_geometry_count", 0)) != 6 or int(world_state.get("deck_light_vfx_shadow_casting_count", -1)) != 0 or int(world_state.get("deck_light_anchor_match_count", 0)) != 3 or float(world_state.get("deck_light_aim_alignment_min", 0.0)) <= 0.999 or float(world_state.get("deck_light_beam_end_clearance_min", 0.0)) <= 0.0 or float(world_state.get("deck_light_beam_end_clearance_max", 1.0)) >= 0.35:
		push_error("Powered base snapshot requires three fixtureless source halos and three shadowless beams at the approved rig anchors, ending just above the deck without a local lighting response.")
		return false
	return true


func _prepare_gpu_particles(root: Node) -> void:
	var particle_index := 0
	for particle_node in root.find_children("*", "GPUParticles3D", true, false):
		var particles := particle_node as GPUParticles3D
		particles.use_fixed_seed = true
		particles.seed = 73_251 + particle_index * 977
		particles.preprocess = 0.0
		particles.speed_scale = 0.0
		# Collision-only child pools are deliberately dormant. Restarting them
		# would turn exact contact effects back into autonomous origin particles.
		if not particles.one_shot and particles.emitting:
			particles.restart(true)
		particle_index += 1


func _seek_gpu_particles(root: Node) -> void:
	for particle_node in root.find_children("*", "GPUParticles3D", true, false):
		var particles := particle_node as GPUParticles3D
		if particles.one_shot:
			if particles.emitting:
				particles.request_particles_process(minf(0.22, particles.lifetime * 0.35))
		else:
			particles.request_particles_process(SHARED_WAVE_PHASE_TIME)


func _render_barriers(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw


func _profile(condition: int, sea: float, rain: float, motion: float, foam: float, splash: float, speed: float):
	var weather = WeatherStateScript.new()
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


func _save_snapshot(file_name: String) -> bool:
	var image := get_viewport().get_texture().get_image()
	if image.get_size() != _capture_resolution:
		push_error(
			"Base weather snapshot %s has invalid size %s instead of %s."
			% [file_name, str(image.get_size()), str(_capture_resolution)]
		)
		get_tree().quit(1)
		return false
	var output_directory := ProjectSettings.globalize_path("res://tmp")
	if not DirAccess.dir_exists_absolute(output_directory):
		var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
		if directory_error != OK:
			push_error("Could not create the base weather snapshot directory. Error: %d" % directory_error)
			get_tree().quit(1)
			return false
	var error := image.save_png(output_directory.path_join(file_name))
	if error != OK:
		push_error("Could not save full-runtime base weather snapshot. Error: %d" % error)
		get_tree().quit(1)
		return false
	if file_name.begins_with("base_weather_storm") and not _validate_storm_lighting(image, file_name):
		return false
	return true


func _validate_storm_lighting(image: Image, file_name: String) -> bool:
	var audit_image := image.duplicate() as Image
	audit_image.convert(Image.FORMAT_RGBA8)
	var pixels: PackedByteArray = audit_image.get_data()
	var image_width: int = audit_image.get_width()
	var overall := _luminance_stats(pixels, image_width, STORM_LIGHTING_ROI)
	if float(overall.median) < STORM_MIN_MEDIAN_LUMINANCE or float(overall.dark_fraction) > STORM_MAX_DARK_PIXEL_FRACTION:
		push_error(
			"Storm lighting %s lost platform legibility: median %.3f, dark fraction %.1f%%."
			% [file_name, float(overall.median), float(overall.dark_fraction) * 100.0]
		)
		get_tree().quit(1)
		return false
	for slot_name in STORM_UNHIGHLIGHTED_SLOT_ROIS:
		var slot_stats := _luminance_stats(pixels, image_width, STORM_UNHIGHLIGHTED_SLOT_ROIS[slot_name])
		if float(slot_stats.mean) < STORM_SLOT_MIN_MEAN_LUMINANCE or float(slot_stats.dark_fraction) > STORM_SLOT_MAX_DARK_PIXEL_FRACTION:
			push_error(
				"Storm lighting %s lost the unhighlighted %s slot: mean %.3f, dark fraction %.1f%%."
				% [file_name, slot_name, float(slot_stats.mean), float(slot_stats.dark_fraction) * 100.0]
			)
			get_tree().quit(1)
			return false
	print(
		"Storm lighting %s passed: platform median %.3f, dark fraction %.1f%%."
		% [file_name, float(overall.median), float(overall.dark_fraction) * 100.0]
	)
	return true


func _luminance_stats(pixels: PackedByteArray, image_width: int, roi: Rect2i) -> Dictionary:
	var histogram := PackedInt32Array()
	histogram.resize(256)
	var luminance_sum := 0.0
	var dark_count := 0
	var pixel_count := 0
	for y in range(roi.position.y, roi.position.y + roi.size.y, LUMINANCE_SAMPLE_STEP):
		for x in range(roi.position.x, roi.position.x + roi.size.x, LUMINANCE_SAMPLE_STEP):
			var byte_offset := (y * image_width + x) * 4
			var luminance := (
				float(pixels[byte_offset]) * 0.2126
				+ float(pixels[byte_offset + 1]) * 0.7152
				+ float(pixels[byte_offset + 2]) * 0.0722
			) / 255.0
			pixel_count += 1
			luminance_sum += luminance
			if luminance < 0.08:
				dark_count += 1
			histogram[clampi(roundi(luminance * 255.0), 0, 255)] += 1
	var median_target := (pixel_count + 1) / 2
	var accumulated := 0
	var median_luminance := 0.0
	for bucket in range(histogram.size()):
		accumulated += histogram[bucket]
		if accumulated >= median_target:
			median_luminance = float(bucket) / 255.0
			break
	return {
		"mean": luminance_sum / float(pixel_count),
		"median": median_luminance,
		"dark_fraction": float(dark_count) / float(pixel_count),
	}
