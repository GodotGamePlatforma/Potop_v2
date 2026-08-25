class_name DiveRescueSurvivor
extends Area2D

const LeonTrappedTexture := preload("res://underwater_map_workbench/assets/gameplay/rescue/leon_trapped.png")
const LeonFreedTexture := preload("res://underwater_map_workbench/assets/gameplay/rescue/leon_freed.png")
const LeonTowingTexture := preload("res://underwater_map_workbench/assets/gameplay/rescue/leon_towing.png")
const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")
const VisualStyle := preload("res://scripts/diving/DiveInteractableVisualStyle.gd")

enum Stage {
	TRAPPED,
	FREED,
	TOWING,
}

@export var encounter_id: String = ""
@export var definition: Resource
@export var interaction_seconds: float = 2.2
@export var required_tool: String = "crowbar"
@export var interaction_action: String = "pry"
@export var stage: Stage = Stage.TRAPPED

var campaign_stage: Stage = Stage.TRAPPED
var _tow_target: Node2D
var _sprite: Sprite2D
var _trapped_debris_beam: Line2D
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
		var shape := CircleShape2D.new()
		shape.radius = 72.0
		collision.shape = shape
		add_child(collision)
	queue_redraw()

func _process(delta: float) -> void:
	if stage != Stage.TOWING or _tow_target == null or not is_instance_valid(_tow_target):
		return
	var target_position := _tow_target.global_position + Vector2(-58.0, 28.0)
	global_position = global_position.lerp(target_position, clampf(delta * 7.0, 0.0, 1.0))

func configure(id: String, rescue_definition: Resource, initial_stage: Stage = Stage.TRAPPED) -> void:
	encounter_id = id
	definition = rescue_definition
	campaign_stage = initial_stage
	stage = initial_stage
	_apply_interaction_contract()
	_refresh_visual()
	queue_redraw()

func reset_attempt() -> void:
	stage = campaign_stage
	_tow_target = null
	process_mode = Node.PROCESS_MODE_INHERIT
	_apply_interaction_contract()
	_refresh_visual()
	queue_redraw()

func mark_freed() -> void:
	stage = Stage.FREED
	_apply_interaction_contract()
	_refresh_visual()
	queue_redraw()

func begin_tow(target: Node2D) -> void:
	stage = Stage.TOWING
	_tow_target = target
	_apply_interaction_contract()
	_refresh_visual()
	queue_redraw()

func can_interact() -> bool:
	return stage in [Stage.TRAPPED, Stage.FREED]

func interaction_text() -> String:
	var interact_prompt := InputPromptScript.action_text(&"dive_interact")
	if definition == null:
		return "Przytrzymaj %s: pomóż ocalałemu" % interact_prompt
	if stage == Stage.FREED:
		return "Przytrzymaj %s: zdecyduj o losie (%s)" % [interact_prompt, str(definition.display_name)]
	return "Przytrzymaj %s: uwolnij ocalałego łomem (%s)" % [interact_prompt, str(definition.display_name)]

func required_tool_display_name() -> String:
	match required_tool:
		"crowbar":
			return "łom"
		"knife":
			return "nóż"
	return required_tool.replace("_", " ")

func set_authored_visual_override(enabled: bool) -> void:
	_authored_visual_override = enabled
	_refresh_visual()
	queue_redraw()

func configure_visual_context(context: Dictionary, explicit_region_hint: String = "") -> void:
	_visual_context = context.duplicate(true)
	_visual_region_id = VisualStyle.resolve_region(explicit_region_hint, _visual_context, encounter_id)
	_refresh_visual()
	queue_redraw()


func sync_visual_context(context: Dictionary, explicit_region_hint: String = "", minimum_depth_delta: float = 0.01) -> bool:
	var next_context := context.duplicate(true)
	var next_region := VisualStyle.resolve_region(explicit_region_hint, next_context, encounter_id)
	var next_depth := clampf(float(next_context.get("depth_ratio", 0.0)), 0.0, 1.0)
	var current_depth := float(_visual_context.get("depth_ratio", -1.0))
	if (
		next_region == _visual_region_id
		and current_depth >= 0.0
		and absf(next_depth - current_depth) < maxf(minimum_depth_delta, 0.0)
	):
		return false
	_visual_context = next_context
	_visual_region_id = next_region
	_refresh_visual()
	queue_redraw()
	return true

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
	match stage:
		Stage.TRAPPED:
			return LeonTrappedTexture
		Stage.FREED:
			return LeonFreedTexture
		Stage.TOWING:
			return LeonTowingTexture
	return null

