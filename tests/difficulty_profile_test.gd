extends SceneTree

const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const DifficultyMathScript := preload("res://scripts/core/DifficultyMath.gd")
const GameDatabaseScript := preload("res://scripts/core/GameDatabase.gd")
const EasyProfile := preload("res://data/difficulty/easy.tres")
const StandardProfile := preload("res://data/difficulty/standard.tres")
const HardProfile := preload("res://data/difficulty/hard.tres")
const CustomProfile := preload("res://data/difficulty/custom.tres")

const BALANCE_FIELDS := [
	"starting_food",
	"starting_planks",
	"starting_scrap",
	"food_per_adult",
	"loot_density_multiplier",
	"build_cost_multiplier",
	"repair_cost_multiplier",
	"hope_loss_multiplier",
	"hope_gain_multiplier",
	"recovery_speed_multiplier",
	"disease_pressure_modifier",
	"oxygen_use_multiplier",
	"suit_damage_multiplier",
	"cold_rate_multiplier",
	"threat_aggression_multiplier",
	"current_strength_multiplier",
	"noise_range_multiplier",
	"backpack_weight_multiplier",
	"storm_frequency_multiplier",
	"storm_damage_multiplier",
	"quiet_day_weight",
	"relief_event_weight_multiplier",
	"hardship_event_weight_multiplier",
	"operator_rescue_chance",
]

const STORED_PROFILE_FIELDS := [
	"profile_id",
	"profile_name",
	"available_in_menu",
	"balance_version",
	"configuration_signature",
	"snapshot_sealed",
]

var _failed := false


func _initialize() -> void:
	_test_authored_profiles()
	_test_authored_profile_files_are_explicit()
	_test_campaign_snapshot()
	_test_validation()
	_test_custom_profile_builder()
	_test_difficulty_math()
	_test_database_id_index()
	if _failed:
		quit(1)
		return
	print("Difficulty profile test passed: authored profiles, sealed snapshots, custom axes, signatures and deterministic scaling are valid.")
	quit(0)


func _test_authored_profiles() -> void:
	var profiles := [EasyProfile, StandardProfile, HardProfile, CustomProfile]
	var expected_ids := [&"easy", &"standard", &"hard", &"custom"]
	var expected_disease_pressure := [-1, 0, 1, 0]
	var signatures: Array[String] = []
	for index in range(profiles.size()):
		var profile = profiles[index]
		_assert(profile.profile_id == expected_ids[index], "Every authored profile must have its stable profile_id.")
		_assert(profile.disease_pressure_modifier == expected_disease_pressure[index], "Authored profile %s must use the approved Society disease-pressure modifier %d." % [profile.profile_id, expected_disease_pressure[index]])
		_assert(profile.balance_version == DifficultyProfileScript.CURRENT_BALANCE_VERSION, "Every authored profile must declare the current balance version explicitly.")
		_assert(not profile.snapshot_sealed, "Database definitions must remain editable source resources, not campaign snapshots.")
		_assert(profile.validation_errors().is_empty(), "Authored profile %s must pass full validation: %s" % [profile.profile_name, "; ".join(profile.validation_errors())])
		var signature: String = profile.compute_configuration_signature()
		_assert(signature.length() == 64, "A profile signature must be a complete SHA-256 hex digest.")
		signatures.append(signature)
	_assert(signatures[0] != signatures[1] and signatures[1] != signatures[2] and signatures[0] != signatures[2], "Public profiles with different balance must have different signatures.")
	_assert(EasyProfile.quiet_day_weight > StandardProfile.quiet_day_weight and StandardProfile.quiet_day_weight > HardProfile.quiet_day_weight, "Public profiles must produce a real gentle-to-harsh quiet-day cadence.")
	_assert(EasyProfile.relief_event_weight_multiplier > HardProfile.relief_event_weight_multiplier, "Gentle difficulty must favor relief events more strongly than harsh difficulty.")
	_assert(EasyProfile.hardship_event_weight_multiplier < HardProfile.hardship_event_weight_multiplier, "Harsh difficulty must favor hardship events more strongly than gentle difficulty.")


