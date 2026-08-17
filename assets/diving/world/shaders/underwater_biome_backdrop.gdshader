shader_type canvas_item;
render_mode unshaded;

// This material is drawn by one world-anchored Polygon2D.  It deliberately
// contains presentation only: no map mask, collision, or gameplay state.
uniform vec2 world_size = vec2(11520.0, 6480.0);
uniform vec2 world_origin = vec2(0.0);
uniform float anim_time = 0.0;
uniform bool reduced_motion = false;
uniform int quality_level = 2;

uniform float r1_depth_end : hint_range(0.0, 1.0) = 0.237;
uniform float r2_depth_end : hint_range(0.0, 1.0) = 0.401;
uniform float r3_depth_end : hint_range(0.0, 1.0) = 0.607;

uniform vec4 r1_backdrop_tint : source_color = vec4(0.16, 0.37, 0.39, 1.0);
uniform vec4 r1_backdrop_accent : source_color = vec4(0.45, 0.74, 0.76, 1.0);
uniform float r1_backdrop_strength : hint_range(0.0, 1.0) = 0.72;
uniform float r1_backdrop_motion_scale : hint_range(0.0, 2.0) = 0.65;
uniform float r1_backdrop_motif_scale : hint_range(0.5, 2.0) = 1.0;

uniform vec4 r2_backdrop_tint : source_color = vec4(0.14, 0.32, 0.23, 1.0);
uniform vec4 r2_backdrop_accent : source_color = vec4(0.43, 0.67, 0.41, 1.0);
uniform float r2_backdrop_strength : hint_range(0.0, 1.0) = 0.72;
uniform float r2_backdrop_motion_scale : hint_range(0.0, 2.0) = 0.82;
uniform float r2_backdrop_motif_scale : hint_range(0.5, 2.0) = 1.0;

uniform vec4 r3_backdrop_tint : source_color = vec4(0.31, 0.24, 0.17, 1.0);
uniform vec4 r3_backdrop_accent : source_color = vec4(0.68, 0.45, 0.24, 1.0);
uniform float r3_backdrop_strength : hint_range(0.0, 1.0) = 0.74;
uniform float r3_backdrop_motion_scale : hint_range(0.0, 2.0) = 0.42;
uniform float r3_backdrop_motif_scale : hint_range(0.5, 2.0) = 1.0;

uniform vec4 r4_backdrop_tint : source_color = vec4(0.17, 0.27, 0.30, 1.0);
uniform vec4 r4_backdrop_accent : source_color = vec4(0.42, 0.61, 0.64, 1.0);
uniform float r4_backdrop_strength : hint_range(0.0, 1.0) = 0.78;
uniform float r4_backdrop_motion_scale : hint_range(0.0, 2.0) = 0.30;
uniform float r4_backdrop_motif_scale : hint_range(0.5, 2.0) = 1.0;

varying vec2 layer_position;
varying vec2 scene_world_position;


float hash21(vec2 point) {
	point = fract(point * vec2(127.1, 311.7));
	point += dot(point, point + 34.5);
	return fract(point.x * point.y);
}


float soft_box(vec2 point, vec2 center, vec2 half_size, float softness) {
	vec2 delta = abs(point - center) - half_size;
	float signed_distance = length(max(delta, vec2(0.0))) + min(max(delta.x, delta.y), 0.0);
	return 1.0 - smoothstep(0.0, max(softness, 0.0001), signed_distance);
}


float soft_ellipse(vec2 point, vec2 center, vec2 radius, float softness) {
	float distance_to_edge = length((point - center) / max(radius, vec2(0.0001))) - 1.0;
	return 1.0 - smoothstep(0.0, max(softness, 0.0001), distance_to_edge);
}


float soft_segment(vec2 point, vec2 start, vec2 end, float width) {
	vec2 direction = end - start;
	float projection = clamp(dot(point - start, direction) / max(dot(direction, direction), 0.0001), 0.0, 1.0);
	float distance_to_segment = length(point - (start + direction * projection));
	return 1.0 - smoothstep(width, width + 0.018, distance_to_segment);
}


