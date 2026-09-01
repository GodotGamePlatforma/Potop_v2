extends Node

const DiverScene := preload("res://diver_workbench/runtime/Diver.tscn")
const DiverSocketProfileScript := preload("res://diver_workbench/definitions/DiverSocketProfile.gd")
const DiverFrameEnvelopeScript := preload("res://diver_workbench/definitions/DiverFrameEnvelope.gd")
const DiverSuitPresentationProfileScript := preload("res://diver_workbench/definitions/DiverSuitPresentationProfile.gd")
const SocketProfile := preload("res://diver_workbench/assets/profiles/diver_socket_profile.tres")
const EnvelopeProfile := preload("res://diver_workbench/assets/profiles/diver_frame_envelope_profile.tres")
const SuitProfile := preload("res://diver_workbench/assets/profiles/diver_suit_presentation_profile.tres")
const ReadabilityShader := preload("res://diver_workbench/assets/shaders/diver_readability.gdshader")
const ActiveSpriteFrames := preload("res://diver_workbench/assets/animation/diver_sprite_frames.tres")
const ActionSpriteFrames := preload("res://diver_workbench/assets/animation/diver_action_sprite_frames.tres")
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
const TRANSITION_SOURCES := {
	&"transition_idle_swim": "res://diver_workbench/assets/animation/diver_transition_idle_swim_16f.png",
	&"transition_idle_sprint": "res://diver_workbench/assets/animation/diver_transition_idle_sprint_16f.png",
	&"transition_swim_sprint": "res://diver_workbench/assets/animation/diver_transition_swim_sprint_16f.png",
}
const TRANSITION_ENDPOINTS := {
	&"transition_idle_swim": [&"idle", 13, &"swim", 9],
	&"transition_idle_sprint": [&"idle", 7, &"sprint", 0],
	&"transition_swim_sprint": [&"swim", 11, &"sprint", 9],
}
const TRANSITION_ROUTES := [
	[&"idle", &"swim", &"transition_idle_swim", 0.30, 9],
	[&"swim", &"idle", &"transition_idle_swim", 0.36, 13],
	[&"idle", &"sprint", &"transition_idle_sprint", 0.28, 0],
	[&"sprint", &"idle", &"transition_idle_sprint", 0.40, 7],
	[&"swim", &"sprint", &"transition_swim_sprint", 0.28, 9],
	[&"sprint", &"swim", &"transition_swim_sprint", 0.32, 11],
]
const KNIFE_SOURCE := "res://diver_workbench/assets/animation/diver_knife_swing_16f.png"
const KNIFE_CONTACT_PROGRESS := 0.40
const CAMERA_TEST_ORIGIN := Vector2(4000.0, 3000.0)
const CAMERA_TICK_RATES := [30, 60, 120]

var _failures: Array[String] = []


func _ready() -> void:
	_test_socket_resource_contract()
	_test_sprite_frame_atlas_contract()
	_test_transition_asset_contract()
	_test_readability_shader_contract()
	_test_suit_profile_contract()
	_test_knife_asset_contract()
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
	var expected_samples := (
		DiverSocketProfileScript.REQUIRED_ANIMATIONS.size()
		* DiverSocketProfileScript.REQUIRED_SOCKETS.size()
		* SocketProfile.frame_count
	)
	_check(sample_count == expected_samples, "Diver socket profile should expose exactly %d authored samples." % expected_samples)


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


func _test_transition_asset_contract() -> void:
	for transition_name: StringName in TRANSITION_SOURCES:
		_check(ActiveSpriteFrames.get_frame_count(transition_name) == 16, "%s should expose 16 authored transition frames." % transition_name)
		_check(not ActiveSpriteFrames.get_animation_loop(transition_name), "%s must remain a one-shot transition clip." % transition_name)
		var source_path: String = TRANSITION_SOURCES[transition_name]
		var sheet := Image.new()
		var load_error := sheet.load(ProjectSettings.globalize_path(source_path))
		_check(load_error == OK, "%s source sheet should load." % transition_name)
		if load_error != OK:
			continue
		if sheet.get_format() != Image.FORMAT_RGBA8:
			sheet.convert(Image.FORMAT_RGBA8)
		_check(sheet.get_size() == Vector2i(2048, 1024), "%s should retain the 4 x 4 atlas dimensions." % transition_name)
		var previous_bounds := Rect2()
		for frame in range(16):
			var texture := ActiveSpriteFrames.get_frame_texture(transition_name, frame) as AtlasTexture
			_check(texture != null, "%s frame %d should be an AtlasTexture." % [transition_name, frame])
			if texture != null:
				var expected_region := Rect2(
					Vector2((frame % 4) * 512, (frame / 4) * 256),
					Vector2(DiverFrameEnvelopeScript.FRAME_SIZE)
				)
				_check(texture.region == expected_region, "%s frame %d should map to its exact atlas cell." % [transition_name, frame])
				_check(texture.atlas != null and texture.atlas.resource_path == source_path, "%s frame %d should use its reviewed transition sheet." % [transition_name, frame])
			var frame_image := _atlas_frame_image(sheet, frame)
			var used_rect := frame_image.get_used_rect()
			var measured := Rect2(
				Vector2(used_rect.position - DiverFrameEnvelopeScript.FRAME_SIZE / 2),
				Vector2(used_rect.size)
			)
			_check(measured == DiverFrameEnvelopeScript.bounds_for(transition_name, frame), "%s frame %d should match its measured alpha bounds." % [transition_name, frame])
			_check(_cell_has_padding(used_rect), "%s frame %d should keep transparent atlas padding." % [transition_name, frame])
			for alpha_threshold: int in [1, 8]:
				var components := _alpha_component_areas(frame_image, alpha_threshold)
				_check(components.size() == 1, "%s frame %d should contain one connected silhouette at alpha %d." % [transition_name, frame, alpha_threshold])
			for fin_socket: StringName in [&"fin_upper", &"fin_lower"]:
				var authored_fin: Vector2 = SocketProfile.position_for(transition_name, fin_socket, frame, false)
				_check(_has_alpha_near(frame_image, authored_fin, 14, 16), "%s/%s frame %d should stay attached to visible fin geometry." % [transition_name, fin_socket, frame])
			if frame > 0:
				var width_change := absf(measured.size.x - previous_bounds.size.x) / maxf(previous_bounds.size.x, 1.0)
				var height_change := absf(measured.size.y - previous_bounds.size.y) / maxf(previous_bounds.size.y, 1.0)
				_check(maxf(width_change, height_change) <= 0.18, "%s frame %d should not introduce a silhouette scale pop." % [transition_name, frame])
			previous_bounds = measured
		_test_transition_endpoints(transition_name, sheet)
		_check(_import_mipmaps_enabled(source_path), "%s must generate mipmaps for runtime minification." % transition_name)


