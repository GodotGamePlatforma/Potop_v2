class_name DiveRecoveryAnalyzer
extends RefCounted


const QueryScript := preload("res://scripts/diving/DiveRecoveryQuery.gd")
const CertificateScript := preload("res://scripts/diving/DiveRecoveryCertificate.gd")
const ReportScript := preload("res://scripts/diving/DiveRecoveryReport.gd")
const DiveSessionStateScript := preload("res://scripts/data/DiveSessionState.gd")
const NavigationSnapshotScript := preload("res://scripts/diving/DiveNavigationSnapshot.gd")
const DiveInteractionRulesScript := preload("res://scripts/diving/DiveInteractionRules.gd")
const DiveMovementSystemScript := preload("res://scripts/diving/DiveMovementSystem.gd")
const OxygenSystemScript := preload("res://scripts/diving/OxygenSystem.gd")
const DiveRiskRuntimeScript := preload("res://scripts/diving/DiveRiskRuntime.gd")
const TemperatureSystemScript := preload("res://scripts/diving/TemperatureSystem.gd")
const CompetencySystemScript := preload("res://scripts/base/CompetencySystem.gd")
const RescueSystemScript := preload("res://scripts/diving/RescueSystem.gd")
const DiveThreatScript := preload("res://scripts/diving/DiveThreat.gd")
const DiveExitLineScript := preload("res://scripts/diving/DiveExitLine.gd")
const DiverScene := preload("res://scenes/diving/Diver.tscn")

const WAYPOINT_TOLERANCE := 4.0
const ARRIVAL_SPEED_TOLERANCE := 0.5
const PATH_SIMPLIFICATION_WINDOW := 64
const MIN_DIRECTIONAL_SPEED := 20.0
const MAX_CACHED_EDGE_ENVIRONMENTS := 500_000
const MAX_CACHED_EDGE_CLEARANCE_CHECKS := 750_000
const NEIGHBOR_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var _oxygen_system = OxygenSystemScript.new()
var _temperature_system = TemperatureSystemScript.new()
var _rescue_system = RescueSystemScript.new()
var _cached_motion_parameters: Dictionary = {}
var _edge_environment_cache: Dictionary = {}
var _edge_clearance_cache: Dictionary = {}
var _planned_path_cache: Dictionary = {}
var _cached_edge_environment_count := 0
var _cached_edge_clearance_count := 0


func analyze_query(
	setup,
	snapshot,
	query,
	policy,
	progression_profile_id: StringName = &"",
	difficulty_profile_id: StringName = &""
) -> Resource:
	var report = ReportScript.new()
	_populate_report_identity(
		report,
		query,
		policy,
		progression_profile_id,
		difficulty_profile_id
	)
	var validation_code := _validation_reason(setup, snapshot, query, policy)
	if validation_code != &"":
		report.reason_code = validation_code
		return report
	if int(query.trip_mode) == QueryScript.TripMode.INDEPENDENT_TRIPS:
		return _analyze_independent_trips(
			setup,
			snapshot,
			query,
			policy,
			progression_profile_id,
			difficulty_profile_id,
			report
		)

	var certificate := certify_sequence(
		setup,
		snapshot,
		query,
		policy,
		progression_profile_id,
		difficulty_profile_id,
		0
	)
	report.certificates.append(certificate)
	if not query.requested_manifest.is_empty():
		for resource_id in query.normalized_requested_manifest().keys():
			report.recovered_amount += int(certificate.recovered_items.get(str(resource_id), 0))
	else:
		report.recovered_amount = int(certificate.recovered_items.get(str(query.resource_id), 0))
	report.feasible = bool(certificate.feasible)
	report.safe = bool(certificate.safe)
	report.reason_code = certificate.reason_code
	return report


func preflight_sequence(setup, snapshot, query, policy) -> Dictionary:
	var validation_code := _validation_reason(setup, snapshot, query, policy)
	if validation_code != &"":
		return _preflight_failure(validation_code, "Niepoprawny kontrakt wejściowy certyfikacji.")

	var target_lookup := _target_lookup(snapshot)
	var target_descriptors: Array[Dictionary] = []
	for target_id in query.target_ids:
		if not target_lookup.has(target_id):
			return _preflight_failure(
				CertificateScript.TARGET_NOT_FOUND,
				"Nie znaleziono celu %s." % target_id
			)
		var descriptor: Dictionary = target_lookup[target_id]
		if not bool(descriptor.get("available", true)) or bool(descriptor.get("completed", false)):
			return _preflight_failure(
				CertificateScript.TARGET_UNAVAILABLE,
				"Cel %s nie jest aktywny." % target_id
			)
		var required_tool := str(descriptor.get("required_tool", ""))
		if not required_tool.is_empty() and not setup.selected_gear.has(required_tool):
			return _preflight_failure(
				CertificateScript.REQUIRED_TOOL_MISSING,
				"Cel %s wymaga narzędzia %s." % [target_id, required_tool]
			)
		target_descriptors.append(descriptor)

	var requested_manifest: Dictionary = query.normalized_requested_manifest()
	if not requested_manifest.is_empty():
		var requested_resource_ids: Array = requested_manifest.keys()
		requested_resource_ids.sort()
		for resource_value in requested_resource_ids:
			var requested_resource_id := str(resource_value)
			var authored_manifest_amount := 0
			for descriptor in target_descriptors:
				authored_manifest_amount += int(
					(descriptor.get("contents", {}) as Dictionary).get(requested_resource_id, 0)
				)
			if authored_manifest_amount < int(requested_manifest[resource_value]):
				return _preflight_failure(
					CertificateScript.SOURCE_AMOUNT_UNAVAILABLE,
					"Wybrane źródła zawierają %d/%d szt. %s."
					% [authored_manifest_amount, int(requested_manifest[resource_value]), requested_resource_id]
				)
	elif not str(query.resource_id).is_empty() and int(query.requested_amount) > 0:
		var authored_amount := 0
		for descriptor in target_descriptors:
			authored_amount += int(
				(descriptor.get("contents", {}) as Dictionary).get(str(query.resource_id), 0)
			)
		if authored_amount < int(query.requested_amount):
			return _preflight_failure(
				CertificateScript.SOURCE_AMOUNT_UNAVAILABLE,
				"Wybrane źródła zawierają %d/%d szt. %s."
				% [authored_amount, int(query.requested_amount), str(query.resource_id)]
			)

	var planning_session = DiveSessionStateScript.new()
	planning_session.begin(setup)
	var remaining_requested := int(query.requested_amount)
	var remaining_requested_manifest: Dictionary = requested_manifest.duplicate(true)
	var cargo_plans: Array[Dictionary] = []
	for descriptor in target_descriptors:
		var cargo_plan := _cargo_plan(
			descriptor,
			query,
			remaining_requested,
			remaining_requested_manifest,
			planning_session
		)
		if not bool(cargo_plan.get("valid", false)):
			return _preflight_failure(
				StringName(cargo_plan.get("reason_code", CertificateScript.CAPACITY_MASS_EXCEEDED)),
				str(cargo_plan.get("detail", "Cel nie mieści się w plecaku."))
			)
		cargo_plans.append(cargo_plan)
		_apply_cargo_plan(planning_session, cargo_plan)
		if not str(query.resource_id).is_empty():
			remaining_requested = maxi(
				remaining_requested
				- int((cargo_plan.get("manifest", {}) as Dictionary).get(str(query.resource_id), 0)),
				0
			)
		if not remaining_requested_manifest.is_empty():
			var recovered_manifest: Dictionary = cargo_plan.get("manifest", {})
			for resource_value in remaining_requested_manifest.keys():
				remaining_requested_manifest[resource_value] = maxi(
					int(remaining_requested_manifest[resource_value])
					- int(recovered_manifest.get(str(resource_value), 0)),
					0
				)

	if not str(query.resource_id).is_empty() and int(query.requested_amount) > 0 and remaining_requested > 0:
		return _preflight_failure(
			CertificateScript.QUANTITY_NOT_RECOVERED,
			"Po interakcjach nadal brakuje %d szt. %s."
			% [remaining_requested, str(query.resource_id)]
		)
	if not remaining_requested_manifest.is_empty():
		var missing_resource_ids: Array = remaining_requested_manifest.keys()
		missing_resource_ids.sort()
		for resource_value in missing_resource_ids:
			var missing_amount := int(remaining_requested_manifest[resource_value])
			if missing_amount > 0:
				return _preflight_failure(
					CertificateScript.QUANTITY_NOT_RECOVERED,
					"Po interakcjach nadal brakuje %d szt. %s."
					% [missing_amount, str(resource_value)]
				)

	return {
		"valid": true,
		"reason_code": &"",
		"reason_detail": "",
		"target_descriptors": target_descriptors,
		"cargo_plans": cargo_plans,
		"requested_manifest": requested_manifest,
	}


