extends Node

const DiverScene := preload("res://diver_workbench/runtime/Diver.tscn")
const DiverSocketProfileScript := preload("res://diver_workbench/definitions/DiverSocketProfile.gd")
const DiverFrameEnvelopeScript := preload("res://diver_workbench/definitions/DiverFrameEnvelope.gd")
const SocketProfile := preload("res://diver_workbench/assets/profiles/diver_socket_profile.tres")
const EnvelopeProfile := preload("res://diver_workbench/assets/profiles/diver_frame_envelope_profile.tres")
const ActiveSpriteFrames := preload("res://diver_workbench/assets/animation/diver_sprite_frames.tres")
const APPROVED_ENVELOPE := Vector2(105.0, 60.0)
const APPROVED_SOURCE_UNION := Rect2(-188, -99, 428, 204)
const APPROVED_WORLD_ALPHA_SIZE := Vector2(102.292, 48.756)
const APPROVED_SPRITE_SCALE := Vector2(0.239, 0.239)
const PREVIOUS_AUTHORED_SPRITE_SCALE := 0.34
const MINIMUM_LOCOMOTION_FIT_RATIO := 0.984
const MAXIMUM_LOCOMOTION_GUARD_OFFSET := 3.0
const MINIMUM_CUE_FIT_RATIO := 0.95
const MINIMUM_AUTHORED_FRAME_WORLD_SIZE := Vector2(92.0, 38.0)
const MINIMUM_CELL_PADDING := 10
const BODY_CONTINUITY_REGION := Rect2i(330, 36, 154, 106)
const REAR_FIN_REGION := Rect2i(0, 0, 220, 256)
const FIN_ALPHA_THRESHOLD := 32
const MINIMUM_FIN_COMPONENT_AREA := 1200
const ANIMATION_SOURCES := {
	&"idle": "res://diver_workbench/assets/animation/diver_idle_16f.png",
	&"swim": "res://diver_workbench/assets/animation/diver_swim_16f.png",
	&"sprint": "res://diver_workbench/assets/animation/diver_sprint_16f.png",
}

var _failures: Array[String] = []


func _ready() -> void:
	_test_socket_resource_contract()
	_test_sprite_frame_atlas_contract()
	_test_frame_envelope_contract()
	_test_animation_timing_contract()
	_test_pre_ready_quality_bridge()
	await _test_runtime_presentation_contract()
	if _failures.is_empty():
		print("DIVER PRESENTATION TEST PASS")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _test_socket_resource_contract() -> void:
	_check(SocketProfile != null, "Diver socket profile should load.")
	if SocketProfile == null:
		return
	var errors: PackedStringArray = SocketProfile.validation_errors()
	_check(errors.is_empty(), "Diver socket profile should validate: %s" % errors)
	var sample_count := 0
	for animation_name: StringName in DiverSocketProfileScript.REQUIRED_ANIMATIONS:
		for socket_id: StringName in DiverSocketProfileScript.REQUIRED_SOCKETS:
			for frame in range(SocketProfile.frame_count):
				var right: Vector2 = SocketProfile.position_for(animation_name, socket_id, frame, false)
				var left: Vector2 = SocketProfile.position_for(animation_name, socket_id, frame, true)
				_check(left.is_equal_approx(Vector2(-right.x, right.y)), "Socket %s/%s/%d should mirror only X." % [animation_name, socket_id, frame])
				sample_count += 1
	_check(sample_count == 288, "Diver socket profile should expose exactly 288 authored samples.")


func _test_sprite_frame_atlas_contract() -> void:
	for animation_name: StringName in ANIMATION_SOURCES:
		_check(ActiveSpriteFrames.get_frame_count(animation_name) == 16, "%s atlas should expose all 16 frames." % animation_name)
		for frame in range(16):
			var texture := ActiveSpriteFrames.get_frame_texture(animation_name, frame) as AtlasTexture
			_check(texture != null, "%s frame %d should be an AtlasTexture." % [animation_name, frame])
			if texture == null:
				continue
			var expected_region := Rect2(
				Vector2((frame % 4) * 512, (frame / 4) * 256),
				Vector2(DiverFrameEnvelopeScript.FRAME_SIZE)
			)
			_check(texture.region == expected_region, "%s frame %d should map to its exact 4 x 4 atlas cell." % [animation_name, frame])
			_check(texture.atlas != null and texture.atlas.resource_path == ANIMATION_SOURCES[animation_name], "%s frame %d should use the approved source sheet." % [animation_name, frame])


