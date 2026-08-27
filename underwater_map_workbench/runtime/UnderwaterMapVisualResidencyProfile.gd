class_name UnderwaterMapVisualResidencyProfile
extends Resource

## Transient presentation tuning for camera-windowed L01/L02 textures.
## Pixel counts describe manager-owned decoded textures, not measured GPU VRAM.

@export_range(0.0, 4.0, 0.05) var prefetch_margin_viewports := 0.75
@export_range(0.0, 8.0, 0.05) var retention_margin_viewports := 1.50
@export_range(1_000_000, 256_000_000, 1_000_000) var resident_pixel_budget := 48_000_000
@export_range(1, 8, 1) var max_in_flight_requests := 2
@export_range(1, 8, 1) var max_commits_per_tick := 1


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if (
		not is_finite(prefetch_margin_viewports)
		or prefetch_margin_viewports < 0.0
	):
		errors.append("prefetch_margin_viewports musi być skończoną liczbą >= 0.")
	if (
		not is_finite(retention_margin_viewports)
		or retention_margin_viewports <= prefetch_margin_viewports
	):
		errors.append(
			"retention_margin_viewports musi być większe od prefetch_margin_viewports."
		)
	if resident_pixel_budget <= 0:
		errors.append("resident_pixel_budget musi być dodatni.")
	if max_in_flight_requests <= 0:
		errors.append("max_in_flight_requests musi być dodatnie.")
	if max_commits_per_tick <= 0:
		errors.append("max_commits_per_tick musi być dodatnie.")
	return errors
