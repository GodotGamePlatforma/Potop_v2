shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float anim_time = 0.0;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.64;
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform vec2 rain_direction = vec2(0.20, 1.0);
uniform bool surface_pass = false;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	float aspect = max(viewport_size.x / max(viewport_size.y, 1.0), 1.0);
	vec2 p = vec2(UV.x * aspect, UV.y);
	float alpha = 0.0;
	vec3 color = vec3(0.52, 0.67, 0.70);

	if (surface_pass) {
		vec2 grid_uv = p * vec2(7.5, 7.0);
		vec2 cell = floor(grid_uv);
		vec2 local = fract(grid_uv);
		float seed = hash21(cell);
		vec2 center = vec2(0.18 + hash21(cell + 2.3) * 0.64, 0.18 + hash21(cell + 8.7) * 0.64);
		float age = fract(anim_time * (0.24 + seed * 0.13) + seed * 5.7);
		vec2 delta = (local - center) * vec2(1.0, aspect * 0.76);
		float radius = age * 0.255;
		float ring = 1.0 - smoothstep(0.008, 0.025, abs(length(delta) - radius));
		float angle = atan(delta.y, delta.x);
		float broken_arc = smoothstep(0.16, 0.72, 0.5 + 0.5 * sin(angle * 3.0 + seed * 12.7 + age * 3.8));
		float life = smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.58, 1.0, age));
		alpha = ring * life * mix(0.42, 1.0, broken_arc) * step(0.66, seed) * rain_intensity * 0.072;
		color = vec3(0.42, 0.62, 0.68);
	} else {
		vec2 fall = normalize(vec2(rain_direction.x * 0.58, max(abs(rain_direction.y), 0.62)));

		vec2 near_uv = p * vec2(31.0, 19.0);
		near_uv -= vec2(fall.x * 6.2, fall.y * 8.3) * anim_time;
		vec2 near_cell = floor(near_uv);
		vec2 near_local = fract(near_uv) - 0.5;
		float near_seed = hash21(near_cell);
		near_local.x -= near_local.y * fall.x * 0.72;
		float near_line = 1.0 - smoothstep(0.012, 0.043, abs(near_local.x - (near_seed - 0.5) * 0.62));
		float near_length = 1.0 - smoothstep(0.20, 0.52, abs(near_local.y + 0.04));
		float near_alpha = near_line * near_length * step(0.63, near_seed) * (0.11 + near_seed * 0.15);

		vec2 far_uv = p * vec2(47.0, 28.0) + vec2(13.7, 5.2);
		far_uv -= vec2(fall.x * 9.5, fall.y * 12.4) * anim_time;
		vec2 far_cell = floor(far_uv);
		vec2 far_local = fract(far_uv) - 0.5;
		float far_seed = hash21(far_cell + vec2(7.3, 19.1));
		far_local.x -= far_local.y * fall.x * 0.58;
		float far_line = 1.0 - smoothstep(0.009, 0.032, abs(far_local.x - (far_seed - 0.5) * 0.58));
		float far_length = 1.0 - smoothstep(0.13, 0.43, abs(far_local.y));
		float far_alpha = far_line * far_length * step(0.72, far_seed) * (0.055 + far_seed * 0.07);

		alpha = clamp(near_alpha + far_alpha, 0.0, 0.34) * rain_intensity;
		color = vec3(0.58, 0.69, 0.71);
	}

	COLOR = vec4(color, alpha);
}
