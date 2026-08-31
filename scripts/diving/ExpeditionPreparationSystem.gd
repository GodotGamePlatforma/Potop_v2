class_name ExpeditionPreparationSystem
extends RefCounted

const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const CampaignProgressionSystemScript := preload("res://scripts/campaign/CampaignProgressionSystem.gd")
const DivingEquipmentSystemScript := preload("res://scripts/diving/DivingEquipmentSystem.gd")
const MissionSystemScript := preload("res://scripts/campaign/MissionSystem.gd")
const SuitSystemScript := preload("res://scripts/diving/SuitSystem.gd")
const WorkPaceSystemScript := preload("res://base_workbench/systems/WorkPaceSystem.gd")

var _equipment_system = DivingEquipmentSystemScript.new()
var _mission_system = MissionSystemScript.new()
var _suit_system = SuitSystemScript.new()
var _work_pace_system = WorkPaceSystemScript

func analyze(state, station, definition) -> Dictionary:
	var difficulty_modifiers := _difficulty_modifiers(state)
	var work_pace := _work_pace_system.pace_for_building(state, station)
	var work_pace_multiplier := _work_pace_system.output_multiplier(work_pace)
	var station_level := maxi(int(station.level), 1) if station != null else 1
	var operator_rescue_max_distance := ExpeditionSetupScript.DEFAULT_OPERATOR_RESCUE_MAX_DISTANCE * work_pace_multiplier
	var suit_repair_amount := int(round(float(_suit_system.repair_amount(station_level)) * work_pace_multiplier))
	difficulty_modifiers["operator_rescue_max_distance"] = operator_rescue_max_distance
	var base_suit_damage_multiplier := float(difficulty_modifiers.get("suit_damage_multiplier", 1.0))
	var result := {
		"ready": false,
		"reason": "Brak aktywnej Stacji Nurkowej.",
		"diver": null,
		"oxygen_capacity": 0.0,
		"oxygen_tank_id": "",
		"oxygen_tank_capacity": 0.0,
		"specialist_oxygen_bonus": 0.0,
		"specialist_oxygen_multiplier": 1.0,
		"carry_capacity": 0.0,
		"station_staffed": false,
		"station_support_assigned": false,
		"station_staffed_carry_multiplier": 1.0,
		"diver_carry_capacity": 0.0,
		"backpack_capacity": 0,
		"capabilities": {},
		"entry_points": [],
		"selected_entry_point": "",
		"entry_point_selection_reason": "Brak dostępnego wejścia do wody.",
		"operator_assigned": false,
		"operator_survivor_id": "",
		"operator_assignment_reason": "Operator nie jest wymagany na tym poziomie Stacji.",
		"operator_rescue_chance": float(difficulty_modifiers.get("operator_rescue_chance", 0.0)),
		"operator_rescue_available": false,
		"operator_rescue_effective_chance": 0.0,
		"operator_rescue_max_distance": operator_rescue_max_distance,
		"work_pace": work_pace,
		"work_pace_label": _work_pace_system.pace_label(work_pace),
		"work_pace_multiplier": work_pace_multiplier,
		"suit_repair_amount": suit_repair_amount,
		"technician_assigned": false,
		"technician_survivor_id": "",
		"technician_assignment_reason": "Technik nie jest wymagany na tym poziomie Stacji.",
		"repair_kit_charges": 1,
		"technician_suit_damage_multiplier": 1.0,
		"technician_suit_damage_reduction": 0.0,
		"suit_damage_multiplier": base_suit_damage_multiplier,
		"difficulty_modifiers": difficulty_modifiers,
	}
	if state == null or station == null or definition == null or not station.is_active():
		return result
	var level_definition = definition.get_level_definition(station.level)
	var capabilities: Dictionary = level_definition.capabilities if level_definition != null else {}
	result.capabilities = capabilities
	result.backpack_capacity = int(capabilities.get("backpack_slots", 6))
	result.entry_points = _available_entry_points(state, capabilities)
	result.selected_entry_point = _selected_entry_point(state, result.entry_points)
	if result.entry_points.is_empty():
		result.entry_point_selection_reason = "Brak dostępnego wejścia do wody."
	elif result.entry_points.size() > 1:
		result.entry_point_selection_reason = ""
	elif bool(capabilities.get("buoy_start_enabled", false)):
		result.entry_point_selection_reason = "Ustaw boję podczas wyprawy, aby odblokować dodatkowe wejście."
	else:
		result.entry_point_selection_reason = "Stacja Nurkowa IV odblokowuje wybór wejścia z ustawionych boi."
	if not bool(capabilities.get("can_dive", false)):
		result.reason = "Bieżący poziom Stacji nie pozwala rozpocząć wyprawy."
		return result
	var selected_diver_id := str(state.current_day_plan.selected_diver_id) if state.current_day_plan != null else ""
	if selected_diver_id.is_empty():
		result.reason = "Wybierz wolnego mieszkańca z listy nurków."
		return result
	var diver = state.find_survivor(selected_diver_id)
	result.diver = diver
	if diver != null:
		var station_staff = _capable_support_worker(state, station, 0, str(diver.id))
		result.station_staffed = station_staff != null
		result.station_support_assigned = result.station_staffed
		result.station_staffed_carry_multiplier = float(capabilities.get("staffed_diver_carry_multiplier", 1.0)) if result.station_staffed else 1.0
		result.carry_capacity = diver.get_carry_capacity() * float(result.station_staffed_carry_multiplier)
		result.diver_carry_capacity = result.carry_capacity
		var operator = _capable_support_worker(state, station, 1, str(diver.id))
		var technician = _capable_support_worker(state, station, 2, str(diver.id))
		if operator != null and technician != null and str(operator.id) == str(technician.id):
			technician = null
		result.operator_assigned = bool(capabilities.get("operator_rescue_enabled", false)) and operator != null
		result.technician_assigned = bool(capabilities.get("technician_support_enabled", false)) and technician != null
		if bool(capabilities.get("operator_rescue_enabled", false)):
			result.operator_assignment_reason = _support_worker_reason(state, station, 1, str(diver.id), "Operator")
		if bool(capabilities.get("technician_support_enabled", false)):
			result.technician_assignment_reason = _support_worker_reason(state, station, 2, str(diver.id), "Technik")
		result.operator_survivor_id = str(operator.id) if result.operator_assigned else ""
		result.technician_survivor_id = str(technician.id) if result.technician_assigned else ""
		result.operator_rescue_available = result.operator_assigned and _operator_rescue_supported_at_entry(state, str(result.selected_entry_point))
		result.operator_rescue_effective_chance = float(result.operator_rescue_chance) if result.operator_rescue_available else 0.0
		if result.technician_assigned:
			var technician_multiplier := float(capabilities.get("technician_suit_damage_multiplier", 0.9))
			result.repair_kit_charges = 2
			result.technician_suit_damage_multiplier = technician_multiplier
			result.technician_suit_damage_reduction = clampf(1.0 - technician_multiplier, 0.0, 1.0)
			result.suit_damage_multiplier = base_suit_damage_multiplier * technician_multiplier
			difficulty_modifiers["suit_damage_multiplier"] = result.suit_damage_multiplier
	var diver_blocker := diver_selection_blocker(state, station, definition, selected_diver_id)
	if not diver_blocker.is_empty():
		result.reason = diver_blocker
		return result
	if state.diving_equipment == null:
		result.reason = "Brak stanu wyposażenia nurkowego."
		return result
	var oxygen_tank_id: String = state.diving_equipment.get_equipped("oxygen_tank")
	var oxygen_tank_definition = _equipment_system.equipped_definition(state, "oxygen_tank")
	if oxygen_tank_definition == null or not state.diving_equipment.owns(oxygen_tank_id) or str(oxygen_tank_definition.equipment_slot) != "oxygen_tank" or float(oxygen_tank_definition.oxygen_capacity) <= 0.0:
		result.reason = "Wyposaż sprawną butlę tlenową."
		return result
	var oxygen_tank_capacity := float(oxygen_tank_definition.oxygen_capacity)
	result.oxygen_tank_id = oxygen_tank_id
	result.oxygen_tank_capacity = oxygen_tank_capacity
	var specialist_bonus := float(definition.get_specialist_bonus_value(diver, "oxygen_bonus"))
	var specialist_multiplier := float(definition.get_specialist_bonus_value(diver, "oxygen_capacity_multiplier", 1.0))
	result.specialist_oxygen_bonus = specialist_bonus
	result.specialist_oxygen_multiplier = specialist_multiplier
	result.oxygen_capacity = diver.get_expedition_oxygen_capacity(oxygen_tank_capacity, specialist_bonus, specialist_multiplier)
	var light_id: String = state.diving_equipment.get_equipped("light")
	if light_id.is_empty() or not state.diving_equipment.owns(light_id):
		result.reason = "Wyposaż sprawne źródło światła."
		return result
	if state.tutorial != null and state.tutorial.is_active() and diver.id != "igor":
		result.reason = "Pierwsze nurkowanie tutoriala musi wykonać Igor Sowa."
		return result
	result.ready = true
	result.reason = "Gotowy do wyprawy."
	return result

