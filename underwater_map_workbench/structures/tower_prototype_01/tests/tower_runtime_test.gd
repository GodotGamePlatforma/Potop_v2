extends SceneTree

const TowerControllerScript := preload("res://underwater_map_workbench/structures/tower_prototype_01/runtime/DiveEnterableTowerController.gd")
const StructureInteractableScript := preload("res://underwater_map_workbench/structures/tower_prototype_01/runtime/DiveStructureInteractable.gd")
const DiverControllerScript := preload("res://diver_workbench/runtime/DiverController.gd")
const DIVE_PLAYER_GROUP := DiverControllerScript.DIVE_PLAYER_GROUP
const PACKAGE_MANIFEST_PATH := "res://underwater_map_workbench/structures/tower_prototype_01/structure_manifest.json"
const STRUCTURE_ID := "tower_prototype_01"
const POWER_LEVER_IDS := ["a_lever_1", "a_lever_2", "a_lever_3"]

var _failed := false
var _package_manifest: Dictionary = {}
var _effective_structure: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_package_manifest = _load_package_manifest()
	if _package_manifest.is_empty():
		_finish()
		return
	_effective_structure = _effective_structure_record(_package_manifest)
	if _effective_structure.is_empty():
		_finish()
		return
	_verify_power_presentation_contract_validation()

	var structure_root := Node2D.new()
	structure_root.name = "TowerPrototype01"
	root.add_child(structure_root)
	var dynamic_bodies := Node2D.new()
	dynamic_bodies.name = "DynamicBodies"
	structure_root.add_child(dynamic_bodies)
	var interactives := Node2D.new()
	interactives.name = "Interactives"
	structure_root.add_child(interactives)

	var controller = TowerControllerScript.new()
	controller.name = "RuntimeTowerController"
	dynamic_bodies.add_child(controller)
	var errors := controller.configure(_effective_structure, interactives)
	_assert(errors.is_empty(), "Poprawny kontrakt wieżowca powinien utworzyć runtime bez błędów: %s" % errors)
	if not errors.is_empty():
		_finish()
		return
	await process_frame
	await physics_frame

	_assert(controller.get_parent() == dynamic_bodies, "Kontroler musi pozostać pod structure-local DynamicBodies.")
	_assert(interactives.get_child_count() == 8, "Runtime musi utworzyć siedem zwykłych controls i jeden panel A pod Interactives.")
	_assert(controller.power_lever_ids() == PackedStringArray(POWER_LEVER_IDS), "Panel A musi publikować trzy stabilne lever IDs z manifestu.")
	for lever_id: String in POWER_LEVER_IDS:
		var lever = controller.power_lever(lever_id)
		_assert(lever is Area2D, "Każda dźwignia A musi być osobnym Area2D: %s." % lever_id)
		_assert(lever.get_script() == StructureInteractableScript, "Dźwignia A musi używać sesyjnego kontraktu struktury, nie trwałego urządzenia: %s." % lever_id)
		_assert(not _has_property(lever, &"persistent_id"), "Dźwignia A nie może publikować persistent_id: %s." % lever_id)
		_assert(lever.can_interact(), "Każda dźwignia A musi być interaktywna niezależnie od stanu obwodów: %s." % lever_id)
		_assert(str(lever.get_meta(&"power_lever_position", "")) == "up", "Każda dźwignia A musi zaczynać w pozycji up.")
		var lever_collision := lever.get_node_or_null("CollisionShape2D") as CollisionShape2D
		_assert(lever_collision != null and lever_collision.shape is RectangleShape2D, "Każda dźwignia A musi mieć własny prostokątny hitbox.")
		if lever_collision != null and lever_collision.shape is RectangleShape2D:
			_assert((lever_collision.shape as RectangleShape2D).size == Vector2(72.0, 72.0), "Hitbox dźwigni A musi odpowiadać jej manifestowemu local_rect.")
		_assert(lever.interaction_text().contains("dół"), "Prompt dźwigni w pozycji up musi zapowiadać przełączenie na dół.")
	var dynamic_body_nodes := controller.find_children("*", "AnimatableBody2D", true, false)
	_assert(dynamic_body_nodes.size() == 13, "Runtime musi utworzyć jedną windę i dwanaście skrzydeł w siedmiu grupach.")
	for body_value: Variant in dynamic_body_nodes:
		var body := body_value as AnimatableBody2D
		_assert(body.collision_layer == 1 and body.collision_mask == 0, "Każde ruchome ciało musi blokować nurka wyłącznie na warstwie fizyki 1.")
		_assert(body.sync_to_physics, "AnimatableBody2D musi synchronizować transform z fizyką.")
		_assert(body.get_node_or_null("MechanismVisual") != null, "Grafika obiektu ruchomego musi być dzieckiem dokładnie tego samego collidera.")
	var safety_areas := controller.find_children("SafetyEnvelope", "Area2D", true, false)
	_assert(safety_areas.size() == 13, "Każde ruchome ciało musi mieć safety envelope.")
	for area_value: Variant in safety_areas:
		var area := area_value as Area2D
		_assert(area.collision_layer == 0 and area.collision_mask == 1, "Safety envelope ma wykrywać CharacterBody2D na warstwie 1 bez własnej kolizji.")

	var initial := controller.state_snapshot()
	_assert(initial.get("lever_positions", {}) == _positions("up", "up", "up"), "Próba musi zaczynać się układem A up/up/up.")
	_assert(str(initial.get("matched_circuit_id", "x")).is_empty(), "Układ startowy A nie może pasować do żadnego obwodu.")
	_assert(str(initial.get("active_circuit_id", "x")).is_empty(), "Układ startowy A nie może zasilać obwodu.")
	_assert(str(initial.get("power_status", "")) == "ready", "Panel A musi po resecie pokazywać ready, nie fault.")
	_assert(initial.get("circuit_states", {}) == {"red": "ready", "blue": "locked", "yellow": "locked"}, "Start A musi publikować red ready oraz blue/yellow locked.")
	var power_panel = controller.control("a_distributor")
	_assert(str(power_panel.get_meta(&"power_logic_contract", "")) == "three_lever_deduction_v2", "Panel A musi publikować dedukcyjny kontrakt feedbacku.")
	_assert(power_panel.circuit_visual_state("red") == "ready" and power_panel.circuit_visual_state("blue") == "locked", "Lampy panelu muszą odwzorować ready/locked ze snapshotu.")
	_assert(str(power_panel.get_meta(&"diagnostic_id", "x")).is_empty(), "Neutralny start A nie może udawać błędu.")
	_verify_power_panel_geometry(controller, power_panel)
	_verify_runtime_visual_order(controller, power_panel, dynamic_body_nodes)
	for label_value: Variant in power_panel.find_children("*", "Label", true, false):
		var label_text := (label_value as Label).text
		_assert(not label_text.contains("↑") and not label_text.contains("↓"), "Panel A nie może wyświetlać gotowego kodu strzałkami.")
	_assert(controller.elevator_current_stop_id() == "floor_12", "Pusty wózek musi zaczynać na floor_12.")
	_assert(not bool(initial.get("trolley_contact_closed", true)), "Styk C musi zaczynać jako otwarty.")
	_assert(not controller.is_public_gate_open(&"attempt_complete") and not controller.is_public_gate_open(&"archive_terminal"), "Przed Archiwum pakiet nie może publikować ukończenia ani prywatnego terminala.")
	_assert(_all_groups_have_state(controller, false), "Wszystkie siedem grup musi zaczynać jako closed.")
	_assert(not bool(controller.activate_control("b_red_relay").get("success", true)), "B nie może ominąć pierwszego A.")
	_assert(not bool(controller.activate_control("c_blue_lock").get("success", true)), "C nie może ominąć A i B.")
	_assert(not bool(controller.activate_control("d_valve_v1").get("success", true)), "D nie może ominąć A, B i C.")
	_assert(not bool(controller.activate_control("basement_hatch_control").get("success", true)), "Sterowanie piwnicy nie może ominąć zagadki D.")
	_assert(bool(controller.activate_power_lever("a_lever_1").get("success", false)), "Publiczne API capture musi przełączać stabilny lever ID.")
	_assert(str((controller.state_snapshot().get("lever_positions", {}) as Dictionary).get("a_lever_1", "")) == "down", "Publiczne API levera musi natychmiast publikować nową pozycję.")
	controller.reset_attempt()
	_verify_all_power_patterns(controller, power_panel)
	controller.reset_attempt()

	_set_power_pattern(controller, ["down", "down", "down"])
	_assert(str(controller.state_snapshot().get("active_circuit_id", "")) == "red", "Wzorzec down/down/down ma aktywować RED.")
	_assert(power_panel.circuit_visual_state("red") == "active", "Lampa RED musi pokazać active.")
	_verify_circuit_badge_content(power_panel.get_node_or_null("CircuitStateRed") as Label, "red", "active")
	_assert(controller.barrier_group_is_open("red_route"), "Aktywny RED musi otworzyć red_route.")
	_assert(_barrier_group_has_visual_state(controller, "red_route", "opening"), "RED musi natychmiast opublikować stan opening podczas ruchu drzwi.")
	await _await_barrier_group_target(controller, "red_route")
	_assert(
		_barrier_group_has_visual_state(controller, "red_route", "open"),
		"RED musi zakończyć ruch jednoznacznym stanem open: %s."
		% [_barrier_group_debug_snapshot(controller, "red_route")],
	)
	_assert(bool(controller.activate_control("b_red_relay").get("success", false)), "B ma zatrzasnąć RED.")
	_assert(controller.barrier_group_is_open("red_route") and controller.barrier_group_is_open("shortcut_b"), "B musi zachować RED i otworzyć shortcut_b.")
	_assert(controller.power_circuit_state("red") == "latched" and controller.power_circuit_state("blue") == "ready", "Po B RED ma być latched, a BLUE ready.")
	_assert(str(controller.state_snapshot().get("power_status", "")) == "latched", "Wzorzec RED po B musi publikować status latched.")
	_assert(power_panel.circuit_visual_state("red") == "latched" and power_panel.circuit_visual_state("blue") == "ready", "Lampy panelu muszą pokazać latch RED i ready BLUE.")
	_verify_circuit_badge_content(power_panel.get_node_or_null("CircuitStateRed") as Label, "red", "latched")
	_verify_circuit_badge_content(power_panel.get_node_or_null("CircuitStateBlue") as Label, "blue", "ready")
	_verify_power_patterns_after_latch(controller, false)
	_set_power_pattern(controller, ["up", "down", "up"])
	_assert(controller.power_circuit_state("blue") == "active", "Wzorzec up/down/up po B ma aktywować BLUE.")
	_verify_circuit_badge_content(power_panel.get_node_or_null("CircuitStateBlue") as Label, "blue", "active")
	_assert(controller.barrier_group_is_open("blue_route"), "Aktywny BLUE musi otworzyć blue_route.")
	_assert(controller.elevator_target_stop_id() == "floor_7", "Aktywny BLUE musi wysłać pusty wózek na floor_7.")
	for _frame_index: int in range(30):
		await physics_frame
	_assert(not controller.elevator_reached_stop("floor_12") and not controller.elevator_reached_stop("floor_7"), "Niezatrzaśnięty pusty wózek musi rozpocząć przejazd z floor_12 do floor_7.")
	var trolley_visual := _mechanism_visual_by_kind(controller, "empty_maintenance_trolley")
	_assert(trolley_visual != null and str(trolley_visual.call("visual_state")) == "moving_down", "Ruch wózka musi mieć stan moving_down.")
	if trolley_visual != null:
		var aperture_value: Variant = trolley_visual.get_meta(&"open_aperture_local_rect", null)
		_assert(
			aperture_value is Rect2
			and (aperture_value as Rect2).size.x > 0.0
			and (aperture_value as Rect2).size.y > 0.0
			and bool(trolley_visual.get_meta(&"open_aperture_expected_transparent", false)),
			"Pusty wózek musi publikować dodatnią, przezroczystą aperturę ładunkową do kontroli capture.",
		)
		var moving_wheel_phase := float(trolley_visual.get("_wheel_phase"))
		for _frame_index: int in range(3):
			await process_frame
		_assert(not is_equal_approx(float(trolley_visual.get("_wheel_phase")), moving_wheel_phase), "Koła pustego wózka muszą obracać się wyłącznie podczas jazdy.")
	_assert(not bool(controller.state_snapshot().get("trolley_contact_closed", true)), "Styk C musi pozostać otwarty podczas ruchu wózka.")
	_assert(not bool(controller.activate_control("c_blue_lock").get("success", true)), "C nie może zatrzasnąć wózka przed fizycznym stykiem na floor_7.")
	_set_power_pattern(controller, ["up", "up", "up"])
	var blue_off := controller.state_snapshot()
	_assert(str(blue_off.get("power_status", "")) == "fault", "Niewłaściwy wzorzec po toggle ma dać wyłącznie feedback fault.")
	_assert(not controller.barrier_group_is_open("blue_route"), "Niezatrzaśnięty BLUE ma się wyłączyć po zmianie wzorca.")
	_assert(controller.elevator_target_stop_id() == "floor_12", "Wyłączenie niezatrzaśniętego BLUE ma zawrócić windę na floor_12.")
	_assert(not bool(blue_off.get("trolley_contact_closed", true)), "Zmiana układu przed C musi otworzyć styk wózka.")
	_assert(controller.barrier_group_is_open("red_route"), "Zmiana wzorca nie może zamknąć zatrzaśniętego RED.")
	await _await_elevator_stop(controller, "floor_12")
	_assert(controller.elevator_reached_stop("floor_12"), "Po wyłączeniu niezatrzaśniętego BLUE winda musi faktycznie wrócić na floor_12.")
	_set_power_pattern(controller, ["up", "down", "up"])
	await _await_elevator_stop(controller, "floor_7")
	var trolley_arrived := controller.state_snapshot()
	_assert(
		str(trolley_arrived.get("elevator_current_stop_id", "")) == "floor_7"
		and bool(trolley_arrived.get("trolley_contact_closed", false)),
		"floor_7 i fizycznie domknięty styk C muszą wystąpić w tej samej obserwacji snapshotu: %s" % trolley_arrived,
	)
	_assert(str(trolley_arrived.get("trolley_visual_state", "")) == "contact_closed", "Grafika wózka musi pokazać domknięty styk przed C.")
	_assert(str(trolley_arrived.get("last_feedback_kind", "")) == "trolley_contact_closed", "Dojście wózka musi mieć jednoznaczny feedback audio.")
	_assert(str(controller.control("c_blue_lock").visual_state()) == "contact_closed", "Grafika C musi pokazać domknięcie styku.")
	if trolley_visual != null:
		var contact_wheel_phase := float(trolley_visual.get("_wheel_phase"))
		for _frame_index: int in range(4):
			await process_frame
		_assert(is_equal_approx(float(trolley_visual.get("_wheel_phase")), contact_wheel_phase), "Koła wózka muszą zatrzymać się dokładnie po domknięciu styku floor_7.")
	_assert(bool(controller.activate_control("c_blue_lock").get("success", false)), "C ma zatrzasnąć pusty wózek i BLUE.")
	_assert(controller.barrier_group_is_open("blue_route") and controller.barrier_group_is_open("shortcut_c"), "C musi zachować BLUE i otworzyć shortcut_c.")
	_assert(controller.power_circuit_state("blue") == "latched" and controller.power_circuit_state("yellow") == "ready", "Po C BLUE ma być latched, a YELLOW ready.")
	_assert(str(controller.state_snapshot().get("power_status", "")) == "latched", "Wzorzec BLUE po C musi publikować status latched.")
	_assert(power_panel.circuit_visual_state("blue") == "latched" and power_panel.circuit_visual_state("yellow") == "ready", "Lampy panelu muszą pokazać latch BLUE i ready YELLOW.")
	_verify_circuit_badge_content(power_panel.get_node_or_null("CircuitStateBlue") as Label, "blue", "latched")
	_verify_circuit_badge_content(power_panel.get_node_or_null("CircuitStateYellow") as Label, "yellow", "ready")
	var yellow_clue := power_panel.get_node_or_null("DeductionClue") as Label
	var expected_yellow_summary := str(
		(_manifest_power_logic().get("clue_summaries", {}) as Dictionary).get("yellow", "")
	)
	var expected_yellow_clue := str(
		(_manifest_power_logic().get("clues", {}) as Dictionary).get("yellow", "")
	)
	_assert(
		yellow_clue != null
		and yellow_clue.visible
		and str(yellow_clue.get_meta(&"clue_circuit_id", "")) == "yellow"
		and yellow_clue.text == expected_yellow_summary
		and yellow_clue.tooltip_text == expected_yellow_clue
		and yellow_clue.text.contains("ŚRODEK ZAJ.")
		and yellow_clue.text.contains("PRAWA ODC.")
		and _label_multiline_content_fits(yellow_clue),
		"Widoczna przesłanka YELLOW musi in-world podać zajęty środek i odciętą prawą gałąź, bez polegania na kolorze lub tooltipie.",
	)
	_assert(str(controller.state_snapshot().get("trolley_visual_state", "")) == "latched_floor_7", "Po C pusty wózek musi być wizualnie nieruchomym interlockiem.")
	_verify_power_patterns_after_latch(controller, true)
	_set_power_pattern(controller, ["up", "up", "up"])
	_assert(controller.barrier_group_is_open("blue_route") and controller.elevator_target_stop_id() == "floor_7", "Zatrzaśnięty BLUE i winda nie mogą cofnąć się po zmianie wzorca.")
	_set_power_pattern(controller, ["down", "up", "up"])
	_assert(controller.power_circuit_state("yellow") == "active", "Wzorzec down/up/up po C ma aktywować YELLOW.")
	_assert(power_panel.circuit_visual_state("yellow") == "active", "Lampa YELLOW musi pokazać active.")
	_verify_circuit_badge_content(power_panel.get_node_or_null("CircuitStateYellow") as Label, "yellow", "active")
	_assert(controller.barrier_group_is_open("yellow_route"), "Aktywny YELLOW musi otworzyć yellow_route.")

	_verify_d_reset_and_fault_matrix(controller)
	_assert(bool(controller.activate_control("d_valve_v1").get("success", false)), "Po resecie V1 ma działać.")
	_assert(str(controller.control("d_valve_v1").visual_state()) == "completed", "WYRÓWNANIE CIŚNIENIA musi mieć własny stan wizualny.")
	_assert(bool(controller.activate_control("d_valve_v2").get("success", false)), "Po V1 ma działać V2.")
	_assert(str(controller.control("d_valve_v2").visual_state()) == "completed", "ZASILENIE SIŁOWNIKA musi mieć własny stan wizualny.")
	_assert(bool(controller.activate_control("d_valve_v3").get("success", false)), "Po V1 i V2 ma działać V3.")
	_assert(str(controller.control("d_valve_v3").visual_state()) == "bolt_released", "ZWOLNIENIE RYGLA musi mieć własny stan wizualny.")
	_assert(controller.barrier_group_is_open("hatch_d"), "V1-V2-V3 musi otworzyć hatch_d.")
	_assert(not bool(controller.activate_control("d_reset").get("success", true)), "RESET nie może cofnąć ukończonego D.")
	_assert(controller.barrier_group_is_open("hatch_d"), "Odmowa RESET po ukończeniu nie może zamknąć hatch_d.")
	_assert(bool(controller.activate_control("basement_hatch_control").get("success", false)), "Sterowanie piwnicy ma działać po D.")
	_assert(controller.is_public_gate_open(&"attempt_complete"), "Dopiero otwarcie Archiwum ma publikować attempt_complete.")
	_assert(not controller.is_public_gate_open(&"archive_terminal") and not controller.is_public_gate_open(&"ocean_shortcut"), "Pakiet nie może publikować prywatnych bramek globalnej integracji.")
	_assert(str(controller.control("basement_hatch_control").visual_state()) == "open", "Sterowanie Archiwum musi pokazać stan open.")
	_assert(_all_groups_have_state(controller, true), "Ukończona próba musi pozostawić wszystkie siedem grup open.")
	_verify_fresh_runtime_has_no_checkpoint()

	var control_global_before: Vector2 = controller.power_lever("a_lever_1").global_position
	var elevator_global_before := (dynamic_body_nodes[0] as AnimatableBody2D).global_position
	var root_delta := Vector2(360.0, -200.0)
	structure_root.position += root_delta
	_assert(controller.power_lever("a_lever_1").global_position.is_equal_approx(control_global_before + root_delta), "Przesunięcie StructureRoot musi przenieść panel i hitboxy dźwigni A.")
	_assert((dynamic_body_nodes[0] as AnimatableBody2D).global_position.is_equal_approx(elevator_global_before + root_delta), "Przesunięcie StructureRoot musi przenieść dynamiczną fizykę.")
	structure_root.position = Vector2.ZERO

	controller.reset_attempt()
	_assert(_all_groups_have_state(controller, false), "reset_attempt musi zamknąć wszystkie siedem grup.")
	_assert(controller.elevator_current_stop_id() == "floor_12", "reset_attempt musi odstawić windę na floor_12.")
	var reset_state := controller.state_snapshot()
	_assert(reset_state.get("lever_positions", {}) == _positions("up", "up", "up"), "reset_attempt musi ustawić wszystkie dźwignie A na up.")
	_assert(reset_state.get("circuit_states", {}) == {"red": "ready", "blue": "locked", "yellow": "locked"}, "reset_attempt musi przywrócić ready/locked obwodów A.")
	_assert(power_panel.circuit_visual_state("red") == "ready" and power_panel.circuit_visual_state("yellow") == "locked", "Reset musi odświeżyć lampy panelu A.")
	_assert(str(reset_state.get("power_status", "")) == "ready" and not bool(reset_state.get("d_complete", true)), "reset_attempt musi wyzerować sekwencję i feedback fault bez checkpointu.")
	_assert(not controller.is_public_gate_open(&"attempt_complete"), "reset_attempt musi wyzerować publiczne attempt_complete.")
	controller.reset_attempt()
	_assert(controller.state_snapshot() == reset_state, "Powtórzony reset_attempt musi być idempotentny dla całego publicznego stanu próby.")

	await _verify_safety_envelopes(controller, structure_root)
	_finish()


