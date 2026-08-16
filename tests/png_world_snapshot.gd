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
const R1_ART_CELL_GAMEPLAY_SNAPSHOTS := [
	{"position": Vector2(1365.0, 768.0), "file_name": "world_png_r1_art_cell_001.png"},
	{"position": Vector2(3669.0, 768.0), "file_name": "world_png_r1_art_cell_002.png"},
	{"position": Vector2(5973.0, 768.0), "file_name": "world_png_r1_art_cell_003.png"},
	{"position": Vector2(8277.0, 768.0), "file_name": "world_png_r1_art_cell_004.png"},
	# The geometric center of cell 005 is intentionally buried under canonical
	# terrain. This in-cell anchor looks through the open-water pocket above it
	# and verifies production occlusion; clean seam/edge frames expose the plate.
	{"position": Vector2(9600.0, 450.0), "file_name": "world_png_r1_art_cell_005.png"},
]
const R1_ART_CELL_CLEAN_SNAPSHOTS := [
	{"position": Vector2(2517.0, 960.0), "file_name": "world_png_r1_seam_001_002.png"},
	{"position": Vector2(4821.0, 960.0), "file_name": "world_png_r1_seam_002_003.png"},
	{"position": Vector2(7125.0, 960.0), "file_name": "world_png_r1_seam_003_004.png"},
	{"position": Vector2(9429.0, 960.0), "file_name": "world_png_r1_seam_004_005.png"},
	{"position": Vector2(533.333333, 960.0), "file_name": "world_png_r1_edge_left_clean.png"},
	{"position": Vector2(10986.666667, 960.0), "file_name": "world_png_r1_edge_right_clean.png"},
	{"position": Vector2(5760.0, 300.0), "file_name": "world_png_r1_edge_top_clean.png"},
	{"position": Vector2(5760.0, 1236.0), "file_name": "world_png_r1_edge_bottom_clean.png"},
	{"position": Vector2(5120.0, 1024.0), "file_name": "world_png_r1_runtime_chunk_seams_clean.png"},
	{"position": Vector2(10368.0, 1024.0), "file_name": "world_png_r1_art_cell_005_center_clean.png"},
]
const R1_ART_CELL_LIBRARY_PATH := "res://assets/diving/world/art_cells/r1/r1_art_cells_v1.json"
const R1_VISIBILITY_EXPECTED_CASE_COUNT := 5
const R1_VISIBILITY_DELTA_THRESHOLD := 6.0 / 255.0
const R1_VISIBILITY_MIN_SIGNAL_RATIO := 0.15
const R1_VISIBILITY_MIN_STRUCTURED_RATIO := 0.01
const R1_VISIBILITY_MIN_DETAIL_SURVIVAL_SHARE := 0.25
const R1_VISIBILITY_MIN_SURVIVAL_RATIO := 0.35
const R1_VISIBILITY_BIN_COUNT := 8
const R1_VISIBILITY_MIN_ACTIVE_BINS := 3
const R1_VISIBILITY_MIN_BIN_STRUCTURED_RATIO := 0.01
const R1_VISIBILITY_DETAIL_DOWNSAMPLE := 4
const R1_VISIBILITY_DETAIL_GRADIENT_THRESHOLD := 3
const R1_VISIBILITY_JITTER_DELTA_THRESHOLD := 2.0 / 255.0
const R1_VISIBILITY_MAX_JITTER_RMS := 1.0 / 255.0
const R1_VISIBILITY_MAX_JITTER_PIXEL_RATIO := 0.001

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
	# These remain gameplay frames: the diver is present, while the camera is
	# independently anchored to the exact ArtCell review coordinate.
	for review_snapshot in R1_ART_CELL_GAMEPLAY_SNAPSHOTS:
		if not await _capture_anchored_world_snapshot(
			dive,
			review_snapshot.get("position", Vector2.ZERO),
			str(review_snapshot.get("file_name", "")),
			"high",
			false,
			false
		):
			return
	# Clean frames preserve the production camera, water grade and streaming, but
	# temporarily isolate the R1 raster from foreground terrain/authored objects.
	# The gameplay frames above remain the authoritative in-context comparison.
	for review_snapshot in R1_ART_CELL_CLEAN_SNAPSHOTS:
		if not await _capture_anchored_world_snapshot(
			dive,
			review_snapshot.get("position", Vector2.ZERO),
			str(review_snapshot.get("file_name", "")),
			"high",
			false,
			true,
			4.0,
			true
		):
			return
	if not await _capture_r1_visibility_qa(dive):
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
	return await _capture_positioned_world_snapshot(
		dive,
		at,
		at,
		file_name,
		quality,
		reduced_motion,
		false,
		anim_time
	)


