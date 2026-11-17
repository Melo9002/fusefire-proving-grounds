class_name CombatCoverTuning
extends Resource
## Shared combat settings. Keep the existing resource path/class for callers.
@export_group("Accuracy and damage")
@export_range(0, 200, 1) var base_accuracy := 100
@export_range(0, 100, 1) var minimum_hit_chance := 5
@export_range(0, 100, 1) var maximum_hit_chance := 100
@export_range(0, 100, 1) var aim_accuracy_bonus := 35
@export_range(-100, 0, 1) var guard_accuracy_modifier := -15
@export_range(1, 1000, 1) var damage_on_hit := 25
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
	return base_accuracy >= 0 and base_accuracy <= 200 \
		and minimum_hit_chance >= 0 and minimum_hit_chance <= maximum_hit_chance and maximum_hit_chance <= 100 \
		and aim_accuracy_bonus >= 0 and aim_accuracy_bonus <= 100 \
		and guard_accuracy_modifier >= -100 and guard_accuracy_modifier <= 0 and damage_on_hit > 0 \
		and low_cover_penalty >= 0 and full_cover_penalty >= low_cover_penalty and full_cover_penalty <= 100 \
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

## Probability never scales a successful hit's damage. Shield is a separate defense.
func damage_for_hit(shield_multiplier: float = 1.0) -> int:
	return maxi(1, roundi(float(damage_on_hit) * shield_multiplier))

func signature() -> String:
	# Full precision prevents a tiny tuning edit being silently replay-compatible.
	var values := [base_accuracy, minimum_hit_chance, maximum_hit_chance, aim_accuracy_bonus, guard_accuracy_modifier, damage_on_hit, low_cover_penalty, full_cover_penalty, safe_range_fraction, range_penalty_at_limit, range_exponent, height_accuracy_per_tile, height_accuracy_cap]
	return "combat-3:" + JSON.stringify(values, "", true, true).sha256_text()