func _verify_all_power_patterns(controller, power_panel: Node2D) -> void:
	var pattern_cases := [
		{"positions": ["up", "up", "up"], "matched": ""},
		{"positions": ["up", "up", "down"], "matched": ""},
		{"positions": ["up", "down", "up"], "matched": "blue"},
		{"positions": ["up", "down", "down"], "matched": ""},
		{"positions": ["down", "up", "up"], "matched": "yellow"},
		{"positions": ["down", "up", "down"], "matched": ""},
		{"positions": ["down", "down", "up"], "matched": ""},
		{"positions": ["down", "down", "down"], "matched": "red"},
	]
	var valid_count := 0
	var invalid_count := 0
	var diagnostic_ids := {}
	controller.reset_attempt()
	_assert(bool(controller.activate_power_lever("a_lever_1").get("success", false)), "Fixture UUU diagnostic wymaga odejścia od neutralnego startu.")
	_assert(bool(controller.activate_power_lever("a_lever_1").get("success", false)), "Fixture UUU diagnostic wymaga powrotu do układu startowego.")
	var returned_to_start: Dictionary = controller.state_snapshot()
	_assert(str(returned_to_start.get("power_diagnostic_id", "")) == "all_branches_open", "Układ UUU osiągnięty po przełączeniu musi zgłosić przerwę, nie neutralny start.")
	_verify_power_feedback_labels(power_panel, returned_to_start, true)
	diagnostic_ids[str(returned_to_start.get("power_diagnostic_id", ""))] = true
	for pattern_case_value: Variant in pattern_cases:
		var pattern_case := pattern_case_value as Dictionary
		controller.reset_attempt()
		var positions := PackedStringArray(pattern_case.get("positions", []))
		_set_power_pattern(controller, positions)
		var snapshot: Dictionary = controller.state_snapshot()
		var expected_match := str(pattern_case.get("matched", ""))
		_assert(snapshot.get("lever_positions", {}) == _positions(str(positions[0]), str(positions[1]), str(positions[2])), "Snapshot musi odwzorować każdą z ośmiu kombinacji dźwigni: %s." % [positions])
		_assert(str(snapshot.get("matched_circuit_id", "")) == expected_match, "Kombinacja %s ma niepoprawny matched_circuit_id: %s." % [positions, snapshot])
		if expected_match.is_empty():
			invalid_count += 1
			_assert(str(snapshot.get("active_circuit_id", "")).is_empty(), "Jeden z pięciu niewłaściwych układów nie może uruchomić mechanizmu: %s." % [positions])
			_assert(not controller.barrier_group_is_open("red_route") and not controller.barrier_group_is_open("blue_route") and not controller.barrier_group_is_open("yellow_route"), "Niewłaściwy układ nie może otworzyć obwodowych barier: %s." % [positions])
			var expected_invalid_status := "ready" if positions == PackedStringArray(["up", "up", "up"]) else "fault"
			_assert(str(snapshot.get("power_status", "")) == expected_invalid_status, "Niewłaściwy układ ma publikować wyłącznie ready po resecie albo fault po toggle: %s." % [positions])
			if expected_invalid_status == "fault":
				var reason_id := str(snapshot.get("power_diagnostic_id", ""))
				_assert(not reason_id.is_empty() and not str(snapshot.get("power_diagnostic_message", "")).is_empty(), "Każdy błędny układ musi mieć reason_id i komunikat: %s." % [positions])
				_verify_power_feedback_labels(power_panel, snapshot, true)
				diagnostic_ids[reason_id] = true
			else:
				_verify_power_feedback_labels(power_panel, snapshot, false)
		else:
			valid_count += 1
			var expected_state := "active" if expected_match == "red" else "locked"
			_assert(controller.power_circuit_state(expected_match) == expected_state, "Wzorzec %s ma respektować aktualne active/locked: %s." % [expected_match, snapshot])
			_assert(str(snapshot.get("power_status", "")) == expected_state, "Feedback panelu ma zgadzać się ze stanem matched circuit.")
			_assert(str(snapshot.get("active_circuit_id", "")) == ("red" if expected_match == "red" else ""), "Przed B tylko wzorzec RED może napędzać mechanizm.")
			_verify_power_feedback_labels(power_panel, snapshot, false)
		for lever_id: String in POWER_LEVER_IDS:
			_assert(controller.power_lever(lever_id).can_interact(), "Levery A muszą pozostać interaktywne także w locked/fault: %s." % [positions])
	_assert(valid_count == 3 and invalid_count == 5, "Rozdzielnia A musi rozróżniać dokładnie 3 prawidłowe i 5 niewłaściwych kombinacji.")
	_assert(diagnostic_ids.size() == 5, "Pięć błędnych konfiguracji A musi dawać pięć unikalnych powodów diagnostycznych: %s." % [diagnostic_ids])


