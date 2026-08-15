class_name WeatherState
extends Resource

enum Condition {
	CALM,
	MODERATE,
	ROUGH,
	STORM,
}

@export var day: int = 1
@export var condition: int = Condition.MODERATE
@export_range(0.0, 1.0) var sea_intensity: float = 0.56
@export_range(0.0, 1.0) var rain_intensity: float = 0.52
@export_range(0.0, 1.4) var motion_intensity: float = 0.58
@export_range(0.0, 1.0) var foam_intensity: float = 0.46
@export_range(0.0, 1.0) var splash_intensity: float = 0.38
@export_range(0.5, 1.5) var wave_speed_multiplier: float = 0.90
@export var wind_direction: Vector2 = Vector2(0.76, 0.65)

func ensure_compatibility(current_day: int) -> void:
	day = maxi(current_day, 1)
	condition = clampi(condition, Condition.CALM, Condition.STORM)
	sea_intensity = clampf(sea_intensity, 0.0, 1.0)
	rain_intensity = clampf(rain_intensity, 0.0, 1.0)
	motion_intensity = clampf(motion_intensity, 0.0, 1.4)
	foam_intensity = clampf(foam_intensity, 0.0, 1.0)
	splash_intensity = clampf(splash_intensity, 0.0, 1.0)
	wave_speed_multiplier = clampf(wave_speed_multiplier, 0.5, 1.5)
	if wind_direction.length_squared() < 0.001:
		wind_direction = Vector2(0.76, 0.65)
	wind_direction = wind_direction.normalized()

func is_storm() -> bool:
	return condition == Condition.STORM

func condition_id() -> String:
	match condition:
		Condition.CALM:
			return "calm"
		Condition.ROUGH:
			return "rough"
		Condition.STORM:
			return "storm"
		_:
			return "moderate"

func display_name() -> String:
	match condition:
		Condition.CALM:
			return "Spokojne morze"
		Condition.ROUGH:
			return "Wzburzone morze"
		Condition.STORM:
			return "Sztorm"
		_:
			return "Umiarkowane fale"
