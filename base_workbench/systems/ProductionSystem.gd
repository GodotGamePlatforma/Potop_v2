class_name ProductionSystem
extends RefCounted

const CompetencySystemScript := preload("res://scripts/survivors/CompetencySystem.gd")
const ProfessionTalentSystemScript := preload("res://scripts/survivors/ProfessionTalentSystem.gd")

const DivingGearDefinitionScript := preload("res://scripts/definitions/DivingGearDefinition.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")
const WorkshopOrderStateScript := preload("res://scripts/data/WorkshopOrderState.gd")
const WorkshopRecipeDefinitionScript := preload("res://base_workbench/definitions/WorkshopRecipeDefinition.gd")
const WorkPaceSystemScript := preload("res://base_workbench/systems/WorkPaceSystem.gd")

const WORK_POINTS_PER_ORDER := 100
const R3_REGULATOR_ID := "r3_regulator"
const COMMON_LINE_SPLITTER_ID := "common_line_splitter"
const TALENT_MATERIAL_RECOVERY := "mechanik_odzysk_materialu"

var _profession_talent_system = ProfessionTalentSystemScript.new()


func get_recipe(recipe_id: String):
	if recipe_id.is_empty():
		return null
	var path := "res://base_workbench/data/workshop_recipes/%s.tres" % recipe_id
	return ResourceLoader.load(path) if ResourceLoader.exists(path) else null


func get_craft_cost(recipe) -> Dictionary:
	return recipe.craft_cost.duplicate(true) if recipe != null else {}


func queue_recipe_blocker(state, workshop, recipe) -> String:
	if (
		state == null
	):
		return "Brak aktywnego stanu kampanii."
	if workshop == null:
		return "Brak Warsztatu."
	if recipe == null or recipe.get_script() != WorkshopRecipeDefinitionScript:
		return "Brak poprawnej definicji receptury."
	if state.resources == null:
		return "Brak stanu magazynu."
	if state.diving_equipment == null:
		return "Brak stanu wyposażenia nurkowego."
	if not str(recipe.prerequisite_story_flag).is_empty() and (state.story_flags == null or not state.story_flags.has_flag(str(recipe.prerequisite_story_flag))):
		return "To zlecenie nie zostało jeszcze odblokowane przez kampanię."
	if state.has_method("day_plan_edit_blocker"):
		var plan_blocker := str(state.day_plan_edit_blocker())
		if not plan_blocker.is_empty():
			return plan_blocker
	elif state.has_method("can_edit_day_plan") and not state.can_edit_day_plan():
		return "Plan dnia jest już zablokowany."
	if str(workshop.definition_id) != "workshop" or str(workshop.id).is_empty():
		return "Produkcję można zaplanować wyłącznie w poprawnym Warsztacie."
	if not workshop.is_active():
		return "Warsztat musi być ukończony i sprawny."
	if not _has_capable_worker(state, workshop):
		return "Przydziel do Warsztatu co najmniej jedną osobę zdolną do pracy."
	if int(state.day) < 1:
		return "Produkcję można zaplanować dopiero podczas aktywnego dnia kampanii."
	if workshop.next_production_order_sequence < 1:
		return "Numeracja kolejki Warsztatu jest niepoprawna."
	var validation_errors: PackedStringArray = workshop.production_order_validation_errors(ResourceIdsScript.all())
	if not validation_errors.is_empty():
		return "Kolejka Warsztatu ma niepoprawny stan: %s" % "; ".join(validation_errors)
	if int(workshop.level) < int(recipe.required_workshop_level):
		return "Receptura wymaga Warsztatu na poziomie %d." % int(recipe.required_workshop_level)
	if workshop.queued_production_orders.size() >= _queue_capacity(workshop.level):
		return "Kolejka Warsztatu jest pełna."
	if not _recipe_can_be_snapshotted(recipe):
		return "Receptura ma niepoprawne dane i nie może zostać bezpiecznie zapisana."
	if _has_queued_recipe_or_output(workshop, str(recipe.id), str(recipe.output_gear_id)):
		return "Ten przedmiot jest już w kolejce Warsztatu."
	if not str(recipe.output_gear_id).is_empty() and state.diving_equipment.owns(str(recipe.output_gear_id)):
		return "Ten przedmiot został już wyprodukowany."
	if str(recipe.output_campaign_id) == R3_REGULATOR_ID and (state.story_flags.r3_regulator_ready or state.story_flags.r3_generator_active):
		return "Regulator R-3 został już wykonany."
	if str(recipe.output_campaign_id) == COMMON_LINE_SPLITTER_ID and (state.story_flags.common_line_splitter_ready or state.story_flags.common_line_splitter_installed):
		return "Rozdzielacz Wspólnej Linii został już wykonany."
	if not str(recipe.prerequisite_gear_id).is_empty() and not state.diving_equipment.owns(str(recipe.prerequisite_gear_id)):
		var prerequisite = _get_gear_definition(str(recipe.prerequisite_gear_id))
		return "Najpierw zdobądź lub wyprodukuj: %s." % (str(prerequisite.display_name) if prerequisite != null else str(recipe.prerequisite_gear_id))
	var shortfalls := _cost_shortfalls(state, _snapshot_cost(recipe.craft_cost))
	return "Brak materiałów — %s." % "; ".join(shortfalls) if not shortfalls.is_empty() else ""


