extends SceneTree

const ResidencyScript := preload(
	"res://underwater_map_workbench/runtime/UnderwaterMapVisualResidency.gd"
)
const ProfileScript := preload(
	"res://underwater_map_workbench/runtime/UnderwaterMapVisualResidencyProfile.gd"
)

const MANIFEST_PATH := "res://underwater_map_workbench/map_manifest.json"
const MAP_SCENE_PATH := "res://underwater_map_workbench/UnderwaterMap.tscn"
const WORKBENCH_RESOURCE_ROOT := "res://underwater_map_workbench/"
const STREAMED_LAYER_IDS := ["L01", "L02"]
const STREAMED_KIND := "texture_rect"
const STREAMED_CONTRACT := "camera_windowed_texture_v1"
const FIXTURE_VIEWPORT_SIZE := Vector2i(640, 360)
const RESIDENCY_TIMEOUT_MSEC := 30_000
const REQUIRED_SPREAD_RECORDS := 8

var _failed := false
var _generated_map: Node
var _map_world_size := Vector2.ZERO


class ResidencyLoaderHarness:
	extends UnderwaterMapVisualResidency

	var scripted_status: ResourceLoader.ThreadLoadStatus = (
		ResourceLoader.THREAD_LOAD_IN_PROGRESS
	)
	var scripted_resource: Resource
	var request_cache_modes: Array[int] = []
	var terminal_get_count := 0

	func _resource_load_threaded_request(
		_path: String,
		cache_mode: ResourceLoader.CacheMode,
	) -> Error:
		request_cache_modes.append(int(cache_mode))
		return OK

	func _resource_load_threaded_get_status(
		_path: String,
		progress: Array,
	) -> ResourceLoader.ThreadLoadStatus:
		progress.append(0.5 if scripted_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS else 1.0)
		return scripted_status

	func _resource_load_threaded_get(_path: String) -> Resource:
		terminal_get_count += 1
		return scripted_resource

	func _resource_get_cached_ref(_path: String) -> Resource:
		return null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var descriptors := _load_active_scene_descriptors()
	var unique_descriptors := _unique_path_descriptors(descriptors)
	if unique_descriptors.size() < REQUIRED_SPREAD_RECORDS:
		_fail(
			"Aktywne L01/L02 wymagają co najmniej %d rozproszonych kanonicznych ścieżek; znaleziono %d."
			% [REQUIRED_SPREAD_RECORDS, unique_descriptors.size()]
		)
		_finish()
		return
	var spread := _select_spread(unique_descriptors, REQUIRED_SPREAD_RECORDS)
	if spread.size() != REQUIRED_SPREAD_RECORDS:
		_fail("Nie udało się deterministycznie wybrać rozproszonych zasobów L01/L02.")
		_finish()
		return

	if not await _test_initial_residency_retention_and_eviction([
		spread[0], spread[3], spread[7],
	]):
		_finish()
		return
	if not await _test_poll_tick_advances_queued_requests([
		spread[0], spread[3], spread[7],
	]):
		_finish()
		return
	if not await _test_rapid_window_change_discards_obsolete_result(spread[1], spread[6]):
		_finish()
		return
	if not await _test_reconfigure_while_request_is_pending(spread[2]):
		_finish()
		return
	if not await _test_obsolete_terminal_failure_restarts(
		spread[2],
		ResourceLoader.THREAD_LOAD_FAILED,
		"FAILED",
	):
		_finish()
		return
	if not await _test_obsolete_terminal_failure_restarts(
		spread[2],
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"INVALID",
	):
		_finish()
		return
	if not await _test_reduced_motion_resize_and_zoom_reselect(spread[4]):
		_finish()
		return
	if not await _test_production_parallax_extreme_cameras(descriptors):
		_finish()
		return
	if not await _test_sticky_failure(spread[5]):
		_finish()
		return
	if not await _test_visible_overcommit_keeps_frame_populated(spread[5]):
		_finish()
		return
	_finish()


