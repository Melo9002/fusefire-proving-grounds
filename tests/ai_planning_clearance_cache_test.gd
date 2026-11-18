extends SceneTree
## Reusing work must never reuse another body layout's clearance.
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.player_count = 1
	config.enemy_count = 1
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await process_frame
	check(level.battle_initialization_succeeded, "Current Depot initializes")
	if not level.battle_initialization_succeeded:
		level.queue_free()
		quit(1)
		return
	var grid := level.battle_controller.grid_manager
	var graph := level.battle_controller.pathfinder
	var actor := level.turn_manager.player_units[0]
	var blocker := level.turn_manager.enemy_units[0]
	var start := Vector3i(1, 0, 16)
	var goal := Vector3i(1, 0, 19)
	grid.update_unit_position(actor, actor.grid_position, start)
	grid.update_unit_position(blocker, blocker.grid_position, Vector3i(1, 0, 22))
	var wanted: Array[Vector3i] = [start, start + Vector3i.RIGHT, start + Vector3i.BACK, goal]
	graph.configure_cell(Vector3i(1, 0, 18), true, true, 3)
	var field := graph.planning_costs_to_goal(goal, wanted, grid, actor)
	for cell in wanted:
		var route := graph.calculate_path_with_occupancy(cell, goal, grid, actor)
		var expected := graph.get_path_cost(route, level.battle_controller.world_to_grid) if not route.is_empty() else INF
		check(is_equal_approx(float(field.get(cell, INF)), expected), "Goal field matches occupancy-aware route cost at %s" % cell)
	graph.configure_cell(Vector3i(1, 0, 18), true, true, 1)
	var cache := {}
	var first := graph.calculate_path_with_occupancy(start, goal, grid, actor, cache)
	check(not first.is_empty() and cache.size() > 1, "Live path populates bounded reusable clearance work")
	check(graph.calculate_path_with_occupancy(start, goal, grid, actor, cache) == first, "Unchanged layout retains the identical route")
	grid.update_unit_position(blocker, blocker.grid_position, Vector3i(1, 0, 18))
	var blocked := graph.calculate_path_with_occupancy(start, goal, grid, actor, cache)
	check(blocked == graph.calculate_path_with_occupancy(start, goal, grid, actor) and blocked != first, "Moved blocker invalidates prior clear edges")
	var changed_field := graph.planning_costs_to_goal(goal, wanted, grid, actor)
	for cell in wanted:
		var route := graph.calculate_path_with_occupancy(cell, goal, grid, actor)
		var expected := graph.get_path_cost(route, level.battle_controller.world_to_grid) if not route.is_empty() else INF
		check(is_equal_approx(float(changed_field.get(cell, INF)), expected), "Goal field retains occupied-body costs at %s" % cell)
	for i in range(1, blocked.size()):
		check(SurfaceNavigation.units_clear(grid, blocked[i-1], blocked[i], actor), "Detour retains independent swept-body clearance")
	var old_gap := grid.map_data.body_clearance
	grid.map_data.body_clearance += 0.1
	check(graph.calculate_path_with_occupancy(start, goal, grid, actor, cache) == graph.calculate_path_with_occupancy(start, goal, grid, actor), "Changed body profile uses fresh clearance")
	grid.map_data.body_clearance = old_gap
	check(graph.calculate_path_with_occupancy(start, goal, grid, blocker, cache) == graph.calculate_path_with_occupancy(start, goal, grid, blocker), "Ignored-actor changes cannot reuse an earlier body's permission")
	grid.unregister_unit_at(blocker.grid_position)
	check(graph.calculate_path_with_occupancy(start, goal, grid, actor, cache) == first, "Removing a blocker releases its obsolete clearance")
	graph.clear()
	check(graph._point_cells.is_empty() and graph.calculate_path_with_occupancy(start, goal, grid, actor, cache).is_empty(), "Graph rebuild clears exact-point lookup and invalidates cached work")
	level.queue_free()
	await process_frame
	print("Planning clearance cache: %d failures" % failures)
	quit(1 if failures else 0)
