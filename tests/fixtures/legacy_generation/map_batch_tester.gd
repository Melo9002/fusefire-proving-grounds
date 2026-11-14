class_name MapBatchTester
extends RefCounted

static func run(first_seed: int, seed_count: int, width: int = 32, depth: int = 24, cell_size: float = 1.0, spawn_capacity: int = 5) -> MapBatchTestResult:
	var report := MapBatchTestResult.new(first_seed, seed_count)
	for offset in seed_count:
		var map_seed := first_seed + offset
		var map_data := FlatMapGenerator.generate_with_cover(width, depth, cell_size, map_seed, spawn_capacity)
		var pathfinder := Pathfinder.new()
		MapGraphBuilder.build(map_data, pathfinder)
		var validation := MapValidator.validate(map_data, pathfinder, {
			TacticalUnit.Faction.PLAYER: spawn_capacity,
			TacticalUnit.Faction.ALLY: spawn_capacity,
			TacticalUnit.Faction.ENEMY: spawn_capacity,
		})
		var messages: Array[String] = []
		if not validation.is_valid():
			for issue in validation.errors:
				messages.append(issue.describe())
		var cover_counts := _count_cover(map_data)
		if cover_counts.x == 0:
			messages.append("[NO_LOW_COVER] Generated map contains no low cover.")
		if cover_counts.y == 0:
			messages.append("[NO_FULL_COVER] Generated map contains no full cover.")
		var cohesive_cover := _count_cohesive_cover(map_data)
		if cohesive_cover < floori(float(cover_counts.x + cover_counts.y) * 0.75):
			messages.append("[SCATTERED_COVER] Fewer than 75%% of cover cells belong to an adjacent formation.")
		if messages.is_empty():
			report.record_success(cover_counts.x, cover_counts.y, cohesive_cover)
		else:
			report.record_failure(map_seed, messages)
	return report

static func _count_cover(map_data: MapData) -> Vector2i:
	var counts := Vector2i.ZERO
	for cell: MapCellData in map_data.cells.values():
		if cell.cover_type == MapCellData.CoverType.LOW:
			counts.x += 1
		elif cell.cover_type == MapCellData.CoverType.FULL:
			counts.y += 1
	return counts

static func _count_cohesive_cover(map_data: MapData) -> int:
	var total := 0
	for cell: MapCellData in map_data.cells.values():
		if cell.cover_type == MapCellData.CoverType.NONE:
			continue
		for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var neighbor := map_data.get_cell(cell.grid_position + direction)
			if neighbor and neighbor.cover_type != MapCellData.CoverType.NONE:
				total += 1
				break
	return total