func certify_sequence(
	setup,
	snapshot,
	query,
	policy,
	progression_profile_id: StringName = &"",
	difficulty_profile_id: StringName = &"",
	trip_index: int = 0
) -> Resource:
	var certificate = CertificateScript.new()
	_populate_certificate_identity(
		certificate,
		query,
		policy,
		progression_profile_id,
		difficulty_profile_id,
		trip_index
	)
	if setup != null and "start_entry_point" in setup:
		certificate.entry_id = str(setup.start_entry_point)
	var preflight := preflight_sequence(setup, snapshot, query, policy)
	if not bool(preflight.get("valid", false)):
		return _fail(
			certificate,
			StringName(preflight.get("reason_code", CertificateScript.INVALID_QUERY)),
			str(preflight.get("reason_detail", "Niepoprawny kontrakt wejściowy certyfikacji."))
		)

	var target_descriptors: Array[Dictionary] = []
	target_descriptors.assign(preflight.get("target_descriptors", []))
	var cargo_plans: Array[Dictionary] = []
	cargo_plans.assign(preflight.get("cargo_plans", []))
	for descriptor in target_descriptors:
		var target_id := str(descriptor.get("id", ""))
		certificate.target_positions[target_id] = descriptor.get("position", Vector2.ZERO)
	var requested_manifest: Dictionary = preflight.get("requested_manifest", {}).duplicate(true)

	var replay_snapshot = _detached_navigation_snapshot(snapshot)
	if replay_snapshot == null or not replay_snapshot.is_valid():
		return _fail(certificate, CertificateScript.INVALID_SNAPSHOT, "Nie udało się utworzyć odłączonego snapshotu replayu.")
	var planning_snapshot = _planning_navigation_snapshot(replay_snapshot, policy)
	if planning_snapshot == null or not planning_snapshot.is_valid():
		return _fail(certificate, CertificateScript.INVALID_SNAPSHOT, "Nie udało się utworzyć snapshotu z marginesem planowania.")
	var session = DiveSessionStateScript.new()
	session.begin(setup)
	var risk_runtime = DiveRiskRuntimeScript.new()
	var threat_nodes := _build_threat_nodes(replay_snapshot)
	risk_runtime.reset(threat_nodes)
	var context := {
		"setup": setup,
		"snapshot": replay_snapshot,
		"policy": policy,
		"session": session,
		"risk_runtime": risk_runtime,
		"threats": threat_nodes,
		"position": replay_snapshot.start_position,
		"velocity": Vector2.ZERO,
		"elapsed": 0.0,
		"threat_exposure_seconds": 0.0,
		"certificate": certificate,
		"tow_definition": null,
		"motion": _motion_parameters(),
	}
	_populate_outcome(certificate, session, 0.0, 0.0)
	var remaining_requested := int(query.requested_amount)
	var remaining_requested_manifest: Dictionary = requested_manifest.duplicate(true)
	var completed_targets: Array[String] = []

	for descriptor_index in range(target_descriptors.size()):
		var descriptor: Dictionary = target_descriptors[descriptor_index]
		var cargo_plan: Dictionary = cargo_plans[descriptor_index]
		certificate.maximum_recoverable_amount += int(cargo_plan.get("maximum_recoverable_amount", 0))
		var target_position: Vector2 = descriptor.get("position", Vector2.ZERO)
		var outbound_plan := _plan_path(
			replay_snapshot,
			planning_snapshot,
			context.position,
			target_position,
			DiveInteractionRulesScript.INTERACTION_DISTANCE,
			setup,
			session.carry_ratio(),
			context.tow_definition,
			policy
		)
		certificate.planner_expansions += int(outbound_plan.get("expansions", 0))
		if not bool(outbound_plan.get("found", false)):
			_free_threat_nodes(threat_nodes)
			return _fail(certificate, CertificateScript.TARGET_UNREACHABLE, "Brak przejścia do celu %s." % str(descriptor.get("id", "")))
		var path: PackedVector2Array = outbound_plan.get("path", PackedVector2Array())
		_append_route(certificate, path)
		certificate.path_distance += _path_distance(path)
		var replay_failure := _replay_path(context, path)
		if replay_failure != &"":
			_free_threat_nodes(threat_nodes)
			return _fail(
				certificate,
				replay_failure,
				str(context.get("replay_failure_detail", "Replay nie dotarł do celu %s." % str(descriptor.get("id", ""))))
			)

		var interaction_failure := _replay_interaction(context, descriptor)
		if interaction_failure != &"":
			_free_threat_nodes(threat_nodes)
			return _fail(
				certificate,
				interaction_failure,
				str(context.get("replay_failure_detail", "Replay nie ukończył interakcji %s." % str(descriptor.get("id", ""))))
			)
		_apply_cargo_plan(session, cargo_plan)
		_populate_outcome(
			certificate,
			session,
			float(context.elapsed),
			float(context.threat_exposure_seconds)
		)
		var target_id := str(descriptor.get("id", ""))
		completed_targets.append(target_id)
		if str(descriptor.get("persistent_kind", "")) == "shortcut":
			var replay_gate_opened := _open_shortcut_in_detached_snapshot(replay_snapshot, target_id)
			var planning_gate_opened := _open_shortcut_in_detached_snapshot(planning_snapshot, target_id)
			if not replay_gate_opened or not planning_gate_opened:
				_free_threat_nodes(threat_nodes)
				return _fail(
					certificate,
					CertificateScript.SHORTCUT_GATE_STATE_MISMATCH,
					"Interakcja %s nie odmaskowała odpowiadającej jej bramy w odłączonym replayu." % target_id
				)
		if str(descriptor.get("kind", "")) == "rescue":
			_begin_conservative_tow(session, descriptor)
			context.tow_definition = descriptor.get("definition", null)
		if not str(query.resource_id).is_empty():
			remaining_requested = maxi(
				remaining_requested - int((cargo_plan.get("manifest", {}) as Dictionary).get(str(query.resource_id), 0)),
				0
			)
		if not remaining_requested_manifest.is_empty():
			var recovered_manifest: Dictionary = cargo_plan.get("manifest", {})
			for resource_value in remaining_requested_manifest.keys():
				remaining_requested_manifest[resource_value] = maxi(
					int(remaining_requested_manifest[resource_value])
					- int(recovered_manifest.get(str(resource_value), 0)),
					0
				)

	if not str(query.resource_id).is_empty() and int(query.requested_amount) > 0 and remaining_requested > 0:
		_free_threat_nodes(threat_nodes)
		return _fail(
			certificate,
			CertificateScript.QUANTITY_NOT_RECOVERED,
			"Po interakcjach nadal brakuje %d szt. %s." % [remaining_requested, str(query.resource_id)]
		)
	if not remaining_requested_manifest.is_empty():
		var missing_resource_ids: Array = remaining_requested_manifest.keys()
		missing_resource_ids.sort()
		for resource_value in missing_resource_ids:
			var missing_amount := int(remaining_requested_manifest[resource_value])
			if missing_amount <= 0:
				continue
			_free_threat_nodes(threat_nodes)
			return _fail(
				certificate,
				CertificateScript.QUANTITY_NOT_RECOVERED,
				"Po interakcjach nadal brakuje %d szt. %s." % [missing_amount, str(resource_value)]
			)

	var return_plan := _plan_path(
		replay_snapshot,
		planning_snapshot,
		context.position,
		replay_snapshot.exit_position,
		DiveInteractionRulesScript.INTERACTION_DISTANCE,
		setup,
		session.carry_ratio(),
		context.tow_definition,
		policy
	)
	certificate.planner_expansions += int(return_plan.get("expansions", 0))
	if not bool(return_plan.get("found", false)):
		_free_threat_nodes(threat_nodes)
		return _fail(certificate, CertificateScript.RETURN_UNREACHABLE, "Brak przejścia do normalnej aktywnej liny.")
	var return_path: PackedVector2Array = return_plan.get("path", PackedVector2Array())
	_append_route(certificate, return_path)
	certificate.path_distance += _path_distance(return_path)
	var return_failure := _replay_path(context, return_path)
	if return_failure != &"":
		_free_threat_nodes(threat_nodes)
		return _fail(
			certificate,
			return_failure,
			str(context.get("replay_failure_detail", "Replay nie ukończył powrotu do normalnej aktywnej liny."))
		)
	var exit_line = DiveExitLineScript.new()
	var exit_interaction_seconds := float(exit_line.interaction_seconds)
	exit_line.free()
	var exit_failure := _replay_interaction(
		context,
		{
			"kind": "exit_line",
			"position": replay_snapshot.exit_position,
			"interaction_seconds": exit_interaction_seconds,
			"interaction_action": "",
		},
		false
	)
	if exit_failure != &"":
		_free_threat_nodes(threat_nodes)
		return _fail(
			certificate,
			exit_failure,
			str(context.get("replay_failure_detail", "Replay nie ukończył pełnej interakcji z normalną aktywną liną."))
		)

	certificate.target_ids.assign(completed_targets)
	certificate.recovered_items = session.carried_items.duplicate(true)
	_populate_outcome(
		certificate,
		session,
		float(context.elapsed),
		float(context.threat_exposure_seconds)
	)
	certificate.feasible = session.health > 0 and session.oxygen_left > 0.0
	certificate.safe = certificate.feasible and _meets_safety_policy(certificate, policy)
	certificate.reason_code = CertificateScript.OK_SAFE if certificate.safe else CertificateScript.OK_FEASIBLE_RESERVE_SHORTFALL
	certificate.reason_detail = "Trasa, pełne interakcje, ładunek i normalna lina przeszły deterministyczny replay."
	_free_threat_nodes(threat_nodes)
	return certificate


