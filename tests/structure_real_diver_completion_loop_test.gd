extends SceneTree

const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const DiverControllerScript := preload("res://diver_workbench/runtime/DiverController.gd")

const DIVE_SCENE_PATH := "res://scenes/diving/DiveScene.tscn"
const REPORT_ROOT := "user://test_structure_real_diver_completion_loop"
const REPORT_FILE := "completion_loop_report.json"
const MOTION_DELTA := 1.0 / 60.0
const PHYSICS_BATCH_SIZE := 8
const WAYPOINT_TOLERANCE := 14.0
const MAX_NAVIGATION_TICKS := 14400
const MAX_REPLANS := 20
const STAGNANT_TICKS := 180
const MAX_TEST_WALL_MSEC := 180_000
const MAX_POWER_CONTROLS := 6
const MAX_SEQUENCE_CONTROLS := 5
const MECHANISM_TIMEOUT_FRAMES := 480
const MECHANISM_STABLE_FRAMES := 8
const STREAMING_EXTENT := Vector2(1000.0, 720.0)

var _failed := false
var _dive: Node
var _map: Node2D
var _diver: CharacterBody2D
var _navigation: RefCounted
var _astar := AStarGrid2D.new()
var _player_interaction_area: Area2D
var _start_position := Vector2.ZERO
var _baseline_available := {}
var _mechanism_transition_count := 0
var _started_msec := 0
var _deadline_msec := 0
var _stage_trace: Array[String] = []
var _stage_positions: Array[Vector2] = []
var _report := {
	"contract": "structure_real_diver_completion_loop_v1",
	"dive_scene": DIVE_SCENE_PATH,
	"continuous_motion": true,
	"teleport_used": false,
	"stages": [],
	"navigation": [],
	"interactions": [],
	"public_gate_transition": false,
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_started_msec = Time.get_ticks_msec()
	_deadline_msec = _started_msec + MAX_TEST_WALL_MSEC
	await process_frame
	if not _prepare_report_root():
		_finish()
		return

	var state = GameStateScript.new()
	state.setup_new_campaign(410_207, DifficultyProfileScript.new())
	var setup = ExpeditionSetupScript.new()
	setup.capture_diver(state.find_survivor("igor"), 100.0)
	setup.start_entry_point = str(state.underwater_world.blueprint.entry_landmark_id)
	setup.target_sector = setup.start_entry_point
	setup.selected_objective = "basic_scavenge"
	setup.item_weights = {"food": 1.0, "planks": 1.2, "scrap": 1.5}
	state.current_expedition_setup = setup

	var scene_resource := ResourceLoader.load(DIVE_SCENE_PATH)
	_assert(scene_resource is PackedScene, "Test musi załadować produkcyjną DiveScene.")
	if not scene_resource is PackedScene:
		_finish()
		return
	_dive = (scene_resource as PackedScene).instantiate()
	root.add_child(_dive)
	await process_frame
	_dive.call("bind", null, state)
	await process_frame
	await physics_frame

	_diver = _find_real_diver()
	_map = _find_dive_map()
	_assert(_diver != null, "Produkcja musi opublikować aktywnego CharacterBody2D przez publiczną grupę gracza.")
	_assert(_map != null, "Produkcja musi opublikować mapę przez capability navigation/current/streaming.")
	if _diver == null or _map == null:
		_finish()
		return
	_dive.set_process(false)
	_dive.set_physics_process(false)
	_diver.set_physics_process(false)
	_diver.call("set_input_enabled", false)
	_assert(_find_active_gameplay_camera() != null, "Prawdziwy Nurek musi zachować aktywną Camera2D odkrytą po typie i stanie.")

	_start_position = _diver.global_position
	_record_main_stage("START")
	_map.call("update_streaming", _start_position, true, STREAMING_EXTENT)
	await process_frame
	await physics_frame

	var navigation_value: Variant = _map.call("navigation_snapshot", 0.0)
	_assert(navigation_value is RefCounted, "Mapa musi udostępnić publiczny snapshot nawigacji.")
	if not navigation_value is RefCounted:
		_finish()
		return
	_navigation = navigation_value as RefCounted
	_assert(bool(_navigation.call("is_valid")), "Publiczny snapshot nawigacji musi być poprawny.")
	if _failed or not _build_navigation_graph():
		_finish()
		return

	var gate_controllers := _discover_gate_controllers()
	_assert(not gate_controllers.is_empty(), "Mapa musi zamontować kontroler z publiczną bramką próby.")
	var initially_open := _count_open_public_gates(gate_controllers)
	_assert(initially_open == 0, "Publiczna bramka attempt_complete musi być zamknięta na początku świeżej próby.")

	var controls := _discover_capability_controls()
	var levers := _discover_power_levers(controls)
	_assert(not levers.is_empty(), "Test musi odkryć aktywny klaster A przez capability power_lever_position.")
	if levers.is_empty():
		_finish()
		return
	_sort_controls_by_position(levers)
	for control in controls:
		if control in levers:
			continue
		if bool(control.call("can_interact")):
			_baseline_available[control.get_instance_id()] = true

	var excluded := {}
	var stage_b_candidates: Array[Area2D] = await _cycle_power_until_new_controls(levers, excluded, "A")
	if stage_b_candidates.is_empty():
		_fail("A nie ujawniło pierwszego przyczynowego sterowania.")
		_finish()
		return
	var stage_b := await _activate_first_candidate(stage_b_candidates, "B")
	if stage_b == null:
		_finish()
		return
	excluded[stage_b.get_instance_id()] = true

	var stage_c_candidates: Array[Area2D] = await _cycle_power_until_new_controls(levers, excluded, "A")
	if stage_c_candidates.is_empty():
		_fail("Drugie przejście przez A nie ujawniło kolejnego przyczynowego sterowania.")
		_finish()
		return
	var stage_c := await _activate_first_candidate(stage_c_candidates, "C")
	if stage_c == null:
		_finish()
		return
	excluded[stage_c.get_instance_id()] = true

	var sequential_pool: Array[Area2D] = await _cycle_power_until_new_controls(levers, excluded, "A")
	if sequential_pool.is_empty():
		_fail("Trzecie przejście przez A nie ujawniło puli sekwencyjnej D.")
		_finish()
		return
	var archive_candidates: Array[Area2D] = await _solve_sequential_pool_with_recovery(
		sequential_pool,
		levers,
		excluded
	)
	if archive_candidates.is_empty():
		_finish()
		return
	var archive := await _activate_first_candidate(archive_candidates, "Archive")
	if archive == null:
		_finish()
		return

	var final_open := _count_open_public_gates(gate_controllers)
	_assert(final_open > initially_open, "Ukończenie fizycznej pętli musi otworzyć publiczną bramkę attempt_complete.")
	_report.public_gate_transition = final_open > initially_open

	var start_tolerance := maxf(12.0, minf(_navigation.cell_scale.x, _navigation.cell_scale.y) * 0.55)
	if not await _navigate_to_position(_start_position, start_tolerance, "Archive_to_START"):
		_fail("Prawdziwy Nurek nie wrócił fizycznie do zapisanego START.")
		_finish()
		return
	_record_main_stage("START")
	_report["physical_mechanism_transitions"] = _mechanism_transition_count
	_assert(_mechanism_transition_count > 0, "Pętla musi fizycznie aktywować co najmniej jeden mechanizm otwierający dalszą trasę.")
	var expected_trace: Array[String] = ["START", "A", "B", "A", "C", "A", "D", "Archive", "START"]
	_assert(_stage_trace == expected_trace, "Pętla etapów musi mieć postać START→A→B→A→C→A→D→Archive→START: %s" % [_stage_trace])
	_assert_stage_leg_distances()
	_assert_navigation_evidence(expected_trace.size() - 1)
	_report["stage_trace"] = _stage_trace.duplicate()
	_report["start_position"] = _vector_json(_start_position)
	_report["final_position"] = _vector_json(_diver.global_position)
	_report["return_distance"] = _diver.global_position.distance_to(_start_position)
	_report["elapsed_wall_msec"] = Time.get_ticks_msec() - _started_msec
	_report["wall_deadline_msec"] = MAX_TEST_WALL_MSEC
	_save_report()
	if not _failed:
		print("Structure real-Diver completion loop passed: continuous START-A-B-A-C-A-D-Archive-START, real overlaps, recovery and public gate.")
	_finish()


func _cycle_power_until_new_controls(
	levers: Array[Area2D],
	excluded: Dictionary,
	stage_label: String
) -> Array[Area2D]:
	var existing := _newly_available_controls(levers, excluded)
	if not existing.is_empty():
		_fail("%s musi fizycznie przełączyć klaster zasilania przed ujawnieniem kolejnego etapu." % stage_label)
		return []
	if levers.size() > MAX_POWER_CONTROLS:
		_fail("Dynamiczny klaster A przekracza limit %d kontrolek dla ograniczonego testu." % MAX_POWER_CONTROLS)
		return []
	var previous_gray := 0
	var state_count := 1 << levers.size()
	for state_index in range(1, state_count):
		if not _deadline_available("stany zasilania A"):
			return []
		var gray := state_index ^ (state_index >> 1)
		var changed_bits := gray ^ previous_gray
		previous_gray = gray
		var bit_index := 0
		while bit_index < levers.size() and (changed_bits & (1 << bit_index)) == 0:
			bit_index += 1
		if bit_index >= levers.size():
			continue
		var result := await _activate_control(levers[bit_index], "%s/power" % stage_label)
		if not bool(result.get("success", false)):
			_fail("Dostępna dźwignia A odrzuciła fizyczną interakcję.")
			return []
		var revealed := _newly_available_controls(levers, excluded)
		if not revealed.is_empty():
			_assert(int(result.get("mechanisms_changed", 0)) > 0, "%s musi przyczynowo zmienić fizyczny mechanizm przed dalszą trasą." % stage_label)
			_record_main_stage(stage_label)
			return revealed
	return []


func _solve_sequential_pool_with_recovery(
	pool: Array[Area2D],
	levers: Array[Area2D],
	excluded: Dictionary
) -> Array[Area2D]:
	_sort_controls_by_position(pool)
	if pool.size() > MAX_SEQUENCE_CONTROLS:
		_fail("Dynamiczna pula sekwencyjna przekracza limit %d kontrolek dla ograniczonego testu." % MAX_SEQUENCE_CONTROLS)
		return []
	var pool_ids := excluded.duplicate()
	for control in pool:
		pool_ids[control.get_instance_id()] = true

	var first_probe_result := await _activate_control(pool[0], "D/fault_probe")
	_assert(bool(first_probe_result.get("interaction_invoked", false)), "Pierwszy krok D musi rzeczywiście wywołać publiczną interakcję.")
	_assert(bool(first_probe_result.get("success", false)), "Pierwszy krok D musi zaakceptować fizyczną interakcję.")
	if not bool(first_probe_result.get("success", false)):
		return []
	_assert(_all_controls_available(pool), "Przed błędem sekwencji pełna wykryta pula D musi pozostać dostępna.")
	if _failed:
		return []
	_record_main_stage("D")
	var probe_result := await _activate_control(pool[0], "D/fault_repeat")
	_assert(bool(probe_result.get("interaction_invoked", false)), "Powtórzenie kroku D musi dotrzeć do produkcyjnego wywołania interakcji.")
	_assert(not bool(probe_result.get("success", false)), "Powtórzenie tego samego kroku D musi wywołać stan odzyskiwania.")
	_assert(not _all_controls_available(pool), "Faktyczny błąd D musi zablokować co najmniej jedną kontrolkę sekwencji.")
	var recovery_controls := _newly_available_controls(levers, pool_ids)
	_assert(not recovery_controls.is_empty(), "Błąd sekwencji musi przyczynowo ujawnić publiczną kontrolkę odzyskiwania.")
	if recovery_controls.is_empty():
		return []
	var recovery := await _activate_first_candidate(recovery_controls, "D_RESET", false)
	if recovery == null:
		return []
	_assert(_all_controls_available(pool), "Po odzyskaniu cała wykryta pula D musi znów być dostępna.")

	var permutations: Array = []
	_append_permutations([], pool, permutations)
	for permutation_value in permutations:
		if not _deadline_available("permutacje D"):
			return []
		var permutation := permutation_value as Array
		var sequence_succeeded := true
		var final_sequence_result := {}
		for control_value in permutation:
			if not _deadline_available("kroki D"):
				return []
			var control := control_value as Area2D
			var result := await _activate_control(control, "D/sequence")
			final_sequence_result = result
			if not bool(result.get("success", false)):
				sequence_succeeded = false
				break
		if sequence_succeeded:
			var archive_excluded := pool_ids.duplicate()
			archive_excluded[recovery.get_instance_id()] = true
			var archive_candidates := _newly_available_controls(levers, archive_excluded)
			if not archive_candidates.is_empty():
				_assert(int(final_sequence_result.get("mechanisms_changed", 0)) > 0, "Domknięcie D musi fizycznie zmienić mechanizm przed trasą do Archive.")
				return archive_candidates
			_fail("Udana pełna permutacja D nie ujawniła kolejnego publicznego sterowania.")
			return []
		if not bool(recovery.call("can_interact")):
			_fail("Błędna permutacja D nie przywróciła kontrolki odzyskiwania.")
			return []
		var reset_result := await _activate_control(recovery, "D/recover")
		if not bool(reset_result.get("success", false)):
			_fail("Kontrolka odzyskiwania odrzuciła reset po błędnej permutacji.")
			return []
	return []


func _append_permutations(prefix: Array, remaining: Array[Area2D], output: Array) -> void:
	if remaining.is_empty():
		output.append(prefix.duplicate())
		return
	for index in range(remaining.size()):
		var next_prefix := prefix.duplicate()
		next_prefix.append(remaining[index])
		var next_remaining := remaining.duplicate()
		next_remaining.remove_at(index)
		_append_permutations(next_prefix, next_remaining, output)


func _activate_first_candidate(
	candidates: Array[Area2D],
	stage_label: String,
	record_main_stage: bool = true
) -> Area2D:
	_sort_controls_by_position(candidates)
	var target := candidates[0] if not candidates.is_empty() else null
	_assert(target != null, "%s musi mieć co najmniej jedną przyczynowo dostępną kontrolkę." % stage_label)
	if target == null:
		return null
	var result := await _activate_control(target, stage_label)
	_assert(bool(result.get("success", false)), "%s musi zaakceptować fizyczną interakcję." % stage_label)
	if not bool(result.get("success", false)):
		return null
	if record_main_stage:
		_assert(int(result.get("mechanisms_changed", 0)) > 0, "%s musi zmienić fizyczny mechanizm przed następnym odcinkiem." % stage_label)
		_record_main_stage(stage_label)
	return target


func _activate_control(target: Area2D, label: String) -> Dictionary:
	if not _deadline_available("interakcja %s" % label):
		return {"success": false, "interaction_invoked": false, "reason": "wall_deadline"}
	if target == null or not is_instance_valid(target) or not bool(target.call("can_interact")):
		return {"success": false, "interaction_invoked": false, "reason": "not_available"}
	if not await _navigate_to_overlap(target, label):
		return {"success": false, "interaction_invoked": false, "reason": "overlap_unreachable"}
	_player_interaction_area = _resolve_player_interaction_area(target)
	if _player_interaction_area == null:
		return {"success": false, "interaction_invoked": false, "reason": "missing_player_area"}
	await physics_frame
	_assert(_player_interaction_area.overlaps_area(target), "%s wymaga rzeczywistego Area2D.overlaps_area przed aktywacją." % label)
	_assert(bool(target.call("can_interact")), "%s musi pozostać dostępne po fizycznym dopłynięciu." % label)
	if _failed:
		return {"success": false, "interaction_invoked": false, "reason": "precondition_failed"}
	var before := _mechanism_snapshot()
	var result_value: Variant = target.call("complete_dive_interaction")
	var result := result_value as Dictionary if result_value is Dictionary else {}
	await physics_frame
	await physics_frame
	var settlement := await _wait_for_mechanisms(before)
	var mechanisms_changed := int(settlement.get("changed", 0))
	if bool(result.get("success", false)) and mechanisms_changed > 0:
		_mechanism_transition_count += 1
	_report.interactions.append({
		"stage": label,
		"success": bool(result.get("success", false)),
		"interaction_invoked": true,
		"real_overlap": true,
		"mechanisms_changed": mechanisms_changed,
		"mechanisms_stable": bool(settlement.get("stable", false)),
	})
	_assert(bool(settlement.get("stable", false)), "%s nie ustabilizowało aktywnych mechanizmów w limicie." % label)
	return {
		"success": bool(result.get("success", false)),
		"interaction_invoked": true,
		"mechanisms_changed": mechanisms_changed,
		"mechanisms_stable": bool(settlement.get("stable", false)),
	}


func _navigate_to_overlap(target: Area2D, label: String) -> bool:
	_player_interaction_area = _resolve_player_interaction_area(target)
	_assert(_player_interaction_area != null, "%s wymaga aktywnego monitorującego Area2D Nurka." % label)
	if _player_interaction_area == null:
		return false
	await physics_frame
	if _player_interaction_area.overlaps_area(target):
		return true
	return await _navigate(target.global_position, target, 0.0, label)


func _navigate_to_position(target_position: Vector2, tolerance: float, label: String) -> bool:
	if _diver.global_position.distance_to(target_position) <= tolerance:
		return true
	return await _navigate(target_position, null, tolerance, label)


func _navigate(
	target_position: Vector2,
	target_area: Area2D,
	tolerance: float,
	label: String
) -> bool:
	if not _refresh_navigation_graph():
		_report.navigation.append({"label": label, "success": false, "reason": "invalid_live_navigation"})
		_save_report()
		return false
	_report["progress"] = {
		"label": label,
		"phase": "navigation_started",
		"position": _vector_json(_diver.global_position),
		"target": _vector_json(target_position),
	}
	_save_report()
	print("REAL_DIVER_ROUTE start %s from=%s target=%s" % [label, _diver.global_position, target_position])
	var total_ticks := 0
	var travelled := 0.0
	var collision_ticks := 0
	var temporary_blocks: Array[Vector2i] = []
	for replan in range(MAX_REPLANS):
		if not _deadline_available("nawigacja %s" % label):
			_restore_temporary_blocks(temporary_blocks)
			return false
		var path := _plan_path(_diver.global_position, target_position)
		if path.is_empty():
			if not temporary_blocks.is_empty():
				_restore_temporary_blocks(temporary_blocks)
				temporary_blocks.clear()
				_build_navigation_graph()
				continue
			_restore_temporary_blocks(temporary_blocks)
			_report.navigation.append({"label": label, "success": false, "reason": "no_path", "replans": replan})
			_report["progress"] = {
				"label": label,
				"phase": "navigation_failed",
				"reason": "no_path",
				"position": _vector_json(_diver.global_position),
				"target": _vector_json(target_position),
			}
			_save_report()
			return false
		var follow := await _follow_path(path, target_position, target_area, tolerance, MAX_NAVIGATION_TICKS - total_ticks)
		total_ticks += int(follow.get("ticks", 0))
		travelled += float(follow.get("travelled", 0.0))
		collision_ticks += int(follow.get("collision_ticks", 0))
		if bool(follow.get("success", false)):
			_restore_temporary_blocks(temporary_blocks)
			_report.navigation.append({
				"label": label,
				"success": true,
				"ticks": total_ticks,
				"travelled": travelled,
				"collision_ticks": collision_ticks,
				"replans": replan,
			})
			_report["progress"] = {"label": label, "phase": "navigation_passed", "ticks": total_ticks}
			_save_report()
			print("REAL_DIVER_ROUTE pass %s ticks=%d replans=%d" % [label, total_ticks, replan])
			return true
		if total_ticks >= MAX_NAVIGATION_TICKS:
			break
		var blocked_cell := follow.get("blocked_cell", Vector2i(-1, -1)) as Vector2i
		if blocked_cell.x < 0 or blocked_cell.y < 0 or _astar.is_point_solid(blocked_cell):
			break
		_astar.set_point_solid(blocked_cell, true)
		temporary_blocks.append(blocked_cell)
		_report["progress"] = {
			"label": label,
			"phase": "replan",
			"replan": replan + 1,
			"ticks": total_ticks,
			"blocked_cell": [blocked_cell.x, blocked_cell.y],
		}
		_save_report()
	_restore_temporary_blocks(temporary_blocks)
	_report.navigation.append({
		"label": label,
		"success": false,
		"reason": "stagnant_or_timeout",
		"ticks": total_ticks,
		"travelled": travelled,
		"collision_ticks": collision_ticks,
	})
	_report["progress"] = {
		"label": label,
		"phase": "navigation_failed",
		"ticks": total_ticks,
		"position": _vector_json(_diver.global_position),
		"target": _vector_json(target_position),
	}
	_save_report()
	print("REAL_DIVER_ROUTE fail %s ticks=%d position=%s" % [label, total_ticks, _diver.global_position])
	return false


func _follow_path(
	path: PackedVector2Array,
	target_position: Vector2,
	target_area: Area2D,
	tolerance: float,
	remaining_tick_budget: int
) -> Dictionary:
	var ticks := 0
	var travelled := 0.0
	var collision_ticks := 0
	var avoidance_normal := Vector2.ZERO
	for waypoint_index in range(path.size()):
		if not _deadline_available("ruch po trasie"):
			return {"success": false, "ticks": ticks, "travelled": travelled, "collision_ticks": collision_ticks}
		var waypoint := path[waypoint_index]
		var best_distance := INF
		var stagnant := 0
		while _diver.global_position.distance_to(waypoint) > WAYPOINT_TOLERANCE:
			if not _deadline_available("ruch do punktu trasy"):
				return {"success": false, "ticks": ticks, "travelled": travelled, "collision_ticks": collision_ticks}
			if _target_reached(target_position, target_area, tolerance):
				return {"success": true, "ticks": ticks, "travelled": travelled, "collision_ticks": collision_ticks}
			if ticks >= remaining_tick_budget:
				return {"success": false, "ticks": ticks, "travelled": travelled, "collision_ticks": collision_ticks, "blocked_cell": _navigation.call("world_to_cell", waypoint)}
			var delta_position := waypoint - _diver.global_position
			var distance := delta_position.length()
			if distance + 0.25 < best_distance:
				best_distance = distance
				stagnant = 0
			else:
				stagnant += 1
			if stagnant > STAGNANT_TICKS:
				return {"success": false, "ticks": ticks, "travelled": travelled, "collision_ticks": collision_ticks, "blocked_cell": _navigation.call("world_to_cell", waypoint)}
			var command := delta_position.normalized()
			if not avoidance_normal.is_zero_approx():
				command = (command + avoidance_normal * 0.85).normalized()
			var current_value: Variant = _map.call("current_at", _diver.global_position)
			var current := current_value as Vector2 if current_value is Vector2 else Vector2.ZERO
			var motion_value: Variant = _diver.call("simulate_motion_tick", command, true, current, 1.0, MOTION_DELTA, true)
			if not motion_value is Dictionary:
				return {"success": false, "ticks": ticks, "travelled": travelled, "collision_ticks": collision_ticks, "blocked_cell": _navigation.call("world_to_cell", waypoint)}
			var motion := motion_value as Dictionary
			travelled += float(motion.get("travelled", 0.0))
			if bool(motion.get("collided", false)):
				collision_ticks += 1
			avoidance_normal = _combined_slide_normal()
			ticks += 1
			if ticks % 24 == 0:
				_map.call("update_streaming", _diver.global_position, true, STREAMING_EXTENT)
			if ticks % PHYSICS_BATCH_SIZE == 0:
				await physics_frame

	var direct_best := INF
	var direct_stagnant := 0
	while not _target_reached(target_position, target_area, tolerance):
		if not _deadline_available("ruch końcowy"):
			break
		if ticks >= remaining_tick_budget:
			break
		var delta_position := target_position - _diver.global_position
		var distance := delta_position.length()
		if distance + 0.25 < direct_best:
			direct_best = distance
			direct_stagnant = 0
		else:
			direct_stagnant += 1
		if direct_stagnant > STAGNANT_TICKS:
			break
		var command := delta_position.normalized()
		if not avoidance_normal.is_zero_approx():
			command = (command + avoidance_normal * 0.85).normalized()
		var current_value: Variant = _map.call("current_at", _diver.global_position)
		var current := current_value as Vector2 if current_value is Vector2 else Vector2.ZERO
		var motion := _diver.call("simulate_motion_tick", command, true, current, 1.0, MOTION_DELTA, true) as Dictionary
		travelled += float(motion.get("travelled", 0.0))
		if bool(motion.get("collided", false)):
			collision_ticks += 1
		avoidance_normal = _combined_slide_normal()
		ticks += 1
		if ticks % 24 == 0:
			_map.call("update_streaming", _diver.global_position, true, STREAMING_EXTENT)
		if ticks % PHYSICS_BATCH_SIZE == 0:
			await physics_frame
	return {
		"success": _target_reached(target_position, target_area, tolerance),
		"ticks": ticks,
		"travelled": travelled,
		"collision_ticks": collision_ticks,
		"blocked_cell": _navigation.call("world_to_cell", target_position),
	}


func _plan_path(from_position: Vector2, target_position: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	var from_cell := _nearest_walkable_cell(_navigation.call("world_to_cell", from_position) as Vector2i)
	if from_cell.x < 0:
		return result
	var target_origin := _navigation.call("world_to_cell", target_position) as Vector2i
	var target_candidates := _walkable_cells_near(target_origin, 12)
	target_candidates.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		return (_navigation.call("cell_center", left) as Vector2).distance_squared_to(target_position) < (_navigation.call("cell_center", right) as Vector2).distance_squared_to(target_position)
	)
	var id_path: Array[Vector2i] = []
	for candidate in target_candidates:
		id_path = _astar.get_id_path(from_cell, candidate)
		if not id_path.is_empty():
			break
	if id_path.is_empty():
		return result
	for index in range(id_path.size()):
		result.append(_corridor_centered_waypoint(id_path, index))
	return result


func _corridor_centered_waypoint(path: Array[Vector2i], index: int) -> Vector2:
	var cell := path[index]
	var point := _navigation.call("cell_center", cell) as Vector2
	var direction := Vector2i.ZERO
	if index + 1 < path.size():
		direction = path[index + 1] - cell
	elif index > 0:
		direction = cell - path[index - 1]
	var cell_scale: Vector2 = _navigation.cell_scale
	if abs(direction.x) >= abs(direction.y) and direction.x != 0:
		var up := cell + Vector2i.UP
		var down := cell + Vector2i.DOWN
		var up_open := _is_astar_walkable(up)
		var down_open := _is_astar_walkable(down)
		if up_open != down_open:
			point.y += (-0.5 if up_open else 0.5) * cell_scale.y
	elif direction.y != 0:
		var left := cell + Vector2i.LEFT
		var right := cell + Vector2i.RIGHT
		var left_open := _is_astar_walkable(left)
		var right_open := _is_astar_walkable(right)
		if left_open != right_open:
			point.x += (-0.5 if left_open else 0.5) * cell_scale.x
	return point


func _build_navigation_graph() -> bool:
	var grid_size: Vector2i = _navigation.grid_size
	var cell_scale: Vector2 = _navigation.cell_scale
	_astar.region = Rect2i(Vector2i.ZERO, grid_size)
	_astar.cell_size = cell_scale
	_astar.offset = cell_scale * 0.5
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if not bool(_navigation.call("is_cell_clear", cell)):
				_astar.set_point_solid(cell, true)
	return true


func _refresh_navigation_graph() -> bool:
	var navigation_value: Variant = _map.call("navigation_snapshot", 0.0)
	if not navigation_value is RefCounted:
		_fail("Mapa musi odświeżyć publiczny snapshot nawigacji po zmianie mechanizmów.")
		return false
	_navigation = navigation_value as RefCounted
	if not bool(_navigation.call("is_valid")):
		_fail("Odświeżony publiczny snapshot nawigacji musi być poprawny.")
		return false
	return _build_navigation_graph()


func _nearest_walkable_cell(origin: Vector2i) -> Vector2i:
	for radius in range(13):
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				if radius > 0 and x > origin.x - radius and x < origin.x + radius and y > origin.y - radius and y < origin.y + radius:
					continue
				var candidate := Vector2i(x, y)
				if _is_astar_walkable(candidate):
					return candidate
	return Vector2i(-1, -1)


func _walkable_cells_near(origin: Vector2i, maximum_radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for radius in range(maximum_radius + 1):
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				if radius > 0 and x > origin.x - radius and x < origin.x + radius and y > origin.y - radius and y < origin.y + radius:
					continue
				var candidate := Vector2i(x, y)
				if _is_astar_walkable(candidate):
					result.append(candidate)
	return result


func _is_astar_walkable(cell: Vector2i) -> bool:
	return bool(_navigation.call("is_cell_in_bounds", cell)) and not _astar.is_point_solid(cell)


func _restore_temporary_blocks(cells: Array[Vector2i]) -> void:
	for cell in cells:
		if bool(_navigation.call("is_cell_clear", cell)):
			_astar.set_point_solid(cell, false)


func _target_reached(target_position: Vector2, target_area: Area2D, tolerance: float) -> bool:
	if target_area != null:
		if not is_instance_valid(target_area):
			return false
		_player_interaction_area = _resolve_player_interaction_area(target_area)
		return _player_interaction_area != null and _player_interaction_area.overlaps_area(target_area)
	return _diver.global_position.distance_to(target_position) <= tolerance


func _combined_slide_normal() -> Vector2:
	var result := Vector2.ZERO
	for collision_index in range(_diver.get_slide_collision_count()):
		var collision := _diver.get_slide_collision(collision_index)
		if collision == null:
			continue
		var normal := collision.get_normal()
		if normal.is_finite() and not normal.is_zero_approx():
			result += normal.normalized()
	return result.normalized() if not result.is_zero_approx() else Vector2.ZERO


func _resolve_player_interaction_area(target: Area2D) -> Area2D:
	if (
		_player_interaction_area != null
		and is_instance_valid(_player_interaction_area)
		and _player_interaction_area.monitoring
		and (_player_interaction_area.collision_mask & target.collision_layer) != 0
	):
		return _player_interaction_area
	for value in _diver.find_children("*", "Area2D", true, false):
		var area := value as Area2D
		if (
			area != null
			and area.monitoring
			and (area.collision_mask & target.collision_layer) != 0
			and _collision_object_has_active_shape(area)
		):
			return area
	return null


func _discover_capability_controls() -> Array[Area2D]:
	var result: Array[Area2D] = []
	for value in _map.find_children("*", "Area2D", true, false):
		var area := value as Area2D
		if (
			area != null
			and area.monitorable
			and area.has_method("can_interact")
			and area.has_method("complete_dive_interaction")
			and area.has_method("interaction_distance_to")
			and _collision_object_has_active_shape(area)
		):
			result.append(area)
	return result


func _discover_power_levers(controls: Array[Area2D]) -> Array[Area2D]:
	var result: Array[Area2D] = []
	for control in controls:
		if control.has_method("power_lever_position") and bool(control.call("can_interact")):
			result.append(control)
	return result


func _newly_available_controls(levers: Array[Area2D], excluded: Dictionary) -> Array[Area2D]:
	var result: Array[Area2D] = []
	for control in _discover_capability_controls():
		var instance_id := control.get_instance_id()
		if control in levers or excluded.has(instance_id) or _baseline_available.has(instance_id):
			continue
		if bool(control.call("can_interact")):
			result.append(control)
	_sort_controls_by_position(result)
	return result


func _all_controls_available(controls: Array[Area2D]) -> bool:
	for control in controls:
		if not is_instance_valid(control) or not bool(control.call("can_interact")):
			return false
	return true


func _discover_gate_controllers() -> Array[Node]:
	var result: Array[Node] = []
	for value in _map.find_children("*", "Node", true, false):
		var node := value as Node
		if node != null and node.has_method("is_public_gate_open") and node.has_method("reset_attempt"):
			result.append(node)
	return result


func _count_open_public_gates(controllers: Array[Node]) -> int:
	var result := 0
	for controller in controllers:
		if is_instance_valid(controller) and bool(controller.call("is_public_gate_open", &"attempt_complete")):
			result += 1
	return result


func _find_real_diver() -> CharacterBody2D:
	for value in get_nodes_in_group(DiverControllerScript.DIVE_PLAYER_GROUP):
		var body := value as CharacterBody2D
		if body != null and body.is_inside_tree() and body.has_method("simulate_motion_tick") and body.has_method("set_input_enabled"):
			return body
	return null


func _find_dive_map() -> Node2D:
	for value in _dive.find_children("*", "Node2D", true, false):
		var node := value as Node2D
		if node != null and node.has_method("navigation_snapshot") and node.has_method("current_at") and node.has_method("update_streaming"):
			return node
	return null


func _find_active_gameplay_camera() -> Camera2D:
	for value in _diver.find_children("*", "Camera2D", true, false):
		var camera := value as Camera2D
		if camera != null and camera.enabled and camera.is_current():
			return camera
	return null


func _collision_object_has_active_shape(object: CollisionObject2D) -> bool:
	for value in object.find_children("*", "CollisionShape2D", true, false):
		var shape := value as CollisionShape2D
		if shape != null and not shape.disabled and shape.shape != null:
			return true
	return false


func _mechanism_snapshot() -> Dictionary:
	var result := {}
	for value in _map.find_children("*", "AnimatableBody2D", true, false):
		var body := value as AnimatableBody2D
		if body != null and body.is_inside_tree() and _collision_object_has_active_shape(body):
			result[body.get_instance_id()] = body.global_transform
	return result


func _wait_for_mechanisms(before: Dictionary) -> Dictionary:
	var previous := _mechanism_snapshot()
	var stable_frames := 0
	for _frame in range(MECHANISM_TIMEOUT_FRAMES):
		if not _deadline_available("stabilizacja mechanizmu"):
			return {"stable": false, "changed": _count_changed_mechanisms(before, previous)}
		await physics_frame
		var current := _mechanism_snapshot()
		if _snapshots_equal(previous, current):
			stable_frames += 1
		else:
			stable_frames = 0
		previous = current
		if stable_frames >= MECHANISM_STABLE_FRAMES:
			return {"stable": true, "changed": _count_changed_mechanisms(before, current)}
	return {"stable": false, "changed": _count_changed_mechanisms(before, previous)}


func _snapshots_equal(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key in left.keys():
		if not right.has(key):
			return false
		var left_transform := left[key] as Transform2D
		var right_transform := right[key] as Transform2D
		if not left_transform.is_equal_approx(right_transform):
			return false
	return true


func _count_changed_mechanisms(before: Dictionary, after: Dictionary) -> int:
	var changed := 0
	for key in before.keys():
		if not after.has(key):
			changed += 1
			continue
		var before_transform := before[key] as Transform2D
		var after_transform := after[key] as Transform2D
		if not before_transform.is_equal_approx(after_transform):
			changed += 1
	for key in after.keys():
		if not before.has(key):
			changed += 1
	return changed


func _sort_controls_by_position(controls: Array[Area2D]) -> void:
	controls.sort_custom(func(left: Area2D, right: Area2D) -> bool:
		if not is_equal_approx(left.global_position.y, right.global_position.y):
			return left.global_position.y < right.global_position.y
		return left.global_position.x < right.global_position.x
	)


func _prepare_report_root() -> bool:
	var absolute := ProjectSettings.globalize_path(REPORT_ROOT)
	var error := DirAccess.make_dir_recursive_absolute(absolute)
	if error != OK:
		_fail("Nie można utworzyć izolowanego katalogu raportu: %s" % error_string(error))
		return false
	return true


func _save_report() -> void:
	var path := REPORT_ROOT.path_join(REPORT_FILE)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Nie można zapisać raportu pętli: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(_report, "  ", false))


func _record_main_stage(stage_label: String) -> void:
	var position := _diver.global_position
	_stage_trace.append(stage_label)
	_stage_positions.append(position)
	_report.stages.append({"stage": stage_label, "position": _vector_json(position)})


func _assert_stage_leg_distances() -> void:
	_assert(_stage_positions.size() == _stage_trace.size(), "Każdy etap główny musi mieć pozycję fizyczną.")
	if _stage_positions.size() != _stage_trace.size():
		return
	var minimum_distance := maxf(1.0, minf(_navigation.cell_scale.x, _navigation.cell_scale.y) * 0.25)
	var legs: Array[Dictionary] = []
	for index in range(1, _stage_positions.size()):
		var distance := _stage_positions[index - 1].distance_to(_stage_positions[index])
		legs.append({
			"from": _stage_trace[index - 1],
			"to": _stage_trace[index],
			"distance": distance,
		})
		_assert(
			distance > minimum_distance,
			"Odcinek %s→%s musi wymagać niezerowego fizycznego ruchu: %.3f <= %.3f."
				% [_stage_trace[index - 1], _stage_trace[index], distance, minimum_distance]
		)
	_report["stage_legs"] = legs
	_report["minimum_stage_leg_distance"] = minimum_distance


func _assert_navigation_evidence(minimum_routes: int) -> void:
	var successful_routes := 0
	var total_travelled := 0.0
	var total_collision_ticks := 0
	for record_value in _report.navigation:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		if not bool(record.get("success", false)):
			continue
		successful_routes += 1
		var travelled := float(record.get("travelled", 0.0))
		var ticks := int(record.get("ticks", 0))
		_assert(ticks > 0 and travelled > 0.0, "Każda zapisana trasa musi zawierać rzeczywiste ticki i niezerowy ruch.")
		total_travelled += travelled
		total_collision_ticks += int(record.get("collision_ticks", 0))
	_assert(successful_routes >= minimum_routes, "Pełna pętla wymaga co najmniej %d udanych tras fizycznych." % minimum_routes)
	_assert(total_travelled > 0.0, "Pełna pętla musi wykazać dodatnią przebytą odległość.")
	_assert(total_collision_ticks > 0, "Ruch prawdziwego Nurka musi faktycznie wejść w kontakt z produkcyjną fizyką kolizji.")
	_report["physical_navigation_summary"] = {
		"successful_routes": successful_routes,
		"travelled": total_travelled,
		"collision_ticks": total_collision_ticks,
	}


func _deadline_available(context: String) -> bool:
	if Time.get_ticks_msec() <= _deadline_msec:
		return true
	if not _failed:
		_fail("Test przekroczył twardy budżet %d ms podczas: %s." % [MAX_TEST_WALL_MSEC, context])
	return false


func _vector_json(value: Vector2) -> Array[float]:
	var result: Array[float] = [value.x, value.y]
	return result


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)


func _finish() -> void:
	if _dive != null and is_instance_valid(_dive):
		_dive.queue_free()
	quit(1 if _failed else 0)