func _test_frame_envelope_contract() -> void:
	var profile_errors: PackedStringArray = DiverFrameEnvelopeScript.validation_errors()
	_check(profile_errors.is_empty(), "Diver frame envelope should validate: %s" % profile_errors)
	_check(EnvelopeProfile != null, "The active diver frame-envelope profile should load.")
	if EnvelopeProfile != null:
		var resource_errors: PackedStringArray = EnvelopeProfile.validation_errors()
		_check(resource_errors.is_empty(), "The active diver frame-envelope profile should validate: %s" % resource_errors)
	var measured_union := Rect2()
	var has_union := false
	var measured_count := 0
	var minimum_world_size := Vector2(INF, INF)
	var source_images := {}
	for animation_name: StringName in ANIMATION_SOURCES:
		var image := Image.new()
		var image_error := image.load(ProjectSettings.globalize_path(ANIMATION_SOURCES[animation_name]))
		_check(image_error == OK, "The %s source sheet should load for alpha-envelope validation." % animation_name)
		if image_error != OK:
			continue
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		source_images[animation_name] = image
		_check(image.get_size() == Vector2i(2048, 1024), "%s should retain the authored 4 x 4 sheet dimensions." % animation_name)
		for frame in range(16):
			var frame_origin := Vector2i(
				(frame % 4) * DiverFrameEnvelopeScript.FRAME_SIZE.x,
				(frame / 4) * DiverFrameEnvelopeScript.FRAME_SIZE.y
			)
			var frame_image := image.get_region(Rect2i(frame_origin, DiverFrameEnvelopeScript.FRAME_SIZE))
			var used_rect := frame_image.get_used_rect()
			var measured := Rect2(
				Vector2(used_rect.position - DiverFrameEnvelopeScript.FRAME_SIZE / 2),
				Vector2(used_rect.size)
			)
			var expected: Rect2 = DiverFrameEnvelopeScript.bounds_for(animation_name, frame)
			_check(measured == expected, "%s frame %d alpha bounds should match the validated runtime profile: %s != %s." % [animation_name, frame, measured, expected])
			_check(
				used_rect.position.x >= MINIMUM_CELL_PADDING
					and used_rect.position.y >= MINIMUM_CELL_PADDING
					and DiverFrameEnvelopeScript.FRAME_SIZE.x - used_rect.end.x >= MINIMUM_CELL_PADDING
					and DiverFrameEnvelopeScript.FRAME_SIZE.y - used_rect.end.y >= MINIMUM_CELL_PADDING,
				"%s frame %d should retain at least %d transparent pixels on every atlas-cell edge." % [animation_name, frame, MINIMUM_CELL_PADDING]
			)
			for alpha_threshold: int in [1, 8]:
				var component_areas := _alpha_component_areas(frame_image, alpha_threshold)
				_check(component_areas.size() == 1, "%s frame %d should contain one connected alpha silhouette at threshold %d, got %s." % [animation_name, frame, alpha_threshold, component_areas])
			for fin_socket: StringName in [&"fin_upper", &"fin_lower"]:
				var authored_fin: Vector2 = SocketProfile.position_for(animation_name, fin_socket, frame, false)
				_check(_has_alpha_near(frame_image, authored_fin, 14, 16), "%s/%s frame %d should remain attached to visible fin geometry." % [animation_name, fin_socket, frame])
			minimum_world_size = minimum_world_size.min(measured.size * EnvelopeProfile.authored_sprite_scale)
			measured_union = measured if not has_union else measured_union.merge(measured)
			has_union = true
			measured_count += 1
	_check(measured_count == 48, "The alpha-envelope gate should inspect all 48 authored frames.")
	_check(measured_union == APPROVED_SOURCE_UNION, "The measured 48-frame source union should match the independently reviewed raster authority.")
	_check(DiverFrameEnvelopeScript.SOURCE_UNION == APPROVED_SOURCE_UNION, "Runtime alpha-envelope data should publish the independently reviewed source union.")
	var base_world_size: Vector2 = measured_union.size * EnvelopeProfile.authored_sprite_scale
	_check(EnvelopeProfile.target_size.is_equal_approx(APPROVED_ENVELOPE), "The active presentation profile should publish the approved 105 x 60 envelope.")
	_check(EnvelopeProfile.authored_sprite_scale.is_equal_approx(APPROVED_SPRITE_SCALE), "The active presentation profile should publish the reviewed 0.239 visual scale.")
	_check(base_world_size.is_equal_approx(APPROVED_WORLD_ALPHA_SIZE), "The authored alpha union should retarget to the reviewed 102.292 x 48.756 world units.")
	_check(base_world_size.x <= EnvelopeProfile.target_size.x and base_world_size.y <= EnvelopeProfile.target_size.y, "Every authored frame must fit the 105 x 60 visual target before presentation motion.")
	_check(minimum_world_size.x >= MINIMUM_AUTHORED_FRAME_WORLD_SIZE.x and minimum_world_size.y >= MINIMUM_AUTHORED_FRAME_WORLD_SIZE.y, "Every authored frame must preserve the approved minimum world-space silhouette; measured minimum is %s." % minimum_world_size)
	var guarded_world_size: Vector2 = measured_union.grow(DiverFrameEnvelopeScript.READABILITY_RIM_SOURCE_PADDING).size * EnvelopeProfile.authored_sprite_scale
	_check(guarded_world_size.x <= EnvelopeProfile.target_size.x and guarded_world_size.y <= EnvelopeProfile.target_size.y, "The authored alpha union plus readability-rim padding must fit the 105 x 60 world envelope.")
	_test_body_and_frame_continuity(source_images)
	_test_raster_fin_motion(source_images)


func _alpha_component_areas(image: Image, minimum_alpha: int) -> PackedInt32Array:
	var rgba: Image = image.duplicate()
	if rgba.get_format() != Image.FORMAT_RGBA8:
		rgba.convert(Image.FORMAT_RGBA8)
	var width: int = rgba.get_width()
	var height: int = rgba.get_height()
	var pixels: PackedByteArray = rgba.get_data()
	var visited := PackedByteArray()
	visited.resize(width * height)
	var areas := PackedInt32Array()
	var queue := PackedInt32Array()
	for start in range(width * height):
		if visited[start] != 0 or int(pixels[start * 4 + 3]) < minimum_alpha:
			continue
		visited[start] = 1
		queue.clear()
		queue.append(start)
		var head: int = 0
		var area: int = 0
		while head < queue.size():
			var current: int = queue[head]
			head += 1
			area += 1
			var x: int = current % width
			var y: int = current / width
			if x > 0:
				_alpha_enqueue(current - 1, minimum_alpha, pixels, visited, queue)
			if x + 1 < width:
				_alpha_enqueue(current + 1, minimum_alpha, pixels, visited, queue)
			if y > 0:
				_alpha_enqueue(current - width, minimum_alpha, pixels, visited, queue)
			if y + 1 < height:
				_alpha_enqueue(current + width, minimum_alpha, pixels, visited, queue)
		areas.append(area)
	return areas


