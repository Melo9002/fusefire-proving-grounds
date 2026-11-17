class_name CombatCoverTuning
extends Resource
## Shared combat settings. Keep the existing resource path/class for callers.
@export_group("Cover")
@export_range(0, 100, 1) var low_cover_penalty := 20
@export_range(0, 100, 1) var full_cover_penalty := 40
@export_group("Range")
@export_range(0.0, 0.99, 0.01) var safe_range_fraction := 0.60
@export_range(0.0, 100.0, 0.5) var range_penalty_at_limit := 70.0
@export_range(1.01, 8.0, 0.01) var range_exponent := 2.0
@export_group("Height")
@export_range(0.0, 100.0, 0.5) var height_accuracy_per_tile := 5.0
@export_range(0.0, 100.0, 0.5) var height_accuracy_cap := 20.0

func is_valid() -> bool:
	return low_cover_penalty >= 0 and full_cover_penalty >= low_cover_penalty and full_cover_penalty <= 100 \
		and is_finite(safe_range_fraction) and safe_range_fraction >= 0 and safe_range_fraction < 1 \
		and is_finite(range_penalty_at_limit) and range_penalty_at_limit >= 0 \
		and is_finite(range_exponent) and range_exponent > 1 \
		and is_finite(height_accuracy_per_tile) and height_accuracy_per_tile >= 0 \
		and is_finite(height_accuracy_cap) and height_accuracy_cap >= 0

## Call only after validating this resource and the attack's positive range.
func range_penalty_for(distance_fraction: float) -> float:
	var tail := clampf((distance_fraction - safe_range_fraction) / (1.0 - safe_range_fraction), 0.0, 1.0)
	return range_penalty_at_limit * pow(tail, range_exponent)

func height_modifier_for(height_delta_tiles: float) -> float:
	return clampf(height_delta_tiles * height_accuracy_per_tile, -height_accuracy_cap, height_accuracy_cap)

func signature() -> String:
	# Full precision prevents a tiny tuning edit being silently replay-compatible.
	var values := [low_cover_penalty, full_cover_penalty, safe_range_fraction, range_penalty_at_limit, range_exponent, height_accuracy_per_tile, height_accuracy_cap]
	return "combat-2:" + JSON.stringify(values, "", true, true).sha256_text()
