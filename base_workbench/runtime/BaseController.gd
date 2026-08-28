extends Control

const BUILDING_ART_DIRECTORY := "res://base_workbench/assets/building_blueprints"

const BaseEnvironmentScript := preload("res://base_workbench/runtime/BaseEnvironment.gd")
const DaySummaryPanelScript := preload("res://base_workbench/ui/DaySummaryPanel.gd")
const DayReportJournalPanelScript := preload("res://base_workbench/ui/DayReportJournalPanel.gd")
const MissionJournalPanelScript := preload("res://base_workbench/ui/MissionJournalPanel.gd")
const SettlementEventPanelScript := preload("res://base_workbench/ui/SettlementEventPanel.gd")
const SettlementEventSystemScript := preload("res://base_workbench/systems/SettlementEventSystem.gd")
const DifficultyDebugPanelScript := preload("res://base_workbench/ui/DifficultyDebugPanel.gd")
const BuildingSlotScene := preload("res://base_workbench/ui/BuildingSlot.tscn")
const BuildingPanelScene := preload("res://base_workbench/ui/BuildingPanel.tscn")
const WorkerCandidatePickerPanelScript := preload("res://base_workbench/ui/WorkerCandidatePickerPanel.gd")
const BuildingPresentationScript := preload("res://base_workbench/ui/BuildingPresentation.gd")
const BuildingOccupancyBadgeScript := preload("res://base_workbench/ui/BuildingOccupancyBadge.gd")
const BuildingEffectSystemScript := preload("res://base_workbench/systems/BuildingEffectSystem.gd")
const BuildingSystemScript := preload("res://base_workbench/systems/BuildingSystem.gd")
const WorkerAssignmentSystemScript := preload("res://base_workbench/systems/WorkerAssignmentSystem.gd")
const ProductionSystemScript := preload("res://base_workbench/systems/ProductionSystem.gd")
const DivingEquipmentSystemScript := preload("res://scripts/diving/DivingEquipmentSystem.gd")
const ExpeditionPreparationSystemScript := preload("res://scripts/diving/ExpeditionPreparationSystem.gd")
const CampaignProgressionSystemScript := preload("res://scripts/campaign/CampaignProgressionSystem.gd")
const MissionSystemScript := preload("res://scripts/campaign/MissionSystem.gd")
const CareerProgressionSystemScript := preload("res://scripts/survivors/CareerProgressionSystem.gd")
const CompetencySystemScript := preload("res://scripts/survivors/CompetencySystem.gd")
const ProfessionTalentSystemScript := preload("res://scripts/survivors/ProfessionTalentSystem.gd")
const DiseaseSystemScript := preload("res://scripts/survivors/DiseaseSystem.gd")
const WorkPaceSystemScript := preload("res://base_workbench/systems/WorkPaceSystem.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const PolicyStateScript := preload("res://scripts/data/PolicyState.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")
const SurvivorPortraitScript := preload("res://scripts/ui/SurvivorPortrait.gd")
const SurvivorInfoPresenterScript := preload("res://scripts/ui/SurvivorInfoPresenter.gd")

const HUD_BASE := Color("092f37")
const HUD_RAISED := Color("10464e")
const HUD_RAISED_HOVER := Color("15545a")
const HUD_BORDER := Color("2c7277")
const HUD_TEXT := Color("f2f0e7")
const HUD_MUTED := Color("b6cac6")
const HUD_TEAL := Color("79c4c0")
const HUD_AMBER := Color("f2af36")
const HUD_AMBER_HOVER := Color("ffcb62")
const HUD_AMBER_DARK := Color("a66318")
const HUD_AMBER_PRESSED := Color("d68d20")
const HUD_GREEN := Color("9bc85c")
const HUD_CORAL := Color("ce6252")
const HUD_DARK_TEXT := Color("092f37")
const WORKSPACE_BASE := Color("efe7d7")
const WORKSPACE_SURFACE := Color("e4d9c5")
const WORKSPACE_SURFACE_RAISED := Color("f7f0e2")
const WORKSPACE_BORDER := Color("c7b38e")
const WORKSPACE_BORDER_SUBTLE := Color("d8c8ad")
const WORKSPACE_TEXT := Color("203b3b")
const WORKSPACE_MUTED := Color("607578")
const WORKSPACE_TEAL := Color("147b80")
const WORKSPACE_TEAL_HOVER := Color("3d9895")
const WORKSPACE_GREEN := Color("4f843c")
const WORKSPACE_CORAL := Color("a83e36")
const WORKSPACE_DISABLED := Color("89928d")
const WORKSPACE_DISABLED_SURFACE := Color("d9d2c4")
const CREW_AVAILABLE_COLOR := HUD_GREEN
const CREW_DEVELOPMENT_COLOR := HUD_AMBER
const NARRATIVE_MUSIC_DUCK_DB := 3.5
const NARRATIVE_MUSIC_DUCK_SECONDS := 0.18
const NarrativeContentScript := preload("res://scripts/ui/NarrativeContent.gd")

const SLOT_LAYOUT := {
	"top_left": {"definition_id": "fishing_hut", "rect": Rect2(0.22, 0.29, 0.20, 0.21), "hit_rect": Rect2(0.205, 0.25, 0.23, 0.28)},
	"top_center": {"definition_id": "kitchen", "rect": Rect2(0.405, 0.29, 0.20, 0.21), "hit_rect": Rect2(0.39, 0.25, 0.23, 0.28)},
	"top_right": {"definition_id": "community_house", "rect": Rect2(0.60, 0.29, 0.20, 0.21), "hit_rect": Rect2(0.585, 0.25, 0.23, 0.28)},
	"bottom_left": {"definition_id": "workshop", "rect": Rect2(0.205, 0.51, 0.22, 0.21), "hit_rect": Rect2(0.19, 0.47, 0.25, 0.28)},
	"center": {"definition_id": "infirmary", "rect": Rect2(0.40, 0.51, 0.21, 0.21), "hit_rect": Rect2(0.39, 0.47, 0.23, 0.28)},
	"bottom_right": {"definition_id": "diving_station", "rect": Rect2(0.60, 0.51, 0.20, 0.21), "hit_rect": Rect2(0.585, 0.47, 0.23, 0.28)},
}
const OCCUPANCY_BADGE_RECTS := {
	"top_left": Rect2(0.225, 0.202, 0.18, 0.102),
	"top_center": Rect2(0.410, 0.202, 0.18, 0.102),
	"top_right": Rect2(0.605, 0.202, 0.18, 0.102),
	"bottom_left": Rect2(0.215, 0.410, 0.18, 0.102),
	"center": Rect2(0.410, 0.410, 0.18, 0.102),
	"bottom_right": Rect2(0.605, 0.410, 0.18, 0.102),
}
const BUILDING_ART_PREFIXES := {
	"fishing_hut": "budynek_chata_rybacka",
	"kitchen": "budynek_kuchnia_i_wedzarnia",
	"community_house": "budynek_dom_wspolnoty_i_radiostacja",
	"workshop": "budynek_warsztat_odzysku",
	"infirmary": "budynek_lecznica_i_suszarnia",
	"diving_station": "budynek_stacja_nurkowa",
}
const BUILDING_MANAGEMENT_ORDER: Array[String] = [
	"top_left",
	"top_center",
	"top_right",
	"bottom_left",
	"center",
	"bottom_right",
]
const BUILDING_MANAGEMENT_SHORT_NAMES := {
	"fishing_hut": "CHATA",
	"kitchen": "KUCHNIA",
	"community_house": "DOM",
	"workshop": "WARSZTAT",
	"infirmary": "LECZNICA",
	"diving_station": "STACJA",
}
const BUILDING_WORKSPACE_SIDE_ANCHOR := 0.05
const BUILDING_WORKSPACE_TOP_OFFSET := 68.0
const BUILDING_WORKSPACE_BOTTOM_MARGIN := 82.0
const BUILDING_NAVIGATION_RAIL_WIDTH := 144.0
const BUILDING_RIGHT_SIDEBAR_WIDTH := 264.0
const BUILDING_WORKSPACE_SEPARATION := 12.0
const BUILDING_NAVIGATION_TILE_HEIGHT := 82.0
const BUILDING_MODAL_Z_INDEX := 50
const BUILDING_ACTIVE_HUD_Z_INDEX := 60
const BUILDING_FLYOUT_DISMISS_Z_INDEX := 61
const BUILDING_FLYOUT_Z_INDEX := 62
const BUILDING_ACTIVE_ACTION_Z_INDEX := 63
const BUILDING_ART_RECTS := {
	"fishing_hut": {
		1: Rect2(0.204, 0.241, 0.232, 0.29),
		2: Rect2(0.204, 0.241, 0.232, 0.29),
		3: Rect2(0.204, 0.241, 0.232, 0.29),
		4: Rect2(0.204, 0.241, 0.232, 0.29),
	},
	"kitchen": {
		1: Rect2(0.389, 0.241, 0.232, 0.29),
		2: Rect2(0.389, 0.241, 0.232, 0.29),
		3: Rect2(0.389, 0.241, 0.232, 0.29),
		4: Rect2(0.389, 0.241, 0.232, 0.29),
	},
	"community_house": {
		1: Rect2(0.576, 0.224, 0.248, 0.31),
		2: Rect2(0.576, 0.224, 0.248, 0.31),
		3: Rect2(0.576, 0.224, 0.248, 0.31),
		4: Rect2(0.576, 0.224, 0.248, 0.31),
	},
	"workshop": {
		1: Rect2(0.182, 0.43, 0.256, 0.32),
		2: Rect2(0.182, 0.43, 0.256, 0.32),
		3: Rect2(0.182, 0.43, 0.256, 0.32),
		4: Rect2(0.182, 0.43, 0.256, 0.32),
	},
	"infirmary": {
		1: Rect2(0.381, 0.439, 0.248, 0.31),
		2: Rect2(0.381, 0.439, 0.248, 0.31),
		3: Rect2(0.381, 0.439, 0.248, 0.31),
		4: Rect2(0.381, 0.439, 0.248, 0.31),
	},
	"diving_station": {
		1: Rect2(0.576, 0.439, 0.248, 0.31),
		2: Rect2(0.576, 0.439, 0.248, 0.31),
		3: Rect2(0.576, 0.439, 0.248, 0.31),
		4: Rect2(0.576, 0.439, 0.248, 0.31),
	},
}
const BUILDING_ART_Z := {
	"fishing_hut": 0,
	"kitchen": 0,
	"community_house": 0,
	"infirmary": 2,
	"workshop": 4,
	"diving_station": 4,
}

var game_root: Node
var game_state

var _building_system = BuildingSystemScript.new()
var _building_effect_system = BuildingEffectSystemScript.new()
var _worker_assignment_system = WorkerAssignmentSystemScript.new()
var _production_system = ProductionSystemScript.new()
var _work_pace_system = WorkPaceSystemScript.new()
var _diving_equipment_system = DivingEquipmentSystemScript.new()
var _expedition_preparation_system = ExpeditionPreparationSystemScript.new()
var _campaign_system = CampaignProgressionSystemScript.new()
var _mission_system = MissionSystemScript.new()
var _settlement_event_system = SettlementEventSystemScript.new()
var _career_progression_system = CareerProgressionSystemScript.new()
var _profession_talent_system = ProfessionTalentSystemScript.new()
var _disease_system = DiseaseSystemScript.new()
var _environment: Control
var _board: Control
var _building_layer: Control
var _building_info_layer: Control
var _slot_layer: Control
var _hud_canvas: CanvasLayer
var _hud_root: Control
var _slots: Dictionary = {}
var _building_presentations: Dictionary = {}
var _occupancy_badges: Dictionary = {}
var _day_label: Label
var _resource_label: RichTextLabel
var _top_status_row: HBoxContainer
var _resource_bar: PanelContainer
var _day_plan_button: Button
var _day_plan_popover: PanelContainer
var _hud_flyout_dismiss_layer: Control
var _ration_hint: Label
var _ration_picker: OptionButton
var _crew_button: Button
var _survivors_panel: PanelContainer
var _survivor_list: VBoxContainer
var _epidemic_status_label: Label
var _tutorial_panel: PanelContainer
var _tutorial_title: Label
var _tutorial_body: Label
var _campaign_panel: PanelContainer
var _campaign_scroll: ScrollContainer
var _campaign_act_label: Label
var _campaign_objective_label: Label
var _campaign_artifacts_label: Label
var _campaign_progress: ProgressBar
var _campaign_details_button: Button
var _campaign_details_expanded: bool = false
var _journal_button: Button
var _report_journal_button: Button
var _end_day_button: Button
var _day_summary_panel: DaySummaryPanel
var _mission_journal_panel: MissionJournalPanel
var _day_report_journal_panel: DayReportJournalPanel
var _settlement_event_panel
var _difficulty_debug_panel
var _modal_layer: ColorRect
var _modal_center: CenterContainer
var _building_workspace: HBoxContainer
var _building_navigation_rail: PanelContainer
var _building_navigation_list: VBoxContainer
var _building_navigation_buttons: Dictionary = {}
var _building_panel
var _building_right_sidebar: VBoxContainer
var _worker_candidate_panel
var _worker_picker_slot_index: int = -1
var _survivor_development_panel: PanelContainer
var _selected_survivor_id: String = ""
var _tooltip: PanelContainer
var _tooltip_label: Label
var _hovered_slot_id: String = ""
var _slot_highlight_modes: Dictionary = {}
var _selected_slot_id: String = ""
var _action_feedback: PanelContainer
var _action_feedback_label: Label
var _action_feedback_tween: Tween
var _modal_tween: Tween
var _animation_time_override: float = -1.0
var _reduced_motion: bool = false
var _graphics_quality: String = "high"
var _focus_building_on_next_refresh: bool = false
var _narrative_music_duck_tween: Tween
var _base_music_nominal_volume_db: float = 0.0
var _base_music_volume_captured: bool = false


func seed_user_settings_before_ready(quality_id: String, reduced_motion: bool) -> void:
	# This narrow lifecycle hook is called before SceneTree entry. Do not touch
	# nodes or tweens here; only seed values consumed by _build_ui().
	_graphics_quality = quality_id if quality_id in ["low", "medium", "high"] else "high"
	_reduced_motion = reduced_motion


func bind(root: Node, state) -> void:
	game_root = root
	game_state = state
	_render()


func supports_pause_menu() -> bool:
	return true


func has_cancelable_overlay_open() -> bool:
	return (
		(_mission_journal_panel != null and _mission_journal_panel.is_open())
		or (_day_report_journal_panel != null and _day_report_journal_panel.is_open())
		or (_modal_layer != null and _modal_layer.visible)
		or (_day_plan_popover != null and _day_plan_popover.visible)
		or (_survivors_panel != null and _survivors_panel.visible)
	)

func set_animation_time_for_tests(seconds: float) -> void:
	_animation_time_override = maxf(seconds, 0.0)
	if _environment != null:
		_environment.set_animation_time_for_tests(_animation_time_override)
	for slot in _slots.values():
		if slot != null and slot.has_method("set_animation_time_for_tests"):
			slot.set_animation_time_for_tests(_animation_time_override)
	for presentation in _building_presentations.values():
		if presentation != null and presentation.has_method("set_animation_time_for_tests"):
			presentation.set_animation_time_for_tests(_animation_time_override)
	if _modal_tween != null and _modal_tween.is_valid():
		_modal_tween.kill()
		_modal_tween = null
	if _action_feedback_tween != null and _action_feedback_tween.is_valid():
		_action_feedback_tween.kill()
		_action_feedback_tween = null
	if _modal_layer != null and _modal_layer.visible:
		_modal_layer.modulate = Color.WHITE
	if _action_feedback != null and _action_feedback.visible:
		_action_feedback.modulate = Color.WHITE
		_action_feedback.scale = Vector2.ONE

func clear_animation_time_override() -> void:
	_animation_time_override = -1.0
	if _environment != null:
		_environment.clear_animation_time_override()
	for slot in _slots.values():
		if slot != null and slot.has_method("clear_animation_time_override"):
			slot.clear_animation_time_override()
	for presentation in _building_presentations.values():
		if presentation != null and presentation.has_method("clear_animation_time_override"):
			presentation.clear_animation_time_override()

func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if _environment != null and _environment.has_method("set_reduced_motion"):
		_environment.set_reduced_motion(enabled)
	if _modal_tween != null and _modal_tween.is_valid():
		_modal_tween.kill()
	if _modal_layer != null and _modal_layer.visible:
		_modal_layer.modulate = Color.WHITE
	if _action_feedback_tween != null and _action_feedback_tween.is_valid():
		_action_feedback_tween.kill()
	if _action_feedback != null and _action_feedback.visible:
		_action_feedback.modulate = Color.WHITE
		_action_feedback.scale = Vector2.ONE
		_action_feedback_tween = create_tween()
		_action_feedback_tween.tween_interval(2.2)
		_action_feedback_tween.tween_callback(_hide_action_feedback)
	for slot in _slots.values():
		if slot != null and slot.has_method("set_reduced_motion"):
			slot.set_reduced_motion(enabled)
	for presentation in _building_presentations.values():
		if presentation != null and presentation.has_method("set_reduced_motion"):
			presentation.set_reduced_motion(enabled)


func set_graphics_quality(quality_id: String) -> void:
	_graphics_quality = quality_id if quality_id in ["low", "medium", "high"] else "high"
	if _environment != null and _environment.has_method("set_graphics_quality"):
		_environment.set_graphics_quality(_graphics_quality)


func set_narrative_audio_duck(active: bool) -> void:
	var music_player := get_node_or_null("BaseMusicPlayer") as AudioStreamPlayer
	if music_player == null:
		return
	if not _base_music_volume_captured:
		_base_music_nominal_volume_db = music_player.volume_db
		_base_music_volume_captured = true
	if _narrative_music_duck_tween != null and _narrative_music_duck_tween.is_valid():
		_narrative_music_duck_tween.kill()
	var target_volume := _base_music_nominal_volume_db - NARRATIVE_MUSIC_DUCK_DB if active else _base_music_nominal_volume_db
	if is_equal_approx(music_player.volume_db, target_volume):
		music_player.volume_db = target_volume
		return
	_narrative_music_duck_tween = create_tween()
	_narrative_music_duck_tween.set_trans(Tween.TRANS_SINE)
	_narrative_music_duck_tween.set_ease(Tween.EASE_IN_OUT)
	_narrative_music_duck_tween.tween_property(music_player, "volume_db", target_volume, NARRATIVE_MUSIC_DUCK_SECONDS)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout_board)
	_build_ui()
	_layout_board()
	_render()


