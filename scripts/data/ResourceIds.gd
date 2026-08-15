class_name ResourceIds
extends RefCounted

const HOPE := "hope"
const FOOD := "food"
const PLANKS := "planks"
const SCRAP := "scrap"
const FABRIC_RUBBER := "fabric_rubber"
const TECH_PARTS := "tech_parts"
const MEDS_CHEMICALS := "meds_chemicals"
const PLATFORM_INTEGRITY := "platform_integrity"

static func all() -> Array[String]:
	return [
		HOPE,
		FOOD,
		PLANKS,
		SCRAP,
		FABRIC_RUBBER,
		TECH_PARTS,
		MEDS_CHEMICALS,
		PLATFORM_INTEGRITY,
	]

static func display_name(resource_id: String) -> String:
	match resource_id:
		HOPE:
			return "Nadzieja"
		FOOD:
			return "Jedzenie"
		PLANKS:
			return "Deski"
		SCRAP:
			return "Złom"
		FABRIC_RUBBER:
			return "Tkaniny i guma"
		TECH_PARTS:
			return "Części techniczne"
		MEDS_CHEMICALS:
			return "Chemikalia i leki"
		PLATFORM_INTEGRITY:
			return "Integralność platformy"
		_:
			return resource_id
