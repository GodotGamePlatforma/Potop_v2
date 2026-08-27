extends SceneTree

const PACKAGE_MANIFEST_PATH := "res://underwater_map_workbench/structures/tower_three_inlets_02/structure_manifest.json"
const PACKAGE_MANIFEST_RELATIVE_PATH := "structures/tower_three_inlets_02/structure_manifest.json"
const PACKAGE_RELATIVE_PREFIX := "structures/tower_three_inlets_02/"
const PACKAGE_ROOT := "res://underwater_map_workbench/structures/tower_three_inlets_02/"
const GENERATED_TRUTH_PATH := PACKAGE_ROOT + "generated/structure_truth.json"
const GENERATED_SCENE_PATH := PACKAGE_ROOT + "generated/structure.tscn"
const STRUCTURE_ID := "tower_three_inlets_02"
const STRUCTURE_SIZE := Vector2i(2400, 3840)
const COLLISION_RASTER_SIZE := Vector2i(60, 96)
const GRID_WORLD_UNITS := 40
const EXPECTED_CONTROL_IDS := ["panel_a", "inlet_b", "inlet_c", "d_v1", "d_v2", "d_reset", "inlet_d"]
const EXPECTED_BARRIER_IDS := ["g1", "c_shortcut", "g2", "h3", "facade"]
const FORBIDDEN_AUTHORITY_KEYS := [
	"origin",
	"world_origin",
	"world_rect",
	"map_manifest",
	"landmark",
	"campaign",
	"checkpoint_id",
	"persistent_id",
]

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var package_manifest := _load_json(PACKAGE_MANIFEST_PATH, "manifest pakietu")
	if package_manifest.is_empty():
		_finish()
		return
	_verify_package_shape(package_manifest)
	_verify_no_second_authority(package_manifest)
	_verify_declared_files(package_manifest)
	var collision := _resolved_collision(package_manifest)
	_verify_collision(package_manifest, collision)
	_verify_sockets(package_manifest)
	_verify_runtime_contract(package_manifest)
	_verify_visual_assets(package_manifest)
	_verify_generated_truth(package_manifest)
	_finish()


func _verify_package_shape(package_manifest: Dictionary) -> void:
	_assert(int(package_manifest.get("schema_version", 0)) == 1, "Pakiet W02 musi używać schema_version 1.")
	_assert(str(package_manifest.get("format", "")) == "enterable_structure_package_v1", "Pakiet W02 musi używać enterable_structure_package_v1.")
	_assert(_vector2i(package_manifest.get("size", [])) == STRUCTURE_SIZE, "Pakiet W02 musi mieć lokalny rozmiar 2400x3840.")
	var template := package_manifest.get("template", {}) as Dictionary
	_assert(not str(template.get("id", "")).is_empty(), "Pakiet W02 musi wskazywać lokalny template.id.")
	_assert(str(template.get("kind", "")) == "enterable_tower", "Template W02 musi być wieżowcem, do którego można wpłynąć.")
	var attempt_state := package_manifest.get("attempt_state", {}) as Dictionary
	_assert(
		attempt_state == {
			"persistence": "none",
			"checkpoint": "none",
			"reset": "whole_structure_attempt",
		},
		"W02 musi jawnie wyłączać persistence/checkpoint i resetować całą próbę.",
	)
	_assert(str(package_manifest.get("local_topology_digest", "")).begins_with("structure-topology-v1:"), "Pakiet musi publikować kanoniczny local_topology_digest.")


func _verify_no_second_authority(package_manifest: Dictionary) -> void:
	_assert(not _contains_any_key(package_manifest, FORBIDDEN_AUTHORITY_KEYS), "Prywatny pakiet nie może kopiować originu, landmarku, kampanii ani trwałego ID.")
	for forbidden_path: String in ["map_manifest.json", "project.godot", "UnderwaterMap.tscn", ".ai/PROJECT_CONTEXT.md", ".ai/DECISIONS.md"]:
		_assert(not FileAccess.file_exists(PACKAGE_ROOT + forbidden_path), "Pakiet nie może tworzyć drugiego authority: %s." % forbidden_path)
	for reference_value: Variant in package_manifest.get("references", []) as Array:
		var reference := reference_value as Dictionary
		_assert(reference.get("authority", true) == false, "Materiał provenance musi mieć authority=false: %s." % str(reference.get("path", "?")))
	_assert(not _contains_any_key(package_manifest.get("runtime", {}), ["persistence", "checkpoint", "persistent_id"]), "Runtime W02 nie może zawierać persistence, checkpointu ani persistent_id.")


