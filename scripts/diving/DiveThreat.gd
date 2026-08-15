class_name DiveThreat
extends Node2D

@export var threat_id: String = ""

var definition
var alert_level: float = 0.0
var attack_cooldown_left: float = 0.0
var health: int = 1
var _defeated: bool = false
var _sprite: Sprite2D
var _elapsed: float = 0.0
var _phase: float = 0.0
var _authored_visual_override := false

func _ready() -> void:
	_build_visual()
	health = maxi(int(definition.max_health), 1)
	_defeated = false

func configure(id: String, threat_definition) -> void:
	threat_id = id
	definition = threat_definition
	name = id.to_pascal_case()
	z_index = 4
	_phase = float(posmod(threat_id.hash(), 1000)) / 1000.0 * TAU
	health = maxi(int(definition.max_health), 1)
	_defeated = false
	_build_visual()
	queue_redraw()

func reset_attempt() -> void:
	alert_level = 0.0
	attack_cooldown_left = 0.0
	health = maxi(int(definition.max_health), 1) if definition != null else 1
	_defeated = false
	_update_visual_state()
	queue_redraw()

func tick_cooldown(delta: float) -> void:
	attack_cooldown_left = maxf(attack_cooldown_left - maxf(delta, 0.0), 0.0)

func set_alert(value: float) -> void:
	var previous_alert := alert_level
	alert_level = clampf(value, 0.0, 100.0)
	_update_visual_state()
	if not is_equal_approx(alert_level, previous_alert):
		queue_redraw()

func can_attack_now() -> bool:
	return not _defeated and attack_cooldown_left <= 0.0

func is_defeated() -> bool:
	return _defeated

func apply_combat_damage(amount: int) -> bool:
	if _defeated or amount <= 0:
		return _defeated
	health = maxi(health - amount, 0)
	set_alert(100.0)
	if health <= 0:
		_defeated = true
		alert_level = 0.0
	_update_visual_state()
	queue_redraw()
	return _defeated

func mark_attacked() -> void:
	if definition == null:
		return
	attack_cooldown_left = float(definition.attack_cooldown)
	set_alert(float(definition.post_attack_alert))

func warning_text() -> String:
	var title: String = str(definition.display_name) if definition != null else "Zagrozenie"
	return "%s reaguje na halas" % title.to_upper()

func set_authored_visual_override(enabled: bool) -> void:
	_authored_visual_override = enabled
	_update_visual_state()
	queue_redraw()

func visual_texture() -> Texture2D:
	return definition.world_texture if definition != null else null

func _process(delta: float) -> void:
	if _sprite == null:
		return
	_elapsed += delta
	_update_visual_state()

func _build_visual() -> void:
	if definition == null:
		return
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "ThreatSprite"
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(_sprite)
	_sprite.texture = visual_texture()
	_update_visual_state()

func _update_visual_state() -> void:
	if _sprite == null or definition == null:
		return
	var alert_ratio := clampf(alert_level / 100.0, 0.0, 1.0)
	var pulse := sin(_elapsed * (1.25 + alert_ratio * 2.4) + _phase)
	var base_scale := float(definition.world_sprite_scale)
	_sprite.position.y = pulse * (1.4 + alert_ratio * 1.8)
	_sprite.rotation = sin(_elapsed * 0.72 + _phase) * (0.018 + alert_ratio * 0.018)
	_sprite.scale = Vector2.ONE * base_scale * (1.0 + pulse * (0.012 + alert_ratio * 0.018))
	_sprite.modulate = Color.WHITE.lerp(Color("ffd1c8"), alert_ratio * 0.42)
	_sprite.visible = not _authored_visual_override
	visible = not _defeated

func _draw() -> void:
	if _authored_visual_override:
		return
	var accent: Color = definition.accent_color if definition != null else Color("d47768")
	var alert_ratio := clampf(alert_level / 100.0, 0.0, 1.0)
	draw_circle(Vector2.ZERO, 76.0, Color(accent.r, accent.g, accent.b, 0.035 + alert_ratio * 0.12))
	if alert_level > 0.0:
		draw_arc(Vector2.ZERO, 88.0, -PI * 0.5, -PI * 0.5 + TAU * alert_ratio, 48, accent, 3.0, true)