vec2 distant_position(vec2 position, float time_value, float motion_scale, float wave_strength) {
	vec2 sample_position = position;
	float motion_time = time_value * motion_scale;
	float first_wave = sin(sample_position.y / 238.0 + motion_time * 0.44);
	float second_wave = sin(sample_position.y / 109.0 - motion_time * 0.29 + sample_position.x / 760.0);
	sample_position.x += (first_wave * 0.72 + second_wave * 0.28) * wave_strength;
	sample_position.y += sin(sample_position.x / 510.0 - motion_time * 0.22) * wave_strength * 0.24;
	return sample_position;
}


float region_depth(float depth_ratio, float start_depth, float end_depth) {
	return clamp((depth_ratio - start_depth) / max(end_depth - start_depth, 0.0001), 0.0, 1.0);
}


float region_transition(float local_depth) {
	return smoothstep(0.82, 1.0, local_depth);
}


vec4 blend_backdrops(vec4 first, vec4 second, float weight) {
	float alpha = mix(first.a, second.a, weight);
	vec3 premultiplied = mix(first.rgb * first.a, second.rgb * second.a, weight);
	return vec4(premultiplied / max(alpha, 0.0001), alpha);
}


vec4 r1_city_backdrop(vec2 position, float time_value) {
	position = distant_position(position, time_value, r1_backdrop_motion_scale, 8.0);
	float scale = 420.0 * clamp(r1_backdrop_motif_scale, 0.5, 2.0);
	vec2 grid = position / scale;
	vec2 cell = floor(grid);
	vec2 local = fract(grid);
	float seed = hash21(cell);
	float secondary_seed = hash21(cell + vec2(19.0, -7.0));
	float building_height = mix(0.23, 0.56, seed);
	float building_width = mix(0.12, 0.24, secondary_seed);
	float building_x = mix(0.23, 0.70, hash21(cell + vec2(3.0, 5.0)));
	float building = soft_box(
		local,
		vec2(building_x, 0.86 - building_height),
		vec2(building_width, building_height),
		0.018
	);
	float annex = soft_box(
		local,
		vec2(0.82 - building_width, 0.88 - building_height * 0.54),
		vec2(building_width * 0.58, building_height * 0.54),
		0.018
	);
	float window_lights = 0.0;
	if (quality_level >= 1) {
		vec2 window_grid = abs(fract(local * vec2(7.0, 9.0) + vec2(seed * 2.7, secondary_seed * 4.1)) - 0.5);
		window_lights = (1.0 - smoothstep(0.11, 0.20, max(window_grid.x, window_grid.y))) * (building + annex);
		window_lights *= 0.52 + 0.48 * sin(time_value * r1_backdrop_motion_scale * 0.55 + seed * 17.0);
	}
	float antenna = 0.0;
	if (quality_level >= 2) {
		antenna = soft_segment(
			local,
			vec2(building_x, 0.31 - building_height * 0.14),
			vec2(building_x + 0.04, 0.18 - building_height * 0.12),
			0.010
		);
	}
	float mass = clamp(building + annex * 0.78 + antenna * 0.42, 0.0, 1.0);
	float accent = clamp(window_lights * 0.92 + antenna * 0.25, 0.0, 1.0);
	vec3 color = mix(r1_backdrop_tint.rgb, r1_backdrop_accent.rgb, accent);
	float alpha = clamp(mass * 0.78 + window_lights * 0.28, 0.0, 1.0) * r1_backdrop_strength;
	return vec4(color, alpha);
}


