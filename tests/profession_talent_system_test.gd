extends SceneTree

const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const ProfessionTalentDefinitionScript := preload("res://scripts/definitions/ProfessionTalentDefinition.gd")
const ProfessionTalentSystemScript := preload("res://scripts/base/ProfessionTalentSystem.gd")
const CareerProgressionSystemScript := preload("res://scripts/base/CareerProgressionSystem.gd")
const PersistenceValidatorScript := preload("res://scripts/data/GameStatePersistenceValidator.gd")

const ROUNDTRIP_PATH := "user://test_profession_talent_system.tres"

var _failed := false


func _initialize() -> void:
	_cleanup()
	_test_catalog_contract()
	_test_selection_boundaries_and_permanence()
	_test_two_formal_professions_cap_selection_at_two()
	_test_persistence_and_snapshot_validation()
	_test_selected_diver_and_carry_persistence_contract()
	_cleanup()
	if _failed:
		quit(1)
		return
	print("Profession talent system test passed: catalog, selection gates, permanence and persistence remain canonical.")
	quit(0)


func _test_catalog_contract() -> void:
	var talents = ProfessionTalentSystemScript.new()
	_assert(talents.validation_errors().is_empty(), "The profession-talent catalog must be valid: %s" % "; ".join(talents.validation_errors()))
	_assert(talents.get_talent_ids().size() == 12, "The catalog must contain exactly twelve talents.")
	var seen_ids: Dictionary = {}
	for profession_id in ProfessionTalentSystemScript.PROFESSION_IDS:
		var talent_ids := talents.get_talent_ids_for_profession(profession_id)
		_assert(talent_ids.size() == 2, "Profession %s must expose exactly two ordered talents." % profession_id)
		for talent_id in talent_ids:
			var definition = talents.get_definition(talent_id)
			_assert(
				definition != null
				and definition.get_script() == ProfessionTalentDefinitionScript
				and definition.is_valid()
				and str(definition.profession_id) == profession_id,
				"Talent %s must be a valid exact definition owned by profession %s." % [talent_id, profession_id]
			)
			_assert(not seen_ids.has(talent_id), "Talent IDs must be globally unique: %s." % talent_id)
			seen_ids[talent_id] = true


func _test_selection_boundaries_and_permanence() -> void:
	var talents = ProfessionTalentSystemScript.new()
	var career = CareerProgressionSystemScript.new()
	var state = _state()
	var survivor = state.find_survivor("mira")
	var choices := talents.get_talent_ids_for_profession("rybak")
	var first_talent := choices[0]
	var second_talent := choices[1]

	survivor.set_job_experience("rybak", 100)
	_assert(
		not career.can_select_profession_talent(state, survivor, first_talent)
		and career.profession_talent_selection_blocker(state, survivor, first_talent).contains("Domu Wspólnoty II"),
		"A ready formal profession must still require an active Community House II."
	)
	var house = _add_community_house(state, 1)
	_assert(
		not career.can_select_profession_talent(state, survivor, first_talent)
		and career.profession_talent_selection_blocker(state, survivor, first_talent).contains("Domu Wspólnoty II"),
		"Community House I must expose the exact level-two talent gate."
	)
	house.level = 2
	survivor.set_job_experience("rybak", 99)
	_assert(
		not career.can_select_profession_talent(state, survivor, first_talent)
		and career.profession_talent_selection_blocker(state, survivor, first_talent).contains("Brakuje 1 praktyki"),
		"Practice 99 must remain below the exact 100-point boundary."
	)
	survivor.set_job_experience("rybak", 100)
	state.current_day_plan.locked = true
	_assert(
		not career.can_select_profession_talent(state, survivor, first_talent)
		and not career.profession_talent_selection_blocker(state, survivor, first_talent).is_empty(),
		"A locked day plan must reject a ready talent choice."
	)
	state.current_day_plan.locked = false
	_assert(career.has_selectable_profession_talent(state, survivor), "Practice 100, an editable plan and active Community House II must expose the choice.")

	var day_before := int(state.day)
	var skill_points_before := int(survivor.unspent_skill_points)
	var resources_before: Dictionary = state.resources.values.duplicate(true)
	_assert(career.select_profession_talent(state, survivor.id, first_talent), "The exact threshold must permit one free talent choice.")
	_assert(
		ProfessionTalentSystemScript.selected_talent_id(survivor, "rybak") == first_talent
		and survivor.profession_talent_ids == {"rybak": first_talent},
		"A successful command must persist the selected talent under its formal profession."
	)
	_assert(
		state.day == day_before
		and survivor.unspent_skill_points == skill_points_before
		and state.resources.values == resources_before,
		"Talent selection must consume no day, development point or resource."
	)
	var permanent_selection: Dictionary = survivor.profession_talent_ids.duplicate(true)
	_assert(
		not career.select_profession_talent(state, survivor.id, first_talent)
		and not career.select_profession_talent(state, survivor.id, second_talent)
		and survivor.profession_talent_ids == permanent_selection,
		"Repeating or replacing the selected talent of one profession must be rejected without mutation."
	)

	var nonformal_talent := talents.get_talent_ids_for_profession("nurek")[0]
	survivor.set_job_experience("nurek", 100)
	_assert(
		not career.select_profession_talent(state, survivor.id, nonformal_talent)
		and survivor.profession_talent_ids == permanent_selection,
		"Practice alone must not unlock a talent of a nonformal profession."
	)


