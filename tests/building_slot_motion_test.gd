extends Node

const BuildingSlotScene := preload("res://scenes/base/BuildingSlot.tscn")
const BaseScene := preload("res://scenes/base/BaseScene.tscn")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")

var _failed := false


func _ready() -> void:
	var slot = BuildingSlotScene.instantiate()
	slot.position = Vector2(34.0, 28.0)
	slot.size = Vector2(320.0, 240.0)
	add_child(slot)
	await get_tree().process_frame

	slot.configure("test_slot", "workshop", Rect2(0.20, 0.25, 0.55, 0.50))
	var pad := slot.get_node_or_null("PadVisual") as Panel
	_assert(pad != null, "Slot powinien zachować osobny, nieinteraktywny PadVisual.")
	_assert(slot.focus_mode == Control.FOCUS_ALL, "Slot powinien być dostępny z klawiatury i pada.")
	if pad == null:
		_finish()
		return

	var hitbox_rect := Rect2(slot.position, slot.size)
	var visual_anchors := Rect2(
		Vector2(pad.anchor_left, pad.anchor_top),
		Vector2(pad.anchor_right - pad.anchor_left, pad.anchor_bottom - pad.anchor_top)
	)
	_assert(visual_anchors.is_equal_approx(Rect2(0.20, 0.25, 0.55, 0.50)), "Konfiguracja grafiki pada nie może zmieniać większego hitboxu slotu.")

	slot.set_state(false, true)
	slot.set_animation_time_for_tests(0.0)
	var queued_low_border := _style(pad).border_color
	slot.set_animation_time_for_tests(1.4)
	var queued_high_border := _style(pad).border_color
	_assert(not queued_low_border.is_equal_approx(queued_high_border), "Zakolejkowana budowa powinna mieć spokojny, deterministyczny puls obramowania.")

	slot.set_reduced_motion(true)
	slot.set_animation_time_for_tests(0.0)
	var reduced_start_border := _style(pad).border_color
	slot.set_animation_time_for_tests(1.4)
	var reduced_later_border := _style(pad).border_color
	_assert(reduced_start_border.is_equal_approx(reduced_later_border), "Reduced motion powinien zatrzymać ciągły puls, zachowując czytelny stan.")

	slot.set_reduced_motion(false)
	slot.set_instant_motion(true)
	slot.clear_animation_time_override()
	slot.set_state(false, false)
	var hover_events: Array[Dictionary] = []
	var highlight_events: Array[Dictionary] = []
	slot.slot_hover_changed.connect(func(slot_id: String, hovered: bool) -> void:
		hover_events.append({"slot_id": slot_id, "hovered": hovered})
	)
	slot.slot_highlight_changed.connect(func(slot_id: String, mode: StringName) -> void:
		highlight_events.append({"slot_id": slot_id, "mode": mode})
	)
	var normal_style := _style_snapshot(pad)
	_assert(Color(normal_style.border).a == 0.0 and Color(normal_style.fill).a == 0.0, "Neutralny hitbox slotu nie może rysować prostokątnego pola nad modelem 3D.")

	# The guided target now uses the same world-space silhouette pipeline. Its old
	# amber Panel must stay fully transparent, even while input states are active.
	slot.set_state(true, false)
	slot.set_animation_time_for_tests(0.0)
	_assert(_style_matches(pad, normal_style), "Cel tutoriala nie może rysować dawnego pomarańczowego prostokąta.")
	slot.set_animation_time_for_tests(1.4)
	_assert(_style_matches(pad, normal_style), "Puls tutoriala ma należeć do poświaty sylwetki, nie do prostokątnego PadVisual.")
	_assert(highlight_events.size() == 1 and StringName(highlight_events.back().mode) == &"tutorial", "Cel tutoriala powinien przekazać osobny tryb poświaty 3D.")
	slot.emit_signal("mouse_entered")
	slot.emit_signal("button_down")
	_assert(highlight_events.size() == 1 and StringName(slot.highlight_mode()) == &"tutorial", "Prowadzony cel ma zachować bursztynową poświatę podczas hoveru i wciśnięcia.")
	_assert(_style_matches(pad, normal_style), "Interakcja z celem tutoriala nie może przywracać pomarańczowego prostokąta.")
	slot.emit_signal("button_up")
	slot.emit_signal("mouse_exited")
	slot.grab_focus()
	await get_tree().process_frame
	_assert(StringName(slot.highlight_mode()) == &"tutorial", "Focus celu tutoriala nie może zmieniać prowadzenia na zwykły cyjan.")
	slot.set_state(false, false)
	_assert(not highlight_events.is_empty() and StringName(highlight_events.back().mode) == &"focus", "Po ustaniu celu tutoriala zapamiętany focus powinien natychmiast odzyskać zwykłą poświatę.")
	slot.release_focus()
	await get_tree().process_frame
	_assert(not highlight_events.is_empty() and StringName(highlight_events.back().mode) == &"none", "Usunięcie tutoriala i focusu powinno wyczyścić poświatę.")
	hover_events.clear()
	highlight_events.clear()

	slot.emit_signal("mouse_entered")
	_assert(_style_matches(pad, normal_style), "Hover ma pozostawić prostokątny PadVisual niewidoczny; feedback przejmuje sylwetka 3D.")
	_assert(hover_events.size() == 1 and bool(hover_events[0].hovered) and str(hover_events[0].slot_id) == "test_slot", "Wejście myszy powinno dokładnie raz zachować publiczny sygnał tooltipu.")
	_assert(highlight_events.size() == 1 and StringName(highlight_events[0].mode) == &"hover", "Wejście myszy powinno przekazać tryb hover do obrysu 3D.")
	slot.emit_signal("button_down")
	_assert(_style_matches(pad, normal_style), "Wciśnięcie nie może przywracać prostokątnego pola.")
	_assert(highlight_events.size() == 2 and StringName(highlight_events[1].mode) == &"pressed", "Wciśnięcie powinno wzmocnić obrys 3D osobnym trybem.")
	slot.emit_signal("button_up")
	slot.emit_signal("mouse_exited")
	_assert(hover_events.size() == 2 and not bool(hover_events[1].hovered), "Wyjście myszy powinno dokładnie raz zgłosić koniec hoveru.")
	_assert(not highlight_events.is_empty() and StringName(highlight_events.back().mode) == &"none", "Wyjście myszy powinno wyczyścić obrys 3D.")

	slot.grab_focus()
	await get_tree().process_frame
	_assert(slot.has_focus() and _style_matches(pad, normal_style), "Focus klawiatury powinien pozostać dostępny bez prostokątnego obramowania pada.")
	_assert(not highlight_events.is_empty() and StringName(highlight_events.back().mode) == &"focus", "Focus klawiatury powinien sterować tym samym obrysem sylwetki 3D.")
	_assert(Rect2(slot.position, slot.size).is_equal_approx(hitbox_rect), "Mikroanimacja nie może poruszać ani skalować hitboxu slotu.")
	_assert(visual_anchors.is_equal_approx(Rect2(Vector2(pad.anchor_left, pad.anchor_top), Vector2(pad.anchor_right - pad.anchor_left, pad.anchor_bottom - pad.anchor_top))), "Mikroanimacja nie może zmieniać layoutu widocznego pada.")

	slot.queue_free()
	await get_tree().process_frame
	await _test_controller_tutorial_highlight_flow()
	await _test_controller_highlight_flow()
	_finish()


