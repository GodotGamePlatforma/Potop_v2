class_name WorkshopRecipeDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var output_gear_id: String = ""
@export var output_campaign_id: String = ""
@export var required_workshop_level: int = 1
@export var required_work_points: int = 100
@export var prerequisite_gear_id: String = ""
@export var prerequisite_story_flag: String = ""
@export var craft_cost: Dictionary = {}
