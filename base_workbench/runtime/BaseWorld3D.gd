class_name BaseWorld3D
extends Node3D

const PLATFORM_MODEL_PATH := "res://base_workbench/assets/platform_3d/start_platform_ruins.glb"
const OCEAN_SHADER_PATH := "res://base_workbench/assets/environment_3d/ocean_surface_3d.gdshader"
const RAIN_COLLISION_CARRIER_SHADER_PATH := "res://base_workbench/assets/environment_3d/rain_collision_carrier.gdshader"
const J7_LIGHT_VFX_SHADER_PATH := "res://base_workbench/assets/environment_3d/j7_directional_light_vfx.gdshader"
const AMBER_LAMP_MATERIAL_NAME := "M_AmberLamp"
const J7_DECK_VFX_COLOR := Color(1.0, 0.82, 0.64)
const J7_DECK_BEAM_WIDTHS: Array[float] = [2.8, 2.7, 2.5]
const J7_DECK_BEAM_LENGTH_FACTOR := 0.98
const J7_DECK_BEAM_OPACITIES: Array[float] = [0.074, 0.074, 0.086]
const J7_DECK_SOURCE_GLOW_OPACITY := 0.74
const J7_DECK_SOURCE_GLOW_SIZE := 0.42
const J7_DECK_SOURCE_CAMERA_OFFSET := 0.09
const J7_DECK_BEAM_CAMERA_OFFSETS: Array[float] = [0.035, 0.035, 0.180]
const J7_DECK_LIGHT_ANCHORS: Array[Vector3] = [
	Vector3(-4.95, 5.30, -8.38),
	Vector3(-0.32, 5.22, -8.36),
	Vector3(4.88, 2.41, -8.53),
]
const J7_DECK_LIGHT_TARGETS: Array[Vector3] = [
	Vector3(-5.70, 0.25, 0.90),
	Vector3(-0.05, 0.25, 0.65),
	Vector3(6.00, 0.25, 0.85),
]

const SLOT_IDS: Array[String] = [
	"top_left",
	"top_center",
	"top_right",
	"bottom_left",
	"center",
	"bottom_right",
]

const SLOT_FALLBACK_POSITIONS := {
	"top_left": Vector3(-8.0, 1.72, -3.25),
	"top_center": Vector3(0.0, 1.72, -3.25),
	"top_right": Vector3(8.0, 1.72, -3.25),
	"bottom_left": Vector3(-8.0, 1.72, 3.45),
	"center": Vector3(0.0, 1.72, 3.45),
	"bottom_right": Vector3(8.0, 1.72, 3.45),
}

const HIGH_OCEAN_SUBDIVISIONS := 160
const MEDIUM_OCEAN_SUBDIVISIONS := 112
const LOW_OCEAN_SUBDIVISIONS := 72

# x = amplitude, y = wavelength, z = speed response, w = angle from wind.
# The first two components are the buoyancy-scale field shared by the shader and
# the heavy platform. The third component is surface chop: it can contribute to
# contact energy, but it never directly drives the platform transform.
const OCEAN_WAVE_COMPONENTS: Array[Vector4] = [
	Vector4(0.30, 16.5, 0.76, 0.0),
	Vector4(0.17, 8.2, 0.94, 0.58),
	Vector4(0.085, 4.3, 1.12, -1.04),
]
const OCEAN_WAVE_STEEPNESS_WEIGHTS: Array[float] = [1.0, 0.78, 0.58]
const OCEAN_SCATTERING_TRANSMISSION_LOSS := Vector2(0.40, 0.56)
const OCEAN_SCATTERING_REFLECTION_STRENGTH := Vector2(0.27, 0.18)
const OCEAN_SCATTERING_LEE_RETENTION := Vector4(0.68, 0.58, 0.42, 0.70)
const OCEAN_SCATTERING_IMPACT_FOAM_STRENGTH := 0.72
const OCEAN_SCATTERING_REFLECTED_FOAM_STRENGTH := 0.34
const BUOYANCY_HALF_WIDTH := 8.4
const BUOYANCY_HALF_DEPTH := 5.4
const SPRAY_ANCHORS: Array[Vector3] = [
	Vector3(-9.6, 0.18, 6.4),
	Vector3(-4.7, 0.18, 7.3),
	Vector3(1.0, 0.18, 7.55),
	Vector3(6.8, 0.18, 7.2),
	Vector3(10.0, 0.18, 5.1),
	Vector3(10.2, 0.18, -2.1),
	Vector3(-10.2, 0.18, -1.6),
	Vector3(-9.8, 0.18, 3.0),
]

const RAIN_MID_AMOUNTS := {"low": 500, "medium": 1100, "high": 1900}
const RAIN_NEAR_AMOUNTS := {"low": 140, "medium": 330, "high": 720}
const RAIN_MID_CONTACT_IMPACT_AMOUNTS := {"low": 190, "medium": 420, "high": 720}
const RAIN_NEAR_CONTACT_IMPACT_AMOUNTS := {"low": 45, "medium": 100, "high": 200}
const RAIN_MID_TERMINAL_SPEED := Vector2(5.8, 9.4)
const RAIN_NEAR_TERMINAL_SPEED := Vector2(7.0, 10.0)
const RAIN_CONTACT_IMPACT_LIFETIME := 0.42
const RAIN_MID_CONTACT_EMISSION_FRACTION := 0.34
const RAIN_NEAR_CONTACT_EMISSION_FRACTION := 0.58
const RAIN_GUST_PRIMARY_SPEED := 0.63
const RAIN_GUST_SECONDARY_SPEED := 1.37
const RAIN_PARTICLE_VISUAL_LAYER := 1
const RAIN_COLLISION_VISUAL_LAYER := 2
const BUILDING_HIGHLIGHT_VISUAL_LAYER := 20
# Emitters are back-projected from the visible contact footprint. Their XZ
# anchors are updated from the current gusted trajectory, so newly born drops
# arrive in-frame instead of forming a screen-like curtain that expires beyond
# the lower edge. Vector2.y maps to world Z in these XZ constants.
const RAIN_MID_CONTACT_CENTER_XZ := Vector2(0.0, -4.647)
const RAIN_MID_CONTACT_REFERENCE_Y := -0.12
const RAIN_MID_EMITTER_HEIGHT := 8.875
const RAIN_MID_EMISSION_EXTENTS := Vector3(13.5, 1.125, 14.0)
const RAIN_MID_VISIBILITY_AABB := AABB(Vector3(-28.0, -21.25, -28.0), Vector3(56.0, 22.75, 56.0))
const RAIN_NEAR_CONTACT_CENTER_XZ := Vector2(0.0, 1.0)
const RAIN_NEAR_CONTACT_REFERENCE_Y := 1.0
const RAIN_NEAR_EMITTER_HEIGHT := 9.875
const RAIN_NEAR_EMISSION_EXTENTS := Vector3(9.0, 2.125, 8.0)
const RAIN_NEAR_VISIBILITY_AABB := AABB(Vector3(-23.0, -29.5, -22.0), Vector3(46.0, 32.0, 44.0))
const RAIN_HEIGHTFIELD_POSITION := Vector3(0.0, 8.0, 6.0)
const RAIN_HEIGHTFIELD_SIZE := Vector3(56.0, 24.0, 68.0)

var camera: Camera3D
var platform_rig: Node3D
var ocean: MeshInstance3D

var _world_environment: WorldEnvironment
var _environment: Environment
var _sun: DirectionalLight3D
var _ocean_material: ShaderMaterial
var _rain_particles: GPUParticles3D
var _rain_process_material: ShaderMaterial
var _rain_near_particles: GPUParticles3D
var _rain_near_process_material: ShaderMaterial
var _rain_contact_impacts: GPUParticles3D
var _rain_near_contact_impacts: GPUParticles3D
var _rain_collision_heightfield: GPUParticlesCollisionHeightField3D
var _rain_deck_collision_proxy: MeshInstance3D
var _spray_emitters: Array[GPUParticles3D] = []
var _spray_process_materials: Array[ParticleProcessMaterial] = []
var _platform_asset: Node3D
var _ruin_nodes: Dictionary = {}
var _building_nodes: Dictionary = {}
var _slot_anchor_nodes: Dictionary = {}
var _slot_states: Dictionary = {}
var _highlighted_slot_id := ""
var _highlight_layer_restore: Dictionary = {}
var _wet_material_entries: Array[Dictionary] = []
var _wet_source_records: Dictionary = {}
var _wet_bindings_by_branch: Dictionary = {}
var _wet_installed_branches: Dictionary = {}
var _amber_lamp_records: Dictionary = {}
var _deck_light_mounts: Array[Marker3D] = []
var _deck_light_beams: Array[MeshInstance3D] = []
var _deck_light_source_glows: Array[MeshInstance3D] = []
var _current_deck_wetness := 0.0
var _last_applied_wetness := -1.0
var _graphics_quality := "high"
var _reduced_motion := false
var _ocean_scattering_enabled := true
var _sea_intensity := 0.56
var _rain_intensity := 0.52
var _foam_intensity := 0.46
var _splash_intensity := 0.38
var _wave_speed_scale := 0.90
var _wind_direction := Vector2(0.76, 0.65).normalized()
var _rain_flow_time := 0.0
var _sun_angular_distance := 0.70
var _powered_presentation := false
var _last_platform_wave_motion := {
	"heave": 0.0,
	"horizontal_offset": Vector2.ZERO,
	"roll": 0.0,
	"pitch": 0.0,
	"contact_energy": 0.0,
	"contact_energy_sides": Vector4.ZERO,
	"pontoon_contact_energy_a": Vector4.ZERO,
	"pontoon_contact_energy_b": Vector4.ZERO,
	"impact_energy": 0.0,
	"impact_side": 0,
	"left_height": 0.0,
	"right_height": 0.0,
	"front_height": 0.0,
	"back_height": 0.0,
	"raw_roll": 0.0,
	"raw_pitch": 0.0,
}
var _built := false


func build() -> void:
	if _built:
		return
	_built = true
	name = "BaseWorld3D"
	_build_environment()
	_build_ocean()
	_build_platform()
	_cache_wet_materials_recursive(_platform_asset)
	_install_active_wet_branches()
	_cache_amber_lamp_materials_recursive(_platform_asset)
	_suppress_amber_lamp_emission()
	_build_rain()
	_build_spray()
	_build_camera()
	_build_powered_deck_vfx()
	_apply_graphics_quality()
	_apply_weather()


func set_viewport_size(viewport_size: Vector2) -> void:
	if camera == null or viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	# A fixed orthographic composition keeps the six gameplay hit regions stable
	# across aspect ratios while the surrounding sea absorbs letterboxing.
	var aspect := viewport_size.x / viewport_size.y
	# The accepted 2.5D composition fills a 16:9 frame with the complete hull,
	# mast and crane still inside the safe image area. Narrow viewports receive a
	# little more headroom, while the canonical 1672x941/16:9 view stays tight.
	camera.size = lerpf(20.5, 18.0, clampf((aspect - 1.25) / 0.53, 0.0, 1.0))
	_fit_rain_emitters_to_camera(viewport_size)


func set_graphics_quality(quality_id: String) -> void:
	_graphics_quality = quality_id if quality_id in ["low", "medium", "high"] else "high"
	if _built:
		_apply_graphics_quality()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if _ocean_material != null:
		# Ocean and platform motion communicate the actual WeatherState and remain
		# active under reduced motion. The flag is kept for shader-compatible
		# suppression of purely decorative micro-noise only.
		_ocean_material.set_shader_parameter("reduced_motion", enabled)


func set_powered_presentation(enabled: bool) -> void:
	if _powered_presentation == enabled:
		return
	_powered_presentation = enabled
	_apply_powered_deck_vfx()


func set_ocean_scattering_enabled(enabled: bool) -> void:
	# Directional platform scattering is a presentation-only layer. Keeping the
	# switch here gives the deterministic capture harness a clean A/B control
	# without changing the canonical CPU wave field or platform motion.
	_ocean_scattering_enabled = enabled
	if _ocean_material != null:
		_ocean_material.set_shader_parameter("platform_scattering_enabled", enabled)


func set_weather(
	sea_intensity: float,
	rain_intensity: float,
	foam_intensity: float,
	splash_intensity: float,
	wave_speed_scale: float,
	wind_direction: Vector2,
	ambient_color: Color,
	ambient_energy: float,
	sun_color: Color,
	sun_energy: float,
	sun_angular_distance: float,
	sun_shadow_opacity: float,
	deck_wetness: float
) -> void:
	_sea_intensity = clampf(sea_intensity, 0.0, 1.0)
	_rain_intensity = clampf(rain_intensity, 0.0, 1.0)
	_foam_intensity = clampf(foam_intensity, 0.0, 1.0)
	_splash_intensity = clampf(splash_intensity, 0.0, 1.0)
	_wave_speed_scale = clampf(wave_speed_scale, 0.5, 1.5)
	_wind_direction = wind_direction.normalized() if wind_direction.length_squared() > 0.001 else Vector2(0.76, 0.65).normalized()
	if _environment != null:
		_environment.ambient_light_color = ambient_color
		_environment.ambient_light_energy = clampf(ambient_energy, 0.0, 2.0)
		_environment.fog_light_color = ambient_color.lerp(Color(0.54, 0.66, 0.70), 0.44)
	if _sun != null:
		_sun.light_color = sun_color
		_sun.light_energy = maxf(sun_energy, 0.0)
		_sun.shadow_opacity = clampf(sun_shadow_opacity, 0.0, 1.0)
	_sun_angular_distance = clampf(sun_angular_distance, 0.0, 2.0)
	_apply_sun_shadow_quality()
	_apply_weather()
	_apply_cached_wetness(deck_wetness)