func queries_for_static_targets(snapshot) -> Array[Resource]:
	var result: Array[Resource] = []
	if snapshot == null or not snapshot.is_valid():
		return result
	var descriptors: Array[Dictionary] = snapshot.target_descriptors()
	descriptors.sort_custom(func(left: Dictionary, right: Dictionary): return str(left.get("id", "")) < str(right.get("id", "")))
	for descriptor in descriptors:
		var target_id := str(descriptor.get("id", ""))
		var contents: Dictionary = descriptor.get("contents", {})
		var requires_full := _descriptor_requires_full_target(descriptor)
		if contents.is_empty() or requires_full:
			var full_query = QueryScript.new()
			full_query.query_id = StringName("target_%s" % target_id)
			full_query.target_ids.assign([target_id])
			full_query.require_full_targets = requires_full
			result.append(full_query)
			continue
		var resource_ids: Array = contents.keys()
		resource_ids.sort()
		for resource_value in resource_ids:
			var resource_id := str(resource_value)
			var query = QueryScript.new()
			query.query_id = StringName("target_%s_%s_max" % [target_id, resource_id])
			query.target_ids.assign([target_id])
			query.resource_id = resource_id
			query.requested_amount = 0
			result.append(query)
	return result


func _analyze_independent_trips(
	setup,
	snapshot,
	query,
	policy,
	progression_profile_id: StringName,
	difficulty_profile_id: StringName,
	report
) -> Resource:
	var successful_certificates: Array[Resource] = []
	for index in range(query.target_ids.size()):
		var subquery = query.detached_copy()
		subquery.query_id = StringName("%s_trip_%d" % [str(query.query_id), index + 1])
		subquery.target_ids.assign([query.target_ids[index]])
		subquery.allow_combining_sources = false
		subquery.trip_mode = QueryScript.TripMode.SINGLE_TRIP
		if not str(query.resource_id).is_empty():
			subquery.requested_amount = 0
		var certificate := certify_sequence(
			setup,
			snapshot,
			subquery,
			policy,
			progression_profile_id,
			difficulty_profile_id,
			index
		)
		report.certificates.append(certificate)
		if certificate.feasible:
			successful_certificates.append(certificate)
			report.recovered_amount += int(certificate.recovered_items.get(str(query.resource_id), 0)) if not str(query.resource_id).is_empty() else 0
		if not str(query.resource_id).is_empty() and int(query.requested_amount) > 0 and report.recovered_amount >= int(query.requested_amount):
			break

	if str(query.resource_id).is_empty():
		report.feasible = successful_certificates.size() == query.target_ids.size()
	else:
		report.feasible = report.recovered_amount > 0 if int(query.requested_amount) == 0 else report.recovered_amount >= int(query.requested_amount)
	report.safe = report.feasible
	for certificate in successful_certificates:
		report.safe = report.safe and bool(certificate.safe)
	if report.safe:
		report.reason_code = CertificateScript.OK_SAFE
	elif report.feasible:
		report.reason_code = CertificateScript.OK_FEASIBLE_RESERVE_SHORTFALL
	else:
		report.reason_code = CertificateScript.QUANTITY_NOT_RECOVERED if not str(query.resource_id).is_empty() else _first_failure_code(report.certificates)
	return report


func _validation_reason(setup, snapshot, query, policy) -> StringName:
	if query == null or query.get_script() != QueryScript or not query.is_valid():
		return CertificateScript.INVALID_QUERY
	if policy == null or not policy.has_method("is_valid") or not policy.is_valid():
		return CertificateScript.INVALID_POLICY
	if setup == null or float(setup.oxygen_capacity) <= 0.0 or int(setup.diver_health) <= 0:
		return CertificateScript.INVALID_SETUP
	if snapshot == null or not snapshot.is_valid():
		return CertificateScript.INVALID_SNAPSHOT
	return &""


func _preflight_failure(reason_code: StringName, reason_detail: String) -> Dictionary:
	return {
		"valid": false,
		"reason_code": reason_code,
		"reason_detail": reason_detail,
		"target_descriptors": [],
		"cargo_plans": [],
		"requested_manifest": {},
	}


func _target_lookup(snapshot) -> Dictionary:
	var result: Dictionary = {}
	for descriptor in snapshot.target_descriptors():
		result[str(descriptor.get("id", ""))] = descriptor
	return result


func _detached_navigation_snapshot(source):
	if source == null or not source.is_valid():
		return null
	var result = NavigationSnapshotScript.new()
	result.world_size = source.world_size
	result.grid_size = source.grid_size
	result.cell_scale = source.cell_scale
	result.clearance_world = source.clearance_world
	result.start_position = source.start_position
	result.exit_position = source.exit_position
	result.open_cells = source.open_cells.duplicate()
	result.clear_cells = source.clear_cells.duplicate()
	result.current_zones = _detached_dictionary_array(source.current_zones)
	result.depth_regions = _detached_dictionary_array(source.depth_regions)
	result.closed_shortcut_gates = source.closed_gate_descriptors()
	result.targets = source.target_descriptors()
	result.threats = source.threat_descriptors()
	result.set_meta(&"recovery_routing_signature", _routing_signature(source))
	return result


func _planning_navigation_snapshot(replay_snapshot, policy):
	if replay_snapshot == null or not replay_snapshot.is_valid() or policy == null:
		return null
	var result = NavigationSnapshotScript.new()
	result.configure(
		replay_snapshot.world_size,
		replay_snapshot.grid_size,
		replay_snapshot.cell_scale,
		replay_snapshot.open_cells,
		replay_snapshot.clearance_world + float(policy.planner_clearance_margin_world),
		replay_snapshot.start_position,
		replay_snapshot.exit_position,
		replay_snapshot.current_zones,
		replay_snapshot.depth_regions,
		replay_snapshot.closed_gate_descriptors(),
		replay_snapshot.target_descriptors(),
		replay_snapshot.threat_descriptors()
	)
	result.set_meta(&"recovery_routing_signature", _routing_signature(result))
	return result


