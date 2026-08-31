class_name WeatherSystem
extends RefCounted

const WeatherStateScript := preload("res://scripts/data/WeatherState.gd")
const StormSystemScript := preload("res://scripts/campaign/StormSystem.gd")

var _storm_system = StormSystemScript.new()

func build_weather(campaign_seed: int, day: int, storm_frequency_multiplier: float = 1.0):
	var result = WeatherStateScript.new()
	result.day = maxi(day, 1)
	var roll := _sample(campaign_seed, result.day, 17)
	if result.day == 1:
		result.condition = WeatherStateScript.Condition.MODERATE
	elif _storm_system.is_storm_day(result.day, storm_frequency_multiplier):
		result.condition = WeatherStateScript.Condition.STORM
	elif _storm_system.is_storm_day(result.day + 1, storm_frequency_multiplier):
		result.condition = WeatherStateScript.Condition.ROUGH
	elif roll < 0.24:
		result.condition = WeatherStateScript.Condition.CALM
	elif roll < 0.73:
		result.condition = WeatherStateScript.Condition.MODERATE
	else:
		result.condition = WeatherStateScript.Condition.ROUGH

	_apply_profile(result, _sample(campaign_seed, result.day, 41))
	var wind_angle := deg_to_rad(lerpf(25.0, 155.0, _sample(campaign_seed, result.day, 83)))
	result.wind_direction = Vector2(cos(wind_angle), sin(wind_angle)).normalized()
	result.ensure_compatibility(result.day)
	return result

func _apply_profile(weather, variation_sample: float) -> void:
	var variation := (variation_sample - 0.5) * 0.06
	match weather.condition:
		WeatherStateScript.Condition.CALM:
			weather.sea_intensity = 0.31 + variation
			weather.rain_intensity = 0.34 + variation * 0.45
			weather.motion_intensity = 0.31 + variation
			weather.foam_intensity = 0.20 + variation * 0.5
			weather.splash_intensity = 0.10
			weather.wave_speed_multiplier = 0.72 + variation * 0.5
		WeatherStateScript.Condition.ROUGH:
			weather.sea_intensity = 0.78 + variation
			weather.rain_intensity = 0.70 + variation * 0.5
			weather.motion_intensity = 0.84 + variation
			weather.foam_intensity = 0.72 + variation * 0.5
			weather.splash_intensity = 0.68
			weather.wave_speed_multiplier = 1.10 + variation * 0.5
		WeatherStateScript.Condition.STORM:
			weather.sea_intensity = 1.0
			weather.rain_intensity = 1.0
			weather.motion_intensity = 1.16
			weather.foam_intensity = 1.0
			weather.splash_intensity = 1.0
			weather.wave_speed_multiplier = 1.34
		_:
			weather.sea_intensity = 0.56 + variation
			weather.rain_intensity = 0.52 + variation * 0.5
			weather.motion_intensity = 0.58 + variation
			weather.foam_intensity = 0.46 + variation * 0.5
			weather.splash_intensity = 0.38
			weather.wave_speed_multiplier = 0.90 + variation * 0.5

func _sample(campaign_seed: int, day: int, salt: int) -> float:
	var mixed := absi(int(campaign_seed) * 92_821 + int(day) * 68_917 + int(salt) * 19_939)
	return float(mixed % 10_000) / 9_999.0
