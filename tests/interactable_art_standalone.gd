extends SceneTree

const ContainerScript := preload("res://scripts/diving/DiveLootContainer.gd")
const PickupScript := preload("res://scripts/diving/DiveWorldPickup.gd")
const PersistentScript := preload("res://scripts/diving/DivePersistentInteractable.gd")
const FixedVisualScript := preload("res://scripts/diving/DiveFixedDeviceVisual.gd")

const OUTPUT_PATH := "res://tmp/interactable_art_standalone.png"
const DEVICE_OUTPUT_PATH := "res://tmp/fixed_devices_standalone.png"

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var first := await _capture_interactables()
	var second := await _capture_devices()
	if not first or not second or _failed:
		quit(1)
		return
	print("Standalone interactable art snapshots saved.")
	quit(0)


func _capture_interactables() -> bool:
	var viewport := _make_viewport()
	var world := _make_backdrop()
	viewport.add_child(world)
	var nodes: Array[Node2D] = []
	nodes.append(_container("r1_food_cache", "Skrzynia żywności", {"food": 3}, "open", "R1"))
	nodes.append(_container("r2_medicine_cache", "Apteczka szklarni", {"meds": 2}, "pry", "R2"))
	nodes.append(_container("r3_workshop_cache", "Magazyn serwisowy", {"scrap": 3}, "pry", "R3"))
	nodes.append(_container("r4_structural_cache", "Rezerwa głębinowa", {"planks": 3}, "cut", "R4"))
	nodes.append(_pickup("pickup_r1_food_01", "food", "R1"))
	nodes.append(_pickup("pickup_r2_planks_01", "planks", "R2"))
	nodes.append(_pickup("pickup_r3_scrap_01", "scrap", "R3"))
	var buoy := PersistentScript.new()
	buoy.configure(PersistentScript.Kind.BUOY, "B-03", "Kotwica boi", false)
	buoy.configure_visual_context({"region_id": "R4"}, "R4")
	nodes.append(buoy)
	var positions := [Vector2(150, 170), Vector2(470, 170), Vector2(810, 170), Vector2(1120, 170), Vector2(230, 485), Vector2(540, 485), Vector2(850, 485), Vector2(1120, 485)]
	for index in range(nodes.size()):
		nodes[index].position = positions[index]
		world.add_child(nodes[index])
	await process_frame
	await process_frame
	var saved := _save_viewport(viewport, OUTPUT_PATH)
	root.remove_child(viewport)
	viewport.free()
	return saved


func _capture_devices() -> bool:
	var viewport := _make_viewport()
	var world := _make_backdrop()
	viewport.add_child(world)
	var kinds := ["junction", "archive", "diagnostic", "generator", "switchboard", "splitter"]
	var regions := ["R1", "R1", "R3", "R3", "R4", "R4"]
	var positions := [Vector2(210, 195), Vector2(640, 195), Vector2(1060, 195), Vector2(210, 500), Vector2(640, 500), Vector2(1060, 500)]
	for index in range(kinds.size()):
		var anchor := Node2D.new()
		anchor.position = positions[index]
		world.add_child(anchor)
		var device := FixedVisualScript.new()
		device.device_kind = kinds[index]
		device.region_id = regions[index]
		anchor.add_child(device)
		var status_marker := PersistentScript.new()
		status_marker.configure(PersistentScript.Kind.FIXED_DEVICE, "%s_probe" % kinds[index], kinds[index], false)
		status_marker.configure_visual_context({"region_id": regions[index]}, regions[index])
		status_marker.set_authored_visual_override(true)
		anchor.add_child(status_marker)
	await process_frame
	await process_frame
	var saved := _save_viewport(viewport, DEVICE_OUTPUT_PATH)
	root.remove_child(viewport)
	viewport.free()
	return saved


func _make_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	return viewport


func _make_backdrop() -> Node2D:
	var world := Node2D.new()
	var background := Polygon2D.new()
	background.polygon = PackedVector2Array([Vector2.ZERO, Vector2(1280, 0), Vector2(1280, 720), Vector2(0, 720)])
	background.color = Color("092631")
	world.add_child(background)
	for index in range(4):
		var bed := Polygon2D.new()
		bed.polygon = PackedVector2Array([Vector2(index * 320, 610), Vector2(index * 320 + 320, 565), Vector2(index * 320 + 320, 720), Vector2(index * 320, 720)])
		bed.color = [Color("35525d"), Color("354b3f"), Color("4d3b31"), Color("15232c")][index]
		world.add_child(bed)
	return world


func _container(id: String, title: String, contents: Dictionary, action: String, region: String):
	var container = ContainerScript.new()
	container.configure(id, title, contents, -1, "", action, 1.0)
	container.configure_visual_context({"region_id": region}, region)
	container.set_graphics_quality("high")
	return container


func _pickup(id: String, resource_id: String, region: String):
	var texture := load("res://assets/diving/pickups/%s_pickup.png" % resource_id) as Texture2D
	var pickup = PickupScript.new()
	pickup.configure(id, resource_id, resource_id, texture, false)
	pickup.configure_visual_context({"region_id": region}, region)
	pickup.set_graphics_quality("high")
	pickup.set_reduced_motion(true)
	return pickup


func _save_viewport(viewport: SubViewport, path: String) -> bool:
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Standalone interactable snapshot returned an empty image.")
		_failed = true
		return false
	var result := image.save_png(ProjectSettings.globalize_path(path))
	if result != OK:
		push_error("Standalone interactable snapshot could not save %s." % path)
		_failed = true
		return false
	return true
