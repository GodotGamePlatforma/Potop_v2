class_name DivingGearDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var equipment_slot: String = ""
@export var tier: int = 1
@export var oxygen_capacity: float = 0.0
@export var light_inner_radius: float = 0.0
@export var light_outer_radius: float = 0.0
@export var light_energy: float = 1.0
@export var light_color: Color = Color.WHITE
@export_range(0, 500, 1) var weapon_damage: int = 0
@export_range(0.0, 2000.0, 1.0) var weapon_range: float = 0.0
@export_range(0.0, 10.0, 0.05) var weapon_cooldown: float = 0.0
@export_range(0, 30, 1) var ammunition_per_dive: int = 0
@export var is_emergency_default: bool = false

func is_valid_light() -> bool:
	return equipment_slot == "light" and light_inner_radius > 0.0 and light_outer_radius > light_inner_radius

func is_valid_oxygen_tank() -> bool:
	return equipment_slot == "oxygen_tank" and oxygen_capacity > 0.0

func is_valid_weapon() -> bool:
	return equipment_slot == "weapon" and weapon_damage > 0 and weapon_range > 0.0 and weapon_cooldown > 0.0 and ammunition_per_dive > 0