func _exit_tree() -> void:
	if _narrative_music_duck_tween != null and _narrative_music_duck_tween.is_valid():
		_narrative_music_duck_tween.kill()
	var music_player := get_node_or_null("BaseMusicPlayer") as AudioStreamPlayer
	if music_player != null:
		music_player.stop()
		music_player.stream = null


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		if _day_plan_popover != null and _day_plan_popover.visible:
			_close_day_plan_popover(true)
			get_viewport().set_input_as_handled()
			return
		if _survivors_panel != null and _survivors_panel.visible:
			_close_crew_flyout(true)
			get_viewport().set_input_as_handled()
			return
		if _modal_layer != null and _modal_layer.visible and _worker_candidate_panel != null and _worker_candidate_panel.visible:
			_close_worker_candidate_picker(true)
			get_viewport().set_input_as_handled()
			return
		if _modal_layer != null and _modal_layer.visible and _survivor_development_panel != null and _survivor_development_panel.visible:
			_close_building_panel()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"open_mission_journal"):
		_on_journal_pressed()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"open_day_reports"):
		_on_report_journal_pressed()
		get_viewport().set_input_as_handled()
		return
	if not OS.is_debug_build() or game_state == null:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		_difficulty_debug_panel.toggle(game_state)
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	_maintain_hud_flyout_focus()
	if _tooltip == null or not _tooltip.visible:
		return
	var desired := get_viewport().get_mouse_position() + Vector2(18, 18)
	var maximum := size - _tooltip.size - Vector2(12, 12)
	_tooltip.position = Vector2(clamp(desired.x, 12.0, max(maximum.x, 12.0)), clamp(desired.y, 12.0, max(maximum.y, 12.0)))

func _build_ui() -> void:
	_environment = BaseEnvironmentScript.new()
	# GameRoot seeds these values before the scene enters the tree. Forward them
	# before build so low/medium never create high-quality GPU resources first.
	_environment.set_graphics_quality(_graphics_quality)
	_environment.set_reduced_motion(_reduced_motion)
	_environment.build()
	add_child(_environment)
	_board = _environment.platform_board
	_building_layer = _environment.building_layer
	_building_info_layer = _environment.building_info_layer
	_slot_layer = _environment.slot_layer
	_build_slots()

	_hud_canvas = CanvasLayer.new()
	_hud_canvas.name = "BaseHUDCanvasLayer"
	_hud_canvas.layer = 40
	add_child(_hud_canvas)
	_hud_root = Control.new()
	_hud_root.name = "BaseHUD"
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_canvas.add_child(_hud_root)

	_build_hud_flyout_dismiss_layer()
	_build_hud()
	_build_survivor_panel()
	_build_tutorial_panel()
	_build_campaign_panel()
	_build_end_day_button()
	_build_tooltip()
	_build_action_feedback()
	_build_modal()
	_build_mission_journal()
	_build_day_report_journal()
	_build_day_summary()
	_build_settlement_event()
	_build_difficulty_debug_panel()


func _build_hud_flyout_dismiss_layer() -> void:
	_hud_flyout_dismiss_layer = Control.new()
	_hud_flyout_dismiss_layer.name = "HudFlyoutDismissLayer"
	_hud_flyout_dismiss_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_flyout_dismiss_layer.visible = false
	_hud_flyout_dismiss_layer.z_index = BUILDING_FLYOUT_DISMISS_Z_INDEX
	_hud_flyout_dismiss_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud_flyout_dismiss_layer.gui_input.connect(_on_hud_flyout_dismiss_gui_input)
	_hud_root.add_child(_hud_flyout_dismiss_layer)

func _build_slots() -> void:
	for slot_id in SLOT_LAYOUT.keys():
		var slot_data: Dictionary = SLOT_LAYOUT[slot_id]
		var definition_id: String = str(slot_data["definition_id"])
		var presentation = BuildingPresentationScript.new()
		presentation.name = "Presentation_%s" % slot_id
		presentation.z_index = _building_art_z(definition_id) + 1
		_apply_normalized_rect(presentation, BUILDING_ART_RECTS[definition_id][1])
		_building_layer.add_child(presentation)
		_building_presentations[slot_id] = presentation
		presentation.set_reduced_motion(_reduced_motion)
		if _animation_time_override >= 0.0:
			presentation.set_animation_time_for_tests(_animation_time_override)

		var occupancy_badge = BuildingOccupancyBadgeScript.new()
		occupancy_badge.name = "BuildingOccupancyBadge_%s" % slot_id
		_apply_normalized_rect(occupancy_badge, OCCUPANCY_BADGE_RECTS[slot_id])
		_building_info_layer.add_child(occupancy_badge)
		occupancy_badge.configure(str(slot_id), "", 0, [], false)
		_occupancy_badges[slot_id] = occupancy_badge

		var slot = BuildingSlotScene.instantiate()
		slot.name = "Slot_%s" % slot_id
		var hit_rect: Rect2 = slot_data["hit_rect"]
		_apply_normalized_rect(slot, hit_rect)
		_slot_layer.add_child(slot)
		slot.configure(slot_id, definition_id, _relative_rect(slot_data["rect"], hit_rect))
		slot.set_reduced_motion(_reduced_motion)
		if _animation_time_override >= 0.0:
			slot.set_animation_time_for_tests(_animation_time_override)
		slot.slot_selected.connect(_on_slot_selected)
		slot.slot_hover_changed.connect(_on_slot_hover_changed)
		slot.slot_highlight_changed.connect(_on_slot_highlight_changed)
		_slots[slot_id] = slot
		_slot_highlight_modes[slot_id] = slot.highlight_mode()

func _build_hud() -> void:
	_resource_bar = PanelContainer.new()
	_resource_bar.name = "ResourceBar"
	_resource_bar.anchor_right = 1.0
	_resource_bar.offset_left = 14
	_resource_bar.offset_top = 10
	_resource_bar.offset_right = -14
	_resource_bar.offset_bottom = 52
	_resource_bar.z_index = BUILDING_ACTIVE_HUD_Z_INDEX
	_resource_bar.add_theme_stylebox_override("panel", _panel_style(Color(HUD_BASE, 0.93), HUD_BORDER, 1))
	_hud_root.add_child(_resource_bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 3)
	_resource_bar.add_child(margin)

	_top_status_row = HBoxContainer.new()
	_top_status_row.name = "TopStatusRow"
	_top_status_row.add_theme_constant_override("separation", 7)
	margin.add_child(_top_status_row)

	_day_label = Label.new()
	_day_label.custom_minimum_size = Vector2(78, 0)
	_day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_day_label.add_theme_font_size_override("font_size", 16)
	_day_label.add_theme_color_override("font_color", HUD_AMBER)
	_top_status_row.add_child(_day_label)

	var divider := VSeparator.new()
	divider.add_theme_color_override("separator", HUD_BORDER)
	_top_status_row.add_child(divider)

	_resource_label = RichTextLabel.new()
	_resource_label.name = "ResourceSummary"
	_resource_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resource_label.custom_minimum_size = Vector2(0, 31)
	_resource_label.bbcode_enabled = true
	_resource_label.fit_content = false
	_resource_label.scroll_active = false
	_resource_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_resource_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_resource_label.add_theme_font_size_override("normal_font_size", 12)
	_resource_label.add_theme_color_override("default_color", HUD_TEXT)
	_top_status_row.add_child(_resource_label)

	_day_plan_button = Button.new()
	_day_plan_button.name = "DayPlanButton"
	_day_plan_button.custom_minimum_size = Vector2(190, 30)
	_day_plan_button.z_index = BUILDING_ACTIVE_ACTION_Z_INDEX - BUILDING_ACTIVE_HUD_Z_INDEX
	_day_plan_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_day_plan_button.tooltip_text = "Sprawdź lub zmień racje na bieżący dzień. Tempo ustawiasz osobno w panelu każdego budynku."
	_day_plan_button.add_theme_font_size_override("font_size", 11)
	_day_plan_button.add_theme_stylebox_override("normal", _hud_button_style(Color(HUD_RAISED, 0.94), HUD_BORDER, 1))
	_day_plan_button.add_theme_stylebox_override("hover", _hud_button_style(Color(HUD_RAISED_HOVER, 0.96), HUD_TEAL, 1))
	_day_plan_button.add_theme_stylebox_override("pressed", _hud_button_style(HUD_BASE, HUD_AMBER, 2))
	_day_plan_button.add_theme_stylebox_override("focus", _hud_button_style(Color("00000000"), HUD_TEAL, 2))
	_day_plan_button.pressed.connect(_on_day_plan_button_pressed)
	_top_status_row.add_child(_day_plan_button)

	_build_day_plan_popover()

func _build_day_plan_popover() -> void:
	_day_plan_popover = PanelContainer.new()
	_day_plan_popover.name = "DayPlanPopover"
	_day_plan_popover.anchor_left = 1.0
	_day_plan_popover.anchor_right = 1.0
	_day_plan_popover.offset_left = -316
	_day_plan_popover.offset_top = 58
	_day_plan_popover.offset_right = -14
	_day_plan_popover.offset_bottom = 276
	_day_plan_popover.visible = false
	_day_plan_popover.z_index = BUILDING_FLYOUT_Z_INDEX
	_day_plan_popover.mouse_filter = Control.MOUSE_FILTER_STOP
	_day_plan_popover.add_theme_stylebox_override("panel", _panel_style(Color(HUD_BASE, 0.98), HUD_AMBER, 2))
	_hud_root.add_child(_day_plan_popover)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 13)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 11)
	_day_plan_popover.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.text = "PLAN DNIA"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", HUD_AMBER)
	header.add_child(title)
	var close := Button.new()
	close.name = "CloseDayPlanButton"
	close.text = "×"
	close.tooltip_text = "Zamknij  [Esc]"
	close.custom_minimum_size = Vector2(30, 28)
	close.pressed.connect(func(): _close_day_plan_popover(true))
	header.add_child(close)

	var ration_label := Label.new()
	ration_label.text = "RACJE ŻYWNOŚCIOWE"
	ration_label.add_theme_font_size_override("font_size", 11)
	ration_label.add_theme_color_override("font_color", HUD_MUTED)
	content.add_child(ration_label)

	_ration_picker = OptionButton.new()
	_ration_picker.name = "RationPolicyPicker"
	_ration_picker.custom_minimum_size = Vector2(0, 34)
	_ration_picker.add_item("Wybierz politykę racji…")
	_ration_picker.set_item_metadata(0, -1)
	_ration_picker.set_item_disabled(0, true)
	_ration_picker.add_item("Pełne racje")
	_ration_picker.set_item_metadata(1, PolicyStateScript.RationPolicy.FULL)
	_ration_picker.add_item("Połowa racji")
	_ration_picker.set_item_metadata(2, PolicyStateScript.RationPolicy.HALF)
	_ration_picker.add_item("Bez racji")
	_ration_picker.set_item_metadata(3, PolicyStateScript.RationPolicy.NONE)
	_ration_picker.add_item("Pierwszeństwo nurka")
	_ration_picker.set_item_metadata(4, PolicyStateScript.RationPolicy.DIVER_PRIORITY)
	_ration_picker.item_selected.connect(_on_ration_policy_selected)
	content.add_child(_ration_picker)
	_ration_hint = Label.new()
	_ration_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ration_hint.add_theme_font_size_override("font_size", 11)
	_ration_hint.add_theme_color_override("font_color", HUD_TEXT)
	content.add_child(_ration_hint)

func _build_survivor_panel() -> void:
	_crew_button = Button.new()
	_crew_button.name = "CrewButton"
	_crew_button.custom_minimum_size = Vector2(148, 30)
	_crew_button.z_index = BUILDING_ACTIVE_ACTION_Z_INDEX - BUILDING_ACTIVE_HUD_Z_INDEX
	_crew_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_crew_button.add_theme_font_size_override("font_size", 11)
	_crew_button.add_theme_stylebox_override("pressed", _hud_button_style(HUD_BASE, HUD_AMBER, 2))
	_crew_button.add_theme_stylebox_override("focus", _hud_button_style(Color("00000000"), HUD_TEAL, 2))
	_crew_button.pressed.connect(_on_crew_button_pressed)
	_top_status_row.add_child(_crew_button)
	_top_status_row.move_child(_crew_button, _day_plan_button.get_index())

	_survivors_panel = PanelContainer.new()
	_survivors_panel.name = "SurvivorsPanel"
	_survivors_panel.offset_left = 14
	_survivors_panel.offset_top = 58
	_survivors_panel.offset_right = 370
	_survivors_panel.offset_bottom = 386
	_survivors_panel.visible = false
	_survivors_panel.z_index = BUILDING_FLYOUT_Z_INDEX
	_survivors_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_survivors_panel.add_theme_stylebox_override("panel", _panel_style(Color(HUD_BASE, 0.98), HUD_BORDER, 1))
	_hud_root.add_child(_survivors_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 11)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_survivors_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)

	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.text = "ZAŁOGA"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", HUD_AMBER)
	header.add_child(title)
	var close := Button.new()
	close.name = "CloseCrewButton"
	close.text = "×"
	close.tooltip_text = "Zamknij  [Esc]"
	close.custom_minimum_size = Vector2(34, 32)
	close.pressed.connect(func(): _close_crew_flyout(true))
	header.add_child(close)

	_epidemic_status_label = Label.new()
	_epidemic_status_label.name = "EpidemicStatusLabel"
	_epidemic_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_epidemic_status_label.add_theme_font_size_override("font_size", 12)
	content.add_child(_epidemic_status_label)

	var survivor_scroll := ScrollContainer.new()
	survivor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	survivor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(survivor_scroll)
	_survivor_list = VBoxContainer.new()
	_survivor_list.name = "SurvivorList"
	_survivor_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_survivor_list.add_theme_constant_override("separation", 7)
	survivor_scroll.add_child(_survivor_list)

func _build_tutorial_panel() -> void:
	_tutorial_panel = PanelContainer.new()
	_tutorial_panel.name = "TutorialPanel"
	_tutorial_panel.offset_left = 14
	_tutorial_panel.offset_top = 60
	_tutorial_panel.offset_right = 370
	_tutorial_panel.offset_bottom = 156
	_tutorial_panel.z_index = 65
	_tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_panel.add_theme_stylebox_override("panel", _panel_style(Color(HUD_BASE, 0.97), HUD_AMBER, 2))
	_hud_root.add_child(_tutorial_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	_tutorial_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 3)
	margin.add_child(content)

	_tutorial_title = Label.new()
	_tutorial_title.name = "TutorialTitle"
	_tutorial_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_title.add_theme_font_size_override("font_size", 13)
	_tutorial_title.add_theme_color_override("font_color", HUD_AMBER_HOVER)
	content.add_child(_tutorial_title)

	_tutorial_body = Label.new()
	_tutorial_body.name = "TutorialBody"
	_tutorial_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_body.add_theme_font_size_override("font_size", 12)
	_tutorial_body.add_theme_color_override("font_color", HUD_TEXT)
	content.add_child(_tutorial_body)

func _build_campaign_panel() -> void:
	_campaign_panel = PanelContainer.new()
	_campaign_panel.name = "CampaignPanel"
	_campaign_panel.anchor_top = 1.0
	_campaign_panel.anchor_bottom = 1.0
	_campaign_panel.offset_left = 14
	_campaign_panel.offset_top = -174
	_campaign_panel.offset_right = 404
	_campaign_panel.offset_bottom = -16
	_campaign_panel.add_theme_stylebox_override("panel", _panel_style(Color(HUD_BASE, 0.95), HUD_BORDER, 1))
	_hud_root.add_child(_campaign_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 11)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_campaign_panel.add_child(margin)
	var panel_content := VBoxContainer.new()
	panel_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_content.add_theme_constant_override("separation", 5)
	margin.add_child(panel_content)
	_campaign_scroll = ScrollContainer.new()
	_campaign_scroll.name = "CampaignTrackerScroll"
	_campaign_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_campaign_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_campaign_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_campaign_scroll.follow_focus = true
	panel_content.add_child(_campaign_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 5)
	_campaign_scroll.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	content.add_child(header)
	_campaign_act_label = Label.new()
	_campaign_act_label.name = "CampaignActLabel"
	_campaign_act_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_campaign_act_label.add_theme_color_override("font_color", HUD_AMBER)
	_campaign_act_label.add_theme_font_size_override("font_size", 11)
	header.add_child(_campaign_act_label)
	_campaign_details_button = Button.new()
	_campaign_details_button.name = "CampaignTrackerExpandButton"
	_campaign_details_button.text = "WIĘCEJ"
	_campaign_details_button.custom_minimum_size = Vector2(70, 25)
	_campaign_details_button.add_theme_font_size_override("font_size", 10)
	_campaign_details_button.add_theme_stylebox_override("normal", _hud_button_style(Color(HUD_RAISED, 0.90), HUD_BORDER, 1))
	_campaign_details_button.add_theme_stylebox_override("hover", _hud_button_style(Color(HUD_RAISED_HOVER, 0.95), HUD_TEAL, 1))
	_campaign_details_button.add_theme_stylebox_override("focus", _hud_button_style(Color("00000000"), HUD_TEAL, 2))
	_campaign_details_button.tooltip_text = "Rozwiń listę celów śledzonego zadania."
	_campaign_details_button.pressed.connect(_on_campaign_details_pressed)
	header.add_child(_campaign_details_button)
	_campaign_objective_label = Label.new()
	_campaign_objective_label.name = "CampaignObjectiveLabel"
	_campaign_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_campaign_objective_label.add_theme_font_size_override("font_size", 12)
	_campaign_objective_label.add_theme_color_override("font_color", HUD_TEXT)
	content.add_child(_campaign_objective_label)
	_campaign_artifacts_label = Label.new()
	_campaign_artifacts_label.name = "CampaignArtifactsLabel"
	_campaign_artifacts_label.visible = false
	_campaign_artifacts_label.add_theme_font_size_override("font_size", 11)
	_campaign_artifacts_label.add_theme_color_override("font_color", HUD_TEAL)
	_campaign_artifacts_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_campaign_artifacts_label)
	_campaign_progress = ProgressBar.new()
	_campaign_progress.name = "ProjectDawnProgress"
	_campaign_progress.show_percentage = false
	_campaign_progress.custom_minimum_size = Vector2(0, 7)
	content.add_child(_campaign_progress)
	var journal_actions := HBoxContainer.new()
	journal_actions.add_theme_constant_override("separation", 7)
	panel_content.add_child(journal_actions)
	_journal_button = Button.new()
	_journal_button.name = "OpenMissionJournalButton"
	_journal_button.text = "DZIENNIK  [%s]" % InputPromptScript.action_text(&"open_mission_journal")
	_journal_button.custom_minimum_size = Vector2(0, 28)
	_journal_button.add_theme_font_size_override("font_size", 10)
	_journal_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_journal_button.pressed.connect(_on_journal_pressed)
	journal_actions.add_child(_journal_button)
	_report_journal_button = Button.new()
	_report_journal_button.name = "DayReportJournalButton"
	_report_journal_button.text = "RAPORTY  [%s]" % InputPromptScript.action_text(&"open_day_reports")
	_report_journal_button.custom_minimum_size = Vector2(0, 28)
	_report_journal_button.add_theme_font_size_override("font_size", 10)
	_report_journal_button.add_theme_color_override("font_disabled_color", Color("788784"))
	_report_journal_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report_journal_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_report_journal_button.pressed.connect(_on_report_journal_pressed)
	journal_actions.add_child(_report_journal_button)

