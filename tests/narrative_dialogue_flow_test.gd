extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const GameFormatScript := preload("res://scripts/data/GameFormat.gd")
const NarrativeAudioCatalogScript := preload("res://scripts/ui/NarrativeAudioCatalog.gd")
const NarrativeContentScript := preload("res://scripts/ui/NarrativeContent.gd")
const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const TutorialDirectorScript := preload("res://scripts/core/TutorialDirector.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")

const TEST_VIEWPORT_SIZES := [Vector2(720, 540), Vector2(1280, 720)]

var _failed := false
var _cue_events: Array[Dictionary] = []
var _dismissed_keys: Array[String] = []


func _ready() -> void:
	var game = GameRootScene.instantiate()
	add_child(game)
	await _frames(2)
	_assert(game.start_new_campaign("standard", 1707, false), "Fixture must start a campaign without persistence.")
	await _frames(4)

	var panel: Control = game.narrative_dialogue_panel
	panel.cue_started.connect(_on_narrative_cue_started)
	panel.dismissed.connect(_on_narrative_dismissed)
	_assert_audio_catalog_contract()
	_assert(game.current_scene != null and game.current_scene.name == "BaseScene", "A programmatic campaign must enter BaseScene.")
	_assert(panel != null and panel.is_open(), "The first important story transition must open a Base conversation.")
	_assert(panel.message_key() == "tutorial_dialogue_day_1", "The first conversation must derive from the day-one tutorial transition.")
	_assert(panel.line_count() == 4 and panel.line_index() == 0, "The day-one conversation must expose one stage direction followed by three dialogue lines.")
	_assert(game.current_scene.process_mode != Node.PROCESS_MODE_DISABLED, "The Base scene must keep processing under story dialogue.")
	_assert_scene_context(panel, "DZIEŃ 1  •  PRZYSTAŃ  •  PIERWSZY PORANEK", "day-one tutorial")
	_assert_non_dialogue_presentation(panel, "stage_direction", "the opening tutorial beat")
	_assert(_label_text(panel, "NarrativeTitleLabel") == "PIERWSZY DACH", "The panel must use the shared conversation title.")
	_assert(_label_text(panel, "NarrativeBodyLabel").contains("Deszcz") and _label_text(panel, "NarrativeBodyLabel").contains("Troje ocalałych"), "The first tutorial beat must establish what is happening before anyone speaks.")
	var continue_button := panel.find_child("NarrativeContinueButton", true, false) as Button if panel != null else null
	_assert(continue_button != null and continue_button.has_focus(), "DALEJ must receive keyboard focus when a conversation opens.")
	await _assert_current_line_fits_viewports(panel, "day-one opening stage direction")

	var environment = game.current_scene.find_child("BaseEnvironment", true, false)
	var elapsed_before := float(environment.get("_elapsed")) if environment != null else -1.0
	await _frames(5)
	var elapsed_after := float(environment.get("_elapsed")) if environment != null else -1.0
	_assert(environment != null and elapsed_after > elapsed_before, "Ocean, rain and platform presentation must keep advancing under the modal dialogue.")

	await _press_key(KEY_ENTER)
	_assert(panel.is_open() and panel.line_index() == 1, "ui_accept bound to Enter must advance exactly one line instead of closing the whole conversation.")
	_assert_dialogue_speaker(panel, "Mira Boruta", "left", "Mira's opening tutorial line")
	_assert(_label_text(panel, "NarrativeBodyLabel").contains("suchy dach"), "Mira's first line must turn the established scene into a concrete need.")
	_assert(_portrait_alpha(panel, "NarrativePortraitFrameLeft") > 0.99 and _portrait_alpha(panel, "NarrativePortraitFrameRight") < 0.01, "Only Mira's current left portrait may be visible.")
	var left_portrait = panel.find_child("NarrativePortraitLeft", true, false) if panel != null else null
	_assert(left_portrait != null and str(left_portrait.get("survivor_id")) == "mira", "The left slot must use Mira's shared SurvivorPortrait asset.")
	_assert(left_portrait != null and not bool(left_portrait.get("mirrored_horizontally")), "The left portrait must preserve the authored orientation.")
	await _assert_current_line_fits_viewports(panel, "Mira's day-one opening line")

	panel.advance()
	await _frames(1)
	_assert(panel.is_open() and panel.line_index() == 2, "The next tutorial beat must remain in the same conversation.")
	_assert_dialogue_speaker(panel, "Anka Ryl", "right", "Anka's day-one response")
	_assert(_portrait_alpha(panel, "NarrativePortraitFrameLeft") < 0.01 and _portrait_alpha(panel, "NarrativePortraitFrameRight") > 0.99, "Only Anka's current right portrait may be visible.")
	var right_portrait = panel.find_child("NarrativePortraitRight", true, false) if panel != null else null
	_assert(right_portrait != null and str(right_portrait.get("survivor_id")) == "anka", "The right slot must use Anka's shared SurvivorPortrait asset.")
	_assert(right_portrait != null and bool(right_portrait.get("mirrored_horizontally")), "The right portrait must mirror horizontally so both speakers face the conversation center.")
	await _assert_current_line_fits_viewports(panel, "Anka's day-one response")

	panel.advance()
	await _frames(1)
	_assert(panel.is_open() and panel.line_index() == 3, "The final day-one line must remain visible until separately advanced.")
	_assert_dialogue_speaker(panel, "Mira Boruta", "left", "Mira's final day-one line")
	await _assert_current_line_fits_viewports(panel, "Mira's final day-one line")
	panel.advance()
	await _frames(2)
	_assert(not panel.is_open(), "Only the final line may close the conversation.")
	_assert(game.game_state.tutorial.step == TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE, "Closing dialogue must never complete the tutorial action.")
	_assert(_label_text(game.current_scene, "TutorialBody") == _objective_body(TutorialStateScript.Step.BUILD_COMMUNITY_HOUSE), "The compact Base HUD must retain the exact mechanical objective.")

	_assert(game.tutorial_event(TutorialDirectorScript.BUILDING_COMPLETED, "community_house"), "A real domain event must advance the tutorial.")
	await _frames(2)
	_assert(not panel.is_open(), "Minor Base tutorial steps must not open another story window.")

	game.game_state.tutorial.step = TutorialStateScript.Step.BUILD_WORKSHOP
	game.game_state.day = 2
	game.game_state.current_phase = GamePhaseScript.Phase.END_DAY_REPORT
	game._sync_narrative_presenter()
	await _frames(2)
	_assert(not panel.is_open(), "The day-two story conversation must never appear over END_DAY_REPORT.")
	_assert(game.acknowledge_day_report(), "The report acknowledgement must enter day-two planning.")
	await _frames(3)
	_assert(panel.is_open() and panel.message_key() == "tutorial_dialogue_day_2", "The day-two conversation must open only after the report acknowledgement.")
	_assert(panel.line_count() == 5, "The day-two scene must contain its stage direction and four alternating speakers.")
	_assert_scene_context(panel, "DZIEŃ 2  •  PRZYSTAŃ  •  STÓŁ WARSZTATOWY", "day-two tutorial")
	_assert_non_dialogue_presentation(panel, "stage_direction", "the day-two opening beat")
	_assert(_label_text(panel, "NarrativeBodyLabel").contains("martwą tablicę elektryczną") and _label_text(panel, "NarrativeBodyLabel").contains("czarny kabel"), "The day-two stage direction must establish the canonical physical evidence.")
	await _assert_current_line_fits_viewports(panel, "day-two opening stage direction")
	panel.advance()
	await _frames(1)
	await _consume_expected_dialogue_lines(panel, "day-two conversation", [
		{"name": "Anka Ryl", "side": "left"},
		{"name": "Igor Sowa", "side": "right"},
		{"name": "Anka Ryl", "side": "left"},
		{"name": "Igor Sowa", "side": "right"},
	])
	await _frames(2)
	_assert(not panel.is_open(), "The day-two conversation must close after all four speakers.")

	game.game_state.tutorial.step = TutorialStateScript.Step.STAFF_WORKSHOP
	game.game_state.current_phase = GamePhaseScript.Phase.DAY_START_REPORT
	game._sync_narrative_presenter()
	await _frames(2)
	_assert(not panel.is_open(), "A pending morning-report phase must keep the day-three conversation closed.")
	game.game_state.current_phase = GamePhaseScript.Phase.BASE_PLANNING
	game._sync_narrative_presenter()
	await _frames(2)
	_assert(panel.is_open() and panel.message_key() == "tutorial_dialogue_day_3", "The day-three conversation must open after all mandatory reports are closed.")
	_assert(panel.line_count() == 5, "The day-three scene must contain its stage direction and four alternating speakers.")
	_assert_scene_context(panel, "DZIEŃ 3  •  PRZYSTAŃ  •  PO POWROCIE", "day-three tutorial")
	_assert_non_dialogue_presentation(panel, "stage_direction", "the day-three opening beat")
	_assert(_label_text(panel, "NarrativeBodyLabel").contains("kawałek grubej, czarnej sieci"), "The day-three stage direction must show the obstruction Igor recovered.")
	await _assert_current_line_fits_viewports(panel, "day-three opening stage direction")
	panel.advance()
	await _frames(1)
	await _consume_expected_dialogue_lines(panel, "day-three conversation", [
		{"name": "Igor Sowa", "side": "left"},
		{"name": "Anka Ryl", "side": "right"},
		{"name": "Igor Sowa", "side": "left"},
		{"name": "Anka Ryl", "side": "right"},
	])
	await _frames(2)
	_assert(not panel.is_open(), "The day-three conversation must close after all four speakers.")

	game.game_state.tutorial.step = TutorialStateScript.Step.ACTIVATE_JUNCTION_J7
	game.game_state.current_phase = GamePhaseScript.Phase.DIVING
	game.game_state.current_expedition_setup = _make_tutorial_setup()
	game._load_scene(preload("res://scenes/diving/DiveScene.tscn"))
	await _frames(4)
	_assert(not panel.is_open(), "Story dialogue must never open during a dive.")
	var dive_objective := _label_text(game.current_scene, "DiveTutorialBody")
	_assert(dive_objective.contains("Powrót jest zablokowany przy głównej linie"), "The dive HUD must retain the explicit return blocker without a story window.")
	_assert(dive_objective.contains("Węźle J-7") and dive_objective.contains("przytrzymaj"), "The dive HUD must retain the exact J-7 action.")

	game.game_state.tutorial.complete()
	_configure_story_speaker_buildings(game.game_state)
	game.game_state.story_flags.junction_j7_active = true
	game.game_state.story_flags.black_front_active = true
	game.game_state.story_flags.black_front_days_remaining = 12
	game.game_state.current_phase = GamePhaseScript.Phase.END_DAY_REPORT
	game.show_base(true)
	await _frames(4)
	_assert(not panel.is_open(), "The J-7 debrief must wait behind the completed-day report.")
	_cue_events.clear()
	_assert(game.acknowledge_day_report(), "Acknowledging the post-J-7 report must enter Base planning.")
	await _frames(3)
	_assert(panel.is_open() and panel.message_key() == "story_j7_first_contact", "The first post-J-7 Base presentation must be one continuous first-contact scene.")
	_assert(panel.line_count() == 6, "The combined J-7 scene must fit the restored-power beat and five dialogue lines in one window.")
	_assert_scene_context(panel, "PRZYSTAŃ  •  DOM WSPÓLNOTY  •  PO POWROCIE Z J-7", "combined J-7 first contact")
	_assert_non_dialogue_presentation(panel, "stage_direction", "the combined J-7 opening beat")
	var j7_opening := _label_text(panel, "NarrativeBodyLabel").to_lower()
	_assert(j7_opening.contains("główny bezpiecznik") and j7_opening.contains("zapalają się lampy") and j7_opening.contains("moduł radiowy") and j7_opening.contains("szum obcego kanału"), "The combined J-7 opening must show power returning and immediately turn it into first contact without implying voice-over.")
	_assert_conversation_cue_contract(
		_conversation_for_key(NarrativeContentScript.story_conversations(game.game_state), "story_j7_first_contact"),
		[
			NarrativeAudioCatalogScript.CUE_LINE_ENGAGE,
			NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_OPEN,
			"",
			NarrativeAudioCatalogScript.CUE_PUMPS_EMERGENCY,
			"",
			"",
		],
		"combined J-7 first contact"
	)
	_assert_current_cue(panel, "story_j7_first_contact", 0, NarrativeAudioCatalogScript.CUE_LINE_ENGAGE, 1, "J-7 power return")
	var base_music := game.current_scene.find_child("BaseMusicPlayer", true, false) as AudioStreamPlayer
	_assert(base_music != null, "The J-7 cue test needs BaseScene's local music player.")
	var base_music_nominal := float(game.current_scene.get("_base_music_nominal_volume_db"))
	await _assert_current_line_fits_viewports(panel, "combined J-7 opening stage direction")
	_assert(_cue_events.size() == 1, "Responsive layout must not replay the J-7 power cue.")
	await get_tree().create_timer(0.25).timeout
	_assert(base_music == null or absf(base_music.volume_db - (base_music_nominal - 3.5)) < 0.15, "A playing narrative cue must locally duck Base music by 3.5 dB without changing Master.")
	panel.advance()
	await _frames(1)
	_assert_dialogue_speaker(panel, "Klara Wysocka", "right", "Klara's first transmission")
	_assert_current_cue(panel, "story_j7_first_contact", 1, NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_OPEN, 2, "J-7 radio channel")
	var klara_portrait = panel.find_child("NarrativePortraitRight", true, false)
	_assert(klara_portrait != null and str(klara_portrait.get("survivor_id")) == "klara", "Klara's response must use her dedicated portrait asset.")
	await _assert_current_line_fits_viewports(panel, "Klara's first transmission")
	panel.advance()
	await _frames(1)
	_assert_dialogue_speaker(panel, "Mira Boruta", "left", "Mira's first-contact reply")
	_assert_silent_current_line(panel, 2, "Mira's J-7 identification")
	_assert(_cue_events.size() == 2, "A line without cue_id must not emit a replacement sound event.")
	await get_tree().create_timer(0.25).timeout
	_assert(base_music == null or absf(base_music.volume_db - base_music_nominal) < 0.15, "Intentional narrative silence must restore Base music to its authored level.")
	await _assert_current_line_fits_viewports(panel, "Mira's first-contact reply")
	panel.advance()
	await _frames(1)
	_assert_dialogue_speaker(panel, "Klara Wysocka", "right", "Klara's emergency-power warning")
	_assert_current_cue(panel, "story_j7_first_contact", 3, NarrativeAudioCatalogScript.CUE_PUMPS_EMERGENCY, 3, "J-7 emergency pumps")
	var emergency_warning := _label_text(panel, "NarrativeBodyLabel").to_lower()
	_assert(emergency_warning.contains("pompy") and emergency_warning.contains("zasilanie awaryjne"), "First contact must explain that the North Platform pumps fell back to emergency power.")
	await _assert_current_line_fits_viewports(panel, "Klara's emergency-power warning")
	panel.advance()
	await _frames(1)
	_assert_dialogue_speaker(panel, "Mira Boruta", "left", "Mira's first-contact dilemma")
	_assert_silent_current_line(panel, 4, "J-7 moral dilemma")
	var harbor_dilemma := _label_text(panel, "NarrativeBodyLabel").to_lower()
	_assert(harbor_dilemma.contains("bez światła i łączności") and harbor_dilemma.contains("zabieramy wam czas"), "The combined scene must make the shared-bank cost legible before giving the player another objective.")
	await _assert_current_line_fits_viewports(panel, "Mira's first-contact dilemma")
	panel.advance()
	await _frames(1)
	_assert_dialogue_speaker(panel, "Klara Wysocka", "right", "Klara's full-integrity warning")
	_assert_silent_current_line(panel, 5, "J-7 integrity warning")
	_assert(_label_text(panel, "NarrativeBodyLabel").contains("100% integralności") and _label_text(panel, "NarrativeBodyLabel").contains("nie 99%") and _label_text(panel, "NarrativeBodyLabel").contains("Archiwum"), "First contact must state the exact 100% integrity requirement and point toward the Archive in the same scene.")
	await _assert_current_line_fits_viewports(panel, "Klara's full-integrity warning")
	panel.advance()
	await _frames(3)
	_assert(not panel.is_open(), "The combined J-7 scene must close after Klara's warning without queuing a second debrief window.")
	await _frames(2)
	_assert(not panel.is_open(), "J-7 must not reopen as a separate debrief after first contact.")

	await _assert_story_catalog_contract(game, panel)

	for survivor in game.game_state.survivors:
		survivor.status = SurvivorStateScript.Status.DEAD
	_reset_story_milestones(game.game_state.story_flags)
	game.game_state.story_flags.junction_j7_active = false
	game.game_state.story_flags.archive_map_transmitted = true
	game._sync_narrative_presenter()
	await _frames(2)
	_assert(panel.is_open() and panel.message_key() == "story_archive_transmitted", "The archive scene must still open when no living survivor can speak.")
	_assert(panel.line_count() == 5, "The archive scene must reveal the Northern Platform decision in five distinct beats.")
	_assert_conversation_cue_contract(
		NarrativeContentScript.story_message(game.game_state),
		["", NarrativeAudioCatalogScript.CUE_ARCHIVE_RELAY_READ, "", "", ""],
		"Archive reveal"
	)
	_assert_scene_context(panel, "PRZYSTAŃ  •  STÓŁ Z MAPĄ WSPÓLNEJ LINII", "archive-map scene")
	_assert_non_dialogue_presentation(panel, "world_event", "the archive-map opening event")
	_assert(_label_text(panel, "NarrativeBodyLabel").contains("jedna sieć, jeden wspólny bank"), "The Archive opening must make the shared network visible before revealing who disconnected J-7.")
	_assert_world_event_has_no_objective_copy(_label_text(panel, "NarrativeBodyLabel"), "Archive opening")
	await _assert_current_line_fits_viewports(panel, "archive-map opening event")
	panel.advance()
	await _frames(1)
	_assert_non_dialogue_presentation(panel, "stage_direction", "the Archive operator-log reveal")
	var archive_log := _label_text(panel, "NarrativeBodyLabel")
	_assert(archive_log.contains("OBSADA: 0") and archive_log.contains("POMPY PÓŁNOCNEJ") and archive_log.contains("ODŁĄCZYĆ"), "The Archive must reveal the exact operator decision instead of summarizing it as a new task.")
	await _assert_current_line_fits_viewports(panel, "Archive operator-log reveal")
	panel.advance()
	await _frames(1)
	_assert_dialogue_speaker(panel, "Klara Wysocka", "right", "Klara's Archive admission")
	_assert(_label_text(panel, "NarrativeBodyLabel").contains("nasi operatorzy") and _label_text(panel, "NarrativeBodyLabel").contains("utrzymało nasze pompy"), "Klara must personally connect the old decision to the survival of the Northern Platform.")
	await _assert_current_line_fits_viewports(panel, "Klara's Archive admission")
	panel.advance()
	await _frames(1)
	_assert_dialogue_speaker(panel, "RAPORT SYSTEMOWY", "left", "Archive neutral Harbor fallback")
	_assert(_portrait_alpha(panel, "NarrativePortraitFrameLeft") < 0.01 and _portrait_alpha(panel, "NarrativePortraitFrameRight") < 0.01, "A neutral report must not invent a character portrait.")
	var archive_fallback := _label_text(panel, "NarrativeBodyLabel")
	_assert(archive_fallback.contains("OBSADA OBECNA") and not archive_fallback.contains("A teraz jesteśmy"), "The neutral fallback must replace personal dialogue with an impersonal current-state report.")
	await _assert_current_line_fits_viewports(panel, "Archive neutral Harbor fallback")
	panel.advance()
	await _frames(1)
	_assert_dialogue_speaker(panel, "Klara Wysocka", "right", "Klara's Archive conclusion")
	_assert(_label_text(panel, "NarrativeBodyLabel").contains("Właśnie dlatego mamy problem"), "The Archive scene must end on the moral contradiction, not a mechanical objective card.")
	await _assert_current_line_fits_viewports(panel, "Klara's Archive conclusion")
	panel.advance()
	await _frames(2)
	_assert(not panel.is_open(), "The Archive scene must close after Klara names the conflict.")

	_assert_ending_catalog_contract(game.game_state)
	await _assert_c4_prelude_before_energy_choice(game, panel)
	game.game_state.story_flags.final_outcome_id = "last_bridge"
	game.game_state.story_flags.energy_choice_pending = false
	game.game_state.current_phase = GamePhaseScript.Phase.ENDING
	_cue_events.clear()
	game._route_current_phase()
	await _frames(4)
	_assert(game.current_scene != null and game.current_scene.name == "EndingScene", "A resolved campaign outcome must route to EndingScene.")
	_assert(panel.is_open() and panel.message_key() == "ending_last_bridge", "EndingScene must present the authored Last Bridge conversation through GameRoot.")
	_assert(GameFormatScript.CAMPAIGN_FORMAT_REVISION == 2, "The presentation-only conversation system must preserve the clean campaign format revision.")
	_assert(panel.line_count() == 6, "The Last Bridge ending must retain its six-beat radio cadence.")
	_assert_scene_context(panel, "WSPÓLNA LINIA  •  ŚWIT PO CZARNYM FRONCIE", "Last Bridge ending")
	var ending_types := ["world_event", "dialogue", "dialogue", "world_event", "dialogue", "stage_direction"]
	var ending_cues := [
		NarrativeAudioCatalogScript.CUE_C4_DUAL_LINE_STORM,
		NarrativeAudioCatalogScript.CUE_PUMPS_STABLE,
		"",
		NarrativeAudioCatalogScript.CUE_RADIO_DISTANT_CHANNEL,
		"",
		"",
	]
	for ending_line_index in range(ending_types.size()):
		_assert(panel.current_line_type() == str(ending_types[ending_line_index]), "Last Bridge ending line %d must preserve its authored type." % (ending_line_index + 1))
		var expected_ending_cue := str(ending_cues[ending_line_index])
		if expected_ending_cue.is_empty():
			_assert_silent_current_line(panel, ending_line_index, "Last Bridge ending line %d" % (ending_line_index + 1))
		else:
			var expected_event_count := 1
			for earlier_index in range(ending_line_index):
				if not str(ending_cues[earlier_index]).is_empty():
					expected_event_count += 1
			_assert_current_cue(panel, "ending_last_bridge", ending_line_index, expected_ending_cue, expected_event_count, "Last Bridge ending line %d" % (ending_line_index + 1))
		if panel.current_line_type() == "dialogue":
			_assert_dialogue_speaker(panel, "Klara Wysocka" if ending_line_index == 1 else "Mira Boruta", "right" if ending_line_index == 1 else "left", "Last Bridge ending line %d" % (ending_line_index + 1))
		else:
			_assert_non_dialogue_presentation(panel, panel.current_line_type(), "Last Bridge ending line %d" % (ending_line_index + 1))
		await _assert_current_line_fits_viewports(panel, "Last Bridge ending line %d" % (ending_line_index + 1))
		panel.advance()
		await _frames(1)
	_assert(not panel.is_open(), "The Last Bridge ending must close only after the distant light answers.")
	await _assert_audio_lifecycle_and_scene_swap(game, panel)

	game.queue_free()
	await _frames(3)
	if _failed:
		get_tree().quit(1)
		return
	print("Narrative dialogue flow test passed: story beats, exact non-voice cue timing, intentional silence, interruption and scene-swap cleanup remain coherent.")
	get_tree().quit(0)


