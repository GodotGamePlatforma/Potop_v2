class_name DifficultyProfile
extends Resource

const DifficultyMathScript := preload("res://scripts/core/DifficultyMath.gd")

const CURRENT_BALANCE_VERSION: int = 3
const AXIS_GENTLE: int = -1
const AXIS_STANDARD: int = 0
const AXIS_HARSH: int = 1

const _CUSTOM_AXIS_IDS := [
	"starting_resources",
	"food_consumption",
	"economy",
	"society",
	"diving",
	"weather",
	"events",
	"forgiveness",
]

@export_group("Identity")
@export var profile_id: StringName = &"standard"
@export var profile_name: String = "Standard"
@export var available_in_menu: bool = true
@export var balance_version: int = CURRENT_BALANCE_VERSION
@export var configuration_signature: String = ""
@export var snapshot_sealed: bool = false

@export_group("Economy")
@export var starting_food: int = 48
@export var starting_planks: int = 12
@export var starting_scrap: int = 8
@export var food_per_adult: int = 4
@export var loot_density_multiplier: float = 1.0
@export var build_cost_multiplier: float = 1.0
@export var repair_cost_multiplier: float = 1.0

@export_group("Society")
@export var hope_loss_multiplier: float = 1.0
@export var hope_gain_multiplier: float = 1.0
@export var recovery_speed_multiplier: float = 1.0
@export_range(-1, 1, 1) var disease_pressure_modifier: int = 0

@export_group("Diving")
@export var oxygen_use_multiplier: float = 1.0
@export var suit_damage_multiplier: float = 1.0
@export var cold_rate_multiplier: float = 1.0
@export var threat_aggression_multiplier: float = 1.0
@export var current_strength_multiplier: float = 1.0
@export var noise_range_multiplier: float = 1.0
@export var backpack_weight_multiplier: float = 1.0

@export_group("Weather")
@export var storm_frequency_multiplier: float = 1.0
@export var storm_damage_multiplier: float = 1.0

@export_group("Settlement Events")
@export_range(1.0, 100.0, 0.5) var quiet_day_weight: float = 45.0
@export var relief_event_weight_multiplier: float = 1.0
@export var hardship_event_weight_multiplier: float = 1.0

@export_group("Forgiveness")
@export var operator_rescue_chance: float = 0.5


func create_campaign_snapshot() -> DifficultyProfile:
	var snapshot := duplicate(true) as DifficultyProfile
	if snapshot == null:
		return null
	snapshot.resource_local_to_scene = true
	snapshot.resource_name = "%s [%s v%d]" % [profile_name, profile_id, balance_version]
	snapshot.snapshot_sealed = true
	snapshot.configuration_signature = ""
	snapshot.configuration_signature = snapshot.compute_configuration_signature()
	return snapshot


func compute_configuration_signature() -> String:
	var payload := PackedStringArray([
		"profile_id=" + str(profile_id),
		"profile_name=" + profile_name,
		"balance_version=" + str(balance_version),
		"starting_food=" + str(starting_food),
		"starting_planks=" + str(starting_planks),
		"starting_scrap=" + str(starting_scrap),
		"food_per_adult=" + str(food_per_adult),
		"loot_density_multiplier=" + _canonical_float(loot_density_multiplier),
		"build_cost_multiplier=" + _canonical_float(build_cost_multiplier),
		"repair_cost_multiplier=" + _canonical_float(repair_cost_multiplier),
		"hope_loss_multiplier=" + _canonical_float(hope_loss_multiplier),
		"hope_gain_multiplier=" + _canonical_float(hope_gain_multiplier),
		"recovery_speed_multiplier=" + _canonical_float(recovery_speed_multiplier),
		"oxygen_use_multiplier=" + _canonical_float(oxygen_use_multiplier),
		"suit_damage_multiplier=" + _canonical_float(suit_damage_multiplier),
		"cold_rate_multiplier=" + _canonical_float(cold_rate_multiplier),
		"threat_aggression_multiplier=" + _canonical_float(threat_aggression_multiplier),
		"current_strength_multiplier=" + _canonical_float(current_strength_multiplier),
		"noise_range_multiplier=" + _canonical_float(noise_range_multiplier),
		"backpack_weight_multiplier=" + _canonical_float(backpack_weight_multiplier),
		"storm_frequency_multiplier=" + _canonical_float(storm_frequency_multiplier),
		"storm_damage_multiplier=" + _canonical_float(storm_damage_multiplier),
		"quiet_day_weight=" + _canonical_float(quiet_day_weight),
		"relief_event_weight_multiplier=" + _canonical_float(relief_event_weight_multiplier),
		"hardship_event_weight_multiplier=" + _canonical_float(hardship_event_weight_multiplier),
		"operator_rescue_chance=" + _canonical_float(operator_rescue_chance),
	])
	# Balance 1-2 signatures predate the disease axis. Keeping their exact payload
	# allows schema 12 to authenticate the old snapshot before upgrading it.
	if balance_version >= 3:
		payload.append("disease_pressure_modifier=" + str(disease_pressure_modifier))
	return DifficultyMathScript.stable_signature("\n".join(payload))


