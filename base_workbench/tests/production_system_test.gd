extends SceneTree

const TEST_ROUNDTRIP_PATH := "user://test_workshop_order_roundtrip.tres"
const KNOWN_TEST_OUTPUT_GEAR_IDS: Array[String] = ["diving_lantern_mk2"]
const TEST_HEAVY_OBJECT_ID := "fixture_heavy_object"

const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const EndOfDayResolverScript := preload("res://scripts/campaign/EndOfDayResolver.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const ProductionSystemScript := preload("res://base_workbench/systems/ProductionSystem.gd")
const ReportStateScript := preload("res://scripts/data/ReportState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const WorkshopOrderStateScript := preload("res://scripts/data/WorkshopOrderState.gd")
const WorkPaceSystemScript := preload("res://base_workbench/systems/WorkPaceSystem.gd")

const TALENT_MATERIAL_RECOVERY := "mechanik_odzysk_materialu"

var _failed := false


func _initialize() -> void:
	_cleanup_roundtrip()
	_test_queue_snapshots_recipe_and_sequence()
	_test_r3_campaign_order_uses_authored_cost_and_work()
	_test_splitter_campaign_order_uses_authored_cost_and_work()
	_test_refund_uses_reserved_snapshot_exactly_once()
	_test_invalid_front_order_is_preserved()
	_test_zero_point_queue_outcomes_fall_through_priorities()
	_test_positive_production_blocks_lower_priorities_and_commits_work()
	_test_work_pace_contract()
	_test_work_point_budget_by_pace()
	_test_material_recovery_is_forecast_and_committed_once()
	_test_local_order_and_building_validation()
	_test_building_resource_roundtrip()
	_cleanup_roundtrip()
	if _failed:
		quit(1)
		return
	print("Production system test passed: durable progress, 75/100/125 work-point budgets, exact refunds, guarded FIFO, validation and Resource roundtrip work.")
	quit(0)


func _test_material_recovery_is_forecast_and_committed_once() -> void:
	var state = _new_state(4, 23)
	var workshop = state.find_building_by_definition("workshop")
	var production = ProductionSystemScript.new()
	_assert(production.queue_recipe(state, workshop, production.get_recipe("diving_lantern_mk2")), "Material-recovery fixture must queue its first qualifying order.")
	_assert(production.queue_recipe(state, workshop, production.get_recipe("oxygen_tank_mk2")), "Material-recovery fixture must queue its second qualifying order.")
	var scrap_before_analysis: int = state.resources.get_amount(ResourceIdsScript.SCRAP)
	var talent_ids: Array[String] = [TALENT_MATERIAL_RECOVERY]
	var analysis: Dictionary = production.analyze_workshop_queue(
		state,
		WorkPaceSystemScript.WORK_PACE_NORMAL,
		null,
		talent_ids
	)
	var completion_refunds: Array[int] = []
	for action in analysis.get("actions", []):
		if str(action.get("kind", "")) == "complete":
			completion_refunds.append(int(action.get("material_recovery_scrap_refund", 0)))
	_assert(
		int(analysis.get("completed", 0)) == 2
		and completion_refunds == [1, 0]
		and int(analysis.get("material_recovery_scrap_refund", 0)) == 1
		and int(analysis.get("refunded_cost", {}).get(ResourceIdsScript.SCRAP, 0)) == 1
		and state.resources.get_amount(ResourceIdsScript.SCRAP) == scrap_before_analysis,
		"Odzysk materiału forecast must mark only the first completed order with reserved scrap >= 2 and remain pure."
	)
	var resolution: Dictionary = production.resolve_workshop_queue(
		state,
		ReportStateScript.new(),
		WorkPaceSystemScript.WORK_PACE_NORMAL,
		null,
		talent_ids
	)
	_assert(
		int(resolution.get("completed", 0)) == 2
		and int(resolution.get("material_recovery_scrap_refund", 0)) == 1
		and state.resources.get_amount(ResourceIdsScript.SCRAP) == scrap_before_analysis + 1,
		"Odzysk materiału settlement must commit the exact one-scrap forecast once despite multiple qualifying completions."
	)

	var progress_state = _new_state(1, 24)
	var progress_workshop = progress_state.find_building_by_definition("workshop")
	_assert(production.queue_recipe(progress_state, progress_workshop, production.get_recipe("diving_lantern_mk2")), "Progress-only material-recovery fixture must queue one qualifying order.")
	var progress_analysis: Dictionary = production.analyze_workshop_queue(
		progress_state,
		WorkPaceSystemScript.WORK_PACE_CAREFUL,
		null,
		talent_ids
	)
	_assert(
		int(progress_analysis.get("points_applied", 0)) == 75
		and int(progress_analysis.get("completed", 0)) == 0
		and int(progress_analysis.get("material_recovery_scrap_refund", -1)) == 0,
		"Odzysk materiału must never refund scrap for progress without a completed order."
	)

	var cancel_state = _new_state(1, 25)
	var cancel_workshop = cancel_state.find_building_by_definition("workshop")
	_assert(production.queue_recipe(cancel_state, cancel_workshop, production.get_recipe("diving_lantern_mk2")), "Cancellation material-recovery fixture must queue one qualifying order.")
	_assert(cancel_state.diving_equipment.add_gear("diving_lantern_mk2"), "Cancellation fixture must make its queued output redundant.")
	var cancel_analysis: Dictionary = production.analyze_workshop_queue(
		cancel_state,
		WorkPaceSystemScript.WORK_PACE_NORMAL,
		null,
		talent_ids
	)
	_assert(
		int(cancel_analysis.get("canceled", 0)) == 1
		and int(cancel_analysis.get("completed", 0)) == 0
		and int(cancel_analysis.get("material_recovery_scrap_refund", -1)) == 0
		and int(cancel_analysis.get("refunded_cost", {}).get(ResourceIdsScript.SCRAP, 0)) == 4,
		"Odzysk materiału must not add its one-scrap completion refund to an ordinary cancellation refund."
	)


func _test_r3_campaign_order_uses_authored_cost_and_work() -> void:
	var state = _new_state(2, 8)
	var workshop = state.find_building_by_definition("workshop")
	var production = ProductionSystemScript.new()
	var recipe = production.get_recipe("r3_regulator")
	state.story_flags.r3_diagnosed = true
	state.story_flags.r3_diagnosed_day = 8
	state.story_flags.set_flag("r3_diagnosed", true)
	var before := _resource_snapshot(state)
	_assert(recipe != null and recipe.required_workshop_level == 2 and recipe.required_work_points == 200, "R-3 recipe must require Workshop II and exactly 200 work points.")
	_assert(production.queue_recipe(state, workshop, recipe), "A diagnosed R-3 should expose one queueable campaign order.")
	var order = workshop.queued_production_orders[0]
	_assert(order.output_campaign_id == "r3_regulator" and order.output_gear_id.is_empty() and order.required_work_points == 200, "R-3 must be a campaign output, not diving gear.")
	_assert(_resource_delta(before, _resource_snapshot(state)) == {"fabric_rubber": 3, "scrap": 6, "tech_parts": 2}, "R-3 must reserve the exact authored material cost once.")
	var first := production.resolve_workshop_queue(state, ReportStateScript.new())
	_assert(first.points_applied == 100 and order.work_progress == 100 and not state.story_flags.r3_regulator_ready, "Workshop II Normal must leave R-3 at 100/200 after one day.")
	var second := production.resolve_workshop_queue(state, ReportStateScript.new())
	_assert(second.completed == 1 and state.story_flags.r3_regulator_ready and state.story_flags.r3_regulator_completed_day == 8, "The second 100-point day must complete the durable R-3 regulator exactly once.")


func _test_splitter_campaign_order_uses_authored_cost_and_work() -> void:
	var state = _new_state(3, 9)
	var workshop = state.find_building_by_definition("workshop")
	var production = ProductionSystemScript.new()
	var recipe = production.get_recipe("common_line_splitter")
	state.story_flags.c4_switchboard_active = true
	state.story_flags.c4_switchboard_activated_day = 9
	state.story_flags.set_flag("c4_switchboard_active", true)
	var before := _resource_snapshot(state)
	_assert(recipe != null and recipe.required_workshop_level == 3 and recipe.required_work_points == 400, "Splitter must require Workshop III and exactly 400 work points.")
	_assert(production.queue_recipe(state, workshop, recipe), "An active C-4 should expose one queueable Splitter order.")
	_assert(_resource_delta(before, _resource_snapshot(state)) == {"fabric_rubber": 5, "scrap": 10, "tech_parts": 4}, "Splitter must reserve the exact authored material cost once.")
	var first := production.resolve_workshop_queue(state, ReportStateScript.new())
	_assert(first.points_applied == 200 and not state.story_flags.common_line_splitter_ready, "Workshop III Normal must leave the Splitter at 200/400 after one day.")
	var second := production.resolve_workshop_queue(state, ReportStateScript.new())
	_assert(second.completed == 1 and state.story_flags.common_line_splitter_ready and state.story_flags.common_line_splitter_completed_day == 9, "The second 200-point day must complete the durable Splitter exactly once.")


func _test_queue_snapshots_recipe_and_sequence() -> void:
	var state = _new_state(4, 7)
	var workshop = state.find_building_by_definition("workshop")
	var production = ProductionSystemScript.new()
	var recipe = production.get_recipe("diving_lantern_mk2").duplicate(true)
	var resources_before := _resource_snapshot(state)

	_assert(production.queue_recipe(state, workshop, recipe), "A valid recipe should create a durable Workshop order.")
	_assert(workshop.queued_production_orders.size() == 1, "A successful queue operation should append exactly one canonical order.")
	_assert(workshop.next_production_order_sequence == 2, "The next sequence should advance only after a successful queue operation.")
	var order = workshop.queued_production_orders[0]
	_assert(order.get_script() == WorkshopOrderStateScript, "The canonical queue should contain exactly typed WorkshopOrderState resources.")
	_assert(order.instance_id == "workshop_order:test_workshop:1", "A new order should carry the owner-scoped sequence ID.")
	_assert(order.recipe_id == "diving_lantern_mk2" and order.output_gear_id == "diving_lantern_mk2", "The order should freeze both historical recipe ID and executable output target.")
	_assert(order.output_display_name == "Latarnia nurkowa II" and order.queued_day == 7, "The order should freeze player copy and the real queue day.")
	_assert(order.reserved_cost == {"fabric_rubber": 2, "scrap": 4, "tech_parts": 1}, "The order should freeze the exact reserved material cost.")
	_assert(_resource_delta(resources_before, _resource_snapshot(state)) == order.reserved_cost, "Queueing should reserve exactly the snapshotted cost.")
	var after_successful_queue := _resource_snapshot(state)
	_assert(not production.queue_recipe(state, workshop, recipe), "A duplicate pending output should be rejected.")
	_assert(_resource_snapshot(state) == after_successful_queue and workshop.queued_production_orders.size() == 1 and workshop.next_production_order_sequence == 2, "A failed queue operation must not change resources, FIFO or sequence.")

	recipe.id = "removed_live_recipe"
	recipe.output_gear_id = "missing_live_target"
	recipe.display_name = "Zmieniona nazwa live"
	recipe.craft_cost = {"scrap": 99}
	var report = ReportStateScript.new()
	var resolution: Dictionary = production.resolve_workshop_queue(state, report)
	_assert(resolution.completed == 1 and resolution.worked, "Completion should use the stored order after the live recipe changes or disappears.")
	_assert(resolution.points_budget == 300 and resolution.points_applied == 100, "A level-4 Workshop should expose its full point budget and spend only the points required by the queue.")
	_assert(state.diving_equipment.owns("diving_lantern_mk2"), "Completion should add the snapshotted output instead of the changed live target.")
	_assert(workshop.queued_production_orders.is_empty(), "A successful completion should remove only the completed FIFO order.")
	_assert(_contains_fragment(report.entries, "Latarnia nurkowa II"), "The completion report should use frozen output copy.")
	_assert(not _contains_fragment(report.entries, "Zmieniona nazwa live"), "Changed live copy must not reinterpret a queued order.")

	_assert(state.diving_equipment.remove_gear("diving_lantern_mk2"), "The sequence regression needs the completed gear removed before requeueing.")
	var canonical_recipe = production.get_recipe("diving_lantern_mk2")
	_assert(production.queue_recipe(state, workshop, canonical_recipe), "A later order should be queueable after the previous target is no longer owned.")
	_assert(workshop.queued_production_orders[0].instance_id == "workshop_order:test_workshop:2", "Completed sequence numbers must never be reused.")
	_assert(workshop.next_production_order_sequence == 3, "The monotonic sequence should advance past the second order.")


func _test_refund_uses_reserved_snapshot_exactly_once() -> void:
	var state = _new_state(4, 9)
	var workshop = state.find_building_by_definition("workshop")
	var production = ProductionSystemScript.new()
	var recipe = production.get_recipe("oxygen_tank_mk2").duplicate(true)
	recipe.display_name = "Butla z migawki"
	recipe.craft_cost = {"scrap": 2, "fabric_rubber": 1, "tech_parts": 3}
	var resources_before := _resource_snapshot(state)

	_assert(production.queue_recipe(state, workshop, recipe), "A replacement gear recipe should reserve its current authored cost.")
	var reserved_cost: Dictionary = workshop.queued_production_orders[0].reserved_cost.duplicate(true)
	recipe.display_name = "Późniejsza nazwa"
	recipe.craft_cost = {"scrap": 90, "fabric_rubber": 80, "tech_parts": 70}
	_assert(state.diving_equipment.add_gear("oxygen_tank_mk2"), "The refund regression should simulate recovering the original gear before production.")
	var order_fingerprint_before := _order_fingerprint(workshop)
	var resources_before_analysis := _resource_snapshot(state)
	var analysis: Dictionary = production.analyze_workshop_queue(state)
	_assert(not analysis.worked and analysis.canceled == 1 and analysis.points_applied == 0, "A redundant FIFO head should be planned as a zero-point cancellation, not as production.")
	_assert(_order_fingerprint(workshop) == order_fingerprint_before and _resource_snapshot(state) == resources_before_analysis, "Queue analysis must not refund resources, remove orders or change progress.")
	var report = ReportStateScript.new()
	var resolution: Dictionary = production.resolve_workshop_queue(state, report)
	_assert(resolution.completed == 0 and not resolution.worked and resolution.points_applied == 0, "Cancelling a redundant order should neither count as production nor consume work points.")
	_assert(workshop.queued_production_orders.is_empty(), "A fully refunded redundant order should leave the FIFO.")
	_assert(_resource_snapshot(state) == resources_before, "Refunding should restore exactly the cost captured when the order was queued.")
	_assert(reserved_cost == {"scrap": 2, "fabric_rubber": 1, "tech_parts": 3}, "The stored refund must remain independent from later recipe edits.")
	_assert(_contains_fragment(report.warnings, "Butla z migawki"), "The cancellation report should use the frozen display name.")
	_assert(not _contains_fragment(report.warnings, "Późniejsza nazwa"), "The cancellation report must not read changed live copy.")
	var after_first_refund := _resource_snapshot(state)
	production.resolve_workshop_queue(state, report)
	_assert(_resource_snapshot(state) == after_first_refund, "Resolving again must not refund a removed order twice.")


func _test_invalid_front_order_is_preserved() -> void:
	var state = _new_state(4, 11)
	var workshop = state.find_building_by_definition("workshop")
	var blocked_order = WorkshopOrderStateScript.new()
	blocked_order.setup(
		"workshop_order:test_workshop:1",
		"retired_recipe",
		"missing_gear_target",
		"Zamrożony brakujący cel",
		{"scrap": 3},
		11
	)
	var valid_order = WorkshopOrderStateScript.new()
	valid_order.setup(
		"workshop_order:test_workshop:2",
		"diving_lantern_mk2",
		"diving_lantern_mk2",
		"Latarnia nurkowa II",
		{"scrap": 4, "fabric_rubber": 2, "tech_parts": 1},
		11
	)
	workshop.queued_production_orders.assign([blocked_order, valid_order])
	workshop.next_production_order_sequence = 3
	var resources_before := _resource_snapshot(state)
	var report = ReportStateScript.new()
	var production = ProductionSystemScript.new()
	var fingerprint_before := _order_fingerprint(workshop)
	var analysis: Dictionary = production.analyze_workshop_queue(state)
	_assert(analysis.blocked and not analysis.worked and analysis.points_applied == 0, "A controlled invalid FIFO head should be forecast as blocked with zero real work.")
	_assert(_order_fingerprint(workshop) == fingerprint_before and _resource_snapshot(state) == resources_before, "Analyzing a blocked head must leave queue, progress and resources untouched.")
	var resolution: Dictionary = production.resolve_workshop_queue(state, report)

	_assert(resolution.completed == 0 and not resolution.worked and resolution.blocked, "A missing executable output target should not count as completed work.")
	_assert(resolution.points_applied == 0, "A blocked FIFO head must preserve the complete point budget without mutating progress.")
	_assert(workshop.queued_production_orders.size() == 2 and workshop.queued_production_orders[0] == blocked_order, "An invalid front order should remain reserved and block FIFO instead of being deleted or skipped.")
	_assert(not state.diving_equipment.owns("diving_lantern_mk2"), "FIFO must not jump over a blocked front order.")
	_assert(_resource_snapshot(state) == resources_before, "A controlled target error must not mutate reserved resources.")
	_assert(_contains_fragment(report.warnings, "zachował zlecenie") and _contains_fragment(report.warnings, "missing_gear_target"), "The report should expose the controlled reason while preserving the order.")


func _test_zero_point_queue_outcomes_fall_through_priorities() -> void:
	var heavy_state = _new_state(3, 19)
	var heavy_workshop = heavy_state.find_building_by_definition("workshop")
	var blocked_order = WorkshopOrderStateScript.new()
	blocked_order.setup(
		"workshop_order:test_workshop:1",
		"retired_recipe",
		"missing_gear_target",
		"Zamrożony brakujący cel",
		{"scrap": 3},
		19
	)
	heavy_workshop.queued_production_orders.append(blocked_order)
	heavy_workshop.next_production_order_sequence = 2
	_add_test_heavy_object(heavy_state)
	heavy_state.underwater_world.marked_heavy_objects.append(TEST_HEAVY_OBJECT_ID)
	var heavy_report = ReportStateScript.new()
	var heavy_resolver = EndOfDayResolverScript.new()
	heavy_resolver._capture_capable_worker_snapshot(heavy_state)
	heavy_resolver._resolve_workshop_and_repairs(heavy_state, heavy_report)
	_assert(heavy_workshop.queued_production_orders.size() == 1 and heavy_workshop.queued_production_orders[0] == blocked_order, "A controlled blocked order should stay reserved after the lower-priority task runs.")
	_assert(not heavy_state.underwater_world.marked_heavy_objects.has(TEST_HEAVY_OBJECT_ID) and heavy_state.underwater_world.recovered_heavy_objects.has(TEST_HEAVY_OBJECT_ID), "Zero production points from a blocked head should allow one marked heavy object to be recovered.")
	_assert(_contains_fragment(heavy_report.warnings, "missing_gear_target") and _contains_fragment(heavy_report.entries, "wydobył ciężki obiekt"), "The report should expose both the preserved order error and the real heavy-recovery task.")

	var repair_state = _new_state(1, 20)
	var repair_workshop = repair_state.find_building_by_definition("workshop")
	var production = ProductionSystemScript.new()
	_assert(production.queue_recipe(repair_state, repair_workshop, production.get_recipe("diving_lantern_mk2")), "The repair fallback fixture should reserve one valid order.")
	_assert(repair_state.diving_equipment.add_gear("diving_lantern_mk2"), "The queued output should become redundant before resolution.")
	repair_state.resources.set_amount(ResourceIdsScript.SCRAP, 0)
	repair_state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 40)
	var repair_report = ReportStateScript.new()
	var repair_resolver = EndOfDayResolverScript.new()
	repair_resolver._capture_capable_worker_snapshot(repair_state)
	repair_resolver._resolve_workshop_and_repairs(repair_state, repair_report)
	_assert(repair_workshop.queued_production_orders.is_empty(), "A redundant head should be refunded and removed exactly once before the fallback task.")
	_assert(repair_state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY) > 40, "A zero-point refund should fund and allow the same-day platform repair even when no scrap was available before cancellation.")
	_assert(_contains_fragment(repair_report.warnings, "Anulowano produkcję") and _contains_fragment(repair_report.entries, "Warsztat naprawił platformę"), "The report should describe the refund and the actual repair instead of claiming production.")


