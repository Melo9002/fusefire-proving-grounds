class_name ShieldCapability
extends Resource

## Immutable, Inspector-authored shield tuning. Active stance and facing belong
## to TacticalState so units sharing this Resource never share runtime state.

@export_range(1, 20, 1, "suffix:AP") var stance_ap_cost := 1
@export_range(1.0, 360.0, 1.0, "suffix:°") var protected_arc_degrees := 120.0
@export_range(0.0, 1.0, 0.01) var damage_multiplier := 0.35
@export_range(-100, 0, 1, "suffix:%") var accuracy_modifier := -20
@export var attacks_allowed := false
@export var reload_allowed := false
## How many attacks the shield can cover during one stance before it is overwhelmed; later attacks
## in the same stance get no protection. Zero means no limit (the original Shield). The stance, and
## so the count, ends at the unit's next activation.
@export_range(0, 20, 1, "suffix:attacks") var max_attacks_covered := 0

## Stable identity of every replay-relevant value, at full precision, so a recording can tell that
## the Shield was retuned after it was made. Edits to any field change the signature. The capacity
## joins the identity only when it is set, so shields without a limit keep their original signature.
func signature() -> String:
	var values := [stance_ap_cost, protected_arc_degrees, damage_multiplier, accuracy_modifier, attacks_allowed, reload_allowed]
	if max_attacks_covered > 0:
		values.append(max_attacks_covered)
	return "shield-1:" + JSON.stringify(values, "", true, true).sha256_text()

## Whether the shield still has capacity after `covered` attacks in this stance.
func has_capacity(covered: int) -> bool:
	return max_attacks_covered <= 0 or covered < max_attacks_covered

func validation_message() -> String:
	if protected_arc_degrees <= 0.0 or protected_arc_degrees > 360.0:
		return "Shield protected arc must be greater than 0 and at most 360 degrees"
	if damage_multiplier < 0.0 or damage_multiplier > 1.0:
		return "Shield damage multiplier must be between 0 and 1"
	if stance_ap_cost < 1:
		return "Shield Stance must cost at least 1 AP"
	return ""
