extends SceneTree

const EnvironmentScript := preload("res://scripts/diving/UnderwaterEnvironment2D.gd")
const TerrainRendererScript := preload("res://scripts/diving/UnderwaterTerrainRenderer.gd")
const CurrentVisualScript := preload("res://scripts/diving/DiveCurrentVisual.gd")
const SIX_LAYER_VISUALS_SCENE_PATH := "res://scenes/diving/map_visuals/UnderwaterMapSixLayerVisuals.tscn"
const LAYER_ELEMENT_TEMPLATE_PATH := "res://scenes/diving/map_visuals/LayerVisualElement.tscn"
const RESIDENT_ELEMENT_TEST_TEXTURE := "res://assets/diving/world/map_v2/visual_chunks/environment_decoration/chunk_04_01.png"
const UNSAFE_NESTED_VISUAL_SCENE_PATH := "res://tests/fixtures/unsafe_visual_nested_instance.tscn"
const UNSAFE_CAMERA_VISUAL_SCENE_PATH := "res://tests/fixtures/unsafe_visual_camera.tscn"
const UnsafeLayerElementSubclassScript := preload("res://tests/fixtures/unsafe_visual_layer_element_subclass.gd")

const EXPECTED_VISUAL_LAYER_IDS: Array[StringName] = [
	&"L00_base_color",
	&"L01_ultra_far_silhouettes",
	&"L02_far_structures",
	&"L03_mid_drift_props",
	&"L04_near_terrain_skin",
	&"L05_foreground_occluders",
]