func _verify_declared_files(package_manifest: Dictionary) -> void:
	var script_roles := {}
	var script_paths := {}
	for script_value: Variant in package_manifest.get("scripts", []) as Array:
		var script_record := script_value as Dictionary
		var role := str(script_record.get("role", ""))
		_assert(not role.is_empty() and not script_roles.has(role), "Każda rola skryptu musi być lokalna i unikalna.")
		script_roles[role] = true
		var relative_path := str(script_record.get("path", ""))
		_assert(relative_path.begins_with("scripts/") and _is_safe_relative_path(relative_path), "Skrypt musi pozostać pod scripts/: %s." % relative_path)
		_assert(not script_paths.has(relative_path), "Każda rola skryptu musi wskazywać unikalny plik: %s." % relative_path)
		script_paths[relative_path] = true
		_verify_file_hash(relative_path, str(script_record.get("sha256", "")), "skrypt")
		var source_file := FileAccess.open(PACKAGE_ROOT + relative_path, FileAccess.READ)
		if source_file != null:
			_assert(not _declares_global_class(source_file.get_as_text()), "Prywatny skrypt nie może publikować class_name: %s." % relative_path)
	_assert(
		_sorted_copy(script_roles.keys()) == _sorted_copy(["controller", "interactable", "moving_body"]),
		"Pakiet W02 musi hash-pinować dokładnie role controller, interactable i moving_body.",
	)

	for reference_value: Variant in package_manifest.get("references", []) as Array:
		var reference := reference_value as Dictionary
		var relative_path := str(reference.get("path", ""))
		_assert(relative_path.begins_with("references/") and _is_safe_relative_path(relative_path), "Provenance musi pozostać pod references/: %s." % relative_path)
		_verify_file_hash(relative_path, str(reference.get("sha256", "")), "provenance")


func _resolved_collision(package_manifest: Dictionary) -> Dictionary:
	var collision := package_manifest.get("collision", {}) as Dictionary
	var source_value: Variant = collision.get("source", null)
	if source_value is Dictionary:
		var source := source_value as Dictionary
		var source_path := str(source.get("path", ""))
		_assert(_is_safe_relative_path(source_path), "Payload kolizji musi być lokalnym plikiem względnym.")
		_verify_file_hash(source_path, str(source.get("sha256", "")), "payload kolizji")
		var payload := _load_json(PACKAGE_ROOT + source_path, "payload kolizji")
		for mirrored_key: String in ["format", "base", "pixel_size", "world_units_per_pixel"]:
			if collision.has(mirrored_key) and payload.has(mirrored_key):
				_assert(_canonical_json(collision[mirrored_key]) == _canonical_json(payload[mirrored_key]), "collision.%s musi odpowiadać payloadowi." % mirrored_key)
		return payload
	return collision


func _verify_collision(package_manifest: Dictionary, collision: Dictionary) -> void:
	_assert(not collision.is_empty(), "Pakiet W02 musi publikować lokalne źródło kolizji.")
	_assert(str(collision.get("format", "")) == "l05_structure_rect_ops_v1", "Kolizja W02 musi używać l05_structure_rect_ops_v1.")
	_assert(str(collision.get("base", "")) == "open_water", "Payload W02 musi zaczynać się od open_water i jawnie nałożyć prefiksowany solid shell.")
	_assert(_vector2i(collision.get("pixel_size", [])) == COLLISION_RASTER_SIZE, "Raster kolizji W02 musi mieć dokładnie 60x96.")
	_assert(_vector2i(collision.get("world_units_per_pixel", [])) == Vector2i(GRID_WORLD_UNITS, GRID_WORLD_UNITS), "Jedna komórka rastra musi odpowiadać 40x40 jednostkom świata.")
	var operations := collision.get("operations", []) as Array
	_assert(not operations.is_empty(), "Payload kolizji W02 musi zawierać lokalne operacje.")
	if operations.is_empty():
		return
	var first_operation := operations[0] as Dictionary
	_assert(
		str(first_operation.get("id", "")) == STRUCTURE_ID + "_shell"
		and str(first_operation.get("op", "")) == "solid_rect"
		and _rect2i(first_operation.get("rect_px", [])) == Rect2i(Vector2i.ZERO, COLLISION_RASTER_SIZE),
		"Pierwszą operacją authority musi być pełny solid shell 60x96.",
	)
	var ids := {}
	for operation_value: Variant in operations:
		var operation := operation_value as Dictionary
		var operation_id := str(operation.get("id", ""))
		_assert(operation_id.begins_with(STRUCTURE_ID + "_"), "ID operacji kolizji musi być prefiksowane stable ID pakietu: %s." % operation_id)
		_assert(not ids.has(operation_id), "ID operacji kolizji musi być unikalne: %s." % operation_id)
		ids[operation_id] = true
		_assert(str(operation.get("op", "")) in ["solid_rect", "open_rect"], "Operacja %s ma nieobsługiwany typ." % operation_id)
		var rect := _rect2i(operation.get("rect_px", []))
		_assert(rect.size.x > 0 and rect.size.y > 0, "Operacja %s musi mieć dodatni rect_px." % operation_id)
		_assert(_rect_inside(rect, Rect2i(Vector2i.ZERO, COLLISION_RASTER_SIZE)), "Operacja %s wychodzi poza lokalny raster 60x96." % operation_id)
	var cells := _collision_cells(collision)
	var digest_payload := {
		"pixel_size": [COLLISION_RASTER_SIZE.x, COLLISION_RASTER_SIZE.y],
		"world_units_per_pixel": [GRID_WORLD_UNITS, GRID_WORLD_UNITS],
		"encoding": {"solid": 0, "open_water": 255},
		"cells_hex": cells.hex_encode(),
	}
	var calculated_digest := "structure-topology-v1:%s" % _canonical_json(digest_payload).sha256_text()
	_assert(
		str(package_manifest.get("local_topology_digest", "")) == calculated_digest,
		"local_topology_digest musi odpowiadać zdekodowanej lokalnej geometrii.",
	)
	_verify_staged_reachability(package_manifest, cells)


