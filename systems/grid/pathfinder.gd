extends RefCounted
class_name Pathfinder

class MovementGraph extends AStar3D:
	var cells: Dictionary = {}
	func _compute_cost(from_id: int, to_id: int) -> float:
		var delta: Vector3i = cells[to_id] - cells[from_id]
		return sqrt(2.0) if delta.y == 0 and absi(delta.x) == 1 and absi(delta.z) == 1 else 1.0
	func _estimate_cost(_from_id: int, _to_id: int) -> float:
		# Explicit ladders/links retain their existing one-step cost.
		return 0.0

var astar := MovementGraph.new()
var _point_cells: Dictionary = {}
var _graph_revision := 0
var _edge_radius_revision := -1
var _max_edge_radius := 0.0
var grid_to_id_map: Dictionary = {}
var id_to_grid_map: Dictionary = {}
var movement_costs: Dictionary = {}
var stoppable_cells: Dictionary = {}
var next_id: int = 0
var max_step_levels: int = 1
var surface_map: MapData
var live_grid: GridManager
var defer_surface_edges := false

const DIRECTIONS: Array[Vector3i] = [
	Vector3i.RIGHT,
	Vector3i.LEFT,
	Vector3i.FORWARD,
	Vector3i.BACK,
]

## Changes whenever the walkable graph does (cells added, opened or closed, links made), never when units move: a route planned at one revision may no longer exist at another.
func graph_revision() -> int:
	return _graph_revision

func clear() -> void:
	_graph_revision += 1
	_point_cells.clear()
	surface_map = null
	live_grid = null
	defer_surface_edges = false
	astar.clear()
	astar.cells.clear()
	grid_to_id_map.clear()
	id_to_grid_map.clear()
	movement_costs.clear()
	stoppable_cells.clear()
	next_id = 0

func add_walkable_cell(grid_pos: Vector3i, world_pos: Vector3) -> void:
	if grid_to_id_map.has(grid_pos):
		return # Avoid duplicating existing nodes

	var id = next_id
	next_id += 1

	grid_to_id_map[grid_pos] = id
	id_to_grid_map[id] = grid_pos
	astar.cells[id] = grid_pos
	astar.add_point(id, world_pos)
	_point_cells[world_pos] = grid_pos
	_graph_revision += 1
	movement_costs[grid_pos] = 1
	stoppable_cells[grid_pos] = true

	for direction in DIRECTIONS:
		for height_offset in range(-max_step_levels, max_step_levels + 1):
			var neighbor = grid_pos + direction + Vector3i.UP * height_offset
			if grid_to_id_map.has(neighbor):
				astar.connect_points(id, grid_to_id_map[neighbor])
	_refresh_diagonals_near(grid_pos)

func configure_cell(grid_pos: Vector3i, traversable: bool, can_stop: bool, movement_cost: int = 1) -> void:
	if not grid_to_id_map.has(grid_pos):
		return
	var point_id = grid_to_id_map[grid_pos]
	_graph_revision += 1
	astar.set_point_disabled(point_id, not traversable)
	astar.set_point_weight_scale(point_id, maxf(1.0, float(movement_cost)))
	movement_costs[grid_pos] = maxi(1, movement_cost)
	stoppable_cells[grid_pos] = can_stop
	_refresh_diagonals_near(grid_pos)

func _clear_for_diagonal(cell: Vector3i) -> bool:
	return grid_to_id_map.has(cell) and stoppable_cells.get(cell, false) and not astar.is_point_disabled(grid_to_id_map[cell])

