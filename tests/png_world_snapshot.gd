extends Node

const GameRootScene := preload("res://scenes/main/GameRoot.tscn")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")

const SNAPSHOTS := {
	"R1-00": "world_png_r1_station.png",
	"R1-03": "world_png_r1_hotel_rescue.png",
	"R1-04": "world_png_r1_j7_art_cell.png",
	"R1-09": "world_png_r1_archive.png",
	"R2-02": "world_png_r2_park.png",
	"R3-04": "world_png_r3_power_plant.png",
	"R4-05": "world_png_r4_city_center.png",
	"R4-06": "world_png_r4_heart.png",
}

const QUALITY_SNAPSHOTS := [
	{"landmark_id": "R1-00", "file_name": "world_png_r1_station_low.png", "quality": "low", "reduced_motion": false},
	{"landmark_id": "R1-09", "file_name": "world_png_r1_archive_low.png", "quality": "low", "reduced_motion": false},
	{"landmark_id": "R1-09", "file_name": "world_png_r1_archive_medium.png", "quality": "medium", "reduced_motion": false},
	{"landmark_id": "R1-09", "file_name": "world_png_r1_archive_reduced.png", "quality": "high", "reduced_motion": true},
	{"landmark_id": "R2-02", "file_name": "world_png_r2_park_low.png", "quality": "low", "reduced_motion": false},
	{"landmark_id": "R2-02", "file_name": "world_png_r2_park_medium.png", "quality": "medium", "reduced_motion": false},
	{"landmark_id": "R2-02", "file_name": "world_png_r2_park_reduced.png", "quality": "high", "reduced_motion": true},
	{"landmark_id": "R3-04", "file_name": "world_png_r3_power_plant_low.png", "quality": "low", "reduced_motion": false},
	{"landmark_id": "R3-04", "file_name": "world_png_r3_power_plant_medium.png", "quality": "medium", "reduced_motion": false},
	{"landmark_id": "R3-04", "file_name": "world_png_r3_power_plant_reduced.png", "quality": "high", "reduced_motion": true},
	{"landmark_id": "R4-05", "file_name": "world_png_r4_city_center_low.png", "quality": "low", "reduced_motion": false},
	{"landmark_id": "R4-05", "file_name": "world_png_r4_city_center_medium.png", "quality": "medium", "reduced_motion": false},
	{"landmark_id": "R4-05", "file_name": "world_png_r4_city_center_reduced.png", "quality": "high", "reduced_motion": true},
	{"landmark_id": "R4-06", "file_name": "world_png_r4_heart_reduced.png", "quality": "high", "reduced_motion": true},
]

const BACKDROP_TIME_SNAPSHOTS := [
	{"file_name": "world_png_r2_backdrop_t8.png", "anim_time": 8.0, "reduced_motion": false},
	{"file_name": "world_png_r2_backdrop_reduced_t4.png", "anim_time": 4.0, "reduced_motion": true},
	{"file_name": "world_png_r2_backdrop_reduced_t8.png", "anim_time": 8.0, "reduced_motion": true},
]

const LIGHT_SNAPSHOTS := [
	{"landmark_id": "R3-04", "file_name": "world_png_r3_lantern_off.png", "enabled": false, "quality": "high", "reduced_motion": false},
	{"landmark_id": "R3-04", "file_name": "world_png_r3_lantern_on.png", "enabled": true, "quality": "high", "reduced_motion": false},
	{"landmark_id": "R3-04", "file_name": "world_png_r3_lantern_on_low.png", "enabled": true, "quality": "low", "reduced_motion": false},
	{"landmark_id": "R3-04", "file_name": "world_png_r3_lantern_on_medium.png", "enabled": true, "quality": "medium", "reduced_motion": false},
	{"landmark_id": "R3-04", "file_name": "world_png_r3_lantern_on_reduced.png", "enabled": true, "quality": "high", "reduced_motion": true},
	{"landmark_id": "R3-04", "file_name": "world_png_r3_lantern_on_left.png", "enabled": true, "quality": "high", "reduced_motion": false, "facing_left": true},
	{"landmark_id": "R4-05", "file_name": "world_png_r4_lantern_off.png", "enabled": false, "quality": "high", "reduced_motion": false},
	{"landmark_id": "R4-05", "file_name": "world_png_r4_lantern_on.png", "enabled": true, "quality": "high", "reduced_motion": false},
	{"landmark_id": "R4-05", "file_name": "world_png_r4_lantern_on_low.png", "enabled": true, "quality": "low", "reduced_motion": false},
	{"landmark_id": "R4-05", "file_name": "world_png_r4_lantern_on_medium.png", "enabled": true, "quality": "medium", "reduced_motion": false},
	{"landmark_id": "R4-05", "file_name": "world_png_r4_lantern_on_reduced.png", "enabled": true, "quality": "high", "reduced_motion": true},
]

