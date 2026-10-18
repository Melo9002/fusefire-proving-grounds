class_name EnvironmentModulePlacement
extends RefCounted

var component_id: StringName
var origin: Vector2i
var rotation: int
var variation: int
var elevation: int

func _init(id: StringName, at: Vector2i, quarter_turns := 0, variation_index := 0, base_elevation := 0) -> void:
	component_id = id
	origin = at
	rotation = posmod(quarter_turns, 4)
	variation = variation_index
	elevation = base_elevation

func signature() -> String:
	return "%s@%d,%d,%d:r%d:v%d" % [component_id, origin.x, elevation, origin.y, rotation, variation]
