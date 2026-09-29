extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _check_eliminate()
	await _check_round_objectives()
	await _check_reach()
	await _check_rescue()
	await _check_extract()
	print("Core objectives: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _create_level(kind: MissionObjectiveDefinition.Kind, include_vip := false, player_count := 1) -> BattleLevel:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(player_count, 2, false, 1, 0, Vector2i(32, 24), include_vip, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(kind, 2, include_vip))
	root.add_child(level)
	await create_timer(0.15).timeout
	# This suite checks objective rules; camera timing has its own focused tests.
	level.action_camera_director.frequency = level.action_camera_director.Frequency.OFF
	return level

func _finish(level: BattleLevel) -> void:
	level.queue_free()
	await process_frame
	await process_frame

func _world_bar_for(level: BattleLevel, unit: TacticalUnit) -> UnitWorldBar:
	for child in level.get_node("Visualizers/BattleUI").get_children():
		if child is UnitWorldBar and child._target_unit == unit:
			return child as UnitWorldBar
	return null

func _check_eliminate() -> void:
	var level := await _create_level(MissionObjectiveDefinition.Kind.ELIMINATE)
	var state := level.objective_manager.get_objective(&"eliminate")
	level.battle_controller.unit_defeated_in_battle.emit(level.turn_manager.enemy_units[0])
	check(state.progress == 1 and state.is_active(), "Eliminate counts enemy defeats")
	level.battle_controller.unit_defeated_in_battle.emit(level.turn_manager.enemy_units[1])
	check(state.is_completed(), "Eliminate completes at the selected enemy count")
	await process_frame
	check(level.turn_manager.battle_result == TurnManager.BattleResult.VICTORY, "Eliminate completion grants mission victory")
	await _finish(level)

func _check_round_objectives() -> void:
	var survive_level := await _create_level(MissionObjectiveDefinition.Kind.SURVIVE)
	for round_number in [2, 3, 4]: survive_level.turn_manager.round_started.emit(round_number)
	check(survive_level.objective_manager.get_objective(&"survive").is_completed(), "Survive completes its timed stage after three rounds")
	check(survive_level.turn_manager.battle_result == TurnManager.BattleResult.ONGOING, "Survive still requires evacuation")
	var survivor := survive_level.turn_manager.player_units[0]
	var exit := survive_level.battle_controller.grid_manager.map_data.get_objective_zone(&"extract")[0]
	survive_level.battle_controller.grid_manager.update_unit_position(survivor, survivor.grid_position, exit)
	check(await survive_level.objective_manager.try_extract(survivor), "A survivor can evacuate after the timed stage")
	await process_frame
	check(survive_level.turn_manager.battle_result == TurnManager.BattleResult.VICTORY, "Evacuating every survivor grants victory")
	await _finish(survive_level)

	var protect_level := await _create_level(MissionObjectiveDefinition.Kind.PROTECT, true)
	for enemy in protect_level.turn_manager.enemy_units:
		protect_level.battle_controller.unit_defeated_in_battle.emit(enemy)
	await process_frame
	check(protect_level.objective_manager.get_objective(&"protect").is_completed(), "Protect completes when elimination ends with the VIP alive")
	check(protect_level.turn_manager.battle_result == TurnManager.BattleResult.VICTORY, "Protect and Eliminate combine into victory")
	await _finish(protect_level)

func _check_reach() -> void:
	var level := await _create_level(MissionObjectiveDefinition.Kind.REACH)
	var player := level.turn_manager.player_units[0]
	var destination := level.battle_controller.grid_manager.map_data.get_objective_zone(&"reach")[0]
	level.battle_controller.unit_moved.emit(player, player.grid_position, destination)
	check(level.objective_manager.get_objective(&"reach").is_completed(), "Reach completes when a player enters its MapData zone")
	await process_frame
	check(level.turn_manager.battle_result == TurnManager.BattleResult.VICTORY, "Reach grants immediate victory")
	await _finish(level)

func _check_rescue() -> void:
	var level := await _create_level(MissionObjectiveDefinition.Kind.RESCUE, false, 2)
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var target_cell := level.battle_controller.grid_manager.get_unit_grid(target)
	var approach := target_cell + Vector3i.LEFT
	var carrier := level.turn_manager.player_units[0]
	var original_speed := carrier.stats.speed
	level.battle_controller.grid_manager.update_unit_position(carrier, carrier.grid_position, approach)
	level.battle_controller.unit_moved.emit(carrier, approach + Vector3i.LEFT, approach)
	check(level.objective_manager.get_objective(&"rescue").is_completed(), "Rescue completes beside its neutral target")
	check(carrier.is_carrying_unit() and carrier.stats.speed == original_speed - 2, "The rescuer carries the VIP with reduced movement")
	check(not target.visible, "A carried VIP no longer remains visible at the pickup cell")
	var exit := level.battle_controller.grid_manager.map_data.get_objective_zone(&"extract")[0]
	var teammate := level.turn_manager.player_units[1]
	level.battle_controller.grid_manager.update_unit_position(teammate, teammate.grid_position, exit)
	check(level.turn_manager.select_player_unit(teammate), "The carrier's teammate remains selectable")
	check(await level.objective_manager.try_extract(teammate), "Other squad members may evacuate after the VIP is picked up")
	check(level.turn_manager.select_player_unit(carrier), "The VIP carrier remains selectable after a teammate evacuates")
	level.battle_controller.grid_manager.update_unit_position(carrier, carrier.grid_position, exit)
	check(await level.objective_manager.try_extract(carrier), "The carrier extracts together with the rescued VIP")
	await process_frame
	check(level.turn_manager.battle_result == TurnManager.BattleResult.VICTORY, "Rescuing and extracting the VIP grants victory")
	await _finish(level)

func _check_extract() -> void:
	var level := await _create_level(MissionObjectiveDefinition.Kind.EXTRACT, false, 2)
	check(not level.objective_manager.should_seek_extraction(level.turn_manager.enemy_units[0]), "Enemies never seek the player's extraction zone")
	check(level.objective_manager.get_objective(&"extract_vips") == null, "Extract missions do not require a VIP unless one was enabled")
	var destinations := level.battle_controller.grid_manager.map_data.get_objective_zone(&"extract")
	var exhausted := level.turn_manager.player_units[1]
	exhausted.stats.current_ap = 0
	level.battle_controller.grid_manager.update_unit_position(exhausted, exhausted.grid_position, destinations[0])
	check(level.objective_manager.can_extract(exhausted), "An exhausted non-active unit may use the zero-AP Extract action")
	var world_bar := _world_bar_for(level, exhausted)
	check(world_bar != null, "An eligible unit has a world-space action bar")
	if world_bar:
		world_bar._refresh_extract_button()
		check(world_bar.extract_button.visible and not world_bar.extract_button.disabled, "Extract is immediately enabled in an active extraction zone")
		world_bar.extract_button.button_down.emit()
		await process_frame
	check(level.objective_manager.extracted_units == 1, "The Extract button's mouse-down signal evacuates the eligible unit")
	check(level.objective_manager.can_end_mission_early(), "One extracted unit unlocks early mission ending")
	check(level.objective_manager.end_mission_early(), "The player can end early and leave a living unit behind")
	check(level.objective_manager.get_result_report() == "VIPs extracted 0/0 | Units extracted 1/2", "The mission report retains extraction consequences")
	await _finish(level)
