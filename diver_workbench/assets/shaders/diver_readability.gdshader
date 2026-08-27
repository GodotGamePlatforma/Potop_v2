shader_type canvas_item;
render_mode unshaded;

uniform vec4 rim_color : source_color = vec4(0.30, 0.78, 0.82, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.70;
uniform float color_lift : hint_range(0.0, 1.0) = 0.78;
uniform float exposure : hint_range(0.5, 2.0) = 1.16;
uniform float accent_strength : hint_range(0.0, 1.0) = 0.32;
uniform float action_glow : hint_range(0.0, 1.0) = 0.0;
uniform float damage_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 action_color : source_color = vec4(0.92, 0.66, 0.24, 1.0);
uniform vec4 damage_color : source_color = vec4(1.0, 0.24, 0.16, 1.0);


void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	vec2 pixel = TEXTURE_PIXEL_SIZE * 3.5;
	float nearby_alpha = 0.0;
	float inner_alpha = 1.0;
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(pixel.x, 0.0)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV - vec2(pixel.x, 0.0)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(0.0, pixel.y)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV - vec2(0.0, pixel.y)).a);
	inner_alpha = min(inner_alpha, texture(TEXTURE, UV + vec2(pixel.x, 0.0)).a);
	inner_alpha = min(inner_alpha, texture(TEXTURE, UV - vec2(pixel.x, 0.0)).a);
	inner_alpha = min(inner_alpha, texture(TEXTURE, UV + vec2(0.0, pixel.y)).a);
	inner_alpha = min(inner_alpha, texture(TEXTURE, UV - vec2(0.0, pixel.y)).a);
	float outer_edge = clamp(nearby_alpha - base.a, 0.0, 1.0);
	float inner_edge = base.a * (1.0 - smoothstep(0.08, 0.94, inner_alpha));
	float source_luma = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
	float shadow_weight = 1.0 - smoothstep(0.035, 0.30, source_luma);
	float warm_accent = smoothstep(0.025, 0.19, base.r - base.b)
		* smoothstep(0.08, 0.42, (base.r + base.g) * 0.5);
	float cool_accent = smoothstep(0.035, 0.20, base.b - base.r)
		* smoothstep(0.08, 0.44, (base.g + base.b) * 0.5);
	vec3 lifted = mix(base.rgb, pow(max(base.rgb, vec3(0.0)), vec3(0.54)), color_lift);
	lifted = min(lifted * exposure, vec3(1.0));
	lifted += vec3(0.018, 0.034, 0.040) * shadow_weight * base.a;
	lifted += vec3(0.24, 0.105, 0.018) * warm_accent * accent_strength;
	lifted += rim_color.rgb * cool_accent * accent_strength * 0.12;
	lifted += rim_color.rgb * base.a * 0.018;
	lifted += rim_color.rgb * inner_edge * rim_strength * 0.46;
	lifted = mix(lifted, lifted + action_color.rgb * (0.18 + inner_edge * 0.28), action_glow * base.a);
	lifted = mix(lifted, damage_color.rgb, damage_flash * base.a * (0.42 + inner_edge * 0.24));
	float outline_alpha = outer_edge * rim_strength * 0.62;
	vec3 final_color = mix(lifted, rim_color.rgb, outline_alpha);
	COLOR = vec4(final_color, max(base.a, outline_alpha));
}
