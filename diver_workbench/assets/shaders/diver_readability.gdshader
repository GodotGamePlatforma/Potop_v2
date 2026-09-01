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
uniform float lantern_glint : hint_range(0.0, 1.0) = 0.0;
uniform vec4 lantern_color : source_color = vec4(0.72, 0.90, 1.0, 1.0);


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


vec3 luma_preserving_tint(vec3 tint, float source_luma) {
	float tint_luma = dot(tint, vec3(0.2126, 0.7152, 0.0722));
	if (tint_luma <= 0.0001) {
		// A black/degenerate authored tint has no chroma direction. Neutral gray
		// is the only fallback that keeps the source luminance exactly intact.
		return vec3(source_luma);
	}
	vec3 chromatic_target = tint * (source_luma / tint_luma);
	float peak = max(max(chromatic_target.r, chromatic_target.g), chromatic_target.b);
	if (peak <= 1.0) {
		return chromatic_target;
	}
	// Pull an out-of-gamut tint towards neutral at the same luminance instead
	// of clipping its highlights and flattening the authored volume.
	float chroma_limit = clamp(
		(1.0 - source_luma) / max(peak - source_luma, 0.001),
		0.0,
		1.0
	);
	return mix(vec3(source_luma), chromatic_target, chroma_limit);
}


