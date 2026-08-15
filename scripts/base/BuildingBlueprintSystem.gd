class_name BuildingBlueprintSystem
extends RefCounted

# System zarządzający szkicami budynków i ich walidacją
# Zgodny z ARD-0003 - Resource dla danych, system dla regul

const BuildingDefinitionScript := preload("res://scripts/definitions/BuildingDefinition.gd")
const BuildingStateScript := preload("res://scripts/data/BuildingState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const PlatformStateScript := preload("res://scripts/data/PlatformState.gd")

# Stan walidacji szkicu
enum BlueprintValidationStatus {
	VALID,
	INVALID_DEFINITION,
	INVALID_LOCATION,
	INVALID_RESOURCES,
	INVALID_PRECONDITIONS,
	INCOMPLETE_PLANNING,
}

# Wynik walidacji szkicu budynku
class BlueprintValidationResult:
	var status: BlueprintValidationStatus = BlueprintValidationStatus.VALID
	var message: String = ""
	var errors: Array[String] = []
	var warnings: Array[String] = []

func _init() -> void:
	pass

# Sprawdza czy szkic budynku jest poprawny
func validate_blueprint(
	state,
	building_definition: BuildingDefinitionScript,
	location: Vector2,
	orientation: int = 0,
	placement_type: String = "normal"
) -> BlueprintValidationResult:
	var result := BlueprintValidationResult.new()

	# Sprawdzenie definicji
	if building_definition == null:
		result.status = BlueprintValidationStatus.INVALID_DEFINITION
		result.message = "Brak definicji budynku"
		result.errors.append("Brak definicji budynku")
		return result

	# Walidacja lokalizacji
	if not _is_valid_location(state, location):
		result.status = BlueprintValidationStatus.INVALID_LOCATION
		result.message = "Nieprawidłowa lokalizacja"
		result.errors.append("Lokalizacja nie jest prawidłowa")
		return result

	# Walidacja zasobów
	if not _has_sufficient_resources(state, building_definition):
		result.status = BlueprintValidationStatus.INVALID_RESOURCES
		result.message = "Niewystarczające zasoby"
		result.errors.append("Brak wystarczających zasobów")
		return result

	# Walidacja warunków wstępnch
	if not _meets_preconditions(state, building_definition):
		result.status = BlueprintValidationStatus.INVALID_PRECONDITIONS
		result.message = "Warunki wstępne nie są spełnione"
		result.errors.append("Nie spełniono warunków wstępnego")
		return result

	# Walidacja planowania
	if not _is_complete_planning(state, building_definition):
		result.status = BlueprintValidationStatus.INCOMPLETE_PLANNING
		result.message = "Planowanie jest niekompletne"
		result.errors.append("Brak kompletnej konfiguracji")
		return result

	result.status = BlueprintValidationStatus.VALID
	result.message = "Szkic budynku jest poprawny"

	return result

# Sprawdza czy lokalizacja jest poprawna dla budynku
func _is_valid_location(state, location: Vector2) -> bool:
	# Weryfikacja granic mapy
	if state == null or state.platform == null:
		return false

	# Przykład walidacji lokalizacji (może być rozszerzona)
	return true

# Sprawdza czy są wystarczające zasoby do budowy
func _has_sufficient_resources(state, building_definition: BuildingDefinitionScript) -> bool:
	if state == null or state.resources == null or building_definition == null:
		return false

	var required_resources := building_definition.get_build_cost()
	for resource_id in required_resources.keys():
		var required_amount := required_resources[resource_id]
		var available_amount := state.resources.get_resource_amount(resource_id)
		if available_amount < required_amount:
			return false

	return true

# Sprawdza czy spełnione są warunki wstępne
func _meets_preconditions(state, building_definition: BuildingDefinitionScript) -> bool:
	if state == null or building_definition == null:
		return false

	# Sprawdzenie warunków wstępnego (może być rozszerzona)
	return true

# Sprawdza czy planowanie jest kompletne
func _is_complete_planning(state, building_definition: BuildingDefinitionScript) -> bool:
	if state == null or building_definition == null:
		return false

	# Sprawdzenie kompletnej konfiguracji (może być rozszerzona)
	return true

# Tworzy nowy stan budynku z szkicu
func create_building_from_blueprint(
	state,
	building_definition: BuildingDefinitionScript,
	location: Vector2,
	orientation: int = 0
) -> BuildingStateScript:
	if state == null or building_definition == null:
		return null

	var building_state := BuildingStateScript.new()
	building_state.id = "%s_%d" % [building_definition.id, Time.get_unix_time_from_system()]
	building_state.definition_id = building_definition.id
	building_state.location = location
	building_state.orientation = orientation
	building_state.level = 1
	building_state.is_constructed = false
	building_state.construction_progress = 0.0

	# Ustawienie początkowych wartości z definicji
	if building_definition.has_method("get_initial_stats"):
		var stats := building_definition.get_initial_stats()
		if stats != null:
			building_state.stats = stats.duplicate(true)

	return building_state

# Zapisuje szkic budynku do stanu kampanii
func save_blueprint_to_campaign(
	state,
	building_state: BuildingStateScript
) -> bool:
	if state == null or building_state == null:
		return false

	# Dodanie budynku do listy budynków w stanie kampanii
	state.buildings.append(building_state)

	# Aktualizacja zasobów (odejmowanie kosztów)
	var required_resources := building_state.get_build_cost()
	for resource_id in required_resources.keys():
		var cost := required_resources[resource_id]
		if state.resources != null:
			state.resources.adjust_resource(resource_id, -cost)

	return true

# Pobiera wszystkie dostępne szkice budynków dla gracza
func get_available_blueprints(state) -> Array[BuildingDefinitionScript]:
	if state == null:
		return []

	var blueprints := []
	# W przyszłości tu będzie logika dostępnego szkicu

	return blueprints