func _refresh_diagonals_near(changed: Vector3i) -> void:
	# All four cells in a square must be clear, including the two side cells.
	# Non-stoppable low cover retains cardinal traversal and its terrain cost.
	for x in range(changed.x - 1, changed.x + 1):
		for z in range(changed.z - 1, changed.z + 1):
			var a := Vector3i(x, changed.y, z)
			var b := a + Vector3i.RIGHT
			var c := a + Vector3i.BACK
			var d := b + Vector3i.BACK
			var diagonal_is_clear := _clear_for_diagonal(a) and _clear_for_diagonal(b) and _clear_for_diagonal(c) and _clear_for_diagonal(d)
			for pair in [[a, d], [b, c]]:
				if not grid_to_id_map.has(pair[0]) or not grid_to_id_map.has(pair[1]):
					continue
				var first: int = grid_to_id_map[pair[0]]
				var second: int = grid_to_id_map[pair[1]]
				var safe := diagonal_is_clear
				if safe and surface_map and surface_map.surface_placement_enabled and not defer_surface_edges:
					safe = SurfaceNavigation.edge_clear(surface_map, astar.get_point_position(first), astar.get_point_position(second))
				if safe:
					astar.connect_points(first, second)
				elif astar.are_points_connected(first, second):
					astar.disconnect_points(first, second)

func get_step_cost(from_cell: Vector3i, to_cell: Vector3i) -> float:
	return astar._compute_cost(grid_to_id_map[from_cell], grid_to_id_map[to_cell]) * float(movement_costs.get(to_cell, 1))

func get_path_cost(path: PackedVector3Array, world_to_grid: Callable) -> float:
	var cost := 0.0
	for index in range(1, path.size()):
		var from_cell: Vector3i = world_to_grid.call(path[index - 1])
		var to_cell: Vector3i = world_to_grid.call(path[index])
		if not grid_to_id_map.has(from_cell) or not grid_to_id_map.has(to_cell):
			return INF
		cost += get_step_cost(from_cell, to_cell)
	return cost

func connect_cells(from_cell: Vector3i, to_cell: Vector3i, bidirectional: bool = true) -> bool:
	if not grid_to_id_map.has(from_cell) or not grid_to_id_map.has(to_cell):
		return false
	if surface_map and not SurfaceNavigation.edge_clear(surface_map, astar.get_point_position(grid_to_id_map[from_cell]), astar.get_point_position(grid_to_id_map[to_cell])): return false
	_graph_revision += 1
	astar.connect_points(grid_to_id_map[from_cell], grid_to_id_map[to_cell], bidirectional)
	return true

func calculate_3d_path(start_grid: Vector3i, end_grid: Vector3i) -> PackedVector3Array:
	if not grid_to_id_map.has(start_grid) or not grid_to_id_map.has(end_grid):
		return PackedVector3Array()
	if not stoppable_cells.get(end_grid, false):
		return PackedVector3Array()

	var start_id = grid_to_id_map[start_grid]
	var end_id = grid_to_id_map[end_grid]
	var path := astar.get_point_path(start_id, end_id)
	if surface_map and surface_map.surface_placement_enabled and is_instance_valid(live_grid) and not live_grid.occupancy_map.is_empty():
		var actor := live_grid.get_unit_at(start_grid)
		if path.is_empty() or not _path_respects_hypothetical_occupancy(path, start_grid, live_grid, actor):
			return _calculate_hypothetical_fallback(start_grid, end_grid, live_grid, actor)
	return path