void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	base.a *= handoff_visibility(UV, TEXTURE_PIXEL_SIZE);
	vec2 pixel = TEXTURE_PIXEL_SIZE * outline_width;
	// The diagonal vector has the same radius as a cardinal sample. Eight-way
	// coverage therefore closes corner gaps without exceeding the reviewed
	// source padding or expanding the visual envelope.
	vec2 diagonal_pixel = pixel * 0.70710678;
	vec2 right_uv = UV + vec2(pixel.x, 0.0);
	vec2 left_uv = UV - vec2(pixel.x, 0.0);
	vec2 down_uv = UV + vec2(0.0, pixel.y);
	vec2 up_uv = UV - vec2(0.0, pixel.y);
	vec2 down_right_uv = UV + diagonal_pixel;
	vec2 up_left_uv = UV - diagonal_pixel;
	vec2 up_right_uv = UV + vec2(diagonal_pixel.x, -diagonal_pixel.y);
	vec2 down_left_uv = UV + vec2(-diagonal_pixel.x, diagonal_pixel.y);
	vec4 right_sample = texture(TEXTURE, right_uv);
	vec4 left_sample = texture(TEXTURE, left_uv);
	vec4 down_sample = texture(TEXTURE, down_uv);
	vec4 up_sample = texture(TEXTURE, up_uv);
	vec4 down_right_sample = texture(TEXTURE, down_right_uv);
	vec4 up_left_sample = texture(TEXTURE, up_left_uv);
	vec4 up_right_sample = texture(TEXTURE, up_right_uv);
	vec4 down_left_sample = texture(TEXTURE, down_left_uv);
	float right_alpha = right_sample.a * COLOR.a * handoff_visibility(right_uv, TEXTURE_PIXEL_SIZE);
	float left_alpha = left_sample.a * COLOR.a * handoff_visibility(left_uv, TEXTURE_PIXEL_SIZE);
	float down_alpha = down_sample.a * COLOR.a * handoff_visibility(down_uv, TEXTURE_PIXEL_SIZE);
	float up_alpha = up_sample.a * COLOR.a * handoff_visibility(up_uv, TEXTURE_PIXEL_SIZE);
	float down_right_alpha = down_right_sample.a * COLOR.a * handoff_visibility(down_right_uv, TEXTURE_PIXEL_SIZE);
	float up_left_alpha = up_left_sample.a * COLOR.a * handoff_visibility(up_left_uv, TEXTURE_PIXEL_SIZE);
	float up_right_alpha = up_right_sample.a * COLOR.a * handoff_visibility(up_right_uv, TEXTURE_PIXEL_SIZE);
	float down_left_alpha = down_left_sample.a * COLOR.a * handoff_visibility(down_left_uv, TEXTURE_PIXEL_SIZE);
	float cardinal_max_alpha = max(max(right_alpha, left_alpha), max(down_alpha, up_alpha));
	float diagonal_max_alpha = max(max(down_right_alpha, up_left_alpha), max(up_right_alpha, down_left_alpha));
	float cardinal_min_alpha = min(min(right_alpha, left_alpha), min(down_alpha, up_alpha));
	float diagonal_min_alpha = min(min(down_right_alpha, up_left_alpha), min(up_right_alpha, down_left_alpha));
	// Q1 is the exact approved v4 baseline. Only upgraded suit treatments may
	// opt into the new diagonal coverage and stronger rim response. The action
	// layer also stays on the legacy path because its treatment is disabled.
	float readability_polish = 0.0;
	if (suit_treatment_enabled && style_selector(0.0) < 0.5) {
		readability_polish = 1.0;
	}
	float nearby_alpha = cardinal_max_alpha;
	float inner_alpha = cardinal_min_alpha;
	if (readability_polish > 0.5) {
		nearby_alpha = max(cardinal_max_alpha, diagonal_max_alpha);
		inner_alpha = min(cardinal_min_alpha, diagonal_min_alpha);
	}
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
	vec3 fabric_target = luma_preserving_tint(suit_fabric_color.rgb, source_luma);
	vec3 metal_target = luma_preserving_tint(suit_metal_color.rgb, source_luma);
	base.rgb = mix(base.rgb, fabric_target, fabric_mask * suit_fabric_mix * suit_enabled);
	base.rgb = mix(base.rgb, metal_target, metal_mask * suit_metal_mix * suit_enabled);

	// Construction accents follow real luminance detail and the silhouette edge.
	// Frame-space stripes and boxes read as scanlines or flat decals on animation.
	float right_luma = dot(right_sample.rgb * COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float left_luma = dot(left_sample.rgb * COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float down_luma = dot(down_sample.rgb * COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float up_luma = dot(up_sample.rgb * COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float cardinal_detail_delta = max(
		max(abs(source_luma - right_luma), abs(source_luma - left_luma)),
		max(abs(source_luma - down_luma), abs(source_luma - up_luma))
	);
	float down_right_luma = dot(down_right_sample.rgb * COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float up_left_luma = dot(up_left_sample.rgb * COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float up_right_luma = dot(up_right_sample.rgb * COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float down_left_luma = dot(down_left_sample.rgb * COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float diagonal_detail_delta = max(
		max(abs(source_luma - down_right_luma), abs(source_luma - up_left_luma)),
		max(abs(source_luma - up_right_luma), abs(source_luma - down_left_luma))
	);
	float detail_delta = cardinal_detail_delta;
	if (readability_polish > 0.5) {
		detail_delta = max(cardinal_detail_delta, diagonal_detail_delta);
	}
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
	// Upgraded suits need a large material mass that survives the gameplay
	// camera, not only thin detail-edge accents. The source luminance still
	// models the volume, so this remains a treatment of the authored raster.
	float broad_panel_mask = fabric_mask * smoothstep(0.025, 0.22, source_luma)
		* (1.0 - smoothstep(0.68, 0.96, source_luma));
	float broad_panel_mix = broad_panel_mask * suit_enabled * (
		sealed_style * suit_pattern_strength * 0.16
		+ pressure_style * suit_plate_strength * 0.19
		+ abyss_style * suit_emissive_strength * 0.24
	);
	vec3 broad_panel_tint = mix(
		suit_fabric_color.rgb,
		suit_pattern_color.rgb,
		sealed_style * 0.20 + pressure_style * 0.14 + abyss_style * 0.24
	);
	vec3 broad_panel_target = luma_preserving_tint(broad_panel_tint, source_luma);
	base.rgb = mix(base.rgb, broad_panel_target, clamp(broad_panel_mix, 0.0, 0.28));

	vec3 lifted = mix(base.rgb, pow(max(base.rgb, vec3(0.0)), vec3(0.54)), color_lift);
	lifted = min(lifted * exposure, vec3(1.0));
	lifted += vec3(0.018, 0.034, 0.040) * shadow_weight * base.a;
	lifted += vec3(0.24, 0.105, 0.018) * warm_accent * accent_strength;
	lifted += rim_color.rgb * cool_accent * accent_strength * 0.12;
	lifted += rim_color.rgb * base.a * 0.018;
	float inner_rim_scale = 0.46;
	float outer_rim_scale = 0.62;
	if (readability_polish > 0.5) {
		inner_rim_scale = 0.48;
		outer_rim_scale = 0.68;
	}
	lifted += rim_color.rgb * inner_edge * rim_strength * inner_rim_scale;
	lifted += suit_pattern_color.rgb * max(detail_edge * 0.26, inner_edge * 0.44)
		* abyss_style * suit_emissive_strength * fabric_mask * suit_enabled;
	lifted = mix(lifted, lifted + action_color.rgb * (0.18 + inner_edge * 0.28), action_glow * base.a);
	lifted = mix(lifted, damage_color.rgb, damage_flash * base.a * (0.42 + inner_edge * 0.24));
	float outline_alpha = outer_edge * rim_strength * outer_rim_scale;
	float lantern_surface = max(metal_mask * 0.72, inner_edge * 0.38) * base.a;
	lifted += lantern_color.rgb * lantern_glint * (base.a * 0.028 + lantern_surface * 0.24);
	outline_alpha = clamp(outline_alpha + outer_edge * lantern_glint * 0.14, 0.0, 1.0);
	vec3 final_color = mix(lifted, rim_color.rgb, outline_alpha);
	COLOR = vec4(final_color, max(base.a, outline_alpha));
}
