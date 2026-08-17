extends SceneTree

const RuntimeMapScript := preload("res://scripts/diving/UnderwaterMapRuntime.gd")
const MapCompilerScript := preload("res://scripts/diving/UnderwaterMapSceneCompiler.gd")
const MANIFEST_PATH := "res://assets/diving/world/map_v2/visual_chunks/map_visual_chunks_v2.json"
const FROZEN_V1_MANIFEST_PATH := "res://assets/diving/world/map_v2/visual_chunks/map_visual_chunks_v1.json"
const FROZEN_V1_SHA256 := "6d4d53bc005a7866d5e3597ca3e62840716260cdcf0eaa6dec906c6a40d8fcb6"
const COMPOSITION_SCENE_PATH := "res://scenes/diving/map_visuals/UnderwaterMapSixLayerVisuals.tscn"
const LAYER_ELEMENT_TEMPLATE_PATH := "res://scenes/diving/map_visuals/LayerVisualElement.tscn"
const NEGATIVE_MAPPING_TEXTURE_PATH := "res://assets/diving/world/map_v2/visual_chunks/environment_decoration/chunk_04_01.png"
const MASTER_ENVIRONMENT_PATH := "res://assets/diving/world/map_v2/visuals/duzaMapaEnvironmentDecorationLayer-v3.png"
const EXPECTED_LAYER_IDS := [
	"L00_base_color",
	"L01_ultra_far_silhouettes",
	"L02_far_structures",
	"L03_mid_drift_props",
	"L04_near_terrain_skin",
	"L05_foreground_occluders",
]
const EXPECTED_LAYER_ROLES := [
	"base_color",
	"ultra_far_silhouettes",
	"far_structures",
	"mid_drift_props",
	"near_terrain_skin",
	"foreground_occluders",
]
const FORBIDDEN_MANIFEST_TRANSFORM_FIELDS := [
	"position",
	"rotation",
	"rotation_degrees",
	"scale",
	"skew",
	"transform",
	"transform_2d",
	"z_index",
]


class FailureTerminalStreamer:
	extends DiveVisualChunkStreamer

	var request_calls := 0


	func _request_entry(entry: Dictionary) -> void:
		var key := str(entry.get("key", ""))
		if not _begin_entry_request(key):
			return
		request_calls += 1
		_mark_entry_failed(key, _request_generation)


class SilentManifestFailureStreamer:
	extends DiveVisualChunkStreamer

	var reported_failures := 0


	func _fail_manifest(message: String) -> void:
		reported_failures += 1
		if _manifest_error.is_empty():
			_manifest_error = message
		elif not _manifest_error.contains(message):
			_manifest_error += "\n" + message
		_manifest_loaded = false