func can_queue_recipe(state, workshop, recipe) -> bool:
	return queue_recipe_blocker(state, workshop, recipe).is_empty()


func queue_recipe(state, workshop, recipe) -> bool:
	if not can_queue_recipe(state, workshop, recipe):
		return false

	var reserved_cost := _snapshot_cost(recipe.craft_cost)
	var sequence := int(workshop.next_production_order_sequence)
	var order = WorkshopOrderStateScript.new()
	if str(recipe.output_campaign_id).is_empty():
		order.setup("workshop_order:%s:%d" % [str(workshop.id), sequence], str(recipe.id), str(recipe.output_gear_id), str(recipe.display_name), reserved_cost, int(state.day))
		order.required_work_points = maxi(int(recipe.required_work_points), 1)
	else:
		order.setup_campaign("workshop_order:%s:%d" % [str(workshop.id), sequence], str(recipe.id), str(recipe.output_campaign_id), str(recipe.display_name), reserved_cost, int(state.day), int(recipe.required_work_points))
	if not order.is_valid(str(workshop.id), ResourceIdsScript.all()):
		return false
	if not _spend_cost(state, reserved_cost):
		return false

	workshop.queued_production_orders.append(order)
	workshop.next_production_order_sequence = sequence + 1
	return true


func resolve_workshop_queue(
	state,
	report,
	pace: String = WorkPaceSystemScript.WORK_PACE_NORMAL,
	workforce_ready_override = null,
	workforce_talent_state = null
) -> Dictionary:
	var plan := analyze_workshop_queue(state, pace, workforce_ready_override, workforce_talent_state)
	var result := {
		"worked": false,
		"completed": 0,
		"points_applied": 0,
		"points_budget": int(plan.get("points_budget", 0)),
		"points_remaining": int(plan.get("points_budget", 0)),
		"blocked": false,
		"canceled": 0,
		"material_recovery_scrap_refund": 0,
	}
	var workshop = plan.get("workshop")
	if workshop == null:
		if bool(plan.get("blocked", false)):
			_add_warning(report, str(plan.get("blocked_message", "Warsztat nie może rozliczyć kolejki.")))
			result.blocked = true
		return result

	for action in plan.get("actions", []):
		if workshop.queued_production_orders.is_empty():
			_add_warning(report, "Warsztat przerwał rozliczenie: kolejka zmieniła się po przygotowaniu planu pracy.")
			result.blocked = true
			break
		var order = workshop.queued_production_orders[0]
		if order != action.get("order"):
			_add_warning(report, "Warsztat przerwał rozliczenie: pierwszy wpis kolejki nie odpowiada przygotowanemu planowi pracy.")
			result.blocked = true
			break
		match str(action.get("kind", "")):
			"cancel":
				_refund_cost(state, order.reserved_cost)
				workshop.queued_production_orders.remove_at(0)
				result.canceled = int(result.canceled) + 1
				_add_warning(
					report,
					"Anulowano produkcję %s po odzyskaniu tego wyposażenia; dokładnie zarezerwowane materiały zwrócono."
					% str(order.output_display_name)
				)
			"progress":
				var progress_points := int(action.get("points", 0))
				order.work_progress = int(action.get("progress", order.work_progress))
				result.points_applied = int(result.points_applied) + progress_points
				result.worked = progress_points > 0 or bool(result.worked)
				if report != null:
					report.add_entry(
						"Warsztat wykonał %d/%d punktów pracy przy: %s."
						% [int(order.work_progress), int(order.required_work_points), str(order.output_display_name)]
					)
			"complete":
				var completion_ok := _complete_order_output(state, order)
				if not completion_ok:
					_add_warning(
						report,
						"Warsztat zachował zlecenie %s: nie udało się dodać docelowego wyposażenia."
						% str(order.instance_id)
					)
					result.blocked = true
					break
				var completion_points := int(action.get("points", 0))
				var material_recovery_refund := int(action.get("material_recovery_scrap_refund", 0))
				if material_recovery_refund > 0:
					state.resources.add_amount(ResourceIdsScript.SCRAP, material_recovery_refund)
					result.material_recovery_scrap_refund = (
						int(result.material_recovery_scrap_refund) + material_recovery_refund
					)
				result.points_applied = int(result.points_applied) + completion_points
				result.worked = completion_points > 0 or bool(result.worked)
				workshop.queued_production_orders.remove_at(0)
				result.completed = int(result.completed) + 1
				if report != null:
					report.add_entry("Warsztat wyprodukował: %s." % str(order.output_display_name))
					if material_recovery_refund > 0:
						report.add_entry(
							"Odzysk materiału zwrócił %d złomu po ukończeniu zlecenia."
							% material_recovery_refund
						)
			_:
				_add_warning(report, "Warsztat przerwał rozliczenie: plan pracy zawiera nieznaną operację.")
				result.blocked = true
				break
	result.points_remaining = maxi(int(result.points_budget) - int(result.points_applied), 0)
	if bool(plan.get("blocked", false)) and int(result.points_applied) == int(plan.get("points_applied", 0)):
		_add_warning(report, str(plan.get("blocked_message", "Warsztat zachował zlecenie bez zmian.")))
		result.blocked = true
	return result


