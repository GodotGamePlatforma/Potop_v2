class_name DiverSocketProfile
extends Resource

## Authored attachment points for the flattened diver animation.
##
## Coordinates are expressed in centered frame pixels, before the
## AnimatedSprite2D scale is applied. Sampling is deliberately discrete: the
## visible bitmap changes on frame boundaries, so interpolating a socket while
## the source frame is still static would make the attachment visibly slide.

const REQUIRED_ANIMATIONS: Array[StringName] = [&"idle", &"swim", &"sprint"]
const REQUIRED_SOCKETS: Array[StringName] = [
	&"breath",
	&"fin_upper",
	&"fin_lower",
	&"tool_hand",
	&"lamp",
	&"leak_valve",
]

@export var frame_size := Vector2i(512, 256)
@export_range(1, 64, 1) var frame_count := 16

@export_group("Idle")
@export var idle_breath := PackedVector2Array()
@export var idle_fin_upper := PackedVector2Array()
@export var idle_fin_lower := PackedVector2Array()
@export var idle_tool_hand := PackedVector2Array()
@export var idle_lamp := PackedVector2Array()
@export var idle_leak_valve := PackedVector2Array()

@export_group("Swim")
@export var swim_breath := PackedVector2Array()
@export var swim_fin_upper := PackedVector2Array()
@export var swim_fin_lower := PackedVector2Array()
@export var swim_tool_hand := PackedVector2Array()
@export var swim_lamp := PackedVector2Array()
@export var swim_leak_valve := PackedVector2Array()

@export_group("Sprint")
@export var sprint_breath := PackedVector2Array()
@export var sprint_fin_upper := PackedVector2Array()
@export var sprint_fin_lower := PackedVector2Array()
@export var sprint_tool_hand := PackedVector2Array()
@export var sprint_lamp := PackedVector2Array()
@export var sprint_leak_valve := PackedVector2Array()


func points_for(animation_name: StringName, socket_id: StringName) -> PackedVector2Array:
	if animation_name not in REQUIRED_ANIMATIONS or socket_id not in REQUIRED_SOCKETS:
		return PackedVector2Array()
	var value: Variant = get("%s_%s" % [String(animation_name), String(socket_id)])
	return value if value is PackedVector2Array else PackedVector2Array()


func position_for(
	animation_name: StringName,
	socket_id: StringName,
	frame: int,
	flip_h: bool = false
) -> Vector2:
	var points := points_for(animation_name, socket_id)
	if points.is_empty():
		return Vector2.ZERO
	var result := points[clampi(frame, 0, points.size() - 1)]
	if flip_h:
		result.x = -result.x
	return result


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if frame_size.x <= 0 or frame_size.y <= 0:
		errors.append("Frame size must be positive.")
	if frame_count <= 0:
		errors.append("Frame count must be positive.")
	var half_extent := Vector2(frame_size) * 0.5
	for animation_name in REQUIRED_ANIMATIONS:
		for socket_id in REQUIRED_SOCKETS:
			var points := points_for(animation_name, socket_id)
			if points.size() != frame_count:
				errors.append(
					"%s/%s contains %d samples; expected %d."
					% [animation_name, socket_id, points.size(), frame_count]
				)
				continue
			for frame in range(points.size()):
				var point := points[frame]
				if (
					not is_finite(point.x)
					or not is_finite(point.y)
					or absf(point.x) > half_extent.x
					or absf(point.y) > half_extent.y
				):
					errors.append(
						"%s/%s frame %d lies outside the authored frame: %s."
						% [animation_name, socket_id, frame, point]
					)
	return errors
