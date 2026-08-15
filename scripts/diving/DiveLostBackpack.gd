class_name DiveLostBackpack
extends DiveLootContainer

@export var owner_diver_id: String = ""
@export var gear_ids: Array[String] = []
@export var lost_on_day: int = 0

var initial_gear_ids: Array[String] = []

func configure_backpack(backpack_id: String, record: Dictionary) -> void:
	owner_diver_id = str(record.get("diver_id", backpack_id))
	gear_ids.assign(record.get("gear_ids", []))
	initial_gear_ids.assign(gear_ids)
	lost_on_day = int(record.get("lost_on_day", 0))
	configure(
		"lost_backpack:%s" % backpack_id,
		"Plecak: %s" % owner_diver_id.capitalize(),
		record.get("items", {}),
		-1,
		"",
		"recover",
		1.0
	)
	set_visual_kind(VisualKind.LOST_BACKPACK)

func backpack_record_id() -> String:
	return owner_diver_id

func restore_initial_contents() -> void:
	contents = initial_contents.duplicate(true)
	gear_ids.assign(initial_gear_ids)
	set_opened(contents.is_empty() and gear_ids.is_empty())

func build_recovery_update() -> Dictionary:
	return {
		"items": contents.duplicate(true),
		"gear_ids": gear_ids.duplicate(),
		"recovered": contents.is_empty() and gear_ids.is_empty(),
	}

func is_fully_recovered() -> bool:
	return contents.is_empty() and gear_ids.is_empty()

func interaction_text() -> String:
	return "Przytrzymaj %s: odzyskaj %s" % [InputPromptScript.action_text(&"dive_interact"), display_name.to_lower()]
