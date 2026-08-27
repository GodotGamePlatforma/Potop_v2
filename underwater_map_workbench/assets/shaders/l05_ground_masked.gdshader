shader_type canvas_item;

uniform sampler2D topology_mask : filter_nearest, repeat_disable;
uniform sampler2D ground_texture : source_color, filter_linear, repeat_enable;
// Presentation-only RGBA data: R exposed edge/sediment, G owner seam and
// subordinate fixed anchors/cables, B generic entrance-frame wear. Alpha is
// reserved and never participates in clipping.
uniform sampler2D surface_detail_mask : filter_linear, repeat_disable;
// The generated scene overrides this with world_rect.size / texture pixel_size,
// preserving exactly one source texel per world unit while repeating the material.
uniform vec2 texture_tiling = vec2(1.0);
uniform vec4 shallow_tint : source_color = vec4(0.66, 0.76, 0.78, 1.0);
uniform vec4 deep_tint : source_color = vec4(0.28, 0.39, 0.43, 1.0);
// Tint alpha is the deliberately restrained contribution of each detail family.
// None of the three channels is emissive or communicates an interaction state.
uniform vec4 sediment_detail_tint : source_color = vec4(0.52, 0.43, 0.32, 0.22);
uniform vec4 seam_detail_tint : source_color = vec4(0.18, 0.26, 0.27, 0.24);
uniform vec4 entrance_frame_detail_tint : source_color = vec4(0.46, 0.53, 0.51, 0.16);
uniform float boundary_softness : hint_range(0.0, 0.49, 0.01) = 0.0;

float world_noise(vec2 position) {
	vec2 p = floor(position * vec2(47.0, 31.0));
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float painterly_variation(vec2 world_locked_uv) {
	float long_brush = sin(dot(world_locked_uv, vec2(79.0, 43.0)) + sin(world_locked_uv.y * 31.0) * 0.7);
	float cross_brush = sin(dot(world_locked_uv, vec2(-37.0, 67.0)) + 1.7);
	return clamp(0.84 + long_brush * 0.08 + cross_brush * 0.08, 0.68, 1.0);
}

vec3 apply_surface_detail(vec3 base_color, vec2 world_locked_uv) {
	vec3 detail = clamp(texture(surface_detail_mask, world_locked_uv).rgb, vec3(0.0), vec3(1.0));
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
	float mask_value = texture(topology_mask, UV).r;
	float solid_alpha = smoothstep(0.5 - boundary_softness, 0.5 + boundary_softness, mask_value);
	vec2 detail_uv = UV * texture_tiling;
	vec4 material_sample = texture(ground_texture, detail_uv);
	float depth_mix = clamp(UV.y, 0.0, 1.0);
	vec3 depth_tint = mix(shallow_tint.rgb, deep_tint.rgb, depth_mix);
	float broad_variation = mix(0.88, 1.08, world_noise(UV));
	vec3 base_color = material_sample.rgb * depth_tint * broad_variation;
	vec3 detailed_color = apply_surface_detail(base_color, UV);
	float canonical_alpha = material_sample.a * solid_alpha;
	COLOR = vec4(detailed_color, canonical_alpha);
}
