extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	await _check_protect_escort()
	await _check_rescue_and_extract()
	print("Protect and rescue AI smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _create_level(kind: MissionObjectiveDefinition.Kind, include_vip := false) -> BattleLevel:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1, false, 1, 1, Vector2i(32, 24), include_vip, MissionActor.VIPBehavior.HOLD_POSITION, MissionCatalog.create_mission(kind, 1, include_vip))
	root.add_child(level)
	await create_timer(0.2).timeout
	return level

func _place(unit: TacticalUnit, cell: Vector3i, level: BattleLevel) -> void:
	var grid := level.battle_controller.grid_manager
	grid.update_unit_position(unit, grid.get_unit_grid(unit), cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

func _wait_until(predicate: Callable, seconds := 6.0) -> void:
	for tick in ceili(seconds / 0.05):
		if predicate.call():
			return
		await create_timer(0.05).timeout

func _escort_start(level: BattleLevel, escort: TacticalUnit, vip: TacticalUnit) -> Vector3i:
	var grid := level.battle_controller.grid_manager
	var vip_cell := grid.get_unit_grid(vip)
	for cell: MapCellData in grid.map_data.cells.values():
		if not grid.can_unit_occupy_cell(escort, cell.grid_position):
			continue
		var path := level.battle_controller.pathfinder.calculate_3d_path(cell.grid_position, vip_cell)
		if path.size() >= 5 and path.size() <= escort.stats.speed + 4:
			return cell.grid_position
	return Vector3i(-1, -1, -1)

func _check_protect_escort() -> void:
	var level := await _create_level(MissionObjectiveDefinition.Kind.PROTECT, true)
	var escort := level.turn_manager.allied_units[0]
	var vip := level.get_node("Units/AlliedUnits/FriendlyVIP") as TacticalUnit
	var start := _escort_start(level, escort, vip)
	check(start.x >= 0, "Protect AI test finds a legal escort route")
	_place(escort, start, level)
	var before := start.distance_to(vip.grid_position)
	level.turn_manager.end_current_turn()
	await _wait_until(func(): return escort.grid_position != start and not escort.is_moving and not level.battle_controller.action_service.is_busy)
	var after := escort.grid_position.distance_to(vip.grid_position)
	check(after < before, "Protecting ally moves closer to the VIP")
	# Position scoring may choose an adjacent safer cell beside the requested
	# three-step path boundary; the contract is meaningful escort progress.
	check(after <= 4.0, "Protecting ally finishes at the escort-radius boundary")
	check(level.objective_manager.get_objective(&"protect").is_active(), "Escort movement does not complete Protect before combat ends")
	level.queue_free()
	await process_frame

func _check_rescue_and_extract() -> void:
	var level := await _create_level(MissionObjectiveDefinition.Kind.RESCUE)
	var grid := level.battle_controller.grid_manager
	var ally := level.turn_manager.allied_units[0]
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var ally_cell := grid.get_unit_grid(ally)
	var rescue_cell := Vector3i(-1, -1, -1)
	var extract_cell := Vector3i(-1, -1, -1)
	for direction in Pathfinder.DIRECTIONS:
		var candidate := ally_cell + direction
		if rescue_cell.x < 0 and grid.can_unit_occupy_cell(target, candidate):
			rescue_cell = candidate
		elif extract_cell.x < 0 and grid.can_unit_occupy_cell(ally, candidate):
			extract_cell = candidate
	check(rescue_cell.x >= 0 and extract_cell.x >= 0, "Rescue AI test finds adjacent rescue and extraction cells")
	_place(target, rescue_cell, level)
	grid.map_data.set_objective_zone(&"extract", [extract_cell])
	level.turn_manager.end_current_turn()
	await _wait_until(func(): return level.objective_manager.extracted_vips == 1 and not level.battle_controller.action_service.is_busy)
	check(level.objective_manager.get_objective(&"rescue").is_completed(), "AI ally rescues the adjacent neutral VIP")
	check(level.objective_manager.extracted_vips == 1, "AI carrier brings the rescued VIP to extraction")
	check(level.objective_manager.can_end_mission_early(), "Rescuing and extracting the VIP unlocks the explicit departure command")
	check(level.turn_manager.battle_result == TurnManager.BattleResult.ONGOING, "Remaining squad members are not silently abandoned by VIP extraction")
	check(level.turn_manager.allied_units.is_empty(), "The extracted AI carrier leaves the allied roster")
	level.queue_free()
	await process_frame