func build_setup(state, station, definition, item_definitions: Dictionary = {}):
	var analysis := analyze(state, station, definition)
	if not bool(analysis.get("ready", false)):
		return null
	var diver = analysis.diver
	var capabilities: Dictionary = analysis.capabilities
	var setup = ExpeditionSetupScript.new()
	setup.capture_diver(
		diver,
		float(analysis.oxygen_tank_capacity),
		float(analysis.specialist_oxygen_bonus),
		float(analysis.specialist_oxygen_multiplier),
		float(analysis.station_staffed_carry_multiplier)
	)
	if setup.has_method("capture_item_weights"):
		setup.capture_item_weights(item_definitions)
		var weight_multiplier := maxf(float(state.difficulty_profile.backpack_weight_multiplier), 0.01) if state.difficulty_profile != null else 1.0
		for item_id in setup.item_weights.keys():
			setup.item_weights[item_id] = float(setup.item_weights[item_id]) * weight_multiplier
	setup.day = state.day
	setup.selected_gear.assign(["crowbar", "repair_kit"])
	if state.story_flags != null and bool(state.story_flags.rescue_knife_unlocked):
		setup.selected_gear.append("knife")
	if state.story_flags != null and bool(state.story_flags.archive_terminal_active):
		setup.selected_gear.append("r3_diagnostic_access")
	if state.story_flags != null and bool(state.story_flags.r3_regulator_ready) and not bool(state.story_flags.r3_generator_active):
		setup.selected_gear.append("r3_regulator")
	if state.story_flags != null and bool(state.story_flags.r3_generator_active) and not bool(state.story_flags.c4_switchboard_active):
		setup.selected_gear.append("c4_control_access")
	if state.story_flags != null and bool(state.story_flags.common_line_splitter_ready) and not bool(state.story_flags.common_line_splitter_installed):
		setup.selected_gear.append("common_line_splitter")
	setup.equipped_gear = _equipment_system.build_loadout(state)
	for gear_id in setup.equipped_gear.values():
		if not setup.selected_gear.has(str(gear_id)):
			setup.selected_gear.append(str(gear_id))
	var weapon_id := str(setup.equipped_gear.get("weapon", ""))
	if not weapon_id.is_empty():
		var weapon_definition = ResourceLoader.load("res://data/diving_gear/%s.tres" % weapon_id)
		if weapon_definition != null:
			setup.weapon_ammunition = maxi(int(weapon_definition.ammunition_per_dive), 0)
	setup.backpack_capacity = int(analysis.backpack_capacity)
	setup.suit_quality = station.level
	setup.base_support_level = station.level
	setup.station_work_pace_multiplier = float(analysis.work_pace_multiplier)
	setup.suit_repair_amount = int(analysis.suit_repair_amount)
	setup.can_place_buoys = bool(capabilities.get("buoy_enabled", false))
	setup.can_start_from_buoy = bool(capabilities.get("buoy_start_enabled", false))
	setup.can_mark_heavy_objects = bool(capabilities.get("heavy_marking_enabled", false))
	setup.buoy_charges = 1 if setup.can_place_buoys else 0
	setup.start_entry_point = str(analysis.selected_entry_point)
	setup.target_sector = _main_entry_landmark_id(state)
	setup.tutorial_mode = state.tutorial != null and state.tutorial.is_active()
	if setup.tutorial_mode:
		setup.tutorial_baseline_step = int(state.tutorial.step)
		setup.selected_objective = "junction_j7_tutorial" if state.story_flags != null and bool(state.story_flags.rescue_knife_unlocked) else "first_dive_tutorial"
	else:
		var campaign_guidance := _common_line_expedition_guidance(state)
		if not campaign_guidance.is_empty():
			setup.selected_objective = str(campaign_guidance.get("objective_id", "common_line"))
			setup.objective_title = str(campaign_guidance.get("title", ""))
			setup.objective_guidance = str(campaign_guidance.get("guidance", ""))
			setup.objective_target_landmark_id = str(campaign_guidance.get("landmark_id", ""))
			setup.objective_target_label = str(campaign_guidance.get("landmark_label", ""))
		else:
			var mission_guidance: Dictionary = _mission_system.expedition_guidance(state)
			if not _guidance_target_is_available(state, mission_guidance):
				mission_guidance = {}
			var mission_id := str(mission_guidance.get("mission_id", ""))
			setup.selected_objective = mission_id if not mission_id.is_empty() else "basic_scavenge"
			setup.objective_title = str(mission_guidance.get("title", ""))
			setup.objective_guidance = str(mission_guidance.get("guidance", ""))
			setup.objective_target_landmark_id = str(mission_guidance.get("landmark_id", ""))
			setup.objective_target_label = str(mission_guidance.get("landmark_label", ""))
	setup.operator_assigned = bool(analysis.operator_assigned)
	setup.technician_assigned = bool(analysis.technician_assigned)
	setup.operator_survivor_id = str(analysis.operator_survivor_id)
	setup.technician_survivor_id = str(analysis.technician_survivor_id)
	var analysis_modifiers: Dictionary = analysis.get("difficulty_modifiers", {})
	setup.difficulty_modifiers = analysis_modifiers.duplicate(true)
	if setup.can_mark_heavy_objects and not setup.selected_gear.has("lift_bag"):
		setup.selected_gear.append("lift_bag")
	return setup


