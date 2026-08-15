class_name PlatformState
extends Resource

@export var slot_states: Dictionary = {}
@export var support_level: int = 1
@export var fishing_pressure: float = 0.0
@export_range(-0.5, 0.5, 0.001) var repair_scrap_rounding_carry: float = 0.0

func setup_starting_slots() -> void:
	repair_scrap_rounding_carry = 0.0
	slot_states = {
		"top_left": {"is_edge": true, "definition_id": "fishing_hut", "building_id": "", "damaged": false},
		"top_center": {"is_edge": false, "definition_id": "kitchen", "building_id": "", "damaged": false},
		"top_right": {"is_edge": true, "definition_id": "community_house", "building_id": "", "damaged": false},
		"bottom_left": {"is_edge": true, "definition_id": "workshop", "building_id": "", "damaged": false},
		"center": {"is_edge": false, "definition_id": "infirmary", "building_id": "", "damaged": false},
		"bottom_right": {"is_edge": true, "definition_id": "diving_station", "building_id": "", "damaged": false},
	}


func ensure_compatibility() -> void:
	support_level = maxi(support_level, 1)
	fishing_pressure = clampf(fishing_pressure, 0.0, 1.0)
	repair_scrap_rounding_carry = clampf(repair_scrap_rounding_carry, -0.5, 0.5)