func _assert_c4_prelude_before_energy_choice(game, panel: Control) -> void:
	for survivor in game.game_state.survivors:
		survivor.status = SurvivorStateScript.Status.AVAILABLE
	_reset_story_milestones(game.game_state.story_flags)
	game.game_state.day = 15
	var story = game.game_state.story_flags
	story.archive_map_transmitted = true
	story.r3_diagnosed = true
	story.r3_regulator_ready = true
	story.r3_generator_active = true
	story.r3_generator_activated_day = 12
	story.c4_switchboard_active = true
	story.c4_switchboard_activated_day = 14
	story.black_front_arrived = true
	story.energy_choice_pending = true
	game._seen_narrative_keys.erase("story_c4_active")
	game.game_state.current_phase = GamePhaseScript.Phase.ENDING
	game._route_current_phase()
	await _frames(4)
	_assert(game.current_scene != null and game.current_scene.name == "EndingScene", "A final-day C-4 return must route to the energy-choice EndingScene.")
	_assert(panel.is_open() and panel.message_key() == "story_c4_active", "The C-4 moral scene must open before the energy-choice controls when the Front arrives on the same resolved day.")
	var c4_types := ["world_event", "dialogue", "dialogue", "dialogue", "stage_direction", "dialogue"]
	for line_index in range(c4_types.size()):
		_assert(panel.current_line_type() == str(c4_types[line_index]), "Final-day C-4 prelude line %d must preserve the moral-scene cadence." % (line_index + 1))
		await _assert_current_line_fits_viewports(panel, "final-day C-4 prelude line %d" % (line_index + 1))
		panel.advance()
		await _frames(1)
	_assert(not panel.is_open(), "The final-day C-4 prelude must finish before the player can use the energy-choice screen.")
	var harbor_choice := game.current_scene.find_child("EnergyChoice_harbor", true, false) as Button if game.current_scene != null else null
	_assert(harbor_choice != null and harbor_choice.visible, "The energy-choice controls must remain available after the C-4 prelude.")


