class_name LootSystem
extends RefCounted

func transfer_single(session, resource_id: String) -> bool:
	return session != null and not resource_id.is_empty() and session.add_item(resource_id, 1) == 1

func transfer_amount(session, contents: Dictionary, resource_id: String, requested_amount: int) -> int:
	if session == null or resource_id.is_empty() or requested_amount <= 0 or not contents.has(resource_id):
		return 0
	var available := maxi(int(contents.get(resource_id, 0)), 0)
	if available <= 0:
		return 0
	var accepted: int = session.add_item(resource_id, mini(requested_amount, available))
	accepted = clampi(accepted, 0, available)
	if accepted <= 0:
		return 0
	var remaining := available - accepted
	if remaining > 0:
		contents[resource_id] = remaining
	else:
		contents.erase(resource_id)
	return accepted

func transfer_all(session, contents: Dictionary) -> Dictionary:
	var transferred: Dictionary = {}
	var resource_ids := contents.keys()
	for resource_id in resource_ids:
		var id := str(resource_id)
		var available := int(contents.get(resource_id, 0))
		var accepted := transfer_amount(session, contents, id, available)
		if accepted > 0:
			transferred[id] = accepted
	return transferred
