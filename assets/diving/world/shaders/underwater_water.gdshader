shader_type canvas_item;

uniform vec4 profile_boundaries = vec4(0.25, 0.5, 0.75, 1.0);
uniform vec4 water_near_0 : source_color = vec4(0.035, 0.25, 0.34, 1.0);
uniform vec4 water_near_1 : source_color = vec4(0.035, 0.20, 0.26, 1.0);
uniform vec4 water_near_2 : source_color = vec4(0.07, 0.16, 0.19, 1.0);
uniform vec4 water_near_3 : source_color = vec4(0.03, 0.09, 0.12, 1.0);
uniform vec4 water_far_0 : source_color = vec4(0.008, 0.075, 0.12, 1.0);
uniform vec4 water_far_1 : source_color = vec4(0.008, 0.075, 0.12, 1.0);
uniform vec4 water_far_2 : source_color = vec4(0.008, 0.075, 0.12, 1.0);
uniform vec4 water_far_3 : source_color = vec4(0.008, 0.075, 0.12, 1.0);
uniform vec4 caustics_color_0 : source_color = vec4(0.32, 0.78, 0.82, 1.0);
uniform vec4 caustics_color_1 : source_color = vec4(0.32, 0.78, 0.82, 1.0);
uniform vec4 caustics_color_2 : source_color = vec4(0.32, 0.78, 0.82, 1.0);
uniform vec4 caustics_color_3 : source_color = vec4(0.32, 0.78, 0.82, 1.0);
uniform vec4 water_params_0 = vec4(0.7, 0.35, 0.35, 0.25);
uniform vec4 water_params_1 = vec4(0.7, 0.35, 0.35, 0.25);
uniform vec4 water_params_2 = vec4(0.7, 0.35, 0.35, 0.25);
uniform vec4 water_params_3 = vec4(0.7, 0.35, 0.35, 0.25);
uniform float world_height = 6480.0;
uniform float quality_level : hint_range(0.0, 2.0) = 2.0;
uniform float anim_time = 0.0;
uniform bool reduced_motion = false;

varying vec2 world_position;


float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32);
	return fract(point.x * point.y);
}


float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}


float region_depth(float depth_ratio, float start_depth, float end_depth) {
	return clamp((depth_ratio - start_depth) / max(end_depth - start_depth, 0.0001), 0.0, 1.0);
}


float region_transition(float local_depth) {
	return smoothstep(0.82, 1.0, local_depth);
}


vec4 blended_profile_value(float depth_ratio, vec4 value_0, vec4 value_1, vec4 value_2, vec4 value_3) {
	if (depth_ratio < profile_boundaries.x) {
		return mix(value_0, value_1, region_transition(region_depth(depth_ratio, 0.0, profile_boundaries.x)));
	}
	if (depth_ratio < profile_boundaries.y) {
		return mix(value_1, value_2, region_transition(region_depth(depth_ratio, profile_boundaries.x, profile_boundaries.y)));
	}
	if (depth_ratio < profile_boundaries.z) {
		return mix(value_2, value_3, region_transition(region_depth(depth_ratio, profile_boundaries.y, profile_boundaries.z)));
	}
	return value_3;
}


vec3 blended_water_color(float depth_ratio) {
	if (depth_ratio < profile_boundaries.x) {
		float local_depth = region_depth(depth_ratio, 0.0, profile_boundaries.x);
		return mix(mix(water_near_0.rgb, water_far_0.rgb, local_depth), water_near_1.rgb, region_transition(local_depth));
	}
	if (depth_ratio < profile_boundaries.y) {
		float local_depth = region_depth(depth_ratio, profile_boundaries.x, profile_boundaries.y);
		return mix(mix(water_near_1.rgb, water_far_1.rgb, local_depth), water_near_2.rgb, region_transition(local_depth));
	}
	if (depth_ratio < profile_boundaries.z) {
		float local_depth = region_depth(depth_ratio, profile_boundaries.y, profile_boundaries.z);
		return mix(mix(water_near_2.rgb, water_far_2.rgb, local_depth), water_near_3.rgb, region_transition(local_depth));
	}
	float local_depth = region_depth(depth_ratio, profile_boundaries.z, profile_boundaries.w);
	return mix(water_near_3.rgb, water_far_3.rgb, local_depth);
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


void fragment() {
	float safe_world_height = max(world_height, 1.0);
	float depth_ratio = clamp(world_position.y / safe_world_height, 0.0, 1.0);
	vec3 water_color = blended_water_color(depth_ratio);
	vec3 far_water = blended_profile_value(depth_ratio, water_far_0, water_far_1, water_far_2, water_far_3).rgb;
	vec3 caustics_color = blended_profile_value(depth_ratio, caustics_color_0, caustics_color_1, caustics_color_2, caustics_color_3).rgb;
	vec4 water_params = blended_profile_value(depth_ratio, water_params_0, water_params_1, water_params_2, water_params_3);
	float water_clarity = water_params.x;
	float caustics_strength = water_params.y;
	float suspended_particle_density = water_params.z;
	float current_distortion_strength = water_params.w;

	float motion_time = reduced_motion ? 0.0 : anim_time;
	vec2 current_offset = vec2(motion_time * 0.009, -motion_time * 0.005) * current_distortion_strength;
	vec2 broad_uv = world_position / 1120.0 + current_offset;
	float broad_noise = value_noise(broad_uv);
	float medium_noise = value_noise(world_position / 390.0 - current_offset * 1.7);
	float fine_noise = value_noise(world_position / 126.0 + current_offset * 3.1);
	float quality_medium = step(0.5, quality_level);
	float quality_high = step(1.5, quality_level);
	float water_noise = broad_noise * 0.76 + medium_noise * 0.18 * quality_medium + fine_noise * 0.06 * quality_high;

	vec2 caustics_uv = world_position / 148.0;
	float caustic_a = sin(caustics_uv.x * 2.7 + sin(caustics_uv.y * 1.9 + motion_time * 0.18));
	float caustic_b = sin(caustics_uv.y * 2.3 - sin(caustics_uv.x * 1.7 - motion_time * 0.14));
	float caustic_lines = pow(clamp(1.0 - abs(caustic_a - caustic_b) * 2.9, 0.0, 1.0), 6.0);
	caustic_lines *= smoothstep(0.54, 0.82, value_noise(world_position / 118.0 + motion_time * 0.006));
	caustic_lines *= mix(0.32, 1.0, quality_medium) * pow(1.0 - depth_ratio, 1.55);

	float haze = mix(0.11, 0.024, water_clarity);
	float cloud_field = smoothstep(0.36, 0.78, broad_noise * 0.72 + medium_noise * 0.28);
	water_color *= mix(0.955, 1.025, water_noise);
	water_color = mix(water_color, far_water, haze * suspended_particle_density * mix(0.78, 1.16, cloud_field));
	water_color += caustics_color * caustic_lines * caustics_strength * mix(0.035, 0.095, water_clarity);
	COLOR = vec4(max(water_color, vec3(0.0)), 1.0);
}
