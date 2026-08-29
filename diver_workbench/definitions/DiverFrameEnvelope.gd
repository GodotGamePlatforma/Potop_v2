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
const BODY_ANIMATIONS: Array[StringName] = [
	&"idle",
	&"swim",
	&"sprint",
	&"transition_idle_swim",
	&"transition_idle_sprint",
	&"transition_swim_sprint",
]
const ACTION_ANIMATIONS: Array[StringName] = [&"knife_swing"]
const REQUIRED_ANIMATIONS: Array[StringName] = BODY_ANIMATIONS + ACTION_ANIMATIONS

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
	&"transition_idle_swim": [
		Rect2(-174, -99, 413, 172), Rect2(-166, -98, 398, 170),
		Rect2(-163, -98, 395, 169), Rect2(-153, -98, 377, 168),
		Rect2(-161, -98, 394, 168), Rect2(-159, -98, 391, 167),
		Rect2(-151, -98, 377, 167), Rect2(-154, -97, 386, 164),
		Rect2(-152, -97, 383, 163), Rect2(-153, -98, 386, 165),
		Rect2(-150, -97, 382, 162), Rect2(-146, -98, 377, 164),
		Rect2(-153, -97, 391, 162), Rect2(-151, -98, 389, 163),
		Rect2(-148, -97, 385, 160), Rect2(-148, -98, 387, 162),
	],
	&"transition_idle_sprint": [
		Rect2(-179, -98, 418, 177), Rect2(-171, -97, 402, 174),
		Rect2(-164, -97, 387, 174), Rect2(-162, -97, 382, 174),
		Rect2(-164, -97, 386, 173), Rect2(-162, -97, 381, 174),
		Rect2(-163, -97, 383, 173), Rect2(-168, -97, 392, 172),
		Rect2(-167, -97, 389, 172), Rect2(-160, -97, 374, 172),
		Rect2(-172, -97, 398, 171), Rect2(-166, -96, 386, 170),
		Rect2(-181, -97, 414, 171), Rect2(-179, -97, 410, 171),
		Rect2(-184, -97, 420, 170), Rect2(-188, -98, 427, 172),
	],
	&"transition_swim_sprint": [
		Rect2(-158, -97, 397, 188), Rect2(-159, -87, 398, 167),
		Rect2(-160, -91, 398, 174), Rect2(-161, -88, 399, 167),
		Rect2(-162, -87, 401, 163), Rect2(-151, -96, 377, 180),
		Rect2(-150, -96, 374, 179), Rect2(-166, -93, 404, 172),
		Rect2(-160, -95, 391, 175), Rect2(-169, -94, 408, 172),
		Rect2(-165, -96, 399, 174), Rect2(-167, -95, 402, 171),
		Rect2(-173, -93, 412, 167), Rect2(-171, -94, 408, 168),
		Rect2(-174, -95, 413, 168), Rect2(-177, -96, 417, 169),
	],
	&"knife_swing": [
		Rect2(-111, -75, 209, 181), Rect2(-116, -67, 219, 169),
		Rect2(-122, -58, 230, 153), Rect2(-127, -47, 241, 134),
		Rect2(-131, -34, 250, 110), Rect2(-134, -24, 257, 88),
		Rect2(-134, -25, 260, 76), Rect2(-133, -28, 260, 66),
		Rect2(-130, -35, 258, 74), Rect2(-132, -29, 259, 66),
		Rect2(-134, -25, 260, 70), Rect2(-134, -24, 258, 82),
		Rect2(-132, -29, 253, 100), Rect2(-128, -43, 244, 127),
		Rect2(-122, -58, 230, 153), Rect2(-114, -71, 214, 175),
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
	for animation_name: StringName in REQUIRED_ANIMATIONS:
		var frames: Array = FRAME_BOUNDS.get(animation_name, [])
		if frames.size() != 16:
			errors.append("%s must expose exactly 16 measured alpha bounds." % animation_name)
			continue
		for frame in range(frames.size()):
			var bounds: Rect2 = frames[frame]
			if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
				errors.append("%s frame %d has an empty alpha envelope." % [animation_name, frame])
	return errors
