extends RefCounted

## Measured alpha bounds in the 512 x 256 source-frame coordinate space.
## The runtime consumes the same data that the local test validates against every
## PNG frame, so presentation poses cannot silently drift outside the approved
## physical envelope stored in DiverFrameEnvelopeProfile.

const FRAME_SIZE := Vector2i(512, 256)
const SOURCE_UNION := Rect2(-238, -84, 430, 195)

const FRAME_BOUNDS := {
	&"idle": [
		Rect2(-213, -81, 400, 175), Rect2(-207, -81, 391, 175),
		Rect2(-198, -82, 381, 177), Rect2(-196, -82, 376, 176),
		Rect2(-203, -82, 385, 182), Rect2(-205, -82, 390, 178),
		Rect2(-197, -83, 380, 178), Rect2(-194, -82, 374, 177),
		Rect2(-202, -82, 385, 179), Rect2(-202, -84, 385, 177),
		Rect2(-198, -83, 379, 174), Rect2(-194, -83, 374, 177),
		Rect2(-203, -83, 387, 179), Rect2(-203, -83, 386, 177),
		Rect2(-199, -82, 382, 176), Rect2(-197, -82, 378, 176),
	],
	&"swim": [
		Rect2(-238, -80, 430, 162), Rect2(-194, -81, 375, 180),
		Rect2(-191, -80, 372, 173), Rect2(-179, -81, 356, 176),
		Rect2(-228, -81, 418, 176), Rect2(-194, -81, 376, 192),
		Rect2(-200, -81, 383, 180), Rect2(-196, -82, 379, 173),
		Rect2(-214, -82, 401, 171), Rect2(-202, -81, 386, 190),
		Rect2(-193, -80, 374, 171), Rect2(-199, -82, 382, 179),
		Rect2(-229, -82, 420, 173), Rect2(-200, -80, 384, 175),
		Rect2(-203, -80, 387, 175), Rect2(-201, -81, 384, 175),
	],
	&"sprint": [
		Rect2(-205, -72, 386, 124), Rect2(-210, -71, 393, 141),
		Rect2(-207, -69, 390, 128), Rect2(-203, -70, 383, 134),
		Rect2(-223, -74, 412, 151), Rect2(-204, -72, 386, 145),
		Rect2(-223, -74, 411, 145), Rect2(-213, -71, 397, 132),
		Rect2(-216, -72, 401, 150), Rect2(-215, -72, 400, 136),
		Rect2(-208, -71, 391, 143), Rect2(-213, -72, 399, 142),
		Rect2(-218, -73, 403, 139), Rect2(-214, -72, 399, 147),
		Rect2(-226, -73, 414, 146), Rect2(-215, -72, 400, 152),
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
