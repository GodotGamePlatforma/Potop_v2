shader_type canvas_item;
render_mode unshaded;

uniform vec4 rim_color : source_color = vec4(0.30, 0.78, 0.82, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.70;
uniform float outline_width : hint_range(0.0, 3.5) = 3.5;
uniform float color_lift : hint_range(0.0, 1.0) = 0.78;
uniform float exposure : hint_range(0.5, 2.0) = 1.16;
uniform float accent_strength : hint_range(0.0, 1.0) = 0.32;
uniform vec4 suit_fabric_color : source_color = vec4(0.145, 0.231, 0.282, 1.0);
uniform vec4 suit_metal_color : source_color = vec4(0.529, 0.376, 0.212, 1.0);
uniform vec4 suit_pattern_color : source_color = vec4(0.30, 0.78, 0.82, 1.0);
uniform float suit_style : hint_range(0.0, 3.0) = 0.0;
uniform float suit_fabric_mix : hint_range(0.0, 1.0) = 0.0;
uniform float suit_metal_mix : hint_range(0.0, 1.0) = 0.0;
uniform float suit_pattern_strength : hint_range(0.0, 1.0) = 0.0;
uniform float suit_plate_strength : hint_range(0.0, 1.0) = 0.0;
uniform float suit_emissive_strength : hint_range(0.0, 1.0) = 0.0;
uniform bool suit_treatment_enabled = true;
uniform bool handoff_enabled = false;
uniform float handoff_mix : hint_range(0.0, 1.0) = 1.0;
uniform float handoff_role : hint_range(0.0, 1.0) = 1.0;
uniform float action_glow : hint_range(0.0, 1.0) = 0.0;
uniform float damage_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 action_color : source_color = vec4(0.92, 0.66, 0.24, 1.0);
uniform vec4 damage_color : source_color = vec4(1.0, 0.24, 0.16, 1.0);


float handoff_visibility(vec2 uv, vec2 texture_pixel_size) {
	if (!handoff_enabled) {
		return 1.0;
	}
	// A short opacity handoff preserves the source silhouette. Ordered alpha
	// dithering produced a one-frame cyan fragmentation at gameplay scale.
	return mix(1.0 - handoff_mix, handoff_mix, handoff_role);
}


float style_selector(float expected) {
	return 1.0 - step(0.5, abs(suit_style - expected));
}


void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	base.a *= handoff_visibility(UV, TEXTURE_PIXEL_SIZE);
	vec2 pixel = TEXTURE_PIXEL_SIZE * outline_width;
	vec2 right_uv = UV + vec2(pixel.x, 0.0);
	vec2 left_uv = UV - vec2(pixel.x, 0.0);
	vec2 down_uv = UV + vec2(0.0, pixel.y);
	vec2 up_uv = UV - vec2(0.0, pixel.y);
	float right_alpha = texture(TEXTURE, right_uv).a * COLOR.a * handoff_visibility(right_uv, TEXTURE_PIXEL_SIZE);
	float left_alpha = texture(TEXTURE, left_uv).a * COLOR.a * handoff_visibility(left_uv, TEXTURE_PIXEL_SIZE);
	float down_alpha = texture(TEXTURE, down_uv).a * COLOR.a * handoff_visibility(down_uv, TEXTURE_PIXEL_SIZE);
	float up_alpha = texture(TEXTURE, up_uv).a * COLOR.a * handoff_visibility(up_uv, TEXTURE_PIXEL_SIZE);
	float nearby_alpha = max(max(right_alpha, left_alpha), max(down_alpha, up_alpha));
	float inner_alpha = min(min(right_alpha, left_alpha), min(down_alpha, up_alpha));
	float outer_edge = clamp(nearby_alpha - base.a, 0.0, 1.0);
	float inner_edge = base.a * (1.0 - smoothstep(0.08, 0.94, inner_alpha));
	float source_luma = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
	float shadow_weight = 1.0 - smoothstep(0.035, 0.30, source_luma);
	float warm_accent = smoothstep(0.025, 0.19, base.r - base.b)
		* smoothstep(0.08, 0.42, (base.r + base.g) * 0.5);
	float cool_accent = smoothstep(0.035, 0.20, base.b - base.r)
		* smoothstep(0.08, 0.44, (base.g + base.b) * 0.5);
	float metal_mask = smoothstep(0.08, 0.42, warm_accent) * base.a;
	float suit_enabled = 1.0;
	if (!suit_treatment_enabled) {
		suit_enabled = 0.0;
	}
	// Preserve the source luminance modelling while giving each equipment tier a
	// broad, readable fabric mass. Restricting this to midtones made all suits
	// collapse back to the same brass silhouette at the gameplay camera scale.
	float fabric_mask = base.a * (1.0 - metal_mask * 0.94);
	vec3 fabric_target = suit_fabric_color.rgb * (0.42 + source_luma * 1.50);
	vec3 metal_target = suit_metal_color.rgb * (0.28 + source_luma * 1.30);
	base.rgb = mix(base.rgb, fabric_target, fabric_mask * suit_fabric_mix * suit_enabled);
	base.rgb = mix(base.rgb, metal_target, metal_mask * suit_metal_mix * suit_enabled);

	// Construction accents follow real luminance detail and the silhouette edge.
	// Frame-space stripes and boxes read as scanlines or flat decals on animation.
	float right_luma = dot(texture(TEXTURE, right_uv).rgb * COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float left_luma = dot(texture(TEXTURE, left_uv).rgb * COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float down_luma = dot(texture(TEXTURE, down_uv).rgb * COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float up_luma = dot(texture(TEXTURE, up_uv).rgb * COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float detail_delta = max(
		max(abs(source_luma - right_luma), abs(source_luma - left_luma)),
		max(abs(source_luma - down_luma), abs(source_luma - up_luma))
	);
	float detail_edge = smoothstep(0.035, 0.18, detail_delta) * base.a;
	float sealed_style = style_selector(1.0);
	float pressure_style = style_selector(2.0);
	float abyss_style = style_selector(3.0);
	float pattern_mask = (
		sealed_style * detail_edge * 0.32
		+ pressure_style * detail_edge * (0.38 + metal_mask * 0.28)
		+ abyss_style * max(detail_edge * 0.34, inner_edge * 0.52)
	) * fabric_mask;
	float plate_mask = detail_edge * fabric_mask
		* (pressure_style * 0.42 + abyss_style * 0.18);
	float construction_mix = clamp(
		pattern_mask * suit_pattern_strength * 0.58
			+ plate_mask * suit_plate_strength * 0.46,
		0.0,
		0.32
	);
	vec3 pattern_target = suit_pattern_color.rgb * (0.30 + source_luma * 0.92);
	base.rgb = mix(base.rgb, pattern_target, construction_mix * suit_enabled);

	vec3 lifted = mix(base.rgb, pow(max(base.rgb, vec3(0.0)), vec3(0.54)), color_lift);
	lifted = min(lifted * exposure, vec3(1.0));
	lifted += vec3(0.018, 0.034, 0.040) * shadow_weight * base.a;
	lifted += vec3(0.24, 0.105, 0.018) * warm_accent * accent_strength;
	lifted += rim_color.rgb * cool_accent * accent_strength * 0.12;
	lifted += rim_color.rgb * base.a * 0.018;
	lifted += rim_color.rgb * inner_edge * rim_strength * 0.46;
	lifted += suit_pattern_color.rgb * max(detail_edge * 0.26, inner_edge * 0.44)
		* abyss_style * suit_emissive_strength * fabric_mask * suit_enabled;
	lifted = mix(lifted, lifted + action_color.rgb * (0.18 + inner_edge * 0.28), action_glow * base.a);
	lifted = mix(lifted, damage_color.rgb, damage_flash * base.a * (0.42 + inner_edge * 0.24));
	float outline_alpha = outer_edge * rim_strength * 0.62;
	vec3 final_color = mix(lifted, rim_color.rgb, outline_alpha);
	COLOR = vec4(final_color, max(base.a, outline_alpha));
}
