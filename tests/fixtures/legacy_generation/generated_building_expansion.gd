class_name GeneratedBuildingExpansion
extends RefCounted

static func apply(data: MapData, rng: RandomNumberGenerator) -> void:
	for building in data.buildings:
		_add_stairs(data, building, rng)
		if rng.randf() < 0.65:
			_add_upper_terrace(data, building)

static func _add_stairs(data: MapData, building: GeneratedBuildingData, rng: RandomNumberGenerator) -> void:
	var directions: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT]
	if rng.randi_range(0, 1) == 1:
		directions.reverse()
	for outward in directions:
		for z in range(building.footprint.position.y, building.footprint.end.y):
			var edge_x := building.footprint.position.x if outward.x < 0 else building.footprint.end.x - 1
			var approach := Vector3i(edge_x, 0, z) + outward * building.roof_level
			var route_area := Rect2i(Vector2i(approach.x, z), Vector2i.ONE).expand(Vector2i(edge_x, z)).grow(1)
			if route_area.position.x < 3 or route_area.end.x > data.map_size.x - 3:
				continue
			var valid := true
			for other in data.buildings:
				if other != building and other.reserved_area.intersects(route_area):
					valid = false
			for distance in range(1, building.roof_level + 1):
				var ground := Vector3i(edge_x, 0, z) + outward * distance
				var cell := data.get_cell(ground)
				if not cell or not cell.can_stop or ground == building.ladder_ground_cell:
					valid = false
			if not valid:
				continue
			building.stair_ground_cell = approach
			building.reserved_area = building.reserved_area.merge(route_area)
			for distance in range(building.roof_level - 1, 0, -1):
				var ground := data.get_cell(Vector3i(edge_x, 0, z) + outward * distance)
				var level := building.roof_level - distance
				_make_solid(ground, float(level))
				var position := Vector3i(ground.grid_position.x, level, z)
				data.add_cell(MapCellData.new(position, ground.world_position + Vector3.UP * level))
				building.stair_cells.append(position)
			return

static func _add_upper_terrace(data: MapData, building: GeneratedBuildingData) -> void:
	var stair_roof_cell := _get_stair_roof_cell(building)
	var corners: Array[Vector2i] = [
		building.footprint.position,
		Vector2i(building.footprint.end.x - 2, building.footprint.position.y),
		Vector2i(building.footprint.position.x, building.footprint.end.y - 2),
		building.footprint.end - Vector2i(2, 2),
	]
	for corner in corners:
		var upper_footprint := Rect2i(corner, Vector2i(2, 2))
		if upper_footprint.has_point(Vector2i(building.ladder_roof_cell.x, building.ladder_roof_cell.z)):
			continue
		if not building.stair_cells.is_empty() and upper_footprint.has_point(Vector2i(building.stair_cells[-1].x, building.stair_cells[-1].z)):
			continue
		if stair_roof_cell != Vector3i.ZERO and upper_footprint.has_point(Vector2i(stair_roof_cell.x, stair_roof_cell.z)):
			continue
		var access := _find_roof_access(building, upper_footprint)
		if access.is_empty():
			continue
		building.upper_footprint = upper_footprint
		building.upper_ladder_ground_cell = access[0]
		building.upper_ladder_roof_cell = access[1]
		for x in range(upper_footprint.position.x, upper_footprint.end.x):
			for z in range(upper_footprint.position.y, upper_footprint.end.y):
				var base_position := Vector3i(x, building.roof_level, z)
				var base := data.get_cell(base_position)
				_make_solid(base, 3.0)
				var upper := base_position + Vector3i.UP * 3
				data.add_cell(MapCellData.new(upper, base.world_position + Vector3.UP * 3.0))
				building.upper_cells.append(upper)
		data.add_traversal_link(TraversalLinkData.new(building.upper_ladder_ground_cell, building.upper_ladder_roof_cell, true))
		return

static func _get_stair_roof_cell(building: GeneratedBuildingData) -> Vector3i:
	if building.stair_cells.is_empty():
		return Vector3i.ZERO
	var last_step: Vector3i = building.stair_cells[-1]
	for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		var candidate: Vector3i = Vector3i(last_step.x, building.roof_level, last_step.z) + direction
		if building.footprint.has_point(Vector2i(candidate.x, candidate.z)):
			return candidate
	return Vector3i.ZERO

static func _find_roof_access(building: GeneratedBuildingData, upper_footprint: Rect2i) -> Array[Vector3i]:
	for x in range(upper_footprint.position.x, upper_footprint.end.x):
		for z in range(upper_footprint.position.y, upper_footprint.end.y):
			var upper_base := Vector2i(x, z)
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var landing_2d: Vector2i = upper_base + direction
				if building.footprint.has_point(landing_2d) and not upper_footprint.has_point(landing_2d):
					return [
						Vector3i(landing_2d.x, building.roof_level, landing_2d.y),
						Vector3i(x, building.roof_level + 3, z),
					]
	return []

static func _make_solid(cell: MapCellData, height: float) -> void:
	cell.walkable = false
	cell.can_stop = false
	cell.cover_type = MapCellData.CoverType.FULL
	cell.cover_height = height
	cell.blocks_line_of_sight = true