func _verify_sockets(package_manifest: Dictionary) -> void:
	var sockets := package_manifest.get("sockets", []) as Array
	_assert(not sockets.is_empty(), "Pakiet W02 musi publikować sockety.")
	_assert(_count_records_by_value(sockets, "kind", "entry_opening") == 1, "W02 musi mieć dokładnie jedno wejście gracza.")
	_assert(_count_records_by_value(sockets, "kind", "building_egress") == 1, "W02 musi mieć dokładnie jedno wyjście z budynku.")
	var socket_ids := {}
	for socket_value: Variant in sockets:
		var socket := socket_value as Dictionary
		var socket_id := str(socket.get("id", ""))
		_assert(not socket_id.is_empty() and not socket_ids.has(socket_id), "Socket IDs muszą być niepuste i lokalnie unikalne: %s." % socket_id)
		socket_ids[socket_id] = true
		var rect := _rect2i(socket.get("local_rect", []))
		_assert(rect.size.x > 0 and rect.size.y > 0, "Socket %s musi mieć dodatni local_rect." % socket_id)
		_assert(_rect_inside(rect, Rect2i(Vector2i.ZERO, STRUCTURE_SIZE)), "Socket %s wychodzi poza 2400x3840." % socket_id)
		_assert(_rect_is_grid_aligned(rect, GRID_WORLD_UNITS), "Socket %s musi leżeć na lokalnej siatce 40 jednostek." % socket_id)


