extends SceneTree

const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const DiveSessionStateScript := preload("res://scripts/data/DiveSessionState.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const GameStateScript := preload("res://scripts/data/GameState.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const OxygenSystemScript := preload("res://scripts/diving/OxygenSystem.gd")
const LootSystemScript := preload("res://scripts/diving/LootSystem.gd")
const EndOfDayResolverScript := preload("res://scripts/base/EndOfDayResolver.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")
const GamePhaseScript := preload("res://scripts/core/GamePhase.gd")
const DiverScene := preload("res://diver_workbench/runtime/Diver.tscn")
const DiveCurrentVisualScript := preload("res://scripts/diving/DiveCurrentVisual.gd")
const InputPromptScript := preload("res://scripts/ui/InputPrompt.gd")
const CompetencySystemScript := preload("res://scripts/base/CompetencySystem.gd")
const ContinuousDiveWorldScript := preload("res://scripts/diving/ContinuousDiveWorld.gd")
const WorldBlueprintScript := preload("res://scripts/data/WorldBlueprint.gd")
const PersistentInteractableScript := preload("res://scripts/diving/DivePersistentInteractable.gd")
const SectorPersistenceSystemScript := preload("res://scripts/diving/SectorPersistenceSystem.gd")


class StructureResetProbe:
	extends Node

	var reset_calls := 0

	func reset_attempt() -> void:
		reset_calls += 1


class StructureCurrentProbe:
	extends Node

	var contribution := Vector2.ZERO
	var sampled_positions: Array[Vector2] = []

	func _init(initial_contribution: Vector2 = Vector2.ZERO) -> void:
		contribution = initial_contribution

	func current_at_world_position(world_position: Vector2) -> Vector2:
		sampled_positions.append(world_position)
		return contribution


class StructureGateProbe:
	extends Node

	var gate_open := false
	var requested_gates: Array[StringName] = []

	func is_public_gate_open(gate_id: StringName) -> bool:
		requested_gates.append(gate_id)
		return gate_open and gate_id == &"attempt_complete"

	func reset_attempt() -> void:
		gate_open = false

var _failed := false

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var setup = ExpeditionSetupScript.new()
	setup.diver_id = "igor"
	setup.oxygen_capacity = 100.0
	setup.diver_health = 82
	setup.diver_health_capacity = 120
	setup.backpack_capacity = 2
	setup.diver_carry_capacity = 30.0
	setup.item_weights = {
		ResourceIdsScript.FOOD: 1.0,
		ResourceIdsScript.PLANKS: 1.2,
		ResourceIdsScript.SCRAP: 1.5,
	}
	setup.tutorial_mode = true

	var session = DiveSessionStateScript.new()
	session.begin(setup)
	_assert(session.oxygen_left == 100.0, "Session should begin with the configured oxygen.")
	_assert(session.health == 82 and session.health_capacity == 120, "Session should receive the diver health snapshot.")
	_assert(session.add_item(ResourceIdsScript.FOOD, 6) == 6, "First resource should enter the backpack.")
	_assert(session.add_item(ResourceIdsScript.FOOD, 2) == 2, "Existing stacks should not consume another slot.")
	_assert(session.add_item(ResourceIdsScript.PLANKS, 4) == 4, "Second resource should use the second slot.")
	_assert(session.add_item(ResourceIdsScript.SCRAP, 3) == 0, "A full backpack should reject a new resource type.")
	session.opened_containers.append("fixture_container")
	session.collected_world_item_ids.append("fixture_container:food")
	session.reset_attempt()
	_assert(session.carried_items.is_empty(), "Retry should discard all loot from the failed attempt.")
	_assert(session.opened_containers.is_empty(), "Retry should restore containers opened during the attempt.")
	_assert(session.collected_world_item_ids.is_empty(), "Retry should restore freestanding items collected during the attempt.")
	_assert(session.oxygen_left == 100.0, "Retry should refill oxygen.")
	_assert(session.health == 82, "Retry should restore health to the start-of-dive snapshot.")
	var structure_reset_world = ContinuousDiveWorldScript.new()
	var structure_reset_probe := StructureResetProbe.new()
	structure_reset_world.structure_controllers.append(structure_reset_probe)
	structure_reset_world.call("_reset_structure_controllers")
	_assert(
		structure_reset_probe.reset_calls == 1,
		"Attempt reset must call each registered structure controller exactly once.",
	)
	structure_reset_probe.free()
	structure_reset_world.free()
	var structure_current_world = ContinuousDiveWorldScript.new()
	var current_blueprint = WorldBlueprintScript.new()
	var current_zones: Array[Dictionary] = [
		{"rect": Rect2(0.0, 0.0, 80.0, 80.0), "velocity": Vector2(10.0, 20.0)},
		{"rect": Rect2(0.0, 0.0, 80.0, 80.0), "velocity": Vector2(100.0, 200.0)},
	]
	current_blueprint.current_zones = current_zones
	structure_current_world._blueprint = current_blueprint
	var position_in_base_current := Vector2(20.0, 20.0)
	_assert(
		structure_current_world.current_at(position_in_base_current) == Vector2(10.0, 20.0),
		"Overlapping base currents must retain first-match precedence.",
	)
	var first_current_probe := StructureCurrentProbe.new(Vector2(3.0, -2.0))
	var second_current_probe := StructureCurrentProbe.new(Vector2(-1.0, 5.0))
	var controller_without_current_hook := Node.new()
	var current_controllers: Array[Node] = [
		first_current_probe,
		controller_without_current_hook,
		second_current_probe,
	]
	structure_current_world.structure_controllers.assign(current_controllers)
	_assert(
		structure_current_world.current_at(position_in_base_current) == Vector2(12.0, 23.0),
		"Structure current contributions must add to the first matching base current.",
	)
	var position_outside_base_current := Vector2(120.0, 120.0)
	_assert(
		structure_current_world.current_at(position_outside_base_current) == Vector2(2.0, 3.0),
		"Structure currents must remain active outside global base-current zones.",
	)
	for probe in [first_current_probe, second_current_probe]:
		_assert(
			probe.sampled_positions == [position_in_base_current, position_outside_base_current],
			"Each opted-in structure controller must receive every unchanged world sample exactly once.",
		)
	structure_current_world.structure_controllers.clear()
	first_current_probe.free()
	second_current_probe.free()
	controller_without_current_hook.free()
	structure_current_world.free()

	var structure_gate_world = ContinuousDiveWorldScript.new()
	var structure_gate_probe := StructureGateProbe.new()
	structure_gate_world._structure_controllers_by_id["fixture_structure"] = structure_gate_probe
	var linked_blueprint = WorldBlueprintScript.new()
	var linked_fixed_devices: Array[Dictionary] = [{
		"id": "future_fixture_device",
		"available_from_day": 99,
		"unlocks_shortcut_id": "fixture_shortcut",
	}]
	linked_blueprint.fixed_device_spawns = linked_fixed_devices
	structure_gate_world._blueprint = linked_blueprint
	var gated_device = PersistentInteractableScript.new()
	gated_device.configure(
		PersistentInteractableScript.Kind.FIXED_DEVICE,
		"fixture_device",
		"Fixture device",
		false,
	)
	gated_device.set_unlocks_shortcut_id("fixture_shortcut")
	gated_device.set_availability_gate(
		Callable(structure_gate_world, "_structure_gate_is_open").bind(
			"fixture_structure",
			&"attempt_complete",
		)
	)
	_assert(not gated_device.can_interact(), "A public structure device must fail closed before its generic gate opens.")
	structure_gate_probe.gate_open = true
	_assert(gated_device.can_interact(), "A public structure device must become interactable when its generic gate opens.")
	_assert(
		structure_gate_probe.requested_gates == [&"attempt_complete", &"attempt_complete"],
		"Root must query only the declared public gate, without reading private structure state.",
	)
	var linked_shortcut = PersistentInteractableScript.new()
	linked_shortcut.configure(
		PersistentInteractableScript.Kind.SHORTCUT,
		"fixture_shortcut",
		"Fixture shortcut",
		false,
	)
	linked_shortcut.set_direct_interaction_allowed(
		not bool(structure_gate_world.call("_is_linked_shortcut_target", "fixture_shortcut"))
	)
	var ordinary_shortcut = PersistentInteractableScript.new()
	ordinary_shortcut.configure(
		PersistentInteractableScript.Kind.SHORTCUT,
		"ordinary_shortcut",
		"Ordinary shortcut",
		false,
	)
	ordinary_shortcut.set_direct_interaction_allowed(
		not bool(structure_gate_world.call("_is_linked_shortcut_target", "ordinary_shortcut"))
	)
	_assert(
		not linked_shortcut.can_interact() and ordinary_shortcut.can_interact(),
		"A linked shortcut must reject direct interaction even before its future device becomes available, while ordinary shortcuts remain usable.",
	)
	structure_gate_world.persistent_interactables.append(linked_shortcut)
	var linked_session = DiveSessionStateScript.new()
	linked_session.begin(setup)
	var sector_persistence = SectorPersistenceSystemScript.new()
	var invalid_device = PersistentInteractableScript.new()
	invalid_device.configure(
		PersistentInteractableScript.Kind.FIXED_DEVICE,
		" ",
		"Invalid device",
		false,
	)
	invalid_device.set_unlocks_shortcut_id("fixture_shortcut")
	_assert(
		not sector_persistence.record_fixed_device_completion_for_attempt(
			linked_session,
			structure_gate_world,
			invalid_device.persistent_id,
			invalid_device.unlocks_shortcut_id,
		)
		and not linked_shortcut.completed,
		"An empty device ID must fail before opening its physical shortcut.",
	)
	_assert(
		sector_persistence.record_fixed_device_completion_for_attempt(
			linked_session,
			structure_gate_world,
			gated_device.persistent_id,
			gated_device.unlocks_shortcut_id,
		),
		"A linked fixed device must atomically resolve its existing shortcut.",
	)
	_assert(
		linked_session.activated_fixed_devices == ["fixture_device"]
		and linked_session.opened_shortcuts == ["fixture_shortcut"]
		and linked_session.safe_return_only_activated_fixed_devices == ["fixture_device"]
		and linked_session.safe_return_only_opened_shortcuts == ["fixture_shortcut"]
		and linked_shortcut.completed,
		"The local dive result must receive the device and shortcut once while the physical gate opens immediately.",
	)
	_assert(
		sector_persistence.record_fixed_device_completion_for_attempt(
			linked_session,
			structure_gate_world,
			gated_device.persistent_id,
			gated_device.unlocks_shortcut_id,
		)
		and linked_session.activated_fixed_devices.size() == 1
		and linked_session.opened_shortcuts.size() == 1,
		"Repeating a linked completion must remain idempotent.",
	)
	var missing_shortcut_device = PersistentInteractableScript.new()
	missing_shortcut_device.configure(
		PersistentInteractableScript.Kind.FIXED_DEVICE,
		"fixture_missing_device",
		"Missing shortcut fixture",
		false,
	)
	missing_shortcut_device.set_unlocks_shortcut_id("missing_shortcut")
	_assert(
		not sector_persistence.record_fixed_device_completion_for_attempt(
			linked_session,
			structure_gate_world,
			missing_shortcut_device.persistent_id,
			missing_shortcut_device.unlocks_shortcut_id,
		)
		and not linked_session.activated_fixed_devices.has("fixture_missing_device")
		and not linked_session.opened_shortcuts.has("missing_shortcut"),
		"A missing public shortcut must fail atomically without partial session state.",
	)
	linked_session.activated_fixed_devices.append("ordinary_device")
	linked_session.opened_shortcuts.append("ordinary_shortcut")
	var safe_result = DiveResultScript.new()
	sector_persistence.populate_result(linked_session, safe_result)
	_assert(
		safe_result.activated_fixed_devices == ["fixture_device", "ordinary_device"]
		and safe_result.opened_shortcuts == ["fixture_shortcut", "ordinary_shortcut"],
		"A normal safe return must carry both linked and ordinary world effects.",
	)
	var death_result = DiveResultScript.new()
	death_result.returned_alive = false
	death_result.diver_dead = true
	sector_persistence.populate_result(linked_session, death_result)
	_assert(
		death_result.activated_fixed_devices == ["ordinary_device"]
		and death_result.opened_shortcuts == ["ordinary_shortcut"],
		"Death must discard only safe-return-linked effects and preserve existing ordinary persistence semantics.",
	)
	var extraction_result = DiveResultScript.new()
	extraction_result.emergency_extraction = true
	sector_persistence.populate_result(linked_session, extraction_result)
	_assert(
		extraction_result.activated_fixed_devices == ["ordinary_device"]
		and extraction_result.opened_shortcuts == ["ordinary_shortcut"],
		"Emergency extraction must not commit effects that require a physical safe return.",
	)
	var linked_world = GameStateScript.new().underwater_world
	var first_apply: Dictionary = sector_persistence.apply_result(linked_world, safe_result)
	var second_apply: Dictionary = sector_persistence.apply_result(linked_world, safe_result)
	_assert(
		linked_world.activated_fixed_devices.count("fixture_device") == 1
		and linked_world.opened_shortcuts.count("fixture_shortcut") == 1
		and int(first_apply.get("fixed_devices", 0)) == 2
		and int(first_apply.get("shortcuts", 0)) == 2
		and int(second_apply.get("fixed_devices", 0)) == 0
		and int(second_apply.get("shortcuts", 0)) == 0,
		"Applying a safe result repeatedly must keep every persisted ID unique.",
	)
	var restored_shortcut = PersistentInteractableScript.new()
	restored_shortcut.configure(
		PersistentInteractableScript.Kind.SHORTCUT,
		"fixture_shortcut",
		"Restored fixture shortcut",
		linked_world.opened_shortcuts.has("fixture_shortcut"),
	)
	restored_shortcut.reset_attempt()
	_assert(
		restored_shortcut.completed,
		"A later dive must restore a safely committed shortcut as open across attempt resets.",
	)
	structure_gate_probe.reset_attempt()
	_assert(
		not gated_device.can_interact(),
		"A fresh structure attempt must close its private completion gate even when the public shortcut is already persisted.",
	)
	linked_session.reset_attempt()
	linked_shortcut.reset_attempt()
	_assert(
		linked_session.activated_fixed_devices.is_empty()
		and linked_session.opened_shortcuts.is_empty()
		and linked_session.safe_return_only_activated_fixed_devices.is_empty()
		and linked_session.safe_return_only_opened_shortcuts.is_empty()
		and not linked_shortcut.completed,
		"Retry must clear both local effects and close a shortcut not yet committed by a safe return.",
	)
	structure_gate_world.persistent_interactables.clear()
	structure_gate_world._structure_controllers_by_id.clear()
	gated_device.free()
	linked_shortcut.free()
	ordinary_shortcut.free()
	restored_shortcut.free()
	invalid_device.free()
	missing_shortcut_device.free()
	structure_gate_probe.free()
	structure_gate_world.free()

	var oxygen = OxygenSystemScript.new()
	var idle_rate: float = oxygen.consumption_rate(false, false, 0.0, false)
	var swim_rate: float = oxygen.consumption_rate(true, false, 0.0, false)
	var sprint_rate: float = oxygen.consumption_rate(true, true, 1.0, true)
	_assert(idle_rate < swim_rate and swim_rate < sprint_rate, "Oxygen drain should scale from idle to swimming and loaded sprinting in a current.")
	var first_dive_seconds_hard := 125.0 / (swim_rate * 1.15)
	var tank_two_seconds_hard := 155.0 / (swim_rate * 1.15)
	var tank_three_seconds_hard := 185.0 / (swim_rate * 1.15)
	_assert(first_dive_seconds_hard >= 300.0, "The starting professional diver must have at least five minutes of continuous ordinary swimming even on Hard.")
	_assert(tank_two_seconds_hard > first_dive_seconds_hard and tank_three_seconds_hard > tank_two_seconds_hard, "Oxygen Tank II and III must extend continuous gameplay monotonically.")
	_assert(sprint_rate >= swim_rate * 2.0, "Sprint must retain a clearly visible oxygen tradeoff after extending ordinary dive time.")
	setup.competency_levels = {"swimming": 3, "oxygen_economy": 3}
	var baseline_oxygen_after := oxygen.consume(100.0, 10.0, swim_rate)
	var skilled_oxygen_after := oxygen.consume(100.0, 10.0, swim_rate * CompetencySystemScript.oxygen_use_multiplier(setup))
	_assert(skilled_oxygen_after > baseline_oxygen_after and is_equal_approx(100.0 - skilled_oxygen_after, (100.0 - baseline_oxygen_after) * 0.88), "Oxygen Economy III must reduce the canonical swimming oxygen cost by exactly 12%.")
	_assert(is_equal_approx(175.0 * CompetencySystemScript.swimming_multiplier(setup), 201.25), "Swimming III must raise the canonical ordinary swim speed from 175 to 201.25.")

	var weight_setup = ExpeditionSetupScript.new()
	weight_setup.backpack_capacity = 6
	weight_setup.diver_carry_capacity = 5.0
	weight_setup.item_weights = {
		ResourceIdsScript.FOOD: 1.0,
		ResourceIdsScript.TECH_PARTS: 2.0,
	}
	var weight_session = DiveSessionStateScript.new()
	weight_session.begin(weight_setup)
	var heavy_contents := {ResourceIdsScript.FOOD: 6}
	var transferred := LootSystemScript.new().transfer_all(weight_session, heavy_contents)
	_assert(transferred.get(ResourceIdsScript.FOOD, 0) == 5, "Loot transfer should take only the amount that fits the diver's carry capacity.")
	_assert(heavy_contents.get(ResourceIdsScript.FOOD, 0) == 1, "Loot that exceeds carry capacity should remain in its container.")
	_assert(is_equal_approx(weight_session.get_carried_weight(), 5.0), "Carried weight should be calculated from per-unit item weights.")
	_assert(is_zero_approx(weight_session.remaining_carry_capacity()), "A diver at the weight limit should have no remaining carry capacity.")
	_assert(weight_session.add_item(ResourceIdsScript.TECH_PARTS, 1) == 0, "A full weight allowance should reject further loot even when backpack slots remain.")
	_assert(not LootSystemScript.new().transfer_single(weight_session, ResourceIdsScript.FOOD), "A freestanding item should remain unavailable when the diver is at the weight limit.")
	var selective_session = DiveSessionStateScript.new()
	selective_session.begin(weight_setup)
	var selective_contents := {
		ResourceIdsScript.FOOD: 5,
		ResourceIdsScript.TECH_PARTS: 2,
	}
	var selective_transfer := LootSystemScript.new()
	_assert(selective_transfer.transfer_amount(selective_session, selective_contents, ResourceIdsScript.FOOD, 2) == 2, "A selective transfer should take exactly the requested amount when it fits.")
	_assert(selective_session.carried_items.get(ResourceIdsScript.FOOD, 0) == 2, "Selected loot should enter the diver's backpack.")
	_assert(selective_contents.get(ResourceIdsScript.FOOD, 0) == 3, "A selective transfer should leave the exact unselected remainder in the container.")
	_assert(selective_contents.get(ResourceIdsScript.TECH_PARTS, 0) == 2, "A selective transfer must not modify another item stack in the same container.")
	var slot_setup = ExpeditionSetupScript.new()
	slot_setup.backpack_capacity = 1
	slot_setup.diver_carry_capacity = 100.0
	slot_setup.item_weights = {
		ResourceIdsScript.FOOD: 1.0,
		ResourceIdsScript.PLANKS: 1.2,
	}
	var slot_session = DiveSessionStateScript.new()
	slot_session.begin(slot_setup)
	_assert(LootSystemScript.new().transfer_single(slot_session, ResourceIdsScript.FOOD), "The first freestanding item should enter an empty backpack.")
	_assert(not LootSystemScript.new().transfer_single(slot_session, ResourceIdsScript.PLANKS), "A new freestanding item type should be rejected when all slots are occupied.")
	_assert(LootSystemScript.new().transfer_single(slot_session, ResourceIdsScript.FOOD), "A full slot count should still allow another item in an existing stack.")
	_assert(slot_session.remove_item(ResourceIdsScript.FOOD, 2) == 2, "Removing an entire stack should report every removed item.")
	_assert(slot_session.slots_used() == 0 and not slot_session.carried_items.has(ResourceIdsScript.FOOD), "Removing an entire stack should free its backpack slot.")
	_assert(LootSystemScript.new().transfer_single(slot_session, ResourceIdsScript.PLANKS), "A different item type should fit in the slot freed by a discarded stack.")
	var id_setup = ExpeditionSetupScript.new()
	id_setup.diver_id = "igor"
	id_setup.day = 7
	var id_session = DiveSessionStateScript.new()
	id_session.begin(id_setup)
	var first_dropped_id: String = id_session.next_dropped_loot_id()
	var second_dropped_id: String = id_session.next_dropped_loot_id()
	_assert(first_dropped_id == "dropped_loot_7_igor_001", "The first dropped-loot ID should be stable for the expedition day and diver.")
	_assert(second_dropped_id == "dropped_loot_7_igor_002" and second_dropped_id != first_dropped_id, "Consecutive dropped-loot piles should receive unique stable sequence IDs.")
	id_session.dropped_loot_updates[first_dropped_id] = {"items": {ResourceIdsScript.FOOD: 1}}
	id_session.reset_attempt()
	_assert(id_session.dropped_loot_updates.is_empty(), "Retrying an attempt should discard every local dropped-loot update.")
	_assert(id_session.next_dropped_loot_id() == first_dropped_id, "Retrying an attempt should deterministically reset the local dropped-loot sequence.")
	_assert(_action_has_key(&"dive_interact", KEY_E), "The contextual dive action should retain the E key.")
	_assert(_action_has_key(&"dive_interact", KEY_SPACE), "The contextual dive action should also accept SPACE.")
	_assert(_action_has_key(&"dive_left", KEY_LEFT), "The remappable left action should retain LEFT as its alternative binding.")
	_assert(_action_has_key(&"dive_right", KEY_RIGHT), "The remappable right action should retain RIGHT as its alternative binding.")
	_assert(_action_has_key(&"dive_up", KEY_UP), "The remappable up action should retain UP as its alternative binding.")
	_assert(_action_has_key(&"dive_down", KEY_DOWN), "The remappable down action should retain DOWN as its alternative binding.")
	_assert(_action_has_key(&"dive_light_toggle", KEY_F), "The remappable dive-light action should use F by default.")
	_assert(_action_has_key(&"open_mission_journal", KEY_J), "The mission journal shortcut should be an InputMap action.")
	_assert(_action_has_key(&"open_day_reports", KEY_R), "The day-report shortcut should be an InputMap action.")
	_assert(InputPromptScript.action_text(&"dive_interact") == "E / SPACJA", "The visible interaction prompt should be derived from both current InputMap bindings.")
	_assert(InputPromptScript.action_text(&"dive_light_toggle") == "F", "The visible light prompt should be derived from the current remappable InputMap binding.")
	var left_key := InputEventKey.new()
	left_key.keycode = KEY_LEFT
	_assert(InputPromptScript.event_text(left_key) == "←", "Input prompts should render a Polish-friendly left-arrow glyph.")
	var space_key := InputEventKey.new()
	space_key.keycode = KEY_SPACE
	_assert(InputPromptScript.event_text(space_key) == "SPACJA", "Input prompts should render a Polish-friendly SPACE label.")
	for loot_id: String in [
		ResourceIdsScript.FOOD,
		ResourceIdsScript.PLANKS,
		ResourceIdsScript.SCRAP,
		ResourceIdsScript.FABRIC_RUBBER,
		ResourceIdsScript.TECH_PARTS,
		ResourceIdsScript.MEDS_CHEMICALS,
	]:
		var item_path := "res://data/items/%s.tres" % loot_id
		_assert(ResourceLoader.exists(item_path), "Every loot resource should have an ItemDefinition: %s." % loot_id)
		var item_definition = ResourceLoader.load(item_path)
		_assert(item_definition != null and item_definition.weight > 0.0, "Every loot item should define a positive per-unit weight: %s." % loot_id)
		if loot_id in [ResourceIdsScript.FOOD, ResourceIdsScript.PLANKS, ResourceIdsScript.SCRAP]:
			_assert(item_definition.world_pickup_texture != null, "Every freestanding resource type should define a real pickup texture: %s." % loot_id)
			_assert(item_definition.world_pickup_texture.get_size() == Vector2(128, 128), "Freestanding pickup textures should use the canonical 128 x 128 canvas: %s." % loot_id)

	var direction_cases := [
		{"vector": Vector2.RIGHT, "symbol": "→"},
		{"vector": Vector2(1, 1), "symbol": "↘"},
		{"vector": Vector2.DOWN, "symbol": "↓"},
		{"vector": Vector2(-1, 1), "symbol": "↙"},
		{"vector": Vector2.LEFT, "symbol": "←"},
		{"vector": Vector2(-1, -1), "symbol": "↖"},
		{"vector": Vector2.UP, "symbol": "↑"},
		{"vector": Vector2(1, -1), "symbol": "↗"},
	]
	for direction_case in direction_cases:
		var test_vector: Vector2 = direction_case["vector"]
		var expected_symbol: String = str(direction_case["symbol"])
		_assert(
			DiveCurrentVisualScript.direction_symbol_for_vector(test_vector) == expected_symbol,
			"The current HUD should map %s to the exact eight-direction symbol %s." % [test_vector, expected_symbol]
		)
	_assert(DiveCurrentVisualScript.direction_symbol_for_vector(Vector2.ZERO).is_empty(), "Still water should not display a current direction symbol.")
	var current_visual = DiveCurrentVisualScript.new()
	root.add_child(current_visual)
	var applied_current := Vector2(24.0, 68.0)
	var visual_anchor := Vector2(640.0, 360.0)
	current_visual.update_sample(applied_current, visual_anchor, 0.1)
	var fade_in_intensity: float = current_visual.intensity()
	_assert(current_visual.sampled_vector() == applied_current, "The current visual should retain the exact gameplay vector without changing its direction.")
	_assert(current_visual.global_position == visual_anchor and current_visual.top_level, "The current visual should be camera-anchored in world space without inheriting map transforms.")
	_assert(fade_in_intensity > 0.0 and fade_in_intensity < 1.0, "Entering a current should fade the presentation in instead of snapping it on.")
	current_visual.set_visual_time_for_tests(2.75, true)
	var frozen_time: float = current_visual.visual_time()
	current_visual.update_sample(applied_current, visual_anchor, 0.8)
	_assert(current_visual.is_test_mode() and is_equal_approx(current_visual.visual_time(), frozen_time), "Explicit current-visual test time should remain deterministic across process deltas.")
	var current_intensity: float = current_visual.intensity()
	current_visual.update_sample(Vector2.ZERO, visual_anchor, 0.1)
	_assert(current_visual.intensity() < current_intensity and current_visual.intensity() > 0.0, "Leaving a current should fade the presentation out instead of hiding it in one frame.")
	_assert(current_visual.get_child_count() == 0, "The procedural current layer should remain presentation-only and contain no physics children.")
	current_visual.queue_free()
	var diver = DiverScene.instantiate()
	_assert(diver is CharacterBody2D, "DiveScene integration must instantiate one physical diver body from the public workshop scene.")
	_assert(
		diver.has_method("simulate_motion_tick")
		and diver.has_method("reset_at")
		and diver.has_method("light_source")
		and diver.has_signal("surface_contacts_reported"),
		"The public Diver boundary must expose movement, reset, light and contact integration without publishing presentation children."
	)
	root.add_child(diver)
	await process_frame
	await physics_frame
	_assert(diver.light_source() is PointLight2D, "The public Diver boundary must provide the light consumed by root equipment systems.")
	diver.velocity = Vector2.ZERO
	var baseline_motion: Dictionary = diver.simulate_motion_tick(Vector2.RIGHT, false, Vector2.ZERO, 1.0, 1.0)
	diver.reset_at(Vector2.ZERO)
	var skilled_motion: Dictionary = diver.simulate_motion_tick(Vector2.RIGHT, false, Vector2.ZERO, CompetencySystemScript.swimming_multiplier(setup), 1.0)
	_assert(
		is_equal_approx(float(baseline_motion.velocity.x), 175.0)
		and is_equal_approx(float(skilled_motion.velocity.x), 201.25),
		"Swimming III must raise the real DiverController ordinary movement target from 175 to 201.25."
	)
	var contact_reports: Array = []
	diver.surface_contacts_reported.connect(func(contacts: Array) -> void:
		contact_reports.append(contacts)
	)
	diver.set_physics_process(false)
	var contact_wall := StaticBody2D.new()
	contact_wall.collision_layer = 1
	contact_wall.collision_mask = 0
	contact_wall.position = Vector2(90.0, 0.0)
	var contact_shape_node := CollisionShape2D.new()
	var contact_shape := RectangleShape2D.new()
	contact_shape.size = Vector2(20.0, 240.0)
	contact_shape_node.shape = contact_shape
	contact_wall.add_child(contact_shape_node)
	root.add_child(contact_wall)
	await physics_frame
	diver.reset_at(Vector2.ZERO)
	var contact_motion: Dictionary = {"collided": false}
	for _contact_tick in range(60):
		contact_motion = diver.simulate_motion_tick(
			Vector2.RIGHT,
			false,
			Vector2.ZERO,
			1.0,
			1.0 / 60.0
		)
		if bool(contact_motion.get("collided", false)):
			break
		await physics_frame
	_assert(bool(contact_motion.get("collided", false)), "Realny tick ruchu nurka musi nadal rozwiązać kontakt przez move_and_slide().")
	_assert(contact_reports.size() == 1, "Jeden tick z prostą ścianą musi zgłosić dokładnie jeden synchroniczny pakiet kontaktów prezentacyjnych.")
	if contact_reports.size() == 1:
		var reported_contacts: Array = contact_reports[0]
		_assert(reported_contacts.size() == 1, "Prosta ściana musi dostarczyć dokładnie jeden skopiowany kontakt powierzchni.")
		if reported_contacts.size() == 1:
			var reported_contact: Dictionary = reported_contacts[0]
			var reported_position: Vector2 = reported_contact.get("position", Vector2(INF, INF))
			var reported_normal: Vector2 = reported_contact.get("normal", Vector2.ZERO)
			_assert(reported_contact.get("collider", null) == contact_wall, "Kontakt prezentacyjny musi zachować rzeczywiste ciało fizyczne do filtrowania przez świat.")
			_assert(reported_position.is_finite() and reported_normal.is_normalized(), "Kontakt prezentacyjny musi kopiować skończony punkt i znormalizowaną normalną.")
			_assert(float(reported_contact.get("opposition_speed", 0.0)) > 0.0, "Kontakt prezentacyjny musi zachować dodatnią prędkość skierowaną w ścianę.")
	root.remove_child(contact_wall)
	contact_wall.free()
	diver.queue_free()

	var state = GameStateScript.new()
	state.setup_new_campaign(777, DifficultyProfileScript.new())
	for survivor in state.survivors:
		_assert(survivor.level == 1 and survivor.get_max_health() == 100 and survivor.get_oxygen_capacity() == 100.0, "Every resident should start with persistent level, health capacity and oxygen capacity.")
		_assert(is_equal_approx(survivor.get_carry_capacity(), 18.0), "Every resident should start with a persistent personal carry capacity.")
		_assert(not survivor.portrait_id.is_empty(), "Every resident should have a stable portrait identity.")
	var returning_diver = state.find_survivor("igor")
	var diving_station_definition = ResourceLoader.load("res://data/buildings/diving_station.tres")
	var diver_oxygen_bonus := float(diving_station_definition.get_specialist_bonus_value(returning_diver, "oxygen_bonus"))
	var diver_oxygen_multiplier := float(diving_station_definition.get_specialist_bonus_value(returning_diver, "oxygen_capacity_multiplier", 1.0))
	_assert(is_equal_approx(diver_oxygen_multiplier, 1.1), "The diving profession should expose a 10% personal oxygen-capacity skill.")
	_assert(is_equal_approx(returning_diver.get_expedition_oxygen_capacity(100.0, diver_oxygen_bonus, diver_oxygen_multiplier), 125.0), "The professional diver should start a level-one Station expedition with 125 oxygen.")
	var non_diver = state.find_survivor("mira")
	var non_diver_oxygen_bonus := float(diving_station_definition.get_specialist_bonus_value(non_diver, "oxygen_bonus"))
	var non_diver_oxygen_multiplier := float(diving_station_definition.get_specialist_bonus_value(non_diver, "oxygen_capacity_multiplier", 1.0))
	_assert(is_zero_approx(non_diver_oxygen_bonus) and is_equal_approx(non_diver_oxygen_multiplier, 1.0), "A resident without the diving profession should not receive either specialist oxygen bonus.")
	_assert(is_equal_approx(non_diver.get_expedition_oxygen_capacity(100.0, non_diver_oxygen_bonus, non_diver_oxygen_multiplier), 100.0), "A non-diver should retain the ordinary level-one Station oxygen capacity.")
	returning_diver.experience = 95
	state.underwater_world.remaining_container_contents["fixture_full_container"] = {ResourceIdsScript.FOOD: 1}
	var returned = DiveResultScript.new()
	returned.diver_id = "igor"
	returned.oxygen_remaining = 31.0
	returned.health_remaining = 83
	returned.experience_gained = 10
	returned.opened_containers.append("fixture_full_container")
	returned.collected_world_item_ids.append("fixture_full_container:food")
	returned.collected_world_item_ids.append("fixture_pickup")
	returned.remaining_container_contents["fixture_partial_container"] = {ResourceIdsScript.PLANKS: 2}
	returned.add_item(ResourceIdsScript.FOOD, 6)
	EndOfDayResolverScript.new().resolve(state, returned, false)
	_assert(state.underwater_world.opened_containers.has("fixture_full_container"), "Successful return should persist opened containers.")
	_assert(state.underwater_world.collected_items.has("fixture_full_container:food"), "Successful return should persist removed world loot.")
	_assert(state.underwater_world.collected_items.has("fixture_pickup"), "Successful return should persist a removed freestanding pickup by stable ID.")
	_assert(not state.underwater_world.remaining_container_contents.has("fixture_full_container"), "A fully emptied container should clear an older persisted remainder.")
	_assert(state.underwater_world.remaining_container_contents.get("fixture_partial_container", {}).get(ResourceIdsScript.PLANKS, 0) == 2, "A partial container should persist the loot that the diver could not carry.")
	_assert(returning_diver.health == 83, "A safe return should persist the session health through DiveResult.")
	_assert(returning_diver.level == 2 and returning_diver.unspent_skill_points == 1, "Dive experience should level the resident and award a development point.")
	_assert(state.current_phase == GamePhaseScript.Phase.END_DAY_REPORT, "A resolved dive should expose its day report before survivor development resumes.")
	state.current_phase = GamePhaseScript.Phase.BASE_PLANNING
	_assert(returning_diver.spend_skill_point("carry") and returning_diver.get_carry_capacity() == 22.0, "A development point should support a persistent carry-capacity upgrade.")
	returning_diver.unspent_skill_points += 1
	_assert(returning_diver.spend_skill_point("oxygen") and returning_diver.get_oxygen_capacity() == 110.0, "A development point should continue to support a persistent oxygen-capacity upgrade.")
	_assert(is_equal_approx(returning_diver.get_expedition_oxygen_capacity(100.0, diver_oxygen_bonus, diver_oxygen_multiplier), 136.0), "The diving skill should scale the diver's upgraded personal oxygen capacity by 10%.")

	var death_state = GameStateScript.new()
	death_state.setup_new_campaign(778, DifficultyProfileScript.new())
	var death_entry_landmark_id: String = str(death_state.underwater_world.blueprint.entry_landmark_id)
	var death_entry_landmark: Dictionary = death_state.underwater_world.blueprint.get_landmark(death_entry_landmark_id)
	var death_entry_label := "%s (%s)" % [str(death_entry_landmark.get("display_name", death_entry_landmark_id)), death_entry_landmark_id]
	var death = DiveResultScript.new()
	death.diver_id = "igor"
	death.returned_alive = false
	death.diver_dead = true
	death.body_location_if_dead = death_entry_landmark_id
	death.backpack_location_if_lost = "%s@900,600" % death_entry_landmark_id
	death.death_world_position = Vector2(900, 600)
	death.lost_items = {ResourceIdsScript.SCRAP: 3}
	var death_report = EndOfDayResolverScript.new().resolve(death_state, death, false)
	_assert(death_state.find_survivor("igor").status == SurvivorStateScript.Status.DEAD, "A normal zero-oxygen result should permanently kill the diver.")
	var backpack_warning := ""
	for warning in death_report.warnings:
		if str(warning).contains("Plecak"):
			backpack_warning = str(warning)
			break
	_assert(backpack_warning.contains(death_entry_label) and not backpack_warning.contains("sektorze"), "The death report should present the manifest-defined landmark instead of an obsolete sector term.")
	_assert(death_state.underwater_world.dead_divers.has("igor"), "The persistent world should remember the diver's body.")
	var lost_backpack: Dictionary = death_state.underwater_world.lost_backpacks.get("igor", {})
	_assert(lost_backpack.get("world_position", Vector2.ZERO) == Vector2(900, 600), "The persistent backpack should retain its exact world position.")
	_assert(lost_backpack.get("items", {}).get(ResourceIdsScript.SCRAP, 0) == 3 and not bool(lost_backpack.get("recovered", true)), "The persistent backpack should retain recoverable loot and recovery status.")

	if _failed:
		quit(1)
		return
	print("Dive system test passed: slots, selective loot, dropped-loot IDs, item weight, dynamic input prompts, alternative movement bindings, carry capacity, oxygen load, progression, retry, persistence and permanent death work.")
	quit(0)

func _action_has_key(action: StringName, keycode: int) -> bool:
	for input_event in InputMap.action_get_events(action):
		if input_event is InputEventKey:
			var key_event := input_event as InputEventKey
			if key_event.keycode == keycode or key_event.physical_keycode == keycode:
				return true
	return false

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Dive system test failed: " + message)