func diver_selection_blocker(state, station, definition, survivor_id: String) -> String:
	if state == null:
		return "Brak aktywnego stanu kampanii."
	if state.has_method("day_plan_edit_blocker"):
		var plan_blocker := str(state.day_plan_edit_blocker())
		if not plan_blocker.is_empty():
			return plan_blocker
	if station == null or definition == null or not station.is_active():
		return "Brak aktywnej Stacji Nurkowej."
	var level_definition = definition.get_level_definition(station.level)
	var capabilities: Dictionary = level_definition.capabilities if level_definition != null else {}
	if not bool(capabilities.get("can_dive", false)):
		return "Bieżący poziom Stacji nie pozwala rozpocząć wyprawy."
	var diver = state.find_survivor(survivor_id)
	if diver == null or not diver.is_present_in_settlement():
		return "Mieszkaniec nie jest obecny w Przystani."
	if not str(diver.current_assignment).is_empty():
		return "%s jest już obsadzony w budynku i nie może równocześnie nurkować." % str(diver.display_name)
	if _is_isolated_in_plan(state, survivor_id):
		return "%s jest w izolacji i nie może nurkować." % str(diver.display_name)
	if not diver.can_dive():
		return str(diver.dive_blocker()) if diver.has_method("dive_blocker") else "Mieszkaniec nie może nurkować."
	if state.tutorial != null and state.tutorial.is_active() and survivor_id != "igor":
		return "Pierwsze nurkowanie tutoriala musi wykonać Igor Sowa."
	return ""


