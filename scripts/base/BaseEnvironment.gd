extends Control

const BaseWorld3DScript := preload("res://scripts/base/BaseWorld3D.gd")

const PLATFORM_MODEL_PATH := "res://assets/base_3d/start_platform_ruins.glb"
const FAR_RAIN_SHADER_PATH := "res://assets/base/environment_3d/rain_far_veil.gdshader"
const BUILDING_HIGHLIGHT_BLUR_SHADER_PATH := "res://assets/base/environment_3d/building_highlight_blur_horizontal.gdshader"
const BUILDING_HIGHLIGHT_SHADER_PATH := "res://assets/base/environment_3d/building_highlight_outline.gdshader"

const BUILDING_HIGHLIGHT_NONE := &"none"
const BUILDING_HIGHLIGHT_FOCUS := &"focus"
const BUILDING_HIGHLIGHT_HOVER := &"hover"
const BUILDING_HIGHLIGHT_PRESSED := &"pressed"
const BUILDING_HIGHLIGHT_TUTORIAL := &"tutorial"
const BUILDING_HIGHLIGHT_COLOR := Color(0.36, 0.94, 0.91, 0.90)
const BUILDING_FOCUS_COLOR := Color(0.72, 1.0, 0.96, 0.88)
const BUILDING_PRESSED_COLOR := Color(1.0, 0.76, 0.30, 1.0)
const BUILDING_TUTORIAL_COLOR := Color(1.0, 0.61, 0.20, 0.94)
const BUILDING_TUTORIAL_PULSE_PERIOD := 2.8

const PLATFORM_ASPECT := 1672.0 / 941.0
const DEFAULT_SEA_INTENSITY := 0.56
const DEFAULT_RAIN_INTENSITY := 0.52
const DEFAULT_MOTION_INTENSITY := 0.58
const DEFAULT_FOAM_INTENSITY := 0.46
const DEFAULT_SPLASH_INTENSITY := 0.38
const DEFAULT_WAVE_SPEED := 0.90
const SPLASH_MIN_INTENSITY := 0.12
const SPLASH_PEAK_THRESHOLD_QUIET := 0.52
const SPLASH_PEAK_THRESHOLD_STORM := 0.32
const SPLASH_COOLDOWN_QUIET := 7.0
const SPLASH_COOLDOWN_STORM := 1.8
const SPLASH_SLOPE_EPSILON := 0.000001
const PLATFORM_SAFE_HEIGHT_RATIO := 0.95
# Conservative local bounds of the hull, active buildings and fixed deck
# machinery. They drive only the inexpensive far-veil exclusion; true contact
# and occlusion of near/mid rain remain in the 3D depth/collision pipeline.
const RAIN_OCCLUSION_LOCAL_MIN := Vector3(-11.6, -0.6, -8.0)
const RAIN_OCCLUSION_LOCAL_MAX := Vector3(11.6, 7.2, 8.0)
const SLOT_IDS: Array[String] = [
	"top_left",
	"top_center",
	"top_right",
	"bottom_left",
	"center",
	"bottom_right",
]
var platform_board: Control
var building_layer: Control
var building_info_layer: Control
var slot_layer: Control
var world_3d: BaseWorld3D
var world_viewport: SubViewport
var building_highlight_viewport: SubViewport
var building_highlight_blur_viewport: SubViewport

var _viewport_container: SubViewportContainer
var _far_rain_veil: ColorRect
var _far_rain_material: ShaderMaterial
var _building_highlight_camera: Camera3D
var _building_highlight_blur_input: TextureRect
var _building_highlight_blur_material: ShaderMaterial
var _building_highlight_overlay: TextureRect
var _building_highlight_material: ShaderMaterial
var _building_highlight_slot_id := ""
var _building_highlight_mode: StringName = BUILDING_HIGHLIGHT_NONE
var _far_rain_occlusion_rect_uv := Rect2()
var _rest_board_position := Vector2.ZERO
var _layout_viewport_size := Vector2(1280.0, 720.0)
var _elapsed := 0.0
var _forced_animation_time := -1.0
var _splash_previous_energy := 0.0
var _splash_peak_energy := 0.0
var _splash_peak_side := 0
var _splash_energy_rising := false
var _splash_last_event_time := 0.0
var _splash_event_sequence := 0
var _built := false
var _reduced_motion := false
var _sea_intensity := DEFAULT_SEA_INTENSITY
var _rain_intensity := DEFAULT_RAIN_INTENSITY
var _motion_intensity := DEFAULT_MOTION_INTENSITY
var _foam_intensity := DEFAULT_FOAM_INTENSITY
var _splash_intensity := DEFAULT_SPLASH_INTENSITY
var _wave_speed := DEFAULT_WAVE_SPEED
var _wind_direction := Vector2(0.76, 0.65).normalized()
var _ambient_color := Color(0.70, 0.74, 0.75)
var _ambient_energy := 0.98
var _sun_color := Color(0.97, 0.91, 0.82)
var _sun_energy := 0.96
var _sun_angular_distance := 0.70
var _sun_shadow_opacity := 0.72
var _deck_wetness := 0.45
var _graphics_quality := "high"
var _powered_presentation := false