## Builds the exact FIFO work plan without changing resources, equipment,
## progress or the queue. Both gameplay resolution and UI forecasts consume
## this result so zero-point cancellations/errors cannot masquerade as work.
func analyze_workshop_queue(
	state,
	pace: String = WorkPaceSystemScript.WORK_PACE_NORMAL,
	workforce_ready_override = null,
	workforce_talent_state = null
) -> Dictionary:
	var result := {
		"worked": false,
		"completed": 0,
		"canceled": 0,
		"points_applied": 0,
		"points_budget": 0,
		"points_remaining": 0,
		"blocked": false,
		"blocked_message": "",
		"next_progress": -1,
		"remaining_order_count": 0,
		"completed_names": [] as Array[String],
		"canceled_names": [] as Array[String],
		"refunded_cost": {},
		"material_recovery_available": false,
		"material_recovery_scrap_refund": 0,
		"material_recovery_order_id": "",
		"actions": [],
		"workshop": null,
	}
	if state == null:
		return result
	var workshop = state.find_building_by_definition("workshop")
	result.workshop = workshop
	if workshop == null or not workshop.is_active():
		return result
	var workforce_ready := (
		_has_capable_worker(state, workshop)
		if workforce_ready_override == null
		else bool(workforce_ready_override)
	)
	if not workforce_ready:
		return result
	var has_material_recovery := _workforce_has_talent(
		state,
		workshop,
		workforce_talent_state,
		TALENT_MATERIAL_RECOVERY
	)
	result.material_recovery_available = has_material_recovery
	var normalized_pace := WorkPaceSystemScript.normalize_pace(pace)
	result.points_budget = maxi(int(round(
		float(_production_slots(workshop.level) * WORK_POINTS_PER_ORDER)
		* WorkPaceSystemScript.output_multiplier(normalized_pace)
		* _production_competency_multiplier(state, workshop)
	)), 0)
	result.points_remaining = result.points_budget
	result.remaining_order_count = workshop.queued_production_orders.size()
	if workshop.queued_production_orders.is_empty():
		return result
	if state.resources == null or state.diving_equipment == null:
		result.blocked = true
		result.blocked_message = "Warsztat nie może rozliczyć kolejki: stan magazynu lub wyposażenia jest niepoprawny."
		return result

	var virtually_owned: Dictionary = {}
	for gear_id in state.diving_equipment.owned_gear_ids:
		virtually_owned[str(gear_id)] = true
	var points_remaining := int(result.points_budget)
	var material_recovery_committed := false
	var material_recovery_definition = _profession_talent_system.get_definition(TALENT_MATERIAL_RECOVERY)
	var material_recovery_parameters: Dictionary = (
		material_recovery_definition.parameters if material_recovery_definition != null else {}
	)
	var material_recovery_minimum_scrap := int(material_recovery_parameters.get("minimum_reserved_scrap", 0))
	var material_recovery_scrap_refund := int(material_recovery_parameters.get("scrap_refund", 0))
	var material_recovery_uses := int(material_recovery_parameters.get("uses_per_day", 0))
	for order in workshop.queued_production_orders:
		var order_error := _active_order_error(workshop, order)
		if not order_error.is_empty():
			result.blocked = true
			result.blocked_message = "Warsztat zachował zlecenie bez zmian: %s" % order_error
			break
		var output_gear_id := str(order.output_gear_id)
		if not output_gear_id.is_empty() and _get_gear_definition(output_gear_id) == null:
			result.blocked = true
			result.blocked_message = (
				"Warsztat zachował zlecenie %s: docelowe wyposażenie %s nie istnieje lub ma niepoprawny typ."
				% [str(order.instance_id), output_gear_id]
			)
			break
		if not output_gear_id.is_empty() and virtually_owned.has(output_gear_id):
			result.actions.append({"kind": "cancel", "order": order})
			result.canceled = int(result.canceled) + 1
			result.canceled_names.append(str(order.output_display_name))
			for resource_id in order.reserved_cost.keys():
				var normalized_resource_id := str(resource_id)
				result.refunded_cost[normalized_resource_id] = (
					int(result.refunded_cost.get(normalized_resource_id, 0))
					+ int(order.reserved_cost[resource_id])
				)
			continue
		if points_remaining <= 0:
			break

		var previous_progress := int(order.work_progress)
		var points_needed := int(order.required_work_points) - previous_progress
		var points_for_order := mini(points_remaining, points_needed)
		if points_for_order < points_needed:
			var progress := previous_progress + points_for_order
			result.actions.append({
				"kind": "progress",
				"order": order,
				"points": points_for_order,
				"progress": progress,
			})
			points_remaining -= points_for_order
			result.points_applied = int(result.points_applied) + points_for_order
			result.next_progress = progress
			break

		var material_recovery_refund := 0
		if (
			has_material_recovery
			and not material_recovery_committed
			and material_recovery_uses > 0
			and int(order.reserved_cost.get(ResourceIdsScript.SCRAP, 0))
				>= material_recovery_minimum_scrap
		):
			material_recovery_refund = material_recovery_scrap_refund
			material_recovery_committed = true
			result.material_recovery_scrap_refund = material_recovery_refund
			result.material_recovery_order_id = str(order.instance_id)
			result.refunded_cost[ResourceIdsScript.SCRAP] = (
				int(result.refunded_cost.get(ResourceIdsScript.SCRAP, 0))
				+ material_recovery_refund
			)
		result.actions.append({
			"kind": "complete",
			"order": order,
			"points": points_for_order,
			"material_recovery_scrap_refund": material_recovery_refund,
		})
		points_remaining -= points_for_order
		result.points_applied = int(result.points_applied) + points_for_order
		result.completed = int(result.completed) + 1
		result.completed_names.append(str(order.output_display_name))
		if not output_gear_id.is_empty():
			virtually_owned[output_gear_id] = true

	result.worked = int(result.points_applied) > 0
	result.points_remaining = points_remaining
	result.remaining_order_count = maxi(
		workshop.queued_production_orders.size()
		- int(result.canceled)
		- int(result.completed),
		0
	)
	return result