func _test_two_formal_professions_cap_selection_at_two() -> void:
	var talents = ProfessionTalentSystemScript.new()
	var career = CareerProgressionSystemScript.new()
	var state = _state()
	var survivor = state.find_survivor("mira")
	_add_community_house(state, 2)
	survivor.secondary_profession = "mechanik"
	survivor.set_job_experience("rybak", 100)
	survivor.set_job_experience("mechanik", 100)
	var fishing_talent := talents.get_talent_ids_for_profession("rybak")[0]
	var mechanic_talent := talents.get_talent_ids_for_profession("mechanik")[0]
	_assert(career.select_profession_talent(state, survivor.id, fishing_talent), "The primary formal profession must accept one talent.")
	_assert(career.select_profession_talent(state, survivor.id, mechanic_talent), "The secondary formal profession must accept one independent talent.")
	_assert(
		survivor.profession_talent_ids.size() == 2
		and survivor.profession_talent_ids.get("rybak") == fishing_talent
		and survivor.profession_talent_ids.get("mechanik") == mechanic_talent
		and not career.has_selectable_profession_talent(state, survivor),
		"Two formal professions must yield at most two permanent choices."
	)
	var medical_talent := talents.get_talent_ids_for_profession("medyk")[0]
	survivor.set_job_experience("medyk", 100)
	_assert(not career.select_profession_talent(state, survivor.id, medical_talent) and survivor.profession_talent_ids.size() == 2, "A third practiced but nonformal profession must never create a third talent.")