func apply_motion(
	current_time: float,
	heave: float,
	horizontal_offset: Vector2,
	roll_radians: float,
	pitch_radians: float,
	contact_energy: float,
	contact_energy_sides: Vector4,
	pontoon_contact_energy_a: Vector4,
	pontoon_contact_energy_b: Vector4
) -> void:
	if platform_rig == null:
		return
	platform_rig.position = Vector3(horizontal_offset.x, heave, horizontal_offset.y)
	platform_rig.rotation = Vector3(pitch_radians, 0.0, roll_radians)
	if _ocean_material != null:
		_ocean_material.set_shader_parameter("time_override", current_time)
		_ocean_material.set_shader_parameter("platform_position_xz", horizontal_offset)
		_ocean_material.set_shader_parameter("platform_contact_energy", clampf(contact_energy, 0.0, 1.0))
		_ocean_material.set_shader_parameter("platform_contact_energy_sides", contact_energy_sides.clamp(Vector4.ZERO, Vector4.ONE))
		_ocean_material.set_shader_parameter("pontoon_contact_energy_a", pontoon_contact_energy_a.clamp(Vector4.ZERO, Vector4.ONE))
		_ocean_material.set_shader_parameter("pontoon_contact_energy_b", pontoon_contact_energy_b.clamp(Vector4.ZERO, Vector4.ONE))
	_update_rain_flow(current_time)


func rain_screen_flow() -> Vector2:
	if camera == null or _rain_process_material == null:
		return Vector2.DOWN
	# Project the same current world-space velocity used by the mid-field drops
	# into the camera plane. Canvas Y points down, hence the negated view-space Y.
	var camera_basis := camera.global_transform.basis if camera.is_inside_tree() else camera.transform.basis
	var rain_direction := Vector3(_rain_process_material.get_shader_parameter("direction"))
	var view_direction := camera_basis.inverse() * rain_direction
	var screen_flow := Vector2(view_direction.x, -view_direction.y)
	if screen_flow.length_squared() <= 0.0001:
		return Vector2.DOWN
	return screen_flow.normalized()


func sample_platform_wave_motion(current_time: float, motion_intensity: float) -> Dictionary:
	# The platform and shader use the same three analytical Gerstner components.
	# A weighted five-point footprint average acts as deterministic hull inertia:
	# it suppresses short chop without a frame-history-dependent physics spring.
	var centre := _sample_wave_field(Vector2.ZERO, current_time, 2)
	var left := _sample_wave_field(Vector2(-BUOYANCY_HALF_WIDTH, 0.0), current_time, 2)
	var right := _sample_wave_field(Vector2(BUOYANCY_HALF_WIDTH, 0.0), current_time, 2)
	var front := _sample_wave_field(Vector2(0.0, BUOYANCY_HALF_DEPTH), current_time, 2)
	var back := _sample_wave_field(Vector2(0.0, -BUOYANCY_HALF_DEPTH), current_time, 2)
	var response := lerpf(0.48, 1.20, clampf(motion_intensity / 1.20, 0.0, 1.0))
	var edge_height := (float(left.height) + float(right.height) + float(front.height) + float(back.height)) * 0.25
	var edge_vertical_velocity := (
		float(left.vertical_velocity) + float(right.vertical_velocity)
		+ float(front.vertical_velocity) + float(back.vertical_velocity)
	) * 0.25
	var heave := (float(centre.height) * 0.68 + edge_height * 0.32) * response
	var hull_vertical_velocity := (
		float(centre.vertical_velocity) * 0.68 + edge_vertical_velocity * 0.32
	) * response
	var horizontal := Vector2(centre.horizontal_offset) * response * 0.22
	# In Godot's axes a positive Z rotation raises +X, while a positive X
	# rotation lowers +Z. The signs therefore follow right-left and back-front,
	# so the edge currently carried by the wave rises with the sampled surface.
	var raw_roll := atan2(float(right.height) - float(left.height), BUOYANCY_HALF_WIDTH * 2.0) * response * 0.72
	var raw_pitch := atan2(float(back.height) - float(front.height), BUOYANCY_HALF_DEPTH * 2.0) * response * 0.68
	heave = clampf(heave, -0.62, 0.62)
	horizontal = horizontal.limit_length(0.13)
	var roll := _soft_limit_angle(raw_roll, deg_to_rad(2.5))
	var pitch := _soft_limit_angle(raw_pitch, deg_to_rad(1.9))

	var contact_samples := [front, right, back, left]
	var max_velocity := 0.0
	var max_rising_impact := 0.0
	var impact_side := 0
	var min_height := INF
	var max_height := -INF
	var side_contact_values: Array[float] = []
	var buoyancy_amplitude := (OCEAN_WAVE_COMPONENTS[0].x + OCEAN_WAVE_COMPONENTS[1].x) * _wave_amplitude_scale()
	var contact_weather_base := 0.06 + _foam_intensity * 0.19 + _sea_intensity * 0.12
	for side_index in range(contact_samples.size()):
		var sample: Dictionary = contact_samples[side_index]
		var signed_velocity := float(sample.vertical_velocity)
		var relative_velocity := signed_velocity - hull_vertical_velocity
		max_velocity = maxf(max_velocity, absf(relative_velocity))
		var height_factor := clampf(float(sample.height) / maxf(buoyancy_amplitude, 0.001) * 0.5 + 0.5, 0.0, 1.0)
		var rising_impact := maxf(relative_velocity, 0.0) * (0.55 + height_factor * 0.45)
		var height_excess := maxf(float(sample.height) - heave, 0.0)
		side_contact_values.append(clampf(
			contact_weather_base + absf(relative_velocity) * 0.20
			+ rising_impact * 0.34 + height_excess * 0.24,
			0.0,
			1.0
		))
		if rising_impact > max_rising_impact:
			max_rising_impact = rising_impact
			impact_side = side_index
		min_height = minf(min_height, float(sample.height))
		max_height = maxf(max_height, float(sample.height))
	var edge_spread := max_height - min_height
	var contact_energy := clampf(
		0.10 + _foam_intensity * 0.28 + _sea_intensity * 0.16 + edge_spread * 0.42 + max_velocity * 0.09,
		0.0,
		1.0
	)
	# Only rising water can arm a burst. Using absolute velocity at all four sides
	# kept rough/storm energy permanently high and allowed just one splash ever.
	var impact_energy := clampf((max_rising_impact - 0.08) * 1.05 + edge_spread * 0.16, 0.0, 1.0)
	var pontoon_contact_values: Array[float] = []
	for anchor in SPRAY_ANCHORS:
		var pontoon_sample := _sample_wave_field(Vector2(anchor.x, anchor.z), current_time, 3)
		var relative_velocity := float(pontoon_sample.vertical_velocity) - hull_vertical_velocity
		var pontoon_height_excess := maxf(float(pontoon_sample.height) - heave, 0.0)
		var pontoon_height_factor := clampf(
			float(pontoon_sample.height) / maxf(buoyancy_amplitude, 0.001) * 0.5 + 0.5,
			0.0,
			1.0
		)
		var pontoon_rising_impact := maxf(relative_velocity, 0.0) * (0.55 + pontoon_height_factor * 0.45)
		pontoon_contact_values.append(clampf(
			contact_weather_base + absf(relative_velocity) * 0.18
			+ pontoon_rising_impact * 0.38 + pontoon_height_excess * 0.28,
			0.0,
			1.0
		))
	var side_contact_energy := Vector4(
		side_contact_values[0], side_contact_values[1],
		side_contact_values[2], side_contact_values[3]
	)
	var pontoon_contact_energy_a := Vector4(
		pontoon_contact_values[0], pontoon_contact_values[1],
		pontoon_contact_values[2], pontoon_contact_values[3]
	)
	var pontoon_contact_energy_b := Vector4(
		pontoon_contact_values[4], pontoon_contact_values[5],
		pontoon_contact_values[6], pontoon_contact_values[7]
	)
	_last_platform_wave_motion = {
		"heave": heave,
		"horizontal_offset": horizontal,
		"roll": roll,
		"pitch": pitch,
		"contact_energy": contact_energy,
		"contact_energy_sides": side_contact_energy,
		"pontoon_contact_energy_a": pontoon_contact_energy_a,
		"pontoon_contact_energy_b": pontoon_contact_energy_b,
		"impact_energy": impact_energy,
		"impact_side": impact_side,
		"left_height": float(left.height),
		"right_height": float(right.height),
		"front_height": float(front.height),
		"back_height": float(back.height),
		"raw_roll": raw_roll,
		"raw_pitch": raw_pitch,
		"hull_vertical_velocity": hull_vertical_velocity,
	}
	return _last_platform_wave_motion.duplicate()


func _soft_limit_angle(value: float, limit: float) -> float:
	if limit <= 0.0:
		return 0.0
	# Preserve small, heavy movements exactly. Above the knee, approach the
	# safety limit with a continuous slope instead of sitting on a hard plateau.
	const LINEAR_KNEE := 0.65
	var normalized := absf(value) / limit
	if normalized <= LINEAR_KNEE:
		return value
	var eased := LINEAR_KNEE + (1.0 - LINEAR_KNEE) * (
		1.0 - exp(-(normalized - LINEAR_KNEE) / (1.0 - LINEAR_KNEE))
	)
	return signf(value) * limit * eased


func _sample_wave_field(world_xz: Vector2, current_time: float, component_count: int) -> Dictionary:
	var height := 0.0
	var horizontal_offset := Vector2.ZERO
	var vertical_velocity := 0.0
	var amplitude_scale := _wave_amplitude_scale()
	var safe_steepness := lerpf(0.58, 0.72, _sea_intensity)
	var active_count := mini(component_count, OCEAN_WAVE_COMPONENTS.size())
	for index in range(active_count):
		var component: Vector4 = OCEAN_WAVE_COMPONENTS[index]
		var direction := _wind_direction.rotated(component.w).normalized()
		var wave_number := TAU / maxf(component.y, 0.05)
		var angular_frequency := sqrt(9.81 * wave_number) * component.z * _wave_speed_scale
		var phase := wave_number * direction.dot(world_xz) - angular_frequency * current_time
		var amplitude := component.x * amplitude_scale
		height += amplitude * sin(phase)
		horizontal_offset += direction * (
			safe_steepness * OCEAN_WAVE_STEEPNESS_WEIGHTS[index] * amplitude * cos(phase)
		)
		vertical_velocity -= amplitude * angular_frequency * cos(phase)
	return {
		"height": height,
		"horizontal_offset": horizontal_offset,
		"vertical_velocity": vertical_velocity,
	}


func _wave_amplitude_scale() -> float:
	return lerpf(0.70, 1.10, _sea_intensity)


func set_slot_state(slot_id: String, is_built: bool, level: int = 0) -> void:
	if not SLOT_IDS.has(slot_id):
		return
	_slot_states[slot_id] = {"is_built": is_built, "level": clampi(level, 0, 4)}
	_apply_slot_state(slot_id)


func set_building_highlight(slot_id: String) -> bool:
	var normalized_slot_id := slot_id if SLOT_IDS.has(slot_id) else ""
	if normalized_slot_id == _highlighted_slot_id and not _highlight_layer_restore.is_empty():
		return true
	_restore_building_highlight_layers()
	_highlighted_slot_id = normalized_slot_id
	_apply_building_highlight_layers()
	return not _highlight_layer_restore.is_empty()


func clear_building_highlight() -> void:
	_restore_building_highlight_layers()
	_highlighted_slot_id = ""


func building_highlight_state_for_tests() -> Dictionary:
	var mesh_states: Array[Dictionary] = []
	for entry_value in _highlight_layer_restore.values():
		var entry: Dictionary = entry_value
		var mesh := entry.get("mesh") as MeshInstance3D
		if mesh == null or not is_instance_valid(mesh):
			continue
		mesh_states.append({
			"node_name": str(mesh.name),
			"node_path": str(mesh.get_path()) if mesh.is_inside_tree() else str(mesh.name),
			"layers_before": int(entry.get("layers", 0)),
			"layers": int(mesh.layers),
			"highlight_layer": mesh.get_layer_mask_value(BUILDING_HIGHLIGHT_VISUAL_LAYER),
			"rain_collision_layer": mesh.get_layer_mask_value(RAIN_COLLISION_VISUAL_LAYER),
			"gameplay_layer": mesh.get_layer_mask_value(RAIN_PARTICLE_VISUAL_LAYER),
		})
	return {
		"active": not _highlight_layer_restore.is_empty(),
		"slot_id": _highlighted_slot_id,
		"visual_layer": BUILDING_HIGHLIGHT_VISUAL_LAYER,
		"mesh_count": mesh_states.size(),
		"meshes": mesh_states,
	}


