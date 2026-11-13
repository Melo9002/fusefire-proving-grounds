class_name AuthoredDeploymentRepair
extends RefCounted
## Revalidate flat-generator deployment columns after authored solids compile.
## Preserve legal cells; move blocked cells only along their original column.
static func apply(data: MapData) -> bool:
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	var zones := data.get_zones_by_kind(MapZoneData.Kind.DEPLOYMENT)
	var anchor := Vector3i(-1, 0, -1)
	for zone in zones:
		for position in zone.cells:
			if _legal(data, position):
				anchor = position
				break
		if anchor.x >= 0: break
	if anchor.x < 0:
		return false
	var used := {}
	var replacements := {}
	# Reserve all existing legal, connected cells before choosing replacements.
	for zone in zones:
		for position in zone.cells:
			if _legal(data, position) and not graph.calculate_3d_path(anchor, position).is_empty():
				used[position] = true
	for zone in zones:
		var accepted: Array[Vector3i] = []
		for original in zone.cells:
			if _legal(data, original) and not graph.calculate_3d_path(anchor, original).is_empty():
				accepted.append(original)
				continue
			var candidates: Array[Vector3i] = []
			for row in range(1, data.map_size.y - 1):
				candidates.append(Vector3i(original.x, 0, row))
			candidates.sort_custom(func(a, b):
				var first := absi(a.z - original.z)
				var second := absi(b.z - original.z)
				return first < second if first != second else a.z < b.z)
			var replacement := Vector3i(-1, 0, -1)
			for candidate in candidates:
				if not used.has(candidate) and _legal(data, candidate) and not graph.calculate_3d_path(anchor, candidate).is_empty():
					replacement = candidate
					break
			if replacement.x < 0:
				return false
			used[replacement] = true
			accepted.append(replacement)
		replacements[zone.zone_id] = accepted
	for zone in zones:
		zone.cells.assign(replacements[zone.zone_id])
	return true

static func _legal(data: MapData, position: Vector3i) -> bool:
	var cell := data.get_cell(position)
	return cell != null and cell.walkable and cell.can_stop