func _test_positive_production_blocks_lower_priorities_and_commits_work() -> void:
	var state = _new_state(3, 21)
	var workshop = state.find_building_by_definition("workshop")
	workshop.work_pace = WorkPaceSystemScript.WORK_PACE_CAREFUL
	workshop.work_tension = 2
	var production = ProductionSystemScript.new()
	_assert(production.queue_recipe(state, workshop, production.get_recipe("diving_lantern_mk2")), "The positive-priority fixture should queue a first canonical order.")
	_assert(production.queue_recipe(state, workshop, production.get_recipe("oxygen_tank_mk2")), "The positive-priority fixture should queue a second order for partial overflow.")
	state.current_day_plan.sync_from_state(state)
	_add_test_heavy_object(state)
	var heavy_spawns: Array = state.underwater_world.blueprint.heavy_object_spawns
	_assert(not heavy_spawns.is_empty(), "The positive-priority fixture needs one canonical heavy object.")
	if heavy_spawns.is_empty():
		return
	var heavy_id := str(heavy_spawns[0].get("id", ""))
	state.underwater_world.marked_heavy_objects.append(heavy_id)
	state.resources.set_amount(ResourceIdsScript.PLATFORM_INTEGRITY, 40)
	var report = ReportStateScript.new()
	var resolver = EndOfDayResolverScript.new()
	resolver._capture_capable_worker_snapshot(state)
	resolver._resolve_workshop_and_repairs(state, report)
	_assert(workshop.queued_production_orders.size() == 1 and workshop.queued_production_orders[0].work_progress == 50, "A careful two-slot Workshop should complete the FIFO head and preserve fifty overflow points on the next order.")
	_assert(state.underwater_world.marked_heavy_objects.has(heavy_id) and not state.underwater_world.recovered_heavy_objects.has(heavy_id), "Any positive production progress should block heavy recovery for that day.")
	_assert(state.resources.get_amount(ResourceIdsScript.PLATFORM_INTEGRITY) == 40, "Any positive production progress should also block the lower platform repair.")
	_assert(resolver._committed_work_events.size() == 1 and str(resolver._committed_work_events[0].get("action_id", "")) == "craft_diving_gear", "Positive partial production should create exactly one real Workshop work event.")
	resolver._resolve_fatigue(state, null, report)
	resolver._resolve_work_tension(state, report)
	_assert(state.find_survivor("anka").fatigue == 4, "The committed careful production shift should charge its worker four fatigue exactly once.")
	_assert(workshop.work_tension == 0, "The committed careful production shift should relieve two local Workshop tension.")
	_assert(_contains_fragment(report.entries, "50/100 punktów pracy") and _contains_fragment(report.entries, "Napięcie pracy"), "The report should expose both partial production and its real local tension transition.")