var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var frozen_v1 := _load_manifest(FROZEN_V1_MANIFEST_PATH)
	_assert(not frozen_v1.is_empty(), "Zamrożony manifest v1 powinien pozostać poprawnym JSON-em.")
	_validate_frozen_v1_contract(frozen_v1)
	var manifest := _load_manifest(MANIFEST_PATH)
	_assert(not manifest.is_empty(), "Pochodny manifest sześciu warstw powinien być poprawnym JSON-em.")
	_validate_manifest_contract(manifest, frozen_v1)

	MapCompilerScript.clear_runtime_caches()
	_assert(not ResourceLoader.has_cached(MASTER_ENVIRONMENT_PATH), "Test nie moze startowac z pelna warstwa dekoracji w cache.")

	var dive_map = RuntimeMapScript.new()
	root.add_child(dive_map)
	await process_frame
	var streamer := dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/VisualChunkStreamer") as DiveVisualChunkStreamer
	_assert(streamer != null, "Runtime powinien utworzyc streamer prezentacyjnych chunkow.")
	if streamer == null:
		_finish()
		return

	_assert(streamer.manifest_loaded(), "Streamer powinien zaakceptowac wersjonowany manifest.")
	_assert(streamer.manifest_entry_count() == 15, "Streamer powinien widziec dokladnie niepuste cropy dekoracji srodowiska.")
	_assert(not ResourceLoader.has_cached(MASTER_ENVIRONMENT_PATH), "Instancjowanie mapy nie moze zaladowac pelnej warstwy dekoracji.")

	var first_position := Vector2(2_500.0, 1_500.0)
	var stack := dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/SixLayerVisuals") as DiveVisualLayerStack
	var edited_element: DiveVisualLayerElement
	if stack != null:
		var authored_root := stack.content_root(&"L02_far_structures", &"world", &"authored")
		for child in authored_root.get_children():
			if child is DiveVisualLayerElement:
				edited_element = child as DiveVisualLayerElement
				break
	_assert(edited_element != null, "Test streamingu wymaga niezależnego elementu scenowego L02.")
	_assert(edited_element == null or edited_element.is_manifest_streamed(), "Element obsługiwany przez manifest v2 musi jawnie używać trybu Manifest Streamed.")
	var edited_element_id := ""
	var edited_transform := Transform2D.IDENTITY
	if edited_element != null:
		edited_element_id = str(edited_element.element_id)
		edited_element.position = first_position
		edited_element.rotation = 0.19
		edited_element.scale = Vector2(1.23, 0.81)
		edited_transform = edited_element.transform
	streamer.update_streaming(first_position, Vector2(320.0, 240.0), true)
	await _wait_until_idle(streamer)
	var first_keys := streamer.loaded_chunk_keys()
	_assert(not first_keys.is_empty(), "Widok przy niepustym obszarze powinien materializowac przynajmniej jeden crop.")
	_assert(first_keys.size() < streamer.manifest_entry_count(), "Pierwszy widok nie moze materializowac calego manifestu.")
	_assert(edited_element_id.is_empty() or first_keys.has(edited_element_id), "Streaming i culling muszą korzystać ze zmienionej pozycji scenowego elementu, a nie historycznego world_rect manifestu.")
	if not edited_element_id.is_empty() and first_keys.has(edited_element_id):
		var edited_state := streamer.chunk_state(edited_element_id)
		var edited_runtime_node := edited_state.get("node") as Node2D
		_assert(edited_state.get("element") == edited_element, "Stan streamera musi zachować scenowy element jako authority transformacji.")
		_assert(edited_element.transform.is_equal_approx(edited_transform), "Asynchroniczne podpięcie grafiki nie może nadpisać pozycji, obrotu ani rozciągnięcia elementu.")
		_assert(edited_runtime_node != null and edited_runtime_node.get_parent() == edited_element.get_node_or_null("Attachment") and edited_runtime_node.position.is_equal_approx(edited_element.visual_local_bounds().position), "Wczytana grafika ma być lokalnym dzieckiem Attachment scenowego elementu i dziedziczyć jego transformację.")
	_validate_loaded_nodes(streamer, first_keys)

	var distant_position := Vector2(7_250.0, 5_900.0)
	streamer.update_streaming(distant_position, Vector2(320.0, 240.0), true)
	await _wait_until_idle(streamer)
	var distant_keys := streamer.loaded_chunk_keys()
	_assert(not distant_keys.is_empty(), "Prefetch odleglego niepustego obszaru powinien materializowac jego cropy.")
	var retained_overlap := 0
	for key in first_keys:
		if distant_keys.has(key):
			retained_overlap += 1
	_assert(retained_overlap == 0, "Daleki skok powinien odpiac stare cropy po przekroczeniu histerezy.")
	_assert(not ResourceLoader.has_cached(MASTER_ENVIRONMENT_PATH), "Streaming cropow nie moze posrednio zaladowac mastera dekoracji.")
	_test_unregistered_manifest_streamed_element_is_rejected(streamer, stack)
	_test_failed_desired_entry_is_terminal_per_residence()
	_test_manifest_failure_requires_explicit_retry()
	await _test_stale_pending_generation_rearms_culling()

	dive_map.queue_free()
	await process_frame
	_finish()


