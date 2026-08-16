extends SceneTree

const RuntimeMapScript := preload("res://scripts/diving/UnderwaterMapRuntime.gd")
const MapCompilerScript := preload("res://scripts/diving/UnderwaterMapSceneCompiler.gd")
const MANIFEST_PATH := "res://assets/diving/world/map_v2/visual_chunks/map_visual_chunks_v1.json"
const MASTER_ENVIRONMENT_PATH := "res://assets/diving/world/map_v2/visuals/duzaMapaEnvironmentDecorationLayer-v3.png"
const R1_ART_CELL_LIBRARY_PATH := "res://assets/diving/world/art_cells/r1/r1_art_cells_v1.json"
const EXPECTED_ENVIRONMENT_CHUNKS := 15
const EXPECTED_R1_ART_CELL_CHUNKS := 24
const EXPECTED_TOTAL_CHUNKS := EXPECTED_ENVIRONMENT_CHUNKS + EXPECTED_R1_ART_CELL_CHUNKS
const R1_ART_CELL_WORLD_SIZE := Vector2i(11_520, 1536)
const R1_ART_CELL_SIZE := Vector2i(2730, 1536)
const R1_ART_CELL_STRIDE := 2304
const R1_ART_CELL_Z_INDEX := -96
const R1_CHUNK_SIZE := 1024
const R1_CHUNK_GUTTER := 2
const R1_ART_CELL_SOURCE_IDS := [
	"Background_001",
	"Background_002",
	"Background_003",
	"Background_004",
	"Background_005",
]
const R1_ART_CELL_SOURCE_PATHS := [
	"res://assets/diving/world/art_cells/r1/r1_art_cell_001.png",
	"res://assets/diving/world/art_cells/r1/r1_art_cell_002.png",
	"res://assets/diving/world/art_cells/r1/r1_art_cell_003.png",
	"res://assets/diving/world/art_cells/r1/r1_art_cell_004.png",
	"res://assets/diving/world/art_cells/r1/r1_art_cell_005.png",
]

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manifest := _load_manifest()
	_assert(not manifest.is_empty(), "Pochodny manifest sparse visuals powinien byc poprawnym JSON-em.")
	_validate_manifest_contract(manifest)

	MapCompilerScript.clear_runtime_caches()
	_assert(not ResourceLoader.has_cached(MASTER_ENVIRONMENT_PATH), "Test nie moze startowac z pelna warstwa dekoracji w cache.")
	_assert_r1_source_textures_not_cached("przed instancjowaniem mapy")

	var dive_map = RuntimeMapScript.new()
	root.add_child(dive_map)
	await process_frame
	var streamer := dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/VisualChunkStreamer") as DiveVisualChunkStreamer
	_assert(streamer != null, "Runtime powinien utworzyc streamer prezentacyjnych chunkow.")
	if streamer == null:
		_finish()
		return
	streamer.enable_headless_texture_materialization_for_tests()

	_assert(streamer.manifest_loaded(), "Streamer powinien zaakceptowac wersjonowany manifest.")
	_assert(streamer.manifest_entry_count() == EXPECTED_TOTAL_CHUNKS, "Streamer powinien widziec dekoracje srodowiska i pelny zestaw cropow R1.")
	_assert(not ResourceLoader.has_cached(MASTER_ENVIRONMENT_PATH), "Instancjowanie mapy nie moze zaladowac pelnej warstwy dekoracji.")
	_assert_r1_source_textures_not_cached("po instancjowaniu mapy")
	var r1_layer := dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/R1ArtCells") as Node2D
	_assert(r1_layer != null, "Runtime powinien zachowac osobny slot R1ArtCells.")
	if r1_layer != null:
		_assert(r1_layer.z_index == R1_ART_CELL_Z_INDEX, "Runtime slot R1ArtCells musi miec z-index -96.")

	var first_position := Vector2(2_500.0, 768.0)
	streamer.update_streaming(first_position, Vector2(320.0, 240.0), true)
	await _wait_until_idle(streamer)
	var first_keys := streamer.loaded_chunk_keys()
	_assert(not first_keys.is_empty(), "Widok przy niepustym obszarze powinien materializowac przynajmniej jeden crop.")
	_assert(first_keys.size() < streamer.manifest_entry_count(), "Pierwszy widok nie moze materializowac calego manifestu.")
	_validate_loaded_nodes(streamer, first_keys)
	var desired_r1_keys := _keys_with_prefix(streamer.desired_chunk_keys(), "r1_art_cells:")
	var loaded_r1_keys := _keys_with_prefix(first_keys, "r1_art_cells:")
	_assert(not desired_r1_keys.is_empty(), "Kadr R1 musi wybrac co najmniej jeden crop r1_art_cells do streamingu.")
	_assert(not loaded_r1_keys.is_empty(), "Kadr R1 musi faktycznie zmaterializowac crop r1_art_cells.")
	for desired_r1_key in desired_r1_keys:
		_assert(loaded_r1_keys.has(desired_r1_key), "Kazdy oczekiwany crop R1 musi byc zaladowany po uspokojeniu streamera: %s." % desired_r1_key)
	for loaded_r1_key in loaded_r1_keys:
		var state := streamer.chunk_state(loaded_r1_key)
		var node := state.get("node") as Sprite2D
		_assert(str(state.get("runtime_parent", "")) == "R1ArtCells", "Crop R1 musi deklarowac runtime_parent R1ArtCells.")
		_assert(node != null and node.get_parent() == r1_layer, "Crop R1 musi byc dzieckiem dedykowanego slotu R1ArtCells.")
		if node != null and node.get_parent() is Node2D:
			_assert((node.get_parent() as Node2D).z_index == R1_ART_CELL_Z_INDEX, "Zaladowany crop R1 musi dziedziczyc warstwe z-index -96.")
			var canvas_material := node.material as CanvasItemMaterial
			_assert(canvas_material != null and canvas_material.light_mode == CanvasItemMaterial.LIGHT_MODE_UNSHADED, "Odlegly crop R1 musi byc unshaded, aby lokalna latarnia nie oswietlala kilometrowej panoramy.")
	var first_stream_state := streamer.presentation_state()
	_assert(int(first_stream_state.get("loaded_decoded_rgba_bytes", 0)) < 48 * 1024 * 1024, "Uspokojony kadr R1 z buforem musi pozostac pod budzetem 48 MiB decoded RGBA.")
	_assert_r1_source_textures_not_cached("po streamingu kadru R1")

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
	_assert(_keys_with_prefix(distant_keys, "r1_art_cells:").is_empty(), "Po dalekim skoku poza R1 zaden crop ArtCells nie moze pozostac zaladowany.")
	_assert(not ResourceLoader.has_cached(MASTER_ENVIRONMENT_PATH), "Streaming cropow nie moze posrednio zaladowac mastera dekoracji.")
	_assert_r1_source_textures_not_cached("po dalekim skoku streamera")

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
	_assert(layers.size() == 2, "Manifest powinien opisywac dekoracje srodowiska i streamowany pas R1 ArtCells.")
	var keys := {}
	var total_chunks := 0
	var total_decoded_rgba := 0
	var layer_chunk_counts := {}
	var layer_decoded_rgba := {}
	for layer_variant in layers:
		if not (layer_variant is Dictionary):
			_assert(false, "Kazda warstwa manifestu powinna byc slownikiem.")
			continue
		var layer: Dictionary = layer_variant
		var layer_id := str(layer.get("id", ""))
		_assert(layer_id in ["environment_decoration", "r1_art_cells"], "Manifest zawiera nieznana warstwe: %s." % layer_id)
		var master_path := str(layer.get("source_path", ""))
		var source_sha256 := str(layer.get("source_sha256", "")).to_lower()
		_assert(source_sha256.length() == 64, "Manifest powinien unieruchomic bajty mastera przez SHA-256.")
		if layer_id == "environment_decoration":
			_assert(master_path == MASTER_ENVIRONMENT_PATH, "Warstwa dekoracji musi zachowac historyczna sciezke mastera.")
			_assert(str(layer.get("runtime_parent", "")) == "EnvironmentDecoration" and int(layer.get("z_index", 0)) == -90, "Dekoracja srodowiska musi zachowac runtime_parent EnvironmentDecoration i z-index -90.")
			if FileAccess.file_exists(master_path):
				_assert(FileAccess.get_sha256(master_path).to_lower() == source_sha256, "Manifest powinien odpowiadac rzeczywistym bajtom mastera: %s." % master_path)
			else:
				_assert(bool(layer.get("source_archived", false)), "Brakujacy master dekoracji musi byc jawnie oznaczony jako zarchiwizowany; runtime korzysta tylko z cropow.")
		elif layer_id == "r1_art_cells":
			_assert(master_path == R1_ART_CELL_LIBRARY_PATH, "Warstwa R1 musi wskazywac przenosna biblioteke zrodlowych ArtCells.")
			_assert(FileAccess.file_exists(master_path) and FileAccess.get_sha256(master_path).to_lower() == source_sha256, "Manifest R1 musi odpowiadac bibliotece ArtCells.")
			_assert(str(layer.get("runtime_parent", "")) == "R1ArtCells" and int(layer.get("z_index", 0)) == R1_ART_CELL_Z_INDEX, "R1 ArtCells musza trafic do warstwy -96.")
			_assert(str(layer.get("light_mode", "")) == "unshaded", "R1 ArtCells musza jawnie ignorowac lokalne Light2D.")
			_validate_r1_source_assets(layer)
			_validate_r1_chunk_tiling(layer)
		var chunks: Array = layer.get("chunks", [])
		total_chunks += chunks.size()
		var decoded_rgba := int(layer.get("generated_decoded_rgba_bytes", 0))
		total_decoded_rgba += decoded_rgba
		layer_chunk_counts[layer_id] = chunks.size()
		layer_decoded_rgba[layer_id] = decoded_rgba
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
	_assert(int(layer_chunk_counts.get("environment_decoration", 0)) == EXPECTED_ENVIRONMENT_CHUNKS, "Rzadka dekoracja musi zachowac 15 historycznych cropow.")
	_assert(int(layer_chunk_counts.get("r1_art_cells", 0)) == EXPECTED_R1_ART_CELL_CHUNKS, "Pelny pas R1 musi miec 24 deterministyczne cropy 1024.")
	_assert(total_chunks == EXPECTED_TOTAL_CHUNKS, "Manifest powinien miec lacznie 39 unikalnych cropow.")
	_assert(int(layer_decoded_rgba.get("environment_decoration", 0)) < 4 * 1024 * 1024, "Rzadka dekoracja powinna pozostac pod 4 MiB decoded RGBA.")
	_assert(int(layer_decoded_rgba.get("r1_art_cells", 0)) < 70 * 1024 * 1024, "Caly pas R1 w cropach powinien pozostac pod 70 MiB decoded RGBA.")
	_assert(total_decoded_rgba < 75 * 1024 * 1024, "Wszystkie pochodne warstwy powinny pozostac pod 75 MiB decoded RGBA.")