func _alpha_enqueue(pixel_index: int, minimum_alpha: int, pixels: PackedByteArray, visited: PackedByteArray, queue: PackedInt32Array) -> void:
	if visited[pixel_index] != 0:
		return
	visited[pixel_index] = 1
	if int(pixels[pixel_index * 4 + 3]) >= minimum_alpha:
		queue.append(pixel_index)


func _has_alpha_near(image: Image, centered_point: Vector2, radius: int, minimum_alpha: int) -> bool:
	var center := Vector2i(
		roundi(centered_point.x + float(DiverFrameEnvelopeScript.FRAME_SIZE.x) * 0.5),
		roundi(centered_point.y + float(DiverFrameEnvelopeScript.FRAME_SIZE.y) * 0.5)
	)
	for y in range(maxi(0, center.y - radius), mini(image.get_height(), center.y + radius + 1)):
		for x in range(maxi(0, center.x - radius), mini(image.get_width(), center.x + radius + 1)):
			if image.get_pixel(x, y).a * 255.0 >= float(minimum_alpha):
				return true
	return false


func _test_body_and_frame_continuity(source_images: Dictionary) -> void:
	var full_limits := {&"idle": 0.18, &"swim": 0.24, &"sprint": 0.28}
	for animation_name: StringName in ANIMATION_SOURCES:
		var sheet := source_images.get(animation_name) as Image
		if sheet == null:
			continue
		var frames: Array[Image] = []
		for frame in range(16):
			var origin := Vector2i((frame % 4) * 512, (frame / 4) * 256)
			frames.append(sheet.get_region(Rect2i(origin, DiverFrameEnvelopeScript.FRAME_SIZE)))
		var neighbor_max := 0.0
		var body_max := 0.0
		for frame in range(15):
			neighbor_max = maxf(neighbor_max, _premultiplied_rmse(frames[frame], frames[frame + 1], Rect2i(Vector2i.ZERO, DiverFrameEnvelopeScript.FRAME_SIZE)))
			body_max = maxf(body_max, _premultiplied_rmse(frames[frame], frames[frame + 1], BODY_CONTINUITY_REGION))
		var seam_delta := _premultiplied_rmse(frames[15], frames[0], Rect2i(Vector2i.ZERO, DiverFrameEnvelopeScript.FRAME_SIZE))
		body_max = maxf(body_max, _premultiplied_rmse(frames[15], frames[0], BODY_CONTINUITY_REGION))
		_check(neighbor_max <= float(full_limits[animation_name]), "%s adjacent-frame delta %.4f should stay below its reviewed continuity limit." % [animation_name, neighbor_max])
		_check(seam_delta <= neighbor_max * 1.20 + 0.01, "%s frame 15 -> 0 seam %.4f should not exceed the authored neighbor cadence %.4f." % [animation_name, seam_delta, neighbor_max])
		_check(body_max <= 0.13, "%s helmet/tank/upper-body continuity should stay stable; measured %.4f." % [animation_name, body_max])


func _premultiplied_rmse(first: Image, second: Image, region: Rect2i) -> float:
	var squared_sum := 0.0
	var sample_count := 0
	for y in range(region.position.y, region.end.y, 2):
		for x in range(region.position.x, region.end.x, 2):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			var pa := Vector4(a.r * a.a, a.g * a.a, a.b * a.a, a.a)
			var pb := Vector4(b.r * b.a, b.g * b.a, b.b * b.a, b.a)
			squared_sum += (pa - pb).length_squared()
			sample_count += 1
	return sqrt(squared_sum / maxf(float(sample_count) * 4.0, 1.0))


func _test_raster_fin_motion(source_images: Dictionary) -> void:
	var separation_ranges := {}
	for animation_name: StringName in [&"idle", &"swim", &"sprint"]:
		var upper := SocketProfile.points_for(animation_name, &"fin_upper")
		var lower := SocketProfile.points_for(animation_name, &"fin_lower")
		var separations: Array[float] = []
		for frame in range(16):
			separations.append(absf(lower[frame].y - upper[frame].y))
		separation_ranges[animation_name] = _float_series_range(separations)
	_check(float(separation_ranges[&"swim"]) >= float(separation_ranges[&"idle"]) + 20.0, "Swim must expose a materially wider raster-aligned kick range than idle.")
	_check(float(separation_ranges[&"sprint"]) >= float(separation_ranges[&"swim"]) + 25.0, "Sprint must expose a materially wider raster-aligned kick range than swim.")

	var extreme_frames := {&"swim": [0, 3], &"sprint": [4, 12]}
	var minimum_extreme_separation := {&"swim": 45.0, &"sprint": 65.0}
	for animation_name: StringName in extreme_frames:
		var sheet := source_images.get(animation_name) as Image
		if sheet == null:
			continue
		for frame: int in extreme_frames[animation_name]:
			var origin := Vector2i((frame % 4) * 512, (frame / 4) * 256)
			var frame_image := sheet.get_region(Rect2i(origin, DiverFrameEnvelopeScript.FRAME_SIZE))
			var components := _alpha_components_in_region(frame_image, REAR_FIN_REGION, FIN_ALPHA_THRESHOLD, MINIMUM_FIN_COMPONENT_AREA)
			_check(components.size() >= 2, "%s frame %d should expose two substantial rear fin masses in the raster, got %s." % [animation_name, frame, components])
			if components.size() < 2:
				continue
			var upper_centroid: Vector2 = components[0]["centroid"]
			var lower_centroid: Vector2 = components[-1]["centroid"]
			_check(lower_centroid.y - upper_centroid.y >= float(minimum_extreme_separation[animation_name]), "%s frame %d should show a readable two-fin vertical separation." % [animation_name, frame])
			for socket_id: StringName in [&"fin_upper", &"fin_lower"]:
				var socket_pixel := SocketProfile.position_for(animation_name, socket_id, frame, false) + Vector2(DiverFrameEnvelopeScript.FRAME_SIZE) * 0.5
				var nearest := INF
				for component: Dictionary in components:
					nearest = minf(nearest, socket_pixel.distance_to(component["centroid"] as Vector2))
				_check(nearest <= 38.0, "%s/%s frame %d should independently remain near a substantial raster fin mass." % [animation_name, socket_id, frame])


