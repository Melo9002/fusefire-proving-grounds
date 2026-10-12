class_name ConditionDefinition
extends Resource

enum Susceptibility { BIOLOGICAL = 1, MECHANICAL_FLUID = 2, ELECTRONIC = 4 }

@export var condition_id: StringName
@export var display_name := "Condition"
@export_multiline var description := ""
@export_flags("Biological", "Mechanical Fluid", "Electronic") var required_susceptibility := 0
@export_range(1, 99, 1) var duration_beats := 1
@export_range(0, 99, 1) var recurring_damage := 0
@export var restricted_action: StringName
## Optional Tactical Tempo impairment owned by this condition. Positive condition
## bonuses and general stat modifiers are outside the 01.13.4 vertical slice.
@export_range(-20, 0, 1, "suffix:AP") var maximum_ap_delta := 0
@export var status_color := Color.WHITE

func validation_message() -> String:
	if condition_id.is_empty(): return "Condition needs a stable identifier"
	if duration_beats < 1: return "Condition duration must be at least one beat"
	if maximum_ap_delta > 0: return "Condition AP modifiers cannot grant Action Points"
	return ""
