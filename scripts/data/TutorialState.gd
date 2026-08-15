class_name TutorialState
extends Resource

enum Step {
	BUILD_COMMUNITY_HOUSE,
	BUILD_DIVING_STATION,
	ASSIGN_COMMUNITY_WORKER,
	SET_RATIONS,
	END_FIRST_DAY,
	BUILD_WORKSHOP,
	ASSIGN_DIVER_FIRST,
	START_FIRST_DIVE,
	DIVE_MOVEMENT,
	DIVE_OXYGEN,
	DIVE_OPEN_CONTAINER,
	DIVE_INVENTORY,
	DIVE_BLOCKED_PASSAGE,
	DIVE_RETURN_TO_LINE,
	STAFF_WORKSHOP,
	CRAFT_RESCUE_KNIFE,
	START_FINAL_DIVE,
	ACTIVATE_JUNCTION_J7,
	FINAL_RETURN_TO_LINE,
	COMPLETED,
}

@export var step: int = Step.BUILD_COMMUNITY_HOUSE

func advance(expected_step: int, next_step: int) -> bool:
	if step != expected_step:
		return false
	step = next_step
	return true

func is_active() -> bool:
	return step >= Step.BUILD_COMMUNITY_HOUSE and step < Step.COMPLETED

func complete() -> void:
	step = Step.COMPLETED
