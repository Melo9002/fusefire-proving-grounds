class_name EnvironmentModuleConnection
extends RefCounted

enum Type {
	ROAD,
	SIDEWALK,
	STRUCTURE_EDGE,
	INTERIOR_ACCESS,
	EXTERIOR_ACCESS,
}

var local_cell: Vector2i
var direction: Vector2i
var type: Type

func _init(at := Vector2i.ZERO, facing := Vector2i.UP, connection_type := Type.ROAD) -> void:
	local_cell = at
	direction = facing
	type = connection_type

static func types_are_compatible(first: Type, second: Type) -> bool:
	if first == second:
		return true
	return (first == Type.SIDEWALK and second == Type.EXTERIOR_ACCESS) \
		or (first == Type.EXTERIOR_ACCESS and second == Type.SIDEWALK)

static func type_label(value: Type) -> String:
	return Type.keys()[value].to_lower()