func _float_series_range(values: Array[float]) -> float:
	var minimum := INF
	var maximum := -INF
	for value in values:
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	return maximum - minimum


func _alpha_components_in_region(image: Image, region: Rect2i, minimum_alpha: int, minimum_area: int) -> Array[Dictionary]:
	var rgba: Image = image.duplicate()
	if rgba.get_format() != Image.FORMAT_RGBA8:
		rgba.convert(Image.FORMAT_RGBA8)
	var pixels: PackedByteArray = rgba.get_data()
	var image_width: int = rgba.get_width()
	var visited := PackedByteArray()
	visited.resize(region.size.x * region.size.y)
	var queue := PackedInt32Array()
	var components: Array[Dictionary] = []
	for start in range(region.size.x * region.size.y):
		if visited[start] != 0:
			continue
		var local_x: int = start % region.size.x
		var local_y: int = start / region.size.x
		var image_index: int = (region.position.y + local_y) * image_width + region.position.x + local_x
		visited[start] = 1
		if int(pixels[image_index * 4 + 3]) < minimum_alpha:
			continue
		queue.clear()
		queue.append(start)
		var head: int = 0
		var area: int = 0
		var coordinate_sum := Vector2.ZERO
		while head < queue.size():
			var current: int = queue[head]
			head += 1
			var x: int = current % region.size.x
			var y: int = current / region.size.x
			area += 1
			coordinate_sum += Vector2(region.position.x + x, region.position.y + y)
			if x > 0:
				_region_alpha_enqueue(current - 1, region, image_width, minimum_alpha, pixels, visited, queue)
			if x + 1 < region.size.x:
				_region_alpha_enqueue(current + 1, region, image_width, minimum_alpha, pixels, visited, queue)
			if y > 0:
				_region_alpha_enqueue(current - region.size.x, region, image_width, minimum_alpha, pixels, visited, queue)
			if y + 1 < region.size.y:
				_region_alpha_enqueue(current + region.size.x, region, image_width, minimum_alpha, pixels, visited, queue)
		if area >= minimum_area:
			components.append({"area": area, "centroid": coordinate_sum / float(area)})
	components.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["centroid"] as Vector2).y < (b["centroid"] as Vector2).y)
	return components


func _region_alpha_enqueue(local_index: int, region: Rect2i, image_width: int, minimum_alpha: int, pixels: PackedByteArray, visited: PackedByteArray, queue: PackedInt32Array) -> void:
	if visited[local_index] != 0:
		return
	visited[local_index] = 1
	var local_x: int = local_index % region.size.x
	var local_y: int = local_index / region.size.x
	var image_index: int = (region.position.y + local_y) * image_width + region.position.x + local_x
	if int(pixels[image_index * 4 + 3]) >= minimum_alpha:
		queue.append(local_index)


func _test_animation_timing_contract() -> void:
	var expected_durations := {
		&"idle": 2.0,
		&"swim": 1.0,
		&"sprint": 0.8,
	}
	for animation_name: StringName in expected_durations:
		var frame_count := ActiveSpriteFrames.get_frame_count(animation_name)
		_check(frame_count == 16, "%s should retain the reviewed 16-frame cycle." % animation_name)
		_check(ActiveSpriteFrames.get_animation_loop(animation_name), "%s should remain a seamless looping clip." % animation_name)
		var duration_weight := 0.0
		for frame in range(frame_count):
			duration_weight += ActiveSpriteFrames.get_frame_duration(animation_name, frame)
		var duration_seconds := duration_weight / ActiveSpriteFrames.get_animation_speed(animation_name)
		_check(is_equal_approx(duration_seconds, float(expected_durations[animation_name])), "%s should last %.2f seconds, got %.4f." % [animation_name, expected_durations[animation_name], duration_seconds])
	for animation_name: StringName in [&"swim", &"sprint"]:
		var upper := SocketProfile.points_for(animation_name, &"fin_upper")
		var lower := SocketProfile.points_for(animation_name, &"fin_lower")
		var minimum_separation := INF
		var maximum_separation := 0.0
		for frame in range(SocketProfile.frame_count):
			var separation := absf(lower[frame].y - upper[frame].y)
			minimum_separation = minf(minimum_separation, separation)
			maximum_separation = maxf(maximum_separation, separation)
		_check(minimum_separation >= 10.0, "%s upper/lower fin sockets must remain separated in every frame." % animation_name)
		_check(maximum_separation - minimum_separation >= 20.0, "%s upper/lower fin socket separation must vary across the cycle." % animation_name)


