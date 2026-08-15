extends SceneTree

const VisualStyle := preload("res://scripts/diving/DiveInteractableVisualStyle.gd")
const ContainerScript := preload("res://scripts/diving/DiveLootContainer.gd")
const PickupScript := preload("res://scripts/diving/DiveWorldPickup.gd")
const PersistentScript := preload("res://scripts/diving/DivePersistentInteractable.gd")
const RescueScript := preload("res://scripts/diving/DiveRescueSurvivor.gd")
const ExitLineScript := preload("res://scripts/diving/DiveExitLine.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_assert(VisualStyle.resolve_region("R3", {"region_id": "R2"}, "pickup_r2_food_01") == "R3", "Jawny region prezentacyjny musi mieć pierwszeństwo przed ID i geometrią.")
	_assert(VisualStyle.resolve_region("", {"region_id": "R2"}, "pickup_r3_planks_01") == "R3", "Stabilne ID R3 musi rozwiązać nakładającą się granicę regionów.")
	_assert(VisualStyle.resolve_region("", {}, "c4_switchboard") == "R4", "Urządzenia C-4 muszą korzystać z palety Czarnego Serca.")
	_assert(VisualStyle.quality_level("low") == 0 and VisualStyle.quality_level("medium") == 1 and VisualStyle.quality_level("high") == 2, "Profile jakości muszą mieć trzy deterministyczne poziomy detalu.")
	for region_id in ["R1", "R2", "R3", "R4"]:
		var colors := VisualStyle.palette(region_id)
		_assert(str(colors.get("region_id", "")) == region_id, "Każdy region musi mieć własną kompletną paletę.")

	var sprite := Sprite2D.new()
	VisualStyle.apply_sprite(sprite, "R3", "scrapyard_generator_r3", "high")
	var skin_material := sprite.material as ShaderMaterial
	_assert(skin_material != null and skin_material.shader != null, "Regionalny skin musi tworzyć materiał bez zmiany tekstury albo sylwetki.")
	_assert(skin_material != null and is_equal_approx(float(skin_material.get_shader_parameter("detail_level")), 2.0), "High musi przekazać pełny detal do statycznej patyny.")
	sprite.material = null
	sprite.free()
	for presenter_script in [ContainerScript, PickupScript, PersistentScript, RescueScript, ExitLineScript]:
		var presenter = presenter_script.new()
		_assert(presenter != null, "Każdy aktywny renderer interakcji musi się parsować i instancjonować.")
		presenter.free()

	if _failed:
		quit(1)
		return
	print("Interactable visual style test passed: regions, quality and presentation-only device skin work.")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Interactable visual style test failed: " + message)