vec4 r2_garden_backdrop(vec2 position, float time_value) {
	position = distant_position(position, time_value, r2_backdrop_motion_scale, 15.0);
	float scale = 360.0 * clamp(r2_backdrop_motif_scale, 0.5, 2.0);
	vec2 grid = position / scale;
	vec2 cell = floor(grid);
	vec2 local = fract(grid);
	float seed = hash21(cell);
	float sway = sin(time_value * r2_backdrop_motion_scale * 0.75 + cell.x * 1.73 + cell.y * 0.91) * 0.10;
	float plant_a = soft_segment(local, vec2(0.17, 0.91), vec2(0.17 + sway, 0.36), 0.017);
	float plant_b = soft_segment(local, vec2(0.39, 0.93), vec2(0.39 - sway * 0.72, 0.48), 0.014);
	float plant_c = soft_segment(local, vec2(0.66, 0.92), vec2(0.66 + sway * 1.18, 0.27), 0.020);
	float coral_mound_a = soft_ellipse(
		local,
		vec2(0.25 + seed * 0.08, 0.88),
		vec2(0.24, 0.13 + seed * 0.04),
		0.22
	);
	float coral_mound_b = soft_ellipse(
		local,
		vec2(0.67 - seed * 0.06, 0.91),
		vec2(0.29, 0.11 + seed * 0.05),
		0.24
	);
	float plant_d = 0.0;
	if (quality_level >= 1) {
		plant_d = soft_segment(local, vec2(0.84, 0.94), vec2(0.84 - sway * 0.85, 0.52), 0.012);
	}
	float fish = 0.0;
	if (quality_level >= 1) {
		float swim_x = fract(seed + time_value * r2_backdrop_motion_scale * 0.052);
		vec2 fish_center = vec2(swim_x, 0.23 + hash21(cell + vec2(-13.0, 23.0)) * 0.27);
		float body = soft_ellipse(local, fish_center, vec2(0.070, 0.026), 0.18);
		float tail = soft_segment(local, fish_center + vec2(-0.065, 0.0), fish_center + vec2(-0.112, 0.035), 0.010);
		tail += soft_segment(local, fish_center + vec2(-0.065, 0.0), fish_center + vec2(-0.112, -0.035), 0.010);
		fish = clamp(body + tail, 0.0, 1.0);
	}
	float garden = clamp(
		plant_a + plant_b + plant_c + plant_d + coral_mound_a * 0.72 + coral_mound_b * 0.62,
		0.0,
		1.0
	);
	vec3 color = mix(r2_backdrop_tint.rgb, r2_backdrop_accent.rgb, clamp(fish * 0.92 + garden * 0.18, 0.0, 1.0));
	float alpha = clamp(garden * 0.82 + fish * 0.72, 0.0, 1.0) * r2_backdrop_strength;
	return vec4(color, alpha);
}


vec4 r3_industry_backdrop(vec2 position, float time_value) {
	position = distant_position(position, time_value, r3_backdrop_motion_scale, 6.0);
	float scale = 480.0 * clamp(r3_backdrop_motif_scale, 0.5, 2.0);
	vec2 grid = position / scale;
	vec2 cell = floor(grid);
	vec2 local = fract(grid);
	float seed = hash21(cell);
	float drift = sin(time_value * r3_backdrop_motion_scale * 0.32 + seed * 11.0) * 0.012;
	float pipe_a = soft_segment(local, vec2(-0.10, 0.76 + drift), vec2(1.08, 0.28 + drift), 0.038);
	float pipe_b = soft_segment(local, vec2(-0.08, 0.86 - drift), vec2(0.92, 0.52 - drift), 0.027);
	float support = soft_box(local, vec2(0.74, 0.61), vec2(0.038, 0.29), 0.014);
	float beam = soft_segment(local, vec2(0.36, 0.80), vec2(0.92, 0.33), 0.016);
	float joints = 0.0;
	if (quality_level >= 1) {
		joints += soft_ellipse(local, vec2(0.23, 0.62 + drift), vec2(0.030), 0.26);
		joints += soft_ellipse(local, vec2(0.54, 0.46 + drift), vec2(0.030), 0.26);
		joints += soft_ellipse(local, vec2(0.84, 0.32 + drift), vec2(0.030), 0.26);
	}
	float truss = 0.0;
	if (quality_level >= 2) {
		truss = soft_segment(local, vec2(0.53, 0.77), vec2(0.91, 0.42), 0.010);
		truss += soft_segment(local, vec2(0.53, 0.42), vec2(0.91, 0.77), 0.010);
	}
	float mass = clamp(pipe_a + pipe_b * 0.82 + support * 0.82 + beam * 0.56 + truss * 0.36, 0.0, 1.0);
	vec3 color = mix(r3_backdrop_tint.rgb, r3_backdrop_accent.rgb, clamp(joints * 0.95 + beam * 0.22, 0.0, 1.0));
	float alpha = clamp(mass * 0.82 + joints * 0.42, 0.0, 1.0) * r3_backdrop_strength;
	return vec4(color, alpha);
}


