class_name DiveLightingDefinition
extends Resource

@export var shallow_visibility_max_depth: float = 35.0
@export var deep_darkness_min_depth: float = 160.0
@export var shallow_ambient_color: Color = Color.WHITE
@export var deep_ambient_color: Color = Color(0.58, 0.58, 0.58, 1.0)
@export_range(0.25, 4.0, 0.05) var transition_power: float = 1.0


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if shallow_visibility_max_depth < 0.0:
		errors.append("Granica pełnej widoczności nie może być ujemna")
	if deep_darkness_min_depth <= shallow_visibility_max_depth:
		errors.append("Granica głębokiej ciemności musi leżeć poniżej granicy pełnej widoczności")
	if transition_power < 0.25 or transition_power > 4.0:
		errors.append("Potęga przejścia musi mieścić się w zakresie 0,25-4,0")
	if not is_equal_approx(shallow_ambient_color.a, 1.0) or not is_equal_approx(deep_ambient_color.a, 1.0):
		errors.append("Kolory ambientu muszą być nieprzezroczyste")
	if _channel_spread(shallow_ambient_color) > 0.001 or _channel_spread(deep_ambient_color) > 0.001:
		errors.append("Ambient steruje wyłącznie ekspozycją i musi pozostać achromatyczny")
	if _relative_luminance(shallow_ambient_color) <= _relative_luminance(deep_ambient_color):
		errors.append("Płytki ambient musi być jaśniejszy od głębokiego")
	return errors


func _relative_luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _channel_spread(color: Color) -> float:
	return maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b))
