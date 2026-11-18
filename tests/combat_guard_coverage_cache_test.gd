extends SceneTree
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func expected(battle: BattleController, actor: TacticalUnit) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for cell: Vector3i in battle.pathfinder.grid_to_id_map:
		if battle.pathfinder.astar.is_point_disabled(battle.pathfinder.grid_to_id_map[cell]): continue
		if CombatRules.has_firing_lane_to_cell(actor, cell, battle.grid_manager): result.append(cell)
	result.sort_custom(func(a: Vector3i,b: Vector3i): return a.x < b.x or (a.x == b.x and (a.z < b.z or (a.z == b.z and a.y < b.y))))
	return result
func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	config.player_count = 1
	config.enemy_count = 1
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await process_frame
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var actor := level.turn_manager.player_units[0]
	var target := level.turn_manager.enemy_units[0]
	grid.update_unit_position(actor, actor.grid_position, Vector3i(1,0,16))
	grid.update_unit_position(target, target.grid_position, Vector3i(1,0,20))
	actor.attack_range = 10
	var rng := battle.action_service.get_combat_rng_state()
	var before := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	var cells := battle._legal_shot_cells(actor)
	check(cells == expected(battle, actor) and cells.has(Vector3i(1,0,19)), "Initial coverage agrees with real geometry")
	check(battle._legal_shot_cells(actor) == cells and rng == battle.action_service.get_combat_rng_state(), "Repeated overlay query is read-only and agrees")
	check(before == BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager), "Caching consumes no tactical state")
	var signature: Array = battle._shot_cell_cache[actor.get_instance_id()].signature.duplicate(true)
	grid.update_unit_position(target, target.grid_position, Vector3i(1,0,21))
	check(battle._legal_shot_cells(actor) == expected(battle, actor) and battle._shot_cell_cache[actor.get_instance_id()].signature == signature, "Equal-height movement preserves geometric coverage")
	target.standing_height += 0.2
	check(battle._legal_shot_cells(actor) == expected(battle, actor) and battle._shot_cell_cache[actor.get_instance_id()].signature != signature, "Different target height invalidates coverage")
	actor.attack_range = 3
	check(battle._legal_shot_cells(actor) == expected(battle, actor) and battle._legal_shot_cells(actor).size() < cells.size(), "Range changes invalidate coverage")
	actor.attack_range = 10
	var obstacle := MapCellData.new(Vector3i(1,0,18), grid.grid_to_world(Vector3i(1,0,18)))
	obstacle.grid_position = Vector3i(1,0,18)
	obstacle.blocks_line_of_sight = true
	obstacle.cover_height = 4
	var point := grid.grid_to_world(obstacle.grid_position)
	obstacle.authored_shot_bounds = AABB(point - Vector3(0.45,0,0.45), Vector3(0.9,4,0.9))
	grid.map_data.add_shot_obstacle(obstacle)
	check(battle._legal_shot_cells(actor) == expected(battle, actor) and not battle._legal_shot_cells(actor).has(Vector3i(1,0,19)), "Added geometry invalidates cached clear lanes")
	grid.update_unit_position(actor, actor.grid_position, Vector3i(2,0,16))
	check(battle._legal_shot_cells(actor) == expected(battle, actor), "Changed source invalidates coverage")
	grid.map_data.rebuild_los_index()
	check(battle._legal_shot_cells(actor) == expected(battle, actor), "LOS rebuild invalidates coverage")
	actor.carried_unit = target
	check(battle._legal_shot_cells(actor).is_empty(), "Carrying invalidates an ordinary firing overlay")
	actor.carried_unit = null
	level.queue_free()
	await process_frame
	print("Guard coverage cache: %d failures" % failures)
	quit(1 if failures else 0)
