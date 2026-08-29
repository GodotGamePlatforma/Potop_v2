extends SceneTree

const PACKAGE_MANIFEST_PATH := "res://underwater_map_workbench/structures/tower_three_inlets_02/structure_manifest.json"
const PACKAGE_ROOT := "res://underwater_map_workbench/structures/tower_three_inlets_02/"
const STRUCTURE_ID := "tower_three_inlets_02"
const CONTROL_IDS := ["panel_a", "inlet_b", "inlet_c", "d_v1", "d_v2", "d_reset", "inlet_d"]
const BARRIER_IDS := ["g1", "c_shortcut", "g2", "h3", "facade"]
const DIVE_PLAYER_GROUP := &"dive_player"
const ROOT_START := Vector2(320.0, -180.0)
const ROOT_MOVE_DELTA := Vector2(440.0, 260.0)
const COLLISION_GRID_WORLD_UNITS := 40.0
const DIVE_INTERACTION_RANGE := 125.0
const DIVER_HALF_HEIGHT := 20.0
const MAX_MOTION_FRAMES := 720

var _failed := false
var _package_manifest: Dictionary = {}
var _effective_structure: Dictionary = {}
var _controller_script: Script
var _moving_body_script: Script


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_package_manifest = _load_package_manifest()
	if _package_manifest.is_empty():
		_finish()
		return
	_controller_script = _load_controller_script(_package_manifest)
	_moving_body_script = _load_script_by_role(_package_manifest, "moving_body")
	if _controller_script == null or _moving_body_script == null:
		_finish()
		return
	_verify_typed_egress_visual_dispatch()
	_effective_structure = _effective_structure_record(_package_manifest)
	if _effective_structure.is_empty():
		_finish()
		return
	_assert(not _effective_structure.has("origin"), "Prywatny runtime test nie może kopiować mapowego originu.")
	_assert(not _effective_structure.has("attempt_state"), "Resolved host record nie może kopiować package-local attempt_state.")

	var mounted := _mount_runtime("TowerThreeInlets02", ROOT_START)
	var structure_root := mounted.get("root") as Node2D
	var interactives := mounted.get("interactives") as Node2D
	var controller = mounted.get("controller")
	if structure_root == null or interactives == null or controller == null:
		_finish()
		return
	await process_frame
	await physics_frame

	_verify_runtime_shape(controller, interactives)
	var initial_dynamic_positions := _dynamic_positions(controller)
	_verify_s0(controller)
	_verify_currents_s0(controller, structure_root)
	_verify_portable_root(controller, structure_root)
	_verify_read_only_panel(controller)
	await _verify_sequence_and_motion(controller, structure_root)
	await _verify_safety_filters(controller, structure_root)
	_verify_reset_attempt(controller, initial_dynamic_positions)
	_verify_fresh_instance()
	structure_root.free()
	_finish()


func _verify_runtime_shape(controller, interactives: Node2D) -> void:
	_assert(str(controller.get_meta(&"structure_id", "")) == STRUCTURE_ID, "Controller musi dostać stable ID W02.")
	_assert(str(controller.get_meta(&"runtime_contract", "")) == "three_inlets_tower_sequence_v1", "Controller musi skonsumować kontrakt three_inlets_tower_sequence_v1.")
	_assert(str(controller.get_meta(&"persistence", "")) == "none" and str(controller.get_meta(&"checkpoint", "")) == "none", "Controller musi jawnie pozostać bez persistence i checkpointu.")
	_assert(not _has_property(controller, &"persistent_id"), "Controller W02 nie może publikować persistent_id.")
	_assert(interactives.get_child_count() == CONTROL_IDS.size(), "Runtime W02 musi utworzyć dokładnie siedem controls.")
	for control_id: String in CONTROL_IDS:
		var interactive = controller.control(control_id)
		_assert(interactive is Area2D, "Control %s musi być Area2D." % control_id)
		if interactive is Area2D:
			_assert(not _has_property(interactive, &"persistent_id"), "Control %s nie może publikować persistent_id." % control_id)
	var dynamic_bodies: Array[Node] = controller.find_children("*", "AnimatableBody2D", true, false)
	_assert(dynamic_bodies.size() == BARRIER_IDS.size() + 1, "Runtime musi utworzyć pięć barier i jeden ruchomy cabinet_d.")
	for body_value: Variant in dynamic_bodies:
		var body := body_value as AnimatableBody2D
		_assert(body.sync_to_physics, "Każde dynamiczne ciało musi używać sync_to_physics.")
		_assert(body.collision_layer == 1 and body.collision_mask == 0, "Dynamiczne ciało ma blokować fizykę na warstwie 1 bez aktywnego maskowania.")
		var safety := body.get_node_or_null("SafetyEnvelope") as Area2D
		_assert(safety != null, "Każde dynamiczne ciało musi mieć SafetyEnvelope.")
		if safety != null:
			_assert(safety.collision_layer == 0 and safety.collision_mask == 1, "SafetyEnvelope ma tylko wykrywać ciała fizyki nurka.")


