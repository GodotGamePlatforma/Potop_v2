class_name DiveRecoveryQuery
extends Resource


enum TripMode {
	SINGLE_TRIP,
	INDEPENDENT_TRIPS,
}

@export var query_id: StringName = &""
@export var target_ids: Array[String] = []
@export var resource_id: String = ""
@export_range(0, 1000000, 1) var requested_amount: int = 0
@export var requested_manifest: Dictionary = {}
@export_enum("single_trip", "independent_trips") var trip_mode: int = TripMode.SINGLE_TRIP
@export var allow_combining_sources: bool = false
@export var require_full_targets: bool = false


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if str(query_id).strip_edges().is_empty():
		errors.append("query_id must not be empty")
	if target_ids.is_empty():
		errors.append("target_ids must contain at least one explicit source")
	var seen: Dictionary = {}
	for target_id in target_ids:
		var normalized := target_id.strip_edges()
		if normalized.is_empty():
			errors.append("target_ids must not contain empty ids")
		elif seen.has(normalized):
			errors.append("target_ids must not contain duplicate ids")
		else:
			seen[normalized] = true
	if target_ids.size() > 1 and not allow_combining_sources:
		errors.append("multiple target_ids require allow_combining_sources")
	if requested_amount < 0:
		errors.append("requested_amount must be non-negative")
	if resource_id.strip_edges().is_empty() and requested_amount > 0:
		errors.append("requested_amount requires resource_id")
	if not requested_manifest.is_empty():
		if not resource_id.strip_edges().is_empty() or requested_amount > 0:
			errors.append("requested_manifest cannot be combined with resource_id or requested_amount")
		if require_full_targets:
			errors.append("requested_manifest cannot be combined with require_full_targets")
		if trip_mode != TripMode.SINGLE_TRIP:
			errors.append("requested_manifest requires single_trip")
		var manifest_ids: Dictionary = {}
		for manifest_key in requested_manifest.keys():
			var manifest_id := str(manifest_key).strip_edges()
			if manifest_id.is_empty():
				errors.append("requested_manifest must not contain empty resource ids")
			elif manifest_ids.has(manifest_id):
				errors.append("requested_manifest must not contain duplicate normalized resource ids")
			else:
				manifest_ids[manifest_id] = true
			var value_type := typeof(requested_manifest[manifest_key])
			if value_type != TYPE_INT or int(requested_manifest[manifest_key]) <= 0:
				errors.append("requested_manifest amounts must be positive integers")
	if trip_mode not in [TripMode.SINGLE_TRIP, TripMode.INDEPENDENT_TRIPS]:
		errors.append("trip_mode is invalid")
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


func normalized_requested_manifest() -> Dictionary:
	var result: Dictionary = {}
	for manifest_key in requested_manifest.keys():
		var manifest_id := str(manifest_key).strip_edges()
		if manifest_id.is_empty():
			continue
		result[manifest_id] = int(requested_manifest[manifest_key])
	return result


func detached_copy() -> DiveRecoveryQuery:
	return duplicate(true) as DiveRecoveryQuery