func _validate_r1_source_assets(layer: Dictionary) -> void:
	var source_assets: Array = layer.get("source_assets", [])
	_assert(source_assets.size() == R1_ART_CELL_SOURCE_PATHS.size(), "Warstwa R1 musi byc zbudowana z pieciu zrodlowych ArtCells.")
	_assert(int(layer.get("source_size_bytes", -1)) == FileAccess.get_file_as_bytes(R1_ART_CELL_LIBRARY_PATH).size(), "source_size_bytes R1 musi oznaczac rozmiar biblioteki JSON.")
	var seen_ids := {}
	var seen_paths := {}
	var source_assets_size_bytes := 0
	for asset_index in range(mini(source_assets.size(), R1_ART_CELL_SOURCE_PATHS.size())):
		var asset_variant = source_assets[asset_index]
		_assert(asset_variant is Dictionary, "Kazdy source_assets R1 musi byc slownikiem.")
		if not (asset_variant is Dictionary):
			continue
		var asset: Dictionary = asset_variant
		var asset_id := str(asset.get("id", ""))
		var path := str(asset.get("path", ""))
		var sha256 := str(asset.get("sha256", "")).to_lower()
		var expected_id := str(R1_ART_CELL_SOURCE_IDS[asset_index])
		var expected_path := str(R1_ART_CELL_SOURCE_PATHS[asset_index])
		var expected_origin := Vector2i(asset_index * R1_ART_CELL_STRIDE, 0)
		var world_origin: Array = asset.get("world_origin", [])
		_assert(asset_id == expected_id, "Manifest R1 musi zachowac dokladne ID source assetu %s." % expected_id)
		_assert(path == expected_path, "Manifest R1 musi zachowac dokladna sciezke source assetu %s." % expected_path)
		_assert(not seen_ids.has(asset_id), "Manifest R1 nie moze powtarzac ID source assetu: %s." % asset_id)
		_assert(not seen_paths.has(path), "Manifest R1 nie moze powtarzac sciezki source assetu: %s." % path)
		seen_ids[asset_id] = true
		seen_paths[path] = true
		_assert(
			world_origin.size() == 2
			and int(world_origin[0]) == expected_origin.x
			and int(world_origin[1]) == expected_origin.y,
			"Manifest R1 musi zachowac world_origin %s dla %s." % [expected_origin, expected_id]
		)
		_assert(FileAccess.file_exists(path), "Brakuje zrodlowego R1 ArtCell: %s." % path)
		if FileAccess.file_exists(path):
			source_assets_size_bytes += FileAccess.get_file_as_bytes(path).size()
			_assert(sha256.length() == 64 and FileAccess.get_sha256(path).to_lower() == sha256, "Hash zrodlowego R1 ArtCell nie zgadza sie: %s." % path)
			var source_image := Image.load_from_file(ProjectSettings.globalize_path(path))
			_assert(not source_image.is_empty() and source_image.get_size() == R1_ART_CELL_SIZE, "Zrodlowy R1 ArtCell musi byc poprawnym PNG 2730x1536: %s." % path)
	_assert(int(layer.get("source_assets_size_bytes", -1)) == source_assets_size_bytes, "source_assets_size_bytes R1 musi oznaczac laczny rozmiar pieciu PNG.")