func _verify_power_patterns_after_latch(controller, blue_latched: bool) -> void:
	var sequence := (
		[
			["up", "down", "up"],
			["up", "down", "down"],
			["down", "down", "down"],
			["down", "down", "up"],
			["down", "up", "up"],
			["down", "up", "down"],
			["up", "up", "down"],
			["up", "up", "up"],
		]
		if blue_latched
		else [
			["down", "down", "down"],
			["down", "down", "up"],
			["down", "up", "up"],
			["down", "up", "down"],
			["up", "up", "down"],
			["up", "up", "up"],
			["up", "down", "up"],
			["up", "down", "down"],
		]
	)
	var expected_matches := {
		"up/up/up": "",
		"up/up/down": "",
		"up/down/up": "blue",
		"up/down/down": "",
		"down/up/up": "yellow",
		"down/up/down": "",
		"down/down/up": "",
		"down/down/down": "red",
	}
	var visited := {}
	for positions_value: Variant in sequence:
		var positions := PackedStringArray(positions_value)
		_set_power_pattern(controller, positions)
		var snapshot: Dictionary = controller.state_snapshot()
		var key := "/".join(positions)
		visited[key] = true
		var expected_match := str(expected_matches.get(key, "missing"))
		_assert(str(snapshot.get("matched_circuit_id", "")) == expected_match, "Układ %s po latchu ma zachować właściwe dopasowanie: %s." % [positions, snapshot])
		_assert(controller.power_circuit_state("red") == "latched" and controller.barrier_group_is_open("red_route"), "RED nie może cofnąć latchu podczas dalszego sterowania A: %s." % [positions])
		if blue_latched:
			var expected_active := "yellow" if expected_match == "yellow" else ""
			var expected_status := "fault" if expected_match.is_empty() else ("active" if expected_match == "yellow" else "latched")
			_assert(controller.power_circuit_state("blue") == "latched" and controller.barrier_group_is_open("blue_route"), "BLUE nie może cofnąć latchu po C: %s." % [positions])
			_assert(controller.power_circuit_state("yellow") == ("active" if expected_match == "yellow" else "ready"), "YELLOW ma reagować wyłącznie na swój wzorzec po C: %s." % [positions])
			_assert(str(snapshot.get("active_circuit_id", "")) == expected_active and str(snapshot.get("power_status", "")) == expected_status, "Feedback po C nie odpowiada układowi %s: %s." % [positions, snapshot])
			_assert(controller.barrier_group_is_open("yellow_route") == (expected_match == "yellow"), "yellow_route ma reagować wyłącznie na YELLOW po C: %s." % [positions])
			_assert(controller.elevator_target_stop_id() == "floor_7", "Latch BLUE musi utrzymać cel windy floor_7 dla każdego układu A.")
		else:
			var expected_active := "blue" if expected_match == "blue" else ""
			var expected_blue_state := "active" if expected_match == "blue" else "ready"
			var expected_status := "fault" if expected_match.is_empty() else ("latched" if expected_match == "red" else expected_blue_state if expected_match == "blue" else "locked")
			_assert(controller.power_circuit_state("blue") == expected_blue_state, "Po B BLUE ma być active tylko dla swojego wzorca: %s." % [positions])
			_assert(controller.power_circuit_state("yellow") == "locked", "Przed C YELLOW musi pozostać locked dla każdego układu A: %s." % [positions])
			_assert(str(snapshot.get("active_circuit_id", "")) == expected_active and str(snapshot.get("power_status", "")) == expected_status, "Feedback po B nie odpowiada układowi %s: %s." % [positions, snapshot])
			_assert(controller.barrier_group_is_open("blue_route") == (expected_match == "blue"), "blue_route ma reagować wyłącznie na BLUE przed C: %s." % [positions])
			_assert(not controller.barrier_group_is_open("yellow_route"), "yellow_route nie może otworzyć się przed C: %s." % [positions])
		for lever_id: String in POWER_LEVER_IDS:
			_assert(controller.power_lever(lever_id).can_interact(), "Każda dźwignia musi pozostać niezależna po latchu: %s." % [positions])
	_assert(visited.size() == 8, "Po latchu trzeba sprawdzić wszystkie osiem układów bez resetowania próby.")
	_set_power_pattern(controller, ["up", "down", "up"] if blue_latched else ["down", "down", "down"])