func build() -> void:
	if _built:
		return
	_built = true
	name = "BaseEnvironment"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "BaseWorldViewportContainer"
	_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport_container.stretch = true
	# This container presents a render target and owns an explicit linear filter.
	# In particular, the low profile upscales a half-resolution 3D image.
	_viewport_container.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewport_container)

	world_viewport = SubViewport.new()
	world_viewport.name = "BaseWorldViewport"
	world_viewport.size = Vector2i(1280, 720)
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	# The marine world owns an opaque target so depth, PBR and sky reflection stay
	# stable. Transparency belongs only to the 2D interaction layers above it.
	world_viewport.transparent_bg = false
	world_viewport.own_world_3d = true
	world_viewport.gui_disable_input = true
	_viewport_container.add_child(world_viewport)

	world_3d = BaseWorld3DScript.new()
	# The saved preset is assigned before build by GameRoot/BaseController. Pass it
	# into the world before any GPU resources are configured so low/medium never
	# allocate the high ocean, particles, SSAO or SSIL for a transient frame.
	world_3d.set_graphics_quality(_graphics_quality)
	world_3d.set_reduced_motion(_reduced_motion)
	world_viewport.add_child(world_3d)
	_apply_viewport_quality()
	world_3d.build()
	_build_far_rain_veil()
	_build_building_highlight()

	# This transparent 2D rig remains the stable gameplay projection. Existing
	# HUD, building panels and broad hit regions keep their contract, while all
	# scenery, ruins, completed buildings and water are rendered in real 3D.
	platform_board = Control.new()
	platform_board.name = "PlatformBoard"
	platform_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(platform_board)

	building_layer = Control.new()
	building_layer.name = "Buildings"
	building_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	building_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	building_layer.z_index = 1
	platform_board.add_child(building_layer)

	building_info_layer = Control.new()
	building_info_layer.name = "BuildingInfo"
	building_info_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	building_info_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	building_info_layer.z_index = 12
	platform_board.add_child(building_info_layer)

	slot_layer = Control.new()
	slot_layer.name = "BuildingSlots"
	slot_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	slot_layer.z_index = 20
	platform_board.add_child(slot_layer)

	_apply_far_rain_quality()
	_apply_weather_to_world()
	# Set deterministic ocean phase before the first visible frame instead of
	# briefly falling back to the global shader TIME value.
	_reset_splash_scheduler(0.0)
	_apply_animation(0.0, false)
	set_process(true)


func layout_environment(viewport_size: Vector2) -> void:
	if platform_board == null or viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	_layout_viewport_size = viewport_size
	world_3d.set_viewport_size(viewport_size)
	_sync_building_highlight_camera()
	if _far_rain_material != null:
		_far_rain_material.set_shader_parameter("viewport_size", viewport_size)

	var available_size := Vector2(viewport_size.x, viewport_size.y * PLATFORM_SAFE_HEIGHT_RATIO)
	var board_size := Vector2(available_size.y * PLATFORM_ASPECT, available_size.y)
	if board_size.x > available_size.x:
		board_size = Vector2(available_size.x, available_size.x / PLATFORM_ASPECT)
	platform_board.size = board_size
	_rest_board_position = (viewport_size - board_size) * 0.5
	platform_board.position = _rest_board_position
	platform_board.pivot_offset = board_size * 0.5
	if is_inside_tree():
		_apply_far_rain_occlusion()


func set_animation_time_for_tests(seconds: float) -> void:
	_forced_animation_time = maxf(seconds, 0.0)
	_reset_splash_scheduler(_forced_animation_time)
	_apply_animation(_forced_animation_time, false)


func clear_animation_time_override() -> void:
	_forced_animation_time = -1.0
	_reset_splash_scheduler(_elapsed)


func set_graphics_quality(quality_id: String) -> void:
	_graphics_quality = quality_id if quality_id in ["low", "medium", "high"] else "high"
	if not _built:
		return
	if world_3d != null:
		world_3d.set_graphics_quality(_graphics_quality)
	_apply_viewport_quality()
	_apply_far_rain_quality()


