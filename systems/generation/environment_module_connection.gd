class_name EnvironmentModuleConnection
extends RefCounted

enum Type {
	ROAD,
	SIDEWALK,
	STRUCTURE_EDGE,
	INTERIOR_ACCESS,
	EXTERIOR_ACCESS,
	ALLEY,
	LOADING,
	VERTICAL,
}

var local_cell: Vector2i
var direction: Vector2i
var type: Type
var elevation: int

func _init(at := Vector2i.ZERO, facing := Vector2i.UP, connection_type := Type.ROAD, at_elevation := 0) -> void:
	local_cell = at
	direction = facing
	type = connection_type
	elevation = at_elevation

static func types_are_compatible(first: Type, second: Type) -> bool:
	if first == second:
		return true
	return (first == Type.SIDEWALK and second == Type.EXTERIOR_ACCESS) \
		or (first == Type.EXTERIOR_ACCESS and second == Type.SIDEWALK) \
		or (first == Type.ALLEY and second == Type.EXTERIOR_ACCESS) \
		or (first == Type.EXTERIOR_ACCESS and second == Type.ALLEY) \
		or (first == Type.LOADING and second == Type.EXTERIOR_ACCESS) \
		or (first == Type.EXTERIOR_ACCESS and second == Type.LOADING)

static func type_label(value: Type) -> String:
	return Type.keys()[value].to_lower()