func _verify_fresh_runtime_has_no_checkpoint() -> void:
	var detached_root := Node2D.new()
	var detached_dynamic := Node2D.new()
	var detached_interactives := Node2D.new()
	detached_root.add_child(detached_dynamic)
	detached_root.add_child(detached_interactives)
	var fresh_controller = TowerControllerScript.new()
	detached_dynamic.add_child(fresh_controller)
	var errors := fresh_controller.configure(_effective_structure, detached_interactives)
	_assert(errors.is_empty(), "Nowa instancja tej samej struktury musi dać się utworzyć bez checkpointu: %s." % errors)
	if errors.is_empty():
		var fresh_state: Dictionary = fresh_controller.state_snapshot()
		_assert(fresh_state.get("lever_positions", {}) == _positions("up", "up", "up"), "Nowa instancja wieżowca nie może odtworzyć ustawienia dźwigni z poprzedniej próby.")
		_assert(fresh_state.get("circuit_states", {}) == {"red": "ready", "blue": "locked", "yellow": "locked"}, "Nowa instancja wieżowca nie może odtworzyć latchy z poprzedniej próby.")
		_assert(not bool(fresh_state.get("d_complete", true)) and _all_groups_have_state(fresh_controller, false), "Nowa instancja wieżowca nie może odtworzyć drzwi ani ukończenia z poprzedniej próby.")
	detached_root.free()