func has_valid_configuration_signature() -> bool:
	return not configuration_signature.is_empty() \
		and configuration_signature == compute_configuration_signature()


func validation_errors() -> PackedStringArray:
	var errors: Array[String] = []
	if not _is_valid_profile_id(str(profile_id)):
		errors.append("profile_id must use lowercase ASCII letters, digits or underscores and cannot be empty")
	if profile_name.strip_edges().is_empty():
		errors.append("profile_name cannot be empty")
	if balance_version < 1 or balance_version > CURRENT_BALANCE_VERSION:
		errors.append("balance_version must be between 1 and %d" % CURRENT_BALANCE_VERSION)
	_validate_int_range(errors, "starting_food", starting_food, 1, 10_000)
	_validate_int_range(errors, "starting_planks", starting_planks, 0, 10_000)
	_validate_int_range(errors, "starting_scrap", starting_scrap, 0, 10_000)
	_validate_int_range(errors, "food_per_adult", food_per_adult, 1, 100)
	_validate_multiplier(errors, "loot_density_multiplier", loot_density_multiplier)
	_validate_multiplier(errors, "build_cost_multiplier", build_cost_multiplier)
	_validate_multiplier(errors, "repair_cost_multiplier", repair_cost_multiplier)
	_validate_multiplier(errors, "hope_loss_multiplier", hope_loss_multiplier)
	_validate_multiplier(errors, "hope_gain_multiplier", hope_gain_multiplier)
	_validate_multiplier(errors, "recovery_speed_multiplier", recovery_speed_multiplier)
	_validate_int_range(errors, "disease_pressure_modifier", disease_pressure_modifier, AXIS_GENTLE, AXIS_HARSH)
	_validate_multiplier(errors, "oxygen_use_multiplier", oxygen_use_multiplier)
	_validate_multiplier(errors, "suit_damage_multiplier", suit_damage_multiplier)
	_validate_multiplier(errors, "cold_rate_multiplier", cold_rate_multiplier)
	_validate_multiplier(errors, "threat_aggression_multiplier", threat_aggression_multiplier)
	_validate_multiplier(errors, "current_strength_multiplier", current_strength_multiplier)
	_validate_multiplier(errors, "noise_range_multiplier", noise_range_multiplier)
	_validate_multiplier(errors, "backpack_weight_multiplier", backpack_weight_multiplier)
	_validate_multiplier(errors, "storm_frequency_multiplier", storm_frequency_multiplier)
	_validate_multiplier(errors, "storm_damage_multiplier", storm_damage_multiplier)
	_validate_float_range(errors, "quiet_day_weight", quiet_day_weight, 1.0, 100.0)
	_validate_multiplier(errors, "relief_event_weight_multiplier", relief_event_weight_multiplier)
	_validate_multiplier(errors, "hardship_event_weight_multiplier", hardship_event_weight_multiplier)
	_validate_float_range(errors, "operator_rescue_chance", operator_rescue_chance, 0.0, 1.0)
	if snapshot_sealed and configuration_signature.is_empty():
		errors.append("a sealed campaign snapshot must contain configuration_signature")
	elif not configuration_signature.is_empty() and not has_valid_configuration_signature():
		errors.append("configuration_signature does not match the profile values")
	return PackedStringArray(errors)