func _apply_viewport_quality() -> void:
	if _viewport_container == null or world_viewport == null:
		return
	_viewport_container.stretch_shrink = 2 if _graphics_quality == "low" else 1
	world_viewport.msaa_3d = Viewport.MSAA_DISABLED if _graphics_quality == "low" else Viewport.MSAA_2X if _graphics_quality == "medium" else Viewport.MSAA_4X
	# SMAA keeps the medium preset clearer than FXAA at the logical 1280x720
	# reference size. TAA remains disabled because it smears rain and rig motion.
	world_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA if _graphics_quality == "medium" else Viewport.SCREEN_SPACE_AA_DISABLED
	world_viewport.use_taa = false
	if building_highlight_viewport != null:
		# The mask renders one binary silhouette. Two samples are enough to retain a
		# stable edge without duplicating the main viewport's 4x/SMAA post-process.
		building_highlight_viewport.msaa_3d = Viewport.MSAA_DISABLED if _graphics_quality == "low" else Viewport.MSAA_2X
		building_highlight_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		building_highlight_viewport.use_taa = false
	# The separable binomial kernels use 3/5/7 samples per axis. Spreading their
	# bilinear taps turns the former narrow rim into a wider, dimmer halo without
	# increasing the number of texture reads. Low also inherits the half-res scale.
	var glow_radius := 2 if _graphics_quality == "low" else 4 if _graphics_quality == "medium" else 6
	var glow_spread := 3.0 if _graphics_quality == "low" else 2.5 if _graphics_quality == "medium" else 2.4
	if _building_highlight_blur_material != null:
		_building_highlight_blur_material.set_shader_parameter("glow_radius", glow_radius)
		_building_highlight_blur_material.set_shader_parameter("glow_spread", glow_spread)
	if _building_highlight_material != null:
		_building_highlight_material.set_shader_parameter("glow_radius", glow_radius)
		_building_highlight_material.set_shader_parameter("glow_spread", glow_spread)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if world_3d != null:
		world_3d.set_reduced_motion(enabled)
	var current_time := _forced_animation_time if _forced_animation_time >= 0.0 else _elapsed
	if _built:
		_apply_animation(current_time, false)


func graphics_quality_state() -> Dictionary:
	var world_state: Dictionary = world_3d.state_for_tests() if world_3d != null else {}
	return {
		"quality": _graphics_quality,
		"rendering_mode": "hybrid_3d_world_2d_hud",
		"rain_surface_visible": bool(world_state.get("rain_surface_visible", false)),
		"rain_air_visible": bool(world_state.get("rain_air_emitting", false)),
		"rain_far_veil_visible": _far_rain_veil != null and _far_rain_veil.visible,
		"sea_mist_visible": false,
		"daylight_overlay_visible": false,
		"beauty_overlay_visible": false,
		"splash_quality_scale": 0.0 if _graphics_quality == "low" else 0.55 if _graphics_quality == "medium" else 1.0,
		"splash_particle_amount": 0 if _graphics_quality == "low" else 14 if _graphics_quality == "medium" else 24,
		"ocean_subdivisions": int(world_state.get("ocean_subdivisions", 0)),
		"rain_particle_amount": int(world_state.get("rain_amount", 0)),
		"rain_near_particle_amount": int(world_state.get("rain_near_amount", 0)),
		"rain_contact_particle_amount": int(world_state.get("rain_contact_amount", 0)),
		"rain_far_occlusion_rect_uv": _far_rain_occlusion_rect_uv,
		"fog_enabled": bool(world_state.get("fog_enabled", false)),
		"volumetric_fog_enabled": bool(world_state.get("volumetric_fog_enabled", false)),
	}


func configure_weather(weather) -> void:
	var condition_id := "moderate"
	if weather == null:
		_sea_intensity = DEFAULT_SEA_INTENSITY
		_rain_intensity = DEFAULT_RAIN_INTENSITY
		_motion_intensity = DEFAULT_MOTION_INTENSITY
		_foam_intensity = DEFAULT_FOAM_INTENSITY
		_splash_intensity = DEFAULT_SPLASH_INTENSITY
		_wave_speed = DEFAULT_WAVE_SPEED
		_wind_direction = Vector2(0.76, 0.65).normalized()
	else:
		if weather.has_method("condition_id"):
			condition_id = str(weather.condition_id())
		_sea_intensity = clampf(float(weather.sea_intensity), 0.0, 1.0)
		_rain_intensity = clampf(float(weather.rain_intensity), 0.0, 1.0)
		_motion_intensity = clampf(float(weather.motion_intensity), 0.0, 1.4)
		_foam_intensity = clampf(float(weather.foam_intensity), 0.0, 1.0)
		_splash_intensity = clampf(float(weather.splash_intensity), 0.0, 1.0)
		_wave_speed = clampf(float(weather.wave_speed_multiplier), 0.5, 1.5)
		_wind_direction = Vector2(weather.wind_direction)
		if _wind_direction.length_squared() < 0.001:
			_wind_direction = Vector2(0.76, 0.65)
		_wind_direction = _wind_direction.normalized()
	_configure_daylight_profile(condition_id)
	_apply_weather_to_world()
	var current_time := _forced_animation_time if _forced_animation_time >= 0.0 else _elapsed
	_reset_splash_scheduler(current_time)
	if _built:
		_apply_animation(current_time, false)


func set_powered_presentation(enabled: bool) -> void:
	if _powered_presentation == enabled:
		return
	_powered_presentation = enabled
	_apply_weather_to_world()


func sync_building_states(game_state) -> void:
	if world_3d == null:
		return
	for slot_id in SLOT_IDS:
		var building = null
		if game_state != null and game_state.platform != null:
			var slot_data: Dictionary = game_state.platform.slot_states.get(slot_id, {})
			var building_id := str(slot_data.get("building_id", ""))
			if not building_id.is_empty() and game_state.has_method("find_building"):
				building = game_state.find_building(building_id)
		var is_built := building != null and bool(building.is_built)
		var level := int(building.level) if is_built else 0
		world_3d.set_slot_state(slot_id, is_built, level)