func _load_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _test_unregistered_manifest_streamed_element_is_rejected(
	streamer: DiveVisualChunkStreamer,
	stack: DiveVisualLayerStack
) -> void:
	if streamer == null or stack == null:
		return
	var template := ResourceLoader.load(LAYER_ELEMENT_TEMPLATE_PATH) as PackedScene
	_assert(template != null, "Test negatywny mapowania wymaga szablonu elementu warstwy.")
	if template == null:
		return
	var extra_element := template.instantiate() as DiveVisualLayerElement
	_assert(extra_element != null, "Szablon elementu warstwy musi tworzyć DiveVisualLayerElement.")
	if extra_element == null:
		return
	extra_element.element_id = &"unregistered_manifest_streamed_test"
	extra_element.resource_path = NEGATIVE_MAPPING_TEXTURE_PATH
	extra_element.load_policy = DiveVisualLayerElement.LoadPolicy.MANIFEST_STREAMED
	extra_element.local_bounds = Rect2(0.0, 0.0, 620.0, 167.0)
	var authored_root := stack.content_root(&"L03_mid_drift_props", &"parallax", &"authored")
	_assert(authored_root != null, "Test negatywny mapowania wymaga bucketu L03/ParallaxContent/Authored.")
	if authored_root == null:
		extra_element.free()
		return
	authored_root.add_child(extra_element)
	var mapping_errors := streamer.scene_manifest_mapping_errors()
	var unregistered_rejected := false
	for mapping_error in mapping_errors:
		if (
			String(mapping_error).contains(String(extra_element.element_id))
			and String(mapping_error).contains("dokładnie jednego wpisu manifestu v2")
		):
			unregistered_rejected = true
			break
	_assert(
		unregistered_rejected,
		"Szesnasty element Manifest Streamed bez wpisu v2 musi zostać jawnie odrzucony."
	)
	authored_root.remove_child(extra_element)
	extra_element.free()


func _test_failed_desired_entry_is_terminal_per_residence() -> void:
	var streamer := FailureTerminalStreamer.new()
	streamer._manifest_loaded = true
	streamer._grid_chunk_size = 32
	var failed_key := "synthetic_failed_entry"
	streamer._entries_by_key[failed_key] = {
		"key": failed_key,
		"path": "res://synthetic_failure_never_reaches_resource_loader.png",
		"runtime_parent": "Synthetic",
		"_legacy_world_rect": Rect2(-8.0, -8.0, 16.0, 16.0),
		"_texture_region": Rect2(0.0, 0.0, 16.0, 16.0),
		"_source_rect": Rect2(0.0, 0.0, 16.0, 16.0),
	}
	var stale_node := Node2D.new()
	streamer.add_child(stale_node)
	streamer._loaded_nodes["synthetic_stale_entry"] = stale_node
	root.add_child(streamer)

	streamer.update_streaming(Vector2.ZERO, Vector2(4.0, 4.0), true)
	_assert(streamer.request_calls == 1, "Pierwsze wejście elementu w prefetch powinno wykonać dokładnie jedną próbę wczytania.")
	_assert(streamer.failed_chunk_keys() == [failed_key], "Błąd powinien być terminalny dla bieżącego pobytu elementu w desired.")
	_assert(streamer.request_attempt_count(failed_key) == 1, "Licznik prób powinien osiągnąć bezpieczny limit jednego żądania na pobyt.")
	_assert(not streamer.loaded_chunk_keys().has("synthetic_stale_entry"), "Terminalny błąd desired nie może blokować odpięcia starego elementu poza histerezą.")

	for _repeat in range(4):
		streamer.update_streaming(Vector2.ZERO, Vector2(4.0, 4.0), true)
	_assert(streamer.request_calls == 1, "Wymuszona aktualizacja w kolejnych klatkach nie może ponawiać tego samego błędu.")
	_assert(streamer.request_attempt_count(failed_key) == 1, "Limit prób musi pozostać stabilny, dopóki element nie opuści desired.")

	streamer.update_streaming(Vector2(256.0, 0.0), Vector2(4.0, 4.0), true)
	_assert(streamer.failed_chunk_keys().is_empty(), "Wyjście elementu z desired powinno wyczyścić terminalny błąd.")
	_assert(streamer.request_attempt_count(failed_key) == 0, "Wyjście z desired powinno wyzerować budżet próby przed ponownym wejściem.")
	streamer.update_streaming(Vector2.ZERO, Vector2(4.0, 4.0), true)
	_assert(streamer.request_calls == 2, "Ponowne wejście do desired powinno dostać jeden nowy, ograniczony retry.")

	streamer.set_graphics_quality("medium")
	_assert(streamer.failed_chunk_keys().is_empty(), "Unieważnienie cullingu powinno wyczyścić błędy starej generacji.")
	_assert(streamer.request_attempt_count(failed_key) == 0, "Nowa generacja powinna otrzymać świeży budżet próby.")
	streamer.update_streaming(Vector2.ZERO, Vector2(4.0, 4.0), true)
	_assert(streamer.request_calls == 3, "Pierwsza aktualizacja nowej generacji powinna wykonać dokładnie jedną nową próbę.")

	streamer.update_streaming(Vector2(256.0, 0.0), Vector2(4.0, 4.0), true)
	streamer._entries_by_key.erase(failed_key)
	streamer.queue_free()


