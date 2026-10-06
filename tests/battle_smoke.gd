extends SceneTree

var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var level = load("res://levels/prototype_map/prototype_map.tscn").instantiate()
	root.add_child(level)
	await create_timer(0.15).timeout
	var battle: BattleController = level.get_node("Systems/BattleController")
	# This test asserts intermediate action state immediately. Keep its timing
	# independent from the player's saved cinematic-camera preference.
	battle.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var turns: TurnManager = battle.turn_manager
	var grid: GridManager = battle.grid_manager
	var player: TacticalUnit = turns.player_units[0]
	var enemy: TacticalUnit = turns.enemy_units[0]
	var camera_rig: TacticalCamera = level.get_node("CameraRig")
	check(turns.current_phase == TurnManager.TurnPhase.PLAYER_TURN, "Battle starts after map scan")
	check(battle.pathfinder.grid_to_id_map.size() == 876, "Expanded ground and vertical terrain are built")
	var wall = grid.world_to_grid(Vector3(2.5, 0, 2.5))
	check(not battle.pathfinder.astar.is_point_disabled(battle.pathfinder.grid_to_id_map[wall]), "Low cover remains connected for vault paths")
	check(not grid.get_cell_data(wall).can_stop, "Units cannot stop on low cover")
	var start = grid.world_to_grid(player.global_position)
	check(not battle.pathfinder.astar.is_point_disabled(battle.pathfinder.grid_to_id_map[start]), "Units do not disable terrain")
	check(battle.pathfinder.calculate_3d_path(start, wall).is_empty(), "Low cover cannot be a movement destination")
	check(not battle.can_attack(player, turns.player_units[1]), "Friendly fire is rejected")
	check(not battle.can_attack(player, enemy), "Out-of-range attacks are rejected")
	var player_ap_before_invalid_actions := player.stats.current_ap
	check(not await battle.try_attack(player, enemy), "The shared gateway rejects an out-of-range attack")
	check(not await battle.try_defend(turns.player_units[1]), "An inactive friendly cannot act")
	check(not await battle.try_move(turns.player_units[1], grid.world_to_grid(turns.player_units[1].global_position) + Vector3i.RIGHT), "An inactive friendly cannot move")
	check(player.stats.current_ap == player_ap_before_invalid_actions and turns.player_units[1].stats.current_ap == turns.player_units[1].stats.max_ap, "Failed actions preserve AP")
	check(FactionRules.are_hostile(TacticalUnit.Faction.ALLY, TacticalUnit.Faction.ENEMY), "Allies and enemies are hostile")
	check(not FactionRules.are_hostile(TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.NEUTRAL), "Neutral units are not hostile")
	camera_rig.global_position = Vector3(100, 0, -100)
	camera_rig._clamp_to_map()
	check(camera_rig.global_position.x == 18.0 and camera_rig.global_position.z == -14.0, "Camera pan follows the larger map bounds")
	camera_rig._set_zoom(100.0)
	check(camera_rig.camera.position.z == camera_rig.max_zoom, "Camera zoom stays within its maximum")

	battle.toggle_move_mode()
	var destination = start + Vector3i(1, 0, 0)
	check(battle.current_movement_zone.has(destination), "Adjacent empty cell is reachable")
	battle._on_floor_clicked(grid.grid_to_world(destination))
	check(player.is_moving and player.stats.current_ap == 1, "Move starts and spends one AP")
	check(battle.is_action_in_progress, "Movement locks other battle actions")
	check(not turns.select_player_unit(turns.player_units[1]), "Selection is blocked during movement")
	turns.end_current_turn()
	check(turns.current_phase == TurnManager.TurnPhase.PLAYER_TURN, "Phase cannot end during movement")
	check(grid.get_unit_at(destination) == player and not grid.is_cell_occupied(start), "Move reserves destination")
	await create_timer(1.0).timeout
	check(not player.is_moving and grid.world_to_grid(player.global_position) == destination, "Move reaches destination")
	check(not battle.is_move_mode_active, "Move returns to neutral mode")

	# Place a target nearby to test the same combat entry point used by the AI.
	var old_enemy_cell = grid.world_to_grid(enemy.global_position)
	enemy.global_position = player.global_position + Vector3(1, 0, 0)
	grid.update_unit_position(enemy, old_enemy_cell, grid.world_to_grid(enemy.global_position))
	var enemy_ap_before_invalid_action := enemy.stats.current_ap
	check(not await battle.try_defend(enemy), "A unit cannot act outside its own active turn")
	check(enemy.stats.current_ap == enemy_ap_before_invalid_action, "Rejected actions do not spend AP")
	enemy.stats.is_defending = true
	check(await battle.try_attack(player, enemy), "In-range attack executes")
	check(enemy.stats.current_hp == 88 and player.stats.current_ap == 0, "Defend halves damage and attack costs one AP")
	check(not await battle.try_attack(player, enemy), "Attack without AP is rejected")
	check(turns.current_phase == TurnManager.TurnPhase.PLAYER_TURN, "Zero AP does not automatically end the phase")

	# LOS reads full-cover terrain independently from movement connectivity.
	var player_cell = grid.world_to_grid(player.global_position)
	var blocker_cell = player_cell + Vector3i(1, 0, 0)
	var target_cell = player_cell + Vector3i(2, 0, 0)
	enemy.global_position = grid.grid_to_world(target_cell) + Vector3.UP
	grid.update_unit_position(enemy, blocker_cell, target_cell)
	var blocker_data = grid.get_cell_data(blocker_cell)
	blocker_data.cover_type = MapCellData.CoverType.FULL
	blocker_data.cover_height = 2.0
	blocker_data.blocks_line_of_sight = true
	grid.map_data.rebuild_los_index()
	check(not battle.can_attack(player, enemy), "Full-cover map data blocks shots")
	blocker_data.cover_type = MapCellData.CoverType.NONE
	blocker_data.cover_height = 0.0
	blocker_data.blocks_line_of_sight = false
	grid.map_data.rebuild_los_index()

	turns.end_current_turn()
	await create_timer(6.0).timeout
	check(turns.current_phase == TurnManager.TurnPhase.PLAYER_TURN and turns.current_round == 2, "Both enemies complete their turns")
	check(player.stats.current_ap == player.stats.max_ap, "New round resets player AP")
	enemy.stats.take_damage(1000)
	await process_frame
	check(turns.enemy_units.size() == 1, "Defeated enemy leaves roster")
	check(grid.occupancy_map.size() == 3, "Defeated enemy leaves occupancy")
	turns.enemy_units[0].stats.take_damage(1000)
	await process_frame
	check(turns.battle_result == TurnManager.BattleResult.VICTORY, "Removing the last enemy ends in victory")
	check(turns.current_phase == TurnManager.TurnPhase.TRANSITION, "Battle result stops normal phases")
	level.queue_free()
	await process_frame
	print("Battle smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)