const R3_LANTERN_RIGHT_ROI := Rect2i(710, 320, 100, 80)
const R3_LANTERN_LEFT_ROI := Rect2i(470, 320, 120, 80)
const MIN_LANTERN_LUMA_DELTA := 0.018
const J7_ART_CELL_REVIEW_POSITION := Vector2(2420.0, 1176.0)

func _ready() -> void:
	var game = GameRootScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	game.start_new_campaign("standard", 103, false)
	await get_tree().process_frame

	var setup = ExpeditionSetupScript.new()
	setup.diver_id = "igor"
	# Day 12 materializes every authored story device for layout-only visual QA.
	setup.day = 12
	setup.oxygen_capacity = 100.0
	setup.backpack_capacity = 6
	setup.target_sector = "dead_city_rooftops_001"
	setup.selected_objective = "visual_regression"
	setup.tutorial_mode = false
	setup.equipped_gear["light"] = "diving_lantern_mk1"
	game.game_state.tutorial.complete()
	# The gold-frame J-7 review represents the post-tutorial route: the cable
	# blockage is removed and the junction state matches the approved target.
	game.game_state.underwater_world.opened_shortcuts.append("SC-01")
	game.game_state.underwater_world.activated_fixed_devices.append("junction_j7")
	game.start_dive(setup)
	await get_tree().process_frame
	await get_tree().process_frame

	var dive = game.current_scene
	for landmark_id in SNAPSHOTS:
		if not await _capture_snapshot(game, dive, str(landmark_id), str(SNAPSHOTS[landmark_id]), "high", false):
			return
	if not await _capture_world_position_snapshot(
		dive,
		J7_ART_CELL_REVIEW_POSITION,
		"world_png_r1_j7_target_view.png",
		"high",
		false
	):
		return

	for snapshot_variant in QUALITY_SNAPSHOTS:
		if not await _capture_snapshot(
			game,
			dive,
			str(snapshot_variant.get("landmark_id", "")),
			str(snapshot_variant.get("file_name", "")),
			str(snapshot_variant.get("quality", "high")),
			bool(snapshot_variant.get("reduced_motion", false)),
			float(snapshot_variant.get("anim_time", 4.0))
		):
			return
	for time_snapshot in BACKDROP_TIME_SNAPSHOTS:
		if not await _capture_snapshot(
			game,
			dive,
			"R2-02",
			str(time_snapshot.get("file_name", "")),
			"high",
			bool(time_snapshot.get("reduced_motion", false)),
			float(time_snapshot.get("anim_time", 4.0))
		):
			return
	for light_snapshot in LIGHT_SNAPSHOTS:
		if not await _capture_light_snapshot(
			game,
			dive,
			str(light_snapshot.get("landmark_id", "")),
			bool(light_snapshot.get("enabled", true)),
			str(light_snapshot.get("file_name", "")),
			str(light_snapshot.get("quality", "high")),
			bool(light_snapshot.get("reduced_motion", false)),
			bool(light_snapshot.get("facing_left", false))
		):
			return
	if not _verify_r3_lantern_volume():
		return
	if not await _capture_motion_snapshot(game, dive):
		return

	print("PNG world visual snapshots saved for all regions, story layouts, quality profiles, reduced motion and diver wake.")
	get_tree().quit(0)


