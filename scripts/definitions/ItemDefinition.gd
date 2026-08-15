class_name ItemDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var stack_limit: int = 99
@export_range(0.01, 1000.0, 0.05) var weight: float = 1.0
@export var tags: Array[String] = []
@export var world_pickup_texture: Texture2D
