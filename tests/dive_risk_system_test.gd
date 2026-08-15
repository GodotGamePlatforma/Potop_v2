extends SceneTree

const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const DiveSessionStateScript := preload("res://scripts/data/DiveSessionState.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const UnderwaterWorldStateScript := preload("res://scripts/data/UnderwaterWorldState.gd")
const MapCompilerScript := preload("res://scripts/diving/UnderwaterMapSceneCompiler.gd")
const SuitSystemScript := preload("res://scripts/diving/SuitSystem.gd")
const TemperatureSystemScript := preload("res://scripts/diving/TemperatureSystem.gd")
const NoiseSystemScript := preload("res://scripts/diving/NoiseSystem.gd")
const ThreatSystemScript := preload("res://scripts/diving/ThreatSystem.gd")
const DiveRiskRuntimeScript := preload("res://scripts/diving/DiveRiskRuntime.gd")
const DiveCombatSystemScript := preload("res://scripts/diving/DiveCombatSystem.gd")
const DiveThreatScript := preload("res://scripts/diving/DiveThreat.gd")

var _failed := false

func _initialize() -> void:
	var setup = ExpeditionSetupScript.new()
	setup.diver_id = "igor"
	setup.diver_health = 100
	setup.diver_health_capacity = 100
	setup.oxygen_capacity = 100.0
	setup.suit_quality = 1
	setup.suit_repair_amount = 56
	setup.selected_gear.assign(["knife", "crowbar", "repair_kit", "harpoon_pistol"])
	setup.equipped_gear = {"weapon": "harpoon_pistol"}
	setup.weapon_ammunition = 6
	setup.difficulty_modifiers = {
		"suit_damage_multiplier": 1.0,
		"cold_rate_multiplier": 1.0,
		"threat_aggression_multiplier": 1.0,
		"noise_range_multiplier": 1.0,
	}

	var session = DiveSessionStateScript.new()
	session.begin(setup)
	_assert(session.repair_kit_charges == 1, "A selected repair kit should provide one contextual suit repair per attempt.")
	_assert(session.has_tool("knife") and session.has_tool("crowbar"), "The session should expose the immutable tool snapshot from ExpeditionSetup.")

	var suit = SuitSystemScript.new()
	var quality_one_damage: int = suit.calculate_damage(20, 1, 1.0)
	var quality_four_damage: int = suit.calculate_damage(20, 4, 1.0)
	_assert(quality_four_damage < quality_one_damage, "Higher suit quality should reduce incoming suit damage.")
	_assert(suit.is_leaking(50) and suit.leak_health_rate(20) > suit.leak_health_rate(50), "A critically damaged suit should leak faster than a moderately damaged suit.")

	var temperature = TemperatureSystemScript.new()
	var shallow_rate: float = temperature.exposure_rate(12.0, 1, 1.0, 1.0)
	var deep_rate: float = temperature.exposure_rate(145.0, 1, 1.0, 1.0)
	var damaged_suit_rate: float = temperature.exposure_rate(145.0, 1, suit.cold_exposure_multiplier(20), 1.0)
	_assert(shallow_rate < deep_rate and deep_rate < damaged_suit_rate, "Cold exposure should rise with depth and accelerate through a damaged suit.")
	_assert(temperature.movement_multiplier(90.0) < 1.0 and temperature.interaction_speed_multiplier(90.0) < 1.0, "Severe cold should slow movement and contextual interactions.")

	var noise = NoiseSystemScript.new()
	_assert(noise.noise_for_action("pry") > noise.noise_for_action("cut"), "Prying with a crowbar should be louder than cutting with a knife.")
	_assert(noise.add_action_noise(0.0, "pry") > noise.add_action_noise(0.0, "sprint"), "Tool actions should create distinct noise pulses.")
	_assert(noise.decay(50.0, 1.0) < 50.0, "Noise should decay when no action sustains it.")
	_assert(
		is_equal_approx(50.0 - noise.decay(50.0, 1.0, 1.60), (50.0 - noise.decay(50.0, 1.0)) * 1.60),
		"Quiet Profile III must accelerate canonical noise decay by exactly 60%."
	)

	var threat_definition = ResourceLoader.load("res://data/threats/noise_eel.tres")
	_assert(threat_definition != null and threat_definition.is_valid(), "The first data-driven threat definition should be valid.")
	var threat_system = ThreatSystemScript.new()
	var stimulated_baseline_alert: float = threat_system.advance_alert(10.0, 0.25, 0.0, 0.0, 100.0, false, threat_definition, 1.0, 1.0, 1.0)
	var stimulated_composed_alert: float = threat_system.advance_alert(10.0, 0.25, 0.0, 0.0, 100.0, false, threat_definition, 1.0, 1.0, 1.45)
	_assert(
		is_equal_approx(stimulated_composed_alert, stimulated_baseline_alert),
		"Composure must not reduce or otherwise alter alert growth while a threat has an active stimulus."
	)
	_assert(threat_definition.world_texture != null and threat_definition.world_texture.resource_path == "res://assets/diving/threats/noise_eel.png" and threat_definition.world_texture.get_size() == Vector2(256, 128), "The first threat definition should carry its production world sprite.")
	var threat = DiveThreatScript.new()
	threat.configure("risk_test_eel", threat_definition)
	threat.position = Vector2(12, 0)
	root.add_child(threat)
	var baseline_setup = setup.duplicate(true)
	baseline_setup.competency_levels.clear()
	var skilled_setup = setup.duplicate(true)
	skilled_setup.competency_levels = {
		"cold_resistance": 3,
		"tool_handling": 3,
		"vigilance": 3,
		"quiet_profile": 3,
		"composure": 3,
		"seal_control": 3,
	}
	var baseline_session = DiveSessionStateScript.new()
	baseline_session.begin(baseline_setup)
	var skilled_session = DiveSessionStateScript.new()
	skilled_session.begin(skilled_setup)
	var competency_risk = DiveRiskRuntimeScript.new()
	competency_risk.advance(baseline_session, baseline_setup, [], Vector2.ZERO, 145.0, false, 10.0, false)
	competency_risk.advance(skilled_session, skilled_setup, [], Vector2.ZERO, 145.0, false, 10.0, false)
	_assert(is_equal_approx(skilled_session.cold_exposure, baseline_session.cold_exposure * 0.85), "Cold Resistance III must reduce canonical runtime cold gain by exactly 15%.")
	_assert(is_equal_approx(competency_risk.interaction_speed_multiplier(skilled_session, skilled_setup), 1.0 / 0.85), "Tool Handling III must reduce canonical runtime interaction time by exactly 15% before cold penalties.")
	baseline_session.noise_level = 50.0
	skilled_session.noise_level = 50.0
	competency_risk.advance(baseline_session, baseline_setup, [], Vector2.ZERO, 0.0, false, 1.0, false)
	competency_risk.advance(skilled_session, skilled_setup, [], Vector2.ZERO, 0.0, false, 1.0, false)
	_assert(
		is_equal_approx(50.0 - skilled_session.noise_level, (50.0 - baseline_session.noise_level) * 1.60),
		"Quiet Profile III must accelerate runtime noise decay by exactly 60% while the diver is not sprinting."
	)
	var baseline_sprint_session = DiveSessionStateScript.new()
	baseline_sprint_session.begin(baseline_setup)
	baseline_sprint_session.noise_level = 50.0
	var skilled_sprint_session = DiveSessionStateScript.new()
	skilled_sprint_session.begin(skilled_setup)
	skilled_sprint_session.noise_level = 50.0
	DiveRiskRuntimeScript.new().advance(baseline_sprint_session, baseline_setup, [], Vector2.ZERO, 0.0, true, 1.0, false)
	DiveRiskRuntimeScript.new().advance(skilled_sprint_session, skilled_setup, [], Vector2.ZERO, 0.0, true, 1.0, false)
	_assert(
		is_equal_approx(skilled_sprint_session.noise_level, baseline_sprint_session.noise_level),
		"Quiet Profile must not accelerate noise decay during a sustained sprint."
	)
	threat.set_alert(25.0)
	var baseline_warning: Dictionary = competency_risk.advance(baseline_session, baseline_setup, [threat], Vector2(1000, 1000), 0.0, false, 0.0, false)
	threat.set_alert(25.0)
	var skilled_warning: Dictionary = competency_risk.advance(skilled_session, skilled_setup, [threat], Vector2(1000, 1000), 0.0, false, 0.0, false)
	_assert(str(baseline_warning.warning).is_empty() and not str(skilled_warning.warning).is_empty(), "Vigilance III must expose the same threat warning fifteen alert points earlier without changing attack rules.")
	baseline_session.noise_level = 0.0
	skilled_session.noise_level = 0.0
	threat.set_alert(50.0)
	competency_risk.advance(baseline_session, baseline_setup, [threat], Vector2(1000, 1000), 0.0, false, 1.0, false)
	var baseline_alert_after_decay: float = threat.alert_level
	threat.set_alert(50.0)
	competency_risk.advance(skilled_session, skilled_setup, [threat], Vector2(1000, 1000), 0.0, false, 1.0, false)
	var skilled_alert_after_decay: float = threat.alert_level
	_assert(
		is_equal_approx(50.0 - skilled_alert_after_decay, (50.0 - baseline_alert_after_decay) * 1.45),
		"Composure III must accelerate threat-alert decay by exactly 45% when no stimulus is active."
	)
	var baseline_leak_session = DiveSessionStateScript.new()
	baseline_leak_session.begin(baseline_setup)
	baseline_leak_session.suit_condition = 49
	baseline_leak_session.cold_exposure = 100.0
	var skilled_leak_session = DiveSessionStateScript.new()
	skilled_leak_session.begin(skilled_setup)
	skilled_leak_session.suit_condition = 49
	skilled_leak_session.cold_exposure = 100.0
	DiveRiskRuntimeScript.new().advance(baseline_leak_session, baseline_setup, [], Vector2.ZERO, 0.0, false, 0.5, false)
	DiveRiskRuntimeScript.new().advance(skilled_leak_session, skilled_setup, [], Vector2.ZERO, 0.0, false, 0.5, false)
	_assert(
		is_equal_approx(skilled_leak_session.leak_damage_progress, baseline_leak_session.leak_damage_progress * 0.55),
		"Seal Control III must reduce leak-health damage by exactly 45% below 50% suit condition."
	)
	_assert(
		is_equal_approx(skilled_leak_session.cold_damage_progress, baseline_leak_session.cold_damage_progress),
		"Seal Control must leave the separate cold-damage accumulator unchanged."
	)
	var baseline_gate_session = DiveSessionStateScript.new()
	baseline_gate_session.begin(baseline_setup)
	baseline_gate_session.suit_condition = 50
	var skilled_gate_session = DiveSessionStateScript.new()
	skilled_gate_session.begin(skilled_setup)
	skilled_gate_session.suit_condition = 50
	DiveRiskRuntimeScript.new().advance(baseline_gate_session, baseline_setup, [], Vector2.ZERO, 0.0, false, 0.5, false)
	DiveRiskRuntimeScript.new().advance(skilled_gate_session, skilled_setup, [], Vector2.ZERO, 0.0, false, 0.5, false)
	_assert(
		is_equal_approx(skilled_gate_session.leak_damage_progress, baseline_gate_session.leak_damage_progress),
		"Seal Control must remain inactive at the exact 50% suit-condition boundary."
	)
	threat.reset_attempt()
	var threat_sprite := threat.get_node_or_null("ThreatSprite") as Sprite2D
	_assert(threat.visual_texture() == threat_definition.world_texture and threat_sprite != null and threat_sprite.texture == threat_definition.world_texture, "The live threat should render the texture owned by its data definition.")
	var combat = DiveCombatSystemScript.new()
	var harpoon_definition = ResourceLoader.load("res://data/diving_gear/harpoon_pistol.tres")
	_assert(harpoon_definition != null and harpoon_definition.is_valid_weapon(), "The Workshop II harpoon pistol must expose valid combat data.")
	_assert(session.selected_combat_tool == "knife" and session.harpoon_ammo == 6, "A dive with both tools should start on the knife with six renewable harpoons.")
	var combat_origin: Vector2 = threat.global_position - Vector2(12, 0)
	for hit_index in range(3):
		var knife_attack: Dictionary = combat.try_attack(session, setup, combat_origin, threat.global_position, [threat], harpoon_definition)
		_assert(bool(knife_attack.success) and bool(knife_attack.hit), "A knife attack aimed at a nearby threat should hit.")
		combat.advance_cooldown(session, 1.0)
	_assert(threat.is_defeated(), "Three quiet knife hits should eliminate the first threat for the current attempt.")
	var ignored_defeated_health: int = int(session.health)
	var defeated_risk = DiveRiskRuntimeScript.new()
	session.noise_level = 100.0
	defeated_risk.advance(session, setup, [threat], Vector2.ZERO, 80.0, false, 5.0, true)
	_assert(session.health == ignored_defeated_health, "A defeated threat must not attack again in the current attempt.")
	threat.reset_attempt()
	_assert(not threat.is_defeated() and threat.health == threat_definition.max_health, "Resetting an attempt must restore the non-persistent threat.")
	_assert(combat.select_weapon(session, setup, "harpoon_pistol"), "The equipped harpoon pistol should be selectable.")
	for hit_index in range(2):
		var shot: Dictionary = combat.try_attack(session, setup, combat_origin, combat_origin + Vector2(500, 0), [threat], harpoon_definition)
		_assert(bool(shot.success) and bool(shot.hit), "A cursor-aimed harpoon shot should hit a threat within range.")
		combat.advance_cooldown(session, 1.0)
	_assert(threat.is_defeated() and session.harpoon_ammo == 4, "Two harpoons should eliminate the threat and consume exactly two of six shots.")
	threat.reset_attempt()
	session.reset_attempt()

	var risk = DiveRiskRuntimeScript.new()
	var original_repair_events := InputMap.action_get_events(&"dive_repair")
	InputMap.action_erase_events(&"dive_repair")
	var remapped_repair := InputEventKey.new()
	remapped_repair.keycode = KEY_T
	InputMap.action_add_event(&"dive_repair", remapped_repair)
	session.suit_condition = 60
	var prompt_result: Dictionary = risk.advance(session, setup, [], Vector2.ZERO, 20.0, false, 0.0, true)
	_assert(str(prompt_result.warning).contains("T: NAPRAWA") and not str(prompt_result.warning).contains("R: NAPRAWA"), "The leak warning should use the current remapped repair binding.")
	InputMap.action_erase_events(&"dive_repair")
	for input_event in original_repair_events:
		InputMap.action_add_event(&"dive_repair", input_event)
	risk.reset([threat])
	session.noise_level = 100.0
	session.last_noise_position = Vector2.ZERO
	var health_before: int = session.health
	for index in range(4):
		risk.advance(session, setup, [threat], Vector2.ZERO, 80.0, false, 1.0, true)
	_assert(session.suit_condition < 100, "A fully alerted nearby threat should damage the suit.")
	_assert(session.health < health_before, "A threat attack should create an immediate health consequence.")
	_assert(session.risk_events.has("threat_attack:risk_test_eel"), "The session should retain a stable threat event identifier.")
	_assert(session.injuries.has("puncture_wound"), "A threat attack should create a persistent injury result.")

	session.suit_condition = 20
	var damaged_condition: int = session.suit_condition
	var repair: Dictionary = risk.try_repair_suit(session, setup, Vector2.ZERO)
	_assert(bool(repair.get("success", false)) and session.suit_condition == damaged_condition + 56, "The repair kit should use the 56-point amount frozen in ExpeditionSetup instead of recomputing the 30-point repair from suit quality.")
	_assert(session.repair_kit_charges == 0 and session.repair_kit_uses == 1, "A repair should consume the single attempt charge.")
	_assert(session.noise_events.has("repair"), "Repairing the suit should produce a recorded noise event.")

	var quiet_without_talent_setup = setup.duplicate(true)
	quiet_without_talent_setup.profession_talent_ids = {}
	var quiet_without_talent_session = DiveSessionStateScript.new()
	quiet_without_talent_session.begin(quiet_without_talent_setup)
	quiet_without_talent_session.suit_condition = 20
	var quiet_without_talent := risk.try_repair_suit(
		quiet_without_talent_session,
		quiet_without_talent_setup,
		Vector2.ZERO,
		DiveRiskRuntimeScript.REPAIR_MODE_QUIET
	)
	_assert(
		not bool(quiet_without_talent.get("success", false))
		and quiet_without_talent_session.suit_condition == 20
		and quiet_without_talent_session.repair_kit_charges == 1
		and is_zero_approx(quiet_without_talent_session.noise_level),
		"Cicha naprawa bez talentu Technika głębinowego musi być odrzucona bez kosztu, naprawy i hałasu."
	)

	var quiet_setup = setup.duplicate(true)
	quiet_setup.profession_talent_ids = {"nurek": "nurek_technik_glebinowy"}
	var quiet_session = DiveSessionStateScript.new()
	quiet_session.begin(quiet_setup)
	quiet_session.suit_condition = 20
	var quiet_repair := risk.try_repair_suit(
		quiet_session,
		quiet_setup,
		Vector2.ZERO,
		DiveRiskRuntimeScript.REPAIR_MODE_QUIET
	)
	_assert(
		bool(quiet_repair.get("success", false))
		and int(quiet_repair.get("repaired_amount", 0)) == 33
		and quiet_session.suit_condition == 53,
		"Cicha naprawa musi zaokrąglić w dół 60% zamrożonej naprawy 56 do dokładnie 33 punktów."
	)
	_assert(
		quiet_session.repair_kit_charges == 0
		and quiet_session.repair_kit_uses == 1
		and is_equal_approx(quiet_session.noise_level, 9.5)
		and quiet_session.risk_events.has("suit_repaired_quiet"),
		"Cicha naprawa musi atomowo zużyć jeden ładunek i wyemitować dokładnie 25% zwykłego hałasu naprawy."
	)
	var full_suit_session = DiveSessionStateScript.new()
	full_suit_session.begin(quiet_setup)
	var full_suit_quiet := risk.try_repair_suit(
		full_suit_session,
		quiet_setup,
		Vector2.ZERO,
		DiveRiskRuntimeScript.REPAIR_MODE_QUIET
	)
	_assert(
		not bool(full_suit_quiet.get("success", false))
		and full_suit_session.repair_kit_charges == 1
		and is_zero_approx(full_suit_session.noise_level),
		"Cicha naprawa pełnego kombinezonu musi pozostać bez kosztu i hałasu."
	)

	session.cold_exposure = 75.0
	var result = DiveResultScript.new()
	risk.populate_result(session, result)
	_assert(result.cold_exposure == 75.0 and result.diver_injuries.has("hypothermia"), "DiveResult should carry hypothermia from local session state.")
	_assert(result.risk_events.has("threat_attack:risk_test_eel") and result.noise_events.has("repair"), "DiveResult should preserve risk and noise reasons for reports.")

	var world = UnderwaterWorldStateScript.new()
	world.setup(8128)
	var map_errors: PackedStringArray = MapCompilerScript.new().generate(world, 8128)
	_assert(map_errors.is_empty(), "Scena mapy musi być dostępna dla testu ryzyka: %s" % "; ".join(map_errors))
	_assert(not world.blueprint.threat_spawns.is_empty(), "Scena mapy powinna zawierać co najmniej jedno zagrożenie.")
	var risky_locker: Dictionary = {}
	for loot in world.blueprint.loot_spawns:
		if str(loot.get("id", "")) == "tutorial_service_locker":
			risky_locker = loot
			break
	_assert(risky_locker.get("required_tool", "") == "crowbar" and risky_locker.get("interaction_action", "") == "pry", "The optional risky locker should declare its contextual crowbar action in blueprint data.")

	threat.queue_free()
	if _failed:
		quit(1)
		return
	print("Dive risk system test passed: suit, cold, competency-gated leak, noise and alert decay, threat, repair and result contracts work.")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Dive risk system test failed: " + message)
