extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const MUSIC_PATH := "res://assets/audio/base/oddech_przystani.ogg"
const EXPECTED_LENGTH_SECONDS := 225.0
const EXPECTED_BPM := 64.0
const EXPECTED_BEAT_COUNT := 240

var _failed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var game = GameRootScene.instantiate()
	# The test harness must keep running while paused, but the production tree must
	# retain its normal pausable inheritance. PauseMenu overrides this for itself.
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	await _frames(3)

	var settings: Dictionary = game.user_settings.snapshot()
	settings["graphics"] = {"quality": "low"}
	_assert(game.user_settings.apply(settings, false) == OK, "The Base music flow should seed the low graphics profile before opening the real Base scene.")
	_assert(game.start_new_campaign("standard", 260809, false, false), "The production GameRoot should start an unsaved campaign directly in Base.")
	await _frames(5)

	_assert(game.current_scene != null and game.current_scene.name == "BaseScene", "The production flow should mount BaseScene.")
	var first_player := _assert_single_music_player(game.current_scene)
	await _frames(2)
	_assert(first_player != null and first_player.playing, "Base music autoplay should start after the scene enters the tree.")
	# The restored opening dialogue intentionally owns cancel input. This fixture
	# isolates Base-scoped music and pause semantics, so remove only its presenter
	# before opening the production pause menu.
	if game.narrative_dialogue_panel != null:
		game.narrative_dialogue_panel.clear()
		await _frames(2)

	if first_player != null:
		var position_before_pause := first_player.get_playback_position()
		_assert(game.open_pause_menu(), "The real Base flow should open its pause menu.")
		await get_tree().create_timer(0.12, true).timeout
		var position_during_pause := first_player.get_playback_position()
		_assert(get_tree().paused, "Opening Base pause should pause the scene tree.")
		_assert(not first_player.can_process(), "The local music player should inherit the paused process state instead of playing under the pause menu.")
		_assert(absf(position_during_pause - position_before_pause) <= 0.04, "The Base music position should not advance materially while the scene tree is paused.")

		game.pause_menu.continue_requested.emit()
		await _frames(2)
		_assert(not get_tree().paused and first_player.can_process(), "Continuing should restore processing for the same local player.")
		await get_tree().create_timer(0.12, true).timeout
		_assert(first_player.get_playback_position() > position_during_pause + 0.04, "Base music should resume from its paused position after continuing.")

	var first_player_ref: WeakRef = weakref(first_player) if first_player != null else null
	game.show_main_menu()
	await _frames(3)
	_assert(game.current_scene != null and game.current_scene.name == "MainMenu", "Leaving Base should replace it with the main menu.")
	_assert(game.current_scene.find_children("BaseMusicPlayer", "AudioStreamPlayer", true, false).is_empty(), "Music scoped to Base must not survive in the main-menu scene.")
	if first_player_ref != null:
		_assert(first_player_ref.get_ref() == null, "Replacing SceneMount should free the previous Base music player.")

	game.show_base()
	await _frames(5)
	var second_player := _assert_single_music_player(game.current_scene)
	_assert(second_player != null and second_player.playing, "Returning to Base should create one fresh playing music instance.")

	if second_player != null:
		second_player.stop()
	var game_ref: WeakRef = weakref(game)
	game.queue_free()
	game = null
	first_player = null
	second_player = null
	first_player_ref = null
	await _frames(3)
	await get_tree().create_timer(0.1).timeout
	_assert(game_ref.get_ref() == null, "The Base music fixture must release its complete GameRoot tree before exit.")
	if get_tree().paused:
		get_tree().paused = false
	if _failed:
		get_tree().quit(1)
		return
	print("Base music test passed: the 48 kHz Ogg loops on Master, autoplays in Base, inherits pause and remains scoped to each BaseScene instance.")
	get_tree().quit(0)


func _assert_single_music_player(scene: Node) -> AudioStreamPlayer:
	_assert(scene != null, "A mounted scene is required to inspect Base music.")
	if scene == null:
		return null
	var players := scene.find_children("BaseMusicPlayer", "AudioStreamPlayer", true, false)
	_assert(players.size() == 1, "Each BaseScene should contain exactly one BaseMusicPlayer.")
	if players.size() != 1:
		return null
	var player := players[0] as AudioStreamPlayer
	_assert(player != null, "BaseMusicPlayer should be a non-positional AudioStreamPlayer.")
	if player == null:
		return null
	_assert(player.bus == &"Master", "Base music should use the project's one real Master bus.")
	_assert(player.autoplay, "Base music should be configured for autoplay.")
	_assert(is_equal_approx(player.volume_db, -1.5), "Base music should preserve the authored presentation gain.")
	var stream := player.stream as AudioStreamOggVorbis
	_assert(stream != null, "BaseMusicPlayer should load the Ogg Vorbis runtime asset.")
	if stream != null:
		_assert(stream.resource_path == MUSIC_PATH, "Base music should resolve the approved authored asset.")
		_assert(stream.has_loop(), "The imported Ogg stream should loop in Godot.")
		_assert(is_zero_approx(stream.loop_offset), "The complete file should loop from sample zero without a one-shot intro.")
		_assert(absf(stream.get_length() - EXPECTED_LENGTH_SECONDS) <= 0.02, "The runtime loop should preserve its exact 60-bar duration.")
		_assert(is_equal_approx(stream.bpm, EXPECTED_BPM), "The imported stream should preserve the authored 64 BPM grid.")
		_assert(stream.beat_count == EXPECTED_BEAT_COUNT, "The imported stream should preserve 60 bars of four beats.")
	return player


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
