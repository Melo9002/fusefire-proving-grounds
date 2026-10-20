class_name EnvironmentModuleLayout
extends RefCounted

var layout_id: StringName
var generation_seed: int
var placements: Array[EnvironmentModulePlacement] = []
var errors: Array[String] = []
var diagnostics: Array[String] = []
var _reserved_cells_by_layer: Dictionary = {}
var _clearance_cells_by_layer: Dictionary = {}
var _visual_reservations: Array[Dictionary] = []

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
	var clearance_reservations := _clearances_for(definition.placement_layer)
	for cell in cells:
		if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
			errors.append("%s extends outside the map at %s" % [placement.component_id, cell])
			return false
		if reservations.has(cell):
			errors.append("%s overlaps %s on %s at %s" % [placement.component_id, reservations[cell], EnvironmentModuleDefinition.PlacementLayer.keys()[definition.placement_layer].to_lower(), cell])
			return false
		if clearance_reservations.has(cell):
			errors.append("%s intrudes into %s clearance on %s at %s" % [placement.component_id, clearance_reservations[cell], EnvironmentModuleDefinition.PlacementLayer.keys()[definition.placement_layer].to_lower(), cell])
			return false
	var clearances := world_clearance_cells(definition, placement)
	for cell in clearances:
		if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
			errors.append("%s clearance extends outside the map at %s" % [placement.component_id, cell])
			return false
		if reservations.has(cell):
			errors.append("%s clearance overlaps %s on %s at %s" % [placement.component_id, reservations[cell], EnvironmentModuleDefinition.PlacementLayer.keys()[definition.placement_layer].to_lower(), cell])
			return false
	var visual_bounds := world_visual_envelope(definition, placement)
	if visual_bounds.size != Vector3.ZERO:
		for existing in _visual_reservations:
			if existing.layer != definition.placement_layer:
				continue
			if visual_bounds.intersects(existing.bounds):
				errors.append("%s visual envelope intersects %s" % [placement.component_id, existing.component_id])
				return false
	placements.append(placement)
	for cell in cells:
		reservations[cell] = placement.component_id
	for cell in clearances:
		clearance_reservations[cell] = placement.component_id
	if visual_bounds.size != Vector3.ZERO:
		_visual_reservations.append({"bounds": visual_bounds, "component_id": placement.component_id, "layer": definition.placement_layer})
	return true

func _reservations_for(layer: EnvironmentModuleDefinition.PlacementLayer) -> Dictionary:
	if not _reserved_cells_by_layer.has(layer):
		_reserved_cells_by_layer[layer] = {}
	return _reserved_cells_by_layer[layer]

func _clearances_for(layer: EnvironmentModuleDefinition.PlacementLayer) -> Dictionary:
	if not _clearance_cells_by_layer.has(layer):
		_clearance_cells_by_layer[layer] = {}
	return _clearance_cells_by_layer[layer]

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

func world_visual_envelope(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement) -> AABB:
	var local := definition.visual_envelope
	if local.size == Vector3.ZERO:
		return AABB()
	var points: Array[Vector3] = []
	for x in [local.position.x, local.end.x]:
		for y in [local.position.y, local.end.y]:
			for z in [local.position.z, local.end.z]:
				var horizontal := definition.rotate_point(Vector2(x, z), placement.rotation)
				var point := Vector3(horizontal.x, y, horizontal.y)
				points.append(point + Vector3(placement.origin.x, placement.elevation, placement.origin.y))
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	# Authoring envelopes that only touch at their boundary are compatible.
	return bounds.grow(-0.01) if bounds.size.x > 0.02 and bounds.size.y > 0.02 and bounds.size.z > 0.02 else bounds

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