func _test_controller_tutorial_highlight_flow() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(19_730, DifficultyProfileScript.new())
	state.current_phase = GamePhaseScript.Phase.BASE_PLANNING

	var base = BaseScene.instantiate()
	_disable_base_music(base)
	base.seed_user_settings_before_ready("low", true)
	add_child(base)
	base.bind(null, state)
	await _settle()

	var environment = base.get_node_or_null("BaseEnvironment")
	var top_left := base.get_node_or_null("BaseEnvironment/PlatformBoard/BuildingSlots/Slot_top_left") as Button
	_assert(environment != null and top_left != null, "Test tutorialowej poświaty wymaga środowiska i realnego hitboxu bazy.")
	if environment == null or top_left == null:
		await _dispose_base(base)
		return

	_assert(_highlight_matches(environment, "top_right", &"tutorial", "Ruin_top_right"), "Początek kampanii ma prowadzić bursztynową poświatą po sylwetce ruiny Domu Wspólnoty.")
	_assert(_highlight_is_amber(environment), "Tutorialowa poświata powinna być bursztynowa, odrębna od cyjanu hoveru.")
	top_left.grab_focus()
	await _settle()
	_assert(_highlight_matches(environment, "top_right", &"tutorial", "Ruin_top_right"), "Fokus innego slotu nie powinien ukrywać prowadzonego celu tutoriala.")
	top_left.emit_signal("mouse_entered")
	top_left.emit_signal("button_down")
	await _settle()
	_assert(_highlight_matches(environment, "top_right", &"tutorial", "Ruin_top_right"), "Hover i wciśnięcie innego slotu nie powinny zastępować celu prowadzonego tutoriala.")

	state.tutorial.step = TutorialStateScript.Step.DIVE_MOVEMENT
	base._render()
	await _settle()
	_assert(_highlight_matches(environment, "top_left", &"pressed", "Ruin_top_left"), "Po przejściu kroku tutoriala zapamiętane wciśnięcie powinno wrócić bez nowego ruchu myszy.")
	top_left.emit_signal("button_up")
	await get_tree().process_frame
	_assert(_highlight_matches(environment, "top_left", &"hover", "Ruin_top_left"), "Zwolnienie przycisku po tutorialu powinno wrócić do zwykłego hoveru.")
	top_left.emit_signal("mouse_exited")
	await _settle()
	_assert(_highlight_matches(environment, "top_left", &"focus", "Ruin_top_left"), "Po wyjściu kursora ma pozostać zapamiętany focus.")

	state.tutorial.step = TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE
	base._render()
	await _settle()
	_assert(_highlight_matches(environment, "top_right", &"tutorial", "Ruin_top_right"), "Ponowne aktywowanie kroku prowadzonego powinno przywrócić bursztynową ruinę.")
	top_left.emit_signal("pressed")
	await _settle()
	var modal := base.find_child("BuildingModal", true, false) as Control
	_assert(modal != null and modal.visible, "Kliknięcie realnego slotu powinno otworzyć modal także podczas prowadzenia.")
	_assert(not bool(environment.building_highlight_state_for_tests().get("active", true)), "Modal musi wyłączyć również tutorialową poświatę świata.")
	base._close_building_panel()
	await _settle()
	_assert(_highlight_matches(environment, "top_right", &"tutorial", "Ruin_top_right"), "Zamknięcie modala powinno przywrócić prowadzony cel, nie prostokąt ani drugi stan.")

	state.tutorial.step = TutorialStateScript.Step.DIVE_MOVEMENT
	base._render()
	await _settle()
	_assert(_highlight_matches(environment, "top_left", &"focus", "Ruin_top_left"), "Usunięcie celu tutoriala powinno ujawnić focus przywrócony po modalu.")
	top_left.release_focus()
	await _dispose_base(base)


