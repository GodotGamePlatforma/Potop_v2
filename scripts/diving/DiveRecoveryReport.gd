class_name DiveRecoveryReport
extends Resource


@export var query_id: StringName = &""
@export var profile_id: StringName = &""
@export var difficulty_profile_id: StringName = &""
@export var safety_policy_id: StringName = &""
@export var feasible: bool = false
@export var safe: bool = false
@export var reason_code: StringName = &"INVALID_QUERY"
@export var requested_resource_id: String = ""
@export var requested_amount: int = 0
@export var requested_manifest: Dictionary = {}
@export var recovered_amount: int = 0
@export var certificates: Array[Resource] = []


func to_dictionary(include_routes: bool = true) -> Dictionary:
	var certificate_values: Array = []
	for certificate in certificates:
		if certificate != null and certificate.has_method("to_dictionary"):
			certificate_values.append(certificate.to_dictionary(include_routes))
	return {
		"query_id": str(query_id),
		"profile_id": str(profile_id),
		"difficulty_profile_id": str(difficulty_profile_id),
		"safety_policy_id": str(safety_policy_id),
		"feasible": feasible,
		"safe": safe,
		"reason_code": str(reason_code),
		"requested_resource_id": requested_resource_id,
		"requested_amount": requested_amount,
		"requested_manifest": requested_manifest.duplicate(true),
		"recovered_amount": recovered_amount,
		"required_trip_count": certificate_values.size(),
		"certificates": certificate_values,
	}