func _verify_power_presentation_contract_validation() -> void:
	var invalid_cases: Array[Dictionary] = [
		{
			"id": "diagnostic_summary_null",
			"field": "diagnostic_summary",
			"value": null,
		},
		{
			"id": "clue_summary_whitespace",
			"field": "clue_summary",
			"value": "   ",
		},
		{
			"id": "diagnostics_not_exact_invalid_complement",
			"field": "diagnostic_positions",
			"value": ["down", "down", "down"],
		},
	]
	for invalid_case: Dictionary in invalid_cases:
		var invalid_record := _effective_structure.duplicate(true)
		var power_logic := _power_logic_from_runtime(invalid_record.get("runtime", null))
		var invalid_field := str(invalid_case.get("field", ""))
		if invalid_field in ["diagnostic_summary", "diagnostic_positions"]:
			var diagnostics := power_logic.get("diagnostics", {}) as Dictionary
			var diagnostic := diagnostics.get("all_branches_open", {}) as Dictionary
			if invalid_field == "diagnostic_summary":
				diagnostic["summary"] = invalid_case.get("value", null)
			else:
				diagnostic["positions"] = invalid_case.get("value", null)
		else:
			var clue_summaries := power_logic.get("clue_summaries", {}) as Dictionary
			clue_summaries["red"] = invalid_case.get("value", null)
		var invalid_controller = TowerControllerScript.new()
		var invalid_interactives := Node2D.new()
		var errors := invalid_controller.configure(invalid_record, invalid_interactives)
		_assert(
			not errors.is_empty(),
			"Konfiguracja A musi fail-closed odrzucić nie-String lub whitespace presentation text: %s."
			% str(invalid_case.get("id", "")),
		)
		invalid_controller.free()
		invalid_interactives.free()


func _verify_power_panel_geometry(controller, power_panel: Node2D) -> void:
	var panel_rect: Variant = power_panel.get_meta(&"socket_rect", null)
	_assert(panel_rect is Rect2 and (panel_rect as Rect2).is_equal_approx(Rect2(1760.0, 680.0, 320.0, 120.0)), "Panel A musi zachować manifestową geometrię 320x120.")
	if not panel_rect is Rect2:
		return
	var socket_rect := panel_rect as Rect2
	var indicator_nodes := power_panel.find_children("CircuitState*", "Label", true, false)
	_assert(indicator_nodes.size() == 3, "Panel A musi mieć trzy realne węzły Label-indicator, nie wyłącznie symbole w _draw().")
	var indicators_by_circuit := {}
	var presentation_labels: Array[Label] = []
	for indicator_value: Variant in indicator_nodes:
		var indicator := indicator_value as Label
		var circuit_id := str(indicator.get_meta(&"circuit_id", ""))
		_assert(circuit_id in ["red", "blue", "yellow"] and not indicators_by_circuit.has(circuit_id), "Indicator A musi mieć unikalne circuit_id red/blue/yellow.")
		indicators_by_circuit[circuit_id] = indicator
		presentation_labels.append(indicator)
		_assert(indicator.get_parent() == power_panel and indicator.z_as_relative and indicator.z_index == 1, "Indicator A musi pozostać realnym dzieckiem panelu na lokalnym z=1 (effective z=-8).")
		_assert(power_panel.z_index + indicator.z_index == -8, "Indicator A musi mieć effective z=-8: nad tłem panelu, pod bryłą L05.")
		_assert(socket_rect.encloses(Rect2(indicator.position, indicator.size)), "Indicator A nie może wyjść poza socket 320x120.")
	var title_label := power_panel.get_node_or_null("PowerStatus") as Label
	var clue_label := power_panel.get_node_or_null("DeductionClue") as Label
	var diagnostic_label := power_panel.get_node_or_null("DiagnosticReason") as Label
	_assert(title_label != null and clue_label != null and diagnostic_label != null, "Panel A musi mieć realne labelki statusu, clue i diagnostyki.")
	if title_label != null:
		presentation_labels.append(title_label)
		_assert(title_label.text == "A", "Tytuł panelu ma pozostać krótkim identyfikatorem A; pełny status należy do tooltip/meta.")
		_assert(not title_label.tooltip_text.is_empty() and not str(title_label.get_meta(&"visual_state", "")).is_empty(), "Tytuł A musi przenosić czytelny status przez tooltip i meta.")
	for message_label: Label in [clue_label, diagnostic_label]:
		if message_label == null:
			continue
		presentation_labels.append(message_label)
	if clue_label != null and diagnostic_label != null:
		_assert(Rect2(clue_label.position, clue_label.size).is_equal_approx(Rect2(diagnostic_label.position, diagnostic_label.size)), "Clue i diagnostyka muszą współdzielić jedno pełne pole tekstowe i przełączać widoczność.")
	for circuit_index: int in range(3):
		var circuit_id: String = ["red", "blue", "yellow"][circuit_index]
		var lever_id: String = POWER_LEVER_IDS[circuit_index]
		var corresponding_lever := controller.power_lever(lever_id) as Node2D
		var indicator := indicators_by_circuit.get(circuit_id, null) as Label
		_assert(indicator != null, "Panel A musi publikować indicator %s." % circuit_id)
		_assert(corresponding_lever != null, "Panel A musi publikować odpowiadającą dźwignię %s." % lever_id)
		if indicator == null or corresponding_lever == null:
			continue
		var indicator_rect := Rect2(indicator.position, indicator.size)
		_assert(is_equal_approx(indicator_rect.get_center().x, corresponding_lever.position.x), "Badge %s musi być wyśrodkowany dokładnie nad odpowiadającą dźwignią." % circuit_id)
		var lever_native_rect := corresponding_lever.get_meta(&"native_visual_rect", Rect2()) as Rect2
		var corresponding_lever_rect := Rect2(corresponding_lever.position + lever_native_rect.position, lever_native_rect.size)
		_assert(indicator_rect.intersects(corresponding_lever_rect), "Badge %s ma być materialną tabliczką nagłówkową przypiętą do własnej dźwigni." % circuit_id)
		var indicator_state := str(indicator.get_meta(&"visual_state", ""))
		_assert(indicator_state in ["locked", "ready", "active", "latched"], "Indicator %s musi publikować wspierany stan." % circuit_id)
		_verify_circuit_badge_content(indicator, circuit_id, indicator_state)
	for label: Label in presentation_labels:
		var label_rect := Rect2(label.position, label.size)
		_assert(label.size.x > 0.0 and label.size.y > 0.0 and socket_rect.encloses(label_rect), "%s musi mieć dodatni rect w całości wewnątrz socketu A." % label.name)
		for lever_id: String in POWER_LEVER_IDS:
			var lever := controller.power_lever(lever_id) as Node2D
			if lever == null:
				continue
			var lever_local_rect: Variant = lever.get_meta(&"native_visual_rect", Rect2())
			if not lever_local_rect is Rect2:
				continue
			var lever_rect := Rect2(lever.position + (lever_local_rect as Rect2).position, (lever_local_rect as Rect2).size)
			_assert(socket_rect.encloses(lever_rect), "Lever rect %s nie może wyjść poza socket panelu A." % lever_id)
			var label_circuit_id := str(label.get_meta(&"circuit_id", ""))
			var expected_lever_id: String = str({
				"red": "a_lever_1",
				"blue": "a_lever_2",
				"yellow": "a_lever_3",
			}.get(label_circuit_id, ""))
			if not expected_lever_id.is_empty() and lever_id == expected_lever_id:
				continue
			_assert(
				not label_rect.intersects(lever_rect),
				"%s %s nie może nachodzić na lever rect %s %s." % [label.name, label_rect, lever_id, lever_rect],
			)