func _apply_interaction_contract() -> void:
	match stage:
		Stage.TRAPPED:
			interaction_seconds = maxf(float(definition.freeing_seconds), 0.1) if definition != null else 2.2
			required_tool = str(definition.required_tool) if definition != null else "crowbar"
		Stage.FREED:
			interaction_seconds = 0.35
			required_tool = ""
		_:
			interaction_seconds = 0.35
			required_tool = ""

func _build_visual() -> void:
	_sprite = get_node_or_null("RescueSprite") as Sprite2D
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "RescueSprite"
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(_sprite)
	_trapped_debris_beam = get_node_or_null("TrappedDebrisBeam") as Line2D
	if _trapped_debris_beam == null:
		_trapped_debris_beam = Line2D.new()
		_trapped_debris_beam.name = "TrappedDebrisBeam"
		_trapped_debris_beam.z_index = 1
		_trapped_debris_beam.width = 8.0
		_trapped_debris_beam.antialiased = true
		_trapped_debris_beam.joint_mode = Line2D.LINE_JOINT_BEVEL
		_trapped_debris_beam.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_trapped_debris_beam.end_cap_mode = Line2D.LINE_CAP_ROUND
		_trapped_debris_beam.points = PackedVector2Array([
			Vector2(-72.0, 44.0),
			Vector2(-62.0, -6.0),
			Vector2(-30.0, -42.0),
			Vector2(8.0, -35.0),
		])
		add_child(_trapped_debris_beam)
	_refresh_visual()

func _refresh_visual() -> void:
	if _sprite == null:
		return
	_sprite.texture = visual_texture()
	_sprite.scale = Vector2.ONE * (0.66 if stage == Stage.TOWING else 0.74)
	_sprite.position = Vector2(12.0, 6.0) if stage == Stage.TRAPPED else Vector2.ZERO
	_sprite.visible = not _authored_visual_override
	if _trapped_debris_beam != null:
		var palette := VisualStyle.palette(_visual_region_id)
		var beam_color: Color = palette.get("body_dark", Color("142b31"))
		_trapped_debris_beam.default_color = Color(beam_color.r, beam_color.g, beam_color.b, 0.92)
		_trapped_debris_beam.width = 7.0 if _graphics_quality == "low" else 8.0
		_trapped_debris_beam.visible = stage == Stage.TRAPPED and not _authored_visual_override
	if _sprite.visible:
		VisualStyle.apply_sprite(
			_sprite,
			_visual_region_id,
			encounter_id if not encounter_id.is_empty() else "rescue_survivor",
			_graphics_quality,
			0.9 if stage == Stage.TOWING else 1.0
		)
	var survivor_id := encounter_id if not encounter_id.is_empty() else "rescue_survivor"
	VisualStyle.configure_effect(
		self,
		_sprite,
		"rescue",
		_visual_region_id,
		survivor_id,
		_graphics_quality,
		_reduced_motion,
		stage != Stage.TRAPPED,
		80.0,
		_visual_context,
		_stage_tag()
	)

func _stage_tag() -> String:
	match stage:
		Stage.TRAPPED:
			return "trapped"
		Stage.FREED:
			return "freed"
		Stage.TOWING:
			return "towing"
	return "trapped"

func _draw() -> void:
	var survivor_id := encounter_id if not encounter_id.is_empty() else "rescue_survivor"
	var resolved := stage != Stage.TRAPPED
	VisualStyle.draw_grounding(self, 80.0, _visual_region_id, survivor_id, _graphics_quality, resolved)
	if _authored_visual_override:
		return
	var palette := VisualStyle.palette(_visual_region_id)
	var outline: Color = palette.get("rim", Color("7ce6d2")) if resolved else palette.get("accent", Color("efb45c"))
	if stage == Stage.TOWING:
		# Lina jest sygnałem stanu i kierunku, niezależnym od regionalnej barwy.
		draw_line(Vector2(55, 0), Vector2(58, -28), Color(outline.r, outline.g, outline.b, 0.84), 2.5, true)
		draw_circle(Vector2(58, -28), 3.5, Color(0.82, 0.77, 0.49, 0.9))
