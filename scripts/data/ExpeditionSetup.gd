class_name ExpeditionSetup
extends Resource

const DEFAULT_OPERATOR_RESCUE_MAX_DISTANCE := 440.0

@export var diver_id: String = ""
@export var diver_display_name: String = ""
@export var diver_profession: String = ""
@export var diver_secondary_profession: String = ""
@export var diver_portrait_id: String = ""
@export var diver_level: int = 1
@export var diver_experience: int = 0
@export var diver_experience_to_next_level: int = 100
@export var diver_health: int = 100
@export var diver_health_capacity: int = 100
@export var diver_personal_oxygen_capacity: float = 100.0
@export var diver_specialist_oxygen_multiplier: float = 1.0
@export var oxygen_tank_capacity: float = 100.0
@export var diver_carry_capacity: float = 18.0
@export var station_staffed_carry_multiplier: float = 1.0
@export var competency_levels: Dictionary = {}
@export var profession_talent_ids: Dictionary = {}
@export var item_weights: Dictionary = {}
@export var selected_gear: Array[String] = []
@export var equipped_gear: Dictionary = {}
@export var weapon_ammunition: int = 0
@export var backpack_capacity: int = 6
@export var oxygen_capacity: float = 100.0
@export var suit_quality: int = 1
@export var start_entry_point: String = "dead_city_rooftops_001"
@export var target_sector: String = "dead_city_rooftops_001"
@export var selected_objective: String = "basic_scavenge"
@export var objective_title: String = ""
@export var objective_guidance: String = ""
@export var objective_target_landmark_id: String = ""
@export var objective_target_label: String = ""
@export var base_support_level: int = 0
@export var station_work_pace_multiplier: float = 1.0
@export var suit_repair_amount: int = 0
@export var operator_assigned: bool = false
@export var technician_assigned: bool = false
@export var operator_survivor_id: String = ""
@export var technician_survivor_id: String = ""
@export var can_place_buoys: bool = false
@export var can_start_from_buoy: bool = false
@export var can_mark_heavy_objects: bool = false
@export var buoy_charges: int = 0
@export var difficulty_modifiers: Dictionary = {}
@export var day: int = 1
@export var tutorial_mode: bool = false
# Transient session baseline. It is intentionally not persisted with campaign saves.
var tutorial_baseline_step: int = -1

func capture_diver(
	survivor,
	equipped_oxygen_tank_capacity: float,
	specialist_oxygen_bonus: float = 0.0,
	specialist_personal_oxygen_multiplier: float = 1.0,
	staffed_carry_multiplier: float = 1.0
) -> void:
	if survivor == null:
		return
	survivor.ensure_compatibility()
	diver_id = survivor.id
	diver_display_name = survivor.display_name
	diver_profession = survivor.profession
	diver_secondary_profession = survivor.secondary_profession
	diver_portrait_id = survivor.portrait_id
	diver_level = survivor.level
	diver_experience = survivor.experience
	diver_experience_to_next_level = survivor.experience_to_next_level()
	diver_health = survivor.health
	diver_health_capacity = survivor.get_max_health()
	diver_personal_oxygen_capacity = survivor.get_oxygen_capacity()
	diver_specialist_oxygen_multiplier = maxf(specialist_personal_oxygen_multiplier, 0.01)
	oxygen_tank_capacity = maxf(equipped_oxygen_tank_capacity, 1.0)
	station_staffed_carry_multiplier = maxf(staffed_carry_multiplier, 0.01)
	diver_carry_capacity = survivor.get_carry_capacity() * station_staffed_carry_multiplier
	competency_levels = survivor.competency_levels.duplicate(true)
	profession_talent_ids = survivor.profession_talent_ids.duplicate(true)
	oxygen_capacity = survivor.get_expedition_oxygen_capacity(
		oxygen_tank_capacity,
		specialist_oxygen_bonus,
		diver_specialist_oxygen_multiplier
	)

func capture_item_weights(item_definitions: Dictionary) -> void:
	item_weights.clear()
	for item_id in item_definitions.keys():
		var definition = item_definitions[item_id]
		if definition == null:
			continue
		item_weights[str(item_id)] = maxf(float(definition.weight), 0.01)