func _build_end_day_button() -> void:
	_end_day_button = Button.new()
	_end_day_button.name = "EndDayButton"
	_end_day_button.text = "ZAKOŃCZ DZIEŃ  ›"
	_end_day_button.anchor_left = 1.0
	_end_day_button.anchor_top = 1.0
	_end_day_button.anchor_right = 1.0
	_end_day_button.anchor_bottom = 1.0
	_end_day_button.offset_left = -218
	_end_day_button.offset_top = -58
	_end_day_button.offset_right = -14
	_end_day_button.offset_bottom = -16
	_end_day_button.z_index = BUILDING_ACTIVE_ACTION_Z_INDEX
	_end_day_button.add_theme_font_size_override("font_size", 12)
	_end_day_button.add_theme_color_override("font_color", HUD_DARK_TEXT)
	_end_day_button.add_theme_color_override("font_hover_color", HUD_DARK_TEXT)
	_end_day_button.add_theme_color_override("font_pressed_color", HUD_DARK_TEXT)
	_end_day_button.add_theme_color_override("font_focus_color", HUD_DARK_TEXT)
	_end_day_button.add_theme_color_override("font_disabled_color", HUD_MUTED)
	_end_day_button.add_theme_stylebox_override("pressed", _hud_button_style(HUD_AMBER_PRESSED, HUD_AMBER_DARK, 2))
	_end_day_button.add_theme_stylebox_override("focus", _hud_button_style(Color("00000000"), HUD_TEAL, 2))
	_end_day_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_end_day_button.pressed.connect(_on_end_day_pressed)
	_hud_root.add_child(_end_day_button)

func _build_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.name = "BuildingTooltip"
	_tooltip.visible = false
	_tooltip.z_index = 40
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_theme_stylebox_override("panel", _panel_style(Color(HUD_BASE, 0.95), HUD_BORDER))
	_hud_root.add_child(_tooltip)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	_tooltip.add_child(margin)
	_tooltip_label = Label.new()
	_tooltip_label.add_theme_color_override("font_color", HUD_TEXT)
	margin.add_child(_tooltip_label)

func _build_action_feedback() -> void:
	_action_feedback = PanelContainer.new()
	_action_feedback.name = "BaseActionFeedback"
	_action_feedback.anchor_left = 0.5
	_action_feedback.anchor_top = 1.0
	_action_feedback.anchor_right = 0.5
	_action_feedback.anchor_bottom = 1.0
	_action_feedback.offset_left = -230.0
	_action_feedback.offset_top = -148.0
	_action_feedback.offset_right = 230.0
	_action_feedback.offset_bottom = -88.0
	_action_feedback.visible = false
	_action_feedback.z_index = 70
	_action_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_action_feedback)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 5)
	_action_feedback.add_child(margin)
	_action_feedback_label = Label.new()
	_action_feedback_label.name = "BaseActionFeedbackLabel"
	_action_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action_feedback_label.add_theme_font_size_override("font_size", 14)
	margin.add_child(_action_feedback_label)

func _build_modal() -> void:
	_modal_layer = ColorRect.new()
	_modal_layer.name = "BuildingModal"
	_modal_layer.color = Color.TRANSPARENT
	_modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_layer.visible = false
	_modal_layer.z_index = BUILDING_MODAL_Z_INDEX
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_layer.gui_input.connect(_on_modal_background_gui_input)
	_hud_root.add_child(_modal_layer)

	_building_workspace = HBoxContainer.new()
	_building_workspace.name = "BuildingManagementWorkspace"
	_building_workspace.set_anchors_preset(Control.PRESET_FULL_RECT)
	_building_workspace.anchor_left = BUILDING_WORKSPACE_SIDE_ANCHOR
	_building_workspace.anchor_right = 1.0 - BUILDING_WORKSPACE_SIDE_ANCHOR
	_building_workspace.offset_left = 0.0
	_building_workspace.offset_top = BUILDING_WORKSPACE_TOP_OFFSET
	_building_workspace.offset_right = 0.0
	_building_workspace.offset_bottom = -BUILDING_WORKSPACE_BOTTOM_MARGIN
	_building_workspace.add_theme_constant_override("separation", int(BUILDING_WORKSPACE_SEPARATION))
	_building_workspace.mouse_filter = Control.MOUSE_FILTER_STOP
	_building_workspace.gui_input.connect(_on_modal_background_gui_input)
	_modal_layer.add_child(_building_workspace)

	_building_navigation_rail = PanelContainer.new()
	_building_navigation_rail.name = "BuildingNavigationRail"
	_building_navigation_rail.custom_minimum_size = Vector2(BUILDING_NAVIGATION_RAIL_WIDTH, 0)
	_building_navigation_rail.add_theme_stylebox_override("panel", _building_navigation_rail_style())
	_building_workspace.add_child(_building_navigation_rail)
	var rail_margin := MarginContainer.new()
	rail_margin.add_theme_constant_override("margin_left", 8)
	rail_margin.add_theme_constant_override("margin_top", 10)
	rail_margin.add_theme_constant_override("margin_right", 8)
	rail_margin.add_theme_constant_override("margin_bottom", 10)
	_building_navigation_rail.add_child(rail_margin)
	_building_navigation_list = VBoxContainer.new()
	_building_navigation_list.name = "BuildingNavigationList"
	_building_navigation_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_building_navigation_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_building_navigation_list.add_theme_constant_override("separation", 6)
	var rail_scroll := ScrollContainer.new()
	rail_scroll.name = "BuildingNavigationScroll"
	rail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rail_margin.add_child(rail_scroll)
	rail_scroll.add_child(_building_navigation_list)

	_building_panel = BuildingPanelScene.instantiate()
	_building_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_building_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_building_workspace.add_child(_building_panel)
	_building_right_sidebar = VBoxContainer.new()
	_building_right_sidebar.name = "BuildingRightSidebar"
	_building_right_sidebar.custom_minimum_size = Vector2(BUILDING_RIGHT_SIDEBAR_WIDTH, 0)
	_building_right_sidebar.size_flags_horizontal = Control.SIZE_SHRINK_END
	_building_right_sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_building_right_sidebar.mouse_filter = Control.MOUSE_FILTER_STOP
	_building_workspace.add_child(_building_right_sidebar)
	_building_panel.set_focus_scope(_building_workspace)
	_building_panel.set_right_sidebar_host(_building_right_sidebar)
	var management_external_focus_scopes: Array[Control] = [
		_day_plan_button,
		_crew_button,
		_day_plan_popover,
		_survivors_panel,
		_end_day_button,
	]
	_building_panel.set_external_focus_scopes(management_external_focus_scopes)
	_building_panel.closed.connect(_close_building_panel)
	_building_panel.build_requested.connect(_on_build_requested)
	_building_panel.upgrade_requested.connect(_on_upgrade_requested)
	_building_panel.worker_picker_requested.connect(_on_worker_picker_requested)
	_building_panel.dive_requested.connect(_on_dive_requested)
	_building_panel.diver_selected.connect(_on_diver_selected)
	_building_panel.production_requested.connect(_on_production_requested)
	_building_panel.gear_equipped.connect(_on_gear_equipped)
	_building_panel.entry_point_selected.connect(_on_entry_point_selected)
	_building_panel.survivor_development_requested.connect(_on_survivor_development_requested)
	_building_panel.career_promotion_requested.connect(_on_career_promotion_requested)
	_building_panel.profession_talent_requested.connect(_on_profession_talent_requested)
	_building_panel.work_pace_selected.connect(_on_building_work_pace_selected)
	_building_panel.medical_priority_changed.connect(_on_medical_priority_changed)
	_build_building_navigation_rail()

	_modal_center = CenterContainer.new()
	_modal_center.name = "ModalCenter"
	_modal_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_center.offset_left = 24
	_modal_center.offset_top = 72
	_modal_center.offset_right = -24
	_modal_center.offset_bottom = -24
	_modal_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_layer.add_child(_modal_center)

	_worker_candidate_panel = WorkerCandidatePickerPanelScript.new()
	_worker_candidate_panel.name = "WorkerCandidatePickerPanel"
	_worker_candidate_panel.visible = false
	_worker_candidate_panel.closed.connect(_close_worker_candidate_picker)
	_worker_candidate_panel.survivor_chosen.connect(_on_worker_candidate_chosen)
	_modal_center.add_child(_worker_candidate_panel)

	_survivor_development_panel = PanelContainer.new()
	_survivor_development_panel.name = "SurvivorDevelopmentPanel"
	_survivor_development_panel.custom_minimum_size = Vector2(650, 540)
	_survivor_development_panel.add_theme_stylebox_override("panel", _panel_style(WORKSPACE_BASE, WORKSPACE_TEAL, 2))
	_survivor_development_panel.visible = false
	_modal_center.add_child(_survivor_development_panel)
	_raise_management_hud_above_modal()


func _raise_management_hud_above_modal() -> void:
	# Godot resolves overlapping Control input using sibling order as well as
	# canvas Z. Keep the world blocker late enough to cover the remaining base
	# HUD, then place only the explicitly active management controls above it.
	for control in [
		_hud_flyout_dismiss_layer,
		_resource_bar,
		_day_plan_popover,
		_survivors_panel,
		_end_day_button,
		_tutorial_panel,
	]:
		if control != null:
			_hud_root.move_child(control, _hud_root.get_child_count() - 1)


func _build_building_navigation_rail() -> void:
	_building_navigation_buttons.clear()
	if _building_navigation_list == null:
		return
	for child in _building_navigation_list.get_children():
		_building_navigation_list.remove_child(child)
		child.queue_free()
	for slot_id in BUILDING_MANAGEMENT_ORDER:
		var slot_layout: Dictionary = SLOT_LAYOUT.get(slot_id, {})
		var definition_id := str(slot_layout.get("definition_id", ""))
		if definition_id.is_empty():
			continue
		var button := Button.new()
		button.name = "BuildingNav_%s" % slot_id
		button.custom_minimum_size = Vector2(128, BUILDING_NAVIGATION_TILE_HEIGHT)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_on_building_navigation_selected.bind(slot_id))
		_building_navigation_list.add_child(button)
		var tile_margin := MarginContainer.new()
		tile_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tile_margin.add_theme_constant_override("margin_left", 5)
		tile_margin.add_theme_constant_override("margin_top", 4)
		tile_margin.add_theme_constant_override("margin_right", 5)
		tile_margin.add_theme_constant_override("margin_bottom", 4)
		button.add_child(tile_margin)
		var tile_content := HBoxContainer.new()
		tile_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile_content.add_theme_constant_override("separation", 5)
		tile_margin.add_child(tile_content)
		var tile_icon := TextureRect.new()
		tile_icon.name = "BuildingNavIcon"
		tile_icon.custom_minimum_size = Vector2(54, 0)
		tile_icon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tile_icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tile_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tile_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile_content.add_child(tile_icon)
		var tile_label := Label.new()
		tile_label.name = "BuildingNavLabel"
		tile_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		tile_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tile_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile_label.add_theme_font_size_override("font_size", 10)
		tile_label.add_theme_color_override("font_color", HUD_TEXT)
		tile_content.add_child(tile_label)
		_building_navigation_buttons[slot_id] = button


func _render_building_navigation_rail() -> void:
	if game_state == null:
		return
	for slot_id in BUILDING_MANAGEMENT_ORDER:
		var button := _building_navigation_buttons.get(slot_id) as Button
		if button == null:
			continue
		var slot_data: Dictionary = game_state.platform.slot_states.get(slot_id, {})
		var definition_id := str(slot_data.get("definition_id", SLOT_LAYOUT.get(slot_id, {}).get("definition_id", "")))
		var definition = GameDatabase.buildings.get(definition_id)
		var building = _building_system.get_building_for_slot(game_state, slot_id)
		var short_name := str(BUILDING_MANAGEMENT_SHORT_NAMES.get(definition_id, definition.display_name if definition != null else definition_id.to_upper()))
		var state_text := "RUINA" if building == null else "POZIOM %d" % int(building.level)
		if building != null and not building.is_built:
			state_text = "NIEAKTYWNY"
		var selected := slot_id == _selected_slot_id
		var tile_label := button.find_child("BuildingNavLabel", true, false) as Label
		if tile_label != null:
			tile_label.text = "%s%s\n%s" % ["▶ " if selected else "", short_name, state_text]
			tile_label.add_theme_color_override("font_color", HUD_AMBER if selected else HUD_TEXT)
		button.tooltip_text = "%s\n%s" % [definition.display_name if definition != null else short_name, _slot_tooltip_text(slot_id)]
		var tile_icon := button.find_child("BuildingNavIcon", true, false) as TextureRect
		if tile_icon != null:
			tile_icon.texture = _building_art_texture(definition_id, clampi(int(building.level), 1, 4) if building != null else 1)
		button.add_theme_stylebox_override("normal", _building_navigation_button_style(selected, false, false))
		button.add_theme_stylebox_override("hover", _building_navigation_button_style(selected, true, false))
		button.add_theme_stylebox_override("pressed", _building_navigation_button_style(true, true, false))
		button.add_theme_stylebox_override("focus", _building_navigation_button_style(selected, false, true))
		button.add_theme_color_override("font_color", HUD_TEXT)
		button.add_theme_color_override("font_hover_color", HUD_TEXT)
		button.add_theme_color_override("font_pressed_color", HUD_TEXT)
		button.add_theme_color_override("font_focus_color", HUD_TEXT)
		button.add_theme_font_size_override("font_size", 11)
		button.set_meta("selected", selected)
		button.set_meta("state_text", state_text)


func _on_building_navigation_selected(slot_id: String) -> void:
	if slot_id == _selected_slot_id:
		_building_panel.call_deferred("focus_initial")
		return
	_on_slot_selected(slot_id)

func _build_day_summary() -> void:
	_day_summary_panel = DaySummaryPanelScript.new()
	_day_summary_panel.build()
	_day_summary_panel.acknowledged.connect(_on_day_summary_acknowledged)
	_hud_root.add_child(_day_summary_panel)

func _build_mission_journal() -> void:
	_mission_journal_panel = MissionJournalPanelScript.new()
	_mission_journal_panel.build()
	_mission_journal_panel.closed.connect(_on_journal_closed)
	_mission_journal_panel.track_requested.connect(_on_journal_track_requested)
	_hud_root.add_child(_mission_journal_panel)


func _build_day_report_journal() -> void:
	_day_report_journal_panel = DayReportJournalPanelScript.new()
	_day_report_journal_panel.build()
	_day_report_journal_panel.closed.connect(_on_report_journal_closed)
	_hud_root.add_child(_day_report_journal_panel)


func _build_settlement_event() -> void:
	_settlement_event_panel = SettlementEventPanelScript.new()
	_settlement_event_panel.build()
	_settlement_event_panel.choice_selected.connect(_on_settlement_event_choice_selected)
	_hud_root.add_child(_settlement_event_panel)


func _build_difficulty_debug_panel() -> void:
	_difficulty_debug_panel = DifficultyDebugPanelScript.new()
	_difficulty_debug_panel.build()
	_hud_root.add_child(_difficulty_debug_panel)

func _layout_board() -> void:
	if _environment == null or size.x <= 0.0 or size.y <= 0.0:
		return
	_environment.layout_environment(size)
	if _survivor_development_panel != null and _survivor_development_panel.visible:
		_refresh_survivor_panel_layout(size)
	if _modal_layer != null and _modal_layer.visible and _building_panel != null and _building_panel.visible:
		if _building_panel.has_method("refresh_layout"):
			_building_panel.refresh_layout(_building_panel_available_size(size))
	if _modal_layer != null and _modal_layer.visible and _worker_candidate_panel != null and _worker_candidate_panel.visible:
		_worker_candidate_panel.refresh_layout(size)


func _building_panel_available_size(viewport_size: Vector2) -> Vector2:
	return Vector2(
		maxf(
			viewport_size.x * (1.0 - BUILDING_WORKSPACE_SIDE_ANCHOR * 2.0)
			- BUILDING_NAVIGATION_RAIL_WIDTH
			- BUILDING_RIGHT_SIDEBAR_WIDTH
			- BUILDING_WORKSPACE_SEPARATION * 2.0,
			360.0
		),
		maxf(viewport_size.y - BUILDING_WORKSPACE_TOP_OFFSET - BUILDING_WORKSPACE_BOTTOM_MARGIN, 360.0)
	)