func _test_transition_endpoints(transition_name: StringName, transition_sheet: Image) -> void:
	var endpoints: Array = TRANSITION_ENDPOINTS[transition_name]
	var source_animation: StringName = endpoints[0]
	var source_frame: int = endpoints[1]
	var target_animation: StringName = endpoints[2]
	var target_frame: int = endpoints[3]
	var source_sheet := Image.new()
	var target_sheet := Image.new()
	_check(source_sheet.load(ProjectSettings.globalize_path(ANIMATION_SOURCES[source_animation])) == OK, "%s source endpoint sheet should load." % transition_name)
	_check(target_sheet.load(ProjectSettings.globalize_path(ANIMATION_SOURCES[target_animation])) == OK, "%s target endpoint sheet should load." % transition_name)
	_check(_atlas_frame_image(transition_sheet, 0).get_data() == _atlas_frame_image(source_sheet, source_frame).get_data(), "%s frame 0 must exactly equal %s frame %d." % [transition_name, source_animation, source_frame])
	_check(_atlas_frame_image(transition_sheet, 15).get_data() == _atlas_frame_image(target_sheet, target_frame).get_data(), "%s frame 15 must exactly equal %s frame %d." % [transition_name, target_animation, target_frame])
	for socket_id: StringName in DiverSocketProfileScript.REQUIRED_SOCKETS:
		_check(SocketProfile.position_for(transition_name, socket_id, 0, false).is_equal_approx(SocketProfile.position_for(source_animation, socket_id, source_frame, false)), "%s/%s frame 0 socket must equal its source-loop anchor." % [transition_name, socket_id])
		_check(SocketProfile.position_for(transition_name, socket_id, 15, false).is_equal_approx(SocketProfile.position_for(target_animation, socket_id, target_frame, false)), "%s/%s frame 15 socket must equal its target-loop anchor." % [transition_name, socket_id])


func _test_suit_profile_contract() -> void:
	_check(SuitProfile != null, "The Diver suit presentation profile should load.")
	_check(SuitProfile.get_script() == DiverSuitPresentationProfileScript, "The suit resource should use the local presentation profile type.")
	if SuitProfile == null:
		return
	var errors: PackedStringArray = SuitProfile.validation_errors()
	_check(errors.is_empty(), "Diver suit presentation profile should validate: %s" % errors)
	var style_ids := {}
	for quality in range(1, 5):
		var style: Dictionary = SuitProfile.style_for(quality)
		style_ids[int(style["style_id"])] = true
		_check(float(style["outline_width"]) <= DiverFrameEnvelopeScript.READABILITY_RIM_SOURCE_PADDING - 0.5, "Suit Q%d outline must remain inside the reviewed rim allowance." % quality)
		_check(is_equal_approx(float(style["outline_width"]), 3.5), "Suit Q%d must retain the reviewed 3.5 px outline radius." % quality)
	_check(style_ids.size() == 4, "Suit qualities Q1..Q4 must use four distinct construction styles.")
	var baseline: Dictionary = SuitProfile.style_for(1)
	_check(
		float(baseline["fabric_mix"]) == 0.0
		and float(baseline["metal_mix"]) == 0.0
		and float(baseline["pattern_strength"]) == 0.0
		and float(baseline["plate_strength"]) == 0.0
		and float(baseline["emissive_strength"]) == 0.0,
		"Suit Q1 must reproduce the approved v4 appearance without recoloring or construction overlays."
	)
	var baseline_fabric: Color = baseline["fabric_color"]
	var baseline_metal: Color = baseline["metal_color"]
	var baseline_pattern: Color = baseline["pattern_color"]
	var baseline_rim: Color = baseline["rim_color"]
	_check(
		baseline_fabric.is_equal_approx(Color("263b48"))
		and baseline_metal.is_equal_approx(Color("876036"))
		and baseline_pattern.is_equal_approx(Color("4dc7d1"))
		and baseline_rim.is_equal_approx(Color("4dc7d1"))
		and is_equal_approx(float(baseline["accent_strength"]), 0.32),
		"Suit Q1 palette and accent data must remain the approved baseline."
	)
	var previous_treatment := 0.0
	var previous_style: Dictionary = {}
	for quality in range(2, 5):
		var current_style: Dictionary = SuitProfile.style_for(quality)
		var treatment := (
			float(current_style["fabric_mix"])
			+ float(current_style["metal_mix"])
			+ float(current_style["pattern_strength"])
			+ float(current_style["plate_strength"])
			+ float(current_style["emissive_strength"])
		)
		_check(treatment > previous_treatment, "Suit Q%d should increase the total presentation treatment over the previous upgrade." % quality)
		if not previous_style.is_empty():
			for scalar_key in ["fabric_mix", "metal_mix", "pattern_strength", "emissive_strength", "accent_strength"]:
				_check(float(current_style[scalar_key]) > float(previous_style[scalar_key]), "Suit Q%d %s should progress monotonically." % [quality, scalar_key])
		previous_treatment = treatment
		previous_style = current_style
	var sealed: Dictionary = SuitProfile.style_for(2)
	var pressure: Dictionary = SuitProfile.style_for(3)
	var abyss: Dictionary = SuitProfile.style_for(4)
	_check(float(sealed["fabric_mix"]) >= 0.55 and float(sealed["pattern_strength"]) >= 0.50, "Suit Q2 should establish a broad sealed-material mass at gameplay scale.")
	_check(float(pressure["fabric_mix"]) >= 0.65 and float(pressure["plate_strength"]) >= 0.70, "Suit Q3 should establish a broad pressure-shell mass at gameplay scale.")
	_check(float(abyss["fabric_mix"]) >= 0.75 and float(abyss["emissive_strength"]) >= 0.45, "Suit Q4 should establish a broad abyss fabric mass with the strongest emissive guide.")
	_check(float(sealed["pattern_strength"]) > 0.0, "Suit Q2 should add visible sealed construction bands.")
	_check(float(pressure["plate_strength"]) > float(abyss["plate_strength"]) and float(abyss["plate_strength"]) > float(sealed["plate_strength"]), "Suit Q3 should remain the strongest pressure-plating profile while Q4 retains more plating than Q2.")
	_check(float(abyss["emissive_strength"]) > float(pressure["emissive_strength"]), "Suit Q4 should add the strongest abyss piping signal.")
	_check(SuitProfile.normalized_quality(-10) == 1 and SuitProfile.normalized_quality(99) == 4, "Suit quality presentation should clamp to canonical levels 1..4.")


func _test_readability_shader_contract() -> void:
	_check(ReadabilityShader != null, "The Diver readability shader should load.")
	if ReadabilityShader == null:
		return
	var shader_code: String = ReadabilityShader.code
	_check(shader_code.count("texture(TEXTURE") == 9, "The readability shader should cache one base and eight neighbor texture samples instead of fetching alpha and luma separately.")
	_check("return vec3(source_luma);" in shader_code, "A black suit tint should fall back to neutral source luminance instead of crushing modeled volume.")
	_check(
		"float readability_polish = 0.0;" in shader_code
		and "float inner_rim_scale = 0.46;" in shader_code
		and "float outer_rim_scale = 0.62;" in shader_code,
		"The shader should retain an explicit legacy Q1 rim path before applying upgraded-suit polish."
	)
	_check("broad_panel_mask" in shader_code, "Upgraded suits should use a broad luminance-preserving material mass, not only thin edge accents.")
	_check("uniform float lantern_glint" in shader_code and "uniform vec4 lantern_color" in shader_code, "The existing lantern presentation seam should drive a material glint without another Light2D.")


