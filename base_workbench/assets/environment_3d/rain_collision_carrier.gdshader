shader_type particles;

// Ballistic rain carrier for Forward+. Godot's stock AT_COLLISION subemitter
// forwards the post-collision transform without resolving penetration or
// orienting the child to the receiver. This shader emits exactly one child at
// the reconstructed hit point with its Y axis aligned to the collision normal.

uniform vec3 emission_box_extents = vec3(1.0);
uniform vec3 direction = vec3(0.0, -1.0, 0.0);
uniform float spread_degrees : hint_range(0.0, 45.0) = 3.0;
uniform float initial_velocity_min = 5.8;
uniform float initial_velocity_max = 9.4;
uniform float scale_min = 0.58;
uniform float scale_max = 1.22;
uniform float impact_emission_probability : hint_range(0.0, 1.0) = 0.30;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D color_ramp : source_color, filter_linear, repeat_disable;
uniform sampler2D color_initial_ramp : source_color, filter_linear, repeat_disable;
uniform float collision_base_size : hint_range(0.0, 0.25) = 0.08;
uniform float impact_surface_bias : hint_range(0.0, 0.05) = 0.008;
uniform vec3 impact_camera_position = vec3(0.0, 31.5, 48.0);


float random_float(inout uint state) {
	state = state * 1664525u + 1013904223u;
	return float(state & 0x00ffffffu) / 16777215.0;
}


vec3 safe_direction(vec3 value, vec3 fallback) {
	float length_squared = dot(value, value);
	return length_squared > 0.000001 ? value * inversesqrt(length_squared) : fallback;
}


vec3 random_cone_direction(vec3 axis_value, float spread_radians, inout uint state) {
	vec3 axis = safe_direction(axis_value, vec3(0.0, -1.0, 0.0));
	vec3 helper = abs(axis.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(helper, axis));
	vec3 bitangent = normalize(cross(axis, tangent));
	float angle = spread_radians * sqrt(random_float(state));
	float azimuth = TAU * random_float(state);
	vec3 radial = tangent * cos(azimuth) + bitangent * sin(azimuth);
	return normalize(axis * cos(angle) + radial * sin(angle));
}


void start() {
	uint state = RANDOM_SEED ^ (NUMBER * 747796405u + 2891336453u);
	vec3 local_position = vec3(
		mix(-emission_box_extents.x, emission_box_extents.x, random_float(state)),
		mix(-emission_box_extents.y, emission_box_extents.y, random_float(state)),
		mix(-emission_box_extents.z, emission_box_extents.z, random_float(state))
	);
	float speed = mix(initial_velocity_min, initial_velocity_max, random_float(state));
	vec3 local_velocity_direction = random_cone_direction(
		direction,
		spread_degrees * PI / 180.0,
		state
	);
	float spawn_scale = mix(scale_min, scale_max, random_float(state));
	float initial_color_coordinate = random_float(state);
	float impact_sample = random_float(state);

	if (RESTART_POSITION) {
		TRANSFORM[3] = EMISSION_TRANSFORM * vec4(local_position, 1.0);
	}
	if (RESTART_ROT_SCALE) {
		TRANSFORM[0] = vec4(EMISSION_TRANSFORM[0].xyz * spawn_scale, 0.0);
		TRANSFORM[1] = vec4(EMISSION_TRANSFORM[1].xyz * spawn_scale, 0.0);
		TRANSFORM[2] = vec4(EMISSION_TRANSFORM[2].xyz * spawn_scale, 0.0);
	}
	if (RESTART_VELOCITY) {
		VELOCITY = mat3(EMISSION_TRANSFORM) * (local_velocity_direction * speed);
	}
	if (RESTART_CUSTOM) {
		// x stays zero so a future material cannot reinterpret it as a particle
		// billboard angle; scale already lives in the TRANSFORM basis columns.
		// y = normalized age, z = initial-ramp coordinate,
		// w = stable hero-impact sample retained for the whole flight.
		CUSTOM = vec4(0.0, 0.0, initial_color_coordinate, impact_sample);
	}
	if (RESTART_COLOR) {
		COLOR = base_color
			* texture(color_initial_ramp, vec2(CUSTOM.z, 0.5))
			* texture(color_ramp, vec2(0.0, 0.5));
	}
}


void process() {
	if (COLLIDED) {
		vec3 surface_normal = safe_direction(COLLISION_NORMAL, vec3(0.0, 1.0, 0.0));
		// HeightField collision resolves the carrier centre after testing a point
		// lowered by collision_base_size. Undo that vertical carrier radius before
		// applying the tiny normal bias used only to prevent surface z-fighting.
		vec3 resolved_carrier_center = TRANSFORM[3].xyz
			+ surface_normal * COLLISION_DEPTH;
		vec3 hit_position = resolved_carrier_center
			- vec3(0.0, max(collision_base_size, 0.0), 0.0)
			+ surface_normal * impact_surface_bias;
		vec3 camera_tangent = impact_camera_position - hit_position;
		camera_tangent -= surface_normal * dot(camera_tangent, surface_normal);
		vec3 fallback_forward = abs(surface_normal.y) < 0.999
			? cross(vec3(0.0, 1.0, 0.0), surface_normal)
			: vec3(0.0, 0.0, 1.0);
		vec3 forward = safe_direction(camera_tangent, safe_direction(fallback_forward, vec3(0.0, 0.0, 1.0)));
		vec3 right = safe_direction(cross(surface_normal, forward), vec3(1.0, 0.0, 0.0));
		forward = safe_direction(cross(right, surface_normal), forward);

		mat4 impact_transform = mat4(1.0);
		impact_transform[0].xyz = right;
		impact_transform[1].xyz = surface_normal;
		impact_transform[2].xyz = forward;
		impact_transform[3].xyz = hit_position;

		// Every carrier stops at the receiver, but rendering a large crown/ring for
		// every physical collision creates an implausible polka-dot carpet. The
		// deterministic sample keeps only representative large-drop impacts; the
		// ocean shader carries the much denser statistical micro-ripple layer.
		if (CUSTOM.w <= clamp(impact_emission_probability, 0.0, 1.0)) {
			emit_subparticle(
				impact_transform,
				vec3(0.0),
				vec4(1.0),
				vec4(0.0),
				FLAG_EMIT_POSITION | FLAG_EMIT_ROT_SCALE
			);
		}
		ACTIVE = false;
	} else {
		// The renderer integrates TRANSFORM from VELOCITY before process(). Only
		// optical age and color need explicit per-frame work here.
		CUSTOM.y = min(CUSTOM.y + DELTA / max(LIFETIME, 0.0001), 1.0);
		COLOR = base_color
			* texture(color_initial_ramp, vec2(CUSTOM.z, 0.5))
			* texture(color_ramp, vec2(CUSTOM.y, 0.5));
	}
}
