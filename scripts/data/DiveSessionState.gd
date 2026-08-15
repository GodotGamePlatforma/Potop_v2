class_name DiveSessionState
extends Resource

const TutorialStateScript := preload("res://scripts/data/TutorialState.gd")
const DiveTutorialOutcomeScript := preload("res://scripts/data/DiveTutorialOutcome.gd")

@export var setup: Resource
@export var oxygen_left: float = 0.0
@export var oxygen_capacity: float = 0.0
@export var health: int = 100
@export var health_capacity: int = 100
@export var starting_health: int = 100
@export var suit_condition: int = 100
@export var cold_exposure: float = 0.0
@export var noise_level: float = 0.0
@export var last_noise_position: Vector2 = Vector2.ZERO
@export var light_enabled: bool = false
@export var repair_kit_charges: int = 0
@export var repair_kit_uses: int = 0
@export var leak_damage_progress: float = 0.0
@export var cold_damage_progress: float = 0.0
@export var noise_events: Array[String] = []
@export var risk_events: Array[String] = []
@export var disease_exposures: Array[DiseaseExposureState] = []
@export var injuries: Array[String] = []
@export var carried_items: Dictionary = {}
@export var carried_item_order: Array[String] = []
@export var backpack_capacity: int = 6
@export var carry_capacity: float = 18.0
@export var item_weights: Dictionary = {}
@export var remaining_container_contents: Dictionary = {}
@export var opened_containers: Array[String] = []
@export var collected_world_item_ids: Array[String] = []
@export var rescued_survivor_ids: Array[String] = []
@export var towed_survivor: Resource
@export var towed_rescue_encounter_id: String = ""
@export var towed_survivor_stabilized: bool = false
@export var placed_buoys: Array[String] = []
@export var opened_shortcuts: Array[String] = []
@export var activated_fixed_devices: Array[String] = []
@export var marked_heavy_objects: Array[String] = []
@export var recovered_backpacks: Dictionary = {}
@export var recovered_gear_ids: Array[String] = []
@export var dropped_loot_updates: Dictionary = {}
@export var dropped_loot_sequence: int = 0
@export var buoy_charges: int = 0
@export var elapsed_time: float = 0.0
@export var tutorial_mode: bool = false
@export var selected_combat_tool: String = ""
@export var harpoon_ammo: int = 0
@export var combat_cooldown_left: float = 0.0
var tutorial_opened_mandatory_orders: Array[int] = []
var tutorial_baseline_step: int = -1
var tutorial_state: TutorialState
var tutorial_event_ids: Array[String] = []

func begin(expedition_setup) -> void:
	setup = expedition_setup
	oxygen_capacity = maxf(float(expedition_setup.oxygen_capacity), 1.0)
	oxygen_left = oxygen_capacity
	health_capacity = maxi(int(expedition_setup.diver_health_capacity), 1)
	starting_health = clampi(int(expedition_setup.diver_health), 0, health_capacity)
	backpack_capacity = maxi(int(expedition_setup.backpack_capacity), 1)
	carry_capacity = maxf(float(expedition_setup.diver_carry_capacity), 0.01)
	item_weights = expedition_setup.item_weights.duplicate(true)
	tutorial_mode = bool(expedition_setup.tutorial_mode)
	tutorial_baseline_step = int(expedition_setup.tutorial_baseline_step) if tutorial_mode else -1
	reset_attempt()

func reset_attempt() -> void:
	oxygen_left = oxygen_capacity
	health = starting_health
	suit_condition = 100
	cold_exposure = 0.0
	noise_level = 0.0
	last_noise_position = Vector2.ZERO
	light_enabled = setup != null and not str(setup.equipped_gear.get("light", "")).is_empty()
	repair_kit_charges = (2 if setup != null and bool(setup.technician_assigned) else 1) if has_tool("repair_kit") else 0
	buoy_charges = maxi(int(setup.buoy_charges), 0) if setup != null else 0
	repair_kit_uses = 0
	leak_damage_progress = 0.0
	cold_damage_progress = 0.0
	noise_events.clear()
	risk_events.clear()
	disease_exposures.clear()
	injuries.clear()
	carried_items.clear()
	carried_item_order.clear()
	remaining_container_contents.clear()
	opened_containers.clear()
	collected_world_item_ids.clear()
	rescued_survivor_ids.clear()
	towed_survivor = null
	towed_rescue_encounter_id = ""
	towed_survivor_stabilized = false
	placed_buoys.clear()
	opened_shortcuts.clear()
	activated_fixed_devices.clear()
	marked_heavy_objects.clear()
	recovered_backpacks.clear()
	recovered_gear_ids.clear()
	dropped_loot_updates.clear()
	dropped_loot_sequence = 0
	elapsed_time = 0.0
	selected_combat_tool = "knife" if has_tool("knife") else "harpoon_pistol" if setup != null and str(setup.equipped_gear.get("weapon", "")) == "harpoon_pistol" else ""
	harpoon_ammo = maxi(int(setup.weapon_ammunition), 0) if setup != null and str(setup.equipped_gear.get("weapon", "")) == "harpoon_pistol" else 0
	combat_cooldown_left = 0.0
	tutorial_opened_mandatory_orders.clear()
	_reset_tutorial_attempt()

