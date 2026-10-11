class_name MissionTerminalDefinition
extends Resource

## Mission-owned authored data for the narrow Prototype 1.5 terminal action.
@export var terminal_id: StringName = &"terminal"
@export var objective_id: StringName
## Leave negative to use the mission planner's deterministic objective cell.
@export var grid_position := Vector3i(-1, -1, -1)
@export var initially_activated := false