func set_building_highlight(slot_id: String, mode: StringName = BUILDING_HIGHLIGHT_HOVER) -> void:
	if (
		world_3d == null
		or slot_id.is_empty()
		or mode not in [BUILDING_HIGHLIGHT_FOCUS, BUILDING_HIGHLIGHT_HOVER, BUILDING_HIGHLIGHT_PRESSED, BUILDING_HIGHLIGHT_TUTORIAL]
	):
		clear_building_highlight()
		return
	if not world_3d.set_building_highlight(slot_id):
		clear_building_highlight()
		return
	_building_highlight_slot_id = slot_id
	_building_highlight_mode = mode
	var current_time := _forced_animation_time if _forced_animation_time >= 0.0 else _elapsed
	_apply_building_highlight_visual(current_time)
	_sync_building_highlight_camera()
	if building_highlight_viewport != null:
		building_highlight_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if building_highlight_blur_viewport != null:
		building_highlight_blur_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if _building_highlight_overlay != null:
		_building_highlight_overlay.visible = true


func clear_building_highlight() -> void:
	if world_3d != null:
		world_3d.clear_building_highlight()
	_building_highlight_slot_id = ""
	_building_highlight_mode = BUILDING_HIGHLIGHT_NONE
	if _building_highlight_overlay != null:
		_building_highlight_overlay.visible = false
	if building_highlight_viewport != null:
		building_highlight_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if building_highlight_blur_viewport != null:
		building_highlight_blur_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func building_highlight_state_for_tests() -> Dictionary:
	var world_state: Dictionary = world_3d.building_highlight_state_for_tests() if world_3d != null else {}
	var shared_world := (
		building_highlight_viewport != null
		and world_viewport != null
		and building_highlight_viewport.find_world_3d() == world_viewport.find_world_3d()
	)
	return {
		"active": _building_highlight_overlay != null and _building_highlight_overlay.visible,
		"slot_id": _building_highlight_slot_id,
		"mode": _building_highlight_mode,
		"viewport_update_mode": int(building_highlight_viewport.render_target_update_mode) if building_highlight_viewport != null else -1,
		"viewport_size": building_highlight_viewport.size if building_highlight_viewport != null else Vector2i.ZERO,
		"blur_viewport_update_mode": int(building_highlight_blur_viewport.render_target_update_mode) if building_highlight_blur_viewport != null else -1,
		"blur_viewport_size": building_highlight_blur_viewport.size if building_highlight_blur_viewport != null else Vector2i.ZERO,
		"transparent_background": building_highlight_viewport != null and building_highlight_viewport.transparent_bg,
		"shared_world": shared_world,
		"camera_cull_mask": _building_highlight_camera.cull_mask if _building_highlight_camera != null else 0,
		"camera_transform_synced": (
			_building_highlight_camera != null
			and world_3d != null
			and world_3d.camera != null
			and _building_highlight_camera.global_transform.is_equal_approx(world_3d.camera.global_transform)
		),
		"glow_radius": int(_building_highlight_material.get_shader_parameter("glow_radius")) if _building_highlight_material != null else 0,
		"glow_spread": float(_building_highlight_material.get_shader_parameter("glow_spread")) if _building_highlight_material != null else 0.0,
		"glow_softness": float(_building_highlight_material.get_shader_parameter("glow_softness")) if _building_highlight_material != null else 0.0,
		"glow_strength": float(_building_highlight_material.get_shader_parameter("glow_strength")) if _building_highlight_material != null else 0.0,
		"glow_color": Color(_building_highlight_material.get_shader_parameter("glow_color")) if _building_highlight_material != null else Color.TRANSPARENT,
		"reduced_motion": _reduced_motion,
		"world": world_state,
	}


func _apply_building_highlight_visual(current_time: float) -> void:
	if _building_highlight_material == null:
		return
	var glow_color := BUILDING_HIGHLIGHT_COLOR
	var glow_strength := 0.98
	var glow_softness := 0.72
	match _building_highlight_mode:
		BUILDING_HIGHLIGHT_FOCUS:
			glow_color = BUILDING_FOCUS_COLOR
			glow_strength = 0.82
			glow_softness = 0.82
		BUILDING_HIGHLIGHT_PRESSED:
			glow_color = BUILDING_PRESSED_COLOR
			glow_strength = 1.18
			glow_softness = 0.68
		BUILDING_HIGHLIGHT_TUTORIAL:
			glow_color = BUILDING_TUTORIAL_COLOR
			glow_softness = 0.72
			if _reduced_motion:
				glow_strength = 0.90
			else:
				var pulse := 0.5 - 0.5 * cos(TAU * maxf(current_time, 0.0) / BUILDING_TUTORIAL_PULSE_PERIOD)
				glow_strength = lerpf(0.76, 1.08, pulse)
		BUILDING_HIGHLIGHT_NONE:
			glow_strength = 0.0
	_building_highlight_material.set_shader_parameter("glow_color", glow_color)
	_building_highlight_material.set_shader_parameter("glow_strength", glow_strength)
	_building_highlight_material.set_shader_parameter("glow_softness", glow_softness)