func _test_database_id_index() -> void:
	var database = GameDatabaseScript.new()
	database.load_definitions()
	_assert(database.get_difficulty_profile("easy") == database.difficulty_profiles.get("Lagodny"), "Stable profile_id must resolve independently of the Polish display label.")
	_assert(database.get_difficulty_profile("standard") == database.get_standard_difficulty(), "Standard lookup must use profile_id as the canonical key.")
	_assert(database.available_difficulty_profiles().size() == 4, "The menu-facing ID index must expose all four authored profiles exactly once.")
	database.free()


func _test_authored_profile_files_are_explicit() -> void:
	for file_name in ["easy.tres", "standard.tres", "hard.tres", "custom.tres"]:
		var source := FileAccess.get_file_as_string("res://data/difficulty/" + file_name)
		_assert(not source.is_empty(), "Authored difficulty file must be readable: " + file_name)
		for field_name in STORED_PROFILE_FIELDS + BALANCE_FIELDS:
			_assert(source.contains("\n%s = " % field_name), "Authored profile %s must explicitly declare %s instead of inheriting a script default." % [file_name, field_name])


func _test_campaign_snapshot() -> void:
	var snapshot = EasyProfile.create_campaign_snapshot()
	var repeated = EasyProfile.create_campaign_snapshot()
	_assert(snapshot != null and snapshot != EasyProfile, "Campaign setup must receive a detached DifficultyProfile instance.")
	_assert(snapshot.resource_path.is_empty(), "A campaign snapshot must not retain the database resource path.")
	_assert(snapshot.snapshot_sealed, "A campaign snapshot must be marked as sealed.")
	_assert(snapshot.has_valid_configuration_signature(), "A newly created campaign snapshot must contain a matching signature.")
	_assert(snapshot.validation_errors().is_empty(), "A newly created campaign snapshot must pass validation.")
	_assert(snapshot.configuration_signature == repeated.configuration_signature, "The same profile values must always produce the same campaign signature.")
	var source_food: int = EasyProfile.starting_food
	snapshot.starting_food += 1
	_assert(EasyProfile.starting_food == source_food, "Changing a detached snapshot must never mutate the database definition.")
	_assert(not snapshot.has_valid_configuration_signature(), "Any balance mutation after sealing must invalidate the snapshot signature.")
	_assert(not snapshot.validation_errors().is_empty(), "A mutated sealed snapshot must fail validation instead of silently changing campaign rules.")


func _test_validation() -> void:
	var invalid = StandardProfile.duplicate(true)
	invalid.profile_id = &"Bad Id"
	invalid.starting_food = 0
	invalid.oxygen_use_multiplier = 0.0
	invalid.quiet_day_weight = 0.0
	invalid.operator_rescue_chance = 1.1
	_assert(invalid.validation_errors().size() == 5, "Full validation must report identity, resources, multiplier, event cadence and chance errors together.")
	var signed = StandardProfile.create_campaign_snapshot()
	signed.profile_name = "Changed after start"
	_assert(not signed.is_valid(), "Display identity is part of the frozen campaign configuration and must be signature-protected.")
	var different = StandardProfile.duplicate(true)
	var original_signature: String = different.compute_configuration_signature()
	different.build_cost_multiplier = 1.01
	_assert(different.compute_configuration_signature() != original_signature, "Changing any balance field must change the stable signature.")