func is_valid() -> bool:
	return validation_errors().is_empty()


static func custom_axis_ids() -> PackedStringArray:
	return PackedStringArray(_CUSTOM_AXIS_IDS)


static func custom_axis_validation_errors(axes: Dictionary) -> PackedStringArray:
	var errors: Array[String] = []
	for raw_axis_id in axes.keys():
		var axis_id := str(raw_axis_id)
		if not _CUSTOM_AXIS_IDS.has(axis_id):
			errors.append("unknown custom difficulty axis: " + axis_id)
	for axis_id in _CUSTOM_AXIS_IDS:
		if not _has_axis(axes, axis_id):
			continue
		var raw_value: Variant = _axis_variant(axes, axis_id)
		if typeof(raw_value) != TYPE_INT:
			errors.append("custom difficulty axis %s must be an integer -1, 0 or 1" % axis_id)
			continue
		var value := int(raw_value)
		if value < AXIS_GENTLE or value > AXIS_HARSH:
			errors.append("custom difficulty axis %s must be -1, 0 or 1" % axis_id)
	return PackedStringArray(errors)


static func build_custom_profile(axes: Dictionary) -> DifficultyProfile:
	if not custom_axis_validation_errors(axes).is_empty():
		return null
	var profile := DifficultyProfile.new()
	profile.profile_id = &"custom"
	profile.profile_name = "Niestandardowy"
	profile.available_in_menu = true
	profile.balance_version = CURRENT_BALANCE_VERSION
	profile.configuration_signature = ""
	profile.snapshot_sealed = false
	_apply_starting_resources_axis(profile, _axis_value(axes, "starting_resources"))
	_apply_food_consumption_axis(profile, _axis_value(axes, "food_consumption"))
	_apply_economy_axis(profile, _axis_value(axes, "economy"))
	_apply_society_axis(profile, _axis_value(axes, "society"))
	_apply_diving_axis(profile, _axis_value(axes, "diving"))
	_apply_weather_axis(profile, _axis_value(axes, "weather"))
	_apply_events_axis(profile, _axis_value(axes, "events"))
	_apply_forgiveness_axis(profile, _axis_value(axes, "forgiveness"))
	return profile


static func _apply_starting_resources_axis(profile: DifficultyProfile, value: int) -> void:
	match value:
		AXIS_GENTLE:
			profile.starting_food = 72
			profile.starting_planks = 16
			profile.starting_scrap = 10
		AXIS_HARSH:
			profile.starting_food = 36
			profile.starting_planks = 8
			profile.starting_scrap = 5
		_:
			profile.starting_food = 48
			profile.starting_planks = 12
			profile.starting_scrap = 8


static func _apply_food_consumption_axis(profile: DifficultyProfile, value: int) -> void:
	match value:
		AXIS_GENTLE:
			profile.food_per_adult = 3
		AXIS_HARSH:
			profile.food_per_adult = 5
		_:
			profile.food_per_adult = 4


static func _apply_economy_axis(profile: DifficultyProfile, value: int) -> void:
	match value:
		AXIS_GENTLE:
			profile.loot_density_multiplier = 1.2
			profile.build_cost_multiplier = 0.85
			profile.repair_cost_multiplier = 0.8
		AXIS_HARSH:
			profile.loot_density_multiplier = 0.85
			profile.build_cost_multiplier = 1.15
			profile.repair_cost_multiplier = 1.2
		_:
			profile.loot_density_multiplier = 1.0
			profile.build_cost_multiplier = 1.0
			profile.repair_cost_multiplier = 1.0


static func _apply_society_axis(profile: DifficultyProfile, value: int) -> void:
	match value:
		AXIS_GENTLE:
			profile.hope_loss_multiplier = 0.8
			profile.hope_gain_multiplier = 1.15
			profile.recovery_speed_multiplier = 1.2
			profile.disease_pressure_modifier = -1
		AXIS_HARSH:
			profile.hope_loss_multiplier = 1.2
			profile.hope_gain_multiplier = 0.85
			profile.recovery_speed_multiplier = 0.8
			profile.disease_pressure_modifier = 1
		_:
			profile.hope_loss_multiplier = 1.0
			profile.hope_gain_multiplier = 1.0
			profile.recovery_speed_multiplier = 1.0
			profile.disease_pressure_modifier = 0


