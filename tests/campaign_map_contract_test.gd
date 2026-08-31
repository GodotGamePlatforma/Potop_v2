extends SceneTree

const CampaignProgressionSystemScript := preload("res://scripts/campaign/CampaignProgressionSystem.gd")
const MapCompilerScript := preload("res://underwater_map_workbench/runtime/UnderwaterMapSceneCompiler.gd")

const CAMPAIGN_SEED := 73_337

var _failed := false


func _initialize() -> void:
	var compiler = MapCompilerScript.new()
	var compilation: Dictionary = compiler.compile_map(null, CAMPAIGN_SEED)
	var compile_errors: PackedStringArray = compilation.get("errors", PackedStringArray())
	_assert(
		compile_errors.is_empty(),
		"Bieżąca mapa musi kompilować WorldBlueprint bez błędów: %s" % "; ".join(compile_errors),
	)
	if not compile_errors.is_empty():
		_finish()
		return
	var blueprint = compilation.get("blueprint")
	_assert(blueprint != null, "Kompilacja bieżącej mapy musi zwrócić WorldBlueprint.")
	if blueprint == null:
		_finish()
		return

	var required_device_ids := CampaignProgressionSystemScript.required_map_device_ids()
	_assert(
		not required_device_ids.is_empty(),
		"System kampanii musi publikować wymagane semantyczne urządzenia mapowe.",
	)
	var required_device_set := {}
	for device_id in required_device_ids:
		_assert(
			not device_id.is_empty() and not required_device_set.has(device_id),
			"Kontrakt wymaganych urządzeń kampanii musi zawierać niepuste, unikalne ID.",
		)
		required_device_set[device_id] = true

	var devices_by_id := {}
	for device: Dictionary in blueprint.fixed_device_spawns:
		var device_id := str(device.get("id", ""))
		if not required_device_set.has(device_id):
			continue
		_assert(
			not devices_by_id.has(device_id),
			"WorldBlueprint nie może zawierać dwóch urządzeń kampanii o ID %s." % device_id,
		)
		devices_by_id[device_id] = device

	for device_id in required_device_ids:
		_assert(
			devices_by_id.has(device_id),
			"WorldBlueprint nie zawiera wymaganego urządzenia kampanii %s." % device_id,
		)
		if not devices_by_id.has(device_id):
			continue
		var device: Dictionary = devices_by_id[device_id]
		var landmark_id := str(device.get("landmark_id", "")).strip_edges()
		_assert(
			not landmark_id.is_empty() and not blueprint.get_landmark(landmark_id).is_empty(),
			"Urządzenie kampanii %s musi wskazywać istniejący landmark." % device_id,
		)

	_finish()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("Campaign map contract test passed: required campaign devices are assigned to landmarks.")
	quit(0)
