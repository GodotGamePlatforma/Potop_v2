extends SceneTree

const PortraitCatalogScript := preload("res://scripts/ui/PortraitCatalog.gd")
const SurvivorPortraitScript := preload("res://scripts/ui/SurvivorPortrait.gd")
const DiverHudPortraitScript := preload("res://scripts/diving/DiverHudPortrait.gd")
const DiveHudDockScript := preload("res://scripts/diving/DiveHudDock.gd")
const ExpeditionSetupScript := preload("res://scripts/data/ExpeditionSetup.gd")

const EXPECTED_PATHS := {
	"mira": "res://assets/ui/portraits/mira_boruta_portrait_v1.png",
	"anka": "res://assets/ui/portraits/anka_ryl_portrait_v1.png",
	"igor": "res://assets/ui/portraits/igor_sowa_portrait_v1.png",
	"klara": "res://assets/ui/portraits/klara_wysocka_portrait_v1.png",
	"zofia_kruk": "res://assets/ui/portraits/zofia_kruk_portrait_v1.png",
	"pawel_mazur": "res://assets/ui/portraits/pawel_mazur_portrait_v1.png",
	"leon": "res://assets/ui/portraits/leon_wrona_portrait_v1.png",
}
const EXPECTED_ASPECT_RATIO := 13.0 / 16.0
const ASPECT_RATIO_TOLERANCE := 0.02
const MAX_IMPORTED_DIMENSION := 512

var _failed := false


func _initialize() -> void:
	_test_explicit_catalog()
	_test_deterministic_fallback()
	_test_diver_portrait_api()
	_test_frozen_dive_snapshot_selection()
	if _failed:
		quit(1)
		return
	print("Portrait catalog test passed: six resident textures plus Klara, dimensions, aspect ratios, deterministic unknown-ID fallback and frozen dive portrait selection work.")
	quit(0)


func _test_explicit_catalog() -> void:
	_assert(PortraitCatalogScript.PORTRAIT_PATHS.size() == EXPECTED_PATHS.size(), "Katalog portretów musi zawierać dokładnie sześć zatwierdzonych osób z Przystani; Klara to zewnętrzna rozmówczyni.")
	for portrait_id in EXPECTED_PATHS:
		var expected_path := str(EXPECTED_PATHS[portrait_id])
		_assert(PortraitCatalogScript.has_portrait_id(portrait_id), "The catalog must recognize %s." % portrait_id)
		_assert(PortraitCatalogScript.portrait_path(portrait_id) == expected_path, "The catalog path must remain explicit and stable for %s." % portrait_id)
		_assert(ResourceLoader.exists(expected_path, "Texture2D"), "Every approved portrait ID must have an imported Texture2D: %s." % portrait_id)
		var texture: Texture2D = PortraitCatalogScript.portrait_texture(portrait_id)
		_assert(texture != null, "Every approved portrait ID must resolve a non-null Texture2D: %s." % portrait_id)
		if texture != null:
			var texture_size := texture.get_size()
			_assert(texture_size.x > 0.0 and texture_size.y > 0.0, "Every approved portrait texture must have positive dimensions: %s." % portrait_id)
			_assert(maxf(texture_size.x, texture_size.y) <= float(MAX_IMPORTED_DIMENSION), "Portrait %s must honor the runtime import size limit." % portrait_id)
			if texture_size.y > 0.0:
				var aspect_ratio := texture_size.x / texture_size.y
				_assert(absf(aspect_ratio - EXPECTED_ASPECT_RATIO) <= ASPECT_RATIO_TOLERANCE, "Portrait %s must remain close to the 13:16 composition; got %.4f." % [portrait_id, aspect_ratio])
		var portrait = SurvivorPortraitScript.new()
		portrait.configure(portrait_id, portrait_id)
		_assert(not portrait.uses_procedural_fallback(), "A known approved portrait ID must never accept a missing authored file as a valid fallback: %s." % portrait_id)
		_assert(portrait.portrait_texture() == texture, "The shared control must use the catalog texture for %s." % portrait_id)
		portrait.free()


func _test_deterministic_fallback() -> void:
	_assert(not PortraitCatalogScript.has_portrait_id("unknown_resident"), "Unknown IDs must not silently enter the authored catalog.")
	_assert(PortraitCatalogScript.portrait_path("unknown_resident").is_empty(), "Unknown IDs must resolve to an empty path.")
	_assert(PortraitCatalogScript.portrait_texture("unknown_resident") == null, "Unknown IDs must not resolve an unrelated texture.")
	var first = SurvivorPortraitScript.new()
	var second = SurvivorPortraitScript.new()
	first.configure("unknown_resident", "Unknown Resident")
	second.configure("unknown_resident", "Unknown Resident")
	_assert(first.uses_procedural_fallback() and second.uses_procedural_fallback(), "Unknown residents must use the procedural fallback.")
	_assert(first.call("_portrait_profile") == second.call("_portrait_profile"), "The same unknown ID must produce the same fallback palette.")
	_assert(first.survivor_id == "unknown_resident" and first.display_name == "Unknown Resident", "The shared control must preserve its configured public identity.")
	first.free()
	second.free()


func _test_diver_portrait_api() -> void:
	var portrait = DiverHudPortraitScript.new()
	portrait.configure("mira", "Mira Boruta")
	_assert(portrait.survivor_id == "mira" and portrait.display_name == "Mira Boruta", "DiverHudPortrait must preserve its configure API through the shared control.")
	_assert(not portrait.uses_procedural_fallback() and portrait.portrait_texture() != null, "The diver control must use the approved Mira texture.")
	portrait.free()


func _test_frozen_dive_snapshot_selection() -> void:
	var dock = DiveHudDockScript.new()
	dock.build()
	var setup = ExpeditionSetupScript.new()
	setup.diver_id = "igor"
	setup.diver_display_name = "Zamrozona Mira"
	setup.diver_profession = "rybak"
	setup.diver_portrait_id = "mira"
	setup.profession_talent_ids = {"rybak": "rybak_straznik_lowiska"}
	dock.update_identity(setup)
	_assert(dock.portrait != null and dock.portrait.survivor_id == "mira", "DiveHudDock must prefer the frozen diver_portrait_id over the diver ID.")
	_assert(dock.portrait.portrait_texture() == PortraitCatalogScript.portrait_texture("mira"), "DiveHudDock must resolve the frozen portrait through the shared catalog.")
	_assert(dock.vitals_cluster.tooltip_text.contains("Strażnik łowiska") and dock.vitals_cluster.tooltip_text.contains("70% zwykłej presji"), "DiveHudDock identity tooltip must present the profession talent frozen in ExpeditionSetup.")
	dock.free()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("Portrait catalog test failed: " + message)
