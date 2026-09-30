extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(1, 1, false, 1, 1)
	root.add_child(level)
	await create_timer(0.2).timeout
	var grid := level.battle_controller.grid_manager
	var player := level.turn_manager.player_units[0]
	var enemy := level.turn_manager.enemy_units[0]
	var ally := level.turn_manager.allied_units[0]
	var start := grid.get_unit_grid(player)
	var hostile_cell := grid.get_unit_grid(enemy)
	var hostiles: Array[TacticalUnit] = [enemy]
	var context := SquadContext.new()
	var normal := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.NORMAL)
	var easy := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.EASY)
	var hard := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.HARD)
	var open_cell := Vector3i(-1, -1, -1)
	var adjacent_cell := Vector3i(-1, -1, -1)
	for cell in grid.map_data.cells:
		if not grid.can_unit_occupy_cell(player, cell):
			continue
		var distance := absi(hostile_cell.x - cell.x) + absi(hostile_cell.y - cell.y) + absi(hostile_cell.z - cell.z)
		if distance <= 2:
			adjacent_cell = cell
		if open_cell.x < 0 and distance <= mini(player.attack_range, enemy.attack_range) and CombatRules.get_directional_cover(hostile_cell, cell, grid) == MapCellData.CoverType.NONE and CombatRules.has_line_of_sight_to_position(enemy, grid.grid_to_world(cell), grid, player.get_world_3d()):
			var origin := grid.grid_to_world(cell) + Vector3.UP * player.standing_height
			if CombatRules.get_blocking_cell(origin, CombatRules.get_shot_destination(enemy, grid), grid) == null:
				open_cell = cell
	check(open_cell.x >= 0, "Found a tile with both incoming exposure and a firing opportunity")
	check(adjacent_cell.x >= 0, "Found a dangerous tile near the enemy")
	if open_cell.x >= 0:
		var normal_score := AIPositionScorer.evaluate(player, open_cell, start, hostile_cell, 2, false, hostiles, grid, normal, context)
		var easy_score := AIPositionScorer.evaluate(player, open_cell, start, hostile_cell, 2, false, hostiles, grid, easy, context)
		var hard_score := AIPositionScorer.evaluate(player, open_cell, start, hostile_cell, 2, false, hostiles, grid, hard, context)
		check(normal_score.exposure < 0.0 and normal_score.firing > 0.0, "Position score includes exposure and firing opportunity")
		player.carried_unit = ally
		var carrier_score := AIPositionScorer.evaluate(player, open_cell, start, hostile_cell, 2, false, hostiles, grid, normal, context)
		check(carrier_score.firing == 0.0 and carrier_score.exposure < normal_score.exposure * 2.0, "Carrier avoids exposed firing positions more strongly than combat units")
		player.carried_unit = null
		var objective_score := AIPositionScorer.evaluate(player, open_cell, start, hostile_cell, 2, true, hostiles, grid, normal, context)
		check(objective_score.firing == 0.0 and objective_score.exposure < normal_score.exposure, "Objective travel favors protection over acquiring a firing lane")
		check(easy_score.exposure > normal_score.exposure and hard_score.exposure < normal_score.exposure, "Difficulty weights incoming exposure")
		check(easy_score.firing < normal_score.firing and hard_score.firing > normal_score.firing, "Difficulty weights firing opportunities")
		var more_progress := AIPositionScorer.evaluate(player, open_cell, start, hostile_cell, 3, false, hostiles, grid, normal, context)
		check(more_progress.progress > normal_score.progress, "Route progress increases position value")
		var delta := hostile_cell - open_cell
		var cover_cell := open_cell + (Vector3i(signi(delta.x), 0, 0) if absi(delta.x) >= absi(delta.z) else Vector3i(0, 0, signi(delta.z)))
		var cover_data := grid.get_cell_data(cover_cell)
		check(cover_data != null, "Found a tile toward the enemy for cover comparison")
		if cover_data:
			var original_cover := cover_data.cover_type
			cover_data.cover_type = MapCellData.CoverType.LOW
			var covered_score := AIPositionScorer.evaluate(player, open_cell, start, hostile_cell, 2, false, hostiles, grid, normal, context)
			check(covered_score.cover > normal_score.cover, "Directional cover increases position value")
			cover_data.cover_type = original_cover
		context.reserve_destination(ally, open_cell)
		check(AIPositionScorer.evaluate(player, open_cell, start, hostile_cell, 2, false, hostiles, grid, normal, context).total == -INF, "Teammate reservation rejects the exact destination")
	if adjacent_cell.x >= 0:
		var danger_score := AIPositionScorer.evaluate(player, adjacent_cell, start, hostile_cell, 0, false, hostiles, grid, normal, null)
		check(danger_score.danger < 0.0, "Close enemy positions receive a danger penalty")
	level.queue_free()
	await process_frame
	print("AI position scoring smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)