func _recipe_can_be_snapshotted(recipe) -> bool:
	if (
		recipe == null
		or recipe.get_script() != WorkshopRecipeDefinitionScript
		or str(recipe.id).is_empty()
		or (str(recipe.output_gear_id).is_empty() == str(recipe.output_campaign_id).is_empty())
		or str(recipe.display_name).strip_edges().is_empty()
		or typeof(recipe.craft_cost) != TYPE_DICTIONARY
	):
		return false
	if not str(recipe.output_gear_id).is_empty() and _get_gear_definition(str(recipe.output_gear_id)) == null:
		return false
	return int(recipe.required_work_points) > 0 and _is_valid_cost(recipe.craft_cost)


func _has_queued_recipe_or_output(workshop, recipe_id: String, output_gear_id: String) -> bool:
	for order in workshop.queued_production_orders:
		if order == null or order.get_script() != WorkshopOrderStateScript:
			return true
		if str(order.recipe_id) == recipe_id or (not output_gear_id.is_empty() and str(order.output_gear_id) == output_gear_id):
			return true
	return false


func _active_order_error(workshop, order) -> String:
	if order == null or order.get_script() != WorkshopOrderStateScript:
		return "pierwszy wpis nie jest WorkshopOrderState."
	var validation_errors: PackedStringArray = order.validation_errors(str(workshop.id), ResourceIdsScript.all())
	if not validation_errors.is_empty():
		return "; ".join(validation_errors)
	var sequence := int(order.sequence_number(str(workshop.id)))
	if sequence > 0 and sequence >= int(workshop.next_production_order_sequence):
		return "sekwencja zlecenia nie jest mniejsza od next_production_order_sequence."
	return ""