func _verify_circuit_badge_content(indicator: Label, circuit_id: String, expected_state: String) -> void:
	var glyphs := {"red": "●", "blue": "▲", "yellow": "■"}
	var state_tokens := {"locked": "BLOKADA", "ready": "GOTOWY", "active": "AKTYWNY", "latched": "RYGIEL"}
	_assert(indicator != null, "Brakuje realnego badge dla obwodu %s." % circuit_id)
	if indicator == null:
		return
	_assert(str(indicator.get_meta(&"visual_state", "")) == expected_state, "Badge %s ma niezgodne meta visual_state." % circuit_id)
	_assert(
		indicator.text.contains(str(glyphs.get(circuit_id, "")))
		and indicator.text.contains(circuit_id.to_upper())
		and indicator.text.contains(str(state_tokens.get(expected_state, ""))),
		"Badge %s musi kodować obwód glyph+tekst oraz widoczny token stanu %s, nie tylko kolor: %s." % [circuit_id, expected_state, indicator.text],
	)
	var style := indicator.get_theme_stylebox(&"normal") as StyleBoxFlat
	_assert(style != null, "Badge %s musi mieć realne tło i kontur StyleBoxFlat." % circuit_id)
	if style == null:
		return
	var font_color := indicator.get_theme_color(&"font_color")
	_assert(_contrast_ratio(font_color, style.bg_color) >= 3.0, "Tekst badge %s musi zachować kontrast co najmniej 3:1 względem tła." % circuit_id)
	_assert(_contrast_ratio(style.border_color, style.bg_color) >= 3.0, "Istotny kontur badge %s musi zachować kontrast co najmniej 3:1 względem tła." % circuit_id)
	_assert(
		style.border_width_left >= 2
		and style.border_width_top >= 2
		and style.border_width_right >= 2
		and style.border_width_bottom >= 2,
		"Kontur badge %s musi mieć co najmniej 2 world px (2.4 px przy gameplay zoom 1.2)." % circuit_id,
	)


func _contrast_ratio(first: Color, second: Color) -> float:
	var first_luminance := _relative_luminance(first)
	var second_luminance := _relative_luminance(second)
	return (maxf(first_luminance, second_luminance) + 0.05) / (minf(first_luminance, second_luminance) + 0.05)


func _relative_luminance(color: Color) -> float:
	return (
		0.2126 * _linear_color_channel(color.r)
		+ 0.7152 * _linear_color_channel(color.g)
		+ 0.0722 * _linear_color_channel(color.b)
	)


func _linear_color_channel(channel: float) -> float:
	return channel / 12.92 if channel <= 0.04045 else pow((channel + 0.055) / 1.055, 2.4)


func _verify_power_feedback_labels(power_panel: Node2D, snapshot: Dictionary, expect_diagnostic: bool) -> void:
	var clue_label := power_panel.get_node_or_null("DeductionClue") as Label
	var diagnostic_label := power_panel.get_node_or_null("DiagnosticReason") as Label
	_assert(clue_label != null and diagnostic_label != null, "Feedback A wymaga dwóch realnych, wzajemnie przełączanych Label.")
	if clue_label == null or diagnostic_label == null:
		return
	var expected_diagnostic := str(snapshot.get("power_diagnostic_message", ""))
	var power_logic := _manifest_power_logic()
	if expect_diagnostic:
		var reason_id := str(snapshot.get("power_diagnostic_id", ""))
		var diagnostic := (power_logic.get("diagnostics", {}) as Dictionary).get(reason_id, {}) as Dictionary
		var expected_manifest_message := str(diagnostic.get("message", ""))
		var expected_summary := str(diagnostic.get("summary", ""))
		_assert(
			not expected_manifest_message.is_empty() and expected_diagnostic == expected_manifest_message,
			"Stan diagnostyczny musi publikować dokładnie manifestowy message w snapshotcie.",
		)
		_assert(diagnostic_label.visible and not clue_label.visible, "Diagnostyka A musi pokazywać realny DiagnosticReason i ukrywać clue.")
		_assert(not expected_summary.is_empty() and diagnostic_label.text == expected_summary and diagnostic_label.tooltip_text == expected_manifest_message, "DiagnosticReason musi pokazywać dokładnie manifestowy summary, a manifestowy message zachować w tooltipie.")
		_assert(_label_multiline_content_fits(diagnostic_label), "Widoczny summary diagnostyki nie może być ucięty w polu panelu A: %s." % expected_summary)
	else:
		var clue_id := str(power_panel.get_meta(&"clue_id", ""))
		var expected_clue := str((power_logic.get("clues", {}) as Dictionary).get(clue_id, ""))
		var expected_summary := str((power_logic.get("clue_summaries", {}) as Dictionary).get(clue_id, ""))
		_assert(expected_diagnostic.is_empty(), "Neutralny lub aktywny stan nie może zachować komunikatu diagnostycznego.")
		_assert(clue_label.visible and not diagnostic_label.visible, "Neutralny lub aktywny stan A musi pokazywać clue i ukrywać DiagnosticReason.")
		_assert(
			not expected_clue.is_empty()
			and not expected_summary.is_empty()
			and str(clue_label.get_meta(&"clue_circuit_id", "")) == clue_id
			and str(power_panel.get_meta(&"clue_text", "")) == expected_clue
			and clue_label.text == expected_summary
			and clue_label.tooltip_text == expected_clue,
			"Kontroler musi przekazać jeden manifestowy clue_id, a panel wyrenderować z niego zgodne summary i pełny tekst.",
		)
		_assert(_label_multiline_content_fits(clue_label), "Widoczny summary clue nie może być ucięty w polu panelu A: %s." % expected_summary)


func _label_multiline_content_fits(label: Label) -> bool:
	if label.text.is_empty() or label.size.x <= 0.0 or label.size.y <= 0.0:
		return false
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	if font == null or font_size <= 0:
		return false
	var measured := font.get_multiline_string_size(
		label.text,
		label.horizontal_alignment,
		label.size.x,
		font_size,
	)
	var font_height := maxf(font.get_height(font_size), 1.0)
	var line_count := maxi(ceili(measured.y / font_height), 1)
	var adjusted_height := measured.y + float(label.get_theme_constant(&"line_spacing")) * float(maxi(line_count - 1, 0))
	return measured.x <= label.size.x + 0.5 and adjusted_height <= label.size.y + 0.5


