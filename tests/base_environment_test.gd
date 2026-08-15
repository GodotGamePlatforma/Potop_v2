extends SceneTree

const BaseEnvironmentScript := preload("res://scripts/base/BaseEnvironment.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const WeatherStateScript := preload("res://scripts/data/WeatherState.gd")
const TILT_AUDIT_WIND := Vector2(0.3746066, 0.9271839)
const DIRECTIONAL_SCATTERING_WIND := Vector2(0.8, 0.6)
const BUILDING_HIGHLIGHT_VISUAL_LAYER := 20

# Side order is the public BaseWorld3D contact contract: front, right, back,
# left. Vector2.y represents world +Z for these XZ-plane normals.
const PLATFORM_SIDE_NORMALS: Array[Vector2] = [
	Vector2(0.0, 1.0),
	Vector2(1.0, 0.0),
	Vector2(0.0, -1.0),
	Vector2(-1.0, 0.0),
]

const SLOT_IDS: Array[String] = [
	"top_left", "top_center", "top_right",
	"bottom_left", "center", "bottom_right",
]

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var environment = BaseEnvironmentScript.new()
	environment.build()
	root.add_child(environment)
	environment.layout_environment(Vector2(1280, 720))
	await process_frame
	await process_frame

	_assert(environment.platform_board != null, "Srodowisko bazy musi wystawiac stabilny rig projekcji gameplayowej.")
	_assert(environment.building_layer != null and environment.building_layer.get_parent() == environment.platform_board, "Warstwa prezentacji budynkow musi dziedziczyc projekcje platformy.")
	_assert(environment.slot_layer != null and environment.slot_layer.get_parent() == environment.platform_board, "Klikalne sloty musza dziedziczyc ten sam ruch co projekcja.")
	_assert(environment.get_node_or_null("BaseWorldViewportContainer") is SubViewportContainer, "Aktywna baza musi renderowac prawdziwy swiat 3D w osobnym viewportcie.")
	var viewport_container := environment.get_node_or_null("BaseWorldViewportContainer") as SubViewportContainer
	_assert(viewport_container.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR, "Render 3D musi byc skalowany liniowo, niezaleznie od globalnego nearest przeznaczonego dla UI.")
	_assert(environment.world_viewport is SubViewport and environment.world_viewport.gui_disable_input, "Viewport 3D nie moze przechwytywac wejscia nalezacego do slotow 2D.")
	_assert(not environment.world_viewport.transparent_bg, "Nieprzezroczysty viewport jest wymagany dla stabilnego PBR, glebi i odbicia proceduralnego nieba.")
	_assert(environment.world_3d != null and environment.world_3d.camera is Camera3D, "Swiat bazy musi miec jawna kamere 3D.")
	var highlight_viewport := environment.get_node_or_null("BuildingHighlightViewport") as SubViewport
	var highlight_blur_viewport := environment.get_node_or_null("BuildingHighlightBlurViewport") as SubViewport
	var highlight_blur_input := environment.get_node_or_null("BuildingHighlightBlurViewport/BuildingHighlightBlurInput") as TextureRect
	var highlight_overlay := environment.get_node_or_null("BuildingHighlightOutline") as TextureRect
	var highlight_camera := highlight_viewport.get_node_or_null("BuildingHighlightCamera") as Camera3D if highlight_viewport != null else null
	var highlight_mask := 1 << (BUILDING_HIGHLIGHT_VISUAL_LAYER - 1)
	var initial_highlight: Dictionary = environment.building_highlight_state_for_tests()
	_assert(highlight_viewport != null and highlight_viewport.transparent_bg and highlight_viewport.gui_disable_input, "Poswiata budynku wymaga osobnego przezroczystego viewportu maski bez wejscia GUI.")
	_assert(highlight_blur_viewport != null and highlight_blur_viewport.transparent_bg and highlight_blur_viewport.gui_disable_input and highlight_blur_viewport.disable_3d and highlight_blur_viewport.render_target_clear_mode == SubViewport.CLEAR_MODE_NEVER, "Miekka poswiata wymaga 2D-only targetu posredniego bez wejscia GUI i zbednego czyszczenia pelnoekranowego passa.")
	_assert(highlight_viewport != null and highlight_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and highlight_blur_viewport != null and highlight_blur_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and highlight_overlay != null and not highlight_overlay.visible, "Nieaktywna poswiata nie moze renderowac maski, filtra ani pozostawiac starej tekstury na ekranie.")
	_assert(highlight_viewport != null and highlight_viewport.debug_draw == Viewport.DEBUG_DRAW_UNSHADED and highlight_viewport.msaa_3d == Viewport.MSAA_2X and highlight_viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED and not highlight_viewport.use_taa, "Maska high ma renderowac jedna nieoswietlona sylwetke z najwyzej 2x MSAA, bez kosztu SMAA/TAA glownego obrazu.")
	_assert(bool(initial_highlight.get("shared_world", false)) and bool(initial_highlight.get("camera_transform_synced", false)), "Maska i glowny obraz musza dzielic World3D oraz identyczna transformacje kamery.")
	_assert(highlight_viewport != null and highlight_viewport.size == environment.world_viewport.size and highlight_blur_viewport != null and highlight_blur_viewport.size == highlight_viewport.size, "Maska i target rozmycia musza miec dokladnie ten sam rozmiar logiczny co obraz swiata.")
	_assert(highlight_camera != null and highlight_camera.cull_mask == highlight_mask and not environment.world_3d.camera.get_cull_mask_value(BUILDING_HIGHLIGHT_VISUAL_LAYER), "Kamera maski ma widziec wylacznie zarezerwowana warstwe obrysu, niewidoczna dla kamery gracza.")
	var highlight_material := highlight_overlay.material as ShaderMaterial if highlight_overlay != null else null
	var highlight_shader_code := (highlight_material.shader as Shader).code if highlight_material != null and highlight_material.shader != null else ""
	var highlight_blur_material := highlight_blur_input.material as ShaderMaterial if highlight_blur_input != null else null
	var highlight_blur_shader_code := (highlight_blur_material.shader as Shader).code if highlight_blur_material != null and highlight_blur_material.shader != null else ""
	_assert(highlight_blur_input != null and highlight_blur_input.texture == highlight_viewport.get_texture() and highlight_overlay.texture == highlight_blur_viewport.get_texture(), "Dwupassowa poswiata musi laczyc maske z poziomym targetem i finalnym kompozytem bez dodatkowego swiata 3D.")
	_assert(highlight_blur_shader_code.contains("weighted_axis_blur") and highlight_blur_shader_code.contains("glow_spread") and highlight_blur_shader_code.contains("blend_disabled") and highlight_shader_code.contains("weighted_axis_blur") and highlight_shader_code.contains("glow_spread") and highlight_shader_code.contains("source_mask") and highlight_shader_code.contains("outside_core") and highlight_shader_code.contains("blend_premul_alpha") and not highlight_shader_code.contains("expanded_alpha"), "Poswiata ma uzywac separowalnego, szeroko rozstawionego rozmycia maski i usuwac rdzen zamiast rysowac binarna dylatacje.")
	_assert(environment.world_3d.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Czytelny uklad 2x3 wymaga stabilnej projekcji ortograficznej.")
	_assert(environment.world_3d.get_node_or_null("OceanSurface3D") is MeshInstance3D, "Morze musi byc geometryczna powierzchnia 3D.")
	var ocean := environment.world_3d.get_node_or_null("OceanSurface3D") as MeshInstance3D
	_assert(ocean != null and ocean.material_override is ShaderMaterial and (ocean.material_override as ShaderMaterial).shader != null, "Morze musi korzystac ze spatial shadera fal, piany i mokrych refleksow.")
	var ocean_material := ocean.material_override as ShaderMaterial
	var ocean_shader_code := (ocean_material.shader as Shader).code
	_assert(not ocean_shader_code.contains("hint_depth_texture") and not ocean_shader_code.contains("ALPHA ="), "Rdzen oceanu nie moze wracac do ekranowego halo ani transparentnego sortowania.")
	_assert(not ocean_shader_code.contains("surface_detail_texture"), "Stary malowany obraz morza nie moze ponownie plywac po albedo ani normalach wody.")
	_assert(not ocean_shader_code.contains("horizon_reflection_color") and not ocean_shader_code.contains("fresnel_power"), "Sky IBL i Schlick-GGX maja liczyc odbicie wody; shader nie moze malowac drugiego Fresnela w ALBEDO.")
	_assert(not ocean_shader_code.contains("short_whitecaps") and ocean_shader_code.contains("jacobian_determinant"), "Aktywne whitecapy maja wynikac z kompresji wspolnego pola Gerstnera, nie z jasnych sinusoidalnych makaronow.")
	_assert(ocean_shader_code.contains("residual_foam_tap") and ocean_shader_code.contains("1.0 - (1.0 - residual_foam)"), "Ocean musi miec deterministyczna Stage B: transportowana, gasnaca pozostalosciowa piane po aktywnym zalamaniu.")
	_assert(ocean_shader_code.contains("platform_contact_energy_sides") and ocean_shader_code.contains("pontoon_contact_energy_a") and ocean_shader_code.contains("nearest_pontoon_data"), "Kontakt nie moze wracac do jednego globalnego prostokatnego halo; shader musi znac boki i osiem authored pontonow.")
	_assert(ocean_shader_code.contains("max(dot(outward, -primary), 0.0)"), "Piana kontaktowa musi traktowac wind_direction jako kierunek propagacji i wybierac naplyw przez normalna burty skierowana przeciwko niemu.")
	_assert(ocean_shader_code.contains("ocean_macro_normal_world") and ocean_shader_code.contains("fwidth(phase)") and ocean_shader_code.contains("procedural_micro_slope(ocean_base_xz"), "Refleks oceanu musi zachowac normalna Gerstnera, stabilne bazowe wspolrzedne i wygaszanie subpikselowego szczegolu.")
	_assert(ocean_shader_code.contains("uniform float rain_intensity") and ocean_shader_code.contains("rain_impact_layer") and ocean_shader_code.contains("rain_impact_layer(ocean_world_position.xz"), "Mikrokregi deszczu maja powstawac bezposrednio na shaderowo zdeformowanej powierzchni Gerstnera, nie na plaskiej wysokosci obok niej.")
	_assert(ocean_shader_code.contains("uniform bool platform_scattering_enabled = true;") and bool(ocean_material.get_shader_parameter("platform_scattering_enabled")), "Kierunkowe oddzialywanie platformy na ocean musi byc jawnym, domyslnie aktywnym kontraktem shadera.")
	var scattering_transmission: Vector2 = ocean_material.get_shader_parameter("platform_scattering_transmission_loss")
	var scattering_reflection: Vector2 = ocean_material.get_shader_parameter("platform_scattering_reflection_strength")
	var scattering_lee_retention: Vector4 = ocean_material.get_shader_parameter("platform_scattering_lee_retention")
	var scattering_impact_strength := float(ocean_material.get_shader_parameter("platform_impact_foam_strength"))
	var scattering_reflected_foam_strength := float(ocean_material.get_shader_parameter("platform_reflected_foam_strength"))
	_assert(scattering_transmission.x >= 0.34 and scattering_transmission.x <= 0.48 and scattering_transmission.y >= 0.48 and scattering_transmission.y <= 0.62 and scattering_transmission.x < 1.0 and scattering_transmission.y < 1.0, "Czytelny cien falowy musi zachowac czesciowa, niezerowa transmisje: dluga fala co najmniej 52%, krotsza co najmniej 38% amplitudy.")
	_assert(scattering_reflection.x >= 0.22 and scattering_reflection.x <= 0.32 and scattering_reflection.y >= 0.14 and scattering_reflection.y <= 0.23, "Odbicie ma byc widoczne, lecz wyraznie slabsze od fali padajacej i od odpowiedzi sztywnego falochronu.")
	_assert(scattering_lee_retention.x >= 0.60 and scattering_lee_retention.x <= 0.76 and scattering_lee_retention.y >= 0.50 and scattering_lee_retention.y <= 0.70 and scattering_lee_retention.z >= 0.35 and scattering_lee_retention.z <= 0.55 and scattering_lee_retention.w >= 0.60 and scattering_lee_retention.w <= 0.78, "Zawietrzna musi byc czytelnie spokojniejsza, ale zachowac chop, glint oraz obie warstwy piany powyzej zera.")
	_assert(scattering_impact_strength >= 0.35 and scattering_impact_strength <= 0.80, "Kierunkowa piana uderzeniowa musi byc czytelna bez zmiany w przyklejona biala obwodke.")
	_assert(scattering_reflected_foam_strength >= 0.20 and scattering_reflected_foam_strength <= 0.45, "Porwane grzbiety odbicia maja wyjasniac przyczyne cienia bez zmiany w bialy falochron.")
	_assert(ocean_shader_code.contains("vec4 sample_platform_scattering(vec2 base_world_xz, float time_value)") and ocean_shader_code.contains("sample_platform_scattering_height") and ocean_shader_code.contains("sample_platform_scattering_component") and ocean_shader_code.contains("platform_projected_extents"), "Shader musi miec jeden bezstanowy helper rozpraszania, wspolny dla wysokosci, gradientu, odbicia, transmisji i dyfrakcji.")
	_assert(ocean_shader_code.contains("varying vec4 ocean_platform_scattering"), "Fragment musi dostac z vertexu jeden spojny wynik: delta wysokosci, dwa gradienty i maske zawietrzna.")
	var scattering_component_source := _source_between(ocean_shader_code, "vec4 sample_platform_scattering_component", "float sample_platform_scattering_height")
	var scattering_dispatch_source := _source_between(ocean_shader_code, "vec4 sample_platform_scattering(vec2", "float sample_platform_scattering_height")
	var impact_component_source := _source_between(ocean_shader_code, "float platform_incident_component_impact", "float platform_incident_impact_foam")
	var impact_dispatch_source := _source_between(ocean_shader_code, "float platform_incident_impact_foam", "float platform_reflected_crest_foam")
	var reflected_crest_source := _source_between(ocean_shader_code, "float platform_reflected_crest_foam", "float residual_breaker_source")
	var scattering_vertex_source := _source_between(ocean_shader_code, "void vertex()", "void fragment()")
	var scattering_fragment_source := _source_between(ocean_shader_code, "void fragment()", "")
	_assert(scattering_component_source.contains("rotation_2d(wave_component.w) * safe_direction(wind_direction)") and scattering_component_source.contains("along_wave = dot(platform_local, direction_value)"), "Kazda skladowa A/B musi wyprowadzac wlasny kierunek swiata z aktualnego wiatru zamiast stalej strony ekranu.")
	_assert(scattering_dispatch_source.contains("if (!platform_scattering_enabled") and scattering_dispatch_source.contains("return vec4(0.0)"), "Tryb A/B off musi zerowac cala odpowiedz geometryczna, gradient i maske zawietrznej przed obliczeniami rozpraszania.")
	_assert(scattering_component_source.contains("downstream_distance = along_wave - projected_extents.x") and scattering_component_source.contains("upstream_distance = -along_wave - projected_extents.x"), "Transmisja ma dzialac po stronie +wind_direction, a odbicie po stronie -wind_direction.")
	_assert(scattering_component_source.contains("Transmission:") and scattering_component_source.contains("Reflection:") and scattering_component_source.contains("Diffraction:") and not scattering_component_source.contains("SCREEN_UV") and not scattering_component_source.contains("TIME"), "Rozpraszanie ma laczyc transmisje, odbicie i dyfrakcje w world XZ oraz korzystac wylacznie z przekazanego czasu.")
	_assert(scattering_dispatch_source.contains("macro_wave_a") and scattering_dispatch_source.contains("macro_wave_b") and scattering_dispatch_source.contains("platform_scattering_transmission_loss.x") and scattering_dispatch_source.contains("platform_scattering_transmission_loss.y") and scattering_dispatch_source.contains("platform_scattering_reflection_strength.x") and scattering_dispatch_source.contains("platform_scattering_reflection_strength.y") and scattering_dispatch_source.contains("quality_level == 0") and scattering_dispatch_source.contains("quality_level >= 1"), "Fale A i B musza konsumowac aktywne parametry transmisji i odbicia na kazdym profilu; jakosc moze zmieniac jedynie koszt dyfrakcji.")
	_assert(scattering_dispatch_source.contains("0.074") and scattering_dispatch_source.contains("0.064") and scattering_dispatch_source.contains("0.032") and scattering_dispatch_source.contains("0.050"), "Kazdy profil ma zachowac dwukrawedziowa dyfrakcje; low przenosi budzet na fale A, a high na krotsze luki B.")
	_assert(impact_component_source.contains("rotation_2d(wave_component.w) * safe_direction(wind_direction)") and impact_component_source.contains("boundary_xz = base_world_xz - outward * hull_distance") and impact_component_source.contains("incident_phase") and impact_component_source.contains("max(dot(outward, -direction_value), 0.0)") and impact_component_source.contains("wave_component.x * wave_amplitude_scale") and impact_component_source.contains("abs(angular_frequency)") and not impact_component_source.contains("platform_projected_extents") and not impact_component_source.contains("SCREEN_UV") and not impact_component_source.contains("TIME"), "Piana uderzeniowa musi sledzic dominujaca faze przy signed-SDF wodnicy, wybierac naplyw i znikac przy zerowej energii fali.")
	_assert(impact_dispatch_source.contains("platform_scattering_enabled") and impact_dispatch_source.contains("macro_wave_a") and not impact_dispatch_source.contains("macro_wave_b") and impact_dispatch_source.contains("platform_impact_foam_strength"), "Przelacznik A/B ma wylaczac kierunkowa piane, a jej rytm ma pochodzic z jednej dominujacej fali zamiast migotania dwoch faz.")
	_assert(impact_dispatch_source.contains("if (!platform_scattering_enabled") and impact_dispatch_source.contains("return 0.0"), "Tryb A/B off musi zerowac fazowa piane uderzeniowa przed probkowaniem dominujacej fali.")
	_assert(reflected_crest_source.contains("platform_scattering_enabled") and reflected_crest_source.contains("upstream_distance = -along_wave - projected_extents.x") and reflected_crest_source.contains("platform_projected_extents(direction_value)") and reflected_crest_source.contains("reflected_slope_delta") and reflected_crest_source.contains("active_breakup") and reflected_crest_source.contains("platform_reflected_foam_strength") and not reflected_crest_source.contains("SCREEN_UV") and not reflected_crest_source.contains("TIME"), "Piana clapotis ma byc objeta tym samym przelacznikiem A/B, siedziec na aktywnym odbitym gradiencie przed rzeczywista sylwetka i miec poszarpane obszary zera.")
	_assert(reflected_crest_source.contains("if (!platform_scattering_enabled") and reflected_crest_source.contains("return 0.0"), "Tryb A/B off musi zerowac piane odbitych grzbietow przed wyznaczeniem strefy naplywu.")
	_assert(scattering_vertex_source.contains("sample_platform_scattering(base_world_xz, time_value)") and scattering_vertex_source.contains("displaced.y += platform_scattering.x") and scattering_vertex_source.contains("derivative_x.y += platform_scattering.y") and scattering_vertex_source.contains("derivative_z.y += platform_scattering.z") and scattering_vertex_source.contains("ocean_platform_scattering = platform_scattering"), "Vertex musi stosowac jednoczesnie wysokosc, oba gradienty normalnej i przekazac ten sam wynik do fragmentu.")
	_assert(scattering_fragment_source.contains("macro_field.xyz += ocean_platform_scattering.xyz") and scattering_fragment_source.contains("lee_mask = clamp(ocean_platform_scattering.w") and not scattering_fragment_source.contains("macro_field += ocean_platform_scattering"), "Fragment ma uzgodnic wysokosc i slope z geometria, ale zachowac incydentny Jacobian jako bezpieczny sygnal kompresji.")
	_assert(scattering_fragment_source.contains("platform_scattering_lee_retention.x") and scattering_fragment_source.contains("platform_scattering_lee_retention.y") and scattering_fragment_source.contains("platform_scattering_lee_retention.z") and scattering_fragment_source.contains("platform_scattering_lee_retention.w"), "Cien ma konsumowac jawne, niezerowe retencje chopu, glintu, Stage A i Stage B zamiast subtelnych stalych bez kontraktu.")
	_assert(scattering_fragment_source.contains("interaction_foam = platform_incident_impact_foam") and scattering_fragment_source.contains("max(contact_foam * 0.86, interaction_foam)") and not scattering_fragment_source.contains("interaction_foam * 0.34") and not scattering_fragment_source.contains("EMISSION"), "Fazowa piana naplywu ma wejsc tylko do swiezej piany PBR, bez emisji, globalnego rozjasnienia ani udawanej natychmiastowej warstwy residual.")
	_assert(scattering_fragment_source.contains("float interaction_reach = max(contact_foam_width * 2.85, 1.25)") and scattering_fragment_source.contains("broad_hull_distance < interaction_reach + 0.12"), "Broad-phase piany uderzeniowej musi obejmowac pelny pas wokol wszystkich wystajacych pontonow bez twardego ciecia jego zewnetrznej krawedzi.")
	_assert(scattering_fragment_source.contains("reflected_crest_foam = platform_reflected_crest_foam") and scattering_fragment_source.contains("1.0 - reflected_crest_foam"), "Odbity grzbiet ma laczyc sie probabilistycznie ze Stage A zamiast globalnie dodawac jasnosc wody.")
	var base_world_source := FileAccess.get_file_as_string("res://scripts/base/BaseWorld3D.gd")
	var motion_source := _source_between(base_world_source, "func sample_platform_wave_motion", "func _soft_limit_angle")
	_assert(not motion_source.is_empty() and not motion_source.contains("scattering") and not motion_source.contains("lee_mask") and not motion_source.contains("reflection") and not motion_source.contains("diffraction"), "Wizualne rozpraszanie nie moze wejsc w petle wypornosci ani kontaktu sample_platform_wave_motion().")
	var rain_mid := environment.world_3d.get_node_or_null("RainVolume3D") as GPUParticles3D
	var rain_near := environment.world_3d.get_node_or_null("RainNear3D") as GPUParticles3D
	var rain_contact_impacts := environment.world_3d.get_node_or_null("RainContactImpacts3D") as GPUParticles3D
	var rain_near_contact_impacts := environment.world_3d.get_node_or_null("RainNearContactImpacts3D") as GPUParticles3D
	var rain_heightfield := environment.world_3d.get_node_or_null("RainSurfaceCollisionHeightField3D") as GPUParticlesCollisionHeightField3D
	var rain_deck_proxy := environment.world_3d.platform_rig.get_node_or_null("RainDeckCollisionProxy3D") as MeshInstance3D
	_assert(rain_mid != null, "Deszcz musi zachowac warstwe srodkowa w swiecie 3D.")
	_assert(rain_near != null, "Deszcz musi miec osobna warstwe bliska kamery dla paralaksy i czytelnosci nad morzem.")
	_assert(environment.world_3d.get_node_or_null("RainOceanImpacts3D") == null, "Kontakt z falami nie moze wracac do plaskiego emitera, ktory unosi sie nad grzbietem albo tonie w dolinie.")
	_assert(rain_contact_impacts != null and rain_near_contact_impacts != null and rain_heightfield != null and rain_deck_proxy != null, "Kontakt kropli wymaga osobnych pul subemiterow mid/near, wysokosciowego collidera GPU i lekkiego proxy pokladu.")
	var far_rain := environment.get_node_or_null("RainFarVeil") as ColorRect
	_assert(far_rain != null and far_rain.material is ShaderMaterial and (far_rain.material as ShaderMaterial).shader != null, "Pelny kadr musi dostac subtelna warstwe dalekiego deszczu.")
	_assert(far_rain.get_index() > viewport_container.get_index() and far_rain.get_index() < environment.platform_board.get_index(), "Daleki deszcz ma pozostac pod hitboxami i HUD-em, a jego shader musi wyciac sylwetke 3D.")
	_assert(highlight_overlay != null and highlight_overlay.get_index() > far_rain.get_index() and highlight_overlay.get_index() < environment.platform_board.get_index(), "Poswiata sylwetki ma byc czytelna nad pogoda, ale pozostac pod blueprintem, hitboxami i HUD-em.")
	var rain_mid_process := rain_mid.process_material as ShaderMaterial if rain_mid != null else null
	var rain_near_process := rain_near.process_material as ShaderMaterial if rain_near != null else null
	var rain_carrier_shader_code := (rain_mid_process.shader as Shader).code if rain_mid_process != null and rain_mid_process.shader != null else ""
	var rain_mid_quad := rain_mid.draw_pass_1 as QuadMesh if rain_mid != null else null
	var rain_near_quad := rain_near.draw_pass_1 as QuadMesh if rain_near != null else null
	var rain_mid_material := rain_mid_quad.material as StandardMaterial3D if rain_mid_quad != null else null
	var rain_near_material := rain_near_quad.material as StandardMaterial3D if rain_near_quad != null else null
	_assert(rain_mid != null and rain_near != null and not rain_mid.local_coords and not rain_near.local_coords, "Spadajace krople musza pozostac w przestrzeni swiata, a nie jechac z emiterem lub platforma.")
	_assert(rain_mid != null and rain_near != null and rain_mid.transform_align == GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY and rain_near.transform_align == GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY, "Smugi obu warstw musza obracac sie zgodnie z rzeczywista predkoscia kropli.")
	_assert(rain_mid_material != null and rain_near_material != null and rain_mid_material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and rain_near_material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and rain_carrier_shader_code.contains("CUSTOM = vec4(0.0"), "Material smugi nie moze drugi raz billboardowac ani interpretowac CUSTOM.x jako obrotu; orientacje i skale dostarcza wylacznie transform czastki.")
	var rain_mid_direction := Vector3(rain_mid_process.get_shader_parameter("direction")) if rain_mid_process != null else Vector3.ZERO
	var rain_near_direction := Vector3(rain_near_process.get_shader_parameter("direction")) if rain_near_process != null else Vector3.ZERO
	var rain_mid_velocity := Vector2(float(rain_mid_process.get_shader_parameter("initial_velocity_min")), float(rain_mid_process.get_shader_parameter("initial_velocity_max"))) if rain_mid_process != null else Vector2.ZERO
	var rain_near_velocity := Vector2(float(rain_near_process.get_shader_parameter("initial_velocity_min")), float(rain_near_process.get_shader_parameter("initial_velocity_max"))) if rain_near_process != null else Vector2.ZERO
	_assert(rain_mid_process != null and rain_near_process != null and rain_mid_direction.y < -0.90 and rain_near_direction.y < -0.90, "Trajektoria musi zawsze miec skladowa w dol, takze przy wietrze i podmuchach.")
	_assert(not rain_carrier_shader_code.contains("VELOCITY +=") and not rain_carrier_shader_code.contains("gravity"), "Krople emitowane z predkoscia terminalna nie moga drugi raz przyspieszac pod wplywem grawitacji.")
	_assert(rain_mid_velocity.x >= 5.5 and rain_mid_velocity.y <= 9.5 and rain_near_velocity.x > rain_mid_velocity.x and rain_near_velocity.y <= 10.1, "Warstwy maja uzywac realistycznych pasm predkosci terminalnej, a bliskie duze krople szybszego konca rozkladu.")
	_assert(rain_mid_quad != null and rain_near_quad != null and rain_mid_quad.size.y <= 0.32 and rain_near_quad.size.y <= 0.50 and rain_mid_quad.size.x < rain_near_quad.size.x, "Smugi maja reprezentowac krotka ekspozycje optyczna, nie metrowe swiecace prety.")
	_assert(rain_mid_material != null and rain_near_material != null and rain_mid_material.albedo_texture != null and rain_near_material.albedo_texture != null and rain_mid_material.proximity_fade_enabled and rain_near_material.proximity_fade_enabled, "Obie warstwy musza miec zwezana teksture alfa i miekkie przeciecie z geometria.")
	_assert(rain_mid_process != null and rain_near_process != null and rain_mid_process.get_shader_parameter("color_ramp") != null and rain_mid_process.get_shader_parameter("color_initial_ramp") != null and rain_near_process.get_shader_parameter("color_ramp") != null and rain_near_process.get_shader_parameter("color_initial_ramp") != null, "Narodziny, zanik i rozklad jasnosci kropli maja byc sterowane rampami zamiast twardego poppingu.")
	_assert(
		rain_mid.fixed_fps >= 60 and rain_near.fixed_fps >= 60
		and rain_mid.collision_base_size >= 0.079 and rain_near.collision_base_size >= 0.079,
		"Szybkie krople potrzebuja co najmniej 60 krokow kolizji i niezerowej srednicy, aby nie tunelowac przez powierzchnie (fps %d/%d, base %.4f/%.4f)."
		% [rain_mid.fixed_fps, rain_near.fixed_fps, rain_mid.collision_base_size, rain_near.collision_base_size]
	)
	_assert(rain_carrier_shader_code.contains("if (COLLIDED)") and rain_carrier_shader_code.contains("COLLISION_NORMAL") and rain_carrier_shader_code.contains("COLLISION_DEPTH") and rain_carrier_shader_code.contains("ACTIVE = false"), "Obie widoczne warstwy musza odtworzyc punkt i normalna pierwszego kontaktu GPU, a potem ukryc smuge.")
	_assert(
		is_equal_approx(float(rain_mid_process.get_shader_parameter("collision_base_size")), rain_mid.collision_base_size)
		and is_equal_approx(float(rain_near_process.get_shader_parameter("collision_base_size")), rain_near.collision_base_size)
		and rain_carrier_shader_code.contains("- vec3(0.0, max(collision_base_size, 0.0), 0.0)"),
		"Punkt wizualnego kontaktu z HeightField musi usunac pionowy promien nosnika; inaczej krag unosi sie kilka pikseli nad fala lub dachem."
	)
	_assert(rain_carrier_shader_code.count("emit_subparticle(") == 1 and rain_carrier_shader_code.contains("FLAG_EMIT_POSITION | FLAG_EMIT_ROT_SCALE"), "Wybrany kontakt hero ma miec jedno miejsce emisji efektu w skorygowanej pozycji i orientacji powierzchni.")
	var mid_impact_probability := float(rain_mid_process.get_shader_parameter("impact_emission_probability"))
	var near_impact_probability := float(rain_near_process.get_shader_parameter("impact_emission_probability"))
	_assert(
		mid_impact_probability >= 0.28 and mid_impact_probability <= 0.38
		and near_impact_probability >= 0.50 and near_impact_probability <= 0.65
		and near_impact_probability > mid_impact_probability
		and rain_carrier_shader_code.contains("CUSTOM.w <= clamp(impact_emission_probability"),
		"Wszystkie smugi maja znikac na kontakcie, ale tylko deterministyczna reprezentacja duzych kropel moze tworzyc czytelny ring; near zachowuje wiekszy udzial hero."
	)
	var maximum_visible_impact_rate := (
		float(rain_mid.amount) / rain_mid.lifetime * mid_impact_probability
		+ float(rain_near.amount) / rain_near.lifetime * near_impact_probability
	)
	_assert(
		maximum_visible_impact_rate >= 440.0 and maximum_visible_impact_rate <= 500.0,
		"Storm/high ma zachowac setki skorelowanych, ale nie wszystkie hero impacty na sekunde (%.1f/s)." % maximum_visible_impact_rate
	)
	_assert(not rain_mid.sub_emitter.is_empty() and not rain_near.sub_emitter.is_empty() and rain_mid.get_node_or_null(rain_mid.sub_emitter) == rain_contact_impacts and rain_near.get_node_or_null(rain_near.sub_emitter) == rain_near_contact_impacts and rain_contact_impacts != rain_near_contact_impacts, "Mid i near musza miec osobne rzeczywiste pule kontaktu; wspoldzielenie jednego RID-u gubi impakty jednego z rodzicow.")
	var contact_process := rain_contact_impacts.process_material as ParticleProcessMaterial if rain_contact_impacts != null else null
	var near_contact_process := rain_near_contact_impacts.process_material as ParticleProcessMaterial if rain_near_contact_impacts != null else null
	var contact_crown := rain_contact_impacts.draw_pass_1 as QuadMesh if rain_contact_impacts != null else null
	var near_contact_crown := rain_near_contact_impacts.draw_pass_1 as QuadMesh if rain_near_contact_impacts != null else null
	var contact_ring := rain_contact_impacts.draw_pass_2 as QuadMesh if rain_contact_impacts != null else null
	var near_contact_ring := rain_near_contact_impacts.draw_pass_2 as QuadMesh if rain_near_contact_impacts != null else null
	var contact_crown_material := contact_crown.material as StandardMaterial3D if contact_crown != null else null
	_assert(rain_contact_impacts != null and rain_near_contact_impacts != null and not rain_contact_impacts.local_coords and not rain_near_contact_impacts.local_coords and not rain_contact_impacts.emitting and not rain_near_contact_impacts.emitting, "Obie pule kontaktu maja pozostac w swiecie i nigdy nie emitowac autonomicznie.")
	_assert(rain_contact_impacts != null and rain_near_contact_impacts != null and rain_contact_impacts.draw_passes == 2 and rain_near_contact_impacts.draw_passes == 2 and contact_ring != null and near_contact_ring != null and contact_ring.orientation == PlaneMesh.FACE_Y and near_contact_ring.orientation == PlaneMesh.FACE_Y, "Kontakt z dachem, pokladem i fala ma laczyc pionowa korone z poziomym kregiem w obu pasmach.")
	_assert(contact_process != null and near_contact_process != null and contact_process.alpha_curve != null and contact_process.scale_curve != null and near_contact_process.alpha_curve != null and near_contact_process.scale_curve != null, "Korony i kregi kontaktu musza szybko pojawiac sie, rozszerzac i zanikac bez stalych naklejek.")
	_assert(rain_contact_impacts != null and rain_near_contact_impacts != null and rain_contact_impacts.lifetime >= 0.38 and rain_contact_impacts.lifetime <= 0.44 and rain_near_contact_impacts.lifetime >= 0.38 and rain_near_contact_impacts.lifetime <= 0.44, "Hero impact ma byc czytelny przez kilkanascie klatek, ale nie moze pozostawac polsekundowa naklejka na ruchomej fali.")
	_assert(contact_crown != null and near_contact_crown != null and contact_crown.size.x >= 0.085 and contact_crown.size.y >= 0.19 and near_contact_crown.size.x >= 0.085 and near_contact_crown.size.y >= 0.19, "Korona uderzenia musi zachowac kilka pikseli wysokosci w kanonicznym kadrze 720p bez dominowania materialu powierzchni.")
	_assert(contact_ring != null and near_contact_ring != null and contact_ring.size.x >= 0.36 and contact_ring.size.x <= 0.40 and near_contact_ring.size.x >= 0.36 and near_contact_ring.size.x <= 0.40 and contact_ring.center_offset.y >= 0.02 and near_contact_ring.center_offset.y >= 0.02, "Krag kontaktu musi pozostac czytelny, lecz nie moze wracac do polmetrowych swiecacych oczek; geometryczny bias chroni depth.")
	_assert(contact_crown_material != null and contact_crown_material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and rain_carrier_shader_code.contains("impact_camera_position") and rain_carrier_shader_code.contains("camera_tangent") and rain_carrier_shader_code.contains("impact_transform[1].xyz = surface_normal"), "Carrier musi sam ustawic korone do kamery i oba meshe do normalnej odbiornika; material billboard nie moze nadpisac tej macierzy.")
	_assert(not rain_carrier_shader_code.contains("FLAG_EMIT_VELOCITY") and rain_carrier_shader_code.contains("vec3(0.0)"), "Korona kontaktu nie moze dziedziczyc predkosci spadajacej kropli i wjezdzac pod powierzchnie.")
	_assert(_contact_pool_has_headroom(rain_mid, rain_contact_impacts) and _contact_pool_has_headroom(rain_near, rain_near_contact_impacts), "Kazda pula high musi pomiescic co najmniej 125% teoretycznie aktywnych impaktow swojego parenta.")
	_assert(rain_heightfield != null and rain_heightfield.update_mode == GPUParticlesCollisionHeightField3D.UPDATE_MODE_ALWAYS and rain_heightfield.resolution == GPUParticlesCollisionHeightField3D.RESOLUTION_512, "High ma aktualizowac wysokosciowy collider oceanu, rigu i budynkow w kazdej klatce przy rozdzielczosci 512.")
	_assert(rain_heightfield != null and (rain_heightfield.cull_mask & rain_mid.layers) != 0 and rain_heightfield.get_heightfield_mask_value(2), "Maski collidera i obu systemow czastek musza sie przecinac, a capture ma czytac wylacznie warstwe proxy 2.")
	_assert(rain_heightfield != null and not rain_heightfield.get_heightfield_mask_value(BUILDING_HIGHLIGHT_VISUAL_LAYER), "Rain heightfield nie moze widziec warstwy maski zaleznej od kursora.")
	var rain_receiver_mesh := rain_deck_proxy.mesh as ArrayMesh if rain_deck_proxy != null else null
	_assert(rain_deck_proxy != null and rain_deck_proxy.get_layer_mask_value(2) and not environment.world_3d.camera.get_cull_mask_value(2), "Proxy pokladu ma trafic do heightfieldu, ale nigdy do obrazu kamery gracza.")
	_assert(rain_receiver_mesh != null and rain_receiver_mesh.get_surface_count() == 1 and rain_receiver_mesh.surface_get_array_len(0) == 36 and rain_receiver_mesh.surface_get_array_index_len(0) == 60 and rain_receiver_mesh.get_aabb().position.y <= 1.721 and rain_receiver_mesh.get_aabb().end.y >= 5.719, "Receiver ma byc lekkim authored obrysem rzeczywistego pokladu, dachow wspolnych i ukosnego zurawia, nie szeroka plaska skrzynka.")
	_assert(rain_heightfield != null and rain_heightfield.size.x <= 56.01 and rain_heightfield.size.z <= 68.01, "Heightfield ma obejmowac emitery z marginesem, lecz nie tracic rozdzielczosci na niewidoczne kilometry oceanu.")
	_assert(ocean != null and ocean.get_layer_mask_value(2), "Heightfield musi probkowac shaderowo zdeformowany ocean, nie plaska wysokosc obok niego.")
	_assert(_all_rain_variant_meshes_tagged(environment.world_3d.platform_rig), "Szesc ruin i wszystkie 24 warianty budynkow musza uczestniczyc w wysokosciowym kontakcie po uaktywnieniu.")
	var visible_ocean_rect := _orthographic_surface_rect(environment.world_3d.camera, Vector2(1280.0, 720.0), ocean.position.y)
	var mid_impact_rect := _rain_impact_rect(rain_mid, rain_mid_process, ocean.position.y)
	var near_impact_rect := _rain_impact_rect(rain_near, rain_near_process, ocean.position.y)
	var mid_visible_coverage := _intersection_area(mid_impact_rect, visible_ocean_rect) / maxf(_rect_area(visible_ocean_rect), 0.001)
	var near_visible_fraction := _intersection_area(near_impact_rect, visible_ocean_rect) / maxf(_rect_area(near_impact_rect), 0.001)
	var mid_area_ratio := _rect_area(mid_impact_rect) / maxf(_rect_area(visible_ocean_rect), 0.001)
	var platform_footprint := Rect2(Vector2(-9.0, -9.0), Vector2(18.0, 17.0))
	_assert(mid_visible_coverage >= 0.65 and mid_area_ratio >= 0.65 and mid_area_ratio <= 1.05, "Mid musi importance-samplowac srodkowe co najmniej 65%% footprintu produkcyjnej kamery bez marnowania wiekszosci kolizji poza kadrem (coverage %.3f, area ratio %.3f, impact %s, visible %s)." % [mid_visible_coverage, mid_area_ratio, str(mid_impact_rect), str(visible_ocean_rect)])
	_assert(near_visible_fraction >= 0.60 and mid_impact_rect.encloses(platform_footprint), "Warstwa hero ma ladowac w widocznym kadrze, a mid obejmowac caly authored footprint platformy i dachow.")
	var mid_contact_center := _rain_contact_center_at_surface(rain_mid, rain_mid_process, ocean.position.y)
	var near_contact_center := _rain_contact_center_at_surface(rain_near, rain_near_process, 1.0)
	_assert(mid_contact_center.distance_to(Vector2(0.0, -4.647)) <= 0.05 and near_contact_center.distance_to(Vector2(0.0, 1.0)) <= 0.05, "Pozycja narodzin musi byc liczona wstecz z widocznego punktu kontaktu dla aktualnego wiatru, a nie przyklejona do surowej pozycji kamery.")
	var canonical_mid_extents := Vector3(rain_mid_process.get_shader_parameter("emission_box_extents"))
	var canonical_near_extents := Vector3(rain_near_process.get_shader_parameter("emission_box_extents"))
	environment.layout_environment(Vector2(1000.0, 800.0))
	var narrow_mid_extents := Vector3(rain_mid_process.get_shader_parameter("emission_box_extents"))
	var narrow_near_extents := Vector3(rain_near_process.get_shader_parameter("emission_box_extents"))
	var narrow_visible_rect := _orthographic_surface_rect(environment.world_3d.camera, Vector2(1000.0, 800.0), ocean.position.y)
	var narrow_mid_impact_rect := _rain_impact_rect(rain_mid, rain_mid_process, ocean.position.y)
	var narrow_mid_coverage := _intersection_area(narrow_mid_impact_rect, narrow_visible_rect) / maxf(_rect_area(narrow_visible_rect), 0.001)
	_assert(
		narrow_mid_extents.x < canonical_mid_extents.x
		and narrow_near_extents.x <= canonical_near_extents.x
		and narrow_mid_extents.z > canonical_mid_extents.z
		and narrow_mid_coverage >= 0.65,
		"Camera-fit 5:4 musi zawezic emitter w X, rozszerzyc mid w Z i zachowac co najmniej 65%% widocznego kontaktu (coverage %.3f, mid %s, near %s)."
		% [narrow_mid_coverage, str(narrow_mid_extents), str(narrow_near_extents)]
	)
	environment.layout_environment(Vector2(1280.0, 720.0))
	_assert(
		Vector3(rain_mid_process.get_shader_parameter("emission_box_extents")).is_equal_approx(canonical_mid_extents)
		and Vector3(rain_near_process.get_shader_parameter("emission_box_extents")).is_equal_approx(canonical_near_extents),
		"Powrot do 16:9 musi deterministycznie odtworzyc kanoniczne footprinty deszczu."
	)
	var mid_spawn_screen: Vector2 = environment.world_3d.camera.unproject_position(rain_mid.global_position)
	var near_spawn_screen: Vector2 = environment.world_3d.camera.unproject_position(rain_near.global_position)
	_assert(mid_spawn_screen.y < float(environment.world_viewport.size.y) * 0.30 and near_spawn_screen.y < float(environment.world_viewport.size.y) * 0.30, "Srodki obu wolumenow maja wchodzic od gornej czesci kadru; deszcz nie moze rodzic sie jako plaska kurtyna na srodku ekranu.")
	var mid_lowest_surface_margin := _rain_lowest_surface_margin(rain_mid, rain_mid_process, ocean_material, ocean.position.y, 0.34)
	var near_lowest_surface_margin := _rain_lowest_surface_margin(rain_near, rain_near_process, ocean_material, ocean.position.y, 0.34 * 0.82)
	_assert(mid_lowest_surface_margin >= 0.0 and near_lowest_surface_margin >= 0.0, "Nawet najwolniejsza kropla z maksymalnym spreadem musi osiagnac najnizsza doline sztormowej fali z dwuklatkowym marginesem (mid %.3f m, near %.3f m)." % [mid_lowest_surface_margin, near_lowest_surface_margin])
	var far_rain_shader_code := ((far_rain.material as ShaderMaterial).shader as Shader).code
	_assert(far_rain_shader_code.contains("screen_flow") and far_rain_shader_code.contains("local_half_length") and far_rain_shader_code.contains("density_response"), "Daleki deszcz musi dziedziczyc projekcje wiatru kamery oraz roznicowac dlugosc i gestosc smug.")
	_assert(not far_rain_shader_code.contains("hint_screen_texture") and not far_rain_shader_code.contains("hint_depth_texture") and far_rain_shader_code.contains("alpha = min(alpha, 0.095)"), "Tani daleki sygnal nie moze czytac ekranu/glebi ani zamieniac sztormu w nieprzezroczyste mycie kadru.")
	_assert(far_rain_shader_code.contains("platform_occlusion_mask") and far_rain_shader_code.contains("platform_occlusion_half_size") and far_rain_shader_code.contains("mix(1.0, 0.06, platform_occlusion_mask(UV))"), "Ekranowy far veil musi wygaszac sie nad projektowana sylwetka platformy zamiast malowac smugi na dachach.")
	var far_occlusion_half_size: Vector2 = (far_rain.material as ShaderMaterial).get_shader_parameter("platform_occlusion_half_size")
	_assert(far_occlusion_half_size.x > 0.25 and far_occlusion_half_size.y > 0.25, "Maska dalekiego deszczu musi rzeczywiscie obejmowac kadlub i najwyzsze przeszkody w aktualnym kadrze.")
	_assert(ResourceLoader.exists(BaseEnvironmentScript.PLATFORM_MODEL_PATH), "Aktywna platforma 3D musi byc zasobem GLB projektu, a nie tylko awaryjnym prymitywem.")

	var initial_world: Dictionary = environment.world_state_for_tests()
	_assert(bool(initial_world.get("model_loaded", false)), "Model startowej platformy musi zostac zaladowany.")
	_assert(int(initial_world.get("ruin_count", 0)) == 6, "Startowa platforma musi zawierac dokladnie szesc typowanych ruin.")
	_assert(int(initial_world.get("slot_anchor_count", 0)) == 6, "Model 3D musi wystawiac szesc markerow projekcji zgodnych z hitboxami.")
	var shared_sun := environment.world_3d.get_node_or_null("SunDirectionalLight3D") as DirectionalLight3D
	_assert(shared_sun != null, "BaseWorld3D musi miec jedno jawnie nazwane swiatlo reprezentujace slonce.")
	_assert(environment.world_3d.get_node_or_null("SeaFill") == null, "Odbite swiatlo morza ma pochodzic z ambientu i nieba, nie z drugiego DirectionalLight3D.")
	_assert(int(initial_world.get("light_count", 0)) == 1, "Baza moze miec tylko jedno wspolne Light3D; lokalne fill lights nie moga maskowac kalibracji slonca.")
	_assert(int(initial_world.get("directional_light_count", 0)) == 1 and int(initial_world.get("shadow_casting_directional_light_count", 0)) == 1, "Platforma, ruiny i budynki musza dzielic dokladnie jedno kierunkowe slonce z cieniem.")
	_assert(bool(initial_world.get("sun_shadow_enabled", false)) and int(initial_world.get("sun_sky_mode", -1)) == DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY, "Wspolne slonce musi oswietlac modele, rzucac cienie i reprezentowac tarcze w proceduralnym niebie.")
	var initial_sun_direction: Vector3 = initial_world.get("sun_direction", Vector3.ZERO)
	_assert(initial_sun_direction.y < -0.35 and Vector2(initial_sun_direction.x, initial_sun_direction.z).length() > 0.20, "Swiatlo sloneczne musi padac wyraznie z gory i z boku, aby modelowac bryly 3D.")
	_assert(Vector3(initial_world.get("sun_rotation_degrees", Vector3.ZERO)).is_equal_approx(Vector3(-52.0, -24.0, 0.0)), "Kierunek wspolnego slonca musi zachowac skalibrowany kat widoczny na gornej i frontowej geometrii platformy.")
	var model_mesh_count := int(initial_world.get("model_mesh_count", 0))
	_assert(model_mesh_count >= 31 and int(initial_world.get("sun_lit_model_mesh_count", 0)) == model_mesh_count, "Wspolna maska slonca musi obejmowac poklad, szesc ruin i wszystkie 24 warianty Built_*.")
	_assert(int(initial_world.get("sun_shadow_casting_model_mesh_count", 0)) == model_mesh_count, "Wszystkie siatki platformy, ruin i wariantow Built_* musza nalezec do wspolnej maski casterow i zachowac rzucanie cienia.")
	var camera_to_platform_distance: float = environment.world_3d.camera.global_position.distance_to(environment.world_3d.platform_rig.global_position)
	_assert(float(initial_world.get("shadow_max_distance", 0.0)) > camera_to_platform_distance + 8.0, "Zasieg cienia slonca musi obejmowac cala plansze, a nie wygasac przy jej srodku.")
	_assert(is_equal_approx(float(initial_world.get("shadow_fade_start", 0.0)), 0.98), "Cien slonca moze zaczac zanikac dopiero za istotna geometria platformy.")
	_assert(is_equal_approx(float(initial_world.get("shadow_split_1", 0.0)), 0.62) and is_equal_approx(float(initial_world.get("shadow_split_2", 0.0)), 0.77) and is_equal_approx(float(initial_world.get("shadow_split_3", 0.0)), 0.90), "Cztery kaskady high musza byc skupione na zakresie glebi rzeczywistej platformy.")
	var platform_geometry := environment.world_3d.platform_rig.find_child("MeshyPlatform_Geometry", true, false) as MeshInstance3D
	_assert(platform_geometry != null and platform_geometry.mesh != null, "Aktywny GLB musi zachowac osobna siatke platformy do niezaleznej korekty materialu.")
	if platform_geometry != null and platform_geometry.mesh != null:
		_assert(not platform_geometry.get_layer_mask_value(2), "Milionowa siatka wspolnej platformy nie moze byc renderowana drugi raz co klatke do rain heightfieldu.")
		var platform_source_material := platform_geometry.mesh.surface_get_material(0) as BaseMaterial3D
		_assert(platform_source_material != null and platform_source_material.resource_name == "M_MeshyPlatformPBR", "Siatka platformy musi zachowac dedykowany material M_MeshyPlatformPBR.")
		if platform_source_material != null:
			_assert(platform_source_material.albedo_color.srgb_to_linear().is_equal_approx(Color(0.62, 0.65, 0.66, 1.0)), "Platforma musi zachowac zatwierdzony mnoznik albedo zamiast rozjasnionego baseColorFactor 1.0.")
			_assert(not platform_source_material.emission_enabled, "Platforma nie moze swiecic wlasna emisja; jej jasnosc ma pochodzic ze wspolnego swiatla sceny.")
	var platform_material_users := _source_material_users(environment.world_3d.platform_rig, "M_MeshyPlatformPBR")
	_assert(platform_material_users.size() == 1 and platform_material_users[0].begins_with("MeshyPlatform_Geometry:"), "Material platformy ma nalezec wylacznie do jej jednej siatki, bez ruin i wariantow Built_*.")
	_assert(int(initial_world.get("tonemap_mode", -1)) == Environment.TONE_MAPPER_ACES and is_equal_approx(float(initial_world.get("tonemap_exposure", 0.0)), 1.08) and float(initial_world.get("tonemap_white", 0.0)) >= 6.0, "Staly ACES bez pompowania ekspozycji musi zachowywac detal mokrych swiatel.")
	_assert(int(initial_world.get("ambient_source", -1)) == Environment.AMBIENT_SOURCE_COLOR and is_equal_approx(float(initial_world.get("ambient_energy", 0.0)), 0.98), "Profil moderate musi miec jawnie skalibrowane, deterministyczne swiatlo rozproszone nieba.")
	_assert(float(initial_world.get("ssao_intensity", 10.0)) <= 0.90, "SSAO nie moze ponownie zatopic miniatury w ciezkich czarnych szczelinach.")
	_assert(int(initial_world.get("wet_material_count", 0)) == 1, "Dzien 1 powinien tworzyc tylko jeden aktywny runtime material mokrosci; ukryte warianty pozostaja leniwe.")
	_assert(float(initial_world.get("wet_material_min_roughness", 0.0)) >= 0.85, "Mieszana platforma PBR nie moze byc globalnie sprowadzona do lustrzanego roughness.")
	_assert(float(initial_world.get("wet_material_max_clearcoat", 1.0)) <= 0.10, "Warstwa wody na starcie musi pozostac subtelna zamiast plastikowego clearcoatu.")
	_assert(str(initial_world.get("wave_motion_source", "")) == "shared_gerstner", "Ocean i platforma musza korzystac z jednego analitycznego pola fal.")
	_assert(bool(initial_world.get("wave_parameters_in_sync", false)), "Parametry pola fal CPU musza byc tymi samymi uniformami, ktore deformuja ocean w shaderze.")
	_assert(bool(initial_world.get("ocean_scattering_enabled", false)) and bool(ocean_material.get_shader_parameter("platform_scattering_enabled")), "Kierunkowe rozpraszanie platformy musi byc domyslnie aktywne i zgodne miedzy wlascicielem runtime a uniformem.")
	_assert(bool(initial_world.get("spray_parented_to_platform", false)), "Kotwice bryzgow musza podazac za prawdziwym rigiem platformy.")
	var first_spray := environment.world_3d.platform_rig.get_node_or_null("HullSpray01") as GPUParticles3D
	var spray_quad := first_spray.draw_pass_1 as QuadMesh if first_spray != null else null
	var spray_material := spray_quad.material as StandardMaterial3D if spray_quad != null else null
	_assert(spray_material != null and spray_material.albedo_texture != null, "Bryzg musi uzywac miekkiej tekstury alfa zamiast widocznego prostokatnego billboardu.")
	_assert(not bool(initial_world.get("ssr_enabled", true)), "High nie moze placic za niewidoczne w tym kadrze SSR; stabilne odbicie oceanu pochodzi z nieba i PBR.")
	environment.world_3d.trigger_splash_group(0)
	_assert(int(environment.world_state_for_tests().get("spray_emitting_count", 0)) > 0, "Lokalne uderzenie fali musi uruchamiac co najmniej jedna kotwice bryzgu na profilu high.")
	var initial_ruins: Dictionary = initial_world.get("ruin_visibility", {})
	for slot_id in SLOT_IDS:
		_assert(bool(initial_ruins.get(slot_id, false)), "Ruina %s musi byc widoczna przed odbudowa." % slot_id)

	var high_quality: Dictionary = environment.graphics_quality_state()
	var high_sun_state := initial_world
	var quality_motion_time := 19.875
	var high_quality_motion: Dictionary = environment.world_3d.sample_platform_wave_motion(quality_motion_time, 0.81)
	_assert(high_quality.quality == "high" and high_quality.rendering_mode == "hybrid_3d_world_2d_hud", "Wysoka jakosc musi uzywac swiata 3D i nieruchomego HUD-u 2D.")
	_assert(high_quality.rain_far_veil_visible and high_quality.rain_surface_visible, "High musi laczyc deszcz bliski, daleki i dyskretne impakty powierzchniowe.")
	_assert(not high_quality.fog_enabled and not high_quality.volumetric_fog_enabled, "Zaden preset nie moze nakladac mlecznej powloki mgly na czytelna plansze 2.5D.")
	_assert(not high_quality.beauty_overlay_visible and int(high_quality.ocean_subdivisions) >= 128, "Wysoka jakosc zachowuje gestsze morze bez plaskiej nakladki beauty nad modelem 3D.")
	environment.set_graphics_quality("low")
	await process_frame
	var low_quality: Dictionary = environment.graphics_quality_state()
	var low_highlight: Dictionary = environment.building_highlight_state_for_tests()
	_assert(int(low_highlight.get("glow_radius", 0)) == 2 and is_equal_approx(float(low_highlight.get("glow_spread", 0.0)), 3.0) and highlight_viewport.msaa_3d == Viewport.MSAA_DISABLED and highlight_viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "Low ma uzywac szeroko rozstawionego trzyprobkowego rozmycia, skalowanego razem z half-res viewportem, bez MSAA ani SMAA maski.")
	_assert(Vector2i(low_highlight.get("viewport_size", Vector2i.ZERO)) == environment.world_viewport.size and Vector2i(low_highlight.get("blur_viewport_size", Vector2i.ZERO)) == environment.world_viewport.size, "Maska i filtr low musza sledzic half-res rozmiar glownego render targetu bez dryfu projekcji.")
	_assert(not low_quality.sea_mist_visible and not low_quality.daylight_overlay_visible and not low_quality.beauty_overlay_visible, "Niska jakosc nie moze przywracac usunietej powloki 2D.")
	_assert(low_quality.rain_air_visible and is_zero_approx(float(low_quality.splash_quality_scale)), "Deszcz informujacy o pogodzie pozostaje, ale dekoracyjny spray znika.")
	_assert(low_quality.rain_far_veil_visible and low_quality.rain_surface_visible, "Low ma zachowac rzadszy, ale fizycznie powiazany kontakt kropli z powierzchnia.")
	_assert(int(low_quality.rain_particle_amount) < int(high_quality.rain_particle_amount) and int(low_quality.rain_near_particle_amount) < int(high_quality.rain_near_particle_amount), "Preset low musi zmniejszac rzeczywista liczbe czastek obu warstw 3D.")
	_assert(int(low_quality.rain_contact_particle_amount) < int(high_quality.rain_contact_particle_amount), "Low musi obnizyc pojemnosc puli impaktow zamiast przywracac przenikanie kropli.")
	_assert(_contact_pool_has_headroom(rain_mid, rain_contact_impacts) and _contact_pool_has_headroom(rain_near, rain_near_contact_impacts), "Obie pule low musza zachowac zapas na zdarzenia zamiast gubic kontakt przy nasyceniu.")
	var low_world: Dictionary = environment.world_state_for_tests()
	var low_quality_motion: Dictionary = environment.world_3d.sample_platform_wave_motion(quality_motion_time, 0.81)
	_assert(int(low_world.get("rain_collision_resolution", -1)) == GPUParticlesCollisionHeightField3D.RESOLUTION_256, "Low ma korzystac z tanszego heightfieldu 256, zachowujac ten sam typ powierzchni.")
	_assert(int(ocean_material.get_shader_parameter("quality_level")) == 0 and bool(ocean_material.get_shader_parameter("platform_scattering_enabled")), "Low ma zachowac kierunkowy cien i naplyw platformy w tanszym profilu, nie wylaczac semantyki efektu.")
	_assert(is_zero_approx(float(low_world.shadow_angular_distance)) and is_equal_approx(float(low_world.shadow_max_distance), 68.0), "Low nie moze placic za PCSS, lecz nadal musi utrzymac cien na calej planszy.")
	_assert(int(low_world.get("sun_shadow_mode", -1)) == DirectionalLight3D.SHADOW_ORTHOGONAL and not bool(low_world.get("sun_shadow_blend_splits", true)), "Low musi uzywac najtanszego pojedynczego cienia kierunkowego.")
	_assert(_same_weather_lighting(low_world, high_sun_state), "Jakosc nie moze reinterpretowac energii, koloru, ambientu, kontrastu cienia ani kierunku pogody.")
	_assert(int(low_quality.ocean_subdivisions) < int(high_quality.ocean_subdivisions), "Preset low musi faktycznie obnizyc gestosc siatki oceanu.")
	_assert(not bool(low_world.get("ssr_enabled", true)), "Low nie moze placic za ekranowe odbicia oceanu.")
	environment.set_graphics_quality("medium")
	await process_frame
	var medium_quality: Dictionary = environment.graphics_quality_state()
	var medium_highlight: Dictionary = environment.building_highlight_state_for_tests()
	_assert(int(medium_highlight.get("glow_radius", 0)) == 4 and is_equal_approx(float(medium_highlight.get("glow_spread", 0.0)), 2.5) and highlight_viewport.msaa_3d == Viewport.MSAA_2X and highlight_viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "Medium ma uzywac szeroko rozstawionej piecioprobkowej osi poswiaty z 2x MSAA maski, bez drugiego przebiegu SMAA.")
	_assert(Vector2i(medium_highlight.get("viewport_size", Vector2i.ZERO)) == environment.world_viewport.size and Vector2i(medium_highlight.get("blur_viewport_size", Vector2i.ZERO)) == environment.world_viewport.size, "Maska i filtr medium musza odzyskac pelny logiczny rozmiar razem z glownym render targetem.")
	var medium_world: Dictionary = environment.world_state_for_tests()
	var medium_quality_motion: Dictionary = environment.world_3d.sample_platform_wave_motion(quality_motion_time, 0.81)
	_assert(int(ocean_material.get_shader_parameter("quality_level")) == 1 and bool(ocean_material.get_shader_parameter("platform_scattering_enabled")), "Medium ma zachowac aktywne rozpraszanie przy posrednim budzecie dyfrakcji.")
	_assert(not medium_quality.sea_mist_visible and not medium_quality.daylight_overlay_visible and not medium_quality.beauty_overlay_visible, "Srednia jakosc pozostaje wolna od plaskiej powloki i mgly.")
	_assert(int(medium_quality.ocean_subdivisions) > int(low_quality.ocean_subdivisions), "Preset medium musi miec posrednia gestosc morza.")
	_assert(int(low_quality.rain_particle_amount) < int(medium_quality.rain_particle_amount) and int(medium_quality.rain_particle_amount) < int(high_quality.rain_particle_amount) and int(low_quality.rain_near_particle_amount) < int(medium_quality.rain_near_particle_amount) and int(medium_quality.rain_near_particle_amount) < int(high_quality.rain_near_particle_amount), "Budzet obu warstw deszczu musi rosnac scisle low < medium < high.")
	_assert(int(low_quality.rain_contact_particle_amount) < int(medium_quality.rain_contact_particle_amount) and int(medium_quality.rain_contact_particle_amount) < int(high_quality.rain_contact_particle_amount), "Pojemnosc skorelowanych impaktow musi rosnac scisle low < medium < high.")
	_assert(_contact_pool_has_headroom(rain_mid, rain_contact_impacts) and _contact_pool_has_headroom(rain_near, rain_near_contact_impacts), "Obie pule medium musza zachowac zapas na zdarzenia zamiast gubic kontakt przy nasyceniu.")
	_assert(medium_quality.rain_air_visible and medium_quality.rain_far_veil_visible and medium_quality.rain_surface_visible, "Medium ma zachowac wszystkie sygnaly deszczu, ograniczajac ich koszt zamiast zmieniac pogode.")
	_assert(environment.world_viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA, "Medium ma uzywac wyrazniejszego SMAA zamiast rozmywajacego FXAA.")
	_assert(not bool(medium_world.get("ssr_enabled", true)), "Medium zachowuje odbicie nieba, ale pomija koszt SSR.")
	_assert(int(medium_world.get("sun_shadow_mode", -1)) == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS and is_equal_approx(float(medium_world.get("shadow_split_1", 0.0)), 0.78) and is_equal_approx(float(medium_world.get("shadow_angular_distance", 0.0)), float(high_sun_state.get("shadow_angular_distance", 0.0)) * 0.76), "Medium musi zachowac pogodowa miekkosc slonca przy tanszym, skalibrowanym cieniu dwoch splitow.")
	_assert(_same_weather_lighting(medium_world, high_sun_state), "Medium moze obnizyc koszt cienia, ale nie znaczenie pogodowego oswietlenia.")
	environment.set_graphics_quality("high")
	await process_frame
	var restored_high_world: Dictionary = environment.world_state_for_tests()
	var restored_highlight: Dictionary = environment.building_highlight_state_for_tests()
	_assert(int(restored_highlight.get("glow_radius", 0)) == 6 and is_equal_approx(float(restored_highlight.get("glow_spread", 0.0)), 2.4) and highlight_viewport.msaa_3d == Viewport.MSAA_2X and highlight_viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "High ma uzywac szeroko rozstawionej siedmioprobkowej osi poswiaty bez kopiowania 4x MSAA glownego swiata.")
	_assert(int(ocean_material.get_shader_parameter("quality_level")) == 2 and bool(ocean_material.get_shader_parameter("platform_scattering_enabled")), "High ma przywrocic pelny profil rozpraszania bez zmiany jego kierunkowego kontraktu.")
	_assert(_same_platform_wave_motion(high_quality_motion, low_quality_motion) and _same_platform_wave_motion(high_quality_motion, medium_quality_motion), "Profile jakosci moga zmieniac koszt dyfrakcji, ale nie kanoniczny ruch, kontakt ani faze platformy.")
	_assert(not bool(restored_high_world.get("ssr_enabled", true)), "Powrot do high nie moze przywracac kosztu niewidocznego SSR.")
	_assert(int(restored_high_world.get("sun_shadow_mode", -1)) == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS and bool(restored_high_world.get("sun_shadow_blend_splits", false)), "High musi przywrocic cztery mieszane splity wspolnego cienia slonca.")
	_assert(_same_weather_lighting(restored_high_world, high_sun_state), "Powrot jakosci high nie moze zmienic profilu pogodowego oswietlenia.")

	environment.set_animation_time_for_tests(0.0)
	var start_board_position: Vector2 = environment.platform_board.position
	var start_rig_position: Vector3 = environment.world_3d.platform_rig.position
	var start_rig_rotation: Vector3 = environment.world_3d.platform_rig.rotation
	environment.set_animation_time_for_tests(3.4)
	var motion_board_position: Vector2 = environment.platform_board.position
	var motion_rig_position: Vector3 = environment.world_3d.platform_rig.position
	var motion_rig_rotation: Vector3 = environment.world_3d.platform_rig.rotation
	_assert(start_board_position.distance_to(motion_board_position) > 1.0, "Projekcja slotow musi podazac za ruchem ciezkiej platformy.")
	_assert(start_rig_position.distance_to(motion_rig_position) > 0.08, "Fala musi fizycznie unosic model 3D.")
	_assert(start_rig_rotation.distance_to(motion_rig_rotation) > deg_to_rad(0.08), "Model 3D musi laczyc roll i pitch zamiast plaskiego przesuniecia.")
	var projection_alignment: Dictionary = environment.platform_projection_alignment_for_tests()
	_assert(float(projection_alignment.position_error) < 0.05, "Hitboxy i tutorial musza uzywac projekcji ruchu prawdziwego rigu 3D, bez dryfu pozycji.")
	_assert(float(projection_alignment.rotation_error) < 0.0001 and float(projection_alignment.scale_error) < 0.0001, "Obrot i skala projekcji interakcji musza pozostac spojne z ruchem modelu 3D.")
	environment.set_animation_time_for_tests(3.4)
	_assert(environment.world_3d.platform_rig.position.is_equal_approx(motion_rig_position), "Wymuszony czas musi deterministycznie odtwarzac pozycje 3D.")
	_assert(environment.world_3d.platform_rig.rotation.is_equal_approx(motion_rig_rotation), "Wymuszony czas musi deterministycznie odtwarzac przechyl 3D.")
	_assert(is_equal_approx(float(ocean_material.get_shader_parameter("time_override")), 3.4), "Ocean ma dostawac surowy czas prezentacji bez ponownego mnozenia przez pogode.")
	var contact_motion_state := environment.world_state_for_tests()
	var bound_platform_position: Vector2 = ocean_material.get_shader_parameter("platform_position_xz")
	var bound_contact_sides: Vector4 = ocean_material.get_shader_parameter("platform_contact_energy_sides")
	var bound_pontoon_energy_a: Vector4 = ocean_material.get_shader_parameter("pontoon_contact_energy_a")
	var bound_pontoon_energy_b: Vector4 = ocean_material.get_shader_parameter("pontoon_contact_energy_b")
	_assert(bound_platform_position.is_equal_approx(Vector2(motion_rig_position.x, motion_rig_position.z)), "Odbicie i cien falowy musza podazac za aktualnym orbitalnym przesunieciem rigu platformy.")
	_assert(bound_contact_sides.is_equal_approx(Vector4(contact_motion_state.platform_contact_energy_sides)), "Cztery lokalne energie bokow musza trafic do shadera w tej samej deterministycznej klatce co ruch platformy.")
	_assert(bound_pontoon_energy_a.is_equal_approx(Vector4(contact_motion_state.pontoon_contact_energy_a)) and bound_pontoon_energy_b.is_equal_approx(Vector4(contact_motion_state.pontoon_contact_energy_b)), "Osiem authored pontonow musi dostac swoje lokalne energie kontaktu zamiast wspolnego pulsu calej ramki.")
	_assert(is_equal_approx(float((far_rain.material as ShaderMaterial).get_shader_parameter("time_offset")), 3.4), "Daleka warstwa deszczu musi korzystac z wymuszonego, deterministycznego czasu snapshotu.")

	var scattering_audit_time := 37.125
	environment.world_3d.set_ocean_scattering_enabled(true)
	var scattering_enabled_motion: Dictionary = environment.world_3d.sample_platform_wave_motion(scattering_audit_time, 0.93)
	environment.world_3d.set_ocean_scattering_enabled(false)
	var scattering_disabled_motion: Dictionary = environment.world_3d.sample_platform_wave_motion(scattering_audit_time, 0.93)
	_assert(not bool(environment.world_state_for_tests().get("ocean_scattering_enabled", true)) and not bool(ocean_material.get_shader_parameter("platform_scattering_enabled")), "Diagnostyczny przelacznik A/B musi wylaczyc wylacznie wizualne rozpraszanie w shaderze.")
	_assert(_same_platform_wave_motion(scattering_enabled_motion, scattering_disabled_motion), "Wlaczenie odbicia, transmisji i dyfrakcji nie moze zmienic wypornosci, kontaktu ani harmonogramu ruchu platformy.")
	environment.world_3d.set_ocean_scattering_enabled(true)
	_assert(bool(environment.world_state_for_tests().get("ocean_scattering_enabled", false)) and bool(ocean_material.get_shader_parameter("platform_scattering_enabled")), "Po probie A/B kierunkowe rozpraszanie musi zostac przywrocone.")
	var scattering_weather = WeatherStateScript.new()
	scattering_weather.condition = WeatherStateScript.Condition.STORM
	scattering_weather.sea_intensity = 1.0
	scattering_weather.rain_intensity = 0.0
	scattering_weather.motion_intensity = 1.16
	scattering_weather.foam_intensity = 1.0
	scattering_weather.splash_intensity = 1.0
	scattering_weather.wave_speed_multiplier = 1.34
	var scattering_phases := PackedFloat32Array([0.0, 0.37, 1.11, 2.73, 5.375, 9.5, 17.25, 37.125])
	var scattering_independence_samples := 0
	for scattering_quality in ["low", "medium", "high"]:
		environment.set_graphics_quality(scattering_quality)
		for scattering_wind in [DIRECTIONAL_SCATTERING_WIND, -DIRECTIONAL_SCATTERING_WIND]:
			scattering_weather.wind_direction = scattering_wind
			environment.configure_weather(scattering_weather)
			var bound_scattering_wind: Vector2 = ocean_material.get_shader_parameter("wind_direction")
			_assert(bound_scattering_wind.is_equal_approx(scattering_wind.normalized()), "Kazdy profil ma przekazac do shadera znormalizowany kierunek pogody bez stalej strony ekranowej.")
			for scattering_phase in scattering_phases:
				environment.world_3d.set_ocean_scattering_enabled(true)
				var visual_motion_on: Dictionary = environment.world_3d.sample_platform_wave_motion(scattering_phase, scattering_weather.motion_intensity)
				environment.world_3d.set_ocean_scattering_enabled(false)
				var visual_motion_off: Dictionary = environment.world_3d.sample_platform_wave_motion(scattering_phase, scattering_weather.motion_intensity)
				_assert(_same_platform_wave_motion(visual_motion_on, visual_motion_off), "Rozpraszanie nie moze wejsc do ruchu/kontaktu dla quality=%s wind=%s time=%.3f." % [scattering_quality, str(scattering_wind), scattering_phase])
				scattering_independence_samples += 1
	_assert(scattering_independence_samples == 48, "Macierz niezaleznosci musi objac 3 jakosci, 2 przeciwne kierunki i 8 faz.")
	environment.set_graphics_quality("high")
	scattering_weather.wind_direction = DIRECTIONAL_SCATTERING_WIND
	environment.configure_weather(scattering_weather)
	environment.world_3d.set_ocean_scattering_enabled(true)

	environment.set_animation_time_for_tests(scattering_audit_time)
	var deterministic_position: Vector3 = environment.world_3d.platform_rig.position
	var deterministic_rotation: Vector3 = environment.world_3d.platform_rig.rotation
	var deterministic_motion: Dictionary = environment.world_3d.sample_platform_wave_motion(scattering_audit_time, 0.93)
	var deterministic_contact_sides: Vector4 = ocean_material.get_shader_parameter("platform_contact_energy_sides")
	environment.set_animation_time_for_tests(5.375)
	environment.set_animation_time_for_tests(scattering_audit_time)
	var repeated_motion: Dictionary = environment.world_3d.sample_platform_wave_motion(scattering_audit_time, 0.93)
	_assert(environment.world_3d.platform_rig.position.is_equal_approx(deterministic_position) and environment.world_3d.platform_rig.rotation.is_equal_approx(deterministic_rotation), "Dowolny czas rozpraszania musi odtwarzac identyczny transform platformy po skoku osi czasu.")
	var repeated_contact_sides: Vector4 = ocean_material.get_shader_parameter("platform_contact_energy_sides")
	_assert(_same_platform_wave_motion(deterministic_motion, repeated_motion) and repeated_contact_sides.is_equal_approx(deterministic_contact_sides), "Powrot do dowolnej chwili musi deterministycznie odtworzyc pole padajace i lokalny kontakt.")
	_assert(is_equal_approx(float(ocean_material.get_shader_parameter("time_override")), scattering_audit_time), "Rozpraszanie musi korzystac z tego samego bezwzglednego time_override co kanoniczne fale, bez mutowalnej historii.")

	var state = GameStateScript.new()
	state.setup_new_campaign(41027)
	environment.sync_building_states(state)
	var empty_state: Dictionary = environment.world_state_for_tests()
	_assert(_all_ruins_visible(empty_state), "Brak BuildingState oznacza szesc widocznych ruin, nie puste place.")
	_assert(_highlight_layer_variant_mesh_count(environment.world_3d.platform_rig, BUILDING_HIGHLIGHT_VISUAL_LAYER) == 0, "Bez wskazania zaden wariant nie moze nalezec do maski poswiaty.")
	environment.set_animation_time_for_tests(0.0)
	environment.set_building_highlight("bottom_right", &"tutorial")
	var ruin_highlight: Dictionary = environment.building_highlight_state_for_tests()
	var tutorial_color := Color(ruin_highlight.get("glow_color", Color.TRANSPARENT))
	var tutorial_strength_start := float(ruin_highlight.get("glow_strength", 0.0))
	_assert(_highlight_targets_variant(ruin_highlight, "Ruin_bottom_right") and StringName(ruin_highlight.get("mode", &"none")) == &"tutorial", "Tutorial pustego slotu ma rozswietlic aktualna ruine, nie przyszly budynek.")
	_assert(tutorial_color.r > 0.9 and tutorial_color.r > tutorial_color.g and tutorial_color.g > tutorial_color.b and tutorial_color.a > 0.8, "Tryb tutoriala ma uzywac osobnej bursztynowej barwy, nie cyjanu hoveru.")
	_assert(_highlight_layers_are_isolated(ruin_highlight), "Aktywny wariant ma zachowac gameplay layer 1 i rain layer 2, dopisujac warstwe 20 bez zmiany pozostalych bitow.")
	_assert(int(ruin_highlight.get("viewport_update_mode", -1)) == SubViewport.UPDATE_ALWAYS and int(ruin_highlight.get("blur_viewport_update_mode", -1)) == SubViewport.UPDATE_ALWAYS and bool(ruin_highlight.get("active", false)), "Ruchoma maska i filtr poswiaty maja renderowac sie w kazdej klatce tylko podczas aktywnego wskazania.")
	environment.set_animation_time_for_tests(1.4)
	var tutorial_strength_peak := float(environment.building_highlight_state_for_tests().get("glow_strength", 0.0))
	_assert(tutorial_strength_peak > tutorial_strength_start, "Tutorialowa poswiata powinna miec spokojny, deterministyczny puls sterowany wspolna osia prezentacji.")
	environment.set_reduced_motion(true)
	environment.set_animation_time_for_tests(0.0)
	var reduced_strength_start := float(environment.building_highlight_state_for_tests().get("glow_strength", 0.0))
	environment.set_animation_time_for_tests(1.4)
	var reduced_strength_peak := float(environment.building_highlight_state_for_tests().get("glow_strength", 0.0))
	_assert(is_equal_approx(reduced_strength_start, reduced_strength_peak) and bool(environment.building_highlight_state_for_tests().get("reduced_motion", false)), "Reduced motion ma zamrozic puls bez wygaszania bursztynowego celu.")
	environment.set_reduced_motion(false)
	environment.set_animation_time_for_tests(0.0)
	var station = BuildingStateScript.new()
	station.id = "building_diving_station"
	station.definition_id = "diving_station"
	station.slot_id = "bottom_right"
	station.level = 4
	station.is_built = true
	state.buildings.append(station)
	var station_slot: Dictionary = state.platform.slot_states["bottom_right"]
	station_slot["building_id"] = station.id
	state.platform.slot_states["bottom_right"] = station_slot
	environment.sync_building_states(state)
	var rebuilt_state: Dictionary = environment.world_state_for_tests()
	_assert(not bool(rebuilt_state.ruin_visibility.bottom_right), "Natychmiastowa odbudowa musi od razu ukryc ruine danego slotu.")
	_assert(bool(rebuilt_state.building_visibility.bottom_right.get(4, false)), "Natychmiastowa rozbudowa musi od razu pokazac aktywny poziom 4.")
	_assert(_highlight_targets_variant(environment.building_highlight_state_for_tests(), "Built_bottom_right_L4"), "Poswiata ma atomowo wskazac od razu aktywny poziom 4.")
	environment.set_building_highlight("top_left", &"focus")
	var transferred_highlight: Dictionary = environment.building_highlight_state_for_tests()
	_assert(_highlight_targets_variant(transferred_highlight, "Ruin_top_left") and StringName(transferred_highlight.get("mode", &"none")) == &"focus", "Bezposredni skok miedzy slotami ma pozostawic dokladnie jedna poswiate i zachowac tryb focus.")
	_assert(_highlight_layer_variant_mesh_count(environment.world_3d.platform_rig, BUILDING_HIGHLIGHT_VISUAL_LAYER) == int((transferred_highlight.get("world", {}) as Dictionary).get("mesh_count", 0)), "Po transferze warstwa maski nie moze pozostac na poprzednim wariancie.")
	environment.clear_building_highlight()
	var cleared_highlight: Dictionary = environment.building_highlight_state_for_tests()
	_assert(not bool(cleared_highlight.get("active", true)) and int(cleared_highlight.get("viewport_update_mode", -1)) == SubViewport.UPDATE_DISABLED and int(cleared_highlight.get("blur_viewport_update_mode", -1)) == SubViewport.UPDATE_DISABLED, "Clear ma ukryc kompozyt oraz zatrzymac viewport maski i filtra.")
	_assert(_highlight_layer_variant_mesh_count(environment.world_3d.platform_rig, BUILDING_HIGHLIGHT_VISUAL_LAYER) == 0 and _all_rain_variant_meshes_tagged(environment.world_3d.platform_rig), "Czyszczenie ma usunac wylacznie bit poswiaty i zachowac wszystkie receivery deszczu.")

	var controlled_rain = WeatherStateScript.new()
	controlled_rain.condition = WeatherStateScript.Condition.STORM
	controlled_rain.sea_intensity = 1.0
	controlled_rain.rain_intensity = 0.55
	controlled_rain.motion_intensity = 1.0
	controlled_rain.foam_intensity = 1.0
	controlled_rain.splash_intensity = 1.0
	controlled_rain.wave_speed_multiplier = 1.2
	controlled_rain.wind_direction = Vector2.RIGHT
	environment.configure_weather(controlled_rain)
	environment.set_animation_time_for_tests(0.0)
	var half_rain_state := environment.world_state_for_tests()
	var half_mid_contact_rate := _contact_event_rate(rain_mid)
	var half_near_contact_rate := _contact_event_rate(rain_near)
	var half_mid_pool_amount := rain_contact_impacts.amount
	var half_near_pool_amount := rain_near_contact_impacts.amount
	_assert(is_equal_approx(float(half_rain_state.rain_amount_ratio), 0.55) and is_equal_approx(float(half_rain_state.rain_near_amount_ratio), 0.55), "Intensywnosc pogody musi plynnie sterowac gestoscia obu warstw przez amount_ratio.")
	controlled_rain.rain_intensity = 1.0
	environment.configure_weather(controlled_rain)
	environment.set_animation_time_for_tests(0.0)
	var right_wind_direction := Vector3((rain_mid.process_material as ShaderMaterial).get_shader_parameter("direction"))
	var right_wind_near_direction := Vector3((rain_near.process_material as ShaderMaterial).get_shader_parameter("direction"))
	var right_wind_screen_flow: Vector2 = (far_rain.material as ShaderMaterial).get_shader_parameter("screen_flow")
	var right_ocean_wind: Vector2 = ocean_material.get_shader_parameter("wind_direction")
	var full_rain_state := environment.world_state_for_tests()
	var full_mid_contact_rate := _contact_event_rate(rain_mid)
	var full_near_contact_rate := _contact_event_rate(rain_near)
	_assert(float(full_rain_state.rain_amount_ratio) > float(half_rain_state.rain_amount_ratio) and is_equal_approx(float(full_rain_state.rain_amount_ratio), 1.0), "Pelny sztorm ma zwiekszac gestosc istniejacych warstw bez tworzenia drugiej pogody.")
	_assert(is_equal_approx(half_mid_contact_rate / full_mid_contact_rate, 0.55) and is_equal_approx(half_near_contact_rate / full_near_contact_rate, 0.55), "Liczba rzeczywistych kontaktow obu parentow musi rosnac liniowo z rain_intensity, bez autonomicznej emisji childow.")
	_assert(rain_contact_impacts.amount == half_mid_pool_amount and rain_near_contact_impacts.amount == half_near_pool_amount and not rain_contact_impacts.emitting and not rain_near_contact_impacts.emitting and is_equal_approx(rain_contact_impacts.amount_ratio, 1.0) and is_equal_approx(rain_near_contact_impacts.amount_ratio, 1.0), "Intensywnosc ma sterowac rate parentow, nie pojemnoscia ani autonomiczna emisja pul kontaktu.")
	_assert(bool(full_rain_state.rain_ocean_ripples_enabled) and is_equal_approx(float(full_rain_state.rain_ocean_ripple_response), 1.0) and is_equal_approx(float(ocean_material.get_shader_parameter("rain_intensity")), 1.0), "Shaderowe mikrokregi oceanu musza dostac te sama intensywnosc deszczu co warstwy powietrzne.")
	_assert(right_wind_direction.x > 0.05 and right_wind_near_direction.x > 0.04 and right_wind_direction.y < -0.90 and right_wind_near_direction.y < -0.90, "Dodatni wiatr ma znosic obie warstwy w te sama strone, lecz nie pokonywac spadania.")
	_assert(right_ocean_wind.is_equal_approx(Vector2.RIGHT), "Ocean musi dostac z WeatherState kierunek propagacji +X bez dodatkowego odwrocenia; strona naplywu wynika dopiero z -wind_direction.")
	_assert(right_wind_screen_flow.y > 0.25 and right_wind_screen_flow.is_equal_approx(environment.world_3d.rain_screen_flow()), "Daleki veil musi dostac dokladna projekcje aktualnej trajektorii 3D przez kamere.")
	environment.set_animation_time_for_tests(4.5)
	var gusted_direction := Vector3((rain_mid.process_material as ShaderMaterial).get_shader_parameter("direction"))
	var gusted_screen_flow: Vector2 = (far_rain.material as ShaderMaterial).get_shader_parameter("screen_flow")
	_assert(gusted_direction.distance_to(right_wind_direction) > 0.01 and gusted_direction.y < -0.90, "Dwa wolne pasma podmuchu maja lamac sztywna kurtyne, nie odwracajac fizyki opadu.")
	_assert(gusted_screen_flow.is_equal_approx(environment.world_3d.rain_screen_flow()), "Kazda wymuszona chwila podmuchu musi pozostac zsynchronizowana miedzy czastkami 3D i dalekim shaderem.")
	controlled_rain.wind_direction = Vector2.LEFT
	environment.configure_weather(controlled_rain)
	environment.set_animation_time_for_tests(0.0)
	var left_wind_direction := Vector3((rain_mid.process_material as ShaderMaterial).get_shader_parameter("direction"))
	var left_ocean_wind: Vector2 = ocean_material.get_shader_parameter("wind_direction")
	_assert(left_wind_direction.x < -0.05 and left_wind_direction.y < -0.90, "Odwrocenie kanonicznego wiatru musi odwrocic dryf deszczu bez ruchu w gore.")
	_assert(left_ocean_wind.is_equal_approx(Vector2.LEFT), "Odwrocony WeatherState musi odwrocic takze kierunek propagacji oceanu, bez stalej strony ekranowej.")

	controlled_rain.wind_direction = DIRECTIONAL_SCATTERING_WIND
	environment.configure_weather(controlled_rain)
	var forward_scattering_wind: Vector2 = ocean_material.get_shader_parameter("wind_direction")
	var forward_exposure := _incoming_side_exposure(forward_scattering_wind)
	controlled_rain.wind_direction = -DIRECTIONAL_SCATTERING_WIND
	environment.configure_weather(controlled_rain)
	var reverse_scattering_wind: Vector2 = ocean_material.get_shader_parameter("wind_direction")
	var reverse_exposure := _incoming_side_exposure(reverse_scattering_wind)
	_assert(forward_scattering_wind.is_equal_approx(DIRECTIONAL_SCATTERING_WIND.normalized()) and reverse_scattering_wind.is_equal_approx(-DIRECTIONAL_SCATTERING_WIND.normalized()), "Kierunkowe rozpraszanie musi konsumowac znormalizowany wiatr w obu przeciwnych kierunkach.")
	_assert(_max_value_index(forward_exposure) == 3 and _max_value_index(reverse_exposure) == 1, "Dla fali +X/+Z naplyw ma byc na lewej/tylnej burcie, a po odwroceniu na prawej/przedniej.")
	_assert(_opposite_side_exposure_matches(forward_exposure, reverse_exposure), "Odwrocenie wiatru o 180 stopni musi dokladnie zamienic boki naplywu i odplywu.")

	var dry_weather = WeatherStateScript.new()
	dry_weather.condition = WeatherStateScript.Condition.MODERATE
	dry_weather.rain_intensity = 0.0
	environment.configure_weather(dry_weather)
	var dry_world := environment.world_state_for_tests()
	var dry_quality := environment.graphics_quality_state()
	_assert(not bool(dry_world.rain_air_emitting) and is_zero_approx(float(dry_world.rain_amount_ratio)) and is_zero_approx(float(dry_world.rain_near_amount_ratio)), "Zerowa intensywnosc musi faktycznie zatrzymac near i mid, a nie tylko ukryc diagnostyke.")
	_assert(is_zero_approx(_contact_event_rate(rain_mid)) and is_zero_approx(_contact_event_rate(rain_near)) and rain_contact_impacts.amount == half_mid_pool_amount and rain_near_contact_impacts.amount == half_near_pool_amount, "Dry wyzerowuje zdarzenia, ale zachowuje gotowe pule GPU dla kolejnej zmiany pogody.")
	_assert(not bool(dry_world.rain_ocean_ripples_enabled) and not bool(dry_world.rain_contact_enabled) and is_zero_approx(float(dry_world.rain_ocean_ripple_response)) and int(dry_world.rain_contact_amount) > 0 and is_zero_approx(float(ocean_material.get_shader_parameter("rain_intensity"))), "Przy zerowym deszczu kolizje i wszystkie sygnaly kontaktu musza zniknac bez niszczenia gotowej puli GPU.")
	_assert(not dry_quality.rain_air_visible and not dry_quality.rain_surface_visible and not dry_quality.rain_far_veil_visible, "Publiczny stan jakosci musi raportowac rzeczywisty brak wszystkich warstw deszczu.")

	var calm_weather = WeatherStateScript.new()
	calm_weather.condition = WeatherStateScript.Condition.CALM
	calm_weather.motion_intensity = 0.30
	calm_weather.sea_intensity = 0.30
	calm_weather.rain_intensity = 0.08
	calm_weather.foam_intensity = 0.18
	calm_weather.splash_intensity = 0.08
	calm_weather.wave_speed_multiplier = 0.72
	environment.configure_weather(calm_weather)
	_assert(is_equal_approx(float(ocean_material.get_shader_parameter("wave_speed_scale")), 0.72), "WeatherState.wave_speed_multiplier musi wejsc do oceanu dokladnie raz.")
	var calm_sun_energy: float = environment.sun_energy_for_tests()
	var calm_sun_state: Dictionary = environment.world_state_for_tests()
	var sample_times := PackedFloat32Array([0.0, 0.85, 1.70, 2.55, 3.40, 4.25, 5.10, 5.95])
	var calm_span := _platform_motion_span(environment, sample_times)
	var calm_splash_schedule := environment.splash_schedule_for_tests(60.0, 60.0)
	var moderate_weather = WeatherStateScript.new()
	moderate_weather.condition = WeatherStateScript.Condition.MODERATE
	environment.configure_weather(moderate_weather)
	var moderate_sun_energy: float = environment.sun_energy_for_tests()
	var moderate_sun_state: Dictionary = environment.world_state_for_tests()
	var moderate_splash_schedule := environment.splash_schedule_for_tests(60.0, 60.0)
	var rough_weather = WeatherStateScript.new()
	rough_weather.condition = WeatherStateScript.Condition.ROUGH
	rough_weather.sea_intensity = 0.78
	rough_weather.rain_intensity = 0.70
	rough_weather.motion_intensity = 0.84
	rough_weather.foam_intensity = 0.72
	rough_weather.splash_intensity = 0.68
	rough_weather.wave_speed_multiplier = 1.10
	environment.configure_weather(rough_weather)
	var rough_sun_energy: float = environment.sun_energy_for_tests()
	var rough_sun_state: Dictionary = environment.world_state_for_tests()
	var rough_splash_schedule := environment.splash_schedule_for_tests(60.0, 60.0)
	var storm_weather = WeatherStateScript.new()
	storm_weather.condition = WeatherStateScript.Condition.STORM
	storm_weather.motion_intensity = 1.16
	storm_weather.sea_intensity = 1.0
	storm_weather.rain_intensity = 1.0
	storm_weather.foam_intensity = 1.0
	storm_weather.splash_intensity = 1.0
	storm_weather.wave_speed_multiplier = 1.34
	environment.configure_weather(storm_weather)
	var storm_sun_energy: float = environment.sun_energy_for_tests()
	var storm_sun_state: Dictionary = environment.world_state_for_tests()
	var storm_splash_schedule := environment.splash_schedule_for_tests(60.0, 60.0)
	var repeated_storm_splash_schedule := environment.splash_schedule_for_tests(60.0, 60.0)
	var storm_span := _platform_motion_span(environment, sample_times)
	_assert(storm_span > calm_span * 1.8, "Sztorm musi poruszac platforma wyraznie mocniej niz spokojne morze w calym cyklu, nie tylko w przypadkowej fazie.")
	# A diagnostic wind direction excites both axes beyond their old hard limits,
	# so this regression cannot pass merely because saturation was never reached.
	storm_weather.wind_direction = TILT_AUDIT_WIND
	environment.configure_weather(storm_weather)
	var alignment_sample_times := PackedFloat32Array()
	for sample_index in range(1201):
		alignment_sample_times.append(float(sample_index) * 0.025)
	var tilt_alignment := _platform_tilt_alignment(environment.world_3d, float(storm_weather.motion_intensity), alignment_sample_times)
	var contact_locality := _platform_contact_locality(environment.world_3d, float(storm_weather.motion_intensity), alignment_sample_times)
	_assert(bool(tilt_alignment.aligned), "Roll i pitch platformy musza podnosic bok aktualnie niesiony przez wspolne pole fal, a nie przechylac rig przeciwnie do powierzchni.")
	_assert(int(tilt_alignment.roll_samples) > 900 and int(tilt_alignment.pitch_samples) > 900, "Test znaku przechylu musi obejmowac wiele istotnych roznic wysokosci obu osi kadluba.")
	_assert(float(tilt_alignment.peak_raw_roll) > deg_to_rad(2.5) * 1.05 and float(tilt_alignment.peak_raw_pitch) > deg_to_rad(1.9) * 1.50, "Fixture musi rzeczywiscie wyjsc ponad dawne limity obu osi, aby testowac saturacje zamiast zwyklego zakresu liniowego.")
	_assert(float(tilt_alignment.max_roll) < deg_to_rad(2.5) and float(tilt_alignment.max_pitch) < deg_to_rad(1.9), "Przechyl ma gladko zblizac sie do limitu bez twardej polki clampu.")
	_assert(bool(tilt_alignment.softened) and bool(tilt_alignment.roll_response_is_strict) and bool(tilt_alignment.pitch_response_is_strict), "Obie osie musza nadal rosnac w strefie bezpieczenstwa, coraz wolniej, ale bez twardego plateau.")
	_assert(bool(contact_locality.valid_range), "Kazda energia boku i pontonu musi pozostac skonczona oraz w zakresie 0..1.")
	_assert(int(contact_locality.side_local_frames) > 100 and float(contact_locality.max_side_spread) > 0.10, "Sztorm musi przez wiele klatek aktywowac boki niezaleznie, a nie rozjasniac caly obwod jednym skalarem.")
	_assert(int(contact_locality.pontoon_local_frames) > 100 and float(contact_locality.max_pontoon_spread) > 0.12, "Osiem pontonow musi reagowac lokalnie na faze i predkosc wzgledna fali.")
	_assert(float(contact_locality.min_pontoon_dynamic_range) > 0.025, "Zaden authored ponton nie moze pozostac martwym lub miec stalej energii kontaktu przez caly cykl.")
	_assert(calm_splash_schedule.size() == 0, "Spokojne morze nie moze generowac kontaktowego sprayu bez energii lamania fali.")
	_assert(moderate_splash_schedule.size() == 10, "Umiarkowane morze powinno dac rzadkie, male zdarzenia bryzgu zamiast stalego zera.")
	_assert(rough_splash_schedule.size() == 13, "Wzburzone morze powinno wyzwalac regularne lokalne uderzenia, ale nie ciagla fontanne.")
	_assert(storm_splash_schedule.size() == 19, "Sztorm musi generowac najczestsze bryzgi; nie moze paradoksalnie przegrywac z profilem rough przez blokade ponownego uzbrojenia.")
	_assert(calm_splash_schedule.size() <= moderate_splash_schedule.size() and moderate_splash_schedule.size() <= rough_splash_schedule.size() and rough_splash_schedule.size() <= storm_splash_schedule.size(), "Czestotliwosc bryzgow musi rosnac monotonicznie wraz z energia pogody.")
	_assert(storm_splash_schedule == repeated_storm_splash_schedule, "Detektor szczytow bryzgu musi odtwarzac identyczne czasy, strony i seedy przy tym samym polu fal.")
	_assert(_unique_splash_seed_count(storm_splash_schedule) == storm_splash_schedule.size(), "Kolejne uderzenia musza miec deterministycznie rozne seedy, aby nie kopiowac identycznej chmury kropli.")
	_assert(calm_sun_energy > moderate_sun_energy and moderate_sun_energy > rough_sun_energy and rough_sun_energy > storm_sun_energy, "Swiatlo musi gasnac kolejno od spokojnego morza do sztormu.")
	_assert(is_equal_approx(calm_sun_energy, 1.18) and is_equal_approx(moderate_sun_energy, 0.96) and is_equal_approx(rough_sun_energy, 0.76) and is_equal_approx(storm_sun_energy, 0.62), "Energia jednego slonca musi zachowac zatwierdzona kalibracje czterech stanow pogody.")
	_assert(is_equal_approx(float(calm_sun_state.get("ambient_energy", 0.0)), 0.88) and is_equal_approx(float(moderate_sun_state.get("ambient_energy", 0.0)), 0.98) and is_equal_approx(float(rough_sun_state.get("ambient_energy", 0.0)), 1.12) and is_equal_approx(float(storm_sun_state.get("ambient_energy", 0.0)), 1.36), "Zachmurzenie musi stopniowo przenosic oswietlenie z bezposredniego slonca do recznie kalibrowanego globalnego ambientu.")
	_assert(is_equal_approx(float(calm_sun_state.get("sun_shadow_opacity", 0.0)), 0.84) and is_equal_approx(float(moderate_sun_state.get("sun_shadow_opacity", 0.0)), 0.72) and is_equal_approx(float(rough_sun_state.get("sun_shadow_opacity", 0.0)), 0.56) and is_equal_approx(float(storm_sun_state.get("sun_shadow_opacity", 0.0)), 0.38), "Rosnace zachmurzenie musi splycac kontrast cienia zamiast zatapiac obiekty w czerni.")
	var calm_lighting_budget := _daylight_luminance_budget(calm_sun_state)
	var moderate_lighting_budget := _daylight_luminance_budget(moderate_sun_state)
	var rough_lighting_budget := _daylight_luminance_budget(rough_sun_state)
	var storm_lighting_budget := _daylight_luminance_budget(storm_sun_state)
	_assert(calm_lighting_budget > moderate_lighting_budget and moderate_lighting_budget > rough_lighting_budget and rough_lighting_budget > storm_lighting_budget and storm_lighting_budget >= calm_lighting_budget * 0.64, "Liniowy proxy budzetu swiatla ma zachowac nastroj pogody bez ponownego zapadniecia najsilniejszego sztormu w czern.")
	_assert(Color(calm_sun_state.get("sun_color", Color.BLACK)).r > Color(calm_sun_state.get("sun_color", Color.BLACK)).b and Color(storm_sun_state.get("sun_color", Color.BLACK)).b > Color(storm_sun_state.get("sun_color", Color.BLACK)).r, "Spokojne slonce ma byc cieple, a sztormowe swiatlo chlodne.")
	_assert(float(calm_sun_state.get("shadow_angular_distance", 0.0)) < float(moderate_sun_state.get("shadow_angular_distance", 0.0)) and float(moderate_sun_state.get("shadow_angular_distance", 0.0)) < float(rough_sun_state.get("shadow_angular_distance", 0.0)) and float(rough_sun_state.get("shadow_angular_distance", 0.0)) < float(storm_sun_state.get("shadow_angular_distance", 0.0)), "Chmury musza stopniowo zmiekczac cien wspolnego slonca od calm do storm.")
	_assert(Vector3(calm_sun_state.get("sun_direction", Vector3.ZERO)).is_equal_approx(initial_sun_direction) and Vector3(moderate_sun_state.get("sun_direction", Vector3.ZERO)).is_equal_approx(initial_sun_direction) and Vector3(rough_sun_state.get("sun_direction", Vector3.ZERO)).is_equal_approx(initial_sun_direction) and Vector3(storm_sun_state.get("sun_direction", Vector3.ZERO)).is_equal_approx(initial_sun_direction), "Pogoda moze zmieniac energie, barwe i miekkosc, ale nie kierunek wspolnego slonca.")

	if _failed:
		quit(1)
		return
	print("Base environment test passed: 3D ocean, directional platform scattering, persistent ruins and deterministic heavy-platform motion work.")
	quit(0)


func _all_ruins_visible(world_state: Dictionary) -> bool:
	var ruins: Dictionary = world_state.get("ruin_visibility", {})
	for slot_id in SLOT_IDS:
		if not bool(ruins.get(slot_id, false)):
			return false
	return true


func _highlight_targets_variant(highlight_state: Dictionary, expected_name_prefix: String) -> bool:
	if not bool(highlight_state.get("active", false)):
		return false
	var world_state: Dictionary = highlight_state.get("world", {})
	var meshes: Array = world_state.get("meshes", [])
	if meshes.is_empty() or int(world_state.get("mesh_count", 0)) != meshes.size():
		return false
	for mesh_value in meshes:
		var mesh_state: Dictionary = mesh_value
		if not str(mesh_state.get("node_name", "")).begins_with(expected_name_prefix):
			return false
	return true


func _highlight_layers_are_isolated(highlight_state: Dictionary) -> bool:
	var world_state: Dictionary = highlight_state.get("world", {})
	var meshes: Array = world_state.get("meshes", [])
	if meshes.is_empty():
		return false
	var highlight_mask := 1 << (BUILDING_HIGHLIGHT_VISUAL_LAYER - 1)
	for mesh_value in meshes:
		var mesh_state: Dictionary = mesh_value
		var layers_before := int(mesh_state.get("layers_before", 0))
		var layers_now := int(mesh_state.get("layers", 0))
		if not bool(mesh_state.get("gameplay_layer", false)) or not bool(mesh_state.get("rain_collision_layer", false)):
			return false
		if not bool(mesh_state.get("highlight_layer", false)) or layers_now != (layers_before | highlight_mask):
			return false
	return true


func _highlight_layer_variant_mesh_count(root_node: Node, visual_layer: int) -> int:
	var highlighted_count := 0
	for candidate_node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate_node as MeshInstance3D
		var node_name := str(mesh_instance.name)
		if not node_name.begins_with("Ruin_") and not node_name.begins_with("Built_"):
			continue
		if mesh_instance.get_layer_mask_value(visual_layer):
			highlighted_count += 1
	return highlighted_count


func _same_weather_lighting(left: Dictionary, right: Dictionary) -> bool:
	return (
		is_equal_approx(float(left.get("sun_energy", 0.0)), float(right.get("sun_energy", -1.0)))
		and Color(left.get("sun_color", Color.BLACK)).is_equal_approx(Color(right.get("sun_color", Color.WHITE)))
		and Vector3(left.get("sun_direction", Vector3.ZERO)).is_equal_approx(Vector3(right.get("sun_direction", Vector3.ONE)))
		and is_equal_approx(float(left.get("ambient_energy", 0.0)), float(right.get("ambient_energy", -1.0)))
		and Color(left.get("ambient_color", Color.BLACK)).is_equal_approx(Color(right.get("ambient_color", Color.WHITE)))
		and is_equal_approx(float(left.get("sun_shadow_opacity", 0.0)), float(right.get("sun_shadow_opacity", -1.0)))
	)


func _daylight_luminance_budget(world_state: Dictionary) -> float:
	var sun_color := Color(world_state.get("sun_color", Color.BLACK))
	var ambient_color := Color(world_state.get("ambient_color", Color.BLACK))
	return (
		_relative_luminance(sun_color) * float(world_state.get("sun_energy", 0.0))
		+ _relative_luminance(ambient_color) * float(world_state.get("ambient_energy", 0.0))
	)


func _relative_luminance(color: Color) -> float:
	var linear_color := color.srgb_to_linear()
	return linear_color.r * 0.2126 + linear_color.g * 0.7152 + linear_color.b * 0.0722


func _platform_motion_span(environment, sample_times: PackedFloat32Array) -> float:
	var positions: Array[Vector3] = []
	for sample_time in sample_times:
		environment.set_animation_time_for_tests(sample_time)
		positions.append(environment.world_3d.platform_rig.position)
	var maximum_span := 0.0
	for first_index in range(positions.size()):
		for second_index in range(first_index + 1, positions.size()):
			maximum_span = maxf(maximum_span, positions[first_index].distance_to(positions[second_index]))
	return maximum_span


func _same_platform_wave_motion(left: Dictionary, right: Dictionary) -> bool:
	var scalar_fields := [
		"heave", "roll", "pitch", "contact_energy", "impact_energy",
		"left_height", "right_height", "front_height", "back_height",
		"raw_roll", "raw_pitch", "hull_vertical_velocity",
	]
	for field in scalar_fields:
		if not is_equal_approx(float(left.get(field, INF)), float(right.get(field, -INF))):
			return false
	if int(left.get("impact_side", -1)) != int(right.get("impact_side", -2)):
		return false
	return (
		Vector2(left.get("horizontal_offset", Vector2(INF, INF))).is_equal_approx(
			Vector2(right.get("horizontal_offset", Vector2(-INF, -INF)))
		)
		and Vector4(left.get("contact_energy_sides", Vector4(INF, INF, INF, INF))).is_equal_approx(
			Vector4(right.get("contact_energy_sides", Vector4(-INF, -INF, -INF, -INF)))
		)
		and Vector4(left.get("pontoon_contact_energy_a", Vector4(INF, INF, INF, INF))).is_equal_approx(
			Vector4(right.get("pontoon_contact_energy_a", Vector4(-INF, -INF, -INF, -INF)))
		)
		and Vector4(left.get("pontoon_contact_energy_b", Vector4(INF, INF, INF, INF))).is_equal_approx(
			Vector4(right.get("pontoon_contact_energy_b", Vector4(-INF, -INF, -INF, -INF)))
		)
	)


func _platform_tilt_alignment(world, motion_intensity: float, sample_times: PackedFloat32Array) -> Dictionary:
	var aligned := true
	var roll_samples := 0
	var pitch_samples := 0
	var max_roll := 0.0
	var max_pitch := 0.0
	var peak_raw_roll := 0.0
	var peak_raw_pitch := 0.0
	var softened := false
	var roll_response_samples: Array[Vector2] = []
	var pitch_response_samples: Array[Vector2] = []
	for sample_time in sample_times:
		var motion: Dictionary = world.sample_platform_wave_motion(sample_time, motion_intensity)
		var roll := float(motion.roll)
		var pitch := float(motion.pitch)
		var raw_roll := absf(float(motion.raw_roll))
		var raw_pitch := absf(float(motion.raw_pitch))
		var right_minus_left := float(motion.right_height) - float(motion.left_height)
		var back_minus_front := float(motion.back_height) - float(motion.front_height)
		if absf(right_minus_left) > 0.002:
			roll_samples += 1
			aligned = aligned and right_minus_left * roll > 0.0
		if absf(back_minus_front) > 0.002:
			pitch_samples += 1
			aligned = aligned and back_minus_front * pitch > 0.0
		max_roll = maxf(max_roll, absf(roll))
		max_pitch = maxf(max_pitch, absf(pitch))
		peak_raw_roll = maxf(peak_raw_roll, raw_roll)
		peak_raw_pitch = maxf(peak_raw_pitch, raw_pitch)
		softened = softened or absf(roll) + 0.00001 < raw_roll
		softened = softened or absf(pitch) + 0.00001 < raw_pitch
		roll_response_samples.append(Vector2(raw_roll, absf(roll)))
		pitch_response_samples.append(Vector2(raw_pitch, absf(pitch)))
	return {
		"aligned": aligned,
		"roll_samples": roll_samples,
		"pitch_samples": pitch_samples,
		"max_roll": max_roll,
		"max_pitch": max_pitch,
		"peak_raw_roll": peak_raw_roll,
		"peak_raw_pitch": peak_raw_pitch,
		"softened": softened,
		"roll_response_is_strict": _has_strict_soft_response(roll_response_samples, deg_to_rad(2.5)),
		"pitch_response_is_strict": _has_strict_soft_response(pitch_response_samples, deg_to_rad(1.9)),
	}


func _has_strict_soft_response(samples: Array[Vector2], limit: float) -> bool:
	samples.sort_custom(func(left: Vector2, right: Vector2) -> bool: return left.x < right.x)
	var previous_raw := -1.0
	var previous_output := -1.0
	var comparisons := 0
	for sample in samples:
		if sample.x < limit * 0.75:
			continue
		if previous_raw >= 0.0 and sample.x - previous_raw < limit * 0.02:
			continue
		if previous_raw >= 0.0:
			comparisons += 1
			if sample.y <= previous_output + limit * 0.00001:
				return false
		previous_raw = sample.x
		previous_output = sample.y
	return comparisons >= 10


func _platform_contact_locality(world, motion_intensity: float, sample_times: PackedFloat32Array) -> Dictionary:
	var valid_range := true
	var side_local_frames := 0
	var pontoon_local_frames := 0
	var max_side_spread := 0.0
	var max_pontoon_spread := 0.0
	var pontoon_minimums: Array[float] = []
	var pontoon_maximums: Array[float] = []
	for _index in range(8):
		pontoon_minimums.append(INF)
		pontoon_maximums.append(-INF)
	for sample_time in sample_times:
		var motion: Dictionary = world.sample_platform_wave_motion(sample_time, motion_intensity)
		var side_vector := Vector4(motion.contact_energy_sides)
		var pontoon_a := Vector4(motion.pontoon_contact_energy_a)
		var pontoon_b := Vector4(motion.pontoon_contact_energy_b)
		var side_values: Array[float] = [side_vector.x, side_vector.y, side_vector.z, side_vector.w]
		var pontoon_values: Array[float] = [
			pontoon_a.x, pontoon_a.y, pontoon_a.z, pontoon_a.w,
			pontoon_b.x, pontoon_b.y, pontoon_b.z, pontoon_b.w,
		]
		var side_minimum := INF
		var side_maximum := -INF
		for value in side_values:
			valid_range = valid_range and is_finite(value) and value >= 0.0 and value <= 1.0
			side_minimum = minf(side_minimum, value)
			side_maximum = maxf(side_maximum, value)
		var side_spread := side_maximum - side_minimum
		max_side_spread = maxf(max_side_spread, side_spread)
		if side_spread > 0.05:
			side_local_frames += 1
		var pontoon_minimum := INF
		var pontoon_maximum := -INF
		for pontoon_index in range(pontoon_values.size()):
			var value: float = pontoon_values[pontoon_index]
			valid_range = valid_range and is_finite(value) and value >= 0.0 and value <= 1.0
			pontoon_minimum = minf(pontoon_minimum, value)
			pontoon_maximum = maxf(pontoon_maximum, value)
			pontoon_minimums[pontoon_index] = minf(pontoon_minimums[pontoon_index], value)
			pontoon_maximums[pontoon_index] = maxf(pontoon_maximums[pontoon_index], value)
		var pontoon_spread := pontoon_maximum - pontoon_minimum
		max_pontoon_spread = maxf(max_pontoon_spread, pontoon_spread)
		if pontoon_spread > 0.06:
			pontoon_local_frames += 1
	var min_pontoon_dynamic_range := INF
	for pontoon_index in range(8):
		min_pontoon_dynamic_range = minf(
			min_pontoon_dynamic_range,
			pontoon_maximums[pontoon_index] - pontoon_minimums[pontoon_index]
		)
	return {
		"valid_range": valid_range,
		"side_local_frames": side_local_frames,
		"pontoon_local_frames": pontoon_local_frames,
		"max_side_spread": max_side_spread,
		"max_pontoon_spread": max_pontoon_spread,
		"min_pontoon_dynamic_range": min_pontoon_dynamic_range,
	}


func _incoming_side_exposure(wave_direction: Vector2) -> Array[float]:
	var direction := wave_direction.normalized() if wave_direction.length_squared() > 0.0001 else Vector2.RIGHT
	var exposure: Array[float] = []
	for outward in PLATFORM_SIDE_NORMALS:
		exposure.append(maxf(outward.dot(-direction), 0.0))
	return exposure


func _max_value_index(values: Array[float]) -> int:
	var best_index := -1
	var best_value := -INF
	for index in range(values.size()):
		if values[index] > best_value:
			best_value = values[index]
			best_index = index
	return best_index


func _opposite_side_exposure_matches(forward: Array[float], reverse: Array[float]) -> bool:
	if forward.size() != PLATFORM_SIDE_NORMALS.size() or reverse.size() != PLATFORM_SIDE_NORMALS.size():
		return false
	for side_index in range(PLATFORM_SIDE_NORMALS.size()):
		var opposite_index := (side_index + 2) % PLATFORM_SIDE_NORMALS.size()
		if not is_equal_approx(forward[side_index], reverse[opposite_index]):
			return false
	return true


func _unique_splash_seed_count(events: Array[Dictionary]) -> int:
	var seeds := {}
	for event in events:
		seeds[int(event.get("event_seed", 0))] = true
	return seeds.size()


func _contact_pool_has_headroom(parent: GPUParticles3D, target: GPUParticles3D) -> bool:
	if parent == null or target == null or parent.lifetime <= 0.0:
		return false
	var process_material := parent.process_material as ShaderMaterial
	if process_material == null:
		return false
	# The carrier shader has one audited emit_subparticle() call per COLLIDED branch.
	var event_rate := float(parent.amount) / parent.lifetime
	return target.amount >= ceili(event_rate * target.lifetime * 1.25)


func _contact_event_rate(parent: GPUParticles3D) -> float:
	if parent == null or parent.lifetime <= 0.0 or not parent.process_material is ShaderMaterial:
		return 0.0
	return float(parent.amount) * parent.amount_ratio / parent.lifetime


func _orthographic_surface_rect(camera: Camera3D, viewport_size: Vector2, surface_y: float) -> Rect2:
	if camera == null or viewport_size.y <= 0.0:
		return Rect2()
	var basis := camera.global_transform.basis.orthonormalized()
	var ray_direction := -basis.z.normalized()
	if absf(ray_direction.y) <= 0.0001:
		return Rect2()
	var half_height := camera.size * 0.5
	var half_width := half_height * viewport_size.x / viewport_size.y
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for horizontal_sign in [-1.0, 1.0]:
		for vertical_sign in [-1.0, 1.0]:
			var ray_origin: Vector3 = (
				camera.global_position
				+ basis.x * half_width * horizontal_sign
				+ basis.y * half_height * vertical_sign
			)
			var distance: float = (surface_y - ray_origin.y) / ray_direction.y
			var world_point: Vector3 = ray_origin + ray_direction * distance
			var point_xz := Vector2(world_point.x, world_point.z)
			minimum = minimum.min(point_xz)
			maximum = maximum.max(point_xz)
	return Rect2(minimum, maximum - minimum)


func _rain_impact_rect(parent: GPUParticles3D, process_material: ShaderMaterial, surface_y: float) -> Rect2:
	if parent == null or process_material == null:
		return Rect2()
	var direction := Vector3(process_material.get_shader_parameter("direction")).normalized()
	if direction.y >= -0.001:
		return Rect2()
	var slope := Vector2(direction.x, direction.z) / -direction.y
	var extents := Vector3(process_material.get_shader_parameter("emission_box_extents"))
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				var spawn := parent.global_position + Vector3(
					extents.x * x_sign,
					extents.y * y_sign,
					extents.z * z_sign
				)
				var contact := Vector2(spawn.x, spawn.z) + slope * (spawn.y - surface_y)
				minimum = minimum.min(contact)
				maximum = maximum.max(contact)
	return Rect2(minimum, maximum - minimum)


func _rain_contact_center_at_surface(parent: GPUParticles3D, process_material: ShaderMaterial, surface_y: float) -> Vector2:
	if parent == null or process_material == null:
		return Vector2(INF, INF)
	var direction := Vector3(process_material.get_shader_parameter("direction")).normalized()
	if direction.y >= -0.001:
		return Vector2(INF, INF)
	var slope := Vector2(direction.x, direction.z) / -direction.y
	return Vector2(parent.global_position.x, parent.global_position.z) + slope * (parent.global_position.y - surface_y)


func _rain_lowest_surface_margin(
	parent: GPUParticles3D,
	process_material: ShaderMaterial,
	ocean_material: ShaderMaterial,
	ocean_y: float,
	maximum_horizontal_drift: float
) -> float:
	if parent == null or process_material == null or ocean_material == null or parent.fixed_fps <= 0:
		return -INF
	var centre_angle := atan(maxf(maximum_horizontal_drift, 0.0))
	var spread_degrees := float(process_material.get_shader_parameter("spread_degrees"))
	var worst_vertical_factor := cos(minf(
		centre_angle + deg_to_rad(spread_degrees),
		PI * 0.499
	))
	var usable_time := maxf(parent.lifetime - 2.0 / float(parent.fixed_fps), 0.0)
	var emission_extents := Vector3(process_material.get_shader_parameter("emission_box_extents"))
	var minimum_velocity := float(process_material.get_shader_parameter("initial_velocity_min"))
	var maximum_spawn_y := parent.global_position.y + emission_extents.y
	var wave_drop := 0.0
	for parameter_name in [&"macro_wave_a", &"macro_wave_b", &"macro_wave_c"]:
		var component := Vector4(ocean_material.get_shader_parameter(parameter_name))
		wave_drop += absf(component.x)
	# _wave_amplitude_scale() reaches 1.10 at the maximum sea profile. The extra
	# ten centimetres cover scattering displacement and one conservative depth step.
	var conservative_surface_y := ocean_y - wave_drop * 1.10 - 0.10
	var final_y := (
		maximum_spawn_y
		- minimum_velocity * worst_vertical_factor * usable_time
	)
	return conservative_surface_y - final_y


func _rect_area(rect: Rect2) -> float:
	return maxf(rect.size.x, 0.0) * maxf(rect.size.y, 0.0)


func _intersection_area(left: Rect2, right: Rect2) -> float:
	var minimum := left.position.max(right.position)
	var maximum := left.end.min(right.end)
	var size := maximum - minimum
	if size.x <= 0.0 or size.y <= 0.0:
		return 0.0
	return size.x * size.y


func _all_rain_variant_meshes_tagged(root_node: Node) -> bool:
	var variant_mesh_count := 0
	for candidate_node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate_node as MeshInstance3D
		var node_name := str(mesh_instance.name)
		if not node_name.begins_with("Ruin_") and not node_name.begins_with("Built_"):
			continue
		variant_mesh_count += 1
		if not mesh_instance.get_layer_mask_value(2):
			return false
	return variant_mesh_count == 30


func _source_material_users(root_node: Node, source_material_name: String) -> PackedStringArray:
	var users := PackedStringArray()
	for candidate_node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate_node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var source_material := mesh_instance.mesh.surface_get_material(surface_index)
			if source_material != null and source_material.resource_name == source_material_name:
				users.append("%s:%d" % [mesh_instance.name, surface_index])
	return users


func _source_between(source: String, start_marker: String, end_marker: String) -> String:
	var start_index := source.find(start_marker)
	if start_index < 0:
		return ""
	if end_marker.is_empty():
		return source.substr(start_index)
	var end_index := source.find(end_marker, start_index + start_marker.length())
	if end_index < 0:
		return source.substr(start_index)
	return source.substr(start_index, end_index - start_index)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Base environment test failed: " + message)
