class_name MissionPlacementEvaluator
extends RefCounted

const UNREACHABLE := 1_000_000
const CARDINALS: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]

var map_data: MapData
var pathfinder: Pathfinder
var player_spawns: Array[Vector3i]
var enemy_spawns: Array[Vector3i]
var blocked: Dictionary[Vector3i, bool] = {}
var player_distances: Dictionary[Vector3i, float] = {}
var enemy_distances: Dictionary[Vector3i, float] = {}
var deployment_separation := 1

func _init(data: MapData, graph: Pathfinder) -> void:
	map_data = data
	pathfinder = graph
	player_spawns = data.get_spawn_cells(TacticalUnit.Faction.PLAYER)
	enemy_spawns = data.get_spawn_cells(TacticalUnit.Faction.ENEMY)
	player_distances = _build_distances(player_spawns)
	enemy_distances = _build_distances(enemy_spawns)
	for position in enemy_spawns:
		deployment_separation = maxi(deployment_separation, int(player_distances.get(position, 1)))
	for faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ALLY, TacticalUnit.Faction.ENEMY, TacticalUnit.Faction.NEUTRAL]:
		for position in data.get_spawn_cells(faction):
			blocked[position] = true

func legal_candidates() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for cell: MapCellData in map_data.cells.values():
		if cell.walkable and cell.can_stop and not blocked.has(cell.grid_position) \
			and player_distances.has(cell.grid_position) and enemy_distances.has(cell.grid_position):
			result.append(cell.grid_position)
	return result

func score_reach(position: Vector3i) -> float:
	var friendly: float = player_distances.get(position, UNREACHABLE)
	var hostile: float = enemy_distances.get(position, UNREACHABLE)
	return minf(friendly, hostile) * 3.0 - absf(friendly - hostile) * 1.5 + _tactical_score(position)

func score_friendly_extract(position: Vector3i) -> float:
	var friendly: float = player_distances.get(position, UNREACHABLE)
	var hostile: float = enemy_distances.get(position, UNREACHABLE)
	return friendly * 3.0 - hostile * 0.25 + _tactical_score(position) + position.y * 2.0

func score_enemy_extract(position: Vector3i) -> float:
	var friendly: float = player_distances.get(position, UNREACHABLE)
	var hostile: float = enemy_distances.get(position, UNREACHABLE)
	return hostile * 3.0 - friendly * 0.25 + _tactical_score(position) + position.y * 2.0

func is_reach_candidate(position: Vector3i) -> bool:
	return player_distances.get(position, UNREACHABLE) >= _minimum_route_fraction(0.32) \
		and enemy_distances.get(position, UNREACHABLE) >= _minimum_route_fraction(0.32)

func is_friendly_extract_candidate(position: Vector3i) -> bool:
	return player_distances.get(position, UNREACHABLE) >= _minimum_route_fraction(0.62) \
		and enemy_distances.get(position, UNREACHABLE) >= _minimum_route_fraction(0.12)

func is_enemy_extract_candidate(position: Vector3i) -> bool:
	return enemy_distances.get(position, UNREACHABLE) >= _minimum_route_fraction(0.62) \
		and player_distances.get(position, UNREACHABLE) >= _minimum_route_fraction(0.12)

func score_rescue(position: Vector3i) -> float:
	var friendly: float = player_distances.get(position, UNREACHABLE)
	var hostile: float = enemy_distances.get(position, UNREACHABLE)
	return minf(friendly, hostile) * 2.5 - absf(friendly - hostile) + _tactical_score(position) + position.y * 3.0

func reserve(cells: Array[Vector3i]) -> void:
	for position in cells:
		blocked[position] = true

func _minimum_route_fraction(fraction: float) -> int:
	return maxi(3, floori(float(deployment_separation) * fraction))

func _tactical_score(position: Vector3i) -> float:
	var cover := 0
	var exits := 0
	for direction in CARDINALS:
		var neighbor := map_data.get_cell(position + direction)
		if neighbor and neighbor.walkable:
			exits += 1
		if neighbor and (neighbor.cover_type != MapCellData.CoverType.NONE or not neighbor.walkable):
			cover += 1
	return cover * 2.0 + mini(exits, 3) * 1.5 - (6.0 if exits < 2 else 0.0)

func _build_distances(origins: Array[Vector3i]) -> Dictionary[Vector3i, float]:
	var distances: Dictionary[Vector3i, float] = {}
	var frontier: Array[Vector3i] = []
	for origin in origins:
		if pathfinder.grid_to_id_map.has(origin):
			distances[origin] = 0
			frontier.append(origin)
	while not frontier.is_empty():
		frontier.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return distances[a] < distances[b])
		var current: Vector3i = frontier[0]
		frontier.remove_at(0)
		var current_cost: float = distances[current]
		var current_id: int = pathfinder.grid_to_id_map[current]
		for neighbor_id in pathfinder.astar.get_point_connections(current_id):
			if pathfinder.astar.is_point_disabled(neighbor_id):
				continue
			var neighbor: Vector3i = pathfinder.id_to_grid_map[neighbor_id]
			var cost := current_cost + pathfinder.get_step_cost(current, neighbor)
			if distances.has(neighbor) and distances[neighbor] <= cost:
				continue
			distances[neighbor] = cost
			frontier.append(neighbor)
	return distances
