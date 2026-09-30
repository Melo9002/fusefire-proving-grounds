extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1)
	root.add_child(level)
	await create_timer(0.15).timeout

	var battle = level.battle_controller
	var grid = battle.grid_manager
	var unit: TacticalUnit = level.turn_manager.player_units[0]
	var poses: Array[StringName] = []
	if unit.visual_adapter:
		unit.visual_adapter.presentation_state_changed.connect(func(pose: StringName): poses.append(pose))
	var bottom := Vector3i(7, 0, 6)
	var top := Vector3i(7, 2, 5)
	var platform_destination := Vector3i(8, 2, 4)

	unit.global_position = grid.grid_to_world(bottom) + Vector3.UP * unit.standing_height
	grid.update_unit_position(unit, grid.get_unit_grid(unit), bottom)
	var ladder_path = battle.pathfinder.calculate_3d_path(bottom, top)
	check(ladder_path.size() == 2, "The ladder is a direct explicit traversal link")
	check(await battle.try_move(unit, top), "A unit can climb the ladder through the normal Move action")
	check(grid.get_unit_grid(unit) == top and is_equal_approx(unit.global_position.y, 3.0), "The unit arrives on the platform's logical and world elevation")
	if unit.visual_adapter:
		check(&"climb" in poses and &"land" in poses, "Climbing selects traversal and landing presentation")

	var platform_path = battle.pathfinder.calculate_3d_path(top, platform_destination)
	check(platform_path.size() > 1, "Elevated platform cells use ordinary horizontal pathfinding")
	check(await battle.try_move(unit, platform_destination), "A unit can move normally after reaching the platform")
	check(grid.get_unit_grid(unit) == platform_destination, "Platform movement updates elevated occupancy")
	var upper_cell := Vector3i(platform_destination.x, 5, platform_destination.z)
	var upper_unit: TacticalUnit = level.turn_manager.enemy_units[0]
	upper_unit.global_position = grid.grid_to_world(upper_cell) + Vector3.UP * upper_unit.standing_height
	grid.update_unit_position(upper_unit, grid.get_unit_grid(upper_unit), upper_cell)
	check(grid.get_unit_at(platform_destination) == unit and grid.get_unit_at(upper_cell) == upper_unit, "Two units can occupy the same X/Z on different decks")
	check(not battle.pathfinder.calculate_3d_path(platform_destination, Vector3i(9, 2, 3)).is_empty(), "A unit can move beneath the suspended upper deck")

	var bottom_id: int = battle.pathfinder.grid_to_id_map[bottom]
	var top_id: int = battle.pathfinder.grid_to_id_map[top]
	battle.pathfinder.astar.disconnect_points(bottom_id, top_id)
	check(battle.pathfinder.calculate_3d_path(bottom, top).is_empty(), "The platform cannot be reached when its explicit ladder link is removed")

	level.queue_free()
	await process_frame
	print("Vertical traversal smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)
