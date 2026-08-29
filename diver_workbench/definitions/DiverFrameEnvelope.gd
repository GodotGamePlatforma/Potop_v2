extends RefCounted

## Measured alpha bounds in the 512 x 256 source-frame coordinate space.
## The runtime consumes the same data that the local test validates against every
## PNG frame, so presentation poses cannot silently drift outside the approved
## physical envelope stored in DiverFrameEnvelopeProfile.

const FRAME_SIZE := Vector2i(512, 256)
const SOURCE_UNION := Rect2(-188, -99, 428, 204)
## The readability shader samples 3.5 source pixels beyond opaque alpha. Reserve
## one additional half-pixel for bilinear filtering so the rendered rim remains
## inside the same physical presentation envelope as the measured raster.
const READABILITY_RIM_SOURCE_PADDING := 4.0

const FRAME_BOUNDS := {
	&"idle": [
		Rect2(-164, -96, 403, 180), Rect2(-161, -98, 400, 180),
		Rect2(-180, -97, 419, 185), Rect2(-179, -97, 418, 187),
		Rect2(-165, -97, 404, 180), Rect2(-180, -97, 419, 181),
		Rect2(-177, -98, 417, 182), Rect2(-179, -98, 418, 177),
		Rect2(-169, -98, 408, 179), Rect2(-179, -98, 418, 180),
		Rect2(-173, -99, 412, 178), Rect2(-172, -99, 411, 173),
		Rect2(-169, -99, 408, 180), Rect2(-174, -99, 413, 172),
		Rect2(-178, -98, 417, 180), Rect2(-175, -98, 414, 179),
	],
	&"swim": [
		Rect2(-167, -96, 406, 173), Rect2(-161, -96, 400, 186),
		Rect2(-158, -95, 397, 161), Rect2(-163, -96, 402, 197),
		Rect2(-173, -97, 412, 175), Rect2(-160, -97, 399, 189),
		Rect2(-166, -98, 405, 175), Rect2(-160, -98, 399, 191),
		Rect2(-168, -98, 407, 181), Rect2(-148, -98, 387, 162),
		Rect2(-162, -97, 401, 168), Rect2(-158, -97, 397, 188),
		Rect2(-168, -95, 407, 177), Rect2(-157, -95, 396, 163),
		Rect2(-155, -95, 394, 180), Rect2(-164, -96, 403, 164),
	],
	&"sprint": [
		Rect2(-188, -98, 427, 172), Rect2(-181, -96, 419, 191),
		Rect2(-166, -97, 404, 202), Rect2(-166, -97, 404, 161),
		Rect2(-182, -96, 420, 200), Rect2(-179, -96, 417, 193),
		Rect2(-166, -96, 404, 194), Rect2(-175, -98, 414, 179),
		Rect2(-177, -96, 416, 176), Rect2(-177, -96, 417, 169),
		Rect2(-181, -98, 421, 185), Rect2(-177, -99, 417, 201),
		Rect2(-180, -98, 420, 170), Rect2(-177, -98, 417, 178),
		Rect2(-178, -98, 418, 164), Rect2(-175, -98, 414, 175),
	],
}


static func bounds_for(animation_name: StringName, frame: int) -> Rect2:
	var frames: Array = FRAME_BOUNDS.get(animation_name, [])
	if frames.is_empty():
		return Rect2()
	var bounds: Rect2 = frames[clampi(frame, 0, frames.size() - 1)]
	return bounds


static func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for animation_name: StringName in [&"idle", &"swim", &"sprint"]:
		var frames: Array = FRAME_BOUNDS.get(animation_name, [])
		if frames.size() != 16:
			errors.append("%s must expose exactly 16 measured alpha bounds." % animation_name)
			continue
		for frame in range(frames.size()):
			var bounds: Rect2 = frames[frame]
			if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
				errors.append("%s frame %d has an empty alpha envelope." % [animation_name, frame])
	return errors
