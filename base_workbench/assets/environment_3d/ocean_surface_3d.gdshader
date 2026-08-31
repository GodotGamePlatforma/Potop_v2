shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Opaque deep water is intentional: the base view never exposes the seabed.
// Keeping the core in the opaque PBR pass gives stable depth and sky reflections
// without transparent sorting.
uniform int quality_level : hint_range(0, 2, 1) = 2;
uniform float weather_intensity : hint_range(0.0, 1.0) = 0.62;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.52;
uniform vec2 wind_direction = vec2(0.82, 0.57);
uniform float wave_amplitude_scale : hint_range(0.0, 2.0) = 1.0;
uniform float wave_speed_scale : hint_range(0.0, 2.0) = 1.0;
uniform float wave_steepness : hint_range(0.0, 1.0) = 0.68;
// BaseWorld3D owns these canonical components and binds them to the shader.
// x = amplitude, y = wavelength, z = speed response, w = angle from wind.
uniform vec4 macro_wave_a = vec4(0.30, 16.5, 0.76, 0.0);
uniform vec4 macro_wave_b = vec4(0.17, 8.2, 0.94, 0.58);
uniform vec4 macro_wave_c = vec4(0.085, 4.3, 1.12, -1.04);
uniform vec3 macro_wave_steepness_weights = vec3(1.0, 0.78, 0.58);

// A non-negative value replaces TIME and makes visual tests deterministic.
// Reduced motion keeps macro weather readable and only damps micro drift.
uniform float time_override = -1.0;
uniform bool reduced_motion = false;
uniform float reduced_micro_motion : hint_range(0.0, 1.0) = 0.30;

uniform vec3 deep_water_color : source_color = vec3(0.065, 0.092, 0.105);
uniform vec3 body_water_color : source_color = vec3(0.115, 0.148, 0.160);
uniform vec3 crest_water_color : source_color = vec3(0.180, 0.215, 0.220);
uniform vec3 storm_tint : source_color = vec3(0.050, 0.064, 0.076);
uniform float water_roughness : hint_range(0.0, 1.0) = 0.29;
uniform float water_specular : hint_range(0.0, 1.0) = 0.50;

uniform vec3 foam_color : source_color = vec3(0.58, 0.60, 0.58);
uniform float crest_foam_strength : hint_range(0.0, 2.0) = 0.72;
uniform float crest_foam_threshold : hint_range(0.0, 1.5) = 0.70;
uniform float foam_drift_speed : hint_range(0.0, 2.0) = 0.075;
uniform float foam_breakup : hint_range(0.0, 1.0) = 0.30;
uniform float foam_roughness : hint_range(0.0, 1.0) = 0.79;
uniform float residual_foam_strength : hint_range(0.0, 1.5) = 0.74;
uniform float residual_foam_transport : hint_range(0.0, 2.0) = 0.46;

// Contact foam is an analytic waterline around the real platform footprint.
// It replaces the old screen-depth halo, which also outlined railings, crane
// parts and other geometry far above the sea.
uniform vec2 platform_position_xz = vec2(0.0);
uniform vec2 platform_half_extents = vec2(10.25, 7.05);
uniform float platform_corner_radius : hint_range(0.1, 4.0) = 1.15;
uniform float contact_foam_width : hint_range(0.05, 3.0) = 0.42;
uniform float contact_foam_strength : hint_range(0.0, 2.0) = 0.65;
uniform float platform_contact_energy : hint_range(0.0, 1.0) = 0.35;
// Presentation-only A/B switch. Scattering is analytic and has no history;
// disabling it restores the canonical incident Gerstner field exactly.
uniform bool platform_scattering_enabled = true;
// Art-direction is deliberately exposed as a compact pair: x = dominant long
// wave A, y = shorter wave B. Both transmission values remain below one, so the
// floating/open platform never behaves like an impermeable breakwater.
uniform vec2 platform_scattering_transmission_loss = vec2(0.40, 0.56);
uniform vec2 platform_scattering_reflection_strength = vec2(0.27, 0.18);
// x/y/z/w = retained lee chop, glint, fresh Stage A, transported Stage B.
uniform vec4 platform_scattering_lee_retention = vec4(0.68, 0.58, 0.42, 0.70);
uniform float platform_impact_foam_strength : hint_range(0.0, 1.0) = 0.72;
uniform float platform_reflected_foam_strength : hint_range(0.0, 1.0) = 0.34;
// x/y/z/w = front(+Z), right(+X), back(-Z), left(-X).
uniform vec4 platform_contact_energy_sides = vec4(0.35);
// The two vectors follow the eight real spray/pontoon anchors owned by BaseWorld3D.
uniform vec4 pontoon_contact_energy_a = vec4(0.35);
uniform vec4 pontoon_contact_energy_b = vec4(0.35);

varying vec3 ocean_world_position;
varying vec2 ocean_base_xz;
varying vec3 ocean_macro_normal_world;
// xyz = scattering height/slope delta, w = directional lee mask.
varying vec4 ocean_platform_scattering;

const float TAU_VALUE = 6.28318530718;
const float GRAVITY_VALUE = 9.81;


vec2 safe_direction(vec2 direction_value) {
	float length_squared = dot(direction_value, direction_value);
	if (length_squared < 0.0001) {
		return vec2(1.0, 0.0);
	}
	return direction_value * inversesqrt(length_squared);
}


mat2 rotation_2d(float angle) {
	float sine_value = sin(angle);
	float cosine_value = cos(angle);
	return mat2(
		vec2(cosine_value, sine_value),
		vec2(-sine_value, cosine_value)
	);
}


float presentation_time() {
	return time_override >= 0.0 ? time_override : TIME;
}


void accumulate_gerstner(
	inout vec3 displaced,
	inout vec3 derivative_x,
	inout vec3 derivative_z,
	vec2 base_xz,
	vec2 direction_value,
	float amplitude,
	float wavelength,
	float speed,
	float steepness,
	float time_value
) {
	vec2 direction_normalized = safe_direction(direction_value);
	float wave_number = TAU_VALUE / max(wavelength, 0.05);
	float angular_frequency = sqrt(GRAVITY_VALUE * wave_number) * speed;
	float phase = wave_number * dot(direction_normalized, base_xz) - angular_frequency * time_value;
	float sine_phase = sin(phase);
	float cosine_phase = cos(phase);
	float horizontal_offset = steepness * amplitude * cosine_phase;
	float derivative_common = steepness * amplitude * wave_number * sine_phase;

	displaced.x += direction_normalized.x * horizontal_offset;
	displaced.y += amplitude * sine_phase;
	displaced.z += direction_normalized.y * horizontal_offset;

	derivative_x += vec3(
		-direction_normalized.x * direction_normalized.x * derivative_common,
		amplitude * direction_normalized.x * wave_number * cosine_phase,
		-direction_normalized.x * direction_normalized.y * derivative_common
	);
	derivative_z += vec3(
		-direction_normalized.x * direction_normalized.y * derivative_common,
		amplitude * direction_normalized.y * wave_number * cosine_phase,
		-direction_normalized.y * direction_normalized.y * derivative_common
	);
}


