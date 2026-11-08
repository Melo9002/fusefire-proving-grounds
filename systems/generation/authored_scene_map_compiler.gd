class_name AuthoredSceneMapCompiler
extends RefCounted
## Compiles explicit tactical metadata from an authored Godot scene into
## MapData. Imported visual geometry never becomes tactical authority.

static func compile(root: Node, data: MapData, cell_size: float, root_transform := Transform3D.IDENTITY) -> void:
	# Establish every walkable surface before any object can stamp onto it.
	_compile_surfaces(root, root_transform, data, cell_size)
	_compile_contents(root, root_transform, data, cell_size)
	data.rebuild_los_index()

static func _compile_surfaces(node: Node, parent_transform: Transform3D, data: MapData, unit: float) -> void:
	var transform := parent_transform
	if node is Node3D: transform *= node.transform
	if node.has_meta("deck_rect"):
		var rect: Rect2i = node.get_meta("deck_rect")
		var level: int = node.get_meta("deck_level")
		data.elevation_labels[level] = "Maintenance walkway"
		for x in range(rect.position.x, rect.end.x):
			for z in range(rect.position.y, rect.end.y):
				var ground := data.get_cell(Vector3i(x, 0, z))
				if ground == null: continue
				data.add_cell(MapCellData.new(Vector3i(x, level, z), ground.world_position + Vector3.UP * level * unit))
				var slab := MapCellData.new(Vector3i(x, level - 1, z), ground.world_position + Vector3.UP * (level - 0.22) * unit)
				slab.walkable = false; slab.can_stop = false; slab.cover_height = 0.22 * unit; slab.blocks_line_of_sight = true
				data.add_cell(slab)
	if node.has_meta("deck_local_rect"):
		var level := int(node.get_meta("deck_level"))
		data.elevation_labels[level] = String(node.get_meta("deck_label", "Maintenance walkway"))
		_stamp_local_deck(data, transform, node.get_meta("deck_local_rect"), level, unit)
	if node is ElevationPath:
		for step: Vector3i in node.get_cells():
			_stamp_local_deck(data, transform, Rect2i(step.x, step.z, 1, 1), step.y, unit, false)
			if node.blocks_ground:
				var ground := data.get_cell(_local_cell_to_grid(transform, Vector3i(step.x, 0, step.z), data, unit))
				if ground:
					ground.walkable = false
					ground.can_stop = false
					ground.cover_type = MapCellData.CoverType.FULL
					ground.cover_height = step.y * unit
					ground.blocks_line_of_sight = true
	for child in node.get_children():
		_compile_surfaces(child, transform, data, unit)

static func _compile_contents(node: Node, parent_transform: Transform3D, data: MapData, unit: float) -> void:
	var transform := parent_transform
	if node is Node3D: transform *= node.transform
	if node.has_meta("solid_size"):
		_stamp_volume(data, transform, node.get_meta("solid_size"), node.get_meta("round_volume", false), unit, int(node.get_meta("movement_cost", 1)))
	if node.has_meta("objective_zone_id"):
		var cells: Array[Vector3i] = []
		for local_cell: Vector3i in node.get_meta("objective_local_cells", []):
			cells.append(_local_cell_to_grid(transform, local_cell, data, unit))
		data.set_objective_zone(node.get_meta("objective_zone_id"), cells)
	if node.has_meta("deployment_faction"):
		var faction := int(node.get_meta("deployment_faction")) as TacticalUnit.Faction
		data.zones.erase(StringName("deployment_%d" % faction))
		for local_cell: Vector3i in node.get_meta("deployment_local_cells", []):
			data.add_spawn_cell(faction, _local_cell_to_grid(transform, local_cell, data, unit))
	if node.has_meta("ladder_bottom"):
		data.add_traversal_link(TraversalLinkData.new(node.get_meta("ladder_bottom"), node.get_meta("ladder_top"), true))
	if node.has_meta("ladder_local_bottom"):
		var bottom := _local_cell_to_grid(transform, node.get_meta("ladder_local_bottom"), data, unit)
		var top := _local_cell_to_grid(transform, node.get_meta("ladder_local_top"), data, unit)
		data.add_traversal_link(TraversalLinkData.new(bottom, top, true))
	if node.has_meta("faction"):
		var origin: Vector3i = node.get_meta("grid_origin")
		for offset in 5: data.add_spawn_cell(int(node.get_meta("faction")) as TacticalUnit.Faction, origin + Vector3i(0, 0, offset))
	for child in node.get_children():
		_compile_contents(child, transform, data, unit)

static func _stamp_local_deck(data: MapData, transform: Transform3D, rect: Rect2i, level: int, unit: float, include_slab := true) -> void:
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			var position := _local_cell_to_grid(transform, Vector3i(x, level, z), data, unit)
			var ground := data.get_cell(Vector3i(position.x, 0, position.z))
			if ground == null: continue
			data.add_cell(MapCellData.new(position, ground.world_position + Vector3.UP * level * unit))
			if not include_slab: continue
			var slab := MapCellData.new(position - Vector3i.UP, ground.world_position + Vector3.UP * (level - 0.22) * unit)
			slab.walkable = false; slab.can_stop = false; slab.cover_height = 0.22 * unit; slab.blocks_line_of_sight = true
			data.add_cell(slab)

static func _local_cell_to_grid(transform: Transform3D, local: Vector3i, data: MapData, unit: float) -> Vector3i:
	var world := transform * Vector3(local)
	return Vector3i(roundi(world.x / unit + data.map_size.x * 0.5 - 0.5), roundi(world.y / unit), roundi(world.z / unit + data.map_size.y * 0.5 - 0.5))

static func _stamp_volume(data: MapData, transform: Transform3D, dimensions: Vector3, round_volume: bool, unit: float, movement_cost: int) -> void:
	var bounds := transform * AABB(-dimensions * 0.5, dimensions)
	var lower := Vector2i(floori(bounds.position.x + data.map_size.x * 0.5), floori(bounds.position.z + data.map_size.y * 0.5))
	var upper := Vector2i(ceili(bounds.end.x + data.map_size.x * 0.5), ceili(bounds.end.z + data.map_size.y * 0.5))
	var inverse := transform.affine_inverse()
	for x in range(maxi(0, lower.x), mini(data.map_size.x, upper.x)):
		for z in range(maxi(0, lower.y), mini(data.map_size.y, upper.y)):
			for cell: MapCellData in data.columns.get(Vector2i(x, z), []):
				var height := float(cell.grid_position.y)
				if height < bounds.position.y - 0.001 or height >= bounds.end.y:
					continue
				var point := inverse * (cell.world_position / unit)
				if absf(point.x) >= dimensions.x * 0.5 + 0.5 or absf(point.z) >= dimensions.z * 0.5 + 0.5: continue
				if round_volume and pow(maxf(absf(point.x) - 0.5, 0.0) / (dimensions.x * 0.5), 2) + pow(maxf(absf(point.z) - 0.5, 0.0) / (dimensions.z * 0.5), 2) > 1.0: continue
				cell.can_stop = false
				cell.cover_height = maxf(cell.cover_height, (bounds.end.y - height) * unit)
				cell.cover_type = MapCellData.CoverType.FULL if cell.cover_height >= 1.2 * unit else MapCellData.CoverType.LOW
				cell.walkable = cell.cover_type == MapCellData.CoverType.LOW
				cell.blocks_line_of_sight = cell.cover_type == MapCellData.CoverType.FULL
				if cell.walkable:
					cell.movement_cost = maxi(cell.movement_cost, movement_cost)