func _test_pre_ready_quality_bridge() -> void:
	var diver := DiverScene.instantiate()
	_check(diver.scale.is_equal_approx(Vector2.ONE), "The CharacterBody2D root must remain unscaled.")
	_check(EnvelopeProfile.authored_sprite_scale.is_equal_approx(APPROVED_SPRITE_SCALE), "The active profile should own the 0.239 authored retarget scale before ready.")
	_check(EnvelopeProfile.authored_sprite_position.is_equal_approx(Vector2(-6.214, -0.717)), "The active profile should own the reviewed raster centering before ready.")
	_check(diver.frame_envelope_profile == EnvelopeProfile, "The scene should bind the single active frame-envelope profile.")
	diver.seed_presentation_settings_before_ready("low", true)
	var visual_effects := diver.get_node_or_null("VisualEffects")
	_check(visual_effects != null, "The local Diver scene should accept presentation settings before ready.")
	if visual_effects != null:
		var state: Dictionary = visual_effects.graphics_quality_state()
		_check(state.get("quality") == "low", "Cold-start graphics profile should reach diver VFX before allocation.")
		_check(state.get("reduced_motion") == true, "Cold-start reduced-motion setting should reach diver VFX before allocation.")
	diver.free()


func _test_runtime_presentation_contract() -> void:
	var diver := DiverScene.instantiate()
	var visual_effects := diver.get_node("VisualEffects")
	diver.set_graphics_quality("low")
	diver.set_reduced_motion(true)
	add_child(diver)
	await get_tree().process_frame

	var low_reduced: Dictionary = visual_effects.graphics_quality_state()
	_check(low_reduced.get("emitter_count") == 6, "Diver should allocate the six contextual presentation emitters.")
	_check(low_reduced.get("bubble_count") == 3, "Cold-start low/reduced should allocate the reduced bubble budget directly.")
	_check(low_reduced.get("wake_upper_count") == 1 and low_reduced.get("wake_lower_count") == 1, "Cold-start low/reduced should allocate one wake particle per fin.")
	_check(low_reduced.get("leak_count") == 1 and low_reduced.get("tool_count") == 1, "Cold-start low/reduced should allocate reduced contextual budgets.")

	diver.set_graphics_quality("high")
	diver.set_reduced_motion(false)
	var high: Dictionary = visual_effects.graphics_quality_state()
	_check(high.get("bubble_count") == 10, "High profile should expose the authored breath budget.")
	_check(high.get("wake_count") == 16, "High profile should split the authored wake budget across both fins.")
	_check(high.get("leak_count") == 6 and high.get("tool_count") == 6 and high.get("cue_count") == 10, "High profile should expose all contextual VFX budgets.")
	_check(float(high.get("bubble_lifetime", 99.0)) < 1.05, "A sprint breath pulse should finish before the next authored breath interval instead of restarting live particles.")
	_check(is_equal_approx(
		float(high.get("visual_retarget_scale", 0.0)),
		APPROVED_SPRITE_SCALE.x / PREVIOUS_AUTHORED_SPRITE_SCALE
	), "Diver VFX dimensions should follow the same visual retarget ratio as the sprite.")

	var sprite := diver.get_node("AnimatedSprite2D") as AnimatedSprite2D
	diver.reset_at(diver.global_position)
	_check(sprite.scale.is_equal_approx(EnvelopeProfile.authored_sprite_scale), "Runtime ready should apply the active authored scale only to the visual branch.")
	_check(sprite.position.is_equal_approx(EnvelopeProfile.authored_sprite_position), "Runtime ready should center the reviewed raster union from the active profile.")
	var breath := diver.get_node("AnimatedSprite2D/BreathSocket") as Marker2D
	sprite.play(&"swim")
	sprite.pause()
	sprite.set_frame_and_progress(5, 0.0)
	sprite.flip_h = false
	diver._update_socket_markers()
	var authored: Vector2 = SocketProfile.position_for(&"swim", &"breath", 5, false)
	_check(breath.position.is_equal_approx(authored), "Runtime breath socket should use the discrete authored sample for the visible frame.")
	sprite.flip_h = true
	diver._update_socket_markers()
	_check(breath.position.is_equal_approx(Vector2(-authored.x, authored.y)), "Runtime sockets should mirror with the diver facing direction.")
	_test_runtime_visual_envelope(diver, sprite)

	var dive_light := diver.get_node("DiveLight") as PointLight2D
	_check(diver.light_source() == dive_light, "The public light boundary should resolve the local authored light without exposing its path to root.")
	_check(diver.get_node_or_null("LanternCone") == null, "The avatar must not add a directional lantern cone beside the canonical radial light.")
	var authored_lights := diver.find_children("*", "PointLight2D", true, false)
	_check(authored_lights.size() == 1 and authored_lights[0] == dive_light, "The avatar should author exactly one PointLight2D.")
	diver.configure_camera_world_bounds(Vector2(23040.0, 12960.0))
	var diver_camera := diver.get_node("Camera2D") as Camera2D
	_check(diver_camera.limit_right == 23040 and diver_camera.limit_bottom == 12960, "The public camera boundary should apply root-provided world bounds.")
	_check(diver.visual_camera_anchor().is_finite(), "The public camera boundary should always return a finite presentation anchor.")
	sprite.flip_h = false
	diver._update_socket_markers()
	diver._update_light_mount()
	_check(dive_light.position.is_zero_approx() and dive_light.global_position.is_equal_approx(diver.global_position), "The radial light must be centered on the physical diver root, not on the visual lamp socket.")
	dive_light.enabled = true
	dive_light.texture_scale = 2.75
	dive_light.energy = 1.1
	dive_light.color = Color(0.76, 0.92, 1.0, 1.0)
	var radial_scale := dive_light.texture_scale
	var radial_energy := dive_light.energy
	var radial_color := dive_light.color
	diver.set_lantern_presentation(true, Color(0.72, 0.9, 1.0, 1.0), 350.0, 1.0)
	_check(dive_light.position.is_zero_approx() and is_equal_approx(dive_light.texture_scale, radial_scale), "The compatibility presentation seam must not replace the root-configured radial rig.")
	sprite.flip_h = true
	diver._update_socket_markers()
	diver._update_light_mount()
	_check(dive_light.position.is_zero_approx() and dive_light.global_position.is_equal_approx(diver.global_position), "Facing left must not move or mirror a radial light.")
	diver.rotation = 0.73
	diver._update_light_mount()
	_check(dive_light.position.is_zero_approx() and dive_light.global_position.is_equal_approx(diver.global_position), "Diver rotation must preserve the central radial origin.")
	diver.set_reduced_motion(true)
	_check(dive_light.position.is_zero_approx(), "Reduced motion must not offset the radial light.")
	_check(is_equal_approx(dive_light.texture_scale, radial_scale) and is_equal_approx(dive_light.energy, radial_energy) and dive_light.color.is_equal_approx(radial_color), "Presentation settings must not change root-owned lantern range, energy or color.")
	diver.set_lantern_presentation(false, Color.WHITE, 350.0, 0.0)
	_check(dive_light.enabled and is_equal_approx(dive_light.texture_scale, radial_scale), "The avatar compatibility seam must not override the root-owned on/off state or radius.")
	diver.rotation = 0.0

	var wake_upper := visual_effects.get_node("WakeEmitterUpper") as GPUParticles2D
	var wake_lower := visual_effects.get_node("WakeEmitterLower") as GPUParticles2D
	diver.velocity = Vector2(90.0, 0.0)
	diver._current_velocity = Vector2(90.0, 0.0)
	visual_effects._update_wake()
	_check(not wake_upper.emitting and not wake_lower.emitting, "Passive current drift should not create fin propulsion wakes.")
	diver.velocity = Vector2(120.0, 0.0)
	diver._current_velocity = Vector2(20.0, 0.0)
	sprite.play(&"swim")
	sprite.pause()
	diver._set_animation_phase(sprite, 0.25)
	visual_effects._update_wake()
	_check(wake_upper.emitting and wake_lower.emitting, "Water-relative propulsion should create wakes at both fin sockets.")
	var upper_push_ratio := wake_upper.amount_ratio
	var lower_recovery_ratio := wake_lower.amount_ratio
	diver._set_animation_phase(sprite, 0.75)
	visual_effects._update_wake()
	_check(upper_push_ratio > lower_recovery_ratio, "The first half-cycle should emphasize the upper-fin propulsion wake.")
	_check(wake_lower.amount_ratio > wake_upper.amount_ratio, "The opposite half-cycle should transfer propulsion emphasis to the lower fin.")

	diver.set_visual_context(0.8, &"repair", 0.5, true)
	visual_effects._update_leak()
	visual_effects._update_tool()
	var leak := visual_effects.get_node("LeakEmitter") as GPUParticles2D
	var tool := visual_effects.get_node("ToolEmitter") as GPUParticles2D
	_check(leak.emitting and tool.emitting, "Leak and successful-work contexts should remain distinct, readable signals.")
	_check(leak.global_position.is_equal_approx(diver.visual_socket_global(&"leak_valve")), "Leak VFX should follow the authored tank-valve socket.")
	_check(tool.global_position.is_equal_approx(diver.visual_socket_global(&"tool_hand")), "Tool VFX should follow the authored hand socket.")

	var root_position: Vector2 = diver.position
	var body_shape := (diver.get_node("CollisionShape2D") as CollisionShape2D).shape
	var interaction_shape := (diver.get_node("InteractionRange/CollisionShape2D") as CollisionShape2D).shape
	var capsule := body_shape as CapsuleShape2D
	_check(Vector2(capsule.height, capsule.radius * 2.0).is_equal_approx(APPROVED_ENVELOPE), "The gameplay capsule AABB must independently match the approved 105 x 60 contract.")
	diver.play_visual_cue(&"repair", diver.global_position + Vector2(80.0, -20.0), 1.0)
	diver._update_presentation_pose(0.08)
	_check(diver.position.is_equal_approx(root_position), "Presentation cues must never move the CharacterBody2D root.")
	_check((diver.get_node("CollisionShape2D") as CollisionShape2D).shape == body_shape, "Presentation cues must not replace or resize the gameplay collider.")
	_check((diver.get_node("InteractionRange/CollisionShape2D") as CollisionShape2D).shape == interaction_shape, "Presentation cues must not replace the interaction shape.")

	diver.set_visual_context(0.0, &"", 0.0, false)
	diver._clear_visual_cue()
	visual_effects.reset_presentation()
	var cleared: Dictionary = diver.presentation_state()
	_check(is_zero_approx(float(cleared.get("leak_intensity", -1.0))), "Clearing presentation context should stop the leak signal.")
	_check(cleared.get("interaction_action") == &"" and cleared.get("is_towing") == false, "Clearing presentation context should not leave stale action state.")
	for emitter_name: String in ["BreathEmitter", "WakeEmitterUpper", "WakeEmitterLower", "LeakEmitter", "ToolEmitter", "CueEmitter"]:
		_check(not (visual_effects.get_node(emitter_name) as GPUParticles2D).emitting, "Presentation reset should stop and clear %s." % emitter_name)
	_test_directional_motion_contract(diver, sprite)
	await _test_physical_contact_contract(diver)
	diver.queue_free()


