class_name RescueEncounterDefinition
extends Resource

@export var id: String = ""
@export var survivor_id: String = ""
@export var display_name: String = ""
@export var age_group: String = "adult"
@export var biography: String = ""
@export var profession: String = ""
@export var positive_trait: String = ""
@export var negative_trait: String = ""
@export var portrait_id: String = ""
@export var required_tool: String = "crowbar"
@export_range(0.1, 10.0, 0.1) var freeing_seconds: float = 2.2
@export_range(0, 10) var stabilization_medicine_cost: int = 1
@export_range(1, 100) var stabilized_health: int = 48
@export_range(1, 100) var unstabilized_health: int = 24
@export_range(0.1, 1.0, 0.01) var stabilized_movement_multiplier: float = 0.64
@export_range(0.1, 1.0, 0.01) var unstabilized_movement_multiplier: float = 0.48
@export_range(1.0, 4.0, 0.05) var stabilized_oxygen_multiplier: float = 1.25
@export_range(1.0, 4.0, 0.05) var unstabilized_oxygen_multiplier: float = 1.55

func is_valid() -> bool:
	return (
		not id.is_empty()
		and not survivor_id.is_empty()
		and not display_name.is_empty()
		and not profession.is_empty()
		and freeing_seconds > 0.0
		and stabilization_medicine_cost >= 0
		and stabilized_health > unstabilized_health
		and stabilized_movement_multiplier >= unstabilized_movement_multiplier
		and stabilized_oxygen_multiplier <= unstabilized_oxygen_multiplier
	)
