class_name EnvironmentModuleDefinition
extends RefCounted

var component_id: StringName
var family: StringName
var size: Vector2i
var footprint_cells: Array[Vector2i] = []
var clearance_cells: Array[Vector2i] = []
var cell_effects: Dictionary = {}
var connections: Array[EnvironmentModuleConnection] = []
var visuals: Array[Dictionary] = []
var allowed_rotations: Array[int] = [0, 1, 2, 3]

func _init(id: StringName, component_family: StringName, dimensions: Vector2i) -> void:
	component_id = id
	family = component_family
	size = dimensions
	for x in dimensions.x:
		for z in dimensions.y:
			footprint_cells.append(Vector2i(x, z))

func rotated_size(rotation: int) -> Vector2i:
	return size if posmod(rotation, 2) == 0 else Vector2i(size.y, size.x)

func rotate_cell(cell: Vector2i, rotation: int) -> Vector2i:
	match posmod(rotation, 4):
		1: return Vector2i(size.y - 1 - cell.y, cell.x)
		2: return Vector2i(size.x - 1 - cell.x, size.y - 1 - cell.y)
		3: return Vector2i(cell.y, size.x - 1 - cell.x)
		_: return cell

func rotate_direction(direction: Vector2i, rotation: int) -> Vector2i:
	var result := direction
	for _step in posmod(rotation, 4):
		result = Vector2i(-result.y, result.x)
	return result

func rotated_cells(cells: Array[Vector2i], rotation: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in cells:
		result.append(rotate_cell(cell, rotation))
	return result

func add_connection(cell: Vector2i, direction: Vector2i, type: EnvironmentModuleConnection.Type) -> EnvironmentModuleDefinition:
	connections.append(EnvironmentModuleConnection.new(cell, direction, type))
	return self

func set_effect(cell: Vector2i, effect: Dictionary) -> EnvironmentModuleDefinition:
	cell_effects[cell] = effect.duplicate(true)
	return self

func add_visual(asset_path: String, local_cell: Vector2, scale: float, yaw_quarters := 0, anchor := 0) -> EnvironmentModuleDefinition:
	visuals.append({
		"asset_path": asset_path,
		"local_cell": local_cell,
		"scale": scale,
		"yaw_quarters": yaw_quarters,
		"anchor": anchor,
	})
	return self
