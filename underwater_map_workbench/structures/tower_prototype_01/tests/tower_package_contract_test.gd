extends SceneTree

const PACKAGE_MANIFEST_PATH := "res://underwater_map_workbench/structures/tower_prototype_01/structure_manifest.json"
const PACKAGE_ROOT := "res://underwater_map_workbench/structures/tower_prototype_01/"
const PACKAGE_SCENE_PATH := PACKAGE_ROOT + "generated/structure.tscn"
const STRUCTURE_TEXTURE_PATH := PACKAGE_ROOT + "assets/visual/tower_structure.png"
const INTERIOR_TEXTURE_PATH := PACKAGE_ROOT + "assets/visual/tower_interior.png"
const STRUCTURE_SOURCE_PATH := PACKAGE_ROOT + "assets/visual/tower_structure_source.svg"
const INTERIOR_SOURCE_PATH := PACKAGE_ROOT + "assets/visual/tower_interior_source.svg"
const SOLID_MASK_PATH := PACKAGE_ROOT + "generated/solid_mask_native.png"
const OPEN_MASK_PATH := PACKAGE_ROOT + "generated/open_water_mask_native.png"
const STRUCTURE_ID := "tower_prototype_01"
const TowerControllerScript := preload("res://underwater_map_workbench/structures/tower_prototype_01/runtime/DiveEnterableTowerController.gd")
const StructureInteractableScript := preload("res://underwater_map_workbench/structures/tower_prototype_01/runtime/DiveStructureInteractable.gd")
const EXPECTED_LEVER_IDS := ["a_lever_1", "a_lever_2", "a_lever_3"]
const EXPECTED_GROUP_IDS := [
	"blue_route",
	"hatch_basement",
	"hatch_d",
	"red_route",
	"shortcut_b",
	"shortcut_c",
	"yellow_route",
]

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var package_manifest := _load_package_manifest()
	if package_manifest.is_empty():
		_finish()
		return
	_verify_package_contract(package_manifest)
	_verify_native_artwork(package_manifest)
	_verify_generated_scene(package_manifest)
	var effective_structure := _effective_structure_record(package_manifest)
	if effective_structure.is_empty():
		_finish()
		return

	var mounted := _mount_runtime(effective_structure, "PrimaryRuntime")
	var controller = mounted.get("controller")
	var structure_root := mounted.get("root") as Node2D
	var interactives_root := mounted.get("interactives") as Node2D
	if controller == null or structure_root == null or interactives_root == null:
		_finish()
		return
	_verify_runtime_shape(controller, interactives_root, package_manifest)
	_verify_attempt_reset_and_fresh_instance(controller, effective_structure)
	structure_root.free()
	_finish()


