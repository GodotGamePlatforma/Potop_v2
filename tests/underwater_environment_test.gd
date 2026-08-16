extends SceneTree

const EnvironmentScript := preload("res://scripts/diving/UnderwaterEnvironment2D.gd")
const TerrainRendererScript := preload("res://scripts/diving/UnderwaterTerrainRenderer.gd")
const CurrentVisualScript := preload("res://scripts/diving/DiveCurrentVisual.gd")

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
	renderer.set_view_center(Vector2(4_600.0, 2_100.0))
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
	_assert((low_renderer_state.get("backdrop_view_center", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(4_600.0, 2_100.0)), "Daleki plan powinien otrzymywać środek widoku dla subtelnego parallaxu.")
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
	_assert(backdrop_shader != null and backdrop_shader.code.contains("distant_position") and backdrop_shader.code.contains("view_center") and backdrop_shader.code.contains("reduced_motion ? 0.0 : anim_time") and backdrop_shader.code.contains("reduced_motion ? 0.0 : parallax_factor"), "Daleki plan musi łączyć parallax, falowanie i deterministyczne zatrzymanie ruchu.")
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


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Underwater environment test failed: " + message)
