class_name DiveLootContainer
extends Area2D

const SupplyCrateTexture := preload("res://assets/diving/interactables/supply_crate.png")
const ToolLockerTexture := preload("res://assets/diving/interactables/tool_locker.png")
const LostBackpackTexture := preload("res://assets/diving/interactables/lost_backpack.png")
const DroppedBundleTexture := preload("res://assets/diving/interactables/dropped_bundle.png")
const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")
const VisualStyle := preload("res://scripts/diving/DiveInteractableVisualStyle.gd")

enum VisualKind {
	SUPPLY_CRATE = 0,
	TOOL_LOCKER = 1,
	LOST_BACKPACK = 3,
	DROPPED_BUNDLE = 4,
}

@export var container_id: String = ""
@export var display_name: String = "Zasobnik"
@export var contents: Dictionary = {}
@export var mandatory_order: int = -1
@export var interaction_seconds: float = 1.15
@export var required_tool: String = ""
@export var interaction_action: String = "open"
@export var visual_kind: VisualKind = VisualKind.SUPPLY_CRATE

var opened: bool = false
var initial_contents: Dictionary = {}
var _sprite: Sprite2D
var _authored_visual_override := false
var _semantic_overlay: Node2D
var _visual_context: Dictionary = {}
var _explicit_region_hint: String = ""
var _region_id: String = "R1"
var _graphics_quality: String = "medium"
var _reduced_motion: bool = false
var _visual_semantic_override: String = ""

func _ready() -> void:
	add_to_group("dive_interactable")
	collision_layer = 2
	collision_mask = 0
	if get_node_or_null("CollisionShape2D") == null:
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(92, 62)
		collision.shape = shape
		add_child(collision)
	_build_visual()
	queue_redraw()

func configure(
	id: String,
	title: String,
	loot: Dictionary,
	order: int = -1,
	required_tool_id: String = "",
	action_id: String = "open",
	required_seconds: float = 1.15
) -> void:
	container_id = id
	display_name = title
	initial_contents = loot.duplicate(true)
	contents = initial_contents.duplicate(true)
	opened = contents.is_empty()
	visual_kind = VisualKind.TOOL_LOCKER if action_id == "pry" else VisualKind.SUPPLY_CRATE
	mandatory_order = order
	required_tool = required_tool_id
	interaction_action = action_id
	interaction_seconds = maxf(required_seconds, 0.1)
	_refresh_visual()

func restore_initial_contents() -> void:
	contents = initial_contents.duplicate(true)
	set_opened(contents.is_empty())

func restore_contents(loot: Dictionary) -> void:
	contents = loot.duplicate(true)
	set_opened(contents.is_empty())

func set_opened(value: bool) -> void:
	opened = value
	_refresh_visual()
	queue_redraw()

func set_visual_kind(value: VisualKind) -> void:
	visual_kind = value
	_refresh_visual()
	queue_redraw()

func set_authored_visual_override(enabled: bool) -> void:
	_authored_visual_override = enabled
	_refresh_visual()
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
	queue_redraw()

func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	queue_redraw()

func set_visual_semantic(semantic_kind: String) -> void:
	_visual_semantic_override = semantic_kind.strip_edges().to_lower()
	_refresh_semantic_overlay()

func visual_texture() -> Texture2D:
	match visual_kind:
		VisualKind.TOOL_LOCKER:
			return ToolLockerTexture
		VisualKind.LOST_BACKPACK:
			return LostBackpackTexture
		VisualKind.DROPPED_BUNDLE:
			return DroppedBundleTexture
	return SupplyCrateTexture

func can_interact() -> bool:
	return not opened

func interaction_text() -> String:
	var interact_prompt := InputPromptScript.action_text(&"dive_interact")
	match interaction_action:
		"pry":
			return "Przytrzymaj %s: podważ łomem (%s)" % [interact_prompt, display_name.to_lower()]
		"cut":
			return "Przytrzymaj %s: przetnij nożem (%s)" % [interact_prompt, display_name.to_lower()]
	return "Przytrzymaj %s: otwórz (%s)" % [interact_prompt, display_name.to_lower()]

func required_tool_display_name() -> String:
	match required_tool:
		"crowbar":
			return "lom"
		"knife":
			return "noz"
		"repair_kit":
			return "zestaw naprawczy"
	return required_tool

func _build_visual() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "ContainerSprite"
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(_sprite)
	if _semantic_overlay == null:
		_semantic_overlay = Node2D.new()
		_semantic_overlay.name = "SemanticMarking"
		_semantic_overlay.z_index = 2
		add_child(_semantic_overlay)
	_refresh_visual()

