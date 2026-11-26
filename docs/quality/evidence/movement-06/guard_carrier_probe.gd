extends "res://tests/rescue_carrier_loss_test.gd"
## Uses the existing Rescue fixture and the real Move/Guard action service.
## Force a hit only after production confirms the checkpoint admits a reaction.

func _run() -> void:
	var level := await _create_level()
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var service := battle.action_service
	var carrier: TacticalUnit = level.turn_manager.player_units[0]
	var watcher: TacticalUnit = level.turn_manager.enemy_units[0]
	var vip := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	for cell: MapCellData in grid.map_data.cells.values():
		cell.blocks_line_of_sight = false
		cell.cover_type = MapCellData.CoverType.NONE
		cell.cover_height = 0
	grid.map_data.rebuild_los_index()
	check(await _rescue(level, carrier, vip), "Real Rescue action picks up the VIP")
	carrier.stats.set_available_ap_for_setup(3)
	level.turn_manager.select_player_unit(carrier)
	watcher.attack_range = 100
	check(watcher.tactical_state.establish_overwatch(), "Controlled watcher enters Guard")
	var origin := grid.get_unit_grid(carrier)
	var destination := Vector3i(-1, -1, -1)
	for candidate in service.query_move(carrier.tactical_id).legal_destination_cells:
		var query := service.query_move(carrier.tactical_id, candidate)
		if query.is_legal() and query.path_cells.size() >= 3 and service.query_guard_reaction(watcher, carrier, query.path_cells[1]).can_fire:
			destination = candidate
			break
	check(destination.x >= 0, "At least one legal route admits Guard at the first checkpoint")
	if failures:
		await _finish(level)
		quit(2)
		return
	var preview := service.query_move(carrier.tactical_id, destination)
	var checkpoint := preview.path_cells[1]
	check(grid.can_unit_occupy_cell(vip, checkpoint), "VIP can stand at the exact checkpoint")
	carrier.stats.current_hp = 1
	var chance: int = service.query_guard_reaction(watcher, carrier, checkpoint).evaluation.hit_chance
	var rng := RandomNumberGenerator.new()
	for seed_value in 1000:
		rng.seed = seed_value
		if rng.randf() * 100.0 < chance:
			service._combat_rng.seed = seed_value
			break
	var receipt := await service.submit_move(service.make_move_request(carrier, destination, TacticalActionRequest.Source.PLAYER), true)
	check(receipt != null and receipt.movement_interrupted and receipt.target_cell == checkpoint, "Authoritative Move stops at the lethal checkpoint")
	print("[GuardCarrier] origin=", origin, " preview=", preview.path_cells, " requested=", destination, " checkpoint=", checkpoint, " receipt=", receipt.target_cell if receipt else null, " VIP=", grid.get_unit_grid(vip), " VIP_occupies_origin=", grid.get_unit_at(origin) == vip, " VIP_occupies_checkpoint=", grid.get_unit_at(checkpoint) == vip)
	await _finish(level)
	quit(0 if not failures else 2)
