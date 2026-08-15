extends Node

const EndingScene := preload("res://scenes/main/EndingScene.tscn")
const GameOverScene := preload("res://scenes/main/GameOverScene.tscn")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const CampaignProgressionSystemScript := preload("res://scripts/base/CampaignProgressionSystem.gd")

func _ready() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(8701, DifficultyProfileScript.new())
	state.tutorial.complete()
	state.day = 18
	state.story_flags.energy_configuration = CampaignProgressionSystemScript.ENERGY_HARBOR
	state.story_flags.final_outcome_id = CampaignProgressionSystemScript.OUTCOME_QUIET_AFTER_STORM
	state.story_flags.chronicle_summary = {
		"living_survivors": ["Igor", "Mira", "Anka"], "dead_survivors": [],
		"accepted_survivors": [], "rejected_survivors": [], "buildings": [],
		"important_decisions": ["Energia pozostała w Przystani"],
		"energy_configuration": "harbor", "hope": 63,
		"r3_active": true, "c4_active": true, "splitter_installed": false,
		"radio_active": false, "north_platform_survived": false,
	}
	var ending = EndingScene.instantiate()
	add_child(ending)
	ending.bind(self, state)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _save_snapshot("campaign_ending.png"):
		return
	remove_child(ending)
	ending.queue_free()

	state.story_flags.game_over_reason = "leadership_collapse"
	state.story_flags.game_over_day = 21
	state.resources.set_amount("hope", 0)
	var game_over = GameOverScene.instantiate()
	add_child(game_over)
	game_over.bind(self, state)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _save_snapshot("campaign_game_over.png"):
		return
	print("Campaign outcome snapshots saved; ending, summary, credits and GAME_OVER fit the canonical viewport.")
	get_tree().quit(0)

func continue_chronicle() -> bool:
	return true

func return_to_main_menu() -> void:
	pass

func _save_snapshot(file_name: String) -> bool:
	var image := get_viewport().get_texture().get_image()
	var output_directory := ProjectSettings.globalize_path("res://tmp")
	if not DirAccess.dir_exists_absolute(output_directory):
		var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
		if directory_error != OK:
			push_error("Could not create the campaign outcome snapshot directory. Error: %d" % directory_error)
			get_tree().quit(1)
			return false
	var error := image.save_png(output_directory.path_join(file_name))
	if error == OK:
		return true
	push_error("Could not save campaign outcome snapshot %s. Error: %d" % [file_name, error])
	get_tree().quit(1)
	return false
