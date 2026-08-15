extends Node2D

const DiveSessionStateScript := preload("res://scripts/data/DiveSessionState.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const NarrativeContentScript := preload("res://scripts/ui/NarrativeContent.gd")
const TutorialDirectorScript := preload("res://scripts/core/TutorialDirector.gd")
const DiveInteractionRulesScript := preload("res://scripts/diving/DiveInteractionRules.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const OxygenSystemScript := preload("res://scripts/diving/OxygenSystem.gd")
const LootSystemScript := preload("res://scripts/diving/LootSystem.gd")
const LightSystemScript := preload("res://scripts/diving/LightSystem.gd")
const SuitSystemScript := preload("res://scripts/diving/SuitSystem.gd")
const DiveRiskRuntimeScript := preload("res://scripts/diving/DiveRiskRuntime.gd")
const DiveScoutRuntimeScript := preload("res://scripts/diving/DiveScoutRuntime.gd")
const DiveCombatSystemScript := preload("res://scripts/diving/DiveCombatSystem.gd")
const DiveCurrentVisualScript := preload("res://scripts/diving/DiveCurrentVisual.gd")
const UnderwaterEnvironmentScript := preload("res://scripts/diving/UnderwaterEnvironment2D.gd")
const DiveHudDockScript := preload("res://scripts/diving/DiveHudDock.gd")
const TutorialDirectionIndicatorScript := preload("res://scripts/diving/TutorialDirectionIndicator.gd")
const DiveLootPanelScript := preload("res://scripts/diving/DiveLootPanel.gd")
const DiveInventoryPanelScript := preload("res://scripts/diving/DiveInventoryPanel.gd")
const ContainerScript := preload("res://scripts/diving/DiveLootContainer.gd")
const DiseaseHazardContainerScript := preload("res://scripts/diving/DiveDiseaseHazardContainer.gd")
const WorldPickupScript := preload("res://scripts/diving/DiveWorldPickup.gd")
const ExitLineScript := preload("res://scripts/diving/DiveExitLine.gd")
const LostBackpackScript := preload("res://scripts/diving/DiveLostBackpack.gd")
const DroppedLootScript := preload("res://scripts/diving/DiveDroppedLoot.gd")
const PersistentInteractableScript := preload("res://scripts/diving/DivePersistentInteractable.gd")
const SectorPersistenceSystemScript := preload("res://scripts/diving/SectorPersistenceSystem.gd")
const RescueSystemScript := preload("res://scripts/diving/RescueSystem.gd")
const RescueSurvivorScript := preload("res://scripts/diving/DiveRescueSurvivor.gd")
const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")
const ProfessionTalentSystemScript := preload("res://scripts/base/ProfessionTalentSystem.gd")

const INTERACTION_DISTANCE := DiveInteractionRulesScript.INTERACTION_DISTANCE
const MOVEMENT_TUTORIAL_DISTANCE := 180.0
const STATIONARY_VELOCITY_EPSILON_SQUARED := 1.0
const TUTORIAL_CABLE_BLOCKAGE_ID := "SC-01"
const TUTORIAL_CABLE_BLOCKAGE_SEEN_DISTANCE := 200.0

@onready var dive_map: ContinuousDiveWorld = $World
@onready var diver: DiverController = $Diver
@onready var ambient_darkness: CanvasModulate = $UnderwaterDarkness
@onready var diver_light: PointLight2D = $Diver/DiveLight

var game_root: Node
var game_state
var setup
var session

var _oxygen_system = OxygenSystemScript.new()
var _loot_system = LootSystemScript.new()
var _light_system = LightSystemScript.new()
var _risk_runtime = DiveRiskRuntimeScript.new()
var _scout_runtime = DiveScoutRuntimeScript.new()
var _profession_talent_system = ProfessionTalentSystemScript.new()
var _combat_system = DiveCombatSystemScript.new()
var _persistence_system = SectorPersistenceSystemScript.new()
var _rescue_system = RescueSystemScript.new()
var _tutorial_director = TutorialDirectorScript.new()
var _equipped_light_definition
var _dive_lighting_definition
var _current_visual
var _underwater_environment: UnderwaterEnvironment2D
var _active_current_vector := Vector2.ZERO
var _current_visual_sample_override := false
var _travelled_distance: float = 0.0
var _tutorial_step_time: float = 0.0
var _interaction_target
var _interaction_progress: float = 0.0
var _quiet_repair_progress: float = 0.0
var _quiet_repair_blocked_until_release: bool = false
var _scout_signal: Dictionary = {}
var _pending_container: DiveLootContainer
var _pending_container_changed: bool = false
var _pending_disease_hazard: DiveDiseaseHazardContainer
var _pending_rescue: DiveRescueSurvivor
var _towed_rescue_node: DiveRescueSurvivor
var _attempt_failed: bool = false
var _ending: bool = false
var _status_message: String = ""
var _status_message_time: float = 0.0
var _risk_warning: String = ""
var _discovered_landmarks_this_dive: Array[String] = []
var _graphics_quality := "high"
var _reduced_motion := false

var _oxygen_bar: ProgressBar
var _oxygen_label: Label
var _oxygen_fill_style: StyleBoxFlat
var _health_bar: ProgressBar
var _health_label: Label
var _health_fill_style: StyleBoxFlat
var _diver_name_label: Label
var _diver_meta_label: Label
var _experience_label: Label
var _portrait: DiverHudPortrait
var _suit_label: Label
var _time_label: Label
var _light_label: Label
var _inventory_summary_label: Label
var _hud_dock: DiveHudDock
var _navigation_panel: PanelContainer
var _return_label: Label
var _depth_label: Label
var _objective_label: Label
var _tutorial_panel: PanelContainer
var _tutorial_title: Label
var _tutorial_body: Label
var _tutorial_direction_indicator: Control
var _inventory_slots: Array[PanelContainer] = []
var _inventory_labels: Array[Label] = []
var _interaction_panel: PanelContainer
var _interaction_label: Label
var _interaction_bar: ProgressBar
var _warning_label: Label
var _current_label: Label
var _scout_label: Label
var _combat_label: Label
var _loot_panel
var _inventory_panel
var _disease_hazard_overlay: ColorRect
var _disease_hazard_title: Label
var _disease_hazard_body: Label
var _accept_disease_hazard_button: Button
var _decline_disease_hazard_button: Button
var _rescue_overlay: ColorRect
var _rescue_title: Label
var _rescue_body: Label
var _stabilize_rescue_button: Button
var _tow_rescue_button: Button
var _leave_rescue_button: Button
var _failure_overlay: ColorRect
var _failure_title: Label
var _failure_body: Label
var _failure_retry_button: Button
var _pending_finish_result

func bind(root: Node, state) -> void:
	game_root = root
	game_state = state
	setup = state.current_expedition_setup if state != null else null
	if setup == null:
		return
	session = DiveSessionStateScript.new()
	session.begin(setup)
	_configure_lighting()
	dive_map.configure(state.underwater_world if state != null else null, setup.start_entry_point, setup)
	_configure_underwater_environment()
	_start_attempt(false)


func supports_pause_menu() -> bool:
	return true


func has_cancelable_overlay_open() -> bool:
	return (
		(_loot_panel != null and _loot_panel.visible)
		or (_inventory_panel != null and _inventory_panel.visible)
		or (_disease_hazard_overlay != null and _disease_hazard_overlay.visible)
	)


func set_graphics_quality(quality_id: String) -> void:
	_graphics_quality = quality_id if quality_id in ["low", "medium", "high"] else "high"
	var visual_effects := diver.get_node_or_null("VisualEffects") if diver != null else null
	if visual_effects != null and visual_effects.has_method("set_graphics_quality"):
		visual_effects.set_graphics_quality(_graphics_quality)
	if _underwater_environment != null:
		_underwater_environment.set_graphics_quality(_graphics_quality)
	if dive_map != null and dive_map.has_method("set_graphics_quality"):
		dive_map.set_graphics_quality(_graphics_quality)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if diver != null and diver.has_method("set_reduced_motion"):
		diver.set_reduced_motion(enabled)
	var visual_effects := diver.get_node_or_null("VisualEffects") if diver != null else null
	if visual_effects != null and visual_effects.has_method("set_reduced_motion"):
		visual_effects.set_reduced_motion(enabled)
	if _underwater_environment != null:
		_underwater_environment.set_reduced_motion(enabled)
	if dive_map != null and dive_map.has_method("set_reduced_motion"):
		dive_map.set_reduced_motion(enabled)
	if _current_visual != null and _current_visual.has_method("set_reduced_motion"):
		_current_visual.set_reduced_motion(enabled)


func seed_user_settings_before_ready(quality_id: String, reduced_motion: bool) -> void:
	_graphics_quality = quality_id if quality_id in ["low", "medium", "high"] else "high"
	_reduced_motion = reduced_motion
	var seeded_diver := get_node_or_null("Diver") as DiverController
	if seeded_diver == null:
		return
	seeded_diver.set_reduced_motion(_reduced_motion)
	var visual_effects := seeded_diver.get_node_or_null("VisualEffects")
	if visual_effects != null:
		if visual_effects.has_method("set_graphics_quality"):
			visual_effects.set_graphics_quality(_graphics_quality)
		if visual_effects.has_method("set_reduced_motion"):
			visual_effects.set_reduced_motion(_reduced_motion)

func _ready() -> void:
	diver.input_enabled = false
	diver.distance_travelled.connect(_on_distance_travelled)
	_build_current_visual()
	_build_underwater_environment()
	_build_ui()
	set_graphics_quality(_graphics_quality)
	set_reduced_motion(_reduced_motion)


func _unhandled_input(event: InputEvent) -> void:
	if (
		_disease_hazard_overlay != null
		and _disease_hazard_overlay.visible
		and event.is_action_pressed(&"ui_cancel")
	):
		_decline_pending_disease_hazard()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if setup == null or session == null:
		return
	if _ending:
		_sync_diver_visual_context(true)
		return
	dive_map.update_streaming(diver.global_position, false, _streaming_visible_half_extent())
	_update_current_presentation(delta)
	_update_environment_lighting(delta)
	if Input.is_action_just_pressed("dive_inventory"):
		if _inventory_panel.visible:
			_close_inventory()
		elif not _attempt_failed and not _loot_panel.visible and not _rescue_overlay.visible and not _disease_hazard_overlay.visible:
			_open_inventory()
	if _attempt_failed or _loot_panel.visible or _inventory_panel.visible or _rescue_overlay.visible or _disease_hazard_overlay.visible:
		diver.input_enabled = false
		diver.current_velocity = Vector2.ZERO
		diver.velocity = Vector2.ZERO
		_cancel_talent_actions()
		_sync_diver_visual_context(true)
		_update_ui()
		return

	diver.input_enabled = true
	session.elapsed_time += delta
	_tutorial_step_time += delta
	if _status_message_time > 0.0:
		_status_message_time = maxf(_status_message_time - delta, 0.0)
	_update_quiet_repair(delta)
	if Input.is_action_just_pressed(&"dive_repair", true):
		_attempt_suit_repair()
	if Input.is_action_just_pressed("dive_light_toggle"):
		_toggle_diver_light()
	_combat_system.advance_cooldown(session, delta)
	_handle_combat_input()

	var current := _active_current_vector
	diver.current_velocity = current
	var landmark_id: String = dive_map.landmark_id_at(diver.global_position)
	if not landmark_id.is_empty() and not _discovered_landmarks_this_dive.has(landmark_id):
		_discovered_landmarks_this_dive.append(landmark_id)
	var is_moving := diver.movement_input.length_squared() > 0.01
	var rate := _oxygen_system.consumption_rate(
		is_moving,
		diver.is_sprinting,
		session.carry_ratio(),
		current.length_squared() > 0.01,
		CompetencySystem.load_oxygen_surcharge_multiplier(setup)
	)
	var rescue_definition = _active_rescue_definition()
	var rescue_oxygen_multiplier := _rescue_system.oxygen_multiplier(session, rescue_definition)
	session.oxygen_left = _oxygen_system.consume(session.oxygen_left, delta, rate * _difficulty_modifier("oxygen_use_multiplier") * rescue_oxygen_multiplier * CompetencySystem.oxygen_use_multiplier(setup))
	if session.oxygen_left <= 0.0:
		_update_ui()
		_on_oxygen_depleted()
		return

	var risk_update: Dictionary = _risk_runtime.advance(
		session,
		setup,
		dive_map.threats,
		diver.global_position,
		dive_map.depth_at(diver.global_position),
		diver.is_sprinting,
		delta,
		_is_diver_light_active()
	)
	diver.movement_speed_multiplier = float(risk_update.get("movement_multiplier", 1.0)) * _rescue_system.movement_multiplier(session, rescue_definition) * CompetencySystem.swimming_multiplier(setup)
	_risk_warning = str(risk_update.get("warning", ""))
	for message in risk_update.get("messages", []):
		_show_status(str(message), 3.2)
	var confirmed_hits: Array = risk_update.get("messages", [])
	if not confirmed_hits.is_empty():
		diver.play_visual_cue(&"hit", diver.global_position, minf(1.0 + float(confirmed_hits.size() - 1) * 0.18, 1.5))
	_sync_diver_visual_context()
	var risk_death_reason := str(risk_update.get("death_reason", ""))
	if not risk_death_reason.is_empty():
		_update_ui()
		_finish_death(risk_death_reason)
		return

	_update_tutorial_progress()
	_update_interaction(delta)
	_sync_diver_visual_context()
	_update_scout(delta)
	if _ending or not is_inside_tree():
		return
	_update_ui()

func _start_attempt(is_retry: bool) -> void:
	if is_retry:
		session.reset_attempt()
		dive_map.reset_attempt()
	_attempt_failed = false
	_ending = false
	_travelled_distance = 0.0
	_tutorial_step_time = 0.0
	_interaction_target = null
	_interaction_progress = 0.0
	_quiet_repair_progress = 0.0
	_quiet_repair_blocked_until_release = false
	_scout_runtime.reset()
	_scout_signal.clear()
	_pending_container = null
	_pending_container_changed = false
	_pending_disease_hazard = null
	if _disease_hazard_overlay != null:
		_disease_hazard_overlay.visible = false
	_pending_rescue = null
	_towed_rescue_node = null
	_status_message = ""
	_status_message_time = 0.0
	_risk_warning = ""
	_discovered_landmarks_this_dive.clear()
	_risk_runtime.reset(dive_map.threats)
	var starting_landmark: String = dive_map.landmark_id_at(dive_map.start_position())
	if not starting_landmark.is_empty():
		_discovered_landmarks_this_dive.append(starting_landmark)
	diver.reset_at(dive_map.start_position())
	var camera := diver.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.limit_right = int(dive_map.world_size().x)
		camera.limit_bottom = int(dive_map.world_size().y)
		camera.reset_smoothing()
	dive_map.update_streaming(dive_map.start_position(), true, _streaming_visible_half_extent())
	_update_current_presentation(0.0, true)
	_apply_diver_light_state()
	_update_environment_lighting(0.0)
	diver.input_enabled = true
	_pending_finish_result = null
	_failure_overlay.visible = false
	if _failure_title != null:
		_failure_title.text = "BRAK TLENU"
	if _failure_retry_button != null:
		_failure_retry_button.text = "Spróbuj ponownie"
	_loot_panel.dismiss()
	_inventory_panel.dismiss()
	_rescue_overlay.visible = false
	if setup.tutorial_mode:
		_tutorial_event(TutorialDirectorScript.DIVE_STARTED)
	_sync_diver_visual_context()
	_update_ui()

func _on_distance_travelled(distance: float) -> void:
	if not _attempt_failed and not _ending:
		_travelled_distance += distance

func _handle_combat_input() -> void:
	if Input.is_action_just_pressed("dive_weapon_knife"):
		if _combat_system.select_weapon(session, setup, "knife"):
			_show_status("Wybrano Nóż ratowniczy.", 1.4)
	if Input.is_action_just_pressed("dive_weapon_ranged"):
		if _combat_system.select_weapon(session, setup, "harpoon_pistol"):
			_show_status("Wybrano Pistolet harpunowy.", 1.4)
		else:
			_show_status("Pistolet harpunowy nie jest wyposażony.", 1.8)
	if not Input.is_action_just_pressed("dive_attack"):
		return
	if _rescue_system.is_towing(session):
		_show_status("Nie można atakować podczas holowania.", 1.8)
		return
	var weapon_definition = GameDatabase.diving_gear.get("harpoon_pistol") if GameDatabase != null else null
	var attack: Dictionary = _combat_system.try_attack(
		session,
		setup,
		diver.global_position,
		get_global_mouse_position(),
		dive_map.threats,
		weapon_definition
	)
	if not bool(attack.get("success", false)):
		var failure_message := str(attack.get("message", ""))
		if not failure_message.is_empty():
			_show_status(failure_message, 1.6)
		return
	_risk_runtime.emit_action_noise(session, setup, str(attack.get("noise_action", "")), diver.global_position)
	var attack_end: Vector2 = attack.get("end_position", diver.global_position)
	var weapon_id := str(session.selected_combat_tool)
	diver.play_visual_cue(&"harpoon_attack" if weapon_id == "harpoon_pistol" else &"knife_attack", attack_end)
	_show_attack_trace(diver.visual_socket_global(&"tool_hand"), attack_end, weapon_id)
	var message := str(attack.get("message", ""))
	if not message.is_empty():
		_show_status(message, 2.0)

func _show_attack_trace(origin: Vector2, end_position: Vector2, weapon_id: String) -> void:
	var trace := Line2D.new()
	trace.name = "CombatTrace"
	trace.width = 4.0 if weapon_id == "harpoon_pistol" else 7.0
	trace.default_color = Color("d8c17a") if weapon_id == "harpoon_pistol" else Color("b9e6df")
	trace.points = PackedVector2Array([origin, end_position])
	trace.z_index = 20
	add_child(trace)
	var tween := trace.create_tween()
	tween.tween_property(trace, "modulate:a", 0.0, 0.14)
	tween.tween_callback(trace.queue_free)

func _update_tutorial_progress() -> void:
	if not setup.tutorial_mode or session == null:
		return
	var step := tutorial_step()
	if step == TutorialStateScript.Step.DIVE_MOVEMENT and _travelled_distance >= MOVEMENT_TUTORIAL_DISTANCE:
		_tutorial_event(TutorialDirectorScript.MOVEMENT_COMPLETED)
	elif step == TutorialStateScript.Step.DIVE_OXYGEN and _tutorial_step_time >= 4.0:
		_tutorial_event(TutorialDirectorScript.OXYGEN_EXPLAINED)
	elif step == TutorialStateScript.Step.DIVE_BLOCKED_PASSAGE:
		var blockage: DivePersistentInteractable = _tutorial_cable_blockage()
		if blockage != null and diver.global_position.distance_to(blockage.global_position) < TUTORIAL_CABLE_BLOCKAGE_SEEN_DISTANCE:
			_tutorial_event(TutorialDirectorScript.BLOCKED_PASSAGE_SEEN)
	_reconcile_tutorial_dive_progress()

func _reconcile_tutorial_dive_progress() -> void:
	if setup == null or not setup.tutorial_mode or session == null:
		return
	while true:
		var step_before := tutorial_step()
		if (
			step_before == TutorialStateScript.Step.DIVE_OPEN_CONTAINER
			and session.tutorial_opened_mandatory_orders.has(0)
		):
			_tutorial_event(TutorialDirectorScript.MANDATORY_CONTAINER_OPENED)
		elif step_before == TutorialStateScript.Step.DIVE_INVENTORY and _has_required_tutorial_loot():
			_tutorial_event(TutorialDirectorScript.MANDATORY_LOOT_COMPLETED)
		else:
			return
		if tutorial_step() == step_before:
			return

func tutorial_step() -> int:
	return session.current_tutorial_step() if session != null else -1


func _tutorial_event(event_id: String) -> bool:
	if session == null or not session.record_tutorial_event(_tutorial_director, event_id):
		return false
	_tutorial_step_time = 0.0
	return true

func _difficulty_modifier(modifier_id: String, fallback: float = 1.0) -> float:
	if setup == null:
		return fallback
	return maxf(float(setup.difficulty_modifiers.get(modifier_id, fallback)), 0.0)

func _update_interaction(delta: float) -> void:
	var nearest = dive_map.get_nearest_interactable(diver.global_position, INTERACTION_DISTANCE)
	if _rescue_system.is_towing(session):
		nearest = dive_map.exit_line if diver.global_position.distance_to(dive_map.exit_line.global_position) <= INTERACTION_DISTANCE else null
	if nearest != _interaction_target:
		_interaction_target = nearest
		_interaction_progress = 0.0
	if _interaction_target == null:
		return
	if _interaction_target is DiveWorldPickup:
		if Input.is_action_just_pressed("dive_interact"):
			var completed_target = _interaction_target
			_interaction_target = null
			_interaction_progress = 0.0
			_complete_interaction(completed_target)
		return

	if Input.is_action_pressed("dive_interact"):
		var required_tool := _required_tool_for(_interaction_target)
		if not required_tool.is_empty() and not session.has_tool(required_tool):
			_interaction_progress = 0.0
			_show_status("Brak narzędzia: %s." % _required_tool_display_name(_interaction_target, required_tool), 1.0)
			return
		_interaction_progress += delta * _risk_runtime.interaction_speed_multiplier(session, setup)
		var required := float(_interaction_target.interaction_seconds)
		if _interaction_progress >= required:
			var completed_target = _interaction_target
			_interaction_target = null
			_interaction_progress = 0.0
			_complete_interaction(completed_target)
	else:
		_interaction_progress = 0.0

func _complete_interaction(target) -> void:
	if target is DiveWorldPickup:
		_collect_world_pickup(target)
	elif target is DiveLootContainer:
		_open_container(target)
	elif target is DivePersistentInteractable:
		_complete_persistent_interaction(target)
	elif target is DiveRescueSurvivor:
		_complete_rescue_interaction(target)
	elif target is DiveExitLine:
		_try_return_to_surface()

func _collect_world_pickup(pickup: DiveWorldPickup) -> void:
	if pickup == null or pickup.collected:
		return
	if not _loot_system.transfer_single(session, pickup.resource_id):
		_show_status("Brak wolnego udźwigu lub slotu. %s pozostaje w wodzie." % pickup.display_name, 2.8)
		return
	if not session.collected_world_item_ids.has(pickup.pickup_id):
		session.collected_world_item_ids.append(pickup.pickup_id)
	pickup.mark_collected()
	diver.play_visual_cue(&"interaction", pickup.global_position, 0.72)
	_show_status("Zebrano: +1 %s (%.1f kg)." % [pickup.display_name, session.get_unit_weight(pickup.resource_id)], 2.2)
	_update_ui()

func _complete_rescue_interaction(target: DiveRescueSurvivor) -> void:
	if target.stage == DiveRescueSurvivor.Stage.TRAPPED:
		_risk_runtime.emit_action_noise(session, setup, target.interaction_action, diver.global_position)
		target.mark_freed()
		diver.play_visual_cue(&"interaction", target.global_position)
	_pending_rescue = target
	_show_rescue_overlay(target)

func _show_rescue_overlay(target: DiveRescueSurvivor) -> void:
	if target == null or target.definition == null:
		return
	var definition = target.definition
	_rescue_title.text = "%s  •  %s" % [str(definition.display_name).to_upper(), str(definition.profession).to_upper()]
	_rescue_body.text = "%s\n\nMożesz zużyć %d x %s, aby ustabilizować rannego. Stabilizacja ogranicza spowolnienie i dodatkowe zużycie tlenu. Bez niej stan ocalałego będzie krytyczny. Podczas holowania możesz użyć tylko liny powrotnej." % [
		str(definition.biography),
		int(definition.stabilization_medicine_cost),
		ResourceIdsScript.display_name(ResourceIdsScript.MEDS_CHEMICALS),
	]
	var has_medicine := _rescue_system.can_stabilize(session, definition)
	_stabilize_rescue_button.disabled = not has_medicine
	_stabilize_rescue_button.text = "Użyj %d leku i holuj" % int(definition.stabilization_medicine_cost)
	_tow_rescue_button.text = "Holuj bez stabilizacji"
	_rescue_overlay.visible = true
	if has_medicine:
		_stabilize_rescue_button.grab_focus()
	else:
		_tow_rescue_button.grab_focus()

func _begin_pending_rescue(stabilized: bool) -> void:
	if _pending_rescue == null:
		return
	var result: Dictionary = _rescue_system.begin_tow(session, _pending_rescue, stabilized)
	if not bool(result.get("success", false)):
		_show_status(str(result.get("message", "Nie udało się rozpocząć holowania.")), 2.5)
		return
	_towed_rescue_node = _pending_rescue
	_rescue_system.attach_tow_target(_towed_rescue_node, diver)
	_pending_rescue = null
	_rescue_overlay.visible = false
	diver.input_enabled = true
	_sync_diver_visual_context()
	diver.play_visual_cue(&"interaction", _towed_rescue_node.global_position if _towed_rescue_node != null else diver.global_position)
	_show_status(str(result.get("message", "Rozpoczęto holowanie.")), 4.0)
	_update_ui()

func _leave_pending_rescue() -> void:
	_pending_rescue = null
	_rescue_overlay.visible = false
	diver.input_enabled = true
	_show_status("Ocalały czeka. Możesz wrócić z lekami albo podjąć ryzykowne holowanie.", 3.0)
	_update_ui()

func _complete_persistent_interaction(target: DivePersistentInteractable) -> void:
	if (
		setup != null
		and setup.tutorial_mode
		and target.kind == DivePersistentInteractable.Kind.FIXED_DEVICE
		and target.persistent_id == "junction_j7"
		and not _tutorial_cable_blockage_opened()
	):
		_show_status("Najpierw przetnij blokadę kabla Nożem ratunkowym.", 3.0)
		return
	match target.kind:
		DivePersistentInteractable.Kind.BUOY:
			if session.buoy_charges <= 0:
				_show_status("Brak kolejnej boi na tej wyprawie.", 2.0)
				return
			session.buoy_charges -= 1
			if not session.placed_buoys.has(target.persistent_id):
				session.placed_buoys.append(target.persistent_id)
			_show_status("Boja %s ustawiona. Zostanie zapisana po zakończeniu wyprawy." % target.persistent_id, 3.0)
		DivePersistentInteractable.Kind.SHORTCUT:
			if not session.opened_shortcuts.has(target.persistent_id):
				session.opened_shortcuts.append(target.persistent_id)
			if target.persistent_id == TUTORIAL_CABLE_BLOCKAGE_ID:
				_show_status("Blokada kabla przecięta. Podążaj dalej do Węzła J-7.", 3.0)
			else:
				_show_status("Skrót %s otwarty." % target.persistent_id, 2.5)
		DivePersistentInteractable.Kind.HEAVY_OBJECT:
			if not session.marked_heavy_objects.has(target.persistent_id):
				session.marked_heavy_objects.append(target.persistent_id)
			_show_status("Obiekt oznaczony. Obsadzony Warsztat III może go wydobyć po powrocie.", 3.2)
		DivePersistentInteractable.Kind.FIXED_DEVICE:
			if not session.activated_fixed_devices.has(target.persistent_id):
				session.activated_fixed_devices.append(target.persistent_id)
			if setup.tutorial_mode and target.persistent_id == "junction_j7":
				_tutorial_event(TutorialDirectorScript.JUNCTION_J7_ACTIVATED)
			if target.persistent_id == "archive_terminal":
				_show_status("Terminal Archiwum działa. Mapa Wspólnej Linii zostanie przesłana do Przystani po bezpiecznym powrocie.", 4.2)
			else:
				_show_status("Urządzenie %s uruchomione. Zmiana zostanie zachowana po nurkowaniu." % target.display_name, 3.2)
	_risk_runtime.emit_action_noise(session, setup, target.interaction_action, diver.global_position)
	target.mark_completed()
	diver.play_visual_cue(&"interaction", target.global_position)

func _open_container(container: DiveLootContainer) -> void:
	if (
		container != null
		and container.get_script() == DiseaseHazardContainerScript
		and not setup.tutorial_mode
		and (container as DiveDiseaseHazardContainer).has_pending_hazard_decision()
	):
		_present_disease_hazard(container as DiveDiseaseHazardContainer)
		return
	_open_container_loot(container)


func _open_container_loot(container: DiveLootContainer) -> void:
	_risk_runtime.emit_action_noise(session, setup, container.interaction_action, diver.global_position)
	diver.input_enabled = false
	diver.current_velocity = Vector2.ZERO
	diver.velocity = Vector2.ZERO
	container.set_opened(true)
	diver.play_visual_cue(&"interaction", container.global_position, 0.86)
	_pending_container = container
	_pending_container_changed = false
	_show_loot_overlay(container)
	if setup.tutorial_mode and container.mandatory_order >= 0:
		session.record_tutorial_container_opened(container.mandatory_order)
		_reconcile_tutorial_dive_progress()


func _present_disease_hazard(container: DiveDiseaseHazardContainer) -> void:
	if container == null or _disease_hazard_overlay == null:
		return
	_pending_disease_hazard = container
	diver.input_enabled = false
	diver.current_velocity = Vector2.ZERO
	diver.velocity = Vector2.ZERO
	var disease_definition = GameDatabase.diseases.get(container.disease_id) if GameDatabase != null else null
	var disease_name := (
		str(disease_definition.display_name)
		if disease_definition != null
		else container.disease_id.replace("_", " ").capitalize()
	)
	var infection_threshold := int(disease_definition.infection_threshold) if disease_definition != null else 0
	var medicine_reward := int(container.initial_contents.get(ResourceIdsScript.MEDS_CHEMICALS, 0))
	_disease_hazard_title.text = "SKAŻONE ZAPLECZE  •  %s" % disease_name.to_upper()
	_disease_hazard_body.text = (
		"Zabezpieczenia magazynu puściły. Otwarcie pozwoli zabrać %d × %s, ale %s otrzyma "
		+ "typowane narażenie o presji +%d. Próg zachorowania wynosi %d; ostateczny wynik "
		+ "zostanie rozliczony dopiero po powrocie. Odmowa nie otworzy magazynu i niczego nie zmieni."
	) % [
		medicine_reward,
		_item_display_name(ResourceIdsScript.MEDS_CHEMICALS),
		_diver_display_name(),
		container.exposure_pressure,
		infection_threshold,
	]
	_accept_disease_hazard_button.text = "Podejmij ryzyko  •  +%d presji" % container.exposure_pressure
	_disease_hazard_overlay.visible = true
	_decline_disease_hazard_button.call_deferred("grab_focus")


func _accept_pending_disease_hazard() -> void:
	if _pending_disease_hazard == null or session == null or setup == null:
		return
	var container := _pending_disease_hazard
	var exposure := container.accept_exposure(str(setup.diver_id), maxi(int(setup.day), 1))
	if exposure == null or not session.add_disease_exposure(exposure):
		_show_status("Nie udało się utworzyć poprawnego narażenia. Magazyn pozostaje zamknięty.", 3.0)
		return
	_pending_disease_hazard = null
	_disease_hazard_overlay.visible = false
	_open_container_loot(container)


func _decline_pending_disease_hazard() -> void:
	_pending_disease_hazard = null
	if _disease_hazard_overlay != null:
		_disease_hazard_overlay.visible = false
	if diver != null:
		diver.input_enabled = true
	_show_status("Pozostawiono skażony magazyn bez zmian.", 2.2)
	_update_ui()

func _show_loot_overlay(container: DiveLootContainer) -> void:
	_loot_panel.present(container, session, Callable(self, "_item_display_name"))

func _take_pending_amount(resource_id: String, amount: int) -> void:
	if _pending_container == null:
		return
	var existed_before := _pending_container.contents.has(resource_id)
	var accepted: int = _loot_system.transfer_amount(session, _pending_container.contents, resource_id, amount)
	if accepted <= 0:
		_show_status("Brak wolnego udźwigu albo slotu na ten przedmiot.", 2.2)
		_loot_panel.refresh(_pending_container, session, Callable(self, "_item_display_name"))
		return
	_pending_container_changed = true
	if existed_before and not _pending_container.contents.has(resource_id):
		_record_depleted_world_item(resource_id)
	_sync_pending_container_state()
	_maybe_complete_tutorial_loot()
	_show_status("Zabrano %d x %s." % [accepted, _item_display_name(resource_id)], 2.0)
	if _pending_container_is_empty():
		_finish_pending_loot_interaction()
	else:
		_loot_panel.refresh(_pending_container, session, Callable(self, "_item_display_name"))
		_update_ui()

func _take_pending_loot() -> void:
	if _pending_container == null:
		return
	var original_resource_ids := _pending_container.contents.keys()
	var transferred: Dictionary = _loot_system.transfer_all(session, _pending_container.contents)
	for resource_id in original_resource_ids:
		if not _pending_container.contents.has(resource_id):
			_record_depleted_world_item(str(resource_id))
	var recovered_any_gear := false
	if _pending_container is LostBackpackScript:
		var backpack = _pending_container
		for gear_id in backpack.gear_ids.duplicate():
			_recover_pending_gear_internal(str(gear_id))
			recovered_any_gear = true
	if not transferred.is_empty() or recovered_any_gear:
		_pending_container_changed = true
		_sync_pending_container_state()
		_maybe_complete_tutorial_loot()
	var has_remaining := not _pending_container_is_empty()
	if has_remaining:
		_show_status("Brak wolnego udźwigu lub slotu. Wybrane reszty zostały w pojemniku.", 3.0)
		_leave_pending_loot()
	else:
		_finish_pending_loot_interaction()

func _recover_pending_gear(gear_id: String) -> void:
	if not _recover_pending_gear_internal(gear_id):
		return
	_pending_container_changed = true
	_sync_pending_container_state()
	_show_status("Odzyskano wyposażenie: %s." % _gear_display_name(gear_id), 2.4)
	if _pending_container_is_empty():
		_finish_pending_loot_interaction()
	else:
		_loot_panel.refresh(_pending_container, session, Callable(self, "_item_display_name"))
		_update_ui()

func _recover_pending_gear_internal(gear_id: String) -> bool:
	if _pending_container == null or not (_pending_container is LostBackpackScript):
		return false
	var backpack = _pending_container
	if not backpack.gear_ids.has(gear_id):
		return false
	backpack.gear_ids.erase(gear_id)
	if not session.recovered_gear_ids.has(gear_id):
		session.recovered_gear_ids.append(gear_id)
	return true

func _record_depleted_world_item(resource_id: String) -> void:
	if _pending_container == null or _pending_container is LostBackpackScript or _pending_container is DroppedLootScript:
		return
	var world_item_id := "%s:%s" % [_pending_container.container_id, resource_id]
	if not session.collected_world_item_ids.has(world_item_id):
		session.collected_world_item_ids.append(world_item_id)

func _sync_pending_container_state() -> void:
	if _pending_container == null:
		return
	if _pending_container is LostBackpackScript:
		var backpack = _pending_container
		session.recovered_backpacks[backpack.backpack_record_id()] = backpack.build_recovery_update()
		_pending_container.set_opened(backpack.is_fully_recovered())
		return
	if _pending_container is DroppedLootScript:
		var dropped = _pending_container
		session.dropped_loot_updates[dropped.persistence_id] = dropped.build_persistence_update()
		_pending_container.set_opened(_pending_container.contents.is_empty())
		return
	if _pending_container.contents.is_empty():
		if not session.opened_containers.has(_pending_container.container_id):
			session.opened_containers.append(_pending_container.container_id)
		session.remaining_container_contents.erase(_pending_container.container_id)
		_pending_container.set_opened(true)
	else:
		session.remaining_container_contents[_pending_container.container_id] = _pending_container.contents.duplicate(true)
		session.opened_containers.erase(_pending_container.container_id)
		_pending_container.set_opened(false)

func _pending_container_is_empty() -> bool:
	if _pending_container == null:
		return true
	if _pending_container is LostBackpackScript:
		return _pending_container.is_fully_recovered()
	return _pending_container.contents.is_empty()

func _finish_pending_loot_interaction() -> void:
	if _pending_container == null:
		return
	var mandatory_order := _pending_container.mandatory_order
	_sync_pending_container_state()
	_pending_container = null
	_pending_container_changed = false
	_loot_panel.dismiss()
	diver.input_enabled = true
	if setup.tutorial_mode and mandatory_order == 1:
		_maybe_complete_tutorial_loot()
	elif setup.tutorial_mode and mandatory_order < 0:
		_tutorial_event("optional_risk_finished")
	_update_ui()

func _item_display_name(item_id: String) -> String:
	var definition = GameDatabase.items.get(item_id) if GameDatabase != null else null
	return str(definition.display_name) if definition != null else ResourceIdsScript.display_name(item_id)

func _gear_display_name(gear_id: String) -> String:
	var definition = GameDatabase.diving_gear.get(gear_id) if GameDatabase != null else null
	return str(definition.display_name) if definition != null else gear_id.replace("_", " ").capitalize()

func _leave_pending_loot() -> void:
	if _pending_container != null:
		if _pending_container_changed:
			_sync_pending_container_state()
		else:
			_pending_container.set_opened(_pending_container_is_empty())
	_pending_container = null
	_pending_container_changed = false
	_loot_panel.dismiss()
	diver.input_enabled = true
	_update_ui()

func _open_inventory() -> void:
	if session == null or _pending_container != null or _pending_disease_hazard != null or _rescue_overlay.visible or _attempt_failed:
		return
	_inventory_panel.present(session, Callable(self, "_item_display_name"))
	diver.input_enabled = false

func _close_inventory() -> void:
	_inventory_panel.dismiss()
	diver.input_enabled = true
	_update_ui()

func _drop_inventory_amount(resource_id: String, amount: int) -> void:
	if session == null or amount <= 0:
		return
	var removed: int = session.remove_item(resource_id, amount)
	if removed <= 0:
		_show_status("Nie udało się porzucić wybranego przedmiotu.", 2.0)
		_inventory_panel.refresh(session, Callable(self, "_item_display_name"))
		return
	var preferred_id: String = session.next_dropped_loot_id()
	var dropped = dive_map.create_or_merge_dropped_loot_pile(
		preferred_id,
		{resource_id: removed},
		diver.global_position,
		int(setup.day)
	)
	if dropped == null:
		session.add_item(resource_id, removed)
		_show_status("Nie znaleziono bezpiecznego miejsca na pakunek.", 2.5)
		_inventory_panel.refresh(session, Callable(self, "_item_display_name"))
		return
	session.dropped_loot_updates[dropped.persistence_id] = dropped.build_persistence_update()
	_show_status("Porzucono %d x %s. Pakunek pozostanie w tym miejscu." % [removed, _item_display_name(resource_id)], 3.0)
	_inventory_panel.refresh(session, Callable(self, "_item_display_name"))
	_update_ui()

func _try_return_to_surface() -> void:
	if setup.tutorial_mode and tutorial_step() <= TutorialStateScript.Step.DIVE_RETURN_TO_LINE and not _has_required_tutorial_loot():
		_show_status("Zabierz wskazane minimum: żywność, deskę oraz 3 złomu i 2 tkaniny i gumy na Nóż ratowniczy.", 3.8)
		return
	var tutorial_return_blocker := _tutorial_return_blocker()
	if not tutorial_return_blocker.is_empty():
		_show_status(tutorial_return_blocker, 3.2)
		return
	_finish_success()

func _mandatory_container_count() -> int:
	if setup != null and setup.tutorial_mode and session != null:
		var current_step := tutorial_step()
		if current_step <= TutorialStateScript.Step.DIVE_OPEN_CONTAINER:
			return 0
		if current_step == TutorialStateScript.Step.DIVE_INVENTORY:
			return 1
		return 2
	var count := 0
	for container in dive_map.containers:
		if container.mandatory_order >= 0 and session.opened_containers.has(container.container_id):
			count += 1
	return count

func _has_required_tutorial_loot() -> bool:
	return session != null and _tutorial_director.has_required_first_dive_loot(session.carried_items)


func _maybe_complete_tutorial_loot() -> void:
	if (
		setup == null
		or not setup.tutorial_mode
		or session == null
		or tutorial_step() != TutorialStateScript.Step.DIVE_INVENTORY
		or not _has_required_tutorial_loot()
	):
		return
	_reconcile_tutorial_dive_progress()

func _on_oxygen_depleted() -> void:
	diver.input_enabled = false
	if setup.tutorial_mode:
		_attempt_failed = true
		_pending_finish_result = null
		_failure_title.text = "BRAK TLENU"
		_failure_body.text = "Tlen się skończył przed powrotem do liny. %s traci łup z tej próby, ale dzień nie zostanie rozliczony. Powtórz wyprawę od wejścia." % _diver_display_name()
		_failure_retry_button.text = "Spróbuj ponownie"
		_failure_overlay.visible = true
		_failure_retry_button.grab_focus()
		return
	_finish_death("brak_tlenu")

func _retry_tutorial_dive() -> void:
	_start_attempt(true)

func _finish_success() -> void:
	if game_root == null or setup == null or _ending:
		return
	_ending = true
	diver.input_enabled = false
	var result = DiveResultScript.new()
	result.diver_id = setup.diver_id
	result.returned_alive = true
	result.diver_dead = false
	result.oxygen_remaining = session.oxygen_left
	result.health_remaining = session.health
	result.experience_gained = _calculate_dive_experience()
	result.dive_duration = session.elapsed_time
	result.discovered_sectors.assign(_discovered_landmarks_this_dive)
	_persistence_system.populate_result(session, result)
	_rescue_system.populate_success_result(session, result)
	result.tutorial_completed = setup.tutorial_mode
	if setup.tutorial_mode:
		result.tutorial_outcome = session.build_tutorial_outcome()
	_risk_runtime.populate_result(session, result)
	_copy_disease_exposures_to_result(result)
	for resource_id in session.carried_items.keys():
		result.add_item(str(resource_id), int(session.carried_items[resource_id]))
	if not game_root.finish_dive(result):
		_show_resolution_save_error(result)

func _finish_death(reason: String) -> void:
	if game_root == null or setup == null or _ending:
		return
	if _try_operator_extraction(reason):
		return
	_ending = true
	var result = DiveResultScript.new()
	result.diver_id = setup.diver_id
	result.returned_alive = false
	result.diver_dead = true
	result.health_remaining = 0
	var death_landmark: String = dive_map.landmark_id_at(diver.global_position)
	result.body_location_if_dead = death_landmark if not death_landmark.is_empty() else setup.target_sector
	result.backpack_location_if_lost = "%s@%d,%d" % [result.body_location_if_dead, int(diver.global_position.x), int(diver.global_position.y)]
	result.death_world_position = diver.global_position
	result.lost_items = session.carried_items.duplicate(true)
	result.discovered_sectors.assign(_discovered_landmarks_this_dive)
	result.dive_duration = session.elapsed_time
	result.lost_gear.assign(setup.selected_gear)
	for recovered_gear_id in session.recovered_gear_ids:
		if not result.lost_gear.has(str(recovered_gear_id)):
			result.lost_gear.append(str(recovered_gear_id))
	_persistence_system.populate_result(session, result)
	_rescue_system.populate_death_result(session, result)
	session.record_risk_event("death:%s" % reason)
	_risk_runtime.populate_result(session, result)
	_copy_disease_exposures_to_result(result)
	if not game_root.finish_dive(result):
		_show_resolution_save_error(result)

func _try_operator_extraction(reason: String) -> bool:
	if not bool(setup.operator_assigned):
		return false
	if str(setup.start_entry_point) not in ["R1-00", "dead_city_rooftops_001"]:
		return false
	var rescue_max_distance := maxf(float(setup.difficulty_modifiers.get(
		"operator_rescue_max_distance",
		ExpeditionSetupScript.DEFAULT_OPERATOR_RESCUE_MAX_DISTANCE
	)), 0.0)
	if dive_map.exit_line == null or diver.global_position.distance_to(dive_map.exit_line.global_position) > rescue_max_distance:
		return false
	var chance := clampf(float(setup.difficulty_modifiers.get("operator_rescue_chance", 0.0)), 0.0, 1.0)
	var campaign_seed := int(game_state.seed) if game_state != null else 1
	var mixed := campaign_seed * 92_821 + int(setup.day) * 68_917 + int(session.elapsed_time * 10.0) * 19_939 + reason.hash()
	var roll := float(posmod(mixed, 10_000)) / 10_000.0
	if roll >= chance:
		return false
	_finish_operator_extraction(reason)
	return true

func _finish_operator_extraction(reason: String) -> void:
	_ending = true
	diver.input_enabled = false
	session.add_injury("emergency_extraction")
	session.record_risk_event("operator_rescue:%s" % reason)
	var result = DiveResultScript.new()
	result.diver_id = setup.diver_id
	result.returned_alive = true
	result.diver_dead = false
	result.emergency_extraction = true
	result.oxygen_remaining = 0.0
	result.health_remaining = maxi(mini(session.health, 35), 1)
	result.dive_duration = session.elapsed_time
	var extraction_loot := _partition_operator_extraction_loot(session.carried_items)
	result.lost_items = extraction_loot.ordinary_items
	result.discovered_sectors.assign(_discovered_landmarks_this_dive)
	_persistence_system.populate_result(session, result)
	_append_operator_artifact_pile(result, extraction_loot.artifact_items)
	_rescue_system.populate_success_result(session, result)
	_risk_runtime.populate_result(session, result)
	_copy_disease_exposures_to_result(result)
	if not game_root.finish_dive(result):
		_show_resolution_save_error(result)


func _partition_operator_extraction_loot(carried_items: Dictionary) -> Dictionary:
	var ordinary_items: Dictionary = {}
	var artifact_items: Dictionary = {}
	for raw_item_id in carried_items.keys():
		var item_id := str(raw_item_id)
		var amount := maxi(int(carried_items[raw_item_id]), 0)
		if item_id.is_empty() or amount <= 0:
			continue
		var target := artifact_items if _is_story_artifact(item_id) else ordinary_items
		target[item_id] = amount
	return {
		"ordinary_items": ordinary_items,
		"artifact_items": artifact_items,
	}


func _append_operator_artifact_pile(result, artifact_items: Dictionary) -> void:
	if result == null or artifact_items.is_empty() or session == null or diver == null or dive_map == null:
		return
	var pile_id: String = session.next_dropped_loot_id()
	var extraction_position: Vector2 = diver.global_position
	var landmark_id: String = dive_map.landmark_id_at(extraction_position)
	result.dropped_loot_updates[pile_id] = {
		"persistence_id": pile_id,
		"world_position": extraction_position,
		"landmark_id": landmark_id if not landmark_id.is_empty() else str(setup.target_sector),
		"items": artifact_items.duplicate(true),
		"created_day": maxi(int(setup.day), 1),
		"recovered": false,
	}


func _is_story_artifact(item_id: String) -> bool:
	var definition = GameDatabase.items.get(item_id) if GameDatabase != null else null
	return definition != null and "story_artifact" in definition.tags


func _copy_disease_exposures_to_result(result: DiveResult) -> void:
	if result == null or session == null:
		return
	for exposure in session.disease_exposures:
		result.add_disease_exposure(exposure)


func _show_resolution_save_error(result) -> void:
	_pending_finish_result = result.detached_copy() if result != null and result.has_method("detached_copy") else null
	_attempt_failed = true
	_ending = true
	diver.input_enabled = false
	_failure_title.text = "NIE UDAŁO SIĘ ZAPISAĆ"
	_failure_body.text = "Wyprawa pozostaje zakończona, ale jej skutki nie zostały zastosowane do kampanii. Zwolnij miejsce na dysku i ponów zapis — nurkowania nie trzeba powtarzać."
	_failure_retry_button.text = "PONÓW ZAPIS I ROZLICZENIE"
	_failure_overlay.visible = true
	_failure_retry_button.call_deferred("grab_focus")


func _on_failure_retry_pressed() -> void:
	if _pending_finish_result == null:
		_retry_tutorial_dive()
		return
	if game_root != null and game_root.finish_dive(_pending_finish_result):
		return
	_failure_body.text = "Zapis nadal się nie udał. Stan kampanii nie został zmieniony; sprawdź miejsce na dysku i spróbuj ponownie."
	_failure_retry_button.call_deferred("grab_focus")

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "DiveHUD"
	canvas.layer = 10
	add_child(canvas)

	_build_tutorial_direction_indicator(canvas)
	_build_status_panel(canvas)
	_build_tutorial_panel(canvas)
	_build_return_panel(canvas)
	_build_interaction_prompt(canvas)
	_build_disease_hazard_overlay(canvas)
	_build_loot_overlay(canvas)
	_build_inventory_overlay(canvas)
	_build_rescue_overlay(canvas)
	_build_failure_overlay(canvas)

	_warning_label = Label.new()
	_warning_label.anchor_left = 0.5
	_warning_label.anchor_right = 0.5
	_warning_label.offset_left = -220
	_warning_label.offset_top = 68
	_warning_label.offset_right = 220
	_warning_label.offset_bottom = 100
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.add_theme_font_size_override("font_size", 18)
	_warning_label.add_theme_color_override("font_color", Color("ff745f"))
	_warning_label.add_theme_constant_override("outline_size", 4)
	_warning_label.add_theme_color_override("font_outline_color", Color("061014"))
	canvas.add_child(_warning_label)

	_current_label = Label.new()
	_current_label.anchor_left = 1.0
	_current_label.anchor_right = 1.0
	_current_label.offset_left = -270
	_current_label.offset_top = 64
	_current_label.offset_right = -20
	_current_label.offset_bottom = 94
	_current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_current_label.add_theme_font_size_override("font_size", 13)
	_current_label.add_theme_color_override("font_color", Color("8edadd"))
	_current_label.add_theme_constant_override("outline_size", 3)
	_current_label.add_theme_color_override("font_outline_color", Color("061014"))
	canvas.add_child(_current_label)

	_scout_label = Label.new()
	_scout_label.name = "ScoutReadout"
	_scout_label.anchor_left = 1.0
	_scout_label.anchor_right = 1.0
	_scout_label.offset_left = -270
	_scout_label.offset_top = 126
	_scout_label.offset_right = -20
	_scout_label.offset_bottom = 156
	_scout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_scout_label.add_theme_font_size_override("font_size", 13)
	_scout_label.add_theme_color_override("font_color", Color("a9d8b8"))
	_scout_label.add_theme_constant_override("outline_size", 3)
	_scout_label.add_theme_color_override("font_outline_color", Color("061014"))
	_scout_label.tooltip_text = "Zwiadowca wskazuje wyłącznie kierunek i kategorię najbliższego sygnału."
	canvas.add_child(_scout_label)

	_combat_label = Label.new()
	_combat_label.anchor_left = 1.0
	_combat_label.anchor_right = 1.0
	_combat_label.offset_left = -390
	_combat_label.offset_top = 96
	_combat_label.offset_right = -20
	_combat_label.offset_bottom = 124
	_combat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combat_label.add_theme_font_size_override("font_size", 13)
	_combat_label.add_theme_color_override("font_color", Color("e8cd83"))
	_combat_label.add_theme_constant_override("outline_size", 3)
	_combat_label.add_theme_color_override("font_outline_color", Color("061014"))
	canvas.add_child(_combat_label)


func _build_tutorial_direction_indicator(canvas: CanvasLayer) -> void:
	_tutorial_direction_indicator = TutorialDirectionIndicatorScript.new()
	_tutorial_direction_indicator.name = "TutorialDirectionIndicator"
	_tutorial_direction_indicator.set_anchors_preset(Control.PRESET_CENTER)
	_tutorial_direction_indicator.offset_left = -TutorialDirectionIndicatorScript.INDICATOR_SIZE.x * 0.5
	_tutorial_direction_indicator.offset_top = -TutorialDirectionIndicatorScript.INDICATOR_SIZE.y * 0.5
	_tutorial_direction_indicator.offset_right = TutorialDirectionIndicatorScript.INDICATOR_SIZE.x * 0.5
	_tutorial_direction_indicator.offset_bottom = TutorialDirectionIndicatorScript.INDICATOR_SIZE.y * 0.5
	_tutorial_direction_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial_direction_indicator.visible = false
	canvas.add_child(_tutorial_direction_indicator)

func _build_status_panel(canvas: CanvasLayer) -> void:
	_hud_dock = DiveHudDockScript.new()
	_hud_dock.anchor_top = 1.0
	_hud_dock.anchor_right = 1.0
	_hud_dock.anchor_bottom = 1.0
	_hud_dock.offset_left = 16
	_hud_dock.offset_top = -88
	_hud_dock.offset_right = -16
	_hud_dock.offset_bottom = -12
	_hud_dock.build()
	canvas.add_child(_hud_dock)
	_oxygen_bar = _hud_dock.oxygen_bar
	_oxygen_label = _hud_dock.oxygen_label
	_oxygen_fill_style = _hud_dock.oxygen_fill_style
	_health_bar = _hud_dock.health_bar
	_health_label = _hud_dock.health_label
	_health_fill_style = _hud_dock.health_fill_style
	_diver_name_label = _hud_dock.diver_name_label
	_diver_meta_label = _hud_dock.diver_meta_label
	_experience_label = _hud_dock.experience_label
	_portrait = _hud_dock.portrait
	_suit_label = _hud_dock.suit_label
	_time_label = _hud_dock.time_label
	_light_label = _hud_dock.light_label
	_inventory_summary_label = _hud_dock.inventory_summary_label
	_inventory_slots = _hud_dock.inventory_slots
	_inventory_labels = _hud_dock.inventory_labels

func _build_tutorial_panel(canvas: CanvasLayer) -> void:
	_tutorial_panel = _make_panel(Color("071318b8"), Color("40575d80"), 1)
	_tutorial_panel.name = "DiveTutorialCapsule"
	_tutorial_panel.anchor_left = 0.5
	_tutorial_panel.anchor_right = 0.5
	_tutorial_panel.offset_left = -220
	_tutorial_panel.offset_top = 18
	_tutorial_panel.offset_right = 220
	_tutorial_panel.offset_bottom = 126
	canvas.add_child(_tutorial_panel)
	var content := _margin_content(_tutorial_panel, 7)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	content.add_child(column)
	_tutorial_title = Label.new()
	_tutorial_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_tutorial_title.add_theme_color_override("font_color", Color("e8e8df"))
	_tutorial_title.add_theme_font_size_override("font_size", 13)
	column.add_child(_tutorial_title)
	_tutorial_body = Label.new()
	_tutorial_body.name = "DiveTutorialBody"
	_tutorial_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_body.add_theme_color_override("font_color", Color("b9c9c7"))
	_tutorial_body.add_theme_font_size_override("font_size", 12)
	column.add_child(_tutorial_body)

func _build_return_panel(canvas: CanvasLayer) -> void:
	_navigation_panel = _make_panel(Color("071318a6"), Color.TRANSPARENT, 0)
	_navigation_panel.name = "DiveNavigationLine"
	_navigation_panel.anchor_left = 1.0
	_navigation_panel.anchor_right = 1.0
	_navigation_panel.offset_left = -398
	_navigation_panel.offset_top = 18
	_navigation_panel.offset_right = -18
	_navigation_panel.offset_bottom = 56
	canvas.add_child(_navigation_panel)
	var content := _margin_content(_navigation_panel, 7)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 9)
	content.add_child(row)
	_return_label = Label.new()
	_return_label.add_theme_font_size_override("font_size", 14)
	_return_label.add_theme_color_override("font_color", Color("dceae7"))
	row.add_child(_return_label)
	var separator := Label.new()
	separator.text = "•"
	separator.add_theme_color_override("font_color", Color("617a80"))
	row.add_child(separator)
	_objective_label = Label.new()
	_objective_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_objective_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_objective_label.add_theme_font_size_override("font_size", 14)
	_objective_label.add_theme_color_override("font_color", Color("9ed3d3"))
	row.add_child(_objective_label)
	_depth_label = Label.new()
	_depth_label.visible = false
	_navigation_panel.add_child(_depth_label)

func _build_interaction_prompt(canvas: CanvasLayer) -> void:
	_interaction_panel = _make_panel(Color("071318df"), Color("9e824b99"), 1)
	_interaction_panel.name = "DiveInteractionPrompt"
	_interaction_panel.anchor_left = 0.5
	_interaction_panel.anchor_top = 1.0
	_interaction_panel.anchor_right = 0.5
	_interaction_panel.anchor_bottom = 1.0
	_interaction_panel.offset_left = -190
	_interaction_panel.offset_top = -144
	_interaction_panel.offset_right = 190
	_interaction_panel.offset_bottom = -94
	_interaction_panel.visible = false
	canvas.add_child(_interaction_panel)
	var content := _margin_content(_interaction_panel, 10)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	content.add_child(column)
	_interaction_label = Label.new()
	_interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interaction_label.add_theme_font_size_override("font_size", 13)
	column.add_child(_interaction_label)
	_interaction_bar = ProgressBar.new()
	_interaction_bar.max_value = 1.0
	_interaction_bar.show_percentage = false
	_interaction_bar.custom_minimum_size.y = 5
	column.add_child(_interaction_bar)

func _build_loot_overlay(canvas: CanvasLayer) -> void:
	_loot_panel = DiveLootPanelScript.new()
	_loot_panel.build()
	_loot_panel.take_amount_requested.connect(_take_pending_amount)
	_loot_panel.take_all_requested.connect(_take_pending_loot)
	_loot_panel.recover_gear_requested.connect(_recover_pending_gear)
	_loot_panel.close_requested.connect(_leave_pending_loot)
	canvas.add_child(_loot_panel)


func _build_disease_hazard_overlay(canvas: CanvasLayer) -> void:
	_disease_hazard_overlay = ColorRect.new()
	_disease_hazard_overlay.name = "DiseaseHazardOverlay"
	_disease_hazard_overlay.color = Color(0.01, 0.025, 0.025, 0.88)
	_disease_hazard_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_disease_hazard_overlay.z_index = 106
	_disease_hazard_overlay.visible = false
	canvas.add_child(_disease_hazard_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_disease_hazard_overlay.add_child(center)
	var panel := _make_panel(Color("111a19fc"), Color("d5a85f"), 2)
	panel.custom_minimum_size = Vector2(680, 400)
	center.add_child(panel)
	var content := _margin_content(panel, 28)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	content.add_child(column)
	var eyebrow := Label.new()
	eyebrow.text = "R1-06  //  JAWNA DECYZJA PRZED ŁUPEM"
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", Color("c79f6b"))
	column.add_child(eyebrow)
	_disease_hazard_title = Label.new()
	_disease_hazard_title.name = "DiseaseHazardTitle"
	_disease_hazard_title.add_theme_font_size_override("font_size", 24)
	_disease_hazard_title.add_theme_color_override("font_color", Color("f0c985"))
	column.add_child(_disease_hazard_title)
	_disease_hazard_body = Label.new()
	_disease_hazard_body.name = "DiseaseHazardBody"
	_disease_hazard_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_disease_hazard_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_disease_hazard_body.add_theme_font_size_override("font_size", 16)
	_disease_hazard_body.add_theme_color_override("font_color", Color("dce5df"))
	column.add_child(_disease_hazard_body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_decline_disease_hazard_button = Button.new()
	_decline_disease_hazard_button.name = "DeclineDiseaseHazardButton"
	_decline_disease_hazard_button.text = "Zostaw magazyn"
	_decline_disease_hazard_button.tooltip_text = "Odmów bez zmiany sesji i bez otwierania łupu."
	_decline_disease_hazard_button.pressed.connect(_decline_pending_disease_hazard)
	buttons.add_child(_decline_disease_hazard_button)
	_accept_disease_hazard_button = Button.new()
	_accept_disease_hazard_button.name = "AcceptDiseaseHazardButton"
	_accept_disease_hazard_button.text = "Podejmij ryzyko"
	_accept_disease_hazard_button.tooltip_text = "Przyjmij narażenie i dopiero wtedy otwórz magazyn ratunkowy."
	_accept_disease_hazard_button.pressed.connect(_accept_pending_disease_hazard)
	buttons.add_child(_accept_disease_hazard_button)
	var decline_to_accept := _decline_disease_hazard_button.get_path_to(_accept_disease_hazard_button)
	var accept_to_decline := _accept_disease_hazard_button.get_path_to(_decline_disease_hazard_button)
	_decline_disease_hazard_button.focus_previous = decline_to_accept
	_decline_disease_hazard_button.focus_next = decline_to_accept
	_decline_disease_hazard_button.focus_neighbor_left = decline_to_accept
	_decline_disease_hazard_button.focus_neighbor_top = decline_to_accept
	_decline_disease_hazard_button.focus_neighbor_right = decline_to_accept
	_decline_disease_hazard_button.focus_neighbor_bottom = decline_to_accept
	_accept_disease_hazard_button.focus_previous = accept_to_decline
	_accept_disease_hazard_button.focus_next = accept_to_decline
	_accept_disease_hazard_button.focus_neighbor_left = accept_to_decline
	_accept_disease_hazard_button.focus_neighbor_top = accept_to_decline
	_accept_disease_hazard_button.focus_neighbor_right = accept_to_decline
	_accept_disease_hazard_button.focus_neighbor_bottom = accept_to_decline

func _build_inventory_overlay(canvas: CanvasLayer) -> void:
	_inventory_panel = DiveInventoryPanelScript.new()
	_inventory_panel.build()
	_inventory_panel.drop_amount_requested.connect(_drop_inventory_amount)
	_inventory_panel.close_requested.connect(_close_inventory)
	canvas.add_child(_inventory_panel)

func _build_rescue_overlay(canvas: CanvasLayer) -> void:
	_rescue_overlay = ColorRect.new()
	_rescue_overlay.name = "RescueOverlay"
	_rescue_overlay.color = Color(0.01, 0.03, 0.04, 0.80)
	_rescue_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rescue_overlay.z_index = 105
	_rescue_overlay.visible = false
	canvas.add_child(_rescue_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rescue_overlay.add_child(center)
	var panel := _make_panel(Color("101a1bfc"), Color("67c9bd"), 2)
	panel.custom_minimum_size = Vector2(660, 430)
	center.add_child(panel)
	var content := _margin_content(panel, 26)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	content.add_child(column)
	var eyebrow := Label.new()
	eyebrow.text = "SYGNAŁ ŻYCIA  //  DECYZJA RATUNKOWA"
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", Color("7fb0ae"))
	column.add_child(eyebrow)
	_rescue_title = Label.new()
	_rescue_title.add_theme_font_size_override("font_size", 24)
	_rescue_title.add_theme_color_override("font_color", Color("a5eee1"))
	column.add_child(_rescue_title)
	_rescue_body = Label.new()
	_rescue_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rescue_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rescue_body.add_theme_font_size_override("font_size", 16)
	_rescue_body.add_theme_color_override("font_color", Color("d8e3df"))
	column.add_child(_rescue_body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	_leave_rescue_button = Button.new()
	_leave_rescue_button.name = "LeaveRescueButton"
	_leave_rescue_button.text = "Zostaw na razie"
	_leave_rescue_button.pressed.connect(_leave_pending_rescue)
	buttons.add_child(_leave_rescue_button)
	_tow_rescue_button = Button.new()
	_tow_rescue_button.name = "TowRescueButton"
	_tow_rescue_button.text = "Holuj bez stabilizacji"
	_tow_rescue_button.pressed.connect(_begin_pending_rescue.bind(false))
	buttons.add_child(_tow_rescue_button)
	_stabilize_rescue_button = Button.new()
	_stabilize_rescue_button.name = "StabilizeRescueButton"
	_stabilize_rescue_button.text = "Użyj leku i holuj"
	_stabilize_rescue_button.pressed.connect(_begin_pending_rescue.bind(true))
	buttons.add_child(_stabilize_rescue_button)

func _build_failure_overlay(canvas: CanvasLayer) -> void:
	_failure_overlay = ColorRect.new()
	_failure_overlay.name = "TutorialRetryOverlay"
	_failure_overlay.color = Color(0.015, 0.025, 0.03, 0.86)
	_failure_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_failure_overlay.z_index = 110
	_failure_overlay.visible = false
	canvas.add_child(_failure_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_failure_overlay.add_child(center)
	var panel := _make_panel(Color("11191cfc"), Color("be594c"), 2)
	panel.custom_minimum_size = Vector2(520, 320)
	center.add_child(panel)
	var content := _margin_content(panel, 28)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	content.add_child(column)
	_failure_title = Label.new()
	_failure_title.name = "DiveFailureTitle"
	_failure_title.text = "BRAK TLENU"
	_failure_title.add_theme_font_size_override("font_size", 26)
	_failure_title.add_theme_color_override("font_color", Color("ff7663"))
	column.add_child(_failure_title)
	_failure_body = Label.new()
	_failure_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_failure_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_failure_body.add_theme_font_size_override("font_size", 17)
	column.add_child(_failure_body)
	_failure_retry_button = Button.new()
	_failure_retry_button.name = "RetryButton"
	_failure_retry_button.text = "Spróbuj ponownie"
	_failure_retry_button.custom_minimum_size = Vector2(0, 52)
	_failure_retry_button.pressed.connect(_on_failure_retry_pressed)
	column.add_child(_failure_retry_button)

func _update_ui() -> void:
	if session == null or _oxygen_bar == null:
		return
	_update_current_presentation(0.0)
	_hud_dock.update_vitals(session)
	_hud_dock.update_identity(setup, game_state.find_survivor(setup.diver_id) if game_state != null else null)
	_hud_dock.update_light(_equipped_light_definition, _is_diver_light_active())
	var oxygen_tank_id := str(setup.equipped_gear.get("oxygen_tank", "oxygen_tank_mk1"))
	_hud_dock.update_oxygen_tank(GameDatabase.diving_gear.get(oxygen_tank_id))

	var to_exit := dive_map.exit_line.global_position - diver.global_position
	var arrow := "←" if absf(to_exit.x) >= absf(to_exit.y) and to_exit.x < 0 else "→" if absf(to_exit.x) >= absf(to_exit.y) else "↑" if to_exit.y < 0 else "↓"
	_return_label.text = "%s  LINA %d m" % [arrow, int(to_exit.length() / 8.0)]
	_depth_label.text = "%s  •  %d m" % [dive_map.module_name_at(diver.global_position), int(round(dive_map.depth_at(diver.global_position)))]
	_objective_label.text = _compact_objective_text()
	var objective_detail := _objective_text()
	_navigation_panel.tooltip_text = "%s\n%s" % [_depth_label.text, objective_detail]
	_return_label.tooltip_text = _navigation_panel.tooltip_text
	_objective_label.tooltip_text = _navigation_panel.tooltip_text
	var current_symbol: String = DiveCurrentVisualScript.direction_symbol_for_vector(_active_current_vector)
	_current_label.text = "PRĄD WODNY  %s" % current_symbol if not current_symbol.is_empty() else ""
	_update_scout_label()
	var combat_tool := str(session.selected_combat_tool)
	if combat_tool == "harpoon_pistol":
		_combat_label.text = "[1] NÓŻ  •  [2] HARPUN  %d/%d  •  [LPM] STRZAŁ" % [int(session.harpoon_ammo), int(setup.weapon_ammunition)]
	elif combat_tool == "knife":
		_combat_label.text = "[1] NÓŻ  •  [2] HARPUN  •  [LPM] ATAK"
	else:
		_combat_label.text = ""

	_update_tutorial_panel()
	var ratio: float = session.oxygen_ratio()
	if ratio <= 0.10:
		_warning_label.text = "TLEN KRYTYCZNY"
	elif _status_message_time > 0.0:
		_warning_label.text = _status_message
	elif ratio <= 0.25:
		_warning_label.text = "NISKI POZIOM TLENU"
	else:
		_warning_label.text = _risk_warning
	var warning_top := 134.0 if _tutorial_panel.visible else 68.0
	_warning_label.offset_top = warning_top
	_warning_label.offset_bottom = warning_top + 36.0

	_update_inventory()
	_update_tutorial_direction_indicator()
	_update_interaction_panel()

func _update_inventory() -> void:
	_hud_dock.update_inventory(session)

func _update_tutorial_panel() -> void:
	_tutorial_panel.visible = setup != null and setup.tutorial_mode
	if not _tutorial_panel.visible or session == null:
		return
	var message: Dictionary = NarrativeContentScript.tutorial_message(tutorial_step())
	if message.is_empty():
		_tutorial_panel.visible = false
		return
	_tutorial_title.text = str(message.get("compact_title", "SAMOUCZEK"))
	_tutorial_body.text = str(message.get("body", ""))
	_tutorial_panel.tooltip_text = _tutorial_body.text
	_tutorial_title.tooltip_text = _tutorial_body.text


func _update_tutorial_direction_indicator() -> void:
	if _tutorial_direction_indicator == null:
		return
	if not is_inside_tree():
		_tutorial_direction_indicator.clear()
		return
	var target := _tutorial_navigation_target()
	if target.is_empty() or diver == null:
		_tutorial_direction_indicator.clear()
		return
	var target_position: Vector2 = target.get("position", diver.global_position)
	_tutorial_direction_indicator.present(
		target_position - diver.global_position,
		str(target.get("label", "CEL")),
		diver.global_position.distance_to(target_position)
	)


func _tutorial_navigation_target() -> Dictionary:
	if (
		setup == null
		or not setup.tutorial_mode
		or session == null
		or not session.is_tutorial_active()
		or dive_map == null
	):
		return {}
	match tutorial_step():
		TutorialStateScript.Step.DIVE_MOVEMENT, TutorialStateScript.Step.DIVE_OXYGEN, TutorialStateScript.Step.DIVE_OPEN_CONTAINER, TutorialStateScript.Step.DIVE_INVENTORY:
			return {
				"position": dive_map.objective_position(_mandatory_container_count()),
				"label": "ZASOBY",
			}
		TutorialStateScript.Step.DIVE_BLOCKED_PASSAGE:
			var blockage: DivePersistentInteractable = _tutorial_cable_blockage()
			if blockage != null:
				return {
					"position": blockage.global_position,
					"label": "BLOKADA KABLA",
				}
		TutorialStateScript.Step.DIVE_RETURN_TO_LINE, TutorialStateScript.Step.FINAL_RETURN_TO_LINE:
			return {
				"position": dive_map.exit_line.global_position,
				"label": "LINA",
			}
		TutorialStateScript.Step.ACTIVATE_JUNCTION_J7:
			if not _tutorial_cable_blockage_opened():
				var blockage: DivePersistentInteractable = _tutorial_cable_blockage()
				if blockage != null:
					return {
						"position": blockage.global_position,
						"label": "BLOKADA KABLA",
					}
			var junction = _tutorial_junction_j7()
			if junction != null:
				return {
					"position": junction.global_position,
					"label": "WĘZEŁ J-7",
				}
	return {}


func _update_interaction_panel() -> void:
	if _quiet_repair_progress > 0.0:
		_interaction_panel.visible = true
		_interaction_label.text = "CICHA NAPRAWA  •  PRZYTRZYMAJ %s" % InputPromptScript.action_text(&"dive_quiet_repair")
		_interaction_bar.visible = true
		_interaction_bar.value = clampf(_quiet_repair_progress / _quiet_repair_hold_seconds(), 0.0, 1.0)
		return
	_interaction_panel.visible = _interaction_target != null and not _loot_panel.visible and not _inventory_panel.visible and not _rescue_overlay.visible and not _attempt_failed
	if not _interaction_panel.visible:
		return
	var return_blocker := _tutorial_return_blocker()
	if _interaction_target is DiveExitLine and not return_blocker.is_empty():
		_interaction_label.text = (
			"POWRÓT ZABLOKOWANY  •  NAJPIERW PRZETNIJ BLOKADĘ KABLA"
			if tutorial_step() == TutorialStateScript.Step.ACTIVATE_JUNCTION_J7 and not _tutorial_cable_blockage_opened()
			else "POWRÓT ZABLOKOWANY  •  NAJPIERW URUCHOM WĘZEŁ J-7"
		)
		_interaction_bar.visible = false
		_interaction_bar.value = 0.0
		return
	_interaction_label.text = _interaction_target.interaction_text()
	var is_instant_pickup := _interaction_target is DiveWorldPickup
	_interaction_bar.visible = not is_instant_pickup
	if is_instant_pickup:
		_interaction_bar.value = 0.0
		return
	var required := maxf(float(_interaction_target.interaction_seconds), 0.01)
	_interaction_bar.value = clampf(_interaction_progress / required, 0.0, 1.0)

func _compact_objective_text() -> String:
	if setup == null:
		return ""
	if _rescue_system.is_towing(session):
		return "RATUNEK  •  WRÓĆ"
	if setup.tutorial_mode:
		if tutorial_step() == TutorialStateScript.Step.DIVE_BLOCKED_PASSAGE:
			var blockage: DivePersistentInteractable = _tutorial_cable_blockage()
			if blockage != null:
				var to_blockage: Vector2 = blockage.global_position - diver.global_position
				return "%s BLOKADA KABLA  %d m" % [_direction_symbol(to_blockage), int(to_blockage.length() / 8.0)]
			return "CEL: BLOKADA KABLA"
		if tutorial_step() == TutorialStateScript.Step.ACTIVATE_JUNCTION_J7:
			if not _tutorial_cable_blockage_opened():
				var blockage: DivePersistentInteractable = _tutorial_cable_blockage()
				if blockage != null:
					var to_blockage: Vector2 = blockage.global_position - diver.global_position
					return "%s BLOKADA KABLA  %d m" % [_direction_symbol(to_blockage), int(to_blockage.length() / 8.0)]
				return "CEL: BLOKADA KABLA"
			var junction = _tutorial_junction_j7()
			if junction != null:
				var to_junction: Vector2 = junction.global_position - diver.global_position
				return "%s WĘZEŁ J-7  %d m" % [_direction_symbol(to_junction), int(to_junction.length() / 8.0)]
			return "CEL: WĘZEŁ J-7"
		if tutorial_step() == TutorialStateScript.Step.FINAL_RETURN_TO_LINE:
			return "CEL: LINA"
		var mandatory_count := _mandatory_container_count()
		if mandatory_count < 2:
			var tutorial_target := dive_map.objective_position(mandatory_count) - diver.global_position
			return "CEL %d m" % int(tutorial_target.length() / 8.0)
		return "CEL: LINA"
	if not setup.objective_target_landmark_id.is_empty() and game_state != null and game_state.underwater_world != null and game_state.underwater_world.blueprint != null:
		var landmark: Dictionary = game_state.underwater_world.blueprint.get_landmark(setup.objective_target_landmark_id)
		if not landmark.is_empty():
			var to_target: Vector2 = landmark.get("position", diver.global_position) - diver.global_position
			var target_name: String = str(setup.objective_target_label) if not setup.objective_target_label.is_empty() else str(landmark.get("short_name", landmark.get("display_name", setup.objective_target_landmark_id)))
			var direction := "←" if absf(to_target.x) >= absf(to_target.y) and to_target.x < 0.0 else "→" if absf(to_target.x) >= absf(to_target.y) else "↑" if to_target.y < 0.0 else "↓"
			return "%s %s  %d m" % [direction, target_name.to_upper(), int(to_target.length() / 8.0)]
	if not setup.objective_title.is_empty():
		return setup.objective_title.to_upper()
	return "CEL: POWRÓT"

func _objective_text() -> String:
	if setup == null:
		return ""
	if _rescue_system.is_towing(session):
		var survivor_name: String = session.towed_survivor.display_name if session.towed_survivor != null else "Ocalały"
		var definition = _active_rescue_definition()
		var speed_penalty := int(round((1.0 - _rescue_system.movement_multiplier(session, definition)) * 100.0))
		var oxygen_penalty := int(round((_rescue_system.oxygen_multiplier(session, definition) - 1.0) * 100.0))
		return "RATUNEK: %s  •  wróć do liny\nPrędkość -%d%%  •  zużycie tlenu +%d%%  •  narzędzia zablokowane" % [survivor_name, speed_penalty, oxygen_penalty]
	if setup.tutorial_mode:
		var count := _mandatory_container_count()
		if count < 2:
			var objective := dive_map.objective_position(count) - diver.global_position
			return "Cel: zasoby  •  %d m" % int(objective.length() / 8.0)
		if tutorial_step() == TutorialStateScript.Step.DIVE_BLOCKED_PASSAGE:
			return "Cel: podążaj za kablem i obejrzyj jego zablokowany odcinek."
		if tutorial_step() == TutorialStateScript.Step.ACTIVATE_JUNCTION_J7:
			if not _tutorial_cable_blockage_opened():
				return "Cel: przetnij blokadę kabla Nożem ratunkowym. Dopiero potem podążaj do Węzła J-7."
			return "Cel: uruchom Węzeł J-7. Do tego czasu główna lina nie kończy wyprawy."
		if tutorial_step() == TutorialStateScript.Step.FINAL_RETURN_TO_LINE:
			return "Cel: wróć do głównej liny. Bezpieczny powrót zapisze aktywację J-7."
	if not setup.objective_title.is_empty() or not setup.objective_guidance.is_empty():
		var heading := "MISJA: %s" % setup.objective_title if not setup.objective_title.is_empty() else "MISJA WYPRAWY"
		var detail: String = str(setup.objective_guidance)
		if not setup.objective_target_landmark_id.is_empty() and game_state != null and game_state.underwater_world != null and game_state.underwater_world.blueprint != null:
			var landmark: Dictionary = game_state.underwater_world.blueprint.get_landmark(setup.objective_target_landmark_id)
			if not landmark.is_empty():
				var to_target: Vector2 = landmark.get("position", diver.global_position) - diver.global_position
				var target_name: String = str(setup.objective_target_label) if not setup.objective_target_label.is_empty() else str(landmark.get("display_name", setup.objective_target_landmark_id))
				var direction := "←" if absf(to_target.x) >= absf(to_target.y) and to_target.x < 0.0 else "→" if absf(to_target.x) >= absf(to_target.y) else "↑" if to_target.y < 0.0 else "↓"
				var navigation := "%s  %s  •  %d m" % [direction, target_name, int(to_target.length() / 8.0)]
				detail = navigation if detail.is_empty() else "%s\n%s" % [detail, navigation]
		return heading if detail.is_empty() else "%s\n%s" % [heading, detail]
	return "Cel: wróć z łupem do liny"


func _tutorial_return_blocker() -> String:
	if (
		setup != null
		and setup.tutorial_mode
		and session != null
		and tutorial_step() >= TutorialStateScript.Step.DIVE_MOVEMENT
		and tutorial_step() < TutorialStateScript.Step.DIVE_RETURN_TO_LINE
	):
		return "Najpierw wykonaj bieżący krok samouczka i obejrzyj zablokowane przejście."
	if (
		setup != null
		and setup.tutorial_mode
		and session != null
		and tutorial_step() == TutorialStateScript.Step.ACTIVATE_JUNCTION_J7
	):
		if not _tutorial_cable_blockage_opened():
			return "Najpierw przetnij blokadę kabla Nożem ratunkowym."
		return "Najpierw uruchom Węzeł J-7, a potem wróć do głównej liny."
	return ""


func _tutorial_cable_blockage() -> DivePersistentInteractable:
	if dive_map == null:
		return null
	for target in dive_map.persistent_interactables:
		if target != null and target.kind == DivePersistentInteractable.Kind.SHORTCUT and target.persistent_id == TUTORIAL_CABLE_BLOCKAGE_ID:
			return target
	return null


func _tutorial_cable_blockage_opened() -> bool:
	return session != null and session.opened_shortcuts.has(TUTORIAL_CABLE_BLOCKAGE_ID)


func _tutorial_junction_j7() -> DivePersistentInteractable:
	if dive_map == null:
		return null
	for target in dive_map.persistent_interactables:
		if target != null and target.kind == DivePersistentInteractable.Kind.FIXED_DEVICE and target.persistent_id == "junction_j7":
			return target
	return null


func _direction_symbol(to_target: Vector2) -> String:
	if absf(to_target.x) >= absf(to_target.y):
		return "←" if to_target.x < 0.0 else "→"
	return "↑" if to_target.y < 0.0 else "↓"


func _update_quiet_repair(delta: float) -> void:
	var held := Input.is_action_pressed(&"dive_quiet_repair", true)
	if not held:
		_quiet_repair_progress = 0.0
		_quiet_repair_blocked_until_release = false
		return
	if _quiet_repair_blocked_until_release:
		return

	var just_started := Input.is_action_just_pressed(&"dive_quiet_repair", true)
	if _rescue_system.is_towing(session):
		if just_started:
			_show_status("Cicha naprawa jest niedostępna podczas holowania.", 2.2)
		_quiet_repair_progress = 0.0
		_quiet_repair_blocked_until_release = true
		return
	var interrupted := (
		diver.movement_input.length_squared() > 0.01
		or diver.velocity.length_squared() > STATIONARY_VELOCITY_EPSILON_SQUARED
		or Input.is_action_pressed(&"dive_interact")
		or Input.is_action_pressed(&"dive_attack")
		or Input.is_action_just_pressed(&"dive_repair", true)
	)
	if interrupted:
		if just_started:
			_show_status("Cicha naprawa wymaga pełnego bezruchu i wolnych rąk.", 2.2)
		_quiet_repair_progress = 0.0
		_quiet_repair_blocked_until_release = true
		return

	var blocker := _risk_runtime.repair_blocker(
		session,
		setup,
		DiveRiskRuntimeScript.REPAIR_MODE_QUIET
	)
	if not blocker.is_empty():
		if just_started:
			_show_status(blocker, 2.2)
		_quiet_repair_progress = 0.0
		_quiet_repair_blocked_until_release = true
		return

	_quiet_repair_progress += maxf(delta, 0.0)
	if _quiet_repair_progress < _quiet_repair_hold_seconds():
		return
	var repair: Dictionary = _risk_runtime.try_repair_suit(
		session,
		setup,
		diver.global_position,
		DiveRiskRuntimeScript.REPAIR_MODE_QUIET
	)
	_quiet_repair_progress = 0.0
	_quiet_repair_blocked_until_release = true
	if bool(repair.get("success", false)):
		diver.play_visual_cue(&"repair", diver.visual_socket_global(&"leak_valve"), 0.82)
	_sync_diver_visual_context()
	_show_status(str(repair.get("message", "")), 3.0 if bool(repair.get("success", false)) else 1.8)


func _update_scout(delta: float) -> void:
	var query := Callable(dive_map, "scout_signal_at").bind(
		diver.global_position,
		_scout_talent_parameter("detection_radius", DiveScoutRuntimeScript.FALLBACK_MAXIMUM_DISTANCE),
		_scout_talent_parameter("strong_current_threshold", DiveScoutRuntimeScript.FALLBACK_MINIMUM_CURRENT_SPEED)
	)
	_scout_signal = _scout_runtime.advance(
		_scout_is_eligible(),
		delta,
		query,
		_scout_talent_parameter("stationary_seconds", DiveScoutRuntimeScript.FALLBACK_REVEAL_SECONDS)
	)
	_update_scout_label()


func _scout_is_eligible() -> bool:
	return (
		ProfessionTalentSystemScript.has_talent(setup, "nurek_zwiadowca")
		and not _is_diver_light_active()
		and not _rescue_system.is_towing(session)
		and not diver.is_sprinting
		and diver.movement_input.length_squared() <= 0.01
		and diver.velocity.length_squared() <= STATIONARY_VELOCITY_EPSILON_SQUARED
		and _interaction_progress <= 0.0
		and _quiet_repair_progress <= 0.0
		and not Input.is_action_pressed(&"dive_interact")
		and not Input.is_action_pressed(&"dive_attack")
		and not Input.is_action_pressed(&"dive_quiet_repair", true)
		and not Input.is_action_just_pressed(&"dive_repair", true)
		and not Input.is_action_just_pressed(&"dive_light_toggle")
	)


func _update_scout_label() -> void:
	if _scout_label == null:
		return
	if _scout_signal.is_empty():
		_scout_label.text = ""
		return
	var kind := str(_scout_signal.get("kind", ""))
	var category := "ZAGROŻENIE" if kind == "threat" else "SILNY PRĄD" if kind == "current" else ""
	if category.is_empty():
		_scout_label.text = ""
		return
	_scout_label.text = "%s  %s" % [
		_direction_symbol_8(_scout_signal.get("direction", Vector2.ZERO)),
		category,
	]


func _direction_symbol_8(direction: Vector2) -> String:
	var absolute := direction.abs()
	if absolute.x > absolute.y * 2.41421356:
		return "←" if direction.x < 0.0 else "→"
	if absolute.y > absolute.x * 2.41421356:
		return "↑" if direction.y < 0.0 else "↓"
	if direction.y < 0.0:
		return "↖" if direction.x < 0.0 else "↗"
	return "↙" if direction.x < 0.0 else "↘"


func _cancel_talent_actions() -> void:
	_quiet_repair_progress = 0.0
	_quiet_repair_blocked_until_release = Input.is_action_pressed(&"dive_quiet_repair", true)
	_scout_runtime.reset()
	_scout_signal.clear()
	_update_scout_label()


func _quiet_repair_hold_seconds() -> float:
	var definition = _profession_talent_system.get_definition("nurek_technik_glebinowy")
	return maxf(
		float(definition.parameters.get("hold_seconds", 1.8)) if definition != null else 1.8,
		0.01
	)


func _scout_talent_parameter(parameter_id: String, fallback: float) -> float:
	var definition = _profession_talent_system.get_definition("nurek_zwiadowca")
	return float(definition.parameters.get(parameter_id, fallback)) if definition != null else fallback

func _configure_lighting() -> void:
	var light_id := str(setup.equipped_gear.get("light", "")) if setup != null else ""
	_dive_lighting_definition = GameDatabase.dive_lighting if GameDatabase != null else null
	_equipped_light_definition = GameDatabase.diving_gear.get(light_id) if GameDatabase != null and not light_id.is_empty() else null
	if _equipped_light_definition == null and not light_id.is_empty():
		var path := "res://data/diving_gear/%s.tres" % light_id
		_equipped_light_definition = ResourceLoader.load(path) if ResourceLoader.exists(path) else null
	var configured := _light_system.configure(
		ambient_darkness,
		diver_light,
		_equipped_light_definition,
		session != null and bool(session.light_enabled),
		_dive_lighting_definition
	)
	if session != null and not configured:
		session.light_enabled = false


func _toggle_diver_light() -> void:
	if session == null:
		return
	if _equipped_light_definition == null or not _equipped_light_definition.is_valid_light():
		session.light_enabled = false
		_apply_diver_light_state()
		_show_status("Nie wyposażono latarni. Wybierz ją przed wyprawą w Stacji Nurkowej.", 2.8)
		return
	session.light_enabled = not session.light_enabled
	_apply_diver_light_state()
	_show_status("Latarnia włączona." if session.light_enabled else "Latarnia wyłączona.", 1.8)


func _apply_diver_light_state() -> void:
	if session == null:
		return
	if _equipped_light_definition == null or not _equipped_light_definition.is_valid_light():
		session.light_enabled = false
	_light_system.set_light_enabled(diver_light, _equipped_light_definition, session.light_enabled)


func _is_diver_light_active() -> bool:
	return session != null \
		and bool(session.light_enabled) \
		and _equipped_light_definition != null \
		and _equipped_light_definition.is_valid_light()


func _update_environment_lighting(delta: float = 0.0) -> void:
	if ambient_darkness == null or dive_map == null or diver == null:
		return
	_light_system.update_ambient(
		ambient_darkness,
		dive_map.depth_at(diver.global_position),
		_dive_lighting_definition
	)
	if _underwater_environment != null:
		var depth_ratio := clampf(dive_map.depth_at(diver.global_position) / 160.0, 0.0, 1.0)
		var visual_context: Dictionary = dive_map.visual_context_at(diver.global_position) if dive_map.has_method("visual_context_at") else {}
		var visual_profile = visual_context.get("profile")
		_underwater_environment.update_environment(
			depth_ratio,
			visual_context.get("water_color", Color(0.035, 0.20, 0.26, 1.0)),
			visual_context.get("accent_color", Color(0.18, 0.75, 0.80, 1.0)),
			_active_current_vector,
			diver.global_position,
			maxf(delta, 0.0),
			float(visual_profile.get("water_clarity")) if visual_profile != null else 0.7,
			float(visual_profile.get("suspended_particle_density")) if visual_profile != null else 0.35,
			float(visual_profile.get("caustics_strength")) if visual_profile != null else 0.35
		)


func _build_underwater_environment() -> void:
	if _underwater_environment != null and is_instance_valid(_underwater_environment):
		return
	_underwater_environment = UnderwaterEnvironmentScript.new()
	_underwater_environment.name = "UnderwaterEnvironment"
	add_child(_underwater_environment)
	_configure_underwater_environment()


func _configure_underwater_environment() -> void:
	if _underwater_environment == null or not is_instance_valid(_underwater_environment):
		return
	_underwater_environment.configure(
		dive_map.world_size() if dive_map != null else Vector2(11_520.0, 6_480.0),
		dive_map.terrain_visual_profiles() if dive_map != null and dive_map.has_method("terrain_visual_profiles") else []
	)

func _build_current_visual() -> void:
	if _current_visual != null and is_instance_valid(_current_visual):
		return
	_current_visual = DiveCurrentVisualScript.new()
	_current_visual.name = "CurrentVisual"
	add_child(_current_visual)
	if _current_visual.has_method("set_reduced_motion"):
		_current_visual.set_reduced_motion(_reduced_motion)

func _update_current_presentation(delta: float, snap_transition: bool = false) -> void:
	if dive_map == null or diver == null:
		return
	if not _current_visual_sample_override:
		_active_current_vector = dive_map.current_at(diver.global_position) * _difficulty_modifier("current_strength_multiplier")
	if _current_visual == null or not is_instance_valid(_current_visual):
		_build_current_visual()
	var world_anchor := diver.global_position
	var camera := diver.get_node_or_null("Camera2D") as Camera2D
	if camera != null and camera.is_inside_tree():
		world_anchor = camera.get_screen_center_position()
	_current_visual.update_sample(_active_current_vector, world_anchor, delta, snap_transition)


func _streaming_visible_half_extent() -> Vector2:
	var viewport_rect := get_viewport_rect()
	var corners := PackedVector2Array([
		viewport_rect.position,
		Vector2(viewport_rect.end.x, viewport_rect.position.y),
		viewport_rect.end,
		Vector2(viewport_rect.position.x, viewport_rect.end.y),
	])
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for corner in corners:
		var local_corner := dive_map.make_canvas_position_local(corner)
		minimum = minimum.min(local_corner)
		maximum = maximum.max(local_corner)
	var view_center := (minimum + maximum) * 0.5
	return (maximum - minimum) * 0.5 + (view_center - diver.global_position).abs()

func set_current_visual_sample_for_tests(current_vector: Vector2, time_seconds: float) -> void:
	_current_visual_sample_override = true
	_active_current_vector = current_vector
	if _current_visual == null or not is_instance_valid(_current_visual):
		_build_current_visual()
	var world_anchor := diver.global_position
	var camera := diver.get_node_or_null("Camera2D") as Camera2D
	if camera != null and camera.is_inside_tree():
		world_anchor = camera.get_screen_center_position()
	_current_visual.update_sample(_active_current_vector, world_anchor, 0.0, true)
	_current_visual.set_visual_time_for_tests(time_seconds, true)
	_update_ui()

func current_visual():
	return _current_visual


func _sync_diver_visual_context(suppress_action: bool = false) -> void:
	if diver == null or session == null:
		return
	var leak_intensity := 0.0
	var suit_condition := clampi(int(session.suit_condition), 0, 100)
	if suit_condition < SuitSystemScript.LEAK_START_CONDITION:
		var damage_ratio := inverse_lerp(
			float(SuitSystemScript.LEAK_START_CONDITION),
			0.0,
			float(suit_condition)
		)
		leak_intensity = lerpf(0.22, 1.0, damage_ratio)

	var interaction_action: StringName = &""
	var interaction_progress := 0.0
	if not suppress_action and _quiet_repair_progress > 0.0:
		interaction_action = &"repair"
		interaction_progress = clampf(
			_quiet_repair_progress / maxf(_quiet_repair_hold_seconds(), 0.01),
			0.0,
			1.0
		)
	elif not suppress_action and _interaction_target != null and _interaction_progress > 0.0:
		interaction_action = StringName(str(_interaction_target.get("interaction_action")))
		interaction_progress = clampf(
			_interaction_progress / maxf(float(_interaction_target.get("interaction_seconds")), 0.01),
			0.0,
			1.0
		)
	diver.set_visual_context(
		leak_intensity,
		interaction_action,
		interaction_progress,
		_rescue_system.is_towing(session)
	)


func _show_status(message: String, seconds: float) -> void:
	_status_message = message
	_status_message_time = seconds

func _attempt_suit_repair() -> void:
	_quiet_repair_progress = 0.0
	if _rescue_system.is_towing(session):
		_show_status("Podczas holowania nie możesz puścić ocalałego, aby użyć zestawu naprawczego.", 2.8)
		return
	var repair: Dictionary = _risk_runtime.try_repair_suit(
		session,
		setup,
		diver.global_position,
		DiveRiskRuntimeScript.REPAIR_MODE_STANDARD
	)
	if bool(repair.get("success", false)):
		diver.play_visual_cue(&"repair", diver.visual_socket_global(&"leak_valve"))
	_sync_diver_visual_context()
	_show_status(str(repair.get("message", "")), 3.0 if bool(repair.get("success", false)) else 1.8)

func _required_tool_for(target) -> String:
	if target is DiveLootContainer:
		return str(target.required_tool)
	if target is DivePersistentInteractable:
		return str(target.required_tool)
	if target is DiveRescueSurvivor:
		return str(target.required_tool)
	return ""

func _required_tool_display_name(target, tool_id: String) -> String:
	if target != null and target.has_method("required_tool_display_name"):
		return str(target.required_tool_display_name())
	return tool_id.replace("_", " ")

func _diver_display_name() -> String:
	if setup == null:
		return "Nurek"
	if not setup.diver_display_name.is_empty():
		return setup.diver_display_name
	var resident = game_state.find_survivor(setup.diver_id) if game_state != null else null
	return resident.display_name if resident != null else setup.diver_id.capitalize()

func _calculate_dive_experience() -> int:
	var reward := 20
	reward += session.carried_item_order.size() * 5
	reward += maxi(_discovered_landmarks_this_dive.size() - 1, 0) * 3
	if setup != null and setup.tutorial_mode:
		reward += 15
	if _rescue_system.is_towing(session):
		reward += 25
	return reward

func _active_rescue_definition():
	if _towed_rescue_node != null and is_instance_valid(_towed_rescue_node):
		return _towed_rescue_node.definition
	return null

func _make_panel(fill: Color, border: Color, width: int = 1) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _margin_content(parent: Control, amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", amount)
	margin.add_theme_constant_override("margin_top", amount)
	margin.add_theme_constant_override("margin_right", amount)
	margin.add_theme_constant_override("margin_bottom", amount)
	parent.add_child(margin)
	return margin
