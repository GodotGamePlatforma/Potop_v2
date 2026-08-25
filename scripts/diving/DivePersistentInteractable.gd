class_name DivePersistentInteractable
extends Area2D

const ReturnBuoyTexture := preload("res://underwater_map_workbench/assets/gameplay/interactables/return_buoy.png")
const ShortcutGateTexture := preload("res://underwater_map_workbench/assets/gameplay/interactables/shortcut_gate.png")
const IndustrialGeneratorTexture := preload("res://underwater_map_workbench/assets/gameplay/interactables/industrial_generator.png")
const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")
const VisualStyle := preload("res://scripts/diving/DiveInteractableVisualStyle.gd")

enum Kind {
	BUOY,
	SHORTCUT,
	HEAVY_OBJECT,
	FIXED_DEVICE,
}

@export var kind: Kind = Kind.BUOY
@export var persistent_id: String = ""
@export var display_name: String = "Punkt eksploracji"
@export var interaction_seconds: float = 1.0
@export var required_tool: String = ""
@export var interaction_action: String = "open"
@export var completed: bool = false
@export var campaign_completed: bool = false
@export var gate_width: float = 170.0

var _gate_body: StaticBody2D
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
	if get_node_or_null("CollisionShape2D") == null:
		var interaction_collision := CollisionShape2D.new()
		var interaction_shape := CircleShape2D.new()
		interaction_shape.radius = 70.0
		interaction_collision.shape = interaction_shape
		add_child(interaction_collision)
	if kind == Kind.SHORTCUT:
		_build_gate_body()
	_build_visual()
	_apply_completed_state()

func configure(
	interaction_kind: Kind,
	id: String,
	title: String,
	is_completed: bool,
	tool_id: String = "",
	action_id: String = "open",
	required_seconds: float = 1.0,
	shortcut_width: float = 170.0
) -> void:
	kind = interaction_kind
	persistent_id = id
	display_name = title
	campaign_completed = is_completed
	completed = is_completed
	required_tool = tool_id
	interaction_action = action_id
	interaction_seconds = maxf(required_seconds, 0.1)
	gate_width = maxf(shortcut_width, 80.0)
	if is_inside_tree():
		_refresh_visual()

func reset_attempt() -> void:
	completed = campaign_completed
	_apply_completed_state()

func mark_completed() -> void:
	completed = true
	_apply_completed_state()

func can_interact() -> bool:
	return not completed

func interaction_text() -> String:
	var interact_prompt := InputPromptScript.action_text(&"dive_interact")
	match kind:
		Kind.BUOY:
			return "Przytrzymaj %s: ustaw boję (%s)" % [interact_prompt, display_name.to_lower()]
		Kind.SHORTCUT:
			if interaction_action == "cut":
				return "Przytrzymaj %s: przetnij blokadę (%s)" % [interact_prompt, display_name.to_lower()]
			return "Przytrzymaj %s: otwórz skrót (%s)" % [interact_prompt, display_name.to_lower()]
		Kind.HEAVY_OBJECT:
			return "Przytrzymaj %s: oznacz do wydobycia (%s)" % [interact_prompt, display_name.to_lower()]
		Kind.FIXED_DEVICE:
			return "Przytrzymaj %s: uruchom urządzenie (%s)" % [interact_prompt, display_name.to_lower()]
	return "Przytrzymaj %s: użyj" % interact_prompt

func required_tool_display_name() -> String:
	match required_tool:
		"crowbar":
			return "łom"
		"knife":
			return "nóż"
		"lift_bag":
			return "worek wypornościowy"
		"r3_regulator":
			return "Regulator R-3"
		"r3_diagnostic_access":
			return "mapa Archiwum i łom"
		"c4_control_access":
			return "sterowanie Generatora R-3"
		"common_line_splitter":
			return "Rozdzielacz Wspólnej Linii"
	return required_tool

func set_authored_visual_override(enabled: bool) -> void:
	_authored_visual_override = enabled
	_refresh_visual()
	queue_redraw()

func configure_visual_context(context: Dictionary, explicit_region_hint: String = "") -> void:
	_visual_context = context.duplicate(true)
	_visual_region_id = VisualStyle.resolve_region(explicit_region_hint, _visual_context, persistent_id)
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
	match kind:
		Kind.BUOY:
			return ReturnBuoyTexture
		Kind.SHORTCUT:
			return ShortcutGateTexture
		Kind.HEAVY_OBJECT:
			return IndustrialGeneratorTexture
		Kind.FIXED_DEVICE:
			return IndustrialGeneratorTexture
	return null