func _render() -> void:
	if _day_label == null:
		return
	if game_state == null:
		_day_label.text = "Ładowanie..."
		_resource_label.text = ""
		_crew_button.visible = false
		_day_plan_button.disabled = true
		_day_plan_button.tooltip_text = "Trwa ładowanie stanu kampanii."
		_close_day_plan_popover(false)
		_close_crew_flyout(false)
		_tutorial_panel.visible = false
		_campaign_panel.visible = false
		_end_day_button.disabled = true
		_end_day_button.tooltip_text = "Trwa ładowanie stanu kampanii."
		_report_journal_button.disabled = true
		_report_journal_button.tooltip_text = "Trwa ładowanie stanu kampanii."
		if _day_summary_panel != null:
			_day_summary_panel.dismiss()
		if _settlement_event_panel != null:
			_settlement_event_panel.dismiss()
		if _mission_journal_panel != null:
			_mission_journal_panel.dismiss()
		if _day_report_journal_panel != null:
			_day_report_journal_panel.dismiss(false)
		_clear_building_highlight()
		return

	if game_root != null and game_root.has_method("reconcile_missions"):
		game_root.reconcile_missions()
	_environment.set_powered_presentation(
		game_state.story_flags != null and bool(game_state.story_flags.junction_j7_active)
	)
	_environment.configure_weather(game_state.weather)
	_sync_tutorial_state()
	_layout_building_slots()
	_day_label.text = "DZIEŃ %d" % game_state.day
	var population: int = game_state.get_alive_survivors().size()
	var shelter_capacity: int = _building_effect_system.shelter_capacity_for_state(game_state)
	_resource_label.text = "[color=#B6CAC6]ŻYW[/color] [color=#F2F0E7]%d[/color]  [color=#B6CAC6]LEKI[/color] [color=#F2F0E7]%d[/color]  [color=#2C7277]│[/color]  [color=#B6CAC6]DES[/color] [color=#F2F0E7]%d[/color]  [color=#B6CAC6]ZŁOM[/color] [color=#F2F0E7]%d[/color]  [color=#B6CAC6]TKAN[/color] [color=#F2F0E7]%d[/color]  [color=#B6CAC6]TECH[/color] [color=#F2F0E7]%d[/color]  [color=#2C7277]│[/color]  [color=#F2AF36]NADZ[/color] [color=#FFCB62]%d[/color]  [color=#79C4C0]POMOST[/color] [color=#F2F0E7]%d%%[/color]  [color=#2C7277]│[/color]  [color=#F2F0E7]%d/%d[/color] [color=#B6CAC6]MIESZKAŃCÓW[/color]" % [
		game_state.resources.get_amount(ResourceIdsScript.FOOD),
		game_state.resources.get_amount(ResourceIdsScript.MEDS_CHEMICALS),
		game_state.resources.get_amount(ResourceIdsScript.PLANKS),
		game_state.resources.get_amount(ResourceIdsScript.SCRAP),
		game_state.resources.get_amount(ResourceIdsScript.FABRIC_RUBBER),
		game_state.resources.get_amount(ResourceIdsScript.TECH_PARTS),
		game_state.resources.get_amount(ResourceIdsScript.HOPE),
		game_state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY),
		population,
		shelter_capacity,
	]
	_resource_label.tooltip_text = "Jedzenie • Chemikalia i leki • Deski • Złom • Tkaniny i guma • Części techniczne • Nadzieja • Integralność platformy • Mieszkańcy / miejsca schronienia"
	_append_disease_resource_summary(_disease_system.campaign_presentation(game_state, GameDatabase.diseases))
	_ration_picker.disabled = not game_state.can_edit_day_plan()
	if game_state.tutorial != null and game_state.tutorial.step == TutorialStateScript.Step.SET_RATIONS:
		_ration_picker.select(0)
	else:
		var displayed_ration_policy := _displayed_ration_policy()
		for index in range(_ration_picker.item_count):
			if int(_ration_picker.get_item_metadata(index)) == displayed_ration_policy:
				_ration_picker.select(index)
				break
	_render_plan_controls()
	_render_survivors()
	_render_buildings()
	_render_slots()
	_render_tutorial()
	_render_campaign()
	_render_mission_journal()
	_render_day_report_journal()
	_render_end_day_button()
	_refresh_open_panel()
	_render_day_summary()
	_render_settlement_event()
	_refresh_building_highlight()


func _append_disease_resource_summary(campaign_view: Dictionary) -> void:
	if _resource_label == null or not bool(campaign_view.get("has_disease_signal", false)):
		return
	var outbreak_active := bool(campaign_view.get("outbreak_active", false))
	var active_count := int(campaign_view.get("active_case_count", 0))
	var contagious_count := int(campaign_view.get("contagious_case_count", 0))
	var pending_count := int(campaign_view.get("pending_exposure_count", 0))
	var threshold := int(campaign_view.get("outbreak_threshold", 0))
	var badge := "EPID" if outbreak_active else "CHOR"
	var badge_color := "#e59a7d" if outbreak_active else "#d9bb75"
	_resource_label.text += "  [color=#2C7277]•[/color]  [color=%s]%s[/color] [color=#F2F0E7]%d/%d[/color]" % [
		badge_color,
		badge,
		active_count,
		contagious_count,
	]
	_resource_label.tooltip_text += "\nZdrowie osady: aktywne przypadki %d • zakaźni %d • oczekujące narażenia %d • próg epidemii %d." % [
		active_count,
		contagious_count,
		pending_count,
		threshold,
	]

func _render_mission_journal() -> void:
	if _mission_journal_panel == null or game_state == null:
		return
	if not _mission_journal_blocker().is_empty():
		_mission_journal_panel.dismiss()
		return
	if _mission_journal_panel.is_open():
		_mission_journal_panel.refresh(game_state, _mission_system)
	if _difficulty_debug_panel != null and _difficulty_debug_panel.visible:
		_difficulty_debug_panel.present(game_state)


func _render_day_report_journal() -> void:
	if _day_report_journal_panel == null or _report_journal_button == null or game_state == null:
		return
	var report_journal_blocker := _report_journal_blocker()
	_report_journal_button.disabled = not report_journal_blocker.is_empty()
	_report_journal_button.tooltip_text = report_journal_blocker if not report_journal_blocker.is_empty() else "Otwórz zapis siedmiu ostatnich zakończonych dni."
	if not report_journal_blocker.is_empty():
		_day_report_journal_panel.dismiss(false)
		return
	if _day_report_journal_panel.is_open():
		_day_report_journal_panel.refresh(game_state.end_day_report_history)


func _render_day_summary() -> void:
	if _day_summary_panel == null or game_state == null:
		return
	if int(game_state.current_phase) != GamePhaseScript.Phase.END_DAY_REPORT or game_state.last_end_day_report == null:
		_day_summary_panel.dismiss()
		return
	_close_hud_flyouts()
	if _modal_layer != null and _modal_layer.visible:
		_close_building_panel(false)
	var dive_result = game_state.last_dive_result if bool(game_state.last_end_day_report.includes_dive) else null
	_day_summary_panel.present(game_state.last_end_day_report, game_state.last_morning_report, dive_result, int(game_state.day))

func _render_settlement_event() -> void:
	if _settlement_event_panel == null or game_state == null:
		return
	if int(game_state.current_phase) != GamePhaseScript.Phase.DAY_START_REPORT or not game_state.has_pending_settlement_event():
		_settlement_event_panel.dismiss()
		return
	var event_state = game_state.pending_settlement_event
	var offer_snapshot = event_state.offer_snapshot
	if offer_snapshot == null:
		_settlement_event_panel.dismiss()
		return
	_close_hud_flyouts()
	if _modal_layer != null and _modal_layer.visible:
		_close_building_panel(false)
	_settlement_event_panel.present(event_state, offer_snapshot, game_state)

func _render_survivors() -> void:
	_crew_button.visible = true
	var campaign_view := _disease_system.campaign_presentation(game_state, GameDatabase.diseases)
	var outbreak_active := bool(campaign_view.get("outbreak_active", false))
	var active_case_count := int(campaign_view.get("active_case_count", 0))
	var contagious_case_count := int(campaign_view.get("contagious_case_count", 0))
	var pending_exposure_count := int(campaign_view.get("pending_exposure_count", 0))
	var outbreak_threshold := int(campaign_view.get("outbreak_threshold", 0))
	if _epidemic_status_label != null:
		if outbreak_active:
			_epidemic_status_label.text = "EPIDEMIA AKTYWNA  •  zakaźni %d / próg %d  •  przypadki %d  •  oczekujące narażenia %d" % [
				contagious_case_count,
				outbreak_threshold,
				active_case_count,
				pending_exposure_count,
			]
			_epidemic_status_label.add_theme_color_override("font_color", Color("e59a7d"))
		elif bool(campaign_view.get("has_disease_signal", false)):
			_epidemic_status_label.text = "NADZÓR CHOROBOWY  •  zakaźni %d / próg %d  •  przypadki %d  •  oczekujące narażenia %d" % [
				contagious_case_count,
				outbreak_threshold,
				active_case_count,
				pending_exposure_count,
			]
			_epidemic_status_label.add_theme_color_override("font_color", Color("d9bb75"))
		else:
			_epidemic_status_label.text = "EPIDEMIA  •  brak aktywnych sygnałów  •  próg %d" % outbreak_threshold
			_epidemic_status_label.add_theme_color_override("font_color", Color("82aaa2"))
	var focused_survivor_button_name := ""
	if _survivors_panel != null and _survivors_panel.visible:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner != null and _survivor_list.is_ancestor_of(focus_owner) and str(focus_owner.name).begins_with("SurvivorButton_"):
			focused_survivor_button_name = str(focus_owner.name)
	for child in _survivor_list.get_children():
		_survivor_list.remove_child(child)
		child.queue_free()
	var present_survivors: Array = []
	var attention_count := 0
	for survivor in game_state.get_alive_survivors():
		if survivor.has_method("is_present_in_settlement") and not survivor.is_present_in_settlement():
			continue
		present_survivors.append(survivor)
		var disease_views := _disease_presentations_for(survivor)
		var has_ready_talent := _career_progression_system.has_selectable_profession_talent(game_state, survivor)
		if survivor.health < survivor.get_max_health() or survivor.hunger >= 60 or survivor.fatigue >= 60 or survivor.morale <= 35 or not disease_views.is_empty() or has_ready_talent:
			attention_count += 1
		var button := Button.new()
		button.name = "SurvivorButton_%s" % survivor.id
		var profession_summary: String = str(survivor.profession).capitalize()
		if not survivor.secondary_profession.is_empty():
			profession_summary += " + " + str(survivor.secondary_profession).capitalize()
		button.custom_minimum_size = Vector2(0, 106 if survivor.unspent_skill_points > 0 and has_ready_talent else 90 if survivor.unspent_skill_points > 0 or has_ready_talent else 72)
		button.tooltip_text = "Otwórz kartę mieszkańca i sprawdź dostępne decyzje rozwoju."
		if survivor.unspent_skill_points > 0:
			button.tooltip_text += "\nPunkty rozwoju do rozdania: %d." % survivor.unspent_skill_points
		if has_ready_talent:
			button.tooltip_text += "\nTalent zawodowy czeka na trwały wybór w Domu Wspólnoty."
		if not disease_views.is_empty():
			var disease_summaries: Array[String] = []
			for view in disease_views:
				disease_summaries.append("%s — %s" % [str(view.get("display_name", "Choroba")), str(view.get("phase_label", ""))])
			button.tooltip_text += "\nChoroby: %s." % "; ".join(disease_summaries)
		button.pressed.connect(_open_survivor_panel.bind(survivor.id))
		_survivor_list.add_child(button)

		var row_margin := MarginContainer.new()
		row_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_margin.add_theme_constant_override("margin_left", 7)
		row_margin.add_theme_constant_override("margin_top", 6)
		row_margin.add_theme_constant_override("margin_right", 7)
		row_margin.add_theme_constant_override("margin_bottom", 6)
		button.add_child(row_margin)
		row_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		row_margin.add_child(row)

		var portrait = SurvivorPortraitScript.new()
		portrait.name = "CrewPortrait_%s" % survivor.id
		portrait.custom_minimum_size = Vector2(44, 54)
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		portrait.configure(str(survivor.portrait_id), str(survivor.display_name))
		row.add_child(portrait)

		var details := VBoxContainer.new()
		details.name = "SurvivorDetails_%s" % survivor.id
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		details.mouse_filter = Control.MOUSE_FILTER_IGNORE
		details.add_theme_constant_override("separation", 0)
		row.add_child(details)

		var summary := Label.new()
		summary.name = "SurvivorSummary_%s" % survivor.id
		summary.text = "%s  •  POZ. %d" % [survivor.display_name, survivor.level]
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
		summary.add_theme_font_size_override("font_size", 11)
		details.add_child(summary)

		var assignment_row := HBoxContainer.new()
		assignment_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		assignment_row.add_theme_constant_override("separation", 5)
		details.add_child(assignment_row)
		var profession := Label.new()
		profession.text = "%s  •" % profession_summary
		profession.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		profession.mouse_filter = Control.MOUSE_FILTER_IGNORE
		profession.add_theme_font_size_override("font_size", 11)
		assignment_row.add_child(profession)
		var assignment := Label.new()
		assignment.name = "SurvivorAssignment_%s" % survivor.id
		assignment.text = _assignment_label(survivor)
		assignment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		assignment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		assignment.add_theme_font_size_override("font_size", 11)
		if survivor.current_assignment.is_empty() and int(survivor.status) == SurvivorStateScript.Status.AVAILABLE:
			assignment.add_theme_color_override("font_color", CREW_AVAILABLE_COLOR)
		assignment_row.add_child(assignment)

		var vitals := Label.new()
		vitals.name = "SurvivorVitals_%s" % survivor.id
		vitals.text = "ZDROWIE %d/%d   GŁÓD %d%%   ZMĘCZENIE %d%%" % [
			survivor.health,
			survivor.get_max_health(),
			survivor.hunger,
			survivor.fatigue,
		]
		vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vitals.add_theme_font_size_override("font_size", 12)
		details.add_child(vitals)

		if survivor.unspent_skill_points > 0:
			var development_alert := Label.new()
			development_alert.name = "SurvivorDevelopmentAlert_%s" % survivor.id
			development_alert.text = "PUNKTY ROZWOJU DO ROZDANIA: %d" % survivor.unspent_skill_points
			development_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
			development_alert.add_theme_font_size_override("font_size", 11)
			development_alert.add_theme_color_override("font_color", CREW_DEVELOPMENT_COLOR)
			details.add_child(development_alert)
		if has_ready_talent:
			var talent_alert := Label.new()
			talent_alert.name = "SurvivorTalentAlert_%s" % survivor.id
			talent_alert.text = "TALENT ZAWODOWY DO WYBORU"
			talent_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
			talent_alert.add_theme_font_size_override("font_size", 11)
			talent_alert.add_theme_color_override("font_color", CREW_DEVELOPMENT_COLOR)
			details.add_child(talent_alert)
	var epidemic_badge := (
		"  •  EPIDEMIA"
		if outbreak_active
		else (
			"  •  CHOROBY %d" % active_case_count
			if active_case_count > 0
			else ("  •  NARAŻENIA %d" % pending_exposure_count if pending_exposure_count > 0 else "")
		)
	)
	_crew_button.text = "ZAŁOGA  %d%s%s" % [present_survivors.size(), "  •  !%d" % attention_count if attention_count > 0 else "", epidemic_badge]
	_crew_button.tooltip_text = "Otwórz listę mieszkańców.%s%s" % [
		"  %d osób wymaga uwagi." % attention_count if attention_count > 0 else "",
		"  Epidemia jest aktywna." if outbreak_active else ("  Aktywne przypadki choroby: %d." % active_case_count if active_case_count > 0 else ("  Oczekujące narażenia: %d." % pending_exposure_count if pending_exposure_count > 0 else "")),
	]
	var crew_border := HUD_CORAL if attention_count > 0 else HUD_BORDER
	_crew_button.add_theme_stylebox_override("normal", _hud_button_style(Color(HUD_RAISED, 0.94), crew_border, 1))
	_crew_button.add_theme_stylebox_override("hover", _hud_button_style(Color(HUD_RAISED_HOVER, 0.98), crew_border.lightened(0.18), 1))
	if _survivors_panel != null and _survivors_panel.visible:
		call_deferred("_refresh_crew_focus_after_render", focused_survivor_button_name)

func _render_buildings() -> void:
	if _environment != null and _environment.has_method("sync_building_states"):
		_environment.sync_building_states(game_state)
	for child in _building_layer.get_children():
		if _building_presentations.values().has(child):
			continue
		_building_layer.remove_child(child)
		child.queue_free()
	for slot_id in SLOT_LAYOUT.keys():
		var building = _building_system.get_building_for_slot(game_state, str(slot_id))
		_configure_building_presentation(str(slot_id), building)
		_configure_occupancy_badge(str(slot_id), building)

func _configure_occupancy_badge(slot_id: String, building) -> void:
	var badge = _occupancy_badges.get(slot_id)
	if badge == null:
		return
	if building == null or not building.is_built:
		badge.configure(slot_id, "", 0, [], false)
		return
	var definition_id := str(SLOT_LAYOUT[slot_id]["definition_id"])
	var definition = GameDatabase.buildings.get(definition_id)
	if definition == null:
		badge.configure(slot_id, "", 0, [], false)
		return
	var level_definition = definition.get_level_definition(int(building.level))
	var building_name := str(level_definition.display_name) if level_definition != null else str(definition.display_name)
	var capacity: int = mini(definition.get_worker_slots(int(building.level)), 3)
	var workers: Array[Dictionary] = []
	for survivor_id_value in building.assigned_survivor_ids:
		if workers.size() >= capacity:
			break
		var survivor_id := str(survivor_id_value)
		var survivor = game_state.find_survivor(survivor_id)
		if survivor == null:
			workers.append({
				"survivor_id": survivor_id,
				"portrait_id": survivor_id,
				"display_name": "Nieznana osoba",
				"ready": false,
				"blocker": "Brak rekordu przypisanej osoby.",
			})
			continue
		var slot_index := workers.size()
		var blocker := str(survivor.work_blocker())
		workers.append({
			"survivor_id": survivor_id,
			"portrait_id": str(survivor.portrait_id),
			"display_name": str(survivor.display_name),
			"ready": blocker.is_empty(),
			"blocker": blocker,
		})
	badge.configure(slot_id, building_name, capacity, workers, true)

func _building_art_texture(definition_id: String, level: int):
	var prefix: String = str(BUILDING_ART_PREFIXES.get(definition_id, ""))
	if prefix.is_empty():
		return null
	var normalized_level := clampi(level, 1, 4)
	var suffix := "" if normalized_level == 1 else "_lvl%d" % normalized_level
	return ResourceLoader.load("%s/%s%s.png" % [BUILDING_ART_DIRECTORY, prefix, suffix])

func _configure_building_presentation(slot_id: String, building) -> void:
	var presentation = _building_presentations.get(slot_id)
	if presentation == null:
		return
	var definition_id: String = str(SLOT_LAYOUT[slot_id]["definition_id"])
	var visual_state: int = _building_visual_state(building, definition_id)
	var target_texture = null
	if visual_state == BuildingPresentationScript.VisualState.CONSTRUCTION_PLANNED:
		target_texture = _building_art_texture(definition_id, 1)
	elif visual_state == BuildingPresentationScript.VisualState.UPGRADE_PLANNED:
		target_texture = _building_art_texture(definition_id, clampi(int(building.pending_level), 1, 4))
	var wind_direction := Vector2(0.76, 0.65).normalized()
	var wind_strength := 0.45
	if game_state.weather != null:
		wind_direction = Vector2(game_state.weather.wind_direction)
		if wind_direction.length_squared() < 0.001:
			wind_direction = Vector2(0.76, 0.65)
		wind_direction = wind_direction.normalized()
		wind_strength = clampf(0.22 + float(game_state.weather.sea_intensity) * 0.52 + float(game_state.weather.rain_intensity) * 0.18, 0.0, 1.0)
	presentation.configure(visual_state, definition_id, target_texture, wind_direction, wind_strength, _reduced_motion)
	if _animation_time_override >= 0.0:
		presentation.set_animation_time_for_tests(_animation_time_override)

