class_name CoverPlacementPolicy
extends RefCounted
## Shared legacy/new population eligibility; orchestration and region rules stay with callers.
static func has_adjacent_full_cover(data: MapData, at: Vector3i) -> bool:
	for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		var neighbor := data.get_cell(at + direction)
		if neighbor and neighbor.cover_type == MapCellData.CoverType.FULL: return true
	return false

static func available(data: MapData, at: Vector3i, full_cover: bool) -> bool:
	var cell := data.get_cell(at)
	return cell != null and cell.walkable and cell.cover_type == MapCellData.CoverType.NONE and (not full_cover or not has_adjacent_full_cover(data, at))