## Read-only planning path. Occupied cells remain blocked except for the named
## actor's live origin, which is treated as vacated when planning from a future
## candidate. This never changes occupancy_map or AStar disabled points.
func calculate_path_with_occupancy(start_grid: Vector3i, end_grid: Vector3i, grid: GridManager, ignored_actor: TacticalUnit = null, clearance_cache: Variant = null) -> PackedVector3Array:
	var checks: Dictionary = {} if clearance_cache == null else clearance_cache
	# A caller can reuse this scratch dictionary across candidates, never across a changed body layout.
	var data := grid.map_data
	var signature: Array = [_graph_revision, grid.get_instance_id(), data.get_instance_id(), data.body_radius,
		data.body_height, data.body_clearance, data.surface_placement_enabled, data.surface_unit, ignored_actor]
	for occupant in grid.occupancy_map.values():
		if not is_instance_valid(occupant): continue
		var cell := data.get_cell(occupant.grid_position)
		# An occupant standing outside the map has no cell position: it is recorded as null so the signature still changes when it moves.
		var occupant_position: Variant = null
		if cell != null:
			occupant_position = cell.world_position
		signature.append([occupant, occupant.grid_position, occupant_position])
	if checks.get("signature") != signature:
		checks.clear()
		checks["signature"] = signature
	var path := PackedVector3Array()
	if grid.map_data.surface_placement_enabled:
		# Hypothetical starts must vacate the explicitly named actor's real origin.
		# Do not first plan as an anonymous actor and repeat an unnecessary detour.
		if grid_to_id_map.has(start_grid) and grid_to_id_map.has(end_grid) and stoppable_cells.get(end_grid, false):
			path = astar.get_point_path(grid_to_id_map[start_grid], grid_to_id_map[end_grid])
	else:
		path = calculate_3d_path(start_grid, end_grid)
	if not path.is_empty() and _path_respects_hypothetical_occupancy(path, start_grid, grid, ignored_actor, checks):
		return path
	return _calculate_hypothetical_fallback(start_grid, end_grid, grid, ignored_actor, checks)

func _path_respects_hypothetical_occupancy(path: PackedVector3Array, start_grid: Vector3i, grid: GridManager, ignored_actor: TacticalUnit, checks: Variant = null) -> bool:
	if checks == null: checks = {}
	for index in path.size():
		var point := path[index]
		if grid.map_data.surface_placement_enabled and not _planning_units_clear(grid, path[maxi(0, index - 1)], point, ignored_actor, checks): return false
		var cell: Vector3i = _point_cells.get(point, Vector3i(-1, -1, -1))
		var occupant := grid.get_unit_at(cell)
		if is_instance_valid(occupant) and occupant != ignored_actor and cell != start_grid:
			return false
	return true

## The normal path is native and fast. This fallback is needed only when live
## AStar disabling hides the planning actor's origin or its first route crosses
## another occupant. It searches the existing graph without mutating it.
func _calculate_hypothetical_fallback(start_grid: Vector3i, end_grid: Vector3i, grid: GridManager, ignored_actor: TacticalUnit, checks: Variant = null) -> PackedVector3Array:
	if checks == null: checks = {}
	if not grid_to_id_map.has(start_grid) or not grid_to_id_map.has(end_grid):
		return PackedVector3Array()
	if not stoppable_cells.get(end_grid, false): return PackedVector3Array()
	if grid.map_data.surface_placement_enabled and not _planning_units_clear(grid, astar.get_point_position(grid_to_id_map[end_grid]), astar.get_point_position(grid_to_id_map[end_grid]), ignored_actor, checks): return PackedVector3Array()
	var start_id: int = grid_to_id_map[start_grid]
	var end_id: int = grid_to_id_map[end_grid]
	var open_ids: Array[int] = [start_id]
	var came_from := {}
	var costs := {start_id: 0.0}
	var estimates := {start_id: 0.0}
	while not open_ids.is_empty():
		var best_index := 0
		for index in range(1, open_ids.size()):
			var candidate_id := open_ids[index]
			var best_id := open_ids[best_index]
			var candidate_score: float = estimates.get(candidate_id, INF)
			var best_score: float = estimates.get(best_id, INF)
			if candidate_score < best_score or (is_equal_approx(candidate_score, best_score) and candidate_id < best_id):
				best_index = index
		var current_id: int = open_ids.pop_at(best_index)
		if current_id == end_id:
			return _reconstruct_hypothetical_path(came_from, current_id)
		for neighbor_id in astar.get_point_connections(current_id):
			var neighbor_cell: Vector3i = id_to_grid_map.get(neighbor_id, Vector3i(-1, -1, -1))
			if neighbor_cell == Vector3i(-1, -1, -1):
				continue
			var occupant := grid.get_unit_at(neighbor_cell)
			if is_instance_valid(occupant) and occupant != ignored_actor:
				continue
			if astar.is_point_disabled(neighbor_id) and occupant != ignored_actor:
				continue
			if not _planning_units_clear(grid, astar.get_point_position(current_id), astar.get_point_position(neighbor_id), ignored_actor, checks): continue
			var step := get_step_cost(id_to_grid_map[current_id], neighbor_cell) if grid.map_data.surface_placement_enabled else astar.get_point_position(current_id).distance_to(astar.get_point_position(neighbor_id))
			var new_cost: float = costs[current_id] + step
			if new_cost >= float(costs.get(neighbor_id, INF)):
				continue
			came_from[neighbor_id] = current_id
			costs[neighbor_id] = new_cost
			var heuristic := astar.get_point_position(neighbor_id).distance_to(astar.get_point_position(end_id))
			if grid.map_data.surface_placement_enabled:
				heuristic = 0.0
				if grid.map_data.traversal_links.is_empty():
					var delta := (neighbor_cell - end_grid).abs()
					heuristic = float(delta.x + delta.z) + (sqrt(2.0) - 2.0) * mini(delta.x, delta.z)
			estimates[neighbor_id] = new_cost + heuristic
			if neighbor_id not in open_ids:
				open_ids.append(neighbor_id)
	return PackedVector3Array()

