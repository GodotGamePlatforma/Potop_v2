class_name BoatExpeditionState
extends Resource

const OutcomeSnapshotScript := preload("res://scripts/data/BoatExpeditionOutcomeSnapshot.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const RosterRotationSystemScript := preload("res://scripts/base/RosterRotationSystem.gd")

@export var instance_id: String = ""
@export var route_id: String = ""
@export var priority_id: String = "balanced"
@export var leader_survivor_id: String = ""
@export var launch_day: int = 0
@export var duration_days: int = 0
@export var return_day: int = 0
@export var fishing_hut_level_at_launch: int = 0
@export var food_per_adult_at_launch: int = 0
@export var leader_health_at_launch: int = 0
@export var reserved_provisions: Dictionary = {}
@export var outcome_seed: int = 0
@export var balance_version: int = 0
@export var balance_signature: String = ""
@export var outcome_snapshot: Resource

const VALID_PRIORITY_IDS: Array[String] = ["balanced", "supplies", "survivors"]


func validation_errors() -> PackedStringArray:
	var errors: Array[String] = []
	if not instance_id.begins_with(RosterRotationSystemScript.EXPEDITION_ID_PREFIX + ":"):
		errors.append("Ekspedycja łodzią nie ma stabilnego instance_id.")
	if route_id.strip_edges().is_empty() or leader_survivor_id.strip_edges().is_empty():
		errors.append("Ekspedycja łodzią nie ma pełnej tożsamości trasy i dowódcy.")
	if not VALID_PRIORITY_IDS.has(priority_id):
		errors.append("Ekspedycja łodzią ma nieznany priorytet.")
	if launch_day < 1:
		errors.append("Dzień wypłynięcia ekspedycji musi być dodatni.")
	if not RosterRotationSystemScript.is_supported_duration(duration_days):
		errors.append("Ekspedycja łodzią ma nieobsługiwany czas trwania.")
	if return_day != RosterRotationSystemScript.return_day(launch_day, duration_days):
		errors.append("Dzień powrotu ekspedycji nie odpowiada dniowi wypłynięcia i czasowi trwania.")
	if fishing_hut_level_at_launch < RosterRotationSystemScript.MIN_FISHING_HUT_LEVEL or fishing_hut_level_at_launch > 4:
		errors.append("Ekspedycja łodzią ma niepoprawny poziom Chaty z chwili wypłynięcia.")
	if fishing_hut_level_at_launch < 4 and priority_id != "balanced":
		errors.append("Priorytet zapasów albo ocalałych wymaga Chaty Rybackiej IV.")
	if food_per_adult_at_launch < 1:
		errors.append("Ekspedycja łodzią nie ma zamrożonego kosztu jedzenia na osobę.")
	if leader_health_at_launch < 1:
		errors.append("Ekspedycja łodzią nie ma dodatniego zdrowia dowódcy z chwili wypłynięcia.")
	if reserved_provisions.size() != 1 or not reserved_provisions.has(ResourceIdsScript.FOOD):
		errors.append("Ekspedycja łodzią musi zamrozić dokładnie pełny koszt żywności.")
	elif (
		typeof(reserved_provisions[ResourceIdsScript.FOOD]) != TYPE_INT
		or int(reserved_provisions[ResourceIdsScript.FOOD])
		!= RosterRotationSystemScript.provision_food_cost(food_per_adult_at_launch, duration_days)
	):
		errors.append("Zamrożony prowiant ekspedycji nie odpowiada pełnemu kosztowi czasu i profilu kampanii.")
	if outcome_seed < 1:
		errors.append("Ekspedycja łodzią nie ma dodatniego, zamrożonego ziarna wyniku.")
	if balance_version < 1 or balance_signature.length() != 64:
		errors.append("Ekspedycja łodzią nie ma wersjonowanego podpisu definicji balansu.")
	if outcome_snapshot == null or outcome_snapshot.get_script() != OutcomeSnapshotScript:
		errors.append("Ekspedycja łodzią nie ma typowanej migawki wyniku.")
	else:
		for outcome_error in outcome_snapshot.validation_errors():
			errors.append(str(outcome_error))
		if outcome_snapshot.candidate_snapshots.size() > 1 and (duration_days < 4 or fishing_hut_level_at_launch < 4):
			errors.append("Druga kandydatura wymaga czterodniowej ekspedycji z Chaty Rybackiej IV.")
		if leader_health_at_launch + int(outcome_snapshot.leader_health_delta) < 1:
			errors.append("Zamrożony wynik nie może zabić dowódcy, który w pierwszym pionie zawsze wraca.")
		for candidate_index in outcome_snapshot.candidate_snapshots.size():
			var candidate = outcome_snapshot.candidate_snapshots[candidate_index]
			if candidate == null:
				continue
			var expected_id := RosterRotationSystemScript.candidate_instance_id(instance_id, candidate_index + 1)
			if str(candidate.get("id")) != expected_id:
				errors.append("Kandydatura %d nie należy do tej ekspedycji." % (candidate_index + 1))
	return PackedStringArray(errors)


func is_valid() -> bool:
	return validation_errors().is_empty()
