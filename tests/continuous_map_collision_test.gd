extends SceneTree

const ContinuousMapScript := preload("res://scripts/diving/UnderwaterMapRuntime.gd")
const DiverScene := preload("res://scenes/diving/Diver.tscn")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const PersistentInteractableScript := preload("res://scripts/diving/DivePersistentInteractable.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")

const EXPECTED_VISUAL_LAYER_IDS: Array[StringName] = [
	&"L00_base_color",
	&"L01_ultra_far_silhouettes",
	&"L02_far_structures",
	&"L03_mid_drift_props",
	&"L04_near_terrain_skin",
	&"L05_foreground_occluders",
]

var _failed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var dive_map = ContinuousMapScript.new()
	root.add_child(dive_map)
	await process_frame
	await physics_frame

	_assert(dive_map.world_size() == Vector2(11_520, 6_480), "Mapa PNG musi miec kanoniczny obszar 11 520 x 6 480.")
	var initial_exit_sprite := dive_map.exit_line.get_node_or_null("ExitLineSprite") as Sprite2D
	var initial_exit_presentation: Dictionary = dive_map._presentation_record("exit_line")
	var initial_authored_exit = dive_map.exit_line.get_node_or_null("AuthoredMapVisual")
	_assert(dive_map.exit_line.support_level == 1, "Domyslna wyprawa powinna prezentowac podstawowa line powrotna.")
	_assert(dive_map.exit_line.visual_texture() != null and dive_map.exit_line.visual_texture().resource_path == "res://assets/diving/interactables/return_line.png", "Stacja I-III powinna korzystac z produkcyjnej grafiki liny powrotnej.")
	_assert(initial_exit_sprite != null and initial_exit_sprite.texture == dive_map.exit_line.visual_texture(), "Lina powrotna powinna podlaczyc wybrana grafike do ExitLineSprite.")
	if not str(initial_exit_presentation.get("visual_scene_path", "")).is_empty():
		_assert(initial_authored_exit != null, "Tylko glowne wejscie R1-00 powinno zachowac authored prefab platformy.")
		_assert(initial_exit_sprite != null and not initial_exit_sprite.visible, "Authored prefab glownej platformy powinien zastapic runtime sprite liny.")
	_assert(dive_map.is_world_position_navigable(dive_map.start_position()), "Punkt startowy nurka musi lezec w przezroczystym obszarze do plywania.")
	_assert(not dive_map.is_world_position_navigable(Vector2.ZERO), "Czarny rog maski musi byc oznaczony jako sciana.")
	_assert(dive_map.collision_segment_count() > 100, "Binarna maska powinna utworzyc konturowy collider swiata.")
	var collision_chunks = dive_map.get_node_or_null("RuntimeDynamic/WorldMaskCollision")
	_assert(collision_chunks is Node2D and collision_chunks.get_child_count() > 0, "Mapa powinna streamowac chunki StaticBody2D utworzone ze wspolnej maski.")
	if collision_chunks is Node2D and collision_chunks.get_child_count() > 0:
		var first_collision_chunk := collision_chunks.get_child(0)
		var occluder_count := 0
		for child in first_collision_chunk.get_children():
			if child is LightOccluder2D:
				occluder_count += 1
				_assert(
					child.occluder != null and child.occluder.polygon.size() >= 2,
					"Kazdy prezentacyjny occluder musi korzystac z konturu wspolnej maski."
				)
		_assert(occluder_count > 0, "Streamowany collider skaly powinien dostarczac occludery latarki z tego samego konturu.")
	var visual_stack := dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/SixLayerVisuals") as DiveVisualLayerStack
	_assert(visual_stack != null and visual_stack.validation_errors().is_empty(), "Runtime powinien zachować poprawny stos dokładnie sześciu edytowalnych warstw.")
	if visual_stack != null:
		_assert(visual_stack.get_child_count() == EXPECTED_VISUAL_LAYER_IDS.size(), "Runtime nie może zgubić ani dodać siódmej warstwy wizualnej.")
		for layer_id in EXPECTED_VISUAL_LAYER_IDS:
			var layer := visual_stack.layer_root(layer_id)
			_assert(layer != null and StringName(layer.name) == layer_id, "Runtime musi zachować stabilną warstwę %s." % layer_id)
	var terrain_renderer = dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/TerrainRenderer")
	_assert(terrain_renderer is UnderwaterTerrainRenderer, "Mapa powinna zawierac chunkowany renderer terenu ze wspolnej maski.")
	if terrain_renderer is UnderwaterTerrainRenderer:
		var terrain_state: Dictionary = terrain_renderer.presentation_state()
		_assert(bool(terrain_state.get("uses_shared_contour_mask", false)), "Renderer powinien uzywac tej samej maski co kolizja.")
		_assert(bool(terrain_state.get("uses_derived_contour_sdf", false)), "Renderer powinien wygladzac kontur pochodnym SDF bez zmiany maski kolizji.")
		_assert(bool(terrain_state.get("uses_detail_texture", false)), "Renderer powinien uzywac produkcyjnego materialu skal.")
		_assert(int(terrain_state.get("active_chunk_count", 0)) > 0, "Renderer powinien sledzic aktywny pierscien streamingu swiata.")
		_assert(bool(terrain_state.get("uses_global_water_layer", false)), "Proceduralna woda powinna byc jedna pelnomapowa warstwa bez szwow miedzy chunkami.")
		_assert(bool(terrain_state.get("uses_global_backdrop_layer", false)), "Dalekie tlo biomow powinno byc jedna pelnomapowa warstwa prezentacyjna.")
		_assert(int(terrain_state.get("backdrop_material_count", 0)) == 1, "Dalekie tlo biomow powinno wspoldzielic jeden material globalny.")
		_assert(int(terrain_state.get("backdrop_z_index", 0)) == -95, "Dalekie tlo biomow powinno lezec miedzy woda a dekoracjami srodowiska.")
		_assert(bool(terrain_state.get("uses_global_terrain_layer", false)), "Proceduralna skala powinna byc jedna pelnomapowa warstwa bez szwow miedzy chunkami.")
		if visual_stack != null:
			_assert(str(terrain_state.get("water_parent", "")) == str(visual_stack.content_root(&"L00_base_color", &"world", &"generated").get_path()), "Renderer musi kierować wodę do L00/WorldContent/Generated.")
			_assert(str(terrain_state.get("backdrop_parent", "")) == str(visual_stack.content_root(&"L01_ultra_far_silhouettes", &"parallax", &"generated").get_path()), "Renderer musi kierować dalekie sylwetki do L01/ParallaxContent/Generated.")
			_assert(str(terrain_state.get("terrain_parent", "")) == str(visual_stack.content_root(&"L04_near_terrain_skin", &"world", &"generated").get_path()), "Renderer musi kierować skórę terenu do L04/WorldContent/Generated.")
	var blueprint = dive_map._blueprint
	var empty_chunk_key := ""
	var empty_chunk_coordinates := Vector2i(-1, -1)
	var empty_chunk_center := dive_map.start_position()
	var chunk_grid_size := Vector2i(
		ceili(blueprint.world_size.x / float(blueprint.chunk_size)),
		ceili(blueprint.world_size.y / float(blueprint.chunk_size))
	)
	for y in range(chunk_grid_size.y):
		for x in range(chunk_grid_size.x):
			var candidate_key: String = blueprint.chunk_key(Vector2i(x, y))
			if not blueprint.chunk_index.has(candidate_key):
				empty_chunk_key = candidate_key
				empty_chunk_coordinates = Vector2i(x, y)
				break
		if not empty_chunk_key.is_empty():
			break
	_assert(not empty_chunk_key.is_empty(), "Fixture mapy powinien zawierac pusty chunk bez landmarku lub polaczenia.")
	if not empty_chunk_key.is_empty():
		empty_chunk_center = (Vector2(empty_chunk_coordinates) + Vector2(0.5, 0.5)) * float(blueprint.chunk_size)
		dive_map.update_streaming(empty_chunk_center, true)
		await physics_frame
	_assert(dive_map.active_chunk_keys.has(empty_chunk_key), "Streaming terenu i kolizji nie moze pomijac pustych chunkow swiata.")
	if terrain_renderer is UnderwaterTerrainRenderer:
		_assert(_string_set(terrain_renderer.active_chunk_keys()) == _string_set(dive_map.active_chunk_keys), "Renderer terenu musi otrzymac dokladnie zestaw aktywnych chunkow swiata.")
		var water_background: Polygon2D
		var distant_backdrop: Polygon2D
		var rock_sprite: Sprite2D
		if visual_stack != null:
			water_background = visual_stack.content_root(&"L00_base_color", &"world", &"generated").get_node_or_null("WaterBackground") as Polygon2D
			distant_backdrop = visual_stack.content_root(&"L01_ultra_far_silhouettes", &"parallax", &"generated").get_node_or_null("DistantBiomeBackground") as Polygon2D
			rock_sprite = visual_stack.content_root(&"L04_near_terrain_skin", &"world", &"generated").get_node_or_null("TerrainBackground") as Sprite2D
		_assert(water_background != null, "Jedna proceduralna warstwa wody powinna pokrywac caly swiat.")
		_assert(distant_backdrop != null, "Dalekie tlo biomow powinno byc globalnym Polygon2D renderera terenu.")
		_assert(rock_sprite != null and rock_sprite.texture == terrain_renderer.contour_sdf, "Jedna pelnomapowa warstwa skal musi uzywac prezentacyjnego SDF renderera.")
		if water_background != null and distant_backdrop != null and rock_sprite != null:
			_assert(water_background.z_index == 0 and distant_backdrop.z_index == 0 and rock_sprite.z_index == 0, "Elementy generowane mają dziedziczyć z-order wyłącznie z własnych wrapperów warstw.")
			_assert(visual_stack.layer_root(&"L00_base_color").z_index < visual_stack.layer_root(&"L01_ultra_far_silhouettes").z_index, "Woda L00 musi pozostać pod dalekim tłem L01.")
			_assert(visual_stack.layer_root(&"L01_ultra_far_silhouettes").z_index < visual_stack.layer_root(&"L02_far_structures").z_index, "Dalekie tło L01 musi pozostać pod autorskimi konstrukcjami L02.")
			_assert(visual_stack.layer_root(&"L02_far_structures").z_index < visual_stack.layer_root(&"L04_near_terrain_skin").z_index, "Konstrukcje L02 muszą pozostać pod skórą terenu L04.")
	var loaded_collision_keys: Array[String] = dive_map.loaded_collision_chunk_keys()
	for loaded_collision_key in loaded_collision_keys:
		_assert(dive_map.active_chunk_keys.has(loaded_collision_key), "Zaladowany collider musi nalezec do aktywnego pierscienia chunkow.")
	var first_loaded_collision_keys := loaded_collision_keys.duplicate()
	dive_map.update_streaming(Vector2(11_000.0, 6_000.0), true)
	await physics_frame
	for stale_collision_key in first_loaded_collision_keys:
		_assert(not dive_map.loaded_collision_chunk_keys().has(stale_collision_key), "Collider opuszczajacy aktywny pierscien musi zostac odlaczony.")
	dive_map.update_streaming(empty_chunk_center if not empty_chunk_key.is_empty() else dive_map.start_position(), true)
	await physics_frame
	for restored_collision_key in first_loaded_collision_keys:
		_assert(dive_map.loaded_collision_chunk_keys().has(restored_collision_key), "Powrot do obszaru musi deterministycznie odtworzyc jego collidery.")
	dive_map.update_streaming(Vector2(5_760.0, 3_240.0), true, Vector2(1_600.0, 900.0))
	_assert(dive_map.active_chunk_keys.size() == 77, "Streaming musi rozszerzyc bufor do 11 x 7 chunkow dla szerokiego kadru 4K przy zoomie 1,2.")
	_assert(dive_map.terrain_visual_profiles().size() == 4, "Mapa powinna miec cztery walidowane profile prezentacyjne regionow.")
	for boundary_ratio in [0.237, 0.401, 0.607]:
		var before_profile: Dictionary = dive_map._blended_visual_profile_at(Vector2(5_760.0, (boundary_ratio - 0.00001) * dive_map.world_size().y))
		var after_profile: Dictionary = dive_map._blended_visual_profile_at(Vector2(5_760.0, (boundary_ratio + 0.00001) * dive_map.world_size().y))
		var before_color: Color = before_profile.get("water_color", Color.BLACK)
		var after_color: Color = after_profile.get("water_color", Color.WHITE)
		_assert(
			Vector4(before_color.r, before_color.g, before_color.b, before_color.a).distance_to(
				Vector4(after_color.r, after_color.g, after_color.b, after_color.a)
			) < 0.01,
			"Globalne srodowisko musi przechodzic plynnie przez granice profili, bez skoku koloru."
		)
		_assert(
			absf(float(before_profile.get("water_clarity", 0.0)) - float(after_profile.get("water_clarity", 1.0))) < 0.01,
			"Globalne VFX musi przechodzic plynnie przez granice profili, bez skoku parametrow."
		)
	_assert(dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/OceanBackground") == null, "Monolityczne tlo oceanu powinno zostac zastapione proceduralna woda chunkow.")
	_assert(dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/EnvironmentDecoration") == null, "Stary pojedynczy kontener EnvironmentDecoration nie może pozostać równoległą siódmą warstwą.")
	if visual_stack != null:
		var l02_authored := visual_stack.content_root(&"L02_far_structures", &"world", &"authored")
		var authored_elements: Array[DiveVisualLayerElement] = []
		for child in l02_authored.get_children():
			if child is DiveVisualLayerElement:
				authored_elements.append(child as DiveVisualLayerElement)
		_assert(authored_elements.size() == 15, "Piętnaście odziedziczonych cropów musi zachować piętnaście niezależnych transformacji w L02.")
	var visual_streamer = dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/VisualChunkStreamer")
	_assert(visual_streamer is DiveVisualChunkStreamer, "Warstwy authored powinien obslugiwac prezentacyjny streamer chunkow.")
	if visual_streamer is DiveVisualChunkStreamer:
		var visual_stream_state: Dictionary = visual_streamer.presentation_state()
		_assert(bool(visual_stream_state.get("manifest_loaded", false)), "Streamer powinien zaladowac pochodny manifest bez ladowania pelnych tekstur.")
		_assert(int(visual_stream_state.get("schema_version", 0)) == 2 and str(visual_stream_state.get("transform_authority", "")) == "composition_scene_only", "Runtime musi korzystać z manifestu v2, w którym transformy pozostają wyłącznie w scenie.")
		_assert(int(visual_stream_state.get("entry_count", 0)) == 15, "Manifest powinien zawierac tylko 15 rzadkich cropow dekoracji srodowiska.")
		_assert(int(visual_stream_state.get("authored_element_count", 0)) == 15, "Każdy wpis manifestu v2 musi mieć dokładnie jeden niezależny element scenowy.")
		_assert(int(visual_stream_state.get("all_chunks_decoded_rgba_bytes", 0)) < 4 * 1024 * 1024, "Komplet cropow dekoracji powinien zajmowac mniej niz 4 MiB decoded RGBA.")
		_assert(int(visual_stream_state.get("loaded_count", 0)) < int(visual_stream_state.get("entry_count", 0)), "Runtime nie powinien jednoczesnie materializowac wszystkich cropow.")
	_assert(not ResourceLoader.has_cached("res://assets/diving/world/map_v2/visuals/duzaMapaEnvironmentDecorationLayer-v3.png"), "Runtime nie powinien ladowac pelnej warstwy dekoracji.")
	_assert(dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/ColliderVisual") == null, "Monolityczny PNG collidera nie powinien pozostac drugim zrodlem widocznej geometrii.")
	_assert(dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/RockTransition") == null, "Recznie synchronizowane przejscie skalne powinien zastapic material wspolnej maski.")
	_assert(visual_stack != null and visual_stack.layer_root(&"L05_foreground_occluders") != null, "Mapa musi mieć niezależną, oszczędną warstwę L05 pierwszego planu.")
	_assert(dive_map.get_node_or_null("BiomeBackdrops") == null, "Stare modularne panoramy nie powinny byc podlaczone do runtime.")
	_assert(dive_map.get_node_or_null("LandmarkVisuals") == null, "Stare proceduralne sylwetki landmarkow nie powinny byc podlaczone do runtime.")
	var container_visual_paths: Dictionary = {}
	for container in dive_map.containers:
		_assert(dive_map.is_world_position_navigable(container.global_position), "Kazdy kontener tutoriala musi lezec w dostepnej wodzie.")
		var container_texture: Texture2D = container.visual_texture()
		var container_sprite := container.get_node_or_null("ContainerSprite") as Sprite2D
		var expected_container_path := (
			"res://assets/diving/interactables/tool_locker.png"
			if container.interaction_action == "pry"
			else "res://assets/diving/interactables/supply_crate.png"
		)
		_assert(container_texture != null and container_texture.resource_path == expected_container_path, "Kazdy kontener wyprawy musi wybrac grafike zgodna ze swoim typem: %s." % container.container_id)
		_assert(container_sprite != null and container_sprite.texture == container_texture, "Kazdy kontener wyprawy musi podlaczyc wybrana grafike do ContainerSprite.")
		if container_texture != null:
			container_visual_paths[container_texture.resource_path] = true
	_assert(container_visual_paths.has("res://assets/diving/interactables/supply_crate.png"), "Zwykle skrzynie powinny korzystac z dedykowanej grafiki zaopatrzeniowej.")
	_assert(container_visual_paths.has("res://assets/diving/interactables/tool_locker.png"), "Skrytki podwazane lomem powinny korzystac z grafiki szafki technicznej.")
	_assert(dive_map.world_pickups.size() == 12, "Mapa powinna utworzyć dwanaście wolnostojących, pojedynczych zasobów.")
	var pickup_ids: Array[String] = []
	for pickup in dive_map.world_pickups:
		_assert(dive_map.is_world_position_navigable(pickup.global_position), "Każdy wolnostojący zasób musi leżeć w dostępnej wodzie: %s." % pickup.pickup_id)
		_assert(pickup.resource_id in [ResourceIdsScript.FOOD, ResourceIdsScript.PLANKS, ResourceIdsScript.SCRAP], "Runtime powinien tworzyć tylko obsługiwane typy wolnostojących zasobów.")
		_assert(pickup.visual_texture() != null and pickup.visual_texture().get_size() == Vector2(128, 128), "Każdy wolnostojący zasób musi mieć właściwą grafikę 128 x 128.")
		_assert(not pickup_ids.has(pickup.pickup_id), "Runtime nie może powielać stabilnych ID wolnostojących zasobów.")
		pickup_ids.append(pickup.pickup_id)
	var r3_boundary_pickup = _find_pickup(dive_map.world_pickups, "pickup_r3_planks_01")
	_assert(r3_boundary_pickup != null and str(r3_boundary_pickup.get("_region_id")) == "R3", "Jawny region ID znajdźki musi wygrać z nakładającą się granicą R2/R3.")
	var active_chunks_before_presentation := _string_set(dive_map.active_chunk_keys)
	var loaded_collision_chunks_before_presentation := _string_set(dive_map.loaded_collision_chunk_keys())
	var collision_segment_count_before_presentation := dive_map.collision_segment_count()
	dive_map.set_graphics_quality("low")
	dive_map.set_reduced_motion(true)
	_assert(_string_set(dive_map.active_chunk_keys) == active_chunks_before_presentation, "Zmiana prezentacji nie może zmienić aktywnych chunków świata.")
	_assert(_string_set(dive_map.loaded_collision_chunk_keys()) == loaded_collision_chunks_before_presentation, "Zmiana prezentacji nie może przeładować ani odłączyć aktywnych colliderów.")
	_assert(dive_map.collision_segment_count() == collision_segment_count_before_presentation, "Zmiana prezentacji nie może zmienić liczby segmentów kanonicznej kolizji.")
	if visual_stack != null:
		for layer_id in EXPECTED_VISUAL_LAYER_IDS:
			var layer := visual_stack.layer_root(layer_id)
			var parallax: Parallax2D
			if layer != null:
				parallax = layer.get_node_or_null("ParallaxContent") as Parallax2D
			_assert(layer != null and layer.visible, "Reduced motion nie może ukrywać warstwy %s." % layer_id)
			_assert(parallax != null and parallax.scroll_scale.is_equal_approx(Vector2.ONE), "Reduced motion musi wyłączyć różnicę prędkości warstwy %s bez jej usuwania." % layer_id)
	for pickup in dive_map.world_pickups:
		_assert(str(pickup.get("_graphics_quality")) == "low", "Profil low musi dotrzeć do każdej znajdźki.")
		_assert(bool(pickup.get("_reduced_motion")), "Reduced motion musi dotrzeć do każdej znajdźki.")
		var pickup_sprite := pickup.get_node_or_null("PickupSprite") as Sprite2D
		_assert(pickup_sprite != null and pickup_sprite.position == Vector2.ZERO and is_zero_approx(pickup_sprite.rotation), "Reduced motion musi zatrzymać bob i obrót znajdźki.")
	dive_map.set_graphics_quality("high")
	dive_map.set_reduced_motion(false)
	_assert(dive_map.persistent_interactables.size() == 10, "Mapa powinna budować dokładnie siedem trwałych bram skrótów i trzy ciężkie obiekty z blueprintu.")
	var persistent_visual_paths: Dictionary = {}
	for interactable in dive_map.persistent_interactables:
		_assert(dive_map.is_world_position_navigable(interactable.global_position), "Każdy trwały punkt eksploracji musi zostać przeniesiony do dostępnej wody.")
		var interactable_texture: Texture2D = interactable.visual_texture()
		var interactable_sprite := interactable.get_node_or_null("InteractableSprite") as Sprite2D
		_assert(interactable_texture != null, "Kazdy trwaly punkt eksploracji musi miec przypisana grafike swiata: %s." % interactable.persistent_id)
		_assert(interactable_sprite != null and interactable_sprite.texture == interactable_texture, "Kazdy trwaly punkt eksploracji musi podlaczyc wybrana grafike do InteractableSprite.")
		if interactable_texture != null:
			persistent_visual_paths[interactable_texture.resource_path] = true
	for expected_visual_path in [
		"res://assets/diving/interactables/shortcut_gate.png",
		"res://assets/diving/interactables/ship_engine.png",
		"res://assets/diving/interactables/shipyard_winch.png",
		"res://assets/diving/interactables/industrial_generator.png",
	]:
		_assert(persistent_visual_paths.has(expected_visual_path), "Mapa musi podlaczyc kazdy wariant przeszkody i ciezkiego obiektu: %s." % expected_visual_path)
	var expected_device_visuals := {
		"junction_j7": "res://scenes/diving/map_visuals/JunctionJ7Visual.tscn",
		"archive_terminal": "res://scenes/diving/map_visuals/ArchiveTerminalVisual.tscn",
		"r3_diagnostic_panel": "res://scenes/diving/map_visuals/R3DiagnosticPanelVisual.tscn",
		"r3_generator": "res://scenes/diving/map_visuals/R3GeneratorVisual.tscn",
		"c4_switchboard": "res://scenes/diving/map_visuals/C4SwitchboardVisual.tscn",
		"c4_splitter_mount": "res://scenes/diving/map_visuals/C4SplitterMountVisual.tscn",
	}
	for device_id in expected_device_visuals.keys():
		var device_record := _fixed_device_record(dive_map._blueprint.fixed_device_spawns, device_id)
		_assert(str(device_record.get("visual_scene_path", "")) == expected_device_visuals[device_id], "Każde urządzenie Wspólnej Linii musi mieć odrębny prefab prezentacyjny: %s." % device_id)
	_assert(dive_map.threats.size() == 1, "Mapa powinna zbudowac jednego wdrozonego przeciwnika pionu ryzyka.")
	if dive_map.threats.size() == 1:
		var threat = dive_map.threats[0]
		var threat_sprite := threat.get_node_or_null("ThreatSprite") as Sprite2D
		_assert(threat.visual_texture() != null and threat.visual_texture().resource_path == "res://assets/diving/threats/noise_eel.png", "Slepy wegorz powinien korzystac z dedykowanej grafiki przeciwnika.")
		_assert(threat_sprite != null and threat_sprite.texture == threat.visual_texture(), "Przeciwnik powinien podlaczyc grafike definicji do ThreatSprite.")
	var reachable_cells := _reachable_cells_from(dive_map, dive_map.start_position())
	for container in dive_map.containers:
		_assert(_is_reachable(dive_map, reachable_cells, container.global_position), "Kazdy pojemnik z zasobami kampanii musi miec fizyczna droge od glownego wejscia: %s." % container.container_id)
	for pickup in dive_map.world_pickups:
		_assert(_is_reachable(dive_map, reachable_cells, pickup.global_position), "Każdy wolnostojący zasób musi mieć fizyczną drogę od głównego wejścia: %s." % pickup.pickup_id)
	for interactable in dive_map.persistent_interactables:
		_assert(_is_reachable(dive_map, reachable_cells, interactable.global_position), "Kazda trwala interakcja musi miec fizyczna droge od glownego wejscia: %s." % interactable.persistent_id)
	for rescue_survivor in dive_map.rescue_survivors:
		_assert(_is_reachable(dive_map, reachable_cells, rescue_survivor.global_position), "Kazdy ocalaly musi byc osiagalny w fizycznej geometrii mapy: %s." % rescue_survivor.encounter_id)

	var stream_target := dive_map.start_position().lerp(Vector2.ZERO, 0.5)
	dive_map.update_streaming(stream_target, true)
	await physics_frame
	var ray_parameters := PhysicsRayQueryParameters2D.create(dive_map.start_position(), Vector2.ZERO, 1)
	var ray_hit := root.get_world_2d().direct_space_state.intersect_ray(ray_parameters)
	_assert(not ray_hit.is_empty(), "Promien z wody do czarnego tla powinien trafic w collider granicy.")

	var diver = DiverScene.instantiate()
	root.add_child(diver)
	diver.reset_at(dive_map.start_position())
	await physics_frame
	var toward_black: Vector2 = (Vector2.ZERO - diver.global_position).normalized() * 5000.0
	var collision: KinematicCollision2D = diver.move_and_collide(toward_black, true)
	_assert(collision != null, "CharacterBody2D nurka nie moze przeplynac z bialej wody w czarna sciane.")

	var world = dive_map._world_state
	var campaign_active_before: String = world.active_sector_id
	world.placed_buoys.append("B-01")
	world.opened_shortcuts.append("SC-01")
	var collected_pickup_id: String = dive_map.world_pickups[0].pickup_id
	world.collected_items.append(collected_pickup_id)
	world.lost_backpacks["test_diver"] = {
		"diver_id": "test_diver",
		"landmark_id": "R2-02",
		"world_position": world.blueprint.get_landmark("R2-02").get("position", Vector2.ZERO),
		"items": {"scrap": 2},
		"gear_ids": [],
		"lost_on_day": 2,
		"recovered": false,
	}
	var expedition_setup = ExpeditionSetupScript.new()
	expedition_setup.can_place_buoys = true
	expedition_setup.base_support_level = 4
	expedition_setup.start_entry_point = "R2-02"
	dive_map.configure(world, expedition_setup.start_entry_point, expedition_setup)
	await physics_frame
	_assert(world.active_sector_id == campaign_active_before, "Selecting a local dive entry must not mutate campaign WorldDelta before DiveResult.")
	var active_buoy_record := _find_buoy_record(world.blueprint.buoy_spawns, "B-01")
	var expected_buoy_start := dive_map.nearest_navigable_position(
		active_buoy_record.get("position", Vector2.ZERO),
		35.0
	)
	_assert(dive_map.active_sector_id == "R2-02", "Runtime musi zachowac kanoniczne ID wybranego landmarku wejscia.")
	_assert(dive_map.start_position() == expected_buoy_start, "Wybrane wejscie z boi musi materializowac start przy fizycznej kotwicy B-01.")
	_assert(dive_map.exit_line.global_position == active_buoy_record.get("position", Vector2.ZERO), "Lina powrotna musi powstac dokladnie przy kotwicy aktywnej boi B-01.")
	_assert(dive_map.start_position().distance_to(dive_map.exit_line.global_position) <= 1.0, "Start z boi musi znaleźć nurka bezpośrednio przy aktywnej linie.")
	_assert(dive_map.exit_line.global_position != world.blueprint.exit_position, "Wejscie z boi nie moze pozostawic liny przy glownej Stacji.")
	var bell_sprite := dive_map.exit_line.get_node_or_null("ExitLineSprite") as Sprite2D
	_assert(dive_map.exit_line.support_level == 4, "Zamrozony poziom wsparcia Stacji powinien dotrzec do punktu powrotu.")
	_assert(dive_map.exit_line.visual_texture() != null and dive_map.exit_line.visual_texture().resource_path == "res://assets/diving/interactables/return_bell.png", "Stacja IV powinna prezentowac produkcyjny dzwon glebinowy.")
	_assert(bell_sprite != null and bell_sprite.texture == dive_map.exit_line.visual_texture(), "Dzwon glebinowy powinien podlaczyc wybrana grafike do ExitLineSprite.")
	_assert(bell_sprite != null and bell_sprite.visible, "Wejscie z boi musi uzyc runtime ReturnBell/ReturnLine bez platformowego override.")
	_assert(dive_map.exit_line.get_node_or_null("AuthoredMapVisual") == null, "Wejscie z boi nie moze instancjonowac authored prefabu glownej platformy.")
	_assert(dive_map.lost_backpacks.size() == 1, "Niezebrany plecak powinien odtworzyć się w świecie z rekordu WorldDelta.")
	if dive_map.lost_backpacks.size() == 1:
		var lost_backpack = dive_map.lost_backpacks[0]
		var lost_backpack_sprite := lost_backpack.get_node_or_null("ContainerSprite") as Sprite2D
		_assert(lost_backpack.visual_texture() != null and lost_backpack.visual_texture().resource_path == "res://assets/diving/interactables/lost_backpack.png", "Utracony plecak powinien miec odrebna grafike, a nie wygladac jak skrzynia.")
		_assert(lost_backpack_sprite != null and lost_backpack_sprite.texture == lost_backpack.visual_texture(), "Utracony plecak powinien podlaczyc dedykowana grafike do ContainerSprite.")
	_assert(dive_map.world_pickups.size() == 11, "Zebrany wcześniej wolnostojący zasób nie może zostać odtworzony na kolejnej wyprawie.")
	for pickup in dive_map.world_pickups:
		_assert(pickup.pickup_id != collected_pickup_id, "Trwale zebrany pickup nie może wrócić do świata.")
	var buoy_count := 0
	var opened_shortcut_found := false
	for interactable in dive_map.persistent_interactables:
		if interactable.kind == PersistentInteractableScript.Kind.BUOY:
			buoy_count += 1
			_assert(interactable.visual_texture() != null and interactable.visual_texture().resource_path == "res://assets/diving/interactables/return_buoy.png", "Kazda kotwica boi powinna korzystac z dedykowanej grafiki.")
		elif interactable.kind == PersistentInteractableScript.Kind.SHORTCUT:
			_assert(interactable.visual_texture() != null and interactable.visual_texture().resource_path == "res://assets/diving/interactables/shortcut_gate.png", "Kazdy skrot powinien korzystac z grafiki fizycznej bramy.")
		elif interactable.kind == PersistentInteractableScript.Kind.HEAVY_OBJECT:
			var expected_heavy_paths := {
				"ship_engine_r1": "res://assets/diving/interactables/ship_engine.png",
				"shipyard_winch_r3": "res://assets/diving/interactables/shipyard_winch.png",
				"scrapyard_generator_r3": "res://assets/diving/interactables/industrial_generator.png",
			}
			var expected_heavy_path := str(expected_heavy_paths.get(interactable.persistent_id, ""))
			_assert(not expected_heavy_path.is_empty() and interactable.visual_texture() != null and interactable.visual_texture().resource_path == expected_heavy_path, "Kazdy ciezki obiekt powinien miec jawnie dopasowana grafike: %s." % interactable.persistent_id)
		if interactable.kind == PersistentInteractableScript.Kind.SHORTCUT and interactable.persistent_id == "SC-01":
			opened_shortcut_found = interactable.completed
	_assert(buoy_count == 2, "Aktywna boja jest punktem powrotu ExitLine; runtime powinien pokazać tylko dwie pozostałe kotwice bez nakładania sprite'ów.")
	_assert(opened_shortcut_found, "Otwarty skrót powinien zostać odtworzony bez aktywnej blokady.")

	if _failed:
		quit(1)
		return
	print("Continuous map collision test passed: shared-mask terrain chunks, streamed collision, authored detail layers and every reward/rescue point are physically reachable.")
	quit(0)

func _reachable_cells_from(dive_map, world_position: Vector2) -> PackedByteArray:
	var reachable := PackedByteArray()
	reachable.resize(dive_map._grid_width * dive_map._grid_height)
	var start_cell: Vector2i = dive_map._world_to_cell(world_position)
	if not dive_map._is_open_cell(start_cell.x, start_cell.y):
		return reachable
	var queue := PackedInt32Array()
	var start_index: int = start_cell.y * dive_map._grid_width + start_cell.x
	queue.append(start_index)
	reachable[start_index] = 1
	var cursor := 0
	var directions := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	while cursor < queue.size():
		var cell_index := queue[cursor]
		cursor += 1
		var cell := Vector2i(cell_index % dive_map._grid_width, cell_index / dive_map._grid_width)
		for direction in directions:
			var neighbor: Vector2i = cell + direction
			if not dive_map._is_open_cell(neighbor.x, neighbor.y):
				continue
			var neighbor_index: int = neighbor.y * dive_map._grid_width + neighbor.x
			if reachable[neighbor_index] == 1:
				continue
			reachable[neighbor_index] = 1
			queue.append(neighbor_index)
	return reachable


func _string_set(values: Array[String]) -> Dictionary:
	var result := {}
	for value in values:
		result[value] = true
	return result


func _find_pickup(pickups: Array, pickup_id: String):
	for pickup in pickups:
		if str(pickup.pickup_id) == pickup_id:
			return pickup
	return null


func _fixed_device_record(records: Array[Dictionary], device_id: String) -> Dictionary:
	for record in records:
		if str(record.get("id", "")) == device_id:
			return record
	return {}


func _find_buoy_record(records: Array[Dictionary], buoy_id: String) -> Dictionary:
	for record in records:
		if str(record.get("id", "")) == buoy_id:
			return record
	return {}

func _is_reachable(dive_map, reachable: PackedByteArray, world_position: Vector2) -> bool:
	var cell: Vector2i = dive_map._world_to_cell(world_position)
	if cell.x < 0 or cell.y < 0 or cell.x >= dive_map._grid_width or cell.y >= dive_map._grid_height:
		return false
	return reachable[cell.y * dive_map._grid_width + cell.x] == 1

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Continuous map collision test failed: " + message)