func _test_manifest_failure_requires_explicit_retry() -> void:
	# Spodziewany negatywny przypadek używa cichego adaptera: rygorystyczny
	# runner traktuje każde push_error jako porażkę, także gdy test go oczekuje.
	var streamer := SilentManifestFailureStreamer.new()
	streamer.manifest_path = MANIFEST_PATH
	var deliberately_wrong_world_size := Vector2(1.0, 1.0)
	streamer.configure(null, deliberately_wrong_world_size)
	_assert(not streamer.manifest_loaded(), "Niezgodny expected_world_size musi terminalnie odrzucić manifest.")
	_assert(streamer.manifest_load_attempt_count() == 1, "Pierwsza konfiguracja powinna wykonać jedną próbę manifestu.")
	_assert(streamer.reported_failures == 1, "Pierwsza niezgodność manifestu powinna zostać zgłoszona dokładnie raz.")
	_assert(streamer._expected_world_size.is_equal_approx(deliberately_wrong_world_size), "Streamer musi zapamiętać expected_world_size przekazany przez właściciela.")
	_assert(streamer.manifest_error().contains("zamiast"), "Niezgodny rozmiar świata musi dać jednoznaczny błąd manifestu.")
	var stable_error := streamer.manifest_error()
	for _repeat in range(4):
		streamer.update_streaming(Vector2.ZERO, Vector2(4.0, 4.0), true)
	_assert(streamer.manifest_load_attempt_count() == 1, "Terminalny błąd manifestu nie może powodować ponownego odczytu co klatkę.")
	_assert(streamer.reported_failures == 1, "Aktualizacje klatek nie mogą ponownie zgłaszać terminalnego błędu manifestu.")
	_assert(streamer.manifest_error() == stable_error, "Zwykłe aktualizacje nie mogą mnożyć tego samego błędu manifestu.")
	_assert(not streamer.retry_manifest_load(), "Jawny retry nadal musi respektować zapamiętany expected_world_size.")
	_assert(streamer.manifest_load_attempt_count() == 2, "Tylko jawny retry powinien rozpocząć kolejną próbę manifestu.")
	_assert(streamer.reported_failures == 2, "Jawny retry może zgłosić dokładnie jedną nową porażkę.")
	streamer.free()


