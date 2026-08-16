extends SceneTree

const RuntimeMapScript := preload("res://scripts/diving/UnderwaterMapRuntime.gd")
const MapCompilerScript := preload("res://scripts/diving/UnderwaterMapSceneCompiler.gd")
const MANIFEST_PATH := "res://assets/diving/world/map_v2/visual_chunks/map_visual_chunks_v1.json"
const MASTER_ENVIRONMENT_PATH := "res://assets/diving/world/map_v2/visuals/duzaMapaEnvironmentDecorationLayer-v3.png"

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manifest := _load_manifest()
	_assert(not manifest.is_empty(), "Pochodny manifest sparse visuals powinien byc poprawnym JSON-em.")
	_validate_manifest_contract(manifest)

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
	streamer.update_streaming(first_position, Vector2(320.0, 240.0), true)
	await _wait_until_idle(streamer)
	var first_keys := streamer.loaded_chunk_keys()
	_assert(not first_keys.is_empty(), "Widok przy niepustym obszarze powinien materializowac przynajmniej jeden crop.")
	_assert(first_keys.size() < streamer.manifest_entry_count(), "Pierwszy widok nie moze materializowac calego manifestu.")
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

	dive_map.queue_free()
	await process_frame
	_finish()


func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	return parsed as Dictionary if parsed is Dictionary else {}


func _validate_manifest_contract(manifest: Dictionary) -> void:
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
		var node := state.get("node") as Sprite2D
		_assert(node != null, "Zaladowany klucz powinien miec Sprite2D.")
		if node == null:
			continue
		var world_rect: Rect2 = state.get("world_rect", Rect2())
		var texture_region: Rect2 = state.get("texture_region", Rect2())
		_assert(node.position.is_equal_approx(world_rect.position), "Sprite powinien zachowac pozycje source pixel -> world unit 1:1.")
		_assert(node.region_rect.is_equal_approx(texture_region), "Sprite powinien renderowac crop bez filter guttera w geometrii.")
		_assert(node.get_parent().name == str(state.get("runtime_parent", "")), "Crop powinien zachowac warstwe i z-order mastera.")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _finish() -> void:
	if _failed:
		quit(1)
	else:
		print("Dive visual chunk streaming test passed: sparse manifest, async requests, hysteresis and no master texture preload.")
		quit(0)
