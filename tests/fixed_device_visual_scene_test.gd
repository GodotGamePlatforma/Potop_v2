extends SceneTree

const VISUAL_SCENES := [
	"res://scenes/diving/map_visuals/JunctionJ7Visual.tscn",
	"res://scenes/diving/map_visuals/ArchiveTerminalVisual.tscn",
	"res://scenes/diving/map_visuals/R3DiagnosticPanelVisual.tscn",
	"res://scenes/diving/map_visuals/R3GeneratorVisual.tscn",
	"res://scenes/diving/map_visuals/C4SwitchboardVisual.tscn",
	"res://scenes/diving/map_visuals/C4SplitterMountVisual.tscn",
]

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var kinds := {}
	for scene_path in VISUAL_SCENES:
		var packed := load(scene_path) as PackedScene
		_assert(packed != null, "Prefab urządzenia musi się wczytywać: %s." % scene_path)
		if packed == null:
			continue
		var instance := packed.instantiate()
		_assert(instance is Node2D, "Prefab urządzenia musi mieć root Node2D: %s." % scene_path)
		_assert(instance.find_children("*", "CollisionObject2D", true, false).is_empty(), "Prefab urządzenia nie może wnosić fizyki: %s." % scene_path)
		_assert(instance.find_children("*", "CollisionShape2D", true, false).is_empty(), "Prefab urządzenia nie może wnosić kształtu kolizji: %s." % scene_path)
		var kind := str(instance.get("device_kind"))
		_assert(not kind.is_empty() and not kinds.has(kind), "Każde urządzenie musi mieć odrębną sylwetkę: %s." % scene_path)
		kinds[kind] = true
		instance.free()
	_assert(kinds.size() == 6, "Galeria Wspólnej Linii musi zawierać sześć odrębnych urządzeń.")
	if _failed:
		quit(1)
		return
	print("Fixed device visual scene test passed: six distinct presentation-only prefabs load without collisions.")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Fixed device visual scene test failed: " + message)
