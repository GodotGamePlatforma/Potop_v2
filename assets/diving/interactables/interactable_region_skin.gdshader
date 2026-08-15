shader_type canvas_item;

uniform vec4 region_tint : source_color = vec4(0.65, 0.72, 0.73, 1.0);
uniform vec4 patina_color : source_color = vec4(0.38, 0.46, 0.47, 1.0);
uniform vec4 rim_color : source_color = vec4(0.70, 0.84, 0.85, 1.0);
uniform float patina_mode : hint_range(0.0, 4.0, 1.0) = 0.0;
uniform float tint_strength : hint_range(0.0, 0.5) = 0.1;
uniform float patina_strength : hint_range(0.0, 0.6) = 0.18;
uniform float detail_level : hint_range(0.0, 2.0, 1.0) = 2.0;
uniform float stable_seed : hint_range(0.0, 1.0) = 0.5;
uniform float state_strength : hint_range(0.0, 1.0) = 1.0;


float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32 + stable_seed * 17.0);
	return fract(point.x * point.y);
}


void fragment() {
	vec4 vertex_color = COLOR;
	vec4 texel = texture(TEXTURE, UV);
	float coarse = hash21(floor(UV * vec2(11.0, 13.0)) + vec2(stable_seed * 19.0));
	float fine = hash21(floor(UV * vec2(29.0, 31.0)) + vec2(stable_seed * 41.0));
	float bottom_deposit = smoothstep(0.48, 0.96, UV.y + (coarse - 0.5) * 0.20);
	float patina_mask = bottom_deposit * smoothstep(0.34, 0.72, coarse);

	if (patina_mode > 1.5 && patina_mode < 2.5) {
		float algae_strand = 1.0 - smoothstep(0.025, 0.075, abs(fract(UV.x * 8.0 + stable_seed * 5.0) - 0.5));
		patina_mask = max(patina_mask * 0.68, algae_strand * smoothstep(0.16, 0.84, UV.y) * (0.30 + coarse * 0.70));
	} else if (patina_mode > 2.5 && patina_mode < 3.5) {
		float rust_spot = smoothstep(0.69, 0.88, coarse * 0.72 + fine * 0.28);
		patina_mask = max(patina_mask * 0.78, rust_spot * (0.48 + bottom_deposit * 0.52));
	} else if (patina_mode > 3.5) {
		float black_silt = smoothstep(0.35, 0.80, bottom_deposit * 0.76 + coarse * 0.24);
		patina_mask = max(patina_mask, black_silt);
	} else if (patina_mode > 0.5) {
		float mineral_film = smoothstep(0.54, 0.82, coarse) * (0.38 + bottom_deposit * 0.62);
		patina_mask = max(patina_mask * 0.62, mineral_film);
	}

	float quality_detail = mix(0.34, 1.0, clamp(detail_level * 0.5, 0.0, 1.0));
	patina_mask *= patina_strength * quality_detail * state_strength;
	vec3 tinted = texel.rgb * mix(vec3(1.0), region_tint.rgb, 0.42);
	vec3 graded = mix(texel.rgb, tinted, tint_strength * state_strength);
	graded *= 1.08;
	graded = mix(graded, patina_color.rgb, clamp(patina_mask, 0.0, 0.52));

	if (detail_level > 1.5) {
		vec2 pixel = TEXTURE_PIXEL_SIZE;
		float neighbor_alpha = min(
			min(texture(TEXTURE, UV + vec2(pixel.x, 0.0)).a, texture(TEXTURE, UV - vec2(pixel.x, 0.0)).a),
			min(texture(TEXTURE, UV + vec2(0.0, pixel.y)).a, texture(TEXTURE, UV - vec2(0.0, pixel.y)).a)
		);
		float inner_rim = clamp(texel.a - neighbor_alpha, 0.0, 1.0);
		graded = mix(graded, rim_color.rgb, inner_rim * 0.24 * state_strength);
	}

	COLOR = vec4(graded, texel.a) * vertex_color;
}
