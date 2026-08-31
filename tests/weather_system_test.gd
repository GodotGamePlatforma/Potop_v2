extends SceneTree

const WeatherSystemScript := preload("res://scripts/campaign/WeatherSystem.gd")
const WeatherStateScript := preload("res://scripts/data/WeatherState.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")

var _failures := 0

func _initialize() -> void:
	var system = WeatherSystemScript.new()
	var first = system.build_weather(12_345, 2, 1.0)
	var repeated = system.build_weather(12_345, 2, 1.0)
	_assert(first.condition == repeated.condition, "Ten sam seed i dzien musza odtwarzac ten sam rodzaj pogody.")
	_assert(is_equal_approx(first.sea_intensity, repeated.sea_intensity), "Intensywnosc morza musi byc deterministyczna.")
	_assert(first.wind_direction.is_equal_approx(repeated.wind_direction), "Kierunek wiatru musi byc deterministyczny.")
	_assert(is_equal_approx(first.wind_direction.length(), 1.0), "Kierunek wiatru musi byc znormalizowany.")

	var day_one = system.build_weather(12_345, 1, 1.0)
	_assert(day_one.condition == WeatherStateScript.Condition.MODERATE, "Pierwszy dzien tutoriala powinien miec czytelne umiarkowane fale.")
	var pre_storm = system.build_weather(12_345, 3, 1.0)
	var storm = system.build_weather(12_345, 4, 1.0)
	_assert(pre_storm.condition == WeatherStateScript.Condition.ROUGH, "Dzien przed standardowym sztormem powinien wizualnie zapowiadac pogorszenie.")
	_assert(storm.condition == WeatherStateScript.Condition.STORM and storm.is_storm(), "Czwarty dzien standardowego profilu musi pozostac dniem sztormowym.")
	var easy_pre_storm = system.build_weather(12_345, 4, 0.8)
	var easy_storm = system.build_weather(12_345, 5, 0.8)
	_assert(easy_pre_storm.condition == WeatherStateScript.Condition.ROUGH, "Latwy profil powinien zapowiadac pozniejszy sztorm.")
	_assert(easy_storm.condition == WeatherStateScript.Condition.STORM, "Latwy profil musi zachowac interwal sztormu wynikajacy z mnoznika.")

	var state = GameStateScript.new()
	state.setup_new_campaign(12_345, DifficultyProfileScript.new())
	_assert(state.weather != null and state.weather.day == state.day, "Nowa kampania musi zapisac migawke pogody biezacego dnia.")
	state.day = 4
	var incompatible_errors: PackedStringArray = state.persistence_validation_errors()
	_assert(not incompatible_errors.is_empty() and state.weather.day == 1, "Biezacy schemat z pogoda innego dnia musi zostac odrzucony bez cichej reinterpretacji migawki.")
	state.prepare_weather_for_day()
	_assert(state.weather.day == 4 and state.weather.is_storm(), "Jawne przygotowanie nowego dnia musi odtworzyc zgodna migawke pogody.")

	if _failures > 0:
		push_error("Weather system test failed with %d assertion(s)." % _failures)
		quit(1)
		return
	print("Weather system test passed: deterministic daily profiles, storm schedule and GameState snapshot work.")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Weather system test failed: " + message)