func _verify_s0(controller) -> void:
	var snapshot: Dictionary = controller.state_snapshot()
	_assert(str(snapshot.get("sequence_state", "")) == "S0", "Nowa próba W02 musi zaczynać się w S0.")
	_assert(not bool(snapshot.get("b_complete", true)) and not bool(snapshot.get("c_complete", true)) and not bool(snapshot.get("d_complete", true)), "S0 nie może dziedziczyć ukończenia B/C/D.")
	_assert(str(snapshot.get("d_state", "")) == "D_START", "Automat D musi zaczynać się w D_START.")
	_assert(not bool(snapshot.get("d_input_locked", true)), "D w S0 nie może pozostać zablokowane przez poprzednią próbę.")
	_assert(is_equal_approx(float(snapshot.get("central_current_multiplier", -1.0)), 1.0), "S0 musi używać pełnego prądu centralnego.")
	_assert(bool(snapshot.get("b_current_active", false)), "Lokalny prąd B musi być aktywny przed ukończeniem B.")
	_assert(snapshot.get("attempt_state", {}) == {"persistence": "none", "checkpoint": "none"}, "Snapshot musi jawnie potwierdzać attempt-local stan bez checkpointu.")
	for barrier_id: String in BARRIER_IDS:
		_assert(not controller.barrier_is_open(barrier_id), "S0 musi zaczynać z zamkniętą barierą %s." % barrier_id)
	var facade := _barrier_body(controller, "facade")
	var egress_rect := _socket_rect(str((_package_manifest.get("runtime", {}) as Dictionary).get("egress_socket_id", "")))
	_assert(facade != null, "S0 wymaga ruchomej fasady wyjścia.")
	if facade != null:
		_assert(str(facade.call(&"visual_style")) == "egress_grille", "Fasada musi wybierać prezentację przez typowany visual_style=egress_grille.")
		_assert(str(facade.call(&"visual_state")) == "CLOSED", "Fasada w S0 musi publikować wizualny stan CLOSED.")
		_assert(is_zero_approx(float(facade.call(&"aperture_clear_fraction"))), "CLOSED musi mieć zerową odsłoniętą część apertury.")
		_assert(not bool(facade.call(&"aperture_is_clear")), "CLOSED nie może raportować pustej apertury.")
		var closed_body_rect: Rect2 = facade.call(&"body_rect_in_parent")
		_assert_rect_approx(closed_body_rect, egress_rect, "Collider i wizual CLOSED muszą dokładnie pokrywać building_egress.")
	_assert(controller.control("panel_a").can_interact(), "S0 musi udostępniać panel A przez zwykłą ścieżkę interakcji gracza.")
	_assert(controller.control("inlet_b").can_interact(), "S0 musi udostępniać B przez zwykłą ścieżkę interakcji.")
	_assert(not controller.control("inlet_c").can_interact(), "S0 nie może udostępniać C przed B.")
	_assert(not controller.control("d_v1").can_interact() and not controller.control("inlet_d").can_interact(), "S0 nie może udostępniać układu D.")
	_assert(not bool(controller.activate_control("inlet_c").get("success", true)), "C nie może ominąć B.")
	_assert(not bool(controller.activate_control("inlet_d").get("success", true)), "D nie może ominąć B i C.")


func _verify_currents_s0(controller, structure_root: Node2D) -> void:
	var currents := (_package_manifest.get("runtime", {}) as Dictionary).get("currents", {}) as Dictionary
	var central := currents.get("central_shaft", {}) as Dictionary
	var b_current := currents.get("inlet_b", {}) as Dictionary
	_assert_vector_approx(
		controller.current_at_world_position(structure_root.to_global(_socket_center(str(central.get("socket_id", ""))))),
		_basis_xform(structure_root.global_transform, _vector2(central.get("velocity", []))),
		"S0: centralny szyb musi zwracać pełny wektor prądu.",
	)
	_assert_vector_approx(
		controller.current_at_world_position(structure_root.to_global(_b_active_sample(b_current))),
		_basis_xform(structure_root.global_transform, _vector2(b_current.get("velocity", []))),
		"S0: aktywna próbka wlotu B musi zwracać jego prąd.",
	)
	_assert_vector_approx(
		controller.current_at_world_position(structure_root.to_global(_socket_center(str((b_current.get("cover_socket_ids", []) as Array)[0])))),
		Vector2.ZERO,
		"S0: osłona B musi tworzyć faktycznie bezpieczną próbkę.",
	)
	_assert_vector_approx(
		controller.current_at_world_position(structure_root.to_global(_socket_center(str(b_current.get("recovery_socket_id", ""))))),
		_basis_xform(structure_root.global_transform, _vector2(b_current.get("recovery_velocity", []))),
		"S0: strefa recovery B musi zwracać wektor odzyskania.",
	)


func _verify_portable_root(controller, structure_root: Node2D) -> void:
	var panel: Area2D = controller.control("panel_a") as Area2D
	var g1 := _barrier_body(controller, "g1")
	var cabinet := _cabinet_body(controller)
	_assert(panel != null and g1 != null and cabinet != null, "Fixture przenoszenia wymaga panelu, g1 i cabinet_d.")
	if panel == null or g1 == null or cabinet == null:
		return
	var panel_before: Vector2 = panel.global_position
	var barrier_before := g1.global_position
	var cabinet_before := cabinet.global_position
	var central := (((_package_manifest.get("runtime", {}) as Dictionary).get("currents", {}) as Dictionary).get("central_shaft", {}) as Dictionary)
	var sample_local := _socket_center(str(central.get("socket_id", "")))
	var old_sample_world := structure_root.to_global(sample_local)
	var expected_current: Vector2 = controller.current_at_world_position(old_sample_world)
	structure_root.position += ROOT_MOVE_DELTA
	_assert(panel.global_position.is_equal_approx(panel_before + ROOT_MOVE_DELTA), "Przesunięcie StructureRoot musi przenieść panel A.")
	_assert(g1.global_position.is_equal_approx(barrier_before + ROOT_MOVE_DELTA), "Przesunięcie StructureRoot musi przenieść collider i grafikę g1.")
	_assert(cabinet.global_position.is_equal_approx(cabinet_before + ROOT_MOVE_DELTA), "Przesunięcie StructureRoot musi przenieść cabinet_d.")
	_assert_vector_approx(controller.current_at_world_position(structure_root.to_global(sample_local)), expected_current, "Prąd struktury musi przenieść się razem z jej rootem.")
	_assert_vector_approx(controller.current_at_world_position(old_sample_world), Vector2.ZERO, "Po przesunięciu rootu stary punkt nie może zachować drugiej kopii prądu.")
	structure_root.position -= ROOT_MOVE_DELTA


func _verify_read_only_panel(controller) -> void:
	var before := _progression_snapshot(controller.state_snapshot())
	var panel = controller.control("panel_a")
	_assert(panel != null and panel.can_interact(), "Panel A musi być dostępny jako fizyczny Area2D dla gracza.")
	if panel == null:
		return
	var result: Dictionary = panel.complete_dive_interaction()
	var after := _progression_snapshot(controller.state_snapshot())
	_assert(before == after, "Panel A musi być read-only i nie może zmieniać S0 ani automatu D.")
	_assert(bool(result.get("success", false)), "Zwykła interakcja gracza z panelem A musi zakończyć się poprawnym odczytem.")
	_assert(bool(result.get("read_only", false)) or str(result.get("effect", "")) == "read_only", "Wynik panelu A musi jawnie komunikować brak mutacji.")


