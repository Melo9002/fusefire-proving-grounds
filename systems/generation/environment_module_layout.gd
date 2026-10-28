class_name EnvironmentModuleLayout
extends RefCounted

var layout_id: StringName
var generation_seed: int
var placements: Array[EnvironmentModulePlacement] = []
var errors: Array[String] = []
var diagnostics: Array[String] = []
const Spatial = preload("res://systems/generation/environment_spatial_queries.gd")
var _spatial_records: Array[Dictionary] = []

func _init(id := &"", layout_seed := 0) -> void:
	layout_id = id
	generation_seed = layout_seed

func placement_error(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, map_size: Vector2i) -> String:
	if definition == null or definition.component_id != placement.component_id:
		return "Unknown or mismatched component: %s" % placement.component_id
	if placement.rotation not in definition.allowed_rotations:
		return "Rotation %d is not allowed for %s" % [placement.rotation, placement.component_id]
	if placement.elevation < 0 or not is_finite(definition.occupancy_height) or not is_finite(definition.clearance_height) or definition.occupancy_height < 0.0 or definition.clearance_height <= 0.0 or (definition.occupancy_height == 0.0 and definition.elevated_surfaces.is_empty()):
		return "Invalid elevation or spatial extent for %s" % placement.component_id
	var candidate := Spatial.record(definition, placement)
	for cell in candidate.cells + candidate.clearance:
		if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
			return "%s footprint/clearance extends outside the map at %s" % [placement.component_id, cell]
	for existing in _spatial_records:
		var reason := Spatial.conflict(candidate, existing)
		if not reason.is_empty():
			return "%s %s %s" % [placement.component_id, reason, existing.component_id]
	return ""

func try_add(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement, map_size: Vector2i) -> bool:
	var failure := placement_error(definition, placement, map_size)
	if not failure.is_empty():
		errors.append(failure)
		return false
	placements.append(placement)
	_spatial_records.append(Spatial.record(definition, placement))
	return true

func world_cells(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement) -> Array[Vector2i]:
	return Spatial.cells(definition, placement, definition.footprint_cells)

func world_clearance_cells(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement) -> Array[Vector2i]:
	return Spatial.cells(definition, placement, definition.clearance_cells)

func world_visual_envelope(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement) -> AABB:
	return Spatial.visual_envelope(definition, placement)

func world_connections(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for connection in definition.connections:
		result.append({
			"cell": placement.origin + definition.rotate_cell(connection.local_cell, placement.rotation),
			"direction": definition.rotate_direction(connection.direction, placement.rotation),
			"type": connection.type,
			"elevation": placement.elevation + connection.elevation,
			"component_id": placement.component_id,
		})
	return result

func world_suitability_cells(kind: EnvironmentModuleDefinition.Suitability, catalog: Dictionary) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for placement in placements:
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		if definition == null:
			continue
		var local_cells: Array = definition.suitability_cells.get(kind, [])
		for local_cell: Vector2i in local_cells:
			var rotated := definition.rotate_cell(local_cell, placement.rotation)
			result.append(Vector3i(placement.origin.x + rotated.x, placement.elevation, placement.origin.y + rotated.y))
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
			if second_connection.elevation != first_connection.elevation:
				continue
			if EnvironmentModuleConnection.types_are_compatible(first_connection.type, second_connection.type):
				return true
	return false

func signature() -> String:
	var parts: Array[String] = []
	for placement in placements:
		parts.append(placement.signature())
	return "%s:%d:%s" % [layout_id, generation_seed, "|".join(parts)]
