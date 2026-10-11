class_name MissionTerminalState
extends RefCounted

var definition: MissionTerminalDefinition
var is_activated := false

func _init(source: MissionTerminalDefinition) -> void:
	definition = source
	is_activated = source.initially_activated

func to_dictionary() -> Dictionary:
	var cell := definition.grid_position
	return {
		"terminal_id": String(definition.terminal_id),
		"objective_id": String(definition.objective_id),
		"grid_position": [cell.x, cell.y, cell.z],
		"activated": is_activated,
	}