func trigger_splash_group(impact_side: int, event_seed: int = 41_159) -> void:
	if _spray_emitters.is_empty() or _graphics_quality == "low" or _splash_intensity < 0.08:
		return
	# front, right, back, left. Each event now starts at the hull side whose
	# sampled wave velocity is strongest. A deterministic per-event seed rotates
	# the local anchors and particle pattern without repeating the same splash.
	var groups := [[0, 1, 2, 3, 4, 7], [3, 4, 5], [5, 6], [6, 7, 0]]
	var selected: Array = groups[posmod(impact_side, groups.size())]
	var amount_scale := 0.55 if _graphics_quality == "medium" else 1.0
	var count := clampi(int(ceil(float(selected.size()) * _splash_intensity)), 1, selected.size())
	var start_index := posmod(event_seed, selected.size())
	for offset in range(count):
		var selected_index := (start_index + offset) % selected.size()
		var emitter_index := int(selected[selected_index])
		var emitter: GPUParticles3D = _spray_emitters[emitter_index]
		emitter.use_fixed_seed = true
		emitter.seed = posmod(event_seed + emitter_index * 977, 2_147_483_647)
		emitter.amount_ratio = clampf(_splash_intensity * amount_scale, 0.12, 1.0)
		emitter.restart()
		emitter.emitting = true


func state_for_tests() -> Dictionary:
	var ruin_visibility := {}
	var building_visibility := {}
	var wet_material_min_roughness := 1.0
	var wet_material_max_clearcoat := 0.0
	var amber_lamp_emission_energy := 0.0
	var amber_lamp_emission_enabled := false
	var deck_light_mount_parented_count := 0
	var deck_light_anchor_match_count := 0
	var deck_light_aim_alignment_min := 1.0
	var deck_light_local_light_count := 0
	var deck_light_beam_end_clearance_min := INF
	var deck_light_beam_end_clearance_max := 0.0
	var deck_light_beam_visible_count := 0
	var deck_light_beam_parented_count := 0
	var deck_light_source_glow_visible_count := 0
	var deck_light_source_glow_parented_count := 0
	var deck_light_vfx_shadow_casting_count := 0
	var deck_light_fixture_geometry_count := 0
	var deck_light_vfx_geometry_count := 0
	var light_scope: Node = get_parent() if get_parent() != null else self
	var light_count := light_scope.find_children("*", "Light3D", true, false).size()
	var spot_light_count := light_scope.find_children("*", "SpotLight3D", true, false).size()
	var omni_light_count := light_scope.find_children("*", "OmniLight3D", true, false).size()
	var directional_light_count := 0
	var shadow_casting_directional_light_count := 0
	for light_node in find_children("*", "DirectionalLight3D", true, false):
		directional_light_count += 1
		if (light_node as DirectionalLight3D).shadow_enabled:
			shadow_casting_directional_light_count += 1
	var model_mesh_count := 0
	var sun_lit_model_mesh_count := 0
	var sun_shadow_casting_model_mesh_count := 0
	if _platform_asset != null and _sun != null:
		for mesh_node in _platform_asset.find_children("*", "MeshInstance3D", true, false):
			var model_mesh := mesh_node as MeshInstance3D
			model_mesh_count += 1
			if (int(model_mesh.layers) & int(_sun.light_cull_mask)) != 0:
				sun_lit_model_mesh_count += 1
			if (int(model_mesh.layers) & int(_sun.shadow_caster_mask)) != 0 and model_mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				sun_shadow_casting_model_mesh_count += 1
	var spray_emitting_count := 0
	for emitter in _spray_emitters:
		if emitter.emitting:
			spray_emitting_count += 1
	for wet_entry in _wet_material_entries:
		var wet_material: BaseMaterial3D = wet_entry.runtime
		wet_material_min_roughness = minf(wet_material_min_roughness, wet_material.roughness)
		wet_material_max_clearcoat = maxf(wet_material_max_clearcoat, wet_material.clearcoat)
	for amber_entry_value in _amber_lamp_records.values():
		var amber_entry: Dictionary = amber_entry_value
		var amber_material := amber_entry.get("runtime") as BaseMaterial3D
		if amber_material == null:
			continue
		amber_lamp_emission_energy = maxf(amber_lamp_emission_energy, amber_material.emission_energy_multiplier)
		amber_lamp_emission_enabled = amber_lamp_emission_enabled or amber_material.emission_enabled
	if platform_rig != null:
		for child in platform_rig.get_children():
			if str(child.name).begins_with("J7DeckFixture"):
				if child is GeometryInstance3D:
					deck_light_fixture_geometry_count += 1
				deck_light_fixture_geometry_count += child.find_children("*", "GeometryInstance3D", true, false).size()
			elif str(child.name).begins_with("J7DeckLightMount"):
				deck_light_vfx_geometry_count += child.find_children("*", "GeometryInstance3D", true, false).size()
	for index in range(_deck_light_mounts.size()):
		var deck_light_mount := _deck_light_mounts[index]
		if deck_light_mount == null:
			deck_light_aim_alignment_min = -1.0
			continue
		if deck_light_mount.get_parent() == platform_rig:
			deck_light_mount_parented_count += 1
		deck_light_local_light_count += deck_light_mount.find_children("*", "Light3D", true, false).size()
		if index >= J7_DECK_LIGHT_ANCHORS.size() or index >= J7_DECK_LIGHT_TARGETS.size():
			deck_light_aim_alignment_min = -1.0
			continue
		var anchor := J7_DECK_LIGHT_ANCHORS[index]
		if deck_light_mount.position.is_equal_approx(anchor):
			deck_light_anchor_match_count += 1
	for index in range(_deck_light_beams.size()):
		var beam := _deck_light_beams[index]
		if beam == null:
			continue
		if beam.visible:
			deck_light_beam_visible_count += 1
		if index < _deck_light_mounts.size() and beam.get_parent() == _deck_light_mounts[index]:
			deck_light_beam_parented_count += 1
		if index < J7_DECK_LIGHT_ANCHORS.size() and index < J7_DECK_LIGHT_TARGETS.size():
			var anchor := J7_DECK_LIGHT_ANCHORS[index]
			var target := J7_DECK_LIGHT_TARGETS[index]
			var expected_direction := (target - anchor).normalized()
			var actual_direction := (beam.basis * Vector3.DOWN).normalized()
			deck_light_aim_alignment_min = minf(
				deck_light_aim_alignment_min,
				actual_direction.dot(expected_direction)
			)
			var beam_quad := beam.mesh as QuadMesh
			if beam_quad != null:
				var end_clearance := anchor.distance_to(target) - beam_quad.size.y
				deck_light_beam_end_clearance_min = minf(deck_light_beam_end_clearance_min, end_clearance)
				deck_light_beam_end_clearance_max = maxf(deck_light_beam_end_clearance_max, end_clearance)
		if beam.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			deck_light_vfx_shadow_casting_count += 1
	for index in range(_deck_light_source_glows.size()):
		var source_glow := _deck_light_source_glows[index]
		if source_glow == null:
			continue
		if source_glow.visible:
			deck_light_source_glow_visible_count += 1
		if index < _deck_light_mounts.size() and source_glow.get_parent() == _deck_light_mounts[index]:
			deck_light_source_glow_parented_count += 1
		if source_glow.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			deck_light_vfx_shadow_casting_count += 1
	for slot_id in SLOT_IDS:
		var ruin: Node3D = _ruin_nodes.get(slot_id)
		ruin_visibility[slot_id] = ruin != null and ruin.visible
		var levels: Dictionary = _building_nodes.get(slot_id, {})
		building_visibility[slot_id] = {}
		for level in levels.keys():
			var level_node: Node3D = levels[level]
			building_visibility[slot_id][level] = level_node.visible
	return {
		"model_loaded": _platform_asset != null,
		"ruin_count": _ruin_nodes.size(),
		"slot_anchor_count": _slot_anchor_nodes.size(),
		"ruin_visibility": ruin_visibility,
		"building_visibility": building_visibility,
		"building_highlight": building_highlight_state_for_tests(),
		"quality": _graphics_quality,
		"ocean_subdivisions": _ocean_subdivisions_for_quality(),
		"rain_amount": _rain_particles.amount if _rain_particles != null else 0,
		"rain_near_amount": _rain_near_particles.amount if _rain_near_particles != null else 0,
		"rain_air_emitting": _rain_particles != null and _rain_near_particles != null and _rain_particles.emitting and _rain_near_particles.emitting,
		"rain_amount_ratio": _rain_particles.amount_ratio if _rain_particles != null else 0.0,
		"rain_near_amount_ratio": _rain_near_particles.amount_ratio if _rain_near_particles != null else 0.0,
		"rain_mid_emitter_position": _rain_particles.position if _rain_particles != null else Vector3.ZERO,
		"rain_near_emitter_position": _rain_near_particles.position if _rain_near_particles != null else Vector3.ZERO,
		"rain_mid_emission_extents": Vector3(_rain_process_material.get_shader_parameter("emission_box_extents")) if _rain_process_material != null else Vector3.ZERO,
		"rain_near_emission_extents": Vector3(_rain_near_process_material.get_shader_parameter("emission_box_extents")) if _rain_near_process_material != null else Vector3.ZERO,
		"rain_mid_contact_center_xz": RAIN_MID_CONTACT_CENTER_XZ,
		"rain_near_contact_center_xz": RAIN_NEAR_CONTACT_CENTER_XZ,
		"rain_surface_visible": (
			_rain_intensity > 0.025
			and _rain_contact_impacts != null and _rain_contact_impacts.visible
			and _rain_near_contact_impacts != null and _rain_near_contact_impacts.visible
			and _rain_collision_heightfield != null and _rain_collision_heightfield.cull_mask != 0
		),
		"rain_ocean_ripples_enabled": _ocean_material != null and _graphics_quality != "low" and _rain_intensity > 0.12,
		"rain_contact_enabled": (
			_rain_intensity > 0.025
			and _rain_contact_impacts != null and _rain_contact_impacts.visible
			and _rain_near_contact_impacts != null and _rain_near_contact_impacts.visible
			and _rain_collision_heightfield != null and _rain_collision_heightfield.cull_mask != 0
		),
		"rain_contact_subemitter_emitting": (
			(_rain_contact_impacts != null and _rain_contact_impacts.emitting)
			or (_rain_near_contact_impacts != null and _rain_near_contact_impacts.emitting)
		),
		"rain_contact_amount": (
			(_rain_contact_impacts.amount if _rain_contact_impacts != null else 0)
			+ (_rain_near_contact_impacts.amount if _rain_near_contact_impacts != null else 0)
		),
		"rain_mid_contact_amount": _rain_contact_impacts.amount if _rain_contact_impacts != null else 0,
		"rain_near_contact_amount": _rain_near_contact_impacts.amount if _rain_near_contact_impacts != null else 0,
		"rain_collision_resolution": int(_rain_collision_heightfield.resolution) if _rain_collision_heightfield != null else -1,
		"rain_collision_update_mode": int(_rain_collision_heightfield.update_mode) if _rain_collision_heightfield != null else -1,
		"rain_collision_size": _rain_collision_heightfield.size if _rain_collision_heightfield != null else Vector3.ZERO,
		"rain_deck_proxy_enabled": _rain_deck_collision_proxy != null and _rain_deck_collision_proxy.visible,
		"rain_ocean_ripple_response": _rain_intensity if _ocean_material != null and _graphics_quality != "low" and _rain_intensity > 0.12 else 0.0,
		"rain_screen_flow": rain_screen_flow(),
		"spray_visible": not _spray_emitters.is_empty() and _spray_emitters[0].visible,
		"spray_emitting_count": spray_emitting_count,
		"fog_enabled": _environment != null and _environment.fog_enabled,
		"volumetric_fog_enabled": _environment != null and _environment.volumetric_fog_enabled,
		"tonemap_mode": int(_environment.tonemap_mode) if _environment != null else -1,
		"tonemap_exposure": _environment.tonemap_exposure if _environment != null else 0.0,
		"tonemap_white": _environment.tonemap_white if _environment != null else 0.0,
		"ambient_source": int(_environment.ambient_light_source) if _environment != null else -1,
		"ambient_color": _environment.ambient_light_color if _environment != null else Color.BLACK,
		"ambient_energy": _environment.ambient_light_energy if _environment != null else 0.0,
		"ssao_intensity": _environment.ssao_intensity if _environment != null else 0.0,
		"light_count": light_count,
		"spot_light_count": spot_light_count,
		"omni_light_count": omni_light_count,
		"directional_light_count": directional_light_count,
		"shadow_casting_directional_light_count": shadow_casting_directional_light_count,
		"sun_name": _sun.name if _sun != null else "",
		"sun_energy": _sun.light_energy if _sun != null else 0.0,
		"sun_color": _sun.light_color if _sun != null else Color.BLACK,
		"sun_direction": (_sun.global_transform.basis * Vector3.FORWARD).normalized() if _sun != null else Vector3.ZERO,
		"sun_rotation_degrees": _sun.rotation_degrees if _sun != null else Vector3.ZERO,
		"sun_shadow_enabled": _sun != null and _sun.shadow_enabled,
		"sun_sky_mode": int(_sun.sky_mode) if _sun != null else -1,
		"sun_shadow_mode": int(_sun.directional_shadow_mode) if _sun != null else -1,
		"sun_shadow_blend_splits": _sun != null and _sun.directional_shadow_blend_splits,
		"sun_light_cull_mask": _sun.light_cull_mask if _sun != null else 0,
		"sun_shadow_caster_mask": _sun.shadow_caster_mask if _sun != null else 0,
		"model_mesh_count": model_mesh_count,
		"sun_lit_model_mesh_count": sun_lit_model_mesh_count,
		"sun_shadow_casting_model_mesh_count": sun_shadow_casting_model_mesh_count,
		"shadow_max_distance": _sun.directional_shadow_max_distance if _sun != null else 0.0,
		"shadow_fade_start": _sun.directional_shadow_fade_start if _sun != null else 0.0,
		"shadow_split_1": _sun.directional_shadow_split_1 if _sun != null else 0.0,
		"shadow_split_2": _sun.directional_shadow_split_2 if _sun != null else 0.0,
		"shadow_split_3": _sun.directional_shadow_split_3 if _sun != null else 0.0,
		"shadow_angular_distance": _sun.light_angular_distance if _sun != null else 0.0,
		"sun_shadow_opacity": _sun.shadow_opacity if _sun != null else 0.0,
		"ssr_enabled": _environment != null and _environment.ssr_enabled,
		"wet_material_count": _wet_material_entries.size(),
		"wet_material_min_roughness": wet_material_min_roughness if not _wet_material_entries.is_empty() else 0.0,
		"wet_material_max_clearcoat": wet_material_max_clearcoat,
		"powered_presentation": _powered_presentation,
		"amber_lamp_material_count": _amber_lamp_records.size(),
		"amber_lamp_emission_enabled": amber_lamp_emission_enabled,
		"amber_lamp_emission_energy": amber_lamp_emission_energy,
		"deck_light_mount_count": _deck_light_mounts.size(),
		"deck_light_mount_parented_count": deck_light_mount_parented_count,
		"deck_light_local_light_count": deck_light_local_light_count,
		"deck_light_anchor_match_count": deck_light_anchor_match_count,
		"deck_light_aim_alignment_min": deck_light_aim_alignment_min if not _deck_light_beams.is_empty() else 0.0,
		"deck_light_beam_end_clearance_min": deck_light_beam_end_clearance_min if not _deck_light_beams.is_empty() else 0.0,
		"deck_light_beam_end_clearance_max": deck_light_beam_end_clearance_max,
		"deck_light_beam_count": _deck_light_beams.size(),
		"deck_light_beam_visible_count": deck_light_beam_visible_count,
		"deck_light_beam_parented_count": deck_light_beam_parented_count,
		"deck_light_source_glow_count": _deck_light_source_glows.size(),
		"deck_light_source_glow_visible_count": deck_light_source_glow_visible_count,
		"deck_light_source_glow_parented_count": deck_light_source_glow_parented_count,
		"deck_light_vfx_shadow_casting_count": deck_light_vfx_shadow_casting_count,
		"deck_light_fixture_geometry_count": deck_light_fixture_geometry_count,
		"deck_light_vfx_geometry_count": deck_light_vfx_geometry_count,
		"deck_light_geometry_count": deck_light_fixture_geometry_count,
		"platform_position": platform_rig.position if platform_rig != null else Vector3.ZERO,
		"platform_rotation": platform_rig.rotation if platform_rig != null else Vector3.ZERO,
		"platform_contact_energy": float(_last_platform_wave_motion.contact_energy),
		"platform_contact_energy_sides": Vector4(_last_platform_wave_motion.contact_energy_sides),
		"pontoon_contact_energy_a": Vector4(_last_platform_wave_motion.pontoon_contact_energy_a),
		"pontoon_contact_energy_b": Vector4(_last_platform_wave_motion.pontoon_contact_energy_b),
		"platform_impact_energy": float(_last_platform_wave_motion.impact_energy),
		"platform_left_height": float(_last_platform_wave_motion.left_height),
		"platform_right_height": float(_last_platform_wave_motion.right_height),
		"platform_front_height": float(_last_platform_wave_motion.front_height),
		"platform_back_height": float(_last_platform_wave_motion.back_height),
		"platform_raw_roll": float(_last_platform_wave_motion.raw_roll),
		"platform_raw_pitch": float(_last_platform_wave_motion.raw_pitch),
		"wave_motion_source": "shared_gerstner",
		"wave_parameters_in_sync": _wave_parameters_in_sync(),
		"ocean_scattering_enabled": _ocean_scattering_enabled,
		"spray_parented_to_platform": not _spray_emitters.is_empty() and _spray_emitters[0].get_parent() == platform_rig,
	}