vec4 sample_macro_wave_field(vec2 base_xz, float time_value) {
	vec2 primary = safe_direction(wind_direction);
	float final_amplitude = max(wave_amplitude_scale, 0.0);
	float final_speed = max(wave_speed_scale, 0.0);
	float height = 0.0;
	vec2 slope = vec2(0.0);
	float jacobian_00 = 1.0;
	float jacobian_01 = 0.0;
	float jacobian_10 = 0.0;
	float jacobian_11 = 1.0;

	vec4 components[3] = vec4[](macro_wave_a, macro_wave_b, macro_wave_c);
	int component_count = quality_level >= 1 ? 3 : 2;
	for (int index = 0; index < component_count; index++) {
		vec2 direction_value = rotation_2d(components[index].w) * primary;
		float amplitude = components[index].x * final_amplitude;
		float wave_number = TAU_VALUE / max(components[index].y, 0.05);
		float angular_frequency = sqrt(GRAVITY_VALUE * wave_number) * components[index].z * final_speed;
		float phase = wave_number * dot(direction_value, base_xz) - angular_frequency * time_value;
		height += amplitude * sin(phase);
		slope += direction_value * amplitude * wave_number * cos(phase);
		// The determinant of the horizontal Gerstner Jacobian is used as an
		// art-directed compression proxy. It shares the exact wave phase with the
		// displaced geometry and avoids inventing a separate foam wave field.
		float compression_term = clamp(wave_steepness, 0.0, 0.90)
			* macro_wave_steepness_weights[index] * amplitude * wave_number * sin(phase);
		jacobian_00 -= compression_term * direction_value.x * direction_value.x;
		jacobian_01 -= compression_term * direction_value.x * direction_value.y;
		jacobian_10 -= compression_term * direction_value.y * direction_value.x;
		jacobian_11 -= compression_term * direction_value.y * direction_value.y;
	}
	float jacobian_determinant = jacobian_00 * jacobian_11 - jacobian_01 * jacobian_10;
	float compression = clamp(1.0 - jacobian_determinant, 0.0, 1.0);
	return vec4(height, slope, compression);
}


float macro_total_amplitude() {
	float amplitude = macro_wave_a.x + macro_wave_b.x;
	if (quality_level >= 1) {
		amplitude += macro_wave_c.x;
	}
	return max(amplitude * max(wave_amplitude_scale, 0.0), 0.001);
}


float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32);
	return fract(point.x * point.y);
}


float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float lower_left = hash21(cell);
	float lower_right = hash21(cell + vec2(1.0, 0.0));
	float upper_left = hash21(cell + vec2(0.0, 1.0));
	float upper_right = hash21(cell + vec2(1.0, 1.0));
	return mix(
		mix(lower_left, lower_right, local.x),
		mix(upper_left, upper_right, local.x),
		local.y
	);
}


float quality_noise(vec2 point) {
	float result = value_noise(point) * 0.58;
	point = rotation_2d(0.61) * point * 2.03 + vec2(7.1, 3.7);
	result += value_noise(point) * 0.27;
	if (quality_level >= 1) {
		point = rotation_2d(-0.47) * point * 2.07 + vec2(13.4, 9.2);
		result += value_noise(point) * 0.11;
	}
	if (quality_level >= 2) {
		point = rotation_2d(0.83) * point * 2.01 + vec2(5.8, 17.6);
		result += value_noise(point) * 0.04;
	}
	return result;
}


vec3 rain_impact_layer(
	vec2 world_xz,
	float time_value,
	float cell_size,
	float cycles_per_second,
	float rotation_angle,
	vec2 seed_offset
) {
	// One deterministic impact lives inside each sufficiently small world-space
	// cell. Its center changes every cycle, while the fade is zero at both ends,
	// so there is no temporal pop or texture sliding across the Gerstner surface.
	vec2 grid_point = rotation_2d(rotation_angle) * world_xz / max(cell_size, 0.1);
	vec2 cell = floor(grid_point);
	vec2 local_point = fract(grid_point);
	float cycle_position = time_value * cycles_per_second + hash21(cell + seed_offset);
	float cycle_index = mod(floor(cycle_position), 4096.0);
	float age = fract(cycle_position);
	vec2 event_key = cell + seed_offset + vec2(cycle_index * 0.754877, cycle_index * 1.569840);
	float density = mix(0.14, 0.82, pow(clamp(rain_intensity, 0.0, 1.0), 0.70));
	float exists = step(1.0 - density, hash21(event_key + vec2(17.31, 8.73)));
	vec2 center = vec2(
		hash21(event_key + vec2(3.17, 29.41)),
		hash21(event_key + vec2(41.73, 6.19))
	);
	// Keeping centers away from cell edges lets one sample cover the complete
	// ripple without a costly 3x3 neighbour search or visible cell clipping.
	center = mix(vec2(0.31), vec2(0.69), center);
	vec2 offset = (local_point - center) * cell_size;
	float distance_to_impact = length(offset);
	float ring_radius = mix(0.015, min(0.26, cell_size * 0.22), smoothstep(0.0, 1.0, age));
	float ring_width = mix(0.026, 0.013, age) + max(fwidth(distance_to_impact), 0.0025);
	float signed_shell = (distance_to_impact - ring_radius) / max(ring_width, 0.004);
	float shell = exp(-signed_shell * signed_shell * 1.35);
	float life_fade = smoothstep(0.0, 0.07, age) * (1.0 - smoothstep(0.58, 1.0, age));
	vec2 radial_direction = rotation_2d(-rotation_angle) * offset / max(distance_to_impact, 0.001);
	// The signed derivative of the shell perturbs the normal on both sides of
	// the rim. The third component is a small reflection/roughness response.
	vec2 slope = radial_direction * (-signed_shell * shell) * life_fade * exists;
	return vec3(slope, shell * life_fade * exists);
}


float filtered_sine_ridge(float phase, float exponent_value) {
	float ridge = pow(max(sin(phase), 0.0), exponent_value);
	// Thin procedural highlights are fragment detail, so MSAA cannot stabilize
	// them. Fade ridges whose screen footprint approaches a pixel instead of
	// allowing distant high-frequency lines to shimmer frame to frame.
	float stability = 1.0 - smoothstep(0.18, 0.62, fwidth(phase));
	return ridge * stability;
}


