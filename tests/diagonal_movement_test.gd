extends SceneTree

var failures := 0

func _initialize() -> void:
	var graph := Pathfinder.new()
	for x in 4:
		for z in 4:
			graph.add_walkable_cell(Vector3i(x, 0, z), Vector3(x, 0, z))
	var start := Vector3i.ZERO
	var end := Vector3i(1, 0, 1)
	check(graph.calculate_3d_path(start, end).size() == 2, "Open diagonal is direct")
	check(not graph.get_reachable_cells(start, 1).has(end), "Diagonal costs more than one point")
	check(graph.get_reachable_cells(start, 2).has(end), "Diagonal fits two-point budget")
	check(not graph.get_reachable_cells(start, 4).has(Vector3i(3, 0, 3)), "Three diagonals cost over four")
	graph.disable_cell(Vector3i.RIGHT)
	check(graph.calculate_3d_path(start, end).size() == 3, "Single corner blocker forces a detour")
	graph.disable_cell(Vector3i.BACK)
	check(graph.calculate_3d_path(start, end).is_empty(), "Touching full blocks seal the corner")
	graph.configure_cell(Vector3i.RIGHT, true, true)
	graph.configure_cell(Vector3i.BACK, true, true)
	check(graph.calculate_3d_path(start, end).size() == 2, "Reopening sides restores diagonal")
	graph.configure_cell(Vector3i.RIGHT, true, false, 3)
	check(graph.calculate_3d_path(start, end).size() == 3, "Low cover prevents corner clipping")
	graph.add_walkable_cell(Vector3i(4, 1, 4), Vector3(4, 0.5, 4))
	check(graph.calculate_3d_path(Vector3i(3, 0, 3), Vector3i(4, 1, 4)).is_empty(), "No automatic diagonal elevation links")
	graph.configure_cell(Vector3i.RIGHT, true, true)
	# Every range result must have a route affordable under the same costs.
	for cell in graph.get_reachable_cells(start, 4):
		var points := graph.astar.get_id_path(graph.grid_to_id_map[start], graph.grid_to_id_map[cell])
		var cost := 0.0
		for i in range(1, points.size()):
			cost += graph.get_step_cost(graph.id_to_grid_map[points[i - 1]], graph.id_to_grid_map[points[i]])
		check(cost <= 4.00001, "Range and chosen path agree")
	print("[DiagonalMovement] %d failure(s)" % failures)
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