func _verify_sequence_and_motion(controller, structure_root: Node2D) -> void:
	var g1_body := _barrier_body(controller, "g1")
	_assert(g1_body != null, "Sekwencja B wymaga ciała bariery g1.")
	var g1_before := g1_body.position if g1_body != null else Vector2.ZERO
	_assert(bool(controller.control("inlet_b").complete_dive_interaction().get("success", false)), "Prawidłowa interakcja gracza z B musi przejść z S0 do S1.")
	_assert(controller.barrier_is_commanded_open("g1") and not controller.barrier_is_open("g1"), "G1 musi rozróżniać żądanie otwarcia od fizycznie osiągniętej pozycji.")
	for _frame: int in range(3):
		await physics_frame
	if g1_body != null:
		_assert(not g1_body.position.is_equal_approx(g1_before), "g1 musi faktycznie poruszyć AnimatableBody2D po B.")
	await _await_barrier_target(controller, "g1")
	_assert(controller.barrier_is_open("g1") and controller.barrier_reached_target("g1"), "Po B g1 musi być otwarta i osiągnąć pozycję docelową.")
	_assert(not controller.barrier_is_open("g2") and not controller.barrier_is_open("facade"), "B nie może przedwcześnie otworzyć G2 ani fasady.")
	_verify_stage(controller, "S1", true, false, false, 2.0 / 3.0)
	_assert(not controller.control("inlet_b").can_interact() and controller.control("inlet_c").can_interact(), "S1 musi wyłączyć B i udostępnić C przez zwykły gameplay.")
	_verify_b_current_disabled(controller, structure_root)

	_assert(bool(controller.control("inlet_c").complete_dive_interaction().get("success", false)), "Prawidłowa interakcja gracza z C musi przejść z S1 do S2.")
	await _await_barrier_target(controller, "c_shortcut")
	await _await_barrier_target(controller, "g2")
	_assert(controller.barrier_is_open("c_shortcut") and controller.barrier_reached_target("c_shortcut"), "C musi otworzyć trwały skrót powrotny.")
	_assert(controller.barrier_is_open("g2") and controller.barrier_reached_target("g2"), "C musi otworzyć G2.")
	_assert(not controller.barrier_is_open("h3") and not controller.barrier_is_open("facade"), "C nie może przedwcześnie otworzyć H3 ani fasady.")
	_verify_stage(controller, "S2", true, true, false, 1.0 / 3.0)
	_assert(not controller.control("inlet_c").can_interact(), "S2 musi wyłączyć ukończony wlot C.")
	_verify_d_controls_not_reachable_through_ceiling(controller, structure_root)

	_assert(controller.control("d_v1").can_interact() and controller.control("d_v2").can_interact(), "W stabilnym D_START oba zawory muszą być osiągalne przez zwykły gameplay.")
	_assert(not controller.control("inlet_d").can_interact(), "Dźwignia D nie może być dostępna przed odsłonięciem przez szafę.")
	var premature_d_result: Dictionary = controller.activate_control("inlet_d")
	_assert(not bool(premature_d_result.get("success", true)), "Bezpośrednia próba D przed V1/V2 musi zostać bezpiecznie odrzucona.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_ERROR_SAFE", "Przedwczesne D musi publikować D_ERROR_SAFE.")
	_assert(bool(controller.control("d_reset").complete_dive_interaction().get("success", false)), "RESET musi naprawić przedwczesną próbę dźwigni D.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_START", "RESET po przedwczesnym D musi wrócić do D_START.")
	var wrong_order_result: Dictionary = controller.control("d_v2").complete_dive_interaction()
	_assert(not bool(wrong_order_result.get("success", true)), "D: zwykła interakcja V2 przed V1 musi wejść w błąd kolejności.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_ERROR_SAFE", "D: zła kolejność musi publikować D_ERROR_SAFE.")
	_assert(controller.control("d_reset").can_interact(), "D_ERROR_SAFE musi udostępnić fizyczny RESET.")
	_assert(not bool(controller.activate_control("d_v1").get("success", true)), "D_ERROR_SAFE musi blokować dalszy krok do resetu.")
	_assert(bool(controller.activate_control("d_reset").get("success", false)), "D: reset w stabilnym stanie błędu musi przywrócić D_START.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_START", "D reset musi wrócić do D_START.")
	_assert(controller.control("d_v1").can_interact() and controller.control("d_v2").can_interact(), "Po RESET oba zawory muszą znów być dostępne w stabilnym D_START.")

	var cabinet := _cabinet_body(controller)
	_assert(cabinet != null, "Automat D wymaga AnimatableBody2D cabinet_d.")
	if cabinet == null:
		return
	var cabinet_start := cabinet.position if cabinet != null else Vector2.ZERO
	var cabinet_definition := ((_package_manifest.get("runtime", {}) as Dictionary).get("cabinet", {}) as Dictionary)
	var cabinet_right_target := cabinet_start + _vector2(cabinet_definition.get("move_right", []))
	var v1_sweep_block_local := cabinet_right_target + Vector2(120.0, 0.0)
	var v1_preflight_diver := _make_character("CabinetV1PreflightDivePlayer", true)
	structure_root.add_child(v1_preflight_diver)
	v1_preflight_diver.global_position = (cabinet.get_parent() as Node2D).to_global(v1_sweep_block_local)
	await physics_frame
	await physics_frame
	_assert(not bool(controller.control("d_v1").complete_dive_interaction().get("success", true)), "V1 musi odmówić aktywacji, gdy dive_player znajduje się w pełnej trasie zamiatania.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_START" and cabinet.position.is_equal_approx(cabinet_start), "Odrzucony preflight V1 nie może uruchomić ruchu ani zmienić stanu.")
	v1_preflight_diver.queue_free()
	await physics_frame
	_assert(bool(controller.control("d_v1").complete_dive_interaction().get("success", false)), "D: zwykła interakcja V1 musi rozpocząć ruch cabinet_d w prawo.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_MOVING_RIGHT", "D: V1 musi wejść w D_MOVING_RIGHT.")
	_assert(bool(controller.state_snapshot().get("d_input_locked", false)), "D: input musi być zablokowany w czasie ruchu w prawo.")
	_assert(not controller.control("d_v1").can_interact() and not controller.control("d_v2").can_interact() and not controller.control("d_reset").can_interact(), "Podczas ruchu w prawo controls D muszą być fizycznie niedostępne.")
	_assert(not bool(controller.activate_control("d_v2").get("success", true)), "D: V2 podczas ruchu V1 musi zostać odrzucony.")
	_assert(not bool(controller.activate_control("d_reset").get("success", true)), "D: reset podczas ruchu cabinet_d musi zostać odrzucony.")
	var v1_motion_diver := _make_character("CabinetV1MotionDivePlayer", true)
	structure_root.add_child(v1_motion_diver)
	v1_motion_diver.global_position = (cabinet.get_parent() as Node2D).to_global(v1_sweep_block_local)
	await physics_frame
	await physics_frame
	var before_large_step := cabinet.position
	_assert(not cabinet.advance_motion(10.0), "Pełny sweep musi zatrzymać także sztucznie duży krok delta V1.")
	_assert(cabinet.position.is_equal_approx(before_large_step), "Odrzucony duży krok nie może przeskoczyć przez nurka.")
	for _frame: int in range(60):
		await physics_frame
	var held_position := cabinet.position
	for _frame: int in range(5):
		await physics_frame
	_assert(cabinet.position.is_equal_approx(held_position) and not controller.cabinet_reached_target(), "SafetyEnvelope musi zatrzymać aktywny ruch V1 przed dive_player.")
	v1_motion_diver.queue_free()
	await physics_frame
	await _await_cabinet_target(controller)
	_assert(cabinet.position.x > cabinet_start.x and is_equal_approx(cabinet.position.y, cabinet_start.y), "Po zwolnieniu trasy cabinet_d musi wznowić ruch w prawo.")
	var after_right := cabinet.position if cabinet != null else Vector2.ZERO
	_assert(controller.cabinet_reached_target(), "D: cabinet_d musi osiągnąć prawy cel przed V2.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_RIGHT_STOP", "D: prawy cel musi publikować D_RIGHT_STOP.")
	_assert(not bool(controller.state_snapshot().get("d_input_locked", true)), "D: po ruchu w prawo input ma zostać odblokowany.")
	_assert(controller.control("d_v1").can_interact() and controller.control("d_v2").can_interact(), "W stabilnym D_RIGHT_STOP oba zawory muszą pozostać osiągalne, także dla ścieżki błędu.")
	var repeated_v1_result: Dictionary = controller.control("d_v1").complete_dive_interaction()
	_assert(not bool(repeated_v1_result.get("success", true)), "Powtórne V1 w D_RIGHT_STOP musi wejść w bezpieczny błąd kolejności.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_ERROR_SAFE", "Powtórne V1 musi publikować D_ERROR_SAFE bez ruchu poza prowadnicę.")
	_assert(bool(controller.control("d_reset").complete_dive_interaction().get("success", false)), "RESET musi naprawić błąd powtórnego V1.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_START" and cabinet.position.is_equal_approx(cabinet_start), "RESET po powtórnym V1 musi przywrócić pełny start D.")
	_assert(bool(controller.control("d_v1").complete_dive_interaction().get("success", false)), "Po resecie V1 musi ponownie uruchomić poprawny ruch.")
	await _await_cabinet_target(controller)
	after_right = cabinet.position
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_RIGHT_STOP", "Po teście powtórnego V1 fixture musi wrócić do D_RIGHT_STOP.")

	var return_path_midpoint := cabinet_start.lerp(after_right, 0.5)
	var decoy := _make_character("CabinetResetDecoy", false)
	structure_root.add_child(decoy)
	decoy.global_position = (cabinet.get_parent() as Node2D).to_global(return_path_midpoint)
	await physics_frame
	await physics_frame
	_assert(bool(controller.control("d_reset").complete_dive_interaction().get("success", false)), "Zwykły CharacterBody2D nie może zablokować bezpiecznego RESET szafy.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_START", "RESET ignorujący decoy musi faktycznie przywrócić D_START.")
	decoy.queue_free()
	await physics_frame
	_assert(bool(controller.control("d_v1").complete_dive_interaction().get("success", false)), "Po bezpiecznym RESET V1 musi ponownie uruchomić ruch w prawo.")
	await _await_cabinet_target(controller)
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_RIGHT_STOP", "Powtórzony V1 musi znów osiągnąć D_RIGHT_STOP.")
	after_right = cabinet.position if cabinet != null else Vector2.ZERO
	return_path_midpoint = cabinet_start.lerp(after_right, 0.5)
	var diver_in_return_path := _make_character("CabinetResetDivePlayer", true)
	structure_root.add_child(diver_in_return_path)
	diver_in_return_path.global_position = (cabinet.get_parent() as Node2D).to_global(return_path_midpoint)
	await physics_frame
	await physics_frame
	_assert(not bool(controller.control("d_reset").complete_dive_interaction().get("success", true)), "RESET musi odmówić teleportu, gdy w przemiatanej trasie stoi dive_player.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_RIGHT_STOP" and cabinet.position.is_equal_approx(after_right), "Odrzucony RESET nie może zmienić stanu ani położenia cabinet_d.")
	diver_in_return_path.queue_free()
	await physics_frame
	_assert(bool(controller.control("d_reset").complete_dive_interaction().get("success", false)), "Po usunięciu dive_player z przemiatanej trasy ten sam RESET musi przejść.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_START" and cabinet.position.is_equal_approx(cabinet_start), "Dozwolony RESET musi przywrócić D_START i pozycję startową szafy.")
	_assert(bool(controller.control("d_v1").complete_dive_interaction().get("success", false)), "Po zwolnieniu trasy V1 musi ponownie doprowadzić cabinet_d do prawego przystanku.")
	await _await_cabinet_target(controller)
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_RIGHT_STOP", "Fixture po bezpiecznym RESET musi wrócić do D_RIGHT_STOP przed V2.")
	after_right = cabinet.position

	var cabinet_down_target := after_right + _vector2(cabinet_definition.get("move_down", []))
	var v2_preflight_diver := _make_character("CabinetV2PreflightDivePlayer", true)
	structure_root.add_child(v2_preflight_diver)
	v2_preflight_diver.global_position = (cabinet.get_parent() as Node2D).to_global(after_right.lerp(cabinet_down_target, 0.65))
	await physics_frame
	await physics_frame
	_assert(not bool(controller.control("d_v2").complete_dive_interaction().get("success", true)), "V2 musi odmówić aktywacji, gdy dive_player znajduje się w pionowej trasie zamiatania.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_RIGHT_STOP" and cabinet.position.is_equal_approx(after_right), "Odrzucony preflight V2 nie może uruchomić ruchu ani zmienić stanu.")
	v2_preflight_diver.queue_free()
	await physics_frame
	_assert(bool(controller.control("d_v2").complete_dive_interaction().get("success", false)), "D: zwykła interakcja V2 po ukończeniu V1 musi rozpocząć ruch w dół.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_MOVING_DOWN", "D: V2 musi wejść w D_MOVING_DOWN.")
	_assert(bool(controller.state_snapshot().get("d_input_locked", false)), "D: input musi być zablokowany w czasie ruchu w dół.")
	_assert(not controller.control("d_v1").can_interact() and not controller.control("d_v2").can_interact() and not controller.control("inlet_d").can_interact(), "Podczas ruchu w dół controls D muszą być fizycznie niedostępne.")
	_assert(not bool(controller.activate_control("inlet_d").get("success", true)), "D: finalny wlot podczas ruchu V2 musi zostać odrzucony.")
	for _frame: int in range(3):
		await physics_frame
	if cabinet != null:
		_assert(is_equal_approx(cabinet.position.x, after_right.x) and cabinet.position.y > after_right.y, "D: cabinet_d musi faktycznie rozpocząć ruch w dół po V2.")
	await _await_cabinet_target(controller)
	_assert(controller.cabinet_reached_target() and not bool(controller.state_snapshot().get("d_input_locked", true)), "D: cabinet_d musi osiągnąć dolny cel i odblokować finalny wlot.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_INLET_EXPOSED", "D: dolny cel musi publikować D_INLET_EXPOSED.")
	_assert(controller.control("inlet_d").can_interact(), "D_INLET_EXPOSED musi udostępnić finalną dźwignię w gameplayu.")
	_assert(bool(controller.control("inlet_d").complete_dive_interaction().get("success", false)), "D: zwykła interakcja finalnego wlotu po V1 i V2 musi ukończyć sekwencję.")
	_assert(str(controller.state_snapshot().get("d_state", "")) == "D_COMPLETE", "D: finalny wlot musi publikować D_COMPLETE.")
	_assert(controller.barrier_is_commanded_open("facade") and not controller.barrier_is_open("facade"), "Fasada nie może raportować faktycznego otwarcia przed osiągnięciem celu ruchu.")
	var facade := _barrier_body(controller, "facade")
	_assert(facade != null, "Sekwencja D wymaga ciała egress_grille.")
	var closed_clear_fraction := float(facade.call(&"aperture_clear_fraction")) if facade != null else -1.0
	var mid_clear_fraction := await _await_facade_mid_state(controller, facade)
	_assert(mid_clear_fraction > closed_clear_fraction and mid_clear_fraction < 1.0, "MID musi monotonicznie odsłonić część apertury bez przedwczesnego OPEN.")
	await _await_barrier_target(controller, "h3")
	await _await_barrier_target(controller, "facade")
	_verify_stage(controller, "S3", true, true, true, 0.0)
	_assert(controller.barrier_is_open("h3") and controller.barrier_reached_target("h3"), "Po D H3 musi być otwarta.")
	_assert(controller.barrier_is_open("facade") and controller.barrier_reached_target("facade"), "Po D fasada/wyjście musi być faktycznie otwarta.")
	if facade != null:
		var open_clear_fraction := float(facade.call(&"aperture_clear_fraction"))
		_assert(str(facade.call(&"visual_state")) == "OPEN", "Fasada po osiągnięciu celu musi publikować wizualny stan OPEN.")
		_assert(open_clear_fraction > mid_clear_fraction and is_equal_approx(open_clear_fraction, 1.0), "OPEN musi monotonicznie osiągnąć w pełni pustą aperturę.")
		_assert(bool(facade.call(&"aperture_is_clear")), "OPEN musi potwierdzić rozłączność collidera fasady i building_egress.")
		var open_body_rect: Rect2 = facade.call(&"body_rect_in_parent")
		var aperture_rect: Rect2 = facade.call(&"aperture_rect_in_parent")
		_assert(not open_body_rect.intersects(aperture_rect), "AABB ruchomego collidera OPEN nie może przecinać drogi do oceanu.")
	_assert(not bool(controller.activate_control("d_reset").get("success", true)), "D: reset nie może cofnąć ukończonej próby.")
	_assert(str(controller.state_snapshot().get("sequence_state", "")) == "S3", "Odrzucony reset po ukończeniu nie może zamknąć wyjścia.")