static func _apply_diving_axis(profile: DifficultyProfile, value: int) -> void:
	match value:
		AXIS_GENTLE:
			profile.oxygen_use_multiplier = 0.85
			profile.suit_damage_multiplier = 0.8
			profile.cold_rate_multiplier = 0.85
			profile.threat_aggression_multiplier = 0.8
			profile.current_strength_multiplier = 0.85
			profile.noise_range_multiplier = 0.85
			profile.backpack_weight_multiplier = 0.9
		AXIS_HARSH:
			profile.oxygen_use_multiplier = 1.15
			profile.suit_damage_multiplier = 1.2
			profile.cold_rate_multiplier = 1.2
			profile.threat_aggression_multiplier = 1.2
			profile.current_strength_multiplier = 1.15
			profile.noise_range_multiplier = 1.15
			profile.backpack_weight_multiplier = 1.1
		_:
			profile.oxygen_use_multiplier = 1.0
			profile.suit_damage_multiplier = 1.0
			profile.cold_rate_multiplier = 1.0
			profile.threat_aggression_multiplier = 1.0
			profile.current_strength_multiplier = 1.0
			profile.noise_range_multiplier = 1.0
			profile.backpack_weight_multiplier = 1.0


static func _apply_weather_axis(profile: DifficultyProfile, value: int) -> void:
	match value:
		AXIS_GENTLE:
			profile.storm_frequency_multiplier = 0.8
			profile.storm_damage_multiplier = 0.8
		AXIS_HARSH:
			profile.storm_frequency_multiplier = 1.2
			profile.storm_damage_multiplier = 1.25
		_:
			profile.storm_frequency_multiplier = 1.0
			profile.storm_damage_multiplier = 1.0


static func _apply_events_axis(profile: DifficultyProfile, value: int) -> void:
	match value:
		AXIS_GENTLE:
			profile.quiet_day_weight = 60.0
			profile.relief_event_weight_multiplier = 1.25
			profile.hardship_event_weight_multiplier = 0.75
		AXIS_HARSH:
			profile.quiet_day_weight = 32.0
			profile.relief_event_weight_multiplier = 0.85
			profile.hardship_event_weight_multiplier = 1.2
		_:
			profile.quiet_day_weight = 45.0
			profile.relief_event_weight_multiplier = 1.0
			profile.hardship_event_weight_multiplier = 1.0


static func _apply_forgiveness_axis(profile: DifficultyProfile, value: int) -> void:
	match value:
		AXIS_GENTLE:
			profile.operator_rescue_chance = 0.65
		AXIS_HARSH:
			profile.operator_rescue_chance = 0.35
		_:
			profile.operator_rescue_chance = 0.5


static func _axis_value(axes: Dictionary, axis_id: String) -> int:
	return int(_axis_variant(axes, axis_id)) if _has_axis(axes, axis_id) else AXIS_STANDARD


static func _has_axis(axes: Dictionary, axis_id: String) -> bool:
	return axes.has(axis_id) or axes.has(StringName(axis_id))


static func _axis_variant(axes: Dictionary, axis_id: String) -> Variant:
	if axes.has(axis_id):
		return axes[axis_id]
	return axes.get(StringName(axis_id), AXIS_STANDARD)


static func _canonical_float(value: float) -> String:
	return "%.6f" % value


static func _is_valid_profile_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var is_lowercase_letter := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if not is_lowercase_letter and not is_digit and code != 95:
			return false
	return true


static func _validate_int_range(
	errors: Array[String],
	field_name: String,
	value: int,
	minimum: int,
	maximum: int
) -> void:
	if value < minimum or value > maximum:
		errors.append("%s must be between %d and %d" % [field_name, minimum, maximum])


static func _validate_multiplier(errors: Array[String], field_name: String, value: float) -> void:
	_validate_float_range(errors, field_name, value, 0.25, 3.0)


static func _validate_float_range(
	errors: Array[String],
	field_name: String,
	value: float,
	minimum: float,
	maximum: float
) -> void:
	if not is_finite(value) or value < minimum or value > maximum:
		errors.append("%s must be between %.2f and %.2f" % [field_name, minimum, maximum])