func _building_visual_state(building, definition_id: String) -> int:
	if building == null:
		return BuildingPresentationScript.VisualState.EMPTY
	if not building.is_built:
		return BuildingPresentationScript.VisualState.CONSTRUCTION_PLANNED
	if building.pending_level > building.level:
		return BuildingPresentationScript.VisualState.UPGRADE_PLANNED
	if building.condition <= 0:
		# `condition` is retained only as a defensive compatibility gate. There is
		# no active per-building damage/repair loop, so the presentation must not
		# advertise a recoverable "damaged building" mechanic.
		return BuildingPresentationScript.VisualState.BLOCKED
	if building.assigned_survivor_ids.is_empty():
		return BuildingPresentationScript.VisualState.ACTIVE_UNSTAFFED
	for survivor_id in building.assigned_survivor_ids:
		var survivor = game_state.find_survivor(str(survivor_id))
		if survivor != null and survivor.can_work():
			var definition = GameDatabase.buildings.get(definition_id)
			if definition == null:
				return BuildingPresentationScript.VisualState.ACTIVE_STAFFED
			var preview: Dictionary = _building_effect_system.staffing_preview(game_state, definition, building)
			var mode := str(preview.get("mode", ""))
			if mode in ["dive_blocked", "repair_blocked", "repair_no_output"]:
				return BuildingPresentationScript.VisualState.BLOCKED
			if mode in ["idle", "medical_idle"]:
				return BuildingPresentationScript.VisualState.ACTIVE_IDLE
			return BuildingPresentationScript.VisualState.ACTIVE_STAFFED
	return BuildingPresentationScript.VisualState.BLOCKED

func _play_building_state_entry(slot_id: String) -> void:
	var presentation = _building_presentations.get(slot_id)
	if presentation != null and presentation.has_method("play_state_entry"):
		presentation.play_state_entry()

func _layout_building_slots() -> void:
	if _slot_layer == null:
		return
	for slot_id in _slots.keys():
		var slot_data: Dictionary = SLOT_LAYOUT[slot_id]
		var hit_rect: Rect2 = slot_data["hit_rect"]
		_apply_normalized_rect(_slots[slot_id], hit_rect)
		_slots[slot_id].set_visual_rect_ratio(_relative_rect(slot_data["rect"], hit_rect))
		var occupancy_badge = _occupancy_badges.get(slot_id)
		if occupancy_badge != null:
			_apply_normalized_rect(occupancy_badge, OCCUPANCY_BADGE_RECTS[slot_id])

func _relative_rect(inner: Rect2, outer: Rect2) -> Rect2:
	return Rect2((inner.position - outer.position) / outer.size, inner.size / outer.size)

func _building_art_z(definition_id: String) -> int:
	return int(BUILDING_ART_Z.get(definition_id, 0))

func _render_slots() -> void:
	for slot_id in _slots.keys():
		var slot = _slots[slot_id]
		var building = _building_system.get_building_for_slot(game_state, slot_id)
		var target_definition := ""
		match int(game_state.tutorial.step):
			TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE, TutorialStateScript.Step.ASSIGN_COMMUNITY_WORKER:
				target_definition = "community_house"
			TutorialStateScript.Step.BUILD_DIVING_STATION, TutorialStateScript.Step.ASSIGN_DIVER_FIRST, TutorialStateScript.Step.START_FIRST_DIVE, TutorialStateScript.Step.START_FINAL_DIVE:
				target_definition = "diving_station"
			TutorialStateScript.Step.BUILD_WORKSHOP, TutorialStateScript.Step.STAFF_WORKSHOP, TutorialStateScript.Step.CRAFT_RESCUE_KNIFE:
				target_definition = "workshop"
		var slot_data: Dictionary = game_state.platform.slot_states.get(slot_id, {})
		var is_target: bool = game_state.tutorial.is_active() and str(slot_data.get("definition_id", "")) == target_definition
		var queued: bool = building != null and building.is_under_construction()
		slot.set_state(is_target, queued)
		var definition = GameDatabase.buildings.get(str(slot_data.get("definition_id", "")))
		var rebuild_is_affordable := building == null and definition != null and _building_system.can_afford(game_state, _building_system.get_build_cost(game_state, definition))
		slot.set_rebuild_indicator(building == null, rebuild_is_affordable)

func _render_tutorial() -> void:
	var tutorial = game_state.tutorial
	_tutorial_panel.visible = tutorial != null and tutorial.is_active()
	if not _tutorial_panel.visible:
		return
	var message: Dictionary = NarrativeContentScript.tutorial_message(int(tutorial.step))
	if message.is_empty():
		_set_tutorial_callout_rect("left_top")
		_tutorial_title.text = "SAMOUCZEK  •  WZNOWIENIE"
		_tutorial_body.text = "Stan prowadzenia jest uzgadniany. Ponownie otwórz bieżący ekran; jeśli komunikat pozostanie, wczytaj ostatni zapis."
		return
	var callout_layout := str(message.get("callout_layout", "left_top"))
	if _day_plan_popover != null and _day_plan_popover.visible:
		callout_layout = "left_top"
	elif _survivors_panel != null and _survivors_panel.visible:
		callout_layout = "right_top"
	elif _modal_layer != null and _modal_layer.visible and _building_panel != null and _building_panel.visible:
		callout_layout = "management_top_right"
	_set_tutorial_callout_rect(callout_layout)
	_tutorial_title.text = str(message.get("compact_title", "SAMOUCZEK"))
	_tutorial_body.text = str(message.get("body", ""))

func _set_tutorial_callout_rect(layout_id: String) -> void:
	match layout_id:
		"management_top_right":
			var management_rect: Rect2 = _building_panel.get_global_rect() if _building_panel != null and _building_panel.visible else Rect2(440.0, 68.0, 356.0, 96.0)
			var callout_left: float = management_rect.position.x + 24.0
			_tutorial_panel.anchor_left = 0.0
			_tutorial_panel.anchor_top = 0.0
			_tutorial_panel.anchor_right = 0.0
			_tutorial_panel.anchor_bottom = 0.0
			_tutorial_panel.offset_left = callout_left
			_tutorial_panel.offset_top = 60
			_tutorial_panel.offset_right = callout_left + 356.0
			_tutorial_panel.offset_bottom = 156
		"right_top":
			_tutorial_panel.anchor_left = 1.0
			_tutorial_panel.anchor_top = 0.0
			_tutorial_panel.anchor_right = 1.0
			_tutorial_panel.anchor_bottom = 0.0
			_tutorial_panel.offset_left = -370
			_tutorial_panel.offset_top = 60
			_tutorial_panel.offset_right = -14
			_tutorial_panel.offset_bottom = 156
		"right_bottom":
			_tutorial_panel.anchor_left = 1.0
			_tutorial_panel.anchor_top = 1.0
			_tutorial_panel.anchor_right = 1.0
			_tutorial_panel.anchor_bottom = 1.0
			_tutorial_panel.offset_left = -370
			_tutorial_panel.offset_top = -164
			_tutorial_panel.offset_right = -14
			_tutorial_panel.offset_bottom = -68
		_:
			_tutorial_panel.anchor_left = 0.0
			_tutorial_panel.anchor_top = 0.0
			_tutorial_panel.anchor_right = 0.0
			_tutorial_panel.anchor_bottom = 0.0
			_tutorial_panel.offset_left = 14
			_tutorial_panel.offset_top = 60
			_tutorial_panel.offset_right = 370
			_tutorial_panel.offset_bottom = 156

func _render_campaign() -> void:
	if _campaign_panel == null or game_state == null or game_state.story_flags == null:
		return
	var story = game_state.story_flags
	var campaign_objective := _campaign_system.objective_text(game_state)
	var building_management_open := _modal_layer != null and _modal_layer.visible
	_campaign_panel.visible = (not game_state.tutorial.is_active() or bool(story.crisis_active)) and not building_management_open
	if not _campaign_panel.visible:
		return
	var mission_view: Dictionary = _mission_system.tracked_mission_view(game_state)
	if mission_view.is_empty():
		_campaign_act_label.text = _campaign_system.act_display_name(game_state).to_upper()
		_campaign_objective_label.text = campaign_objective
		_campaign_artifacts_label.text = ""
		_campaign_artifacts_label.visible = false
		_campaign_details_button.visible = false
		_campaign_progress.visible = false
		if _campaign_scroll != null:
			_campaign_scroll.scroll_vertical = 0
	else:
		var progress := _mission_progress_values(mission_view)
		var current := int(progress.get("current", 0))
		var required := maxi(int(progress.get("required", 1)), 1)
		_campaign_act_label.text = "%s  •  %s" % [_mission_category_label(str(mission_view.get("category", "main"))), _campaign_system.act_display_name(game_state).to_upper()]
		_campaign_objective_label.text = "%s\nŚLEDZONE: %s  •  %d/%d\nNASTĘPNIE: %s" % [
			campaign_objective,
			str(mission_view.get("title", "Bieżące zadanie")).to_upper(),
			current,
			required,
			_next_mission_step(mission_view.get("objectives", []), str(mission_view.get("summary", "Sprawdź dziennik zadania."))),
		]
		_campaign_artifacts_label.text = "\n".join(_mission_objective_lines(mission_view.get("objectives", [])))
		_campaign_artifacts_label.visible = _campaign_details_expanded
		_campaign_details_button.visible = not _campaign_artifacts_label.text.is_empty()
		_campaign_details_button.text = "MNIEJ" if _campaign_details_expanded else "WIĘCEJ"
		_campaign_progress.max_value = required
		_campaign_progress.value = current
		_campaign_progress.visible = required > 1
	_journal_button.visible = not mission_view.is_empty() or (game_state.mission_progress != null and (not game_state.mission_progress.active_mission_ids.is_empty() or not game_state.mission_progress.completed_mission_ids.is_empty() or not game_state.mission_progress.failed_mission_ids.is_empty()))
	var mission_journal_blocker := _mission_journal_blocker()
	_journal_button.disabled = not mission_journal_blocker.is_empty()
	_journal_button.tooltip_text = mission_journal_blocker if not mission_journal_blocker.is_empty() else "Otwórz pełny dziennik misji."
	_report_journal_button.visible = true
	_campaign_panel.offset_top = -174.0
	if _campaign_scroll != null:
		_campaign_scroll.scroll_vertical = 0
	if bool(story.crisis_active):
		_campaign_panel.add_theme_stylebox_override("panel", _panel_style(Color("3a2425f2"), HUD_CORAL, 2))
	else:
		_campaign_panel.add_theme_stylebox_override("panel", _panel_style(Color(HUD_BASE, 0.95), HUD_BORDER, 1))

func _next_mission_step(raw_objectives, fallback: String) -> String:
	if raw_objectives is Array:
		for raw_objective in raw_objectives:
			if raw_objective is Dictionary and not bool(raw_objective.get("complete", false)) and not bool(raw_objective.get("failed", false)):
				return str(raw_objective.get("text", fallback))
	return fallback

func _on_campaign_details_pressed() -> void:
	_campaign_details_expanded = not _campaign_details_expanded
	_render_campaign()
	if not _campaign_details_expanded and _campaign_scroll != null:
		_campaign_scroll.scroll_vertical = 0

func _mission_progress_values(view: Dictionary) -> Dictionary:
	var current = view.get("current", 0)
	var required = view.get("required", view.get("target", 1))
	var progress = view.get("progress", null)
	if progress is Dictionary:
		current = progress.get("current", progress.get("completed", current))
		required = progress.get("required", progress.get("target", progress.get("total", required)))
	elif progress is int or progress is float:
		current = progress
	return {"current": maxi(int(current), 0), "required": maxi(int(required), 1)}

func _mission_objective_lines(raw_objectives) -> Array[String]:
	var result: Array[String] = []
	if not raw_objectives is Array:
		return result
	for raw_objective in raw_objectives:
		if not raw_objective is Dictionary:
			continue
		var objective: Dictionary = raw_objective
		var complete := bool(objective.get("complete", false))
		var failed := bool(objective.get("failed", false))
		var marker := "✕" if failed else "✓" if complete else "○"
		var line := "%s %s" % [marker, str(objective.get("text", "Cel zadania"))]
		var status_text := str(objective.get("status_text", "")).strip_edges()
		# Tracker ma pozostać krótką checklistą. Pełny status każdego budynku
		# jest dostępny w szczegółach dziennika pod J.
		if str(objective.get("kind", "")) != "building_built" and not status_text.is_empty() and not complete:
			line += " — %s" % status_text
		result.append(line)
	return result

func _mission_category_label(category: String) -> String:
	match category:
		"urgent":
			return "CEL KRYZYSOWY"
		"side":
			return "MISJA POBOCZNA"
	return "MISJA GŁÓWNA"

func _render_end_day_button() -> void:
	var tutorial_active: bool = game_state.tutorial != null and game_state.tutorial.is_active()
	var is_target: bool = tutorial_active and game_state.tutorial.step == TutorialStateScript.Step.END_FIRST_DAY
	var blocker := _end_day_blocker()
	_end_day_button.disabled = not blocker.is_empty()
	_end_day_button.tooltip_text = blocker if not blocker.is_empty() else "Rozlicz zaplanowane prace, racje i skutki dnia."
	_end_day_button.add_theme_stylebox_override("normal", _hud_button_style(HUD_AMBER_HOVER if is_target else HUD_AMBER, HUD_AMBER_DARK, 3 if is_target else 2))
	_end_day_button.add_theme_stylebox_override("hover", _hud_button_style(HUD_AMBER_HOVER, HUD_AMBER_DARK, 2))
	_end_day_button.add_theme_stylebox_override("disabled", _hud_button_style(Color(HUD_BASE, 0.68), Color(HUD_BORDER, 0.62), 1))
	_end_day_button.text = "ZAKOŃCZ DZIEŃ  ›"

func _refresh_open_panel() -> void:
	if not _modal_layer.visible or _selected_slot_id.is_empty():
		return
	var slot_data: Dictionary = game_state.platform.slot_states.get(_selected_slot_id, {})
	var definition = GameDatabase.buildings.get(str(slot_data.get("definition_id", "")))
	if definition == null:
		_close_building_panel()
		return
	var building = _building_system.get_building_for_slot(game_state, _selected_slot_id)
	var header_art_level := 1 if building == null else clampi(maxi(int(building.level), int(building.pending_level)), 1, 4)
	_building_panel.configure(
		game_state,
		_selected_slot_id,
		definition,
		building,
		_building_system,
		_production_system,
		game_state.tutorial.step,
		_building_art_texture(str(definition.id), header_art_level)
	)
	_building_panel.refresh_layout(_building_panel_available_size(size))
	_render_building_navigation_rail()
	if _focus_building_on_next_refresh:
		_focus_building_on_next_refresh = false
		_building_panel.call_deferred("focus_initial")

func _sync_tutorial_state() -> void:
	if game_root != null:
		game_root.reconcile_tutorial()

func _on_slot_selected(slot_id: String) -> void:
	if game_state == null or int(game_state.current_phase) not in [GamePhaseScript.Phase.BASE_PLANNING, GamePhaseScript.Phase.CRISIS]:
		return
	var slot_data: Dictionary = game_state.platform.slot_states.get(slot_id, {})
	if slot_data.is_empty():
		return
	_selected_slot_id = slot_id
	_selected_survivor_id = ""
	_focus_building_on_next_refresh = true
	_close_hud_flyouts()
	_building_panel.visible = true
	_worker_candidate_panel.visible = false
	_worker_picker_slot_index = -1
	_survivor_development_panel.visible = false
	_hovered_slot_id = ""
	_tooltip.visible = false
	_present_building_modal()
	_render()

func _on_slot_hover_changed(slot_id: String, hovered: bool) -> void:
	var occupancy_badge = _occupancy_badges.get(slot_id)
	if occupancy_badge != null and occupancy_badge.has_method("set_hovered"):
		occupancy_badge.set_hovered(hovered and not (_modal_layer != null and _modal_layer.visible))
	if _modal_layer != null and _modal_layer.visible:
		return
	if hovered:
		_hovered_slot_id = slot_id
		_tooltip_label.text = _slot_tooltip_text(slot_id)
		_tooltip.visible = true
	else:
		if _hovered_slot_id == slot_id:
			_hovered_slot_id = ""
			_tooltip.visible = false


func _on_slot_highlight_changed(slot_id: String, mode: StringName) -> void:
	if not _slots.has(slot_id):
		return
	_slot_highlight_modes[slot_id] = mode
	_refresh_building_highlight()


func _refresh_building_highlight() -> void:
	if _environment == null or not _environment.has_method("set_building_highlight"):
		return
	if (
		game_state == null
		or int(game_state.current_phase) not in [GamePhaseScript.Phase.BASE_PLANNING, GamePhaseScript.Phase.CRISIS]
		or (_modal_layer != null and _modal_layer.visible)
	):
		_clear_building_highlight()
		return
	var selected_slot_id := ""
	var selected_mode: StringName = &"none"
	var selected_priority := 0
	for slot_key in SLOT_LAYOUT.keys():
		var slot_id := str(slot_key)
		var mode := StringName(_slot_highlight_modes.get(slot_id, &"none"))
		var priority := _building_highlight_priority(mode)
		if priority > selected_priority:
			selected_priority = priority
			selected_slot_id = slot_id
			selected_mode = mode
	if selected_slot_id.is_empty():
		_clear_building_highlight()
		return
	_environment.set_building_highlight(selected_slot_id, selected_mode)


func _clear_building_highlight() -> void:
	if _environment != null and _environment.has_method("clear_building_highlight"):
		_environment.clear_building_highlight()


func _building_highlight_priority(mode: StringName) -> int:
	match mode:
		&"tutorial":
			return 4
		&"pressed":
			return 3
		&"hover":
			return 2
		&"focus":
			return 1
	return 0

func _on_build_requested(slot_id: String, definition_id: String) -> void:
	var definition = GameDatabase.buildings.get(definition_id)
	if definition == null:
		return
	if not _building_system.queue_construction(game_state, slot_id, definition):
		return
	if game_root != null:
		game_root.tutorial_event("building_completed", definition_id)
	_close_building_panel()
	_render()
	_play_building_state_entry(slot_id)
	_show_action_feedback(
		"ODBUDOWANO  •  %s\nBudynek jest aktywny od razu." % definition.display_name,
		Color("e4b45f")
	)

func _on_upgrade_requested(building_id: String) -> void:
	var building = game_state.find_building(building_id)
	if building == null:
		return
	var definition = GameDatabase.buildings.get(building.definition_id)
	if definition != null and _building_system.queue_upgrade(game_state, building, definition):
		var target_level: int = building.level
		_close_building_panel()
		_render()
		_play_building_state_entry(str(building.slot_id))
		_show_action_feedback(
			"ROZBUDOWANO  •  %s  •  POZIOM %d\nNowy poziom jest aktywny od razu." % [definition.display_name, target_level],
			Color("e4b45f")
		)

