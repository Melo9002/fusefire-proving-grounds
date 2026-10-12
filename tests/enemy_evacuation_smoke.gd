extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _wait_until(predicate: Callable, seconds := 5.0) -> void:
	for tick in ceili(seconds / 0.05):
		if predicate.call():
			return
		await create_timer(0.05).timeout

func _create_level() -> BattleLevel:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1, false, 1, 0, Vector2i(32, 24), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ENEMY_EVACUATION, 1))
	root.add_child(level)
	await create_timer(0.2).timeout
	return level

func _nearby_destination(level: BattleLevel, unit: TacticalUnit) -> Vector3i:
	var grid := level.battle_controller.grid_manager
	var start := grid.get_unit_grid(unit)
	for cell in level.battle_controller.pathfinder.get_reachable_cells(start, unit.stats.speed):
		if cell != start and grid.can_unit_occupy_cell(unit, cell):
			return cell
	return Vector3i(-1, -1, -1)

func _run() -> void:
	await _check_manual_enemy_extract_button()
	await _check_enemy_escape_causes_defeat()
	await _check_stopping_every_enemy_causes_victory()
	print("Enemy evacuation smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _world_bar_for(level: BattleLevel, unit: TacticalUnit) -> UnitWorldBar:
	for child in level.get_node("Visualizers/BattleUI").get_children():
		if child is UnitWorldBar and child._target_unit == unit:
			return child as UnitWorldBar
	return null

func _check_manual_enemy_extract_button() -> void:
	var level := await _create_level()
	var enemy := level.turn_manager.enemy_units[0]
	level.battle_controller.set_debug_enemy_control(true)
	level.battle_controller.grid_manager.map_data.set_objective_zone(&"enemy_extract", [enemy.grid_position])
	level.turn_manager.end_current_turn()
	await _wait_until(func(): return level.turn_manager.current_phase == TurnManager.TurnPhase.ENEMY_TURN)
	var world_bar := _world_bar_for(level, enemy)
	check(world_bar != null, "The manually controlled enemy has a world bar")
	if world_bar == null:
		level.queue_free()
		await process_frame
		return
	world_bar._refresh_extract_button()
	check(world_bar.extract_button.visible, "The active manually controlled enemy receives an Extract button")
	enemy.stats.set_available_ap_for_setup(0)
	world_bar._refresh_extract_button()
	check(world_bar.extract_button.visible and not world_bar.extract_button.disabled, "Enemy extraction remains enabled at zero AP")
	world_bar.extract_button.button_down.emit()
	await _wait_until(func(): return level.turn_manager.battle_result != TurnManager.BattleResult.ONGOING)
	check(level.turn_manager.battle_result == TurnManager.BattleResult.DEFEAT, "The manual enemy Extract button uses the mission action")
	level.queue_free()
	await process_frame

func _check_enemy_escape_causes_defeat() -> void:
	var level := await _create_level()
	var enemy := level.turn_manager.enemy_units[0]
	var intent := level.objective_manager.get_mission_intent(enemy)
	check(intent.kind == MissionIntent.Kind.EXTRACT and intent.zone_id == &"enemy_extract", "Enemy evacuees receive their faction-owned extraction goal")
	var destination := _nearby_destination(level, enemy)
	check(destination.x >= 0, "Enemy evacuation test finds a reachable exit")
	level.battle_controller.grid_manager.map_data.set_objective_zone(&"enemy_extract", [destination])
	level.turn_manager.end_current_turn()
	await _wait_until(func(): return level.turn_manager.battle_result != TurnManager.BattleResult.ONGOING)
	check(level.turn_manager.battle_result == TurnManager.BattleResult.DEFEAT, "One enemy escape fails the interception mission")
	check(level.objective_manager.escaped_enemies == 1, "Enemy extraction is recorded separately from friendly evacuation")
	check(level.objective_manager.get_objective(&"stop_enemy_evacuation").is_failed(), "The required stop-evacuation objective reports failure")
	check(level.turn_manager.enemy_units.is_empty(), "An escaped enemy releases its turn-roster slot")
	level.queue_free()
	await process_frame

func _check_stopping_every_enemy_causes_victory() -> void:
	var level := await _create_level()
	var enemy := level.turn_manager.enemy_units[0]
	enemy.stats.take_damage(1000)
	await _wait_until(func(): return level.turn_manager.battle_result != TurnManager.BattleResult.ONGOING)
	check(level.turn_manager.battle_result == TurnManager.BattleResult.VICTORY, "Defeating every evacuee completes the mission")
	check(level.objective_manager.escaped_enemies == 0, "A successful interception records no escaped enemies")
	level.queue_free()
	await process_frame