func _test_controller_highlight_flow() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(19_731, DifficultyProfileScript.new())
	state.tutorial.complete()
	state.current_phase = GamePhaseScript.Phase.BASE_PLANNING

	var base = BaseScene.instantiate()
	_disable_base_music(base)
	base.seed_user_settings_before_ready("low", true)
	add_child(base)
	base.bind(null, state)
	await _settle()

	var environment = base.get_node_or_null("BaseEnvironment")
	var top_left := base.get_node_or_null("BaseEnvironment/PlatformBoard/BuildingSlots/Slot_top_left") as Button
	var bottom_right := base.get_node_or_null("BaseEnvironment/PlatformBoard/BuildingSlots/Slot_bottom_right") as Button
	_assert(environment != null and top_left != null and bottom_right != null, "Test integracyjny obrysu wymaga środowiska i obu realnych hitboxów bazy.")
	if environment == null or top_left == null or bottom_right == null:
		await _dispose_base(base)
		return
	_assert(not bool(environment.building_highlight_state_for_tests().get("active", true)), "Po wejściu do bazy bez focusu ani hoveru obrys musi być wyłączony.")

	top_left.grab_focus()
	await _settle()
	_assert(_highlight_matches(environment, "top_left", &"focus", "Ruin_top_left"), "Focus klawiatury ma obrysować aktualną ruinę wskazanego slotu.")

	bottom_right.emit_signal("mouse_entered")
	await get_tree().process_frame
	_assert(_highlight_matches(environment, "bottom_right", &"hover", "Ruin_bottom_right"), "Hover ma mieć priorytet nad focusem innego slotu.")
	bottom_right.emit_signal("button_down")
	await get_tree().process_frame
	_assert(_highlight_matches(environment, "bottom_right", &"pressed", "Ruin_bottom_right"), "Wciśnięcie ma wzmocnić obrys hoverowanego slotu bez zmiany celu.")
	bottom_right.emit_signal("button_up")
	await get_tree().process_frame
	_assert(_highlight_matches(environment, "bottom_right", &"hover", "Ruin_bottom_right"), "Zwolnienie przycisku nad slotem ma wrócić do trybu hover.")
	bottom_right.emit_signal("mouse_exited")
	await _settle()
	_assert(_highlight_matches(environment, "top_left", &"focus", "Ruin_top_left"), "Po wyjściu hoveru obrys ma deterministycznie wrócić do fokusowanego slotu.")

	top_left.emit_signal("pressed")
	await _settle()
	var modal := base.find_child("BuildingModal", true, false) as Control
	_assert(modal != null and modal.visible, "Kliknięcie realnego slotu powinno otworzyć modal budynku.")
	_assert(not bool(environment.building_highlight_state_for_tests().get("active", true)), "Modal budynku musi wyłączyć obrys świata pod blokującą warstwą UI.")
	base._close_building_panel()
	await _settle()
	_assert(_highlight_matches(environment, "top_left", &"focus", "Ruin_top_left"), "Zamknięcie modala ma przywrócić focus i obrys właściwego slotu.")

	state.current_phase = GamePhaseScript.Phase.END_DAY_REPORT
	base._refresh_building_highlight()
	_assert(not bool(environment.building_highlight_state_for_tests().get("active", true)), "Faza poza planowaniem i kryzysem musi bezwarunkowo wyłączyć obrys budynków.")
	state.current_phase = GamePhaseScript.Phase.BASE_PLANNING
	base._refresh_building_highlight()
	_assert(_highlight_matches(environment, "top_left", &"focus", "Ruin_top_left"), "Powrót do planowania ma odtworzyć obrys z bieżącego stanu focusu, bez równoległej kopii stanu.")

	top_left.release_focus()
	await _settle()
	_assert(not bool(environment.building_highlight_state_for_tests().get("active", true)), "Utrata ostatniego focusu ma wyłączyć viewport maski i obrys.")
	await _dispose_base(base)


