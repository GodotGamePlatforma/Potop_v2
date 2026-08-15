shader_type canvas_item;

// Presentation-only concrete edge for authored R1 ArtCells. The canonical
// terrain SDF remains the sole geometry authority and the global terrain stays
// visible below this local material pass.
uniform sampler2D terrain_sdf : repeat_disable, filter_linear;
uniform sampler2D concrete_albedo : source_color, repeat_disable, filter_linear_mipmap;
uniform vec2 world_size = vec2(11520.0, 6480.0);
uniform vec2 world_origin = vec2(0.0);
uniform vec2 cell_half_size = vec2(1120.0, 650.0);
uniform vec2 cell_feather = vec2(150.0, 110.0);
uniform float band_start : hint_range(0.50, 0.90) = 0.55;
uniform float band_end : hint_range(0.51, 1.00) = 0.72;
uniform float opacity : hint_range(0.0, 1.0) = 0.96;
uniform vec4 concrete_dark : source_color = vec4(0.024, 0.041, 0.044, 1.0);
uniform vec4 concrete_mid : source_color = vec4(0.135, 0.188, 0.190, 1.0);
uniform vec4 concrete_light : source_color = vec4(0.265, 0.350, 0.350, 1.0);
uniform vec4 algae_tint : source_color = vec4(0.110, 0.225, 0.135, 1.0);
uniform vec4 wet_edge_tint : source_color = vec4(0.110, 0.390, 0.430, 1.0);
uniform float edge_ao_strength : hint_range(0.0, 1.0) = 0.72;
uniform float edge_cap_strength : hint_range(0.0, 1.0) = 0.56;
uniform float normal_depth : hint_range(0.0, 1.0) = 0.23;

varying vec2 world_position;
varying vec2 local_position;


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
	local_position = VERTEX;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy - world_origin;
}


void fragment() {
	vec2 world_uv = clamp(world_position / max(world_size, vec2(1.0)), vec2(0.0), vec2(1.0));
	float sdf_value = texture(terrain_sdf, world_uv).r;
	float contour_aa = max(fwidth(sdf_value) * 0.9, 1.0 / 255.0);
	float solid_alpha = smoothstep(0.5 - contour_aa, 0.5 + contour_aa, sdf_value);

	vec2 cell_margin = cell_half_size - abs(local_position);
	float cell_fade = smoothstep(0.0, cell_feather.x, cell_margin.x)
		* smoothstep(0.0, cell_feather.y, cell_margin.y);
	float coverage = solid_alpha * cell_fade * opacity;
	if (coverage <= 0.002) {
		discard;
	}

	// One non-repeating authored sample spans the full cell. It supplies broad
	// cracks and slab joints without creating a tiled embossed pattern.
	float cell_diameter = cell_half_size.x * 2.0;
	vec2 concrete_uv = local_position / cell_diameter + vec2(0.5);
	vec3 source = texture(concrete_albedo, concrete_uv).rgb;
	float broad_macro = value_noise(world_position / 510.0 + vec2(7.1, -3.4));
	vec3 authored_concrete = source * vec3(0.62, 0.78, 0.76);
	vec3 concrete_color = mix(concrete_dark.rgb, authored_concrete, 0.88);
	concrete_color *= mix(0.84, 1.08, broad_macro);
	float source_luma = dot(source, vec3(0.2126, 0.7152, 0.0722));
	concrete_color = mix(concrete_color, concrete_mid.rgb, smoothstep(0.46, 0.76, source_luma) * 0.16);
	concrete_color += concrete_light.rgb * smoothstep(0.72, 0.94, source_luma) * 0.055;

	vec2 sdf_step = vec2(1.0 / 1440.0, 1.0 / 810.0);
	vec2 sdf_gradient = vec2(
		texture(terrain_sdf, world_uv + vec2(sdf_step.x, 0.0)).r - texture(terrain_sdf, world_uv - vec2(sdf_step.x, 0.0)).r,
		texture(terrain_sdf, world_uv + vec2(0.0, sdf_step.y)).r - texture(terrain_sdf, world_uv - vec2(0.0, sdf_step.y)).r
	);
	vec2 edge_normal = normalize(sdf_gradient + vec2(0.00001));
	float contact = (1.0 - smoothstep(0.50 + contour_aa, 0.57, sdf_value)) * solid_alpha;
	float bevel = smoothstep(0.52, 0.58, sdf_value) * (1.0 - smoothstep(0.63, band_end, sdf_value));
	float upper_facing = clamp(dot(edge_normal, vec2(0.0, -1.0)) * 0.5 + 0.5, 0.0, 1.0);
	concrete_color = mix(concrete_color, concrete_dark.rgb * 0.54, contact * edge_ao_strength);

	float edge_breakup = value_noise(world_position / 76.0 + vec2(11.3, 2.7));
	float concrete_cap = (1.0 - smoothstep(band_start, band_end, sdf_value)) * solid_alpha;
	float algae = concrete_cap * smoothstep(0.48, 0.75, edge_breakup + broad_macro * 0.20);
	concrete_color = mix(concrete_color, algae_tint.rgb, algae * edge_cap_strength);
	concrete_color += wet_edge_tint.rgb * concrete_cap * mix(0.028, 0.13, upper_facing);

	vec3 bevel_normal = normalize(vec3(-edge_normal * 0.85, 1.0));
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), bevel_normal * 0.5 + 0.5, bevel);
	NORMAL_MAP_DEPTH = normal_depth;
	COLOR = vec4(max(concrete_color, vec3(0.0)), coverage);
}
