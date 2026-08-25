shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float anim_time = 0.0;
uniform bool reduced_motion = false;
uniform float quality_level : hint_range(0.0, 2.0) = 2.0;
uniform float intensity : hint_range(0.0, 0.4) = 0.10;
uniform vec2 flow_vector = vec2(0.0);
uniform vec2 world_anchor = vec2(0.0);
uniform vec4 region_color : source_color = vec4(0.035, 0.20, 0.26, 1.0);
uniform vec4 accent_color : source_color = vec4(0.18, 0.75, 0.80, 1.0);
uniform float depth_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float water_clarity : hint_range(0.0, 1.0) = 0.7;
uniform float suspended_particle_density : hint_range(0.0, 1.0) = 0.35;


float hash21(vec2 point) {
	point = fract(point * vec2(127.1, 311.7));
	point += dot(point, point + 34.5);
	return fract(point.x * point.y);
}


float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}


float soft_beam(vec2 uv, float source_x, float slope, float width) {
	float axis = source_x + (uv.y + 0.12) * slope;
	float distance_to_axis = abs(uv.x - axis);
	return 1.0 - smoothstep(width * 0.34, width, distance_to_axis);
}


void fragment() {
	float time_value = reduced_motion ? 0.0 : anim_time;
	vec2 drift = flow_vector * time_value * 0.010;
	vec2 sample_uv = UV + drift;
	float breakup_a = value_noise(sample_uv * vec2(5.2, 3.4) + world_anchor / 1150.0 + vec2(time_value * 0.018, -time_value * 0.010));
	float breakup_b = value_noise(sample_uv * vec2(11.7, 6.8) - world_anchor / 1730.0 + vec2(-time_value * 0.009, time_value * 0.014));
	float breakup = mix(breakup_a, breakup_b, 0.36);

	float beams = soft_beam(UV, 0.40, 0.12, 0.19);
	if (quality_level > 0.5) {
		beams += soft_beam(UV, 0.66, -0.18, 0.14) * 0.78;
	}
	if (quality_level > 1.5) {
		beams += soft_beam(UV, 0.18, 0.27, 0.10) * 0.52;
	}
	beams *= 1.0 - smoothstep(0.08, 0.90, UV.y);
	beams *= smoothstep(0.18, 0.56, breakup);

	float haze = smoothstep(0.48, 0.83, breakup_a) * smoothstep(0.04, 0.44, UV.y);
	haze *= 1.0 - smoothstep(0.70, 1.0, UV.y);
	float depth_visibility = mix(1.0, 0.28, smoothstep(0.10, 0.92, depth_ratio));
	float clarity_visibility = mix(0.66, 1.0, water_clarity);
	float density_visibility = mix(1.0, 0.78, suspended_particle_density);
	float field = clamp(beams * 0.82 + haze * 0.20, 0.0, 1.0)
		* intensity * depth_visibility * clarity_visibility * density_visibility;
	vec3 cool_water = mix(region_color.rgb, vec3(0.22, 0.63, 0.76), 0.72);
	vec3 shaft_color = mix(cool_water, accent_color.rgb, 0.14);
	COLOR = vec4(shaft_color, field);
}