func _verify_runtime_contract(package_manifest: Dictionary) -> void:
	var runtime := package_manifest.get("runtime", {}) as Dictionary
	_assert(str(runtime.get("contract", "")) == "three_inlets_tower_sequence_v1", "Runtime W02 musi używać kontraktu three_inlets_tower_sequence_v1.")
	_assert(str(runtime.get("egress_socket_id", "")).length() > 0, "Runtime musi wskazać jedno egress_socket_id.")
	var interactives := runtime.get("interactives", []) as Array
	_assert(_sorted_ids(interactives) == _sorted_copy(EXPECTED_CONTROL_IDS), "Runtime musi publikować dokładnie siedem uzgodnionych controls.")
	var panel := _record_by_id(interactives, "panel_a")
	_assert(str(panel.get("kind", "")) == "status_panel", "Panel A musi być read-only status_panel.")
	_assert(str(panel.get("interaction_action", "")) in ["inspect", "inspect_status", "read"], "Panel A nie może być przełącznikiem ani dźwignią.")
	var expected_order := {"inlet_b": 0, "inlet_c": 1, "inlet_d": 2}
	for control_id: String in expected_order:
		var control := _record_by_id(interactives, control_id)
		_assert(int(control.get("stage", -1)) == int(expected_order[control_id]), "B, C i D muszą deklarować kolejność etapów 0→1→2: %s." % control_id)
	for d_id: String in ["d_v1", "d_v2", "d_reset", "inlet_d"]:
		_assert(not _record_by_id(interactives, d_id).is_empty(), "Automat D wymaga control %s." % d_id)

	var barriers := runtime.get("barriers", []) as Array
	_assert(_sorted_ids(barriers) == _sorted_copy(EXPECTED_BARRIER_IDS), "W02 musi mieć dokładnie dynamiczne bariery g1/c_shortcut/g2/h3/facade.")
	var egress_socket_id := str(runtime.get("egress_socket_id", ""))
	var egress_socket := _record_by_id(package_manifest.get("sockets", []) as Array, egress_socket_id)
	var egress_rect := _rect2i(egress_socket.get("local_rect", []))
	var egress_visual_barriers: Array[Dictionary] = []
	for barrier_value: Variant in barriers:
		var barrier := barrier_value as Dictionary
		_assert(float(barrier.get("travel_speed", 0.0)) > 0.0, "Bariera %s musi mieć dodatnią prędkość ruchu." % str(barrier.get("id", "?")))
		_assert(not str(barrier.get("socket_id", "")).is_empty(), "Bariera %s musi wskazywać socket." % str(barrier.get("id", "?")))
		_assert(_vector2(barrier.get("open_offset", [])).length() > 0.0, "Bariera %s musi mieć rzeczywisty open_offset." % str(barrier.get("id", "?")))
		_assert(str(_record_by_id(package_manifest.get("sockets", []) as Array, str(barrier.get("socket_id", ""))).get("kind", "")) == "dynamic_door", "Bariera %s musi wiązać się z socketem dynamic_door." % str(barrier.get("id", "?")))
		_assert(not barrier.has("visual_style"), "Czysto prezentacyjny styl bariery nie może zmieniać runtime ani gameplay signature.")
		var barrier_socket := _record_by_id(package_manifest.get("sockets", []) as Array, str(barrier.get("socket_id", "")))
		if (
			str(barrier_socket.get("kind", "")) == "dynamic_door"
			and _rect2i(barrier_socket.get("local_rect", [])) == egress_rect
		):
			egress_visual_barriers.append(barrier)

	_assert(egress_visual_barriers.size() == 1, "Dokładnie jedna bariera dynamic_door musi pokrywać typowany building_egress i otrzymać prezentację egress_grille.")
	if egress_visual_barriers.size() == 1:
		var egress_barrier := egress_visual_barriers[0]
		var barrier_socket := _record_by_id(package_manifest.get("sockets", []) as Array, str(egress_barrier.get("socket_id", "")))
		var closed_rect := _rect2i(barrier_socket.get("local_rect", []))
		var open_offset := _vector2i(egress_barrier.get("open_offset", []))
		var open_rect := Rect2i(closed_rect.position + open_offset, closed_rect.size)
		_assert(closed_rect == egress_rect, "Relacja dynamic_door→building_egress musi typować egress_grille bez zależności od ID, socketu, label ani symbolu.")
		_assert((open_offset.x == 0) != (open_offset.y == 0), "egress_grille musi otwierać się wzdłuż dokładnie jednej osi.")
		_assert(not open_rect.intersects(egress_rect), "Pozycja OPEN egress_grille musi całkowicie opuścić prostokąt przejścia.")

	var cabinet := runtime.get("cabinet", {}) as Dictionary
	_assert(str(cabinet.get("id", "")) == "cabinet_d", "Automat D musi sterować cabinet_d.")
	_assert(str(_record_by_id(package_manifest.get("sockets", []) as Array, str(cabinet.get("socket_id", ""))).get("kind", "")) == "moving_obstacle", "cabinet_d musi wiązać się z socketem moving_obstacle.")
	_assert(float(cabinet.get("travel_speed", 0.0)) > 0.0, "cabinet_d musi mieć dodatnią prędkość ruchu.")
	_assert(_vector2(cabinet.get("move_right", [])).x > 0.0, "Pierwszy krok D musi przesuwać cabinet_d w prawo.")
	_assert(_vector2(cabinet.get("move_down", [])).y > 0.0, "Drugi krok D musi przesuwać cabinet_d w dół.")

	var currents := runtime.get("currents", {}) as Dictionary
	var central := currents.get("central_shaft", {}) as Dictionary
	_assert(_vector2(central.get("velocity", [])).length() > 0.0, "Centralny szyb musi publikować niezerowe velocity.")
	_assert((central.get("stage_multipliers", []) as Array).size() == 4, "Centralny szyb musi publikować mnożniki S0-S3.")
	var multipliers := central.get("stage_multipliers", []) as Array
	if multipliers.size() == 4:
		_assert(is_equal_approx(float(multipliers[0]), 1.0), "S0 centralnego prądu musi mieć mnożnik 1.")
		_assert(is_equal_approx(float(multipliers[1]), 2.0 / 3.0), "Po B centralny prąd musi spaść do 2/3.")
		_assert(is_equal_approx(float(multipliers[2]), 1.0 / 3.0), "Po C centralny prąd musi spaść do 1/3.")
		_assert(is_zero_approx(float(multipliers[3])), "Po D centralny prąd musi być wyłączony.")
	var b_current := currents.get("inlet_b", {}) as Dictionary
	var cover_socket_ids := b_current.get("cover_socket_ids", []) as Array
	_assert(cover_socket_ids.size() == 2, "Prąd B musi wskazywać dokładnie dwie bezpieczne osłony.")
	_assert(not str(b_current.get("recovery_socket_id", "")).is_empty(), "Prąd B musi wskazywać recovery socket.")
	_assert(_vector2(b_current.get("velocity", [])).length() > 0.0 and _vector2(b_current.get("recovery_velocity", [])).length() > 0.0, "Prąd B musi publikować velocity i recovery_velocity.")
	var b_velocity := _vector2(b_current.get("velocity", []))
	var recovery_velocity := _vector2(b_current.get("recovery_velocity", []))
	_assert(b_velocity.x > 0.0 and is_zero_approx(b_velocity.y), "Prąd B musi spychać od dźwigni w stronę prawej kraty, aby osłony były potrzebne.")
	_assert(recovery_velocity.x < 0.0 and is_zero_approx(recovery_velocity.y), "Strefa recovery B musi odprowadzać od prawej kraty do bezpiecznej osłony.")
	_assert(b_velocity.dot(recovery_velocity) < 0.0, "Recovery B musi działać przeciwnie do głównego prądu.")
	var main_current_rect := _rect2i(_record_by_id(package_manifest.get("sockets", []) as Array, str(b_current.get("socket_id", ""))).get("local_rect", []))
	var recovery_rect := _rect2i(_record_by_id(package_manifest.get("sockets", []) as Array, str(b_current.get("recovery_socket_id", ""))).get("local_rect", []))
	_assert(recovery_rect.end.x == main_current_rect.end.x and recovery_rect.position.y == main_current_rect.position.y, "Strefa recovery B musi być zakotwiczona przed prawą kratą.")
	_assert(_rect_inside(recovery_rect, main_current_rect), "Strefa recovery B musi leżeć wewnątrz current_b_main.")
	var collision_cells := _collision_cells(package_manifest.get("collision", {}) as Dictionary)
	for cover_socket_id_value: Variant in cover_socket_ids:
		var cover_socket_id := str(cover_socket_id_value)
		var cover_rect := _rect2i(_record_by_id(package_manifest.get("sockets", []) as Array, cover_socket_id).get("local_rect", []))
		_assert(_rect_contains_collision_value(cover_rect, collision_cells, 0), "Osłona B %s musi zawierać fizyczny filar." % cover_socket_id)
		_assert(_rect_contains_collision_value(cover_rect, collision_cells, 255), "Osłona B %s musi pozostawiać osiągalną kieszeń bez prądu." % cover_socket_id)
	_assert(int(b_current.get("active_stage", -1)) == 0, "Prąd B może działać wyłącznie w S0.")
	_assert(str(egress_socket.get("kind", "")) == "building_egress", "egress_socket_id musi wskazywać jedyne building_egress.")


