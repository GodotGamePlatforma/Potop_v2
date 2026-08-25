shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float anim_time = 0.0;
uniform float depth_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.12;
uniform vec2 flow_vector = vec2(0.0);
uniform vec2 world_anchor = vec2(0.0);
uniform vec4 accent_color : source_color = vec4(0.25, 0.82, 0.86, 1.0);


float caustic_band(vec2 point, float scale, float phase) {
	vec2 warped = point * scale;
	warped += vec2(
		sin(warped.y * 1.7 + phase),
		cos(warped.x * 1.3 - phase)
	) * 0.18;
	float first = abs(sin(warped.x + sin(warped.y * 1.2 + phase)));
	float second = abs(cos(warped.y * 0.92 - cos(warped.x + phase * 0.7)));
	return pow(max(0.0, 1.0 - abs(first - second) * 5.2), 5.0);
}


void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	vec2 world_locked = centered * vec2(4.8, 2.8) + world_anchor / 245.0;
	vec2 flow = flow_vector * anim_time * 0.032;
	float broad = caustic_band(world_locked + flow, 5.4, anim_time * 0.27);
	float fine = caustic_band(world_locked - flow * 0.58, 9.7, -anim_time * 0.21);
	float breakup = smoothstep(-0.42, 0.64, sin(dot(world_locked, vec2(1.37, -1.91)) + anim_time * 0.08));
	float field = (broad * 0.58 + fine * 0.42) * mix(0.28, 1.0, breakup);
	float edge_fade = (1.0 - smoothstep(0.64, 1.0, abs(centered.x))) * (1.0 - smoothstep(0.62, 1.0, abs(centered.y)));
	float depth_fade = mix(1.0, 0.08, pow(depth_ratio, 1.35));
	float alpha = field * edge_fade * depth_fade * intensity;
	COLOR = vec4(accent_color.rgb * alpha, alpha);
}
