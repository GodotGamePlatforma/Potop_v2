extends SceneTree

const DiveSessionStateScript := preload("res://scripts/data/DiveSessionState.gd")
const DiveResultScript := preload("res://scripts/data/DiveResult.gd")
const UnderwaterWorldStateScript := preload("res://scripts/data/UnderwaterWorldState.gd")
const WorldBlueprintScript := preload("res://scripts/data/WorldBlueprint.gd")
const ContinuousDiveWorldScript := preload("res://scripts/diving/ContinuousDiveWorld.gd")
const PersistentInteractableScript := preload("res://scripts/diving/DivePersistentInteractable.gd")
const SectorPersistenceSystemScript := preload("res://scripts/diving/SectorPersistenceSystem.gd")


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
	var dive_world = ContinuousDiveWorldScript.new()
	var gate_probe := StructureGateProbe.new()
	dive_world._structure_controllers_by_id["fixture_structure"] = gate_probe
	var blueprint = WorldBlueprintScript.new()
	var fixed_devices: Array[Dictionary] = [{
		"id": "future_fixture_device",
		"available_from_day": 99,
		"unlocks_shortcut_id": "fixture_shortcut",
	}]
	blueprint.fixed_device_spawns = fixed_devices
	dive_world._blueprint = blueprint

	var device = PersistentInteractableScript.new()
	device.configure(
		PersistentInteractableScript.Kind.FIXED_DEVICE,
		"fixture_device",
		"Fixture device",
		false,
	)
	device.set_unlocks_shortcut_id("fixture_shortcut")
	device.set_availability_gate(
		Callable(dive_world, "_structure_gate_is_open").bind(
			"fixture_structure",
			&"attempt_complete",
		)
	)
	_assert(not device.can_interact(), "The public device must fail closed before the generic structure gate opens.")
	gate_probe.gate_open = true
	_assert(device.can_interact(), "The public device must become usable after the generic structure gate opens.")
	_assert(
		gate_probe.requested_gates == [&"attempt_complete", &"attempt_complete"],
		"Root must query only the declared public gate.",
	)

	var linked_shortcut = PersistentInteractableScript.new()
	linked_shortcut.configure(
		PersistentInteractableScript.Kind.SHORTCUT,
		"fixture_shortcut",
		"Fixture shortcut",
		false,
	)
	linked_shortcut.set_direct_interaction_allowed(
		not bool(dive_world.call("_is_linked_shortcut_target", "fixture_shortcut"))
	)
	var ordinary_shortcut = PersistentInteractableScript.new()
	ordinary_shortcut.configure(
		PersistentInteractableScript.Kind.SHORTCUT,
		"ordinary_shortcut",
		"Ordinary shortcut",
		false,
	)
	ordinary_shortcut.set_direct_interaction_allowed(
		not bool(dive_world.call("_is_linked_shortcut_target", "ordinary_shortcut"))
	)
	_assert(
		not linked_shortcut.can_interact() and ordinary_shortcut.can_interact(),
		"A linked shortcut must reject direct interaction even before its future device is available, while ordinary shortcuts remain usable.",
	)
	dive_world.persistent_interactables.append(linked_shortcut)

	var session = DiveSessionStateScript.new()
	var persistence = SectorPersistenceSystemScript.new()
	_assert(
		not persistence.record_fixed_device_completion_for_attempt(
			session,
			dive_world,
			" ",
			"fixture_shortcut",
		)
		and not linked_shortcut.completed,
		"An empty device ID must fail before the physical shortcut opens.",
	)
	_assert(
		persistence.record_fixed_device_completion_for_attempt(
			session,
			dive_world,
			device.persistent_id,
			device.unlocks_shortcut_id,
		),
		"A linked device must atomically open its existing physical shortcut.",
	)
	_assert(
		session.activated_fixed_devices == ["fixture_device"]
		and session.opened_shortcuts == ["fixture_shortcut"]
		and session.safe_return_only_activated_fixed_devices == ["fixture_device"]
		and session.safe_return_only_opened_shortcuts == ["fixture_shortcut"]
		and linked_shortcut.completed,
		"The attempt must receive one safe-return-linked pair while the shortcut opens immediately.",
	)
	_assert(
		persistence.record_fixed_device_completion_for_attempt(
			session,
			dive_world,
			device.persistent_id,
			device.unlocks_shortcut_id,
		)
		and session.activated_fixed_devices.size() == 1
		and session.opened_shortcuts.size() == 1,
		"Repeated linked completion must remain idempotent.",
	)
	_assert(
		not persistence.record_fixed_device_completion_for_attempt(
			session,
			dive_world,
			"missing_fixture_device",
			"missing_shortcut",
		)
		and not session.activated_fixed_devices.has("missing_fixture_device")
		and not session.opened_shortcuts.has("missing_shortcut"),
		"A missing shortcut must fail without partial attempt state.",
	)

	session.activated_fixed_devices.append("ordinary_device")
	session.opened_shortcuts.append("ordinary_shortcut")
	var safe_result = DiveResultScript.new()
	persistence.populate_result(session, safe_result)
	_assert(
		safe_result.activated_fixed_devices == ["fixture_device", "ordinary_device"]
		and safe_result.opened_shortcuts == ["fixture_shortcut", "ordinary_shortcut"],
		"A normal safe return must carry linked and ordinary world effects.",
	)
	var death_result = DiveResultScript.new()
	death_result.returned_alive = false
	death_result.diver_dead = true
	persistence.populate_result(session, death_result)
	_assert(
		death_result.activated_fixed_devices == ["ordinary_device"]
		and death_result.opened_shortcuts == ["ordinary_shortcut"],
		"Death must discard only safe-return-linked effects.",
	)
	var extraction_result = DiveResultScript.new()
	extraction_result.emergency_extraction = true
	persistence.populate_result(session, extraction_result)
	_assert(
		extraction_result.activated_fixed_devices == ["ordinary_device"]
		and extraction_result.opened_shortcuts == ["ordinary_shortcut"],
		"Emergency extraction must not commit effects requiring a physical safe return.",
	)

	var world = UnderwaterWorldStateScript.new()
	var first_apply: Dictionary = persistence.apply_result(world, safe_result)
	var second_apply: Dictionary = persistence.apply_result(world, safe_result)
	_assert(
		world.activated_fixed_devices.count("fixture_device") == 1
		and world.opened_shortcuts.count("fixture_shortcut") == 1
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
		world.opened_shortcuts.has("fixture_shortcut"),
	)
	restored_shortcut.set_direct_interaction_allowed(false)
	restored_shortcut.reset_attempt()
	_assert(restored_shortcut.completed, "A later dive must restore a safely committed shortcut as open.")
	gate_probe.reset_attempt()
	_assert(
		not device.can_interact(),
		"A fresh private structure attempt must close its generic completion gate even when the public shortcut persists.",
	)
	session.reset_attempt()
	linked_shortcut.reset_attempt()
	_assert(
		session.activated_fixed_devices.is_empty()
		and session.opened_shortcuts.is_empty()
		and session.safe_return_only_activated_fixed_devices.is_empty()
		and session.safe_return_only_opened_shortcuts.is_empty()
		and not linked_shortcut.completed,
		"Retry must clear both local effects and close an uncommitted shortcut.",
	)

	dive_world.persistent_interactables.clear()
	dive_world._structure_controllers_by_id.clear()
	device.free()
	linked_shortcut.free()
	ordinary_shortcut.free()
	restored_shortcut.free()
	gate_probe.free()
	dive_world.free()
	quit(1 if _failed else 0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Structure world link test failed: %s" % message)
