class_name RescueSystem
extends RefCounted

const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")

const STATUS_RESCUED := "rescued"
const STATUS_DEAD := "dead"

func can_stabilize(session, definition) -> bool:
	if session == null or definition == null:
		return false
	return int(session.carried_items.get(ResourceIdsScript.MEDS_CHEMICALS, 0)) >= int(definition.stabilization_medicine_cost)

func begin_tow(session, encounter, stabilized: bool) -> Dictionary:
	if session == null or encounter == null or encounter.definition == null:
		return {"success": false, "message": "Nie można rozpocząć holowania."}
	if session.towed_survivor != null:
		return {"success": false, "message": "Można holować tylko jedną osobę naraz."}
	var definition = encounter.definition
	if stabilized:
		var cost := int(definition.stabilization_medicine_cost)
		if not can_stabilize(session, definition) or session.remove_item(ResourceIdsScript.MEDS_CHEMICALS, cost) != cost:
			return {"success": false, "message": "W plecaku brakuje leków do stabilizacji."}

	var survivor = _create_survivor(definition, stabilized)
	session.towed_survivor = survivor
	session.towed_rescue_encounter_id = str(encounter.encounter_id)
	session.towed_survivor_stabilized = stabilized
	if not session.rescued_survivor_ids.has(survivor.id):
		session.rescued_survivor_ids.append(survivor.id)
	encounter.begin_tow(null)
	return {
		"success": true,
		"message": "%s jest ustabilizowany i gotowy do holowania." % survivor.display_name if stabilized else "%s jest w stanie krytycznym. Wracaj natychmiast do liny." % survivor.display_name,
		"survivor": survivor,
	}

func attach_tow_target(encounter, diver: Node2D) -> void:
	if encounter != null:
		encounter.begin_tow(diver)

func is_towing(session) -> bool:
	return session != null and session.towed_survivor != null and not str(session.towed_rescue_encounter_id).is_empty()

func movement_multiplier(session, definition) -> float:
	if not is_towing(session) or definition == null:
		return 1.0
	return float(definition.stabilized_movement_multiplier) if session.towed_survivor_stabilized else float(definition.unstabilized_movement_multiplier)

func oxygen_multiplier(session, definition) -> float:
	if not is_towing(session) or definition == null:
		return 1.0
	return float(definition.stabilized_oxygen_multiplier) if session.towed_survivor_stabilized else float(definition.unstabilized_oxygen_multiplier)

func populate_success_result(session, result) -> void:
	if not is_towing(session) or result == null:
		return
	result.rescued_survivors.append(session.towed_survivor.duplicate(true))
	result.rescue_outcomes[session.towed_rescue_encounter_id] = {
		"status": STATUS_RESCUED,
		"survivor_id": session.towed_survivor.id,
		"stabilized": session.towed_survivor_stabilized,
	}

func populate_death_result(session, result) -> void:
	if not is_towing(session) or result == null:
		return
	result.rescue_outcomes[session.towed_rescue_encounter_id] = {
		"status": STATUS_DEAD,
		"survivor_id": session.towed_survivor.id,
		"stabilized": session.towed_survivor_stabilized,
	}

func _create_survivor(definition, stabilized: bool):
	var survivor = SurvivorStateScript.new()
	survivor.id = str(definition.survivor_id)
	survivor.display_name = str(definition.display_name)
	survivor.age_group = str(definition.age_group)
	survivor.biography = str(definition.biography)
	survivor.profession = str(definition.profession)
	survivor.positive_trait = str(definition.positive_trait)
	survivor.negative_trait = str(definition.negative_trait)
	survivor.portrait_id = str(definition.portrait_id)
	survivor.health = int(definition.stabilized_health) if stabilized else int(definition.unstabilized_health)
	survivor.status = SurvivorStateScript.Status.INJURED
	survivor.injury_states.assign(["rescue_recovery" if stabilized else "critical_rescue"])
	survivor.ensure_compatibility()
	return survivor
