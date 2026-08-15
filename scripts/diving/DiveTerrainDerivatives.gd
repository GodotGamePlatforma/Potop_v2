class_name DiveTerrainDerivatives
extends RefCounted

## Builds and validates committed caches derived from the Polygon2D macroterrain.
## The PNG is retained for shaders/import and the SDF remains presentation-only;
## neither file is allowed to override the scene geometry.

const MacroTerrainRasterScript := preload("res://scripts/diving/MacroTerrainRaster.gd")

const NAVIGATION_PNG_PATH := "res://assets/diving/world/map_v2/world_collision_grid.png"
const NAVIGATION_MANIFEST_PATH := "res://assets/diving/world/map_v2/world_collision_grid.json"
const SDF_PNG_PATH := "res://assets/diving/world/map_v2/world_collision_render_sdf_v1.png"
const SDF_MANIFEST_PATH := "res://assets/diving/world/map_v2/world_collision_render_sdf_v1.json"
const SDF_BUILDER_PATH := "res://tools/build_dive_terrain_sdf.py"
const AUTHORITY_SCENE_PATH := "res://scenes/diving/UnderwaterMap.tscn"
const AUTHORITY_NODE_PATH := "Terrain/TerrainNavigation"
const GENERATOR_VERSION := 1
const NAVIGATION_SEMANTIC_CONTRACT := "polygon_scene_default_blocked_open_then_islands"
const SDF_GENERATOR := "tools/build_dive_terrain_sdf.py"
const SDF_GENERATOR_VERSION := 1
const SDF_BLOCKED_THRESHOLD := 128
const SDF_SPREAD_TEXELS := 12.0
const SDF_SMOOTH_RADIUS_TEXELS := 1.75
const SDF_SEMANTIC_CONTRACT := "derived_bright_blocked_dark_traversable"


static func rasterize_map(map_root: Node) -> Dictionary:
	if map_root == null:
		return {"errors": PackedStringArray(["Nie można zbudować pochodnych pustej mapy."])}
	var terrain_navigation := map_root.get_node_or_null(AUTHORITY_NODE_PATH) as Node2D
	var world_size: Vector2 = map_root.get("world_size")
	return MacroTerrainRasterScript.rasterize(terrain_navigation, world_size, map_root as Node2D)


static func rebuild(map_root: Node) -> Dictionary:
	var raster := rasterize_map(map_root)
	var errors: PackedStringArray = raster.get("errors", PackedStringArray())
	if not errors.is_empty():
		return {"errors": errors, "raster": raster, "navigation_changed": false}

	var width := int(raster.get("width", 0))
	var height := int(raster.get("height", 0))
	var authority_cells: PackedByteArray = raster.get("cells", PackedByteArray())
	var current_image := Image.load_from_file(ProjectSettings.globalize_path(NAVIGATION_PNG_PATH))
	var navigation_changed := not _image_matches_cells(current_image, authority_cells, width, height)
	if navigation_changed:
		var image := _image_from_cells(authority_cells, width, height)
		var save_error := image.save_png(ProjectSettings.globalize_path(NAVIGATION_PNG_PATH))
		if save_error != OK:
			errors.append("Nie można zapisać pochodnego rastra nawigacji: %s." % error_string(save_error))
			return {"errors": errors, "raster": raster, "navigation_changed": false}
	var navigation_output_hash := FileAccess.get_sha256(NAVIGATION_PNG_PATH).to_lower()
	map_root.set("navigation_cells_sha256", str(raster.get("cells_hash", "")))
	map_root.set("navigation_signature_sha256", navigation_output_hash)

	var manifest_error := _write_navigation_manifest(map_root, raster)
	if not manifest_error.is_empty():
		errors.append(manifest_error)
		return {"errors": errors, "raster": raster, "navigation_changed": navigation_changed}

	if navigation_changed or _sdf_needs_rebuild():
		var sdf_result := _rebuild_sdf()
		var sdf_errors: PackedStringArray = sdf_result.get("errors", PackedStringArray())
		for sdf_error in sdf_errors:
			errors.append(sdf_error)
	if errors.is_empty():
		for validation_error in validate_derivatives(map_root, raster, true):
			errors.append(validation_error)
	return {
		"errors": errors,
		"raster": raster,
		"navigation_changed": navigation_changed,
	}


