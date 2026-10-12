extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	await _check_setup_control()
	await _check_handmade_allied_spawn()
	await _check_allied_activation()
	await _check_extracted_player_advances_after_barrier()
	await _check_battle_results()
	print("Allied faction smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_setup_control() -> void:
	var setup := load("res://ui/match_setup.tscn").instantiate() as MatchSetup
	root.add_child(setup)
	await process_frame
	check(setup.ally_count.value == 0, "Match setup defaults to no allied units")
	setup.ally_count.value = 2
	check("AI allies: 2" in setup.deployment_summary.text, "Match summary displays the independent ally count")
	setup.queue_free()
	await process_frame

func _check_handmade_allied_spawn() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1, false, 1, 1)
	root.add_child(level)
	await create_timer(0.2).timeout
	check(level.battle_controller.last_map_validation.is_valid(), "Handmade ally spawn data passes map validation")
	check(level.turn_manager.allied_units.size() == 1, "Handmade map spawns an allied unit")
	check(level.battle_controller.grid_manager.occupancy_map.size() == 3, "Handmade allied spawn does not overlap another unit")
	level.queue_free()
	await process_frame

func _create_level() -> BattleLevel:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1, true, 2468, 1)
	root.add_child(level)
	await create_timer(0.2).timeout
	return level

func _check_allied_activation() -> void:
	var level := await _create_level()
	var turns := level.turn_manager
	var battle := level.battle_controller
	check(turns.allied_units.size() == 1, "Setup creates the requested allied roster")
	var ally := turns.allied_units[0]
	var player := turns.player_units[0]
	var enemy := turns.enemy_units[0]
	check(ally.faction == TacticalUnit.Faction.ALLY, "Allied unit keeps its faction identity")
	check(not FactionRules.are_hostile(ally.faction, player.faction), "Allies cannot attack players")
	check(FactionRules.are_hostile(ally.faction, enemy.faction), "Allies treat enemies as hostile")
	check(not turns.select_player_unit(ally), "Players cannot manually select an autonomous ally")
	check(battle.grid_manager.occupancy_map.size() == 3, "Player, ally, and enemy occupy independent cells")

	turns.end_current_turn()
	check(turns.current_phase == TurnManager.TurnPhase.ALLY_TURN and turns.active_unit == ally, "Player phase advances to the allied activation")
	for tick in 160:
		if turns.current_round >= 2:
			break
		await create_timer(0.1).timeout
	check(turns.current_round >= 2 and turns.current_phase == TurnManager.TurnPhase.PLAYER_TURN, "Ally and enemy AI complete before the next player round")
	check(ally.stats.current_ap < ally.stats.max_ap, "Allied AI spends AP through shared actions")
	level.queue_free()
	await process_frame

func _check_extracted_player_advances_after_barrier() -> void:
	var turns := TurnManager.new()
	var player := TacticalUnit.new()
	var ally := TacticalUnit.new()
	player.stats = UnitStats.new()
	ally.stats = UnitStats.new()
	player.show_world_hud = false
	ally.show_world_hud = false
	player.tactical_id = &"PlayerUnit1"
	ally.tactical_id = &"AllyUnit1"
	turns.player_units = [player]
	turns.allied_units = [ally]
	turns.automatic_annihilation_results = false
	root.add_child(turns)
	root.add_child(player)
	root.add_child(ally)
	turns.current_phase = TurnManager.TurnPhase.PLAYER_TURN
	turns.active_unit = player
	var barrier := [true]
	turns.action_completion_barrier = func() -> bool: return barrier[0]
	turns.remove_extracted_unit(player)
	await process_frame
	check(turns.current_phase == TurnManager.TurnPhase.PLAYER_TURN and turns.active_unit == null, "Extraction waits for the action presentation barrier before advancing")
	barrier[0] = false
	await process_frame
	await process_frame
	check(turns.current_phase == TurnManager.TurnPhase.ALLY_TURN and turns.active_unit == ally, "The last player extraction advances directly to the allied activation")
	turns.queue_free()
	player.queue_free()
	ally.queue_free()
	await process_frame

func _check_battle_results() -> void:
	var victory_level := await _create_level()
	victory_level.turn_manager.enemy_units[0].stats.take_damage(1000)
	await process_frame
	check(victory_level.turn_manager.battle_result == TurnManager.BattleResult.VICTORY, "Enemy defeat grants victory while an ally survives")
	victory_level.queue_free()
	await process_frame

	var defeat_level := await _create_level()
	defeat_level.turn_manager.player_units[0].stats.take_damage(1000)
	await process_frame
	check(defeat_level.turn_manager.battle_result == TurnManager.BattleResult.DEFEAT, "Losing all player units is defeat even while an ally survives")
	defeat_level.queue_free()
	await process_frame
