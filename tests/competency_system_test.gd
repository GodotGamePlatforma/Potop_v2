extends SceneTree

const CompetencySystemScript := preload("res://scripts/base/CompetencySystem.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")

var _failed := false


func _initialize() -> void:
	_test_catalog_contract()
	_test_atomic_point_spending()
	_test_exact_effects()
	_test_expedition_snapshot()
	if _failed:
		quit(1)
		return
	print("Competency system test passed: fifteen passive competencies, atomic levels, exact effects and expedition snapshots work.")
	quit(0)


func _test_catalog_contract() -> void:
	_assert(CompetencySystemScript.MAX_LEVEL == 3, "Every passive competency must have exactly three purchasable levels.")
	_assert(CompetencySystemScript.IDS.size() == 15, "The canonical catalog must contain exactly fifteen passive competencies.")
	var unique_ids: Dictionary = {}
	for competency_id in CompetencySystemScript.IDS:
		_assert(not competency_id.is_empty() and not unique_ids.has(competency_id), "Every competency ID must be non-empty and unique.")
		unique_ids[competency_id] = true
		_assert(str(CompetencySystemScript.LABELS.get(competency_id, "")).strip_edges() != "", "Every competency must have a canonical label.")
		_assert(str(CompetencySystemScript.DESCRIPTIONS.get(competency_id, "")).strip_edges() != "", "Every competency must have a canonical effect description.")
		var tooltip := CompetencySystemScript.tooltip_text(null, competency_id)
		_assert(tooltip.contains(str(CompetencySystemScript.LABELS[competency_id])) and not tooltip.contains("brak aktywnego efektu"), "Every competency must expose a canonical current-effect summary in its tooltip.")
	_assert(not CompetencySystemScript.is_valid_id("active_dash"), "An undeclared active skill must not enter the passive competency catalog.")


func _test_atomic_point_spending() -> void:
	for competency_id in CompetencySystemScript.IDS:
		var survivor = _survivor()
		survivor.unspent_skill_points = 1
		_assert(survivor.spend_skill_point(competency_id), "Every canonical competency must accept one available development point.")
		_assert(
			CompetencySystemScript.level(survivor, competency_id) == 1
			and survivor.unspent_skill_points == 0
			and survivor.competency_levels.size() == 1,
			"A successful competency purchase must add exactly one level and spend exactly one point."
		)
	var invalid = _survivor()
	invalid.unspent_skill_points = 1
	var invalid_before: Dictionary = invalid.competency_levels.duplicate(true)
	_assert(not invalid.spend_skill_point("active_dash"), "An unknown or active skill ID must be rejected.")
	_assert(invalid.unspent_skill_points == 1 and invalid.competency_levels == invalid_before, "Unknown-skill rejection must preserve all development state.")

	var no_points = _survivor()
	var no_points_before: Dictionary = no_points.competency_levels.duplicate(true)
	_assert(not no_points.spend_skill_point("swimming"), "A competency purchase without a development point must be rejected.")
	_assert(no_points.unspent_skill_points == 0 and no_points.competency_levels == no_points_before, "No-point rejection must preserve all development state.")

	var capped = _survivor()
	capped.unspent_skill_points = 1
	capped.competency_levels["swimming"] = CompetencySystemScript.MAX_LEVEL
	var capped_before: Dictionary = capped.competency_levels.duplicate(true)
	_assert(not capped.spend_skill_point("swimming"), "A level-three competency must reject a fourth purchase.")
	_assert(capped.unspent_skill_points == 1 and capped.competency_levels == capped_before, "Maximum-level rejection must preserve the point and all competency levels.")


