class_name DiveResult
extends Resource

@export var diver_id: String = ""
@export var returned_alive: bool = true
@export var diver_dead: bool = false
@export var diver_injuries: Array[String] = []
@export var lost_gear: Array[String] = []
@export var collected_items: Dictionary = {}
@export var rescued_survivors: Array = []
@export var rescue_outcomes: Dictionary = {}
@export var discovered_sectors: Array[String] = []
@export var placed_buoys: Array[String] = []
@export var opened_shortcuts: Array[String] = []
@export var activated_fixed_devices: Array[String] = []
@export var opened_containers: Array[String] = []
@export var collected_world_item_ids: Array[String] = []
@export var remaining_container_contents: Dictionary = {}
@export var marked_heavy_objects: Array[String] = []
@export var recovered_backpacks: Dictionary = {}
@export var recovered_gear_ids: Array[String] = []
@export var dropped_loot_updates: Dictionary = {}
@export var story_flags_unlocked: Array[String] = []
@export var body_location_if_dead: String = ""
@export var backpack_location_if_lost: String = ""
@export var death_world_position: Vector2 = Vector2.ZERO
@export var lost_items: Dictionary = {}
@export var oxygen_remaining: float = 0.0
@export var health_remaining: int = -1
@export var suit_condition_remaining: int = 100
@export var cold_exposure: float = 0.0
@export var repair_kit_uses: int = 0
@export var experience_gained: int = 0
@export var dive_duration: float = 0.0
@export var noise_events: Array[String] = []
@export var risk_events: Array[String] = []
@export var disease_exposures: Array[DiseaseExposureState] = []
@export var tutorial_completed: bool = false
@export var emergency_extraction: bool = false
# Runtime-only transaction payload. The committed campaign stores only the
# validated effects and the durable tutorial_completed compatibility flag.
var tutorial_outcome: DiveTutorialOutcome

func add_item(resource_id: String, amount: int) -> void:
	collected_items[resource_id] = int(collected_items.get(resource_id, 0)) + amount


func add_disease_exposure(exposure: DiseaseExposureState) -> bool:
	if exposure == null or not exposure.is_valid():
		return false
	var detached := exposure.detached_copy() as DiseaseExposureState
	if detached == null or not detached.is_valid():
		return false
	disease_exposures.append(detached)
	return true


func validation_errors(expedition_setup = null) -> PackedStringArray:
	var errors := PackedStringArray()
	if expedition_setup == null:
		errors.append("Brak aktywnego setupu wyprawy dla wyniku nurkowania.")
	else:
		if diver_id.strip_edges().is_empty() or diver_id != str(expedition_setup.diver_id):
			errors.append("Wynik nurkowania nie odpowiada nurkowi z aktywnego setupu.")
	if returned_alive == diver_dead:
		errors.append("Wynik nurkowania musi wskazywać dokładnie jeden stan terminalny.")
	if diver_dead and health_remaining not in [-1, 0]:
		errors.append("Śmiertelny wynik nurkowania ma niepoprawne zdrowie końcowe.")
	if returned_alive and (health_remaining < -1 or health_remaining == 0):
		errors.append("Bezpieczny powrót ma niepoprawne zdrowie końcowe.")
	if (
		not is_finite(oxygen_remaining)
		or oxygen_remaining < 0.0
		or not is_finite(cold_exposure)
		or cold_exposure < 0.0
		or cold_exposure > 100.0
		or not is_finite(dive_duration)
		or dive_duration < 0.0
	):
		errors.append("Wynik nurkowania ma niepoprawne metryki tlenu, zimna lub czasu.")
	if suit_condition_remaining < 0 or suit_condition_remaining > 100 or repair_kit_uses < 0 or experience_gained < 0:
		errors.append("Wynik nurkowania ma niepoprawny stan sprzętu lub postęp.")
	if emergency_extraction and (not returned_alive or diver_dead):
		errors.append("Awaryjne wyciągnięcie ma niespójny stan terminalny.")

	var setup_tutorial_mode := expedition_setup != null and bool(expedition_setup.tutorial_mode)
	if tutorial_completed:
		if not setup_tutorial_mode or not returned_alive or diver_dead or emergency_extraction:
			errors.append("Zakończenie tutoriala nie odpowiada bezpiecznemu powrotowi z sesji tutorialowej.")
		if tutorial_outcome == null:
			errors.append("Zakończony tutorial nie zawiera typowanego rezultatu sesji.")
	elif tutorial_outcome != null:
		errors.append("Rezultat tutoriala występuje przy wyniku, który go nie zatwierdza.")
	if setup_tutorial_mode and returned_alive and not emergency_extraction and not tutorial_completed:
		errors.append("Bezpieczny powrót tutorialowy nie został oznaczony do zatwierdzenia.")
	if tutorial_outcome != null:
		errors.append_array(tutorial_outcome.validation_errors())
		if expedition_setup != null and tutorial_outcome.baseline_step != int(expedition_setup.tutorial_baseline_step):
			errors.append("Rezultat tutoriala nie odpowiada bazowemu krokowi setupu wyprawy.")
	return errors


func detached_copy() -> DiveResult:
	var copy := duplicate(true) as DiveResult
	if copy != null and tutorial_outcome != null:
		copy.tutorial_outcome = tutorial_outcome.detached_copy()
	return copy
