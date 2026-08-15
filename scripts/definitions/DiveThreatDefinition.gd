class_name DiveThreatDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = "Podwodne zagrozenie"
@export_multiline var description: String = ""
@export_range(1.0, 2000.0, 1.0) var noise_detection_radius: float = 360.0
@export_range(1.0, 1000.0, 1.0) var light_detection_radius: float = 150.0
@export_range(0.0, 100.0, 0.5) var noise_threshold: float = 18.0
@export_range(0.0, 10.0, 0.05) var light_sensitivity: float = 0.35
@export_range(0.1, 200.0, 0.5) var alert_rate: float = 52.0
@export_range(0.0, 100.0, 0.5) var alert_decay_rate: float = 15.0
@export_range(0.0, 100.0, 0.5) var warning_threshold: float = 38.0
@export_range(0.0, 100.0, 0.5) var attack_threshold: float = 100.0
@export_range(1.0, 500.0, 1.0) var attack_radius: float = 185.0
@export_range(0.1, 30.0, 0.1) var attack_cooldown: float = 4.0
@export_range(0.0, 100.0, 0.5) var post_attack_alert: float = 28.0
@export_range(0, 100) var attack_suit_damage: int = 22
@export_range(0, 100) var attack_health_damage: int = 5
@export_range(1, 1000, 1) var max_health: int = 100
@export var accent_color: Color = Color("d47768")
@export var world_texture: Texture2D
@export_range(0.1, 2.0, 0.01) var world_sprite_scale: float = 1.0

func is_valid() -> bool:
	return not id.is_empty() \
		and not display_name.is_empty() \
		and noise_detection_radius > 0.0 \
		and attack_radius > 0.0 \
		and attack_threshold >= warning_threshold \
		and attack_suit_damage > 0 \
		and max_health > 0 \
		and world_texture != null \
		and world_sprite_scale > 0.0