func _verify_visual_assets(package_manifest: Dictionary) -> void:
	var assets := package_manifest.get("visual_assets", []) as Array
	_assert(assets.size() == 2, "Pakiet W02 musi deklarować dokładnie parę assetów wnętrza L04 i bryły L05.")
	var ids := {}
	var kind_counts := {
		"structure_interior_texture": 0,
		"structure_owner_masked_texture": 0,
	}
	var expected_layers := {
		"structure_interior_texture": "L04",
		"structure_owner_masked_texture": "L05",
	}
	var shared_group_id := ""
	var full_rect := Rect2i(Vector2i.ZERO, STRUCTURE_SIZE)
	for asset_value: Variant in assets:
		var asset := asset_value as Dictionary
		var asset_id := str(asset.get("id", ""))
		_assert(asset_id.begins_with(STRUCTURE_ID + "_"), "ID assetu musi być prefiksowane stable ID pakietu: %s." % asset_id)
		_assert(not ids.has(asset_id), "ID assetu wizualnego musi być unikalne: %s." % asset_id)
		ids[asset_id] = true
		var kind := str(asset.get("kind", ""))
		_assert(kind_counts.has(kind), "Asset %s ma nieobsługiwany kind %s." % [asset_id, kind])
		if kind_counts.has(kind):
			kind_counts[kind] = int(kind_counts[kind]) + 1
			_assert(str(asset.get("layer_id", "")) == str(expected_layers[kind]), "Asset %s musi należeć do %s." % [asset_id, str(expected_layers[kind])])
		_assert(bool(asset.get("enabled", false)), "Wymagany asset %s musi być włączony." % asset_id)
		var group_id := str(asset.get("group_id", ""))
		_assert(not group_id.is_empty(), "Asset %s musi należeć do nazwanej wspólnej grupy." % asset_id)
		if shared_group_id.is_empty():
			shared_group_id = group_id
		else:
			_assert(group_id == shared_group_id, "Assety L04 i L05 muszą należeć do tej samej grupy organizacyjnej.")
		var local_rect := _rect2i(asset.get("local_rect", []))
		var pixel_size := _vector2i(asset.get("pixel_size", []))
		_assert(pixel_size == STRUCTURE_SIZE, "Asset %s musi mieć natywne 2400x3840 bez resamplingu." % asset_id)
		_assert(local_rect == full_rect, "Asset %s musi pokrywać pełny lokalny rect 2400x3840 w skali 1:1." % asset_id)
		var relative_path := str(asset.get("path", ""))
		_assert(relative_path.begins_with("assets/") and _is_safe_relative_path(relative_path), "Asset musi pozostać pod assets/: %s." % relative_path)
		_verify_file_hash(relative_path, str(asset.get("sha256", "")), "asset")
		var image := Image.new()
		var load_error := image.load(ProjectSettings.globalize_path(PACKAGE_ROOT + relative_path))
		_assert(load_error == OK, "Asset %s musi być ładowalną natywną bitmapą." % asset_id)
		if load_error == OK:
			_assert(Vector2i(image.get_width(), image.get_height()) == pixel_size, "Rzeczywisty rozmiar bitmapy %s musi być zgodny z pixel_size bez resamplingu." % asset_id)
	_assert(int(kind_counts["structure_interior_texture"]) == 1, "Pakiet W02 wymaga dokładnie jednego wnętrza L04.")
	_assert(int(kind_counts["structure_owner_masked_texture"]) == 1, "Pakiet W02 wymaga dokładnie jednej bryły właściciela kolidera L05.")


