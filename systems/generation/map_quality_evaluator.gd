class_name MapQualityEvaluator
extends RefCounted

const CARDINALS: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
const LANE_DIRECTIONS: Array[Vector3i] = [
	Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK,
	Vector3i(-1, 0, -1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(1, 0, 1),
]
const COVER_SEARCH_BUDGET := 6
const FIRING_RANGE := 10

static func evaluate(map_data: MapData, pathfinder: Pathfinder) -> MapQualityReport:
	var report := MapQualityReport.new()
	report.map_seed = map_data.generation_seed
	report.source_kind = map_data.source_kind
	report.map_size = map_data.map_size
	var stoppable := _stoppable_cells(map_data)
	report.stoppable_cells = stoppable.size()
	var player_spawns := map_data.get_spawn_cells(TacticalUnit.Faction.PLAYER)
	var enemy_spawns := map_data.get_spawn_cells(TacticalUnit.Faction.ENEMY)
	report.player_cover_access = _cover_access(player_spawns, map_data, pathfinder)
	report.enemy_cover_access = _cover_access(enemy_spawns, map_data, pathfinder)
	report.cover_fairness = _fairness(report.player_cover_access, report.enemy_cover_access)
	report.player_route_options = _route_options(player_spawns, enemy_spawns, pathfinder)
	report.enemy_route_options = _route_options(enemy_spawns, player_spawns, pathfinder)
	report.route_fairness = _fairness(report.player_route_options, report.enemy_route_options)
	var open_cells := _open_cells(stoppable, map_data)
	report.open_space_ratio = _ratio(open_cells.size(), stoppable.size())
	report.largest_open_region_ratio = _ratio(_largest_region(open_cells, pathfinder), stoppable.size())
	var lane_result := _firing_lanes(stoppable, map_data)
	report.average_firing_lane = lane_result.x
	report.maximum_firing_lane = roundi(lane_result.y)
	report.player_spawn_exposure = _spawn_exposure(player_spawns, map_data)
	report.enemy_spawn_exposure = _spawn_exposure(enemy_spawns, map_data)
	report.exposure_fairness = _fairness(report.player_spawn_exposure, report.enemy_spawn_exposure)
	var cover_supply := clampf((report.player_cover_access + report.enemy_cover_access) * 0.5 / 0.25, 0.0, 1.0)
	var route_supply := clampf((report.player_route_options + report.enemy_route_options) * 0.5 / 3.0, 0.0, 1.0)
	var exposure_safety := 1.0 - (report.player_spawn_exposure + report.enemy_spawn_exposure) * 0.5
	var lane_quality := clampf(1.0 - absf(report.average_firing_lane - 6.0) / 6.0, 0.0, 1.0)
	report.cover_score = 100.0 * (report.cover_fairness * 0.40 + cover_supply * 0.60)
	report.route_score = 100.0 * (report.route_fairness * 0.50 + route_supply * 0.50)
	report.open_space_score = 100.0 * _open_space_quality(report.open_space_ratio)
	report.firing_lane_score = 100.0 * lane_quality
	report.spawn_safety_score = 100.0 * (report.exposure_fairness * (2.0 / 7.0) + exposure_safety * (5.0 / 7.0))
	report.overall_score = (
		report.cover_score * 0.25
		+ report.route_score * 0.20
		+ report.open_space_score * 0.10
		+ report.firing_lane_score * 0.10
		+ report.spawn_safety_score * 0.35
	)
	return report

static func _stoppable_cells(map_data: MapData) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for cell: MapCellData in map_data.cells.values():
		if cell.walkable and cell.can_stop:
			result.append(cell.grid_position)
	return result

static func _cover_access(spawns: Array[Vector3i], map_data: MapData, pathfinder: Pathfinder) -> float:
	if spawns.is_empty():
		return 0.0
	var total := 0.0
	for spawn in spawns:
		var nearby := pathfinder.get_reachable_cells(spawn, COVER_SEARCH_BUDGET)
		nearby.append(spawn)
		var protected := 0
		for position in nearby:
			if _cover_directions(position, map_data) > 0:
				protected += 1
		total += _ratio(protected, nearby.size())
	return total / float(spawns.size())

static func _cover_directions(position: Vector3i, map_data: MapData) -> int:
	var count := 0
	for direction in CARDINALS:
		var neighbor := map_data.get_cell(position + direction)
		if neighbor and (neighbor.cover_type != MapCellData.CoverType.NONE or neighbor.blocks_line_of_sight):
			count += 1
	return count

static func _route_options(origins: Array[Vector3i], targets: Array[Vector3i], pathfinder: Pathfinder) -> float:
	if origins.is_empty() or targets.is_empty():
		return 0.0
	var total := 0.0
	for origin in origins:
		if not pathfinder.grid_to_id_map.has(origin):
			continue
		var origin_id: int = pathfinder.grid_to_id_map[origin]
		pathfinder.astar.set_point_disabled(origin_id, true)
		var branches := 0
		for neighbor_id in pathfinder.astar.get_point_connections(origin_id):
			if pathfinder.astar.is_point_disabled(neighbor_id):
				continue
			for target in targets:
				if pathfinder.grid_to_id_map.has(target) and not pathfinder.astar.get_id_path(neighbor_id, pathfinder.grid_to_id_map[target]).is_empty():
					branches += 1
					break
		pathfinder.astar.set_point_disabled(origin_id, false)
		total += branches
	return total / float(origins.size())

static func _open_cells(stoppable: Array[Vector3i], map_data: MapData) -> Dictionary[Vector3i, bool]:
	var result: Dictionary[Vector3i, bool] = {}
	for position in stoppable:
		var exits := 0
		for direction in CARDINALS:
			var neighbor := map_data.get_cell(position + direction)
			if neighbor and neighbor.walkable:
				exits += 1
		if exits >= 3 and _cover_directions(position, map_data) == 0:
			result[position] = true
	return result

static func _largest_region(open_cells: Dictionary[Vector3i, bool], pathfinder: Pathfinder) -> int:
	var visited: Dictionary[Vector3i, bool] = {}
	var largest := 0
	for start in open_cells:
		if visited.has(start):
			continue
		var size := 0
		var frontier: Array[Vector3i] = [start]
		var head := 0
		visited[start] = true
		while head < frontier.size():
			var current: Vector3i = frontier[head]
			head += 1
			size += 1
			var current_id: int = pathfinder.grid_to_id_map.get(current, -1)
			if current_id < 0:
				continue
			for neighbor_id in pathfinder.astar.get_point_connections(current_id):
				var neighbor: Vector3i = pathfinder.id_to_grid_map[neighbor_id]
				if open_cells.has(neighbor) and not visited.has(neighbor):
					visited[neighbor] = true
					frontier.append(neighbor)
		largest = maxi(largest, size)
	return largest

static func _firing_lanes(stoppable: Array[Vector3i], map_data: MapData) -> Vector2:
	if stoppable.is_empty():
		return Vector2.ZERO
	var total := 0
	var maximum := 0
	for position in stoppable:
		var best := 0
		for direction in LANE_DIRECTIONS:
			best = maxi(best, _lane_length(position, direction, map_data))
		total += best
		maximum = maxi(maximum, best)
	return Vector2(float(total) / float(stoppable.size()), maximum)

static func _lane_length(origin: Vector3i, direction: Vector3i, map_data: MapData) -> int:
	var length := 0
	for step in range(1, FIRING_RANGE + 1):
		var position := origin + direction * step
		var cell := map_data.get_cell(position)
		if not cell:
			break
		if cell.blocks_line_of_sight:
			break
		length = step
	return length

static func _spawn_exposure(spawns: Array[Vector3i], map_data: MapData) -> float:
	if spawns.is_empty():
		return 0.0
	var total := 0.0
	for spawn in spawns:
		var longest := 0
		for direction in LANE_DIRECTIONS:
			longest = maxi(longest, _lane_length(spawn, direction, map_data))
		var cover_protection := float(_cover_directions(spawn, map_data)) / float(CARDINALS.size())
		total += (float(longest) / float(FIRING_RANGE)) * (1.0 - cover_protection)
	return total / float(spawns.size())

static func _fairness(first: float, second: float) -> float:
	var scale := maxf(maxf(absf(first), absf(second)), 0.25)
	return clampf(1.0 - absf(first - second) / scale, 0.0, 1.0)

static func _open_space_quality(ratio: float) -> float:
	# Broadly reward a mixed battlefield; later simulation can tune this target.
	return clampf(1.0 - absf(ratio - 0.40) / 0.40, 0.0, 1.0)

static func _ratio(numerator: int, denominator: int) -> float:
	return float(numerator) / float(denominator) if denominator > 0 else 0.0
