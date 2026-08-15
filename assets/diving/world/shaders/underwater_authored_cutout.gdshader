shader_type canvas_item;

uniform vec4 water_haze : source_color = vec4(0.015, 0.12, 0.15, 1.0);
uniform sampler2D terrain_sdf : repeat_disable, filter_linear;
uniform vec2 world_size = vec2(11520.0, 6480.0);
uniform vec2 world_origin = vec2(0.0);
uniform float haze_strength : hint_range(0.0, 0.35) = 0.055;
uniform float key_start : hint_range(0.0, 1.0) = 0.55;
uniform float key_end : hint_range(0.0, 1.0) = 0.74;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float exposure : hint_range(0.35, 1.25) = 0.74;

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


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - world_origin;
}


void fragment() {
	vec4 authored = texture(TEXTURE, UV);
	float luma = dot(authored.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec2 normal_step = TEXTURE_PIXEL_SIZE * 2.0;
	float height_left = dot(texture(TEXTURE, UV - vec2(normal_step.x, 0.0)).rgb, vec3(0.2126, 0.7152, 0.0722));
	float height_right = dot(texture(TEXTURE, UV + vec2(normal_step.x, 0.0)).rgb, vec3(0.2126, 0.7152, 0.0722));
	float height_up = dot(texture(TEXTURE, UV - vec2(0.0, normal_step.y)).rgb, vec3(0.2126, 0.7152, 0.0722));
	float height_down = dot(texture(TEXTURE, UV + vec2(0.0, normal_step.y)).rgb, vec3(0.2126, 0.7152, 0.0722));
	vec2 authored_gradient = clamp(
		vec2(height_right - height_left, height_down - height_up),
		vec2(-0.16),
		vec2(0.16)
	);
	vec3 authored_normal = normalize(vec3(-authored_gradient * 3.5, 1.0));
	// The generated plate carries a neutral light contact sheet outside the
	// authored rock. Key only that high-value range; the dark wet material and
	// its teal/rust highlights remain intact.
	float neutral_range = 1.0 - smoothstep(0.035, 0.16, max(authored.r, max(authored.g, authored.b)) - min(authored.r, min(authored.g, authored.b)));
	float keyed_background = smoothstep(key_start, key_end, luma) * neutral_range;
	vec2 world_uv = clamp(world_position / max(world_size, vec2(1.0)), vec2(0.0), vec2(1.0));
	float sdf_value = texture(terrain_sdf, world_uv).r;
	float contour_aa = max(fwidth(sdf_value) * 0.82, 1.0 / 255.0);
	// The authored overhang slightly overpaints the semantic edge, then the SDF
	// trims the generated plate so its silhouette still matches traversal.
	float edge_variation = (value_noise(world_position / 22.0) - 0.5) * 0.15;
	edge_variation += (value_noise(world_position / 51.0 + vec2(7.3, -2.8)) - 0.5) * 0.055;
	float shifted_sdf = sdf_value + edge_variation;
	float terrain_mask = smoothstep(0.475 - contour_aa, 0.505 + contour_aa, shifted_sdf);
	float alpha = (1.0 - keyed_background) * terrain_mask * opacity;
	vec3 integrated = mix(authored.rgb, authored.rgb * (1.0 - water_haze.rgb * 0.28) + water_haze.rgb * 0.12, haze_strength) * exposure;
	float edge_rim = (1.0 - smoothstep(0.012, 0.065, abs(shifted_sdf - 0.49))) * terrain_mask;
	integrated += water_haze.rgb * edge_rim * 0.19;
	NORMAL_MAP = authored_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = alpha * 0.32;
	COLOR = vec4(integrated, alpha);
}