const PROFILE_PATHS := [
	"res://data/diving_visuals/r1_rooftops.tres",
	"res://data/diving_visuals/r2_green_estates.tres",
	"res://data/diving_visuals/r3_rust_belt.tres",
	"res://data/diving_visuals/r4_black_heart.tres",
]

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profiles: Array[Resource] = []
	for profile_path in PROFILE_PATHS:
		var profile := ResourceLoader.load(profile_path)
		_assert(profile != null, "Każdy z czterech regionów musi mieć wczytywalny profil prezentacyjny.")
		if profile != null:
			profiles.append(profile)

	var environment := EnvironmentScript.new()
	root.add_child(environment)
	environment.configure(Vector2(11_520.0, 6_480.0), profiles)
	environment.set_visual_time_for_tests(2.75)
	environment.update_environment(
		0.58,
		Color(0.16, 0.21, 0.18, 1.0),
		Color(0.86, 0.46, 0.20, 1.0),
		Vector2(48.0, -22.0),
		Vector2(5_600.0, 3_400.0),
		0.0,
		0.42,
		0.68,
		0.22
	)

	environment.set_graphics_quality("low")
	var low_state: Dictionary = environment.environment_state()
	_assert(not bool(low_state.get("refraction_enabled", true)), "Low nie może wykonywać refrakcji ekranu.")
	_assert(int(low_state.get("far_particle_count", 0)) == 32, "Low powinno utrzymywać budżet 32 dalekich drobin.")
	_assert(int(low_state.get("near_particle_count", -1)) == 0, "Low nie powinno tworzyć bliskiej warstwy drobin.")
	var low_shafts_intensity := float(low_state.get("light_shafts_intensity", -1.0))
	_assert(low_shafts_intensity > 0.0, "Low ma zachować statyczną, oszczędną warstwę promieni światła.")

	environment.set_graphics_quality("medium")
	var medium_state: Dictionary = environment.environment_state()
	_assert(bool(medium_state.get("refraction_enabled", false)), "Medium powinno włączać subtelną refrakcję.")
	_assert(int(medium_state.get("far_particle_count", 0)) == 56, "Medium powinno utrzymywać budżet 56 dalekich drobin.")
	_assert(int(medium_state.get("near_particle_count", 0)) == 8, "Medium powinno utrzymywać 8 bliskich drobin.")
	var medium_shafts_intensity := float(medium_state.get("light_shafts_intensity", -1.0))
	_assert(medium_shafts_intensity > low_shafts_intensity, "Medium musi zwiększać czytelność promieni względem Low.")

	environment.set_graphics_quality("high")
	var high_state: Dictionary = environment.environment_state()
	_assert(bool(high_state.get("refraction_enabled", false)), "High powinno włączać subtelną refrakcję.")
	_assert(int(high_state.get("far_particle_count", 0)) == 96, "High powinno utrzymywać budżet 96 dalekich drobin.")
	_assert(int(high_state.get("near_particle_count", 0)) == 16, "High powinno utrzymywać 16 bliskich drobin.")
	_assert(is_equal_approx(float(high_state.get("visual_time", -1.0)), 2.75), "Jawny czas VFX musi pozostać deterministyczny.")
	_assert(is_equal_approx(float(high_state.get("water_clarity", -1.0)), 0.42), "Środowisko musi konsumować przejrzystość aktywnego profilu regionu.")
	_assert(is_equal_approx(float(high_state.get("suspended_particle_density", -1.0)), 0.68), "Środowisko musi konsumować gęstość zawiesiny aktywnego regionu.")
	_assert(float(high_state.get("caustics_intensity", -1.0)) > 0.0, "Profil i jakość muszą składać dodatni, budżetowany sygnał caustics.")
	_assert(float(high_state.get("light_shafts_intensity", -1.0)) > medium_shafts_intensity, "High musi zwiększać czytelność promieni względem Medium.")

	environment.set_reduced_motion(true)
	var reduced_state: Dictionary = environment.environment_state()
	_assert(bool(reduced_state.get("reduced_motion", false)), "Reduced motion musi dotrzeć do środowiska.")
	_assert(not bool(reduced_state.get("refraction_enabled", true)), "Reduced motion musi całkowicie wyłączyć refrakcję.")
	_assert(int(reduced_state.get("near_particle_count", 0)) == 16, "Reduced motion ma zachować statyczną atmosferę i budżet cząstek.")
	await _test_six_layer_motion_contract()

	var current_visual := CurrentVisualScript.new()
	root.add_child(current_visual)
	current_visual.set_reduced_motion(true)
	current_visual.update_sample(Vector2(48.0, -22.0), Vector2(640.0, 360.0), 1.0, true)
	_assert(current_visual.reduced_motion_enabled(), "Reduced motion musi dotrzeć do smug prądu.")
	_assert(is_zero_approx(current_visual.visual_time()), "Smugi prądu nie mogą przesuwać się przy reduced motion.")
	current_visual.set_reduced_motion(false)
	current_visual.update_sample(Vector2(48.0, -22.0), Vector2(640.0, 360.0), 0.5, false)
	_assert(is_equal_approx(current_visual.visual_time(), 0.5), "Bez reduced motion smugi prądu muszą korzystać z jawnego delta.")
	current_visual.set_graphics_quality("low")
	_assert(current_visual.graphics_quality() == "low" and current_visual.sample_budget() == 20, "Low ma ograniczyć organiczne próbki prądu do 20.")
	current_visual.set_graphics_quality("medium")
	_assert(current_visual.sample_budget() == 30, "Medium ma używać 30 próbek prądu.")
	current_visual.set_graphics_quality("high")
	_assert(current_visual.sample_budget() == 40, "High ma używać pełnych 40 próbek prądu bez zmiany wektora gameplayowego.")

	var renderer := TerrainRendererScript.new()
	renderer.region_profiles.assign(profiles)
	renderer.contour_mask = ResourceLoader.load("res://assets/diving/world/map_v2/world_collision_grid.png")
	renderer.contour_sdf = ResourceLoader.load("res://assets/diving/world/map_v2/world_collision_render_sdf_v1.png")
	renderer.rock_detail_texture = ResourceLoader.load("res://assets/diving/world/materials/underwater_rock_detail_premium_v5.png")
	root.add_child(renderer)
	_assert(renderer.validation_errors().is_empty(), "Produkcyjny renderer terenu i profile muszą przejść walidację.")
	renderer.set_anim_time(3.25)
	renderer.set_active_chunks(["0:0", "0:3", "0:7", "0:7", "999:999"])
	renderer.set_reduced_motion(false)
	renderer.set_graphics_quality("low")
	var low_renderer_state: Dictionary = renderer.presentation_state()
	_assert(str(low_renderer_state.get("graphics_quality", "")) == "low", "Jakość grafiki musi dotrzeć do materiału terenu.")
	_assert(not bool(low_renderer_state.get("reduced_motion", true)), "Zwykły wariant renderera nie może oznaczać reduced motion.")
	_assert(is_equal_approx(float(low_renderer_state.get("anim_time", -1.0)), 3.25), "Renderer terenu musi korzystać z jawnego czasu animacji.")
	_assert(int(low_renderer_state.get("active_chunk_count", 0)) == 3, "Renderer ma deduplikować i odrzucać chunki poza mapą.")
	_assert(bool(low_renderer_state.get("uses_global_depth_profiles", false)), "Wszystkie chunki muszą dzielić globalny profil głębokości bez pasów na granicach.")
	_assert(int(low_renderer_state.get("water_material_count", 0)) == 1, "Chunki w różnych regionach powinny współdzielić jeden materiał wody.")
	_assert(int(low_renderer_state.get("terrain_material_count", 0)) == 1, "Chunki w różnych regionach powinny współdzielić jeden materiał skał.")
	_assert(bool(low_renderer_state.get("uses_global_water_layer", false)), "Woda powinna być pojedynczą warstwą świata bez szwów geometrii chunków.")
	_assert(bool(low_renderer_state.get("uses_global_backdrop_layer", false)), "Dalekie tło biomów powinno być jedną globalną warstwą świata.")
	_assert(int(low_renderer_state.get("backdrop_material_count", 0)) == 1, "Dalekie tło biomów powinno współdzielić jeden materiał między regionami.")
	_assert(int(low_renderer_state.get("backdrop_z_index", 0)) == -95, "Dalekie tło biomów powinno leżeć między wodą a dekoracjami środowiska.")
	_assert(is_equal_approx(float(low_renderer_state.get("backdrop_quality_level", -1.0)), 0.0), "Low musi przekazać poziom 0 do materiału dalekiego tła.")
	_assert(not bool(low_renderer_state.get("backdrop_reduced_motion", true)), "Zwykły wariant dalekiego tła nie może oznaczać reduced motion.")
	_assert(is_equal_approx(float(low_renderer_state.get("backdrop_anim_time", -1.0)), 3.25), "Dalekie tło powinno używać jawnego czasu animacji poza reduced motion.")
	_assert(not low_renderer_state.has("backdrop_view_center"), "Renderer nie może już przekazywać shaderowi drugiego, ręcznie synchronizowanego parallaxu.")
	_assert(bool(low_renderer_state.get("uses_global_terrain_layer", false)), "Proceduralna skała powinna być pojedynczą warstwą świata bez szwów geometrii chunków.")
	_assert(bool(low_renderer_state.get("uses_derived_contour_sdf", false)), "Krawędź skał powinna korzystać z prezentacyjnego SDF wyprowadzonego z maski semantycznej.")

	renderer.set_graphics_quality("medium")
	var medium_renderer_state: Dictionary = renderer.presentation_state()
	_assert(is_equal_approx(float(medium_renderer_state.get("backdrop_quality_level", -1.0)), 1.0), "Medium musi przekazać poziom 1 do materiału dalekiego tła.")
	_assert(is_equal_approx(float(medium_renderer_state.get("backdrop_anim_time", -1.0)), 3.25), "Medium musi zachować jawny czas animacji dalekiego tła.")
	_assert(int(medium_renderer_state.get("active_chunk_count", 0)) == 3, "Zmiana jakości nie może zmienić aktywnego pierścienia chunków renderera.")

	renderer.set_graphics_quality("high")
	var high_renderer_state: Dictionary = renderer.presentation_state()
	_assert(is_equal_approx(float(high_renderer_state.get("backdrop_quality_level", -1.0)), 2.0), "High musi przekazać poziom 2 do materiału dalekiego tła.")
	_assert(is_equal_approx(float(high_renderer_state.get("backdrop_anim_time", -1.0)), 3.25), "High musi zachować jawny czas animacji dalekiego tła.")
	_assert(int(high_renderer_state.get("active_chunk_count", 0)) == 3, "Zmiana jakości nie może zmienić aktywnego pierścienia chunków renderera.")

	renderer.set_reduced_motion(true)
	var renderer_state: Dictionary = renderer.presentation_state()
	_assert(str(renderer_state.get("graphics_quality", "")) == "high", "Zmiana jakości high powinna pozostać aktywna po włączeniu reduced motion.")
	_assert(bool(renderer_state.get("reduced_motion", false)), "Reduced motion musi dotrzeć do materiału terenu.")
	_assert(bool(renderer_state.get("uses_global_backdrop_layer", false)), "Reduced motion nie może usuwać statycznej warstwy dalekiego tła.")
	_assert(bool(renderer_state.get("backdrop_reduced_motion", false)), "Reduced motion musi dotrzeć do materiału dalekiego tła.")
	_assert(is_equal_approx(float(renderer_state.get("backdrop_anim_time", -1.0)), 0.0), "Reduced motion musi zatrzymać animację dalekiego tła bez zmiany jego palety.")
	_assert(int(renderer_state.get("active_chunk_count", 0)) == 3, "Reduced motion nie może zmienić aktywnego pierścienia chunków renderera.")
	_assert(renderer.contour_sdf != null and renderer.contour_sdf.get_size() == renderer.contour_mask.get_size(), "SDF i pochodny raster scenowego makroterenu muszą mieć identyczną siatkę.")
	var navigation_manifest_path := "res://assets/diving/world/map_v2/world_collision_grid.json"
	var navigation_manifest_variant = JSON.parse_string(FileAccess.get_file_as_string(navigation_manifest_path))
	_assert(navigation_manifest_variant is Dictionary, "Pochodny raster nawigacji musi mieć poprawny manifest JSON.")
	if navigation_manifest_variant is Dictionary:
		var navigation_manifest: Dictionary = navigation_manifest_variant
		_assert(str(navigation_manifest.get("authority_path", "")) == "res://scenes/diving/UnderwaterMap.tscn", "Manifest rastra musi wskazywać scenę Godot jako authority makroterenu.")
		_assert(str(navigation_manifest.get("authority_node_path", "")) == "Terrain/TerrainNavigation", "Manifest rastra musi wskazywać scenowy węzeł TerrainNavigation.")
		_assert(str(navigation_manifest.get("semantic_contract", "")) == "polygon_scene_default_blocked_open_then_islands", "Manifest rastra musi opisywać semantykę scenowych Polygon2D.")
		_assert(str(navigation_manifest.get("geometry_sha256", "")).length() == 64 and str(navigation_manifest.get("cells_sha256", "")).length() == 64, "Manifest rastra musi utrwalać hash geometrii i komórek.")
		_assert(str(navigation_manifest.get("output_sha256", "")) == FileAccess.get_sha256("res://assets/diving/world/map_v2/world_collision_grid.png").to_lower(), "Manifest rastra musi wskazywać rzeczywisty hash pochodnego PNG.")
	var sdf_manifest_path := "res://assets/diving/world/map_v2/world_collision_render_sdf_v1.json"
	var sdf_manifest_variant = JSON.parse_string(FileAccess.get_file_as_string(sdf_manifest_path))
	_assert(sdf_manifest_variant is Dictionary, "Manifest pochodzenia SDF musi być poprawnym obiektem JSON.")
	if sdf_manifest_variant is Dictionary:
		var sdf_manifest: Dictionary = sdf_manifest_variant
		_assert(str(sdf_manifest.get("semantic_contract", "")) == "derived_bright_blocked_dark_traversable", "Manifest SDF musi opisywać drugi etap pochodny od scenowych Polygon2D.")
		_assert(str(sdf_manifest.get("source_sha256", "")) == FileAccess.get_sha256("res://assets/diving/world/map_v2/world_collision_grid.png").to_lower(), "Manifest SDF musi wskazywać bieżący hash pochodnego rastra sceny.")
		_assert(str(sdf_manifest.get("output_sha256", "")) == FileAccess.get_sha256("res://assets/diving/world/map_v2/world_collision_render_sdf_v1.png").to_lower(), "Manifest SDF musi wskazywać rzeczywisty hash wygenerowanej tekstury.")
		_assert(is_equal_approx(float(sdf_manifest.get("spread_texels", 0.0)), 12.0), "Shader i generator muszą zachować zatwierdzony zasięg SDF 12 texeli źródłowych.")
		_assert(is_equal_approx(float(sdf_manifest.get("smooth_radius_texels", 0.0)), 1.75), "Pochodny SDF musi zachować deterministyczne, prezentacyjne wygładzenie konturu.")
	var terrain_shader := ResourceLoader.load("res://assets/diving/world/shaders/underwater_terrain.gdshader") as Shader
	var water_shader := ResourceLoader.load("res://assets/diving/world/shaders/underwater_water.gdshader") as Shader
	var backdrop_shader := ResourceLoader.load("res://assets/diving/world/shaders/underwater_biome_backdrop.gdshader") as Shader
	var authored_backdrop_shader := ResourceLoader.load("res://assets/diving/world/shaders/underwater_authored_backdrop.gdshader") as Shader
	var light_shafts_shader := ResourceLoader.load("res://assets/diving/world/shaders/underwater_light_shafts.gdshader") as Shader
	var post_process_shader := ResourceLoader.load("res://assets/diving/world/shaders/underwater_post_process.gdshader") as Shader
	_assert(terrain_shader != null and not terrain_shader.code.contains("render_mode unshaded"), "Aktywny teren musi przyjmować lokalne światło latarki.")
	_assert(water_shader != null and not water_shader.code.contains("render_mode unshaded"), "Aktywna warstwa wody musi przyjmować lokalne światło latarki.")
	_assert(backdrop_shader != null and backdrop_shader.code.contains("render_mode unshaded"), "Daleki plan nie może udawać pierwszego planu oświetlanego latarką.")
	_assert(backdrop_shader != null and backdrop_shader.code.contains("r1_city_backdrop") and backdrop_shader.code.contains("r2_garden_backdrop") and backdrop_shader.code.contains("r3_industry_backdrop") and backdrop_shader.code.contains("r4_monument_backdrop"), "Każdy region musi mieć własny motyw dalekiego planu.")
	_assert(backdrop_shader != null and backdrop_shader.code.contains("distant_position") and backdrop_shader.code.contains("reduced_motion ? 0.0 : anim_time"), "Daleki plan musi zachować falowanie i deterministyczne zatrzymanie ruchu.")
	_assert(backdrop_shader != null and not backdrop_shader.code.contains("uniform vec2 view_center") and not backdrop_shader.code.contains("parallax_factor"), "Shader dalekiego planu nie może dublować parallaxu obsługiwanego przez Parallax2D.")
	_assert(backdrop_shader != null and backdrop_shader.code.contains("region_transition(region_depth") and backdrop_shader.code.contains("smoothstep(0.82, 1.0, local_depth)"), "Granice motywów dalekiego planu muszą używać tego samego przejścia co woda i teren.")
	_assert(authored_backdrop_shader != null and authored_backdrop_shader.code.contains("render_mode unshaded") and authored_backdrop_shader.code.contains("edge_fade"), "Autorski średni plan musi zachować baked lighting i miękko znikać na krawędziach.")
	_assert(light_shafts_shader != null and light_shafts_shader.code.contains("render_mode unshaded, blend_add") and light_shafts_shader.code.contains("reduced_motion ? 0.0 : anim_time") and light_shafts_shader.code.contains("quality_level"), "Promienie mają być addytywne, budżetowane jakością i deterministycznie zatrzymywane.")
	_assert(terrain_shader != null and terrain_shader.code.contains("blended_profile_value"), "Teren musi wyliczać profil z globalnej głębokości, niezależnie od środka chunka.")
	_assert(terrain_shader != null and terrain_shader.code.contains("fwidth(sdf_value)"), "Shader terenu musi wygładzać pochodny kontur SDF w przestrzeni ekranu.")
	_assert(terrain_shader != null and terrain_shader.code.contains("float terrain_fbm(vec2 point)") and terrain_shader.code.contains("oblique_noise_a") and terrain_shader.code.contains("oblique_noise_b"), "Szerokie pola materiału skał muszą mieszać obrócone domeny szumu bez osiowych prostokątów.")
	_assert(terrain_shader != null and terrain_shader.code.contains("terrain_fbm(world_position / 610.0") and terrain_shader.code.contains("terrain_fbm(world_position / 360.0") and terrain_shader.code.contains("terrain_fbm(world_position / 188.0"), "Makrorelief, osad i minerały muszą korzystać z deterministycznych pól świata.")
	_assert(terrain_shader != null and terrain_shader.code.contains("if (!has_detail_texture)") and terrain_shader.code.contains("authored_detail_luminance(texture(rock_detail_texture, detail_uv).rgb)"), "Produkcyjny kolor i relief skały muszą korzystać z autorskiego kafla, a proceduralna siatka wyłącznie z fallbacku.")
	_assert(terrain_shader != null and terrain_shader.code.contains("NORMAL_MAP =") and terrain_shader.code.contains("NORMAL_MAP_DEPTH"), "Relief skały musi trafiać do potoku normalnych 2D i reagować na lokalne światła.")
	var rock_detail_import := FileAccess.get_file_as_string("res://assets/diving/world/materials/underwater_rock_detail_premium_v5.png.import")
	_assert(rock_detail_import.contains("mipmaps/generate=true"), "Powtarzalny detal skały musi generować mipmapy dla filtrowania oddalonego materiału.")
	var detail_manifest_variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/diving/world/materials/underwater_rock_detail_premium_v5.json"))
	_assert(detail_manifest_variant is Dictionary, "Bezszwowy detal skały musi mieć manifest pochodzenia.")
	if detail_manifest_variant is Dictionary:
		var detail_manifest: Dictionary = detail_manifest_variant
		_assert(bool(detail_manifest.get("seamless", false)), "Manifest produkcyjnego materiału musi potwierdzać kontrolę bezszwowego kafla.")
		_assert(int(detail_manifest.get("width", 0)) == 1254 and int(detail_manifest.get("height", 0)) == 1254, "Manifest musi zachować zweryfikowany rozmiar kafla materiału.")
		_assert(str(detail_manifest.get("output_sha256", "")) == FileAccess.get_sha256("res://assets/diving/world/materials/underwater_rock_detail_premium_v5.png").to_lower(), "Manifest detalu musi wskazywać rzeczywisty produkcyjny kafel.")
	_assert(water_shader != null and water_shader.code.contains("blended_profile_value"), "Woda musi wyliczać profil z globalnej głębokości, niezależnie od środka chunka.")
	_assert(post_process_shader != null and post_process_shader.code.contains("SCREEN_PIXEL_SIZE"), "Ziarno postprocessu musi skalować się z rzeczywistym rozmiarem viewportu.")
	_assert(post_process_shader != null and not post_process_shader.code.contains("vec2(1280.0, 720.0)"), "Postprocess nie może kodować rozdzielczości referencyjnej na stałe.")
	_assert(post_process_shader != null and post_process_shader.code.contains("filter_linear_mipmap") and post_process_shader.code.contains("textureLod") and post_process_shader.code.contains("bloom_strength"), "Postprocess High/Medium musi korzystać z kontrolowanego, jednoprzejściowego bloom LDR.")

	if _failed:
		quit(1)
		return
	print("Underwater environment test passed: global region profiles, quality budgets, reduced motion and viewport-scaled postprocess work.")
	quit(0)