func _test_exact_effects() -> void:
	var survivor = _survivor()
	for competency_id in CompetencySystemScript.IDS:
		survivor.competency_levels[competency_id] = CompetencySystemScript.MAX_LEVEL
	_assert(is_equal_approx(CompetencySystemScript.swimming_multiplier(survivor), 1.15), "Swimming III must give exactly +15% movement speed.")
	_assert(is_equal_approx(CompetencySystemScript.oxygen_use_multiplier(survivor), 0.88), "Oxygen Economy III must reduce oxygen use by exactly 12%.")
	_assert(is_equal_approx(CompetencySystemScript.cold_rate_multiplier(survivor), 0.85), "Cold Resistance III must reduce cold gain by exactly 15%.")
	_assert(is_equal_approx(CompetencySystemScript.production_multiplier(survivor), 1.15), "Production III must give exactly +15% personal production.")
	_assert(is_equal_approx(CompetencySystemScript.cooperation_multiplier(survivor), 1.12), "Cooperation III must give exactly +12% work efficiency.")
	_assert(CompetencySystemScript.disease_pressure_reduction(survivor) == 3, "Resilience III must remove exactly three disease-pressure points.")
	_assert(is_equal_approx(CompetencySystemScript.interaction_speed_multiplier(survivor), 1.0 / 0.85), "Tool Handling III must reduce interaction time by exactly 15%.")
	_assert(is_equal_approx(CompetencySystemScript.vigilance_warning_reduction(survivor), 15.0), "Vigilance III must lower the warning threshold by exactly fifteen points.")
	_assert(is_equal_approx(CompetencySystemScript.load_oxygen_surcharge_multiplier(survivor), 0.50), "Load Trim III must halve only the oxygen surcharge from carried load.")
	_assert(is_equal_approx(CompetencySystemScript.noise_decay_multiplier(survivor), 1.60), "Quiet Profile III must accelerate noise decay by exactly 60%.")
	_assert(is_equal_approx(CompetencySystemScript.threat_alert_decay_multiplier(survivor), 1.45), "Composure III must accelerate unstimulated threat-alert decay by exactly 45%.")
	_assert(is_equal_approx(CompetencySystemScript.leak_health_damage_multiplier(survivor), 0.55), "Seal Control III must reduce leak health damage by exactly 45% while its condition gate is active.")
	_assert(CompetencySystemScript.work_fatigue_reduction(survivor) == 3, "Work Ergonomics III must remove exactly three work-fatigue points.")
	_assert(CompetencySystemScript.low_hope_morale_loss_reduction(survivor) == 3, "Fortitude III must offset up to three personal morale-loss points from low Hope.")
	_assert(CompetencySystemScript.emitted_disease_pressure_reduction(survivor) == 3, "Workplace Hygiene III must remove exactly three disease-pressure points emitted to coworkers.")

	var expected_load_trim := [1.0, 0.80, 0.65, 0.50]
	for competency_level in range(CompetencySystemScript.MAX_LEVEL + 1):
		var ranked = _survivor()
		ranked.competency_levels = {
			"load_trim": competency_level,
			"quiet_profile": competency_level,
			"composure": competency_level,
			"seal_control": competency_level,
			"work_ergonomics": competency_level,
			"fortitude": competency_level,
			"workplace_hygiene": competency_level,
		}
		_assert(is_equal_approx(CompetencySystemScript.load_oxygen_surcharge_multiplier(ranked), expected_load_trim[competency_level]), "Every Load Trim rank must expose its exact non-linear surcharge multiplier.")
		_assert(is_equal_approx(CompetencySystemScript.noise_decay_multiplier(ranked), 1.0 + 0.20 * competency_level), "Every Quiet Profile rank must expose its exact noise-decay multiplier.")
		_assert(is_equal_approx(CompetencySystemScript.threat_alert_decay_multiplier(ranked), 1.0 + 0.15 * competency_level), "Every Composure rank must expose its exact alert-decay multiplier.")
		_assert(is_equal_approx(CompetencySystemScript.leak_health_damage_multiplier(ranked), 1.0 - 0.15 * competency_level), "Every Seal Control rank must expose its exact leak-health multiplier.")
		_assert(CompetencySystemScript.work_fatigue_reduction(ranked) == competency_level, "Every Work Ergonomics rank must expose its exact work-fatigue reduction.")
		_assert(CompetencySystemScript.low_hope_morale_loss_reduction(ranked) == competency_level, "Every Fortitude rank must expose its exact low-Hope morale reduction.")
		_assert(CompetencySystemScript.emitted_disease_pressure_reduction(ranked) == competency_level, "Every Workplace Hygiene rank must expose its exact emitted-pressure reduction.")


func _test_expedition_snapshot() -> void:
	var survivor = _survivor()
	survivor.id = "snapshot_diver"
	survivor.display_name = "Snapshot Diver"
	survivor.competency_levels = {
		"swimming": 2,
		"oxygen_economy": 3,
		"tool_handling": 1,
		"load_trim": 3,
		"quiet_profile": 2,
		"composure": 1,
		"seal_control": 3,
	}
	var setup = ExpeditionSetupScript.new()
	setup.capture_diver(survivor, 100.0)
	survivor.competency_levels["swimming"] = 3
	survivor.competency_levels.erase("oxygen_economy")
	survivor.competency_levels["load_trim"] = 1
	_assert(
		CompetencySystemScript.level(setup, "swimming") == 2
		and CompetencySystemScript.level(setup, "oxygen_economy") == 3
		and CompetencySystemScript.level(setup, "tool_handling") == 1,
		"ExpeditionSetup must retain the detached competency snapshot captured at departure."
	)
	_assert(
		CompetencySystemScript.level(setup, "load_trim") == 3
		and CompetencySystemScript.level(setup, "quiet_profile") == 2
		and CompetencySystemScript.level(setup, "composure") == 1
		and CompetencySystemScript.level(setup, "seal_control") == 3,
		"Every dive-facing competency must use the detached ExpeditionSetup snapshot for the entire attempt."
	)


func _survivor():
	var survivor = SurvivorStateScript.new()
	survivor.health = survivor.get_max_health()
	return survivor


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Competency system test failed: " + message)