func world_state_for_tests() -> Dictionary:
	return world_3d.state_for_tests() if world_3d != null else {}


func sun_energy_for_tests() -> float:
	if world_3d == null:
		return 0.0
	return float(world_3d.state_for_tests().get("sun_energy", 0.0))


func _process(delta: float) -> void:
	if not _built or platform_board == null:
		return
	_elapsed += delta
	var current_time := _forced_animation_time if _forced_animation_time >= 0.0 else _elapsed
	_apply_animation(current_time, _forced_animation_time < 0.0)
	_sync_building_highlight_camera()


func _apply_animation(current_time: float, allow_splashes: bool) -> void:
	if world_3d == null:
		return
	var motion := world_3d.sample_platform_wave_motion(current_time, _motion_intensity)
	world_3d.apply_motion(
		current_time,
		float(motion.heave),
		Vector2(motion.horizontal_offset),
		float(motion.roll),
		float(motion.pitch),
		float(motion.contact_energy),
		Vector4(motion.contact_energy_sides),
		Vector4(motion.pontoon_contact_energy_a),
		Vector4(motion.pontoon_contact_energy_b)
	)
	# build() can be called before this Control enters the SceneTree (as in tests).
	# Local 3D transforms and shader uniforms are valid then, camera projection is not.
	if is_inside_tree():
		_apply_projected_platform_motion()
		_apply_far_rain_occlusion()
	if _far_rain_material != null:
		_far_rain_material.set_shader_parameter("time_offset", current_time)
		_apply_far_rain_flow()
	_apply_building_highlight_visual(current_time)

	if allow_splashes:
		var splash_event := _advance_splash_scheduler(
			current_time,
			float(motion.impact_energy),
			int(motion.impact_side)
		)
		if bool(splash_event.triggered):
			world_3d.trigger_splash_group(int(splash_event.side), int(splash_event.event_seed))


func _reset_splash_scheduler(current_time: float) -> void:
	_splash_previous_energy = 0.0
	_splash_peak_energy = 0.0
	_splash_peak_side = 0
	_splash_energy_rising = false
	# Anchoring the cooldown suppresses a synthetic burst on the first visible
	# frame after entering the base or switching from a deterministic snapshot.
	_splash_last_event_time = current_time
	_splash_event_sequence = 0


func _advance_splash_scheduler(current_time: float, impact_energy: float, impact_side: int) -> Dictionary:
	var result := {
		"triggered": false,
		"side": impact_side,
		"event_seed": 0,
	}
	var energy := clampf(impact_energy, 0.0, 1.0)
	if _splash_intensity < SPLASH_MIN_INTENSITY:
		_splash_previous_energy = energy
		_splash_peak_energy = energy
		_splash_peak_side = impact_side
		_splash_energy_rising = false
		return result

	if energy > _splash_previous_energy + SPLASH_SLOPE_EPSILON:
		if not _splash_energy_rising:
			_splash_peak_energy = energy
			_splash_peak_side = impact_side
		elif energy >= _splash_peak_energy:
			_splash_peak_energy = energy
			_splash_peak_side = impact_side
		_splash_energy_rising = true
	elif energy < _splash_previous_energy - SPLASH_SLOPE_EPSILON:
		if _splash_energy_rising:
			var threshold := lerpf(SPLASH_PEAK_THRESHOLD_QUIET, SPLASH_PEAK_THRESHOLD_STORM, _splash_intensity)
			var cooldown := lerpf(SPLASH_COOLDOWN_QUIET, SPLASH_COOLDOWN_STORM, _splash_intensity)
			if _splash_peak_energy >= threshold and current_time - _splash_last_event_time >= cooldown:
				var event_seed := posmod(
					41_159 + _splash_event_sequence * 9_973 + _splash_peak_side * 683,
					2_147_483_647
				)
				result = {
					"triggered": true,
					"side": _splash_peak_side,
					"event_seed": event_seed,
				}
				_splash_event_sequence += 1
				_splash_last_event_time = current_time
		_splash_energy_rising = false
		_splash_peak_energy = energy
		_splash_peak_side = impact_side
	elif _splash_energy_rising and energy >= _splash_peak_energy - SPLASH_SLOPE_EPSILON:
		# Preserve the physically dominant side across a flat, clamped peak.
		_splash_peak_energy = energy
		_splash_peak_side = impact_side

	_splash_previous_energy = energy
	return result


func splash_schedule_for_tests(duration_seconds: float, sample_fps: float = 60.0) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if world_3d == null or duration_seconds <= 0.0 or sample_fps <= 0.0:
		return events
	_reset_splash_scheduler(0.0)
	var sample_count := floori(duration_seconds * sample_fps)
	for sample_index in range(sample_count + 1):
		var current_time := float(sample_index) / sample_fps
		var motion := world_3d.sample_platform_wave_motion(current_time, _motion_intensity)
		var splash_event := _advance_splash_scheduler(
			current_time,
			float(motion.impact_energy),
			int(motion.impact_side)
		)
		if bool(splash_event.triggered):
			splash_event["time"] = current_time
			events.append(splash_event)
	var restore_time := _forced_animation_time if _forced_animation_time >= 0.0 else _elapsed
	_reset_splash_scheduler(restore_time)
	return events