func select_diver(state, station, definition, survivor_id: String) -> bool:
	if not diver_selection_blocker(state, station, definition, survivor_id).is_empty():
		return false
	if state.current_day_plan == null or not state.current_day_plan.set_selected_diver(survivor_id):
		return false
	state.set_preferred_diver(survivor_id)
	return true


func clear_selected_diver(state) -> bool:
	if state == null or state.current_day_plan == null:
		return false
	if state.has_method("day_plan_edit_blocker") and not str(state.day_plan_edit_blocker()).is_empty():
		return false
	if not state.current_day_plan.clear_selected_diver():
		return false
	state.clear_preferred_diver()
	return true


func _common_line_expedition_guidance(state) -> Dictionary:
	if state == null or state.story_flags == null:
		return {}
	var story = state.story_flags
	if (
		not str(story.game_over_reason).is_empty()
		or not str(story.final_outcome_id).is_empty()
		or bool(story.energy_choice_pending)
		or bool(story.black_front_arrived)
		or not bool(story.black_front_active)
	):
		return {}
	if bool(story.junction_j7_active) and not bool(story.archive_map_transmitted):
		return _fixed_device_guidance(state, CampaignProgressionSystemScript.ARCHIVE_TERMINAL_DEVICE_ID, {
			"objective_id": "common_line_archive",
			"title": "MAPA WSPÓLNEJ LINII",
			"guidance": "Dotrzyj do Zalanego Archiwum, uruchom terminal, prześlij mapę i wróć do aktywnej liny.",
			"landmark_label": "Zalane Archiwum",
		})
	if bool(story.archive_map_transmitted) and not bool(story.r3_diagnosed):
		return _fixed_device_guidance(state, CampaignProgressionSystemScript.R3_DIAGNOSTIC_DEVICE_ID, {
			"objective_id": "common_line_r3_diagnostic",
			"title": "DIAGNOSTYKA GENERATORA R-3",
			"guidance": "Dotrzyj do Generatora R-3, otwórz panel diagnostyczny i wróć do aktywnej liny.",
			"landmark_label": "Generator R-3",
		})
	if bool(story.r3_regulator_ready) and not bool(story.r3_generator_active):
		return _fixed_device_guidance(state, CampaignProgressionSystemScript.R3_GENERATOR_DEVICE_ID, {
			"objective_id": "common_line_r3_activation",
			"title": "URUCHOM GENERATOR R-3",
			"guidance": "Wróć do Generatora R-3, zamontuj Regulator R-3, uruchom urządzenie i wróć do aktywnej liny.",
			"landmark_label": "Generator R-3",
		})
	if bool(story.r3_generator_active) and not bool(story.c4_switchboard_active):
		return _fixed_device_guidance(state, CampaignProgressionSystemScript.C4_SWITCHBOARD_DEVICE_ID, {
			"objective_id": "common_line_c4_activation",
			"title": "URUCHOM ROZDZIELNIĘ C-4",
			"guidance": "Dotrzyj do Rozdzielni C-4, uruchom panel awaryjny i wróć do aktywnej liny.",
			"landmark_label": "Rozdzielnia C-4",
		})
	if bool(story.common_line_splitter_ready) and not bool(story.common_line_splitter_installed):
		return _fixed_device_guidance(state, CampaignProgressionSystemScript.COMMON_LINE_SPLITTER_DEVICE_ID, {
			"objective_id": "common_line_splitter_installation",
			"title": "ZAMONTUJ ROZDZIELACZ",
			"guidance": "Wróć do Rozdzielni C-4, zamontuj Rozdzielacz Wspólnej Linii i wróć do aktywnej liny.",
			"landmark_label": "Rozdzielnia C-4",
		})
	return {}

