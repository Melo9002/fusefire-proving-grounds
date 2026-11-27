extends "res://tests/contextual_firing_bay_test.gd"
## Matched read-only query measurements on the same battle and actor.

func _run() -> void:
	var level := await _level(1)
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var enemy: TacticalUnit = level.turn_manager.enemy_units[0]
	var tile := actor.grid_position
	var offset: Vector3 = grid.map_data.contextual_steps[tile]
	_timing("contextual-target", func(): return battle.query_attack(actor, enemy))
	grid.map_data.contextual_steps.erase(tile)
	_timing("blocked-direct", func(): return battle.query_attack(actor, enemy))
	grid.map_data.contextual_steps[tile] = offset
	var previous := tile + Vector3i(0, 0, -1)
	grid.update_unit_position(actor, tile, previous)
	var move := battle.query_move(actor, tile)
	var enemies: Array[TacticalUnit] = [enemy]
	_timing("contextual-arrival", func(): return TacticalFeedbackText.movement_options(move, actor, enemies, grid))
	grid.map_data.contextual_steps.erase(tile)
	_timing("blocked-arrival", func(): return TacticalFeedbackText.movement_options(move, actor, enemies, grid))
	level.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _timing(label: String, query: Callable) -> void:
	for warmup in 8: query.call()
	var values: Array[float] = []
	for index in 128:
		var start := Time.get_ticks_usec()
		query.call()
		values.append(float(Time.get_ticks_usec() - start) / 1000.0)
	values.sort()
	print("[BayQuery] ",label," samples=",values.size()," p95_ms=",values[121]," max_ms=",values[-1])