func _test_work_point_budget_by_pace() -> void:
	var careful_state = _new_state(1, 12)
	var careful_workshop = careful_state.find_building_by_definition("workshop")
	var production = ProductionSystemScript.new()
	_assert(production.queue_recipe(careful_state, careful_workshop, production.get_recipe("diving_lantern_mk2")), "The careful pace fixture should queue one valid order.")
	var careful_result: Dictionary = production.resolve_workshop_queue(
		careful_state,
		ReportStateScript.new(),
		WorkPaceSystemScript.WORK_PACE_CAREFUL
	)
	_assert(careful_result.points_budget == 75 and careful_result.points_applied == 75, "Careful pace should provide exactly 75 work points for one production slot.")
	_assert(careful_result.worked and careful_result.completed == 0, "Applying a partial careful budget should count as real work without completing the order.")
	_assert(careful_workshop.queued_production_orders[0].work_progress == 75, "Unused completion progress should remain durably attached to the FIFO order.")

	var normal_state = _new_state(1, 13)
	var normal_workshop = normal_state.find_building_by_definition("workshop")
	_assert(production.queue_recipe(normal_state, normal_workshop, production.get_recipe("diving_lantern_mk2")), "The normal pace fixture should queue one valid order.")
	var normal_result: Dictionary = production.resolve_workshop_queue(
		normal_state,
		ReportStateScript.new(),
		WorkPaceSystemScript.WORK_PACE_NORMAL
	)
	_assert(normal_result.points_budget == 100 and normal_result.points_applied == 100, "Normal pace should provide exactly 100 work points for one production slot.")
	_assert(normal_result.worked and normal_result.completed == 1 and normal_workshop.queued_production_orders.is_empty(), "A normal one-slot budget should complete exactly one fresh order.")

	var intense_state = _new_state(2, 14)
	var intense_workshop = intense_state.find_building_by_definition("workshop")
	_assert(production.queue_recipe(intense_state, intense_workshop, production.get_recipe("diving_lantern_mk2")), "The intense pace fixture should queue its first valid order.")
	_assert(production.queue_recipe(intense_state, intense_workshop, production.get_recipe("oxygen_tank_mk2")), "The level-2 fixture should queue a second valid order for overflow work.")
	var intense_result: Dictionary = production.resolve_workshop_queue(
		intense_state,
		ReportStateScript.new(),
		WorkPaceSystemScript.WORK_PACE_INTENSE
	)
	_assert(intense_result.points_budget == 125 and intense_result.points_applied == 125, "Intense pace should provide exactly 125 work points for one production slot.")
	_assert(intense_result.completed == 1 and intense_workshop.queued_production_orders.size() == 1, "An intense one-slot budget should finish the FIFO head and retain the next order.")
	_assert(intense_workshop.queued_production_orders[0].work_progress == 25, "The 25-point intense overflow should persist on the next FIFO order.")

	var competent_state = _new_state(2, 15)
	var competent_workshop = competent_state.find_building_by_definition("workshop")
	competent_state.find_survivor("anka").competency_levels["production"] = 3
	_assert(production.queue_recipe(competent_state, competent_workshop, production.get_recipe("harpoon_pistol")), "The production-competency fixture should queue one two-day order.")
	var competent_result: Dictionary = production.resolve_workshop_queue(
		competent_state,
		ReportStateScript.new(),
		WorkPaceSystemScript.WORK_PACE_NORMAL
	)
	_assert(competent_result.points_budget == 115 and competent_result.points_applied == 115, "Production III must raise a capable worker's normal Workshop budget from 100 to exactly 115 points.")
	_assert(competent_workshop.queued_production_orders[0].work_progress == 115, "The competency-adjusted production budget must be committed to the canonical FIFO order.")