func _load_active_scene_descriptors() -> Array[Dictionary]:
	var manifest := _load_json(MANIFEST_PATH)
	if manifest.is_empty():
		return []
	var map_value: Variant = manifest.get("map", null)
	if map_value is Dictionary:
		_map_world_size = _vector2((map_value as Dictionary).get("world_size", null))
	if _map_world_size.x <= 0.0 or _map_world_size.y <= 0.0:
		_fail("map_manifest.json nie publikuje dodatniego map.world_size.")
		return []
	var visual_value: Variant = manifest.get("visual", null)
	if not visual_value is Dictionary:
		_fail("map_manifest.json nie publikuje obiektu visual.")
		return []
	var assets_value: Variant = (visual_value as Dictionary).get("assets", null)
	if not assets_value is Array:
		_fail("map_manifest.json nie publikuje tablicy visual.assets.")
		return []

	var active_records: Array[Dictionary] = []
	var active_ids := {}
	for asset_value in assets_value as Array:
		if not asset_value is Dictionary:
			continue
		var asset := asset_value as Dictionary
		var layer_id := str(asset.get("layer_id", ""))
		if (
			layer_id not in STREAMED_LAYER_IDS
			or str(asset.get("kind", "")) != STREAMED_KIND
			or not bool(asset.get("enabled", true))
		):
			continue
		var asset_id := str(asset.get("id", "")).strip_edges()
		var canonical_path := _canonical_resource_path(str(asset.get("path", "")))
		var world_rect := _rect(asset.get("world_rect", null))
		var pixel_size := _vector2i(asset.get("pixel_size", null))
		if asset_id.is_empty() or active_ids.has(asset_id):
			_fail("Aktywne rekordy L01/L02 wymagają unikalnych, niepustych id.")
			return []
		if canonical_path.is_empty():
			_fail("Aktywne rekordy L01/L02 wymagają lokalnych ścieżek zasobów.")
			return []
		if (
			not _positive_finite_rect(world_rect)
			or pixel_size.x <= 0
			or pixel_size.y <= 0
			or not world_rect.size.is_equal_approx(Vector2(pixel_size))
		):
			_fail("Aktywny rekord L01/L02 %s ma niespójną geometrię 1:1." % asset_id)
			return []
		active_ids[asset_id] = true
		active_records.append(asset)

	if active_records.is_empty():
		_fail("Manifest nie zawiera aktywnych texture_rect w L01/L02.")
		return []
	var packed_map := ResourceLoader.load(
		MAP_SCENE_PATH,
		"PackedScene",
		ResourceLoader.CACHE_MODE_REUSE,
	) as PackedScene
	if packed_map == null:
		_fail("Nie można załadować wygenerowanej sceny mapy.")
		return []
	_generated_map = packed_map.instantiate()
	if _generated_map == null:
		_fail("Nie można utworzyć instancji wygenerowanej sceny mapy.")
		return []
	var visual_layers := _generated_map.get_node_or_null("VisualLayers") as Node2D
	if visual_layers == null:
		_fail("Wygenerowana scena nie zawiera VisualLayers.")
		return []

	var scene_nodes_by_id := {}
	for layer_id in STREAMED_LAYER_IDS:
		var layer := visual_layers.get_node_or_null(NodePath(layer_id))
		if not layer is Node2D:
			_fail("Wygenerowana scena nie zawiera warstwy %s." % layer_id)
			return []
		for group_node in layer.get_children():
			for asset_node in group_node.get_children():
				var source_value: Variant = asset_node.get_meta("source", null)
				if not source_value is Dictionary:
					continue
				var source := source_value as Dictionary
				if (
					str(source.get("layer_id", "")) != layer_id
					or str(source.get("kind", "")) != STREAMED_KIND
					or not bool(source.get("enabled", true))
				):
					continue
				var asset_id := str(source.get("id", "")).strip_edges()
				if asset_id.is_empty() or scene_nodes_by_id.has(asset_id):
					_fail("Scena zawiera pusty albo zduplikowany aktywny stub L01/L02.")
					return []
				scene_nodes_by_id[asset_id] = asset_node

	if scene_nodes_by_id.size() != active_records.size():
		_fail(
			"Scena ma %d aktywnych stubów L01/L02, a manifest %d."
			% [scene_nodes_by_id.size(), active_records.size()]
		)
		return []

	var descriptors: Array[Dictionary] = []
	for record in active_records:
		var asset_id := str(record.get("id", ""))
		var asset_node_value: Variant = scene_nodes_by_id.get(asset_id, null)
		if not asset_node_value is Node2D:
			_fail("Scena nie publikuje stuba aktywnego rekordu %s." % asset_id)
			return []
		var asset_node := asset_node_value as Node2D
		var layer_id := str(record.get("layer_id", ""))
		var canonical_path := _canonical_resource_path(str(record.get("path", "")))
		var world_rect := _rect(record.get("world_rect", null))
		var pixel_size := _vector2i(record.get("pixel_size", null))
		var bitmap := asset_node.get_node_or_null("Bitmap") as TextureRect
		if bitmap == null:
			_fail("Stub %s nie zawiera publicznego Bitmap:TextureRect." % asset_id)
			return []
		if bitmap.texture != null:
			_fail("Stub %s preładowuje teksturę zamiast zaczynać od null." % asset_id)
			return []
		if str(asset_node.get_meta("asset_id", "")) != asset_id:
			_fail("Stub %s ma niespójne metadata asset_id." % asset_id)
			return []
		if str(asset_node.get_meta("layer_id", "")) != layer_id:
			_fail("Stub %s ma niespójne metadata layer_id." % asset_id)
			return []
		if str(asset_node.get_meta("residency_contract", "")) != STREAMED_CONTRACT:
			_fail("Stub %s nie publikuje kontraktu %s." % [asset_id, STREAMED_CONTRACT])
			return []
		if str(asset_node.get_meta("resource_path", "")) != canonical_path:
			_fail("Stub %s ma resource_path inne niż manifest." % asset_id)
			return []
		if str(asset_node.get_meta("source_sha256", "")) != str(record.get("sha256", "")):
			_fail("Stub %s ma pin SHA-256 inny niż manifest." % asset_id)
			return []
		if asset_node.get_meta("pixel_size", Vector2i.ZERO) != pixel_size:
			_fail("Stub %s ma pixel_size inne niż manifest." % asset_id)
			return []
		var scene_rect_value: Variant = asset_node.get_meta("world_rect", null)
		if not scene_rect_value is Rect2 or not (scene_rect_value as Rect2).is_equal_approx(world_rect):
			_fail("Stub %s ma world_rect inne niż manifest." % asset_id)
			return []
		var source := asset_node.get_meta("source") as Dictionary
		if (
			str(source.get("id", "")) != asset_id
			or str(source.get("path", "")) != str(record.get("path", ""))
			or str(source.get("sha256", "")) != str(record.get("sha256", ""))
		):
			_fail("Stub %s ma rekord source inny niż manifest." % asset_id)
			return []
		var source_layer := visual_layers.get_node_or_null(NodePath(layer_id)) as Parallax2D
		if source_layer == null:
			_fail("Warstwa %s aktywnego stuba nie jest Parallax2D." % layer_id)
			return []
		var parallax_scale := source_layer.scroll_scale
		var authored_scale_value: Variant = source_layer.get_meta("parallax_scale", null)
		if (
			not authored_scale_value is Vector2
			or not (authored_scale_value as Vector2).is_equal_approx(parallax_scale)
			or parallax_scale.is_equal_approx(Vector2.ONE)
		):
			_fail(
				"Warstwa %s musi używać produkcyjnego scroll_scale zgodnego z parallax_scale."
				% layer_id
			)
			return []
		descriptors.append({
			"asset_id": asset_id,
			"layer_id": layer_id,
			"path": canonical_path,
			"world_rect": world_rect,
			"pixel_size": pixel_size,
			"scene_node": asset_node,
			"parallax_scale": parallax_scale,
		})
	descriptors.sort_custom(_descriptor_before)
	return descriptors


