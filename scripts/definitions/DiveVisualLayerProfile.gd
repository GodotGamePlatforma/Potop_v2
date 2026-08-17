@tool
class_name DiveVisualLayerProfile
extends Resource

## Editor-authoritative presentation contract for one member of the six-layer
## underwater composition. Runtime consumers read it; editor changes emit the
## standard Resource.changed signal so the live composition updates immediately.

const VALID_QUALITY_IDS := [&"low", &"medium", &"high"]

@export_group("Identity")
@export var layer_id: StringName = &"":
	set(value):
		if layer_id == value:
			return
		layer_id = value
		emit_changed()
@export var role: String = "":
	set(value):
		if role == value:
			return
		role = value
		emit_changed()

@export_group("Composition")
@export_range(-4096, 4096, 1) var z_index: int = 0:
	set(value):
		if z_index == value:
			return
		z_index = value
		emit_changed()
@export var normal_scroll_scale: Vector2 = Vector2.ONE:
	set(value):
		if normal_scroll_scale == value:
			return
		normal_scroll_scale = value
		emit_changed()
@export var reduced_motion_scroll_scale: Vector2 = Vector2.ONE:
	set(value):
		if reduced_motion_scroll_scale == value:
			return
		reduced_motion_scroll_scale = value
		emit_changed()
@export var world_locked: bool = false:
	set(value):
		if world_locked == value:
			return
		world_locked = value
		emit_changed()
@export_enum("low", "medium", "high") var minimum_quality: String = "low":
	set(value):
		if minimum_quality == value:
			return
		minimum_quality = value
		emit_changed()


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var normalized_id := String(layer_id).strip_edges()
	if normalized_id.is_empty():
		errors.append("Warstwa wizualna wymaga stabilnego layer_id.")
	elif not _is_valid_id(normalized_id):
		errors.append("layer_id może zawierać wyłącznie litery ASCII, cyfry i podkreślenia.")
	if role.strip_edges().is_empty():
		errors.append("Warstwa %s wymaga opisanej roli kompozycyjnej." % normalized_id)
	if not _is_valid_scroll_scale(normal_scroll_scale):
		errors.append("Warstwa %s ma niepoprawną normal_scroll_scale." % normalized_id)
	if not _is_valid_scroll_scale(reduced_motion_scroll_scale):
		errors.append("Warstwa %s ma niepoprawną reduced_motion_scroll_scale." % normalized_id)
	if world_locked:
		if not normal_scroll_scale.is_equal_approx(Vector2.ONE):
			errors.append("Warstwa world_locked %s musi mieć normal_scroll_scale = Vector2.ONE." % normalized_id)
		if not reduced_motion_scroll_scale.is_equal_approx(Vector2.ONE):
			errors.append("Warstwa world_locked %s musi mieć reduced_motion_scroll_scale = Vector2.ONE." % normalized_id)
	if StringName(normalize_quality(minimum_quality)) != StringName(minimum_quality):
		errors.append("Warstwa %s ma nieznany minimum_quality: %s." % [normalized_id, minimum_quality])
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func minimum_quality_level() -> int:
	return quality_level(minimum_quality)


static func normalize_quality(quality_id: String) -> String:
	var normalized := quality_id.strip_edges().to_lower()
	return normalized if StringName(normalized) in VALID_QUALITY_IDS else "high"


static func quality_level(quality_id: String) -> int:
	match normalize_quality(quality_id):
		"low":
			return 0
		"medium":
			return 1
		_:
			return 2


static func _is_valid_scroll_scale(value: Vector2) -> bool:
	return (
		is_finite(value.x)
		and is_finite(value.y)
		and value.x > 0.0
		and value.y > 0.0
		and value.x <= 2.0
		and value.y <= 2.0
	)


static func _is_valid_id(value: String) -> bool:
	for character in value:
		var code := character.unicode_at(0)
		var is_lowercase_ascii := code >= 97 and code <= 122
		var is_uppercase_ascii := code >= 65 and code <= 90
		var is_digit := code >= 48 and code <= 57
		if not is_lowercase_ascii and not is_uppercase_ascii and not is_digit and character != "_":
			return false
	return true
