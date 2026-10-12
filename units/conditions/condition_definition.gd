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
@export var status_color := Color.WHITE

func validation_message() -> String:
	if condition_id.is_empty(): return "Condition needs a stable identifier"
	if duration_beats < 1: return "Condition duration must be at least one beat"
	return ""
