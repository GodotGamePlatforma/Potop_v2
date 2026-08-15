class_name NarrativeSpeakerResolver
extends RefCounted

const NarrativeContentScript := preload("res://scripts/ui/NarrativeContent.gd")

const LINE_TYPE_DIALOGUE := "dialogue"
const LINE_TYPE_STAGE_DIRECTION := "stage_direction"
const LINE_TYPE_WORLD_EVENT := "world_event"


static func normalized_line_type(message: Dictionary) -> String:
	var line_type := str(message.get("line_type", LINE_TYPE_DIALOGUE))
	if line_type in [LINE_TYPE_STAGE_DIRECTION, LINE_TYPE_WORLD_EVENT]:
		return line_type
	return LINE_TYPE_DIALOGUE


static func requires_speaker(message: Dictionary) -> bool:
	return normalized_line_type(message) == LINE_TYPE_DIALOGUE


static func resolve(state, message: Dictionary) -> Dictionary:
	if not requires_speaker(message):
		return {
			"portrait_id": "",
			"display_name": "",
			"role_label": "",
			"has_portrait": false,
			"available": true,
			"neutral_report": false,
		}
	var explicit_id := str(message.get("speaker_id", ""))
	if not explicit_id.is_empty():
		var external_speaker := bool(message.get("external_speaker", false))
		var survivor = state.find_survivor(explicit_id) if state != null and state.has_method("find_survivor") else null
		if not external_speaker and not _is_present_and_alive(survivor):
			return {
				"portrait_id": "",
				"display_name": "",
				"role_label": "",
				"has_portrait": false,
				"available": false,
			}
		return {
			"portrait_id": str(survivor.portrait_id) if survivor != null else explicit_id,
			"display_name": str(survivor.display_name) if survivor != null else str(message.get("speaker_name", explicit_id)),
			"role_label": str(message.get("speaker_role", "NARRATOR")),
			"has_portrait": true,
			"available": true,
			"neutral_report": false,
		}
	var role_id := str(message.get("speaker_role_id", ""))
	var preferred_id := "anka" if role_id == NarrativeContentScript.ROLE_TECHNICAL_VOICE else "mira"
	var building_id := "workshop" if role_id == NarrativeContentScript.ROLE_TECHNICAL_VOICE else "community_house"
	var role_label := "GŁOS TECHNICZNY" if role_id == NarrativeContentScript.ROLE_TECHNICAL_VOICE else "GŁOS PRZYSTANI"
	var survivor = _resolve_role_survivor(state, building_id, preferred_id, role_id)
	if survivor == null:
		return {
			"portrait_id": "",
			"display_name": "RAPORT SYSTEMOWY",
			"role_label": "KOMUNIKAT PRZYSTANI",
			"has_portrait": false,
			"available": true,
			"neutral_report": true,
		}
	return {
		"portrait_id": str(survivor.portrait_id),
		"display_name": str(survivor.display_name),
		"role_label": role_label,
		"has_portrait": true,
		"available": true,
		"neutral_report": false,
	}


static func _resolve_role_survivor(state, building_definition_id: String, preferred_id: String, role_id: String):
	if state == null:
		return null
	var building = state.find_building_by_definition(building_definition_id) if state.has_method("find_building_by_definition") else null
	var building_active: bool = building != null and building.has_method("is_active") and building.is_active()
	var assigned_ids: Array = building.assigned_survivor_ids if building_active else []
	var preferred = state.find_survivor(preferred_id) if state.has_method("find_survivor") else null
	if assigned_ids.has(preferred_id) and _is_eligible(preferred):
		return preferred
	for survivor_id in assigned_ids:
		var assigned = state.find_survivor(str(survivor_id))
		if _is_eligible(assigned):
			return assigned
	if role_id != NarrativeContentScript.ROLE_TECHNICAL_VOICE:
		return null
	if _is_eligible(preferred) and preferred.has_method("has_profession") and preferred.has_profession("mechanik"):
		return preferred
	for survivor in state.get_alive_survivors() if state.has_method("get_alive_survivors") else []:
		if _is_eligible(survivor) and survivor.has_method("has_profession") and survivor.has_profession("mechanik"):
			return survivor
	return null


static func _is_eligible(survivor) -> bool:
	return (
		_is_present_and_alive(survivor)
		and survivor.has_method("can_work")
		and survivor.can_work()
	)


static func _is_present_and_alive(survivor) -> bool:
	return (
		survivor != null
		and survivor.has_method("is_alive")
		and survivor.is_alive()
		and survivor.has_method("is_present_in_settlement")
		and survivor.is_present_in_settlement()
	)