func _test_knife_asset_contract() -> void:
	_check(ActionSpriteFrames != null, "The knife action SpriteFrames resource should load.")
	if ActionSpriteFrames == null:
		return
	_check(ActionSpriteFrames.get_frame_count(&"knife_swing") == 16, "Knife swing should expose 16 authored frames.")
	_check(not ActionSpriteFrames.get_animation_loop(&"knife_swing"), "Knife swing must remain a one-shot action clip.")
	var duration_weight := 0.0
	for frame in range(16):
		duration_weight += ActionSpriteFrames.get_frame_duration(&"knife_swing", frame)
	var duration := duration_weight / ActionSpriteFrames.get_animation_speed(&"knife_swing")
	_check(is_equal_approx(duration, 0.30), "Knife swing should retain the reviewed 0.30 second presentation duration.")
	var sheet := Image.new()
	var load_error := sheet.load(ProjectSettings.globalize_path(KNIFE_SOURCE))
	_check(load_error == OK, "The knife source sheet should load.")
	if load_error != OK:
		return
	if sheet.get_format() != Image.FORMAT_RGBA8:
		sheet.convert(Image.FORMAT_RGBA8)
	var previous_area := -1
	var unique_frames := {}
	for frame in range(16):
		var texture := ActionSpriteFrames.get_frame_texture(&"knife_swing", frame) as AtlasTexture
		_check(texture != null, "Knife frame %d should be an AtlasTexture." % frame)
		if texture != null:
			_check(texture.atlas != null and texture.atlas.resource_path == KNIFE_SOURCE, "Knife frame %d should use the approved action sheet." % frame)
			_check(texture.region == Rect2(Vector2((frame % 4) * 512, (frame / 4) * 256), Vector2(512, 256)), "Knife frame %d should map to its exact atlas cell." % frame)
		var frame_image := _atlas_frame_image(sheet, frame)
		var used_rect := frame_image.get_used_rect()
		var measured := Rect2(Vector2(used_rect.position - Vector2i(256, 128)), Vector2(used_rect.size))
		_check(measured == DiverFrameEnvelopeScript.bounds_for(&"knife_swing", frame), "Knife frame %d should match its separate action envelope." % frame)
		_check(_cell_has_padding(used_rect), "Knife frame %d should retain transparent atlas padding." % frame)
		var components := _alpha_component_areas(frame_image, 8)
		_check(components.size() == 1, "Knife frame %d should contain one connected glove-and-blade silhouette." % frame)
		var area := int(components[0]) if components.size() == 1 else 0
		if previous_area > 0:
			_check(absf(float(area - previous_area)) / float(previous_area) <= 0.01, "Knife frame %d should preserve fixed-grip silhouette mass across the arc." % frame)
		previous_area = area
		unique_frames[hash(frame_image.get_data())] = true
	_check(unique_frames.size() >= 12, "Knife swing should expose a real authored arc rather than repeated still frames.")
	_check(_import_mipmaps_enabled(KNIFE_SOURCE), "Knife action sheet must generate mipmaps for runtime minification.")


func _atlas_frame_image(sheet: Image, frame: int) -> Image:
	var origin := Vector2i((frame % 4) * 512, (frame / 4) * 256)
	return sheet.get_region(Rect2i(origin, DiverFrameEnvelopeScript.FRAME_SIZE))


func _cell_has_padding(used_rect: Rect2i) -> bool:
	return (
		used_rect.position.x >= MINIMUM_CELL_PADDING
		and used_rect.position.y >= MINIMUM_CELL_PADDING
		and DiverFrameEnvelopeScript.FRAME_SIZE.x - used_rect.end.x >= MINIMUM_CELL_PADDING
		and DiverFrameEnvelopeScript.FRAME_SIZE.y - used_rect.end.y >= MINIMUM_CELL_PADDING
	)


func _import_mipmaps_enabled(source_path: String) -> bool:
	var import_path := source_path + ".import"
	return FileAccess.file_exists(import_path) and "mipmaps/generate=true" in FileAccess.get_file_as_string(import_path)


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
	_check(low_reduced.get("bubble_count") == 2, "Cold-start low/reduced should allocate the focused breath budget directly.")
	_check(low_reduced.get("wake_upper_count") == 2 and low_reduced.get("wake_lower_count") == 2, "Cold-start low/reduced should retain a small two-fin wake signal.")
	_check(low_reduced.get("leak_count") == 1 and low_reduced.get("tool_count") == 2 and low_reduced.get("cue_count") == 4, "Cold-start low/reduced should allocate reduced contextual budgets.")

	diver.set_reduced_motion(false)
	var low: Dictionary = visual_effects.graphics_quality_state()
	_check(low.get("bubble_count") == 3 and low.get("wake_upper_count") == 3 and low.get("wake_lower_count") == 3, "Low profile should retain the focused breath and two-fin wake budgets.")
	_check(low.get("leak_count") == 2 and low.get("tool_count") == 3 and low.get("cue_count") == 5, "Low profile should retain readable contextual budgets.")

	diver.set_graphics_quality("medium")
	var medium: Dictionary = visual_effects.graphics_quality_state()
	_check(medium.get("bubble_count") == 5 and medium.get("wake_upper_count") == 5 and medium.get("wake_lower_count") == 5, "Medium profile should increase breath and keep a balanced two-fin wake density.")
	_check(medium.get("leak_count") == 4 and medium.get("tool_count") == 5 and medium.get("cue_count") == 8, "Medium profile should increase contextual density monotonically.")

	diver.set_graphics_quality("high")
	var high: Dictionary = visual_effects.graphics_quality_state()
	_check(high.get("bubble_count") == 7, "High profile should expose the focused authored breath budget.")
	_check(high.get("wake_count") == 20, "High profile should split the authored wake budget across both fins.")
	_check(high.get("leak_count") == 7 and high.get("tool_count") == 7 and high.get("cue_count") == 12, "High profile should expose all contextual VFX budgets.")
	_check(float(high.get("bubble_lifetime", 99.0)) < 1.05, "A sprint breath pulse should finish before the next authored breath interval instead of restarting live particles.")
	_check(is_equal_approx(
		float(high.get("visual_retarget_scale", 0.0)),
		APPROVED_SPRITE_SCALE.x / PREVIOUS_AUTHORED_SPRITE_SCALE
	), "Diver VFX dimensions should follow the same visual retarget ratio as the sprite.")
	var bubble_material := (visual_effects.get_node("BreathEmitter") as GPUParticles2D).process_material as ParticleProcessMaterial
	var tool_material := (visual_effects.get_node("ToolEmitter") as GPUParticles2D).process_material as ParticleProcessMaterial
	var cue_material := (visual_effects.get_node("CueEmitter") as GPUParticles2D).process_material as ParticleProcessMaterial
	var retarget_scale := APPROVED_SPRITE_SCALE.x / PREVIOUS_AUTHORED_SPRITE_SCALE
	_check(is_equal_approx(bubble_material.scale_min, 0.24 * retarget_scale) and is_equal_approx(bubble_material.scale_max, 0.70 * retarget_scale), "Breath bubbles should retain the focused readable scale range.")
	_check(is_equal_approx(bubble_material.emission_sphere_radius, 1.5 * retarget_scale) and bubble_material.spread <= 9.0, "Breathing should remain a focused regulator pulse instead of a cloud around the helmet.")
	_check(is_equal_approx(tool_material.scale_min, 0.24 * retarget_scale) and is_equal_approx(tool_material.scale_max, 0.62 * retarget_scale), "Tool glints should retain the reviewed readable scale range.")
	_check(is_equal_approx(cue_material.scale_min, 0.28 * retarget_scale) and is_equal_approx(cue_material.scale_max, 0.82 * retarget_scale), "Action cues should retain the reviewed readable scale range.")

	diver.set_reduced_motion(true)
	var high_reduced: Dictionary = visual_effects.graphics_quality_state()
	_check(high_reduced.get("bubble_count") == 5 and high_reduced.get("wake_count") == 10, "Reduced motion should lower high-profile breath and wake density.")
	_check(high_reduced.get("leak_count") == 4 and high_reduced.get("tool_count") == 4 and high_reduced.get("cue_count") == 8, "Reduced motion should lower all high-profile contextual budgets.")
	_check(float(high_reduced.get("bubble_lifetime", 99.0)) < float(high.get("bubble_lifetime", 0.0)) and float(high_reduced.get("wake_lifetime", 99.0)) < float(high.get("wake_lifetime", 0.0)), "Reduced motion should shorten the breath and wake trails.")
	_check(float(high_reduced.get("bubble_speed_scale", 99.0)) < float(high.get("bubble_speed_scale", 0.0)) and float(high_reduced.get("wake_speed_scale", 99.0)) < float(high.get("wake_speed_scale", 0.0)), "Reduced motion should slow the breath and wake particles.")
	diver.set_reduced_motion(false)

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
	_test_camera_smoothing_contract(diver, diver_camera)
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
	var body_material := sprite.material as ShaderMaterial
	var high_lantern_glint := float(body_material.get_shader_parameter(&"lantern_glint"))
	var lantern_state: Dictionary = diver.presentation_state()
	_check(bool(lantern_state.get("lantern_glint_enabled")) and high_lantern_glint > 0.0, "An enabled canonical lantern should produce a restrained local material glint.")
	_check((body_material.get_shader_parameter(&"lantern_color") as Color).is_equal_approx(Color(0.72, 0.9, 1.0, 1.0)), "The glint should derive its color from the canonical lantern presentation seam.")
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
	diver.set_graphics_quality("low")
	var low_reduced_glint := float(body_material.get_shader_parameter(&"lantern_glint"))
	_check(low_reduced_glint > 0.0 and low_reduced_glint < high_lantern_glint, "Low/reduced presentation should retain the lantern cue with a smaller shader budget.")
	diver.set_lantern_presentation(false, Color.WHITE, 350.0, 0.0)
	_check(dive_light.enabled and is_equal_approx(dive_light.texture_scale, radial_scale), "The avatar compatibility seam must not override the root-owned on/off state or radius.")
	_check(is_zero_approx(float(body_material.get_shader_parameter(&"lantern_glint"))), "Disabling the presentation seam should remove only the local glint.")
	diver.set_graphics_quality("high")
	diver.set_reduced_motion(false)
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
	var low_speed_density := float(visual_effects.graphics_quality_state().get("wake_density"))
	var low_speed_amount := wake_upper.amount_ratio + wake_lower.amount_ratio
	diver.velocity = Vector2(230.0, 0.0)
	diver._current_velocity = Vector2(20.0, 0.0)
	visual_effects._update_wake()
	var high_speed_state: Dictionary = visual_effects.graphics_quality_state()
	_check(float(high_speed_state.get("water_relative_speed")) >= 209.0 and float(high_speed_state.get("wake_density")) > low_speed_density, "Wake density should rise with speed relative to water, not world drift.")
	_check(wake_upper.amount_ratio + wake_lower.amount_ratio > low_speed_amount, "Faster propulsion should strengthen both-fin particulate wake output.")
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
	_test_transition_runtime_contract(diver, sprite)
	_test_suit_runtime_contract(diver)
	_test_knife_runtime_contract(diver, sprite)
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