func _verify_package_contract(package_manifest: Dictionary) -> void:
	_assert(int(package_manifest.get("schema_version", 0)) == 1, "Pakiet wieżowca musi używać schema_version 1.")
	_assert(str(package_manifest.get("format", "")) == "enterable_structure_package_v1", "Pakiet wieżowca ma nieobsługiwany format.")
	var template := package_manifest.get("template", {}) as Dictionary
	_assert(str(template.get("id", "")) == "enterable_tower_v1", "Pakiet musi wskazywać enterable_tower_v1.")
	var size := package_manifest.get("size", []) as Array
	_assert(size.size() == 2 and float(size[0]) == 2240.0 and float(size[1]) == 3680.0, "Pakiet musi zachować natywny rozmiar 2240x3680.")

	var attempt_state := package_manifest.get("attempt_state", {}) as Dictionary
	_assert(attempt_state == {
		"persistence": "none",
		"checkpoint": "none",
		"reset": "whole_structure_attempt",
	}, "Pakiet musi jawnie wyłączać persistence i checkpoint oraz resetować całą próbę.")
	var runtime := package_manifest.get("runtime", {}) as Dictionary
	_assert(not _contains_any_key(runtime, [&"persistence", &"checkpoint", &"persistent_id"]), "Runtime pakietu nie może zawierać kontraktu zapisu ani checkpointu.")
	_assert(str(runtime.get("contract", "")) == "enterable_tower_sequence_v3", "Runtime pakietu musi używać enterable_tower_sequence_v3.")

	var scripts := package_manifest.get("scripts", []) as Array
	var script_roles: Array[String] = []
	for script_value: Variant in scripts:
		var script_record := script_value as Dictionary
		script_roles.append(str(script_record.get("role", "")))
		var script_path := PACKAGE_ROOT + str(script_record.get("path", ""))
		var script_file := FileAccess.open(script_path, FileAccess.READ)
		_assert(script_file != null, "Nie można otworzyć prywatnego skryptu pakietu: %s." % script_path)
		if script_file != null:
			_assert(not _declares_global_class(script_file.get_as_text()), "Prywatny skrypt pakietu nie może publikować globalnego class_name: %s." % script_path)
	script_roles.sort()
	_assert(script_roles == ["controller", "interactable", "mechanism_visual", "power_panel"], "Pakiet musi publikować cztery prywatne role skryptów, w tym grafikę mechanizmów.")

	var sockets := package_manifest.get("sockets", []) as Array
	_assert(sockets.size() == 22, "Pakiet musi publikować dokładnie 22 sockety.")
	_assert(_count_socket_kind(sockets, "entry_opening") == 1, "Pakiet musi mieć jedno wejście.")
	_assert(_count_socket_kind(sockets, "moving_elevator") == 1, "Pakiet musi mieć jeden socket windy.")
	_assert(_count_socket_kind(sockets, "dynamic_door") == 12, "Pakiet musi mieć dwanaście socketów barier.")
	_assert(_count_socket_kind(sockets, "fixed_interactable") == 8, "Pakiet musi mieć osiem socketów controls.")

	var groups := runtime.get("barrier_groups", []) as Array
	_assert(groups.size() == 7, "Runtime pakietu musi definiować siedem grup barier.")
	var group_ids: Array[String] = []
	var member_count := 0
	for group_value: Variant in groups:
		var group := group_value as Dictionary
		group_ids.append(str(group.get("id", "")))
		member_count += (group.get("members", []) as Array).size()
	group_ids.sort()
	_assert(group_ids == EXPECTED_GROUP_IDS, "Pakiet musi publikować siedem stabilnych group IDs: %s." % [group_ids])
	_assert(member_count == 12, "Siedem grup musi łącznie sterować dwunastoma barierami.")

	var elevator := runtime.get("elevator", {}) as Dictionary
	_assert(str(elevator.get("id", "")) == "elevator_main", "Pakiet musi zachować techniczne id mechanizmu elevator_main.")
	_assert(str(elevator.get("socket_id", "")) == "elevator_upper_travel", "Pusty wózek musi korzystać ze swojego socketu podróży.")
	_assert(str(elevator.get("initial_stop_id", "")) == "floor_12", "Pusty wózek musi zaczynać na floor_12.")
	_assert((elevator.get("stops", []) as Array).size() == 2, "Pusty wózek musi mieć dwa jawne położenia mechaniczne.")

	var interactives := runtime.get("interactives", []) as Array
	_assert(interactives.size() == 8, "Runtime pakietu musi definiować osiem wysokopoziomowych controls.")
	var power_definition := _interactive_by_kind(interactives, "power_distributor")
	var power_logic := power_definition.get("power_logic", {}) as Dictionary
	_assert(str(power_logic.get("contract", "")) == "three_lever_deduction_v2", "Rozdzielnia A musi używać dedukcyjnego kontraktu trzech dźwigni.")
	_assert(str(power_logic.get("evaluation", "")) == "on_toggle", "Rozdzielnia A musi oceniać układ po każdym przełączeniu.")
	var levers := power_logic.get("levers", []) as Array
	_assert(levers.size() == 3 and (1 << levers.size()) == 8, "Trzy binarne dźwignie muszą dawać dokładnie osiem kombinacji.")
	var lever_ids: Array[String] = []
	for lever_value: Variant in levers:
		var lever := lever_value as Dictionary
		lever_ids.append(str(lever.get("id", "")))
		_assert(str(lever.get("initial_position", "")) == "up", "Każda dźwignia musi zaczynać w pozycji up.")
	_assert(lever_ids == EXPECTED_LEVER_IDS, "Pakiet musi zachować trzy stabilne lever IDs.")
	var circuits := power_logic.get("circuits", {}) as Dictionary
	_assert(circuits.size() == 3, "Trzy obwody muszą mapować trzy poprawne kombinacje.")
	_assert((circuits.get("red", {}) as Dictionary).get("positions", []) == ["down", "down", "down"], "RED musi odpowiadać down/down/down.")
	_assert((circuits.get("blue", {}) as Dictionary).get("positions", []) == ["up", "down", "up"], "BLUE musi odpowiadać up/down/up.")
	_assert((circuits.get("yellow", {}) as Dictionary).get("positions", []) == ["down", "up", "up"], "YELLOW musi odpowiadać down/up/up.")
	var diagnostics := power_logic.get("diagnostics", {}) as Dictionary
	_assert(diagnostics.size() == 5, "Pięć niewłaściwych układów A musi mieć pięć diagnostycznych powodów.")
	var diagnostic_positions := {}
	for reason_id_value: Variant in diagnostics.keys():
		var reason_id := str(reason_id_value)
		var diagnostic := diagnostics[reason_id] as Dictionary
		var position_parts := PackedStringArray()
		for position_value: Variant in diagnostic.get("positions", []) as Array:
			position_parts.append(str(position_value))
		var position_key := "/".join(position_parts)
		diagnostic_positions[position_key] = true
		_assert(not str(diagnostic.get("message", "")).is_empty(), "Diagnostyka %s musi mieć czytelny komunikat." % reason_id)
	_assert(diagnostic_positions.size() == 5, "Każdy błędny układ A musi mieć unikalną diagnostykę.")
	var clues := power_logic.get("clues", {}) as Dictionary
	_assert(clues.size() == 3 and not str(clues.get("red", "")).is_empty() and not str(clues.get("blue", "")).is_empty() and not str(clues.get("yellow", "")).is_empty(), "A/B/C muszą publikować trzy przesłanki dedukcyjne.")


