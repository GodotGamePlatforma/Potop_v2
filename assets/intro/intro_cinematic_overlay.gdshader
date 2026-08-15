shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform float anim_time = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	float aspect = max(viewport_size.x / max(viewport_size.y, 1.0), 1.0);
	vec2 centered = UV * 2.0 - 1.0;
	centered.x *= aspect;
	float vignette = smoothstep(0.72, 1.52, length(centered));
	float subtitle_bed = smoothstep(0.64, 0.98, UV.y) * 0.52;
	float cloud_cap = (1.0 - smoothstep(0.0, 0.22, UV.y)) * 0.18;
	float grain = hash21(floor(FRAGCOORD.xy * 0.52) + floor(anim_time * 10.0));
	float grain_alpha = (grain - 0.5) * 0.032;
	float alpha = clamp(vignette * 0.48 + subtitle_bed + cloud_cap + grain_alpha, 0.0, 0.74) * strength;
	COLOR = vec4(vec3(0.012, 0.032, 0.041), alpha);
}
