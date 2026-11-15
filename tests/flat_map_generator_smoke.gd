extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	_check_data_generation()
	await _check_playable_generated_battle()
	print("Generated cover map smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_data_generation() -> void:
	var first := FlatMapGenerator.generate_with_cover(16, 12, 1.0, 4242, 5)
	var repeated := FlatMapGenerator.generate_with_cover(16, 12, 1.0, 4242, 5)
	var different := FlatMapGenerator.generate_with_cover(16, 12, 1.0, 4243, 5)
	check(first.cells.size() == 192 and first.map_size == Vector2i(16, 12), "Generator creates the requested flat dimensions")
	check(first.source_kind == "generated_cover" and first.generation_seed == 4242, "Generated MapData records its source and seed")
	check(first.get_spawn_cells(TacticalUnit.Faction.PLAYER) == repeated.get_spawn_cells(TacticalUnit.Faction.PLAYER), "The same seed reproduces player spawns")
	check(first.get_spawn_cells(TacticalUnit.Faction.ENEMY) == repeated.get_spawn_cells(TacticalUnit.Faction.ENEMY), "The same seed reproduces enemy spawns")
	check(first.get_spawn_cells(TacticalUnit.Faction.ALLY) == repeated.get_spawn_cells(TacticalUnit.Faction.ALLY), "The same seed reproduces ally spawns")
	var spawn_layout_changed := first.get_spawn_cells(TacticalUnit.Faction.PLAYER) != different.get_spawn_cells(TacticalUnit.Faction.PLAYER) \
		or first.get_spawn_cells(TacticalUnit.Faction.ENEMY) != different.get_spawn_cells(TacticalUnit.Faction.ENEMY)
	check(spawn_layout_changed, "A different seed changes the spawn layout")
	var first_signature := _cover_signature(first)
	check(first_signature == _cover_signature(repeated), "The same seed reproduces cover terrain")
	check(first_signature != _cover_signature(different), "A different seed changes cover terrain")
	var cover_counts := _cover_counts(first)
	check(cover_counts.x > 0 and cover_counts.y > 0, "Generated terrain contains both low and full cover")
	check(_cohesive_cover_count(first) >= floori(float(cover_counts.x + cover_counts.y) * 0.75), "Most generated cover belongs to a formation")
	check(_contains_cover_corner(first), "Generated terrain includes a tactical corner formation")
	for faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ALLY, TacticalUnit.Faction.ENEMY]:
		for spawn in first.get_spawn_cells(faction):
			check(first.get_cell(spawn).cover_type == MapCellData.CoverType.NONE, "Spawn bands stay clear of generated cover")
	var graph := Pathfinder.new()
	MapGraphBuilder.build(first, graph)
	var validation := MapValidator.validate(first, graph, {TacticalUnit.Faction.PLAYER: 5, TacticalUnit.Faction.ENEMY: 5})
	check(validation.is_valid(), "Generated data passes the shared map validator")
	check(graph.grid_to_id_map.size() == first.cells.size(), "Pathfinder is derived from every generated cell")

