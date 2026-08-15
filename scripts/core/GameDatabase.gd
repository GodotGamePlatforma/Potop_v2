extends Node

const BuildingDefinitionScript := preload("res://scripts/definitions/BuildingDefinition.gd")
const BuildingLevelDefinitionScript := preload("res://scripts/definitions/BuildingLevelDefinition.gd")
const DiseaseDefinitionScript := preload("res://scripts/definitions/DiseaseDefinition.gd")
const DiveLightingDefinitionScript := preload("res://scripts/definitions/DiveLightingDefinition.gd")
const DifficultyProfileScript := preload("res://scripts/definitions/DifficultyProfile.gd")
const MissionObjectiveDefinitionScript := preload("res://scripts/definitions/MissionObjectiveDefinition.gd")
const SettlementEventChoiceDefinitionScript := preload("res://scripts/definitions/SettlementEventChoiceDefinition.gd")
const SettlementEventDefinitionScript := preload("res://scripts/definitions/SettlementEventDefinition.gd")
const ProfessionTalentSystemScript := preload("res://scripts/base/ProfessionTalentSystem.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const UnderwaterMapSceneCompilerScript := preload("res://scripts/diving/UnderwaterMapSceneCompiler.gd")
const SETTLEMENT_EVENT_BALANCE_PATH := "res://data/balance/settlement_events.tres"
const DIVE_LIGHTING_PATH := "res://data/balance/dive_lighting.tres"


func _exit_tree() -> void:
	UnderwaterMapSceneCompilerScript.clear_runtime_caches()

const REQUIRED_BUILDING_IDS := [
	"fishing_hut",
	"kitchen",
	"community_house",
	"workshop",
	"infirmary",
	"diving_station",
]
const REQUIRED_DISEASE_IDS := ["flood_fever"]
const BUILDING_CAPABILITY_CONTRACTS := {
	"fishing_hut": [
		{"id": "food_per_worker", "from_level": 1, "value_contract": "positive_integer"},
		{"id": "fishing_pressure_per_food", "from_level": 1, "value_contract": "positive_number"},
	],
	"kitchen": [
		{"id": "ration_efficiency", "from_level": 1, "value_contract": "positive_unit_interval"},
	],
	"community_house": [
		{"id": "hope_per_worker", "from_level": 1, "value_contract": "positive_integer"},
		{"id": "shelter_capacity", "from_level": 1, "value_contract": "positive_integer"},
	],
	"workshop": [
		{"id": "platform_repair_per_worker", "from_level": 1, "value_contract": "positive_integer"},
		{"id": "production_queue_capacity", "from_level": 1, "value_contract": "positive_integer"},
		{"id": "production_slots_per_day", "from_level": 1, "value_contract": "positive_integer"},
		{"id": "repair_scrap_cost", "from_level": 1, "value_contract": "positive_integer"},
		{"id": "heavy_recovery_enabled", "from_level": 3, "value_contract": "enabled_boolean"},
	],
	"infirmary": [
		{"id": "healing_per_patient", "from_level": 1, "value_contract": "positive_integer"},
		{"id": "medicine_per_patient", "from_level": 1, "value_contract": "positive_integer"},
		{"id": "patient_capacity", "from_level": 1, "value_contract": "positive_integer"},
		{
			"id": "formal_isolation_capacity",
			"from_level": 1,
			"value_contract": "non_negative_integer",
			"expected_by_level": {1: 0, 2: 0, 3: 2, 4: 4},
		},
	],
	"diving_station": [
		{"id": "backpack_slots", "from_level": 1, "value_contract": "positive_integer"},
		{"id": "can_dive", "from_level": 1, "value_contract": "enabled_boolean"},
		{"id": "staffed_diver_carry_multiplier", "from_level": 1, "value_contract": "greater_than_one"},
		{"id": "operator_rescue_enabled", "from_level": 2, "value_contract": "enabled_boolean"},
		{"id": "buoy_enabled", "from_level": 3, "value_contract": "enabled_boolean"},
		{"id": "buoy_start_enabled", "from_level": 4, "value_contract": "enabled_boolean"},
		{"id": "heavy_marking_enabled", "from_level": 4, "value_contract": "enabled_boolean"},
		{"id": "technician_support_enabled", "from_level": 4, "value_contract": "enabled_boolean"},
		{"id": "technician_suit_damage_multiplier", "from_level": 4, "value_contract": "open_unit_interval"},
	],
}
const BUILDING_SPECIALIST_BONUS_CONTRACTS := {
	"fishing_hut": {"production_bonus": "positive_number"},
	"kitchen": {"ration_efficiency_bonus": "positive_number"},
	"community_house": {"hope_bonus": "positive_number"},
	"workshop": {"repair_bonus": "positive_number"},
	"infirmary": {"healing_bonus": "positive_number"},
	"diving_station": {
		"oxygen_bonus": "positive_number",
		"oxygen_capacity_multiplier": "greater_than_one",
	},
}

const REQUIRED_OXYGEN_TANKS := {
	"oxygen_tank_mk1": {"tier": 1, "oxygen_capacity": 100.0},
	"oxygen_tank_mk2": {"tier": 2, "oxygen_capacity": 130.0},
	"oxygen_tank_mk3": {"tier": 3, "oxygen_capacity": 160.0},
}

var difficulty_profiles: Dictionary = {}
var difficulty_profiles_by_id: Dictionary = {}
var diseases: Dictionary = {}
var buildings: Dictionary = {}
var items: Dictionary = {}
var diving_gear: Dictionary = {}
var workshop_recipes: Dictionary = {}
var threats: Dictionary = {}
var rescue_encounters: Dictionary = {}
var settlement_events: Dictionary = {}
var settlement_event_balance: Resource
var dive_lighting: Resource
var survivor_templates: Dictionary = {}
var professions: Dictionary = {}
var missions: Dictionary = {}
var validation_errors: Array[String] = []

func _ready() -> void:
	load_definitions()

func load_definitions() -> void:
	validation_errors.clear()
	difficulty_profiles = _load_resource_map("res://data/difficulty", "profile_name")
	_rebuild_difficulty_profile_index()
	diseases = _load_resource_map("res://data/diseases", "id")
	buildings = _load_resource_map("res://data/buildings", "id")
	items = _load_resource_map("res://data/items", "id")
	diving_gear = _load_resource_map("res://data/diving_gear", "id")
	workshop_recipes = _load_resource_map("res://data/workshop_recipes", "id")
	threats = _load_resource_map("res://data/threats", "id")
	rescue_encounters = _load_resource_map("res://data/survivors", "id")
	settlement_events = _load_resource_map("res://data/events", "id")
	settlement_event_balance = _load_required_resource(SETTLEMENT_EVENT_BALANCE_PATH)
	dive_lighting = _load_required_resource(DIVE_LIGHTING_PATH)
	survivor_templates = _load_resource_map("res://data/survivor_templates", "id")
	professions = _load_resource_map("res://data/professions", "id")
	missions = _load_resource_map("res://data/missions", "id")
	_validate_definitions()
	for talent_error in ProfessionTalentSystemScript.new().validation_errors():
		validation_errors.append("Talenty zawodowe: %s" % talent_error)
	for message in validation_errors:
		push_error("GameDatabase: %s" % message)

func get_standard_difficulty():
	return difficulty_profiles_by_id.get("standard", DifficultyProfileScript.new())


func get_difficulty_profile(profile_id: String):
	return difficulty_profiles_by_id.get(profile_id.strip_edges())


func get_disease_definition(disease_id: String):
	return diseases.get(disease_id.strip_edges())


func available_difficulty_profiles() -> Array:
	var result: Array = []
	for profile in difficulty_profiles_by_id.values():
		if profile != null and bool(profile.available_in_menu):
			result.append(profile)
	result.sort_custom(func(left, right): return str(left.profile_name) < str(right.profile_name))
	return result


func _rebuild_difficulty_profile_index() -> void:
	difficulty_profiles_by_id.clear()
	for profile in difficulty_profiles.values():
		if profile == null:
			continue
		var profile_id := str(profile.profile_id).strip_edges()
		if not profile_id.is_empty() and not difficulty_profiles_by_id.has(profile_id):
			difficulty_profiles_by_id[profile_id] = profile

func is_valid() -> bool:
	return validation_errors.is_empty()

func _load_resource_map(path: String, key_property: String) -> Dictionary:
	var result: Dictionary = {}
	var files = DirAccess.get_files_at(path)
	for file_name in files:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue

		var resource = ResourceLoader.load(path.path_join(file_name))
		if resource == null:
			validation_errors.append("Nie można wczytać %s." % path.path_join(file_name))
			continue

		var key = resource.get(key_property)
		if key == null or str(key).is_empty():
			validation_errors.append("%s nie zawiera pola %s." % [path.path_join(file_name), key_property])
			continue
		if result.has(str(key)):
			validation_errors.append("Powielony identyfikator %s w %s." % [str(key), path])
			continue
		result[str(key)] = resource
	return result


func _load_required_resource(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		validation_errors.append("Brak wymaganego zasobu %s." % path)
		return null
	var resource := ResourceLoader.load(path)
	if resource == null:
		validation_errors.append("Nie można wczytać %s." % path)
	return resource

func _validate_definitions() -> void:
	if dive_lighting == null or dive_lighting.get_script() != DiveLightingDefinitionScript:
		validation_errors.append("Definicja oświetlenia nurkowania ma niewłaściwy typ.")
	else:
		for lighting_error in dive_lighting.validation_errors():
			validation_errors.append("Oświetlenie nurkowania: %s." % lighting_error)
	if not difficulty_profiles.has("Standard"):
		validation_errors.append("Brak profilu trudności Standard.")
	var difficulty_profile_ids: Dictionary = {}
	for profile_name in difficulty_profiles.keys():
		var profile = difficulty_profiles[profile_name]
		if profile == null or not profile.has_method("validation_errors"):
			validation_errors.append("Profil trudności %s nie obsługuje pełnej walidacji." % profile_name)
			continue
		for profile_error in profile.validation_errors():
			validation_errors.append("Profil trudności %s: %s." % [profile_name, profile_error])
		var profile_id := str(profile.profile_id)
		if difficulty_profile_ids.has(profile_id):
			validation_errors.append("Powielony profile_id trudności %s w profilach %s i %s." % [profile_id, difficulty_profile_ids[profile_id], profile_name])
		else:
			difficulty_profile_ids[profile_id] = str(profile_name)
		if bool(profile.snapshot_sealed):
			validation_errors.append("Definicja profilu %s nie może być zamrożoną migawką kampanii." % profile_name)
		if int(profile.balance_version) != DifficultyProfileScript.CURRENT_BALANCE_VERSION:
			validation_errors.append("Profil trudności %s ma wersję balansu %d zamiast %d." % [profile_name, int(profile.balance_version), DifficultyProfileScript.CURRENT_BALANCE_VERSION])

	var disease_display_names: Dictionary = {}
	for disease_id_value in diseases.keys():
		var disease_id := str(disease_id_value)
		if not REQUIRED_DISEASE_IDS.has(disease_id):
			validation_errors.append("Nieoczekiwana definicja choroby %s; katalog produkcyjny jest zamknięty." % disease_id)
		var definition = diseases[disease_id_value]
		if definition == null or not (definition is Resource) or definition.get_script() != DiseaseDefinitionScript:
			validation_errors.append("Choroba %s ma niewłaściwy typ definicji." % disease_id)
			continue
		if str(definition.id) != disease_id:
			validation_errors.append("Definicja choroby %s ma identyfikator %s." % [disease_id, definition.id])
		for disease_error in definition.validation_errors():
			validation_errors.append("Choroba %s: %s." % [disease_id, disease_error])
		var normalized_name := str(definition.display_name).strip_edges().to_lower()
		if disease_display_names.has(normalized_name):
			validation_errors.append("Choroby %s i %s mają tę samą nazwę." % [disease_display_names[normalized_name], disease_id])
		else:
			disease_display_names[normalized_name] = disease_id
	for required_disease_id in REQUIRED_DISEASE_IDS:
		if not diseases.has(required_disease_id):
			validation_errors.append("Brak wymaganej definicji choroby %s." % required_disease_id)
	if diseases.has("flood_fever"):
		var flood_fever = diseases["flood_fever"]
		if flood_fever != null and flood_fever.get_script() == DiseaseDefinitionScript:
			if str(flood_fever.display_name) != "Gorączka Zalewowa" or int(flood_fever.definition_version) != 1:
				validation_errors.append("Produkcyjna Gorączka Zalewowa ma niepoprawną nazwę lub definition_version.")
			if flood_fever.authored_source_pressures != {"R1-06": 3}:
				validation_errors.append("Produkcyjna Gorączka Zalewowa musi mieć dokładnie źródło R1-06 o presji 3.")
			if flood_fever.ration_pressure_modifiers != {"full": -1, "half": 0, "none": 1}:
				validation_errors.append("Produkcyjna Gorączka Zalewowa ma niepoprawne modyfikatory faktycznej racji.")

	validation_errors.append_array(required_building_validation_errors(buildings))
	for building_id in buildings.keys():
		var definition = buildings[building_id]
		if definition == null or not (definition is Resource) or definition.get_script() != BuildingDefinitionScript:
			continue
		var is_required_building := REQUIRED_BUILDING_IDS.has(str(building_id))
		if not is_required_building and definition.max_level < 1:
			validation_errors.append("Budynek %s nie ma poprawnego max_level." % building_id)
		var cost_levels_by_number: Dictionary = {}
		for level_definition in definition.levels:
			if level_definition == null or not (level_definition is Resource) or level_definition.get_script() != BuildingLevelDefinitionScript:
				continue
			var level_number := int(level_definition.level)
			if not cost_levels_by_number.has(level_number):
				cost_levels_by_number[level_number] = level_definition
		for level in range(1, int(definition.max_level) + 1):
			var level_definition = cost_levels_by_number.get(level)
			if level_definition == null:
				if not is_required_building:
					validation_errors.append("Budynek %s nie ma definicji poziomu %d." % [building_id, level])
				continue
			_validate_cost(level_definition.build_cost, "budynek %s, poziom %d" % [building_id, level])
			_validate_cost(level_definition.upgrade_cost, "rozbudowa %s, poziom %d" % [building_id, level])

	_validate_professions(REQUIRED_BUILDING_IDS)

	for item_id in items.keys():
		var item = items[item_id]
		if item.display_name.is_empty() or item.weight <= 0.0:
			validation_errors.append("Przedmiot %s ma niepełną nazwę lub niepoprawną wagę." % item_id)
	for material_id in [ResourceIdsScript.FOOD, ResourceIdsScript.PLANKS, ResourceIdsScript.SCRAP, ResourceIdsScript.FABRIC_RUBBER, ResourceIdsScript.TECH_PARTS, ResourceIdsScript.MEDS_CHEMICALS]:
		if not items.has(material_id):
			validation_errors.append("Brak definicji przedmiotu %s." % material_id)
	for pickup_item_id in [ResourceIdsScript.FOOD, ResourceIdsScript.PLANKS, ResourceIdsScript.SCRAP]:
		if items.has(pickup_item_id) and items[pickup_item_id].world_pickup_texture == null:
			validation_errors.append("Przedmiot %s nie ma grafiki wolnostojącej znajdźki." % pickup_item_id)
	for gear_id in diving_gear.keys():
		var gear = diving_gear[gear_id]
		if gear.display_name.is_empty() or gear.equipment_slot.is_empty():
			validation_errors.append("Wyposażenie %s ma niepełne dane." % gear_id)
		elif gear.equipment_slot == "light" and not gear.is_valid_light():
			validation_errors.append("Źródło światła %s ma niepoprawne promienie." % gear_id)
		elif gear.equipment_slot == "oxygen_tank" and not gear.is_valid_oxygen_tank():
			validation_errors.append("Butla tlenowa %s ma niepoprawną pojemność." % gear_id)
		elif gear.equipment_slot == "weapon" and not gear.is_valid_weapon():
			validation_errors.append("Broń %s ma niepoprawne parametry walki." % gear_id)

	for tank_id in REQUIRED_OXYGEN_TANKS.keys():
		if not diving_gear.has(tank_id):
			validation_errors.append("Brak wymaganej butli tlenowej %s." % tank_id)
			continue
		var tank = diving_gear[tank_id]
		var expected: Dictionary = REQUIRED_OXYGEN_TANKS[tank_id]
		if str(tank.equipment_slot) != "oxygen_tank":
			validation_errors.append("Butla tlenowa %s musi używać slotu oxygen_tank." % tank_id)
		if int(tank.tier) != int(expected.tier):
			validation_errors.append("Butla tlenowa %s ma poziom %d zamiast %d." % [tank_id, int(tank.tier), int(expected.tier)])
		if not is_equal_approx(float(tank.oxygen_capacity), float(expected.oxygen_capacity)):
			validation_errors.append("Butla tlenowa %s ma pojemność %.0f zamiast %.0f." % [tank_id, float(tank.oxygen_capacity), float(expected.oxygen_capacity)])

	for recipe_id in workshop_recipes.keys():
		var recipe = workshop_recipes[recipe_id]
		if recipe.output_gear_id.is_empty() == recipe.output_campaign_id.is_empty():
			validation_errors.append("Receptura %s musi mieć dokładnie jeden wynik." % recipe_id)
		elif not recipe.output_gear_id.is_empty() and not diving_gear.has(recipe.output_gear_id):
			validation_errors.append("Receptura %s wskazuje brakujące wyposażenie %s." % [recipe_id, recipe.output_gear_id])
		if int(recipe.required_work_points) < 1:
			validation_errors.append("Receptura %s musi wymagać dodatniej pracy." % recipe_id)
		if not recipe.prerequisite_gear_id.is_empty() and not diving_gear.has(recipe.prerequisite_gear_id):
			validation_errors.append("Receptura %s wskazuje brakujący warunek %s." % [recipe_id, recipe.prerequisite_gear_id])
		_validate_cost(recipe.craft_cost, "receptura %s" % recipe_id)

	if not threats.has("noise_eel"):
		validation_errors.append("Brak definicji pierwszego zagrożenia noise_eel.")
	for threat_id in threats.keys():
		var threat = threats[threat_id]
		if threat == null or not threat.has_method("is_valid") or not threat.is_valid():
			validation_errors.append("Zagrożenie %s ma niepoprawne dane." % threat_id)

	if not rescue_encounters.has("leon_wrona"):
		validation_errors.append("Brak definicji pierwszego ocalałego leon_wrona.")
	var survivor_ids: Array[String] = []
	for rescue_id in rescue_encounters.keys():
		var rescue = rescue_encounters[rescue_id]
		if rescue == null or not rescue.has_method("is_valid") or not rescue.is_valid():
			validation_errors.append("Ocalały %s ma niepoprawne dane ratunkowe." % rescue_id)
			continue
		if survivor_ids.has(str(rescue.survivor_id)):
			validation_errors.append("Powielony identyfikator mieszkańca %s w definicjach ratunkowych." % rescue.survivor_id)
		else:
			survivor_ids.append(str(rescue.survivor_id))

	_validate_survivor_templates(survivor_ids)
	_validate_settlement_events()
	_validate_missions()


func required_building_validation_errors(candidate_buildings: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var display_names: Dictionary = {}
	var descriptions: Dictionary = {}
	for candidate_id in candidate_buildings.keys():
		if not REQUIRED_BUILDING_IDS.has(str(candidate_id)):
			errors.append("Nieoczekiwana definicja budynku %s; aktywna platforma obsługuje dokładnie sześć wymaganych typów." % candidate_id)
	for building_id in REQUIRED_BUILDING_IDS:
		if not candidate_buildings.has(building_id):
			errors.append("Brak definicji budynku %s." % building_id)
			continue
		var definition = candidate_buildings[building_id]
		if definition == null or not (definition is Resource) or definition.get_script() != BuildingDefinitionScript:
			errors.append("Budynek %s ma niewłaściwy typ definicji." % building_id)
			continue
		if str(definition.id) != building_id:
			errors.append("Definicja budynku %s ma identyfikator %s." % [building_id, definition.id])

		_validate_unique_building_text(errors, display_names, definition.display_name, building_id, "display_name")
		_validate_unique_building_text(errors, descriptions, definition.description, building_id, "description")
		_validate_required_building_levels(errors, building_id, definition)
		_validate_required_specialist_bonus(errors, building_id, definition.specialist_bonus)
	return errors


func _validate_unique_building_text(
	errors: Array[String],
	used_values: Dictionary,
	raw_value,
	building_id: String,
	property_name: String
) -> void:
	if typeof(raw_value) != TYPE_STRING or str(raw_value).strip_edges().is_empty():
		errors.append("Budynek %s ma pustą wartość %s." % [building_id, property_name])
		return
	var normalized_value := str(raw_value).strip_edges().to_lower()
	if used_values.has(normalized_value):
		errors.append("Budynki %s i %s mają tę samą wartość %s." % [used_values[normalized_value], building_id, property_name])
		return
	used_values[normalized_value] = building_id


func _validate_required_building_levels(errors: Array[String], building_id: String, definition) -> void:
	if int(definition.max_level) != 4:
		errors.append("Budynek %s musi mieć max_level równy 4." % building_id)
	if definition.levels.size() != 4:
		errors.append("Budynek %s musi zawierać dokładnie cztery definicje poziomów." % building_id)

	var levels_by_number: Dictionary = {}
	for level_definition in definition.levels:
		if level_definition == null or not (level_definition is Resource) or level_definition.get_script() != BuildingLevelDefinitionScript:
			errors.append("Budynek %s zawiera poziom o niewłaściwym typie danych." % building_id)
			continue
		var level := int(level_definition.level)
		if level < 1 or level > 4:
			errors.append("Budynek %s ma poziom o numerze %d poza zakresem 1-4." % [building_id, level])
			continue
		if levels_by_number.has(level):
			errors.append("Budynek %s ma powieloną definicję poziomu %d." % [building_id, level])
			continue
		levels_by_number[level] = level_definition
		if str(level_definition.display_name).strip_edges().is_empty():
			errors.append("Budynek %s, poziom %d ma pustą nazwę." % [building_id, level])
		if int(level_definition.worker_slots) <= 0:
			errors.append("Budynek %s, poziom %d musi mieć dodatnią liczbę stanowisk." % [building_id, level])

	for level in range(1, 5):
		if not levels_by_number.has(level):
			errors.append("Budynek %s nie ma definicji poziomu %d." % [building_id, level])
			continue
		var level_definition = levels_by_number[level]
		for contract in BUILDING_CAPABILITY_CONTRACTS.get(building_id, []):
			if level < int(contract.get("from_level", 1)):
				continue
			_validate_required_value(
				errors,
				level_definition.capabilities,
				str(contract.get("id", "")),
				str(contract.get("value_contract", "")),
				"Budynek %s, poziom %d" % [building_id, level]
			)
			var expected_by_level: Dictionary = contract.get("expected_by_level", {})
			if expected_by_level.has(level) and level_definition.capabilities.get(str(contract.get("id", ""))) != expected_by_level[level]:
				errors.append(
					"Budynek %s, poziom %d ma wartość %s inną niż wymagane %s."
					% [building_id, level, contract.get("id", ""), expected_by_level[level]]
				)


func _validate_required_specialist_bonus(errors: Array[String], building_id: String, specialist_bonus: Dictionary) -> void:
	var profession = specialist_bonus.get("profession")
	if typeof(profession) != TYPE_STRING or str(profession).strip_edges().is_empty():
		errors.append("Budynek %s nie ma niepustego zawodu w premii specjalisty." % building_id)
	for bonus_id in BUILDING_SPECIALIST_BONUS_CONTRACTS.get(building_id, {}).keys():
		_validate_required_value(
			errors,
			specialist_bonus,
			str(bonus_id),
			str(BUILDING_SPECIALIST_BONUS_CONTRACTS[building_id][bonus_id]),
			"Budynek %s, premia specjalisty" % building_id
		)


func _validate_required_value(
	errors: Array[String],
	values: Dictionary,
	value_id: String,
	value_contract: String,
	context: String
) -> void:
	if not values.has(value_id):
		errors.append("%s nie ma wymaganej wartości %s." % [context, value_id])
		return
	var value = values[value_id]
	if _value_matches_contract(value, value_contract):
		return
	errors.append("%s ma niepoprawną wartość %s; wymagany kontrakt: %s." % [context, value_id, value_contract])


func _value_matches_contract(value, value_contract: String) -> bool:
	match value_contract:
		"non_negative_integer":
			return typeof(value) == TYPE_INT and int(value) >= 0
		"positive_integer":
			return typeof(value) == TYPE_INT and int(value) > 0
		"positive_number":
			return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0
		"positive_unit_interval":
			return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0 and float(value) <= 1.0
		"open_unit_interval":
			return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0 and float(value) < 1.0
		"greater_than_one":
			return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 1.0
		"enabled_boolean":
			return typeof(value) == TYPE_BOOL and bool(value)
	return false


func _validate_professions(required_buildings: Array) -> void:
	var required_professions := ["rybak", "kucharz", "mechanik", "medyk", "organizator", "nurek"]
	var profession_by_building: Dictionary = {}
	for profession_id in required_professions:
		if not professions.has(profession_id):
			validation_errors.append("Brak definicji zawodu %s." % profession_id)
	for profession_id in professions.keys():
		var definition = professions[profession_id]
		if definition == null or not definition.has_method("is_valid") or not definition.is_valid():
			validation_errors.append("Zawód %s ma niepoprawne dane progresji." % profession_id)
			continue
		var building_id := str(definition.building_definition_id)
		if not buildings.has(building_id):
			validation_errors.append("Zawód %s wskazuje brakujący budynek %s." % [profession_id, building_id])
			continue
		if profession_by_building.has(building_id):
			validation_errors.append("Budynek %s ma więcej niż jedną główną ścieżkę zawodową." % building_id)
		else:
			profession_by_building[building_id] = str(profession_id)
		var building = buildings[building_id]
		if building == null or not (building is Resource) or building.get_script() != BuildingDefinitionScript:
			continue
		if str(building.specialist_bonus.get("profession", "")) != str(profession_id):
			validation_errors.append("Zawód %s nie odpowiada specjaliście budynku %s." % [profession_id, building_id])
	for building_id in required_buildings:
		if not profession_by_building.has(building_id):
			validation_errors.append("Budynek %s nie ma definicji ścieżki zawodowej." % building_id)

func _validate_survivor_templates(reserved_survivor_ids: Array[String]) -> void:
	var survivor_ids := reserved_survivor_ids.duplicate()
	for starting_id in ["mira", "anka", "igor"]:
		if not survivor_ids.has(starting_id):
			survivor_ids.append(starting_id)
	for survivor_id in survivor_templates.keys():
		var definition = survivor_templates[survivor_id]
		if definition == null or not definition.has_method("is_valid") or not definition.is_valid():
			validation_errors.append("Szablon mieszkańca %s ma niepoprawne dane." % survivor_id)
			continue
		if survivor_ids.has(str(definition.id)):
			validation_errors.append("Powielony identyfikator mieszkańca %s w szablonach wydarzeń." % definition.id)
		else:
			survivor_ids.append(str(definition.id))

func _validate_settlement_events() -> void:
	var required_events := [
		"survivors_on_horizon",
		"drifting_supply_crates",
		"torn_mooring",
		"shared_meal",
		"trader_at_dawn",
	]
	for event_id in required_events:
		if not settlement_events.has(event_id):
			validation_errors.append("Brak definicji wydarzenia osady %s." % event_id)

	var configured_weight_tags: Array[String] = []
	var balance_contract_valid := false
	if settlement_event_balance == null or not settlement_event_balance.has_method("validation_errors"):
		validation_errors.append("Brak poprawnej definicji balansu wydarzeń osady.")
	else:
		var balance_errors: PackedStringArray = settlement_event_balance.validation_errors()
		for balance_error in balance_errors:
			validation_errors.append("Balans wydarzeń osady: %s." % balance_error)
		balance_contract_valid = balance_errors.is_empty()
		if balance_contract_valid and settlement_event_balance.has_method("configured_trigger_tags"):
			configured_weight_tags.assign(settlement_event_balance.configured_trigger_tags())
	var allowed_impact_tags := [
		"food_relief",
		"material_relief",
		"hope_relief",
		"food_cost",
		"workforce_relief",
		"population_gain",
		"food_demand",
		"hope_change",
		"material_cost",
		"integrity_risk",
		"integrity_relief",
		"medicine_relief",
		"resource_exchange",
	]
	var allowed_exclusive_tags := [
		"food_critical",
		"hope_critical",
		"no_shelter",
		"integrity_critical",
		"workforce_critical",
		"recent_death",
		"storm_today",
	]
	var used_weight_tags: Array[String] = []
	var consumer_impacts_by_trigger: Dictionary = {}
	var has_forced_workforce_consumer := false
	var event_ids_by_history_key: Dictionary = {}
	for event_id in settlement_events.keys():
		var definition = settlement_events[event_id]
		if definition == null or definition.get_script() != SettlementEventDefinitionScript:
			validation_errors.append("Wydarzenie osady %s ma niewłaściwy typ danych." % event_id)
			continue
		var history_key := str(definition.history_key)
		if history_key.is_empty():
			validation_errors.append("Wydarzenie %s nie ma stabilnego history_key." % event_id)
		elif event_ids_by_history_key.has(history_key):
			validation_errors.append("Wydarzenia %s i %s współdzielą history_key %s." % [event_ids_by_history_key[history_key], event_id, history_key])
		else:
			event_ids_by_history_key[history_key] = str(event_id)
		var fallback = definition.find_choice(str(definition.fallback_choice_id))
		if fallback == null:
			validation_errors.append("Wydarzenie %s wskazuje nieistniejącą decyzję awaryjną %s." % [event_id, definition.fallback_choice_id])
		else:
			if fallback.has_resource_cost():
				validation_errors.append("Decyzja awaryjna %s/%s ma ujemny koszt zwykłego zasobu." % [event_id, fallback.id])
			if not fallback.survivor_definition_ids.is_empty():
				validation_errors.append("Decyzja awaryjna %s/%s dodaje mieszkańca." % [event_id, fallback.id])
		if definition == null or not definition.has_method("is_valid") or not definition.is_valid():
			validation_errors.append("Wydarzenie osady %s ma niepoprawne dane." % event_id)
			continue
		for resource_id in definition.required_resource_minimums.keys():
			if not ResourceIdsScript.all().has(str(resource_id)):
				validation_errors.append("Wydarzenie %s wymaga nieznanego zasobu %s." % [event_id, resource_id])
			elif int(definition.required_resource_minimums[resource_id]) < 0:
				validation_errors.append("Wydarzenie %s ma ujemne minimum zasobu %s." % [event_id, resource_id])
		var effective_trigger_tags: Array[String] = definition.effective_trigger_tags()
		for trigger_tag in effective_trigger_tags:
			if not configured_weight_tags.has(str(trigger_tag)):
				validation_errors.append("Wydarzenie %s używa trigger tagu bez reguły balansu: %s." % [event_id, trigger_tag])
			elif not used_weight_tags.has(str(trigger_tag)):
				used_weight_tags.append(str(trigger_tag))
			var consumer_impacts: Array = consumer_impacts_by_trigger.get(str(trigger_tag), [])
			for impact_tag in definition.impact_tags:
				if not consumer_impacts.has(str(impact_tag)):
					consumer_impacts.append(str(impact_tag))
			consumer_impacts_by_trigger[str(trigger_tag)] = consumer_impacts
		for impact_tag in definition.impact_tags:
			if not allowed_impact_tags.has(str(impact_tag)):
				validation_errors.append("Wydarzenie %s ma nieznany impact tag %s." % [event_id, impact_tag])
		for exclusive_tag in definition.exclusive_tags:
			if not allowed_exclusive_tags.has(str(exclusive_tag)):
				validation_errors.append("Wydarzenie %s ma nieznany exclusive tag %s." % [event_id, exclusive_tag])
		if definition.trigger_tags.is_empty():
			validation_errors.append("Wydarzenie %s nie ma jawnego trigger tagu." % event_id)
		if definition.impact_tags.is_empty():
			validation_errors.append("Wydarzenie %s nie ma jawnego impact tagu." % event_id)
		if str(definition.tone) == "hardship" and float(definition.pressure_cost) <= 0.0:
			validation_errors.append("Trudne wydarzenie %s musi zużywać dodatni budżet presji." % event_id)
		var has_cost_free_choice := false
		var adds_authored_survivor := false
		var choice_impact_union: Array[String] = []
		for choice in definition.choices:
			if choice == null or choice.get_script() != SettlementEventChoiceDefinitionScript:
				validation_errors.append("Wydarzenie %s zawiera opcję niewłaściwego typu." % event_id)
				continue
			if not choice.has_resource_cost():
				has_cost_free_choice = true
			for impact_tag in choice.impact_tags:
				var resolved_impact_tag := str(impact_tag)
				if not allowed_impact_tags.has(resolved_impact_tag):
					validation_errors.append("Opcja %s/%s ma nieznany impact tag %s." % [event_id, choice.id, resolved_impact_tag])
				elif not definition.impact_tags.has(resolved_impact_tag):
					validation_errors.append("Opcja %s/%s ma impact tag %s nieobecny w kontrakcie wydarzenia." % [event_id, choice.id, resolved_impact_tag])
				elif not choice_impact_union.has(resolved_impact_tag):
					choice_impact_union.append(resolved_impact_tag)
			for resource_id in choice.resource_deltas.keys():
				if not ResourceIdsScript.all().has(str(resource_id)):
					validation_errors.append("Opcja %s/%s używa nieznanego zasobu %s." % [event_id, choice.id, resource_id])
			_validate_settlement_choice_impact_semantics(event_id, choice)
			var choice_survivor_ids: Array[String] = []
			for survivor_id in choice.survivor_definition_ids:
				adds_authored_survivor = true
				if choice_survivor_ids.has(str(survivor_id)):
					validation_errors.append("Opcja %s/%s powtarza szablon mieszkańca %s." % [event_id, choice.id, survivor_id])
					continue
				choice_survivor_ids.append(str(survivor_id))
				if not survivor_templates.has(str(survivor_id)):
					validation_errors.append("Opcja %s/%s wskazuje brakujący szablon mieszkańca %s." % [event_id, choice.id, survivor_id])
		for impact_tag in definition.impact_tags:
			if not choice_impact_union.has(str(impact_tag)):
				validation_errors.append("Wydarzenie %s deklaruje impact tag %s, którego nie realizuje żadna opcja." % [event_id, impact_tag])
		if not has_cost_free_choice:
			validation_errors.append("Wydarzenie %s nie ma awaryjnej opcji bez kosztu." % event_id)
		if adds_authored_survivor and not bool(definition.once_per_campaign):
			validation_errors.append("Wydarzenie %s dodaje autorskich mieszkańców, ale nie jest jednorazowe." % event_id)
		if adds_authored_survivor and str(definition.recovery_role) == "workforce":
			has_forced_workforce_consumer = true
	for configured_tag in configured_weight_tags:
		if not used_weight_tags.has(configured_tag):
			validation_errors.append("Reguła balansu wydarzeń %s nie ma żadnego konsumenta w aktywnej puli." % configured_tag)
		var rule = settlement_event_balance.find_trigger_rule(configured_tag)
		if rule == null:
			continue
		var consumer_impacts: Array = consumer_impacts_by_trigger.get(configured_tag, [])
		var has_matching_impact := false
		for raw_impact_tag in rule.required_available_impact_tags:
			var impact_tag := str(raw_impact_tag)
			if not allowed_impact_tags.has(impact_tag):
				validation_errors.append("Reguła balansu %s wymaga nieznanego impact tagu %s." % [configured_tag, impact_tag])
			elif consumer_impacts.has(impact_tag):
				has_matching_impact = true
		if not has_matching_impact:
			validation_errors.append("Reguła balansu %s nie ma karty realizującej wymagany dostępny skutek." % configured_tag)
	if balance_contract_valid and bool(settlement_event_balance.force_workforce_recovery) and not has_forced_workforce_consumer:
		validation_errors.append("Gwarancja krytycznej załogi nie ma jednorazowej karty workforce dodającej mieszkańców.")


func _validate_settlement_choice_impact_semantics(event_id: String, choice) -> void:
	if choice == null or choice.get_script() != SettlementEventChoiceDefinitionScript:
		return
	var tags: Array[String] = []
	tags.assign(choice.impact_tags)
	var food_delta := int(choice.resource_deltas.get(ResourceIdsScript.FOOD, 0))
	var planks_delta := int(choice.resource_deltas.get(ResourceIdsScript.PLANKS, 0))
	var scrap_delta := int(choice.resource_deltas.get(ResourceIdsScript.SCRAP, 0))
	var hope_delta := int(choice.resource_deltas.get(ResourceIdsScript.HOPE, 0))
	var integrity_delta := int(choice.resource_deltas.get(ResourceIdsScript.PLATFORM_INTEGRITY, 0))
	var medicine_delta := int(choice.resource_deltas.get(ResourceIdsScript.MEDS_CHEMICALS, 0))
	var adds_survivors: bool = not choice.survivor_definition_ids.is_empty()
	var has_exchange_gain := false
	var has_exchange_cost := false
	for raw_resource_id in choice.resource_deltas.keys():
		var resource_id := str(raw_resource_id)
		if resource_id in [ResourceIdsScript.HOPE, ResourceIdsScript.PLATFORM_INTEGRITY]:
			continue
		var delta := int(choice.resource_deltas[raw_resource_id])
		has_exchange_gain = has_exchange_gain or delta > 0
		has_exchange_cost = has_exchange_cost or delta < 0

	_validate_choice_tag_contract(event_id, choice, tags, "food_cost", food_delta < 0, "ujemny koszt jedzenia")
	_validate_choice_tag_contract(event_id, choice, tags, "material_cost", planks_delta < 0 or scrap_delta < 0, "ujemny koszt desek lub złomu")
	_validate_choice_tag_contract(event_id, choice, tags, "food_relief", food_delta > 0, "dodatni przyrost jedzenia")
	_validate_choice_tag_contract(event_id, choice, tags, "material_relief", planks_delta + scrap_delta > 0, "dodatni bilans desek i złomu")
	_validate_choice_tag_contract(event_id, choice, tags, "medicine_relief", medicine_delta > 0, "dodatni przyrost leków")
	_validate_choice_tag_contract(event_id, choice, tags, "integrity_relief", integrity_delta > 0, "dodatni przyrost integralności")
	_validate_choice_tag_contract(event_id, choice, tags, "hope_relief", hope_delta > 0, "dodatni przyrost Nadziei")
	_validate_choice_tag_contract(event_id, choice, tags, "hope_change", hope_delta < 0, "ujemną zmianę Nadziei")
	_validate_choice_tag_contract(event_id, choice, tags, "integrity_risk", integrity_delta < 0, "ujemną zmianę integralności")
	_validate_choice_tag_contract(event_id, choice, tags, "workforce_relief", adds_survivors, "dodanie mieszkańców")
	_validate_choice_tag_contract(event_id, choice, tags, "population_gain", adds_survivors, "dodanie mieszkańców")
	_validate_choice_tag_contract(event_id, choice, tags, "food_demand", adds_survivors, "dodanie mieszkańców zwiększających racje")
	_validate_choice_tag_contract(event_id, choice, tags, "resource_exchange", has_exchange_gain and has_exchange_cost, "jednoczesny przychód i koszt zasobów")


func _validate_choice_tag_contract(
	event_id: String,
	choice,
	tags: Array[String],
	tag: String,
	condition: bool,
	meaning: String
) -> void:
	var has_tag := tags.has(tag)
	if condition and not has_tag:
		validation_errors.append("Opcja %s/%s musi deklarować impact tag %s: %s." % [event_id, choice.id, tag, meaning])
	elif has_tag and not condition:
		validation_errors.append("Opcja %s/%s deklaruje impact tag %s bez skutku: %s." % [event_id, choice.id, tag, meaning])

func _validate_missions() -> void:
	var required_missions := [
		"foundation_harbor",
		"old_signal",
		"leadership_crisis",
		"rescue_leon",
		"light_in_depths",
		"more_air",
		"return_network",
		"heavy_recovery",
	]
	for mission_id in required_missions:
		if not missions.has(mission_id):
			validation_errors.append("Brak definicji misji %s." % mission_id)

	var allowed_categories := ["main", "side", "urgent"]
	var allowed_unlock_kinds := ["always", "tutorial_complete", "building_built", "building_level", "heavy_recovery_available", "crisis_active"]
	var allowed_objective_kinds := MissionObjectiveDefinitionScript.SUPPORTED_KINDS
	for mission_id in missions.keys():
		var definition = missions[mission_id]
		if definition == null or not definition.has_method("is_valid") or not definition.is_valid():
			validation_errors.append("Misja %s ma niepoprawne dane." % mission_id)
			continue
		if not allowed_categories.has(str(definition.category)):
			validation_errors.append("Misja %s ma nieznaną kategorię %s." % [mission_id, definition.category])
		if not allowed_unlock_kinds.has(str(definition.unlock_kind)):
			validation_errors.append("Misja %s ma nieznany warunek odblokowania %s." % [mission_id, definition.unlock_kind])
		if bool(definition.repeatable) and str(definition.unlock_kind) != "crisis_active":
			validation_errors.append("Powtarzalna misja %s nie ma obsługiwanego warunku ponownej aktywacji." % mission_id)
		if str(definition.unlock_kind) in ["building_built", "building_level"] and not buildings.has(str(definition.unlock_target_id)):
			validation_errors.append("Misja %s odwołuje się do brakującego budynku %s." % [mission_id, definition.unlock_target_id])
		for prerequisite_id in definition.prerequisite_mission_ids:
			if not missions.has(str(prerequisite_id)):
				validation_errors.append("Misja %s wymaga brakującej misji %s." % [mission_id, prerequisite_id])
		for objective in definition.objectives:
			if objective == null:
				continue
			var kind := str(objective.kind)
			if not allowed_objective_kinds.has(kind):
				validation_errors.append("Misja %s ma nieznany rodzaj celu %s." % [mission_id, kind])
			elif kind == "building_built" and not buildings.has(str(objective.target_id)):
				validation_errors.append("Misja %s wskazuje brakujący budynek %s." % [mission_id, objective.target_id])
			elif kind == "gear_owned" and not diving_gear.has(str(objective.target_id)):
				validation_errors.append("Misja %s wskazuje brakujące wyposażenie %s." % [mission_id, objective.target_id])
			elif kind == "artifact_recovered" and (not items.has(str(objective.target_id)) or not items[str(objective.target_id)].tags.has("story_artifact")):
				validation_errors.append("Misja %s wskazuje brakujący element fabularny %s." % [mission_id, objective.target_id])
			elif kind == "resource_at_least" and not ResourceIdsScript.all().has(str(objective.target_id)):
				validation_errors.append("Misja %s wskazuje nieznany zasób %s." % [mission_id, objective.target_id])

func _validate_cost(cost: Dictionary, context: String) -> void:
	for resource_id in cost.keys():
		if int(cost[resource_id]) < 0:
			validation_errors.append("Ujemny koszt %s w: %s." % [resource_id, context])
		if not ResourceIdsScript.all().has(str(resource_id)):
			validation_errors.append("Nieznany zasób %s w: %s." % [resource_id, context])
