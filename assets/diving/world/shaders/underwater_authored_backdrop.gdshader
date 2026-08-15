shader_type canvas_item;
render_mode unshaded, blend_mix;

// Authored biome plates keep their baked material hierarchy. This lightweight
// material only integrates them with the surrounding water and removes the
// rectangular edge before the shared screen atmosphere is applied.
uniform vec4 water_haze : source_color = vec4(0.025, 0.19, 0.24, 1.0);
uniform float haze_strength : hint_range(0.0, 0.4) = 0.055;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float edge_softness : hint_range(0.001, 0.25) = 0.075;
uniform float warm_practical_lift : hint_range(0.0, 0.5) = 0.12;


void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float horizontal_fade = smoothstep(0.0, edge_softness, UV.x)
		* smoothstep(0.0, edge_softness, 1.0 - UV.x);
	float vertical_fade = smoothstep(0.0, edge_softness, UV.y)
		* smoothstep(0.0, edge_softness, 1.0 - UV.y);
	float edge_fade = horizontal_fade * vertical_fade;

	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	float distance_haze = smoothstep(0.16, 0.88, UV.y) * haze_strength;
	vec3 integrated = mix(source.rgb, water_haze.rgb, distance_haze);
	float warm_mask = smoothstep(0.055, 0.24, source.r - source.b)
		* smoothstep(0.24, 0.78, luminance);
	integrated += vec3(0.34, 0.145, 0.035) * warm_mask * warm_practical_lift;

	COLOR = vec4(max(integrated, vec3(0.0)), source.a * edge_fade * opacity);
}