func _test_directional_motion_contract(diver: DiverController, sprite: AnimatedSprite2D) -> void:
	var directions := PackedVector2Array([
		Vector2.RIGHT,
		Vector2(1.0, 1.0).normalized(),
		Vector2.DOWN,
		Vector2(-1.0, 1.0).normalized(),
		Vector2.LEFT,
		Vector2(-1.0, -1.0).normalized(),
		Vector2.UP,
		Vector2(1.0, -1.0).normalized(),
	])
	for direction in directions:
		diver.reset_at(Vector2.ZERO)
		for _step in range(24):
			diver.simulate_motion_tick(direction, false, Vector2.ZERO, 1.0, 1.0 / 60.0, true)
		var visual_forward := _visual_forward(diver, sprite)
		_check(visual_forward.dot(direction) >= 0.985, "The diver visual should face its commanded eight-way direction: %s versus %s." % [visual_forward, direction])
		_check(sprite.animation == &"swim", "Eight-way movement should select the swim clip.")
		if absf(direction.x) > 0.05:
			_check(sprite.flip_h == (direction.x < 0.0), "Horizontal facing should mirror the sprite without mirroring the physical root scale.")
		_check(diver.scale.is_equal_approx(Vector2.ONE), "Eight-way steering must keep the CharacterBody2D root unscaled.")
	_test_continuous_turn_sweeps(diver, sprite)
	diver.reset_at(Vector2.ZERO)
	sprite.play(&"swim")
	sprite.pause()
	diver._set_animation_phase(sprite, 0.375)
	var swim_phase := diver._animation_phase(sprite)
	diver._switch_animation_preserving_phase(&"sprint", false)
	var sprint_phase := diver._animation_phase(sprite)
	_check(absf(swim_phase - sprint_phase) <= 0.001, "Swim-to-sprint transition should preserve normalized kick phase.")
	diver._switch_animation_preserving_phase(&"idle", false)
	var idle_phase := diver._animation_phase(sprite)
	_check(absf(sprint_phase - idle_phase) <= 0.001, "Sprint-to-idle transition should preserve normalized kick phase.")
	diver.reset_at(Vector2.ZERO)