func _wave_parameters_in_sync() -> bool:
	if _ocean_material == null:
		return false
	var shader_components := [
		_ocean_material.get_shader_parameter("macro_wave_a"),
		_ocean_material.get_shader_parameter("macro_wave_b"),
		_ocean_material.get_shader_parameter("macro_wave_c"),
	]
	for index in range(OCEAN_WAVE_COMPONENTS.size()):
		if not shader_components[index] is Vector4:
			return false
		if not Vector4(shader_components[index]).is_equal_approx(OCEAN_WAVE_COMPONENTS[index]):
			return false
	return true


func _build_environment() -> void:
	_world_environment = WorldEnvironment.new()
	_world_environment.name = "MarineWorldEnvironment"
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.70, 0.74, 0.75)
	_environment.ambient_light_energy = 0.98
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.tonemap_exposure = 1.08
	# ACES with its default white point clips the wet highlights into hard cyan
	# patches. A photographic white reference preserves texture detail while the
	# deterministic daylight profiles continue to own scene brightness.
	_environment.tonemap_white = 6.0
	# The compact orthographic board must remain legible. Atmospheric depth comes
	# from the ocean, sky, rain and lighting; full-screen fog created a milky veil
	# over the platform and hid both materials and the six gameplay slots.
	_environment.fog_enabled = false
	_environment.fog_light_color = Color(0.55, 0.66, 0.70)
	_environment.fog_light_energy = 0.0
	_environment.fog_density = 0.0
	_environment.fog_height = 1.4
	_environment.fog_height_density = 0.18

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.075, 0.12, 0.16)
	sky_material.sky_horizon_color = Color(0.34, 0.43, 0.47)
	sky_material.ground_horizon_color = Color(0.25, 0.33, 0.35)
	sky_material.ground_bottom_color = Color(0.035, 0.065, 0.075)
	sky_material.sun_angle_max = 14.0
	sky_material.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_material
	_environment.sky = sky
	_world_environment.environment = _environment
	add_child(_world_environment)

	_sun = DirectionalLight3D.new()
	_sun.name = "SunDirectionalLight3D"
	_sun.rotation_degrees = Vector3(-52.0, -24.0, 0.0)
	_sun.light_color = Color(0.97, 0.91, 0.82)
	_sun.light_energy = 0.96
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 80.0
	_sun.directional_shadow_fade_start = 0.98
	_sun.light_angular_distance = _sun_angular_distance
	_sun.shadow_opacity = 0.72
	add_child(_sun)


func _build_ocean() -> void:
	ocean = MeshInstance3D.new()
	ocean.name = "OceanSurface3D"
	var ocean_mesh := PlaneMesh.new()
	ocean_mesh.size = Vector2(120.0, 120.0)
	ocean_mesh.subdivide_width = HIGH_OCEAN_SUBDIVISIONS
	ocean_mesh.subdivide_depth = HIGH_OCEAN_SUBDIVISIONS
	ocean.mesh = ocean_mesh
	_ocean_material = ShaderMaterial.new()
	if ResourceLoader.exists(OCEAN_SHADER_PATH):
		_ocean_material.shader = ResourceLoader.load(OCEAN_SHADER_PATH)
	_ocean_material.set_shader_parameter("macro_wave_a", OCEAN_WAVE_COMPONENTS[0])
	_ocean_material.set_shader_parameter("macro_wave_b", OCEAN_WAVE_COMPONENTS[1])
	_ocean_material.set_shader_parameter("macro_wave_c", OCEAN_WAVE_COMPONENTS[2])
	_ocean_material.set_shader_parameter(
		"macro_wave_steepness_weights",
		Vector3(OCEAN_WAVE_STEEPNESS_WEIGHTS[0], OCEAN_WAVE_STEEPNESS_WEIGHTS[1], OCEAN_WAVE_STEEPNESS_WEIGHTS[2])
	)
	_ocean_material.set_shader_parameter("platform_scattering_enabled", _ocean_scattering_enabled)
	_ocean_material.set_shader_parameter("platform_scattering_transmission_loss", OCEAN_SCATTERING_TRANSMISSION_LOSS)
	_ocean_material.set_shader_parameter("platform_scattering_reflection_strength", OCEAN_SCATTERING_REFLECTION_STRENGTH)
	_ocean_material.set_shader_parameter("platform_scattering_lee_retention", OCEAN_SCATTERING_LEE_RETENTION)
	_ocean_material.set_shader_parameter("platform_impact_foam_strength", OCEAN_SCATTERING_IMPACT_FOAM_STRENGTH)
	_ocean_material.set_shader_parameter("platform_reflected_foam_strength", OCEAN_SCATTERING_REFLECTED_FOAM_STRENGTH)
	ocean.material_override = _ocean_material
	ocean.position.y = -0.12
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean.extra_cull_margin = 2.0
	# Layer 2 is rendered only by the particle height field. The gameplay camera
	# remains on layer 1, while the collision capture receives the exact same
	# vertex-displaced Gerstner surface as the visible ocean.
	ocean.set_layer_mask_value(RAIN_COLLISION_VISUAL_LAYER, true)
	add_child(ocean)


func _build_platform() -> void:
	platform_rig = Node3D.new()
	platform_rig.name = "PlatformRig3D"
	add_child(platform_rig)
	if ResourceLoader.exists(PLATFORM_MODEL_PATH):
		var packed := ResourceLoader.load(PLATFORM_MODEL_PATH) as PackedScene
		if packed != null:
			_platform_asset = packed.instantiate() as Node3D
	if _platform_asset == null:
		_platform_asset = _build_fallback_platform()
	_platform_asset.name = "StartPlatformRuins"
	platform_rig.add_child(_platform_asset)
	_index_platform_variants()
	for slot_id in SLOT_IDS:
		if not _slot_states.has(slot_id):
			_slot_states[slot_id] = {"is_built": false, "level": 0}
		_apply_slot_state(slot_id)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "BaseOrthographicCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 18.0
	camera.near = 0.1
	camera.far = 180.0
	# Rain collision proxies live on visual layer 2. Keeping the camera on layer
	# 1 makes those inexpensive opaque meshes available to the height-field pass
	# without ever drawing them into the player's image.
	camera.cull_mask = 1 << (RAIN_PARTICLE_VISUAL_LAYER - 1)
	# Equivalent to the canonical Blender preview camera after Y-up export. The
	# low frontal elevation makes the front edge nearly horizontal and preserves
	# the wide 3x2 platform silhouette from the approved reference.
	camera.position = Vector3(0.0, 31.5, 48.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.65, -1.70), Vector3.UP)
	camera.current = true
	add_child(camera)
	_update_rain_impact_camera_position()


func _build_rain() -> void:
	# Rain near the surface is already at terminal speed. A short, tapered quad
	# represents camera exposure rather than a metre-long physical drop. The two
	# world-space volumes provide depth and parallax without expensive trails.
	var streak_texture := _build_rain_streak_texture()
	var lifetime_ramp := _rain_lifetime_ramp()
	var brightness_ramp := _rain_brightness_ramp()
	var collision_carrier_shader := ResourceLoader.load(RAIN_COLLISION_CARRIER_SHADER_PATH) as Shader

	_rain_particles = GPUParticles3D.new()
	_rain_particles.name = "RainVolume3D"
	_rain_particles.amount = RAIN_MID_AMOUNTS.high
	_rain_particles.lifetime = 2.10
	_rain_particles.preprocess = 2.10
	_rain_particles.randomness = 0.36
	_rain_particles.local_coords = false
	_rain_particles.use_fixed_seed = true
	_rain_particles.seed = 41027
	_rain_particles.visibility_aabb = RAIN_MID_VISIBILITY_AABB
	_rain_particles.position = Vector3(
		RAIN_MID_CONTACT_CENTER_XZ.x,
		RAIN_MID_EMITTER_HEIGHT,
		RAIN_MID_CONTACT_CENTER_XZ.y
	)
	_rain_particles.fixed_fps = 60
	_rain_particles.interpolate = true
	_rain_particles.collision_base_size = 0.08
	_rain_particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_rain_particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_rain_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_process_material = _make_rain_collision_carrier_material(
		collision_carrier_shader,
		RAIN_MID_EMISSION_EXTENTS,
		Vector3(0.12, -1.0, 0.08).normalized(),
		3.2,
		RAIN_MID_TERMINAL_SPEED,
		Vector2(0.58, 1.22),
		RAIN_MID_CONTACT_EMISSION_FRACTION,
		_rain_particles.collision_base_size,
		lifetime_ramp,
		brightness_ramp
	)
	_rain_particles.process_material = _rain_process_material

	var rain_quad := QuadMesh.new()
	rain_quad.size = Vector2(0.014, 0.30)
	rain_quad.material = _rain_streak_material(Color(0.69, 0.80, 0.82, 0.31), streak_texture)
	_rain_particles.draw_pass_1 = rain_quad
	add_child(_rain_particles)

	# A second, central hero volume carries fewer, slightly larger exposure
	# streaks. Its contact footprint covers the platform, roofs and nearby sea;
	# it is still ballistic world-space rain, not a screen-space overlay.
	_rain_near_particles = GPUParticles3D.new()
	_rain_near_particles.name = "RainNear3D"
	_rain_near_particles.amount = RAIN_NEAR_AMOUNTS.high
	_rain_near_particles.lifetime = 2.70
	_rain_near_particles.preprocess = 2.70
	_rain_near_particles.randomness = 0.42
	_rain_near_particles.local_coords = false
	_rain_near_particles.use_fixed_seed = true
	_rain_near_particles.seed = 41041
	_rain_near_particles.visibility_aabb = RAIN_NEAR_VISIBILITY_AABB
	_rain_near_particles.position = Vector3(
		RAIN_NEAR_CONTACT_CENTER_XZ.x,
		RAIN_NEAR_EMITTER_HEIGHT,
		RAIN_NEAR_CONTACT_CENTER_XZ.y
	)
	_rain_near_particles.fixed_fps = 60
	_rain_near_particles.interpolate = true
	_rain_near_particles.collision_base_size = 0.10
	_rain_near_particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_rain_near_particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_rain_near_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_near_process_material = _make_rain_collision_carrier_material(
		collision_carrier_shader,
		RAIN_NEAR_EMISSION_EXTENTS,
		Vector3(0.10, -1.0, 0.07).normalized(),
		2.8,
		RAIN_NEAR_TERMINAL_SPEED,
		Vector2(0.62, 1.24),
		RAIN_NEAR_CONTACT_EMISSION_FRACTION,
		_rain_near_particles.collision_base_size,
		lifetime_ramp,
		brightness_ramp
	)
	_rain_near_particles.process_material = _rain_near_process_material
	var near_quad := QuadMesh.new()
	near_quad.size = Vector2(0.024, 0.48)
	near_quad.material = _rain_streak_material(Color(0.72, 0.84, 0.86, 0.35), streak_texture)
	_rain_near_particles.draw_pass_1 = near_quad
	add_child(_rain_near_particles)

	_update_rain_flow(0.0)
	_build_rain_surface_impacts()
	# Each parent owns a bounded subemitter pool. Godot resets a target emission
	# buffer before each parent dispatch, so sharing one target between unrelated
	# parents can erase the other parent's collision batch.
	_rain_particles.sub_emitter = _rain_particles.get_path_to(_rain_contact_impacts)
	_rain_near_particles.sub_emitter = _rain_near_particles.get_path_to(_rain_near_contact_impacts)


