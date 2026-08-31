class_name SettlementEventWeightCurveDefinition
extends Resource

const WeightBandDefinitionScript := preload("res://base_workbench/definitions/SettlementEventWeightBandDefinition.gd")

const VALID_METRICS: Array[String] = [
	"alive_count",
	"healthy_workers",
	"food_days",
	"hope",
	"integrity",
	"material_stock",
	"medicine_stock",
	"free_shelter",
]

@export_enum(
	"alive_count",
	"healthy_workers",
	"food_days",
	"hope",
	"integrity",
	"material_stock",
	"medicine_stock",
	"free_shelter"
) var metric: String = "food_days"
@export_range(0.01, 100.0, 0.01) var fallback_multiplier: float = 1.0
@export var bands: Array[Resource] = []


func evaluate(metrics: Dictionary) -> Dictionary:
	var value := float(metrics.get(metric, 0.0))
	for band in bands:
		if band != null and band.get_script() == WeightBandDefinitionScript and band.matches(value):
			return {
				"metric": metric,
				"value": value,
				"band": str(band.label),
				"multiplier": float(band.multiplier),
			}
	return {
		"metric": metric,
		"value": value,
		"band": "fallback",
		"multiplier": fallback_multiplier,
	}


func validation_errors() -> PackedStringArray:
	var errors: Array[String] = []
	if not VALID_METRICS.has(metric):
		errors.append("unknown metric: " + metric)
	if not is_finite(fallback_multiplier) or fallback_multiplier <= 0.0:
		errors.append("fallback_multiplier must be finite and greater than zero")
	if bands.is_empty():
		errors.append("at least one band is required")
	var labels: Array[String] = []
	for index in range(bands.size()):
		var band = bands[index]
		if band == null or band.get_script() != WeightBandDefinitionScript:
			errors.append("band %d is missing or has the wrong type" % index)
			continue
		for band_error in band.validation_errors():
			errors.append("band %d: %s" % [index, band_error])
		var band_label := str(band.label)
		if labels.has(band_label):
			errors.append("duplicate band label: " + band_label)
		else:
			labels.append(band_label)
		for previous_index in range(index):
			var previous = bands[previous_index]
			if previous != null and previous.get_script() == WeightBandDefinitionScript and band.overlaps(previous):
				errors.append("bands %s and %s overlap" % [str(previous.label), band_label])
	return PackedStringArray(errors)


func is_valid() -> bool:
	return validation_errors().is_empty()