func _test_initial_residency_retention_and_eviction(
	descriptors: Array,
) -> bool:
	var fixture := _create_fixture(descriptors)
	if fixture.is_empty():
		return false
	await process_frame
	var profile = _new_profile()
	profile.prefetch_margin_viewports = 0.0
	profile.retention_margin_viewports = 1.0
	var manager = ResidencyScript.new()
	var errors: PackedStringArray = manager.configure(fixture["visual_layers"], profile)
	if not _require(errors.is_empty(), "Konfiguracja scenariusza retencji: %s" % str(errors)):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	var initial: Dictionary = manager.telemetry_snapshot()
	if not _require(
		int(initial.get("tracked_canonical_path_count", 0)) == descriptors.size(),
		"Manager nie śledzi wszystkich wybranych kanonicznych ścieżek.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	if not _require(
		int(initial.get("resident_texture_count", -1)) == 0
		and _all_fixture_bitmaps_are_null(fixture),
		"Przed pierwszym oknem żaden zasób nie może być rezydentny.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false

	var target: Dictionary = descriptors[0]
	var target_rect := target["world_rect"] as Rect2
	_set_camera(fixture, target_rect.get_center(), Vector2.ONE)
	await process_frame
	manager.invalidate_window()
	manager.update_window(
		(fixture["camera"] as Camera2D).position,
		_visible_half_extent(fixture),
		true,
	)
	var at_a := await _wait_for_settled(manager, fixture, true, "okno A")
	if at_a.is_empty():
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	if not _require(
		int(at_a.get("resident_texture_count", 0)) > 0
		and int(at_a.get("resident_texture_count", 0)) < descriptors.size(),
		"Okno A ma wczytać część, lecz nie wszystkie śledzone zasoby.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	if not _require(
		_fixture_bitmap(fixture, str(target["path"])).texture != null,
		"Widoczny zasób A musi otrzymać teksturę.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false

	var viewport_width := float((fixture["viewport"] as SubViewport).size.x)
	var visible_edge_delta := target_rect.size.x * 0.5 + viewport_width * 0.5
	var retention_extra: float = viewport_width * float(profile.retention_margin_viewports)
	var retention_position := target_rect.get_center() + Vector2(
		visible_edge_delta + retention_extra * 0.5,
		0.0,
	)
	_set_camera(fixture, retention_position, Vector2.ONE)
	await process_frame
	manager.invalidate_window()
	manager.update_window(retention_position, _visible_half_extent(fixture), true)
	var retained := manager.telemetry_snapshot()
	if not _require(
		_fixture_bitmap(fixture, str(target["path"])).texture != null
		and int(retained.get("resident_texture_count", 0)) > 0,
		"Zasób A ma pozostać rezydentny wewnątrz granicy retencji.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false

	var eviction_before := int(retained.get("eviction_count", 0))
	var far_position := target_rect.get_center() + Vector2(
		visible_edge_delta + retention_extra + viewport_width * 0.25 + 1.0,
		0.0,
	)
	_set_camera(fixture, far_position, Vector2.ONE)
	await process_frame
	manager.invalidate_window()
	manager.update_window(far_position, _visible_half_extent(fixture), true)
	var far_snapshot := manager.telemetry_snapshot()
	if not _require(
		_fixture_bitmap(fixture, str(target["path"])).texture == null
		and int(far_snapshot.get("eviction_count", 0)) > eviction_before,
		"Po wyjściu daleko poza retencję zasób A ma zostać ewikowany.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	await _dispose_manager(manager)
	_dispose_fixture(fixture)
	return not _failed


func _test_rapid_window_change_discards_obsolete_result(
	a_descriptor: Dictionary,
	b_descriptor: Dictionary,
) -> bool:
	var fixture := _create_fixture([a_descriptor, b_descriptor])
	if fixture.is_empty():
		return false
	await process_frame
	var profile = _new_profile()
	profile.prefetch_margin_viewports = 0.0
	profile.retention_margin_viewports = 0.25
	profile.max_in_flight_requests = 1
	profile.max_commits_per_tick = 1
	var manager = ResidencyScript.new()
	var errors: PackedStringArray = manager.configure(fixture["visual_layers"], profile)
	if not _require(errors.is_empty(), "Konfiguracja szybkiego A→B: %s" % str(errors)):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false

	var a_rect := a_descriptor["world_rect"] as Rect2
	_set_camera(fixture, a_rect.get_center(), Vector2.ONE)
	await process_frame
	manager.invalidate_window()
	manager.update_window(a_rect.get_center(), _visible_half_extent(fixture), true)
	var requested_a := manager.telemetry_snapshot()
	if not _require(
		int(requested_a.get("request_count", 0)) == 1
		and int(requested_a.get("in_flight_count", 0)) == 1,
		"Okno A musi pozostawić dokładnie jedno nieodebrane żądanie przed skokiem do B.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false

	var b_rect := b_descriptor["world_rect"] as Rect2
	_set_camera(fixture, b_rect.get_center(), Vector2.ONE)
	await process_frame
	manager.invalidate_window()
	manager.update_window(b_rect.get_center(), _visible_half_extent(fixture), true)
	var at_b := await _wait_for_settled(manager, fixture, true, "szybkie okno B")
	if at_b.is_empty():
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	if not _require(
		_fixture_bitmap(fixture, str(a_descriptor["path"])).texture == null,
		"Terminalny wynik starego okna A nie może zostać przypięty po skoku do B.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	if not _require(
		_fixture_bitmap(fixture, str(b_descriptor["path"])).texture != null
		and int(at_b.get("visible_missing_count", -1)) == 0,
		"Aktualne okno B musi otrzymać teksturę po odrzuceniu wyniku A.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	if not _require(
		int(at_b.get("request_count", 0)) >= 2
		and int(at_b.get("terminal_request_count", -1)) == int(at_b.get("request_count", 0)),
		"Każde żądanie szybkiego A→B musi zostać odebrane terminalnie.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	await _dispose_manager(manager)
	_dispose_fixture(fixture)
	return not _failed


func _test_reconfigure_while_request_is_pending(descriptor: Dictionary) -> bool:
	var first_fixture := _create_fixture([descriptor])
	if first_fixture.is_empty():
		return false
	await process_frame
	var profile = _new_profile()
	profile.prefetch_margin_viewports = 0.0
	profile.retention_margin_viewports = 0.5
	profile.max_in_flight_requests = 1
	profile.max_commits_per_tick = 1
	var manager = ResidencyScript.new()
	var errors: PackedStringArray = manager.configure(first_fixture["visual_layers"], profile)
	if not _require(errors.is_empty(), "Pierwsza konfiguracja podczas requestu: %s" % str(errors)):
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		return false
	var rect := descriptor["world_rect"] as Rect2
	_set_camera(first_fixture, rect.get_center(), Vector2.ONE)
	await process_frame
	manager.invalidate_window()
	manager.update_window(rect.get_center(), _visible_half_extent(first_fixture), true)
	var pending := manager.telemetry_snapshot()
	if not _require(
		int(pending.get("request_count", 0)) == 1
		and int(pending.get("in_flight_count", 0)) == 1,
		"Rekonfiguracja musi rozpocząć się przy śledzonym żądaniu.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		return false

	var second_fixture := _create_fixture([descriptor])
	if second_fixture.is_empty():
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		return false
	var path := str(descriptor["path"])
	var second_node := (second_fixture["nodes"] as Dictionary).get(path) as Node2D
	if not _require(second_node != null, "Druga konfiguracja nie zawiera stuba testowego."):
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		_dispose_fixture(second_fixture)
		return false
	var revised_sha := "0".repeat(64)
	if str(second_node.get_meta("source_sha256", "")) == revised_sha:
		revised_sha = "f".repeat(64)
	var revised_source := (second_node.get_meta("source") as Dictionary).duplicate(true)
	revised_source["sha256"] = revised_sha
	second_node.set_meta("source_sha256", revised_sha)
	second_node.set_meta("source", revised_source)
	_set_camera(second_fixture, rect.get_center(), Vector2.ONE)
	await process_frame
	var reconfigure_errors: PackedStringArray = manager.configure(
		second_fixture["visual_layers"],
		profile,
	)
	if not _require(
		reconfigure_errors.is_empty(),
		"Rekonfiguracja przy request: %s" % str(reconfigure_errors),
	):
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		_dispose_fixture(second_fixture)
		return false
	var after_reconfigure := manager.telemetry_snapshot()
	if not _require(
		int(after_reconfigure.get("request_count", 0)) == 1
		and int(after_reconfigure.get("in_flight_count", 0)) == 1,
		"Rekonfiguracja ma przejąć istniejące żądanie kanonicznej ścieżki bez duplikatu.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		_dispose_fixture(second_fixture)
		return false
	manager.invalidate_window()
	manager.update_window(rect.get_center(), _visible_half_extent(second_fixture), true)
	var settled := await _wait_for_settled(
		manager,
		second_fixture,
		true,
		"rekonfiguracja przy request",
	)
	if settled.is_empty():
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		_dispose_fixture(second_fixture)
		return false
	if not _require(
		_fixture_bitmap(first_fixture, str(descriptor["path"])).texture == null
		and _fixture_bitmap(second_fixture, str(descriptor["path"])).texture != null,
		"Wynik requestu ma trafić wyłącznie do aktualnej konfiguracji.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		_dispose_fixture(second_fixture)
		return false
	if not _require(
		int(settled.get("request_count", 0)) == 2
		and int(settled.get("terminal_request_count", 0)) == 2
		and int(settled.get("cache_reuse_count", 0)) == 0,
		"Zmieniony deskryptor ma odrzucić stary wynik i wykonać dokładnie jeden świeży request z wymianą cache.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		_dispose_fixture(second_fixture)
		return false
	await _dispose_manager(manager)
	_dispose_fixture(first_fixture)
	_dispose_fixture(second_fixture)
	return not _failed


func _test_obsolete_terminal_failure_restarts(
	descriptor: Dictionary,
	terminal_status: ResourceLoader.ThreadLoadStatus,
	status_label: String,
) -> bool:
	var first_fixture := _create_fixture([descriptor])
	if first_fixture.is_empty():
		return false
	await process_frame
	var profile = _new_profile()
	profile.prefetch_margin_viewports = 0.0
	profile.retention_margin_viewports = 0.05
	profile.max_in_flight_requests = 1
	profile.max_commits_per_tick = 1
	var manager := ResidencyLoaderHarness.new()
	var errors: PackedStringArray = manager.configure(first_fixture["visual_layers"], profile)
	if not _require(
		errors.is_empty(),
		"Konfiguracja obsolete %s: %s" % [status_label, str(errors)],
	):
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		return false

	var rect := descriptor["world_rect"] as Rect2
	var path := str(descriptor["path"])
	_set_camera(first_fixture, rect.get_center(), Vector2.ONE)
	await process_frame
	manager.invalidate_window()
	manager.update_window(rect.get_center(), _visible_half_extent(first_fixture), true)
	var pending := manager.telemetry_snapshot()
	if not _require(
		int(pending.get("request_count", 0)) == 1
		and int(pending.get("in_flight_count", 0)) == 1
		and manager.request_cache_modes == [int(ResourceLoader.CACHE_MODE_REUSE)],
		"Scenariusz obsolete %s musi rozpocząć jeden request REUSE." % status_label,
	):
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		return false

	var second_fixture := _create_fixture([descriptor])
	if second_fixture.is_empty():
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		return false
	var second_node := (second_fixture["nodes"] as Dictionary).get(path) as Node2D
	if not _require(second_node != null, "Fixture obsolete %s nie ma stuba." % status_label):
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		_dispose_fixture(second_fixture)
		return false
	var revised_sha := "1".repeat(64)
	if str(second_node.get_meta("source_sha256", "")) == revised_sha:
		revised_sha = "e".repeat(64)
	var revised_source := (second_node.get_meta("source") as Dictionary).duplicate(true)
	revised_source["sha256"] = revised_sha
	second_node.set_meta("source_sha256", revised_sha)
	second_node.set_meta("source", revised_source)
	_set_camera(second_fixture, rect.get_center(), Vector2.ONE)
	await process_frame
	var reconfigure_errors: PackedStringArray = manager.configure(
		second_fixture["visual_layers"],
		profile,
	)
	if not _require(
		reconfigure_errors.is_empty(),
		"Rekonfiguracja obsolete %s: %s" % [status_label, str(reconfigure_errors)],
	):
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		_dispose_fixture(second_fixture)
		return false

	manager.scripted_status = terminal_status
	manager.invalidate_window()
	manager.update_window(rect.get_center(), _visible_half_extent(second_fixture), true)
	var restarted := manager.telemetry_snapshot()
	if not _require(
		int(restarted.get("request_count", 0)) == 2
		and int(restarted.get("terminal_request_count", 0)) == 1
		and int(restarted.get("in_flight_count", 0)) == 1
		and int(restarted.get("failed_path_count", -1)) == 0
		and int(restarted.get("failure_count", -1)) == 0
		and manager.request_cache_modes == [
			int(ResourceLoader.CACHE_MODE_REUSE),
			int(ResourceLoader.CACHE_MODE_REPLACE),
		],
		(
			"Stary terminalny %s ma wrócić do IDLE i uruchomić dokładnie jeden świeży request REPLACE."
			% status_label
		),
	):
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		_dispose_fixture(second_fixture)
		return false

	manager.scripted_resource = ResourceLoader.load(
		path,
		"Texture2D",
		ResourceLoader.CACHE_MODE_REUSE,
	)
	if not _require(
		manager.scripted_resource is Texture2D,
		"Scenariusz obsolete %s nie może załadować fixture Texture2D." % status_label,
	):
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		_dispose_fixture(second_fixture)
		return false
	manager.scripted_status = ResourceLoader.THREAD_LOAD_LOADED
	await process_frame
	manager.update_window(rect.get_center(), _visible_half_extent(second_fixture), false)
	var settled := await _wait_for_settled(
		manager,
		second_fixture,
		true,
		"obsolete %s po REPLACE" % status_label,
	)
	var expected_get_count := 2 if terminal_status == ResourceLoader.THREAD_LOAD_FAILED else 1
	if settled.is_empty() or not _require(
		int(settled.get("request_count", 0)) == 2
		and int(settled.get("terminal_request_count", 0)) == 2
		and int(settled.get("outstanding_request_count", -1)) == 0
		and int(settled.get("failure_count", -1)) == 0
		and manager.terminal_get_count == expected_get_count
		and _fixture_bitmap(first_fixture, path).texture == null
		and _fixture_bitmap(second_fixture, path).texture != null,
		"Świeży request po obsolete %s musi zostać jedynym rezydentnym wynikiem." % status_label,
	):
		await _dispose_manager(manager)
		_dispose_fixture(first_fixture)
		_dispose_fixture(second_fixture)
		return false
	await _dispose_manager(manager)
	_dispose_fixture(first_fixture)
	_dispose_fixture(second_fixture)
	return not _failed


func _test_reduced_motion_resize_and_zoom_reselect(descriptor: Dictionary) -> bool:
	var fixture := _create_fixture([descriptor])
	if fixture.is_empty():
		return false
	await process_frame
	var profile = _new_profile()
	profile.prefetch_margin_viewports = 0.0
	profile.retention_margin_viewports = 0.5
	var manager = ResidencyScript.new()
	var errors: PackedStringArray = manager.configure(fixture["visual_layers"], profile)
	if not _require(errors.is_empty(), "Konfiguracja resize/zoom/reduced motion: %s" % str(errors)):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	var rect := descriptor["world_rect"] as Rect2
	_set_camera(fixture, rect.get_center(), Vector2.ONE)
	await process_frame
	manager.invalidate_window()
	manager.update_window(rect.get_center(), _visible_half_extent(fixture), true)
	var initial := await _wait_for_settled(manager, fixture, true, "bazowe okno transformacji")
	if initial.is_empty():
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false

	var layer := (fixture["layers"] as Dictionary).get(str(descriptor["layer_id"])) as Parallax2D
	if not _require(layer != null, "Fixture nie zawiera warstwy parallax rekordu testowego."):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	var authored_scale := descriptor.get("parallax_scale", Vector2.ONE) as Vector2
	if authored_scale.is_equal_approx(Vector2.ONE):
		authored_scale = Vector2(0.75, 1.0)
	layer.scroll_scale = authored_scale
	(fixture["camera"] as Camera2D).force_update_scroll()
	await process_frame
	manager.invalidate_window()
	manager.update_window(
		(fixture["camera"] as Camera2D).position,
		_visible_half_extent(fixture),
		true,
	)
	var authored_snapshot := manager.telemetry_snapshot()
	if not _require(
		int(authored_snapshot.get("generation", 0)) > int(initial.get("generation", 0))
		and str(authored_snapshot.get("selection_error", "")).is_empty(),
		"Zmiana parallax musi zostać ponownie sklasyfikowana przez update_window.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false

	layer.scroll_scale = Vector2.ONE
	_set_camera(fixture, rect.get_center(), Vector2.ONE)
	await process_frame
	manager.invalidate_window()
	manager.update_window(rect.get_center(), _visible_half_extent(fixture), true)
	var reduced := await _wait_for_settled(manager, fixture, true, "reduced motion")
	if reduced.is_empty() or not _require(
		int(reduced.get("generation", 0)) > int(authored_snapshot.get("generation", 0)),
		"Włączenie reduced motion musi odświeżyć generację okna.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false

	(fixture["viewport"] as SubViewport).size = Vector2i(800, 450)
	(fixture["camera"] as Camera2D).force_update_scroll()
	await process_frame
	manager.invalidate_window()
	manager.update_window(rect.get_center(), _visible_half_extent(fixture), true)
	var resized := await _wait_for_settled(manager, fixture, true, "resize viewportu")
	if resized.is_empty() or not _require(
		int(resized.get("generation", 0)) > int(reduced.get("generation", 0)),
		"Resize viewportu musi odświeżyć generację okna.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false

	_set_camera(fixture, rect.get_center(), Vector2(1.35, 1.35))
	await process_frame
	manager.invalidate_window()
	manager.update_window(rect.get_center(), _visible_half_extent(fixture), true)
	var zoomed := await _wait_for_settled(manager, fixture, true, "zoom kamery")
	if zoomed.is_empty() or not _require(
		int(zoomed.get("generation", 0)) > int(resized.get("generation", 0))
		and _fixture_bitmap(fixture, str(descriptor["path"])).texture != null,
		"Zoom musi ponownie wybrać okno i zachować widoczny zasób.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	await _dispose_manager(manager)
	_dispose_fixture(fixture)
	return not _failed


func _test_production_parallax_extreme_cameras(
	descriptors: Array[Dictionary],
) -> bool:
	var fixture := _create_fixture(descriptors, true)
	if fixture.is_empty():
		return false
	await process_frame
	for layer_id in STREAMED_LAYER_IDS:
		var layer := (fixture["layers"] as Dictionary).get(layer_id) as Parallax2D
		var expected_scale := _production_layer_scale(descriptors, layer_id)
		if not _require(
			layer != null
			and expected_scale.is_finite()
			and not expected_scale.is_equal_approx(Vector2.ONE)
			and layer.scroll_scale.is_equal_approx(expected_scale),
			"Fixture musi zachować produkcyjny scroll_scale warstwy %s." % layer_id,
		):
			_dispose_fixture(fixture)
			return false

	var profile = _new_profile()
	profile.prefetch_margin_viewports = 0.0
	profile.retention_margin_viewports = 0.05
	profile.resident_pixel_budget = 256_000_000
	profile.max_in_flight_requests = 8
	profile.max_commits_per_tick = 8
	var manager = ResidencyScript.new()
	var errors: PackedStringArray = manager.configure(fixture["visual_layers"], profile)
	if not _require(errors.is_empty(), "Konfiguracja skrajnego parallax: %s" % str(errors)):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false

	var visible_half := _visible_half_extent(fixture)
	var camera_y := clampf(_map_world_size.y * 0.4, visible_half.y, _map_world_size.y - visible_half.y)
	var camera_positions := PackedVector2Array([
		Vector2(visible_half.x, camera_y),
		Vector2(_map_world_size.x - visible_half.x, camera_y),
	])
	var resident_sets: Array[PackedStringArray] = []
	for edge_index in range(camera_positions.size()):
		var camera_position := camera_positions[edge_index]
		_set_camera(fixture, camera_position, Vector2.ONE)
		await process_frame
		manager.invalidate_window()
		manager.update_window(camera_position, _visible_half_extent(fixture), true)
		var snapshot := await _wait_for_settled(
			manager,
			fixture,
			true,
			"produkcyjny parallax skraj %d" % edge_index,
		)
		var resident_paths := _resident_fixture_paths(fixture)
		var expected_visible := _expected_visible_paths_by_layer(
			descriptors,
			camera_position,
			_visible_half_extent(fixture),
		)
		var expected_visible_asset_ids := _expected_visible_asset_ids_by_layer(
			descriptors,
			camera_position,
			_visible_half_extent(fixture),
		)
		var expected_unique_paths := {}
		var expected_unique_asset_ids := {}
		var all_expected_visible_are_resident := true
		var all_expected_visible_assets_are_resident := true
		for layer_id in STREAMED_LAYER_IDS:
			var layer_paths: PackedStringArray = expected_visible.get(
				layer_id,
				PackedStringArray(),
			)
			if layer_paths.is_empty():
				all_expected_visible_are_resident = false
			for path in layer_paths:
				expected_unique_paths[path] = true
				var bitmap := _fixture_bitmap(fixture, path)
				if bitmap == null or bitmap.texture == null:
					all_expected_visible_are_resident = false
			var layer_asset_ids: PackedStringArray = expected_visible_asset_ids.get(
				layer_id,
				PackedStringArray(),
			)
			if layer_asset_ids.is_empty():
				all_expected_visible_assets_are_resident = false
			for asset_id in layer_asset_ids:
				expected_unique_asset_ids[asset_id] = true
				var bitmap_by_asset_id := fixture["bitmap_by_asset_id"] as Dictionary
				var asset_bitmap := bitmap_by_asset_id.get(asset_id) as TextureRect
				if asset_bitmap == null or asset_bitmap.texture == null:
					all_expected_visible_assets_are_resident = false
		if snapshot.is_empty() or not _require(
			int(snapshot.get("tracked_asset_count", 0)) == descriptors.size()
			and int(snapshot.get("visible_required_texture_count", 0)) > 0
			and int(snapshot.get("visible_required_asset_count", 0)) > 0
			and int(snapshot.get("visible_required_texture_count", -1))
			== expected_unique_paths.size()
			and int(snapshot.get("visible_required_asset_count", -1))
			== expected_unique_asset_ids.size()
			and int(snapshot.get("visible_missing_texture_count", -1)) == 0
			and int(snapshot.get("visible_missing_asset_count", -1)) == 0
			and int(snapshot.get("resident_texture_count", 0)) >= int(
				snapshot.get("visible_required_texture_count", 0)
			)
			and not resident_paths.is_empty()
			and all_expected_visible_are_resident
			and all_expected_visible_assets_are_resident,
			(
				"Skrajna kamera %d musi sklasyfikować i osadzić widoczne tekstury przy produkcyjnym parallax."
				% edge_index
			),
		):
			await _dispose_manager(manager)
			_dispose_fixture(fixture)
			return false
		resident_sets.append(resident_paths)
	if not _require(
		resident_sets.size() == 2 and resident_sets[0] != resident_sets[1],
		"Lewy i prawy skraj kamery muszą wybrać różne zbiory rezydentne L01/L02.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	await _dispose_manager(manager)
	_dispose_fixture(fixture)
	return not _failed


func _test_poll_tick_advances_queued_requests(descriptors: Array) -> bool:
	var collocated: Array[Dictionary] = []
	for descriptor_value: Variant in descriptors:
		var descriptor := (descriptor_value as Dictionary).duplicate(true)
		var source_rect := descriptor.get("world_rect", Rect2()) as Rect2
		descriptor["world_rect"] = Rect2(Vector2.ZERO, source_rect.size)
		collocated.append(descriptor)
	var fixture := _create_fixture(collocated)
	if fixture.is_empty():
		return false
	await process_frame
	var profile = _new_profile()
	profile.prefetch_margin_viewports = 0.0
	profile.retention_margin_viewports = 0.5
	profile.max_in_flight_requests = 1
	profile.max_commits_per_tick = 1
	var manager = ResidencyScript.new()
	var errors: PackedStringArray = manager.configure(fixture["visual_layers"], profile)
	if not _require(errors.is_empty(), "Konfiguracja kolejki poll: %s" % str(errors)):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	var camera_position := Vector2(64.0, 64.0)
	_set_camera(fixture, camera_position, Vector2.ONE)
	await process_frame
	manager.invalidate_window()
	manager.update_window(camera_position, _visible_half_extent(fixture), true)
	var initial := manager.telemetry_snapshot()
	if not _require(
		int(initial.get("request_count", 0)) == 1
		and int(initial.get("in_flight_count", 0)) == 1,
		"Pierwszy tick ma wypełnić dokładnie jeden dozwolony slot requestu.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	var settled: Dictionary = {}
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < RESIDENCY_TIMEOUT_MSEC:
		manager.poll_pending_requests()
		var snapshot: Dictionary = manager.telemetry_snapshot()
		if bool(snapshot.get("settled", false)) and manager.is_visible_window_ready():
			settled = snapshot
			break
		await process_frame
	if not _require(
		not settled.is_empty()
		and int(settled.get("request_count", 0)) == collocated.size()
		and int(settled.get("terminal_request_count", 0)) == collocated.size()
		and int(settled.get("outstanding_request_count", -1)) == 0
		and int(settled.get("visible_missing_count", -1)) == 0,
		"Sam publiczny poll tick musi opróżnić całą kolejkę po zwolnieniu slotu.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	await _dispose_manager(manager)
	_dispose_fixture(fixture)
	return not _failed


func _test_sticky_failure(source_descriptor: Dictionary) -> bool:
	var synthetic_source := _synthetic_size_mismatch_stub(source_descriptor)
	var descriptor := {
		"asset_id": str(synthetic_source.get_meta("asset_id")),
		"layer_id": "L01",
		"path": str(synthetic_source.get_meta("resource_path")),
		"world_rect": synthetic_source.get_meta("world_rect") as Rect2,
		"pixel_size": synthetic_source.get_meta("pixel_size") as Vector2i,
		"scene_node": synthetic_source,
		"parallax_scale": Vector2.ONE,
	}
	var fixture := _create_fixture([descriptor])
	synthetic_source.free()
	if fixture.is_empty():
		return false
	await process_frame
	var profile = _new_profile()
	profile.prefetch_margin_viewports = 0.0
	profile.retention_margin_viewports = 0.5
	profile.max_in_flight_requests = 1
	var manager = ResidencyScript.new()
	var errors: PackedStringArray = manager.configure(fixture["visual_layers"], profile)
	if not _require(errors.is_empty(), "Konfiguracja sticky failure: %s" % str(errors)):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	var rect := descriptor["world_rect"] as Rect2
	_set_camera(fixture, rect.get_center(), Vector2.ONE)
	await process_frame
	manager.invalidate_window()
	manager.update_window(rect.get_center(), _visible_half_extent(fixture), true)
	var failed := await _wait_for_settled(manager, fixture, false, "sticky failure")
	if failed.is_empty():
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	if not _require(
		int(failed.get("failed_path_count", 0)) == 1
		and int(failed.get("visible_missing_count", 0)) == 1
		and not manager.is_visible_window_ready(),
		"Niezgodny rozmiar zasobu ma zakończyć się jawnym, widocznym failure.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	var request_count := int(failed.get("request_count", 0))
	var failure_count := int(failed.get("failure_count", 0))
	for _iteration in range(5):
		manager.update_window(rect.get_center(), _visible_half_extent(fixture), false)
		await process_frame
	var repeated := manager.telemetry_snapshot()
	if not _require(
		int(repeated.get("request_count", -1)) == request_count
		and int(repeated.get("failure_count", -1)) == failure_count
		and int(repeated.get("failed_path_count", 0)) == 1,
		"Failure ma być sticky i nie może generować kolejnych requestów.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	await _dispose_manager(manager)
	_dispose_fixture(fixture)
	return not _failed


func _test_visible_overcommit_keeps_frame_populated(descriptor: Dictionary) -> bool:
	var fixture := _create_fixture([descriptor])
	if fixture.is_empty():
		return false
	await process_frame
	var profile = _new_profile()
	profile.prefetch_margin_viewports = 0.0
	profile.retention_margin_viewports = 0.5
	profile.resident_pixel_budget = 1
	profile.max_in_flight_requests = 1
	var manager = ResidencyScript.new()
	var errors: PackedStringArray = manager.configure(fixture["visual_layers"], profile)
	if not _require(errors.is_empty(), "Konfiguracja visible overcommit: %s" % str(errors)):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	var rect := descriptor["world_rect"] as Rect2
	_set_camera(fixture, rect.get_center(), Vector2.ONE)
	await process_frame
	manager.invalidate_window()
	manager.update_window(rect.get_center(), _visible_half_extent(fixture), true)
	var snapshot := await _wait_for_settled(manager, fixture, true, "visible overcommit")
	if snapshot.is_empty():
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	if not _require(
		int(snapshot.get("visible_missing_count", -1)) == 0
		and int(snapshot.get("resident_texture_count", 0)) == 1
		and int(snapshot.get("budget_overcommit_pixels", 0)) > 0
		and _fixture_bitmap(fixture, str(descriptor["path"])).texture != null,
		"Widoczny zasób ponad budżet ma pozostać w kadrze i raportować overcommit.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	if not _require(
		int(snapshot.get("estimated_rgba8_bytes", -1))
		== int(snapshot.get("resident_pixels", 0)) * 4,
		"Telemetria RGBA8 musi odpowiadać rezydentnym pikselom.",
	):
		await _dispose_manager(manager)
		_dispose_fixture(fixture)
		return false
	await _dispose_manager(manager)
	_dispose_fixture(fixture)
	return not _failed


func _create_fixture(
	descriptors: Array,
	use_production_parallax: bool = false,
) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "VisualResidencyViewport"
	viewport.size = FIXTURE_VIEWPORT_SIZE
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var world := Node2D.new()
	world.name = "World"
	viewport.add_child(world)
	var visual_layers := Node2D.new()
	visual_layers.name = "VisualLayers"
	world.add_child(visual_layers)

	var layers := {}
	var groups := {}
	for layer_id in STREAMED_LAYER_IDS:
		var layer := Parallax2D.new()
		layer.name = layer_id
		var layer_scale := Vector2.ONE
		if use_production_parallax:
			layer_scale = _production_layer_scale(descriptors, layer_id)
			if layer_scale.x <= 0.0 or layer_scale.y <= 0.0:
				_fail("Brak spójnego produkcyjnego parallax_scale dla %s." % layer_id)
				viewport.free()
				return {}
		layer.scroll_scale = layer_scale
		layer.set_meta("parallax_scale", layer_scale)
		visual_layers.add_child(layer)
		var group := Node2D.new()
		group.name = "Elements"
		layer.add_child(group)
		layers[layer_id] = layer
		groups[layer_id] = group

	var bitmaps := {}
	var bitmap_by_asset_id := {}
	var nodes := {}
	for index in range(descriptors.size()):
		var descriptor_value: Variant = descriptors[index]
		if not descriptor_value is Dictionary:
			_fail("Fixture rezydencji otrzymał rekord inny niż Dictionary.")
			viewport.free()
			return {}
		var descriptor := descriptor_value as Dictionary
		var source_node := descriptor.get("scene_node") as Node2D
		var asset_id := str(descriptor.get("asset_id", ""))
		var layer_id := str(descriptor.get("layer_id", ""))
		var path := str(descriptor.get("path", ""))
		if (
			source_node == null
			or asset_id.is_empty()
			or bitmap_by_asset_id.has(asset_id)
			or not groups.has(layer_id)
			or path.is_empty()
		):
			_fail("Fixture rezydencji otrzymał niepełny deskryptor stuba.")
			viewport.free()
			return {}
		var clone := source_node.duplicate() as Node2D
		if clone == null:
			_fail("Nie można zduplikować scenowego stuba do fixture.")
			viewport.free()
			return {}
		clone.name = "Asset%04d" % index
		clone.position = (descriptor["world_rect"] as Rect2).position
		clone.rotation = 0.0
		clone.scale = Vector2.ONE
		clone.visible = true
		var bitmap := clone.get_node_or_null("Bitmap") as TextureRect
		if bitmap == null:
			_fail("Duplikat scenowego stuba nie zawiera Bitmap.")
			clone.free()
			viewport.free()
			return {}
		bitmap.texture = null
		(groups[layer_id] as Node).add_child(clone)
		bitmaps[path] = bitmap
		bitmap_by_asset_id[asset_id] = bitmap
		nodes[path] = clone

	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.position_smoothing_enabled = false
	camera.enabled = true
	world.add_child(camera)
	camera.make_current()
	return {
		"viewport": viewport,
		"world": world,
		"visual_layers": visual_layers,
		"camera": camera,
		"layers": layers,
		"bitmaps": bitmaps,
		"bitmap_by_asset_id": bitmap_by_asset_id,
		"nodes": nodes,
	}


func _synthetic_size_mismatch_stub(source_descriptor: Dictionary) -> Node2D:
	const ASSET_ID := "visual_residency_size_mismatch_fixture"
	var source_node := source_descriptor.get("scene_node") as Node2D
	var source_value: Variant = source_node.get_meta("source", {}) if source_node != null else {}
	var source: Dictionary = source_value as Dictionary if source_value is Dictionary else {}
	var resource_path: String = str(source_descriptor.get("path", ""))
	var relative_path: String = resource_path.trim_prefix(WORKBENCH_RESOURCE_ROOT)
	var actual_pixel_size: Vector2i = source_descriptor.get("pixel_size", Vector2i.ZERO) as Vector2i
	var pixel_size := actual_pixel_size + Vector2i(1, 0)
	var world_rect := Rect2(Vector2.ZERO, Vector2(pixel_size))
	var stub := Node2D.new()
	stub.name = "SyntheticSizeMismatchStub"
	stub.set_meta("asset_id", ASSET_ID)
	stub.set_meta("layer_id", "L01")
	stub.set_meta("residency_contract", STREAMED_CONTRACT)
	stub.set_meta("resource_path", resource_path)
	stub.set_meta("source_sha256", str(source.get("sha256", "")))
	stub.set_meta("pixel_size", pixel_size)
	stub.set_meta("world_rect", world_rect)
	stub.set_meta("kind", STREAMED_KIND)
	stub.set_meta("source", {
		"id": ASSET_ID,
		"layer_id": "L01",
		"group_id": "Elements",
		"kind": STREAMED_KIND,
		"path": relative_path,
		"sha256": str(source.get("sha256", "")),
		"pixel_size": [pixel_size.x, pixel_size.y],
		"world_rect": [world_rect.position.x, world_rect.position.y, world_rect.size.x, world_rect.size.y],
		"enabled": true,
	})
	var bitmap := TextureRect.new()
	bitmap.name = "Bitmap"
	bitmap.set_size(Vector2(pixel_size))
	bitmap.texture = null
	stub.add_child(bitmap)
	return stub


func _new_profile():
	var profile = ProfileScript.new()
	profile.prefetch_margin_viewports = 0.0
	profile.retention_margin_viewports = 0.5
	profile.resident_pixel_budget = 48_000_000
	profile.max_in_flight_requests = 1
	profile.max_commits_per_tick = 1
	return profile


func _wait_for_settled(
	manager,
	fixture: Dictionary,
	require_visible_ready: bool,
	label: String,
) -> Dictionary:
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < RESIDENCY_TIMEOUT_MSEC:
		manager.update_window(
			(fixture["camera"] as Camera2D).position,
			_visible_half_extent(fixture),
			false,
		)
		var snapshot: Dictionary = manager.telemetry_snapshot()
		if (
			bool(snapshot.get("settled", false))
			and int(snapshot.get("settled_generation", -1))
			>= int(snapshot.get("generation", 0))
			and int(snapshot.get("in_flight_count", -1)) == 0
			and (not require_visible_ready or manager.is_visible_window_ready())
		):
			return snapshot
		await process_frame
	_fail("Timeout rezydencji dla %s: %s" % [label, manager.telemetry_snapshot()])
	return {}


func _dispose_manager(manager) -> void:
	if manager == null:
		return
	manager.detach()
	var started_at := Time.get_ticks_msec()
	while int(manager.telemetry_snapshot().get("in_flight_count", 0)) > 0:
		manager.poll_pending_requests()
		if Time.get_ticks_msec() - started_at >= RESIDENCY_TIMEOUT_MSEC:
			_fail("Timeout podczas terminalnego odbioru żądań po detach.")
			return
		await process_frame


func _dispose_fixture(fixture: Dictionary) -> void:
	var viewport := fixture.get("viewport") as SubViewport
	if viewport == null or not is_instance_valid(viewport):
		return
	if viewport.get_parent() != null:
		viewport.get_parent().remove_child(viewport)
	viewport.free()


func _set_camera(fixture: Dictionary, position: Vector2, zoom: Vector2) -> void:
	var camera := fixture["camera"] as Camera2D
	camera.position = position
	camera.zoom = zoom
	camera.force_update_scroll()


func _visible_half_extent(fixture: Dictionary) -> Vector2:
	var viewport_size := Vector2((fixture["viewport"] as SubViewport).size)
	var zoom := (fixture["camera"] as Camera2D).zoom
	return Vector2(
		viewport_size.x / zoom.x,
		viewport_size.y / zoom.y,
	) * 0.5


func _fixture_bitmap(fixture: Dictionary, path: String) -> TextureRect:
	return (fixture["bitmaps"] as Dictionary).get(path) as TextureRect


func _resident_fixture_paths(fixture: Dictionary) -> PackedStringArray:
	var paths := PackedStringArray()
	for path_value in (fixture["bitmaps"] as Dictionary).keys():
		var path := str(path_value)
		var bitmap := _fixture_bitmap(fixture, path)
		if bitmap != null and bitmap.texture != null:
			paths.append(path)
	paths.sort()
	return paths


func _all_fixture_bitmaps_are_null(fixture: Dictionary) -> bool:
	for bitmap_value in (fixture["bitmaps"] as Dictionary).values():
		var bitmap := bitmap_value as TextureRect
		if bitmap == null or bitmap.texture != null:
			return false
	return true


func _production_layer_scale(descriptors: Array, layer_id: String) -> Vector2:
	var result := Vector2.ZERO
	for descriptor_value: Variant in descriptors:
		if not descriptor_value is Dictionary:
			continue
		var descriptor := descriptor_value as Dictionary
		if str(descriptor.get("layer_id", "")) != layer_id:
			continue
		var scale := descriptor.get("parallax_scale", Vector2.ZERO) as Vector2
		if result == Vector2.ZERO:
			result = scale
		elif not result.is_equal_approx(scale):
			return Vector2.ZERO
	return result


func _expected_visible_paths_by_layer(
	descriptors: Array[Dictionary],
	camera_position: Vector2,
	visible_half_extent: Vector2,
) -> Dictionary:
	var result := {
		"L01": PackedStringArray(),
		"L02": PackedStringArray(),
	}
	for descriptor in descriptors:
		var layer_id := str(descriptor.get("layer_id", ""))
		if not result.has(layer_id):
			continue
		var scale := descriptor.get("parallax_scale", Vector2.ONE) as Vector2
		var source_viewport := Rect2(
			camera_position * scale - visible_half_extent,
			visible_half_extent * 2.0,
		)
		var world_rect := descriptor.get("world_rect", Rect2()) as Rect2
		if source_viewport.intersects(world_rect, true):
			var paths := result[layer_id] as PackedStringArray
			paths.append(str(descriptor.get("path", "")))
			result[layer_id] = paths
	for layer_id in STREAMED_LAYER_IDS:
		var paths := result[layer_id] as PackedStringArray
		paths.sort()
		result[layer_id] = paths
	return result


func _expected_visible_asset_ids_by_layer(
	descriptors: Array[Dictionary],
	camera_position: Vector2,
	visible_half_extent: Vector2,
) -> Dictionary:
	var result := {
		"L01": PackedStringArray(),
		"L02": PackedStringArray(),
	}
	for descriptor in descriptors:
		var layer_id := str(descriptor.get("layer_id", ""))
		if not result.has(layer_id):
			continue
		var scale := descriptor.get("parallax_scale", Vector2.ONE) as Vector2
		var source_viewport := Rect2(
			camera_position * scale - visible_half_extent,
			visible_half_extent * 2.0,
		)
		var world_rect := descriptor.get("world_rect", Rect2()) as Rect2
		if source_viewport.intersects(world_rect, true):
			var asset_ids := result[layer_id] as PackedStringArray
			asset_ids.append(str(descriptor.get("asset_id", "")))
			result[layer_id] = asset_ids
	for layer_id in STREAMED_LAYER_IDS:
		var asset_ids := result[layer_id] as PackedStringArray
		asset_ids.sort()
		result[layer_id] = asset_ids
	return result


func _select_spread(
	descriptors: Array[Dictionary],
	count: int,
) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	if count <= 0 or descriptors.size() < count:
		return selected
	if count == 1:
		selected.append(descriptors[int(descriptors.size() / 2.0)])
		return selected
	var used_paths := {}
	for selection_index in range(count):
		var source_index := int(round(
			float(selection_index) * float(descriptors.size() - 1) / float(count - 1)
		))
		var descriptor := descriptors[source_index]
		var path := str(descriptor.get("path", ""))
		if path.is_empty() or used_paths.has(path):
			return []
		used_paths[path] = true
		selected.append(descriptor)
	return selected


func _unique_path_descriptors(
	descriptors: Array[Dictionary],
) -> Array[Dictionary]:
	var unique: Array[Dictionary] = []
	var seen := {}
	for descriptor in descriptors:
		var path := str(descriptor.get("path", ""))
		if path.is_empty() or seen.has(path):
			continue
		seen[path] = true
		unique.append(descriptor)
	return unique


func _descriptor_before(left: Dictionary, right: Dictionary) -> bool:
	var left_rect := left.get("world_rect", Rect2()) as Rect2
	var right_rect := right.get("world_rect", Rect2()) as Rect2
	var left_center := left_rect.get_center()
	var right_center := right_rect.get_center()
	if not is_equal_approx(left_center.x, right_center.x):
		return left_center.x < right_center.x
	if not is_equal_approx(left_center.y, right_center.y):
		return left_center.y < right_center.y
	return str(left.get("path", "")) < str(right.get("path", ""))


func _canonical_resource_path(relative_path: String) -> String:
	var normalized := relative_path.strip_edges().replace("\\", "/").simplify_path()
	while normalized.begins_with("/"):
		normalized = normalized.substr(1)
	if normalized.is_empty() or normalized == "." or normalized.begins_with("../"):
		return ""
	return WORKBENCH_RESOURCE_ROOT + normalized


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("Brak pliku JSON: %s." % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Nie można otworzyć JSON %s (error %d)." % [path, FileAccess.get_open_error()])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_fail("Plik %s nie jest obiektem JSON." % path)
		return {}
	return parsed as Dictionary


func _vector2i(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Vector2:
		return Vector2i(value as Vector2)
	if not value is Array or (value as Array).size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(value[0]), int(value[1]))


func _vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Vector2i:
		return Vector2(value as Vector2i)
	if not value is Array or (value as Array).size() != 2:
		return Vector2.ZERO
	return Vector2(float(value[0]), float(value[1]))


func _rect(value: Variant) -> Rect2:
	if value is Rect2:
		return value as Rect2
	if value is Rect2i:
		return Rect2(value as Rect2i)
	if not value is Array or (value as Array).size() != 4:
		return Rect2(Vector2(INF, INF), Vector2.ZERO)
	return Rect2(
		float(value[0]),
		float(value[1]),
		float(value[2]),
		float(value[3]),
	)


func _positive_finite_rect(rect: Rect2) -> bool:
	return (
		rect.position.is_finite()
		and rect.size.is_finite()
		and rect.size.x > 0.0
		and rect.size.y > 0.0
	)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _fail(message: String) -> void:
	_failed = true
	push_error("Underwater map visual residency test failed: " + message)


func _finish() -> void:
	if _generated_map != null and is_instance_valid(_generated_map):
		_generated_map.free()
	_generated_map = null
	if _failed:
		quit(1)
		return
	print(
		"Underwater map visual residency test passed: dynamic L01/L02 stubs, partial residency, retention/eviction, stale loaded/failed/invalid requests, reconfigure, production parallax extremes, transforms, sticky failure and visible overcommit."
	)
	quit(0)