func _make_rain_collision_carrier_material(
	carrier_shader: Shader,
	emission_extents: Vector3,
	initial_direction: Vector3,
	spread_degrees: float,
	terminal_speed: Vector2,
	scale_range: Vector2,
	impact_emission_fraction: float,
	collision_base_size: float,
	lifetime_ramp: Texture2D,
	brightness_ramp: Texture2D
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = carrier_shader
	material.set_shader_parameter("emission_box_extents", emission_extents)
	material.set_shader_parameter("direction", initial_direction.normalized())
	material.set_shader_parameter("spread_degrees", maxf(spread_degrees, 0.0))
	material.set_shader_parameter("initial_velocity_min", maxf(terminal_speed.x, 0.0))
	material.set_shader_parameter("initial_velocity_max", maxf(terminal_speed.y, terminal_speed.x))
	material.set_shader_parameter("scale_min", maxf(scale_range.x, 0.001))
	material.set_shader_parameter("scale_max", maxf(scale_range.y, scale_range.x))
	material.set_shader_parameter("impact_emission_probability", clampf(impact_emission_fraction, 0.0, 1.0))
	material.set_shader_parameter("base_color", Color.WHITE)
	material.set_shader_parameter("color_ramp", lifetime_ramp)
	material.set_shader_parameter("color_initial_ramp", brightness_ramp)
	material.set_shader_parameter("collision_base_size", maxf(collision_base_size, 0.0))
	material.set_shader_parameter("impact_surface_bias", 0.008)
	material.set_shader_parameter(
		"impact_camera_position",
		(
			camera.global_position if camera != null and camera.is_inside_tree()
			else camera.position if camera != null
			else Vector3(0.0, 31.5, 48.0)
		)
	)
	return material


func _update_rain_impact_camera_position() -> void:
	if camera == null:
		return
	var camera_position := camera.global_position if camera.is_inside_tree() else camera.position
	for material in [_rain_process_material, _rain_near_process_material]:
		if material != null:
			material.set_shader_parameter("impact_camera_position", camera_position)


func _rain_streak_material(color: Color, streak_texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# GPUParticles3D already supplies the camera-facing, velocity-aligned basis.
	# BILLBOARD_PARTICLES would rebuild it in the material, treat CUSTOM.x as an
	# angle and discard the per-drop scale stored in the particle transform.
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.albedo_color = color
	material.albedo_texture = streak_texture
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.proximity_fade_enabled = true
	material.proximity_fade_distance = 0.18
	return material


func _build_rain_streak_texture() -> ImageTexture:
	const TEXTURE_WIDTH := 16
	const TEXTURE_HEIGHT := 96
	var image := Image.create(TEXTURE_WIDTH, TEXTURE_HEIGHT, false, Image.FORMAT_RGBA8)
	for pixel_y in range(TEXTURE_HEIGHT):
		for pixel_x in range(TEXTURE_WIDTH):
			var uv := (Vector2(pixel_x, pixel_y) + Vector2(0.5, 0.5)) / Vector2(TEXTURE_WIDTH, TEXTURE_HEIGHT)
			var centred := uv * 2.0 - Vector2.ONE
			var cross_fade := 1.0 - smoothstep(0.08, 0.92, absf(centred.x))
			var end_fade := 1.0 - smoothstep(0.72, 1.0, absf(centred.y))
			var optical_head := exp(-pow((centred.y - 0.43) * 3.1, 2.0))
			var optical_tail := lerpf(0.70, 1.0, optical_head)
			var alpha := clampf(cross_fade * end_fade * optical_tail, 0.0, 1.0)
			image.set_pixel(pixel_x, pixel_y, Color(1.0, 1.0, 1.0, alpha))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _rain_lifetime_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.07, 0.76, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.92, 0.97, 1.0, 0.82),
		Color(0.88, 0.95, 1.0, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


func _rain_brightness_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.48, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.72, 0.82, 0.84, 0.62),
		Color(0.90, 0.96, 0.98, 0.84),
		Color(1.0, 1.0, 1.0, 1.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


func _build_rain_surface_impacts() -> void:
	var crown_texture := _build_rain_impact_crown_texture()
	var ring_texture := _build_rain_impact_ring_texture()
	var crown_mesh := _rain_impact_crown_mesh(Vector2(0.09, 0.20), crown_texture, Color(0.78, 0.92, 0.94, 0.72))
	var ring_mesh := _rain_impact_ring_mesh(0.38, ring_texture, Color(0.74, 0.90, 0.92, 0.52))
	_build_rain_collision_geometry()
	_rain_contact_impacts = _make_surface_impact_emitter(
		"RainContactImpacts3D",
		RAIN_MID_CONTACT_IMPACT_AMOUNTS.high,
		41081,
		crown_mesh,
		ring_mesh,
		RAIN_CONTACT_IMPACT_LIFETIME
	)
	add_child(_rain_contact_impacts)
	_rain_near_contact_impacts = _make_surface_impact_emitter(
		"RainNearContactImpacts3D",
		RAIN_NEAR_CONTACT_IMPACT_AMOUNTS.high,
		41093,
		crown_mesh,
		ring_mesh,
		RAIN_CONTACT_IMPACT_LIFETIME
	)
	add_child(_rain_near_contact_impacts)


func _build_rain_collision_geometry() -> void:
	# The imported common platform mesh exceeds a million triangles. Re-rendering
	# it every frame into the collision height field would be wasteful, so the
	# broad deck uses a hidden low-poly proxy. Active ruins/buildings are already
	# inexpensive meshes and were tagged for the same capture layer while indexing.
	_rain_deck_collision_proxy = MeshInstance3D.new()
	_rain_deck_collision_proxy.name = "RainDeckCollisionProxy3D"
	_rain_deck_collision_proxy.layers = 0
	_rain_deck_collision_proxy.set_layer_mask_value(RAIN_COLLISION_VISUAL_LAYER, true)
	_rain_deck_collision_proxy.position = Vector3.ZERO
	_rain_deck_collision_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_deck_collision_proxy.mesh = _build_rain_platform_receiver_mesh()
	platform_rig.add_child(_rain_deck_collision_proxy)

	_rain_collision_heightfield = GPUParticlesCollisionHeightField3D.new()
	_rain_collision_heightfield.name = "RainSurfaceCollisionHeightField3D"
	_rain_collision_heightfield.position = RAIN_HEIGHTFIELD_POSITION
	_rain_collision_heightfield.size = RAIN_HEIGHTFIELD_SIZE
	_rain_collision_heightfield.heightfield_mask = 0
	_rain_collision_heightfield.set_heightfield_mask_value(RAIN_COLLISION_VISUAL_LAYER, true)
	_rain_collision_heightfield.cull_mask = 1 << (RAIN_PARTICLE_VISUAL_LAYER - 1)
	_rain_collision_heightfield.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	# Ocean vertices, platform motion and visible building variants all change at
	# runtime. ALWAYS keeps the GPU height field synchronized with that presentation.
	_rain_collision_heightfield.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_ALWAYS
	add_child(_rain_collision_heightfield)


func _build_rain_platform_receiver_mesh() -> ArrayMesh:
	# Authored from top-facing samples of the production GLB. The 20-triangle
	# receiver follows the real deck outline plus the largest common roofs and
	# crane. It replaces a 1.38-million-triangle capture and avoids a rectangular
	# sheet that used to report impacts above open water near the corners.
	var vertices := PackedVector3Array([
		Vector3(-8.45, 1.72, -6.15), Vector3(8.45, 1.72, -6.15),
		Vector3(8.75, 1.72, -5.55), Vector3(8.75, 1.72, 7.35),
		Vector3(8.45, 1.72, 7.75), Vector3(-8.45, 1.72, 7.75),
		Vector3(-8.75, 1.72, 7.35), Vector3(-8.75, 1.72, -5.55),
		Vector3(-8.35, 1.72, -8.10), Vector3(-5.35, 1.72, -8.10),
		Vector3(-6.05, 1.72, -6.15), Vector3(-8.45, 1.72, -6.15),
		Vector3(6.90, 1.72, -8.10), Vector3(8.35, 1.72, -8.10),
		Vector3(8.45, 1.72, -6.15), Vector3(6.75, 1.72, -6.15),
		# Rear service roof.
		Vector3(-6.05, 3.27, -8.55), Vector3(-1.95, 3.27, -8.55),
		Vector3(-1.95, 3.27, -6.30), Vector3(-6.05, 3.27, -6.30),
		# Rear control roof and its raised step.
		Vector3(-0.55, 3.02, -8.35), Vector3(1.55, 3.02, -8.35),
		Vector3(1.55, 3.02, -6.30), Vector3(-0.55, 3.02, -6.30),
		Vector3(0.35, 4.55, -8.15), Vector3(1.15, 4.55, -8.15),
		Vector3(1.15, 4.55, -7.25), Vector3(0.35, 4.55, -7.25),
		# Sloped crane boom and its horizontal base.
		Vector3(4.00, 4.10, -7.15), Vector3(4.00, 4.10, -6.45),
		Vector3(8.05, 5.72, -6.45), Vector3(8.05, 5.72, -7.15),
		Vector3(5.20, 3.05, -8.10), Vector3(6.70, 3.05, -8.10),
		Vector3(6.70, 3.05, -7.40), Vector3(5.20, 3.05, -7.40),
	])
	var indices := PackedInt32Array([
		0, 2, 1, 0, 7, 2, 7, 3, 2, 7, 6, 3, 6, 4, 3, 6, 5, 4,
		8, 10, 9, 8, 11, 10, 12, 14, 13, 12, 15, 14,
		16, 18, 17, 16, 19, 18,
		20, 22, 21, 20, 23, 22, 24, 26, 25, 24, 27, 26,
		28, 29, 30, 28, 30, 31,
		32, 34, 33, 32, 35, 34,
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var receiver_material := StandardMaterial3D.new()
	receiver_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	receiver_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, receiver_material)
	return mesh


func _make_surface_impact_emitter(
	emitter_name: String,
	particle_amount: int,
	fixed_seed: int,
	crown_mesh: Mesh,
	ring_mesh: Mesh,
	impact_lifetime: float
) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = emitter_name
	emitter.amount = maxi(particle_amount, 1)
	emitter.lifetime = maxf(impact_lifetime, 0.1)
	emitter.randomness = 0.72
	emitter.local_coords = false
	emitter.use_fixed_seed = true
	emitter.seed = fixed_seed
	emitter.fixed_fps = 60
	emitter.interpolate = true
	emitter.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-34.0, -4.0, -40.0), Vector3(68.0, 24.0, 90.0))
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	process_material.direction = Vector3.UP
	process_material.spread = 0.0
	process_material.gravity = Vector3.ZERO
	process_material.initial_velocity_min = 0.0
	process_material.initial_velocity_max = 0.0
	process_material.scale_min = 0.72
	process_material.scale_max = 1.18
	process_material.alpha_curve = _rain_impact_alpha_curve()
	process_material.scale_curve = _rain_impact_scale_curve()
	emitter.process_material = process_material
	emitter.draw_passes = 2
	emitter.draw_pass_1 = crown_mesh
	emitter.draw_pass_2 = ring_mesh
	# Subemitters must stay dormant until the parent particle explicitly emits
	# them at collision. Setting this true would reintroduce unrelated fake rings.
	emitter.emitting = false
	return emitter


func _rain_impact_crown_mesh(size: Vector2, texture: Texture2D, color: Color) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = size
	# Geometry offsets remain effective for subparticles whose position was
	# supplied by the parent collision event; child emission_shape_offset does not.
	mesh.center_offset = Vector3(0.0, 0.055, 0.0)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# The collision carrier already supplies a camera-facing tangent basis whose Y
	# follows the receiver normal. A material billboard would overwrite that basis.
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.albedo_color = color
	material.albedo_texture = texture
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = material
	return mesh


func _rain_impact_ring_mesh(diameter: float, texture: Texture2D, color: Color) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.orientation = PlaneMesh.FACE_Y
	mesh.size = Vector2.ONE * diameter
	mesh.center_offset = Vector3(0.0, 0.022, 0.0)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.albedo_texture = texture
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = material
	return mesh


func _rain_impact_alpha_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.06, 1.0))
	curve.add_point(Vector2(0.34, 0.70))
	curve.add_point(Vector2(0.72, 0.24))
	curve.add_point(Vector2(1.0, 0.0))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


