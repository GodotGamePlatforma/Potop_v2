shader_type canvas_item;

uniform sampler2D rock_detail_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform bool has_detail_texture = false;
uniform vec4 profile_boundaries = vec4(0.25, 0.5, 0.75, 1.0);
uniform vec4 rock_base_0 : source_color = vec4(0.32, 0.4, 0.43, 0.35);
uniform vec4 rock_base_1 : source_color = vec4(0.32, 0.4, 0.43, 0.35);
uniform vec4 rock_base_2 : source_color = vec4(0.32, 0.4, 0.43, 0.35);
uniform vec4 rock_base_3 : source_color = vec4(0.32, 0.4, 0.43, 0.35);
uniform vec4 rock_shadow_0 : source_color = vec4(0.075, 0.11, 0.13, 1.0);
uniform vec4 rock_shadow_1 : source_color = vec4(0.075, 0.11, 0.13, 1.0);
uniform vec4 rock_shadow_2 : source_color = vec4(0.075, 0.11, 0.13, 1.0);
uniform vec4 rock_shadow_3 : source_color = vec4(0.075, 0.11, 0.13, 1.0);
uniform vec4 rock_edge_0 : source_color = vec4(0.34, 0.72, 0.75, 1.0);
uniform vec4 rock_edge_1 : source_color = vec4(0.34, 0.72, 0.75, 1.0);
uniform vec4 rock_edge_2 : source_color = vec4(0.34, 0.72, 0.75, 1.0);
uniform vec4 rock_edge_3 : source_color = vec4(0.34, 0.72, 0.75, 1.0);
uniform vec4 rock_params_0 = vec4(192.0, 0.68, 1.35, 0.65);
uniform vec4 rock_params_1 = vec4(192.0, 0.68, 1.35, 0.65);
uniform vec4 rock_params_2 = vec4(192.0, 0.68, 1.35, 0.65);
uniform vec4 rock_params_3 = vec4(192.0, 0.68, 1.35, 0.65);
uniform float world_height = 6480.0;
uniform vec2 world_origin = vec2(0.0);
uniform float quality_level : hint_range(0.0, 2.0) = 2.0;
uniform float anim_time = 0.0;
uniform bool reduced_motion = false;

varying vec2 world_position;