func _test_work_pace_contract() -> void:
	_assert(
		WorkPaceSystemScript.valid_paces() == ["careful", "normal", "intense"],
		"The shared pace contract should expose exactly the three canonical IDs in UI order."
	)
	_assert(WorkPaceSystemScript.normalize_pace("invalid") == WorkPaceSystemScript.WORK_PACE_NORMAL, "An invalid pace should fail safely to normal.")
	_assert(
		[
			WorkPaceSystemScript.output_multiplier(WorkPaceSystemScript.WORK_PACE_CAREFUL),
			WorkPaceSystemScript.output_multiplier(WorkPaceSystemScript.WORK_PACE_NORMAL),
			WorkPaceSystemScript.output_multiplier(WorkPaceSystemScript.WORK_PACE_INTENSE),
		] == [0.75, 1.0, 1.25],
		"The shared output multipliers should remain 0.75/1.00/1.25."
	)
	_assert(
		[
			WorkPaceSystemScript.worker_fatigue_gain(WorkPaceSystemScript.WORK_PACE_CAREFUL),
			WorkPaceSystemScript.worker_fatigue_gain(WorkPaceSystemScript.WORK_PACE_NORMAL),
			WorkPaceSystemScript.worker_fatigue_gain(WorkPaceSystemScript.WORK_PACE_INTENSE),
		] == [4, 8, 14],
		"Base workers should gain 4/8/14 fatigue after real work."
	)
	_assert(
		[
			WorkPaceSystemScript.diver_fatigue_gain(240.0, WorkPaceSystemScript.WORK_PACE_CAREFUL),
			WorkPaceSystemScript.diver_fatigue_gain(240.0, WorkPaceSystemScript.WORK_PACE_NORMAL),
			WorkPaceSystemScript.diver_fatigue_gain(240.0, WorkPaceSystemScript.WORK_PACE_INTENSE),
		] == [14, 18, 23],
		"Diver fatigue should scale the duration-based total once instead of adding worker fatigue."
	)
	_assert(
		[
			WorkPaceSystemScript.community_worker_adjustment(WorkPaceSystemScript.WORK_PACE_CAREFUL),
			WorkPaceSystemScript.community_worker_adjustment(WorkPaceSystemScript.WORK_PACE_NORMAL),
			WorkPaceSystemScript.community_worker_adjustment(WorkPaceSystemScript.WORK_PACE_INTENSE),
		] == [-1, 0, 1],
		"Community House output should use the discrete -1/0/+1 worker adjustment."
	)
	var idle_transition: Dictionary = WorkPaceSystemScript.tension_transition(3, WorkPaceSystemScript.WORK_PACE_INTENSE, false)
	var careful_transition: Dictionary = WorkPaceSystemScript.tension_transition(2, WorkPaceSystemScript.WORK_PACE_CAREFUL, true)
	var normal_transition: Dictionary = WorkPaceSystemScript.tension_transition(3, WorkPaceSystemScript.WORK_PACE_NORMAL, true)
	var intense_transition: Dictionary = WorkPaceSystemScript.tension_transition(2, WorkPaceSystemScript.WORK_PACE_INTENSE, true)
	_assert(idle_transition.current == 1 and not idle_transition.relieved and not idle_transition.intense, "A building without real work should shed two tension regardless of its selected pace.")
	_assert(careful_transition.current == 0 and careful_transition.relieved, "Real careful work should shed two tension and expose actual relief.")
	_assert(normal_transition.current == 2, "Real normal work should shed one tension.")
	_assert(intense_transition.current == 3 and intense_transition.intense, "Real intense work should add one tension and expose the intense flag.")
	_assert(
		[
			WorkPaceSystemScript.workforce_band(0),
			WorkPaceSystemScript.workforce_band(3),
			WorkPaceSystemScript.workforce_band(4),
			WorkPaceSystemScript.workforce_band(6),
			WorkPaceSystemScript.workforce_band(7),
		] == [0, 0, 1, 1, 2],
		"The workforce Hope band should change only at four and seven unique workers."
	)
	var state = _new_state(1, 10)
	var workshop = state.find_building_by_definition("workshop")
	workshop.work_pace = WorkPaceSystemScript.WORK_PACE_CAREFUL
	state.current_day_plan.building_work_paces[workshop.id] = WorkPaceSystemScript.WORK_PACE_INTENSE
	_assert(WorkPaceSystemScript.pace_for_building(state, workshop) == WorkPaceSystemScript.WORK_PACE_INTENSE, "A frozen DayPlan pace should take precedence over the mutable BuildingState value.")
	state.current_day_plan.building_work_paces.erase(workshop.id)
	_assert(WorkPaceSystemScript.pace_for_building(state, workshop) == WorkPaceSystemScript.WORK_PACE_CAREFUL, "BuildingState should provide the planning fallback before a pace is frozen.")


