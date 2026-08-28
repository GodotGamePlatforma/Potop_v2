shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float anim_time = 0.0;
uniform float outline_strength : hint_range(0.0, 0.5) = 0.18;
uniform float base_strength : hint_range(0.0, 0.5) = 0.22;
uniform float base_start : hint_range(0.0, 1.0) = 0.77;
uniform float reduced_motion : hint_range(0.0, 1.0) = 0.0;
uniform vec4 outline_color : source_color = vec4(0.45, 0.80, 0.80, 1.0);
uniform vec4 base_tint : source_color = vec4(0.20, 0.35, 0.38, 1.0);

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 sample_step = TEXTURE_PIXEL_SIZE * 2.25;
	float alpha_max = source.a;
	float alpha_min = source.a;

	float sample_alpha = texture(TEXTURE, UV + vec2(sample_step.x, 0.0)).a;
	alpha_max = max(alpha_max, sample_alpha);
	alpha_min = min(alpha_min, sample_alpha);
	sample_alpha = texture(TEXTURE, UV - vec2(sample_step.x, 0.0)).a;
	alpha_max = max(alpha_max, sample_alpha);
	alpha_min = min(alpha_min, sample_alpha);
	sample_alpha = texture(TEXTURE, UV + vec2(0.0, sample_step.y)).a;
	alpha_max = max(alpha_max, sample_alpha);
	alpha_min = min(alpha_min, sample_alpha);
	sample_alpha = texture(TEXTURE, UV - vec2(0.0, sample_step.y)).a;
	alpha_max = max(alpha_max, sample_alpha);
	alpha_min = min(alpha_min, sample_alpha);

	float silhouette_edge = smoothstep(0.025, 0.38, alpha_max - alpha_min);
	float restrained_pulse = mix(
		0.95 + 0.05 * sin(anim_time * 1.20),
		1.0,
		reduced_motion
	);
	float outline_alpha = silhouette_edge * outline_strength * restrained_pulse;

	// Only the low foundation band is ever filled. The rest of the target
	// texture is represented by its edge, never by a translucent full ghost.
	float base_gate = smoothstep(base_start, min(base_start + 0.045, 1.0), UV.y);
	float foundation_alpha = source.a * base_gate * base_strength;
	vec3 foundation_color = mix(source.rgb, base_tint.rgb, 0.72);
	float result_alpha = max(outline_alpha, foundation_alpha);
	vec3 result_color = mix(outline_color.rgb, foundation_color, step(outline_alpha, foundation_alpha));
	COLOR = vec4(result_color, result_alpha);
}