func _detached_dictionary_array(source: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in source:
		if value is Dictionary:
			result.append(value.duplicate(true))
	return result


func _open_shortcut_in_detached_snapshot(snapshot, shortcut_id: String) -> bool:
	if snapshot == null or shortcut_id.is_empty():
		return false
	var gates: Array[Dictionary] = snapshot.closed_gate_descriptors()
	var gate_removed := false
	for index in range(gates.size() - 1, -1, -1):
		if str(gates[index].get("id", "")) != shortcut_id:
			continue
		gates.remove_at(index)
		gate_removed = true
	var targets: Array[Dictionary] = snapshot.target_descriptors()
	var target_updated := false
	for index in range(targets.size()):
		if str(targets[index].get("id", "")) != shortcut_id:
			continue
		targets[index]["completed"] = true
		targets[index]["available"] = false
		targets[index]["is_obstacle"] = false
		target_updated = true
	if not gate_removed or not target_updated:
		return false
	var current_zones := _detached_dictionary_array(snapshot.current_zones)
	var depth_regions := _detached_dictionary_array(snapshot.depth_regions)
	snapshot.configure(
		snapshot.world_size,
		snapshot.grid_size,
		snapshot.cell_scale,
		snapshot.open_cells,
		snapshot.clearance_world,
		snapshot.start_position,
		snapshot.exit_position,
		current_zones,
		depth_regions,
		gates,
		targets,
		snapshot.threat_descriptors()
	)
	if snapshot.has_meta(&"recovery_routing_signature"):
		snapshot.remove_meta(&"recovery_routing_signature")
	if snapshot.is_valid():
		snapshot.set_meta(&"recovery_routing_signature", _routing_signature(snapshot))
	return snapshot.is_valid()


func _cargo_plan(
	descriptor: Dictionary,
	query,
	remaining_requested: int,
	remaining_requested_manifest: Dictionary,
	session
) -> Dictionary:
	var contents: Dictionary = (descriptor.get("contents", {}) as Dictionary).duplicate(true)
	var manifest: Dictionary = {}
	var maximum_recoverable_amount := 0
	var requires_full := bool(query.require_full_targets) or _descriptor_requires_full_target(descriptor)
	if not remaining_requested_manifest.is_empty():
		var shadow = session.duplicate(true)
		var requested_resource_ids: Array = remaining_requested_manifest.keys()
		requested_resource_ids.sort()
		for resource_value in requested_resource_ids:
			var resource_id := str(resource_value)
			var remaining_amount := maxi(int(remaining_requested_manifest[resource_value]), 0)
			var available := maxi(int(contents.get(resource_id, 0)), 0)
			var selected_amount := mini(remaining_amount, available)
			if selected_amount <= 0:
				continue
			var accepted: int = shadow.add_item(resource_id, selected_amount)
			if accepted != selected_amount:
				return _capacity_failure(shadow, resource_id)
			manifest[resource_id] = selected_amount
			maximum_recoverable_amount += selected_amount
		return {
			"valid": true,
			"manifest": manifest,
			"maximum_recoverable_amount": maximum_recoverable_amount,
		}
	elif not str(query.resource_id).is_empty():
		var resource_id := str(query.resource_id)
		var available := maxi(int(contents.get(resource_id, 0)), 0)
		if available <= 0:
			return {
				"valid": false,
				"reason_code": CertificateScript.SOURCE_AMOUNT_UNAVAILABLE,
				"detail": "Cel %s nie zawiera %s." % [str(descriptor.get("id", "")), resource_id],
			}
		maximum_recoverable_amount = mini(available, session.max_addable_amount(resource_id, available))
		if requires_full:
			manifest = contents.duplicate(true)
		else:
			var selected_amount := maximum_recoverable_amount
			if remaining_requested > 0:
				selected_amount = mini(selected_amount, remaining_requested)
			if selected_amount <= 0:
				return _capacity_failure(session, resource_id)
			manifest[resource_id] = selected_amount
	elif not contents.is_empty():
		if requires_full:
			manifest = contents.duplicate(true)
		else:
			var resource_ids: Array = contents.keys()
			resource_ids.sort()
			var resource_id := str(resource_ids[0])
			var available := maxi(int(contents[resource_id]), 0)
			maximum_recoverable_amount = mini(available, session.max_addable_amount(resource_id, available))
			if maximum_recoverable_amount <= 0:
				return _capacity_failure(session, resource_id)
			manifest[resource_id] = maximum_recoverable_amount

	var shadow = session.duplicate(true)
	var manifest_ids: Array = manifest.keys()
	manifest_ids.sort()
	for resource_value in manifest_ids:
		var resource_id := str(resource_value)
		var amount := maxi(int(manifest[resource_value]), 0)
		if amount <= 0:
			continue
		var accepted: int = shadow.add_item(resource_id, amount)
		if accepted != amount:
			return _capacity_failure(shadow, resource_id)
	return {
		"valid": true,
		"manifest": manifest,
		"maximum_recoverable_amount": maximum_recoverable_amount,
	}


func _capacity_failure(session, resource_id: String) -> Dictionary:
	var slots_full: bool = not session.carried_items.has(resource_id) and session.slots_used() >= session.backpack_capacity
	return {
		"valid": false,
		"reason_code": CertificateScript.CAPACITY_SLOT_EXCEEDED if slots_full else CertificateScript.CAPACITY_MASS_EXCEEDED,
		"detail": "Brak miejsca na %s: %s." % [resource_id, "sloty" if slots_full else "masa"],
	}


func _apply_cargo_plan(session, cargo_plan: Dictionary) -> void:
	var manifest: Dictionary = cargo_plan.get("manifest", {})
	var resource_ids: Array = manifest.keys()
	resource_ids.sort()
	for resource_value in resource_ids:
		session.add_item(str(resource_value), int(manifest[resource_value]))


func _descriptor_requires_full_target(descriptor: Dictionary) -> bool:
	return (
		bool(descriptor.get("full_pickup", false))
		or bool(descriptor.get("mandatory", false))
		or bool(descriptor.get("story", false))
		or str(descriptor.get("kind", "")) in ["pickup", "rescue", "persistent_objective"]
	)


func _plan_path(
	snapshot,
	planning_safety_snapshot,
	start_position: Vector2,
	target_position: Vector2,
	interaction_radius: float,
	setup,
	load_ratio: float,
	tow_definition,
	policy
) -> Dictionary:
	var base_routing_signature := _routing_signature(snapshot)
	var safety_routing_signature := _routing_signature(planning_safety_snapshot)
	var routing_signature := "%s|current-safety:%s" % [base_routing_signature, safety_routing_signature]
	var cache_key := _path_cache_key(
		routing_signature,
		start_position,
		target_position,
		interaction_radius,
		setup,
		load_ratio,
		tow_definition,
		policy
	)
	if _planned_path_cache.has(cache_key):
		var cached_plan: Dictionary = _planned_path_cache[cache_key]
		return _detached_plan(cached_plan)
	var start_cell := _nearest_clear_cell(snapshot, start_position, 16)
	if start_cell.x < 0:
		var missing_start := {"found": false, "expansions": 0}
		_planned_path_cache[cache_key] = missing_start
		return missing_start.duplicate(true)
	var stride := maxi(int(policy.planner_cell_stride), 1)
	var environment_cache: Dictionary = _edge_environment_cache.get(base_routing_signature, {})
	if not _edge_environment_cache.has(base_routing_signature):
		_edge_environment_cache[base_routing_signature] = environment_cache
	var clearance_cache: Dictionary = _edge_clearance_cache.get(base_routing_signature, {})
	if not _edge_clearance_cache.has(base_routing_signature):
		_edge_clearance_cache[base_routing_signature] = clearance_cache
	var safety_clearance_cache: Dictionary = _edge_clearance_cache.get(safety_routing_signature, {})
	if not _edge_clearance_cache.has(safety_routing_signature):
		_edge_clearance_cache[safety_routing_signature] = safety_clearance_cache
	var start_key := _cell_key(start_cell, snapshot.grid_size.x)
	var open_cells: Array[Vector2i] = []
	var open_priorities: Array[float] = []
	_heap_push(open_cells, open_priorities, start_cell, 0.0)
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_key: 0.0}
	var closed: Dictionary = {}
	var expansions := 0
	var goal_cell := Vector2i(-1, -1)

	while not open_cells.is_empty() and expansions < int(policy.maximum_planner_expansions):
		var current_cell := _heap_pop(open_cells, open_priorities)
		var current_key := _cell_key(current_cell, snapshot.grid_size.x)
		if closed.has(current_key):
			continue
		closed[current_key] = true
		expansions += 1
		var current_position: Vector2 = snapshot.cell_center(current_cell)
		if current_position.distance_to(target_position) <= interaction_radius:
			goal_cell = current_cell
			break

		for direction in NEIGHBOR_DIRECTIONS:
			var neighbor := current_cell + direction * stride
			var neighbor_position: Vector2 = snapshot.cell_center(neighbor) if snapshot.is_cell_in_bounds(neighbor) else Vector2.ZERO
			var neighbor_segment_clear: bool = (
				snapshot.is_cell_in_bounds(neighbor)
				and snapshot.is_cell_clear(neighbor)
				and _current_aware_planner_segment_is_clear(
					snapshot,
					planning_safety_snapshot,
					current_position,
					neighbor_position,
					clearance_cache,
					safety_clearance_cache
				)
			)
			if not neighbor_segment_clear and stride > 1:
				neighbor = current_cell + direction
				neighbor_position = snapshot.cell_center(neighbor) if snapshot.is_cell_in_bounds(neighbor) else Vector2.ZERO
				neighbor_segment_clear = false
			if not snapshot.is_cell_in_bounds(neighbor) or not snapshot.is_cell_clear(neighbor):
				continue
			var neighbor_key := _cell_key(neighbor, snapshot.grid_size.x)
			if closed.has(neighbor_key):
				continue
			if not neighbor_segment_clear and not _current_aware_planner_segment_is_clear(
				snapshot,
				planning_safety_snapshot,
				current_position,
				neighbor_position,
				clearance_cache,
				safety_clearance_cache
			):
				continue
			var tentative := float(g_score[current_key]) + _planner_edge_cost(
				current_position,
				neighbor_position,
				snapshot,
				setup,
				load_ratio,
				tow_definition,
				policy,
				environment_cache
			)
			if tentative >= float(g_score.get(neighbor_key, INF)):
				continue
			came_from[neighbor_key] = current_key
			g_score[neighbor_key] = tentative
			var heuristic_distance := maxf(neighbor_position.distance_to(target_position) - interaction_radius, 0.0)
			var heuristic := heuristic_distance / maxf(_base_swim_speed() * CompetencySystemScript.swimming_multiplier(setup), MIN_DIRECTIONAL_SPEED) * OxygenSystemScript.SWIM_RATE
			_heap_push(open_cells, open_priorities, neighbor, tentative + heuristic)

	if goal_cell.x < 0:
		var missing_goal := {"found": false, "expansions": expansions}
		_planned_path_cache[cache_key] = missing_goal
		return missing_goal.duplicate(true)
	var cell_path: Array[Vector2i] = []
	var cursor_key := _cell_key(goal_cell, snapshot.grid_size.x)
	while true:
		var cursor_cell := Vector2i(cursor_key % snapshot.grid_size.x, floori(float(cursor_key) / float(snapshot.grid_size.x)))
		cell_path.push_front(cursor_cell)
		if cursor_key == start_key:
			break
		if not came_from.has(cursor_key):
			var broken_chain := {"found": false, "expansions": expansions}
			_planned_path_cache[cache_key] = broken_chain
			return broken_chain.duplicate(true)
		cursor_key = int(came_from[cursor_key])
	var raw_path := PackedVector2Array([start_position])
	for cell in cell_path:
		var point: Vector2 = snapshot.cell_center(cell)
		if raw_path[-1].distance_to(point) > 0.01:
			raw_path.append(point)
	var planned := {
		"found": true,
		"expansions": expansions,
		"path": _simplify_path(
			snapshot,
			planning_safety_snapshot,
			raw_path,
			clearance_cache,
			safety_clearance_cache
		),
	}
	_planned_path_cache[cache_key] = planned
	return _detached_plan(planned)


