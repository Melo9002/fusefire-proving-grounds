class_name EnvironmentModuleLayout
extends RefCounted

var layout_id: StringName
var generation_seed: int
var placements: Array[EnvironmentModulePlacement] = []
var errors: Array[String] = []
var _reserved_cells_by_layer: Dictionary = {}

func _init(id := &"", layout_seed := 0) -> void:
	layout_id = id
	generation_seed = layout_seed

func try_add(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, map_size: Vector2i) -> bool:
	if definition == null or definition.component_id != placement.component_id:
		errors.append("Unknown or mismatched component: %s" % placement.component_id)
		return false
	if placement.rotation not in definition.allowed_rotations:
		errors.append("Rotation %d is not allowed for %s" % [placement.rotation, placement.component_id])
		return false
	var cells := world_cells(definition, placement)
	var reservations := _reservations_for(definition.placement_layer)
	for cell in cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
			errors.append("%s extends outside the map at %s" % [placement.component_id, cell])
			return false
		if reservations.has(cell):
			errors.append("%s overlaps %s on %s at %s" % [placement.component_id, reservations[cell], EnvironmentModuleDefinition.PlacementLayer.keys()[definition.placement_layer].to_lower(), cell])
			return false
	placements.append(placement)
	for cell in cells:
		reservations[cell] = placement.component_id
	return true

func _reservations_for(layer: EnvironmentModuleDefinition.PlacementLayer) -> Dictionary:
	if not _reserved_cells_by_layer.has(layer):
		_reserved_cells_by_layer[layer] = {}
	return _reserved_cells_by_layer[layer]

func world_cells(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in definition.rotated_cells(definition.footprint_cells, placement.rotation):
		result.append(placement.origin + cell)
	return result

func world_clearance_cells(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in definition.rotated_cells(definition.clearance_cells, placement.rotation):
		result.append(placement.origin + cell)
	return result

func world_connections(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for connection in definition.connections:
		result.append({
			"cell": placement.origin + definition.rotate_cell(connection.local_cell, placement.rotation),
			"direction": definition.rotate_direction(connection.direction, placement.rotation),
			"type": connection.type,
			"component_id": placement.component_id,
		})
	return result

func placements_connect(first: EnvironmentModulePlacement, second: EnvironmentModulePlacement, catalog: Dictionary) -> bool:
	var first_definition: EnvironmentModuleDefinition = catalog.get(first.component_id)
	var second_definition: EnvironmentModuleDefinition = catalog.get(second.component_id)
	if first_definition == null or second_definition == null:
		return false
	for first_connection in world_connections(first_definition, first):
		for second_connection in world_connections(second_definition, second):
			if first_connection.cell + first_connection.direction != second_connection.cell:
				continue
			if second_connection.direction != -first_connection.direction:
				continue
			if EnvironmentModuleConnection.types_are_compatible(first_connection.type, second_connection.type):
				return true
	return false

func signature() -> String:
	var parts: Array[String] = []
	for placement in placements:
		parts.append(placement.signature())
	return "%s:%d:%s" % [layout_id, generation_seed, "|".join(parts)]
