@tool
class_name DiveCommonLineC4CableVisual
extends "res://scripts/diving/DiveCommonLineStoryCableVisual.gd"

## Lokalnie względem generatora R-3. Końcowa wersja punktów jest generowana
## po otwarciu zatoki serwisowej C-4 i kończy się przy jej rozdzielni.
const ROUTE_POINTS := [
	Vector2(0.0, 0.0),
	Vector2(-1080.0, 180.0),
	Vector2(-1128.0, 204.0),
	Vector2(-1872.0, 644.0),
	Vector2(-1944.0, 644.0),
	Vector2(-1976.0, 652.0),
	Vector2(-2232.0, 932.0),
	Vector2(-2232.0, 1244.0),
	Vector2(-2240.0, 1260.0),
	Vector2(-2424.0, 1428.0),
	Vector2(-2464.0, 1428.0),
	Vector2(-2704.0, 1692.0),
	Vector2(-2704.0, 1724.0),
	Vector2(-2712.0, 1740.0),
	Vector2(-2848.0, 1932.0),
	Vector2(-2928.0, 2004.0),
	Vector2(-3376.0, 2204.0),
	Vector2(-3416.0, 2204.0),
	Vector2(-4600.0, 2760.0),
]


func _story_route_points() -> PackedVector2Array:
	return PackedVector2Array(ROUTE_POINTS)
