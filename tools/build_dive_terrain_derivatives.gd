extends SceneTree

const MapSceneScript := preload("res://scripts/diving/UnderwaterMapScene.gd")
const DerivativesScript := preload("res://scripts/diving/DiveTerrainDerivatives.gd")
const MAP_SCENE_PATH := "res://scenes/diving/UnderwaterMap.tscn"


func _initialize() -> void:
	var scene := ResourceLoader.load(MAP_SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		_fail("Nie można załadować produkcyjnej sceny mapy.")
		return
	var map_root := scene.instantiate()
	if map_root == null or map_root.get_script() != MapSceneScript:
		if map_root != null:
			map_root.free()
		_fail("Produkcjna scena mapy nie używa UnderwaterMapScene.")
		return
	var check_only := OS.get_cmdline_user_args().has("--check")
	var errors: PackedStringArray
	if check_only:
		errors = DerivativesScript.validate_derivatives(map_root, {}, true)
	else:
		var result := DerivativesScript.rebuild(map_root)
		errors = result.get("errors", PackedStringArray())
	map_root.free()
	if not errors.is_empty():
		_fail("; ".join(errors))
		return
	print(
		"Pochodne makroterenu są %s i zgodne ze sceną Polygon2D." % [
			"aktualne" if check_only else "odbudowane",
		]
	)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
