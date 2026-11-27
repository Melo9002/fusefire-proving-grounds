extends SceneTree
## Same post-ray hover and targeted-query workloads on baseline and review builds.

const Battle := preload("res://levels/prototype_map/prototype_map.tscn")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _measure(BattlefieldCatalog.SERVICE_DEPOT, 16, Vector3i(25, 0, 6), Vector3i(26, 0, 6), Vector3i(30, 0, 8))
	await _measure(BattlefieldCatalog.TACTICAL_TEST_RANGE, 1, Vector3i(6, 0, 15), Vector3i(6, 3, 12), Vector3i(30, 8, 30))
	quit()

func _measure(id: StringName, seed_value: int, start: Vector3i, valid: Vector3i, denied: Vector3i) -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(id)
	config.battle_seed = seed_value
	config.player_count = 3
	config.enemy_count = 3
	config.engagement_policy = CombatRules.EngagementPolicy.HEAD_CORE_SYMMETRIC
	var level := Battle.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	grid.update_unit_position(actor, actor.grid_position, start)
	actor.global_position = grid.grid_to_world(start) + Vector3.UP * actor.standing_height
	battle.toggle_move_mode()
	var accepted := battle.query_move(actor, valid)
	var rejected := battle.query_move(actor, denied)
	if not accepted.is_legal() or rejected.is_legal():
		push_error("Timing fixtures do not have one valid and one invalid stop")
		quit(1)
		return
	var bad_tile := grid.get_cell_data(denied)
	var denied_point := bad_tile.support_center if bad_tile else grid.grid_to_world(denied)
	var good_hit := {"grid_position": valid, "position": grid.grid_to_world(valid)}
	var bad_hit := {"grid_position": denied, "position": denied_point}
	var alternating := [good_hit, bad_hit]
	var state := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	var rng := battle.action_service.get_combat_rng_state()
	var row := {
		"map": String(id), "seed": seed_value, "start": str(start), "valid": str(valid), "denied": str(denied),
		"same_valid_hover": _sample(func(_index): battle._update_movement_preview(good_hit)),
		"same_invalid_hover": _sample(func(_index): battle._update_movement_preview(bad_hit)),
		"alternating_hover": _sample(func(index): battle._update_movement_preview(alternating[index % 2])),
		"targeted_valid": _sample(func(_index): battle.query_move(actor, valid)),
		"targeted_invalid": _sample(func(_index): battle.query_move(actor, denied)),
	}
	print("[MoveReadabilityTiming] ", JSON.stringify(row))
	if state != BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager) or rng != battle.action_service.get_combat_rng_state():
		push_error("Preview performance changed tactical state")
		quit(1)
	level.queue_free()
	await process_frame

func _sample(operation: Callable) -> Array[int]:
	var elapsed: Array[int] = []
	for index in 136:
		var start := Time.get_ticks_usec()
		operation.call(index)
		if index >= 8: elapsed.append(Time.get_ticks_usec() - start)
	elapsed.sort()
	return [elapsed[elapsed.size() / 2], elapsed[ceili(elapsed.size() * 0.95) - 1]]
