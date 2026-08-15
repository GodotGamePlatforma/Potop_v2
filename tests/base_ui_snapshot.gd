extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const DiveTutorialOutcomeScript := preload("res://scripts/data/DiveTutorialOutcome.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const TutorialDirectorScript := preload("res://scripts/core/TutorialDirector.gd")
const SettlementEventStateScript := preload("res://scripts/data/SettlementEventState.gd")
const SettlementEventSystemScript := preload("res://scripts/base/SettlementEventSystem.gd")
const BuildingPresentationScript := preload("res://scripts/base/BuildingPresentation.gd")

const CAPTURE_RESOLUTION := Vector2i(1280, 720)

func _ready() -> void:
	# Keep native OS cursor placement from changing hover visuals in golden PNGs.
	# All interactions in this harness emit their signals programmatically.
	get_viewport().gui_disable_input = true
	var game = GameRootScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	game.start_new_campaign("standard", 101, false)
	await get_tree().process_frame
	await get_tree().process_frame
	await _freeze_base_environment(game.current_scene, 1.7)
	var base_scene = game.current_scene
	var resource_bar := base_scene.find_child("ResourceBar", true, false) as Control
	var resource_summary := base_scene.find_child("ResourceSummary", true, false) as RichTextLabel
	var weather_badge: Node = base_scene.find_child("WeatherBadge", true, false)
	var weather_label: Node = base_scene.find_child("WeatherLabel", true, false)
	var crew_button := base_scene.find_child("CrewButton", true, false) as Button
	var crew_panel := base_scene.find_child("SurvivorsPanel", true, false) as Control
	var plan_button := base_scene.find_child("DayPlanButton", true, false) as Button
	var plan_popover := base_scene.find_child("DayPlanPopover", true, false) as Control
	var tutorial_panel := base_scene.find_child("TutorialPanel", true, false) as Control
	var initial_hud_summary := resource_summary.get_parsed_text().replace(" ", "") if resource_summary != null else ""
	if resource_bar == null or resource_bar.size.y > 54.0 or resource_summary == null or not initial_hud_summary.contains("POMOST70%│3/3MIESZKAŃCÓW") or weather_badge != null or weather_label != null or crew_button == null or crew_panel == null or crew_panel.visible or plan_button == null or plan_popover == null or plan_popover.visible:
		push_error("The world-first base HUD should keep a <=54 px top bar, show shelter occupancy after the pier, omit weather, and keep both detailed flyouts closed by default.")
		get_tree().quit(1)
		return
	crew_button.emit_signal("pressed")
	await get_tree().process_frame
	if not crew_panel.visible or tutorial_panel == null or crew_panel.get_global_rect().intersects(tutorial_panel.get_global_rect()):
		push_error("Opening the crew flyout should preserve a readable, non-overlapping tutorial callout.")
		get_tree().quit(1)
		return
	plan_button.emit_signal("pressed")
	await get_tree().process_frame
	if crew_panel.visible or not plan_popover.visible or plan_popover.get_global_rect().intersects(tutorial_panel.get_global_rect()):
		push_error("Opening the day-plan popover should close the crew flyout and restore the tutorial opposite the popover.")
		get_tree().quit(1)
		return
	plan_button.emit_signal("pressed")
	await get_tree().process_frame
	var community_slot = base_scene.find_child("Slot_top_right", true, false)
	if not _tutorial_glow_matches(base_scene, community_slot, "top_right", "Ruin_top_right"):
		push_error("Day-one tutorial should use an amber ruin-silhouette glow with a fully transparent slot rectangle.")
		get_tree().quit(1)
		return
	if not await _save_snapshot("base_day1.png"):
		return

	community_slot.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var community_build_button := base_scene.find_child("BuildButton", true, false) as Button
	if community_build_button == null or community_build_button.disabled:
		push_error("The current day-one tutorial should allow rebuilding Community House I before the Diving Station.")
		get_tree().quit(1)
		return
	community_build_button.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var community = game.game_state.find_building_by_definition("community_house")
	if community == null or not community.is_active() or game.game_state.tutorial.step != TutorialStateScript.Step.BUILD_DIVING_STATION:
		push_error("Rebuilding Community House I should activate it immediately and advance the tutorial to the Diving Station.")
		get_tree().quit(1)
		return
	var community_hud_summary := resource_summary.get_parsed_text().replace(" ", "") if resource_summary != null else ""
	if not community_hud_summary.contains("POMOST70%│3/4MIESZKAŃCÓW"):
		push_error("Community House I should immediately raise the HUD shelter counter from 3/3 to 3/4 after the pier integrity.")
		get_tree().quit(1)
		return
	base_scene._hide_action_feedback()
	await _freeze_base_environment(base_scene, 1.7)
	var station_slot = base_scene.find_child("Slot_bottom_right", true, false)
	if not _tutorial_glow_matches(base_scene, station_slot, "bottom_right", "Ruin_bottom_right"):
		push_error("After Community House I, the same amber silhouette glow should move to the Diving Station ruin.")
		get_tree().quit(1)
		return

	station_slot.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var building_workspace := base_scene.find_child("BuildingManagementWorkspace", true, false) as Control
	var building_panel := base_scene.find_child("BuildingPanel", true, false) as Control
	var modal_focus := get_viewport().gui_get_focus_owner()
	if building_workspace == null or not building_workspace.visible or building_panel == null or building_panel.size.x < 720.0 or modal_focus == null or not building_workspace.is_ancestor_of(modal_focus):
		push_error("The building management workspace should expose a wide action panel and keep keyboard focus inside its modal scope.")
		get_tree().quit(1)
		return
	var construction_benefits := base_scene.find_child("ConstructionBenefitsLabel", true, false) as Label
	if (
		construction_benefits == null
		or not construction_benefits.text.contains("6 miejsc")
		or not construction_benefits.text.contains("Umożliwia wyprawy")
		or not construction_benefits.text.contains("Kombinezon poziomu 1")
	):
		push_error("The construction panel should state the concrete level-one Station benefits before resources are committed.")
		get_tree().quit(1)
		return
	if not await _save_snapshot("base_build_panel.png"):
		return

	var build_button = base_scene.find_child("BuildButton", true, false)
	build_button.emit_signal("pressed")
	await get_tree().process_frame
	if get_viewport().gui_get_focus_owner() != station_slot:
		push_error("Closing building management after an action should restore focus to the originating slot.")
		get_tree().quit(1)
		return
	var construction_presentation = base_scene.find_child("Presentation_bottom_right", true, false)
	var action_feedback = base_scene.find_child("BaseActionFeedback", true, false)
	var action_feedback_label := base_scene.find_child("BaseActionFeedbackLabel", true, false) as Label
	if (
		construction_presentation == null
		or int(construction_presentation.visual_state) != BuildingPresentationScript.VisualState.ACTIVE_UNSTAFFED
		or construction_presentation.is_blueprint_visible()
		or action_feedback == null
		or not action_feedback.visible
		or action_feedback_label == null
		or action_feedback_label.text != "ODBUDOWANO  •  Stacja Nurkowa\nBudynek jest aktywny od razu."
	):
		push_error("Rebuilding the unstaffed Station should show its active-unassigned presentation immediately, without a blueprint, and retain the exact success feedback.")
		get_tree().quit(1)
		return
	if not await _save_snapshot("base_station_built.png"):
		return
	base_scene._hide_action_feedback()

	community_slot.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var community_worker_change := base_scene.find_child("WorkerChangeButton", true, false) as Button
	if community_worker_change == null or community_worker_change.disabled:
		push_error("The active Community House should expose its current tile-based worker assignment flow.")
		get_tree().quit(1)
		return
	community_worker_change.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var mira_worker_candidate := base_scene.find_child("WorkerCandidate_mira", true, false) as Button
	if mira_worker_candidate == null or mira_worker_candidate.disabled:
		push_error("Mira should be an available Community House worker in the day-one tutorial fixture.")
		get_tree().quit(1)
		return
	mira_worker_candidate.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	if community.assigned_survivor_ids != ["mira"] or game.game_state.tutorial.step != TutorialStateScript.Step.SET_RATIONS:
		push_error("Assigning Mira to Community House I should persist the roster and advance the tutorial to the explicit ration choice.")
		get_tree().quit(1)
		return
	var staffed_community_hud_summary := resource_summary.get_parsed_text().replace(" ", "") if resource_summary != null else ""
	if not staffed_community_hud_summary.contains("POMOST70%│3/4MIESZKAŃCÓW"):
		push_error("The HUD shelter counter must count residents, not Community House worker assignments.")
		get_tree().quit(1)
		return
	base_scene._close_building_panel()
	base_scene._hide_action_feedback()
	await get_tree().process_frame
	plan_button.emit_signal("pressed")
	await get_tree().process_frame
	var ration_picker := base_scene.find_child("RationPolicyPicker", true, false) as OptionButton
	if ration_picker == null or ration_picker.item_count < 2 or ration_picker.is_item_disabled(1):
		push_error("The day-one tutorial should expose an explicit full-rations choice after staffing Community House I.")
		get_tree().quit(1)
		return
	ration_picker.select(1)
	ration_picker.emit_signal("item_selected", 1)
	await get_tree().process_frame
	await get_tree().process_frame
	if game.game_state.tutorial.step != TutorialStateScript.Step.END_FIRST_DAY:
		push_error("Selecting full rations explicitly should unlock the end of tutorial day one.")
		get_tree().quit(1)
		return
	var end_day_button = base_scene.find_child("EndDayButton", true, false)
	end_day_button.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	base_scene = game.current_scene
	await _freeze_base_environment(base_scene, 1.7)
	var day_summary = base_scene.find_child("DaySummaryOverlay", true, false)
	var day_summary_title := base_scene.find_child("DaySummaryTitle", true, false) as Label
	var day_summary_continue := base_scene.find_child("DaySummaryContinueButton", true, false) as Button
	if day_summary == null or not day_summary.visible or day_summary_title == null or day_summary_title.text != "DZIEŃ 1 ZAKOŃCZONY" or day_summary_continue == null:
		push_error("Ending a day without a dive should show the modal summary for the completed day.")
		get_tree().quit(1)
		return
	if not await _save_snapshot("base_day1_summary.png"):
		return
	day_summary_continue.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	base_scene = game.current_scene
	await _freeze_base_environment(base_scene, 1.7)
	var workshop_slot = base_scene.find_child("Slot_bottom_left", true, false)
	if not _tutorial_glow_matches(base_scene, workshop_slot, "bottom_left", "Ruin_bottom_left"):
		push_error("Day two should begin with the amber tutorial glow on the Workshop ruin.")
		get_tree().quit(1)
		return
	workshop_slot.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var workshop_build_button := base_scene.find_child("BuildButton", true, false) as Button
	if workshop_build_button == null or workshop_build_button.disabled:
		push_error("The tutorial supply package should allow rebuilding Workshop I on day two.")
		get_tree().quit(1)
		return
	workshop_build_button.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var workshop = game.game_state.find_building_by_definition("workshop")
	if workshop == null or not workshop.is_active() or game.game_state.tutorial.step != TutorialStateScript.Step.ASSIGN_DIVER_FIRST:
		push_error("Rebuilding Workshop I should activate it immediately and advance the tutorial to selecting Igor as diver.")
		get_tree().quit(1)
		return
	base_scene._hide_action_feedback()
	await _freeze_base_environment(base_scene, 1.7)
	station_slot = base_scene.find_child("Slot_bottom_right", true, false)
	if not _tutorial_glow_matches(base_scene, station_slot, "bottom_right", "Built_bottom_right_L1"):
		push_error("After Workshop I, the day-two diver tutorial should move the same amber glow to the built Station silhouette.")
		get_tree().quit(1)
		return
	if not await _save_snapshot("base_day2_station.png"):
		return

	await _freeze_base_environment(base_scene, 1.7)
	station_slot.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var empty_profile = base_scene.find_child("DiverProfilePanel", true, false)
	var igor_candidate := base_scene.find_child("DiverCandidate_igor", true, false) as Button
	var current_level_benefits := base_scene.find_child("CurrentLevelBenefitsLabel", true, false) as Label
	var empty_staff_contribution := base_scene.find_child("StaffContributionLabel", true, false) as Label
	var empty_worker_effect := base_scene.find_child("WorkerEffectLabel", true, false) as Label
	if (
		empty_profile == null
		or igor_candidate == null
		or igor_candidate.disabled
		or not str(game.game_state.current_day_plan.selected_diver_id).is_empty()
		or current_level_benefits == null
		or not current_level_benefits.text.contains("6 miejsc")
		or not current_level_benefits.text.contains("Kombinezon poziomu 1")
		or empty_staff_contribution == null
		or not empty_staff_contribution.text.contains("Nurek: brak")
		or empty_worker_effect == null
		or not empty_worker_effect.text.contains("0")
		or not empty_worker_effect.text.contains("nieobsadzone")
	):
		push_error("Diving Station HUD should show an empty diver profile, an available Igor candidate and an independent unstaffed support rail.")
		get_tree().quit(1)
		return
	if not await _save_snapshot("base_assignment_panel.png"):
		return

	igor_candidate.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var diver_name = base_scene.find_child("DiverNameLabel", true, false) as Label
	var health_bar = base_scene.find_child("DiverHealthBar", true, false) as ProgressBar
	var oxygen_bar = base_scene.find_child("DiverOxygenBar", true, false) as ProgressBar
	var carry_bar = base_scene.find_child("DiverCarryBar", true, false) as ProgressBar
	var traits_label = base_scene.find_child("DiverTraitsLabel", true, false) as Label
	var states_label = base_scene.find_child("DiverStatesLabel", true, false) as Label
	var oxygen_tank_picker = base_scene.find_child("OxygenTankGearPicker", true, false) as OptionButton
	var light_picker = base_scene.find_child("LightGearPicker", true, false) as OptionButton
	var dive_button = base_scene.find_child("DiveButton", true, false) as Button
	var staffed_staff_contribution := base_scene.find_child("StaffContributionLabel", true, false) as Label
	var staffed_worker_effect := base_scene.find_child("WorkerEffectLabel", true, false) as Label
	if diver_name == null or diver_name.text != "Igor Sowa" or health_bar == null or health_bar.value != 100.0:
		push_error("Diving Station HUD should bind the assigned diver name and health from SurvivorState.")
		get_tree().quit(1)
		return
	if oxygen_bar == null or not is_equal_approx(oxygen_bar.value, 125.0) or carry_bar == null or carry_bar.value != 18.0 or traits_label == null or not traits_label.text.contains("+10%") or states_label == null:
		push_error("Diving Station HUD should expose oxygen capacity, carry capacity, traits and current survivor states.")
		get_tree().quit(1)
		return
	if oxygen_tank_picker == null or oxygen_tank_picker.item_count != 1 or str(oxygen_tank_picker.get_selected_metadata()) != "oxygen_tank_mk1":
		push_error("A new campaign should expose the equipped Oxygen Tank I in the Station HUD.")
		get_tree().quit(1)
		return
	if light_picker == null or light_picker.item_count < 1 or dive_button == null or dive_button.disabled:
		push_error("A valid diver should be able to equip the starting oxygen tank and lantern, then start the dive from the Station HUD.")
		get_tree().quit(1)
		return
	if (
		staffed_staff_contribution == null
		or not staffed_staff_contribution.text.contains("Igor Sowa")
		or not staffed_staff_contribution.text.contains("125 jednostek tlenu")
		or not staffed_staff_contribution.text.contains("6 miejsc")
		or staffed_worker_effect == null
		or not staffed_worker_effect.text.contains("stanowisko nieobsadzone")
	):
		push_error("Selecting Igor should quantify the expedition while leaving the independent Station support role explicitly unstaffed.")
		get_tree().quit(1)
		return
	var modal_feedback := base_scene.find_child("BaseActionFeedback", true, false) as Control
	resource_bar = base_scene.find_child("ResourceBar", true, false) as Control
	building_panel = base_scene.find_child("BuildingPanel", true, false) as Control
	tutorial_panel = base_scene.find_child("TutorialPanel", true, false) as Control
	var building_modal := base_scene.find_child("BuildingModal", true, false) as Control
	var feedback_rect := modal_feedback.get_global_rect() if modal_feedback != null else Rect2()
	var panel_rect := building_panel.get_global_rect() if building_panel != null else Rect2()
	var viewport_rect := get_viewport().get_visible_rect()
	if modal_feedback == null or not modal_feedback.visible or resource_bar == null or building_panel == null or tutorial_panel == null or building_modal == null or not feedback_rect.size.is_equal_approx(Vector2(312.0, 62.0)) or absf(feedback_rect.get_center().x - viewport_rect.get_center().x) > 1.0 or not feedback_rect.intersects(panel_rect) or modal_feedback.z_index <= building_modal.z_index or feedback_rect.intersects(resource_bar.get_global_rect()) or feedback_rect.intersects(tutorial_panel.get_global_rect()) or modal_feedback.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		push_error("Diver-selection feedback must be a compact, centered, input-transparent toast layered over the management panel without covering resources or tutorial. Feedback=%s panel=%s resource=%s tutorial=%s z=%d/%d mouse_filter=%d" % [feedback_rect, panel_rect, resource_bar.get_global_rect() if resource_bar != null else Rect2(), tutorial_panel.get_global_rect() if tutorial_panel != null else Rect2(), modal_feedback.z_index if modal_feedback != null else -1, building_modal.z_index if building_modal != null else -1, modal_feedback.mouse_filter if modal_feedback != null else -1])
		get_tree().quit(1)
		return
	if not await _save_snapshot("base_dive_ready.png"):
		return

	dive_button.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	if game.current_scene == null or game.current_scene.name != "DiveScene":
		push_error("Tutorial UI did not transition to DiveScene.")
		get_tree().quit(1)
		return
	if game.game_state.current_expedition_setup == null or not is_equal_approx(game.game_state.current_expedition_setup.oxygen_capacity, 125.0):
		push_error("The oxygen capacity shown for a diver specialist must match ExpeditionSetup.")
		get_tree().quit(1)
		return
	if game.game_state.current_expedition_setup.diver_carry_capacity != 18.0 or game.game_state.current_expedition_setup.item_weights.size() < 6 or str(game.game_state.current_expedition_setup.equipped_gear.get("oxygen_tank", "")) != "oxygen_tank_mk1":
		push_error("ExpeditionSetup should snapshot the selected diver's carry capacity, loot weights and equipped oxygen tank.")
		get_tree().quit(1)
		return
	# The dive frame is only a transition checkpoint in this base-flow harness,
	# but its bubble emitter must still be deterministic when it is persisted.
	_prepare_gpu_particles(game.current_scene)
	_seek_gpu_particles(game.current_scene, 1.7)
	await _render_barriers(2)
	if not await _save_snapshot("dive_scene.png"):
		return
	if game.game_state.tutorial.step != TutorialStateScript.Step.START_FIRST_DIVE or not game.current_scene.has_method("tutorial_step") or int(game.current_scene.tutorial_step()) != TutorialStateScript.Step.DIVE_MOVEMENT:
		push_error("The dive session should begin with movement while the campaign keeps its transactional first-dive baseline.")
		get_tree().quit(1)
		return

	var result = DiveResultScript.new()
	result.diver_id = "igor"
	result.returned_alive = true
	result.oxygen_remaining = 35.0
	result.health_remaining = 82
	result.suit_condition_remaining = 68
	result.cold_exposure = 34.0
	result.dive_duration = 187.0
	result.experience_gained = 25
	result.diver_injuries.assign(["hypothermia"])
	result.add_item("food", 3)
	result.add_item("planks", 2)
	result.tutorial_completed = true
	var tutorial_outcome = DiveTutorialOutcomeScript.new()
	tutorial_outcome.baseline_step = TutorialStateScript.Step.START_FIRST_DIVE
	tutorial_outcome.final_step = TutorialStateScript.Step.DIVE_RETURN_TO_LINE
	tutorial_outcome.event_ids.assign([
		TutorialDirectorScript.DIVE_STARTED,
		TutorialDirectorScript.MOVEMENT_COMPLETED,
		TutorialDirectorScript.OXYGEN_EXPLAINED,
		TutorialDirectorScript.MANDATORY_CONTAINER_OPENED,
		TutorialDirectorScript.MANDATORY_LOOT_COMPLETED,
		TutorialDirectorScript.BLOCKED_PASSAGE_SEEN,
	])
	result.tutorial_outcome = tutorial_outcome
	if not game.finish_dive(result):
		push_error("The deterministic snapshot result should satisfy the typed first-dive transaction contract.")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if game.game_state.day != 3 or game.current_scene == null or game.current_scene.name != "BaseScene":
		push_error("Returning from the first dive should automatically resolve the day and return to the base on day three.")
		get_tree().quit(1)
		return
	base_scene = game.current_scene
	await _freeze_base_environment(base_scene, 1.7)
	day_summary = base_scene.find_child("DaySummaryOverlay", true, false)
	day_summary_title = base_scene.find_child("DaySummaryTitle", true, false) as Label
	day_summary_continue = base_scene.find_child("DaySummaryContinueButton", true, false) as Button
	if day_summary == null or not day_summary.visible or day_summary_title == null or day_summary_title.text != "DZIEŃ 2 ZAKOŃCZONY" or day_summary_continue == null:
		push_error("Returning from a dive should show the previous day's summary before base planning resumes.")
		get_tree().quit(1)
		return
	if not await _save_snapshot("base_day2_dive_summary.png"):
		return
	_install_population_event_for_snapshot(game, base_scene)
	day_summary_continue.emit_signal("pressed")
	await get_tree().process_frame
	var settlement_event = base_scene.find_child("SettlementEventOverlay", true, false)
	var settlement_event_title := base_scene.find_child("SettlementEventTitle", true, false) as Label
	var settlement_event_accept := base_scene.find_child("SettlementEventChoice_accept", true, false) as Button
	var settlement_event_reject := base_scene.find_child("SettlementEventChoice_reject", true, false) as Button
	if game.game_state.current_phase != GamePhaseScript.Phase.DAY_START_REPORT or day_summary.visible or settlement_event == null or not settlement_event.visible:
		push_error("The summary action should reveal the saved morning event before base planning.")
		get_tree().quit(1)
		return
	if settlement_event_title == null or not settlement_event_title.text.contains("DWOJE") or settlement_event_accept == null or settlement_event_reject == null:
		push_error("The morning event snapshot should contain the authored card and both decisions.")
		get_tree().quit(1)
		return
	if not await _save_snapshot("base_day3_settlement_event.png"):
		return
	settlement_event_accept.emit_signal("pressed")
	await get_tree().process_frame
	if game.game_state.current_phase != GamePhaseScript.Phase.BASE_PLANNING or settlement_event.visible:
		push_error("Resolving the event should dismiss the modal and resume base planning.")
		get_tree().quit(1)
		return
	var report_journal_button := base_scene.find_child("DayReportJournalButton", true, false) as Button
	if report_journal_button == null or report_journal_button.disabled:
		push_error("The report archive should be available after both mandatory morning modals are resolved.")
		get_tree().quit(1)
		return
	report_journal_button.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var report_journal := base_scene.find_child("DayReportJournalOverlay", true, false) as Control
	var report_journal_title := base_scene.find_child("DayReportJournalTitle", true, false) as Label
	var report_journal_entries = base_scene.find_child("DayReportJournalEntries", true, false)
	var report_journal_warnings = base_scene.find_child("DayReportJournalWarnings", true, false)
	var report_day_one := base_scene.find_child("DayReportJournalDay_1", true, false) as Button
	var report_day_two := base_scene.find_child("DayReportJournalDay_2", true, false) as Button
	if report_journal == null or not report_journal.visible or report_journal_title == null or report_journal_title.text != "DZIEŃ 2" or report_journal_entries == null or report_journal_warnings == null or report_day_one == null or report_day_two == null:
		push_error("The report archive should open newest-first with both completed tutorial days available.")
		get_tree().quit(1)
		return
	if not _joined_label_text(report_journal_entries).contains("Z wyprawy odzyskano") or not _joined_label_text(report_journal_warnings).contains("wychłodzony"):
		push_error("The newest archive selection should show the day-two expedition entries and warning snapshot.")
		get_tree().quit(1)
		return
	if not await _save_snapshot("base_day3_report_journal.png"):
		return
	report_day_one.emit_signal("pressed")
	await get_tree().process_frame
	if report_journal_title.text != "DZIEŃ 1" or not report_day_one.button_pressed or report_day_two.button_pressed:
		push_error("Selecting an older report should update both the detail title and the selected day button.")
		get_tree().quit(1)
		return
	if not _joined_label_text(report_journal_entries).contains("Tego dnia nie zorganizowano wyprawy") or _joined_label_text(report_journal_warnings).contains("wychłodzony"):
		push_error("Selecting day one should replace both entries and warnings with its detached no-dive report.")
		get_tree().quit(1)
		return
	var report_journal_close := base_scene.find_child("DayReportJournalCloseButton", true, false) as Button
	if report_journal_close == null:
		push_error("The optional report archive should have an explicit close action.")
		get_tree().quit(1)
		return
	report_journal_close.emit_signal("pressed")
	await get_tree().process_frame
	if report_journal.visible:
		push_error("Closing the report archive should restore the unobstructed base.")
		get_tree().quit(1)
		return

	print("Base UI snapshots saved; manual/post-dive summaries, the morning event and the report archive were verified.")
	get_tree().quit(0)

func _freeze_base_environment(base_scene: Node, animation_time: float) -> void:
	if base_scene == null:
		return
	_prepare_gpu_particles(base_scene)
	if base_scene.has_method("set_animation_time_for_tests"):
		base_scene.set_animation_time_for_tests(animation_time)
	else:
		var environment = base_scene.find_child("BaseEnvironment", true, false)
		if environment != null and environment.has_method("set_animation_time_for_tests"):
			environment.set_animation_time_for_tests(animation_time)
	_seek_gpu_particles(base_scene, animation_time)
	await _render_barriers(2)


func _render_barriers(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw


func _prepare_gpu_particles(root: Node) -> void:
	var particle_index := 0
	for particle_node in root.find_children("*", "GPUParticles3D", true, false):
		var particles := particle_node as GPUParticles3D
		particles.use_fixed_seed = true
		particles.seed = 73_251 + particle_index * 977
		particles.preprocess = 0.0
		particles.speed_scale = 0.0
		# Collision-only child pools are deliberately dormant. Restarting them
		# would turn exact contact effects back into autonomous origin particles.
		if not particles.one_shot and particles.emitting:
			particles.restart(true)
		particle_index += 1
	for particle_node in root.find_children("*", "GPUParticles2D", true, false):
		var particles_2d := particle_node as GPUParticles2D
		particles_2d.use_fixed_seed = true
		particles_2d.seed = 73_251 + particle_index * 977
		particles_2d.preprocess = 0.0
		particles_2d.speed_scale = 0.0
		if not particles_2d.one_shot:
			particles_2d.restart(true)
		particle_index += 1


func _seek_gpu_particles(root: Node, animation_time: float) -> void:
	for particle_node in root.find_children("*", "GPUParticles3D", true, false):
		var particles := particle_node as GPUParticles3D
		if particles.one_shot:
			if particles.emitting:
				particles.request_particles_process(minf(0.22, particles.lifetime * 0.35))
		else:
			particles.request_particles_process(animation_time)
	for particle_node in root.find_children("*", "GPUParticles2D", true, false):
		var particles_2d := particle_node as GPUParticles2D
		if particles_2d.one_shot:
			if particles_2d.emitting:
				particles_2d.request_particles_process(minf(0.22, particles_2d.lifetime * 0.35))
		else:
			particles_2d.request_particles_process(animation_time)


func _install_population_event_for_snapshot(game, base_scene: Node) -> void:
	# Dobór karty i jego rozkład mają własne testy domenowe. Snapshot potrzebuje
	# jednej stabilnej, autorskiej karty niezależnie od zmian wag i profilu presji.
	var state = game.game_state
	var definition = GameDatabase.settlement_events.get("survivors_on_horizon")
	var pending_event = SettlementEventStateScript.new()
	var offer_snapshot = SettlementEventSystemScript.new().build_offer_snapshot(state, definition, GameDatabase.survivor_templates)
	pending_event.setup_offer(offer_snapshot, int(state.day))
	state.pending_settlement_event = pending_event
	state.settlement_event_roll_day = int(state.day)
	if state.pressure_state != null:
		state.pressure_state.quiet_morning = false
		state.pressure_state.committed_event_id = str(definition.id)
		state.pressure_state.committed_event_tone = str(definition.tone)
		state.pressure_state.committed_event_severity = int(definition.severity)
		state.pressure_state.spent_pressure_budget = float(definition.pressure_cost)
		state.pressure_state.refresh_debug_summary()
	if base_scene != null and base_scene.has_method("bind"):
		base_scene.bind(game, state)

func _joined_label_text(root: Node) -> String:
	var lines: Array[String] = []
	for child in root.get_children():
		if child is Label:
			lines.append((child as Label).text)
		lines.append(_joined_label_text(child))
	return "\n".join(lines)


func _tutorial_glow_matches(base_scene: Node, target_slot: Control, expected_slot_id: String, expected_variant_prefix: String) -> bool:
	if base_scene == null or target_slot == null:
		return false
	var environment = base_scene.find_child("BaseEnvironment", true, false)
	if environment == null or not environment.has_method("building_highlight_state_for_tests"):
		return false
	var blur_viewport := environment.get_node_or_null("BuildingHighlightBlurViewport") as SubViewport
	if blur_viewport == null or not _soft_glow_mask_has_pixels(blur_viewport.get_texture().get_image()):
		return false
	var state: Dictionary = environment.building_highlight_state_for_tests()
	if not bool(state.get("active", false)) or str(state.get("slot_id", "")) != expected_slot_id or StringName(state.get("mode", &"none")) != &"tutorial":
		return false
	if int(state.get("viewport_update_mode", -1)) != SubViewport.UPDATE_ALWAYS or int(state.get("blur_viewport_update_mode", -1)) != SubViewport.UPDATE_ALWAYS or not bool(state.get("transparent_background", false)) or not bool(state.get("shared_world", false)) or not bool(state.get("camera_transform_synced", false)):
		return false
	var glow_color := Color(state.get("glow_color", Color.TRANSPARENT))
	if glow_color.r <= 0.9 or glow_color.r <= glow_color.g or glow_color.g <= glow_color.b or glow_color.a <= 0.8:
		return false
	var pad := target_slot.get_node_or_null("PadVisual") as Panel
	var pad_style := pad.get_theme_stylebox("panel") as StyleBoxFlat if pad != null else null
	if pad_style == null or pad_style.bg_color.a > 0.0001 or pad_style.border_color.a > 0.0001:
		return false
	var world_state: Dictionary = state.get("world", {})
	var meshes: Array = world_state.get("meshes", [])
	if meshes.is_empty() or int(world_state.get("mesh_count", 0)) != meshes.size():
		return false
	for mesh_value in meshes:
		var mesh_state: Dictionary = mesh_value
		if not str(mesh_state.get("node_name", "")).begins_with(expected_variant_prefix) or not bool(mesh_state.get("highlight_layer", false)):
			return false
	return true


func _soft_glow_mask_has_pixels(image: Image) -> bool:
	if image == null or image.is_empty():
		return false
	var transparent_samples := 0
	var soft_samples := 0
	var opaque_samples := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var alpha := image.get_pixel(x, y).a
			if alpha <= 0.001:
				transparent_samples += 1
			elif alpha < 0.98:
				soft_samples += 1
			else:
				opaque_samples += 1
	return opaque_samples > 20 and soft_samples > 20 and transparent_samples > opaque_samples + soft_samples


func _save_snapshot(file_name: String) -> bool:
	# A logical state transition can complete before the viewport texture is
	# redrawn. Capture only after the renderer has presented the new frame.
	await _render_barriers(1)
	var image := get_viewport().get_texture().get_image()
	if image.get_size() != CAPTURE_RESOLUTION:
		push_error(
			"Base UI snapshot %s has invalid size %s instead of %s."
			% [file_name, str(image.get_size()), str(CAPTURE_RESOLUTION)]
		)
		get_tree().quit(1)
		return false
	var output_directory := ProjectSettings.globalize_path("res://tmp")
	if not DirAccess.dir_exists_absolute(output_directory):
		var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
		if directory_error != OK:
			push_error("Could not create the base UI snapshot directory. Error: %d" % directory_error)
			get_tree().quit(1)
			return false
	var error := image.save_png(output_directory.path_join(file_name))
	if error != OK:
		push_error("Could not save base UI snapshot. Error: %d" % error)
		get_tree().quit(1)
		return false
	return true