func _test_stale_pending_generation_rearms_culling() -> void:
	var isolated_viewport := SubViewport.new()
	isolated_viewport.size = Vector2i(64, 64)
	var visual_layers := Node2D.new()
	var legacy_root := Node2D.new()
	legacy_root.name = &"EnvironmentDecoration"
	var streamer := DiveVisualChunkStreamer.new()
	streamer.name = &"VisualChunkStreamer"
	streamer._manifest_loaded = true
	streamer._manifest_load_attempted = true
	streamer._manifest_schema = 1
	streamer._grid_chunk_size = 32
	var pending_key := "synthetic_stale_generation"
	streamer._entries_by_key[pending_key] = {
		"key": pending_key,
		"path": NEGATIVE_MAPPING_TEXTURE_PATH,
		"runtime_parent": "EnvironmentDecoration",
		"_legacy_world_rect": Rect2(-8.0, -8.0, 16.0, 16.0),
		"_texture_region": Rect2(0.0, 0.0, 16.0, 16.0),
		"_source_rect": Rect2(0.0, 0.0, 16.0, 16.0),
	}
	visual_layers.add_child(legacy_root)
	visual_layers.add_child(streamer)
	isolated_viewport.add_child(visual_layers)
	root.add_child(isolated_viewport)
	_assert(streamer.get_viewport().get_camera_2d() == null, "Regresja starej generacji musi być sprawdzana bez Camera2D.")

	var stationary_position := Vector2.ZERO
	var stationary_extent := Vector2(4.0, 4.0)
	streamer.update_streaming(stationary_position, stationary_extent, true)
	_assert(streamer.pending_chunk_keys() == [pending_key], "Fixture musi rozpocząć dokładnie jedno żądanie starej generacji.")
	streamer.set_reduced_motion(true)
	streamer.update_streaming(stationary_position, stationary_extent)
	_assert(streamer.request_attempt_count(pending_key) == 0, "Aktualizacja nowej generacji nie może policzyć starego pending jako świeżej próby.")
	await _wait_until_idle(streamer)
	_assert(not streamer.loaded_chunk_keys().has(pending_key), "Zasób ukończony w starej generacji nie może zostać podpięty.")

	streamer.update_streaming(stationary_position, stationary_extent)
	_assert(streamer.request_attempt_count(pending_key) == 1, "Ukończenie starego pending musi odblokować identyczny update bez kamery i ponownie zażądać elementu.")
	await _wait_until_idle(streamer)
	_assert(streamer.loaded_chunk_keys().has(pending_key), "Ponowne żądanie bieżącej generacji powinno podpiąć element.")
	isolated_viewport.queue_free()
	await process_frame


