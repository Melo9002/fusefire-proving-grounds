class_name GeneratedTraversalBuilder
extends RefCounted

const DIRECTIONS: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]

static func apply(data: MapData, rng: RandomNumberGenerator, cell_size: float) -> void:
	for index in data.platforms.size():
		var platform: GeneratedPlatformData = data.platforms[index]
		var preferred := GeneratedTraversalData.Kind.LADDER
		if platform.elevation_level >= 5:
			preferred = GeneratedTraversalData.Kind.STAIRS
		elif index % 3 == 1:
			preferred = GeneratedTraversalData.Kind.STAIRS
		elif index % 3 == 2:
			preferred = GeneratedTraversalData.Kind.RAMP
		if preferred == GeneratedTraversalData.Kind.LADDER:
			_add_ladder(data, platform, rng)
		elif not _add_sloped_access(data, platform, preferred, rng, cell_size):
			_add_ladder(data, platform, rng)

static func _add_ladder(data: MapData, platform: GeneratedPlatformData, rng: RandomNumberGenerator) -> bool:
	for candidate in _edge_candidates(platform, rng):
		var top: Vector3i = candidate[0]
		var ground: Vector3i = candidate[1]
		var ground_data := data.get_cell(ground)
		if not ground_data or not ground_data.walkable or not ground_data.can_stop or _column_is_reserved(data, ground):
			continue
		data.add_traversal_link(TraversalLinkData.new(ground, top, true))
		data.generated_traversals.append(GeneratedTraversalData.new(GeneratedTraversalData.Kind.LADDER, ground, top))
		platform.reserved_area = platform.reserved_area.expand(Vector2i(ground.x, ground.z))
		return true
	return false

static func _add_sloped_access(data: MapData, platform: GeneratedPlatformData, kind: GeneratedTraversalData.Kind, rng: RandomNumberGenerator, cell_size: float) -> bool:
	for candidate in _edge_candidates(platform, rng):
		var top: Vector3i = candidate[0]
		var outward: Vector3i = candidate[1] - Vector3i(top.x, 0, top.z)
		var cells: Array[Vector3i] = []
		var valid := true
		var bases: Array[Vector3i] = []
		for distance in range(platform.elevation_level, 0, -1):
			var base_position := Vector3i(top.x, 0, top.z) + outward * distance
			var base := data.get_cell(base_position)
			if not base or not base.walkable or not base.can_stop or _column_is_reserved(data, base_position):
				valid = false
				break
			bases.append(base_position)
		if not valid:
			continue
		for index in bases.size():
			var base_position := bases[index]
			var base := data.get_cell(base_position)
			var distance := platform.elevation_level - index
			var level := platform.elevation_level - distance
			if level == 0:
				cells.append(base_position)
				continue
			base.walkable = false
			base.can_stop = false
			base.cover_height = float(level) * cell_size
			base.blocks_line_of_sight = true
			var step := Vector3i(base_position.x, level, base_position.z)
			data.add_cell(MapCellData.new(step, base.world_position + Vector3.UP * float(level) * cell_size))
			cells.append(step)
		cells.append(top)
		data.generated_traversals.append(GeneratedTraversalData.new(kind, cells[0], top, cells))
		for cell in cells:
			platform.reserved_area = platform.reserved_area.expand(Vector2i(cell.x, cell.z))
		return true
	return false

static func _edge_candidates(platform: GeneratedPlatformData, rng: RandomNumberGenerator) -> Array:
	var result: Array = []
	var half_size := Vector2i(
		floori(float(platform.footprint.size.x) / 2.0),
		floori(float(platform.footprint.size.y) / 2.0)
	)
	var center := platform.footprint.position + half_size
	for direction in DIRECTIONS:
		var edge := center
		if direction.x < 0: edge.x = platform.footprint.position.x
		if direction.x > 0: edge.x = platform.footprint.end.x - 1
		if direction.z < 0: edge.y = platform.footprint.position.y
		if direction.z > 0: edge.y = platform.footprint.end.y - 1
		var top := Vector3i(edge.x, platform.elevation_level, edge.y)
		result.append([top, Vector3i(edge.x, 0, edge.y) + direction])
	for index in range(result.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held = result[index]
		result[index] = result[swap]
		result[swap] = held
	return result

static func _column_is_reserved(data: MapData, position: Vector3i) -> bool:
	var column := Vector2i(position.x, position.z)
	for traversal in data.generated_traversals:
		if Vector2i(traversal.from_cell.x, traversal.from_cell.z) == column:
			return true
		if Vector2i(traversal.to_cell.x, traversal.to_cell.z) == column:
			return true
		for cell in traversal.path_cells:
			if Vector2i(cell.x, cell.z) == column:
				return true
	return false