func _capture_anchored_world_snapshot(
	dive,
	camera_position: Vector2,
	file_name: String,
	quality: String,
	reduced_motion: bool,
	hide_diver: bool,
	anim_time: float = 4.0,
	isolate_r1_art_cells: bool = false,
	hide_hud: bool = false,
	hide_r1_art_cells: bool = false,
	frozen_particle_state: Dictionary = {},
	apply_visual_settings: bool = true
) -> bool:
	var diver_position: Vector2 = dive.dive_map.nearest_navigable_position(camera_position)
	return await _capture_positioned_world_snapshot(
		dive,
		camera_position,
		diver_position,
		file_name,
		quality,
		reduced_motion,
		hide_diver,
		anim_time,
		isolate_r1_art_cells,
		hide_hud,
		hide_r1_art_cells,
		frozen_particle_state,
		apply_visual_settings
	)


func _capture_positioned_world_snapshot(
	dive,
	camera_position: Vector2,
	diver_position: Vector2,
	file_name: String,
	quality: String,
	reduced_motion: bool,
	hide_diver: bool,
	anim_time: float,
	isolate_r1_art_cells: bool = false,
	hide_hud: bool = false,
	hide_r1_art_cells: bool = false,
	frozen_particle_state: Dictionary = {},
	apply_visual_settings: bool = true
) -> bool:
	var camera := dive.diver.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		push_error("PNG world snapshot requires the production diver Camera2D.")
		get_tree().quit(1)
		return false
	var original_camera_position := camera.position
	var original_dive_processing: bool = bool(dive.is_processing())
	dive.set_process(false)
	if apply_visual_settings:
		dive.set_graphics_quality(quality)
		dive.set_reduced_motion(reduced_motion)
	# Quality and reduced-motion setters legitimately configure particle speeds.
	# Visibility A/B captures therefore re-apply their temporary freeze only after
	# those setters have finished, while ordinary snapshots keep production motion.
	if not frozen_particle_state.is_empty():
		_enforce_particle_visuals_frozen(dive, frozen_particle_state)
	dive.session.light_enabled = false
	dive._apply_diver_light_state()
	dive.diver.reset_at(diver_position)
	# Camera2D remains the production camera with its real zoom and limits, but a
	# temporary local offset keeps the review coordinate independent from the
	# nearest collision-safe position chosen for the diver.
	camera.global_position = camera_position
	camera.reset_smoothing()
	dive.dive_map.update_streaming(camera_position, true, dive._streaming_visible_half_extent())
	var terrain_renderer := dive.dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/TerrainRenderer") as UnderwaterTerrainRenderer
	if terrain_renderer != null:
		terrain_renderer.auto_advance_animation = false
		terrain_renderer.set_anim_time(anim_time)
	if dive._underwater_environment != null:
		dive._underwater_environment.set_visual_time_for_tests(anim_time)
	dive._update_current_presentation(0.0, true)
	dive._update_environment_lighting(0.0)
	dive._update_ui()
	var diver_visibility_state := _hide_diver_visuals(dive) if hide_diver else {}
	var scene_visibility_state := _isolate_r1_art_cell_visuals(dive) if isolate_r1_art_cells else {}
	if hide_hud:
		_hide_dive_hud(dive, scene_visibility_state)
	if hide_r1_art_cells:
		_hide_r1_art_cells(dive, scene_visibility_state)
	await get_tree().process_frame
	await get_tree().process_frame
	await _settle_visual_chunks(dive)
	if not camera.global_position.is_equal_approx(camera_position):
		push_error("PNG world snapshot camera drifted from requested anchor. requested=%s actual=%s" % [camera_position, camera.global_position])
		get_tree().quit(1)
		_restore_canvas_visibility(scene_visibility_state)
		_restore_diver_visuals(diver_visibility_state)
		camera.position = original_camera_position
		camera.reset_smoothing()
		dive.set_process(original_dive_processing)
		return false
	var rendered_center := camera.get_screen_center_position()
	if not rendered_center.is_equal_approx(camera_position):
		push_error("PNG world snapshot viewport drifted from requested anchor. requested=%s actual=%s" % [camera_position, rendered_center])
		get_tree().quit(1)
		_restore_canvas_visibility(scene_visibility_state)
		_restore_diver_visuals(diver_visibility_state)
		camera.position = original_camera_position
		camera.reset_smoothing()
		dive.set_process(original_dive_processing)
		return false
	var saved := _save_snapshot(file_name)
	_restore_canvas_visibility(scene_visibility_state)
	_restore_diver_visuals(diver_visibility_state)
	camera.position = original_camera_position
	camera.reset_smoothing()
	dive.set_process(original_dive_processing)
	return saved