func _validate_manifest_contract(manifest: Dictionary, frozen_v1: Dictionary) -> void:
	_assert(int(manifest.get("schema_version", 0)) == 2, "Aktywny manifest powinien używać schematu v2.")
	_assert(str(manifest.get("transform_authority", "")) == "composition_scene_only", "Pozycja, obrót i skala elementów muszą należeć wyłącznie do sceny kompozycji.")
	var world_size: Array = manifest.get("world_size", [])
	_assert(world_size.size() == 2 and int(world_size[0]) == 11_520 and int(world_size[1]) == 6_480, "Manifest v2 powinien zachować kanoniczny obszar świata.")
	var composition: Dictionary = manifest.get("composition_scene", {})
	_assert(str(composition.get("path", "")) == COMPOSITION_SCENE_PATH, "Manifest v2 musi wskazywać kanoniczną scenę sześciu warstw.")
	_assert(str(composition.get("sha256", "")).to_lower() == FileAccess.get_sha256(COMPOSITION_SCENE_PATH).to_lower(), "Manifest v2 musi odpowiadać bieżącym bajtom sceny kompozycji.")
	var layers: Array = manifest.get("layers", [])
	_assert(layers.size() == EXPECTED_LAYER_IDS.size(), "Manifest v2 musi zawierać dokładnie sześć profili warstw.")
	var actual_layer_ids: Array[String] = []
	var profile_paths := {}
	for layer_index in range(layers.size()):
		var layer_variant = layers[layer_index]
		_assert(layer_variant is Dictionary, "Każdy rekord warstwy v2 musi być słownikiem.")
		if not (layer_variant is Dictionary):
			continue
		var layer: Dictionary = layer_variant
		var layer_id := str(layer.get("id", ""))
		actual_layer_ids.append(layer_id)
		_assert(layer_index < EXPECTED_LAYER_ROLES.size() and str(layer.get("role", "")) == EXPECTED_LAYER_ROLES[layer_index], "Każda warstwa manifestu musi zachować własną rolę L00-L05.")
		var profile_path := str(layer.get("profile_path", ""))
		_assert(not profile_path.is_empty() and not profile_paths.has(profile_path), "Każda z sześciu warstw musi mieć odrębny profil.")
		profile_paths[profile_path] = true
		_assert(FileAccess.file_exists(profile_path), "Profil warstwy musi istnieć: %s." % profile_path)
		_assert(str(layer.get("profile_sha256", "")).to_lower() == FileAccess.get_sha256(profile_path).to_lower(), "Manifest musi utrwalać bieżący hash profilu: %s." % profile_path)
	_assert(actual_layer_ids == EXPECTED_LAYER_IDS, "Manifest v2 musi zachować stabilną kolejność L00-L05.")
	var payloads: Array = manifest.get("payloads", [])
	_assert(payloads.size() == 1 and payloads[0] is Dictionary, "Manifest v2 powinien adoptować dokładnie jeden legacy payload.")
	if payloads.size() != 1 or not (payloads[0] is Dictionary):
		return
	var payload: Dictionary = payloads[0]
	_assert(str(payload.get("id", "")) == "legacy_environment_decoration" and str(payload.get("mode", "")) == "adopt_verify_only", "Istniejące cropy mogą być wyłącznie zweryfikowane i adoptowane bez regeneracji.")
	_assert(str(payload.get("target_layer", "")) == "L02_far_structures", "Piętnaście istniejących cropów musi należeć do L02.")
	_assert(str(payload.get("placement_authority", "")) == "composition_scene_elements", "Runtime placement elementów musi pochodzić ze sceny, nie z manifestu.")
	_assert(str(payload.get("legacy_rects_authority", "")) == "integrity_and_migration_only", "Legacy world_rect może służyć tylko integralności i migracji.")
	var source_manifest: Dictionary = payload.get("source_manifest", {})
	_assert(str(source_manifest.get("path", "")) == FROZEN_V1_MANIFEST_PATH, "Payload v2 musi jawnie wskazywać zamrożony manifest v1.")
	_assert(str(source_manifest.get("sha256", "")).to_lower() == FROZEN_V1_SHA256, "Payload v2 musi utrwalać hash zamrożonego manifestu v1.")
	var legacy_chunks_by_key := {}
	var legacy_layers: Array = frozen_v1.get("layers", [])
	if legacy_layers.size() == 1 and legacy_layers[0] is Dictionary:
		for chunk_variant in (legacy_layers[0] as Dictionary).get("chunks", []):
			if chunk_variant is Dictionary:
				legacy_chunks_by_key[str((chunk_variant as Dictionary).get("key", ""))] = chunk_variant
	var elements: Array = payload.get("elements", [])
	_assert(elements.size() == 15, "Payload v2 musi adoptować dokładnie piętnaście istniejących cropów jako niezależne elementy.")
	for element_variant in elements:
		_assert(element_variant is Dictionary, "Każdy adoptowany element musi być słownikiem.")
		if not (element_variant is Dictionary):
			continue
		var element: Dictionary = element_variant
		for forbidden_field in FORBIDDEN_MANIFEST_TRANSFORM_FIELDS:
			_assert(not element.has(forbidden_field), "Manifest nie może dublować scenowej transformacji elementu: %s." % forbidden_field)
		var key := str(element.get("key", ""))
		_assert(legacy_chunks_by_key.has(key), "Każdy element v2 musi pochodzić z zamrożonego cropa v1: %s." % key)
		if legacy_chunks_by_key.has(key):
			var legacy: Dictionary = legacy_chunks_by_key[key]
			for frozen_field in ["path", "sha256", "coord", "source_rect", "texture_region", "world_rect"]:
				_assert(element.get(frozen_field) == legacy.get(frozen_field), "Adoptowany element %s musi zachować pole integralności %s z v1." % [key, frozen_field])