func _test_custom_profile_builder() -> void:
	var standard_axes: Dictionary = {}
	for axis_id in DifficultyProfileScript.custom_axis_ids():
		standard_axes[axis_id] = DifficultyProfileScript.AXIS_STANDARD
	var custom_standard = DifficultyProfileScript.build_custom_profile(standard_axes)
	_assert(custom_standard != null and custom_standard.is_valid(), "A complete standard custom configuration must build a valid profile.")
	_assert(custom_standard.profile_id == &"custom" and custom_standard.available_in_menu, "The configurator must produce a public custom definition with stable identity.")
	_assert_balance_equal(custom_standard, StandardProfile, "All standard custom axes must reproduce Standard balance.")
	for society_value in [DifficultyProfileScript.AXIS_GENTLE, DifficultyProfileScript.AXIS_STANDARD, DifficultyProfileScript.AXIS_HARSH]:
		var society_axes := standard_axes.duplicate()
		society_axes["society"] = society_value
		var society_profile = DifficultyProfileScript.build_custom_profile(society_axes)
		_assert(society_profile != null and society_profile.disease_pressure_modifier == society_value, "The Society axis %d must map directly to disease pressure %d." % [society_value, society_value])
	for axis_id in DifficultyProfileScript.custom_axis_ids():
		if axis_id == "society":
			continue
		var unrelated_axes := standard_axes.duplicate()
		unrelated_axes[axis_id] = DifficultyProfileScript.AXIS_HARSH
		var unrelated_profile = DifficultyProfileScript.build_custom_profile(unrelated_axes)
		_assert(unrelated_profile != null and unrelated_profile.disease_pressure_modifier == 0, "Changing non-Society axis %s must not change disease pressure." % axis_id)

	var gentle_axes: Dictionary = {}
	var harsh_axes: Dictionary = {}
	for axis_id in DifficultyProfileScript.custom_axis_ids():
		gentle_axes[axis_id] = DifficultyProfileScript.AXIS_GENTLE
		harsh_axes[axis_id] = DifficultyProfileScript.AXIS_HARSH
	var gentle = DifficultyProfileScript.build_custom_profile(gentle_axes)
	var harsh = DifficultyProfileScript.build_custom_profile(harsh_axes)
	_assert(gentle.food_per_adult == 3 and harsh.food_per_adult == 5, "The custom food-consumption axis must really change daily food use without changing public presets.")
	for field_name in BALANCE_FIELDS:
		if field_name == "food_per_adult":
			continue
		_assert_values_equal(gentle.get(field_name), EasyProfile.get(field_name), "Gentle custom axis must match the gentle preset for %s." % field_name)
		_assert_values_equal(harsh.get(field_name), HardProfile.get(field_name), "Harsh custom axis must match the harsh preset for %s." % field_name)
	_assert(gentle.compute_configuration_signature() != harsh.compute_configuration_signature(), "Different custom configurations must have different signatures.")

	var mixed = DifficultyProfileScript.build_custom_profile({
		"starting_resources": -1,
		"food_consumption": 1,
		"economy": 1,
		"society": -1,
		"diving": 0,
		"weather": 1,
		"events": -1,
		"forgiveness": 0,
	})
	_assert(mixed.starting_food == 72 and mixed.food_per_adult == 5, "Starting resources and food consumption must be independent custom axes.")
	_assert(is_equal_approx(mixed.build_cost_multiplier, 1.15) and is_equal_approx(mixed.recovery_speed_multiplier, 1.2), "Economy and society axes must compose without overwriting one another.")
	_assert(is_equal_approx(mixed.oxygen_use_multiplier, 1.0) and is_equal_approx(mixed.storm_damage_multiplier, 1.25), "Diving and weather axes must compose independently.")
	_assert(is_equal_approx(mixed.quiet_day_weight, 60.0) and is_equal_approx(mixed.operator_rescue_chance, 0.5), "Event and forgiveness axes must compose independently.")
	_assert(DifficultyProfileScript.build_custom_profile({"economy": 2}) == null, "Out-of-range custom axes must be rejected instead of silently clamped.")
	_assert(DifficultyProfileScript.build_custom_profile({"economyy": 0}) == null, "Unknown custom axes must be rejected instead of silently ignored.")