func _consume_expected_dialogue_lines(panel: Control, context: String, expected_speakers: Array) -> void:
	for expected_index in range(expected_speakers.size()):
		var expected: Dictionary = expected_speakers[expected_index]
		_assert(panel != null and panel.is_open(), "%s must remain open for expected dialogue line %d." % [context, expected_index + 1])
		if panel == null or not panel.is_open():
			return
		_assert_dialogue_speaker(panel, str(expected.get("name", "")), str(expected.get("side", "")), "%s line %d" % [context, expected_index + 1])
		await _assert_current_line_fits_viewports(panel, "%s line %d" % [context, expected_index + 1])
		panel.advance()
		await _frames(1)


func _assert_current_line_fits_viewports(panel: Control, context: String) -> void:
	_assert(panel != null and panel.is_open(), "%s needs an open narrative panel for responsive-layout verification." % context)
	if panel == null or not panel.is_open():
		return
	var original_size := panel.size
	for viewport_variant in TEST_VIEWPORT_SIZES:
		var viewport_size: Vector2 = viewport_variant
		panel.size = viewport_size
		panel.call("_layout_dialogue")
		await _frames(2)
		_assert(
			_dialogue_geometry_is_compact(panel, viewport_size),
			"%s (%s, line %d) must stay inside %s; got %s." % [context, panel.current_line_type(), panel.line_index() + 1, viewport_size, _dialogue_geometry_description(panel)]
		)
		_assert(
			_conversation_layout_fits(panel),
			"%s (%s, line %d) must keep every visible narrative control inside the panel at %s." % [context, panel.current_line_type(), panel.line_index() + 1, viewport_size]
		)
	panel.size = original_size
	panel.call("_layout_dialogue")
	await _frames(1)