func _dispose_base(base: Node) -> void:
	base.free()
	await get_tree().process_frame
	await get_tree().process_frame


func _disable_base_music(base: Node) -> void:
	var music_player := base.get_node_or_null("BaseMusicPlayer") as AudioStreamPlayer
	if music_player == null:
		return
	music_player.autoplay = false
	music_player.stream = null


func _highlight_matches(environment, slot_id: String, mode: StringName, variant_prefix: String) -> bool:
	var state: Dictionary = environment.building_highlight_state_for_tests()
	if not bool(state.get("active", false)) or str(state.get("slot_id", "")) != slot_id or StringName(state.get("mode", &"none")) != mode:
		return false
	var world_state: Dictionary = state.get("world", {})
	var meshes: Array = world_state.get("meshes", [])
	if meshes.is_empty() or int(world_state.get("mesh_count", 0)) != meshes.size():
		return false
	for mesh_value in meshes:
		var mesh_state: Dictionary = mesh_value
		if not str(mesh_state.get("node_name", "")).begins_with(variant_prefix):
			return false
	return true


func _highlight_is_amber(environment) -> bool:
	var state: Dictionary = environment.building_highlight_state_for_tests()
	var color := Color(state.get("glow_color", Color.TRANSPARENT))
	return color.r > 0.9 and color.r > color.g and color.g > color.b and color.a > 0.8


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _style(pad: Panel) -> StyleBoxFlat:
	return pad.get_theme_stylebox("panel") as StyleBoxFlat


func _style_snapshot(pad: Panel) -> Dictionary:
	var style := _style(pad)
	return {
		"fill": style.bg_color,
		"border": style.border_color,
		"width": style.border_width_left,
	}


func _style_matches(pad: Panel, expected: Dictionary) -> bool:
	var style := _style(pad)
	return (
		style.bg_color.is_equal_approx(Color(expected.fill))
		and style.border_color.is_equal_approx(Color(expected.border))
		and style.border_width_left == int(expected.width)
	)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Building slot motion test failed: " + message)


func _finish() -> void:
	if _failed:
		get_tree().quit(1)
		return
	print("Building slot motion test passed: tutorial, hover, press and keyboard focus delegate to a deterministic soft 3D silhouette glow without slot rectangles.")
	get_tree().quit(0)