func _test_local_order_and_building_validation() -> void:
	var valid_order = WorkshopOrderStateScript.new()
	valid_order.setup(
		"workshop_order:test_workshop:4",
		"diving_lantern_mk2",
		"diving_lantern_mk2",
		"Latarnia nurkowa II",
		{"scrap": 4},
		5
	)
	_assert(valid_order.validation_errors("test_workshop", ResourceIdsScript.all(), KNOWN_TEST_OUTPUT_GEAR_IDS).is_empty(), "A well-formed order should pass local validation.")

	var corrupt_order = valid_order.duplicate(true)
	corrupt_order.queued_day = 0
	corrupt_order.reserved_cost = {"unknown": -1, "scrap": 1.5}
	var corrupt_errors: PackedStringArray = corrupt_order.validation_errors("other_workshop", ResourceIdsScript.all(), KNOWN_TEST_OUTPUT_GEAR_IDS)
	_assert(corrupt_errors.size() >= 4, "Local validation should reject owner, day, resource and cost type/value errors together.")

	var workshop = BuildingStateScript.new()
	workshop.id = "test_workshop"
	workshop.definition_id = "workshop"
	workshop.queued_production_orders.assign([valid_order, valid_order.duplicate(true)])
	workshop.next_production_order_sequence = 4
	var building_errors := workshop.production_order_validation_errors(ResourceIdsScript.all(), KNOWN_TEST_OUTPUT_GEAR_IDS)
	_assert(not building_errors.is_empty(), "Building validation should reject duplicate instance IDs and a next sequence that is not greater than active ordinary IDs.")

	var non_workshop = BuildingStateScript.new()
	non_workshop.id = "fishing"
	non_workshop.definition_id = "fishing_hut"
	non_workshop.queued_production_orders.append(valid_order)
	non_workshop.next_production_order_sequence = 2
	_assert(not non_workshop.production_order_validation_errors().is_empty(), "Only the Workshop may own canonical production orders or a non-default sequence.")