func _test_transition_runtime_contract(diver: DiverController, sprite: AnimatedSprite2D) -> void:
	diver.set_reduced_motion(false)
	var half_target := APPROVED_ENVELOPE * 0.5
	for route: Array in TRANSITION_ROUTES:
		var from_state: StringName = route[0]
		var to_state: StringName = route[1]
		var clip: StringName = route[2]
		var duration: float = route[3]
		var target_anchor: int = route[4]
		diver.reset_at(Vector2.ZERO)
		diver._locomotion_state = from_state
		diver._locomotion_target = from_state
		sprite.play(from_state)
		sprite.pause()
		sprite.set_frame_and_progress(5, 0.0)
		diver._begin_locomotion_transition(from_state, to_state)
		_check(diver._transition_clip == clip, "%s>%s should select %s." % [from_state, to_state, clip])
		_check(is_equal_approx(diver._transition_duration, duration), "%s>%s should last %.2f seconds." % [from_state, to_state, duration])
		_check(diver._handoff_active and (diver.handoff_sprite as AnimatedSprite2D).visible, "%s>%s should begin with a short visual handoff." % [from_state, to_state])
		diver._transition_progress = 0.5
		diver._sample_transition_frame()
		diver._update_presentation_pose(0.0)
		diver._update_socket_markers()
		var expected_frame := 7
		_check(sprite.frame == expected_frame, "%s>%s midpoint should sample the authored transition direction." % [from_state, to_state])
		var bounds: Rect2 = diver._current_visual_alpha_bounds()
		_check(bounds.position.x >= -half_target.x - 0.01 and bounds.end.x <= half_target.x + 0.01, "%s>%s handoff union should remain in the horizontal body envelope." % [from_state, to_state])
		_check(bounds.position.y >= -half_target.y - 0.01 and bounds.end.y <= half_target.y + 0.01, "%s>%s handoff union should remain in the vertical body envelope." % [from_state, to_state])
		diver._transition_progress = 1.0
		diver._sample_transition_frame()
		diver._finish_locomotion_transition()
		_check(diver._locomotion_state == to_state and sprite.animation == to_state, "%s>%s should finish in its target loop." % [from_state, to_state])
		_check(sprite.frame == target_anchor, "%s>%s should land on target anchor frame %d." % [from_state, to_state, target_anchor])
		_check(not diver._handoff_active and not (diver.handoff_sprite as AnimatedSprite2D).visible, "%s>%s should clear its handoff layer." % [from_state, to_state])

	diver.reset_at(Vector2.ZERO)
	diver._locomotion_state = &"idle"
	sprite.play(&"idle")
	diver._begin_locomotion_transition(&"idle", &"swim")
	diver._transition_progress = 0.37
	diver._sample_transition_frame()
	var frame_before_reverse := sprite.frame
	var frame_progress_before_reverse := sprite.frame_progress
	diver._reverse_locomotion_transition()
	_check(sprite.frame == frame_before_reverse and is_equal_approx(sprite.frame_progress, frame_progress_before_reverse), "Reversing a transition should preserve the currently visible authored sample.")
	_check(diver._transition_from == &"swim" and diver._transition_to == &"idle", "Transition reversal should swap the directed route.")
	_check(is_equal_approx(diver._transition_duration, 0.36), "Idle-to-swim reversal should adopt the swim-to-idle duration.")

	diver.reset_at(Vector2.ZERO)
	var reset_state: Dictionary = diver.presentation_state()
	_check(
		reset_state.get("locomotion_state") == &"idle"
		and reset_state.get("locomotion_target") == &"idle"
		and reset_state.get("transition_clip") == &""
		and is_zero_approx(float(reset_state.get("transition_progress", -1.0)))
		and is_zero_approx(float(reset_state.get("transition_duration", -1.0)))
		and reset_state.get("transition_forward") == true
		and reset_state.get("handoff_active") == false
		and not (diver.handoff_sprite as AnimatedSprite2D).visible
		and sprite.animation == &"idle",
		"reset_at should clear an in-flight locomotion transition and its handoff."
	)
	diver._locomotion_state = &"idle"
	sprite.play(&"idle")
	diver._begin_locomotion_transition(&"idle", &"swim")
	diver._transition_progress = 0.65
	diver._sample_transition_frame()
	diver._redirect_locomotion_transition(&"sprint")
	_check(diver._transition_from == &"swim" and diver._transition_to == &"sprint", "A third-state redirect should choose the direct edge from the dominant pose.")
	_check(diver._transition_clip == &"transition_swim_sprint", "Idle-to-swim redirected to sprint should use the swim/sprint authored edge.")
	_test_handoff_socket_blend(diver, sprite, false)
	_test_handoff_socket_blend(diver, sprite, true)
	_assert_core_presentation_invariants(diver)
	diver.reset_at(Vector2.ZERO)


