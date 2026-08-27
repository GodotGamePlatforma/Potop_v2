extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const PLATFORM_PRERENDER_PATH := "res://assets/intro/platform_prerender.png"
const PLATFORM_PRERENDER_SIZE := Vector2(1672.0, 941.0)
const PLATFORM_PRERENDER_SHA256 := "B27242D563A474D9318FFA767504A8225CB1940B6635A85447458057DF74B19C"
const MIRA_PORTRAIT_PATH := "res://assets/ui/portraits/mira_boruta_portrait_v1.png"
const INTRO_PREMIX_PATH := "res://assets/audio/intro/intro_ambient.ogg"
const INTRO_PREMIX_LENGTH_SECONDS := 45.0
const INTRO_PREMIX_SAMPLE_RATE := 48000
const INTRO_PREMIX_BPM := 64.0
const INTRO_PREMIX_BEAT_COUNT := 48
const INTRO_PREMIX_BAR_BEATS := 4

const TEST_SAVE := "user://test_intro_flow.tres"
const TEST_PENDING := "user://test_intro_flow.pending.tres"
const TEST_BACKUP := "user://test_intro_flow.backup.tres"
const TEST_REPLACEMENT_GUARD := TEST_SAVE + ".replace_guard"

var _failed := false


class FailingMapCompiler:
	extends RefCounted

	var _errors: PackedStringArray

	func _init(errors: PackedStringArray) -> void:
		_errors = errors.duplicate()

	func generate(_world, _seed: int) -> PackedStringArray:
		return _errors.duplicate()


class InvalidCandidateMapCompiler:
	extends RefCounted

	func generate(_world, _seed: int) -> PackedStringArray:
		# Returning success without compiling the blueprint forces the subsequent
		# full candidate validation branch without coupling the test to a private
		# GameState field.
		return PackedStringArray()


