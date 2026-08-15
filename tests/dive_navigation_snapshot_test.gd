extends SceneTree


const ContinuousMapScript := preload("res://scripts/diving/UnderwaterMapRuntime.gd")
const NavigationSnapshotScript := preload("res://scripts/diving/DiveNavigationSnapshot.gd")
const DiveScoutRuntimeScript := preload("res://scripts/diving/DiveScoutRuntime.gd")
const PersistentInteractableScript := preload("res://scripts/diving/DivePersistentInteractable.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")


var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dive_map = ContinuousMapScript.new()
	root.add_child(dive_map)
	await process_frame
	await physics_frame

	var snapshot = dive_map.navigation_snapshot()
	_assert(snapshot != null and snapshot.is_valid(), "Migawka nawigacji musi mieć kompletną siatkę runtime.")
	_assert(snapshot.world_size == dive_map.world_size(), "Migawka musi zachować kanoniczny rozmiar świata.")
	_assert(snapshot.grid_size == Vector2i(1440, 810), "Migawka musi kopiować pełną siatkę PNG 1440 x 810.")
	_assert(snapshot.cell_scale == Vector2(8.0, 8.0), "Migawka musi zachować skalę 8 x 8 jednostek na komórkę.")
	_assert(is_equal_approx(snapshot.clearance_world, 35.0), "Domyślna erozja musi obejmować obracaną kapsułę nurka.")
	_assert(snapshot.start_position == dive_map.start_position(), "Migawka musi publikować finalną pozycję startu.")
	_assert(snapshot.exit_position == dive_map.exit_line.global_position, "Migawka musi publikować finalną pozycję aktywnej liny.")
	_assert(snapshot.open_cells.size() == 1440 * 810, "Migawka musi kopiować każdą surową komórkę kolizji.")
	_assert(snapshot.clear_cells.size() == snapshot.open_cells.size(), "Maska po erozji musi odpowiadać rozmiarem siatce źródłowej.")
	_assert(snapshot.is_position_open(snapshot.start_position) == dive_map.is_world_position_navigable(snapshot.start_position), "Surowa migawka i runtime muszą identycznie klasyfikować start.")
	_assert(snapshot.is_position_open(Vector2.ZERO) == dive_map.is_world_position_navigable(Vector2.ZERO), "Surowa migawka i runtime muszą identycznie klasyfikować czarny narożnik.")
	_assert(snapshot.is_cell_in_bounds(snapshot.world_to_cell(snapshot.start_position)), "Pozycja startu musi mapować się do komórki świata.")
	_assert(snapshot.cell_center(Vector2i(0, 0)) == Vector2(4.0, 4.0), "Helper cell_center musi zwracać środek pierwszej komórki.")
	_assert(not snapshot.is_cell_open(Vector2i(-1, 0)), "Komórka poza siatką musi być zamknięta.")

	_assert(snapshot.current_zones.size() == 3, "Migawka musi kopiować wszystkie trzy strefy prądów fixture świata.")
	for zone in snapshot.current_zones:
		var rect: Rect2 = zone.get("rect", Rect2())
		var sample_position := rect.get_center()
		_assert(snapshot.current_at(sample_position) == dive_map.current_at(sample_position), "Migawka musi zachować kierunkowy wektor prądu.")
	for sample_position in [snapshot.start_position, snapshot.exit_position, snapshot.world_size * 0.5]:
		_assert(is_equal_approx(snapshot.depth_at(sample_position), dive_map.depth_at(sample_position)), "Migawka musi odtwarzać ten sam profil głębokości co świat.")

	_validate_target_descriptors(dive_map, snapshot)
	_validate_closed_shortcuts(dive_map, snapshot)
	_validate_conservative_geometry()
	_validate_scout_signal_contract()

	var raw_start_cell := snapshot.world_to_cell(snapshot.start_position)
	var raw_start_index: int = raw_start_cell.y * snapshot.grid_size.x + raw_start_cell.x
	var runtime_start_open := dive_map.is_world_position_navigable(snapshot.start_position)
	snapshot.open_cells[raw_start_index] = 0 if snapshot.open_cells[raw_start_index] == 1 else 1
	_assert(dive_map.is_world_position_navigable(snapshot.start_position) == runtime_start_open, "Zmiana kopii siatki nie może mutować ContinuousDiveWorld.")
	_validate_buoy_entry_snapshot(dive_map)

	dive_map.queue_free()
	if _failed:
		quit(1)
		return
	print("Dive navigation snapshot test passed: copied grid, conservative capsule, gates, segments, currents, depth and resolved target semantics.")
	quit(0)