func _verify_b_current_disabled(controller, structure_root: Node2D) -> void:
	var b_current := (((_package_manifest.get("runtime", {}) as Dictionary).get("currents", {}) as Dictionary).get("inlet_b", {}) as Dictionary)
	var sample_points := {
		"active": _b_active_sample(b_current),
		"cover": _socket_center(str((b_current.get("cover_socket_ids", []) as Array)[0])),
		"recovery": _socket_center(str(b_current.get("recovery_socket_id", ""))),
	}
	for sample_id: String in sample_points:
		var sample_point: Vector2 = sample_points[sample_id]
		_assert_vector_approx(
			controller.current_at_world_position(structure_root.to_global(sample_point)),
			Vector2.ZERO,
			"Po B próbka %s lokalnego wlotu musi być wyłączona." % sample_id,
		)


func _verify_d_controls_not_reachable_through_ceiling(controller, structure_root: Node2D) -> void:
	var upper_floor := _collision_operation_rect("tower_three_inlets_02_floor_05_left")
	_assert(upper_floor.size.x > 0.0 and upper_floor.size.y > 0.0, "Test D wymaga geometrii piętra P.05 nad komorą.")
	if upper_floor.size.x <= 0.0 or upper_floor.size.y <= 0.0:
		return
	var upper_player_center_y := upper_floor.end.y - DIVER_HALF_HEIGHT
	for control_id: String in ["d_v1", "d_v2"]:
		var interactive = controller.control(control_id)
		_assert(interactive is Area2D, "Test zasięgu przez strop wymaga Area2D %s." % control_id)
		if not interactive is Area2D:
			continue
		var control_area := interactive as Area2D
		var control_local := structure_root.to_local(control_area.global_position)
		var probe_world := structure_root.to_global(Vector2(control_local.x, upper_player_center_y))
		var distance := float(interactive.call(&"interaction_distance_to", probe_world))
		_assert(
			distance > DIVE_INTERACTION_RANGE,
			"%s nie może być obsługiwany z P.05 przez strop (distance=%.1f, host range=%.1f)." % [control_id, distance, DIVE_INTERACTION_RANGE],
		)


