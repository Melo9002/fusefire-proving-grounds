extends SceneTree
## Timed production Rescue and Move on one authored 4 m link.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): quit(2))
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.PARKING_GARAGE)
	config.battle_seed = 17
	config.player_count = 1
	config.enemy_count = 1
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 1, false)
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var actor := level.turn_manager.player_units[0]
	var vip := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var battle := level.battle_controller
	var grid := battle.grid_manager
	for link: TraversalLinkData in grid.map_data.traversal_links:
		if link.surface_kind != TraversalLinkData.LADDER or link.to_cell.y - link.from_cell.y != 4:
			continue
		if not grid.can_unit_occupy_cell(actor, link.from_cell) or not grid.can_unit_occupy_cell(actor, link.to_cell):
			continue
		for offset in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var pickup_cell: Vector3i = link.from_cell + offset
			if not grid.can_unit_occupy_cell(vip, pickup_cell):
				continue
			_place(grid, actor, link.from_cell)
			_place(grid, vip, pickup_cell)
			if not level.objective_manager.can_rescue(actor, vip):
				continue
			if not await level.objective_manager.try_rescue(actor, vip):
				break
			var success := true
			for target in [link.to_cell, link.from_cell]:
				var start := Time.get_ticks_msec()
				var service := battle.action_service
				var result := await service.submit_move(service.make_move_request(actor, target, TacticalActionRequest.Source.PLAYER))
				success = success and result != null and result.presentation_error.is_empty() and actor.grid_position == target
				print("[Garage ladder] rise=4.0m to=", target, " ms=", Time.get_ticks_msec() - start, " arrived=", success)
			level.queue_free()
			await process_frame
			quit(0 if success else 1)
			return
	push_error("No usable authored Rescue approach to the 4 m link")
	quit(1)

func _place(grid: GridManager, unit: TacticalUnit, cell: Vector3i) -> void:
	grid.update_unit_position(unit, grid.get_unit_grid(unit), cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height
