shader_type canvas_item;

uniform sampler2D terrain_sdf : repeat_disable, filter_linear;
uniform sampler2D authored_rock_albedo : source_color, repeat_enable, filter_linear_mipmap;
uniform vec2 world_size = vec2(11520.0, 6480.0);
uniform vec2 world_origin = vec2(0.0);
uniform float material_world_scale : hint_range(96.0, 640.0) = 286.0;
uniform vec4 base_tint : source_color = vec4(0.24, 0.26, 0.23, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.032, 0.045, 0.043, 1.0);
uniform vec4 edge_tint : source_color = vec4(0.24, 0.42, 0.38, 1.0);
uniform vec4 rust_tint : source_color = vec4(0.32, 0.14, 0.055, 1.0);
uniform float rust_strength : hint_range(0.0, 0.5) = 0.18;
uniform float wet_sheen_strength : hint_range(0.0, 0.5) = 0.16;

varying vec2 world_position;


float perceptual_luminance(vec3 linear_color) {
	vec3 perceptual = pow(max(linear_color, vec3(0.0)), vec3(1.0 / 2.2));
	return dot(perceptual, vec3(0.2126, 0.7152, 0.0722));
}


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


float authored_height(vec2 uv) {
	return perceptual_luminance(texture(authored_rock_albedo, uv).rgb);
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - world_origin;
}


void fragment() {
	vec2 world_uv = clamp(world_position / max(world_size, vec2(1.0)), vec2(0.0), vec2(1.0));
	float sdf_value = texture(terrain_sdf, world_uv).r;
	float contour_aa = max(fwidth(sdf_value) * 0.82, 1.0 / 255.0);
	float rock_alpha = smoothstep(0.5 - contour_aa, 0.5 + contour_aa, sdf_value);

	vec2 detail_uv = world_position / max(material_world_scale, 1.0);
	vec3 authored_albedo = texture(authored_rock_albedo, detail_uv).rgb;
	float height = perceptual_luminance(authored_albedo);
	const float RELIEF_STEP = 0.0022;
	float height_x = authored_height(detail_uv + vec2(RELIEF_STEP, 0.0)) - authored_height(detail_uv - vec2(RELIEF_STEP, 0.0));
	float height_y = authored_height(detail_uv + vec2(0.0, RELIEF_STEP)) - authored_height(detail_uv - vec2(0.0, RELIEF_STEP));
	vec3 surface_normal = normalize(vec3(-height_x * 11.0, -height_y * 11.0, 1.0));
	float key_light = clamp(dot(surface_normal, normalize(vec3(-0.42, -0.72, 0.72))) * 0.5 + 0.5, 0.0, 1.0);

	float macro = value_noise(world_position / 410.0 + vec2(4.7, -2.1));
	float material_value = clamp(height * 0.55 + key_light * 0.33 + macro * 0.12, 0.0, 1.0);
	vec3 rock_color = mix(shadow_tint.rgb, base_tint.rgb, smoothstep(0.23, 0.78, material_value));
	float authored_linear_luma = max(dot(authored_albedo, vec3(0.2126, 0.7152, 0.0722)), 0.018);
	vec3 authored_chroma = clamp(authored_albedo / authored_linear_luma, vec3(0.78), vec3(1.22));
	rock_color *= authored_chroma * mix(0.68, 1.18, smoothstep(0.20, 0.67, height));

	float crack_mask = (1.0 - smoothstep(0.29, 0.46, height)) * smoothstep(0.44, 0.78, macro);
	rock_color = mix(rock_color, rust_tint.rgb, crack_mask * rust_strength);
	float wet_sheen = pow(key_light, 8.0) * smoothstep(0.50, 0.74, height);
	rock_color += edge_tint.rgb * wet_sheen * wet_sheen_strength;

	vec2 sdf_step = vec2(1.0 / 1440.0, 1.0 / 810.0);
	vec2 sdf_gradient = vec2(
		texture(terrain_sdf, world_uv + vec2(sdf_step.x, 0.0)).r - texture(terrain_sdf, world_uv - vec2(sdf_step.x, 0.0)).r,
		texture(terrain_sdf, world_uv + vec2(0.0, sdf_step.y)).r - texture(terrain_sdf, world_uv - vec2(0.0, sdf_step.y)).r
	);
	float edge_band = max(length(sdf_gradient) * 0.62, contour_aa * 2.0);
	float edge = (1.0 - smoothstep(contour_aa, edge_band, abs(sdf_value - 0.5))) * rock_alpha;
	vec2 edge_normal = normalize(sdf_gradient + vec2(0.00001));
	float edge_facing = clamp(dot(edge_normal, normalize(vec2(-0.36, -0.94))) * 0.5 + 0.5, 0.0, 1.0);
	rock_color = mix(rock_color, shadow_tint.rgb * 0.78, edge * mix(0.16, 0.045, edge_facing));
	rock_color += edge_tint.rgb * edge * edge_facing * 0.075;

	NORMAL_MAP = surface_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.48;
	COLOR = vec4(max(rock_color, vec3(0.0)), rock_alpha);
}