func _verify_generated_truth(package_manifest: Dictionary) -> void:
	_assert(FileAccess.file_exists(GENERATED_TRUTH_PATH), "Po buildzie pakiet wymaga generated/structure_truth.json.")
	_assert(FileAccess.file_exists(GENERATED_SCENE_PATH), "Po buildzie pakiet wymaga generated/structure.tscn.")
	if not FileAccess.file_exists(GENERATED_TRUTH_PATH):
		return
	var truth := _load_json(GENERATED_TRUTH_PATH, "structure_truth")
	_assert(not truth.is_empty(), "Istniejący structure_truth.json musi być poprawny.")
	_assert(truth.get("authority", true) == false and truth.get("generated", false) == true, "structure_truth musi być jawną nieautorytatywną pochodną.")
	_assert(str(truth.get("structure_id", "")) == STRUCTURE_ID, "structure_truth musi należeć do W02.")
	_assert(str(truth.get("package_manifest_path", "")) == PACKAGE_MANIFEST_RELATIVE_PATH, "structure_truth musi wskazywać jedyny manifest pakietu.")
	_assert(str(truth.get("package_manifest_sha256", "")).to_lower() == FileAccess.get_sha256(PACKAGE_MANIFEST_PATH).to_lower(), "structure_truth musi być hash-pinned do bieżącego manifestu.")
	_assert(_vector2i(truth.get("size", [])) == STRUCTURE_SIZE, "structure_truth musi zachować lokalny rozmiar 2400x3840.")
	_assert(not _contains_any_key(truth, ["origin", "world_origin", "world_rect", "landmark"]), "Pochodna pakietu nie może kopiować globalnego placementu mapy.")
	for artifact_value: Variant in (truth.get("native_artifacts", {}) as Dictionary).values():
		if not artifact_value is Dictionary:
			continue
		var artifact := artifact_value as Dictionary
		var path := str(artifact.get("path", ""))
		if not path.is_empty():
			_verify_resource_hash(_normalize_generated_path(path), str(artifact.get("sha256", "")), "generated artifact")
	for card_value: Variant in truth.get("socket_cards", []) as Array:
		var card := card_value as Dictionary
		_verify_resource_hash(_normalize_generated_path(str(card.get("path", ""))), str(card.get("sha256", "")), "socket card")
	for asset_id_value: Variant in truth.get("visual_asset_ids", []) as Array:
		_assert(str(asset_id_value).begins_with(STRUCTURE_ID + "_"), "Pochodne visual asset IDs muszą pozostać prefiksowane.")

	_assert(FileAccess.file_exists(GENERATED_SCENE_PATH), "Po buildzie structure_truth wymaga generated/structure.tscn.")
	var packed_scene := load(GENERATED_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "Wygenerowana scena W02 musi być ładowalnym PackedScene.")
	if packed_scene != null:
		var scene_root := packed_scene.instantiate() as Node2D
		_assert(scene_root != null, "Root wygenerowanej struktury musi być Node2D.")
		if scene_root != null:
			_assert(scene_root.position == Vector2.ZERO and scene_root.scale == Vector2.ONE and is_zero_approx(scene_root.rotation), "Prywatny StructureRoot musi zachować identity transform.")
			_assert(str(scene_root.get_meta(&"structure_id", "")) == STRUCTURE_ID, "Pochodna scena musi publikować stable ID W02.")
			scene_root.free()


func _collision_cells(collision: Dictionary) -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(COLLISION_RASTER_SIZE.x * COLLISION_RASTER_SIZE.y)
	cells.fill(255)
	for operation_value: Variant in collision.get("operations", []) as Array:
		var operation := operation_value as Dictionary
		var rect := _rect2i(operation.get("rect_px", []))
		var value := 0 if str(operation.get("op", "")) == "solid_rect" else 255
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				if x >= 0 and y >= 0 and x < COLLISION_RASTER_SIZE.x and y < COLLISION_RASTER_SIZE.y:
					cells[y * COLLISION_RASTER_SIZE.x + x] = value
	return cells


