class_name SettlementEventWeightBandDefinition
extends Resource

@export var label: String = ""
@export var minimum_enabled: bool = false
@export var minimum_value: float = 0.0
@export var minimum_inclusive: bool = true
@export var maximum_enabled: bool = false
@export var maximum_value: float = 0.0
@export var maximum_inclusive: bool = false
@export_range(0.01, 100.0, 0.01) var multiplier: float = 1.0


func matches(value: float) -> bool:
	if minimum_enabled:
		if value < minimum_value or (is_equal_approx(value, minimum_value) and not minimum_inclusive):
			return false
	if maximum_enabled:
		if value > maximum_value or (is_equal_approx(value, maximum_value) and not maximum_inclusive):
			return false
	return true


func overlaps(other) -> bool:
	if other == null:
		return false
	if maximum_enabled and bool(other.minimum_enabled):
		var other_minimum := float(other.minimum_value)
		if maximum_value < other_minimum:
			return false
		if is_equal_approx(maximum_value, other_minimum) and not (maximum_inclusive and bool(other.minimum_inclusive)):
			return false
	if bool(other.maximum_enabled) and minimum_enabled:
		var other_maximum := float(other.maximum_value)
		if other_maximum < minimum_value:
			return false
		if is_equal_approx(other_maximum, minimum_value) and not (bool(other.maximum_inclusive) and minimum_inclusive):
			return false
	return true


func validation_errors() -> PackedStringArray:
	var errors: Array[String] = []
	if label.strip_edges().is_empty():
		errors.append("label cannot be empty")
	if not minimum_enabled and not maximum_enabled:
		errors.append("at least one interval bound must be enabled")
	if minimum_enabled and not is_finite(minimum_value):
		errors.append("minimum_value must be finite")
	if maximum_enabled and not is_finite(maximum_value):
		errors.append("maximum_value must be finite")
	if minimum_enabled and maximum_enabled:
		if minimum_value > maximum_value:
			errors.append("minimum_value cannot exceed maximum_value")
		elif is_equal_approx(minimum_value, maximum_value) and not (minimum_inclusive and maximum_inclusive):
			errors.append("equal bounds must both be inclusive")
	if not is_finite(multiplier) or multiplier <= 0.0:
		errors.append("multiplier must be finite and greater than zero")
	return PackedStringArray(errors)


func is_valid() -> bool:
	return validation_errors().is_empty()