float hash21(vec2 point) {
	point = fract(point * vec2(127.1, 311.7));
	point += dot(point, point + 34.5);
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


// A single value-noise domain exposes its square lattice when it is sampled at
// the broad rock scales used by the full-world terrain sprite.  Keep the
// deterministic noise, but decorrelate its axes before composing material
// variation. Broad tonal fields receive two differently rotated domains and a
// restrained third octave on high quality; fine relief keeps its cheaper path.
float oblique_noise_a(vec2 point) {
	const mat2 rotation = mat2(vec2(0.8192, -0.5736), vec2(0.5736, 0.8192));
	return value_noise(rotation * point + vec2(11.73, -7.19));
}


float oblique_noise_b(vec2 point) {
	const mat2 rotation = mat2(vec2(0.6157, 0.7880), vec2(-0.7880, 0.6157));
	return value_noise(rotation * point + vec2(-5.41, 13.37));
}


float terrain_fbm(vec2 point) {
	float first = oblique_noise_a(point);
	float second = oblique_noise_b(point * 1.93 + vec2(2.17, -3.61));
	float result = first * 0.35 + second * 0.65;
	if (quality_level > 1.5) {
		float third = oblique_noise_a(point * 3.87 + vec2(-8.23, 4.79));
		result = result * 0.76 + third * 0.24;
	}
	return result;
}


float authored_detail_luminance(vec3 linear_color) {
	// source_color textures are sampled in linear space. Convert back to a
	// perceptual range before treating the authored albedo as a height field;
	// otherwise dark wet rock collapses into an almost uniform value.
	vec3 perceptual_color = pow(max(linear_color, vec3(0.0)), vec3(1.0 / 2.2));
	return dot(perceptual_color, vec3(0.2126, 0.7152, 0.0722));
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


float rock_height(vec2 detail_uv) {
	if (!has_detail_texture) {
		return terrain_fbm(detail_uv * 1.35);
	}
	float primary = authored_detail_luminance(texture(rock_detail_texture, detail_uv).rgb);
	if (quality_level <= 1.5) {
		return primary;
	}
	vec2 rotated_uv = mat2(vec2(0.86, -0.51), vec2(0.51, 0.86)) * detail_uv;
	float secondary = authored_detail_luminance(texture(rock_detail_texture, rotated_uv * 1.83 + vec2(0.37, 0.19)).rgb);
	return mix(primary, secondary, 0.14);
}


float rock_relief_height(vec2 detail_uv) {
	if (has_detail_texture) {
		return authored_detail_luminance(texture(rock_detail_texture, detail_uv).rgb);
	}
	return terrain_fbm(detail_uv * 1.35);
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - world_origin;
}


void fragment() {
	float safe_world_height = max(world_height, 1.0);
	float depth_ratio = clamp(world_position.y / safe_world_height, 0.0, 1.0);
	vec4 base_profile = blended_profile_value(depth_ratio, rock_base_0, rock_base_1, rock_base_2, rock_base_3);
	vec3 base_tint = base_profile.rgb;
	vec3 shadow_tint = blended_profile_value(depth_ratio, rock_shadow_0, rock_shadow_1, rock_shadow_2, rock_shadow_3).rgb;
	vec3 edge_tint = blended_profile_value(depth_ratio, rock_edge_0, rock_edge_1, rock_edge_2, rock_edge_3).rgb;
	vec4 rock_params = blended_profile_value(depth_ratio, rock_params_0, rock_params_1, rock_params_2, rock_params_3);
	float detail_world_scale = rock_params.x;
	float detail_strength = rock_params.y;
	float edge_width_texels = rock_params.z;
	float edge_highlight_strength = rock_params.w;
	float caustics_strength = base_profile.a;

	// TEXTURE is a deterministic signed-distance presentation derivative of the
	// canonical collision mask.  A 0.5 contour is the exact semantic boundary;
	// screen-space derivatives only anti-alias that boundary for presentation.
	float sdf_value = texture(TEXTURE, UV).r;
	vec2 sample_step = TEXTURE_PIXEL_SIZE * edge_width_texels;
	float sdf_left = texture(TEXTURE, UV - vec2(sample_step.x, 0.0)).r;
	float sdf_right = texture(TEXTURE, UV + vec2(sample_step.x, 0.0)).r;
	float sdf_up = texture(TEXTURE, UV - vec2(0.0, sample_step.y)).r;
	float sdf_down = texture(TEXTURE, UV + vec2(0.0, sample_step.y)).r;
	vec2 mask_gradient = vec2(sdf_right - sdf_left, sdf_down - sdf_up);
	float contour_aa = max(fwidth(sdf_value) * 0.75, 1.0 / 255.0);
	float rock_alpha = smoothstep(0.5 - contour_aa, 0.5 + contour_aa, sdf_value);
	float edge_band = max(length(mask_gradient) * 0.58, contour_aa * 2.0);
	float edge = 1.0 - smoothstep(contour_aa, edge_band, abs(sdf_value - 0.5));
	edge *= rock_alpha;

	float safe_detail_scale = max(detail_world_scale, 1.0);
	vec2 detail_uv = world_position / safe_detail_scale;
	float detail_height = rock_height(detail_uv);
	vec3 authored_albedo = vec3(0.5);
	float primary_surface = 0.5;
	if (has_detail_texture) {
		authored_albedo = texture(rock_detail_texture, detail_uv).rgb;
		primary_surface = authored_detail_luminance(authored_albedo);
	}
	float relief_step = mix(0.018, 0.010, step(1.5, quality_level));
	float relief_x = 0.0;
	float relief_y = 0.0;
	if (quality_level > 0.5) {
		float relief_height = rock_relief_height(detail_uv);
		relief_x = rock_relief_height(detail_uv + vec2(relief_step, 0.0)) - relief_height;
		relief_y = rock_relief_height(detail_uv + vec2(0.0, relief_step)) - relief_height;
	}
	vec3 relief_normal = normalize(vec3(-relief_x * 4.2, -relief_y * 4.2, 1.0));
	// Feed the authored relief into Godot's 2D light pass. The same material
	// remains fully readable without the lantern, while local lights now reveal
	// wet ridges instead of brightening every rock pixel uniformly.
	NORMAL_MAP = relief_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(0.32, 0.82, step(1.5, quality_level));
	float diffuse_relief = clamp(dot(relief_normal, normalize(vec3(-0.38, -0.72, 0.78))) * 0.5 + 0.5, 0.0, 1.0);
	float macro_relief = terrain_fbm(world_position / 610.0 + vec2(0.17, -0.31));
	float mineral_breakup = terrain_fbm(world_position / 188.0 + vec2(2.7, 1.3));
	float sediment = smoothstep(0.48, 0.78, terrain_fbm(world_position / 360.0 + vec2(-1.4, 3.1)));
	float shaped_detail = mix(0.5, detail_height, detail_strength);
	float material_value = clamp(shaped_detail * 0.58 + diffuse_relief * 0.30 + macro_relief * 0.12, 0.0, 1.0);
	vec3 rock_color = mix(shadow_tint, base_tint, smoothstep(0.08, 0.92, material_value));
	if (has_detail_texture) {
		// Preserve the authored material's wet cracks and boulder boundaries as
		// albedo variation instead of reducing the texture to procedural noise.
		float authored_linear_luma = max(dot(authored_albedo, vec3(0.2126, 0.7152, 0.0722)), 0.018);
		vec3 authored_chroma = clamp(authored_albedo / authored_linear_luma, vec3(0.76), vec3(1.24));
		float authored_value = mix(0.56, 1.22, smoothstep(0.20, 0.68, primary_surface));
		rock_color *= authored_chroma * authored_value;
	}
	rock_color *= mix(0.91, 1.055, macro_relief * 0.62 + mineral_breakup * 0.38);
	rock_color = mix(rock_color, base_tint * vec3(0.90, 0.92, 0.88), sediment * 0.11);
	float wet_sheen = pow(clamp(diffuse_relief, 0.0, 1.0), 7.0)
		* smoothstep(0.54, 0.88, detail_height)
		* step(0.5, quality_level);
	rock_color += edge_tint * wet_sheen * mix(0.035, 0.085, step(1.5, quality_level));

	float motion_time = reduced_motion ? 0.0 : anim_time;
	vec2 caustics_uv = world_position / 118.0;
	float caustic_wave = sin(caustics_uv.x * 4.4 + sin(caustics_uv.y * 3.2 + motion_time * 0.32));
	caustic_wave += sin(caustics_uv.y * 4.0 - motion_time * 0.24);
	float caustic = pow(clamp(1.0 - abs(caustic_wave) * 0.72, 0.0, 1.0), 8.0);
	caustic *= smoothstep(0.42, 0.74, value_noise(world_position / 82.0 + motion_time * 0.008));
	caustic *= step(0.5, quality_level) * pow(1.0 - depth_ratio, 1.5);
	rock_color += base_tint * caustic * caustics_strength * 0.075;

	vec2 edge_normal = normalize(mask_gradient + vec2(0.00001));
	float edge_facing = clamp(dot(edge_normal, normalize(vec2(-0.38, -0.92))) * 0.5 + 0.5, 0.0, 1.0);
	float edge_breakup = smoothstep(0.24, 0.82, value_noise(world_position / 76.0 + vec2(3.2, -1.6)));
	rock_color = mix(rock_color, shadow_tint * 0.86, edge * mix(0.13, 0.05, edge_facing));
	float edge_glint = edge * edge_highlight_strength * mix(0.10, 0.54, edge_facing) * mix(0.22, 1.0, edge_breakup);
	rock_color = mix(rock_color, edge_tint, clamp(edge_glint * 0.32, 0.0, 0.22));
	COLOR = vec4(max(rock_color, vec3(0.0)), rock_alpha);
}
