class_name DiveCombatSystem
extends RefCounted

const KNIFE_ID := "knife"
const HARPOON_PISTOL_ID := "harpoon_pistol"
const KNIFE_RANGE := 82.0
const KNIFE_DAMAGE := 35
const KNIFE_COOLDOWN := 0.5
const HIT_RADIUS := 58.0

func available_weapon_ids(session, setup) -> Array[String]:
	var result: Array[String] = []
	if session != null and session.has_tool(KNIFE_ID):
		result.append(KNIFE_ID)
	if setup != null and str(setup.equipped_gear.get("weapon", "")) == HARPOON_PISTOL_ID:
		result.append(HARPOON_PISTOL_ID)
	return result

func select_weapon(session, setup, weapon_id: String) -> bool:
	if session == null or not available_weapon_ids(session, setup).has(weapon_id):
		return false
	session.selected_combat_tool = weapon_id
	return true

func advance_cooldown(session, delta: float) -> void:
	if session != null:
		session.combat_cooldown_left = maxf(session.combat_cooldown_left - maxf(delta, 0.0), 0.0)

func try_attack(session, setup, origin: Vector2, target_position: Vector2, threats: Array, weapon_definition = null) -> Dictionary:
	var result := {"success": false, "message": "", "hit": false, "defeated": false, "threat": null, "end_position": origin, "noise_action": ""}
	if session == null or setup == null:
		result.message = "Brak aktywnej wyprawy."
		return result
	if session.combat_cooldown_left > 0.0:
		return result
	var weapon_id := str(session.selected_combat_tool)
	if not available_weapon_ids(session, setup).has(weapon_id):
		result.message = "Wybrane narzędzie nie jest dostępne."
		return result
	var direction := target_position - origin
	if direction.length_squared() <= 0.0001:
		return result
	direction = direction.normalized()
	var attack_range := KNIFE_RANGE
	var damage := KNIFE_DAMAGE
	var cooldown := KNIFE_COOLDOWN
	var noise_action := "knife_attack"
	if weapon_id == HARPOON_PISTOL_ID:
		if weapon_definition == null or str(weapon_definition.id) != HARPOON_PISTOL_ID:
			result.message = "Brak poprawnej definicji pistoletu harpunowego."
			return result
		if session.harpoon_ammo <= 0:
			result.message = "Brak harpunów."
			return result
		session.harpoon_ammo -= 1
		attack_range = float(weapon_definition.weapon_range)
		damage = int(weapon_definition.weapon_damage)
		cooldown = float(weapon_definition.weapon_cooldown)
		noise_action = "harpoon_shot"
	result.success = true
	result.noise_action = noise_action
	session.combat_cooldown_left = cooldown
	var best_threat = null
	var best_projection := attack_range + 1.0
	for threat in threats:
		if threat == null or not is_instance_valid(threat) or not threat.has_method("is_defeated") or threat.is_defeated():
			continue
		var offset: Vector2 = threat.global_position - origin
		var projection := offset.dot(direction)
		if projection < 0.0 or projection > attack_range:
			continue
		var perpendicular := absf(offset.cross(direction))
		if perpendicular <= HIT_RADIUS and projection < best_projection:
			best_projection = projection
			best_threat = threat
	result.end_position = origin + direction * (best_projection if best_threat != null else attack_range)
	if best_threat != null:
		result.hit = true
		result.threat = best_threat
		result.defeated = bool(best_threat.apply_combat_damage(damage))
		result.message = "%s wyeliminowany." % best_threat.definition.display_name if result.defeated else "%s trafiony: %d obrażeń." % [best_threat.definition.display_name, damage]
	return result