func _apply_projected_platform_motion() -> void:
	if platform_board == null:
		return
	var projection := _projected_platform_motion()
	platform_board.position = _rest_board_position + Vector2(projection.translation)
	platform_board.rotation = float(projection.rotation)
	platform_board.scale = Vector2(projection.scale)


func _projected_platform_motion() -> Dictionary:
	var fallback := {
		"translation": Vector2.ZERO,
		"rotation": 0.0,
		"scale": Vector2.ONE,
	}
	if world_3d == null or world_3d.camera == null or world_3d.platform_rig == null or world_viewport == null:
		return fallback
	var render_size := Vector2(world_viewport.size)
	if render_size.x <= 0.0 or render_size.y <= 0.0:
		return fallback
	var output_scale := Vector2(
		_layout_viewport_size.x / render_size.x,
		_layout_viewport_size.y / render_size.y
	)
	var rig_parent := world_3d.platform_rig.get_parent_node_3d()
	if rig_parent == null:
		return fallback

	# The board pivot represents the deck centre. Project that anchor plus its
	# local right/depth axes both at rest and after the real rig transform. This
	# keeps tutorial callouts and hitboxes attached to the rendered slots without
	# maintaining a second, hand-tuned animation in screen pixels.
	var local_center := Vector3(0.0, 1.65, 0.0)
	var local_right := local_center + Vector3.RIGHT
	var local_depth := local_center + Vector3.BACK
	var parent_transform := rig_parent.global_transform
	var rest_center := _project_world_point(parent_transform * local_center, output_scale)
	var rest_right := _project_world_point(parent_transform * local_right, output_scale)
	var rest_depth := _project_world_point(parent_transform * local_depth, output_scale)
	var current_center := _project_world_point(world_3d.platform_rig.to_global(local_center), output_scale)
	var current_right := _project_world_point(world_3d.platform_rig.to_global(local_right), output_scale)
	var current_depth := _project_world_point(world_3d.platform_rig.to_global(local_depth), output_scale)
	var rest_right_axis := rest_right - rest_center
	var rest_depth_axis := rest_depth - rest_center
	var current_right_axis := current_right - current_center
	var current_depth_axis := current_depth - current_center
	if rest_right_axis.length_squared() <= 0.0001 or rest_depth_axis.length_squared() <= 0.0001:
		return fallback
	return {
		"translation": current_center - rest_center,
		"rotation": angle_difference(rest_right_axis.angle(), current_right_axis.angle()),
		"scale": Vector2(
			clampf(current_right_axis.length() / rest_right_axis.length(), 0.85, 1.15),
			clampf(current_depth_axis.length() / rest_depth_axis.length(), 0.85, 1.15)
		),
	}


func _project_world_point(world_point: Vector3, output_scale: Vector2) -> Vector2:
	return world_3d.camera.unproject_position(world_point) * output_scale


func _apply_far_rain_occlusion() -> void:
	if (
		_far_rain_material == null or world_3d == null or world_3d.camera == null
		or world_3d.platform_rig == null or world_viewport == null
		or _layout_viewport_size.x <= 0.0 or _layout_viewport_size.y <= 0.0
	):
		return
	var render_size := Vector2(world_viewport.size)
	if render_size.x <= 0.0 or render_size.y <= 0.0:
		return
	var output_scale := Vector2(
		_layout_viewport_size.x / render_size.x,
		_layout_viewport_size.y / render_size.y
	)
	var bounds_min := Vector2(INF, INF)
	var bounds_max := Vector2(-INF, -INF)
	for local_x in [RAIN_OCCLUSION_LOCAL_MIN.x, RAIN_OCCLUSION_LOCAL_MAX.x]:
		for local_y in [RAIN_OCCLUSION_LOCAL_MIN.y, RAIN_OCCLUSION_LOCAL_MAX.y]:
			for local_z in [RAIN_OCCLUSION_LOCAL_MIN.z, RAIN_OCCLUSION_LOCAL_MAX.z]:
				var screen_point := _project_world_point(
					world_3d.platform_rig.to_global(Vector3(local_x, local_y, local_z)),
					output_scale
				)
				bounds_min = bounds_min.min(screen_point)
				bounds_max = bounds_max.max(screen_point)
	# A small feather margin covers railings and avoids a hard screen-space seam.
	bounds_min -= Vector2(10.0, 8.0)
	bounds_max += Vector2(10.0, 8.0)
	bounds_min = bounds_min.clamp(Vector2.ZERO, _layout_viewport_size)
	bounds_max = bounds_max.clamp(Vector2.ZERO, _layout_viewport_size)
	var center_uv := ((bounds_min + bounds_max) * 0.5) / _layout_viewport_size
	var half_size_uv := ((bounds_max - bounds_min) * 0.5) / _layout_viewport_size
	_far_rain_occlusion_rect_uv = Rect2(center_uv - half_size_uv, half_size_uv * 2.0)
	_far_rain_material.set_shader_parameter("platform_occlusion_center", center_uv)
	_far_rain_material.set_shader_parameter("platform_occlusion_half_size", half_size_uv)