func _test_six_layer_motion_contract() -> void:
	var packed := ResourceLoader.load(SIX_LAYER_VISUALS_SCENE_PATH) as PackedScene
	_assert(packed != null, "Scena sześciu niezależnych warstw musi dać się załadować.")
	if packed == null:
		return
	var stack := packed.instantiate() as DiveVisualLayerStack
	_assert(stack != null, "Korzeń kompozycji musi implementować DiveVisualLayerStack.")
	if stack == null:
		return
	var authored_layer := stack.layer_root(&"L03_mid_drift_props")
	var authored_parallax := authored_layer.get_node("ParallaxContent") as Parallax2D
	_assert(authored_parallax.scroll_offset.is_equal_approx(Vector2.ZERO), "Każda warstwa musi startować z autorskim scroll_offset = ZERO.")
	authored_parallax.scroll_offset = Vector2(19.0, -7.0)
	var nonzero_authored_offset_rejected := false
	for validation_error in authored_layer.validation_errors():
		if String(validation_error).contains("autorskiego scroll_offset = Vector2.ZERO"):
			nonzero_authored_offset_rejected = true
			break
	_assert(nonzero_authored_offset_rejected, "Walidator musi odrzucać zapisany w scenie, niezerowy scroll_offset warstwy.")
	authored_parallax.scroll_offset = Vector2.ZERO
	var editor_offset_result := DiveVisualLayer._profile_application_scroll_offset(
		Vector2(37.0, -21.0),
		Vector2(0.94, 0.94),
		Vector2(0.97, 0.97),
		Vector2(4_800.0, -1_600.0),
		true,
		true
	)
	_assert(editor_offset_result.is_equal_approx(Vector2.ZERO), "Edycja profilu w @tool musi zerować baseline zamiast kompensować pozycję viewportu edytora.")
	_test_visual_packed_scene_side_effect_preflight()
	root.add_child(stack)
	await process_frame
	_assert(stack.validation_errors().is_empty(), "Sześć profili i ich węzły muszą tworzyć poprawny stos.")
	var refresh_layer := stack.layer_root(&"L03_mid_drift_props")
	var refresh_parallax := refresh_layer.get_node("ParallaxContent") as Parallax2D
	var refresh_screen_offset := Vector2(3_271.25, -1_407.5)
	var refresh_target_scale := refresh_layer.profile.normal_scroll_scale
	refresh_parallax.screen_offset = refresh_screen_offset
	refresh_parallax.scroll_scale = refresh_target_scale
	refresh_parallax.scroll_offset = Vector2(1.0, -1.0)
	refresh_parallax.scroll_offset = Vector2.ZERO
	var expected_refreshed_position := refresh_parallax.position
	refresh_parallax.scroll_scale = Vector2.ONE
	refresh_parallax.scroll_offset = Vector2(1.0, -1.0)
	refresh_parallax.scroll_offset = Vector2.ZERO
	_assert(not refresh_parallax.position.is_equal_approx(expected_refreshed_position), "Test odświeżenia wymaga dwóch różnych pozycji dla scroll_scale=1 i profilu przy niezerowym screen_offset.")
	refresh_parallax.scroll_scale = refresh_target_scale
	refresh_layer._apply_profile(false)
	_assert(refresh_parallax.scroll_offset.is_equal_approx(Vector2.ZERO), "Odświeżenie profilu nie może zapisać przesunięcia przy wyłączonej kompensacji.")
	_assert(refresh_parallax.position.is_equal_approx(expected_refreshed_position), "Ponowne ustawienie profilu musi natychmiast odświeżyć Parallax2D także przy identycznym zerowym scroll_offset.")
	var normal_scales := {}
	var normal_offsets := {}
	var normal_positions := {}
	var screen_offsets := {}
	var previous_scale := Vector2(-INF, -INF)
	for layer_index in range(EXPECTED_VISUAL_LAYER_IDS.size()):
		var layer_id := EXPECTED_VISUAL_LAYER_IDS[layer_index]
		var layer := stack.layer_root(layer_id)
		_assert(layer != null and layer.visible, "Warstwa %s musi być obecna i widoczna w zwykłym trybie." % layer_id)
		if layer == null:
			continue
		var parallax := layer.get_node_or_null("ParallaxContent") as Parallax2D
		_assert(parallax != null, "Warstwa %s musi używać natywnego Parallax2D." % layer_id)
		if parallax == null:
			continue
		parallax.screen_offset = Vector2(4_231.25 + 137.0 * layer_index, -1_732.5 + 91.0 * layer_index)
		normal_scales[layer_id] = parallax.scroll_scale
		normal_offsets[layer_id] = parallax.scroll_offset
		normal_positions[layer_id] = parallax.position
		screen_offsets[layer_id] = parallax.screen_offset
		_assert(parallax.scroll_scale.x > previous_scale.x and parallax.scroll_scale.y > previous_scale.y, "Dalsza warstwa musi przesuwać się wolniej niż każda kolejna, bliższa warstwa.")
		previous_scale = parallax.scroll_scale
	stack.set_reduced_motion(true)
	for layer_id in EXPECTED_VISUAL_LAYER_IDS:
		var layer := stack.layer_root(layer_id)
		if layer == null:
			continue
		var parallax := layer.get_node_or_null("ParallaxContent") as Parallax2D
		_assert(layer.visible, "Reduced motion nie może ukryć warstwy %s." % layer_id)
		_assert(parallax != null and parallax.scroll_scale.is_equal_approx(Vector2.ONE), "Reduced motion musi ustawić scroll_scale=1 dla %s." % layer_id)
		if parallax != null:
			var normal_scale: Vector2 = normal_scales.get(layer_id, Vector2.ONE)
			var normal_offset: Vector2 = normal_offsets.get(layer_id, Vector2.ZERO)
			var screen_offset: Vector2 = screen_offsets.get(layer_id, Vector2.ZERO)
			var expected_offset := normal_offset + (Vector2.ONE - normal_scale) * screen_offset
			_assert(parallax.scroll_offset.is_equal_approx(expected_offset), "Reduced motion musi użyć dokładnego screen_offset Parallax2D dla %s." % layer_id)
			_assert(parallax.position.is_equal_approx(normal_positions.get(layer_id, Vector2.ZERO)), "Włączenie reduced motion nie może przesunąć warstwy %s nawet przed następną klatką." % layer_id)
		_assert(layer.get_node_or_null("WorldContent") != null and layer.get_node("WorldContent").visible, "Reduced motion nie może ukryć treści związanej ze światem w %s." % layer_id)
	var reduced_positions := {}
	var reduced_offsets := {}
	for layer_index in range(EXPECTED_VISUAL_LAYER_IDS.size()):
		var layer_id := EXPECTED_VISUAL_LAYER_IDS[layer_index]
		var layer := stack.layer_root(layer_id)
		var parallax := layer.get_node_or_null("ParallaxContent") as Parallax2D
		parallax.screen_offset += Vector2(311.5 + layer_index, -207.25 - layer_index)
		reduced_positions[layer_id] = parallax.position
		reduced_offsets[layer_id] = parallax.scroll_offset
	stack.set_reduced_motion(false)
	for layer_id in EXPECTED_VISUAL_LAYER_IDS:
		var layer := stack.layer_root(layer_id)
		if layer == null:
			continue
		var parallax := layer.get_node_or_null("ParallaxContent") as Parallax2D
		_assert(parallax != null and parallax.scroll_scale.is_equal_approx(normal_scales.get(layer_id, Vector2.ZERO)), "Wyłączenie reduced motion musi przywrócić autorski scroll_scale %s." % layer_id)
		if parallax != null:
			var normal_scale: Vector2 = normal_scales.get(layer_id, Vector2.ONE)
			var expected_offset: Vector2 = reduced_offsets.get(layer_id, Vector2.ZERO) + (normal_scale - Vector2.ONE) * parallax.screen_offset
			_assert(parallax.scroll_offset.is_equal_approx(expected_offset), "Wyłączenie reduced motion musi skompensować aktualny screen_offset %s." % layer_id)
			_assert(parallax.position.is_equal_approx(reduced_positions.get(layer_id, Vector2.ZERO)), "Wyłączenie reduced motion nie może przesunąć warstwy %s nawet przed następną klatką." % layer_id)
	var positions_before_round_trip := {}
	for layer_id in EXPECTED_VISUAL_LAYER_IDS:
		positions_before_round_trip[layer_id] = (stack.layer_root(layer_id).get_node("ParallaxContent") as Parallax2D).position
	stack.set_reduced_motion(true)
	stack.set_reduced_motion(false)
	for layer_id in EXPECTED_VISUAL_LAYER_IDS:
		var parallax := stack.layer_root(layer_id).get_node("ParallaxContent") as Parallax2D
		_assert(parallax.position.is_equal_approx(positions_before_round_trip.get(layer_id, Vector2.ZERO)), "Round-trip reduced motion przy nieruchomej kamerze musi być ciągły dla %s." % layer_id)
	var live_layer := stack.layer_root(&"L03_mid_drift_props")
	var live_parallax := live_layer.get_node("ParallaxContent") as Parallax2D
	var original_live_scale := live_layer.profile.normal_scroll_scale
	live_parallax.screen_offset = Vector2(3_417.25, -1_289.75)
	var live_position_before := live_parallax.position
	var edited_live_scale := original_live_scale - Vector2(0.005, 0.005)
	live_layer.profile.normal_scroll_scale = edited_live_scale
	_assert(live_parallax.scroll_scale.is_equal_approx(edited_live_scale), "Zmiana profilu w Inspectorze musi natychmiast ustawić nowy scroll_scale.")
	_assert(live_parallax.position.is_equal_approx(live_position_before), "Zmiana profilu na żywo nie może wywołać skoku warstwy przy niezerowym screen_offset.")
	live_layer.profile.normal_scroll_scale = original_live_scale
	_assert(live_parallax.position.is_equal_approx(live_position_before), "Przywrócenie profilu na żywo także musi zachować ciągłość położenia.")
	_test_layer_element_authoring_contract(stack)
	stack.queue_free()
	await process_frame


