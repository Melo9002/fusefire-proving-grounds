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
var grid_to_id_map: Dictionary = {}
var id_to_grid_map: Dictionary = {}
var movement_costs: Dictionary = {}
var stoppable_cells: Dictionary = {}
var next_id: int = 0
var max_step_levels: int = 1

const DIRECTIONS: Array[Vector3i] = [
	Vector3i.RIGHT,
	Vector3i.LEFT,
	Vector3i.FORWARD,
	Vector3i.BACK,
]

func clear() -> void:
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
			var clear := _clear_for_diagonal(a) and _clear_for_diagonal(b) and _clear_for_diagonal(c) and _clear_for_diagonal(d)
			for pair in [[a, d], [b, c]]:
				if not grid_to_id_map.has(pair[0]) or not grid_to_id_map.has(pair[1]):
					continue
				var first: int = grid_to_id_map[pair[0]]
				var second: int = grid_to_id_map[pair[1]]
				if clear:
					astar.connect_points(first, second)
				elif astar.are_points_connected(first, second):
					astar.disconnect_points(first, second)

func get_step_cost(from_cell: Vector3i, to_cell: Vector3i) -> float:
	return astar._compute_cost(grid_to_id_map[from_cell], grid_to_id_map[to_cell]) * float(movement_costs.get(to_cell, 1))

func connect_cells(from_cell: Vector3i, to_cell: Vector3i, bidirectional: bool = true) -> bool:
	if not grid_to_id_map.has(from_cell) or not grid_to_id_map.has(to_cell):
		return false
	astar.connect_points(grid_to_id_map[from_cell], grid_to_id_map[to_cell], bidirectional)
	return true

func calculate_3d_path(start_grid: Vector3i, end_grid: Vector3i) -> PackedVector3Array:
	if not grid_to_id_map.has(start_grid) or not grid_to_id_map.has(end_grid):
		return PackedVector3Array()
	if not stoppable_cells.get(end_grid, false):
		return PackedVector3Array()

	var start_id = grid_to_id_map[start_grid]
	var end_id = grid_to_id_map[end_grid]
	return astar.get_point_path(start_id, end_id)

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
			var new_cost = current_cost + get_step_cost(current_pos, neighbor)
			if new_cost > movement_budget or (best_cost.has(neighbor) and best_cost[neighbor] <= new_cost):
				continue
			best_cost[neighbor] = new_cost
			frontier.append([neighbor, new_cost])

	return reachable
