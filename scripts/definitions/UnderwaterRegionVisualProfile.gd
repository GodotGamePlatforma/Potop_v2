class_name UnderwaterRegionVisualProfile
extends Resource

@export_group("Identity and depth")
@export var region_id: String = ""
@export var display_name: String = ""
@export_range(0.0, 1.0, 0.001) var start_depth_ratio: float = 0.0
@export_range(0.0, 1.0, 0.001) var end_depth_ratio: float = 1.0

@export_group("Water")
@export var water_near_color: Color = Color(0.035, 0.25, 0.34, 1.0)
@export var water_far_color: Color = Color(0.008, 0.075, 0.12, 1.0)
@export var caustics_color: Color = Color(0.32, 0.78, 0.82, 1.0)
@export_range(0.0, 1.0, 0.01) var water_clarity: float = 0.7
@export_range(0.0, 1.0, 0.01) var caustics_strength: float = 0.35
@export_range(0.0, 1.0, 0.01) var suspended_particle_density: float = 0.35
@export_range(0.0, 1.0, 0.01) var current_distortion_strength: float = 0.25

@export_group("Rock")
@export var rock_base_tint: Color = Color(0.32, 0.4, 0.43, 1.0)
@export var rock_shadow_tint: Color = Color(0.075, 0.11, 0.13, 1.0)
@export var rock_edge_color: Color = Color(0.34, 0.72, 0.75, 1.0)
@export_range(32.0, 1024.0, 1.0, "or_greater") var detail_world_scale: float = 192.0
@export_range(0.0, 1.0, 0.01) var detail_strength: float = 0.68
@export_range(0.25, 8.0, 0.05) var edge_width_texels: float = 1.35
@export_range(0.0, 2.0, 0.01) var edge_highlight_strength: float = 0.65


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var normalized_id := region_id.strip_edges()
	if normalized_id.is_empty():
		errors.append("Region wizualny wymaga stabilnego region_id.")
	elif not _is_valid_id(normalized_id):
		errors.append("region_id może zawierać wyłącznie małe litery ASCII, cyfry i podkreślenia.")
	if display_name.strip_edges().is_empty():
		errors.append("Region wizualny wymaga display_name.")
	if not is_finite(start_depth_ratio) or not is_finite(end_depth_ratio):
		errors.append("Granice głębokości regionu muszą być skończone.")
	elif start_depth_ratio < 0.0 or end_depth_ratio > 1.0 or end_depth_ratio <= start_depth_ratio:
		errors.append("Zakres głębokości regionu musi mieścić się w 0-1 i mieć dodatnią długość.")
	if not _is_opaque(water_near_color) or not _is_opaque(water_far_color):
		errors.append("Kolory wody muszą być nieprzezroczyste.")
	if not _is_opaque(caustics_color):
		errors.append("Kolor caustics musi być nieprzezroczysty.")
	if not _is_opaque(rock_base_tint) or not _is_opaque(rock_shadow_tint) or not _is_opaque(rock_edge_color):
		errors.append("Kolory skały muszą być nieprzezroczyste.")
	if not is_finite(detail_world_scale) or detail_world_scale < 32.0:
		errors.append("Skala detalu skały musi być skończona i wynosić co najmniej 32 jednostki świata.")
	if not is_finite(edge_width_texels) or edge_width_texels < 0.25 or edge_width_texels > 8.0:
		errors.append("Szerokość krawędzi musi mieścić się w zakresie 0,25-8 texeli maski.")
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func contains_depth_ratio(depth_ratio: float) -> bool:
	return depth_ratio >= start_depth_ratio and depth_ratio <= end_depth_ratio


func _is_valid_id(value: String) -> bool:
	for character in value:
		var code := character.unicode_at(0)
		var is_lowercase_ascii := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not is_lowercase_ascii and not is_digit and character != "_":
			return false
	return true


func _is_opaque(color: Color) -> bool:
	return is_equal_approx(color.a, 1.0)