func _verify_stage(controller, expected_state: String, b_complete: bool, c_complete: bool, d_complete: bool, expected_multiplier: float) -> void:
	var snapshot: Dictionary = controller.state_snapshot()
	_assert(str(snapshot.get("sequence_state", "")) == expected_state, "Niepoprawny stan sekwencji: oczekiwano %s, jest %s." % [expected_state, snapshot])
	_assert(bool(snapshot.get("b_complete", false)) == b_complete, "%s ma niepoprawny b_complete." % expected_state)
	_assert(bool(snapshot.get("c_complete", false)) == c_complete, "%s ma niepoprawny c_complete." % expected_state)
	_assert(bool(snapshot.get("d_complete", false)) == d_complete, "%s ma niepoprawny d_complete." % expected_state)
	_assert(is_equal_approx(float(snapshot.get("central_current_multiplier", -1.0)), expected_multiplier), "%s ma niepoprawny mnożnik centralnego prądu." % expected_state)
	var central := (((_package_manifest.get("runtime", {}) as Dictionary).get("currents", {}) as Dictionary).get("central_shaft", {}) as Dictionary)
	var structure_root := controller.get_parent().get_parent() as Node2D
	if structure_root != null:
		var expected_vector := _basis_xform(structure_root.global_transform, _vector2(central.get("velocity", []))) * expected_multiplier
		_assert_vector_approx(controller.current_at_world_position(structure_root.to_global(_socket_center(str(central.get("socket_id", ""))))), expected_vector, "%s musi stosować właściwy centralny prąd także przez API world position." % expected_state)


