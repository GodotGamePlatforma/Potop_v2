@tool
class_name DiveCommonLineArchiveCableVisual
extends "res://scripts/diving/DiveCommonLineStoryCableVisual.gd"

## Lokalnie względem J-7. Trasa biegnie otwartą wodą do terminala Archiwum.
const ROUTE_POINTS := [
	Vector2(0.0, 0.0),
	Vector2(288.0, -312.0),
	Vector2(296.0, -320.0),
	Vector2(304.0, -328.0),
	Vector2(992.0, -656.0),
	Vector2(2592.0, -664.0),
	Vector2(4192.0, -664.0),
	Vector2(5736.0, -120.0),
]


func _story_route_points() -> PackedVector2Array:
	return PackedVector2Array(ROUTE_POINTS)
