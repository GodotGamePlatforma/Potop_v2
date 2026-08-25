class_name DiveExitLine
extends Area2D

const ReturnLineTexture := preload("res://underwater_map_workbench/assets/gameplay/interactables/return_line.png")
const ReturnBellTexture := preload("res://underwater_map_workbench/assets/gameplay/interactables/return_bell.png")
const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")
const VisualStyle := preload("res://scripts/diving/DiveInteractableVisualStyle.gd")

@export var interaction_seconds: float = 0.45
@export_range(1, 4, 1) var support_level: int = 1

var _sprite: Sprite2D
var _authored_visual_override := false
var _visual_context: Dictionary = {}
var _visual_region_id := "r1"
var _graphics_quality := "high"
var _reduced_motion := false

func _ready() -> void:
	add_to_group("dive_interactable")
	collision_layer = 2
	collision_mask = 0
	_build_visual()
	if get_node_or_null("CollisionShape2D") == null:
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(110, 330)
		collision.shape = shape
		add_child(collision)
	queue_redraw()

func configure(level: int) -> void:
	support_level = clampi(level, 1, 4)
	_refresh_visual()
	queue_redraw()

func set_authored_visual_override(enabled: bool) -> void:
	_authored_visual_override = enabled
	_refresh_visual()
	queue_redraw()

func configure_visual_context(context: Dictionary, explicit_region_hint: String = "") -> void:
	_visual_context = context.duplicate(true)
	_visual_region_id = VisualStyle.resolve_region(explicit_region_hint, _visual_context, "return_line")
	_refresh_visual()
	queue_redraw()

func set_graphics_quality(quality_id: String) -> void:
	_graphics_quality = VisualStyle.normalize_quality(quality_id)
	_refresh_visual()
	queue_redraw()

func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	_refresh_visual()
	queue_redraw()

func set_interaction_presentation(focused: bool, progress: float) -> void:
	VisualStyle.set_effect_interaction(self, focused, progress)

func set_visual_time_for_tests(time_seconds: float) -> void:
	VisualStyle.set_effect_time_for_tests(self, time_seconds)

func release_visual_time_override() -> void:
	VisualStyle.release_effect_time_override(self)

func visual_effect_state_for_tests() -> Dictionary:
	return VisualStyle.effect_state(self)

func visual_texture() -> Texture2D:
	return ReturnBellTexture if support_level >= 4 else ReturnLineTexture

func can_interact() -> bool:
	return true

func interaction_text() -> String:
	return "Przytrzymaj %s: wróć na platformę" % InputPromptScript.action_text(&"dive_interact")

func _build_visual() -> void:
	_sprite = get_node_or_null("ExitLineSprite") as Sprite2D
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "ExitLineSprite"
		_sprite.position = Vector2(0, -64)
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(_sprite)
	_refresh_visual()

func _refresh_visual() -> void:
	if _sprite == null:
		return
	_sprite.texture = visual_texture()
	_sprite.visible = not _authored_visual_override
	if _sprite.visible:
		VisualStyle.apply_sprite(
			_sprite,
			_visual_region_id,
			"return_bell" if support_level >= 4 else "return_line",
			_graphics_quality,
			1.0
		)
	var exit_id := "return_bell" if support_level >= 4 else "return_line"
	VisualStyle.configure_effect(
		self,
		_sprite,
		"exit",
		_visual_region_id,
		exit_id,
		_graphics_quality,
		_reduced_motion,
		support_level >= 4,
		88.0,
		_visual_context,
		exit_id
	)

func _draw() -> void:
	var exit_id := "return_bell" if support_level >= 4 else "return_line"
	VisualStyle.draw_grounding(self, 88.0, _visual_region_id, exit_id, _graphics_quality, false)
	VisualStyle.draw_signal_arcs(self, 78.0, _visual_region_id, exit_id, _graphics_quality, false, 1.26)