func _ready() -> void:
	_remove_test_saves()
	SaveManager.configure_paths(TEST_SAVE, TEST_PENDING, TEST_BACKUP)
	var previous_campaign = GameStateScript.new()
	var previous_setup_errors: PackedStringArray = previous_campaign.setup_new_campaign(70_001, DifficultyProfileScript.new())
	_assert(previous_setup_errors.is_empty(), "The replacement fixture should initialize against the real current map.")
	_assert(SaveManager.save_game(previous_campaign) == OK, "The replacement fixture should seed a valid previous campaign.")
	var previous_campaign_id := str(previous_campaign.campaign_id)
	var previous_storage_hashes := _storage_hashes()

	var game = GameRootScene.instantiate()
	var failure_codes: Dictionary = game.get_script().get_script_constant_map().get("NewCampaignFailure", {})
	_assert(not failure_codes.is_empty(), "GameRoot should expose stable machine-readable new-campaign failure codes.")
	add_child(game)
	await _frames(2)
	var low_settings: Dictionary = game.user_settings.snapshot()
	low_settings["graphics"] = {"quality": "low"}
	_assert(game.user_settings.apply(low_settings, false) == OK, "Intro test should be able to seed a low presentation profile before scene routing.")
	var new_game_button := game.current_scene.find_child("NewGameButton", true, false) as Button
	_assert(new_game_button != null, "Main menu should expose the real new-game button.")
	var continue_button := game.current_scene.find_child("ContinueButton", true, false) as Button
	var status_label := game.current_scene.find_child("StatusLabel", true, false) as Label
	_assert(continue_button != null and not continue_button.disabled, "A valid previous campaign should enable Continue before replacement.")
	var original_menu = game.current_scene
	var controlled_map_error := "kontrolowany błąd aktualności mapy"
	game.use_next_new_campaign_map_compiler_for_tests(FailingMapCompiler.new(PackedStringArray([controlled_map_error])))
	if new_game_button != null:
		new_game_button.pressed.emit()
	await _frames(2)
	var confirmation := game.current_scene.find_child("NewGameConfirmation", true, false) as ConfirmationDialog
	_assert(confirmation != null and confirmation.visible, "Replacing a valid campaign should require the real confirmation dialog.")
	_assert(confirmation != null and confirmation.dialog_text.contains("dopiero po poprawnym utworzeniu i bezpiecznym zapisie"), "Confirmation should describe deferred replacement instead of delete-first behavior.")
	if confirmation != null:
		confirmation.get_ok_button().pressed.emit()
	await _frames(3)
	var expected_map_failure := "Nie udało się rozpocząć nowej kampanii: dane mapy są nieaktualne lub niespójne. Dotychczasowa kampania pozostała bez zmian."
	_assert(game.current_scene == original_menu and game.current_scene.name == "MainMenu", "A map setup failure must remain in the same real menu instance.")
	_assert(game.game_state == null, "A map setup failure must not publish a new runtime GameState.")
	_assert(game.last_new_campaign_failure == int(failure_codes.get("MAP_SETUP", -1)), "Map setup should retain a stable machine-readable failure category.")
	_assert(game.last_new_campaign_failure_details.has(controlled_map_error), "The exact compiler diagnostic should remain available without becoming an ERROR.")
	_assert(status_label != null and status_label.text == expected_map_failure, "The menu should show the exact product message for stale or inconsistent map data.")
	_assert(continue_button != null and not continue_button.disabled, "Map failure must leave Continue enabled.")
	_assert(_storage_hashes() == previous_storage_hashes, "Map failure must leave all campaign files byte-for-byte unchanged.")
	var preserved_after_map = SaveManager.load_game()
	_assert(preserved_after_map != null and str(preserved_after_map.campaign_id) == previous_campaign_id, "Map failure must keep the previous campaign loadable.")

	SaveManager.fail_next_save_for_tests(ERR_CANT_CREATE)
	new_game_button.pressed.emit()
	await _frames(2)
	confirmation = game.current_scene.find_child("NewGameConfirmation", true, false) as ConfirmationDialog
	if confirmation != null:
		confirmation.get_ok_button().pressed.emit()
	await _frames(3)
	var expected_save_failure := "Nie udało się rozpocząć nowej kampanii: nie udało się bezpiecznie zapisać zmian. Dotychczasowa kampania pozostała bez zmian."
	_assert(game.current_scene == original_menu and game.game_state == null, "Persistence failure must not replace the menu or publish a candidate.")
	_assert(game.last_new_campaign_failure == int(failure_codes.get("PERSISTENCE", -1)), "Persistence failure should retain a stable machine-readable category.")
	_assert(status_label != null and status_label.text == expected_save_failure, "The menu should show the exact safe-save failure message.")
	_assert(continue_button != null and not continue_button.disabled, "Persistence failure must leave Continue enabled.")
	_assert(_storage_hashes() == previous_storage_hashes, "A forced write failure before the transaction must leave all storage hashes unchanged.")
	var preserved_after_save = SaveManager.load_game()
	_assert(preserved_after_save != null and str(preserved_after_save.campaign_id) == previous_campaign_id, "Persistence failure must keep the previous campaign loadable.")

	if continue_button != null:
		continue_button.pressed.emit()
	await _frames(3)
	_assert(game.current_scene != null and game.current_scene.name == "BaseScene", "The real Continue button must still enter Base after a failed replacement.")
	_assert(game.game_state != null and str(game.game_state.campaign_id) == previous_campaign_id, "The real Continue button must load the exact previous campaign after failure.")
	game.queue_free()
	await _frames(3)
	game = GameRootScene.instantiate()
	add_child(game)
	await _frames(2)
	game.user_settings.apply(low_settings, false)
	new_game_button = game.current_scene.find_child("NewGameButton", true, false) as Button
	_assert(new_game_button != null, "A fresh menu should expose New Game for the successful retry.")

	new_game_button.pressed.emit()
	await _frames(2)
	confirmation = game.current_scene.find_child("NewGameConfirmation", true, false) as ConfirmationDialog
	if confirmation != null:
		confirmation.get_ok_button().pressed.emit()
	await _frames(3)

	_assert(game.game_state != null, "Starting through the menu should create a campaign before the intro.")
	_assert(game.current_scene != null and game.current_scene.name == "IntroScene", "The real menu flow should open IntroScene.")
	_assert(game.game_state != null and str(game.game_state.campaign_id) != previous_campaign_id, "A successful retry should publish a genuinely new campaign identity.")
	_assert(_all_storage_candidates_match(game.game_state), "A successful retry must leave only exact copies of the new campaign snapshot.")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(TEST_PENDING)), "A normal successful retry should clean the pending file.")
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
	var intro_audio_players: Array[Node] = intro.find_children("*", "AudioStreamPlayer", true, false) if intro != null else []
	_assert(intro_audio_players.size() == 1, "Intro must use exactly one local premix player without parallel rain or music stems.")
	var ambient_player := intro.find_child("AmbientPlayer", true, false) as AudioStreamPlayer if intro != null else null
	_assert(ambient_player != null, "Intro must expose its single rain-and-music premix as AmbientPlayer.")
	if ambient_player != null:
		_assert(ambient_player.playing, "The premix should start alongside the authoritative intro animation.")
		_assert(not ambient_player.autoplay, "The controller should start the premix explicitly with the intro timeline.")
		_assert(ambient_player.bus == &"Master", "The premix should use the project's one real Master bus.")
		_assert(is_equal_approx(ambient_player.volume_db, 0.0), "The premix should preserve its authored local level without voice-over ducking.")
		var premix_stream := ambient_player.stream as AudioStreamOggVorbis
		_assert(premix_stream != null, "AmbientPlayer should load the authored Ogg Vorbis premix.")
		if premix_stream != null:
			_assert(premix_stream.resource_path == INTRO_PREMIX_PATH, "Intro should resolve the approved rain-and-music premix asset.")
			_assert(not premix_stream.has_loop(), "The 45-second intro premix must not loop.")
			_assert(absf(premix_stream.get_length() - INTRO_PREMIX_LENGTH_SECONDS) <= 0.02, "The premix should preserve the exact 12-bar intro duration.")
			_assert(is_equal_approx(premix_stream.bpm, INTRO_PREMIX_BPM), "The imported premix should preserve the authored 64 BPM grid.")
			_assert(premix_stream.beat_count == INTRO_PREMIX_BEAT_COUNT, "The imported premix should preserve exactly 48 beats.")
			_assert(premix_stream.bar_beats == INTRO_PREMIX_BAR_BEATS, "The imported premix should preserve the 4/4 bar grid.")
			_assert(premix_stream.packet_sequence != null and premix_stream.packet_sequence.sampling_rate == INTRO_PREMIX_SAMPLE_RATE, "The runtime premix should use the authored 48 kHz sample rate.")
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
		_assert(ambient_player != null and is_equal_approx(ambient_player.volume_db, 0.0), "Premix should keep a fixed local level because intro has no voice-over ducking.")
		intro.call("set_timeline_time_for_tests", 18.5)
		_assert(_alpha(intro, "DiscoveryPlate") > 0.9 and _label_text(intro, "NarrationLabel").contains("było nas troje"), "Discovery beat should show exactly the human premise named by Mira.")
		intro.call("set_timeline_time_for_tests", 25.0)
		_assert(_alpha(intro, "PlatformReveal") > 0.9 and _label_text(intro, "NarrationLabel").contains("odbudować świat"), "The prerendered platform beat should bridge the illustration to live gameplay.")
		intro.call("set_timeline_time_for_tests", 28.5)
		_assert(ambient_player != null and is_equal_approx(ambient_player.volume_db, 0.0), "Premix level should remain stable between captions.")
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
	var active_state_before_failure = programmatic_game.game_state
	var active_scene_before_failure = programmatic_game.current_scene
	programmatic_game.set("_seen_narrative_keys", {"preserved_failure_fixture": true})
	programmatic_game.set("_narrative_sync_queued", true)
	var active_narrative_before_failure: Dictionary = programmatic_game.get("_seen_narrative_keys").duplicate(true)
	var active_persistence_before_failure: bool = programmatic_game.campaign_persistence_enabled

	GameDatabase.validation_errors.append("controlled game-data failure")
	var game_data_started: bool = programmatic_game.start_new_campaign("standard", 8080, false)
	GameDatabase.validation_errors.remove_at(GameDatabase.validation_errors.size() - 1)
	_assert(not game_data_started, "Invalid game data should fail through the public new-campaign API.")
	_assert(programmatic_game.last_new_campaign_failure == int(failure_codes.get("GAME_DATA", -1)), "Invalid game data should retain its machine-readable failure category.")
	_assert(programmatic_game.last_new_campaign_failure_text() == "Nie udało się rozpocząć nowej kampanii: dane gry są niekompletne lub uszkodzone. Nie utworzono kampanii.", "Game-data failure should use the exact no-campaign product message.")
	_assert(_failed_attempt_preserved(programmatic_game, active_state_before_failure, active_scene_before_failure, active_narrative_before_failure, active_persistence_before_failure), "Game-data failure must preserve runtime, scene, narrative and persistence mode.")

	_assert(not programmatic_game.start_new_campaign("missing_profile", 80801, false), "An unknown profile should fail through the public new-campaign API.")
	_assert(programmatic_game.last_new_campaign_failure == int(failure_codes.get("PROFILE", -1)), "Unknown profile should retain its machine-readable failure category.")
	_assert(programmatic_game.last_new_campaign_failure_text() == "Nie udało się rozpocząć nowej kampanii: wybrany poziom trudności jest nieprawidłowy. Nie utworzono kampanii.", "Profile failure should use the exact no-campaign product message.")
	_assert(_failed_attempt_preserved(programmatic_game, active_state_before_failure, active_scene_before_failure, active_narrative_before_failure, active_persistence_before_failure), "Profile failure must preserve runtime, scene, narrative and persistence mode.")

	programmatic_game.use_next_new_campaign_map_compiler_for_tests(FailingMapCompiler.new(PackedStringArray(["programmatic map failure"])))
	_assert(not programmatic_game.start_new_campaign("standard", 8081, false, false, true), "A controlled programmatic map failure should return false.")
	_assert(programmatic_game.last_new_campaign_failure == int(failure_codes.get("MAP_SETUP", -1)), "Map setup should retain its machine-readable failure category.")
	_assert(programmatic_game.last_new_campaign_failure_text() == "Nie udało się rozpocząć nowej kampanii: dane mapy są nieaktualne lub niespójne. Nie utworzono kampanii.", "A failure without a persisted previous campaign should use the exact no-campaign suffix.")
	_assert(_failed_attempt_preserved(programmatic_game, active_state_before_failure, active_scene_before_failure, active_narrative_before_failure, active_persistence_before_failure), "Map failure must preserve runtime, scene, narrative and persistence mode.")

	programmatic_game.use_next_new_campaign_map_compiler_for_tests(InvalidCandidateMapCompiler.new())
	_assert(not programmatic_game.start_new_campaign("standard", 80811, false), "A structurally invalid initialized candidate should fail through the public API.")
	_assert(programmatic_game.last_new_campaign_failure == int(failure_codes.get("CANDIDATE_VALIDATION", -1)), "Invalid initialized state should retain its machine-readable failure category.")
	_assert(programmatic_game.last_new_campaign_failure_text() == "Nie udało się rozpocząć nowej kampanii: stan startowy nie przeszedł kontroli poprawności. Nie utworzono kampanii.", "Candidate validation failure should use the exact no-campaign product message.")
	_assert(_failed_attempt_preserved(programmatic_game, active_state_before_failure, active_scene_before_failure, active_narrative_before_failure, active_persistence_before_failure), "Candidate validation failure must preserve runtime, scene, narrative and persistence mode.")

	SaveManager.fail_next_save_for_tests(ERR_CANT_CREATE)
	_assert(not programmatic_game.start_new_campaign("standard", 8082, true, false, true), "A controlled persistence failure after successful setup should return false.")
	_assert(programmatic_game.last_new_campaign_failure == int(failure_codes.get("PERSISTENCE", -1)), "The active-runtime storage failure should retain the persistence category.")
	_assert(programmatic_game.last_new_campaign_failure_text() == "Nie udało się rozpocząć nowej kampanii: nie udało się bezpiecznie zapisać zmian. Nie utworzono kampanii.", "Persistence failure should use the exact no-campaign product message.")
	_assert(_failed_attempt_preserved(programmatic_game, active_state_before_failure, active_scene_before_failure, active_narrative_before_failure, active_persistence_before_failure), "Persistence failure must preserve runtime, scene, narrative and persistence mode.")
	_assert(SaveManager.load_game() == null and not SaveManager.has_any_save_file(), "A pre-transaction storage failure must not publish files for the detached candidate.")

	_assert(programmatic_game.start_new_campaign("standard", 8083, true, false), "The default public API should persist a new campaign through the replacement transaction.")
	var first_default_persisted_id := str(programmatic_game.game_state.campaign_id)
	_assert(_all_storage_candidates_match(programmatic_game.game_state), "The first default persisted start must publish the exact canonical runtime snapshot to every valid copy.")
	SaveManager.miss_next_load_for_tests()
	_assert(programmatic_game.start_new_campaign("standard", 8084, true, false), "The default public API must safely replace an existing campaign without a special flag.")
	_assert(str(programmatic_game.game_state.campaign_id) != first_default_persisted_id, "Default programmatic replacement should publish a genuinely new campaign identity.")
	_assert(SaveManager.load_game() == null, "A forced post-commit disk-read miss must remain pending, proving GameRoot used the transaction's canonical handoff instead of adding a fallible second read.")
	_assert(programmatic_game.last_new_campaign_failure == int(failure_codes.get("NONE", 0)), "A post-commit read fault outside the transaction must not turn an already committed campaign into a false failure.")
	_assert(_all_storage_candidates_match(programmatic_game.game_state), "Default programmatic replacement must not leave the old campaign in any valid namespace candidate.")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(TEST_PENDING)), "Default successful replacement should clean its pending candidate.")
	var runtime_before_in_doubt = programmatic_game.game_state
	var scene_before_in_doubt = programmatic_game.current_scene
	var persistence_before_in_doubt: bool = programmatic_game.campaign_persistence_enabled
	programmatic_game.set("_seen_narrative_keys", {"preserved_in_doubt_fixture": true})
	programmatic_game.set("_narrative_sync_queued", true)
	var narrative_before_in_doubt: Dictionary = programmatic_game.get("_seen_narrative_keys").duplicate(true)
	SaveManager.fail_next_campaign_replacement_for_tests(SaveManager.REPLACE_STEP_PRIMARY_COMMIT_INVALID_TARGET, ERR_CANT_CREATE)
	SaveManager.fail_next_campaign_replacement_for_tests(SaveManager.REPLACE_STEP_RECONCILE_REWRITE_NEW, ERR_CANT_CREATE)
	SaveManager.fail_next_campaign_replacement_for_tests(SaveManager.REPLACE_STEP_RECONCILE_RESTORE_OLD, ERR_CANT_CREATE)
	SaveManager.fail_next_campaign_replacement_for_tests(SaveManager.REPLACE_STEP_RECONCILE_REMOVE_PRIMARY, ERR_CANT_CREATE)
	_assert(not programmatic_game.start_new_campaign("standard", 8085, true, false), "An irreconcilable multi-operation storage fault must not be reported as a normal campaign success.")
	_assert(programmatic_game.last_new_campaign_failure == int(failure_codes.get("PERSISTENCE_IN_DOUBT", -1)), "An unconfirmed disk outcome must expose the dedicated machine-readable IN_DOUBT category.")
	_assert(programmatic_game.last_new_campaign_failure_text() == "Nie udało się jednoznacznie ustalić wyniku zapisu nowej kampanii. KONTYNUUJ zostało wyłączone; ponów NOWĄ GRĘ, aby bezpiecznie uzgodnić zapis.", "An unconfirmed disk outcome must never claim that the previous campaign remained unchanged.")
	_assert(not SaveManager.has_save(), "IN_DOUBT must disable Continue in the current process instead of selecting an unconfirmed fallback.")
	_assert(FileAccess.file_exists(ProjectSettings.globalize_path(TEST_REPLACEMENT_GUARD)), "IN_DOUBT must leave a durable replacement guard in the campaign namespace.")
	_assert(_failed_attempt_preserved(programmatic_game, runtime_before_in_doubt, scene_before_in_doubt, narrative_before_in_doubt, persistence_before_in_doubt), "IN_DOUBT must preserve the active runtime while refusing to make a false disk-state promise.")
	SaveManager.last_replacement_outcome = SaveManager.CampaignReplacementOutcome.NONE
	_assert(SaveManager.load_game() == null and not SaveManager.has_save(), "Losing volatile diagnostics across a simulated restart must not bypass the durable IN_DOUBT guard.")
	_assert(not programmatic_game.continue_campaign(), "The public Continue boundary must reject a durable IN_DOUBT namespace even when called outside the UI.")
	_assert(_failed_attempt_preserved(programmatic_game, runtime_before_in_doubt, scene_before_in_doubt, narrative_before_in_doubt, persistence_before_in_doubt), "Rejected programmatic Continue must not mutate runtime while replacement is unresolved.")
	var restarted_menu_game = GameRootScene.instantiate()
	add_child(restarted_menu_game)
	await _frames(2)
	var restarted_menu = restarted_menu_game.current_scene
	var restarted_continue := restarted_menu.find_child("ContinueButton", true, false) as Button if restarted_menu != null else null
	var restarted_status := restarted_menu.find_child("StatusLabel", true, false) as Label if restarted_menu != null else null
	var restarted_new_game := restarted_menu.find_child("NewGameButton", true, false) as Button if restarted_menu != null else null
	var in_doubt_text := "Nie udało się jednoznacznie ustalić wyniku zapisu nowej kampanii. KONTYNUUJ zostało wyłączone; ponów NOWĄ GRĘ, aby bezpiecznie uzgodnić zapis."
	_assert(restarted_menu != null and restarted_menu.name == "MainMenu", "A fresh GameRoot with a durable guard must still mount the real main menu.")
	_assert(restarted_continue != null and restarted_continue.disabled, "A fresh menu must keep Continue disabled while the durable guard exists.")
	_assert(restarted_status != null and restarted_status.text == in_doubt_text and not restarted_status.text.contains("nieprawidłowe dane"), "A fresh menu must report IN_DOUBT truth, not mislabel an exact guarded snapshot as invalid data.")
	if restarted_new_game != null:
		restarted_new_game.pressed.emit()
	await _frames(2)
	var restarted_confirmation := restarted_menu.find_child("NewGameConfirmation", true, false) as ConfirmationDialog if restarted_menu != null else null
	_assert(restarted_confirmation != null and restarted_confirmation.visible, "A guarded restart must require confirmation before retrying New Game.")
	_assert(restarted_confirmation != null and restarted_confirmation.dialog_text == in_doubt_text and not restarted_confirmation.dialog_text.contains("nieprawidłowe dane"), "Guarded restart confirmation must describe IN_DOUBT, not invalid storage.")
	restarted_menu_game.queue_free()
	await _frames(3)
	# The restart fixture intentionally advances frames, so any narrative sync
	# already queued by the earlier successful scene mount may finish here. Capture
	# a fresh sentinel immediately before the guarded preflight retries; those
	# retries themselves must not mutate this runtime baseline.
	var guarded_retry_state = programmatic_game.game_state
	var guarded_retry_scene = programmatic_game.current_scene
	var guarded_retry_persistence: bool = programmatic_game.campaign_persistence_enabled
	programmatic_game.set("_seen_narrative_keys", {"preserved_guarded_retry_fixture": true})
	programmatic_game.set("_narrative_sync_queued", true)
	var guarded_retry_narrative: Dictionary = programmatic_game.get("_seen_narrative_keys").duplicate(true)
	var guarded_map_error := "guarded retry map failure"
	programmatic_game.use_next_new_campaign_map_compiler_for_tests(FailingMapCompiler.new(PackedStringArray([guarded_map_error])))
	_assert(not programmatic_game.start_new_campaign("standard", 80851, true, false), "A retry that fails map preflight must not hide the durable unresolved replacement.")
	_assert(programmatic_game.last_new_campaign_failure == int(failure_codes.get("PERSISTENCE_IN_DOUBT", -1)), "Map-preflight failure during a guarded retry must retain the IN_DOUBT category.")
	_assert(programmatic_game.last_new_campaign_failure_details.has(guarded_map_error), "Map-preflight diagnostics must remain available beneath the overriding IN_DOUBT category.")
	_assert(programmatic_game.last_new_campaign_failure_text() == "Nie udało się jednoznacznie ustalić wyniku zapisu nowej kampanii. KONTYNUUJ zostało wyłączone; ponów NOWĄ GRĘ, aby bezpiecznie uzgodnić zapis.", "A guarded map-preflight failure must keep the exact fail-closed player message.")
	_assert(FileAccess.file_exists(ProjectSettings.globalize_path(TEST_REPLACEMENT_GUARD)) and SaveManager.load_game() == null and not SaveManager.has_save(), "Map-preflight failure during retry must leave the guard and read barriers intact.")
	_assert(_failed_attempt_preserved(programmatic_game, guarded_retry_state, guarded_retry_scene, guarded_retry_narrative, guarded_retry_persistence), "Guarded map-preflight failure must preserve runtime, scene, narrative and persistence mode.")
	programmatic_game.use_next_new_campaign_map_compiler_for_tests(InvalidCandidateMapCompiler.new())
	_assert(not programmatic_game.start_new_campaign("standard", 80852, true, false), "A retry with an invalid detached candidate must not hide the durable unresolved replacement.")
	_assert(programmatic_game.last_new_campaign_failure == int(failure_codes.get("PERSISTENCE_IN_DOUBT", -1)), "Candidate-validation failure during a guarded retry must retain the IN_DOUBT category.")
	_assert(not programmatic_game.last_new_campaign_failure_details.is_empty(), "Candidate-validation diagnostics must remain available beneath the overriding IN_DOUBT category.")
	_assert(programmatic_game.last_new_campaign_failure_text() == "Nie udało się jednoznacznie ustalić wyniku zapisu nowej kampanii. KONTYNUUJ zostało wyłączone; ponów NOWĄ GRĘ, aby bezpiecznie uzgodnić zapis.", "A guarded candidate-validation failure must keep the exact fail-closed player message.")
	_assert(SaveManager.save_game(runtime_before_in_doubt) == ERR_BUSY, "Autosave must remain blocked after preflight-only retry failures while the durable guard exists.")
	_assert(FileAccess.file_exists(ProjectSettings.globalize_path(TEST_REPLACEMENT_GUARD)) and SaveManager.load_game() == null and not SaveManager.has_save(), "Candidate-validation failure during retry must leave the guard and read barriers intact.")
	_assert(_failed_attempt_preserved(programmatic_game, guarded_retry_state, guarded_retry_scene, guarded_retry_narrative, guarded_retry_persistence), "Guarded candidate-validation failure must preserve runtime, scene, narrative and persistence mode.")
	SaveManager.fail_next_save_for_tests(ERR_CANT_CREATE)
	_assert(not programmatic_game.start_new_campaign("standard", 8086, true, false), "A failed retry must not be promoted to a resolved replacement.")
	_assert(programmatic_game.last_new_campaign_failure == int(failure_codes.get("PERSISTENCE_IN_DOUBT", -1)), "A failed retry must retain the machine-readable IN_DOUBT category.")
	_assert(FileAccess.file_exists(ProjectSettings.globalize_path(TEST_REPLACEMENT_GUARD)) and SaveManager.load_game() == null and not SaveManager.has_save(), "A failed retry must keep the durable guard and all Continue boundaries closed.")
	_assert(programmatic_game.start_new_campaign("standard", 8087, true, false), "Retrying New Game must reconcile an IN_DOUBT namespace into one exact new campaign.")
	_assert(SaveManager.has_save() and _all_storage_candidates_match(programmatic_game.game_state), "Successful retry after IN_DOUBT must restore Continue and leave only the exact canonical campaign.")
	_assert(not FileAccess.file_exists(ProjectSettings.globalize_path(TEST_REPLACEMENT_GUARD)), "Only a verified successful retry may clear the durable replacement guard.")
	_assert(programmatic_game.start_new_campaign("standard", 809, false, true), "A programmatic caller should be able to opt into intro explicitly.")
	await _frames(3)
	var natural_intro = programmatic_game.current_scene
	_assert(natural_intro != null and natural_intro.name == "IntroScene", "Explicit intro opt-in should show IntroScene.")
	if natural_intro != null:
		var natural_player := natural_intro.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_assert(natural_player != null, "Intro should use AnimationPlayer as its authoritative clock.")
		if natural_player != null:
			var intro_animation := natural_player.get_animation(&"intro")
			_assert(intro_animation != null and is_equal_approx(intro_animation.length, INTRO_PREMIX_LENGTH_SECONDS), "The authoritative visual timeline should preserve the same 45-second authored duration.")
			var natural_premix_player := natural_intro.find_child("AmbientPlayer", true, false) as AudioStreamPlayer
			if natural_premix_player != null:
				natural_premix_player.stop()
				natural_premix_player.stream = null
			natural_player.speed_scale = 1000.0
	await _frames(12)
	_assert(programmatic_game.current_scene != null and programmatic_game.current_scene.name == "BaseScene", "The natural animation end should use the same safe handoff as skip even when the premix is unavailable.")

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
	print("Intro flow test passed: text-only prerendered intro, fixed rain-and-music premix, deterministic beats, skip and continue are safe.")
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


