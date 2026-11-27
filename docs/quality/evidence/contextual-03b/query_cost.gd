extends "res://tests/contextual_battlefield_test.gd"
## Matched UI query work on the same compiled Depot and actors.
func _run() -> void:
	var level := await _depot(BattlefieldCatalog.CONTEXTUAL_SHOWCASE, 16)
	if not level.battle_initialization_succeeded:
		quit(1)
		return
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var enemy: TacticalUnit = level.turn_manager.enemy_units[0]
	_place(actor, AI_START, grid)
	_place(enemy, OPPONENT, grid)
	var targets: Array[TacticalUnit] = [enemy]
	for enabled in [false, true, true, false]:
		grid.map_data.contextual_discovery_enabled = enabled
		_place(actor, DISCOVERED, grid)
		_sample("target", enabled, 128, func(): battle.query_attack(actor, enemy))
		_sample("guard-cold", enabled, 12, func():
			battle._shot_cell_cache.clear()
			battle._legal_shot_cells(actor))
		_sample("guard-warm", enabled, 128, func(): battle._legal_shot_cells(actor))
		if enabled: await _measure_slices(battle, actor)
		_place(actor, AI_START, grid)
		_sample("move-preview", enabled, 128, func():
			var query := battle.query_move(actor, DISCOVERED)
			TacticalFeedbackText.movement(query, actor, targets, grid))
	level.queue_free()
	await process_frame
	quit(0)

func _sample(label: String, enabled: bool, count: int, query: Callable) -> void:
	for warmup in 6: query.call()
	var values: Array[float] = []
	for index in count:
		var started := Time.get_ticks_usec()
		query.call()
		values.append((Time.get_ticks_usec() - started) / 1000.0)
	values.sort()
	print("[ContextualQuery] ",label," enabled=",enabled, " n=", count,
		" median=", values[ceili(count * 0.5) - 1], " p95=", values[ceili(count * 0.95) - 1],
		" p99=", values[ceili(count * 0.99) - 1], " max=", values[-1])

func _measure_slices(battle: BattleController, actor: TacticalUnit) -> void:
	battle._shot_cell_cache.clear()
	var started_at := Time.get_ticks_usec()
	var work := battle._begin_shot_coverage(actor)
	var total := 0
	var maximum := 0
	var count := 0
	var done := false
	while not done:
		var started := Time.get_ticks_usec()
		done = battle._scan_shot_coverage(work, BattleController.COVERAGE_SLICE_USEC)
		var cost := Time.get_ticks_usec() - started
		total += cost
		maximum = maxi(cost, maximum)
		count += 1
		if not done: await process_frame
	battle._finish_shot_coverage(work)
	print("[ContextualQuery] guard-sliced cells=", work.cells.size(), " slices=", count,
		" work_ms=", total / 1000.0, " longest_slice_ms=", maximum / 1000.0,
		" wall_ms=", (Time.get_ticks_usec() - started_at) / 1000.0)