func _capture_r1_visibility_qa(dive) -> bool:
	var visibility_cases := _load_r1_visibility_cases()
	if visibility_cases.size() != R1_VISIBILITY_EXPECTED_CASE_COUNT:
		push_error(
			"R1 visibility QA requires exactly %d manifest cases, got %d."
			% [R1_VISIBILITY_EXPECTED_CASE_COUNT, visibility_cases.size()]
		)
		get_tree().quit(1)
		return false
	var r1_art_cells := dive.dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/R1ArtCells") as CanvasItem
	if r1_art_cells == null:
		push_error("R1 visibility QA requires RuntimeDynamic/VisualLayers/R1ArtCells.")
		get_tree().quit(1)
		return false
	var camera := dive.diver.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		push_error("R1 visibility QA requires the production diver Camera2D.")
		get_tree().quit(1)
		return false
	var original_diver_global_position: Vector2 = dive.diver.global_position
	var original_camera_position := camera.position

	var normalized_cases: Array = []
	var seen_ids := {}
	for case_index in range(visibility_cases.size()):
		var normalized_case := _normalize_r1_visibility_case(visibility_cases[case_index], case_index)
		if normalized_case.is_empty():
			get_tree().quit(1)
			return false
		var case_id := str(normalized_case.get("id", ""))
		if seen_ids.has(case_id):
			push_error("R1 visibility QA case id is duplicated: " + case_id)
			get_tree().quit(1)
			return false
		seen_ids[case_id] = true
		normalized_cases.append(normalized_case)

	# Configure the production profile once, then keep the particle field visible
	# but frozen across all A/B variants. Reapplying the quality setters for every
	# frame would restart the GPU emitters and randomize their initial field even
	# when speed_scale is immediately forced back to zero.
	dive.set_graphics_quality("high")
	dive.set_reduced_motion(false)
	var particle_speed_state := _freeze_particle_visuals(dive)
	var failed_case_summaries: Array[String] = []
	for normalized_case_variant in normalized_cases:
		var normalized_case: Dictionary = normalized_case_variant
		var case_id := str(normalized_case.get("id", ""))
		var camera_position: Vector2 = normalized_case.get("camera", Vector2.ZERO)
		var screen_roi: Rect2i = normalized_case.get("screen_roi", Rect2i())
		var artifact_id := _r1_visibility_artifact_id(case_id)
		if artifact_id.is_empty():
			push_error("R1 visibility QA case has an unsupported artifact id: " + case_id)
			get_tree().quit(1)
			_restore_particle_visuals(particle_speed_state)
			return false
		var file_stem := "world_png_r1_visibility_%s" % artifact_id
		var file_names := {
			"clean": file_stem + "_clean.png",
			"clean_no_r1": file_stem + "_clean_no_r1.png",
			"gameplay": file_stem + "_gameplay.png",
			"gameplay_no_r1": file_stem + "_gameplay_no_r1.png",
			"gameplay_no_r1_repeat": file_stem + "_gameplay_no_r1_repeat.png",
			"heatmap": file_stem + "_heatmap.png",
		}
		# Each A/B render uses the same production camera, fixed visual time and
		# hidden HUD/diver. Clean keeps only WaterBackground plus R1; gameplay keeps
		# every production layer and changes only R1ArtCells visibility.
		var capture_variants := [
			{"key": "clean", "isolate": true, "hide_r1": false},
			{"key": "clean_no_r1", "isolate": true, "hide_r1": true},
			{"key": "gameplay", "isolate": false, "hide_r1": false},
			{"key": "gameplay_no_r1", "isolate": false, "hide_r1": true},
			{"key": "gameplay_no_r1_repeat", "isolate": false, "hide_r1": true},
		]
		for capture_variant in capture_variants:
			var capture_key := str(capture_variant.get("key", ""))
			var captured := await _capture_anchored_world_snapshot(
				dive,
				camera_position,
				str(file_names.get(capture_key, "")),
				"high",
				false,
				true,
				4.0,
				bool(capture_variant.get("isolate", false)),
				true,
				bool(capture_variant.get("hide_r1", false)),
				particle_speed_state,
				false
			)
			# _capture_anchored_world_snapshot restores the Camera2D local offset;
			# restoring its parent anchor as well makes every A/B input identical and
			# prevents the QA pass from leaking a camera/diver position to later tests.
			dive.diver.global_position = original_diver_global_position
			camera.position = original_camera_position
			camera.reset_smoothing()
			if not captured:
				_restore_particle_visuals(particle_speed_state)
				return false
			if capture_key == "clean" and not _verify_r1_visibility_streaming(dive, case_id):
				_restore_particle_visuals(particle_speed_state)
				return false

		var clean_image := _load_snapshot_image(str(file_names.get("clean", "")))
		var clean_no_r1_image := _load_snapshot_image(str(file_names.get("clean_no_r1", "")))
		var gameplay_image := _load_snapshot_image(str(file_names.get("gameplay", "")))
		var gameplay_no_r1_image := _load_snapshot_image(str(file_names.get("gameplay_no_r1", "")))
		var gameplay_no_r1_repeat_image := _load_snapshot_image(str(file_names.get("gameplay_no_r1_repeat", "")))
		if clean_image.is_empty() or clean_no_r1_image.is_empty() or gameplay_image.is_empty() or gameplay_no_r1_image.is_empty() or gameplay_no_r1_repeat_image.is_empty():
			push_error("R1 visibility QA could not reload all A/B frames for " + case_id)
			get_tree().quit(1)
			_restore_particle_visuals(particle_speed_state)
			return false
		var evaluation := _evaluate_r1_visibility_case(
			case_id,
			screen_roi,
			clean_image,
			clean_no_r1_image,
			gameplay_image,
			gameplay_no_r1_image,
			gameplay_no_r1_repeat_image
		)
		if not bool(evaluation.get("valid", false)):
			push_error(str(evaluation.get("error", "R1 visibility QA image validation failed.")))
			get_tree().quit(1)
			_restore_particle_visuals(particle_speed_state)
			return false
		var heatmap := evaluation.get("heatmap") as Image
		if heatmap == null or not _save_snapshot_image(heatmap, str(file_names.get("heatmap", ""))):
			_restore_particle_visuals(particle_speed_state)
			return false
		var summary := str(evaluation.get("summary", ""))
		if bool(evaluation.get("passed", false)):
			print("R1 visibility QA %s PASS: %s" % [case_id, summary])
		else:
			failed_case_summaries.append("%s: %s" % [case_id, summary])

	if not failed_case_summaries.is_empty():
		for failed_summary in failed_case_summaries:
			push_error("R1 visibility QA FAIL " + failed_summary)
		get_tree().quit(1)
		_restore_particle_visuals(particle_speed_state)
		return false
	_restore_particle_visuals(particle_speed_state)
	return true