func _validate_frozen_v1_contract(manifest: Dictionary) -> void:
	_assert(FileAccess.get_sha256(FROZEN_V1_MANIFEST_PATH).to_lower() == FROZEN_V1_SHA256, "Manifest v1 i jego historyczne recty muszą pozostać bitowo zamrożone.")
	_assert(int(manifest.get("schema_version", 0)) == 1, "Manifest powinien miec jawna wersje kontraktu.")
	var world_size: Array = manifest.get("world_size", [])
	_assert(
		world_size.size() == 2 and int(world_size[0]) == 11_520 and int(world_size[1]) == 6_480,
		"Manifest powinien zachowac kanoniczny obszar swiata."
	)
	_assert(int(manifest.get("grid_chunk_size", 0)) == 1024, "Pochodne cropy powinny uzywac deterministycznej siatki 1024 px.")
	var layers: Array = manifest.get("layers", [])
	_assert(layers.size() == 1, "Manifest powinien opisywac tylko warstwe dekoracji srodowiska.")
	var keys := {}
	var total_chunks := 0
	var total_decoded_rgba := 0
	for layer_variant in layers:
		if not (layer_variant is Dictionary):
			_assert(false, "Kazda warstwa manifestu powinna byc slownikiem.")
			continue
		var layer: Dictionary = layer_variant
		var master_path := str(layer.get("source_path", ""))
		_assert(master_path == MASTER_ENVIRONMENT_PATH, "Manifest powinien wskazywac tylko master dekoracji srodowiska.")
		var source_sha256 := str(layer.get("source_sha256", "")).to_lower()
		_assert(source_sha256.length() == 64, "Manifest powinien unieruchomic bajty mastera przez SHA-256.")
		if FileAccess.file_exists(master_path):
			_assert(
				FileAccess.get_sha256(master_path).to_lower() == source_sha256,
				"Manifest powinien odpowiadac rzeczywistym bajtom mastera: %s." % master_path
			)
		else:
			_assert(
				bool(layer.get("source_archived", false)),
				"Brakujacy master dekoracji musi byc jawnie oznaczony jako zarchiwizowany."
			)
		var chunks: Array = layer.get("chunks", [])
		total_chunks += chunks.size()
		total_decoded_rgba += int(layer.get("generated_decoded_rgba_bytes", 0))
		for chunk_variant in chunks:
			var chunk: Dictionary = chunk_variant
			var key := str(chunk.get("key", ""))
			var path := str(chunk.get("path", ""))
			_assert(not key.is_empty() and not keys.has(key), "Kazdy crop powinien miec unikalny klucz.")
			keys[key] = true
			_assert(path.begins_with("res://assets/diving/world/map_v2/visual_chunks/"), "Runtime path powinien prowadzic tylko do pochodnego katalogu chunkow.")
			_assert(FileAccess.file_exists(path), "Kazdy wpis manifestu powinien miec fizyczny PNG: %s." % path)
			var chunk_sha256 := str(chunk.get("sha256", "")).to_lower()
			_assert(
				chunk_sha256.length() == 64 and FileAccess.get_sha256(path).to_lower() == chunk_sha256,
				"Manifest powinien odpowiadac rzeczywistym bajtom cropa: %s." % path
			)
			var world_rect: Array = chunk.get("world_rect", [])
			var texture_region: Array = chunk.get("texture_region", [])
			_assert(world_rect.size() == 4 and texture_region.size() == 4, "Crop powinien miec jawne world_rect i texture_region.")
			if world_rect.size() == 4:
				_assert(float(world_rect[0]) >= 0.0 and float(world_rect[1]) >= 0.0, "Crop nie moze zaczynac sie poza mapa.")
				_assert(float(world_rect[0]) + float(world_rect[2]) <= 11_520.0, "Crop nie moze wychodzic poza prawa krawedz.")
				_assert(float(world_rect[1]) + float(world_rect[3]) <= 6_480.0, "Crop nie moze wychodzic poza dolna krawedz.")
	_assert(total_chunks == 15, "Puste komorki siatki powinny byc pominiete; fixture zawiera 15 cropow dekoracji.")
	_assert(total_decoded_rgba < 4 * 1024 * 1024, "Komplet pochodnych cropow dekoracji powinien miec mniej niz 4 MiB decoded RGBA.")


