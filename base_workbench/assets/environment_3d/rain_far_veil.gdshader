shader_type canvas_item;
render_mode unshaded, blend_mix;

// This material is intended for a full-screen ColorRect placed above the
// BaseWorld3D texture, but below PlatformBoard and the HUD. It is only a quiet
// far-field cue; the 3D particles remain responsible for readable near rain.
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.52;
uniform vec2 screen_flow = vec2(0.0, 1.0);
uniform float time_offset = 0.0;
uniform float veil_opacity : hint_range(0.0, 1.0) = 0.58;
uniform int quality_level : hint_range(0, 2, 1) = 2;
uniform vec4 veil_color : source_color = vec4(0.62, 0.76, 0.78, 1.0);
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform vec2 platform_occlusion_center = vec2(0.5);
uniform vec2 platform_occlusion_half_size = vec2(0.0);

float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32);
	return fract(point.x * point.y);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);

	float lower_left = hash21(cell);
	float lower_right = hash21(cell + vec2(1.0, 0.0));
	float upper_left = hash21(cell + vec2(0.0, 1.0));
	float upper_right = hash21(cell + vec2(1.0, 1.0));
	return mix(
		mix(lower_left, lower_right, local.x),
		mix(upper_left, upper_right, local.x),
		local.y
	);
}

vec2 rain_flow_direction(vec2 projected_flow) {
	// BaseWorld3D projects its current gusted 3D terminal-velocity direction
	// through the real camera. This keeps the canvas veil aligned with near/mid
	// rain for every world-space wind direction instead of guessing from wind.x.
	vec2 flow = projected_flow;
	float length_squared = dot(flow, flow);
	if (length_squared < 0.0001) {
		return vec2(0.0, 1.0);
	}
	return flow * inversesqrt(length_squared);
}

float streak_layer(
	vec2 aspect_uv,
	vec2 flow,
	float time_value,
	vec2 grid_scale,
	float speed,
	float half_length,
	float density,
	float seed_offset
) {
	vec2 side = vec2(flow.y, -flow.x);
	vec2 aligned = vec2(dot(aspect_uv, side), dot(aspect_uv, flow));
	aligned.y -= time_value * speed;

	vec2 grid_position = aligned * grid_scale;
	vec2 cell = floor(grid_position);
	vec2 local = fract(grid_position) - 0.5;
	vec2 seeded_cell = cell + vec2(seed_offset, seed_offset * 1.731);

	float existence_seed = hash21(seeded_cell);
	float horizontal_seed = hash21(seeded_cell + vec2(17.17, 3.91));
	float vertical_seed = hash21(seeded_cell + vec2(5.73, 29.41));
	float brightness_seed = hash21(seeded_cell + vec2(37.11, 11.23));
	float length_seed = hash21(seeded_cell + vec2(61.73, 23.47));

	// Every segment fades well before its cell boundary. The random center and
	// gentle shear hide the grid without requiring texture samples.
	float horizontal_center = (horizontal_seed - 0.5) * 0.54;
	float vertical_center = (vertical_seed - 0.5) * 0.34;
	float shear = (brightness_seed - 0.5) * 0.16;
	float cross_distance = abs(local.x - horizontal_center - local.y * shear);
	float along_distance = abs(local.y - vertical_center);

	// The explicit viewport size keeps the thinnest veil from disappearing at lower
	// render resolutions while aspect_uv keeps cells square at every aspect.
	float pixel_in_cell = max(grid_scale.x / max(viewport_size.y, 1.0), 0.0001);
	float half_width = max(0.012, pixel_in_cell * 0.58);
	float width_feather = max(0.018, pixel_in_cell * 0.92);
	float line_mask = 1.0 - smoothstep(
		half_width,
		half_width + width_feather,
		cross_distance
	);
	// Exposure length varies per drop. A fixed length makes distant rain read as
	// a regular screen-space barcode, especially when the camera is static.
	float local_half_length = half_length * mix(0.58, 1.24, length_seed);
	float end_feather = min(local_half_length * 0.46, 0.065);
	float length_mask = 1.0 - smoothstep(
		max(local_half_length - end_feather, 0.001),
		local_half_length,
		along_distance
	);

	float exists = step(1.0 - density, existence_seed);
	float brightness = mix(0.54, 1.0, brightness_seed);
	return line_mask * length_mask * exists * brightness;
}