func _refresh_visual() -> void:
	if _sprite == null:
		return
	_sprite.texture = visual_texture()
	_sprite.position = Vector2.ZERO
	_sprite.rotation = 0.0
	var scale_value := 0.64
	match visual_kind:
		VisualKind.TOOL_LOCKER:
			scale_value = 0.62
		VisualKind.LOST_BACKPACK:
			scale_value = 0.78
		VisualKind.DROPPED_BUNDLE:
			scale_value = 0.86
	_sprite.scale = Vector2.ONE * scale_value
	if opened:
		_sprite.modulate = Color(0.62, 0.72, 0.74, 0.86)
		_sprite.position.y = 3.0
	else:
		_sprite.modulate = Color.WHITE
	_sprite.visible = not _authored_visual_override
	_resolve_visual_region()
	_refresh_visual_style()
	_refresh_semantic_overlay()

func _resolve_visual_region() -> void:
	_region_id = VisualStyle.resolve_region(_explicit_region_hint, _visual_context, _visual_stable_id())

func _refresh_visual_style() -> void:
	if _sprite == null:
		return
	VisualStyle.apply_sprite(
		_sprite,
		_region_id,
		_visual_stable_id(),
		_graphics_quality,
		0.68 if opened else 1.0
	)
	if _semantic_overlay != null:
		_semantic_overlay.modulate.a = 0.50 if opened else 1.0

func _visual_stable_id() -> String:
	if not container_id.is_empty():
		return container_id
	return "%s:%d" % [display_name, int(visual_kind)]

func _semantic_kind() -> String:
	if not _visual_semantic_override.is_empty():
		return _visual_semantic_override
	match visual_kind:
		VisualKind.LOST_BACKPACK:
			return "personal"
		VisualKind.DROPPED_BUNDLE:
			return "bundle"
	var source := initial_contents if not initial_contents.is_empty() else contents
	var scores := {
		"medical": 0,
		"food": 0,
		"construction": 0,
		"technical": 0,
	}
	for item_key in source.keys():
		var item_id := str(item_key).to_lower()
		var amount := maxi(int(source[item_key]), 0)
		if item_id.contains("med") or item_id.contains("medicine") or item_id.contains("antibi") or item_id.contains("lek"):
			scores["medical"] += amount
		elif item_id.contains("food") or item_id.contains("ration") or item_id.contains("zywn"):
			scores["food"] += amount
		elif item_id.contains("plank") or item_id.contains("wood") or item_id.contains("des"):
			scores["construction"] += amount
		elif item_id.contains("scrap") or item_id.contains("tech") or item_id.contains("part") or item_id.contains("metal"):
			scores["technical"] += amount
	var total := 0
	var represented := 0
	var strongest := "mixed"
	var strongest_score := 0
	for kind in scores.keys():
		var score := int(scores[kind])
		total += score
		if score > 0:
			represented += 1
		if score > strongest_score:
			strongest = str(kind)
			strongest_score = score
	if represented == 1 or (total > 0 and float(strongest_score) / float(total) >= 0.68):
		return strongest
	return "mixed"

func _refresh_semantic_overlay() -> void:
	if _semantic_overlay == null:
		return
	for child in _semantic_overlay.get_children():
		_semantic_overlay.remove_child(child)
		child.queue_free()
	_semantic_overlay.visible = not _authored_visual_override
	if _authored_visual_override:
		return
	var palette_data := VisualStyle.palette(_region_id)
	var accent: Color = palette_data.get("accent", Color("72cfd0"))
	var shadow: Color = palette_data.get("shadow", Color("07161c"))
	accent.a = 0.78
	shadow.a = 0.66
	var seed_fraction := float(posmod(_visual_stable_id().hash(), 101)) / 100.0
	_semantic_overlay.rotation = lerpf(-0.035, 0.035, seed_fraction)
	_semantic_overlay.position = Vector2(0.0, -4.0)
	match visual_kind:
		VisualKind.LOST_BACKPACK:
			_semantic_overlay.position = Vector2(0.0, 2.0)
		VisualKind.DROPPED_BUNDLE:
			_semantic_overlay.position = Vector2(0.0, 1.0)
	_add_mark_polygon(PackedVector2Array([
		Vector2(-13, -10), Vector2(13, -10), Vector2(13, 10), Vector2(-13, 10),
	]), shadow)
	_add_mark_line(PackedVector2Array([
		Vector2(-13, -10), Vector2(13, -10), Vector2(13, 10), Vector2(-13, 10), Vector2(-13, -10),
	]), Color(accent.r, accent.g, accent.b, 0.42), 1.2)
	_draw_semantic_icon(_semantic_kind(), accent)

