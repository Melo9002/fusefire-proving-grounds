extends "res://tests/contextual_battlefield_test.gd"

func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.CONTEXTUAL_SHOWCASE)
	config.battle_seed = 16
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 2)
	var level := Scene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Real comparison level starts")
	if not level.battle_initialization_succeeded: quit(1); return
	var battle := level.battle_controller
	var a := level.turn_manager.player_units[0]
	var b := level.turn_manager.player_units[1]
	var x := level.turn_manager.enemy_units[0]
	var y := level.turn_manager.enemy_units[1]
	var player_context := battle.get_squad_context(a)
	var enemy_context := battle.get_squad_context(x)
	var policy := battle.get_commander_policy(a)
	check(battle.get_squad_context(b) == player_context and battle.get_squad_context(y) == enemy_context
		and player_context != enemy_context, "Default shares commitments within each faction only")
	battle.simulation_isolated_squad_factions = [TacticalUnit.Faction.PLAYER]
	var a_context := battle.get_squad_context(a)
	check(a_context != battle.get_squad_context(b) and battle.peek_squad_context(a) == a_context,
		"Private contexts retain each player's own state across lookups")
	a_context.reserve_target(a, x)
	check(not battle.get_squad_context(b).intended_targets.has(a.tactical_id), "An independent actor does not see an ally's claims")
	check(battle.get_squad_context(x) == enemy_context and battle.get_squad_context(y) == enemy_context
		and battle.get_commander_policy(a) == policy, "Mixed condition leaves the other side and opposing doctrine intact")
	battle.simulation_isolated_squad_factions.clear()
	check(battle.get_squad_context(a) == player_context and battle.get_squad_context(b) == player_context,
		"Disabling the laboratory option restores production coordination")
	level.queue_free()
	await process_frame
	print("[CoordinationChecks] ", checks, " checks and ", failures, " failures")
	quit(int(failures > 0))
