extends SceneTree

const DebugMissionControllerData := preload("res://systems/debug_mission_controller.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	await _check_round_objective_and_teleport()
	await _check_force_extraction()
	print("Debug mission controls smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _make_controller(level: BattleLevel):
	var controller = DebugMissionControllerData.new()
	controller.configure(level.battle_controller, level.turn_manager, level.objective_manager, level.battle_controller.grid_manager)
	return controller

func _check_round_objective_and_teleport() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1, true, 24102, 0, Vector2i(24, 20), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(4, 1))
	root.add_child(level)
	await create_timer(0.25).timeout
	var controller = _make_controller(level)
	var survive := level.objective_manager.get_objective(&"survive")
	check(controller.advance_round(), "Debug control advances an active battle round")
	check(level.turn_manager.current_round == 2 and survive.progress == 1, "Advancing a round emits normal survival progress")
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var origin := actor.grid_position
	var destination := Vector3i(-1, -1, -1)
	for cell: MapCellData in level.battle_controller.grid_manager.map_data.cells.values():
		if cell.walkable and cell.can_stop and not level.battle_controller.grid_manager.is_cell_occupied(cell.grid_position) and cell.grid_position != origin:
			destination = cell.grid_position
			break
	check(destination.x >= 0 and controller.teleport_actor(actor, destination), "Debug control teleports an actor to a legal free cell")
	check(actor.grid_position == destination and level.battle_controller.grid_manager.get_unit_at(destination) == actor, "Teleport keeps actor and occupancy synchronized")
	check(level.battle_controller.grid_manager.get_unit_at(origin) == null, "Teleport clears the actor's original occupancy")
	check(controller.complete_objective(&"survive") and survive.is_completed(), "Debug control completes a selected active objective")
	check(controller.fail_objective(&"extract_units"), "Debug control fails a selected active objective")
	await process_frame
	check(level.turn_manager.battle_result == TurnManager.BattleResult.DEFEAT, "Failing a required objective evaluates the normal defeat outcome")
	level.queue_free()
	await process_frame

func _check_force_extraction() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1, true, 24103, 0, Vector2i(24, 20), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(5, 1))
	root.add_child(level)
	await create_timer(0.25).timeout
	var controller = _make_controller(level)
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	check(await controller.force_extract(actor), "Debug force extraction uses the mission's extraction zone and action")
	await process_frame
	check(level.objective_manager.extracted_units == 1, "Forced extraction updates mission extraction counters")
	check(level.turn_manager.player_units.is_empty(), "Forced extraction removes the actor from the active roster")
	check(level.turn_manager.battle_result == TurnManager.BattleResult.VICTORY, "Forced extraction evaluates the normal mission victory")
	level.queue_free()
	await process_frame