func _rain_impact_scale_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = 1.40
	curve.add_point(Vector2(0.0, 0.30))
	curve.add_point(Vector2(0.12, 0.72))
	curve.add_point(Vector2(0.55, 1.08))
	curve.add_point(Vector2(1.0, 1.28))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


func _build_rain_impact_crown_texture() -> ImageTexture:
	const TEXTURE_WIDTH := 32
	const TEXTURE_HEIGHT := 64
	var image := Image.create(TEXTURE_WIDTH, TEXTURE_HEIGHT, false, Image.FORMAT_RGBA8)
	for pixel_y in range(TEXTURE_HEIGHT):
		for pixel_x in range(TEXTURE_WIDTH):
			var uv := Vector2(
				(float(pixel_x) + 0.5) / float(TEXTURE_WIDTH),
				(float(pixel_y) + 0.5) / float(TEXTURE_HEIGHT)
			)
			var centred := uv * 2.0 - Vector2.ONE
			var jet := (1.0 - smoothstep(0.05, 0.62, absf(centred.x))) * (1.0 - smoothstep(0.05, 0.98, absf(centred.y + 0.18)))
			var shoulder_left := 1.0 - smoothstep(0.04, 0.22, Vector2(centred.x + 0.42, centred.y + 0.62).length())
			var shoulder_right := 1.0 - smoothstep(0.04, 0.22, Vector2(centred.x - 0.42, centred.y + 0.62).length())
			var alpha := clampf(maxf(jet * 0.74, maxf(shoulder_left, shoulder_right) * 0.62), 0.0, 1.0)
			image.set_pixel(pixel_x, pixel_y, Color(1.0, 1.0, 1.0, alpha))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _build_rain_impact_ring_texture() -> ImageTexture:
	const TEXTURE_SIZE := 48
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for pixel_y in range(TEXTURE_SIZE):
		for pixel_x in range(TEXTURE_SIZE):
			var uv := Vector2(
				(float(pixel_x) + 0.5) / float(TEXTURE_SIZE),
				(float(pixel_y) + 0.5) / float(TEXTURE_SIZE)
			)
			var centred := uv * 2.0 - Vector2.ONE
			var radius := centred.length()
			var ring := 1.0 - smoothstep(0.045, 0.15, absf(radius - 0.62))
			var angle := atan2(centred.y, centred.x)
			var breakup := lerpf(0.58, 1.0, sin(angle * 7.0 + radius * 9.0) * 0.5 + 0.5)
			var centre_flash := (1.0 - smoothstep(0.0, 0.18, radius)) * 0.24
			var alpha := clampf(maxf(ring * breakup, centre_flash), 0.0, 1.0)
			image.set_pixel(pixel_x, pixel_y, Color(1.0, 1.0, 1.0, alpha))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _build_spray() -> void:
	var spray_quad := QuadMesh.new()
	spray_quad.size = Vector2(0.085, 0.18)
	var spray_material := StandardMaterial3D.new()
	spray_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spray_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spray_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spray_material.albedo_color = Color(0.72, 0.82, 0.82, 0.58)
	spray_material.albedo_texture = _build_soft_spray_texture()
	spray_material.vertex_color_use_as_albedo = true
	spray_quad.material = spray_material
	var spray_gradient := Gradient.new()
	spray_gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.68, 1.0])
	spray_gradient.colors = PackedColorArray([
		Color(0.72, 0.86, 0.88, 0.10),
		Color(0.76, 0.88, 0.89, 0.72),
		Color(0.60, 0.76, 0.78, 0.38),
		Color(0.48, 0.63, 0.66, 0.0),
	])
	var spray_ramp := GradientTexture1D.new()
	spray_ramp.gradient = spray_gradient
	for index in range(SPRAY_ANCHORS.size()):
		var emitter := GPUParticles3D.new()
		emitter.name = "HullSpray%02d" % (index + 1)
		emitter.position = SPRAY_ANCHORS[index]
		emitter.amount = 24
		emitter.lifetime = 0.82
		emitter.one_shot = true
		emitter.explosiveness = 0.92
		emitter.randomness = 0.72
		emitter.local_coords = false
		emitter.use_fixed_seed = true
		emitter.seed = 41120 + index * 17
		emitter.fixed_fps = 30
		emitter.interpolate = true
		emitter.visibility_aabb = AABB(Vector3(-5.0, -1.0, -5.0), Vector3(10.0, 8.0, 10.0))
		var process_material := ParticleProcessMaterial.new()
		process_material.spread = 36.0
		process_material.gravity = Vector3(0.0, -12.0, 0.0)
		process_material.initial_velocity_min = 2.6
		process_material.initial_velocity_max = 6.2
		process_material.scale_min = 0.36
		process_material.scale_max = 0.92
		process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process_material.emission_sphere_radius = 0.42
		process_material.color_ramp = spray_ramp
		emitter.process_material = process_material
		emitter.draw_pass_1 = spray_quad
		emitter.emitting = false
		platform_rig.add_child(emitter)
		_spray_emitters.append(emitter)
		_spray_process_materials.append(process_material)
	_update_spray_directions()


func _build_soft_spray_texture() -> ImageTexture:
	const TEXTURE_SIZE := 32
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for pixel_y in range(TEXTURE_SIZE):
		for pixel_x in range(TEXTURE_SIZE):
			var uv := (Vector2(pixel_x, pixel_y) + Vector2(0.5, 0.5)) / float(TEXTURE_SIZE)
			var centred := uv * 2.0 - Vector2.ONE
			# A narrow ellipse with a softer upper mist tail removes the hard corners
			# of the old untextured particle quad while keeping transparent overdraw low.
			var radial := Vector2(centred.x / 0.54, (centred.y + 0.08) / 0.96).length()
			var core_alpha := 1.0 - smoothstep(0.42, 1.0, radial)
			var tail_alpha := 1.0 - smoothstep(0.16, 0.92, absf(centred.x) + maxf(centred.y, 0.0) * 0.34)
			var alpha := clampf(core_alpha * lerpf(0.72, 1.0, tail_alpha), 0.0, 1.0)
			image.set_pixel(pixel_x, pixel_y, Color(1.0, 1.0, 1.0, alpha))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _update_spray_directions() -> void:
	for index in range(mini(_spray_emitters.size(), _spray_process_materials.size())):
		var anchor := _spray_emitters[index].position
		var outward_2d := Vector2(anchor.x / 10.2, anchor.z / 7.5).normalized()
		var launch_2d := (outward_2d * 0.78 + _wind_direction * 0.22).normalized()
		_spray_process_materials[index].direction = Vector3(launch_2d.x * 0.72, 1.0, launch_2d.y * 0.72).normalized()


func _build_fallback_platform() -> Node3D:
	var root := Node3D.new()
	root.name = "FallbackPlatform"
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(22.0, 0.9, 15.2)
	deck.mesh = deck_mesh
	deck.position.y = 0.55
	deck.material_override = _standard_material(Color(0.12, 0.15, 0.16), 0.28, 0.78)
	root.add_child(deck)
	for slot_id in SLOT_IDS:
		var ruin := Node3D.new()
		ruin.name = "Ruin_%s" % slot_id
		ruin.position = SLOT_FALLBACK_POSITIONS[slot_id]
		root.add_child(ruin)
		_build_fallback_ruin(ruin, slot_id)
		for level in range(1, 5):
			var built := Node3D.new()
			built.name = "Built_%s_L%d" % [slot_id, level]
			built.position = SLOT_FALLBACK_POSITIONS[slot_id]
			root.add_child(built)
			_build_fallback_building(built, slot_id, level)
	return root


func _build_fallback_ruin(root: Node3D, slot_id: String) -> void:
	var rust := _standard_material(Color(0.24, 0.18, 0.13), 0.22, 0.94)
	var width := 4.15 if slot_id in ["top_right", "center"] else 3.7
	var depth := 3.0
	for x in [-width * 0.5, width * 0.5]:
		for z in [-depth * 0.5, depth * 0.5]:
			_add_box(root, Vector3(0.13, 1.75 if x < 0.0 or z > 0.0 else 1.08, 0.13), Vector3(x, 0.88, z), rust)
	_add_box(root, Vector3(width, 0.12, 0.14), Vector3(0.0, 1.72, -depth * 0.5), rust)
	_add_box(root, Vector3(width * 0.62, 0.11, 0.14), Vector3(-width * 0.18, 1.58, depth * 0.5), rust)
	if slot_id == "kitchen" or slot_id == "top_center":
		_add_box(root, Vector3(0.3, 2.4, 0.3), Vector3(1.1, 1.18, 0.5), rust)
	elif slot_id == "bottom_left":
		_add_box(root, Vector3(width + 0.4, 0.15, 0.15), Vector3(0.0, 2.0, 0.0), rust)
	elif slot_id == "bottom_right":
		_add_box(root, Vector3(0.18, 2.5, 0.18), Vector3(-1.1, 1.25, 0.0), rust)


func _build_fallback_building(root: Node3D, slot_id: String, level: int) -> void:
	var metal := _standard_material(Color(0.19, 0.23, 0.23), 0.42, 0.72)
	var accent_colors := {
		"top_left": Color(0.20, 0.30, 0.30),
		"top_center": Color(0.30, 0.25, 0.18),
		"top_right": Color(0.27, 0.25, 0.22),
		"bottom_left": Color(0.25, 0.20, 0.16),
		"center": Color(0.25, 0.30, 0.29),
		"bottom_right": Color(0.18, 0.26, 0.29),
	}
	var width := 3.9 + float(level - 1) * 0.18
	var height := 1.8 + float(level - 1) * 0.28
	_add_box(root, Vector3(width, height, 2.8), Vector3(0.0, height * 0.5, 0.0), metal)
	_add_box(root, Vector3(width + 0.25, 0.16, 3.05), Vector3(0.0, height + 0.08, 0.0), _standard_material(accent_colors[slot_id], 0.34, 0.66))
	for upgrade in range(level - 1):
		_add_box(root, Vector3(0.34, 0.9 + upgrade * 0.18, 0.34), Vector3(-1.25 + upgrade * 0.85, height + 0.5, 0.55), metal)


func _index_platform_variants() -> void:
	_ruin_nodes.clear()
	_building_nodes.clear()
	_slot_anchor_nodes.clear()
	for slot_id in SLOT_IDS:
		var ruin := _find_node_recursive(_platform_asset, "Ruin_%s" % slot_id) as Node3D
		if ruin != null:
			_ruin_nodes[slot_id] = ruin
			_set_rain_collision_layer_recursive(ruin)
		var anchor := _find_node_recursive(_platform_asset, "SlotAnchor_%s" % slot_id) as Node3D
		if anchor != null:
			_slot_anchor_nodes[slot_id] = anchor
		var levels := {}
		for level in range(1, 5):
			var built := _find_node_recursive(_platform_asset, "Built_%s_L%d" % [slot_id, level]) as Node3D
			if built != null:
				levels[level] = built
				_set_rain_collision_layer_recursive(built)
		_building_nodes[slot_id] = levels