func _planning_units_clear(grid: GridManager, from: Vector3, to: Vector3, ignored: TacticalUnit, checks: Dictionary) -> bool:
	var key := [from, to]
	if not checks.has(key): checks[key] = SurfaceNavigation.units_clear(grid, from, to, ignored)
	return checks[key]

func _reconstruct_hypothetical_path(came_from: Dictionary, end_id: int) -> PackedVector3Array:
	var ids: Array[int] = [end_id]
	var current_id := end_id
	while came_from.has(current_id):
		current_id = int(came_from[current_id])
		ids.push_front(current_id)
	var result := PackedVector3Array()
	for point_id in ids:
		result.append(astar.get_point_position(point_id))
	return result

func disable_cell(grid_pos: Vector3i) -> void:
	configure_cell(grid_pos, false, false)

## Dijkstra search respects terrain movement costs.
func get_reachable_cells(start_grid: Vector3i, movement_budget: int) -> Array[Vector3i]:
	var reachable: Array[Vector3i] = []
	if not grid_to_id_map.has(start_grid):
		return reachable
	if astar.is_point_disabled(grid_to_id_map[start_grid]):
		return reachable

	var frontier: Array = [[start_grid, 0]]
	var best_cost: Dictionary = {start_grid: 0}
	while not frontier.is_empty():
		frontier.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
		var current: Array = frontier.pop_front()
		var current_pos: Vector3i = current[0]
		var current_cost: float = current[1]
		if current_cost != best_cost[current_pos]:
			continue
		if current_pos != start_grid and stoppable_cells.get(current_pos, false):
			reachable.append(current_pos)

		var current_id: int = grid_to_id_map[current_pos]
		for neighbor_id in astar.get_point_connections(current_id):
			var neighbor: Vector3i = id_to_grid_map[neighbor_id]
			if astar.is_point_disabled(neighbor_id):
				continue
			if surface_map and surface_map.surface_placement_enabled and is_instance_valid(live_grid):
				if live_grid.is_cell_occupied(neighbor): continue
				if not SurfaceNavigation.units_clear(live_grid, astar.get_point_position(current_id), astar.get_point_position(neighbor_id), live_grid.get_unit_at(start_grid)): continue
			var new_cost = current_cost + get_step_cost(current_pos, neighbor)
			if new_cost > movement_budget or (best_cost.has(neighbor) and best_cost[neighbor] <= new_cost):
				continue
			best_cost[neighbor] = new_cost
			frontier.append([neighbor, new_cost])

	reachable.sort_custom(_cell_less)
	return reachable

func _cell_less(first: Vector3i, second: Vector3i) -> bool:
	if first.x != second.x: return first.x < second.x
	if first.y != second.y: return first.y < second.y
	return first.z < second.z