func _fixed_device_guidance(state, device_id: String, guidance: Dictionary) -> Dictionary:
	var result := guidance.duplicate(true)
	result["landmark_id"] = ""
	var placement := _fixed_device_placement(state, device_id)
	if placement.is_empty():
		return result
	result["landmark_id"] = str(placement.get("landmark_id", ""))
	result["landmark_label"] = str(placement.get("landmark_label", ""))
	return result

func _guidance_target_is_available(state, guidance: Dictionary) -> bool:
	return _landmark_is_available(state, str(guidance.get("landmark_id", "")))

func _fixed_device_placement(state, device_id: String) -> Dictionary:
	var blueprint = _blueprint_for(state)
	if blueprint == null or device_id.is_empty():
		return {}
	for record in blueprint.fixed_device_spawns:
		if not (record is Dictionary) or str(record.get("id", "")) != device_id:
			continue
		var landmark_id := str(record.get("landmark_id", "")).strip_edges()
		if landmark_id.is_empty():
			return {}
		var resolved_id := str(blueprint.resolve_landmark_id(landmark_id)) if blueprint.has_method("resolve_landmark_id") else ""
		if resolved_id.is_empty():
			return {}
		var landmark: Dictionary = blueprint.get_landmark(resolved_id) if blueprint.has_method("get_landmark") else {}
		return {
			"landmark_id": resolved_id,
			"landmark_label": str(record.get("display_name", landmark.get("display_name", ""))),
		}
	return {}

func _blueprint_for(state):
	if state == null or not ("underwater_world" in state) or state.underwater_world == null:
		return null
	return state.underwater_world.blueprint

func _main_entry_landmark_id(state) -> String:
	var blueprint = _blueprint_for(state)
	return str(blueprint.entry_landmark_id) if blueprint != null else ""

func _landmark_is_available(state, landmark_id: String) -> bool:
	var normalized_id := landmark_id.strip_edges()
	if normalized_id.is_empty():
		return true
	var blueprint = _blueprint_for(state)
	if blueprint == null or not blueprint.has_method("resolve_landmark_id"):
		return false
	return not str(blueprint.resolve_landmark_id(normalized_id)).is_empty()

