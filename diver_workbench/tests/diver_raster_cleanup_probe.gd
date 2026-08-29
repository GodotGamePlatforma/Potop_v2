extends Node

const DiverFrameEnvelopeScript := preload("res://diver_workbench/definitions/DiverFrameEnvelope.gd")
const ANIMATION_SOURCES := {
	&"idle": "res://diver_workbench/assets/animation/diver_idle_16f.png",
	&"swim": "res://diver_workbench/assets/animation/diver_swim_16f.png",
	&"sprint": "res://diver_workbench/assets/animation/diver_sprint_16f.png",
}


func _ready() -> void:
	for error in _validation_errors():
		push_error("Diver raster cleanup validation failed: " + error)


func _validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var measured_union := Rect2()
	var has_union := false
	var measured_count := 0
	for animation_name: StringName in ANIMATION_SOURCES:
		var image := Image.new()
		var image_error := image.load(ProjectSettings.globalize_path(ANIMATION_SOURCES[animation_name]))
		if image_error != OK:
			errors.append("%s source sheet should load." % animation_name)
			continue
		if image.get_format() != Image.FORMAT_RGBA8:
			errors.append("%s should remain RGBA8." % animation_name)
		if image.get_size() != Vector2i(2048, 1024):
			errors.append("%s should retain the 4 x 4 sheet dimensions." % animation_name)
			continue
		for frame in range(16):
			var frame_origin := Vector2i(
				(frame % 4) * DiverFrameEnvelopeScript.FRAME_SIZE.x,
				(frame / 4) * DiverFrameEnvelopeScript.FRAME_SIZE.y
			)
			var frame_image := image.get_region(Rect2i(frame_origin, DiverFrameEnvelopeScript.FRAME_SIZE))
			var component_count := _count_alpha_components(frame_image)
			if component_count != 1:
				errors.append("%s frame %d should contain one 8-connected alpha component, got %d." % [animation_name, frame, component_count])
			var used_rect := frame_image.get_used_rect()
			var measured := Rect2(
				Vector2(used_rect.position - DiverFrameEnvelopeScript.FRAME_SIZE / 2),
				Vector2(used_rect.size)
			)
			var expected: Rect2 = DiverFrameEnvelopeScript.bounds_for(animation_name, frame)
			if measured != expected:
				errors.append("%s frame %d alpha bounds should match the runtime profile: %s != %s." % [animation_name, frame, measured, expected])
			measured_union = measured if not has_union else measured_union.merge(measured)
			has_union = true
			measured_count += 1
	if measured_count != 48:
		errors.append("Raster cleanup should inspect all 48 frames.")
	if measured_union != DiverFrameEnvelopeScript.SOURCE_UNION:
		errors.append("The measured union should match the runtime profile: %s != %s." % [measured_union, DiverFrameEnvelopeScript.SOURCE_UNION])
	return errors


func _count_alpha_components(image: Image) -> int:
	image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var pixel_count := width * height
	var rgba := image.get_data()
	var visited := PackedByteArray()
	visited.resize(pixel_count)
	var queue := PackedInt32Array()
	var components := 0
	for pixel_index in range(pixel_count):
		if visited[pixel_index] != 0 or rgba[pixel_index * 4 + 3] == 0:
			continue
		components += 1
		visited[pixel_index] = 1
		queue.clear()
		queue.append(pixel_index)
		var queue_index := 0
		while queue_index < queue.size():
			var current := queue[queue_index]
			queue_index += 1
			var current_x := current % width
			var current_y := current / width
			for neighbor_y in range(maxi(0, current_y - 1), mini(height, current_y + 2)):
				for neighbor_x in range(maxi(0, current_x - 1), mini(width, current_x + 2)):
					var neighbor := neighbor_y * width + neighbor_x
					if visited[neighbor] != 0 or rgba[neighbor * 4 + 3] == 0:
						continue
					visited[neighbor] = 1
					queue.append(neighbor)
	return components
