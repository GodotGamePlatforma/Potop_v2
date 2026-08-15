class_name DiveRiskRuntime
extends RefCounted

const SuitSystemScript := preload("res://scripts/diving/SuitSystem.gd")
const TemperatureSystemScript := preload("res://scripts/diving/TemperatureSystem.gd")
const NoiseSystemScript := preload("res://scripts/diving/NoiseSystem.gd")
const ThreatSystemScript := preload("res://scripts/diving/ThreatSystem.gd")
const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")
const CompetencySystemScript := preload("res://scripts/base/CompetencySystem.gd")
const ProfessionTalentSystemScript := preload("res://scripts/base/ProfessionTalentSystem.gd")

const REPAIR_MODE_STANDARD := "standard"
const REPAIR_MODE_QUIET := "quiet"

var _suit_system = SuitSystemScript.new()
var _temperature_system = TemperatureSystemScript.new()
var _noise_system = NoiseSystemScript.new()
var _threat_system = ThreatSystemScript.new()
var _profession_talent_system = ProfessionTalentSystemScript.new()
var _was_sprinting: bool = false

func reset(threats: Array = []) -> void:
	_was_sprinting = false
	for threat in threats:
		if threat != null and is_instance_valid(threat) and threat.has_method("reset_attempt"):
			threat.reset_attempt()

func advance(
	session,
	setup,
	threats: Array,
	diver_position: Vector2,
	depth: float,
	is_sprinting: bool,
	delta: float,
	light_active: bool = true
) -> Dictionary:
	var result := {
		"warning": "",
		"messages": [],
		"death_reason": "",
		"movement_multiplier": 1.0,
	}
	if session == null or setup == null:
		return result

	var noise_decay_multiplier := 1.0
	if not is_sprinting:
		noise_decay_multiplier = CompetencySystemScript.noise_decay_multiplier(setup)
	session.noise_level = _noise_system.decay(session.noise_level, delta, noise_decay_multiplier)
	if is_sprinting:
		if not _was_sprinting:
			emit_action_noise(session, setup, "sprint", diver_position)
		else:
			session.noise_level = _noise_system.sustain_action_noise(
				session.noise_level,
				"sprint",
				delta,
				_modifier(setup, "noise_range_multiplier")
			)
		session.last_noise_position = diver_position
	_was_sprinting = is_sprinting

	var suit_cold_multiplier := _suit_system.cold_exposure_multiplier(session.suit_condition)
	session.cold_exposure = _temperature_system.advance_exposure(
		session.cold_exposure,
		delta,
		depth,
		setup.suit_quality,
		suit_cold_multiplier,
		_modifier(setup, "cold_rate_multiplier") * CompetencySystemScript.cold_rate_multiplier(setup)
	)
	result.movement_multiplier = _temperature_system.movement_multiplier(session.cold_exposure)
	_apply_environmental_damage(session, setup, delta)

	var threat_warning := ""
	for threat in threats:
		if threat == null or not is_instance_valid(threat) or threat.definition == null:
			continue
		if threat.has_method("is_defeated") and threat.is_defeated():
			continue
		threat.tick_cooldown(delta)
		var diver_distance: float = threat.global_position.distance_to(diver_position)
		var noise_distance: float = threat.global_position.distance_to(session.last_noise_position)
		var alert := _threat_system.advance_alert(
			threat.alert_level,
			delta,
			noise_distance,
			diver_distance,
			session.noise_level,
			light_active,
			threat.definition,
			_modifier(setup, "threat_aggression_multiplier"),
			_modifier(setup, "noise_range_multiplier"),
			CompetencySystemScript.threat_alert_decay_multiplier(setup)
		)
		threat.set_alert(alert)
		if _threat_system.should_warn(alert, threat.definition, CompetencySystemScript.vigilance_warning_reduction(setup)):
			threat_warning = threat.warning_text()
		if threat.can_attack_now() and _threat_system.can_attack(alert, diver_distance, threat.definition):
			var attack_message := _apply_threat_attack(session, setup, threat)
			if not attack_message.is_empty():
				result.messages.append(attack_message)

	if not threat_warning.is_empty():
		result.warning = threat_warning
	elif _temperature_system.is_critical(session.cold_exposure):
		result.warning = "SKRAJNE WYCHLODZENIE"
	elif _suit_system.is_critical(session.suit_condition):
		result.warning = "KRYTYCZNY PRZECIEK KOMBINEZONU"
	elif _suit_system.is_leaking(session.suit_condition):
		result.warning = "KOMBINEZON PRZECIEKA — %s: NAPRAWA" % InputPromptScript.action_text(&"dive_repair")
	elif _temperature_system.is_hypothermic(session.cold_exposure):
		result.warning = "WYCHLODZENIE SPOWALNIA NURKA"

	if session.health <= 0:
		result.death_reason = "obrazenia"
	return result

func emit_action_noise(
	session,
	setup,
	action_id: String,
	world_position: Vector2,
	action_multiplier: float = 1.0
) -> float:
	if session == null:
		return 0.0
	session.noise_level = _noise_system.add_action_noise(
		session.noise_level,
		action_id,
		_modifier(setup, "noise_range_multiplier") * maxf(action_multiplier, 0.0)
	)
	session.last_noise_position = world_position
	session.record_noise_event(action_id)
	return session.noise_level