func _on_worker_picker_requested(building_id: String, slot_index: int) -> void:
	if game_state == null or _worker_candidate_panel == null:
		return
	var building = game_state.find_building(building_id)
	if building == null:
		return
	var definition = GameDatabase.buildings.get(str(building.definition_id))
	if definition == null:
		return
	var max_workers: int = definition.get_worker_slots(building.level)
	if slot_index < 0 or slot_index >= max_workers:
		return
	_worker_picker_slot_index = slot_index
	_building_panel.visible = false
	_survivor_development_panel.visible = false
	_worker_candidate_panel.visible = true
	_worker_candidate_panel.configure(game_state, definition, building, slot_index, game_state.tutorial.step)
	_worker_candidate_panel.refresh_layout(size)
	_worker_candidate_panel.call_deferred("focus_initial")


func _on_worker_candidate_chosen(building_id: String, slot_index: int, survivor_id: String) -> void:
	if _on_worker_selected(building_id, slot_index, survivor_id):
		var restore_worker_focus := (
			game_state == null
			or int(game_state.tutorial.step) != TutorialStateScript.Step.CRAFT_RESCUE_KNIFE
		)
		_close_worker_candidate_picker(restore_worker_focus)


func _close_worker_candidate_picker(restore_focus: bool = true) -> void:
	if _worker_candidate_panel == null or not _worker_candidate_panel.visible:
		return
	var slot_index := _worker_picker_slot_index
	_worker_candidate_panel.visible = false
	_worker_picker_slot_index = -1
	_building_panel.visible = true
	if restore_focus and slot_index >= 0:
		_building_panel.call_deferred("focus_worker_slot", slot_index)


func _on_worker_selected(building_id: String, slot_index: int, survivor_id: String) -> bool:
	var building = game_state.find_building(building_id)
	if building == null:
		return false
	var definition = GameDatabase.buildings.get(building.definition_id)
	if definition == null:
		return false
	var max_workers: int = definition.get_worker_slots(building.level)
	if slot_index < 0 or slot_index >= max_workers:
		return false
	if not _worker_assignment_system.assign_worker_to_slot(
		game_state,
		building.id,
		slot_index,
		survivor_id,
		max_workers
	):
		return false
	if building.definition_id == "community_house" and not survivor_id.is_empty():
		_tutorial_event("community_worker_assigned")
	elif building.definition_id == "workshop" and not survivor_id.is_empty():
		_tutorial_event("workshop_worker_assigned")
	_render()
	if survivor_id.is_empty():
		_show_action_feedback("STANOWISKO ZWOLNIONE", Color("a7b8b7"))
	else:
		var survivor = game_state.find_survivor(survivor_id)
		_show_action_feedback(
			"PRZYDZIAŁ ZAKTUALIZOWANY  •  %s" % (survivor.display_name if survivor != null else survivor_id),
			Color("78c3a2")
		)
	return true


func _on_building_work_pace_selected(building_id: String, work_pace: String) -> void:
	if game_state == null or not game_state.can_edit_day_plan():
		return
	var building = game_state.find_building(building_id)
	if building == null or not _work_pace_system.is_valid_pace(work_pace):
		return
	building.work_pace = _work_pace_system.normalize_pace(work_pace)
	if game_state.current_day_plan != null:
		game_state.current_day_plan.sync_from_state(game_state)
	_render()


func _on_medical_priority_changed(survivor_id: String, desired: bool) -> void:
	if game_state == null or game_state.current_day_plan == null or not game_state.can_edit_day_plan():
		return
	var priority_ids: Array[String] = []
	priority_ids.assign(game_state.current_day_plan.medical_priority_survivor_ids)
	priority_ids.erase(survivor_id)
	if desired:
		priority_ids.append(survivor_id)
	if game_state.current_day_plan.set_medical_priority(priority_ids):
		_render()
		var survivor = game_state.find_survivor(survivor_id)
		if survivor != null and _selected_survivor_id == survivor_id and _survivor_development_panel.visible:
			_populate_survivor_panel(survivor)


func _on_production_requested(building_id: String, recipe_id: String) -> void:
	if recipe_id == "tutorial_rescue_knife" and game_root != null:
		if game_root.craft_tutorial_rescue_knife():
			_render()
			_show_action_feedback("ODBLOKOWANO  •  NÓŻ RATOWNICZY", Color("78c3a2"))
		return
	var workshop = game_state.find_building(building_id)
	var recipe = _production_system.get_recipe(recipe_id)
	if workshop == null or recipe == null:
		return
	if _production_system.queue_recipe(game_state, workshop, recipe):
		_render()
		_show_action_feedback("DODANO DO KOLEJKI  •  %s" % recipe.display_name, Color("78c3a2"))

func _on_gear_equipped(_slot_id: String, gear_id: String) -> void:
	if _diving_equipment_system.equip(game_state, gear_id):
		_render()
		_show_action_feedback("WYPOSAŻENIE ZMIENIONE  •  %s" % gear_id.replace("_", " ").to_upper(), Color("78b9c3"))

func _on_entry_point_selected(entry_point_id: String) -> void:
	if game_state == null or game_state.current_day_plan == null:
		return
	if game_state.current_day_plan.select_expedition_entry(entry_point_id):
		_render()
		_show_action_feedback("PUNKT WEJŚCIA ZAPLANOWANY  •  %s" % entry_point_id, Color("78b9c3"))

func _on_diver_selected(survivor_id: String) -> void:
	if game_state == null:
		return
	var station = game_state.find_building_by_definition("diving_station")
	var definition = GameDatabase.buildings.get("diving_station")
	var changed := _expedition_preparation_system.clear_selected_diver(game_state) if survivor_id.is_empty() else _expedition_preparation_system.select_diver(game_state, station, definition, survivor_id)
	if not changed:
		return
	if survivor_id.is_empty():
		_render()
		_show_action_feedback("ZAPAMIĘTANY NUREK WYCZYSZCZONY", Color("a7b8b7"))
		return
	if survivor_id == "igor":
		_tutorial_event("igor_assigned")
	_render()
	var survivor = game_state.find_survivor(survivor_id)
	_show_action_feedback(
		"NUREK WYBRANY  •  %s" % (survivor.display_name if survivor != null else survivor_id),
		Color("78c3a2")
	)

func _on_dive_requested() -> void:
	if game_root == null or game_state == null:
		return
	var station = game_state.find_building_by_definition("diving_station")
	var definition = GameDatabase.buildings.get("diving_station")
	var setup = _expedition_preparation_system.build_setup(game_state, station, definition, GameDatabase.items)
	if setup == null:
		return
	game_root.start_dive(setup)

func _on_end_day_pressed() -> void:
	if game_root == null or game_state == null:
		return
	_close_hud_flyouts()
	if not _end_day_blocker().is_empty():
		return
	if not game_root.end_day():
		_end_day_button.text = "BŁĄD ZAPISU — SPRÓBUJ PONOWNIE"
		_end_day_button.tooltip_text = "Rozliczenie nie zostało zastosowane. Sprawdź miejsce na dysku i ponów zapis."

func _on_day_summary_acknowledged() -> void:
	if game_root == null or not game_root.acknowledge_day_report():
		return
	_day_summary_panel.dismiss()
	_render()

func _on_settlement_event_choice_selected(choice_id: String) -> void:
	if game_root == null or not game_root.resolve_settlement_event(choice_id):
		_settlement_event_panel.show_error("Nie udało się zapisać decyzji. Spróbuj ponownie.")

func _on_journal_pressed() -> void:
	if game_state == null or _mission_journal_panel == null:
		return
	if not _mission_journal_blocker().is_empty():
		return
	if _modal_layer != null and _modal_layer.visible:
		return
	_close_hud_flyouts()
	if _day_report_journal_panel != null and _day_report_journal_panel.is_open():
		_day_report_journal_panel.dismiss(false)
	if _mission_journal_panel.is_open():
		_mission_journal_panel.dismiss()
		_on_journal_closed()
	else:
		_mission_journal_panel.present(game_state, _mission_system)

func _on_journal_closed() -> void:
	if _journal_button != null and _journal_button.visible and not _journal_button.disabled:
		_journal_button.call_deferred("grab_focus")


func _on_report_journal_pressed() -> void:
	if game_state == null or _day_report_journal_panel == null:
		return
	if not _report_journal_blocker().is_empty():
		return
	_close_hud_flyouts()
	if _modal_layer != null and _modal_layer.visible:
		_close_building_panel()
	_hovered_slot_id = ""
	if _tooltip != null:
		_tooltip.visible = false
	if _mission_journal_panel != null and _mission_journal_panel.is_open():
		_mission_journal_panel.dismiss()
	if _day_report_journal_panel.is_open():
		_day_report_journal_panel.dismiss()
	else:
		_day_report_journal_panel.present(game_state.end_day_report_history)


func _on_report_journal_closed() -> void:
	if _report_journal_button != null and _report_journal_button.visible and not _report_journal_button.disabled:
		_report_journal_button.call_deferred("grab_focus")

func _on_journal_track_requested(mission_id: String) -> void:
	var changed := false
	if game_root != null and game_root.has_method("track_mission"):
		changed = bool(game_root.track_mission(mission_id))
	else:
		changed = _mission_system.track_mission(game_state, mission_id)
	if not changed:
		return
	_mission_journal_panel.refresh(game_state, _mission_system)
	_render_campaign()
	_show_action_feedback("CEL ŚLEDZONY  •  %s" % mission_id.replace("_", " ").to_upper(), Color("78b9c3"))

func _tutorial_event(event_id: String) -> void:
	if game_root != null:
		game_root.tutorial_event(event_id)

func _on_ration_policy_selected(index: int) -> void:
	if game_state == null or not game_state.can_edit_day_plan() or index < 0 or index >= _ration_picker.item_count:
		return
	var ration_policy := int(_ration_picker.get_item_metadata(index))
	if ration_policy not in [
		PolicyStateScript.RationPolicy.FULL,
		PolicyStateScript.RationPolicy.HALF,
		PolicyStateScript.RationPolicy.NONE,
		PolicyStateScript.RationPolicy.DIVER_PRIORITY,
	]:
		return
	game_state.active_policies.ration_policy = ration_policy
	if game_state.current_day_plan != null:
		game_state.current_day_plan.sync_from_state(game_state)
	_tutorial_event("rations_selected")
	_render()

func _on_day_plan_button_pressed() -> void:
	if _day_plan_popover == null:
		return
	if _day_plan_popover.visible:
		_close_day_plan_popover(true)
	elif _hud_flyout_can_open():
		_open_day_plan_popover()

func _on_crew_button_pressed() -> void:
	if _survivors_panel == null:
		return
	if _survivors_panel.visible:
		_close_crew_flyout(true)
		return
	if not _hud_flyout_can_open():
		return
	_open_crew_flyout()


func _open_day_plan_popover() -> void:
	_close_crew_flyout(false)
	_day_plan_popover.visible = true
	if game_state != null and _tutorial_panel != null:
		_render_tutorial()
	_sync_hud_flyout_dismiss_layer()
	call_deferred("_focus_day_plan_popover")


func _close_day_plan_popover(restore_focus: bool) -> void:
	if _day_plan_popover == null or not _day_plan_popover.visible:
		_sync_hud_flyout_dismiss_layer()
		return
	_day_plan_popover.visible = false
	_sync_hud_flyout_dismiss_layer()
	if game_state != null and _tutorial_panel != null:
		_render_tutorial()
	if restore_focus and _day_plan_button != null and _day_plan_button.visible and not _day_plan_button.disabled:
		_day_plan_button.call_deferred("grab_focus")


func _open_crew_flyout() -> void:
	_close_day_plan_popover(false)
	_survivors_panel.visible = true
	if game_state != null and game_state.tutorial != null and game_state.tutorial.is_active():
		_render_tutorial()
	_sync_hud_flyout_dismiss_layer()
	call_deferred("_focus_crew_flyout")

func _close_hud_flyouts() -> void:
	_close_day_plan_popover(false)
	_close_crew_flyout(false)

func _close_crew_flyout(restore_focus: bool) -> void:
	if _survivors_panel == null or not _survivors_panel.visible:
		_sync_hud_flyout_dismiss_layer()
		return
	_survivors_panel.visible = false
	_sync_hud_flyout_dismiss_layer()
	if game_state != null and _tutorial_panel != null:
		_render_tutorial()
	if restore_focus and _crew_button != null and _crew_button.visible:
		_crew_button.call_deferred("grab_focus")


func _sync_hud_flyout_dismiss_layer() -> void:
	if _hud_flyout_dismiss_layer == null:
		return
	_hud_flyout_dismiss_layer.visible = (
		(_day_plan_popover != null and _day_plan_popover.visible)
		or (_survivors_panel != null and _survivors_panel.visible)
	)


func _on_hud_flyout_dismiss_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _day_plan_popover != null and _day_plan_popover.visible:
		_close_day_plan_popover(true)
	elif _survivors_panel != null and _survivors_panel.visible:
		_close_crew_flyout(true)
	get_viewport().set_input_as_handled()


func _hud_flyout_can_open() -> bool:
	for overlay in [_day_summary_panel, _mission_journal_panel, _day_report_journal_panel, _settlement_event_panel, _difficulty_debug_panel]:
		if overlay != null and overlay.visible:
			return false
	return true

func _render_plan_controls() -> void:
	if game_state == null or _day_plan_button == null:
		return
	_day_plan_button.disabled = false
	var is_tutorial_target: bool = (
		game_state.tutorial != null
		and game_state.tutorial.is_active()
		and game_state.tutorial.step == TutorialStateScript.Step.SET_RATIONS
	)
	var plan_ink := HUD_DARK_TEXT if is_tutorial_target else HUD_TEXT
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_day_plan_button.add_theme_color_override(color_name, plan_ink)
	_day_plan_button.add_theme_color_override("font_disabled_color", HUD_MUTED)
	_day_plan_button.add_theme_stylebox_override(
		"normal",
		_hud_button_style(
			HUD_AMBER if is_tutorial_target else HUD_RAISED,
			HUD_AMBER_DARK if is_tutorial_target else HUD_BORDER,
			3 if is_tutorial_target else 1
		)
	)
	_day_plan_button.add_theme_stylebox_override(
		"hover",
		_hud_button_style(
			HUD_AMBER_HOVER if is_tutorial_target else HUD_RAISED_HOVER,
			HUD_AMBER_DARK if is_tutorial_target else HUD_TEAL,
			3 if is_tutorial_target else 1
		)
	)
	var planned_ration_policy := _displayed_ration_policy()
	var ration_label := "PEŁNE"
	match planned_ration_policy:
		PolicyStateScript.RationPolicy.HALF:
			ration_label = "POŁOWA"
		PolicyStateScript.RationPolicy.NONE:
			ration_label = "BRAK"
		PolicyStateScript.RationPolicy.DIVER_PRIORITY:
			ration_label = "NUREK"
	_day_plan_button.text = "PLAN DNIA  •  RACJE: %s" % ration_label
	var ration_forecast: Dictionary = _building_effect_system.ration_forecast(game_state)
	var forecast_lines: Array[String] = []
	for line in ration_forecast.get("lines", []):
		forecast_lines.append(str(line))
	_ration_hint.text = _ration_policy_hint(planned_ration_policy)
	if not forecast_lines.is_empty():
		_ration_hint.text += "\n\n" + "\n".join(forecast_lines)
	var editable: bool = game_state.can_edit_day_plan()
	_ration_picker.disabled = not editable
	_ration_picker.tooltip_text = _day_plan_edit_blocker() if not editable else "Zmień racje dla bieżącego dnia."
	_day_plan_button.tooltip_text = "Racje: %s. Tempo ustawiasz osobno w panelu każdego budynku.%s" % [
		ration_label.to_lower(),
		" Plan można teraz zmienić." if editable else " Plan jest zablokowany, ale możesz go sprawdzić.",
	]


func _displayed_ration_policy() -> int:
	if game_state != null and game_state.current_day_plan != null:
		return int(game_state.current_day_plan.ration_policy)
	if game_state != null and game_state.active_policies != null:
		return int(game_state.active_policies.ration_policy)
	return PolicyStateScript.RationPolicy.FULL


func _ration_policy_hint(policy: int) -> String:
	match policy:
		PolicyStateScript.RationPolicy.HALF:
			return "Połowa porcji dla grupy: rośnie głód, spadają Nadzieja i morale."
		PolicyStateScript.RationPolicy.NONE:
			return "Nikt nie je: duży wzrost głodu oraz spadek Nadziei i morale."
		PolicyStateScript.RationPolicy.DIVER_PRIORITY:
			return "Najpierw pełna, a przy niedoborze pół racji dla żyjącego nurka; bez poprawnego nurka obowiązuje grupowa połowa albo brak wydania."
	return "Próba pełnej racji dla wszystkich; przy niedoborze system przechodzi do połowy albo braku posiłku."


func _day_plan_edit_blocker() -> String:
	if game_state == null:
		return "Brak aktywnego stanu kampanii."
	if game_state.has_method("day_plan_edit_blocker"):
		return str(game_state.day_plan_edit_blocker())
	return "" if game_state.can_edit_day_plan() else "Plan dnia jest już zablokowany."


func _end_day_blocker() -> String:
	if game_root != null and game_root.has_method("end_day_blocker"):
		return str(game_root.end_day_blocker())
	if game_state != null and game_state.has_method("end_day_blocker"):
		return str(game_state.end_day_blocker())
	return _day_plan_edit_blocker()


func _mission_journal_blocker() -> String:
	if game_state == null:
		return "Brak aktywnego stanu kampanii."
	match int(game_state.current_phase):
		GamePhaseScript.Phase.BASE_PLANNING, GamePhaseScript.Phase.CRISIS:
			return ""
		GamePhaseScript.Phase.END_DAY_REPORT:
			return "Najpierw potwierdź obowiązkowe podsumowanie zakończonego dnia."
		GamePhaseScript.Phase.DAY_START_REPORT:
			return "Najpierw rozstrzygnij wydarzenie poranka."
	return "Dziennik misji jest dostępny podczas planowania w bazie lub kryzysu."


func _report_journal_blocker() -> String:
	if game_state == null:
		return "Brak aktywnego stanu kampanii."
	if game_state.end_day_report_history.is_empty():
		return "Pierwszy raport pojawi się po zakończeniu dnia."
	match int(game_state.current_phase):
		GamePhaseScript.Phase.BASE_PLANNING, GamePhaseScript.Phase.CRISIS:
			return ""
		GamePhaseScript.Phase.END_DAY_REPORT:
			return "Najpierw potwierdź bieżące obowiązkowe podsumowanie dnia."
		GamePhaseScript.Phase.DAY_START_REPORT:
			return "Najpierw rozstrzygnij wydarzenie poranka."
	return "Archiwum raportów jest dostępne podczas planowania w bazie lub kryzysu."


