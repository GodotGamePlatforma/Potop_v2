extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const PLATFORM_PRERENDER_PATH := "res://assets/intro/platform_prerender.png"
const PLATFORM_PRERENDER_SIZE := Vector2(1672.0, 941.0)
const PLATFORM_PRERENDER_SHA256 := "B27242D563A474D9318FFA767504A8225CB1940B6635A85447458057DF74B19C"
const MIRA_PORTRAIT_PATH := "res://assets/ui/portraits/mira_boruta_portrait_v1.png"

const TEST_SAVE := "user://test_intro_flow.tres"
const TEST_PENDING := "user://test_intro_flow.pending.tres"
const TEST_BACKUP := "user://test_intro_flow.backup.tres"

var _failed := false


func _ready() -> void:
	_remove_test_saves()
	SaveManager.configure_paths(TEST_SAVE, TEST_PENDING, TEST_BACKUP)

	var game = GameRootScene.instantiate()
	add_child(game)
	await _frames(2)
	var low_settings: Dictionary = game.user_settings.snapshot()
	low_settings["graphics"] = {"quality": "low"}
	_assert(game.user_settings.apply(low_settings, false) == OK, "Intro test should be able to seed a low presentation profile before scene routing.")
	var new_game_button := game.current_scene.find_child("NewGameButton", true, false) as Button
	_assert(new_game_button != null, "Main menu should expose the real new-game button.")
	if new_game_button != null:
		new_game_button.pressed.emit()
	await _frames(3)

	_assert(game.game_state != null, "Starting through the menu should create a campaign before the intro.")
	_assert(game.current_scene != null and game.current_scene.name == "IntroScene", "The real menu flow should open IntroScene.")
	_assert(game.game_state != null and int(game.game_state.current_phase) == GamePhaseScript.Phase.BASE_PLANNING, "Intro must remain outside saved campaign phases.")
	var saved_during_intro = SaveManager.load_game()
	_assert(saved_during_intro != null and int(saved_during_intro.current_phase) == GamePhaseScript.Phase.BASE_PLANNING, "The initial BASE_PLANNING save must already exist while the intro is playing.")

	var intro = game.current_scene
	var platform_plate := intro.find_child("PlatformReveal", true, false) as TextureRect if intro != null else null
	_assert(platform_plate != null, "Intro must expose the platform reveal as a static TextureRect.")
	_assert(platform_plate != null and platform_plate.texture != null, "The platform reveal must load its prerendered texture.")
	if platform_plate != null and platform_plate.texture != null:
		_assert(platform_plate.texture.resource_path == PLATFORM_PRERENDER_PATH, "Intro must use the canonical platform prerender asset.")
		_assert(platform_plate.texture.get_size() == PLATFORM_PRERENDER_SIZE, "The canonical platform prerender must preserve its authored 1672x941 frame.")
		_assert(FileAccess.get_sha256(PLATFORM_PRERENDER_PATH).to_upper() == PLATFORM_PRERENDER_SHA256, "The canonical platform prerender pixels must match the approved source image.")
	_assert(intro == null or intro.find_child("BaseEnvironment", true, false) == null, "Intro must not instantiate the gameplay BaseEnvironment.")
	_assert(intro == null or intro.find_child("BaseWorldViewport", true, false) == null, "Intro must not instantiate the gameplay 3D world viewport.")
	_assert(intro == null or intro.find_child("ArrivalDetails", true, false) == null, "The retired procedural founder silhouettes must not remain in runtime.")
	_assert(intro == null or intro.find_children("*", "SubViewport", true, false).is_empty(), "Intro must not allocate any SubViewport.")
	_assert(intro == null or intro.find_children("*", "Node3D", true, false).is_empty(), "Intro must remain a purely 2D presentation tree.")
	_assert(intro == null or not intro.has_method("set_graphics_quality"), "Graphics quality must not reconfigure a static intro prerender.")
	_assert(intro == null or intro.find_child("VoicePlayer", true, false) == null, "Intro must not instantiate a voice player.")
	var speaker_label := intro.find_child("SpeakerLabel", true, false) as Label if intro != null else null
	_assert(speaker_label != null and speaker_label.text == "MIRA", "The intro should identify the author of its text without implying voice-over.")
	var mira_portrait := intro.find_child("MiraPortrait", true, false) as Control if intro != null else null
	_assert(mira_portrait != null, "Mira's portrait must be part of the intro caption layer.")
	if mira_portrait != null:
		_assert(str(mira_portrait.get("survivor_id")) == "mira", "The intro portrait must be configured from Mira's shared survivor identity.")
		_assert(mira_portrait.has_method("portrait_texture") and mira_portrait.has_method("uses_procedural_fallback"), "The intro must use the shared SurvivorPortrait control.")
		var portrait_texture := mira_portrait.call("portrait_texture") as Texture2D
		_assert(portrait_texture != null and portrait_texture.resource_path == MIRA_PORTRAIT_PATH, "Mira's intro portrait must resolve the approved authored raster.")
		_assert(not bool(mira_portrait.call("uses_procedural_fallback")), "Mira's approved authored portrait must not fall back to procedural drawing.")
		var intro_rect: Rect2 = (intro as Control).get_global_rect()
		var portrait_rect: Rect2 = mira_portrait.get_global_rect()
		_assert(intro_rect.encloses(portrait_rect), "Mira's portrait must remain inside the intro viewport.")
		_assert(portrait_rect.get_center().x < intro_rect.get_center().x and portrait_rect.get_center().y > intro_rect.get_center().y, "Mira's portrait must stay in the lower-left caption rail instead of covering the key center of the frame.")
	if intro != null and intro.has_method("get_caption_windows_for_tests"):
		var caption_windows: Array = intro.call("get_caption_windows_for_tests")
		_assert(caption_windows.size() == 7, "Intro should expose all seven authored text windows.")
		for index in range(caption_windows.size()):
			var caption: Dictionary = caption_windows[index]
			_assert(float(caption["start"]) < float(caption["end"]), "Caption %d should have a positive display window." % (index + 1))
			_assert(not str(caption["text"]).strip_edges().is_empty(), "Caption %d should preserve its canonical text." % (index + 1))
	else:
		_assert(false, "IntroScene should expose its text timing contract for tests.")
	if intro != null and intro.has_method("set_timeline_time_for_tests"):
		var caption_windows: Array = intro.call("get_caption_windows_for_tests")
		for index in range(caption_windows.size()):
			var caption: Dictionary = caption_windows[index]
			var caption_midpoint := (float(caption["start"]) + float(caption["end"])) * 0.5
			intro.call("set_timeline_time_for_tests", caption_midpoint)
			_assert(_alpha(intro, "SubtitlePanel") > 0.99, "Mira's portrait and caption panel must be fully visible during caption %d." % (index + 1))
			_assert(mira_portrait != null and mira_portrait.is_visible_in_tree(), "Mira's portrait must remain visible for caption %d." % (index + 1))
		intro.call("set_timeline_time_for_tests", 4.0)
		_assert(_label_text(intro, "NarrationLabel").contains("Pięć lat"), "Opening caption should be Mira's first-person chronicle.")
		var ambient_player := intro.find_child("AmbientPlayer", true, false) as AudioStreamPlayer
		_assert(ambient_player != null and is_equal_approx(ambient_player.volume_db, 0.0), "Ambient should keep a fixed local level because intro has no voice-over ducking.")
		intro.call("set_timeline_time_for_tests", 18.5)
		_assert(_alpha(intro, "DiscoveryPlate") > 0.9 and _label_text(intro, "NarrationLabel").contains("było nas troje"), "Discovery beat should show exactly the human premise named by Mira.")
		intro.call("set_timeline_time_for_tests", 25.0)
		_assert(_alpha(intro, "PlatformReveal") > 0.9 and _label_text(intro, "NarrationLabel").contains("odbudować świat"), "The prerendered platform beat should bridge the illustration to live gameplay.")
		intro.call("set_timeline_time_for_tests", 28.5)
		_assert(ambient_player != null and is_equal_approx(ambient_player.volume_db, 0.0), "Ambient level should remain stable between captions.")
		intro.call("set_timeline_time_for_tests", 34.0)
		_assert(_alpha(intro, "BridgePlate") > 0.9 and _label_text(intro, "NarrationLabel").contains("Pod nami"), "Underwater beat should connect survival resources and missing people to the depths.")
		intro.call("set_timeline_time_for_tests", 43.0)
		_assert(_alpha(intro, "TitleGroup") > 0.9, "The final title should be visible after Mira's last line.")
	else:
		_assert(false, "IntroScene should expose a deterministic presentation timeline for tests.")

	var skip_button := intro.find_child("IntroSkipButton", true, false) as Button if intro != null else null
	_assert(skip_button != null, "Intro should expose a stable skip button.")
	if skip_button != null:
		skip_button.pressed.emit()
	await _frames(3)
	_assert(game.current_scene != null and game.current_scene.name == "BaseScene", "Skipping should enter the live base.")
	_assert(game.game_state.tutorial.step == TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE, "Intro must hand off to the first three-day tutorial objective.")

	game.queue_free()
	await _frames(3)
	var continued_game = GameRootScene.instantiate()
	add_child(continued_game)
	await _frames(2)
	_assert(continued_game.current_scene != null and continued_game.current_scene.name == "MainMenu", "A fresh root should still begin in the menu.")
	_assert(continued_game.continue_campaign(), "Continue should load the campaign saved before the intro.")
	await _frames(3)
	_assert(continued_game.current_scene != null and continued_game.current_scene.name == "BaseScene", "Continue must not replay the presentational intro.")

	continued_game.queue_free()
	await _frames(3)
	_remove_test_saves()
	var programmatic_game = GameRootScene.instantiate()
	add_child(programmatic_game)
	await _frames(2)
	_assert(programmatic_game.start_new_campaign("standard", 808, false), "Existing programmatic campaign start should still succeed.")
	await _frames(3)
	_assert(programmatic_game.current_scene != null and programmatic_game.current_scene.name == "BaseScene", "Default programmatic starts should continue to bypass intro for existing automated callers.")
	_assert(programmatic_game.start_new_campaign("standard", 809, false, true), "A programmatic caller should be able to opt into intro explicitly.")
	await _frames(3)
	var natural_intro = programmatic_game.current_scene
	_assert(natural_intro != null and natural_intro.name == "IntroScene", "Explicit intro opt-in should show IntroScene.")
	if natural_intro != null:
		var natural_player := natural_intro.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_assert(natural_player != null, "Intro should use AnimationPlayer as its authoritative clock.")
		if natural_player != null:
			natural_player.speed_scale = 1000.0
	await _frames(12)
	_assert(programmatic_game.current_scene != null and programmatic_game.current_scene.name == "BaseScene", "The natural animation end should use the same safe handoff as skip.")

	natural_intro = null
	programmatic_game.queue_free()
	programmatic_game = null
	await _frames(3)
	game = null
	continued_game = null
	saved_during_intro = null
	intro = null
	await get_tree().create_timer(0.1).timeout
	_remove_test_saves()
	SaveManager.reset_paths()
	if _failed:
		get_tree().quit(1)
		return
	print("Intro flow test passed: text-only prerendered intro, fixed ambient, deterministic beats, skip and continue are safe.")
	get_tree().quit(0)


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _label_text(root: Node, node_name: String) -> String:
	var label := root.find_child(node_name, true, false) as Label
	return label.text if label != null else ""


func _alpha(root: Node, node_name: String) -> float:
	var item := root.find_child(node_name, true, false) as CanvasItem
	return item.modulate.a if item != null else 0.0


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Intro flow test failed: " + message)


func _remove_test_saves() -> void:
	for path in [TEST_SAVE, TEST_PENDING, TEST_BACKUP]:
		var absolute_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute_path):
			DirAccess.remove_absolute(absolute_path)
