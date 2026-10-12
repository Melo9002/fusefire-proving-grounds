extends SceneTree

var failures := 0

func _init() -> void:
	for dimensions in FlatMapGenerator.MAP_SIZES:
		for map_seed in range(12000, 12020):
			_check_map(dimensions, map_seed, false)
	for map_seed in range(22000, 22020):
		_check_map(Vector2i(40, 30), map_seed, true)
	print("Generated mission placement: 80 maps; %d failures" % failures)
	quit(1 if failures else 0)

func _check_map(dimensions: Vector2i, map_seed: int, refinery: bool) -> void:
	var data := FlatMapGenerator.generate_with_cover(dimensions.x, dimensions.y, 1.0, map_seed, 5, refinery)
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	MissionZonePlanner.populate_defaults(data, graph)
	var evaluator := MissionPlacementEvaluator.new(data, graph)
	var validation := MapValidator.validate(data, graph, {
		TacticalUnit.Faction.PLAYER: 5,
		TacticalUnit.Faction.ALLY: 5,
		TacticalUnit.Faction.ENEMY: 5,
	})
	check(validation.is_valid(), "Seed %d placement validates: %s" % [map_seed, validation.describe()])
	var used: Dictionary[Vector3i, bool] = {}
	for zone_id in [&"reach", &"terminal", &"extract", &"enemy_extract", &"rescue_spawn"]:
		var cells := data.get_objective_zone(zone_id)
		check(cells.size() == (1 if zone_id in [&"terminal", &"rescue_spawn"] else 4), "Seed %d creates the expected %s zone size" % [map_seed, zone_id])
		for position in cells:
			check(not used.has(position), "Seed %d keeps mission zones separate" % map_seed)
			used[position] = true
			check(not data.get_spawn_cells(TacticalUnit.Faction.PLAYER).has(position) and not data.get_spawn_cells(TacticalUnit.Faction.ENEMY).has(position), "Seed %d keeps mission placement out of deployments" % map_seed)
		if not cells.is_empty():
			match zone_id:
				&"reach": check(evaluator.is_reach_candidate(cells[0]), "Seed %d keeps Reach away from both deployments" % map_seed)
				&"terminal": check(evaluator.is_terminal_candidate(cells[0]), "Seed %d places Terminal on the hostile side of the battlefield" % map_seed)
				&"extract": check(evaluator.is_friendly_extract_candidate(cells[0]), "Seed %d keeps friendly extraction across the battlefield" % map_seed)
				&"enemy_extract": check(evaluator.is_enemy_extract_candidate(cells[0]), "Seed %d keeps enemy extraction across the battlefield" % map_seed)
	var rescue := MissionZonePlanner.find_rescue_cell(data)
	check(rescue.x >= 0 and not graph.calculate_3d_path(data.get_spawn_cells(TacticalUnit.Faction.PLAYER)[0], rescue).is_empty(), "Seed %d places a reachable rescue actor" % map_seed)

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