func _verify_safety_filters(controller, structure_root: Node2D) -> void:
	var g1 := _barrier_body(controller, "g1")
	var cabinet := _cabinet_body(controller)
	_assert(g1 != null and cabinet != null, "Test safety wymaga g1 i cabinet_d.")
	if g1 == null or cabinet == null:
		return
	await _assert_safety_filters_one_body(controller, structure_root, g1, "g1")
	await _assert_safety_filters_one_body(controller, structure_root, cabinet, "cabinet_d")


func _assert_safety_filters_one_body(controller, structure_root: Node2D, dynamic_body: AnimatableBody2D, dynamic_id: String) -> void:
	var safety := dynamic_body.get_node_or_null("SafetyEnvelope") as Area2D
	_assert(safety != null, "%s wymaga SafetyEnvelope." % dynamic_id)
	if safety == null:
		return
	var decoy := _make_character("NonDiverDecoy", false)
	structure_root.add_child(decoy)
	decoy.global_position = safety.global_position
	await physics_frame
	await physics_frame
	var decoy_clear: bool = controller.cabinet_safety_clear() if dynamic_id == "cabinet_d" else controller.barrier_safety_clear(dynamic_id)
	_assert(decoy_clear, "%s nie może traktować zwykłego CharacterBody2D jako nurka." % dynamic_id)
	decoy.queue_free()
	await physics_frame

	var diver := _make_character("DivePlayerBlocker", true)
	structure_root.add_child(diver)
	diver.global_position = safety.global_position
	await physics_frame
	await physics_frame
	var diver_clear: bool = controller.cabinet_safety_clear() if dynamic_id == "cabinet_d" else controller.barrier_safety_clear(dynamic_id)
	_assert(not diver_clear, "%s musi zatrzymać ruch, gdy SafetyEnvelope zajmuje dive_player." % dynamic_id)
	diver.queue_free()
	await physics_frame


func _verify_reset_attempt(controller, initial_dynamic_positions: Dictionary) -> void:
	controller.reset_attempt()
	var snapshot: Dictionary = controller.state_snapshot()
	_assert(str(snapshot.get("sequence_state", "")) == "S0", "reset_attempt musi przywrócić S0.")
	_assert(str(snapshot.get("d_state", "")) == "D_START" and not bool(snapshot.get("d_input_locked", true)), "reset_attempt musi wyzerować pełny automat D.")
	_assert(not bool(snapshot.get("b_complete", true)) and not bool(snapshot.get("c_complete", true)) and not bool(snapshot.get("d_complete", true)), "reset_attempt musi wyzerować B/C/D.")
	_assert(is_equal_approx(float(snapshot.get("central_current_multiplier", -1.0)), 1.0) and bool(snapshot.get("b_current_active", false)), "reset_attempt musi odtworzyć prądy S0.")
	for barrier_id: String in BARRIER_IDS:
		_assert(not controller.barrier_is_open(barrier_id), "reset_attempt musi zamknąć %s." % barrier_id)
		var body := _barrier_body(controller, barrier_id)
		_assert(body != null and controller.barrier_reached_target(barrier_id), "reset_attempt musi domknąć fizyczny ruch %s." % barrier_id)
		if body != null:
			_assert(body.position.is_equal_approx(initial_dynamic_positions.get(barrier_id, Vector2.INF)), "reset_attempt musi przywrócić pozycję początkową bariery %s." % barrier_id)
			if barrier_id == "facade":
				_assert(str(body.call(&"visual_state")) == "CLOSED", "reset_attempt musi przywrócić prezentację fasady CLOSED.")
				_assert(is_zero_approx(float(body.call(&"aperture_clear_fraction"))) and not bool(body.call(&"aperture_is_clear")), "reset_attempt musi ponownie zamknąć aperturę wyjścia.")
	var cabinet := _cabinet_body(controller)
	_assert(controller.cabinet_reached_target(), "reset_attempt musi odstawić cabinet_d do pozycji początkowej bez checkpointu.")
	if cabinet != null:
		_assert(cabinet.position.is_equal_approx(initial_dynamic_positions.get("cabinet_d", Vector2.INF)), "reset_attempt musi przywrócić dokładną pozycję startową cabinet_d.")
	var first_reset_state := _progression_snapshot(controller.state_snapshot())
	var first_reset_positions := _dynamic_positions(controller)
	controller.reset_attempt()
	_assert(_progression_snapshot(controller.state_snapshot()) == first_reset_state, "Powtórny reset_attempt w już wyzerowanej próbie musi być logicznie idempotentny.")
	_assert(_dynamic_positions(controller) == first_reset_positions, "Powtórny reset_attempt nie może przemieścić żadnej bariery ani cabinet_d.")
	_assert(controller.control("inlet_b").can_interact(), "Po reset_attempt B musi znów być dostępne.")
	_assert(not controller.control("inlet_c").can_interact() and not controller.control("d_v1").can_interact() and not controller.control("inlet_d").can_interact(), "Po reset_attempt C i D muszą pozostać niedostępne do swojej kolejności.")


