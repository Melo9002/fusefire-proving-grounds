extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func place(unit: TacticalUnit, cell: Vector3i, grid: GridManager) -> void:
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP
	grid.update_unit_position(unit, grid.get_unit_grid(unit), cell)

func _run() -> void:
	var level = load("res://levels/prototype_map/prototype_map.tscn").instantiate()
	root.add_child(level)
	await create_timer(0.15).timeout

	var battle: BattleController = level.get_node("Systems/BattleController")
	var grid = battle.grid_manager
	var trajectory := level.get_node("Visualizers/ShotTrajectoryVisualizer") as ShotTrajectoryVisualizer
	trajectory.set_debug_enabled(true)
	var attacker = battle.turn_manager.player_units[0]
	var target = battle.turn_manager.enemy_units[0]
	check(attacker.attack_range == 10, "Friendly units use the configured test range")
	check(target.attack_range == 10, "Enemies use the same configured test range")
	var mismatches := 0
	var small_block = grid.get_cell_data(Vector3i(18, 0, 14))
	place(attacker, Vector3i(17, 0, 14), grid)
	place(target, Vector3i(19, 0, 14), grid)
	check(battle.evaluate_attack(attacker, target).hit_chance == 50, "Small authored block permits a 50 percent shot")
	check(level.get_node("Environment/Obstacles/CentralLowBlock").size.y == small_block.cover_height, "Small block height matches metadata")
	# Sample preview parity across ground and elevated cells with full cover enabled.
	small_block.blocks_line_of_sight = true
	grid.map_data.rebuild_los_index()
	var walkable_cells: Array[Vector3i] = []
	for candidate in grid.map_data.cells:
		if grid.get_cell_data(candidate).walkable:
			walkable_cells.append(candidate)
	for source_index in range(0, walkable_cells.size(), 29):
		var source = walkable_cells[source_index]
		place(attacker, source, grid)
		for destination_index in range(0, walkable_cells.size(), 31):
			var destination = walkable_cells[destination_index]
			if source == destination:
				continue
			place(target, destination, grid)
			var floor_visible = CombatRules.has_line_of_sight_to_position(attacker, grid.grid_to_world(destination), grid, battle.get_world_3d())
			var unit_visible = CombatRules.has_line_of_sight_to_position(attacker, target.global_position, grid, battle.get_world_3d())
			if floor_visible != unit_visible:
				if mismatches == 0:
					print("First LOS mismatch: ", source, " -> ", destination, " floor=", floor_visible, " unit=", unit_visible)
				mismatches += 1
	check(mismatches == 0, "Floor and unit LOS must agree across sampled map layers: %d mismatches" % mismatches)
	var corner_blocker = grid.get_cell_data(Vector3i(2, 0, 2))
	corner_blocker.blocks_line_of_sight = true
	corner_blocker.cover_height = 2.0
	grid.map_data.rebuild_los_index()
	place(attacker, Vector3i(1, 0, 2), grid)
	place(target, Vector3i(2, 0, 1), grid)
	check(battle.evaluate_attack(attacker, target).is_legal, "Touching a full-cover corner alone permits a shot")
	place(target, Vector3i(3, 0, 2), grid)
	check(not battle.evaluate_attack(attacker, target).is_legal, "Crossing the interior of full cover blocks a shot")
	corner_blocker.blocks_line_of_sight = false
	corner_blocker.cover_height = 0.0
	grid.map_data.rebuild_los_index()

	# The west low barrier protects only the side facing the attacker.
	place(attacker, Vector3i(9, 0, 6), grid)
	place(target, Vector3i(9, 0, 9), grid)
	var low_cover = battle.evaluate_attack(attacker, target)
	check(low_cover.is_legal, "Low cover keeps the attack legal")
	check(low_cover.hit_chance == 50, "Directional low cover gives 50 percent hit chance")
	check(low_cover.cover_type == MapCellData.CoverType.LOW, "Evaluation reports low cover")
	var low_cover_cell = Vector3i(9, 0, 8)
	check(not battle.pathfinder.astar.is_point_disabled(battle.pathfinder.grid_to_id_map[low_cover_cell]), "Low cover remains connected for vault paths")
	check(not grid.get_cell_data(low_cover_cell).can_stop, "Units cannot end movement on low cover")
	check(CombatRules.has_line_of_sight_to_position(attacker, target.global_position, grid, battle.get_world_3d()), "Unwalkable low cover does not block a shot")
	check(CombatRules.has_line_of_sight_to_position(attacker, grid.grid_to_world(Vector3i(9, 0, 9)), grid, battle.get_world_3d()), "Attack preview and target checks share line of sight")

	place(attacker, Vector3i(9, 0, 10), grid)
	var wrong_side = battle.evaluate_attack(attacker, target)
	check(wrong_side.is_legal and wrong_side.hit_chance == 100, "Cover does not protect the wrong side")

	# Intervening geometry affects accuracy even when it is not the target's directional cover.
	var corridor_cells: Array[MapCellData] = [
		grid.get_cell_data(Vector3i(4, 0, 5)),
		grid.get_cell_data(Vector3i(5, 0, 5)),
		grid.get_cell_data(Vector3i(6, 0, 5)),
	]
	var saved_cover_types: Array[int] = []
	var saved_heights: Array[float] = []
	for cell in corridor_cells:
		saved_cover_types.append(cell.cover_type)
		saved_heights.append(cell.cover_height)
		cell.cover_type = MapCellData.CoverType.NONE
		cell.cover_height = 0.0
	var intervening := corridor_cells[1]
	place(attacker, Vector3i(3, 0, 5), grid)
	place(target, Vector3i(7, 0, 5), grid)
	intervening.cover_type = MapCellData.CoverType.LOW
	intervening.cover_height = 1.0
	var obstructed := battle.evaluate_attack(attacker, target)
	check(obstructed.is_legal and obstructed.hit_chance < 100, "An intervening waist-high barrier reduces accuracy")
	check(obstructed.visibility_fraction > 0.0 and obstructed.visibility_fraction < 1.0, "Attack evaluation reports partial target visibility")
	check(obstructed.aim_point.y > intervening.world_position.y + intervening.cover_height, "The selected aim point clears the intervening barrier")
	for index in corridor_cells.size():
		corridor_cells[index].cover_type = saved_cover_types[index]
		corridor_cells[index].cover_height = saved_heights[index]

	attacker.attack_range = 6
	place(attacker, Vector3i(14, 0, 8), grid)
	place(target, Vector3i(18, 0, 8), grid)
	var full_cover = battle.evaluate_attack(attacker, target)
	check(not full_cover.is_legal and full_cover.reason == "Blocked", "Full cover makes the shot illegal")
	trajectory.draw_trajectory(CombatRules.get_shot_origin(attacker, grid), CombatRules.get_shot_destination(target, grid), full_cover)
	check(trajectory.mesh_instance.mesh != null and trajectory.last_reason == "Blocked", "Debug trajectory draws even when a shot is illegal")
	check(trajectory.last_origin.is_equal_approx(CombatRules.get_shot_origin(attacker, grid)), "Debug trajectory shares the combat-rule origin")
	check(trajectory.blocker_marker.mesh != null, "Blocked shots highlight the responsible LOS cell")
	check(trajectory.last_blocking_cell != null, "Blocked shots retain the responsible LOS cell")
	if trajectory.last_blocking_cell != null:
		check(trajectory.last_blocking_cell.grid_position == Vector3i(16, 0, 8), "LOS highlight reports the blocking cell coordinate")

	place(attacker, Vector3i(14, 0, 11), grid)
	place(target, Vector3i(18, 0, 11), grid)
	var wall_edge = battle.evaluate_attack(attacker, target)
	check(wall_edge.is_legal and wall_edge.hit_chance == 100, "A shot past the wall edge remains legal")
	trajectory.clear()
	check(trajectory.mesh_instance.mesh == null, "Debug trajectory can be cleared with attack mode")
	check(trajectory.blocker_marker.mesh == null and trajectory.last_blocking_cell == null, "Clearing the shot also clears its blocker highlight")

	check(not AttackActionResult.roll_hits(75.0, 50), "A roll above hit chance resolves as a miss")
	check(AttackActionResult.roll_hits(25.0, 50), "A roll below hit chance resolves as a hit")

	level.queue_free()
	await process_frame
	print("Combat cover smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)