func _test_difficulty_math() -> void:
	_assert(DifficultyMathScript.scale_cost_amount(1, 1.2) == 1, "A 20 percent surcharge must not turn a base cost of one into two.")
	_assert(DifficultyMathScript.scale_cost_amount(6, 1.15) == 7, "Ordinary cost scaling must round to the nearest whole unit.")
	_assert(DifficultyMathScript.scale_cost_amount(2, 0.85) == 2, "A positive cost must remain at least one and use nearest rounding.")
	_assert(DifficultyMathScript.scale_cost_amount(0, 1.2) == 0, "A zero base cost must remain zero.")
	var base_cost := {"scrap": 1, "planks": 6}
	var scaled_cost: Dictionary = DifficultyMathScript.scale_cost(base_cost, 1.2)
	_assert(scaled_cost == {"scrap": 1, "planks": 7}, "Dictionary cost scaling must apply the same rule to every component.")
	_assert(base_cost == {"scrap": 1, "planks": 6}, "Cost scaling must not mutate authored definition data.")

	var first_roll := DifficultyMathScript.scale_loot_amount(1, 0.85, 1234, "cache_17", "scrap")
	for repeat_index in range(10):
		_assert(DifficultyMathScript.scale_loot_amount(1, 0.85, 1234, "cache_17", "scrap") == first_roll, "Fractional loot rounding must be stable for the same campaign and IDs.")
	_assert(DifficultyMathScript.scale_loot_amount(4, 1.25, 99, "cache", "food") == 5, "Integral scaled loot amounts must not depend on the random sample.")
	_assert(DifficultyMathScript.scale_loot_amount(1, 0.1, 99, "cache", "food", 1) == 1, "Explicit protected loot may request a positive minimum.")
	_assert(DifficultyMathScript.scale_loot_amount(0, 1.2, 99, "cache", "food", 1) == 0, "A protected minimum must never create loot from an empty authored stack.")
	_assert(DifficultyMathScript.minimum_loot_amount(2, 0.85, 1) == 1, "The seed-independent loot floor must use the lower fractional outcome.")
	_assert(DifficultyMathScript.minimum_loot_amount(1, 0.85, 1) == 1, "The authored one-unit guarantee must survive every campaign seed.")
	_assert(DifficultyMathScript.minimum_loot_amount(0, 0.85, 1) == 0, "The seed-independent floor must not invent unauthored loot.")
	var amortized_totals := {"easy": 0, "standard": 0, "hard": 0}
	for profile_key in amortized_totals.keys():
		var multiplier := 0.8 if profile_key == "easy" else 1.2 if profile_key == "hard" else 1.0
		var carry := 0.0
		for _day in range(5):
			var payment := DifficultyMathScript.scale_amortized_cost_amount(1, multiplier, carry)
			amortized_totals[profile_key] += int(payment.amount)
			carry = float(payment.next_carry)
	_assert(amortized_totals == {"easy": 4, "standard": 5, "hard": 6}, "Repeated one-unit repairs must preserve real 0.8/1.0/1.2 difficulty costs through deterministic error diffusion.")

	var one_count := 0
	var changed_by_seed := 0
	for index in range(1_000):
		var source_id := "cache_%04d" % index
		one_count += DifficultyMathScript.scale_loot_amount(1, 0.85, 7_777, source_id, "scrap")
		if DifficultyMathScript.scale_loot_amount(1, 0.5, 7_777, source_id, "scrap") != DifficultyMathScript.scale_loot_amount(1, 0.5, 8_888, source_id, "scrap"):
			changed_by_seed += 1
	_assert(one_count >= 800 and one_count <= 900, "Deterministic fractional rounding must preserve the requested density over many stable loot IDs (got %d/1000)." % one_count)
	_assert(changed_by_seed > 100, "Campaign seed must materially change fractional decisions while remaining deterministic.")
	var sample := DifficultyMathScript.stable_unit_sample(5, "source", "item")
	_assert(sample >= 0.0 and sample < 1.0, "Stable loot samples must stay in the half-open unit interval.")
	_assert(DifficultyMathScript.stable_hash_32("difficulty") == 164_617_456, "The stable hash algorithm is balance data and must not change accidentally.")
	_assert(is_equal_approx(sample, 0.94981849193573), "The same seed and stable IDs must keep the exact fractional sample across runs.")
	var signature := DifficultyMathScript.stable_signature("profile payload")
	_assert(signature.length() == 64 and signature == DifficultyMathScript.stable_signature("profile payload"), "Stable signatures must be repeatable SHA-256 digests.")
	_assert(signature != DifficultyMathScript.stable_signature("profile payload changed"), "A changed signature payload must produce a different digest.")


func _assert_balance_equal(first, second, message: String) -> void:
	for field_name in BALANCE_FIELDS:
		_assert_values_equal(first.get(field_name), second.get(field_name), "%s Field: %s." % [message, field_name])


func _assert_values_equal(first: Variant, second: Variant, message: String) -> void:
	if typeof(first) == TYPE_FLOAT or typeof(second) == TYPE_FLOAT:
		_assert(is_equal_approx(float(first), float(second)), message)
		return
	_assert(first == second, message)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Difficulty profile test failed: " + message)
