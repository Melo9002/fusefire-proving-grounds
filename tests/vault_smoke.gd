extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var level = load("res://levels/prototype_map/prototype_map.tscn").instantiate()
	root.add_child(level)
	await create_timer(0.15).timeout

	var battle: BattleController = level.get_node("Systems/BattleController")
	var grid = battle.grid_manager
	var unit = battle.turn_manager.player_units[0]
	var old_cell = grid.world_to_grid(unit.global_position)
	var start = Vector3i(17, 0, 14)
	var cover = Vector3i(18, 0, 14)
	var destination = Vector3i(19, 0, 14)
	unit.global_position = grid.grid_to_world(start) + Vector3.UP * unit.standing_height
	grid.update_unit_position(unit, old_cell, start)

	var reachable_with_two = battle.pathfinder.get_reachable_cells(start, 2)
	var reachable_with_three = battle.pathfinder.get_reachable_cells(start, 3)
	check(not reachable_with_two.has(destination), "Two movement points cannot cross and land beyond low cover")
	check(reachable_with_three.has(destination), "Three movement points can cross and land beyond low cover")
	check(not reachable_with_three.has(cover), "Low cover is never a valid destination")
	var cover_visualizer: CoverVisualizer = level.get_node("Visualizers/CoverVisualizer")
	cover_visualizer.draw_for_cells([start, destination])
	check(cover_visualizer.low_indicator_count == 2, "Both protected tile edges receive low-cover indicators")

	var path = battle.pathfinder.calculate_3d_path(start, destination)
	check(path.size() == 3, "Vault path crosses the low-cover cell")
	var animated_path = battle._build_movement_path(unit, path)
	check(is_equal_approx(animated_path[1].y, 2.0), "Vault waypoint rises over one-meter cover")
	check(is_equal_approx(animated_path[2].y, 1.0), "Path returns to standing height")
	var ap_before_move: int = unit.stats.current_ap
	check(await battle.try_move(unit, destination), "Move action can vault low cover")
	check(unit.stats.current_ap == ap_before_move - 1, "Vault move costs one AP regardless of configured base AP")
	check(grid.world_to_grid(unit.global_position) == destination, "Unit lands beyond low cover")

	var full_cover = grid.get_cell_data(cover)
	full_cover.walkable = false
	full_cover.can_stop = false
	battle.pathfinder.configure_cell(cover, false, false)
	check(battle.pathfinder.calculate_3d_path(start, destination).size() > 3, "Full cover cannot be crossed directly")

	level.queue_free()
	await process_frame
	print("Vault smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)