func _test_continuous_turn_sweeps(diver: DiverController, sprite: AnimatedSprite2D) -> void:
	_run_turn_sweep(diver, sprite, 72, 109, 1, "downward right-to-left")
	_run_turn_sweep(diver, sprite, 108, 71, -1, "downward left-to-right")
	_run_turn_sweep(diver, sprite, -108, -71, 1, "upward left-to-right")
	_run_turn_sweep(diver, sprite, -72, -109, -1, "upward right-to-left")


func _run_turn_sweep(diver: DiverController, sprite: AnimatedSprite2D, start_degrees: int, end_degrees: int, step_degrees: int, label: String) -> void:
	diver.reset_at(Vector2.ZERO)
	var first_direction := Vector2.from_angle(deg_to_rad(float(start_degrees)))
	for _settle in range(48):
		diver.simulate_motion_tick(first_direction, false, Vector2.ZERO, 1.0, 1.0 / 60.0, true)
	var previous_forward := _visual_forward(diver, sprite)
	for degrees in range(start_degrees, end_degrees, step_degrees):
		var command := Vector2.from_angle(deg_to_rad(float(degrees)))
		diver.simulate_motion_tick(command, false, Vector2.ZERO, 1.0, 1.0 / 60.0, true)
		var current_forward := _visual_forward(diver, sprite)
		_check(current_forward.dot(command) >= 0.985, "%s turn sweep should keep the visible diver aligned at %d degrees." % [label, degrees])
		_check(previous_forward.dot(current_forward) >= 0.95, "%s turn sweep should not reverse the visible heading when flip_h changes at %d degrees." % [label, degrees])
		_check(diver.scale.is_equal_approx(Vector2.ONE), "%s turn sweep must keep the physical root unscaled." % label)
		previous_forward = current_forward


func _visual_forward(diver: DiverController, sprite: AnimatedSprite2D) -> Vector2:
	return (Vector2.LEFT if sprite.flip_h else Vector2.RIGHT).rotated(diver.rotation)


