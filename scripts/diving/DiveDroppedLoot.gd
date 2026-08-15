class_name DiveDroppedLoot
extends DiveLootContainer

@export var persistence_id: String = ""
@export var landmark_id: String = ""
@export var created_day: int = 0
@export var created_in_session: bool = false

func configure_dropped_loot(pile_id: String, record: Dictionary, is_created_in_session: bool = false) -> void:
	persistence_id = pile_id.strip_edges()
	if persistence_id.is_empty():
		persistence_id = str(record.get("persistence_id", "")).strip_edges()
	landmark_id = str(record.get("landmark_id", ""))
	created_day = maxi(int(record.get("created_day", 0)), 0)
	created_in_session = is_created_in_session
	var loot := _normalized_items(record.get("items", {}))
	configure(
		"dropped_loot:%s" % persistence_id,
		"Porzucony pakunek",
		loot,
		-1,
		"",
		"recover",
		0.65
	)
	set_visual_kind(VisualKind.DROPPED_BUNDLE)
	set_opened(loot.is_empty())

func build_persistence_update() -> Dictionary:
	var remaining_items := _normalized_items(contents)
	return {
		"persistence_id": persistence_id,
		"world_position": global_position,
		"landmark_id": landmark_id,
		"items": remaining_items,
		"created_day": created_day,
		"recovered": remaining_items.is_empty(),
	}

func interaction_text() -> String:
	return "Przytrzymaj %s: przeszukaj porzucony pakunek" % InputPromptScript.action_text(&"dive_interact")

func _normalized_items(value) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		return result
	for resource_id in value.keys():
		var id := str(resource_id)
		var amount := maxi(int(value[resource_id]), 0)
		if not id.is_empty() and amount > 0:
			result[id] = amount
	return result