func _load_r1_visibility_cases() -> Array:
	var manifest_file := FileAccess.open(R1_ART_CELL_LIBRARY_PATH, FileAccess.READ)
	if manifest_file == null:
		push_error(
			"Could not open R1 ArtCell manifest for visibility QA. Error: %d"
			% FileAccess.get_open_error()
		)
		return []
	var parsed_manifest: Variant = JSON.parse_string(manifest_file.get_as_text())
	if not parsed_manifest is Dictionary:
		push_error("R1 ArtCell visibility QA manifest is not a JSON object.")
		return []
	var manifest: Dictionary = parsed_manifest
	var cases_variant: Variant = manifest.get("qa_visibility_cases", null)
	if not cases_variant is Array:
		push_error("R1 ArtCell manifest is missing top-level qa_visibility_cases.")
		return []
	return cases_variant


func _normalize_r1_visibility_case(case_variant: Variant, case_index: int) -> Dictionary:
	if not case_variant is Dictionary:
		push_error("R1 visibility QA case %d is not an object." % case_index)
		return {}
	var case_data: Dictionary = case_variant
	var case_id := str(case_data.get("id", "")).strip_edges()
	var camera_variant: Variant = case_data.get("camera", null)
	var roi_variant: Variant = case_data.get("screen_roi", null)
	if case_id.is_empty():
		push_error("R1 visibility QA case %d has no id." % case_index)
		return {}
	if not _is_numeric_array(camera_variant, 2):
		push_error("R1 visibility QA case %s camera must contain two numbers." % case_id)
		return {}
	if not _is_numeric_array(roi_variant, 4):
		push_error("R1 visibility QA case %s screen_roi must contain four numbers." % case_id)
		return {}
	var camera_values: Array = camera_variant
	var roi_values: Array = roi_variant
	var screen_roi := Rect2i(
		int(roi_values[0]),
		int(roi_values[1]),
		int(roi_values[2]),
		int(roi_values[3])
	)
	if screen_roi.size.x <= 0 or screen_roi.size.y <= 0:
		push_error("R1 visibility QA case %s screen_roi must have positive size." % case_id)
		return {}
	return {
		"id": case_id,
		"camera": Vector2(float(camera_values[0]), float(camera_values[1])),
		"screen_roi": screen_roi,
	}


func _is_numeric_array(value: Variant, expected_size: int) -> bool:
	if not value is Array:
		return false
	var values: Array = value
	if values.size() != expected_size:
		return false
	for item in values:
		if typeof(item) != TYPE_INT and typeof(item) != TYPE_FLOAT:
			return false
	return true


func _load_snapshot_image(file_name: String) -> Image:
	var output_directory := ProjectSettings.globalize_path("res://tmp")
	return Image.load_from_file(output_directory.path_join(file_name))


