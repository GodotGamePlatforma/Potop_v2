extends SceneTree

const CampaignProgressionSystemScript := preload("res://scripts/base/CampaignProgressionSystem.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const GameDatabaseScript := preload("res://scripts/core/GameDatabase.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")

var _failed := false

func _initialize() -> void:
	var database = GameDatabaseScript.new()
	database.load_definitions()
	_assert(database.is_valid(), "Baza danych Wspólnej Linii musi być poprawna.")
	var state = GameStateScript.new()
	state.setup_new_campaign(8507, database.get_standard_difficulty())
	var campaign = CampaignProgressionSystemScript.new()
	var result = DiveResultScript.new()
	result.diver_id = "igor"
	result.activated_fixed_devices.append(CampaignProgressionSystemScript.ARCHIVE_TERMINAL_DEVICE_ID)
	state.underwater_world.delta.activated_fixed_devices.append(CampaignProgressionSystemScript.JUNCTION_J7_DEVICE_ID)
	state.underwater_world.delta.activated_fixed_devices.append(CampaignProgressionSystemScript.ARCHIVE_TERMINAL_DEVICE_ID)
	state.story_flags.junction_j7_active = true
	state.story_flags.junction_j7_activated_day = state.day
	campaign.apply_dive_result(state, result, null)
	_assert(state.story_flags.archive_terminal_active and state.story_flags.archive_map_transmitted, "Terminal Archiwum musi utrwalić transmisję Wspólnej Linii.")
	_assert(state.story_flags.act == state.story_flags.ACT_COMMON_LINE, "Archiwum nie może przełączać kampanii do usuniętego aktu.")
	var errors: PackedStringArray = state.persistence_validation_errors()
	_assert(errors.is_empty(), "Stan po pierwszym wynurzeniu musi przejść walidację zapisu: %s" % "; ".join(errors))
	database.free()
	if _failed:
		quit(1)
		return
	print("Campaign story system test passed: Archive surfacing remains valid in the Common Line-only campaign.")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
