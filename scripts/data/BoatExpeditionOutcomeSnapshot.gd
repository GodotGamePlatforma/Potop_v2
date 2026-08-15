class_name BoatExpeditionOutcomeSnapshot
extends Resource

const MAX_CANDIDATES := 2
const VALID_RESULT_TIERS: Array[String] = ["failed", "lean", "standard", "rich"]
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const DiseaseCaseStateScript := preload("res://scripts/data/DiseaseCaseState.gd")
const CompetencySystemScript := preload("res://scripts/base/CompetencySystem.gd")
const RosterRotationSystemScript := preload("res://scripts/base/RosterRotationSystem.gd")
const SurvivorStateScript := preload("res://scripts/data/SurvivorState.gd")

@export var result_tier: String = ""
@export_multiline var summary_text: String = ""
@export var reward_resource_deltas: Dictionary = {}
@export var leader_health_delta: int = 0
@export var leader_hunger_delta: int = 0
@export var leader_fatigue_delta: int = 0
@export var leader_morale_delta: int = 0
@export var candidate_snapshots: Array[Resource] = []


func detached_copy():
	var result = duplicate(true)
	if result != null:
		result.resource_local_to_scene = true
	return result


func candidate_ids() -> Array[String]:
	var result: Array[String] = []
	for candidate in candidate_snapshots:
		if candidate != null and candidate.get_script() == SurvivorStateScript:
			result.append(str(candidate.id))
	return result


func validation_errors() -> PackedStringArray:
	var errors: Array[String] = []
	if not VALID_RESULT_TIERS.has(result_tier):
		errors.append("Migawka wyniku ekspedycji łodzią ma nieznany poziom rezultatu.")
	if summary_text.strip_edges().is_empty():
		errors.append("Migawka wyniku ekspedycji łodzią nie ma zamrożonego opisu.")
	if leader_health_delta < -100 or leader_health_delta > 0:
		errors.append("Utrata zdrowia dowódcy ekspedycji musi mieścić się w zakresie -100..0.")
	if leader_hunger_delta < 0 or leader_hunger_delta > 100:
		errors.append("Przyrost głodu dowódcy ekspedycji musi mieścić się w zakresie 0..100.")
	if leader_fatigue_delta < 0 or leader_fatigue_delta > 100:
		errors.append("Przyrost zmęczenia dowódcy ekspedycji musi mieścić się w zakresie 0..100.")
	if leader_morale_delta < -100 or leader_morale_delta > 100:
		errors.append("Zmiana morale dowódcy ekspedycji musi mieścić się w zakresie -100..100.")

	var known_resource_ids := ResourceIdsScript.all()
	for raw_resource_id in reward_resource_deltas.keys():
		var resource_id := str(raw_resource_id)
		if typeof(raw_resource_id) != TYPE_STRING or not known_resource_ids.has(resource_id):
			errors.append("Migawka wyniku ekspedycji ma nieznany zasób nagrody %s." % resource_id)
			continue
		if resource_id in [ResourceIdsScript.HOPE, ResourceIdsScript.PLATFORM_INTEGRITY]:
			errors.append("Ekspedycja łodzią nie może bezpośrednio przyznać zasobu %s." % resource_id)
		if typeof(reward_resource_deltas[raw_resource_id]) != TYPE_INT or int(reward_resource_deltas[raw_resource_id]) < 0:
			errors.append("Nagroda zasobu %s musi być nieujemną liczbą całkowitą." % resource_id)

	if candidate_snapshots.size() > MAX_CANDIDATES:
		errors.append("Jedna ekspedycja łodzią może przywieźć najwyżej dwie kandydatury.")
	var seen_candidate_ids: Dictionary = {}
	for candidate in candidate_snapshots:
		if candidate == null or candidate.get_script() != SurvivorStateScript:
			errors.append("Migawka wyniku ekspedycji zawiera kandydaturę niewłaściwego typu.")
			continue
		var candidate_id := str(candidate.id).strip_edges()
		if candidate_id.is_empty() or seen_candidate_ids.has(candidate_id):
			errors.append("Migawka wyniku ekspedycji ma pusty lub powielony identyfikator kandydatury.")
		else:
			seen_candidate_ids[candidate_id] = true
		if str(candidate.display_name).strip_edges().is_empty() or str(candidate.profession).strip_edges().is_empty():
			errors.append("Kandydatura %s nie ma pełnej tożsamości albo zawodu." % candidate_id)
		if not RosterRotationSystemScript.is_valid_candidate_profession(str(candidate.profession)):
			errors.append("Kandydatura %s ma profesję bez wykonywalnego skutku." % candidate_id)
		if (
			not str(candidate.secondary_profession).is_empty()
			and not RosterRotationSystemScript.is_valid_candidate_profession(str(candidate.secondary_profession))
		):
			errors.append("Kandydatura %s ma nieznaną drugą profesję." % candidate_id)
		if str(candidate.secondary_profession) == str(candidate.profession):
			errors.append("Kandydatura %s ma powieloną profesję główną i dodatkową." % candidate_id)
		if int(candidate.status) not in [SurvivorStateScript.Status.AVAILABLE, SurvivorStateScript.Status.INJURED]:
			errors.append("Kandydatura %s nie opisuje żywej osoby gotowej wejść do rosteru." % candidate_id)
		if not str(candidate.current_assignment).is_empty():
			errors.append("Kandydatura %s ma przydział należący do innego stanu kampanii." % candidate_id)
		if int(candidate.health) <= 0 or int(candidate.health) > int(candidate.get_max_health()):
			errors.append("Kandydatura %s ma niepoprawne zdrowie." % candidate_id)
		for field_name in ["hunger", "fatigue", "morale"]:
			var value := int(candidate.get(field_name))
			if value < 0 or value > 100:
				errors.append("Kandydatura %s ma %s poza zakresem 0..100." % [candidate_id, field_name])
		var seen_injuries: Dictionary = {}
		for injury_id in candidate.injury_states:
			if injury_id.strip_edges().is_empty() or seen_injuries.has(injury_id):
				errors.append("Kandydatura %s ma pusty albo powielony uraz." % candidate_id)
			else:
				seen_injuries[injury_id] = true
		var seen_diseases: Dictionary = {}
		for disease_case in candidate.disease_cases:
			if disease_case == null or disease_case.get_script() != DiseaseCaseStateScript or not disease_case.is_valid():
				errors.append("Kandydatura %s ma niepoprawny przypadek choroby." % candidate_id)
			continue
			var disease_id := str(disease_case.disease_id)
			if seen_diseases.has(disease_id):
				errors.append("Kandydatura %s ma powielony przypadek choroby %s." % [candidate_id, disease_id])
			else:
				seen_diseases[disease_id] = true
		for competency_id in candidate.competency_levels.keys():
			var level := int(candidate.competency_levels[competency_id])
			if not CompetencySystemScript.is_valid_id(str(competency_id)) or level < 1 or level > CompetencySystemScript.MAX_LEVEL:
				errors.append("Kandydatura %s ma niepoprawny poziom kompetencji %s." % [candidate_id, competency_id])
	return PackedStringArray(errors)


func is_valid() -> bool:
	return validation_errors().is_empty()
