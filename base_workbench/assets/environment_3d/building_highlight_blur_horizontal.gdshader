shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D source_mask : filter_linear, repeat_disable;
uniform int glow_radius : hint_range(2, 6, 2) = 6;
uniform float glow_spread : hint_range(1.0, 3.0, 0.05) = 2.4;

float mask_alpha(vec2 sample_uv, vec2 texel_size) {
	vec2 safe_minimum = texel_size * 0.5;
	vec2 safe_maximum = vec2(1.0) - safe_minimum;
	if (
		sample_uv.x < safe_minimum.x
		|| sample_uv.y < safe_minimum.y
		|| sample_uv.x > safe_maximum.x
		|| sample_uv.y > safe_maximum.y
	) {
		return 0.0;
	}
	return texture(source_mask, sample_uv).a;
}

float weighted_axis_blur(vec2 center_uv, vec2 axis_texel, vec2 texel_size) {
	if (glow_radius <= 2) {
		return mask_alpha(center_uv, texel_size) * 0.375
			+ (mask_alpha(center_uv + axis_texel * 1.2, texel_size) + mask_alpha(center_uv - axis_texel * 1.2, texel_size)) * 0.3125;
	}
	if (glow_radius <= 4) {
		return mask_alpha(center_uv, texel_size) * 0.2734375
			+ (mask_alpha(center_uv + axis_texel * 1.333333, texel_size) + mask_alpha(center_uv - axis_texel * 1.333333, texel_size)) * 0.328125
			+ (mask_alpha(center_uv + axis_texel * 3.111111, texel_size) + mask_alpha(center_uv - axis_texel * 3.111111, texel_size)) * 0.03515625;
	}
	return mask_alpha(center_uv, texel_size) * 0.22558594
		+ (mask_alpha(center_uv + axis_texel * 1.384615, texel_size) + mask_alpha(center_uv - axis_texel * 1.384615, texel_size)) * 0.31420898
		+ (mask_alpha(center_uv + axis_texel * 3.230769, texel_size) + mask_alpha(center_uv - axis_texel * 3.230769, texel_size)) * 0.06982422
		+ (mask_alpha(center_uv + axis_texel * 5.076923, texel_size) + mask_alpha(center_uv - axis_texel * 5.076923, texel_size)) * 0.00317383;
}

void fragment() {
	float blurred_alpha = clamp(weighted_axis_blur(UV, vec2(TEXTURE_PIXEL_SIZE.x * glow_spread, 0.0), TEXTURE_PIXEL_SIZE), 0.0, 1.0);
	COLOR = vec4(blurred_alpha, blurred_alpha, blurred_alpha, blurred_alpha);
}