func _r1_visibility_artifact_id(case_id: String) -> String:
	const PREFIX := "Background_"
	if not case_id.begins_with(PREFIX):
		return ""
	var artifact_id := case_id.trim_prefix(PREFIX)
	if artifact_id.length() != 3 or not artifact_id.is_valid_int():
		return ""
	return artifact_id


func _verify_r1_visibility_streaming(dive, case_id: String) -> bool:
	var streamer: Node = dive.dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/VisualChunkStreamer")
	if streamer == null:
		push_error("R1 visibility QA requires VisualChunkStreamer for " + case_id)
		get_tree().quit(1)
		return false
	var desired: Array[String] = streamer.desired_chunk_keys()
	var loaded: Array[String] = streamer.loaded_chunk_keys()
	var desired_r1: Array[String] = []
	var loaded_r1: Array[String] = []
	for chunk_key in desired:
		if chunk_key.begins_with("r1_art_cells:"):
			desired_r1.append(chunk_key)
	for chunk_key in loaded:
		if chunk_key.begins_with("r1_art_cells:"):
			loaded_r1.append(chunk_key)
	var missing_r1: Array[String] = []
	for chunk_key in desired_r1:
		if not loaded_r1.has(chunk_key):
			missing_r1.append(chunk_key)
	if desired_r1.is_empty() or loaded_r1.is_empty() or not missing_r1.is_empty():
		push_error(
			"R1 visibility QA streaming is incomplete for %s. desired=%s loaded=%s missing=%s"
			% [case_id, desired_r1, loaded_r1, missing_r1]
		)
		get_tree().quit(1)
		return false
	return true


