extends "res://tests/contextual_battlefield_test.gd"
## Equal exact queries per mode. Rotate trial order, discard warm-up and use a
## read-only, fixed set of canonical cells per generated board.

func _run() -> void:
	for site in [BattlefieldCatalog.CONTEXTUAL_SHOWCASE, BattlefieldCatalog.CONTEXTUAL_FREIGHT]:
		var level := await _depot(site, 16)
		var battle := level.battle_controller
		var grid := battle.grid_manager
		var actor := level.turn_manager.player_units[0]
		var hostile := level.turn_manager.enemy_units[0]
		var cells: Array[Vector3i] = []
		for cell in grid.map_data.cells.values():
			if cell.can_stop and CombatRules.attack_distance(cell.grid_position, hostile.grid_position, grid) <= actor.attack_range 				and not is_instance_valid(grid.get_unit_at(cell.grid_position)):
				cells.append(cell.grid_position)
		for steps in [false, true]:
			grid.map_data.contextual_discovery_enabled = steps
			for trial in 6:
				for turn in 4:
					var mode := (trial + turn) % 4
					grid.map_data.engagement_policy = mode
					var hits := 0
					var start := Time.get_ticks_usec()
					for repeat in 3:
						for cell in cells:
							var shot := CombatRules.evaluate_attack_from_cell(actor, cell, hostile, grid, null)
							hits += int(shot.is_legal)
					var cost := Time.get_ticks_usec() - start
					if trial == 0: continue
					print("[QueryBench] ", JSON.stringify({"map":site,"steps":steps,"mode":mode,"trial":trial,
						"queries":cells.size()*3,"legal":hits,"usec":cost}))
		level.queue_free()
		await process_frame
	quit(int(failures > 0))
