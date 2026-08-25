shader_type canvas_item;

uniform sampler2D topology_mask : filter_nearest, repeat_disable;
uniform sampler2D ground_texture : source_color, filter_linear, repeat_enable;
// The generated scene overrides this with world_rect.size / texture pixel_size,
// preserving exactly one source texel per world unit while repeating the material.
uniform vec2 texture_tiling = vec2(1.0);
uniform vec4 shallow_tint : source_color = vec4(0.66, 0.76, 0.78, 1.0);
uniform vec4 deep_tint : source_color = vec4(0.28, 0.39, 0.43, 1.0);
uniform float boundary_softness : hint_range(0.0, 0.49, 0.01) = 0.0;

float world_noise(vec2 position) {
	vec2 p = floor(position * vec2(47.0, 31.0));
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float mask_value = texture(topology_mask, UV).r;
	float solid_alpha = smoothstep(0.5 - boundary_softness, 0.5 + boundary_softness, mask_value);
	vec2 detail_uv = UV * texture_tiling;
	vec4 material_sample = texture(ground_texture, detail_uv);
	float depth_mix = clamp(UV.y, 0.0, 1.0);
	vec3 depth_tint = mix(shallow_tint.rgb, deep_tint.rgb, depth_mix);
	float broad_variation = mix(0.88, 1.08, world_noise(UV));
	COLOR = vec4(material_sample.rgb * depth_tint * broad_variation, material_sample.a * solid_alpha);
}