func _verify_fresh_instance() -> void:
	var mounted := _mount_runtime("FreshTowerThreeInlets02", Vector2(-800.0, 620.0))
	var fresh_root := mounted.get("root") as Node2D
	var fresh_controller = mounted.get("controller")
	if fresh_controller != null:
		var snapshot: Dictionary = fresh_controller.state_snapshot()
		_assert(str(snapshot.get("sequence_state", "")) == "S0" and str(snapshot.get("d_state", "")) == "D_START", "Nowa instancja nie może odziedziczyć sekwencji ani automatu D.")
		_assert(snapshot.get("attempt_state", {}) == {"persistence": "none", "checkpoint": "none"}, "Nowa instancja musi pozostać bez zapisu i checkpointu.")
		for barrier_id: String in BARRIER_IDS:
			_assert(not fresh_controller.barrier_is_open(barrier_id), "Nowa instancja nie może odziedziczyć otwartej bariery %s." % barrier_id)
	if fresh_root != null:
		fresh_root.free()


func _mount_runtime(node_name: String, local_position: Vector2) -> Dictionary:
	var structure_root := Node2D.new()
	structure_root.name = node_name
	structure_root.position = local_position
	root.add_child(structure_root)
	var dynamic_bodies := Node2D.new()
	dynamic_bodies.name = "DynamicBodies"
	structure_root.add_child(dynamic_bodies)
	var interactives := Node2D.new()
	interactives.name = "Interactives"
	structure_root.add_child(interactives)
	var controller = _controller_script.new()
	controller.name = "TowerThreeInletsController"
	dynamic_bodies.add_child(controller)
	var errors = controller.configure(_effective_structure, interactives)
	_assert(errors is PackedStringArray or errors is Array, "configure musi zwrócić listę błędów.")
	_assert(errors.is_empty(), "Poprawny pakiet W02 musi skonfigurować runtime bez błędów: %s." % errors)
	if not errors.is_empty():
		structure_root.free()
		return {}
	return {"root": structure_root, "interactives": interactives, "controller": controller}


func _dynamic_positions(controller) -> Dictionary:
	var positions := {}
	for barrier_id: String in BARRIER_IDS:
		var body := _barrier_body(controller, barrier_id)
		if body != null:
			positions[barrier_id] = body.position
	var cabinet := _cabinet_body(controller)
	if cabinet != null:
		positions["cabinet_d"] = cabinet.position
	return positions


func _load_package_manifest() -> Dictionary:
	var file := FileAccess.open(PACKAGE_MANIFEST_PATH, FileAccess.READ)
	_assert(file != null, "Nie można otworzyć manifestu W02: %s." % PACKAGE_MANIFEST_PATH)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_assert(parsed is Dictionary, "Manifest W02 musi być poprawnym obiektem JSON.")
	return parsed as Dictionary if parsed is Dictionary else {}


func _load_controller_script(package_manifest: Dictionary) -> Script:
	for script_value: Variant in package_manifest.get("scripts", []) as Array:
		var script_record := script_value as Dictionary
		if str(script_record.get("role", "")) != "controller":
			continue
		var script := load(PACKAGE_ROOT + str(script_record.get("path", ""))) as Script
		_assert(script != null, "Nie można załadować prywatnego skryptu controller W02.")
		return script
	_assert(false, "Manifest W02 nie deklaruje skryptu roli controller.")
	return null


func _load_script_by_role(package_manifest: Dictionary, role: String) -> Script:
	for script_value: Variant in package_manifest.get("scripts", []) as Array:
		var script_record := script_value as Dictionary
		if str(script_record.get("role", "")) != role:
			continue
		var script := load(PACKAGE_ROOT + str(script_record.get("path", ""))) as Script
		_assert(script != null, "Nie można załadować prywatnego skryptu roli %s W02." % role)
		return script
	_assert(false, "Manifest W02 nie deklaruje skryptu roli %s." % role)
	return null


func _verify_typed_egress_visual_dispatch() -> void:
	if _moving_body_script == null:
		return
	var body = _moving_body_script.new()
	var definition := {
		"id": "renamed_visual_fixture",
		"socket_id": "renamed_socket_fixture",
		"label": "dowolna nazwa bez słowa wyjście",
		"symbol": "?",
		"open_offset": [0, -240],
		"travel_speed": 280,
	}
	var socket_rect := Rect2(120.0, 320.0, 80.0, 160.0)
	var errors: PackedStringArray = body.configure(definition, socket_rect, STRUCTURE_ID, "egress_grille")
	_assert(errors.is_empty(), "Typowany egress_grille musi konfigurować się niezależnie od ID/socket/label/symbol: %s." % errors)
	_assert(str(body.call(&"visual_style")) == "egress_grille", "Dispatch prezentacji nie może zależeć od symbol.contains ani nazwy bariery.")
	_assert(str(body.call(&"visual_state")) == "CLOSED", "Syntetyczny egress_grille musi zaczynać w CLOSED.")
	body.snap_to_local_position(body.home_local_position() + Vector2(0.0, -240.0))
	_assert(str(body.call(&"visual_state")) == "OPEN" and bool(body.call(&"aperture_is_clear")), "Syntetyczny egress_grille musi kończyć z pustą aperturą niezależnie od nazw.")
	body.free()


func _effective_structure_record(package_manifest: Dictionary) -> Dictionary:
	var template := package_manifest.get("template", {}) as Dictionary
	var size := package_manifest.get("size", []) as Array
	var sockets := package_manifest.get("sockets", []) as Array
	var runtime := package_manifest.get("runtime", {}) as Dictionary
	_assert(not str(template.get("id", "")).is_empty(), "Manifest W02 musi mieć template.id.")
	_assert(size.size() == 2 and sockets is Array and not runtime.is_empty(), "Manifest W02 musi mieć size, sockets i runtime.")
	if str(template.get("id", "")).is_empty() or size.size() != 2 or runtime.is_empty():
		return {}
	return {
		"id": STRUCTURE_ID,
		"template_id": str(template.get("id", "")),
		"size": size.duplicate(true),
		"sockets": sockets.duplicate(true),
		"runtime": runtime.duplicate(true),
	}


func _barrier_body(controller, barrier_id: String) -> AnimatableBody2D:
	for body_value: Variant in controller.find_children("*", "AnimatableBody2D", true, false):
		var body := body_value as AnimatableBody2D
		if str(body.get_meta(&"barrier_id", "")) == barrier_id:
			return body
	return null


