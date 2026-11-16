extends SceneTree
## Regressions from the combat audit: sample parity, nearest blockers and Move state.
var failures := 0
var level: BattleLevel
var grid: GridManager
var actor: TacticalUnit
var enemy: TacticalUnit

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battle_seed = 1604
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.player_count = 1
	config.enemy_count = 1
	level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Regression starts a real validated battle")
	if not level.battle_initialization_succeeded:
		level.free()
		quit(1)
		return
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	grid = level.battle_controller.grid_manager
	actor = level.turn_manager.player_units[0]
	enemy = level.turn_manager.enemy_units[0]
	var battle := level.battle_controller
	var hostiles: Array[TacticalUnit] = [enemy]
	var policy := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.NORMAL)

	_reset(Vector3i(1, 0, 5), Vector3i(9, 2, 5))
	_solid(Vector3i(5, 0, 5), 2, MapCellData.CoverType.FULL)
	var shot := battle.query_attack(actor, enemy)
	check(shot.is_legal() and shot.hit_chance == 50 and is_equal_approx(shot.visibility_fraction, 0.2), "Raised target has one visible sample and unchanged 50 percent chance")
	check(battle._legal_shot_cells(actor).has(enemy.grid_position), "Painted attack/Guard range includes a genuinely shootable raised target")
	var score := AIPositionScorer.evaluate(actor, actor.grid_position, actor.grid_position, Vector3i(-1, -1, -1), 0, false, hostiles, grid, policy, null)
	check(score.firing > 0, "AI destination scoring recognizes the same raised firing opportunity")
	enemy.standing_height = 0.5
	check(not battle.query_attack(actor, enemy).is_legal() and not battle._legal_shot_cells(actor).has(enemy.grid_position), "Occupied-cell range uses the actual target's body height")

	_reset(Vector3i(1, 0, 5), Vector3i(9, 0, 5))
	_solid(Vector3i(2, 0, 5), 1.15, MapCellData.CoverType.LOW)
	check(not battle.query_attack(actor, enemy).is_legal(), "Low barrier near the shooter blocks all samples")
	check(not battle._legal_shot_cells(actor).has(enemy.grid_position), "Painted range excludes the blocked low-barrier lane")
	score = AIPositionScorer.evaluate(actor, actor.grid_position, actor.grid_position, Vector3i(-1, -1, -1), 0, false, hostiles, grid, policy, null)
	check(is_zero_approx(score.firing), "AI does not reward a blocked low-barrier firing lane")
	_reset(Vector3i(1, 0, 5), Vector3i(9, 0, 5))
	_solid(Vector3i(8, 0, 5), 1.15, MapCellData.CoverType.LOW)
	check(not CombatRules.evaluate_attack(enemy, actor, grid, actor.get_world_3d()).is_legal, "Reverse low barrier blocks the incoming threat")
	score = AIPositionScorer.evaluate(actor, actor.grid_position, actor.grid_position, Vector3i(-1, -1, -1), 0, false, hostiles, grid, policy, null)
	check(is_zero_approx(score.exposure), "AI exposure uses body samples for incoming shots too")
	var advisor := AIController.new()
	advisor.unit = actor
	advisor.turn_manager = level.turn_manager
	advisor.battle_controller = battle
	check(is_zero_approx(advisor._advance_exposure(actor.grid_position)), "Safe-advance gating uses the same incoming shot visibility as AI scoring")
	advisor.free()

	_reset(Vector3i(9, 0, 5), Vector3i(1, 0, 5))
	_solid(Vector3i(3, 0, 5), 3, MapCellData.CoverType.FULL)
	_solid(Vector3i(7, 0, 5), 3, MapCellData.CoverType.FULL)
	shot = battle.query_attack(actor, enemy)
	check(not shot.is_legal() and shot.evaluation.blocking_cell.grid_position == Vector3i(7, 0, 5), "Blocked-shot evidence reports the nearer wall, not cell traversal order")
	var near := grid.get_cell_data(Vector3i(7, 0, 5))
	battle.shot_trajectory_visualizer.draw_trajectory(CombatRules.get_shot_origin(actor, grid), shot.aim_point, shot.evaluation, true)
	check(battle.shot_trajectory_visualizer.last_blocking_cell == near, "The real feedback marker consumes the nearest-blocker result")
	near.authored_shot_parts.assign([AABB(near.world_position + Vector3(-0.4, 0, -0.4), Vector3(0.2, 3, 0.8)), AABB(near.world_position + Vector3(0.2, 0, -0.4), Vector3(0.2, 3, 0.8))])
	check(battle.query_attack(actor, enemy).evaluation.blocking_cell == near, "Nearest-blocker selection respects compound sub-cell parts")
	_place(actor, Vector3i(1, 0, 5))
	_place(enemy, Vector3i(9, 0, 5))
	check(battle.query_attack(actor, enemy).evaluation.blocking_cell.grid_position == Vector3i(3, 0, 5), "Reversing the shot reverses which wall is nearest")
	_reset(Vector3i(0, 0, 0), Vector3i(1, 0, 1))
	_solid(Vector3i(1, 0, 0), 2, MapCellData.CoverType.FULL)
	_solid(Vector3i(0, 0, 1), 2, MapCellData.CoverType.FULL)
	var origin := CombatRules.get_shot_origin(actor, grid)
	var end := CombatRules.get_shot_destination(enemy, grid)
	var seam := CombatRules.get_blocking_cell(origin, end, grid)
	grid.map_data.los_blocking_cells.reverse()
	check(seam != null and CombatRules.get_blocking_cell(origin, end, grid) == seam, "Diagonal seam blocking and tie diagnostics do not depend on candidate insertion order")

	_reset(Vector3i(2, 0, 5), Vector3i(7, 0, 5))
	actor.shield_capability = ShieldCapability.new()
	var service := battle.action_service
	check(await service.submit_shield(service.make_shield_request(actor, enemy, TacticalActionRequest.Source.PLAYER), true) != null, "Enter actual Shield stance")
	var destination := Vector3i(2, 0, 6)
	var move := battle.query_move(actor, destination)
	var before := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	var route_shot := CombatRules.evaluate_attack_at_cell(enemy, actor, destination, grid, actor.get_world_3d())
	var destination_shot := CombatRules.evaluate_attack_after_move(enemy, actor, destination, grid, actor.get_world_3d())
	check(route_shot.shield_applied and route_shot.hit_chance == 80, "During-route checkpoint semantics retain active Shield")
	check(not destination_shot.shield_applied and destination_shot.hit_chance == 100 and is_equal_approx(destination_shot.shield_damage_multiplier, 1.0), "Completed-destination prediction excludes canceled Shield")
	var description := TacticalFeedbackText.movement(move, actor, hostiles, grid)
	check(description.contains("Shield canceled"), "Move feedback explains loss of Shield")
	check(before == BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager), "Preview leaves live stance, RNG-independent state and occupancy untouched")
	check(await service.submit_move(service.make_move_request(actor, destination, TacticalActionRequest.Source.PLAYER), true) != null, "Commit the advertised move")
	check(not actor.tactical_state.is_shielding, "Completed Move clears Shield")
	var actual := CombatRules.evaluate_attack(enemy, actor, grid, actor.get_world_3d())
	check(actual.hit_chance == destination_shot.hit_chance and actual.shield_applied == destination_shot.shield_applied and actual.shield_damage_multiplier == destination_shot.shield_damage_multiplier, "Pure destination prediction matches the actual completed Move")
	level.queue_free()
	await process_frame
	await process_frame
	print("Combat prediction consistency: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _reset(source: Vector3i, target: Vector3i) -> void:
	grid.cell_size = 1
	grid.elevation_step = 1
	grid.map_floor.size = Vector3(12, 0.2, 12)
	grid.map_floor.position.y = -0.1
	grid.map_data = TacticalMapBuilder.generate(12, 12, 1, 1604, 1)
	grid.occupancy_map.clear()
	for unit in [actor, enemy]:
		unit.standing_height = 1
		unit.tactical_state.reset()
		unit.shield_capability = null
		unit.attack_range = 20
		unit.stats.set_available_ap_for_setup(3)
		unit.stats.current_supply_points = 4
	for cell in [source, target]:
		if not grid.map_data.has_cell(cell): grid.map_data.add_cell(MapCellData.new(cell, grid.grid_to_world(cell)))
	_place(actor, source)
	_place(enemy, target)
	MapGraphBuilder.build(grid.map_data, level.battle_controller.pathfinder)

func _place(unit: TacticalUnit, cell: Vector3i) -> void:
	grid.update_unit_position(unit, unit.grid_position, cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

func _solid(cell: Vector3i, height: float, kind: MapCellData.CoverType) -> void:
	var data := grid.get_cell_data(cell)
	data.cover_type = kind
	data.cover_height = height
	data.blocks_line_of_sight = kind == MapCellData.CoverType.FULL
	data.walkable = false
	data.can_stop = false
	grid.map_data.rebuild_los_index()