func _verify_runtime_visual_order(controller, power_panel: Node2D, dynamic_bodies: Array[Node]) -> void:
	for body_value: Variant in dynamic_bodies:
		var body := body_value as AnimatableBody2D
		_assert(body.z_index == -10, "Każdy mechanizm musi być nad L04 (-20), lecz pod panelem A i bryłą L05.")
	_assert(power_panel.z_index == -9 and power_panel.z_as_relative, "Tło panelu A musi pozostać na z=-9 pomiędzy mechanizmami a controls.")
	for lever_id: String in POWER_LEVER_IDS:
		var lever := controller.power_lever(lever_id) as Node2D
		_assert(lever != null and lever.z_index == 1 and lever.z_as_relative, "Dźwignie A muszą dziedziczyć panel -9 i dawać efektywne z=-8.")
	for control_id: String in ["b_red_relay", "c_blue_lock", "d_valve_v1", "d_valve_v2", "d_valve_v3", "d_reset", "basement_hatch_control"]:
		var control := controller.control(control_id) as Node2D
		_assert(control != null and control.z_index == -8 and control.z_as_relative, "Control %s musi być nad mechanizmami, ale pod bryłą L05." % control_id)


func _mechanism_visual_by_kind(controller, dynamic_kind: String) -> Node2D:
	for body_value: Variant in controller.find_children("*", "AnimatableBody2D", true, false):
		var body := body_value as AnimatableBody2D
		if str(body.get_meta(&"dynamic_kind", "")) == dynamic_kind:
			return body.get_node_or_null("MechanismVisual") as Node2D
	return null


func _barrier_group_has_visual_state(controller, group_id: String, expected_state: String) -> bool:
	var member_count := 0
	for body_value: Variant in controller.find_children("*", "AnimatableBody2D", true, false):
		var body := body_value as AnimatableBody2D
		if str(body.get_meta(&"barrier_group_id", "")) != group_id:
			continue
		member_count += 1
		var visual := body.get_node_or_null("MechanismVisual")
		if str(body.get_meta(&"visual_state", "")) != expected_state:
			return false
		if visual == null or str(visual.call("visual_state")) != expected_state:
			return false
	return member_count > 0


func _barrier_group_debug_snapshot(controller, group_id: String) -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	for body_value: Variant in controller.find_children("*", "AnimatableBody2D", true, false):
		var body := body_value as AnimatableBody2D
		if str(body.get_meta(&"barrier_group_id", "")) != group_id:
			continue
		var visual := body.get_node_or_null("MechanismVisual")
		members.append({
			"socket_id": str(body.get_meta(&"socket_id", "")),
			"position": body.position,
			"target_position": body.get_meta(&"target_position", Vector2.ZERO),
			"body_visual_state": str(body.get_meta(&"visual_state", "")),
			"reached_target": bool(body.get_meta(&"reached_target", false)),
			"mechanism_visual_state": (
				str(visual.call("visual_state"))
				if visual != null and visual.has_method("visual_state")
				else ""
			),
		})
	return members


func _await_barrier_group_target(controller, group_id: String) -> void:
	for _frame_index: int in range(180):
		if controller.barrier_group_reached_target(group_id):
			return
		await physics_frame


func _has_property(target: Object, property_name: StringName) -> bool:
	for property_value: Variant in target.get_property_list():
		var property := property_value as Dictionary
		if StringName(property.get("name", &"")) == property_name:
			return true
	return false


func _set_power_pattern(controller, positions: PackedStringArray) -> void:
	var snapshot: Dictionary = controller.state_snapshot()
	var current_positions := snapshot.get("lever_positions", {}) as Dictionary
	for lever_index: int in range(POWER_LEVER_IDS.size()):
		var lever_id := str(POWER_LEVER_IDS[lever_index])
		var target_position := str(positions[lever_index])
		if str(current_positions.get(lever_id, "up")) == target_position:
			continue
		var lever = controller.power_lever(lever_id)
		var result: Dictionary = lever.complete_dive_interaction()
		_assert(bool(result.get("success", false)), "Dźwignia %s musi przełączyć się przez zwykły kontrakt interakcji: %s." % [lever_id, result])
		current_positions[lever_id] = target_position


func _positions(first: String, second: String, third: String) -> Dictionary:
	return {
		"a_lever_1": first,
		"a_lever_2": second,
		"a_lever_3": third,
	}


func _verify_d_reset_and_fault_matrix(controller) -> void:
	_assert(bool(controller.activate_control("d_valve_v1").get("success", false)), "RESET D musi być dostępny po pierwszym poprawnym etapie.")
	_assert(bool(controller.activate_control("d_reset").get("success", false)), "RESET D musi wyzerować prefiks długości 1.")
	_assert(bool(controller.activate_control("d_valve_v1").get("success", false)), "Fixture resetu prefiksu 2 wymaga etapu 1.")
	_assert(bool(controller.activate_control("d_valve_v2").get("success", false)), "Fixture resetu prefiksu 2 wymaga etapu 2.")
	_assert(bool(controller.activate_control("d_reset").get("success", false)), "RESET D musi wyzerować prefiks długości 2.")
	var wrong_cases := [
		{"prefix": [], "wrong": 2},
		{"prefix": [], "wrong": 3},
		{"prefix": [1], "wrong": 1},
		{"prefix": [1], "wrong": 3},
		{"prefix": [1, 2], "wrong": 1},
		{"prefix": [1, 2], "wrong": 2},
	]
	for case_value: Variant in wrong_cases:
		var fault_case := case_value as Dictionary
		for prefix_step_value: Variant in (fault_case.get("prefix", []) as Array):
			var prefix_step := int(prefix_step_value)
			_assert(bool(controller.activate_control("d_valve_v%d" % prefix_step).get("success", false)), "Prefiks D musi być wykonalny przed testem błędu: %s." % [fault_case])
		var wrong_step := int(fault_case.get("wrong", 0))
		var result: Dictionary = controller.activate_control("d_valve_v%d" % wrong_step)
		_assert(not bool(result.get("success", true)), "Każdy niewłaściwy wybór D musi wejść w fault: %s." % [fault_case])
		var fault_state: Dictionary = controller.state_snapshot()
		_assert(bool(fault_state.get("d_requires_reset", false)), "Niewłaściwy wybór D musi wymagać RESET: %s." % [fault_case])
		_assert(str(fault_state.get("last_feedback_kind", "")) == "d_fault", "Każdy fault D musi mieć diagnostyczny feedback audio.")
		_assert(str(controller.control("d_valve_v1").visual_state()) == "fault" and str(controller.control("d_valve_v2").visual_state()) == "fault" and str(controller.control("d_valve_v3").visual_state()) == "fault", "Fault D musi być widoczny na wszystkich trzech stacjach.")
		_assert(bool(fault_state.get("red_latched", false)) and bool(fault_state.get("blue_latched", false)), "Fault D nie może cofnąć B ani C.")
		_assert(bool(fault_state.get("trolley_contact_closed", false)) and bool(fault_state.get("elevator_locked", false)), "Fault D nie może zwolnić styku pustego wózka.")
		_assert(controller.barrier_group_is_open("shortcut_b") and controller.barrier_group_is_open("shortcut_c"), "Fault D nie może zamknąć lokalnych skrótów B/C.")
		_assert(not bool(controller.activate_control("d_valve_v1").get("success", true)), "Po fault żaden etap D nie może działać przed RESET.")
		_assert(bool(controller.activate_control("d_reset").get("success", false)), "RESET D musi działać z każdego stanu fault.")
		var reset_state: Dictionary = controller.state_snapshot()
		_assert(int(reset_state.get("d_progress", -1)) == 0 and not bool(reset_state.get("d_requires_reset", true)), "RESET D musi wyzerować wyłącznie lokalną sekwencję.")
		_assert(bool(reset_state.get("red_latched", false)) and bool(reset_state.get("blue_latched", false)) and bool(reset_state.get("trolley_contact_closed", false)), "RESET D musi zachować B, C i styk pustego wózka.")