func _evaluate_r1_visibility_case(
	case_id: String,
	screen_roi: Rect2i,
	clean_image: Image,
	clean_no_r1_image: Image,
	gameplay_image: Image,
	gameplay_no_r1_image: Image,
	gameplay_no_r1_repeat_image: Image
) -> Dictionary:
	var image_size := clean_image.get_size()
	if clean_no_r1_image.get_size() != image_size or gameplay_image.get_size() != image_size or gameplay_no_r1_image.get_size() != image_size or gameplay_no_r1_repeat_image.get_size() != image_size:
		return {"valid": false, "error": "R1 visibility QA A/B image sizes differ for " + case_id}
	if screen_roi.position.x < 0 or screen_roi.position.y < 0 or screen_roi.end.x > image_size.x or screen_roi.end.y > image_size.y:
		return {
			"valid": false,
			"error": "R1 visibility QA screen_roi is outside the rendered image for %s. roi=%s image=%s"
			% [case_id, screen_roi, image_size],
		}
	if screen_roi.size.x % R1_VISIBILITY_DETAIL_DOWNSAMPLE != 0 or screen_roi.size.y % R1_VISIBILITY_DETAIL_DOWNSAMPLE != 0:
		return {
			"valid": false,
			"error": "R1 visibility QA screen_roi must align to 4x4 detail blocks for %s. roi=%s"
			% [case_id, screen_roi],
		}

	var pixel_count := screen_roi.size.x * screen_roi.size.y
	var clean_delta_field := PackedFloat32Array()
	var gameplay_delta_field := PackedFloat32Array()
	clean_delta_field.resize(pixel_count)
	gameplay_delta_field.resize(pixel_count)
	var clean_signal_count := 0
	var gameplay_signal_count := 0
	var jitter_squared_sum := 0.0
	var jitter_pixel_count := 0
	var field_index := 0
	for y in range(screen_roi.position.y, screen_roi.end.y):
		for x in range(screen_roi.position.x, screen_roi.end.x):
			var clean_pixel := clean_image.get_pixel(x, y)
			var clean_no_r1_pixel := clean_no_r1_image.get_pixel(x, y)
			var gameplay_pixel := gameplay_image.get_pixel(x, y)
			var gameplay_no_r1_pixel := gameplay_no_r1_image.get_pixel(x, y)
			var gameplay_no_r1_repeat_pixel := gameplay_no_r1_repeat_image.get_pixel(x, y)
			var clean_delta := _maximum_rgb_delta(clean_pixel, clean_no_r1_pixel)
			var gameplay_delta := _maximum_rgb_delta(gameplay_pixel, gameplay_no_r1_pixel)
			var jitter_delta := _maximum_rgb_delta(gameplay_no_r1_pixel, gameplay_no_r1_repeat_pixel)
			clean_delta_field[field_index] = clean_delta
			gameplay_delta_field[field_index] = gameplay_delta
			if clean_delta >= R1_VISIBILITY_DELTA_THRESHOLD:
				clean_signal_count += 1
			if gameplay_delta >= R1_VISIBILITY_DELTA_THRESHOLD:
				gameplay_signal_count += 1
			jitter_squared_sum += jitter_delta * jitter_delta
			if jitter_delta > R1_VISIBILITY_JITTER_DELTA_THRESHOLD:
				jitter_pixel_count += 1
			field_index += 1

	var clean_detail_mask := _build_r1_screen_detail_mask(
		clean_image,
		screen_roi,
		clean_delta_field
	)
	if clean_detail_mask.size() != pixel_count:
		return {
			"valid": false,
			"error": "R1 visibility QA could not build the 4x4 clean detail mask for " + case_id,
		}
	var heatmap: Image = gameplay_image.duplicate()
	var bin_structured_counts := PackedInt32Array()
	bin_structured_counts.resize(R1_VISIBILITY_BIN_COUNT)
	var clean_detail_count := 0
	var surviving_detail_count := 0
	field_index = 0
	for local_y in range(screen_roi.size.y):
		for local_x in range(screen_roi.size.x):
			var x := screen_roi.position.x + local_x
			var y := screen_roi.position.y + local_y
			var clean_delta := clean_delta_field[field_index]
			var gameplay_delta := gameplay_delta_field[field_index]
			var is_clean_detail := clean_detail_mask[field_index] != 0
			var survival_ratio := gameplay_delta / maxf(clean_delta, 0.000001)
			var has_absolute_survival := gameplay_delta >= R1_VISIBILITY_DELTA_THRESHOLD
			var has_required_survival_ratio := survival_ratio >= R1_VISIBILITY_MIN_SURVIVAL_RATIO
			var is_surviving_detail := (
				is_clean_detail
				and has_absolute_survival
				and has_required_survival_ratio
			)
			if is_clean_detail:
				clean_detail_count += 1
			if is_surviving_detail:
				surviving_detail_count += 1
				var bin_index := mini(
					R1_VISIBILITY_BIN_COUNT - 1,
					floori(float(local_x * R1_VISIBILITY_BIN_COUNT) / float(screen_roi.size.x))
				)
				bin_structured_counts[bin_index] += 1
			var base_color := gameplay_image.get_pixel(x, y)
			var dim_color := Color(base_color.r * 0.18, base_color.g * 0.18, base_color.b * 0.18, 1.0)
			var marker_color := dim_color
			if clean_delta >= R1_VISIBILITY_DELTA_THRESHOLD and not is_clean_detail:
				marker_color = Color(0.05, 0.35, 1.0, 1.0)
			elif is_surviving_detail:
				marker_color = Color(0.05, 1.0, 0.2, 1.0)
			elif is_clean_detail and has_absolute_survival:
				marker_color = Color(1.0, 0.65, 0.05, 1.0)
			elif is_clean_detail and has_required_survival_ratio:
				marker_color = Color(1.0, 0.95, 0.05, 1.0)
			elif is_clean_detail:
				marker_color = Color(1.0, 0.05, 0.05, 1.0)
			heatmap.set_pixel(x, y, dim_color.lerp(marker_color, 0.86))
			field_index += 1

	var active_bin_count := 0
	for bin_index in range(R1_VISIBILITY_BIN_COUNT):
		var bin_start_x := floori(float(bin_index * screen_roi.size.x) / float(R1_VISIBILITY_BIN_COUNT))
		var bin_end_x := floori(float((bin_index + 1) * screen_roi.size.x) / float(R1_VISIBILITY_BIN_COUNT))
		var bin_pixel_count := maxi((bin_end_x - bin_start_x) * screen_roi.size.y, 1)
		var required_bin_pixels := maxi(
			ceili(float(bin_pixel_count) * R1_VISIBILITY_MIN_BIN_STRUCTURED_RATIO),
			1
		)
		if bin_structured_counts[bin_index] >= required_bin_pixels:
			active_bin_count += 1

	var clean_signal_ratio := float(clean_signal_count) / maxf(float(pixel_count), 1.0)
	var gameplay_signal_ratio := float(gameplay_signal_count) / maxf(float(pixel_count), 1.0)
	var structured_survival_ratio := float(surviving_detail_count) / maxf(float(pixel_count), 1.0)
	var detail_survival_share := float(surviving_detail_count) / maxf(float(clean_detail_count), 1.0)
	var jitter_rms := sqrt(jitter_squared_sum / maxf(float(pixel_count), 1.0))
	var jitter_pixel_ratio := float(jitter_pixel_count) / maxf(float(pixel_count), 1.0)
	var jitter_passed := (
		jitter_rms <= R1_VISIBILITY_MAX_JITTER_RMS
		and jitter_pixel_ratio <= R1_VISIBILITY_MAX_JITTER_PIXEL_RATIO
	)
	var passed := (
		gameplay_signal_ratio >= R1_VISIBILITY_MIN_SIGNAL_RATIO
		and structured_survival_ratio >= R1_VISIBILITY_MIN_STRUCTURED_RATIO
		and detail_survival_share >= R1_VISIBILITY_MIN_DETAIL_SURVIVAL_SHARE
		and active_bin_count >= R1_VISIBILITY_MIN_ACTIVE_BINS
		and jitter_passed
	)
	var summary := (
		"gameplay_signal=%.2f%%/15%% clean_signal=%.2f%% structured=%.2f%%/1%% detail_survival=%.2f%%/25%% bins=%d/%d (need %d) detail_pixels=%d jitter_rms=%.4f/%.4f jitter_pixels=%.3f%%/%.3f%%"
		% [
			gameplay_signal_ratio * 100.0,
			clean_signal_ratio * 100.0,
			structured_survival_ratio * 100.0,
			detail_survival_share * 100.0,
			active_bin_count,
			R1_VISIBILITY_BIN_COUNT,
			R1_VISIBILITY_MIN_ACTIVE_BINS,
			clean_detail_count,
			jitter_rms,
			R1_VISIBILITY_MAX_JITTER_RMS,
			jitter_pixel_ratio * 100.0,
			R1_VISIBILITY_MAX_JITTER_PIXEL_RATIO * 100.0,
		]
	)
	return {
		"valid": true,
		"passed": passed,
		"summary": summary,
		"heatmap": heatmap,
	}


