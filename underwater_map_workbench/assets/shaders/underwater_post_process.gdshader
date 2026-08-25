shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform float anim_time = 0.0;
uniform bool reduced_motion = false;
uniform float depth_ratio : hint_range(0.0, 1.0) = 0.0;
uniform float effect_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float refraction_pixels : hint_range(0.0, 2.0) = 0.75;
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
uniform float chromatic_aberration_pixels : hint_range(0.0, 1.0) = 0.22;
uniform float low_focus_recovery : hint_range(0.0, 0.5) = 0.0;


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


float interleaved_gradient_noise(vec2 pixel_position) {
	return fract(52.9829189 * fract(dot(pixel_position, vec2(0.06711056, 0.00583715))));
}


void fragment() {
	vec2 uv = SCREEN_UV;
	float motion_time = reduced_motion ? 0.0 : anim_time;
	vec2 normalized_flow = flow_vector;
	float flow_length = length(normalized_flow);
	if (flow_length > 0.0001) {
		normalized_flow /= flow_length;
	}

	float first_wave = sin((uv.y * 12.0 + uv.x * 3.0) + motion_time * 0.42);
	float second_wave = cos((uv.x * 15.0 - uv.y * 5.0) - motion_time * 0.34);
	vec2 refraction_texel = SCREEN_PIXEL_SIZE * refraction_pixels;
	vec2 wave_offset = vec2(first_wave, second_wave) * refraction_texel;
	wave_offset += normalized_flow * min(flow_length, 1.0) * refraction_texel * 0.75;
	vec2 refracted_uv = clamp(uv + wave_offset, vec2(0.001), vec2(0.999));
	// Preserve the full-resolution linework and move only the low-frequency
	// underwater light/color band. Visible refraction must not resample every
	// terrain edge through a fractional bilinear lookup.
	float refraction_lod = 2.35;
	vec3 source = texture(screen_texture, uv).rgb;
	vec3 source_low = textureLod(screen_texture, uv, refraction_lod).rgb;
	vec3 refracted_low = textureLod(screen_texture, refracted_uv, refraction_lod).rgb;
	if (quality_level > 1.5 && chromatic_aberration_pixels > 0.0 && !reduced_motion) {
		vec2 spectral_axis = normalize(vec2(0.86, 0.51) + normalized_flow * 0.18);
		vec2 spectral_offset = spectral_axis * SCREEN_PIXEL_SIZE * chromatic_aberration_pixels;
		refracted_low.r = textureLod(screen_texture, clamp(refracted_uv + spectral_offset, vec2(0.001), vec2(0.999)), refraction_lod).r;
		refracted_low.b = textureLod(screen_texture, clamp(refracted_uv - spectral_offset, vec2(0.001), vec2(0.999)), refraction_lod).b;
	}
	source += refracted_low - source_low;
	// The Low profile composites an upscaled V5 world plate. Recover a bounded
	// part of its final full-frame detail without adding another screen sample;
	// all reduced-motion and higher-quality profiles keep the source untouched.
	if (low_focus_recovery > 0.0 && !reduced_motion) {
		source += clamp(
			(source - source_low) * low_focus_recovery,
			vec3(-0.028),
			vec3(0.028)
		);
	}

	vec2 centered = uv * 2.0 - 1.0;
	float focus_field = 1.0 - smoothstep(0.035, 0.34, dot(centered, centered));
	float haze_density = mix(1.08, 0.64, water_clarity) * mix(0.78, 1.24, suspended_particle_density);
	float depth_fog = mix(0.014, 0.105, depth_ratio) * haze_density * effect_intensity;
	vec2 fog_anchor = world_anchor / vec2(1420.0, 1180.0);
	float fog_variation = value_noise(uv * vec2(7.0, 4.0) + fog_anchor + vec2(motion_time * 0.018, -motion_time * 0.011));
	float fog_amount = clamp(depth_fog * mix(0.84, 1.16, fog_variation), 0.0, 0.17);
	vec3 backscatter_color = mix(region_color.rgb, accent_color.rgb, 0.06 + water_clarity * 0.04);
	// The water shader is the sole owner of depth absorption. This pass only
	// adds in-scattered light, so it must never attenuate the source signal.
	vec3 graded = source + (vec3(1.0) - source) * backscatter_color * fog_amount;

	vec2 caustic_uv = uv * vec2(118.0, 72.0) + world_anchor / 86.0;
	float caustic_a = sin(caustic_uv.x + caustic_uv.y * 0.34 + motion_time * 0.30);
	float caustic_b = sin(caustic_uv.x * -0.58 + caustic_uv.y * 0.92 - motion_time * 0.25);
	float caustic = pow(max(0.0, caustic_a * caustic_b), 7.0);
	caustic *= smoothstep(0.42, 0.74, value_noise(caustic_uv * 0.11 + motion_time * 0.009));
	graded += accent_color.rgb * caustic * mix(0.010, 0.002, depth_ratio) * caustics_strength * effect_intensity;

	if (quality_level > 0.5 && bloom_strength > 0.0) {
		vec3 blurred = textureLod(screen_texture, refracted_uv, 2.35).rgb;
		if (quality_level > 1.5) {
			vec3 broad_bloom = textureLod(screen_texture, refracted_uv, 3.85).rgb;
			blurred = mix(blurred, broad_bloom, 0.34);
		}
		float blurred_luminance = dot(blurred, vec3(0.2126, 0.7152, 0.0722));
		float highlight_mask = smoothstep(0.42, 0.84, blurred_luminance);
		vec3 bloom_color = max(blurred - vec3(0.28), vec3(0.0));
		graded += bloom_color * highlight_mask * bloom_strength * effect_intensity;
	}

	float vignette = 1.0 - smoothstep(0.34, 1.18, dot(centered, centered));
	graded *= mix(0.985, 1.0, vignette);
	graded *= 1.0 + focus_field * mix(0.006, 0.025, depth_ratio);
	vec2 screen_pixel = floor(uv / max(SCREEN_PIXEL_SIZE, vec2(0.000001)));
	float dither_rate = mix(2.0, 4.0, step(1.5, quality_level));
	float dither_phase = reduced_motion || quality_level < 0.5 ? 0.0 : floor(motion_time * dither_rate);
	float grain = interleaved_gradient_noise(screen_pixel + vec2(dither_phase * 17.0, dither_phase * -11.0)) - 0.5;
	graded += grain * grain_strength * effect_intensity * mix(1.0, 0.58, focus_field);
	COLOR = vec4(clamp(graded, vec3(0.0), vec3(1.0)), 1.0);
}
