shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 light_color : source_color = vec4(1.0, 0.68, 0.42, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.12;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
// 0.0 = directional beam ribbon, 1.0 = compact source glow.
uniform float effect_mode : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centred_uv = UV * 2.0 - vec2(1.0);

	// The beam starts narrow at UV.y = 0 (the approved mount), remains optically
	// light and fades to zero before the deck. A broad lateral falloff avoids the
	// flat opaque core that made the previous quad read as a brown curtain.
	float along = clamp(UV.y, 0.0, 1.0);
	float width_variation = 1.0 + sin(along * 21.0) * 0.045 + sin(along * 47.0 + 1.7) * 0.025;
	float half_width = mix(0.030, 0.62, pow(along, 0.96)) * width_variation;
	float axis_wander = (sin(along * 17.0 + 0.8) + sin(along * 39.0) * 0.45) * 0.014 * along;
	float lateral_distance = (centred_uv.x - axis_wander) / max(half_width, 0.001);
	float lateral = exp(-4.0 * lateral_distance * lateral_distance);
	// Keep a narrow visible neck at the marker so the beam reads as coming from
	// the high source instead of appearing only as a pool on the receiving deck.
	float start_fade = mix(0.34, 1.0, smoothstep(0.0, 0.12, along));
	float end_fade = 1.0 - smoothstep(0.28, 0.46, along);
	float longitudinal_density = mix(0.98, 0.68, smoothstep(0.10, 0.40, along));
	float density_wisp = 0.92 + sin(along * 36.0 + centred_uv.x * 5.0) * 0.08;
	float beam_mask = lateral * start_fade * end_fade * longitudinal_density * density_wisp;

	// The glow is a light cue only: a small soft core with no fixture silhouette.
	float radial = length(centred_uv);
	float halo = pow(1.0 - smoothstep(0.0, 1.0, radial), 1.65);
	float core = 1.0 - smoothstep(0.0, 0.18, radial);
	float glow_mask = max(halo * 0.72, core);

	float mask = mix(beam_mask, glow_mask, step(0.5, effect_mode));
	ALBEDO = light_color.rgb * intensity;
	ALPHA = mask * opacity * light_color.a;
}