func _test_building_resource_roundtrip() -> void:
	var state = _new_state(4, 18)
	var workshop = state.find_building_by_definition("workshop")
	var production = ProductionSystemScript.new()
	_assert(production.queue_recipe(state, workshop, production.get_recipe("diving_lantern_mk2")), "The roundtrip fixture should contain one real queued order.")
	workshop.queued_production_orders[0].work_progress = 75
	_assert(ResourceSaver.save(workshop, TEST_ROUNDTRIP_PATH) == OK, "BuildingState with a typed order should save as a standalone Resource.")
	var loaded = ResourceLoader.load(TEST_ROUNDTRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	_assert(loaded != null and loaded.get_script() == BuildingStateScript, "The roundtrip should restore the exact BuildingState type.")
	if loaded == null or loaded.get_script() != BuildingStateScript:
		return
	_assert(loaded.queued_production_orders.size() == 1 and loaded.queued_production_orders[0].get_script() == WorkshopOrderStateScript, "The roundtrip should restore the exact WorkshopOrderState type inside the typed queue.")
	_assert(loaded.next_production_order_sequence == 2, "The roundtrip should preserve the monotonic counter.")
	var loaded_order = loaded.queued_production_orders[0]
	_assert(loaded_order.instance_id == "workshop_order:test_workshop:1" and loaded_order.queued_day == 18, "The roundtrip should preserve order identity and queue day.")
	_assert(loaded_order.work_progress == 75, "The roundtrip should preserve partial work progress on the canonical order.")
	_assert(loaded_order.reserved_cost == {"fabric_rubber": 2, "scrap": 4, "tech_parts": 1}, "The roundtrip should preserve the deep reserved-cost snapshot.")
	_assert(loaded.production_order_validation_errors(ResourceIdsScript.all(), KNOWN_TEST_OUTPUT_GEAR_IDS).is_empty(), "The restored building and order should pass local validation.")


func _new_state(workshop_level: int, target_day: int):
	var state = GameStateScript.new()
	state.setup_new_campaign(77_000 + target_day, DifficultyProfileScript.new())
	state.tutorial.complete()
	state.day = target_day
	state.prepare_weather_for_day(target_day)
	state.begin_new_day_plan()
	for resource_id in ResourceIdsScript.all():
		state.resources.set_amount(resource_id, 100)
	var workshop = BuildingStateScript.new()
	workshop.id = "test_workshop"
	workshop.definition_id = "workshop"
	workshop.slot_id = "bottom_left"
	workshop.level = workshop_level
	workshop.condition = 100
	workshop.is_built = true
	workshop.assigned_survivor_ids.assign(["anka"])
	state.buildings.append(workshop)
	var slot_data: Dictionary = state.platform.slot_states["bottom_left"]
	slot_data["building_id"] = workshop.id
	state.platform.slot_states["bottom_left"] = slot_data
	var worker = state.find_survivor("anka")
	worker.current_assignment = workshop.id
	return state


func _add_test_heavy_object(state) -> void:
	state.underwater_world.blueprint.heavy_object_spawns.append({
		"id": TEST_HEAVY_OBJECT_ID,
		"display_name": "Ciężki obiekt fixture",
		"rewards": {ResourceIdsScript.SCRAP: 2},
	})


func _resource_snapshot(state) -> Dictionary:
	var snapshot: Dictionary = {}
	for resource_id in ResourceIdsScript.all():
		snapshot[resource_id] = state.resources.get_amount(resource_id)
	return snapshot


func _resource_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var delta: Dictionary = {}
	for resource_id in before.keys():
		var amount := int(before[resource_id]) - int(after.get(resource_id, 0))
		if amount != 0:
			delta[str(resource_id)] = amount
	return delta


func _order_fingerprint(workshop) -> Array[String]:
	var result: Array[String] = []
	for order in workshop.queued_production_orders:
		result.append("%s|%s|%s|%s|%s|%d|%d" % [order.instance_id, order.recipe_id, order.output_gear_id, order.output_display_name, var_to_str(order.reserved_cost), order.queued_day, order.work_progress])
	result.append("next:%d" % int(workshop.next_production_order_sequence))
	return result


func _contains_fragment(lines: Array[String], fragment: String) -> bool:
	for line in lines:
		if fragment in line:
			return true
	return false


func _cleanup_roundtrip() -> void:
	if FileAccess.file_exists(TEST_ROUNDTRIP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_ROUNDTRIP_PATH))


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Production system test failed: " + message)