func _on_modal_background_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	# `gui_input` reports `position` in workspace-local coordinates. Child panel
	# rectangles are global, so all hit tests must use the global pointer.
	var pointer := (event as InputEventMouseButton).global_position
	if _building_panel != null and _building_panel.visible and _building_panel.get_global_rect().has_point(pointer):
		return
	if _worker_candidate_panel != null and _worker_candidate_panel.visible:
		if _worker_candidate_panel.get_global_rect().has_point(pointer):
			return
		_close_worker_candidate_picker(true)
		get_viewport().set_input_as_handled()
		return
	if _survivor_development_panel != null and _survivor_development_panel.visible:
		if _survivor_development_panel.get_global_rect().has_point(pointer):
			return
		_close_building_panel()
		get_viewport().set_input_as_handled()
		return
	# The management workspace has no click-outside close path. Only child
	# layers use the surrounding workspace to return to their parent context.

func _present_building_modal() -> void:
	if _modal_tween != null and _modal_tween.is_valid():
		_modal_tween.kill()
	for occupancy_badge in _occupancy_badges.values():
		if occupancy_badge != null and occupancy_badge.has_method("set_hovered"):
			occupancy_badge.set_hovered(false)
	_modal_layer.visible = true
	_modal_layer.modulate = Color.WHITE
	_clear_building_highlight()
	_close_hud_flyouts()
	if _campaign_panel != null:
		_campaign_panel.visible = false
	if _animation_time_override >= 0.0 or _reduced_motion:
		return
	_modal_layer.modulate.a = 0.0
	_modal_tween = create_tween()
	_modal_tween.set_trans(Tween.TRANS_SINE)
	_modal_tween.set_ease(Tween.EASE_OUT)
	_modal_tween.tween_property(_modal_layer, "modulate:a", 1.0, 0.18)

func _show_action_feedback(message: String, accent: Color) -> void:
	if _action_feedback == null or _action_feedback_label == null:
		return
	# The mission journal already confirms tracking inline by changing the
	# selected action to "ŚLEDZONE". A global toast would either sit behind or
	# cover its full-screen window, so do not duplicate that feedback.
	if _mission_journal_panel != null and _mission_journal_panel.visible:
		_hide_action_feedback()
		return
	if _action_feedback_tween != null and _action_feedback_tween.is_valid():
		_action_feedback_tween.kill()
	_layout_action_feedback_for_context()
	_action_feedback_label.text = message
	_action_feedback_label.add_theme_color_override("font_color", accent.lightened(0.18))
	_action_feedback.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(HUD_BASE, 0.97), Color(accent.r, accent.g, accent.b, 0.92), 2)
	)
	_action_feedback.visible = true
	_action_feedback.modulate = Color.WHITE
	_action_feedback.scale = Vector2.ONE
	_action_feedback.pivot_offset = _action_feedback.size * 0.5
	if _animation_time_override >= 0.0:
		return
	if _reduced_motion:
		_action_feedback_tween = create_tween()
		_action_feedback_tween.tween_interval(2.2)
		_action_feedback_tween.tween_callback(_hide_action_feedback)
		return
	_action_feedback.modulate.a = 0.0
	_action_feedback.scale = Vector2(0.985, 0.985)
	_action_feedback_tween = create_tween()
	_action_feedback_tween.set_trans(Tween.TRANS_SINE)
	_action_feedback_tween.set_ease(Tween.EASE_OUT)
	_action_feedback_tween.tween_property(_action_feedback, "modulate:a", 1.0, 0.18)
	_action_feedback_tween.parallel().tween_property(_action_feedback, "scale", Vector2.ONE, 0.18)
	_action_feedback_tween.tween_interval(2.0)
	_action_feedback_tween.set_ease(Tween.EASE_IN)
	_action_feedback_tween.tween_property(_action_feedback, "modulate:a", 0.0, 0.22)
	_action_feedback_tween.tween_callback(_hide_action_feedback)

func _layout_action_feedback_for_context() -> void:
	if _action_feedback == null:
		return
	_action_feedback.anchor_left = 0.5
	_action_feedback.anchor_right = 0.5
	if _modal_layer != null and _modal_layer.visible:
		# W otwartym workspace toast pozostaje zwarty, wyśrodkowany i
		# warstwowany nad panelem. Jest odsunięty od górnej kapsuły tutoriala,
		# aby wynik komendy nie zasłaniał bieżącej instrukcji.
		_action_feedback.offset_left = -156.0
		_action_feedback.offset_right = 156.0
		_action_feedback.anchor_top = 0.0
		_action_feedback.anchor_bottom = 0.0
		var feedback_top := 74.0
		if _tutorial_panel != null and _tutorial_panel.visible:
			var tutorial_rect := _tutorial_panel.get_global_rect()
			var tutorial_bottom := maxf(
				tutorial_rect.end.y,
				tutorial_rect.position.y + _tutorial_panel.get_combined_minimum_size().y
			)
			feedback_top = maxf(feedback_top, tutorial_bottom + 12.0)
		_action_feedback.offset_top = feedback_top
		_action_feedback.offset_bottom = feedback_top + 62.0
	else:
		_action_feedback.offset_left = -230.0
		_action_feedback.offset_right = 230.0
		_action_feedback.anchor_top = 1.0
		_action_feedback.anchor_bottom = 1.0
		_action_feedback.offset_top = -148.0
		_action_feedback.offset_bottom = -88.0

func _hide_action_feedback() -> void:
	if _action_feedback != null:
		_action_feedback.visible = false
		_action_feedback.modulate = Color.WHITE
		_action_feedback.scale = Vector2.ONE

func _close_building_panel(restore_focus: bool = true) -> void:
	if _modal_tween != null and _modal_tween.is_valid():
		_modal_tween.kill()
	var closing_slot_id := _selected_slot_id
	var was_survivor_panel := _survivor_development_panel != null and _survivor_development_panel.visible
	_selected_slot_id = ""
	_selected_survivor_id = ""
	_focus_building_on_next_refresh = false
	_modal_layer.visible = false
	_modal_layer.modulate = Color.WHITE
	_building_panel.visible = true
	_worker_candidate_panel.visible = false
	_worker_picker_slot_index = -1
	_survivor_development_panel.visible = false
	_refresh_building_highlight()
	if _action_feedback != null and _action_feedback.visible:
		_layout_action_feedback_for_context()
	if game_state != null and _tutorial_panel != null:
		_render_tutorial()
	if game_state != null and _campaign_panel != null:
		_render_campaign()
	if restore_focus and not closing_slot_id.is_empty() and _slots.has(closing_slot_id):
		(_slots[closing_slot_id] as Control).call_deferred("grab_focus")
	elif restore_focus and was_survivor_panel and _crew_button != null and _crew_button.visible:
		_crew_button.call_deferred("grab_focus")

func _open_survivor_panel(survivor_id: String) -> void:
	if game_state == null:
		return
	var survivor = game_state.find_survivor(survivor_id)
	if survivor == null:
		return
	_selected_slot_id = ""
	_selected_survivor_id = survivor_id
	_close_hud_flyouts()
	_building_panel.visible = false
	_worker_candidate_panel.visible = false
	_worker_picker_slot_index = -1
	_survivor_development_panel.visible = true
	_refresh_survivor_panel_layout(size)
	_present_building_modal()
	_populate_survivor_panel(survivor)


func _refresh_survivor_panel_layout(viewport_size: Vector2) -> void:
	if _survivor_development_panel == null:
		return
	var available_size := Vector2(
		maxf(viewport_size.x - 48.0, 0.0),
		maxf(viewport_size.y - 96.0, 0.0)
	)
	_survivor_development_panel.custom_minimum_size = Vector2(
		minf(650.0, available_size.x),
		minf(540.0, available_size.y)
	)


func _populate_survivor_panel(survivor) -> void:
	for child in _survivor_development_panel.get_children():
		_survivor_development_panel.remove_child(child)
		child.queue_free()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	_survivor_development_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 13)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.name = "SurvivorDevelopmentTitle"
	var profession_summary: String = str(survivor.profession).to_upper()
	if not survivor.secondary_profession.is_empty():
		profession_summary += " + " + survivor.secondary_profession.to_upper()
	title.text = "%s  •  %s" % [survivor.display_name.to_upper(), profession_summary]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", WORKSPACE_TEXT)
	header.add_child(title)
	var close := Button.new()
	close.name = "CloseSurvivorDevelopment"
	close.text = "Zamknij"
	_apply_workspace_secondary_button_style(close)
	close.pressed.connect(_close_building_panel)
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.name = "SurvivorDevelopmentScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "SurvivorDevelopmentBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 13)
	scroll.add_child(body)
	var biography := Label.new()
	biography.text = survivor.biography
	biography.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	biography.add_theme_color_override("font_color", WORKSPACE_MUTED)
	body.add_child(biography)
	var progress := Label.new()
	progress.name = "SurvivorDevelopmentProgress"
	progress.text = "POZIOM %d  •  PD %d / %d  •  PUNKTY ROZWOJU %d" % [survivor.level, survivor.experience, survivor.experience_to_next_level(), survivor.unspent_skill_points]
	progress.add_theme_font_size_override("font_size", 15)
	progress.add_theme_color_override("font_color", WORKSPACE_TEAL)
	body.add_child(progress)
	var stats := Label.new()
	stats.name = "SurvivorDevelopmentStats"
	stats.text = "Zdrowie  %d / %d     Tlen  %.0f     Udźwig  %.1f kg\nGłód  %d%%     Zmęczenie  %d%%     Morale  %d%%" % [
		survivor.health,
		survivor.get_max_health(),
		survivor.get_oxygen_capacity(),
		survivor.get_carry_capacity(),
		survivor.hunger,
		survivor.fatigue,
		survivor.morale,
	]
	stats.add_theme_font_size_override("font_size", 16)
	stats.add_theme_color_override("font_color", WORKSPACE_TEXT)
	stats.tooltip_text = SurvivorInfoPresenterScript.combined_state_tooltip(survivor)
	body.add_child(stats)
	var traits := HBoxContainer.new()
	traits.add_theme_constant_override("separation", 18)
	body.add_child(traits)
	var positive_trait := Label.new()
	positive_trait.name = "SurvivorPositiveTrait"
	positive_trait.text = "ATUT  •  %s" % str(survivor.positive_trait).capitalize()
	positive_trait.tooltip_text = SurvivorInfoPresenterScript.trait_tooltip(str(survivor.positive_trait), true)
	positive_trait.add_theme_color_override("font_color", WORKSPACE_GREEN)
	traits.add_child(positive_trait)
	var negative_trait := Label.new()
	negative_trait.name = "SurvivorNegativeTrait"
	negative_trait.text = "SŁABOŚĆ  •  %s" % str(survivor.negative_trait).capitalize()
	negative_trait.tooltip_text = SurvivorInfoPresenterScript.trait_tooltip(str(survivor.negative_trait), false)
	negative_trait.add_theme_color_override("font_color", WORKSPACE_CORAL)
	traits.add_child(negative_trait)
	_build_survivor_competency_summary(body, survivor)
	_build_survivor_profession_progress(body, survivor)
	_build_survivor_profession_talent_summary(body, survivor)
	_build_survivor_disease_section(body, survivor)
	var separator := HSeparator.new()
	separator.add_theme_stylebox_override("separator", _panel_style(WORKSPACE_BORDER_SUBTLE, WORKSPACE_BORDER_SUBTLE, 0))
	column.add_child(separator)
	var footer := VBoxContainer.new()
	footer.name = "SurvivorDevelopmentActions"
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)
	var hint := Label.new()
	hint.name = "SurvivorDevelopmentBlocker"
	var development_blocker := _career_progression_system.development_blocker(game_state, survivor, "health")
	if development_blocker.is_empty():
		hint.text = "Aktywny Dom Wspólnoty pozwala wydać punkt na jedno trwałe ulepszenie:"
		hint.add_theme_color_override("font_color", WORKSPACE_MUTED)
	else:
		hint.text = development_blocker
		hint.add_theme_color_override("font_color", WORKSPACE_CORAL)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	footer.add_child(buttons)
	_add_development_button(buttons, survivor, "health", "ZDROWIE +10", "Większy margines na urazy i wychłodzenie.")
	_add_development_button(buttons, survivor, "oxygen", "TLEN +10", "Dłuższa bezpieczna wyprawa.")
	_add_development_button(buttons, survivor, "carry", "UDŹWIG +4 kg", "Więcej zasobów lub bezpieczniejszy powrót.")
	call_deferred("_focus_survivor_modal")


func _build_survivor_competency_summary(content: VBoxContainer, survivor) -> void:
	var heading := Label.new()
	heading.text = "KOMPETENCJE PASYWNE"
	heading.tooltip_text = SurvivorInfoPresenterScript.section_tooltip("competencies")
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", HUD_AMBER_DARK)
	content.add_child(heading)
	var grid := GridContainer.new()
	grid.name = "SurvivorCompetencySummary"
	grid.columns = 3 if _survivor_development_panel.custom_minimum_size.x >= 620.0 else 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	content.add_child(grid)
	for competency_id in CompetencySystemScript.IDS:
		var label := Label.new()
		label.name = "SurvivorCompetency_%s" % competency_id
		label.text = "%s %d/%d" % [
			str(CompetencySystemScript.LABELS[competency_id]),
			CompetencySystemScript.level(survivor, competency_id),
			CompetencySystemScript.MAX_LEVEL,
		]
		label.tooltip_text = CompetencySystemScript.tooltip_text(survivor, competency_id)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", WORKSPACE_TEAL)
		grid.add_child(label)


func _build_survivor_profession_progress(content: VBoxContainer, survivor) -> void:
	var section := VBoxContainer.new()
	section.name = "ProfessionProgressSection"
	section.add_theme_constant_override("separation", 7)
	content.add_child(section)
	var heading := Label.new()
	heading.text = "DOŚWIADCZENIE ZAWODOWE"
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", HUD_AMBER_DARK)
	section.add_child(heading)
	for profession_id in _career_progression_system.get_profession_ids():
		var definition = _career_progression_system.get_profession_definition(profession_id)
		if definition == null:
			continue
		var practice: int = int(survivor.get_job_experience(profession_id))
		var threshold := int(definition.promotion_experience)
		var rank_name := _career_progression_system.get_rank_display_name(survivor, profession_id)
		var line := Label.new()
		line.name = "ProfessionProgress_%s" % profession_id
		line.text = "%s  •  %s  •  %d / %d" % [definition.display_name, rank_name, practice, threshold]
		line.add_theme_font_size_override("font_size", 12)
		line.add_theme_color_override("font_color", WORKSPACE_MUTED)
		section.add_child(line)
		var bar := ProgressBar.new()
		bar.name = "ProfessionProgressBar_%s" % profession_id
		bar.max_value = threshold
		bar.value = mini(practice, threshold)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.add_theme_stylebox_override("background", _panel_style(WORKSPACE_SURFACE, WORKSPACE_BORDER, 1))
		bar.add_theme_stylebox_override("fill", _panel_style(WORKSPACE_TEAL, WORKSPACE_TEAL, 0))
		section.add_child(bar)


func _build_survivor_profession_talent_summary(content: VBoxContainer, survivor) -> void:
	var selected: Array[Dictionary] = []
	for profession_id in [str(survivor.profession), str(survivor.secondary_profession)]:
		if profession_id.is_empty():
			continue
		var talent_id := ProfessionTalentSystemScript.selected_talent_id(survivor, profession_id)
		var talent_definition = _profession_talent_system.get_definition(talent_id)
		if talent_definition == null:
			continue
		var profession_definition = _career_progression_system.get_profession_definition(profession_id)
		selected.append({
			"profession_id": profession_id,
			"profession_name": str(profession_definition.display_name) if profession_definition != null else profession_id.capitalize(),
			"talent": talent_definition,
		})
	if selected.is_empty():
		return

	var section := VBoxContainer.new()
	section.name = "SurvivorProfessionTalentSection"
	section.add_theme_constant_override("separation", 4)
	content.add_child(section)
	var heading := Label.new()
	heading.text = "TALENTY ZAWODOWE"
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", HUD_AMBER_DARK)
	section.add_child(heading)
	for entry in selected:
		var talent = entry.talent
		var label := Label.new()
		label.name = "SurvivorProfessionTalent_%s" % str(entry.profession_id)
		label.text = "%s  •  %s" % [str(entry.profession_name).to_upper(), str(talent.display_name).to_upper()]
		label.tooltip_text = str(talent.description)
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", WORKSPACE_GREEN)
		section.add_child(label)