func _capture_snapshot(game, dive, landmark_id: String, file_name: String, quality: String, reduced_motion: bool, anim_time: float = 4.0) -> bool:
	var landmark: Dictionary = game.game_state.underwater_world.get_sector_blueprint(landmark_id)
	if landmark.is_empty():
		push_error("Missing PNG snapshot landmark: " + landmark_id)
		get_tree().quit(1)
		return false
	var requested_position: Vector2 = landmark.get("position", Vector2.ZERO)
	return await _capture_world_position_snapshot(dive, requested_position, file_name, quality, reduced_motion, anim_time)


func _capture_world_position_snapshot(dive, requested_position: Vector2, file_name: String, quality: String, reduced_motion: bool, anim_time: float = 4.0) -> bool:
	var at: Vector2 = dive.dive_map.nearest_navigable_position(requested_position)
	dive.set_graphics_quality(quality)
	dive.set_reduced_motion(reduced_motion)
	dive.session.light_enabled = false
	dive._apply_diver_light_state()
	dive.diver.reset_at(at)
	dive.dive_map.update_streaming(at, true, dive._streaming_visible_half_extent())
	var terrain_renderer := dive.dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/TerrainRenderer") as UnderwaterTerrainRenderer
	if terrain_renderer != null:
		terrain_renderer.auto_advance_animation = false
		terrain_renderer.set_anim_time(anim_time)
	if dive._underwater_environment != null:
		dive._underwater_environment.set_visual_time_for_tests(anim_time)
	dive._update_current_presentation(0.0, true)
	dive._update_environment_lighting(0.0)
	dive._update_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	await _settle_visual_chunks(dive)
	return _save_snapshot(file_name)


func _capture_light_snapshot(game, dive, landmark_id: String, enabled: bool, file_name: String, quality: String, reduced_motion: bool, facing_left: bool = false) -> bool:
	var landmark: Dictionary = game.game_state.underwater_world.get_sector_blueprint(landmark_id)
	if landmark.is_empty():
		push_error("Missing PNG light snapshot landmark: " + landmark_id)
		get_tree().quit(1)
		return false
	var at: Vector2 = dive.dive_map.nearest_navigable_position(landmark.get("position", Vector2.ZERO))
	dive.set_graphics_quality(quality)
	dive.set_reduced_motion(reduced_motion)
	dive.diver.reset_at(at)
	dive.session.light_enabled = enabled
	dive._apply_diver_light_state()
	var diver_sprite := dive.diver.get_node("AnimatedSprite2D") as AnimatedSprite2D
	diver_sprite.flip_h = facing_left
	dive.diver._update_socket_markers()
	dive.diver._update_light_mount()
	dive.dive_map.update_streaming(at, true, dive._streaming_visible_half_extent())
	var terrain_renderer := dive.dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/TerrainRenderer") as UnderwaterTerrainRenderer
	if terrain_renderer != null:
		terrain_renderer.auto_advance_animation = false
		terrain_renderer.set_anim_time(4.0)
	if dive._underwater_environment != null:
		dive._underwater_environment.set_visual_time_for_tests(4.0)
	dive._update_current_presentation(0.0, true)
	dive._update_environment_lighting(0.0)
	dive._update_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	await _settle_visual_chunks(dive)
	return _save_snapshot(file_name)