func _build_visual() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "InteractableSprite"
		add_child(_sprite)
	_refresh_visual()

func _refresh_visual() -> void:
	if _sprite == null:
		return
	_sprite.texture = visual_texture()
	_sprite.position = Vector2.ZERO
	_sprite.rotation = 0.0
	_sprite.visible = true
	_sprite.modulate = Color.WHITE
	match kind:
		Kind.BUOY:
			_sprite.scale = Vector2.ONE * (0.72 if completed else 0.66)
			_sprite.modulate = Color.WHITE if completed else Color(0.58, 0.68, 0.69, 0.82)
		Kind.SHORTCUT:
			_sprite.scale = Vector2(gate_width / 236.0, 0.68)
			_sprite.visible = not completed
		Kind.HEAVY_OBJECT:
			_sprite.scale = Vector2.ONE * 0.78
			if completed:
				_sprite.modulate = Color(0.78, 1.0, 0.86, 1.0)
		Kind.FIXED_DEVICE:
			_sprite.scale = Vector2.ONE * 0.7
			_sprite.modulate = Color(0.62, 1.0, 0.82, 1.0) if completed else Color(0.72, 0.78, 0.82, 0.9)
	if _authored_visual_override:
		_sprite.visible = false
	if _sprite.visible:
		VisualStyle.apply_sprite(
			_sprite,
			_visual_region_id,
			persistent_id if not persistent_id.is_empty() else display_name,
			_graphics_quality,
			0.82 if completed else 1.0
		)
	VisualStyle.configure_effect(
		self,
		_sprite,
		_effect_role(),
		_visual_region_id,
		persistent_id if not persistent_id.is_empty() else display_name,
		_graphics_quality,
		_reduced_motion,
		completed,
		_effect_radius(),
		_visual_context,
		persistent_id
	)
	_refresh_authored_visual_visibility()

func _effect_role() -> String:
	match kind:
		Kind.BUOY:
			return "buoy"
		Kind.SHORTCUT:
			return "shortcut"
		Kind.HEAVY_OBJECT:
			return "heavy"
		Kind.FIXED_DEVICE:
			return "device"
	return "device"

func _effect_radius() -> float:
	match kind:
		Kind.BUOY:
			return 66.0
		Kind.SHORTCUT:
			return clampf(gate_width * 0.42, 58.0, 92.0)
		Kind.HEAVY_OBJECT:
			return 78.0
		Kind.FIXED_DEVICE:
			return 72.0
	return 72.0

func _refresh_authored_visual_visibility() -> void:
	for child in get_children():
		if child is CanvasItem and child.has_meta(&"authored_map_visual"):
			(child as CanvasItem).visible = not (kind == Kind.SHORTCUT and completed)

func _build_gate_body() -> void:
	_gate_body = StaticBody2D.new()
	_gate_body.name = "ShortcutGateCollision"
	_gate_body.collision_layer = 1
	_gate_body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(gate_width, 28.0)
	collision.shape = shape
	_gate_body.add_child(collision)
	add_child(_gate_body)

func _apply_completed_state() -> void:
	if _gate_body != null:
		_gate_body.process_mode = Node.PROCESS_MODE_DISABLED if completed else Node.PROCESS_MODE_INHERIT
		_gate_body.visible = not completed
		var collision := _gate_body.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision != null:
			collision.disabled = completed
	_refresh_visual()
	queue_redraw()

func _draw() -> void:
	if _authored_visual_override:
		_draw_authored_visual_signal()
		return
	match kind:
		Kind.BUOY:
			_draw_buoy()
		Kind.SHORTCUT:
			_draw_shortcut()
		Kind.HEAVY_OBJECT:
			_draw_heavy_object()
		Kind.FIXED_DEVICE:
			_draw_fixed_device()

func _draw_authored_visual_signal() -> void:
	# Prefab authoringowy jest właścicielem sylwetki, ten node zachowuje wyłącznie stan i czytelność interakcji.
	match kind:
		Kind.BUOY:
			VisualStyle.draw_grounding(self, 66.0, _visual_region_id, persistent_id, _graphics_quality, completed)
			VisualStyle.draw_signal_arcs(self, 56.0, _visual_region_id, persistent_id, _graphics_quality, completed, 1.18)
		Kind.SHORTCUT:
			VisualStyle.draw_grounding(self, maxf(gate_width * 0.48, 72.0), _visual_region_id, persistent_id, _graphics_quality, completed)
			VisualStyle.draw_signal_arcs(self, clampf(gate_width * 0.42, 58.0, 92.0), _visual_region_id, persistent_id, _graphics_quality, completed, 0.88)
		Kind.HEAVY_OBJECT:
			VisualStyle.draw_grounding(self, 78.0, _visual_region_id, persistent_id, _graphics_quality, completed)
			VisualStyle.draw_signal_arcs(self, 68.0, _visual_region_id, persistent_id, _graphics_quality, completed, 0.9)
		Kind.FIXED_DEVICE:
			VisualStyle.draw_grounding(self, 72.0, _visual_region_id, persistent_id, _graphics_quality, completed)
			VisualStyle.draw_signal_arcs(self, 67.0, _visual_region_id, persistent_id, _graphics_quality, completed, 1.08)

