@tool
class_name DiveCommonLineR3CableVisual
extends "res://scripts/diving/DiveCommonLineStoryCableVisual.gd"

## Lokalnie względem terminala Archiwum. Kabel omija bryłę ruin, przechodzi
## przez panel diagnostyczny i domyka ciąg aż do generatora R-3.
const ROUTE_POINTS := [
	Vector2(0.0, 0.0),
	Vector2(848.0, 312.0),
	Vector2(2168.0, 688.0),
	Vector2(2752.0, 688.0),
	Vector2(2904.0, 696.0),
	Vector2(2952.0, 712.0),
	Vector2(2968.0, 728.0),
	Vector2(3152.0, 1160.0),
	Vector2(3160.0, 1216.0),
	Vector2(3200.0, 1544.0),
	Vector2(3200.0, 1560.0),
	Vector2(3168.0, 1632.0),
	Vector2(3080.0, 1712.0),
	Vector2(2776.0, 1768.0),
	Vector2(1952.0, 1680.0),
	Vector2(1780.0, 1600.0),
	Vector2(2040.0, 1760.0),
	Vector2(2320.0, 1940.0),
]


func _story_route_points() -> PackedVector2Array:
	return PackedVector2Array(ROUTE_POINTS)
