extends RefCounted

## Measured alpha bounds in the 512 x 256 source-frame coordinate space.
## The runtime consumes the same data that the local test validates against every
## PNG frame, so presentation poses cannot silently drift outside the approved
## physical envelope stored in DiverFrameEnvelopeProfile.

const FRAME_SIZE := Vector2i(512, 256)
const SOURCE_UNION := Rect2(-207, -82, 420, 199)
## The readability shader samples 3.5 source pixels beyond opaque alpha. Reserve
## one additional half-pixel for bilinear filtering so the rendered rim remains
## inside the same physical presentation envelope as the measured raster.
const READABILITY_RIM_SOURCE_PADDING := 4.0

const FRAME_BOUNDS := {
	&"idle": [
		Rect2(-207, -82, 420, 163), Rect2(-207, -82, 420, 163),
		Rect2(-207, -82, 420, 163), Rect2(-207, -82, 420, 163),
		Rect2(-207, -82, 420, 163), Rect2(-207, -82, 420, 163),
		Rect2(-207, -82, 420, 163), Rect2(-207, -82, 420, 163),
		Rect2(-207, -82, 420, 163), Rect2(-207, -82, 420, 163),
		Rect2(-206, -82, 419, 163), Rect2(-206, -82, 419, 163),
		Rect2(-206, -82, 419, 163), Rect2(-206, -82, 419, 163),
		Rect2(-206, -82, 419, 163), Rect2(-207, -82, 420, 163),
	],
	&"swim": [
		Rect2(-207, -82, 420, 163), Rect2(-207, -82, 420, 172),
		Rect2(-207, -82, 420, 184), Rect2(-206, -82, 419, 192),
		Rect2(-206, -82, 419, 195), Rect2(-206, -82, 419, 192),
		Rect2(-207, -82, 420, 184), Rect2(-207, -82, 420, 172),
		Rect2(-207, -82, 420, 163), Rect2(-206, -82, 419, 163),
		Rect2(-205, -82, 418, 171), Rect2(-204, -82, 417, 179),
		Rect2(-203, -82, 416, 182), Rect2(-204, -82, 417, 179),
		Rect2(-205, -82, 418, 171), Rect2(-206, -82, 419, 163),
	],
	&"sprint": [
		Rect2(-207, -82, 420, 163), Rect2(-207, -82, 420, 174),
		Rect2(-207, -82, 420, 187), Rect2(-206, -82, 419, 196),
		Rect2(-206, -82, 419, 199), Rect2(-206, -82, 419, 196),
		Rect2(-207, -82, 420, 187), Rect2(-207, -82, 420, 174),
		Rect2(-207, -82, 420, 163), Rect2(-206, -82, 419, 163),
		Rect2(-205, -82, 418, 174), Rect2(-203, -82, 416, 183),
		Rect2(-203, -82, 416, 187), Rect2(-203, -82, 416, 183),
		Rect2(-205, -82, 418, 174), Rect2(-206, -82, 419, 163),
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