static func validate_derivatives(
	map_root: Node,
	raster: Dictionary = {},
	verify_semantic_pixels: bool = false
) -> PackedStringArray:
	var errors := PackedStringArray()
	var effective_raster := raster
	if effective_raster.is_empty():
		effective_raster = rasterize_map(map_root)
	var raster_errors: PackedStringArray = effective_raster.get("errors", PackedStringArray())
	for raster_error in raster_errors:
		errors.append(raster_error)
	if not raster_errors.is_empty():
		return errors

	var manifest_variant = JSON.parse_string(FileAccess.get_file_as_string(NAVIGATION_MANIFEST_PATH))
	if not (manifest_variant is Dictionary):
		errors.append("Pochodny raster nawigacji wymaga poprawnego manifestu JSON.")
		return errors
	var manifest: Dictionary = manifest_variant
	var width := int(effective_raster.get("width", 0))
	var height := int(effective_raster.get("height", 0))
	var cells: PackedByteArray = effective_raster.get("cells", PackedByteArray())
	var cells_hash := str(effective_raster.get("cells_hash", ""))
	var world_size: Vector2 = map_root.get("world_size")
	var expected := {
		"authority_path": AUTHORITY_SCENE_PATH,
		"authority_node_path": AUTHORITY_NODE_PATH,
		"generator": "scripts/diving/DiveTerrainDerivatives.gd",
		"generator_version": GENERATOR_VERSION,
		"width": width,
		"height": height,
		"grid_step": MacroTerrainRasterScript.GRID_STEP,
		"geometry_sha256": str(effective_raster.get("geometry_hash", "")),
		"cells_sha256": cells_hash,
		"output_path": NAVIGATION_PNG_PATH,
		"semantic_contract": NAVIGATION_SEMANTIC_CONTRACT,
		"world_height": world_size.y,
		"world_width": world_size.x,
	}
	for key in expected:
		if manifest.get(key) != expected[key]:
			errors.append("Manifest rastra nawigacji ma nieaktualne pole %s." % key)
	if not FileAccess.file_exists(NAVIGATION_PNG_PATH):
		errors.append("Brakuje pochodnego rastra nawigacji PNG.")
	else:
		var png_hash := FileAccess.get_sha256(NAVIGATION_PNG_PATH).to_lower()
		if str(manifest.get("output_sha256", "")).to_lower() != png_hash:
			errors.append("Pochodny raster nawigacji PNG nie odpowiada manifestowi.")
		if verify_semantic_pixels:
			var image := Image.load_from_file(ProjectSettings.globalize_path(NAVIGATION_PNG_PATH))
			if not _image_matches_cells(image, cells, width, height):
				errors.append("Pochodny raster nawigacji nie odpowiada komórkom scenowych Polygon2D.")
		if str(map_root.get("navigation_signature_sha256")).to_lower() != png_hash:
			errors.append("Scenowy skrót zgodności zapisu nie odpowiada pochodnemu PNG.")
	if str(map_root.get("navigation_cells_sha256")).to_lower() != cells_hash.to_lower():
		errors.append("Scenowy skrót komórek nie odpowiada makroterenowi Polygon2D.")

	_append_sdf_chain_errors(errors, width, height)
	return errors


static func _write_navigation_manifest(map_root: Node, raster: Dictionary) -> String:
	var world_size: Vector2 = map_root.get("world_size")
	var manifest := {
		"authority_node_path": AUTHORITY_NODE_PATH,
		"authority_path": AUTHORITY_SCENE_PATH,
		"cells_sha256": str(raster.get("cells_hash", "")),
		"generator": "scripts/diving/DiveTerrainDerivatives.gd",
		"generator_version": GENERATOR_VERSION,
		"geometry_sha256": str(raster.get("geometry_hash", "")),
		"grid_step": MacroTerrainRasterScript.GRID_STEP,
		"height": int(raster.get("height", 0)),
		"output_path": NAVIGATION_PNG_PATH,
		"output_sha256": FileAccess.get_sha256(NAVIGATION_PNG_PATH).to_lower(),
		"semantic_contract": NAVIGATION_SEMANTIC_CONTRACT,
		"width": int(raster.get("width", 0)),
		"world_height": world_size.y,
		"world_width": world_size.x,
	}
	var output := FileAccess.open(NAVIGATION_MANIFEST_PATH, FileAccess.WRITE)
	if output == null:
		return "Nie można zapisać manifestu pochodnego rastra nawigacji."
	output.store_string(JSON.stringify(manifest, "  ", true) + "\n")
	output.close()
	return ""


