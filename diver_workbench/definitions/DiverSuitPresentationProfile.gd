class_name DiverSuitPresentationProfile
extends Resource

## Presentation-only mapping from the canonical root suit quality (1..4) to
## distinct construction treatments. Equipment ownership, balance and save data
## remain outside the Diver workbench.

const MIN_QUALITY := 1
const MAX_QUALITY := 4

@export_group("Quality 1 - Expedition")
@export var quality_1_label: StringName = &"Expedition"
@export_range(0, 3, 1) var quality_1_style_id := 0
@export var quality_1_fabric := Color("263b48")
@export var quality_1_metal := Color("876036")
@export var quality_1_pattern := Color("4dc7d1")
@export var quality_1_rim := Color("4dc7d1")
@export_range(0.0, 1.0, 0.01) var quality_1_fabric_mix := 0.0
@export_range(0.0, 1.0, 0.01) var quality_1_metal_mix := 0.0
@export_range(0.0, 1.0, 0.01) var quality_1_pattern_strength := 0.0
@export_range(0.0, 1.0, 0.01) var quality_1_plate_strength := 0.0
@export_range(0.0, 1.0, 0.01) var quality_1_emissive_strength := 0.0
@export_range(0.0, 1.0, 0.01) var quality_1_accent_strength := 0.32
@export_range(0.0, 3.5, 0.1) var quality_1_outline_width := 3.5

@export_group("Quality 2 - Sealed")
@export var quality_2_label: StringName = &"Sealed"
@export_range(0, 3, 1) var quality_2_style_id := 1
@export var quality_2_fabric := Color("1d5960")
@export var quality_2_metal := Color("b8733f")
@export var quality_2_pattern := Color("62d2ca")
@export var quality_2_rim := Color("5dc9c6")
@export_range(0.0, 1.0, 0.01) var quality_2_fabric_mix := 0.50
@export_range(0.0, 1.0, 0.01) var quality_2_metal_mix := 0.36
@export_range(0.0, 1.0, 0.01) var quality_2_pattern_strength := 0.45
@export_range(0.0, 1.0, 0.01) var quality_2_plate_strength := 0.15
@export_range(0.0, 1.0, 0.01) var quality_2_emissive_strength := 0.04
@export_range(0.0, 1.0, 0.01) var quality_2_accent_strength := 0.36
@export_range(0.0, 3.5, 0.1) var quality_2_outline_width := 3.5

@export_group("Quality 3 - Pressure")
@export var quality_3_label: StringName = &"Pressure"
@export_range(0, 3, 1) var quality_3_style_id := 2
@export var quality_3_fabric := Color("26303d")
@export var quality_3_metal := Color("c4a66b")
@export var quality_3_pattern := Color("e0d5b8")
@export var quality_3_rim := Color("72d3dc")
@export_range(0.0, 1.0, 0.01) var quality_3_fabric_mix := 0.55
@export_range(0.0, 1.0, 0.01) var quality_3_metal_mix := 0.50
@export_range(0.0, 1.0, 0.01) var quality_3_pattern_strength := 0.35
@export_range(0.0, 1.0, 0.01) var quality_3_plate_strength := 0.65
@export_range(0.0, 1.0, 0.01) var quality_3_emissive_strength := 0.08
@export_range(0.0, 1.0, 0.01) var quality_3_accent_strength := 0.40
@export_range(0.0, 3.5, 0.1) var quality_3_outline_width := 3.5

@export_group("Quality 4 - Abyss")
@export var quality_4_label: StringName = &"Abyss"
@export_range(0, 3, 1) var quality_4_style_id := 3
@export var quality_4_fabric := Color("101a20")
@export var quality_4_metal := Color("d2a84f")
@export var quality_4_pattern := Color("71f3e4")
@export var quality_4_rim := Color("91e5df")
@export_range(0.0, 1.0, 0.01) var quality_4_fabric_mix := 0.68
@export_range(0.0, 1.0, 0.01) var quality_4_metal_mix := 0.62
@export_range(0.0, 1.0, 0.01) var quality_4_pattern_strength := 0.75
@export_range(0.0, 1.0, 0.01) var quality_4_plate_strength := 0.40
@export_range(0.0, 1.0, 0.01) var quality_4_emissive_strength := 0.35
@export_range(0.0, 1.0, 0.01) var quality_4_accent_strength := 0.45
@export_range(0.0, 3.5, 0.1) var quality_4_outline_width := 3.5


func normalized_quality(value: int) -> int:
	return clampi(value, MIN_QUALITY, MAX_QUALITY)


func style_for(value: int) -> Dictionary:
	var quality := normalized_quality(value)
	return {
		"quality": quality,
		"label": get("quality_%d_label" % quality),
		"style_id": get("quality_%d_style_id" % quality),
		"fabric_color": get("quality_%d_fabric" % quality),
		"metal_color": get("quality_%d_metal" % quality),
		"pattern_color": get("quality_%d_pattern" % quality),
		"rim_color": get("quality_%d_rim" % quality),
		"fabric_mix": get("quality_%d_fabric_mix" % quality),
		"metal_mix": get("quality_%d_metal_mix" % quality),
		"pattern_strength": get("quality_%d_pattern_strength" % quality),
		"plate_strength": get("quality_%d_plate_strength" % quality),
		"emissive_strength": get("quality_%d_emissive_strength" % quality),
		"accent_strength": get("quality_%d_accent_strength" % quality),
		"outline_width": get("quality_%d_outline_width" % quality),
	}


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var signatures := {}
	for quality in range(MIN_QUALITY, MAX_QUALITY + 1):
		var style := style_for(quality)
		if String(style["label"]).is_empty():
			errors.append("Suit quality %d requires a presentation label." % quality)
		var style_id := int(style["style_id"])
		if style_id < 0 or style_id > 3:
			errors.append("Suit quality %d has an invalid style id." % quality)
		for color_key in ["fabric_color", "metal_color", "pattern_color", "rim_color"]:
			var color: Color = style[color_key]
			if not (
				is_finite(color.r)
				and is_finite(color.g)
				and is_finite(color.b)
				and is_finite(color.a)
			):
				errors.append("Suit quality %d has a non-finite %s." % [quality, color_key])
		for scalar_key in [
			"fabric_mix", "metal_mix", "pattern_strength", "plate_strength",
			"emissive_strength", "accent_strength",
		]:
			var scalar := float(style[scalar_key])
			if not is_finite(scalar) or scalar < 0.0 or scalar > 1.0:
				errors.append("Suit quality %d has an invalid %s." % [quality, scalar_key])
		var outline_width := float(style["outline_width"])
		if not is_finite(outline_width) or outline_width < 0.0 or outline_width > 3.5:
			errors.append("Suit quality %d exceeds the reviewed outline envelope." % quality)
		signatures["%s" % style] = true
	if signatures.size() != MAX_QUALITY - MIN_QUALITY + 1:
		errors.append("All four suit qualities must expose distinct presentation styles.")
	var baseline := style_for(1)
	if (
		float(baseline["fabric_mix"]) != 0.0
		or float(baseline["metal_mix"]) != 0.0
		or float(baseline["pattern_strength"]) != 0.0
		or float(baseline["plate_strength"]) != 0.0
		or float(baseline["emissive_strength"]) != 0.0
	):
		errors.append("Suit quality 1 must preserve the approved v4 raster treatment.")
	return errors
