class_name MissionDefinition
extends Resource

@export var mission_id: StringName
@export var title := "Mission"
@export var objectives: Array[MissionObjectiveDefinition] = []
@export var terminals: Array[MissionTerminalDefinition] = []
