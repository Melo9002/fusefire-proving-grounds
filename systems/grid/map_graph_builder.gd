class_name MapGraphBuilder
extends RefCounted

static func build(map_data: MapData, pathfinder: Pathfinder) -> void:
	pathfinder.clear()
	pathfinder.surface_map = map_data
	for cell: MapCellData in map_data.cells.values():
		pathfinder.add_walkable_cell(cell.grid_position, cell.world_position)
	for cell: MapCellData in map_data.cells.values():
		pathfinder.configure_cell(cell.grid_position, cell.walkable, cell.can_stop, cell.movement_cost)
	for link in map_data.traversal_links:
		if link:
			pathfinder.connect_cells(link.from_cell, link.to_cell, link.bidirectional)
	if map_data.surface_placement_enabled:
		for cell: MapCellData in map_data.cells.values():
			var id: int = pathfinder.grid_to_id_map[cell.grid_position]
			for neighbor_id in pathfinder.astar.get_point_connections(id):
				if not SurfaceNavigation.edge_clear(map_data, cell.world_position, pathfinder.astar.get_point_position(neighbor_id)):
					pathfinder.astar.disconnect_points(id, neighbor_id)