## One reverse cost field replaces repeated hypothetical route searches on the
## ordinary bidirectional surface graph. Custom traversal links keep the old path.
func planning_costs_to_goal(goal: Vector3i, wanted: Array[Vector3i], grid: GridManager, ignored: TacticalUnit) -> Dictionary:
	if not grid.map_data.surface_placement_enabled or not grid.map_data.traversal_links.is_empty() or not grid_to_id_map.has(goal): return {}
	var goal_id: int = grid_to_id_map[goal]
	if astar.is_point_disabled(goal_id) or not stoppable_cells.get(goal, false): return {}
	var goal_point := astar.get_point_position(goal_id)
	if not SurfaceNavigation.units_clear(grid, goal_point, goal_point, ignored): return {}
	if _edge_radius_revision != _graph_revision:
		_max_edge_radius = 0.0
		for point_id in id_to_grid_map:
			var from := astar.get_point_position(point_id)
			for adjacent in astar.get_point_connections(point_id):
				var to := astar.get_point_position(adjacent)
				_max_edge_radius = maxf(_max_edge_radius, Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z)))
		_edge_radius_revision = _graph_revision
	var nearby := {}
	var gap := grid.map_data.body_radius * 2.0 + grid.map_data.body_clearance
	var broad_radius := _max_edge_radius + gap + 0.0001
	for occupant in grid.occupancy_map.values():
		if not is_instance_valid(occupant) or occupant == ignored: continue
		var body_cell := grid.map_data.get_cell(occupant.grid_position)
		if body_cell == null: return {}
		var body := Vector2(body_cell.world_position.x, body_cell.world_position.z)
		for point_id in id_to_grid_map:
			var point := astar.get_point_position(point_id)
			if body.distance_squared_to(Vector2(point.x, point.z)) <= broad_radius * broad_radius: nearby[point_id] = true
	var costs := {goal_id: 0.0}
	var result := {}
	var pending := {}
	for cell in wanted: pending[cell] = true
	var heap: Array[Array] = [[0.0, goal_id]]
	var checks := {}
	while not heap.is_empty() and not pending.is_empty():
		var entry := _cost_heap_pop(heap)
		var cost: float = entry[0]
		var current: int = entry[1]
		if cost != costs.get(current, INF): continue
		var current_cell: Vector3i = id_to_grid_map[current]
		result[current_cell] = cost
		pending.erase(current_cell)
		for neighbor in astar.get_point_connections(current):
			var cell: Vector3i = id_to_grid_map[neighbor]
			var occupant := grid.get_unit_at(cell)
			if is_instance_valid(occupant) and occupant != ignored: continue
			if astar.is_point_disabled(neighbor) and occupant != ignored: continue
			# Reverse direction: terrain cost belongs to the original destination.
			# Triangle inequality: an edge cannot reach a body farther from its
			# endpoint than the longest edge plus body clearance. Near edges still
			# use the complete swept test, including vertical traversal geometry.
			if nearby.has(current) and not _planning_units_clear(grid, astar.get_point_position(neighbor), astar.get_point_position(current), ignored, checks): continue
			var next_cost := cost + get_step_cost(cell, current_cell)
			if next_cost >= float(costs.get(neighbor, INF)): continue
			costs[neighbor] = next_cost
			_cost_heap_push(heap, [next_cost, neighbor])
	return result

static func _cost_heap_less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])

static func _cost_heap_push(heap: Array[Array], entry: Array) -> void:
	heap.append(entry)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1  # the binary heap's parent index; i > 0 here, so this equals the integer quotient
		if not _cost_heap_less(heap[i], heap[parent]): break
		var value := heap[parent]
		heap[parent] = heap[i]
		heap[i] = value
		i = parent

static func _cost_heap_pop(heap: Array[Array]) -> Array:
	var first := heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty(): return first
	heap[0] = last
	var i := 0
	while i * 2 + 1 < heap.size():
		var child := i * 2 + 1
		if child + 1 < heap.size() and _cost_heap_less(heap[child + 1], heap[child]): child += 1
		if not _cost_heap_less(heap[child], heap[i]): break
		var value := heap[i]
		heap[i] = heap[child]
		heap[child] = value
		i = child
	return first
