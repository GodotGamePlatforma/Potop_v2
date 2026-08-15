class_name SettlementEventWeightRuleDefinition
extends Resource

const WeightCurveDefinitionScript := preload("res://scripts/definitions/SettlementEventWeightCurveDefinition.gd")

@export var trigger_tag: String = ""
@export_range(0.0, 1.0, 0.01) var event_probability_bonus: float = 0.0
@export_range(1.0, 100.0, 0.01) var bonus_activation_multiplier: float = 1.01
@export var required_available_impact_tags: Array[String] = []
@export var curves: Array[Resource] = []


func evaluate(metrics: Dictionary) -> Dictionary:
	var multiplier := 1.0
	var curve_breakdown: Array[Dictionary] = []
	for curve in curves:
		if curve == null or curve.get_script() != WeightCurveDefinitionScript:
			continue
		var curve_result: Dictionary = curve.evaluate(metrics)
		multiplier *= float(curve_result.get("multiplier", 1.0))
		curve_breakdown.append(curve_result)
	return {
		"trigger_tag": trigger_tag,
		"multiplier": multiplier,
		"curves": curve_breakdown,
	}


func validation_errors() -> PackedStringArray:
	var errors: Array[String] = []
	if trigger_tag.strip_edges().is_empty():
		errors.append("trigger_tag cannot be empty")
	if not is_finite(event_probability_bonus) or event_probability_bonus < 0.0 or event_probability_bonus > 1.0:
		errors.append("event_probability_bonus must be finite and between zero and one")
	if not is_finite(bonus_activation_multiplier) or bonus_activation_multiplier < 1.0:
		errors.append("bonus_activation_multiplier must be finite and at least one")
	elif event_probability_bonus > 0.0 and is_equal_approx(bonus_activation_multiplier, 1.0):
		errors.append("bonus_activation_multiplier must exceed one when event_probability_bonus is positive")
	if required_available_impact_tags.is_empty():
		errors.append("at least one required_available_impact_tag is required")
	var seen_impact_tags: Array[String] = []
	for raw_tag in required_available_impact_tags:
		var impact_tag := str(raw_tag)
		if impact_tag.is_empty():
			errors.append("required_available_impact_tags cannot contain an empty tag")
		elif seen_impact_tags.has(impact_tag):
			errors.append("duplicate required_available_impact_tag: " + impact_tag)
		else:
			seen_impact_tags.append(impact_tag)
	if curves.is_empty():
		errors.append("at least one curve is required")
	var metrics: Array[String] = []
	for index in range(curves.size()):
		var curve = curves[index]
		if curve == null or curve.get_script() != WeightCurveDefinitionScript:
			errors.append("curve %d is missing or has the wrong type" % index)
			continue
		for curve_error in curve.validation_errors():
			errors.append("curve %d: %s" % [index, curve_error])
		var metric := str(curve.metric)
		if metrics.has(metric):
			errors.append("duplicate metric curve: " + metric)
		else:
			metrics.append(metric)
	return PackedStringArray(errors)


func is_valid() -> bool:
	return validation_errors().is_empty()