func _complete_order_output(state, order) -> bool:
	if not str(order.output_gear_id).is_empty():
		return state.diving_equipment.add_gear(str(order.output_gear_id))
	if str(order.output_campaign_id) == R3_REGULATOR_ID and state.story_flags != null and state.story_flags.r3_diagnosed and not state.story_flags.r3_generator_active:
		state.story_flags.r3_regulator_ready = true
		state.story_flags.r3_regulator_completed_day = int(state.day)
		state.story_flags.set_flag("r3_regulator_ready", true)
		return true
	if str(order.output_campaign_id) == COMMON_LINE_SPLITTER_ID and state.story_flags != null and state.story_flags.c4_switchboard_active and not state.story_flags.common_line_splitter_installed:
		state.story_flags.common_line_splitter_ready = true
		state.story_flags.common_line_splitter_completed_day = int(state.day)
		state.story_flags.set_flag("common_line_splitter_ready", true)
		return true
	return false


func _get_gear_definition(gear_id: String):
	if gear_id.is_empty():
		return null
	var path := "res://data/diving_gear/%s.tres" % gear_id
	if not ResourceLoader.exists(path):
		return null
	var definition = ResourceLoader.load(path)
	if definition == null or definition.get_script() != DivingGearDefinitionScript or str(definition.id) != gear_id:
		return null
	return definition


func _snapshot_cost(cost: Dictionary) -> Dictionary:
	var snapshot: Dictionary = {}
	for resource_key in cost.keys():
		snapshot[str(resource_key)] = int(cost[resource_key])
	return snapshot.duplicate(true)