func _capable_support_worker(state, station, slot_index: int, diver_id: String):
	if not _support_worker_reason(state, station, slot_index, diver_id, "Wsparcie").is_empty():
		return null
	var survivor_id := str(station.assigned_survivor_ids[slot_index])
	var survivor = state.find_survivor(survivor_id)
	return survivor


func _support_worker_reason(state, station, slot_index: int, diver_id: String, role_label: String) -> String:
	if state == null or station == null:
		return "%s nie ma aktywnej Stacji." % role_label
	if slot_index < 0 or slot_index >= station.assigned_survivor_ids.size():
		return "%s nie jest przydzielony." % role_label
	var survivor_id := str(station.assigned_survivor_ids[slot_index])
	if survivor_id.is_empty() or survivor_id == diver_id:
		return "%s nie jest przydzielony do osobnego stanowiska." % role_label
	var survivor = state.find_survivor(survivor_id)
	if survivor == null or str(survivor.current_assignment) != str(station.id):
		return "%s nie ma poprawnego przydziału do Stacji." % role_label
	if _is_isolated_in_plan(state, survivor_id):
		return "%s jest w izolacji i nie może pełnić wsparcia." % str(survivor.display_name)
	if not survivor.can_work():
		return str(survivor.work_blocker()) if survivor.has_method("work_blocker") else "%s nie może pracować." % role_label
	return ""


func _is_isolated_in_plan(state, survivor_id: String) -> bool:
	return (
		state != null
		and state.current_day_plan != null
		and survivor_id in state.current_day_plan.isolated_survivor_ids
	)

func _operator_rescue_supported_at_entry(state, entry_point_id: String) -> bool:
	var main_entry_id := _main_entry_landmark_id(state)
	return not main_entry_id.is_empty() and entry_point_id == main_entry_id

func _available_entry_points(state, capabilities: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state == null or state.underwater_world == null or state.underwater_world.blueprint == null:
		return result
	var blueprint = state.underwater_world.blueprint
	var main_entry: Dictionary = blueprint.get_landmark(blueprint.entry_landmark_id)
	result.append({
		"id": str(blueprint.entry_landmark_id),
		"label": str(main_entry.get("display_name", "Główna lina")),
		"kind": "main_line",
	})
	if not bool(capabilities.get("buoy_start_enabled", false)):
		return result
	for buoy_id in state.underwater_world.placed_buoys:
		var buoy_definition: Dictionary = {}
		for candidate in blueprint.buoy_spawns:
			if str(candidate.get("id", "")) == str(buoy_id):
				buoy_definition = candidate
				break
		var landmark: Dictionary = blueprint.get_landmark(str(buoy_definition.get("entry_landmark_id", "")))
		if landmark.is_empty():
			continue
		result.append({
			"id": str(landmark.get("id", "")),
			"label": "Boja %s • %s" % [str(buoy_id), str(landmark.get("display_name", "wejście"))],
			"kind": "buoy",
		})
	return result

func _selected_entry_point(state, entry_points: Array[Dictionary]) -> String:
	if entry_points.is_empty():
		return str(state.underwater_world.blueprint.entry_landmark_id) if state != null and state.underwater_world != null and state.underwater_world.blueprint != null else ""
	var requested := ""
	if state != null and state.current_day_plan != null:
		requested = str(state.current_day_plan.expedition_entry_point)
	for entry in entry_points:
		if str(entry.get("id", "")) == requested:
			return requested
	return str(entry_points[0].get("id", ""))

func _difficulty_modifiers(state) -> Dictionary:
	if state == null or state.difficulty_profile == null:
		return {}
	return {
		"oxygen_use_multiplier": float(state.difficulty_profile.oxygen_use_multiplier),
		"suit_damage_multiplier": float(state.difficulty_profile.suit_damage_multiplier),
		"cold_rate_multiplier": float(state.difficulty_profile.cold_rate_multiplier),
		"threat_aggression_multiplier": float(state.difficulty_profile.threat_aggression_multiplier),
		"current_strength_multiplier": float(state.difficulty_profile.current_strength_multiplier),
		"noise_range_multiplier": float(state.difficulty_profile.noise_range_multiplier),
		"backpack_weight_multiplier": float(state.difficulty_profile.backpack_weight_multiplier),
		"loot_density_multiplier": float(state.difficulty_profile.loot_density_multiplier),
		"operator_rescue_chance": float(state.difficulty_profile.operator_rescue_chance),
	}