func _verify_staged_reachability(package_manifest: Dictionary, cells: PackedByteArray) -> void:
	var cabinet := (package_manifest.get("runtime", {}) as Dictionary).get("cabinet", {}) as Dictionary
	var cabinet_right := _vector2i(cabinet.get("move_right", []))
	var cabinet_down := cabinet_right + _vector2i(cabinet.get("move_down", []))
	var cases := [
		{
			"name": "S0",
			"open": [],
			"cabinet": Vector2i.ZERO,
			"expected": {
				"panel_a_status": true,
				"inlet_b_lever": true,
				"inlet_c_lever": false,
				"d_valve_v1": false,
				"d_valve_v2": false,
				"d_inlet_lever": false,
				"egress_ground_floor": false,
			},
		},
		{
			"name": "S1",
			"open": ["g1"],
			"cabinet": Vector2i.ZERO,
			"expected": {
				"inlet_c_lever": true,
				"d_valve_v1": false,
				"egress_ground_floor": false,
			},
		},
		{
			"name": "S2_HOME",
			"open": ["g1", "c_shortcut", "g2"],
			"cabinet": Vector2i.ZERO,
			"expected": {
				"d_valve_v1": true,
				"d_valve_v2": true,
				"d_inlet_lever": false,
				"egress_ground_floor": false,
			},
		},
		{
			"name": "S2_RIGHT",
			"open": ["g1", "c_shortcut", "g2"],
			"cabinet": cabinet_right,
			"expected": {
				"d_inlet_lever": false,
				"egress_ground_floor": false,
			},
		},
		{
			"name": "S2_DOWN",
			"open": ["g1", "c_shortcut", "g2"],
			"cabinet": cabinet_down,
			"expected": {
				"d_inlet_lever": true,
				"egress_ground_floor": false,
			},
		},
		{
			"name": "S3",
			"open": ["g1", "c_shortcut", "g2", "h3", "facade"],
			"cabinet": cabinet_down,
			"expected": {"egress_ground_floor": true},
		},
	]
	for case_value: Variant in cases:
		var case_record := case_value as Dictionary
		var reachable := _reachable_cells(
			package_manifest,
			cells,
			case_record.get("open", []) as Array,
			case_record.get("cabinet", Vector2i.ZERO) as Vector2i
		)
		for socket_id_value: Variant in (case_record.get("expected", {}) as Dictionary).keys():
			var socket_id := str(socket_id_value)
			var expected := bool((case_record.get("expected", {}) as Dictionary)[socket_id_value])
			var actual := reachable.has(_socket_center_cell(package_manifest, socket_id))
			_assert(
				actual == expected,
				"%s: osiągalność socketu %s musi wynosić %s." % [str(case_record.get("name", "?")), socket_id, expected],
			)

	var d_error_cases := [
		{
			"name": "D_ERROR_HOME",
			"start_socket": "d_valve_v2",
			"cabinet": Vector2i.ZERO,
		},
		{
			"name": "D_ERROR_RIGHT_STOP",
			"start_socket": "d_valve_v1",
			"cabinet": cabinet_right,
		},
	]
	for case_value: Variant in d_error_cases:
		var case_record := case_value as Dictionary
		var reachable := _reachable_cells(
			package_manifest,
			cells,
			["g1", "c_shortcut", "g2"],
			case_record.get("cabinet", Vector2i.ZERO) as Vector2i,
			str(case_record.get("start_socket", ""))
		)
		_assert(
			reachable.has(_socket_center_cell(package_manifest, "d_reset")),
			"%s: prawidłowy komponent gracza w komorze D musi zachować drogę do RESET." % str(case_record.get("name", "?")),
		)


func _reachable_cells(
	package_manifest: Dictionary,
	cells: PackedByteArray,
	open_barrier_ids: Array,
	cabinet_offset: Vector2i,
	start_socket_id: String = "entry_floor_12_damaged_balcony"
) -> Dictionary:
	var blocked := {}
	for y: int in range(COLLISION_RASTER_SIZE.y):
		for x: int in range(COLLISION_RASTER_SIZE.x):
			if cells[y * COLLISION_RASTER_SIZE.x + x] == 0:
				blocked[Vector2i(x, y)] = true
	var sockets := package_manifest.get("sockets", []) as Array
	var runtime := package_manifest.get("runtime", {}) as Dictionary
	for barrier_value: Variant in runtime.get("barriers", []) as Array:
		var barrier := barrier_value as Dictionary
		var rect := _rect2i(_record_by_id(sockets, str(barrier.get("socket_id", ""))).get("local_rect", []))
		if str(barrier.get("id", "")) in open_barrier_ids:
			rect.position += _vector2i(barrier.get("open_offset", []))
		_mark_rect_cells(blocked, rect)
	var cabinet := runtime.get("cabinet", {}) as Dictionary
	var cabinet_rect := _rect2i(_record_by_id(sockets, str(cabinet.get("socket_id", ""))).get("local_rect", []))
	cabinet_rect.position += cabinet_offset
	_mark_rect_cells(blocked, cabinet_rect)

	var start := _socket_center_cell(package_manifest, start_socket_id)
	var seen := {}
	if blocked.has(start):
		return seen
	var frontier: Array[Vector2i] = [start]
	seen[start] = true
	var head := 0
	while head < frontier.size():
		var cell := frontier[head]
		head += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor := cell + direction
			if (
				neighbor.x < 0
				or neighbor.y < 0
				or neighbor.x >= COLLISION_RASTER_SIZE.x
				or neighbor.y >= COLLISION_RASTER_SIZE.y
				or blocked.has(neighbor)
				or seen.has(neighbor)
			):
				continue
			seen[neighbor] = true
			frontier.append(neighbor)
	return seen


func _mark_rect_cells(target: Dictionary, rect: Rect2i) -> void:
	for y: int in range(COLLISION_RASTER_SIZE.y):
		for x: int in range(COLLISION_RASTER_SIZE.x):
			var center := Vector2i(
				x * GRID_WORLD_UNITS + GRID_WORLD_UNITS / 2,
				y * GRID_WORLD_UNITS + GRID_WORLD_UNITS / 2
			)
			if rect.has_point(center):
				target[Vector2i(x, y)] = true


func _socket_center_cell(package_manifest: Dictionary, socket_id: String) -> Vector2i:
	var socket := _record_by_id(package_manifest.get("sockets", []) as Array, socket_id)
	var rect := _rect2i(socket.get("local_rect", []))
	return Vector2i(
		int((rect.position.x + rect.size.x * 0.5) / GRID_WORLD_UNITS),
		int((rect.position.y + rect.size.y * 0.5) / GRID_WORLD_UNITS)
	)


