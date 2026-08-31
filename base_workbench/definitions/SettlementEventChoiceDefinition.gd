class_name SettlementEventChoiceDefinition
extends Resource

@export var id: String = ""
@export var label: String = ""
@export_multiline var preview: String = ""
@export_multiline var result_text: String = ""
@export var resource_deltas: Dictionary = {}
@export var survivor_definition_ids: Array[String] = []
@export var impact_tags: Array[String] = []

func is_valid() -> bool:
	if id.is_empty() or label.is_empty() or result_text.is_empty():
		return false
	var seen_tags: Array[String] = []
	for raw_tag in impact_tags:
		var tag := str(raw_tag)
		if tag.is_empty() or seen_tags.has(tag):
			return false
		seen_tags.append(tag)
	return true

func has_resource_cost() -> bool:
	for resource_id in resource_deltas.keys():
		if str(resource_id) in ["hope", "platform_integrity"]:
			continue
		if int(resource_deltas[resource_id]) < 0:
			return true
	return false