func _build_r1_screen_detail_mask(
	clean_image: Image,
	screen_roi: Rect2i,
	clean_delta_field: PackedFloat32Array
) -> PackedByteArray:
	var pixel_count := screen_roi.size.x * screen_roi.size.y
	var detail_mask := PackedByteArray()
	if clean_delta_field.size() != pixel_count:
		return detail_mask
	var normalized := clean_image.duplicate() as Image
	normalized.convert(Image.FORMAT_RGB8)
	var source_data := normalized.get_data()
	var image_width := normalized.get_width()
	var downsampled_width := floori(
		float(screen_roi.size.x) / float(R1_VISIBILITY_DETAIL_DOWNSAMPLE)
	)
	var downsampled_height := floori(
		float(screen_roi.size.y) / float(R1_VISIBILITY_DETAIL_DOWNSAMPLE)
	)
	if downsampled_width < 2 or downsampled_height < 2:
		return detail_mask
	var downsampled_luma := PackedByteArray()
	downsampled_luma.resize(downsampled_width * downsampled_height)
	for output_y in range(downsampled_height):
		for output_x in range(downsampled_width):
			var red_sum := 0
			var green_sum := 0
			var blue_sum := 0
			for block_y in range(R1_VISIBILITY_DETAIL_DOWNSAMPLE):
				var source_offset := (
					(
						screen_roi.position.y
						+ output_y * R1_VISIBILITY_DETAIL_DOWNSAMPLE
						+ block_y
					) * image_width
					+ screen_roi.position.x
					+ output_x * R1_VISIBILITY_DETAIL_DOWNSAMPLE
				) * 3
				for _block_x in range(R1_VISIBILITY_DETAIL_DOWNSAMPLE):
					red_sum += int(source_data[source_offset])
					green_sum += int(source_data[source_offset + 1])
					blue_sum += int(source_data[source_offset + 2])
					source_offset += 3
			var weighted_sum := 299 * red_sum + 587 * green_sum + 114 * blue_sum
			downsampled_luma[output_y * downsampled_width + output_x] = clampi(
				int(float(weighted_sum + 8000) / 16000.0),
				0,
				255
			)

	detail_mask.resize(pixel_count)
	for block_y in range(downsampled_height - 1):
		for block_x in range(downsampled_width - 1):
			var block_index := block_y * downsampled_width + block_x
			var gradient := maxi(
				absi(int(downsampled_luma[block_index + 1]) - int(downsampled_luma[block_index])),
				absi(int(downsampled_luma[block_index + downsampled_width]) - int(downsampled_luma[block_index]))
			)
			if gradient < R1_VISIBILITY_DETAIL_GRADIENT_THRESHOLD:
				continue
			for pixel_y in range(R1_VISIBILITY_DETAIL_DOWNSAMPLE):
				for pixel_x in range(R1_VISIBILITY_DETAIL_DOWNSAMPLE):
					var local_x := block_x * R1_VISIBILITY_DETAIL_DOWNSAMPLE + pixel_x
					var local_y := block_y * R1_VISIBILITY_DETAIL_DOWNSAMPLE + pixel_y
					var field_index := local_y * screen_roi.size.x + local_x
					if clean_delta_field[field_index] >= R1_VISIBILITY_DELTA_THRESHOLD:
						detail_mask[field_index] = 1
	return detail_mask


func _maximum_rgb_delta(left: Color, right: Color) -> float:
	return maxf(absf(left.r - right.r), maxf(absf(left.g - right.g), absf(left.b - right.b)))


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