func _build_survivor_disease_section(content: VBoxContainer, survivor) -> void:
	var disease_views := _disease_presentations_for(survivor)
	if disease_views.is_empty():
		return
	var section := VBoxContainer.new()
	section.name = "DiseaseSection"
	section.add_theme_constant_override("separation", 8)
	content.add_child(section)
	var heading := Label.new()
	heading.text = "CHOROBY I PLAN OPIEKI"
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", HUD_AMBER_DARK)
	section.add_child(heading)
	var isolated: bool = (
		game_state != null
		and game_state.current_day_plan != null
		and str(survivor.id) in game_state.current_day_plan.isolated_survivor_ids
	)
	var prioritized: bool = (
		game_state != null
		and game_state.current_day_plan != null
		and str(survivor.id) in game_state.current_day_plan.medical_priority_survivor_ids
	)
	for view in disease_views:
		var disease_case = _disease_case_for(survivor, str(view.get("disease_id", "")))
		var forecast := _building_effect_system.disease_case_plan_projection(
			game_state,
			str(survivor.id),
			disease_case
		)
		var card := PanelContainer.new()
		card.name = "DiseaseCard_%s" % str(view.get("disease_id", "unknown"))
		card.add_theme_stylebox_override("panel", _panel_style(WORKSPACE_SURFACE_RAISED, WORKSPACE_CORAL, 1))
		section.add_child(card)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_top", 9)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 9)
		card.add_child(margin)
		var card_content := VBoxContainer.new()
		card_content.add_theme_constant_override("separation", 4)
		margin.add_child(card_content)
		var title := Label.new()
		title.name = "DiseaseTitle_%s" % str(view.get("disease_id", "unknown"))
		title.text = "%s  •  %s" % [
			str(view.get("display_name", "Choroba")).to_upper(),
			str(view.get("phase_label", "Nieznany etap")).to_upper(),
		]
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", WORKSPACE_CORAL)
		card_content.add_child(title)
		var effects := Label.new()
		effects.name = "DiseaseEffects_%s" % str(view.get("disease_id", "unknown"))
		effects.text = "Zakaźność: %s  •  Praca: %d%%  •  Nurkowanie: %s" % [
			"TAK" if bool(view.get("contagious", false)) else "NIE",
			int(round(float(view.get("work_multiplier", 0.0)) * 100.0)),
			"DOZWOLONE" if bool(view.get("dive_allowed", false)) else "ZABLOKOWANE",
		]
		effects.add_theme_font_size_override("font_size", 13)
		effects.add_theme_color_override("font_color", WORKSPACE_TEXT)
		card_content.add_child(effects)
		var plan := Label.new()
		plan.name = "DiseasePlan_%s" % str(view.get("disease_id", "unknown"))
		plan.text = "Plan: izolacja %s  •  priorytet terapii %s" % [
			"TAK" if isolated else "NIE",
			"TAK" if prioritized else "NIE",
		]
		plan.add_theme_font_size_override("font_size", 12)
		plan.add_theme_color_override("font_color", WORKSPACE_MUTED)
		card_content.add_child(plan)
		var forecast_label := Label.new()
		forecast_label.name = "DiseaseForecast_%s" % str(view.get("disease_id", "unknown"))
		forecast_label.text = _disease_forecast_text(forecast)
		forecast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		forecast_label.add_theme_font_size_override("font_size", 12)
		forecast_label.add_theme_color_override("font_color", WORKSPACE_MUTED)
		card_content.add_child(forecast_label)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	section.add_child(controls)
	var desired_isolation: bool = not isolated
	var isolation_blocker := _disease_system.isolation_change_blocker(game_state, str(survivor.id), desired_isolation)
	var isolation_button := Button.new()
	isolation_button.name = "IsolationIntentButton_%s" % str(survivor.id)
	isolation_button.text = "Zakończ izolację" if isolated else "Zaplanuj izolację"
	_apply_workspace_secondary_button_style(isolation_button)
	isolation_button.disabled = not isolation_blocker.is_empty()
	isolation_button.tooltip_text = isolation_blocker if not isolation_blocker.is_empty() else (
		"Izolacja zachowuje trwałe przypisanie, ale blokuje pracę i nurkowanie."
	)
	isolation_button.pressed.connect(_on_survivor_isolation_changed.bind(str(survivor.id), desired_isolation))
	controls.add_child(isolation_button)


func _disease_presentations_for(survivor) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if survivor == null:
		return result
	for disease_case in survivor.disease_cases:
		if disease_case == null:
			continue
		var definition = GameDatabase.diseases.get(str(disease_case.disease_id))
		var presentation := _disease_system.case_presentation(disease_case, definition)
		if not presentation.is_empty():
			result.append(presentation)
	return result


func _disease_case_for(survivor, disease_id: String):
	if survivor == null:
		return null
	for disease_case in survivor.disease_cases:
		if disease_case != null and str(disease_case.disease_id) == disease_id:
			return disease_case
	return null


func _disease_forecast_text(forecast: Dictionary) -> String:
	if not bool(forecast.get("valid", false)):
		return "Prognoza końca dnia jest chwilowo niedostępna."
	var source_kind := str(forecast.get("source_kind", "")).strip_edges()
	var source_id := str(forecast.get("source_id", "")).strip_edges()
	var source := source_kind if source_id.is_empty() else "%s / %s" % [source_kind, source_id]
	if source.is_empty():
		source = "nieznane"
	var ration_label := str(forecast.get("ration_id", "none"))
	match ration_label:
		"full":
			ration_label = "pełna"
		"half":
			ration_label = "połowa"
		"none":
			ration_label = "brak"
	var isolation_label := "NIE"
	if bool(forecast.get("formally_isolated", false)):
		isolation_label = "FORMALNA"
	elif bool(forecast.get("emergency_isolated", false)):
		isolation_label = "AWARYJNA"
	elif bool(forecast.get("isolated", false)):
		isolation_label = "TAK"
	var projected_outcome := (
		"USUNIĘCIE PRZYPADKU"
		if bool(forecast.get("projected_case_cleared", false))
		else str(forecast.get("projected_phase_label", "Nieznany etap")).to_upper()
	)
	return "ŹRÓDŁO  •  %s  •  presja bazowa %d\nPRESJA  •  racja %s %+d  •  warunki %+d  •  trudność %+d  •  prognoza %d / próg %d  •  rozliczenie narażenia %s\nKONIEC DNIA  •  %s  •  terapia %s  •  izolacja %s  •  naturalny powrót %s %d/%d  •  zdrowie %+d" % [
		source,
		int(forecast.get("exposure_pressure", 0)),
		ration_label,
		int(forecast.get("ration_pressure_modifier", 0)),
		int(forecast.get("adverse_conditions_pressure", 0)),
		int(forecast.get("difficulty_pressure_modifier", 0)),
		int(forecast.get("projected_pressure", 0)),
		int(forecast.get("infection_threshold", 0)),
		"TAK" if bool(forecast.get("exposure_resolves_today", false)) else "NIE",
		projected_outcome,
		"TAK" if bool(forecast.get("treatment_planned", false)) else "NIE",
		isolation_label,
		"TAK" if bool(forecast.get("natural_recovery_qualified", false)) else "NIE",
		int(forecast.get("natural_recovery_days_after", 0)),
		int(forecast.get("natural_recovery_required", 0)),
		int(forecast.get("projected_health_delta", 0)),
	]


func _on_survivor_isolation_changed(survivor_id: String, desired: bool) -> void:
	if game_state == null:
		return
	var blocker := _disease_system.isolation_change_blocker(game_state, survivor_id, desired)
	if not blocker.is_empty():
		_show_action_feedback(blocker, Color("d18b72"))
		return
	if not _disease_system.set_isolation_intent(game_state, survivor_id, desired):
		return
	var survivor = game_state.find_survivor(survivor_id)
	var display_name := str(survivor.display_name) if survivor != null else survivor_id
	_render()
	if survivor != null and _selected_survivor_id == survivor_id and _survivor_development_panel.visible:
		_populate_survivor_panel(survivor)
	_show_action_feedback(
		"IZOLACJA %s  •  %s" % ["ZAPLANOWANA" if desired else "ZAKOŃCZONA", display_name],
		Color("d5b271")
	)

func _focus_survivor_modal() -> void:
	if _survivor_development_panel == null or not _survivor_development_panel.is_visible_in_tree():
		return
	var controls: Array[Control] = []
	_collect_focusable_controls(_survivor_development_panel, controls)
	if controls.is_empty():
		return
	_configure_focus_loop(controls)
	var close := _survivor_development_panel.find_child("CloseSurvivorDevelopment", true, false) as Control
	(close if close != null else controls[0]).grab_focus()


func _focus_day_plan_popover() -> void:
	if _day_plan_popover == null or not _day_plan_popover.is_visible_in_tree():
		return
	var controls: Array[Control] = []
	_collect_focusable_controls(_day_plan_popover, controls)
	if controls.is_empty():
		return
	_configure_focus_loop(controls)
	var preferred := _ration_picker as Control
	if preferred == null or not preferred.is_visible_in_tree() or (preferred is BaseButton and (preferred as BaseButton).disabled):
		preferred = _day_plan_popover.find_child("CloseDayPlanButton", true, false) as Control
	(preferred if preferred != null else controls[0]).grab_focus()


func _focus_crew_flyout() -> void:
	if _survivors_panel == null or not _survivors_panel.is_visible_in_tree():
		return
	var controls: Array[Control] = []
	_collect_focusable_controls(_survivors_panel, controls)
	if controls.is_empty():
		return
	_configure_focus_loop(controls)
	var preferred: Control = null
	if _survivor_list != null:
		for child in _survivor_list.get_children():
			var candidate := child as Control
			if candidate != null and candidate.is_visible_in_tree() and candidate.focus_mode != Control.FOCUS_NONE and not (candidate is BaseButton and (candidate as BaseButton).disabled):
				preferred = candidate
				break
	if preferred == null:
		preferred = _survivors_panel.find_child("CloseCrewButton", true, false) as Control
	(preferred if preferred != null else controls[0]).grab_focus()


func _refresh_crew_focus_after_render(preferred_control_name: String = "") -> void:
	if _survivors_panel == null or not _survivors_panel.is_visible_in_tree():
		return
	var controls: Array[Control] = []
	_collect_focusable_controls(_survivors_panel, controls)
	_configure_focus_loop(controls)
	if not preferred_control_name.is_empty():
		var preferred := _survivors_panel.find_child(preferred_control_name, true, false) as Control
		if preferred != null and preferred.is_visible_in_tree() and preferred.focus_mode != Control.FOCUS_NONE and not (preferred is BaseButton and (preferred as BaseButton).disabled):
			preferred.grab_focus()
			return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null or not _survivors_panel.is_ancestor_of(focus_owner):
		_focus_crew_flyout()


func _maintain_hud_flyout_focus() -> void:
	var active_panel: Control = null
	if _day_plan_popover != null and _day_plan_popover.is_visible_in_tree():
		active_panel = _day_plan_popover
	elif _survivors_panel != null and _survivors_panel.is_visible_in_tree():
		active_panel = _survivors_panel
	if active_panel == null or _has_visible_child_window(active_panel):
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if (
		focus_owner == _day_plan_button and _day_plan_button.is_pressed()
		or focus_owner == _crew_button and _crew_button.is_pressed()
	):
		return
	if focus_owner != null and active_panel.is_ancestor_of(focus_owner):
		return
	if active_panel == _day_plan_popover:
		_focus_day_plan_popover()
	else:
		_focus_crew_flyout()


func _has_visible_child_window(root: Node) -> bool:
	for child in root.find_children("*", "Window", true, false):
		if child is Window and child.visible:
			return true
	return false

func _collect_focusable_controls(root: Node, result: Array[Control]) -> void:
	for child in root.get_children():
		if child is Control:
			var control := child as Control
			var disabled := control is BaseButton and (control as BaseButton).disabled
			if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and not disabled:
				result.append(control)
		_collect_focusable_controls(child, result)

func _configure_focus_loop(controls: Array[Control]) -> void:
	if controls.is_empty():
		return
	if controls.size() == 1:
		var only := controls[0]
		only.focus_previous = NodePath(".")
		only.focus_next = NodePath(".")
		only.focus_neighbor_left = NodePath(".")
		only.focus_neighbor_top = NodePath(".")
		only.focus_neighbor_right = NodePath(".")
		only.focus_neighbor_bottom = NodePath(".")
		return
	for index in range(controls.size()):
		var control := controls[index]
		var previous := controls[(index - 1 + controls.size()) % controls.size()]
		var next := controls[(index + 1) % controls.size()]
		var previous_path := control.get_path_to(previous)
		var next_path := control.get_path_to(next)
		control.focus_previous = previous_path
		control.focus_next = next_path
		control.focus_neighbor_left = previous_path
		control.focus_neighbor_top = previous_path
		control.focus_neighbor_right = next_path
		control.focus_neighbor_bottom = next_path

func _add_development_button(parent: HBoxContainer, survivor, stat_id: String, title: String, description: String) -> void:
	var button := Button.new()
	button.name = "Develop_%s" % stat_id
	button.text = "%s\n%s" % [title, description]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0, 82)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_workspace_primary_button_style(button)
	var blocker := _survivor_development_blocker(survivor, stat_id)
	button.disabled = not blocker.is_empty()
	button.tooltip_text = blocker if not blocker.is_empty() else "Wydaj jeden punkt rozwoju na trwałe ulepszenie."
	button.pressed.connect(_on_survivor_development_requested.bind(survivor.id, stat_id))
	parent.add_child(button)


func _survivor_development_blocker(survivor, stat_id: String) -> String:
	return _career_progression_system.development_blocker(game_state, survivor, stat_id)

func _on_survivor_development_requested(survivor_id: String, stat_id: String) -> void:
	if game_state == null or not _career_progression_system.spend_development_point(game_state, survivor_id, stat_id):
		return
	var survivor = game_state.find_survivor(survivor_id)
	if survivor == null:
		return
	if _survivor_development_panel.visible and _selected_survivor_id == survivor_id:
		_populate_survivor_panel(survivor)
	_render_survivors()
	_refresh_open_panel()
	var stat_label: String = str({
		"health": "+10 ZDROWIA",
		"oxygen": "+10 TLENU",
		"carry": "+4 KG UDŹWIGU",
	}.get(stat_id, stat_id.to_upper()))
	_show_action_feedback("ROZWÓJ  •  %s  •  %s" % [survivor.display_name, stat_label], Color("f0c86b"))

func _on_career_promotion_requested(survivor_id: String, profession_id: String) -> void:
	if game_state == null or not _career_progression_system.promote_secondary_profession(game_state, survivor_id, profession_id):
		return
	_render_survivors()
	_refresh_open_panel()
	var survivor = game_state.find_survivor(survivor_id)
	_show_action_feedback(
		"NOWA SPECJALIZACJA  •  %s  •  %s" % [survivor.display_name if survivor != null else survivor_id, profession_id.to_upper()],
		Color("f0c86b")
	)


func _on_profession_talent_requested(survivor_id: String, talent_id: String) -> void:
	if game_state == null or not _career_progression_system.select_profession_talent(game_state, survivor_id, talent_id):
		return
	_render_survivors()
	_refresh_open_panel()
	var survivor = game_state.find_survivor(survivor_id)
	var definition = _profession_talent_system.get_definition(talent_id)
	_show_action_feedback(
		"NOWY TALENT  •  %s  •  %s" % [
			survivor.display_name if survivor != null else survivor_id,
			str(definition.display_name).to_upper() if definition != null else talent_id.to_upper(),
		],
		Color("f0c86b")
	)

func _slot_tooltip_text(slot_id: String) -> String:
	if game_state == null or game_state.platform == null:
		return "Zrujnowany szkielet budynku"
	var slot_data: Dictionary = game_state.platform.slot_states.get(slot_id, {})
	var definition = GameDatabase.buildings.get(str(slot_data.get("definition_id", "")))
	if definition == null:
		return "Zrujnowany szkielet budynku"
	var building = _building_system.get_building_for_slot(game_state, slot_id)
	if building == null:
		return "%s\nZrujnowany • gotowy do odbudowy" % definition.display_name
	if not building.is_built:
		return "%s\nOdbudowa zaplanowana" % definition.display_name
	if building.pending_level > building.level:
		return "%s\nPoziom %d • rozbudowa w toku" % [definition.display_name, building.level]
	if building.condition <= 0:
		return "%s\nPoziom %d • budynek nieaktywny" % [definition.display_name, building.level]
	return "%s\nPoziom %d • aktywny" % [definition.display_name, building.level]

func _assignment_label(survivor) -> String:
	if survivor.current_assignment.is_empty():
		return "dostępny"
	var building = game_state.find_building(survivor.current_assignment)
	if building == null:
		return "przydzielony"
	var definition = GameDatabase.buildings.get(building.definition_id)
	return definition.display_name if definition != null else "przydzielony"

func _apply_normalized_rect(control: Control, rect: Rect2) -> void:
	control.anchor_left = rect.position.x
	control.anchor_top = rect.position.y
	control.anchor_right = rect.end.x
	control.anchor_bottom = rect.end.y
	control.offset_left = 0
	control.offset_top = 0
	control.offset_right = 0
	control.offset_bottom = 0


func _building_navigation_rail_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(HUD_BASE, 0.98)
	style.border_color = HUD_BORDER
	style.set_border_width_all(2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 4)
	return style


func _building_navigation_button_style(selected: bool, hovered: bool, focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = HUD_RAISED if selected else HUD_RAISED_HOVER if hovered else Color("0b3940")
	style.border_color = HUD_AMBER if selected else HUD_TEAL if focused else HUD_BORDER
	style.set_border_width_all(3 if selected or focused else 1)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 5
	style.content_margin_top = 5
	style.content_margin_right = 5
	style.content_margin_bottom = 5
	return style

func _panel_style(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style

func _button_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := _panel_style(fill, border, width)
	style.content_margin_left = 16
	style.content_margin_right = 16
	return style


func _hud_button_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := _panel_style(fill, border, width)
	style.content_margin_left = 9
	style.content_margin_right = 9
	return style


func _apply_workspace_secondary_button_style(button: Button) -> void:
	button.add_theme_color_override("font_color", WORKSPACE_TEXT)
	button.add_theme_color_override("font_hover_color", WORKSPACE_TEXT)
	button.add_theme_color_override("font_pressed_color", WORKSPACE_TEXT)
	button.add_theme_color_override("font_focus_color", WORKSPACE_TEXT)
	button.add_theme_color_override("font_disabled_color", WORKSPACE_DISABLED)
	button.add_theme_stylebox_override("normal", _button_style(WORKSPACE_SURFACE_RAISED, WORKSPACE_TEAL, 1))
	button.add_theme_stylebox_override("hover", _button_style(WORKSPACE_BASE, WORKSPACE_TEAL_HOVER, 2))
	button.add_theme_stylebox_override("pressed", _button_style(WORKSPACE_SURFACE, HUD_AMBER_DARK, 2))
	button.add_theme_stylebox_override("focus", _button_style(WORKSPACE_BASE, WORKSPACE_TEAL_HOVER, 2))
	button.add_theme_stylebox_override("disabled", _button_style(WORKSPACE_DISABLED_SURFACE, WORKSPACE_BORDER_SUBTLE, 1))


func _apply_workspace_primary_button_style(button: Button) -> void:
	button.add_theme_color_override("font_color", HUD_DARK_TEXT)
	button.add_theme_color_override("font_hover_color", HUD_DARK_TEXT)
	button.add_theme_color_override("font_pressed_color", HUD_DARK_TEXT)
	button.add_theme_color_override("font_focus_color", HUD_DARK_TEXT)
	button.add_theme_color_override("font_disabled_color", WORKSPACE_DISABLED)
	button.add_theme_stylebox_override("normal", _button_style(HUD_AMBER, HUD_AMBER_DARK, 1))
	button.add_theme_stylebox_override("hover", _button_style(HUD_AMBER_HOVER, HUD_AMBER_DARK, 2))
	button.add_theme_stylebox_override("pressed", _button_style(HUD_AMBER_PRESSED, HUD_AMBER_DARK, 2))
	button.add_theme_stylebox_override("focus", _button_style(HUD_AMBER_HOVER, WORKSPACE_TEAL_HOVER, 2))
	button.add_theme_stylebox_override("disabled", _button_style(WORKSPACE_DISABLED_SURFACE, WORKSPACE_BORDER_SUBTLE, 1))
