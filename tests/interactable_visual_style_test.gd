extends SceneTree

const VisualStyle := preload("res://scripts/diving/DiveInteractableVisualStyle.gd")
const VisualEffects := preload("res://scripts/diving/DiveInteractableVisualEffects.gd")
const ContainerScript := preload("res://scripts/diving/DiveLootContainer.gd")
const PickupScript := preload("res://scripts/diving/DiveWorldPickup.gd")
const PersistentScript := preload("res://scripts/diving/DivePersistentInteractable.gd")
const RescueScript := preload("res://scripts/diving/DiveRescueSurvivor.gd")
const ExitLineScript := preload("res://scripts/diving/DiveExitLine.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_explicit_context_and_colors()
	_assert(
		VisualStyle.quality_level("low") == 0
		and VisualStyle.quality_level("medium") == 1
		and VisualStyle.quality_level("high") == 2,
		"Profile jakości muszą mieć trzy deterministyczne poziomy detalu."
	)
	_test_all_effect_roles()
	_test_stable_seed_does_not_choose_context()
	_test_quality_budgets()
	_test_reduced_motion_freezes_time()
	_test_focus_progress_and_resolved_state()
	_test_presentation_does_not_mutate_physics_or_root_transform()
	_test_towed_rescue_context_uses_bounded_refresh()
	_test_tool_locker_mounting_is_contextual_and_presentation_only()
	_test_shader_uses_only_explicit_animation_time()

	for presenter_script in [ContainerScript, PickupScript, PersistentScript, RescueScript, ExitLineScript]:
		var presenter = presenter_script.new()
		_assert(presenter != null, "Każdy aktywny renderer interakcji musi się parsować i instancjonować.")
		presenter.free()

	if _failed:
		quit(1)
		return
	print("Interactable visual style test passed: explicit contexts, roles, depth, deterministic animation, quality and presentation-only effects work.")
	quit(0)


func _test_explicit_context_and_colors() -> void:
	var colors := {
		"tint": Color("8ba6aa"),
		"patina": Color("657477"),
		"accent": Color("4dc7bb"),
		"rim": Color("b8f2ec"),
		"shadow": Color("07161c"),
		"silt": Color("6f7971"),
		"body_dark": Color("142b31"),
		"body_mid": Color("35535a"),
		"body_light": Color("88a7a8"),
	}
	var context := {
		"context_id": "salvage-yard",
		"colors": colors,
		"depth_ratio": 0.38,
		"effect_variant": "diagnostic",
	}
	_assert(
		VisualStyle.resolve_context_id("explicit-style", context) == "explicit-style",
		"Jawny identyfikator stylu musi mieć pierwszeństwo przed identyfikatorem kontekstu."
	)
	_assert(
		VisualStyle.resolve_region("", context, "arbitrary_object_identifier") == "salvage-yard",
		"Kompatybilnościowe wejście musi czytać wyłącznie jawny kontekst."
	)
	_assert(
		VisualStyle.resolve_region("", {}, "identifier_that_looks_structured") == "",
		"Stable ID nie może samodzielnie wybierać kontekstu ani palety."
	)
	var resolved := VisualStyle.palette(context)
	_assert(resolved.get("context_id", "") == "salvage-yard", "Dowolny jawny identyfikator kontekstu musi być zachowany.")
	for key in colors.keys():
		_assert(resolved.get(key) == colors[key], "Jawny kolor '%s' musi przejść bez mapowego remapowania." % key)
	var other_context := VisualStyle.palette({
		"context_id": "open-water",
		"colors": {"accent": Color("d39a5c")},
	})
	_assert(other_context.get("accent") == Color("d39a5c"), "Nowy kontekst kolorów nie może wymagać dopisania palety do zamkniętego katalogu.")

	var sprite := Sprite2D.new()
	VisualStyle.apply_sprite(sprite, context, "fixture_interactable", "high")
	var skin_material := sprite.material as ShaderMaterial
	_assert(skin_material != null and skin_material.shader != null, "Skin musi tworzyć materiał bez zmiany tekstury albo sylwetki.")
	_assert(skin_material != null and skin_material.shader == VisualStyle.INTERACTABLE_SKIN_SHADER, "Wspólny skin musi używać jednego jawnego shadera prezentacji.")
	_assert(skin_material != null and skin_material.get_shader_parameter("region_tint") == colors["tint"], "Shader musi dostać jawnie przekazany kolor tintu.")
	_assert(skin_material != null and is_equal_approx(float(skin_material.get_shader_parameter("detail_level")), 2.0), "High musi przekazać pełny detal statycznej patyny.")
	sprite.material = null
	sprite.free()


func _test_all_effect_roles() -> void:
	var roles: Array[String] = [
		"container",
		"pickup",
		"buoy",
		"shortcut",
		"heavy",
		"device",
		"rescue",
		"exit",
	]
	_assert(VisualEffects.EFFECT_ROLES == roles, "Kontrakt efektów musi jawnie obejmować wszystkie aktywne role interakcji.")
	for role_index in range(roles.size()):
		var role := roles[role_index]
		var setup := _make_effect_host(role, "role_%s_fixture" % role, _context("role-style", 0.43), "high", false, false)
		var host := setup["host"] as Node2D
		var material := setup["material"] as ShaderMaterial
		var state := VisualStyle.effect_state(host)
		_assert(str(state.get("role", "")) == role, "Rola '%s' musi zachować własny renderer materiałowy." % role)
		_assert(is_equal_approx(float(material.get_shader_parameter("interactable_role")), float(role_index)), "Rola '%s' musi trafić do jawnego parametru materiału." % role)
		host.free()


func _test_stable_seed_does_not_choose_context() -> void:
	var context := _context("shared-style", 0.43)
	var first := _make_effect_host("container", "stable_container", context, "high", false, false)
	var second := _make_effect_host("container", "stable_container", context, "high", false, false)
	var different := _make_effect_host("container", "other_container", context, "high", false, false)
	var first_host := first["host"] as Node2D
	var second_host := second["host"] as Node2D
	var different_host := different["host"] as Node2D
	var first_material := first["material"] as ShaderMaterial
	var second_material := second["material"] as ShaderMaterial
	var different_material := different["material"] as ShaderMaterial

	VisualStyle.set_effect_time_for_tests(first_host, 3.25)
	VisualStyle.set_effect_time_for_tests(second_host, 3.25)
	VisualStyle.set_effect_time_for_tests(different_host, 3.25)
	var first_state := VisualStyle.effect_state(first_host)
	var second_state := VisualStyle.effect_state(second_host)
	var different_state := VisualStyle.effect_state(different_host)
	_assert(is_equal_approx(float(first_state.get("visual_time", -1.0)), 3.25), "Jawny czas testowy musi sterować fazą efektu bez zegara globalnego.")
	_assert(is_equal_approx(float(first_material.get_shader_parameter("interactable_anim_time")), 3.25), "Jawny czas efektu musi być przekazany do shadera.")
	_assert(is_equal_approx(float(first_state.get("stable_phase", -1.0)), float(second_state.get("stable_phase", -2.0))), "To samo stable ID musi dawać identyczną fazę efektów.")
	_assert(not is_equal_approx(float(first_state.get("stable_phase", -1.0)), float(different_state.get("stable_phase", -1.0))), "Różne stable ID mogą rozpraszać wyłącznie fazę efektów.")
	_assert(first_state.get("context_id", "") == different_state.get("context_id", ""), "Stable ID nie może zmienić jawnego kontekstu stylu.")
	_assert(first_state.get("colors", {}) == different_state.get("colors", {}), "Stable ID nie może zmienić jawnej palety kolorów.")
	_assert(is_equal_approx(float(first_material.get_shader_parameter("stable_seed")), float(second_material.get_shader_parameter("stable_seed"))), "To samo stable ID musi dawać identyczny seed patyny.")
	_assert(not is_equal_approx(float(first_material.get_shader_parameter("stable_seed")), float(different_material.get_shader_parameter("stable_seed"))), "Różne stable ID mogą rozpraszać seed patyny.")

	VisualStyle.set_effect_time_for_tests(first_host, 8.5)
	_assert(is_equal_approx(float(VisualStyle.effect_state(first_host).get("visual_time", -1.0)), 8.5), "Zmiana jawnego czasu musi deterministycznie aktualizować fazę efektu.")
	_assert(is_equal_approx(float(first_material.get_shader_parameter("interactable_anim_time")), 8.5), "Shader musi śledzić każdą zmianę jawnego czasu.")
	first_host.free()
	second_host.free()
	different_host.free()


func _test_quality_budgets() -> void:
	var budgets: Array[int] = []
	for quality in ["low", "medium", "high"]:
		var setup := _make_effect_host("pickup", "quality_pickup", _context("quality-style", 0.36), quality, false, false)
		var host := setup["host"] as Node2D
		budgets.append(int(VisualStyle.effect_state(host).get("detail_budget", -1)))
		host.free()
	_assert(budgets.size() == 3 and budgets[0] > 0, "Low musi zachować co najmniej jeden czytelny detal materiałowy.")
	_assert(budgets[0] <= budgets[1] and budgets[1] <= budgets[2], "Budżet efektów musi rosnąć monotonicznie od low przez medium do high.")
	_assert(budgets[0] < budgets[2], "High musi mieć większy budżet detalu niż low.")


func _test_reduced_motion_freezes_time() -> void:
	var setup := _make_effect_host("rescue", "rescue_reduced", _context("deep-style", 0.82), "high", true, false)
	var host := setup["host"] as Node2D
	var material := setup["material"] as ShaderMaterial
	VisualStyle.set_effect_time_for_tests(host, 4.0)
	var first_state := VisualStyle.effect_state(host)
	VisualStyle.set_effect_time_for_tests(host, 19.0)
	var second_state := VisualStyle.effect_state(host)
	_assert(bool(first_state.get("reduced_motion", false)), "Reduced motion musi być częścią jawnego stanu prezentacji.")
	_assert(is_equal_approx(float(first_state.get("visual_time", -1.0)), 0.0), "Reduced motion musi zamrozić wyświetlaną fazę mimo jawnego czasu.")
	_assert(is_equal_approx(float(second_state.get("visual_time", -1.0)), 0.0), "Zmiana czasu nie może poruszać efektu w reduced motion.")
	_assert(is_equal_approx(float(material.get_shader_parameter("interactable_anim_time")), 0.0), "Shader także musi dostać zamrożoną fazę reduced motion.")
	_assert(float(material.get_shader_parameter("interactable_motion_strength")) < 1.0, "Reduced motion musi ograniczać ruch materiału niezależnie od fazy.")
	host.free()


func _test_focus_progress_and_resolved_state() -> void:
	var device_context := _context("technical-style", 0.61)
	device_context["effect_variant"] = "diagnostic"
	var setup := _make_effect_host("device", "focus_device", device_context, "medium", false, false, "repairing")
	var host := setup["host"] as Node2D
	var material := setup["material"] as ShaderMaterial
	VisualStyle.set_effect_interaction(host, true, 0.65)
	var focused_state := VisualStyle.effect_state(host)
	_assert(bool(focused_state.get("focused", false)), "Cel interakcji musi dostać jawny stan focus.")
	_assert(is_equal_approx(float(focused_state.get("interaction_progress", -1.0)), 0.65), "Postęp przytrzymania musi trafić do prezentacji materiałowej.")
	_assert(str(focused_state.get("state_tag", "")) == "repairing", "Efekt musi zachować semantyczny tag stanu prefabu.")
	_assert(str(focused_state.get("visual_variant", "")) == "diagnostic", "Wariant urządzenia musi pochodzić z jawnego kontekstu.")
	_assert(float(material.get_shader_parameter("interactable_focus_strength")) > 0.65, "Focus i postęp muszą wzmacniać materiał, nie tworzyć drugiego stanu domenowego.")

	VisualStyle.set_effect_interaction(host, false, 0.9)
	var unfocused_state := VisualStyle.effect_state(host)
	_assert(not bool(unfocused_state.get("focused", true)), "Utrata celu musi natychmiast wyłączyć focus.")
	_assert(is_zero_approx(float(unfocused_state.get("interaction_progress", -1.0))), "Postęp prezentacyjny musi się wyzerować po utracie celu.")
	host.free()
	var semantic_setup := _make_effect_host(
		"device", "opaque_device_id", _context("semantic-style", 0.61), "medium", false, false, "generator"
	)
	var semantic_host := semantic_setup["host"] as Node2D
	_assert(
		str(VisualStyle.effect_state(semantic_host).get("visual_variant", "")) == "generator",
		"Jawny semantyczny tag urządzenia musi zachować jego rozpoznawalność bez wyprowadzania palety ze stable ID."
	)
	semantic_host.free()

	var resolved_setup := _make_effect_host("shortcut", "resolved_shortcut", _context("fiber-style", 0.52), "high", false, true, "opened")
	var resolved_host := resolved_setup["host"] as Node2D
	var resolved_material := resolved_setup["material"] as ShaderMaterial
	var resolved_state := VisualStyle.effect_state(resolved_host)
	_assert(bool(resolved_state.get("resolved", false)), "Stan rozwiązany musi wyciszać efekt na podstawie autorytatywnego stanu obiektu.")
	_assert(is_equal_approx(float(resolved_material.get_shader_parameter("interactable_resolved")), 1.0), "Shader musi dostać jawny stan resolved.")
	resolved_host.free()


func _test_presentation_does_not_mutate_physics_or_root_transform() -> void:
	var host := Node2D.new()
	host.position = Vector2(173.0, -42.0)
	host.rotation = 0.37
	host.scale = Vector2(1.17, 0.83)
	var sprite := Sprite2D.new()
	host.add_child(sprite)
	var transform_before := host.transform
	var context := _context("root-invariant", 0.8)
	VisualStyle.apply_sprite(sprite, context, "root_invariant_device", "high")
	VisualStyle.configure_effect(host, sprite, "device", context, "root_invariant_device", "high", false, false, 72.0, context, "active")
	VisualStyle.set_effect_interaction(host, true, 0.75)
	VisualStyle.set_effect_time_for_tests(host, 14.0)
	var effect := host.get_node_or_null("InteractableVisualEffects")
	_assert(effect != null, "Styl musi zamontować dokładnie jeden lokalny komponent efektów.")
	_assert(host.transform == transform_before, "Efekty nie mogą zmieniać transformu root ani położenia gameplayowego obiektu.")
	_assert(effect != null and not _has_physics_descendant(effect), "Komponent prezentacyjny nie może tworzyć Area2D, colliderów ani innych dzieci fizycznych.")
	VisualStyle.configure_effect(host, sprite, "device", context, "root_invariant_device", "low", true, true, 72.0, context, "complete")
	_assert(host.get_node_or_null("InteractableVisualEffects") == effect, "Rekonfiguracja nie może tworzyć drugiego komponentu efektów.")
	_assert(host.transform == transform_before, "Rekonfiguracja jakości, stanu i reduced motion nie może poruszyć root.")
	host.free()


func _test_shader_uses_only_explicit_animation_time() -> void:
	var shader_code := VisualStyle.INTERACTABLE_SKIN_SHADER.code
	_assert(shader_code.contains("uniform float interactable_anim_time"), "Shader musi deklarować jawny czas animacji sterowany przez runtime i snapshoty.")
	_assert(shader_code.contains("interactable_focus_strength"), "Shader musi przyjmować focus jako parametr prezentacyjny.")
	_assert(shader_code.contains("interactable_motion_strength"), "Shader musi przyjmować ograniczenie ruchu dla reduced motion.")
	_assert(shader_code.contains("interactable_depth"), "Shader musi przyjmować jawny depth_ratio jako parametr prezentacyjny.")
	_assert(not shader_code.contains("TIME"), "Shader interakcji nie może korzystać z wbudowanego TIME ani niedeterministycznego zegara renderera.")


func _test_towed_rescue_context_uses_bounded_refresh() -> void:
	var rescue = RescueScript.new()
	rescue.configure("rescue_context_fixture", null, RescueScript.Stage.TOWING)
	get_root().add_child(rescue)
	var shallow := _context("shallow-water", 0.40)
	rescue.configure_visual_context(shallow, "shallow-water")
	var initial_state: Dictionary = rescue.visual_effect_state_for_tests()
	_assert(is_equal_approx(float(initial_state.get("depth_ratio", -1.0)), 0.40), "Ratunek musi przyjąć początkową głębokość prezentacji.")
	var shallow_drift := _context("shallow-water", 0.405)
	_assert(not rescue.sync_visual_context(shallow_drift, "shallow-water", 0.01), "Subpikselowy dryf głębokości nie może przebudowywać efektów holowanego ocalałego co klatkę.")
	_assert(is_equal_approx(float(rescue.visual_effect_state_for_tests().get("depth_ratio", -1.0)), 0.40), "Pominięte odświeżenie musi zachować ostatni zatwierdzony kontekst.")
	var shallow_step := _context("shallow-water", 0.42)
	_assert(rescue.sync_visual_context(shallow_step, "shallow-water", 0.01), "Zmiana głębokości ponad próg musi odświeżyć materiał.")
	var deep := _context("deep-water", 0.42)
	_assert(rescue.sync_visual_context(deep, "deep-water", 0.01), "Zmiana jawnego kontekstu musi odświeżyć paletę niezależnie od głębokości.")
	var final_state: Dictionary = rescue.visual_effect_state_for_tests()
	_assert(str(final_state.get("context_id", "")) == "deep-water", "Holowany ocalały musi przejąć jawny kontekst prezentacji.")
	_assert(is_equal_approx(float(final_state.get("depth_ratio", -1.0)), 0.42), "Próg odświeżenia nie może zgubić istotnej zmiany głębokości.")
	rescue.free()


func _test_tool_locker_mounting_is_contextual_and_presentation_only() -> void:
	var locker = ContainerScript.new()
	locker.configure("tool_locker_fixture", "Szafka testowa", {"scrap": 1}, -1, "crowbar", "pry")
	locker.position = Vector2(137.0, -58.0)
	locker.rotation = 0.19
	locker.scale = Vector2(1.08, 0.93)
	get_root().add_child(locker)
	var root_transform_before: Transform2D = locker.transform
	locker.set_graphics_quality("low")
	var cool_context := _context("cool-salvage", 0.36)
	locker.configure_visual_context(cool_context, "cool-salvage")
	var mounting := locker.get_node_or_null("ToolLockerFrontMount") as Node2D
	_assert(mounting != null and mounting.visible and mounting.z_index == 1, "Szafka techniczna musi mieć przednią, bezkolizyjną warstwę mocowania.")
	_assert(mounting != null and mounting.get_child_count() >= 2, "Low musi zachować główną opaskę albo zaciski szafki.")
	_assert(mounting != null and not _has_physics_descendant(mounting), "Mocowanie szafki nie może tworzyć collidera ani Area2D.")
	var geometry_signature := _mount_geometry_signature(mounting)
	var first_color_signature := _semantic_color_signature(locker)
	var expected_child_count := mounting.get_child_count() if mounting != null else -1
	locker.set_reduced_motion(true)
	var rebuilt_mounting := locker.get_node_or_null("ToolLockerFrontMount") as Node2D
	_assert(rebuilt_mounting != null and rebuilt_mounting.get_child_count() == expected_child_count, "Reduced motion musi przebudować ten sam stabilny zestaw mocowań bez akumulacji dzieci.")
	locker.set_reduced_motion(false)
	var warm_context := _context("warm-salvage", 0.36, Color("d49a62"))
	locker.configure_visual_context(warm_context, "warm-salvage")
	var recolored_mounting := locker.get_node_or_null("ToolLockerFrontMount") as Node2D
	_assert(_mount_geometry_signature(recolored_mounting) == geometry_signature, "Zmiana kolorów kontekstu nie może reinterpretować stable ID jako wariantu mapy.")
	_assert(_semantic_color_signature(locker) != first_color_signature, "Etykieta szafki musi odświeżyć jawnie przekazany kolor.")
	_assert(locker.transform == root_transform_before, "Zmiana kontekstu i jakości mocowania nie może poruszyć korzenia gameplayowego szafki.")
	locker.free()


func _context(context_id: String, depth_ratio: float, accent: Color = Color("72cfd0")) -> Dictionary:
	return {
		"context_id": context_id,
		"depth_ratio": depth_ratio,
		"colors": {
			"tint": Color("a8cad0"),
			"patina": Color("78979a"),
			"accent": accent,
			"rim": Color("b9edf0"),
			"shadow": Color("091d24"),
			"silt": Color("5f797c"),
			"body_dark": Color("142b31"),
			"body_mid": Color("35535a"),
			"body_light": Color("88a7a8"),
		},
	}


func _make_effect_host(
	role: String,
	stable_id: String,
	context: Dictionary,
	quality: String,
	reduced_motion: bool,
	resolved: bool,
	state_tag: String = ""
) -> Dictionary:
	var host := Node2D.new()
	var sprite := Sprite2D.new()
	host.add_child(sprite)
	VisualStyle.apply_sprite(sprite, context, stable_id, quality, 0.55 if resolved else 1.0)
	VisualStyle.configure_effect(
		host,
		sprite,
		role,
		context,
		stable_id,
		quality,
		reduced_motion,
		resolved,
		58.0,
		context,
		state_tag
	)
	return {
		"host": host,
		"sprite": sprite,
		"material": sprite.material as ShaderMaterial,
	}


func _mount_geometry_signature(mounting: Node2D) -> String:
	if mounting == null:
		return ""
	var signature := ""
	for child in mounting.get_children():
		if child is Line2D:
			signature += str((child as Line2D).points) + "|"
		elif child is Polygon2D:
			signature += str((child as Polygon2D).polygon) + "|"
	return signature


func _semantic_color_signature(locker: Node) -> String:
	var overlay := locker.get_node_or_null("SemanticMarking") as Node2D
	if overlay == null:
		return ""
	var signature := ""
	for child in overlay.get_children():
		if child is Line2D:
			signature += str((child as Line2D).default_color) + "|"
		elif child is Polygon2D:
			signature += str((child as Polygon2D).color) + "|"
	return signature


func _has_physics_descendant(node: Node) -> bool:
	for child in node.get_children():
		if child is CollisionObject2D or child is CollisionShape2D or child is CollisionPolygon2D:
			return true
		if _has_physics_descendant(child):
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Interactable visual style test failed: " + message)