func _test_runtime_visual_envelope(diver: DiverController, sprite: AnimatedSprite2D) -> void:
	var half_target: Vector2 = EnvelopeProfile.target_size * 0.5
	for animation_name: StringName in [&"idle", &"swim", &"sprint"]:
		for frame in range(16):
			for flip_h: bool in [false, true]:
				sprite.play(animation_name)
				sprite.pause()
				sprite.flip_h = flip_h
				sprite.set_frame_and_progress(frame, 0.0)
				diver._update_presentation_pose(0.0)
				var visual_bounds: Rect2 = diver._current_visual_alpha_bounds()
				var intended_scale: Vector2 = diver._visual_base_scale * diver._visual_pose_scale
				var intended_position: Vector2 = diver._authored_visual_position(sprite) + diver._visual_pose_offset
				var locomotion_fit_ratio := minf(
					sprite.scale.x / maxf(intended_scale.x, 0.001),
					sprite.scale.y / maxf(intended_scale.y, 0.001)
				)
				_check(locomotion_fit_ratio >= MINIMUM_LOCOMOTION_FIT_RATIO, "%s frame %d rendered-alpha guard must preserve at least %.1f%% of the intended locomotion scale (ratio %.4f)." % [animation_name, frame, MINIMUM_LOCOMOTION_FIT_RATIO * 100.0, locomotion_fit_ratio])
				var guard_offset := sprite.position.distance_to(intended_position)
				_check(guard_offset <= MAXIMUM_LOCOMOTION_GUARD_OFFSET, "%s frame %d rendered-alpha guard must remain within %.2f world units of the intended position (measured %.3f)." % [animation_name, frame, MAXIMUM_LOCOMOTION_GUARD_OFFSET, guard_offset])
				_check(visual_bounds.position.x >= -half_target.x - 0.01, "%s frame %d should stay behind the rear collider plane when facing %s." % [animation_name, frame, "left" if flip_h else "right"])
				_check(visual_bounds.end.x <= half_target.x + 0.01, "%s frame %d should stay behind the front collider plane when facing %s." % [animation_name, frame, "left" if flip_h else "right"])
				_check(visual_bounds.position.y >= -half_target.y - 0.01 and visual_bounds.end.y <= half_target.y + 0.01, "%s frame %d should remain inside the vertical collider envelope." % [animation_name, frame])
	for cue: StringName in [&"knife_attack", &"harpoon_attack", &"repair", &"interaction", &"hit"]:
		for flip_h: bool in [false, true]:
			sprite.play(&"swim")
			sprite.pause()
			sprite.flip_h = flip_h
			sprite.set_frame_and_progress(0, 0.0)
			var direction := Vector2.LEFT if flip_h else Vector2.RIGHT
			diver.play_visual_cue(cue, diver.global_position + direction * 80.0 + Vector2.UP * 20.0, 1.5)
			diver._cue_elapsed = diver._cue_duration * 0.5
			diver._update_presentation_pose(0.0)
			var cue_bounds: Rect2 = diver._current_visual_alpha_bounds()
			var cue_intended_scale: Vector2 = diver._visual_base_scale * diver._visual_pose_scale
			var cue_fit_ratio := minf(
				sprite.scale.x / maxf(cue_intended_scale.x, 0.001),
				sprite.scale.y / maxf(cue_intended_scale.y, 0.001)
			)
			_check(cue_fit_ratio >= MINIMUM_CUE_FIT_RATIO, "%s cue rendered-alpha guard must preserve at least %.1f%% of the intended scale (ratio %.4f)." % [cue, MINIMUM_CUE_FIT_RATIO * 100.0, cue_fit_ratio])
			_check(cue_bounds.position.x >= -half_target.x - 0.01 and cue_bounds.end.x <= half_target.x + 0.01, "%s cue should keep visible alpha inside the horizontal envelope." % cue)
			_check(cue_bounds.position.y >= -half_target.y - 0.01 and cue_bounds.end.y <= half_target.y + 0.01, "%s cue should keep visible alpha inside the vertical envelope." % cue)
			diver._clear_visual_cue()
	diver.set_visual_context(0.0, &"repair", 0.55, true)
	diver._update_presentation_pose(0.0)
	var contextual_bounds: Rect2 = diver._current_visual_alpha_bounds()
	_check(contextual_bounds.position.x >= -half_target.x - 0.01 and contextual_bounds.end.x <= half_target.x + 0.01, "Towing and interaction pose should preserve the horizontal envelope.")
	_check(contextual_bounds.position.y >= -half_target.y - 0.01 and contextual_bounds.end.y <= half_target.y + 0.01, "Towing and interaction pose should preserve the vertical envelope.")
	diver.set_visual_context(0.0, &"", 0.0, false)
	diver.reset_at(diver.global_position)


func _test_physical_contact_contract(diver: DiverController) -> void:
	diver.set_physics_process(false)
	var body_collision := diver.get_node("CollisionShape2D") as CollisionShape2D
	var body_shape := body_collision.shape as CapsuleShape2D
	var interaction_shape := (diver.get_node("InteractionRange/CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
	_check(is_equal_approx(body_shape.radius, 30.0) and is_equal_approx(body_shape.height, 105.0), "Wall-contact QA must use the approved 105 x 60 capsule.")
	_check(is_equal_approx(interaction_shape.radius, 112.0), "Wall-contact QA must not alter InteractionRange.")

	var vertical_wall := _create_test_wall("VerticalWall", Vector2(100.0, 0.0), Vector2(10.0, 240.0))
	await get_tree().physics_frame
	diver.reset_at(Vector2.ZERO)
	await get_tree().physics_frame
	var vertical_collision := false
	for _step in range(120):
		var result: Dictionary = diver.simulate_motion_tick(Vector2.RIGHT, false, Vector2.ZERO, 1.0, 1.0 / 60.0, true)
		vertical_collision = vertical_collision or bool(result["collided"])
		if vertical_collision:
			break
	_check(vertical_collision, "The real CharacterBody2D should collide with a vertical StaticBody2D wall.")
	_check(diver.global_position.x + body_shape.height * 0.5 <= 95.1, "The 105-unit horizontal capsule must stop before the vertical wall plane.")
	_check((diver.get_node("DiveLight") as PointLight2D).position.is_zero_approx(), "Wall contact must not move the central radial light.")
	vertical_wall.queue_free()
	await get_tree().physics_frame

	var horizontal_wall := _create_test_wall("HorizontalWall", Vector2(0.0, 100.0), Vector2(240.0, 10.0))
	await get_tree().physics_frame
	diver.reset_at(Vector2.ZERO)
	await get_tree().physics_frame
	var horizontal_collision := false
	for _step in range(120):
		var result: Dictionary = diver.simulate_motion_tick(Vector2.DOWN, false, Vector2.ZERO, 1.0, 1.0 / 60.0, true)
		horizontal_collision = horizontal_collision or bool(result["collided"])
		if horizontal_collision:
			break
	_check(horizontal_collision, "The real CharacterBody2D should collide with a horizontal StaticBody2D wall.")
	var vertical_support := body_shape.radius + (body_shape.height * 0.5 - body_shape.radius) * absf(sin(diver.rotation))
	_check(absf(angle_difference(diver.rotation, PI * 0.5)) <= 0.05, "Downward runtime movement should rotate the real diver root and capsule vertically.")
	_check(diver.global_position.y + vertical_support <= 95.1, "The rotated capsule must stop before the horizontal wall plane.")
	_check(body_collision.shape == body_shape and is_equal_approx(interaction_shape.radius, 112.0), "Both wall contacts must preserve collider and interaction resources.")
	horizontal_wall.queue_free()
	await get_tree().physics_frame


func _create_test_wall(wall_name: String, wall_position: Vector2, wall_size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.name = wall_name
	wall.position = wall_position
	var shape := RectangleShape2D.new()
	shape.size = wall_size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	return wall


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