vec2 procedural_micro_slope(vec2 world_xz, float time_value) {
	vec2 primary = safe_direction(wind_direction);
	vec2 secondary = rotation_2d(0.72) * primary;
	vec2 tertiary = rotation_2d(-1.08) * primary;
	vec2 quaternary = rotation_2d(1.77) * primary;
	float motion_scale = reduced_motion ? reduced_micro_motion : 1.0;
	float motion_time = time_value * max(wave_speed_scale, 0.0) * motion_scale;
	float weather_scale = mix(0.78, 1.12, weather_intensity);
	float strength_scale = (reduced_motion ? 0.62 : 1.0) * weather_scale;

	vec2 slope = primary * cos(dot(world_xz, primary) * 2.55 - motion_time * 1.18) * 0.061;
	slope += secondary * cos(dot(world_xz, secondary) * 4.40 - motion_time * 1.71 + 1.7) * 0.038;
	if (quality_level >= 1) {
		slope += tertiary * cos(dot(world_xz, tertiary) * 7.25 - motion_time * 2.18 + 4.1) * 0.024;
	}
	if (quality_level >= 2) {
		slope += quaternary * cos(dot(world_xz, quaternary) * 11.6 - motion_time * 2.82 + 2.4) * 0.014;
	}
	// Two wind-locked procedural noise gradients break the parallel ripples into
	// natural short facets. Unlike the retired painted image, this detail changes
	// only the normal and never slides a recognisable albedo pattern over the sea.
	float sample_step = 0.055;
	vec2 noise_point = rotation_2d(0.37) * world_xz * 0.61 - primary * motion_time * 0.074;
	vec2 noise_gradient = vec2(
		quality_noise(noise_point + vec2(sample_step, 0.0)) - quality_noise(noise_point - vec2(sample_step, 0.0)),
		quality_noise(noise_point + vec2(0.0, sample_step)) - quality_noise(noise_point - vec2(0.0, sample_step))
	) / (sample_step * 2.0);
	slope += rotation_2d(-0.37) * noise_gradient * 0.022;
	if (quality_level >= 2) {
		vec2 fine_point = rotation_2d(-0.91) * world_xz * 1.43 + secondary * motion_time * 0.106;
		vec2 fine_gradient = vec2(
			value_noise(fine_point + vec2(sample_step, 0.0)) - value_noise(fine_point - vec2(sample_step, 0.0)),
			value_noise(fine_point + vec2(0.0, sample_step)) - value_noise(fine_point - vec2(0.0, sample_step))
		) / (sample_step * 2.0);
		slope += rotation_2d(0.91) * fine_gradient * 0.011;
	}
	return slope * strength_scale;
}


float rounded_box_sdf(vec2 point, vec2 half_extents, float radius) {
	vec2 q = abs(point) - max(half_extents - vec2(radius), vec2(0.0));
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
}


float smoothstep_derivative(float edge_start, float edge_end, float value) {
	float edge_width = max(edge_end - edge_start, 0.0001);
	float normalized_value = clamp((value - edge_start) / edge_width, 0.0, 1.0);
	return 6.0 * normalized_value * (1.0 - normalized_value) / edge_width;
}


vec2 platform_projected_extents(vec2 wave_direction_value) {
	vec2 direction_value = safe_direction(wave_direction_value);
	vec2 sideways = vec2(-direction_value.y, direction_value.x);
	vec2 hull_extents = max(platform_half_extents - vec2(0.18), vec2(0.1));
	return vec2(
		dot(abs(direction_value), hull_extents),
		dot(abs(sideways), hull_extents)
	);
}


vec4 platform_shadow_edge_points(vec2 wave_direction_value) {
	// A smooth elliptical approximation supplies two silhouette points without
	// snapping between rectangle corners when the wind crosses a cardinal axis.
	// The rounded-box extents still own the reflection and transmission masks.
	vec2 direction_value = safe_direction(wave_direction_value);
	vec2 sideways = vec2(-direction_value.y, direction_value.x);
	vec2 hull_extents = max(platform_half_extents - vec2(0.18), vec2(0.1));
	float denominator = max(length(hull_extents * sideways), 0.001);
	vec2 edge_point = vec2(
		hull_extents.x * hull_extents.x * sideways.x,
		hull_extents.y * hull_extents.y * sideways.y
	) / denominator;
	return vec4(edge_point, -edge_point);
}


