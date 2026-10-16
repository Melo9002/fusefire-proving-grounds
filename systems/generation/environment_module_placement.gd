class_name EnvironmentModulePlacement
extends RefCounted

var component_id: StringName
var origin: Vector2i
var rotation: int
var variation: int

func _init(id: StringName, at: Vector2i, quarter_turns := 0, variation_index := 0) -> void:
	component_id = id
	origin = at
	rotation = posmod(quarter_turns, 4)
	variation = variation_index

func signature() -> String:
	return "%s@%d,%d:r%d:v%d" % [component_id, origin.x, origin.y, rotation, variation]