func _verify_safety_envelopes(controller, structure_root: Node2D) -> void:
	_set_power_pattern(controller, ["down", "down", "down"])
	_assert(controller.barrier_group_is_open("red_route"), "Fixture safety wymaga aktywnego RED.")
	for _frame_index: int in range(45):
		await physics_frame
	var decoy := CharacterBody2D.new()
	decoy.name = "NonDiverCharacterBody"
	decoy.collision_layer = 1
	decoy.collision_mask = 1
	decoy.position = Vector2(1000.0, 1020.0)
	var decoy_collision := CollisionShape2D.new()
	var decoy_shape := RectangleShape2D.new()
	decoy_shape.size = Vector2(40.0, 70.0)
	decoy_collision.shape = decoy_shape
	decoy.add_child(decoy_collision)
	structure_root.add_child(decoy)
	await physics_frame
	await physics_frame
	_assert(controller.barrier_group_safety_clear("red_route"), "CharacterBody2D bez roli nurka nie może blokować safety envelope.")
	decoy.queue_free()
	await physics_frame
	var blocker := CharacterBody2D.new()
	blocker.name = "SafetyBlocker"
	blocker.add_to_group(DIVE_PLAYER_GROUP)
	blocker.collision_layer = 1
	blocker.collision_mask = 1
	blocker.position = Vector2(1000.0, 1020.0)
	var blocker_collision := CollisionShape2D.new()
	var blocker_shape := RectangleShape2D.new()
	blocker_shape.size = Vector2(40.0, 70.0)
	blocker_collision.shape = blocker_shape
	blocker.add_child(blocker_collision)
	structure_root.add_child(blocker)
	await physics_frame
	await physics_frame
	_assert(not controller.barrier_group_safety_clear("red_route"), "Safety envelope ma wykryć nurka w zamykanym otworze.")
	_assert(not controller.request_barrier_group_open("red_route", false), "Drzwi nie mogą rozpocząć zamknięcia na nurku.")
	_assert(controller.barrier_group_is_open("red_route"), "Odrzucone zamknięcie nie może zmienić stanu grupy.")
	_set_power_pattern(controller, ["up", "up", "up"])
	await physics_frame
	_assert(
		controller.barrier_group_is_open("red_route")
		and _barrier_group_has_visual_state(controller, "red_route", "open"),
		"Po odłączeniu RED drzwi muszą pozostać fizycznie i wizualnie open, dopóki Nurek zajmuje safety envelope.",
	)
	blocker.position = Vector2(400.0, 400.0)
	await physics_frame
	await physics_frame
	_assert(controller.request_barrier_group_open("red_route", false), "Po opuszczeniu safety envelope zamknięcie ma być dozwolone.")
	_assert(_barrier_group_has_visual_state(controller, "red_route", "closing"), "Dozwolone zamknięcie RED musi natychmiast opublikować stan closing.")
	await _await_barrier_group_target(controller, "red_route")
	_assert(
		_barrier_group_has_visual_state(controller, "red_route", "closed"),
		"Drzwi RED muszą zakończyć zamknięcie stanem closed: %s."
		% [_barrier_group_debug_snapshot(controller, "red_route")],
	)

	controller.reset_attempt()
	blocker.position = Vector2(1280.0, 180.0)
	var blocker_parent_before := blocker.get_parent()
	var blocker_position_before := blocker.position
	await physics_frame
	await physics_frame
	_assert(not controller.elevator_safety_clear(), "Safety envelope pustego wózka ma wykryć nurka przed ruchem: %s" % controller.state_snapshot())
	_set_power_pattern(controller, ["down", "down", "down"])
	_assert(bool(controller.activate_control("b_red_relay").get("success", false)), "Fixture pustego wózka wymaga B.")
	_set_power_pattern(controller, ["up", "down", "up"])
	for _frame_index: int in range(5):
		await physics_frame
	_assert(controller.elevator_current_stop_id() == "floor_12", "Pusty wózek ma czekać, gdy nurek zajmuje jego safety envelope: %s" % controller.state_snapshot())
	_assert(str(controller.state_snapshot().get("trolley_visual_state", "")) == "blocked_by_diver", "Zablokowany pusty wózek musi mieć czytelny stan wizualny.")
	var blocked_visual := _mechanism_visual_by_kind(controller, "empty_maintenance_trolley")
	if blocked_visual != null:
		var blocked_wheel_phase := float(blocked_visual.get("_wheel_phase"))
		for _frame_index: int in range(4):
			await process_frame
		_assert(is_equal_approx(float(blocked_visual.get("_wheel_phase")), blocked_wheel_phase), "Sygnalizacja blocked_by_diver może pulsować, ale koła pustego wózka muszą stać.")
	_assert(blocker.get_parent() == blocker_parent_before and blocker.position == blocker_position_before, "Pusty wózek nie może reparentować ani przewozić Nurka.")
	blocker.position = Vector2(400.0, 400.0)
	await physics_frame
	await physics_frame
	await _await_elevator_stop(controller, "floor_7")
	_assert(controller.elevator_reached_stop("floor_7"), "Po zwolnieniu safety envelope pusty wózek ma wznowić ruch.")
	blocker.queue_free()


func _await_elevator_stop(controller, stop_id: String) -> void:
	for _frame_index: int in range(420):
		if controller.elevator_reached_stop(stop_id):
			return
		await physics_frame


func _all_groups_have_state(controller, expected_open: bool) -> bool:
	for group_id: String in [
		"red_route",
		"blue_route",
		"yellow_route",
		"shortcut_b",
		"shortcut_c",
		"hatch_d",
		"hatch_basement",
	]:
		if controller.barrier_group_is_open(group_id) != expected_open:
			return false
	return true


func _load_package_manifest() -> Dictionary:
	var file := FileAccess.open(PACKAGE_MANIFEST_PATH, FileAccess.READ)
	_assert(file != null, "Nie można otworzyć manifestu pakietu: %s." % PACKAGE_MANIFEST_PATH)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_assert(parsed is Dictionary, "Manifest pakietu musi być poprawnym obiektem JSON.")
	if not parsed is Dictionary:
		return {}
	return parsed as Dictionary


func _manifest_power_logic() -> Dictionary:
	return _power_logic_from_runtime(_package_manifest.get("runtime", null))


func _power_logic_from_runtime(runtime_value: Variant) -> Dictionary:
	if not runtime_value is Dictionary:
		return {}
	var interactives_value: Variant = (runtime_value as Dictionary).get("interactives", null)
	if not interactives_value is Array:
		return {}
	for definition_value: Variant in interactives_value as Array:
		if not definition_value is Dictionary:
			continue
		var definition := definition_value as Dictionary
		if str(definition.get("kind", "")) != "power_distributor":
			continue
		var power_logic_value: Variant = definition.get("power_logic", null)
		if power_logic_value is Dictionary:
			return power_logic_value as Dictionary
		return {}
	return {}


func _effective_structure_record(package_manifest: Dictionary) -> Dictionary:
	var template_value: Variant = package_manifest.get("template", null)
	var size_value: Variant = package_manifest.get("size", null)
	var sockets_value: Variant = package_manifest.get("sockets", null)
	var runtime_value: Variant = package_manifest.get("runtime", null)
	_assert(template_value is Dictionary, "Manifest pakietu musi zawierać słownik template.")
	_assert(size_value is Array and (size_value as Array).size() == 2, "Manifest pakietu musi zawierać dwuelementowy size.")
	_assert(sockets_value is Array, "Manifest pakietu musi zawierać tablicę sockets.")
	_assert(runtime_value is Dictionary, "Manifest pakietu musi zawierać słownik runtime.")
	if not template_value is Dictionary or not size_value is Array or not sockets_value is Array or not runtime_value is Dictionary:
		return {}
	var template := template_value as Dictionary
	var template_id := str(template.get("id", ""))
	_assert(not template_id.is_empty(), "Manifest pakietu musi wskazywać template.id.")
	if template_id.is_empty():
		return {}
	return {
		"id": STRUCTURE_ID,
		"template_id": template_id,
		"origin": [0, 0],
		"size": (size_value as Array).duplicate(true),
		"sockets": (sockets_value as Array).duplicate(true),
		"runtime": (runtime_value as Dictionary).duplicate(true),
	}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("Enterable tower runtime test passed.")
	quit(0)