func _test_layer_element_authoring_contract(stack: DiveVisualLayerStack) -> void:
	var legacy_elements: Array[DiveVisualLayerElement] = []
	for node in stack.find_children("*", "", true, false):
		if node is DiveVisualLayerElement:
			legacy_elements.append(node as DiveVisualLayerElement)
	_assert(legacy_elements.size() == 15, "Kompozycja musi zachować 15 niezależnych, jawnie streamowanych elementów legacy.")
	for element in legacy_elements:
		_assert(element.is_manifest_streamed(), "Element legacy %s musi pozostać manifest-streamed." % element.element_id)
	var hidden_layer := stack.layer_root(&"L03_mid_drift_props")
	hidden_layer.visible = false
	stack.set_graphics_quality("low")
	stack.set_graphics_quality("high")
	stack.set_reduced_motion(true)
	stack.set_reduced_motion(false)
	_assert(not hidden_layer.visible, "Autorskie visible=false warstwy musi przetrwać jakość i reduced motion.")
	hidden_layer.visible = true
	var template := ResourceLoader.load(LAYER_ELEMENT_TEMPLATE_PATH) as PackedScene
	_assert(template != null, "Szablon niezależnego elementu musi być dostępny.")
	if template == null:
		return
	var element := template.instantiate() as DiveVisualLayerElement
	element.element_id = &"scene_resident_contract_test"
	element.resource_path = RESIDENT_ELEMENT_TEST_TEXTURE
	element.local_bounds = Rect2(0.0, 0.0, 620.0, 167.0)
	element.position = Vector2(17.0, -9.0)
	element.rotation = 0.31
	element.scale = Vector2(1.4, 0.65)
	var authored_root := stack.content_root(&"L03_mid_drift_props", &"parallax", &"authored")
	authored_root.add_child(element)
	_assert(not element.is_manifest_streamed() and element.runtime_content_node() is Sprite2D, "Nowy scene-resident element musi działać w runtime bez wpisu manifestu.")
	_assert(element.position == Vector2(17.0, -9.0) and is_equal_approx(element.rotation, 0.31) and element.scale == Vector2(1.4, 0.65), "Runtime nie może nadpisać przesunięcia, obrotu ani niejednorodnej skali elementu.")
	element.visible = false
	element.set_graphics_quality("low")
	element.set_graphics_quality("high")
	_assert(not element.visible, "Autorskie visible=false elementu musi przetrwać zmianę jakości.")
	authored_root.remove_child(element)
	element.free()
	var unsafe_direct_remote := RemoteTransform2D.new()
	authored_root.add_child(unsafe_direct_remote)
	var direct_side_effect_rejected := false
	for validation_error in stack.validation_errors():
		if String(validation_error).contains("RemoteTransform2D"):
			direct_side_effect_rejected = true
			break
	_assert(direct_side_effect_rejected, "Bezpośredni RemoteTransform2D w Authored musi podlegać tej samej bramce bezpieczeństwa co PackedScene.")
	authored_root.remove_child(unsafe_direct_remote)
	unsafe_direct_remote.free()
	var unsafe_tile_map := TileMapLayer.new()
	authored_root.add_child(unsafe_tile_map)
	var tile_map_rejected := false
	for validation_error in stack.validation_errors():
		if String(validation_error).contains("TileMapLayer"):
			tile_map_rejected = true
			break
	_assert(tile_map_rejected, "TileMapLayer w Authored musi być odrzucony, bo TileSet może wnosić kolizję lub nawigację.")
	authored_root.remove_child(unsafe_tile_map)
	unsafe_tile_map.free()
	var unsafe_control := Button.new()
	authored_root.add_child(unsafe_control)
	var control_rejected := false
	for validation_error in stack.validation_errors():
		if String(validation_error).contains("Button"):
			control_rejected = true
			break
	_assert(control_rejected, "Control w Authored musi być odrzucony, aby nie przechwytywał wejścia ani fokusu UI.")
	authored_root.remove_child(unsafe_control)
	unsafe_control.free()
	var unsafe_nested_parallax := Parallax2D.new()
	authored_root.add_child(unsafe_nested_parallax)
	var nested_parallax_rejected := false
	for validation_error in stack.validation_errors():
		if String(validation_error).contains("Parallax2D"):
			nested_parallax_rejected = true
			break
	_assert(nested_parallax_rejected, "Autorski element nie może tworzyć siódmego tempa Parallax2D poza kontrolą reduced motion.")
	authored_root.remove_child(unsafe_nested_parallax)
	unsafe_nested_parallax.free()
	var unsafe_subclass := UnsafeLayerElementSubclassScript.new() as DiveVisualLayerElement
	unsafe_subclass.element_id = &"unsafe_scripted_subclass"
	unsafe_subclass.resource_path = RESIDENT_ELEMENT_TEST_TEXTURE
	unsafe_subclass.local_bounds = Rect2(0.0, 0.0, 620.0, 167.0)
	var unsafe_subclass_attachment := Node2D.new()
	unsafe_subclass_attachment.name = "Attachment"
	unsafe_subclass.add_child(unsafe_subclass_attachment)
	authored_root.add_child(unsafe_subclass)
	var subclass_script_rejected := false
	for validation_error in stack.validation_errors():
		if String(validation_error).contains("własnego skryptu runtime"):
			subclass_script_rejected = true
			break
	_assert(subclass_script_rejected, "Podklasa DiveVisualLayerElement nie może przemycić własnego _ready/_process przez wyjątek skryptu kanonicznego.")
	authored_root.remove_child(unsafe_subclass)
	unsafe_subclass.free()