func _wait_until_idle(streamer: DiveVisualChunkStreamer) -> void:
	for _frame in range(180):
		if streamer.pending_chunk_keys().is_empty():
			return
		await process_frame
	_assert(false, "Asynchroniczne wczytywanie cropow powinno zakonczyc sie w 180 klatkach testu.")


func _validate_loaded_nodes(streamer: DiveVisualChunkStreamer, keys: Array[String]) -> void:
	for key in keys:
		var state := streamer.chunk_state(key)
		var element := state.get("element") as DiveVisualLayerElement
		var node := state.get("node") as Sprite2D
		_assert(element != null, "Załadowany klucz powinien wskazywać scenowy DiveVisualLayerElement.")
		_assert(node != null, "Załadowany klucz powinien mieć runtime Sprite2D.")
		if element == null or node == null:
			continue
		var authored_bounds: Rect2 = state.get("authored_bounds", Rect2())
		var legacy_world_rect: Rect2 = state.get("legacy_world_rect", Rect2())
		var texture_region: Rect2 = state.get("texture_region", Rect2())
		_assert(authored_bounds.is_equal_approx(_transformed_rect(element.visual_local_bounds(), element.global_transform)), "Culling powinien wyprowadzać world bounds z bieżącego elementu scenowego.")
		_assert((state.get("world_rect", Rect2()) as Rect2).is_equal_approx(authored_bounds), "Publiczny world_rect stanu musi oznaczać bieżące bounds sceny, nie historyczny rect manifestu.")
		_assert(legacy_world_rect.size.x > 0.0 and legacy_world_rect.size.y > 0.0, "Historyczny world_rect ma pozostać dostępny wyłącznie jako metadana integralności.")
		_assert(node.position.is_equal_approx(element.visual_local_bounds().position), "Runtime Sprite2D nie może kopiować historycznej pozycji manifestu do lokalnego transformu.")
		_assert(node.region_rect.is_equal_approx(texture_region), "Sprite powinien renderować crop bez filter guttera w geometrii.")
		_assert(node.get_parent() == element.get_node_or_null("Attachment") and element.runtime_content_node() == node, "Runtime attachment musi być lokalnym dzieckiem niezależnego elementu.")
		_assert(element.get_parent().name == &"Authored" and element.get_parent().get_parent().name == &"WorldContent" and element.get_parent().get_parent().get_parent().name == &"L02_far_structures", "Legacy crop musi pozostać elementem L02/WorldContent/Authored.")


func _transformed_rect(rect: Rect2, transform: Transform2D) -> Rect2:
	var corners := PackedVector2Array([
		transform * rect.position,
		transform * Vector2(rect.end.x, rect.position.y),
		transform * rect.end,
		transform * Vector2(rect.position.x, rect.end.y),
	])
	var minimum := corners[0]
	var maximum := corners[0]
	for corner in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _finish() -> void:
	if _failed:
		quit(1)
	else:
		print("Dive visual chunk streaming test passed: schema v2 keeps transforms in the six-layer scene while async requests, hysteresis and sparse textures remain intact.")
		quit(0)