func _capture_motion_snapshot(game, dive) -> bool:
	var landmark: Dictionary = game.game_state.underwater_world.get_sector_blueprint("R2-02")
	if landmark.is_empty():
		push_error("Missing PNG motion snapshot landmark: R2-02")
		get_tree().quit(1)
		return false
	var at: Vector2 = dive.dive_map.nearest_navigable_position(landmark.get("position", Vector2.ZERO))
	dive.set_graphics_quality("high")
	dive.set_reduced_motion(false)
	dive.diver.reset_at(at)
	dive.dive_map.update_streaming(at, true, dive._streaming_visible_half_extent())
	dive.diver.set_physics_process(false)
	dive.diver.velocity = Vector2(176.0, 0.0)
	dive.diver.movement_input = Vector2.RIGHT
	dive.diver.is_sprinting = false
	var diver_sprite := dive.diver.get_node("AnimatedSprite2D") as AnimatedSprite2D
	diver_sprite.flip_h = false
	diver_sprite.play(&"swim")
	diver_sprite.pause()
	diver_sprite.set_frame_and_progress(8, 0.0)
	dive._update_current_presentation(0.0, true)
	dive._update_environment_lighting(0.0)
	dive._update_ui()
	for _frame in range(55):
		await get_tree().process_frame
	await _settle_visual_chunks(dive)
	var saved := _save_snapshot("world_png_r2_park_motion.png")
	dive.diver.velocity = Vector2.ZERO
	dive.diver.set_physics_process(true)
	return saved


func _settle_visual_chunks(dive) -> void:
	var streamer: Node = dive.dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/VisualChunkStreamer")
	if streamer == null:
		return
	for _frame in range(180):
		var pending: Array[String] = streamer.pending_chunk_keys()
		var desired: Array[String] = streamer.desired_chunk_keys()
		var loaded: Array[String] = streamer.loaded_chunk_keys()
		if pending.is_empty() and loaded.size() >= desired.size():
			return
		await get_tree().process_frame
	push_error("Visual chunks did not settle before PNG snapshot.")
	get_tree().quit(1)


func _verify_r3_lantern_volume() -> bool:
	var output_directory := ProjectSettings.globalize_path("res://tmp")
	var lantern_off := Image.load_from_file(output_directory.path_join("world_png_r3_lantern_off.png"))
	var lantern_right := Image.load_from_file(output_directory.path_join("world_png_r3_lantern_on.png"))
	var lantern_left := Image.load_from_file(output_directory.path_join("world_png_r3_lantern_on_left.png"))
	if lantern_off.is_empty() or lantern_right.is_empty() or lantern_left.is_empty():
		push_error("Could not load R3 lantern snapshots for volumetric-light verification.")
		get_tree().quit(1)
		return false
	var right_delta := _mean_luminance(lantern_right, R3_LANTERN_RIGHT_ROI) - _mean_luminance(lantern_off, R3_LANTERN_RIGHT_ROI)
	var left_delta := _mean_luminance(lantern_left, R3_LANTERN_LEFT_ROI) - _mean_luminance(lantern_off, R3_LANTERN_LEFT_ROI)
	if right_delta < MIN_LANTERN_LUMA_DELTA or left_delta < MIN_LANTERN_LUMA_DELTA:
		push_error(
			"R3 lantern volume is not visibly directional. right_delta=%.4f left_delta=%.4f"
			% [right_delta, left_delta]
		)
		get_tree().quit(1)
		return false
	return true


func _mean_luminance(image: Image, roi: Rect2i) -> float:
	var safe_end := Vector2i(
		mini(roi.end.x, image.get_width()),
		mini(roi.end.y, image.get_height())
	)
	var sample_count := 0
	var luminance_sum := 0.0
	for y in range(maxi(roi.position.y, 0), safe_end.y):
		for x in range(maxi(roi.position.x, 0), safe_end.x):
			luminance_sum += image.get_pixel(x, y).get_luminance()
			sample_count += 1
	return luminance_sum / maxf(float(sample_count), 1.0)

func _save_snapshot(file_name: String) -> bool:
	var image := get_viewport().get_texture().get_image()
	var output_directory := ProjectSettings.globalize_path("res://tmp")
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error != OK:
		push_error("Could not create PNG snapshot directory. Error: %d" % directory_error)
		get_tree().quit(1)
		return false
	var output_path := output_directory.path_join(file_name)
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save PNG world snapshot. Error: %d" % error)
		get_tree().quit(1)
		return false
	return true
