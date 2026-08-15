shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 light_color : source_color = vec4(0.72, 0.90, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 1.0;

varying vec2 cone_uv;


void vertex() {
	float axial = clamp(VERTEX.x / 350.0, 0.0, 1.0);
	float half_width = mix(88.0, 176.0, axial);
	cone_uv = vec2(axial, VERTEX.y / max(half_width * 2.0, 0.001) + 0.5);
}


void fragment() {
	float axial = smoothstep(0.0, 0.045, cone_uv.x) * (1.0 - smoothstep(0.68, 1.0, cone_uv.x));
	float half_width = mix(0.18, 0.50, smoothstep(0.0, 1.0, cone_uv.x));
	float lateral_distance = abs(cone_uv.y - 0.5) / max(half_width, 0.001);
	float soft_body = 1.0 - smoothstep(0.46, 1.0, lateral_distance);
	float core_width = mix(0.09, 0.26, cone_uv.x);
	float core = 1.0 - smoothstep(0.28, 1.0, abs(cone_uv.y - 0.5) / max(core_width, 0.001));
	float body_alpha = axial * (soft_body * 0.105 + core * 0.055) * intensity;
	float source_glow = (1.0 - smoothstep(0.0, 0.16, cone_uv.x)) * (1.0 - smoothstep(0.0, 1.0, lateral_distance));
	float alpha = clamp(body_alpha + source_glow * 0.16 * intensity, 0.0, 0.24);
	vec3 warm_core = vec3(1.0, 0.88, 0.67);
	vec3 beam_color = mix(light_color.rgb, warm_core, core * 0.24);
	COLOR = vec4(beam_color, alpha * light_color.a);
}
