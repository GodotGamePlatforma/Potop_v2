extends SceneTree

const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const SLoopRealDiverHarnessScript := preload("res://tests/s_loop_real_diver_integration_harness.gd")

const DIVE_SCENE_PATH := "res://scenes/diving/DiveScene.tscn"
const DIVER_SCENE_PATH := "res://diver_workbench/runtime/Diver.tscn"
const REPORT_ROOT := "user://test_diver_clearance_integration"
const REPORT_FILE := "diver_clearance_report.json"
const CAPTURE_RESOLUTION := Vector2i(1280, 720)
const MOTION_DELTA := 1.0 / 60.0
const TARGET_DISTANCE := 9.0
const MAX_MOTION_TICKS := 360
const STAGNANT_TICKS := 90
const STOP_TICKS := 45
const CAMERA_MOTION_TICKS := 45
const CAMERA_RECENTER_TICKS := 120
const CAMERA_CENTER_TOLERANCE := 1.5
const QUERY_MARGIN := 0.05
const THROAT_SIDE_MARGIN := 92.0
const DIAGONAL_OFFSET := 18.0
const KNIFE_PRESENTATION_DURATION := 0.30
const KNIFE_CONTACT_PROGRESS := 0.40

var _failed := false
var _dive: Node
var _map: Node2D
var _diver: CharacterBody2D
var _camera: Camera2D
var _shape_records: Array[Dictionary] = []
var _native_capture := false
var _report := {
	"contract": "diver_clearance_integration_v1",
	"dive_scene": DIVE_SCENE_PATH,
	"replays": [],
	"dynamic_barriers": [],
	"currents": [],
	"camera": {},
	"presentation_bridge": {},
	"structure_runtime_states": [],
	"clearance_ab": {},
	"captures": [],
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_native_capture = DisplayServer.get_name() != "headless" and not Engine.is_embedded_in_editor()
	if _native_capture and not await _configure_native_viewport():
		_finish()
		return
	if not _prepare_report_root():
		_finish()
		return
	await _audit_camera_cold_start_contract()
	if _failed:
		_finish()
		return

	var state = GameStateScript.new()
	state.setup_new_campaign(105_060, DifficultyProfileScript.new())
	var setup = ExpeditionSetupScript.new()
	setup.capture_diver(state.find_survivor("igor"), 100.0)
	setup.day = 4
	setup.start_entry_point = str(state.underwater_world.blueprint.entry_landmark_id)
	setup.target_sector = setup.start_entry_point
	setup.selected_objective = "basic_scavenge"
	setup.can_place_buoys = true
	setup.item_weights = {"food": 1.0, "planks": 1.2, "scrap": 1.5}
	setup.selected_gear.append("knife")
	setup.suit_quality = 1
	setup.tutorial_mode = true
	setup.tutorial_baseline_step = TutorialStateScript.Step.DIVE_MOVEMENT
	state.current_expedition_setup = setup

	var dive_scene_value := ResourceLoader.load(DIVE_SCENE_PATH)
	_assert(dive_scene_value is PackedScene, "Harness musi załadować produkcyjną DiveScene.")
	if not dive_scene_value is PackedScene:
		_finish()
		return
	_dive = (dive_scene_value as PackedScene).instantiate()
	root.add_child(_dive)
	await process_frame
	_dive.call("bind", null, state)
	await process_frame
	await physics_frame

	_diver = _find_real_diver(_dive)
	_map = _find_dive_map(_dive)
	_assert(_diver != null, "DiveScene musi publikować dokładnie jednego prawdziwego nurka.")
	_assert(_map != null, "DiveScene musi publikować mapę z current_at/update_streaming.")
	if _diver == null or _map == null:
		_finish()
		return
	_dive.set_process(false)
	_dive.set_physics_process(false)
	_diver.set_physics_process(false)
	_diver.call("set_input_enabled", false)
	_camera = _find_gameplay_camera(_diver)
	_assert(_camera != null, "Live DiveScene musi publikować jedną Camera2D należącą do fizycznego Nurka.")
	if _camera == null:
		_finish()
		return
	var world_size: Vector2 = state.underwater_world.blueprint.world_size
	_diver.call("configure_camera_world_bounds", world_size)
	_camera.enabled = true
	_camera.make_current()

	var entry_position: Vector2 = state.underwater_world.blueprint.entry_position
	_map.call("update_streaming", entry_position, true, Vector2(900.0, 600.0))
	await process_frame
	await physics_frame
	var q1_state := _diver.call("presentation_state") as Dictionary
	_assert(int(q1_state.get("suit_quality", 0)) == 1, "Produkcyjny bind Q1 musi zachować bazowy wariant kombinezonu.")
	_clear_tutorial_indicator_for_capture()
	await _capture_checkpoint("presentation_suit_q1", false)

	setup.suit_quality = 4
	_dive.call("bind", null, state)
	await process_frame
	await physics_frame
	_diver.set_physics_process(false)
	_diver.call("set_input_enabled", false)
	_diver.call("configure_camera_world_bounds", world_size)
	_camera.enabled = true
	_camera.make_current()
	_map.call("update_streaming", entry_position, true, Vector2(900.0, 600.0))
	await process_frame
	await physics_frame
	var q4_state := _diver.call("presentation_state") as Dictionary
	_assert(int(q4_state.get("suit_quality", 0)) == 4, "Produkcyjny bind musi przekazać kanoniczną jakość kombinezonu Q4.")
	_clear_tutorial_indicator_for_capture()
	await _capture_checkpoint("presentation_suit_q4", false)

	if not _capture_real_collider_contract():
		_finish()
		return
	await _audit_root_presentation_bridge(entry_position)
	if _failed:
		_finish()
		return
	await _audit_camera_world_limits(world_size, entry_position)
	if _failed:
		_finish()
		return
	_map.call("update_streaming", entry_position, true, Vector2(900.0, 600.0))
	await process_frame
	await physics_frame
	var tutorial_case := _find_open_water_case(entry_position)
	_assert(not tutorial_case.is_empty(), "Tutorialowe wejście musi zawierać fizyczny odcinek dla realnego collidera.")
	if not tutorial_case.is_empty():
		if not await _audit_camera_motion_contract(tutorial_case):
			_finish()
			return
		await _audit_tutorial_indicator_tracks_diver(tutorial_case)
		if _failed:
			_finish()
			return
		if not await _run_replay(tutorial_case, false):
			_finish()
			return
		await _capture_checkpoint("tutorial_entry")

	var structure_roots := _find_structure_roots(_map)
	_assert(structure_roots.size() >= 2, "Live DiveScene musi montować wszystkie zarejestrowane struktury potrzebne do replayu integracyjnego.")
	var sampled_points: Array[Vector2] = [entry_position]
	var exact_eighty_count := 0
	var current_count := 0
	for structure_root in structure_roots:
		var structure_id := str(structure_root.get_meta(&"structure_id", ""))
		var package_manifest := _load_structure_manifest(structure_root)
		_assert(not package_manifest.is_empty(), "Struktura %s musi publikować czytelny package manifest." % structure_id)
		if package_manifest.is_empty():
			continue
		_map.call("update_streaming", structure_root.global_position, true, Vector2(1300.0, 2100.0))
		await physics_frame
		_assert(_audit_dynamic_barrier(structure_root), "%s musi wystawić początkową fizyczną dynamiczną barierę widoczną dla collidera Nurka." % structure_id)
		var current_record := await _audit_structure_current(structure_root, package_manifest)
		if not current_record.is_empty():
			current_count += 1
			sampled_points.append(current_record.get("position", Vector2.ZERO) as Vector2)
			if not await _prepare_structure_runtime_for_clearance(structure_root, current_record, entry_position):
				_finish()
				return
		for axis_id in ["horizontal", "vertical"]:
			var throat_case := _find_structure_throat_case(structure_root, package_manifest, axis_id)
			_assert(not throat_case.is_empty(), "%s musi mieć fizycznie przejezdne gardło osi %s." % [structure_id, axis_id])
			if throat_case.is_empty():
				continue
			if bool(throat_case.get("exact_80_square", false)):
				exact_eighty_count += 1
			sampled_points.append(throat_case.center)
			if not await _run_replay(throat_case, true):
				_finish()
				return
		var chamber_case := _find_chamber_turn_case(structure_root, package_manifest)
		_assert(not chamber_case.is_empty(), "%s musi publikować komorę do rzeczywistego obrotu 90 stopni." % structure_id)
		if not chamber_case.is_empty() and not await _run_chamber_turn(chamber_case):
			_finish()
			return
		await _capture_checkpoint(structure_id)

	_assert(exact_eighty_count >= 1, "Bieżąca integracja musi fizycznie przejść co najmniej jedno dokładne gardło 80×80.")
	_assert(current_count >= 1, "Live DiveScene musi przepchnąć realnego Nurka przez co najmniej jeden prąd struktury.")
	_record_clearance_ab(sampled_points)
	var s_loop_result := await SLoopRealDiverHarnessScript.new().run(self, _map, _diver)
	_report["s_loop_real_diver"] = s_loop_result.get("report", {})
	_assert(
		bool(s_loop_result.get("success", false)),
		"Real-Diver S-loop integration failed: %s" % "; ".join(s_loop_result.get("errors", PackedStringArray())),
	)
	_save_report()
	_finish()


func _capture_real_collider_contract() -> bool:
	_shape_records.clear()
	var combined := Rect2()
	var has_combined := false
	for shape_node in _owned_physical_shapes(_diver):
		var local_transform := _diver.global_transform.affine_inverse() * shape_node.global_transform
		_shape_records.append({"shape": shape_node.shape, "local_transform": local_transform})
		var rect := _transformed_rect(shape_node.shape.get_rect(), local_transform)
		combined = rect if not has_combined else combined.merge(rect)
		has_combined = true
	_assert(_shape_records.size() == 1, "Publiczny nurek integracyjny musi mieć jeden aktywny fizyczny Shape2D.")
	if not has_combined:
		return false
	var size := combined.size
	var long_side := maxf(size.x, size.y)
	var short_side := minf(size.x, size.y)
	_assert(is_equal_approx(long_side, 105.0) and is_equal_approx(short_side, 60.0), "Live collider musi mieć kopertę 105×60, otrzymano %s." % size)
	_report["diver_collider"] = {
		"shape_count": _shape_records.size(),
		"aabb": [size.x, size.y],
		"collision_layer": _diver.collision_layer,
		"collision_mask": _diver.collision_mask,
	}
	return not _failed


func _audit_root_presentation_bridge(entry_position: Vector2) -> void:
	_diver.call("reset_at", entry_position)
	_camera.force_update_scroll()
	await process_frame
	var root_position := _diver.global_position
	var root_rotation := _diver.rotation
	var root_scale := _diver.scale
	var shape_count := _owned_physical_shapes(_diver).size()
	var hit_end := entry_position + Vector2(72.0, -18.0)
	var hit_attack := {
		"success": true,
		"hit": true,
		"defeated": false,
		"end_position": hit_end,
	}
	_assert(
		bool(_dive.call("_present_resolved_attack", hit_attack, "knife", hit_end)),
		"Root musi rozpocząć formalną prezentację już rozstrzygniętego trafienia nożem.",
	)
	var state := _diver.call("presentation_state") as Dictionary
	_assert(bool(state.get("attack_active", false)), "Formalna prezentacja noża musi być aktywna po begin.")
	_assert(int(state.get("attack_id", -1)) == 1, "Pierwszy atak próby musi otrzymać nietrwały ID 1.")
	_assert(is_zero_approx(float(state.get("attack_progress", -1.0))), "Formalny begin musi jawnie ustawić progress 0.")
	_assert(is_equal_approx(float(state.get("attack_impact_progress", 0.0)), KNIFE_CONTACT_PROGRESS), "Root musi przekazać contact_progress 0.40.")
	_assert(bool(state.get("attack_confirmed", false)) and bool(state.get("attack_hit", false)), "Natychmiastowy wynik hit musi zostać potwierdzony przed animacją kontaktu.")
	_assert(not bool(state.get("attack_defeated", true)), "Zwykłe trafienie nie może zostać przedstawione jako defeated.")
	var contact_position := state.get("attack_contact_global", Vector2.ZERO) as Vector2
	_assert(contact_position.is_equal_approx(hit_end), "Formalny hit musi zachować rozstrzygnięty punkt kontaktu.")
	_assert(StringName(state.get("cue", &"")) == &"knife_attack", "Kompatybilny cue musi pozostać dodatkiem do aktywnego formalnego ataku.")
	_assert(not bool(_dive.call("_present_resolved_attack", hit_attack, "knife", hit_end)), "Aktywna prezentacja musi odrzucić nakładający się drugi begin bez zużycia ID.")
	_clear_tutorial_indicator_for_capture()
	await _capture_checkpoint("presentation_knife_00", false)

	_dive.set("_ending", true)
	_dive.call("_process", KNIFE_PRESENTATION_DURATION * KNIFE_CONTACT_PROGRESS)
	_dive.set("_ending", false)
	state = _diver.call("presentation_state") as Dictionary
	_assert(is_equal_approx(float(state.get("attack_progress", 0.0)), KNIFE_CONTACT_PROGRESS), "Prezentacja noża musi osiągnąć fazę kontaktu 0.40 przed early return procesu Root.")
	_assert(bool(state.get("attack_active", false)) and bool(state.get("attack_confirmed", false)), "Potwierdzony wynik musi pozostać aktywny w fazie kontaktu.")
	_assert(_diver.global_position.is_equal_approx(root_position), "Prezentacja noża nie może przesunąć fizycznego korzenia Nurka.")
	_assert(is_equal_approx(_diver.rotation, root_rotation) and _diver.scale.is_equal_approx(root_scale), "Prezentacja noża nie może zmienić obrotu ani skali fizycznego korzenia.")
	_assert(_owned_physical_shapes(_diver).size() == shape_count, "Warstwa noża nie może dodać collidera ani Shape2D.")
	_clear_tutorial_indicator_for_capture()
	await _capture_checkpoint("presentation_knife_40_contact", false)

	_dive.call("_advance_knife_attack_presentation", KNIFE_PRESENTATION_DURATION * (1.0 - KNIFE_CONTACT_PROGRESS))
	state = _diver.call("presentation_state") as Dictionary
	_assert(not bool(state.get("attack_active", true)), "Prezentacja noża musi zakończyć się przy progress 1.0.")
	_assert(int(state.get("attack_last_completed_id", -1)) == 1, "Pierwszy formalny end musi zostać zapisany dokładnie raz.")
	_assert(not bool(state.get("attack_canceled", true)), "Naturalnie ukończony wymach nie może być oznaczony jako anulowany.")
	_dive.call("_advance_knife_attack_presentation", KNIFE_PRESENTATION_DURATION)
	var repeated_end_state := _diver.call("presentation_state") as Dictionary
	_assert(int(repeated_end_state.get("attack_last_completed_id", -1)) == 1, "Kolejna klatka po końcu nie może wykonać drugiego end.")
	_clear_tutorial_indicator_for_capture()
	await _capture_checkpoint("presentation_knife_100_end", false)

	var miss_end := entry_position + Vector2(58.0, 30.0)
	var miss_attack := {
		"success": true,
		"hit": false,
		"defeated": false,
		"end_position": miss_end,
	}
	_assert(bool(_dive.call("_present_resolved_attack", miss_attack, "knife", miss_end)), "Root musi przedstawić rozstrzygnięte pudło noża.")
	state = _diver.call("presentation_state") as Dictionary
	_assert(int(state.get("attack_id", -1)) == 2 and bool(state.get("attack_confirmed", false)), "Pudło musi otrzymać rosnący ID 2 i dokładnie jedno potwierdzenie.")
	_assert(not bool(state.get("attack_hit", true)) and not bool(state.get("attack_defeated", true)), "Pudło nie może przedstawiać hit ani defeated.")
	_dive.call("_advance_knife_attack_presentation", KNIFE_PRESENTATION_DURATION)

	var defeated_end := entry_position + Vector2(-64.0, 12.0)
	var defeated_attack := {
		"success": true,
		"hit": true,
		"defeated": true,
		"end_position": defeated_end,
	}
	_assert(bool(_dive.call("_present_resolved_attack", defeated_attack, "knife", defeated_end)), "Root musi przedstawić już rozstrzygnięte defeated.")
	state = _diver.call("presentation_state") as Dictionary
	_assert(int(state.get("attack_id", -1)) == 3 and bool(state.get("attack_hit", false)) and bool(state.get("attack_defeated", false)), "Defeated musi zachować wynik hit i rosnący ID 3.")
	_dive.call("_advance_knife_attack_presentation", KNIFE_PRESENTATION_DURATION)

	var failed_attack := {
		"success": false,
		"hit": false,
		"defeated": false,
		"end_position": entry_position,
	}
	_assert(not bool(_dive.call("_present_resolved_attack", failed_attack, "knife", hit_end)), "Nieudany gameplayowy atak nie może uruchomić prezentacji.")
	state = _diver.call("presentation_state") as Dictionary
	_assert(not bool(state.get("attack_active", true)) and int(state.get("attack_last_completed_id", -1)) == 3, "Odrzucony atak nie może zmienić formalnego seriala Nurka.")

	var zero_endpoint_attack := {
		"success": true,
		"hit": true,
		"defeated": false,
		"end_position": entry_position,
	}
	_assert(bool(_dive.call("_present_resolved_attack", zero_endpoint_attack, "knife", hit_end)), "Zerowy endpoint trafienia musi użyć niezerowego kierunku fallback prezentacji.")
	state = _diver.call("presentation_state") as Dictionary
	_assert(bool(state.get("attack_active", false)) and int(state.get("attack_id", -1)) == 4, "Fallback endpointu musi zachować rosnący ID 4.")
	_dive.call("_advance_knife_attack_presentation", KNIFE_PRESENTATION_DURATION)

	var harpoon_end := entry_position + Vector2(120.0, 0.0)
	var harpoon_attack := {
		"success": true,
		"hit": false,
		"defeated": false,
		"end_position": harpoon_end,
	}
	_assert(bool(_dive.call("_present_resolved_attack", harpoon_attack, "harpoon_pistol", harpoon_end)), "Istniejąca prezentacja harpunu musi pozostać dostępna.")
	state = _diver.call("presentation_state") as Dictionary
	_assert(not bool(state.get("attack_active", true)) and StringName(state.get("cue", &"")) == &"harpoon_attack", "Harpun musi nadal korzystać wyłącznie ze zgodnościowego cue.")
	_diver.call("reset_at", entry_position)

	var cancel_end := entry_position + Vector2(70.0, 8.0)
	var cancel_attack := {
		"success": true,
		"hit": false,
		"defeated": false,
		"end_position": cancel_end,
	}
	_assert(bool(_dive.call("_present_resolved_attack", cancel_attack, "knife", cancel_end)), "Fixture anulowania musi rozpocząć formalny atak.")
	state = _diver.call("presentation_state") as Dictionary
	_assert(int(state.get("attack_id", -1)) == 5, "Atak anulowany musi kontynuować serial ID 5.")
	_assert(bool(_dive.call("_cancel_knife_attack_presentation")), "Anulowanie musi wywołać formalny end dokładnie raz.")
	state = _diver.call("presentation_state") as Dictionary
	_assert(not bool(state.get("attack_active", true)) and bool(state.get("attack_canceled", false)) and int(state.get("attack_last_completed_id", -1)) == 5, "Formalne anulowanie musi zachować canceled i ukończony ID 5.")
	_assert(not bool(_dive.call("_cancel_knife_attack_presentation")), "Powtórne anulowanie nie może wywołać drugiego end.")

	_assert(bool(_dive.call("_present_resolved_attack", cancel_attack, "knife", cancel_end)), "Fixture retry musi rozpocząć kolejny formalny atak.")
	state = _diver.call("presentation_state") as Dictionary
	_assert(int(state.get("attack_id", -1)) == 6, "Atak przed retry musi otrzymać ID 6.")
	_dive.call("_start_attempt", true)
	state = _diver.call("presentation_state") as Dictionary
	_assert(not bool(state.get("attack_active", true)) and int(state.get("attack_id", 0)) == -1 and int(state.get("attack_last_completed_id", 0)) == -1, "Retry musi wyczyścić lokalną epokę prezentacji Nurka.")
	_assert(bool(_dive.call("_present_resolved_attack", miss_attack, "knife", miss_end)), "Pierwszy atak po retry musi rozpocząć świeżą epokę.")
	state = _diver.call("presentation_state") as Dictionary
	_assert(int(state.get("attack_id", -1)) == 1, "Pierwszy atak po retry musi ponownie otrzymać ID 1.")
	_dive.call("_advance_knife_attack_presentation", KNIFE_PRESENTATION_DURATION)
	_diver.call("reset_at", entry_position)
	_map.call("update_streaming", entry_position, true, Vector2(900.0, 600.0))
	await process_frame
	await physics_frame

	_report["presentation_bridge"] = {
		"suit_quality_q1_bound": true,
		"suit_quality_q4_bound": true,
		"knife_duration": KNIFE_PRESENTATION_DURATION,
		"knife_contact_progress": KNIFE_CONTACT_PROGRESS,
		"completed_ids_before_retry": [1, 2, 3, 4, 5],
		"retry_first_id": 1,
		"zero_endpoint_fallback": true,
		"harpoon_compatibility_cue": true,
		"physical_shape_count": shape_count,
	}


func _clear_tutorial_indicator_for_capture() -> void:
	var indicator := _dive.find_child("TutorialDirectionIndicator", true, false)
	if indicator != null and indicator.has_method("clear"):
		indicator.call("clear")


func _prepare_structure_runtime_for_clearance(structure_root: Node2D, current_record: Dictionary, safe_position: Vector2) -> bool:
	var structure_id := str(structure_root.get_meta(&"structure_id", ""))
	var sample_position := current_record.get("position", Vector2.ZERO) as Vector2
	var controller := _find_structure_controller(structure_root)
	_assert(controller != null, "%s musi publikować jeden kontroler prądu przez capability seam." % structure_id)
	if controller == null:
		return false
	var initial_current_value: Variant = controller.call("current_at_world_position", sample_position)
	var initial_current := initial_current_value as Vector2 if initial_current_value is Vector2 else Vector2.ZERO
	_assert(initial_current.length() >= 1.0, "%s musi publikować aktywny prąd przed replayem sterowań." % structure_id)
	var controls := _find_clearance_controls(structure_root)
	_assert(not controls.is_empty(), "%s musi publikować dostępne sterowania przez capability seam." % structure_id)
	if controls.is_empty():
		return false

	# Keep the real diver away from moving safety envelopes while the integration
	# harness exercises only the public interactable/controller capabilities. The
	# order comes from the mounted package; Root does not copy private IDs or states.
	_diver.call("reset_at", safe_position)
	await physics_frame
	var completed_controls := {}
	var action_records: Array[Dictionary] = []
	for _step in range(controls.size() * 3):
		var current_value: Variant = controller.call("current_at_world_position", sample_position)
		var current := current_value as Vector2 if current_value is Vector2 else Vector2.ZERO
		if current.length() < 1.0:
			break
		var candidate := _next_available_clearance_control(controls, completed_controls)
		_assert(candidate != null, "%s nie udostępnił kolejnego sterowania potrzebnego do wygaszenia prądu." % structure_id)
		if candidate == null:
			return false
		var result_value: Variant = candidate.call("complete_dive_interaction")
		var result := result_value as Dictionary if result_value is Dictionary else {}
		_assert(bool(result.get("success", false)), "%s odrzucił dostępne sterowanie capability: %s." % [structure_id, result])
		if not bool(result.get("success", false)):
			return false
		completed_controls[candidate.get_instance_id()] = true
		_assert(await _await_moving_bodies_settled(structure_root), "%s nie domknął ruchomych ciał po sterowaniu." % structure_id)
		# The controller publishes the next affordance after observing the settled
		# body in its own physics tick; let that public state propagate.
		await physics_frame
		var after_value: Variant = controller.call("current_at_world_position", sample_position)
		var after := after_value as Vector2 if after_value is Vector2 else Vector2.ZERO
		action_records.append({
			"interaction_action": str(candidate.get("interaction_action")),
			"affordance_shape": str(candidate.get_meta(&"affordance_shape", "")),
			"current_before": _vector_json(current),
			"current_after": _vector_json(after),
		})
	var final_value: Variant = controller.call("current_at_world_position", sample_position)
	var final_current := final_value as Vector2 if final_value is Vector2 else Vector2.ZERO
	_assert(final_current.length() < 1.0, "%s nie wygasił prądu przez publiczną sekwencję dostępnych sterowań." % structure_id)
	_report.structure_runtime_states.append({
		"structure_id": structure_id,
		"current_before": _vector_json(initial_current),
		"current_after": _vector_json(final_current),
		"actions": action_records,
	})
	_assert(_audit_dynamic_barrier(structure_root), "%s po sekwencji musi zachować fizyczne ciała drzwi w osiągniętych pozycjach docelowych." % structure_id)
	return not _failed


func _find_structure_controller(structure_root: Node) -> Node:
	var candidates: Array[Node] = []
	for value in structure_root.find_children("*", "Node", true, false):
		var node := value as Node
		if node != null and node.has_method("current_at_world_position"):
			candidates.append(node)
	_assert(candidates.size() == 1, "Struktura z prądem musi mieć dokładnie jeden capability controller.")
	return candidates[0] if candidates.size() == 1 else null


func _find_clearance_controls(structure_root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for value in structure_root.find_children("*", "Node", true, false):
		var node := value as Node
		if node != null and node.has_method("can_interact") and node.has_method("complete_dive_interaction"):
			result.append(node)
	return result


func _next_available_clearance_control(controls: Array[Node], completed: Dictionary) -> Node:
	var reset_fallback: Node = null
	for control in controls:
		if completed.has(control.get_instance_id()) or not bool(control.call("can_interact")):
			continue
		var action := str(control.get("interaction_action"))
		if action == "inspect":
			continue
		if action == "reset":
			reset_fallback = control
			continue
		return control
	return reset_fallback


func _await_moving_bodies_settled(structure_root: Node, max_frames: int = 360) -> bool:
	var moving_bodies: Array[Node] = []
	for value in structure_root.find_children("*", "Node", true, false):
		var node := value as Node
		if node != null and node.has_method("reached_target"):
			moving_bodies.append(node)
	if moving_bodies.is_empty():
		return true
	for _frame in range(max_frames):
		var settled := true
		for body in moving_bodies:
			if not bool(body.call("reached_target")):
				settled = false
				break
		if settled:
			return true
		await physics_frame
	return false


func _find_open_water_case(anchor: Vector2) -> Dictionary:
	var cardinal_directions: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
	for direction in cardinal_directions:
		var start: Vector2 = anchor - direction * 80.0
		var finish: Vector2 = anchor + direction * 220.0
		var center: Vector2 = anchor + direction * 70.0
		var angle := _aligned_root_angle(direction)
		var diagonal_start: Vector2 = start + direction.rotated(PI * 0.5) * 36.0
		if not _pose_clear(diagonal_start, angle) or not _motion_clear(diagonal_start, center, angle):
			diagonal_start = start - direction.rotated(PI * 0.5) * 36.0
		if (
			_pose_clear(start, angle)
			and _pose_clear(center, angle)
			and _pose_clear(finish, angle)
			and _pose_clear(diagonal_start, angle)
			and _motion_clear(start, finish, angle)
			and _motion_clear(diagonal_start, center, angle)
		):
			return {
				"label": "tutorial_entry",
				"start": start,
				"center": center,
				"finish": finish,
				"axis": direction,
				"diagonal_start": diagonal_start,
				"exact_80_square": false,
			}
	return {}


func _audit_camera_cold_start_contract() -> void:
	var diver_scene_value := ResourceLoader.load(DIVER_SCENE_PATH)
	_assert(diver_scene_value is PackedScene, "Harness musi załadować produkcyjną scenę Nurka do próby cold-start.")
	if not diver_scene_value is PackedScene:
		return
	var probe := (diver_scene_value as PackedScene).instantiate() as CharacterBody2D
	_assert(probe != null, "Próba cold-start musi utworzyć prawdziwy DiverController.")
	if probe == null:
		return
	probe.call("seed_presentation_settings_before_ready", "low", true)
	root.add_child(probe)
	await process_frame
	probe.set_physics_process(false)
	var probe_camera := _find_gameplay_camera(probe)
	_assert(probe_camera != null, "Próba cold-start musi znaleźć prywatną Camera2D Nurka.")
	if probe_camera != null:
		_assert(not probe_camera.position_smoothing_enabled, "Ograniczenie ruchu ustawione przed _ready() musi wyłączyć smoothing kamery od pierwszej klatki.")
		_assert((probe_camera.global_position - probe.global_position).is_zero_approx(), "Ograniczenie ruchu ustawione przed _ready() musi rozpocząć z kamerą na środku Nurka.")
		probe.call("set_reduced_motion", false)
		_assert(probe_camera.position_smoothing_enabled, "Wyjście z cold-start reduced motion musi przywrócić authored smoothing kamery.")
	probe.queue_free()
	await process_frame


func _audit_camera_world_limits(world_size: Vector2, restore_position: Vector2) -> void:
	var viewport_size := Vector2(root.get_visible_rect().size)
	var half_visible_world := viewport_size * 0.5 / _camera.zoom
	var probes: Array[Dictionary] = [
		{
			"label": "top_left_outward_lead",
			"position": Vector2.ZERO,
			"lead": half_visible_world * Vector2(-0.5, -0.5),
		},
		{
			"label": "bottom_right_outward_lead",
			"position": world_size,
			"lead": half_visible_world * Vector2(0.5, 0.5),
		},
	]
	var records: Array[Dictionary] = []
	for probe in probes:
		var probe_position: Vector2 = probe.get("position", Vector2.ZERO) as Vector2
		var emulated_lead: Vector2 = probe.get("lead", Vector2.ZERO) as Vector2
		_diver.call("reset_at", probe_position)
		_camera.position = emulated_lead
		_camera.reset_smoothing()
		_camera.force_update_scroll()
		await process_frame
		var center := _camera.get_screen_center_position()
		var visible_min := center - half_visible_world
		var visible_max := center + half_visible_world
		var within_limits := (
			visible_min.x >= -CAMERA_CENTER_TOLERANCE
			and visible_min.y >= -CAMERA_CENTER_TOLERANCE
			and visible_max.x <= world_size.x + CAMERA_CENTER_TOLERANCE
			and visible_max.y <= world_size.y + CAMERA_CENTER_TOLERANCE
		)
		_assert(
			within_limits,
			"Camera2D z wychyleniem %s nie może odsłonić obszaru poza granicami świata: min=%s max=%s world=%s."
			% [probe.label, visible_min, visible_max, world_size],
		)
		records.append({
			"label": str(probe.label),
			"emulated_world_lead": _vector_json(emulated_lead),
			"screen_center": _vector_json(center),
			"visible_min": _vector_json(visible_min),
			"visible_max": _vector_json(visible_max),
			"within_limits": within_limits,
		})
	_diver.call("reset_at", restore_position)
	_camera.force_update_scroll()
	await process_frame
	var camera_report := _report.get("camera", {}) as Dictionary
	camera_report["world_limits"] = records
	_report["camera"] = camera_report


func _audit_camera_motion_contract(case: Dictionary) -> bool:
	var start: Vector2 = case.get("start", Vector2.ZERO) as Vector2
	var direction: Vector2 = (case.get("axis", Vector2.RIGHT) as Vector2).normalized()
	var original_signal_blocking := _diver.is_blocking_signals()
	_diver.set_block_signals(true)
	_diver.call("set_reduced_motion", false)
	_diver.call("reset_at", start)
	_camera.make_current()
	_camera.force_update_scroll()
	await process_frame
	var idle_target_lead := _camera_target_world_lead()
	var idle_screen_lead := _camera.get_screen_center_position() - _diver.global_position
	_assert(_camera.zoom.is_equal_approx(Vector2(1.2, 1.2)), "Gameplayowa Camera2D musi zachować stały zoom 1.2.")
	_assert(
		idle_target_lead.length() <= CAMERA_CENTER_TOLERANCE,
		"Po resecie cel Camera2D musi być wycentrowany na Nurku; lead=%s." % idle_target_lead,
	)
	_assert(
		idle_screen_lead.length() <= CAMERA_CENTER_TOLERANCE,
		"W bezruchu rzeczywisty środek ekranu musi pokrywać się z Nurkiem; lead=%s." % idle_screen_lead,
	)

	var swim_sample: Dictionary = await _sample_camera_motion(start, direction, false)
	var sprint_sample: Dictionary = await _sample_camera_motion(start, direction, true)
	_assert(int(swim_sample.get("collision_ticks", 0)) == 0, "Próba kamery podczas zwykłego pływania nie może opierać się o kolizję.")
	_assert(int(sprint_sample.get("collision_ticks", 0)) == 0, "Próba kamery podczas sprintu nie może opierać się o kolizję.")
	var swim_target_along := float(swim_sample.get("target_along", 0.0))
	var sprint_target_along := float(sprint_sample.get("target_along", 0.0))
	var swim_screen_along := float(swim_sample.get("screen_along", 0.0))
	var sprint_screen_along := float(sprint_sample.get("screen_along", 0.0))
	_assert(swim_target_along > 10.0, "Zwykłe pływanie musi przesunąć cel kamery przed Nurka; lead=%.3f." % swim_target_along)
	_assert(swim_screen_along > 3.0, "Zwykłe pływanie musi pokazać więcej świata przed Nurkiem; screen lead=%.3f." % swim_screen_along)
	_assert(
		sprint_target_along > swim_target_along + 10.0,
		"Sprint musi mieć większe wychylenie celu kamery niż zwykłe pływanie: swim=%.3f sprint=%.3f."
		% [swim_target_along, sprint_target_along],
	)
	_assert(
		sprint_screen_along > swim_screen_along + 3.0,
		"Sprint musi rzeczywiście pokazać więcej świata przed Nurkiem niż zwykłe pływanie: swim=%.3f sprint=%.3f."
		% [swim_screen_along, sprint_screen_along],
	)

	var release_mid_target := 0.0
	for tick in range(CAMERA_RECENTER_TICKS):
		_diver.call("simulate_motion_tick", Vector2.ZERO, false, Vector2.ZERO, 1.0, MOTION_DELTA, true)
		await physics_frame
		await process_frame
		if tick == 14:
			release_mid_target = _camera_target_world_lead().length()
	_camera.force_update_scroll()
	await process_frame
	var release_target_lead := _camera_target_world_lead()
	var release_screen_lead := _camera.get_screen_center_position() - _diver.global_position
	_assert(
		release_mid_target < sprint_target_along,
		"Po puszczeniu sterowania kamera musi płynnie wracać do środka: start=%.3f po_15=%.3f."
		% [sprint_target_along, release_mid_target],
	)
	_assert(
		release_target_lead.length() <= CAMERA_CENTER_TOLERANCE,
		"Po wyhamowaniu cel kamery musi wrócić do Nurka; lead=%s." % release_target_lead,
	)
	_assert(
		release_screen_lead.length() <= CAMERA_CENTER_TOLERANCE,
		"Po wyhamowaniu rzeczywisty środek ekranu musi wrócić do Nurka; lead=%s." % release_screen_lead,
	)

	var slowed_sample: Dictionary = await _sample_camera_motion(start, direction, false, 0.5)
	var slowed_target_along := float(slowed_sample.get("target_along", 0.0))
	_assert(slowed_target_along > 0.0 and slowed_target_along < swim_target_along, "Rzeczywiste spowolnienie pływania musi zmniejszyć wychylenie kamery: slow=%.3f swim=%.3f." % [slowed_target_along, swim_target_along])

	_diver.call("reset_at", start)
	for _tick in range(CAMERA_MOTION_TICKS):
		_diver.call("simulate_motion_tick", direction, false, Vector2.ZERO, 1.0, MOTION_DELTA, true)
	var lead_before_reversal := _camera_target_world_lead()
	_diver.call("simulate_motion_tick", -direction, false, Vector2.ZERO, 1.0, MOTION_DELTA, true)
	var first_reversal_lead := _camera_target_world_lead()
	_assert(first_reversal_lead.dot(direction) < lead_before_reversal.dot(direction), "Bezpośrednia zmiana kierunku musi natychmiast zacząć wygaszać stare wychylenie.")
	for _tick in range(CAMERA_MOTION_TICKS * 2):
		_diver.call("simulate_motion_tick", -direction, false, Vector2.ZERO, 1.0, MOTION_DELTA, true)
	var reversed_lead := _camera_target_world_lead()
	_assert(reversed_lead.dot(-direction) > 10.0, "Po zmianie kierunku kamera musi osiąść przed Nurkiem w nowym kierunku; lead=%s." % reversed_lead)

	_diver.call("reset_at", start)
	for _tick in range(CAMERA_MOTION_TICKS):
		_diver.call("simulate_motion_tick", direction, false, Vector2.ZERO, 1.0, MOTION_DELTA, true)
	var lead_before_cross_current := _camera_target_world_lead()
	var cross_current := direction.rotated(PI * 0.5) * 240.0
	_diver.call("simulate_motion_tick", direction, false, cross_current, 1.0, MOTION_DELTA, true)
	var cross_current_lead := _camera_target_world_lead()
	_assert(absf(cross_current_lead.dot(direction.rotated(PI * 0.5))) <= 0.05, "Nagły poprzeczny prąd nie może skręcić celu kamery; lead=%s." % cross_current_lead)
	_assert(cross_current_lead.length() < lead_before_cross_current.length(), "Odrzucony kierunek poprzecznego prądu musi wygaszać stare wychylenie zamiast je zamrażać.")

	var reduced_fixture: Dictionary = await _sample_camera_motion(start, direction, true)
	_assert(float(reduced_fixture.get("target_along", 0.0)) > 10.0, "Próba reduced motion wymaga aktywnego sprintowego wychylenia.")
	_diver.call("set_reduced_motion", true)
	_camera.force_update_scroll()
	await process_frame
	var reduced_target_lead := _camera_target_world_lead()
	var reduced_screen_lead := _camera.get_screen_center_position() - _diver.global_position
	_assert(reduced_target_lead.length() <= CAMERA_CENTER_TOLERANCE, "Reduced motion musi natychmiast wycentrować cel kamery.")
	_assert(reduced_screen_lead.length() <= CAMERA_CENTER_TOLERANCE, "Reduced motion musi natychmiast wycentrować rzeczywisty kadr kamery.")
	_assert(not _camera.position_smoothing_enabled, "Reduced motion musi wyłączyć smoothing śledzenia.")
	for _tick in range(15):
		_diver.call("simulate_motion_tick", direction, true, Vector2.ZERO, 1.0, MOTION_DELTA, true)
	_assert(_camera_target_world_lead().length() <= CAMERA_CENTER_TOLERANCE, "Reduced motion musi utrzymać kamerę na środku także podczas sprintu.")
	_diver.call("set_reduced_motion", false)
	_assert(_camera.position_smoothing_enabled, "Wyjście z reduced motion musi przywrócić authored smoothing śledzenia.")
	_diver.call("reset_at", start)

	var camera_report := _report.get("camera", {}) as Dictionary
	camera_report["motion"] = {
		"zoom": _vector_json(_camera.zoom),
		"idle_target_lead": _vector_json(idle_target_lead),
		"idle_screen_lead": _vector_json(idle_screen_lead),
		"swim": swim_sample,
		"sprint": sprint_sample,
		"release_mid_target_distance": release_mid_target,
		"release_target_lead": _vector_json(release_target_lead),
		"release_screen_lead": _vector_json(release_screen_lead),
		"slowed": slowed_sample,
		"reversal_first_lead": _vector_json(first_reversal_lead),
		"reversed_lead": _vector_json(reversed_lead),
		"cross_current_lead": _vector_json(cross_current_lead),
		"reduced_target_lead": _vector_json(reduced_target_lead),
		"reduced_screen_lead": _vector_json(reduced_screen_lead),
	}
	_report["camera"] = camera_report
	_diver.call("reset_at", start)
	_diver.set_block_signals(original_signal_blocking)
	return not _failed


func _audit_tutorial_indicator_tracks_diver(case: Dictionary) -> void:
	var indicator := _dive.find_child("TutorialDirectionIndicator", true, false) as Control
	_assert(indicator != null, "Produkcyjna DiveScene musi zbudować tutorialowy wskaźnik kierunku.")
	if indicator == null:
		return
	var start: Vector2 = case.get("start", Vector2.ZERO) as Vector2
	var direction: Vector2 = (case.get("axis", Vector2.RIGHT) as Vector2).normalized()
	var original_signal_blocking := _diver.is_blocking_signals()
	_diver.set_block_signals(true)
	_diver.call("reset_at", start)
	for _tick in range(CAMERA_MOTION_TICKS):
		_diver.call("simulate_motion_tick", direction, false, Vector2.ZERO, 1.0, MOTION_DELTA, true)
		await physics_frame
		await process_frame
	# The harness disables DiveController._process(), while production refreshes
	# this HUD after the camera step every frame. Mirror that phase explicitly and
	# measure synchronously so another smoothing step cannot stale the ring.
	_dive.call("_update_ui")

	var state := indicator.call("state_for_tests") as Dictionary
	_assert(is_equal_approx(float(state.get("ring_radius", 0.0)), 72.0), "Stylistyczna korekta nie może zmienić promienia pierścienia 72.")
	_assert(is_equal_approx(float(state.get("arrow_length", 0.0)), 20.0), "Strzałka musi mieć zatwierdzoną długość 20.")
	_assert(is_equal_approx(float(state.get("arrow_half_width", 0.0)), 9.0), "Strzałka musi mieć zatwierdzoną połowę szerokości 9.")
	_assert(is_equal_approx(float(state.get("target_reached_distance", 0.0)), 36.0), "Stylistyczna korekta nie może zmienić reguły osiągnięcia celu 36.")
	_assert((state.get("indicator_size", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(220.0, 220.0)), "Stylistyczna korekta nie może zmienić rozmiaru wskaźnika.")
	_assert((state.get("ring_color", Color.TRANSPARENT) as Color).is_equal_approx(Color("f2bd5518")), "Pierścień musi używać zatwierdzonej alfy 0x18.")
	_assert(is_equal_approx(float(state.get("ring_width", 0.0)), 1.0), "Pierścień musi mieć szerokość 1.")
	_assert((state.get("shadow_color", Color.TRANSPARENT) as Color).is_equal_approx(Color("06101470")), "Cień strzałki musi używać osłabionej alfy 0x70.")
	_assert((state.get("shadow_offset", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(1.0, 2.0)), "Cień strzałki musi mieć offset (1, 2).")
	_assert(is_equal_approx(float(state.get("outline_width", 0.0)), 1.0), "Obrys strzałki musi mieć szerokość 1.")
	_assert(indicator.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Wskaźnik tutoriala nie może przejmować wejścia GUI.")
	var diver_screen_position: Vector2 = _diver.get_global_transform_with_canvas().origin
	var ring_center := indicator.get_global_rect().get_center()
	var viewport_center := Vector2(root.get_visible_rect().size) * 0.5
	var shifted_distance := diver_screen_position.distance_to(viewport_center)
	var shifted_alignment := ring_center.distance_to(diver_screen_position)
	var navigation_target := _dive.call("_tutorial_navigation_target") as Dictionary
	var expected_direction := (
		(navigation_target.get("position", _diver.global_position) as Vector2)
		- _diver.global_position
	).normalized()
	_assert(bool(state.get("visible", false)), "Wskaźnik tutoriala musi być widoczny podczas pierwszego zejścia.")
	_assert(str(state.get("target_label", "")) == "ZASOBY", "Próba kamery nie może zmienić semantycznego celu wskaźnika tutoriala.")
	_assert((state.get("direction", Vector2.ZERO) as Vector2).is_equal_approx(expected_direction), "Strzałka musi zachować kierunek rzeczywistego celu tutoriala.")
	_assert(shifted_distance > 20.0, "Fixture wskaźnika musi rzeczywiście przesunąć Nurka poza środek viewportu.")
	_assert(
		shifted_alignment <= 1.0,
		"Pierścień tutoriala musi pozostać wycentrowany na Nurku przy aktywnym look-ahead; diver=%s ring=%s delta=%.3f."
		% [diver_screen_position, ring_center, shifted_alignment],
	)
	await _capture_checkpoint("tutorial_indicator_lookahead")

	_diver.call("reset_at", start)
	_camera.force_update_scroll()
	await process_frame
	_dive.call("_update_ui")
	diver_screen_position = _diver.get_global_transform_with_canvas().origin
	ring_center = indicator.get_global_rect().get_center()
	var centered_alignment := ring_center.distance_to(diver_screen_position)
	_assert(
		centered_alignment <= 1.0,
		"Pierścień tutoriala musi pozostać na Nurku po powrocie kamery do centrum; diver=%s ring=%s delta=%.3f."
		% [diver_screen_position, ring_center, centered_alignment],
	)
	await _capture_checkpoint("tutorial_indicator_centered")

	indicator.call("present", Vector2.RIGHT, "PRÓG", 36.0)
	var reached_state := indicator.call("state_for_tests") as Dictionary
	_assert(not bool(reached_state.get("visible", true)), "Cel dokładnie w progu 36 musi ukryć wskaźnik.")
	_assert(str(reached_state.get("target_label", "")) == "PRÓG", "Próg osiągnięcia nie może zgubić semantycznego celu.")
	indicator.call("present", Vector2.RIGHT, "PRÓG", 36.01)
	var beyond_state := indicator.call("state_for_tests") as Dictionary
	_assert(bool(beyond_state.get("visible", false)), "Cel tuż poza progiem 36 musi pokazać wskaźnik.")
	_assert((beyond_state.get("direction", Vector2.ZERO) as Vector2).is_equal_approx(Vector2.RIGHT), "Próg widoczności nie może zmienić kierunku celu.")
	indicator.call("present", Vector2.ZERO, "ZEROWY KIERUNEK", 100.0)
	_assert(not bool((indicator.call("state_for_tests") as Dictionary).get("visible", true)), "Zerowy kierunek musi ukryć wskaźnik niezależnie od dystansu.")
	_dive.call("_update_ui")
	_diver.set_block_signals(original_signal_blocking)

	var camera_report := _report.get("camera", {}) as Dictionary
	camera_report["tutorial_indicator"] = {
		"target_label": str(state.get("target_label", "")),
		"shifted_diver_from_viewport_center": shifted_distance,
		"shifted_ring_alignment": shifted_alignment,
		"centered_ring_alignment": centered_alignment,
	}
	_report["camera"] = camera_report


func _sample_camera_motion(start: Vector2, direction: Vector2, sprint_requested: bool, speed_multiplier: float = 1.0) -> Dictionary:
	_diver.call("reset_at", start)
	_camera.force_update_scroll()
	await process_frame
	var collision_ticks := 0
	for _tick in range(CAMERA_MOTION_TICKS):
		var motion := _diver.call(
			"simulate_motion_tick",
			direction,
			sprint_requested,
			Vector2.ZERO,
			speed_multiplier,
			MOTION_DELTA,
			true,
		) as Dictionary
		collision_ticks += 1 if bool(motion.get("collided", false)) else 0
		await physics_frame
		await process_frame
	_camera.force_update_scroll()
	await process_frame
	var target_lead := _camera_target_world_lead()
	var screen_lead := _camera.get_screen_center_position() - _diver.global_position
	return {
		"sprint": sprint_requested,
		"speed_multiplier": speed_multiplier,
		"ticks": CAMERA_MOTION_TICKS,
		"collision_ticks": collision_ticks,
		"diver_position": _vector_json(_diver.global_position),
		"target_lead": _vector_json(target_lead),
		"target_along": target_lead.dot(direction),
		"screen_lead": _vector_json(screen_lead),
		"screen_along": screen_lead.dot(direction),
	}


func _camera_target_world_lead() -> Vector2:
	return _camera.global_position - _diver.global_position


func _find_structure_throat_case(structure_root: Node2D, manifest: Dictionary, axis_id: String) -> Dictionary:
	var collision := manifest.get("collision", {}) as Dictionary
	var scale := _vector_from_value(collision.get("world_units_per_pixel", []))
	var structure_id := str(structure_root.get_meta(&"structure_id", ""))
	# Prefer exact 2x2/80x80 operations, but fall back to another clear two-cell throat.
	# The preference makes the product's tightest published aperture an explicit replay,
	# instead of relying on manifest ordering.
	for exact_only in [true, false]:
		for operation_value in collision.get("operations", []):
			if not operation_value is Dictionary:
				continue
			var operation := operation_value as Dictionary
			if str(operation.get("op", "")) != "open_rect":
				continue
			var rect_px := _rect_from_value(operation.get("rect_px", []))
			if axis_id == "horizontal" and not is_equal_approx(rect_px.size.x, 2.0):
				continue
			if axis_id == "vertical" and not is_equal_approx(rect_px.size.y, 2.0):
				continue
			var exact_square := is_equal_approx(rect_px.size.x, 2.0) and is_equal_approx(rect_px.size.y, 2.0)
			if exact_square != exact_only:
				continue
			var local_rect := Rect2(rect_px.position * scale, rect_px.size * scale)
			var axis: Vector2 = Vector2.RIGHT if axis_id == "horizontal" else Vector2.DOWN
			var narrow_extent: float = local_rect.size.x if axis_id == "horizontal" else local_rect.size.y
			var center: Vector2 = structure_root.to_global(local_rect.get_center())
			var side_distance: float = narrow_extent * 0.5 + THROAT_SIDE_MARGIN
			var start: Vector2 = center - axis * side_distance
			var finish: Vector2 = center + axis * side_distance
			var angle := _aligned_root_angle(axis)
			if not (_pose_clear(start, angle) and _pose_clear(center, angle) and _pose_clear(finish, angle)):
				continue
			if not _motion_clear(start, finish, angle):
				continue
			var diagonal_start: Vector2 = start + axis.rotated(PI * 0.5) * DIAGONAL_OFFSET
			if not _pose_clear(diagonal_start, angle) or not _motion_clear(diagonal_start, center, angle):
				diagonal_start = start - axis.rotated(PI * 0.5) * DIAGONAL_OFFSET
			if not _pose_clear(diagonal_start, angle) or not _motion_clear(diagonal_start, center, angle):
				continue
			return {
				"label": "%s/%s/%s" % [structure_id, axis_id, str(operation.get("id", "throat"))],
				"start": start,
				"center": center,
				"finish": finish,
				"axis": axis,
				"diagonal_start": diagonal_start,
				"rect_px": [rect_px.position.x, rect_px.position.y, rect_px.size.x, rect_px.size.y],
				"exact_80_square": exact_square,
			}
	return {}


func _find_chamber_turn_case(structure_root: Node2D, manifest: Dictionary) -> Dictionary:
	var collision := manifest.get("collision", {}) as Dictionary
	var scale := _vector_from_value(collision.get("world_units_per_pixel", []))
	for operation_value in collision.get("operations", []):
		if not operation_value is Dictionary:
			continue
		var operation := operation_value as Dictionary
		if str(operation.get("op", "")) != "open_rect":
			continue
		var rect_px := _rect_from_value(operation.get("rect_px", []))
		var local_rect := Rect2(rect_px.position * scale, rect_px.size * scale)
		if local_rect.size.x < 240.0 or local_rect.size.y < 180.0:
			continue
		var center: Vector2 = structure_root.to_global(local_rect.get_center())
		var left: Vector2 = center - Vector2.RIGHT * 45.0
		var down: Vector2 = center + Vector2.DOWN * 50.0
		if not (_pose_clear(left, 0.0) and _pose_clear(center, 0.0) and _pose_clear(center, PI * 0.5) and _pose_clear(down, PI * 0.5)):
			continue
		if _motion_clear(left, center, 0.0) and _motion_clear(center, down, PI * 0.5):
			return {
				"label": "%s/chamber_turn" % str(structure_root.get_meta(&"structure_id", "")),
				"start": left,
				"center": center,
				"finish": down,
				"room_world_size": local_rect.size,
			}
	return {}


func _run_replay(case: Dictionary, stop_in_center: bool) -> bool:
	var label := str(case.label)
	var start: Vector2 = case.start
	var center: Vector2 = case.center
	var finish: Vector2 = case.finish
	var diagonal_start: Vector2 = case.diagonal_start
	_diver.call("reset_at", diagonal_start)
	await physics_frame
	var travelled := 0.0
	var first_leg: Dictionary = await _swim_to(center, label + "/diagonal_entry")
	if not bool(first_leg.get("success", false)):
		var control_variants: Array[Dictionary] = [first_leg]
		for strategy in [&"direct_sprint", &"counter_sprint"]:
			_diver.call("reset_at", diagonal_start)
			await physics_frame
			var retry: Dictionary = await _swim_to(center, label + "/diagonal_entry", strategy)
			control_variants.append(retry)
			if bool(retry.get("success", false)):
				first_leg = retry
				break
		if not bool(first_leg.get("success", false)):
			_diver.call("reset_at", diagonal_start)
			await physics_frame
			control_variants.append(await _swim_to(center, label + "/diagonal_entry", &"no_current"))
			_report["blocking_replay"] = {
				"label": label,
				"start": _vector_json(diagonal_start),
				"target": _vector_json(center),
				"variants": control_variants,
			}
			_save_report()
			_fail("Realny Diver nie przeszedł diagonal entry %s w żadnym sterowaniu z aktywnym prądem: %s." % [label, control_variants])
			return false
	travelled += float(first_leg.get("travelled", 0.0))
	if stop_in_center:
		var stop_result: Dictionary = await _stop_at_current_pose(label + "/stop")
		if not bool(stop_result.get("success", false)):
			_fail("Realny Diver nie utrzymał bezpiecznego stopu w %s: %s." % [label, stop_result])
			return false
		travelled += float(stop_result.get("travelled", 0.0))
	var forward: Dictionary = await _swim_to(finish, label + "/forward")
	if not bool(forward.get("success", false)):
		_fail("Realny Diver nie przeszedł gardła do przodu %s: %s." % [label, forward])
		return false
	travelled += float(forward.get("travelled", 0.0))
	var backout: Dictionary = await _swim_to(start, label + "/backout")
	if not bool(backout.get("success", false)):
		_fail("Realny Diver nie wycofał się przez gardło %s: %s." % [label, backout])
		return false
	travelled += float(backout.get("travelled", 0.0))
	_report.replays.append({
		"label": label,
		"rect_px": case.get("rect_px", []),
		"exact_80_square": bool(case.get("exact_80_square", false)),
		"start": _vector_json(start),
		"center": _vector_json(center),
		"finish": _vector_json(finish),
		"travelled": travelled,
		"diagonal_entry": true,
		"diagonal_entry_strategy": str(first_leg.get("strategy", "direct_swim")),
		"stopped_in_center": stop_in_center,
		"backout": true,
	})
	return true


func _run_chamber_turn(case: Dictionary) -> bool:
	_diver.call("reset_at", case.start)
	await physics_frame
	var horizontal: Dictionary = await _swim_to(case.get("center", Vector2.ZERO) as Vector2, str(case.get("label", "")) + "/horizontal")
	if not bool(horizontal.get("success", false)):
		_fail("Realny Diver nie dotarł do komory obrotu %s: %s." % [case.label, horizontal])
		return false
	_diver.call("stop_motion")
	var turn_start := _diver.global_position
	var turn_travelled := 0.0
	var collision_ticks := 0
	for _tick in range(24):
		var current_value: Variant = _map.call("current_at", _diver.global_position)
		var current: Vector2 = current_value as Vector2 if current_value is Vector2 else Vector2.ZERO
		var motion := _diver.call("simulate_motion_tick", Vector2.DOWN, false, current, 1.0, MOTION_DELTA, true) as Dictionary
		turn_travelled += float(motion.get("travelled", 0.0))
		collision_ticks += 1 if bool(motion.get("collided", false)) else 0
		await physics_frame
	_assert(collision_ticks == 0, "Obrót 90 stopni w %s nie może opierać się o collider komory." % case.label)
	_assert(_pose_clear(_diver.global_position, _diver.rotation), "Po obrocie 90 stopni realny collider musi pozostać poza geometrią komory %s." % case.label)
	_assert(
		absf(absf(_diver.rotation) - PI * 0.5) < 0.18,
		"Obrót 90 stopni w %s musi zmienić rzeczywistą rotację root collidera; otrzymano %.4f rad." % [case.label, _diver.rotation],
	)
	_report.replays.append({
		"label": case.label,
		"turn_degrees": 90,
		"rotation": _diver.rotation,
		"room_world_size": _vector_json(case.get("room_world_size", Vector2.ZERO) as Vector2),
		"turn_start": _vector_json(turn_start),
		"turn_finish": _vector_json(_diver.global_position),
		"turn_travelled": turn_travelled,
		"travelled": float(horizontal.get("travelled", 0.0)) + turn_travelled,
		"collision_ticks": collision_ticks,
	})
	return not _failed


func _swim_to(target: Vector2, label: String, strategy: StringName = &"direct_swim") -> Dictionary:
	var travelled := 0.0
	var best_distance := INF
	var stagnant := 0
	var peak_current := 0.0
	var collision_ticks := 0
	for tick in range(MAX_MOTION_TICKS):
		var delta_position := target - _diver.global_position
		var distance := delta_position.length()
		if distance <= TARGET_DISTANCE:
			return {
				"success": true,
				"strategy": strategy,
				"ticks": tick,
				"travelled": travelled,
				"distance": distance,
				"peak_current": peak_current,
				"collision_ticks": collision_ticks,
				"rotation": _diver.rotation,
			}
		if distance + 0.35 < best_distance:
			best_distance = distance
			stagnant = 0
		else:
			stagnant += 1
		if stagnant > STAGNANT_TICKS:
			break
		var current_value: Variant = _map.call("current_at", _diver.global_position)
		var live_current: Vector2 = current_value as Vector2 if current_value is Vector2 else Vector2.ZERO
		peak_current = maxf(peak_current, live_current.length())
		var current := Vector2.ZERO if strategy == &"no_current" else live_current
		var command := delta_position.normalized()
		var sprint_requested := strategy == &"direct_sprint" or strategy == &"counter_sprint"
		if strategy == &"counter_sprint":
			var sprint_speed := maxf(float(_diver.get("sprint_speed")), 1.0)
			var desired_ground_velocity := delta_position.normalized() * 60.0
			command = ((desired_ground_velocity - current) / sprint_speed).limit_length(1.0)
		var motion_value: Variant = _diver.call(
			"simulate_motion_tick",
			command,
			sprint_requested,
			current,
			1.0,
			MOTION_DELTA,
			true,
		)
		if not motion_value is Dictionary:
			return {"success": false, "reason": "invalid_motion_result", "label": label, "strategy": strategy}
		var motion := motion_value as Dictionary
		travelled += float(motion.get("travelled", 0.0))
		collision_ticks += 1 if bool(motion.get("collided", false)) else 0
		await physics_frame
	return {
		"success": false,
		"reason": "stagnant_or_timeout",
		"label": label,
		"strategy": strategy,
		"position": _vector_json(_diver.global_position),
		"target": _vector_json(target),
		"distance": _diver.global_position.distance_to(target),
		"rotation": _diver.rotation,
		"travelled": travelled,
		"peak_current": peak_current,
		"collision_ticks": collision_ticks,
	}


func _stop_at_current_pose(label: String) -> Dictionary:
	var travelled := 0.0
	for _tick in range(STOP_TICKS):
		var current_value: Variant = _map.call("current_at", _diver.global_position)
		var current := current_value as Vector2 if current_value is Vector2 else Vector2.ZERO
		var motion := _diver.call("simulate_motion_tick", Vector2.ZERO, false, current, 1.0, MOTION_DELTA, true) as Dictionary
		travelled += float(motion.get("travelled", 0.0))
		await physics_frame
	var clear := _pose_clear(_diver.global_position, _diver.rotation)
	var camera_target_lead := _camera_target_world_lead()
	var camera_centered := camera_target_lead.length() <= 2.0
	return {
		"success": clear and camera_centered,
		"label": label,
		"position": _vector_json(_diver.global_position),
		"rotation": _diver.rotation,
		"travelled": travelled,
		"pose_clear": clear,
		"camera_target_lead": _vector_json(camera_target_lead),
		"camera_centered": camera_centered,
	}


func _audit_dynamic_barrier(structure_root: Node2D) -> bool:
	for value in structure_root.find_children("*", "AnimatableBody2D", true, false):
		var body := value as AnimatableBody2D
		if body == null or not _body_has_active_shape(body):
			continue
		for shape_value in body.find_children("*", "CollisionShape2D", true, false):
			var body_shape := shape_value as CollisionShape2D
			if body_shape == null or body_shape.disabled or body_shape.shape == null:
				continue
			for angle in [0.0, PI * 0.5]:
				var query := _shape_query(_shape_records[0], body_shape.global_position, angle)
				for collision_value in _diver.get_world_2d().direct_space_state.intersect_shape(query, 16):
					var collision := collision_value as Dictionary
					if collision.get("collider", null) != body:
						continue
					_report.dynamic_barriers.append({
						"structure_id": str(structure_root.get_meta(&"structure_id", "")),
						"node_type": body.get_class(),
						"socket_id": str(body.get_meta(&"socket_id", "")),
						"target_open": bool(body.get_meta(&"target_open", false)),
						"reached_target": bool(body.get_meta(&"reached_target", false)),
						"blocked_real_capsule": true,
					})
					return true
	return false


func _audit_structure_current(structure_root: Node2D, manifest: Dictionary) -> Dictionary:
	var size := _vector_from_value(manifest.get("size", []))
	for local_y in range(40, roundi(size.y), 80):
		for local_x in range(40, roundi(size.x), 80):
			var position := structure_root.to_global(Vector2(local_x, local_y))
			var current_value: Variant = _map.call("current_at", position)
			if not current_value is Vector2 or (current_value as Vector2).length() < 1.0:
				continue
			var current := current_value as Vector2
			var angle := _aligned_root_angle(current)
			if not _pose_clear(position, angle) or not _motion_clear(position, position + current.normalized() * 100.0, angle):
				continue
			_diver.call("reset_at", position)
			await physics_frame
			var start := _diver.global_position
			for _tick in range(30):
				_diver.call("simulate_motion_tick", Vector2.ZERO, false, current, 1.0, MOTION_DELTA, true)
				await physics_frame
			var displacement := _diver.global_position - start
			if displacement.dot(current.normalized()) <= 5.0:
				continue
			var camera_target_lead := _camera_target_world_lead()
			_assert(
				camera_target_lead.length() <= CAMERA_CENTER_TOLERANCE,
				"Pasywny prąd w %s nie może tworzyć dodatkowego celu wyprzedzenia kamery; lead=%s."
				% [str(structure_root.get_meta(&"structure_id", "")), camera_target_lead],
			)
			var record := {
				"structure_id": str(structure_root.get_meta(&"structure_id", "")),
				"position": position,
				"current": current,
				"displacement": displacement,
			}
			_report.currents.append({
				"structure_id": record.structure_id,
				"position": _vector_json(position),
				"current": _vector_json(current),
				"idle_displacement": _vector_json(displacement),
				"camera_target_lead": _vector_json(camera_target_lead),
			})
			return record
	return {}


func _record_clearance_ab(points: Array[Vector2]) -> void:
	var baseline_value: Variant = _map.call("navigation_snapshot", 35.0)
	var broad_value: Variant = _map.call("navigation_snapshot", 52.5)
	var samples: Array[Dictionary] = []
	var baseline_clear := 0
	var broad_clear := 0
	var physical_clear := 0
	for point in points:
		var baseline_ok := bool(baseline_value.call("is_position_clear", point))
		var broad_ok := bool(broad_value.call("is_position_clear", point))
		var physical_ok := _pose_clear(point, 0.0) or _pose_clear(point, PI * 0.5)
		baseline_clear += 1 if baseline_ok else 0
		broad_clear += 1 if broad_ok else 0
		physical_clear += 1 if physical_ok else 0
		samples.append({
			"position": _vector_json(point),
			"square_35": baseline_ok,
			"square_52_5": broad_ok,
			"real_capsule_any_orientation": physical_ok,
		})
	_report.clearance_ab = {
		"non_blocking_report_only": true,
		"sample_count": points.size(),
		"square_35_clear": baseline_clear,
		"square_52_5_clear": broad_clear,
		"real_capsule_clear": physical_clear,
		"samples": samples,
	}
	print("CLEARANCE_AB square35=%d square52.5=%d real_capsule=%d samples=%d (report-only)" % [baseline_clear, broad_clear, physical_clear, points.size()])


func _pose_clear(position: Vector2, root_angle: float) -> bool:
	var space := _diver.get_world_2d().direct_space_state
	for record in _shape_records:
		if not space.intersect_shape(_shape_query(record, position, root_angle), 1).is_empty():
			return false
	return true


func _motion_clear(start: Vector2, finish: Vector2, root_angle: float) -> bool:
	var motion := finish - start
	var space := _diver.get_world_2d().direct_space_state
	for record in _shape_records:
		var query := _shape_query(record, start, root_angle)
		query.motion = motion
		var fractions := space.cast_motion(query)
		if fractions.size() < 2 or float(fractions[0]) < 0.995:
			return false
	return _pose_clear(finish, root_angle)


func _shape_query(record: Dictionary, position: Vector2, root_angle: float) -> PhysicsShapeQueryParameters2D:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = record.shape
	query.transform = Transform2D(root_angle, position) * (record.local_transform as Transform2D)
	query.collision_mask = _diver.collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var excluded: Array[RID] = [_diver.get_rid()]
	query.exclude = excluded
	query.margin = QUERY_MARGIN
	return query


func _aligned_root_angle(axis: Vector2) -> float:
	var local_transform := _shape_records[0].get("local_transform", Transform2D.IDENTITY) as Transform2D
	var zero_rect := _transformed_rect((_shape_records[0].shape as Shape2D).get_rect(), local_transform)
	var long_axis_horizontal := zero_rect.size.x >= zero_rect.size.y
	var wants_horizontal := absf(axis.x) >= absf(axis.y)
	return 0.0 if long_axis_horizontal == wants_horizontal else PI * 0.5


func _owned_physical_shapes(diver: CharacterBody2D) -> Array[CollisionShape2D]:
	var result: Array[CollisionShape2D] = []
	for value in diver.find_children("*", "CollisionShape2D", true, false):
		var shape_node := value as CollisionShape2D
		if shape_node == null or shape_node.disabled or shape_node.shape == null:
			continue
		var owner: Node = shape_node.get_parent()
		while owner != null and not owner is CollisionObject2D:
			owner = owner.get_parent()
		if owner == diver:
			result.append(shape_node)
	return result


func _body_has_active_shape(body: CollisionObject2D) -> bool:
	for value in body.find_children("*", "CollisionShape2D", true, false):
		var shape := value as CollisionShape2D
		if shape != null and not shape.disabled and shape.shape != null:
			return true
	return false


func _find_real_diver(scope: Node) -> CharacterBody2D:
	var candidates: Array[CharacterBody2D] = []
	for value in scope.find_children("*", "CharacterBody2D", true, false):
		var body := value as CharacterBody2D
		if body != null and body.has_method("simulate_motion_tick") and body.has_method("reset_at"):
			candidates.append(body)
	_assert(candidates.size() == 1, "Publiczny seam DiveScene musi zawierać dokładnie jeden CharacterBody2D z simulate_motion_tick/reset_at.")
	return candidates[0] if candidates.size() == 1 else null


func _find_dive_map(scope: Node) -> Node2D:
	var candidates: Array[Node2D] = []
	for value in scope.find_children("*", "Node2D", true, false):
		var node := value as Node2D
		if node != null and node.has_method("current_at") and node.has_method("update_streaming") and node.has_method("navigation_snapshot"):
			candidates.append(node)
	_assert(candidates.size() == 1, "Publiczny seam DiveScene musi zawierać dokładnie jedną mapę runtime.")
	return candidates[0] if candidates.size() == 1 else null


func _find_gameplay_camera(diver: CharacterBody2D) -> Camera2D:
	var candidates: Array[Camera2D] = []
	for value in diver.find_children("*", "Camera2D", true, false):
		var camera := value as Camera2D
		if camera != null:
			candidates.append(camera)
	_assert(candidates.size() == 1, "Publiczny Nurek musi mieć dokładnie jedną Camera2D niezależnie od nazwy dziecka.")
	return candidates[0] if candidates.size() == 1 else null


func _find_structure_roots(dive_map: Node2D) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for value in dive_map.find_children("*", "Node2D", true, false):
		var node := value as Node2D
		if node == null or str(node.get_meta(&"structure_id", "")).is_empty():
			continue
		if node.get_node_or_null("StaticCollision") is StaticBody2D and node.get_meta(&"size", null) is Vector2:
			result.append(node)
	result.sort_custom(func(left: Node2D, right: Node2D) -> bool:
		return str(left.get_meta(&"structure_id", "")) < str(right.get_meta(&"structure_id", ""))
	)
	return result


func _load_structure_manifest(structure_root: Node2D) -> Dictionary:
	var path := str(structure_root.get_meta(&"package_manifest_path", ""))
	if path.is_empty():
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _transformed_rect(rect: Rect2, transform: Transform2D) -> Rect2:
	var corners := [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	var result := Rect2(transform * corners[0], Vector2.ZERO)
	for index in range(1, corners.size()):
		result = result.expand(transform * corners[index])
	return result


func _rect_from_value(value: Variant) -> Rect2:
	if value is Array and (value as Array).size() == 4:
		var values := value as Array
		return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	return Rect2()


func _vector_from_value(value: Variant) -> Vector2:
	if value is Array and (value as Array).size() == 2:
		var values := value as Array
		return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO


func _vector_json(value: Vector2) -> Array[float]:
	var result: Array[float] = [value.x, value.y]
	return result


func _configure_native_viewport() -> bool:
	root.gui_disable_input = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(CAPTURE_RESOLUTION)
	for _frame in range(60):
		await process_frame
		if Vector2i(root.get_texture().get_size()) == CAPTURE_RESOLUTION:
			return true
	_fail("Native viewport nie osiągnął %s." % CAPTURE_RESOLUTION)
	return false


func _prepare_report_root() -> bool:
	var absolute := ProjectSettings.globalize_path(REPORT_ROOT)
	var error := DirAccess.make_dir_recursive_absolute(absolute)
	if error != OK:
		_fail("Nie można utworzyć izolowanego katalogu raportu: %s." % absolute)
		return false
	return true


func _capture_checkpoint(label: String, refresh_ui: bool = true) -> void:
	if not _native_capture or _camera == null:
		return
	_camera.make_current()
	_camera.reset_smoothing()
	_camera.force_update_scroll()
	# The harness disables the production controller's process loop so route replay
	# stays deterministic; refresh its derived HUD once against the final camera
	# transform before recording the visual proof.
	if refresh_ui:
		_dive.call("_update_ui")
	for _frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != CAPTURE_RESOLUTION:
		_fail("Live Camera2D capture %s nie zwrócił obrazu %s." % [label, CAPTURE_RESOLUTION])
		return
	var screen_position := root.get_canvas_transform() * _diver.global_position
	if not Rect2(Vector2.ZERO, Vector2(CAPTURE_RESOLUTION)).has_point(screen_position):
		_fail("Nurek jest poza live Camera2D capture %s: %s." % [label, screen_position])
		return
	var file_name := "%s.png" % label
	var save_path := REPORT_ROOT.path_join(file_name)
	if image.save_png(ProjectSettings.globalize_path(save_path)) != OK:
		_fail("Nie można zapisać live Camera2D capture %s." % save_path)
		return
	_report.captures.append({
		"file": file_name,
		"checkpoint": label,
		"diver_position": _vector_json(_diver.global_position),
		"diver_screen_position": _vector_json(screen_position),
		"camera_path": str(_camera.get_path()),
		"camera_parent_scene": _diver.scene_file_path,
	})


func _save_report() -> void:
	_report["source"] = {
		"dive_scene_sha256": FileAccess.get_sha256(DIVE_SCENE_PATH),
		"diver_scene_path": _diver.scene_file_path,
		"diver_scene_sha256": FileAccess.get_sha256(_diver.scene_file_path),
		"native_capture": _native_capture,
	}
	var path := REPORT_ROOT.path_join(REPORT_FILE)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Nie można otworzyć raportu %s." % path)
		return
	file.store_string(JSON.stringify(_report, "  "))
	var error := file.get_error()
	file.close()
	if error != OK:
		_fail("Nie można zapisać raportu %s." % path)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("Diver 105x60 live DiveScene clearance integration passed: %s." % REPORT_ROOT)
	quit(0)