func _test_persistence_and_snapshot_validation() -> void:
	var talents = ProfessionTalentSystemScript.new()
	var career = CareerProgressionSystemScript.new()
	var state = _state()
	var survivor = state.find_survivor("mira")
	_add_community_house(state, 2)
	survivor.set_job_experience("rybak", 100)
	var talent_id := talents.get_talent_ids_for_profession("rybak")[0]
	_assert(career.select_profession_talent(state, survivor.id, talent_id), "The persistence fixture must start with a legal choice.")
	var valid_errors: PackedStringArray = state.persistence_validation_errors()
	_assert(valid_errors.is_empty(), "A legal talent choice must pass aggregate persistence validation: %s" % "; ".join(valid_errors))
	_assert(ResourceSaver.save(state, ROUNDTRIP_PATH) == OK, "The legal campaign fixture must be serializable.")
	var loaded = ResourceLoader.load(ROUNDTRIP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	var loaded_survivor = loaded.find_survivor(survivor.id) if loaded != null else null
	_assert(
		loaded_survivor != null
		and loaded_survivor.profession_talent_ids == {"rybak": talent_id}
		and ProfessionTalentSystemScript.selected_talent_id(loaded_survivor, "rybak") == talent_id,
		"The selected talent map must survive a Resource roundtrip."
	)

	var unknown = state.duplicate(true)
	unknown.find_survivor(survivor.id).profession_talent_ids = {"rybak": "unknown_talent"}
	_assert(_errors_contain(unknown.persistence_validation_errors(), "Nieznany talent zawodowy"), "Persistence must reject an ID outside the catalog.")
	var mismatched = state.duplicate(true)
	mismatched.find_survivor(survivor.id).profession_talent_ids = {"rybak": talents.get_talent_ids_for_profession("medyk")[0]}
	_assert(_errors_contain(mismatched.persistence_validation_errors(), "nie należy do profesji rybak"), "Persistence must reject a talent stored under another profession.")
	var premature = state.duplicate(true)
	premature.find_survivor(survivor.id).set_job_experience("rybak", 99)
	_assert(_errors_contain(premature.persistence_validation_errors(), "przed progiem praktyki 100"), "Persistence must reject a choice below the exact practice threshold.")
	var third = state.duplicate(true)
	var third_survivor = third.find_survivor(survivor.id)
	third_survivor.secondary_profession = "mechanik"
	third_survivor.set_job_experience("mechanik", 100)
	third_survivor.set_job_experience("medyk", 100)
	third_survivor.profession_talent_ids = {
		"rybak": talent_id,
		"mechanik": talents.get_talent_ids_for_profession("mechanik")[0],
		"medyk": talents.get_talent_ids_for_profession("medyk")[0],
	}
	_assert(_errors_contain(third.persistence_validation_errors(), "przekracza limit dwóch formalnych profesji"), "Persistence must reject more than two selected talents.")

	var candidate_snapshot = SurvivorStateScript.new()
	candidate_snapshot.id = "snapshot_candidate"
	candidate_snapshot.display_name = "Kandydatka"
	candidate_snapshot.profession = "rybak"
	candidate_snapshot.set_job_experience("rybak", 100)
	candidate_snapshot.profession_talent_ids = {"rybak": "unknown_talent"}
	var snapshot_errors: Array[String] = []
	PersistenceValidatorScript._append_snapshot_survivor_core_errors(snapshot_errors, candidate_snapshot, "testowej kandydatki")
	_assert(_errors_contain(snapshot_errors, "Nieznany talent zawodowy"), "Nested survivor snapshots must use the same validated catalog.")

	var setup = ExpeditionSetupScript.new()
	_assert("profession_talent_ids" in setup, "ExpeditionSetup must expose the agreed frozen profession_talent_ids map.")
	if "profession_talent_ids" in setup:
		setup.diver_id = survivor.id
		setup.diver_profession = "rybak"
		setup.diver_secondary_profession = ""
		setup.day = state.day
		setup.set("profession_talent_ids", {"rybak": "unknown_talent"})
		state.current_day_plan.expedition_setup = setup
		_assert(_errors_contain(state.persistence_validation_errors(), "Nieznany talent zawodowy"), "Expedition snapshots must reject talent IDs outside the catalog.")


func _test_selected_diver_and_carry_persistence_contract() -> void:
	var state = _state()
	state.current_day_plan.selected_diver_id = "igor"
	var valid_diver_errors: PackedStringArray = state.persistence_validation_errors()
	_assert(not _errors_contain(valid_diver_errors, "Wybrany nurek"), "A present, free and dive-capable selected diver must pass persistence validation.")

	var unknown_diver = state.duplicate(true)
	unknown_diver.current_day_plan.selected_diver_id = "missing_diver"
	_assert(_errors_contain(unknown_diver.persistence_validation_errors(), "nie istnieje"), "A selected diver ID must resolve to a survivor.")

	var isolated_diver = state.duplicate(true)
	isolated_diver.current_day_plan.isolated_survivor_ids.append("igor")
	_assert(_errors_contain(isolated_diver.persistence_validation_errors(), "objęty izolacją"), "An isolated survivor cannot remain the selected diver.")

	var assigned_diver = state.duplicate(true)
	var house = _add_community_house(assigned_diver, 2)
	house.assigned_survivor_ids.append("igor")
	assigned_diver.find_survivor("igor").current_assignment = house.id
	assigned_diver.current_day_plan.sync_from_state(assigned_diver)
	assigned_diver.current_day_plan.selected_diver_id = "igor"
	var assigned_errors: PackedStringArray = assigned_diver.persistence_validation_errors()
	_assert(
		_errors_contain(assigned_errors, "pozostaje w rosterze")
		and _errors_contain(assigned_errors, "niepusty odwrotny przydział"),
		"A selected diver must be absent from every building roster and have an empty reverse assignment."
	)

	var incapable_diver = state.duplicate(true)
	incapable_diver.find_survivor("igor").hunger = 65
	_assert(_errors_contain(incapable_diver.persistence_validation_errors(), "can_dive"), "A selected diver must continue to satisfy can_dive().")

	var carry_state = _state()
	var setup = ExpeditionSetupScript.new()
	setup.diver_id = "igor"
	setup.diver_profession = "nurek"
	setup.day = carry_state.day
	setup.station_staffed_carry_multiplier = 1.0
	setup.diver_carry_capacity = 18.0
	carry_state.current_day_plan.expedition_setup = setup
	var base_carry_errors: PackedStringArray = carry_state.persistence_validation_errors()
	_assert(
		not _errors_contain(base_carry_errors, "station_staffed_carry_multiplier")
		and not _errors_contain(base_carry_errors, "diver_carry_capacity"),
		"The unstaffed 1.0 multiplier and a positive finite carry capacity must be valid."
	)
	setup.station_staffed_carry_multiplier = 1.05
	_assert(not _errors_contain(carry_state.persistence_validation_errors(), "station_staffed_carry_multiplier"), "The exact staffed 1.05 multiplier must be valid.")
	setup.station_staffed_carry_multiplier = 1.02
	setup.diver_carry_capacity = 0.0
	var invalid_carry_errors: PackedStringArray = carry_state.persistence_validation_errors()
	_assert(
		_errors_contain(invalid_carry_errors, "station_staffed_carry_multiplier")
		and _errors_contain(invalid_carry_errors, "diver_carry_capacity"),
		"A multiplier outside {1.0, 1.05} and a non-positive carry capacity must be rejected."
	)
	setup.station_staffed_carry_multiplier = INF
	setup.diver_carry_capacity = NAN
	var nonfinite_carry_errors: PackedStringArray = carry_state.persistence_validation_errors()
	_assert(
		_errors_contain(nonfinite_carry_errors, "station_staffed_carry_multiplier")
		and _errors_contain(nonfinite_carry_errors, "diver_carry_capacity"),
		"Non-finite frozen carry values must be rejected."
	)


func _state():
	var state = GameStateScript.new()
	state.setup_new_campaign(12_012, DifficultyProfileScript.new())
	state.tutorial.complete()
	return state


func _add_community_house(state, level: int):
	var existing = state.find_building_by_definition("community_house")
	if existing != null:
		existing.level = level
		existing.is_built = true
		existing.pending_level = 0
		existing.condition = 100
		state.current_day_plan.sync_from_state(state)
		return existing
	var building = BuildingStateScript.new()
	building.id = "test_community_house"
	building.definition_id = "community_house"
	building.slot_id = "top_right"
	building.level = level
	building.is_built = true
	building.pending_level = 0
	building.condition = 100
	state.buildings.append(building)
	var slot_data: Dictionary = state.platform.slot_states[building.slot_id]
	slot_data["building_id"] = building.id
	state.platform.slot_states[building.slot_id] = slot_data
	state.current_day_plan.sync_from_state(state)
	return building


func _errors_contain(errors, fragment: String) -> bool:
	for error in errors:
		if str(error).contains(fragment):
			return true
	return false


func _cleanup() -> void:
	var absolute_path := ProjectSettings.globalize_path(ROUNDTRIP_PATH)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Profession talent system test failed: " + message)
