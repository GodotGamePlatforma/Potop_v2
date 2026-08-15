shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform float anim_time = 0.0;
uniform float depth_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float effect_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float refraction_strength : hint_range(0.0, 0.01) = 0.0015;
uniform float grain_strength : hint_range(0.0, 0.04) = 0.008;
uniform vec2 flow_vector = vec2(0.0);
uniform vec2 world_anchor = vec2(0.0);
uniform vec4 region_color : source_color = vec4(0.035, 0.20, 0.26, 1.0);
uniform vec4 accent_color : source_color = vec4(0.18, 0.75, 0.80, 1.0);
uniform float water_clarity : hint_range(0.0, 1.0) = 0.7;
uniform float suspended_particle_density : hint_range(0.0, 1.0) = 0.35;
uniform float caustics_strength : hint_range(0.0, 1.0) = 0.35;
uniform float quality_level : hint_range(0.0, 2.0) = 2.0;
uniform float bloom_strength : hint_range(0.0, 0.2) = 0.055;
uniform float chromatic_aberration : hint_range(0.0, 0.003) = 0.0004;


float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32);
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


void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 normalized_flow = flow_vector;
	float flow_length = length(normalized_flow);
	if (flow_length > 0.0001) {
		normalized_flow /= flow_length;
	}

	float first_wave = sin((uv.y * 12.0 + uv.x * 3.0) + anim_time * 0.42);
	float second_wave = cos((uv.x * 15.0 - uv.y * 5.0) - anim_time * 0.34);
	vec2 wave_offset = vec2(first_wave, second_wave) * refraction_strength;
	wave_offset += normalized_flow * min(flow_length, 1.0) * refraction_strength * 0.75;
	vec2 refracted_uv = clamp(uv + wave_offset, vec2(0.001), vec2(0.999));
	vec3 source = texture(screen_texture, refracted_uv).rgb;
	if (quality_level > 0.5 && chromatic_aberration > 0.0) {
		vec2 spectral_axis = normalize(vec2(0.86, 0.51) + normalized_flow * 0.18);
		vec2 spectral_offset = spectral_axis * chromatic_aberration;
		source.r = texture(screen_texture, clamp(refracted_uv + spectral_offset, vec2(0.001), vec2(0.999))).r;
		source.b = texture(screen_texture, clamp(refracted_uv - spectral_offset, vec2(0.001), vec2(0.999))).b;
	}

	vec2 centered = uv * 2.0 - 1.0;
	float focus_field = 1.0 - smoothstep(0.035, 0.34, dot(centered, centered));
	float haze_density = mix(1.08, 0.64, water_clarity) * mix(0.78, 1.24, suspended_particle_density);
	float depth_fog = mix(0.014, 0.105, depth_ratio) * haze_density * effect_intensity;
	vec2 fog_anchor = world_anchor / vec2(1420.0, 1180.0);
	float fog_variation = value_noise(uv * vec2(7.0, 4.0) + fog_anchor + vec2(anim_time * 0.018, -anim_time * 0.011));
	float fog_amount = clamp(depth_fog * mix(0.84, 1.16, fog_variation), 0.0, 0.17);
	vec3 graded = mix(source, region_color.rgb, fog_amount);
	graded *= mix(vec3(1.0), vec3(0.86, 0.93, 0.96), depth_ratio * 0.16 * effect_intensity);

	vec2 caustic_uv = uv * vec2(118.0, 72.0) + world_anchor / 86.0;
	float caustic_a = sin(caustic_uv.x + caustic_uv.y * 0.34 + anim_time * 0.30);
	float caustic_b = sin(caustic_uv.x * -0.58 + caustic_uv.y * 0.92 - anim_time * 0.25);
	float caustic = pow(max(0.0, caustic_a * caustic_b), 7.0);
	caustic *= smoothstep(0.42, 0.74, value_noise(caustic_uv * 0.11 + anim_time * 0.009));
	graded += accent_color.rgb * caustic * mix(0.010, 0.002, depth_ratio) * caustics_strength * effect_intensity;

	if (quality_level > 0.5 && bloom_strength > 0.0) {
		float bloom_lod = mix(2.0, 3.1, step(1.5, quality_level));
		vec3 blurred = textureLod(screen_texture, refracted_uv, bloom_lod).rgb;
		float blurred_luminance = dot(blurred, vec3(0.2126, 0.7152, 0.0722));
		float highlight_mask = smoothstep(0.42, 0.84, blurred_luminance);
		vec3 bloom_color = max(blurred - vec3(0.28), vec3(0.0));
		graded += bloom_color * highlight_mask * bloom_strength * effect_intensity;
	}

	float vignette = 1.0 - smoothstep(0.34, 1.18, dot(centered, centered));
	graded *= mix(0.985, 1.0, vignette);
	graded *= 1.0 + focus_field * mix(0.006, 0.025, depth_ratio);
	vec2 screen_pixel = floor(uv / max(SCREEN_PIXEL_SIZE, vec2(0.000001)));
	float grain = hash21(screen_pixel + floor(anim_time * 18.0)) - 0.5;
	graded += grain * grain_strength * effect_intensity * mix(1.0, 0.58, focus_field);
	COLOR = vec4(clamp(graded, vec3(0.0), vec3(1.0)), 1.0);
}