func _draw_semantic_icon(kind: String, color: Color) -> void:
	match kind:
		"medical":
			_add_mark_line(PackedVector2Array([Vector2(-7, 0), Vector2(7, 0)]), color, 3.2)
			_add_mark_line(PackedVector2Array([Vector2(0, -7), Vector2(0, 7)]), color, 3.2)
		"food":
			_add_mark_polygon(PackedVector2Array([
				Vector2(-7, 2), Vector2(-3, -6), Vector2(6, -7), Vector2(8, 0), Vector2(2, 6),
			]), Color(color.r, color.g, color.b, 0.52))
			_add_mark_line(PackedVector2Array([Vector2(-7, 7), Vector2(3, -3)]), color, 1.8)
		"construction":
			_add_mark_line(PackedVector2Array([Vector2(-8, 7), Vector2(6, -7)]), color, 3.0)
			_add_mark_line(PackedVector2Array([Vector2(-3, 8), Vector2(9, -4)]), Color(color.r, color.g, color.b, 0.60), 2.2)
			_add_mark_line(PackedVector2Array([Vector2(-8, -5), Vector2(7, 7)]), color, 2.0)
		"technical":
			_add_mark_line(PackedVector2Array([
				Vector2(-8, -5), Vector2(3, -5), Vector2(3, -1), Vector2(8, -1),
			]), color, 1.8)
			_add_mark_line(PackedVector2Array([
				Vector2(-8, 5), Vector2(-2, 5), Vector2(-2, 1), Vector2(8, 1),
			]), color, 1.8)
			_add_mark_disc(Vector2(-8, -5), 2.0, color)
			_add_mark_disc(Vector2(-8, 5), 2.0, color)
		"hazard":
			_add_mark_line(PackedVector2Array([
				Vector2(0, -8), Vector2(9, 7), Vector2(-9, 7), Vector2(0, -8),
			]), color, 2.0)
			_add_mark_line(PackedVector2Array([Vector2(0, -3), Vector2(0, 2)]), color, 2.2)
			_add_mark_disc(Vector2(0, 5), 1.5, color)
		"personal":
			_add_mark_line(PackedVector2Array([
				Vector2(-7, 7), Vector2(-7, -3), Vector2(-3, -7), Vector2(3, -7), Vector2(7, -3), Vector2(7, 7),
			]), color, 2.2)
			_add_mark_line(PackedVector2Array([Vector2(-7, -1), Vector2(7, -1)]), color, 1.5)
		"bundle":
			_add_mark_line(PackedVector2Array([Vector2(-8, -7), Vector2(8, 7)]), color, 2.2)
			_add_mark_line(PackedVector2Array([Vector2(8, -7), Vector2(-8, 7)]), color, 2.2)
			_add_mark_line(PackedVector2Array([Vector2(-10, 0), Vector2(10, 0)]), color, 1.5)
		_:
			_add_mark_line(PackedVector2Array([Vector2(-8, -5), Vector2(8, -5)]), color, 2.0)
			_add_mark_line(PackedVector2Array([Vector2(-6, 0), Vector2(6, 0)]), Color(color.r, color.g, color.b, 0.72), 2.0)
			_add_mark_line(PackedVector2Array([Vector2(-4, 5), Vector2(4, 5)]), Color(color.r, color.g, color.b, 0.48), 2.0)

func _add_mark_line(points: PackedVector2Array, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = color
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = true
	_semantic_overlay.add_child(line)

func _add_mark_polygon(points: PackedVector2Array, color: Color) -> void:
	var polygon := Polygon2D.new()
	polygon.polygon = points
	polygon.color = color
	_semantic_overlay.add_child(polygon)

func _add_mark_disc(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	_add_mark_polygon(points, color)

func _draw() -> void:
	if _authored_visual_override:
		return
	var radius := 49.0 if visual_kind in [VisualKind.LOST_BACKPACK, VisualKind.DROPPED_BUNDLE] else 57.0
	VisualStyle.draw_grounding(self, radius, _region_id, _visual_stable_id(), _graphics_quality, opened)
	VisualStyle.draw_signal_arcs(
		self,
		radius,
		_region_id,
		_visual_stable_id(),
		_graphics_quality,
		opened,
		1.18 if mandatory_order >= 0 else 1.0
	)
	var palette_data := VisualStyle.palette(_region_id)
	var outline: Color = palette_data.get("accent", Color("72cfd0"))
	if mandatory_order >= 0 and not opened:
		var notch_count := clampi(mandatory_order + 1, 1, 3)
		for index in range(notch_count):
			var x := (float(index) - float(notch_count - 1) * 0.5) * 7.0
			draw_line(Vector2(x, radius - 1.0), Vector2(x, radius + 5.0), Color(outline.r, outline.g, outline.b, 0.86), 2.0, true)
	if opened and visual_kind in [VisualKind.SUPPLY_CRATE, VisualKind.TOOL_LOCKER]:
		draw_line(Vector2(-41, -31), Vector2(28, -58), Color(outline.r, outline.g, outline.b, 0.48), 7.0, true)
		draw_circle(Vector2(35, -52), 3.0, Color(outline.r, outline.g, outline.b, 0.62))
