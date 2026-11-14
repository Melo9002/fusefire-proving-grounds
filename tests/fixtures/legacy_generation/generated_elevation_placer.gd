class_name GeneratedElevationPlacer
extends RefCounted

const PLATFORM_LEVELS: Array[int] = [2, 3]

static func apply(data: MapData, rng: RandomNumberGenerator, cell_size: float, refinery: bool = false) -> void:
	if data.map_size == Vector2i(40, 30):
		_place_large_map_hill(data, rng, cell_size)
	var desired_count := 4 if refinery else (2 if data.map_size.x * data.map_size.y >= 1000 else 1)
	var candidates := _candidate_footprints(data, rng)
	for footprint in candidates:
		if data.platforms.size() >= desired_count:
			break
		if not _can_place(data, footprint):
			continue
		_add_platform(data, footprint, PLATFORM_LEVELS[rng.randi_range(0, PLATFORM_LEVELS.size() - 1)], cell_size)

static func _candidate_footprints(data: MapData, rng: RandomNumberGenerator) -> Array[Rect2i]:
	var candidates: Array[Rect2i] = []
	for x in range(5, data.map_size.x - 8):
		for z in range(3, data.map_size.y - 6):
			var size := Vector2i(4, 3) if rng.randi_range(0, 1) == 0 else Vector2i(3, 4)
			candidates.append(Rect2i(Vector2i(x, z), size))
	_shuffle(candidates, rng)
	return candidates

static func _can_place(data: MapData, footprint: Rect2i) -> bool:
	var clearance := footprint.grow(1)
	if clearance.position.x < 5 or clearance.end.x > data.map_size.x - 5:
		return false
	if clearance.position.y < 2 or clearance.end.y > data.map_size.y - 2:
		return false
	var center_row := floori(float(data.map_size.y) / 2.0)
	if clearance.position.y <= center_row + 1 and clearance.end.y > center_row - 1:
		return false
	for building in data.buildings:
		if building.reserved_area.intersects(clearance):
			return false
	for hill in data.hills:
		if hill.reserved_area.intersects(clearance):
			return false
	for platform in data.platforms:
		if platform.reserved_area.intersects(clearance):
			return false
	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			var ground := data.get_cell(Vector3i(x, 0, z))
			if not ground or not ground.walkable or not ground.can_stop:
				return false
	return true

static func _add_platform(data: MapData, footprint: Rect2i, level: int, cell_size: float) -> void:
	var platform := GeneratedPlatformData.new(footprint, level)
	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			var ground := data.get_cell(Vector3i(x, 0, z))
			var position := Vector3i(x, level, z)
			data.add_cell(MapCellData.new(position, ground.world_position + Vector3.UP * float(level) * cell_size))
			platform.cells.append(position)
	_disable_support_cells(data, footprint)
	data.platforms.append(platform)

static func _disable_support_cells(data: MapData, footprint: Rect2i) -> void:
	var corners: Array[Vector2i] = [
		footprint.position,
		Vector2i(footprint.end.x - 1, footprint.position.y),
		Vector2i(footprint.position.x, footprint.end.y - 1),
		footprint.end - Vector2i.ONE,
	]
	for corner in corners:
		var ground := data.get_cell(Vector3i(corner.x, 0, corner.y))
		ground.walkable = false
		ground.can_stop = false

static func _place_large_map_hill(data: MapData, rng: RandomNumberGenerator, cell_size: float) -> void:
	var candidates: Array[Rect2i] = []
	for x in range(7, data.map_size.x - 13):
		for z in range(3, data.map_size.y - 9):
			candidates.append(Rect2i(Vector2i(x, z), Vector2i(7, 7)))
	_shuffle(candidates, rng)
	for footprint in candidates:
		if not _can_place_hill(data, footprint):
			continue
		_add_hill(data, footprint, cell_size)
		return

static func _can_place_hill(data: MapData, footprint: Rect2i) -> bool:
	var clearance := footprint.grow(1)
	var center_row := floori(float(data.map_size.y) / 2.0)
	if clearance.position.y <= center_row + 1 and clearance.end.y > center_row - 1:
		return false
	for building in data.buildings:
		if building.reserved_area.intersects(clearance):
			return false
	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			var ground := data.get_cell(Vector3i(x, 0, z))
			if not ground or not ground.walkable or not ground.can_stop:
				return false
	return true

static func _add_hill(data: MapData, footprint: Rect2i, cell_size: float) -> void:
	var hill := GeneratedHillData.new(footprint)
	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			var horizontal_edge := mini(x - footprint.position.x, footprint.end.x - 1 - x)
			var vertical_edge := mini(z - footprint.position.y, footprint.end.y - 1 - z)
			var edge_distance := mini(horizontal_edge, vertical_edge)
			var level := mini(edge_distance + 1, 3)
			var ground := data.get_cell(Vector3i(x, 0, z))
			ground.walkable = false
			ground.can_stop = false
			ground.cover_height = float(level) * cell_size
			ground.blocks_line_of_sight = true
			var position := Vector3i(x, level, z)
			data.add_cell(MapCellData.new(position, ground.world_position + Vector3.UP * float(level) * cell_size))
			hill.surface_cells.append(position)
	data.hills.append(hill)

static func _shuffle(values: Array[Rect2i], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := values[index]
		values[index] = values[swap_index]
		values[swap_index] = held