func platform_projection_alignment_for_tests() -> Dictionary:
	var expected := _projected_platform_motion()
	return {
		"position_error": platform_board.position.distance_to(_rest_board_position + Vector2(expected.translation)),
		"rotation_error": absf(angle_difference(platform_board.rotation, float(expected.rotation))),
		"scale_error": platform_board.scale.distance_to(Vector2(expected.scale)),
	}


func _apply_weather_to_world() -> void:
	if world_3d == null:
		return
	world_3d.set_weather(
		_sea_intensity,
		_rain_intensity,
		_foam_intensity,
		_splash_intensity,
		_wave_speed,
		_wind_direction,
		_ambient_color,
		_ambient_energy,
		_sun_color,
		_sun_energy,
		_sun_angular_distance,
		_sun_shadow_opacity,
		_deck_wetness
	)
	world_3d.set_powered_presentation(_powered_presentation)
	_apply_far_rain_weather()


func _build_far_rain_veil() -> void:
	_far_rain_veil = ColorRect.new()
	_far_rain_veil.name = "RainFarVeil"
	_far_rain_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_far_rain_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_far_rain_veil.color = Color.WHITE
	_far_rain_material = ShaderMaterial.new()
	if ResourceLoader.exists(FAR_RAIN_SHADER_PATH):
		_far_rain_material.shader = ResourceLoader.load(FAR_RAIN_SHADER_PATH)
	_far_rain_material.set_shader_parameter("viewport_size", Vector2(1280.0, 720.0))
	_far_rain_material.set_shader_parameter("platform_occlusion_center", Vector2(0.5, 0.5))
	_far_rain_material.set_shader_parameter("platform_occlusion_half_size", Vector2.ZERO)
	_far_rain_veil.material = _far_rain_material
	add_child(_far_rain_veil)


func _build_building_highlight() -> void:
	building_highlight_viewport = SubViewport.new()
	building_highlight_viewport.name = "BuildingHighlightViewport"
	building_highlight_viewport.size = world_viewport.size
	building_highlight_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	building_highlight_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	building_highlight_viewport.transparent_bg = true
	building_highlight_viewport.own_world_3d = false
	building_highlight_viewport.gui_disable_input = true
	building_highlight_viewport.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	add_child(building_highlight_viewport)
	_share_building_highlight_world()

	_building_highlight_camera = Camera3D.new()
	_building_highlight_camera.name = "BuildingHighlightCamera"
	_building_highlight_camera.cull_mask = 1 << (BaseWorld3DScript.BUILDING_HIGHLIGHT_VISUAL_LAYER - 1)
	_building_highlight_camera.current = true
	building_highlight_viewport.add_child(_building_highlight_camera)

	# The mask is blurred horizontally into a reusable target. The visible overlay
	# performs only the vertical pass and removes the source core, producing a soft
	# halo with 7/11/15 total texture reads instead of a large square kernel.
	building_highlight_blur_viewport = SubViewport.new()
	building_highlight_blur_viewport.name = "BuildingHighlightBlurViewport"
	building_highlight_blur_viewport.size = building_highlight_viewport.size
	building_highlight_blur_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# The full-rect blend-disabled blur input overwrites every pixel, so this
	# 2D-only pass neither needs a 3D buffer nor a separate target clear.
	building_highlight_blur_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	building_highlight_blur_viewport.transparent_bg = true
	building_highlight_blur_viewport.gui_disable_input = true
	building_highlight_blur_viewport.disable_3d = true
	add_child(building_highlight_blur_viewport)

	_building_highlight_blur_input = TextureRect.new()
	_building_highlight_blur_input.name = "BuildingHighlightBlurInput"
	_building_highlight_blur_input.set_anchors_preset(Control.PRESET_FULL_RECT)
	_building_highlight_blur_input.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_building_highlight_blur_input.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_building_highlight_blur_input.stretch_mode = TextureRect.STRETCH_SCALE
	_building_highlight_blur_input.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_building_highlight_blur_input.texture = building_highlight_viewport.get_texture()
	_building_highlight_blur_material = ShaderMaterial.new()
	if ResourceLoader.exists(BUILDING_HIGHLIGHT_BLUR_SHADER_PATH):
		_building_highlight_blur_material.shader = ResourceLoader.load(BUILDING_HIGHLIGHT_BLUR_SHADER_PATH)
	_building_highlight_blur_material.set_shader_parameter("source_mask", building_highlight_viewport.get_texture())
	_building_highlight_blur_input.material = _building_highlight_blur_material
	building_highlight_blur_viewport.add_child(_building_highlight_blur_input)

	_building_highlight_overlay = TextureRect.new()
	_building_highlight_overlay.name = "BuildingHighlightOutline"
	_building_highlight_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_building_highlight_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_building_highlight_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_building_highlight_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_building_highlight_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_building_highlight_overlay.texture = building_highlight_blur_viewport.get_texture()
	_building_highlight_overlay.visible = false
	_building_highlight_material = ShaderMaterial.new()
	if ResourceLoader.exists(BUILDING_HIGHLIGHT_SHADER_PATH):
		_building_highlight_material.shader = ResourceLoader.load(BUILDING_HIGHLIGHT_SHADER_PATH)
	_building_highlight_material.set_shader_parameter("blurred_mask", building_highlight_blur_viewport.get_texture())
	_building_highlight_material.set_shader_parameter("source_mask", building_highlight_viewport.get_texture())
	_building_highlight_material.set_shader_parameter("glow_color", BUILDING_HIGHLIGHT_COLOR)
	_building_highlight_overlay.material = _building_highlight_material
	add_child(_building_highlight_overlay)
	_apply_viewport_quality()
	_apply_building_highlight_visual(0.0)
	_sync_building_highlight_camera()