func _set_rain_collision_layer_recursive(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		(node as MeshInstance3D).set_layer_mask_value(RAIN_COLLISION_VISUAL_LAYER, true)
	for child in node.get_children():
		_set_rain_collision_layer_recursive(child)


func _apply_slot_state(slot_id: String) -> void:
	var state: Dictionary = _slot_states.get(slot_id, {"is_built": false, "level": 0})
	var is_built := bool(state.get("is_built", false))
	var level := clampi(int(state.get("level", 0)), 1, 4)
	var ruin: Node3D = _ruin_nodes.get(slot_id)
	if ruin != null:
		ruin.visible = not is_built
	var levels: Dictionary = _building_nodes.get(slot_id, {})
	for candidate_level in levels.keys():
		var built: Node3D = levels[candidate_level]
		built.visible = is_built and int(candidate_level) == level
	var wet_branch := "built:%s:%d" % [slot_id, level] if is_built else "ruin:%s" % slot_id
	_install_wet_branch(wet_branch)
	if _highlighted_slot_id == slot_id:
		_restore_building_highlight_layers()
		_apply_building_highlight_layers()


func _apply_building_highlight_layers() -> void:
	if _highlighted_slot_id.is_empty():
		return
	var target := _active_slot_variant(_highlighted_slot_id)
	if target == null:
		return
	_set_building_highlight_layer_recursive(target)


func _active_slot_variant(slot_id: String) -> Node3D:
	var state: Dictionary = _slot_states.get(slot_id, {"is_built": false, "level": 0})
	if not bool(state.get("is_built", false)):
		return _ruin_nodes.get(slot_id) as Node3D
	var levels: Dictionary = _building_nodes.get(slot_id, {})
	return levels.get(clampi(int(state.get("level", 0)), 1, 4)) as Node3D


func _set_building_highlight_layer_recursive(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var instance_id := mesh.get_instance_id()
		if not _highlight_layer_restore.has(instance_id):
			_highlight_layer_restore[instance_id] = {"mesh": mesh, "layers": int(mesh.layers)}
		mesh.set_layer_mask_value(BUILDING_HIGHLIGHT_VISUAL_LAYER, true)
	for child in node.get_children():
		_set_building_highlight_layer_recursive(child)


func _restore_building_highlight_layers() -> void:
	for entry_value in _highlight_layer_restore.values():
		var entry: Dictionary = entry_value
		var mesh := entry.get("mesh") as MeshInstance3D
		if mesh != null and is_instance_valid(mesh):
			mesh.layers = int(entry.get("layers", mesh.layers))
	_highlight_layer_restore.clear()


func _apply_weather() -> void:
	if _ocean_material != null:
		# Rain owns impacts and visibility, but it cannot silently turn a calm sea
		# into storm whitecaps. Ocean morphology follows the canonical sea state.
		_ocean_material.set_shader_parameter("weather_intensity", _sea_intensity)
		_ocean_material.set_shader_parameter("rain_intensity", _rain_intensity)
		# These are the final macro-wave values. The shader deliberately does not
		# apply a second weather multiplier.
		_ocean_material.set_shader_parameter("wave_amplitude_scale", _wave_amplitude_scale())
		_ocean_material.set_shader_parameter("wave_speed_scale", _wave_speed_scale)
		_ocean_material.set_shader_parameter("wave_steepness", lerpf(0.58, 0.72, _sea_intensity))
		_ocean_material.set_shader_parameter("crest_foam_strength", lerpf(0.08, 0.68, _foam_intensity))
		_ocean_material.set_shader_parameter("contact_foam_strength", lerpf(0.38, 0.78, _foam_intensity))
		_ocean_material.set_shader_parameter("wind_direction", _wind_direction)
		_ocean_material.set_shader_parameter("reduced_motion", _reduced_motion)
	_update_spray_directions()
	for rain_layer in [_rain_particles, _rain_near_particles]:
		if rain_layer == null:
			continue
		rain_layer.emitting = _rain_intensity > 0.025
		rain_layer.amount_ratio = clampf(_rain_intensity, 0.0, 1.0)
	_update_rain_flow(_rain_flow_time)
	var contacts_enabled := _rain_intensity > 0.025
	for contact_emitter in [_rain_contact_impacts, _rain_near_contact_impacts]:
		if contact_emitter == null:
			continue
		# The emitters remain false by contract: collision events, not autonomous
		# emission, populate their pools. Visibility only gates presentation/cost.
		contact_emitter.emitting = false
		contact_emitter.visible = contacts_enabled
		contact_emitter.amount_ratio = 1.0
	if _rain_collision_heightfield != null:
		_rain_collision_heightfield.cull_mask = (1 << (RAIN_PARTICLE_VISUAL_LAYER - 1)) if contacts_enabled else 0


func _update_rain_flow(current_time: float) -> void:
	_rain_flow_time = maxf(current_time, 0.0)
	if _rain_process_material == null and _rain_near_process_material == null:
		return
	# Two slow deterministic bands perturb the shared wind by only a few degrees.
	# This breaks the rigid curtain while keeping every drop ballistic and falling.
	var weather_strength := clampf(maxf(_sea_intensity, _rain_intensity), 0.0, 1.0)
	var gust_signal := (
		sin(_rain_flow_time * RAIN_GUST_PRIMARY_SPEED + 0.71) * 0.64
		+ sin(_rain_flow_time * RAIN_GUST_SECONDARY_SPEED + 2.37) * 0.36
	)
	var gust_angle := gust_signal * lerpf(0.025, 0.14, weather_strength)
	var wind_side := Vector2(-_wind_direction.y, _wind_direction.x)
	var gusted_wind := (_wind_direction + wind_side * gust_angle).normalized()
	var horizontal_drift := lerpf(0.10, 0.34, weather_strength)
	if _rain_process_material != null:
		var mid_direction := Vector3(
			gusted_wind.x * horizontal_drift,
			-1.0,
			gusted_wind.y * horizontal_drift
		).normalized()
		_rain_process_material.set_shader_parameter("direction", mid_direction)
		if _rain_particles != null:
			_rain_particles.position = _rain_spawn_position_for_contact(
				RAIN_MID_CONTACT_CENTER_XZ,
				RAIN_MID_EMITTER_HEIGHT,
				RAIN_MID_CONTACT_REFERENCE_Y,
				mid_direction
			)
	if _rain_near_process_material != null:
		# Foreground drops represent the larger end of the distribution and are
		# deflected a little less than the numerous smaller mid-field drops.
		var near_direction := Vector3(
			gusted_wind.x * horizontal_drift * 0.82,
			-1.0,
			gusted_wind.y * horizontal_drift * 0.82
		).normalized()
		_rain_near_process_material.set_shader_parameter("direction", near_direction)
		if _rain_near_particles != null:
			_rain_near_particles.position = _rain_spawn_position_for_contact(
				RAIN_NEAR_CONTACT_CENTER_XZ,
				RAIN_NEAR_EMITTER_HEIGHT,
				RAIN_NEAR_CONTACT_REFERENCE_Y,
				near_direction
			)


func _rain_spawn_position_for_contact(
	contact_center_xz: Vector2,
	spawn_height: float,
	surface_height: float,
	trajectory_direction: Vector3
) -> Vector3:
	# At terminal speed, velocity magnitude cancels from horizontal/vertical
	# displacement. Back-projecting this slope makes the centre drop reach the
	# selected world-space footprint for every wind direction and deterministic
	# gust, while local_coords=false leaves already airborne drops undisturbed.
	var vertical_component := maxf(-trajectory_direction.y, 0.001)
	var trajectory_slope := Vector2(
		trajectory_direction.x,
		trajectory_direction.z
	) / vertical_component
	var fall_height := maxf(spawn_height - surface_height, 0.0)
	var spawn_xz := contact_center_xz - trajectory_slope * fall_height
	return Vector3(spawn_xz.x, spawn_height, spawn_xz.y)


func _fit_rain_emitters_to_camera(viewport_size: Vector2) -> void:
	if camera == null or viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	# KEEP_HEIGHT narrows the horizontal safe span on portrait-like layouts while
	# set_viewport_size() deliberately opens the vertical span. Fit X inward and
	# extend the mid contact depth by the same authored margin, otherwise a 5:4
	# viewport loses rain at the newly exposed front/back strips of ocean.
	var viewport_aspect := viewport_size.x / viewport_size.y
	var camera_half_width := camera.size * viewport_aspect * 0.5
	if _rain_process_material != null:
		var mid_extents := RAIN_MID_EMISSION_EXTENTS
		mid_extents.x = clampf(camera_half_width - 1.85, 8.5, RAIN_MID_EMISSION_EXTENTS.x)
		mid_extents.z = clampf(
			RAIN_MID_EMISSION_EXTENTS.z + maxf(camera.size - 18.0, 0.0) * 0.60,
			RAIN_MID_EMISSION_EXTENTS.z,
			15.5
		)
		_rain_process_material.set_shader_parameter("emission_box_extents", mid_extents)
	if _rain_near_process_material != null:
		var near_extents := RAIN_NEAR_EMISSION_EXTENTS
		near_extents.x = clampf(camera_half_width - 2.30, 6.5, RAIN_NEAR_EMISSION_EXTENTS.x)
		_rain_near_process_material.set_shader_parameter("emission_box_extents", near_extents)
	_update_rain_flow(_rain_flow_time)


func _apply_graphics_quality() -> void:
	if ocean != null and ocean.mesh is PlaneMesh:
		var ocean_mesh := ocean.mesh as PlaneMesh
		var subdivisions := _ocean_subdivisions_for_quality()
		ocean_mesh.subdivide_width = subdivisions
		ocean_mesh.subdivide_depth = subdivisions
	if _ocean_material != null:
		_ocean_material.set_shader_parameter("quality_level", 0 if _graphics_quality == "low" else 1 if _graphics_quality == "medium" else 2)
	if _rain_particles != null:
		_rain_particles.amount = int(RAIN_MID_AMOUNTS[_graphics_quality])
	if _rain_near_particles != null:
		_rain_near_particles.amount = int(RAIN_NEAR_AMOUNTS[_graphics_quality])
	if _rain_contact_impacts != null:
		_rain_contact_impacts.amount = int(RAIN_MID_CONTACT_IMPACT_AMOUNTS[_graphics_quality])
	if _rain_near_contact_impacts != null:
		_rain_near_contact_impacts.amount = int(RAIN_NEAR_CONTACT_IMPACT_AMOUNTS[_graphics_quality])
	if _rain_collision_heightfield != null:
		_rain_collision_heightfield.resolution = (
			GPUParticlesCollisionHeightField3D.RESOLUTION_512
			if _graphics_quality == "high"
			else GPUParticlesCollisionHeightField3D.RESOLUTION_256
		)
	for emitter in _spray_emitters:
		emitter.visible = _graphics_quality != "low"
		emitter.amount = 14 if _graphics_quality == "medium" else 24
		if _graphics_quality == "low":
			emitter.emitting = false
	_apply_mesh_quality_recursive(_platform_asset)
	if _environment != null:
		_environment.ssao_enabled = _graphics_quality != "low"
		_environment.ssao_radius = 0.85
		_environment.ssao_intensity = 0.72 if _graphics_quality == "medium" else 0.90
		_environment.ssil_enabled = _graphics_quality == "high"
		_environment.ssil_radius = 1.55
		_environment.ssil_intensity = 0.34
		# A deterministic 60 FPS A/B capture showed no visible hull reflection from
		# SSR in this steep orthographic composition, while native high-quality
		# profiling still measured its cost. Sky/PBR reflection remains the stable
		# source for every preset; screen-space reflection stays disabled.
		_environment.ssr_enabled = false
		_environment.volumetric_fog_enabled = false
		_environment.volumetric_fog_density = 0.0
		_environment.volumetric_fog_length = 42.0
		_environment.volumetric_fog_detail_spread = 2.0
	if _sun != null:
		_apply_sun_shadow_quality()
	_apply_weather()


func _apply_sun_shadow_quality() -> void:
	if _sun == null:
		return
	match _graphics_quality:
		"low":
			_sun.directional_shadow_max_distance = 68.0
			_sun.light_angular_distance = 0.0
			_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			_sun.directional_shadow_blend_splits = false
		"medium":
			_sun.directional_shadow_max_distance = 74.0
			_sun.directional_shadow_split_1 = 0.78
			_sun.light_angular_distance = _sun_angular_distance * 0.76
			_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			_sun.directional_shadow_blend_splits = true
		_:
			_sun.directional_shadow_max_distance = 80.0
			_sun.directional_shadow_split_1 = 0.62
			_sun.directional_shadow_split_2 = 0.77
			_sun.directional_shadow_split_3 = 0.90
			_sun.light_angular_distance = _sun_angular_distance
			_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			_sun.directional_shadow_blend_splits = true


func _ocean_subdivisions_for_quality() -> int:
	return LOW_OCEAN_SUBDIVISIONS if _graphics_quality == "low" else MEDIUM_OCEAN_SUBDIVISIONS if _graphics_quality == "medium" else HIGH_OCEAN_SUBDIVISIONS


func _cache_wet_materials_recursive(node: Node, inherited_branch := "common") -> void:
	if node == null:
		return
	var branch := _wet_branch_for_node(str(node.name), inherited_branch)
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count := mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 0
		for surface_index in range(surface_count):
			var active_material := mesh_instance.get_active_material(surface_index)
			if not active_material is BaseMaterial3D:
				continue
			var source_material := active_material as BaseMaterial3D
			var profile := _wetness_profile(source_material)
			if bool(profile.get("excluded", false)):
				continue
			var source_id := source_material.get_instance_id()
			if not _wet_source_records.has(source_id):
				_wet_source_records[source_id] = {
					"source": source_material,
					"runtime": null,
					"profile": profile,
					"response_scale": 0.55 if source_material.resource_name.begins_with("M_Wet") else 1.0,
					"dry_color": source_material.albedo_color,
					"dry_roughness": source_material.roughness,
					"dry_clearcoat_enabled": source_material.clearcoat_enabled,
					"dry_clearcoat": source_material.clearcoat,
					"dry_clearcoat_roughness": source_material.clearcoat_roughness,
				}
			var bindings: Array = _wet_bindings_by_branch.get(branch, [])
			bindings.append({
				"mesh": mesh_instance,
				"surface_index": surface_index,
				"source_id": source_id,
			})
			_wet_bindings_by_branch[branch] = bindings
	for child in node.get_children():
		_cache_wet_materials_recursive(child, branch)


func _cache_amber_lamp_materials_recursive(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var surface_count := mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 0
		for surface_index in range(surface_count):
			var active_material := mesh_instance.get_active_material(surface_index)
			if not active_material is BaseMaterial3D:
				continue
			var source_material := active_material as BaseMaterial3D
			if source_material.resource_name != AMBER_LAMP_MATERIAL_NAME:
				continue
			var source_id := source_material.get_instance_id()
			if not _amber_lamp_records.has(source_id):
				_amber_lamp_records[source_id] = {
					"runtime": source_material.duplicate(false) as BaseMaterial3D,
				}
			var record: Dictionary = _amber_lamp_records[source_id]
			mesh_instance.set_surface_override_material(surface_index, record.runtime as BaseMaterial3D)
	for child in node.get_children():
		_cache_amber_lamp_materials_recursive(child)


func _build_powered_deck_vfx() -> void:
	# J-7 uses three exact mount points and two inexpensive transparent quads per
	# mount. The effect communicates origin and direction without a physical lamp
	# fixture or a Light3D response that would paint a false source on the deck.
	if platform_rig == null or not _deck_light_mounts.is_empty():
		return
	if (
		J7_DECK_LIGHT_ANCHORS.size() != J7_DECK_LIGHT_TARGETS.size()
		or J7_DECK_LIGHT_ANCHORS.size() != J7_DECK_BEAM_WIDTHS.size()
		or J7_DECK_LIGHT_ANCHORS.size() != J7_DECK_BEAM_OPACITIES.size()
		or J7_DECK_LIGHT_ANCHORS.size() != J7_DECK_BEAM_CAMERA_OFFSETS.size()
	):
		push_error("J-7 deck VFX anchors, targets, beam widths, opacities and camera offsets must have matching sizes.")
		return
	var vfx_shader := ResourceLoader.load(J7_LIGHT_VFX_SHADER_PATH) as Shader
	if vfx_shader == null:
		push_error("J-7 directional light VFX shader is required: %s" % J7_LIGHT_VFX_SHADER_PATH)
		return
	var camera_local_position := Vector3(0.0, 31.5, 48.0)
	if camera != null:
		# build() is also used before this world enters the SceneTree. In that case
		# PlatformRig3D and Camera3D are siblings, so the camera's local position is
		# already expressed in the rig parent's coordinate space.
		camera_local_position = (
			platform_rig.to_local(camera.global_position)
			if camera.is_inside_tree()
			else camera.position
		)
	for index in range(J7_DECK_LIGHT_ANCHORS.size()):
		var anchor := J7_DECK_LIGHT_ANCHORS[index]
		var target_offset := J7_DECK_LIGHT_TARGETS[index] - anchor
		if target_offset.length_squared() <= 0.000001:
			target_offset = Vector3.DOWN
		var target_distance := target_offset.length()
		var direction := target_offset / target_distance

		var mount := Marker3D.new()
		mount.name = "J7DeckLightMount%02d" % (index + 1)
		mount.position = anchor
		platform_rig.add_child(mount)
		_deck_light_mounts.append(mount)

		var beam := MeshInstance3D.new()
		beam.name = "J7DeckDirectionalBeam%02d" % (index + 1)
		var beam_mesh := QuadMesh.new()
		var beam_length := maxf(target_distance * J7_DECK_BEAM_LENGTH_FACTOR, 0.10)
		beam_mesh.size = Vector2(J7_DECK_BEAM_WIDTHS[index], beam_length)
		beam.mesh = beam_mesh
		beam.material_override = _j7_light_vfx_material(vfx_shader, 0.0, J7_DECK_BEAM_OPACITIES[index], 1)
		var beam_midpoint := direction * beam_length * 0.50
		var beam_to_camera := (camera_local_position - anchor - beam_midpoint).normalized()
		var beam_y := -direction
		var beam_x := beam_y.cross(beam_to_camera)
		if beam_x.length_squared() <= 0.000001:
			beam_x = beam_y.cross(Vector3.RIGHT)
		beam_x = beam_x.normalized()
		var beam_z := beam_x.cross(beam_y).normalized()
		beam.transform = Transform3D(
			Basis(beam_x, beam_y, beam_z),
			beam_midpoint + beam_to_camera * J7_DECK_BEAM_CAMERA_OFFSETS[index]
		)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.extra_cull_margin = 1.0
		beam.visible = false
		mount.add_child(beam)
		_deck_light_beams.append(beam)

		var source_glow := MeshInstance3D.new()
		source_glow.name = "J7DeckSourceGlow%02d" % (index + 1)
		var source_glow_mesh := QuadMesh.new()
		source_glow_mesh.size = Vector2(J7_DECK_SOURCE_GLOW_SIZE, J7_DECK_SOURCE_GLOW_SIZE)
		source_glow.mesh = source_glow_mesh
		source_glow.material_override = _j7_light_vfx_material(vfx_shader, 1.0, J7_DECK_SOURCE_GLOW_OPACITY, 2)
		var source_to_camera := (camera_local_position - anchor).normalized()
		var glow_up := Vector3.FORWARD if absf(source_to_camera.dot(Vector3.UP)) > 0.98 else Vector3.UP
		source_glow.transform = Transform3D(
			Basis.looking_at(source_to_camera, glow_up),
			source_to_camera * J7_DECK_SOURCE_CAMERA_OFFSET
		)
		source_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		source_glow.extra_cull_margin = 0.5
		source_glow.visible = false
		mount.add_child(source_glow)
		_deck_light_source_glows.append(source_glow)
	_apply_powered_deck_vfx()


func _j7_light_vfx_material(
	shader: Shader,
	effect_mode: float,
	opacity: float,
	render_priority: int
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = render_priority
	material.set_shader_parameter("light_color", J7_DECK_VFX_COLOR)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("intensity", 1.0)
	material.set_shader_parameter("effect_mode", effect_mode)
	return material


func _suppress_amber_lamp_emission() -> void:
	for amber_entry_value in _amber_lamp_records.values():
		var amber_entry: Dictionary = amber_entry_value
		var material := amber_entry.get("runtime") as BaseMaterial3D
		if material == null:
			continue
		material.emission_enabled = false
		material.emission_energy_multiplier = 0.0


func _apply_powered_deck_vfx() -> void:
	for beam in _deck_light_beams:
		if beam != null:
			beam.visible = _powered_presentation
	for source_glow in _deck_light_source_glows:
		if source_glow != null:
			source_glow.visible = _powered_presentation


func _wet_branch_for_node(node_name: String, inherited_branch: String) -> String:
	if node_name.begins_with("Ruin_"):
		return "ruin:%s" % node_name.trim_prefix("Ruin_")
	if node_name.begins_with("Built_"):
		var branch_value := node_name.trim_prefix("Built_")
		var level_separator := branch_value.rfind("_L")
		if level_separator > 0:
			return "built:%s:%s" % [branch_value.left(level_separator), branch_value.substr(level_separator + 2)]
	return inherited_branch


func _install_active_wet_branches() -> void:
	_install_wet_branch("common")
	for slot_id in SLOT_IDS:
		var state: Dictionary = _slot_states.get(slot_id, {"is_built": false, "level": 0})
		if bool(state.get("is_built", false)):
			_install_wet_branch("built:%s:%d" % [slot_id, clampi(int(state.get("level", 1)), 1, 4)])
		else:
			_install_wet_branch("ruin:%s" % slot_id)


func _install_wet_branch(branch: String) -> void:
	if _wet_installed_branches.has(branch) or not _wet_bindings_by_branch.has(branch):
		return
	var created_runtime := false
	for binding in _wet_bindings_by_branch[branch]:
		var mesh_instance: MeshInstance3D = binding.mesh
		if not is_instance_valid(mesh_instance):
			continue
		var source_id := int(binding.source_id)
		var record: Dictionary = _wet_source_records[source_id]
		var runtime_material := record.runtime as BaseMaterial3D
		if runtime_material == null:
			runtime_material = (record.source as BaseMaterial3D).duplicate(false) as BaseMaterial3D
			record.runtime = runtime_material
			_wet_source_records[source_id] = record
			_wet_material_entries.append(record)
			created_runtime = true
		mesh_instance.set_surface_override_material(int(binding.surface_index), runtime_material)
	_wet_installed_branches[branch] = true
	if created_runtime:
		_apply_cached_wetness(_current_deck_wetness, true)


func _apply_cached_wetness(wetness: float, force := false) -> void:
	_current_deck_wetness = clampf(wetness, 0.0, 1.0)
	if not force and absf(_current_deck_wetness - _last_applied_wetness) <= 0.0001:
		return
	_last_applied_wetness = _current_deck_wetness
	var wet_curve := smoothstep(0.10, 0.95, _current_deck_wetness)
	for entry in _wet_material_entries:
		var material: BaseMaterial3D = entry.runtime
		var profile: Dictionary = entry.profile
		var effective_wetness := wet_curve * float(entry.response_scale)
		var dry_roughness := float(entry.dry_roughness)
		var roughness_target := maxf(
			dry_roughness * float(profile.roughness_multiplier),
			float(profile.roughness_floor)
		)
		material.roughness = lerpf(dry_roughness, roughness_target, effective_wetness)
		var dry_color: Color = entry.dry_color
		var color_multiplier := lerpf(1.0, float(profile.albedo_multiplier), effective_wetness)
		material.albedo_color = Color(
			dry_color.r * color_multiplier,
			dry_color.g * color_multiplier,
			dry_color.b * color_multiplier,
			dry_color.a
		)
		if bool(profile.preserve_clearcoat):
			material.clearcoat_enabled = bool(entry.dry_clearcoat_enabled)
			material.clearcoat = float(entry.dry_clearcoat)
			material.clearcoat_roughness = float(entry.dry_clearcoat_roughness)
			continue
		# BaseMaterial3D may keep a numeric default coat of 1.0 while the lobe is
		# disabled. Treat that disabled value as zero, otherwise enabling wetness
		# would accidentally turn the default into a full plastic coat.
		var dry_clearcoat := float(entry.dry_clearcoat) if bool(entry.dry_clearcoat_enabled) else 0.0
		var target_clearcoat := maxf(dry_clearcoat, float(profile.clearcoat_max))
		material.clearcoat = lerpf(dry_clearcoat, target_clearcoat, effective_wetness)
		material.clearcoat_enabled = bool(entry.dry_clearcoat_enabled) or (
			float(profile.clearcoat_max) > 0.001 and effective_wetness > 0.001
		)
		material.clearcoat_roughness = lerpf(
			float(entry.dry_clearcoat_roughness),
			float(profile.clearcoat_roughness),
			effective_wetness
		)


func _wetness_profile(material: BaseMaterial3D) -> Dictionary:
	var material_name := material.resource_name
	if material_name in ["M_AmberLamp", "M_RedNavigationLamp"]:
		return {"excluded": true}
	if material_name == "M_MeshyPlatformPBR":
		return _wetness_values(0.98, 0.88, 0.36, 0.08, 0.28)
	if material_name in ["M_RustFresh", "M_RustOxide", "M_RustDark"]:
		return _wetness_values(0.89, 0.90, 0.55, 0.0, 0.34)
	if material_name in ["M_SafetyOchre", "M_SafetyYellow", "M_FadedMarineBlue", "M_FadedTeal", "M_WeatheredOffWhite", "M_MedicalRed"]:
		return _wetness_values(0.95, 0.82, 0.34, 0.12, 0.30)
	if material_name in ["M_DeepSteel", "M_WetGraphiteSteel", "M_WeatheredSteel", "M_GalvanizedSteel"]:
		return _wetness_values(0.99, 0.78, 0.28, 0.14, 0.24)
	if material_name == "M_SaltStainedGlass":
		return _wetness_values(1.0, 0.98, 0.14, 0.0, 0.0, true)
	if material_name in ["M_WetRope", "M_FadedBlueCanvas"]:
		return _wetness_values(0.86, 0.94, 0.72, 0.0, 0.40)
	if material_name in ["M_WetSalvageWood", "M_BleachedWood"]:
		return _wetness_values(0.88, 0.90, 0.60, 0.0, 0.40)
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return {"excluded": true}
	return _wetness_values(0.96, 0.88, 0.44, 0.05, 0.30)


func _wetness_values(
	albedo_multiplier: float,
	roughness_multiplier: float,
	roughness_floor: float,
	clearcoat_max: float,
	clearcoat_roughness: float,
	preserve_clearcoat := false
) -> Dictionary:
	return {
		"excluded": false,
		"albedo_multiplier": albedo_multiplier,
		"roughness_multiplier": roughness_multiplier,
		"roughness_floor": roughness_floor,
		"clearcoat_max": clearcoat_max,
		"clearcoat_roughness": clearcoat_roughness,
		"preserve_clearcoat": preserve_clearcoat,
	}


func _apply_mesh_quality_recursive(node: Node) -> void:
	if node == null:
		return
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		# The Meshy shell is intentionally a high-detail source mesh. Generated
		# import LODs keep medium/low practical without changing the high preset.
		geometry.lod_bias = 1.0 if _graphics_quality == "high" else 0.55 if _graphics_quality == "medium" else 0.25
	for child in node.get_children():
		_apply_mesh_quality_recursive(child)


func _find_node_recursive(root: Node, target_name: String) -> Node:
	if root == null:
		return null
	if root.name == target_name:
		return root
	for child in root.get_children():
		var result := _find_node_recursive(child, target_name)
		if result != null:
			return result
	return null


func _standard_material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _add_box(root: Node3D, box_size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mesh_instance.mesh = box
	mesh_instance.position = position
	mesh_instance.material_override = material
	root.add_child(mesh_instance)
	return mesh_instance