func _planner_edge_cost(
	from_position: Vector2,
	to_position: Vector2,
	snapshot,
	setup,
	load_ratio: float,
	tow_definition,
	policy,
	environment_cache: Dictionary
) -> float:
	var delta := to_position - from_position
	var distance := delta.length()
	if distance <= 0.0:
		return 0.0
	var direction := delta / distance
	var environment: Vector3 = _edge_environment(
		snapshot,
		from_position,
		to_position,
		environment_cache
	)
	var current := Vector2(environment.x, environment.y) * _modifier(setup, "current_strength_multiplier")
	var tow_speed_multiplier := _tow_movement_multiplier(tow_definition)
	var swim_speed := _base_swim_speed() * CompetencySystemScript.swimming_multiplier(setup) * tow_speed_multiplier
	var directional_speed := maxf(swim_speed + current.dot(direction), MIN_DIRECTIONAL_SPEED)
	var seconds := distance / directional_speed
	var oxygen_rate := _oxygen_system.consumption_rate(
		true,
		false,
		load_ratio,
		current.length_squared() > 0.01,
		CompetencySystemScript.load_oxygen_surcharge_multiplier(setup)
	) * _modifier(setup, "oxygen_use_multiplier") * _tow_oxygen_multiplier(tow_definition) * CompetencySystemScript.oxygen_use_multiplier(setup)
	var cost := seconds * oxygen_rate
	cost += environment.z * float(policy.threat_route_penalty_seconds) * OxygenSystemScript.SWIM_RATE
	return cost


func _routing_signature(snapshot) -> String:
	if snapshot == null:
		return "invalid"
	if snapshot.has_meta(&"recovery_routing_signature"):
		return str(snapshot.get_meta(&"recovery_routing_signature"))
	var current_records: Array[String] = []
	for zone in snapshot.current_zones:
		var rect: Rect2 = zone.get("rect", Rect2())
		var velocity: Vector2 = zone.get("velocity", Vector2.ZERO)
		current_records.append(
			"%s|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f"
			% [str(zone.get("id", "")), rect.position.x, rect.position.y, rect.size.x, rect.size.y, velocity.x, velocity.y]
		)
	current_records.sort()
	var threat_records: Array[String] = []
	for threat in snapshot.threats:
		var definition = threat.get("definition", null)
		var position: Vector2 = threat.get("position", Vector2.ZERO)
		var light_radius := float(definition.get("light_detection_radius")) if definition != null else 0.0
		var noise_radius := float(definition.get("noise_detection_radius")) if definition != null else 0.0
		threat_records.append(
			"%s|%.9f|%.9f|%.9f|%.9f"
			% [str(threat.get("id", "")), position.x, position.y, light_radius, noise_radius]
		)
	threat_records.sort()
	var metadata := (
		"%d|%d|%.9f|%.9f|%.9f\n%s\n%s"
		% [
			int(snapshot.grid_size.x),
			int(snapshot.grid_size.y),
			float(snapshot.cell_scale.x),
			float(snapshot.cell_scale.y),
			float(snapshot.clearance_world),
			"\n".join(current_records),
			"\n".join(threat_records),
		]
	)
	var hashing_context := HashingContext.new()
	hashing_context.start(HashingContext.HASH_SHA256)
	hashing_context.update(metadata.to_utf8_buffer())
	hashing_context.update(snapshot.clear_cells)
	return hashing_context.finish().hex_encode()


