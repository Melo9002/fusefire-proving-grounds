extends RefCounted
## Presentation-only classification. Never changes path or combat legality.

const DIRECTIONS := [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.FORWARD, Vector3i.BACK]
const SurfaceFit = preload("res://systems/grid/surface_placement.gd")

static func cover_at(grid: GridManager, cell: Vector3i, facing: Vector3) -> Dictionary:
	var result := {"type": MapCellData.CoverType.NONE, "direction": Vector3.ZERO}
	var ground := grid.get_cell_data(cell)
	if not ground: return result
	var best_score := -INF
	var nearby: Array[MapCellData] = []
	if grid.map_data.surface_placement_enabled:
		nearby = SurfaceNavigation.cover_surfaces(grid.map_data, ground.world_position)
	else:
		for offset: Vector3i in [Vector3i.ZERO] + DIRECTIONS:
			var neighbor := grid.get_cell_data(cell + offset)
			if neighbor: nearby.append(neighbor)
	for neighbor in nearby:
		if not neighbor or neighbor.cover_height <= 0 or neighbor.cover_type == MapCellData.CoverType.NONE: continue
		var bounds: Array[AABB] = neighbor.authored_shot_parts.duplicate()
		if bounds.is_empty():
			bounds.append(neighbor.authored_shot_bounds if neighbor.authored_shot_bounds.has_volume() else AABB(neighbor.world_position - Vector3(grid.cell_size * 0.5, 0, grid.cell_size * 0.5), Vector3(grid.cell_size, neighbor.cover_height, grid.cell_size)))
		for part in bounds:
			# A tile-sized stand-in for a round asset: the real wall is handled below.
			if grid.map_data.presentation_stand_ins.has(part): continue
			var contact := SurfaceFit.contact(ground.world_position, part, grid.cell_size * 0.28, grid.cell_size * 1.8, grid.cell_size * 0.04)
			if not contact.found or contact.distance > grid.cell_size * 0.85: continue
			var score: float = contact.direction.dot(facing.normalized()) * 2 - contact.distance / grid.cell_size
			if score > best_score:
				best_score = score
				result = contact
				result.type = MapCellData.CoverType.FULL if part.end.y - ground.world_position.y >= grid.cell_size * 1.2 else MapCellData.CoverType.LOW
				result.height = part.end.y - ground.world_position.y
				result.stand_position = ground.world_position
	# Round assets: pose against the real curved wall, not the tile-sized stand-in.
	if grid.map_data.surface_placement_enabled:
		for entry in SurfaceNavigation.presentation_contacts(grid.map_data, ground.world_position, grid.cell_size * SurfaceNavigation.ROUND_REACH_UNITS):
			var wall: Dictionary = entry.contact
			var wall_score: float = wall.direction.dot(facing.normalized()) * 2 - wall.distance / grid.cell_size
			if wall_score > best_score:
				best_score = wall_score
				result = wall.duplicate()
				result.type = MapCellData.CoverType.FULL if entry.top - ground.world_position.y >= grid.cell_size * 1.2 else MapCellData.CoverType.LOW
				result.height = entry.top - ground.world_position.y
				result.stand_position = ground.world_position
	return result

static func path_poses(grid: GridManager, path: PackedVector3Array) -> Array[StringName]:
	var poses: Array[StringName] = []
	for i in path.size():
		var pose := &"move"
		if i > 0:
			var from_cell := grid.get_cell_data(grid.world_to_grid(path[i - 1]))
			var to_cell := grid.get_cell_data(grid.world_to_grid(path[i]))
			if from_cell and to_cell:
				if to_cell.grid_position.y > from_cell.grid_position.y:
					pose = &"climb"
				elif to_cell.grid_position.y < from_cell.grid_position.y:
					pose = &"descend"
				elif from_cell.cover_type == MapCellData.CoverType.LOW or to_cell.cover_type == MapCellData.CoverType.LOW:
					pose = &"vault"
		poses.append(pose)
	return poses