func _test_visual_packed_scene_side_effect_preflight() -> void:
	var unsafe_nested_scene := ResourceLoader.load(UNSAFE_NESTED_VISUAL_SCENE_PATH) as PackedScene
	_assert(unsafe_nested_scene != null, "Test preflightu wymaga zagnieżdżonej sceny z wbudowanymi efektami ubocznymi.")
	if unsafe_nested_scene == null:
		return
	var errors := DiveVisualLayerElement.packed_scene_preflight_validation_errors(unsafe_nested_scene)
	for forbidden_type in ["RemoteTransform2D", "CanvasModulate", "AnimationPlayer"]:
		var rejected := false
		for validation_error in errors:
			if String(validation_error).contains("Niedozwolony typ %s" % forbidden_type):
				rejected = true
				break
		_assert(rejected, "Preflight zagnieżdżonego SceneState musi odrzucić %s przed instantiate()." % forbidden_type)
	var unsafe_camera_scene := ResourceLoader.load(UNSAFE_CAMERA_VISUAL_SCENE_PATH) as PackedScene
	_assert(unsafe_camera_scene != null, "Test preflightu wymaga PackedScene z Camera2D.")
	if unsafe_camera_scene == null:
		return
	var camera_rejected := false
	for validation_error in DiveVisualLayerElement.packed_scene_preflight_validation_errors(unsafe_camera_scene):
		if String(validation_error).contains("Niedozwolony typ Camera2D"):
			camera_rejected = true
			break
	_assert(camera_rejected, "Preflight SceneState musi odrzucić Camera2D przed instantiate().")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Underwater environment test failed: " + message)