float aerial_veil(vec2 aspect_uv, vec2 flow, float time_value) {
	vec2 drift = flow * time_value * 0.030;
	float noise_value = value_noise(aspect_uv * vec2(2.4, 3.2) - drift);
	float weight = 1.0;

	if (quality_level >= 1) {
		float second_octave = value_noise(
			aspect_uv.yx * vec2(5.1, 4.2) + drift * vec2(0.63, -0.47) + vec2(9.7, 4.3)
		);
		noise_value += second_octave * 0.46;
		weight += 0.46;
	}
	if (quality_level >= 2) {
		float third_octave = value_noise(
			aspect_uv * vec2(9.4, 7.7) - drift * 1.36 + vec2(17.2, 12.8)
		);
		noise_value += third_octave * 0.20;
		weight += 0.20;
	}

	noise_value /= weight;
	// Only the denser lobes contribute. This preserves local depth variation
	// instead of laying a uniform grey film over the world.
	return smoothstep(0.46, 0.78, noise_value);
}

float platform_occlusion_mask(vec2 uv) {
	if (min(platform_occlusion_half_size.x, platform_occlusion_half_size.y) <= 0.001) {
		return 0.0;
	}
	vec2 distance_to_box = abs(uv - platform_occlusion_center) - platform_occlusion_half_size;
	float signed_distance = length(max(distance_to_box, vec2(0.0)))
		+ min(max(distance_to_box.x, distance_to_box.y), 0.0);
	// The broad canvas veil has no access to the isolated 3D viewport depth.
	// Fade it out over the projected platform silhouette so it cannot paint
	// distant streaks on top of roofs/deck. Collision-aware 3D rain remains.
	return 1.0 - smoothstep(-0.012, 0.018, signed_distance);
}

void fragment() {
	vec2 screen_size = max(viewport_size, vec2(1.0));
	float aspect_ratio = screen_size.x / max(screen_size.y, 1.0);
	vec2 aspect_uv = vec2(UV.x * aspect_ratio, UV.y);
	vec2 flow = rain_flow_direction(screen_flow);
	// BaseEnvironment advances this value from the same presentation clock as
	// the platform and ocean. Avoiding the global TIME uniform makes forced-time
	// snapshots bit-stable and pauses the veil together with the scene.
	float time_value = time_offset;
	float intensity = clamp(rain_intensity, 0.0, 1.0);
	float density_response = mix(0.38, 1.0, pow(intensity, 0.72));
	float speed_response = mix(0.94, 1.06, intensity);

	// Low renders one broad far layer. Medium and high add progressively finer,
	// lower-opacity layers; uniform branches skip their hashes/noise entirely.
	float streak_alpha = streak_layer(
		aspect_uv,
		flow,
		time_value,
		vec2(20.0, 12.5),
		2.05 * speed_response,
		0.150,
		0.20 * density_response,
		3.1
	) * 0.086;

	if (quality_level >= 1) {
		streak_alpha += streak_layer(
			aspect_uv,
			flow,
			time_value,
			vec2(31.0, 18.5),
			2.72 * speed_response,
			0.130,
			0.15 * density_response,
			19.7
		) * 0.055;
	}
	if (quality_level >= 2) {
		streak_alpha += streak_layer(
			aspect_uv,
			flow,
			time_value,
			vec2(45.0, 27.0),
			3.35 * speed_response,
			0.110,
			0.10 * density_response,
			41.3
		) * 0.035;
	}

	float aerial_alpha = aerial_veil(aspect_uv, flow, time_value) * 0.014;
	float weather_response = smoothstep(0.025, 1.0, intensity);
	float alpha = (streak_alpha + aerial_alpha) * weather_response;
	alpha *= clamp(veil_opacity, 0.0, 1.0) * veil_color.a;
	alpha *= mix(1.0, 0.06, platform_occlusion_mask(UV));

	// Even a fully driven storm cannot turn this secondary cue into an opaque
	// screen wash. Readability must still come from the world and near particles.
	alpha = min(alpha, 0.095);
	COLOR = vec4(veil_color.rgb, alpha);
}