func _validate_target_descriptors(dive_map, snapshot) -> void:
	var descriptors: Array[Dictionary] = snapshot.target_descriptors()
	var expected_count: int = (
		dive_map.containers.size()
		+ dive_map.world_pickups.size()
		+ dive_map.rescue_survivors.size()
		+ dive_map.persistent_interactables.size()
	)
	_assert(descriptors.size() == expected_count, "Migawka musi publikować każdy finalny cel runtime dokładnie raz.")
	var descriptor_lookup: Dictionary = {}
	for descriptor in descriptors:
		var descriptor_id := str(descriptor.get("id", ""))
		_assert(not descriptor_id.is_empty(), "Każdy cel snapshotu musi mieć stabilne ID.")
		_assert(not descriptor_lookup.has(descriptor_id), "ID celu snapshotu nie może się powtarzać: %s." % descriptor_id)
		descriptor_lookup[descriptor_id] = descriptor
		_assert(descriptor.get("position", null) is Vector2, "Każdy cel musi publikować finalną pozycję świata: %s." % descriptor_id)
		_assert(descriptor.get("requested_position", null) is Vector2, "Każdy cel musi publikować pozycję autorską sprzed resolvera: %s." % descriptor_id)

	for container in dive_map.containers:
		var descriptor: Dictionary = descriptor_lookup.get(container.container_id, {})
		_assert(str(descriptor.get("kind", "")) == "container", "Kontener musi zachować rodzaj celu: %s." % container.container_id)
		_assert(descriptor.get("position", Vector2(-999999.0, -999999.0)) == container.global_position, "Kontener musi publikować pozycję po resolverze: %s." % container.container_id)
		_assert(descriptor.get("contents", {}) == container.contents, "Kontener musi publikować bieżącą, możliwą do zabrania zawartość: %s." % container.container_id)
		_assert(bool(descriptor.get("mandatory", false)) == (container.mandatory_order >= 0), "Kontener musi publikować semantykę obowiązkowego celu: %s." % container.container_id)
		_assert(str(descriptor.get("required_tool", "")) == container.required_tool, "Kontener musi publikować wymagane narzędzie: %s." % container.container_id)
		_assert(str(descriptor.get("interaction_action", "")) == container.interaction_action, "Kontener musi publikować akcję interakcji: %s." % container.container_id)
		_assert(is_equal_approx(float(descriptor.get("interaction_seconds", 0.0)), container.interaction_seconds), "Kontener musi publikować pełny czas interakcji: %s." % container.container_id)

	for pickup in dive_map.world_pickups:
		var descriptor: Dictionary = descriptor_lookup.get(pickup.pickup_id, {})
		_assert(str(descriptor.get("kind", "")) == "pickup", "Pickup musi zachować rodzaj celu: %s." % pickup.pickup_id)
		_assert(descriptor.get("position", Vector2(-999999.0, -999999.0)) == pickup.global_position, "Pickup musi publikować pozycję po resolverze: %s." % pickup.pickup_id)
		_assert(descriptor.get("contents", {}) == {pickup.resource_id: 1}, "Pickup musi gwarantować dokładnie jedną pełną sztukę: %s." % pickup.pickup_id)
		_assert(bool(descriptor.get("full_pickup", false)), "Pickup musi być oznaczony jako niepodzielny cel: %s." % pickup.pickup_id)

	for rescue_survivor in dive_map.rescue_survivors:
		var descriptor: Dictionary = descriptor_lookup.get(rescue_survivor.encounter_id, {})
		_assert(str(descriptor.get("kind", "")) == "rescue", "Spotkanie ratunkowe musi zachować rodzaj celu.")
		_assert(descriptor.get("position", Vector2(-999999.0, -999999.0)) == rescue_survivor.global_position, "Ratunek musi publikować finalną pozycję.")
		_assert(descriptor.get("definition", null) != null, "Ratunek musi publikować odseparowaną definicję kosztów holowania.")
		_assert(str(descriptor.get("required_tool", "")) == rescue_survivor.required_tool, "Ratunek musi publikować wymagane narzędzie.")
		_assert(is_equal_approx(float(descriptor.get("interaction_seconds", 0.0)), rescue_survivor.interaction_seconds), "Ratunek musi publikować czas uwolnienia.")

	for interactable in dive_map.persistent_interactables:
		var descriptor: Dictionary = descriptor_lookup.get(interactable.persistent_id, {})
		_assert(str(descriptor.get("kind", "")) == "persistent_objective", "Trwały punkt musi zachować rodzaj gwarantowanego celu: %s." % interactable.persistent_id)
		_assert(descriptor.get("position", Vector2(-999999.0, -999999.0)) == interactable.global_position, "Trwały punkt musi publikować finalną pozycję: %s." % interactable.persistent_id)
		_assert(bool(descriptor.get("completed", false)) == interactable.completed, "Trwały punkt musi publikować stan ukończenia: %s." % interactable.persistent_id)
		if interactable.kind == PersistentInteractableScript.Kind.SHORTCUT:
			var obstacle: Dictionary = descriptor.get("obstacle", {})
			_assert(not obstacle.is_empty(), "Skrót musi publikować rzeczywistą geometrię przeszkody: %s." % interactable.persistent_id)
			_assert(obstacle.get("size", Vector2.ZERO) == Vector2(interactable.gate_width, 28.0), "Skrót musi publikować rozmiar RectangleShape2D: %s." % interactable.persistent_id)

	var copied_descriptors: Array[Dictionary] = snapshot.target_descriptors()
	if not copied_descriptors.is_empty():
		var original_position: Vector2 = snapshot.targets[0].get("position", Vector2.ZERO)
		copied_descriptors[0]["position"] = original_position + Vector2(999.0, 999.0)
		_assert(snapshot.targets[0].get("position", Vector2.ZERO) == original_position, "target_descriptors() musi zwracać głęboką kopię snapshotu.")

	var threat_descriptors: Array[Dictionary] = snapshot.threat_descriptors()
	_assert(threat_descriptors.size() == dive_map.threats.size(), "Migawka musi publikować finalne pozycje wszystkich aktywnych zagrożeń.")
	for threat in dive_map.threats:
		var found := false
		for descriptor in threat_descriptors:
			if str(descriptor.get("id", "")) == str(threat.get("threat_id")):
				found = descriptor.get("position", Vector2(-999999.0, -999999.0)) == threat.global_position and descriptor.get("definition", null) != null
				break
		_assert(found, "Zagrożenie musi zachować finalną pozycję i definicję: %s." % str(threat.get("threat_id")))


