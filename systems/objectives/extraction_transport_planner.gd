extends RefCounted
## Deterministic terrain reservation before validation and replay startup.

static func place(map: MapData, pathfinder: Pathfinder, mission: MissionDefinition) -> void:
	if not mission:
		return
	for objective in mission.objectives:
		if objective.kind != MissionObjectiveDefinition.Kind.EXTRACT:
			continue
		var zone := objective.zone_id if not objective.zone_id.is_empty() else &"extract"
		if map.transport_footprints.has(zone):
			continue
		var boarding := map.get_objective_zone(zone)
		if boarding.is_empty():
			continue
		var reserved := {}
		for entry: MapZoneData in map.zones.values():
			for cell in entry.cells:
				reserved[cell] = true
		for link in map.traversal_links:
			reserved[link.from_cell] = true
			reserved[link.to_cell] = true
		var options: Array[Dictionary] = []
		var original_components := _component_count(map, pathfinder)
		for anchor: Vector3i in map.cells:
			if anchor.y != 0:
				continue
			for size in [Vector2i(2, 4), Vector2i(4, 2)]:
				var footprint: Array[Vector3i] = []
				var legal := true
				var distance := INF
				for x in size.x:
					for z in size.y:
						var pos := anchor + Vector3i(x, 0, z)
						var cell := map.get_cell(pos)
						if not cell or not cell.walkable or not cell.can_stop or cell.cover_type != MapCellData.CoverType.NONE or reserved.has(pos) or map.get_column_cells(pos.x, pos.z).size() != 1:
							legal = false
						footprint.append(pos)
						for tile in boarding:
							distance = minf(distance, Vector3(pos).distance_to(Vector3(tile)))
				if legal and distance <= 2.0:
					options.append({"cells": footprint, "distance": distance, "anchor": anchor, "wide": size.x == 4})
		options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(a.distance, b.distance): return a.distance < b.distance
			if a.anchor.x != b.anchor.x: return a.anchor.x < b.anchor.x
			if a.anchor.z != b.anchor.z: return a.anchor.z < b.anchor.z
			return not a.wide and b.wide)
		for option in options:
			var footprint: Array[Vector3i] = option.cells
			for pos in footprint:
				map.get_cell(pos).walkable = false
			MapGraphBuilder.build(map, pathfinder)
			# Preserve connectivity of all remaining walkable terrain, including
			# diagonal corner rules rebuilt around the vehicle footprint.
			if _component_count(map, pathfinder) <= original_components:
				for pos in footprint:
					var cell := map.get_cell(pos)
					cell.can_stop = false
					cell.cover_type = MapCellData.CoverType.FULL
					cell.cover_height = 2.0
					cell.blocks_line_of_sight = true
				map.transport_footprints[zone] = footprint
				map.rebuild_los_index()
				MapGraphBuilder.build(map, pathfinder)
				break
			for pos in footprint:
				map.get_cell(pos).walkable = true
			MapGraphBuilder.build(map, pathfinder)

static func _component_count(map: MapData, pathfinder: Pathfinder) -> int:
	var ids: Array[int] = []
	for cell: MapCellData in map.cells.values():
		if cell.walkable:
			ids.append(pathfinder.grid_to_id_map[cell.grid_position])
	var seen := {}
	var count := 0
	for seed_id in ids:
		if seen.has(seed_id): continue
		count += 1
		seen[seed_id] = true
		var queue: Array[int] = [seed_id]
		var cursor := 0
		while cursor < queue.size():
			var current := queue[cursor]
			cursor += 1
			for neighbor in pathfinder.astar.get_point_connections(current):
				if not seen.has(neighbor) and not pathfinder.astar.is_point_disabled(neighbor):
					seen[neighbor] = true
					queue.append(neighbor)
	return count