vec4 sample_platform_scattering_component(
	vec2 base_world_xz,
	float time_value,
	vec4 wave_component,
	float transmission_loss,
	float reflection_strength,
	float diffraction_strength
) {
	vec2 direction_value = rotation_2d(wave_component.w) * safe_direction(wind_direction);
	vec2 sideways = vec2(-direction_value.y, direction_value.x);
	vec2 platform_local = base_world_xz - platform_position_xz;
	vec2 projected_extents = platform_projected_extents(direction_value);
	float along_wave = dot(platform_local, direction_value);
	float across_wave = dot(platform_local, sideways);
	float wavelength = max(wave_component.y, 0.05);
	float wave_number = TAU_VALUE / wavelength;
	float angular_frequency = sqrt(GRAVITY_VALUE * wave_number)
		* wave_component.z * max(wave_speed_scale, 0.0);
	float amplitude = max(wave_component.x * wave_amplitude_scale, 0.0);
	if (amplitude <= 0.00001) {
		return vec4(0.0);
	}

	float incident_phase = wave_number * dot(direction_value, base_world_xz)
		- angular_frequency * time_value;
	float incident_sine = sin(incident_phase);
	float incident_cosine = cos(incident_phase);

	// Transmission: a soft, non-zero lee shadow follows the real direction of
	// this wave component. Its core narrows, its edge softens and the incident
	// wave recovers over several wavelengths, so no dead flat patch forms.
	float downstream_distance = along_wave - projected_extents.x;
	float downstream_positive = max(downstream_distance, 0.0);
	float downstream_gate = smoothstep(-0.30, 0.78, downstream_distance);
	vec2 downstream_gate_gradient = direction_value
		* smoothstep_derivative(-0.30, 0.78, downstream_distance);
	// The protected core narrows downstream while its transition broadens. Edge
	// diffraction therefore fills the shadow instead of a widening hard wedge.
	float lee_core_shrink = 0.045;
	float lee_raw_width = projected_extents.y - downstream_positive * lee_core_shrink;
	float lee_minimum_width = projected_extents.y * 0.42;
	float lee_width = max(lee_raw_width, lee_minimum_width);
	vec2 lee_width_gradient = vec2(0.0);
	if (downstream_distance > 0.0 && lee_raw_width > lee_minimum_width) {
		lee_width_gradient = -direction_value * lee_core_shrink;
	}
	float lee_softness_growth = 0.055;
	float lee_softness = max(wavelength * 0.105, 0.80)
		+ downstream_positive * lee_softness_growth;
	vec2 lee_softness_gradient = downstream_distance > 0.0
		? direction_value * lee_softness_growth
		: vec2(0.0);
	float lee_lateral_coordinate = abs(across_wave) - lee_width;
	float lee_lateral = 1.0 - smoothstep(-lee_softness, lee_softness, lee_lateral_coordinate);
	vec2 lee_lateral_coordinate_gradient = sign(across_wave) * sideways - lee_width_gradient;
	float lee_softness_t = clamp(
		0.5 + lee_lateral_coordinate / max(2.0 * lee_softness, 0.001),
		0.0,
		1.0
	);
	float lee_lateral_softness_derivative = 6.0 * lee_softness_t
		* (1.0 - lee_softness_t) * (lee_softness_t - 0.5) / max(lee_softness, 0.001);
	vec2 lee_lateral_gradient = -smoothstep_derivative(
		-lee_softness,
		lee_softness,
		lee_lateral_coordinate
	) * lee_lateral_coordinate_gradient
		+ lee_lateral_softness_derivative * lee_softness_gradient;
	float recovery_length = wavelength * 1.45;
	float lee_recovery = exp(-downstream_positive / max(recovery_length, 0.1));
	vec2 lee_recovery_gradient = vec2(0.0);
	if (downstream_distance > 0.0) {
		lee_recovery_gradient = -direction_value * lee_recovery / max(recovery_length, 0.1);
	}
	float lee_mask = downstream_gate * lee_lateral * lee_recovery;
	vec2 lee_gradient = downstream_gate_gradient * lee_lateral * lee_recovery
		+ downstream_gate * lee_lateral_gradient * lee_recovery
		+ downstream_gate * lee_lateral * lee_recovery_gradient;
	float transmission = 1.0 - transmission_loss * lee_mask;
	float scattered_height = (transmission - 1.0) * amplitude * incident_sine;
	vec2 scattered_slope = -transmission_loss * amplitude * (
		lee_gradient * incident_sine
		+ lee_mask * incident_cosine * wave_number * direction_value
	);

	// Reflection: the weak phase-matched return travels back upwave and decays
	// quickly. It is intentionally far below a rigid seawall response because the
	// floating, open-bottom platform still transmits most long-wave energy.
	float upstream_distance = -along_wave - projected_extents.x;
	float upstream_positive = max(upstream_distance, 0.0);
	vec2 upstream_distance_gradient = -direction_value;
	float reflection_gate = smoothstep(-0.24, 0.66, upstream_distance);
	vec2 reflection_gate_gradient = upstream_distance_gradient
		* smoothstep_derivative(-0.24, 0.66, upstream_distance);
	float reflection_decay_length = wavelength * 0.62;
	float reflection_decay = exp(-upstream_positive / max(reflection_decay_length, 0.1));
	vec2 reflection_decay_gradient = vec2(0.0);
	if (upstream_distance > 0.0) {
		reflection_decay_gradient = upstream_distance_gradient
			* (-reflection_decay / max(reflection_decay_length, 0.1));
	}
	float reflection_spread = 0.065;
	float reflection_width = projected_extents.y + upstream_positive * reflection_spread;
	float reflection_softness = max(wavelength * 0.095, 0.72);
	float reflection_lateral_coordinate = abs(across_wave) - reflection_width;
	vec2 reflection_lateral_coordinate_gradient = sign(across_wave) * sideways;
	if (upstream_distance > 0.0) {
		reflection_lateral_coordinate_gradient -= upstream_distance_gradient * reflection_spread;
	}
	float reflection_lateral = 1.0 - smoothstep(
		-reflection_softness,
		reflection_softness,
		reflection_lateral_coordinate
	);
	vec2 reflection_lateral_gradient = -smoothstep_derivative(
		-reflection_softness,
		reflection_softness,
		reflection_lateral_coordinate
	) * reflection_lateral_coordinate_gradient;
	float reflection_mask = reflection_gate * reflection_decay * reflection_lateral;
	vec2 reflection_mask_gradient = reflection_gate_gradient * reflection_decay * reflection_lateral
		+ reflection_gate * reflection_decay_gradient * reflection_lateral
		+ reflection_gate * reflection_decay * reflection_lateral_gradient;
	float platform_phase = wave_number * dot(direction_value, platform_position_xz);
	float reflection_phase = -wave_number * along_wave + platform_phase
		- 2.0 * wave_number * projected_extents.x - angular_frequency * time_value;
	vec2 reflection_phase_gradient = -wave_number * direction_value;
	float interaction_scale = mix(0.84, 1.08, clamp(weather_intensity, 0.0, 1.0));
	float reflected_amplitude = amplitude * reflection_strength * interaction_scale;
	scattered_height += reflected_amplitude * reflection_mask * sin(reflection_phase);
	scattered_slope += reflected_amplitude * (
		reflection_mask_gradient * sin(reflection_phase)
		+ reflection_mask * cos(reflection_phase) * reflection_phase_gradient
	);

	// Diffraction: the two smooth silhouette points launch subtle, phase-matched
	// arcs into the lee. Every profile retains both A/B directions; quality only
	// redistributes a small stable detail budget toward the shorter component.
	if (diffraction_strength > 0.0001) {
		vec4 edge_points = platform_shadow_edge_points(direction_value);
		float diffraction_lateral_softness = max(wavelength * 0.42, 1.2);
		for (int edge_index = 0; edge_index < 2; edge_index++) {
			vec2 edge_point = edge_index == 0 ? edge_points.xy : edge_points.zw;
			vec2 radial_vector = platform_local - edge_point;
			float radial_distance = max(length(radial_vector), 0.001);
			vec2 radial_direction = radial_vector / radial_distance;
			float forward_distance = dot(radial_vector, direction_value);
			float diffraction_sector = smoothstep(-0.12, wavelength * 0.14, forward_distance);
			vec2 diffraction_sector_gradient = direction_value * smoothstep_derivative(
				-0.12,
				wavelength * 0.14,
				forward_distance
			);
			float forward_positive = max(forward_distance, 0.0);
			float diffraction_width = projected_extents.y + wavelength * 0.92 + forward_positive * 0.10;
			float diffraction_lateral_coordinate = abs(across_wave) - diffraction_width;
			vec2 diffraction_lateral_coordinate_gradient = sign(across_wave) * sideways;
			if (forward_distance > 0.0) {
				diffraction_lateral_coordinate_gradient -= direction_value * 0.10;
			}
			float diffraction_lateral = 1.0 - smoothstep(
				0.0,
				diffraction_lateral_softness,
				diffraction_lateral_coordinate
			);
			vec2 diffraction_lateral_gradient = -smoothstep_derivative(
				0.0,
				diffraction_lateral_softness,
				diffraction_lateral_coordinate
			) * diffraction_lateral_coordinate_gradient;
			float geometric_decay_scale = wavelength * 0.55;
			float geometric_decay_base = 1.0 + radial_distance / max(geometric_decay_scale, 0.1);
			float diffraction_decay = inversesqrt(geometric_decay_base)
				* exp(-radial_distance / max(wavelength * 3.0, 0.1));
			float diffraction_decay_derivative = diffraction_decay * (
				-0.5 / (max(geometric_decay_scale, 0.1) * geometric_decay_base)
				- 1.0 / max(wavelength * 3.0, 0.1)
			);
			vec2 diffraction_decay_gradient = radial_direction * diffraction_decay_derivative;
			float diffraction_mask = diffraction_sector * diffraction_lateral * diffraction_decay;
			vec2 diffraction_mask_gradient = diffraction_sector_gradient * diffraction_lateral * diffraction_decay
				+ diffraction_sector * diffraction_lateral_gradient * diffraction_decay
				+ diffraction_sector * diffraction_lateral * diffraction_decay_gradient;
			vec2 edge_world_xz = platform_position_xz + edge_point;
			float diffraction_phase = wave_number * radial_distance
				+ wave_number * dot(direction_value, edge_world_xz)
				- angular_frequency * time_value;
			vec2 diffraction_phase_gradient = wave_number * radial_direction;
			float diffracted_amplitude = amplitude * diffraction_strength * interaction_scale;
			scattered_height += diffracted_amplitude * diffraction_mask * sin(diffraction_phase);
			scattered_slope += diffracted_amplitude * (
				diffraction_mask_gradient * sin(diffraction_phase)
				+ diffraction_mask * cos(diffraction_phase) * diffraction_phase_gradient
			);
		}
	}

	return vec4(scattered_height, scattered_slope, clamp(lee_mask, 0.0, 1.0));
}