func _share_building_highlight_world() -> void:
	if building_highlight_viewport == null or world_viewport == null:
		return
	var shared_world := world_viewport.find_world_3d()
	if shared_world != null and building_highlight_viewport.world_3d != shared_world:
		building_highlight_viewport.world_3d = shared_world


func _sync_building_highlight_camera() -> void:
	if (
		building_highlight_viewport == null
		or _building_highlight_camera == null
		or world_viewport == null
		or world_3d == null
		or world_3d.camera == null
	):
		return
	_share_building_highlight_world()
	building_highlight_viewport.size = Vector2i(maxi(world_viewport.size.x, 2), maxi(world_viewport.size.y, 2))
	if building_highlight_blur_viewport != null:
		building_highlight_blur_viewport.size = building_highlight_viewport.size
	building_highlight_viewport.mesh_lod_threshold = world_viewport.mesh_lod_threshold
	var source := world_3d.camera
	_building_highlight_camera.projection = source.projection
	_building_highlight_camera.keep_aspect = source.keep_aspect
	_building_highlight_camera.size = source.size
	_building_highlight_camera.fov = source.fov
	_building_highlight_camera.near = source.near
	_building_highlight_camera.far = source.far
	_building_highlight_camera.frustum_offset = source.frustum_offset
	_building_highlight_camera.h_offset = source.h_offset
	_building_highlight_camera.v_offset = source.v_offset
	if source.is_inside_tree() and _building_highlight_camera.is_inside_tree():
		_building_highlight_camera.global_transform = source.global_transform
	else:
		# build() is intentionally allowed before BaseEnvironment enters SceneTree.
		# Both cameras have identity spatial parents then, so the local transform is
		# the exact safe equivalent without asking Godot for an invalid global one.
		_building_highlight_camera.transform = source.transform


func _apply_far_rain_quality() -> void:
	if _far_rain_material == null:
		return
	var quality_level := 0 if _graphics_quality == "low" else 1 if _graphics_quality == "medium" else 2
	_far_rain_material.set_shader_parameter("quality_level", quality_level)
	# Low keeps a slightly stronger full-resolution veil so half-resolution 3D
	# cannot erase all sub-pixel rain streaks.
	_far_rain_material.set_shader_parameter("veil_opacity", 0.64 if _graphics_quality == "low" else 0.56 if _graphics_quality == "medium" else 0.48)


func _apply_far_rain_weather() -> void:
	if _far_rain_veil == null or _far_rain_material == null:
		return
	_far_rain_veil.visible = _rain_intensity > 0.025
	_far_rain_material.set_shader_parameter("rain_intensity", _rain_intensity)
	_apply_far_rain_flow()


func _apply_far_rain_flow() -> void:
	if _far_rain_material == null or world_3d == null:
		return
	_far_rain_material.set_shader_parameter("screen_flow", world_3d.rain_screen_flow())


func _configure_daylight_profile(condition_id: String) -> void:
	match condition_id:
		"calm":
			_ambient_color = Color(0.76, 0.80, 0.79)
			_ambient_energy = 0.88
			_sun_color = Color(1.0, 0.93, 0.79)
			_sun_energy = 1.18
			_sun_angular_distance = 0.50
			_sun_shadow_opacity = 0.84
			_deck_wetness = 0.25
		"rough":
			_ambient_color = Color(0.66, 0.71, 0.73)
			_ambient_energy = 1.12
			_sun_color = Color(0.88, 0.92, 0.95)
			_sun_energy = 0.76
			_sun_angular_distance = 0.95
			_sun_shadow_opacity = 0.56
			_deck_wetness = 0.72
		"storm":
			_ambient_color = Color(0.63, 0.69, 0.72)
			_ambient_energy = 1.36
			_sun_color = Color(0.81, 0.87, 0.91)
			_sun_energy = 0.62
			_sun_angular_distance = 1.30
			_sun_shadow_opacity = 0.38
			_deck_wetness = 0.94
		_:
			_ambient_color = Color(0.70, 0.74, 0.75)
			_ambient_energy = 0.98
			_sun_color = Color(0.97, 0.91, 0.82)
			_sun_energy = 0.96
			_sun_angular_distance = 0.70
			_sun_shadow_opacity = 0.72
			_deck_wetness = 0.45