func _validate_closed_shortcuts(dive_map, snapshot) -> void:
	var closed_shortcut = null
	var expected_closed_count := 0
	for interactable in dive_map.persistent_interactables:
		if interactable.kind != PersistentInteractableScript.Kind.SHORTCUT or interactable.completed:
			continue
		expected_closed_count += 1
		if closed_shortcut == null:
			closed_shortcut = interactable
	_assert(snapshot.closed_shortcut_gates.size() == expected_closed_count, "Migawka musi zawierać każdą aktywną zamkniętą bramę.")
	for gate in snapshot.closed_shortcut_gates:
		_assert(bool(gate.get("active", false)), "Lista zamkniętych bram nie może zawierać nieaktywnego collidera.")
		_assert(gate.get("size", Vector2.ZERO).y == 28.0, "Migawka musi czytać wysokość rzeczywistego RectangleShape2D.")
		_assert(not snapshot.is_position_clear(gate.get("position", Vector2.ZERO)), "Środek aktywnej bramy musi być wyłączony z maski przejścia.")

	_assert(closed_shortcut != null, "Fixture świata musi zawierać co najmniej jeden zamknięty skrót.")
	if closed_shortcut == null:
		return
	closed_shortcut.mark_completed()
	var opened_snapshot = dive_map.navigation_snapshot()
	_assert(opened_snapshot.closed_shortcut_gates.size() == expected_closed_count - 1, "Snapshot po otwarciu skrótu musi usunąć wyłączony collider.")
	var opened_descriptor := _find_descriptor(opened_snapshot.targets, closed_shortcut.persistent_id)
	_assert(bool(opened_descriptor.get("completed", false)), "Cel skrótu musi odzwierciedlać lokalne otwarcie sesji.")
	_assert(not bool(opened_descriptor.get("is_obstacle", true)), "Otwarty skrót nie może pozostać aktywną przeszkodą snapshotu.")
	closed_shortcut.reset_attempt()


