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
	level.configure(5, 5)
	root.add_child(level)
	await create_timer(0.2).timeout

	var battle = level.battle_controller
	var turns = level.turn_manager
	var grid = battle.grid_manager
	check(turns.player_units.size() == 5 and turns.enemy_units.size() == 5, "Stress battle starts with 5v5 rosters")
	check(grid.occupancy_map.size() == 10, "Every stress-test unit has unique occupancy")
	check(turns.player_units[0].attack_range == turns.enemy_units[0].attack_range, "Both teams use the same test-battle attack range")
	var enemy_start_cells: Dictionary = {}
	for enemy in turns.enemy_units:
		enemy_start_cells[enemy] = grid.get_unit_grid(enemy)

	for player in turns.player_units:
		for enemy in turns.enemy_units:
			check(not battle.pathfinder.calculate_3d_path(grid.get_unit_grid(player), grid.get_unit_grid(enemy)).is_empty(), "Every opposing spawn pair shares a route")

	turns.end_current_turn()
	for tick in 200:
		if turns.current_phase == TurnManager.TurnPhase.PLAYER_TURN and turns.current_round == 2:
			break
		await create_timer(0.1).timeout

	check(turns.current_phase == TurnManager.TurnPhase.PLAYER_TURN and turns.current_round == 2, "All five AI units finish the expanded-map turn")
	check(grid.occupancy_map.size() == 10, "AI movement preserves unique 5v5 occupancy")
	for enemy in turns.enemy_units:
		check(grid.get_unit_grid(enemy) != enemy_start_cells[enemy], "%s moves through the shared movement gateway" % enemy.name)
		# A safe second advance can consume the remaining AP instead of Defend.
		check(enemy.stats.current_ap == 0, "%s spends its AP through shared actions" % enemy.name)
	for unit in turns.player_units + turns.enemy_units:
		check(not unit.is_moving, "%s finishes movement before the next round" % unit.name)

	level.queue_free()
	await process_frame
	print("Battlefield stress smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)