func _verify_native_artwork(package_manifest: Dictionary) -> void:
	var structure_image := Image.load_from_file(STRUCTURE_TEXTURE_PATH)
	var interior_image := Image.load_from_file(INTERIOR_TEXTURE_PATH)
	var solid_mask := Image.load_from_file(SOLID_MASK_PATH)
	var open_mask := Image.load_from_file(OPEN_MASK_PATH)
	_assert(structure_image != null and interior_image != null and solid_mask != null and open_mask != null, "Warstwy 1:1 i kanoniczne maski muszą być ładowalne.")
	if structure_image == null or interior_image == null or solid_mask == null or open_mask == null:
		return
	var native_size := Vector2i(2240, 3680)
	_assert(structure_image.get_size() == native_size and interior_image.get_size() == native_size, "Obie grafiki wieżowca muszą mieć natywne 2240x3680 bez skalowania.")
	_assert(solid_mask.get_size() == native_size and open_mask.get_size() == native_size, "Kanoniczne maski muszą mieć ten sam rozmiar 1:1.")
	structure_image.convert(Image.FORMAT_RGBA8)
	interior_image.convert(Image.FORMAT_RGBA8)
	solid_mask.convert(Image.FORMAT_L8)
	open_mask.convert(Image.FORMAT_L8)
	var structure_bytes := structure_image.get_data()
	var interior_bytes := interior_image.get_data()
	var solid_bytes := solid_mask.get_data()
	var open_bytes := open_mask.get_data()
	var pixel_count := native_size.x * native_size.y
	var mismatch_count := 0
	var overlap_count := 0
	var gap_count := 0
	for pixel_index: int in range(pixel_count):
		var structure_alpha := int(structure_bytes[pixel_index * 4 + 3])
		var interior_alpha := int(interior_bytes[pixel_index * 4 + 3])
		var solid_value := int(solid_bytes[pixel_index])
		var open_value := int(open_bytes[pixel_index])
		if structure_alpha != solid_value or interior_alpha != open_value:
			mismatch_count += 1
		if structure_alpha > 0 and interior_alpha > 0:
			overlap_count += 1
		if structure_alpha == 0 and interior_alpha == 0:
			gap_count += 1
	_assert(mismatch_count == 0, "Alfa obu grafik musi zgadzać się piksel w piksel z colliderem/open-water: %d różnic." % mismatch_count)
	_assert(overlap_count == 0 and gap_count == 0, "Złożona grafika budynku musi być pełnym prostokątem 2240x3680 bez nakładek i luk.")
	var asset_hashes := {}
	for asset_value: Variant in package_manifest.get("visual_assets", []) as Array:
		var asset := asset_value as Dictionary
		asset_hashes[str(asset.get("path", ""))] = str(asset.get("sha256", ""))
	_assert(str(asset_hashes.get("assets/visual/tower_structure.png", "")) == FileAccess.get_sha256(STRUCTURE_TEXTURE_PATH), "Manifest musi przypinać finalną grafikę bryły.")
	_assert(str(asset_hashes.get("assets/visual/tower_interior.png", "")) == FileAccess.get_sha256(INTERIOR_TEXTURE_PATH), "Manifest musi przypinać finalną grafikę wnętrza.")
	var structure_source := FileAccess.get_file_as_string(STRUCTURE_SOURCE_PATH)
	var interior_source := FileAccess.get_file_as_string(INTERIOR_SOURCE_PATH)
	_assert(structure_source.contains("width=\"2240\"") and structure_source.contains("height=\"3680\""), "Źródło bryły musi powstawać bezpośrednio na płótnie 1:1.")
	_assert(interior_source.contains("width=\"2240\"") and interior_source.contains("height=\"3680\""), "Źródło wnętrza musi powstawać bezpośrednio na płótnie 1:1.")
	_assert(not structure_source.contains("tower_art_source") and not interior_source.contains("tower_art_source"), "Finalna grafika nie może skalować obcego konceptu rastrowego.")
	_assert(not interior_source.contains("radialGradient") and not interior_source.contains("lampAmber") and not interior_source.contains("lampCyan"), "Wnętrze musi pozostać nieemisyjne i bez wypalonych świateł.")