static func _append_sdf_chain_errors(errors: PackedStringArray, width: int, height: int) -> void:
	var manifest_variant = JSON.parse_string(FileAccess.get_file_as_string(SDF_MANIFEST_PATH))
	if not (manifest_variant is Dictionary):
		errors.append("Prezentacyjny SDF wymaga poprawnego manifestu JSON.")
		return
	var manifest: Dictionary = manifest_variant
	var source_hash := FileAccess.get_sha256(NAVIGATION_PNG_PATH).to_lower()
	var expected := _expected_sdf_manifest(width, height, source_hash)
	for key in expected:
		if manifest.get(key) != expected[key]:
			errors.append("Manifest SDF ma nieaktualne pole %s." % key)
	if not FileAccess.file_exists(SDF_PNG_PATH):
		errors.append("Brakuje prezentacyjnego SDF terenu.")
	elif str(manifest.get("output_sha256", "")).to_lower() != FileAccess.get_sha256(SDF_PNG_PATH).to_lower():
		errors.append("Prezentacyjny SDF nie odpowiada własnemu manifestowi.")


static func _sdf_needs_rebuild() -> bool:
	var manifest_variant = JSON.parse_string(FileAccess.get_file_as_string(SDF_MANIFEST_PATH))
	if not (manifest_variant is Dictionary):
		return true
	var manifest: Dictionary = manifest_variant
	var source_image := Image.load_from_file(ProjectSettings.globalize_path(NAVIGATION_PNG_PATH))
	if source_image == null or source_image.is_empty():
		return true
	var source_hash := FileAccess.get_sha256(NAVIGATION_PNG_PATH).to_lower()
	var expected := _expected_sdf_manifest(source_image.get_width(), source_image.get_height(), source_hash)
	for key in expected:
		if manifest.get(key) != expected[key]:
			return true
	return (
		not FileAccess.file_exists(SDF_PNG_PATH)
		or str(manifest.get("output_sha256", "")).to_lower() != FileAccess.get_sha256(SDF_PNG_PATH).to_lower()
	)


static func _expected_sdf_manifest(width: int, height: int, source_hash: String) -> Dictionary:
	return {
		"blocked_threshold": SDF_BLOCKED_THRESHOLD,
		"generator": SDF_GENERATOR,
		"generator_version": SDF_GENERATOR_VERSION,
		"height": height,
		"output_path": SDF_PNG_PATH,
		"semantic_contract": SDF_SEMANTIC_CONTRACT,
		"smooth_radius_texels": SDF_SMOOTH_RADIUS_TEXELS,
		"source_path": NAVIGATION_PNG_PATH,
		"source_sha256": source_hash,
		"spread_texels": SDF_SPREAD_TEXELS,
		"width": width,
	}


static func _rebuild_sdf() -> Dictionary:
	var script_path := ProjectSettings.globalize_path(SDF_BUILDER_PATH)
	var output: Array = []
	var exit_code := OS.execute("python", PackedStringArray([script_path]), output, true)
	if exit_code == -1:
		exit_code = OS.execute("py", PackedStringArray(["-3", script_path]), output, true)
	if exit_code != 0:
		return {"errors": PackedStringArray([
			"Generator SDF zakończył się kodem %d: %s" % [exit_code, "\n".join(output)],
		])}
	return {"errors": PackedStringArray(), "output": output}


static func _image_from_cells(cells: PackedByteArray, width: int, height: int) -> Image:
	var pixels := PackedByteArray()
	pixels.resize(cells.size())
	for index in range(cells.size()):
		pixels[index] = 0 if cells[index] == 1 else 255
	return Image.create_from_data(width, height, false, Image.FORMAT_L8, pixels)


static func _image_matches_cells(
	image: Image,
	cells: PackedByteArray,
	width: int,
	height: int
) -> bool:
	if image == null or image.is_empty() or image.get_width() != width or image.get_height() != height:
		return false
	if image.get_format() != Image.FORMAT_L8:
		image.convert(Image.FORMAT_L8)
	var pixels := image.get_data()
	if pixels.size() != cells.size():
		return false
	for index in range(cells.size()):
		if (pixels[index] <= 127) != (cells[index] == 1):
			return false
	return true