func _test_handoff_socket_blend(
	diver: DiverController,
	sprite: AnimatedSprite2D,
	flip_h: bool
) -> void:
	diver.reset_at(Vector2.ZERO)
	diver._locomotion_state = &"idle"
	diver._locomotion_target = &"idle"
	sprite.play(&"idle")
	sprite.pause()
	sprite.flip_h = flip_h
	sprite.set_frame_and_progress(5, 0.0)
	var source_positions := {}
	for socket_id: StringName in DiverSocketProfileScript.REQUIRED_SOCKETS:
		source_positions[socket_id] = diver.socket_profile.position_for(
			&"idle", socket_id, 5, flip_h
		)
	diver._begin_locomotion_transition(&"idle", &"swim")
	diver._update_socket_markers()
	for socket_id: StringName in DiverSocketProfileScript.REQUIRED_SOCKETS:
		var marker := diver._marker_for_socket(socket_id)
		_check(marker.position.is_equal_approx(source_positions[socket_id]), "Handoff start must retain %s on the visible source pose when flip_h=%s." % [socket_id, flip_h])

	diver._handoff_elapsed = DiverController.TRANSITION_HANDOFF_DURATION * 0.5
	diver._update_socket_markers()
	for socket_id: StringName in DiverSocketProfileScript.REQUIRED_SOCKETS:
		var marker := diver._marker_for_socket(socket_id)
		var target_position: Vector2 = diver.socket_profile.position_for(
			sprite.animation, socket_id, sprite.frame, flip_h
		)
		var expected_half: Vector2 = (source_positions[socket_id] as Vector2).lerp(
			target_position,
			0.5
		)
		_check(marker.position.is_equal_approx(expected_half), "Handoff midpoint must blend %s between source and target when flip_h=%s." % [socket_id, flip_h])

	diver._advance_handoff(DiverController.TRANSITION_HANDOFF_DURATION * 0.5)
	diver._update_socket_markers()
	_check(not diver._handoff_active and not diver.handoff_sprite.visible, "Handoff end should retire the source layer when flip_h=%s." % flip_h)
	for socket_id: StringName in DiverSocketProfileScript.REQUIRED_SOCKETS:
		var marker := diver._marker_for_socket(socket_id)
		var target_position: Vector2 = diver.socket_profile.position_for(
			sprite.animation, socket_id, sprite.frame, flip_h
		)
		_check(marker.position.is_equal_approx(target_position), "Handoff end must land %s on the target pose when flip_h=%s." % [socket_id, flip_h])


func _test_suit_runtime_contract(diver: DiverController) -> void:
	var main_sprite := diver.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var handoff := diver.get_node("HandoffSprite2D") as AnimatedSprite2D
	var action := diver.get_node("AnimatedSprite2D/ToolHandSocket/ActionSprite2D") as AnimatedSprite2D
	var materials: Array[ShaderMaterial] = [
		main_sprite.material as ShaderMaterial,
		handoff.material as ShaderMaterial,
		action.material as ShaderMaterial,
	]
	_check(materials[0] != materials[1] and materials[0] != materials[2] and materials[1] != materials[2], "Main, handoff and action layers require independent scene-local materials.")
	for material in materials:
		_check(material != null and material.resource_local_to_scene, "Every Diver readability material should be scene-local.")
	_check(materials[2].get_shader_parameter(&"suit_treatment_enabled") == false, "The knife action layer must preserve its authored steel and gauntlet materials.")
	var suit_materials: Array[ShaderMaterial] = [materials[0], materials[1]]
	for quality in range(1, 5):
		diver.set_suit_quality_presentation(quality)
		var expected: Dictionary = SuitProfile.style_for(quality)
		for material in suit_materials:
			_check(is_equal_approx(float(material.get_shader_parameter(&"suit_style")), float(expected["style_id"])), "Suit Q%d style id should reach both body layers." % quality)
			_check((material.get_shader_parameter(&"suit_pattern_color") as Color).is_equal_approx(expected["pattern_color"] as Color), "Suit Q%d pattern color should reach both body layers." % quality)
			_check(is_equal_approx(float(material.get_shader_parameter(&"suit_plate_strength")), float(expected["plate_strength"])), "Suit Q%d plate treatment should reach both body layers." % quality)
			_check(is_equal_approx(float(material.get_shader_parameter(&"suit_emissive_strength")), float(expected["emissive_strength"])), "Suit Q%d emissive treatment should reach both body layers." % quality)
	var second := DiverScene.instantiate() as DiverController
	add_child(second)
	diver.set_suit_quality_presentation(4)
	var second_material := (second.get_node("AnimatedSprite2D") as AnimatedSprite2D).material as ShaderMaterial
	_check(is_equal_approx(float(second_material.get_shader_parameter(&"suit_style")), 0.0), "A second Diver instance should retain independent Q1 presentation state.")
	second.queue_free()
	diver.set_suit_quality_presentation(1)
	_assert_core_presentation_invariants(diver)