vec4 sample_platform_scattering(vec2 base_world_xz, float time_value) {
	if (!platform_scattering_enabled) {
		return vec4(0.0);
	}
	// A and B always receive their own directional transmission, reflection and
	// two-edge diffraction. Low leans more on the dominant A proxy; medium/high
	// spend their existing detail budget on the shorter B arcs as well.
	float diffraction_a = quality_level == 0 ? 0.074 : (quality_level >= 2 ? 0.064 : 0.068);
	float diffraction_b = quality_level >= 1 ? (quality_level >= 2 ? 0.050 : 0.044) : 0.032;
	vec4 scattering_a = sample_platform_scattering_component(
		base_world_xz,
		time_value,
		macro_wave_a,
		platform_scattering_transmission_loss.x,
		platform_scattering_reflection_strength.x,
		diffraction_a
	);
	vec4 scattering_b = sample_platform_scattering_component(
		base_world_xz,
		time_value,
		macro_wave_b,
		platform_scattering_transmission_loss.y,
		platform_scattering_reflection_strength.y,
		diffraction_b
	);
	return vec4(
		scattering_a.xyz + scattering_b.xyz,
		max(scattering_a.w, scattering_b.w)
	);
}


float sample_platform_scattering_height(vec2 base_world_xz, float time_value) {
	return sample_platform_scattering(base_world_xz, time_value).x;
}


float circle_sdf(vec2 point, vec2 centre, float radius) {
	return length(point - centre) - radius;
}


float platform_main_hull_sdf(vec2 point) {
	vec2 extents = max(platform_half_extents, vec2(0.1));
	return rounded_box_sdf(
		point,
		max(extents - vec2(0.28, 0.22), vec2(0.1)),
		platform_corner_radius
	);
}


vec2 nearest_pontoon_data(vec2 point) {
	vec2 anchors[8] = vec2[](
		vec2(-9.6, 6.4), vec2(-4.7, 7.3), vec2(1.0, 7.55), vec2(6.8, 7.2),
		vec2(10.0, 5.1), vec2(10.2, -2.1), vec2(-10.2, -1.6), vec2(-9.8, 3.0)
	);
	float energies[8] = float[](
		pontoon_contact_energy_a.x, pontoon_contact_energy_a.y,
		pontoon_contact_energy_a.z, pontoon_contact_energy_a.w,
		pontoon_contact_energy_b.x, pontoon_contact_energy_b.y,
		pontoon_contact_energy_b.z, pontoon_contact_energy_b.w
	);
	float nearest_distance = 1000.0;
	float nearest_energy = platform_contact_energy;
	for (int index = 0; index < 8; index++) {
		float candidate_distance = circle_sdf(point, anchors[index], 0.70);
		if (candidate_distance < nearest_distance) {
			nearest_distance = candidate_distance;
			nearest_energy = energies[index];
		}
	}
	return vec2(nearest_distance, nearest_energy);
}


float platform_waterline_sdf(vec2 point) {
	return min(platform_main_hull_sdf(point), nearest_pontoon_data(point).x);
}


vec2 platform_waterline_gradient(vec2 point) {
	const float GRADIENT_STEP = 0.045;
	float right_distance = platform_waterline_sdf(point + vec2(GRADIENT_STEP, 0.0));
	float left_distance = platform_waterline_sdf(point - vec2(GRADIENT_STEP, 0.0));
	float front_distance = platform_waterline_sdf(point + vec2(0.0, GRADIENT_STEP));
	float back_distance = platform_waterline_sdf(point - vec2(0.0, GRADIENT_STEP));
	return safe_direction(vec2(right_distance - left_distance, front_distance - back_distance));
}


float contact_energy_at(vec2 outward, vec2 pontoon_data) {
	vec4 side_weights = vec4(
		max(outward.y, 0.0),
		max(outward.x, 0.0),
		max(-outward.y, 0.0),
		max(-outward.x, 0.0)
	);
	float weight_sum = dot(side_weights, vec4(1.0));
	float side_energy = weight_sum >= 0.001
		? dot(side_weights, platform_contact_energy_sides) / weight_sum
		: platform_contact_energy;
	float pontoon_influence = 1.0 - smoothstep(0.10, 1.25, abs(pontoon_data.x));
	float local_energy = mix(side_energy, pontoon_data.y, pontoon_influence * 0.88);
	return mix(platform_contact_energy, local_energy, 0.90);
}


float platform_incident_component_impact(
	vec2 base_world_xz,
	float time_value,
	vec4 wave_component,
	vec2 outward,
	float hull_distance
) {
	vec2 direction_value = rotation_2d(wave_component.w) * safe_direction(wind_direction);
	float wavelength = max(wave_component.y, 0.05);
	float wave_number = TAU_VALUE / wavelength;
	float angular_frequency = sqrt(GRAVITY_VALUE * wave_number)
		* wave_component.z * max(wave_speed_scale, 0.0);
	float outside_distance = max(hull_distance, 0.0);
	vec2 boundary_xz = base_world_xz - outward * hull_distance;
	float incident_phase = wave_number * dot(direction_value, boundary_xz)
		- angular_frequency * time_value;

	// A rising upper half-cycle reads as a crest reaching the waterline rather
	// than a permanently painted stripe. The outward-normal test selects only the
	// side facing -d, so reversing WeatherState.wind_direction reverses the cue.
	float crest_height = max(sin(incident_phase), 0.0);
	float rising_face = max(-cos(incident_phase), 0.0);
	float crest_arrival = smoothstep(0.12, 0.62, crest_height * mix(0.38, 1.0, rising_face));
	float incidence = smoothstep(0.18, 0.72, max(dot(outward, -direction_value), 0.0));
	float interaction_reach = max(contact_foam_width * 2.85, 1.25);
	float waterline_band = 1.0 - smoothstep(0.02, interaction_reach, outside_distance);
	float outside_gate = smoothstep(-0.08, 0.12, hull_distance);
	float incident_energy = smoothstep(
		0.015,
		0.14,
		max(wave_component.x * wave_amplitude_scale, 0.0) * abs(angular_frequency)
	);
	return crest_arrival * incidence * waterline_band * outside_gate * incident_energy;
}


