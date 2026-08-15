class_name DiveScoutRuntime
extends RefCounted


const FALLBACK_REVEAL_SECONDS := 1.5
const FALLBACK_MAXIMUM_DISTANCE := 640.0
const FALLBACK_MINIMUM_CURRENT_SPEED := 60.0


var stationary_time: float = 0.0


func reset() -> void:
	stationary_time = 0.0


func advance(
	eligible: bool,
	delta: float,
	signal_query: Callable,
	reveal_seconds: float = FALLBACK_REVEAL_SECONDS
) -> Dictionary:
	if not eligible:
		reset()
		return {}
	stationary_time += maxf(delta, 0.0)
	if stationary_time < maxf(reveal_seconds, 0.01) or not signal_query.is_valid():
		return {}
	var signal_result = signal_query.call()
	if not signal_result is Dictionary:
		return {}
	return signal_result.duplicate(true)


func progress_ratio(reveal_seconds: float = FALLBACK_REVEAL_SECONDS) -> float:
	return clampf(stationary_time / maxf(reveal_seconds, 0.01), 0.0, 1.0)
