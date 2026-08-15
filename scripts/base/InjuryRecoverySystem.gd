class_name InjuryRecoverySystem
extends RefCounted

const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")


## Pure projection shared by end-of-day treatment and its read-only UI forecast.
func project(injury_states: Array[String], health: int, status: int) -> Dictionary:
	var before: Array[String] = []
	before.assign(injury_states)
	var after: Array[String] = []
	after.assign(injury_states)

	if after.has("critical_rescue") and health >= 35:
		after.erase("critical_rescue")
		if not after.has("rescue_recovery"):
			after.append("rescue_recovery")
	if after.has("rescue_recovery") and health >= 50:
		after.erase("rescue_recovery")
	if health >= 75:
		for injury_id in after.duplicate():
			if str(injury_id) not in ["critical_rescue", "rescue_recovery"]:
				after.erase(str(injury_id))
				break

	var next_status := status
	if after.is_empty() and health >= 50 and status == SurvivorStateScript.Status.INJURED:
		next_status = SurvivorStateScript.Status.AVAILABLE
	return {
		"before": before,
		"after": after,
		"status_before": status,
		"status_after": next_status,
	}


func project_survivor(survivor, predicted_health: int) -> Dictionary:
	if survivor == null:
		return {"before": [], "after": [], "status_before": -1, "status_after": -1}
	var injuries: Array[String] = []
	injuries.assign(survivor.injury_states)
	return project(injuries, predicted_health, int(survivor.status))


func apply(survivor) -> Dictionary:
	if survivor == null:
		return {"before": [], "after": [], "status_before": -1, "status_after": -1}
	var result := project_survivor(survivor, int(survivor.health))
	survivor.injury_states.assign(result.get("after", []))
	survivor.status = int(result.get("status_after", survivor.status))
	return result


func display_name(injury_id: String) -> String:
	match injury_id:
		"hypothermia":
			return "wychłodzenie"
		"suit_breach":
			return "skutki rozszczelnienia kombinezonu"
		"puncture_wound":
			return "rana kłuta"
		"emergency_extraction":
			return "uraz po awaryjnym wyciągnięciu"
		"critical_rescue":
			return "stan krytyczny po ratowaniu"
		"rescue_recovery":
			return "rekonwalescencja po ratowaniu"
	return injury_id.replace("_", " ")