func _path_cache_key(
	routing_signature: String,
	start_position: Vector2,
	target_position: Vector2,
	interaction_radius: float,
	setup,
	load_ratio: float,
	tow_definition,
	policy
) -> String:
	return (
		"%s|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%.9f|%d|%d|%.9f"
		% [
			routing_signature,
			start_position.x,
			start_position.y,
			target_position.x,
			target_position.y,
			interaction_radius,
			load_ratio,
			_modifier(setup, "current_strength_multiplier"),
			_modifier(setup, "oxygen_use_multiplier"),
			CompetencySystemScript.swimming_multiplier(setup),
			CompetencySystemScript.load_oxygen_surcharge_multiplier(setup),
			CompetencySystemScript.oxygen_use_multiplier(setup),
			_tow_movement_multiplier(tow_definition),
			_tow_oxygen_multiplier(tow_definition),
			int(policy.planner_cell_stride),
			int(policy.maximum_planner_expansions),
			float(policy.threat_route_penalty_seconds),
		]
	)


func _detached_plan(source: Dictionary) -> Dictionary:
	var source_path: PackedVector2Array = source.get("path", PackedVector2Array())
	return {
		"found": bool(source.get("found", false)),
		"expansions": int(source.get("expansions", 0)),
		"path": source_path.duplicate(),
	}


func _planner_segment_is_clear(
	snapshot,
	from_position: Vector2,
	to_position: Vector2,
	clearance_cache: Dictionary
) -> bool:
	var edge_key: int = _undirected_cell_edge_key(snapshot, from_position, to_position)
	if edge_key >= 0 and clearance_cache.has(edge_key):
		return bool(clearance_cache[edge_key])
	var segment_clear: bool = bool(snapshot.is_segment_clear(from_position, to_position))
	if edge_key >= 0 and _cached_edge_clearance_count < MAX_CACHED_EDGE_CLEARANCE_CHECKS:
		clearance_cache[edge_key] = segment_clear
		_cached_edge_clearance_count += 1
	return segment_clear


func _current_aware_planner_segment_is_clear(
	snapshot,
	planning_safety_snapshot,
	from_position: Vector2,
	to_position: Vector2,
	clearance_cache: Dictionary,
	safety_clearance_cache: Dictionary
) -> bool:
	if not _planner_segment_is_clear(snapshot, from_position, to_position, clearance_cache):
		return false
	if not _segment_intersects_authored_current(snapshot, from_position, to_position):
		return true
	return _planner_segment_is_clear(
		planning_safety_snapshot,
		from_position,
		to_position,
		safety_clearance_cache
	)


func _segment_intersects_authored_current(snapshot, from_position: Vector2, to_position: Vector2) -> bool:
	for zone in snapshot.current_zones:
		var velocity: Vector2 = zone.get("velocity", Vector2.ZERO)
		if velocity.length_squared() <= 0.01:
			continue
		var rect: Rect2 = zone.get("rect", Rect2())
		if rect.has_point(from_position) or rect.has_point(to_position) or _segment_intersects_rect(from_position, to_position, rect):
			return true
	return false


func _segment_intersects_rect(from_position: Vector2, to_position: Vector2, rect: Rect2) -> bool:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	var delta := to_position - from_position
	var minimum_t := 0.0
	var maximum_t := 1.0
	if absf(delta.x) <= 0.000001:
		if from_position.x < rect.position.x or from_position.x > rect.end.x:
			return false
	else:
		var x_t_a := (rect.position.x - from_position.x) / delta.x
		var x_t_b := (rect.end.x - from_position.x) / delta.x
		minimum_t = maxf(minimum_t, minf(x_t_a, x_t_b))
		maximum_t = minf(maximum_t, maxf(x_t_a, x_t_b))
		if minimum_t > maximum_t:
			return false
	if absf(delta.y) <= 0.000001:
		if from_position.y < rect.position.y or from_position.y > rect.end.y:
			return false
	else:
		var y_t_a := (rect.position.y - from_position.y) / delta.y
		var y_t_b := (rect.end.y - from_position.y) / delta.y
		minimum_t = maxf(minimum_t, minf(y_t_a, y_t_b))
		maximum_t = minf(maximum_t, maxf(y_t_a, y_t_b))
	return minimum_t <= maximum_t


func _undirected_cell_edge_key(snapshot, from_position: Vector2, to_position: Vector2) -> int:
	var from_cell: Vector2i = snapshot.world_to_cell(from_position)
	var to_cell: Vector2i = snapshot.world_to_cell(to_position)
	if (
		from_position.distance_squared_to(snapshot.cell_center(from_cell)) > 0.000001
		or to_position.distance_squared_to(snapshot.cell_center(to_cell)) > 0.000001
	):
		return -1
	var from_key: int = _cell_key(from_cell, snapshot.grid_size.x)
	var to_key: int = _cell_key(to_cell, snapshot.grid_size.x)
	var minimum_key: int = mini(from_key, to_key)
	var maximum_key: int = maxi(from_key, to_key)
	var cell_count: int = int(snapshot.grid_size.x) * int(snapshot.grid_size.y)
	return minimum_key * cell_count + maximum_key


func _edge_environment(
	snapshot,
	from_position: Vector2,
	to_position: Vector2,
	environment_cache: Dictionary
) -> Vector3:
	var edge_key: int = _undirected_cell_edge_key(snapshot, from_position, to_position)
	if edge_key >= 0 and environment_cache.has(edge_key):
		var cached_environment: Vector3 = environment_cache[edge_key]
		return cached_environment
	var sample_position: Vector2 = (from_position + to_position) * 0.5
	var raw_current: Vector2 = snapshot.current_at(sample_position)
	var threat_exposure: float = 0.0
	for threat in snapshot.threats:
		var definition = threat.get("definition", null)
		if definition == null:
			continue
		var threat_position: Vector2 = threat.get("position", Vector2.ZERO)
		var threat_distance: float = sample_position.distance_to(threat_position)
		var avoidance_radius: float = maxf(float(definition.light_detection_radius), float(definition.noise_detection_radius))
		if threat_distance < avoidance_radius:
			threat_exposure += 1.0 - threat_distance / maxf(avoidance_radius, 1.0)
	var result: Vector3 = Vector3(raw_current.x, raw_current.y, threat_exposure)
	if edge_key >= 0 and _cached_edge_environment_count < MAX_CACHED_EDGE_ENVIRONMENTS:
		environment_cache[edge_key] = result
		_cached_edge_environment_count += 1
	return result


func _replay_path(context: Dictionary, path: PackedVector2Array) -> StringName:
	context.erase("replay_failure_detail")
	if path.is_empty():
		context["replay_failure_detail"] = "Replay otrzymał pustą ścieżkę."
		return CertificateScript.REPLAY_GEOMETRY_DIVERGED
	context.position = path[0]
	for index in range(1, path.size()):
		var waypoint: Vector2 = path[index]
		while true:
			var position: Vector2 = context.position
			var distance_to_waypoint: float = position.distance_to(waypoint)
			if distance_to_waypoint <= WAYPOINT_TOLERANCE and Vector2(context.velocity).length() <= ARRIVAL_SPEED_TOLERANCE:
				if not context.snapshot.is_segment_clear(position, waypoint):
					context["replay_failure_detail"] = (
						"Replay utracił prześwit na domknięciu segmentu %d: %s → %s."
						% [index, position, waypoint]
					)
					return CertificateScript.REPLAY_GEOMETRY_DIVERGED
				context.position = waypoint
				break
			if float(context.elapsed) >= float(context.policy.maximum_replay_seconds):
				return CertificateScript.REPLAY_LIMIT_EXCEEDED
			var delta: float = minf(float(context.policy.fixed_step_seconds), float(context.policy.maximum_replay_seconds) - float(context.elapsed))
			var to_waypoint: Vector2 = waypoint - position
			var snapshot = context.snapshot
			var setup = context.setup
			var session = context.session
			var raw_current: Vector2 = snapshot.current_at(position)
			var current: Vector2 = raw_current * _modifier(setup, "current_strength_multiplier")
			var risk_multiplier: float = _temperature_system.movement_multiplier(session.cold_exposure)
			var speed_multiplier: float = risk_multiplier * CompetencySystemScript.swimming_multiplier(setup) * _rescue_system.movement_multiplier(session, context.tow_definition)
			var motion: Dictionary = context.motion
			var command: Vector2 = _arrival_command(
				to_waypoint,
				current,
				float(motion.swim_speed),
				float(motion.acceleration),
				speed_multiplier
			)
			var velocity: Vector2 = DiveMovementSystemScript.advance_velocity(
				context.velocity,
				command,
				false,
				current,
				speed_multiplier,
				delta,
				float(motion.swim_speed),
				float(motion.sprint_speed),
				float(motion.acceleration),
				float(motion.drag)
			)
			var proposed: Vector2 = position + velocity * delta
			if not snapshot.is_position_clear(proposed) or not snapshot.is_segment_clear(position, proposed):
				context["replay_failure_detail"] = (
					"Replay wyszedł poza prześwit na segmencie %d: pozycja %s, krok %s, waypoint %s, prędkość %s, prąd %s."
					% [index, position, proposed, waypoint, velocity, raw_current]
				)
				return CertificateScript.REPLAY_GEOMETRY_DIVERGED
			context.position = proposed
			context.velocity = velocity
			var tick_failure: StringName = _advance_runtime_tick(context, delta, true, raw_current.length_squared() > 0.01)
			if tick_failure != &"":
				return tick_failure
	return &""