func _test_knife_runtime_contract(diver: DiverController, sprite: AnimatedSprite2D) -> void:
	diver.reset_at(Vector2.ZERO)
	diver.set_reduced_motion(false)
	var action := diver.get_node("AnimatedSprite2D/ToolHandSocket/ActionSprite2D") as AnimatedSprite2D
	var collision_children := diver.find_children("*", "CollisionObject2D", true, false)
	var interaction_range := diver.get_node("InteractionRange") as Area2D
	_check(collision_children.size() == 1 and collision_children[0] == interaction_range, "Diver may contain only its approved InteractionRange child; knife presentation must not add a hitbox anywhere in the scene.")
	var body_shape_node := diver.get_node("CollisionShape2D") as CollisionShape2D
	var interaction_shape_node := diver.get_node("InteractionRange/CollisionShape2D") as CollisionShape2D
	var collision_shapes := diver.find_children("*", "CollisionShape2D", true, false)
	_check(collision_shapes.size() == 2 and body_shape_node in collision_shapes and interaction_shape_node in collision_shapes, "Diver may contain exactly the approved body and InteractionRange shapes; knife presentation must not add a shape under an existing collision object.")
	_check(diver.find_children("*", "CollisionPolygon2D", true, false).is_empty(), "Knife presentation must not hide a collision polygon anywhere in the Diver scene.")
	_check(not diver.begin_attack_presentation(0, &"knife", Vector2(80.0, 0.0), 0.4), "Attack presentation should reject a non-positive serial.")
	_check(not diver.begin_attack_presentation(1, &"harpoon_pistol", Vector2(80.0, 0.0), 0.4), "Knife presentation should reject unsupported weapons.")
	_check(not diver.begin_attack_presentation(1, &"knife", diver.global_position, 0.4), "Attack presentation should reject a zero aim vector.")
	_check(not diver.begin_attack_presentation(1, &"knife", Vector2(INF, 0.0), 0.4), "Attack presentation should reject non-finite targets.")
	_check(not diver.begin_attack_presentation(1, &"knife", Vector2(80.0, 0.0), NAN), "Attack presentation should reject non-finite impact timing.")
	_check(not diver.begin_attack_presentation(1, &"knife", Vector2(80.0, 0.0), 0.01), "Attack presentation should reject impact timing outside the authored window.")

	var target := diver.global_position + Vector2(80.0, -20.0)
	var body_before := diver._current_visual_alpha_bounds()
	_check(diver.begin_attack_presentation(101, &"knife", target, KNIFE_CONTACT_PROGRESS), "A valid root-resolved knife presentation should begin.")
	_check(diver.begin_attack_presentation(101, &"knife", target, KNIFE_CONTACT_PROGRESS), "An identical duplicate begin should be idempotent.")
	_check(not diver.begin_attack_presentation(101, &"knife", target + Vector2.ONE, KNIFE_CONTACT_PROGRESS), "A duplicate serial with a changed target must be rejected.")
	_check(not diver.begin_attack_presentation(101, &"knife", target, 0.45), "A duplicate serial with changed timing must be rejected.")
	_check(not diver.begin_attack_presentation(102, &"knife", target, KNIFE_CONTACT_PROGRESS), "A new serial must not replace an active presentation.")
	diver._update_presentation_pose(0.0)
	_check(diver._current_visual_alpha_bounds().is_equal_approx(body_before), "The separate action layer must not expand the body envelope at zero progress.")
	_check(diver.set_attack_presentation_progress(101, 0.20), "Knife presentation progress should advance monotonically.")
	_check(not diver.set_attack_presentation_progress(101, 0.19), "Knife presentation progress must reject reversal.")
	_check(diver.confirm_attack_presentation(101, true, target, false), "Root should be able to confirm one hit result.")
	_check(not diver.confirm_attack_presentation(101, true, target, false), "A hit result must be accepted exactly once.")
	diver._update_readability_material()
	var action_material := action.material as ShaderMaterial
	_check((action_material.get_shader_parameter(&"action_color") as Color).is_equal_approx(Color("79ded4")), "A confirmed hit must not be revealed before its contact phase.")
	_check(diver.set_attack_presentation_progress(101, KNIFE_CONTACT_PROGRESS), "Knife presentation should reach its contact phase.")
	_check(action.frame == 6, "Root impact progress 0.40 should map exactly to authored knife frame 6.")
	_check((action_material.get_shader_parameter(&"action_color") as Color).is_equal_approx(Color("f0c56b")), "Confirmed contact should receive the authored hit emphasis.")
	_check(not diver.action_visual_alpha_bounds().size.is_zero_approx(), "A visible knife should expose a separate non-empty action envelope.")
	var formal_pose: Dictionary = diver._action_pose_for(sprite)
	diver.play_visual_cue(&"knife_attack", target, 1.0)
	_check(not diver._legacy_knife_action_active, "Compatibility cue playback must not create a second legacy action during a formal attack.")
	var visual_effects := diver.get_node("VisualEffects")
	var knife_cue_state: Dictionary = visual_effects.graphics_quality_state()
	var knife_cue_emitter := visual_effects.get_node("CueEmitter") as GPUParticles2D
	var knife_cue_material := knife_cue_emitter.process_material as ParticleProcessMaterial
	_check(knife_cue_state.get("active_cue") == &"knife_attack", "The formal knife bridge should produce the authored short hand cue.")
	_check(float(knife_cue_state.get("cue_lifetime")) <= 0.22 and knife_cue_material.spread <= 15.0, "Knife cue particles should form a short, narrow blade-edge flash.")
	diver._cue_elapsed = diver._cue_duration * 0.5
	var combined_pose: Dictionary = diver._action_pose_for(sprite)
	_check((combined_pose["offset"] as Vector2).is_equal_approx(formal_pose["offset"] as Vector2), "Compatibility cue must not double the formal knife body lunge.")
	_check(is_equal_approx(float(combined_pose["rotation"]), float(formal_pose["rotation"])), "Compatibility cue must not double the formal knife body roll.")
	_check((combined_pose["scale"] as Vector2).is_equal_approx(formal_pose["scale"] as Vector2), "Compatibility cue must not double the formal knife body scale impulse.")
	_check(diver.end_attack_presentation(101), "Knife presentation should end once.")
	_check(not diver.end_attack_presentation(101), "Knife presentation must reject duplicate end callbacks.")
	diver._update_action_sprite()
	_check(not action.visible and diver.presentation_state()["cue"] == &"", "Ending a formal knife action must not resurrect a still-running legacy cue.")
	_check(not diver.begin_attack_presentation(101, &"knife", target, KNIFE_CONTACT_PROGRESS), "A completed serial must never replay.")

	_check(diver.begin_attack_presentation(102, &"knife", target, KNIFE_CONTACT_PROGRESS), "A later miss presentation should begin.")
	_check(diver.confirm_attack_presentation(102, false, Vector2(INF, INF), false), "A root-confirmed miss may omit a finite contact point.")
	_check(diver.end_attack_presentation(102), "A root-confirmed miss should end normally.")
	_check(diver.begin_attack_presentation(103, &"knife", target, KNIFE_CONTACT_PROGRESS), "A later defeat presentation should begin.")
	_check(not diver.confirm_attack_presentation(103, false, target, true), "Defeated presentation must imply a confirmed hit.")
	_check(diver.confirm_attack_presentation(103, true, target, true), "A root-confirmed defeating hit should be accepted once.")
	_check(diver.end_attack_presentation(103), "A defeating hit presentation should end normally.")

	var directions := PackedVector2Array([
		Vector2.RIGHT,
		Vector2(1.0, -1.0).normalized(),
		Vector2.UP,
		Vector2(-1.0, -1.0).normalized(),
		Vector2.LEFT,
		Vector2(-1.0, 1.0).normalized(),
		Vector2.DOWN,
		Vector2(1.0, 1.0).normalized(),
	])
	var serial := 104
	for direction in directions:
		var aim_target := diver.global_position + direction * 80.0
		_check(diver.begin_attack_presentation(serial, &"knife", aim_target, KNIFE_CONTACT_PROGRESS), "Knife direction sample %s should begin." % direction)
		_check(diver.set_attack_presentation_progress(serial, KNIFE_CONTACT_PROGRESS), "Knife direction sample %s should reach contact." % direction)
		var displayed_forward := Vector2.RIGHT.rotated(action.global_rotation)
		_check(displayed_forward.dot(direction) >= 0.995, "Knife action should visually aim in the full root-supplied direction %s." % direction)
		_check(not diver.action_visual_alpha_bounds().size.is_zero_approx(), "Knife direction %s should retain a measurable action envelope." % direction)
		_check(diver.end_attack_presentation(serial), "Knife direction sample %s should end once." % direction)
		serial += 1

	diver.reset_at(Vector2.ZERO)
	diver.play_visual_cue(&"knife_attack", Vector2(80.0, 0.0), 1.0)
	diver._cue_elapsed = diver._cue_duration * 0.5
	diver.rotation = PI * 0.5
	diver._update_action_sprite()
	var legacy_displayed_forward := Vector2.RIGHT.rotated(action.global_rotation)
	_check(legacy_displayed_forward.dot(Vector2.RIGHT) >= 0.995, "Legacy knife cue must keep aiming at its immutable root-supplied world target while the diver turns.")
	var legacy_pose: Dictionary = diver._action_pose_for(sprite)
	var legacy_lunge_global := (legacy_pose["offset"] as Vector2).rotated(diver.rotation).normalized()
	_check(legacy_lunge_global.dot(Vector2.RIGHT) >= 0.995, "Legacy knife body lunge must remain aligned with the immutable world-space attack target while the diver turns.")
	diver._clear_visual_cue()
	diver.rotation = 0.0

	diver.reset_at(Vector2.ZERO)
	_check(diver.begin_attack_presentation(1, &"knife", Vector2(80.0, 0.0), KNIFE_CONTACT_PROGRESS), "reset_at should deliberately begin a fresh attack-serial epoch.")
	_check(diver.end_attack_presentation(1, true), "A reset-epoch presentation should support a single canceled end.")
	_assert_core_presentation_invariants(diver)
	diver.reset_at(Vector2.ZERO)
	sprite.flip_h = false