func _validate_conservative_geometry() -> void:
	var grid_size := Vector2i(21, 21)
	var cell_scale := Vector2(10.0, 10.0)
	var world_size := Vector2(
		float(grid_size.x) * cell_scale.x,
		float(grid_size.y) * cell_scale.y
	)
	var all_open := PackedByteArray()
	all_open.resize(grid_size.x * grid_size.y)
	all_open.fill(1)

	var static_cells := all_open.duplicate()
	static_cells[10 * grid_size.x + 10] = 0
	var static_snapshot = NavigationSnapshotScript.new()
	static_snapshot.configure(
		world_size,
		grid_size,
		cell_scale,
		static_cells,
		35.0,
		Vector2.ZERO,
		Vector2.ZERO,
		[],
		[],
		[],
		[]
	)
	_assert(static_snapshot.is_cell_open(Vector2i(14, 10)), "Komórka obok ściany musi pozostać surowo otwarta.")
	_assert(not static_snapshot.is_cell_clear(Vector2i(14, 10)), "Erozja musi odsunąć obracaną kapsułę 35 jednostek od ściany.")
	_assert(static_snapshot.is_cell_clear(Vector2i(15, 10)), "Komórka poza konserwatywnym promieniem ściany powinna pozostać dostępna.")

	var gate_transform := Transform2D(0.0, Vector2(105.0, 105.0))
	var gate_descriptor := {
		"id": "synthetic_gate",
		"transform": gate_transform,
		"position": gate_transform.origin,
		"rotation": 0.0,
		"size": Vector2(20.0, 4.0),
		"active": true,
	}
	var open_snapshot = NavigationSnapshotScript.new()
	open_snapshot.configure(
		world_size,
		grid_size,
		cell_scale,
		all_open,
		35.0,
		Vector2.ZERO,
		Vector2.ZERO,
		[],
		[],
		[],
		[]
	)
	var gated_snapshot = NavigationSnapshotScript.new()
	gated_snapshot.configure(
		world_size,
		grid_size,
		cell_scale,
		all_open,
		35.0,
		Vector2.ZERO,
		Vector2.ZERO,
		[],
		[],
		[gate_descriptor],
		[]
	)
	var segment_start := Vector2(45.0, 105.0)
	var segment_end := Vector2(165.0, 105.0)
	_assert(open_snapshot.is_position_clear(gate_transform.origin), "Bez bramy środek syntetycznego korytarza musi być dostępny.")
	_assert(not gated_snapshot.is_position_clear(gate_transform.origin), "Aktywna brama musi zablokować własny środek.")
	_assert(open_snapshot.is_segment_clear(segment_start, segment_end), "Helper segmentu musi zaakceptować prostą trasę w otwartej wodzie.")
	_assert(not gated_snapshot.is_segment_clear(segment_start, segment_end), "Helper segmentu musi odrzucić przejście przez aktywną bramę.")