func record_tutorial_container_opened(mandatory_order: int) -> void:
	if mandatory_order >= 0 and not tutorial_opened_mandatory_orders.has(mandatory_order):
		tutorial_opened_mandatory_orders.append(mandatory_order)


func record_tutorial_event(director, event_id: String) -> bool:
	if not tutorial_mode or tutorial_state == null or director == null:
		return false
	if not director.handle_tutorial_event(tutorial_state, event_id):
		return false
	tutorial_event_ids.append(event_id)
	return true


func current_tutorial_step() -> int:
	return int(tutorial_state.step) if tutorial_state != null else -1


func is_tutorial_active() -> bool:
	return tutorial_state != null and tutorial_state.is_active()


func build_tutorial_outcome() -> DiveTutorialOutcome:
	if not tutorial_mode or tutorial_state == null:
		return null
	var outcome := DiveTutorialOutcomeScript.new()
	outcome.baseline_step = tutorial_baseline_step
	outcome.final_step = int(tutorial_state.step)
	outcome.event_ids.assign(tutorial_event_ids)
	return outcome


func _reset_tutorial_attempt() -> void:
	tutorial_event_ids.clear()
	if not tutorial_mode:
		tutorial_state = null
		return
	tutorial_state = TutorialStateScript.new()
	tutorial_state.step = tutorial_baseline_step

func add_item(resource_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	if not carried_items.has(resource_id):
		if carried_item_order.size() >= backpack_capacity:
			return 0
	var accepted := max_addable_amount(resource_id, amount)
	if accepted <= 0:
		return 0
	if not carried_items.has(resource_id):
		carried_item_order.append(resource_id)
	carried_items[resource_id] = int(carried_items.get(resource_id, 0)) + accepted
	return accepted

func remove_item(resource_id: String, amount: int) -> int:
	if amount <= 0 or not carried_items.has(resource_id):
		return 0
	var removed := mini(int(carried_items[resource_id]), amount)
	var remaining := int(carried_items[resource_id]) - removed
	if remaining <= 0:
		carried_items.erase(resource_id)
		carried_item_order.erase(resource_id)
	else:
		carried_items[resource_id] = remaining
	return removed

func next_dropped_loot_id() -> String:
	dropped_loot_sequence += 1
	var expedition_day := maxi(int(setup.day), 1) if setup != null else 1
	var diver_id := str(setup.diver_id).strip_edges() if setup != null else "diver"
	if diver_id.is_empty():
		diver_id = "diver"
	diver_id = diver_id.to_lower().replace(" ", "_").replace(":", "_").replace("/", "_").replace("\\", "_")
	return "dropped_loot_%d_%s_%03d" % [expedition_day, diver_id, dropped_loot_sequence]

func max_addable_amount(resource_id: String, requested_amount: int) -> int:
	if requested_amount <= 0:
		return 0
	if not carried_items.has(resource_id) and carried_item_order.size() >= backpack_capacity:
		return 0
	var unit_weight := get_unit_weight(resource_id)
	var by_weight := int(floor((remaining_carry_capacity() + 0.0001) / unit_weight))
	return mini(requested_amount, maxi(by_weight, 0))

func slots_used() -> int:
	return carried_item_order.size()

func get_unit_weight(resource_id: String) -> float:
	return maxf(float(item_weights.get(resource_id, 1.0)), 0.01)

func get_carried_weight() -> float:
	var total := 0.0
	for resource_id in carried_items.keys():
		total += float(carried_items[resource_id]) * get_unit_weight(str(resource_id))
	return total

func remaining_carry_capacity() -> float:
	return maxf(carry_capacity - get_carried_weight(), 0.0)

func carry_ratio() -> float:
	return clampf(get_carried_weight() / carry_capacity, 0.0, 1.0) if carry_capacity > 0.0 else 1.0

func oxygen_ratio() -> float:
	return oxygen_left / oxygen_capacity if oxygen_capacity > 0.0 else 0.0

func health_ratio() -> float:
	return clampf(float(health) / float(health_capacity), 0.0, 1.0) if health_capacity > 0 else 0.0

func apply_damage(amount: int) -> int:
	var previous_health := health
	health = maxi(health - maxi(amount, 0), 0)
	return previous_health - health

func has_tool(tool_id: String) -> bool:
	return setup != null and setup.selected_gear.has(tool_id)

func record_noise_event(action_id: String) -> void:
	if not action_id.is_empty() and not noise_events.has(action_id):
		noise_events.append(action_id)

func record_risk_event(event_id: String) -> void:
	if not event_id.is_empty() and not risk_events.has(event_id):
		risk_events.append(event_id)


func add_disease_exposure(exposure: DiseaseExposureState) -> bool:
	if exposure == null or not exposure.is_valid():
		return false
	for existing in disease_exposures:
		if (
			existing != null
			and existing.disease_id == exposure.disease_id
			and existing.target_survivor_id == exposure.target_survivor_id
			and existing.source_kind == exposure.source_kind
			and existing.source_id == exposure.source_id
			and existing.acquired_day == exposure.acquired_day
		):
			return true
	var detached := exposure.detached_copy() as DiseaseExposureState
	if detached == null or not detached.is_valid():
		return false
	disease_exposures.append(detached)
	return true

func add_injury(injury_id: String) -> void:
	if not injury_id.is_empty() and not injuries.has(injury_id):
		injuries.append(injury_id)