func _assert_core_presentation_invariants(diver: DiverController) -> void:
	var capsule := (diver.get_node("CollisionShape2D") as CollisionShape2D).shape as CapsuleShape2D
	var interaction := (diver.get_node("InteractionRange/CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
	var camera := diver.get_node("Camera2D") as Camera2D
	var light := diver.get_node("DiveLight") as PointLight2D
	_check(diver.scale.is_equal_approx(Vector2.ONE), "Diver presentation features must keep the CharacterBody2D root unscaled.")
	_check(is_equal_approx(capsule.height, 105.0) and is_equal_approx(capsule.radius, 30.0), "Diver presentation features must preserve the 105 x 60 gameplay capsule.")
	_check(is_equal_approx(interaction.radius, 112.0), "Diver presentation features must preserve InteractionRange 112.")
	_check(is_equal_approx(diver.swim_speed, 175.0) and is_equal_approx(diver.sprint_speed, 265.0), "Diver presentation features must preserve movement speeds.")
	_check(is_equal_approx(diver.acceleration, 620.0) and is_equal_approx(diver.drag, 760.0) and is_equal_approx(diver.turn_speed, 10.0), "Diver presentation features must preserve movement response values.")
	_check(light.get_parent() == diver and light.position.is_zero_approx(), "Diver presentation features must preserve one central radial light.")
	_check(diver.camera_profile != null and camera.process_callback == 0 and camera.zoom.is_equal_approx(Vector2(1.2, 1.2)), "Diver presentation features must preserve the approved v4 camera profile and physics follow mode.")


func _test_camera_smoothing_contract(diver: DiverController, camera: Camera2D) -> void:
	_check(camera.position_smoothing_enabled, "The production camera should retain the reduced-motion smoothing seam.")
	_check(is_zero_approx(camera.position_smoothing_speed), "Camera2D must not stack its frame-dependent filter over the deterministic diver-camera filter.")
	_check(diver.camera_profile.validation_errors().is_empty(), "The active camera profile should remain valid.")
	_check(is_equal_approx(diver._camera_intent_weight(0.79, 0.8), 0.0), "Camera look-ahead should reject propulsion outside the intended movement cone.")
	_check(is_equal_approx(diver._camera_intent_weight(0.8, 0.8), 0.0), "Camera look-ahead should enter its intent cone without a binary lead jump.")
	_check(is_equal_approx(diver._camera_intent_weight(0.9, 0.8), 0.5), "Camera look-ahead should feather continuously through the intent cone.")
	_check(is_equal_approx(diver._camera_intent_weight(1.0, 0.8), 1.0), "Camera look-ahead should retain full lead for aligned propulsion.")

	var sprint_response := float(diver.camera_profile.get("sprint_response"))
	var constant_target := Vector2(float(diver.camera_profile.get("sprint_lead_distance")), 0.0)
	var fixed_target_samples: Array[Vector2] = []
	var first_fixed_steps := {}
	for ticks_per_second: int in CAMERA_TICK_RATES:
		diver._camera_lead_world = Vector2.ZERO
		diver._camera_lead_velocity_world = Vector2.ZERO
		var previous := Vector2.ZERO
		var monotonic := true
		for tick in range(ticks_per_second):
			diver._smooth_camera_lead(constant_target, sprint_response, 1.0 / float(ticks_per_second))
			var current: Vector2 = diver._camera_lead_world
			monotonic = monotonic and current.x >= previous.x - 0.0001 and current.x <= constant_target.x + 0.0001 and absf(current.y) <= 0.0001
			if tick == 0:
				first_fixed_steps[ticks_per_second] = current.length()
			previous = current
		fixed_target_samples.append(diver._camera_lead_world)
		_check(monotonic, "Camera lead should approach a fixed target without overshoot at %d physics ticks per second." % ticks_per_second)
	_check(float(first_fixed_steps.get(60, constant_target.length())) <= constant_target.length() * 0.02, "Camera lead should accelerate gently instead of jumping on its first 60 Hz step.")
	_check(fixed_target_samples[0].distance_to(fixed_target_samples[1]) <= 0.001, "A fixed camera target should agree after one second at 30 and 60 physics ticks per second.")
	_check(fixed_target_samples[1].distance_to(fixed_target_samples[2]) <= 0.001, "A fixed camera target should agree after one second at 60 and 120 physics ticks per second.")

	var runtime_samples := {false: {}, true: {}}
	for sprinting: bool in [false, true]:
		for ticks_per_second: int in CAMERA_TICK_RATES:
			var sample := _camera_start_trace(diver, ticks_per_second, sprinting)
			runtime_samples[sprinting][ticks_per_second] = sample
			var authored_distance := float(diver.camera_profile.get("sprint_lead_distance" if sprinting else "swim_lead_distance"))
			_check(bool(sample.get("monotonic", false)), "%s camera lead should grow monotonically without overshoot at %d Hz." % ["Sprint" if sprinting else "Swim", ticks_per_second])
			_check(float(sample.get("first_step", authored_distance)) <= authored_distance * 0.04, "%s camera lead should stay gentle on the first %d Hz movement step." % ["Sprint" if sprinting else "Swim", ticks_per_second])
			_check(float(sample.get("final", 0.0)) > 10.0 and float(sample.get("final", authored_distance + 1.0)) <= authored_distance + 0.01, "%s camera lead should settle ahead without overshoot at %d Hz." % ["Sprint" if sprinting else "Swim", ticks_per_second])
		var thirty_final := float((runtime_samples[sprinting][30] as Dictionary).get("final", 0.0))
		var sixty_final := float((runtime_samples[sprinting][60] as Dictionary).get("final", 0.0))
		var one_twenty_final := float((runtime_samples[sprinting][120] as Dictionary).get("final", 0.0))
		_check(absf(thirty_final - sixty_final) <= 2.0, "%s camera result after one second should be comparable at 30 and 60 Hz." % ["Sprint" if sprinting else "Swim"])
		_check(absf(sixty_final - one_twenty_final) <= 1.0, "%s camera result after one second should be comparable at 60 and 120 Hz." % ["Sprint" if sprinting else "Swim"])
	for ticks_per_second: int in CAMERA_TICK_RATES:
		var swim_final := float((runtime_samples[false][ticks_per_second] as Dictionary).get("final", 0.0))
		var sprint_final := float((runtime_samples[true][ticks_per_second] as Dictionary).get("final", 0.0))
		_check(sprint_final > swim_final + 10.0, "Sprint should retain a materially larger stable lead than swim at %d Hz." % ticks_per_second)

	for sprinting: bool in [false, true]:
		for ticks_per_second: int in CAMERA_TICK_RATES:
			var reversal := _camera_reversal_trace(diver, ticks_per_second, sprinting)
			_check(float(reversal.get("warm_velocity", 0.0)) > 1.0, "The %s reversal fixture at %d Hz must exercise retained camera velocity." % ["sprint" if sprinting else "swim", ticks_per_second])
			_check(float(reversal.get("first", 0.0)) < float(reversal.get("before", 0.0)), "A %s 180-degree turn must retire the old lead on its first %d Hz tick." % ["sprint" if sprinting else "swim", ticks_per_second])
			_check(bool(reversal.get("monotonic", false)) and bool(reversal.get("within_target", false)), "A %s 180-degree turn must not oscillate or overshoot at %d Hz." % ["sprint" if sprinting else "swim", ticks_per_second])
			_check(float(reversal.get("final", 0.0)) < -10.0, "A %s 180-degree turn should settle ahead in the new direction at %d Hz." % ["sprint" if sprinting else "swim", ticks_per_second])
			var release := _camera_release_trace(diver, ticks_per_second, sprinting)
			_check(float(release.get("warm_velocity", 0.0)) > 1.0, "The %s release fixture at %d Hz must exercise retained camera velocity." % ["sprint" if sprinting else "swim", ticks_per_second])
			_check(float(release.get("first", 0.0)) < float(release.get("before", 0.0)), "Releasing %s input must recenter on its first %d Hz tick." % ["sprint" if sprinting else "swim", ticks_per_second])
			_check(bool(release.get("monotonic", false)) and float(release.get("final", 1.0)) <= 0.1 and float(release.get("final_speed", 1.0)) <= 0.5, "Releasing %s input must settle without overshoot, oscillation or residual drift at %d Hz." % ["sprint" if sprinting else "swim", ticks_per_second])

	diver.reset_at(CAMERA_TEST_ORIGIN)
	camera.force_update_scroll()
	var screen_lead := camera.get_screen_center_position() - diver.global_position
	_check(screen_lead.length() <= 0.1, "The real Camera2D screen center should share the controller-owned centered state after reset.")
	_check(diver.scale.is_equal_approx(Vector2.ONE), "Camera traces must preserve the physical root scale; actual=%s." % diver.scale)


func _camera_start_trace(diver: DiverController, ticks_per_second: int, sprinting: bool) -> Dictionary:
	diver.reset_at(CAMERA_TEST_ORIGIN)
	var delta := 1.0 / float(ticks_per_second)
	var previous := 0.0
	var first_step := 0.0
	var monotonic := true
	var authored_distance := float(diver.camera_profile.get("sprint_lead_distance" if sprinting else "swim_lead_distance"))
	for tick in range(ticks_per_second):
		diver.simulate_motion_tick(Vector2.RIGHT, sprinting, Vector2.ZERO, 1.0, delta, true)
		var current := diver._camera_lead_world.x
		if tick == 0:
			first_step = current
		monotonic = monotonic and current >= previous - 0.0001 and current <= authored_distance + 0.0001 and absf(diver._camera_lead_world.y) <= 0.0001
		previous = current
	return {
		"first_step": first_step,
		"final": diver._camera_lead_world.x,
		"monotonic": monotonic,
	}


func _camera_reversal_trace(diver: DiverController, ticks_per_second: int, sprinting: bool) -> Dictionary:
	diver.reset_at(CAMERA_TEST_ORIGIN)
	var delta := 1.0 / float(ticks_per_second)
	var warmup_ticks := maxi(1, roundi(float(ticks_per_second) * 0.3))
	for _tick in range(warmup_ticks):
		diver.simulate_motion_tick(Vector2.RIGHT, sprinting, Vector2.ZERO, 1.0, delta, true)
	var before := diver._camera_lead_world.x
	var warm_velocity := diver._camera_lead_velocity_world.x
	diver.simulate_motion_tick(Vector2.LEFT, sprinting, Vector2.ZERO, 1.0, delta, true)
	var first := diver._camera_lead_world.x
	var previous := first
	var monotonic := first < before
	var authored_distance := float(diver.camera_profile.get("sprint_lead_distance" if sprinting else "swim_lead_distance"))
	var within_target := first >= -authored_distance - 0.01
	for _tick in range(maxi(1, roundi(float(ticks_per_second) * 1.7))):
		diver.simulate_motion_tick(Vector2.LEFT, sprinting, Vector2.ZERO, 1.0, delta, true)
		var current := diver._camera_lead_world.x
		monotonic = monotonic and current <= previous + 0.0001
		within_target = within_target and current >= -authored_distance - 0.01 and absf(diver._camera_lead_world.y) <= 0.0001
		previous = current
	return {
		"before": before,
		"first": first,
		"final": diver._camera_lead_world.x,
		"warm_velocity": warm_velocity,
		"monotonic": monotonic,
		"within_target": within_target,
	}


func _camera_release_trace(diver: DiverController, ticks_per_second: int, sprinting: bool) -> Dictionary:
	diver.reset_at(CAMERA_TEST_ORIGIN)
	var delta := 1.0 / float(ticks_per_second)
	var warmup_ticks := maxi(1, roundi(float(ticks_per_second) * 0.3))
	for _tick in range(warmup_ticks):
		diver.simulate_motion_tick(Vector2.RIGHT, sprinting, Vector2.ZERO, 1.0, delta, true)
	var before := diver._camera_lead_world.x
	var warm_velocity := diver._camera_lead_velocity_world.x
	diver.simulate_motion_tick(Vector2.ZERO, false, Vector2.ZERO, 1.0, delta, true)
	var first := diver._camera_lead_world.x
	var previous := first
	var monotonic := first < before and first >= -0.0001
	for _tick in range(maxi(1, roundi(float(ticks_per_second) * 2.0))):
		diver.simulate_motion_tick(Vector2.ZERO, false, Vector2.ZERO, 1.0, delta, true)
		var current := diver._camera_lead_world.x
		monotonic = monotonic and current <= previous + 0.0001 and current >= -0.0001 and absf(diver._camera_lead_world.y) <= 0.0001
		previous = current
	return {
		"before": before,
		"first": first,
		"final": diver._camera_lead_world.length(),
		"final_speed": diver._camera_lead_velocity_world.length(),
		"warm_velocity": warm_velocity,
		"monotonic": monotonic,
	}


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
		_check(diver.scale.is_equal_approx(Vector2.ONE), "%s turn sweep must keep the physical root unscaled; actual=%s." % [label, diver.scale])
		previous_forward = current_forward


func _visual_forward(diver: DiverController, sprite: AnimatedSprite2D) -> Vector2:
	return (Vector2.LEFT if sprite.flip_h else Vector2.RIGHT).rotated(diver.rotation)


func _test_runtime_visual_envelope(diver: DiverController, sprite: AnimatedSprite2D) -> void:
	var half_target: Vector2 = EnvelopeProfile.target_size * 0.5
	for animation_name: StringName in DiverFrameEnvelopeScript.BODY_ANIMATIONS:
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