func _storage_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for path in [TEST_SAVE, TEST_PENDING, TEST_BACKUP]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes


func _all_storage_candidates_match(expected) -> bool:
	var canonical = SaveManager.load_game()
	if canonical == null or str(canonical.campaign_id) != str(expected.campaign_id):
		return false
	if not bool(SaveManager.call("_same_campaign_snapshot_identity", canonical, expected)):
		return false
	var valid_count := 0
	for path in [TEST_SAVE, TEST_PENDING, TEST_BACKUP]:
		if not ResourceLoader.exists(path):
			continue
		var loaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if loaded == null or loaded.get_script() != GameStateScript:
			return false
		var errors: PackedStringArray = loaded.load_validation_errors()
		if not errors.is_empty():
			return false
		valid_count += 1
		if not bool(SaveManager.call("_same_campaign_snapshot_identity", loaded, expected)):
			return false
	return valid_count > 0


func _failed_attempt_preserved(game, expected_state, expected_scene, expected_narrative: Dictionary, expected_persistence: bool) -> bool:
	return (
		game.game_state == expected_state
		and game.current_scene == expected_scene
		and game.campaign_persistence_enabled == expected_persistence
		and game.get("_seen_narrative_keys") == expected_narrative
		and bool(game.get("_narrative_sync_queued"))
	)


func _remove_test_saves() -> void:
	for path in [TEST_SAVE, TEST_PENDING, TEST_BACKUP, TEST_REPLACEMENT_GUARD]:
		var absolute_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute_path):
			DirAccess.remove_absolute(absolute_path)
