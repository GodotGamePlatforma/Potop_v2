shader_type canvas_item;

uniform sampler2D clip_mask : filter_nearest, repeat_disable;
// Presentation-only RGBA data: R exposed edge/sediment, G owner seam and
// subordinate fixed anchors/cables, B generic entrance-frame wear. Alpha is
// reserved and never participates in clipping.
uniform sampler2D surface_detail_mask : filter_linear, repeat_disable;
// The builder enables detail only for structure_owner_masked. Interior assets
// retain their source RGB and canonical open-water clipping unchanged.
uniform bool detail_enabled = false;
uniform vec2 local_rect_origin = vec2(0.0);
uniform vec2 local_rect_size = vec2(1.0);
uniform vec2 structure_size = vec2(1.0);
uniform vec2 world_rect_origin = vec2(0.0);
uniform vec2 world_size = vec2(1.0);
uniform vec4 sediment_detail_tint : source_color = vec4(0.52, 0.43, 0.32, 0.22);
uniform vec4 seam_detail_tint : source_color = vec4(0.18, 0.26, 0.27, 0.24);
uniform vec4 entrance_frame_detail_tint : source_color = vec4(0.46, 0.53, 0.51, 0.16);

float painterly_variation(vec2 world_locked_uv) {
	float long_brush = sin(dot(world_locked_uv, vec2(79.0, 43.0)) + sin(world_locked_uv.y * 31.0) * 0.7);
	float cross_brush = sin(dot(world_locked_uv, vec2(-37.0, 67.0)) + 1.7);
	return clamp(0.84 + long_brush * 0.08 + cross_brush * 0.08, 0.68, 1.0);
}

vec3 apply_surface_detail(vec3 base_color, vec2 detail_uv, vec2 world_locked_uv) {
	vec3 detail = clamp(texture(surface_detail_mask, detail_uv).rgb, vec3(0.0), vec3(1.0));
	float brush = painterly_variation(world_locked_uv);
	float luminance = dot(base_color, vec3(0.2126, 0.7152, 0.0722));
	float tint_value = mix(0.55, 1.10, clamp(luminance, 0.0, 1.0));
	vec3 result = base_color;
	result = mix(
		result,
		sediment_detail_tint.rgb * tint_value,
		detail.r * sediment_detail_tint.a * brush
	);
	result = mix(
		result,
		seam_detail_tint.rgb * tint_value,
		detail.g * seam_detail_tint.a * (0.92 + (1.0 - brush) * 0.08)
	);
	result = mix(
		result,
		entrance_frame_detail_tint.rgb * tint_value,
		detail.b * entrance_frame_detail_tint.a * (0.90 + brush * 0.10)
	);
	return result;
}

void fragment() {
	vec4 sampled_color = texture(TEXTURE, UV);
	vec2 local_position = local_rect_origin + UV * local_rect_size;
	vec2 mask_uv = local_position / structure_size;
	float clip_alpha = texture(clip_mask, mask_uv).r;
	vec3 detailed_color = sampled_color.rgb;
	if (detail_enabled) {
		vec2 world_locked_uv = (world_rect_origin + UV * local_rect_size) / world_size;
		detailed_color = apply_surface_detail(detailed_color, mask_uv, world_locked_uv);
	}
	float canonical_alpha = sampled_color.a * clip_alpha;
	COLOR = vec4(detailed_color, canonical_alpha);
}