func _verify_generated_scene(package_manifest: Dictionary) -> void:
	var packed_scene := load(PACKAGE_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Wygenerowana scena pakietu musi być ładowalnym PackedScene.")
	if packed_scene == null:
		return
	var structure_root := packed_scene.instantiate() as Node2D
	_assert(structure_root != null, "Wygenerowana scena pakietu musi mieć root Node2D.")
	if structure_root == null:
		return
	_assert(structure_root.position == Vector2.ZERO and structure_root.scale == Vector2.ONE, "Root pakietu musi zachować identity transform.")
	for asset_value: Variant in package_manifest.get("visual_assets", []) as Array:
		var asset := asset_value as Dictionary
		var mount_name := "InteriorVisual" if str(asset.get("kind", "")) == "structure_interior_texture" else "StructureVisual"
		var node_path := "%s/%s/%s" % [mount_name, str(asset.get("group_id", "")), str(asset.get("id", ""))]
		var asset_node := structure_root.get_node_or_null(node_path)
		_assert(asset_node != null, "Scena pakietu musi zawierać asset %s." % str(asset.get("id", "")))
		if asset_node != null:
			var source := asset_node.get_meta(&"source", {}) as Dictionary
			var expected_source := asset.duplicate(true)
			expected_source["path"] = "structures/%s/%s" % [STRUCTURE_ID, str(asset.get("path", ""))]
			expected_source["structure_id"] = STRUCTURE_ID
			expected_source["topology_digest"] = asset_node.get_meta(&"topology_digest", "")
			expected_source["partition_digest"] = asset_node.get_meta(&"partition_digest", "")
			_assert(str(expected_source["topology_digest"]).begins_with("topology-v1:"), "Asset sceny musi być związany z topologią mapy.")
			_assert(str(expected_source["partition_digest"]).begins_with("partition-v1:"), "Asset sceny musi być związany z partycją mapy.")
			_assert(
				_canonical_json(source) == _canonical_json(expected_source),
				"Asset %s w scenie musi zachować dokładne rozwinięte source metadata." % str(asset.get("id", "")),
			)
	structure_root.free()


func _verify_runtime_shape(controller, interactives_root: Node2D, package_manifest: Dictionary) -> void:
	_assert(str(controller.get_meta(&"structure_id", "")) == STRUCTURE_ID, "Kontroler musi dostać stable ID efektywnego rekordu.")
	_assert(str(controller.get_meta(&"runtime_contract", "")) == "enterable_tower_sequence_v3", "Kontroler musi skonsumować kontrakt runtime z pakietu.")
	_assert(controller.power_lever_ids() == PackedStringArray(EXPECTED_LEVER_IDS), "Kontroler musi utworzyć trzy dźwignie z manifestu.")
	_assert(interactives_root.get_child_count() == 8, "Kontroler musi utworzyć osiem wysokopoziomowych controls.")
	var interactive_areas := interactives_root.find_children("*", "Area2D", true, false)
	_assert(interactive_areas.size() == 10, "Osiem controls, w tym panel z trzema osobnymi lever Area2D, musi dawać dziesięć Area2D.")
	for area_value: Variant in interactive_areas:
		var area := area_value as Area2D
		_assert(area.get_script() == StructureInteractableScript, "Każda strefa interakcji wieżowca musi używać attempt-local interactable.")
		_assert(not _has_property(area, &"persistent_id"), "Interakcja wieżowca nie może publikować persistent_id.")
		var interaction_collision := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		_assert(interaction_collision != null and interaction_collision.shape is RectangleShape2D, "Każdy obiekt interaktywny musi mieć prostokątny collider 1:1.")
		if interaction_collision != null and interaction_collision.shape is RectangleShape2D:
			var interaction_size := (interaction_collision.shape as RectangleShape2D).size
			var native_visual_size: Variant = area.get_meta(&"native_visual_size", Vector2.ZERO)
			var native_visual_rect: Variant = area.get_meta(&"native_visual_rect", Rect2())
			_assert(native_visual_size is Vector2 and (native_visual_size as Vector2).is_equal_approx(interaction_size), "Grafika obiektu interaktywnego musi mieć dokładny rozmiar jego collidera.")
			_assert(native_visual_rect is Rect2 and (native_visual_rect as Rect2).is_equal_approx(Rect2(-interaction_size * 0.5, interaction_size)), "Granice grafiki obiektu interaktywnego muszą być wycentrowane 1:1 na colliderze.")

	var power_panel = controller.control("a_distributor")
	var panel_socket_rect: Variant = power_panel.get_meta(&"socket_rect", Rect2())
	var panel_visual_rect: Variant = power_panel.get_meta(&"native_visual_rect", Rect2())
	_assert(panel_socket_rect is Rect2 and panel_visual_rect is Rect2 and (panel_visual_rect as Rect2).is_equal_approx(panel_socket_rect as Rect2), "Grafika rozdzielni A musi dokładnie wypełniać własny socket 320x120.")
	if panel_socket_rect is Rect2:
		for label_value: Variant in power_panel.find_children("*", "Label", true, false):
			var label := label_value as Label
			_assert((panel_socket_rect as Rect2).encloses(Rect2(label.position, label.size)), "Żaden opis rozdzielni A nie może wychodzić poza jej socket ani collider.")

	var dynamic_bodies: Array[Node] = controller.find_children("*", "AnimatableBody2D", true, false)
	var elevator_count := 0
	var barrier_count := 0
	var runtime := package_manifest.get("runtime", {}) as Dictionary
	var elevator := runtime.get("elevator", {}) as Dictionary
	var elevator_size := _vector_from_value(elevator.get("cabin_size", null))
	for body_value: Variant in dynamic_bodies:
		var body := body_value as AnimatableBody2D
		var mechanism_visual := body.get_node_or_null("MechanismVisual") as Node2D
		var mechanism_collision := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
		_assert(mechanism_visual != null, "Każdy ruchomy collider musi nieść własną grafikę 1:1.")
		_assert(mechanism_collision != null and mechanism_collision.shape is RectangleShape2D, "Każdy ruchomy obiekt musi mieć prostokątny collider.")
		if mechanism_visual != null and mechanism_collision != null and mechanism_collision.shape is RectangleShape2D:
			var collider_size := (mechanism_collision.shape as RectangleShape2D).size
			var visual_size: Variant = mechanism_visual.get_meta(&"native_visual_size", Vector2.ZERO)
			var visual_rect: Variant = mechanism_visual.get_meta(&"native_visual_rect", Rect2())
			_assert(mechanism_visual.position.is_zero_approx(), "Grafika ruchomego obiektu musi być wycentrowana na tym samym body co collider.")
			_assert(visual_size is Vector2 and (visual_size as Vector2).is_equal_approx(collider_size), "Grafika ruchomego obiektu musi mieć dokładny rozmiar collidera.")
			_assert(visual_rect is Rect2 and (visual_rect as Rect2).is_equal_approx(Rect2(-collider_size * 0.5, collider_size)), "Natywne granice grafiki ruchomego obiektu muszą pokrywać collider 1:1.")
		match str(body.get_meta(&"dynamic_kind", "")):
			"empty_maintenance_trolley":
				elevator_count += 1
				if mechanism_collision != null and mechanism_collision.shape is RectangleShape2D:
					_assert((mechanism_collision.shape as RectangleShape2D).size.is_equal_approx(elevator_size), "Pusty wózek musi mieć dokładny manifestowy rozmiar 464x200.")
			"dynamic_door":
				barrier_count += 1
				if mechanism_collision != null and mechanism_collision.shape is RectangleShape2D:
					var socket_rect := _socket_rect_by_id(package_manifest, str(body.get_meta(&"socket_id", "")))
					_assert((mechanism_collision.shape as RectangleShape2D).size.is_equal_approx(socket_rect.size), "Grafika i collider drzwi muszą dokładnie odpowiadać rozmiarowi socketu.")
	_assert(elevator_count == 1 and barrier_count == 12, "Efektywny runtime musi utworzyć jedną windę i dwanaście barier.")
	_assert(controller.find_children("SafetyEnvelope", "Area2D", true, false).size() == 13, "Każde dynamiczne ciało musi mieć safety envelope.")

	_assert(controller.elevator_current_stop_id() == str(elevator.get("initial_stop_id", "")), "Stan windy musi pochodzić z initial_stop_id manifestu.")
	_assert(controller.elevator_target_stop_id() == "floor_12", "Cel windy po konfiguracji musi być floor_12.")
	_assert(_all_groups_have_state(controller, false), "Wszystkie siedem grup musi zaczynać jako closed.")
	var initial: Dictionary = controller.state_snapshot()
	_assert(initial.get("lever_positions", {}) == _positions("up", "up", "up"), "Runtime musi skonsumować startowe pozycje up/up/up.")
	_assert(initial.get("circuit_states", {}) == {"red": "ready", "blue": "locked", "yellow": "locked"}, "Runtime musi rozpocząć bez odziedziczonych latchy.")
	_assert(not controller.is_public_gate_open(&"attempt_complete") and not controller.is_public_gate_open(&"unknown"), "Świeża próba nie może publikować otwartej bramki publicznej.")


func _verify_attempt_reset_and_fresh_instance(controller, effective_structure: Dictionary) -> void:
	_set_power_pattern(controller, ["down", "down", "down"])
	_assert(controller.barrier_group_is_open("red_route"), "Aktywny wzorzec RED musi otworzyć red_route.")
	_assert(bool(controller.activate_control("b_red_relay").get("success", false)), "B musi zatrzasnąć RED w obrębie bieżącej próby.")
	_set_power_pattern(controller, ["up", "down", "up"])
	_assert(controller.barrier_group_is_open("blue_route"), "BLUE po B musi otworzyć blue_route.")
	_assert(controller.elevator_target_stop_id() == "floor_7", "Aktywny BLUE po B musi wysłać windę na floor_7.")

	controller.reset_attempt()
	_assert(controller.state_snapshot().get("lever_positions", {}) == _positions("up", "up", "up"), "reset_attempt musi przywrócić startowe pozycje dźwigni.")
	_assert(controller.elevator_current_stop_id() == "floor_12" and controller.elevator_target_stop_id() == "floor_12", "reset_attempt musi przywrócić windę na floor_12.")
	_assert(_all_groups_have_state(controller, false), "reset_attempt musi zamknąć wszystkie siedem grup.")
	_assert(not controller.is_public_gate_open(&"attempt_complete"), "reset_attempt musi zamknąć attempt_complete.")

	_set_power_pattern(controller, ["down", "down", "down"])
	_assert(bool(controller.activate_control("b_red_relay").get("success", false)), "Fixture fresh instance wymaga lokalnie zatrzaśniętego RED.")
	var fresh := _mount_runtime(effective_structure, "FreshRuntime")
	var fresh_controller = fresh.get("controller")
	var fresh_root := fresh.get("root") as Node2D
	if fresh_controller != null:
		var fresh_state: Dictionary = fresh_controller.state_snapshot()
		_assert(fresh_state.get("lever_positions", {}) == _positions("up", "up", "up"), "Nowa instancja nie może odtworzyć pozycji dźwigni poprzedniej próby.")
		_assert(not bool(fresh_state.get("red_latched", true)), "Nowa instancja nie może odtworzyć attempt-local latcha RED.")
		_assert(fresh_controller.elevator_current_stop_id() == "floor_12", "Nowa instancja musi zaczynać z windą na floor_12.")
		_assert(_all_groups_have_state(fresh_controller, false), "Nowa instancja nie może odtworzyć otwartych barier.")
		_assert(not fresh_controller.is_public_gate_open(&"attempt_complete"), "Nowa instancja nie może odziedziczyć attempt_complete.")
	if fresh_root != null:
		fresh_root.free()


func _mount_runtime(effective_structure: Dictionary, node_name: String) -> Dictionary:
	var structure_root := Node2D.new()
	structure_root.name = node_name
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
	var errors := controller.configure(effective_structure, interactives)
	_assert(errors.is_empty(), "Pakiet musi skonfigurować lokalny controller bez błędów: %s." % errors)
	if not errors.is_empty():
		structure_root.free()
		return {}
	return {"root": structure_root, "interactives": interactives, "controller": controller}


func _load_package_manifest() -> Dictionary:
	var file := FileAccess.open(PACKAGE_MANIFEST_PATH, FileAccess.READ)
	_assert(file != null, "Nie można otworzyć manifestu pakietu: %s." % PACKAGE_MANIFEST_PATH)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_assert(parsed is Dictionary, "Manifest pakietu musi być poprawnym obiektem JSON.")
	return parsed as Dictionary if parsed is Dictionary else {}


func _effective_structure_record(package_manifest: Dictionary) -> Dictionary:
	var template_value: Variant = package_manifest.get("template", null)
	var size_value: Variant = package_manifest.get("size", null)
	var sockets_value: Variant = package_manifest.get("sockets", null)
	var runtime_value: Variant = package_manifest.get("runtime", null)
	_assert(template_value is Dictionary and not str((template_value as Dictionary).get("id", "")).is_empty(), "Pakiet musi zawierać template.id.")
	_assert(size_value is Array and (size_value as Array).size() == 2, "Pakiet musi zawierać dwuelementowy size.")
	_assert(sockets_value is Array, "Pakiet musi zawierać tablicę sockets.")
	_assert(runtime_value is Dictionary, "Pakiet musi zawierać słownik runtime.")
	if not template_value is Dictionary or not size_value is Array or not sockets_value is Array or not runtime_value is Dictionary:
		return {}
	return {
		"id": STRUCTURE_ID,
		"template_id": str((template_value as Dictionary).get("id", "")),
		"origin": [0, 0],
		"size": (size_value as Array).duplicate(true),
		"sockets": (sockets_value as Array).duplicate(true),
		"runtime": (runtime_value as Dictionary).duplicate(true),
	}


func _interactive_by_kind(interactives: Array, kind: String) -> Dictionary:
	for interactive_value: Variant in interactives:
		var interactive := interactive_value as Dictionary
		if str(interactive.get("kind", "")) == kind:
			return interactive
	return {}


func _count_socket_kind(sockets: Array, kind: String) -> int:
	var count := 0
	for socket_value: Variant in sockets:
		if str((socket_value as Dictionary).get("kind", "")) == kind:
			count += 1
	return count


func _contains_any_key(value: Variant, forbidden_keys: Array[StringName]) -> bool:
	if value is Dictionary:
		for key_value: Variant in (value as Dictionary).keys():
			if StringName(str(key_value)) in forbidden_keys:
				return true
			if _contains_any_key((value as Dictionary)[key_value], forbidden_keys):
				return true
	elif value is Array:
		for child_value: Variant in value as Array:
			if _contains_any_key(child_value, forbidden_keys):
				return true
	return false


func _declares_global_class(source: String) -> bool:
	for line: String in source.split("\n"):
		if line.strip_edges().begins_with("class_name "):
			return true
	return false


func _has_property(target: Object, property_name: StringName) -> bool:
	for property_value: Variant in target.get_property_list():
		if StringName((property_value as Dictionary).get("name", &"")) == property_name:
			return true
	return false


func _socket_rect_by_id(package_manifest: Dictionary, socket_id: String) -> Rect2:
	for socket_value: Variant in package_manifest.get("sockets", []):
		var socket := socket_value as Dictionary
		if str(socket.get("id", "")) != socket_id:
			continue
		var rect_value: Variant = socket.get("local_rect", null)
		if rect_value is Array and (rect_value as Array).size() == 4:
			var values := rect_value as Array
			return Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	return Rect2()


func _vector_from_value(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Array and (value as Array).size() == 2:
		var values := value as Array
		return Vector2(float(values[0]), float(values[1]))
	return Vector2.ZERO


func _canonical_json(value: Variant) -> String:
	return JSON.stringify(_canonical_value(value), "", true, true)


func _canonical_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var dictionary_result := {}
			for key_value: Variant in (value as Dictionary).keys():
				dictionary_result[str(key_value)] = _canonical_value((value as Dictionary)[key_value])
			return dictionary_result
		TYPE_ARRAY:
			var array_result := []
			for child_value: Variant in value as Array:
				array_result.append(_canonical_value(child_value))
			return array_result
		TYPE_FLOAT:
			var number := float(value)
			return int(number) if is_finite(number) and number == floor(number) else number
		_:
			return value


func _set_power_pattern(controller, target_positions: Array) -> void:
	var current_positions := controller.state_snapshot().get("lever_positions", {}) as Dictionary
	for lever_index: int in range(EXPECTED_LEVER_IDS.size()):
		var lever_id := str(EXPECTED_LEVER_IDS[lever_index])
		var target_position := str(target_positions[lever_index])
		if str(current_positions.get(lever_id, "up")) == target_position:
			continue
		var result: Dictionary = controller.activate_power_lever(lever_id)
		_assert(bool(result.get("success", false)), "Dźwignia %s musi przełączyć się przez publiczne API." % lever_id)
		current_positions[lever_id] = target_position


func _positions(first: String, second: String, third: String) -> Dictionary:
	return {"a_lever_1": first, "a_lever_2": second, "a_lever_3": third}


func _all_groups_have_state(controller, expected_open: bool) -> bool:
	for group_id: String in EXPECTED_GROUP_IDS:
		if controller.barrier_group_is_open(group_id) != expected_open:
			return false
	return true


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("Tower package contract test passed.")
	quit(0)