func _validate_scout_signal_contract() -> void:
	var threat_records := [
		{"id": "threat_b", "position": Vector2(100.0, 0.0)},
		{"id": "threat_a", "position": Vector2(100.0, 0.0)},
		{"id": "defeated", "position": Vector2(10.0, 0.0), "defeated": true},
	]
	var current_records := [
		{"id": "current_tie", "rect": Rect2(100.0, -10.0, 40.0, 20.0), "velocity": Vector2(60.0, 0.0)},
		{"id": "current_weak", "rect": Rect2(20.0, -10.0, 10.0, 20.0), "velocity": Vector2(59.9, 0.0)},
	]
	var threat_signal := NavigationSnapshotScript.scout_signal_for_records(
		Vector2.ZERO,
		threat_records,
		current_records,
		640.0,
		60.0
	)
	_assert(
		str(threat_signal.get("kind", "")) == "threat" and str(threat_signal.get("id", "")) == "threat_a",
		"Zwiadowca musi przy remisie wybrać zagrożenie przed prądem, a następnie stabilne najniższe ID."
	)
	var current_signal := NavigationSnapshotScript.scout_signal_for_records(
		Vector2.ZERO,
		[],
		current_records,
		640.0,
		60.0
	)
	_assert(
		str(current_signal.get("kind", "")) == "current" and str(current_signal.get("id", "")) == "current_tie",
		"Zwiadowca musi wskazać krawędź silnej strefy prądu i ignorować próg poniżej 60."
	)
	var containing_current := NavigationSnapshotScript.scout_signal_for_records(
		Vector2(110.0, 0.0),
		[],
		current_records,
		640.0,
		60.0
	)
	_assert(containing_current.is_empty(), "Strefa prądu zawierająca nurka nie może dublować bieżącego wskaźnika HUD.")
	var out_of_range := NavigationSnapshotScript.scout_signal_for_records(
		Vector2.ZERO,
		[{"id": "far", "position": Vector2(640.01, 0.0)}],
		[],
		640.0,
		60.0
	)
	_assert(out_of_range.is_empty(), "Zwiadowca nie może ujawniać sygnału poza promieniem 640 jednostek.")
	var zero_direction_signal := NavigationSnapshotScript.scout_signal_for_records(
		Vector2.ZERO,
		[{"id": "overlapping", "position": Vector2.ZERO}],
		[],
		640.0,
		60.0
	)
	_assert(zero_direction_signal.is_empty(), "Zwiadowca nie może zwrócić dziewiątego, bezkierunkowego znaku dla nakładającego się obiektu.")

	var scout_runtime = DiveScoutRuntimeScript.new()
	var synthetic_query := func() -> Dictionary:
		return {"kind": "threat", "id": "timed", "direction": Vector2.RIGHT, "distance": 20.0}
	_assert(scout_runtime.advance(true, 1.49, synthetic_query).is_empty(), "Zwiadowca nie może ujawnić sygnału po 1,49 s bezruchu.")
	_assert(not scout_runtime.advance(true, 0.01, synthetic_query).is_empty(), "Zwiadowca musi ujawnić sygnał dokładnie po 1,50 s bezruchu.")
	_assert(scout_runtime.advance(false, 0.01, synthetic_query).is_empty(), "Ruch, światło lub akcja muszą natychmiast wyczyścić sygnał Zwiadowcy.")
	_assert(scout_runtime.advance(true, 1.49, synthetic_query).is_empty(), "Po przerwaniu licznik Zwiadowcy musi zaczynać pełne 1,50 s od początku.")


func _validate_buoy_entry_snapshot(dive_map) -> void:
	var world = dive_map._world_state
	if not world.placed_buoys.has("B-01"):
		world.placed_buoys.append("B-01")
	var setup = ExpeditionSetupScript.new()
	setup.start_entry_point = "R2-02"
	setup.base_support_level = 4
	dive_map.configure(world, setup.start_entry_point, setup)
	var buoy: Dictionary = _find_buoy_record(world.blueprint.buoy_spawns, "B-01")
	var expected_start: Vector2 = dive_map.nearest_navigable_position(
		buoy.get("position", Vector2.ZERO),
		NavigationSnapshotScript.DEFAULT_DIVER_CLEARANCE
	)
	var buoy_snapshot = dive_map.navigation_snapshot()
	_assert(dive_map.active_sector_id == "R2-02", "Runtime musi rozwinąć start_entry_point do kanonicznego landmarku boi.")
	_assert(dive_map.start_position() == expected_start, "Runtime musi materializować start przy fizycznej kotwicy boi wybranej przez start_entry_point.")
	_assert(dive_map.exit_line.global_position == buoy.get("position", Vector2.ZERO), "Runtime musi materializować linię przy kotwicy aktywnej boi.")
	_assert(dive_map.start_position().distance_to(dive_map.exit_line.global_position) <= 1.0, "Start z boi musi leżeć bezpośrednio przy aktywnej linie.")
	_assert(buoy_snapshot.start_position == expected_start, "Snapshot musi publikować finalny start wejścia z boi.")
	_assert(buoy_snapshot.exit_position == buoy.get("position", Vector2.ZERO), "Snapshot musi publikować finalną linię przy aktywnej boi.")


func _find_buoy_record(records: Array[Dictionary], buoy_id: String) -> Dictionary:
	for record in records:
		if str(record.get("id", "")) == buoy_id:
			return record
	return {}


func _find_descriptor(descriptors: Array[Dictionary], descriptor_id: String) -> Dictionary:
	for descriptor in descriptors:
		if str(descriptor.get("id", "")) == descriptor_id:
			return descriptor
	return {}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