func _assert_scene_context(panel: Control, expected_text: String, context: String) -> void:
	var context_label := panel.find_child("NarrativeContextLabel", true, false) as Label if panel != null else null
	_assert(context_label != null, "%s must expose a dedicated scene-context label." % context)
	if context_label == null:
		return
	_assert(context_label.visible, "%s scene context must be user-facing rather than hidden metadata." % context)
	_assert(context_label.text == expected_text, "%s must show the authored scene context; got '%s'." % [context, context_label.text])


func _assert_non_dialogue_presentation(panel: Control, expected_type: String, context: String) -> void:
	_assert(panel != null and panel.current_line_type() == expected_type, "%s must render as %s." % [context, expected_type])
	if panel == null:
		return
	var expected_kind := "ZMIANA W ŚWIECIE" if expected_type == "world_event" else "OPIS SCENY"
	_assert(panel.current_side().is_empty(), "%s must not claim a dialogue side." % context)
	_assert(not _control_is_visible(panel, "NarrativeSpeakerLabel"), "%s must not display a fictional speaker." % context)
	_assert(not _control_is_visible(panel, "NarrativePortraitFrameLeft") and not _control_is_visible(panel, "NarrativePortraitFrameRight"), "%s must not reserve or display character portraits." % context)
	_assert(_control_is_visible(panel, "NarrativeLineKindLabel") and _label_text(panel, "NarrativeLineKindLabel") == expected_kind, "%s must expose the correct non-dialogue label." % context)


func _assert_dialogue_speaker(panel: Control, expected_name: String, expected_side: String, context: String) -> void:
	_assert(panel != null and panel.current_line_type() == "dialogue", "%s must render as dialogue." % context)
	if panel == null:
		return
	_assert(panel.current_side() == expected_side, "%s must use the stable %s speaker side." % [context, expected_side])
	_assert(_control_is_visible(panel, "NarrativeSpeakerLabel") and _label_text(panel, "NarrativeSpeakerLabel").contains(expected_name), "%s must visibly identify %s." % [context, expected_name])
	_assert(_control_is_visible(panel, "NarrativePortraitFrameLeft") and _control_is_visible(panel, "NarrativePortraitFrameRight"), "%s must retain the dialogue portrait slots." % context)
	_assert(not _control_is_visible(panel, "NarrativeLineKindLabel"), "%s must not carry a stage/world-event label." % context)


func _assert_story_catalog_contract(game, panel: Control) -> void:
	_assert(game != null and game.game_state != null and game.game_state.story_flags != null, "The story catalog test needs campaign state.")
	if game == null or game.game_state == null or game.game_state.story_flags == null:
		return
	for survivor in game.game_state.survivors:
		survivor.status = SurvivorStateScript.Status.AVAILABLE
	var story = game.game_state.story_flags
	_reset_story_milestones(story)
	story.archive_map_transmitted = true
	var scenarios := [
		{
			"flag": "r3_diagnosed",
			"key": "story_r3_diagnosed",
			"line_types": ["world_event", "dialogue", "stage_direction"],
			"cues": ["", "", ""],
			"required": ["spalił się regulator", "odczyty zostają przypięte"],
		},
		{
			"flag": "r3_regulator_ready",
			"key": "story_r3_regulator_ready",
			"line_types": ["stage_direction", "dialogue", "stage_direction"],
			"cues": ["", "", ""],
			"required": ["równym zielonym pulsem", "zamknięty w uszczelnionym stelażu"],
		},
		{
			"flag": "r3_generator_active",
			"key": "story_r3_active",
			"line_types": ["world_event", "dialogue", "stage_direction", "dialogue", "dialogue"],
			"cues": [NarrativeAudioCatalogScript.CUE_R3_STARTUP, NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_OPEN, NarrativeAudioCatalogScript.CUE_PUMPS_STABLE, "", ""],
			"required": ["miarowa praca pomp Północnej", "maszyny, nie alarm", "po obu stronach są ludzie"],
			"klara_lines": 2,
		},
		{
			"flag": "c4_switchboard_active",
			"key": "story_c4_active",
			"line_types": ["world_event", "dialogue", "dialogue", "dialogue", "stage_direction", "dialogue"],
			"cues": [NarrativeAudioCatalogScript.CUE_C4_SINGLE_LINE, "", "", "", "", ""],
			"required": ["JEDNA LINIA PRIORYTETOWA", "skierujcie zasilanie do Przystani", "wybierała za nas", "szkic prowizorycznego rozdzielacza", "materiałami", "pracą Warsztatu", "jeszcze jednym zejściem"],
			"klara_lines": 1,
		},
		{
			"flag": "common_line_splitter_ready",
			"key": "story_splitter_ready",
			"line_types": ["stage_direction", "dialogue", "stage_direction"],
			"cues": ["", "", NarrativeAudioCatalogScript.CUE_SPLITTER_BENCH_LATCH],
			"required": ["jeszcze ciepły od spawania", "zablokowany w stelażu transportowym"],
		},
		{
			"flag": "common_line_splitter_installed",
			"key": "story_splitter_installed",
			"line_types": ["stage_direction", "world_event", "dialogue", "dialogue", "dialogue"],
			"cues": ["", NarrativeAudioCatalogScript.CUE_C4_DUAL_LINE_TEST, "", "", ""],
			"required": ["kontrolki PRZYSTAŃ i PÓŁNOCNA", "kogo zgasić"],
			"klara_lines": 2,
		},
		{
			"flag": "crisis_active",
			"key": "story_crisis_17",
			"line_types": ["stage_direction", "dialogue", "stage_direction", "dialogue"],
			"cues": ["", "", "", ""],
			"required": ["przekreślił słowo „jutro”", "Najpierw wysłuchamy gniewu"],
		},
		{
			"flag": "black_front_active",
			"key": "story_black_front_last_day",
			"line_types": ["world_event", "dialogue", "dialogue", "dialogue", "stage_direction"],
			"cues": [NarrativeAudioCatalogScript.CUE_FRONT_PRESSURE, NarrativeAudioCatalogScript.CUE_PUMPS_STABLE, "", "", NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_FADE],
			"required": ["Pomost Siedem, potwierdźcie", "Jeśli kanał zgaśnie, wołajcie dalej", "pierwszy grzmot"],
			"klara_lines": 2,
		},
	]
	for scenario_variant in scenarios:
		var scenario: Dictionary = scenario_variant
		if str(scenario.get("flag", "")) == "black_front_active":
			story.crisis_active = false
			story.black_front_days_total = 12
			story.black_front_days_remaining = 1
		story.set(str(scenario.get("flag", "")), true)
		if bool(story.crisis_active):
			story.crisis_started_day = 17
		var conversation: Dictionary = NarrativeContentScript.story_message(game.game_state)
		var expected_key := str(scenario.get("key", ""))
		_assert(str(conversation.get("key", "")) == expected_key, "Story milestone %s must resolve to its dedicated scene." % expected_key)
		var source_lines: Array = conversation.get("lines", [])
		var expected_types: Array = scenario.get("line_types", [])
		_assert(source_lines.size() == expected_types.size(), "Story milestone %s must use the intended %d-beat cadence." % [expected_key, expected_types.size()])
		_assert_conversation_cue_contract(conversation, scenario.get("cues", []), expected_key)
		var actual_types: Array[String] = []
		var story_text := ""
		var klara_lines := 0
		for line_variant in source_lines:
			if typeof(line_variant) != TYPE_DICTIONARY:
				continue
			var story_line: Dictionary = line_variant
			actual_types.append(str(story_line.get("line_type", "dialogue")))
			story_text += "\n" + str(story_line.get("body", ""))
			if str(story_line.get("speaker_id", "")) == "klara":
				klara_lines += 1
			if str(story_line.get("line_type", "dialogue")) == "world_event":
				_assert_world_event_has_no_objective_copy(str(story_line.get("body", "")), expected_key)
		_assert(actual_types == expected_types, "Story milestone %s must preserve its authored narrator/dialogue cadence." % expected_key)
		for required_variant in scenario.get("required", []):
			var required_fragment := str(required_variant)
			_assert(story_text.to_lower().contains(required_fragment.to_lower()), "Story milestone %s must retain the dramatic beat '%s'." % [expected_key, required_fragment])
		_assert(klara_lines == int(scenario.get("klara_lines", 0)), "Story milestone %s must use Klara exactly %d times." % [expected_key, int(scenario.get("klara_lines", 0))])
		var resolved_lines: Array[Dictionary] = game._resolve_narrative_lines(conversation)
		_assert(resolved_lines.size() == source_lines.size(), "Story milestone %s must keep every authored beat after speaker resolution." % expected_key)
		var resolved_klara_lines := 0
		for resolved_line_variant in resolved_lines:
			var resolved_line: Dictionary = resolved_line_variant
			if str(resolved_line.get("speaker_id", "")) != "klara":
				continue
			var resolved_speaker: Dictionary = resolved_line.get("speaker", {})
			_assert(str(resolved_speaker.get("display_name", "")) == "Klara Wysocka" and str(resolved_speaker.get("portrait_id", "")) == "klara", "Story milestone %s must resolve Klara to her name and dedicated portrait." % expected_key)
			resolved_klara_lines += 1
		_assert(resolved_klara_lines == klara_lines, "Story milestone %s must retain every authored Klara line after speaker resolution." % expected_key)
		panel.present(conversation, resolved_lines)
		await _frames(1)
		_assert(panel.is_open(), "Story milestone %s must be presentable by the shared panel." % expected_key)
		for line_index in range(resolved_lines.size()):
			_assert(panel.current_line_type() == str(expected_types[line_index]), "Story milestone %s line %d must render with its authored type." % [expected_key, line_index + 1])
			await _assert_current_line_fits_viewports(panel, "%s line %d" % [expected_key, line_index + 1])
			panel.advance()
			await _frames(1)
		_assert(not panel.is_open(), "Story milestone %s must close after its final authored beat." % expected_key)
	await _assert_technical_neutral_fallback(game, panel)
	_assert_final_day_milestone_order(game.game_state)
	_reset_story_milestones(story)