func _draw_fixed_device() -> void:
	VisualStyle.draw_grounding(self, 72.0, _visual_region_id, persistent_id, _graphics_quality, completed)
	VisualStyle.draw_signal_arcs(self, 67.0, _visual_region_id, persistent_id, _graphics_quality, completed, 1.08)
	_draw_generator_detail()

func _draw_buoy() -> void:
	VisualStyle.draw_grounding(self, 66.0, _visual_region_id, persistent_id, _graphics_quality, completed)
	VisualStyle.draw_signal_arcs(self, 56.0, _visual_region_id, persistent_id, _graphics_quality, completed, 1.18)
	var colors := _palette()
	var signal_color: Color = colors.get("rim", Color("67dce7")) if completed else colors.get("accent", Color("e8c45f"))
	# Pionowy grot zachowuje unikalny, globalny język boi bez efektu neonowego tokenu.
	draw_line(Vector2(-12.0, -57.0), Vector2(0.0, -69.0), Color(signal_color.r, signal_color.g, signal_color.b, 0.72), 2.0, true)
	draw_line(Vector2(0.0, -69.0), Vector2(12.0, -57.0), Color(signal_color.r, signal_color.g, signal_color.b, 0.72), 2.0, true)

func _draw_shortcut() -> void:
	VisualStyle.draw_grounding(self, maxf(gate_width * 0.48, 72.0), _visual_region_id, persistent_id, _graphics_quality, completed)
	VisualStyle.draw_signal_arcs(self, clampf(gate_width * 0.42, 58.0, 92.0), _visual_region_id, persistent_id, _graphics_quality, completed, 0.88)
	var colors := _palette()
	var outline: Color = colors.get("rim", Color("73c99a")) if completed else colors.get("accent", Color("df8656"))
	if completed:
		draw_line(Vector2(-gate_width * 0.44, 9.0), Vector2(-gate_width * 0.28, -8.0), Color(outline.r, outline.g, outline.b, 0.64), 3.0, true)
		draw_line(Vector2(gate_width * 0.44, 9.0), Vector2(gate_width * 0.28, -8.0), Color(outline.r, outline.g, outline.b, 0.64), 3.0, true)
		return
	draw_rect(Rect2(-gate_width * 0.5 - 5.0, -24.0, gate_width + 10.0, 48.0), Color(outline.r, outline.g, outline.b, 0.34), false, 2.0)

func _draw_heavy_object() -> void:
	VisualStyle.draw_grounding(self, 78.0, _visual_region_id, persistent_id, _graphics_quality, completed)
	VisualStyle.draw_signal_arcs(self, 68.0, _visual_region_id, persistent_id, _graphics_quality, completed, 0.9)
	var colors := _palette()
	var outline: Color = colors.get("rim", Color("72cf9d")) if completed else colors.get("accent", Color("d9a65d"))
	if completed:
		draw_line(Vector2(-48, -52), Vector2(48, -52), Color(outline.r, outline.g, outline.b, 0.86), 4.0, true)
		draw_line(Vector2(-48, -52), Vector2(-32, -35), Color(outline.r, outline.g, outline.b, 0.74), 3.0, true)
		draw_line(Vector2(48, -52), Vector2(32, -35), Color(outline.r, outline.g, outline.b, 0.74), 3.0, true)

func _palette() -> Dictionary:
	return VisualStyle.palette(_visual_region_id)

func _draw_generator_detail() -> void:
	var colors := _palette()
	var accent: Color = colors.get("rim", Color("66e0a3")) if completed else colors.get("accent", Color("76b9d6"))
	var patina: Color = colors.get("patina", Color("728267"))
	# Bitmapa generatora pozostaje czytelna; detal wiąże ją z językiem pozostałych urządzeń.
	draw_line(Vector2(-31, 43), Vector2(28, 43), Color(patina.r, patina.g, patina.b, 0.62), 3.0, true)
	draw_circle(Vector2(39, -28), 5.0, Color(accent.r, accent.g, accent.b, 0.76))
