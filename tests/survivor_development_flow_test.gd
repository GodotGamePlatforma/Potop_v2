extends Node

const BaseScene := preload("res://scenes/base/BaseScene.tscn")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const CompetencySystemScript := preload("res://scripts/base/CompetencySystem.gd")

var _failed := false

func _ready() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(906, DifficultyProfileScript.new())
	state.tutorial.complete()
	var igor = state.find_survivor("igor")
	igor.unspent_skill_points = 4
	igor.set_job_experience("medyk", 100)
	var anka = state.find_survivor("anka")
	var community_house = _add_community_house(state)
	community_house.assigned_survivor_ids.assign(["anka"])
	anka.current_assignment = community_house.id
	var departed_survivor = SurvivorStateScript.new()
	departed_survivor.id = "departed_resident"
	departed_survivor.display_name = "Była mieszkanka"
	departed_survivor.profession = "mechanik"
	departed_survivor.status = SurvivorStateScript.Status.DEPARTED
	state.survivors.append(departed_survivor)
	var base = BaseScene.instantiate()
	add_child(base)
	await get_tree().process_frame
	base.bind(null, state)
	await get_tree().process_frame

	var community_slot := base.get_node("BaseEnvironment/PlatformBoard/BuildingSlots/Slot_top_right")
	community_slot.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame

	var crew_grid := base.find_child("CommunityCrewGrid", true, false) as GridContainer
	var mira_card := base.find_child("CommunitySurvivorCard_mira", true, false) as Button
	var anka_card := base.find_child("CommunitySurvivorCard_anka", true, false) as Button
	var crew_igor_card := base.find_child("CommunitySurvivorCard_igor", true, false) as Button
	_assert(crew_grid != null and crew_grid.get_child_count() == 3 and base.find_child("CommunitySurvivorCard_departed_resident", true, false) == null, "The Community House should expose every present resident as a crew tile and exclude departed people.")
	_assert(mira_card != null and anka_card != null and crew_igor_card != null, "The Community House crew grid should contain Mira, Anka and Igor independently of its staffing rail.")
	_assert(base.find_child("CommunityPortrait_mira", true, false) != null and base.find_child("CommunityPortrait_igor", true, false) != null, "Crew tiles should show the canonical resident portraits.")
	mira_card.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	var identity := base.find_child("CommunityDevelopmentIdentity", true, false) as Label
	_assert(identity != null and identity.text.contains("MIRA BORUTA"), "Choosing a Community House crew tile should rebuild the details for that resident.")

	crew_igor_card = base.find_child("CommunitySurvivorCard_igor", true, false) as Button
	crew_igor_card.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	identity = base.find_child("CommunityDevelopmentIdentity", true, false) as Label
	crew_igor_card = base.find_child("CommunitySurvivorCard_igor", true, false) as Button
	_assert(identity != null and identity.text.contains("IGOR SOWA") and crew_igor_card != null and crew_igor_card.has_focus(), "The selected crew tile should switch back to Igor and retain keyboard focus.")

	var profession_picker := base.find_child("CommunityProfessionPicker", true, false) as OptionButton
	_assert(profession_picker != null, "The Community House should render a career-path selector for the chosen resident.")
	var medic_index := _find_picker_item(profession_picker, "medyk")
	_assert(medic_index >= 0, "The Community House career section should list every executable secondary profession except the resident's primary profession.")
	profession_picker.select(medic_index)
	profession_picker.emit_signal("item_selected", medic_index)
	await get_tree().process_frame
	await get_tree().process_frame
	var career_progress := base.find_child("CommunityCareerProgress", true, false) as Label
	var promote_button := base.find_child("PromoteProfessionButton", true, false) as Button
	_assert(career_progress != null and career_progress.text.contains("GOTOWY DO AWANSU") and career_progress.text.contains("100 / 100"), "The selected career should show exact practice and readiness derived from canonical state.")
	_assert(promote_button != null and promote_button.disabled and promote_button.tooltip_text.contains("Dom Wspólnoty II"), "Community House I should explain that formal promotion requires the Sala zgromadzeń level.")

	community_house.level = 2
	base.bind(null, state)
	await get_tree().process_frame
	base.get_node("BaseEnvironment/PlatformBoard/BuildingSlots/Slot_top_right").emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	promote_button = base.find_child("PromoteProfessionButton", true, false) as Button
	_assert(promote_button != null and not promote_button.disabled, "A ready resident should expose an enabled career promotion in an active Community House II.")
	promote_button.emit_signal("pressed")
	await get_tree().process_frame
	var confirmation := base.find_child("CareerPromotionConfirmation", true, false) as ConfirmationDialog
	_assert(confirmation != null and confirmation.visible and igor.secondary_profession.is_empty(), "An irreversible promotion should require confirmation before mutating SurvivorState.")
	confirmation.emit_signal("canceled")
	await get_tree().process_frame
	await get_tree().process_frame
	promote_button = base.find_child("PromoteProfessionButton", true, false) as Button
	_assert(igor.secondary_profession.is_empty() and base.find_child("CareerPromotionConfirmation", true, false) == null, "Canceling the irreversible promotion should close the dialog without changing the resident.")
	_assert(promote_button != null and promote_button.has_focus(), "Canceling career promotion should return keyboard focus to the promotion action.")
	var panel_scroll := base.find_child("PanelScroll", true, false) as ScrollContainer
	if panel_scroll != null:
		panel_scroll.scroll_vertical = int(panel_scroll.get_v_scroll_bar().max_value)
		await get_tree().process_frame
	var career_scroll_before := panel_scroll.scroll_vertical if panel_scroll != null else 0
	promote_button.emit_signal("pressed")
	await get_tree().process_frame
	confirmation = base.find_child("CareerPromotionConfirmation", true, false) as ConfirmationDialog
	_assert(confirmation != null and confirmation.visible, "The same ready promotion should remain available after a canceled confirmation.")
	confirmation.emit_signal("confirmed")
	await get_tree().process_frame
	await get_tree().process_frame
	var career_summary := base.find_child("CommunityCareerSummary", true, false) as Label
	_assert(igor.secondary_profession == "medyk" and career_summary != null and career_summary.text.contains("MEDYCYNA"), "Confirming promotion should set and immediately render the canonical secondary profession.")
	panel_scroll = base.find_child("PanelScroll", true, false) as ScrollContainer
	profession_picker = base.find_child("CommunityProfessionPicker", true, false) as OptionButton
	_assert(panel_scroll == null or panel_scroll.scroll_vertical >= maxi(career_scroll_before - 4, 0), "Confirming a promotion should preserve the career section's scroll position.")
	_assert(profession_picker != null and profession_picker.has_focus(), "After promotion the rebuilt panel should focus the career selector beside the visible result.")

	var carry_button := base.find_child("Develop_carry", true, false) as Button
	var progress := base.find_child("CommunityDevelopmentProgress", true, false) as Label
	var health_button := base.find_child("Develop_health", true, false) as Button
	var oxygen_button := base.find_child("Develop_oxygen", true, false) as Button
	_assert(carry_button != null and health_button != null and oxygen_button != null and not carry_button.disabled and not health_button.disabled and not oxygen_button.disabled and progress != null and progress.text.contains("PUNKTY ROZWOJU 4"), "A selected resident with points should expose enabled stat-development choices in the Community House.")
	for competency_id in CompetencySystemScript.IDS:
		var competency_button := base.find_child("Develop_%s" % competency_id, true, false) as Button
		_assert(
			competency_button != null
			and not competency_button.disabled
			and competency_button.text.contains("0/%d" % CompetencySystemScript.MAX_LEVEL),
			"The Community House must render an enabled level-zero action for every canonical passive competency."
		)
	var swimming_button := base.find_child("Develop_swimming", true, false) as Button
	panel_scroll = base.find_child("PanelScroll", true, false) as ScrollContainer
	if panel_scroll != null:
		panel_scroll.scroll_vertical = mini(240, int(panel_scroll.get_v_scroll_bar().max_value))
		await get_tree().process_frame
	var development_scroll_before := panel_scroll.scroll_vertical if panel_scroll != null else 0
	swimming_button.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	panel_scroll = base.find_child("PanelScroll", true, false) as ScrollContainer
	swimming_button = base.find_child("Develop_swimming", true, false) as Button
	_assert(CompetencySystemScript.level(igor, "swimming") == 1 and igor.unspent_skill_points == 3, "Clicking a passive competency must spend one point on the canonical SurvivorState.")
	_assert(swimming_button != null and swimming_button.text.contains("1/%d" % CompetencySystemScript.MAX_LEVEL) and swimming_button.has_focus(), "The rebuilt panel must show the purchased competency level and restore focus to its action.")
	_assert(panel_scroll == null or panel_scroll.scroll_vertical >= maxi(development_scroll_before - 4, 0), "Spending a competency point should preserve the resident card's scroll position.")

	health_button = base.find_child("Develop_health", true, false) as Button
	development_scroll_before = panel_scroll.scroll_vertical if panel_scroll != null else 0
	health_button.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(igor.unspent_skill_points == 2 and igor.health == 110 and igor.get_max_health() == 110, "Health development should increase both current and maximum health by ten on the canonical SurvivorState.")
	panel_scroll = base.find_child("PanelScroll", true, false) as ScrollContainer
	health_button = base.find_child("Develop_health", true, false) as Button
	_assert(panel_scroll == null or panel_scroll.scroll_vertical >= maxi(development_scroll_before - 4, 0), "Spending a development point should preserve the resident card's scroll position.")
	_assert(health_button != null and health_button.has_focus(), "The rebuilt resident card should return keyboard focus to the development action just used.")

	oxygen_button = base.find_child("Develop_oxygen", true, false) as Button
	oxygen_button.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(igor.unspent_skill_points == 1 and is_equal_approx(igor.get_oxygen_capacity(), 110.0), "Oxygen development should increase the resident's canonical personal capacity by ten.")

	carry_button = base.find_child("Develop_carry", true, false) as Button
	carry_button.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	carry_button = base.find_child("Develop_carry", true, false) as Button
	swimming_button = base.find_child("Develop_swimming", true, false) as Button
	var stats := base.find_child("CommunityDevelopmentStats", true, false) as Label
	_assert(igor.unspent_skill_points == 0 and is_equal_approx(igor.get_carry_capacity(), 22.0), "Clicking the carry choice should spend the point on the canonical SurvivorState.")
	_assert(carry_button != null and carry_button.disabled and swimming_button != null and swimming_button.disabled and stats != null and stats.text.contains("22.0 kg"), "The panel should immediately show the persistent result and prevent another stat or competency purchase without points.")
	_assert(igor.current_assignment.is_empty() and anka.current_assignment == community_house.id and community_house.assigned_survivor_ids == ["anka"], "Selecting a resident for development must not change the independent Community House staffing assignment.")

	igor.unspent_skill_points = 1
	community_house.condition = 0
	base.bind(null, state)
	await get_tree().process_frame
	base.get_node("BaseEnvironment/PlatformBoard/BuildingSlots/Slot_top_right").emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	carry_button = base.find_child("Develop_carry", true, false) as Button
	swimming_button = base.find_child("Develop_swimming", true, false) as Button
	_assert(carry_button != null and carry_button.disabled and carry_button.tooltip_text.contains("Domu Wspólnoty I"), "An inactive Community House must show resident information and the canonical level-one development blocker.")
	_assert(swimming_button != null and swimming_button.disabled and swimming_button.tooltip_text.contains("Domu Wspólnoty I"), "An inactive Community House must apply the same canonical blocker to passive competency purchases.")

	# The global Crew card is a second UI route to the same irreversible
	# command. It must not bypass the Community House gate, even if the handler
	# is invoked directly instead of through the disabled button.
	var building_panel := base.find_child("BuildingPanel", true, false) as Control
	var building_close := building_panel.find_child("CloseButton", true, false) as Button if building_panel != null else null
	if building_close != null:
		building_close.emit_signal("pressed")
		await get_tree().process_frame
	var crew_button := base.find_child("CrewButton", true, false) as Button
	_assert(crew_button != null, "The global development route requires the Crew HUD button.")
	if crew_button != null:
		crew_button.emit_signal("pressed")
		await get_tree().process_frame
		await get_tree().process_frame
	var crew_panel := base.find_child("SurvivorsPanel", true, false) as Control
	var igor_card := crew_panel.find_child("SurvivorButton_igor", true, false) as Button if crew_panel != null else null
	_assert(igor_card != null, "The Crew panel should expose Igor's global resident card.")
	var igor_summary := igor_card.find_child("SurvivorSummary_igor", true, false) as Label if igor_card != null else null
	var igor_development_alert := igor_card.find_child("SurvivorDevelopmentAlert_igor", true, false) as Label if igor_card != null else null
	_assert(
		igor_summary != null
		and igor_summary.text.contains(igor.display_name)
		and igor_summary.text.contains("POZ.")
		and igor_development_alert != null
		and igor_development_alert.is_visible_in_tree()
		and igor_development_alert.text == "PUNKTY ROZWOJU DO ROZDANIA: 1"
		and igor_card.get_global_rect().encloses(igor_development_alert.get_global_rect()),
		"The Crew row must visibly contain the dedicated development alert for the resident's unspent point."
	)
	if igor_card != null:
		igor_card.emit_signal("pressed")
		await get_tree().process_frame
		await get_tree().process_frame
	var global_panel := base.find_child("SurvivorDevelopmentPanel", true, false) as Control
	var profession_section := global_panel.find_child("ProfessionProgressSection", true, false) as Control if global_panel != null else null
	_assert(profession_section != null, "The resident card must expose the profession-practice section.")
	for profession_id in ["rybak", "kucharz", "mechanik", "medyk", "organizator", "nurek"]:
		var profession_line := global_panel.find_child("ProfessionProgress_%s" % profession_id, true, false) as Label if global_panel != null else null
		var profession_bar := global_panel.find_child("ProfessionProgressBar_%s" % profession_id, true, false) as ProgressBar if global_panel != null else null
		_assert(profession_line != null and profession_bar != null, "The resident card must show a labelled practice bar for %s." % profession_id)
	var global_carry := global_panel.find_child("Develop_carry", true, false) as Button if global_panel != null else null
	var global_gate := global_panel.find_child("SurvivorDevelopmentBlocker", true, false) as Label if global_panel != null else null
	_assert(
		global_carry != null
		and global_carry.disabled
		and global_carry.tooltip_text.contains("Domu Wspólnoty I")
		and global_gate != null
		and global_gate.text.contains("Domu Wspólnoty I"),
		"The global resident card must visibly present the same Community House I blocker as the building panel."
	)
	var carry_before_blocked_command: float = igor.get_carry_capacity()
	base.call("_on_survivor_development_requested", igor.id, "carry")
	_assert(igor.unspent_skill_points == 1 and is_equal_approx(igor.get_carry_capacity(), carry_before_blocked_command), "Calling the global UI handler directly must not bypass an inactive Community House.")
	var global_close := global_panel.find_child("CloseSurvivorDevelopment", true, false) as Button if global_panel != null else null
	if global_close != null:
		global_close.emit_signal("pressed")
		await get_tree().process_frame

	community_house.condition = 100
	community_house.level = 1
	base.bind(null, state)
	await get_tree().process_frame
	crew_button = base.find_child("CrewButton", true, false) as Button
	if crew_button != null:
		crew_button.emit_signal("pressed")
		await get_tree().process_frame
		await get_tree().process_frame
	crew_panel = base.find_child("SurvivorsPanel", true, false) as Control
	igor_card = crew_panel.find_child("SurvivorButton_igor", true, false) as Button if crew_panel != null else null
	if igor_card != null:
		igor_card.emit_signal("pressed")
		await get_tree().process_frame
		await get_tree().process_frame
	global_panel = base.find_child("SurvivorDevelopmentPanel", true, false) as Control
	global_carry = global_panel.find_child("Develop_carry", true, false) as Button if global_panel != null else null
	_assert(global_carry != null and not global_carry.disabled, "An active Community House I should unlock the global Crew development action.")
	if global_carry != null:
		global_carry.emit_signal("pressed")
		await get_tree().process_frame
		await get_tree().process_frame
	_assert(igor.unspent_skill_points == 0 and is_equal_approx(igor.get_carry_capacity(), carry_before_blocked_command + 4.0), "The global Crew route should delegate one successful point spend after Community House I becomes active.")
	base.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	base = null
	state = null
	igor = null
	anka = null
	community_house = null
	departed_survivor = null
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout

	if _failed:
		get_tree().quit(1)
		return
	print("Survivor development flow test passed: the Community House develops stats and passive competencies and confirms one real secondary profession without changing staffing.")
	get_tree().quit(0)

func _add_community_house(state):
	var building = BuildingStateScript.new()
	building.id = "test_community_house"
	building.definition_id = "community_house"
	building.slot_id = "top_right"
	building.level = 1
	building.is_built = true
	state.buildings.append(building)
	var slot_data: Dictionary = state.platform.slot_states[building.slot_id]
	slot_data["building_id"] = building.id
	state.platform.slot_states[building.slot_id] = slot_data
	return building

func _find_picker_item(picker: OptionButton, item_id: String) -> int:
	for index in range(picker.item_count):
		if str(picker.get_item_metadata(index)) == item_id:
			return index
	return -1

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Survivor development flow test failed: " + message)