func _rect_contains_collision_value(rect: Rect2i, cells: PackedByteArray, expected: int) -> bool:
	for y: int in range(COLLISION_RASTER_SIZE.y):
		for x: int in range(COLLISION_RASTER_SIZE.x):
			var center := Vector2i(
				x * GRID_WORLD_UNITS + GRID_WORLD_UNITS / 2,
				y * GRID_WORLD_UNITS + GRID_WORLD_UNITS / 2
			)
			if rect.has_point(center) and cells[y * COLLISION_RASTER_SIZE.x + x] == expected:
				return true
	return false


func _verify_file_hash(relative_path: String, expected_sha256: String, label: String) -> void:
	_verify_resource_hash(PACKAGE_ROOT + relative_path, expected_sha256, label)


func _verify_resource_hash(resource_path: String, expected_sha256: String, label: String) -> void:
	_assert(not resource_path.is_empty() and FileAccess.file_exists(resource_path), "Brak zadeklarowanego pliku %s: %s." % [label, resource_path])
	_assert(expected_sha256.length() == 64, "%s musi deklarować pełny SHA-256: %s." % [label, resource_path])
	if FileAccess.file_exists(resource_path) and expected_sha256.length() == 64:
		_assert(FileAccess.get_sha256(resource_path).to_lower() == expected_sha256.to_lower(), "Niezgodny SHA-256 dla %s: %s." % [label, resource_path])


func _normalize_generated_path(path: String) -> String:
	if path.begins_with("res://"):
		return path
	if path.begins_with(PACKAGE_RELATIVE_PREFIX):
		return PACKAGE_ROOT + path.trim_prefix(PACKAGE_RELATIVE_PREFIX)
	if path.begins_with("structures/"):
		_assert(false, "W02 nie może weryfikować generated artifact z innego pakietu: %s." % path)
		return ""
	return PACKAGE_ROOT + path


func _load_json(path: String, label: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	_assert(file != null, "Nie można otworzyć %s: %s." % [label, path])
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_assert(parsed is Dictionary, "%s musi być poprawnym obiektem JSON: %s." % [label, path])
	return parsed as Dictionary if parsed is Dictionary else {}


func _record_by_id(records: Array, record_id: String) -> Dictionary:
	for record_value: Variant in records:
		var record := record_value as Dictionary
		if str(record.get("id", "")) == record_id:
			return record
	return {}


func _sorted_ids(records: Array) -> Array:
	var result: Array[String] = []
	for record_value: Variant in records:
		result.append(str((record_value as Dictionary).get("id", "")))
	result.sort()
	return result


func _sorted_copy(values: Array) -> Array:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	result.sort()
	return result


func _count_records_by_value(records: Array, key: String, expected: String) -> int:
	var count := 0
	for record_value: Variant in records:
		if str((record_value as Dictionary).get(key, "")) == expected:
			count += 1
	return count


func _contains_any_key(value: Variant, forbidden_keys: Array) -> bool:
	if value is Dictionary:
		for key_value: Variant in (value as Dictionary).keys():
			if str(key_value) in forbidden_keys:
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


func _is_safe_relative_path(path: String) -> bool:
	return not path.is_empty() and not path.begins_with("/") and not path.begins_with("res://") and not path.contains("..") and not path.contains("\\")


func _rect_inside(inner: Rect2i, outer: Rect2i) -> bool:
	return inner.position.x >= outer.position.x and inner.position.y >= outer.position.y and inner.end.x <= outer.end.x and inner.end.y <= outer.end.y


func _rect_is_grid_aligned(rect: Rect2i, grid: int) -> bool:
	return rect.position.x % grid == 0 and rect.position.y % grid == 0 and rect.size.x % grid == 0 and rect.size.y % grid == 0


func _vector2i(value: Variant) -> Vector2i:
	if not value is Array or (value as Array).size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int((value as Array)[0]), int((value as Array)[1]))


func _vector2(value: Variant) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2.ZERO
	return Vector2(float((value as Array)[0]), float((value as Array)[1]))


func _rect2i(value: Variant) -> Rect2i:
	if not value is Array or (value as Array).size() != 4:
		return Rect2i(0, 0, -1, -1)
	return Rect2i(int((value as Array)[0]), int((value as Array)[1]), int((value as Array)[2]), int((value as Array)[3]))


func _canonical_json(value: Variant) -> String:
	return JSON.stringify(_canonical_value(value), "", true, true)


func _canonical_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var result := {}
			var keys: Array[String] = []
			for key_value: Variant in (value as Dictionary).keys():
				keys.append(str(key_value))
			keys.sort()
			for key: String in keys:
				result[key] = _canonical_value((value as Dictionary)[key])
			return result
		TYPE_ARRAY:
			var result := []
			for child_value: Variant in value as Array:
				result.append(_canonical_value(child_value))
			return result
		TYPE_FLOAT:
			var number := float(value)
			return int(number) if is_finite(number) and number == floor(number) else number
		_:
			return value


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("Tower three inlets package contract test passed.")
	quit(0)
