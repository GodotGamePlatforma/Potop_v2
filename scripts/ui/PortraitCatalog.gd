class_name PortraitCatalog
extends RefCounted

const PORTRAIT_PATHS := {
	"mira": "res://assets/ui/portraits/mira_boruta_portrait_v1.png",
	"anka": "res://assets/ui/portraits/anka_ryl_portrait_v1.png",
	"igor": "res://assets/ui/portraits/igor_sowa_portrait_v1.png",
	"klara": "res://assets/ui/portraits/klara_wysocka_portrait_v1.png",
	"zofia_kruk": "res://assets/ui/portraits/zofia_kruk_portrait_v1.png",
	"pawel_mazur": "res://assets/ui/portraits/pawel_mazur_portrait_v1.png",
	"leon": "res://assets/ui/portraits/leon_wrona_portrait_v1.png",
}

static func portrait_path(portrait_id: String) -> String:
	return str(PORTRAIT_PATHS.get(_normalized_id(portrait_id), ""))


static func has_portrait_id(portrait_id: String) -> bool:
	return PORTRAIT_PATHS.has(_normalized_id(portrait_id))


static func portrait_texture(portrait_id: String) -> Texture2D:
	var path := portrait_path(portrait_id)
	if path.is_empty() or not ResourceLoader.exists(path, "Texture2D"):
		return null
	return ResourceLoader.load(path, "Texture2D") as Texture2D


static func _normalized_id(portrait_id: String) -> String:
	return portrait_id.strip_edges().to_lower()
