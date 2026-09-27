extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	await _check_pause_and_manual_enemy_control()
	await _check_automatic_battle()
	print("Debug tools smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_pause_and_manual_enemy_control() -> void:
	var level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1)
	root.add_child(level)
	await create_timer(0.15).timeout
	var debug_tools := level.get_node("Visualizers/BattleUI/DebugTools") as DebugTools
	var turns: TurnManager = level.turn_manager
	var battle: BattleController = level.battle_controller
	var enemy: TacticalUnit = turns.enemy_units[0]
	var enemy_start: Vector3i = enemy.grid_position

	check(debug_tools.debug_tools_enabled, "Debug tools are exposed and enabled on the test scene")
	debug_tools.set_panel_open(true)
	check(paused and debug_tools.panel_open, "Opening debug tools pauses the scene")
	check(debug_tools._panel.position.y + debug_tools._panel.size.y <= debug_tools.get_viewport_rect().size.y, "Expanded F3 panel fits inside the 720p viewport")
	debug_tools.set_manual_enemy_control(true)
	debug_tools.set_panel_open(false)
	check(not paused, "Closing debug tools resumes a pause it owns")

	turns.end_current_turn()
	await create_timer(0.8).timeout
	check(turns.current_phase == TurnManager.TurnPhase.ENEMY_TURN, "Manual control holds the enemy phase")
	check(enemy.grid_position == enemy_start and enemy.stats.current_ap == enemy.stats.max_ap, "Enemy AI waits without moving or spending AP")
	check(battle.is_current_phase_manually_controlled(), "Normal action input is enabled for the active enemy")
	check(battle.try_defend(enemy), "A manually controlled enemy uses the shared action gateway")

	debug_tools.set_manual_enemy_control(false)
	level.queue_free()
	await process_frame

func _check_automatic_battle() -> void:
	var level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1)
	root.add_child(level)
	await create_timer(0.15).timeout
	var debug_tools := level.get_node("Visualizers/BattleUI/DebugTools") as DebugTools
	var turns: TurnManager = level.turn_manager
	var player: TacticalUnit = turns.player_units[0]
	var enemy: TacticalUnit = turns.enemy_units[0]
	var player_start: Vector3i = player.grid_position
	var enemy_start: Vector3i = enemy.grid_position

	debug_tools.set_auto_battle(true)
	for tick in 160:
		if turns.current_round >= 2:
			break
		await create_timer(0.1).timeout
	debug_tools.set_auto_battle(false)
	check(turns.current_round >= 2, "AI-versus-AI mode completes a full round")
	check(player.grid_position != player_start, "Player AI moves through shared actions")
	check(enemy.grid_position != enemy_start, "Enemy AI moves through shared actions")
	check(level.battle_controller.grid_manager.occupancy_map.size() == 2, "Automatic battle preserves unique occupancy")
	check(not debug_tools._latest_ai_decision.is_empty(), "Automatic actions publish an AI decision explanation")
	check(debug_tools._latest_ai_decision.has("action") and debug_tools._latest_ai_decision.has("reason"), "AI explanations contain a choice and reason")
	check(debug_tools._latest_ai_decision.has("mission_goal"), "AI explanations keep the mission goal beside the combat choice")
	check(debug_tools._latest_ai_decision.has("squad_adjustments"), "AI explanations expose squad-awareness adjustments")

	level.queue_free()
	await process_frame
