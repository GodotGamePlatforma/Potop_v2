class_name DiveThreatRuntimeState
extends RefCounted


var threat_id: String = ""
var definition
var position: Vector2 = Vector2.ZERO
var alert_level: float = 0.0
var attack_cooldown_left: float = 0.0


func _init(
	id: String = "",
	threat_definition = null,
	world_position: Vector2 = Vector2.ZERO
) -> void:
	threat_id = id
	definition = threat_definition
	position = world_position


func reset() -> void:
	alert_level = 0.0
	attack_cooldown_left = 0.0


func duplicate_state():
	var copy = get_script().new(threat_id, definition, position)
	copy.alert_level = alert_level
	copy.attack_cooldown_left = attack_cooldown_left
	return copy


func snapshot() -> Dictionary:
	return {
		"id": threat_id,
		"definition_id": str(definition.id) if definition != null else "",
		"position": position,
		"alert": alert_level,
		"cooldown": attack_cooldown_left,
	}