vec4 r4_monument_backdrop(vec2 position, float time_value) {
	position = distant_position(position, time_value, r4_backdrop_motion_scale, 9.0);
	float scale = 560.0 * clamp(r4_backdrop_motif_scale, 0.5, 2.0);
	vec2 grid = position / scale;
	vec2 cell = floor(grid);
	vec2 local = fract(grid);
	float seed = hash21(cell);
	float pylon_height = mix(0.38, 0.78, seed);
	float pylon_x = mix(0.22, 0.72, hash21(cell + vec2(7.0, -4.0)));
	float pylon = soft_box(local, vec2(pylon_x, 0.88 - pylon_height), vec2(0.070, pylon_height), 0.018);
	float crown = soft_box(local, vec2(pylon_x, 0.10 + (1.0 - pylon_height) * 0.38), vec2(0.112, 0.038), 0.016);
	float companion = soft_box(local, vec2(pylon_x + 0.20, 0.74 - pylon_height * 0.48), vec2(0.036, pylon_height * 0.48), 0.016);
	float skyline_seed = hash21(cell + vec2(-17.0, 29.0));
	float city_dome = soft_ellipse(
		local,
		vec2(mix(0.22, 0.43, skyline_seed), 0.88),
		vec2(mix(0.19, 0.29, seed), mix(0.11, 0.18, skyline_seed)),
		0.24
	);
	float city_shoulders = soft_ellipse(
		local,
		vec2(mix(0.59, 0.77, seed), 0.91),
		vec2(mix(0.22, 0.32, skyline_seed), mix(0.09, 0.15, seed)),
		0.26
	);
	float leaning_spire = soft_segment(
		local,
		vec2(mix(0.62, 0.78, skyline_seed), 0.88),
		vec2(mix(0.56, 0.73, skyline_seed), mix(0.48, 0.60, seed)),
		0.026
	);
	float life = 0.0;
	if (quality_level >= 1) {
		float glide_x = fract(hash21(cell + vec2(31.0, 2.0)) + time_value * r4_backdrop_motion_scale * 0.020);
		vec2 life_center = vec2(glide_x, 0.32 + seed * 0.20);
		life = soft_ellipse(local, life_center, vec2(0.105, 0.030), 0.20);
		life += soft_segment(local, life_center + vec2(-0.082, 0.0), life_center + vec2(-0.145, 0.048), 0.012);
		life += soft_segment(local, life_center + vec2(-0.082, 0.0), life_center + vec2(-0.145, -0.048), 0.012);
		life = clamp(life, 0.0, 1.0);
	}
	float city_mass = clamp(city_dome * 0.68 + city_shoulders * 0.62 + leaning_spire * 0.46, 0.0, 1.0);
	float mass = clamp(pylon + crown * 0.76 + companion * 0.68 + city_mass, 0.0, 1.0);
	vec3 color = mix(
		r4_backdrop_tint.rgb,
		r4_backdrop_accent.rgb,
		clamp(life * 0.76 + crown * 0.18 + city_mass * 0.16, 0.0, 1.0)
	);
	float alpha = clamp(mass * 0.84 + life * 0.55, 0.0, 1.0) * r4_backdrop_strength;
	return vec4(color, alpha);
}


void vertex() {
	layer_position = VERTEX;
	scene_world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - world_origin;
}


void fragment() {
	float safe_world_height = max(world_size.y, 1.0);
	float depth_ratio = clamp(scene_world_position.y / safe_world_height, 0.0, 1.0);
	float time_value = reduced_motion ? 0.0 : anim_time;
	vec4 backdrop = vec4(0.0);
	if (depth_ratio < r1_depth_end) {
		float transition = region_transition(region_depth(depth_ratio, 0.0, r1_depth_end));
		backdrop = blend_backdrops(
			r1_city_backdrop(layer_position, time_value),
			r2_garden_backdrop(layer_position, time_value),
			transition
		);
	} else if (depth_ratio < r2_depth_end) {
		float transition = region_transition(region_depth(depth_ratio, r1_depth_end, r2_depth_end));
		backdrop = blend_backdrops(
			r2_garden_backdrop(layer_position, time_value),
			r3_industry_backdrop(layer_position, time_value),
			transition
		);
	} else if (depth_ratio < r3_depth_end) {
		float transition = region_transition(region_depth(depth_ratio, r2_depth_end, r3_depth_end));
		backdrop = blend_backdrops(
			r3_industry_backdrop(layer_position, time_value),
			r4_monument_backdrop(layer_position, time_value),
			transition
		);
	} else {
		backdrop = r4_monument_backdrop(layer_position, time_value);
	}
	COLOR = vec4(backdrop.rgb, clamp(backdrop.a, 0.0, 1.0));
}
