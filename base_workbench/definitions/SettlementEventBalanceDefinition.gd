class_name SettlementEventBalanceDefinition
extends Resource

const VALID_SAFE_TONES: Array[String] = ["relief", "opportunity", "tradeoff"]
const WeightRuleDefinitionScript := preload("res://base_workbench/definitions/SettlementEventWeightRuleDefinition.gd")

@export_group("Identity")
@export var balance_id: String = "settlement_events_v1"
@export_range(1, 999, 1) var balance_version: int = 1

@export_group("Cadence")
@export_range(1, 9999, 1) var minimum_event_day: int = 3
@export_range(0.0, 100.0, 0.5) var fallback_quiet_day_percentage: float = 45.0
@export_range(0.0, 1.0, 0.01) var minimum_event_probability: float = 0.25
@export_range(0.0, 1.0, 0.01) var maximum_event_probability: float = 0.80
@export_range(0.0, 1.0, 0.01) var maximum_need_probability_bonus: float = 0.20

@export_group("Final weight limits")
@export_range(0.01, 1.0, 0.01) var minimum_weight_multiplier: float = 0.10
@export_range(1.0, 100.0, 0.5) var maximum_weight_multiplier: float = 5.5

@export_group("Critical workforce guarantee")
@export var force_workforce_recovery: bool = true
@export_range(0, 999, 1) var critical_alive_maximum: int = 2
@export_range(0, 999, 1) var critical_healthy_workers_maximum: int = 1
@export_range(0.0, 100.0, 0.05) var forced_minimum_food_days: float = 0.75
@export_range(0, 999, 1) var forced_minimum_free_shelter: int = 2
@export_enum("workforce") var forced_recovery_role: String = "workforce"

@export_group("Recovery morning preference")
@export var recovery_safe_tones: Array[String] = ["relief", "opportunity"]
@export_range(1.0, 100.0, 0.05) var recovery_match_weight_multiplier: float = 2.4
@export_range(1.0, 100.0, 0.05) var preferred_impact_weight_multiplier: float = 1.35

@export_group("Need curves")
@export var trigger_rules: Array[Resource] = []


func configured_trigger_tags() -> Array[String]:
	var result: Array[String] = []
	for rule in trigger_rules:
		if not _is_trigger_rule(rule):
			continue
		var tag := str(rule.trigger_tag)
		if not tag.is_empty() and not result.has(tag):
			result.append(tag)
	result.sort()
	return result


func find_trigger_rule(trigger_tag: String):
	for rule in trigger_rules:
		if _is_trigger_rule(rule) and str(rule.trigger_tag) == trigger_tag:
			return rule
	return null


func evaluate_trigger(trigger_tag: String, metrics: Dictionary) -> Dictionary:
	var rule = find_trigger_rule(trigger_tag)
	if rule == null or not rule.has_method("evaluate"):
		return {
			"trigger_tag": trigger_tag,
			"multiplier": 0.0,
			"curves": [],
			"error": "missing trigger rule",
		}
	return rule.evaluate(metrics)


func validation_errors() -> PackedStringArray:
	var errors: Array[String] = []
	if balance_id.strip_edges().is_empty():
		errors.append("balance_id cannot be empty")
	if balance_version < 1:
		errors.append("balance_version must be at least 1")
	if minimum_event_day < 1:
		errors.append("minimum_event_day must be at least 1")
	_validate_probability(errors, "fallback_quiet_day_percentage", fallback_quiet_day_percentage / 100.0)
	_validate_probability(errors, "minimum_event_probability", minimum_event_probability)
	_validate_probability(errors, "maximum_event_probability", maximum_event_probability)
	_validate_probability(errors, "maximum_need_probability_bonus", maximum_need_probability_bonus)
	if minimum_event_probability > maximum_event_probability:
		errors.append("minimum_event_probability cannot exceed maximum_event_probability")
	if maximum_need_probability_bonus > maximum_event_probability:
		errors.append("maximum_need_probability_bonus cannot exceed maximum_event_probability")
	_validate_positive_float(errors, "minimum_weight_multiplier", minimum_weight_multiplier)
	_validate_positive_float(errors, "maximum_weight_multiplier", maximum_weight_multiplier)
	if maximum_weight_multiplier < minimum_weight_multiplier:
		errors.append("maximum_weight_multiplier cannot be lower than minimum_weight_multiplier")
	if critical_alive_maximum < 0 or critical_healthy_workers_maximum < 0:
		errors.append("critical workforce limits cannot be negative")
	if not is_finite(forced_minimum_food_days) or forced_minimum_food_days < 0.0:
		errors.append("forced_minimum_food_days must be finite and non-negative")
	if forced_minimum_free_shelter < 0:
		errors.append("forced_minimum_free_shelter cannot be negative")
	if forced_recovery_role != "workforce":
		errors.append("forced_recovery_role must be workforce for the critical workforce guarantee")
	_validate_preference_multiplier(errors, "recovery_match_weight_multiplier", recovery_match_weight_multiplier)
	_validate_preference_multiplier(errors, "preferred_impact_weight_multiplier", preferred_impact_weight_multiplier)
	if recovery_safe_tones.is_empty():
		errors.append("recovery_safe_tones cannot be empty")
	var seen_tones: Array[String] = []
	for raw_tone in recovery_safe_tones:
		var tone := str(raw_tone)
		if not VALID_SAFE_TONES.has(tone):
			errors.append("unknown recovery-safe tone: " + tone)
		elif seen_tones.has(tone):
			errors.append("duplicate recovery-safe tone: " + tone)
		else:
			seen_tones.append(tone)
	if trigger_rules.is_empty():
		errors.append("at least one trigger rule is required")
	var seen_tags: Array[String] = []
	for index in range(trigger_rules.size()):
		var rule = trigger_rules[index]
		if not _is_trigger_rule(rule):
			errors.append("trigger rule %d is missing or has the wrong type" % index)
			continue
		for rule_error in rule.validation_errors():
			errors.append("trigger rule %d: %s" % [index, rule_error])
		var tag := str(rule.trigger_tag)
		if seen_tags.has(tag):
			errors.append("duplicate trigger rule: " + tag)
		else:
			seen_tags.append(tag)
	return PackedStringArray(errors)


func is_valid() -> bool:
	return validation_errors().is_empty()


func _validate_positive_float(errors: Array[String], field_name: String, value: float) -> void:
	if not is_finite(value) or value <= 0.0:
		errors.append(field_name + " must be finite and greater than zero")


func _validate_preference_multiplier(errors: Array[String], field_name: String, value: float) -> void:
	if not is_finite(value) or value < 1.0:
		errors.append(field_name + " must be finite and at least one")


func _validate_probability(errors: Array[String], field_name: String, value: float) -> void:
	if not is_finite(value) or value < 0.0 or value > 1.0:
		errors.append(field_name + " must be finite and between zero and one")


func _is_trigger_rule(rule) -> bool:
	return rule != null and rule.get_script() == WeightRuleDefinitionScript
