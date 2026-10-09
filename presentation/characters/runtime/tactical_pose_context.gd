extends RefCounted
## Presentation-only classification. Never changes path or combat legality.

const DIRECTIONS := [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.FORWARD, Vector3i.BACK]

static func cover_at(grid: GridManager, cell: Vector3i, facing: Vector3) -> Dictionary:
	var result := {"type": MapCellData.CoverType.NONE, "direction": Vector3.ZERO}
	var best_score := -INF
	for direction: Vector3i in DIRECTIONS:
		var neighbor := grid.get_cell_data(cell + direction)
		if neighbor == null or neighbor.cover_type == MapCellData.CoverType.NONE:
			continue
		var score := Vector3(direction).dot(facing)
		if score > best_score:
			best_score = score
			result = {"type": neighbor.cover_type, "direction": Vector3(direction)}
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
