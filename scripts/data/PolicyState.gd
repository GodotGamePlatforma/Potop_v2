class_name PolicyState
extends Resource

enum RationPolicy {
	FULL,
	HALF,
	NONE,
	DIVER_PRIORITY,
}

const WORK_PACE_CAREFUL := "careful"
const WORK_PACE_NORMAL := "normal"
const WORK_PACE_INTENSE := "intense"

@export var ration_policy: int = RationPolicy.FULL
@export var active_laws: Array[String] = []