float platform_incident_impact_foam(
	vec2 base_world_xz,
	float time_value,
	vec2 outward,
	float hull_distance,
	float local_contact_energy,
	float contact_breakup
) {
	if (!platform_scattering_enabled || platform_impact_foam_strength <= 0.0001) {
		return 0.0;
	}
	float wave_impact = platform_incident_component_impact(
		base_world_xz, time_value, macro_wave_a, outward, hull_distance
	);
	float interaction_weather = smoothstep(0.20, 0.82, weather_intensity);
	float local_energy = mix(0.38, 1.0, clamp(local_contact_energy, 0.0, 1.0));
	float torn_surface = mix(0.24, 1.0, clamp(contact_breakup, 0.0, 1.0));
	return clamp(
		wave_impact * interaction_weather * local_energy * torn_surface
			* platform_impact_foam_strength,
		0.0,
		0.78
	);
}


float platform_reflected_crest_foam(
	vec2 base_world_xz,
	float reflected_slope_delta,
	float crest_signal,
	float active_breakup,
	float foam_weather_gate
) {
	if (!platform_scattering_enabled || platform_reflected_foam_strength <= 0.0001) {
		return 0.0;
	}
	vec2 direction_value = rotation_2d(macro_wave_a.w) * safe_direction(wind_direction);
	vec2 sideways = vec2(-direction_value.y, direction_value.x);
	vec2 platform_local = base_world_xz - platform_position_xz;
	vec2 projected_extents = platform_projected_extents(direction_value);
	float along_wave = dot(platform_local, direction_value);
	float across_wave = dot(platform_local, sideways);
	float upstream_distance = -along_wave - projected_extents.x;
	float upstream_positive = max(upstream_distance, 0.0);
	float upstream_gate = smoothstep(-0.25, 0.55, upstream_distance)
		* exp(-upstream_positive / max(macro_wave_a.y * 0.42, 0.1));
	float lateral_width = projected_extents.y + upstream_positive * 0.05;
	float lateral_softness = max(macro_wave_a.y * 0.18, 1.0);
	float lateral_gate = 1.0 - smoothstep(
		lateral_width,
		lateral_width + lateral_softness,
		abs(across_wave)
	);
	float reflected_activity = smoothstep(0.006, 0.048, reflected_slope_delta);
	float reflected_crest = smoothstep(0.46, 0.76, crest_signal + reflected_activity * 0.16);
	return clamp(
		upstream_gate * lateral_gate * reflected_activity * reflected_crest
			* active_breakup * foam_weather_gate * crest_foam_strength
			* platform_reflected_foam_strength,
		0.0,
		0.38
	);
}


float residual_breaker_source(vec2 source_xz, float source_time) {
	vec4 source_field = sample_macro_wave_field(source_xz, source_time);
	float source_crest = clamp(source_field.x / macro_total_amplitude() * 0.5 + 0.5, 0.0, 1.0);
	float compression_threshold = mix(0.178, 0.102, weather_intensity);
	float compression_gate = smoothstep(compression_threshold, compression_threshold + 0.070, source_field.w);
	float upper_face = smoothstep(crest_foam_threshold - 0.19, crest_foam_threshold + 0.01, source_crest);
	float incoming_face = smoothstep(0.006, 0.082, -dot(source_field.yz, safe_direction(wind_direction)));
	return compression_gate * upper_face * mix(0.38, 1.0, incoming_face);
}


float residual_foam_tap(vec2 world_xz, float time_value, float age, vec2 seed, float decay) {
	vec2 primary = safe_direction(wind_direction);
	vec2 cross_wind = vec2(-primary.y, primary.x);
	vec2 source_xz = world_xz - primary * residual_foam_transport * age;
	source_xz += cross_wind * sin(age * 3.71 + dot(seed, vec2(0.13, 0.19))) * 0.08;
	float source = residual_breaker_source(source_xz, time_value - age);
	vec2 patch_point = vec2(
		dot(source_xz, cross_wind) * 0.52,
		dot(source_xz, primary) * 0.20
	) + seed;
	float patch = smoothstep(0.36, 0.62, value_noise(patch_point));
	float torn_edge = smoothstep(0.36, 0.69, value_noise(rotation_2d(0.73) * patch_point * 2.83 + seed.yx));
	return source * patch * mix(0.22, 1.0, torn_edge) * decay;
}


void vertex() {
	vec3 base_position = VERTEX;
	vec3 displaced = base_position;
	vec3 derivative_x = vec3(1.0, 0.0, 0.0);
	vec3 derivative_z = vec3(0.0, 0.0, 1.0);
	vec2 base_world_xz = (MODEL_MATRIX * vec4(base_position, 1.0)).xz;
	vec2 primary = safe_direction(wind_direction);
	float final_amplitude = max(wave_amplitude_scale, 0.0);
	float final_speed = max(wave_speed_scale, 0.0);
	float safe_steepness = clamp(wave_steepness, 0.0, 0.90);
	float time_value = presentation_time();

	accumulate_gerstner(displaced, derivative_x, derivative_z, base_position.xz, rotation_2d(macro_wave_a.w) * primary, macro_wave_a.x * final_amplitude, macro_wave_a.y, macro_wave_a.z * final_speed, safe_steepness * macro_wave_steepness_weights.x, time_value);
	accumulate_gerstner(displaced, derivative_x, derivative_z, base_position.xz, rotation_2d(macro_wave_b.w) * primary, macro_wave_b.x * final_amplitude, macro_wave_b.y, macro_wave_b.z * final_speed, safe_steepness * macro_wave_steepness_weights.y, time_value);
	if (quality_level >= 1) {
		accumulate_gerstner(displaced, derivative_x, derivative_z, base_position.xz, rotation_2d(macro_wave_c.w) * primary, macro_wave_c.x * final_amplitude, macro_wave_c.y, macro_wave_c.z * final_speed, safe_steepness * macro_wave_steepness_weights.z, time_value);
	}
	// The platform affects presentation only. CPU buoyancy/contact continue to
	// sample the canonical incident field, avoiding self-feedback from reflection.
	vec4 platform_scattering = sample_platform_scattering(base_world_xz, time_value);
	displaced.y += platform_scattering.x;
	derivative_x.y += platform_scattering.y;
	derivative_z.y += platform_scattering.z;
	vec3 wave_normal = normalize(cross(derivative_z, derivative_x));
	VERTEX = displaced;
	NORMAL = wave_normal;
	TANGENT = normalize(derivative_x);
	BINORMAL = normalize(derivative_z);
	ocean_world_position = (MODEL_MATRIX * vec4(displaced, 1.0)).xyz;
	ocean_base_xz = base_world_xz;
	ocean_macro_normal_world = normalize((MODEL_MATRIX * vec4(wave_normal, 0.0)).xyz);
	ocean_platform_scattering = platform_scattering;
}