func _hide_diver_visuals(dive) -> Dictionary:
	var visibility_state := {}
	for node_path in ["AnimatedSprite2D", "VisualEffects", "DiveLight", "LanternCone"]:
		var visual := dive.diver.get_node_or_null(node_path) as CanvasItem
		if visual == null:
			continue
		visibility_state[visual] = visual.visible
		visual.visible = false
	return visibility_state


func _restore_diver_visuals(visibility_state: Dictionary) -> void:
	for visual_variant in visibility_state.keys():
		var visual := visual_variant as CanvasItem
		if visual != null and is_instance_valid(visual):
			visual.visible = bool(visibility_state[visual_variant])


func _isolate_r1_art_cell_visuals(dive) -> Dictionary:
	var visibility_state := {}
	var runtime_dynamic: Node = dive.dive_map.get_node_or_null("RuntimeDynamic")
	var visual_layers: Node = dive.dive_map.get_node_or_null("RuntimeDynamic/VisualLayers")
	if runtime_dynamic != null:
		for child_variant in runtime_dynamic.get_children():
			var child := child_variant as CanvasItem
			if child == null or child == visual_layers:
				continue
			_store_canvas_visibility(child, false, visibility_state)
	if visual_layers != null:
		for child_variant in visual_layers.get_children():
			var child := child_variant as CanvasItem
			if child == null or child.name in [&"R1ArtCells", &"VisualChunkStreamer", &"TerrainRenderer"]:
				continue
			_store_canvas_visibility(child, false, visibility_state)
	var terrain_renderer: Node = dive.dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/TerrainRenderer")
	if terrain_renderer != null:
		for child_variant in terrain_renderer.get_children():
			var child := child_variant as CanvasItem
			if child == null or child.name == &"WaterBackground":
				continue
			_store_canvas_visibility(child, false, visibility_state)
	var hud := dive.get_node_or_null("DiveHUD") as CanvasLayer
	if hud != null:
		visibility_state[hud] = hud.visible
		hud.visible = false
	return visibility_state


func _hide_dive_hud(dive, visibility_state: Dictionary) -> void:
	var hud := dive.get_node_or_null("DiveHUD") as CanvasLayer
	if hud == null:
		return
	if not visibility_state.has(hud):
		visibility_state[hud] = hud.visible
	hud.visible = false


func _hide_r1_art_cells(dive, visibility_state: Dictionary) -> void:
	var r1_art_cells := dive.dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/R1ArtCells") as CanvasItem
	if r1_art_cells != null:
		_store_canvas_visibility(r1_art_cells, false, visibility_state)


func _freeze_particle_visuals(root: Node) -> Dictionary:
	var speed_state := {}
	_enforce_particle_visuals_frozen(root, speed_state)
	return speed_state


func _enforce_particle_visuals_frozen(root: Node, speed_state: Dictionary) -> void:
	var particles: Array[Node] = []
	particles.append_array(root.find_children("*", "GPUParticles2D", true, false))
	particles.append_array(root.find_children("*", "CPUParticles2D", true, false))
	for particle in particles:
		if not speed_state.has(particle):
			speed_state[particle] = float(particle.get("speed_scale"))
		particle.set("speed_scale", 0.0)


func _restore_particle_visuals(speed_state: Dictionary) -> void:
	for particle_variant in speed_state.keys():
		var particle := particle_variant as Node
		if particle != null and is_instance_valid(particle):
			particle.set("speed_scale", float(speed_state[particle_variant]))


func _store_canvas_visibility(item: CanvasItem, visible: bool, visibility_state: Dictionary) -> void:
	if not visibility_state.has(item):
		visibility_state[item] = item.visible
	item.visible = visible


func _restore_canvas_visibility(visibility_state: Dictionary) -> void:
	for item_variant in visibility_state.keys():
		var item := item_variant as CanvasItem
		if item != null and is_instance_valid(item):
			item.visible = bool(visibility_state[item_variant])
			continue
		var canvas_layer := item_variant as CanvasLayer
		if canvas_layer != null and is_instance_valid(canvas_layer):
			canvas_layer.visible = bool(visibility_state[item_variant])


func _settle_visual_chunks(dive) -> void:
	var streamer: Node = dive.dive_map.get_node_or_null("RuntimeDynamic/VisualLayers/VisualChunkStreamer")
	if streamer == null:
		return
	for _frame in range(180):
		var pending: Array[String] = streamer.pending_chunk_keys()
		var desired: Array[String] = streamer.desired_chunk_keys()
		var loaded: Array[String] = streamer.loaded_chunk_keys()
		var all_desired_loaded := true
		for desired_key in desired:
			if not loaded.has(desired_key):
				all_desired_loaded = false
				break
		if pending.is_empty() and all_desired_loaded:
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
	return _save_snapshot_image(image, file_name)


func _save_snapshot_image(image: Image, file_name: String) -> bool:
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