func _validate_r1_chunk_tiling(layer: Dictionary) -> void:
	var chunks: Array = layer.get("chunks", [])
	_assert(int(layer.get("generated_chunk_count", 0)) == EXPECTED_R1_ART_CELL_CHUNKS, "Manifest R1 musi deklarowac dokladnie 24 wygenerowane cropy.")
	_assert(int(layer.get("rendered_pixel_count", 0)) == R1_ART_CELL_WORLD_SIZE.x * R1_ART_CELL_WORLD_SIZE.y, "Manifest R1 musi deklarowac dokladny obszar renderu 11520x1536.")
	var chunks_by_key := {}
	var world_rects: Array[Rect2i] = []
	var total_world_area := 0
	for chunk_variant in chunks:
		_assert(chunk_variant is Dictionary, "Kazdy crop R1 musi byc slownikiem.")
		if not (chunk_variant is Dictionary):
			continue
		var chunk: Dictionary = chunk_variant
		var key := str(chunk.get("key", ""))
		chunks_by_key[key] = chunk
		var world_rect_value = chunk.get("world_rect", [])
		if not (world_rect_value is Array) or world_rect_value.size() != 4:
			continue
		var world_rect := Rect2i(
			int(world_rect_value[0]),
			int(world_rect_value[1]),
			int(world_rect_value[2]),
			int(world_rect_value[3])
		)
		for existing_rect in world_rects:
			_assert(not world_rect.intersects(existing_rect), "Cropy R1 nie moga nakladac sie w przestrzeni swiata: %s i %s." % [world_rect, existing_rect])
		world_rects.append(world_rect)
		total_world_area += world_rect.size.x * world_rect.size.y

	var expected_decoded_rgba := 0
	for chunk_y in range(2):
		for chunk_x in range(12):
			var key := "r1_art_cells:%d:%d" % [chunk_x, chunk_y]
			_assert(chunks_by_key.has(key), "Pelny tiling R1 wymaga cropa %s." % key)
			if not chunks_by_key.has(key):
				continue
			var chunk: Dictionary = chunks_by_key[key]
			var left := chunk_x * R1_CHUNK_SIZE
			var top := chunk_y * R1_CHUNK_SIZE
			var right := mini(left + R1_CHUNK_SIZE, R1_ART_CELL_WORLD_SIZE.x)
			var bottom := mini(top + R1_CHUNK_SIZE, R1_ART_CELL_WORLD_SIZE.y)
			var expected_world_rect := Rect2i(left, top, right - left, bottom - top)
			var source_left := maxi(left - R1_CHUNK_GUTTER, 0)
			var source_top := maxi(top - R1_CHUNK_GUTTER, 0)
			var source_right := mini(right + R1_CHUNK_GUTTER, R1_ART_CELL_WORLD_SIZE.x)
			var source_bottom := mini(bottom + R1_CHUNK_GUTTER, R1_ART_CELL_WORLD_SIZE.y)
			var expected_source_rect := Rect2i(source_left, source_top, source_right - source_left, source_bottom - source_top)
			var expected_texture_region := Rect2i(left - source_left, top - source_top, expected_world_rect.size.x, expected_world_rect.size.y)
			var expected_path := "res://assets/diving/world/map_v2/visual_chunks/r1_art_cells/chunk_%02d_%02d.png" % [chunk_x, chunk_y]
			_assert(_pair_array_matches(chunk.get("coord", []), Vector2i(chunk_x, chunk_y)), "Crop %s musi zachowac dokladne coord." % key)
			_assert(str(chunk.get("path", "")) == expected_path, "Crop %s musi zachowac deterministyczna sciezke pliku." % key)
			_assert(_rect_array_matches(chunk.get("world_rect", []), expected_world_rect), "Crop %s musi zachowac dokladny world_rect %s." % [key, expected_world_rect])
			_assert(_rect_array_matches(chunk.get("source_rect", []), expected_source_rect), "Crop %s musi zachowac dwupikselowy gutter w source_rect %s." % [key, expected_source_rect])
			_assert(_rect_array_matches(chunk.get("texture_region", []), expected_texture_region), "Crop %s musi renderowac tylko bezszwowy srodek %s." % [key, expected_texture_region])
			expected_decoded_rgba += expected_source_rect.size.x * expected_source_rect.size.y * 4
			if FileAccess.file_exists(expected_path):
				var chunk_image := Image.load_from_file(ProjectSettings.globalize_path(expected_path))
				_assert(not chunk_image.is_empty(), "Crop R1 musi byc poprawnym PNG: %s." % expected_path)
				if not chunk_image.is_empty():
					_assert(chunk_image.get_size() == expected_source_rect.size, "Rzeczywisty rozmiar cropa R1 musi odpowiadac source_rect z gutterem: %s." % expected_path)

	_assert(world_rects.size() == EXPECTED_R1_ART_CELL_CHUNKS, "Tiling R1 musi zawierac 24 poprawne prostokaty swiata.")
	_assert(total_world_area == R1_ART_CELL_WORLD_SIZE.x * R1_ART_CELL_WORLD_SIZE.y, "Niepokrywajace sie cropy R1 musza bez luk wypelniac dokladnie 11520x1536.")
	_assert(int(layer.get("generated_decoded_rgba_bytes", 0)) == expected_decoded_rgba, "Budzet decoded RGBA R1 musi wynikac z rzeczywistych rectow cropow z gutterem.")


func _pair_array_matches(value: Variant, expected: Vector2i) -> bool:
	return value is Array and value.size() == 2 and int(value[0]) == expected.x and int(value[1]) == expected.y


func _rect_array_matches(value: Variant, expected: Rect2i) -> bool:
	return (
		value is Array
		and value.size() == 4
		and int(value[0]) == expected.position.x
		and int(value[1]) == expected.position.y
		and int(value[2]) == expected.size.x
		and int(value[3]) == expected.size.y
	)


func _keys_with_prefix(keys: Array[String], prefix: String) -> Array[String]:
	var result: Array[String] = []
	for key in keys:
		if key.begins_with(prefix):
			result.append(key)
	return result


func _assert_r1_source_textures_not_cached(context: String) -> void:
	for source_path_variant in R1_ART_CELL_SOURCE_PATHS:
		var source_path := str(source_path_variant)
		_assert(not ResourceLoader.has_cached(source_path), "Runtime nie moze cache'owac pelnego zrodlowego R1 ArtCell %s (%s)." % [source_path, context])


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
