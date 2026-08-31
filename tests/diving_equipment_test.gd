extends SceneTree

const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const DiveSessionStateScript := preload("res://scripts/data/DiveSessionState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const ProductionSystemScript := preload("res://base_workbench/systems/ProductionSystem.gd")
const DivingEquipmentSystemScript := preload("res://scripts/diving/DivingEquipmentSystem.gd")
const ExpeditionPreparationSystemScript := preload("res://scripts/diving/ExpeditionPreparationSystem.gd")
const WorkerAssignmentSystemScript := preload("res://base_workbench/systems/WorkerAssignmentSystem.gd")
const EndOfDayResolverScript := preload("res://scripts/campaign/EndOfDayResolver.gd")
const LightSystemScript := preload("res://scripts/diving/LightSystem.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const LanternMk1 := preload("res://data/diving_gear/diving_lantern_mk1.tres")
const LanternMk2 := preload("res://data/diving_gear/diving_lantern_mk2.tres")
const DiveLighting := preload("res://data/balance/dive_lighting.tres")
const OxygenTankMk1 := preload("res://data/diving_gear/oxygen_tank_mk1.tres")
const OxygenTankMk2 := preload("res://data/diving_gear/oxygen_tank_mk2.tres")
const OxygenTankMk3 := preload("res://data/diving_gear/oxygen_tank_mk3.tres")
const HarpoonPistol := preload("res://data/diving_gear/harpoon_pistol.tres")

var _failed := false

func _initialize() -> void:
	var state = GameStateScript.new()
	state.setup_new_campaign(1402, DifficultyProfileScript.new())
	state.tutorial.complete()
	_assert(state.diving_equipment.owns("diving_lantern_mk1"), "A new campaign must own the emergency lantern.")
	_assert(state.diving_equipment.get_equipped("light") == "diving_lantern_mk1", "The emergency lantern must start equipped.")
	_assert(state.diving_equipment.owns("oxygen_tank_mk1"), "A new campaign must own Oxygen Tank I.")
	_assert(state.diving_equipment.get_equipped("oxygen_tank") == "oxygen_tank_mk1", "Oxygen Tank I must start equipped.")
	_assert(OxygenTankMk1.tier == 1 and OxygenTankMk1.oxygen_capacity == 100.0, "Oxygen Tank I must define the starting 100-unit capacity.")
	_assert(OxygenTankMk2.tier == 2 and OxygenTankMk2.oxygen_capacity == 130.0, "Oxygen Tank II must define a 130-unit capacity.")
	_assert(OxygenTankMk3.tier == 3 and OxygenTankMk3.oxygen_capacity == 160.0, "Oxygen Tank III must define a 160-unit capacity.")

	for resource_id in ResourceIdsScript.all():
		state.resources.set_amount(resource_id, 100)
	var workshop = _add_staffed_workshop(state, 1)
	var production = ProductionSystemScript.new()
	var lantern_recipe = production.get_recipe("diving_lantern_mk2")
	var tank_mk2_recipe = production.get_recipe("oxygen_tank_mk2")
	var tank_mk3_recipe = production.get_recipe("oxygen_tank_mk3")
	var harpoon_recipe = production.get_recipe("harpoon_pistol")
	_assert(lantern_recipe != null and lantern_recipe.required_workshop_level == 1, "Lantern II recipe must be available to Workshop I.")
	_assert(LanternMk1.light_inner_radius < LanternMk2.light_inner_radius and LanternMk1.light_outer_radius < LanternMk2.light_outer_radius and LanternMk1.light_energy < LanternMk2.light_energy, "Lantern I must remain weaker in range and energy than the Workshop I Lantern II upgrade.")
	_assert(tank_mk2_recipe != null and tank_mk2_recipe.required_workshop_level == 2, "Oxygen Tank II must require Workshop II.")
	_assert(tank_mk2_recipe.prerequisite_gear_id == "oxygen_tank_mk1" and tank_mk2_recipe.craft_cost == {"fabric_rubber": 3, "scrap": 5, "tech_parts": 2}, "Oxygen Tank II must require Tank I and use the confirmed cost.")
	_assert(tank_mk3_recipe != null and tank_mk3_recipe.required_workshop_level == 3, "Oxygen Tank III must require Workshop III.")
	_assert(tank_mk3_recipe.prerequisite_gear_id == "oxygen_tank_mk2" and tank_mk3_recipe.craft_cost == {"fabric_rubber": 5, "scrap": 8, "tech_parts": 4}, "Oxygen Tank III must require Tank II and use the confirmed cost.")
	_assert(HarpoonPistol.is_valid_weapon() and harpoon_recipe != null and harpoon_recipe.required_workshop_level == 2 and harpoon_recipe.required_work_points == 200, "The harpoon pistol must be a valid 200-point Workshop II weapon.")
	_assert(harpoon_recipe.craft_cost == {"fabric_rubber": 3, "scrap": 6, "tech_parts": 2}, "The harpoon pistol must reserve its confirmed fixed material cost.")
	_assert(not production.can_queue_recipe(state, workshop, tank_mk2_recipe), "Workshop I must not queue Oxygen Tank II even when materials and Tank I are available.")
	workshop.level = 2
	_assert(not production.can_queue_recipe(state, workshop, tank_mk3_recipe), "Workshop II must not bypass the Tank II prerequisite or Workshop III requirement.")

	var scrap_before: int = state.resources.get_amount(ResourceIdsScript.SCRAP)
	var fabric_before: int = state.resources.get_amount(ResourceIdsScript.FABRIC_RUBBER)
	var tech_before: int = state.resources.get_amount(ResourceIdsScript.TECH_PARTS)
	_assert(production.queue_recipe(state, workshop, tank_mk2_recipe), "A staffed Workshop II should queue Oxygen Tank II when materials and Tank I are available.")
	_assert(not state.diving_equipment.owns("oxygen_tank_mk2"), "Queued Oxygen Tank II must not exist before day resolution.")
	_assert(workshop.queued_production_orders.size() == 1 and workshop.queued_production_orders[0].recipe_id == "oxygen_tank_mk2", "The Oxygen Tank II order must persist as a canonical Workshop snapshot.")
	_assert(state.resources.get_amount(ResourceIdsScript.SCRAP) == scrap_before - 5, "Oxygen Tank II must reserve five scrap when queued.")
	_assert(state.resources.get_amount(ResourceIdsScript.FABRIC_RUBBER) == fabric_before - 3, "Oxygen Tank II must reserve three fabric and rubber when queued.")
	_assert(state.resources.get_amount(ResourceIdsScript.TECH_PARTS) == tech_before - 2, "Oxygen Tank II must reserve two technical parts when queued.")

	EndOfDayResolverScript.new().resolve(state, null, false)
	_resume_planning_after_direct_resolution(state)
	_assert(state.diving_equipment.owns("oxygen_tank_mk2"), "Oxygen Tank II must be added to persistent equipment after day resolution.")
	_assert(workshop.queued_production_orders.is_empty(), "Completed production must leave the workshop queue.")
	_assert(not production.can_queue_recipe(state, workshop, tank_mk3_recipe), "Owning Tank II must not let Workshop II queue the level-three recipe.")
	workshop.level = 3
	scrap_before = state.resources.get_amount(ResourceIdsScript.SCRAP)
	fabric_before = state.resources.get_amount(ResourceIdsScript.FABRIC_RUBBER)
	tech_before = state.resources.get_amount(ResourceIdsScript.TECH_PARTS)
	_assert(production.queue_recipe(state, workshop, tank_mk3_recipe), "A staffed Workshop III should queue Oxygen Tank III after Tank II is complete.")
	_assert(state.resources.get_amount(ResourceIdsScript.SCRAP) == scrap_before - 8, "Oxygen Tank III must reserve eight scrap when queued.")
	_assert(state.resources.get_amount(ResourceIdsScript.FABRIC_RUBBER) == fabric_before - 5, "Oxygen Tank III must reserve five fabric and rubber when queued.")
	_assert(state.resources.get_amount(ResourceIdsScript.TECH_PARTS) == tech_before - 4, "Oxygen Tank III must reserve four technical parts when queued.")
	EndOfDayResolverScript.new().resolve(state, null, false)
	_resume_planning_after_direct_resolution(state)
	_assert(state.diving_equipment.owns("oxygen_tank_mk3"), "Oxygen Tank III must be added to persistent equipment after day resolution.")
	_assert(workshop.queued_production_orders.is_empty(), "Completed Tank III production must leave the workshop queue.")

	var equipment = DivingEquipmentSystemScript.new()
	_assert(equipment.equip(state, "oxygen_tank_mk2"), "An owned Oxygen Tank II should be equippable.")
	var loadout := equipment.build_loadout(state)
	_assert(str(loadout.get("oxygen_tank", "")) == "oxygen_tank_mk2", "The expedition loadout must receive the equipped Oxygen Tank II.")
	var station = _add_staffed_diving_station(state, 1)
	var station_definition = ResourceLoader.load("res://base_workbench/data/buildings/diving_station.tres")
	var preparation = ExpeditionPreparationSystemScript.new()
	_assert(preparation.select_diver(state, station, station_definition, "igor"), "Igor must be selected independently from the staffed Diving Station through ExpeditionPreparationSystem.")
	var analysis := preparation.analyze(state, station, station_definition)
	_assert(analysis.get("oxygen_tank_id", "") == "oxygen_tank_mk2" and is_equal_approx(float(analysis.get("oxygen_tank_capacity", 0.0)), 130.0), "Expedition analysis must use the equipped Tank II definition.")
	_assert(is_equal_approx(float(analysis.get("oxygen_capacity", 0.0)), 155.0), "Igor with Tank II must receive 155 oxygen after personal and specialist bonuses.")
	_assert(bool(analysis.get("station_support_assigned", false)) and is_equal_approx(float(analysis.get("station_staffed_carry_multiplier", 0.0)), 1.05), "A separate capable Station worker must provide the frozen five-percent carry support.")
	station.level = 4
	var level_four_analysis := preparation.analyze(state, station, station_definition)
	_assert(is_equal_approx(float(level_four_analysis.get("oxygen_capacity", 0.0)), 155.0), "Upgrading the Diving Station must not increase oxygen capacity when Tank II stays equipped.")
	_assert(equipment.equip(state, "oxygen_tank_mk3"), "An owned Oxygen Tank III should be equippable.")
	var setup = preparation.build_setup(state, station, station_definition)
	_assert(setup != null and setup.oxygen_tank_capacity == 160.0, "ExpeditionSetup must snapshot the equipped Tank III capacity.")
	_assert(is_equal_approx(setup.oxygen_capacity, 185.0), "Igor with Tank III must receive 185 oxygen after personal and specialist bonuses.")
	_assert(str(setup.equipped_gear.get("oxygen_tank", "")) == "oxygen_tank_mk3", "ExpeditionSetup must carry Oxygen Tank III in the equipment snapshot.")

	_assert(production.queue_recipe(state, workshop, lantern_recipe), "A staffed Workshop III should still queue Lantern II.")
	EndOfDayResolverScript.new().resolve(state, null, false)
	_resume_planning_after_direct_resolution(state)
	_assert(state.diving_equipment.owns("diving_lantern_mk2"), "Lantern II must remain craftable alongside the tank progression.")
	_assert(equipment.equip(state, "diving_lantern_mk2"), "An owned Lantern II should be equippable.")
	_assert(state.diving_equipment.remove_gear("oxygen_tank_mk2"), "The duplicate-recovery regression needs Tank II to be absent from base equipment first.")
	var refund_resources_before := {
		ResourceIdsScript.SCRAP: state.resources.get_amount(ResourceIdsScript.SCRAP),
		ResourceIdsScript.FABRIC_RUBBER: state.resources.get_amount(ResourceIdsScript.FABRIC_RUBBER),
		ResourceIdsScript.TECH_PARTS: state.resources.get_amount(ResourceIdsScript.TECH_PARTS),
	}
	_assert(production.queue_recipe(state, workshop, tank_mk2_recipe), "A replacement Tank II should be queueable while the lost original is absent.")
	var recovered_replacement = DiveResultScript.new()
	recovered_replacement.diver_id = "igor"
	recovered_replacement.health_remaining = state.find_survivor("igor").health
	recovered_replacement.recovered_gear_ids.assign(["oxygen_tank_mk2"])
	var refund_report = EndOfDayResolverScript.new().resolve(state, recovered_replacement, false)
	_resume_planning_after_direct_resolution(state)
	_assert(state.diving_equipment.owns("oxygen_tank_mk2"), "Recovering the original Tank II must restore it before queued production resolves.")
	_assert(workshop.queued_production_orders.is_empty(), "A redundant queued Tank II must be removed after the original is recovered.")
	_assert(
		state.resources.get_amount(ResourceIdsScript.SCRAP) == int(refund_resources_before[ResourceIdsScript.SCRAP])
		and state.resources.get_amount(ResourceIdsScript.FABRIC_RUBBER) == int(refund_resources_before[ResourceIdsScript.FABRIC_RUBBER])
		and state.resources.get_amount(ResourceIdsScript.TECH_PARTS) == int(refund_resources_before[ResourceIdsScript.TECH_PARTS]),
		"Cancelling redundant Tank II production must refund every reserved material exactly once."
	)
	_assert(_contains_fragment(refund_report.warnings, "zarezerwowane materiały zwrócono"), "The day report must explain why redundant production was cancelled and refunded.")
	_assert(production.queue_recipe(state, workshop, harpoon_recipe), "A staffed Workshop III should queue the Workshop II harpoon pistol.")
	EndOfDayResolverScript.new().resolve(state, null, false)
	_resume_planning_after_direct_resolution(state)
	_assert(state.diving_equipment.owns("harpoon_pistol") and equipment.equip(state, "harpoon_pistol"), "Completed harpoon production must create equippable persistent weapon gear.")
	_assert(preparation.select_diver(state, station, station_definition, "igor"), "A fresh day plan must require and accept selecting Igor again before building the next ExpeditionSetup.")
	var armed_setup = preparation.build_setup(state, station, station_definition)
	_assert(str(armed_setup.equipped_gear.get("weapon", "")) == "harpoon_pistol" and armed_setup.selected_gear.has("harpoon_pistol"), "ExpeditionSetup must freeze the equipped harpoon pistol.")

	var ambient := CanvasModulate.new()
	var point_light := PointLight2D.new()
	root.add_child(ambient)
	root.add_child(point_light)
	var lighting = LightSystemScript.new()
	_assert(DiveLighting.validation_errors().is_empty(), "The production depth-lighting definition must pass its own validation.")
	var shallow_color: Color = lighting.ambient_color_for_depth(8.0, DiveLighting)
	var shallow_boundary_color: Color = lighting.ambient_color_for_depth(DiveLighting.shallow_visibility_max_depth, DiveLighting)
	var transition_color: Color = lighting.ambient_color_for_depth(70.0, DiveLighting)
	var deep_boundary_color: Color = lighting.ambient_color_for_depth(DiveLighting.deep_darkness_min_depth, DiveLighting)
	var deep_color: Color = lighting.ambient_color_for_depth(160.0, DiveLighting)
	var shallow_after_jump: Color = lighting.ambient_color_for_depth(8.0, DiveLighting)
	_assert(DiveLighting.deep_darkness_min_depth >= 150.0, "Ambient exposure must fade across the broad world depth instead of collapsing inside R3.")
	_assert(_channel_spread(DiveLighting.shallow_ambient_color) <= 0.001 and _channel_spread(DiveLighting.deep_ambient_color) <= 0.001, "CanvasModulate must stay achromatic so spectral absorption has exactly one owner: water.")
	_assert(shallow_color.is_equal_approx(DiveLighting.shallow_ambient_color) and shallow_boundary_color.is_equal_approx(shallow_color), "The whole first-region depth range must retain the authored shallow ambient.")
	_assert(_luminance(shallow_color) > _luminance(transition_color) and _luminance(transition_color) > _luminance(deep_color), "Ambient visibility must darken monotonically through the authored depth transition.")
	_assert(deep_boundary_color.is_equal_approx(DiveLighting.deep_ambient_color) and deep_color.is_equal_approx(deep_boundary_color), "The deepest region must retain the authored deep ambient after the transition endpoint.")
	_assert(_luminance(deep_color) / _luminance(shallow_color) >= 0.55, "The deepest ambient must preserve readable midtones instead of crushing the world into black.")
	var previous_ambient_luminance := _luminance(lighting.ambient_color_for_depth(0.0, DiveLighting))
	for sampled_depth in range(5, 166, 5):
		var sampled_luminance := _luminance(lighting.ambient_color_for_depth(float(sampled_depth), DiveLighting))
		_assert(sampled_luminance <= previous_ambient_luminance + 0.0001, "Ambient exposure must remain monotonic at every sampled depth.")
		_assert(previous_ambient_luminance - sampled_luminance <= 0.035, "Ambient exposure must not create a visible depth band between neighboring samples.")
		previous_ambient_luminance = sampled_luminance
	_assert(shallow_after_jump.is_equal_approx(shallow_color), "Jumping deep and back to shallow depth must restore the exact stateless ambient color.")
	_assert(LanternMk1.light_inner_radius > 125.0 and LanternMk1.light_outer_radius > 300.0, "Lantern I should use the increased starting visibility range.")
	_assert(LanternMk1.light_outer_radius < LanternMk2.light_outer_radius, "Lantern II must remain the longer-range upgrade.")
	_assert(lighting.configure(ambient, point_light, LanternMk1, false, DiveLighting, 8.0), "Lantern I should configure the underwater light rig even while switched off.")
	var mk1_scale := point_light.texture_scale
	var mk1_energy := point_light.energy
	var mk1_color := point_light.color
	_assert(not point_light.enabled and point_light.texture != null, "A configured but switched-off diver light must keep its rig without emitting light.")
	_assert(is_equal_approx(point_light.height, 96.0), "The diver light should use a visible virtual height for normal-mapped 2D relief.")
	_assert(point_light.shadow_enabled and point_light.shadow_item_cull_mask == 1, "The diver light should retain terrain-only shadows.")
	_assert(point_light.shadow_filter == Light2D.SHADOW_FILTER_PCF13 and is_equal_approx(point_light.shadow_filter_smooth, 1.5), "High quality should use the authored PCF13 shadow profile.")
	lighting.apply_graphics_quality(point_light, "low")
	_assert(point_light.shadow_filter == Light2D.SHADOW_FILTER_PCF5 and is_equal_approx(point_light.shadow_filter_smooth, 2.0), "Low quality should retain a lightweight soft-shadow profile without hard terrain wedges.")
	lighting.apply_graphics_quality(point_light, "medium")
	_assert(point_light.shadow_filter == Light2D.SHADOW_FILTER_PCF13 and is_equal_approx(point_light.shadow_filter_smooth, 2.0), "Medium quality should use the smooth PCF13 shadow profile.")
	lighting.apply_graphics_quality(point_light, "high")
	_assert(point_light.shadow_filter == Light2D.SHADOW_FILTER_PCF13 and is_equal_approx(point_light.shadow_filter_smooth, 1.5), "Returning to high quality should restore PCF13 deterministically.")
	_assert(is_equal_approx(point_light.texture_scale, mk1_scale) and is_equal_approx(point_light.energy, mk1_energy) and point_light.color.is_equal_approx(mk1_color), "Graphics quality must not change lantern range, energy or color.")
	_assert(ambient.color.is_equal_approx(DiveLighting.shallow_ambient_color), "The first region must remain readable independently of the lantern state.")
	_assert(lighting.set_light_enabled(point_light, LanternMk1, true) and point_light.enabled, "An equipped Lantern I must be switchable on.")
	_assert(not lighting.set_light_enabled(point_light, LanternMk1, false) and not point_light.enabled, "An equipped Lantern I must be switchable off.")
	_assert(lighting.configure(ambient, point_light, LanternMk2, true, DiveLighting, 120.0), "Lantern II should configure the same reusable light rig.")
	_assert(point_light.texture_scale > mk1_scale, "Lantern II must produce a larger visibility radius than Lantern I.")
	_assert(not lighting.configure(ambient, point_light, null, true, DiveLighting, 120.0) and not point_light.enabled, "Missing equipped light data must never fall back to Lantern I or emit light.")

	var light_session = DiveSessionStateScript.new()
	light_session.begin(setup)
	_assert(light_session.light_enabled, "A valid equipped light must start each dive attempt switched on.")
	light_session.light_enabled = false
	light_session.reset_attempt()
	_assert(light_session.light_enabled, "Retrying an attempt must restore the equipped light's initial on state.")
	var no_light_setup = setup.duplicate(true)
	no_light_setup.equipped_gear.erase("light")
	var no_light_session = DiveSessionStateScript.new()
	no_light_session.begin(no_light_setup)
	_assert(not no_light_session.light_enabled, "A setup without an equipped light must start and remain without local light.")
	ambient.queue_free()
	point_light.queue_free()

	var death = DiveResultScript.new()
	var entry_landmark_id: String = str(state.underwater_world.blueprint.entry_landmark_id)
	death.diver_id = "igor"
	death.returned_alive = false
	death.diver_dead = true
	death.body_location_if_dead = entry_landmark_id
	death.backpack_location_if_lost = "%s@100,100" % entry_landmark_id
	death.lost_gear.assign(["diving_lantern_mk2", "oxygen_tank_mk3", "harpoon_pistol", "diving_lantern_mk1", "oxygen_tank_mk1", "knife"])
	EndOfDayResolverScript.new().resolve(state, death, false)
	_assert(not state.diving_equipment.owns("diving_lantern_mk2"), "A crafted lantern carried by a dead diver must be removed from base equipment.")
	_assert(state.diving_equipment.get_equipped("light") == "diving_lantern_mk1", "Losing an upgraded lantern must restore the emergency Lantern I fallback.")
	_assert(not state.diving_equipment.owns("oxygen_tank_mk3"), "A crafted oxygen tank carried by a dead diver must be removed from base equipment.")
	_assert(state.diving_equipment.get_equipped("oxygen_tank") == "oxygen_tank_mk1", "Losing an upgraded oxygen tank must restore the emergency Tank I fallback.")
	_assert(not state.diving_equipment.owns("harpoon_pistol") and state.diving_equipment.get_equipped("weapon").is_empty(), "A crafted harpoon pistol carried by a dead diver must leave the base loadout.")
	var lost_backpack: Dictionary = state.underwater_world.lost_backpacks.get("igor", {})
	var lost_backpack_gear: Array = lost_backpack.get("gear_ids", [])
	_assert(lost_backpack_gear.size() == 3 and lost_backpack_gear.has("diving_lantern_mk2") and lost_backpack_gear.has("oxygen_tank_mk3") and lost_backpack_gear.has("harpoon_pistol"), "The death backpack must contain crafted light, tank and weapon upgrades that were actually removed from base equipment.")
	_assert(not lost_backpack_gear.has("diving_lantern_mk1") and not lost_backpack_gear.has("oxygen_tank_mk1") and not lost_backpack_gear.has("knife"), "Emergency defaults and Station tools must not be duplicated into a lost backpack.")

	var transfer_state = GameStateScript.new()
	transfer_state.setup_new_campaign(1404, DifficultyProfileScript.new())
	transfer_state.tutorial.complete()
	var transfer_entry_landmark_id: String = str(transfer_state.underwater_world.blueprint.entry_landmark_id)
	transfer_state.underwater_world.lost_backpacks["first_diver"] = {
		"diver_id": "first_diver",
		"landmark_id": transfer_entry_landmark_id,
		"world_position": Vector2(400, 300),
		"items": {},
		"gear_ids": ["oxygen_tank_mk2"],
		"lost_on_day": 1,
		"recovered": false,
	}
	var transfer_death = DiveResultScript.new()
	transfer_death.diver_id = "mira"
	transfer_death.returned_alive = false
	transfer_death.diver_dead = true
	transfer_death.body_location_if_dead = transfer_entry_landmark_id
	transfer_death.backpack_location_if_lost = "%s@500,350" % transfer_entry_landmark_id
	transfer_death.death_world_position = Vector2(500, 350)
	transfer_death.recovered_backpacks["first_diver"] = {
		"items": {},
		"gear_ids": [],
		"recovered": true,
	}
	transfer_death.recovered_gear_ids.assign(["oxygen_tank_mk2"])
	transfer_death.lost_gear.assign(["oxygen_tank_mk2", "oxygen_tank_mk1", "knife"])
	EndOfDayResolverScript.new().resolve(transfer_state, transfer_death, false)
	var emptied_backpack: Dictionary = transfer_state.underwater_world.lost_backpacks.get("first_diver", {})
	var transferred_backpack: Dictionary = transfer_state.underwater_world.lost_backpacks.get("mira", {})
	_assert(emptied_backpack.get("gear_ids", []).is_empty() and bool(emptied_backpack.get("recovered", false)), "Recovering Tank II must remove it from the first lost backpack before the result is resolved.")
	_assert(transferred_backpack.get("gear_ids", []) == ["oxygen_tank_mk2"], "A recovered Tank II carried by a diver who then dies must transfer to the new lost backpack exactly once.")

	var empty_death_state = GameStateScript.new()
	empty_death_state.setup_new_campaign(1405, DifficultyProfileScript.new())
	empty_death_state.tutorial.complete()
	var empty_entry_landmark_id: String = str(empty_death_state.underwater_world.blueprint.entry_landmark_id)
	var empty_death = DiveResultScript.new()
	empty_death.diver_id = "anka"
	empty_death.returned_alive = false
	empty_death.diver_dead = true
	empty_death.body_location_if_dead = empty_entry_landmark_id
	empty_death.backpack_location_if_lost = "%s@120,120" % empty_entry_landmark_id
	empty_death.death_world_position = Vector2(120, 120)
	empty_death.lost_gear.assign(["diving_lantern_mk1", "oxygen_tank_mk1", "knife"])
	EndOfDayResolverScript.new().resolve(empty_death_state, empty_death, false)
	var empty_backpack: Dictionary = empty_death_state.underwater_world.lost_backpacks.get("anka", {})
	_assert(bool(empty_backpack.get("recovered", false)), "A death with no loot or recoverable upgrades must not leave a permanently respawning empty backpack.")

	if _failed:
		quit(1)
		return
	print("Diving equipment test passed: starting Tank I, Workshop II-III crafting chain, capacity progression, Station independence, persistence, equipping and death transfers/fallbacks work.")
	quit(0)

func _add_staffed_workshop(state, level: int):
	var workshop = BuildingStateScript.new()
	workshop.id = "test_workshop"
	workshop.definition_id = "workshop"
	workshop.slot_id = "bottom_left"
	workshop.level = level
	workshop.is_built = true
	workshop.assigned_survivor_ids.assign(["anka"])
	state.buildings.append(workshop)
	var slot_data: Dictionary = state.platform.slot_states["bottom_left"]
	slot_data["building_id"] = workshop.id
	state.platform.slot_states["bottom_left"] = slot_data
	return workshop

func _add_staffed_diving_station(state, level: int):
	var station = BuildingStateScript.new()
	station.id = "test_diving_station"
	station.definition_id = "diving_station"
	station.slot_id = "bottom_right"
	station.level = level
	station.is_built = true
	state.buildings.append(station)
	var slot_data: Dictionary = state.platform.slot_states["bottom_right"]
	slot_data["building_id"] = station.id
	state.platform.slot_states["bottom_right"] = slot_data
	_assert(WorkerAssignmentSystemScript.new().assign_worker_to_slot(state, station.id, 0, "mira", 1), "The fixture must assign a separate capable worker to Diving Station support.")
	return station

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Diving equipment test failed: " + message)

func _contains_fragment(lines: Array[String], fragment: String) -> bool:
	for line in lines:
		if fragment in line:
			return true
	return false

func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722

func _channel_spread(color: Color) -> float:
	return maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b))

func _resume_planning_after_direct_resolution(state) -> void:
	state.pending_settlement_event = null
	state.settlement_event_roll_day = int(state.day)
	state.current_phase = GamePhaseScript.Phase.BASE_PLANNING
	state.begin_new_day_plan()