void fragment() {
	float time_value = presentation_time();
	vec4 macro_field = sample_macro_wave_field(ocean_base_xz, time_value);
	// Height and slope used by shading match the vertex deformation; compression
	// remains the canonical incident-field Jacobian in macro_field.w.
	macro_field.xyz += ocean_platform_scattering.xyz;
	float lee_mask = clamp(ocean_platform_scattering.w, 0.0, 1.0);
	float fragment_crest_signal = clamp(macro_field.x / macro_total_amplitude() * 0.5 + 0.5, 0.0, 1.0);
	float fragment_slope_signal = clamp(length(macro_field.yz) * 2.25, 0.0, 1.0);
	vec2 detail_slope = procedural_micro_slope(ocean_base_xz, time_value);
	// The lee reduces wind chop but never erases the surface; rain impacts remain
	// local events and are added after this non-zero transmission factor.
	detail_slope *= mix(1.0, platform_scattering_lee_retention.x, lee_mask);
	vec3 rain_impact_detail = vec3(0.0);
	if (quality_level >= 1 && rain_intensity > 0.12) {
		rain_impact_detail = rain_impact_layer(ocean_world_position.xz, time_value, 1.55, 1.05, 0.19, vec2(7.3, 19.1));
		if (quality_level >= 2) {
			rain_impact_detail += rain_impact_layer(ocean_world_position.xz, time_value, 1.05, 1.45, -0.73, vec2(23.7, 4.9)) * 0.72;
		}
	}
	float rain_impact_response = smoothstep(0.12, 0.52, rain_intensity);
	detail_slope += rain_impact_detail.xy * rain_impact_response * 0.052;
	// Preserve the exact Gerstner/Jacobian normal already used by the displaced
	// geometry. Fragment detail only perturbs it instead of replacing it with a
	// different height-field normal whose highlights can slide off the crest.
	vec3 surface_normal_world = normalize(ocean_macro_normal_world + vec3(-detail_slope.x, 0.0, -detail_slope.y));
	vec3 surface_normal = normalize(mat3(VIEW_MATRIX) * surface_normal_world);
	NORMAL = surface_normal;

	vec2 primary = safe_direction(wind_direction);
	vec2 cross_wind = vec2(-primary.y, primary.x);
	float detail_time = time_value * max(wave_speed_scale, 0.0) * (reduced_motion ? reduced_micro_motion : 1.0);
	vec2 directional_point = vec2(
		dot(ocean_base_xz, cross_wind) * 0.78,
		dot(ocean_base_xz, primary) * 0.30 - detail_time * foam_drift_speed
	);
	float structure_noise = quality_noise(directional_point);

	float height_light = smoothstep(0.20, 0.92, fragment_crest_signal);
	float slope_light = smoothstep(0.08, 0.86, fragment_slope_signal);
	float body_mix = clamp(0.40 + height_light * 0.34 + slope_light * 0.12 + (structure_noise - 0.5) * 0.13, 0.0, 1.0);
	vec3 water_color = mix(deep_water_color, body_water_color, body_mix);
	water_color = mix(water_color, crest_water_color, height_light * slope_light * 0.31);
	water_color = mix(water_color, storm_tint, weather_intensity * 0.12);
	// Godot's GGX dielectric already receives the sky radiance and implements
	// Fresnel. Painting a second horizon reflection into ALBEDO made the body of
	// the sea pastel/cyan and detached it from the actual lighting.

	// Narrow cross-wind caps make the rough profiles read as directional water
	// rather than broad specular clouds. Macro height/slope and noise break them,
	// so they cannot become a repeating full-surface stripe texture.
	float ridge_phase = dot(ocean_base_xz, primary) * 1.82;
	ridge_phase += sin(dot(ocean_base_xz, cross_wind) * 0.47 + detail_time * 0.17) * 0.82;
	ridge_phase -= detail_time * 4.22;
	float directional_ridge = filtered_sine_ridge(ridge_phase, 12.0);
	float ridge_breakup = smoothstep(0.34, 0.67, structure_noise + fragment_slope_signal * 0.18);
	vec2 secondary_direction = rotation_2d(0.72) * primary;
	float fine_ridge_phase = dot(ocean_base_xz, secondary_direction) * 3.68;
	fine_ridge_phase += sin(dot(ocean_base_xz, primary) * 0.83 - detail_time * 0.22) * 0.56;
	fine_ridge_phase -= detail_time * 6.01;
	float fine_ridge = quality_level >= 1 ? filtered_sine_ridge(fine_ridge_phase, 15.0) : 0.0;
	float fine_breakup = quality_noise(directional_point * 2.13 + vec2(9.3, 4.7));
	float surface_glint = directional_ridge * ridge_breakup;
	surface_glint = max(surface_glint, fine_ridge * smoothstep(0.36, 0.70, fine_breakup) * 0.72);
	float micro_ridge = 0.0;
	if (quality_level >= 2) {
		vec2 tertiary_direction = rotation_2d(-0.94) * primary;
		float micro_phase = dot(ocean_base_xz, tertiary_direction) * 6.25;
		micro_phase += sin(dot(ocean_base_xz, cross_wind) * 1.16 + detail_time * 0.31) * 0.39;
		micro_phase -= detail_time * 7.83;
		micro_ridge = filtered_sine_ridge(micro_phase, 17.0);
		surface_glint = max(surface_glint, micro_ridge * smoothstep(0.43, 0.73, fine_breakup) * 0.42);
	}
	surface_glint *= smoothstep(0.04, 0.48, fragment_slope_signal + fragment_crest_signal * 0.26);
	surface_glint *= 0.62;
	surface_glint *= mix(1.0, platform_scattering_lee_retention.y, lee_mask);
	surface_glint = max(surface_glint, rain_impact_detail.z * rain_impact_response * 0.34);
	// Glints are changes in reflected light, not bright pigment painted into the
	// water. They modulate PBR roughness below; only actual foam changes albedo.

	// Stage A: fresh white water is born only where the Gerstner mapping is
	// compressed on an upper, incoming face. A true-zero cellular mask tears the
	// front into short irregular breakers; no sine ridge is painted into albedo.
	float compression_threshold = mix(0.178, 0.102, weather_intensity);
	float compression_width = max(fwidth(macro_field.w) * 1.15, 0.006);
	float compression_gate = smoothstep(
		compression_threshold - compression_width,
		compression_threshold + 0.070 + compression_width,
		macro_field.w
	);
	float breaking_face = smoothstep(0.006, 0.090, -dot(macro_field.yz, primary));
	float crest_gate = smoothstep(crest_foam_threshold - 0.17, crest_foam_threshold + 0.015, fragment_crest_signal);
	float foam_weather_gate = smoothstep(0.29, 0.88, weather_intensity);
	// Reuse the already sampled, uncorrelated structure fields as a low-frequency
	// domain warp. This prevents every compressed front from being cut into the
	// same row of brush-like cells while keeping the mask deterministic.
	vec2 active_point = directional_point
		+ vec2(structure_noise - 0.5, fine_breakup - 0.5) * 0.31;
	float cap_cells = smoothstep(
		0.39,
		0.64,
		value_noise(active_point * vec2(5.55, 5.95) + vec2(21.7, 8.4))
	);
	float torn_cells = smoothstep(
		0.40,
		0.70,
		value_noise(rotation_2d(-0.81) * active_point * vec2(8.60, 9.35) + vec2(3.6, 19.2))
	);
	float active_breakup = cap_cells * mix(0.16, 1.0, torn_cells);
	active_breakup *= smoothstep(0.34, 0.68, structure_noise + fragment_slope_signal * foam_breakup * 0.52);
	float crest_foam = compression_gate * crest_gate * mix(0.34, 1.0, breaking_face);
	crest_foam *= active_breakup * foam_weather_gate * crest_foam_strength * 0.98;
	float reflected_crest_foam = platform_reflected_crest_foam(
		ocean_base_xz,
		length(ocean_platform_scattering.yz),
		fragment_crest_signal,
		active_breakup,
		foam_weather_gate
	);
	crest_foam = 1.0 - (1.0 - clamp(crest_foam, 0.0, 1.0))
		* (1.0 - reflected_crest_foam);
	// Fresh Stage A breaking reacts most strongly to the directional lee, but a
	// floating platform never creates a zero-foam or perfectly flat rectangle.
	crest_foam *= mix(1.0, platform_scattering_lee_retention.z, lee_mask);

	// Stage B: deterministic, advected samples of recently broken fronts leave
	// lower-contrast foam patches behind. Low uses one age tap, medium two and
	// high three, preserving the same weather semantics at different costs.
	float residual_foam = residual_foam_tap(ocean_base_xz, time_value, 0.68, vec2(11.4, 4.7), 0.54);
	if (quality_level >= 1) {
		float middle_age_foam = residual_foam_tap(ocean_base_xz, time_value, 1.65, vec2(3.2, 17.9), 0.32);
		residual_foam = 1.0 - (1.0 - residual_foam) * (1.0 - middle_age_foam);
	}
	if (quality_level >= 2) {
		float old_foam = residual_foam_tap(ocean_base_xz, time_value, 3.10, vec2(18.1, 2.6), 0.16);
		residual_foam = 1.0 - (1.0 - residual_foam) * (1.0 - old_foam);
	}
	residual_foam *= foam_weather_gate * crest_foam_strength * residual_foam_strength;
	// Older Stage B foam has already been advected, so it survives the shadow
	// more readily than new whitecaps while still reading as calmer water.
	residual_foam *= mix(1.0, platform_scattering_lee_retention.w, lee_mask);

	vec2 platform_local = ocean_world_position.xz - platform_position_xz;
	float contact_foam = 0.0;
	float contact_residual = 0.0;
	float interaction_foam = 0.0;
	// This broad gate must cover the full directional impact band around every
	// protruding pontoon. It only widens the cheap rejection envelope; the exact
	// union-SDF, incidence and breakup below still decide which pixels receive foam.
	float interaction_reach = max(contact_foam_width * 2.85, 1.25);
	float broad_hull_distance = rounded_box_sdf(platform_local, platform_half_extents + vec2(1.10), platform_corner_radius + 0.55);
	if (broad_hull_distance > -1.55 && broad_hull_distance < interaction_reach + 0.12) {
		vec2 pontoon_data = nearest_pontoon_data(platform_local);
		float hull_distance = min(platform_main_hull_sdf(platform_local), pontoon_data.x);
		vec2 outward = platform_waterline_gradient(platform_local);
		float local_contact_energy = contact_energy_at(outward, pontoon_data);
		float outside_gate = smoothstep(-0.08, 0.12, hull_distance);
		float contact_band = pow(1.0 - smoothstep(0.0, contact_foam_width, abs(hull_distance)), 1.45);
		float wind_face = 0.06 + 0.94 * max(dot(outward, -primary), 0.0);
		float contact_noise = quality_noise(platform_local * vec2(0.74, 0.52) + primary * detail_time * 0.10);
		float contact_cells = smoothstep(0.43, 0.67, contact_noise + fragment_slope_signal * 0.15);
		float contact_tears = smoothstep(0.34, 0.68, value_noise(rotation_2d(0.64) * platform_local * 1.73 - primary * detail_time * 0.08));
		float contact_breakup = contact_cells * mix(0.26, 1.0, contact_tears);
		contact_foam = contact_band * outside_gate * contact_breakup * wind_face;
		contact_foam *= contact_foam_strength * mix(0.18, 1.0, local_contact_energy);
		interaction_foam = platform_incident_impact_foam(
			ocean_base_xz,
			time_value,
			outward,
			hull_distance,
			local_contact_energy,
			contact_breakup
		);
		float residual_band = pow(1.0 - smoothstep(0.0, contact_foam_width * 1.72, abs(hull_distance)), 1.12);
		contact_residual = residual_band * outside_gate * contact_tears * wind_face;
		contact_residual *= contact_foam_strength * mix(0.04, 0.40, local_contact_energy);
	}

	residual_foam = 1.0 - (1.0 - residual_foam) * (1.0 - contact_residual);
	float residual_layer = clamp(residual_foam, 0.0, 0.62);
	float fresh_layer = clamp(max(crest_foam, max(contact_foam * 0.86, interaction_foam)), 0.0, 0.88);
	vec3 residual_color = mix(body_water_color, foam_color, 0.58);
	water_color = mix(water_color, residual_color, residual_layer * 0.86);
	water_color = mix(water_color, foam_color, fresh_layer);
	float total_foam = clamp(max(fresh_layer, residual_layer * 0.72), 0.0, 0.90);
	ALBEDO = water_color;
	float base_roughness = clamp(
		water_roughness + weather_intensity * 0.055 + (structure_noise - 0.5) * 0.045
		+ (quality_level == 0 ? 0.045 : 0.0) - surface_glint * mix(0.035, 0.075, weather_intensity),
		0.16,
		0.54
	);
	ROUGHNESS = mix(
		base_roughness,
		foam_roughness,
		total_foam
	);
	SPECULAR = water_specular;
	METALLIC = 0.0;
}
