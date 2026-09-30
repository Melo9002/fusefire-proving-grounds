extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _wait_until(predicate: Callable, seconds := 8.0) -> void:
	for tick in ceili(seconds / 0.05):
		if predicate.call(): return
		await create_timer(0.05).timeout

func _place(level: BattleLevel, unit: TacticalUnit, cell: Vector3i) -> void:
	var grid := level.battle_controller.grid_manager
	grid.update_unit_position(unit, grid.get_unit_grid(unit), cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

func _run() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1, false, 1, 2, Vector2i(32, 24), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 1))
	root.add_child(level)
	await create_timer(0.2).timeout
	level.battle_controller.set_debug_enemy_control(true)

	var grid := level.battle_controller.grid_manager
	var carrier := level.turn_manager.allied_units[0]
	var supporter := level.turn_manager.allied_units[1]
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var carrier_cell := grid.get_unit_grid(carrier)
	for direction in Pathfinder.DIRECTIONS:
		var candidate := carrier_cell + direction
		if grid.can_unit_occupy_cell(target, candidate):
			_place(level, target, candidate)
			break

	var support_start := Vector3i(-1, -1, -1)
	var exit := Vector3i(-1, -1, -1)
	for cell: MapCellData in grid.map_data.cells.values():
		if not grid.can_unit_occupy_cell(supporter, cell.grid_position): continue
		var path := level.battle_controller.pathfinder.calculate_3d_path(carrier_cell, cell.grid_position)
		if support_start.x < 0 and path.size() >= 9 and path.size() <= 13:
			support_start = cell.grid_position
		if path.size() >= 18:
			exit = cell.grid_position
		if support_start.x >= 0 and exit.x >= 0: break
	check(support_start.x >= 0 and exit.x >= 0, "Carrier-support test finds separated reachable positions")
	_place(level, supporter, support_start)
	grid.map_data.set_objective_zone(&"extract", [exit])
	var before := support_start.distance_to(carrier_cell)

	level.turn_manager.end_current_turn()
	await _wait_until(func(): return level.turn_manager.current_phase == TurnManager.TurnPhase.ENEMY_TURN)
	check(carrier.is_carrying_unit(), "The first ally becomes the rescue carrier")
	check(supporter.grid_position.distance_to(carrier.grid_position) < before, "A later ally closes distance to support the mobile rescue carrier")
	# After the passenger boards, living enemies must not veto escort evacuation.
	var objectives := root.get_tree().get_first_node_in_group("objective_manager") as ObjectiveManager
	level.action_camera_director.frequency = 0
	_place(level, carrier, exit)
	check(await objectives.try_extract(carrier), "Carrier boards before escort departure")
	await process_frame
	_place(level, supporter, exit)
	var ai := level.allied_units_parent.get_node("AllyUnit2AI") as AIController
	ai.current_mission_intent = objectives.get_mission_intent(supporter)
	check(not level.turn_manager.enemy_units.is_empty(), "Enemies remain alive during evacuation regression")
	var step: int = await ai._try_mission_step(false)
	check(step == AIController.MissionStepResult.EXTRACTED, "Escort extracts despite remaining hostiles after VIP evacuation")
	print("Rescue carrier support smoke: %d failure(s)" % failures)
	level.queue_free()
	await process_frame
	quit(1 if failures else 0)