func _cabinet_body(controller) -> AnimatableBody2D:
	for body_value: Variant in controller.find_children("*", "AnimatableBody2D", true, false):
		var body := body_value as AnimatableBody2D
		if str(body.get_meta(&"cabinet_id", "")) == "cabinet_d":
			return body
	return null


func _await_barrier_target(controller, barrier_id: String) -> void:
	for _frame: int in range(MAX_MOTION_FRAMES):
		if controller.barrier_reached_target(barrier_id):
			return
		await physics_frame
	_assert(false, "Bariera %s nie osiągnęła celu w limicie physics frames: %s." % [barrier_id, controller.state_snapshot()])


func _await_facade_mid_state(controller, facade) -> float:
	if facade == null:
		return -1.0
	for _frame: int in range(MAX_MOTION_FRAMES):
		var clear_fraction := float(facade.call(&"aperture_clear_fraction"))
		if clear_fraction >= 0.35 and clear_fraction < 0.95:
			_assert(str(facade.call(&"visual_state")) == "MID", "Częściowo odsłonięta fasada musi publikować MID.")
			_assert(controller.barrier_is_commanded_open("facade") and not controller.barrier_is_open("facade") and not controller.barrier_reached_target("facade"), "MID musi zachować rozróżnienie commanded/open/reached.")
			var mid_body_rect: Rect2 = facade.call(&"body_rect_in_parent")
			var aperture_rect: Rect2 = facade.call(&"aperture_rect_in_parent")
			_assert(mid_body_rect.intersects(aperture_rect), "MID ma nadal częściowo przecinać aperturę, zanim osiągnie OPEN.")
			return clear_fraction
		await physics_frame
	_assert(false, "Fasada nie opublikowała odpornego stanu MID przed OPEN: %s." % controller.state_snapshot())
	return -1.0


func _await_cabinet_target(controller) -> void:
	for _frame: int in range(MAX_MOTION_FRAMES):
		if controller.cabinet_reached_target():
			return
		await physics_frame
	_assert(false, "cabinet_d nie osiągnął celu w limicie physics frames: %s." % controller.state_snapshot())


func _make_character(node_name: String, is_dive_player: bool) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 1
	if is_dive_player:
		body.add_to_group(DIVE_PLAYER_GROUP)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(40.0, 72.0)
	collision.shape = shape
	body.add_child(collision)
	return body


func _progression_snapshot(snapshot: Dictionary) -> Dictionary:
	return {
		"sequence_state": snapshot.get("sequence_state", ""),
		"b_complete": snapshot.get("b_complete", false),
		"c_complete": snapshot.get("c_complete", false),
		"d_complete": snapshot.get("d_complete", false),
		"d_state": snapshot.get("d_state", ""),
		"d_input_locked": snapshot.get("d_input_locked", false),
		"central_current_multiplier": snapshot.get("central_current_multiplier", -1.0),
		"b_current_active": snapshot.get("b_current_active", false),
		"barriers": snapshot.get("barriers", {}),
		"cabinet": snapshot.get("cabinet", {}),
	}


func _has_property(target: Object, property_name: StringName) -> bool:
	for property_value: Variant in target.get_property_list():
		if StringName((property_value as Dictionary).get("name", &"")) == property_name:
			return true
	return false


func _vector2(value: Variant) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2.ZERO
	return Vector2(float((value as Array)[0]), float((value as Array)[1]))


func _socket_by_id(socket_id: String) -> Dictionary:
	for socket_value: Variant in _package_manifest.get("sockets", []) as Array:
		var socket := socket_value as Dictionary
		if str(socket.get("id", "")) == socket_id:
			return socket
	return {}


func _socket_rect(socket_id: String) -> Rect2:
	var socket := _socket_by_id(socket_id)
	var value: Variant = socket.get("local_rect", [])
	if not value is Array or (value as Array).size() != 4:
		return Rect2()
	return Rect2(float((value as Array)[0]), float((value as Array)[1]), float((value as Array)[2]), float((value as Array)[3]))


func _socket_center(socket_id: String) -> Vector2:
	return _socket_rect(socket_id).get_center()


func _collision_operation_rect(operation_id: String) -> Rect2:
	var collision := _package_manifest.get("collision", {}) as Dictionary
	for operation_value: Variant in collision.get("operations", []) as Array:
		var operation := operation_value as Dictionary
		if str(operation.get("id", "")) != operation_id:
			continue
		var value: Variant = operation.get("rect_px", [])
		if not value is Array or (value as Array).size() != 4:
			return Rect2()
		return Rect2(
			float((value as Array)[0]) * COLLISION_GRID_WORLD_UNITS,
			float((value as Array)[1]) * COLLISION_GRID_WORLD_UNITS,
			float((value as Array)[2]) * COLLISION_GRID_WORLD_UNITS,
			float((value as Array)[3]) * COLLISION_GRID_WORLD_UNITS
		)
	return Rect2()


func _b_active_sample(b_current: Dictionary) -> Vector2:
	var main_rect := _socket_rect(str(b_current.get("socket_id", "")))
	var exclusions: Array[Rect2] = []
	for cover_socket_id: Variant in b_current.get("cover_socket_ids", []) as Array:
		exclusions.append(_socket_rect(str(cover_socket_id)))
	exclusions.append(_socket_rect(str(b_current.get("recovery_socket_id", ""))))
	for y: int in range(int(main_rect.position.y) + 20, int(main_rect.end.y), 40):
		for x: int in range(int(main_rect.position.x) + 20, int(main_rect.end.x), 40):
			var candidate := Vector2(float(x), float(y))
			var excluded := false
			for exclusion: Rect2 in exclusions:
				if exclusion.has_point(candidate):
					excluded = true
					break
			if not excluded:
				return candidate
	return main_rect.get_center()


func _basis_xform(transform_value: Transform2D, vector: Vector2) -> Vector2:
	return transform_value.x * vector.x + transform_value.y * vector.y


func _assert_vector_approx(actual: Vector2, expected: Vector2, message: String) -> void:
	_assert(actual.is_equal_approx(expected), "%s Oczekiwano %s, otrzymano %s." % [message, expected, actual])


func _assert_rect_approx(actual: Rect2, expected: Rect2, message: String) -> void:
	_assert(actual.position.is_equal_approx(expected.position) and actual.size.is_equal_approx(expected.size), "%s Oczekiwano %s, otrzymano %s." % [message, expected, actual])


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("Tower three inlets runtime test passed.")
	quit(0)