func _is_valid_cost(cost: Dictionary) -> bool:
	var known_resource_ids := ResourceIdsScript.all()
	var seen_resource_ids: Dictionary = {}
	for resource_key in cost.keys():
		var resource_id := str(resource_key)
		if (
			typeof(resource_key) != TYPE_STRING
			or resource_id.is_empty()
			or not known_resource_ids.has(resource_id)
			or seen_resource_ids.has(resource_id)
			or typeof(cost[resource_key]) != TYPE_INT
			or int(cost[resource_key]) < 0
		):
			return false
		seen_resource_ids[resource_id] = true
	return true


func _can_afford(state, cost: Dictionary) -> bool:
	for resource_id in cost.keys():
		if state.resources.get_amount(str(resource_id)) < int(cost[resource_id]):
			return false
	return true


func _cost_shortfalls(state, cost: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_resource_id in cost.keys():
		var resource_id := str(raw_resource_id)
		var missing: int = int(cost[raw_resource_id]) - int(state.resources.get_amount(resource_id))
		if missing > 0:
			result.append("%s: brakuje %d" % [ResourceIdsScript.display_name(resource_id), missing])
	return result


func _spend_cost(state, cost: Dictionary) -> bool:
	if state == null or state.resources == null or not _is_valid_cost(cost) or not _can_afford(state, cost):
		return false
	var spent: Dictionary = {}
	for resource_id in cost.keys():
		var amount := int(cost[resource_id])
		if not state.resources.spend(str(resource_id), amount):
			_refund_cost(state, spent)
			return false
		spent[str(resource_id)] = amount
	return true


func _refund_cost(state, cost: Dictionary) -> void:
	if state == null or state.resources == null:
		return
	for resource_id in cost.keys():
		state.resources.add_amount(str(resource_id), int(cost[resource_id]))


func _add_warning(report, message: String) -> void:
	if report != null:
		report.add_warning(message)


func _production_slots(workshop_level: int) -> int:
	var capabilities := _workshop_capabilities(workshop_level)
	return maxi(int(capabilities.get("production_slots_per_day", 1)), 1)


func _queue_capacity(workshop_level: int) -> int:
	var capabilities := _workshop_capabilities(workshop_level)
	return maxi(int(capabilities.get("production_queue_capacity", 1)), 1)


func _workshop_capabilities(workshop_level: int) -> Dictionary:
	var definition = ResourceLoader.load("res://base_workbench/data/buildings/workshop.tres")
	var level_definition = definition.get_level_definition(workshop_level) if definition != null else null
	return level_definition.capabilities if level_definition != null else {}


func _has_capable_worker(state, workshop) -> bool:
	for survivor_id in workshop.assigned_survivor_ids:
		var survivor = state.find_survivor(str(survivor_id))
		if survivor != null and survivor.can_work():
			return true
	return false


func _workforce_has_talent(state, workshop, workforce_talent_state, talent_id: String) -> bool:
	if workforce_talent_state != null:
		if workforce_talent_state is Dictionary:
			var talent_ids = workforce_talent_state.get("talent_ids", [])
			if talent_ids.has(talent_id):
				return true
			if bool(workforce_talent_state.get(talent_id, false)):
				return true
			for selected_talent_id in workforce_talent_state.values():
				if str(selected_talent_id) == talent_id:
					return true
			return false
		if workforce_talent_state is Array or workforce_talent_state is PackedStringArray:
			return workforce_talent_state.has(talent_id)
		return false
	if state == null or workshop == null or not state.has_method("find_survivor"):
		return false
	for survivor_id in workshop.assigned_survivor_ids:
		var survivor = state.find_survivor(str(survivor_id))
		if survivor != null and survivor.can_work() and ProfessionTalentSystemScript.has_talent(survivor, talent_id):
			return true
	return false


func _production_competency_multiplier(state, workshop) -> float:
	var total := 0.0
	var count := 0
	for survivor_id in workshop.assigned_survivor_ids:
		var survivor = state.find_survivor(str(survivor_id))
		if survivor == null or not survivor.can_work():
			continue
		total += CompetencySystemScript.production_multiplier(survivor)
		count += 1
	return total / float(count) if count > 0 else 1.0