func try_repair_suit(
	session,
	setup,
	world_position: Vector2,
	mode: String = REPAIR_MODE_STANDARD
) -> Dictionary:
	var blocker := repair_blocker(session, setup, mode)
	if not blocker.is_empty():
		return {"success": false, "message": blocker}
	var previous: int = int(session.suit_condition)
	session.repair_kit_charges -= 1
	session.repair_kit_uses += 1
	var repair_amount := int(setup.suit_repair_amount)
	if repair_amount <= 0:
		# Kompatybilność ręcznie tworzonych i starszych przejściowych setupów.
		repair_amount = _suit_system.repair_amount(setup.suit_quality)
	if mode == REPAIR_MODE_QUIET:
		repair_amount = maxi(int(floor(
			float(repair_amount)
			* _talent_float_parameter("nurek_technik_glebinowy", "repair_amount_multiplier", 0.60)
		)), 1)
	session.suit_condition = _suit_system.repair(session.suit_condition, repair_amount)
	var repaired_amount: int = int(session.suit_condition) - previous
	session.record_risk_event("suit_repaired_quiet" if mode == REPAIR_MODE_QUIET else "suit_repaired")
	var noise_multiplier := (
		_talent_float_parameter("nurek_technik_glebinowy", "noise_multiplier", 0.25)
		if mode == REPAIR_MODE_QUIET
		else 1.0
	)
	emit_action_noise(
		session,
		setup,
		"repair",
		world_position,
		noise_multiplier
	)
	var message := "Naprawiono kombinezon: %d%% -> %d%%. Hałas może zwabić zagrożenie." % [previous, session.suit_condition]
	if mode == REPAIR_MODE_QUIET:
		message = "Cicha naprawa kombinezonu: %d%% -> %d%%." % [previous, session.suit_condition]
	return {
		"success": true,
		"message": message,
		"mode": mode,
		"repaired_amount": repaired_amount,
	}


func repair_blocker(session, setup, mode: String = REPAIR_MODE_STANDARD) -> String:
	if session == null or setup == null:
		return "Brak aktywnej wyprawy."
	if mode not in [REPAIR_MODE_STANDARD, REPAIR_MODE_QUIET]:
		return "Nieznany tryb naprawy."
	if mode == REPAIR_MODE_QUIET and not ProfessionTalentSystemScript.has_talent(setup, "nurek_technik_glebinowy"):
		return "Cicha naprawa wymaga talentu Technik głębinowy."
	if not session.has_tool("repair_kit"):
		return "Nie zabrano zestawu naprawczego."
	if session.repair_kit_charges <= 0:
		return "Zestaw naprawczy został już zużyty."
	if session.suit_condition >= 100:
		return "Kombinezon nie wymaga naprawy."
	return ""


func _talent_float_parameter(talent_id: String, parameter_id: String, fallback: float) -> float:
	var definition = _profession_talent_system.get_definition(talent_id)
	return float(definition.parameters.get(parameter_id, fallback)) if definition != null else fallback

func interaction_speed_multiplier(session, setup = null) -> float:
	return (_temperature_system.interaction_speed_multiplier(session.cold_exposure) if session != null else 1.0) * CompetencySystemScript.interaction_speed_multiplier(setup)

func populate_result(session, result) -> void:
	if session == null or result == null:
		return
	if _temperature_system.is_hypothermic(session.cold_exposure):
		session.add_injury("hypothermia")
	if _suit_system.is_critical(session.suit_condition):
		session.add_injury("suit_breach")
	result.suit_condition_remaining = session.suit_condition
	result.cold_exposure = session.cold_exposure
	result.repair_kit_uses = session.repair_kit_uses
	result.noise_events.assign(session.noise_events)
	result.risk_events.assign(session.risk_events)
	result.diver_injuries.assign(session.injuries)

func _apply_environmental_damage(session, setup, delta: float) -> void:
	var leak_damage_multiplier := 1.0
	if session.suit_condition < 50:
		leak_damage_multiplier = CompetencySystemScript.leak_health_damage_multiplier(setup)
	session.leak_damage_progress += _suit_system.leak_health_rate(session.suit_condition) * leak_damage_multiplier * maxf(delta, 0.0)
	session.cold_damage_progress += _temperature_system.health_damage_rate(session.cold_exposure) * maxf(delta, 0.0)
	var pending_damage := int(floor(session.leak_damage_progress)) + int(floor(session.cold_damage_progress))
	if pending_damage <= 0:
		return
	session.leak_damage_progress -= floor(session.leak_damage_progress)
	session.cold_damage_progress -= floor(session.cold_damage_progress)
	session.apply_damage(pending_damage)

func _apply_threat_attack(session, setup, threat) -> String:
	var raw_suit_damage := int(threat.definition.attack_suit_damage)
	var suit_damage := _suit_system.calculate_damage(
		raw_suit_damage,
		setup.suit_quality,
		_modifier(setup, "suit_damage_multiplier")
	)
	session.suit_condition = _suit_system.apply_damage(session.suit_condition, suit_damage)
	var health_damage := _threat_system.attack_health_damage(
		threat.definition,
		_modifier(setup, "threat_aggression_multiplier")
	)
	session.apply_damage(health_damage)
	session.add_injury("puncture_wound")
	session.record_risk_event("threat_attack:%s" % threat.threat_id)
	threat.mark_attacked()
	return "%s atakuje: kombinezon -%d%%, zdrowie -%d." % [threat.definition.display_name, suit_damage, health_damage]

func _modifier(setup, modifier_id: String, fallback: float = 1.0) -> float:
	if setup == null:
		return fallback
	return maxf(float(setup.difficulty_modifiers.get(modifier_id, fallback)), 0.0)
