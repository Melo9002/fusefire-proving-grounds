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

func validation_message() -> String:
	if protected_arc_degrees <= 0.0 or protected_arc_degrees > 360.0:
		return "Shield protected arc must be greater than 0 and at most 360 degrees"
	if damage_multiplier < 0.0 or damage_multiplier > 1.0:
		return "Shield damage multiplier must be between 0 and 1"
	if stance_ap_cost < 1:
		return "Shield Stance must cost at least 1 AP"
	return ""
