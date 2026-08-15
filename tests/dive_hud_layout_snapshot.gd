extends Node

const DiveHudDockScript := preload("res://scripts/diving/DiveHudDock.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")
const DiveSessionStateScript := preload("res://scripts/data/DiveSessionState.gd")
const ResourceIdsScript := preload("res://scripts/data/ResourceIds.gd")

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("082832"))
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var dock = DiveHudDockScript.new()
	dock.anchor_top = 1.0
	dock.anchor_right = 1.0
	dock.anchor_bottom = 1.0
	dock.offset_left = 16
	dock.offset_top = -88
	dock.offset_right = -16
	dock.offset_bottom = -12
	dock.build()
	canvas.add_child(dock)
	await get_tree().process_frame

	var setup = ExpeditionSetupScript.new()
	setup.diver_id = "igor"
	setup.diver_display_name = "Igor Sowa"
	setup.diver_profession = "nurek"
	setup.diver_portrait_id = "igor"
	setup.diver_level = 3
	setup.diver_experience = 65
	setup.diver_experience_to_next_level = 200
	setup.diver_health = 84
	setup.diver_health_capacity = 110
	setup.oxygen_capacity = 145.0
	setup.diver_personal_oxygen_capacity = 110.0
	setup.oxygen_tank_capacity = 130.0
	setup.equipped_gear = {"light": "diving_lantern_mk2", "oxygen_tank": "oxygen_tank_mk2"}
	setup.backpack_capacity = 6
	setup.diver_carry_capacity = 18.0
	setup.item_weights = {
		ResourceIdsScript.FOOD: 1.0,
		ResourceIdsScript.PLANKS: 1.2,
		ResourceIdsScript.SCRAP: 1.5,
	}

	var session = DiveSessionStateScript.new()
	session.begin(setup)
	session.oxygen_left = 96.0
	session.add_item(ResourceIdsScript.FOOD, 6)
	session.add_item(ResourceIdsScript.PLANKS, 4)
	session.add_item(ResourceIdsScript.SCRAP, 3)
	session.suit_condition = 92
	session.elapsed_time = 198.0
	dock.update_identity(setup)
	dock.update_vitals(session)
	dock.update_inventory(session)
	var light_definition = ResourceLoader.load("res://data/diving_gear/diving_lantern_mk2.tres")
	dock.update_light(light_definition)
	if not dock.light_label.text.contains("WŁ.") or not dock.light_label.text.contains("[F]"):
		push_error("Dive HUD should expose the equipped light's real state and remappable toggle prompt.")
		get_tree().quit(1)
		return
	var oxygen_tank_definition = ResourceLoader.load("res://data/diving_gear/oxygen_tank_mk2.tres")
	dock.update_oxygen_tank(oxygen_tank_definition)
	await get_tree().process_frame
	await get_tree().process_frame

	if dock == null or dock.size.x < 1200.0 or dock.size.y > 80.0 or dock.size.y < 68.0:
		push_error("Minimal dive HUD should span the viewport while staying below 80 pixels tall.")
		get_tree().quit(1)
		return
	var dock_style := dock.get_theme_stylebox("panel") as StyleBoxFlat
	if dock_style == null or dock_style.bg_color.a > 0.0 or dock_style.get_border_width(SIDE_LEFT) != 0:
		push_error("Dive HUD dock should keep a transparent background and no outer frame.")
		get_tree().quit(1)
		return
	var floating_root := dock.get_node_or_null("FloatingHudGroups") as Control
	var inventory_scroll := dock.inventory_cluster.get_node_or_null("InventoryBar/InventoryScroll") as ScrollContainer
	if dock.mouse_filter != Control.MOUSE_FILTER_IGNORE or floating_root == null or floating_root.mouse_filter != Control.MOUSE_FILTER_IGNORE or inventory_scroll == null or inventory_scroll.mouse_filter != Control.MOUSE_FILTER_STOP:
		push_error("Transparent HUD roots must stay click-through while the inventory scroll remains interactive.")
		get_tree().quit(1)
		return
	if dock.portrait == null or dock.oxygen_bar == null or dock.health_bar == null or dock.inventory_slots.size() != 6:
		push_error("Dive HUD should contain a portrait, health, oxygen and six inventory slots.")
		get_tree().quit(1)
		return
	if dock.vitals_cluster == null or dock.vitals_cluster.size.x > 310.0 or dock.inventory_cluster == null or dock.inventory_cluster.size.x > 345.0 or dock.context_cluster == null or dock.context_cluster.size.x > 280.0:
		push_error("Dive HUD should use three bounded floating clusters instead of large cards.")
		get_tree().quit(1)
		return
	if dock.portrait.size.x > 50.0 or dock.inventory_slots[0].size.x > 44.0 or dock.inventory_slots[0].size.y > 44.0:
		push_error("Minimal dive HUD should keep the portrait and hotbar slots compact.")
		get_tree().quit(1)
		return
	if dock.vitals_cluster.get_global_rect().end.x > dock.inventory_cluster.get_global_rect().position.x or dock.inventory_cluster.get_global_rect().end.x > dock.context_cluster.get_global_rect().position.x:
		push_error("Floating HUD clusters should not overlap at the canonical 1280x720 viewport.")
		get_tree().quit(1)
		return
	if dock.time_label.visible:
		push_error("Zero cold and noise values should stay hidden in the contextual status cluster.")
		get_tree().quit(1)
		return
	if dock.context_cluster.size.y > 48.0:
		push_error("The calm-state equipment capsule should stay below 48 pixels tall.")
		get_tree().quit(1)
		return
	if dock.inventory_summary_label == null or not dock.inventory_summary_label.text.contains("WAGA") or not is_equal_approx(session.get_carried_weight(), 15.3):
		push_error("Dive HUD should expose the diver's current carried weight and carry limit. Actual label: %s" % (dock.inventory_summary_label.text if dock.inventory_summary_label != null else "<missing>"))
		get_tree().quit(1)
		return
	if not dock.oxygen_label.text.contains("B-II"):
		push_error("Compact oxygen telemetry should retain the equipped tank tier without restoring a separate card.")
		get_tree().quit(1)
		return
	if not dock.inventory_slots[0].tooltip_text.contains("6 szt.") or not dock.inventory_slots[0].tooltip_text.contains("6,0 kg"):
		push_error("A compact occupied slot should retain full stack quantity and weight in its tooltip.")
		get_tree().quit(1)
		return

	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("Dive HUD snapshot requires a rendering display driver, not the headless dummy renderer.")
		get_tree().quit(1)
		return
	var output_directory := ProjectSettings.globalize_path("res://tmp")
	if not DirAccess.dir_exists_absolute(output_directory):
		var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
		if directory_error != OK:
			push_error("Could not create the dive HUD snapshot directory. Error: %d" % directory_error)
			get_tree().quit(1)
			return
	var error := image.save_png(output_directory.path_join("dive_hud_layout.png"))
	if error != OK:
		push_error("Could not save dive HUD layout snapshot. Error: %d" % error)
		get_tree().quit(1)
		return
	session.cold_exposure = 31.0
	session.noise_level = 20.0
	dock.update_vitals(session)
	await get_tree().process_frame
	if not dock.time_label.visible or not dock.time_label.text.contains("CHŁÓD 31%") or not dock.time_label.text.contains("HAŁAS 20%") or dock.context_cluster.size.y < 58.0 or dock.context_cluster.size.y > 64.0:
		push_error("The contextual equipment capsule should expand only when cold or noise telemetry is active.")
		get_tree().quit(1)
		return
	for capacity in [6, 10, 14, 16]:
		session.backpack_capacity = capacity
		dock.update_inventory(session)
		await get_tree().process_frame
		if dock.inventory_slots.size() != capacity or dock.inventory_labels.size() != capacity:
			push_error("Dive HUD should rebuild its scrollable inventory for a %d-slot backpack." % capacity)
			get_tree().quit(1)
			return
		if dock.inventory_labels[0].text != "JED.\nx6" or dock.inventory_labels[1].text != "DES.\nx4" or dock.inventory_labels[2].text != "ZŁOM\nx3":
			push_error("Dynamic backpack rebuilding should preserve occupied stack labels at capacity %d." % capacity)
			get_tree().quit(1)
			return
		if dock.inventory_labels[capacity - 1].text != "%02d" % capacity:
			push_error("The final empty slot should retain its ordinal at capacity %d." % capacity)
			get_tree().quit(1)
			return
	print("Dive HUD layout snapshot saved: three compact floating clusters, contextual telemetry and dynamic 6/10/14/16-slot inventory are present.")
	get_tree().quit(0)
