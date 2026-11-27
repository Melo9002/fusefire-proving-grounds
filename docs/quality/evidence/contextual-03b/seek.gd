extends "res://tests/contextual_firing_bay_test.gd"
## Locates a start tile from which ordinary planning discovers a surveyed angle.
const WITNESSES := [
	[Vector3i(16, 0, 22), Vector3i(11, 0, 25)],
	[Vector3i(9, 0, 20), Vector3i(16, 0, 20)],
	[Vector3i(13, 0, 23), Vector3i(20, 0, 23)],
	[Vector3i(13, 0, 24), Vector3i(6, 0, 24)],
	[Vector3i(13, 0, 27), Vector3i(20, 0, 27)],
	[Vector3i(17, 0, 27), Vector3i(10, 0, 27)],
	[Vector3i(23, 0, 15), Vector3i(30, 0, 15)],
	[Vector3i(24, 0, 22), Vector3i(31, 0, 22)],
	[Vector3i(27, 0, 15), Vector3i(20, 0, 15)],
	[Vector3i(28, 0, 20), Vector3i(21, 0, 20)],
	[Vector3i(28, 0, 27), Vector3i(35, 0, 27)],
	[Vector3i(32, 0, 25), Vector3i(25, 0, 25)],
]
const STEPS := [
	Vector3i.RIGHT, Vector3i.LEFT, Vector3i.FORWARD, Vector3i.BACK,
	Vector3i(1, 0, 1), Vector3i(-1, 0, -1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1),
]

func _run() -> void:
	Engine.time_scale = 8.0
	for witness in WITNESSES:
		for delta in STEPS:
			if await _seek(witness[0] + delta, witness[0], witness[1]):
				quit(0)
				return
	quit(1)

func _depot() -> BattleLevel:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battle_seed = 16
	config.select_battlefield(BattlefieldCatalog.CONTEXTUAL_DEPOT)
	config.player_count = 1
	config.enemy_count = 1
	config.difficulty = AIDifficultyPolicy.Tier.HARD
	config.enemy_commander = AICommanderPolicy.Profile.CAUTIOUS
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1)
	var level := Scene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	for frame in 4: await process_frame
	return level

func _place(actor: TacticalUnit, cell: Vector3i, grid: GridManager) -> void:
	grid.update_unit_position(actor, actor.grid_position, cell)
	actor.global_position = grid.grid_to_world(cell) + Vector3.UP * actor.standing_height

func _seek(start: Vector3i, stop: Vector3i, target_cell: Vector3i) -> bool:
	var level := await _depot()
	var grid := level.battle_controller.grid_manager
	var actor: TacticalUnit = level.turn_manager.enemy_units[0]
	var target: TacticalUnit = level.turn_manager.player_units[0]
	var found := false
	if grid.can_unit_occupy_cell(actor, start) and grid.can_unit_occupy_cell(target, target_cell):
		_place(actor, start, grid)
		_place(target, target_cell, grid)
		var initial := CombatRules.evaluate_attack(actor, target, grid, null)
		var arrival := CombatRules.evaluate_attack_from_cell(actor, stop, target, grid, null)
		if not initial.is_legal and arrival.is_legal and arrival.firing_solution.body_offset != Vector3.ZERO:
			var moves := []
			var shots := []
			level.battle_controller.action_service.action_presented.connect(func(result):
				if result.request.actor_id != actor.tactical_id: return
				if result is MoveActionResult: moves.append(actor.grid_position)
				if result is AttackActionResult: shots.append(result))
			level.turn_manager.end_current_turn()
			var deadline := Time.get_ticks_msec() + 10000
			while level.turn_manager.current_phase == TurnManager.TurnPhase.ENEMY_TURN and shots.is_empty() and Time.get_ticks_msec() < deadline:
				await process_frame
			found = not moves.is_empty() and not shots.is_empty() and shots[0].firing_solution.body_offset != Vector3.ZERO
			print("[ContextualSeek] start=", start, " witness=", stop, " target=", target_cell, " moves=", moves,
				" first_shot=", shots[0].firing_solution.to_replay_record() if not shots.is_empty() else {}, " discover=", found)
	level.queue_free()
	await process_frame
	return found
