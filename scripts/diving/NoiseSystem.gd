class_name NoiseSystem
extends RefCounted

const MAX_NOISE := 100.0
const DECAY_PER_SECOND := 17.0

func noise_for_action(action: String) -> float:
	match action:
		"pry":
			return 72.0
		"cut":
			return 48.0
		"repair":
			return 38.0
		"knife_attack":
			return 8.0
		"harpoon_shot":
			return 64.0
		"sprint":
			return 28.0
		"open":
			return 12.0
		"deploy":
			return 24.0
		"mark":
			return 18.0
		_:
			return 6.0

func add_action_noise(current: float, action: String, multiplier: float = 1.0) -> float:
	return clampf(current + noise_for_action(action) * maxf(multiplier, 0.0), 0.0, MAX_NOISE)

func sustain_action_noise(current: float, action: String, delta: float, multiplier: float = 1.0) -> float:
	var sustain_rate := 16.0 if action == "sprint" else noise_for_action(action) * 0.25
	return clampf(current + sustain_rate * maxf(delta, 0.0) * maxf(multiplier, 0.0), 0.0, MAX_NOISE)

func decay(current: float, delta: float, decay_multiplier: float = 1.0) -> float:
	return maxf(current - DECAY_PER_SECOND * maxf(decay_multiplier, 0.0) * maxf(delta, 0.0), 0.0)

func ratio(current: float) -> float:
	return clampf(current / MAX_NOISE, 0.0, 1.0)