func _assert_world_event_has_no_objective_copy(body: String, context: String) -> void:
	var normalized := body.to_lower()
	for forbidden_fragment in [
		"nowy cel", "kolejny cel", "cel aktywny", "projekt dostępny", "wymagania", "czas na wykonanie",
		"warsztat ii", "warsztat iii", "punktów pracy", "złomu", "tkaniny/gumy", "części techniczne",
		"wróć do", "dotrzyj do", "wykonaj ", "zbuduj ", "zamontuj ", "uruchom ", "aktywuj ",
	]:
		_assert(not normalized.contains(forbidden_fragment), "World-event card in %s must leave objective, recipe and imperative copy in the tracker; found '%s'." % [context, forbidden_fragment])


func _assert_audio_catalog_contract() -> void:
	var cue_ids: Array[String] = NarrativeAudioCatalogScript.cue_ids()
	_assert(cue_ids.size() == 13, "The narrative audio catalog must expose the 13 approved recurring non-voice cues.")
	for cue_id in cue_ids:
		var stream := NarrativeAudioCatalogScript.stream_for(cue_id)
		_assert(stream is AudioStreamWAV, "Narrative cue %s must resolve to a local PCM WAV stream." % cue_id)
		if stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			_assert(wav.mix_rate == 48000 and wav.stereo, "Narrative cue %s must use the authored 48 kHz stereo format." % cue_id)
			_assert(wav.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Narrative cue %s must be a finite one-shot, never a loop." % cue_id)
			var metrics := _wav_source_signal_metrics(stream.resource_path)
			_assert(bool(metrics.get("pcm16_stereo_48k", false)), "Narrative cue %s source must retain deterministic PCM16, 48 kHz stereo samples." % cue_id)
			var peak := float(metrics.get("peak", 0.0))
			var mono_peak := float(metrics.get("mono_peak", 0.0))
			var mono_rms := float(metrics.get("mono_rms", 0.0))
			_assert(peak >= 0.45 and peak <= 0.90, "Narrative cue %s must remain audible with safe peak headroom; got %.3f." % [cue_id, peak])
			_assert(mono_peak >= peak * 0.45, "Narrative cue %s must preserve its recognizable transient after mono fold-down." % cue_id)
			_assert(mono_rms >= 0.025 and mono_rms <= 0.25, "Narrative cue %s must avoid near-silence and excessive sustained level; mono RMS %.3f." % [cue_id, mono_rms])
		_assert(stream != null and stream.get_length() >= 0.3 and stream.get_length() <= 6.0, "Narrative cue %s must remain a short 0.3-6.0 second signifier." % cue_id)
	_assert(NarrativeAudioCatalogScript.stream_for("") == null and NarrativeAudioCatalogScript.stream_for("not_an_authored_cue") == null, "Missing and unknown cue IDs must resolve to intentional silence.")


func _wav_source_signal_metrics(source_path: String) -> Dictionary:
	var data := FileAccess.get_file_as_bytes(source_path)
	if data.size() < 44 or data.slice(0, 4).get_string_from_ascii() != "RIFF" or data.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {}
	var audio_format := 0
	var channels := 0
	var sample_rate := 0
	var bits_per_sample := 0
	var sample_data_offset := -1
	var sample_data_size := 0
	var chunk_offset := 12
	while chunk_offset + 8 <= data.size():
		var chunk_id := data.slice(chunk_offset, chunk_offset + 4).get_string_from_ascii()
		var chunk_size := int(data.decode_u32(chunk_offset + 4))
		var chunk_data_offset := chunk_offset + 8
		if chunk_data_offset + chunk_size > data.size():
			return {}
		if chunk_id == "fmt " and chunk_size >= 16:
			audio_format = int(data.decode_u16(chunk_data_offset))
			channels = int(data.decode_u16(chunk_data_offset + 2))
			sample_rate = int(data.decode_u32(chunk_data_offset + 4))
			bits_per_sample = int(data.decode_u16(chunk_data_offset + 14))
		elif chunk_id == "data":
			sample_data_offset = chunk_data_offset
			sample_data_size = chunk_size
		chunk_offset = chunk_data_offset + chunk_size + (chunk_size % 2)
	if audio_format != 1 or channels != 2 or sample_rate != 48000 or bits_per_sample != 16 or sample_data_offset < 0:
		return {"pcm16_stereo_48k": false}
	var peak := 0.0
	var mono_peak := 0.0
	var mono_square_sum := 0.0
	var frame_count := 0
	var sample_data_end := mini(sample_data_offset + sample_data_size, data.size())
	for byte_offset in range(sample_data_offset, sample_data_end - 3, 4):
		var left := float(data.decode_s16(byte_offset)) / 32768.0
		var right := float(data.decode_s16(byte_offset + 2)) / 32768.0
		var mono := (left + right) * 0.5
		peak = maxf(peak, maxf(absf(left), absf(right)))
		mono_peak = maxf(mono_peak, absf(mono))
		mono_square_sum += mono * mono
		frame_count += 1
	return {
		"pcm16_stereo_48k": true,
		"peak": peak,
		"mono_peak": mono_peak,
		"mono_rms": sqrt(mono_square_sum / maxf(float(frame_count), 1.0)),
	}


func _conversation_for_key(conversations: Array, expected_key: String) -> Dictionary:
	for conversation_variant in conversations:
		if typeof(conversation_variant) != TYPE_DICTIONARY:
			continue
		var conversation: Dictionary = conversation_variant
		if str(conversation.get("key", "")) == expected_key:
			return conversation
	return {}


func _assert_conversation_cue_contract(conversation: Dictionary, expected_cues: Array, context: String) -> void:
	var lines: Array = conversation.get("lines", [])
	_assert(lines.size() == expected_cues.size(), "%s must expose one cue decision for every authored line." % context)
	for line_index in range(mini(lines.size(), expected_cues.size())):
		var line: Dictionary = lines[line_index] if typeof(lines[line_index]) == TYPE_DICTIONARY else {}
		var expected_cue := str(expected_cues[line_index])
		var actual_cue := str(line.get("cue_id", ""))
		_assert(actual_cue == expected_cue, "%s line %d must use cue '%s', got '%s'." % [context, line_index + 1, expected_cue, actual_cue])
		if expected_cue.is_empty():
			_assert(not line.has("cue_id"), "%s line %d must express intentional silence by omitting cue_id." % [context, line_index + 1])
		else:
			_assert(NarrativeAudioCatalogScript.has_cue(expected_cue), "%s line %d must reference an authored catalog stream." % [context, line_index + 1])


func _assert_current_cue(panel: Control, expected_key: String, expected_line_index: int, expected_cue: String, expected_event_count: int, context: String) -> void:
	_assert(panel != null and panel.line_index() == expected_line_index, "%s must test the intended narrative line." % context)
	_assert(panel != null and panel.current_cue_id() == expected_cue and panel.is_cue_playing(), "%s must start cue '%s' as its line becomes current." % [context, expected_cue])
	var player := panel.find_child("NarrativeCuePlayer", true, false) as AudioStreamPlayer if panel != null else null
	_assert(player != null and player.bus == &"Master" and player.max_polyphony == 1, "%s must use the single local Master-bus one-shot player." % context)
	_assert(player == null or player.process_mode == Node.PROCESS_MODE_PAUSABLE, "%s cue must respect a paused SceneTree even though dialogue input remains available." % context)
	_assert(player != null and player.stream == NarrativeAudioCatalogScript.stream_for(expected_cue), "%s must play the catalog stream assigned to this cue ID." % context)
	_assert(_cue_events.size() == expected_event_count, "%s must emit exactly one cue-start event for this line." % context)
	if not _cue_events.is_empty():
		var event: Dictionary = _cue_events.back()
		_assert(str(event.get("key", "")) == expected_key and int(event.get("line_index", -1)) == expected_line_index and str(event.get("cue_id", "")) == expected_cue, "%s cue event must identify the exact conversation and line." % context)


func _assert_silent_current_line(panel: Control, expected_line_index: int, context: String) -> void:
	_assert(panel != null and panel.line_index() == expected_line_index, "%s must test the intended silent narrative line." % context)
	_assert(panel != null and panel.current_cue_id().is_empty() and not panel.is_cue_playing(), "%s must stop the previous one-shot and remain intentionally silent." % context)
	var player := panel.find_child("NarrativeCuePlayer", true, false) as AudioStreamPlayer if panel != null else null
	_assert(player != null and player.stream == null, "%s must release the previous stream instead of carrying it under the next line." % context)


func _assert_audio_lifecycle_and_scene_swap(game, panel: Control) -> void:
	var synthetic_conversation := {
		"key": "audio_lifecycle_contract",
		"title": "TEST AUDIO",
		"scene_context": "TEST",
	}
	var synthetic_lines: Array[Dictionary] = [
		{"line_type": "stage_direction", "body": "Długi motyw zostaje uruchomiony.", "cue_id": NarrativeAudioCatalogScript.CUE_FRONT_PRESSURE},
		{"line_type": "stage_direction", "body": "Kanał zastępuje poprzedni motyw.", "cue_id": NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_OPEN},
		{"line_type": "stage_direction", "body": "Zamierzona cisza."},
		{"line_type": "stage_direction", "body": "Nieznany identyfikator zachowuje ciszę.", "cue_id": "unknown_narrative_cue"},
	]
	_cue_events.clear()
	panel.present(synthetic_conversation, synthetic_lines)
	await _frames(1)
	_assert_current_cue(panel, "audio_lifecycle_contract", 0, NarrativeAudioCatalogScript.CUE_FRONT_PRESSURE, 1, "synthetic first-line cue")
	await _assert_active_cue_pauses_with_tree(panel)
	var starts_before_layout := _cue_events.size()
	panel.call("_layout_dialogue")
	game.call("_on_user_settings_applied", game.user_settings.snapshot())
	await _frames(2)
	_assert(_cue_events.size() == starts_before_layout, "Layout and settings application must not replay the current narrative cue.")
	panel.advance()
	_assert_current_cue(panel, "audio_lifecycle_contract", 1, NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_OPEN, 2, "rapid cue replacement")
	panel.advance()
	_assert_silent_current_line(panel, 2, "rapid advance into intentional silence")
	_assert(_cue_events.size() == 2, "Intentional silence must not emit a cue-start event.")
	panel.advance()
	_assert_silent_current_line(panel, 3, "unknown cue fallback")
	_assert(_cue_events.size() == 2, "An unknown cue ID must fail silently without a start event.")
	var natural_finish_lines: Array[Dictionary] = [
		{"line_type": "stage_direction", "body": "Krótki kanał wygasa naturalnie.", "cue_id": NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_FADE},
	]
	panel.present(synthetic_conversation, natural_finish_lines)
	await _frames(1)
	_assert_current_cue(panel, "audio_lifecycle_contract", 0, NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_FADE, 3, "natural one-shot completion setup")
	await get_tree().create_timer(0.65).timeout
	_assert(panel.is_open() and panel.current_cue_id().is_empty() and not panel.is_cue_playing(), "A finished one-shot must release audio without advancing or closing its narrative line.")
	var natural_player := panel.find_child("NarrativeCuePlayer", true, false) as AudioStreamPlayer
	_assert(natural_player != null and natural_player.stream == null, "Natural one-shot completion must release its stream.")
	panel.present(synthetic_conversation, synthetic_lines)
	await _frames(1)
	_assert_current_cue(panel, "audio_lifecycle_contract", 0, NarrativeAudioCatalogScript.CUE_FRONT_PRESSURE, 4, "player-dismiss cleanup setup")
	var dismissed_before_player_close := _dismissed_keys.size()
	panel.dismiss()
	_assert(not panel.is_open() and panel.current_cue_id().is_empty() and not panel.is_cue_playing(), "Player dismissal must stop an active narrative cue before emitting dismissed.")
	_assert(natural_player != null and natural_player.stream == null, "Player dismissal must release the active stream.")
	_assert(_dismissed_keys.size() == dismissed_before_player_close + 1 and _dismissed_keys.back() == "audio_lifecycle_contract", "Player dismissal must still emit its one normal dismissed event.")
	panel.present(synthetic_conversation, synthetic_lines)
	await _frames(1)
	_assert_current_cue(panel, "audio_lifecycle_contract", 0, NarrativeAudioCatalogScript.CUE_FRONT_PRESSURE, 5, "scene-swap cleanup setup")
	var dismissed_before_swap := _dismissed_keys.size()
	game.show_main_menu()
	await _frames(3)
	_assert(game.current_scene != null and game.current_scene.name == "MainMenu", "The audio lifecycle fixture must perform a real scene swap.")
	_assert(not panel.is_open() and panel.current_cue_id().is_empty() and not panel.is_cue_playing(), "A scene swap must synchronously clear the narrative panel and stop its cue.")
	var player := panel.find_child("NarrativeCuePlayer", true, false) as AudioStreamPlayer
	_assert(player != null and player.stream == null, "A scene swap must release the narrative stream so it cannot leak into the menu.")
	_assert(_dismissed_keys.size() == dismissed_before_swap, "Forced clear during a scene swap must not masquerade as a player-dismissed conversation.")


func _assert_active_cue_pauses_with_tree(panel: Control) -> void:
	var player := panel.find_child("NarrativeCuePlayer", true, false) as AudioStreamPlayer if panel != null else null
	_assert(player != null and player.playing, "Pause/resume verification needs an active narrative one-shot.")
	if player == null or not player.playing:
		return
	var original_test_process_mode := process_mode
	process_mode = Node.PROCESS_MODE_ALWAYS
	var position_before_pause := player.get_playback_position()
	get_tree().paused = true
	await get_tree().create_timer(0.25, true, false, true).timeout
	var position_while_paused := player.get_playback_position()
	_assert(player.stream != null and panel.current_cue_id() == NarrativeAudioCatalogScript.CUE_FRONT_PRESSURE, "A paused SceneTree must suspend the pausable cue without discarding its stream or identity.")
	_assert(absf(position_while_paused - position_before_pause) < 0.08, "A narrative cue must not advance while the SceneTree is paused.")
	get_tree().paused = false
	await get_tree().create_timer(0.25, true, false, true).timeout
	var position_after_resume := player.get_playback_position()
	_assert(player.playing, "Unpausing must resume the same active narrative cue.")
	_assert(position_after_resume > position_while_paused + 0.08, "The suspended narrative cue must continue after unpausing.")
	process_mode = original_test_process_mode


func _assert_technical_neutral_fallback(game, panel: Control) -> void:
	for survivor in game.game_state.survivors:
		survivor.status = SurvivorStateScript.Status.DEAD
	_reset_story_milestones(game.game_state.story_flags)
	game.game_state.story_flags.archive_map_transmitted = true
	game.game_state.story_flags.r3_diagnosed = true
	var conversation: Dictionary = NarrativeContentScript.story_message(game.game_state)
	var resolved_lines: Array[Dictionary] = game._resolve_narrative_lines(conversation)
	_assert(resolved_lines.size() == 3, "R-3 diagnosis must retain all three beats under a technical neutral fallback.")
	var technical_report: Dictionary = resolved_lines[1] if resolved_lines.size() > 1 else {}
	var speaker: Dictionary = technical_report.get("speaker", {})
	_assert(bool(speaker.get("neutral_report", false)), "Technical fallback must be explicitly marked as a neutral report.")
	_assert(str(speaker.get("display_name", "")) == "RAPORT SYSTEMOWY" and not bool(speaker.get("has_portrait", true)), "Technical fallback must not invent a technician or portrait.")
	_assert(str(technical_report.get("body", "")).contains("RAPORT DIAGNOSTYCZNY R-3") and not str(technical_report.get("body", "")).contains("Generator odpowiada"), "Technical fallback must replace the personal diagnosis with fallback_body.")
	panel.present(conversation, resolved_lines)
	await _frames(1)
	panel.advance()
	await _frames(1)
	_assert_dialogue_speaker(panel, "RAPORT SYSTEMOWY", "right", "R-3 technical neutral fallback")
	_assert(_portrait_alpha(panel, "NarrativePortraitFrameLeft") < 0.01 and _portrait_alpha(panel, "NarrativePortraitFrameRight") < 0.01, "Technical neutral fallback must hide both portraits.")
	await _assert_current_line_fits_viewports(panel, "R-3 technical neutral fallback")
	panel.dismiss()
	await _frames(1)
	for survivor in game.game_state.survivors:
		survivor.status = SurvivorStateScript.Status.AVAILABLE


func _assert_final_day_milestone_order(state) -> void:
	_reset_story_milestones(state.story_flags)
	var original_day := int(state.day)
	state.day = 14
	var story = state.story_flags
	story.archive_map_transmitted = true
	story.r3_diagnosed = true
	story.r3_regulator_ready = true
	story.r3_generator_active = true
	story.r3_generator_activated_day = 12
	story.c4_switchboard_active = true
	story.c4_switchboard_activated_day = 13
	story.black_front_active = true
	story.black_front_days_total = 12
	story.black_front_days_remaining = 1
	var planning_keys: Array[String] = []
	for conversation in NarrativeContentScript.story_conversations(state):
		planning_keys.append(str(conversation.get("key", "")))
	_assert(planning_keys == ["story_c4_active", "story_black_front_last_day"], "A C-4 return on the last morning must show the moral scene before the final-day radio scene.")
	story.black_front_active = false
	story.black_front_days_remaining = 0
	story.black_front_arrived = true
	story.energy_choice_pending = true
	state.day = 15
	story.c4_switchboard_activated_day = 14
	var ending_prelude_keys: Array[String] = []
	for conversation in NarrativeContentScript.ending_prelude_conversations(state):
		ending_prelude_keys.append(str(conversation.get("key", "")))
	_assert(ending_prelude_keys == ["story_c4_active"], "A C-4 return that triggers the Front must still show its moral scene before the energy choice.")
	state.day = original_day


func _reset_story_milestones(story) -> void:
	if story == null:
		return
	story.crisis_active = false
	story.crisis_days_remaining = 0
	story.crisis_started_day = 0
	story.junction_j7_active = false
	story.archive_terminal_active = false
	story.archive_map_transmitted = false
	story.r3_diagnosed = false
	story.r3_diagnosed_day = 0
	story.r3_regulator_ready = false
	story.r3_regulator_completed_day = 0
	story.r3_generator_active = false
	story.r3_generator_activated_day = 0
	story.c4_switchboard_active = false
	story.c4_switchboard_activated_day = 0
	story.common_line_splitter_ready = false
	story.common_line_splitter_completed_day = 0
	story.common_line_splitter_installed = false
	story.common_line_splitter_installed_day = 0
	story.black_front_active = false
	story.black_front_days_total = 0
	story.black_front_days_remaining = 0
	story.black_front_arrived = false
	story.energy_choice_pending = false
	story.energy_configuration = ""
	story.final_outcome_id = ""
	story.final_chronicle_continued = false


func _assert_ending_catalog_contract(state) -> void:
	_assert(state != null and state.story_flags != null, "The ending catalog test needs story state.")
	if state == null or state.story_flags == null:
		return
	var original_outcome := str(state.story_flags.final_outcome_id)
	var expected_keys := {
		"quiet_after_storm": "ending_quiet_after_storm",
		"debt_repaid": "ending_debt_repaid",
		"last_bridge": "ending_last_bridge",
	}
	var expected_types := {
		"quiet_after_storm": ["stage_direction", "dialogue", "world_event", "stage_direction", "dialogue"],
		"debt_repaid": ["world_event", "stage_direction", "dialogue", "dialogue", "stage_direction", "dialogue"],
		"last_bridge": ["world_event", "dialogue", "dialogue", "world_event", "dialogue", "stage_direction"],
	}
	var required_motifs := {
		"quiet_after_storm": ["z odbiornika kapie woda", "Północna, tu Przystań", "wyłącznie szum", "Nie słychać nawet rytmu pomp", "Nie wyłączaj. Jeszcze raz"],
		"debt_repaid": ["zielona lampka", "Przystań, potwierdźcie", "Jesteśmy", "pompy Północnej", "U nas też"],
		"last_bridge": ["Pompy trzymają", "Pokład trzyma", "trzeci, słaby sygnał", "Słyszymy. Mów dalej", "pojedyncze światło"],
	}
	var expected_cues := {
		"quiet_after_storm": ["", NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_OPEN, "", "", NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_OPEN],
		"debt_repaid": ["", NarrativeAudioCatalogScript.CUE_LINE_ENGAGE, NarrativeAudioCatalogScript.CUE_RADIO_CHANNEL_OPEN, "", NarrativeAudioCatalogScript.CUE_PUMPS_STABLE, ""],
		"last_bridge": [NarrativeAudioCatalogScript.CUE_C4_DUAL_LINE_STORM, NarrativeAudioCatalogScript.CUE_PUMPS_STABLE, "", NarrativeAudioCatalogScript.CUE_RADIO_DISTANT_CHANNEL, "", ""],
	}
	var last_bridge: Dictionary = {}
	for outcome_id in expected_keys:
		state.story_flags.final_outcome_id = outcome_id
		var conversation: Dictionary = NarrativeContentScript.ending_conversation(state)
		_assert(str(conversation.get("key", "")) == str(expected_keys[outcome_id]), "Ending outcome %s must map to its dedicated conversation." % outcome_id)
		_assert(not str(conversation.get("scene_context", "")).is_empty(), "Ending outcome %s must retain a user-facing scene context." % outcome_id)
		var lines: Array = conversation.get("lines", [])
		_assert(not lines.is_empty(), "Ending outcome %s must contain authored narrative beats." % outcome_id)
		_assert_conversation_cue_contract(conversation, expected_cues[outcome_id], "ending %s" % outcome_id)
		var has_non_dialogue_beat := false
		var ending_types: Array[String] = []
		var ending_text := ""
		for line_index in range(lines.size()):
			var line_variant = lines[line_index]
			if typeof(line_variant) != TYPE_DICTIONARY:
				continue
			var ending_line: Dictionary = line_variant
			var line_type := str(ending_line.get("line_type", "dialogue"))
			ending_types.append(line_type)
			ending_text += "\n" + str(ending_line.get("body", ""))
			_assert(line_type in ["dialogue", "stage_direction", "world_event"], "Ending outcome %s must use only supported line types." % outcome_id)
			if line_type != "dialogue":
				has_non_dialogue_beat = true
				_assert(not ending_line.has("speaker_id") and not ending_line.has("speaker_role_id") and not ending_line.has("side"), "Ending %s non-dialogue beats must not invent speaker data." % outcome_id)
			if line_type == "world_event":
				_assert_world_event_has_no_objective_copy(str(ending_line.get("body", "")), "ending %s" % outcome_id)
			if str(ending_line.get("speaker_id", "")) == "klara":
				_assert(str(ending_line.get("speaker_name", "")) == "Klara Wysocka" and str(ending_line.get("side", "")) == "right", "Ending %s line %d must assign Klara's callback to her stable right side." % [outcome_id, line_index + 1])
		_assert(has_non_dialogue_beat, "Ending outcome %s must include at least one narrator/world beat." % outcome_id)
		_assert(ending_types == expected_types[outcome_id], "Ending outcome %s must preserve the authored sound/dialogue cadence." % outcome_id)
		for motif_variant in required_motifs[outcome_id]:
			var motif := str(motif_variant)
			_assert(ending_text.to_lower().contains(motif.to_lower()), "Ending outcome %s must echo the recurring motif '%s'." % [outcome_id, motif])
		if outcome_id == "last_bridge":
			last_bridge = conversation
	state.story_flags.final_outcome_id = original_outcome
	if last_bridge.is_empty():
		return
	var last_bridge_types: Array[String] = []
	for line_variant in last_bridge.get("lines", []):
		if typeof(line_variant) == TYPE_DICTIONARY:
			var last_bridge_line: Dictionary = line_variant
			last_bridge_types.append(str(last_bridge_line.get("line_type", "dialogue")))
	_assert(last_bridge_types == ["world_event", "dialogue", "dialogue", "world_event", "dialogue", "stage_direction"], "The Last Bridge ending must preserve its world/dialogue cadence through the final stage direction.")
	_assert(str(last_bridge.get("scene_context", "")) == "WSPÓLNA LINIA  •  ŚWIT PO CZARNYM FRONCIE", "The Last Bridge ending must identify its place and time.")


func _control_is_visible(root: Node, node_name: String) -> bool:
	var control := root.find_child(node_name, true, false) as Control if root != null else null
	return control != null and control.visible


func _label_text(root: Node, node_name: String) -> String:
	var text_control := root.find_child(node_name, true, false) if root != null else null
	if text_control is Label:
		return (text_control as Label).text
	if text_control is RichTextLabel:
		return (text_control as RichTextLabel).text
	return ""


func _objective_body(step: int) -> String:
	var message: Dictionary = NarrativeContentScript.tutorial_message(step)
	return str(message.get("body", ""))


func _portrait_alpha(panel: Control, node_name: String) -> float:
	var frame := panel.find_child(node_name, true, false) as Control if panel != null else null
	return frame.modulate.a if frame != null else -1.0


func _dialogue_geometry_is_compact(panel: Control, expected_viewport: Vector2) -> bool:
	var dialogue_box := panel.find_child("NarrativeDialogueBox", true, false) as Control if panel != null else null
	var left_portrait := panel.find_child("NarrativePortraitFrameLeft", true, false) as Control if panel != null else null
	var right_portrait := panel.find_child("NarrativePortraitFrameRight", true, false) as Control if panel != null else null
	if dialogue_box == null or left_portrait == null or right_portrait == null:
		return false
	var rect := Rect2(dialogue_box.position, dialogue_box.size)
	var viewport_rect := Rect2(Vector2.ZERO, expected_viewport)
	return (
		viewport_rect.encloses(rect)
		and dialogue_box.size.x <= 820.0
		and dialogue_box.size.y >= 188.0
		and dialogue_box.size.y <= 216.0
		and left_portrait.size.y < dialogue_box.size.y - 20.0
		and right_portrait.size.y < dialogue_box.size.y - 20.0
		and rect.end.y <= expected_viewport.y - 11.0
		and _narrative_text_fits(panel)
	)


func _narrative_text_fits(panel: Control) -> bool:
	var body := panel.find_child("NarrativeBodyLabel", true, false) as RichTextLabel if panel != null else null
	if body == null:
		return false
	return body.get_content_height() <= body.size.y + 1.0


func _conversation_layout_fits(panel: Control) -> bool:
	if not _narrative_text_fits(panel):
		return false
	var dialogue_box := panel.find_child("NarrativeDialogueBox", true, false) as Control if panel != null else null
	if dialogue_box == null:
		return false
	var panel_rect := dialogue_box.get_global_rect()
	for node_name in [
		"NarrativeContextLabel",
		"NarrativeSpeakerLabel",
		"NarrativeLineKindLabel",
		"NarrativeTitleLabel",
		"NarrativeBodyLabel",
		"NarrativeFooter",
		"NarrativeContinueButton",
	]:
		var control := panel.find_child(node_name, true, false) as Control
		if control == null or (control.visible and not panel_rect.encloses(control.get_global_rect())):
			return false
	return true


func _dialogue_geometry_description(panel: Control) -> String:
	var dialogue_box := panel.find_child("NarrativeDialogueBox", true, false) as Control if panel != null else null
	var left_portrait := panel.find_child("NarrativePortraitFrameLeft", true, false) as Control if panel != null else null
	var right_portrait := panel.find_child("NarrativePortraitFrameRight", true, false) as Control if panel != null else null
	if dialogue_box == null or left_portrait == null or right_portrait == null:
		return "missing controls"
	var body := panel.find_child("NarrativeBodyLabel", true, false) as RichTextLabel
	return "panel pos=%s size=%s, left=%s, right=%s, body=%s content=%s, root=%s" % [
		dialogue_box.position,
		dialogue_box.size,
		left_portrait.size,
		right_portrait.size,
		body.size if body != null else Vector2.ZERO,
		body.get_content_height() if body != null else -1,
		panel.size,
	]


func _make_tutorial_setup():
	var setup = ExpeditionSetupScript.new()
	setup.diver_id = "igor"
	setup.diver_display_name = "Igor Sowa"
	setup.day = 3
	setup.diver_health = 100
	setup.diver_health_capacity = 100
	setup.oxygen_capacity = 100.0
	setup.backpack_capacity = 6
	setup.diver_carry_capacity = 24.0
	setup.item_weights = {}
	setup.selected_gear.assign(["knife", "crowbar", "repair_kit"])
	setup.suit_quality = 1
	setup.tutorial_mode = true
	setup.tutorial_baseline_step = TutorialStateScript.Step.ACTIVATE_JUNCTION_J7
	setup.difficulty_modifiers = {
		"oxygen_use_multiplier": 1.0,
		"suit_damage_multiplier": 1.0,
		"cold_rate_multiplier": 1.0,
		"threat_aggression_multiplier": 1.0,
		"current_strength_multiplier": 1.0,
		"noise_range_multiplier": 1.0,
	}
	return setup


func _configure_story_speaker_buildings(state) -> void:
	var community = state.find_building_by_definition("community_house") if state != null else null
	if state != null and community == null:
		community = BuildingStateScript.new()
		community.id = "narrative_fixture_community"
		community.definition_id = "community_house"
		community.slot_id = "center"
		state.buildings.append(community)
	if community != null:
		community.is_built = true
		community.level = maxi(int(community.level), 1)
		community.pending_level = 0
		community.condition = maxi(int(community.condition), 1)
		community.assigned_survivor_ids.assign(["mira"])
	var workshop = state.find_building_by_definition("workshop") if state != null else null
	if state != null and workshop == null:
		workshop = BuildingStateScript.new()
		workshop.id = "narrative_fixture_workshop"
		workshop.definition_id = "workshop"
		workshop.slot_id = "bottom_left"
		state.buildings.append(workshop)
	if workshop != null:
		workshop.is_built = true
		workshop.level = maxi(int(workshop.level), 1)
		workshop.pending_level = 0
		workshop.condition = maxi(int(workshop.condition), 1)
		workshop.assigned_survivor_ids.assign(["anka"])


func _press_key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _on_narrative_cue_started(message_key: String, line_index: int, cue_id: String) -> void:
	_cue_events.append({
		"key": message_key,
		"line_index": line_index,
		"cue_id": cue_id,
	})


func _on_narrative_dismissed(message_key: String) -> void:
	_dismissed_keys.append(message_key)


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Narrative dialogue flow test failed: " + message)