func _check_playable_generated_battle() -> void:
	var level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	# This suite deliberately protects the historical generator fixture.
	var config := BattleConfiguration.new()
	config.player_count = 5
	config.enemy_count = 5
	config.generated_map = true
	config.battle_seed = 4242
	config.select_battlefield(BattlefieldCatalog.GENERATED_COVER)
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.2).timeout
	var battle: BattleController = level.battle_controller
	var map_data: MapData = battle.grid_manager.map_data
	check(map_data.source_kind == "generated_cover" and map_data.generation_seed == 4242, "Battle uses generated MapData")
	check(map_data.cells.size() > 768 and not map_data.traversal_links.is_empty(), "Playable generated map includes elevated roof cells and access links")
	check(battle.last_map_validation.is_valid(), "Generated battle validates before unit registration")
	check(level.turn_manager.player_units.size() == 5 and level.turn_manager.enemy_units.size() == 5, "Generated spawn cells support 5v5")
	check(battle.grid_manager.occupancy_map.size() == 10, "Generated units occupy ten unique cells")
	var cover_counts := _cover_counts(map_data)
	var generated_geometry := level.get_node("GeneratedTerrain")
	var expected_structures := cover_counts.x + cover_counts.y - map_data.containers.size() * 5 - map_data.buildings.size() * 11
	expected_structures += map_data.platforms.size()
	expected_structures += map_data.hills.size()
	expected_structures += map_data.generated_traversals.size()
	for building in map_data.buildings:
		expected_structures -= building.stair_cells.size() + building.upper_cells.size()
	check(generated_geometry.get_child_count() == expected_structures, "Multi-cell structures render once per data record")
	for feature_node in level.get_tree().get_nodes_in_group("terrain_features"):
		check(not (feature_node as Node3D).visible, "%s is hidden on generated terrain" % feature_node.name)
	for unit in level.turn_manager.player_units:
		check(map_data.get_spawn_cells(TacticalUnit.Faction.PLAYER).has(unit.grid_position), "%s uses a generated player spawn" % unit.name)
	for unit in level.turn_manager.enemy_units:
		check(map_data.get_spawn_cells(TacticalUnit.Faction.ENEMY).has(unit.grid_position), "%s uses a generated enemy spawn" % unit.name)
	var route: PackedVector3Array = battle.pathfinder.calculate_3d_path(level.turn_manager.player_units[0].grid_position, level.turn_manager.enemy_units[0].grid_position)
	check(not route.is_empty(), "Opposing generated spawns share a playable route")
	level.turn_manager.end_current_turn()
	for tick in 200:
		if level.turn_manager.current_round >= 2:
			break
		await create_timer(0.1).timeout
	check(level.turn_manager.current_round >= 2, "Enemy AI completes a turn on generated pathfinding")
	check(battle.grid_manager.occupancy_map.size() == 10, "Generated movement preserves unique occupancy")

	level.queue_free()
	await process_frame

func _cover_signature(map_data: MapData) -> Array[String]:
	var signature: Array[String] = []
	for cell: MapCellData in map_data.cells.values():
		if cell.cover_type != MapCellData.CoverType.NONE:
			signature.append("%s:%d" % [cell.grid_position, cell.cover_type])
	signature.sort()
	return signature

func _cover_counts(map_data: MapData) -> Vector2i:
	var counts := Vector2i.ZERO
	for cell: MapCellData in map_data.cells.values():
		if cell.cover_type == MapCellData.CoverType.LOW:
			counts.x += 1
		elif cell.cover_type == MapCellData.CoverType.FULL:
			counts.y += 1
	return counts

func _cohesive_cover_count(map_data: MapData) -> int:
	var total := 0
	for cell: MapCellData in map_data.cells.values():
		if cell.cover_type == MapCellData.CoverType.NONE:
			continue
		for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var neighbor := map_data.get_cell(cell.grid_position + direction)
			if neighbor and neighbor.cover_type != MapCellData.CoverType.NONE:
				total += 1
				break
	return total

func _contains_cover_corner(map_data: MapData) -> bool:
	for cell: MapCellData in map_data.cells.values():
		if cell.cover_type == MapCellData.CoverType.NONE:
			continue
		var horizontal := false
		var vertical := false
		for direction in [Vector3i.LEFT, Vector3i.RIGHT]:
			var neighbor := map_data.get_cell(cell.grid_position + direction)
			horizontal = horizontal or (neighbor and neighbor.cover_type != MapCellData.CoverType.NONE)
		for direction in [Vector3i.FORWARD, Vector3i.BACK]:
			var neighbor := map_data.get_cell(cell.grid_position + direction)
			vertical = vertical or (neighbor and neighbor.cover_type != MapCellData.CoverType.NONE)
		if horizontal and vertical:
			return true
	return false