func _replay_interaction(context: Dictionary, descriptor: Dictionary, emit_noise: bool = true) -> StringName:
	context.erase("replay_failure_detail")
	var interaction_seconds := maxf(float(descriptor.get("interaction_seconds", 0.0)), 0.0)
	var action_id := str(descriptor.get("interaction_action", "open"))
	var interaction_anchor: Vector2 = context.position
	var target_position: Vector2 = descriptor.get("position", interaction_anchor)
	if Vector2(context.velocity).length() <= ARRIVAL_SPEED_TOLERANCE:
		context.velocity = Vector2.ZERO
	var progress := 0.0
	while progress + 0.0001 < interaction_seconds:
		if float(context.elapsed) >= float(context.policy.maximum_replay_seconds):
			return CertificateScript.REPLAY_LIMIT_EXCEEDED
		var delta := minf(float(context.policy.fixed_step_seconds), float(context.policy.maximum_replay_seconds) - float(context.elapsed))
		var snapshot = context.snapshot
		var setup = context.setup
		var session = context.session
		var position: Vector2 = context.position
		var raw_current: Vector2 = snapshot.current_at(position)
		var current: Vector2 = raw_current * _modifier(setup, "current_strength_multiplier")
		var risk_multiplier: float = _temperature_system.movement_multiplier(session.cold_exposure)
		var speed_multiplier: float = risk_multiplier * CompetencySystemScript.swimming_multiplier(setup) * _rescue_system.movement_multiplier(session, context.tow_definition)
		var motion: Dictionary = context.motion
		var command := _arrival_command(
			interaction_anchor - position,
			current,
			float(motion.swim_speed),
			float(motion.acceleration),
			speed_multiplier
		)
		var velocity: Vector2 = DiveMovementSystemScript.advance_velocity(
			context.velocity,
			command,
			false,
			current,
			speed_multiplier,
			delta,
			float(motion.swim_speed),
			float(motion.sprint_speed),
			float(motion.acceleration),
			float(motion.drag)
		)
		var proposed := position + velocity * delta
		if not snapshot.is_position_clear(proposed) or not snapshot.is_segment_clear(position, proposed):
			context["replay_failure_detail"] = (
				"Replay interakcji wyszedł poza prześwit: pozycja %s, krok %s, cel %s, prędkość %s, prąd %s."
				% [position, proposed, target_position, velocity, raw_current]
			)
			return CertificateScript.REPLAY_GEOMETRY_DIVERGED
		if proposed.distance_to(target_position) > DiveInteractionRulesScript.INTERACTION_DISTANCE:
			context["replay_failure_detail"] = (
				"Replay interakcji utracił zasięg celu: pozycja %s, krok %s, cel %s, prędkość %s, prąd %s."
				% [position, proposed, target_position, velocity, raw_current]
			)
			return CertificateScript.REPLAY_GEOMETRY_DIVERGED
		context.position = proposed
		context.velocity = velocity
		var interaction_multiplier: float = context.risk_runtime.interaction_speed_multiplier(context.session, context.setup)
		progress += delta * interaction_multiplier
		var tick_failure := _advance_runtime_tick(
			context,
			delta,
			command.length_squared() > 0.01,
			raw_current.length_squared() > 0.01
		)
		if tick_failure != &"":
			return tick_failure
	if emit_noise and str(descriptor.get("kind", "")) != "pickup" and not action_id.is_empty():
		context.risk_runtime.emit_action_noise(context.session, context.setup, action_id, context.position)
	return &""


func _advance_runtime_tick(context: Dictionary, delta: float, is_moving: bool, in_current: bool) -> StringName:
	var session = context.session
	var setup = context.setup
	var oxygen_rate := _oxygen_system.consumption_rate(
		is_moving,
		false,
		session.carry_ratio(),
		in_current,
		CompetencySystemScript.load_oxygen_surcharge_multiplier(setup)
	)
	var rescue_oxygen_multiplier := _rescue_system.oxygen_multiplier(session, context.tow_definition)
	session.oxygen_left = _oxygen_system.consume(
		session.oxygen_left,
		delta,
		oxygen_rate * _modifier(setup, "oxygen_use_multiplier") * rescue_oxygen_multiplier * CompetencySystemScript.oxygen_use_multiplier(setup)
	)
	session.elapsed_time += delta
	context.elapsed = float(context.elapsed) + delta
	if _is_exposed_to_active_threat(context.threats, context.position):
		context.threat_exposure_seconds = float(context.threat_exposure_seconds) + delta
	if session.oxygen_left <= 0.0:
		_populate_outcome(
			context.certificate,
			session,
			float(context.elapsed),
			float(context.threat_exposure_seconds)
		)
		return CertificateScript.OXYGEN_DEPLETED
	var risk_update: Dictionary = context.risk_runtime.advance(
		session,
		setup,
		context.threats,
		context.position,
		context.snapshot.depth_at(context.position),
		false,
		delta,
		session.light_enabled
	)
	_populate_outcome(
		context.certificate,
		session,
		float(context.elapsed),
		float(context.threat_exposure_seconds)
	)
	if session.health <= 0 or not str(risk_update.get("death_reason", "")).is_empty():
		return CertificateScript.DIVER_DIED
	return &""


func _is_exposed_to_active_threat(threats: Array, world_position: Vector2) -> bool:
	for threat in threats:
		if threat == null or not is_instance_valid(threat) or threat.definition == null:
			continue
		if threat.has_method("is_defeated") and threat.is_defeated():
			continue
		var exposure_radius := maxf(
			float(threat.definition.light_detection_radius),
			float(threat.definition.noise_detection_radius)
		)
		if threat.global_position.distance_to(world_position) <= exposure_radius:
			return true
	return false


func _begin_conservative_tow(session, descriptor: Dictionary) -> void:
	session.towed_survivor = Resource.new()
	session.towed_rescue_encounter_id = str(descriptor.get("id", ""))
	session.towed_survivor_stabilized = false
	if not session.rescued_survivor_ids.has(session.towed_rescue_encounter_id):
		session.rescued_survivor_ids.append(session.towed_rescue_encounter_id)


func _build_threat_nodes(snapshot) -> Array:
	var result: Array = []
	for descriptor in snapshot.threat_descriptors():
		var definition = descriptor.get("definition", null)
		if definition == null:
			continue
		var threat = DiveThreatScript.new()
		threat.configure(str(descriptor.get("id", "")), definition.duplicate(true))
		threat.position = descriptor.get("position", Vector2.ZERO)
		result.append(threat)
	return result


func _free_threat_nodes(threats: Array) -> void:
	for threat in threats:
		if threat != null and is_instance_valid(threat):
			threat.free()
	threats.clear()


func _motion_parameters() -> Dictionary:
	if not _cached_motion_parameters.is_empty():
		return _cached_motion_parameters.duplicate()
	var diver = DiverScene.instantiate()
	_cached_motion_parameters = {
		"swim_speed": float(diver.swim_speed),
		"sprint_speed": float(diver.sprint_speed),
		"acceleration": float(diver.acceleration),
		"drag": float(diver.drag),
	}
	diver.free()
	return _cached_motion_parameters.duplicate()


