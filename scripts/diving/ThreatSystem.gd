class_name ThreatSystem
extends RefCounted

func advance_alert(
	current_alert: float,
	delta: float,
	noise_distance: float,
	diver_distance: float,
	noise_level: float,
	light_active: bool,
	definition,
	aggression_multiplier: float = 1.0,
	noise_range_multiplier: float = 1.0,
	alert_decay_multiplier: float = 1.0
) -> float:
	if definition == null:
		return 0.0
	var threshold := float(definition.noise_threshold)
	var noise_ratio := 0.0
	if noise_level > threshold:
		noise_ratio = inverse_lerp(threshold, 100.0, clampf(noise_level, threshold, 100.0))
	var noise_radius := float(definition.noise_detection_radius) \
		* maxf(noise_range_multiplier, 0.0) \
		* lerpf(0.30, 1.0, noise_ratio)
	var noise_stimulus := noise_ratio if noise_ratio > 0.0 and noise_distance <= noise_radius else 0.0
	var light_stimulus := 0.0
	if light_active and diver_distance <= float(definition.light_detection_radius):
		light_stimulus = float(definition.light_sensitivity) \
			* (1.0 - clampf(diver_distance / maxf(float(definition.light_detection_radius), 1.0), 0.0, 1.0))
	var stimulus := maxf(noise_stimulus, light_stimulus)
	if stimulus > 0.0:
		return clampf(
			current_alert + float(definition.alert_rate) * stimulus * maxf(aggression_multiplier, 0.0) * maxf(delta, 0.0),
			0.0,
			100.0
		)
	var decay_amount := float(definition.alert_decay_rate) \
		* maxf(alert_decay_multiplier, 0.0) \
		* maxf(delta, 0.0)
	return maxf(current_alert - decay_amount, 0.0)

func should_warn(alert: float, definition = null, threshold_reduction: float = 0.0) -> bool:
	var threshold := float(definition.warning_threshold) if definition != null else 70.0
	return alert >= maxf(threshold - maxf(threshold_reduction, 0.0), 0.0)

func can_attack(alert: float, diver_distance: float, definition) -> bool:
	return definition != null \
		and alert >= float(definition.attack_threshold) \
		and diver_distance <= float(definition.attack_radius)

func attack_health_damage(definition, aggression_multiplier: float = 1.0) -> int:
	if definition == null:
		return 0
	return maxi(int(ceil(float(definition.attack_health_damage) * maxf(aggression_multiplier, 0.0))), 0)
