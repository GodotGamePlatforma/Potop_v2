class_name DiveWorldPickup
extends Area2D

const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")
const VisualStyle := preload("res://scripts/diving/DiveInteractableVisualStyle.gd")

@export var pickup_id: String = ""
@export var resource_id: String = ""
@export var display_name: String = "Zasób"
@export var pickup_texture: Texture2D
@export var interaction_seconds: float = 0.0
@export var collected: bool = false
@export var campaign_collected: bool = false

var _sprite: Sprite2D
var _collision: CollisionShape2D
var _elapsed: float = 0.0
var _phase: float = 0.0
var _authored_visual_override := false
var _visual_context: Dictionary = {}
var _explicit_region_hint: String = ""
var _region_id: String = ""
var _graphics_quality: String = "medium"
var _reduced_motion: bool = false
var _visual_time_locked: bool = false

func _ready() -> void:
	add_to_group("dive_interactable")
	collision_layer = 2
	collision_mask = 0
	_phase = float(posmod(pickup_id.hash(), 1000)) / 1000.0 * TAU
	_build_visual()
	_build_collision()
	_apply_collected_state()

func configure(
	id: String,
	item_id: String,
	title: String,
	texture: Texture2D,
	is_collected: bool = false
) -> void:
	pickup_id = id
	resource_id = item_id
	display_name = title
	pickup_texture = texture
	campaign_collected = is_collected
	collected = is_collected
	_phase = float(posmod(pickup_id.hash(), 1000)) / 1000.0 * TAU
	if is_inside_tree():
		_build_visual()
		_apply_collected_state()

func can_interact() -> bool:
	return not collected

func interaction_text() -> String:
	return "%s: zbierz %s" % [InputPromptScript.action_text(&"dive_interact"), display_name.to_lower()]

func mark_collected() -> void:
	collected = true
	_apply_collected_state()

func reset_attempt() -> void:
	collected = campaign_collected
	_apply_collected_state()

func set_authored_visual_override(enabled: bool) -> void:
	_authored_visual_override = enabled
	if _sprite != null:
		_sprite.visible = not _authored_visual_override
	queue_redraw()

func configure_visual_context(context: Dictionary, explicit_region_hint: String = "") -> void:
	_visual_context = context.duplicate(true)
	_explicit_region_hint = explicit_region_hint.strip_edges()
	_resolve_visual_region()
	_refresh_visual_style()
	queue_redraw()

func set_graphics_quality(quality_id: String) -> void:
	var normalized := VisualStyle.normalize_quality(quality_id)
	if _graphics_quality == normalized:
		return
	_graphics_quality = normalized
	_refresh_visual_style()
	_update_motion_processing()
	queue_redraw()

func set_reduced_motion(enabled: bool) -> void:
	if _reduced_motion == enabled:
		return
	_reduced_motion = enabled
	if _sprite != null and _reduced_motion:
		_sprite.position = Vector2.ZERO
		_sprite.rotation = 0.0
	_refresh_visual_style()
	_update_motion_processing()
	queue_redraw()

func set_interaction_presentation(focused: bool, progress: float) -> void:
	VisualStyle.set_effect_interaction(self, focused, progress)

func set_visual_time_for_tests(time_seconds: float) -> void:
	_elapsed = maxf(time_seconds, 0.0)
	_visual_time_locked = true
	_apply_pickup_motion()
	VisualStyle.set_effect_time_for_tests(self, _elapsed)
	_update_motion_processing()

func release_visual_time_override() -> void:
	_visual_time_locked = false
	VisualStyle.release_effect_time_override(self)
	_update_motion_processing()

func visual_effect_state_for_tests() -> Dictionary:
	return VisualStyle.effect_state(self)

func visual_texture() -> Texture2D:
	return pickup_texture

func _process(delta: float) -> void:
	if collected or _sprite == null:
		return
	_elapsed += delta
	_apply_pickup_motion()

func _apply_pickup_motion() -> void:
	if _sprite == null:
		return
	if collected or _reduced_motion:
		_sprite.position = Vector2.ZERO
		_sprite.rotation = 0.0
		return
	var bob := sin(_elapsed * 1.35 + _phase)
	var motion_scale := 0.52 if VisualStyle.quality_level(_graphics_quality) <= 0 else 0.78 if VisualStyle.quality_level(_graphics_quality) == 1 else 1.0
	_sprite.position.y = bob * 2.2 * motion_scale
	_sprite.rotation = sin(_elapsed * 0.72 + _phase) * 0.025 * motion_scale

func _build_visual() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "PickupSprite"
		add_child(_sprite)
	_sprite.texture = pickup_texture
	_sprite.scale = Vector2.ONE * 0.88
	_sprite.visible = not _authored_visual_override
	_resolve_visual_region()
	_refresh_visual_style()

func _build_collision() -> void:
	if _collision != null:
		return
	_collision = CollisionShape2D.new()
	_collision.name = "CollisionShape2D"
	var shape := CircleShape2D.new()
	shape.radius = 42.0
	_collision.shape = shape
	add_child(_collision)

func _apply_collected_state() -> void:
	visible = not collected
	_refresh_visual_style()
	_update_motion_processing()
	if _collision != null:
		_collision.disabled = collected
	queue_redraw()

func _update_motion_processing() -> void:
	set_process(not collected and not _reduced_motion and not _visual_time_locked)
	if _sprite != null and (collected or _reduced_motion):
		_sprite.position = Vector2.ZERO
		_sprite.rotation = 0.0

func _resolve_visual_region() -> void:
	_region_id = VisualStyle.resolve_region(_explicit_region_hint, _visual_context, _visual_stable_id())

func _refresh_visual_style() -> void:
	if _sprite == null:
		return
	VisualStyle.apply_sprite(_sprite, _region_id, _visual_stable_id(), _graphics_quality, 1.0)
	VisualStyle.configure_effect(
		self,
		_sprite,
		"pickup",
		_region_id,
		_visual_stable_id(),
		_graphics_quality,
		_reduced_motion,
		collected,
		47.0,
		_visual_context,
		resource_id
	)

func _visual_stable_id() -> String:
	if not pickup_id.is_empty():
		return pickup_id
	if not resource_id.is_empty():
		return resource_id
	return display_name

func _draw() -> void:
	if collected or _authored_visual_override:
		return
	VisualStyle.draw_grounding(self, 42.0, _region_id, _visual_stable_id(), _graphics_quality, false)
	VisualStyle.draw_signal_arcs(self, 47.0, _region_id, _visual_stable_id(), _graphics_quality, false, 0.90)