func _base_swim_speed() -> float:
	if _cached_motion_parameters.is_empty():
		_motion_parameters()
	return float(_cached_motion_parameters.get("swim_speed", 175.0))


func _tow_movement_multiplier(definition) -> float:
	return float(definition.unstabilized_movement_multiplier) if definition != null else 1.0


func _tow_oxygen_multiplier(definition) -> float:
	return float(definition.unstabilized_oxygen_multiplier) if definition != null else 1.0


func _arrival_command(
	to_waypoint: Vector2,
	current: Vector2,
	base_swim_speed: float,
	acceleration: float,
	speed_multiplier: float
) -> Vector2:
	var maximum_speed := base_swim_speed * clampf(speed_multiplier, 0.1, 1.5)
	if maximum_speed <= 0.0:
		return Vector2.ZERO
	var braking_distance := maxf(to_waypoint.length() - WAYPOINT_TOLERANCE, 0.0)
	var desired_speed := minf(
		maximum_speed,
		sqrt(2.0 * maxf(acceleration, 1.0) * braking_distance)
	)
	var desired_velocity := (
		to_waypoint.normalized() * desired_speed
		if to_waypoint.length_squared() > 0.000001
		else Vector2.ZERO
	)
	return ((desired_velocity - current) / maximum_speed).limit_length(1.0)


func _nearest_clear_cell(snapshot, world_position: Vector2, maximum_radius: int) -> Vector2i:
	var center: Vector2i = snapshot.world_to_cell(world_position)
	if snapshot.is_cell_clear(center):
		return center
	for radius in range(1, maximum_radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			for x in [center.x - radius, center.x + radius]:
				var candidate := Vector2i(x, y)
				if snapshot.is_cell_clear(candidate):
					return candidate
		for x in range(center.x - radius + 1, center.x + radius):
			for y in [center.y - radius, center.y + radius]:
				var candidate := Vector2i(x, y)
				if snapshot.is_cell_clear(candidate):
					return candidate
	return Vector2i(-1, -1)


func _simplify_path(
	snapshot,
	planning_safety_snapshot,
	raw_path: PackedVector2Array,
	clearance_cache: Dictionary,
	safety_clearance_cache: Dictionary
) -> PackedVector2Array:
	if raw_path.size() <= 2:
		return raw_path
	var result := PackedVector2Array([raw_path[0]])
	var anchor_index := 0
	while anchor_index < raw_path.size() - 1:
		var next_index := mini(anchor_index + PATH_SIMPLIFICATION_WINDOW, raw_path.size() - 1)
		while next_index > anchor_index + 1 and not _current_aware_planner_segment_is_clear(
			snapshot,
			planning_safety_snapshot,
			raw_path[anchor_index],
			raw_path[next_index],
			clearance_cache,
			safety_clearance_cache
		):
			next_index -= 1
		result.append(raw_path[next_index])
		anchor_index = next_index
	return result


func _path_distance(path: PackedVector2Array) -> float:
	var result := 0.0
	for index in range(1, path.size()):
		result += path[index - 1].distance_to(path[index])
	return result


func _append_route(certificate, path: PackedVector2Array) -> void:
	for point in path:
		if certificate.route.is_empty() or certificate.route[-1].distance_to(point) > 0.01:
			certificate.route.append(point)


func _meets_safety_policy(certificate, policy) -> bool:
	return (
		float(certificate.oxygen_reserve_ratio) >= float(policy.minimum_oxygen_reserve_ratio)
		and float(certificate.health_reserve_ratio) >= float(policy.minimum_health_reserve_ratio)
		and int(certificate.suit_condition_remaining) >= int(policy.minimum_suit_condition)
		and float(certificate.cold_exposure) <= float(policy.maximum_cold_exposure)
	)


func _populate_outcome(
	certificate,
	session,
	elapsed: float,
	threat_exposure_seconds: float
) -> void:
	certificate.oxygen_required = maxf(session.oxygen_capacity - session.oxygen_left, 0.0)
	certificate.oxygen_remaining = session.oxygen_left
	certificate.oxygen_reserve_ratio = session.oxygen_ratio()
	certificate.cargo_mass = session.get_carried_weight()
	certificate.cargo_slots = session.slots_used()
	certificate.threat_exposure_seconds = maxf(threat_exposure_seconds, 0.0)
	certificate.health_remaining = session.health
	certificate.health_reserve_ratio = session.health_ratio()
	certificate.suit_condition_remaining = session.suit_condition
	certificate.cold_exposure = session.cold_exposure
	certificate.elapsed_seconds = elapsed


func _populate_report_identity(report, query, policy, profile_id: StringName, difficulty_id: StringName) -> void:
	report.query_id = query.query_id if query != null and "query_id" in query else &""
	report.profile_id = profile_id
	report.difficulty_profile_id = difficulty_id
	report.safety_policy_id = policy.policy_id if policy != null and "policy_id" in policy else &""
	report.requested_resource_id = str(query.resource_id) if query != null and "resource_id" in query else ""
	report.requested_amount = int(query.requested_amount) if query != null and "requested_amount" in query else 0
	report.requested_manifest = query.normalized_requested_manifest() if query != null and query.has_method("normalized_requested_manifest") else {}


func _populate_certificate_identity(certificate, query, policy, profile_id: StringName, difficulty_id: StringName, trip_index: int) -> void:
	certificate.query_id = query.query_id if query != null and "query_id" in query else &""
	certificate.profile_id = profile_id
	certificate.difficulty_profile_id = difficulty_id
	certificate.safety_policy_id = policy.policy_id if policy != null and "policy_id" in policy else &""
	certificate.trip_index = trip_index
	if query != null and "target_ids" in query:
		certificate.target_ids.assign(query.target_ids)


func _fail(certificate, reason_code: StringName, detail: String) -> Resource:
	certificate.feasible = false
	certificate.safe = false
	certificate.reason_code = reason_code
	certificate.reason_detail = detail
	return certificate


func _first_failure_code(certificates: Array[Resource]) -> StringName:
	for certificate in certificates:
		if certificate != null and not bool(certificate.feasible):
			return certificate.reason_code
	return CertificateScript.QUANTITY_NOT_RECOVERED


func _modifier(setup, modifier_id: String, fallback: float = 1.0) -> float:
	if setup == null:
		return fallback
	return maxf(float(setup.difficulty_modifiers.get(modifier_id, fallback)), 0.0)


func _cell_key(cell: Vector2i, grid_width: int) -> int:
	return cell.y * grid_width + cell.x


func _heap_push(cells: Array[Vector2i], priorities: Array[float], cell: Vector2i, priority: float) -> void:
	cells.append(cell)
	priorities.append(priority)
	var index := cells.size() - 1
	while index > 0:
		var parent := floori(float(index - 1) / 2.0)
		if priorities[parent] <= priorities[index]:
			break
		var parent_cell := cells[parent]
		cells[parent] = cells[index]
		cells[index] = parent_cell
		var parent_priority := priorities[parent]
		priorities[parent] = priorities[index]
		priorities[index] = parent_priority
		index = parent


func _heap_pop(cells: Array[Vector2i], priorities: Array[float]) -> Vector2i:
	var result := cells[0]
	var last_cell: Vector2i = cells.pop_back()
	var last_priority: float = priorities.pop_back()
	if cells.is_empty():
		return result
	cells[0] = last_cell
	priorities[0] = last_priority
	var index := 0
	while true:
		var left := index * 2 + 1
		var right := left + 1
		if left >= cells.size():
			break
		var smallest := left
		if right < cells.size() and priorities[right] < priorities[left]:
			smallest = right
		if priorities[index] <= priorities[smallest]:
			break
		var swap_cell := cells[index]
		cells[index] = cells[smallest]
		cells[smallest] = swap_cell
		var swap_priority := priorities[index]
		priorities[index] = priorities[smallest]
		priorities[smallest] = swap_priority
		index = smallest
	return result
